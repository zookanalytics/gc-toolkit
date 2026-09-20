---
name: First reaction as the universal enrichment + triage layer
description: Design proposal to make mol-first-reaction wire neighborhood links behind a scripted-discovery / LLM-validation split — a single low-commitment related edge for confident-but-unproven links, hard actions (close-as-duplicate, parent-child) only through the path that owns their consequence — through one shared edge-writing helper, and to remove the per-sweep sling cap so every idle bead gets a reaction. For operator review before any build.
---

# First reaction as the universal enrichment + triage layer

A design proposal, not an implementation. It covers two facets the bead
(tk-87nwhv.2) names: make first reaction *act* on the neighborhood it already
surveys (Facet A, enrichment), and remove the per-sweep sling cap so every
idle bead gets a reaction (Facet B, coverage). The build beads that come out
of this land as incremental commits on one PR, reviewed holistically.

## Origin and intent

The seed is tk-georjc, an operator dialogue capture. Its "Model C" line was a
render-model approval stitched onto the wrong thread at intake; there is no
lost skill design to recover, so this scope is fresh and set by the operator's
current direction (tk-georjc notes, "Model C: RESOLVED").

The operator's direction is to fold the enrichment into the first-reaction
layer rather than build a separate creation-time skill. The three asks —
associate a bead with the epic it belongs under, link similar beads as
related, and flag likely duplicates — are all derivable from graph and text
state. They do not depend on the live conversation that filed the bead, which
is why folding them into first reaction does not hit the operator's original
worry about losing that context. That worry bites only when capturing
conversation nuance into a *new* bead's body, which is a separate concern
already handled by how converse and mechanik write beads.

The parent epic tk-87nwhv carries an inherited constraint: any capability
moved behind a mechanical trigger must be triggered by a formula step or a
hook, never a bare "invoke X when Y" instruction. Folding enrichment into
`mol-first-reaction` satisfies this — the formula step is the trigger.

## How first reaction works today

`mol-first-reaction` (`formulas/mol-first-reaction.toml`) is a three-step
graph.v2 workflow a proactive-pool worker runs once per bead and then drains:

1. **load-bead** reads the bead's body and its universe slice
   (`tools/gc-bd-universe.sh slice`).
2. **first-reaction** writes a fixed-shape CARD into the bead's notes —
   `Understanding · Found · Proposal · Decision needed · Disposition` — and
   decides the disposition.
3. **advance-and-drain** performs the disposition through
   `assets/scripts/first-reaction-dispose.sh`.

The disposition is one of four exits, chosen from the card:

| Disposition | Exit | Graph effect |
|---|---|---|
| actionable | release the bead to a pool | routed, unassigned, open bead a worker claims |
| blocked | write the wait as a `blocks` edge | bead held by a named blocker |
| close | route to a validating closer (`mol-validate-close`) | a capable pool re-checks the no-work call and closes, or escalates |
| ruling | file a visit | held conversation the operator lands in |

The `## Found` section of the card *names* related beads and candidate epics.
The reaction never acts on them. Every edge an exit does write is a control
edge, never a neighborhood link: the blocked disposition's `blocks` edge from
the subject to its blocker, the close disposition's transient `blocks` edge
from the subject to the reaction's own workflow root (to gate the deferred
closer), and the ruling exit's `tracks` edge from a freshly filed visit to its
subject. No `related`, `parent-child`, or duplicate link into the subject's
neighborhood is ever wired. That is the gap Facet A closes.

The universe slice the reaction reads is 1-hop and titles-only: it returns the
bead's *existing* parent, children, and dependency edges, with counts and a
title manifest (`tools/gc-bd-universe.sh` `slice_json`). It performs no
similarity search, so any related, duplicate, or candidate-epic bead that is
not already an edge is invisible to the slice. Today the reacting agent finds
those, when it finds them at all, by ad-hoc judgment. There is no defined
discovery step.

## Facet A — enrichment

### Enrichment is a separate axis from disposition

