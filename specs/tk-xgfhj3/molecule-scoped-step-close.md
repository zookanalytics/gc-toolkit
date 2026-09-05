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

Three failures follow from the one key, and the hermetic suite reproduces each
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
- **A stale hint, obeyed.** `--bead` carries `.bead_id` from a claim, and a
  caller resuming after a hook-claim can hold one from an earlier molecule. With
  the assignee as the only test it verified, so the closed-hint arm printed
  `already closed — nothing to do` over another chain's bead even when the caller
  had supplied the correct `--root`. Where no other source named a molecule, the
  hint supplied one itself, which put the same false green back with the root
  gate in place: scoped by a root taken from the hint, the gate can only agree.

Only `(gc.root_bead_id, gc.step_ref)` is unique, and the pour stamps
`gc.root_bead_id` on every step bead. Resolution is scoped to it; the assignee
now corroborates rather than identifies.

## 2. Establishing the molecule

The scope is only as good as the derivation, and the derivation has to survive
the conditions that made the bug visible — a chain whose assignees are gone. A
caller-supplied `--root` is taken as given, for a caller holding `root_bead_id`
from `gc hook --claim --json`. Failing that, three sources answer in order, each
only when it names exactly one root:

1. `gc.session_id`, the stamp a claim leaves on the step it hands out.
2. This session's live bead for this step.
3. Any live bead of the same formula under this session.

Source 1 alone is not enough, because the stamp is not universal: the six steps
of root tk-4ffl70 carry `gc.session_id=lx-2rrxb`, and the six of tk-j2ddcs carry
none. Sources 2 and 3 cover those, and source 3 is also what closes a step whose
own bead is no longer at an executable tier — the siblings still open in the same
molecule answer for it.

`--bead` is not among them. `verify()` cannot scope a candidate to a molecule
while the molecule is still being derived, so at that point a same-assignee,
same-step bead from an earlier run verifies exactly as this chain's own would. A
root taken from one scopes every resolution below it to the wrong chain, and
then vouches for that same hint on the way back out — which is how the
closed-hint arm reports another chain's bead as already closed at exit 0. A hint
is thus refused as a source outright, while sources 2 and 3 answer but do not
authorize on their own, which is §2a.

An ambiguous source is treated as no answer rather than as a refusal, so a
session carrying husks from earlier runs still resolves through a later source.

Once the molecule is known it gates every answer below it, the hint included: a
candidate whose `gc.root_bead_id` differs is rejected and named, whatever its
assignee says.

When nothing establishes the molecule, an executable bead is still closed on the
old pair where no rival contradicts it (§2a), but a *closed* match is refused
outright, because a closed match is exactly the shape that cannot be told apart
from a foreign one.
The `--bead` arms that act take the same rule: with no molecule `verify()` is
back to the non-unique pair, so a hint reading `open` or `in_progress` is not
closed and one reading `closed` is not reported as done. Both fall through to
the store, which applies the rule above. The arms that only report still run —
a hint parked at `blocked` is the fact the reader needs, and naming it acts on
nothing.

The cost of that refusal is a visible line on a step that was already closed;
the cost of the alternative is the silent husk this bead is about.

## 2a. An assignee-derived molecule authorizes nothing on its own

Sources 2 and 3 read the assignee, which is the pair the scoping exists to
replace. A root they name is therefore not independent evidence, and one shape
turns that into a wrong close: this chain's own bead carries no assignee, no
`gc.session_id` and no `--root`, while an earlier molecule's bead for the same
step is still live under the same assignee. Source 2 names the earlier
molecule, the scoped close lands there, and this chain's step stays open.

So the molecule has to be named by something the assignee did not supply —
`--root`, or the `gc.session_id` a claim stamps — before a close may rest on
it. Where only the assignee names it, the script asks whether anything else
could be this shell's own bead: a live bead for this step, outside that
molecule, that no other session holds by assignee or by session stamp. One such
bead makes the answer a guess, and the guess is refused.

The refusal is scoped to that doubt rather than to the derivation, so the
common case is unchanged: with no live rival for this step outside the derived
molecule there is nothing else this shell could be running, and the close
proceeds on the assignee as before. What it costs is a stalled step whenever a
same-step husk is live and the chain carries no stamp — visible, and still
reachable by the finalizer. What it buys is that no close lands in a chain this
shell never ran.

Deriving the molecule from a `--bead` hint is refused outright rather than
guarded, because a hint is not evidence at all: the only thing naming the
molecule would be the bead the molecule was then used to vouch for.

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
above — key the close to the molecule, so a chain that has lost its assignees
still closes wherever the molecule is named, and refuses rather than lands in
another chain where it is not.

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
