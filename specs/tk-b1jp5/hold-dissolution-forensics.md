---
name: Forensics — what actually dissolved the refinery duplicate-hold on tk-8d9u9
description: Read this before implementing either remedy proposed on tk-b1jp5. Establishes, from the Dolt event log plus the shipped bd source and a live positive/negative control, that neither filed defect exists — the pool never offered a blocked bead and the claim never erased the hold markers. Records what the real residual defect is and re-scopes the two remedies.
date: 2026-08-10
status: INVESTIGATION COMPLETE — both filed defects disproven; no code written by design
work_bead: tk-b1jp5
investigates: tk-8d9u9 (the 2026-08-09 incident), tk-p8rgv (the incumbent)
answers: tk-qnsqhv (sequenced behind this bead)
related: tk-rlm94 (quiesce is_terminal_anchor — routed separately), tk-44xkw
---

# Forensics: what dissolved the duplicate-hold on tk-8d9u9

## Scope

What this document establishes: the actual causal chain of the
2026-08-09T06:11Z hold dissolution on `tk-8d9u9`, with the mechanism of
each step pinned to either a row in the Dolt event log or a line in the
source of the `bd` binary that was running at the time.

What it does not do: propose an implementation. The bead was routed
investigate-first precisely because the mechanism was unestablished, and
the finding is that both proposed remedies target behaviour that does not
exist. Writing either one would have been a no-op shipped as a fix.

## Verdict

**Both defects as filed are misattributions.** They were inferred by
comparing a before-snapshot (the hold, 05:21:53Z) with an after-snapshot
(post-claim, 06:11:47Z) and attributing the difference to the only event
visible in between — the claim. The event log shows four writes by a
third actor in the intervening 35 seconds.

| Filed defect | Status | What actually happened |
|---|---|---|
| 1. A `status=blocked` bead was offered to a pool | **Does not occur** | The bead was `status=open` at claim time. `gc-toolkit__mayor` set it open 35s earlier. |
| 2. The claim cleared `duplicate_of` + `gc.routed_to` | **Does not occur** | Both were cleared by `gc-toolkit__mayor` at 06:10:53Z and 06:11:03Z, *before* the claim. The claim writes no metadata at all. |

