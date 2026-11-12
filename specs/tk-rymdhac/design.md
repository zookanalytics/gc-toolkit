---
name: Design — a converse sitting edits a change live with the operator and hands it to review
description: The design for tk-rymdhac, the design child of initiative tk-bvw8j5t, read at main 126b66747. It draws the line for when a sitting changes a repository, says where the change lives and how it survives the sitting, which writer hands it to the refinery, where a check's send-back goes, how a rig's UI runs as an isolated copy the operator can see, and which doctrine changes, and it defines the units the implementation child files. Read it to approve the design at its gate, or to build one of its units.
---

# Design: a sitting edits a change with the operator and hands it to review

This is the design record for tk-rymdhac, the design child of the initiative
tk-bvw8j5t. The pack was read at main 126b66747, the commit
`integration/tk-bvw8j5t` was cut from. Gas City is cited by symbol or page at
`gastownhall/gascity` 34485296, and Gas Town at `gastownhall/gascity-packs`
7f86098c. The merge member's design (tk-1tfzr71.66, PR #1459, in review) was
read at its head 07a6cd0be. The city's own state was read on 2026-11-11. The
search behind the surface the units add is [gas-city-search.md](gas-city-search.md).

The operator's rulings in conversation tk-2clin7q, quoted on tk-bvw8j5t, bind
this design: a separate attended builder "is a singular entity. The whole reason
for converse is that we can have multiple of them, so I feel like it should be
converse that does it"; Gas Town's crew edits make it "sane for us to do this in
some form"; "The sitting isn't the check"; "We have an entire check set of
steps, I feel like that's the checks not a polecat"; and "Yes, send it to design
with PR checks as checks." The sitting's proposals beside those rulings are
weighed below, and the design adopts the line and the hand-off it proposed.

## What the operator approves

Today a sitting never changes a repository, so a wording, a look or a small fix
agreed with you goes to a polecat, and you see the result a review round later.
Approving this design lets a sitting make such a change itself, while you
watch, once you rule in the sitting that it should. The change lives in a
working copy of its own, waits on the conversation while the sitting edits it,
and leaves through the same hand-off a polecat's work uses, so the PR checks are
its checks, as you ruled. In this rig those checks test it as they test a
polecat's change: the refinery's gate lints it, the correctness check reads or
runs the tests its files select, and CI runs the whole suite on the PR that
takes it to `main`, so neither change meets the whole suite before review.
Work whose spec can be written down still goes to a polecat. A change to a PR
that is already open waits for the review-lanes member, which decides how a
PR's branch takes another writer, and until then a ruling on an open PR still
sends a rework.

How you see a copy of a rig's UI while a sitting changes it is decided. You
open the copy as a live page at an address of its own, which exists for exactly
as long as the copy runs, and any number of copies run at once. The tailnet lets
your devices reach every port on this host, but a copy listens only on the host
itself, so the city publishes it. It cannot go under the supervisor's address,
because the board's page reads the live city from whatever address it is served
on. It needs a publisher the city sets, a serve command the rig declares, and
one pack script. In a city that sets no publisher, the sitting shows you
screenshots instead. It captures each look and reads it, and you see the images
on the change's PR once it has one.

A check's send-back goes to the pool, as any change's does, even while the
sitting that made the change is still open, so a review's finding never comes
back into the sitting. When you want to react to a finding live, you engage the
change, and a sitting edits it as an open PR once unit 5 lands. Every live
change is a bead the sitting files. The sitting hands a change off on your go.
In conversation tk-16d2j3q you answered "Yes always a new bead" to a
recommendation that also sent every send-back to the pool, and "go" to the
rework that has the sitting hand off on your go.

Merging this design's PR releases the implementation, whose first four units
land on the effort's branch, the doctrine after the writers it names. The
fifth, a sitting editing an open PR's branch, is filed to wait for the
review-lanes and merge members.

The design serves the Core Belief "Human attention is the budget"
([foundation.md](../../docs/foundation.md)), with the mandate's high-bandwidth
human interaction: your reaction to a wording or a look reaches the change in
the sitting where you give it, and work that needs no reaction never holds you.

## 1. The line, and how the ruling is recorded

**The line.** A sitting changes a repository only when the operator rules, in
that sitting, that it make the change, and only a change whose next step is the
operator's reaction:

- a document's wording or a screen's look, which the operator reacts to as it
  takes shape;
- a small fix agreed in the sitting, whose spec would take as long to write as
  the change.

Work whose spec can be written down and sent goes to a pool on a formula, as it
does today. The ruling is what licenses an edit, so a sitting never edits on its
own judgment, and the line is how it judges what to propose. When the operator
asks for an edit outside the line, the sitting says so and recommends sending
it, and the operator's ruling decides. A sitting holds the operator while it
works, so work that needs no reaction would spend their attention for nothing.
The alternative, a sitting that edits whatever the operator asks, spends it on
work a pool does as well without them.

Whatever the ruling, a sitting never:

- holds more than one change in flight per conversation, so a second waits
  until the first is handed off or dropped;
- changes a repository other than its own rig's, the rig its conversation is
  filed in. The hold (section 2) is a `blocks` edge, which holds only between
  two beads in one store (the waits skill), so a change to another rig's
  repository is sent to that rig's pool;
- edits in its home, whose start syncs it to the default branch and refuses a
  start that finds an edit or a commit there (`sync_worktree` in
  `assets/scripts/worktree-setup.sh`);
- pushes to a target branch, merges, or forces a push: the hand-off pushes the
  change's own branch, and the refinery lands it;
- edits an open PR's branch before unit 5 lands (section 2);
- cuts an integration effort's branch, which stays the mechanik's recipe or
  `mol-design-convoy`'s step.

**The record.** Before the first edit, the sitting records the ruling three
ways, and each write's exit decides whether it landed:

1. On the change's bead: the operator's words, quoted, with the date and the
   conversation, and the scope of the change. It is the description of the
   bead, which the sitting files. A later sitting that resumes the change
   appends its own ruling to the bead as a note.
   A PR's body falls back to its anchor's description, and the summary quotes
   the ruling, so a reviewer sees where the change's decisions came from.
2. On the subject, as step 6's outcome record: the ruling, and the bead that
   carries the change.
3. The hold (section 2): a `blocks` edge from the change's bead onto the
   conversation. Work's writers take it as the proof that this sitting holds the
   change.

## 2. Where the change lives

**Which bead is the change.** The sitting files every change's bead, as it
files work for a pool (the work skill, "File new work"), in its own rig's store,
since section 1 keeps a sitting's changes to its own rig's repository, with its
target in the create: the default branch, or the integration branch of an
effort the change belongs to. It carries no route and no `hold:mayor`, because
the operator routed it in the sitting. For an epic subject, the bead is the
epic's member. When a pool, a run or the refinery already holds the subject,
the sitting tells the operator, and their ruling decides whether that work
stops (the work skill) before the change is filed. That reading informs the
operator and never picks the bead.

