# PROTOTYPE — what a wave-parallel run looks like in one terminal

Throwaway prototype for [#411](https://github.com/hadrysm/foldwise-voice/issues/411).
It answers one question: **what does the maintainer see while three agents,
a Planner and a Merger share a single terminal, and what tells them the wave is
healthy without opening a log file?**

Nothing here runs an agent, touches git, or calls GitHub. `script.mts` is a
scripted 10-item run over three waves against SPEC #371, written so that every
outcome the driver can produce actually appears — including a timeout, a crash,
a zero-commit item, a fan-in conflict, a transitive skip, a rejected plan and a
provably skipped Merger.

```sh
pnpm --dir .sandcastle prototype:wave-report -- --renderer=ledger --heartbeat=both
pnpm --dir .sandcastle prototype:wave-report -- --renderer=dashboard
pnpm --dir .sandcastle prototype:wave-report -- --renderer=report
```

`--speed=N` compresses the 84-minute run (default 150, so it replays in about
34 seconds; `--speed=800` is a fast skim that still shows heartbeats).
`--heartbeat=metronome|plain|alarm|both` switches between the rival liveness
signals; `both` is the one the maintainer chose.

## What the two renderers are for

**`ledger`** is append-only. Every line is written once and never rewritten;
in-flight items surface through a periodic heartbeat rather than a moving line.
The scrollback *is* the record.

**`dashboard`** pins one line per in-flight item to the bottom of the terminal
and repaints it with a spinner, elapsed time and the item's last tool call. It
is here to lose an argument honestly, not as a straw man — run it and watch
where the foreign lines land.

**`report`** prints only the end-of-run artifact, so it can be read against the
live view. Both come from the same `itemLine` in `render.mts`, which is the
proposal: one renderer, used live when an item settles and again in the report.

## Facts about Sandcastle 0.12.0 the design has to live with

Read off the installed package, not the docs.

1. **`LoggingOption` has two variants, not three.** `{ type: "file", path,
   verbose?, onAgentStreamEvent? }` and `{ type: "stdout", verbose? }`
   (`dist/index.d.ts:456`). There is no `{ type: "terminal" }`; #411's body is
   wrong on this.
2. **`stdout` mode is a Clack UI, not a stream of lines.** It resolves to
   `ClackDisplay` (`dist/index.js:1086`, `:2477`), which drives
   `clack.spinner()`, `clack.taskLog()`, `clack.intro()` and `clack.note()`
   (`dist/chunk-VOG34SRF.js:24995`). Three concurrent dispatches would not
   interleave lines — they would fight over the same cursor. **Concurrent items
   cannot use `stdout` mode.** That is a library constraint, not a design
   choice.
3. **`file` mode is not silent.** `printFileDisplayStartup`
   (`dist/index.js:904`) writes two lines to `console.log` on every dispatch —
   `[<name>] Started on branch <branch>` and a dim `  tail -f <path>` — before
   the file display is installed. The driver cannot suppress them through any
   option. Both renderers reproduce these verbatim, as `foreign` lines.
4. **`onAgentStreamEvent` exists only on the `file` variant**
   (`dist/index.d.ts:468`). It fires per `text` / `toolCall` / `raw` event, and
   errors thrown by the callback are swallowed. This is the only live signal a
   driver can get out of a concurrent item, and it is available precisely in the
   mode concurrency forces. It is what feeds the heartbeat's last-tool column.
5. **The default log path already separates concurrent items.** It is built from
   the branch and the agent name (`buildLogFilename`, `dist/index.js:913`), and
   #404 gives every item its own `sandcastle/<number>-<slug>` branch, so per-item
   log files are the default rather than something the driver has to arrange.

## What was decided

Both forks were put to the maintainer against these renderings.

- **Append-only ledger**, not a repainting dashboard, because the run is AFK.
  The maintainer starts a wave and leaves. What they need on return is a
  scrollback they can read top to bottom, not a block showing only *now*. A
  repainting block also has to share the cursor with fact 3 above, and it
  degrades to nothing when the output is piped.
- **Sparse metronome plus silence alarm** (`--heartbeat=both`). A one-line
  metronome every ten minutes proves the *driver* has a pulse; a warning when an
  item emits no stream event for five minutes, and a matching line when it
  resumes, proves the *agents* do. Roughly fourteen heartbeat lines across an
  84-minute run, and the loud ones are only the item that actually went quiet.
  Rejected: a two-minute per-item metronome, which produces ~120 lines and
  buries the record it lives in; and the alarm alone, which leaves a healthy run
  silent for fifteen minutes at a stretch.

## The claims this prototype is making

- **A heartbeat is not decoration, it is the liveness signal.** The body
  dispatches exactly twice, so a healthy item is silent for ten to fifteen
  minutes. Without a heartbeat that is indistinguishable from a hang.
- **The heartbeat's clock is elapsed against the item timeout**, because the
  timeout is the only thing that will end a hang — so the one number worth
  showing is how far off it is.
- **The log path is repeated where it becomes useful.** Sandcastle prints it
  once, at dispatch, an hour before anyone wants it. The driver repeats it as an
  indented line under a silence alarm and under every outcome worth opening a
  log for — `crashed`, `timed out`, `no commits`, `conflict rewound` — and
  nowhere else. An approved item never gets one: there is nothing to read.
- **The denominator does not move.** Mid-run progress is `n/10 settled` against
  the frozen selection; a transitive skip settles an item rather than shrinking
  the total, so the fraction only ever grows.
- **Nothing interrupts a sibling.** A failure prints a line and the wave carries
  on. The display never asks a question, because there is nobody there to answer
  it.
- **Seven outcomes, two phases, one bounce annotation.** The loop settles into
  `approved` / `crashed` / `timed out` / `no commits`; fan-in settles into
  `merged` / `conflict rewound`; and an item that was never dispatched is
  `skipped`. A bounce annotates an outcome, it is not one. `timed out` carries
  its own glyph and colour and never shares either with `crashed`.
