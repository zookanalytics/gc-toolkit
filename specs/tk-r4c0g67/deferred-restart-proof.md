---
name: Live proof of the witness's deferred next pass
description: Whether an always-on witness whose next patrol wisp is deferred stays idle until the defer passes and is then restarted fresh on that wisp, run on one rig before the defer was built. Read it to check the timings this change cites, or to rerun the proof after changing how a pass ends, or after a Gas City or bd upgrade.
---

# Live proof of the witness's deferred next pass

The operator's ruling of 2026-11-06 asked for this proof before anything relied on
the defer: a witness ends its pass with its next wisp deferred, stays idle until the
defer passes, then Gas City restarts it fresh and the new session runs the pass. It
ran on 2026-11-06 on this city's build, `gc` 1.4.3 at `e03752646` and bd 1.3.2, on one
rig whose witness had been idle at its prompt since 2026-10-31, holding its patrol
wisp in progress.

## Method

The new step had not landed, so the ending's writes were made by hand, in the step's
order, with a five-minute defer, against the rig's store (`GC_RIG` set to the rig):

```bash
NEXT=$(gc bd mol wisp mol-witness-patrol --root-only --var binding_prefix='gc-toolkit.' --json | jq -r '.new_epic_id')
gc bd update "$NEXT" --set-metadata gc.rig="$RIG"
gc bd update "$NEXT" --assignee="$RIG/gc-toolkit.witness"
gc bd update "$NEXT" --defer="$(date -u -v+5M +%Y-%m-%dT%H:%M:%SZ)"
gc bd mol burn "$HELD" --force    # the wisp the witness held in progress
```

bd read the next wisp back as `deferred`, assigned to the witness, with the date. A
watcher then read the session list, the wisp, the supervisor log
(`~/.gc/supervisor.log`), the reconciler trace and the witness's transcripts every few
seconds. It used `gc bd show` and `gc bd list` only, so it ran no ready read and woke
nothing.

## What happened

| Time (UTC) | Event |
|---|---|
| 05:46:12 | The writes were done: the held wisp burned, the next wisp deferred until 05:51:04. |
| 05:46:12 to 05:53:50 | No restart. The session id stayed the same through 38 controller passes. |
| 05:51:33 | The wisp read back `open` with no date, 29 seconds after the date. |
| 05:53:10 | The supervisor's named-work read matched the wisp as the witness's open work. |
| 05:53:50 | `Cycled fresh-mode session '<rig>--gc-toolkit__witness' for bead reassign: <held> → <next>` |
| 05:55:23 | The new session's start was enqueued. Its transcript began at 05:55:29. |
| 05:55:36 | The new session's startup reconcile adopted the wisp. |
| 05:55:56 to 05:56:20 | It ran the whole pass on main's formula: an empty inbox, no orphan candidates, a clean refinery queue, then main's ending. |

So the defer held the restart off for its whole length, and the restart came 2 minutes
46 seconds after the date.

## What the run and the source show together

- **The hold is bd's deferred status.** For an assigned root-only patrol wisp, Gas
  City's wake demand is a live list of the beads bd records open
  (`listOpenForControllerDemandLive`), and the check on each row reads its status and
  never its `defer_until` (`isOpenAssignedMoleculeWork`). So a wisp kept open with a
  future date would restart the witness at once. The citations are in
  [the search record](gas-city-search.md#what-holds-a-deferred-wisp-and-what-releases-it).
- **The release is a write.** bd returns an expired dated defer to `open` when a ready
  read or a claim reaches its store. The wake here came 29 seconds after the date,
  while the watcher ran no ready read. The controller makes a live ready read of each
  store on its passes, and the burn removed the wisp's event rows, so which process
  made this one is not on record.
- **The restart is the ordinary reassignment restart.** The session had recorded the
  held wisp as the bead it was processing, and the woken wisp differed from it.

## Putting the witness back

Main's ending, which the new session ran, poured and assigned another wisp, burned the
adopted one and started main's 600-second wait as a Claude Code background task, then
ended its turn. Left alone, the task's notification would have opened a new turn in the
same conversation at about 06:06:20, and that turn's pass would have led to more passes
back to back. So the run put the witness back as it found it, idle at its prompt and
holding a patrol wisp in progress:

- At 05:56:21 a guarded write set the newly assigned wisp in progress
  (`--if-assignee=<witness> --if-status=open --status=in_progress`). A session holding
  in-progress work gets no restart.
- At 06:06:24.8 the background task's notification opened a turn. At 06:06:25.9 the
  supervisor's session stop (`POST /v0/city/<city>/session/<id>/stop`, the interrupt a
  run cancel sends a holder) interrupted it before the model ran any command.

Afterwards the session was active and idle, held one patrol wisp in progress, and took
no further restart.

## The step's defer and the reconcile's listing

The proof deferred to an RFC3339 date, because five minutes has no compact form. The
step's own form ran later that day on the same build, against a throwaway ephemeral
molecule in one rig's store, unassigned and under a title no reader takes.
`gc bd update <id> --defer=+1h` read back `deferred`, with `defer_until` one hour after
the write. The startup reconcile's deferred listing
(`gc bd list --status=deferred --type=molecule --include-infra`) returned it, and its
open listing did not. The molecule was then burned.

## What it does not show

- No model ran the new step's text here. [The ending probe](ending-probe.md) covers how
  the witness's model reads it.
- It ran on one rig, with one five-minute defer, on the legacy reconciler this city
  runs. The v2 reconciler reads the same raw open status for a bd store, by reading the
  source, not by a run.
- A restart came about three minutes after the date. A loaded controller's slower
  passes would stretch that, which matters little against an hour.
