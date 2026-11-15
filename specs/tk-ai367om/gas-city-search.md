---
name: Gas City search for a stay that comes back when its work is ready for approval
description: Use when you review or build a unit of the design in specs/tk-ai367om/design.md, which brings a staying sitting back when its PR is ready for the operator's approval, and need the Gas City, bd and GitHub primitives each piece of its surface composes, what was searched for each and found not to cover it, and why the stay's record stays a bd edge, the wake is a Gas City session wait, the hold is the PR's draft and a condition of the evaluator's, a stay's round is counted from the lines it already writes, and the reading's record is the PR comment itself.
---

# Gas City search: a stay that comes back at readiness

The design brings a staying sitting back when its PR is ready for the operator's
approval, holds the PR until the sitting's reading of its latest ruling is on it,
as a draft or by its merge, and has the sitting read again in each round. Its
surface is listed in the design's section 8. This record names, for each piece, the primitive it composes and what else was
searched. Gas City citations are at upstream `gastownhall/gascity` main
8e7d91b583, bd citations at beads v1.3.4, and the pack's at main 5d4c3b4cf and
`integration/tk-1tfzr71.22` 04d8dad0d. The searches made for the stay before
this one are `specs/tk-pb9wnr3/gas-city-search.md` (the stay of PR #1480) and
`specs/tk-blwi68h/gas-city-search.md` at PR #1515's head 6ffdc541f (a stay on the
conversation's own subject). Their findings that this record relies on were read
again at the commits above.

## The wake at readiness: a Gas City session wait

**What it composes.** `gc session wait <session> --on-beads <ids> --note <text>`
registers a durable wait, a bead labelled `gc:wait` that names the session and
the beads it watches (`cmdSessionWait` and `doSessionWait` in
`cmd/gc/cmd_wait.go`; `docs/reference/cli.md`, `gc session wait`). `gc wait ready
<wait>` marks a wait ready by hand (`newWaitReadyCmd`), and `gc wait list --json`
names each open wait's session, state and `dep_ids` (`waitJSON`). A ready wait
wakes its session (the `wait-ready` reason in `cmd/gc/compute_awake_set.go`) and
reaches it as a queued nudge, `Wait satisfied (<wait>): <note>`
(`dispatchReadyWaitNudgesWithSnapshot`). Gas City also marks a `deps` wait ready
when its beads close (`depsWaitReadyDetailedFrom`), which on the old review path
is the only way it turns ready. So the stay registers the wait, the landing order
marks it ready while a reading is owed, and Gas City wakes the sitting with the
note. The order tells the stay's wait from one another session registered on the
bead by its `session_id`: the session `gc session list --json` lists with the
conversation's assignee as its `alias` (`sessionListJSONRow` in
`cmd/gc/cmd_session.go`). The review-lanes design placed the wake here in its
section 9.

**What it does not cover, and what covers it.**

- **The sleep and the record.** An explicit wake, `gc session wake` or the
  API's, cancels every wait of its session (`Store.wakeSessionFromBead` in
  `internal/session/wait_store.go`), and `gc session attach` asks the controller
  to start a stopped session as `gc session wake` does (`cmd/gc/cmd_session.go`,
  the attach command's help). A wait
  registered before a fresh restart is cancelled as stale
  (`WaitInfo.ContinuationStale` in `internal/session/waits.go`), a closed
  session's waits are cancelled (`prepareWaitWakeStateHooked` in
  `cmd/gc/cmd_wait.go`), and a ready wait closes once its nudge is delivered
  (`finalizeReadyWaitFromNudge`, `CloseWaitFromNudge`). So the stay keeps its bd
  `blocks` edge as the sleep and the record, as PR #1480 does, and the entry has
  the sitting register the wait again whenever it finds the stay without one.
