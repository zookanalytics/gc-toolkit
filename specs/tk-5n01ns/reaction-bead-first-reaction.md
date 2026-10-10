---
name: reaction-bead first-reaction dispatch
description: The design of the reaction-bead model — a first reaction is its own leased task bead R that tracks the subject S — and how it replaces the mol-first-reaction / subject-metadata dispatch. Read this to understand why a reaction is a bead, how exactly-once rides the substrate, what each of the five dispositions writes back to S, and how the model composed with the first-reaction work that landed on main while it was in review.
---

# Reaction-bead first-reaction dispatch

A first reaction is inbox triage: read a freshly-filed bead S once, sort it into
one of five dispositions, and dispatch accordingly. This document describes the
model in which the triage is itself a work bead.

## The problem this removes

The substrate already runs work exactly-once: a bead is claimed under a lease,
worked, and closed, and the claim CAS plus the lease make a second worker
impossible. A first reaction could not use that guarantee, because triage ends
by handing the subject S *back* alive — routed to a pool, held on an edge, handed
to a validating closer, or put to a human — not by closing it. A disposition that
leaves its subject open cannot lean on close-means-done, so the prior model
hand-rolled a done-marker on S instead: a metadata stamp written around the
disposition act, whose presence a guard read to refuse a second reaction.

Getting that marker's timing right across a crash was the entire bug class. The
marker written *before* the act records only an attempt, so a guard keyed on it
deadlocks a partial disposition — it refuses to re-run and cannot complete. The
marker written *after* the act leaves a window where the disposition landed but
the proof did not, so a re-run re-disposes. Both the subject-metadata design
(`gc.first_reaction` + `gc.proactive_reaction`) and its rework
(`gc.first_reaction_landed`) carried this class; the second only renamed the
marker.

## The model: a reaction is a bead

Model the triage as its own work bead **R** — a plain `task`, not a workflow.
R is created once per subject S, tracks S, and is routed to the proactive pool.
R is claimed, leased, retried, and closed by the ordinary work lifecycle, so
exactly-once is the substrate's and **R's identity is the idempotency key**. A
worker that dies mid-triage lets R's lease lapse; R is re-offered and
re-claimed; nothing is hand-rolled.

- **R is a plain task.** No poured formula, no step beads, no
  `workflow-finalize`, no drain choreography. The proactive prompt is the
  method.
- **R tracks S.** The link is a `tracks` dependency edge `R --tracks--> S`,
  never `parent-child`. Only `parent-child` cascades the subject's `is_blocked`
  flag; a subject awaiting a first reaction is frequently blocked or held, and a
  parent-child child would inherit that block and never reach `bd ready` —
  unclaimable exactly when the reaction is owed. `tracks` records lineage and
  gates nothing, so R stays independently claimable. This is the same edge a
  converse visit uses to track its subject.
- **S stays clean until R dispatches it.** At intake S carries no reaction
  metadata and no route; R carries its own route. The un-clearable-execution-route
  pain of pouring a workflow onto a bead that is not that workflow's work never
  arises, because the workflow (such as it is) lives on R.

### Lifecycle

1. **Create (once per S).** `gc-proactive.sh` scan/sling finds a movable-forward
   subject S. Before creating anything it proves S present in the store its id
   prefix names (`bead-store.sh --present`), because R's worker reads S and
   writes the disposition back to it, so an R whose subject is missing is work
   nobody can dispose. A subject that is absent, or that its store gives no
   verdict on, fails the sling with an error, and nothing is filed. The sling
   then checks that no live owner owns S's reaction (`gc.reaction_owned`), that
   no open reaction already tracks S (the dedup below), and that no live
   workflow already drives S. It then creates R, stamps it, and wires the
   tracks edge. S is untouched.
2. **Claim.** A proactive pool worker claims R through `gc hook --claim` — the
   substrate CAS. The claim stamps R's lease (`gc.claimed_at`,
   `lease_expires_at`). R, not S, is the claimed work.
3. **React.** The worker resolves S from R, reads S and its universe slice,
   writes the first-reaction card into S's notes, and takes exactly one of five
   dispositions — the write-back to S.
4. **Close R.** After the write-back lands, `first-reaction-dispose.sh` closes R
   (`gc.outcome=reacted`, `gc.work_outcome=no-op`: R's work is a card and a
   disposition, never a commit). The reaction is complete; the substrate records
   it done.

### Create-R-once (the dedup)

