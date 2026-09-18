---
name: reaction-bead first-reaction dispatch
description: The design of the reaction-bead model — a first reaction is its own leased task bead R that tracks the subject S — and how it replaces the mol-first-reaction / subject-metadata dispatch. Read this to understand why a reaction is a bead, how exactly-once rides the substrate, and what each disposition writes back to S.
---

# Reaction-bead first-reaction dispatch

A first reaction is inbox triage: read a freshly-filed bead S once, sort it into
one of four dispositions, and dispatch accordingly. This document describes the
model in which the triage is itself a work bead.

## The problem this removes

The substrate already runs work exactly-once: a bead is claimed under a lease,
worked, and closed, and the claim CAS plus the lease make a second worker
impossible. A first reaction could not use that guarantee, because triage ends
by handing the subject S *back* alive — routed to a pool, held on an edge, or
put to a human — not by closing it. A disposition that leaves its subject
open cannot lean on close-means-done, so the prior model hand-rolled a
done-marker on S instead: a metadata stamp written around the disposition act,
whose presence a guard read to refuse a second reaction.

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
   subject S, and before creating anything checks that no open reaction already
   tracks S (the dedup below). It then creates R, stamps it, and wires the
   tracks edge. S is untouched.
2. **Claim.** A proactive pool worker claims R through `gc hook --claim` — the
   substrate CAS. The claim stamps R's lease (`gc.claimed_at`,
   `lease_expires_at`). R, not S, is the claimed work.
3. **React.** The worker resolves S from R, reads S and its universe slice,
   writes the first-reaction card, and takes exactly one of four dispositions —
   the write-back to S.
4. **Close R.** After the write-back lands, the worker closes R. The reaction is
   complete; the substrate records it done.

### Create-R-once (the dedup)

Exactly-once for the *reaction* is the substrate's, but exactly-once for
*creating R* is not — two scan passes could each mint an R for the same S. The
dedup is at create time, keyed on **subject + kind**: before creating R for S,
`gc-proactive.sh` refuses if an open or in-progress bead with
`task_kind=reaction` already tracks S (matched by either `gc.reaction_subject=S`
or a `tracks` edge to S, since a visit records its subject twice and only the
edge has proved reliable). One open reaction per subject.

The dedup keys on `task_kind=reaction`, not on any marker on S, so it holds
while S is still scan-eligible — which S remains until the reaction's write-back
lands (S is unchanged between R's creation and R's disposition). Once the
write-back lands, S is no longer scan-eligible on its own terms (routed, held on
an edge, awaiting a visit, or closed — see each exit below), so no further
reaction is minted. A deliberate re-reaction ("it has been a week, look again")
is simply a new R filed against an S that has become eligible again; the dedup
does not forbid it, because it keys on *open* reactions, not on history.

## The four dispositions: the write-back to S

Each disposition is R's write-back to S, performed by
`assets/scripts/first-reaction-dispose.sh`. The reaction never closes S except
through the one evidence-gated writer (the superseded exit). The write-back
carries the reaction card into S's notes as the dispatch record
(`--append-notes`, never `--notes`).

| Disposition | S becomes | Act |
|---|---|---|
| **actionable** | routed to a pool | route S (`gc.routed_to`), the card is the dispatch note |
| **blocked** | held on a `blocks` edge | wire the edge to the blocker; optionally arm a deferred dispatch for when it clears |
| **ruling** | awaiting an operator visit | file the visit (tracks S), hold S on it |
| **superseded** | closed with a successor | `bead-rehome.sh --check`, then close through `bead-rehome.sh` |

`gc.origin=operator` forces the ruling exit; the other three are refused, so a
bead the operator filed for a person always reaches one.

`superseded` is the reaction's own close-with-successor, and it is the narrow
one: it takes only `fixed-upstream` or `duplicate`, the two kinds whose evidence
a reaction can establish (the successor exists, is closed or shipped, in the same
store, and S did no work). The judgment kinds — `re-homed`, `folded`,
`not-needed` — are a person's call and reach the operator through the ruling
exit. Every close-with-successor, from any actor, goes through
`bead-rehome.sh`, the single writer that re-establishes the evidence itself
(§ bead-rehome).

