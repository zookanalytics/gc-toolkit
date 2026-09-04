---
name: Beads lease primitive — adoption findings
description: Why the shipped bd lease cannot replace the witness's session-liveness detection, and what the lease is actually good for in gc-toolkit. Read before acting on tk-eotd6's checklist, which this record supersedes on two items.
---

# Beads lease primitive — adoption findings

`tk-eotd6` tracked an upstream dependency: adopt the Beads lease primitive,
then delete gc-toolkit's home-grown session-liveness detection from the
witness patrol. The gate the tracker was parked on is open — `bd` 1.2.2 ships
`heartbeat` and `reclaim`, and the lease storage migration is applied. The
checklist the tracker carried was written against the upstream *branch* in
July, and the primitive that shipped differs from it in ways that invert two
of its items.

Every measurement below was taken against the running `bd` 1.2.2
(`62d211937`) and the live gc-toolkit store on 2026-09-03.

## What shipped

A claim through `bd update --claim` stamps a lease: `lease_expires_at =
now + TTL`, with `TTL` fixed at five minutes. `bd heartbeat <id>` pushes that
forward, owner-only. `bd reclaim` reverts in_progress issues whose lease
expired more than a grace window ago back to open, clearing the assignee.

The lease does **not** live on the `issues` row. Migration 0055 moved it into
a separate `leases` table that is registered `dolt_ignored`
(`internal/storage/schema/migrations/0055_move_leases_to_table.up.sql`). That
table is ephemeral and node-local: it does not version, does not replicate,
and a lease is only enforceable on the replica that granted it.

## The lease covers a minority of owned beads

The witness's orphan recovery judges every bead that names an owner in one of
three places — `metadata.gc.session_id`, `assignee`, or
`metadata.gc.session_name`. A lease records a claim actor, so it can only ever
attach to the slice that carries an `assignee`.

Measured over that candidate set (open + in_progress, owner-bearing) at
2026-09-03T08:04:47Z:

| | count |
|---|---|
| owned candidates | 42 |
| has an assignee, and a lease | 11 |
| no assignee, and no lease | 31 |
| of the 11 leases, live | 3 |
| of the 11 leases, expired | 8 |

The split falls exactly on that line, with no bead on either side of it
mismatched. The 31 unleased candidates are workflow roots and session-pinned
step beads: nothing claims them, so they name their owner in
`metadata.gc.session_name` or `metadata.gc.session_id` and will never carry a
lease however the primitive is configured.

A rule reading "no live lease means orphaned" therefore classifies 39 of 42
candidates as orphans: the 31 that can never hold a lease, plus the 8 whose
lease expired for the reason given below rather than because the holder died.

The session-liveness detection in `formulas/mol-witness-patrol.toml` resolves
owners the lease cannot see, so it stays, and the `gc-3tn8g` empty-map
fail-safe stays with it. The tracker's checklist item 3 does not survive the
measurement.

## The TTL is not tunable, and does not need to be

The tracker's checklist item 5 asks for a 30–60 minute TTL, reasoning that a
heartbeat writes a Dolt commit and a long TTL avoids the write amplification
behind past connection-storm incidents. Both halves are wrong against what
shipped.

Heartbeats write only to the `dolt_ignored` `leases` table. They produce no
Dolt commit and no history, so cadence is not a write-volume question —
`bd heartbeat --help` states this directly, and migration 0055 is why.

The TTL is also not reachable. `issueops.DefaultLeaseTTL` is a five-minute
constant, overridable only through `issueops.WithLeaseTTL`, a Go context key.
Its only callers are conformance fixtures; `cmd/bd/` wires it to no flag, no
environment variable, and no config key. Raising the TTL from gc-toolkit is
not possible, and no gc-toolkit change can make it possible.

## A pool claim cannot heartbeat itself

The assignee `gc hook --claim` records depends on the session. For a pool
worker it is the session **id** — `lx-ojs28` for the session that wrote this
record — while `BEADS_ACTOR` in that same session is the session **name**,
`gc-toolkit--gc-toolkit__polecat-1-pool`. `bd heartbeat` is owner-only and
matches the actor against the assignee under `actorMatches`
(`internal/storage/issueops/identity.go`), which accepts a byte-identical
actor or one that canonicalizes to the same string. A session id and a session
name are distinct identities, not two spellings of one, so it refuses:

```
$ gc bd heartbeat tk-eotd6
Error: heartbeat tk-eotd6: issue already claimed by lx-ojs28

$ BEADS_ACTOR=lx-ojs28 gc bd heartbeat tk-eotd6
✓ Heartbeat tk-eotd6 (lease refreshed)     # 08:00:10Z -> 08:05:09Z
```

A session whose `BEADS_ACTOR` already equals the assignee its claim recorded
heartbeats fine. `cmd/gc/cmd_hook_claim.go` records the alias/agent form for a
named agent, and there the ambient actor and the assignee are the same string.
The gap is the path that records a session identity — the pool worker, and the
continuation-pinned claim `continuationPinAssignee` serves — where the assignee
is a session id the ambient session-name actor never matches. The claim side
already resolves this: `cmd/gc/cmd_hook_claim.go` uses the bead's current
assignee as the claim actor, with a comment naming the hazard — `BEADS_ACTOR`
may be the runtime name, the session bead id, or an alias, and bd requires a
match. `rewriteBdHeartbeatArgs` in `cmd/gc/cmd_bd.go` forwards `heartbeat <id>`
to bd with the ambient actor and applies no such resolution.

So a pool worker's lease expires five minutes into a task that runs for tens of
minutes, and the worker cannot refresh it. For the pool population — the bulk
of long-running claims — expired is the steady state, and it carries no
information about the holder.

## Nothing reads the lease

`lease_expires_at` appears nowhere in gc-toolkit's formulas, scripts, or
agents, and appears in gascity only inside two comments. gascity's own
pool-orphan release, `releaseOrphanedPoolAssignments`, decides on session
liveness through `liveOpenSessionAssignmentExists`, not on the lease.

The lease is therefore stamped by every claim and consumed by nobody. That is
why the expired majority has caused no incident: it is inert, not benign.

## What follows from this

Checklist item 4 stands and gains a second reason. A bare `bd reclaim` on a
timer would revert live work to open — not only ahead of worktree salvage, as
the tracker says, but because a live pool holder's lease is stale by
construction: it cannot heartbeat, and reclaim cannot tell that holder from a
dead one. Nothing should reclaim while the pool population it would sweep
cannot refresh its own lease.

The order of operations that follows is: fix the heartbeat identity resolution
in gascity (`gc-ox80c`), then heartbeat long-running pool claims here
(`tk-dkfyz5`, blocked on it), then reconsider reclaim. The same defect is
drafted for filing against `gastownhall/gascity` as section 8 of
[../2026-08-fresh-start/upstream-contrib-drafts.md](../2026-08-fresh-start/upstream-contrib-drafts.md);
`gc-ox80c` is the fix in our fork, which is what this city runs.

The witness's session-liveness detection is unaffected by all three and
remains the only liveness source for the 31 candidates a lease will never
reach.
