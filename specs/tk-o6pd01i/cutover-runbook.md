---
name: The native-gates cutover runbook
description: The steps that move a city from visits onto native human gates and conversations once integration/tk-iirrmiw merges (specs/tk-0ur8r9p/design.md, section 12) — who does each, the commands, what each report line from the migration asks of a person, and how the cutover hands off to its follow-up. Read it before merging the integration branch, and keep it open until the follow-up runs.
---

# The native-gates cutover runbook

The design's section 12 orders the cutover in five steps, and section 11
specifies the migration that step 4 and step 5 run. This runbook names each
step with its commands and its check. Two beads carry the parts that are not
commands: tk-1tfzr71.32 is step 1, assigned to the mechanik, and
tk-1tfzr71.33 is the follow-up after step 5, armed to the polecat pool.
tk-1tfzr71.4, the landing bead, waits on tk-1tfzr71.32, so the merge in step 2
holds until step 1 has landed. tk-1tfzr71.33 waits on tk-1tfzr71.4 and on the
human gate tk-nly1mqd, which the operator clears at the end of step 5.

Every pack command below runs the pack's own copy of the script:

```bash
SD="$(gc gc-toolkit scripts-dir)"
```

## Step 1. The notify order goes off

The town repo's city.toml gains an order override that turns off core's
`notify-on-human-gate-creation`, beside the existing override that turns off
`renudge-stale-human-gates`. The mechanik commits it (tk-1tfzr71.32). After
the cutover the board is how a human gate reaches the operator, and the order
would mail one unread notice per gate to the `human` mailbox.

Check: `gc order list` no longer lists the order, and
`gc order show notify-on-human-gate-creation` still resolves it.

## Step 2. The operator merges the integration branch

The operator approves and merges the one PR that carries integration/tk-iirrmiw
to main (landing bead tk-1tfzr71.4). It cannot merge before step 1 has landed.

## Step 3. The pack moves, and the board and gctk are rebuilt

The rig checkout sync fast-forwards the gc-toolkit checkout to the merge, and
every rig switches at once, because one pack serves them all. From then on
gate-visit-sweep's order is gone, human-gate.sh files gates, the hand-off at
escalate.sh runs it for a run poured before the sync, and engage files
conversations.

The board and gctk are built binaries, so they switch only when their build
orders rebuild them. Run both as soon as the checkout has moved:

```bash
git -C "$(gc rig list --json | jq -r '.rigs[] | select(.name == "gc-toolkit") | .path')" log -1 --oneline
gc order run helm-build
gc order run gctk-build
```

Check: the first line names the merge. The new board folds each human gate
onto the bead it blocks and lists conversations where visits were.

Until step 4 finishes, the open visits are on no board, a ruled finding and a
routed comment that name a visit wait for the migration, and a converse
sitting that was live at the sync still runs its old prompt against the old
scripts in its own worktree. Step 4 ends every such sitting before it moves
anything.

## Step 4. The migration runs on every store

Read the plan first, then run it:

```bash
"$SD/migrate-visits-to-gates.sh" --all --dry-run
"$SD/migrate-visits-to-gates.sh" --all
```

`--all` takes the city store first, then every rig store, suspended rigs
included. Each store's run ends with a tally line. The run exits 0 when it
has finished, whatever it left for a person, 1 when a store's listing did not
answer, and 3 when a converse session on a visit did not stop.

**Exit 3 moves nothing in any store.** The run names each session that is
still listed and the visit its alias names. Stop each one
(`gc session close <id>`), and run step 4 again. Nothing has moved, so a note
the sitting wrote in the meantime is carried with the rest.

**Exit 1** names the store that did not answer. Run again once it answers;
every store's run is safe to repeat.

### What the report asks of a person

A line that starts `LEFT OPEN for a person` names an item the migration would
not move without a guess. The item stays open, so a later run takes it once a
person has settled it:

| The line says | What a person does |
|---|---|
| a visit names no subject | Decide what it is about. Open a conversation on that bead with `$SD/gc-helm.sh open <bead>`, then close the visit by hand. |
| a visit is about a gate that leaves several open beads waiting, or none | Engage the one bead you mean, or clear the gate if nothing waits on it any more, then close the visit by hand. |
| a visit's subject no longer exists and no bead waits on it | Close the visit by hand once its question is gone or carried elsewhere. |
| only until edges wait on a visit, on a subject a gate cannot block | The answer resolves those beads, and the subject cannot take a gate (it has open children, or its own until edge). File the question as a gate on the bead that should wait, or close the until waiters, then run again. |
| the sweep's visit for a legacy demand that no bead waits on | Both stay open together. Add the `blocks` edge the demand was meant to have (`gc bd dep add <bead> <demand> --type blocks`) and run again, or close both if the question is gone. |
| a legacy demand that no open bead waits on through a `blocks` edge | The same: add the edge it was meant to have, or close it. |
| a visit's release from its holder did not land | Run again: the rerun releases it from the holder it reads then. |
| bd refused a visit's close | Something other than the moved demand still blocks it, or it has an open child. Settle that, then run again. |
| a finding or an anchor still names a visit that is open | Nothing to do: the visit is left open for one of the reasons above, and the run that moves it re-points the reference. |

A visit a person closes by hand closes with a reason that says where its
question went: `migrated: gate <id>` when a gate now asks it, so a finding or
a routed comment that names the visit follows it there on the next run, and
any other reason when nothing asks it any more. bd refuses to close a visit a
sitting claimed until it is released from that holder:

```bash
gc bd update <visit> --if-assignee <holder> --status open --assignee ""
gc bd close <visit> --reason "migrated: gate <id>"
```

Lines that need no action but are worth reading:

- **A step that can still file a visit.** A mol-validate-close or
  mol-feedback-distiller step poured before step 3 still carries the
  gate-visit block and files a visit when it runs. The run counts each one
  (open, or closed canceled or skipped while its session is listed) and names
  its run's root and its session. Nothing waits for it, and nothing cancels it.
  The visit it files is taken by step 5.
- **A gate that is shaped but blocks no bead.** Its demand's `blocks` edge
  never landed. The board gives it a row of its own, and the first line of its
  description names the bead its filer meant. Add the edge or clear the gate.

## Step 5. The migration runs again, the check passes, and the operator checks the board

Once no store holds a step that can still file a visit, run the migration on
every store again, then the check:

```bash
"$SD/migrate-visits-to-gates.sh" --all
"$SD/migrate-visits-to-gates.sh" --check
```

The rerun converts each visit a step filed after a store's first run, and
finishes any item a person settled. The check reads every store, and it fails
and names each store's open visit, open legacy demand and counted step while
any is left. Repeat step 4's settling and this step until it passes.

When the check passes, open the board and confirm that it shows every human
gate on the bead it blocks and every conversation waiting in the queue. Then
clear the cutover gate:

```bash
gc bd gate resolve tk-nly1mqd --reason "ruled: cutover checked"
```

That releases tk-1tfzr71.33, which the next deferred-dispatch pass sends to the
polecat pool. It runs the check again before it deletes anything: the migration
script and its test, the keys only the script still read, and the old
PR-reminder marker's debt, as section 12 lists. The hand-offs at escalate.sh
and escalation-rig.sh go with tk-kvdomjb, which checks their own drain.

## What does not move back

No step undoes the migration. Once step 4 has run on a store, its visits are
closed `migrated: gate <id>` or `migrated: conversation <id>` and its demands
are shaped gates, which the pack before the merge does not read. A rollback
of the pack after step 4 would leave the operator's open questions on gates
and conversations that pack never shows.
