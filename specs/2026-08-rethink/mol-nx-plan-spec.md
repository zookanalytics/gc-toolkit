# Spec — `mol-nx-plan`, the decomposition formula

**Brand (O8):** turns a brief into a ratified tree of work, and keeps it
one — each run drafts the *desired* epic/story structure, holds it for the
operator's yes, and reconciles the live tree to it; the first run and the
tenth are the same mechanism.

**Not a do-once action (operator, 2026-08-05):** an epic is re-addressed
many times as the initiative iterates. That ruling shapes the core design
choice below — the plan block is always the **full desired tree**, and
filing is a **diff against what is live**, so re-planning is re-running,
not a special mode.

**Consistency trace (architecture's test):** *Equip the human to make the
best decision* (G2) and *Decisions have a home*, made concrete through
bead + molecule + check + routing, composed the way Delivery and
Attention & conversation already compose — the ratification gate is a
check only a human can clear, delivered as a conversation turn.

Fills the gap named in [ecosystem-fit.md](ecosystem-fit.md) (intake bead
#1): every downstream piece of a brief → epics → stories flow ships; the
step that *files the tree* does not. This spec is design-only; the formula
is implemented against it as an ordinary bead once ratified.

## The loop, in one paragraph

An operator (usually via `thread-ops`, or a one-line sling) points
`mol-nx-plan` at a **brief bead** — any bead whose description says what
is wanted; on iteration, the same brief again. A wright drafts the
**desired tree** — epics, convoys, stories, dependencies — informed by
what is already live (closed stories stay closed; in-flight work is
respected), and writes it to the brief's notes as a structured plan. A
**ratification turn** is filed on the brief (the tk-h9pq5 mechanism: the
operator arrives at a framed diff — *adds, retires, re-wires* — not a
cold prompt) and **blocks** the final step, so nothing changes until a
human says yes. On ratify (possibly after redirects, all recorded on the
brief), the final step re-reads the plan *from the brief's record* —
never from session memory — and **reconciles**: creates missing stories
with their `parent-child` and `blocks` edges, retires ratified removals,
re-wires changed dependencies, and touches nothing in flight.
Ready-visibility does the sequencing: a story with open blockers creates
no demand until its blockers close, so the whole tree can be routed at
file time without flooding anything — the pool caps bound concurrency and
the dependency graph releases the frontier, on the first run and on every
re-plan.

## Contract: graph.v2, and why

Three materialized steps with one runtime-created gate between the last
two. v2 is earned (packs.md §1): the draft and file steps are
independently routable pool work separated by an arbitrarily long human
wait — precisely what must NOT hold a session open (the wait can be
days), so they cannot be one v1 in-session molecule. The session that
drafted dies at the turn boundary; the session that files is a fresh
claimant reconstituting from the record. `[requires] formula_compiler =
">=2.0.0"`; no vapor; every step body closes `$GC_BEAD_ID` before any
drain-ack.

**The ratification gate is the O4 interlock, implemented.** The check
"a human ratified this plan" is composed exactly as architecture defines
a check: a **blocking dependency that holds work un-Ready until the
asserted thing is satisfied**. Step 2 files the turn and wires
`gc bd dep add <turn> --blocks <step3-bead>` at runtime; `bd ready`
excludes beads with active blockers, so step 3 generates no demand until
the turn closes. The step that needs the check files the check — no
polling, no coordinator, no new machinery.

## Steps

| # | Step | Runs on | Does |
|---|---|---|---|
| 1 | `draft` | `wright` | Prime; read the brief, its universe slice (fenced untrusted data, as first-reaction does), **and the live tree state** — the manifest plus each listed bead's current status. Draft the desired tree and write it to the **brief bead's notes** as the plan block (schema below), with a **diff summary** against live: stories to add, stories to retire, edges to re-wire, in-flight work the plan must respect. First run is the degenerate case (live tree empty; diff = everything is an add). Close own step bead. |
| 2 | `gate` | `wright` | File the ratification turn on the brief (`mol-nx-turn` shape inline: `gc.routed_to` → converse pool rig-qualified, `gc.continuation_group=<brief>`, `task_kind=conversation`, title `turn: <brief> — ratify the plan (rev N)`), its body leading with the **diff summary** so the operator ratifies changes, not a wall of re-stated tree; then `dep add <turn> --blocks <step3-bead>`; verify the edge by re-read (an unverified block is a tree that files itself); close own step bead. |
| 3 | `reconcile` | `wright` | Becomes Ready only when the turn closes. Re-read the **latest** plan block from the brief's notes and the turn's `gc.outcome`. On *ratified*: reconcile live to desired (rules below), update the manifest, close own step. On *rejected*: change nothing, note it, close own step — the workflow completes empty, honestly. |

Plus the standard v2 `drain` terminal. The `workflow-finalize` /
control-dispatcher dependency is named in the header, as `mol-nx-work`
does.

**Redirects cost nothing extra.** A redirect is the converse role doing
its normal job: the operator's revisions are written to the brief's
notes as an updated plan block, and the turn closes only when the
operator ratifies or rejects — possibly after several warm/cold visits.
Step 3 never sees intermediate states; it reads the record once, after
the gate opens. If the operator wants a *substantially* different plan
drafted, converse files a fresh `mol-nx-plan` run and closes the turn as
rejected — re-drafting is a new run, not a loop inside this one.

## The plan block (the record's schema)

A fenced block in the brief's notes, latest-wins, both human-editable in
a turn and machine-readable by step 3:

```yaml
# nx-plan v1
epics:
  - title: "…"                # one epic bead (type=epic) per entry
    convoy: true              # owned convoy + integration branch (default)
    stories:
      - id: s1                # local handle for edges, not a bead id
        title: "…"
        kind: task            # task | doc | research (sets check_set/target defaults)
        needs: []             # local handles → blocks edges
      - id: s2
        title: "…"
        needs: [s1]
notes: "…"                    # anything the operator said that shapes filing
```

Local `id` handles are **stable across revisions** — that is what lets a
rev-3 plan block say "s2 now also needs s7" and the reconciler know which
live bead `s2` is (the manifest maps handle → bead id at creation).

Step 3 validates before touching anything: unknown `needs` handles,
cycles, or a story count over `max_stories` are errors — recorded on the
brief, step closed `gc.outcome=fail` with `gc.failure_class=hard`,
nothing partially applied before validation passes. Reconciliation itself
is sequential and resumable: each applied change is appended to the
manifest immediately, so a crashed run resumes by diffing manifest
against plan, not by re-creating.

## Reconciliation rules (the iteration contract)

Desired (the plan block) is compared against live (the manifest + each
bead's current status); the diff is applied under rules that never
falsify the record:

- **Add** — a handle in desired with no manifest entry: create the story
  with its edges and routing, append to manifest.
- **Retire** — a manifest entry absent from desired, whose bead is still
  **open and unclaimed**: close it with a re-planned-away reason (the
  state machine's decision-close: "the work is no longer wanted, so
  there is nothing unlanded to lie about"). Every retire is listed in
  the ratification diff — removals are always explicitly ratified.
- **Never auto-touch work in motion** — a bead that is `in_progress`,
  gating, or closed is out of reconciliation's reach: a closed story
  stays closed (its work landed; history does not un-happen), and an
  in-flight story the plan wants gone is **flagged in the turn** for the
  operator's explicit call (abandon it via the normal abandonment path,
  or let it land) — the formula records the decision, a human makes it.
- **Re-wire** — `needs` changes on a live open story add/remove `blocks`
  edges; edge removal can make a story Ready (that is the point);
  edge addition to an in-progress story is flagged, not forced.
- **Epic/convoy entries reconcile the same way**, with one extra guard:
  a convoy with any closed-as-landed child is never retired — its PR
  history is real; the operator disposes of it through abandonment if
  needed.

## What gets filed

Per the convoy-integration doctrine (spec §7 matrix) and the state
machine's boundary invariant:

- **Epic bead** (`type=epic`) — structure, never execution: excluded from
  every claim query by core; conversed about through turn-children.
- **Owned convoy** per epic (unless `convoy: false`): the PR owner, with
  its integration branch as the stories' `metadata.target`.
- **Story beads**, `parent-child` to the epic, `blocks` edges from
  `needs`, `metadata.target` = the convoy branch, `check_set` defaulted
  by `kind` (task → `"signoff"`; doc/research → non-impl done-sequence
  applies), **routed at file time** to
  `${GC_RIG:+$GC_RIG/}{{binding_prefix}}wright` (stamp-don't-sling, one
  key per flag). Ready-visibility sequences them; the wright cap bounds
  concurrency.
- **Route mode** (`route_mode` var): `all` (default — the graph gates
  release) or `hold` (file unrouted; the operator or thread-ops releases
  waves by stamping routes — the conservative mode for a first live run).

The brief bead itself stays open, the tree's conversation anchor; it
closes through its own lifecycle when the initiative lands (the epic's
completion is the natural close signal, an operator disposition — this
formula never closes it).

## Invocation (the seeding story, closed)

- **From thread-ops** (the operator's stated primary door): "here's what
  I want" → thread-ops creates the brief bead from the conversation and
  slings `mol-nx-plan` at it. One utterance to a ratification turn.
- **One-liner**: `gc sling <rig>/gc-next.wright <brief> --on mol-nx-plan`.
- **From a turn**: converse can file it against the subject under
  discussion.
- The future `nx-seed "<sentence>"` helper (decisions.md addendum) is
  now a thin compose: create brief + attach this formula.

## Vars

| Var | Default | Meaning |
|---|---|---|
| `brief` | required | The brief bead (sling source). |
| `binding_prefix` | `gc-next.` | Pool qualification, as everywhere. |
| `max_stories` | `30` | Validation cap on the desired tree per run; bigger initiatives plan in layers (an epic's story can itself be a brief). |
| `route_mode` | `all` | `all` = route at file time (graph-gated release); `hold` = file unrouted. |

## Guards and edges

- **Idempotence and concurrency:** re-running against a filed brief is
  the designed iteration path (above), but two *concurrent* plan runs on
  one brief would race the manifest — step 1 aborts (fail/hard, noted)
  if another `mol-nx-plan` workflow is open against the same brief. One
  brief, one planning conversation at a time.
- **Who triggers a re-plan:** any of the three doors — the operator
  ("re-plan this epic" to thread-ops), a conversation turn concluding
  the plan has drifted, or (later, recorded not designed) an event-driven
  formula noticing the tree has gone stale. Each is just another sling
  of this formula at the brief.
- **Reaper safety:** the ratification turn carries
  `task_kind=conversation` — already shielded by the health patrol's
  skip clause.
- **Chain-of-record:** every decision (draft, each redirect, the
  ratification, the manifest) lives on the brief bead's notes — a cold
  reader reconstructs the whole planning history from the record, per
  the conversation model's core bet.
- **No self-closing brief, no auto-landed plan doc:** the plan text
  lives in the brief's notes; committing a polished `specs/<brief>/plan.md`
  is, when wanted, simply a `doc` story *in the tree* — it rides
  Delivery like everything else instead of adding a pre-ratification
  landing cycle.
- **Stage-1 additions:** the runtime `--blocks` gate (a bead created by
  a step body blocking a sibling step bead) is the one mechanism here
  not yet exercised by a shipped formula — added to the stage-1
  verification list alongside the existing five.

## Documentary proxy (for this spec's own review)

The formula header carries: the brand, the trace, the v2 rationale, the
interlock line ("the ratification check is filed by the step it gates —
implemented"), the dispatcher dependency, and the stage-1 note. The
implementation is reviewed against the step table, the plan-block
schema, and the guards above.