Neither remedy on the bead should be built. Details in
[Re-scoping the remedies](#re-scoping-the-remedies).

## Ground truth: the event log

Source: `tk.events` on the city Dolt server, `issue_id='tk-8d9u9'`. This
is `bd`'s own audit table — the same rows `RecordFullEventInTable` writes
inside the claim transaction — so it is not a reconstruction.

```
ts (UTC)  event           actor                             status        duplicate_of   gc.routed_to
05:21:53  status_changed  gc-toolkit--gc-toolkit__refinery  blocked       tk-p8rgv       human        <- HOLD PLACED
06:10:53  updated         gc-toolkit__mayor                 -             tk-p8rgv       human
06:10:53  status_changed  gc-toolkit__mayor                 open          -              -            <- UN-BLOCKED
06:10:53  updated         gc-toolkit__mayor                 -             tk-p8rgv       ""           <- ROUTE CLEARED
06:11:03  updated         gc-toolkit__mayor                 -             <absent>       ""           <- duplicate_of REMOVED
06:11:28  claimed         gc-toolkit__polecat-lx-hdq6       in_progress   -              -            <- THE CLAIM
06:11:47  updated         gascity                           -             -              ""           <- session pointers stamped
06:26:06  updated         gc-toolkit--gc-toolkit__refinery  -             tk-p8rgv       human        <- HOLD RESTORED
06:26:07  status_changed  gc-toolkit--gc-toolkit__refinery  blocked       -              -
```

Metadata key sets on the mayor's writes, showing the removal directly
(`JSON_KEYS` of `new_value.metadata`):

```
06:10:53  gc-toolkit__mayor  ["branch","target","work_dir","duplicate_of","gc.routed_to"]
06:11:03  gc-toolkit__mayor  ["branch","target","work_dir","gc.routed_to"]              <- duplicate_of gone
06:11:28  polecat (claimed)  NULL                                                        <- no metadata in the claim event
```

The claim event's entire `new_value` is:

```json
{"assignee":"gc-toolkit__polecat-lx-hdq6","status":"in_progress"}
```

`blocked_reason` was also already absent from the mayor's 06:10:53 write,
i.e. it did not survive as the bead's report states — it was gone before
the claim too.

At the instant of the claim the bead was: `status=open`, `assignee=""`,
`gc.routed_to=""`, no `duplicate_of`, no `blocked_reason`. **That is an
ordinary unheld open bead, and claiming it was correct behaviour.**

Note also `gc.routed_to=""` at claim time: an empty route matches no
pool's offer predicate, so the bead was not pool-*offered* at all. The
claimant was `lx-hdq6` — the same session that had been working the bead
since 05:04Z. It re-derived its own work bead and re-claimed it, exactly
as the polecat prime's claim-first invariant directs. No pool dispatch
was involved anywhere in this incident.

## Defect 1: the pool offer predicate

### The predicate does exclude blocked

The pool demand query is built at
`rigs/gascity/internal/config/workquery.go:41` (`bdReadyPoolDemandShell`):

```
bd ready --metadata-field "gc.routed_to=$target" --unassigned --exclude-type=epic --json <limit>
```

The bead's note is right that this line carries no status filter. The
status filter is inside `bd ready` itself, at
`internal/storage/sqlbuild/ready.go:93` (`BuildReadyWorkWhere`):

```go
default:
    statusClause = "status IN ('open', 'in_progress')"   // :105
}
whereClauses := []string{
    statusClause,                                        // :108
    "(pinned = 0 OR pinned IS NULL)",
    "is_blocked = 0",                                    // :110
}
```

A caller can override it via `filter.Status` / `filter.Statuses` (`:97`,
`:100`) — i.e. by passing `--status blocked` explicitly. The pool
predicate passes neither, so it takes the default and `blocked` is
excluded. `is_blocked = 0` is an additional, independent exclusion for
dependency-blocked rows.

The other two tiers of the same probe are excluded on the same grounds:
the migration tier (`workquery.go:53`) is another `bd ready`, and the
legacy ephemeral tier (`workquery.go:86`) queries `status=open`
explicitly. The assigned-work tier
(`workquery.go:170`) matches on `--status in_progress --assignee=<id>`,
which a blocked *unassigned* bead cannot satisfy.

### Demonstrated, not just read

Run against the shipped binary (`bd 1.1.0`, module
`v1.1.1-0.20260729113304-423afdcb2813`) in a throwaway proxied-server
workspace, using the exact pool predicate. Both controls included,
because an empty result proves nothing on its own:

```
bead zz-ijn, metadata {duplicate_of, gc.routed_to=zz/zz.polecat}

status=blocked  ->  bd ready --metadata-field "gc.routed_to=zz/zz.polecat" --unassigned --exclude-type=epic  ->  []
status=open     ->  same query                                                                              ->  ["zz-ijn"]   (positive control)
```

And the claim refuses a blocked bead outright:

```
$ bd update zz-ijn --claim          # status=blocked
Error: 1 of 1 issues failed to update
  zz-ijn: claiming issue: issue not claimable: status blocked
```

That refusal is `ClaimableSourceStatusesInTx`
(`internal/storage/issueops/claim.go:289`), which returns `open` plus
custom statuses whose category is `active` — nothing else. Its own
comment at `:285-287` states the intent: "an in_progress/blocked issue,
or a custom alias for one, is never silently re-claimable."

**Conclusion.** There is no path by which a `status=blocked` bead is
offered to or claimed by a pool. The premise of defect 1 is false. There
is consequently no "which path was it" to determine, and nothing to
exclude that is not already excluded.

## Defect 2: what the claim writes

`BdStore.Claim` (`rigs/gascity/internal/beads/bdstore.go:1365`) does not
write metadata itself; it shells out to `bd update <id> --claim --json`
and parses the result. So the whole question reduces to what `bd`'s claim
does.

`ClaimIssueInTx` (`internal/storage/issueops/claim.go:35`) issues exactly
one statement (`:99`, and the no-`started_at` twin at `:109`):

```sql
UPDATE issues
SET assignee = ?, status = 'in_progress', updated_at = ?, started_at = ?, <row_lock>
WHERE id = ? AND status IN (<claimable>) AND (<assignee predicate>)
```

Five columns: `assignee`, `status`, `updated_at`, `started_at`,
`row_lock`. **The `metadata` column is not among them, and appears
nowhere in the function.** The recorded event mirrors this — `newUpdates`
at `:180` is `{assignee, status}` only, which is exactly what the live
06:11:28Z row contains.

Demonstrated on the shipped binary:

```
before claim: {"status":"open",       "assignee":null,         "metadata":{"duplicate_of":"zz-incumbent","gc.routed_to":"human"}}
after  claim: {"status":"in_progress","assignee":"test-polecat","metadata":{"duplicate_of":"zz-incumbent","gc.routed_to":"human"}}
```

Both keys survive the claim untouched — including `gc.routed_to`, which
the bead assumed was consumed by the claim "by design". It is not. It is
consumed by *dispatch* paths that explicitly rewrite it (the 06:11:47Z
`gascity` write is one), not by the claim.

**Conclusion.** The claim path cannot erase `duplicate_of`, and did not.
The premise of defect 2 is false. The design constraint recorded on the
bead about the claim guard's atomic rollback is real but irrelevant here
— it governs multi-key updates *on* an in_progress bead, not the claim.

Corollary worth keeping: the bead's observation that `duplicate_of` has
zero hits in gascity core Go is correct, and the reason is now clear —
core has no reason to know the key. It is not core's.

## The real residual defect

Everything the machinery did was correct. The hold came apart because
**a refinery dedup-hold is a convention with no representation in any
code, and therefore nothing to enforce or protect it.**

Three findings support that, and they are the part of this bead worth
carrying forward:

1. **The hold has no reader.** `duplicate_of` appears in **zero** files
   in the gc-toolkit pack and **zero** in gascity core. Nothing gates on
   it, nothing alerts on its removal, nothing refuses to act in its
   presence. The bead's note that "merge-skill.sh (4 refs) and
   reconcile-merged-prs.sh (7 refs) already honor the hold markers" is
   about a *different* marker: those files reference `merge_hold` (16 and
   12 occurrences respectively) and `hold_reason` **zero** times. The
   operator gate `merge_hold` is honoured; the dedup hold is not.

2. **The hold has no writer contract either.** No shipped artifact
   defines the `status=blocked` + `assignee=""` + `gc.routed_to=human` +
   `duplicate_of` + `blocked_reason` shape — no script, no formula, no
   fragment. It is reproduced from agent instructions each time, which is
   also why its field set drifts between incidents.

3. **`blocked` protects only against `--claim`, not against `--status`.**
   The anti-steal guarantee at `claim.go:289` is real but narrow: it
   makes a blocked bead unclaimable *directly*. Any actor may set
   `--status=open` first, with no guard, and then claim it. That two-step
   is exactly the observed sequence, and it means `status=blocked` is not
   load-bearing as a hold — it is a hint.

Intent is not established: the event log records what the mayor wrote,
not why. The bead's notes say the operator had already decided to fold
this branch via rework `tk-u24oa`, which would make the un-blocking a
deliberate release that the refinery then re-imposed 15 minutes later. If
so, the incident is an actor-coordination conflict rather than an
accident, and "make the hold tamper-proof" would be the wrong fix — it
would harden a hold against the actor entitled to lift it. **Confirming
the mayor's intent is the prerequisite for any remedy here**, and it is a
question for the operator, not something the log can answer.

## Re-scoping the remedies

The bead proposes two. Neither should be built as written.

- *"Exclude `status=blocked` from the pool offer predicate (and confirm
  no other offer path bypasses it)."* — Already excluded, on every path.
  Implementing this ships a no-op; the confirmation half is done above.

