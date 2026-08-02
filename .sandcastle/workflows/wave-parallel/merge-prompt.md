# TASK

A wave has finished. Every item in it was implemented and reviewed alone, in its own worktree, against its own tests — and you are the first and only thing that sees them all in one tree.

Two jobs, in this order:

1. Finish the merges git could not complete on its own.
2. Prove the merged tree still builds and its tests still pass, and repair it if it does not.

You MUST end by emitting the verdict block described at the end of this prompt.

# CONTEXT

## What the run already did

```json
{{WAVE}}
```

- `branch` is the branch you are on — the one every item was cut from and merged back into.
- `base` is the SHA it pointed at before this wave's merges, recorded so a person can read the wave as one range afterwards.
- `merged` lists the items git merged cleanly, each with the merge commit it produced. **These are finished.** Do not merge them again, do not inspect them for a second opinion, and do not undo them.
- `unmerged` lists the items git refused to merge, with the paths that conflicted. Each failed merge has already been rewound, so your working tree is clean and holds exactly the merged items. These are yours to attempt.

`unmerged` is often empty. When it is, you have only the second job.

## Coding standards

````markdown
!`cat docs/CODING_STANDARDS.md`
````

# WORKFLOW

## 1. Merge what is left

For each entry in `unmerged`, in the order listed:

```
git merge --no-ff <that entry's branch>
```

Resolve the conflicts by reading both sides and keeping both intentions. Two agents changed the same lines because both were asked to; a resolution that deletes one side to make the conflict disappear silently throws away work a reviewer already approved.

If you cannot reconcile a conflict honestly — the two changes genuinely contradict each other, or you cannot tell what one side was for — run `git merge --abort` and record that item's number as unresolved. **Leaving an item out is a real answer.** It costs that one item, and only that one.

## 2. Verify the merged tree

Run, in order:

1. `swiftformat .`
2. `swiftlint --fix && swiftlint lint --strict`
3. `swift build --build-tests` (compilation is the type check)
4. `swift test --skip-build`
5. **Only if this wave touched `.sandcastle/`** — `pnpm --dir .sandcastle run check-types` then `pnpm --dir .sandcastle run test`. The Swift steps above never reach that TypeScript.

Every item's own loop already ran this against its own branch. You are running it against the combination, which nothing else in the run ever sees.

## 3. Repair a breakage

A tree that merged cleanly and then fails to build is two items disagreeing without git noticing: one renamed what the other calls, changed a signature the other passes to, or moved what the other imports.

Repair the integration, not the feature. Update the call site, reconcile the signature, correct a test that asserted the shape that changed. If making the tree build would mean writing any item's feature work, stop: that is not a repair, and the tree is broken. Report it.

## 4. Commit

Conflict resolutions belong in the merge commit they resolve. Repairs are one further commit, with a Conventional Commit subject (`fix:` for a broken combination, `refactor:` or `test:` for a reconciliation that changes no behaviour) whose body names the items that disagreed and what you changed to reconcile them.

# THE DISTINCTION THAT MUST NOT BLUR

Two things can go wrong here and they are not the same thing.

- A **conflict** belongs to exactly one branch. Nothing else in the wave is implicated, the item's own commits are all still on its branch, and leaving it out costs that item alone.
- A **broken tree** belongs to no branch. Every item merged, every item's tests passed in isolation, and the combination is still wrong — so there is nobody to leave out and nothing to rewind.

Never report a failing build as an unresolved conflict, and never abandon a branch because the tree does not build. Getting this backwards makes the run blame an item that did nothing wrong, or carry on from a tree that does not compile.

# VERDICT

End with exactly one block, of exactly this shape:

<merge>{ "verified": true, "unresolved": [], "notes": "Merged #378 by hand: both it and #375 rewrote the recorder's init. Full verify loop green." }</merge>

- `verified` — `true` only if you ran the whole verify loop on the final tree and every step passed. If any step fails and you could not repair it, `false`.
- `unresolved` — the numbers of items in `unmerged` you could not merge. `[]` when there are none.
- `notes` — one short paragraph a person reads in the run report: what conflicted and how you reconciled it, what you repaired, or what is still failing and how it fails. When everything was already merged and the tree is green, say that in one line.

Report what happened rather than what you hoped for. `verified: true` on a tree you did not verify is the one output nothing downstream can catch.

# RULES

- **Never touch the issue tracker.** No close, no reopen, no comment, no query. You have no issue of your own, every item has already reported for itself, and an item you cannot merge is still work that was really done.
- **Never push and never open a pull request** — commits stay on the current branch for human review.
- **Never use a force flag.** Not on a branch, not on a checkout, not on a worktree. When git refuses, the refusal is information and it belongs in your notes.
- **Do not reset, rebase, or rewind the branch**, and do not delete a branch or a worktree. The run owns all of that; it is holding this wave's branches precisely so that nothing here is unrecoverable.
- **Implement nothing.** No item's feature work is yours, including one whose merge you could not complete.

# DONE

The verdict block is the whole answer. Emit it and stop — the run reads that block and nothing else you write.
