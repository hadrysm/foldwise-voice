import { execFileSync } from 'node:child_process';
import { describe, expect, it } from 'vitest';
import {
  commitShasByIssue,
  decideHandoff,
  explainEmptyScopedQueue,
  openSliceNumbers,
  parseIssueNumber,
  pickerMenu,
  resolveIterationCap,
  releasedSlices,
  resolveLaunchMode,
  resolvePickerChoice,
  sliceNumbersFilter,
  suggestedIterationCap,
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
    expect(resolveLaunchMode(['3'], false)).toEqual({
      kind: 'whole-queue',
      maxIterations: 3,
    });
  });

  it('scopes to a PRD when given an iteration count and a PRD number', () => {
    expect(resolveLaunchMode(['3', '31'], false)).toEqual({
      kind: 'scoped',
      maxIterations: 3,
      prdNumber: 31,
    });
  });

  it('opens the interactive picker when launched with no arguments on a TTY', () => {
    expect(resolveLaunchMode([], true)).toEqual({ kind: 'interactive' });
  });

  it('rejects a no-argument launch without a TTY, so automations fail loudly', () => {
    expect(resolveLaunchMode([], false)).toEqual({ kind: 'invalid' });
  });

  it('bypasses the picker when explicit arguments are given on a TTY', () => {
    expect(resolveLaunchMode(['3', '31'], true)).toEqual({
      kind: 'scoped',
      maxIterations: 3,
      prdNumber: 31,
    });
  });

  it.each([
    { args: ['0'], why: 'zero iterations' },
    { args: ['-1'], why: 'negative iterations' },
    { args: ['abc'], why: 'non-numeric iteration count' },
    { args: ['1.5'], why: 'fractional iteration count' },
    { args: ['3', '0'], why: 'zero PRD number' },
    { args: ['3', 'abc'], why: 'non-numeric PRD number' },
    { args: ['1', '2', '3'], why: 'too many arguments' },
  ])('rejects $why', ({ args }) => {
    expect(resolveLaunchMode(args, true)).toEqual({ kind: 'invalid' });
  });
});

describe('pickerMenu', () => {
  it('lists the open PRDs first, then the queue and manual-entry escape hatches', () => {
    const menu = pickerMenu([
      { number: 31, title: 'Sandcastle sequential-reviewer workflow' },
      { number: 40, title: 'Another feature' },
    ]);
    expect(menu).toEqual([
      '  1) PRD #31 — Sandcastle sequential-reviewer workflow',
      '  2) PRD #40 — Another feature',
      '  3) Whole ready-for-agent queue',
      '  4) Enter a PRD number manually',
    ]);
  });

  it('keeps the escape hatches when no PRD is open', () => {
    expect(pickerMenu([])).toEqual([
      '  1) Whole ready-for-agent queue',
      '  2) Enter a PRD number manually',
    ]);
  });

  it('resolves every rendered row number to a choice', () => {
    const prds = [{ number: 31, title: 'A' }];
    const choices = pickerMenu(prds).map((_, index) =>
      resolvePickerChoice(String(index + 1), prds),
    );
    expect(choices).not.toContain(undefined);
  });
});

describe('resolvePickerChoice', () => {
  const prds = [
    { number: 31, title: 'Sandcastle sequential-reviewer workflow' },
    { number: 40, title: 'Another feature' },
  ];

  it('maps a PRD row to that PRD', () => {
    expect(resolvePickerChoice('2', prds)).toEqual({ kind: 'prd', prdNumber: 40 });
  });

  it('maps the row after the PRDs to the whole ready-for-agent queue', () => {
    expect(resolvePickerChoice('3', prds)).toEqual({ kind: 'whole-queue' });
  });

  it('maps the last row to manual PRD entry', () => {
    expect(resolvePickerChoice('4', prds)).toEqual({ kind: 'manual-prd' });
  });

  it.each([
    { input: '1', choice: { kind: 'whole-queue' } },
    { input: '2', choice: { kind: 'manual-prd' } },
  ])('offers escape hatch row $input even when no PRD is open', ({ input, choice }) => {
    expect(resolvePickerChoice(input, [])).toEqual(choice);
  });

  it.each([
    { input: '0', why: 'zero' },
    { input: '5', why: 'past the last row' },
    { input: 'abc', why: 'not a number' },
    { input: '', why: 'empty' },
  ])('rejects $why with undefined so the picker can re-prompt', ({ input }) => {
    expect(resolvePickerChoice(input, prds)).toBeUndefined();
  });
});

describe('parseIssueNumber', () => {
  it('accepts a positive issue number for manual PRD entry', () => {
    expect(parseIssueNumber('31')).toBe(31);
  });

  it('accepts a number wrapped in whitespace', () => {
    expect(parseIssueNumber(' 31 ')).toBe(31);
  });

  it.each([
    { input: '0', why: 'zero' },
    { input: '-3', why: 'negative' },
    { input: '#31', why: 'a hash prefix' },
    { input: 'abc', why: 'non-numeric input' },
    { input: '', why: 'an empty answer' },
  ])('rejects $why with undefined so the picker can re-prompt', ({ input }) => {
    expect(parseIssueNumber(input)).toBeUndefined();
  });
});

describe('resolveIterationCap', () => {
  it('accepts the suggestion on an empty answer', () => {
    expect(resolveIterationCap('', 5)).toBe(5);
  });

  it('accepts the suggestion on a whitespace-only answer', () => {
    expect(resolveIterationCap('  ', 5)).toBe(5);
  });

  it('takes an explicit cap over the suggestion', () => {
    expect(resolveIterationCap('9', 5)).toBe(9);
  });

  it.each([
    { input: '0', why: 'zero' },
    { input: '-1', why: 'negative' },
    { input: '1.5', why: 'fractional' },
    { input: 'abc', why: 'non-numeric' },
  ])('rejects a $why cap with undefined so the picker can re-prompt', ({ input }) => {
    expect(resolveIterationCap(input, 5)).toBeUndefined();
  });
});

describe('suggestedIterationCap', () => {
  it('suggests one implement→review cycle per open slice plus slack for bounces', () => {
    expect(suggestedIterationCap(3)).toBe(5);
  });

  it('still leaves the bounce slack for a single open slice', () => {
    expect(suggestedIterationCap(1)).toBe(3);
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
