---
name: A duplicate human gate, and how far closing one could reach
description: Use when you need to know whether two human gates can stand under one key, how the pack tells, or whether closing one can release a bead that waits, or when you weigh the cleanup PR #1381 removes against putting it back.
---

# A duplicate human gate

The operator asked on PR #1381 (review 5726524542, 2026-11-01): "It's not clear
to me how a duplicate can even be filed or how in the past we could even detect
duplicates. Only case where duplicates are truly duplicates is when they have
our uniqueness key based on reporting locations. Is that what this is managing?"

Yes. This page derives that answer and the brief on the PR. The code is read at
the branch merged with main 451687e63, and the stores at 2026-11-01T05:19Z.
"Uniqueness key" and "reporting location" appear in no doc or script, so reading
them as `--key` is this record's inference, and the validation pass read them
the same way.

## What a duplicate is

Two open human gates that block one bead under one key.

- The key is the `--key` a filing site passes to `human-gate.sh`, stored as the
  gate's `await_id`. `bd_human_gates` reads a bead's gates through its `blocks`
  edges, and `bd_gates_open_under_key` matches the key exactly.
- Nothing else is compared. Two gates with different keys never count, whatever
  they say, and neither does one key on two beads: `liveness-sweep` stands open
  on two beads in other rigs today.
- A site names its key, and no code derives one from where the call sits. Most
  sites pass a fixed name for their situation (`polecat-branch-shape`,
  `refinery-false-completion`). Others add what it concerns (`wedged-<session>`,
  `bring-current-question.<bead>`, `review-needs-you.<finding>`,
  `conversation.<id>`, `pr-abandoned.<pr>`). An agent filing by hand picks one
  under `skills/waits/SKILL.md`. So "based on reporting location" fits the fixed
  names, and comes close for the rest.

## How one gets filed

`human-gate.sh` reads the bead's gates first and files nothing when one under the
key is open. A later call names that first gate. `bd gate create` checks nothing:
`createGateThroughRoles` in the running bd's `cmd/bd/gate.go` reads the target and
creates the gate and its edge in one write, with no look at the target's other
gates. That leaves two ways to a pair:

- two writers on one bead and key that both read before either create lands;
- a native `gc bd gate create --await-id <key>`, the form `skills/waits/SKILL.md`
  gives for a one-off wait, under a key already open.

The first needs one filing site running twice at once on one bead. A worker files
on the bead its own run holds, and a patrol or cadence normally runs one pass at a
time, so the usual way there is two runs of one bead, which `gc sling`'s launch
lock and load-context's duplicate gate exist to refuse.

## How one was caught

Only the helper that reached main in d983f9f50 looked for one. After its create it
read the bead's gates back, and when another open gate under the key sorted first,
it closed its own with a reason headed `moot: a duplicate of gate`. The branch
removes that read-back and that close, so nothing looks for a pair now. Every
other reader takes a pair as it stands: the dedup and `await-ruling.sh` take the
first gate, `--retract` and Accept resolve every open gate under the key, and a
sitting answers each gate its conversation replies to.

The writers before that helper looked no further than the read before filing.
`escalate.sh` read `escalation_key` plus the subject and then created, and read
back only its own stamps. `gc-helm.sh demand` wrote the `gc-demand:<bead>[:topic]` keys the same
way, with no lock.

## How far the release reaches

The review finding on PR #1317 was that the close could release a bead with no
answer from anyone. That needs a bead with an edge onto the gate that closes, and
nothing else holding it. A bead comes to wait on a gate in three ways.

1. **The gate is filed on that bead.** This is every call but one. Each gate of a
   pair then blocks that bead, and the first-sorted gate's filer never closes it,
   so the bead stays held.
2. **`await-ruling.sh --subject`, on a gate filed on another bead.** The one call
   that passes `--subject` is the bring-current question in `mol-polecat-work`,
   and its key is `bring-current-question.<the work bead>`. Only runs of that one
   bead file or wait under the key, and each run that files then waits on the
   first open gate, so the surviving gate holds the bead. The model below finds a
   release here only with three runs of one rework filing at once and two of them
   dying partway.
