---
name: Epic steward — design record (tk-isd5sa)
description: Why the epic steward ships as a gate-only v1 — the continue/shift/close ruling with close terminal and carrying its outcome, the finalize-gate clause, and the I14 invariant — what the operator ruling removed from the first build and why, and what the follow-on epic owns, with the cost of waiting. The authoritative mechanism doc is docs/epic-stewardship.md.
---

# Epic steward — design record

This bead (tk-isd5sa) set out to build the mechanism that gives the city its
tendency to elaborate and advance epics. It ships as a v1 that enforces one
thing: an epic that carries a hypothesis closes only on a recorded close ruling
with its outcome. [docs/epic-stewardship.md](../../docs/epic-stewardship.md)
describes what shipped. This record is why it has that shape, what the first
build carried that v1 does not, and what is deferred.

## Inputs this descends from

- **tk-c5atcz** — the epic contract (docs/epics.md): the five fields and the
  hypothesis-answered closure model.
- **tk-ged0zz** — the survey pre-read: the before-close architecture, and the
  ruling that the mechanism must not ride doctor.
- **tk-xgj2ko** — the membership mechanics, which own membership and its repair
  primitive.
- **tk-089mt7x** — the operator sitting that settled the model and pared this
  bead's PR (#977) to v1, 2026-10-07.
- **tk-yaor8a** — the goal primitive spec, which the sitting folded into the epic
  model.

## What the sitting ruled

The first build of #977 (through 213cb356) was a proactive steward: a rig-scoped
exec order (`orders/epic-steward.toml`, `assets/scripts/epic-steward.sh`) whose
floor, contract and ruling arms filed and retracted operator visits, plus the
gate clause and I14. Its ruling arm counted an epic's `parent-child` children,
filed a visit once every one had closed, and asked for persevere, pivot, or
close; any of the three satisfied the gate. Review kept finding defects in the
proactive arms: arms firing out of contract order, visits never retracted, a
stale persevere satisfying the gate after later units landed, per-pass cost
that starved the tail of the epic list, and a floor visit for every
pre-stewardship epic on first run. The PR then stalled behind a merge conflict.

The sitting settled the model rather than patch the arms:

- The ruling is **continue / shift / close**. continue and shift are non-terminal
  and aim the next body of work; close is terminal and carries its reason or
  outcome. The operator chose this over enumerating complete and abandon,
  because the outcome on the close says which one it was.
- "Every unit landed" is the wrong trigger. Whether an epic is done is decided
  by a ruling at a checkpoint, never by a count.
