---
name: Claim-lease heartbeating — what shipped, and why nothing consumes the lease yet
description: The record of tk-dkfyz5. Why the heartbeat is in-session (the primitive is holder-only), where it is wired and which claim each path refreshes, what it cannot cover, and the reconsideration of lease consumers that supersedes specs/tk-eotd6/lease-adoption.md's "nothing reads the lease".
---

# Claim-lease heartbeating

`tk-dkfyz5` asked to call `gc bd heartbeat <bead>` from the long-running
claim paths so a live holder's lease stays in the future, then to reconsider
whether anything should consume the lease. It follows `tk-eotd6`, whose
`specs/tk-eotd6/lease-adoption.md` is the derivation this builds on; read that
first. This record supersedes that one on a single point — "nothing reads the
lease" — which a later upstream change made stale.

## The prerequisite is live on the running binary

`gc-ox80c` (merged as gascity PR #177) made `gc bd heartbeat` resolve a
session-id claim's actor to its recorded assignee, so a holder whose claim was
recorded under a session id can refresh its own lease. Confirmed live on the
running `bd 1.3.1-rc.2 (696e3967b)`: `gc bd heartbeat` on this session's own
wisp-id claim returned "lease refreshed" (exit 0), which is exactly the
session-id-claim-holder case the fix enables. A claim cannot refresh under a
binary that predates the fix, so this check is the gate, not the merge.

## The heartbeat is in-session, because the primitive is holder-only

`gc bd heartbeat` is owner-only. `gc-ox80c` did not widen that: its override,
`heartbeatActorForOwnedClaim` (gascity `cmd/gc/cmd_bd.go`), substitutes the
heartbeat actor with the bead's assignee only when that assignee is one of the
*calling process's own* `GC_SESSION_*` identities (`sessionOwnIdentities`). A
process that is not the holder carries different identities and is refused.

So a central keepalive that sweeps the roster and heartbeats other sessions'
claims from outside — the shape `pin-keepalive.sh` uses for session pins — is
not possible for leases. Only the holder can refresh its own claim. The
heartbeat therefore lives in the holder's own long-running steps.

## What shipped

`assets/scripts/lease-heartbeat.sh <bead-id> -- <command...>` runs a command
and, every two minutes while it runs, refreshes the bead's lease with
`gc bd heartbeat`. The lease TTL is a fixed five minutes and the test suite
routinely outlives it (the full suite is ~25 minutes, a single file budgeted
15), so the wrapper keeps a live holder's lease ahead of the TTL across the
run. It exits with the command's status; a heartbeat that fails or stalls is
swallowed, because the lease is a best-effort liveness hint, never a gate.
Heartbeats write only the `dolt_ignored` `leases` table, so they cost no Dolt
commit however often they fire.

It is wired into the pool `--claim` holders that run a long blocking test
command, each targeting the bead its own `gc hook --claim` returned (the
lease-bearing one):

- `mol-polecat-work` `preflight-tests` — the base-branch pre-flight suite,
  refreshing the preflight-tests step bead (`CLAIMED_STEP_BEAD_ID`).
- `mol-polecat-work` `self-review` — the affected-or-full suite on the branch,
  refreshing the iteration bead (`CLAIMED_ITER_BEAD`).
- `mol-review` `review` — the suites run at the reviewed commit, refreshing the
  review step bead (`CLAIMED_STEP_BEAD_ID`).

Each resolves the wrapper from the pack and degrades to running the command
plain if it cannot (best-effort). The polecat steps carry the rig's test
command to the wrapper in a quoted heredoc, so a quote inside the command
cannot re-split it. Where the rig declares no test command and the holder runs
the repo's own quality gate, the step instructs wrapping that command the same
way.

### The target is the claim, never the subject

The lease sits on the bead the holder's claim returned and on no other. The
beads a step works *on* carry no lease the holder can refresh. The review bead
a `mol-review` convoy tracks stays open and unassigned while its molecule runs.
The work bead a `mol-polecat-work` molecule builds is open and unassigned while
the polecat works it. An earlier step's claim is already closed by the time a
later step runs. The store refuses a heartbeat on any of them ("issue not
claimable"), and a keepalive aimed at one refreshes nothing while the real
claim lapses. That is why each wired step names its own claim in a `CLAIMED_*`
variable and hands that, not a pin it derived for the work.

Two properties keep a mis-aimed keepalive from passing unnoticed:

- The wrapper reports the first refused heartbeat on stderr, carrying the
  store's reason, and stays quiet after that. An empty bead id runs the command
  plain and says so. Neither fails the command.
- `assets/scripts/lease-heartbeat.test.sh` extracts each formula's keepalive
  region between its `# >>> <step>-lease-keepalive` markers and executes it with
  every candidate id set to a distinct value. It asserts that the id handed to
  the wrapper is the step's own claim, and that the variable carrying it is set
  from that step's `gc hook --claim`.

### Deliberately not wired

- **Converse sittings.** Their long holds are operator-paced *idle* waits, not
  blocking commands, so an in-session wrapper has nothing to wrap. Session-level
  `pin-keepalive` already keeps those sessions alive.
- **The patrols** (refinery, witness, deacon). They self-assign their wisp with
  `gc bd update --assignee`, not `gc hook --claim`, so they carry no lease to
  refresh.

## What it cannot cover

The wrapper covers a long *blocking command*. It does not cover the open-ended
`implement` phase, where the holder is coding and thinking with no shell loop to
tick inside — a stretch longer than five minutes with no intervening command
lets the lease lapse even though the holder is alive. Incremental commits are
the only natural refresh point there, and they are not guaranteed within any
window.

So heartbeating makes the lease a far more reliable "this holder is executing"
signal than before — across the test runs that were its most common and most
deterministic lapse — but not a perfect one.

## Reconsidering the consumer: nothing should consume it yet

`tk-eotd6`'s record concluded "nothing reads the lease." Against gascity HEAD
(`92344d46d`, read 2026-10-04) that is no longer the whole picture. Two
consumers exist in code:

- The standalone `bd reclaim`. It is scheduled nowhere in this pack (the only
  `*-reclaim` orders are `dolt-reclaim`, `worktree-reap`, `scratch-reap`, all
  unrelated to the claim lease). The surviving `tk-eotd6` constraint holds: a
  bare `bd reclaim` on a timer reopens an issue before worktree salvage and
  strands unpushed work.
- A scoped stale-lease reclaim inside `gc hook --claim` itself
  (`AutoReclaimStaleClaims` / `ReclaimStale`, gascity `cmd/gc/cmd_hook_claim.go`,
  ga-7rj87d). It is a per-agent opt-in (`auto_reclaim_stale_claims` in agent
  config), **off by default and enabled by no agent in this city** (no pack
  agent, no town config sets it). When enabled, it lets a claiming worker
  reclaim an `in_progress` candidate whose lease is stale.

Neither should be turned on here on the strength of this change:

- The scoped reclaim would reclaim a candidate by *lease staleness*. Because the
  `implement` gap above lets a live holder's lease lapse, enabling it on the
  polecat would still risk reclaiming a live, actively-coding holder with
  uncommitted work — the exact stranding the `tk-eotd6` constraint forbids.
  Heartbeating narrows that window to the un-wrapped phases; it does not close
  it.
- A bare `bd reclaim` remains unsafe for the salvage-ordering reason above,
  which heartbeating does not touch.
- The witness's session-liveness detection stays the authority. The lease
  attaches only where an assignee does — a minority of owned beads — so it can
  neither replace that detection nor see the workflow roots and session-pinned
  step beads that never pass through `--claim`.

What heartbeating buys is the foundation: a lease that, for the duration of a
long test run, means the holder is alive rather than expiring by construction.
A future consumer that salvages worktrees before reopening and keys off the
lease only beyond a grace window — and only for the slice the lease covers —
could rest on that. Building and enabling such a consumer is a separate
decision, and a gascity/city-config one for the `gc hook --claim` path, not a
gc-toolkit change.
