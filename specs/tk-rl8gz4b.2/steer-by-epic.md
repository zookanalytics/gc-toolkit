---
name: Steer work by epic — park gate, priority flow, placement
description: The design for the epic "Steer work by epic" (tk-rl8gz4b). It settles how an epic's priority, or its park, decides when the epic's work runs. It covers the park gate that holds a whole subtree, how armed and slung work stays parked, why a decision gate is not a park, how the epic's priority reaches the polecat queue and already-poured workflows, where PR-finishing work ranks, which checks and boards must read a park, how intake holds findings for the placement sitting, and how a Checkpoint records the next priority. It lists the implementation units. Read it to review the design or to build one of its units.
---

# Steer work by epic

## The decision

The operator steers polecat capacity by epic. An open epic is at P0, P1 or P2,
or it is parked. Work under an epic queues at the epic's priority. Nothing new
starts under a parked epic, and work already in flight finishes. This design does
that with bd's own blocks edges, the parent-child cascade and bead priorities. It
needs no gascity change.

The operator steers with these moves, each one command:

- `epic-steer.sh park <epic>` holds everything under the epic that has not started.
- `epic-steer.sh unpark <epic> <P0|P1|P2>` releases it at a priority.
- `epic-steer.sh priority <epic> <P0|P1|P2>` re-ranks the epic's work, including
  workflows already poured.

The operator has ruled on what a park holds and what it leaves running.

- **A park holds everything under the epic that has not started, armed work
  included.** Deferred dispatch does not sling armed work past a park gate.
- **Waiting on the operator's decision is not a park.** An epic blocked only by a
  demand gate, the human gate a converse hold files, keeps dispatching its armed
  work as each bead's own blockers close, as it does today. The two gates carry
  different markers, `gc.park_gate` and `gc.demand_for`, and deferred dispatch
  reads them (section 2).
- **Every other hold on an epic holds its armed work too.** A prerequisite task is
  the common case. The Checkpoints epic (tk-wmwcdlc) waits on the close-gate task
  (tk-isd5sa), so its armed work waits for that task to land.
- **Existing PR work keeps moving under every hold on its epic.** Merges of
  approved PRs, review reworks, merge-ins, red-check fixes and validation passes
  go on. This is an invariant of the graph, not an exception path. PR-finishing
  work is never filed as a parent-child descendant, so no cascade reaches it
  (section 7).

Each of these recommendations still needs a yes or a no.

1. **An item placed under an epic is worked by proxy.** Once an item is under
   an epic at P0 to P2, it runs at that epic's priority with no further move. Under
   a parked epic it waits. The epic's priority is the operator's standing go.
   *Cost:* an item placed under the wrong epic spends capacity in that epic's
   band until the next sitting moves it. *The alternative*, link only, costs one
   operator decision per item and leaves an active epic's new defects unworked
   between sittings.
2. **PR-finishing work runs ahead of new work.** Conflicts, red checks, review
   reworks and reviews run at P0 once the PR is approved. Before approval they run
   one band above their epic. *Cost:* at P0, age alone decides, so another epic's
   approved PR can wait behind older new work of a P0 epic. *The alternative*,
   finishing at the epic's own priority, leaves approved PRs queued behind new
   work of the same band, which is the problem as filed.
3. **Nothing associates findings with an epic automatically yet.** That
   classifier belongs to the first-class-epics epic (tk-rctkrj), which is parked.
   Until it lands, every non-emergency finding waits for the placement sitting.
   *Cost:* one sitting decision per finding. *The alternative* is to move the
   classifier unit under this epic and unpark it here.

