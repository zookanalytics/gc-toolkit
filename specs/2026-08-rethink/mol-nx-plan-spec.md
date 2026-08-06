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
| 1 | `draft` | `wright` | Prime; **guard first**: if an open ratification turn already exists on this brief (the concurrency probe — one brief, one planning conversation), record that and close this step as a **no-op** (`gc.outcome=fail`, `gc.failure_class=hard`, reason noted). Otherwise read the brief, its universe slice (fenced untrusted data, as first-reaction does), **and the live tree state** — the manifest plus each listed bead's current status. Draft the desired tree, bump `rev`, and write it to the **brief bead's notes** as the plan block (schema below), with a **diff summary** against live: adds, retires (hand-raised retires listed separately), updates, re-wires, in-flight work the plan must respect. First run is the degenerate case (live tree empty; diff = everything is an add). Close own step bead. |
| 2 | `gate` | `wright` | **Open by reading step 1's `gc.outcome`; on `fail`, no-op** — close own step (`gc.outcome=pass`, "predecessor aborted; no turn filed") so the graph completes empty (a failed predecessor still closed its bead, and closing releases dependents — the fail-open trap this rule closes). Otherwise: resolve step 3's bead (own bead's `gc.root_bead_id` → query `gc.step_ref=mol-nx-plan.reconcile` within that root; **exactly one match or fail-hold** — never wire across runs); file the ratification turn on the brief (`mol-nx-turn` shape inline: `gc.routed_to` → converse pool rig-qualified, `gc.continuation_group=<brief>`, `task_kind=conversation`, title `turn: <brief> — ratify the plan (rev <rev>)`), its body leading with the **diff summary** and naming the plan `rev`; wire the gate — the blocking dependency from turn to step-3 bead — and **verify the edge by re-read before closing this step** (step 3 stays suppressed by this step's own open bead throughout the wiring window, so the happy path is race-free; if the edge cannot be verified, hold this step open and say so — closing it unverified is the tree that files itself); record the turn's bead id and rev in the manifest; close own step bead. |
| 3 | `reconcile` | `wright` | Becomes Ready only when the turn closes (any close — see the fail-closed rule). Re-read the turn (by the manifest-recorded id) and the **latest** plan block. **Reconcile only when all three hold:** the turn is closed with `gc.outcome=ratified`; the turn's stamped ratified-rev (and content hash) matches the latest plan block (the check's head-pin — a plan block appended after ratification re-opens the question, it does not ride through); and validation passes. **Every other state — rejected, cut short, missing turn, unstamped outcome, rev mismatch — changes nothing:** note the reason on the brief, close own step `gc.outcome=pass` (the step did its job: it declined honestly). On reconcile: apply in the fixed order (rules below), update the manifest, close own step. |

Plus the standard v2 `drain` terminal. The `workflow-finalize` /
control-dispatcher dependency is named in the header, as `mol-nx-work`
does.

**Converse's side of the gate** (turn-body instructions, within its
shipped contract): on **ratify**, stamp `gc.outcome=ratified` plus the
ratified `rev` and plan-block hash on the turn, then close it. On
**reject-and-redraft**, close the turn as `rejected` **first**, then file
the fresh `mol-nx-plan` run (order matters: the fresh run's step-1 guard
probes for an open ratification turn, so close-then-file never trips it —
fixing the race the first draft of this spec designed in). A
**recycle-cut-short** close (the converse recycle guard) is an ordinary
non-ratified close: step 3 declines, the run ends empty, and resuming is
filing a fresh run — the gate is one-shot; no successor turn can re-block
a released step.

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
rev: 3                        # bumped every draft; the ratification head-pin
epics:
  - title: "…"                # one epic bead (type=epic) per entry
    convoy: true              # owned convoy + integration branch (default)
    stories:
      - id: s1                # local handle, GLOBALLY unique, stable across revs
        title: "…"
        kind: task            # task | doc | research (sets landing defaults, below)
        needs: []             # local handles → blocks edges (global namespace)
      - id: s2
        title: "…"
        needs: [s1]