- **`--sleep`.** Its wait hold suppresses the session's demand-driven wake
  (`cmd/gc/compute_awake_set.go`, "wait_hold suppresses normal demand-driven
  wake"), which would keep a sitting asleep past a wait in the store that closes
  early. The design needs no such override: every PR stay's wait in the store
  stays open until the PR's bead closes, because the rework stay waits on the
  anchor's input convoy rather than the ask. The stay registers its session wait
  with no `--sleep`, so the bd edge alone decides the sleep, as it does today.

**What else was searched.**

- **A bead that closes at readiness.** Nothing in Gas City or bd closes when a PR
  becomes ready for review. bd's `gh:pr` gate waits for the PR's merge
  (`cmd/bd/gate.go`, "gh:pr - Waits for PR merge", resolved on `state=MERGED`),
  and core's `gate-sweep` checks only `timer` and `gh` gates
  (`internal/bootstrap/packs/core/assets/scripts/gate-sweep.sh`). A bead the pack
  filed for the order to close at readiness would be a bead kind of the pack's
  own, standing in for the wait Gas City already ships.
- **A nudge from the order.** `gc session nudge` sends text to a running session,
  and its `queue` delivery "never wakes the session" (`docs/reference/cli.md`,
  `gc session nudge`). A sleeping sitting needs a wake, and `gc session wake`,
  the explicit wake, cancels every wait of the session, the waits on its other
  PRs among them (`Store.wakeSessionFromBead`).
- **An order of its own.** Order triggers are cooldown, cron, condition, event,
  manual and webhook (`internal/orders/order.go`). The readiness is decided
  inside the landing order's pass, where the PR would be marked ready, so a
  second order would only decide it again. The wake is a call in that pass.
- **The blocker-closed notice.** Core's `cascade-nudge-on-blocker-close` order
  runs on `bead.closed` only
  (`internal/bootstrap/packs/core/orders/cascade-nudge-on-blocker-close.toml`),
  and nothing closes at readiness.

## The stays on a bead: bd's edges

**What it composes.** A stay already writes a `blocks` edge from its
conversation onto its work, or onto an input convoy that tracks the work when the
conversation tracks it. The order finds the stays on a PR's bead from that bead's
dependents (`bd dep list <bead> --direction=up`), the rows of those that read as
conversations, and the dependents of each open convoy among them that tracks the
bead alone and carries no `owned` label, which Gas City closes with the bead
(`convoyStillAutocloses`). It adds no record.

**The rework's wait.** The conversation tracks the PR's anchor, and bd keeps one
edge from a bead onto another (`DependencyTypeConflictError`, beads
`issueops/errors.go`), so it cannot block on the anchor. A graph.v2 sling pours
over a convoy that tracks the bead alone (`graphv2.NormalizeInputConvoy` and
`CreateSingleItemInputConvoy` in `internal/graphv2/invocation.go`), and Gas City
closes it when the bead closes (`doConvoyAutocloseWith` and
`convoyStillAutocloses` in `cmd/gc/cmd_convoy.go`). An edge onto that convoy sits
beside the anchor's `blocks` edge onto the conversation without a cycle, because
bd's cycle check walks only `blocks`, `conditional-blocks` and `parent-child`
edges (`types.IsSchedulingEdge` in beads `internal/types/types.go`, which
`WouldCreateSchedulingCycleInTx` applies). The ask a ruling files is not the
wait, because the review run's `record` step closes it before the refinery
validates the round's head (the review-lanes design, sections 1, 5 and 8).

**What else was searched.**

- **The session waits as the set.** `gc wait list` names each wait's session and
  beads, but the waits are cancelled by an attach, a restart and a close, and
  close once delivered, so a hold read off them would let a PR leave draft while
  its sitting reads. The edges outlive all of that.
- **A key on the conversation that names the PR's bead.** It would be a metadata
  key that only the pack reads, standing in for the edge the stay already writes.

## The hold: the PR's draft, and a condition of the evaluator's

**What it composes.** The review run's draft cycle already keeps a PR a draft
until the landing order marks it ready, and a draft is a condition of the city's
in the evaluator (`KindDraft` in `services/gctk/pr/pr.go`). GitHub requests no
review on a draft, and this repository's CI skips its suite on one
(`.github/workflows/tests.yml`). Under the design's call 1 (a), one clause in the
order's `readyBar` (`services/gctk/pr/draft.go`) keeps the PR a draft while a
stay owes its reading.

A draft does not reach a round that ends on a PR that is ready already, as when a
review run answers an ask with no push: its push step returns before
`gctk pr draft` (`cmd_push` in `assets/scripts/review-run.sh`), and only a writer
that pushes returns a PR to draft (`Draft` in `services/gctk/pr/draft.go`). The
merge the hold must stop is the landing order's own request, which asks the
evaluator and then GitHub (`decide` in `services/gctk/pr/landing.go`), so a hold
anywhere else would not reach it. The evaluator (`Ready` in
`services/gctk/pr/pr.go`) gains one condition kind of the city's, which holds the
merge while a stay owes its reading or is in progress, beside the waits, holds
and asks it already reads. Under call 1 (b), `readyBar` gains no clause, and the
condition alone holds the PR. No state or record comes with it: the condition is
computed at each read, from the stays, their rounds and the PR's comments, as the
evaluator computes every answer.

**What else was searched.**

- **A `blocks` edge from the PR's bead onto the conversation**, the conversation's
  hold on a PR's merge (`conversation_hold_merge` in `assets/scripts/gc-helm.sh`).
  For new work it closes a cycle with the stay's own edge onto the work, which bd
  refuses, and an edge onto the work's bead while the work is built would hold it
  from its own run and from the refinery's find-work.
- **`merge_hold`.** It is a hold a person sets by hand, which `prstatus` reads as
  `needs-attention`, and a stay is the city's work, not a person's hold.
- **GitHub's review request or a required check.** Either would make the reading
  one of the PR's checks, which the initiative's boundaries rule out.
- **A return to draft when a send-back is filed**, through `gctk pr draft` from
  `converse-rework.sh` or `gctk review ask`. It would add a writer of the draft
  flag that pushes nothing, beside the draft cycle's rule that every writer of
  the city returns the PR to draft before it pushes (the review-lanes design,
  section 5), and the next ready transition would run CI and request review
  again on a head both have already seen. It holds nothing before the send-back
  is filed, while the operator talks with the sitting, so the evaluator would
  still need its condition for a stay in progress.

## A stay's round: the lines it already writes

**What it composes.** `converse-signoff.sh --stay` appends a `staying:` line
naming the stay's work each time it stays, and the entry reads the stay from
those lines (`converse-entry.sh`). Their count is the stay's round, which the
evaluator reads from the conversation's notes when it reads the stays. No key,
state or record comes with it.

**What else was searched.**

- **A key on the conversation**, such as a counter the sign-off writes. It would
  be a second record of what the lines already say, one that can disagree with
  them, and a metadata key of its own.
- **The sign-off's time in its line.** It would name each ruling too, at the cost
  of a change to the line that the entry and the stopped-short recovery parse,
  where the count needs none.
- **The ask a send-back files.** A stay that changes what was agreed without
  sending the PR back files no ask, so an ask does not name every ruling.
- **The stay's Gas City session wait.** Its id changes within a round, because an
  attach, a restart or a delivered note ends the wait, and the entry registers
  another.

## The hold while the operator talks with the sitting again

**What it composes.** The claim-back's guarded write
(`gc bd update --if-assignee --if-status open --status in_progress`, in
`converse-stay`) and the hold's record (`converse-hold`), which a sitting already
makes when it must ask the operator something, and which the entry already reads
as a hold that stands (`converse-entry.sh`). The stay is then in progress, which
the evaluator's condition holds. What the skills say is no surface. The surface
this needs is the condition's clause for a stay in progress.

**What else was searched.**

- **engage's hold on the PR's merge** (`conversation_hold_merge` in
  `assets/scripts/gc-helm.sh`), added again for a staying conversation. It
  reaches only the PR of the conversation's subject, since an edge from new
  work's bead onto the conversation closes a cycle with the stay's edge onto that
  work. A hold engage wrote under a stay nobody talks to would stand with no wake
  to clear it, and the PR would read as the city's work (`Render` in
  `services/gctk/prstatus/render.go` reads a stay that holds a PR as `working`).
