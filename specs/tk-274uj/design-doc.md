---
name: Design — Stewardship Visits and Continuation-Group Granularity (Bead-Universe v2 completion)
description: Completes the v2 conversation model for STEWARDSHIP conversations ("let's move Epic X forward") — stewardship as a second visit kind, its subtree roll-up prep contract, its three formula-driven triggers, the routing constraint that makes the conversation a separate tracks-linked routed bead (never the epic, never its parent-child child), and the operator's ruling that continuation-group and hierarchy are orthogonal axes (with the two-layer prompt-influence mechanism that makes hierarchy real). Design-only.
---

# Design: Stewardship Visits and Continuation-Group Granularity

*Design-only spec for tk-274uj. It **completes** `specs/tk-h9pq5/design-doc.md`
(Conversation-as-Continuation-Group, Bead-Universe v2 — landed via PR#233, merged
`763e2825`). That doc models a conversation sitting as **reactive to a discrete event**
and mentions epics only as *duration*. It therefore cannot express "have a
conversation about moving Epic X forward" — a thing v1's bead-host did by
construction, and a property v2's own Q4 recommendation ("supersede the binding")
depends on. This spec closes that gap. Read tk-h9pq5's doc first; its primitives,
role contract, and sitting mechanism are assumed here and not re-derived.*

> **Vocabulary.** tk-h9pq5 says **turn**; the live surfaces say **visit**. The rename
> was an operator decision taken in the implementing PR on 2026-08-08 — `mol-turn.toml`
> → `mol-visit.toml`, `gate-turn` → `gate-visit`, `task_kind=conversation` →
> `task_kind=visit` (`specs/2026-08-fresh-start/liveness-and-triage-spec.md:8-12`).
> **This spec uses the live vocabulary throughout.** Read tk-h9pq5's "turn" as "visit".

> **Ground truth.** Where the ratified tk-h9pq5 design and the *ported* spine disagree,
> **the port wins** — it is what actually runs (`specs/2026-08-fresh-start/spine-port.md`,
> `formulas/mol-visit.toml`, `agents/converse/prompt.template.md`,
> `formulas/mol-witness-patrol.toml`). One such disagreement is load-bearing here and is
> stated where it bites (§1, orphan recovery).

---

## Scope

**Mandate.** How a v2 conversation addresses a **subject with aggregate state** (an
epic) rather than a discrete occurrence: the visit kind that does it, what that visit
owes the operator before it holds, what files it, and how conversation identity
relates to work hierarchy.

**Boundaries.** This is a completion of tk-h9pq5, not a replacement. It does not
revisit the v2 reframe, the role's claim contract, warm/cold continuity, or the
attention rewire — those are settled there, and their *as-shipped* form is settled in
the port. No implementation.

---

## Executive Summary

**Five things, four of which follow from one.**

1. **Stewardship is a second VISIT KIND, not a second agent.** The instruction lives
   on the visit bead's description, because `run-operator`'s contract is literally
   *"Execute exactly the claimed bead's description and result contract"*
   (`run-operator/prompt.template.md:175`). One conversation role therefore serves
   both event visits and stewardship visits, and the set of visit kinds is extensible
   **without touching any agent config**. This is an *advantage* over v1's bead-host,
   which baked one ownership posture into a static agent prompt — not a concession.

2. **A stewardship visit owes the operator a proposal, not archaeology.** Its prep
   contract is a subtree roll-up in four buckets — **ready / blocked-and-why / stale
   / contradictory** — plus **exactly one recommended next move**, and only then does
   it hold. It is the epic-scale analogue of `formulas/mol-first-reaction.toml`, which
   already does this for a single bead.

3. **Three triggers, one mechanism.** Operator, event, and formula all resolve to
   *run the canonical `gate-visit` snippet against the epic.* The event trigger is
   restricted to **aggregate-state** events; a single child's news is that child's
   conversation, not the epic's. Do not build three mechanisms.

