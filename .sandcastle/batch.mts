// Pure decision logic for the Sandcastle batch runner.
//
// Every side-effect-free decision the runner makes lives here so it can be
// unit-tested: argument parsing, sub-issue → queue resolution, the jq
// selection fragment, and the empty-queue explainer. `main.mts` stays a thin
// I/O shell over this module — it fetches data with `gh`/`git`, feeds it
// through these functions, and acts on the returned values.

/**
 * A PRD's native GitHub sub-issue, as flattened from the GraphQL response.
 * Queue decisions work off state and labels only — never issue bodies (a
 * body regex drifts with free text and fails silently).
 */
export type SubIssue = {
  number: number;
  state: 'OPEN' | 'CLOSED';
  labels: string[];
};

/**
 * The release gate: a slice joins the batch queue only once the maintainer
 * labels it `ready-for-agent`. This reuses the repo's existing triage label
 * rather than adding a Sandcastle-specific one.
 */
export const RELEASE_GATE_LABEL = 'ready-for-agent';

/**
 * The handoff label: a drained PRD batch gets this, marking it as waiting
 * for the maintainer's code review and manual PR.
 */
export const HANDOFF_LABEL = 'code-review';

export type LaunchMode =
  | { kind: 'whole-queue'; maxIterations: number }
  | { kind: 'scoped'; maxIterations: number; prdNumber: number }
  | { kind: 'invalid' };

const positiveInteger = (raw: string): number | undefined =>
  /^[1-9]\d*$/.test(raw) ? Number(raw) : undefined;

/**
 * Parse CLI arguments into a launch mode: a lone iteration count runs the
 * whole `ready-for-agent` queue, a second argument scopes the run to that
 * PRD's sub-issues, and anything else is invalid.
 */
export function resolveLaunchMode(args: string[]): LaunchMode {
  if (args.length < 1 || args.length > 2) return { kind: 'invalid' };

  const maxIterations = positiveInteger(args[0]);
  if (maxIterations === undefined) return { kind: 'invalid' };

  if (args.length === 1) return { kind: 'whole-queue', maxIterations };

  const prdNumber = positiveInteger(args[1]);
  if (prdNumber === undefined) return { kind: 'invalid' };

  return { kind: 'scoped', maxIterations, prdNumber };
}

/**
 * A jq fragment spliced into the implement prompt's issue query
 * (`[.[] | <fragment> | {...}]`) to narrow it to the scoped queue.
 * `undefined` means unscoped — the whole-queue identity pass-through.
 */
export function sliceNumbersFilter(numbers: number[] | undefined): string {
  if (numbers === undefined) return '.';
  if (numbers.length === 0) return 'select(false)';
  return `select(.number | IN(${numbers.join(', ')}))`;
}

/** Sub-issues that have passed the release gate, regardless of state. */
export function releasedSlices(subIssues: SubIssue[]): SubIssue[] {
  return subIssues.filter((issue) => issue.labels.includes(RELEASE_GATE_LABEL));
}

/**
 * The scoped run's queue: numbers of the PRD's released slices that are
 * still open. Re-resolved every iteration, so closed slices drop out.
 */
export function openSliceNumbers(subIssues: SubIssue[]): number[] {
  return releasedSlices(subIssues)
    .filter((issue) => issue.state === 'OPEN')
    .map((issue) => issue.number);
}

/**
 * Why a scoped run has nothing to do, with a copy-pasteable fix. Call only
 * when `openSliceNumbers` came back empty; the three cases are exhaustive
 * given that.
 */