- *"Make the dedup hold claim-durable: do not clear `duplicate_of` on
  claim, or add a `hold_by`/`hold_reason` pair the claim path must
  preserve, and have the claim REFUSE a bead carrying it."* — The claim
  already preserves arbitrary metadata and already refuses blocked beads.
  The first two thirds are no-ops. Only the third — *refuse a bead
  carrying a hold marker* — describes behaviour that does not exist, and
  it is not a claim-path change: the claim never saw a held bead. It
  would have to be a guard on the **write** that lifts the hold.

What is actually open, if the operator wants it pursued, is narrower and
differently placed:

- Give the dedup hold a code representation with at least one reader, so
  it is a mechanism rather than a convention (finding 1 and 2). This is
  pack-side and is the tractable piece.
- Decide whether lifting a hold should be guarded at all, which depends
  entirely on the intent question above. `bd` has conditional-update
  guards (`--if-status`, `--if-assignee`, `update.go:336`) that would let
  a lift be made compare-and-set without any core change.
- Alert on a hold being lifted. The bead is right that this failed
  silently; the refinery caught it only on its next patrol pass.

None of these is what the bead currently asks for, so they need the
operator's call before anyone writes code — which is why this bead was
routed investigate-first.

## Answer for tk-qnsqhv

`tk-qnsqhv` (double-dispatch race, re-pool while the polecat is alive) is
sequenced behind this bead and asked to be answered by these findings. It
is, and it is the same shape from the other end.

