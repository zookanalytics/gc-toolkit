---
name: Census of "is this blocked?" at b25a5c06, and the answers the one rule changes
description: Every place in gc-toolkit's runtime code that decides whether a bead is blocked, held, parked or ready, taken at b25a5c06, with the dependency rules among them, where their answers disagree, and what happens to each place under the design. Beside it are the store's own rules, read in the bd the city runs and tried against it in a scratch store, the live beads on each disagreement, measured across every store the pack serves, and every answer the one rule in docs/gctk-architecture.md changes, for the operator to approve.
---

# "Is this blocked?": the census and what the one rule changes

The one rule is in
[docs/gctk-architecture.md](../../docs/gctk-architecture.md#is-this-bead-blocked).
This record holds the evidence for it. The places were read at b25a5c06. The
live beads were read on 2026-10-27 at 18:33Z from all seven stores the pack
serves, the city store and six rig stores, each pinned with `--db`.

## The store's rules

Read in bd 1.3.2, the binary on the city's `PATH` (`bd version`: 9b65b9e19,
with Gas City's beads patches on top, which touch none of the code below), at
beads commit 9b65b9e19.

- **Blocked.** A bead is blocked (`is_blocked`) when its status is neither
  `closed` nor `pinned` and one of these holds: a `blocks` or
  `conditional-blocks` edge onto a bead in the same store whose status is
  neither `closed` nor `pinned`; a parent-child parent that is itself blocked;
  or a `waits-for` edge whose gate holds
  (`internal/storage/issueops/blocked_state.go`, `markBlockedTemplateForIssues`).
  The gate reads the spawner's parent-child children (`waitsForGateBlockedSQL`).
  An `all-children` gate, the default, holds while at least one child is
  neither `closed` nor `pinned`, whatever the spawner's own status. An
  `any-children` gate holds while at least one child is neither `closed` nor
  `pinned` and none is `closed`. An edge a formula cook marks `also_blocks`
  also holds while the spawner itself is neither `closed` nor `pinned`. The
  edge rule joins on the target's row, so an edge onto an id the store does not
  hold blocks nothing. A target at `in_progress` or `hooked` blocks.
- **Ready.** `bd ready` offers a bead whose status is `open` (or a custom status
  of category active, and this city declares none), that is not pinned, not
  blocked, not ephemeral, not deferred to a future time, not a child of a
  future-deferred parent, and not of a type the rule excludes: merge-request,
  gate, molecule, rig and the infra types
  (`internal/storage/sqlbuild/ready.go`, `BuildReadyWorkWhere`).
- **Close.** bd refuses a close for open children, or when the bead is blocked
  and has a live `blocks`, `waits-for` or `conditional-blocks` blocker of its
  own. A bead blocked only through its parent closes
  (`internal/storage/issueops/close.go` and `IsBlockedInTx` in
  `dependency_queries.go`). A blocker of its own is live when its status is
  neither `closed` nor `pinned`, a `waits-for` spawner included, so the close
  rule does not read the gate. A bead that its own gate holds on a closed
  spawner closes, and an open spawner whose gate has opened still refuses the
  close.
- **`bd blocked`.** It reads the beads the store marks blocked and lists each
  with its own live blockers, judged as the close rule judges them. A bead with
  none is attributed to its parent, and a bead with neither is left out
  (`internal/storage/issueops/blocked.go`, `GetBlockedIssuesInTx`, which bd's
  embedded and server paths share and `bd ready --explain` reuses). For a bead
  whose own waits are `blocks` or `conditional-blocks` edges, that is the
  store's answer: when none of its own is live, only a blocked parent can mark
  it, so the parent it names is the one it is held through. For a bead with a
  `waits-for` edge of its own it is not. The listing leaves out a parentless
  bead that its own gate holds on a closed spawner, names the parent of one
  that has a parent, and names a spawner whose gate has opened. It also
  discards a failed parent read, which drops every bead held through its
  parent with no error. Upstream main at 41b0a80dd has the same code, and
  `bd show --json` carries neither `is_blocked` nor an edge's gate.
- **Statuses.** `hooked` is a work-in-progress status like `in_progress`, and
  `pinned` is a frozen one like `deferred` (`internal/types/types.go`,
  `BuiltInStatusCategory`).
- **The supervisor** serves `/beads/ready` and no blocked route (Gas City
  `internal/api/supervisor_city_routes.go`), so a reader of the blocked set
  reads it through `gc bd blocked`. On the gc-toolkit store at a host load of
  24, `gc bd blocked` took 1.0 to 1.6 s and `gc bd ready` 1.3 to 1.4 s.

On 2026-10-27 the bd the city runs gave these answers in a scratch store, on a
dolt sql-server of its own:

| Case | The store marks it blocked | `bd blocked` | `bd close` |
|---|---|---|---|
| A parentless bead on an `all-children` gate whose spawner closed with a child still open | yes | leaves it out | closes it |
| The same gate, on a bead whose parent is not blocked | yes | names the parent | closes it |
| A bead whose `any-children` gate one closed child has opened, held only through a blocked parent | yes | names the open spawner | refuses, naming the spawner |
| A bead with a `blocks` edge onto an open bead | yes | names that bead | refuses |

The first case needs no forced close: a spawner that closes with no children
and then gains one leaves its waiter in the same state. No store held a
`waits-for` or `conditional-blocks` edge when all seven were read again at
20:12Z.

## The census

A read-only sweep covered every runtime directory: `assets/scripts` without the
suites, formula step text, doctor checks, orders, agents, overlays, skills,
tools, and `services/helm` and `services/gctk` without their tests. A place is
one decision site that acts on the answer, and a shared library counts at its
callers. Two places share a rule only when they give the same answer on every
axis in the next section.

| | Places | Rules |
|---|---|---|
| The 2026-10-16 census, taken in the sitting on visit tk-ke61a5r | about 78 | about 34 |
| its share that is blocked by a dependency alone | 25 | 5 |
| This census, every sense of blocked, held, parked or ready | 105 | 74 |
| its share that is blocked by a dependency alone | 46 | 27 |

The two were taken with different scope and grouping, so their numbers do not
compare directly. This one splits a rule wherever two places handle a failed
read differently. That handling is each caller's policy, not the rule, and
with it set aside the 27 dependency rules are 21. The sweep marked 28 more
places uncertain. 18 of them check that an edge a writer just wrote is there,
which is the writer's read-back, not a decision about whether a bead is
blocked. The other 10 are hold, park, status and dispatch-path readings at the
edge of the senses. None of the 28 is counted above.

Only the dependency rules are "is this blocked?". The other senses are other
questions, and the design moves none of them into `waits`.

| Sense | Rules | What it reads | Where it goes |
|---|---|---|---|
| A hold marker | 16 | `merge_hold`, `rebase_hold`, `triage.hold`, `blocked_reason`, a takeaway, review quiescence, a live must-fix finding, an arm read as a hold | each marker belongs to the act it pauses, mostly a merge, and retires with the merge, GitHub-intake, review-lane or intake member (tk-1tfzr71.20, .21, .22, .17) |
| A park for a person | 11 | `gc.routed_to=human`, `placement=pending`, visits | the native-gates effort (tk-1tfzr71.4) turns a wait on a person into a gate, which is a wait the store holds; placement is intake's (tk-1tfzr71.17) |
| A bead's own status | 11 | `hooked`, `in_progress`, `blocked`, `deferred`, `pinned` as the bead's own | not a wait. The store's ready rule adds status to the blocked answer, and each status reader's question is its own |
| Ready and composite | 9 | a dispatch path, the merge cadence's composite holds, the liveness classifiers | the dispatch member and the members that retire the cadence and the census |

### The dependency rules

Each rule is named for its family. The axes are those of the next section.

| Rule | What counts as blocked | Pinned blocker | Ancestor's blocker | Edge into another store |
|---|---|---|---|---|
| D1 to D6, the store's own queries | `bd ready`, `gc bd ready`, a pool's work query, `bd list --ready`, `bd blocked` | resolved | holds | holds nothing |
| D7 to D10, `hold-lib.sh` | a `blocks` edge on the bead or an ancestor onto a bead not closed or pinned. A demand gate on an ancestor does not hold, and a bead carrying `branch`, `merge_result` or `rejection_reason` reads only its own edges. D7 also slings what `bd list --ready` offers | resolved | holds, except a demand gate | holds as unread on the bead itself, nothing on an ancestor |
| D11 to D13, D17, D18, D21 to D26, own edges | a `blocks` edge on the bead itself onto a bead whose status is not `closed` | holds, and gc-helm's park accepts a pinned bead as a target | ignored | ignored (D11 to D13, D17, D18, D24, D25), read at its status in its own store (D21, D22), reported stale (D23), refused at write time (D26) |
| D14 to D16, own edges at a live status | a `blocks` edge onto a bead at open, in_progress, blocked, deferred, hooked or pinned. D15 also counts the bead's children and the beads that name its PR | holds | ignored | ignored |
| D19, D20, the `until` disposal | a `blocks` edge on the bead onto a bead not closed, beside its `until` targets | holds | ignored | leaves the bead unresolved, never disposed |
| D27, a write-time refusal | a wait the caller names in another store is refused | n/a | n/a | refused |

### Every dependency place, and what happens to it

"Moves" means the place asks `waits` once the implementation lands:
`blocked` is "is this bead blocked, and on what", and `pending` is "which of
its own waits are pending". "Stays" means the place already asks the store's
own query, which is the rule. "Retires" means the deletion plan removes the
code the place sits in, so under built-once rule 1 the place gets no new work,
and the member that retires it gets a note naming the one rule its replacement
follows.

| Place | Rule | After |
|---|---|---|
| `assets/scripts/deferred-dispatch.sh:442-457`, `arm`'s note | D7 | moves: blocked |
| `deferred-dispatch.sh:770-808, 1577-1589, 1647-1657`, `reconcile_dispatch` | D7 | moves: blocked |
| `deferred-dispatch.sh:861-878`, `list` | D7 | moves: blocked |
| `deferred-dispatch.sh:1299-1337` with `until-resolved.sh:200-239`, the `until` scan | D19 | moves: pending |
| `deferred-dispatch.sh:1356-1379` with `until-resolved.sh:256-280`, the `until` re-read | D20 | moves: pending |
| `deferred-dispatch.sh:1154`, `until_confirm` | D20 | moves: pending |
| `doctor/check-until-resolved-owed/run.sh:171-195` | D19 | moves: pending |
| `doctor/check-until-resolved-owed/run.sh:199-217` | D20 | moves: pending |
| `doctor/check-armed-dispatch-owed/run.sh:327-357` | D9 | moves: blocked |
| `formulas/mol-refinery-patrol.toml:156-184`, find-work | D8 | moves: blocked, as a call-site swap; the formula's step retires with tk-1tfzr71.20 |
| `doctor/check-refinery-patrol-live/run.sh:158-185` | D8 | moves: blocked, as a call-site swap; the check retires with tk-1tfzr71.20 |
| `formulas/mol-witness-patrol.toml:937-965`, check-refinery | D10 | moves: blocked, as a call-site swap; the step retires with tk-1tfzr71.19 |
| `assets/scripts/gc-helm.sh:969-983`, takeaway `--release` | D11 | moves: pending |
| `gc-helm.sh:1014-1036`, takeaway `--route` and `--assign` | D12 | moves: pending, less the bead's own demand gate |
| `gc-helm.sh:1821-1825, 1862-1886`, park `--waiting-on` | D26 | moves: the new edge is read back through pending, so a target that holds nothing is refused |
| `assets/scripts/bead-context.sh:295-301, 550-559`, `--frontier` | D22 | moves: blocked |
| `assets/scripts/patrol-finding.sh:304-310, 350-367` | D21 | moves: pending |
| `doctor/check-wait-is-an-edge/run.sh:200-236, 389-401` | D23 | moves: pending, with the edges into another store from foreign |
| `doctor/check-step-terminal/run.sh:261-317, 348-352` | D24 | moves: blocked |
| `agents/mechanik/prompt.template.md:197-200`, the wait on an effort's summary | D18 | moves: pending |
| `services/helm/internal/source/beads.go:1033-1058` with `internal/board/derive.go:317-346, 635-656`, `ruled` and `ruledInFlight` | D25 | moves: pending, through the package |
| `services/helm/internal/board/derive.go:674-677`, `dispositionDue` | D25 | moves: pending, through the package |
| `assets/scripts/queue-priority.sh:718-736` | D1 | stays |
| `doctor/check-blocked-work-armed/run.sh:189-286` | D6 | stays |
| `doctor/check-claim-advancing/run.sh:452-475` | D1 | stays |
| `doctor/check-root-advancing/run.sh:241-260` | D1 | stays |
| `agents/proactive/agent.toml:39-44`, `work_query` | D3 | stays |
| `agents/proactive/agent.toml:52-57`, `scale_check` | D3 | stays |
| `tools/gc-proactive.sh:673-700`, `demand` | D3 | stays |
| `tools/gc-proactive.sh:780-800, 866-900`, `scan` | D1 | stays |
| `deferred-dispatch.sh:575-583, 637-653, 673-705`, `notify` | D4 | retires with tk-1tfzr71.16, the notify path |
| `deferred-dispatch.sh:887-896, 960-1013`, `reconcile_notices` | D4 | retires with tk-1tfzr71.16 |
| `assets/scripts/liveness-sweep.sh:158, 352-362` | D1 | retires with tk-1tfzr71.19 |
| `assets/scripts/liveness-sweep-precheck.sh:209, 275-281` | D1 | retires with tk-1tfzr71.19 |
| `assets/scripts/liveness-recheck.sh:155, 175-185, 228-268` | D2 | retires with tk-1tfzr71.19 |
| `liveness-sweep.sh:400-407` | D13 | retires with tk-1tfzr71.19 |
| `doctor/check-routed-work-claimable/run.sh:243-485` | D5 | retires with tk-1tfzr71.15 |
| `gc-helm.sh:4253-4264`, `engage` | D11 | retires with the native-gates effort, tk-1tfzr71.4 |
| `assets/scripts/finding.sh:1179-1196` | D13 | retires with tk-1tfzr71.22 |
| `finding.sh:1397-1427` | D13 | retires with tk-1tfzr71.22 |
| `finding.sh:1428-1452` | D13 | retires with tk-1tfzr71.22 |
| `assets/scripts/gate-ensure.sh:319-332, 399-400` | D16 | retires with tk-1tfzr71.22 |
| `assets/scripts/pr-facts.sh:2645-2649` | D14 | retires with tk-1tfzr71.21 |
| `services/gctk/internal/cli/merge.go:554-575, 1518-1570` | D15 | retires with tk-1tfzr71.20 |
| `formulas/mol-polecat-work.toml:330-356`, load-context | D17 | retires with tk-1tfzr71.12, which inherits load-context from core |
| `assets/scripts/first-reaction-dispose.sh:326, 345, 375` | D27 | retires with tk-1tfzr71.17 |

So 22 places move onto `waits`, 8 already ask the store, and 16 sit in code the
deletion plan retires. 6 of those 16 ask the store too. The other 10 are copies
of a different rule, and each stays until its member deletes it.

## Where the copies disagree, and the one rule's answer

| Axis | Today's copies | The one rule |
|---|---|---|
| A pinned blocker | resolved in the store's queries and `hold-lib.sh`; holds in every own-edge copy; gc-helm's park accepts a pinned target | resolved |
| A blocker on an ancestor | holds in the store's queries and `hold-lib.sh`; ignored by every own-edge copy | holds work that has not started; work in flight is held only by its own waits |
| A demand gate on an ancestor | holds in the store's queries; `hold-lib.sh` exempts it, under the operator's earlier ruling that waiting on that decision does not hold armed work | holds work that has not started, as every gate does (design.md, departure 5) |
| An edge onto a bead in another store | holds nothing in the store's queries and most own-edge copies; holds as unread in `hold-lib.sh`, though D7 still slings what `bd list --ready` offers; read at its real status (D21, D22); never disposed (D19, D20); reported stale (D23); refused at write time (D26, D27) | holds nothing; listed for a doctor check; refused at write time by the ledger |
| A blocker at `hooked` or `in_progress` | holds everywhere | holds |
| A bead whose own status is `hooked` | not ready for the store; stranded in deferred dispatch's list; refused by `arm`; parked at load-context; claimed for bead-context, gc-helm's park survey and queue-priority; idle on the board | in flight; its status is not a wait, so only its own waits hold it |
| The statuses that resolve a blocker | closed or pinned (D1 to D10); closed only (D11 to D13, D17 to D26); anything outside the live set (D14 to D16), so a custom status resolves there | closed or pinned |
| The edge types that hold | `blocks`, `conditional-blocks`, `waits-for` and the cascade in the store's queries; `blocks` alone elsewhere; D15 adds children and PR references, and D19 and D20 add `until` | the store's. A child or a PR reference that holds a merge is the merge's own rule, and `until` is dispatch's disposal, not a wait. A bead with a `waits-for` edge of its own gets an error until bd's listing judges the gate |
| When a bead is in flight | `hold-lib.sh`: it carries `branch`, `merge_result` or `rejection_reason` | steering.md's definition, which adds a claim and a run past load-context |
| A failed read | refuse, proceed, held or empty, by caller | an error. Each caller keeps its own policy for what an error means |

## Live beads on each disagreement

Read at 2026-10-27 18:33Z. Counts are per store. The gc-toolkit store's beads
are named. Other stores belong to other rigs, so they appear here only as
counts.

| What | gc-toolkit store | other stores |
|---|---|---|
| a bead whose blocker is pinned | none | none |
| a bead at `hooked`, or one whose blocker is `hooked` | none | none |
| a `conditional-blocks` or `waits-for` edge | none | none |
| a bead with an edge onto an id its store does not hold | 3: tk-nt5uda, which an open blocker in its own store also holds; tk-7rea7j and tk-r05k0v, both routed to a person, which the store lists as ready | none |
| a bead the store blocks only through an ancestor | 184, all open, under 19 blocked parents | 8, all open, under 3 blocked parents, in one store |
| of those, one in flight | none | none |
| of those, one held only by a demand gate higher up | none | none |
| of those, one armed | 2: tk-ikpyzn.14 and tk-3ybhqhp.2 | none |
| of those, one routed | 1: tk-georjc, to a person | 1, to a person |
| an armed bead on which `hold-lib.sh` and the one rule differ | none of 76 | none of 23 |
| a refinery handoff on which they differ | none of 3 | none of 4 |
| a bead at status `blocked` with no wait of its own | 1: tk-g22m11, held by `blocked_reason` | 1 |

## The answers that change, for approval

### On live beads

- **bead-context's frontier reads the 192 beads held through an ancestor as
  blocked.** Today it reads them as ready.
- **A doctor check lists the three edges into another store**, on tk-nt5uda,
  tk-7rea7j and tk-r05k0v. The check that a wait is an edge already reports
  tk-7rea7j and tk-r05k0v as holds that rest on no live edge, and it still
  does.

Nothing changes for deferred dispatch, the refinery's queue or the witness's
check on it: the 99 armed beads and the 7 handoffs read the same under both
rules. The board's ruled rows and gc-helm's takeaway guards ask `pending`, the
bead's own waits. So tk-georjc keeps its row, and a sitting can still route or
assign it, or any of the 192 beads above. The route guard refuses a bead whose
own work sits on a blocker, and a parked parent's members still carry their
own work, which reaches the pool once the park is released
([steering.md](../../docs/steering.md#what-a-park-holds)).

### With no live bead on them today

- A pinned blocker is resolved everywhere. gc-helm's park refuses a pinned bead
  as the target of `--waiting-on`, since an edge onto it holds nothing.
- A demand gate on an ancestor holds the work under it that has not started.
  `hold-lib.sh`'s exemption goes.
- `conditional-blocks` holds wherever the store says it does. A bead with a
  `waits-for` edge of its own gets an error from `waits` until the bd the city
  runs judges the gate in its listing and its close rule
  ([design.md](design.md#what-the-operator-approves)).
- A claimed bead, and a bead with a run past load-context, is in flight, so an
  ancestor's wait no longer holds it in deferred dispatch.
- An own blocker in another store no longer keeps a handoff out of the
  refinery's queue, and no longer stops an `until` disposal.

### Left to the members that retire the copies

Each of these members gets a note naming the one rule, and its replacement asks
`waits`.

- **Load-context (tk-1tfzr71.12).** A bead slung by hand under a parked epic is
  built today, because load-context reads only the bead's own edges. Under the
  one rule it would be refused, since its work has not started. The member
  decides whether the pack keeps a guard at load-context once it inherits
  core's.
- **The merge, review and GitHub-intake members (tk-1tfzr71.20, .22, .21).**
  `merge.go`, `gate-ensure.sh` and `pr-facts.sh` count a blocker at any live
  status, a pinned one included, and `merge.go` also holds a merge on the
  bead's children and on beads that name its PR. Which of those holds survive
  is merge policy, for tk-1tfzr71.20's design.
- **Visits (tk-1tfzr71.4), the liveness census (tk-1tfzr71.19), intake
  (tk-1tfzr71.17) and the routed-work check (tk-1tfzr71.15)** retire their
  copies whole.
