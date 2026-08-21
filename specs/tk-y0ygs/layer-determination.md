---
name: Layer determination for deferred dispatch (tk-y0ygs)
description: Which layer each of tk-y0ygs's three fix directions needs, why only one of them is reachable from pack content, and what the two gc-side directions would take if the operator decides to spend a binary change on them.
---

# Which layer can hold a pending dispatch (tk-y0ygs)

tk-y0ygs carries an explicit constraint:

> `bd ready` is the beads binary and the demand query may be gc. **The
> operator is deliberately avoiding gc patches right now.** If the fix
> cannot be done in pack content, STOP and surface which layer it needs
> rather than reaching for a patch — that decision is the operator's, not
> this bead's.

So the first work was to establish, from source, where each of the
bead's three fix directions would have to live. One of the three is
reachable from pack content. It was built; the other two are surfaced
here and **not** started, and no bead was filed against `gascity` for
them either — filing one would be making the layer decision the bead
reserves for the operator.

## What was re-derived first

The bead's structural claim holds, verified live rather than taken on
trust (`tk-hlec6`, a `mol-polecat-work` pour observed from inside it on
2026-08-21):

| Record | Edges it actually carries |
|---|---|
| step bead (`load-context`, `tk-2dbqx`) | one `tracks` edge to the workflow root. Nothing else. |
| workflow root (`tk-hlec6`) | one `blocks` edge to its own `workflow-finalize` step. `gc.input_convoy_id` points at the input convoy as **metadata**. |
| work bead (`tk-y0ygs`) | its own deps only. Nothing in the poured tree points at it with an edge. |

No edge from the poured tree reaches the work bead, and no readiness
query walks a metadata pointer. `gc sling` has no flag for this
(`gc sling --help`: no `--after`, `--when`, `--defer`) and no non-test
file under `internal/sling/` reads blocker state at all.

## Direction 3 — a durable deferred-dispatch record — **pack-reachable, built**

The bead's own framing was *"sling accepts a blocked bead, stamps the
intent on the bead, and something reconciles it when the blocker
closes."* Only the first clause needs `gc`, and it turns out not to be
needed at all: `gc sling` does not *refuse* a blocked bead, it dispatches
one too eagerly. So the intent can be stamped by a different caller, and
`gc sling` is never asked to do anything new.

Both halves are ordinary pack content:

- `assets/scripts/deferred-dispatch.sh` — `arm` / `disarm` / `list` /
  `reconcile`.
- `orders/deferred-dispatch.toml` — a `cooldown` exec order at
  `scope = "rig"`. Packs ship `orders/` (this one already ships seven),
  order discovery scans them per importing rig, and `exec` is run as
  `sh -c` from the rig root with `GC_RIG` / `BEADS_DIR` supplied by the
  runner (`shellExecRunner`, `cmd/gc/order_dispatch.go:142-149`). An
  `exec` order needs no pool, so it does not hit the unbound-registration
  trap that `doctor/check-rig-scoped-orders-bound` exists to catch.

Two beads-side capabilities made it clean, and both were verified
against the running binary rather than assumed: `bd list
--has-metadata-key <key>` gives presence-indexing without knowing any
value in advance (`--metadata-field` can only match an exact value, which
a per-bead target is not), and `bd list --ready` composes with it, so
dispatchability is beads' own predicate rather than a private copy of the
blocking-type rules.

