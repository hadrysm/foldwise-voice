# Context

## Open issues

!`gh issue list --state open --label ready-for-agent --limit 100 --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`

The list above has already been filtered to issues ready for work and is the sole source of truth for what work exists. Do not run your own unfiltered query to find more issues — if the list is empty, there is nothing to do.

## Recent completed slices (last 10)

!`git log --oneline --grep="Closes #" -10`

# Task

You are an autonomous coding agent working through issues one at a time.

## Priority order

Work on issues in this order:

1. **Bug fixes** — broken behaviour affecting users
2. **Tracer bullets** — thin end-to-end slices that prove an approach works
3. **Polish** — improving existing functionality (error messages, UX, docs)
4. **Refactors** — internal cleanups with no user-visible change

Pick the highest-priority open issue that is not blocked by another open issue.

## Workflow

1. **Explore** — read the issue carefully. Pull in the parent PRD if referenced. Read `CONTEXT.md` and `docs/adr/` if present (proceed silently if absent), then the relevant source files and tests before writing any code. Issue-tracker conventions live in @docs/agents/issue-tracker.md.
2. **Plan** — decide what to change and why. Keep the change as small as possible.
3. **Execute** — use RGR (Red → Green → Repeat → Refactor): write a failing test first, then write the implementation to pass it. Follow the coding standards in @docs/CODING_STANDARDS.md.
4. **Verify** — run, in order:
   1. `swiftformat .`
   2. `swiftlint --fix && swiftlint lint --strict`
   3. `swift build --build-tests` (compilation is the type check)
   4. `swift test --skip-build`
   5. **Only if the change touches `.sandcastle/`** — `pnpm --dir .sandcastle run check-types`
      then `pnpm --dir .sandcastle run test`. The Swift steps above never reach this
      TypeScript, so a runner change is otherwise committed unverified.

   Fix any failures before proceeding — a commit that fails any of these will be rejected by CI.
5. **Commit** — make a single git commit. The message MUST:
   - Start the **subject line** with a Conventional Commit type so release-please can categorise the change: `feat:`, `fix:`, `perf:`, `refactor:`, `docs:`, `build:`, `chore:`, `test:`, `style:`, or `ci:`. Add an optional scope when it clarifies, e.g. `fix(hotkey): …`. Choose the type from what the change *is*:
     - `feat:` — a new user-facing capability (most tracer bullets)
     - `fix:` — corrects broken user-facing behaviour (most bug fixes)
     - `perf:` — a performance improvement with no behaviour change
     - `refactor:` — an internal cleanup with no user-visible change
     - `docs:`, `build:`, `test:`, `style:`, `ci:` — as named
     - `chore:` — anything that fits none of the above

     Keep the subject in the imperative mood, ~72 characters or fewer, with no trailing period.
   - Include a `Closes #<n>` line in the body referencing the issue this commit implements — the reviewer uses it to trace the commit back to the issue, and release-please uses it to link the changelog entry.
   - In the body, record the task completed and any PRD reference, the key decisions made, the files changed, and any blockers for the next iteration.
6. **Close** — close the issue with `gh issue close <ID> --comment "Completed by Sandcastle"` explaining what was done.

## Rules

- Work on **one issue per iteration**. Do not attempt multiple issues in a single iteration.
- Do not close an issue until you have committed the fix and verified tests pass.
- Do not leave commented-out code or TODO comments in committed code.
- Never push and never open a pull request — commits stay on the current branch for human review.
- If you are blocked (missing context, failing tests you cannot fix, external dependency), leave a comment on the issue and move on — do not close it.

# Done

When all actionable issues are complete (or you are blocked on all remaining ones), or the open-issues block at the top of this prompt is empty, output the completion signal:

<promise>COMPLETE</promise>
