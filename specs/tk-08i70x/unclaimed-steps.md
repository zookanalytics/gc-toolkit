---
name: The step nobody ever claimed
description: Why the never-claimed detection extends doctor/check-claim-advancing rather than time-bounding gate-ensure's pour arm, why bd ready and a free worker are both gates on the verdict, and what the arm found live on the run that shipped it.
---

# The step nobody ever claimed

A `mol-review` workflow poured over a review bead, routed to a pool, and then
every step sits `open` because nothing ever claims it. Two instances were
reported by the gc-toolkit refinery on 2026-08-27: root tk-uyj4t7 open and
unclaimed at ~2h20m, and root tk-1m8c0d poured 04:25:39Z with all four steps
still open and unclaimed at 07:07Z. Both eventually drained with
`gc.outcome=pass` once a session picked them up, which is the point — nothing
detected them, and nothing would have if they had never drained.

## The cell between the two detectors

`pour_spent()` in `assets/scripts/gate-ensure.sh` returns rc=2, "still driven",
as soon as any non-finalizer step is not closed. Its comment states the
assumption outright: an open step is a live claim or a husk the re-offer path
will pick up, and either way not that arm's business. There is no third reading
for "open, routed, and nobody has ever claimed it", and no time bound anywhere
in the arm.

`doctor/check-claim-advancing` did not cover it either. Its store walk listed
`--status in_progress` only, so an unclaimed step, which is `open`, was outside
the scan.

The two detectors together covered "claimed and stalled" and "closed with no
verdict". The cell between them was reachable by neither.

## Why the detection half, and why here

The bead asked for the extension rather than a time bound on the gate arm, and
that is the right split. `gate-ensure.sh` declines the reading deliberately and
runs on the merge path, where a wrong answer holds a landing. The doctor check
already had the store walk, the age bound and the session join, and its whole
job is reporting rather than gating.

It also belongs on I11 rather than beside it. tk-beecuu's spec argued against
folding liveness into I3 because reachability and liveness ask different
questions of different data. This is not that: "has anything claimed it" and
"is the holder advancing it" are the same question one state apart, and both
are answered from the same join of the bead store against the session roster.
One check, two arms.

## The three gates on the verdict

An open routed step past the bound is not by itself a fault. Three gates stand
between the candidate set and an error, and each one was put there by a
false positive the live city would have produced.

**`bd ready` membership.** Graph.v2 steps carry `blocks` edges to their
predecessors, so every downstream step of every live molecule is open, routed,
and older than any bound worth setting. A six-step `mol-polecat-work` molecule
that a session is working correctly right now presents five such beads. A pool
offers what `bd ready` returns, so that is the only honest test of whether the
step is being offered at all; the rest are waiting on their predecessor by
design.

The offer list is probed lazily, after a store has produced a candidate that
passes every other gate. Most stores produce none, and the offer list is the
expensive half of the walk.

**Never claimed.** No assignee, and no `gc.claimed_at` ever stamped. A pool
claim pre-assigns its whole continuation group, so an open step carrying an
assignee is the live continuation of a working session. A step that carries
`gc.claimed_at` has been claimed before and released or reopened, which is
`check-step-terminal`'s REOPENED finding. Routes are compared as stored, so a
padded one falls through to a note rather than being silently repaired — an
address nothing answers is I3's finding.

**A free worker in the routed pool.** This is the gate that separates a strand
from a queue, and the live city proved it necessary: at the first run of the
finished check, `gc-toolkit/gc-toolkit.polecat` had two running sessions, both
holding a step, with two more work beads queued behind them. That is
backpressure. So is a pool scaled to zero, whose backlog is the demand probe's
business, and a suspended pool, and a pool configured with `max` 0. Only a
running session holding nothing, alongside a step that has been on offer past
the bound, is a fault — an idle worker and an offered step that have not met.

