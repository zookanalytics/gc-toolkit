---
name: A claimed detached anchor drops out of the --status=open cadence — the backstop fix (tk-8g910r)
description: Why a pre_open_gate/pull_request anchor claimed into a non-open status goes invisible to every cadence reader, and why the fix extends doctor/check-state-space to see that end-state rather than widening the cadence readers or auto-resetting the anchor.
---

# A claimed detached anchor drops out of the cadence (tk-8g910r)

## The hazard

A detached-state anchor (`merge_result=pre_open_gate` or `pull_request`) rests
open, unassigned, and unrouted so the merge cadence can drive it. Every cadence
reader enumerates `--status=open`, so an anchor claimed or held into any non-open
status drops out of all of them at once and stalls in the pipeline until the
claim resolves. The live instance at investigation time was tk-or0ha2:
`in_progress`, `merge_result=pre_open_gate`, assignee empty, no route.

## Which readers, and where the flip comes from

Every merge-cadence reader filters `--status=open --metadata-field
merge_result=<state>`. All are pack-local under `assets/scripts`:

- `gate-ensure.sh:401` (loops `pre_open_gate`, `pull_request`)
- `pr-open.sh:199` (`pre_open_gate`)
- `pre-open-rebase.sh:179` (`pre_open_gate`)
- `merge.sh:213`, `merge.sh:388` (`pull_request`)
- `pr-facts.sh:347`, `pr-facts.sh:1289` (`pull_request`)

There is no shared enumeration helper. Each script defines its own `bd_list` and
passes `--status=open` at the call site. `refinery-reconcile.sh` orchestrates
these arms and inherits the scope.

The `open`->`in_progress` flip is core gastown (`gc hook --claim` / `gc bd update
--claim`), which carries no `merge_result` awareness: it offers and claims any
open, routed, `bd ready` bead. The pack keeps gating anchors out of the pools by
clearing their route and assignee on entry to a detached state (`lifecycle.sh`,
`mol-refinery-patrol.toml:723`), and `doctor/check-state-space` flags an open
detached anchor that still carries a route or an assignee. None of that covers
the anchor once it is already claimed: at `status=in_progress` it is invisible to
the cadence and to `check-state-space`, which enumerates `--status=open` as well.

## Why the fix is the backstop, not the readers or an auto-reset

The bead named two candidate fixes. Both are unsafe as stated:

- Widening the cadence readers to include `in_progress` anchors makes `pr-open`
  and `merge` act on an anchor a worker may hold. `docs/state-machine.md` states
  the governing rule: a live claim is a hold to escalate, not to overwrite. The
  readers cannot tell a live claim from a dead one, so acting on the set is the
  overwrite the rule forbids.
- Auto-resetting the anchor to `open` keys recovery off an empty assignee, which
  is never a liveness signal: a `mol-polecat-work` anchor is unassigned for the
  whole time its polecat works it, because the polecat is assigned to the step
  beads. A pass that resets on "no assignee" acts on live work, and restoring
  bead state safely first needs the concurrent-writer attribution the cadence
  cannot do inline.

`docs/state-machine.md` already assigns this invariant to
`doctor/check-state-space` ("reports either violation"), and that doctor shares
the cadence's `--status=open` blind spot, so it never reported the claimed
end-state. Fixing the doctor makes the documented backstop real: it surfaces the
stall to a person, who attributes it and either re-enqueues a dead orphan or
escalates a live claim. That is the escalate-not-overwrite path the design
already keeps, and it leaves the cadence readers correctly skipping claimed
anchors.

## The change

- `doctor/check-state-space/run.sh`: a second probe reads the non-open live
  statuses (`--status in_progress,blocked,deferred,hooked,pinned
  --has-metadata-key merge_result`) and reports any bead in a detached state that
  is not open. The open-scoped scan and all of its findings are unchanged.
- `doctor/check-state-space/run.test.sh`: the `bd` stub honors `--status` and
  `--has-metadata-key`, so the test can tell the non-open probe from the open scan
  and a dropped filter is caught. `--has-metadata-key merge_result` with no
  `--status` returns beads in every non-closed status, open included — it does not
  restrict to open. The probe's `--status` flag is load-bearing for that reason.
  It scopes the probe to the non-open statuses. The open detached anchors rest
  open by design and the open scan already covers them, so without the flag the
  probe would read them too and report each as a false `status=open, not open`
  violation. New cases
  cover an `in_progress` detached anchor (flagged), a `blocked` one (flagged), an
  open detached anchor at rest (not re-flagged by the non-open probe), and an
  ordinary `in_progress` work bead with no `merge_result` (not flagged).
- `doctor/check-state-space/doctor.toml` and `docs/state-machine.md` state the
  invariant and the backstop.

The check reports tk-or0ha2 after the change; the pre-change check reports OK.