4. **The conversation is a SEPARATE ROUTED BEAD, `tracks`-linked to the epic.** Pool
   demand is `bd ready … --unassigned --exclude-type=epic`
   (`gascity/internal/config/workquery.go:42`), so an epic can never *be* pool demand
   and a conversation can never be routed **at** an epic bead. That forces a separate
   claimable bead; it does **not** license hanging that bead off the epic with a
   `parent-child` edge — which is forbidden, because parent-child transmits the
   subject's blocked/arrested state to the visit (F-06). The canonical link is
   `tracks`. (§4.)

5. **Continuation-group and hierarchy are ORTHOGONAL AXES** — the operator's ruling,
   which supersedes the mayor's lean recorded in this bead's description. An epic
   **spans** many conversations; it does not *have* them. The epic has **one** group —
   its own — and resuming its conversation is *filing a new visit into that group*
   (that is the stewardship visit). A unit of work spun up under the epic gets a
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

tk-h9pq5 defines exactly one conversation class — stamped `task_kind=visit` on the
live spine — with no notion of visit *scope*, and models the subject of a visit as a
discrete occurrence ("PR review posted — decision needed"). Its prep step is "rebuild
the subject's fed slice."

That is sufficient when the subject is a leaf bead whose slice *is* the subject. It
is not sufficient when the subject is an **epic**, whose state is not a body to read
but an **aggregate to compute**: forty children in five phases, some ready, some
blocked on each other, some untouched for three weeks, two of them holding decisions
that contradict. "Rebuild the subject's fed slice" over an epic returns the epic's
one-paragraph body — which is precisely the archaeology the operator would then have
to do by hand, and precisely what v1's bead-host avoided by carrying "own the broader
epic" in its prompt.

So the gap is not a missing agent. It is a missing **visit contract**.

---

## 1. Stewardship as a Visit Kind

### The mechanism

A stewardship visit is an **ordinary v2 visit bead**, filed by the canonical
`gate-visit` snippet with no modification (`formulas/mol-visit.toml:36-55`):
`task_kind=visit`, `gc.routed_to=<rig-qualified converse pool>`,
`gc.continuation_group=<subject-id>`, and a `tracks` edge to the subject. The **only**
thing that makes it a stewardship visit is its `-d` body — the stewardship prep
contract (§2) in place of an event prompt.

That is the whole delta. **Stewardship needs no new filing mechanism, no new edge
type, and no change to the role.** The role does not branch on kind; it does what the
claimed bead's description says, because that is its entire contract:

> `run-operator/prompt.template.md:175` — *"Execute exactly the claimed bead's
> description and result contract."*

### Why this beats v1's bead-host (argue it as an advantage)

bead-host put "you own this epic while in conversation" in the **agent prompt**. That
is static and singular: one ownership posture, rendered identically for every hosted
bead, chosen at config time by whoever wrote the prompt. Wanting a second posture
meant a second agent — a second `agent.toml`, a second prompt to keep in sync, a
second pool, and a second always-on context cost.

v2 puts it in the **visit bead**. Three consequences, all in v2's favour:

- **Extensible at zero config cost.** A third or fourth visit kind (a triage visit, a
  ratification visit, a post-mortem visit) is a new *description template in a
  formula*. No agent, no pool, no prompt edit, no redeploy.
- **Per-visit posture on the same subject.** The same epic can take a stewardship visit
  on Monday and a narrow event visit on Tuesday. Under bead-host, posture was a
  property of the *host*, so it could not vary per visit.
- **The posture is legible and auditable after the fact.** The instruction that
  produced a given conversation is durable on the visit bead, not implicit in whatever
  the agent prompt happened to say that week. This matters for the same reason the
  whole reframe matters: *the record is the durable thing.*

The cost is that visit descriptions must be authored well and consistently. That is a
formula-authoring concern, and formulas are the intended home for it (§3).

### The class marker, and the recovery contract that actually ships

**`task_kind=visit` is the class marker, unchanged** — stamped by the canonical
snippet, and the structural tell the board and the patrols read.

