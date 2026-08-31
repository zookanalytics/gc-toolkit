---
name: Target model for work that is not moving, and its migration
description: The proposed target model — one hold primitive, one demand primitive, and a shape law for routed work — with an incremental migration that converts existing holds rather than breaking them, the answer to whether gc sling should learn to read edges, and how this reconciles with tk-0slbb6, tk-lb3u4m and tk-gdtgvr.
---

# Target model, and how to get there

Read `assessment.md` first. Its verdict is that this is not a redesign: the
rule is the pack's published doctrine, the converging mechanism is proven, and
the demand-bead primitive is already filed 54 times over. What is missing is
that no path requires the edge.

The proposal is therefore mostly about making a default mandatory, plus one
real shape change, plus the check that keeps it true.

## 1. The target model

### One hold primitive

A `blocks` edge from the waiting bead to an open bead **in the same store**.
Nothing else holds work. Everything currently used as a hold either becomes
one of these, becomes a conclusion recorded beside one, or is retired.

The same-store clause is not a detail. A cross-store `bd dep add` reports
success and holds nothing: the bead stays in `bd ready`, and `bd dep list
--json` does not render the edge at all, so every automated reader sees no
wait. A demand about work in another rig is filed in the waiting bead's own
store and names the foreign bead in its body.

### One demand primitive

What a person owes is a bead. Three shapes, and the city already has all
three:

- a ruling only the operator can give: `issue_type=decision`;
- a task only a named human can perform: a bead assigned to them;
- a question that needs a conversation: the visit `escalate.sh` already files.

A demand bead carries the authored headline that today goes into
`gc.takeaway`. That primitive is right and is kept: 140 characters, enforced,
provenance-stamped, written by whoever concluded the sitting.

### The shape law

> A bead that will ever carry a `blocks` edge must have no `parent-child`
> children. Containers do not block; blockers do not parent.

The reason is what the two edges mean, not what the cascade does.
`parent-child` is decomposition: the child is part of the parent's work. A
`blocks` edge is a wait: the source cannot proceed until the target closes.
Routed work is not a part of the thing that routed it. Work `W` handed out by a
sitting on subject `S` is what `S` is waiting for, so filing `W` as a child of
`S` asserts a containment that is not true, and the graph stops describing the
city it is supposed to describe. Read as a graph and nothing else, the accurate
shape is `W` beside `S` with `S` blocking on `W`. That is the shape proposed,
and it would be the right shape with no cascade in the product at all.

The cascade is a consequence rather than a reason, and it is not the thing to
fix. The blocked flag propagates down `parent-child`, which is correct for
decomposition: if a container is held, every part of it is held. It strands
work only where the edge was asserting a containment that was false to begin
with, which is exactly the routed-child shape. beads refuses the sharpest case,
a parent blocked by its own descendant, and that refusal is the same rule
caught at the one point where a machine can catch it. So the answer to "why is
the cascade a problem" is that it is not: the cascade is right and the shape
was wrong.

The one real change of shape is therefore that **routed work stops being filed
as a child of the thing it waits on.** Verified: with `S` and `W` both children
of a container, `S` blocked-by `W` is accepted, `W` stays ready, and closing
`W` returns `S` to `bd ready` automatically.

Where a container is wanted for roll-up, it is a bead that never blocks.

### Prose keeps its job

The conclusion stays prose and is never cleared. `gc.takeaway` and
`blocked_reason` are records of what was concluded, and
`docs/lifecycle-composition.md` is right that they should be. Their defect is
being the *only* record of the wait. Neither is removed; both stop being load-
bearing.

### The demand ages

`liveness-sweep.sh` classifies over `bd ready`, so an edge-blocked bead is
outside its funnel. That is correct today and becomes a hole once edges are
the dominant hold: a demand nobody answers would be invisible to the one pass
that audits for stranded work. The sweep gains one class, `demand`, over open
beads that block something, and reports the ones that have been owed longest.
This is the same list `tk-lb3u4m` phase 1 puts on the board, computed from the
same edges.

## 2. Should `gc sling` learn to read edges?

