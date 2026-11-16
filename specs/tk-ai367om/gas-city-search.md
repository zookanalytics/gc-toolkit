---
name: Gas City search for a stay that comes back before the operator's next decision
description: Use when you review or build a unit of the design in specs/tk-ai367om/design.md, which has a staying sitting promise its return with a Gas City session wait and come back to discuss the result before the operator's next decision, and need the Gas City, bd and GitHub primitives each piece of its surface composes, what was searched for each and found not to cover it, and why the promise is a session wait the sitting registers, the sleep is a bd edge onto a convoy, the wake is the landing order's `gc wait ready`, the hold is the conversation's existing hold on a PR's merge, and a visit and a fresh context need changes in Gas City, which the words unit waits on through a gate in this store.
---

# Gas City search: a stay that comes back before the operator's next decision

The design has a staying sitting promise its return with a Gas City session
wait, come back when the work is ready for the operator's next decision, and
wait for the operator to discuss it, while the PR's merge waits for that
discussion. Its surface is listed in the design's section 12. This record names,
for each piece, the primitive it composes and what else was searched.

Gas City citations are at upstream `gastownhall/gascity` main 76a06b2327, bd
citations at beads v1.3.4, and the pack's at main 713e3a733. The searches made
for the stay before this one are `specs/tk-pb9wnr3/gas-city-search.md` (the
stay of PR #1480) and `specs/tk-blwi68h/gas-city-search.md` at PR #1515's head
6ffdc541f (a stay on the conversation's own subject). Their findings that this
record relies on were read again at the commits above.

## The promise: a session wait the sitting registers

**What it composes.** `gc session wait <session> --on-beads <ids> --note <text>`
records a durable wait, a bead of type `gate` labelled `gc:wait` whose metadata
names the session and the beads it watches (`cmdSessionWait` and
`doSessionWait` in `cmd/gc/cmd_wait.go`; `CreateWait` in
`internal/session/wait_store.go`; `docs/reference/cli.md`, `gc session wait`). A
ready wait wakes its session (the `wait-ready` reason in
`cmd/gc/compute_awake_set.go`), reaches it as a queued nudge,
`Wait satisfied (<wait>): <note>` (`dispatchReadyWaitNudgesWithSnapshot`), and
closes once the nudge is delivered (`CloseWaitFromNudge`). Gas City marks a
`deps` wait ready when its beads close, and anyone can mark one ready with
`gc wait ready <wait>`. That is the promise the operator described: register a
wait on the work, and get a nudge when it is ready.

The sitting runs the command itself, once its stay has landed, so the promise is
a native write and no surface of the pack's. A stay can then be kept without a
promise, as the design's section 6 keeps a conversation available after the
operator settles.

**What else was searched.**

- **The sign-off registering the promise.** It would tie every stay to a
  promise, so a conversation kept available after a settlement would be woken at
  the PR's next round and hold its merge again.
- **A bead that closes at readiness.** Nothing in Gas City or bd closes when a PR
  becomes ready for review. bd's `gh:pr` gate waits for the PR's merge
  (`cmd/bd/gate.go`), and core's `gate-sweep` checks only `timer` and `gh` gates
  (`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). A bead the pack
  filed for the order to close would be a bead kind of the pack's own, standing
  in for the wait Gas City already ships.
- **A nudge from the order.** `gc session nudge` sends text to a running session,
  and its `queue` delivery "never wakes the session" (`docs/reference/cli.md`,
  `gc session nudge`). `gc session wake` wakes it but cancels every wait the
  session has (`Store.WakeSession`).
- **An order of its own.** Order triggers are cooldown, cron, condition, event,
  manual and webhook (`internal/orders/order.go`). The end of a round is decided
  inside the landing order's pass, so a second order would only decide it
  again.
- **The blocker-closed notice.** Core's `cascade-nudge-on-blocker-close` runs on
  `bead.closed` only
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`),
  and nothing closes at readiness.

## The sleep: the stay's edge onto a convoy

**What it composes.** A manual session is wanted awake while ready or claimed
work is assigned to it, and sleeps after its idle window only while it is not
attached and what is assigned to it waits on something open
(`compute_awake_set.go`: "Blocked open assignments do not prevent idle sleep").
The conversation is assigned to its sitting, so the stay's own `blocks` edge is
what lets the sitting sleep, as PR #1480 built it. The edge also keeps the
conversation reading as a stay to the landing order (`heldBy` in
`services/gctk/pr/admit.go`) and to the boards (`conversation.Staying`), so the
PR's review runs go on while the work is out.

The edge goes onto a convoy that tracks the work alone and carries no `owned`
label, which Gas City closes once the work closes (`convoyStillAutocloses` in
`cmd/gc/cmd_convoy.go`). A graph.v2 pour on a bead that is not a convoy mints a
fresh one-item convoy that tracks it (`NormalizeInputConvoy` and
`CreateSingleItemInputConvoy` in `internal/graphv2/invocation.go`), as a
formula's sling of the work and each review run do. The sign-off waits on the
newest open one, the rule `subject_convoy` applies at PR #1515's head, and when
none is open it makes one with `gc convoy create <name> <bead>`
(`docs/reference/cli.md`, `gc convoy create`, without `--owned`).

**What else was searched.**

- **An edge onto the work itself.** The hold is the PR's bead's `blocks` edge
  onto the conversation, which bd refuses while the conversation blocks on that
  bead, because its cycle check walks `blocks`, `conditional-blocks` and
  `parent-child` edges (`types.IsSchedulingEdge`, beads `internal/types/types.go`).
  The convoy reaches the bead by `tracks`, which the check does not walk.
- **An edge onto the conversation's own subject.** The conversation tracks its
  subject, and bd keeps one edge from a bead onto another
  (`DependencyTypeConflictError`, beads `issueops/errors.go`).
- **The ruling's ask.** On the review path the run's `record` step closes the ask
  before the refinery validates the head the operator approves (the review-lanes
  design, sections 1, 5 and 8, in `specs/tk-1tfzr71.108/design.md`), so the
  sitting would come back, and the conversation would stop reading as a stay,
  before the round ends.
- **A move onto the first review run's convoy**, which the earlier draft made
  when the ask closed. A convoy the sign-off makes when none is open covers the
  same case from the start, with no second step.
- **The session wait as the sleep.** It would leave the conversation unblocked,
  so ready work assigned to the sitting would keep it awake, and a wait with
  `--sleep` holds out the attached wake as well (`compute_awake_set.go`), which
  the sitting needs while the operator talks with it.

## The wake: `gc wait ready` from the landing order

**What it composes.** In the landing order's pass (`decide` in
`services/gctk/pr/landing.go`), the end of a round is `readyBar`'s conditions
other than the draft flag (`services/gctk/pr/draft.go`). At that moment the order
reads the pending waits on the PR's bead (`gc wait list --json`, which names each
wait's session, state and beads), keeps those whose session is a conversation's
sitting (`gc session list --json`, whose alias for a sitting is its
conversation's assignee, `conversation.IsAssignee`), puts the hold on, and marks
each ready (`gc wait ready`). The review-lanes design placed the wake in this
pass, in its section 9.

**What else was searched.**

- **Every wait on the bead**, as the review-lanes design's section 9 words it.
  A wait another session registered on the PR's bead watches for its close, so
  marking it ready at the round's end would tell that session the bead closed.
  The order marks only the waits of conversations' sittings.
- **The ready transition alone.** A round that ends with no push leaves the PR
  ready, with no transition to mark it at (`cmd_push` in
  `assets/scripts/review-run.sh`), so the order reads the end of the round
  instead.

## The hold: the conversation's existing hold on a PR's merge

**What it composes.** A conversation on an open PR holds its merge through the
anchor's `blocks` edge onto it (`conversation_hold_merge` in
`assets/scripts/gc-helm.sh`; `docs/human-engagement.md`, "A conversation on an
open PR holds its merge"). The evaluator reads that edge as a wait of the bead's
own (`ownWaits` and `KindWait` in `services/gctk/pr/pr.go`), and `prstatus`
reads it as the city's work while the conversation stays and as the operator's
move once the sitting holds the conversation (`Render`; `Staying` and `Owed` in
`services/gctk/prstatus/gates.go`). The landing order writes the same edge at the
end of a round, before it marks the promise ready, and the sitting lifts it on
the operator's settlement with `gc bd dep remove`, as `converse-hold` lifts it
today. No condition, key or state comes with it.

**What else was searched.**

- **The sitting writing the hold at its return.** The minutes between the end of
  the round and the sitting's first write would hold nothing, and a sitting that
  did not wake would hold nothing at all.
- **A condition of the evaluator's**, which the earlier draft added for a stay
  that owed a reading. It read the stays, their rounds and the PR's comments on
  every pass. The edge is a wait the evaluator already reads.
- **Keeping the PR a draft**, which the previous revision kept as an option in
  a narrower form and the operator ruled out, so that CI and GitHub's review
  request go on while the sitting reads. GitHub requests no review on a draft
  and this repository's CI skips its suite on one
  (`.github/workflows/tests.yml`), but a draft does not hold a PR that is ready
  already, as after a round with no push, so it cannot be the hold.
- **`merge_hold`.** It is a hold a person sets by hand, which `prstatus` reads as
  `needs-attention` from the start, while the sitting is still on its way.
- **GitHub's review request or a required check.** Either would make the return
  one of the PR's checks, which the initiative's boundaries rule out.
- **GitHub's `dequeuePullRequest`.** The landing order leaves a PR in its base's
  merge queue to GitHub (`decide` returns before `readyBar` and the evaluator for
  one), and no rig in the city has a merge queue on its default branch
  (`repository.mergeQueue`, read for each rig on 2026-11-16).

## The return's trigger: the notice, confirmed in the record

**What it composes.** The promise's `Wait satisfied` notice is what tells the
sitting why it woke. A session's start carries no wake cause (`PromptContext` in
`cmd/gc/prompt.go` has no wake field), and the claim answers a staying sitting
`drain` with the reason `no_work` while its conversation waits on open work. The
sitting confirms the notice in the record: the notice names its wait, and
`gc wait inspect <wait> --json` reads that wait in any state, `ready` before
delivery, `closed` with the nudge's id after it (`CloseWaitFromNudge`), and
`canceled` when something cancelled it (`CancelWait`; `GetWait` in
`internal/session/wait_store.go`). A delivered or cancelled wait is a closed
bead, so `gc wait list --session <session> --json` lists only the session's open
waits, pending or ready (`ListWaits` and `WaitsForSession`). After a restart
that list tells the sitting which promises still stand, and a promise missing
from it was delivered, cancelled or never registered.

**What else was searched.**

- **A `ready` answer from `converse-entry.sh`**, fed by a key of
  `gctk pr status` and a marked reading on the PR, as the earlier draft built it.
  The notice already says why the sitting woke, and the wait's record says
  whether it was delivered, so the entry needs no new answer and gctk no new
  key.
- **The pack's own record of each promise's wait**, so that a thread a reset
  started fresh could read a delivered or cancelled promise by its id. It
  would be a second registry of the session's waits beside Gas City's, which the
  brief the operator approved in conversation tk-8e83do9 says not to make the
  preferred architecture. Such a thread instead registers each promise the
  stay's hand-back names that is neither open, nor held as a notice, nor a
  return it carries on, so a return whose notice reached the thread before it
  still comes back once (the design's section 4).

## Visits and fresh contexts: the changes Gas City makes

**What it composes.** `gc session attach` attaches to a running session and
changes nothing else, so a visit while the sitting runs keeps the promise. On a
session that is not running it asks the controller to start it "as gc session
wake does" (`sessionAttach.attachOnceControllerStarts`, then `doSessionWake`, in
`cmd/gc/cmd_session.go` and `cmd/gc/cmd_session_wake.go`), and
`Store.WakeSession` cancels every wait the session has as it clears what keeps
the session from starting (`wakeSessionFromBead` in
`internal/session/wait_store.go`). A visit to a sleeping sitting therefore
cancels its promise today.

`gc session reset` asks for a fresh restart (`SessionHandle.Reset` in
`internal/worker/handle_lifecycle.go`, then `Manager.RequestFreshRestart` in
`internal/session/manager.go`). Once the start that consumes it has moved the
session to its next `continuation_epoch`, each wait registered before it reads
stale and is cancelled as `continuation-stale` (`WaitInfo.ContinuationStale` in
`internal/session/waits.go`; `prepareWaitWakeStateHooked` in
`cmd/gc/cmd_wait.go`). A return handed to a fresh context therefore cancels the
sitting's other promises today. Gas City already carries one kind of wait across
that restart: a wait registered while the reset is pending is marked
`registered_reset_pending` (`CreateWait`) and is delivered in the conversation
the restart opens (`DeliveryEpoch` and `HeldForPendingReset`).

The operator ruled that keeping a promise through both is a prerequisite for
turning the return on, built in the city's fork of Gas City ("Second operator
rework ruling" on tk-ai367om, conversation tk-8e83do9, 2026-11-16). Both changes
are Gas City's, each filed in the Gas City rig and held for the operator's
placement. gc-gspdoo covers the attach, and gc-lwa1vp a fresh restart, which
extends the fence a wait registered during a pending reset already has to the
session's open waits.

**What else was searched.**

- **The API's message resume** (`resume: true`), which keeps waits but consumes
  only an operator's suspend (`Store.ResumeHeld` in `internal/session/resume.go`;
  `internal/api/AGENTS.md`), so it cannot start a session that slept idle or
  under a wait hold.
