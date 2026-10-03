---
name: gc-helm takeaway --release quiesce fan-out
description: Why the --release store-hammer was a per-release O(open-molecules) query fan-out, not the reported recursive re-spawn, and how keying the quiesce on the parked anchor bounds it.
---

# The --release quiesce fanned a store read out across every open molecule

## What was reported
tk-p76m9h filed a `gc-helm.sh takeaway … --release --no-wait` that "did not
return" for ~5 minutes and spawned "an ever-deepening chain of gc-helm.sh
takeaway subprocesses, each the child of the previous, all with identical args"
— read as a recursive re-spawn / fork-bomb with no convergence guard, to be
fixed by bounding how the release "detaches/retries and reaps its children."

## What the code actually does
The release path spawns no `gc-helm.sh takeaway` child and never re-execs
itself. `cmd_takeaway`'s `--release` arm writes the subject bead and then calls
`quiesce_release_molecule_steps`, whose only children are `gc bd` / `gc convoy`
reads and writes. A read-only sweep of the pack (shell and the two Go helper
modules) found nothing — no lifecycle hook, trigger, or deferred-dispatch arm —
that re-invokes `takeaway` or `first-reaction-dispose.sh` on a bead write. A
nested chain of identical `takeaway` processes cannot be produced by this
pack's code; it would require gascity's control-dispatcher, which is not in this
repo. So the "recursive re-spawn" premise is false.

The real mechanism is a query fan-out inside the quiesce. It listed every open
bead (~1500 at the time), extracted every workflow root (~76), and for EACH root
issued `gc bd show <root>` + `gc convoy status <convoy>` to find the one molecule
whose convoy's single tracked member is the parked anchor — ~150 store
round-trips per release, almost all discarded. The work scaled with the number
of molecules open in the store, not with the one molecule being released. Under
concurrent proactive dispose load the fan-outs overlapped and hammered the
shared Dolt store; each release's sequential `gc` children are what an observer
under duress read as a growing "chain of takeaway subprocesses." The disposition
itself landed early and correctly — the fan-out ran on after it, redundant.

## The fix
Resolve the released molecule directly from the parked anchor. The input convoy
TRACKS the anchor, so `gc bd dep list <anchor> --direction=up -t tracks` names
its convoy(s) in one read keyed on the anchor. Roots are then matched in memory
against that set (their `gc.input_convoy_id` is already in the open-bead scan),
and the single-child `gc convoy status` confirm — the fail-closed guard that the
molecule's one tracked member IS the anchor — runs only for the matched root.
The reap and de-pin behavior below the match is unchanged. Round-trips per
release drop from O(open molecules) to a small constant, independent of store
size, so the store-hammer cannot recur as the store grows or dispose load rises.

A root reachable only through its still-open steps (its own bead already closed)
carries no convoy row in the scan and is skipped — the same boundary the old
`gc bd show`-per-root walk drew for a root it could not resolve ("an absent root
is the witness patrol's, not ours"), and consistent with the quiesce being
best-effort with witness-patrol retry.

Proof is in `assets/scripts/gc-helm.test.sh`: the existing reap/de-pin/scope/
fail-closed assertions still pass, and a `(BOUND)` assertion records every
`gc convoy status` call and asserts the release confirms exactly the one matched
convoy, not one per open root — so a regression back to the enumeration fails
the suite.

## Separate finding, not fixed here
The incident's "second independent chain rooted at a different wrapper" was a
second concurrent dispose of the same subject, from a read-then-act race in the
proactive sweep's `sling_first_reaction_guard` (filed as tk-u61kn9). It is a
distinct root cause. This fix removes its store-hammering consequence — each
release is now cheap — but the redundant double-dispatch itself is left for that
bead.