- **A claim engage writes for the sitting.** The entry reads a claimed stay whose
  newest record is its `staying:` line as one that stopped short, whose recovery
  runs the stay again and lets the claim go, and only the sitting can record what
  the operator owes.
- **Whether the operator is attached to the sitting's session**, the `attached`
  field that `gc-helm.sh` reads from `gc session list --json`. The evaluator
  would read Gas City's sessions on every pass and every board read, and a tab
  left attached would hold the PR with nothing on the record to say why.

## The record of a reading: the PR comment

**What it composes.** The rule asks for the reading to be on the PR, so the
reading's comment is its record. `pr-post.sh comment` is the one writer of the
city's posts and appends the city's mark, so the feedback intake never counts the
post (`assets/scripts/pr-post.sh`, `own-def`). The body opens with a marker that
names the conversation, the stay's round and the head, the way the city already
marks a purpose post, as the sitting reminder's `<!-- gc:sitting:<task> -->`
does. The evaluator
reads the PR's conversation comments on each pass (`GitHub.IssueComments` in
`services/gctk/pr/pr.go`). The landing order consults `readyBar` before the
evaluator runs (`decide` in `services/gctk/pr/landing.go`), so under call 1 (a)
its draft arm reads the comments once more, only for a PR whose bead has a stay.
Only a post of the city's own counts, by `pr-post.sh own-def`'s `gc_city_own`,
so a marker anyone else writes releases nothing. `pr-post.sh edit` rewrites a
reading in place when a return restarts.

