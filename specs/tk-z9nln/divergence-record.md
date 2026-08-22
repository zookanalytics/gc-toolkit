---
name: Divergence record — gc-toolkit design intent vs the running system (2026-08-22)
description: Point-in-time audit-as-diff for the bead, PR, and visit data flows plus the seam where they compose. For each divergence it states the design intent, what the running system does, whether the gap was deliberate or drift, and what it costs today. Read it to find out which design documents still describe the system and which have been outlived.
---

# Divergence record: design intent vs running system

**Measured 2026-08-22, against `main` at `3d624df`.** Every current-state
claim below cites a file:line or a command output taken at that commit.
This is a point-in-time record, not a live document: it will go stale, and
that is expected of anything under `specs/`.

## Scope

Covers the three data flows the operator named — the lifecycle of a bead, a
PR, and a visit — plus the seam where they compose, audited as a **diff**
between what the design record says and what the code does. It does not
restate the three lifecycles themselves: `docs/work-bead-state-machine.md`,
`docs/refinery-merge-cadence.md`, and `docs/gascity-human-engagement.md`
each own one and are individually fresh. It does not propose the doc
changes it implies; that work is scoped in [Deliverable C](#deliverable-c)
and filed separately.

## Method

Read the design record (`specs/bead-universe/`, `specs/tk-h9pq5/`,
`specs/2026-08-fresh-start/`, `docs/foundation.md`, `docs/architecture.md`),
then verified each named artifact against the tree and the live CLI. Where
the audit brief supplied a prior measurement, it was re-derived rather than
copied — one such re-derivation overturned the brief's framing (below).

---

## The headline: the audit's own premise was wrong, and that is the finding

The brief that commissioned this audit stated that
`specs/bead-universe/design-doc.md` is "dying the same death" as the
deleted `docs/roadmap.md`, evidenced by a census in which **every** named
artifact is absent:

> `agents/bead-host/` ABSENT · `gc bd universe --slice` no such subcommand ·
> `gc attention open|flag` no such subcommand · `assets/scripts/gc-attention.sh` ABSENT

Each of those five observations is individually **true** — re-verified at
`3d624df`:

```
$ ls -d agents/bead-host        → No such file or directory
$ gc bd universe tk-x           → Error: unknown command "universe" for "bd"
$ gc attention open tk-x        → gc: unknown command "attention"
$ ls assets/scripts/ | grep -i atten  → (no match)
```

**The conclusion drawn from them is false.** The census searched for v1's
artifacts under v1's names, and found absence. It did not search for the
*capabilities*, which shipped — under different names, on a different
surface, because of a deliberate, written-down supersession. Two structural
facts explain every "absent" line:

1. **A pack cannot add subcommands to `gc`.** `gc` is a Go binary; the
   pack's command surface is `tools/gc-*.sh` and `assets/scripts/*.sh`.
   Probing for `gc bd universe` and `gc attention` was therefore a test that
   *could not have passed for any pack feature*, shipped or not.
2. **v1 was superseded by a v2 that is itself on the record.**
   `specs/tk-h9pq5/design-doc.md` — "Conversation-as-Continuation-Group
   (Bead-Universe v2)", settled in operator discussion 2026-07-29 —
   explicitly retires the v1 artifacts the census went looking for.

Here is what actually shipped:

| v1 design element | Status | What is in the tree at `3d624df` |
|---|---|---|
| `agents/bead-host/` (Phase 1) | **Retired by v2** | `agents/converse/` — cites `specs/tk-h9pq5/` as authority (`agents/converse/PROVENANCE.md:6`) |
| `hosts_bead` / `host_session` links | **Retired by v2** | `gc.continuation_group = <subject-bead-id>`; the group name *is* the binding |
| `gc bd universe <id> --slice` (Phase 2) | **Shipped, renamed** | `tools/gc-bd-universe.sh slice` (22 KB) + `tools/bead-universe-reachability-fixture.sh` |
| `gc-attention.sh` board (Phase 3) | **Shipped, renamed** | `services/helm/` (Go service + web UI) + `assets/scripts/gc-helm.sh` |
| `gc attention open` (Phase 3) | **Shipped, renamed** | `assets/scripts/gc-helm.sh open` / `gc-visit-open.sh` |
| `gc attention flag` + `gc.attention` (Phase 3) | **Deliberately removed** | Nothing. Replaced by filing a visit — `specs/2026-08-fresh-start/attention-flag-removal.md` |
| `mol-first-reaction` + proactive pool (Phase 4) | **Shipped, default-off** | `formulas/mol-first-reaction.toml`, `agents/proactive/`, `tools/gc-proactive.sh` |

So the bead-universe model is not an outlived map. It is **substantially
built**. The one genuinely abandoned piece is v1's central technical bet,
and it was abandoned on purpose — see D3.

**Why this matters more than the correction itself:** the false conclusion
was not careless. It was the predictable result of following the citations
that the live code itself provides. That is D1, and it is the most
expensive finding in this record.

---

## The mandated question, answered

> *Is the bead-universe operating model still the intended direction, or has
> it been superseded by the 2026-08 fresh-start work?*

**Still the intended direction. It was superseded only *within its own
line*, v1 → v2, and not by the fresh-start work at all.** The record
settles this without ambiguity:

- **v2 is a reframe of the same goal, not a replacement of it.**
  `specs/tk-h9pq5/design-doc.md:65` — "The bead-universe goal is unchanged
  from v1: bring the operator's serial, scoped attention to the right branch
  of the work tree." What changed is the mechanism: v2 states its scope of
  supersession precisely as "the bead-host *binding and lifecycle*" and
  keeps the board (`specs/tk-h9pq5/design-doc.md:51`).
- **The v1 implementation epic closed cleanly.** `tk-q4xaj` — "Bead-Universe
  Operating Model v1 — implementation" — `closed 2026-06-13T05:52:48Z`.
  v2 cites that closure itself (`specs/tk-h9pq5/design-doc.md:9`).
- **The fresh-start work is orthogonal.** `specs/2026-08-fresh-start/gas-city-native.md`
  is a *substrate* position paper — "what if gc-toolkit just used Gas City
  as it is being designed today" — mapping pack systems onto upstream
  equivalents. It asks what the pack should stop building. It does not
  propose a different answer to the attention problem, and it does not
  mention superseding bead-universe.
- **The built system already says so.** `docs/architecture.md:162` describes
  the converse role, grounded in `specs/tk-h9pq5/`, as "the built system."

No further operator ruling is needed to establish this. The direction is
intact; the *citations pointing at it* are what broke.

---

## Findings

Ordered by cost. "Deliberate" means a decision record exists; "drift" means
the system moved and nothing updated the claim.

### D1 — Eight live artifacts cite a superseded design as their authority, which has no forward pointer · **DRIFT** · material

**Intent.** `docs/foundation.md` — "Decisions have a home. Documentation is
the system's memory. What's written survives; what isn't, doesn't." And
`docs/architecture.md:308` ("The consistency test") requires a capability to
trace a straight line back to a belief.

**Running system.** Eight live (non-`specs/`) artifacts name
`specs/bead-universe/design-doc.md` as their design authority:

```
agents/proactive/PROVENANCE.md:10          agents/proactive/agent.toml:3
formulas/mol-first-reaction.toml:5         tools/gc-proactive.sh:3
tools/gc-bd-universe.sh:4                  tools/helm-surface-fixture.sh:3
tools/proactive-first-reaction-fixture.sh:3
tools/bead-universe-reachability-fixture.sh:3
```

Several cite it by *phase* — `formulas/mol-first-reaction.toml:5` reads
"Phase 4 of the Bead-Universe Operating Model (specs/bead-universe/design-doc.md
— Key Components 5-6, Phase 4)."

