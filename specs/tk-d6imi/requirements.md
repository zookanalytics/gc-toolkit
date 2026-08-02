---
name: Requirements — docs/architecture.md (gc-toolkit 30k-ft guide)
description: The brief and scoping decisions for tk-d6imi — why docs/architecture.md exists, its altitude, and its distinct subject vs the other central docs — plus the two PR #225 review rounds: the round-1 redirect to a one-substrate model, then the round-2 premise-level rewrite to the belief → primitive spine (architecture derives from foundation.md and operationalizes it on Gas City primitives), three engagement modes, and the Gas City-substrate / GasTown-independent position.
---

# Requirements — write `docs/architecture.md` (gc-toolkit)

This is the durable decision record for **tk-d6imi**: the brief that scoped a
new central `docs/architecture.md` and the calls made while writing it. The
authoritative artifact is `docs/architecture.md` itself; this file preserves
*why it was written that way*.

## Goal

Write a concise, **30,000-ft architectural guide** to how gc-toolkit's concepts
are *implemented*. It names the core features the pack delivers, the
**architectural pattern** behind each, how they play together, and where each is
defined — so the repo reads as one coherent system, and both what's built and
what's built next can be checked for consistency against it.

## Audience & altitude

- **Primary reader:** operator strategic reference — wants the *mental model* of
  what the pack is and how it's implemented. NOT a contributor how-to.
- **Altitude:** 30,000 ft. Broad architectural terms. **Name the pattern; don't
  tutorialize.** No code, no config syntax, no CLI-flag references, no
  file-line detail in prose.
- **NOT a decision-tree.** It explains *how we implement the concepts
  architecturally*, not "where to put your change."
- **Concise & scannable.** Target ~1–2 pages, consistent per-capability
  micro-structure. Each pattern is a phrase; interplay is a line; resist
  expanding into how-to.

## Distinctness (one doc per subject — link, don't duplicate)

- `foundation.md` = the **why** (beliefs/goals) → link.
- `roadmap.md` = the **where-to** (direction/primitives) → link.
- `README.md` = pitch/install; `file-structure.md` = filing conventions → link.
- `architecture.md` = **how it's built & how it coheres** (patterns + interplay
  + definition-sites). This is its distinct subject.

## Organizing spine: two flows + support, on one composition substrate