The subject waits on the change from the moment it is filed, before the first
edit. The sitting withdraws the subject's arm and pool route, as the sign-off's
"New work carries it" case does (the converse-settle skill), then writes the
wait the waits skill gives a bead that is checked and closed once other work
lands: the close brief, the `blocks` edge and the validating closer's arm. So
no pool takes the subject while the sitting edits, and a dismiss leaves the
subject waiting on the change. An epic subject already waits on its member and
takes no edge. A subject the sign-off arms no closer for, such as an epic,
whose members carry it, takes no brief and no arm either, because the sign-off
refuses a `--close-brief` for one (`converse-signoff.sh`).

At the sign-off, the sitting names the same wait, `--waiting-on <the change>`
with the brief's own text as `--close-brief`, and the sign-off writes none of it
a second time. The subject's headline, which the sign-off writes through
`gc-helm.sh takeaway`, adds the same edge again, and bd keeps one edge
(`AddDependencyInTx`, bd 1.3.4). The sign-off appends no brief while the
subject's latest close brief is held on the same change with the same text, and
it arms no closer that is already armed (`converse-signoff.sh`). So the subject
carries one close brief and one closer arm. An epic subject's sign-off names no
wait on its member, because bd refuses that edge.

The one bead a sitting edits that it did not file in its own sitting is a
change an earlier sitting filed and a dismiss left open, which the operator
engages to resume. The sitting resumes it because the bead's own record, the
ruling its description holds, says a sitting filed it for a change, never
because of who holds it at the time. A subject the sitting did not file carries
state the sitting did not write, such as a human gate waiting on the operator,
a pool route, a dispatch arm, a hold label, a branch from an earlier run, and a
description written before the ruling, which reviewers judge the change
against. Work's writers would meet all of it, while a bead the sitting files
carries only what the sitting wrote. The cost is a second bead beside the
subject until the change lands, and the subject's close through its validating
closer.

A resumed change is its own conversation's subject, so the subject's wait is
not written again. The original subject has waited on the change since the
earlier sitting filed it, and that wait stands. The resuming sitting adds only
its hold, the change's `blocks` edge onto its own conversation, and appends its
ruling to the change, which as the subject also takes its outcome record
(section 1). Before its first edit and at its sign-off, it writes no close
brief, no closer's arm and no edge that makes the change wait on itself.

