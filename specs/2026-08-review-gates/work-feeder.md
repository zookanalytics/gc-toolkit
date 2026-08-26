---
name: Work feeder — triage on the filing side
description: The design for what converts a ready bead into a dispatch — eligibility, who decides, and at what cadence — built as the filing-side twin of the review triage gate rather than as a cadence arm that slings whatever is ready. Designed 2026-08-26 under tk-xhwits; the review-gates half of that bead is implemented, this half is not.
---

# Work feeder: triage on the filing side

Status: **designed, not implemented.** Filed from the rewrite cutover runbook
(step 9 item 11, carried from PR #464) and folded into the review-gates scope
because the runbook is explicit that the feeder is a triage-design decision,
not a bolt-on cadence arm.

## The evidence

Nothing in the city converts a ready bead into a dispatch. `gc sling` routes
a bead when a human or an agent decides to. `deferred-dispatch.sh` routes a
bead whose blockers have closed, but only one that was explicitly armed with
`gc.dispatch_when_ready`. A bead filed with neither just sits. At the count
recorded in the runbook: 252 ready-but-unrouted beads, the oldest 123 days
old.

## Why not an arm that slings what is ready

The one-line fix is an order that routes every ready unrouted bead to the
polecat pool. It fails three ways, and each failure names a piece the real
design needs:

1. **No admission control.** Routed unclaimed work IS demand — the runtime
   spawns a session to meet it with no operator keystroke. Routing 252 beads
   routes 252 sessions' worth of demand.
2. **No eligibility judgment.** A bead that has been ready for 123 days is
   more likely stale, superseded, duplicated, or premised on something that
   has since changed than it is ready-and-valuable. Dispatching it sends a
   polecat to redo or re-derive work that already moved.
3. **No owner for the decision.** "Should this be worked now" is a
   classification, and the pack already has a shape for one: a declared
   table, a small-context session that classifies over it, and a recorded
   justification per decision. A second, differently-shaped mechanism for the
   same question is the drift the component model rejects.

## The design

The filing-side twin of the review triage gate, sharing its contract:

| | Review triage | Work feeder |
|---|---|---|
| Declared table | the gate menu in `docs/review-charter.md` | the eligibility table (below) |
| Classifier | a review-pool session running `skills/review-triage` | a session running `skills/work-triage` |
| Decision recorded as | `check_set` widening + `triage-add:` notes | a route stamp + `feed-*:` notes |
| Human door | `escalate.sh`, one visit per situation key | the same |
| Rate watched by | the feedback distiller (add-rate, waiver-rate) | the same (dispatch-rate, retire-rate) |

### 1. What makes a ready bead eligible

Two stages, because the cheap mechanical filter must not be the judgment.

**Candidate** — the order's predicate, mechanical and total:

- `status = open`, no assignee, `gc.routed_to` empty or absent;
- not blocked: no open `blocks` or `parent-child` ancestor;
- not an anchor (`merge_result` absent) — anchors belong to the merge cadence;
- not a step bead, convoy, visit, warrant, or observation (`gc.kind` /
  `task_kind` filters), and not a wisp;
- no feeder decision already recorded on it since its last update.

**Eligible** — the classifier's judgment, one question per row:

| Test | Fails when | Outcome |
|---|---|---|
| Actionable | the bead states no done condition — it is a note, a question, or a link with no ask | escalate: it is a conversation, not work |
| Current | its premise no longer holds; the cited file, behavior, or defect has moved or been fixed | retire |
| Unduplicated | an open peer bead or an in-flight PR already covers it | retire, naming the survivor |
| Sized | it is an epic, not one unit a session can finish | defer, with a note that it needs splitting into a convoy |
| Routable | no pool can do it (missing capability, wrong rig) | escalate |

A bead passing all five is dispatched. The expected shape of a 123-day
backlog is that most of it retires or defers; draining it is as much of the
feeder's job as feeding from it.

### 2. Who decides

A pool session running a `work-triage` method skill, dispatched by the order.
Not the order itself, and not a patrol agent deciding inline: the judgment
needs to read the bead, the repo, and the ledger, and it must land in one
contained, reviewable, auditable place — the same reason the review triage
gate is a session rather than a predicate.

Each decision is one recorded line on the bead, in the convention the review
side already uses:

```
feed-dispatch: <pool> @<date> — <why now>
feed-defer:    <condition> @<date> — <what must change first>
feed-retire:   <survivor-or-reason> @<date> — <what falsified it>
```

Dispatch **stamps** `gc.routed_to` rather than slinging, so the pool's own
demand offers the work — the rule `signoff.sh`'s rework path already follows.
A retire that is a judgment call rather than a fact routes to a human through
`escalate.sh` instead of closing.

### 3. Cadence and ceiling

- One cooldown order per rig, on the order of ten minutes. The backlog is
  months old; the cadence is not the constraint.
- **The ceiling is the load-bearing part.** Each pass dispatches a classifier
  only while routed-but-unclaimed work for the target pool is under a WIP
  limit. The feeder then feeds the pool exactly as fast as the pool drains,
  and the 252-bead flood cannot happen whatever the backlog size.
- One classifier session per pass, handed a small batch (order of ten)
  **oldest-first**, so the long tail drains instead of being starved by newer
  arrivals.
- The human queue is bounded by `escalate.sh`'s one-open-visit-per-key dedup,
  which is already how every other escalation is rate-limited.

## What this design does not do

- It never closes a bead without a recorded reason on the bead.
- It never slings; it stamps a route.
- It does not order work beyond oldest-first. A priority model is a separate
  decision, and guessing one here would bury it in an implementation.

## Implementation inventory

| # | Artifact | Change |
|---|---|---|
| 1 | the eligibility table | Declared in a parseable form, like the gate menu — so the doctor clause and the skill read one source. |
| 2 | `skills/work-triage/SKILL.md` | The method: the five tests, the four outcomes, the note conventions, the escalation shape. |
| 3 | `assets/scripts/work-feeder.sh` | The candidate query, the WIP ceiling, one classifier dispatch per pass. |
| 4 | `orders/work-feeder.toml` | Cooldown order, `scope = "rig"`, like `refinery-reconcile.toml`. |
| 5 | doctor clause | Ready-and-unrouted past N days with no recorded feeder decision — the backstop for a feeder that stops firing. |
| 6 | Tests | Cases in the suites the above touch; the pack has no test auto-discovery, so a new suite file is a test nobody runs. |

## Open at implementation

- **Where the eligibility table lives.** `docs/review-charter.md`'s mandate is
  what a reviewer holds a diff against; work eligibility has a different
  reader and a different question. A separate declared table, cross-linked,
  is the better fit — but it is one more charter to keep true.
- **Which pool classifies.** Reusing the review pool keeps one small-context
  role; a dedicated pool keeps the merge cadence's reviewers uncontended.
- **Retirement authority.** Which outcomes a classifier may close directly
  and which must become a visit. Closing another agent's filed bead is the
  decision most likely to be wrong, and the cheapest to make reversible.
