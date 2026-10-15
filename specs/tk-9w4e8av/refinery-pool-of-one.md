---
name: Refinery as an ordinary pool of one
description: The design for tk-9w4e8av, the design child of convoy tk-alyaztk under initiative tk-zvu0bd6. The refinery's pre-PR intake becomes a pool capped at one session that claims offered handoffs through gascity's ordinary claim, so session liveness and orphan recovery cover its work the way they cover a polecat's. It settles how a handoff becomes an offer, how a refinery session claims and releases it, the named wait every failure exit takes, what wakes the pool, the one structural alarm and what watches its host, what is deleted (the witness's 4h stuck-handoff timer, I14, the patrol wisp loop, the wake nudge, the named session), how mail state moves to beads, why merges stay serialized, what belongs upstream, and how each listed input is disposed. It defines the implementation breakdown. Read it to review the design or to build one of its units.
---

# Refinery as an ordinary pool of one

## The decision

Today a polecat hands its pushed branch to the refinery by writing the
refinery's name into the bead's assignee and nudging it. The refinery reads its
queue by that assignee. Nothing ever claims the bead, so no liveness reader can
see the refinery stop working on it. When the refinery dies, idles or wedges,
the only thing that notices is the witness's 4-hour clock. It reports one
lane-wide failure as one alert per waiting handoff, hours late, and then mutes
itself for a day.

Under this design a handoff is an offer. The polecat routes the bead to the
rig's refinery pool and leaves it unassigned. The refinery becomes an ordinary
pool capped at one session. A refinery session claims one offer through `gc hook
--claim`, the same claim every polecat makes. It works that one bead to an
outcome and drains. Because the claim is an ordinary pool claim, gascity
recovers it when its session drains, dies or is retired. Either the next
refinery session resumes it or gascity gives it back to the queue (section 2),
and the witness's orphan recovery reads it like any other claim.

Every failure ends the claim, and moves only the bead it failed on:

- a transient fault releases the bead, and the queue offers it again;
- a fault only a person can rule on blocks the bead on a demand;
- a fault in the rig or the pack blocks the bead on one finding per fault, which
  routes the fix.

The next offer proceeds in every case, so one bad bead cannot hold the line.
The refinery reads an offer's readiness through the pack's one definition of a
hold, `hold-lib.sh`, which holds a bead in flight only by blockers of its own.
So parking an epic never holds a branch that was already handed off. Routed
demand wakes the pool. One structural alarm, "offers wait, the refinery takes
none and holds none", is raised by the refinery-reconcile order, and I10 already
notices when that order goes silent. No clock decides that work is stuck. The
witness's 4h timer, I14, the patrol wisp loop, the polecat's wake nudge and the
refinery's named session are deleted.

### What the operator approves here

1. **The refinery becomes a pool, not a named session.** The `[[named_session]]`
   stanza for the refinery goes. The pool keeps the address
   `<rig>/gc-toolkit.refinery`, because gascity gives a pool capped at one
   session its configured name as a stable alias. Mail, nudges and routes keep
   the same address. Section 2 explains why a pool rather than a named session
   claiming routed work.
2. **One claim per session.** A refinery session claims one handoff, takes it to
   an outcome or a wait, and drains. The cost is one session start per handoff.
   At the initiative's measured rate of 420 handoffs in a week, that is about 60
   a day. The gain is that no context carries across beads, and no rotation can
   restart the session under a bead it is working.
3. **One retry, then a wait.** A bead gets two claims that end without an outcome
   before it is set aside on a finding. The gate step already applies the same
   rule to a gate cut short: start it once more, then escalate.
4. **The alarm lives in the merge cadence.** It is not in the doctor sweep, which
   collected no result for 27.5 hours across the 10-14 wedge (tk-dk2aqb7). It is
   not in the witness either, because nothing watches the witness's patrol.
5. **The refinery declares its own claim and demand query.** On gascity's default
   query a parked epic would hold every handoff under it, because `bd ready`
   withholds a parked epic's members. steer-by-epic rules that a park leaves
   in-flight work running, and a handed-off branch is in flight. The pack's one
   definition of a hold, `hold-lib.sh`, already leaves a bead in flight running
   under a park, and deferred dispatch reads holds through it. So one script,
   which the claim, the demand count and the alarm all call, selects the
   refinery's beads and keeps the ones `hold-lib.sh` finds nothing holding. The
   cost is that gascity's idle-claim backstop covers only the offers its default
   query can see, so it misses a session woken only for an offer under a parked
   epic. The alarm covers that case. gascity gc-9h08f6 asks for a custom demand
   count that names the beads it counts, which would remove the cost.

## What this design rests on

Each claim below was read at a fixed revision.

- The pack is read at `132909cb5`, the commit integration/tk-alyaztk was cut
  from. Line numbers in this document are at that commit.
- gascity is read at `46db7fbee`. That is the revision of the installed `gc`
  (`go version -m ~/go/bin/gc` reports `vcs.revision=46db7fbee…`, built
  2026-10-14), and it is also the gascity checkout's HEAD.

The initiative tk-zvu0bd6 carries the evidence for the problem. That is four
lane-wide alert episodes between 10-07 and 10-14, and the distribution of time to
refinery action over 420 handoffs. It also carries the upstream design history,
and this document does not repeat it.

## 1. A handoff is an offer

### What writes a handoff today

Three writers put a bead in front of the refinery, and all three do it by
assignee:

- **The polecat's submit step**, `formulas/mol-polecat-work.toml:1710-1764`
  (`submit-target-consume`). It makes three ordered writes. The first carries
  the metadata, and it clears `gc.routed_to` and the session pins. The second sets
  `--status=open`. The third sets `--assignee=<rig>/gc-toolkit.refinery`. Step 6,
  at `:1777-1781`, then runs `gc session wake` and `gc session nudge` against the
  refinery.
- **Convoy graduation**, `assets/scripts/convoy-graduate.sh:286-302`. It sets
  `--assignee="$GC_AGENT"`, where `refinery-reconcile.sh` projects the refinery's
  identity into `GC_AGENT`.
- **The gascity keeper's rebase handoff**,
  `packs/gascity-keeper/formulas/mol-upstream-gc-rebase.toml:839-872`. It runs
  `--status=open --assignee="$REFINERY_TARGET"`, followed by a wake and a nudge.

### What they write instead

Each writer routes the bead to the refinery pool and leaves it unassigned. The
route is resolved through `pool-route.sh gc-toolkit.refinery`, which qualifies
the name with the rig and proves it byte-for-byte against the live agent set.
That is the claim contract I3 enforces (`doctor/check-routed-work-claimable`).

The polecat keeps its three guard-safe writes, in the same order, with two
fields changed:

1. Metadata and notes set `target`, set `gc.routed_to=<rig>/gc-toolkit.refinery`,
   unset `gc.session_id` and `gc.session_name`, and carry the summary.
2. `--status=open`, as today.
3. `--assignee=""` replaces `--assignee=<refinery>`.

The route lands in the first write, before the bead becomes unassigned in the
third. So the bead never rests open, unassigned and unrouted. That resting shape
is the one gascity's detached-handoff orphan sweep re-routes from a session pin
(`isDetachedHandoffOrphanCandidate`). A molecule-run work bead was never claimed
(load-context, "This workflow never claims its work bead"), so for it the third
write is a no-op and the bead becomes an offer at the first write. That is safe,
because the branch is already pushed and verified by then.

Step 6, the wake and nudge, is deleted, because the offer itself wakes the pool
(section 4).

Convoy graduation and the keeper handoff make the same change. Each writes the
route and an empty assignee, and the keeper drops its wake and nudge.

### Cutover: what an old-style handoff becomes

A bead assigned to the refinery the old way reaches the new refinery by one of
three paths, and none of them needs a migration script.

1. **Handoffs waiting at cutover.** Removing the `[[named_session]]` stanza makes
   gascity retire that session. `retireRemovedConfiguredNamedSessionBead`
   (gascity `cmd/gc/session_beads.go:878-905`) stops the session's runtime,
   retires its bead, and releases every bead assigned to it. The release clears
   the assignee and keeps a route the bead carries (`releaseRoute`,
   `work_release.go:255-273`). An old-style handoff carries no refinery route,
   so cutover step 1 writes the refinery's route on each waiting handoff and
   unsets any `gc.run_target` just before graduation (section 12). The old
   refinery reads its queue by assignee (`mol-refinery-patrol.toml:156`), so the
   write changes nothing for it, and the retirement then releases every waiting
   handoff as an offer.

   The hand step is needed because the release would otherwise route an
   unrouted bead by its `gc.run_target`, and stamp the session's `template`
   there only when the bead carries none (`retiredSessionFallbackRoute`,
   `:907-912`, and `ReleaseWorkBead`, `work_assignment.go:188-206`). A carried
   `gc.run_target` is an archived route, stamped by an earlier gascity release
   that found the bead unrouted, and it can name the pool that built the work. On
   2026-10-15, 15 of the rig's beads carried both a `branch` and a
   `gc.run_target`. All but one named the polecat pool, and two of those were
   rework children handed to the refinery. Released on that route, a handoff
   would be offered to the polecat pool.
