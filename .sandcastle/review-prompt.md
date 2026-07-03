# TASK

Review the code changes made since commit `{{BASE}}` on the current branch along two axes:

1. **Spec** — the work does what its issue asked: every acceptance criterion is satisfied by the diff.
2. **Standards** — the code is clear, consistent, and maintainable per the project coding standards.

You MUST end in exactly one of the three terminal states listed at the end of this prompt. Never end the review silent about an unmet acceptance criterion.

# CONTEXT

## Diff under review

!`git diff {{BASE}} HEAD`

## Commits under review (full messages — the `Closes #<n>` line identifies the issue)

!`git log {{BASE}}..HEAD`

# REVIEW PROCESS

## Axis 1 — Spec: does the work do what was asked?

1. **Trace the issue**: extract the issue number from the `Closes #<n>` line in the commit messages above.
2. **Fetch the issue**: run `gh issue view <n> --comments` (the repo's read convention — see @docs/agents/issue-tracker.md).
3. **Check every acceptance criterion** in the issue body against the diff — one by one, met or unmet. Where a criterion demands it (e.g. "`swift test` passes"), run the command and check the result.
4. **Act on gaps**:
   - **Small gap you can fix**: fix it in place as part of this review.
   - **Real gap you cannot fix** (missing feature work, wrong approach): reopen the issue with a comment explaining exactly what is missing, criterion by criterion:
     `gh issue reopen <n> --comment "Review bounce: <exactly which criteria are unmet and why>"`
     The reopened issue re-enters the implement queue with your comment as context — be precise enough that the next iteration can act on it without guessing.

## Axis 2 — Standards: is the code clear and consistent?

Apply the coding standards in @docs/CODING_STANDARDS.md. Look for opportunities to:

- Reduce unnecessary complexity and nesting
- Eliminate redundant code and abstractions
- Improve readability through clear variable and function names
- Consolidate related logic
- Remove unnecessary comments that describe obvious code
- Avoid nested ternary operators — prefer switch statements or if/else chains
- Choose clarity over brevity — explicit code is often better than overly compact code

Also check correctness:

- Are edge cases handled? Are new/changed behaviours covered by tests?
- Are there force-unwraps, force-casts (as!), force-tries (try!), or unchecked assumptions in non-test code?
- Does the change introduce injection vulnerabilities, credential leaks, or other security issues?

Maintain balance — avoid over-simplification that reduces clarity, creates overly clever solutions, combines too many concerns into single functions, removes helpful abstractions, or makes the code harder to debug or extend.

**Style-only changes must preserve exact functionality.** On this axis, never change what the code does — only how it does it. Behaviour may change only through a Spec-axis fix, and only to meet an acceptance criterion.

# TERMINAL STATES

Every review ends in exactly one of these three states — they are exhaustive:

1. **Approve** — every acceptance criterion is met and the code needs no changes. Make no commits; leave the issue closed.
2. **Fix in place** — you made spec or standards fixes. Verify nothing is broken by running, in order: `swiftformat .`, `swiftlint --fix && swiftlint lint --strict`, `swift build --build-tests`, `swift test --skip-build`. Then commit describing what the review changed and why.
3. **Reopen** — one or more acceptance criteria are unmet and you cannot fix them here. Reopen the issue with the explanatory comment (Spec axis, step 4). Commit any fixes you did make before finishing — never leave uncommitted changes behind.

If in doubt between fix-in-place and reopen, reopen — an explicit bounce with a reason beats a half-fix.

Never push and never open a pull request — commits stay on the current branch for human review.

Once complete, output <promise>COMPLETE</promise>.