**No, and the question is narrower than it looks.**

An edge already gates the **claim**. Tier 3 is a `bd ready` read, so a routed
bead with an open blocker is not offered and does not count as pool demand.
Verified against the exact Tier-3 predicate.

That covers Lanes 1, 2 and 3, and Lane 4's classic attach: in all of them the
routed claimable unit is the work bead itself, so its blockers gate it.
Slinging a blocked bead to a pool is therefore already safe — it is routed,
and it is not offered until the blocker closes. Nothing to change.

The blindness is specific to the **graph.v2 formula dispatch** (`gc sling
--on <formula>`), where the pour mints a fresh workflow root that carries none
of the work bead's dependencies, and the claimable step beads hang off that
root by `tracks`. There the work bead's edges are two metadata pointers away
from anything the read side walks.

For that one case, arming remains the mechanism. `deferred-dispatch.sh arm`
records the pending dispatch on the work bead and the rig's
`deferred-dispatch` order performs it once `bd list --ready` reports the bead
ready. Three reasons to keep it rather than teach sling:

- `gc sling` is in the gascity binary, a different repo. Changing it is not an
  increment this pack can make, and it changes behaviour for every caller in
  every city at once.
- The gap is one dispatch path, not the model. Making sling dependency-aware
  would duplicate a predicate `bd` already owns.
- Arming is already built, already converges, and is measured at **zero live
  uses**. The problem is adoption, not capability.

What changes is that arming stops being optional on that path: a blocked bead
slung `--on` is a defect the check flags.

## 3. Migration

Incremental, no flag day, existing holds converted rather than broken. Each
phase is shippable alone and leaves the engine running.

### Phase 0 — make the invariant checkable (no behaviour change)

Build `doctor/check-wait-is-an-edge`, warn-only at first. This is **already
filed as `tk-5r1a12`**, which is itself stuck behind the failure it describes:
capped at three rework rounds, `check.codex=exception@`, `gc.routed_to=human`.
Unblock and rescope it rather than filing a new bead.

Scope it to what the measurements showed:

1. an open bead carrying a hold marker (`triage.hold`, `gc.routed_to=human`,
   `blocked_reason`, `check.*=exception@`, `dispatch_count` at the ceiling,
   `gc.takeaway` used as a hold) with no open `blocks` edge;
2. a `blocks` edge whose target is in another store, which reads as a wait and
   holds nothing;
3. a bead carrying both a `blocks` edge and `parent-child` children, which is
   the stranding shape;
4. a metadata key on an open bead that `lifecycle/lifecycle.toml` does not
   register, which catches the `quiesce.terminal_since` residue and the seven
   unregistered keys in one pass.

Warn-only until phase 3 drains the backlog, then error.

### Phase 1 — make the edge mandatory at the writers (additive)

Every path that files a demand today offers the edge as an option and defaults
to prose. Invert that.

| Writer | Change |
|---|---|
| `assets/scripts/escalate.sh` | add `--blocks <bead>` and wire the edge so the named bead waits on the visit, which is `gc bd dep "$VISIT" --blocks "$BEAD"`. 54 open visits currently gate nothing |
| `formulas/mol-visit.toml` gate-visit block | the block's line 54 suggests `gc bd dep add "$VISIT" --blocks "<id>"`, which exits `unknown flag: --blocks`. `--blocks` belongs to the bare `bd dep <blocker> --blocks <blocked>` form; `dep add` takes the blocked bead and its blocker positionally. Correct the comment to `gc bd dep "$VISIT" --blocks "<blocked-bead-id>"` first, then promote it from suggestion to the block's own step |
| `assets/scripts/gc-helm.sh takeaway` | require `--waiting-on <bead>` or an explicit `--no-wait`; refuse a silent prose-only park. Keep the best-effort edge write, but fail loudly on a cross-store target instead of warning |
| `assets/scripts/signoff.sh` cap arm | file one `issue_type=decision` bead titled from the findings, block the rework child on it, and keep `blocked_reason` as the conclusion beside it |
| `assets/scripts/liveness-sweep.sh` | drop `triage.hold` from the `held-by-design` class; a hold with no edge is an unnamed wait, which is what the sweep exists to report |
| `deferred-dispatch.sh` | unchanged; it is already correct. Phase 1 only starts calling it |