2. **Handoffs a pre-cutover polecat writes after cutover.** A molecule poured
   before the change runs the submit text frozen into its steps at pour time.
   That text still clears the route (`mol-polecat-work.toml:1738`), assigns the
   refinery by name, and runs its own wake and nudge. A pre-cutover keeper
   handoff assigns the refinery the same way and leaves whatever route the bead
   carried. The new refinery serves such a bead through the claim's second tier,
   which returns open work assigned to the session's own identities. Those
   include `<rig>/gc-toolkit.refinery` (section 2), the same string the old text
   writes. While the bead waits, the demand count and the alarm count it as they
   count an offer (sections 4 and 5), and the witness leaves it to the claim
   (section 2). The claim gives it the refinery's route before anything else is
   done to it ("The claim routes what it takes", section 2). From then on it is
   released, parked and offered again exactly as an offer's claim is. This
   window closes when the last molecule poured before cutover submits. A query
   for open beads assigned to the refinery whose route is not the refinery's
   counts what is left. If PR #1217 lands first, the handoff is a script that
   every pour calls by name, and the window does not open at all.
3. **The patrol wisps.** These are the `mol-refinery-patrol` molecules assigned
   to the old identity. The retire release reads the wisp tier as well as the
   issue tier (`seat_work.go:160`), so it unassigns the wisps along with the
   handoffs and stamps the same `gc.run_target` on them. A molecule container is
   never routable demand on gascity's default query
   (`internal/config/workquery.go:1052-1053`), and no tier of
   `refinery-offers.sh` serves one (section 2), so a released wisp is never
   offered as work, whatever route recovery writes on it. A pool session also
   cannot start before the retirement, because the named session's row holds the
   alias, which stops the pool from minting one beside it (section 8). So the new
   session's first tier cannot find a wisp still assigned to the alias and
   resume it as its claim. Nothing reads the wisps after cutover, and the
   cutover burns them by hand (section 12).

## 2. Claiming and releasing a handoff

### Why a pool rather than a named session

gascity at `46db7fbee` lets a canonical singleton named session do two new
things. Routed demand can wake it (`NamedSessionRoutedDemand`,
`build_desired_state.go:103-122`). It can also claim work routed to its own
alias (`namedSelfTargetAdmit`, `internal/config/workquery.go:905-929`). So
assignment by name is no longer the only way to wake or feed a named refinery.
The pool is still the right shape, for three reasons.

- **Recovery.** gascity's dead-assignee sweep keeps a claim held by the
  configured named identity that backs the claim's route, even with that
  session's bead closed, on the assumption that the session comes back
  (`assigneePreservesNamedSessionRoute`, `pool_session_name.go:1078-1108`,
  called at `:338-340`). A pool claim is released once no open session holds
  it.
- **One materialization path.** With the stanza gone, pool demand is the only
  automated way to start a refinery session. That is the shape tk-77txj0 asked
  for (section 8).
- **The ruling.** The operator's target model in tk-zvu0bd6 names a pool.

gascity's idle-claim backstop is a fourth reason, because it serves pool slots
only. While the pool declares its own demand count, it reaches only the offers
gascity's default query can see (section 4).

### Configuration

`agents/refinery/agent.toml` makes five changes:

- It sets `min_active_sessions = 0` beside `max_active_sessions = 1`. A template
  capped at one counts as a pool, and gets pool reconciliation, only when it
  sets a minimum or a scale check. Without either it is treated as the backing of
  a named session (`internal/config/session_capacity.go:93-127`). The scale
  check below already qualifies it. The minimum makes the template a pool on its
  own, whatever its demand query. The polecat and proactive pools set the same
  minimum, though a cap above one already makes them pools.
- It keeps `wake_mode = "fresh"` and the per-instance `work_dir`. A pool capped at
  one uses the canonical identity, with no `-1` suffix
  (`UsesCanonicalSingletonPoolIdentity`). So `{{.AgentBase}}` resolves to
  `gc-toolkit.refinery`, and the session keeps the directory it has today.
- Its `nudge` becomes the claim protocol: claim one handoff through
  `assets/scripts/refinery-claim.sh` (below), carry it to an outcome or a wait,
  then drain.
- It declares a `work_query` and a `scale_check`, described below.
- Its header comment describes a pool, not a named singleton.

`pack.toml` deletes the refinery's `[[named_session]]` stanza.

A pool capped at one is a canonical singleton pool member. So gascity gives its
session the alias `<rig>/gc-toolkit.refinery`, and `GC_ALIAS` carries it
(`applyPoolInstanceIdentity`, `build_desired_state.go:4084-4096`, and
`usesTransientPoolSlotIdentity` with `poolDesiredRequestIdentity`,
`:4456-4491`). Mail, nudges, `gc session peek` and routes keep their address.

### Readiness is the pack's hold

gascity's default routed tier and its default demand count both read `bd ready`.
`bd ready` withholds every bead whose parent-child ancestor has an open `blocks`
edge, so a parked epic holds all of its members. A live check on 2026-10-15 shows
this: the parked epic tk-s0jfq7k has 34 open children, `bd ready --parent
tk-s0jfq7k` returns none of them, and `bd blocked` lists all 34 with
`blocked_by=["tk-s0jfq7k"]`. On the default query, a branch handed off from a
member of a parked epic would never be claimed and would never wake the pool.

That contradicts a rule the operator has approved. steer-by-epic says a park
holds work that has not started and leaves work in flight running, and it counts
on the refinery reading its queue by `bd list`, not `bd ready`
(`specs/tk-rl8gz4b.2/steer-by-epic.md`, "What a hold leaves running"). A
handed-off branch is in flight.

The pack already has one definition of a hold, and it leaves work in flight
running. `assets/scripts/hold-lib.sh` holds a bead when the bead, or one of its
parent-child ancestors, has a `blocks` edge onto a bead that is still open. A
bead that carries a `branch`, a `merge_result` or a `rejection_reason` is in
flight. Only a blocker of its own holds it, and the walk reads none of its
ancestors (`hold_chain`, `hold-lib.sh:101-112`, and `docs/component-model.md:491`).
Deferred dispatch reads holds through it, and `doctor/check-armed-dispatch-owed`
reports no held arm as owed. The refinery reads readiness through the same
definition and adds no rule of its own.

So the refinery declares a `work_query` and a `scale_check`, as the proactive pool
already does. Both call one script, `assets/scripts/refinery-offers.sh`, which
the alarm (section 5) also calls, so the three cannot disagree. The script reads
the work by `bd list` and gives the claim three tiers in the default order:

1. In-progress beads assigned to the session's own identities. These are its own
   claim, resumed after a crash. The identities are the session's id, its
   session name and its alias, and `<rig>/gc-toolkit.refinery` is always among
   them, so a session whose alias gascity deferred still finds work held under
   it (see the claim below).
2. Open beads assigned to those identities. These are old-style handoffs during
   cutover. They carry no refinery route until the claim writes one (below).
3. Open, unassigned beads routed to `<rig>/gc-toolkit.refinery`. Epics and
   beads carrying a dispatch-hold or `human` label are excluded, which matches the
   default tier's serving rules (`workquery.go:216-222`). The result is sorted
   by priority, then `created_at`. The tier keeps the default query's origin gate.
   It serves a session whose origin is ephemeral or empty, or whose alias is the
   refinery's own, and no other (`poolDemandOriginGateScript`,
   `workquery.go:931-938`).

No tier serves a molecule container. gascity's default query never offers one,
because `bd ready` excludes it, but the script reads `bd list` and so excludes
molecules itself. Those are the only rules the script owns: the tiers, the route
and the assignee, the label, epic and molecule exclusions, the origin gate and
the sort.

Readiness is the shared hold's. The script sources `hold-lib.sh` and builds, with
`hold_graph`, the graph of the beads that tiers 2 and 3 select. Its reader reads
the ids it is given from the rig's own store, at every status and class, as
`hold-lib.sh` asks of every reader. The script keeps a bead in either tier only
when `hold_held` finds nothing holding it. A walk whose read fails leaves every
bead it was for unread, never free, so the script exits non-zero, as it does on
any read it cannot parse (section 3). The claim then takes nothing. gascity counts
a `scale_check` that fails as no new demand (`evaluatePoolNewDemand`,
`cmd/gc/pool.go:217-232`). The alarm records no observation for that pass
(section 5).

