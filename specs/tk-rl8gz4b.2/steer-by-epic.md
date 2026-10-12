---
name: Steer work by epic — priority flow, parks as blockers, placement
description: The design for the epic "Steer work by epic" (tk-rl8gz4b). It settles how an epic's priority, or a park on it, decides when the epic's work runs, with an epic treated as an ordinary bead and a park as an ordinary blocker. It covers the park move and its gate, how armed and slung work stays held, why the operator's pending decision is not a hold, how a bead's queue priority follows its parent's and its own, where that priority is computed and written, where PR-finishing work ranks, which checks and boards must read a hold, how intake holds findings and the feedback distiller's beads for the placement sitting, and how a Checkpoint records the next priority. It lists the implementation units. Read it to review the design or to build one of its units.
---

# Steer work by epic

## The decision

The operator steers polecat capacity by epic. An epic is an ordinary bead: its
priority is its bd priority, and parking it adds an ordinary blocker. Work under
an epic queues at the epic's priority, adjusted by the work's own. A blocker on
an epic holds everything under the epic that has not started, and work already
in flight finishes. This design does that with bd's own blocks edges, the
parent-child cascade and bead priorities. It needs no gascity change.

The operator steers with these moves, each one command. Each takes any bead, and
neither has logic for epics alone.

- `epic-steer.sh park <bead> <condition>` holds everything under the bead that
  has not started. It files a gate that states why the bead is parked and what
  releases it, and makes the bead wait on that gate. Unparking closes the gate.
- `epic-steer.sh priority <bead> <P0-P4>` re-ranks the bead's work, including
  workflows already poured. It works on a parked bead too, so the work is already
  at its rank when the park is released.

These points are decided.

- **A park holds everything under the bead that has not started, armed work
  included.** Deferred dispatch does not sling armed work past it, and a hand
  sling does not build it.
- **Waiting on the operator's decision is not a hold.** The operator ruled this
  on 2026-10-11 at 00:26Z. A demand gate (`gc.demand_for`) on an ancestor is
  therefore deferred dispatch's one exception: it does not hold an armed bead.
  Every other blocker holds as bd says. The exception retires once converse holds
  stop filing a blocking demand (tk-n18e15). See section 2.
- **An approved PR under a parked epic lands, and its bead closes.** The PR's
  anchor bead is a member of the epic, but nothing that lands it reads its
  parent. Of the bead graph, `merge.sh` reads only the anchor's own blockers, its
  children and the beads naming its PR (`assets/scripts/merge.sh:613-614`; the
  gctk port reads the same edges at `services/gctk/internal/cli/merge.go:555-556`).
  bd refuses a close only for open children or a live direct blocker, so a bead
  held only through its parent closes (beads v1.3.1
  `internal/storage/issueops/close.go:41-55`, `:155-160`). PR #1161 (tk-6nn4vcb)
  and PR #1032 (tk-yx2oqr.5) merged on 2026-10-11 under parked epics, and both
  anchors closed (fact 5). A park edge on the anchor itself would hold its merge,
  so `park` refuses a bead in flight.
- **The rest of a PR's finishing work keeps moving under any hold on its epic.**
  Review reworks, merge-ins, red-check fixes and validation passes are never filed
  as parent-child descendants, so no cascade reaches them (section 7).
- **Work under an epic runs at the epic's priority with no further move**,
  adjusted by its own rank within the epic (section 3). Placing an item under an
  epic is the operator's go for it. Under a parked epic it waits until the park
  is released.
- **PR-finishing work runs one band above its anchor, and at P0 once the PR is
  approved** (section 7).
- **Automatic association stays out of this epic.** The classifier that would
  associate findings with an epic belongs to the first-class-epics epic
  (tk-rctkrj). Until it lands, every finding that is not an emergency waits for
  the placement sitting.
- **The feedback distiller's beads wait for placement too.** Its prompt-update
  and engineering beads are new work, and the operator's "hold everything" ruling
  of 2026-10-11 at 00:25Z excluded only existing PR work. So they follow the
  intake rule a finding follows: each reaches a polecat once the sitting places
  it, and a park on the epic it is placed under holds it. The operator still
  reviews each one at its PR. The cost is one placement per bead, at most three
  a day (section 5).

One recommendation still needs a yes or a no.

**Rank within an epic.** The operator asked for a bead's priority to be its
epic's, adjusted up or down by the bead's own. bd gives a bead one priority
field. The pool claims by it, and a pour copies it into every bead of the
workflow it starts, with no way to give the pour another (fact 2). So the queue
priority has to be in that field before a bead can be claimed or poured, and the
field cannot also keep the bead's own.

- *Recommended:* the field carries the queue priority. A member's own rank is one
  key, `own_priority`, which `priority <member> <P>` sets and which reads as P2
  when unset. *Cost:* a hand edit of a member's priority field lasts only until
  the member is next computed, so ranking a member takes `priority`.
