---
name: pr918-membership-mechanics-review-reconciliation
description: The record behind the four-relationship rewrite of membership-mechanics.md — a post-merge review of PR 918 (verbatim), and the disposition of each of its ten findings against the code and docs they cite.
---

# PR 918 review and reconciliation

PR 918 merged `specs/tk-xgj2ko/membership-mechanics.md`. A post-merge review found
that the spec's central approach — auto-parent all coordination-routed work as a
`parent-child` child of its subject ("create-time parenting"), and retire the
demand's `blocks` edge as "redundant for gating" — misclassifies relationships by
construction and contradicts `docs/component-model.md`. This record holds the
review verbatim and the disposition of each finding. The resolved model is in
[`membership-mechanics.md`](membership-mechanics.md); `docs/component-model.md`
was reconciled to agree with it.

The error was never children. Decomposition as a child is correct and is how
beads intends epics to work (`bd create --parent`). The error was a blanket rule
that parented things which are gates or dependencies, and a claim that one gating
mechanism makes another redundant. The resolution is the four-relationship model:
a bead is a member (a `parent-child` child), a halt (a `blocks` edge on the
epic), a hold on finalization (the finalize-gate on the `tracks` edge), or a
dependency (a sibling `blocks` edge). Each relationship has one mechanism, and
create-time parenting becomes an advisory indicator that surfaces the likely epic
(the subject when it is an epic, otherwise its epic ancestor) rather than a law
applied to everything.

## Disposition of the ten findings