- **The pack registering a cancelled promise again, as the way a visit or a
  reset keeps it.** The ruling makes keeping a session's pending waits and
  their queued notices Gas City's work and a prerequisite for the return, and
  the brief the operator approved in conversation tk-8e83do9 says not to make
  pack-side restoration the preferred architecture. The sitting's entry
  registers a promise again only where Gas City's list cannot hold it once Gas
  City keeps waits through both: a promise never registered, a notice that
  reached a thread which ended before it took that return up, and a sitting
  that takes the conversation up after its session closed (the design's
  section 4).
- **The sitting registering its other promises again while its reset is
  pending**, which the existing fence would carry into the fresh conversation.
  The controller stops the session once it acts on the reset's request, so the
  writes would race the sitting's own restart. That would also be pack-side
  restoration, which the brief rules out as the preferred architecture.
- **A restriction on resets while a promise is pending**, which the ruling allows
  until the reset change exists. It would bind only the resets a sitting makes
  itself, not an operator's, and the gate already keeps the return off until
  Gas City keeps the promise, so no promise exists for a reset to withdraw.
- **A wrapper around engage's attach** that keeps the operator's terminal tab
  while the runtime sleeps. That is terminal work, which epic tk-uipsrmt holds.
- **`--sleep` for a sitting that leaves.** No command sleeps a session on a wait
  it already has (`docs/reference/cli.md`, `gc session wait` and `gc wait`), and
  the idle window already sleeps a sitting whose conversation waits on open work.

