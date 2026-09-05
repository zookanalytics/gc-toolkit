---
name: Verification of the polecat demand/claim agreement fix
description: What was run and measured to establish that both halves of tk-czh6y — the 2026-05-07 empty-spawn storm and the 2026-05-14 codex no-auto-spawn variant — are fixed and guarded, and what that evidence does not cover.
---

# Verification of the polecat demand/claim agreement fix

tk-czh6y reported two symptoms of one property breaking. In the storm
(2026-05-07) the controller counted a row as demand, minted a seat, and the
seat's own query did not serve that row, so it drained with
`state_reason=creation_complete` and the row was counted again on the next
tick. In the codex variant (2026-05-14) the mirror held: rows routed to
`polecat-codex` were servable but not counted, so no seat was minted for
them, and claims landed only through short-form `polecat-codex-adhoc-*`
direct-assign rather than the qualified `<rig>/<agent>` form.

A 2026-05-24 pass called the bead PARTIAL: the storm was fixed by gascity
`14be5e2b` and `aacd9fda`, and the codex variant was left open and
unverified.

## The property, and where it now lives

`gascity cmd/gc/demand_serve_agreement_test.go` states both directions as one
invariant:

> Any row the controller counts as demand for template T must, in the same
> store state, be servable to a T-worker and acceptable to that worker's claim
> matcher. Counted-by-one is the defect — in either direction. A row counted
> but not servable spawns a seat that reads empty, drains, and is counted again
> next tick; a row servable but not counted is work no seat is ever minted for.

`agreementRow` carries a single `wantServable` field on purpose: one verdict
shared by the demand side and the serve side is the property.

## Guard

Six tests, all in `cmd/gc/demand_serve_agreement_test.go`:

    TestDemandCountsExactlyTheClaimableRows
    TestTierThreeServeRulesMatchTheGeneratedQuery
    TestSlotSuffixCollapseIsPersistedForClaimableFormsOnly
    TestSlotSuffixCollapseIsIdempotent
    TestGoPredicateAndGeneratedQueryAgreeRowByRow
    TestCountFormDeclinesEveryKindTheHookRefuses

All six pass at gascity `f8f4ee8c8`, with `GC_RIG` unset and `TMPDIR` at its
default. `go test ./cmd/gc -list '<the six, alternated>'` returns exactly those
six names and no others. A first build of `./cmd/gc` runs past 110s; warm runs
finish in about 1.4s.

The selector matters. `go test ./cmd/gc -run Agreement` selects four other
tests, none of them in this file, and
`TestDroppingALegBreaksAgreementAndNotTheRowCorpus` among them reads as if it
were this guard. That pattern returns a green that says nothing about the
property.

## Runtime metric

gascity emits `session.demand_claim_divergence` after a demand-spawned seat
drains empty. `cmd/gc/demand_divergence.go` classifies each one against the
trigger row it was minted for, and `classifyDemandTrigger` returns
`divergence` only when that row is still `open`, still servable, and still
route-matching for this seat's template — the invariant breaking. Every other
outcome is `benign`, which is a sibling seat having claimed the row first, and
a read that fails is `unknown` rather than an invented divergence. The file
states the target directly: the divergence count is the rollout metric for the
agreement fix and should be zero, while the benign count is expected to be
nonzero forever.

The metric covers one direction of the property. It runs only when a seat the
controller minted from counted demand drains empty, so it registers the storm
half: a row counted but not servable. It does not register the codex half. A
row servable but not counted mints no seat, so nothing drains and the emitter
never runs.

Measured over the full retained city event ring, 2026-09-03 00:38:11Z to
02:38:03Z, 7961 events across all four rigs:

| classification | count |
|---|---|
| `benign` | 7 |
| `divergence` | 0 |
| `unknown` | 0 |

Six of the seven benign events had a trigger already `closed` at drain. The
seventh (`signal-loom/gc-toolkit.polecat`, session `lx-7c7cl`, trigger
`sl-1zay2`) had a trigger still `open`, and is classified correctly: that
polecat had claimed `sl-1zay2` at 02:24:13Z, stamping `gc.claimed_at` and
`gc.session_id=lx-7c7cl`, then handed it to the refinery, which closed it at
02:34:12Z — eleven seconds after the drain. The seat did claim its work.

## Live probes

Re-derived 2026-09-03 between 02:31Z and 02:38Z.

**Auto-spawn into the codex pool.** `gc status` reports
`gc-toolkit/gc-toolkit.polecat-codex` as `scaled (min=0, max=2)` with both
members running. The variant's primary symptom, routed work with no seat
minted, does not reproduce.

**Demand predicate.** `gc bd ready --metadata-field
gc.routed_to=gc-toolkit/gc-toolkit.polecat-codex --unassigned` returns one row,
`tk-28pkkc`, created 02:29:59Z by `gc-toolkit/gc-toolkit.refinery` — about
ninety seconds before the read, against a pool already at its maximum of two
seats. That is demand in flight, not a stranded row.

**Qualified-assignee claims.** Of the twelve most recently created rows routed
to the codex pool, nine carry the qualified form
`gc-toolkit/gc-toolkit.ripley` or `gc-toolkit/gc-toolkit.hicks` and are closed.
No `polecat-codex-adhoc-*` short-form assignee appears anywhere in that set.
The three with no assignee are `mol-review` workflow roots, which
`TestDemandCountsExactlyTheClaimableRows` asserts are not counted as demand;
they are topology, not claimable rows. `tk-2a24xe` and `tk-rbmamt`, cited
earlier the same night as in-progress under the qualified form, are now closed.

This path is exercised continuously rather than incidentally:
`assets/scripts/refinery-reconcile.sh:56` sets
`REVIEW_POOL="$RIG/${BINDING_PREFIX}polecat-codex"`, so every refinery review
dispatch runs codex spawn and claim.

## What this does not cover

The city event ring retains about two hours: `gc events --since 6h` returns
nothing, and wider windows do not complete. The divergence count above is a
live-window measurement, not a history. A recurrence of the storm half would
show as a `divergence`-classified event, the counter to watch for that half
rather than re-running these probes by hand. The codex half raises no such
event, for the reason the Runtime metric section gives: no seat is minted, so
nothing drains. That direction is held at build time by the guard in
`demand_serve_agreement_test.go`, and at runtime by the demand predicate
against pool state. The runtime signature is an unassigned ready row the codex
pool never mints a seat for, which is the check the Live probes section runs.
