---
name: The converse-hold model, as it behaves now
description: What a converse hold-for-operator sitting actually does today, mechanism by mechanism, across the merge layer, the session layer, and the ruling-to-rework gap — and the two premises the sub-problem beads (tk-kdmfl8, tk-d3k4qm, tk-bq9ua) were filed on that no longer hold. Read this before proposal.md.
---

# Assessment

A converse sitting is a bounded conversation about a subject bead. When the
sitting decides the operator must answer before the work moves, it takes a
hold. The operator observed on 2026-09-04 (subject tk-x498m6) that such a hold
can keep a subject PR from merging, and asked for a visit that shepherds a PR
and then closes itself. Reconciling that produced three sub-problem beads —
tk-kdmfl8 (merge), tk-d3k4qm (session), tk-bq9ua (ruling-to-rework) — which the
operator then ruled must be solved as one, under the waiting-is-an-edge doctrine
(tk-s4fg87). This assessment establishes what the hold does now, so the proposal
can say what changes.

The three faces are one defect stated three ways: converse models a human
conversation as pool work. It gates the subject anchor so the PR freezes, it
keeps a live session seat for the duration of the wait, and it leaves the
operator's ruling in prose that nothing reads. Each is the same category error —
a wait that should be an edge, or an output that should be a bead, expressed as
something else.

## 1. What a converse hold does today

The hold is written by `assets/scripts/converse-hold.sh` (step 5 of the converse
prompt). It resolves the item as the visit's `stall_root`, else the subject
(`converse-hold.sh:50-52`); for a conversation about a PR the item is the PR's
anchor bead. It then writes three things:

1. a board-visible takeaway headline on the item (`converse-hold.sh:58`,
   best-effort);
2. a demand bead, via `gc-helm.sh demand "$ITEM" "$NEED"`
   (`converse-hold.sh:66-67`), gated so the caller must not post the framing if
   it does not land;
3. `gc.hold_demand=<demand>` on the visit, read back before the sitting waits
   (`converse-hold.sh:91-99`), the sole proof a resume reads to tell a real hold
   from a claim that died early.

Where the item is still `unanchored` it also transitions to `held`
(`converse-hold.sh:106-108`). The sitting is discharged by
`converse-signoff.sh` (step 7): on `--ruled yes` it resolves the demand gate and
releases a `held` item back to the pool; on `--ruled no` it re-states the demand
so the wait stays a graph edge (`converse-signoff.sh:107-138`).

## 2. Face 1 — the merge freeze is the demand's edge, not the `held` state

tk-kdmfl8 was filed on the premise that the freeze is the `held` merge_result
state and that the fix is to reuse `held` as an explicit flag. The sitting
re-diagnosed this on 2026-09-04, and the code confirms the re-diagnosis: the
freeze is the demand bead's `blocks` edge, and `held` is not involved for a live
PR.

`gc-helm.sh demand <gated> "<text>"` files a native human gate
(`issue_type=gate`, `await_type=human`) as a sibling of the gated bead, adds a
`blocks` edge so the gated bead is blocked by the gate, and stamps
`gc.demand_for=<gated>` (`gc-helm.sh:1011-1034`). Because `converse-hold.sh`
passes the anchor as `<gated>`, the anchor is blocked by the demand.

The merge sweep honors that edge. Its in-flight-holder arm reads the anchor's
`blocks` blockers and holds the merge on any live one (`merge.sh:471-512`). A
blocker is only marked `progressing` when a pool is behind it — the route is the
discriminator, and a demand carries route empty or `human`
(`merge.sh:513-525`). So a converse demand holds the merge without marking it
progressing: the anchor sits in the "asking" state, frozen until the demand
closes.

`held` cannot be the freeze for a live PR. The `merge_result` machine has only
two `held` edges, `unanchored -> held` and `held -> unanchored`
(`lifecycle.sh` transition table); there is no `pull_request -> held` edge, and
`converse-hold.sh` transitions to `held` only when the item is `unanchored`.
A bead already at `pull_request` is never moved to `held`, so `held` never drops
it from the sweep. `held` is real, but it is the pre-PR hold; the PR freeze is
the edge.

The consequence the operator hit is exactly the shepherd inversion recorded in
tk-x498m6: a converse opened to unstick a PR files a demand that then blocks the
signoff reset which would unstick it. `signoff.sh` refuses a reset while a live
demand holds the anchor (`signoff.sh` `takeaway_is_holding`), so the demand must
be closed with the ruling before the reset, which the quoted session re-derived
live.

## 3. Face 2 — the pool-seat premise is falsified; the residual is the live seat