## The gate the words unit waits on

**What it composes.** The words unit, which turns the return on, waits on
gc-gspdoo and gc-lwa1vp, and both are in the Gas City rig's store. A `blocks`
edge across two stores prints success and holds nothing, so a bead whose blocker
is in another store waits on a human gate in its own store that names the
blocker, which a person clears once the blocker lands (`skills/waits/SKILL.md`,
"Make a bead wait on other work"; `human-gate.sh`). The implementation child
files that gate on the words unit and arms the unit, so clearing it starts the
unit.

**What else was searched.**

- **A `blocks` edge onto each Gas City bead.** It holds nothing across stores.
- **bd's `gh:pr` gate on the fork's pull request.** It waits for the PR's merge
  (`cmd/bd/gate.go`). The ruling's condition is that the fork's behavior is
  built, verified and running in the city. The city's gc is built and installed
  apart from the fork's merges, so its revision moves on its own, and a person
  reads the condition.
- **A gate on the landing bead.** It would hold the effort's merge too, but the
  words unit would then be built before the changes it describes run, and no
  unit would remove the Debt entry those changes retire.

## Ending a stay: `gc wait cancel`

**What it composes.** Before the sign-off that ends the conversation, the
sitting cancels its pending promises with `gc wait cancel <wait>`, a native write
of its own, so no promise outlives its conversation. The landing order leaves a
promise alone once its conversation has closed, and a closed session's waits are
cancelled by Gas City as well
(`prepareWaitWakeStateHooked` in `cmd/gc/cmd_wait.go`), and the core reaper
closes drained sessions older than a day
(`internal/bootstrap/packs/core/assets/scripts/reaper.sh`), which is why a stay
never drains.

