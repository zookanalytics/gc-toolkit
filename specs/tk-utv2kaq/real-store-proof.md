---
name: The stand-down on a real bd store
description: Use when you doubt that the stand-down's order holds on the real bd, or want to re-run the proof after a change to stand-down.sh, bead-rehome.sh or the reconcile pass. The suites stub bd, so this is the one run against a real blocks edge.
---

# The stand-down on a real bd store

`real-store-proof.sh`, beside this file, runs the branch's scripts against a
scratch store under bd 1.3.2, with a real `blocks` edge onto a real human gate that
`human-gate.sh` filed and a real arm that `await-ruling.sh` wrote. Its `gc` is a
shim that passes `gc bd` to bd, names one rig and records each sling. The test
floor refuses the real bd inside a suite, so `stand-down.test.sh` holds the same
shapes over a stub, and this is run by hand:

```
env -i HOME="$HOME" TERM=dumb bash specs/tk-utv2kaq/real-store-proof.sh \
  <work dir> <this branch's assets/scripts> <a base's assets/scripts> <gctk binary>
```

Each run takes a fresh work dir, because the store's server outlives a run for a
little while and would answer for a new store on the same path. Run on 2026-11-01
against this branch, with `d983f9f50` as the base. Ids are the scratch store's.

## What the bead reported

The instruction the gate messages carried is refused, and the only other order by
hand restarts the work:

```
work pb-h08, gate pb-hvr: {"status":"open","armed":"probe/probe.polecat", ...}
close pb-h08: ... cannot close blocked issue: pb-h08 is blocked by [pb-hvr] (use --force to override)
rc=1
gate resolved, then a pass:
deferred-dispatch: 1 dispatched, 0 retired, 0 held, ...
sling probe/probe.polecat pb-h08 --on mol-polecat-work
```

## The stand-down

```
stand-down: answered gate pb-bh1: ruled: the branch is wrong and nobody needs this
bead-rehome: pb-1tg closed in rig:probe — not needed, per pb-bh1 in rig:probe — the branch is wrong and nobody needs this
stand-down: pb-1tg closed as not needed, per pb-bh1; nothing re-slings it
work: {"status":"closed","armed":"","route":"","pointer":"pb-bh1","outcome":"no-op", ...}
gate: {"status":"closed","close_reason":"ruled: the branch is wrong and nobody needs this","supersedes":"pb-1tg"}
the next pass: 0 dispatched
a second run: already closed, rc=0
```

## A pass already running

The stand-down lands between a pass's listing of the arms and its read of what holds
them. The base's pass has only that listing to go on, so it sends the work. This
branch's pass reads the arm again before it slings:

```
base:   deferred-dispatch: 1 dispatched ...
        sling probe/probe.polecat pb-k03 --on mol-polecat-work
branch: deferred-dispatch: withdrawn pb-dh5 — its arm was removed after this pass listed it; not slinging
        deferred-dispatch: 0 dispatched, 1 retired ...
```

## A stop partway, then a re-run

With the gate's resolve refused, the bead stays open with no arm and no route, a
pass sends nothing, and the same command finishes it:

```
stand-down: the arm on pb-0av is gone and its run has ended, but gate pb-avy did not resolve, so nothing closed. Re-run this command once that is repaired.
work: {"status":"open","armed":"","route":"", ...}; gate status: open
a pass between the runs: 0 dispatched
re-run: stand-down: pb-0av closed as not needed, per pb-avy; nothing re-slings it
```

## In a sitting

The stand-down runs first and names the conversation as the evidence, then the
sign-off reads the gate as answered and closes the conversation. A subject the hold
left at `held` goes the same way, and the sign-off releases it:

```
stand-down: pb-52f closed as not needed, per pb-p11; nothing re-slings it
gate pb-drp was already cleared before this sign-off: "ruled: the operator ruled this out". That answer stands.
SIGNED OFF conversation pb-p11 on pb-52f (settled)

lifecycle: pb-jxa held -> unanchored
SIGNED OFF conversation pb-wys on pb-jxa (settled)
```

## Refusals

Each of these exits 1 with the bead's row unchanged: a key no gate carries, another
open gate, another live blocker, an open child, a gate that also holds another bead
with nothing else named as the evidence, an open PR, a gate a person is assigned, and
a claim.

## A gate that also holds another bead

An answer would release the other bead, so this bead leaves the gate instead. Taken
off by hand with its arm standing, it is sent by the next pass:

```
slings by that pass: 1: sling probe/probe.polecat pb-03d --on mol-polecat-work
```

With the evidence named, the command takes it off once the arm and the route are
gone. A pass run right behind that write sends nothing, the gate stays open and
still holds the other bead, and an answer once this bead has closed sends only the
other bead:

```
stand-down: pb-zyv left gate pb-8pt, which stays open: gate pb-8pt also holds pb-8mb
stand-down: pb-zyv closed as not needed, per pb-q0y; nothing re-slings it
the pass behind the edge: deferred-dispatch: 0 dispatched, ...
work: {"status":"closed","armed":"","route":"","pointer":"pb-q0y","outcome":"no-op", ...}
gate: {"status":"open"}
other bead: {"status":"open","armed":"probe/probe.polecat", ...}
an answer once the work has closed, then a pass: slings 1: sling probe/probe.polecat pb-8mb
```

A route is the other way a bead goes out. A pool's query does not offer a routed bead
on the gate, and it does once the bead is taken off by hand. Through the command, the
same query right behind that write offers nothing, because the script reads back that
the bead has no route before it lets the edge go:

```
a pool's query, on the gate: []
a pool's query, off the gate by hand: ["pb-8rf"]
stand-down: pb-edu left gate pb-ghy, which stays open: gate pb-ghy also holds pb-bx7
a pool's query, right behind the edge: []
```

A sitting always names its conversation as the evidence, so it goes the same way, and
`--leave` on the sign-off keeps the gate for the other bead:

```
stand-down: pb-ok6 left gate pb-4pq, which stays open: gate pb-4pq also holds pb-j6u
gate pb-4pq stays open and owed: the ruling leaves it, and this conversation's reply stays on it
SIGNED OFF conversation pb-51i on pb-ok6 (settled)
work: {"status":"closed","armed":"","route":"","pointer":"pb-51i","outcome":"no-op", ...}
gate: {"status":"open"}
```

## A graduated convoy

A graduated convoy the refinery parked `blocked` stands down the same way, as its
gate's message says, and the bead it tracks stays open:

```
lifecycle: pb-q7z unanchored -> blocked
stand-down: answered gate pb-2y5: ruled: drop the graduation
stand-down: pb-q7z closed as not needed, per pb-2y5; nothing re-slings it
convoy: {"status":"closed","armed":"","route":"","pointer":"pb-2y5","outcome":"no-op", ...}
tracked: {"status":"open", ...}
```

## What the first run found

The first run of this proof found a defect in the first draft, which handed the
gates to `bead-rehome.sh --except-key`. A gate named as the close's evidence lost its
edge in that script's drop of a wait onto its successor, so its read of the bead's
own gates missed it, and the bead closed with the gate still open. That is why
stand-down.sh answers the gates itself, before it hands over the close.
