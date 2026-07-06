# Context

Glossaries for this repo: the **dictation pipeline** the app runs, and the
**batch workflow** used across issues, prompts, and agent tooling. Terms
only — for the decisions behind either, see `docs/adr/`.

## Dictation pipeline

**Dictation session** — One press-to-insert cycle: from holding the hotkey
and speaking, through to the (optionally polished) text landing in the
focused app — or left on the clipboard when it can't be pasted. The unit the
app sequences and reports progress for.
_Avoid_: recording, dictation

**Stage** — One of the four steps a dictation session flows through: record
the audio, transcribe it to text, optionally polish that text, and insert it
into the focused app.

**Polish** — The optional stage that rewrites a raw transcript with a local
LLM (Ollama) per the active Mode. Skipped for raw modes and very short
transcripts, and it falls back to the raw transcript whenever Ollama is
unreachable.
_Avoid_: clean, format, LLM step

**Mode** — A named dictation profile that decides whether and how to polish:
its LLM model, system prompt, and preserved vocabulary. E.g. "Voice to Text"
(raw), "Clean", "Email", "Bullets".
_Avoid_: profile, preset

**In-place Mode** — A Mode whose Polish output tracks the transcript closely:
same words, same rough length, fixed punctuation/casing. E.g. "Clean". Off-task
detection can be strict here — the polished text should stay near the raw one.
_Avoid_: transform-in-place, tight mode

**Expanding Mode** — A Mode whose Polish legitimately restructures and grows the
transcript — reordering, rephrasing, dropping filler. E.g. "Email", "Bullets".
Off-task detection must be looser here, because low overlap and larger length
are honest for these Modes, not a sign the model went off-task.
_Avoid_: generative mode, loose mode

**Off-task** — The Polish failure the app defends against: the model *replies
to* or *obeys* the transcript (an answer, a refusal, a poem) instead of
*transforming* it per the Mode. Distinct from an unreachable model or a
malformed response; the tell is answer-shaped output with little relation to
what was said.
_Avoid_: injected, jailbroken, hallucination

## Batch workflow

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

**Commit convention** — every commit an agent makes uses a Conventional
Commit subject (`feat:`, `fix:`, `refactor:`, …) so release-please can
categorise it for the changelog and version bump. Each commit also carries a
`Closes #<n>` line naming its slice — the line that traces a batch's
commits back to the slices they implement.

**Handoff** — the end of a scoped run, when the batch returns to the
maintainer. A drained PRD (every released slice closed) is labeled
`code-review` and gets a per-slice summary; a stalled run gets a report of
the slices that remain and why it stopped. Review of the resulting diff
and the PR itself stay human, always.
