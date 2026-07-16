# Context

Glossaries for this repo: the **dictation pipeline** the app runs, the
**app surfaces** it presents, and the **batch workflow** used across
issues, prompts, and agent tooling. Terms only — for the decisions behind
any of them, see `docs/adr/`.

## App surfaces

**Badge** — The always-on-top, non-activating floating pill that is the
app's recording surface. A single living component that moves through
idle ⇄ hover → recording → working → done/error and back; it never steals
focus from the app being dictated into.
_Avoid_: HUD, overlay, recording bar, floating window

**Dictation row** — The compact presentation of one saved Dictation session
used in both Home's recent list and the full History list. The two surfaces may
offer different secondary actions, but the row's identity and visual language
stay the same.
_Avoid_: history element, history item, session preview

**Appearance preference** — The user's global choice of System, Light, or Dark
for FoldWise surfaces. System follows the live macOS appearance; Light and Dark
override it across the main window and Badge.
_Avoid_: theme mode, color mode

**Shortcut collision** — An invalid assignment where Push to Talk, Toggle
Recording, or Mode cycle resolve to the same effective key, including aliases
and differences in case or surrounding whitespace.
_Avoid_: duplicate shortcut, hotkey conflict

**Mode cycle** — The optional global command that advances the active selection
through the visible order of editable Modes, wrapping at the end. Voice to Text
is outside the order; the command has no effect when no different selection is
available.
_Avoid_: switch mode, next mode

## Dictation pipeline

**Dictation session** — One press-to-insert cycle: from holding the hotkey
and speaking, through to the (optionally polished) text landing in the
focused app — or left on the clipboard when it can't be pasted. The unit the
app sequences and reports progress for.
_Avoid_: recording, dictation

**Input device** — The global microphone source used by the record Stage. It is
either the live macOS system default or a specifically chosen connected device.
_Avoid_: microphone setting, audio source

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
(raw), "Casual", "Email", "Bullets".
_Avoid_: profile, preset

**In-place Mode** — A Mode whose Polish output tracks the transcript closely:
same words, same rough length, fixed punctuation/casing. E.g. "Casual". Off-task
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

**ASR engine** — A transcription backend behind the transcribe Stage's
`Transcribing` seam: a library plus the family of speech models it runs.
FoldWise has two — FluidAudio (the Parakeet family, on the Neural Engine) and
WhisperKit (the Whisper family, CoreML). Each engine is one conformer of
`Transcribing`.
_Avoid_: backend, provider, ASR

**ASR model** — A specific set of speech weights an engine loads to transcribe,
e.g. Parakeet TDT v3, Whisper large-v3-turbo, Whisper small. One engine offers
several models that trade download size for accuracy and language coverage; the
Whisper models are what widen FoldWise's language reach beyond Parakeet's 25.
_Avoid_: weights, checkpoint

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

**Run model** — The single coding model selected interactively when a
Sandcastle run starts. The implementer and reviewer use the same Run model for
the entire run; providers are never mixed between phases. Selection comes from
a closed, curated Anthropic/OpenAI catalog; arbitrary model ids are not accepted.
_Avoid_: agent model, phase model, provider selection

**Run effort** — The reasoning budget selected after the Run model when a
Sandcastle run starts. The same effort applies to both the implementer and the
reviewer for the entire run. The picker offers only efforts supported by the
selected model; unsupported effort is never silently downgraded.
_Avoid_: thinking level, phase effort

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