**The tree.** Work's setup cuts the tree at `<the sitting's home>/worktrees/<bead>`,
on the bead's branch cut fresh from its target, and records `work_dir` and
`branch` on the bead. That is where and how it cuts a polecat's:
`assets/scripts/work-setup.sh` makes a new tree at `${GC_DIR:-$PWD}/worktrees/<bead>`
on `polecat/<bead>`. A sitting's home is a worktree of the rig named for its
conversation, `.gc/worktrees/<rig>/converse-<model>/<rig>.<conversation>`, and
its start's sync leaves `worktrees/` alone (`GC_WRITES` in
`worktree-setup.sh`: "the per-bead worktrees under the home"), as it does in
every polecat's home. The branch keeps the per-bead name, `polecat/<bead>`. It
belongs to the bead, and a send-back hands the same branch to a polecat
(section 4), so a second naming scheme would teach every reader of the per-bead
shape another one.

**The hold.** The change's bead depends on the conversation through a `blocks`
edge, which the sitting adds before Work's setup runs. While the conversation is
open, bd counts the change blocked, so it leaves `bd ready`, and no pool is
offered it even when something routes it. It is the bd edge that already holds
an open PR's merge while a conversation on the PR is open
([human-engagement.md](../../docs/human-engagement.md#a-conversation-on-an-open-pr-holds-its-merge)),
and it asks nothing of the platform. That page gives a pre-open anchor no such
edge, because the edge would stop the pool that builds it. Here the sitting
builds it, and keeping the pool off is the point. The hand-off removes the edge
as its last write, once it has assigned the bead to the refinery (section 3).
When Work's writers refuse the change because someone else holds it, the
sitting removes the edge itself, and a conversation's close ends the edge's
effect.

**Sleep, restarts and the next sitting.**

- The idle sleep stops a session's process and never touches its disk, and it
  skips a session that holds claimed work, so a sitting holding its
  conversation is not slept while it edits
  ([human-engagement.md](../../docs/human-engagement.md#how-a-held-sitting-ends)).
- A restart runs the home's sync, which leaves the tree alone, and the restart
  rule re-opens the sitting at its hold. The conversation's record names the
  change, and Work's setup, run again, re-enters the tree the bead records.
- A sitting that must end with the change in flight, for low context or because
  it was cut short, commits what it has, records where the change stands on the
  conversation, and hands the conversation back. The change stays held, because
  the conversation is still open, and the next sitting resumes it from the
  record. A sitting on another model has another home, and it enters the tree
  where the bead records it.
- The sitting commits after each step the operator agrees, so the tree holds
  nothing the next sitting cannot read. The commits stay local until the
  hand-off pushes them, as a polecat's do.
- A dismiss closes the conversation and so ends the hold. The change's bead
  stays open and unrouted with its tree, the subject keeps waiting on it, and
  the operator engages the change to resume it or drops it.

**What removes the tree.**

- The hand-off removes the tree and its local branch once the push is verified,
  as it removes a polecat's (`release_tree` in `work-submit.sh`). A send-back
  makes a fresh tree from origin's branch.
- When the operator drops a change, their ruling also says what becomes of the
  subject's ask, and the sitting carries both out through the work skill. It
  first withdraws the subject's validating-closer arm, so the closer does not
  ask the operator about a drop they ruled. The disposition writer moves no wait
  under not needed, so the change's close ends the subject's wait, and a closer
  still armed would then be sent. The sitting closes the change's bead through
  that writer as not needed, with the conversation as the evidence, and then
  removes the tree and its local branch with git. Naming the conversation is
  also what lets the close land: bd refuses to close a bead that an open bead
  blocks, and the writer gives a `blocks` edge onto the bead it names way to its
  own edge (`bead-rehome.sh`). Once the change has closed, the subject's wait on
  it holds nothing, and the sitting sends the subject on, closes it, or leaves
  it waiting on other work, as ruled. The edit skill gives the commands.
- A tree whose sitting ended before either is left on its branch, and Gas City's
  reaper removes it once its bead closes, as it does a polecat's
  (`auto_reap_closed_bead_worktrees`).

**A change to an open PR.** An open PR's branch takes one writer at a time.
Today that writer is the PR's rework child, which the rework writer
(`rework-child.sh`) files and a polecat runs, and the review machinery keys on
it: no review is dispatched while it is open, and a ruling's rework returns
every lane to unreviewed (`converse-rework.sh`, and Quiescence in
[state-machine.md](../../docs/state-machine.md)). A sitting's own push onto the
branch would bypass both, so once the conversation's hold ended, a lane could
stay green over a head no review read. The merge member's design also moves
every push onto a PR's branch onto its publication of the head (tk-1tfzr71.66,
section 4 and its unit 2). So a sitting edits an open PR's branch only through
the review-lanes member's rework, once that member (tk-1tfzr71.22) moves rework
into its loop, and through the merge member's publication (tk-1tfzr71.20).
Unit 5 builds it once both land. Until then a ruling on an open PR sends a
rework, as the converse-iterate-document skill has it, and the sitting can
settle the wording with the operator in the thread first. `work-tree-holder.sh`,
which tells whether a live session holds a work bead's tree, has no part in
this: the hold edge records who holds a sitting's change, and tk-1tfzr71.39
retires the script.

## 3. The hand-off

**On the operator's go.** The sitting hands a change off on the operator's go.
It asks for the go once the steps the operator agreed are in, and the operator
can give it up front when they rule the edit, which leaves the moment to the
sitting. After the hand-off every further change waits a review round, so the
operator says when they have finished reacting.

**The anchor and its target.** A new change has no PR yet, so its bead is the
anchor, as a polecat's fresh work is. Its target is the one it was filed with.
The refinery resolves a direct strategy on a bead whose target is the rig's
default branch to the PR pipeline (the merge-strategy-resolve block of
`formulas/mol-refinery-patrol.toml`), so a change bound for the default branch
reaches a PR whatever is stamped, and a change in an effort lands on the
effort's branch as the effort's other beads do.

**What the sitting composes.** Work's two writers, `work-setup.sh` for the tree
and `work-submit.sh` for the hand-off, take their bead from a run's input convoy
(`--convoy`) or from a claimant with no poured workflow (`--bead`). Each ends a
run on a refusal: it declines, cancels or files a gate, and it drains. A
sitting's claim is its conversation, and the sitting must outlive the hand-off.
So both writers take `--held-by <conversation>` beside `--bead`:

- **The proof.** `gc hook current` names that conversation, and the bead has a
  `blocks` edge onto it. Beside the hook and the edge, both writers refuse a
  bead that someone else holds or is queued to take: one assigned to anyone,
  the refinery included; one a run works; or one whose `gc.routed_to` names a
  pool. The assignee is a field of the row the writers already read once
  (`work_read` and `work_field .assignee` in `work-lib.sh`), which
  `work-submit.sh`'s `--bead` check reads today, though that check lets a bead
  assigned to the refinery through. Only `run-lib.sh`'s `run_lib runs` tells a
  run, because Gas City leaves a bead under a run open, unassigned and
  unrouted, and `work-setup.sh`'s `in_flight` already asks it for a live one.
  The route is the row's `gc.routed_to`, which `dispatch-path.sh` defines as
  the pool queue that serves the bead once bd reports it ready. A missing hook
  or edge, or any of the three, refuses, with nothing written. The writers make
  no exception, not even for a run of this sitting's own hand-off once it has
  assigned the refinery (A hand-off cut short, below). So a sitting that adds
  its edge to a change already with the refinery, a polecat or a pool is
  stopped by the writers rather than by its own reading, and the sitting then
  removes that edge, which would otherwise hold the holder's work until the
  conversation closes.
- **No run control.** Every refusal, a hand-off write bd refuses among them,
  exits non-zero with its reason, and writes no gate, cancels nothing, closes no
  step and drains nothing, because the operator is in the sitting to hear it.
- **The release, last.** The hand-off removes the edge onto the conversation as
  its last write: after the three hand-off writes have assigned the bead to the
  refinery, and before the refinery's wake. The refinery's queue leaves an
  assigned bead that a wait of its own holds until the wait clears (find-work in
  `formulas/mol-refinery-patrol.toml`), so the assignment starts nothing while
  the edge stands.
- **A hand-off cut short.** One that stops before the assignment, on a refused
  write or a call cut off, leaves the bead unassigned and the edge in place, so
  the proof still holds and the sitting runs the hand-off again. The second run
  writes nothing the first did not reach, beyond the hand-off's note appended
  again: a head the first run pushed is already on origin, the bring-current
  guard holds nothing on a branch with no PR, and the other writes set the
  values they set before. Once the assignment lands, the change is the
  refinery's, and a call that stops after it has missed at most the release,
  the refinery's wake and the removal of the tree. A run then is refused, with
  the refinery named as the holder and nothing written, whether or not the
  release landed. So the writers never have to tell a run of this sitting's own
  hand-off from a run on a change the refinery took another way, to which the
  sitting added its edge afterwards: both are refused. The sitting answers
  either refusal the same way. It removes its edge onto the conversation if the
  edge still stands, and it wakes the refinery as the hand-off does. The reaper
  removes the tree once the bead closes.
- **Everything else is the same code:** the branch gate, the target, the
  uncommitted check, the push and its verification, the bring-current guard,
  the anchor's summary and title, the three hand-off writes, the refinery's wake,
  and the removal of the tree with its local branch.

The hand-off removes the tree from under the sitting's home, so the edit skill
runs it in a subshell that enters the tree, and the sitting's own shell stays in
its home.

So the polecat's submit and the sitting's hand-off are one writer, as the
sitting proposed, and a fix to either is a fix to both. The sitting never brings
its branch current: the refinery's prep merges the target in, and a conflict
goes back to the pool (section 4). That keeps the bring-current guard, which the
deletion plan retires, a no-op on a sitting's branch.

**Commits, signatures and the push.** The sitting's commits are signed by its
session's own git configuration, as a polecat's are: each agent home's
`.gitconfig` turns signing on and names the key and the identity, and the rig's
clone sets none of them (read 2026-11-11). So the sitting commits with no
identity flags. gc-toolkit's rules require verified signatures on every branch,
`main` included (read 2026-11-11), so an unsigned commit is refused at the
push, and the hand-off reports the refused push. To find a missing key at the
first commit rather than at the hand-off, the edit skill has the sitting read
the first commit's signature status (`git log -1 --format=%G?` reads `G`). A
new change's branch heads no PR, so the hand-off's plain push and its check of
origin's ref are the whole push, and the merge member's publication, which a
push onto a PR's branch will need, does not apply to it.

**The summary and the title.** The sitting writes the PR's summary, because it
holds the rulings, to the standard a polecat's submit writes it to, and it
titles the anchor by the commit-conventions skill. That standard lives today in
the text of `mol-polecat-work`'s submit step ("Compose the PR summary"). Unit 2
moves it into the commit-conventions skill, which the submit step and the edit
skill both load, so it has one home. The summary quotes the ruling and says
that the change was made in a sitting.

**The checks.** The sitting runs no self-review loop. The PR checks are the
change's checks, as the operator ruled, and each runs what the rig declares for
it (section 10):

- The refinery's gate runs the checks the rig sets for `mol-refinery-patrol`.
  gc-toolkit sets a lint command and `run_tests = false`, and no test or
  typecheck command, so its gate runs lint and no tests.
- The correctness review takes a pass that `gctk rig` recorded at the commit it
  reviews, of the whole suite or of the suites the diff selects, as its test
  evidence. With none recorded there, it runs the suites the diff touches
  itself.
- CI runs the whole suite on a PR to `main`, and on no PR into another branch,
  and main's rules hold the merge until the suite passes on Linux and macOS. A
  change bound for `main` meets CI on its own PR. A change in an effort lands on
  the effort's branch with no CI run, and meets CI on the effort's landing PR.
- The operator approves the PR.

Before the hand-off, the sitting runs the suites its diff selects through
`gctk rig`, with the affected-tests command the rig declares for a polecat's
self-review, so the pass is recorded at the head it hands off. That record is
the test evidence a polecat's self-review records, and the correctness review
reads it as it reads a polecat's. So in gc-toolkit a sitting's change reaches
review linted and tested as a polecat's change does, and neither meets the whole
suite before review. The design relies on no such run, so it names none as a
prerequisite. Tests in this rig pin some prompt and skill text, so a wording
change can break a suite, and the operator is in the sitting to decide whether
the pin or the wording changes, where a polecat fixing it later would decide
without them.

## 4. A check's send-back

A send-back goes where any change's goes, even while the sitting that made the
change is still open (operator, conversation tk-16d2j3q). A failure the branch
caused at the refinery's gate sends the bead back to the polecat pool with its
branch kept and its `rejection_reason`, and a review that requests changes
files a rework child the pool runs (`signoff.sh` through `rework-child.sh`
today, and the review-lanes member's loop once it lands). The sitting is not in
that path.
A finding is written down, which is the line's own test for polecat work, and a
polecat resumes the sitting's branch because `metadata.branch` is authoritative
to Work's setup. When the operator wants to react to a send-back live, they
engage the change, and a sitting edits it as an open PR once unit 5 has landed.

## 5. A copy of a rig's UI

**One path for a person and a demo.** A copy of a rig's UI is served one way,
whoever consumes it. The operator ruled in conversation tk-ralyjxq that the copy
moves onto `gctk rig` and that the demo tools move with it: "Demo and user
viewing should be the same path, it's just about who consumes it (showsprint or
a user) and whether it needs to expose an external port or not." `gctk rig
serve` runs a copy from the checkout it is called in, reports its state and
stops it. A sitting starts one with an address for the operator. A demo
capture's `--serve` starts one with no address and points the SprintShow
engine at its loopback port, in place of the engine spawning the server itself.
The verb follows the rig noun's checks: its caller passes the commands, with
`--command` for the serve command, and `--check` reads a copy's state without
starting one. `--stop` ends it.

**The per-rig declaration.** A rig declares how to serve its UI as a serve
command, `ui_serve_command`, among the commands the city's config sets for the
rig beside its lint and test commands, which are the rig's `[rigs.formula_vars]`
in `city.toml`. `mol-rig-demo` declares it beside `app_reads_city`, along with
the city's two values that Publishing describes, so one call,
`gc formula show mol-rig-demo --rig <rig> --json`, reads all three as each var's
`rig_default`. The caller reads them, as a formula step renders a check's
command, and passes them to the verb, which reads no formula var. The serve
command is a var of its own and not `mol-rig-demo`'s `serve_cmd`, because a
rig's value is the default for every pour of that formula, and its capture step
declines a pour that names `serve_cmd` beside a `serve_dir` or a `base_url`.

The declared command, run from the checkout's top, serves the rig's UI on
fixture data with no city behind it, listens on loopback at `$PORT`, and takes
nothing that two copies would share. It is one value for every branch of the
rig, so it names an entry point every branch carries. A rig that declares none
offers no live copy. That restricts live UI work to the rigs that can run an
isolated copy, which is the restriction the operator's concern offered. The
rig's demo guidance, its `docs/review-demo.md`, refers to the declared command
where it tells a capture what to serve, so the command has one home.
gc-toolkit's value runs `go run ./cmd/helm-fixture` from `services/helm`
([review-demo.md](../../docs/review-demo.md#the-helm-board)). gc-toolkit sets
`app_reads_city = "true"`, so its declared command is the fixture server and
never the helm service.

**Isolation.** A copy runs from the change's checkout, so it shows the change.
It listens on a free loopback port the verb picks, so two copies never collide.
Its serve command runs inside the sandbox the pack's demo capture runs in,
`demo-engine-lib.sh`'s, through `demo_engine_sandboxed`: it cannot read the
city's directories, reach a loopback port but its own or a Unix socket, or
signal a process outside the sandbox, and it runs with none of the variables
that point a command at the city. So both consumers get the demo's isolation,
rather than only what a serve command promises. The verb finds the library in
the pack's scripts directory, which `GCTK_SCRIPTS_DIR` names, as `gctk merge`
finds its helpers. A capture's engine reaches a copy's port only once
`gctk rig serve --check`, asked in the checkout the process listening there
works in, answers that the copy runs on that port, which the verb reports only
while every process listening there at an address loopback reaches is in the
copy's own process group. A copy keeps an origin of its own: it is never mounted
under the supervisor as a Gas City service, because a page there shares the
supervisor's origin, and the board's own client reads the supervisor's API
relative to the page's origin (`services/helm/web/src/drill/origin.ts`), so a
copy mounted there would read the live city. A copy ends when its caller stops
it, or by Gas City's orphan sweep once the session that started it has ended
(Cleanup, below).

**Reach.** The tailnet lets the operator's devices reach every port on this
host. What their browser can open is decided on the host, first by the address
each program listens on, and then by the host's application firewall. The
firewall admits the programs on its list and software signed with a valid
certificate, and nobody is at the host's screen to approve another. Everything
the city runs listens on loopback, and the one thing published is the
supervisor, which `tailscale serve` maps to the host's HTTPS name. The board's
client notes that the operator opens the board from a phone or a laptop that is
not the city host (`drill/origin.ts`). So a copy on loopback is out of the
operator's reach until something publishes its port. A copy is published on a
port of its own and does not listen on the tailnet address itself, for the
reasons the operator agreed to in conversation tk-mfwgu1a. `tailscaled`, which
the firewall admits, takes the connection and hands it to the copy on loopback,
so publishing works for any rig's UI with nobody at the host's screen.

**The verb.** Any session of a rig can call it. The operator asked in
conversation tk-mfwgu1a for a helper, or configuration and a helper, that lets
an agent run a local instance of a rig's UI and learn the local port and the
address to give them. It prints one JSON line, so a caller reads each value
without parsing prose:

- **Start.** `--command` with the serve command runs it from the checkout on a
  free loopback port, and prints the port. A checkout has at most one copy, so a
  start for one whose copy runs reports that copy, which makes a start safe to
  repeat after a session wakes. A start whose command differs from the running
  copy's is refused and leaves that copy running, because the copy shows
  another app, so a capture never takes a copy of another command. A start
  reports a copy once it answers on its port as its own, and stops a copy that
  does not within its wait.
- **An address on request.** With `--publish-command` and `--address-pattern`
  it also publishes the port and prints the address to give the operator. A
  copy a capture runs takes no address.
- **Stop.** `--stop` ends a copy's whole process group.
- **State.** `--check` says whether a copy runs, answers on its port as its own
  and still has its address, because a publisher can end alone.
- **No publisher.** Where the city sets none, the copy runs with no address,
  and the report says why, and the sitting shows screenshots.
- **No cap.** Each copy has a port of its own, so any number run at once.

**Publishing.** The city sets a publish command, `ui_publish_command`, and an
address pattern, `ui_address_pattern`. The publish command takes a copy's local
port and publishes it at an origin of its own for exactly as long as the command
runs. The address pattern gives the address for a port. There is no withdraw
command. The copy's leader runs the publish command in the copy's process group
and ties it to the copy. When the copy ends, the leader ends the publish
command, so no address outlives its copy. When the publish command ends alone,
the copy runs on and reads as having no address until a start publishes it
again. A publish the publisher refuses because another client was changing its
config is tried again, and a port refused as taken gets another free port.

In this city the publish command is `tailscale serve --yes --https=<port>
http://127.0.0.1:<port>`, run in the foreground, and the address is
`https://<the host's tailnet name>:<port>/`. `tailscaled` keeps such a mapping
under the command's own session and deletes it when that session ends, however
the command died. It refuses a port any mapping holds, so a copy cannot take the
supervisor's port. Nothing runs `tailscale serve reset`, which drops every
mapping, the supervisor's included.