And `specs/bead-universe/design-doc.md` contains **no forward pointer to
v2**: grepping it for `h9pq5`, `v2`, `supersed`, or `Superseded` returns
nothing. It also carries no frontmatter, so it has no `description` field in
which a supersession note would conventionally sit (`docs/file-structure.md:256`
makes frontmatter mandatory on local spec docs; this doc predates that rule).

**Why it is drift, not deliberate.** v2 lists what it retires
(`specs/tk-h9pq5/design-doc.md:239`) but nothing swept the citations, and
the retirement was never stamped on the retired document. `agents/converse/`
was rebuilt against v2 and cites it correctly — so the pack updated the
*code* and left the *pointers*.

**Cost, already paid.** An agent that follows any of those eight citations
lands in a design whose Phase 1 has been retired, whose Phase 3 verbs were
deleted, and which gives no indication of either. That is exactly what
happened when this audit was framed: the brief's census, its "dying the same
death" verdict, and its instruction to treat the bead-universe model as a
candidate for supersession all follow from reading v1 as current. The
audit's own premise is the measured cost.

### D2 — `docs/roadmap.md`'s tracker outlived the file by 20 days · **DRIFT** · material

**Intent.** A tracking bead should not outlive its subject.

**Running system.** `tk-t4rlv` — "Refresh or retire docs/roadmap.md — stale
(pre-bead-universe; lists retired architect as upcoming)" — is `status=open`,
created 2026-06-13, last updated 2026-07-29. The file it names was deleted
2026-08-02 in `e851a08` ("docs: delete docs/roadmap.md — carry its 3 unique
primitives into architecture.md (tk-gwj51) (#244)"). `ls docs/roadmap.md` →
No such file or directory.

**Cost.** One permanently unsatisfiable open bead, and a second-order one:
it is a live invitation to recreate the file. The brief's standing rule
"never resurrect docs/roadmap.md" exists because this tracker still asks for
it. This is the same class as D5 — a wait recorded once and never
re-evaluated.

**Disposition.** Genuinely disposed of: the work landed in `e851a08`. It
should be closed with a successor pointer via `assets/scripts/bead-rehome.sh`,
never a bare close.

### D3 — The conversation layer runs `wake_mode=fresh`; v1's central bet was resume · **DELIBERATE** · not material, but the most load-bearing gap to understand

**Intent (v1).** The whole spine. `specs/bead-universe/design-doc.md:15-17`
— "A conversation bound to a bead, that you can create, suspend, and
resume." `:94-95` specifies `agents/bead-host/agent.toml` as `consult-host`'s
shape "with two changes: `wake_mode=resume` (carry the conversation)". The
doc explicitly rejects the alternative: the abandoned `consult-host` used
`wake_mode=fresh`, "which discards the conversation each wake". v1's Phase 0
existed solely to de-risk whether resume carries a conversation across a
drain.

**Running system.** `agents/converse/agent.toml:8` — `wake_mode = "fresh"`.
The rejected shape is the shipped shape. The file is candid about the
consequence (`:27-29`): "the stop clears the scrollback, and wake_mode=fresh
makes the respawn a clean session: the thread is UNRECOVERABLE, not hidden."

**Why deliberate, and why it is an improvement.** v2 inverted the bet rather
than losing it. `specs/tk-h9pq5/design-doc.md:41-48`: session slots were
never the binding constraint — provider *context* is, and "a resume-forever
session spanning a months-long epic blows context with no principled place
to shed it." v2's answer is that turn boundaries are the release valve:
because a turn writes its outcome back to the subject bead, "at any turn
boundary the session can be allowed to die and nothing written down is
lost." The engineering burden flips from keeping a session alive to making
the record good. `agents/converse/agent.toml:30` states the same in
operational terms: "the pack's defense is durability, not longevity."

**Cost.** None from the substitution itself. The residual cost is that v1 —
still cited by eight artifacts (D1) — describes resume as the spine, so a
reader who has not found v2 will believe the system carries conversations
across suspends. It does not.

### D4 — `gc.attention` is fully removed; v2 still says the board keeps it · **DELIBERATE**, with a stale downstream claim · minor

**Intent (v1).** `specs/bead-universe/design-doc.md:127` — `gc attention flag`,
"escalation inversion: a bead's LLM raises its own bead onto the board (sets
`gc.attention`)."

**Running system.** Zero live references. Grepping `gc.attention` across
`*.sh`, `*.toml`, `*.go`, `*.ts`, `*.tsx` outside `specs/` returns nothing.

**Deliberate, with a full decision record.**
`specs/2026-08-fresh-start/attention-flag-removal.md` carries the operator's
2026-08-08 decision verbatim and the defensibility check that preceded it:
the flag was "a bare metadata bit with no lifecycle (set, often never
cleared), no upstream meaning … and it is the backdoor form of agents
asserting urgency, which the operator has separately rejected." The
replacement is filing a visit. The sweep inventory names every site removed.
This is the model case — the decision, its reasoning, and its scope are all
on the record.

