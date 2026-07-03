import { execFileSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';
import {
  commitShasByIssue,
  decideHandoff,
  explainEmptyScopedQueue,
  openSliceNumbers,
  releasedSlices,
  resolveLaunchMode,
  sliceNumbersFilter,
  type Commit,
  type SubIssue,
} from '../batch.mts';

const slice = (number: number, state: SubIssue['state'], labels: string[]): SubIssue => ({
  number,
  state,
  labels,
});

const commit = (sha: string, message: string): Commit => ({ sha, message });

describe('resolveLaunchMode', () => {
  it('runs the whole queue when given a lone iteration count', () => {
    expect(resolveLaunchMode(['3'])).toEqual({
      kind: 'whole-queue',
      maxIterations: 3,
    });
  });

  it('scopes to a PRD when given an iteration count and a PRD number', () => {
    expect(resolveLaunchMode(['3', '31'])).toEqual({
      kind: 'scoped',
      maxIterations: 3,
      prdNumber: 31,
    });
  });

  it.each([
    { args: [], why: 'no arguments' },
    { args: ['0'], why: 'zero iterations' },
    { args: ['-1'], why: 'negative iterations' },
    { args: ['abc'], why: 'non-numeric iteration count' },
    { args: ['1.5'], why: 'fractional iteration count' },
    { args: ['3', '0'], why: 'zero PRD number' },
    { args: ['3', 'abc'], why: 'non-numeric PRD number' },
    { args: ['1', '2', '3'], why: 'too many arguments' },
  ])('rejects $why', ({ args }) => {
    expect(resolveLaunchMode(args)).toEqual({ kind: 'invalid' });
  });
});

describe('releasedSlices', () => {
  it('keeps only sub-issues carrying the ready-for-agent release gate', () => {
    const released = releasedSlices([
      slice(32, 'CLOSED', ['ready-for-agent']),
      slice(34, 'OPEN', []),
      slice(35, 'OPEN', ['ready-for-agent', 'prd']),
    ]);
    expect(released.map((s) => s.number)).toEqual([32, 35]);
  });
});

describe('openSliceNumbers', () => {
  it('returns the numbers of open released slices only', () => {
    const queue = openSliceNumbers([
      slice(32, 'CLOSED', ['ready-for-agent']),
      slice(34, 'OPEN', []),
      slice(35, 'OPEN', ['ready-for-agent']),
      slice(36, 'OPEN', ['ready-for-agent']),
    ]);
    expect(queue).toEqual([35, 36]);
  });

  it('returns an empty queue once every released slice is closed', () => {
    const queue = openSliceNumbers([
      slice(32, 'CLOSED', ['ready-for-agent']),
      slice(33, 'CLOSED', ['ready-for-agent']),
    ]);
    expect(queue).toEqual([]);
  });
});

describe('sliceNumbersFilter', () => {
  // The fragment is spliced into the implement prompt's issue query:
  //   [.[] | <fragment> | {number}]
  // Run it through the real jq binary (the same engine `gh` embeds) so a
  // syntax error is caught where a string assertion could not.
  const selectedNumbers = (fragment: string, issues: { number: number }[]): number[] =>
    JSON.parse(
      execFileSync('jq', ['-c', `[.[] | ${fragment} | .number]`], {
        input: JSON.stringify(issues),
        encoding: 'utf8',
      }),
    );

  const fixture = [{ number: 34 }, { number: 35 }, { number: 36 }];

  it('selects exactly the listed slice numbers', () => {
    expect(selectedNumbers(sliceNumbersFilter([35, 36]), fixture)).toEqual([35, 36]);
  });

  it('selects nothing when the queue is empty', () => {
    expect(selectedNumbers(sliceNumbersFilter([]), fixture)).toEqual([]);
  });

  it('passes everything through for the whole-queue run', () => {
    expect(selectedNumbers(sliceNumbersFilter(undefined), fixture)).toEqual([34, 35, 36]);
  });
});

describe('commitShasByIssue', () => {
  it('attributes a commit to the slice named on its Closes line', () => {
    const byIssue = commitShasByIssue([
      commit('abc1234def', 'RALPH: implement the picker\n\nCloses #36'),
    ]);
    expect(byIssue.get(36)).toEqual(['abc1234def']);
  });

  it('collects every commit for a bounced-and-retried slice in order', () => {
    const byIssue = commitShasByIssue([
      commit('abc1234def', 'RALPH: first attempt\n\nCloses #36'),
      commit('def5678abc', 'RALPH: address the bounce\n\nCloses #36'),
    ]);
    expect(byIssue.get(36)).toEqual(['abc1234def', 'def5678abc']);
  });

  it('matches the Closes keyword case-insensitively, as GitHub does', () => {
    const byIssue = commitShasByIssue([commit('abc1234def', 'RALPH: fix\n\ncloses #34')]);
    expect(byIssue.get(34)).toEqual(['abc1234def']);
  });

  it('ignores a mid-line prose mention of closing an issue', () => {
    const byIssue = commitShasByIssue([
      commit('abc1234def', 'RALPH: fix\n\nThis probably also closes #7 as a side effect.'),
    ]);
    expect(byIssue.size).toBe(0);
  });

  it('does not attribute commits without a Closes line, such as review amendments', () => {
    const byIssue = commitShasByIssue([commit('abc1234def', 'RALPH: review fixes for #36')]);
    expect(byIssue.size).toBe(0);
  });
});

describe('decideHandoff', () => {
  const drained = [
    slice(32, 'CLOSED', ['ready-for-agent']),
    slice(36, 'CLOSED', ['ready-for-agent']),
  ];
  const drainedCommits = [
    commit('abc1234def', 'RALPH: one\n\nCloses #32'),
    commit('def5678abc', 'RALPH: two\n\nCloses #36'),
  ];

  it('completes when every released slice is closed', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: drained,
      commits: drainedCommits,
      stopReason: 'iteration-cap',
    });
    expect(handoff.kind).toBe('complete');
  });

  it('summarizes each slice with its short commit SHAs', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: drained,
      commits: drainedCommits,
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('#32: `abc1234`');
  });

  it('marks a slice with several implement commits as bounced and retried', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(36, 'CLOSED', ['ready-for-agent'])],
      commits: [
        commit('abc1234def', 'RALPH: first attempt\n\nCloses #36'),
        commit('def5678abc', 'RALPH: address the bounce\n\nCloses #36'),
      ],
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('#36: `abc1234`, `def5678` (bounced and retried)');
  });

  it('notes a closed released slice with no commit attributed this run', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(32, 'CLOSED', ['ready-for-agent'])],
      commits: [],
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('#32: no commit attributed this run');
  });

  it('ignores unreleased sub-issues when deciding completion', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(32, 'CLOSED', ['ready-for-agent']), slice(34, 'OPEN', [])],
      commits: drainedCommits,
      stopReason: 'iteration-cap',
    });
    expect(handoff.kind).toBe('complete');
  });

  it('stalls when a released slice is still open', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(36, 'OPEN', ['ready-for-agent'])],
      commits: [],
      stopReason: 'iteration-cap',
    });
    expect(handoff.kind).toBe('stalled');
  });

  it('lists the remaining open slices in the stall report', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [
        slice(36, 'OPEN', ['ready-for-agent']),
        slice(38, 'OPEN', ['ready-for-agent']),
      ],
      commits: [],
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('#36, #38');
  });

  it('states that the iteration cap stopped the run', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(36, 'OPEN', ['ready-for-agent'])],
      commits: [],
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('iteration cap reached');
  });

  it('states that the implementer made no commits when that stopped the run', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [slice(36, 'OPEN', ['ready-for-agent'])],
      commits: [],
      stopReason: 'no-commits',
    });
    expect(handoff.comment).toContain('implementer made no commits');
  });

  it('reports progress made before the stall, slice by slice', () => {
    const handoff = decideHandoff({
      prdNumber: 31,
      subIssues: [
        slice(32, 'CLOSED', ['ready-for-agent']),
        slice(36, 'OPEN', ['ready-for-agent']),
      ],
      commits: [commit('abc1234def', 'RALPH: one\n\nCloses #32')],
      stopReason: 'iteration-cap',
    });
    expect(handoff.comment).toContain('#32: `abc1234`');
  });
});

