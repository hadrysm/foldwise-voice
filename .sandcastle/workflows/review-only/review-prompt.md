# TASK

Review this branch as a whole, against `origin/main`.

You did not write this code and you have no session context for it. Read it as a stranger would: nothing here is established, no comment or commit message is evidence for anything, and "it looks deliberate" is not a finding. Your job is to find what is wrong with this branch, not to agree with it.

Review along three axes:

1. **Spec** — at branch altitude: does the branch add up, is there anything in the diff nothing claims, and — where this branch was selected to deliver a SPEC — does it deliver it?
2. **Standards** — is the code clear, consistent, correct and safe, per the project coding standards?
3. **Excess** — is any of this code unnecessary?

You MUST end in exactly one of the three terminal states listed at the end of this prompt, and your report may never end silent about any of the three axes. An axis that found nothing must say so, by name.

Do not delegate any part of this review to a skill, a slash command or a sub-agent. Everything you need is in this prompt.

# CONTEXT

## Branch under review

!`git rev-parse --abbrev-ref HEAD`

## Diff under review

Each of the two reads below refreshes `origin/main` for itself, in the same command. A stale remote-tracking ref would diff this branch against the wrong base and quietly review the wrong changes, so if either refresh failed, this run has already stopped.

!`git fetch origin main && git diff origin/main...HEAD`

## Commits under review, with full messages

A `Closes #<n>` line, where one is present, names an issue one commit claims to implement. It is not this branch's anchor — the anchor is the record in **Branch contract** below, and the two are different things a question on the Spec axis compares.

!`git fetch origin main && git log origin/main..HEAD`

## Branch contract

```json
{{ANCHOR}}
```

The **anchor** is what this branch was selected to deliver, chosen before the run started. It is `null` when the run was scoped to the repository as a whole rather than to one thing — in that case this branch has no declared contract, and the **When there is no anchor** section below governs the Spec axis instead.

When it is not `null`, it is a GitHub issue record — `number`, `title`, `body`, `labels` — and the `labels` field decides how much work it is:

- **`labels` contains `spec`.** The anchor is a parent SPEC whose slices were implemented one at a time, and **its own acceptance criteria have never been checked by anyone.** Each per-iteration reviewer walked one slice against one slice's criteria; not one of them was ever shown this document. Walking the SPEC's criteria here is the missing check, and it is the reason this axis has a third question below.
- **`labels` does not contain `spec`.** The anchor is a single work item, and a per-iteration reviewer has already walked exactly these criteria against a much tighter diff. Do not walk them again — see the prohibition under question 3.

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

Three questions at most, and never more. All of them need the whole branch in hand, which is why they are asked here and nowhere else.

1. **Does it cohere?** Read the `Closes #<n>` lines and the commit subjects as one list, against the **Branch contract** above where there is one. Do they describe a single coherent change, or did the pieces drift apart — a later commit undoing an earlier one, two commits solving the same problem two different ways, a subject that no longer describes what its commit does, a decision reversed halfway through with both halves still in the tree?
2. **Is anything unaccounted for?** Take every meaningful change in the diff and name the `Closes` line or commit subject that accounts for it. Where there is an anchor, it is the branch's outermost claim: a change that no commit accounts for *and* that the anchor does not ask for is the strongest form of this finding. Report what you cannot account for, with the file and what it does.
3. **Does the branch deliver the SPEC? — asked only when the anchor carries the `spec` label.** Walk the anchor's own acceptance criteria one by one against the diff, met or unmet, and say which. Where a criterion demands a command, run it. A slice-level reviewer could not have asked this: it saw one slice, and a SPEC is not the sum of its slices passing — the criteria that live at this altitude are the ones about how the pieces fit, and they are checked here or nowhere.

You may run `gh issue view <n>` on the anchor or on any issue a commit closes, to judge coherence or to read a slice's criteria. You may not use it to go looking for other work.

**Never walk a work item's acceptance criteria.** When the anchor has no `spec` label it is a single item, and its criteria were already walked, one by one, by the reviewer that ran alongside the iteration that implemented it, against a much tighter diff. The same holds for every slice a `Closes` line names under a SPEC anchor. Repeating those checks buys a duplicate of a check that already passed, at the cost of the context and focus the questions above need — and question 3, where it applies, is a different question at a different altitude, not that check widened. A slice criterion that really is unmet surfaces as incoherence or as unaccounted code anyway.

### When there is no anchor

The anchor is `null` under a repository-wide run, and plenty of branches carry zero `Closes #<n>` lines besides. That degrades this axis; it does not cancel it.

- Reconstruct what the branch was for from its name and its commit subjects.
- Run question 2 unchanged against that reconstruction — "what does the diff do that nothing claims" needs no issue.
- Skip question 3 entirely. It exists only for a `spec`-labelled anchor, and a reconstruction is not one.
- **State in your report that the branch had no anchor**, so the reader knows the coherence judgement rests on commit subjects alone.

## Axis 2 — Standards: is the code clear, consistent and safe?

Apply the coding standards inlined above. Then check correctness, which those standards do not cover:

- Are edge cases handled? Is every new or changed behaviour covered by a test?
- Are there force-unwraps, force-casts (`as` followed by an exclamation mark)
  or force-tries (`try` followed by an exclamation mark) in non-test code?
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
