---
name: finalize-gate
description: The precondition set that decides whether a bead may be finalized — its PR merged or the bead closed — with the human-gate clause that holds finalization while an open human gate blocks that bead, and the epic-ruling clause that holds an epic until its hypothesis is ruled closed.
---

# The finalize gate

Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR, or
closing the bead. `assets/scripts/finalize-gate.sh` is the one place that
answers, for a single bead, whether every precondition for that act holds. It is
a composable SET of clauses run in order; the first to refuse stops the set and
names why.

## Scope

**Mandate.** The finalize-gate precondition set: the clauses it checks, how a
caller invokes it, its fail-closed contract, and the finalize paths that call it.

**Boundaries.** What a human gate is, who files one and how a person clears it
belong to `docs/human-engagement.md` and `assets/scripts/human-gate.sh`. The
read of a bead's human gates is defined once, as `bd_human_gates` in
`assets/scripts/bd-lib.sh`. The merge cadence's other arms live in
`docs/refinery-merge-cadence.md`, and the lifecycle state machine in
`docs/state-machine.md`.

## What it checks

`finalize-gate.sh check <bead-id>`:

- exit 0 — every clause passed; the bead may be finalized (no output).
- exit 1 — a clause refuses; the one-line reason is on stdout for the caller to log.
- exit 2 — usage error.

### Clause: no open human gate

An open human gate that blocks this bead refuses the bead's finalization. A human
gate is Gas City's native bead for a wait a person must clear (`issue_type=gate`,
`await_type=human`). A bead's human gates are the human gates its `blocks` edges
reach, open and closed alike:

- `gc bd dep list <bead> --type blocks --json` returns each bead the given bead
  depends on through a `blocks` edge, with its type, status, await type, await
  id and assignee;
- the gate keeps the rows whose `issue_type` is `gate` and whose `await_type` is
  `human`, and holds while any of them is in a status other than closed.

bd already refuses an unforced close of a bead an open gate blocks, and the merge
holds on a live blocker of the anchor. The clause states the same hold as an
explicit precondition, because a close path that passes `--force` skips bd's
refusal. A gate blocks only the beads whose edges reach it, so the clause holds
this bead alone and never reads its children. A conversation tracks the bead it
is about and blocks nothing, so it holds nothing here, and neither does any
other `tracks` edge.

### The caller's own report

`finalize-gate.sh check <bead-id> --except-key <situation-key>` names the
situation key under which the caller files, through `human-gate.sh`, its report
of a refused finalization of this bead. That report asks for the retry, so
holding the retry on it would keep the bead from ever finalizing once the
obstruction it reported had cleared. A gate is excepted only when its await id is
that key and no person is assigned it. Every gate under the key is excepted
alike, twins included. A gate assigned to a person holds like any other, and so
does every gate under another key.

bd still refuses the close while an excepted gate blocks the bead. So the caller
that closes resolves those gates first, once nothing else would refuse the close
(below).

### Clause: epic ruling recorded

An epic that carries a hypothesis (`epic_hypothesis`) refuses finalization until
it is ruled close with its outcome recorded (`epic_ruling=close` and
`epic_ruling_reason`). A continue or shift ruling keeps an epic open, so it holds
the epic as an absent ruling does, and so does a value outside the enum. An epic
with no hypothesis predates the model, and a disposed epic (`gc.superseded_by`)
carries a recorded terminal reason, so both pass. A non-epic bead is untouched
([epic-stewardship.md](epic-stewardship.md)). The clause reads the bead itself
(`gc bd show`), so that read runs for every finalize, epic or not. The
`--except-key` exception excepts a human gate, so it never releases an epic this
clause holds.

Neither finalize path wired today reaches an undisposed epic: `merge.sh`
finalizes merge anchors, and `bead-rehome.sh` stamps the disposition before it
runs the gate. A bare `gc bd close` runs no gate, and the doctor invariant I15
(`doctor/check-epic-closed-implies-ruled`) reports an epic closed that way
without its ruling.

## Fail closed

A probe that does not read, or does not answer with a JSON array, refuses the
finalization. An unreadable probe is never an all-clear: the act it guards — a
squash-merge, a close — cannot be taken back.

Every probe reads the store as it stands. A refinery pass memoizes its
`bd_list` reads (`GC_RECONCILE_BD_CACHE`, `assets/scripts/bd-lib.sh`), and the
gate turns that cache off for its own reads, because the terminal re-assert
below exists to see a gate filed after the first check.

## Where it is wired

- **Merge** — `assets/scripts/merge.sh`. The merge arm runs the gate as an ordered
  validation before the squash-merge, and re-asserts it at the terminal re-read
  immediately before the merge. A gate is filed without moving the PR head, so
  `--match-head-commit` does not catch one raised between validation and the
  merge; the terminal re-assert does.
- **Close** — `assets/scripts/bead-rehome.sh`. The sanctioned close-with-successor
  path runs the gate before the close. The successor pointer is already stamped,
  so a hold leaves an open, pointed, findable bead — the same shape a refused
  close leaves. The release is to clear the gate, then re-run.
  `bead-rehome.sh --except-key <situation-key>` hands the key to the gate's
  exception, and `pr-facts.sh` names its own `pr-dispose-failed.<num>` key when
  it retries a pre-recorded PR-close disposition. The retry then closes in three
  steps:
  1. It reads what would hold the close: the gate, and the bead's live blockers
     and open children, which an unforced `bd close` refuses on. Anything but
     the bead's own gates under the key that no person is assigned holds the
     close, and then nothing is resolved or closed.
  2. It resolves each of those gates with a reason that names the retry and
     carries no outcome word, so no quiet period starts.
  3. It closes the bead, unforced.

  Only a blocker or an open child that appeared after step 1 can refuse step 3.
  The bead then stays open with its gate withdrawn, and `pr-facts.sh` files its
  report again under the same key. A run that stops between steps leaves a
  state the next run completes, because a resolved gate stays resolved.

`assets/scripts/lifecycle.sh` closes only into `merged`, and on the merge path
that close is the bookkeeping that runs after the irreversible merge — so the
merge is gated before it happens, in `merge.sh`, not at that close.

## Composability

The gate is a set, so a further precondition is one more clause in
`finalize_gate_check`. A caller never learns which clause held: it reads the
one-line reason and holds.