Waiting has a cost. Today a hand sling or any newly armed bead under a parked epic
starts work. Priority does nothing yet: work queues at whatever priority each bead
was filed with. Patrol findings still become polecat work. The board shows every
parked epic as stalled. [What waiting costs](#what-waiting-costs) has the detail.

## Facts this design rests on

Each fact below was read or measured on 2026-10-10 or 2026-10-11. Source paths
name the gascity fork (`rigs/gascity`, HEAD `e1f4eef5e`), the beads module bd
runs (v1.3.1), or this repo.

1. **Claims follow priority.** The pool's routed claim tier reads `bd ready` with
   no `--sort`. It therefore gets bd's default order: priority, then `created_at`,
   then id (gascity `internal/config/workquery.go:393-408`; beads
   `internal/storage/sqlbuild/ready.go:55-56`). gascity #5629 (`48d68d13a`) made
   that change. The running `gc` build (`254144dec`) contains it. `gc hook --claim`
   takes the first row it can claim in that order. A session that already holds a
   workflow takes that workflow's own steps first, before any fresh pool work
   (`workquery.go:880-907`, tier order at `:1028-1044`). So in-flight work
   finishes ahead of new work whatever the priorities. The claim-predicate row of
   [gascity-routing-model.md](../../docs/gascity-routing-model.md) still quotes
   `--sort oldest`, which no longer holds.
2. **A pour copies priority once.** `gc sling --on` creates the input convoy at
   the work bead's priority (`internal/graphv2/invocation.go:439-444`). It then
   pours the workflow root and every step at the convoy's priority
   (`internal/sling/sling_core.go:603-607`,
   `internal/molecule/graph_apply.go:165-185`).
   Nothing writes priority after the pour. Nodes fanned out later take the root's
   priority at that moment (`internal/molecule/molecule.go:1152-1159`). A plain
   route leaves priority alone.
3. **The cascade reaches members, not poured workflows or PR-finishing work.** bd
   marks a bead blocked when a parent-child ancestor is blocked, and `bd ready`
   excludes it
   ([gascity-routing-model.md](../../docs/gascity-routing-model.md#the-blocked-flag-cascades-down-parent-child-edges)).
   A poured workflow's root has no parent, and its steps hang off it by `tracks`
   edges, so the cascade never reaches a workflow already poured. PR-finishing
   children carry a `blocks` edge to their anchor and no parent edge, so it does
   not reach them either.
4. **`bd blocked` lists a cascade-held bead under its own id**, with its parent
   named as the blocker. In a live read of gc-toolkit, tk-8gradm4.4 showed
   `blocked_by=["tk-8gradm4"]`. The header of
   `doctor/check-armed-dispatch-owed/run.sh` (lines 15-19) says the opposite, and so
   does [component-model.md](../../docs/component-model.md) (lines 199-200).
5. **bd refuses a close only for a live direct blocker.** A bead blocked only
   through its parent closes normally (beads
   `internal/storage/issueops/close.go:43-53`, `:155-160`). So a merged anchor under
   a parked epic still closes. A bead parked by its own edge cannot close until the
   edge is removed.
6. **Deferred dispatch ignores ancestors.** Its reconcile slings an armed bead
   held only by an ancestor once the bead's own blockers close
   (`assets/scripts/deferred-dispatch.sh:8-13`, `:314-323`). The bypass came from
   tk-so8clv (#857). There, a converse demand gate on the epic tk-6bji7k held its
   children's arms for days.
7. **No sweep closes or visits a bare gate.** The core gate sweep evaluates only
   timer and GitHub gates (gascity
   `internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). The gate-visit
   sweep keys on `gc.demand_for`. A gate carrying neither an await type nor that
   key is left alone by both.
8. **The park in place today was built by hand on 2026-10-10.** There is one gate
   per store; gc-toolkit's is tk-u5t8h6x. In gc-toolkit, 77 beads carry a direct
   edge to it: the parked epics, plus the items mechanik parked one by one because
   they could have started on their own. Another 201 beads are held through those
   edges. Of the 201, 196 have neither a route nor an arm, 5 are routed, and none
   is armed, because mechanik gave every armed bead its own edge (from
   `gc bd blocked --json`, 2026-10-11 00:05Z).

## 1. Epic priority and parking

**The steering state.** An open epic's steering state is its bead priority, P0,
P1 or P2. The one exception is an epic carrying an open `blocks` edge to its
store's park gate. That epic is parked, and its priority field is not read.

**The park gate.** Each store has one park gate. It is an `issue_type=gate` bead
that is never closed, marked with `gc.park_gate=true`, a key registered in
`lifecycle/lifecycle.toml`. It carries no await type and no `gc.demand_for`
(fact 7), and none of the `[holds]` markers that `check-wait-is-an-edge` reads. It
sits in the same store as what it parks, because bd resolves edges within one
store. Closing it would unpark everything at once, which is why nothing closes it.

**The predicate.** A bead is parked when it is open, and it or one of its
parent-child ancestors has an open `blocks` edge to a park gate. One shell
definition, `assets/scripts/park-lib.sh`, serves every shell reader, the way
`dispatch-path.sh` defines a dispatch path once. The helm board mirrors the
predicate in Go, pinned to the shell copy by a shared fixture.

**In flight.** A bead is in flight once work on it has started. It carries
`branch`, `merge_result` or `rejection_reason`, or a workflow poured for it has
passed load-context.

**What a park holds.** A park holds work that has not started:

- pool-routed members, through bd's cascade, which already works (fact 3);
- armed members, through deferred dispatch (section 2);
- members slung by hand, through the load-context guard (section 2);
- items placed under the epic later, through the same cascade (section 5).

**What a park leaves running.** A park leaves in-flight work running. A poured
workflow is out of the cascade's reach. PR-finishing work has no parent edge, and
section 7 makes that an invariant. The anchor itself is a member, but nothing that
drives it reads its parent. The refinery's find-work lists its handoffs with
`bd list`, not `bd ready`. `merge.sh` enumerates anchors by `merge_result`, and the
only edges it reads are the anchor's own blockers and children. None of
`pr-facts.sh`, `gate-ensure.sh` and `pr-open.sh` reads `bd ready`, `bd blocked` or
a parent edge. So a parked epic's open PRs still merge, and an anchor whose PR
merges still closes (fact 5).

One in-flight path does get held. When the refinery patrol rejects a handed-off
bead, its rebase and handle-failures steps route the work bead itself back to the
pool (`formulas/mol-refinery-patrol.toml`). That bead is a member, so the cascade
holds it. Unit 4 dispatches the rejection as a pour instead, which the cascade does
not reach.

**The moves.** `assets/scripts/epic-steer.sh` carries them, shaped like
`deferred-dispatch.sh`: verbs plus a reconcile.

- `park <bead>` writes the edge and reads it back. It prints what is now held and
  what stays in flight. When the store has no gate yet, it creates one, marker
  included. It refuses a bead in flight. That bead's own edge would be a live
  direct blocker. `merge.sh` holds an anchor's merge on any open blocker of its
  own, and bd refuses its close after the merge (fact 5). Any bead can be
  parked, so a loose item the operator wants held takes its own edge, as today.
- `unpark <epic> <P>` sets the epic's priority and runs the priority reconcile
  over the subtree at that priority while the park still holds it. It removes
  the edge only once those writes read back, so no member is released at its old
  priority (section 3). It also names every other open `blocks` edge on the
  epic, because each one still holds the subtree. Today the Checkpoints epic
  (tk-wmwcdlc) and the responsive-PR-workflow epic (tk-hf7nadf) both wait on the
  close-gate task (tk-isd5sa).
- `priority <epic> <P>` sets the priority and runs the reconcile. It refuses a
  parked epic and names `unpark`.
- `status` prints one row per open epic: its state, and how many of its beads are
  held, in flight and ready. It flags an unparked epic outside P0 to P2.

Each move records the state it set (`epic_steer`) and who set it and when
(`epic_steer_by`, `epic_steer_at`). Given `--evidence <visit>`, it also records
`epic_steer_evidence` (section 6).

**The shape law.** I1's shape law says containers do not block
([component-model.md](../../docs/component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law)).
The park gate is the one sanctioned exception, and the doc says so. Its purpose is
the cascade itself: parking an epic parks all of its parts, and that is the
reading of containment the shape law's own rationale gives. Every other `blocks`
edge on a container remains a violation.

**Rejected.**

- *Status deferred on the epic.* bd's cascade does not follow status, so the
  children stay in `bd ready`. That is why the hand-built park moved to the gate.
- *A future `defer_until` on the epic.* bd drops the children of a deferred parent
  from ready, but the date has to be invented, and the field means "not before a
  date", not "until the operator says".
- *One gate per epic.* This is the same mechanism with more beads. One gate per
  store lets every reader find the gates with one read.

## 2. Armed and slung work stays parked

**Kinds of blocker.** Each blocker on an epic is a park gate, a decision gate or a
real prerequisite, told apart by what it carries.

- *A park gate* carries `gc.park_gate=true` (section 1). It is the operator's "not
  now", and it holds every descendant that has not started, armed ones included.
- *A decision gate* carries a non-empty `gc.demand_for`. `gc-helm.sh demand` files
  it as a human gate and stamps the key with the bead it gates. A converse hold on
  an epic files one gated on the epic itself, because `converse-hold.sh` moves the
  demand to the visit only for a PR anchor. It waits on the operator's answer, so
  it is not a park, and the epic's armed work keeps dispatching.
- *Anything else*, such as a task the epic waits on, is a real prerequisite. It
  holds the epic's armed work, as the cascade already holds its routed work.

A visit is none of these. `escalate.sh` links a visit to its subject by a `tracks`
edge, which holds nothing, so a visit on an epic leaves the epic's work running.

**Armed work.** The bypass narrows to decision gates. Reconcile still slings an
armed bead whose own blockers have closed, but only when every open blocker on each
of its ancestors is a decision gate and no ancestor carries a future
`defer_until`. Any other hold on an ancestor holds the armed bead. The predicate
walks every ancestor, because a member two levels down is held through a parent
that has no blocker of its own. A decision gate is the coordination wait the bypass
exists for (fact 6). A demand waits on a person's answer, and since tk-p8svsz the
visit behind it holds only its subject's own merge and close, never downstream
work. A park gate shows in `list` and the pass log as `PARKED`. A real
prerequisite shows as `WAITING on <blocker>`. The arm stays intact, so unparking
needs no re-arm. `check-armed-dispatch-owed` applies the same predicate, so a
parked arm is neither owed nor stranded. That settles tk-rl8gz4b.1.

The narrowing is an allow-list of the one shape the bypass was built for, and it
fails closed. Exempting park gates alone would keep slinging the armed children of
an epic that waits on a real prerequisite, while its routed children wait.

*Rejected:* disarming on park and re-arming on unpark, which is the second shape
tk-rl8gz4b.1 offered. It costs two writes per armed bead per move, and a re-arm
that never lands drops the work silently.

*Later:* converse holds will stop filing a cascading demand (tk-n18e15). Once that
lands and no open demand bead blocks an epic, the bypass has nothing left to serve.
Reconcile can then read `bd ready` alone (unit 12).

**Slung work.** `gc sling` pours without reading any edge, so a hand sling of a
parked bead pours a workflow the cascade cannot reach. mol-polecat-work's
load-context step already refuses a work bead that has an open `blocks` blocker of
its own: it arms a re-dispatch and holds the molecule. Unit 3 extends that guard
to a parked bead, and lets a bead in flight through. The re-dispatch fires when the
epic is unparked. `gc-helm.sh accept` refuses a parked bead with the `unpark` hint,
instead of pouring into the guard.

One risk carries over from the existing guard. A molecule held at load-context can
make gascity refuse the re-dispatch's pour while the held root is live. Unit 3's
done-when therefore runs the whole round trip: park, sling, unpark, built.

## 3. Priority flow

**The rule.** A bead queues at the priority of its nearest epic ancestor when that
epic is not parked. A bead under no epic keeps its own priority. PR-finishing work
ranks by section 7. Emergencies, meaning a red main or a broken gate, stay outside
every epic at P0.

**Two writers, one function.** The reconcile carries a priority change to work
that is already queued. `settle` sets a bead's priority at the moment the bead
becomes claimable. Both compute a bead's priority with one function, so they
cannot disagree.

**The reconcile.** `epic-steer.sh reconcile` runs from a rig-scoped cooldown
order, `orders/epic-priority.toml`, every five minutes, the same shape as
`orders/deferred-dispatch.toml`. `priority` also runs it at once for the epic's
subtree. `unpark` runs it for the subtree at the new priority while the park
still holds the subtree, and only then removes the edge (section 1). Each pass
works through these steps.

1. It reads the store's open epics and its park gates.
2. It reads the open beads with their edges and finds each one's nearest epic.
3. It sets each member of an unparked epic to the epic's priority.
4. It follows each such member into its live workflow and sets the input convoy,
   the root and every open step. The convoy tracks the member, the root names the
   convoy in `gc.input_convoy_id`, and each step names the root in
   `gc.root_bead_id`.
5. It ranks PR-finishing work (section 7).
6. It writes only the differences, one multi-id update per priority value, so a
   settled store costs reads only.

Members of a parked epic are skipped. Unpark sets them before it releases them.

The scheduled pass and the two verbs take one per-rig lock, as
`refinery-reconcile.sh` does for its passes. So a pass that read an epic's old
priority cannot write it back after a `priority` move.

**Settle before a bead can be claimed.** Claims follow bead priority (fact 1),
and a pour copies it once (fact 2). A bead that becomes claimable between two
passes would be claimed at whatever priority it carries, so the reconcile alone
is too late for it. Every writer that makes a member or a PR-finishing child
claimable therefore settles the bead first.

`epic-steer.sh settle <bead>` computes the bead's priority, writes it to the bead
and to any live workflow the bead has, and reads it back. It exits non-zero when
the read-back does not match. A writer that slings or releases a bead does so
only after settle exits zero. A writer that routes a bead directly runs
`settle --print <bead>` instead, which computes the same priority and writes
nothing, and puts that priority in the same `bd update` as the route. bd writes a
metadata patch in the same row write as the field edits (beads
`internal/storage/issueops/execution.go:192-213`), so the route is never visible
before the priority. When either form fails, the writer stops and says so.

These writers settle:

- `place` routes the item with its settled priority in the route's own update
  (section 5).
- `unpark` writes the subtree at the new priority while the park still holds it
  (section 1).
- Deferred dispatch slings every armed bead through one function, `sling_bead`,
  and that function settles the bead before it slings. So an arm fires at the
  right priority, whoever wrote it.
- `gc-helm.sh takeaway --route` puts the settled priority in its route's update.
  First reaction's actionable exit routes through it.
- `gc-helm.sh accept` settles before it pours.
- Each PR-finishing creator settles its child before it routes or slings it
  (section 7).

A bead under no epic and outside section 7 settles to its own priority, and so
does a member of a parked epic until unpark settles it. For either, settle
changes nothing.

**Edges of the rule.**

- A bead in progress is not rewritten. A claim already made stands.
- A hand edit to a member's priority is reverted by the next pass. That is the rule
  working.
- A gascity store transaction can write a stale snapshot back over a concurrent
  priority write (gascity `internal/beads/bdstore.go:2205-2209`). The next pass
  re-applies the priority.
- A writer outside the list above, such as a raw `gc sling` or a route written
  by hand, runs no settle. It queues the bead at the priority the bead carries.
  That is already the epic's once `place` or one pass has settled the bead. The
  gap left is a bead made a member by a raw edge write and then made claimable
  by hand before the next pass. Until that pass, it queues at its old priority.
- A `priority` move re-ranks queued work as its pass writes each bead. A claim
  made before the pass reached a bead was made at the rank then in force.
  `settle` does not take the lock, so a settle that read the epic's old priority
  can write it after the move's pass has written the new one. The next pass
  corrects that bead and its workflow.

**Rejected.**

- *The reconcile alone.* A bead routed between passes would queue at the
  priority it was filed with, and a polecat could claim it there before the next
  pass.
- *Stamping alone, at each route and sling.* No stamp follows a later priority
  change, so the reconcile is still needed.
- *A polecat `work_query` that computes the epic's priority at claim time.* The
  proactive pool overrides its own query in this way
  (`agents/proactive/agent.toml`). For polecats it would replace gascity's tiered
  query for the busiest pool, and it would walk ancestors on every claim and every
  demand count. Bead priority is what `bd ready`, the hook and the board already
  read.
- *An order triggered on `bead.updated`.* gascity's event trigger cannot filter on
  the payload (`internal/orders/triggers.go:470-497`), so it would fire on every
  bead write.

## 4. Readers that must see a park

| Reader | What it does with a parked bead today | Change |
|---|---|---|
| `doctor/check-blocked-work-armed` | It lists `bd blocked`, which includes cascade-held members (fact 4), and flags a member with no route or arm. Its remedy, "arm it", would dispatch the bead through the bypass. 196 of the 201 held beads have neither a route nor an arm (fact 8). | Skip parked beads (unit 7). |
| `doctor/check-armed-dispatch-owed` | It reports an armed member that only an ancestor holds as owed after 15 minutes. | Apply section 2's predicate (unit 2). |
| `deferred-dispatch.sh` list and reconcile | It slings the bead (fact 6). | Section 2 (unit 2). |
| `assets/scripts/bead-context.sh` (converse prep) | It reads a parked epic's frontier as stuck. | Read the park (unit 7). |
| Helm board | Idle children make a parked epic high severity, and the board files it under STALLED ("open work nothing is moving"). The board has no park notion. Its word "parked" means a bead carrying `gc.takeaway`. Epic priority is only a hidden ranking weight. | Show each epic's steering state. Give parked epics their own section with no stranded children. Rename the takeaway notion (unit 8). |
| `liveness-sweep.sh` | It classifies over `bd ready`, so a parked bead is outside its funnel. | None. |
| `doctor/check-state-space` detached-anchor probe | It keys on status, and a park leaves status open. | None. |
| `doctor/check-wait-is-an-edge`, `gate-visit-sweep.sh` | They read markers that the park gate does not carry. | None. The gate must keep carrying none. |
| `tools/gc-proactive.sh` scan | It reads `bd ready` and drops parented beads. | None. |
| Witness orphan recovery | It keys on owners. | None. |

Unit 2 also corrects the documents named in fact 4.

## 5. Intake holds findings for placement

**Paths today.** A filed bead becomes polecat work without the operator by these
paths.

- *The scheduled sweep*, `orders/proactive-scan-sling.toml`, every 15 minutes. It
  is off in gc-toolkit and gascity by overrides in the town's `city.toml` (sections
  6 and 7), which are not committed.
- *Patrol findings.* `patrol-finding.sh` slings a first reaction right after filing
  (`assets/scripts/patrol-finding.sh:418-428`), which bypasses the order. Its
  callers are the deacon and witness patrols and `merge-tail-report.sh`. None of
  them passes `--no-react`.
- *First reaction's exits.* The actionable exit routes the bead to the polecat
  pool (`assets/scripts/first-reaction-dispose.sh:166-176`, written at `:578-586`).
  The blocked exit's then-route arms a dispatch for when the blocker closes.
- *The witness* files mail about a pack defect as a bug routed to the polecat pool
  at creation (`formulas/mol-witness-patrol.toml`, the bug-dispatch block).

So section 7 of `city.toml` stops only the sweep. A patrol finding still becomes
polecat work through its reaction.

**The rule.** A bead may be routed or armed to the polecat pool only when one of
these holds:

- it is a member of an epic;
- it is PR-finishing work of an anchor;
- it is an emergency, meaning a red main or a broken gate, checked rather than
  asserted;
- the operator routed it, through a sitting, a hand sling or an Accept.

Everything else waits for placement.

**What changes (unit 9).**

- First reaction still reacts, because its card is the sitting's triage. Its
  actionable exit routes a member, or an emergency at P0. Any other bead it marks
  `placement=pending` and leaves unrouted. The blocked exit's then-route follows
  the same rule.
- The witness's bug dispatch follows the rule at creation.
- With the hold in place, the scheduled sweep comes back on. The town repo deletes
  sections 6 and 7 of `city.toml`, as their own release notes say to.
- `epic-steer.sh unplaced` lists the sitting's queue.

First reaction's close exit keeps its validating closer, because that closer
closes beads and so shrinks the queue. The learning loop's promotion work stays as
it is too (`formulas/mol-feedback-distiller.toml` routes prompt-update and
engineering beads at creation): it is not a finding, and the operator gates each
one at its PR.

**Association means membership.** Placing an item under an epic writes a
parent-child edge. The board, the cascade and the priority reconcile all read that
edge. After that, the epic's state decides when the item runs, and there is no
separate linked-only state. Under an epic at P0 to P2, the item runs at the epic's
priority: it is worked by proxy, with the epic's priority standing as the
operator's go. Under a parked epic, the cascade holds the item until the epic is
unparked.

**The placement verb (unit 10).** `place <item> <epic>` first removes any
relates-to edge between the two, because bd refuses a parent-child edge beside one
on the same pair. It then writes the parent edge and records who placed it and
when. That is the unrelate-then-reparent primitive tk-8bzuc2 names, which sits
under the parked first-class-epics epic, and unit 10 builds it here. Last,
`place` routes the item to the polecat pool, with the item's settled priority in
the route's own update, so the item is never routed at its old priority
(section 3). Under a parked epic, the parent edge already holds the item when the
route lands, and unpark settles it before release. `place` refuses a bead
carrying `anchor_bead`, because PR-finishing work stays outside every epic
(section 7). `place <item> --standalone` routes a loose item at its own priority.
The sitting's other outcomes, a new epic or a close, use the existing tools. An
item the sitting does not place stays without an epic until the operator judges a
group of such items material enough to become an epic, with a hypothesis, a first
Feature and a Checkpoint after it.

**Who associates.** The operator associates at the placement sitting, using the
verb. A first reaction proposing or making the association is the create-time
membership classifier. The first-class-epics epic (tk-rctkrj) owns that classifier,
and this epic's boundaries leave it there. Until it lands, nothing is associated
automatically. When it lands, it writes the same edge through the same verb and
records itself as the placer, so the next sitting can review its choices. It
associates only when exactly one open epic's contract covers the item.

## 6. A Checkpoint records the next priority

A Checkpoint ruling of continue or shift names the epic's next steering state: P0,
P1, P2 or parked. The sitting that records the ruling applies that state with the
steering verb before it ends, citing its own visit:
`epic-steer.sh priority <epic> P1 --evidence <visit>`. The verb stamps
`epic_steer_evidence`. The ruling stamps `epic_ruling_evidence`, a field from the
close-gate change (PR #977, tk-isd5sa). Both name the same visit, so a reader can
see which steering move the ruling made.

A close ruling names no next priority. A parked epic is unparked before it closes,
because its own edge to the gate is a live direct blocker, and bd refuses a close
with one (fact 5).

## 7. PR-finishing work

**Today.** These creators make PR-finishing work:

- `assets/scripts/pr-facts.sh` makes a merge-in child for an approved PR that
  conflicts, a child for a red required check (up to three attempts), and a
  comment rework. Each is routed directly.
- `assets/scripts/pre-open-rebase.sh` makes a merge-in child before a PR exists.
- `assets/scripts/signoff.sh` makes a rework when a review requests changes, and
  slings it with mol-polecat-work.
- `assets/scripts/gate-ensure.sh` dispatches the review beads, and the validation
  passes that `pr-facts.sh` and `signoff.sh` open.

None of them sets a priority. Each child queues at P2, bd's default, beside new
work and in age order within that band. Each carries `anchor_bead` and a `blocks`
edge to the anchor, with no parent edge.

**The invariant.** PR-finishing work is never filed as a parent-child descendant.
That keeps existing PR work moving under a park and under a decision hold with no
exception path. No cascade reaches a bead with no parent, and the scripts that
drive the anchor itself never read its parent (section 1). On 2026-10-11, none of
the 51 open, in-progress or blocked beads carrying `anchor_bead` had a parent edge.
Each creator's own suite asserts that the child it files has no parent (unit 6),
and the placement verb refuses a bead carrying `anchor_bead` (unit 10). So no
creator, sitting or future classifier can file one under an epic.

**The rank.** Each creator settles its child before it routes or slings it, so
the child's first claim is already at its rank. The reconcile then re-ranks the
child and its live workflow as the PR's posture and the epic's priority change
(section 3). The rank is:

- once the anchor's PR is approved (`pr_posture=approved`, which pr-facts records
  on the anchor), at P0;
- otherwise one band above the anchor's epic: P1 for a P2 epic, and P0 for a P1 or
  P0 epic;
- for a parked epic, as if the epic were P3, so its in-flight PRs finish at P2,
  behind every unparked epic's finishing work;
- for an anchor under no epic, one band above the anchor's own priority.

**Why.** Finishing turns work already spent into merged work, and it keeps open
PRs from collecting conflicts. Once a PR is approved, only mechanical work stands
between the operator's decision and the merge. Running one band up puts an epic's
own finishing ahead of its own new work. It does not let a low epic's review
rounds overtake a top epic's new work.

**At P0, age decides.** P0 holds emergencies, approved-PR finishing, and a P0
epic's new and finishing work, so age decides within it. An approved PR from
another epic can wait behind older new work of a P0 epic. A P0 epic is the
operator's all-hands call, and this design accepts that.

**Rejected.**

- *Finishing at the epic's own priority.* Approved PRs would wait behind new work
  of the same band.
- *All finishing at P0.* A parked epic's review rounds would outrank every active
  epic's new work.

The refinery's own queue of handoffs already sorts by priority (the find-work step
of `formulas/mol-refinery-patrol.toml`), so a ranked rework's hand-back is taken
first there too. `merge.sh` lands every landable PR on each pass, so the merge
order needs no rank.

## Implementation units

Each unit is one reviewable change under the epic tk-rl8gz4b. Every unit is
pack-side, and none needs gascity. Each unit updates the central documents its
change makes stale. The first unit creates `docs/epic-steering.md` as the
authoritative statement of the model, and the units after it extend it.

| # | Unit | Section | Needs | Done when |
|---|---|---|---|---|
| 1 | **Park gate and the park moves.** `epic-steer.sh` `park`, `unpark`, `status`; `park-lib.sh`; the `gc.park_gate` marker, registered and backfilled on every store's gate; `--evidence`; `docs/epic-steering.md`; I1's park-gate exception; an authority-map row for the verbs. | 1 | — | Park, unpark and status pass fixture tests on a scratch store. Every live park gate carries the marker. Unpark names the other blockers that still hold a subtree. |
| 2 | **Armed work stays parked.** The bypass narrows to ancestors held only by decision gates; `PARKED` and `WAITING` states in `list` and the pass log; `check-armed-dispatch-owed` applies the same predicate; the fact 4 corrections. This unit is tk-rl8gz4b.1, re-scoped. | 2 | 1 | An armed child of a parked epic is neither slung nor reported owed, and neither is one two levels down. One held only by a demand gate still dispatches; the tk-so8clv case stays green. One whose epic waits on a real blocker waits too. |
| 3 | **A sling does not start parked work.** The load-context guard covers a parked bead and lets in-flight beads through; Accept refuses a parked bead. | 2 | 1, 2 | Park, sling, unpark ends with the bead built, held root included. A bead in flight under a parked epic is built. |
| 4 | **A park does not strand in-flight work.** The refinery patrol's rejection dispatches a pour instead of routing the work bead. | 1 | 1 | A rejected handoff under a parked epic is rebuilt. An unparked one behaves as today. |
| 5 | **Priority flow.** `reconcile`, `settle` with its `--print` form, and `orders/epic-priority.toml`; the `priority` verb; unpark settles the subtree before it removes the edge; one lock for the order and the verbs; the routing doc's claim-predicate row is corrected. | 3 | 1 | After a priority change, the members and their poured workflows' open steps carry the new priority within one pass. A later sling inherits it. A hand edit reverts. Loose beads are untouched. `settle` and the reconcile give every bead of a shared fixture the same priority. With the scheduled pass off, unparking at P0 releases every member already at P0: the test's recorded writes put each member's priority before the edge's removal. A pass that overlaps a `priority` move does not write the old priority back. Pass time stays inside the order's timeout on the live store. |
| 6 | **PR-finishing rank and its invariant.** The reconcile ranks anchor children and their workflows. Each PR-finishing creator settles its child before it routes or slings it. Each creator's suite asserts that the child it files has no parent. | 7 | 5 | With the scheduled pass off, each creator routes or slings its child at its rank: an approved PR's merge-in child at P0, a P2 epic's review rework at P1, and a parked epic's in-flight rework at P2. A creator changed to file its child with a parent fails its own suite. |
| 7 | **Checks and converse context read the park.** `check-blocked-work-armed` skips parked beads; `bead-context.sh` reads a park. | 4 | 1 | A parked member draws no finding and no arm remedy. An unparked unarmed blocked member still does. |
| 8 | **The helm board shows steering.** The board shows each epic's state and priority, parks epics in their own section, and stops calling their idle children stranded. The takeaway notion gets a new name. | 4 | 1 | The board fixture renders a parked epic under its own section and an unparked one with its priority. The Go and shell predicates agree on the shared fixture. |
| 9 | **Intake holds findings for placement.** First reaction's actionable and blocked exits; the witness's bug dispatch; `unplaced`; the scheduled sweep back on, with `city.toml` sections 6 and 7 deleted in a town-repo commit. | 5 | — | A patrol finding with no epic ends with `placement=pending`, unrouted. A finding for a red main routes at P0. The sweep runs again. |
| 10 | **The placement verb.** `place`, with unrelate-then-reparent, a route that carries the settled priority, and the placement record; `--standalone`; the refusal of PR-finishing work. | 5 | 5 | Placing an item with a relates-to edge to its epic makes it a member and routes it. With the scheduled pass off, an item filed at P3 and placed under a P0 epic is routed at P0, in the same write as its route. Under a parked epic the cascade holds it. Placing a bead that carries `anchor_bead` is refused. |
| 11 | **The Checkpoint records the next priority.** epics.md and epic-stewardship.md state the section 6 rule. | 6 | 1, PR #977 (tk-isd5sa) | The docs carry it, and a checkpoint sitting's recipe applies the verb with its visit as evidence. |
| 12 | **Retire the ancestor bypass.** Reconcile reads `bd ready` alone. | 2 | 2, tk-n18e15 | No open demand bead blocks an epic, and the bypass code and its tests are gone. |
| 13 | **The existing writers settle.** Deferred dispatch's `sling_bead` and `gc-helm.sh accept` settle before they sling, and `gc-helm.sh takeaway --route` puts the settled priority in its route's update. | 3 | 5 | With the scheduled pass off, a member filed at P2 under a P0 epic is first claimable at P0 through each writer. An arm that fires pours at P0, a takeaway route lands at P0 in the same write as the route, and an Accept pours at P0. A settle that fails leaves the bead neither slung nor routed. |

A successor bead under the epic (tk-rl8gz4b.3) waits on this spec, and its
dispatch is armed. Once the spec merges, it files these units with the dependencies
the table gives, re-scopes tk-rl8gz4b.1 as unit 2, and arms each unit for the
polecat pool.

## What waiting costs

Until the units land:

- **Armed work starts under a parked epic.** The next deferred-dispatch pass slings
  any armed bead under a parked epic that lacks its own park edge (fact 6).
  Mechanik gave that edge by hand to every armed bead parked on 2026-10-10, but a
  bead armed later is not held.
- **A hand sling builds parked work.** A sling of a parked bead pours, and a
  polecat builds it.
- **Priority does nothing.** Work under the one unparked epic queues at whatever
  priority each bead was filed with. PR-finishing work queues at P2 beside new
  work.
- **Findings still become polecat work.** A patrol finding becomes polecat work
  through its first reaction, though `city.toml` section 7 reads as if intake were
  off.
- **Checks and the board read the park as a stall.**
  `check-blocked-work-armed` flags parked members that have no route or arm, and
  following its remedy would start them. The helm board shows every parked epic
  as stalled.

## Risks

- **Re-dispatch over a held root.** The guard unit 3 extends holds the molecule and
  arms a re-dispatch. gascity can refuse a second pour while the held root is live.
  Unit 3 proves the round trip, retiring the held root if it has to.
- **Reconcile cost.** Unit 5's pass reads a few whole-store listings. On a loaded
  store, a listing can outrun the order's timeout, and deferred dispatch has hit
  exactly that. The unit measures one pass against the live store before it
  registers the order.
- **The same word for two things.** "Parked" now names an epic held by the gate,
  while the helm board uses the word for a bead carrying a takeaway. Unit 8 renames
  the board's notion, so the operator meets the word with one meaning.