The exception for a parked epic rests on the handoff being in flight, and every
handoff carries a `branch` by the time it is handed over. A polecat's work bead
gets it at workspace-setup (`mol-polecat-work.toml:772`), and a rework child gets
it from `rework-child.sh` when the child is filed (`:173`). Submit's branch gate
refuses a handoff whose checkout is not on that branch
(`mol-polecat-work.toml:1391-1430`). Convoy graduation sets
`branch=<integration branch>` in its assignee write (`convoy-graduate.sh:287-289`),
and the keeper sets `branch=rebase/<issue>` (`mol-upstream-gc-rebase.toml:842`)
ahead of its handoff at `:866`. So the shared hold reads only a handoff's own
blockers:

- an open `blocks` blocker holds it, and a closed or pinned one holds nothing;
- a demand gate of its own holds it;
- a blocker of its own that the store does not return holds it, marked unread;
- a park on its epic, or on any other ancestor, holds nothing.

A routed bead with no `branch`, `merge_result` or `rejection_reason` is not in
flight. The ancestor rule applies to it, so a park holds it as it holds any work
that has not started. Once claimed, a bead with no `branch` has nothing to
prepare, and the prepare step puts it to a person (section 3, line 219).

The shared hold reads `blocks` edges only, while `bd ready` also honors
`waits-for` and `conditional-blocks`. Neither reaches a handoff, so the shared
contract needs no rule for them and the refinery adds none. gascity writes
`waits-for` only between the step beads of a compiled formula, from a step's
`waits_for` field (`internal/formula/compile.go:757-775`), and a handoff is a work
bead, never a compiled step. No code in the pack or in gascity writes
`conditional-blocks`. Every wait the refinery writes is a `blocks` edge its one
writer files (section 3), and so is a hold request (section 7).

The `scale_check` counts the beads tier 3 keeps and the old-style handoffs tier 2
keeps, which are the open beads assigned to `<rig>/gc-toolkit.refinery`. So an
old-style handoff wakes the pool the way an offer does (section 4).

A bead parked on a refinery wait has an open blocker of its own, so the shared
hold holds it (section 3). A bead under a parked epic has none, so nothing holds
it. gascity's own queries stay as they are for every other pool.

The custom demand count has one cost. A custom `scale_check` returns a count,
and a count names no bead (`pool_desired_state.go:589-640`). While the pool is
cold, gascity also runs its default demand probe for it, clamped to one, and
that probe names a concrete trigger bead for the slot it wakes
(`build_desired_state.go:1428-1440`, `:2451-2467`). The probe reads `bd ready`,
so it never names an offer under a parked epic. A session woken only for such an
offer has no trigger bead, and the idle-claim backstop keys on that bead, so it
does not serve that session (section 4). A readiness option in gascity's default
query would remove the cost only by adding a second definition of a hold beside
`hold-lib.sh`, so the refinery would not adopt one. gascity gc-9h08f6 asks
instead for a `scale_check` that names the beads it counts. With it, the backstop
would serve every offer, and readiness would stay the pack's.

### The claim

A refinery session claims through `assets/scripts/refinery-claim.sh`, which runs
`gc hook --claim --drain-ack --json`. That command claims one item, or
acknowledges drain when there is none. The hook takes its candidates only from
the work query's output (`tryHookClaim`, `cmd_hook_claim.go:473-495`). So
`refinery-offers.sh` carries the same three tiers gascity's default query does
(`EffectiveWorkQuery` and `buildWorkQuery`, `workquery.go:1039-1117`), with
readiness read as above.

The claim writes these fields:

- `status=in_progress`.
- `assignee` is the session's alias. A stable identity claims under its alias
  (`hookClaimAssigneeIdentity`, `cmd/gc/cmd_hook.go:1040-1064`, and the
  rationale at `build_desired_state.go:4462-4471`). gascity defers a new
  session's alias while an earlier session row still holds it or its create is
  pending. A session started then runs with a blank `GC_ALIAS` and claims under
  its session id (`setPoolTemplateRuntimeIdentityInfo`,
  `build_desired_state_pool_info.go:55-65`). A bead that tier 2 serves keeps the
  assignee it carries, because the hook claims assigned work under that assignee
  (`claimFirstReadyHookAssignment`, `cmd_hook_claim.go:776-777`). So an
  old-style handoff is claimed under `<rig>/gc-toolkit.refinery`.
- `gc.session_id` and `gc.session_name` name the concrete session
  (`hookClaimIdentityPatch`, `cmd_hook_claim.go:1819-1827`).
- `gc.claimed_at` is stamped write-once at the bead's first claim
  (`internal/beadmeta/keys.go:62-69`).

The hook writes no route, so `gc.routed_to` stays on the claimed bead as it was.
Every release path below reads that route, so the claim makes it the refinery's
before anything else happens (below).

The session then runs `mol-refinery-patrol`'s working steps against the claimed
bead, once `refinery-claim.sh` has routed it and counted the attempt (section 3).
Those are prepare (`rebase`), `run-tests`, `handle-failures` and `merge-push`.
`$WORK` is the claimed bead id. The steps are read from the formula. No wisp is
poured, adopted or burned.

### The claim routes what it takes

A claim from tier 3 already carries the refinery's route. A claim from tier 2
does not. The old submit text cleared `gc.routed_to`, and a keeper handoff keeps
whatever route the bead had. Released as it stands, an old-style handoff would be
open and unassigned with no route to the refinery. Tier 2 would no longer return
it, tier 3 never did, and the alarm would not count it. A wait would leave it in
the same shape once its blocker closed. Nothing gives such a bead the refinery's
route again. Route recovery copies only a carried `gc.run_target`
(`carriedPoolRoute`, `route_recovery.go:32-69`). The detached-handoff sweep
needs a session pin, and every exit clears the pins. The witness's restore step
copies `gc.execution_routed_to` (`orphan-dispose.sh:226-255`), which on a
polecat-built handoff names the polecat pool.

A carried `gc.run_target` can misroute a bead even after its route is right.
gascity's `reopen-source`, which the witness's source arm runs, writes a carried
`gc.run_target` over the route (`cmd_convoy_dispatch.go:2548-2570`). Before the
route is right, gascity's drain-ack, retirement, close-cascade and
stranded-repair releases route an unrouted bead by it (`releaseRoute`). An
old-style handoff can carry one that names the polecat pool (section 1).

So `refinery-claim.sh` settles the claimed bead's route before it does anything
else. Unless the bead already carries `gc.routed_to=<rig>/gc-toolkit.refinery`
and no `gc.run_target`, the script writes that route, resolved through
`pool-route.sh gc-toolkit.refinery`, and unsets `gc.run_target` in the same
write. Then it reads both back. Only a read-back that matches lets it go on to
the attempt count (section 3) and lets the session run the working steps. From
then on, every release and wait in section 3, every gascity release path and the
witness's source arm give the bead back to the refinery. A transient release
leaves an offer, and a wait leaves one when its blocker closes.

When the read-back does not match, the script writes once more. If the write
still does not land, the script does not work the bead. It puts the bead back
with the pins cleared and no attempt counted, and the route the bead carries
decides how.

- A bead with no refinery route is an old-style handoff, held under
  `<rig>/gc-toolkit.refinery` because the hook claims tier 2's beads under the
  assignee they carry. A release would leave it unrouted, so the script sets its
  status back to `open` and leaves the assignee as it is. That write changes no
  assignee, so bd's claim guard does not refuse it ("Ending a claim", below). The
  bead is an old-style handoff again. Tier 2 returns it, the demand count wakes
  the pool for it, and the next claim routes it first.
- A bead from tier 3 already carries the refinery's route, and only its
  `gc.run_target` did not clear. The script releases it as a transient exit
  does (section 3): open and unassigned, with the route kept. It is an offer
  again, and nothing routes it by that `gc.run_target` while it waits. Only
  `reopen-source` writes a carried `gc.run_target` over a present route. The
  pack runs it on a bead that names an owner, in the witness's source arm, or on
  a bead the refinery is rejecting, whose route `rejection-repool.sh` then
  clears. Left assigned, the bead would be served only by the tier 2 of a
  session that holds its assignee, and none does once a session that claimed
  under its session id drains.

Either way, a route write that keeps failing leaves the bead waiting with an
unchanged count, which is what the alarm's third condition looks for
(section 5).

