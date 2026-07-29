# Streaming latency acceptance

Evidence record for
[Gate streaming latency and record single-model residency](https://github.com/hadrysm/foldwise-voice/issues/358).
Complete this on the documented `foldwise-streaming-reference` Apple-silicon Mac,
against the packaged Release app built from the exact commit being accepted. The
run procedure is
[`docs/streaming-latency-harness.md`](../streaming-latency-harness.md).

**Status: not yet executed.** The harness, the gate, and their deterministic
tests ship unaccepted: no authoritative run exists, so
`docs/streaming-latency-baselines.json` has `acceptedRun: null` and no pinned
fixture hashes.

## Candidate

- Version:
- Commit:
- Reference Mac / chip / memory:
- macOS / Xcode:
- Power and thermal state:
- Accessibility insert constant p95 (ms), with its five raw samples:
- Fixture SHA-256 (short / long):
- Report artifact:
- Tester:
- Human verification:
- Date:

## Automated gate

- [ ] `python3 scripts/run_streaming_latency.py …` completed on the reference Mac
      with 20 samples per class for both `parakeet-eou-320` and `nemotron-560`.
- [ ] The report is `authoritative: true` with an empty `authorityViolations`.
- [ ] The independent `swift test -c release` re-check of the retained report
      passed against `docs/streaming-latency-baselines.json`.
- [ ] First-feedback p95 ≤ 1200 ms for both models. Observed:
- [ ] Short post-release p95 ≤ 1000 ms for Voice to Text, In-place, and
      Expanding on both models. Observed:
- [ ] Long Voice to Text post-release p95 ≤ 1500 ms on both models. Observed:
- [ ] Long In-place and Expanding totals and Polish generation components are
      retained as evidence and were not treated as gates. Observed:

## Single-model residency

- [ ] Exactly one resident ASR engine per measured process.
- [ ] EOU 320 integrated peak footprint / maximum RSS:
- [ ] Nemotron 560 integrated peak footprint / maximum RSS:
- [ ] The Nemotron comparison with the documented **1.227 GB** standalone maximum
      RSS was reviewed by a maintainer and justified here:

## Manual streaming acceptance matrix

Packaged app, real microphone, no debugger.

- [ ] Real EOU 320 download completes and the reported size matches the pane copy.
- [ ] Real Nemotron 560 download completes and the reported size matches.
- [ ] Switching ASR models in both directions leaves exactly one engine resident
      and Dictation working.
- [ ] Voice to Text inserts the streaming final exactly once, unchanged.
- [ ] A Mode's Polish consumes the same raw final History recorded.
- [ ] A long dictation stays responsive and its caption head-truncates to two lines.
- [ ] Live rewrites revise only the tentative tail; the committed prefix never
      shortens.
- [ ] A forced stream failure recovers by re-feeding the retained buffer.
- [ ] A Dictation session started while the previous one is still processing
      records without live snapshots and inserts in order.
- [ ] Changing the input route mid-session does not duplicate or lose audio.
- [ ] Accessibility insertion pastes into the frontmost app.
- [ ] Reduce Motion shows the caption without a fade.
- [ ] VoiceOver reads the caption's stage, committed words, and tentative tail.
- [ ] Dragging the Badge keeps the caption tethered; screen edges clamp it.
- [ ] Another app stays frontmost throughout: neither the Badge nor the caption
      ever takes key or main window status.

## Notes