The city's two values are read by the call that reads the serve command, so any
session of the rig reads them, and the mechanik sets them. They are not an
environment value on the converse templates, which would reach only a sitting.
Gas City's config sets a formula var only for a rig and has no value set once
for a whole city (section 10), so the mechanik sets the two among the formula
vars of each rig that offers a live copy.

A copy on another port of the host's name shares the cookie jar of the
supervisor's host name, because cookies ignore ports. The supervisor and the
board set no cookie today, and a cookie added to either would reach every copy.

**Cleanup.** Stopping a copy ends its process group, which ends the publish
command with it. The sitting stops its copy at the hand-off, at a drop and at the
sign-off, and a capture stops the copy it started once the capture is taken. A
copy whose session has ended is ended by Gas City's orphan sweep, which the
design composes and does not rebuild. The sweep ends a process that left its
session's terminal, carries the session's `GC_SESSION_ID` and `GC_CITY_PATH` and
has been reparented to PID 1, once the session is closed, or stopped with no
live pane, and it kills that process's group. For a stopped session it also
needs the process's `GC_RUNTIME_EPOCH` and a start before the stop. While the
session runs, the sweep leaves the process alone, because a process whose
`GC_SESSION_ID` names a running session counts as that session's. So the copy's
leader keeps the session's `GC_SESSION_ID`, `GC_CITY_PATH` and
`GC_RUNTIME_EPOCH`. It is a gctk process, `gctk rig serve --lead`, that a start
runs in a session of its own, so it leads a process group that holds the copy
and its publish command and is reparented to PID 1 once the start exits. And
macOS lets `ps` read its environment, which it withholds for an Apple platform
binary such as `/bin/sh`, `/bin/bash` or `/usr/bin/perl`. The serve command
runs inside the sandbox with none of those values, in the leader's group, so
the sweep's kill of the group reaches it. `detached-job.sh start` does not
serve here, because it removes `GC_SESSION_ID` from the job's environment to
survive this sweep (`assets/scripts/detached-job.sh:321`).

