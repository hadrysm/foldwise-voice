# TASK

Review this branch as a whole, against `origin/main`.

You did not write this code and you have no session context for it. Read it as a stranger would: nothing here is established, no comment or commit message is evidence for anything, and "it looks deliberate" is not a finding. Your job is to find what is wrong with this branch, not to agree with it.

Review along three axes:

1. **Spec** — at branch altitude: does the branch add up, and is there anything in the diff nothing claims?
2. **Standards** — is the code clear, consistent, correct and safe, per the project coding standards?
3. **Excess** — is any of this code unnecessary?

You MUST end in exactly one of the three terminal states listed at the end of this prompt, and your report may never end silent about any of the three axes. An axis that found nothing must say so, by name.

Do not delegate any part of this review to a skill, a slash command or a sub-agent. Everything you need is in this prompt.

# CONTEXT

## Refreshing the remote's main

!`git fetch origin main`

The fetch above ran before you started. A stale remote-tracking ref would diff this branch against the wrong base and quietly review the wrong changes, so if it failed, this run has already stopped.

## Branch under review

!`git rev-parse --abbrev-ref HEAD`

## Diff under review

!`git diff origin/main...HEAD`

## Commits under review, with full messages

A `Closes #<n>` line, where one is present, is this branch's issue anchor.

!`git log origin/main..HEAD`

## Issue-tracker conventions

````markdown
!`cat docs/agents/issue-tracker.md`
````

## Coding standards

````markdown
!`cat docs/CODING_STANDARDS.md`
````

# REVIEW PROCESS

Spec's second question and the Excess axis are one measurement taken from two directions: one asks what the diff contains that the branch never claimed, the other asks what this code would lose by being deleted. So walk the diff **once** and file each finding under whichever axis names it. Do not sweep it twice.

## Axis 1 — Spec: does the branch add up?

Two questions, and only two. Both need the whole branch in hand, which is why they are asked here and nowhere else.

1. **Does it cohere?** Read the `Closes #<n>` lines and the commit subjects as one list. Do they describe a single coherent change, or did the pieces drift apart — a later commit undoing an earlier one, two commits solving the same problem two different ways, a subject that no longer describes what its commit does, a decision reversed halfway through with both halves still in the tree?
2. **Is anything unaccounted for?** Take every meaningful change in the diff and name the `Closes` line or commit subject that accounts for it. What you cannot account for is the finding — report it, with the file and what it does.

You may run `gh issue view <n>` on an anchor issue to judge coherence.

**Do not re-check acceptance criteria.** They were already walked, one by one, by the reviewer that ran alongside each iteration, against a much tighter diff. Repeating that here buys a duplicate of a check that already passed, at the cost of the context and focus the two questions above need. A criterion that really is unmet surfaces as incoherence or as unaccounted code anyway.

### When the branch has no issue anchor

Plenty of branches carry zero `Closes #<n>` lines. That degrades this axis; it does not cancel it.

- Reconstruct what the branch was for from its name and its commit subjects.
- Run question 2 unchanged against that reconstruction — "what does the diff do that nothing claims" needs no issue.
- **State in your report that no issue anchor was found**, so the reader knows the coherence judgement rests on commit subjects alone.

## Axis 2 — Standards: is the code clear, consistent and safe?

Apply the coding standards inlined above. Then check correctness, which those standards do not cover:

- Are edge cases handled? Is every new or changed behaviour covered by a test?
- Are there force-unwraps, force-casts (`as!`) or force-tries (`try!`) in non-test code?
- Does the change introduce an injection vulnerability or leak a credential — a shell command built from unvalidated input, a token or key in a log line, a secret in a committed file?

**Style-only changes must preserve exact functionality.** On this axis, never change what the code does — only how it does it.

## Axis 3 — Excess: is any of this code unnecessary?

Apply this test:

> For every new type, protocol, parameter, config flag, or file in this diff: name the caller that requires it. One caller and no test exercising the other path means inline it.

State the verdict for each one. You may not skip this section by concluding the code "seems reasonable."

Two different defects hide on this axis, and they are caught differently:

- **Scope creep** — code nothing asked for: an extra option, a defensive branch for a state that cannot occur, an extension point with no second implementation, a configurable value with one possible value. Caught by tracing the code back to what the branch claims, which is Spec's question 2 read from this side.
- **Ceremony** — in-scope code built with more machinery than the job needs: a protocol with one conformer, a wrapper that only forwards, a parameter every caller passes the same value for, a type that exists to be passed to one function. Caught by the delete test above.

# TERMINAL STATES

Every review ends in exactly one of these three states — they are exhaustive:

1. **Approve** — nothing to change on any axis. Make no commits. Say so axis by axis; "looks good" is not a report.
2. **Fix in place** — you corrected what you found and committed it, as described under **Commits** below. Findings you chose not to act on still go in the report.
3. **Report** — you write the findings out and commit nothing; the human decides. This is the right state whenever the fact is solid but acting on it is a design call: "this protocol has one conformer" is a fact, "so delete it" is an opinion. Prefer Report over a deletion you are not sure of.

## Commits

At most two commits, in this order:

1. One `fix:` or `refactor:` commit for every Spec and Standards correction.
2. One separate `refactor:` commit for every Excess deletion, and nothing else. **Always last.**

The split is what makes your deletions reversible. You hold the least context about why this code exists and, being a different model than the one that wrote it, the most confidence that it is wrong — so with the deletions alone in the final commit, `git reset --hard HEAD~1` drops every deletion and keeps every correction. Never mix a correction into the deletion commit, and never put a deletion in the first one.

Write **Conventional Commit** subjects, as elsewhere in this repo: imperative mood, ~72 characters or fewer, no trailing period. Say in the body what the review changed and why.

## Verify before committing

Run, in order:

1. `swiftformat .`
2. `swiftlint --fix && swiftlint lint --strict`
3. `swift build --build-tests`
4. `swift test --skip-build`
5. **Only if your changes touch `.sandcastle/`** — `pnpm --dir .sandcastle run check-types`, then `pnpm --dir .sandcastle run test`. The four Swift steps above never reach that TypeScript, so a change there is otherwise committed unverified.

Fix every failure before you commit.

Never push and never open a pull request — commits stay on this branch for human review.

Once complete, output <promise>COMPLETE</promise>.