Each finding was verified against the code or docs it cites before this rewrite.
Nine hold; one (#3) is factually wrong and is dropped with its reason.

1. **Sign-off `blocks` / `--waiting-on` not accounted for — HOLDS.**
   `gc-helm.sh takeaway --waiting-on` writes `subject` blocked-by `work` as a
   `blocks` edge; if that work is a member (child), the edge runs
   parent→descendant and beads refuses it, degrading the wait to prose. The spec
   now branches that write on the relationship (member: no edge; dependency: the
   edge). Addressed in the "sign-off's wait-for-work edge" section.

2. **"Demand's `blocks` edge redundant for gating" — HOLDS (the claim was
   false).** The finalize-gate reads only `tracks` and the subject's own
   finalization; it never consults readiness (`docs/finalize-gate.md`). So it
   cannot hold work out of the pool, and the demand's `blocks` edge is not
   redundant — it is a different mechanism for a different job. Resolved by the
   four-relationship table: hold-finalization (finalize-gate, no cascade) and
   halt/depends-on (`blocks`, cascades, holds readiness) are distinct.

3. **"Re-homing in-flight work strands it" — DROPPED, factually wrong.** The
   claim was that an inherited (parent-cascade) block prevents `bd close`, so an
   in-progress bead re-parented under a blocked epic is stranded open. The beads
   close guard refuses only on a live direct blocker: its predicate is
   `blocked && len(blockers) > 0`, and `blockers` is built only from direct
   `blocks`/`waits-for`/`conditional-blocks` edges on the issue
   (`internal/storage/issueops/close.go`,
   `internal/storage/issueops/dependency_queries.go`). A parent-cascade sets the
   `is_blocked` column on the child with no direct edge
   (`internal/storage/issueops/blocked_state.go`), so it drives `bd ready`
   readiness but not the close check. An in-flight re-homed bead still closes
   when its PR merges. The real cascade-unsafe case is unstarted dispatch, which
   the halt holds out of the pool; the repair primitive hard-refuses that.

4. **"Refuses or warns" is not safe — HOLDS.** A warning still performs the
   freezing write, and the audit that calls the primitive is non-interactive, so
   the warning is never read. The repair-primitive spec now says hard-refuse.
   Addressed in the "membership repair" section.

5. **Subject is not always an epic — HOLDS.** Blanket parenting under the
   subject turns a leaf (a task, visit, gate, or merge anchor) into a container.
   Resolved by making create-time parenting an advisory indicator that surfaces
   the likely epic (the subject when it is an epic, otherwise the epic in its
   ancestry) and offers it as an overridable default. The parent is never blindly
   the subject; a non-epic subject with no epic ancestor yields no suggestion; and
   parenting happens only when the work genuinely belongs.

6. **Contradicts component-model (routed work is a sibling) — HOLDS.**
   `docs/component-model.md` stated flatly that work handed out by a sitting "is
   not a part of `S`". That is too absolute. Both docs now agree: routed work is
   a dependency (sibling) by default, a member (child) when it genuinely
   decomposes an epic subject, with "the subject is an epic" as the indicator.
   `docs/component-model.md` was reconciled in the same change.

7. **Misstated reason for sibling filing — HOLDS.** The documented reason is that
   beads refuses a parent→descendant `blocks` edge, not that "a sibling inherits
   no block" (`assets/scripts/converse-parent.sh` states this reason directly).
   Corrected in the "why a `blocks`-bearing gate or dependency is a sibling"
   section.

8. **"Scattered" premise overstated — HOLDS.** The board already groups
   sibling-filed work through a shared parent or through the `WaitingOn`/`blocks`
   climb (`services/helm/internal/board/derive.go`). Scattering happens only for
   a parentless subject with no wait edge. The scope of the fix is narrowed to
   that case.

9. **Climb description incomplete — HOLDS.** The climb reads `tracks` edges
   (through a convoy's children) and `metadata.anchor_bead`, not "parent-child
   and `blocks` alone", and the `parent-child` roll-up is gathered only for epic,
   human, parked, and merge anchors (`services/helm/internal/source/beads.go`
   `needsParentChildren`). Corrected in the "how the board groups" section.

10. **Visits conflated with demand-gates — HOLDS.** A visit is parentless and
    attached by a `tracks` edge, held by the finalize-gate; a demand-gate is a
    true sibling with a `blocks` edge (`services/helm/internal/board/derive.go`).
    They are now separated: visits are the hold-finalization relationship,
    demand-gates are the depends-on relationship.

tk-n18e15 (converse hold → finalize-gate) is correct under this model — it is the
hold-finalization relationship — and is unaffected.

## The review, verbatim

> The review of PR #918 finished with 10 findings, all against
> specs/tk-xgj2ko/membership-mechanics.md (the only file in the PR). Nothing was
> posted to the PR.
>
> Design gaps that would break behaviour if implemented as written
>
> 1. Line 110: --waiting-on edge is not accounted for. Sign-off writes a blocks
>    edge from the subject to every routed work bead (gc-helm.sh:1260). Once
>    tk-9wojzh files that work as a child of the subject, beads refuses the edge
>    and the wait degrades to prose only. The spec lists neither this wiring nor
>    gc-helm.sh takeaway among the sites to change.
> 2. Line 105: the demand's blocks edge is not "redundant for gating". The
>    finalize-gate only checks for an open visit by tracks and never consults
>    readiness (docs/finalize-gate.md:54-56). After a --ruled no sign-off closes
>    the visit, the blocks edge is the only thing holding the item. Retiring it
>    lets the pool claim and merge while a person still owes an answer.
> 3. Line 171: re-homing in-flight work is not safe. An inherited block also
>    prevents close (bead-rehome.sh:15-16). An in-progress bead re-parented under
>    a blocked epic is stranded open after its PR merges, and the primitive's
>    "refuse or warn" rule only checks unstarted beads.
> 4. Line 174: "refuses or warns" does not make the primitive safe before
>    tk-n18e15. A warning still makes the freezing write, and the periodic audit
>    is non-interactive. The spec needs to fix the behaviour as refuse, or carry
>    a dependency on tk-n18e15.
> 5. Line 144: the parent is undefined when the subject is not the epic. If the
>    subject is a task or merge anchor under epic E, filing under the subject
>    turns a leaf into a container. That contradicts the repair primitive's own
>    "not an epic" refusal at line 159.
>
> Contradictions with existing docs and code
>
> 6. Line 65: I1 says the opposite about routed work. docs/component-model.md:247-252
>    says work handed out by a sitting "is not a part of S" and sits beside it.
>    The spec cites I1 as its foundation but does not reconcile this, and
>    component-model.md is not in the rewrite list.
> 7. Line 99: the reason for sibling filing is misstated. The documented reason
>    is that beads refuses a parent-to-descendant blocks edge, not that "a sibling
>    inherits no block". Retiring the demand's edge leaves that constraint in
>    place.
> 8. Line 130: the "renders scattered" premise is overstated. Sibling-filed work
>    already groups under the epic, through the shared parent or through the
>    --waiting-on edge (derive.go:2581-2585). Scattering only happens with a
>    parentless subject and no wait edge.
> 9. Line 45: the climb definition is incomplete. Convoy tracks edges and
>    metadata.anchor_bead also climb. parent-child children are gathered only for
>    epic, human, parked or merge anchors (beads.go:649-655).
> 10. Line 114: demand gates and visits are conflated. Only visits carry tracks,
>     and visits have no parent at all, so "all are siblings" is wrong for them.
>
> Not checked: the referenced beads (gc bd does not run outside a city directory)
> and the beads behaviours the spec asserts (one edge type per pair, the --parent
> rejection message).
>
> Findings 1, 2 and 7 share a root: the spec treats the demand's blocks edge as
> the only obstacle to create-time parenting, when the subject-waits-on-work edge
> and the post-sign-off hold both depend on blocks too. I'd resolve that first,
> since it likely reshapes the tk-9wojzh scope.
