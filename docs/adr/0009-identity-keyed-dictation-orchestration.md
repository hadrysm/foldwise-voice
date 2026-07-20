# ADR-0009: Dictation orchestration is identity-keyed and snapshot-driven

## Status

Accepted (2026-07-20) by issue #199. Extends ADR-0002's Pipeline seams and
ADR-0008's ASR recognition-session boundary.

## Context

Native streaming makes recognition overlap recording, while FoldWise still
allows a newer Dictation session to be captured before an older session has
finished. The existing flat `PipelineState` callback cannot distinguish late
events from different sessions, represent one session recording while another
finishes, or prevent an older result from stealing the Badge. At the same time,
the one-resident-engine and one-recognition-session invariants require FIFO ASR
admission without exposing runtime capability or admission state to Pipeline.

## Decision

Pipeline assigns one stable Dictation session identity when capture begins and
uses it through audio commands, ASR events, Pipeline state, Badge actions,
delivery, and History. Pipeline publishes immutable snapshots of its ordered
in-flight sessions rather than unrelated global state deltas. The newest
accepted session owns the Badge; an older success never interrupts it, while an
older outcome requiring user action waits until the newer session terminates.

Audio follows one capability-neutral path. The recorder emits ordered chunks
that Pipeline forwards immediately to the captured opaque ASR session. The
session boundary owns pre-admission buffering, serializes Feed, Finish, and
Cancel, and admits recognition FIFO. Native-streaming drivers may emit committed
whole-text updates; batch drivers emit only their authoritative final text.
Pipeline neither branches on recognition mode nor drops audio. Every session is
limited to ten minutes and reaching that limit performs Stop and finalization.

FoldWise accepts at most one session waiting behind the ASR-active session.
Capture and recognition for a newer session may overlap an older session's
Polish and delivery, but Polish, delivery, and History form one start-order
commit lane. A session captures its exact Dictation target, Mode, ASR selection,
and Effective ASR model at start. Delivery requests Cmd-V only while the exact
focused accessibility element is still the captured target; otherwise it falls
back to the clipboard without stealing focus.

Stop finalizes accepted audio. Cancel remains available until delivery begins;
it discards audio and transcript output and creates no History entry. An
unexpected capture failure after usable audio instead finalizes early. Raw audio
is erased at every ASR terminal and is never persisted or retained for retry.
Profile- and device-specific watchdogs turn overlong ASR work into failure and a
fatal-engine recovery gate rather than silently retrying or changing models.

Only ASR completion supplies raw text to Polish and delivery. A streaming failure
may retain its last committed snapshot as an incomplete, manually copyable
transcript, but it is neither delivered nor saved to History. Completed sessions
record the authoritative raw/final text, Mode attribution, captured and effective
ASR attribution, and truthful delivery outcome when History is enabled. Delivery
is `paste requested`, `clipboard only`, or recoverable `delivery failed`; FoldWise
never claims the target accepted a posted paste command.

## Consequences

- Badge presentation cannot be corrupted by late events from another session,
  and every Stop, Cancel, Copy retry, and deferred outcome targets one identity.
- Live recognition begins whenever FIFO admission permits it without reopening
  Pipeline's model/runtime boundary; batch and fallback sessions use the same
  orchestration with no fabricated live output.
- One waiting session and the ten-minute ceiling bound retained audio while
  preserving the existing silent double-tap workflow.
- Start-order downstream commits preserve deterministic paste and History order
  even though capture, ASR, and Polish may occupy different sessions at once.
- ASR watchdog thresholds become reviewed profile-and-device evidence rather
  than an arbitrary application-wide timeout.

## Rejected alternatives

- A flat global Pipeline state stream, because concurrent sessions can overwrite
  each other's presentation and accept actions intended for another session.
- Blocking every new capture until the whole previous Pipeline finishes, because
  it removes silent double-tap and needlessly idles ASR during Polish.
- Letting Pipeline inspect admission or recognition mode, because it leaks
  lifecycle/runtime policy across the opaque ASR session boundary.
- Pasting into whichever element happens to be focused at delivery, because a
  queued session can silently send dictated text to the wrong destination.
- Retrying failed audio through another model, because it changes the captured
  ASR contract and makes live and final text provenance disagree.
