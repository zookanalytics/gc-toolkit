---
name: A parked merge anchor is not pool demand — where the guard belongs
description: Work record for tk-eh64m. The bead named the refinery prompt's Step-0 orphan scan as the fix site; that file is not in this city's pack set and the scan runs nowhere here. The live re-offer has a different cause — the gc binary's detached-orphan lane, filed as gascity gc-gf1l6 — and the pack half is a declared detached-state property on lifecycle.toml, enforced by lifecycle.sh and doctor/check-state-space. Read it before treating Step 0 as an open gc-toolkit hole, and before adding a fourth writer that re-clears gc.routed_to.
---

# A parked merge anchor is not pool demand

Work record for bead tk-eh64m. The bead asked for one thing (a `merge_result`
guard on the refinery prompt's Step-0 orphan-merge scan) and this work
delivered something else in this repo, because the named file is not part of
this city and the harm it describes has a different writer. What follows is
the evidence for each of those two claims and the shape of what shipped.

## The Step-0 premise does not hold in this city

The bead locates the fix in `gastown/agents/refinery/prompt.template.md` at
`gastownhall/gascity-packs`, "the pack `packs.lock` resolves the refinery
prompt from". Checked at 2026-08-27:

- `packs.lock` carries four entries: `contributing`, `gascity/roles`,
  `gascity.git//examples/bd`, `gascity.git//internal/bootstrap/packs/core`.
  No `gastown`. `gc pack list` reports "No remote packs configured".
- Every rig in `city.toml` imports `source = "rigs/gc-toolkit"`, and
  `gc agent list` names all four refineries `<rig>/gc-toolkit.refinery` — the
  `gc-toolkit.` binding prefix is the providing pack.
- `agents/refinery/prompt.template.md` exists in this repo and contains no
  orphan scan. It defers to `mol-refinery-patrol`.
- The only copies of the gastown refinery prompt on the machine are two
  materialized pack caches under `.gc/agents/mayor/` and one
  `mechanik-thread` workspace, both dated 2026-05-27.

So the Step-0 scan the bead quotes does not run anywhere in this city, and
the bead's "gc-toolkit ships no refinery prompt at all" is stale. The
`merge_result` guard the bead wanted mirrored is already the only enumeration
of its kind here: `formulas/mol-refinery-patrol.toml`'s `find-work-select`
block, guarded under tk-jcal4 and covered by
`assets/scripts/find-work-gating-guard.test.sh`. There is no second entry
point in this repo to mirror it into.

## The live re-offer has a different writer

The bead's own notes, added while resolving a re-offer of tk-iuquyk, name it:
`isDetachedHandoffOrphanCandidate` in the gascity rig's
`cmd/gc/pool_detached_orphan_sweep.go`. Confirmed by reading the predicate.
It accepts a bead on `status == open`, empty assignee, empty `gc.routed_to`,
empty `gc.run_target`, empty `gc.kind`, non-empty `gc.work_branch`, and a
`gc.session_id` or `gc.session_name`. Nothing about `merge_result`.

That is byte-for-byte what `mol-refinery-patrol` merge-push writes on its
success path:

    lifecycle.sh transition "$WORK" --to pre_open_gate --assignee "" --route "" ...

The branch is on origin so `gc.work_branch` is set, and the claim-time
session keys are still on the bead. Every correctly parked anchor is
therefore a candidate for a lane whose doc comment scopes it to a *failed*
done sequence, and the lane re-stamps `gc.routed_to` with the pool route it
resolves from the session bead.

Cost, observed 2026-08-27: tk-iuquyk (`merge_result=pull_request`, PR #503)
was claimed by a polecat at 13:47Z while its PR sat open awaiting operator
sign-off. `merge.sh` and `pr-facts.sh` both enumerate with `--status=open`,
so the claim made the anchor invisible to the merge cadence for its duration.
tk-bpo8cj and tk-d6ixcw carried the same re-stamped route at the same moment.

Filed as gascity **gc-gf1l6** (P1), with the patch site, the reproduction,
and the test. This repo cannot push to that one.

## What shipped here

The pack half is not a mirror of Step 0. It is the declaration that was
missing underneath both: `lifecycle/lifecycle.toml` already declared which
states route to a human, but never that the two machine-driven open states
route to nobody. That absence is why a lane could re-stamp a route with
nothing to contradict it, and why `pr-open.sh`'s flip carried an already-bad
route forward into `pull_request` untouched.

- `lifecycle/lifecycle.toml` gains `detached_states` and `park_route`.
- `assets/scripts/lifecycle.sh` mirrors both into the state table and clears
  `gc.routed_to` on entry to a detached state, the exact symmetry of the
  existing human-state arm. Because the clear sets `ROUTE_SET`, it also falls
  under the post-write read-back, so a route that fails to clear surfaces as
  an unverified transition rather than as a silent pool offer.
- `doctor/check-state-space` gains an arm on the same invariant.

### Why the park sentinel is an exception, and how that was found

The first version of the doctor arm errored on any non-empty route and
returned 20 findings against the live city. Seventeen were
`gc.routed_to=human` on parked anchors — `signoff.sh`'s round-cap terminal
verdict, which parks the anchor for the operator. `human` is a documented
park, not a queue: no core machinery claims it
(`docs/gascity-human-engagement.md`), and `check-routed-work-claimable`
already models it as a sentinel. Erroring on it would have called the
operator surface a defect, and clearing it in `lifecycle.sh` would have
silently retracted a bead a person still owned. Hence `park_route`, read
from the declaration by both readers rather than assumed by either.

After the correction the same live run returns exactly the three genuine
findings above.

### Why no repair pass

`reconcile-refinery-handoffs` was considered and rejected as a home. Re-
clearing `gc.routed_to` on a parked anchor from a pass that cannot see why it
was set is the fight `mol-refinery-patrol` forbids ("Flag, never rewrite"),
and the gc binary already carries a flap guard for that class at
`route_recovery.go:334`. The doctor arm reports; it never writes. The only
thing that stops the re-stamp is gc-gf1l6, at which point this arm goes
permanently green and stays as the regression gate.