**What else was searched.**

- **The session wait.** It closes when its nudge is delivered, before the
  sitting reads, so it cannot record that the reading came after.
- **A bead per reading, or a key on the conversation.** Each would be a record of
  the pack's own beside the comment the rule asks for, and two records of one
  fact can disagree.
- **A GitHub review.** `pr-post.sh review` posts a `COMMENT` review, which sits
  among the PR's reviews beside the approvals the merge rule reads. A reading
  passes and fails nothing, and a conversation comment is the form the stay's
  return already posts on a PR.

## The entry's `ready`: the record, read through gctk

**What it composes.** A sitting woken at readiness gets the hook's `drain`
answer with the reason `no_work` (`hookClaimReasonNoWork` in
`cmd/gc/cmd_hook_claim.go`), because its conversation still waits on open work
and is no ready work, so the claim does not say why it woke. A session's start
carries no wake cause (`PromptContext` in `cmd/gc/prompt.go` has no wake field),
and the wait's note reaches the prompt stream, not a script. So the entry reads
the record, as it already does for `waiting` and `returned`: it asks
`gctk pr status <bead> --json` whether the PR waits at its head for this
conversation's reading. The rule lives once, in gctk's pr domain, which the order
reads too, so the entry decides none of it itself.

**What else was searched.** Reading the PR on GitHub from the entry, through
`gh`, would put a second copy of the hold's rule in shell. The `reading` key is
one more key in an existing verb's output, which the label writer and the board
leave alone.

## The stay's waits in the sign-off

**What it composes.** `converse-signoff.sh --stay` already writes the stay's
lines, its edge and its guarded status write. It gains the session wait, through
`gc session wait "$GC_SESSION_ID"`, which needs no session argument in a sitting's
own shell. It reaches the subject through the dispatch's input convoy, PR #1515's
composition, and the anchor of the PR under discussion through the anchor's
input convoy. A sign-off that ends a stay cancels its waits with `gc wait
cancel`. It adds no flag: `--stay` and `--waiting-on` keep their meaning, and the
mode writes what the stay now needs.

## What it leaves in place

- **A sitting no wait can wake**, because its session closed, its return was cut
  short before it registered its wait again, or its wait's note failed to reach
  it, still stays, so its PR does not merge, and a draft stays a draft, until
  the operator engages or dismisses the conversation. The condition names it.
- **An operator who has opened a stay's conversation and not yet spoken in it.**
  Between engage's attach and the operator's first turn nothing holds the merge
  for the exchange to come (the design, section 2). Gas City closes a session
  only when a person or a prune asks, and the pack adds no sweep for it.
- **A rework of a PR whose anchor has no open input convoy**, such as a change a
  sitting edited and handed over through `work-submit.sh`, waits on the ruling's
  ask and comes back at the review run's `record`, a step before the readiness.
- **A person's own toggle** of the draft flag passes the hold, as it passes the
  draft cycle.
- **A rig on the old review path** has no ready transition, and the code nearest
  one, `gate-ensure.sh`, is on the deletion plan with tk-1tfzr71.22, so it gets no
  new work. Stays there come back as they do on main.
