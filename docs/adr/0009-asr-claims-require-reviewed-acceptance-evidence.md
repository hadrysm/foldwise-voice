# ADR-0009: ASR claims require reviewed acceptance evidence

## Status

Accepted (2026-07-20) by issue #203.

## Context

FoldWise's catalog separates model visibility, artifact release eligibility,
device eligibility, local availability, and selection. Publisher benchmarks and
runtime support tables establish feasibility, but they cannot prove that an exact
artifact profile is correct, usable, or safe on a particular Mac. The catalog
therefore needs a reproducible acceptance contract before FoldWise may claim
capabilities or enable Download and Use.

## Decision

FoldWise accepts no composite benchmark score and does not average away failures.
Every requirement below is an independent hard gate. A failed gate cannot be
offset by a stronger result elsewhere, and a crash, timeout, corrupt result, or
contract violation may not be discarded as an outlier.

### Evidence topology

Capability correctness and device eligibility are related but separate:

- **ASR capability certification** belongs to one exact artifact profile,
  runtime revision, and signed FoldWise release-candidate build. The full suite
  runs in the weakest intended eligible SoC/memory configuration, its
  worst-cooling shipping enclosure, and the minimum supported macOS major. A
  profile may certify on a stronger environment only by declaring that narrower
  floor.
- **ASR device eligibility** belongs to one ASR device evidence cell: exact
  artifact profile; Apple SoC generation and marketed tier; enabled CPU, GPU,
  and Neural Engine core configuration; and physical unified-memory size. Binned
  variants and memory sizes are separate cells. Mac model, OS build, app and
  runtime revisions, power state, and test conditions are evidence metadata,
  not dimensions that widen a cell. Stronger or newer hardware is never inferred
  eligible.
- Every non-canonical device cell runs the complete resource, performance,
  lifecycle, and thermal suite plus a smaller correctness smoke. A failure in
  that smoke affects only the cell; a failure in the full profile suite blocks
  or narrows the capability claim everywhere.

Catalog-visible publisher coverage may be shown only as a source-attributed
fact. A FoldWise claim requires FoldWise acceptance evidence. Each certified
locale is independent, but batch/native-streaming recognition mode and
translation behavior are identity-defining ASR profile capabilities. A failed
declared profile capability blocks that profile definition rather than silently
downgrading it at runtime; a reduced contract requires a newly reviewed profile
definition and ID.

### Frozen correctness fixtures

Each proposed certified locale requires at least 10,000 normalized reference
words of clean human speech and 5,000 words with frozen moderate-noise mixes,
from at least 20 speakers. The corpus covers materially distinct regional
accents, voice ranges, speech rates, recording devices, conversational dictation,
prose, names, numerals, dates, commands, and code-switch boundary probes. No
required demographic or accent slice contributes less than 10%, and every slice
used by a threshold contains at least 2,000 words. Office, street, fan, and cafe
noise is mixed deterministically at 10-20 dB SNR. Recordings are licensed,
held-out, human speech with documented provenance and no known training overlap;
TTS cannot establish certification. Adaptation-ready locales are not certified.

Every fixture set is frozen before testing in a content-addressed manifest that
records audio SHA-256, locale, pseudonymous speaker and slice metadata, reference
text, license and provenance, normalization rules, noise source, SNR, and
deterministic transform seed. Bulky or restricted audio may live outside Git,
but its manifest and expected references are versioned. A fixture may never be
removed after its failure is observed. Corrections create a new fixture-set
version, require the affected certification to rerun, and preserve the old
manifest and evidence. Comparisons across fixture versions require an explicit
bridge run.

The production recorder normalizes audio to 16 kHz mono non-interleaved Float32.
Capability and recognition-performance fixtures enter at the production
recognition-session boundary in exactly that format without bypassing ASR
preprocessing, decoding, serialization, or lifecycle behavior. A separate
capture-path suite feeds 44.1/48 kHz mono and stereo files through the production
conversion path; recognition may diverge by no more than two error-rate
percentage points from the canonical 16 kHz fixture. Hardware-microphone testing
remains supplemental manual smoke and does not establish model accuracy.

### Recognition and capability gates

For every certified locale:

- clean conversational corpus WER is at most 15%, with every required slice at
  most 25%;
- moderate-noise corpus WER is at most 25%, with every required slice at most
  35%;
- locale-aware CER replaces WER for scripts without reliable word boundaries,
  using the same limits; and
- a later accepted build may regress by no more than two absolute percentage
  points overall or 10% relative within any slice against its frozen baseline.

Locales and clean/noisy conditions never average into one passing score.
Multilingual profiles run through the production session path without test-only
language hints because FoldWise has no per-Dictation locale selector. A profile
that passes only with an injected locale does not certify that locale.
Code-switch probes are robustness checks, not a code-switching claim; such a
claim requires a future dedicated bilingual corpus and profile declaration.

Translation-capable profiles test every certified source locale directly against
a frozen speech-to-English corpus. At least 99% of non-empty outputs must be
English, corpus chrF++ must be at least 50, every speaker/noise/domain slice must
be at least 40, and dedicated negation, numeral, named-entity, date, and dosage
probes permit zero critical meaning reversals. A failing source locale is omitted
from the certified translation-locale set. A profile that declares translation
unavailable must reject the operation explicitly; it may not silently transcribe
or route through Polish.

Punctuation and casing are scored only on raw ASR output before Polish or other
formatting. A profile may certify transcription while declaring either
capability unavailable. If punctuation is claimed, sentence-boundary F1 must be
at least 0.90 and punctuation macro-F1 at least 0.80 across periods, commas,
questions, and exclamations. Claimed capitalization requires at least 95%
token-level casing accuracy after genuinely ambiguous proper-name references are
excluded. WER/CER normalization cannot certify these claims.

Each profile also runs 100 frozen no-speech fixtures spanning 0.1-60 seconds of
digital silence, room tone, fans, keyboard noise, clicks, and lyric-free music.
They permit zero lexical output; punctuation and whitespace normalize to empty.
Adding ten seconds of leading and trailing silence to speech may worsen normalized
error by no more than two percentage points and may not repeat text. Empty,
sub-frame, clipped, NaN, and infinite-sample inputs must terminate deterministically
as empty or failed according to the input contract, never crash, hang, or
fabricate text.

The smaller correctness smoke in every non-canonical device cell contains at
least 200 clean and 100 noisy reference words for every certified locale from
two speakers, one translation probe per certified translation locale, the full
batch/streaming structural event fixture, and ten no-speech fixtures. Each locale
must satisfy the absolute accuracy floor and stay within five percentage points
of its canonical-environment result. Any structural mismatch, hallucination,
wrong-language behavior, or larger divergence fails the cell and triggers a
full diagnostic run there.

### Batch and streaming gates

Batch profiles emit no transcript update before `finish`. Native-streaming
profiles must produce at least one non-empty update before `finish` on a
continuous-speech fixture. First-update latency may not exceed declared
algorithmic context plus one second of processing: 3.08 seconds for Unified's
reviewed 2.08-second context and 3.24 seconds for Nemotron's reviewed 2240 ms
profile. Later token-bearing updates remain ordered append-only full snapshots,
suppress duplicates, and keep tentative text empty. `finish` flushes residual
audio, and every session publishes exactly one authoritative completed,
cancelled, or failed terminal. These are acceptance limits, not a promise of one
universal display cadence.

Timing uses a monotonic clock at FoldWise's session boundary. Batch real-time
factor includes serialized `feed`, preprocessing, inference, decoding, `finish`,
and terminal delivery divided by accepted audio duration, excluding engine load
and fixture-file I/O. Streaming RTF sums actual processing time rather than the
real-time pauses used to feed audio. First-update latency begins when the first
voiced sample is accepted; finish latency begins when `finish` wins serialization.
Cold load begins after the prior engine is fully dropped and ends only when the
replacement is prewarmed and can vend a session. Short fixtures contain ten
seconds of audio and long-form fixtures five minutes.

With a warm engine:

- a ten-second batch utterance completes within two seconds at p95 and three
  seconds maximum after `finish`;
- batch long-form RTF is at most 0.5 at p95;
- streaming processing RTF is at most 0.8 so audio cannot accumulate without
  bound; and
