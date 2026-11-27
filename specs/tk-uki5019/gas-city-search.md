---
name: Gas City search for the placement hold write
description: Use when you need the evidence for how the pack adds the placement hold, hold:mayor, to a bead that exists, which bd and Gas City primitives were searched, the reason Gas City gives for setting a hold with set-state and how this city measured it, or where the fix at Gas City's source is filed.
---

# Gas City search: the placement hold beside any other hold

The change stops the pack from setting the placement hold, `hold:mayor`, with
`bd set-state`, the write Gas City's hold conventions sanction. The pack adds the
label with `bd update --add-label` instead, with the hold's reason as a note in
the same update. The change adds no operational surface. It avoids one of Gas
City's routes, so this record holds the search, the reason Gas City gives with
its measurement in this city, and the fix at the source.

Read at `gastownhall/gascity` main 0997336456fe (2026-11-25) and
`gastownhall/beads` main 78624109 (2026-11-20). The city runs bd 1.3.4, read at
the `v1.3.4` tag of `gastownhall/beads`. Every line cited below says the same
there as on main, unless the line names a difference. Where a line says
"observed", the behavior was also run on the city's bd, in the store acceptance
case `services/gctk/reaction/acceptance_test.go`.

## What each write does to a hold another writer set

**`bd set-state <id> hold=<value>` swaps that hold out.** `runSetState` in
`cmd/bd/state.go` reads the bead's labels through the detail view, which sorts
them, before its update. `findStateLabel` takes the first label that begins
`hold:`, and the update's label patch removes that label and adds the new one.
`hold:external` sorts before `hold:mayor`, so a bead that carries it when
set-state reads loses it. The command takes one flag, `--reason`. It has no
guard and no mode that adds a value beside another. Observed: after
`bd label add <id> hold:external`, `bd set-state <id> hold=mayor` left the bead
carrying `hold:mayor` alone.

**`bd update <id> --add-label <label>` keeps it, and covers the need.**
`ApplyLabelPatch` in `internal/storage/issueops/aggregate.go` (on main, the body
it calls, `applyLabelPatch`) works out the bead's labels inside the update's own
transaction: the labels it carries, plus each one added, less each one removed.
It deletes only the labels the bead carries that are not in that set. So an
update that only adds deletes nothing, whenever another writer's label landed.
`AddLabelInTx` in `internal/storage/issueops/labels.go` (on main, `addLabelInTx`)
records a `label_added` event with its actor in the bead's history, and
`--append-notes` in the same update records the reason in the same transaction.
Observed: with another writer adding `hold:external` just before intake's
update, the bead carried both holds. Its history held `label_added hold:mayor`
and no `label_removed`.

**`bd label add <id> <label>` keeps it, with no reason.** It makes the same add,
but no note rides with it, so the reason would take a second write.

**No source fix keeps `set-state`.** bd keeps one value per state dimension by
design. The comment at set-state's label patch says the patch is one write "so
the dimension has one value or the command failed", and
`gastownhall/beads#8022` (open) treats two values for one dimension as the
defect to fix. A set-state that left another hold in place would make the
dimension hold several values, against that design.
`gastownhall/beads#5657` (open) reports that concurrent label writes on one
issue lose labels, set-state among them, on bd 1.1.0. A fix for it would not
help here, because set-state removes the label it read before its own
transaction starts.

**Gas City has no hold write of its own.** `gc bd` hands the write to bd. The
hold-label doctor check (`cmd/gc/doctor_hold_label_conventions.go`) reads only
retired labels, and names set-state in its fix hint.

## The reason Gas City gives, tested here

The conventions page, `engdocs/contributors/hold-label-conventions.md`
(unchanged since 0998eac14bfe), sets a hold "with the sanctioned command —
never with a plain `bd label add`". It says a `hold:<value>` label is
"Structured, audited (files an event bead), and names the *who*", and that
"`bd set-state` removes any existing label in the `hold:` dimension, adds the
new one, and files an audit event bead". The reason has two parts: one hold
names the one actor the bead waits on, and the event bead is the audit record.

**One hold per bead does not fit the placement hold.** Gas City's dispatcher
reads each hold label on its own: `HasDispatchHold` in
`internal/beadmeta/hold_labels.go` holds a bead that carries any label in
`DispatchHoldLabels`. The pack reads `hold:mayor` as the placement queue,
apart from any other hold. `gctk bead place` refuses a bead that also carries
`hold:external` until that hold is lifted, and `gctk reaction check` refuses a
bead that carries either. A swap would put a bead that waits on an outside actor
into the queue as work ready to place.

**Nothing here reads the event bead.** No pack code reads a hold's event bead,
and `assets/scripts/bead-context.sh` leaves `issue_type=event` children out of a
bead's listing. No upstream Gas City code reads one either. The reason moves to
the note in the update that adds the label, and bd's history records who added
it.

**Measured** on 2026-11-25 at 07:25Z, across the city's five rig stores and its
city store. The events came from
`gc bd list --type event --all --title-contains 'State change: hold' --json --limit 0`
and the live beads from `gc bd list --label-pattern 'hold:*' --json --limit 0`:

- set-state had filed 438 hold events, 433 of them setting `hold:mayor`. One
  swapped another hold out ("Changed hold from external to mayor"), and its
  reason says its writer meant to move that hold. No other event replaced a
  hold.
- Each of the 156 live held beads carried `hold:mayor` alone. None carried two
  holds, and none carried `hold:external`.

So the swap has not fired by accident in this city. The change removes the
cause that the review of PR #1706 found (run tk-1t6ejcn, finding C3), not a
harm measured here.

## The fix at the source

Gas City's conventions page names no write for a hold that must stand beside
another, and its "never with a plain `bd label add`" sends every writer to the
swap. The fix is one paragraph on that page. It would say that set-state
replaces the first hold label the bead carries, and name `bd update --add-label`,
with the reason in the notes, for a hold that stands beside another. It is filed
as the upstream finding tk-507pp9q, deferred for the operator, and nothing waits
on it.
