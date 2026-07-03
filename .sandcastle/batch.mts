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
    `  gh issue edit ${prdNumber} --add-label code-review`,
  ].join('\n');
}