A copy also ends when its session sleeps or is stopped. A held sitting does not
sleep, and a start is safe to repeat after a wake. No watcher inside a copy
polls for its session. Unit 4 proved on the host that the sweep ends a copy
whose leader carries an ended session's values, on the city's running gc.

**Screenshots.** Where the verb can give no address, the sitting captures each
look from the checkout with `demo-screenshot.sh --serve`, which serves it as a
copy with no address in the same sandbox and captures that copy, and reads the
image itself. The operator sees the images on GitHub once the change has a PR,
attached by `demo-deliver.sh`.

**Containers stay out.** Gas City runs a city's sessions in pods or sandboxes,
chosen for the whole city (`[session] provider`), and has no primitive that runs
one isolated app instance ([gas-city-search.md](gas-city-search.md)). A rig whose
UI cannot run on fixtures is not offered live UI work, and its own design takes
containers up once it needs them.

## 6. The doctrine and text that change

Unit 3 makes each change below. The new step skill is named `converse-edit`
here; its name follows [skills.md](../../docs/skills.md) when it is filed.

| Where | Today | After |
|---|---|---|
| `agents/_converse/prompt.template.md`, opening | "You never change a repo: you write no code, make no commits and merge nothing." | A sitting changes a repository only on the operator's ruling in the sitting, inside the line, and merges nothing. |
| the same, "A sitting is not a unit of work" and "asks for work; it does not do it" | No files, no commits; a repo change is the one line a sitting does not cross. | A sitting asks for work. The one exception is a change the operator rules it make with them, which it hands off as a polecat's work is handed off. |
| the same, Rules: a sitting's universe; disposing a subject | "What you never do is change a repository"; "never a repo change"; "Only a repo change does, and that goes to a molecule." | The rule states the line, the limits in section 1 and the edit skill, and keeps the reason that work a spec can carry is a molecule's. |
| the same, the step table | No row for an edit. | A row: steps 5 to 8, when the operator rules that the sitting make a change with them, load `converse-edit`. |
| `skills/converse-edit/SKILL.md` (new) | none | The line; the record; filing the change's bead and making the subject wait on it at once; resuming a change a sitting filed; asking the operator's go before the hand-off; the hold edge; Work's setup and hand-off with `--held-by`; reading the polecat class's standards from their fragments before the first edit (`work-quality-polecats`, `learned-conventions-polecat`), as the mechanik reads its own; committing without identity flags and reading the first signature; a commit per agreed step; the rig's tests through `gctk rig`; the summary; each refusal; a hand-off cut short, which it runs again, and a refusal that says the refinery holds the change, which it answers by removing its own edge and waking the refinery; dropping a change; a change in flight at a hand-back, a restart or a dismiss; a UI copy (unit 4); an open PR, which sends a rework until unit 5. |
| `skills/converse-iterate-document/SKILL.md` | "A sitting writes no files, so it changes a document by sending work." | Two ends: the operator rules the sitting edit the document itself (`converse-edit`), or the scaffold and one rework, which stays the way to change an open PR until unit 5. |
| `skills/records/SKILL.md` | A sitting writes no files, so it files a bead for a document. | A sitting writes a document only as a change the operator ruled it make, and otherwise files a bead for it. |
| `skills/work/SKILL.md`, "Stand up an integration effort", and `skills/work/integration-effort.md` | "a converse sitting never pushes, so a sitting does not run it" | A sitting pushes only the branch of a change the operator ruled it make, through Work's hand-off, so the effort's branch is cut by the recipe's runner or `mol-design-convoy`. |
| `docs/design-convoy.md`, and `formulas/mol-design-convoy.toml` (its description and seed-branch step) | A sitting never pushes, so it cannot cut the branch. | The same conclusion, from the same reason as the work skill's. |
| `docs/human-engagement.md` | "Iterating on a document. A sitting writes no files"; "A sitting is not a unit of work ... The one line it does not cross is a repo change." | The two paragraphs restated, and a section under The sitting, "A sitting's change", with sections 1 to 4 at the page's altitude. The rule that a pre-open anchor takes no conversation edge gains its exception. |
| `docs/authority-map.md` | Close-with-successor and acting on a subject's PR forbid converse to "change a repo". | A row for the new power, editing a change and handing it to the refinery from a sitting: its holder, the evidence (the ruling recorded, the hold edge), and what it may never do (section 1's limits). The two prohibitions narrow to match. |
| `docs/state-machine.md` | "converse never pushes code; the molecule does." | A ruling on an open PR still files a rework a polecat runs, until unit 5. |
| `docs/feedback-learning.md`, `skills/learning-distill/SKILL.md` | "a standard about changing a repo does not reach the human converse class" | Such a standard reaches a sitting through the edit skill, which has it read the polecat class's fragments before its first edit. |
| `docs/built-once-target.md`, Human engagement | "A sitting is a converse session that holds the conversation doctrine." | It also edits a change on the operator's ruling, through Work's writers. |
| `assets/scripts/converse-rework.sh`, header | "converse never pushes code; the molecule does" | The rework is how a ruling changes an open PR until unit 5. |
| `docs/architecture.md` | This PR states the target and its Debt. | Unit 3 removes the first Debt entry, and unit 5 the second. |
| Suites | `skill-needs.test.sh` pins the work skill's sentence, and its step-table check names every skill the table loads. | The pins follow the new text, the new skill exists, and every suite the edited text breaks is fixed with it. The seed audit is re-rendered for the prompt. |

