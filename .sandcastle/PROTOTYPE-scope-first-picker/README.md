# PROTOTYPE — scope-first Sandcastle picker

This throwaway prototype answers one question: **what should the complete
Sandcastle CLI walk look and feel like when Work scope is the first decision
for every workflow?** It exercises scope selection, target entry, live GitHub
validation, resolved issue feedback, workflow and model choices, scope-specific
count behaviour, confirmation, cancellation, and recovery.

Run it from the repository root:

```sh
pnpm --dir .sandcastle prototype:scope-picker
```

Normal issue numbers and URLs are resolved from this repository with read-only
`gh` calls. The target field also accepts these prototype-only inputs so every
recovery path can be exercised without changing GitHub:

- `demo:network` — GitHub cannot be reached
- `demo:valid` — a valid target with eligible work
- `demo:empty` — a valid SPEC with no eligible descendants
- `demo:closed` — a closed target
- `demo:labels` — a target without `ready-for-agent`
- `demo:blocked` — a blocked target

The live repository-wide queue is validated as-is. If it is empty, its recovery
screen offers **Continue with demo queue** so the queue-only 1–50 count prompt
can still be exercised.

No selection is persisted and starting a run dispatches no agent. The final
screen only reports the plan the real runner would receive.