tk-d3k4qm was filed (2026-09-05) on the premise that converse holds an
`in_progress` pool claim governed by the execution backstop, dodging the reap
with `nudge=""` and `idle_timeout=0`. That premise no longer holds. The
manual-origin cutover (tk-2i4bde, #696; tk-fry37b, #701) made converse a manual,
spawn-on-engagement session that is never `pool_managed`. All three claim
backstops gate `governs()` on `pool_managed`, so none of them reaches a converse
sitting whatever the nudge holds; the manual origin is the exemption, and the
empty nudge is documented as belt-and-suspenders, not the protection
(`agents/converse/agent.toml:19-31`). The execution backstop does not govern
converse.

What remains true is narrower and still real: converse keeps a live session for
the whole duration of a hold. Reaps are disabled to protect the hold, so a
session whose visit is still open — the operator engaged, then walked away —
holds a `max_active_sessions` seat with no clean end. `converse-reap.sh` collects
a session only once its visit is closed; the open-visit-walked-away case is named
in the config as the ending it does not reach (`agent.toml:47-53`). The symptom
beads are the live evidence that the seat is modeled wrong: tk-qgrnq8 (a held
visit outlives its lease and the pool re-offers it), tk-6p3tpo (action=hold
cannot tell a claim-and-die from a held sitting), tk-d8nd3h (a claim nudge
mid-hold reads as an instruction to abandon). All three are open.

The intended direction already exists in the converse design authority. tk-h9pq5
("conversation as continuation group") makes turn boundaries the release valve:
a visit records its outcome on the subject and closes, and the session is free to
die because a fresh session reconstitutes losslessly from the record. The gap is
that a hold-for-operator does not reach a boundary — it parks mid-visit and keeps
the seat — so the release valve never fires for the one case that most needs it.

## 4. Face 3 — a ruling has no path to rework

A converse ruling lands in three places, none of which produces work:
`converse-signoff.sh` stamps the closing takeaway on the item, resolves or closes
the demand gate with the ruling as its reason, and (through the prompt's step 6)
appends the ruling to the subject's notes. There is no branch anywhere in
`converse-signoff.sh` that mints a rework child or wires a `blocks` edge against
a published PR. When the ruling's consequence is that an open PR is now stale,
the ruling is authenticated and undeliverable — the evidence in tk-bq9ua is a
signal-loom bead that carried two operator rulings in its notes for seventeen
hours while its PR read review-ready.

The canonical rework path is review-driven and cannot be borrowed as-is.
`signoff.sh` request-changes creates one rework child (`signoff.sh:952`), stamps
it `task_kind=rework`, `anchor_bead`, `branch`, `target`, `rejection_reason`,
`source_review_bead`, `merge_strategy=mr`, and the PR fields
(`signoff.sh:964-975`), then blocks the anchor on it (`signoff.sh:981`) and
slings it. Every field is present except one: `source_review_bead` names the
verdict the rework answers, and an operator ruling has no verdict. Minting a fake
verdict to reuse the path would fabricate provenance. The path is right; converse
needs a ruling-sourced entry into it.

## 5. The three are one defect

State the three faces as a single sentence and the shared cause is visible: a
converse hold gates the subject anchor (so the conversation's wait freezes the
work), holds a live session seat (so the wait is modeled as pool execution), and
records its ruling only in prose (so the conversation's product reaches nothing).
Each mistakes what the sitting owns. The sitting owns the conversation, not the
subject's merge, not a work-pool seat, and not a note nobody reads. The proposal
re-points each output to the thing the sitting actually owns.

## 6. Constraints the fix must honor

- **Waiting-is-an-edge (tk-s4fg87).** A wait is a `blocks` edge to an open bead
  in the same store, and what a person owes is a demand bead. The doctrine is
  invariant I1 in `docs/component-model.md` and `docs/lifecycle-composition.md`.
  It is not in `docs/waiting.md`: that path was written in two intermediate
  commits (5d68d4c5, 951768a1) but did not survive into the merged PR #485, so
  beads that cite `docs/waiting.md` cite a file that never landed. No committed
  file cites the missing path — only bead bodies do, which are historical record
  — so there is no repo cleanup owed; the record here is the correction.
- **check-wait-is-an-edge (`doctor/check-wait-is-an-edge/`).** Every live bead
  carrying a hold marker must also carry a live same-store `blocks` edge. A bead
  carrying `gc.demand_for` is the terminal wait and is exempt; a marker whose
  settled-key is set is answered and exempt. Any new hold the proposal introduces
  must be an edge, a terminal demand, or nothing — never a bare marker, or the
  check flags it.
- **Field vocabulary (tk-qf055w / tk-rdgyfp).** `lifecycle/lifecycle.toml`
  `[metadata]` is the key registry; a key not listed is not pack state, and the
  field-vocabulary arm of the check flags an unregistered key on an open bead.
  Any new key the proposal adds must be registered.
- **The shape law and sling's blindness (tk-s4fg87).** A bead that will carry a
  `blocks` edge must have no `parent-child` children; routed work is a sibling of
  its subject, not a child. `gc sling` reads no `blocks` deps on the graph.v2
  `--on` path, so a blocked bead slung there is armed through
  `deferred-dispatch.sh`, not gated by the edge alone.

## 7. Verdict

The doctrine is right and already published; converse applies it to the wrong
targets. No new hold primitive is needed and no `merge_result` field split is
needed. The fix re-points the conversation's wait onto the visit, makes the
merge hold an explicit edge on the anchor rather than a default one, stops
holding a live seat across the wait, and gives a ruling a sourced path into the
existing rework machinery. That is three phases of edge-and-bead work, set out in
`proposal.md`.