- *The alternative* leaves a member's field as its own rank and never writes it.
  The pack starts a member's work only through a pour that carries the queue
  priority, by creating the pour's input convoy itself at that priority. *Cost:*
  every path that routes a member straight to the pool becomes a pour. The pack
  creates each convoy the way gascity does, or gascity's guard against launching
  a workflow twice stops seeing it (fact 2). A member filed at its epic's
  priority, as filers often do now, counts that priority twice.

Waiting has a cost. Today a hand sling or any newly armed bead under a parked
epic starts work. Priority does nothing yet: work queues at whatever priority
each bead was filed with. Patrol findings and the distiller's beads still become
polecat work. The board shows every parked epic as stalled.
[What waiting costs](#what-waiting-costs) has the detail.

## Facts this design rests on

Each fact below was read or measured between 2026-10-10 and 2026-10-12. Source
paths name the gascity fork (`rigs/gascity`, HEAD `fbc3aeefe`), the beads module
bd runs (v1.3.1), or this repo.

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
2. **A pour copies priority once, from its input convoy.** `gc sling --on` takes
   the pour's priority from its input convoy
   (`internal/sling/sling_core.go:603-607`). For a bead, it creates that convoy at
   the bead's priority (`internal/graphv2/invocation.go:436-444`). A sling whose
   target is already a convoy uses that convoy as it is (`:383-411`). It then pours
   the workflow root and every step at the convoy's priority
   (`internal/molecule/graph_apply.go:165-185`). `gc sling` has no flag that sets
   a priority. Nothing writes priority after the pour. Nodes fanned out later take
   the root's priority at that moment (`internal/molecule/molecule.go:1152-1159`).
   A plain route leaves priority alone. The guard that refuses a second launch of
   a formula on a bead counts only convoys marked `gc.synthetic`, the mark on the
   convoy gascity creates (`internal/sling/sling_attachment.go:142-162`).
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
5. **Landing a PR reads no parent, and a close refuses only a direct blocker.**
   `merge.sh` holds a merge on any open blocker of the anchor's own, on its open
   children, and on the beads that name its PR. It never reads the anchor's parent
   (`assets/scripts/merge.sh:606-683`; the gctk port reads the same edges at
   `services/gctk/internal/cli/merge.go:548-556`). bd refuses a close only for open
   children or a live direct blocker, and a bead blocked only through its parent
   closes normally (beads `internal/storage/issueops/close.go:41-55`, `:155-160`).
   So a merged anchor under a parked epic closes. PR #1161 (tk-6nn4vcb, under
   tk-s0jfq7k) and PR #1032 (tk-yx2oqr.5, under tk-yx2oqr) merged on 2026-10-11,
   after both epics took their park edge at about 23:26Z the evening before. Each
   anchor closed seconds after its merge. A bead parked by its own edge cannot
   close until the edge is removed.
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
8. **bd records who changed what, and when.** Its audit events record each
   update, status change, close and dependency change with the actor and the time
   (`bd history <id> --events`; the event types are at beads
   `internal/types/types.go:1646-1660`). A gate's creator and creation time are
   fields of the gate.
9. **Nothing tells the pack when a priority or a parent changes.** An order
   triggered by an event fires on the event's type alone (gascity
   `internal/orders/triggers.go:470-497`), so an order on `bead.updated` fires on
   every bead write. bd's events journal, which records every mutation in order
   for a consumer to tail, is off in the gc-toolkit store
   (`bd config get events-journal` reads `false`).
10. **The park in place today was built by hand on 2026-10-10.** There is one gate
    per store, and every parked epic in that store waits on it. gc-toolkit's is
    tk-u5t8h6x, and its description says never to close it. On 2026-10-11 at
    00:05Z, 77 gc-toolkit beads carried a direct edge to it: the parked epics, plus
    the items mechanik parked one by one because they could have started on their
    own. Another 201 beads were held through those edges. Of the 201, 196 had
    neither a route nor an arm, 5 were routed, and none was armed, because
    mechanik gave every armed bead its own edge (from `gc bd blocked --json`). On
    2026-10-12, 125 beads carried a direct edge. The same store already holds a
    gate shaped like a single park: tk-dp0oyx7 holds tk-n9fxzj0, and its
    description says why and what releases it.

## 1. Epic priority and parks

**An epic is a bead.** Its priority is its bd priority, P0 to P4, and `priority`
moves it (section 3). A park adds a blocker and leaves the priority alone, so a
parked epic keeps its rank, and `priority` works on it while it is parked.
Nothing in this design reads `issue_type=epic`. A park or a priority on any bead
acts on that bead and everything under it.

**A park is a gate of its own.** `park <bead> <condition>` files a gate bead,
`issue_type=gate`, whose title and description state the condition: why the bead
is parked and what releases it. It then gives the bead a `blocks` edge onto the
gate and reads the edge back. The condition is required, so every park says what
releases it. The gate carries no await type and no `gc.demand_for`, so no sweep
closes or visits it (fact 7). It carries none of the `[holds]` markers that
`check-wait-is-an-edge` reads either. Who parked the bead, and when, are the
gate's creator and creation time (fact 8). The gate is filed in the bead's own
store, because bd resolves edges within one store.

