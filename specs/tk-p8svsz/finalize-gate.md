---
name: finalize-gate-design
description: The design record for tk-p8svsz — a visit holds only its subject's finalization (merge/close), fail-closed, never downstream work. Why the gate reads the tracks edge, where it is wired, and why the operator's named close seam (lifecycle.sh) was not the one used.
---

# A visit holds only its subject's finalization

> **Bead:** tk-p8svsz · **Kind:** design + implementation record · **Ruling:** operator, 2026-09-29
> **Authoritative model:** `docs/finalize-gate.md` (what is true now). This file records why.

## Problem

A converse hold filed a demand as a `blocks` edge on the subject. When the
subject is a container (an epic), bd's `is_blocked` cascades down parent-child
legs unconditionally, so the demand froze every child of the epic — armed
dispatches never fired while the coordination sitting stood open. Root finding:
tk-g6xcwi.

## Ruling (operator, 2026-09-29)

A visit holds ONLY its subject's finalization, and NEVER downstream work, in any
situation.

## Model implemented

The hold lives at the finalize gate, not in the dependency graph. Finalizing a
bead is merging its PR or closing the bead; `assets/scripts/finalize-gate.sh` is
a composable "may this bead be finalized?" precondition set. Its first clause:
an open visit whose subject is this bead refuses that bead's finalization.
Subject-scoped, fail-closed, and — because it reads a non-blocking `tracks` edge
rather than placing a `blocks` edge — it never touches the bead's readiness or
its children. `docs/finalize-gate.md` is the present-tense description.

## Decisions

### The signal is the shared visit identity: tracks edge, then continuation_group

A visit's coverage is the shared visit identity (`assets/scripts/visit-identity.sh`
is the one matcher; mol-visit files it): its outgoing `tracks` edge, or — the
fallback for a visit whose edge has not landed — its `gc.continuation_group`
stamp. The gate reads both from the subject's end:

- The subject's incoming tracks edges: `gc bd dep list <bead> --direction=up
  -t tracks --json` returns exactly the beads whose tracks edge points at the
  subject; the clause keeps the open `task_kind=visit` rows.
- The visits stamped with the subject: `gc bd list --metadata-field
  gc.continuation_group=<bead>` returns the ones covering it by the fallback; the
  clause holds for any open `task_kind=visit` among them whose tracks edge has not
  landed. A stamped visit that already carries a tracks edge is covered by the
  edge, above, and is not counted twice.

Both reads are targeted, not a population scan. `gc bd list --status=open,in_progress`
alone returns the whole open population (~1180 beads live), and the merge arm runs
the gate twice per anchor every cadence pass; the reverse-dep query and the
metadata-field query are each local to the one bead, matching merge.sh's existing
per-anchor `gc bd dep list` probes. The reverse-dep row does not carry a
`.dependencies[]` array (it carries the edge's `dependency_type` at top level), so
the `-t tracks --direction=up` query establishes coverage by the edge itself; the
fallback is confirmed by a `--direction=down -t tracks` probe on each stamped
candidate, empty exactly when the edge has not landed.

The continuation_group fallback is consulted because its state is reachable, not
degenerate: `escalate.sh` creates a visit already stamped with the subject, then
adds the tracks edge in a separate write it does not read back, so a stamped visit
with no edge yet is an open visit the board and converse already honor. A gate that
read only the edge would allow the subject's merge or close while that visit stands
— the fail-open this targeted query closes.

### Fail closed

A tracker list that does not read, or does not answer with a JSON array, refuses
the finalization. A squash-merge and a close are both irreversible; an unreadable
probe is never an all-clear.

### Wired at the merge gate, and at the non-merge close — but not lifecycle.sh

The operator's ruling named `merge.sh` and `lifecycle.sh`. `merge.sh` is correct
and is wired at two points: the ordered validation before the squash-merge, and
the terminal re-read immediately before it — a visit is filed without moving the
PR head, so `--match-head-commit` cannot catch one raised mid-pass; only the
terminal re-assert can.

`lifecycle.sh` is **not** the non-merge close seam, on reading it:
`LIFECYCLE_CLOSED_STATES="merged"` (lifecycle.sh) — its only close is into
`merged`, and on the merge path that close is the bookkeeping `merge.sh` runs
*after* the irreversible `gh pr merge`. Gating it there would either be a no-op
(the merge arm already passed the gate) or actively wrong (refusing a close after
the PR has merged leaves a merged-but-open bead). The actual non-merge close of a
subject goes through `assets/scripts/bead-rehome.sh` (the sanctioned
close-with-successor; `liveness-sweep.sh` already says in prose that a visit
subject "is dispositioned through its own visit and bead-rehome.sh, never
bare-closed"). So the close-side gate is wired there, before the close. The
pointer is already stamped at that point, so a hold leaves an open, pointed,
findable bead — the shape a refused close already leaves.

### pr-facts retires a stale visit before the rehome, not after

`pr-facts.sh` consummates a pre-recorded PR-close disposition through
bead-rehome.sh, then retired the stale `pr-abandoned.<num>` visit afterward. With
the gate on bead-rehome's close, that order deadlocks: the stale visit tracks the
anchor, so the gate would hold the very close whose disposition already answers
the visit's question. The retirement is moved before the rehome. The disposition
marker on the anchor — not the visit — drives a retry, so retiring first is safe
even if the close does not land that pass. A *different* open visit (a live
conversation, not the stale rework-or-close one) still holds the close, and
pr-facts escalates the refusal to a human — which is correct.

## Scope boundary

- **tk-g6xcwi** owns the complementary container-safety half — refusing to place
  a demand `blocks` edge on a parent-child container. This work does not reverse
  it: it adds the finalize gate as the subject-scoped hold and does not touch
  `gc-helm.sh demand` or `converse-hold.sh`. The demand mechanism still exists;
  retiring it in favor of the finalize gate is later work, not this bead.
- **tk-u4z8me** owns the direct-container-gate doctor check. Not this bead.
- No bd change. No stale-visit sweep (the helm board carries hold visibility;
  board slice is helm epic tk-ikpyzn).

## Tests

- `finalize-gate.test.sh` — the clause over the hermetic bd stub: open visit
  holds, closed visit does not, subject-scoped, non-visit tracker does not hold, a
  `blocks` edge is not a `tracks` edge, and the unreadable probe fails closed.
- `merge.test.sh` — an open visit holds the merge (and names it), a closed visit
  does not, and a visit filed mid-pass is caught by the terminal re-read.
- `bead-rehome.test.sh` — a gate refusal holds the close (exit 5), leaving the
  origin open with its pointer stamped.
- `pr-facts.test.sh` — the pre-recorded disposition still retires its stale visit
  (now before the rehome).
