# Prototype verdict

Question: Does the proposed five-step Guided setup state model make each
step's promise honest?

Verdict: Accepted with the human-selected order **Accessibility → Speech model
→ Microphone → Push-to-Talk shortcut → Polish**. The reducer's other contracts
stand: Accessibility is optional with Input Monitoring and Badge-only
fallbacks; starting the speech-model download advances its cursor while
readiness remains independent; Microphone is the sole hard gate; the shipped
shortcut is explicitly confirmed or replaced; and Polish is last and may be
declined.

Decisions to capture:

- Final Setup step order: Accessibility, Speech model, Microphone,
  Push-to-Talk shortcut, Polish.
- Whether shortcut confirmation remains a Setup step: Yes, fourth.
- Whether Accessibility and Input Monitoring remain one Setup step: Yes;
  Input Monitoring is a fallback inside Accessibility.
- What “completed but Dictation not ready” is allowed to mean: Every Setup step
  was visited, but the accepted speech-model download has not yet become ready.
- Any per-step completion or re-entry contract changed by the exercise: Only
  the order changed. The prototype's completion and re-entry contracts stand.