Nothing here breaks an existing hold. Every prose key keeps working and keeps
being read.

### Phase 2 — the converse shape

Owned by `tk-0slbb6`. Sittings end with a demand bead and an edge; routed work
becomes a sibling of its subject rather than a child. The shape law in §1 is
the answer that bead was blocked on.

Two things the implementer needs that are not obvious:

- The board reads `parent-child` children for the `parked` and `human`
  roll-ups (`services/helm/internal/source/beads.go:493-503`). Moving routed
  work to siblings empties that roll-up. The board already derives the same
  answer from edges — `waitingEdges`, `disposition_due`, `ruled` — so the
  roll-up is the workaround and the edge is the replacement. Say so in the PR
  and re-point the gather.
- The demand bead goes in the subject's own store.

### Phase 3 — convert the backlog

87 beads carry a hold marker and no edge. They are not one job. Ordered by
what a conversion needs:

| Class | Count | Conversion |
|---|---|---|
| capped anchors (`exception@` + `dispatch_count` + `blocked_reason`) | 15 | one `decision` bead per anchor, titled from the existing text; block the surviving rework child on it. This is exactly what `tk-gdtgvr` already does for the four gascity cases |
| `triage.hold` | 30 | each names its reason in prose; file the named thing as a bead and block on it, or close the bead if the reason has expired |
| `gc.routed_to=human` without a takeaway | subset of 25 | `tk-lb3u4m` phase 1 renders these as "parked for you, no question recorded", which is the signal that whoever parked it did not finish |
| parked subjects with a takeaway and no edge | subset of 49 | `--waiting-on` retro-fit where the named work exists; a demand bead where it does not |
| `merge_hold` / `rebase_hold` prose | 2 open, 16 closed | agent-written free text read by five fail-closed gates (§4). Same conversion as any prose hold: file the named successor as a bead, block the held bead on it, keep the sentence as the conclusion. `tk-aezem4` already names its successor, visit `tk-4g98t` |

Convert, never clear. A hold whose cause cannot be named is a bead to close,
not a field to blank.

### Phase 4 — retire the duplicates

Once phases 1 to 3 hold, the redundancy in `assessment.md` §4 can be removed
without losing a mechanism:

- `dispatch_count`'s role as a second convergence cap is already gone:
  `signoff.sh` no longer reads it, and it now bounds review dispatches under
  its own `GC_MAX_REVIEW_DISPATCHES` ceiling. Nothing further is owed here.
- `status=blocked` as a hand-set status has no converging behaviour and no
  live use. Remove it from every recipe in favour of the edge that produces
  `is_blocked` derivably.
- `quiesce.terminal_since` has no writer. Unset it on the six beads.
- The seven unregistered keys either enter `lifecycle.toml` or are unset.
- The two `hold:` labels are documented as upstream gascity mechanism rather
  than a local hold, per §4. Nothing to retire here.

## 4. The operator-brake question, withdrawn

An earlier draft filed `tk-shxtwm`, a decision bead asking whether
`merge_hold`, `rebase_hold` and the `hold:mayor` / `hold:external` labels
should become beads, on the premise that they are emergency stops the operator
sets by hand. The operator's answer at PR #485 was that they do not set them,
and that `hold:mayor` looked like a carryover from elsewhere. Both halves check
out, and the premise does not survive them. Re-measured, the two mechanisms
turn out to be different things, and neither is a question for the operator.