**The residue.** v2 predates the removal by ten days and lists among what it
*keeps*: "the `gc.attention` board / Helm picker as the human-facing surface"
(`specs/tk-h9pq5/design-doc.md:51`), with an Interface row citing
"`gc.attention` board" (`:237`). v2 is the live design authority for
`agents/converse/`, so a stale clause there costs more than one in v1. The
capability (the board) survived; only the flag died — so the claim misleads
about mechanism, not about direction.

### D5 — The composition seam: a subject's wait is free text, so completion never propagates · **DRIFT** · material, and the operator has hit it three times

This is the seam the brief identified as unowned by any document, and it has
a live P1 sitting exactly on it: **`tk-2plde`** (open, 2026-08-22).

**Intent.** Operator's framing, quoted on the bead: "waiting, holding, those
are graph states, not comments."

**Running system.** A parked subject's entire graph footprint is
`dependencies: []`, no parent, and three metadata keys (`gc.takeaway`,
`gc.takeaway_at`, `gc.takeaway_by`). The board's parked predicate —
`assets/scripts/gc-helm.sh:1434` — is:

```
(if ($tk | length) > 0 then "parked" else empty end)
```

A non-empty takeaway string is the whole test. It reads no dependencies. So
"holding — awaiting X" and "nothing further needed here" are mechanically
identical rows. Nothing re-asks whether the thing a subject was waiting on
has landed.

