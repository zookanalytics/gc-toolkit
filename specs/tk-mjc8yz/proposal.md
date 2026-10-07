---
name: Represent a converse hold as edges and beads, not a frozen anchor and a held seat
description: The reconciled target model for a converse hold-for-operator sitting, and the three-phase migration that implements it — Phase A re-points the conversation wait off the anchor (resumes tk-kdmfl8), Phase B parks the visit instead of holding a session seat (resumes tk-d3k4qm), Phase C gives an operator ruling a sourced path into the rework machinery (resumes tk-bq9ua). Read assessment.md first.
---

# Target model, and how to get there

`assessment.md` establishes that the doctrine is right and converse applies it
to the wrong targets. The proposal is therefore a re-pointing, not a redesign:
each of a hold's three outputs moves onto the thing the sitting owns, using
primitives that already ship. No new hold primitive, no `merge_result` field
split, no operator-facing mode.

## 1. The target model

A converse sitting has three possible outputs, and each is a bead with an edge:

- **The conversation wait gates the visit, not the anchor.** When the operator
  owes an answer, the demand blocks the *visit* — the conversation cannot
  conclude until the operator answers. The subject anchor is untouched and keeps
  moving. This is the default, and it is the operator's ruling of 2026-09-04
  (Option 1): a conversation about a PR does not freeze the PR.
- **The merge hold is an explicit, edge-backed opt-in on the anchor.** When the
  sitting decides the merge should pause, it takes one documented step that files
  a demand blocking the *anchor*. That is the same edge the merge sweep already
  honors, so nothing in `merge.sh` changes. The hold is an edge to a live bead,
  so check-wait-is-an-edge stays green with no new marker.
- **A ruling's consequence is a rework demand.** When the ruling makes an open PR
  stale, the sitting files a rework child that blocks the anchor, sourced by the
  ruling. The ruling stops being prose nobody reads and becomes the same demand
  the refinery already knows how to land.

And the sitting is not itself a hold:

- **The session is not the wait.** A hold parks the *visit* (a demand blocks it),
  and the session is free to die at that boundary. When the operator engages, a
  fresh session reconstitutes from the record — the release valve tk-h9pq5 was
  built to provide, now reaching the hold-for-operator case.

### Why this is one model, not three fixes

Every output is a demand bead plus a `blocks` edge, and the only design decision
is *what each edge targets*: the visit for the conversation's wait, the anchor
for an explicit merge hold, the anchor for a ruling's rework. The default (track)
and the opt-in (hold) differ by one edge target, which is why no state can encode
the shepherd-versus-hold distinction and none is asked to — the sitting chooses
the target. This is the single behavior the operator converged on: a conversation
holds nothing by default and flags a hold when it means to.

## 2. Why this honors waiting-is-an-edge

Each output is already the doctrine's shape. The conversation wait is a demand
gate on the visit (`gc-helm.sh demand <visit>`), which is a `blocks` edge to a
live same-store bead. The merge hold is a demand gate on the anchor, the shape
converse already files — it only stops being the default. The rework demand is a
rework child blocking the anchor, the shape `signoff.sh` already files. No output
is a bare marker, so check-wait-is-an-edge is satisfied by construction, and the
proposal introduces no `held` flag for the anchor to re-create the parked-marker
anti-pattern the operator's own map (tk-x498m6, 2026-09-17) warned Phase A against.

The one new key, `source_ruling_bead` (Phase C), is registered in
`lifecycle/lifecycle.toml` `[metadata]` alongside `source_review_bead`, so the
field-vocabulary arm does not flag it.

## 3. The migration

Three phases, each shippable alone, each leaving the engine running. The
recommended order is A, C, B: A is the operator's funded priority and the direct
answer to the original wish, C completes the shepherd case A opens, and B is the
deepest and can follow. None hard-blocks another.

### Phase A — the conversation wait leaves the anchor (resumes tk-kdmfl8)

Default track, opt-in hold, done by re-targeting the demand edge.

- `converse-hold.sh` files its conversation demand against the *visit* instead of
  the item, when the item is a PR anchor. The visit is what the conversation
  waits on; resolving it re-readies the visit, and the anchor is never blocked.
  `gc.hold_demand` on the visit is unchanged.
- Add one documented merge-hold step converse takes when it means to pause the
  merge: a demand filed against the anchor (`gc-helm.sh demand <anchor>`), which
  the merge sweep already honors. Document it in the converse prompt (step 5/7)
  and in `docs/gascity-human-engagement.md` as the explicit flag, so a shepherd
  sitting simply omits it.
- `converse-signoff.sh` discharges whichever demands the sitting filed: the visit
  demand always, the anchor demand only if an explicit hold was taken.
- No `pull_request -> held` edge is added and `held` is left as the pre-PR hold
  it is. The anchor gating stays on the edge the sweep already reads, so
  `merge.sh` and `signoff.sh` are unchanged.

Correction to the bead's original scope: tk-kdmfl8's design questions Q2/Q3
proposed unifying anchor gating onto a `held` flag and adding
`pull_request <-> held` edges. The assessment shows the freeze was never `held`
for a live PR, so that unification is unnecessary and would introduce exactly the
marker the doctrine forbids. Phase A keeps anchor gating on the demand edge.

### Phase B — the visit parks, the session does not hold (resumes tk-d3k4qm)

