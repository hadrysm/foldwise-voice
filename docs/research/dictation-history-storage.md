# How Wispr Flow and superwhisper store dictation history

**Summary:** superwhisper is fully local — every dictation is a timestamped
folder of `audio.m4a` + `meta.json` under `~/Documents/superwhisper/recordings`,
kept forever unless you delete it. Wispr Flow is cloud-assisted — history is a
server-synced list gated by two independent switches (Privacy Mode, Cloud Sync),
with a first-class per-row flag/copy/delete UI worth copying. This note pins both
models to their docs and turns them into a local-first history design for
foldwise-voice.
**Date:** 2026-07-06

This is an engineering note, not a survey. Every non-obvious claim is tied to a
primary source inline; the full URL list is in *Further reading*. Where a claim
could not be pinned to a primary source, it says so at the end.

---

## 1. What "history" means in each app

**superwhisper (local-first).** History is not a database feature bolted onto a
cloud service — it *is* the filesystem. Every dictation writes a folder to disk;
the History panel is just a browser over that folder. superwhisper is explicit
that "Transcripts, audio recordings, modes, vocabulary, and app settings live
locally on your machine" and "we don't store your transcripts, audio, modes, or
vocabulary on our servers"
([Account deletion](https://superwhisper.com/docs/security/account-deletion.md)).
With local models "no audio or text ever leaves your machine"
([Sensitive data](https://superwhisper.com/docs/security/sensitive-data.md)).
This is the same posture as foldwise-voice, so superwhisper is the closer
reference model of the two.

**Wispr Flow (cloud-assisted).** History is a **server-synced record list**,
because Wispr's transcription runs server-side by default. The interesting design
is that Wispr splits history into two *independent* concerns behind two toggles:
whether data is used to train models (**Privacy Mode**) and whether data is
stored on Wispr's servers at all (**Cloud Sync**). Cloud Sync "controls whether
your transcription data (transcripts, audio, dictation history) is stored on
Wispr's servers to power features such as cross-device sync"
([Security & compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq)).
So for Wispr you must distinguish what is **collected** (sent to servers to
transcribe) from what is **stored** (retained as history) — they are separately
controllable.

---

## 2. superwhisper: how it collects & stores history

**On-disk location (the load-bearing fact).** History lives at
`~/Documents/superwhisper/recordings`, where `~` is the user's home folder, and
this "can be changed in Superwhisper's settings"
([History management](https://superwhisper.com/docs/get-started/history-management)).
Because the default is under `~/Documents`, if iCloud Drive syncs the Documents
folder those recordings sync to iCloud and other signed-in devices — a real
privacy footgun that superwhisper's own feedback board flags (see *unverified*
note at the end; treat the iCloud-sync detail as reported, not doc-confirmed).

**Record shape (per dictation).** Each dictation is a **timestamped subfolder**
holding the audio file plus a `meta.json`. superwhisper writes `meta.json` after
transcription completes with fields including `result` (the final text),
`rawResult`/`llmResult` (raw transcription vs. AI-processed text), `datetime`,
`duration`, `processingTime`, and `segments`
([alfred-superwhisper README, ognistik](https://github.com/ognistik/alfred-superwhisper/blob/main/README.md)
— a third-party tool that parses these files, used here as the on-disk-format
source since superwhisper's own docs don't enumerate the JSON fields). The app's
own docs corroborate the *displayed* shape: the History panel's right sidebar
shows "recording details," "processing information," and the "mode configuration
used for the dictation," and entries expose both the "original voice
transcription" and the "AI-processed result"
([History panel](https://superwhisper.com/docs/get-started/interface-history.md)).
So a superwhisper history entry contains: **audio + raw transcript + polished
result + mode used + timestamp + duration + processing time + segments.** It
keeps *both* the raw and polished text — a decision foldwise-voice should mirror.

**What's kept: audio AND text.** Both the audio recording and its transcription
data are retained; this is what makes "Process Again" work — you "Right-click on
the desired recording and select 'Process Again'" to re-run it under a different
mode
([Transcribe history](https://superwhisper.com/docs/get-started/transcribe-history.md)).
Retaining audio is the feature that costs the most disk and the most privacy.

**Retention / auto-delete.** For individuals there is **no built-in retention or
scheduled cleanup** — "Superwhisper does not offer a built-in feature to
bulk-delete or schedule cleanup," and the docs' workaround is a user-run `cron`
job that deletes recording folders "older than 1 day" (customizable)
([History management](https://superwhisper.com/docs/get-started/history-management)).
Only the **Enterprise** tier gets real retention enforcement: admins can "Set the
maximum duration that members can keep recordings on disk. Recordings older than
this are deleted automatically by the app on each member's machine," with a fixed
enum — "No restriction (default), 1 day, 1 week, 2 weeks, 1 month, 6 months, 1
year" — and it "applies to recordings stored locally by Superwhisper, not to
anything members have exported"
([Enterprise configuration](https://superwhisper.com/docs/enterprise/configuration.md)).
The default is **no restriction (keep forever)**.

**Delete / export.** Deletion is per-entry via the History panel (right-click →
delete) or by using "the History Management feature within the app," or simply
uninstalling
([Account deletion](https://superwhisper.com/docs/security/account-deletion.md)).
There is no first-class export beyond "the files are already on disk as JSON +
audio, go read them."

**Per-entry actions in the UI.** Right-click a dictation to "Process Again"
(reprocess), and to "Report Issue" — superwhisper's built-in *flag/report* path,
which "Report[s] errors" for a dictation
([History panel](https://superwhisper.com/docs/get-started/interface-history.md)).
Copy toggles between the voice result and the AI result then uses a copy button.
Search exists but is limited: "Use the search field on the left sidebar to
quickly find specific recordings based on your original voice input" — and,
critically, "Search only filters original dictation, not AI-processed results."

**Privacy default.** History (including audio) is **on by default / opt-out.**
The app "automatically saves your dictations every few seconds"
([Troubleshooting](https://superwhisper.com/docs/common-issues/troubleshooting)),
and account deletion "does not affect this local data"
([Account deletion](https://superwhisper.com/docs/security/account-deletion.md)).
The docs' own recommendation for sensitive environments is to "review your
history retention practices" and actively delete
([Sensitive data](https://superwhisper.com/docs/security/sensitive-data.md)) —
i.e. the burden is on the user to turn it down.

---

## 3. Wispr Flow: how it collects & stores history

**Collected vs. stored — keep these separate.** Because transcription is
server-side, audio and transcript are *sent to Wispr's servers to be processed*
regardless of history settings. Whether they are then *retained* is a separate
choice governed by Cloud Sync. Two switches, in Settings → Data and Privacy
([Data controls](https://wisprflow.ai/data-controls)):

- **Privacy Mode** (default **off**): when on, "none of your dictation data
  (i.e. audio, transcript, edits) will be used to evaluate, train, or improve AI
  models," and Wispr keeps "nothing—no audio, no transcripts, no edits"
  ([Data controls](https://wisprflow.ai/data-controls)). When off, your data "may
  be used to evaluate, train, and improve Wispr features and AI models."
- **Cloud Sync** (server storage): "controls whether your transcription data
  (transcripts, audio, dictation history) is stored on Wispr's servers." "When
  disabled, audio and transcripts are processed in real time and discarded after
  each request"
  ([Security & compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq)).

"Enable Privacy Mode and disable Cloud Sync for zero data retention"
([Privacy](https://wisprflow.ai/privacy)). Note the always-collected residue:
"Wispr may collect usage statistics such as the number of words you have
dictated, regardless of your Privacy Mode or Cloud Sync settings"
([Data controls](https://wisprflow.ai/data-controls)).

**Local storage controls (desktop).** Separately from Cloud Sync, desktop users
pick a **local** retention policy in Settings → Data and Privacy, with three
options: **"Store data locally" (default)**, "Auto-delete local data every 24
hours," and "Never store data locally." "Local data storage controls what's kept
on this device. It is separate from Cloud Sync, which controls whether
transcription data is stored on Wispr's servers"
([Delete transcripts and history](https://docs.wisprflow.ai/articles/4465314211-delete-transcripts-and-history-in-wispr-flow)).
The **24-hour auto-delete** is Wispr's answer to superwhisper's "keep forever"
default, and it is the single most copyable retention idea here.

**Retention windows (server-side).** Wispr's Privacy Policy does **not** publish
an explicit audio/transcript retention window — it states only that it retains
personal data "only for as long as is necessary" and that Customer Content shared
with third-party model providers "is generally deleted within 30 days, subject to
the provider's applicable retention practices"
([Privacy policy](https://wisprflow.ai/privacy-policy)). So the one concrete
number is **30 days at subprocessors**; the app-visible history itself is "per
the published Privacy Policy" with no hard window
([Security & compliance FAQ](https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq)).
Wispr also states "zero data retention agreements with all third-party AI
providers"
([Data controls](https://wisprflow.ai/data-controls)) — note this reads as in
tension with the "generally deleted within 30 days" line in the policy; treat the
30-day figure as the conservative primary-source number.

**History UI, deletion, and the flag/report action (the part to copy).** The
history panel is opened from the Home/sidebar. Per-entry actions on Mac/Windows:
"Hover over a transcript and click the three-dot menu (⋯), then select 'Delete
transcript' and confirm," swipe/row actions expose "Report, Retry, and Copy," and
dismissed entries show "This transcription was dismissed" with a "Recover" link
([Delete transcripts and history](https://docs.wisprflow.ai/articles/4465314211-delete-transcripts-and-history-in-wispr-flow)).
The **flag** is a dedicated icon: "the flag icon appears next to transcripts in
the transcript popup or history panel," "appears on all entries, including failed
transcriptions," and "Flagged transcripts are used to improve the product… may be
reviewed by the Wispr Flow team. Only flag transcripts you're comfortable
sharing"
([Getting help: reporting & flagging](https://docs.wisprflow.ai/articles/7837779518-getting-help-with-wispr-flow-reporting-flagging-and-contacting-support)).
**This hover → copy/flag/three-dot-overflow row is exactly the screenshot's
interaction model.**

**Privacy default.** History/storage is **on by default**: Privacy Mode ships
**off**, Cloud Sync/local storage default to **storing** data. Zero retention is
opt-in and requires flipping both switches.

---

## 4. Side-by-side

| Dimension | superwhisper | Wispr Flow |
|---|---|---|
| Storage location | Local only: `~/Documents/superwhisper/recordings` (relocatable) | On-device + Wispr servers (Cloud Sync); server is default |
| Audio retained? | Yes, by default (enables "Process Again") | Yes if Cloud Sync/local-store on; discarded in real time if off |
| Transcript retained? | Yes — keeps **both** raw + AI-polished | Yes if stored; nothing kept under Privacy Mode + Cloud Sync off |
| Retention window | None for individuals (keep forever); Enterprise enum 1 day…1 year, default *no restriction* | Local: keep / **auto-delete 24h** / never. Server: no published window; subprocessors "generally… within 30 days" |
| Search | Yes, but original dictation only (not AI result) | Yes (history panel) |
| Per-entry actions | Process Again, Report Issue, delete, copy (voice/AI toggle) | Copy, **Flag** (report for review), Delete, Retry, Recover; hover + three-dot overflow |
| Privacy default | History on / opt-out; audio saved automatically | Storage on / opt-out; Privacy Mode off by default |
| Export | Files already on disk (JSON + audio) | Full history export when Cloud Sync on |

Two takeaways for foldwise-voice: superwhisper proves the **local folder-of-JSON**
model works and that keeping *both* raw and polished text is valuable; Wispr
proves the **row-level hover UI (copy / flag / overflow)** the screenshot wants
and the **24-hour auto-delete** retention default worth adopting.

---

## 5. The history-record data model (to reproduce the screenshot)

The screenshot is a date-grouped list ("TODAY"), each row = timestamp +
transcribed text, with hover actions copy / flag / overflow. Minimum fields to
render that, plus the "worth-having" ones both reference apps keep:

| Field | Why | Source of the idea |
|---|---|---|
| `id` (UUID) | stable row identity for actions | — |
| `createdAt` (Date) | the row's timestamp **and** the "TODAY / date" grouping key | superwhisper `datetime` |
| `text` (String) | the row's visible transcribed text | both |
| `rawText` (String) | pre-Polish transcript, so you can show/copy either | superwhisper `rawResult` vs `llmResult` |
| `isPolished` (Bool) | did the LLM run? drives a raw/polished toggle | superwhisper raw vs AI result |
| `modeName` (String) | which Mode/profile produced it (already a first-class concept) | superwhisper "mode used" |
| `sourceApp` (String?) | app that was focused at insertion (nice for search/filter) | superwhisper "captured context" |
| `durationMs` / `wordCount` (Int) | cheap metadata for the row + stats | superwhisper `duration`; Wispr word-count stat |
| `flagged` (Bool) + `flagReason` (String?) | powers the screenshot's flag action (see §6) | Wispr flag |

**Grouping/UI:** group rows by `Calendar.startOfDay(for: createdAt)` and render
"TODAY / YESTERDAY / <date>" headers. **Copy** → put `text` (or `rawText` per a
toggle) on `NSPasteboard`. **Flag** → set `flagged = true`, optionally capture a
reason. **Overflow ("…")** → delete, copy-raw-vs-polished, re-insert, re-run
Polish (foldwise-voice's local analog of "Process Again"), reveal-in-Finder if
you keep files. Deliberately **omit audio** from the default record (see §6).

---

## 6. Recommendation for foldwise-voice

foldwise-voice is Swift / macOS 14+ / SwiftUI, local-first, currently persisting a
single `modes.json` via `Codable`. A history feature must not break the privacy
posture (nothing leaves the machine) and should not force a heavy new dependency.

**Storage choice.** Three realistic options:

- **Append-only JSONL** (`~/Library/Application Support/FoldWise Voice/history.jsonl`,
  one JSON object per line). Zero new dependency, matches the existing `Codable`
  habit, trivially appendable at pipeline end, and mirrors superwhisper's
  "folder of JSON" ethos. Weakness: no indexed search, and you rewrite the whole
  file to delete a row (fine at hundreds–low-thousands of entries).
- **SQLite via GRDB.** Proper indexed queries, FTS5 full-text search over
  transcripts, cheap per-row delete, easy retention sweeps (`DELETE WHERE
  createdAt < ?`). Cost: a real dependency and the app's first database.
- **SwiftData.** Native, SwiftUI-friendly `@Query` binding. Cost: it is the
  heaviest conceptual jump from a flat file, migrations are opaque, and it pulls
  the app's persistence model toward a framework the rest of the code doesn't use.

**Recommendation: start with JSONL, design the row as a `Codable` struct, and
keep a clean `HistoryStore` protocol so a GRDB/SQLite backend can slot in when
search or volume demands it.** Rationale: it is the smallest step from today's
`modes.json`, adds no dependency, and the screenshot's UI (date-grouped list,
in-memory filter) needs no SQL at the volumes a single-user dictation app
produces. Promote to GRDB the moment you want fast full-text search or the file
crosses tens of thousands of rows. (SwiftData is the option to *avoid* first: it
would be the only framework-backed store in an otherwise plain-`Codable`
codebase.)

**Proposed schema** (the §5 struct, serialized one-per-line):

```swift
struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var text: String          // shown text (polished if it ran, else raw)
    var rawText: String       // pre-Polish transcript
    var isPolished: Bool
    var modeName: String
    var sourceApp: String?
    var durationMs: Int?
    var wordCount: Int?
    var flagged: Bool = false
    var flagReason: String?
}
```

**Where to hook in the pipeline.** At the single point where the final text is
produced in `Pipeline.process(_:mode:)` — after Polish resolves (or after the
raw-transcript fallback fires). That is where you already have raw transcript,
polished result, the `Mode`, and can grab the focused app. Append one
`HistoryEntry` there. Do it *after* insertion so a history write never delays the
paste, and make the append best-effort (a failed history write must never break
dictation).

**Retention default + user control.** Follow Wispr, not superwhisper's
keep-forever: ship a **sane default retention** and a visible control. Concretely,
a Settings pane with "Keep history: **30 days** (default) / 7 days / 90 days /
Forever / Off," plus Wispr's "auto-delete" idea. Run the sweep on launch (delete
entries older than the window). "Off" must mean *don't even write the file* —
which is the real privacy switch below.

**Opt-out / off switch.** A single "Save dictation history" toggle, default **on**
(so the feature is discoverable) but honestly documented. When off,
`Pipeline.process` skips the append entirely — no file, no residue — matching
Wispr's "Never store data locally." Because foldwise-voice already never records
audio to disk, you inherit a privacy win superwhisper users have to opt into:
**do not persist audio in history at all.** History is text-only by design; if
"re-run Polish on this entry" is wanted, re-run it on the stored `rawText`, not on
re-decoded audio. This sidesteps superwhisper's biggest privacy complaint.

**What "flag/report" means with no server.** foldwise-voice has nowhere to send a
report and must not grow one — Wispr's flag literally ships the transcript to
their team ("Flagged transcripts… may be reviewed by the Wispr Flow team")
([Getting help](https://docs.wisprflow.ai/articles/7837779518-getting-help-with-wispr-flow-reporting-flagging-and-contacting-support)),
which is exactly what this app must not do. So implement flag as a **purely local
"flag for review" bucket**: set `flagged = true`, optionally store a local
`flagReason`, and add a "Flagged" filter view. It becomes a personal
quality-triage list ("these transcriptions were wrong / the Polish misfired") the
user can revisit, copy, or delete — useful for the user tuning their Modes, with
zero network. If you later want it to feed model/prompt tuning, keep that a
**manual, explicit, on-device export** the user initiates — never an automatic
phone-home. Label the action honestly in the UI ("Flag for my review") so it is
never mistaken for a cloud report.

**Net design:** a text-only, local JSONL history hooked at the end of
`Pipeline.process`, date-grouped in a SwiftUI list with hover copy/flag/overflow
rows, a 30-day default retention with a user-set window, a real off switch that
suppresses the write, and a flag that is a local triage bucket — superwhisper's
local-first storage without its keep-forever/audio-on-disk defaults, and Wispr's
row UI and retention controls without its servers.

---

## Further reading (primary sources)

superwhisper:
- History management (folder path, cron retention): <https://superwhisper.com/docs/get-started/history-management>
- History panel (fields shown, search, Process Again, Report Issue): <https://superwhisper.com/docs/get-started/interface-history.md>
- Transcribe from history (Process Again): <https://superwhisper.com/docs/get-started/transcribe-history.md>
- Sensitive data (local-only, "no audio or text ever leaves your machine"): <https://superwhisper.com/docs/security/sensitive-data.md>
- Account deletion (local storage of transcripts/audio, nothing on servers): <https://superwhisper.com/docs/security/account-deletion.md>
- Compliance (on-device vs cloud, zero-data-retention, BYOK): <https://superwhisper.com/docs/security/compliance.md>
- Enterprise configuration (recording controls + retention enum): <https://superwhisper.com/docs/enterprise/configuration.md>
- Troubleshooting ("automatically saves your dictations every few seconds"): <https://superwhisper.com/docs/common-issues/troubleshooting>
- Docs index (llms.txt): <https://superwhisper.com/docs/llms.txt>
- alfred-superwhisper README (third-party parser; meta.json field names): <https://github.com/ognistik/alfred-superwhisper/blob/main/README.md>

Wispr Flow:
- Data controls (Privacy Mode, Cloud Sync, word-count stat): <https://wisprflow.ai/data-controls>
- Privacy: <https://wisprflow.ai/privacy>
- Privacy policy (30-day subprocessor deletion, "as long as necessary"): <https://wisprflow.ai/privacy-policy>
- Security & compliance FAQ (Cloud Sync wording, local storage default): <https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq>
- Delete transcripts & history (three-dot delete, local storage options + default, 24h auto-delete): <https://docs.wisprflow.ai/articles/4465314211-delete-transcripts-and-history-in-wispr-flow>
- Getting help: reporting & flagging (flag icon, "reviewed by the Wispr Flow team"): <https://docs.wisprflow.ai/articles/7837779518-getting-help-with-wispr-flow-reporting-flagging-and-contacting-support>

### Claims that could not be verified against a primary source

- **superwhisper's exact recording-storage on/off toggle name and default.**
  Multiple secondary sources (and superwhisper's public feedback board) describe
  a Settings toggle to disable saving recordings and say audio-on-disk is the
  opt-out default, but I could not find a first-party docs page that names the
  toggle or states its default verbatim. The "saves automatically" default is
  doc-confirmed (Troubleshooting); the explicit *disable* control is reported,
  not doc-pinned.
- **iCloud sync of the recordings folder.** That `~/Documents/superwhisper`
  syncs to iCloud when iCloud Drive is on is a logical consequence of the
  documented default path plus a secondary source, not a statement in
  superwhisper's own docs. Stated as reported.
- **superwhisper `meta.json` field names.** Sourced to the third-party
  alfred-superwhisper tool that reads those files, not to superwhisper's own docs
  (which describe the *displayed* fields but do not enumerate the JSON keys).
  Treat field names as accurate-as-parsed-by-a-real-tool but not officially
  documented.
- **Wispr Flow's app-visible history retention window.** No explicit number is
  published for how long stored history persists; the only concrete figure is
  "generally deleted within 30 days" at third-party subprocessors, which also
  reads in tension with Wispr's "zero data retention agreements with all
  third-party AI providers" claim. Flagged as a conflict, not resolved.
- **Wispr Flow date-grouping / "TODAY" header.** The per-row hover actions
  (copy/flag/delete/overflow) are doc-confirmed; the specific date-grouped
  "TODAY" layout in the user's screenshot is inferred from the general history
  panel description, not quoted from a Wispr doc.
