# PRD: The Bead-Universe Operating Model (gc-toolkit)

> **Provenance.** This PRD is a *distillation* of decision bead **tk-yrio** (revision 3,
> operator-converged over 6 revisions in mechanik-thread, 2026-06-06). tk-yrio is the
> authoritative brief and the PRD substance — this document re-structures its converged
> framing into PRD form for the review/design legs; it does **not** re-derive the framing
> or introduce new scope. Where this PRD and tk-yrio disagree, **tk-yrio wins.** Read
> tk-yrio in full: `gc bd show tk-yrio --db /home/zook/loomington/rigs/gc-toolkit/.beads`.
>
> This is a draft. Breadth over polish; uncertainty is exposed, not hidden.

---

## Problem Statement

**Optimize human time. Bring human cognition to problems of execution without wasting
attention.** This is foundation.md's first belief used as the *design driver* — not a
downstream benefit. (Improvement/audit and declarative control are things this model can
later *yield*; they are explicitly not what it solves for.)

**Diagnosis: a conversation is linear; cognition is branching.** The work is a large,
*parallel* tree of branches, many live at once. Human attention is *serial and scoped* —
it sits on one branch (or a portion of the tree) at a time. ("One at a time" is the
human's focus, not the work.) Forcing branching cognition through a linear conversation
produces two symptoms:

- **topic-mixing** — multiple branches crammed into one conversational line; and
- **lost ideas** — branches with nowhere to go.

These are *symptoms*. The fix is **not** "decompose harder" (see Non-Goals). The fix is to
make the *unit of engagement* a node in the tree, give that node a resident intelligence,
and route the human's serial spotlight to the node that needs it.

## Goals

The model rests on **two pillars working together**: get both right and the human's serial,
scoped spotlight always lands on the *right* branch, and once there, *everything is already
known or reachable.*

**G1 — Pillar 1: the bead-universe (depth).** Nearly every bead has an LLM attached, and
the human engages *at the level of a bead*. You don't hold a conversation and then bring up
a bead inside it — you hold a conversation *within the universe of a bead*. The bead is
still a work-tracking row; it *gains* an LLM and a universe.

**G2 — Context-completeness via reachability (THE core).** Given a bead, its resident LLM
knows — or can find out — everything about its mini-universe: the PR it created, that PR's
CI status, its child beads, its deps, its history. Completeness comes from *reachability*,
not pre-loading: feed the scoped core, make the rest fetchable on demand.

**G3 — A mayor for every node.** Each bead-LLM commands its universe and everything below
it: an Epic's LLM is a mayor over the whole epic subtree; a story's LLM over its substory;
deeper nodes are more specific. Coordination is no longer funneled through one city-wide
identity. (The single city-wide mayor may still have a home — as the root-node mayor, or
for cross-tree concerns.)

**G4 — Proactivity (the sharpest expression of foundation's cost asymmetry).** Because the
bead-LLM knows its universe, it can *move the bead forward before the human ever engages*:
explore open questions, run down what's reachable, do speculative work (accepted or not),
and carry the richer conversation already in progress. The human then arrives at a bead that
is *already advanced* — the cheap thinking done, the real decision teed up. Cheap agent
iteration spent ahead of time buys back scarce human attention. **In its own universe, the
LLM acts; it does not merely respond.**

**G5 — Pillar 2: the attention surface (breadth).** Bring the human *to* the bead-LLM —
don't route a problem-summary to a central mayor. Evolve the existing **`gc-attention.sh`**
prototype (decision `lo-0hvt`, PR gc-toolkit#83): a read-only, cross-rig "render-what-floats"
board that ranks the anchors most needing a human now (stranded frontiers, open decisions,
stale epics). It surfaces **what needs attention** — unlike `prefix+S`, which surfaces
**what's open now** (live sessions) and is blind to the tree. Its own deferred follow-ups
name the next step: **pick-a-row → spawn/attach a thread.** That launcher *is* the inversion:
glance the board, pick the bead that needs you, land inside its universe with its resident
LLM already informed. Coupled with proactivity, the board surfaces beads whose LLM has
*already advanced them* — the human ratifies or redirects, never cold-starts.

**G6 — Measured by human-time at the system level.** Judge the whole process by human-time,
not every mechanism individually. A given mechanism need not prove itself against the budget;
the *system as a whole* is measured by it. Proxy (foundation G1): **fewer escalations over
time, each higher-value** / nothing falls through.

## Non-Goals

**Scope discipline — these are named so the design does not drift.**

- **Not** "the bead stops being a work-tracking row." It still is one; it *gains* an LLM and
  a universe. (Not "an attention unit instead.")
- **Not** aggressive auto-decomposition. Spinning off-topic into its own bead is *handling
  off-topic* — useful, secondary, and **allowed to be mediocre**; it can be learned over time
  without endangering the model. *(Demoted; evolvable.)*
- **Not** UX-*first*. UX does not *define* the model, and `prefix+S` is the wrong starting
  interface. **But UX quality is load-bearing for adoption** — a sound model with poor UX
  will not land. Treat UX as a first-class *execution risk*, sequenced after the model is
  right; not a deferred nice-to-have.

**Explicitly out of scope for v1** (named so the process does not drift):

- **Declarative control engine** (parent-validates-children reconciliation).
- **Content-triggered mols** (the rules/intent engine).
- **Automated** hierarchical context distillation. *The parent/child universe relationship
  is in scope (see Open Question 2); the summarization machinery is v2.*
- **The audit / improvement loop** (depends only on Binding; can follow immediately, but is
  not v1).

**Not in this run:** rewriting `foundation.md` to "built on Gas City" is operator-DECIDED but
tracked separately as **tk-egzn** — do not perform that rewrite here.

## User Stories / Scenarios

1. **Pick-a-row landing.** The human glances the attention board, sees a ranked row —
   *"decision X needs you; its LLM explored 3 options and recommends B"* — picks it, and lands
   *inside that bead's universe* with its resident LLM already informed. They spend attention
   ratifying or redirecting, not cold-starting.

2. **Proactive advance.** While the human is elsewhere, a bead's resident LLM (within token
   budget) explores its open questions, fetches reachable facts (PR diff, CI status, child
   status, dep state, history), and does speculative work — then surfaces *"here's what I'd
   do and why; accept / redirect?"* on the board.

3. **Node-mayor over a subtree.** An Epic-level conversation asks "what's the state of this
   epic and what's blocked?" Its resident LLM, as mayor over the epic subtree, answers from
   reachable child/dep state — and can help with anything *below* it.

4. **Escalation inversion.** A bead-LLM hits something only the human can decide. Instead of
   mailing a problem-summary + pointer to the central mayor, it **flags the bead as needing
   attention**; the board ranks it up; the human drops into *that bead's* universe.

5. **Child ↔ parent universe relationship.** A child bead's LLM operates on a scoped slice
   but can reach up to its parent's universe (and the parent down to children) for context —
   without either loading the whole tree. (The *relationship* is in scope; automated
   summarization across it is v2.)

## Constraints

- **Built on Gas City.** **Gastown is mostly leaveable** — the bead-universe + node-mayor
  topology replaces most of Gastown's fixed-crew + pool machinery (polecat/refinery/deacon
  personas; pour/burn/sling). Use Gastown only where it earns a place. *(Compatible with
  foundation line 23's letter — not-using is not forking — and the operator has DECIDED
  foundation.md will be rewritten to "built on Gas City"; that rewrite is tk-egzn, not this
  run.)*
- **Judge by human-time at the system level**, not each mechanism individually.
- **Build on what already exists (inventory + verify FIRST):**
  - `gc-attention.sh` — the Pillar-2 prototype; its FOLLOW-UPS name the next cuts (pick-a-row
    launcher + LLM-interpretation/weighting layer).
  - **The tree** — bead deps, convoy (transient execution-means), epic (durable rollup).
    Branch structure largely exists.
  - **Sessions = the resident LLM instances** (one per bead-universe, conceptually).
  - **Threads already prove the mechanism** — multiple focused instances (mayor-thread,
    mechanik-thread — *this very conversation*) exist on demand today. One view of the whole
    model: **a thread per bead, ready on demand.** The resident-LLM is not new tech; the work
    is making it *per-bead*, *context-complete*, and *materialized on demand*, leaning on the
    existing **on_demand session lifecycle** — with its known sharp edges: **drain-on-detach,
    config-drift drain, picker-blind once drained.**
  - **The bead↔conversation link is convention-only today** (spawn-prompt + title; transcripts
    in `.gc/agents/`) — this is **the binding gap** (a necessary tech validation).
  - **Adjacent:** the city self-improvement loop (`lo-d5by`) = the audit nice-to-have; "city
    owns the seam, Workflow owns the middle" = the bead-LLM can delegate execution to a Claude
    Workflow while owning intake/landing at the bead.

## The Central Tension (what the design MUST nail)

Not "who decomposes." The real nut is **Pillar 1's hard edge: what defines a bead's universe,
and how does its LLM stay context-complete without context-overload?** It must reach
*everything* relevant (PR, CI, children, deps, history) yet operate on a *scoped, coherent
slice* — not the whole tree (token-ruinous, incoherent). **Where the universe boundary sits,
what is fed vs. fetched-on-demand, and how a child-universe relates to its parent's** — that
is the heart of the heart. (Completeness is not only for on-demand answering; it is also what
lets the LLM work *ahead* of the human.)

## Open Questions

(The exhaustive design process owns these; the 6 design legs map onto them.)

1. **Binding** *(necessary tech validation)* — durable conversation↔bead attachment; 0..N per
   bead; interactive vs. autonomous-transcript flavors.
2. **Context-completeness** *(THE core)* — what *is* a bead's universe; what is fed vs.
   fetched-on-demand; how the resident LLM reaches PR/CI/children/history; how a child-universe
   relates to its parent's.
3. **Attention surface** — evolve `gc-attention.sh`: render-what-floats → pick-a-row → drop
   into the bead-LLM; what ranks as "needs attention." (Not `prefix+S`.)
4. **Context to feed the owning LLM** — if a conversation already exists, context already
   exists; the question is the *scoped slice* fed to the bead's resident LLM.
5. **Escalation inversion** — bring the human to the bead-LLM vs. problem→mayor. Is mail still
   the means? Does the single mayor keep a home (root node? cross-tree?)? Flag-bead-needing-
   attention → human drops in.
6. **Minimal representation** — smallest bead/session change to support bead-universes +
   resident LLMs without precluding downstream nice-to-haves.
7. **Did it work?** — proxy for "human time optimized / nothing fell through" (foundation G1:
   fewer escalations over time, each higher-value).
8. **Selective proactivity** — which beads get proactive work, and how much? Every node-mayor
   exploring at once is real (if cheap) compute; the lazy↔proactive spectrum needs a budget,
   probably driven by the same attention-ranking as Pillar 2. And: how speculative ("accepted
   or not") work is surfaced for cheap accept/redirect.

## Rough Approach

A two-pillar system coupled by proactivity, built on existing primitives with the *smallest*
representational change:

- **Depth (Pillar 1):** define the bead-universe boundary and the fed-vs-fetched split; give
  each bead an on-demand resident LLM (a "thread per bead") that reaches PR/CI/children/deps/
  history on demand and acts as node-mayor over its subtree.
- **Breadth (Pillar 2):** evolve `gc-attention.sh` from render-what-floats into pick-a-row →
  spawn/attach the bead-LLM, with an LLM-interpretation/weighting layer for "needs attention."
- **Coupling (proactivity):** a budgeted, attention-ranked loop where bead-LLMs advance their
  universes ahead of the human and surface speculative work for cheap accept/redirect.
- **Binding** is the necessary tech validation underneath all of it (durable conversation↔bead
  attachment), reusing the on_demand session lifecycle and its known sharp edges.
- **Escalation** flips from problem→central-mayor to flag-bead → human-drops-in.

The design process must resolve the central tension (universe boundary + completeness-without-
overload + child↔parent relationship) before the UX, and judge the whole by human-time.

---

## Clarifications from Human Review (AUTHORITATIVE — amends the above where conflicting)

*Operator answers at the PRD gate, 2026-06-06. Full record + corrections in
`.plan-reviews/bead-universe/human-clarifications.md`.*

**Correction:** `consult-host` is an **abandoned idea, not a production prototype** — the
PRD-review's "build the seam from consult-host" framing is withdrawn; do not weight toward it.

**Amended scope (v1):**
- **Goals — G4 (proactivity) amended:** the resident always-on proactive loop is **deferred.**
  "Proactive" work in v1 = **slinging a mol** against a bead (reuse existing dispatch). The design
  must still work out how proactive-via-slung-mol behaves. The cheap **first reaction** is the
  content — research→spec, or an LLM reading the bead's **"body" (description/prompt)** and
  articulating what it means.
- **Goals — binding amended to 1:1** (one bead ↔ one LLM); 0..N deferred.
- **Goals — G6 / measurement amended:** capture the **intent** only; build **no** measurement
  architecture, pick no human-time unit now. Acceptance = a mechanical Definition of Done
  (binding + reachability demonstrably work).
- **Goals — G1 amended:** *any* bead **can** get an LLM on demand; **not every** bead has one
  (capability, not deployment). Rename "context-complete" → **"context-reachable"** throughout.
- **Node authority (NOT a non-goal):** a node-LLM **may act on its subtree** via normal primitives
  — sling an unslung bead, create a bead. This is fine. Only the **declarative-control
  reconciliation engine** stays out of scope.
- **Constraints — refinery kept** (merge gate). **Open design question:** how the mayor & mechanik
  are engaged conceptually in this model (unsettled — do not assume today's roles).
- **Non-Goals confirmed:** declarative-control engine, content-triggered mols, **automated**
  hierarchical distillation (parent↔child *relationship* in scope, fields-on-demand, no
  summarization — summarization is a later addition), audit/improvement loop, foundation.md rewrite
  (tk-egzn).
