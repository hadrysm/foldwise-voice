# Context

## The work items that are ready now

```json
{{READY}}
```

Every item in that list is ready to start right now: its dependencies are already satisfied, it sits inside the run's work scope, and it was selected before this prompt was written. The list is complete and it is already in the order the run will use. There is no other work.

## How many may run at once

At most **{{MAX_PARALLEL}}** items can run at the same time on this machine.

# Task

You are scheduling **one wave** — the set of items that start now. Everything you leave out waits for the next one.

Each item in a wave is implemented on its own branch, in its own worktree, cut from the same starting point, by an agent that never sees the others. When the wave finishes, those branches are merged back together. That merge is the only thing running two items together can break, so you have exactly one question to answer:

**Would these two items, written without knowledge of each other, rewrite the same code?**

Two items in different modules are safe together however large they are. Two items that both rewrite the same file are not: each will be written as if it were the only change, and the merge has to reconcile them afterwards. Judge that from what the items say about themselves — their titles and their bodies, which is all you have and all you get.

You will often not be able to tell. **Do not defer on a guess.** Deferring an item you were merely unsure about costs an entire wave of waiting for work that would have been fine. Letting a real overlap through costs one merge that has to be reconciled. The second is the cheaper mistake. When the items do not tell you they collide, put them in the wave.

## Output

Emit exactly one plan block, of exactly this shape:

<plan>{ "wave": [12, 15, 21], "deferrals": [{ "number": 18, "reason": "rewrites the audio capture module, as does #12" }] }</plan>

- `wave` — the numbers of the items that start now, taken exactly as they appear above.
- `deferrals` — every item you left out, each with the reason you left it out.

Order inside `wave` carries no meaning: the items start together, and the run merges them back in its own order, not yours.

## Rules

- **Choose only from the list above.** A number that is not in it is not work; it is a number you made up.
- **Every item is in exactly one of the two lists** — never both, never neither, never twice.
- **The wave holds at most {{MAX_PARALLEL}} items.**
- **Never return an empty wave.** Everything above is ready and something has to go first. An empty wave is not a way of saying "none of this should run" — that judgement is not yours, and nothing you were given supports it.
- **Deferring is not dropping.** A deferred item is offered again in the next wave, so leaving one out delays it and nothing worse. You are never choosing whether an item happens.
- **Write reasons for a person.** A maintainer reads them to tell a real collision from a coin flip, so name the other item and the thing the two share: "rewrites the hotkey recorder, as does #12" is a reason; "may conflict" is not. Say plainly when you are unsure rather than dressing a guess up as a finding.
- **Identity is the number.** Do not name branches, do not repeat titles, do not invent file paths — the run already knows all three, and anything you echo back it can only get wrong.
- **Run nothing and read nothing.** You have no issue to close, no repository to inspect, no command to run and nothing to look up. Everything you may consider is in this prompt. Do not query the issue tracker — not for more items, not to check these ones, not to see what depends on them.

# Done

The plan block is the whole answer. Emit it and stop — the run reads that block and nothing else you write.
