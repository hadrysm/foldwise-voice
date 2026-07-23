# FoldWise Modes and Mode editor prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid for Wayfinder ticket
> “Prototype Modes and the Mode editor,” not production code.

Question: How should the Modes library, selection and detail states, empty and
unavailable-model states, destructive confirmation, and Mode editor sheet
translate into the approved Ember Edge grammar without changing Mode behavior
or validation?

Run the isolated native SwiftUI gallery from the repository root:

```sh
./Prototypes/ModesLibrary/run.sh
```

The bottom review bar switches among three structurally different compositions:

- **A — Command Ledger**: a dense ordered library keeps selection visible beside
  a stable detail inspector.
- **B — Studio Rail**: Voice to Text and editable Modes form a horizontal
  instrument rack above one generous editing canvas.
- **C — Mode Stack**: one full-width ordered stack expands the selected Mode
  in place, keeping library and detail in the same reading flow.

Command–Left Arrow and Command–Right Arrow cycle compositions. The review bar
also forces Light or Dark, Standard or Contrast+, and these representative
states: selected Mode, Voice to Text, empty library, unavailable model, delete
confirmation, populated editor, validation errors, persistence retry, and icon
palette.

Render the curated review snapshots to `.context/modes-library-shots` with:

```sh
./Prototypes/ModesLibrary/run.sh --render
```

## Preserved behavior represented by the gallery

- Voice to Text remains a permanent system Dictation selection outside the
  editable Mode library.
- Mode order remains both display order and Mode-cycle order.
- Selecting a Mode changes the next Dictation session only.
- Detail retains icon, transformation, AI model, Polish instructions, preserved
  vocabulary, edit, duplicate, reorder, and delete.
- Empty-library guidance keeps Voice to Text available and points to Add Mode.
- An unavailable AI model keeps its Mode identity, explains raw-transcript
  fallback, and links to Models.
- Delete confirmation states that History remains, the AI model is not
  uninstalled, and deleting the selected Mode selects Voice to Text.
- The editor remains a fixed 820×570 sheet with explicit Save/Retry and Cancel,
  field-level validation, the labeled icon palette, two transformations, and
  one-term-per-line vocabulary.
- Orange signals selection, focus, and primary actions. Warning and error states
  retain semantic color plus icon, text, and shape cues.
- Increase Contrast raises essential borders from one to two points. Production
  Reduce Motion removes the shared 160 ms transitions; this static prototype
  introduces no essential motion.

## Verdict

Approved: **A — Command Ledger**.

The persistent ordered library makes Dictation selection and Mode-cycle order
easy to scan while a stable inspector gives long Polish instructions,
vocabulary, unavailable-model guidance, and library actions enough room. Voice
to Text remains visually separate as the permanent system selection.

The selected row uses the approved Ember Edge ingress mark, active icon, weight,
and checkmark rather than an orange surface wash. The inspector, destructive
confirmation, and fixed editor sheet carry the same dense, layered grammar
through normal, empty, unavailable, validation, and persistence-retry states.

This is a composition decision only. Existing selection timing, ordering,
candidate transactions, validation, History attribution, raw-transcript
fallback, keyboard behavior, and accessibility semantics remain unchanged.

Variants B and C remain in this throwaway artifact only as review context. The
complete prototype gallery and production specification should carry forward
Variant A.