A claim the script has not settled outlives its session only if the put-back
fails too, or if the session dies between the claim and the route write. An
unrouted claim then stays in progress under the alias, which drain-ack leaves
alone (the release table below), and the next session's first tier resumes it
and routes it first. The stranded repair can reach a dead session's claim first.
It gives the claim back on a `gc.run_target` the bead carries, or otherwise on
the seat's route, `<rig>/gc-toolkit.refinery`, which route recovery restores.
After a failed put-back the witness can reach the claim first instead, once the
drained session's row is gone. Its restore step would route an unrouted claim by
`gc.execution_routed_to`, and its `reopen-source` would route a tier-3 claim by
the `gc.run_target` that did not clear. So a misroute needs either a session
that dies between the claim and the route write, on a bead that carries an
archived `gc.run_target`, or three failed writes on the bead in a row.

### One claim per session

The session ends after one bead. That removes the cause of tk-55vtleo.

In fresh mode the controller tears a live session down when its assigned bead
changes, unless the session claimed that bead itself (`selfClaimed`,
`session_reconciler.go:4755-4796`). Today two writes trigger the teardown. The
handoff's `--assignee` write is made by another session. The wisp rotation's
`gc bd update "$NEXT" --assignee="$GC_AGENT"` is made by the refinery itself, but
outside `gc hook --claim`. In the pool model the only assignment the refinery
ever sees is its own `gc hook --claim`, so the reassign cycle never fires
mid-bead. A session also starts each bead with an empty context, so the 200K
recycle hook and the cost gascity #2980 describes have nothing to accumulate.

### Release paths

gascity has one release verb with a policy per path (`cmd/gc/work_release.go:3-21`,
`:77-100`). Each path also picks the identities it releases under, and the paths
differ on the stable alias. A pool claim with a route is served by every path
whose identities include its assignee.

| Path | What it does to a refinery claim |
|---|---|
| Drain-ack | `gc runtime drain-ack` gives back the in-progress claims held under the session's id or session name (`releaseUnexecutedClaimsOnDrainAck`, `session_beads.go:1215-1263`). It leaves out the stable alias (`releaseScopeOwn`, `work_location.go:219-225`), so a claim held under the alias stays in progress, for the next session's first tier to resume or for a path below to give back. |
| Killed seat | A seat that `gc session kill` stops keeps work it started, so the same seat resumes it (`releaseKilledSeat`, `work_release.go:93`). |
| Retired session (`gc session close`, a removed named session) | The claims held under the session's id, session name or named identity are given back with their route (`session_beads.go:1199-1212`). Like drain-ack, it leaves out the alias. |
| Close cascade, stranded repair | The claim is given back with its route, including one held under the alias. |
| Dead-assignee sweep | Routed work whose assignee maps to no open session is reopened (`releaseOrphanedPoolAssignments`, `pool_session_name.go:196-417`). |

A crash leaves the claim in progress. Once the runtime has stayed dead through
gascity's two-minute confirm window, the stranded repair retires the session and
gives the claim back with its route (`strandedRepairConfirmGrace`,
`session_beads.go:1517`), so the bead is offered again. A session that holds the
alias before then resumes the claim through its first tier instead.

### Every reader that must cover the claim

| Reader | How it covers a refinery claim | Change |
|---|---|---|
| gascity session liveness and release (above) | The claim carries a route and the session's pins. The release paths above serve it, each under the identities it covers. | None. |
| Witness orphan recovery (`mol-witness-patrol.toml` `recover-orphaned-beads`) | `host-bead-skip` ranks `gc.session_id` first (`:223-229`), so the owner is the concrete refinery session, not the alias the next session inherits. A dead owner sends the bead to `orphan-dispose.sh`'s source arm. That arm runs `delete-source`, which finds no workflow, then `reopen-source`, which writes a carried `gc.run_target` over the route and otherwise keeps it, then clears the pins. The claim unset `gc.run_target`, so the route kept is the refinery's. The restore step leaves a present route alone (`orphan-dispose.sh:226-255`), so the bead is offered to the refinery again. `downstream-court-skip` does not drop it, because a claim carries no `merge_result`. | The prose at `:338-344`, which excludes the refinery as an infrastructure identity and describes the polecat-to-refinery pin handoff, is rewritten. A refinery claim is pool work, and its owner is its `gc.session_id`. The refinery's alias stays on the infrastructure list. An offer names no owner and a claim names its session, so the only bead the alias then owns is an old-style handoff waiting for its claim. A cold pool can leave the alias with no live session. Without the exclusion the witness would then read that handoff as orphaned, and the restore step would route it by its `gc.execution_routed_to`, which for a polecat-built handoff is the polecat pool. `orphan-dispose.test.sh` gains a fixture for a claimed refinery bead. |
| Liveness census (`liveness-sweep.sh`, `liveness-classify.sh`) | An offer is in `bd ready --unassigned` and classifies as `routed-and-claimable` (`liveness-classify.sh:150`). An offer under a parked epic is outside the ready set, and its wait is the park's edge on the epic. A claim is in progress and outside the ready set, like every claimed step. A bead parked on a refinery wait is blocked, so it is outside the ready set and its wait is an edge. | None. A test fixture pins the offer's class. |
| I11 (`doctor/check-claim-advancing`) | Arm 1 judges a claim's holder: UNHELD, ORPHANED, DEAD, or STALLED. It takes only in-progress beads that carry `gc.step_ref` (`run.sh:309-312`), so today a refinery claim is invisible to it. | Arm 1 widens to in-progress beads routed to a pool agent. A refinery claim's holder is then judged exactly as a step's is. Arm 2, offers nobody claims, stays step-scoped, because refinery offers belong to the one alarm in section 5. `gc.claimed_at` is write-once, so a re-claim is aged from the first claim. That only makes I11 check the holder sooner. A working holder stays clean, because STALLED also needs the holder's `last_active` past the bound. |
| I3 (`doctor/check-routed-work-claimable`) | Both the route and the claim's assignee are the agent's qualified name. An offer appears in `bd ready`, or in `bd blocked` when it waits on its own edge or under a parked epic. | None. |

Three more readers take the old handoff shape as evidence, and each changes with
it:

- **The polecat's load-context duplicate-dispatch gate**
  (`mol-polecat-work.toml:92-235`). Its comment at `:151` reads "Open under a
  foreign assignee is a completed hand-off". An offer is open and unassigned, so
  the gate would read it as unowned, and the next polecat would rebuild handed-off
  work. A claim is in progress under a live refinery, so the gate would read it as
  a live duplicate and escalate. The gate reads both as finished: a route to the
  rig's refinery, and a claim by it. That is the same quiesce-without-visit arm a
  handed-off bead takes today.
- **`gc-helm.sh takeaway`'s landed-rider proof** (`gc-helm.sh:1194-1223`). It
  accepts "its assignee is the refinery" as proof that a wait's work is pushed. It
  also accepts a route to the refinery.
- **`submit-branch-gate.test.sh`**. It asserts the handoff's shape, and its
  fixtures follow the new writes.

### Ending a claim

Every exit that ends a claim follows two rules.

- **It clears the claim's pins** (`gc.session_id`, `gc.session_name`), as every
  release in the pack does. The witness ranks `gc.session_id` first, so a
  `gc.session_id` left behind names a drained session as the bead's owner. A
  `gc.session_name` left behind is the residue `doctor/executor-identity-residue`
  reports once the bead carries a route the stamp does not match. The pins go in
  the same write that clears the route, or in an earlier one. gascity's
  detached-handoff orphan sweep restores a pool route from a session pin on any
  bead that is open, unassigned and unrouted, carries a `branch`, and carries no
  `merge_result`, `gc.run_target`, `gc.kind` or step key
  (`isDetachedHandoffOrphanCandidate`, `pool_detached_orphan_sweep.go:204-240`).
  A rejection takes exactly that shape at `rejection-repool.sh`'s unanchoring
  write, and keeps it while the rebuild runs, because a rebuild's workflow never
  claims its work bead. A pin left there would send the rejected bead straight
  back to the refinery. Today the handoff carries no pins, because the polecat
  clears its own and the refinery never claims, so `rejection-repool.sh` has
  never needed to clear them. Its unanchoring transition clears them too
  (unit 2).
- **It ends the claim before it reassigns.** bd refuses an assignee change on an
  in-progress bead from an actor that is not its holder, and the refusal drops
  every field batched with it. The holder's own clear lands.
  `docs/gascity-routing-model.md:47` records both from a live probe. So an exit
  that hands the bead to another identity writes the status first and the
  assignee after it, in separate writes, the order the polecat's submit already
  uses. Once the bead is open the guard no longer applies, whichever actor bd
  sees. The keeper race loss is one such exit.

The merge-push terminal transitions already pass `--assignee ""`. They add the two
pin unsets. Their `merge_result` keeps them out of the orphan sweep either way.