**Measured cost.** `tk-yps55` sat parked for 29 hours after the work it was
waiting on (`tk-hgmob`) merged 2026-08-21T06:54Z in PR #398 — and cost the
operator a full converse sitting to discover it was already finished.
Operator: "The need to load this at all was a waste of time and deserves a
fix." The board's parked budget is capped (`assets/scripts/gc-helm.sh:241`,
`GC_HELM_MAX_PARKED` default 15) and sits at the cap, so every terminal
remnant evicts a live conversation; by their own takeaway text roughly 6 of
the 15 are self-declared terminal.

**It is a class, not an incident.** The same defect — a wait recorded once
and never re-evaluated — appears in three surfaces: `tk-puh9d` (P2, open
since 2026-08-02, `blocked` never auto-clears when deps close: the edge
exists and nothing re-derives from it); `tk-st143` (P1, open since
2026-08-14, the liveness sweep files visits about already-landed work); and
`tk-2plde` itself, where there is no edge to read at all. D2 is a fourth
instance in a different surface.

**Already tracked.** `tk-2plde` owns the fix and proposes a shape. This
record adds the generalization — that it is one instance of a class the
system hits repeatedly — and nothing here should be re-filed against it.

### D6 — Half the bead ledger is dead workflow machinery, and the share is growing · **DRIFT** · material

**Intent.** `docs/foundation.md` — "Decisions have a home"; the ledger is
the system's memory. A store where half the open records are husks is a
degraded memory.

**Running system, measured 2026-08-22T05:58:29Z:**

```
open beads in the gc-toolkit store        471
carrying gc.step_id or gc.kind=workflow   238   (50.5%)

  mol-polecat-work.implement          29
  mol-polecat-work.preflight-tests    29
  mol-polecat-work.self-review        29
  mol-polecat-work.submit-and-exit    29
  mol-polecat-work.workflow-finalize  29
  mol-polecat-work.workspace-setup    28
  mol-polecat-work.load-context       22
  mol-polecat-work (roots)            15
```

The brief's census, taken earlier the same day, read 385 open / 185 husks
(48%). Re-measured hours later: 471 open / 238 husks (50.5%). **The
absolute count and the share are both rising.**

**Root cause is known and written down.** `specs/tk-y389z/step-close-root-cause.md`.
A graph.v2 step advances only by closing its own bead, and `mol-polecat-work`
contains no close path — so every completed run strands its whole six-step
chain plus a `workflow-finalize` that can never become ready. The fix is
upstream (`mol-polecat-base` in gascity, `mol-polecat-work` in gascity-packs),
which is why it has not landed here.

**Cost, and it compounds.** Husk chains keep their pool routes, so they are
re-offered as work. A polecat that claims one must classify it and de-route
it before it does damage — and a misclassification is destructive, because
`workspace-setup` rebuilds a branch that may be parked under a live review.
This is not hypothetical: **this audit's own session** was handed one first.
Claim `tk-utovj` (root `tk-b7cft`) arrived one minute after its work bead
`tk-voeed` closed as `shipped`, while the re-gate review `tk-ece1s` was in
progress at that branch's head. Executing it would have moved a head under a
live gate. Four husk roots were quiesced (`tk-b7cft`, `tk-e8klu`, `tk-j0ycs`,
`tk-nv6gx`) before real work could be claimed. Every polecat pays this toll,
and the toll grows with the husk count.