When the condition names a bead, the park waits on that bead and files no gate.
Naming another park's gate parks one more bead for the same reason. Naming a task
parks the bead until the task closes.

**Unparking closes the gate.** Closing a gate releases everything that waits on
it, as closing any blocker does (`gc bd close <gate>`). To release one bead from a
gate that holds several, remove that bead's edge
(`gc bd dep remove <bead> <gate>`). The gates built by hand on 2026-10-10 (fact
10) become ordinary parks. Each states the 2026-10-10 hold as its condition, its
epics are released one by one as the operator unparks them, and it closes once it
holds nothing. Unit 1 rewrites their descriptions, so none says never to close it.

**Held and in flight.** A bead is held when it, or one of its parent-child
ancestors, has an open `blocks` edge onto an open bead. A demand gate on an
ancestor is the one blocker that does not count (section 2). A park and a
prerequisite hold the same way, and no reader tells them apart. One shell
definition, `assets/scripts/hold-lib.sh`, serves every shell reader, the way
`dispatch-path.sh` defines a dispatch path once. The helm board mirrors it in Go,
pinned to the shell copy by a shared fixture.

A bead is in flight once work on it has started. It carries `branch`,
`merge_result` or `rejection_reason`, or a workflow poured for it has passed
load-context.

**What a hold holds.** A hold holds work that has not started:

- pool-routed members, through bd's cascade, which already works (fact 3);
- armed members, through deferred dispatch (section 2);
- members slung by hand, and workflows poured before the hold that have not
  passed load-context, through the load-context guard (section 2);
- items placed under the bead later, through the same cascade (section 5).

**What a hold leaves running.** A hold leaves in-flight work running. A workflow
past load-context is out of the cascade's reach. PR-finishing work has no parent
edge, and section 7 makes that an invariant. The anchor itself is a member, but
nothing that drives it reads its parent. The refinery's find-work lists its
handoffs with `bd list`, not `bd ready`. `merge.sh` reads only the anchor's own
blockers, its children and the beads naming its PR (fact 5). None of
`pr-facts.sh`, `gate-ensure.sh` and `pr-open.sh` reads `bd ready`, `bd blocked`
or a parent edge. So a parked epic's open PRs still merge, and their anchors close
(fact 5).

One in-flight path does get held. When the refinery patrol rejects a handed-off
bead, its rebase and handle-failures steps route the work bead itself back to the
pool (`formulas/mol-refinery-patrol.toml`). That bead is a member, so the cascade
holds it. Unit 4 dispatches the rejection as a pour instead, which the cascade
does not reach.

**The park move refuses a bead in flight.** That bead's own edge would be a live
direct blocker. `merge.sh` holds an anchor's merge on any open blocker of its own,
and bd refuses the anchor's close (fact 5). Parking the epic instead leaves the PR
landing. `park` prints what the park now holds and what stays in flight.

