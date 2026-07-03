# Context

Glossary of the batch-workflow vocabulary used across this repo's issues,
prompts, and agent tooling. Terms only — for the decisions behind the
workflow, see `docs/adr/`.

## Glossary

**PRD** — a GitHub issue carrying the `prd` label that holds a product
requirements document: the problem, the solution shape, and a planned
breakdown into slices. A PRD parents its slices as native GitHub
sub-issues.

**Slice** — one sub-issue of a PRD: a single, independently implementable
and reviewable unit of the PRD's work. Each slice states its own
acceptance criteria; an agent works exactly one slice at a time.

**Release gate** — the act of labeling a slice `ready-for-agent`. Drafting
a slice and releasing it are separate acts: a slice exists as soon as its
sub-issue does, but joins the batch queue only once the maintainer applies
the label.

**Batch** — the set of issues one run works through: either a PRD's open,
released slices (a *scoped* run) or the whole `ready-for-agent` queue.

**Implement→review loop** — the run's repeating cycle: an implementer
agent picks one slice from the batch, implements it test-first, and
commits; then a reviewer agent reviews exactly that slice's changes and
either approves, fixes small gaps in place, or reopens the slice with a
bounce comment for the next cycle.

**RALPH** — the implementer agent's persona, and the commit-message prefix
(`RALPH:`) marking every commit it makes. Each such commit also carries a
`Closes #<n>` line naming its slice — the line that traces a batch's
commits back to the slices they implement.

**Handoff** — the end of a scoped run, when the batch returns to the
maintainer. A drained PRD (every released slice closed) is labeled
`code-review` and gets a per-slice summary; a stalled run gets a report of
the slices that remain and why it stopped. Review of the resulting diff
and the PR itself stay human, always.
