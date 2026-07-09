# Paste-ready prompt for Claude Code

---

I'm redesigning my macOS SwiftUI dictation app **FoldWise Voice**. In `design_handoff_foldwise_redesign/` you'll find:
- `README.md` — the complete design spec (tokens, layouts, states, animation math). Treat it as the source of truth.
- `FoldWise Redesign (standalone).html` — a self-contained interactive prototype: open it in a browser to SEE the animations live (badge idle breathing, hover expansion, silk-ribbon recording). Reference only — do NOT port the HTML; recreate in SwiftUI.
- `screenshots/` — pixel references for each badge state and the Home views. Match these visually: `badge-idle.png`, `badge-hover.png`, `badge-recording.png`, `home-light.png`, `home-dark.png`.

Please implement, in this order:

1. **Design tokens**: add a `Theme` (colors for light/dark from the README, spacing, radii, type scale). Wire into the existing views incrementally — don't break current functionality.

2. **Main window shell**: resize the window — default **980×720**, minimum 880×640 (today it's 770×590), frame autosaved; auto-collapse the sidebar to the icon rail below ~880pt width. Titlebar with a native sidebar-toggle button (and ⌘\), a collapsible sidebar that animates between a 190pt labeled list and a 52pt icon rail (SF Symbols: house, sparkles, shippingbox, clock, chart.bar, slider.horizontal.3). Icon rail shows tooltips on hover per the spec. Remove any user-avatar/notification icons. Persist the collapsed state.

3. **Home view**: greeting + "hold right ⌘" keycap hint, the last 10 dictations from the existing history store (timestamp · truncated text · mode tag) grouped Today/Yesterday with hairline rows, and a right-hand 212pt stats rail (total words, wpm, day streak, minutes saved + system status summary). Reuse the app's existing history/stats data sources.

4. **Floating badge** (the always-on-top recording bar, an NSPanel that never steals focus): three states — idle (104pt pill with breathing dot/bar glyph), hover (158pt, three buttons: mode sparkle, mic, open-app, with tooltips), recording (248pt, silk-ribbon waveform + timer). Width animates 300ms ease; content cross-fades 220ms. Implement the silk-ribbon animation with TimelineView + Canvas using `.blendMode(.plusLighter)` following the exact algorithm in the README ("The silk-ribbon animation") and matching `screenshots/badge-recording.png`; drive amplitude from real mic RMS smoothed over ~100ms.

5. Apply the same visual language to the remaining views (Modes, Models, History, Stats, Settings) using the tokens — keep current functionality, restyle only.

Constraints: macOS 14+, SwiftUI first (AppKit only where needed: NSPanel, global hotkeys). Match the spec's colors/typography/spacing closely; use SF Pro/SF Mono if we don't bundle Instrument Sans / IBM Plex Mono. Ask me before restructuring navigation or data models.

---