The mechanik's own no-edit rule is out of scope, and the po's is unchanged.

## 7. What waits on the deletion plan

Nothing in this design builds on a file `tools/deletion-plan.tsv` lists.

| File | Retired by | What this design does with it |
|---|---|---|
| `rework-child.sh` | tk-1tfzr71.22 | Nothing. A ruling on an open PR still files a rework through it, by `converse-rework.sh`, until unit 5, which waits on tk-1tfzr71.22. |
| `gate-ensure.sh`, `review-outcome.sh`, `review-sweep.sh` | tk-1tfzr71.22 | Nothing. They are why unit 5 waits. |
| `bring-current-guard.sh`, `bring-current-audit.sh` | tk-1tfzr71.20, and tk-1tfzr71.66 keeps them until tk-1tfzr71.22 | The hand-off keeps calling the guard, unchanged. A sitting never brings its branch current, so the guard has nothing to hold on its branch. |
| `refinery-reconcile.sh`, `refinery-workspace.sh`, `merge-tail-report.sh` | tk-1tfzr71.20 | Nothing. The hand-off assigns the bead to the refinery as a polecat's does. |
| `pr-facts.sh`, `review-answer.sh`, `review-dismissal.sh` | tk-1tfzr71.21 | Nothing. |
| `work-tree-holder.sh` | tk-1tfzr71.39 | Not used. The hold edge records who holds a sitting's change. |

Two retirements touch the same writers. The merge member's unit 2 moves
`work-submit.sh`'s push onto its publication of a head, and unit 1 adds
`--held-by` to the same script, so whichever lands second carries the other.
`integration/tk-1tfzr71.15` rewrites `work-setup.sh`'s stop path, which a
sitting never takes, and unit 1's change to the same script is merged with it
the same way.

## 8. The units

The implementation child (tk-rbasce7) files these, each in order behind the one
before where the table says so. Units 1 to 4 build now, and unit 5, filed
outside the effort, waits on tk-1tfzr71.22 and tk-1tfzr71.20 (operator,
conversation tk-16d2j3q: "yes, build the rest").

| # | Unit | What it builds | Waits on |
|---|---|---|---|
| 1 | Work's writers serve a sitting | `--held-by <conversation>` on `work-setup.sh` and `work-submit.sh`: the proof, with its refusal of a bead someone else holds or is queued to take, the refinery included; refusals that end nothing; and the hand-off's release of the edge as its last write, after the refinery assignment. Tests in `work-setup.test.sh` and `work-submit.test.sh`: a sitting's setup and its re-entry to a recorded tree; a hand-off that assigns the refinery and then releases the edge; a hand-off stopped before the assignment by a refused write, which a second run completes with nothing written beyond what the first did not reach and its note appended again; a run once the refinery is assigned, refused with the refinery named as the holder and nothing pushed or written, whether this conversation's own hand-off stopped before its release or completed it, or the refinery took the bead another way and this conversation's edge was added afterwards; a missing edge, a hook that names another bead, a bead assigned to another holder, one a run works and one with a pool route, each refused with nothing written; and a refusal that drains nothing. The `component-model.md` rows. The commit cites the search record. | nothing |
| 2 | One home for the PR summary's standard | The submit step's "Compose the PR summary" moves into the commit-conventions skill, whose description gains the summary. The submit step loads the skill and keeps its calls, and `formula-step-size.test.sh` holds. | nothing |
| 3 | The doctrine and the edit skill | Every row of section 6 except the UI section of `converse-edit`, and the first Debt entry of `architecture.md` removed. | units 1 and 2 |
| 4 | A copy of a rig's UI | The copy's verb, `gctk rig serve`, which starts a copy with or without an address inside the capture's sandbox, stops it and reports its state, with the demo captures' `--serve` moved onto it, and its tests, which stub the publish command so that no suite touches Tailscale. The serve command's declaration and the city's publish command and address pattern, as the three vars `mol-rig-demo` declares and the verb's callers read. `converse-edit`'s section on a copy, which calls the verb, gives the operator the address it prints and shows screenshots where it prints none. gc-toolkit's `docs/review-demo.md` pointed at the declared command. A bead for the mechanik to set gc-toolkit's serve command, which runs `go run ./cmd/helm-fixture` from `services/helm`, and the city's two values in the city's config. Its first act is the proof under Cleanup in section 5. | unit 3 |
| 5 | A sitting edits an open PR's branch | Built on tk-1tfzr71.22's rework in its loop and tk-1tfzr71.20's publication of a head, following whatever tk-1tfzr71.22's design settles. It removes the second Debt entry. | tk-1tfzr71.22 and tk-1tfzr71.20 |

