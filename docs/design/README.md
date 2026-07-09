# Handoff: FoldWise Voice — App Redesign + Floating Badge

## Overview
Redesign of FoldWise Voice, a macOS dictation app (menu-bar + main window). This package covers:
1. The **main window** ("Editorial" direction): collapsible sidebar → icon rail, Home screen with last-10 dictations + stats rail. Light and dark mode.
2. The **floating badge** (recording bar): a 3-state living component — idle → hover → recording — with a generative "silk ribbon" light animation.

## About the Design Files
The file `FoldWise Redesign.dc.html` is a **design reference created in HTML** — a prototype showing intended look and behavior, NOT production code. Your task is to **recreate these designs in the existing Swift/SwiftUI codebase** using its established patterns. Do not port HTML/CSS/JS directly; translate the visual and behavioral spec below into SwiftUI (+ AppKit/Metal where noted).

## Fidelity
**High-fidelity.** Colors, typography, spacing, radii, and animation timings below are final and should be matched closely. The dictation copy in the history list is sample data.

## Design Tokens

### Light mode
- Window background: `#FCFBF8`
- Sidebar background: `#F7F5F0`
- Hairline / borders: `#E9E5DC` (window border `#E2DED6`)
- Primary text: `#1B1813`
- Secondary text: `#6E675A`
- Tertiary / labels: `#8F887A`
- Faint text: `#B0A995`
- Accent: `#C24A22` (links, active nav dot/icon, "All history →")
- Keycap chip: bg `#FFFFFF`, border `#D8D2C4` (bottom border 2.5px), text `#1B1813`
- Active nav item: bg `#FCFBF8`, subtle shadow `rgba(50,42,30,.07)`

### Dark mode
- Window background: `#161411`
- Sidebar background: `#1B1815`
- Hairline: `#2C2822`
- Primary text: `#F2EFE8`
- Secondary text: `#9B9482`
- Tertiary: `#87816F`
- Faint: `#6B655A` / `#5C564A`
- Accent: `#E06A3E`
- Keycap chip: bg `#211E19`, border `#4A453B`
- Active nav item: bg `#26221C`

### Floating badge (own palette — same in both modes, it floats over any wallpaper)
- Pill background: `rgba(16,13,22,.96)`
- Border: `rgba(167,139,250,.22)` idle/hover → `rgba(167,139,250,.45)` recording
- Glow: `0 0 24px rgba(124,93,250,.22)` idle → `0 0 44px` recording; plus drop shadow `0 18px 40px rgba(0,0,0,.6)`
- Icon idle color `#B8AEDB`, emphasized `#E8E2F7`; mic button bg `rgba(167,139,250,.16)`, hover `.3`
- Ribbon palette (RGB): `(196,132,252)`, `(124,93,250)`, `(94,214,255)`, `(244,158,255)`, `(168,225,255)`

### Typography
- UI: **Instrument Sans** (Google Fonts). Closest system approach: SF Pro with similar weights is acceptable; if bundling, use Instrument Sans 400/500/600.
- Mono (timestamps, mode tags, keycaps, timer): **IBM Plex Mono** 400–600, or SF Mono.
- Scale: page title 28/600, letter-spacing −0.02em · stat numbers 27/600 · body rows 13.5/400 · nav 13.5/500 (600 active) · section labels 11/700, tracking +0.1em, uppercase · timestamps 11 mono · mode tags 10.5 mono · tooltips 11.5/600.

### Window sizing
- Current app is 770×590 — **increase it.** New default: **980×720**, minimum **880×640**, resizable, size persisted (`.windowResizability(.contentSize)` off; standard autosave frame).
- The layout is built for this: sidebar 190 (or rail 52) + main column ≥560 + stats rail 212. Below ~880pt width, collapse the sidebar to the icon rail automatically.

### Radii & spacing
- Window corner 12 · nav item 8 · rail icon tile 9 · cards/keycap 6–8 · pill/badge fully rounded.
- Sidebar width 190; icon rail width 52 (36×36 tiles, 4pt gap); stats rail width 212; content padding 30–40.

## Screens / Views

### 1. Titlebar (both modes)
Traffic lights · **sidebar toggle button** (27×22, 1.5px border `#B8B1A2`/`#5C564A`, rounded 6, with inner vertical divider line at x=8 — the standard macOS "toggle sidebar" glyph) · app name 12.5/600 tertiary. Bottom hairline. **No user avatar, no notification icon.**

### 2. Sidebar — expanded (190pt)
Nav: Home, Modes, Models, History, Stats, Settings. Each row: 16pt stroke icon (1.8pt, round joins) + label, padding 7×11.
- Icons: Home=house · Modes=4-point sparkle · Models=cube/box · History=clock · Stats=3 rising bars · Settings=two sliders.
- Active row: card background (see tokens), icon stroked in accent, text primary 600.
- Footer pinned bottom: `v0.12.0 · up to date` 11pt faint.