Its incident (`tk-7druqk`, 2026-06-03) has the same causal structure —
verified the same way, in `tk.events`:

```
21:46:49  claimed         gc-toolkit__polecat-lo-session-a4b0…   in_progress
21:47:47  status_changed  order:orphan-sweep                     open, assignee=""   <- RE-POOLED
21:51:38  claimed         gc-toolkit__polecat-lo-session-13cc…   in_progress         <- second polecat
21:53:03  status_changed  order:orphan-sweep                     open, assignee=""   <- again
```

The re-pooling actor is `order:orphan-sweep` — a live city order on a
5-minute cooldown that resets beads assigned to dead agents. So both
incidents are instances of one statement:

> The read side is sound. `bd ready` and the claim CAS are correctly
> fenced. In both incidents a **third actor rewrote the fields that
> encode "this bead is spoken for"** (`status`, `assignee`,
> `gc.routed_to`), after which the offer and the claim behaved exactly to
> spec. The defect is on the write side, and it is unguarded.

That is the answer to tk-qnsqhv's "what may be offered, and what a claim
writes" question: what may be offered is exactly what the predicate says,
and a claim writes only `assignee` + `status`. Its re-pool question is
therefore not about the pool — it is about `orphan-sweep`'s liveness
determination.

One caveat, so tk-qnsqhv is not scoped on a stale reading: the current
`orphan-sweep.sh` already carries a re-check guard,
`work_bead_still_resettable()` (`:175`), plus a `live_session_match`
probe, and selects only `--status=in_progress` beads (`:58`) — so it
cannot dissolve a blocked hold, and its 2026-06-03 race may be partly
mitigated already. The earliest appearance of that guard at that path is
2026-06-10 (`f895c0ff4`), i.e. *after* the incident. Whether an
equivalent existed elsewhere on 06-03 is unverified. **tk-qnsqhv should
re-confirm the race still reproduces against the current script before
being worked**, rather than treating the 06-03 timeline as current.

## Method, for re-verification

The whole investigation is read-only except the isolated experiment, and
reproducible in a few calls:

1. **Event log** (authoritative; `bd`'s own audit table):
   `gc dolt sql -q "SELECT created_at, event_type, actor, new_value FROM tk.events WHERE issue_id='<id>' ORDER BY created_at"`.
   Guard the JSON accessors with `JSON_VALID(new_value)` — close events
   store a bare string and break `JSON_EXTRACT` for the whole result set.
   The rig databases are named by bead prefix (`tk`), not `beads_<rig>`.
2. **Source of the binary that actually ran**, which is not the one
   gascity's `go.mod` pins: `go version -m $(which bd)` gives the true
   module version, then `go mod download` it and read from the module
   cache. Here the running binary was
   `v1.1.1-0.20260729113304-423afdcb2813` (2026-07-29) while gascity
   pins `zookanalytics/beads` at 2026-06-25 — reading the pinned copy
   would have been reading the wrong code.
3. **Isolated live controls**: `bd init --proxied-server` in a scratch
   directory spawns a per-workspace Dolt child, so behaviour can be
   demonstrated without creating a single bead in the city ledger. Stop
   it with `bd dolt stop` and delete the directory afterwards. Embedded
   mode is unavailable — this `bd` is built `CGO_ENABLED=0`.
