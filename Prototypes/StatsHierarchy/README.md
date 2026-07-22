# Stats calendar states prototype

> THROWAWAY PROTOTYPE — this is a visual decision aid, not production code.

Question: Do the resolved intensity scale, day-detail grammar, compact layout,
empty and saving-off states, keyboard focus, VoiceOver labeling, and
reduced-motion behavior remain clear and practical when combined in the rough
native Stats prototype at representative Light and Dark window sizes?

Run it with one command from the repository root:

```sh
./Prototypes/StatsHierarchy/run.sh
```

Use the bottom review bar to compare four representative states, switch between
880×640, 980×720, and 1180×760 windows, force Light or Dark, and compare normal
with reduced motion. Command–Left Arrow and Command–Right Arrow cycle states.

Tab into the calendar to focus today. The unmodified arrow keys move the roving
day focus by one day or one week; hover and keyboard focus reveal the same day
detail shelf. Future days are deliberately excluded from focus and VoiceOver.

To render the Light/Dark compact and wide review matrix into
`.context/stats-prototype-shots`, run:

```sh
./Prototypes/StatsHierarchy/run.sh --render
```

The sample data is illustrative. The five fixed thresholds, legend language,
day-detail copy, and interaction/accessibility behavior reflect the prior
Wayfinder decisions; this prototype exists only to review them together.
