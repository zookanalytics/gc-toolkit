---
name: Design — Stewardship Turns and Continuation-Group Granularity (Bead-Universe v2 completion)
description: Completes the v2 conversation model for STEWARDSHIP conversations ("let's move Epic X forward") — stewardship as a second turn kind, its subtree roll-up prep contract, its three formula-driven triggers, the epic-routing constraint that forces turns-as-children, and the operator's ruling that continuation-group and hierarchy are orthogonal axes (with the two-layer prompt-influence mechanism that makes hierarchy real). Design-only.
---

# Design: Stewardship Turns and Continuation-Group Granularity

*Design-only spec for tk-274uj. It **completes** `specs/tk-h9pq5/design-doc.md`
(Conversation-as-Continuation-Group, Bead-Universe v2 — landed via PR#233, merged
`763e2825`). That doc models a conversation turn as **reactive to a discrete event**
and mentions epics only as *duration*. It therefore cannot express "have a
conversation about moving Epic X forward" — a thing v1's bead-host did by
construction, and a property v2's own Q4 recommendation ("supersede the binding")
depends on. This spec closes that gap. Read tk-h9pq5's doc first; its primitives,
role contract, and turn mechanism are assumed here and not re-derived.*

---

## Scope

**Mandate.** How a v2 conversation addresses a **subject with aggregate state** (an
epic) rather than a discrete occurrence: the turn kind that does it, what that turn
owes the operator before it holds, what files it, and how conversation identity
relates to work hierarchy.

**Boundaries.** This is a completion of tk-h9pq5, not a replacement. It does not
revisit the v2 reframe, the role's claim contract, warm/cold continuity, the reaper
skip, or the attention rewire — those are settled there. No implementation.

---

## Executive Summary

**Five things, four of which follow from one.**

1. **Stewardship is a second TURN KIND, not a second agent.** The instruction lives
   on the turn bead's description, because `run-operator`'s contract is literally
   *"Execute exactly the claimed bead's description and result contract"*
   (`run-operator/prompt.template.md:175`). One conversation role therefore serves
   both event turns and stewardship turns, and the set of turn kinds is extensible
   **without touching any agent config**. This is an *advantage* over v1's bead-host,
   which baked one ownership posture into a static agent prompt — not a concession.

2. **A stewardship turn owes the operator a proposal, not archaeology.** Its prep
   contract is a subtree roll-up in four buckets — **ready / blocked-and-why / stale
   / contradictory** — plus **exactly one recommended next move**, and only then does
   it hold. It is the epic-scale analogue of `formulas/mol-first-reaction.toml`, which
   already does this for a single bead.

3. **Three triggers, one mechanism.** Operator, event, and formula all resolve to
   *file a turn bead in the subject's group.* The event trigger is restricted to
   **aggregate-state** events; a single child's news is that child's conversation, not
   the epic's. Do not build three mechanisms.

4. **Turns-as-children is the only shape core routing permits.** Pool demand is
   `bd ready … --unassigned --exclude-type=epic`
   (`gascity/internal/config/workquery.go:42`), so an epic can never *be* pool demand
   and a conversation can never be routed **at** an epic bead. (The exclusion is
   tier-scoped — §4 shows why the assigned-tier loophole is a dead end anyway.)

5. **Continuation-group and hierarchy are ORTHOGONAL AXES** — the operator's ruling,
   which supersedes the mayor's lean recorded in this bead's description. An epic
   **spans** many conversations; it does not *have* them. The epic has **one** group —
   its own — and resuming its conversation is *filing a new turn into that group*
   (that is the stewardship turn). A unit of work spun up under the epic gets a
   **different** group: its own conversation. **A child knows it belongs to the epic
   through its PROMPT, not by sharing a group.**

**Which makes the operator's real question the load-bearing one: how do we influence
the prompts?** Answer, verified: **prompt composition is static; the bead is the only
dynamic input.** All twelve upstream role prompts use exactly two template variables
— `{{ .AgentName }}` and `{{ .TemplateName }}` — and **zero** bead-derived ones. So
epic-awareness is necessarily **two-layer**: a **static fragment teaches the
PROTOCOL** (which metadata locates you in a hierarchy, and what to do about it), and
**the bead supplies the PARTICULARS** (which epic). `run-operator` already ships
exactly this pattern, in a section literally titled *"## Continuation Group
Protocol"*. **Epic-awareness is one more key plus one clause — not a new mechanism.**