### The completion marker and the residual window

Cross-bead atomicity — dispatch S *and* close R in one transaction — is not
available at the beads layer, so the window between the write-back to S and the
close of R persists. In this model that window is a self-healing no-op, not a
deadlock.

The last write of each disposition stamps `gc.reacted_by=<R-id>` on S — after
the edge on the blocked exit, so it stays completion-marker-last. On re-claim
(the worker died in the window, R's lease lapsed, R is re-offered), the worker
reads S: if `gc.reacted_by` names this R, the write-back already landed, so it
closes R and touches S no further. S is never re-dispatched, and never yanked
from a downstream worker that has since claimed a routed S.

`gc.reacted_by` is not the old machinery reborn. Correctness does not rest on
it: the write-backs are idempotent (routing S to the same pool is a no-op, an
edge is deduplicated, a visit is deduped by its situation key, a superseded
close takes `bead-rehome.sh`'s already-closed repair path), so a re-run without
the marker is safe — the marker only spares the redundant work and protects a
claimed S. No guard refuses progress on its presence, so no partial state can
deadlock. And it is keyed to R's identity, so a marker left by a closed R does
not suppress a later, deliberate re-reaction by a different R.

## bead-rehome.sh: the one close-with-successor writer

`bead-rehome.sh` closes a bead with a legible successor pointer
(`gc.superseded_by` + `gc.superseded_by_store`), and it is the single writer for
that act across every actor: reactions (superseded), converse dispositions, and
operator re-homes. It gates its own evidence rather than trusting the caller.

- `--check` evaluates the gates and writes nothing (exit 0 eligible, non-zero
  refused). The reaction's superseded exit runs `--check` first and falls back
  to the ruling exit on a refusal, so a reaction never half-closes a bead.
- The gates, re-established by the script for every kind: the origin is not a
  review bead, not a step bead or workflow root, carries no unlanded work
  (`merge_result` empty or `merged`), and is not held in progress by another
  session. For `fixed-upstream` / `duplicate`: the successor is in the same
  store and is closed or `work_outcome=shipped`, and the origin did no work
  (`work_outcome=no-op`, or no work-product key set at all).
- The pointer is stamped and read back before the close; a close is gated on the
  read-back, not the write's exit status. The close is deliberately not
  `--force`, so a refusal leaves an open, pointed, findable bead rather than a
  silent drop.

These are the gates the retired duplicate sweep used to enforce as a separate
arm; folding them into `bead-rehome.sh` gives every close-with-successor caller
one contract.

## What this replaces

- **`formulas/mol-first-reaction.toml`** is retired. A reaction is no longer a
  poured graph.v2 workflow with an input convoy and per-step closes; it is a
  plain bead R. In-flight molecules poured before the cutover complete on their
  frozen step descriptions (§ Cutover).
- **The subject-metadata dispatch** — `gc.first_reaction`,
  `gc.first_reaction_reason`, `gc.first_reaction_target`, `gc.first_reaction_at`
  — is retired. `first-reaction-dispose.sh` no longer writes the attempt record
  before the act, and `gc-helm.sh`'s `takeaway --release` no longer stamps or
  reads back `gc.proactive_reaction`. The reaction-bead path replaces the
  completion proof with `gc.reacted_by`; `gc.proactive_reaction` survives only on
  the frozen no-`--reaction-bead` path, where `first-reaction-dispose.sh` stamps
  it as the legacy landed proof until pre-cutover molecules drain (§ Cutover).
- **`assets/scripts/duplicate-sweep.sh`** (merge-cadence arm) and the
  `duplicate_of` / `duplicate_of_store` markers are retired. Its evidence gates
  live in `bead-rehome.sh`; its backlog was zero.

## Cutover

The cutover is one PR, not a two-phase interim. Two facts keep it safe:

- **In-flight `mol-first-reaction` molecules complete on frozen steps.** A step
  bead's description is frozen at pour, so retiring the formula file does not
  strand a molecule already running; its `advance-and-drain` step still calls
  `first-reaction-dispose.sh`.
- **`first-reaction-dispose.sh` stays backward-compatible.** Called without
  `--reaction-bead` (the frozen invocation), it performs the same four-exit
  write-back on the claimed subject and skips the close-R step. With no R to key
  exactly-once on, it stamps the legacy landed proof `gc.proactive_reaction=1`
  after the act, in place of `gc.reacted_by`. The frozen `advance-and-drain`
  molecule reads that proof two ways — its own `load-bead` REACTED check and this
  script's re-offer guard — so a re-offered frozen step stops before the act
  rather than re-releasing (reopening, unassigning, re-routing) a subject a
  downstream worker has already claimed. That release is not idempotent, which is
  why the frozen path keeps a landed proof rather than relying on the step chain
  alone; the proof is retained until pre-cutover molecules drain.

Newly-scanned subjects take the reaction-bead path from the moment the PR lands;
the scheduler that runs `scan --sling` on a cadence is a separate, downstream
change (tk-cbwtkb), which waits on this model and then wires the same
`scan --sling` entry point.

## Metadata

On R (the reaction bead):

| Key | Meaning |
|---|---|
| `task_kind=reaction` | R is a reaction bead — the dedup and pool-query key |
| `gc.reaction_subject` (+ `_store`) | the subject S this reaction tracks |
| `gc.reaction_kind` | the reaction sub-type, `first-reaction` |
| `gc.routed_to` | the proactive pool that claims R |

On S (written by the write-back):

| Key | Meaning |
|---|---|
| `gc.reacted_by` | the reaction R whose write-back landed — the residual-window self-heal |
| `gc.proactive_reaction` | `1`, the legacy landed proof the frozen no-R path stamps in place of `gc.reacted_by` |

Retired everywhere (writers, readers, and the `lifecycle.toml` registry):
`gc.first_reaction`, `gc.first_reaction_reason`, `gc.first_reaction_target`,
`gc.first_reaction_at`, `duplicate_of`, `duplicate_of_store`. Kept:
`gc.proactive` (the standing scan opt-in), `gc.reacted_by` (the reaction-bead
landed proof), `gc.proactive_reaction` (the legacy landed proof the frozen
no-`--reaction-bead` path stamps, until pre-cutover molecules drain),
`gc.superseded_by` / `_store` and `gc.supersedes` / `_store` (the rehome
pointers), `gc.blocker_key`.

## Implementation surface

- `tools/gc-proactive.sh` — `cmd_sling` creates R and wires the tracks edge
  instead of pouring a formula; the dedup guard keys on
  `(task_kind=reaction, subject)`; `exclude_graph_structural` drops topology
  roots and step beads from both scan and demand.
- `agents/proactive/prompt.template.md` — the reaction method: claim R, resolve
  S, re-offer recovery on `gc.reacted_by`, card, one of four exits, close R.
- `agents/proactive/agent.toml` — the pool `work_query` / `scale_check` claim
  routed reaction beads and exclude graph-structural beads.
- `assets/scripts/first-reaction-dispose.sh` — the four-exit write-back, the
  `gc.reacted_by` marker, the close-R step, and the backward-compatible
  no-`--reaction-bead` arm that stamps and guards on the legacy
  `gc.proactive_reaction` landed proof for frozen molecules.
- `assets/scripts/bead-rehome.sh` — the single evidence-gated
  close-with-successor writer with `--check` and the folded-in gates.
- `assets/scripts/gc-helm.sh` — `takeaway --release` no longer stamps or reads
  back `gc.proactive_reaction`.
- Retired: `formulas/mol-first-reaction.toml`, `assets/scripts/duplicate-sweep.sh`
  (+ test), the `duplicate_of` predicate in `pr-stack.sh`, and the duplicate-sweep
  arm in `refinery-reconcile.sh`.
- `lifecycle/lifecycle.toml` — the metadata registry gains the reaction keys and
  drops the retired ones.
- Docs reconciled: `docs/authority-map.md`, `docs/component-model.md`,
  `docs/state-machine.md`, `docs/gascity-human-engagement.md`,
  `agents/proactive/PROVENANCE.md`, and the converse prompt.
