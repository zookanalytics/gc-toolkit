---
name: Design record — gctk's domains from its CLI, proved on "is this blocked?"
description: The record behind docs/gctk-architecture.md, taken at b25a5c06. It covers what approving the design decides and what each part costs, where the design departs from its Feature's contract and why, what the design-gate sittings settled, the rulings on the queued pr-open, signoff and cobra beads, the nouns the surviving intents yield against the epic's starting proposal, which change carries each domain move, the breakdown the implementation child follows, and what the Epic Checkpoint reads. The census of "blocked" is in blocked-census.md beside it.
---

# Design record: gctk's domains from its CLI

The design itself is [docs/gctk-architecture.md](../../docs/gctk-architecture.md).
This record holds what it was derived from and what it decides about work that
is already filed. It was taken at b25a5c06, the commit `integration/tk-ssm8qns.1`
was cut from.

## What the operator approves

Approving the design starts the proof, tk-ssm8qns.3. It builds gctk's command
tree, the ledger, the store adapter with its fake, and `waits`, the package
behind `gctk bead holds`, which answers what holds a bead, "is this blocked?"
among it. Every place in surviving code that decides "is this blocked?" then
asks `waits`, and `hold-lib.sh`, its suite and its fixture (686 lines) are
deleted. Approving decides six things.

- **The surface and its callers.** Every intent that survives the migration
  map is one `gctk <noun> <verb>` call. Each verb carries a caller class, agent,
  hook or order, and a defense: the feature it adds over the native call it
  wraps, or the debt it contains and what retires it. The nouns are bead,
  priority, pr, rig, review, quota-park, seed and dolt, and lifecycle and merge
  join as named debt. Writes stay on the native surface, and pack logic that
  follows a write reacts through an order, which one admission rule governs.
  A verb shares a native word only where it means the same or does the whole
  act over the native primitive, and takes a fresh word wherever its answer
  can differ from the native call it would be taken for, so the bead read is
  `bead holds` and the order that starts an armed bead is `bead start-armed`.
  Anchor, findings, engagement, disposition, run, convoy, epics and learning
  are not nouns, because what they hold retires onto Gas City or stays prose.
  Dispatch, sessions and sends dissolve: arm and disarm are bead verbs and the
  start is an order, quota-park nudging is an order of its own, and the
  containment acts live under pr. This costs nothing until a domain moves.