## What it leaves in place

- **The return waits for Gas City.** Until the city's gc carries gc-gspdoo and
  gc-lwa1vp, the words unit waits on its gate, and a stay comes back only when
  its work closes, as it does today.
- **A sitting whose session has closed** is not woken at the end of the round,
  and the landing order writes no hold for it until a sitting takes the
  conversation up again and promises again. Meanwhile a PR whose merge the
  conversation does not hold through engage's edge merges on the operator's
  approval, and the stay comes back when the work closes.
- **The minute between the end of a round and the sitting's wake**, while the PR
  reads `working`.
- **A promise registered again waits for the next pass.** A fresh thread that
  registers a promise whose round has already ended is woken on the landing
  order's next pass, not at once.
- **No command sleeps a session on a wait it already has**, so a sitting the
  operator leaves runs for up to its idle window.
- **A rig on the old review path** has no end of a round to wake at. Its rework
  stay comes back when the rework reaches the branch, and its other stays after
  the merge. The code nearest a readiness there, `gate-ensure.sh`, is on the
  deletion plan with tk-1tfzr71.122, so it gets no new work.
- **A merge already requested.** On a base that requires a merge queue, GitHub
  merges a queued PR once the queue's checks pass, whatever the sitting holds,
  and no rig in the city has one on its default branch.