- streaming `finish` reaches the terminal within one second at p95 and 1.5
  seconds maximum.

A timeout, dropped audio, or unbounded backlog is a hard failure.

### Cold installation, storage, and load

Network transfer time is not a device-eligibility measurement. Cold installation
starts with the complete immutable payload present locally and with no prior
profile data, staging directory, or relevant Core ML cache. The real network
path is tested separately for URL validity, resume/cancel behavior, and manifest
integrity without a latency limit. Installation passes only when isolated
staging, complete hash verification, semantic validation, compilation, atomic
promotion, and prewarm succeed, and the profile never appears available early.

The default Parakeet profile must cold-install through prewarm within 120 seconds
maximum and post-reboot cold-load within 15 seconds at p95 and 20 seconds maximum.
Optional profiles must cold-install within 300 seconds maximum and post-reboot
cold-load within 60 seconds at p95 and 75 seconds maximum. Operations may show
determinate or indeterminate progress but must terminate explicitly in success
or failure and remain cancellable where the lifecycle permits.

Catalog evidence reports manifest download bytes, installed bytes, and temporary
free space separately. Required temporary free space equals the worst observed
clean-install peak plus the larger of 1 GiB or 20% of that peak, and preflight
runs before staging. Success leaves no staging residue. Failure or cancellation
restores the original state and removes unverified data; only explicitly verified
resumable chunks may remain. Exceeding the published requirement invalidates the
evidence until the value is raised and the cell rerun.

Every profile/cell injects missing, extra, truncated, and hash-mismatched files;
invalid Core ML packages and tokenizer/vocabulary layouts; insufficient disk at
download, staging, compilation, and promotion; permission denial; cancellation;
and process termination at every durable phase. Invalid data never becomes
available, a valid installed profile survives failed repair unchanged, promotion
is atomic, restart reconciliation removes unverified residue while preserving
verified resumable chunks, and a later clean retry succeeds.

### Memory, cancellation, reclamation, and queueing

Memory gates run after a clean reboot and again with a deterministic coexistence
fixture reserving 25% of physical memory, capped at 4 GiB. During cold install,
load, and sustained recognition, FoldWise's peak physical footprint remains below
60% of physical unified memory; system pressure never becomes critical or stays
warning-level longer than five seconds; and additional swap is at most 256 MiB.
Allocation failure, engine eviction, process termination, or session corruption
fails the cell. Peak physical footprint, compressed memory, pressure, and swap
delta are retained even for passing runs.

After cancellation wins session serialization, the session emits `cancelled`
within one second at p95 and two seconds maximum, accepts no more audio, never
flushes, and emits no later transcript event. The next admitted session must
match a fresh-engine control. Across 50 completion cycles and 50 feed/cancel
cycles, retained footprint growth remains below the larger of 64 MiB or 2% of
physical memory with no monotonic trend. After an engine is dropped, its footprint
returns within the larger of 256 MiB or 10% of its load-time increase over the
pre-load baseline within 15 seconds. Replacement never shows two full resident
engine footprints concurrently.

Each cell also executes 50 deterministic schedules mixing completed, cancelled,
failed, and queued real-engine sessions. Admission remains FIFO and only one
session executes at a time. Pre-admission cancellation removes only that session;
post-admission cancellation uses the latency gate. Selection, repair, and deletion
block new capture, drain existing leases, reclaim the old engine, and only then
load the replacement. Deadlock, starvation, cross-session text, duplicate
terminals, or overlapping resident engines fails the cell. Queue wait is reported
separately and is not hidden in inference RTF.

### Thermal and power evidence

Each cell uses the thermally worst shipping enclosure for its exact SoC/memory
combination. At 22 +/- 2 degrees Celsius, run 30 minutes of continuous streaming
or back-to-back batch recognition on AC and again on battery with Low Power Mode
off. Thermal state never reaches serious or critical; final-five-minute
latency/RTF degrades by no more than 20% from the first five minutes; every
absolute performance gate still passes; and no event, audio, session, or memory
is lost. If the worst enclosure is unmeasured, the cell is unmeasured.

