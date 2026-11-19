---
name: Gas City search for a stay that comes back before the operator's next decision
description: Use when you review or build a unit of the design in specs/tk-ai367om/design.md, in which a staying sitting promises its return with a return gate of the pack's own that the landing order closes, and need the Gas City, bd and GitHub primitives each piece of its surface composes, what was searched for each and found not to cover it, and why the promise is a gate kind defined in gctk, the closer is the landing order, the wake is Gas City's for ready assigned work, the stay's own wait is a convoy, the hold is the conversation's existing hold on a PR's merge, the readers take one rule from gctk, and a visit and a fresh context need nothing from Gas City.
---

# Gas City search: a stay that comes back before the operator's next decision

The design has a staying sitting promise its return with a return gate, a gate
of the pack's own kind, which the landing order closes when the work is ready
for the operator's next decision. bd then reads the sitting's conversation as
ready work, and Gas City wakes the sitting for it. The sitting reads the result,
and waits for the operator to discuss it, while the PR's merge waits for that
discussion. Its surface is listed in the design's section 13. This record names,
for each piece, the primitive it composes and what else was searched.

Gas City citations are at upstream `gastownhall/gascity` main 17d7d77ce2, bd
citations at beads v1.3.4, and the pack's at integration/tk-vrg93t0 2a6fd322e.
The searches made for the stay before this one are
`specs/tk-pb9wnr3/gas-city-search.md` (the stay of PR #1480) and
`specs/tk-blwi68h/gas-city-search.md` at PR #1515's head 6ffdc541f (a stay on
the conversation's own subject). Their findings that this record relies on were
read again at the commits above.

## The promise: a gate of the pack's own kind

**What it composes.** A bd gate. `bd gate create` files a bead of issue type
`gate` with the await type its `--type` names, which it does not check, and the
await id its `--await-id` names, and writes the `blocks` edge of the bead its
`--blocks` names onto the gate (`buildGateIssue` and `gateCreateCmd` in
`cmd/bd/gate.go`). The bead that waits leaves `bd ready` until the gate closes.
This is bd's shape for waiting on a state other than a close: a bead stands for
the state, and its close releases what waits on it. bd's help for `bd gate`
says gates "must be closed (manually or via watchers) for the blocked step to
proceed".

The return gate's await type is the pack's own, `stay-return`. bd's own check
evaluates `gh:run`, `gh:pr`, `timer` and `bead` gates and passes over every
other await type (`evaluateGates` in `cmd/bd/gate.go`; `isMachineCheckableGate`
in `cmd/bd/close.go` lists the same types). Gas City's core sweep runs
`gate check --type=timer` and `--type=gh` in each store
(`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). So the pack's
closer is the gate's only one. The gate watches the work through bd's `tracks`
edge, the relation a convoy uses for its members. bd's cycle check does not walk
it (`types.IsSchedulingEdge`), and Gas City's convoy rules read it only on a
bead of type `convoy` (`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`).

**What else was searched.**

- **bd's own gate types.** A human gate waits for a person. A timer gate waits
  for the clock, and a `gh:run` gate for a workflow run. A `gh:pr` gate closes
  only when its PR merges (`checkGHPR`), after the decision the return is for. A
  `bead` gate closes when another bead closes, and Gas City's sweep skips it
  (the header of `gate-sweep.sh`). None closes when a PR becomes ready for the
  operator's approval, and none sees a rework round end on a PR already out of
  draft.
- **A GitHub gate that closes when a PR leaves draft**, if bd or Gas City added
  one. It would cover new work's first round. A send-back that the review run
  answers with no push ends its round on a PR that never returned to draft
  (`cmd_push` in `assets/scripts/review-run.sh`), so the pack would still need a
  closer of its own.
- **Gas City's session wait**, the previous revision's promise
  (`gc session wait <session> --on-beads <ids> --note <text>`). These
  behaviors of it keep it from holding a sitting's promise:
  - An attach that starts a sleeping session cancels the session's waits:
    `Store.WakeSession` calls `cancelWaitsAndCollectNudgeIDs` as it starts the
    session (`internal/session/wait_store.go`). It is filed in the Gas City rig
    as gc-gspdoo, which records it as a regression from upstream #9011.
  - A fresh restart cancels each wait registered before it, as
    `continuation-stale` (`WaitInfo.ContinuationStale` in
    `internal/session/waits.go`, and its `CancelWait` call in
    `cmd/gc/cmd_wait.go`). It is filed as gc-lwa1vp.
  - A ready wait does not wake a session that slept at the end of its idle
    window. The idle latch lets a demand through only by
    `wakeDemandOverridesSleepSuppression` (`cmd/gc/session_reconciler.go`),
    which passes an attach, assigned work, an explicit wake, routed demand, pool
    demand on a non-interactive session and the min-active floor, and no ready
    wait. Unit 1's probe showed it on the city's gc in a scratch city
    (tk-u41ko5k's notes). It is filed as gc-qxq03t.

  A gate in the store meets none of these, because a session's start and its
  restart change neither the conversation nor its gate.
- **A `blocks` edge onto the work.** It clears only when the work closes, which
  for a PR is after the merge. It also meets the hold's cycle and the subject's
  one edge (the stay's wait, below).
- **A plain gate, or a task, that the pack closes.** A reader could not tell it
  from a person's: the board counts a gate with no await type as a person's
  (`sweptGate` in `services/helm/internal/board/state.go`), as the park gate
  `gc-helm.sh park` files is, and a task reads as work. The await type is the
  field bd gives a gate for what it waits on.
- **A metadata key naming the gate's kind.** bd's await type already carries it,
  and the store's lite read includes it (`IssueBaseColumnsLite` in
  `internal/storage/sqlbuild/sqlbuild.go`), so a key would be a second field for
  one fact.

## Filing it: `gctk gate return`

**What it composes.** Native writes in one order: `bd gate create` with the type
`stay-return`, the conversation as both the bead it blocks and its await id,
then a `tracks` edge from the gate onto each bead it watches (`bd dep add`), then
the removal of the conversation's other `blocks` edges onto a convoy or a return
gate (`bd dep remove`), which leaves a park or any other wait on it in place. The
verb carries the sitting's one intent, to come back when this work is ready for
the operator's next decision, through every step: it finds the conversation's
open gate before it files one, writes the edges in the order that keeps the
conversation waiting throughout, and refuses a gate nothing would close, on a
bead in another store, on a bead that has closed, or in a store the landing
order does not read.

**What else was searched.**

- **`bd gate create` alone.** It files the gate and the conversation's edge onto
  it, but not the watch, and it leaves the stay's edges onto its convoys. bd
  reads a bead ready only once every bead it waits on through a `blocks` edge
  has closed, so the conversation would come back only once its work had closed.
- **The sitting typing the writes itself.** That is several writes in one order
  and refusals the sitting would derive each time, the steps gctk's verbs take
  out of an agent's hands.
- **The sign-off filing the gate.** `converse-signoff.sh --stay` cannot tell a
  stay that awaits a return from one that follows a settled exchange without a
  new flag, and whether to promise the return is the sitting's call, as the
  previous revision's session wait was. A flag would grow a script whose new
  intent gctk can hold.
- **Gas City's session wait**, above.

## Closing it: the landing order

**What it composes.** The landing order's pass (`gctk pr reconcile`, the
rig-scoped exec order `orders/pr-reconcile.toml` on a five-minute cooldown)
already decides the end of a round: `readyBar`'s conditions other than the draft
flag (`services/gctk/pr/draft.go`, `decide` in `services/gctk/pr/landing.go`).
At that moment it writes the hold and closes the gate, a native close. In the
same pass it closes a return gate whose watched bead has closed, or whose
conversations have all closed. The review-lanes design placed the wake at this
point of the pass, in its section 9 (`specs/tk-1tfzr71.108/design.md`).

**What else was searched.**

- **Gas City's core gate sweep and `bd gate check`.** They close only the types
  bd evaluates, and none of those closes at a PR's readiness (above).
- **An order of its own.** Order triggers are cooldown, cron, condition, event
  and manual (`Trigger` in `internal/orders/order.go`). The end of a round is
  decided inside the landing order's pass, so a second order would only decide
  it again.
- **The ready transition alone.** A round that ends with no push leaves the PR
  ready, with no transition to close the gate at (`cmd_push` in
  `assets/scripts/review-run.sh`), so the order reads the end of the round
  instead.
- **Gas City's event on a bead's close**, for a gate whose watched bead closed.
  The core order `cascade-nudge-on-blocker-close` runs on `bead.closed` and
  nudges the assignees of the closed bead's dependents
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`).
  The gate watches its work through `tracks`, so it is no dependent of the work,
  and a nudge closes nothing. The landing order's pass reads the gate's watched
  beads instead.

## The sleep and the wake: Gas City's, unchanged

**What it composes.** The conversation is assigned to its sitting. A manual
session sleeps after its idle window while it is not attached and what is
assigned to it only waits on something open (`computeAwakeSet` in
`cmd/gc/compute_awake_set.go`: "Blocked open assignments do not prevent idle
sleep"), so the conversation's edge onto the open gate lets the sitting sleep,
as the stay's edge onto its work does today. Once the gate closes, the
conversation is ready work assigned to the sitting (`workBeadHasAwakeDemand`),
and Gas City wakes the session for it, even when it slept at the end of its idle
window (`HasAssignedWork` in `wakeDemandOverridesSleepSuppression`), and resumes
its thread under `wake_mode = "resume"`. A sitting still up gets the notice the
core order `cascade-nudge-on-blocker-close` sends the assignee of a closed bead's
dependent. The stay probe ran this path on a sitting asleep with sleep reason
`idle`: the close of what its conversation waited on woke it on its session key
with its thread, and its claim read `ready_assignment` (the edge path in
`specs/tk-pb9wnr3/stay-probe.md`).

**What else was searched.**

- **A nudge from the order.** `gc session nudge`'s `queue` delivery "never wakes
  the session" (`docs/reference/cli.md`, `gc session nudge`), and the
  conversation's readiness already wakes it with no write of the order's.
- **The session wait's wake**, above.

## The stay's own wait: a convoy

**What it composes.** The stay that follows a settled exchange, and every stay
until its sitting promises the return, waits on its work's close through a
convoy that tracks the work alone and carries no `owned` label, which Gas City
closes once the work closes (`convoyStillAutocloses`). A graph.v2 pour on a bead
that is not a convoy mints a fresh one-item convoy that tracks it
(`NormalizeInputConvoy` and `CreateSingleItemInputConvoy` in
`internal/graphv2/invocation.go`), as a formula's sling of the work and each
review run do. The sign-off waits on the newest open one, the rule
`subject_convoy` applies at PR #1515's head, and when none is open it makes one
with `gc convoy create <name> <bead>` (`docs/reference/cli.md`,
`gc convoy create`, without `--owned`).

**What else was searched.**

- **An edge onto the work itself.** The hold is the PR's bead's `blocks` edge
  onto the conversation, which bd refuses while the conversation blocks on that
  bead, because its cycle check walks `blocks`, `conditional-blocks` and
  `parent-child` edges (`types.IsSchedulingEdge`, beads
  `internal/types/types.go`). The convoy reaches the bead by `tracks`, which the
  check does not walk.
- **An edge onto the conversation's own subject.** The conversation tracks its
  subject, and bd keeps one edge from a bead onto another
  (`DependencyTypeConflictError`).
- **The ruling's ask.** On the review path the run's `record` step closes the ask
  before the refinery validates the head the operator approves (the review-lanes
  design, sections 1, 5 and 8, in `specs/tk-1tfzr71.108/design.md`), so the
  sitting would come back, and the conversation would stop reading as a stay,
  before the round ends.
- **The return gate as the stay's only wait.** A stay that follows a settled
  exchange waits for its work's close alone. A return gate filed then would close
  on the landing order's next pass, at the end of the round the operator has just
  discussed.

## The hold: the conversation's existing hold on a PR's merge

**What it composes.** A conversation on an open PR holds its merge through the
anchor's `blocks` edge onto it (`conversation_hold_merge` in
`assets/scripts/gc-helm.sh`; `docs/human-engagement.md`, "A conversation on an
open PR holds its merge"). The evaluator reads that edge as a wait of the bead's
own (`ownWaits` and `KindWait` in `services/gctk/pr/pr.go`), and `prstatus`
reads it as the city's work while the conversation stays and as the operator's
move once it does not (`Render`; `Staying` and `Owed` in
`services/gctk/prstatus/gates.go`). The landing order writes the same edge at
the end of a round, before it closes the gate, and the sitting lifts it on the
operator's settlement with `gc bd dep remove`, as `converse-hold` lifts it
today. No condition, key or state comes with it.

**What else was searched.**

- **The sitting writing the hold at its return.** The minutes between the end of
  the round and the sitting's first write would hold nothing, and a sitting that
  did not wake would hold nothing at all.
- **A condition of the evaluator's**, which the first draft added for a stay
  that owed a reading. It read the stays, their rounds and the PR's comments on
  every pass. The edge is a wait the evaluator already reads.
- **Keeping the PR a draft.** The operator ruled it out, so that CI and GitHub's
  review request go on while the sitting reads. GitHub requests no review on a
  draft and this repository's CI skips its suite on one
  (`.github/workflows/tests.yml`), but a draft does not hold a PR that is ready
  already, as after a round with no push, so it cannot be the hold.
- **`merge_hold`.** It is the operator's freeze, theirs to lift
  (`lifecycle/lifecycle.toml`, beside `settled_keys`), not a hold the city puts
  on and a ruling lifts.
- **GitHub's review request or a required check.** Either would make the return
  one of the PR's checks, which the initiative's boundaries rule out.
- **GitHub's `dequeuePullRequest`.** The landing order leaves a PR in its base's
  merge queue to GitHub (`decide` returns before `readyBar` and the evaluator for
  one), and no rig in the city has a merge queue on its default branch
  (`repository.mergeQueue`, read for each rig on 2026-11-16).

## The readers: one rule in gctk

**What it composes.** The await type bd stores on the gate, and one rule in
gctk's `gate` package that says, for an await type, whether the city or a person
closes a gate of that type. The main board, the rig board and the human-gate
rule's Go readers read it there (the design's section 2).

**What else was searched.**

- **bd's own answer.** bd stores no field that says who closes a gate. Its
  `isMachineCheckableGate` names only the types bd checks itself, so it would
  read the return gate as a person's.
- **Gas City's API.** The supervisor API's bead carries no await type (`apiBead`
  in `services/helm/internal/source/supervisor.go`), so the board's fallback onto
  that API cannot tell the return gate from a park. The board reads the store
  directly unless that read fails its startup probe.
- **Each reader keeping its own list.** That is the state the readers are in
  now, where the main board, the rig board and the scripts each apply a rule of
  their own (the design's section 2), and a new kind would be added to each.

## Ending a stay

**What it composes.** The sign-off without `--stay` closes the conversation and
releases its holds with the close. The landing order then closes the
conversation's open return gate on its next pass, since nothing the gate blocks
is open, so no return gate outlives its conversation and the sitting runs no
command of its own for it. A stay never drains, because the core reaper closes
drained sessions older than a day (`gc session prune --state drained` in
`internal/bootstrap/packs/core/assets/scripts/reaper.sh`), and a closed session
leaves the return to a sitting with no thread.

## What it leaves in place

- **The minutes between the end of a round and the sitting's post**, while the
  PR reads `needs-attention`, held by the conversation, and the sitting has not
  yet posted what it found.
- **A watched bead's close reaches the gate on the landing order's next pass**,
  up to its cooldown later than a convoy's close would wake the sitting.
- **A return never promised.** A restart between the stay and the promise leaves
  the conversation waiting on its work's close, and the sitting promises the
  return when its entry reads `waiting` with no open return gate.
- **A bead whose round ends while the sitting holds the conversation for
  another** is held only once the sitting promises again and the landing order's
  next pass finds the new gate.
- **The board's supervisor fallback** reads a staying conversation as parked.
- **A sitting whose session has closed** is not woken. The hold still goes on
  at the end of the round, and the return starts once the operator engages the
  conversation.
- **A rig on the old review path** has no end of a round to close a gate at, so
  the sitting promises nothing there. Its rework stay comes back when the
  rework reaches the branch, and its other stays after the merge. The code
  nearest a readiness there, `gate-ensure.sh`, is on the deletion plan with
  tk-1tfzr71.122, so it gets no new work.
- **A merge already requested.** On a base that requires a merge queue, GitHub
  merges a queued PR once the queue's checks pass, whatever the sitting holds,
  and no rig in the city has one on its default branch.