**Orphan recovery does NOT skip it, and a stewardship visit must not ask it to.**
tk-h9pq5's Phase 2 specified a reaper-skip clause keyed on the conversation marker.
That clause was **deliberately not ported** (`spine-port.md` D4), and the live patrol
says the opposite in as many words:

> `formulas/mol-witness-patrol.toml:156-160` — *"there is no class of assigned bead
> that orphan recovery must skip. Visits and their converse sessions need no carve-out
> either: a visit whose session died mid-hold SHOULD return to the pool, because
> respawn-and-reconstitute-from-the-record is the cold continuity path."*

The filter is assigned-only and is pinned by a regression that executes it verbatim
(`assets/scripts/host-bead-skip.test.sh`). Recovery *is* kind-aware, but in the other
direction: for `task_kind == "visit"` the patrol releases **the assignee only**,
because the workflow reset would strip `gc.routed_to` / `gc.continuation_group` /
`task_kind` — which *are* a visit's identity (`mol-witness-patrol.toml:486-496`).

**A stewardship visit gets ordinary recovery, and is better off for it.** Its state is
a *computed roll-up*, not a conversation transcript: a died-mid-hold stewardship visit
that returns to the pool is re-prepped by a fresh converse session from the record,
which recomputes the subtree **as of the respawn**. Reviving a stale roll-up would be
strictly worse. This is the cold-continuity path working as designed, not a hazard to
be skipped around.

### The one piece of new metadata, and what it actually earns

Add `visit_kind` (`event` | `stewardship`) as the **subkind**, layered on
`task_kind=visit` (never in place of it). It is not read by the role — the description
is the instruction — so it must justify itself on other grounds.

**It does not earn its keep on dedup — the obvious first argument, and the wrong one.**
The live spine already dedups **group-wide and subkind-agnostically**: *"Skip if a visit
is live — the subject's id appears in `$CONVGROUPS` … Never stack a second visit on
one subject"* (`formulas/mol-triage-recurrence.toml:88-90`), with the same rule
enforced from the claim side by converse's concurrent-hold fold
(`agents/converse/prompt.template.md:24-33`). Two concurrent roll-ups of one subtree
are already impossible without any new key. §3's precondition is now that live rule.

What the key does buy is narrower and real:

> **The phase-checkpoint trigger needs to know that a stewardship roll-up specifically
> is in flight or was the last thing that happened on this epic.** A checkpoint asks
> "has this epic been rolled up and ratified before we proceed?" An unrelated event
> visit sitting in the epic's group does not answer that question — but it *does*
> satisfy the group-wide "a visit is live" rule, so the checkpoint cannot distinguish
> the two without a queryable facet. Prose in a description is not queryable.

Secondary, non-justifying benefits: the board can rank stewardship visits differently,
and "how often does an epic need stewardship" becomes answerable.

*Naming note.* An earlier draft of this spec called this key `turn_kind`, carried over
from tk-h9pq5's pre-rename vocabulary. It is spelled `visit_kind` here for the same
reason the operator renamed turn→visit on the live surfaces: a **new** schema key
spelled in retired vocabulary would fork the vocabulary a second time, on the one
surface — bead metadata — where the fork is queryable and therefore permanent.

---

## 2. The Stewardship Prep Contract

**The rule, stated once:** *the operator arrives at a proposal, not at archaeology.*

Before it holds, a stewardship visit rolls up the subject's subtree into four buckets
and commits to one recommendation. Everything below is what the visit's description
instructs; the role executes it because that is its contract.

### The four buckets

| Bucket | What it answers | How it is derived |
|---|---|---|
| **Ready** | What could move right now, and who would move it | `bd ready` scoped to the subtree; unassigned + routed rows are the ones a pool would actually claim |
| **Blocked — and why** | What cannot move, named by its blocker | open children held by an unclosed **ready-blocking** dep — the canonical set `bd ready` itself uses, `blocks` / `waits-for` / `conditional-blocks` (`gascity/internal/beads/beads.go:433-436`, `IsReadyBlockingDependencyType`); the *why* is the blocker's identity and status, not the word "blocked" |
| **Stale** | What has quietly stopped | no state change in N days (children whose last write predates the threshold), which is the only bucket that is invisible on a board |
| **Contradictory** | Where the subtree disagrees with itself or with the epic's frame | **not a query** — see below |