- The epic is delivered through Features (SAFe's bounded delivery window), each
  followed by an operator-judged Epic Checkpoint whose judge is never the
  worker. "Checkpoint" stays as a family of qualified terms (Epic, PR, Bead
  Checkpoint). The goal primitive folds into the epic.
- v1 is the mechanical close gate, renamed to the new vocabulary, plus the I14
  invariant. The proactive layer comes back as the follow-on epic tk-wmwcdlc,
  after the checkpoint motion is proven by hand.

## Decisions

**v1 is enforcement only.** The order, the driver, its three arms and their
tests are removed. `doctor/check-cadence-live` reads `orders/*.toml` by glob, so
removing the order needed no change there. Nothing in v1 files a visit about an
epic; the operator calls the sitting.

**Only close releases an epic, and close carries its outcome.** The approved v1
item read "an epic can't close without a close ruling + reason". The gate runs
before the close, so it can read only what is already on the bead. The outcome
is therefore recorded with the ruling as `epic_ruling_reason`, rather than left
to bd's close reason, which the close itself writes. Each ruling overwrites
`epic_ruling` and `epic_ruling_reason`, so a continue recorded at an earlier
sitting never stands in for a later close. A reason of whitespace alone counts
as absent.

**One predicate, two readers.** `finalize-gate.sh clause_epic_ruling_recorded`
and `doctor/check-epic-closed-implies-ruled` apply the same predicate: an epic
that carries a hypothesis, is not disposed, and is not ruled close with an
outcome is held (gate) or is an error once closed (I14). A continue or shift
ruling and an off-enum value each get their own message. Each reader's test
pins the predicate, and a mutant that accepts continue or shift, or drops the
outcome, fails in both suites. The steward script carried a third copy of the
enum, which left with it.

**The clause holds no close path wired today; I14 is the enforcement that sees
every close.** Review of #977 (thread on finalize-gate.sh:176) showed that
neither gate-running path reaches an undisposed epic. `merge.sh` finalizes merge
anchors, and `bead-rehome.sh` stamps `gc.superseded_by` before it gates, which
the clause exempts. The exemption is intended: the operator's directive names
"a stewarded epic (carries a hypothesis, not disposed)". So the clause stays as
the precondition a gate-running close of an epic inherits, with the checkpoint
layer's close path the expected first one, and no doc claims it holds
bead-rehome. Its cost is one `gc bd show` per finalize, failing closed like the
visit clause's two probes. Taking the bead's type from the caller would save
that read, but it widens the gate's interface across merge.sh, its gctk port,
and bead-rehome.sh, which v1 leaves alone.

**The gate reads past the refinery's `bd_list` cache.** Moving the visit clause
onto bd-lib's readers, so the `gc bd:` notice strip lives in one place, put its
`gc.continuation_group` probe behind `GC_RECONCILE_BD_CACHE`, which a refinery
pass exports to merge.sh. merge.sh's terminal re-assert then read its first
check's rows and could pass a visit filed between the two. `finalize_gate_check`
now runs every clause with the cache off (`local GC_RECONCILE_BD_CACHE=""`), and
finalize-gate.test.sh case 26 reproduces the stale re-assert, failing without
the fix.

**I14's remedy is bd's.** `lifecycle.sh reopen` refuses a closed bead with no
`merge_result`, which is every epic. The finding now names the write that clears
it (record `epic_ruling=close` and `epic_ruling_reason` on the closed epic) and
bd's own reopen for an epic that should go on.

**`single-flight.sh` is not extracted.** The extraction existed so
refinery-reconcile.sh and epic-steward.sh shared one lock implementation. With
the steward removed it had one consumer, so refinery-reconcile.sh keeps main's
own lock and v1 does not touch the merge cadence.

**Kept from the first build.** Bare `epic_*` metadata keys registered in
lifecycle/lifecycle.toml `[metadata.epic_stewardship]`, now with
`epic_ruling_reason`; bd-lib.sh's strip of the `gc bd:` notice line in
`bd_json` and `bd_list`, and `bd_json`'s stdin guard, which the gate reads
through; the harness's `STUB_SHOW_NOTICE`.

**There is no automatic transition to intercept.** No parent→child close cascade
exists for `parent-child` edges (merge.sh closes only the merged anchor;
lifecycle.sh has no cascade; bd enforces the opposite, an open-children hold).
The only native auto-close is convoy-scoped and cannot fire on an
`issue_type=epic`. So epics.md's "never a last-unit auto-close" is a guardrail
against building one, and an epic reaches closed only through an explicit act.

## Deferred, with cost

Tracked:

- **The Feature and Epic Checkpoint layer** — tk-wmwcdlc, the follow-on epic,
  blocked by this bead. It builds the Feature level, the formula that prepares
  and files the operator-judged checkpoint sitting after a Feature lands, and
  the goals consolidation: measured and graded criteria and the anti-gaming
  invariant in the epic contract, with specs/tk-yaor8a retired as a separate
  primitive. docs/epics.md states the model as direction. Cost while deferred:
  nothing prompts a ruling. An epic whose work has landed waits for the operator
  to call a sitting, so an answered or stalled epic stays open until someone
  looks. The close requirement holds meanwhile, through I14.
- **Membership scope-reading audit** — tk-lt585p, blocked on the repair
  primitive tk-8bzuc2 and on a scope classification that is LLM judgment. It was
  framed as a fourth steward arm in epic-steward.sh; with that script removed,
  its home is decided when it unblocks. Cost: misfiled work is not swept, and
  membership drifts as work is filed.

The first build also recorded three scope boundaries of its cadence: an exact
create-time audit, an LLM drafting arm, and city scope. They were properties of
the removed order, and the checkpoint layer decides them afresh.

## Follow-on beads

- tk-wmwcdlc — the Feature and Epic Checkpoint layer (filed by sitting
  tk-089mt7x).
- tk-lt585p — the membership audit; its notes record that the steward it would
  have extended is gone.
- tk-td0fpz — doctor-check-count drift in docs/architecture.md and
  docs/component-model.md, found while adding I14 and left out of scope.