The four dispositions answer one question: what is the subject's next forward
move? Exactly one applies. Enrichment answers a different question: how is the
subject wired into its neighborhood? Several answers can apply at once, and
they are independent of the forward move. A bead can be actionable *and* belong
under an epic *and* be related to two others. So enrichment is additive and
orthogonal, and the design treats it as its own pass that runs regardless of
which disposition the card chose.

### Discovery is cheap and scripted; the intelligent call is at the disposition

Split the work into a cheap stage and an expensive one, and put each where it
belongs.

- **Discovery** is a set of scripted rules that surface candidates, and
  nothing more. Similarity is a net for finding pairs worth a closer look, not
  the decider: set it too tight and real duplicates never reach evaluation, too
  loose and the candidate list explodes. It runs on the primitives `bd`
  already ships, with no API key:
  - `bd search <query>` — text search over titles (and `--desc-contains` for
    descriptions), all statuses by default, so "was this already filed?" cannot
    silently answer no. Bounded by `--limit`.
  - `bd find-duplicates --method mechanical` — token-based Jaccard similarity,
    fast and free, tunable by `--threshold` (0.0–1.0, default 0.5, lower =
    more results). It only *reports* ranked candidate pairs; it closes and
    merges nothing.
  - `bd duplicates` — exact content-hash matches, narrower; useful only for
    identical beads.
