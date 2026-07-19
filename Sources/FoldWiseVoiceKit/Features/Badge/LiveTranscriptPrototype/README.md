# Live transcript Badge prototype

Throwaway UI prototype for [Prototype live transcript behavior in the FoldWise Badge](https://github.com/hadrysm/foldwise-voice/issues/195).

Run from the repository root:

```sh
python3 -m http.server 4173 --directory Sources/FoldWiseVoiceKit/Features/Badge/LiveTranscriptPrototype
```

Then open <http://localhost:4173/?variant=A>. Use the floating switcher or the left/right arrow keys to compare variants A, B, and C.

Choose **Start live comparison** once, then switch variants while the same transcript is running. Their shared idle Badge is intentionally identical; the variants differ in how live text grows and commits.

The lab is intentionally dependency-free and does not share production code. It exists to settle interaction behavior, then should be captured on a throwaway branch and removed from the implementation branch.