A hold-for-operator parks the visit as a human gate and lets the session reach a
boundary, rather than holding a live seat until the operator returns.

- On taking a hold, converse parks the visit (its own demand gate makes it a
  human-gated bead) and drains at that boundary, instead of holding `in_progress`
  through the wait. The visit is edge-backed, so it is not orphan-recovered and
  not re-offered.
- On engagement, pool demand for the parked visit spawns a fresh session that
  reconstitutes from the subject record (tk-h9pq5's cold path), holds only while
  the operator is live, and drains when they leave.
- This closes the open-visit-walked-away seat leak and the claim/nudge symptom
  bugs, because there is no live seat to leak and no mid-hold nudge to
  misread.

Correction to the bead's premise: tk-d3k4qm's "governed by the execution
backstop" is falsified by the manual-origin cutover (tk-2i4bde / tk-fry37b);
Phase B is scoped to the residual live-seat model, and its authority is tk-h9pq5,
not a backstop patch. Direction A of the bead (park plus on-demand fresh session)
is the shape adopted; directions B and C are not.

### Phase C — a ruling reaches rework (resumes tk-bq9ua)

A converse-invocable rework dispatch that takes an anchor and a ruling as its
provenance.

- Add a ruling-sourced entry into the existing rework machinery: create a rework
  child stamped `task_kind=rework`, `anchor_bead`, `branch`, `target`,
  `rejection_reason` (the ruling), `merge_strategy=mr`, and the PR fields, block
  the anchor on it, and sling `mol-polecat-work` — the `signoff.sh:952-981` shape,
  sourced by a new `source_ruling_bead` in place of `source_review_bead`.
- Register `source_ruling_bead` in `lifecycle/lifecycle.toml` `[metadata]`.
- Wire it into `converse-signoff.sh` so a `--ruled yes` whose consequence is a
  stale open PR files the rework rather than only resolving the demand.

This makes the operator ruling a first-class rework origin beside the review
verdict, which the bead argues is the structural gap. The alternative doctrine
the bead floated — close and re-pour a published PR that needs ruling-driven
rework — is rejected: it discards the PR's review history and its green checks,
where the rework child preserves both by resuming the anchor's own branch.

## 4. Disposition of the three sub-problem beads

Each is resumed as its phase, with its scope or premise corrected in a note that
points here. None is folded and none is superseded: all three name real,
distinct work, and the design changes what each builds, not whether it is built.

| Bead | Face | Disposition | Correction recorded |
|---|---|---|---|
| tk-kdmfl8 | merge | resumed as Phase A | freeze is the demand edge, not `held`; keep anchor gating on the edge, drop the `held`-flag unification (Q2/Q3) |
| tk-d3k4qm | session | resumed as Phase B | execution-backstop premise falsified by the manual cutover; scope to the residual live-seat model under tk-h9pq5, adopt direction A |
| tk-bq9ua | ruling-to-rework | resumed as Phase C | shape confirmed: rework child sourced by a new `source_ruling_bead`, reusing `signoff.sh`'s rework path |

The phases are left unblocked, as the parent design bead left the three: a
blocked-but-unrouted bead is the debt check-blocked-work-armed flags. They await
the operator's adoption of this design at its review, not a `blocks` edge.

## 5. Reconciliation with work in flight

- **tk-i1axe4 / tk-whufad** (convert `merge_hold` prose to demand + edge, going
  forward and backlog). Phase A's explicit merge hold is the same demand-plus-edge
  shape these establish, so Phase A aligns with them rather than competing; the
  anchor hold converse files is already the target shape they convert toward.
- **tk-qf055w / tk-rdgyfp** (field vocabulary). Phase C's `source_ruling_bead`
  registers into the `[metadata]` registry these complete; Phase C should land
  after or alongside the registry so the new key is defined where it is added.
- **Symptom bugs.** tk-qgrnq8, tk-6p3tpo, tk-d8nd3h are subsumed by Phase B (no
  live seat, no mid-hold nudge). tk-5wdhtg (folding a visit drops the merge hold
  its `pr_number` carried) is subsumed by Phase A: once the merge hold is an edge
  on the anchor rather than a stamp on the visit, folding the visit cannot drop
  it. Each should be closed against its phase, not worked separately.
- **tk-h9pq5** (conversation as continuation group) is Phase B's design authority;
  Phase B is the hold-for-operator case reaching the turn-boundary release valve
  that spec defines.
- **docs/waiting.md divergence.** Beads cite a doctrine home that never landed
  (assessment §6). No committed file cites the missing path, so no repo change is
  owed; the doctrine's live home is `docs/component-model.md` I1. Recorded here so
  a reader who follows a stale bead citation is not sent looking for a file that
  was never merged.

## 6. If nothing is done

The 2026-09-04 ruling funded the merge fix and it stalled for thirteen days,
which the operator named as the broken city failing to unstick itself. Leaving it
means the shepherd case stays inverted: a conversation opened to help a PR land
holds it from landing, and the operator clears each one by hand. The session seat
keeps leaking on every walked-away visit, and every operator ruling that bears on
an open PR stays in notes that nothing reads. The three are one defect; fixing one
face leaves the other two alive and, in the case of a merge-only fix, risks the
new marker the doctrine exists to prevent.