**The shape law.** I1's shape law says that "a bead which will ever carry a
`blocks` edge must have no `parent-child` children"
([component-model.md](../../docs/component-model.md#i1-in-full-the-hold-the-demand-and-the-shape-law),
lines 250-251). The law's own reason is that a parent's blocked state cascades
down to every part of it, and that the cascade is the correct reading of
containment. A park on an epic, or a prerequisite of all of an epic's work, is a
wait of the whole epic, and the cascade is what it means. Unit 1 restates the law
for any bead with children: a blocker on it holds every part of it, so it carries
one only for a wait that belongs to all of its parts. A wait that belongs to one
part goes on that part, and work a sitting hands out on a subject stays a
dependency sibling, as now. The proposed doctor check tk-u4z8me reads the law as
written, so it follows the restated law.

**Rejected.**

- *Status deferred on the epic.* bd's cascade does not follow status, so the
  children stay in `bd ready`. That is why the hand-built park moved to a gate.
- *A future `defer_until` on the epic.* bd drops the children of a deferred parent
  from ready, but the date has to be invented, and the field means "not before a
  date", not "until the operator says".
- *One never-closed gate per store.* It cannot say why any one bead is parked or
  what releases it, and it has to exist whether or not anything is parked.
- *A marker that tells a park gate from other blockers.* A park holds the way any
  blocker holds, so no reader needs to tell them apart.

## 2. Armed and slung work stays held

**Every blocker holds, with one exception.** A blocker on a bead or on any of its
ancestors holds the bead's armed work, as bd's cascade already holds its routed
work. A visit holds nothing. `escalate.sh` links a visit to its subject by a
`tracks` edge, so a visit on an epic leaves the epic's work running.

The exception is the operator's pending decision. A demand gate is the human gate
that `gc-helm.sh demand` files, and it carries `gc.demand_for` naming the bead it
gates. A converse hold on an epic files one gated on the epic itself, because
`converse-hold.sh` moves the demand to the visit only for a PR anchor. The
operator ruled on 2026-10-11 that a hold waiting only on their decision does not
hold armed work. So a demand gate on an ancestor does not hold an armed bead. A
demand gate on the bead itself still does, because the decision is about that
bead. This is deferred dispatch's one rule about a blocker's kind, and it names
no kind of epic.

The exception retires with tk-n18e15. That change stops converse holds filing a
blocking demand, so no demand gate blocks an epic, and deferred dispatch can read
`bd ready` alone (unit 12). tk-n18e15 waits on the operator's ruling on its visit
(tk-eswxzg4), and both of that visit's options that keep the change, A and B, stop
the blocking demand. On 2026-10-12 no open demand gate in gc-toolkit blocks an
epic.

**Armed work.** Reconcile still slings an armed bead whose own blockers have
closed, but only when the bead is not held: every open blocker on each of its
ancestors is a demand gate. The predicate walks every ancestor, because a member
two levels down is held through a parent that has no blocker of its own. A held
armed bead shows in `list` and the pass log as `HELD by <blocker>`, with the
blocker's title, so a parked bead shows its park's condition. The arm stays
intact, so unparking needs no re-arm. `check-armed-dispatch-owed` applies the same
predicate, so a held arm is neither owed nor stranded. That settles tk-rl8gz4b.1.

The predicate fails closed. An ancestor or a blocker that cannot be read holds the
bead.

*Rejected:* disarming on park and re-arming on unpark, which is the second shape
tk-rl8gz4b.1 offered. It costs two writes per armed bead per move, and a re-arm
that never lands drops the work silently.

**Slung work.** `gc sling` pours without reading any edge, so a hand sling of a
held bead pours a workflow the cascade cannot reach. A workflow poured before the
hold reaches a polecat the same way. mol-polecat-work's load-context step already
refuses a work bead that has an open `blocks` blocker of its own: it arms a
re-dispatch and holds the molecule. Unit 3 extends that guard to a held bead, and
lets a bead in flight through. The re-dispatch fires when the hold is released.
`gc-helm.sh accept` refuses a held bead and names its blocker, instead of pouring
into the guard.

One risk carries over from the existing guard. A molecule held at load-context can
make gascity refuse the re-dispatch's pour while the held root is live. Unit 3's
done-when therefore runs the whole round trip: park, sling, unpark, built.

## 3. Priority flow

**The rule.** A bead's queue priority is its parent's queue priority, adjusted by
the bead's own rank within its parent. Own P2 keeps the parent's band. Each level
above P2 moves the bead one band ahead, and each level below moves it one band
back, within P0 to P4. Under a P1 epic, a member at its own P2 queues at P1, and a
member ranked P1 queues at P0. A bead with no parent queues at its own priority,
so an epic's priority is the band its work starts from. The rule applies at every
level, so a feature under an epic adjusts the band for everything under it. A
workflow's input convoy, root and steps queue at their member's priority.
PR-finishing work ranks by section 7. Emergencies, meaning a red main or a broken
gate, stay outside every epic at P0.

**Where the queue priority is written.** This follows the recommendation on the
first screen. The bead's priority field carries the queue priority, because that
field is what every claim reads (fact 1) and what every pour copies (fact 2). A
member's own rank is the key `own_priority`, which reads as P2 when unset. A bead
with no parent needs no such key, because its field is both its own priority and
its queue priority. A member's own rank starts at P2 whatever priority it was
filed with. Filers often give a child its epic's priority already, and a rank read
from the field would count that priority twice. The operator sets a rank with
`priority <member> <P>`.

Under the alternative, the field keeps the member's own rank, and the queue
priority is written only on the workflow the pack pours for it: the input convoy,
the root and the open steps. Unit 5's writes change to match, and one more unit
turns each direct route of a member into such a pour.

**Computed where the inputs change.** Each input has a writer, and the writer
computes and writes what the change affects at once.

- *A bead's own rank, or an ancestor's priority.* `priority <bead> <P>` writes the
  bead's own value. Then it writes the queue priority of every open bead under it
  that is not claimed, with each one's live workflow, and of the PR-finishing
  children of each anchor among them, with theirs. It writes held beads too, so a
  bead is already at its rank when its hold is released.
- *Membership.* `place` writes the item's queue priority in the same update as its
  route (section 5).
- *A bead becoming claimable.* Every pack writer that routes, slings or releases a
  bead settles it first (below).
- *The PR's posture.* When the posture `pr-facts.sh` records on an anchor turns
  approved, or stops being approved, it settles the anchor's open PR-finishing
  children and their workflows (section 7).

A live workflow is found from its member. The input convoy tracks the member, the
root names the convoy in `gc.input_convoy_id`, and each step names the root in
`gc.root_bead_id`. A write to a workflow sets the convoy, the root and every open
step, because a pour copies priority only once (fact 2).

**Settle before a bead can be claimed.** `epic-steer.sh settle <bead>` computes
the bead's queue priority, writes it to the bead and to any live workflow the bead
has, and reads it back. It exits non-zero when the read-back does not match. A
writer that slings or releases a bead does so only after settle exits zero. A
writer that routes a bead directly runs `settle --print <bead>` instead, which
computes the same priority and writes nothing, and puts that priority in the same
`bd update` as the route. bd writes a metadata patch in the same row write as the
field edits (beads `internal/storage/issueops/execution.go:192-213`), so the route
is never visible before the priority. When either form fails, the writer stops
and says so.

These writers settle:

- `place` routes the item with its queue priority in the route's own update
  (section 5).
- Deferred dispatch slings every armed bead through one function, `sling_bead`,
  and that function settles the bead before it slings. So an arm fires at the
  right priority, whoever wrote it.
- `gc-helm.sh takeaway --route` puts the queue priority in its route's update.
  First reaction's actionable exit routes through it.
- `gc-helm.sh accept` settles before it pours.
- Each PR-finishing creator settles its child before it routes or slings it
  (section 7).

For a bead under no epic and outside section 7, settle changes nothing.

**One pass, for writes no writer sees.** A raw write can change an input without
running any of these writers: a hand `bd update --priority` on an epic, a parent
edge written by hand or by `bd create --parent`, or a hand sling or route of a
bead nothing settled. Nothing tells the pack that such a write happened (fact 9),
and work already queued would keep a stale rank until it finished. So
`epic-steer.sh reconcile` runs from a rig-scoped cooldown order,
`orders/queue-priority.toml`, every fifteen minutes, the same shape as
`orders/deferred-dispatch.toml`. It reads what a polecat claim reads, the beads
ready for the polecat pool, and settles each one whose priority differs. It reads
the queue, not the store. A bead that is not queued needs no pass, because a
writer settles it when it queues it.

The pass, `priority` and settle take one per-rig lock, as `refinery-reconcile.sh`
does for its passes. So neither a pass nor a settle that read an epic's old
priority can write it back after a `priority` move.

**Edges of the rule.**

- A claimed bead is not rewritten. A claim already made stands.
- A hand edit of a member's priority field is overwritten at the member's next
  computation: its epic's next `priority` move, its settle when it is queued, or
  the pass while it is queued. Rank a member with `priority` instead. This is the
  cost the recommendation names.
- A gascity store transaction reasserts the fields its callback staged, so it can
  write a stale priority over a concurrent priority write only when it staged
  priority itself (gascity `internal/beads/bdstore.go:2205-2209`). The pass
  re-settles a queued bead it reaches.
- A `priority` move re-ranks queued work as it writes each bead. A claim made
  before the move reached a bead was made at the rank then in force.

**Rejected.**

- *A whole-store pass every five minutes*, which the reviewed version of this
  section used. Every input but a raw write has a writer that computes at the
  change, so a pass only has to reach what a raw write can mis-rank, and that is
  the queue.
- *No pass at all.* A raw priority edit on an epic, a hand re-parent and a hand
  sling reach no writer (fact 9), so queued work would keep the stale rank until it
  finished.
- *Tailing bd's events journal* for priority and parent changes. The journal is
  off in this store (fact 9), and turning it on journals every write.
- *An order triggered on `bead.updated`.* The trigger matches on the event's type
  alone (fact 9), so it would fire on every bead write.
- *A polecat `work_query` that computes the priority at claim time.* The proactive
  pool overrides its own query in this way (`agents/proactive/agent.toml`). For
  polecats it would replace gascity's tiered query for the busiest pool, and it
  would walk ancestors on every claim and every demand count. Bead priority is
  what `bd ready`, the hook and the board already read.

## 4. Readers that must see a hold

| Reader | What it does with a held bead today | Change |
|---|---|---|
| `doctor/check-blocked-work-armed` | It lists `bd blocked`, which includes members held through a parent (fact 4), and flags a member with no route or arm. Its remedy, "arm it", would dispatch the bead through the bypass. 196 of the 201 beads held through the 2026-10-10 park had neither a route nor an arm (fact 10). | Flag only a bead with an open blocker of its own. A member held only through an ancestor waits on that ancestor's blocker, which owes it no arm (unit 7). |
| `doctor/check-armed-dispatch-owed` | It reports an armed member that only an ancestor holds as owed after 15 minutes. | Apply section 2's predicate (unit 2). |
| `deferred-dispatch.sh` list and reconcile | It slings the bead (fact 6). | Section 2 (unit 2). |
| `assets/scripts/bead-context.sh` (converse prep) | It reads a parked epic's frontier as stuck. | Read the hold and name its blocker (unit 7). |
| Helm board | Idle children make a parked epic high severity, and the board files it under STALLED ("open work nothing is moving"). The board has no notion of a held epic. Its word "parked" means a bead carrying `gc.takeaway`. Epic priority is only a hidden ranking weight. | Show each epic's priority and its open blockers with their titles, so a park shows its condition. Give held epics their own section with no stranded children. Rename the takeaway notion (unit 8). |
| `liveness-sweep.sh` | It classifies over `bd ready`, so a held bead is outside its funnel. | None. |
| `doctor/check-state-space` detached-anchor probe | It keys on status, and a hold leaves status open. | None. |
| `doctor/check-wait-is-an-edge`, `gate-visit-sweep.sh` | They read markers that a park gate does not carry. | None. A park gate carries none. |
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
- *The feedback distiller* files prompt-update and engineering beads, and routes
  each one to the polecat pool as it files it
  (`formulas/mol-feedback-distiller.toml`, the file-and-dispatch step).

So section 7 of `city.toml` stops only the sweep. A patrol finding still becomes
polecat work through its reaction, and a distiller bead through the route it is
filed with.

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
- The feedback distiller follows the rule when it files a bead: it marks each
  prompt-update and engineering bead `placement=pending` and leaves it unrouted.
- With the hold in place, the scheduled sweep comes back on. The town repo deletes
  sections 6 and 7 of `city.toml`, as their own release notes say to.
- `epic-steer.sh unplaced` lists the sitting's queue.

First reaction's close exit keeps its validating closer, because that closer
closes beads and so shrinks the queue.

**The distiller's beads wait like findings.** A distiller bead is not a finding,
and the operator reviews each one at its PR. It is still new work, and the
operator's "hold everything" ruling of 2026-10-11 at 00:25Z excluded only existing
PR work. The distiller files its beads with no parent, so parking an epic never
holds one. From that ruling to 2026-10-12, every bead the distiller filed was
parked by hand: tk-ymhd3o4 and tk-06ac0rv by the polecats that claimed them, and
tk-csqkf5w by the distiller's own session as it filed it. Under the rule, the
sitting places a distiller bead under an epic, where the epic's priority ranks it
and a park on the epic holds it, or routes it with `place --standalone`. The cost
is one placement for each bead before a polecat builds it. The distiller's order
fires at most once a day, and a run files at most three beads
(`max_beads_per_run`).

*Rejected:* keeping the distiller's route at filing. A park on an epic would never
hold its beads, so a hold on all new work would reach one only if an agent noticed
the hold and parked the bead by hand: the distiller's session as it files the
bead, or the polecat that claims it. Nothing in the pack makes either one check.

**Association means membership.** Placing an item under an epic writes a
parent-child edge. The board, the cascade and the priority writers all read that
edge. After that, the epic's state decides when the item runs, and there is no
separate linked-only state. Under an epic that is not held, the item runs at its
queue priority: it is worked by proxy, with the epic's priority standing as the
operator's go. Under a held epic, the cascade holds the item until the hold is
released.

**The placement verb (unit 10).** `place <item> <epic>` first removes any
relates-to edge between the two, because bd refuses a parent-child edge beside one
on the same pair. It then writes the parent edge, and bd's own record names who
placed the item and when (fact 8). That is the unrelate-then-reparent primitive
tk-8bzuc2 names, which sits under the parked first-class-epics epic, and unit 10
builds it here. Last, `place` routes the item to the polecat pool, with the item's
queue priority in the route's own update, so the item is never routed at its old
priority (section 3). Under a held epic, the parent edge already holds the item
when the route lands, and the item already carries its rank. `place` refuses a
bead carrying `anchor_bead`, because PR-finishing work stays outside every epic
(section 7). `place <item> --standalone` routes a loose item at its own priority.
The sitting's other outcomes, a new epic or a close, use the existing tools. An
item the sitting does not place stays without an epic until the operator judges a
group of such items material enough to become an epic, with a hypothesis, a first
Feature and a Checkpoint after it.

**Who associates.** The operator associates at the placement sitting, using the
verb. A first reaction proposing or making the association is the create-time
membership classifier. The first-class-epics epic (tk-rctkrj) owns that
classifier, and the operator ruled that it stays there. Until it lands, nothing is
associated automatically. When it lands, it writes the same edge through the same
verb, and bd's record names it as the placer, so the next sitting can review its
choices. It associates only when exactly one open epic's contract covers the item.

## 6. A Checkpoint records the next priority

A Checkpoint ruling of continue or shift names the epic's next priority, and
whether the epic is parked. The sitting that records the ruling applies it with
the moves before it ends: `priority <epic> <P>`, and `park <epic> <condition>` or
the close of the epic's park gate. The ruling stamps `epic_ruling_evidence` with
its visit, a field from the close-gate change (PR #977, tk-isd5sa). bd records who
made each move and when (fact 8), and a park the ruling makes states the ruling in
its gate's condition.

A close ruling names no next priority. A parked epic's park is released before the
epic closes, because its own edge to the gate is a live direct blocker, and bd
refuses a close with one (fact 5).

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
the child's first claim is already at its rank. The writers of section 3 then
re-rank the child and its live workflow when the PR's posture or its anchor's
priority changes. The rank is:

- once the anchor's PR is approved, P0;
- otherwise one band above the anchor's queue priority (section 3): P1 for an
  anchor at P2, and P0 for an anchor at P1 or P0.

The anchor's queue priority already carries its epic's band and the anchor's own
rank within the epic. An anchor under no epic queues at its own priority. A parked
epic keeps its priority, so its in-flight PRs finish at the rank that priority
gives them.

**Reading the approval.** For the rank, a PR is approved when the review posture
pr-facts records on its anchor is `approved`. That record, `pr_posture`, is a
dated key. `lifecycle.sh --set-dated` stores it as `<posture>@<oid>@<since>`, so
an approved anchor carries `approved@<head>@<since>`, never the bare word
([state-machine.md](../../docs/state-machine.md#posture)). The priority function
that settle and the section 3 writers share is the one place the rank reads the
key, and it takes the posture as the part before the first `@`, the way
`pr-facts.sh` reads its own record. A rank that compared the whole stored value
with `approved` would never match, so it would rank every approved PR's finishing
work as unapproved.

The posture is not the approval rule that `merge.sh` lands on
(`review-verdict.sh`). `pr-facts.sh` derives it from GitHub's review decision,
and an unanswered review comment outranks an approval. So a PR that rule calls
approved ranks as unapproved while one of its review comments is unanswered, and
whenever GitHub reports no review decision for it, as on a base that requires no
approving review.

**Why.** Finishing turns work already spent into merged work, and it keeps open
PRs from collecting conflicts. Once a PR is approved, only mechanical work stands
between the operator's decision and the merge. Running one band up puts an epic's
own finishing ahead of its own new work, and level with the new work of an epic
one band higher. So a higher epic's work still runs first, and a lower epic's PRs
still land. A low epic's review rounds do not overtake a top epic's new work.

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
| 1 | **The park move.** `epic-steer.sh park`, which files a gate stating the condition, or waits on a named bead, and refuses a bead in flight; `docs/epic-steering.md`; I1's shape law restated for any bead with children, and tk-u4z8me rewritten to it; an authority-map row for the moves; each store's 2026-10-10 park gate states its condition. | 1 | — | `park` passes fixture tests on a scratch store. It files a gate whose title and description carry the condition, gives the bead an edge onto it and reads the edge back. Given a bead id, it waits on that bead and files no gate. It refuses a bead in flight. No live park gate says never to close it. |
| 2 | **Armed work stays held.** `hold-lib.sh` with the held predicate; deferred dispatch slings an armed bead only when no ancestor has a blocker other than a demand gate; `HELD by <blocker>` in `list` and the pass log; `check-armed-dispatch-owed` applies the same predicate; the fact 4 corrections. This unit is tk-rl8gz4b.1, re-scoped. | 2 | — | An armed child of a parked epic is neither slung nor reported owed, and neither is one two levels down. One whose epic waits on a task waits too. One held only by a demand gate on its epic still dispatches, and the tk-so8clv case stays green. |
| 3 | **A sling does not start held work.** The load-context guard covers a held bead, including a workflow poured before the hold, and lets a bead in flight through; Accept refuses a held bead. | 2 | 2 | Park, sling, unpark ends with the bead built, held root included. A workflow poured before the park is held at load-context and built after the unpark. A bead in flight under a parked epic is built. |
| 4 | **A hold does not strand in-flight work.** The refinery patrol's rejection dispatches a pour instead of routing the work bead. | 1 | — | A rejected handoff under a parked epic is rebuilt. One under no hold behaves as today. |
| 5 | **Priority flow.** The queue-priority function; `own_priority`, registered; `settle` with its `--print` form; `priority`, which writes the subtree, its live workflows and its anchors' PR-finishing children; `reconcile` over the queue, from `orders/queue-priority.toml`; one lock for the order, `priority` and settle; the routing doc's claim-predicate row corrected. | 3 | 1 | With the order off, a `priority` move leaves the members, their poured workflows' open steps and their anchors' PR-finishing children at the new rank. A member ranked P1 under a P1 epic queues at P0, and at P1 once the epic moves to P2. A parked epic's members take a new priority while the park holds them. A raw priority edit on an epic reaches its queued work in one pass, and the pass reads only the queue. `settle` and `priority` give every bead of a shared fixture the same priority. A pass that overlaps a `priority` move does not write the old priority back. One pass on the live store stays inside the order's timeout. |
| 6 | **PR-finishing rank and its invariant.** The function ranks anchor children and their workflows; each PR-finishing creator settles its child before it routes or slings it; `pr-facts.sh` settles an anchor's children when the posture it records turns approved or stops being approved; each creator's suite asserts that the child it files has no parent. | 7 | 5 | With the order off, each creator routes or slings its child at its rank: an approved PR's merge-in child at P0, and a review rework at P1 under a P2 epic. When an anchor's posture turns approved, its open children and their workflows reach P0 in the pass that records it. Every fixture anchor with a PR records its posture in the stored shape, `approved@<head>@<since>` for an approved PR. Each suite with an approved PR holds one under a P2 epic, where unapproved finishing work runs at P1, so a rank changed to compare the whole stored value fails it. A creator changed to file its child with a parent fails its own suite. |
| 7 | **Checks and converse context read the hold.** `check-blocked-work-armed` flags only a bead with an open blocker of its own; `bead-context.sh` reads a hold and names its blocker. | 4 | 2 | A member held through its parked epic draws no finding and no arm remedy. An unarmed member with an open blocker of its own still does. |
| 8 | **The helm board shows steering.** Each epic's priority and open blockers with their titles; held epics in their own section, with their idle children not called stranded; the takeaway notion renamed. | 4 | 2 | The board fixture renders a parked epic under its own section with its park's condition, and an unparked one with its priority. The Go and shell predicates agree on the shared fixture. |
| 9 | **Intake holds findings for placement.** First reaction's actionable and blocked exits; the witness's bug dispatch; the feedback distiller's filing, and the promotion path in `docs/feedback-learning.md` that describes it; `unplaced`; the scheduled sweep back on, with `city.toml` sections 6 and 7 deleted in a town-repo commit. | 5 | — | A patrol finding with no epic ends with `placement=pending`, unrouted. A finding for a red main routes at P0. A distiller run leaves each bead it files with `placement=pending`, unrouted. The sweep runs again. |
| 10 | **The placement verb.** `place`, with unrelate-then-reparent and a route that carries the item's queue priority; `--standalone`; the refusal of PR-finishing work. | 5 | 5 | Placing an item with a relates-to edge to its epic makes it a member and routes it. With the order off, an item filed at P3 and placed under a P0 epic is routed at P0, in the same write as its route. Under a parked epic the cascade holds it. Placing a bead that carries `anchor_bead` is refused. |
| 11 | **The Checkpoint records the next priority.** epics.md and epic-stewardship.md state the section 6 rule. | 6 | 1, 5, PR #977 (tk-isd5sa) | The docs carry it, and a checkpoint sitting's recipe applies the moves before the sitting ends. |
| 12 | **Retire the demand-gate exception.** Deferred dispatch and the held predicate read `bd ready` alone. | 2 | 2, tk-n18e15 | No open demand gate blocks a bead with children, and the exception's code and tests are gone. |
| 13 | **The existing writers settle.** Deferred dispatch's `sling_bead` and `gc-helm.sh accept` settle before they sling, and `gc-helm.sh takeaway --route` puts the queue priority in its route's update. | 3 | 5 | With the order off, a member filed at P2 under a P0 epic is first claimable at P0 through each writer. An arm that fires pours at P0, a takeaway route lands at P0 in the same write as the route, and an Accept pours at P0. A settle that fails leaves the bead neither slung nor routed. |

A successor bead under the epic (tk-rl8gz4b.3) waits on this spec, and its
dispatch is armed. Once the spec merges, it files these units with the dependencies
the table gives, re-scopes tk-rl8gz4b.1 as unit 2, and arms each unit for the
polecat pool. If the operator chooses the alternative to the recommendation, units
5 and 10 change as section 3 says, and one more unit, which turns each direct
route of a member into a pour, comes before them.

## What waiting costs

Until the units land:

- **Armed work starts under a parked epic.** The next deferred-dispatch pass slings
  any armed bead under a parked epic that lacks its own park edge (fact 6).
  Mechanik gave that edge by hand to every armed bead parked on 2026-10-10, but a
  bead armed later is not held.
- **A hand sling builds parked work.** A sling of a parked bead pours, and a
  polecat builds it. A workflow poured before the park reaches a polecat the same
  way.
- **Priority does nothing.** Work under the one unparked epic queues at whatever
  priority each bead was filed with. PR-finishing work queues at P2 beside new
  work.
- **Findings still become polecat work.** A patrol finding becomes polecat work
  through its first reaction, though `city.toml` section 7 reads as if intake were
  off.
- **The distiller's beads still route themselves.** The feedback distiller routes
  each bead to the polecat pool as it files it, so no park on an epic holds one.
  While a hold on all new work stands, an agent has to notice the hold and park
  each such bead by hand: the distiller's session as it files the bead, or the
  polecat that claims it.
- **Checks and the board read the park as a stall.**
  `check-blocked-work-armed` flags parked members that have no route or arm, and
  following its remedy would start them. The helm board shows every parked epic
  as stalled.

## Risks

- **Re-dispatch over a held root.** The guard unit 3 extends holds the molecule and
  arms a re-dispatch. gascity can refuse a second pour while the held root is live.
  Unit 3 proves the round trip, retiring the held root if it has to.
- **Pass cost.** The pass reads the polecat queue through `bd ready`. The queue is
  small, but on a loaded store a listing can outrun the order's timeout, and
  deferred dispatch has hit exactly that. Unit 5 measures one pass against the
  live store before it registers the order.
- **The same word for two things.** "Parked" now names a bead held by a park gate,
  while the helm board uses the word for a bead carrying a takeaway. Unit 8 renames
  the board's notion, so the operator meets the word with one meaning.