- **The intelligent call** — is this candidate actually a duplicate, does this
  bead actually belong under that epic — is a judgment, and the judgment that
  carries a consequence is re-made against live state at the point the
  consequence is applied, not trusted from the discovery snapshot. For a
  duplicate that means the LLM validation in the close disposition (see "Close
  as duplicate" below); for a soft link it means the reacting agent's own read,
  recorded as a `related` edge that commits to nothing irreversible.

The candidates and the agent's read land in the card's `## Found` section, each
freshness-stamped like every other fetched fact.

### Confirmed versus likely: one soft edge, hard actions only through their owner

The neighborhood links first reaction wants to draw come in two strengths, and
the distinction generalizes across every relationship kind:

- **Confirmed** — "this *is* a duplicate of X", "this *belongs under* that
  epic". The assertion carries a consequence: a duplicate closes a bead, a
  parent transmits blocked state and defines scope.
- **Likely** — "these two are probably related; someone looking at either
  should see the other, but I will not close or re-parent on a maybe".

`bd` has no built-in way to mark a link's strength. `bd dep add` accepts ten
edge types (`blocks | tracks | related | parent-child | discovered-from |
until | caused-by | validates | relates-to | supersedes`, plus `blocked-by` /
`depends-on` as aliases for `blocks`; `bd link` exposes the first five), but
none of them encodes confidence — the only lever is *which type*, and there is
no strength or tentative attribute on an edge. So the clean model is the one
the graph can actually represent:

- **A single `related` edge carries every likely link.** Whether the agent is
  fairly-confident-but-not-certain that two beads are duplicates, siblings
  under an epic, or merely adjacent, the record is the same low-commitment
  `related` edge. It transmits no blocked state, re-scopes nothing, is findable
  from both ends, and is cheap to drop if wrong. High-confidence-but-unproven
  is exactly what `related` is for, and using one type for all of it keeps the
  graph legible instead of inventing a soft-duplicate / soft-parent vocabulary
  the tooling does not understand.
- **A hard action is never taken speculatively, and only through the path that
  owns its consequence.** A confirmed duplicate closes through the duplicate
  path (below); a confirmed epic parent would be a `parent-child` write — which
  is deferred (below). First reaction's enrichment pass writes `related` and
  nothing heavier; the heavy moves are gated by validation elsewhere.

### Close as duplicate: validate at the disposition, act through bead-rehome

A confident duplicate is a *close*, and first reaction never closes a bead
itself — that is the standing contract. It takes the existing **close**
disposition, which routes to `mol-validate-close`. But `mol-validate-close`
today validates only a plain no-work / no-op close: its `validate-and-resolve`
step closes with `gc.work_outcome=no-op`, and it *explicitly escalates* any
close that needs a successor —

> "A bead whose close needs a successor (a duplicate, a supersede) is
> `bead-rehome.sh`'s and the operator's — escalate it."
> (`formulas/mol-validate-close.toml`)

So today a duplicate routed to the closer is escalated, not resolved. This
proposal extends `mol-validate-close` to make "close as duplicate" a state it
validates and acts on:

- The reaction routes the bead to the closer with the claimed canonical id in
  the brief (`gc.first_reaction_reason`), the same channel the no-op close
  already uses.
- `validate-and-resolve` gains a duplicate arm: re-derive the claim against
  live state — the canonical exists, is open or the surviving side, and the two
  genuinely overlap — and on confirmation close through
  `assets/scripts/bead-rehome.sh --origin <bead> --successor <canonical>
  --kind duplicate`, the repo's canonical successor-pointer close. It records
  the relationship in `gc.superseded_by` and closes with a "duplicate of …"
  reason; it is the same path `assets/scripts/duplicate-sweep.sh` already
  drives, so the duplicate machinery is reused rather than reinvented. A claim
  that does not hold escalates, exactly as a failed no-op validation does now.

This keeps the intelligent validation of a duplicate claim in one place — an
LLM re-checking a scripted candidate before anything closes — and keeps first
reaction's no-close contract intact. `bd duplicate <id> --of <canonical>` is
the lower-level primitive that also closes-with-reference, but the repo
standardizes successor closes on `bead-rehome.sh` (metadata-based, tested,
already consumed by the sweep), so the extension reuses that path.

A lower-confidence duplicate is not routed to the closer. It is surfaced in the
card as "possible duplicate of X — confirm" and carried by a `related` edge so
the pair is navigable, left for a human or a later validation to adjudicate.

### Epic association: a low-commitment related edge now, parent-child later

A candidate epic is the heaviest of the confirmed links, because a
`parent-child` edge transmits the parent's blocked state to the child and
defines the child's scope — a wrong parent both mis-scopes the bead and can
make it unclaimable. Two things follow, and they point the same way for now:

- A bead that belongs under an epic must be *findable from the epic*, and
  without a graph edge it is not. So when the agent is confident, it wires a
  low-commitment **`related` edge between the bead and the epic** — enough to
  make the pair navigable from either end, with none of `parent-child`'s blast
  radius.
- The strong `parent-child` write is **deferred**, not forbidden: epic
  management is still maturing, and a speculative re-parent is the expensive
  mistake. When epic handling settles, a confirmed parent-child becomes a
  natural hard action (validated the way a duplicate is), but that is a later
  build, not this one.

### One shared edge writer, not a first-reaction-specific script

Adding a graph edge is not unique to first reaction, and the repo has no
general edge-writing helper today: every script that needs an edge inlines
`gc bd dep add` for its own domain (`gc-helm.sh`, `finding.sh`,
`patrol-finding.sh`, `escalate.sh`, `signoff.sh`, and others), and
`first-reaction-dispose.sh` is structurally first-reaction-specific — it
hard-codes the four dispositions, the `gc.first_reaction*` stamping, and the
workflow-root gating. Writing a second first-reaction-specific edge script
would grow exactly the proliferation the design should avoid.

The proposal is instead a single small, general helper —
`assets/scripts/bead-link.sh` (name open) — that writes one typed edge
between two beads with the store-pinning and same-store guard the enrichment
needs. Those two guards are the genuinely reusable part of
`first-reaction-dispose.sh` and would be extracted into the shared helper:

- **Store pinning by rig prefix.** The reacting worker runs from a pool
  worktree whose `.beads` is gitignored, so an unpinned `bd` up-walk overshoots
  to the wrong ledger; the helper resolves the subject's rig by id prefix
  (`gc rig list --json`) and pins `--db <path>/.beads`.
- **Same-store guard.** `bd dep add` naming a bead in another rig's store
  answers "✓ Added dependency" and holds nothing (component-model I1), so the
  helper refuses a cross-store edge rather than reporting a phantom success.

First reaction's enrichment step calls this helper; so can any future caller
that needs a guarded edge write. Because the write goes through a formula step
that names the helper, the mechanical-trigger constraint from tk-87nwhv is
satisfied.

### Stale worldview and fan-out

Two existing guardrails carry over unchanged and the build must respect them.

- **Freshness.** A slung reaction acts on a snapshot that may have moved by
  the time a human reads the card (design-doc Risk, "stale proactive
  worldview"). The card already freshness-stamps every fetched fact in
  `## Found`; enrichment candidates are stamped the same way, and this is
  another reason a duplicate is re-validated at the disposition rather than
  acted on from the discovery snapshot.

- **No fan-out.** The formula's actionable exit already forbids a reaction
  from filing a spray of new beads, and where several beads share one cause it
  requires one bead naming the cause. Enrichment writes edges on the *existing*
  neighborhood, so it does not add beads — with one exception, the blocked
  exit's `--blocker` filing, which is already deduped by `--blocker-key`.
  Duplicate handling files no new bead either; it reuses the close exit.

## Facet B — coverage (remove the sling cap)

### Three bounds sit in the scan-to-sling path, and only one should stay tight

`tools/gc-proactive.sh scan --sling` is the sweep that finds idle beads and
slings a first reaction at each. Three separate bounds throttle it today, and
they do not all earn their place:

1. **`GC_PROACTIVE_SLING_CAP` (default 5) — remove it.** Within a sweep's
   candidates, the `--sling` loop stops spending after this many genuine
   dispatches. Its stated rationale is that "an uncapped sweep is a queue of
   implementation sessions filed by one command." But slinging a reaction only
   *enqueues* it; enqueue is free, drops nothing, and starves nothing. The cap
   throttles the wrong thing — the depth of a free queue — and the real limit
   on work lives downstream, in the pools.
2. **Pool `max_active_sessions` — keep it; this is the real processing cap.**
   The proactive pool is capped at 2 (`agents/proactive/agent.toml`), which
   bounds how many reactions run at once; the polecat pool is capped at 5
   (`agents/polecat/agent.toml`), which bounds how many downstream
   implementations run at once. This is where "do not work on more than X at
   once" is enforced, and it is enforced whether or not the sling cap exists.
3. **`GC_PROACTIVE_SCAN_LIMIT` (default 20) — keep it, as an overload guard.**
   `scan` filters and board-ranks the whole ready set, then slices to this many
   candidates per sweep (`0` = unbounded). Its job is not to manage a backlog;
   it is to keep any single sweep to a batch size known to run cleanly, so a
   latent bug that only bites above some size cannot turn an unbounded batch
   into a random future failure. A steady batch per cadence, sized to what a
   sweep can reliably do, is safer than one unbounded pass.

With the sling cap gone, `SCAN_LIMIT` becomes the single per-sweep bound:
one sweep considers, and now slings, at most the top `SCAN_LIMIT` idle beads by
board weight. One bound on candidates per sweep is simpler than two nested
bounds with overlapping rationales.

### Backlog is fine to process

The concern the sling cap guarded against — the first sweep after deploy
hitting the whole idle backlog — is not a problem to ration. Each bead is
reacted once (`scan_precision_filter` drops anything already carrying
`gc.proactive_reaction` or `gc.first_reaction`), so the backlog is a one-time
cost that drains through normal cadence: at most `SCAN_LIMIT` beads per sweep,
highest board-priority first, until only newly idle beads remain. The pools'
`max_active_sessions` throttles the actual work throughout. No special
first-deploy ramp is needed; the backlog is processed, not staged.

### "Idle / not going somewhere on its own" is already defined precisely

The population a reaction should reach already has a concrete definition, in
`scan_precision_filter` plus the `gc bd ready` query that feeds it
(`tools/gc-proactive.sh`). A candidate is:

- open and ready (dependencies closed) and unassigned — from `bd ready`;
- an allowlisted issue type (`GC_PROACTIVE_TYPES`, default
  `task,bug,feature,spike`);
- top-level (no parent-child parent edge);
- not a topology root (`gc.kind` not in `workflow/scope/spec`);
- not machinery or work-in-flight (not `task_kind` `feedback-pattern` or
  `review`; no `branch/merge_result/work_dir/pr_url/pr_number/check_name/
  anchor_bead` marker);
- not already ruled (`gc.takeaway`/`gc.takeaway_by` empty);
- not already reacted (`gc.proactive_reaction` and `gc.first_reaction` empty);
- not already routed (`gc.routed_to` empty);
- has a non-empty description.

This is exactly "unrouted + unassigned + not being worked + not already
reacted", made concrete. The design does not redefine idle; it points the
coverage change at this existing filter and leaves it as the contract.

### What removing the cap does and does not change

Removing `GC_PROACTIVE_SLING_CAP` changes how many reactions one sweep may
dispatch (from 5 up to `SCAN_LIMIT`). It does not change what a reaction does,
which pools throttle the work, or the definition of an idle bead. The true
throttle on operator attention remains downstream: the polecat pool's rate and
the human merge gate, neither of which the sling cap governs.

## Risks

- **Review-queue pressure.** More reactions mean more actionable dispositions,
  more implementations, and more PRs at the human merge gate. This is the
  operator's stated intent ("any bead that will sit around should get a first
  reaction"), and the merge gate already serializes the human's attention; the
  polecat pool rate and the merge gate are the intended throttle, and
  `SCAN_LIMIT` sizes the per-sweep batch to what runs cleanly.
- **Wrong enrichment edge.** A mis-wired `related` edge is cheap to drop; a
  wrong close or a wrong parent is not. The strength model contains this: only
  `related` is written speculatively, the duplicate close is re-validated
  before it fires, and parent-child is deferred entirely.
- **Discovery cost on a large store.** `bd search` is title-scoped and
  `--limit`-bounded, and `find-duplicates --method mechanical` is local; the
  build should cap candidate counts so a reaction on a 20k-bead store stays
  cheap.

## Open questions for the operator dialogue

1. **Extend `mol-validate-close`, or a sibling formula?** The proposal extends
   the existing closer with a duplicate arm, so one formula owns "validate a
   claimed close and act". A sibling `mol-validate-duplicate` would isolate the
   duplicate path at the cost of a second closer to keep in step. The proposal
   recommends extending.
2. **Shared edge-writer home and name.** `assets/scripts/bead-link.sh` is
   proposed as a new general helper; the alternative is to grow an existing
   script. The proposal recommends the new helper because no current script is
   a general edge writer.
3. **`SCAN_LIMIT`'s role.** It reads two ways: a backlog device, removable now
   the backlog is handled, or an overload guard that holds each sweep to a size
   known to run cleanly. The proposal keeps it as the overload guard — please
   confirm that is the intended reading.

## Build plan — incremental commits on one PR

The build lands as a sequence of incremental commits on a single branch and
PR, reviewed holistically rather than split across four PRs. The commits are
ordered so each is reviewable on its own, but they ship and merge together:

1. **Shared edge writer.** `assets/scripts/bead-link.sh` (store-pinned,
   same-store-guarded), extracting those guards from `first-reaction-dispose.sh`.
2. **Discovery + related enrichment.** The scripted discovery step
   (`bd search` / `find-duplicates --method mechanical`) and auto-wiring of
   confident `related` edges through the shared helper; lower-confidence links
   surfaced in the card.
3. **Epic association.** A confident bead-to-epic `related` edge through the
   same helper; `parent-child` deferred.
4. **Close as duplicate.** Extend `mol-validate-close`'s `validate-and-resolve`
   with a duplicate arm that re-validates the claim and closes through
   `bead-rehome.sh --kind duplicate`; route confident duplicates to it from the
   close disposition.
5. **Remove the sling cap.** Drop `GC_PROACTIVE_SLING_CAP` from
   `tools/gc-proactive.sh`, keep `SCAN_LIMIT` as the per-sweep overload guard,
   and update the `agents/proactive/agent.toml` and design-doc notes that
   reference the cap.

Commit 5 (cap removal) is genuinely independent of 1–4 and could stand alone;
per the operator's steer it rides the same PR unless the operator prefers to
pull it out. Commit 1 is the prerequisite for 2 and 3; commit 4 depends only on
the discovery step from 2.