export function explainEmptyScopedQueue(subIssues: SubIssue[], prdNumber: number): string {
  if (subIssues.length === 0) {
    return [
      `PRD #${prdNumber} has no sub-issues.`,
      'Break the PRD into slices and attach them as native GitHub sub-issues:',
      `  gh issue view ${prdNumber} --web`,
    ].join('\n');
  }

  const released = releasedSlices(subIssues);
  if (released.length === 0) {
    const open = subIssues.filter((issue) => issue.state === 'OPEN');
    const fix =
      open.length > 0
        ? [
            'Release the slices that are ready:',
            ...open.map(
              (issue) => `  gh issue edit ${issue.number} --add-label ${RELEASE_GATE_LABEL}`,
            ),
          ]
        : [
            'All of them are closed. Reopen and release a slice, or add new sub-issues:',
            `  gh issue view ${prdNumber} --web`,
          ];
    return [
      `PRD #${prdNumber} has sub-issues, but none are released — no sub-issue carries the \`${RELEASE_GATE_LABEL}\` label.`,
      ...fix,
    ].join('\n');
  }

  return [
    `Every released slice of PRD #${prdNumber} is already closed — the batch is drained.`,
    'Hand the PRD off for review:',
    `  gh issue edit ${prdNumber} --add-label ${HANDOFF_LABEL}`,
  ].join('\n');
}

/** A commit made by one of this run's implement phases. */
export type Commit = {
  sha: string;
  message: string;
};

/**
 * Why the outer loop stopped without draining its queue — the stall
 * report's enumerated reasons. A drained queue is not a stop reason: it
 * always yields a `complete` handoff, which ignores this value.
 */
export type StopReason = 'no-commits' | 'iteration-cap';

/** How a scoped run hands its batch back: the label decision + comment. */
export type Handoff = { kind: 'complete' | 'stalled'; comment: string };

/**
 * Attribute this run's implement commits to slices. The sole signal is the
 * commit contract's `Closes #<n>` line — anchored to line start and matched
 * case-insensitively, as GitHub does — so prose mentions never attribute,
 * and review amendments (which carry no such line) never attribute either.
 */
export function commitShasByIssue(commits: Commit[]): Map<number, string[]> {
  const byIssue = new Map<number, string[]>();
  for (const commit of commits) {
    for (const match of commit.message.matchAll(/^closes #(\d+)/gim)) {
      const issue = Number(match[1]);
      byIssue.set(issue, [...(byIssue.get(issue) ?? []), commit.sha]);
    }
  }
  return byIssue;
}

/**
 * Decide how a scoped run hands its batch back to the human: `complete`
 * (every released slice closed — label the PRD and post the summary) or
 * `stalled` (open slices remain — post the report, no label). Whole-queue
 * runs never call this; they have no PRD to hand off.
 */
export function decideHandoff(args: {
  prdNumber: number;
  subIssues: SubIssue[];
  commits: Commit[];
  stopReason: StopReason;
}): Handoff {
  const { prdNumber, subIssues, commits, stopReason } = args;
  const released = releasedSlices(subIssues);
  const shasByIssue = commitShasByIssue(commits);

  const sliceLine = (issue: SubIssue): string => {
    const shas = shasByIssue.get(issue.number) ?? [];
    if (shas.length === 0) return `- #${issue.number}: no commit attributed this run`;
    const list = shas.map((sha) => `\`${sha.slice(0, 7)}\``).join(', ');
    return shas.length > 1
      ? `- #${issue.number}: ${list} (bounced and retried)`
      : `- #${issue.number}: ${list}`;
  };

  const stillOpen = released.filter((issue) => issue.state === 'OPEN');
  if (stillOpen.length === 0) {
    return {
      kind: 'complete',
      comment: [
        `Sandcastle batch complete — every released slice of PRD #${prdNumber} is closed.`,
        '',
        ...released.map(sliceLine),
        '',
        'Nothing was pushed — review the workspace branch and open the PR manually.',
      ].join('\n'),
    };
  }

  const reason: Record<StopReason, string> = {
    'iteration-cap': 'iteration cap reached before the queue drained',
    'no-commits': 'the implementer made no commits (remaining slices blocked or unactionable)',
  };
  const closedThisRun = released.filter(
    (issue) => issue.state === 'CLOSED' && shasByIssue.has(issue.number),
  );
  return {
    kind: 'stalled',
    comment: [
      `Sandcastle batch stalled — released slices of PRD #${prdNumber} still open: ${stillOpen
        .map((issue) => `#${issue.number}`)
        .join(', ')}.`,
      '',
      `Stop reason: ${reason[stopReason]}.`,
      ...(closedThisRun.length > 0
        ? ['', 'Closed this run:', ...closedThisRun.map(sliceLine)]
        : []),
    ].join('\n'),
  };
}