notes: "…"                    # anything the operator said that shapes filing
```

`kind` landing defaults, per the state machine's committed-vs-ephemeral
split: `task` → code path, `check_set="signoff"`; `doc` → **keepable
artifact** — lands through a PR with the same check-set (a committed
output always pays the gate; the non-impl done-sequence applies only to
outputs that produce no commit); `research` → ephemeral — lands in the
bead's own notes and closes when recorded.

**Handles are machine-internal, always** (operator ruling, decisions.md
#14): they exist only in the plan block and the manifest. Every
operator-facing surface — the ratification turn's diff, flags, notes the
operator is expected to read — speaks in **story titles and purposes**
("drop the *RSS export* story; do *schema migration* before *API
endpoint*"), and the diff is framed at the level of what needs a
decision, not a re-statement of the tree. The operator redirects in
natural phrasing; **converse translates to handles** when it writes the
revised plan block. A turn body that asks the operator to track labeled
list items is a defect.

Local `id` handles are **stable across revisions** — that is what lets a
rev-3 plan block say "s2 now also needs s7" and the reconciler know which
live bead `s2` is (the manifest maps handle → bead id at creation).
Reusing a retired handle for a *different* story is the one hand-edit the
machine cannot fully catch; the mechanical tell is surfaced: a live
bead's title diverging from its manifest title is a **warning line in
the ratification diff**, so the operator sees the collision before
ratifying it.

Step 3 validates before touching anything: unknown `needs` handles,
**duplicate handles** (the namespace is global — `needs` crosses epics),
cycles, or a story count over `max_stories` are errors — recorded on the
brief, step closed without reconciling, nothing partially applied before
validation passes. Reconciliation itself is sequential and resumable:
each applied change is appended to the manifest immediately —
**re-read-before-append and verified by re-read**, since converse writes
the same notes surface (the sibling-write staleness idiom) — so a
crashed run resumes by diffing manifest against plan, not by
re-creating.

## Reconciliation rules (the iteration contract)

Desired (the plan block) is compared against live (the manifest + each
bead's current status); the diff is applied under rules that never
falsify the record:

- **Add** — a handle in desired with no manifest entry: create the story
  with its edges and routing, append to manifest.
- **Update** — a manifest handle whose desired entry changed: retitle an
  open, unclaimed bead in place; a `kind` change (it silently changes
  landing defaults) is **flagged in the ratification diff** and applied
  only to an open, unclaimed bead.
- **Retire** — a manifest entry absent from desired, whose bead is
  **unassigned and not in_progress, not gating, not closed**: close it
  with a re-planned-away reason (the state machine's decision-close:
  "the work is no longer wanted, so there is nothing unlanded to lie
  about"). Every retire is listed in the ratification diff — removals
  are always explicitly ratified — and a **hand-raised** bead
  (`blocked`/`deferred`: it raised its hand for a reason) gets its own
  diff line, since the raised hand may carry context the removal
  decision needs.
- **Never auto-touch work in motion** — a bead that is `in_progress`,
  gating, or closed is out of reconciliation's reach: a closed story
  stays closed (its work landed; history does not un-happen), and an
  in-flight story the plan wants gone is **flagged in the turn** for the
  operator's explicit call (abandon it via the normal abandonment path,
  or let it land) — the formula records the decision, a human makes it.
- **Re-wire** — `needs` changes on a live open story add/remove `blocks`
  edges; edge removal can make a story Ready (that is the point);
  edge addition to an in-progress story is flagged, not forced.
- **Apply order is fixed, because stories are live-routed while the
  reconcile runs:** (1) create adds and wire **all** new edges, verified;
  (2) remove edges; (3) retire-close — a shared blocker is closed only
  after every dependent's new edge set is verified in place. Retiring
  first would open a no-blocker window in which a wright claims a story
  whose new dependencies were still unwired, and a late edge-add against
  in-progress work is flagged-not-forced — the sequencing would be
  permanently lost.
- **Retiring a story that others `needs`** is caught by validation
  before anything applies: desired edges may only reference desired
  handles, so a retire that would strand a dependent is a plan error the
  operator sees, not a runtime surprise.
- **Epic/convoy entries reconcile the same way**, with one extra guard:
  a convoy with any closed-as-**landed** child (`merged_sha` / landed
  close reason — a retired child's decision-close does not count) is
  never retired; its PR history is real, and the operator disposes of it
  through abandonment if needed.

## What gets filed

Per the convoy-integration doctrine (spec §7 matrix) and the state
machine's boundary invariant:

**The edge set, stated in full** (the completion gate and graduation key
on the *convoy's* children, so membership edges are load-bearing — a
story wired only to the epic would leave the convoy childless, and "all
children closed" would be vacuously true the moment it was minted: an
empty convoy graduating an empty integration branch to main on the
lander's next cycle):

```
epic ──parent-child──▶ convoy ──parent-child──▶ story (×N)
                                     story ──blocks──▶ story   (from needs)
