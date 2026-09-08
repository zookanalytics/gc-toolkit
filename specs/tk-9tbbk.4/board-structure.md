---
name: Helm board structure — attention bands, wrapper fold, template clusters
description: The design decisions behind the tk-9tbbk.4 board refresh — the attention-type section taxonomy and its order, the visit/demand fold that ends row-doubling, the template-cluster threshold, and the ruling that cross-rig beads stay on the board. Read when changing how the Helm board groups or folds rows.
---

# Helm board structure

The board was a flat ranked list — a hundred-plus unlike rows (a pull request, a
decision, a stranded epic, a finished conversation) in one column, ordered by a
proxy weight. This work gives it structure along three axes, all landed in the
shared derive layer (`services/helm/internal/board`) so the `helm-svc board` CLI
and the dashboard render over one classification rather than each inventing its
own.

The live census that grounded these decisions (2026-09-08, `helm-svc board --all
--json --limit=0`, whole city): 611 rows, of which 407 were the DONE band; of
the ~204 live rows, 55 were `visit:` wrappers and the dominant recurring
templates were "routed to you — no question recorded" (49), "no children —
decompose or assign" (19), the cap-3 signoff row (18), and the first-reaction
gate (later 12). Counts move; the shapes are what the design targets.

## Sections (attention-type bands)

Each tile carries a `Section` computed by `classifySection`, orthogonal to
`Severity` (which says how badly, not what kind of move). One row lands in
exactly one band. The bands, in `SectionOrder`:

1. `review` — a pull request wants the operator (any merge anchor).
2. `gate` — a person must answer: a decision, a demand, a human-routed bead, or
   a parked conversation whose blocker landed (anything `Owed` that is not a PR).
3. `stalled` — open work with nothing moving it, or an unowned convoy.
4. `active` — healthy in-flight roll-up work.
5. `cleanup` — finished, empty, or ruled — dispose of it (the `LOW` floor).
6. `done` — the anchor's own bead has closed.

Precedence is the arm order in `classifySection`: `done` wins over everything
(a closed row is not competing for attention); a live merge anchor is `review`
even when it is also owed (the PR round-trip axes carry the wedge); `gate` comes
before the health bands because a demand the operator owes is the operator's
move, not "stalled work". The order leads with the operator's own moves (review,
gate), then the city's health (stalled, active), then the quiet tail (cleanup,
done).

**Decision the operator can revisit.** The original brief listed "gate" and
"decision" as separate example bands. They are merged into `gate`: a decision
IS a human gate, and the operator resolves both the same way (answer it).
Splitting them would add a band for a distinction the rig column and the row's
own kind already carry.

## The visit/demand fold (row-doubling)

A visit bead (`task_kind=visit`, tracking its subject in
`gc.continuation_group`) and a demand bead (`gc.demand_for`) each carry
`gc.routed_to=human`, so each is gathered as its OWN `human` anchor — a second
row for an attention item its subject already carries. The doubling is
deliberate, correct graph structure: a `tracks` edge keeps the visit claimable,
and beads refuses a parent→descendant `blocks` edge, so the demand must be a
sibling. It therefore cannot be fixed in the graph; the renderer recognises the
edges.

`foldWrappers` (a BuildBoard pass, after dedup, before the owed partition)
resolves each wrapper against the tile set:

- **Subject has a live row** → fold. The wrapper's ask (the visit title, minus
  the `visit: <id> — ` prefix; or the demand's authored question) moves onto the
  subject, which becomes owed — and held when the wrapper is a visit, since
  `held` is visit presence and a demand is not — and the wrapper's own row is
  dropped. The subject's owed clock takes the wrapper's ask instant, so the queue
  dates the row by when the person was first asked.
- **Subject has no row** → keep the wrapper. A wrapper can name a plain bead that
  is no anchor, and dropping the wrapper would erase the only trace of the
  attention; its needs is rewritten from its own title so the kept row states the
  ask instead of the empty "routed to you — no question recorded".

**A closed wrapper never folds.** A visit or demand that has itself closed is a
finished conversation, not a live ask; it stays in the DONE band. Folding it
would mark a live subject owed on the strength of an ask that already ended, and
would pull the closed wrapper out of the DONE band it belongs in.

## Template clusters

`tagClusters` stamps `ClusterKey` on every row that is one of at least
`clusterThreshold` (3) rows sharing a section and a `Needs` sentence. A renderer
folds them into one line naming the count with the members listed. The threshold
is 3 because two identical asks are a coincidence a reader absorbs at a glance,
while three is a template worth collapsing.

The wire still carries every member (the fold is render-only), so
`tmux-pick-helm.sh` and anything else reading the JSON array is unchanged. A row
with an LLM-authored takeaway is unique and never clusters; the DONE band is
left alone (already capped and recency-ordered).

## Cross-rig beads stay

The board is the cross-rig human-attention surface by design (its own header and
README say so), so cross-rig beads remain on it — a signal-loom decision and a
gc-toolkit decision are both `gate` rows, distinguished by the rig column, which
is the right axis. No rig-based filter was added: which rigs belong on the
operator's board is a policy the operator sets, not a structural fix, and the
attention-type bands plus the rig column already organise the interleaving the
brief raised. If the operator wants product-strategy beads (signal-loom
monetization/brand) scoped out, that is a follow-up policy toggle, not a change
to this structure.

## Contract

Both fields are appended to `Tile` (the struct-tag contract is additive), mirrored
in `web/src/contract.ts`, and pinned in `board.fixture.json` and the parity test.
Both renderers read the fields; neither re-derives the split. The CLI groups via
`GroupBySection`/`ClusterRows`; the dashboard replicates the trivial grouping in
TypeScript because the hard decision — which band, which cluster — is already on
the wire.

## Out of scope

The retired bash board (`assets/scripts/gc-helm.sh`) renders no board and was not
touched. The 68s gather time the funding conversation also raised is a separate
sibling concern, not addressed here.
