# TASK

Review the code changes committed on your current branch since `{{REVIEW_BASE}}` — the commit this iteration started from — along two axes:

1. **Spec** — the work does what its issue asked: every acceptance criterion is satisfied by the diff.
2. **Standards** — the code is clear, consistent, and maintainable per the project coding standards.

You MUST end in exactly one of the three terminal states listed at the end of this prompt. Never end the review silent about an unmet acceptance criterion.

# CONTEXT

## The work item this iteration was given

```json
{{WORK}}
```

This is the same record the implementer received, as the issue stood when the run selected it. Its `body` holds the acceptance criteria you check on the Spec axis, its `comments` hold any earlier review bounce, and `spec`, when not `null`, is the ancestor SPEC the item sits inside.

Do not fetch this issue from GitHub. The implementer has already closed it and left its own summary as a comment there — a report by the author arguing that the work is correct, which is the one piece of evidence a reviewer should least want in hand.

## Diff under review

!`git diff {{REVIEW_BASE}}...HEAD`

## Commits under review (full messages — the `Closes #<n>` line identifies the issue)

!`git log {{REVIEW_BASE}}..HEAD`

## Issue-tracker conventions

````markdown
!`cat docs/agents/issue-tracker.md`
````

## Coding standards

````markdown
!`cat docs/CODING_STANDARDS.md`
````

# REVIEW PROCESS

## Axis 1 — Spec: does the work do what was asked?

1. **Cross-check the anchor**: read the `Closes #<n>` line in the commit messages above and compare `<n>` against the `number` field of the work item. They must be the same issue.

   A mismatch, or a missing `Closes` line, is itself a Spec finding and you must report it: the commit claims an issue other than the one this iteration was given, so release-please will link the changelog entry to the wrong issue and no later reader can trace the change back. Report it, then review the diff against the work item above regardless — the work item is the contract, not the commit message.

2. **Check every acceptance criterion** in the work item's `body` against the diff — one by one, met or unmet. Where a criterion demands it (e.g. "`swift test` passes"), run the command and check the result.
3. **Act on gaps**:
   - **Small gap you can fix**: fix it in place as part of this review.
   - **Real gap you cannot fix** (missing feature work, wrong approach): reopen the work item — the issue whose `number` is in the record above, never the one the commit message named if the two disagreed — with a comment explaining exactly what is missing, criterion by criterion:
     `gh issue reopen <number> --comment "Review bounce: <exactly which criteria are unmet and why>"`
     Leaving that issue open is the entire bounce signal: the run reads its state back from GitHub after you finish, and open means bounced. Your comment is the only context a later attempt gets, so be precise enough that it can act without guessing.

## Axis 2 — Standards: is the code clear and consistent?

Apply the coding standards from the **Coding standards** section above. Look for opportunities to:

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
2. **Fix in place** — you made spec or standards fixes. Verify nothing is broken by running, in order: `swiftformat .`, `swiftlint --fix && swiftlint lint --strict`, `swift build --build-tests`, `swift test --skip-build`. Then make a single **Conventional Commit** — pick the type from what you changed (`fix:` for a spec correction; `refactor:`, `style:`, or `docs:` for standards cleanups) — describing what the review changed and why.
3. **Reopen** — one or more acceptance criteria are unmet and you cannot fix them here. Reopen the work item with the explanatory comment (Spec axis, step 3). Commit any fixes you did make before finishing — never leave uncommitted changes behind.

If in doubt between fix-in-place and reopen, reopen — an explicit bounce with a reason beats a half-fix.

Never push and never open a pull request — commits stay on the current branch for human review.

Once complete, output <promise>COMPLETE</promise>.
