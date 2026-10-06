---
name: finalize-gate
description: The precondition set that decides whether a bead may be finalized — its PR merged or the bead closed — with the open-visit clause that holds finalization while a conversation is owed on that bead, and the orphan-gate clause that holds it while a human gate on the bead has lost its conversation.
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

**Boundaries.** The demand bead and its `blocks` edge — the separate record of
what a person owes a converse sitting — belong to `docs/gascity-human-engagement.md`
and `assets/scripts/gc-helm.sh`. What subject a visit covers is defined once in
`assets/scripts/visit-identity.sh` and the mol-visit formula. The merge cadence's
other arms live in `docs/refinery-merge-cadence.md`, and the lifecycle state
machine in `docs/state-machine.md`.

## What it checks

`finalize-gate.sh check <bead-id>`:

- exit 0 — every clause passed; the bead may be finalized (no output).
- exit 1 — a clause refuses; the one-line reason is on stdout for the caller to log.
- exit 2 — usage error.

### Clause: no open visit

An open visit whose subject is this bead refuses the bead's finalization. A visit
is a subject-scoped conversation a person owes an answer to (the mol-visit
formula). A visit covers its subject by the shared visit identity
(`assets/scripts/visit-identity.sh`): its outgoing `tracks` edge, or — the
fallback for a visit whose edge has not landed — its `gc.continuation_group`
stamp. The gate reads both from the subject's end and holds finalization while
any open `task_kind=visit` covers the bead:

- the subject's incoming `tracks` edges —
  `gc bd dep list <bead> --direction=up -t tracks` returns exactly the beads
  whose tracks edge points at it;
- the visits stamped with this subject —
  `gc bd list --metadata-field gc.continuation_group=<bead>` returns the ones
  covering it by the fallback. `escalate.sh` stamps a visit at creation and adds
  its tracks edge in a later write, so a stamped visit with no edge yet is open
  and owed here; one that already carries a tracks edge is covered by the edge,
  not the fallback, and is not counted twice.

A `tracks` edge is non-blocking. So the gate holds only this bead's finalization:
it never consults the bead's readiness, and it never reaches the bead's children.
A visit on an epic holds the epic's own close and leaves every child free to move.

### Clause: no orphan gate

An orphan human gate on this bead refuses its finalization too. A converse hold
can leave a human demand gate that names this bead in `gc.demand_for`, and the
bead's work blocks on it. The gate's `gc.gate_visit` names the visit that
carries its decision, and `gate-visit-sweep` never re-offers a gate that carries
that stamp. So when the visit closes without a decision, the gate stays open,
keeps blocking the bead, and has no conversation left to ask for one. The
no-open-visit clause cannot see this case, because the visit is already closed.

The clause lists every open, in-progress or blocked bead carrying
`gc.demand_for`, with `--include-gates`, since a plain `gc bd list` hides gates.
It keeps the unassigned ones that name this bead, because an assigned gate is a
person's task and not a decision a visit carries. A kept gate is an orphan when
its `gc.gate_visit` names a visit that is neither open nor in progress: closed,
missing, or unreadable. A gate with no `gc.gate_visit` is not an orphan, since
the sweep will offer it a visit. Neither is a gate stamped `skip`, the
operator's suppression, or `filed`, the sweep's stamp for a visit it filed
without learning its id.

The refusal names the two ways to clear an orphan. Re-ask it with
`gc bd update <gate> --unset-metadata gc.gate_visit`, so the sweep offers a fresh
visit, or resolve it with `gc bd gate resolve <gate>`. `gc-helm.sh dismiss`
holds until each linked gate is resolved or re-asked, and applies those
decisions before it closes the visit. This clause is the backstop for any other
path that closes a visit and leaves its gate. A gate list that does not read, or
does not answer with a JSON array, refuses the finalization.

## Fail closed

A tracker list that does not read, or does not answer with a JSON array, refuses
the finalization. An unreadable probe is never an all-clear: the act it guards —
a squash-merge, a close — cannot be taken back.

## Where it is wired

- **Merge** — `assets/scripts/merge.sh`. The merge arm runs the gate as an ordered
  validation before the squash-merge, and re-asserts it at the terminal re-read
  immediately before the merge. A visit is filed without moving the PR head, so
  `--match-head-commit` does not catch one raised between validation and the
  merge; the terminal re-assert does.
- **Close** — `assets/scripts/bead-rehome.sh`. The sanctioned close-with-successor
  path runs the gate before the close. The successor pointer is already stamped,
  so a hold leaves an open, pointed, findable bead — the same shape a refused
  close leaves. The release is to conclude the open visit, then re-run.

`assets/scripts/lifecycle.sh` closes only into `merged`, and on the merge path
that close is the bookkeeping that runs after the irreversible merge — so the
merge is gated before it happens, in `merge.sh`, not at that close.

## Composability

The gate is a set so a later precondition — an epic's goal-met, for instance — is
one more clause in `finalize_gate_check`. A caller never learns which clause held:
it reads the one-line reason and holds.