Occupancy counts a session holding *any* in-progress bead, not only a formula
step, because a singleton agent's work usually is not one. That is why the
in-progress listing is filtered for `gc.step_ref` in the check's own jq rather
than server-side: arm 1 wants the steps, arm 2 wants everything, and one probe
answers both. It is also a city-wide question — a pool worker is busy in
whichever store its claim happens to live in, which is often not the store
holding the strand — so the verdict is deferred until after the store walk.

## Joining a session to the pool it runs

`template` is the field that ties a session to its agent, and it is the only
one that works. A pool member's `alias` is empty, so the identity join arm 1
uses for claims — id, session_name, alias — cannot reach a pool from a route.
A codex polecat is worse: `gc-toolkit--gc-toolkit__hicks` carries alias
`gc-toolkit/gc-toolkit.hicks`, naming the persona, while its `template` reads
`gc-toolkit/gc-toolkit.polecat-codex`, which is what the route says. Matching
on `template` is exact string equality against `gc.routed_to`, the same
contract the offer itself uses.

Pool configuration comes from `gc agent list --json`: `suspended`, and
`pool.max`, where 0 means no sessions are configured and -1 means a singleton
with no bound. When that probe fails the arm does not run and says so; it never
passes.

## Bound and degrade

The same 30 minutes and the same `GC_DOCTOR_CLAIM_STALL_MINUTES` as arm 1. The
clock is `updated_at`, falling back to `created_at`: any write to the bead
restarts it, which keeps a re-poured or repaired step quiet and matches the
"untouched for longer than" language `check-step-terminal` already uses.

Liveness is read out of the same session roster arm 1 uses, so the same stale
cache degrades this verdict too: sessions that read as running and free may have
exited or taken work since the snapshot. Past the bound, the error becomes a
warning. A store whose in-progress beads could not be read degrades it the same
way, because a busy worker would read as free.

## Verification

`doctor/check-claim-advancing/run.test.sh` is hermetic, stubs `gc` and `bd`
only, and passes 95 assertions — the 54 that guarded arm 1 unchanged, plus 41
for arm 2. The `bd` stub grew a `ready` subcommand answering from a separate
fixture per store, because what a store holds and what it offers are different
questions and this arm turns on the difference.

The new cases cover the acceptance case and every silence property one at a
time: inside the bound, not offered by `bd ready`, already assigned, already
carrying `gc.claimed_at`, suspended, `max` 0, no running session, every session
busy, a session busy under its alias, a session holding a non-step bead, and a
route naming no agent. Also the `gc.execution_routed_to` fallback, the
configurable bound, the stale-cache degrade, an unreadable agent list, and an
unreadable `bd ready` — each failing closed to a warning rather than a pass.

Against the live city the arm was silent on its first run: ten candidates, all
ten correctly read as backpressure behind two full pools. Twelve minutes later
both codex polecats had finished their reviews and gone idle, and the arm
reported real strands — eight `mol-review.load-dispatch` beads unclaimed for 37
to 48 minutes against `gc-toolkit/gc-toolkit.polecat-codex` with its sessions
running and holding nothing, and one `mol-review.workflow-finalize` unclaimed
for 44 minutes against a running, idle `gc-toolkit/core.control-dispatcher`.
Every element was confirmed by hand: status, assignee, absent `gc.claimed_at`,
`bd ready` membership, and an empty in-progress list for both holders. This is
the shape the bead was filed for, forty-four minutes in, invisible to every
other detector. On the next run the dispatcher had claimed the finalize step
and the arm went quiet on it, which is the same property from the other side.

Notes are aggregated per (store, route, reason) rather than per bead. A queue
behind a full pool is the ordinary state of a busy city, and one line per
queued bead would bury the findings that have to be read; the aggregate keeps
the count and the oldest age, which is what the reason turns on.

The 23 errors arm 1 reports alongside are the pre-existing UNHELD strands
already filed as tk-d0j3r7.

## Scope

Detection only. The root cause of the two observed instances is filed as
gc-ycww6 in the gascity store, where `gc hook --claim` lives; this arm outlives
that fix and keeps reporting the failure whatever its cause.