Average and peak process energy impact or package power are recorded when the
hardware exposes trustworthy counters, but thermal stability is the eligibility
gate. FoldWise makes no "power-efficient" or battery comparison without a frozen
comparison target and an explicit energy-per-audio-minute threshold. Missing
reliable counters produces no energy claim.

### Repetitions and supported OS coverage

Minimum run counts are:

- five fully clean cold installations, all of which pass, with the maximum
  authoritative;
- 30 post-reboot cold loads per profile/cell;
- 30 randomized warm runs for short latency, first emission, flush, and
  cancellation;
- 30 five-minute runs for long-form RTF;
- three independent 30-minute thermal runs on AC and three on battery; and
- one 50-session completion soak and one 50-session cancellation soak.

Timing order and fixtures are randomized to reduce cache and ordering bias.
Every failed or retried attempt remains in the evidence.

A cell passes on the latest maintained patch of every macOS major supported by
the release, including the minimum major. One major never implies another. A new
macOS major receives no claim until FoldWise measures it and ships reviewed
evidence. Routine patch updates require focused smoke rather than automatic full
invalidation, but any discovered Core ML/runtime regression suspends the cell
until the full gate reruns. If any supported major fails, the profile cannot be
claimed eligible for the cell unless FoldWise explicitly narrows its OS support.

### Evidence production, review, and invalidation

Every gate is produced by a deterministic FoldWise acceptance runner in release
configuration, using exact profile artifacts and the same artifact, runtime, and
session code as the signed candidate. It emits raw machine-readable samples and
a non-editable verdict. Manual microphone, UI, and real-download smoke remains
required supplemental evidence but cannot establish or override a quantitative
pass. Human review may reject bad provenance or conditions but may not waive a
failure. Test hooks cannot inject production-unavailable hints or broaden a
capability.

Evidence records the artifact-manifest hash, fixture and harness hashes, app
commit and binary hash, runtime revision, macOS build, exact hardware and
enclosure, memory, power state, ambient conditions, timestamps, raw samples, and
every failed or retried attempt. The compact manifest and human verdict are
versioned in the repository; bulky raw logs live in a content-addressed release
asset referenced by SHA-256.

A runner pass is only proposed evidence. A maintainer reviews provenance,
environment, samples, omitted-attempt checks, and threshold calculation through
a repository change. Approval records the evidence hash and marks it accepted;
only accepted evidence feeds the app's bundled eligibility table. Rejected,
superseded, and revoked evidence stays immutable and auditable. Regression
revokes the evidence in the repository and requires an app update because
installed clients do not accept remote eligibility changes.

Acceptance applies only to the exact signed release-candidate binary hash. Any
rebuild requires the affected matrix to rerun. Artifact/profile, runtime,
decoder/tokenizer, compute configuration, preprocessing, session/lifecycle,
compiler/Core ML toolchain, fixture, harness, threshold, or hardware-key changes
require a full affected rerun. A new supported macOS major also requires the full
matrix. Historical evidence remains useful for regression comparison but cannot
authorize a rebuilt app.

FoldWise generates its bundled eligibility table only from reviewed accepted
manifests. The app never benchmarks a user's Mac to grant eligibility, and no
remote service or third party can broaden a bundled claim between app releases.

### Product outcomes

For an exact artifact profile and device cell:

- no accepted evidence, or stale, invalid, superseded, or revoked evidence means
  **Not verified**;
- accepted evidence with every hard gate passing means **Eligible**;
- accepted measurement with a hard-gate failure means **Incompatible**; and
- a transient disk, memory-pressure, or runtime-load failure on an eligible cell
  means **Unavailable/Retry**, not permanent incompatibility.

Only Eligible enables Download and Use. Every model remains catalog-visible.

## Consequences

The policy is intentionally expensive: exact profiles, binned SoCs, memory
sizes, supported macOS majors, and signed candidates create a large physical
test matrix. That cost is the price of making truthful local-device and
capability claims without extrapolation. Initial releases may therefore show
many visible profiles or hardware combinations as Not verified, and the default
Parakeet profile cannot ship until it clears the full supported product floor.

Upstream benchmarks, marketing labels, a faster neighboring SoC, one passing
language, manual smoke, dynamic self-benchmarking, and composite scores were
rejected because none supplies auditable evidence for the exact claim FoldWise
makes.
