// Sequential Reviewer — implement-then-review loop, in place
//
// Drives a two-phase workflow per issue, directly in the current checkout:
//   Phase 1 (Implement): An agent picks an open `ready-for-agent` issue,
//                        implements it test-first, and commits on the
//                        current branch.
//   Phase 2 (Review):    A second agent reviews the commits made in Phase 1
//                        and either approves them or amends the code.
//
// No worktree, no sandbox: agents run on the host with the `head` branch
// strategy, so commits land on the branch this checkout is already on.
// That is mandatory here, not a preference — FoldWiseVoice is a macOS
// AppKit Swift package (`platforms: [.macOS(.v14)]`) that cannot compile
// inside Sandcastle's Linux container sandbox. It also fits
// the Conductor workflow where each workspace is its own worktree: working
// in place puts results on the workspace branch instead of a throwaway
// `sandcastle/*` branch. Nothing is ever pushed and no PR is opened — the
// human gate is preserved.
//
// The outer loop repeats up to maxIterations times, processing one issue
// per iteration and stopping early once the backlog is exhausted (an
// implement phase that produces no commits, or a scoped queue that drains).
//
// This file is deliberately a thin I/O shell: every side-effect-free
// decision (argument parsing, queue resolution, the jq filter, the
// empty-queue explainer) lives in `batch.mts`, where it is unit-tested.
//
// Usage (from the repo root — Sandcastle resolves prompt files and git
// against process.cwd()):
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts <maxIterations> [prdNumber]
// e.g. a single implement→review cycle over the ready-for-agent queue:
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts 1
// or a run scoped to PRD #31's released sub-issues:
//   .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts 5 31

import { execFileSync, execSync } from 'node:child_process';
import * as sandcastle from '@ai-hero/sandcastle';
import { noSandbox } from '@ai-hero/sandcastle/sandboxes/no-sandbox';
import {
  explainEmptyScopedQueue,
  openSliceNumbers,
  resolveLaunchMode,
  sliceNumbersFilter,
  type SubIssue,
} from './batch.mts';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const USAGE = `Usage (from the repo root):
  .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts <maxIterations> [prdNumber]

<maxIterations> is the maximum number of implement→review cycles; each
cycle works on one open ready-for-agent issue. For example, a single cycle
over the whole ready-for-agent queue:
  .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts 1

[prdNumber] scopes the run to that PRD's open ready-for-agent sub-issues.
For example, up to five cycles over PRD #31's released slices:
  .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts 5 31`;

const mode = resolveLaunchMode(process.argv.slice(2));
if (mode.kind === 'invalid') {
  console.error(USAGE);
  process.exit(1);
}

// ---------------------------------------------------------------------------
// GitHub I/O
// ---------------------------------------------------------------------------

/** The PRD's native GitHub sub-issues, flattened for `batch.mts`. */
function fetchSubIssues(prdNumber: number): SubIssue[] {
  const query = `query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      issue(number: $number) {
        subIssues(first: 100) {
          nodes { number state labels(first: 20) { nodes { name } } }
        }
      }
    }
  }`;
  const response = JSON.parse(
    execFileSync(
      'gh',
      [
        'api',
        'graphql',
        '-F',
        'owner={owner}',
        '-F',
        'name={repo}',
        '-F',
        `number=${prdNumber}`,
        '-f',
        `query=${query}`,
      ],
      { encoding: 'utf8' },
    ),
  );
  type LabelNode = { name: string };
  type SubIssueNode = { number: number; state: SubIssue['state']; labels: { nodes: LabelNode[] } };
  const nodes: SubIssueNode[] = response.data.repository.issue.subIssues.nodes;
  return nodes.map((node) => ({
    number: node.number,
    state: node.state,
    labels: node.labels.nodes.map((label) => label.name),
  }));
}

console.log(
  mode.kind === 'scoped'
    ? `Scope: PRD #${mode.prdNumber} (open ready-for-agent sub-issues)`
    : 'Scope: whole ready-for-agent queue',
);

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

for (let iteration = 1; iteration <= mode.maxIterations; iteration++) {
  console.log(`\n=== Iteration ${iteration}/${mode.maxIterations} ===\n`);

  // The jq fragment narrowing the implementer's issue query. For a scoped
  // run the queue is re-resolved every iteration, so slices closed by
  // earlier iterations drop out automatically. An empty queue on the first
  // iteration is a misconfigured launch (abort, non-zero); later it means
  // the batch drained (or was descoped) mid-run — either way the explainer
  // states the actual reason.
  let sliceFilter: string;
  if (mode.kind === 'scoped') {
    const subIssues = fetchSubIssues(mode.prdNumber);
    const queue = openSliceNumbers(subIssues);
    if (queue.length === 0) {
      const explanation = explainEmptyScopedQueue(subIssues, mode.prdNumber);
      if (iteration === 1) {
        console.error(explanation);
        process.exit(1);
      }
      console.log(`${explanation}\n\nStopping.`);
      break;
    }
    console.log(`Queue for PRD #${mode.prdNumber}: ${queue.map((n) => `#${n}`).join(', ')}`);
    sliceFilter = sliceNumbersFilter(queue);
  } else {
    sliceFilter = sliceNumbersFilter(undefined);
  }

  // Tip of the current branch before the implementer runs — the reviewer
  // diffs against this, so each review covers exactly one iteration's work.
  const base = execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();

  // ---------------------------------------------------------------------------
  // Phase 1: Implement
  //
  // The agent picks the next open issue, implements it (using RGR: write a
  // failing test first, then make it pass), runs the Swift verification
  // suite, and commits the result on the current branch.
  // ---------------------------------------------------------------------------
  // maxIterations: 1 so each outer pass implements a single issue, then
  // hands it to the reviewer. A higher value would let the agent drain
  // several issues in one pass, which defeats the per-issue review.
  const implement = await sandcastle.run({
    name: 'implementer',
    maxIterations: 1,
    agent: sandcastle.claudeCode('claude-fable-5', { effort: 'xhigh' }),
    sandbox: noSandbox(),
    branchStrategy: { type: 'head' },
    promptFile: './.sandcastle/implement-prompt.md',
    promptArgs: {
      SLICE_FILTER: sliceFilter,
    },
  });

  if (!implement.commits.length) {
    // No commits means the backlog is empty or every remaining issue is
    // blocked — there is nothing left to implement or review, so stop.
    console.log('Implementation agent made no commits. Stopping.');
    break;
  }

  console.log(`\nImplementation complete on branch: ${implement.branch}`);
  console.log(`Commits: ${implement.commits.length}`);

  // ---------------------------------------------------------------------------
  // Phase 2: Review
  //
  // A second agent reviews everything committed since {{BASE}} — exactly
  // this iteration's work — and either approves or amends it in place.
  // ---------------------------------------------------------------------------
  await sandcastle.run({
    name: 'reviewer',
    maxIterations: 1,
    agent: sandcastle.claudeCode('claude-fable-5'),
    sandbox: noSandbox(),
    branchStrategy: { type: 'head' },
    promptFile: './.sandcastle/review-prompt.md',
    promptArgs: {
      BASE: base,
    },
  });

  console.log('\nReview complete.');
}

console.log('\nAll done.');
