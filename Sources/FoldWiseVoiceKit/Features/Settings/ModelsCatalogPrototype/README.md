# Complete Models catalog prototype

Throwaway UI prototype for [Prototype a usable Models tab for the complete catalog](https://github.com/hadrysm/foldwise-voice/issues/196).

Run from the repository root:

```sh
python3 -m http.server 4174 --directory Sources/FoldWiseVoiceKit/Features/Settings/ModelsCatalogPrototype
```

Then open <http://localhost:4174/?variant=A>. Use the floating switcher or the left/right arrow keys to compare:

- **A — Inspector rail:** scanning and management share a persistent master-detail layout.
- **B — Comparison table:** the full catalog is treated as a sortable data set.
- **C — Guided shelves:** the page leads with a language/job choice and progressively discloses families.

All variants render the same pinned 65-entry Handy catalog baseline and share in-memory selection, download, quantization, filtering, and deletion state. Switch to **Polish** to evaluate separating the two jobs without adding another sidebar destination.

The prototype is intentionally dependency-free and read-only with respect to FoldWise. It fetches the immutable Handy catalog pinned by the wayfinding research; a small fallback data set keeps the layout usable if that request fails. It should be deleted after its interaction decisions are captured.