### D7 — The three lifecycles are documented; their composition is not · **DRIFT (gap)** · material

**Running system.** Each flow has exactly one fresh owner:

| Flow | Owner | Size |
|---|---|---|
| bead | `docs/work-bead-state-machine.md` | 135 KB |
| PR | `docs/refinery-merge-cadence.md` | 10 KB |
| visit | `docs/gascity-human-engagement.md` | 40 KB |

No document covers how they **compose** — the seam where a bead becomes a
PR becomes a visit and the result propagates back. D5 is a defect sitting on
precisely that seam, and D2 is the same shape in the doc-tracking surface.
`docs/architecture.md:291` ("What is still in transition") is honest and
current but does not name this gap.

**Cost.** The seam is where the expensive failures live, and there is no
document to correct when one is found — so each instance is rediscovered
from the code. Note the constraint on any fix: the three lifecycle docs each
own their subject and must not be restated. The composition seam is a
genuinely new subject; the three lifecycles are not.

---

## What this record does not cover

- **The PR flow was audited only at its seam.** `docs/refinery-merge-cadence.md`
  is fresh and no divergence surfaced against it in the areas this audit
  touched. A dedicated PR-lifecycle audit was not performed.
- **`docs/gascity-agents.md` (72 KB), `docs/gascity-routing-model.md` (113 KB)**
  and the other large implementation docs were not diffed. They are
  downstream of the grounding chain and out of this audit's frame.
- **The remaining `specs/2026-08-fresh-start/` documents** (`live-adoption-findings*.md`,
  `build-factory-trial*.md`, `spine-port.md`, `upstream-contrib-drafts.md`,
  ~2,600 lines) were read for the supersession question only, not diffed
  claim-by-claim.
- **Terminology.** v2 says "turns"; the shipped system says "visits"
  (`formulas/mol-visit.toml`, `assets/scripts/gc-visit-open.sh`). The rename
  appears settled and harmless, and no bead is filed for it.

## Disposition

What this audit filed or closed, and — as important — what it deliberately
did not re-file. Every finding was deduped against the 471 open beads before
acting.

| Finding | Action | Bead |
|---|---|---|
| D1 (+D4 absorbed) | Filed | **`tk-mcyd1`** — stale design-authority citations; the eight sites, v1's missing banner, and v2's stale `gc.attention` clause. D4 absorbed as a second site because the remedy is one sweep. |
| D2 | **Closed with a successor pointer** | `tk-t4rlv` → `gc.superseded_by=tk-gwj51`, kind `folded`, via `assets/scripts/bead-rehome.sh`. Never a bare close. |
| D6 | Filed | **`tk-zab6q`** — husk regrowth past the cleared backlog; the untracked fact is regrowth after `tk-y389z` closed, not the mechanism. |
| D7 | Filed (Deliverable C) | **`tk-wvrga`** — child of `tk-z9nln`; the composition-seam doc plus the `architecture.md` transition-list edit. |
| D3, D4 | **Not filed** | Deliberate substitutions with decision records. Nothing to fix. |
| D5 | **Not re-filed** | `tk-2plde` already owns the seam defect and proposes a shape. This record adds only the generalization that it is one instance of a class hit in four surfaces. |

**Not filed, on purpose.** D6's root cause is adjacent to three open beads
(`tk-3o2ym`, `tk-wi0u1`, `tk-i3fb7`) that cover *different* mechanisms —
`step-close.sh` on the `ready_assignment` tier, and the quiesce sweep's scope.
The new bead names them so a fix agent dedupes rather than rediscovers.

## Deliverable C

The doc-landing work this record implies — one new document for the
bead→PR→visit composition seam (D7), plus naming that seam in
`docs/architecture.md`'s transition list — is deliberately not in this bead.
The composition doc could not be written honestly before this diff existed,
and mixing a many-finding record with an edit to the grounding chain in one PR
makes the review worse. Filed as **`tk-wvrga`**, a child of `tk-z9nln`, and
scoped from the findings that survived the audit rather than from its opening
assumptions — two of which this record overturns.
