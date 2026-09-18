---
name: Helm board grouping — regroup by dependency structure
description: Proposal for tk-492ssx. Presents three render models for grouping the helm board by dependency family instead of attention band, with a recommendation, so the operator picks the shape before the build.
---

# Helm board: regroup by dependency structure

The board groups its rows by attention band. An anchor and the beads that
hang off it — children, blockers, rework, reviews — land in different bands
and scatter across the board, so the operator cannot read a family as one
thing. tk-492ssx makes dependency structure the primary grouping axis and
demotes the attention band to ordering and highlight within a family.

The acceptance criteria reserve the render shape for the operator: the intent
is stated, the shape is not. This document proposes it. It presents what the
board does now, defines what a family is and how to derive it, lays out three
render models with a recommendation, and names the build that follows once a
shape is chosen. No render change ships with this document.

## The decision this asks for

Pick one render model for a family:

- **Model A — nested rows.** The anchor is a row; its family members are
  indented rows beneath it.
- **Model B — family blocks.** Each family is a titled block; members are a
  flat list inside it, band shown as a per-row tag.
- **Model C — family blocks, band-ordered within (recommended).** Model B,
  plus the members inside a block are ordered by attention band and the
  band drives a per-row highlight.

A second, smaller decision rides along: whether the default view keeps its
flat operator-queue partition above the grouped body, or groups that too.
The [open sub-decisions](#open-sub-decisions) section states it and
recommends keeping the queue flat.

The recommendation is Model C with a flat queue on top. The rest of this
document is the evidence for that pick and the build it implies.

## What the board does now

The pipeline is `services/helm/internal/board`; a bare Go filename below
(`derive.go`, `model.go`, a `*_test.go`) lives in that package, and every
other path is written from the repo root. `BuildBoard`
(`derive.go:1566`) turns each gathered `Anchor` into one `Tile` through
`computeTile` (`derive.go:1424`), ranks and deduplicates them, folds visit
and demand wrappers onto their subject (`foldWrappers`, `derive.go:1630`),
tags recurring templates (`tagClusters`, `derive.go:1795`), and partitions
owed rows ahead of the rest (`owedFirst`, `derive.go:1987`).

A tile carries two grouping classifications, both on the wire (`model.go`):

- `Section` — the *kind* of attention a row wants: review, gate, stalled,
  active, cleanup, done (`classifySection`, `derive.go:1397`; `SectionOrder`,
  `derive.go:1382`). One tile lands in exactly one section.
- `ClusterKey` — set when at least three rows in one section share a `Needs`
  sentence, so a repeated template folds to one line (`tagClusters`).

Both renderers group by `Section` and nothing else. The CLI iterates
`GroupBySection` (`derive.go:1828`) one band at a time
(`services/helm/cmd/helm-svc/board.go:499`). The web dashboard buckets
client-side on `tile.section` (`services/helm/web/src/App.tsx:432`). Section
is the top-level axis on both surfaces; dependency structure is not an axis
at all.

### Why families scatter

Six bead *kinds* are selected as tiles. Three are selected by issue type —
epic, decision, convoy (`typedAnchorKinds`,
`services/helm/internal/source/beads.go:455`) — and three by metadata: human
(`gc.routed_to=human`), parked (`gc.takeaway` present), and merge (a
`merge_result`, i.e. a pull request)
(`services/helm/internal/source/beads.go:499-523`).

A selected convoy the city does not own renders as a seventh kind, `unowned`.
`applyConvoyOwnership` (`services/helm/internal/source/beads.go:950`) flips its
`Kind` from `convoy` to `unowned` after selection, so `unowned` is a
convoy-derived rendered kind rather than a separate selection. It follows the
convoy grouping rules below: it keeps the `tracks` children gathered before the
flip, and it gathers no `blocks` edges until the source change in the build
plan. Like any convoy tile it can be a family root, a child, or a blocker, so
the grouping and the build must carry it as a convoy that reads `unowned`.

A parent's ordinary children are not tiles. They roll up into that parent's
counts (`rollUp`), read at all statuses so `n_closed` is real
(`services/helm/internal/source/beads.go:538`). A child surfaces as its *own*
tile only when it is
independently one of the six selected kinds — and that is exactly when a family
breaks apart. An epic with two children where one has opened a PR and the other is
routed to a human produces three tiles: the epic (active or stalled), the PR
child (review), and the human child (gate). `classifySection` bands each on
its own facts, so the three land in three sections and read as three
unrelated rows. The same happens to a `blocks` prerequisite that is itself an
epic, and to a rework or review child that carries a `merge_result`.

The scatter is structural, not cosmetic: the board has no representation of
the edge between a tile and the tile it hangs off, so no renderer can place
them together.

## What a family is

A family is one top-level anchor and every tile that hangs off it by one of
these edges:

- **parent → child**: a child id in an epic's or convoy's rolled-up
  `Anchor.Children` that also has a tile of its own.
- **blocked → blocker**: an id in the anchor's `WaitingOn` / `Blockers` that
  has a tile. The source gathers these `blocks` edges for only some anchor
  kinds today; the join below and the build plan address the gap.
- **rework / review child**: a `task_kind=review` or `task_kind=rework` bead
  that names the family root in `metadata.anchor_bead`. One that has landed a
  `merge_result` or is routed to a human is already a tile; an in-flight one is
  not, and the source must select it — the paragraph below and the build plan
  address the gap.
- **folded wrapper**: a visit or demand bead. `foldWrappers` already collapses
  these onto their subject, so a family inherits that fold rather than
  redoing it.

The parent → child edge needs no new gather. `Anchor.Children`
(`model.go:108`) is already populated for every parent kind that becomes a
tile: an epic from its parent-child dependents, a convoy from its `tracks`
members.

The blocked → blocker edge needs one. `Anchor.WaitingOn` and `Anchor.Blockers`
(`model.go:148`, `model.go:162`) are gathered only for the kinds
`needsWaitingEdges` selects — decision, human, parked, merge
(`services/helm/internal/source/beads.go:640`). Epic and convoy anchors gather
no `blocks` edges: an epic receives only its parent-child children, and a
convoy spends its one dependency read on `tracks`. So an epic or convoy blocked
by another tile reaches `BuildBoard` with an empty `WaitingOn`, and the join
cannot see that blocker. Grouping those kinds by blocker needs a source change
— extend the edge gather so epic and convoy anchors also collect their `blocks`
edges — which the build plan sequences before the derivation that consumes it.

The rework / review edge needs a source selector, not only an edge gather. An
in-flight review or rework bead is an ordinary `task` whose one routing marker
is `gc.execution_routed_to`; it carries no `merge_result` until it lands and no
`gc.routed_to=human`, so it matches neither the typed kinds
(`services/helm/internal/source/beads.go:455`) nor the metadata kinds
(`services/helm/internal/source/beads.go:497`) and reaches `BuildBoard` with no
tile. The acceptance criteria name rework and review beads as family members, so
the source selects them: a not-closed bead carrying `metadata.anchor_bead` with
`task_kind` in `{review, rework}` becomes a tile. It joins through the blocked →
blocker edge it already carries — a review or rework child `blocks` its anchor,
and that anchor is a `merge` anchor, which `needsWaitingEdges` already selects,
so its `WaitingOn` holds the child once the child is a tile.
`metadata.anchor_bead` names the same root directly, so a partial edge gather
still resolves it. Such a child is always a member, never a root: it hangs off
the anchor it blocks.

## The grouping-key derivation

This computation is shared by all three render models, so it is settled
before the shape is:

1. Build a child-to-parent map from every anchor's `Children`, and a
   blocker-to-blocked map from every anchor's `WaitingOn` — the blocker map
   complete only once the source gathers `blocks` edges for epic and convoy
   anchors, per the build plan.
2. For each tile, walk parent and blocked edges upward to its **group root**:
   the top-most ancestor that is itself a tile and has no parent of its own.
   A tile with no such ancestor is its own root.
3. Tiles that resolve to the same root form one family. The root anchors the
   family; the rest are its members.

Add one wire field, `Tile.GroupRoot` (the root's id; equal to the tile's own
id for a root). A tile's `GroupRoot` is enough for either renderer to bucket
families the way both already bucket sections. The additive-contract rule in
`model.go` allows a new trailing field; it forbids renaming or removing one,
so `Section` and `ClusterKey` stay exactly as they are.

Three cases the build must rule on, none of which blocks this proposal:

- **A bead in two families** (blocks two anchors, or is a child of one and a
  blocker of another). Pick one root deterministically — lowest-ranked-owner
  or lowest id — so a bead appears once. State the rule in code.
- **A blocker that is itself a top-level epic.** It is a root of its own
  family and a member of the family it blocks. The same one-root rule
  decides which; the other family shows it as a reference, not a duplicate
  row.
- **Cross-rig edges.** An edge whose other end has no tile in this board
  leaves the tile a root. The family is what this board can see.

## Candidate render models

The mockups use the CLI table; the web dashboard mirrors whatever is chosen,
since both bucket the same wire field.

### Model A — nested rows

```
SEV       ID          KIND    N/M   FRONTIER
ELEVATED  tk-epic1    epic    3/7   4 open, 1 in flight
  REVIEW  tk-child-a  merge   —     PR #812, gate green, owed 2d
  GATE    tk-child-b  human   —     routed to you: pick a shape
NORMAL    tk-epic2    epic    5/9   3 in flight
```

The anchor is a row and members indent beneath it. Compact, and the tree
reads at a glance. The cost is that the band is no longer a column the eye
can scan down: a reader hunting every review now scans indented rows across
families instead of one Review block. Nesting also complicates the cluster
fold and the row cap, both of which count flat rows today
(`ClusterRows`, `CapRows`).

### Model B — family blocks

```
── tk-epic1 · epic · 3/7 · 4 open, 1 in flight ───────────────
  [review]  tk-child-a  merge   PR #812, gate green, owed 2d
  [gate]    tk-child-b  human   routed to you: pick a shape
  [active]  tk-child-c  convoy  2/4 in flight

── tk-epic2 · epic · 5/9 · 3 in flight ───────────────────────
  [active]  tk-epic2    epic    healthy
```

Each family is a titled block; the band rides each row as a tag. The family
is unmistakably one thing. Members appear in whatever order the block emits
them, so a block with one review and five active rows does not lead with the
review.

### Model C — family blocks, band-ordered within (recommended)

```
── tk-epic1 · epic · 3/7 · needs you on 1 ───────────────────
  ● review  tk-child-a  merge   PR #812, gate green, owed 2d
  ● gate    tk-child-b  human   routed to you: pick a shape
    active  tk-child-c  convoy  2/4 in flight
    active  tk-epic1    epic    4 open, 1 in flight

── tk-epic2 · epic · 5/9 · healthy ──────────────────────────
    active  tk-epic2    epic    3 in flight
```

Model B, with two additions. Members inside a block are ordered by
`SectionOrder`, so the most-pressing member leads the family. A band-driven
glyph highlights the rows that want a person (`●` on review and gate). This
is the literal reading of the second acceptance criterion: the band orders
and highlights within a family and is not the top-level axis.

## Recommendation

Model C. It satisfies both binding criteria directly: dependency structure is
the top-level axis, and the attention band is demoted to within-family
ordering and highlight. It reuses the existing per-tile `Section` and
`Severity` rather than inventing a second ranking, so `classifySection`,
`rankScore`, and the cluster fold keep working unchanged inside a family. It
extends the block header of Model B, which is the shape an operator already
reads for a convoy, so it adds no new idiom.

Model A is the fallback if vertical space is tight enough that block headers
cost too much; it trades the scannable band column for density. Model B is
Model C without the within-family ordering, and there is no reason to stop
short of C once the block exists.

## How E and B land on this

The coupling note arms two sibling fixes on the new model:

- **E — section membership** (a parked-for-operator row must not sit in
  Active). Under Model C the band is a within-family signal, so E becomes a
  correction to `classifySection`'s within-family ordering rather than to a
  top-level bucket. The fix is smaller on the new model, because a misfiled
  band no longer moves a row to a distant part of the board — it only
  misorders it inside its family.
- **B — aggregate rows carry per-bead context**. A family block *is* the
  aggregate with its context: the members that B wants surfaced are the block
  rows, each carrying its own id, band, and frontier. B lands as the block
  body rather than as a new column on a flat row.

## Build plan

Once a shape is chosen, one build bead implements, in this order:

1. The source-side blocker gather in `services/helm/internal/source/beads.go`:
   extend `needsWaitingEdges` and `attachEdges` so epic and convoy anchors
   collect their `blocks` edges into `WaitingOn` / `Blockers`, behind tests in
   `services/helm/internal/source/beads_test.go`. A convoy already issues the
   dependency read for its `tracks` members, so this extracts the `blocks`
   edges it already returns; an epic must be added to that read. Without this
   step the blocked → blocker edge is invisible for those kinds and the join
   groups only their children.
2. The source-side selector for in-flight review and rework children in
   `services/helm/internal/source/beads.go`: admit a not-closed bead carrying
   `metadata.anchor_bead` with `task_kind` in `{review, rework}` as a tile,
   behind tests in `services/helm/internal/source/beads_test.go`. Without it
   these beads reach `BuildBoard` with no tile and the join cannot place them,
   so the family misses the review and rework children the acceptance criteria
   name.
3. The grouping-key derivation and `Tile.GroupRoot` in `derive.go`, with the
   one-root rule for the three edge cases. The walk keys on the parent and
   blocker edges, not on `Tile.Kind`, so a convoy that renders `unowned` groups
   as the convoy it is: its `tracks` children are its family. This is the
   shape-independent core, behind its own tests in `derive_test.go`.
4. The chosen render in both surfaces: `GroupBySection` and
   `services/helm/cmd/helm-svc/board.go` for the CLI, the `tile.section`
   bucketing in `services/helm/web/src/App.tsx` for the dashboard.
   `services/helm/web/src/contract.ts` and
   `services/helm/web/src/board.fixture.json` gain `group_root`.
5. E and B folded into the new model, per the section above.

The row cap (`CapRows`, `CapQueue`) and the template-cluster fold
(`tagClusters`, `ClusterRows`) both count flat rows today and must be
re-derived against families; the build bead owns that. Tests to update:
`derive_test.go`, `sections_test.go`,
`services/helm/cmd/helm-svc/board_render_test.go`,
`services/helm/cmd/helm-svc/board_test.go`,
`services/helm/web/src/App.test.tsx`, and the fixtures. The `derive_test.go`
cases include an `unowned` convoy as a family root, as a child, and as a
blocker, so the grouping is exercised across the full rendered-kind set.

## Open sub-decisions

- **Does the default view group too?** The default answers the operator's
  queue — owed rows, oldest first (`OperatorQueue`, `derive.go:2029`) — above
  the city overview. The queue is a linear to-do list the operator burns down;
  grouping it by family would scatter that list across family blocks.
  Recommendation: keep the queue flat and owed-first, and apply family
  grouping to the city overview (`--all`) and the body beneath the queue. The
  owed rows still carry their `GroupRoot`, so a reader can pivot to a row's
  family on the overview.
- **Family ordering.** Order families by their strongest member: the family
  containing the oldest-owed or highest-ranked row leads. This keeps the most
  pressing family at the top without re-introducing band as the top axis.
- **Root selection for a shared bead.** Named above as an edge case; the build
  picks the deterministic rule and states it in code.
