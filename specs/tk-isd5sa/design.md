---
name: Epic steward — design record (tk-isd5sa)
description: The design decisions behind the epic-steward order and driver — why an exec order, rig scope, bare metadata keys, the visit-workflow placement, and the three-layer before-close enforcement — plus the arms deferred to follow-on beads and the cost of waiting. The authoritative mechanism doc is docs/epic-stewardship.md.
---

# Epic steward — design record

This bead (tk-isd5sa) built the epic steward: the mechanism that gives the city
its tendency to elaborate and advance epics. It is the central audit the epic
decomposition named — "the central audit that runs on create and on a queued
schedule" (specs/tk-xgj2ko/membership-mechanics.md). The authoritative
description of what shipped is [docs/epic-stewardship.md](../../docs/epic-stewardship.md);
this record is why it is shaped the way it is, and what it deliberately left for
later.

## Inputs this descends from

- **tk-c5atcz** — the epic contract (docs/epics.md). The five fields and the
  hypothesis-answered closure model are what the steward reads and enforces.
- **tk-ged0zz** — the survey pre-read. Its two maps settled the shape: the
  before-close architecture (where closure validation hooks into the existing
  machinery) and the stewardship-of-X pattern (audit-on-create, queued re-audit,
  sling forward), with the ruling that the mechanism must not ride doctor.
- **tk-xgj2ko** — the membership mechanics. It defines membership and the repair
  primitive the deferred membership arm will call; this unit builds the audit,
  not a second definition.

## Decisions

**An exec order, not a judgment formula.** A pass is an enumeration, a set of
metadata-presence gates, and a deduped visit per owed decision — no LLM judgment
runs in the pass. The judgment an epic needs (drafting a hypothesis, ruling on
it) is the operator's, surfaced at the visit. This matches deferred-dispatch's
stance ("one bd list + one sling … needs no LLM") and keeps the steward cheap
enough to run often. Generating the draft itself (an LLM arm) is deferred, not
designed in.

**scope=rig.** An epic is a durable per-rig anchor (services/helm), so one
registration, store and clock per importing rig, each reading its own epics —
the same scope the refinery runs at. The survey speculated city scope; the epic
model is per-rig, so rig scope is correct until epics are shown to cross rigs.

**Cadence is a heartbeat.** Every arm is idempotent and every visit is deduped by
(epic, concern) and retracted when the concern clears, so a frequent pass
re-files nothing. Frequency only shortens how long a new epic waits for its first
audit — the create-time half. A short interval (1h default, tunable) approximates
"audit on create" without a separate create-time trigger; the exact create-time
arm is deferred (below).

**Bare `epic_*` metadata keys.** The contract fields are recorded as bare keys
(`epic_hypothesis`, `epic_ruling`, …), matching the refinery's bare
managed-domain convention (`merge_result`, `check_set`, `pr_posture`) rather than
the `gc.`-prefixed runtime/routing namespace. Registered in
lifecycle/lifecycle.toml `[metadata.epic_stewardship]` per the "a metadata key is
state" rule (component-model.md). They are the operator's to ratify — no pack
script writes them — so the steward reads a floor/ruling the operator stamped.

**Placed in the visit workflow (component-model.md §4).** The steward's product
is the operator decisions an epic owes, surfaced as visits; it is the per-epic
analog of first-reaction's per-bead intake, which also sits in visit. The
cadence/order shape rhymes with the patrol orders (convoy-check, liveness-sweep)
and the refinery, but placement follows product, not mechanism, and the product
is operator decisions — visit. This is the placement worth arguing about; a
reviewer who reads the product as "fleet/structure health" would move it to
patrol.

## The before-close enforcement, and why three layers

The survey asked where epic validate-before-close hooks in. The load-bearing
finding, derived by reading the close paths rather than inheriting the contract's
wording: **there is no automatic transition to intercept.** No parent→child close
cascade exists for `parent-child` edges (merge.sh closes only the merged anchor;
lifecycle.sh has no cascade; bd enforces the opposite, an open-children hold). The
only native auto-close is convoy-scoped (it walks `gc.input_convoy_id` /
workflow roots) and structurally cannot fire on an `issue_type=epic`. So
epics.md's "never a last-unit auto-close" is a guardrail against building one, and
an epic reaches closed only through an explicit act.

finalize-gate.sh is wired into only merge.sh and bead-rehome.sh, so a clause
there catches the disposition close but not a bare `gc bd close` or a lifecycle
transition. No single layer covers every close, so enforcement is three layers:

1. The steward's ruling visit surfaces the decision to the operator (who performs
   the close) and holds the gate via its tracks edge.
2. `clause_epic_ruling_recorded` in finalize-gate.sh refuses the gate-running
   close paths.
3. `doctor/check-epic-closed-implies-ruled` (I14) is the after-the-fact backstop
   for any path that bypasses the gate.

## Deferred, with cost

Each deferred piece is tracked; none is dropped. The deliverable that shipped is
the running mechanism (floor, contract, ruling arms + the before-close trio); the
pieces below extend it.

- **Membership scope-reading arm** — the fourth arm (re-home work that drifted
  outside its epic). Blocked on the repair primitive **tk-8bzuc2** (re-parent a
  bead, refusing a cascade-unsafe re-parent) and on a scope classification the
  shell pass cannot do (which sibling belongs under which epic is LLM judgment).
  Filed as a follow-on bead. Cost while deferred: misfiled work is not swept and
  membership drifts as work is filed — the same cost the membership spec records
  for this audit.
- **Exact create-time audit** — a first-reaction-style arm that reacts the moment
  an epic is filed, rather than on the next cadence tick. Cost while deferred: a
  new epic waits up to one interval for its first audit; the field data
  (tk-xgj2ko notes) also shows coordination roles file epics directly, bypassing
  first-reaction, so the periodic audit is the robust backstop regardless.
- **LLM drafting arm** — generate the proposed hypothesis/closure draft for the
  operator to ratify, rather than asking the operator to draft it. Cost while
  deferred: the visit asks the operator to write the floor rather than editing a
  proposed one; the elaboration still happens, with more operator effort.
- **City scope** — if epics are ever shown to span rigs. Cost while deferred:
  none today; epics are per-rig.

## Follow-on beads filed

- Membership scope-reading arm (blocked on tk-8bzuc2).
- A doctor-check-count drift in docs/architecture.md and docs/component-model.md
  (prose predating the current 23→24 check count), found while adding I14; left
  untouched here as out of scope.