describe('explainEmptyScopedQueue', () => {
  it('explains a PRD with no sub-issues and points at the PRD to fix it', () => {
    const explanation = explainEmptyScopedQueue([], 31);
    expect(explanation).toContain('PRD #31 has no sub-issues');
    expect(explanation).toContain('gh issue view 31 --web');
  });

  it('explains unreleased sub-issues with the exact release command', () => {
    const explanation = explainEmptyScopedQueue(
      [slice(34, 'OPEN', []), slice(35, 'OPEN', ['needs-info'])],
      31,
    );
    expect(explanation).toContain('none are released');
    expect(explanation).toContain('gh issue edit 34 --add-label ready-for-agent');
    expect(explanation).toContain('gh issue edit 35 --add-label ready-for-agent');
  });

  it('still gives a fix command when every unreleased sub-issue is closed', () => {
    const explanation = explainEmptyScopedQueue([slice(34, 'CLOSED', [])], 31);
    expect(explanation).toContain('none are released');
    expect(explanation).toContain('gh issue view 31 --web');
  });

  it('explains a drained batch with the manual handoff command', () => {
    const explanation = explainEmptyScopedQueue(
      [slice(32, 'CLOSED', ['ready-for-agent']), slice(34, 'OPEN', [])],
      31,
    );
    expect(explanation).toContain('already closed');
    expect(explanation).toContain('gh issue edit 31 --add-label code-review');
  });
});