---

## Problem Statement

tk-h9pq5 defines exactly one `task_kind=conversation` with no notion of turn *scope*,
and models the subject of a turn as a discrete occurrence ("PR review posted —
decision needed"). Its prep step is "rebuild the subject's fed slice."

That is sufficient when the subject is a leaf bead whose slice *is* the subject. It
is not sufficient when the subject is an **epic**, whose state is not a body to read
but an **aggregate to compute**: forty children in five phases, some ready, some
blocked on each other, some untouched for three weeks, two of them holding decisions
that contradict. "Rebuild the subject's fed slice" over an epic returns the epic's
one-paragraph body — which is precisely the archaeology the operator would then have
to do by hand, and precisely what v1's bead-host avoided by carrying "own the broader
epic" in its prompt.

So the gap is not a missing agent. It is a missing **turn contract**.

---

## 1. Stewardship as a Turn Kind

### The mechanism

A stewardship turn is an ordinary v2 turn bead — child of the subject,
`gc.run_target=<conversation-role>`, `gc.continuation_group=<subject-id>` — whose
**description carries the stewardship prep contract** (§2) instead of an event
prompt.

Nothing else changes. The role does not branch on kind; it does what the claimed
bead's description says, because that is its entire contract:

> `run-operator/prompt.template.md:175` — *"Execute exactly the claimed bead's
> description and result contract."*

### Why this beats v1's bead-host (argue it as an advantage)

bead-host put "you own this epic while in conversation" in the **agent prompt**. That
is static and singular: one ownership posture, rendered identically for every hosted
bead, chosen at config time by whoever wrote the prompt. Wanting a second posture
meant a second agent — a second `agent.toml`, a second prompt to keep in sync, a
second pool, and a second always-on context cost.

v2 puts it in the **turn bead**. Three consequences, all in v2's favour:

- **Extensible at zero config cost.** A third or fourth turn kind (a triage turn, a
  ratification turn, a post-mortem turn) is a new *description template in a
  formula*. No agent, no pool, no prompt edit, no redeploy.
- **Per-turn posture on the same subject.** The same epic can take a stewardship turn
  on Monday and a narrow event turn on Tuesday. Under bead-host, posture was a
  property of the *host*, so it could not vary per visit.
- **The posture is legible and auditable after the fact.** The instruction that
  produced a given conversation is durable on the turn bead, not implicit in whatever
  the agent prompt happened to say that week. This matters for the same reason the
  whole reframe matters: *the record is the durable thing.*

The cost is that turn descriptions must be authored well and consistently. That is a
formula-authoring concern, and formulas are the intended home for it (§3).

### The one piece of new metadata, and why it earns its keep

Keep `task_kind=conversation` as the **class** marker, unchanged. tk-h9pq5's Phase 2
reaper-skip clause keys on it (`mol-witness-patrol.toml` orphan-recovery skip, sibling
case in `host-bead-skip.test.sh`); a stewardship turn is a conversation turn and must
be skipped by exactly the same clause, with no revision to a landed gate.

Add `turn_kind` (`event` | `stewardship`) as the **subkind**. It is not read by the
role — the description is the instruction — so it must justify itself on other
grounds. It does, on one:

> **Dedup.** Filing a second stewardship turn while one is open produces two
> concurrent roll-ups of the same subtree and two competing "recommended next moves"
> for one operator. The three triggers in §3 fire independently and *will* collide
> (a phase-checkpoint formula and a staleness event on the same quiet epic is the
> normal case, not the exotic one). The trigger's precondition is therefore *"no open
> bead in group `<epic-id>` with `turn_kind=stewardship`"* — which needs a queryable
> facet, not prose in a description.

Secondary, non-justifying benefits: the board can rank stewardship turns differently,
and "how often does an epic need stewardship" becomes answerable.

---

## 2. The Stewardship Prep Contract

**The rule, stated once:** *the operator arrives at a proposal, not at archaeology.*

Before it holds, a stewardship turn rolls up the subject's subtree into four buckets
and commits to one recommendation. Everything below is what the turn's description
instructs; the role executes it because that is its contract.

### The four buckets

| Bucket | What it answers | How it is derived |
|---|---|---|
| **Ready** | What could move right now, and who would move it | `bd ready` scoped to the subtree; unassigned + routed rows are the ones a pool would actually claim |
| **Blocked — and why** | What cannot move, named by its blocker | open children with unclosed `blocks`/`waits-for` deps; the *why* is the blocker's identity and status, not the word "blocked" |
| **Stale** | What has quietly stopped | no state change in N days (children whose last write predates the threshold), which is the only bucket that is invisible on a board |
| **Contradictory** | Where the subtree disagrees with itself or with the epic's frame | **not a query** — see below |

The first three are mechanical and should be computed, not narrated: a turn that
reports "12 ready, 3 blocked, 5 stale" and lists them is doing arithmetic the
operator should never do by hand.

**Contradiction is the bucket that is not mechanical, and that is the point.** There
is no dep type for "these two decisions are incompatible." Detecting that a child's
recorded decision contradicts the epic's frame — or another child's — requires
reading the rolled-up record and understanding it. That is exactly the work an LLM
does and a query cannot, and it is *why the stewardship turn is a conversation rather
than a generated report*. A design that made all four buckets mechanical would have
argued itself out of needing a conversation at all.

Honest limit: contradiction detection is **best-effort and unbounded in quality**. It
will miss things on a large subtree, and it degrades with record quality — the same
dependency tk-h9pq5 already flagged under "cold reconstitution quality depends on
record discipline." State it in the turn's output rather than implying completeness:
*what was read, and what was not.*

### The recommendation

**Exactly one recommended next move**, with its reasoning and its alternative. Not a
menu — a menu is archaeology with extra steps, and it pushes the synthesis back onto
the operator. One recommendation the operator can ratify in a single move, plus the
runner-up and why it lost, is the shape that makes the visit short.

Then the turn **holds** (`in_progress`), per tk-h9pq5's Engage step, and on operator
input writes the outcome to the **subject** bead, stamps `gc.outcome` on the turn, and
closes **only the turn**. Unchanged from v2.

### The analogue that already ships

`formulas/mol-first-reaction.toml` is this contract at single-bead scale: it "reads
the bead's body — its durable seed/prompt — does the cheap reaction …, writes a
first-reaction CARD to the bead notes, and files a visit on the bead so the human
arrives at advanced work through a held visit. Then it drains. One reaction, then
gone." A stewardship turn is the same move with the subtree as the body and the
roll-up as the card. Where first-reaction never closes its target, a stewardship turn
never closes the epic — the same invariant, for the same reason.

---

## 3. Triggers: Three Channels, One Mechanism

All three **file a turn bead into the epic's group and route it to the conversation
role.** All three are **formula-driven** — no trigger writes a session, and no event
starts a conversation directly.

**1. Operator — "let's talk about epic X."** A one-step formula that creates the turn
and routes it. This is the direct replacement for bead-host's pick-a-row, and it is
the same action tk-h9pq5's Phase 3 attention rewire performs from the Helm board.

**2. Event — but only AGGREGATE-state events.** An event drives a formula, which
decides whether a turn is warranted; the event never files the turn itself.
Qualifying events change the state *of the epic as a whole*:

- the **last** child of a phase closes (the phase is done — proceed or re-plan?)
- a child goes **blocked** in a way that stalls its siblings
- **N days with no child movement anywhere in the subtree**

**The discriminator, which follows from §5's orthogonality ruling:** *news about one
child is that child's conversation, not the epic's.* A PR opening, a review posting,
a single bead going blocked with its siblings still moving — those belong to the
child's own group. They reach the epic only if the child's conversation escalates
them (§5, the escalation clause), which is a decision made *by a conversation*, not
by an event router. This is what keeps a busy epic from generating a stewardship turn
per child event, and it is the same restraint the operator already imposed in v2 ("a
PR merely opening must not start a conversation").

**3. Formula — phase checkpoints.** The epic's own workflow files a stewardship turn
*before proceeding* past a checkpoint, so ratification is a step in the work rather
than an interrupt to it. This is the trigger that makes stewardship routine instead
of exceptional.

**Shared precondition (all three):** no open `turn_kind=stewardship` bead already in
group `<epic-id>` (§1). If one exists, the new trigger appends its cause to that
turn's description instead of filing a second — the open turn has not yet held, so
its roll-up will simply include the new fact.

---

## 4. The Structural Constraint: Why Turns-as-Children Is the Only Shape

The obvious wrong answer is "route the conversation at the epic bead itself." Core
routing forecloses it:

```
bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json
```
— `gascity/internal/config/workquery.go:42` (`bdReadyPoolDemandShell`)

The graph.v2 migration probe at `workquery.go:54` carries `--exclude-type=epic` as
well, so **both** pool-demand paths exclude epics. An epic can never satisfy pool
demand, therefore a conversation can never be *routed at* an epic. Live confirmation:
`tk-yhwfv` (type=`epic`, status=`open`, this rig's context-budget epic) is never pool
demand no matter what metadata it carries.

**The nuance worth stating, because it closes the loophole rather than leaving it:**
the exclusion is **tier-scoped**. `workquery.go:388` is explicit —

> *"Parent epics are excluded from the routed (pool) tier only … The assigned tiers do
> NOT exclude epics: work already assigned to this agent is owned, and the patrol-loop
> pattern … can self-assign an epic wisp that the agent must resume after a session
> restart."*

So one could imagine *assigning* an epic to a long-lived conversation session and
sidestepping the pool entirely. Reject it on two independent grounds:

- **It has no executable spec.** Same comment: *"An unassigned parent epic has no
  executable spec — its semantic is 'all children done' — so a pool worker claiming
  one does undefined work (gc-udx)."* A conversation role claiming an epic would be
  executing a bead whose description says nothing about this visit — the exact
  contract violation §1 is built on avoiding.
- **It resurrects v1.** An assigned epic held by a session *is* the bead-host: one
  resident conversation per epic, holding across the epic's whole life, accumulating
  context with no principled place to shed it. That is the single thing v2 exists to
  shed ("turn boundaries are the release valve").

**Conclusion: turns-as-children is not a style choice.** It is what core routing
permits, and independently what the v2 context bet requires.

---

## 5. Continuation-Group Granularity — RESOLVED

### The ruling

**The operator has ruled. Continuation-group and hierarchy are ORTHOGONAL AXES.**

This **supersedes** the mayor's lean recorded in this bead's description ("group = the
epic, with a child getting its own group only when large enough"). That lean is wrong
and must not be designed.

| Axis | Encodes | Mechanism |
|---|---|---|
| **Continuation group** | *conversation identity* — which thread this turn belongs to | `gc.continuation_group` |
| **Hierarchy** | *work structure* — what this bead is part of | `parent-child` deps |

- **An epic spans MANY conversations. It does not have one.**
- **The epic itself largely has one thread — its own group.** Resuming a conversation
  with the epic = **file a new turn bead into the EPIC'S group**. That is the
  stewardship turn; the two are the same act.
- **A unit of work spun up under the epic gets a DIFFERENT group** — its own
  conversation, not the epic's.
- **A child knows it belongs to the epic through its PROMPT, not by sharing a group.**

### Why the superseded lean was wrong

Not merely inconvenient — it collapses the two axes, and the collapse costs exactly
what v2 was built to save. If group = epic, then every turn about every child lands
in **one** conversation. On a forty-child epic that is one provider context absorbing
forty threads of unrelated detail — which is the resume-forever context problem
tk-h9pq5 rejected, reintroduced through the group key instead of through session
lifetime. The property it was reaching for ("one epic, one mind, full history") is
real, but it is served by the **stewardship turn's roll-up** (§2), which reconstitutes
the epic's state from the record on demand — cold, cheap, and current — rather than by
holding forty conversations in one context and hoping the relevant one is still in the
window.

The orthogonal model gets that property *better*: the epic's thread stays about the
epic, and each child's thread stays about the child.

### The real question: how do we influence the prompts?

If a child does not share the epic's group, the child's conversation must learn about
the epic some other way. The operator's question is the whole design problem, and its
answer is a verified constraint:

> **PROMPT COMPOSITION IS STATIC. THE BEAD IS THE ONLY DYNAMIC INPUT.**

All twelve role prompts in `gascity/roles/agents/*/prompt.template.md` (at the city's
adopted pin `sha:5b7c5c13`) use exactly **two** template variables —
`{{ .AgentName }}` and `{{ .TemplateName }}`, twelve occurrences of each, one per
prompt — and **zero** bead-derived variables. **A prompt cannot be rendered already
knowing which epic it is under.**

> **A premise of tk-h9pq5's Q5 has moved, and a future reader should know.** That doc
> recorded "gc-toolkit imports `gc-roles` nowhere today" and chose a native role partly
> to avoid taking on a new pack dependency. That is still true *of gc-toolkit* — but
> the city now imports `gascity/roles` into the **shutupandlisten** rig
> (`city.toml:105-107`, same pin). The import mechanics are therefore proven in-city,
> which weakens Q5's blast-radius argument without settling it. Not a decision this
> spec needs — flagged so Q5 is revisited against current facts rather than the ones
> that held when it was written.

Four layers can be influenced, and only one is dynamic:

| # | Layer | Where | When |
|---|---|---|---|
| 1 | Role prompt | `agents/<role>/prompt.template.md` | static |
| 2 | Shared fragment | `template-fragments/*.template.md` (`{{ define "…" }}`) | static |
| 3 | **Fragment injection** | `inject_fragments` / `inject_fragments_append` | **config-time** |
| 4 | **The bead** | `gc hook --claim --json` | **RUNTIME** |

**Layer 3 is the practical lever, and it is already in use in this city.**
`city.toml:71-77` appends `rebase-conventions` + `refinery-rebase-handling` to the
gascity rig's refinery and `rebase-conventions` + `polecat-patterns` to its polecat;
`pack.toml` does the same per-agent for gc-toolkit's own roles. Mechanically:
`InjectFragments` / `InjectFragmentsAppend` (`gascity/internal/config/config.go:753`,
`:785`; per-rig patch surface `internal/config/patch.go:126`, `:149`, applied at
`:572-579`). **An epic-awareness fragment can be added to an agent without forking its
prompt.**

### Therefore: epic-awareness is two-layer

**The static fragment teaches the PROTOCOL** — which metadata keys locate you in a
hierarchy and what to do with them. **The bead supplies the PARTICULARS** — which
epic. This is not a new pattern; `run-operator` ships it verbatim under a section
titled **"## Continuation Group Protocol"**:

> `run-operator/prompt.template.md:208-213`
> ```
> Important metadata:
>
> - `gc.root_bead_id` - workflow root for this bead
> - `gc.scope_id` - scope/body bead controlling teardown
> - `gc.continuation_group` - beads that prefer the same live session
> - `gc.scope_role=teardown` - cleanup/finalizer work; always execute when ready
> ```

**Epic-awareness is ONE MORE KEY PLUS A CLAUSE, not a new mechanism.**

### The clause

Draft; wording to be refined during implementation, semantics fixed:

> **If you have an epic ancestor, read its thread's record before deciding. It is your
> frame: your decisions must be consistent with it. If you find a contradiction, do
> not resolve it unilaterally — file a stewardship turn on the epic.**

**The final sentence is the load-bearing one.** It is the **escalation path** from a
child conversation up to the epic thread, and it is what makes the hierarchy *real
rather than decorative*: without it, "you belong to an epic" is a fact the child can
read and nothing it can act on. And it introduces no new primitive — *file a turn bead
into the epic's group* is the same single act as §3's triggers and as "resume the epic
conversation."

Note the symmetry with §3's event discriminator: child-level events do not reach the
epic automatically; they reach it when a child's conversation **decides** they should.
Escalation is a judgment, made by the party holding the context, which is the only
place that judgment can be made well.

### No new state is required

**Parent-child deps already encode "am I under an epic."** Verified live on this rig:

```
$ gc bd dep list tk-23wdf --direction=down -t parent-child --json
tk-yhwfv  [epic]  Context budget: audit and reduce always-on prompt context…
```

Two implementation notes for whoever builds this:

- **Direction is counter-intuitive and will be got wrong.** `--direction=down` lists
  *what this issue depends on* — i.e. **the parent**. `--direction=up` lists
  dependents (children). The upward walk to an epic ancestor is `down`.
- **The walk is multi-hop.** A bead may sit under a non-epic parent that sits under the
  epic; the protocol clause should say *ancestor*, and the walk should climb until it
  finds `issue_type=epic` or runs out.

A cached `gc.epic_id` would only save that walk. There is no such key in gascity today
(`grep epic_id internal/` → no hits). **Treat it as an optimization, not a
requirement** — and note the usual cost of caching a derived fact: it can go stale
against the dep graph if a bead is re-parented, so the graph stays authoritative and
the cache, if ever added, is a hint.

---

## Cost: this design adds always-on context, and that is contested ground

An epic-awareness fragment is **always-on**: every agent it is injected into pays it
on every spawn, and again on every compaction. `specs/tk-23wdf/context-budget-ledger.md`
(landed 2026-08-10) measures the polecat's rendered prompt at **102,550 bytes**, of
which 72.3% is gc-toolkit fragments, and records that `gc prime` **re-pays 102,486
bytes** on every compaction. Epic **tk-yhwfv** is actively trying to *reduce* that
number. This spec proposes adding to it.

The conflict is real and should not be papered over. Three constraints keep the
addition proportionate:

1. **Protocol-only in the fragment.** Keys, the walk, and the escalation rule.
   Everything situational goes in the bead, where it costs nothing when absent. Target
   the size of the `run-operator` block it is modeled on — a handful of lines, not a
   section.
2. **Inject only where it can fire.** An agent that never claims a bead under an epic,
   or that has no authority to file a turn, pays for nothing. Layer 3's per-agent
   granularity (`[[patches.agent]]` with `dir` + `name`) is exactly the right knob, and
   the ledger's per-agent table is how to choose the list.
3. **Measure it against the ledger before landing.** The method in
   `context-budget-ledger.md §3` is reproducible; a fragment that lands without a
   measured delta is how 70KB accumulated in the first place.

Worth noting that this spec is itself an instance of its own §5 clause: two epics'
frames disagree, and the design's own rule says a child does not resolve that
unilaterally — it surfaces it. This section is that surfacing.

---

## Interface

| Surface | Change | Built from |
|---|---|---|
| Stewardship turn description template | **New** — the §2 prep contract, authored in a formula | turn-filing convention (tk-h9pq5) |
| `turn_kind` (`event`\|`stewardship`) on turn beads | **New** — dedup key for the §3 trigger precondition | bead metadata (free-form, no migration) |
| Stewardship trigger formula(s) | **New** — three entry points, one filing action | `gc bd create` + `gc.run_target`→`gc.routed_to` |
| Epic-awareness fragment | **New** — protocol clause + escalation rule | `template-fragments/` + `inject_fragments_append` |
| `task_kind=conversation`, the conversation role, reaper skip, warm/cold continuity, Helm rewire | **Unchanged** — a stewardship turn is a conversation turn | tk-h9pq5 |
| `gc.continuation_group` semantics | **Unchanged** — and explicitly *not* widened to epics | core |
| `parent-child` deps | **Unchanged** — already the hierarchy axis | core |

---

## Trade-offs and Decisions

- **Turn kind over a second agent.** (§1.) Extensibility at zero config cost and
  per-visit posture, at the price of turn-description authoring discipline. Formulas
  are where that discipline lives.
- **`turn_kind` earns its keep on dedup alone.** (§1.) If dedup were not needed, the
  description would carry the whole contract and no new key would be justified. Stated
  this way so a future reader can retire the key if the trigger design changes.
- **Orthogonal axes over group-per-epic.** (§5.) Operator ruling; the roll-up serves
  "one epic, one mind" better than a shared context does, and without the context bill.
- **Escalation is a judgment, not a route.** (§3, §5.) Child events do not
  auto-propagate to the epic. Costs some latency on genuinely epic-level news that a
  child under-escalates; buys the epic thread's coherence, and the child holds the
  context needed to make the call.
- **One recommendation, not a menu.** (§2.) A menu returns the synthesis to the
  operator, which is the thing the turn exists to do for them.
- **Fragment injection over prompt forking.** (§5.) Already the city's idiom; the
  alternative (per-agent prompt copies) is the drift-generating pattern this pack
  avoids by policy.

---

## Risks and Mitigations

- **Roll-up quality degrades with subtree size.** Forty children is a long read;
  contradiction detection is best-effort (§2). *Mitigation:* the turn states what it
  read and what it did not; phase-scoped stewardship turns (roll up one phase, not the
  whole epic) are the natural escape hatch and need no new mechanism.
- **Trigger storms on a busy epic.** Three independent triggers on one subtree.
  *Mitigation:* the §3 open-turn precondition, which is why `turn_kind` exists;
  triggers append to the open turn rather than filing beside it.
- **Always-on context cost.** (Cost section.) *Mitigation:* protocol-only fragment,
  per-agent injection, measured delta against the landed ledger before landing.
- **The escalation clause is instruction-dependent, and instruction-dependent remedies
  fail silently.** A child that ignores "file a stewardship turn" produces no error —
  the epic simply never hears. *Mitigation:* prefer a structural backstop where one
  exists — the staleness event in §3 fires on a quiet subtree regardless of whether any
  child escalated, so the epic's blind spot is bounded by N days rather than unbounded.
- **Multi-hop ancestry walk on every claim.** A per-claim dep walk on deep trees costs
  a round trip. *Mitigation:* it is one `bd dep list` per hop against a local store;
  `gc.epic_id` as a cached hint exists if measurement ever justifies it (§5).

---

## Implementation Plan

Sequenced after tk-h9pq5's Phase 1 (the role + the turn spine), which this depends on
entirely. Each phase independently shippable; none requires a schema migration.

**Phase A — The stewardship turn description (the contract).** Author the §2 prep
contract as a formula-owned description template; add `turn_kind`. **Gate:** file a
stewardship turn on one real epic → the role produces all four buckets plus exactly one
recommendation, then holds; the roll-up's ready/blocked/stale counts match an
independent `bd` query of the same subtree.

**Phase B — Triggers (§3).** The operator one-step formula first (it is the direct
bead-host replacement and is exercised by hand); then the phase-checkpoint formula;
then the aggregate-state event formula last, since it is the one that can storm.
**Gate:** each trigger files exactly one turn; a second trigger firing against an open
stewardship turn appends rather than files.

**Phase C — Epic-awareness fragment (§5).** The protocol clause + escalation rule; the
per-agent injection list chosen from the ledger. **Gate:** a bead under an epic reports
its epic ancestor from a fresh claim without being told the epic id, and a seeded
contradiction produces a stewardship turn on the epic rather than a unilateral
resolution. Measured prompt delta recorded against `context-budget-ledger.md`.

**Definition of done (composite):** Phase A gate (roll-up correctness, automated
against `bd`) + Phase B gate (dedup, automated) + Phase C gate (escalation, seeded and
operator-judged) on one real epic.

---

## Remaining Open Questions

1. **What is N for staleness?** The subtree-quiet threshold is the one trigger
   parameter with no principled derivation here. Best answered by observing real epics;
   start deliberately long (a week) so the event trigger is the backstop it is meant to
   be rather than a source of noise.
2. **Does a phase-scoped stewardship turn need its own group?** If phase roll-ups become
   routine on large epics, a phase may be "large enough to be its own conversation" —
   the same judgment as "should this be an epic." The orthogonal model already permits
   it; whether it is wanted is an operating question, not a design one.
3. **How do the mayor and mechanik relate to epic threads?** Carried forward unresolved
   from tk-h9pq5's Open Question 2. Stewardship turns sharpen it: if an epic's own
   thread proposes the next move, the mayor's dispatch role over that epic narrows.
   Still a v1.5 question, still not to be pre-specified.
4. **Is contradiction detection worth any mechanical assist?** §2 argues it is
   irreducibly a reading task. A cheap pre-filter (children whose decisions touch the
   same file or the same central doc) might raise recall on large subtrees. Unproven;
   do not build it before Phase A shows where the misses actually are.

---

## Non-goals

- **No implementation.** Design only, per the bead.
- **No second agent.** Stewardship is a turn kind (§1); proposing a stewardship agent
  is the thing this spec argues against.
- **No revision of tk-h9pq5.** Its reframe, role contract, continuity model, reaper
  skip, and attention rewire are settled and assumed.
- **No queue/suspend policy.** Still deferred (tk-h9pq5 Q3).
- **No `gc.epic_id`.** Explicitly an optimization, not part of this design (§5).
