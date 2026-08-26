---
name: Molecule-scoped step-close
description: Why step-close.sh resolves by (gc.root_bead_id, gc.step_ref) instead of by assignee, what each derivation source is for, and the determination on the second half of tk-xgfhj3 — the finalizer that clears assignees.
---

# Molecule-scoped step-close

Bead tk-xgfhj3 reported one symptom and named two candidate defects. This
records what each turned out to be, and what was decided about the half that
this repository does not own.

## 1. The key was not unique

`step-close.sh` resolved a step bead from `(assignee, gc.step_ref)`. That pair
is not unique. A pool agent wears one assignee for every molecule it has ever
run, so the pair matches the same step of every earlier run — and those are all
closed.

Measured on the gc-toolkit store, 2026-08-26, for the assignee
`gc-toolkit--gc-toolkit__polecat-1-pool`: closed `mol-polecat-work.*` step beads
exist under roots tk-4ffl70, tk-j2ddcs, tk-k7uhme and tk-p0gi4s, each covering
all six step refs. Any close that failed to find a live bead of its own would
match one of those.

Two failures follow from the one key, and the hermetic suite reproduces both
against the pre-change script:

- **A close that never happened, reported as a pass.** With no live bead of its
  own — the reported case, where the chain's beads had lost their assignee — the
  resolver fell through to the closed tier, matched another molecule's bead, and
  printed `already closed — nothing to do`, exit 0. Six such lines are what a
  finished chain and a completely unclosed chain both look like.
- **A live bead of another molecule, closed.** `in_progress` outranks `open`, so
  an earlier molecule's step still in progress under the same assignee wins over
  this chain's own `open` bead. That is a step removed from a workflow nobody
  was running.

Only `(gc.root_bead_id, gc.step_ref)` is unique, and the pour stamps
`gc.root_bead_id` on every step bead. Resolution is scoped to it; the assignee
now corroborates rather than identifies.

## 2. Establishing the molecule

The scope is only as good as the derivation, and the derivation has to survive
the conditions that made the bug visible — a chain whose assignees are gone.
Four sources answer in order, each only when it names exactly one root:

1. `--root`, for a caller holding `root_bead_id` from `gc hook --claim --json`.
2. A `--bead` hint that already verified.
3. `gc.session_id`, the stamp a claim leaves on the step it hands out.
4. This session's live beads: the one for this step first, then any bead of the
   same formula.

Source 3 alone is not enough, because the stamp is not universal: the six steps
of root tk-4ffl70 carry `gc.session_id=lx-2rrxb`, and the six of tk-j2ddcs carry
none. Source 4 covers those, and it is also what closes a step whose own bead is
no longer at an executable tier — the siblings still open in the same molecule
answer for it.

An ambiguous source is treated as no answer rather than as a refusal, so a
session carrying husks from earlier runs still resolves through a later source.

When nothing establishes the molecule, an executable bead is still closed on the
old pair — that path is unchanged — but a *closed* match is refused, because a
closed match is exactly the shape that cannot be told apart from a foreign one.
The cost of that refusal is a visible line on a step that was already closed;
the cost of the alternative is the silent husk this bead is about.

## 3. The second defect: assignees cleared mid-run

The bead attributed the assignee clear to the workflow finalizer, and reported
that it hits the work bead too, leaving it open, unassigned and unrouted while
carrying a branch — a bead nobody polls.

It asked which of two changes to make: close the step chain *before* the
handoff, or stop the finalizer touching a bead outside the molecule.

**Neither, from here.** The ordering is not the defect: the handoff is the last
thing that must be true before the chain unwinds, and closing the chain first
lets the finalizer force-close stragglers while `submit-and-exit` is still
running. What the finalizer writes belongs to the control-dispatcher in the gc
binary, which this pack does not contain. The fix available here is the one
above — make the close path independent of the assignee, so a chain that has
lost its assignees still closes.

The stranded work-bead shape does not reproduce as an outstanding population.
Measured 2026-08-26 over the gc-toolkit store, the query from the bead (open,
no assignee, empty `gc.routed_to`, has `branch`, no `merge_result`) returns two
beads, both work in flight at the time of the query. The finalized molecules
sampled — tk-4ffl70 and tk-j2ddcs — kept their step assignees, and their work
beads sit at `merge_result=pre_open_gate`, which is where the pre-open codex
gate parks a first handoff on purpose.

What would re-open the question: a work bead open with a branch, no assignee,
empty route, and no `merge_result` at all, outliving the session that pushed it.
That is a gascity bead when it appears, not a pack one.
