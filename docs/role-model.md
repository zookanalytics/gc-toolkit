---
name: Role Model
description: The stable contract behind every gc-toolkit role — the taxonomy, the universal contract a role answers, the cross-role relationships, and the invariants — separate from the agent files that realize it. Read this to understand what a role *is* before reading how any one agent is wired.
---

# Role Model

A gc-toolkit **role** is a durable identity with a contract: a mandate, a
place in the system, and invariants it must uphold. An **agent** — the
`agents/<name>/` directory plus the running session it spawns — is how a
role is *realized* at a point in time.

This doc is the stable half. It names the role taxonomy, the contract every
role answers, how roles relate, and the invariants that hold across them. It
does **not** carry the specifics — prompt prose, `idle_timeout` values, the
`work_query` shell, fragment lists. Those drift; they live in the agent
files and are cited from here, never copied.

This is the same split the pack already trusts elsewhere. `docs/` is what's
true now; `specs/` is what was thought ([file-structure.md](file-structure.md)).
A doc's [`## Scope`](file-structure.md#the-scope-section) charter "names the
category, not the members" — stable while the governed content moves. **A
role's spec is that doctrine applied to roles**: the contract is the
category, the agent files are the members. The external analog is OpenAI's
Symphony, where one stable `SPEC.md` fixes the orchestration model and the
`WORKFLOW.md` *schema* while repository-owned `WORKFLOW.md` carries the
volatile policy — prompt text, dispatch rules, hooks
([SPEC.md](https://github.com/openai/symphony/blob/main/SPEC.md)).

## Scope

**Mandate.** What a gc-toolkit role *is* — the taxonomy of role kinds, the
contract every role answers, the relationships between roles, and the
invariants that hold across them. It also holds the per-role **charter**
(mandate + boundaries) for every role gc-toolkit defines, and records what
gc-toolkit asserts about the roles it imports and patches.

**Boundaries.** This governs the role *contract*, not its *realization*: the
prompt prose, config values, fragment wiring, and provider choices are the
agent files' to hold, and this doc points at them rather than restating
them. For roles gc-toolkit imports from gastown, the authoritative prompt
and charter live upstream; this doc records only the taxonomy slot and the
patches gc-toolkit layers on. The mechanics of *wiring* an agent into a city
— imports, `[[patches.agent]]`, `[[named_session]]`, overrides — belong to
[install.md](install.md).

## Role vs. agent: the spec/realization split

| | Role (the spec — here) | Agent (the realization — `agents/<name>/`) |
|---|---|---|
| Answers | "What is this, and what must it uphold?" | "How is it wired right now?" |
| Holds | mandate, boundaries, taxonomy slot, contract, invariants | prompt prose, config values, fragments, provider, namepool |
| Stability | stable; re-chartered deliberately | moves whenever the world does |
| Lives in | `docs/role-model.md` | `agent.toml`, `prompt.template.md`, `PROVENANCE.md` |

The spec is **governing, not generative**. It does not generate a prompt;
it constrains one. A realization is correct when it upholds its charter and
the invariants — the same way a `docs/` doc is correct when its body still
serves its `## Scope`, and the way Symphony's spec constrains but never
authors a `WORKFLOW.md`. Drift between a charter and its agent files is a
bug to fix in the files, not a reason to quietly loosen the charter.

## The role contract

Every role answers the same set of questions. These are the **dimensions** —
the contract's schema — not their values; a role's values live in its
`agent.toml`.

- **Identity & scope.** `city` or `rig`. A provider if it overrides the
  default process (e.g. `codex`, `gemini`).
- **Lifecycle & materialization.** `wake_mode` (`fresh` discards the
  conversation each wake; `resume` carries it). Idle behavior (suspend vs
  die) and timeout. Whether the role is materialized `always` or on-demand,
  and its session-count band (`min`/`max_active_sessions`).
- **Work intake.** Two predicates decide how work reaches the role: a
  **demand** predicate (`work_query`) the reconciler runs to decide whether
  to spawn, and a **sling** predicate (`sling_query`) that says whether the
  role is a valid `gc sling` target. A nudge string is what the role reads
  on wake.
- **Inputs.** Where direction comes from — routed mail, `gc hook` (assigned
  and routed beads), decision/desire-path beads, the operator, the role's
  own observation.
- **Outputs.** What the role produces — config changes, dispatched beads,
  branches/PRs, notes, attention-board cards.
- **Relationships.** Who routes to it, who it coordinates with, and whether
  it is a *canonical* identity (the system of record) or a non-canonical
  variant that borrows a canonical's persona.
- **Realization wiring.** Whether it owns its `prompt_template` or renders
  another role's by reference, which fragments it injects/appends, its
  `work_dir`, and any `env`.

### The three hats (specialist roles)

A role dedicated to a *domain* — a specialist — is expected to wear three
hats within it ([roadmap.md](roadmap.md#three-hats-for-any-specialist-agent)):
**Partner** (reactive: answers, consults, records decisions), **Active**
(seeks out: patrols for drift, promotes decisions hiding in other
conversations), **Library** (keeps the data: knows what artifacts exist and
retrieves them fast). The Active and Library hats require persistence
between invocations, which is why specialist work picks a persistent role
over a formula-only one.

## Role taxonomy

Four kinds, distinguished by their contract shape. Every gc-toolkit role —
and every role it imports — falls into one.

### Persistent specialist
City-scoped, `wake_mode = "fresh"`, materialized `always`, claims routed
work and reads routed mail. The system-of-record identity for its domain;
wears the three hats. Designed to outlive any single conversation.
*Members:* `mechanik`. (Imported gastown `mayor`, `deacon` are persistent
roles of this shape, though only the mayor is a domain specialist in the
three-hats sense.)

### Pool worker
Rig-scoped, `wake_mode = "fresh"`, `min_active_sessions = 0` with a capped
`max`, one worktree per instance via a `pre_start` setup script. Spawned by
the reconciler to meet pool demand and drained when demand falls. Fungible:
identity is per-instance (a namepool), not durable. *Members:*
`polecat-codex`, `proactive`, `_polecat-gemini` (disabled — leading `_`
hides it from discovery). Imported gastown `polecat`, `refinery`, `witness`,
`boot` are pool/utility roles.

### Operator-spawned thread
City-scoped, `wake_mode = "resume"` (the conversation *is* the artifact),
long idle timeout, **never a sling target and never auto-spawned** (see the
operator-only invariant below). Renders a canonical role's prompt under its
own identity and appends the `thread-role` fragment, so it carries the full
persona and authority but is **not** the system of record. A parallel
thinking surface beside the canonical. *Members:* `mayor-thread`,
`mechanik-thread`.

### Per-bead host
City-scoped, `wake_mode = "resume"`, operator-spawned only, with `alias` =
the bead id (alias uniqueness gives a 1:1 bead↔session link for free).
Suspends between visits and resumes on demand — a register for one bead's
conversation, not a worker. *Members:* `bead-host`.

> **Imported and patched roles.** gc-toolkit imports the gastown roster
> (`mayor`, `deacon`, `polecat`, `refinery`, `witness`, `boot`) and layers
> divergence as bare-name `[[patches.agent]]` fragment-appends — it does not
> own their prompts. `dog` comes from the auto-included maintenance pack, not
> gc-toolkit at all ([DOG-NOTE](../agents/DOG-NOTE.md)). For these, the
> authoritative charter lives upstream; this doc records only their taxonomy
> slot and the fragments gc-toolkit appends (see `pack.toml`).

## Invariants

Properties that hold across roles regardless of realization. A realization
that violates one is broken, even if it runs.

- **Operator-only spawn (threads, hosts).** A role meant to be spawned only
  by the operator must make that structural, not advisory: its demand
  predicate emits no demand (so the reconciler never auto-spawns it) and its
  sling predicate fails loudly (so an accidental `gc sling` errors instead of
  silently routing). Realized today as `work_query` returning `[]` and
  `sling_query` exiting non-zero.
- **Dispatch, don't direct-edit (mechanik).** A role that *stewards*
  versioned pack content scopes and reviews changes to it rather than editing
  it in place; the edits flow through beads to pool workers. The audit trail
  outweighs the saved minute. (Mechanik Principle 6; applies to gc-toolkit
  pack content, not the role's own scratch dir or city config.)
- **Shed first under pressure (proactive).** A role budgeted as
  best-effort sheds before load-bearing work does: when the city is at its
  session cap, its demand predicate emits no demand so it drains first and
  never starves the impl pool.
- **Code takes the gated path (proactive).** Any code a best-effort
  reaction produces takes the review-gated merge path, never `direct` —
  enforced in depth (city default, agent `env`, and the tool that slings it).
- **Re-read on resume (hosts, threads).** A `resume` role wakes into a world
  that moved while it was suspended; its first act is to re-read its anchor
  (the bead, the focus) rather than act on a stale snapshot.
- **Threads route, they don't doer-own.** A thread carries a canonical's
  persona and authority but not its inbox, patrol cadence, or
  system-of-record identity; cross-agent coordination it produces is filed as
  beads, not delivered from the thread's own mailbox.
- **Merge-strategy agnostic.** No role assumes a particular merge strategy
  (`direct`/`mr`/`pr`). The consuming rig chooses; the role adapts
  ([roadmap.md](roadmap.md#merge-strategy-agnosticism)).

## Charters

The stable mandate and boundaries for each role gc-toolkit defines. Each
points at its realization; it does not restate it.

### mechanik
**Mandate.** City-level structural engineer for Gas City's own
infrastructure — owns agent configuration, formulas, dispatch patterns,
quality gates, prompt engineering, operational conventions, tooling
ergonomics. The structural counterpart to the mayor's coordination and the
deacon's runtime patrols. **Boundaries.** Does not grind beads; does not
direct-edit gc-toolkit pack content (dispatches it). Taxonomy: persistent
specialist (three hats). Realization: `agents/mechanik/`.

### mechanik-thread / mayor-thread
**Mandate.** A parallel, operator-spawned thinking thread carrying the full
persona and authority of its canonical (`mechanik` / `mayor`) — files beads,
slings, pushes — for focused work beside the canonical's queue.
**Boundaries.** Not the system of record: does not own routed mail, the
patrol cadence, or the canonical identity; never a sling target; never
auto-spawned. Taxonomy: operator-spawned thread. Realization:
`agents/mechanik-thread/`, `agents/mayor-thread/` (each renders its
canonical's prompt by reference and appends `thread-role`).

### bead-host
**Mandate.** A per-bead conversation register — one resumable session bound
1:1 to a bead via its alias — created on demand so any bead *can* get a host
without every bead having one. **Boundaries.** Purely interactive: never
claims pool work, never a sling target, never auto-spawned; the durable
bead↔session link lives in metadata, outside the agent config. Taxonomy:
per-bead host. Realization: `agents/bead-host/`.

### proactive
**Mandate.** A dedicated, small rig pool that runs slung first reactions
(`mol-first-reaction`) — a cheap read-the-bead-and-flag-it pass that lands
work on the attention board so the human arrives at advanced state.
**Boundaries.** Default-disabled (opt-in gate); first to shed at the city
cap so it never starves the impl pool; any code it emits takes the gated
merge path, never `direct`. Taxonomy: pool worker. Realization:
`agents/proactive/`.

### polecat-codex / polecat-gemini
**Mandate.** Pools of polecat workers identical in role to gastown's
`polecat`, switched to an alternate provider (`codex` / `gemini`) with a
distinct worktree tree and session cap. **Boundaries.** Intentional
divergence from gastown's polecat is limited to provider, `work_dir`, and
cap; the prompt is shared by reference and the same convoy / non-impl-done
fragments are injected. `polecat-gemini` ships disabled (leading `_`).
Taxonomy: pool worker. Realization: `agents/polecat-codex/`,
`agents/_polecat-gemini/`.

### Imported roster (charter upstream)
`mayor`, `deacon`, `polecat`, `refinery`, `witness`, `boot` are imported
from gastown; `dog` from maintenance. gc-toolkit asserts only their taxonomy
slot and the fragments it appends — see the `[[patches.agent]]` blocks in
`pack.toml` and [DOG-NOTE](../agents/DOG-NOTE.md). Their authoritative
charters live with their upstream prompts.

## Adding or changing a role

1. **Charter first.** Write or amend the role's charter here at the
   mandate/boundary altitude, and place it in the taxonomy. If a proposed
   role fits no taxonomy slot and upholds no clear invariant, that is a
   signal to reconsider the role, not to bend the model.
2. **Realize it to conform.** Write/adjust the agent files so they uphold the
   charter and every invariant for that taxonomy slot. Per the
   dispatch-don't-direct-edit invariant, mechanik scopes this as a bead and
   reviews the pool worker's diff rather than editing the files itself.
3. **Keep the charter stable.** Routine config churn — a new `idle_timeout`,
   a tweaked `work_query` — does not touch this doc. The charter changes only
   on a genuine re-charter (mandate or boundaries shift) or when it has gone
   inaccurate. Re-chartering is a deliberate editorial act, like
   [adding a central doc](file-structure.md#drafting-and-adoption).