> **Superseded as the doc's *front* by the PR #225 redirect** (see
> [Redirect](#redirect--operator-review-of-pr-225-tk-pqjla) below). It survives
> as the *reference half* of the doc — the map — but no longer opens it. The
> text below is the original brief, preserved as history.

The pack exists to run **two flows**; everything else supports them, all wired
by one substrate.

- **Flow 1 — Attention** (the Bead-Universe Operating Model; epic `tk-q4xaj`):
  pre-advance work before it claims human attention.
- **Flow 2 — Delivery** (filed bead → landed, live change).
- **Support layers:** engine health, fork & upstream, doc & knowledge cohesion.
- **Composition substrate:** how all of the above is wired and where each lives.

## Per-capability entry contract

For each capability: **what it delivers · the architectural pattern that
implements it · how it plays with the rest · where it's defined.** A small
two-flows diagram is welcome IF it aids the at-a-glance "how they play together"
— optional, keep it minimal.

## Forward lever

Close with a short note (a few sentences, not a routing tree): the doc is the
consistency map — new capabilities should slot into one of these flows/layers
and reuse its pattern; that's how "what gets built next" stays coherent.

## Verification (accuracy is the point of a cohesion doc)

- **Verify every "where defined" against the actual files** before asserting it.
  The file-level survey wins over the brief; correct any pattern name or
  definition-site the brief got wrong.
- Ground every pattern claim in the pack (`pack.toml`, the fragments, the
  formulas, the docs). If a claimed pattern isn't how it actually works, fix the
  doc.

## Deliverables

1. `docs/architecture.md` — the guide (central tier; standard frontmatter per
   `file-structure.md`).
2. `specs/tk-d6imi/requirements.md` — this brief as the durable decision record
   (local tier; per the filing-documentation rule it must not live only as a
   bead comment).

## Acceptance criteria

- [ ] `docs/architecture.md` exists; central-tier frontmatter; ~1–2 pages; scannable.
- [ ] Organized as two flows + support + composition substrate; each capability
      entry carries delivers / pattern / plays-with / defined-in.
- [ ] Patterns named at 30k ft; no code / CLI / decision-tree.
- [ ] Every definition-site verified against real files.
- [ ] Links (not restatements) to `foundation.md`, `roadmap.md`,
      `file-structure.md`, `work-bead-state-machine.md`,
      `gascity-local-patching.md`; references epic `tk-q4xaj`.
- [ ] `specs/tk-d6imi/requirements.md` committed.
- [ ] PR opened; passes the standard merge-gate. (Owned convoy: closed = landed.)

## Process

- Owned convoy anchors this to landed (closed = landed).
- Standard merge-gate applies (human approval + codex). **Do not self-merge.**
- mechanik reviews before it lands.

---

## Redirect — operator review of PR #225 (tk-pqjla)

*Amendment, 2026-07-29. Everything above is the original brief and is preserved
as written; this section records what changed and why. Rework bead `tk-pqjla`,
a child of `tk-d6imi`, landed on the same PR (#225) — not a new deliverable.*

> **Superseded in framing by the round-2 review** (see
> [Round 2](#round-2--operator-review-of-pr-225-tk-wpows) below). The
> "one substrate / two laws / two localities" model this section ratified was
> itself rejected at the next review as a premise-level miss — laws should not
> be authored in architecture.md, and grounding runs to `foundation.md`, not the
> state machine. This section is preserved as history; the ratified model is now
> **belief → primitive**. Read Round 2 for what stands.

### What the operator rejected

The first draft satisfied the brief above and still missed the point. In the
operator's words it "misses the simplicity of the overall process intention."
The diagnosis: the doc was an **implementation decomposition**. It opened at
"two flows + support layers + composition substrate" — a description of how the
pack is *assembled* — and never stated the **primitives those layers operate
on**. A reader finished it knowing how the pack is put together and still not
knowing what the system *is*.

The failure is instructive and worth keeping: the original brief asked for
"how the concepts are implemented" and got exactly that, because it never
required the concepts themselves to be stated first. An architecture doc whose
front is a decomposition answers *what is built*; it cannot answer *what this
is*.

### The ratified spine — one substrate, two localities

The operator ratified this structure explicitly. The point is that the pack's
rules are **derived**, not listed — a flat bullet list of invariants would
reproduce the same failure at a different altitude.

**The bead is the substrate.** Two laws over it:

- **Law 1 — locality of truth.** The bead owns the artifact. This law is
  **canonical and already written** in `docs/work-bead-state-machine.md`, so
  architecture.md states it in one line, **links**, and does not restate the
  state machine (one doc per subject). Its consequences are listed compactly —
  one owning bead per artifact; open = unlanded / closed = landed; one bead or
  many is the same machine (the degenerate one-child convoy); the check-set is
  one class of gate; an unowned artifact is an exception the board catches.
- **Law 2 — locality of attention.** The bead owns the conversation about it.
  This is **new synthesis** — written nowhere else in the repo, so this doc is
  where it lands. It promotes the bead-host from an *agent* to a *law*: one
  bead / one resident durable conversation; the bead raises its own hand onto
  the board rather than the operator scanning a queue; the operator arrives at a
  warmed, framed conversation.

The **symmetry is the deliverable**: Law 1 is where an artifact's *truth* lives,
Law 2 is where its *dialogue* lives; both answer "where does this belong?" with
*the bead*. That symmetry is the simplicity the review was asking for.

Grounding rule applied to Law 2: because it is new synthesis rather than a
citation, each of its three consequences had to be traceable to a real pack file
(`agents/bead-host`, `assets/scripts/gc-helm.sh`, `agents/proactive` +
`formulas/mol-first-reaction.toml`) — cut, not asserted, if it could not be.

### Intake is a named gap, deliberately

Both laws presume a bead exists. **Intake — the moment a new thing becomes
one — sits outside both**, because there is nothing yet to own the truth or host
the conversation. The doc states this as a **predicted consequence of the
model**, not a loose TODO, and grounds it: `agents/` ships no native intake
agent, every native role is post-bead (a host is spawned only at an existing
bead and refuses to be a sling target; a first reaction is slung *at* a bead),
and the one plausible front — `mayor` — is imported from gastown, not designed
here.

**The doc does not name a front door, and that is deliberate.** Which agent owns
intake is an open design decision the operator explicitly reserved. Describe
what is, name the gap, stop. A future decision on intake should amend this
record rather than treat the gap as an oversight.

### Structural consequences

- New outline: `## The model` (substrate + Law 1 + Law 2 + the hole) → `## How
  it runs` (three scenarios) → `## The map` (the existing body, demoted to
  `###` subsections and trimmed) → `## The consistency map`.
- **`## How it runs` is the user-centric half**: idea → bead → board → host
  (whose first arrow *is* the hole); bead → convoy → merge-gate → landed (the
  degenerate one-child convoy); the many-child initiative that graduates. Short
  walkthroughs showing the laws in motion, not restating them.
- The original two-flows body became the **reference half** and was trimmed to
  pay for the new front. Trimming compressed prose only — **every "Defined in."
  line was preserved byte-for-byte**, since the verified definition-sites are
  the doc's durable value.
- Budget moved from the original "~1–2 pages" to **~3 pages**; the two flows are
  now framed in the map as "Law 1 / Law 2 in running code."
- The forward lever sharpened: the consistency test is now *the model* first —
  a new capability should be a consequence of Law 1 or Law 2, or an honest named
  exception like intake — and only then "which flow or layer does it slot into."
- `Scope` and the frontmatter `description` were updated to say the doc leads
  with the operating model; the altitude discipline (name patterns, no code, no
  CLI flags, no config syntax, no decision tree) is unchanged.

### Amended acceptance criteria

Supersedes the checklist above where they conflict; the rest still applies.

- [ ] Leads with `## The model`: bead-as-substrate, Law 1 (one line + link to
      `work-bead-state-machine.md`, consequences as phrases), Law 2 (new, each
      consequence grounded in a pack file), intake as a named structural gap.
- [ ] `## How it runs` carries the three scenarios.
- [ ] The original body survives as `## The map`, trimmed, with every
      "Defined in." line intact and re-verified at the branch tip.
- [ ] Law 1 vocabulary is quoted from `work-bead-state-machine.md`
      ("everything is owned", "locality of truth", "one class of gate",
      "degenerate one-child convoy"), not paraphrased into new terms.
- [ ] No front door is invented or asserted.
- [ ] ~3 pages; same links and the `tk-q4xaj` epic reference retained.
- [ ] Lands on PR #225 as added commits — no second PR, no second anchor.

---

## Round 2 — operator review of PR #225 (tk-wpows)

*Amendment, 2026-07-29. Everything above is preserved as written; this section
records the second review round and what it changed. Rework bead `tk-wpows`, a
child of `tk-d6imi`, landed on the same PR (#225) — a premise-level rewrite, not
a new deliverable. Source of truth: 27 operator inline comments on PR #225 at
`ce42c8d`, and the design decisions recorded in the `tk-d6imi` bead notes.*

### What the operator rejected (round 2)

The round-1 rewrite led with "one substrate, two laws / two localities." The
operator rejected the framing at the premise level — an edit pass would not fix
it:

- **"Law" is the wrong unit.** architecture.md invented laws and derived them
  from `work-bead-state-machine.md` — the least-reviewed doc in the set. Both
  moves rejected: do not author laws in architecture.md, and do not ground in the
  state machine.
- **Dependency inversion.** `work-bead-state-machine.md` and other
  implementation docs are **downstream** of architecture.md, not upstream.
  architecture.md takes its influence from `foundation.md`; the state machine
  takes its influence from architecture.md.
- **The Attention/Delivery flow taxonomy** split by machinery and hid where
  human conversation enters. Replaced by three engagement modes keyed on how
  much conversation a bead needs.
- **Intake-as-a-hole.** Arguing about what does not exist is not architecture.
  Replaced by naming the *surfaces* and being honest about what is temporary.

### The ratified spine — belief → primitive

Operator-ratified, chosen explicitly over a flat list of rules:

> **foundation.md holds the beliefs. architecture.md shows how those beliefs are
> operationalized on Gas City primitives. work-bead-state-machine.md and other
> implementation docs are downstream of architecture.md.**

The unit of the doc is **belief → primitive**, not "law." For each foundation
belief, architecture.md shows which Gas City primitive(s) operationalize it.
Vocabulary is defined before motion — the primitives first, so the flows can be
written in terms already established. The five primitives, each traced to a
belief and grounded in a real definition-site verified at the branch tip:

| Primitive | Belief it operationalizes | Grounded in |
|---|---|---|
| bead | Decisions have a home | `work-bead-state-machine.md` ("everything is owned / locality of truth") |
| molecule | Agents earn every interaction | `docs/gascity-packs.md`; `formulas/mol-*` |
| check | Agents make their edges visible | `work-bead-state-machine.md` ("the check-set: one class of gate") |
| skill | The pack borrows before it invents | `foundation.md` Boundaries ("pack-local … skills"); `skills/` |
| board | Human attention is the budget | `assets/scripts/gc-helm.sh`; `services/helm/` |

Molecules and checks are **Gas City primitives** — the means by which foundation
is made tangible — **not** beliefs. They must not be added to foundation.md
(confirmed: neither foundation.md nor roadmap.md names molecules or checks). The
belief *Agents improve* deliberately maps to no single primitive; it is carried
across the map, and the doc says so rather than inventing a primitive for it.

### The three engagement modes

Replace Flow 1 / Flow 2 entirely. The axis is how much human conversation a bead
needs to reach done:

1. **Automated to resolution** — filed → landed with no human in the loop; a
   first-class, supported path, not an aspiration; most such beads create code.
2. **Needs conversation to move at all** — the bead is the locus of the
   conversation; the operator arrives warmed and framed.
3. **A human joins an existing artifact** — a bead or a PR; the conversation
   attaches via the bead, since everything gets a bead (or one is created).

### Law-vs-implementation — enforcement stripped from the model

The most-repeated correction: the draft encoded enforcement as law. Each is
demoted to implementation (the map), not the model:

- **codex has no place in architecture.md** — one check among many, may be gone
  tomorrow. CHECKS are the architectural item; codex is a replaceable instance,
  named in the model nowhere and in the map only as a replaceable
  review-executor (`agents/polecat-codex`, `agents/_polecat-gemini`).
- the **merge-gate** is implementation; architectural is only that gates exist
  and that things can be asserted true through the workflow.
- **human approval** is not architectural — it is a check only a human can
  currently resolve.
- **convoys** are too specific for the model's altitude.
- **"the board catches unowned artifacts"** is enforcement. The boundary is kept
  (an unowned artifact is a defined exception — part of the rule's own edge) but
  the mechanism moved to the board primitive / map.

### Intake as surfaces, not a hole

Resolved by the operator: the mayor allows bead creation today and any
conversation can create a bead; the "named hole / open design gap" framing is
rejected. architecture.md defines the surfaces — have a conversation about X,
start a new conversation, ensure work Y progresses, create a new unit of work —
and, where today's architecture is temporary-but-workable (starting a brand-new
conversation), says so under "What is not well defined today." No front door is
invented.

### Skills — the dropped thread restored

Skills were absent from round 1. Leveraging skills and the agent ecosystem is
core to gc-toolkit. This is a dropped thread, not new invention: foundation.md's
Boundaries already names "pack-local … skills." architecture.md gives skills a
primitive entry grounded there and in the shipped `skills/`
(`filing-documentation`, `handoff`, `session-title`, `demo-capture`,
`gc-demo-script`).

### Gas City vs GasTown — and the second file

- **Gas City is the substrate.** Leverage its primitives heavily; do not depend
  on any Gas City *fork* modification; actively remove such dependencies.
- **GasTown is an example pack, not an upstream we augment.** Take what is
  genuinely reusable (reusable molecules above all); otherwise independent;
  avoid copying. gc-toolkit is realistically an independent implementation of its
  own approach on top of Gas City — GasTown's attention/helm model diverges
  materially.
- The wholesale-import + bare-name fragment-append pattern is **not** encoded as
  the architecture; it is transitional and being reduced.
- **Second file, this PR:** `docs/foundation.md` Boundaries corrected, because
  architecture.md now derives from it and the old sentence conflated Gas City
  with Gastown and called the pack an augmentation of both. The edit is minimal
  and surgical — the Boundaries premise only; "pack-local … skills" preserved
  intact as the skills-section anchor.

### Structural consequences

- New outline: `## Scope` (durable Mandate that names the *category*, not the two
  laws, per `file-structure.md`) → `## What we operationalize with` (the five
  primitives, each traced to a belief) → `## How work moves` (three engagement
  modes + a mermaid diagram) → `## What is not well defined today` (intake
  surfaces, the molecule/check interlock, the composition transition) →
  `## The map` (verified definition-sites, rewritten framing, composition
  rewritten to the independent-implementation position) → `## The consistency
  map` (forward lever re-anchored on belief → primitive).
- The ASCII diagram was replaced with a mermaid diagram of the three modes and
  where conversation enters.
- The two praised paragraphs were preserved in character: the owned-convoy
  close-on-land pattern (Delivery) and the engine-health layer where gastown's
  imported agents come straight in.
- Every "Defined in" definition-site was re-verified against files at the branch
  tip.
- Out of scope, own beads: the `docs/roadmap.md` rewrite (`tk-zf4vm`), and the
  gastown import-strategy decision. `roadmap.md` is stale and being rewritten
  separately, so it is no longer cited as an anchor here.

### Amended acceptance criteria (round 2)

Supersede the round-1 checklist where they conflict.

- [ ] Derives from foundation.md; no invented laws; `work-bead-state-machine.md`
      linked as downstream, not restated.
- [ ] `## What we operationalize with` names bead / molecule / check / skill /
      board, each traced to a foundation belief and grounded in a real
      definition-site.
- [ ] `## How work moves` carries the three engagement modes and a mermaid
      diagram.
- [ ] codex is named nowhere in the model; checks are the architectural item;
      merge-gate / approval / convoys demoted to implementation.
- [ ] Skills have a primitive-level section grounded in foundation.md.
- [ ] Intake framed as surfaces with an honest "not well defined today" note; no
      front door invented.
- [ ] Composition states the Gas City-substrate / GasTown-independent position;
      the import pattern is not encoded as the architecture.
- [ ] `docs/foundation.md` Boundaries corrected, minimal and surgical.
- [ ] Durable Mandate that names the category, not the two laws.
- [ ] Lands on PR #225 as added commits — no second PR, no second anchor.