**`merge_hold` and `rebase_hold` are agent-written prose, not an operator
brake.** The pack reads them in five places and writes them in none:
`merge.sh:206`, `gate-ensure.sh:402-406`, `pr-open.sh:188-191`,
`pr-facts.sh:289-294`, and `convoy-graduate.sh:96` and `:112-116`, with both
keys registered at `lifecycle/lifecycle.toml:183`. No script sets either key:
this pack only reads them, and gascity's pack does not mention them at all.
Every value present was written ad hoc by an agent with
`bd update --set-metadata`. Eighteen beads have carried one across the five
stores, sixteen closed and two open (`tk-iunfnh` with `merge_hold=true`,
`gc-lhums` with `merge_hold=signoff-cap-reached`), and the values range from
`true` and `false` through slugs like `operator-gated-graduation` to a full
paragraph on `tk-aezem4` that ends "Held by refinery pending operator
disposition of visit tk-4g98t". Each reader treats `""`, `false`, `0` and
`null` as not held and anything else as held, so the key is a free-text field
whose only machine-readable content is whether it is empty.

That is the definition of a prose hold, and it puts B7 and B8 in the same class
as `blocked_reason` rather than in a class of their own. The `tk-aezem4` value
is the clearest case: it names a successor (visit `tk-4g98t`) in a sentence
that no reader can act on. Nothing about it needs an operator ruling, because
it needs the same conversion every other prose hold in §3 needs — the named
successor becomes a bead, the held bead blocks on it, and the sentence stays as
the conclusion beside the edge.

**`hold:mayor` and `hold:external` are not this pack's mechanism at all.** They
are `beadmeta.DispatchHoldLabels` in the gascity binary
(`internal/beadmeta/hold_labels.go`), terms of the gascity claim predicate
excluded by `--exclude-label` on the routed tier. No mayor agent exists in this
city — `gc agent list` has no such row in any rig — so the name describes a
role that is not here. This install's `gc` also predates the commit that added
the labels to the predicate, so they exclude nothing locally today;
`docs/gascity-routing-model.md:41` records that measurement. Across the five
stores exactly one bead has ever carried either label — `gc-vbkys` in gascity,
closed, `hold:mayor` — and no open bead carries one. There is nothing to
convert and nothing to rule on. Upstream owns the mechanism, and this pack's
only stake is not describing it as a local hold.

So no operator ruling is owed. `tk-shxtwm` is withdrawn as premised on a use
that does not occur, and `tk-whufad`, which existed only to apply that ruling,
is rescoped and unblocked. The five readers stay: they are fail-closed vetoes
that cost nothing and correctly stop a merge. What changes is the classification
and the conversion, both of which are now ordinary Phase 3 work.

## 5. Reconciliation with the three beads in flight

**`tk-0slbb6`** — converse sittings end with a demand bead and an edge. It was
blocked on this evaluation for the shape decision. The answer is §1's shape
law: siblings, not children, because routed work is not a part of its subject
and a `parent-child` edge asserting that it is makes the graph wrong before it
makes anything unclaimable. It also asks whether `gc-helm.sh takeaway` should file the
edge or explain why prose alone is correct for that call site. The answer is
that it should file the edge and refuse a silent prose-only park, and that
prose alone is never correct as the record of a wait, though it remains the
record of the conclusion.

**`tk-lb3u4m`** — the Helm board. Phase 1 is presentation over today's signals
and this proposal does not touch it. Phase 2 sources demands from the
dependency graph, which is what §1 produces. Two additions for it: a demand
bead should be gathered even when it blocks nothing yet, and the cross-store
edge finding in `assessment.md` §5 means the board must keep treating an
unreadable or foreign wait as still open, which its existing `WaitingUnknown`
handling already does.

**`tk-gdtgvr`** — repaired the stranded gascity rework children, and closed
while this evaluation was in review. It had already committed to the shape this
proposal recommends: a sibling `decision` bead, titled from the anchor's
existing takeaway, with the rework child blocked on it. **No amendment was
needed and none was proposed**, so it stands as the first instance of the
shape rather than a contradiction of it.

## 6. If nothing is done

The failure is not that work stalls. It is that a stall and a finished job
look identical. 96 beads carry a hold marker, 87 of them name nothing a
machine can resolve, and 54 visits and 10 decision beads hold back exactly one
bead between them. Twelve anchors in this rig are capped, routed to a human,
and waiting on nobody in particular; two of the twelve are the beads filed to
fix this problem, one of them being the bead that would build the check.