## 9. Edges and notes the implementation child adds

- Units 1 to 4 are filed as tk-rbasce7's description says: `target=integration/tk-bvw8j5t`
  in the create, with the effort's landing bead (tk-bvw8j5t) and summary task
  (tk-e87vbl3) each waiting on them, and each unit waiting on the units the
  table names.
- Unit 5 is filed outside the effort, with target `main`, waiting on
  tk-1tfzr71.22 and tk-1tfzr71.20 through `blocks` edges and armed to dispatch
  when both have closed. Neither the landing bead nor the summary task waits on
  it, so the effort lands without it, and the second Debt entry says what is
  missing until it does.
- A note on tk-1tfzr71.20: its unit 2 publishes the push of `work-submit.sh`,
  which unit 1 gives a sitting's caller, and whichever lands second carries the
  other.
- A note on tk-1tfzr71.22: its design decides how an open PR's branch takes a
  writer other than a rework child's polecat, which unit 5 waits on. An open
  sitting takes no send-back, by the operator's ruling in conversation
  tk-16d2j3q, so unit 5 routes none to one.
- The mechanik's bead from unit 4 goes to the mechanik, and no bead of the
  effort waits on it, since a rig with no declared serve command offers no live
  copy and a city with no publisher shows screenshots.

## 10. Facts this design rests on

- **The converse seats.** Each `converse-<model>` template runs a manual
  session in a worktree home at `.gc/worktrees/{{.Rig}}/converse-<model>/{{.AgentBase}}`,
  with `pre_start` running `worktree-setup.sh ... --sync`, `wake_mode = "resume"`
  and `sleep_after_idle = "10m"` (`agents/converse-claude-opus/agent.toml`).
  On disk the home is named for the conversation, as in
  `.gc/worktrees/gc-toolkit/converse-claude-opus/gc-toolkit.tk-2clin7q`, and
  242 converse homes stood in this rig on 2026-11-11, closed sittings' among
  them, so nothing removes a sitting's home when the sitting ends.
- **The home's sync** fails a start on a commit the tip lacks, on another
  branch, on an operation stopped partway, on a changed tracked file and on an
  untracked file gc did not write, and files a patrol finding
  (`check_head`, `check_changes` and `report` in `worktree-setup.sh`). Its
  `GC_WRITES` hides `worktrees/` from that check.
- **Work's writers.** `work-setup.sh` makes a new tree at
  `${GC_DIR:-$PWD}/worktrees/$WORK_ID` and cuts `polecat/$WORK_ID` when
  `metadata.branch` is unset, and its refusals end through `decline.sh`, which
  cancels the run and drains. `work-submit.sh` refuses a `--bead` caller that
  holds neither that bead, as `gc hook current` names it, nor the run's step,
  closes the step through `claim-close.sh`,
  ends each refusal with `gc runtime drain-ack` or a gate and a cancel
  (`work_stop_with_gate`), and removes the tree with its local branch after the
  hand-off (`release_tree`).
- **One store per edge.** A `blocks` edge holds only between two beads in one
  store, and a link across two stores prints success and holds nothing
  (`skills/waits/SKILL.md`). A conversation is filed in its subject's rig
  (`docs/human-engagement.md`, Engage). Gas City's reaper lists a rig's trees
  from the rig's own repository and acts only on those under
  `.gc/worktrees/<rig>/` (`reapClosedBeadWorktrees`), so it would never reap a
  tree of another rig's repository under a sitting's home either.
- **The disposition writer** gives a `blocks` edge onto the bead it names way
  to its own edge just before the close, because bd refuses to close a bead
  that an open bead blocks (`bead-rehome.sh`).
- **The refinery's strategy.** `merge-strategy-resolve` in
  `formulas/mol-refinery-patrol.toml` turns a direct strategy on a bead whose
  target is the rig's default branch into the PR pipeline.
- **The rules.** gc-toolkit requires verified signatures on every branch, and on
  `main` also a PR, linear history and status checks
  (`gh api repos/<owner>/<repo>/rules/branches/<branch>`, read 2026-11-11).