Exactly-once for the *reaction* is the substrate's, but exactly-once for
*creating R* is not — two scan passes could each mint an R for the same S. The
dedup is at create time, keyed on **subject + kind**: before creating R for S,
`gc-proactive.sh` refuses if an open or in-progress bead with
`task_kind=reaction` already tracks S (matched by either `gc.reaction_subject=S`
or a `tracks` edge to S, since a visit records its subject twice and only the
edge has proved reliable). One open reaction per subject. A store that cannot
answer the edge lookup is not proof of absence: the sling fails closed with an
error, not a skip.

The dedup keys on `task_kind=reaction`, not on any marker on S, so it holds
while S is still scan-eligible — which S remains until the reaction's write-back
lands (S is unchanged between R's creation and R's disposition). Once the
write-back lands, S is no longer scan-eligible on its own terms (routed, held on
an edge or a gate, driven by a closer, and carrying the reaction's takeaway), so
no further reaction is minted. A deliberate re-reaction ("it has been a week,
look again") is simply a new R filed against an S that has become eligible
again; the dedup does not forbid it, because it keys on *open* reactions, not on
history.

## The five dispositions: the write-back to S

Each disposition is R's write-back to S, performed by
`assets/scripts/first-reaction-dispose.sh`. No disposition closes S: a first
reaction runs on a cheap model and never has the last word on a close. The card
in S's notes is the record of what was chosen and why.

| Disposition | S becomes | Act |
|---|---|---|
| **actionable** | routed to a pool | release S to the pool (`gc.routed_to`); the card is the dispatch note |
| **recommend** | held on a human gate, with an action to Accept | stamp `gc.recommended_formula`, file the gate (`gc-helm.sh demand`, topic `first-reaction`), hold S on it |
| **blocked** | held on a `blocks` edge | wire the edge to the blocker; optionally arm a deferred dispatch for when it clears |
| **close** | driven by the validating closer | append the close brief to S's notes, sling `mol-validate-close` at S |
| **ruling** | held on a human gate, Discuss-only | file the gate, hold S on it |

`gc.origin=operator` does not decide the exit: an operator capture is triaged on
its merits, and the guardrail that a fork, an irreversible action, or a policy
call reaches a human lives in the reacting agent's rubric. The gate is the
escalation's state; `orders/gate-visit-sweep` files the visit that resolves it.

A confident "nothing to do" — already fixed, a duplicate, fixed upstream, or a
bead that should not exist — is the **close** disposition. The validating closer
re-checks the close brief against live state and closes S on its own confident
check, or leaves S open and files a visit. A close that needs a successor
pointer is the operator's, through `bead-rehome.sh`.

### The completion marker and the residual window

Cross-bead atomicity — dispatch S *and* close R in one transaction — is not
available at the beads layer, so the window between the write-back to S and the
close of R persists. In this model that window is a self-healing no-op, not a
deadlock.

The last write of each disposition stamps `gc.reacted_by=<R-id>` on S — after
the edge or the arm, so it stays completion-marker-last. On re-claim (the worker
died in the window, R's lease lapsed, R is re-offered), the worker reads S: if
`gc.reacted_by` names this R, the write-back already landed, so it closes R and
touches S no further. S is never re-dispatched, and never yanked from a
downstream worker that has since claimed a routed S.

`gc.reacted_by` is not the old machinery reborn. Correctness does not rest on
it: the write-backs are idempotent (routing S to the same pool is a no-op, an
edge is deduplicated, the gate is refreshed under its topic rather than filed
twice, and a closer slung again is refused by `gc sling` as a live-workflow
conflict, which the close exit reads as the closer already slung), so a re-run
without the marker is safe — the marker only spares the redundant work and
protects a claimed S. No guard refuses progress on its presence, so no partial
state can deadlock. And it is keyed to R's identity, so a marker left by a closed
R does not suppress a later, deliberate re-reaction by a different R.

## bead-rehome.sh: the one close-with-successor writer

`bead-rehome.sh` closes a bead with a legible successor pointer
(`gc.superseded_by` + `gc.superseded_by_store`), and it is the single writer for
that act across every actor: converse dispositions, operator re-homes,
`pr-facts.sh` consummating a pre-recorded PR-close disposition, and
`duplicate-sweep.sh` closing a marked duplicate or a never-dispatched rework
twin. It gates its own evidence rather than trusting the caller.

- `--check` evaluates the gates and writes nothing (exit 0 eligible, non-zero
  refused).
- Every kind: the origin is not a review bead, not a step bead or workflow root,
  and is not held in progress by another session.
- `fixed-upstream` / `duplicate`, the kinds that claim the origin's work is
  already delivered elsewhere: the successor is in the same store and is closed
  or `work_outcome=shipped`, and the origin did no work (`work_outcome=no-op`, or
  no work-product key set at all, so an origin with unlanded work is refused). An
  origin carrying the operator's pre-recorded PR-close disposition for that kind
  and successor (`pr-dispose.sh`) is a ruling already made, read from the store,
  and these gates do not re-judge it.
- `re-homed`, `folded`, `not-needed` are a person's call: a non-closed
  `merge_result` does not bar them, because the converse retire path disposes an
  in-flight anchor through this writer on the operator's ruling.
- The pointer is stamped and read back before the close; a close is gated on the
  read-back, not the write's exit status. The close is deliberately not
  `--force`, so a refusal leaves an open, pointed, findable bead rather than a
  silent drop.

## What this replaces

- **`formulas/mol-first-reaction.toml`** is retired. A reaction is no longer a
  poured graph.v2 workflow with an input convoy and per-step closes; it is a
  plain bead R. In-flight molecules poured before the cutover complete on their
  frozen step descriptions (§ Cutover).
- **The subject-metadata attempt record** — `gc.first_reaction`,
  `gc.first_reaction_reason`, `gc.first_reaction_target`, `gc.first_reaction_at`
  — is retired. `first-reaction-dispose.sh` no longer writes it, and
  `gc-helm.sh`'s `takeaway --release` no longer stamps or reads back
  `gc.proactive_reaction`. The reaction-bead path's completion proof is
  `gc.reacted_by`; `gc.proactive_reaction` survives only on the frozen
  no-`--reaction-bead` path (§ Cutover). The validating closer reads its brief
  from S's notes, and falls back to `gc.first_reaction_reason` for a reaction that
  ran before reaction beads. The retired keys stay registered in
  `lifecycle/lifecycle.toml` so residue on an older bead reads as known, and
  `bead-context.sh` still shows an older subject's `gc.first_reaction*` record.

## Cutover

The cutover is one PR, not a two-phase interim. Two facts keep it safe:

- **In-flight `mol-first-reaction` molecules complete on frozen steps.** A step
  bead's description is frozen at pour, so retiring the formula file does not
  strand a molecule already running; its `advance-and-drain` step still calls
  `first-reaction-dispose.sh`.
- **`first-reaction-dispose.sh` stays backward-compatible.** Called without
  `--reaction-bead` (the frozen invocation), it performs the same write-back on
  the claimed subject, the close exit's `--after-workflow` deferral included, and
  closes no R. With no R to key exactly-once on, it stamps the legacy landed proof
  `gc.proactive_reaction=1` after the act, in place of `gc.reacted_by`. The frozen
  `advance-and-drain` molecule reads that proof two ways — its own REACTED checks
  and this script's re-offer guard — so a re-offered frozen step stops before the
  act rather than re-releasing (reopening, unassigning, re-routing) a subject a
  downstream worker has already claimed. That release is not idempotent, which is
  why the frozen path keeps a landed proof rather than relying on the step chain
  alone; the proof is retained until pre-cutover molecules drain.

Newly-scanned subjects take the reaction-bead path from the moment the PR lands.
The scheduled `scan --sling` order (`orders/proactive-scan-sling.toml`) calls the
same entry point, so it files reaction beads too.

## Composition with the first-reaction work that landed on main

This branch was ruled on 2026-09-18 and stayed in review while main's
first-reaction work kept landing. Bringing it current composed the two. Each
clash was decided by the later, more specific ruling, and a retirement whose
premise no longer held was left to the operator:

- **Five exits, not four.** Main added `recommend` (Accept/Discuss), `close`
  (the validating closer), and a native human gate for `ruling` and `recommend`
  (gate adoption Part A). They change what a reaction decides, an axis this
  branch does not touch, so they carry over as R's write-back.
- **No `superseded` exit.** The operator's 2026-09-19 ruling (tk-mw3bso) is that
  a first reaction must not itself resolve or close a bead. The branch's
  `superseded` exit closed S through `bead-rehome.sh`, so it gave way to
  `close`, which hands S to the validating closer.
- **Operator-origin triage on merits.** The same ruling removed the
  `gc.origin=operator` gate; the branch's copy of it went.
- **`bead-rehome.sh`'s gates scoped by kind.** The branch's every-kind
  unlanded-work gate refused three callers that act on an operator's ruling:
  `pr-facts.sh` consummating a pre-recorded PR-close disposition (an anchor at
  `merge_result=pull_request`, under any kind, `duplicate` included), the
  converse retire path, and an abandoned anchor, for which `pr-dispose.sh` names
  `bead-rehome.sh` as the verb. The evidence gates now apply to the kinds that
  claim delivered work, and a recorded PR-close disposition satisfies them.
- **`duplicate-sweep.sh` and the `duplicate_of` marker stay.** The 2026-09-18
  ruling folded their retirement into this branch on the premise that no bead
  carried the marker. That premise no longer held when the branch was brought
  current: five open beads carried `duplicate_of`, each parked on a successor
  still open and each waiting on the sweep's marker pass to close it once that
  successor lands. Retiring the pass would strand them, so both passes stay, and
  retiring the marker is left to the operator. Main's never-dispatched
  rework-twin pass (tk-p2frq5) now stamps `gc.work_outcome=no-op` on the twin
  before the close. `bead-rehome.sh`'s duplicate evidence accepts that stamp
  beside the work-order branch the twin carries, and `pr-stack.sh` reads it to
  keep the twin off the branch's bead list, so the twin pass no longer stamps
  `duplicate_of` after the close.
- **Scan and sling guards.** Main's guards — standing kinds, dispatch paths,
  live workflows, `gc.reaction_owned`, a fail-closed rig — gate filing R exactly
  as they gated pouring the formula.
- **The scan's step clause.** Main later gave the scan a step clause of its
  own, keyed on `gc.step_ref` alone. The scan keeps this branch's wider clause,
  which also drops a bead carrying `gc.step_id` or `gc.root_bead_id`, the same
  keys demand and the pool queries drop on. Main's step cases in
  `tools/gc-proactive.test.sh` carry over, and its sweep case expects the
  reaction-bead dry-run line.

## Metadata

On R (the reaction bead):

| Key | Meaning |
|---|---|
| `task_kind=reaction` | R is a reaction bead — the dedup and pool-query key |
| `gc.reaction_subject` (+ `_store`) | the subject S this reaction tracks |
| `gc.reaction_kind` | the reaction sub-type, `first-reaction` |
| `gc.routed_to` | the proactive pool that claims R |
| `gc.outcome=reacted`, `gc.work_outcome=no-op` | stamped as R closes |

On S (written by the write-back):

| Key | Meaning |
|---|---|
| `gc.reacted_by` | the reaction R whose write-back landed — the residual-window self-heal |
| `gc.recommended_formula` | the mol a `recommend` names for the operator's Accept |
| `gc.proactive_reaction` | `1`, the legacy landed proof the frozen no-R path stamps in place of `gc.reacted_by` |

Retired (no writer; registered as residue): `gc.first_reaction`,
`gc.first_reaction_reason`, `gc.first_reaction_target`, `gc.first_reaction_at`.
Kept: `gc.proactive` (the standing scan opt-in), `gc.reaction_owned` (a live
owner's stand-down marker), `gc.superseded_by` / `_store` and `gc.supersedes` /
`_store` (the rehome pointers), `duplicate_of` / `_store` (the hand-stamped
duplicate marker `duplicate-sweep.sh` reads), `gc.blocker_key`.

## Implementation surface

- `tools/gc-proactive.sh` — `cmd_sling` creates R and wires the tracks edge
  instead of pouring a formula; `subject_present_guard` refuses a subject its
  own store does not prove present; `reaction_absent_guard` refuses a
  live-owned subject and dedups on `(task_kind=reaction, subject)`;
  `scan_precision_filter` drops topology roots and step beads from the scan, and
  `exclude_graph_structural` drops them from demand by the same keys.
- `agents/proactive/prompt.template.md` — the reaction method: claim R, resolve
  S, stand down on `gc.reacted_by=R` or `gc.reaction_owned`, card, one of five
  exits, close R.
- `agents/proactive/agent.toml` — the pool `work_query` / `scale_check` claim
  routed reaction beads and exclude graph-structural beads.
- `assets/scripts/first-reaction-dispose.sh` — the five-exit write-back, the
  `gc.reacted_by` marker, the close-R step, and the backward-compatible
  no-`--reaction-bead` arm that stamps and guards on the legacy
  `gc.proactive_reaction` landed proof for frozen molecules.
- `assets/scripts/bead-rehome.sh` — the single evidence-gated
  close-with-successor writer with `--check` and the kind-scoped gates.
- `assets/scripts/duplicate-sweep.sh` — the rework-twin pass records
  `gc.work_outcome=no-op` on a twin before its close; the marker pass is
  unchanged.
- `formulas/mol-validate-close.toml` — reads the close brief from S's notes.
- `assets/scripts/gc-helm.sh` — `takeaway --release` no longer stamps or reads
  back `gc.proactive_reaction`.
- Retired: `formulas/mol-first-reaction.toml` and the tests of its step text.
- `lifecycle/lifecycle.toml` — the metadata registry gains the reaction keys and
  marks the retired ones.
- Docs reconciled: `docs/authority-map.md`, `docs/component-model.md`,
  `docs/state-machine.md`, `docs/gascity-human-engagement.md`,
  `docs/refinery-merge-cadence.md`, `agents/proactive/PROVENANCE.md`, and the
  converse prompt.