## 3. Failure exits move only their own bead

### The rule

A claim ends in an outcome or a named wait, and a session never drains holding
one. There are four exit classes:

| Class | Meaning | What the exit writes |
|---|---|---|
| **Outcome** | The bead left the refinery's queue for good: merged, gated (pre_open_gate or pull_request), handed back to its anchor, rejected to the polecat pool, or parked by its lifecycle state. | Unchanged, except that the claim's pins are cleared. |
| **Transient** | Nothing is shown to be wrong with the bead or the rig. A read or write did not land, a branch moved under a race, or the harness refused a command. | Release. The status goes to open, the assignee is cleared, the pins are unset, and the route, which the claim made the refinery's (section 2), is kept. A note names the exit. The queue offers the bead again. |
| **Person** | The bead asks for a decision only a person can make. | A demand. `gc-helm.sh demand <bead> "<question>" --topic refinery-<exit>` files a native human gate the bead is blocked by (`gc-helm.sh:1525-1555`), and the board shows the question. |
| **Rig** | Something outside the bead stops it, and would stop the next bead the same way: a pack defect, a rig setup fault, or a process on the host. | A finding. `patrol-finding.sh --scope refinery-findings --key refinery-<exit>` files one bead per fault, deduped on the key. The bead blocks on it. The finding's first reaction routes the fix to a pool, or puts it to the operator. |

A parked bead keeps its route, which the claim made the refinery's. Its wait is
an open blocker of its own, which holds it under the shared hold (section 2), so
the pool neither counts it as demand nor serves it. When the demand or the
finding closes, nothing holds the bead, and it is offered again, with no
deferred-dispatch arm and no re-sling. This is the raw pool routing case
load-context already describes: the work bead itself is the routed unit, so a
blocker of its own holds it.

### Bounding the retry without a clock

An unbounded release is a head-of-line wedge in a new form. The released bead is
still the oldest in its priority band, so the next session claims it first, fails
the same way, and drains. That loop burns a session per turn, and nothing reports
it. So the bead keeps a count, and the count is of claims, not of time.

- Once the claim's route reads back (section 2), `refinery-claim.sh` reads
  `refinery_attempts`. That counts the earlier claims of this bead that got this
  far and ended without an outcome or a wait. A crash counts, and so does a
  transient exit. A put-back from the route write does not.
  - If the count is two or more, the bead goes straight to a rig wait under
    `refinery-repeat-unresolved`, and the finding names the exits its notes
    record. The bead is not worked again.
  - Otherwise the script adds one to the count, and the session works the bead.
- An outcome or a park clears the count. So a bead re-offered after its wait
  closes starts fresh.

A bead therefore gets at most two claims that end without an outcome. That is the
same "start it once more, then escalate" rule the gate step applies to a gate cut
short (`mol-refinery-patrol.toml:515-521`). `refinery_attempts` is registered with
the merge-identity keys in `lifecycle/lifecycle.toml`.

### One writer for the waits

All three non-outcome classes go through one helper, `refinery-exit.sh`. It does
six things:

1. It reads and keeps the attempt count.
2. It writes the release, the demand or the finding.
3. It adds the `blocks` edge and reads it back.
4. It ends the claim.
5. It clears the pins.
6. It prints what it did, so the step can drain.

Each exit in the formula becomes one call naming its exit and its class. That
replaces about forty drain-ack lines, each of which composes its own handling.
It also follows PR #1217's way of keeping steps under the hook cap: a mechanical
block lives in a script, and the step calls it by name.

The helper refuses to block a bead on itself. The usual fix for a refinery fault
is the finding bead, and a polecat reworking that finding hands the finding itself
to the refinery. If its own fault stops it, its wait becomes a demand.

### Every exit and its wait

The table lists every exit in `mol-refinery-patrol.toml` at `132909cb5` that today
reads "leaving the work with the refinery", "ending the turn", "the next patrol
retries" or "STOP", plus the keeper's refinery exits. "Rig" names the finding key
after `refinery-`.

**Prepare (`rebase` step)**

| Line | Today | Class | Wait |
|---|---|---|---|
| 211 | The bead could not be read | Transient | Release |
| 219 | No `metadata.branch`, so there is nothing to prepare | Person | Demand: re-dispatch the work or drop the bead |
| 225 | The `prepare_mode` write was refused | Transient | Release |
| 242 | The rig root does not resolve | Rig | `rig-root-unresolved` |
| 254 | `detached-job.sh` not found | Rig | `pack-script-missing` |
| 257 | A gate left running will not stop | Rig | `gate-unstoppable`, put to the operator |
| 266 | The prep worktree cannot be staged | Transient | Release |
| 275-307 | The merge conflicts | Outcome | Rejection to the polecat pool (unchanged) |
| 300 | `rejection-repool.sh` not found | Rig | `pack-script-missing` |
| 307 | `rejection-repool.sh` exits 3 with the bead still routed to the refinery: it stopped before its unanchoring write landed, and no visit landed | Transient | Release. `reopen-source` has already reopened the bead and kept its route, so the bead is an offer again. |
| 307 | `rejection-repool.sh` exits 3 after its unanchoring write cleared the route: the rejection is recorded, but no pour was proved and no visit landed | Rig | `repool-unfinished`, with no edge. The bead has left the refinery's queue, and a pour may have started, so it is not released to the refinery. The finding carries the command that finishes the repool. |
| 307 | `rejection-repool.sh` exits 1 (usage) | Rig | `repool-refused` |

The two exit-3 rows are told apart by reading the bead's route. `reopen-source`
keeps it, and the unanchoring write clears it.

**Gate (`run-tests` step)**