**Name the blocking set, never re-list a subset of it.** Ready and Blocked must
*partition* the open subtree, and they only do so if both sides read readiness the same
way. Ready is whatever `bd ready` returns, and `bd ready` blocks on all three types
above; a blocked predicate that hand-copies `blocks`/`waits-for` alone puts a child held
by a live `conditional-blocks` edge in **neither** bucket — `bd ready` excludes it, the
roll-up never names it, and the visit hands the operator a blocked count that is short
by exactly the children they most need to see, under a recommendation computed without
them. So the implementation names the canonical set (or asks core for it via
`IsReadyBlockingDependencyType`); it does not restate a predicate that already exists
upstream and can drift from it silently.

The subtree is walked over `parent-child`, which is the work axis and **only** the work
axis (§5). Because visits hang off their subject by `tracks` and not by `parent-child`
(§4), the roll-up never counts the epic's own conversations as work — the epic's visit
history is context for the roll-up, not a row in it.

The first three buckets are mechanical and should be computed, not narrated: a visit
that reports "12 ready, 3 blocked, 5 stale" and lists them is doing arithmetic the
operator should never do by hand.

**Contradiction is the bucket that is not mechanical, and that is the point.** There
is no dep type for "these two decisions are incompatible." Detecting that a child's
recorded decision contradicts the epic's frame — or another child's — requires
reading the rolled-up record and understanding it. That is exactly the work an LLM
does and a query cannot, and it is *why the stewardship visit is a conversation rather
than a generated report*. A design that made all four buckets mechanical would have
argued itself out of needing a conversation at all.

Honest limit: contradiction detection is **best-effort and unbounded in quality**. It
will miss things on a large subtree, and it degrades with record quality — the same
dependency tk-h9pq5 already flagged under "cold reconstitution quality depends on
record discipline." State it in the visit's output rather than implying completeness:
*what was read, and what was not.*

### The recommendation

**Exactly one recommended next move**, with its reasoning and its alternative. Not a
menu — a menu is archaeology with extra steps, and it pushes the synthesis back onto
the operator. One recommendation the operator can ratify in a single move, plus the
runner-up and why it lost, is the shape that makes the visit short.

Then the visit **holds** (`in_progress`), and on operator input writes the outcome to
the **subject** bead, stamps `gc.outcome` on the visit, and closes **only the visit**
— the live loop's steps 4-6 verbatim (`agents/converse/prompt.template.md:42-58`),
unchanged from v2. The epic is never closed by a stewardship visit.

### The analogue that already ships

`formulas/mol-first-reaction.toml` is this contract at single-bead scale: it "reads
the bead's body — its durable seed/prompt — does the cheap reaction …, writes a
first-reaction CARD to the bead notes, and files a visit on the bead so the human
arrives at advanced work through a held visit. Then it drains. One reaction, then
gone." A stewardship visit is the same move with the subtree as the body and the
roll-up as the card. Where first-reaction never closes its target, a stewardship visit
never closes the epic — the same invariant, for the same reason.

---

## 3. Triggers: Three Channels, One Mechanism

All three **run the canonical `gate-visit` snippet against the epic** — one visit,
stamped into the epic's group, routed to the converse pool. All three are
**formula-driven** — no trigger writes a session, and no event starts a conversation
directly.

**1. Operator — "let's talk about epic X."** A one-step formula that creates the visit
and routes it — i.e. `mol-visit` itself, with a stewardship body. This is the direct
replacement for bead-host's pick-a-row, and it is the same action tk-h9pq5's Phase 3
attention rewire performs from the Helm board.

**2. Event — but only AGGREGATE-state events.** An event drives a formula, which
decides whether a visit is warranted; the event never files the visit itself.
Qualifying events change the state *of the epic as a whole*:

- the **last** child of a phase closes (the phase is done — proceed or re-plan?)
- a child goes **blocked** in a way that stalls its siblings
- **N days with no child movement anywhere in the subtree**

**The discriminator, which follows from §5's orthogonality ruling:** *news about one
child is that child's conversation, not the epic's.* A PR opening, a review posting,
a single bead going blocked with its siblings still moving — those belong to the
child's own group. They reach the epic only if the child's conversation escalates
them (§5, the escalation clause), which is a decision made *by a conversation*, not
by an event router. This is what keeps a busy epic from generating a stewardship visit
per child event, and it is the same restraint the operator already imposed in v2 ("a
PR merely opening must not start a conversation").

**3. Formula — phase checkpoints.** The epic's own workflow files a stewardship visit
*before proceeding* past a checkpoint, so ratification is a step in the work rather
than an interrupt to it. This is the trigger that makes stewardship routine instead
of exceptional, and the only one that reads `visit_kind` (§1).

### Shared precondition: the live one-live-visit-per-subject rule

**No trigger files a visit while any visit is live (open or held) in the subject's
group.** This is not new policy — it is the shipped rule
(`mol-triage-recurrence.toml:88-90`, "Never stack a second visit on one subject";
converse's concurrent-hold fold at `prompt.template.md:24-33` catches the race from
the claim side). What each trigger does instead:

| Trigger | On a live visit in the epic's group |
|---|---|
| **Operator** | Do not file. The ask is already served: same group, so the live sitting *is* the conversation the operator wants — warm, the running session vacuums it. |
| **Event** | Skip and **stamp nothing**, exactly as triage recurrence does: a fact that arrives during a hold must resurface on the first pass after that visit closes, and stamping it as seen swallows it silently. |
| **Phase checkpoint** | Wait. The checkpoint is gated on a stewardship roll-up, so it re-fires after the live visit closes — and files only if that visit was not itself `visit_kind=stewardship`. This is the read that justifies the key. |

**The tempting alternative — append the new cause to the open visit's description —
is wrong.** It rewrites a held visit's contract mid-sitting, and a converse session
that has already prepped will not re-read it; worse, it can turn a narrow event visit
into a stewardship roll-up the operator never asked for. Skip-and-resurface is the
shipped idiom and needs no new mechanism.

---

## 4. The Structural Constraint: Why the Conversation Is a Separate, `tracks`-Linked Bead

Two questions, two independent answers. The obvious wrong answer to the first is
"route the conversation at the epic bead itself"; the obvious wrong answer to the
second is "then hang the conversation off the epic as its child."

### 4a. Why the conversation cannot BE the epic

Core routing forecloses it:

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
  shed (spine-port D3: *"Turn boundaries — not recycling — are the release valve by
  design"*).

So the conversation must be **its own routed bead**: a `task=visit` the pool can
actually offer.

### 4b. Why that bead is `tracks`-linked, NOT a parent-child child

The routing constraint above says nothing about the *edge*. Getting the edge wrong is
its own outage, and it is one this rig already had:

> **F-06 — "A visit on a blocked/arrested subject is never claimable: the parent-child
> edge transmits the subject's block."** `specs/2026-08-fresh-start/live-adoption-findings.md:227`,
> isolated with a 2×2 (four visits identical but for two variables): on an **arrested**
> subject, the visit **without** the edge entered `bd ready`; the visit **with** it never
> did. Fixed by moving to `tracks`, and confirmed end-to-end in round 2
> (`live-adoption-findings-round2.md:183`).

The canonical snippet now carries the rule and the reason inline
(`formulas/mol-visit.toml:49-54`), and `assets/scripts/gate-visit.test.sh:71-74` fails
any copy that omits `--type=tracks` **or** that contains `--type=parent-child`, in every
marked block under `formulas/*.toml`, and additionally fails if fewer than the four
known formula consumers carry one. This is a pinned invariant, not a convention.

**It bites hardest exactly here.** The subject in F-06 was an arrested bead; an epic is
the *long-lived* subject most likely to be carrying a blocker or an arrest at the
moment someone most needs to talk about it — "this epic is stuck" is a leading reason
to file a stewardship visit at all. A parent-child edge would make the stewardship
visit unclaimable on precisely the epics that need one.

**And it would corrupt the axis §5 depends on.** `parent-child` is the hierarchy axis:
§5's epic-ancestry walk climbs it, and §2's roll-up enumerates it. Hanging visits on
it would put the epic's own conversations into its own subtree — visits showing up as
"work" in the roll-up they produced, and an ancestry walk that has to filter them back
out. Two axes, two edge types, no overlap.

**When a `blocks` edge is right:** only when *another bead is genuinely gated on this
conversation* — the canonical snippet's commented `--blocks` line
(`mol-visit.toml:53-54`). A stewardship visit filed by a phase checkpoint is the
normal case for that: the checkpoint's downstream work waits on the ratification.
Blocking is a deliberate, per-case statement about *other* work; it is never the
lineage link.

**Conclusion.** The shape is forced twice over: core routing permits nothing but a
separate routed bead, and F-06 permits nothing but a `tracks` edge to reach it. Neither
is a style choice.

> *Implementation note for whoever builds this:* `agents/converse/prompt.template.md:13`
> still describes a visit as *"a child of its subject"* — loose wording that predates
> F-06 and now reads as an instruction to add the forbidden edge. The prompt's own
> filing rule points at the marked block (which is correct), so nothing is broken today,
> but the sentence should be reworded when that file is next touched. Out of scope here:
> this bead is design-only.

---

## 5. Continuation-Group Granularity — RESOLVED

### The ruling

**The operator has ruled. Continuation-group and hierarchy are ORTHOGONAL AXES.**

This **supersedes** the mayor's lean recorded in this bead's description ("group = the
epic, with a child getting its own group only when large enough"). That lean is wrong
and must not be designed.

| Axis | Encodes | Mechanism |
|---|---|---|
| **Continuation group** | *conversation identity* — which thread this visit belongs to | `gc.continuation_group` |
| **Hierarchy** | *work structure* — what this bead is part of | `parent-child` deps |
| **Lineage** | *what this visit is about* — non-blocking | `tracks` (§4) |

- **An epic spans MANY conversations. It does not have one.**
- **The epic itself largely has one thread — its own group.** Resuming a conversation
  with the epic = **file a new visit bead into the EPIC'S group**. That is the
  stewardship visit; the two are the same act.
- **A unit of work spun up under the epic gets a DIFFERENT group** — its own
  conversation, not the epic's.
- **A child knows it belongs to the epic through its PROMPT, not by sharing a group.**

### Why the superseded lean was wrong

Not merely inconvenient — it collapses the two axes, and the collapse costs exactly
what v2 was built to save. If group = epic, then every visit about every child lands
in **one** conversation. On a forty-child epic that is one provider context absorbing
forty threads of unrelated detail — which is the resume-forever context problem
tk-h9pq5 rejected, reintroduced through the group key instead of through session
lifetime. The property it was reaching for ("one epic, one mind, full history") is
real, but it is served by the **stewardship visit's roll-up** (§2), which reconstitutes
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
> not resolve it unilaterally — file a stewardship visit on the epic.**

**The final sentence is the load-bearing one.** It is the **escalation path** from a
child conversation up to the epic thread, and it is what makes the hierarchy *real
rather than decorative*: without it, "you belong to an epic" is a fact the child can
read and nothing it can act on. And it introduces no new primitive — *run `gate-visit`
against the epic* is the same single act as §3's triggers and as "resume the epic
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

The walk is clean precisely because visits do not ride this axis (§4): everything a
`parent-child` walk returns is work, so the climb terminates on the epic rather than
wandering into conversation beads.

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
   or that has no authority to file a visit, pays for nothing. Layer 3's per-agent
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
| Stewardship visit description template | **New** — the §2 prep contract, authored in a formula | the `-d` body of the canonical `gate-visit` snippet (`mol-visit.toml:36-55`) |
| `visit_kind` (`event`\|`stewardship`) on visit beads | **New** — read by the §3 phase-checkpoint trigger | bead metadata (free-form, no migration) |
| Stewardship trigger formula(s) | **New** — three entry points, one filing action | `gate-visit` snippet, copied with its markers |
| Epic-awareness fragment | **New** — protocol clause + escalation rule | `template-fragments/` + `inject_fragments_append` |
| `task_kind=visit`, the `gate-visit` snippet (incl. its `tracks` edge), the converse role and its loop, warm/cold continuity, **ordinary orphan recovery**, Helm rewire | **Unchanged** — a stewardship visit is an ordinary visit | `mol-visit.toml`, `agents/converse/`, `mol-witness-patrol.toml`, tk-h9pq5 |
| One-live-visit-per-subject rule | **Unchanged** — reused as §3's shared precondition | `mol-triage-recurrence.toml:88-90`, `agents/converse/prompt.template.md:24-33` |
| `gc.continuation_group` semantics | **Unchanged** — and explicitly *not* widened to epics | core |
| `parent-child` deps | **Unchanged** — already the hierarchy axis, and kept free of visits | core |

---

## Trade-offs and Decisions

- **Visit kind over a second agent.** (§1.) Extensibility at zero config cost and
  per-visit posture, at the price of visit-description authoring discipline. Formulas
  are where that discipline lives.
- **`visit_kind` earns its keep on the phase-checkpoint trigger alone.** (§1, §3.) The
  dedup argument this spec originally made for it is already served group-wide by the
  shipped one-live-visit rule. Stated plainly so a future reader can **retire the key**
  if the checkpoint trigger is dropped or changes shape.
- **`tracks`, not `parent-child`, for the visit→subject link.** (§4b.) Costs the
  intuition that a conversation "belongs to" its subject in the dep graph; buys
  claimability on blocked and arrested subjects (F-06) and keeps the hierarchy axis
  clean for §2's roll-up and §5's ancestry walk.
- **Ordinary orphan recovery, no reaper skip.** (§1.) Deviates from tk-h9pq5 Phase 2
  and follows the shipped port (spine-port D4): a died-mid-hold stewardship visit
  returns to the pool and is re-prepped against a *current* subtree, which is better
  than reviving a stale roll-up.
- **Orthogonal axes over group-per-epic.** (§5.) Operator ruling; the roll-up serves
  "one epic, one mind" better than a shared context does, and without the context bill.
- **Escalation is a judgment, not a route.** (§3, §5.) Child events do not
  auto-propagate to the epic. Costs some latency on genuinely epic-level news that a
  child under-escalates; buys the epic thread's coherence, and the child holds the
  context needed to make the call.
- **One recommendation, not a menu.** (§2.) A menu hands the synthesis back to the
  operator, which is the thing the visit exists to do for them.
- **Fragment injection over prompt forking.** (§5.) Already the city's idiom; the
  alternative (per-agent prompt copies) is the drift-generating pattern this pack
  avoids by policy.

---

## Risks and Mitigations

- **Roll-up quality degrades with subtree size.** Forty children is a long read;
  contradiction detection is best-effort (§2). *Mitigation:* the visit states what it
  read and what it did not; phase-scoped stewardship visits (roll up one phase, not the
  whole epic) are the natural escape hatch and need no new mechanism.
- **Trigger storms on a busy epic.** Three independent triggers on one subtree.
  *Mitigation:* the shipped one-live-visit-per-subject rule (§3), which already bounds
  the epic to one conversation at a time; triggers skip and resurface rather than
  stacking.
- **A stewardship visit whose session dies mid-hold loses its roll-up.** *Mitigation:*
  by design — recovery returns it to the pool and the fresh session recomputes the
  roll-up from the record (§1). The cost is one re-prep; the alternative (a skip clause)
  strands it assigned to a dead session.
- **Always-on context cost.** (Cost section.) *Mitigation:* protocol-only fragment,
  per-agent injection, measured delta against the landed ledger before landing.
- **The escalation clause is instruction-dependent, and instruction-dependent remedies
  fail silently.** A child that ignores "file a stewardship visit" produces no error —
  the epic simply never hears. *Mitigation:* prefer a structural backstop where one
  exists — the staleness event in §3 fires on a quiet subtree regardless of whether any
  child escalated, so the epic's blind spot is bounded by N days rather than unbounded.
- **Multi-hop ancestry walk on every claim.** A per-claim dep walk on deep trees costs
  a round trip. *Mitigation:* it is one `bd dep list` per hop against a local store;
  `gc.epic_id` as a cached hint exists if measurement ever justifies it (§5).

---

## Implementation Plan

Sequenced after tk-h9pq5's Phase 1 (the role + the visit spine), which this depends on
entirely — and which has shipped as the port. Each phase independently shippable; none
requires a schema migration.

**Phase A — The stewardship visit description (the contract).** Author the §2 prep
contract as a formula-owned `-d` body for the canonical `gate-visit` snippet; add
`visit_kind`. **Gate:** file a stewardship visit on one real epic → the role produces
all four buckets plus exactly one recommendation, then holds; the roll-up's
ready/blocked/stale counts match an independent `bd` query of the same subtree — with
the blocked query built over the **full** ready-blocking dep set (§2), and seeded with a
`conditional-blocks`-held child, since a partial predicate is the one failure this gate
would otherwise pass by counting nothing; the filed bead passes
`assets/scripts/gate-visit.test.sh` (tracks edge, no parent-child, `task_kind=visit`,
rig-qualified pool).

**Phase B — Triggers (§3).** The operator one-step formula first (it is the direct
bead-host replacement and is exercised by hand); then the phase-checkpoint formula;
then the aggregate-state event formula last, since it is the one that can storm.
**Gate:** each trigger files exactly one visit; with a visit already live on the epic,
the operator trigger files nothing, the event trigger files nothing **and stamps
nothing**, and the checkpoint re-fires after that visit closes.

**Phase C — Epic-awareness fragment (§5).** The protocol clause + escalation rule; the
per-agent injection list chosen from the ledger. **Gate:** a bead under an epic reports
its epic ancestor from a fresh claim without being told the epic id, and a seeded
contradiction produces a stewardship visit on the epic rather than a unilateral
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
2. **Does a phase-scoped stewardship visit need its own group?** If phase roll-ups become
   routine on large epics, a phase may be "large enough to be its own conversation" —
   the same judgment as "should this be an epic." The orthogonal model already permits
   it; whether it is wanted is an operating question, not a design one.
3. **How do the mayor and mechanik relate to epic threads?** Carried forward unresolved
   from tk-h9pq5's Open Question 2. Stewardship visits sharpen it: if an epic's own
   thread proposes the next move, the mayor's dispatch role over that epic narrows.
   Still a v1.5 question, still not to be pre-specified.
4. **Is contradiction detection worth any mechanical assist?** §2 argues it is
   irreducibly a reading task. A cheap pre-filter (children whose decisions touch the
   same file or the same central doc) might raise recall on large subtrees. Unproven;
   do not build it before Phase A shows where the misses actually are.

---

## Non-goals

- **No implementation.** Design only, per the bead.
- **No second agent.** Stewardship is a visit kind (§1); proposing a stewardship agent
  is the thing this spec argues against.
- **No revision of tk-h9pq5.** Its reframe, role contract, continuity model, and
  attention rewire are settled and assumed. Where the port deviated from it (D4, the
  reaper skip), this spec follows the port and says so (§1) rather than re-opening it.
- **No new edge type, and no change to the `gate-visit` snippet.** A stewardship visit
  is filed by the shipped block, verbatim (§1, §4b).
- **No queue/suspend policy.** Still deferred (tk-h9pq5 Q3).
- **No `gc.epic_id`.** Explicitly an optimization, not part of this design (§5).
