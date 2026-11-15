---
name: The stop of an armed bead on a real bd store, with gctk's arm verbs
description: Use when you doubt that a stop removes an armed bead's arm before anything else on the real bd, or want to re-run stand-down's real-store proof after a change to stand-down.sh, gc-helm.sh's release or gctk's arm verbs. The suites stub bd, so this is the run against a real blocks edge.
---

# The stop of an armed bead on a real bd store

`real-store-proof.sh`, beside this file, is stand-down's real-store proof
(`specs/tk-utv2kaq/real-store-proof.sh`) with every arm, disarm and pass made by
gctk's verbs: `gctk bead arm`, `gctk bead disarm` and the deferred-dispatch
order's pass, `gctk bead start-armed`. It runs the branch's scripts against a
scratch store under the real bd, with a real `blocks` edge onto a real human gate
that `human-gate.sh` filed and a real arm that `await-ruling.sh` wrote through
`gctk bead arm`. Its `gc` is a shim that passes `gc bd` to bd, names one rig and
records each sling. gctk takes the arm's lock under a scratch city
(`GC_CITY_PATH`) and reads only through that shim (`GC_NO_API=1`). It is run by
hand:

```
env -i HOME="$HOME" TERM=dumb bash specs/tk-1tfzr71.104/real-store-proof.sh \
  <work dir> <this branch's assets/scripts> <gctk binary> [<a base's assets/scripts>]
```

Each run takes a fresh work dir, because the store's server outlives a run for a
little while and would answer for a new store on the same path.

## What differs from stand-down's proof

- A pass is `gctk bead start-armed --db <store>`, and its last line is its count.
- The case of a pass already running is a pass right behind the stand-down's
  answer to the gate. The stand-down removes the arm before it answers, so a pass
  that reads the bead once the gate is answered finds no arm. The base's
  `reconcile` it used as a control no longer runs on any branch of the effort.
- A case for `gc-helm.sh takeaway --release` on an armed bead (tk-5trydl2). With
  a base's scripts named, the same release from that base's `gc-helm.sh` runs
  first, as the control.
- The sitting cases sign off without `--route`, which the sign-off no longer
  takes, and the graduated convoy's park writes no route, as lifecycle.sh now
  refuses a bare one.
- The case of a sitting's hold that left its subject at `held` is gone. No hold
  writes that state now, and lifecycle.sh declares none.

## The run

Run on 2026-11-13 against `polecat/tk-1tfzr71.104` at `9ef19d298`, its scripts
and a gctk built from it, with `origin/main` at `c3d9f4e32` as the base for the
release's control. bd 1.3.4 (`7ef2fd05e+patched`). Ids are the scratch store's.
The run exited 0, and the shim was asked nothing it does not serve.

### The two orders a person would try by hand

A close first is refused, and an answer first lets the next pass send the work:

```
work pb-8ss, gate pb-pq1: {"status":"open","armed":"probe/probe.polecat", ...}
close pb-8ss: ... cannot close blocked issue: pb-8ss is blocked by [pb-pq1] (use --force to override)
rc=1
gate first, then a pass:
gctk bead start-armed: 1 start, 0 sent, 0 retire, 0 withdrawn, 0 hold, 0 ask, 0 leave, 0 fail
sling probe/probe.polecat pb-8ss --on mol-polecat-work --title mol-polecat-work arm:pb-8ss@2026-11-13T22:58:30Z
```

### The stand-down

```
stand-down: answered gate pb-22q: ruled: the branch is wrong and nobody needs this
bead-rehome: pb-25q closed in rig:probe — not needed, per pb-22q in rig:probe — ...
work: {"status":"closed","armed":"","route":"","outcome":"no-op", ...}
the next pass: 0 start ... 0 fail
slings by the next pass: 0
a second run: pb-25q is already closed, so there is nothing to stand down; rc=0
```

### A pass right behind the gate's answer

The pass runs inside the shim, right after bd lands the stand-down's
`gate resolve`, so it reads the bead with its gate answered and before the close.
The disarm came first, so the pass finds no arm:

```
stand-down: answered gate pb-bom: ruled: stop this while a pass runs
stand-down: pb-m8z closed as not needed, per pb-bom; nothing re-slings it
the pass right behind the answer: gctk bead start-armed: 0 start, 0 sent, 0 retire, 0 withdrawn, 0 hold, 0 ask, 0 leave, 0 fail
slings by that pass and the stand-down: 0
```

### Stop it: `takeaway --release` on an armed bead

The base's release leaves the arm on, and the pass after the blocker closes sends
the bead it stopped. The branch's release removes the arm first:

```
base:   after the base's release: {"status":"open","armed":"probe/probe.polecat", ...}
        gctk bead start-armed: 1 start, ...
        sling probe/probe.polecat pb-1w6 --on mol-polecat-work --title mol-polecat-work arm:pb-1w6@2026-11-13T22:58:41Z
branch: gc-helm: disarmed pb-9ja
        takeaway set on pb-9ja (by host) [released]: Stopped: the work moved
        after the release: {"status":"open","armed":"", ...}
        gctk bead start-armed: 0 start, ...
        slings by the pass once its blocker closed: 0
```

### A store write that fails partway, then a re-run

The gate's answer is refused after the disarm and the release. Nothing is left to
send the work, so a pass between the runs sends nothing, and the re-run finishes:

```
stand-down: the arm on pb-fv7 is gone and its run has ended, but gate pb-3hf did not resolve, so nothing closed. Re-run this command once that is repaired.
work: {"status":"open","armed":"","route":"", ...}; gate status: open
slings by a pass between the runs: 0
re-run: rc=0; work: {"status":"closed", "outcome":"no-op", ...}
```

### Sittings, refusals and shared gates

Each holds as in stand-down's proof:

- A sitting stands down first and then signs off. The sign-off reads the gate the
  stand-down answered as already cleared and closes the conversation, rc 0.
- Each refusal writes nothing: a key no gate carries, another open gate, another
  live blocker, an open child, a gate that holds another bead with nothing else
  as the evidence, an open PR, a gate a person is assigned, and a claim. The
  store reads unchanged after each.
- A gate that also holds another bead, taken off it by hand with the arm still
  on: the next pass sends the work (1 start).
- The same gate with the evidence named: the bead leaves the gate after its arm
  and route are gone, and a pass right behind the edge's removal sends nothing.
  The other bead keeps its arm and goes once the gate is answered (1 start).
- A routed bead on a shared gate: off it by hand, a pool's query offers it, and
  through the stand-down the query right behind the edge offers nothing.
- The same gate in a sitting leaves the gate open and owed to the other bead,
  and the next pass sends nothing.
- A graduated convoy the refinery parked closes as not needed, and the bead it
  tracks is untouched.
- An epic that carries a hypothesis closes on a disposition, its gate answered,
  the conversation closed, and the next pass sends nothing. I15 passes. An epic
  with an open child or under another open gate is refused with nothing written.
