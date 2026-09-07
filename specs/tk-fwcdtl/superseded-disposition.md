---
name: The superseded disposition — an already-resolved bead routed to the close sweep (tk-fwcdtl)
description: Why mol-first-reaction's terminal step has a fourth exit for a bead a later one already resolved, why it routes to duplicate-sweep.sh rather than closing, and how gc.disposition_kind gives the close the right word. Read with specs/tk-diqxx9 before changing the disposition set.
---

# The superseded disposition (tk-fwcdtl)

## The gap

`first-reaction-dispose.sh` had three exits — `actionable`, `blocked`,
`ruling` — and none of them reaches an actor allowed to close a bead whose
subject a later bead already resolved. `docs/authority-map.md` puts
close-with-successor in the hands of `bead-rehome.sh` callers (mechanik,
converse, `duplicate-sweep.sh`) and forbids a work bead from being "closed by
its own polecat". So a first reaction that found a bead already resolved had one
automated exit, `actionable`, which routes it to a pool whose worker cannot
perform the disposal the takeaway asks for. The one indirect path a polecat
could reach — stamp `duplicate_of` for `duplicate-sweep.sh` — was named nowhere
and used the wrong word: `bead-rehome.sh` would call a retired check
`fixed-upstream`, but `duplicate_of` was the only marker with a reader.

## The exit: route to the closer, never close

`superseded` takes a `--successor <bead-id>` (same store) and an optional
`--kind` (default `fixed-upstream`; `duplicate` when the subject merely repeats
the successor's request). It records `gc.first_reaction=superseded` with its
reason and target, stamps the `duplicate_of` pointer plus `gc.disposition_kind`,
and parks the bead at rest with `gc-helm.sh takeaway --release --no-wait` — no
route. `duplicate-sweep.sh` (merge cadence arm 7) then closes it through
`bead-rehome.sh`.

It does not close the bead itself, and that is deliberate rather than
incidental. A first reaction is the first, shallow look at a freshly-arrived
bead; the pack keeps the reaction from terminating a bead so that a second actor
with more context acts before anything closes. Every one of the other three
exits leaves the bead open for exactly this reason, and the rule is asserted and
tested across the formula, the prompt, `PROVENANCE.md`, and
`first-reaction-dispose.test.sh`'s `(NEVERCLOSE)` gate. The superseded exit
keeps the rule: the sweep is the second actor, and it re-establishes every fact
before it closes.

## The guards mirror the sweep's, so a parked bead is one it will take

The exit refuses unless the two facts `duplicate-sweep.sh` itself checks already
hold: the successor resolves and is closed or records `work_outcome=shipped`,
and the subject did no work of its own. That second fact is proved the way the
sweep's no-work gate proves it, so the exit accepts exactly what the sweep will
close: `work_outcome=no-op` (the polecat's own statement that nothing was
pushed, which holds even when a work-product key names a rework or rebase twin's
branch), or no `work_outcome` and none of the work-product keys (`branch`,
`work_dir`, `gc.work_dir`, `pr_number`, `pr_url`, `merge_result`,
`gc.work_commit`); any other outcome (`blocked`, `shipped`, `abandoned`) is work
the sweep holds as not a no-op, so the exit refuses it rather than parking a bead
the sweep would never close. Checking them here, at stamp time, is what keeps
the exit non-stranding: a bead it parks is one the next sweep disposes, not one
it silently leaves open forever. The two refusals also name the exit that fits
instead — a successor not yet resolved is a `blocked` wait, and a subject that
did work is a re-home a person makes through `ruling`. Same-store is required
for the same reason: the sweep skips a successor it cannot read in the subject's
store, so a cross-store superseded would park a bead nothing closes.

`gc.origin=operator` still forces `ruling`. A commissioned topic is a
conversation a human is waiting on, and an automated close answers a question
nobody asked; the operator-origin guard already refused every exit but `ruling`,
and `superseded` inherits that refusal.

## The right word: gc.disposition_kind

`duplicate-sweep.sh` closed everything as `--kind duplicate`, because
`duplicate_of` was a duplicate-only marker. It now reads `gc.disposition_kind`
and passes it as the `--kind` to `bead-rehome.sh` (falling back to `duplicate`
when absent or unrecognised, the historical shape its gates were written for).
So a bead a successor retired upstream is disposed as `fixed-upstream`, not
filed as a plain duplicate — for both the superseded exit and a polecat that
stamps the marker by hand.

## Why not close synchronously through bead-rehome.sh

Adding `first-reaction-dispose.sh` to the close-with-successor holders and
calling `bead-rehome.sh` inline would be smaller and needs no cadence latency.
It is rejected because it reverses the "a reaction never closes" invariant — a
shallow triage would terminate beads — and because the sweep's extra gates
(successor closed/shipped, subject a no-op, nobody else owns it) are a second
check on the reaction's judgment that a synchronous close would skip. Routing to
the sweep keeps the invariant and reuses the one auditable close path.

## Where superseded sits against ruling

`ruling` already carried a recommend-close shape: a first reaction that concluded
there was nothing to do filed a visit for the operator to confirm. `superseded`
is the automatable subset of that — the case where the resolution is a fact (a
named successor already shipped, no work of the bead's own) rather than a
judgment. When it is provable, `superseded` disposes it without an operator
glance; when it is a judgment (the bead should not exist, or resolution is
believed but unprovable), it stays a `ruling` recommend-close.