- **One rule for "is this blocked?", and it is the store's.** Work that has not
  started is held by whatever keeps it out of `bd ready`, a wait of its own or
  an ancestor's. Work in flight is held only by its own waits, the ones bd
  refuses its close for. The cost is two answers that change on live beads
  ([blocked-census.md](blocked-census.md#the-answers-that-change-for-approval)):
  - bead-context's frontier reads 192 beads as blocked;
  - a doctor check lists 3 edges into another store.

  Nothing changes for the 99 armed beads, the 7 refinery handoffs, or a
  sitting's route of a bead its epic's park holds.

  One kind of wait needs a repair in bd first. bd judges a `waits-for` edge by
  its spawner's status rather than by its gate, both in `bd blocked` and in its
  close rule. So its listing can leave out a bead that its own gate holds,
  blame a parent that holds nothing, or name a spawner whose gate has opened
  ([blocked-census.md](blocked-census.md#the-stores-rules)). Until the bd the
  city runs judges the gate, a bead with a `waits-for` edge of its own reads
  `unjudged`. Unlike a failed read, that answer stands until the repair, so
  every caller that acts holds such a bead, even once its gate opens. The
  adapter takes it from the bead's own edge, never from the listing. No
  store held such an edge at 20:12Z, so this costs nothing today, and unit 3
  reads the stores again before its callers move. The same repair makes
  `bd blocked` return an error when its read of parents fails. Today it drops
  every bead held through a parent and exits 0, so until then the adapter
  checks the listing against the beads the store marks blocked, and a bead the
  listing lost gets a read error, which no caller takes for `unjudged`.
  tk-ssm8qns.5 tracks the repair and waits on this design and on your choice
  of its path, an upstream fix or a beads patch (tk-n9xx029). The report to
  upstream beads is parked for you to send (tk-j692b1f), and tk-ssm8qns.6
  drops the `waits-for` error and the check once the repair is in the city's
  bd. The alternative, holding the proof until then, would hold the six
  members that wait on this Feature as well.
- **An earlier ruling gives way.** A demand gate on a parent holds the parent's
  work that has not started, as every gate does, so deferred dispatch stops
  exempting it. No live bead sat under one on 2026-10-27, and unit 3 reads the
  stores again before its callers move. The cost: a member armed under a
  parent that waits on your decision no longer starts until you decide. A
  question about one member goes on that member instead.
- **Domain moves ride the migration members.** Six members build their
  surviving residuals in gctk, each waiting on this Feature by a `blocks`
  edge: tk-1tfzr71.16, .18, .20, .21, .22 and .24. This costs no time while
  the converse migration is in flight, since both lanes already wait on it. A
  member waits only if its turn comes before this Feature lands.
- **Ten copies wait for their members.** Copies of a different rule in code
  the deletion plan retires get no new work under built-once rule 1. Until
  those members land, "blocked" is decided by `waits`, by the store's own
  queries and by those ten copies, each with the member that deletes it.
- **The queued beads.** The pr-open and signoff ports are dropped, and the
  cobra bead folds into this Feature.

One reading the design takes needs no change today. **Closure condition 5 is
read as covering surviving intents.** The epic's condition says no formula,
prompt, order or doctor check needs a script. The migration map keeps some glue
as shell on purpose: `run-cancel.sh`, the scratch reapers, the cycle-recycle
hook, `self-review-check.sh` and the work-context overlay. The design gives
none of them a gctk verb. If they should move as well, that is a ruling the
epic's later Features carry.

## Departures from the Feature's contract

The Feature (tk-ssm8qns.1) was written on 2026-10-16. Two operator rulings and
the migration map came after it, and the design follows them where they differ.

1. **The CLI comes from the surviving intents, not from every intent a caller
   expresses today** (sitting tk-za3gnpt, 2026-10-19). An intent the migration
   map retires is not given a gctk verb, even where a caller expresses it today,
   because porting it would carry it forward.
2. **A port deletes the shell it replaces and carries only surviving intents**
   (sitting tk-v7c6973, 2026-10-26). So the design files no port beads. A
   surviving intent moves into gctk in the change that settles its final shape,
   which for most of them is the migration member that re-expresses its feature.
3. **The ledger reads a write back only before an act that cannot be undone,
   and refuses a wait edge into another store.** The Feature's contract says
   the ledger "makes every write read itself back". The migration map's
   read-back verdict, which came later, found bd's exit status honest for an
   ordinary write. It kept one helper, for irreversible acts and cross-store
   edges, as a surviving intent (tk-1tfzr71.11). Reading back every write would
   double the store traffic of every verb to guard against a failure the map
   found no path for. A cross-store edge reads back as written and still holds
   nothing, so the ledger checks the target before the write instead.
4. **"Move every caller that decides blocked" covers callers in code that
   survives, and every caller of `hold-lib.sh`.** A caller in code the deletion
   plan retires gets no new work (built-once rule 1, adopted 2026-10-26). Its
   member's replacement asks the domain, and the implementation leaves a rule-1
   note on each such member naming the one rule. `hold-lib.sh` is the one shared
   shell definition of the rule, and this port deletes it, so its five callers
   swap their call site onto `waits` in the same change, three of them in
   retiring code. The census lists every place and which way it goes.
5. **The one rule drops `hold-lib.sh`'s demand-gate exemption.** The store
   passes a demand gate's hold down to every descendant, as it does any gate's.
   `hold-lib.sh` exempts a demand gate on an ancestor, under the operator's
   earlier ruling that waiting on their decision does not hold armed work.
   Keeping the exemption would make `waits` walk the tree past the store's
   answer, which is the second rule this Feature removes. The native-gates
   design, which lands with tk-1tfzr71.4 from `integration/tk-iirrmiw`, already
   decided the same way in tk-0ur8r9p, decision 4: a gate on a bead with open
   children pauses every part that has not started, and each caller chooses
   whether its question blocks the parent, one member, or opens a conversation
   instead. No live bead sits under such an ancestor today.
6. **`waits` answers two questions, and both are the store's.** "Is it blocked"
   is the ready rule's, and "which of its own waits are pending" is the close
   rule's. A caller that asks what a bead records it waits on, or whether its
   own work sits on another bead, is asking the second. Answering it with the
   first would read an epic's park as a takeaway's wait: the board would band
   tk-georjc, whose ruling recorded no wait, as work in flight. The takeaway's
   route guard would refuse to route a member its epic's park holds, yet
   steering.md expects a park to hold routed members, and the doctor check on
   blocked work flags a member that has neither a route nor an arm.

## What the design-gate sittings settled

The operator ruled the design at 9db113b9 unapprovable as written in the
design-gate sitting (visit tk-ppb4639, 2026-10-28), and settled its rework
there. The rulings, with their provenance, are on tk-ssm8qns.2's notes. The
design follows them.

1. **The bar.** An architecture doc defines, defends and describes. Every
   element states the feature it adds over the native call it wraps, or the
   debt it contains and what retires it, and an element that defends neither is
   cut. A pack-local definition is classed aloud as a feature or as debt.
2. **One surface, classed by caller.** The CLI is a product that defends its
   structure and its value. The CLI table and the domain table become one
   surface table, and each verb carries a caller class. The classes are agent,
   hook and order and no others, because each of them has a registry that
   enumerates its consumers. No verb is internal, since an internal consumer
   cannot be enumerated, and Go packages are implementation beneath the verbs.
3. **Writes stay native, and pack logic reacts, as a floor.** No gctk verb
   parallels an act the native surface already expresses. Pack logic that
   follows a native write reacts through an order. An adversarial stress test
   amended the principle before it was adopted: where the pack owns the writer,
   the writer settles synchronously as a hook and the order stays as the
   backstop. The naive form would have deleted the synchronous half of
   queue-priority's shipped shape.
4. **The order class has an admission rule and a guarantee model.** An order is
   admitted only when it converges from durable state, is idempotent, tolerates
   lag, finds every intent it must keep already stored, reads a bounded set and
   guards its writes with the field's one lock. Its guarantee is per cadence,
   never per change, because the event bus is lossy by design.
5. **Priority shift stays** as the one agent-class priority verb: it writes the
   stored shift and settles the queue in one act. `priority set` dies, because
   an absolute write parallels the native act. Settle is hook-class, and
   reconcile is the order backstop.
6. **The nouns change.** `waits` is a package behind one bead read, which
   answers blocked, pending and one status with own-or-inherited attribution.
   Dispatch decomposes into the bead verbs arm and disarm plus the orders that
   start and dispose. Sessions dissolves, and quota-park nudging is an order.
   Sends dissolves: its acts live under pr, and its containment rule in the
   GitHub adapter. pr derives from Gas City's own PR concept first, and "any
   merge rule GitHub cannot express" is cut as hypothetical.
7. **The record of debts.** The in-flight test is adopted debt. `lifecycle` and
   `merge` and the store adapter's compensations each state why they
   re-implement Gas City's logic, the goal of staying in step, and the risk.
   Quota-park nudging is kept, its warrant is written, and its revisit is
   tk-vtnyw8d.

The check-in sitting (visit tk-weluos5, 2026-10-29) audited that rework against
these rulings. It found a caller class no ruling sanctioned and soft spots in
the text, and settled the fixes, which the design follows.

8. **Names follow the native meaning.** A verb shares a native word where the
   meaning is the same, keeps its word where it does the whole act over a
   native primitive and agents are documented onto it alone, and takes a fresh
   word wherever its answer can differ from the native call it would be taken
   for. The bead read is `bead holds`. Applied across the surface, the test
   also renames the order that starts an armed bead to `bead start-armed`,
   because `unblocked` would read as the store's answer, which differs for a
   bead with a `waits-for` edge of its own.
9. **A verb gets a section only when no steward doc holds its semantics.** A
   row's defense cell carries its whole meaning, and `bead holds` keeps the one
   contract section, since no steward doc defines what holds a bead.
10. **Classes follow call sites.** `review checks` is read by the review
    formula's steps and by the merge cadence, so it is hook and order.
    `review passed` is the script a formula check loop runs, so it is hook.
    `pr status` is hook and order, and its order's bounded scan is stated.
11. **The soft spots are stated.** The start says which write lands
    first and names the window it leaves. `unjudged` comes only from a bead's
    own `waits-for` edge, so a lost listing reads as a failed read. The
    guarantee promises nothing shorter than the cadence.
12. **The breakdown gains duties.** Unit 3's caller census covers the prompts
    and skills that teach the old reads. A unit that edits a file a live branch
    also edits waits on that branch from its filing. Each dated live-store
    figure or timing a unit relies on is read again when that unit builds.

## Rulings on the queued beads

Each of these waits on the Feature by a `blocks` edge. The implementation child
applies the rulings once this design merges.

| Bead | Ruling | Why |
|---|---|---|
| tk-1fv2tn, port pr-open | **Dropped.** Its surviving part becomes the `pr` domain's `compose` verb, built by the merge member (tk-1tfzr71.20). | pr-open.sh does three things. Gating the PR's opening on the review lanes moves to the review-lane member (tk-1tfzr71.22). Opening the PR moves to Gas Town's refinery under the merge member. Only composing the title and the managed summary survives, and the merge member already keeps it "as glue in the step that opens or updates the PR". A port of the whole script would carry the two retiring parts forward. |
| tk-tyopvq, port signoff | **Dropped.** Its surviving part becomes the `review` domain, built by the review-lane member (tk-1tfzr71.22). | That member retires review beads as a pack kind and most of signoff.sh, and keeps the lanes' synthesis and the check loop's check script, which is the surviving intent. The bead's teardown of the remaining shell ports is moot: lifecycle.sh and merge.sh keep no fallback, and the other ports closed as not needed. |
| tk-s8bvzal, cobra across the binary | **Folded into this Feature,** as unit 1, less the part that reaches into retiring code. | The CLI this design draws is cobra's command tree, so adopting cobra is the first step of building it. The bead's added scope has two parts. Moving lifecycle.go's and merge.go's git calls onto `internal/git` is dropped, because both files retire with the merge member, and built-once rule 1 gives them no new work. Their commands join the tree unchanged. Of the five doc comments it names, lifecycle.go's and merge.go's go with those files. prstatus.go's is rewritten with the `pr status` rename, and gcbd.go's and daemon.go's are rewritten when unit 1 makes them the store adapter. |

Dropping the last two fallback ports also leaves `gctk-resolve.sh`'s
`gctk_resolve`, its version-skew guard and `GCTK_FALLBACK` with no caller, at
this commit as before: only `gctk_require`, which `lifecycle.sh` and `merge.sh`
call, is in use. They served only a port that lands with its script kept as the
fallback, so unit 1 deletes them with their cases in `gctk-resolve.test.sh`,
and the `GCTK_FALLBACK` clear in `test-harness.sh` with its cases in
`test-harness.test.sh`.

## The derived nouns against the starting proposal

The epic's notes proposed anchor, waits, dispatch, review, findings, pr,
engagement, disposition, run, convoy, sessions and rig, plus epics and learning.
The surface drawn from the surviving intents keeps some, narrows some, dissolves
or drops the rest, and adds the nouns the proposal did not name.

| Proposed | Derived | Why |
|---|---|---|
| anchor | dropped | The anchor state machine retires toward the states Gas Town's refinery records (tk-1tfzr71.20). The one question that survives about an anchor, which bead owns a PR, is `pr`'s. |
| waits | a package | It answers "is this blocked?", the proof, behind the one bead read `gctk bead holds`. A wait is a projection of bead state, not a new thing, and no surviving intent maps to it. |
| dispatch | dissolved | Only the residual survives: pour on ready, and close on an `until` target's close (tk-1tfzr71.16). Arm and disarm are bead verbs, and `start-armed` and `dispose-resolved` are the orders that act. |
| review | narrowed | Only the lanes' synthesis and the check loop's check script survive (tk-1tfzr71.22). |
| findings | dropped | Finding beads for machine findings retire with the review lanes. |
| pr | narrowed | Title and summary composition, the hop from a GitHub event to its owning bead, the PR status the board shares, and the containment acts that were sends'. It starts from Gas City's own PR concept, and the hypothetical merge rule GitHub cannot express is cut. |
| engagement | dropped | Visits, demands and takeaways move onto Gas City's human gates (the native-gates effort, tk-1tfzr71.4). |
| disposition | dropped | `bd duplicate` and `bd supersede` (tk-1tfzr71.13). |
| run | dropped | `run-cancel.sh` is retained glue, one call over an endpoint with no CLI verb. The map keeps it as shell. |
| convoy | dropped | `gc convoy land`, tracks and Gas Town's auto-land (tk-1tfzr71.23). |
| sessions | dissolved | Only quota-park nudging survives, and nothing in it is a session question an agent asks. It is the `quota-park` noun's order, under its warrant, which the session-liveness member re-checks (tk-1tfzr71.18). |
| rig | kept | Already in gctk. |
| epics, learning | dropped | Retained product the map holds in prose, formulas, skills and doctor checks. Neither is a surviving intent. |
| (new) bead | added | The one bead read, and arm and disarm with the orders that act on an arm. |
| (new) priority | added | Priority following, under its warrant. The field is bd's, and the noun owns the derivation. |
| (new) quota-park | added | Quota-park nudging, under its warrant. |
| (new) dolt | added | Dolt reclaim, under its warrant. |
| (new) seed | added | The seed audit, retained glue the map names as a surviving intent. |

The board's derivations are a surviving intent too, but not a domain. The
board is product, already Go in `services/helm`, and it imports each domain's
questions as the domain moves.

## Who carries each domain move

A domain moves in the change that settles its final shape. Where a migration
member re-expresses the feature, that member builds the surviving residual
directly as the gctk domain, so no residual is written in shell and then
ported. Where no member touches the feature, a later Feature of this epic moves
it after this Feature's checkpoint.

| Domain | Carried by | Notes |
|---|---|---|
| bead's read, `bead holds` over `waits` | this Feature (tk-ssm8qns.3) | The proof. |
| rig | in gctk already | Joins the cobra tree in this Feature, and its `rig_check.<check>` key becomes the ledger's first owned declaration. |
| bead's arm and disarm, and the orders that start and dispose | the deferred-dispatch member (tk-1tfzr71.16) | Its contract re-expresses the residual as one event order on `bead.closed`. Under this design that event only cuts latency, so `gctk bead start-armed` and `gctk bead dispose-resolved` also converge on a cadence, as the admission rule requires, and both ask `waits`. Until then deferred-dispatch.sh asks `gctk bead holds`. |
| quota-park | the session-liveness member (tk-1tfzr71.18) | Only if its re-check keeps the quota-park warrant. |
| pr | the merge member (tk-1tfzr71.20) for composition; the GitHub-intake member (tk-1tfzr71.21) for the owner hop | `prstatus` moves under `pr` with whichever of them rewrites its facts. |
| review | the review-lane member (tk-1tfzr71.22) | |
| the board's shared questions | the board member (tk-1tfzr71.24) | This Feature moves the board's ruled rows onto `waits`. The board imports each other domain's questions as that domain moves. Its ranking and attention model stay in helm. |
| priority, pr's post and guard, dolt, seed | later Features of this epic | The implementation child files each under the epic, waiting on this Feature by a `blocks` edge and not armed, so the epic's checkpoint decides when the next one starts. |
| the ledger's read-back | this Feature builds it | The read-back member (tk-1tfzr71.11) records the warrant and reduces the shell sites. |

## The implementation breakdown

tk-ssm8qns.3 builds unit 1 and files units 2 and 3 as beads, the way its own
description says: under the epic, with `target=integration/tk-ssm8qns.1`, each
waiting on the one before it, and each blocking the landing bead and the
summary task. All three land on the integration branch with no PR of their
own. Its first act applies the rulings above and adds the edges and notes the
next section lists. A unit that edits a file a live branch also edits waits on
the bead that carries that branch, by a `blocks` edge written when the unit is
filed, or for unit 1 when tk-ssm8qns.3 starts, so the overlap is a wait in the
graph from the start and never a conflict found at merge.

**Unit 1: the command tree, the ledger and the store adapter.**

- cobra builds the command tree, and the hand-rolled dispatch and usage text
  go. `lifecycle` and `merge` join the tree with their own flag parsing
  unchanged. `pr-status` becomes `pr status`, and its one shell caller,
  `pr-status-label.sh`, swaps in the same change.
- `internal/gcbd` and `internal/daemon` become the store adapter, with an
  in-memory fake. It uses `gc bd` for writes, for reads that must see a fresh
  write, and for the blocked set, and the supervisor API for other reads. It
  answers a bead with a `waits-for` edge of its own with the `waits-for` error,
  which it takes from the bead's own edges. It also reads the ids the store
  marks blocked, through `gc bd sql` with the query `bd blocked` starts from
  over both of its tables, and answers a marked bead that the listing leaves
  out with a read error, the type a failed read returns. They are distinct
  error types. Its tests on a stub `gc` cover each, and a bead with no
  `waits-for` edge that the stub listing loses gets the read error, never the
  `waits-for` one. If tk-ssm8qns.5 has closed by the time the adapter is built,
  the adapter answers every bead from the listing and reads no marks, and
  tk-ssm8qns.6 closes as not needed.
- When the adapter is built, its read of the blocked set and its marks read
  are timed again on the gc-toolkit store, with the host load beside each
  figure, and the unit's PR sets them against the figures in
  [The boundaries kept](#the-boundaries-kept), which were read on 2026-10-27 at
  host loads of 12 to 24.
- The adapter's acceptance test runs the bd the city runs against a scratch
  store, on a dolt sql-server of its own, since that bd is built without cgo
  and opens no embedded store. Each case builds its beads, then compares the
  adapter's answer with what the store does:
  - a bead with a `blocks` edge onto an open bead is blocked on that bead, and
    bd refuses its close;
  - a bead held only through a blocked parent is blocked through the parent,
    and bd closes it;
  - a parentless bead on an `all-children` gate whose spawner closed with a
    child still open is held out of `bd ready`, and `bd blocked` leaves it
    out. The adapter returns the `waits-for` error, not the read error a
    marked bead the listing leaves out gets;
  - the same gate on a bead whose parent is not blocked is named by
    `bd blocked` as held through that parent. The adapter returns the
    `waits-for` error;
  - a bead whose `any-children` gate one closed child has opened, and that is
    held only through a blocked parent, is named by `bd blocked` as blocked on
    its open spawner. The adapter returns the `waits-for` error;
  - a bead whose `also_blocks` edge holds on an open spawner with no open
    child gets the `waits-for` error too;
  - the marks read names every bead that a case above holds, the one that
    `bd blocked` leaves out included.

  tk-ssm8qns.6 turns each error case into the gate's answer and drops the
  marks read.
- The ledger as docs/gctk-architecture.md states it. Its registry is generated
  from the declarations, and a test fails when the generated file is stale.
  rig's `rig_check.<check>` key moves into a declaration in rig's package, and
  rig's publish writes through the ledger, so the registry has a real owner
  from the start.
- The keys `waits` reads to tell work in flight are `branch`, `merge_result`
  and `rejection_reason`, and the run link Gas City keeps. They are declared
  read-only for it, because their writers have not moved. The change that
  moves a writer takes over its key's declaration.
- CI runs `go vet` and `go test ./...` for `services/gctk` and `services/helm`
  on every PR, and a Go test fails an import that points up or closes a cycle.
- `gctk-resolve.sh` loses `gctk_resolve`, its skew guard and `GCTK_FALLBACK`,
  as the rulings above say.

**Unit 2: `waits` and the bead read.**

- The package answers whether a bead is blocked and on what, which of its own
  waits are pending, which wait edges point into another store, and whether a
  bead is in flight. It reads one snapshot and computes no wait itself.
- `gctk bead holds` prints one JSON record per bead, so a shell caller reads
  the answer with one call. The record carries the bead's status, `blocked`,
  `held`, `unjudged` or `clear`, with the waits behind it and whether each is
  the bead's own or an ancestor's, its own pending waits and when the last one
  landed, its arm, and its wait edges into another store. A bead with a
  `waits-for` edge of its own reads `unjudged`, which is not a failed read.
  Only the adapter's `waits-for` error reads as `unjudged`, and a read error
  returns an error, never a status.
- Go tests on the fake cover every row of the census's disagreement table, a
  failed read, a bead with a `waits-for` edge of its own, which reads
  `unjudged`, a marked bead the listing lost, which gets an error and never
  `unjudged`, each condition that puts a bead in flight, and each status.

**Unit 3: the callers.**

- Before the callers move, every store is read again for the beads whose
  answers the swap changes and which numbered none when last read: a
  `waits-for` or `conditional-blocks` edge (none at 2026-10-27 20:12Z) and a
  bead held only by a demand gate on an ancestor (none at 18:33Z). The unit's
  PR names any it finds.
- The 22 places the census marks "moves" ask `gctk bead holds`, or `waits`
  through the package from Go. `hold-lib.sh`'s five callers swap in the same
  change that deletes `hold-lib.sh`, `hold-lib.test.sh` and
  `hold-lib.fixture.json`, and the test harness stops copying it.
  `until-resolved.sh` keeps the `until` predicate and reads the bead's pending
  waits for its `blocks` clause.
- The board asks `pending` through the package for its ruled rows, from one
  snapshot per render.
- check-wait-is-an-edge lists every wait edge into another store, from the
  bead read, for every bead, not only one with a hold marker.
- Each suite whose caller moved drives it through the built binary over the
  harness's stub store, as the suites that reach `gctk merge` do. Nothing keeps
  two copies equal.
- Each moved caller's suite gives it a bead with a `waits-for` edge of its own.
  A caller that acts holds that bead, and a check or a listing shows the edge
  as unjudged, whatever the caller does when a read fails.
- Every doc, skill and comment that states the hold rule or names
  `hold-lib.sh` says the one rule in the same change: steering.md's park
  sections, deferred-dispatch.md, component-model.md's `hold-lib.sh` row and
  its I14 and `check-armed-dispatch-owed` entries, authority-map.md's row for
  arming deferred dispatch, the waits skill, and the comments in
  `dispatch-path.sh` and `gc-helm.sh`.
- The caller census covers the prompts and skills that teach an agent the old
  reads, bead-context's `--frontier` and an answer composed from raw row reads,
  and not only script call sites. Each one teaches `gctk bead holds` in the
  same change.
- The refinery's median pass time, read from its pass log over a day before
  and after the swap, stays under 552 s.

## Edges and notes the implementation child adds

- A `blocks` edge onto tk-ssm8qns.1 from tk-1tfzr71.16, .18, .20, .21, .22 and
  .24, with a note on each naming the domain it builds. tk-1tfzr71.16's note
  also names the start's window, a sling that lands before its mark is proven,
  which docs/gctk-architecture.md leaves to that member's design of the start
  order.
- A rule-1 note on each member that retires a copy, naming the one rule its
  replacement follows: tk-1tfzr71.12, .15, .17, .19, .20, .21, .22, and
  tk-1tfzr71.4, the native-gates effort's landing bead. Its convoy, tk-iirrmiw,
  is closed, and what waited on the convoy waits on that bead.
  tk-1tfzr71.12's note names the change for a bead slung by hand under a parked
  epic (blocked-census.md).
- The priority, pr post and guard, dolt and seed Features, filed under the epic
  as the carriers table says.

## What the checkpoint reads

The Epic Checkpoint asks whether "is this blocked?" lives in one place with
every caller on it, and whether a change to its rule touches only that place.
Once unit 3 lands:

- In code the deletion plan keeps, every dependency decision is `waits` or the
  store's own query. The ten copies in retiring code are the census's rows,
  each with its member, and their count falls to zero as those members land.
- A change to the rule is a change to the `waits` package and its tests alone.
  Each axis is one case in unit 2's tests, and no other package names it.
- `hold-lib.sh` is gone, and a re-run of the census at the effort's head finds
  no copy the census does not list.

## The boundaries kept

- **Same behavior wherever today's copies agree.** Every copy agrees that a
  blocker at `in_progress` or `hooked` holds, and that an open blocker of the
  bead's own, in its own store, holds. Those answers do not move.
- **Not gascity.** gctk reads the store's blocked set through `gc bd blocked`,
  since the supervisor serves no blocked route. That read took 1.0 to 1.6 s at
  a host load of 24, so no pass needs a new route, and none waits on one. The
  marks read it checks the listing against took 0.3 s at a host load of 12 to
  16, beside 0.5 to 0.6 s for the listing.
- **No refinery pass gets slower than today's 552 s median.** find-work's hold
  read becomes one `gctk bead holds` call in place of `hold-lib.sh`'s reads,
  and unit 3 measures the pass time.
