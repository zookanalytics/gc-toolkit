---
name: Gas City search for a stay that comes back before the operator's next decision
description: Use when you review or build a unit of the design in specs/tk-ai367om/design.md, in which a staying sitting promises its return with a bd gate of a type the pack defines, gctk:needs-review, that the landing order resolves from a PR's own status, and need the Gas City, bd and GitHub primitives each piece of its surface composes, what was searched for each and found not to cover it, and why the promise is a gate type defined in gctk, its condition is a view in the pack's status owner, the closer is the landing order, the wake is Gas City's for ready assigned work, a conversation waits on one gate and on no convoy, the hold is the conversation's existing hold on a PR's merge, the readers take one rule from gctk, and a visit and a fresh context need nothing from Gas City.
---

# Gas City search: a stay that comes back before the operator's next decision

The design has a staying sitting promise its return with a bd gate of a type
the pack defines, `gctk:needs-review`, which the landing order resolves once
the work's PR is left with the operator's part. bd then reads the sitting's conversation as
ready work, and Gas City wakes the sitting for it. The sitting reads the result,
and waits for the operator to discuss it, while the PR's merge waits for that
discussion. Its surface is listed in the design's section 13. This record names,
for each piece, the primitive it composes and what else was searched.

Gas City citations are at upstream `gastownhall/gascity` main 17d7d77ce2, bd
citations at beads v1.3.4, and the pack's at integration/tk-vrg93t0 2a6fd322e.
The pack's status owner and its landing order were read again at main
39099392f, and pull request 1612 at its head a1be1e0c6.
The searches made for the stay before this one are
`specs/tk-pb9wnr3/gas-city-search.md` (the stay of PR #1480) and
`specs/tk-blwi68h/gas-city-search.md` at PR #1515's head 6ffdc541f (a stay on
the conversation's own subject). Their findings that this record relies on were
read again at the commits above.

## The promise: a bd gate of a type the pack defines

**What it composes.** A bd gate. `bd gate create` files a bead of issue type
`gate` with the await type its `--type` names, which it does not check, and the
await id its `--await-id` names, and writes the `blocks` edge of the bead its
`--blocks` names onto the gate (`buildGateIssue` and `gateCreateCmd` in
`cmd/bd/gate.go`). The bead that waits leaves `bd ready` until the gate closes.
This is how bd waits on a state other than a close, for the types it
documents: a bead stands for the state, and its close releases what waits on
it. bd's help for `bd gate`
says gates "must be closed (manually or via watchers) for the blocked step to
proceed".

The gate's type is the pack's own, `gctk:needs-review`. It names the condition
that resolves the gate, as bd's own types do: bd's help gives a `gh:pr` gate as
one that "Waits for PR merge" and a `bead` gate as one that "Waits for another
bead to close", with that bead's id as its await id (`bd gate --help`). The
stay's gate has the `bead` gate's shape with an earlier condition. bd's own check
evaluates `gh:run`, `gh:pr`, `timer` and `bead` gates and passes over every
other await type (`evaluateGates` in `cmd/bd/gate.go`; `isMachineCheckableGate`
in `cmd/bd/close.go` lists the same types). Gas City's core sweep runs
`gate check --type=timer` and `--type=gh` in each store
(`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). So the pack's
closer is the gate's only one. The gate names the work by its await id, which
bd's help gives as the "Condition identifier (run ID, PR number, etc.)" a gate
waits on, and the conversation is the bead its `--blocks` names. An await id is
no edge, so bd's cycle check never meets it (`types.IsSchedulingEdge`).

**What bd and Gas City say about gates.** Neither gives guidance for a gate type
of one's own. bd's help documents the types `human`, `timer`, `gh:run`, `gh:pr`
and `bead`, stores any `--type` unchecked (`buildGateIssue`), and says gates
"must be closed (manually or via watchers)" without defining a watcher. The
stay's gate uses that opening, with the landing order as its watcher. Gas City,
at upstream main 17d7d77ce2, maps `gt gate` to `gc wait` and to formula gates,
and calls durable waits "the closest platform concept"
(`docs/reference/gastown-command-map.md`). A formula's `[steps.gate]` stamps its
declared type verbatim as `gc.gate_type` metadata, "the parser never validates
them", and "No bundled watcher resolves any gate type"
(`docs/reference/specs/formula-spec-v2.md`). Its stores "have no gate-condition
column" (`GateTypeMetadataKey` in `internal/beadmeta/keys.go`). The gate kind it
defines for itself, the cross-store gate, is marked by the label
`gc:cross-store-gate` and `gc.cross_store_gate_*` metadata, and its controller
releases it (`internal/dispatch/cross_store_gate.go`). So the gate stands
in for Gas City's session wait, the primitive Gas City offers for this wait,
which cannot hold the promise today (below), and the gate's warrant names that
wait (the design's section 13).

**What else was searched.**

- **bd's own gate types.** A human gate waits for a person. A timer gate waits
  for the clock, and a `gh:run` gate for a workflow run. A `gh:pr` gate closes
  only when its PR merges (`checkGHPR`), after the decision the return is for. A
  `bead` gate closes when another bead closes, and Gas City's sweep skips it
  (the header of `gate-sweep.sh`). None resolves when a PR is left with only
  the operator's approval.
- **A gate on GitHub's ready flag, keyed on the PR's number**, which the
  operator weighed on 2026-11-21 as `gh:ready_for_review`. New work has no PR,
  and so no number, when its gate is filed. The landing order is what marks a
  PR ready, so it can put the hold on first, where a gate that watches the flag
  sees it afterwards. A send-back that the review run answers with no push
  leaves the PR ready all along (`cmd_push` in `assets/scripts/review-run.sh`),
  so the flag never turns. And `gh:` is bd's own prefix:
  `bd gate check --type=gh` selects every type that starts `gh:`
  (`shouldCheckGate` in `cmd/bd/gate.go`), and `evaluateGates` checks one that
  starts `gh:pr` as a PR's merge.
- **bd's waiters.** `bd gate add-waiter <gate-id> <waiter>` stores an address that
  its help says is woken "via 'bd gate wake'" when the gate closes. bd v1.3.4
  has no `gate wake` command, and `cmd/bd/gate.go` only adds a waiter and shows
  it. So the wake comes from the bead the gate blocks, which Gas City reads as
  ready work (the sleep and the wake, below).
- **Gas City's session wait**, an earlier revision's promise
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
  one edge (one gate and no convoy, below).
- **A plain gate, or a task, that the pack closes.** A reader could not tell it
  from a person's: the park rule reads a gate with no await type as a park
  (`gateHold` in `services/helm/internal/rigboard/table.go`), as the gate a
  park files is, and a task reads as work. The await type is the
  field bd gives a gate for what it waits on.
- **A metadata key naming the gate's kind.** Gas City marks the gate kinds it
  defines in metadata and labels: a formula gate's type as `gc.gate_type`,
  since its stores have no gate-condition column, and the cross-store gate by
  a label and `gc.cross_store_gate_*` keys (above). A bd gate carries its kind
  in a field of its own, the await type, which the store's lite read includes
  (`IssueBaseColumnsLite` in `internal/storage/sqlbuild/sqlbuild.go`), and
  every reader of the gate reads bd's rows: `bd gate list`, and a gate's
  row in `bd show` and in `bd dep list`. So for a bd gate the await type holds,
  and a key would be a second field for one fact. The one reader it misses is
  the board's fallback onto the supervisor's API, whose bead carries metadata
  and no await type (`services/helm/internal/source/supervisor.go`), so there
  a waiting conversation reads as parked. The design keeps that limit.
  A key would remove it, and so would the API carrying a bead's await type.

## Filing it: `gctk gate create`

**What it composes.** Whoever sends a piece of work runs the verb once the send
is made: the sitting for a piece of work it sends itself, before it signs off,
and the stay's sign-off for the work its own call sends, when the conversation
has no open gate (the design's section 1). The verb makes one native write,
while the conversation is still claimed:
`bd gate create --type gctk:needs-review --await-id <work-bead-id> --blocks <conversation-bead-id>`.
It takes bd's own flags and is that command with the refusals in front.
It finds the conversation's open gate among the gates that block the
conversation, which `bd gate list <conversation-bead-id> --limit 0` lists with each
one's await type and await id, and files one only when none is open. On a
proxied server bd writes the gate and the conversation's edge onto it in one
transaction (`runGateCreateProxiedServer` in `cmd/bd/gate_proxied_server.go`).
The city's stores run on a Dolt server, where `gateCreateCmd` creates the gate,
then adds the edge, then commits, so a create that stops between the two leaves
a gate that nothing waits on. The verb's next run finds no gate the
conversation waits on for that bead and files one, and the stray resolves at
its condition (resolving it, below). The verb refuses a bead in another store, and a
bead in the city's own store, which the rig-scoped landing order does not read, and
a bead that has closed. It refuses a second piece while the conversation waits on
an open gate of this type, and a bead that waits on the conversation through another
bead, which could not move until something the conversation holds had landed.

**What else was searched.**

- **A `tracks` edge from the gate onto the work**, as a convoy tracks its
  members, with the conversation as the gate's await id. It is a write of its
  own after the create, so a stop between them leaves a gate that already holds
  the conversation and watches nothing, which no close reaches while the
  conversation is open. The await id is the field bd gives a gate for what it
  waits on, and the conversation is the bead the gate blocks.
- **The sitting typing the writes itself.** That is a read, a write and
  refusals the sitting would derive each time, the steps gctk's verbs take out
  of an agent's hands.
- **A verb named for the return**, which the text the operator read on
  2026-11-20 had: `gctk gate return <conversation> --on <bead>`. bd has no slot
  for what follows a gate's close, so the name described no part of the gate,
  and it hid bd's own terms for the two beads.
- **The stay's `--waiting-on` as the piece to bring back**, which would need no
  second command. That flag already has a job in every sign-off: it makes the
  subject wait on the bead and arms the subject's closer
  (`assets/scripts/converse-signoff.sh`; the headline's writer in
  `assets/scripts/gc-helm.sh` adds the edge). A subject can wait on work the
  operator has settled, and a gate filed for such a bead would resolve on the
  landing order's next pass and hold a PR the operator had released.
- **The sign-off telling the piece from the store**, as the previous revision
  did for a PR the conversation holds. The record cannot tell work just sent
  from work the operator settled: new work can open its PR before the sign-off
  runs, and a settled PR returns to draft when the city starts a round on it
  by itself. So the
  piece is named by an act of its own.
- **A flag on the sign-off that names the piece.** It would fold the promise
  into the stay's call. It grows an existing script by a key for what the verb
  already does, and it ties the promise to a sign-off, where the verb can run
  at any moment while the sitting holds the conversation. The gate comes after
  the send either way, because a rework's PR is already ready at its head when
  the operator rules, so the landing order's next pass would resolve a gate
  filed before the ask was open.
- **Gas City's session wait**, above.

## Resolving it: the pack's status of a PR, read by the landing order

**What it composes.** The status the pack already computes for a PR. The pr
domain's evaluator lists each condition a PR on the pending record has not met
(`services/gctk/pr/pr.go`), and the status owner turns that answer, with the
facts about what the PR's bead waits for, into the word the PR's label shows
(`Render` in `services/gctk/prstatus/render.go`). `docs/pull-request-states.md`
gives `needs-review` as "The city has finished with the PR, and it waits for a
person to review it." The gate's condition is one more view over the same
answer and facts, the PR's own status, with what holds the PR set aside (the
design's section 3). What holds a PR is told by the person rules, which the
status owner applies to each of the bead's waits already when it reads those
facts (`IsHumanGate` and `IsPersonBlocker` in `services/gctk/prstatus/gates.go`
on main, and `services/gctk/standing/person` with pull request 1612), so the
view adds no data.

The landing order's pass (`gctk pr reconcile`, the rig-scoped exec order
`orders/pr-reconcile.toml`, on a one-minute cooldown on main since PR #1559)
decides each open PR at its head (`decideAtHead` in
`services/gctk/pr/landing.go`). There, for an open gate that names the PR's
bead, it writes the hold and resolves the gate, a native close, once the own
status is `needs-review` or `merging`, and it requests no merge while such a
gate is open. In the same pass it resolves a gate whose bead has closed. A gate
that no open or in-progress conversation waits on resolves at the same
conditions with no hold. The order lists the store's open gates in each pass,
and again before a merge request, with
`bd gate list --limit 0`, because bd lists 50 gates unless `--limit` says
otherwise (`gateListCmd` in `cmd/bd/gate.go`): a gate's bead is its await id,
and its conversation is its dependent through a `blocks` edge
(`bd dep list <gate> --direction=up --type blocks`). It removes no edge. The
review-lanes design placed the wake in the landing order's pass, in its
section 9 (`specs/tk-1tfzr71.108/design.md`).

**What else was searched.**

- **Gas City's core gate sweep and `bd gate check`.** They close only the types
  bd evaluates, and none of those resolves on a PR's status (above).
- **An order of its own.** Order triggers are cooldown, cron, condition, event
  and manual (`Trigger` in `internal/orders/order.go`). A PR's status is
  decided inside the landing order's pass, so a second order would only decide
  it again.
- **The ready transition, or its own conditions**, which the text the operator
  read on 2026-11-20 listed (`readyBar` in `services/gctk/pr/draft.go`). A
  send-back answered with no push has no transition (`cmd_push` in
  `assets/scripts/review-run.sh`). The conditions were a second list of what
  the status owner computes, and they left out the required checks, which run
  only once the PR is ready, because this repository's CI skips a draft
  (`.github/workflows/tests.yml`).
- **The label's own word**, read off the label or `gctk pr status`. It counts
  what holds the PR. A PR its own staying conversation holds reads `working`
  (`Facts.Staying`), so the gate would never resolve, and an unrelated question
  on the PR would keep the sitting asleep. An approved PR the city is still
  changing reads `merging`, so that word would resolve the gate too early.
- **A bead's standing** (pull request 1612, `services/gctk/standing`), which
  answers whose move a bead is. It reads a PR's bead through the same status
  owner, holds included, so it meets the label's two problems. The gate's view
  sits in that owner, beside the label's.
- **A new word for the state**, `ready-for-approval`. The pack already names
  it `needs-review`.
- **A wider type**, `gctk:needs-attention`, which the operator raised on
  2026-11-21 and which would also resolve when the PR needs a person. It is
  another type over the same view, and tk-lfcb8ug holds it.
- **Gas City's event on a bead's close**, for a gate whose watched bead closed.
  The core order `cascade-nudge-on-blocker-close` runs on `bead.closed` and
  nudges the assignees of the closed bead's dependents
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`).
  The gate names its work by its await id, so it is no dependent of the work,
  and a nudge closes nothing. The landing order's pass reads each gate's bead
  instead.
- **A close of its own for a gate nothing waits on**, which the previous
  revision made once such a gate was five minutes old. The age did not prove
  that a create had finished, so a create that stalled could lose its gate.
  Such a gate now resolves at its condition and holds nothing.

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

## One gate and no convoy

**What it composes.** bd reads a bead as ready only once every bead it waits on
through a `blocks` edge has closed. A conversation waits on one gate at a
time, so that rule is all the wait needs: the gate closes, and the conversation
is ready.

**What else was searched.**

- **An edge onto the work itself.** The hold is the PR's bead's `blocks` edge
  onto the conversation, which bd refuses while the conversation blocks on that
  bead, because its cycle check walks `blocks`, `conditional-blocks` and
  `parent-child` edges (`types.IsSchedulingEdge`, beads
  `internal/types/types.go`).
- **An edge onto the conversation's own subject.** The conversation tracks its
  subject, and bd keeps one edge from a bead onto another
  (`DependencyTypeConflictError`).
- **The ruling's ask.** On the review path the run's `record` step closes the ask
  before the refinery validates the head the operator approves (the review-lanes
  design, sections 1, 5 and 8, in `specs/tk-1tfzr71.108/design.md`), so the
  sitting would come back, and the conversation would stop reading as a stay,
  before the city has finished with the PR.
- **A gate for each of several pieces of work.** bd's rule then brings the
  sitting back only once every gate has closed, so a PR that is finished first
  is held while its sitting sleeps on another piece. When that other piece
  cannot move until the held PR lands, as when the subject's PR waits on new
  work, nothing wakes the sitting. Closing a conversation's gates together at
  the first of them wakes it, but leaves a piece that has no PR yet with no gate
  and no hold until the sitting stays again.
- **bd's `waits-for` edge with the `any-children` gate**, a wait that clears at
  the first of several to close. It waits on the `parent-child` children of a
  spawner bead (`waitsForGateBlockedSQL` in
  `internal/storage/issueops/blocked_state.go`), so each stay would need a
  spawner of its own, and the pack's readers of a stay read the conversation's
  own `blocks` edges: the PR's status asks `conversation.Staying` with them
  (`staying` in `services/gctk/prstatus/gates.go`), and `gctk bead holds`
  reads a bead with a `waits-for` edge of its own as unjudged, not blocked.
- **A convoy that tracks a bead**, which Gas City closes once the bead closes
  when it carries no `owned` label (`convoyStillAutocloses` in
  `cmd/gc/cmd_convoy.go`; `gc convoy create` in `docs/reference/cli.md`). The
  previous revision waited through one for work the operator had settled, and
  for the subject's close. Its edge stayed on the conversation when new work
  was sent, and the conversation then waited on the convoy and the gate
  together. The design waits for neither now. A conversation that stays
  available until its subject closes is a change of its own (tk-lfcb8ug), and a
  convoy on the subject is the primitive it would start from.

## The hold: the conversation's existing hold on a PR's merge

**What it composes.** A conversation on an open PR holds its merge through the
anchor's `blocks` edge onto it (`conversation_hold_merge` in
`assets/scripts/gc-helm.sh`; `docs/human-engagement.md`, "A conversation on an
open PR holds its merge"). The evaluator reads that edge as a wait of the bead's
own (`ownWaits` and `KindWait` in `services/gctk/pr/pr.go`), and `prstatus`
reads it as the city's work while the conversation stays and as the operator's
move once it does not (`Render`; `Staying` and `Owed` in
`services/gctk/prstatus/gates.go`). The landing order writes the same edge
before it resolves the gate, and the sitting lifts it on the operator's
settlement with `gc bd dep remove`, as `converse-hold` lifts it today. No
condition, key or state comes with it.

**What else was searched.**

- **The sitting writing the hold at its return.** The minutes between the gate's
  resolve and the sitting's first write would hold nothing, and a sitting that
  did not wake would hold nothing at all.
- **An order of writes alone**, the hold before the resolve, with no rule
  about the merge. A PR can be approved and ready while its gate is still open,
  and `merge` reads only the bead's status and assignee before its request,
  where a gate is no edge of the bead's. So the order requests no merge while
  an open gate names the bead, and lists the gates again before a merge
  request.
- **A condition of the evaluator's**, which the first draft added for a stay
  that owed a reading. It read the stays, their rounds and the PR's comments on
  every pass. The edge is a wait the evaluator already reads.
- **Keeping the PR a draft.** The operator ruled it out, so that CI and GitHub's
  review request go on. GitHub requests no review on a draft and this
  repository's CI skips its suite on one (`.github/workflows/tests.yml`), so
  the checks the gate's condition waits for would never run. A draft also does
  not hold a PR that is ready already, as after a send-back answered with no
  push, so it cannot be the hold.
- **`merge_hold`.** It is the operator's freeze, theirs to lift
  (`lifecycle/lifecycle.toml`, beside `settled_keys`), not a hold the city puts
  on and a ruling lifts.
- **GitHub's review request or a required check.** Either would make the return
  one of the PR's checks, which the initiative's boundaries rule out.
- **GitHub's `dequeuePullRequest`.** The landing order leaves a PR in its base's
  merge queue to GitHub (`decideAtHead` returns for one before it reads anything
  else), and no rig in the city has a merge queue on its default branch
  (`repository.mergeQueue`, read for each rig on 2026-11-16).

## The readers: one rule in gctk

**What it composes.** The await type bd stores on the gate, and one rule in
gctk's `gate` package that says the city closes a gate of this type. Two rules
ask it: the park rule (`gateHold`, in the rig board on main and in the standing
owner with pull request 1612), and with that pull request the rule for how far
the city carries a bead (`services/gctk/standing/advance.go`), which reads a
wait on a gate that is no human gate as stuck (the design's section 2).

**What else was searched.**

- **bd's own answer.** bd stores no field that says who closes a gate. Its
  `isMachineCheckableGate` names only the types bd checks itself, so it would
  read the gate as a person's.
- **Gas City's API.** The supervisor API's bead carries no await type
  (`services/helm/internal/source/supervisor.go`), so the board's fallback onto
  that API cannot tell the gate from a park. The board reads the store directly
  unless that read fails its startup probe.
- **The park rule keeping a list of its own.** It reads every gate that is no
  human gate as a park today, a timer among them, so each type the city closes
  would be added there by hand.

## Ending a stay

**What it composes.** The sign-off without `--stay` closes the conversation and
releases its holds with the close. A gate still open then has no open
conversation, so it resolves at its condition with no hold, and the sitting
runs no command of its own for it. A stay never drains, because the
core reaper closes drained sessions older than a day
(`gc session prune --state drained` in
`internal/bootstrap/packs/core/assets/scripts/reaper.sh`), and a closed session
leaves the return to a sitting with no thread.

## What it leaves in place

- **The minutes between the gate's resolve and the sitting's post**, while the
  PR reads `needs-attention`, held by the conversation, and the sitting has not
  yet posted what it found.
- **New work's PR is ready and not yet held while its checks run**, and its
  label can read `needs-review` for a pass after they pass. An approval given
  then merges nothing, because the gate is still open.
- **A merge made by hand** is outside the rule, which binds the landing order's
  own request.
- **A watched bead's close reaches the gate on the landing order's next pass**,
  up to its cooldown later than an edge onto the bead would wake the sitting.
- **A gate create that stops before its edge**, on the city's Dolt server,
  leaves an open gate that nothing waits on until it resolves at its
  condition.
- **A sitting cut off between a send and its promise.** If nobody picks it up
  for a whole build and review, that PR turns ready with no hold, and needs
  only the operator's approval, as a stay's work does today.
- **Other work the sitting sent**, and work sent from a visit while it waits,
  brings no return of its own, because a conversation waits on one gate. It is
  held only on a PR the conversation already holds.
- **Trouble on the work** does not wake the sitting: a question for a person
  filed on it, a required check that failed, or a PR closed unmerged. It
  reaches the operator as it does today, and the gate stays open until the
  PR's own status turns. tk-lfcb8ug holds the wider type that would wake it.
- **A dependency written after the promise** onto something the conversation
  holds. The verb's refusal reads only the edges that exist when it runs.
- **The board's supervisor fallback** reads a staying conversation as parked.
- **A sitting whose session has closed** is not woken. The hold still goes on
  once the PR's own status turns, and the return starts once the operator
  engages the conversation.
- **The city's own store.** The landing order is rig-scoped
  (`orders/pr-reconcile.toml`), so no pass there would resolve a gate, and the
  sitting promises nothing there. A stay there comes back when its work closes,
  as today. Main has had no other merge path since PR #1615.
- **A merge already requested.** On a base that requires a merge queue, GitHub
  merges a queued PR once the queue's checks pass, whatever the sitting holds,
  and no rig in the city has one on its default branch.