3. **A `blocks` edge added some other way.** Gas City allows it, and the pack's
   general wait writers take any blocker: `gc bd dep add` under
   `skills/waits/SKILL.md`, `gc-helm.sh`'s takeaway wait and park, and
   `first-reaction-dispose.sh`. A session pointing one at a gate is exposed only
   between that gate's create and its filer's read-back, and only when a rival
   gate sorts first. Six of the 528 gates in the stores ever held a second bead.
   All six are closed and carry the earlier writer's keys, so that shape exists
   and has never met a race.

The finding's reproduction and this branch's regression use a shape no caller has:
a work bead that waits under a key it did not file. They are right about what the
helper allowed, and the regression still pins that for any later caller.

| Runs under one subject and key | Main's helper releases a bead | This branch's helper |
|---|---|---|
| one filer | no | no |
| two filers, one work bead | no | no |
| three filers, one work bead | no | no |
| three filers, one work bead, one crash | no | no |
| three filers, one work bead, two crashes | yes | no |
| two filers and a bare waiter, one work bead | no | no |
| two filers, each with its own work bead | no | no |
| three filers, each with its own work bead | yes | no |
| two filers and a bare waiter, each with its own work bead (the finding's shape) | yes | no |

Under both helpers, every row with two or more filers can end with two gates open,
which main's helper reaches when one create lands after the other writer's
read-back. The model enumerates interleavings without weighting them, so it says
what can happen and nothing about how often. It models what the scripts read and
write, and it is not the scripts: `await-ruling.test.sh` runs the real ones
through the finding's shape. To run it:

```bash
awk '/^```python$/{f=1;next} /^```$/{f=0} f' specs/tk-89yti0r/duplicate-gate-reach.md | python3 -I -
```

## What the stores show

At 2026-11-01T05:19Z, across the rig stores, read with `gc bd --rig <rig> gate
list --all --limit 0 --json` (the city store holds none):

- 528 human gates, every one carrying a key;
- 40 keys carried by more than one gate, with the closest two gates 3453 seconds
  apart and none within a minute;
- none closed with the duplicate reason;
- 522 under the earlier writer's `gc-demand:` keys, whose writer took no lock, so
  a race would have shown as a pair.

## What follows

This makes the branch more a deletion than a fix: 44 runtime lines and one way a
gate closes with no person behind it. Its cost is a question asked twice in a race
main's helper would often have settled to one. Neither case has been seen. The
brief on the PR gives the operator that choice, with keeping main's cleanup as an
option. This branch recommends the deletion: the cleanup handles a race no store
has shown, and taking it out costs only a repeated question if that race comes.

## The model

```python
#!/usr/bin/env python3
"""Every interleaving of human-gate.sh and await-ruling.sh on one subject and
key, run against two helpers: the one that closed its own gate when another open
gate sorted first, and the one that never closes a gate. duplicate-gate-reach.md
says what the results mean.

A filing run's steps, each atomic:
  pre     read the open gates under the key; any open means file nothing
  commit  the create lands: the gate and its edge become visible together
  back    read back; the closing helper notes whether another open gate sorts first
  close   the closing helper closes its own gate when one did
  aread   await-ruling reads the first open gate under the key
  aedge   the run's work bead gains a blocks edge onto the gate aread picked
A bare waiter runs aread and aedge only.

Gates sort by created_at, then id. created_at is stamped before the create is
visible and reads at whole seconds, so every total order of the gates is tried,
whatever order they became visible in.

"one bead" gives every run the same work bead, which is the shape of the only
call that passes --subject, whose key names that bead. "own beads" gives each run
its own, the shape of the review finding: beads sharing one subject and key.

A crash stops a run for good before any step.

A bead is released when it has an edge, every gate it has an edge on is closed,
nobody answered anything, and no run can move. Interleavings are enumerated, not
weighted, so nothing here says how likely any outcome is. This is a model of what
the scripts read and write, not the scripts.
"""
import itertools
from collections import deque


def explore(writers, bare, closing_helper, beads, crashes):
    n = writers + bare
    bead_of = ["C" if beads == "one bead" else f"B{i}" for i in range(n)]
    result = {"released": None, "two_open": False}
    for order in itertools.permutations(range(writers)):
        rank = {g: order.index(g) for g in range(writers)}

        def first(gates):
            return min(gates, key=lambda g: rank[g]) if gates else None

        start = (
            tuple(("pre" if i < writers else "aread", None) for i in range(n)),
            frozenset(),
            frozenset(),
            frozenset(),
            crashes,
        )
        parent = {start: None}
        queue = deque([start])
        while queue:
            state = queue.popleft()
            runs, visible, closed, edges, left = state
            moved = False
            for i, (pc, chosen) in enumerate(runs):
                if pc == "done":
                    continue
                moved = True
                nexts = []
                if left > 0:
                    nexts.append((("done", chosen), visible, closed, edges, left - 1, f"r{i}.crash@{pc}"))
                open_now = visible - closed
                if pc == "pre":
                    nexts.append((("aread" if open_now else "commit", None), visible, closed, edges, left, f"r{i}.pre"))
                elif pc == "commit":
                    nexts.append((("back", None), visible | {i}, closed, edges, left, f"r{i}.commit"))
                elif pc == "back":
                    head = first(open_now)
                    lost = closing_helper and head is not None and head != i
                    nexts.append((("close" if lost else "aread", None), visible, closed, edges, left, f"r{i}.back"))
                elif pc == "close":
                    nexts.append((("aread", None), visible, closed | {i}, edges, left, f"r{i}.close"))
                elif pc == "aread":
                    head = first(open_now)
                    if head is None:
                        nexts.append((("done", None), visible, closed, edges, left, f"r{i}.aread(none)"))
                    else:
                        nexts.append((("aedge", head), visible, closed, edges, left, f"r{i}.aread={head}"))
                elif pc == "aedge":
                    nexts.append((("done", chosen), visible, closed, edges | {(bead_of[i], chosen)}, left, f"r{i}.edge->{chosen}"))
                for run, vis, clo, edg, lft, label in nexts:
                    after = (runs[:i] + (run,) + runs[i + 1:], vis, clo, edg, lft)
                    if after not in parent:
                        parent[after] = (state, label)
                        queue.append(after)
            if moved:
                continue
            if len(visible - closed) >= 2:
                result["two_open"] = True
            held = {}
            for bead, gate in edges:
                held.setdefault(bead, set()).add(gate)
            gone = sorted(bead for bead, gates in held.items() if gates <= closed)
            if gone and result["released"] is None:
                path, cur = [], state
                while parent[cur] is not None:
                    cur, label = parent[cur]
                    path.append(label)
                result["released"] = (order, gone, path[::-1])
    return result


CASES = [
    ("one filer", 1, 0, "one bead", 0),
    ("two filers, one bead", 2, 0, "one bead", 0),
    ("three filers, one bead", 3, 0, "one bead", 0),
    ("three filers, one bead, one crash", 3, 0, "one bead", 1),
    ("three filers, one bead, two crashes", 3, 0, "one bead", 2),
    ("two filers and a bare waiter, one bead", 2, 1, "one bead", 0),
    ("two filers, own beads", 2, 0, "own beads", 0),
    ("three filers, own beads", 3, 0, "own beads", 0),
    ("two filers and a bare waiter, own beads", 2, 1, "own beads", 0),
]

if __name__ == "__main__":
    for name, writers, bare, beads, crashes in CASES:
        closing = explore(writers, bare, True, beads, crashes)
        keeping = explore(writers, bare, False, beads, crashes)
        print(
            f"{name}: closing helper releases={'yes' if closing['released'] else 'no'} "
            f"two open={'yes' if closing['two_open'] else 'no'}; "
            f"keeping helper releases={'yes' if keeping['released'] else 'no'} "
            f"two open={'yes' if keeping['two_open'] else 'no'}"
        )
        if closing["released"]:
            order, gone, path = closing["released"]
            print(f"  shortest release, gates sorted {order}, bead {gone}: " + " ".join(path))
```