### 3. Sidebar — collapsed (icon rail, 52pt)
Same icons as 36×36 centered tiles. Active tile gets the active-row background + accent icon. **Hover any tile → tooltip** to its right (10pt offset, vertically centered): dark chip `#1B1813`/text `#F7F5F0` in light mode, inverted `#F2EFE8`/`#1B1813` in dark mode; 11.5/600, padding 5×10, radius 6, shadow. Fade+slide in 150ms.
Toggle animates width 190↔52 (~300ms ease-out; SwiftUI `.animation(.easeOut(duration: 0.3))`). Keyboard: `⌘\`.

### 4. Home
Three columns: [sidebar] [main] [stats rail 212].
**Main:** title "Ready when you are." → subtitle "Hold `right ⌘` and speak — release to insert at your cursor." (keycap chip inline) → `TODAY` section label → dictation rows → `YESTERDAY` label → rows → accent link "All history →".
**Dictation row** (last 10 overall): timestamp (mono 11, tertiary, 44pt column) · single-line truncated transcript (13.5, primary) · mode tag right-aligned (mono 10.5, faint: clean/raw/email/bullets). Hairline separators, 11pt vertical padding.
**Stats rail** (left hairline divider): four stat lines — `3,765 total words`, `119 wpm`, `1 day streak`, `~41 min saved` — number 27/600 + label 12 tertiary, hairline-separated. Below: "All systems go" summary (12.5/600 + 11.5 tertiary: Parakeet v3 · qwen2.5:3b · accessibility granted · v0.12.0) + accent "Stats →".

### 5. Floating badge (NSPanel, always-on-top, non-activating)
Height 46. Width animates by state: **idle 104 → hover 158 → recording 248** (300ms, cubic-bezier(.4,0,.2,1)). Content cross-fades with a 220ms pop (opacity 0→1, scale .9→1).

- **Idle:** glyph row of rounded bars/dots (4pt wide): dot·dot·dot·15pt bar·dot·9pt bar·dot; colors `#B8AEDB` (dots) / `#E8E2F7` (bars). Each element "breathes" (scaleY 1→1.9, opacity .55→1) on a 3.4s ease-in-out loop, staggered 0.35s apart.
- **Hover** (mouse enters pill): three round buttons — sparkle 34 (cycles/opens mode picker; tooltip "Mode: Clean"), **mic 36** (highlighted bg; tooltip "Dictate — right ⌘"), expand 34 (tooltip "Open FoldWise"). Tooltips appear above the pill, same chip style as rail tooltips. Button hover: bg `rgba(167,139,250,.14)`, mic scales 1.06.
- **Recording** (mic pressed / hotkey held): silk-ribbon canvas (~160×26pt) + mono timer `m:ss` in `#CFC4EA`. Border and glow intensify (see tokens). Click anywhere on pill = stop.
- Idle ↔ hover on mouse enter/leave; recording only exits on stop.

## The silk-ribbon animation (recording waveform)
Generative light ribbons, additive-blended on transparent background. Recreate with **TimelineView + Canvas** (`.blendMode(.plusLighter)`) or a small **Metal** layer.

Algorithm (t = elapsed ms, w×h = canvas size):
- A base 1px horizontal line at y = h/2, stroked with a horizontal gradient: transparent → `rgba(180,150,255,.5)` at 15% → `rgba(120,220,255,.5)` at 85% → transparent.
- 4 ribbon strands, each drawn 3 times (sub-strokes offset in phase by 0.5) for a silky bundle. For strand i (0–3), sub s:
  - `phase = i*1.7`, `freq = 0.010 + i*0.0032` (per px), `drift = sin(t*0.00012 + i)*0.12`
  - envelope: `u = x/w`, remap u over [flat, 1−flat] (flat = 0.08–0.10) to eu ∈ [0,1], `env = sin(π·eu)²` — so ribbons are flat at the edges and swell mid-line
  - `y = h/2 + sin(x·freq + t·speed·(1+i·0.13) + phase + s·0.5)·h·amp·env + sin(x·0.004 + t·0.0002 + i)·h·0.06·env + drift·h·env·0.3`
  - stroke color = palette[i], alpha ≈ `0.5/3 + 0.08`; line width 1.6 (s=0) else 1.0; soft glow (shadow blur 6, same color at .8)
- Speeds: idle preview `speed = 0.00045`, `amp = 0.30`; **recording**: `speed = 0.0009` and amp driven by mic level — in the prototype it's simulated as `amp = 0.22 + 0.13·|sin(t·0.0016)| + 0.06·sin(t·0.0057)`. In production, map real input RMS to amp ∈ [0.10, 0.45] with ~100ms smoothing.

## Interactions & Behavior
- Sidebar toggle: titlebar button + `⌘\`; state persists across launches.
- Rail tooltips: 150ms fade/slide, no delay needed (or 200ms delay to feel native).
- Badge: hover expansion must not steal focus (non-activating panel); recording starts via mic click or global hotkey (right ⌘ hold / toggle key); stop inserts text at cursor.
- History rows: click → open in History view; hover may reveal copy action (not in mock).
- All hover/active states listed in tokens.

## State Management
- `sidebarExpanded: Bool` (persisted)
- `badgeState: enum { idle, hover, recording }` + `recordingSeconds: Int` (timer)
- `activeMode: enum { clean, voiceToText, email, bullets }` — shown in badge tooltip, cycled/picked from sparkle button
- Home data: last 10 history entries (timestamp, text, mode), aggregate stats (totalWords, wpm, streakDays, minutesSaved)

## Assets
No bitmap assets. All icons are simple 24×24 stroke glyphs (1.8pt, round caps/joins) — use SF Symbols equivalents: `house`, `sparkles`, `shippingbox`, `clock`, `chart.bar`, `slider.horizontal.3`, `mic`, `arrow.up.left.and.arrow.down.right`. Fonts: Instrument Sans + IBM Plex Mono (Google Fonts) or SF Pro/SF Mono fallbacks.

## Files
- `FoldWise Redesign (standalone).html` — **self-contained interactive prototype** — open directly in any browser; all animations and interactions work offline. Section 6 = floating badge (hover it, click the mic; force states with the chips), section 5 = Home light/dark with working sidebar collapse + icon-rail tooltips.
- `screenshots/` — pixel references: `badge-idle.png`, `badge-hover.png`, `badge-recording.png` (exact target for the recording state — silk ribbons, glow, timer), `home-light.png`, `home-dark.png`.
