# Usage statistics for foldwise-voice: words, WPM, and streaks

**Summary:** The screenshot's three stats — "33 total words", "144 wpm", "1 day"
— are Wispr Flow's headline "Your Usage" card: a lifetime word count, an average
*dictation* speed, and a consecutive-day streak. For foldwise-voice these are
**not a new data-collection problem**: every input they need is already on disk.
`HistoryEntry` already stores `createdAt`, `wordCount`, and `durationMs` for every
session (`History.swift:13`), the pipeline fills them at one point
(`Pipeline.swift:253`), and the Settings window already holds the loaded rows
(`SettingsModel.swift:116`). So the whole feature is a **pure aggregation over the
existing history store** — mirror the `HistoryFilter` pattern, add a card, done.
The one real decision is whether stats are a *projection of kept history* (honest,
zero new state, shrinks when history is off/pruned) or a *separate always-on
odometer* (survives history-off, like Wispr — but is new retained data). This note
pins Wispr's definitions to their docs and turns them into a local-first design.
**Date:** 2026-07-07

This is an engineering note, not a survey. Every non-obvious claim is tied to a
primary source inline; the full URL list is in *Further reading*. Where a claim
could not be pinned to a primary source, it says so at the end. It is the sibling
of `dictation-history-storage.md` (the store this feature reads) — read that first.

---

## 1. What Wispr's three stats actually mean

Wispr Flow's in-app **"Your Usage" tab** (in the Insights section, desktop only)
is the surface the screenshot comes from. Its documented definitions:

- **Total words dictated** — "A running count of every word you've dictated using
  Flow" ([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow)).
  It is a **lifetime running total**, contextualized by a separate month-over-month
  badge ("word count so far this month against your full word count from the
  previous month"). Critically, this counter is **always on**: "Wispr may collect
  usage statistics such as the number of words you have dictated, **regardless of
  your Privacy Mode or Private Cloud Sync settings**"
  ([Data controls](https://wisprflow.ai/data-controls)). So Wispr counts words even
  when it keeps *no history at all* — the counter is decoupled from the record list.
  That decoupling is the crux of the design decision in §3.

- **WPM** — "An animated semicircular gauge shows your **average dictation speed**
  as a rounded whole number, plus your percentile compared to global keyboard
  typists (e.g., 'Top 4%')"
  ([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow)).
  It is a **speaking-speed** metric (words per minute *of dictation*), not
  wall-clock, updated after each dictation. Wispr does **not** publish the literal
  arithmetic (words ÷ seconds); treat the exact denominator as inferred. The
  percentile is ranked against keyboard typists, not other users, on this stated
  baseline: "most keyboard typists average around **52 WPM**, [so] dictating at 100
  WPM puts you in the top 4%, and 150 WPM puts you in the top 0.5%" (same page).

- **Streak ("1 day")** — a "calendar view of your dictation activity. Days in your
  current streak glow; the glow only appears when your current streak is greater
  than 1 day" and "ends on the most recent day you dictated and does not extend to
  today if you haven't dictated yet"
  ([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow)).
  It's a **consecutive-day** count in the user's local calendar. "1 day" is
  consistent with a streak of exactly one (the glow only kicks in above 1).

Two things the screenshot's model does **not** include, worth knowing:

- **"Time saved" is marketing, not an in-app stat.** The Usage tab surfaces WPM,
  corrections, total words, app breakdown, and streak — **no minutes-saved metric**
  ([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow)).
  "Time saved" lives only in Wispr's marketing: "The average person types about 40
  words per minute… we speak at 150 words per minute or more… nearly four times
  faster," with the worked example "replacing two hours of typing reports with 30
  minutes of spoken dictation"
  ([Voice productivity blog](https://wisprflow.ai/post/voice-productivity)). Note
  the app and the blog cite **different** typing baselines — 52 WPM in the stats
  card, 40 WPM in marketing.

- **superwhisper ships none of this.** Its docs index lists no personal
  words/WPM/streak/time-saved page — only History, History Management, and an
  Enterprise-only *team* usage dashboard
  ([superwhisper docs index](https://superwhisper.com/docs/llms.txt)). The
  words/day / time-saved numbers people attribute to superwhisper come from a
  **third-party** toolkit that parses its local recordings
  ([crarau/superwhisper-analysis](https://github.com/crarau/superwhisper-analysis)),
  not the app. So on stats, Wispr is the only real reference; superwhisper is a
  non-example (it ships history, which foldwise-voice already has).

---

## 2. The load-bearing local fact: the data already exists

foldwise-voice already records, per dictation session, exactly the fields a stats
card needs. From `HistoryEntry` (`History.swift:13`):

| `HistoryEntry` field | Type | Written at | Feeds |
|---|---|---|---|
| `createdAt` | `Date` | `Pipeline.swift:255` (`Date()`) | day-grouping, active-days, streak |
| `wordCount` | `Int?` | `Pipeline.swift:260` — `text.split(whereSeparator: { $0.isWhitespace }).count` | total words, WPM numerator |
| `durationMs` | `Int?` | `Pipeline.swift:262` — `samples.count / 16000 * 1000` | WPM denominator, time-saved |
| `modeName` | `String` | `Pipeline.swift:259` | optional per-Mode breakdown |
| `isPolished` | `Bool` | `Pipeline.swift:258` | optional raw-vs-polished split |

And the plumbing to reach them already exists too:

- The store loads them: `JSONLHistoryStore.load() -> [HistoryEntry]`
  (`History.swift:179`), reading `history.jsonl` in
  `~/Library/Application Support/FoldWise Voice/` (`History.swift:150`).
- The Settings window **already holds the loaded rows**: `@Published var
  historyEntries: [HistoryEntry]` is populated when the window opens and re-read
  after mutations (`SettingsModel.swift:116`). A stats card reads straight from it.
- Live updates are free: the store's `onAppend` observer already prepends
  new sessions to the open pane (`History.swift:119`); a card bound to
  `historyEntries` recomputes with it. **No new observer, no new file, no schema
  change, no migration.**

There is **no existing aggregate counter, analytics, or streak state** anywhere in
the codebase — this is greenfield, but greenfield *on top of data you already
keep*, not new instrumentation.

### Three caveats the code forces you to handle

1. **`wordCount` and `durationMs` are `Optional`.** Older or future rows may hold
   `nil`. Aggregation must treat `nil` as "skip", not "0-crash": sum `wordCount ??
   0`, and include a row in the WPM denominator **only if it has both** a
   `wordCount` and a `durationMs > 0`.

2. **`wordCount` counts the *shown* text, not the spoken words.** Line 260 counts
   `text` — the polished result when Polish survived, the raw transcript otherwise.
   For an in-place Mode (`Clean`) that ≈ spoken words; for an **expanding Mode**
   (`Email`, `Bullets`) the polished text can be much longer or shorter than what
   was said (`CONTEXT.md` — Expanding Mode). So a WPM built on `wordCount` is
   *output* words per minute, which overstates speaking rate for expanding Modes.
   For an honest "how fast do you dictate" number, count `rawText` (the actual
   transcript) for the WPM numerator; keep `wordCount` for the "words produced"
   headline. This is a real modeling choice, not a rounding detail — call it out in
   the UI label ("words dictated" vs "your speaking speed").

3. **`durationMs` is hold-to-talk time, including pauses and silence.** It's the
   length of the recorded buffer (`samples.count / 16000 * 1000`), so it counts
   the leading/trailing silence and mid-sentence pauses inside a held hotkey. Your
   WPM will therefore read **lower** than Wispr's "speaking speed" (Wispr appears
   to measure tighter speech time). That's the honest effective rate for a
   push-to-talk app — but don't be surprised it undercuts Wispr's numbers, and
   don't "fix" it by inventing a tighter duration you don't measure. (The pipeline
   already drops sub-0.1s and near-silent captures at `Pipeline.swift:198`, so
   stored `durationMs` is always ≥ 100 ms — no divide-by-zero in practice, but
   guard it anyway.)

---

## 3. The one real decision: projection vs. odometer

Everything else is mechanical; this is the choice that shapes the feature.

| | **A. Projection over kept history** (recommended default) | **B. Always-on lifetime odometer** (Wispr's model) |
|---|---|---|
| What it is | `stats = f(historyEntries)` — a pure lens over rows already on disk | a tiny `stats.json` of monotonic totals, incremented at the pipeline record point independent of the history entry |
| New persisted state | **None** | Yes — aggregate counts (no text, no audio) |
| Survives "Save history" **off**? | **No** — goes to 0 (the pipeline writes nothing, `Pipeline.swift:252`) | **Yes** — matches Wispr counting "regardless of Privacy Mode" |
| Survives retention pruning / row delete? | No — totals shrink with the store (30-day default window) | Yes — odometer never decrements |
| "Total words" means | "words in the history you've kept" (window-scoped) | "words ever dictated" (true lifetime) |
| Privacy surface | Inherits history's exactly — nothing new retained | New: aggregates persist even with history off (disclose it, as Wispr does) |
| Effort / risk | Pure function + a card; unit-tested like `HistoryFilter` | + a persisted counter, its own load/save, its own tests, a new privacy line |

**Recommendation: ship A first.** It is the smallest honest step, adds no new
stored data or privacy surface, respects the local-first posture (the stats are
just a view of data you already keep), and matches the repo's pure-function-tested
convention (`HistoryFilter`, `PolishStatus`, `RetentionWindow` are all pure and
unit-tested apart from the SwiftUI view). Label it honestly — under a 30-day
retention it's "your last 30 days," not an all-time odometer — and that honesty is
a *feature* for a privacy-first app, not a shortfall.

**Add B only if you deliberately want the gamified lifetime numbers to survive
history being off** (the Wispr framing). If you do: keep it **aggregates-only** (a
running `lifetimeWords`, `lifetimeDurationMs`, a set of active-day dates, and the
current streak state — never any transcript text or audio), increment it at the
single record point in `Pipeline.process` right next to the history append, gate it
on its *own* disclosed switch rather than piggy-backing the history switch, and
document it exactly as Wispr does ("we keep a count of words dictated even with
history off"). B is a considered, disclosed choice — not a default — because it
introduces the first piece of state that outlives "history off."

A pragmatic middle path: **A for words/WPM/active-days (window-scoped, no new
state), plus a single persisted `{ lifetimeWords, currentStreak, lastActiveDay }`**
if and only if the lifetime streak matters to you — a streak is the one stat
projection can't do faithfully once retention prunes days out of the window.

---

## 4. Per-stat formulas and honest labels

All defensible from the sources in §1; each carries the caveat the code imposes.

**Total words.** `entries.reduce(0) { $0 + ($1.wordCount ?? 0) }`. Label "words
dictated". Window-scoped under Option A. (Wispr: "a running count of every word
you've dictated" — [Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow).)

**WPM.** Aggregate — **not** an average of per-row WPMs (short rows explode and
dominate a mean). Sum over rows that have both fields:

```
totalWords   = Σ wordCount   (over rows with wordCount AND durationMs > 0)
totalMinutes = Σ durationMs / 60000   (same rows)
WPM          = totalWords / totalMinutes        // nil if totalMinutes == 0
```

Prefer `rawText`'s word count as the numerator for a true *speaking* rate (caveat
2, §2). Optionally show Wispr's keyboard-typist comparison, but cite the baseline
honestly: **52 WPM** is Wispr's in-app figure
([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow));
40 WPM is its marketing figure
([blog](https://wisprflow.ai/post/voice-productivity)). Pick one and state it. Note
that hold-to-talk `durationMs` biases this low (caveat 3).

**Active days / streak.** Two flavors — decide which "day" means:

- *Active days* (matches a plain "N days" reading): `Set(entries.map {
  Calendar.current.startOfDay(for: $0.createdAt) }).count`.
- *Consecutive-day streak* (Wispr's meaning): from `startOfDay(now)`, walk
  backwards counting unbroken days present in that set; the streak "ends on the
  most recent day you dictated and does not extend to today if you haven't dictated
  yet" ([Your Usage tab](https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow)),
  so today counts only if there's an entry today. Use `Calendar.current` +
  `startOfDay` so DST and timezone are handled. Under Option A a 30-day retention
  caps the streak at 30; a true lifetime streak needs Option B's persisted
  `lastActiveDay` + `currentStreak` (the one number projection can't fake).

**Time saved (optional; Wispr's marketing metric).** Not in Wispr's in-app tab —
add it only if you want the "you saved X minutes" framing, and frame it as an
*estimate against an assumed typing speed*, never a measured fact (the repo's
honesty ethos — cf. the "English" ASR-label decision). You have an advantage over
Wispr's `words/150` estimate: you measure real dictation time.

```
minutesSaved = totalWords / typingWPM  -  totalMinutes   // real dictation time
```

Pick and disclose one `typingWPM` (52 is the more defensible "average keyboard
typist"; 40 is Wispr's rhetorical number).

---

## 5. Recommendation for foldwise-voice

**A pure `UsageStats` aggregator + a card bound to `historyEntries`.** Mirror the
`HistoryFilter` shape (`History.swift:348`): a pure function, unit-tested apart
from the untested SwiftUI view.

```swift
/// Aggregate usage stats over recorded dictations. Pure, so the numbers are
/// unit-tested apart from the SwiftUI card — the `HistoryFilter` pattern.
struct UsageStats: Equatable {
    var totalWords: Int
    var totalMinutes: Double
    var wordsPerMinute: Double?     // nil when no timed entry exists
    var activeDays: Int
    var currentStreak: Int
    var estimatedMinutesSaved: Double?  // nil unless a typing baseline is supplied
}

enum UsageStatsAggregator {
    static func compute(
        from entries: [HistoryEntry],
        now: Date,
        calendar: Calendar = .current,
        typingWPM: Double? = nil    // e.g. 52 — Wispr's in-app keyboard baseline
    ) -> UsageStats {
        var words = 0
        var timedWords = 0, timedMs = 0
        var days: Set<Date> = []
        for e in entries {
            let wc = e.wordCount ?? 0
            words += wc
            if let ms = e.durationMs, ms > 0 { timedWords += wc; timedMs += ms }
            days.insert(calendar.startOfDay(for: e.createdAt))
        }
        let timedMinutes = Double(timedMs) / 60_000
        let wpm = timedMinutes > 0 ? Double(timedWords) / timedMinutes : nil
        // streak: walk back from startOfDay(now) while `days` contains the day.
        var streak = 0
        var day = calendar.startOfDay(for: now)
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        let saved = typingWPM.map { Double(words) / $0 - Double(timedMs) / 60_000 }
        return UsageStats(
            totalWords: words, totalMinutes: Double(timedMs) / 60_000,
            wordsPerMinute: wpm, activeDays: days.count,
            currentStreak: streak, estimatedMinutesSaved: saved
        )
    }
}
```

(For a true *speaking* WPM, pass a spoken-word count derived from `rawText` rather
than `wordCount` — see caveat 2. The sketch uses `wordCount` for brevity.)

**Where to render it.** In order of increasing scope:

1. **A compact card at the top of the History pane** (`HistoryView`, above the
   "Save dictation history" switch). It reads `model.historyEntries` — already
   loaded, already live — and sits next to the list it summarizes. **Smallest,
   ships today, zero plumbing.** This is the recommended first surface.
2. **A summary card on the Home pane** (`SettingsModel.Pane.home`,
   `SettingsModel.swift:9`) for at-a-glance numbers on open.
3. **A dedicated `.stats` pane** — add `case stats = "Stats"` to
   `SettingsModel.Pane` (icon e.g. `chart.bar.fill`, `SettingsModel.swift:8`) and a
   render arm in `SettingsView`. This is the Wispr "Your Usage" analog and the home
   for later gamified extras (heatmap, per-Mode breakdown, share cards). **Defer
   it** — it's the surface, not the feature; land the aggregator and a card first.

**Testing.** `UsageStatsAggregator.compute` is pure → an XCTest file
(`UsageStatsTests.swift`) modeled on `HistoryFilterTests.swift`: feed fixture
entries + a fixed `now`, assert each number. Cover the caveats explicitly — `nil`
`wordCount`/`durationMs` skipped, empty store → all zeroes, WPM excludes
untimed rows, streak breaks across a missing day, streak respects `startOfDay`
across a DST boundary, "today with no entry" doesn't extend the streak.

**Privacy.** Under Option A the feature retains *nothing new* — it's arithmetic
over rows the user already chose to keep, honoring the "Save history" switch
(`Pipeline.swift:252`) and retention window for free. No audio, no text, nothing
leaves the machine. If you take Option B's odometer, keep it aggregates-only and
disclose it — the moment you count words with history *off*, you owe the user the
same sentence Wispr writes on its data-controls page.

---

## 6. Side-by-side

| Dimension | Wispr Flow | foldwise-voice (recommended) |
|---|---|---|
| Words | lifetime running total, always-on counter | Σ `wordCount` over kept history (window-scoped); lifetime only if you add the odometer |
| WPM | "average dictation speed" gauge + percentile vs 52-WPM typists | Σwords / Σminutes over timed rows; hold-to-talk time (reads lower); optional 52-WPM comparison |
| Streak | consecutive local-calendar days, glow > 1 day | walk-back over `startOfDay(createdAt)` set; lifetime streak needs a persisted `lastActiveDay` |
| Time saved | marketing only (40 & 150 WPM), not in-app | optional; you have *real* dictation minutes, so `words/typingWPM − minutes` |
| Where | in-app "Your Usage" tab + share carousel + admin dashboard | History-pane card first; a `.stats` pane later |
| Counts with history/privacy off? | Yes (words counter is decoupled) | No under Option A (honest); Yes only if you add the disclosed odometer |
| Stored data | server-synced | none new (Option A) / tiny local aggregates (Option B) |

**Net design:** a pure `UsageStats` aggregator over the existing `HistoryEntry`
stream, rendered as a card bound to the already-loaded `historyEntries`, honestly
labeled as window-scoped, unit-tested like `HistoryFilter` — Wispr's words/WPM/
streak card without its server, its always-on counter, or its baseline
inconsistency. Reach for a persisted odometer only for a lifetime streak or to make
the numbers survive "history off", and disclose it when you do.

---

## Further reading (primary sources)

Wispr Flow:
- Your Usage tab (WPM gauge, percentile vs 52-WPM typists, total-words = lifetime running count, streak heatmap, share carousel): <https://docs.wisprflow.ai/articles/8760230576-your-usage-tab-track-your-dictation-stats-in-wispr-flow>
- Data controls ("collect… number of words you have dictated, regardless of your Privacy Mode or Private Cloud Sync settings"): <https://wisprflow.ai/data-controls>
- Voice-productivity blog (40 WPM typing / 150 WPM speaking / "4x faster" / time-saved example): <https://wisprflow.ai/post/voice-productivity>
- Homepage / features ("4x faster than your keyboard"): <https://wisprflow.ai/> · <https://wisprflow.ai/features>
- Enterprise/team admin dashboard (separate from personal stats): <https://admin.wisprflow.ai/>

superwhisper (non-example — ships history, not personal stats):
- Docs index (no personal words/WPM/streak page; History + Enterprise team analytics only): <https://superwhisper.com/docs/llms.txt>
- Third-party analytics toolkit (community, NOT a superwhisper feature): <https://github.com/crarau/superwhisper-analysis>

foldwise-voice (the code this builds on):
- `HistoryEntry` model + `HistoryStore`/`JSONLHistoryStore` + `HistoryFilter`: `Sources/FoldWiseVoiceKit/History.swift`
- Record point (word count `:260`, duration `:262`, save gate `:252`): `Sources/FoldWiseVoiceKit/Pipeline.swift:195`
- Loaded rows + Settings panes: `Sources/FoldWiseVoiceKit/SettingsModel.swift:8` / `:116`
- Sibling note on the store itself: `docs/research/dictation-history-storage.md`

### Claims that could not be verified against a primary source

- **The literal WPM arithmetic.** Wispr labels it "average dictation speed" and
  computes it per-dictation, language-aware, but never publishes words ÷ seconds.
  The denominator (speaking time) is inferred, not stated.
- **Exact streak reset mechanics** (calendar-day vs calendar-week, local timezone).
  The consecutive-day heatmap and the "glow > 1 day / ends on last dictated day"
  behavior are doc-confirmed; the precise "resets on a skipped calendar day/week in
  local timezone" wording came from a search snippet, not a quotable page — reported,
  not doc-confirmed.
- **A first-party weekly recap email** carrying these stats. Documented surfaces are
  the in-app Usage tab and share carousel; an emailed recap could not be confirmed
  first-party.
- **superwhisper native personal stats** — confirmed *absent* from its docs; the
  words/day and time-saved figures circulating online are from the third-party
  `superwhisper-analysis` toolkit, not the app.
</content>
</invoke>