| Line | Today | Class | Wait |
|---|---|---|---|
| 363, 478 | The rig root does not resolve | Rig | `rig-root-unresolved` |
| 371 | `detached-job.sh` not found | Rig | `pack-script-missing` |
| 372 | The prep worktree is missing | Transient | Release |
| 378 | The previous gate will not stop | Rig | `gate-unstoppable` |
| 391 | The rig's check commands cannot be read | Transient | Release |
| 407 | A check cannot be written | Transient | Release |
| 457 | The gate did not start (tk-rohu7om's refusal) | Transient | Release |
| 509-514 | The gate is still running after the limit, and its group survived TERM and KILL | Rig | `gate-unstoppable` |
| 515-521 | The gate was cut short twice | Person | Demand: land it, reject it, or re-run it |

**Failure triage (`handle-failures` step)**

| Line | Today | Class | Wait |
|---|---|---|---|
| 549, 556 | As 300 and 307 | As above | As above |
| 629 | `preexisting-failure.sh` not found | Rig | `pack-script-missing` |
| 640 | No failure key derived | Transient | Release |
| 660 | The duplicate probe could not be read | Transient | Release |
| 678 | The work bead could not be read | Transient | Release |
| 692 | No tracker was filed | Transient | Release |

**Land or gate (`merge-push` step)**

| Line | Today | Class | Wait |
|---|---|---|---|
| 755 | `lifecycle.sh` not found | Rig | `pack-script-missing` |
| 778, 809, 865 | The rig root does not resolve | Rig | `rig-root-unresolved` |
| 782-788 | The branch has no change against its target | Outcome | `refused_false_completion`, routed to a person with its visit (unchanged) |
| 828 | The direct push verified a different origin tip | Transient | Release |
| 838 | The direct push failed for a reason other than branch protection | Transient | Release |
| 880 | The mr push was rejected because the branch moved | Transient | One in-session re-fetch and retry, as today, then release |
| 891 | `existing_pr` failed validation | Outcome | `blocked`, routed to a person with its visit (unchanged) |
| 929 | The recorded PR does not match the branch or the target | Person | Demand: repair the PR record |
| 1012 | The rework read-back fetch failed | Transient | Release |
| 1019 | The rework head is not on origin | Transient | Release |
| 1029 | The rework close was refused after unanchoring | Transient | Release |
| 1032 | The rework could not leave its anchor state | Transient | Release |
| 1047 | The gating transition failed | Transient | Release |
| 1057 | The merge strategy is unsupported | Person | Demand: set a supported strategy |

**Steps that leave the formula**

| Line | Today | Disposition |
|---|---|---|
| 113 | `GC_AGENT` is empty | Deleted. The claim is gascity's, and the runtime supplies the identity. |
| 158 | The work list does not parse | Deleted. `refinery-offers.sh` exits non-zero on a read it cannot parse, rather than reading it as an empty queue. A failing work query makes `gc hook --claim` exit non-zero and claim nothing, and it writes no drain result, even with `--drain-ack` (`gc hook --help`). So the claim protocol drains the session itself, holding nothing. |
| 1105, 1112, 1119 | The next wisp could not be poured, assigned or burned | Deleted with the wisp loop. |

**The keeper's refinery exits (gascity rig only, `refinery-rebase-handling.template.md`)**

| Line | Today | Class | Wait |
|---|---|---|---|
| 74, 237-270 | The preflight refusal and the race loss (lease miss) | Outcome | The bead goes back to the keeper, its existing wait. It is written in the claim-safe order, status then assignee. The operator signal becomes a valid `escalate.sh --subject "$WORK" --key rebase-race-loss` call, which repairs tk-vfgmu8k. |

No bead reaches the table's "Release" more than twice. Its third claim finds the
attempt count at two and sends the bead to `refinery-repeat-unresolved` before
working it. In practice the transient rows are what tk-rohu7om's intermittent
refusal and an ordinary store blip look like: they cost one more claim, and only
for the bead they hit.

## 4. What wakes the pool

Routed demand wakes the pool. The controller runs the refinery's `scale_check`,
which counts tier 3 of `refinery-offers.sh`, the offers nothing holds, and the
old-style handoffs of tier 2 (section 2). Those are the
beads a session that holds nothing claims, so the demand count and the claim
agree. In bead-backed mode a pool's `scale_check` is its authoritative count of
new unassigned demand (`build_desired_state.go:1365-1368`). The controller runs
it whether or not a session is up, and wakes the slot, or creates one, when the
count is above zero and the cap has room. A bead blocked on a wait is not
counted, so it does not wake the pool.

An old-style handoff needs the count. gascity's resume tier files assigned work
under the template its route names, or under the template of a session that
holds its assignee (`computePoolDesiredStatesAt`,
`pool_desired_state.go:354-382`). An old-style handoff has no refinery route,
so while no session holds the alias it wakes nothing there. The pre-cutover
text's own `gc session wake` reaches only a session row that already exists
(section 8).

gascity's idle-claim backstop (`idle_nudge.go:45-98`) nudges a running pool slot
whose trigger offer stays unclaimed, and recycles it after three tries. It needs
a trigger bead. The refinery's custom count supplies none, and gascity's
cold-pool probe supplies one only for an offer its default query can see
(section 2). So the backstop serves a refinery session woken for an ordinary
offer, and not one woken only for an offer under a parked epic or for an
old-style handoff. Every refinery session that sits at its prompt without
claiming while an offer waits is caught by the alarm in section 5. That alarm
files its finding at the second pass that sees nothing taken and nothing held,
and the finding's first reaction puts the stopped session to whoever can act on
it. gascity gc-9h08f6, a `scale_check` that names the beads it counts, would
extend the backstop to every offer.

So the design adds no nudge and no wake order. It deletes the polecat's step-6
wake and nudge, and the keeper's.

## 5. Backpressure and the one alarm

### Backpressure

Offers that wait while a refinery claim is held are backpressure: one session is
busy and the queue behind it grows. The refinery-reconcile pass writes one note
line in its pass log. The line says how many offers wait, which bead is held, and
how long the oldest offer has waited. The age is information, not a threshold. A
held claim never raises the alarm, however long the queue gets. A claim whose
holder has stopped is I11's to report (section 2).

### The alarm

**Predicate**, per rig, evaluated once a pass. All four conditions must hold:

1. At least one offer waits. The offers are the beads the demand count counts:
   tier 3 of `refinery-offers.sh`, and the old-style handoffs of tier 2
   (section 4).
2. No in-progress bead is routed to the refinery. That is, the refinery holds
   nothing.
3. Every offer that was waiting at the previous pass is still waiting, with the
   same `refinery_attempts`. That is, the pool took nothing since the last look.
   The count matters because a claim raises it even when its exit releases the
   bead again, so a bead claimed and released between two passes waits at both.
   The pass's state directory keeps the previous pass's offer ids and counts. A
   pass whose read of the offers fails records nothing (section 2), so the
   comparison is always between two passes that read them.
4. Neither the refinery agent nor its rig is suspended. A suspended pool is a
   note.

**What it files.** One finding per rig, through `patrol-finding.sh --scope
refinery-findings --key refinery-offers-untaken`. It goes through the same writer
`merge-tail-report.sh` already uses from inside the reconcile pass. The message
names the waiting offers and the refinery session's state from `gc session list`.
A recurrence updates the one finding's occurrence count, so a lane-wide failure
is one bead, not one per handoff. The finding's first reaction disposes it, and it
can put it to the operator. The alarm never retracts itself. A retract through
`escalate.sh --retract` records a moot verdict, and escalate.sh's 24-hour window
would then mute every recurrence for a day. That is the case tk-eiphpx and
tk-5ogyne report, and the initiative rules out patching the window for it.

**Why the merge cadence hosts it.** The refinery-reconcile order runs every pass
for every rig, with no session. It keeps running while the refinery session is
dead, idle or wedged, because it is the cadence half of the refinery. A pass
already reads the rig's anchors, and the alarm adds two reads. Two other hosts
were considered:

- **The deacon's doctor sweep**, where I14 runs today. It collected no result from
  2026-10-13T17:25Z to 2026-10-14T21:00Z. No deacon finding's `finding.last_seen`
  falls inside that window. The stamps before it cluster at 10-13 17:19Z-17:25Z,
  and the stamps after it at 10-14 21:00Z-21:01Z. No check reads whether the
  sweep's results keep arriving (tk-dk2aqb7).
- **The witness patrol**, where the timer runs today. No check reads whether the
  witness's patrol is cycling.

**Why it is not a clock.** Nothing in the predicate is a duration. Condition 3
compares two observations: was anything taken between them? gascity gives a fresh
slot a 90-second grace to claim before its backstop first nudges it
(`idle_nudge.go:57`). Passes are at least 60 seconds apart and usually further,
because the supervisor fires a short-interval order once per trip of its dispatch
rotation (I10's description). So a working pool almost always takes something
between passes. The finding's first reaction dismisses the rare false start.

**What notices when the host goes silent.** I10 (`doctor/check-cadence-live`)
reports any order the pack ships that has not fired within its cadence window.
refinery-reconcile is registered once per rig, so I10 names the rig. A silent
reconcile also stops every merge and every PR open on that rig, so the silence is
not quiet in effect. I10 runs in the doctor sweep. A silent reconcile together
with a silent sweep is a double fault that this design leaves to tk-dk2aqb7.

### A handoff the walk cannot read

The pass reads the same walk as the claim, so it also sees a bead that tiers 2
and 3 select and whose only holds are unread: a blocker of its own that the rig's
store does not return. Such a bead is not an offer, so it never meets the alarm's
first condition. Nothing will release it either, because the walk cannot see its
blocker close. So the pass files it under its own key, `refinery-offer-unread`,
through the same writer as the alarm. That is one finding per rig, whose message
names each such bead and the ids the walk could not read. The doctor check
`check-armed-dispatch-owed` reports an arm in the same state as one it could not
check.

## 6. What the design deletes

- **The witness's `check-refinery` step**, `mol-witness-patrol.toml:862-1029`. That
  includes the `refinery-stuck-escalate` block and its retract arm, the keys
  `witness-refinery-queue`, `witness-refinery-queue-unroutable` and
  `witness-refinery-queue-unreadable`, and the block's test. `next-iteration`
  then follows `recover-orphaned-beads`, and the formula's scope line drops
  "watches the refinery queue". PR #1217's move of the block into
  `refinery-stuck-escalate.sh` is superseded: the script is deleted with the step.
- **The 24-hour-mute case.** It retires with the timer. Nothing escalates per
  handoff any more, so a moot verdict has nothing to mute. Open
  `witness-refinery-queue` visits are closed at cutover with outcome `moot` and a
  note naming this design.
- **I14 (`doctor/check-refinery-patrol-live`).** I14 dates a patrol by its wisp,
  and there is no wisp any more. Its job splits two ways. Offers that wait while
  nothing is held go to the alarm. A claim nothing advances goes to I11's widened
  arm 1. The run-tests wait's note on the patrol wisp exists only for I14
  (`mol-refinery-patrol.toml:467-470`, `:487-500`), and it goes too.
  tk-16ku05d, which reads the gate record into I14, is superseded.
- **The patrol wisp loop.** This is the prompt's adopt-before-pour reconcile and
  its "Patrol lifecycle" section (`agents/refinery/prompt.template.md:35-86`).
  It also covers the formula's `validate-identity`, `check-inbox`, `find-work`,
  `patrol-summary` and `next-iteration` steps, and the tests that extract their
  blocks (`find-work-gating-guard`, `patrol-wisp-reconcile`, `patrol-pour-vars`).
- **The refinery's `[[named_session]]` stanza** in `pack.toml`.
- **The wake and nudge** in the polecat's submit step and in the keeper's handoff.
- **Its own debris.** Between 10-06 and 10-08 the witness filed nine findings
  about its own stale or malformed `witness-refinery-queue` visits, among them
  tk-3auvams and tk-gp6rwuh. That class has no writer once the step is gone.

## 7. Mail state moves to beads

`mol-refinery-patrol.toml:127-128` tells the refinery to read its inbox for
"priority overrides, hold requests". No script or formula in the pack mails the
refinery. The only `gc mail send` naming it is the keeper's completion mail, which
goes to the operator. So the mail is a channel a person might use, and two bead
states already carry both kinds of request, both read by the claim itself:

- **A priority override is the bead's priority.** The routed tier claims in
  priority order, so writing a handoff's priority reorders the queue. Today that
  write is `gc bd update <bead> --priority <n>`. Once steer-by-epic's priority
  unit lands, it is `gc-helm.sh priority`, which keeps the queue's own priority
  pass from re-deriving the override away (`specs/tk-rl8gz4b.2/steer-by-epic.md`,
  unit 5).
- **A hold request is a `blocks` edge on the handoff itself.** The claim serves
  no bead with an open blocker of its own, and none with a dispatch-hold label, so
  a held handoff is not claimed until the hold is lifted. A park on the handoff's
  epic does not hold it, because a handoff is in flight and steer-by-epic leaves
  in-flight work running. For the same reason `gc-helm.sh park` refuses a bead in
  flight, so the edge is written with `gc bd dep add <handoff> <gate>`. The edge
  stays on the bead after it is gated, and `merge.sh` holds an anchor's merge on
  any open blocker of its own. So a held handoff stays held through its merge until
  the edge goes, which is what a hold on that work means.

The `check-inbox` step is deleted. Mail sent to `<rig>/gc-toolkit.refinery` still
delivers, because the alias is stable, but nothing reads it as state.

## 8. Merges stay serialized

gascity's session-model design counts every active or creating session of a
template against `max_active_sessions` (`engdocs/design/session-model-unification.md:1212-1233`).
The reconciler this city runs bounds each start path on its own. These are the
paths that can start a refinery session:

| Path | Bounded by |
|---|---|
| Pool demand | `capNewDemandCount` caps new sessions at the template's maximum less its accepted requests (`pool_desired_state.go:1368-1398`), and a session holding a claim is one of those (`:532`). A pool session that has not claimed yet takes the first new-demand slot before any new session is created (`:537-544`, `:583-604`), and a create in flight is counted (`:572-580`). So at a cap of one, a session that holds a claim, or one that is about to claim, leaves no room for a second. |
| Explicit wake (`gc session wake`) | It wakes a session row that already exists, and creates one only for a configured named session, which the refinery no longer has (`resolveSessionIDMaterializingNamed`, `cmd_session_wake.go:105`). The legacy reconciler applies no cap to a wake (`compute_awake_set.go:298-305`). gascity's v2 allocator, whose `underMaxActive` would (`allocator_decide.go:778-806`), is refused while any agent declares a custom `scale_check` (`reconcile_latch.go:39-82`). A wake by the alias reaches the one row that holds it. A wake of another row by its id is an explicit operator action, like a manual session. |
| The named session | Removed. |
| `min_active_sessions` floor | Zero. |
| Dependency floor | No agent depends on the refinery. |
| A manual session (`gc session new`) | A manual session may soft-exceed the cap, because it is an explicit operator action (`session-model-unification.md:1231-1233`). It cannot claim an offer unless an operator gives it the refinery's alias by hand, because tier 3 of `refinery-offers.sh` keeps gascity's origin gate (`workquery.go:931-938`). A manual session that holds the alias also stops the pool from minting one beside it, as below. |

tk-77txj0 reports a named path and a pool path that do not share a count. At
`46db7fbee` a session outside the pool that holds a canonical singleton's alias,
as the named session does, stops the pool from minting a standby beside it
(`canonicalSingletonAliasHeldTemplates`, `pool_desired_state.go:745-785`,
applied at `:569-571`). The check skips the pool's own sessions, which the pool's
count bounds. With the named path removed, the pool is the only automated path,
so the question has no second path to ask about.

The merge itself stays where it is. `merge.sh` runs in the refinery-reconcile
pass under its per-rig flock, and the refinery session's direct-mode push runs
inside its one claim.

## 9. What belongs upstream in gascity

- **A shared count for named and pool sessions (tk-77txj0).** Nothing to file.
  gascity already suppresses a pool standby beside a named session that holds the
  alias at a cap of one (section 8). This design removes the second path.
- **A custom `work_query` and `scale_check` for the refinery.** Needed, and they
  stay. gascity's default routed tier and demand count read `bd ready`, which
  holds a parked epic's members, and a handoff is in flight (section 2). The
  custom queries are how the refinery reads readiness through the pack's one
  definition of a hold, so no gascity readiness option replaces them: its rule
  would be a second definition beside `hold-lib.sh`. What the refinery lacks is
  concrete demand. A custom `scale_check` prints a count (`parseScaleCheckCount`,
  `cmd/gc/pool.go:234-247`), so a session started only for that count has no
  trigger bead, and the idle-claim backstop does not serve it (section 4). Filed
  as gascity gc-9h08f6: let a `scale_check` name the beads it counts. gascity
  gc-tj666s asks for own-blocker readiness as a pool option. That is such a
  second definition, so the refinery would not adopt it, and the bead's notes say
  so.
- **The repeated `--status` trap behind tk-cg7k9zi.** Filed as gascity gc-3zov2j.
  `gc bd list --status=open --status=in_progress` keeps only the last value. A
  live probe on the polecat route returned 4 rows that way against 57 for
  `--status=open,in_progress`. This design removes the refinery's hand-written
  queue read, but the trap stays for every other agent.

A controller-level alarm for "routed demand no session takes" would generalize
section 5 to every pool. It is not filed. For a pool on default demand, gascity's
idle-claim backstop already rescues a live, idle slot. The remaining case, a
session that cannot start, already shows in gascity's session states and
provider-health alerts.

## 10. Inputs accounted for

| Input | Disposition | Why |
|---|---|---|
| tk-8pq6dk, the bespoke claim-route gates | Partly absorbed; left open, narrowed | Site 1, the submit handoff's tail-match roster check, is replaced by the route `pool-route.sh` proves. Site 2, the witness's refinery query, is deleted with the timer. Sites 3 and 4, `first-reaction-dispose.sh` and `gc-proactive.sh`, have nothing to do with the refinery and stay in tk-8pq6dk. |
| tk-77txj0, two materialization paths | Absorbed | The named session is removed. The pool is the only automated path, and the cap holds on it (section 8). The four town-repo cap patches it mentions stay the operator's to remove. |
| tk-cg7k9zi, the 6.5h idle on a hand-written read | Absorbed; its second remedy filed upstream | The claim is `gc hook --claim`, so no refinery session composes a queue read, which is the class the bead names. Its second remedy, making the CLI refuse the repeat, is gascity gc-3zov2j. |
| tk-55vtleo, wake_mode=fresh kills the next bead's work | Superseded | There is no wisp rotation, and the only assignment is the session's own claim, which the fresh cycle skips (section 2). |
| tk-16ku05d, I14 reads the gate record | Superseded | I14 is deleted. |
| tk-vfgmu8k, the race-loss escalation never files | Absorbed | The race-loss exit is rewritten for the claim-safe order, and its escalation call is corrected in the same edit. |
| tk-rohu7om, the refused gate start | Trigger fix stays separate | Its fix belongs to the gate-start block or tk-b0ww25t's cutover. This design removes the structure that let one refusal hold the queue for 13 hours: the refused start is a transient exit, the bead gets one more claim, and then only that bead waits. |
| tk-s0jfq7k, the parked refinery and review-lane epic | Members dispositioned here; the epic stays | The members that share this design's cause are tk-cg7k9zi, tk-vfgmu8k and tk-8pq6dk, above. tk-t8makac, tk-dz0xss and tk-r5ofy4t touch `mol-refinery-patrol.toml`, but each has a cause of its own (a control-byte fail-open, a vestigial var, git calls that read cwd), so they stay separate. The implementation re-checks each against the formula it ships. The other members are merge-cadence and review-lane defects with other causes. |
| PR #1217, the formula step size cap | Its `refinery-stuck-escalate.sh` move is superseded; the rest merges in | The move is superseded because the step is deleted. Its `submit-and-exit.sh`, `direct-merge-push.sh`, `one-anchor-per-pr.sh` and `zero-diff-guard.sh` hold blocks this design edits. The implementation edits whichever form is on the integration branch when it starts. Every step it edits stays under #1217's 9,000-character rendered bound. |
| PR #1249, run cancel and work-bead waits | Overlaps files; no conflict of design | It edits `mol-polecat-work.toml`, `mol-witness-patrol.toml`, `orphan-dispose.sh`, `lifecycle.toml`, `liveness-sweep.sh` and `gc-helm.sh`. The refinery's waits need none of its `await-ruling.sh` machinery, because a parked offer keeps its route and its edge's close re-offers it. Whichever lands second merges the other in. |
| tk-eiphpx and tk-5ogyne, the 24h mute | Retired | Both already fold into tk-zvu0bd6. The mute needs a per-handoff escalation, and the timer that filed one is deleted. |

## 11. Implementation breakdown

These units are for the implementation child tk-fhkllrb. All of them land on
integration/tk-alyaztk, and the convoy graduates to main as one PR. So the order
below is the build order. Nothing reaches production until graduation, which is
why the writers and the refinery can change in separate units without a window
where one speaks the old shape to the other.

1. **The exit writer.** Write `assets/scripts/refinery-exit.sh` and its test. It
   covers release, demand and finding, the attempt count, the edge read-back, the
   self-block refusal, pin clearing, and the unfinished repool's finding, which
   takes no edge. Register `refinery_attempts` in `lifecycle/lifecycle.toml`. The
   test covers each class against a bead held in progress under the alias, a
   crash count reaching two, and an edge that fails to land.
2. **The refinery pool.** This changes `agents/refinery/agent.toml` (min 0, max 1,
   the claim nudge that runs `assets/scripts/refinery-claim.sh`, and the
   `work_query` and `scale_check` that call `assets/scripts/refinery-offers.sh`),
   adds both scripts, and deletes the stanza in `pack.toml`.
   `refinery-offers.sh` reads readiness only through `hold-lib.sh` (section 2).
   It sources the file, builds its graph with `hold_graph` over a reader of the
   rig's own store, and applies `$HOLD_JQ`. It joins the readers that
   `hold-lib.test.sh` lists, so that test fails if the script stops sourcing the
   file, applying the predicate, or building its graph with `hold_graph`. The unit
   also names the script wherever the hold's readers are listed: the header of
   `hold-lib.sh`, its row in `docs/component-model.md`, and `docs/steering.md`'s
   account of what a park holds and leaves running, which says a park holds every
   pool-routed member.
   `refinery-offers.sh`'s test covers these cases: a handoff under a parked epic
   is listed and counted; a handoff with an open blocker of its own is not; the
   in-flight, pinned-blocker and unread-blocker cases of `hold-lib.fixture.json`,
   each with its bead routed to the refinery, list a bead exactly when the case
   finds nothing holding it; a walk whose read fails makes the script exit
   non-zero; an old-style handoff, assigned to the alias with no route, is
   listed and counted; the session's own in-progress claim comes first; and the
   sort is priority, then age. `refinery-claim.sh`'s test admits an old-style
   handoff written after the named session has retired, so nothing has routed
   it, and another that also carries an archived `gc.run_target` naming the
   polecat pool. For each, it
   proves that the claim writes the refinery's route, unsets `gc.run_target` and
   reads both back before it reads the attempt count. Through unit 1, it then
   proves that a transient release leaves an offer `refinery-offers.sh` lists in
   tier 3, and that a person wait and a rig wait each leave one once their
   blocker closes. When a route write does not read back, the old-style handoff
   goes back open under the alias, still listed in tier 2, and a tier-3 offer
   whose `gc.run_target` did not clear goes back open and unassigned, listed in
   tier 3. Neither counts an attempt. The prompt
   (`agents/refinery/prompt.template.md`) describes the claim
   protocol and drops the wisp reconcile. In `mol-refinery-patrol.toml`, the loop
   steps are deleted, the claim's `$WORK` is used, every exit goes through unit 1,
   and the terminal transitions clear the pins. `rejection-repool.sh`'s
   unanchoring transition clears them too (section 2). The formula's block tests,
   `rejection-repool.test.sh` and `refinery-escalation-wiring.test.sh` follow the
   edits. It depends on unit 1.
3. **The handoff writers.** These are the submit handoff (the route through
   `pool-route.sh`, with no wake or nudge), `convoy-graduate.sh`, the keeper's
   `mol-upstream-gc-rebase.toml` handoff, and its `refinery-rebase-handling` race
   loss. The unit also covers the readers of the old shape: the load-context gate
   and the `gc-helm.sh` rider proof. Their tests follow, including
   `submit-branch-gate.test.sh`. It depends on unit 1, for the race-loss exit.
4. **The claim's readers.** Widen I11 arm 1 to routed pool claims. Add the
   `orphan-dispose.test.sh` fixture, the census fixture, and the witness's orphan
   recovery prose, which keeps the refinery's alias an infrastructure owner
   (section 2).
5. **The alarm and the deletions.** Add the refinery-reconcile alarm arm, its
   `refinery-offer-unread` report (section 5) and their test. Delete I14, the
   witness's `check-refinery` step and its test
   (`refinery-stuck-escalate.test.sh`), the `witness-refinery-queue` assertion in
   `witness-escalation-wiring.test.sh`, and the run-tests wisp note.
6. **Documents.** The central docs that describe the refinery's intake change with
   the unit that makes them stale: `docs/refinery-merge-cadence.md`,
   `docs/gascity-routing-model.md` (the handoff and claim rows),
   `docs/state-machine.md`, `docs/authority-map.md` (the new writer, and who writes
   a refinery wait) and `docs/architecture.md`. `docs/component-model.md` and
   `docs/steering.md` name the hold's new reader (unit 2). Each unit carries its
   own document edits rather than a final docs pass.

The design splits into units by surface, not by risk, so a reviewer reads each
unit against one part of this document.

## 12. Cutover

Graduation deploys every unit at once, and the hand steps below go with it. They
are recorded in tk-fhkllrb's notes when run, and no script for them lands in the
repo.

1. As the last act before graduation, list the old-style handoffs on each rig:
   open beads assigned to `<rig>/gc-toolkit.refinery` whose route is not
   `<rig>/gc-toolkit.refinery`. On each, set
   `gc.routed_to=<rig>/gc-toolkit.refinery` and unset `gc.run_target`, the same
   write the claim makes (section 2). The old refinery reads its queue by
   assignee, so nothing changes for it, and the retirement then releases each
   one on that route (section 1). After graduation, confirm that every listed
   handoff was released onto the refinery's route. A handoff submitted between
   the write and graduation is routed by the release itself, so check those too.
   Any left assigned are still served by the claim's second tier, which routes
   each one as it claims it.
2. Burn each rig's `mol-refinery-patrol` wisps.
3. Close the open `witness-refinery-queue` visits as moot, naming this design.
4. Confirm one refinery session per rig: `gc session list` shows at most one
   session per rig with an active or creating state.
5. Each pre-cutover molecule writes its old-style handoff when it submits. Check
   that the query from step 1 drains to zero as those molecules finish.

## Alternatives considered

- **Keep the named session, and route instead of assign.** gascity's routed-demand
  wake and self-target claim would let a named refinery claim routed work. It is
  not chosen, for the reasons in section 2: a named identity's claim survives its
  session in the dead-assignee sweep, it gets no idle-claim rescue, and two
  materialization paths would remain.
- **Pour a `mol-refinery-work` molecule per handoff.** This puts the refinery's
  steps on graph.v2 step beads, which I11 already covers. It is not chosen: the
  handoff bead would go back to being an unclaimed anchor beside a molecule. That
  is the shape whose "unassigned is not idle" readers this design exists to stop
  needing.
- **Move the parked bead to the back of the queue, instead of counting attempts.**
  Claim order is priority, then age, so moving a bead back means rewriting its
  priority or its creation time. Both are facts other readers trust.
- **Route a parent-less offer bead instead of the work bead.** An offer bead with
  no parent escapes the epic cascade by construction, so gascity's default query,
  default demand and idle-claim backstop would all apply unchanged. It is not
  chosen, because it moves the claim onto a second bead that must be kept
  consistent with its work bead. That means one live offer per work bead, an offer
  left stale when its work bead moves on, and a crash window between the work
  bead's transition and the offer's close. Readers would also have to follow the
  offer to the work bead, and the offer's readiness would be `bd ready`'s rule
  rather than the pack's hold. The custom query costs one script and, until
  gascity gc-9h08f6, the backstop for offers under a parked epic.
- **Let a park hold handoffs.** This keeps gascity's default queries and needs
  nothing custom. It is not chosen, because it reverses steer-by-epic's approved
  rule that a park leaves in-flight work running: a branch already built would
  wait for the unpark before it is gated.