```

- **Epic bead** (`type=epic`) — structure, never execution: excluded from
  every claim query by core; conversed about through turn-children; holds
  its convoys as `parent-child` children.
- **Owned convoy** per epic (unless `convoy: false`): the PR owner, with
  its integration branch as the stories' `metadata.target`; **the
  stories are ITS `parent-child` children** — that membership is what
  the completion gate counts and the convoy-ancestor target walk uses.
  With `convoy: false`, stories are the epic's children directly and
  land per their own `target`.
- **Story beads**, `parent-child` to the **convoy**, `blocks` edges from
  `needs`, `metadata.target` = the convoy branch, landing defaults by
  `kind` (schema section), **routed at file time** to
  `${GC_RIG:+$GC_RIG/}{{binding_prefix}}wright` (stamp-don't-sling, one
  key per flag). Ready-visibility sequences them; the wright cap bounds
  concurrency.
- **Route mode** (`route_mode` var): `all` (default — the graph gates
  release) or `hold` (file unrouted — the deliberately detached shape
  nothing watches, so it must not be silent: **thread-ops owns release
  on the record**, the manifest marks held stories, and the chain-
  liveness doctor gains a warn for manifest stories never routed after
  N days — the conservative mode for a first live run, not a parking
  lot).

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
  one brief would race the manifest. The guard is mechanical and
  **pre-gate-scoped**: step 1 probes for an **open ratification turn on
  this brief** (a workflow past its gate is already reconciling from a
  ratified rev and holds no turn; probing workflow state itself would
  race the dispatcher-gated finalize and trip the designed
  reject→fresh-run path). One brief, one open planning conversation at
  a time — and converse's close-turn-then-file-fresh ordering (step
  table) keeps the designed re-plan path from ever tripping it.
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
- **Stage-1 additions (four, not one):** (a) the exact dep CLI shape for
  a blocks edge — the corpus attests `gc bd dep <gate> --blocks <bead>`
  and `gc bd dep add <a> <b> --type=parent-child`, and this spec's
  gate needs the blocks form verified verbatim; (b) the sibling-step
  addressing keys a step body can actually read
  (`gc.root_bead_id` + `gc.step_ref` scoping, exactly-one-match); (c)
  **runtime removal of a blocks edge** — re-wire depends on it and no
  shipped formula removes a dependency edge anywhere; (d) engine
  behavior on a step closed with `gc.outcome=fail` (the fail-open trap
  the step table's no-op rules assume: closing releases dependents and
  nothing halts the graph). All four join the stage-1 list in
  implementation-notes.md.

## Documentary proxy (for this spec's own review)

The formula header carries: the brand, the trace, the v2 rationale, the
interlock line ("the ratification check is filed by the step it gates —
implemented"), the dispatcher dependency, and the stage-1 note. The
implementation is reviewed against the step table, the plan-block
schema, and the guards above.
