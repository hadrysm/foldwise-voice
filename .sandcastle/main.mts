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
// With no arguments on a TTY (the Conductor run-button case), an
// interactive picker offers the open PRDs, the whole queue, and manual
// PRD entry, then suggests an iteration cap.

import { execFileSync, execSync } from 'node:child_process';
import * as readline from 'node:readline/promises';
import * as sandcastle from '@ai-hero/sandcastle';
import { noSandbox } from '@ai-hero/sandcastle/sandboxes/no-sandbox';
import {
  HANDOFF_LABEL,
  RELEASE_GATE_LABEL,
  decideHandoff,
  explainEmptyScopedQueue,
  openSliceNumbers,
  parseIssueNumber,
  pickerMenu,
  resolveIterationCap,
  resolveLaunchMode,
  resolvePickerChoice,
  sliceNumbersFilter,
  suggestedIterationCap,
  type Commit,
  type LaunchMode,
  type PickerChoice,
  type PickerPrd,
  type StopReason,
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
  .sandcastle/node_modules/.bin/tsx .sandcastle/main.mts 5 31

With no arguments on a TTY, an interactive picker chooses the batch and
the iteration cap. Without a TTY, arguments are required.`;

const parsed = resolveLaunchMode(process.argv.slice(2), process.stdin.isTTY === true);
if (parsed.kind === 'invalid') {
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

/** Open issues carrying `label`, with the given `--json` fields. */
function listOpenIssues<T>(label: string, fields: string): T[] {
  return JSON.parse(
    execFileSync(
      'gh',
      ['issue', 'list', '--state', 'open', '--label', label, '--limit', '100', '--json', fields],
      { encoding: 'utf8' },
    ),
  );
}

/** The open PRDs (label `prd`) offered as picker rows. */
const fetchOpenPrds = (): PickerPrd[] => listOpenIssues('prd', 'number,title');

/** How many issues the whole-queue run would draw from. */
const countReadyForAgentIssues = (): number =>
  listOpenIssues(RELEASE_GATE_LABEL, 'number').length;

// ---------------------------------------------------------------------------
// Interactive batch picker
//
// The Conductor run-button path: no arguments, a TTY. Every prompt
// re-asks until the answer parses — the parsing itself lives in
// `batch.mts`, where it is unit-tested; this function only does I/O.
// ---------------------------------------------------------------------------

type RunMode = Extract<LaunchMode, { maxIterations: number }>;

/** Ask until the answer parses; the parsers live (tested) in `batch.mts`. */
async function askUntil<T>(
  rl: readline.Interface,
  prompt: string,
  parse: (input: string) => T | undefined,
  hint: string,
): Promise<T> {
  for (;;) {
    const answer = parse(await rl.question(prompt));
    if (answer !== undefined) return answer;
    console.log(hint);
  }
}

async function pickBatch(): Promise<RunMode> {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const prds = fetchOpenPrds();
    console.log('Pick a batch:');
    for (const line of pickerMenu(prds)) console.log(line);

    const choice: PickerChoice = await askUntil(
      rl,
      'Batch: ',
      (input) => resolvePickerChoice(input, prds),
      'Enter one of the row numbers above.',
    );

    let prdNumber: number | undefined;
    if (choice.kind === 'prd') prdNumber = choice.prdNumber;
    if (choice.kind === 'manual-prd') {
      prdNumber = await askUntil(
        rl,
        'PRD number: ',
        parseIssueNumber,
        'Enter a positive issue number, e.g. 31.',
      );
    }

    const openSliceCount =
      prdNumber === undefined
        ? countReadyForAgentIssues()
        : openSliceNumbers(fetchSubIssues(prdNumber)).length;
    const suggested = suggestedIterationCap(openSliceCount);
    console.log(
      `${openSliceCount} open slice(s) in the queue — suggesting ${suggested} iterations` +
        ' (one cycle per slice plus slack for reviewer bounces).',
    );

    const maxIterations = await askUntil(
      rl,
      `Max iterations [${suggested}]: `,
      (input) => resolveIterationCap(input, suggested),
      'Enter a positive number, or leave empty to accept.',
    );

    return prdNumber === undefined
      ? { kind: 'whole-queue', maxIterations }
      : { kind: 'scoped', maxIterations, prdNumber };
  } finally {
    rl.close();
  }
}

/** Ctrl+D at a picker prompt aborts the launch, not the stack trace. */
async function pickBatchOrAbort(): Promise<RunMode> {
  try {
    return await pickBatch();
  } catch (error) {
    if ((error as { code?: string }).code === 'ABORT_ERR') {
      console.error('\nPicker aborted — nothing was run.');
      process.exit(1);
    }
    throw error;
  }
}

const mode: RunMode = parsed.kind === 'interactive' ? await pickBatchOrAbort() : parsed;

/** Tip of the current branch. */
const gitHead = (): string => execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();

/**
 * The commits in `base..head`, oldest first, for `Closes #<n>` attribution.
 * Called on the range an implement phase just produced, so review
 * amendments (made later) never enter the attribution pool.
 */
function commitsInRange(base: string, head: string): Commit[] {
  const raw = execFileSync(
    'git',
    ['log', '-z', '--reverse', '--format=%H%n%B', `${base}..${head}`],
    { encoding: 'utf8' },
  );
  return raw
    .split('\0')
    .filter((entry) => entry.length > 0)
    .map((entry) => {
      const firstNewline = entry.indexOf('\n');
      return { sha: entry.slice(0, firstNewline), message: entry.slice(firstNewline + 1) };
    });
}

console.log(
  mode.kind === 'scoped'
    ? `Scope: PRD #${mode.prdNumber} (open ready-for-agent sub-issues)`
    : 'Scope: whole ready-for-agent queue',
);

// ---------------------------------------------------------------------------
// Main loop
// ---------------------------------------------------------------------------

// Implement commits accumulated across iterations, and why the loop
// stopped — together they decide the end-of-run handoff. `iteration-cap`
// holds unless a break says otherwise.
const runCommits: Commit[] = [];
let stopReason: StopReason = 'iteration-cap';

for (let iteration = 1; iteration <= mode.maxIterations; iteration++) {
  console.log(`\n=== Iteration ${iteration}/${mode.maxIterations} ===\n`);

  // The jq fragment narrowing the implementer's issue query. For a scoped
  // run the queue is re-resolved every iteration, so slices closed by
  // earlier iterations drop out automatically. An empty queue on the first
  // iteration is a misconfigured launch (abort, non-zero, with the
  // explainer's copy-pasteable fix); later it means the batch drained (or
  // was descoped) mid-run, which the end-of-run handoff reports and labels
  // — no manual fix to print. The stop reason is never read on that path:
  // no released slice is open, so decideHandoff lands on `complete`.
  let sliceFilter: string;
  if (mode.kind === 'scoped') {
    const subIssues = fetchSubIssues(mode.prdNumber);
    const queue = openSliceNumbers(subIssues);
    if (queue.length === 0) {
      if (iteration === 1) {
        console.error(explainEmptyScopedQueue(subIssues, mode.prdNumber));
        process.exit(1);
      }
      console.log(`Scoped queue for PRD #${mode.prdNumber} is empty — stopping.`);
      break;
    }
    console.log(`Queue for PRD #${mode.prdNumber}: ${queue.map((n) => `#${n}`).join(', ')}`);
    sliceFilter = sliceNumbersFilter(queue);
  } else {
    sliceFilter = sliceNumbersFilter(undefined);
  }

  // Tip of the current branch before the implementer runs — the reviewer
  // diffs against this, so each review covers exactly one iteration's work.
  const base = gitHead();

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
    stopReason = 'no-commits';
    break;
  }

  // Snapshot the implement phase's commits now, before the reviewer runs,
  // so its amendments stay out of the slice attribution.
  runCommits.push(...commitsInRange(base, gitHead()));

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

// ---------------------------------------------------------------------------
// Handoff
//
// A scoped run ends by handing the batch back to the human on GitHub: a
// drained PRD gets the handoff label plus a per-slice summary, a stalled
// one gets a report of what remains and why the run stopped. Whole-queue
// runs have no PRD to hand off. Nothing is pushed either way.
// ---------------------------------------------------------------------------

if (mode.kind === 'scoped') {
  const handoff = decideHandoff({
    prdNumber: mode.prdNumber,
    subIssues: fetchSubIssues(mode.prdNumber),
    commits: runCommits,
    stopReason,
  });
  const complete = handoff.kind === 'complete';
  if (complete) {
    execFileSync('gh', ['issue', 'edit', String(mode.prdNumber), '--add-label', HANDOFF_LABEL]);
  }
  execFileSync('gh', ['issue', 'comment', String(mode.prdNumber), '--body', handoff.comment]);
  console.log(
    complete
      ? `\nBatch drained — labeled PRD #${mode.prdNumber} \`${HANDOFF_LABEL}\` and posted the summary.`
      : `\nBatch stalled — posted the stall report on PRD #${mode.prdNumber}.`,
  );
}

console.log('\nAll done.');
