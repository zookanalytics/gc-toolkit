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

One call is left, the send-back call, and it costs something either way. **Who
takes a check's send-back while the sitting is still open:**

- (a) The pool, as for any change. A check's finding is written down, which
  is the line's own test for polecat work. A send-back about a look then
  waits a polecat cycle, and you are not in it.
- (b) The open sitting. It keeps you in the loop on feedback about a look,
  and it waits for the review-lanes member, because the writer that files a
  send-back today is one that member deletes.

Approving as it stands ships (a), the pool taking a send-back. Merging this
design's PR releases the implementation, whose first four units land on the
effort's branch, the doctrine after the writers it names. The fifth, a sitting
editing an open PR's branch, is filed to wait for the review-lanes and merge
members.

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
   conversation, and the scope of the change. It is the bead's description when
   the sitting files the bead, and a note when the subject is itself the change.
   A PR's body falls back to its anchor's description, and the summary quotes
   the ruling, so a reviewer sees where the change's decisions came from.
2. On the subject, as step 6's outcome record: the ruling, and the bead that
   carries the change.
3. The hold (section 2): a `blocks` edge from the change's bead onto the
   conversation. Work's writers take it as the proof that this sitting holds the
   change.

## 2. Where the change lives

**Which bead is the change.** When the subject is itself work the line covers,
and no pool, live run or refinery holds it, the subject is the change's bead. A
change an earlier sitting left in flight is such a subject (below). Otherwise
the sitting files the bead as it files work for a pool (the work skill, "File
new work"), in its own rig's store, since section 1 keeps a sitting's changes to
its own rig's repository, with its target in the create: the default branch,
or the integration branch of an effort the change belongs to. It carries no
route and no `hold:mayor`, because the operator routed it in the sitting. The
subject waits on it as it waits on any work a sitting sends (the waits skill).

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
as its last write, once it has assigned the bead to the refinery (section 3),
and a conversation's close ends its effect, so nothing else writes a release.

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
  stays open and unrouted with its tree, its record names it on the subject, and
  the operator engages it to resume the change or closes it.

**What removes the tree.**

- The hand-off removes the tree and its local branch once the push is verified,
  as it removes a polecat's (`release_tree` in `work-submit.sh`). A send-back
  makes a fresh tree from origin's branch.
- When the operator drops a change, the sitting closes its bead through the
  disposition writer as not needed, with the conversation as the evidence, and
  then removes the tree and its local branch with git. Naming the conversation
  is also what lets the close land: bd refuses to close a bead that an open bead
  blocks, and the writer gives a `blocks` edge onto the bead it names way to its
  own edge (`bead-rehome.sh`). The edit skill gives the commands.
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
  `blocks` edge onto it. Either missing refuses, with nothing written.
- **No run control.** Every refusal, a hand-off write bd refuses among them,
  exits non-zero with its reason, and writes no gate, cancels nothing, closes no
  step and drains nothing, because the operator is in the sitting to hear it.
- **The release, last.** The hand-off removes the edge onto the conversation as
  its last write: after the three hand-off writes have assigned the bead to the
  refinery, and before the refinery's wake. The refinery's queue leaves an
  assigned bead that a wait of its own holds until the wait clears (find-work in
  `formulas/mol-refinery-patrol.toml`), so the assignment starts nothing while
  the edge stands.
- **A hand-off cut short.** One that stops before the release, on a refused
  write, a release that does not land or a call cut off, leaves the edge in
  place, so the proof still holds and the sitting runs the hand-off again. The
  second run writes nothing the first did not reach, beyond the hand-off's note
  appended again: a head the first run pushed is already on origin, the
  bring-current guard holds nothing on a branch with no PR, and the other writes
  set the values they set before. Once the release lands, the change is the
  refinery's, and a call that stops after it has missed only the refinery's wake
  and the removal of the tree. A run after the release is refused by the proof,
  its refusal says that the refinery holds the change, and the sitting then
  wakes the refinery as the hand-off does. The reaper removes the tree once the
  bead closes.
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

Under option (a) of the send-back call, a send-back goes where any change's
goes. A failure the branch caused at the refinery's gate sends the bead back to
the polecat pool with its branch kept and its `rejection_reason`, and a review
that requests changes files a rework child the pool runs (`signoff.sh` through
`rework-child.sh` today, and the review-lanes member's loop once it lands). The
sitting is not in that path.
A finding is written down, which is the line's own test for polecat work, and a
polecat resumes the sitting's branch because `metadata.branch` is authoritative
to Work's setup. When the operator wants to react to a send-back live, they
engage the change, and a sitting edits it as an open PR once unit 5 has landed.

Under option (b), an open sitting on the change takes its send-backs. Routing a
send-back to a sitting is new work on the rework writer that tk-1tfzr71.22
retires, so unit 5 would carry it, and the sitting would stay open, holding the
operator, until the change lands.

## 5. A copy of a rig's UI

**The per-rig declaration.** A rig declares how to serve its UI as a serve
command, `ui_serve_command`, among the commands the city's config sets for the
rig beside its lint and test commands, which are the rig's `[rigs.formula_vars]`
in `city.toml`. The copy script reads it as the demo engine reads
`app_reads_city`: `gc formula show <formula> --rig <rig> --json`, then the var's
`rig_default` (`assets/scripts/demo-engine-lib.sh:479-493`; that var is declared
at `formulas/mol-rig-demo.toml:95`). `mol-rig-demo` declares the serve command
beside it, along with the city's two values that Publishing describes, so one
call reads all three. The serve command is a var of its own and not
`mol-rig-demo`'s `serve_cmd`, because a rig's value is the default for every
pour of that formula, and its capture step declines a pour that names
`serve_cmd` beside a `serve_dir` or a `base_url`.

The declared command, run from the tree it is given, serves the rig's UI on
fixture data with no city behind it, listens on loopback at `$PORT`, and takes
nothing that two copies would share. It is one value for every branch of the
rig, so it names an entry point every branch carries. A rig that declares none
offers no live copy. That restricts live UI work to the rigs that can run an
isolated copy, which is the restriction the operator's concern offered. The
rig's demo guidance, its `docs/review-demo.md`, refers to the declared command
where it tells a capture what to serve, so the command has one home, and how
`demo-screenshot.sh` takes its command does not change. gc-toolkit's value runs
`go run ./cmd/helm-fixture` from `services/helm`
([review-demo.md](../../docs/review-demo.md#the-helm-board)). gc-toolkit sets
`app_reads_city = "true"`, so its declared command is the fixture server and
never the helm service.

**Isolation.** A copy runs from the change's tree, so it shows the change. It
listens on a free loopback port, chosen as `demo-screenshot.sh` turns
`--port 0` into a free port, so two copies never collide. It serves fixture
data with nothing live behind it. And it keeps an origin of its own: it is never
mounted under the supervisor as a Gas City service, because a page there shares
the supervisor's origin, and the board's own client reads the supervisor's API
relative to the page's origin (`services/helm/web/src/drill/origin.ts`), so a
copy mounted there would read the live city. A copy ends when the session that
started it stops it, or by Gas City's orphan sweep once that session has ended
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
so publishing works for any rig's UI with nobody at the host's screen. The copy
never listens on a network address. And it gets an origin of its own.

**The copy script.** One pack script runs a copy, and any session of a rig can
call it. The operator asked in conversation tk-mfwgu1a for a helper, or
configuration and a helper, that lets an agent run a local instance of a rig's
UI and learn the local port and the address to give them. This design gives it
one caller, the sitting, through `converse-edit`. The script does these things:

- **Start.** From a tree the caller names, it reads the rig's declared serve
  command, picks a free loopback port with `demo_engine_free_port`
  (`assets/scripts/demo-engine-lib.sh:226-231`), as `demo-screenshot.sh
  --port 0` does, runs the command there and prints the local port.
- **An address on request.** When the caller asks for one, it also publishes the
  port and prints the address to give the operator. A copy a session runs for
  its own checks takes no address.
- **Stop.** It ends a copy.
- **State.** It tells a caller whether a copy is running and whether it still
  has its address, because a publisher can end alone.
- **Output.** It prints the local port and the address so that a caller reads
  each without parsing prose.
- **No publisher.** Where the city sets none, it runs the copy, prints the port
  and says that no address can be given, and the sitting shows screenshots.
- **No cap.** Each copy has a port of its own, so any number run at once.

Its verbs, flags and value names follow the pack's scripts and the names beside
them in `[rigs.formula_vars]`.

**Publishing.** The city sets a publish command, `ui_publish_command`, and an
address pattern, `ui_address_pattern`. The publish command takes a copy's local
port and publishes it at an origin of its own for exactly as long as the command
runs. The address pattern gives the address for a port. There is no withdraw
command. The script runs the publish command in the copy's process group and
ties the two together. When the copy or the publish command ends, the script
ends the other, so no address outlives its copy, and a copy whose publisher
ended reads as having no address until the script publishes it again. A publish
the publisher refuses because another client was changing its config is tried
again, and a port refused as taken gets another free port.

In this city the publish command is `tailscale serve --yes --https=<port>
http://127.0.0.1:<port>`, run in the foreground, and the address is
`https://<the host's tailnet name>:<port>/`. `tailscaled` keeps such a mapping
under the command's own session and deletes it when that session ends, however
the command died. It refuses a port any mapping holds, so a copy cannot take the
supervisor's port. The city's publish command never runs `tailscale serve
reset`, which drops every mapping, the supervisor's included.

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
sign-off. A copy whose session has ended is ended by Gas City's orphan sweep,
which the design composes and does not rebuild. The sweep ends a process that
left its session's terminal, carries the session's `GC_SESSION_ID` and
`GC_CITY_PATH` and has been reparented to PID 1, once the session is closed, or
stopped with no live pane, and it kills that process's group. For a stopped
session it also needs the process's `GC_RUNTIME_EPOCH` and a start before the
stop. While the session runs, the sweep leaves the process alone, because a
process whose `GC_SESSION_ID` names a running session counts as that session's.
So the copy's leading process keeps the session's `GC_SESSION_ID`,
`GC_CITY_PATH` and `GC_RUNTIME_EPOCH`. It leads a process group of its own that
holds the copy and its publish command. And it is a program whose environment
macOS lets `ps` read, which an Apple platform binary such as `/bin/sh`,
`/bin/bash` or `/usr/bin/perl` is not.

The script cannot compose `detached-job.sh start` as it stands, because that
script removes `GC_SESSION_ID` from the job's environment to survive this sweep
(`assets/scripts/detached-job.sh:321`), and a `/bin/sh` wrapper leads its job.
In its place the script detaches the copy as that script does, through perl's or
python3's `setsid()`, keeps the three values, and leads the group with a program
whose environment `ps` reads, such as the Homebrew bash the pack's scripts run
under on this host.

A copy also ends when its session sleeps or is stopped. A held sitting does not
sleep, and the script's start is safe to repeat after a wake. No watcher inside
a copy polls for its sitting. Unit 4's first act is the proof on the host that
the sweep ends a copy started this way on the city's running gc. If it does not,
the fallback the operator accepted in conversation tk-mfwgu1a is that the
script's next start ends each copy whose session has ended, for which the
script then records each copy's session.

**Screenshots.** Where the script can give no address, the sitting captures each
look from the tree with `demo-screenshot.sh`, inside the sandbox where the live
city cannot be reached, and reads the image itself. The operator sees the images
on GitHub once the change has a PR, attached by `demo-deliver.sh`.

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
| `skills/converse-edit/SKILL.md` (new) | none | The line; the record; choosing or filing the change's bead; the hold edge; Work's setup and hand-off with `--held-by`; reading the polecat class's standards from their fragments before the first edit (`work-quality-polecats`, `learned-conventions-polecat`), as the mechanik reads its own; committing without identity flags and reading the first signature; a commit per agreed step; the rig's tests through `gctk rig`; the summary; each refusal; a hand-off cut short, which it runs again until the release lands, and the refinery's wake when a refusal says the refinery already holds the change; dropping a change; a change in flight at a hand-back, a restart or a dismiss; a UI copy (unit 4); an open PR, which sends a rework until unit 5. |
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
before where the table says so.

| # | Unit | What it builds | Waits on |
|---|---|---|---|
| 1 | Work's writers serve a sitting | `--held-by <conversation>` on `work-setup.sh` and `work-submit.sh`: the proof, refusals that end nothing, and the hand-off's release of the edge as its last write, after the refinery assignment, with a refusal after the release that says the refinery holds the bead. Tests in `work-setup.test.sh` and `work-submit.test.sh`: a sitting's setup and its re-entry to a recorded tree, a hand-off that assigns the refinery and then releases the edge, a hand-off stopped before the release, by a refused write or a failed release, that a second run completes with nothing written beyond what the first did not reach and its note appended again, a run after the release refused with the refinery named as the holder and nothing written, a missing edge and a hook that names another bead, each refused with nothing written, and a refusal that drains nothing. The `component-model.md` rows. The commit cites the search record. | nothing |
| 2 | One home for the PR summary's standard | The submit step's "Compose the PR summary" moves into the commit-conventions skill, whose description gains the summary. The submit step loads the skill and keeps its calls, and `formula-step-size.test.sh` holds. | nothing |
| 3 | The doctrine and the edit skill | Every row of section 6 except the UI section of `converse-edit`, and the first Debt entry of `architecture.md` removed. | units 1 and 2 |
| 4 | A copy of a rig's UI | The copy script, which starts a copy with or without an address, stops it and reports its state, and its tests, which stub the publish command so that no suite touches Tailscale. The serve command's declaration and the city's publish command and address pattern, as the three vars `mol-rig-demo` declares and the script reads. `converse-edit`'s section on a copy, which calls the script, gives the operator the address it prints and shows screenshots where it prints none. gc-toolkit's `docs/review-demo.md` pointed at the declared command. A bead for the mechanik to set gc-toolkit's serve command, which runs `go run ./cmd/helm-fixture` from `services/helm`, and the city's two values in the city's config. Its first act is the proof under Cleanup in section 5. | unit 3 |
| 5 | A sitting edits an open PR's branch | Built on tk-1tfzr71.22's rework in its loop and tk-1tfzr71.20's publication of a head, following whatever tk-1tfzr71.22's design settles. Under option (b) of the send-back call, it also routes a send-back to an open sitting. It removes the second Debt entry. | tk-1tfzr71.22 and tk-1tfzr71.20 |

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
  writer other than a rework child's polecat, which unit 5 waits on, and the
  send-back call is the operator's ruling on whether an open sitting takes a
  send-back.
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
  `demo-screenshot.sh --port 0` fills with a free port from
  `demo_engine_free_port`, and it refuses a `--addr` that is not a loopback
  address (`services/helm/cmd/helm-fixture/main.go:86-91`;
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