The user-visible difference from the bead's framing: the entry point is
`deferred-dispatch.sh arm`, not `gc sling`. An agent that calls
`gc sling` directly on a blocked bead still pours immediately. The
mechanism is opt-in at the call site, and that is a real limitation, not
a presentational one — see [What direction 3 does not
buy](#what-direction-3-does-not-buy).

## Direction 1 — teach the demand path to read the work bead's deps — **gc, and expensive**

Not reachable from this pack even in degraded form, for a reason worth
recording: **`[[patches.agent]]` cannot set `work_query`.** `AgentPatch`
(`internal/config/patch.go`) carries `ScaleCheck` but has no `WorkQuery`
field, and the `polecat` pool is imported from the gastown pack rather
than defined here, so this pack cannot reach its offer query at all. It
*could* patch `scale_check` alone — which would be worse than doing
nothing: that gates only the reconciler's spawn decision while the offer
served to a live worker stays unchanged, which is exactly the
`scale_check ↔ work_query` protocol-mismatch class that
`bdReadyPoolDemandShell`'s own comment warns against.

In `gc`, the patch site is `bdReadyPoolDemandShell`
(`internal/config/workquery.go:180-181`), the single shell shared by the
worker offer (Tier 3) and the reconciler's count form
(`poolDemandCountShell`, `:293-295`). The predicate reads the step or
root bead; to reach the work bead's deps it would have to follow
`gc.root_bead_id` → root → `gc.input_convoy_id` → convoy → member, per
candidate. That is a metadata-pointer walk no readiness query performs
today, and it turns the city's hottest query into O(candidates) extra
`bd` reads against the shared Dolt — a cost this pack's own
`tools/gc-proactive.sh` already calls out as prohibitive for a
work_query. Highest blast radius of the three.

## Direction 2 — give the poured graph a gating-visible edge — **gc, and the cleanest of the three**

The narrow version: at pour time, copy the work bead's *open* blockers
onto the entry step as `blocks` edges, so `load-context` is not Ready
until they close. Nothing else changes — the offer, the demand count and
`bd ready` all keep working exactly as they do, because the gate is
expressed in the vocabulary they already read. No new writer, no
reconciler, no polling, and a blocker closing releases the dispatch
through the existing path with no latency.

Sites: the step's upward edge is written at
`internal/molecule/graph_apply.go:299-316` (the `Type: "tracks"` edge and
the comment explaining why it is deliberately non-blocking); the root's
own formula deps at `addWorkflowRootDeps`,
`internal/formula/compile.go:672`. Note the
edge must land on the **entry step**, not the root — the root is already
excluded from `bd ready` by its `in_progress` status and its own `blocks`
edge to `workflow-finalize`, so gating it changes nothing observable.

Its one structural limitation is why it does not fully supersede
direction 3: the copy is a **point-in-time snapshot taken at pour**. A
`blocks` edge added to the work bead *after* the pour still gates
nothing, because by then the workflow exists and a worker may already
hold it. Direction 3 avoids that by not pouring at all until the bead is
clear.

These two are complementary, not alternatives: direction 2 makes an
already-poured workflow honor the deps that existed when it was poured;
direction 3 keeps the pour from happening early in the first place.

## What direction 3 does not buy

Stated plainly so nobody reads the shipped mechanism as more than it is:

- **It is opt-in.** `gc sling <target> <blocked-bead>` behaves exactly as
  before. Nothing prevents an agent from bypassing the arm — this is a
  remedy in code for the agent that *reaches for it*, and doctrine is
  what points them at it (`docs/gascity-routing-model.md`'s "How to
  actually hold a bead" now does).
- **It adds a writer,** which the bead flagged as the cost to weigh. The
  mitigation is the per-rig single-flight the order runner already
  provides — the open-tracking gate keys on `ScopedName()`
  (`deferred-dispatch:rig:<rig>`) — plus a reconcile pass that refuses to
  sling anything `bd` has not called ready, anything already routed, and
  anything carrying an `assignee`.
- **It does not close a bead its blocker resolved.** See the sibling
  below.

## What the live control caught

The hermetic suite runs against stubs, so the mechanism was also driven
once end to end against the real `bd` and a real `blocks` edge (two
throwaway beads, `tk-x4hps` blocking `tk-qrn1d`, both closed afterwards;
`gc sling` itself stubbed out via `reconcile --dry-run` so no polecat was
spawned). Armed while genuinely blocked it reported `1 waiting`; with the
blocker closed the same pass reported it dispatchable; closing the gated
bead with the arm still set exercised the retire path for real, and the
bead's notes came out as a complete append-only arm → disarm → arm →
retire trail.

That run paid for itself twice, and both findings are worth not
re-deriving:

- **`bd list --ready` refuses an `--id` filter.** Not "returns nothing" —
  it errors: `validation failed: --ready cannot filter on IDFilter
  (--id); the blocker-aware ready query cannot be narrowed to specific
  ids`. `arm`'s "this has no blocker right now" hint was originally a
  per-id readiness probe, so it could never have fired against live `bd`
  in either direction. It now asks through the same
  `--has-metadata-key … --ready` query the reconcile pass uses, which
  also means the hint and the pass cannot disagree.
- **The stub had accepted that query happily**, which is the fixture
  lying about the tool. It now refuses the combination the way `bd` does,
  and the suite gained the mirror case (a *blocked* bead must NOT get the
  hint) so the assertion is load-bearing in both directions rather than
  passing vacuously.

A third, smaller one, in the control's own setup rather than in the
shipped code: `gc bd dep A --blocks B` writes the dependency row on **B**
(the blocked bead), naming A. `bd dep remove <issue-id> <depends-on-id>`
follows the same convention — and prints `✓ Removed dependency` even when
no such edge existed, so its success line is not evidence the edge is
gone. Read the row back.

## The sibling, tk-4dksv

tk-y0ygs asks that the two not be designed apart without checking. They
were checked, and they are the same shape — an edge type with no
consumer — pointing in opposite directions:

- tk-y0ygs: *"X must land before me"* → the consumer should **dispatch**
  me when X closes. That consumer now exists.
- tk-4dksv: *"X resolves me"* → the consumer should **close** me when X
  closes. Still none. The `until` dependency type already exists with
  exactly those declared semantics — `DepUntil DependencyType = "until"
  // Active until target closes`, `internal/types/types.go:1239` in
  beads — and has no **behavioral** consumer: re-derived 2026-08-21, all
  seven non-test references are vocabulary or display (the `bd schema`
  enum `:1256`, `WellKnownDependencyTypes` `:1283`, a `backend/types.go`
  alias, a label map and an emoji in `cmd/bd/`). Nothing acts on an
  `until` edge when its target closes. (tk-4dksv's mechanik note reached
  the same conclusion and cited `:1046`; the declaration has since
  moved, and "zero consumers anywhere" is now imprecise — the references
  exist, none of them does anything.)

One fix does not cover both, because the dispositions differ — but the
`deferred-dispatch` order is the natural host for the second consumer
when it is built: same cadence, same rig scope, same "an edge closed,
now act on it" pass shape. Building tk-4dksv's half as a second arm of
this order would be cheaper than standing up new machinery, and would
keep both consumers of "a blocker closed" in one place.

There is a partial overlap worth naming: for a bead whose disposition
*was* "dispatch it when clear", an armed record means the bead no longer
re-enters triage as an anonymous ready candidate — the ledger now says
what was owed. That removes tk-4dksv's re-derivation cost for that
subset, and none of the rest.

## The live instance, deliberately not armed

`tk-fkeft` is still held behind `tk-2v08m` by exactly this mechanism, and
still held by the mechanik because nothing else could hold it (verified
2026-08-21: `tk-fkeft` open, unassigned, unrouted, one open `blocks` edge
to `tk-2v08m`, which is itself in flight). It is the obvious first use of
`arm`, and it was left alone on purpose — the dispatch is the mechanik's
to decide, not this bead's to make on its behalf.

## Why `docs/work-bead-state-machine.md` was not touched

The bead invokes that doc's law — a bead is the single locus of truth for
its work — and an armed dispatch is state about the work. But that doc's
`## Scope` says it "describes the lifecycle a single unit of work moves
through **from dispatch to closure**", and explicitly puts "the routing
that delivers work to an agent" out of scope. An armed dispatch is
strictly *before* dispatch. Adding a row to its state table would put
out-of-scope content in an audited doc; the new state is documented in
`docs/deferred-dispatch.md` and cross-referenced from the routing model,
which is the doc that owns pre-dispatch routing.