- **The operator's reach** (read on the host 2026-11-11, each with its command
  in tk-rymdhac's notes of that date). The packet filter this node received
  allows every tailnet peer every port, TCP and UDP (`tailscale debug netmap`).
  `tailscaled` runs as root on a utun interface, so a loopback listener is not
  reachable on the tailnet address. `tailscale serve status` maps only `/` on
  the host's HTTPS name to `http://127.0.0.1:8372`, the supervisor. Every TCP
  listener of the city's user is on loopback (`lsof`). The application firewall
  is on, in stealth mode, and admits built-in and downloaded signed software on
  its own (`socketfilterfw --getglobalstate` and `--getallowsigned`). Its list
  allows node, sshd-auth, mosh-server, tailscaled, `/usr/bin/python3` and
  `/usr/bin/ruby` beside Apple's own services, and blocks Homebrew's Python.app
  (`socketfilterfw --listapps`). Whether it blocks a fresh `go run` build
  listening on the tailnet address was not tested. Such a build carries only an
  ad-hoc signature with no certificate (`codesign -dv` on a Go build of the
  city's), and no list names it, so the inference is that it would wait for an
  approval at the host's screen. The board's drill plane reads
  `/v0/city/<city>/...` relative to the page's origin, under a
  `connect-src 'self'` policy, because the operator opens the board from a phone
  or a laptop (`services/helm/web/src/drill/origin.ts`).
- **The city's publisher.** `tailscaled`'s prefs name the city's user as its
  operator (`tailscale debug prefs`), and Tailscale's CLI reference says "The
  operator can manage Serve and Funnel port targets, but serving a file,
  directory, or Unix socket still requires root" (tailscale.com/kb/1080/cli).
  Its Serve reference says that with `--bg` a serve "runs persistently in the
  background until you disable it" (tailscale.com/kb/1242/tailscale-serve).
  Tailscale's source is read at `tailscale/tailscale` tag v1.104.5, the host
  daemon's version. A foreground `tailscale serve` stores its mapping under
  `ServeConfig.Foreground`, keyed by the CLI's session and valid for that
  session's life (`ipn/serve.go`, lines 70-76). The daemon deletes it when that
  session ends (`ipn/ipnlocal/local.go`, `WatchNotificationsAs`, the deferred
  `DeleteForegroundSession` at line 3938), and it refuses a port that is taken
  (`ipn/ipnlocal/serve.go`, `validateServeConfigUpdate`, lines 1851-1888, and
  the comment at line 345). Exercised on the host as the city's user with no
  sudo and no terminal: a mapping appeared and its address answered, three
  coexisted, a second claim on a mapped port was refused, one of two starts in
  the same instant was told to try again, a `kill -9` of the command removed its
  mapping within three seconds, and the supervisor's mapping was unchanged
  throughout. The operator then opened a page published this way from their own
  device ("Yes, that worked", conversation tk-mfwgu1a).
- **Cookies.** The supervisor and the board set no cookie on `/`, `/health`, the
  city's status route or the board's page, and `services/helm` has no cookie
  code.
- **Gas City's orphan sweep** (`gastownhall/gascity` 34485296). gc scans the
  host's process table for a session's leftover processes, as it does for tmux
  sessions: "a process that left the agent's process group and outlived its
  terminal, carrying the session's `GC_SESSION_ID` and `GC_CITY_PATH`. The
  orphan sweep ends such a process once its session is closed, or stopped with
  no live box under its name, and a session's start ends its own stopped
  incarnation's leftovers first" (`docs/reference/exec-session-provider.md`,
  lines 637-643). In code, `sweepProcessTableOrphans` takes only a root that is
  untracked and reparented to PID 1 (`processRootReapable`), and
  `processRootIncarnationOver` ends it once its session's row is closed or
  absent, or open and stopped with no live pane, which also needs the root's
  `GC_RUNTIME_EPOCH` and a start before the stop (all in
  `cmd/gc/session_beads.go`). The tmux provider counts a root as tracked while
  its `GC_SESSION_ID` names a running session (`FindRuntimesBySessionID` in
  `internal/runtime/tmux/adapter.go`). A start runs `Manager.killExistingOrphans`
  (`internal/session/manager.go`). The kill signals the root's process group,
  TERM then KILL (`internal/runtime/proctable/kill_unix.go`). On macOS the scan
  reads each process's environment as `ps` does
  (`internal/runtime/proctable/scan_darwin_records.go`), and macOS withholds an
  Apple platform binary's environment from every other process
  (`internal/pidutil/environ_darwin.go`). On the host, `ps` read no environment
  for `/bin/sh`, `/bin/bash`, `/bin/sleep` or `/usr/bin/perl`, and read it for
  Homebrew's bash, including one that perl's `setsid()` started. The sweep was
  not exercised on this host for a copy, which is unit 4's proof.
- **A rig's declared commands.** Gas City gives a formula var a value per rig,
  in `formula_vars` on a rig and on a rig patch, and its config has no formula
  var set once for a whole city: the City table carries none, and
  `[defaults.rig]` seeds only a rig's imports (`docs/reference/config.md` at
  `gastownhall/gascity` 34485296, Rig's `formula_vars` at line 821 and
  RigPatch's at line 837; `Rig.FormulaVars` in `internal/config/config.go`). A
  rig's value is the default for a var a formula declares, and a session reads
  it through `gc formula show <formula> --rig <rig> --json`, as the var's
  `rig_default` (`rigFormulaVarsForScope` in `cmd/gc/cmd_formula.go`).
  gc-toolkit's `[rigs.formula_vars]` set `lint_command`, `run_tests`,
  `affected_tests_command` and `app_reads_city`. `mol-rig-demo`'s capture step
  declines a pour that names more than one of `serve_dir`, `serve_cmd` and
  `base_url` ("Resolve the app target" in `formulas/mol-rig-demo.toml`).
- **The fixture board.** `helm-fixture` listens on loopback at `$PORT`, which
  `gctk rig serve` fills with a free port for a copy, and it refuses a `--addr`
  that is not a loopback address (`services/helm/cmd/helm-fixture/main.go:86-91`;
  [review-demo.md](../../docs/review-demo.md#the-helm-board)).
  `demo-deliver.sh` attaches a file to a PR through `gh pr comment --attach`,
  so an image reaches GitHub only through a PR.
- **The pipeline's checks** (read 2026-11-11). The refinery's run-tests step
  takes each check from the rig's own value where the rig sets one, and runs
  `test_command` only when `run_tests` is true (the rig-check-commands block of
  `formulas/mol-refinery-patrol.toml`). gc-toolkit sets `lint_command` and
  `run_tests = false`, and no test or typecheck command
  (`gc formula show mol-refinery-patrol --rig gc-toolkit --json`), so its gate
  runs lint only, as `docs/review-correctness.md` says under "Where the gates
  run". A polecat's self-review runs the rig's `lint_command` and its
  `affected_tests_command`, `tools/run-tests.sh --affected origin/main`, through
  `gctk rig` (`gc formula show mol-polecat-work --rig gc-toolkit --json`). The
  correctness review takes a full or affected pass recorded at the reviewed
  commit as its evidence, and runs the suites the diff touches when none is
  recorded (`skills/review-correctness/SKILL.md`, "Settle the test evidence").
  CI runs the whole `*.test.sh` suite on Linux and macOS, and vets and tests the
  Go modules, on pull requests to `main` and pushes to it, and on no pull
  request into another branch (`.github/workflows/tests.yml`). Main's rules
  require the two suite jobs, `test` and `test-macos`
  (`gh api repos/<owner>/<repo>/rules/branches/main`). tk-w1qqeoh's notes say
  the gate runs the full suite and typecheck, which holds only for a rig that
  sets those checks.
- **The merge member's design** (tk-1tfzr71.66 at 07a6cd0be): a polecat hands
  its bead to the refinery as it does today; each push onto a PR's branch
  publishes the head through its unit 2; one worker per branch, a branch with an
  open rework child taking its conflicts through that child, until
  tk-1tfzr71.22; and the bring-current audit and guard stay until tk-1tfzr71.22.
- **The deletion plan** is `tools/deletion-plan.tsv` at main 126b66747.
