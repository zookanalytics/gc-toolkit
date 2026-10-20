---
name: Converse on native human gates — a question is a gate, a conversation is a task
description: The design for tk-0ur8r9p, the design child of convoy tk-iirrmiw under initiative tk-1tfzr71.4, rewritten to the ruling of sitting tk-4t0uev0. A question for the operator becomes one native human gate that blocks what waits for its answer, filed by escalate.sh, answered by resolving the gate with the outcome at the head of its reason, and never claimed by a session. A conversation becomes an ordinary task that tracks the bead or question it is about, held by a manual converse session named for it. The helm board reads both directly. The visit bead kind, the sweep that turned gates into visits, and the scripts that kept the two in step retire. It settles what a question blocks and carries, what a conversation is, the one writer, every caller and reader, how a question reaches the operator, the sitting's claim, recovery and ending, the board's read path, the skills and prompts, the retire list and keys, the migration of open visits, the cutover, the build breakdown and the sequencing with the epic's other members. It also records the platform facts it was verified against and the premises of the initiative's ruling and of the sitting ruling that did not hold, and it supersedes the specs that record the visit design. Read it to approve the design at its checkpoint or to build one of its units.
---

# Converse on native human gates: a question is a gate, a conversation is a task

## What the operator approves here

Today a question the city needs you to answer is a visit, a task bead of the
pack's own, and the visit is also where your conversation with converse takes
place. Some questions are filed first as native human gates, a sweep files
visits for them, and the rest of the pack reads the visits. After this change
the question and the conversation are two native things. A question is a human
gate on what waits for your answer. A conversation is an ordinary task that a
converse session holds while you talk. Nothing converts one into the other, and
the board reads both directly. Your sitting with converse, the record it
leaves, the board's ranking and the keys you press stay as they are. The ruling
of sitting tk-4t0uev0 set this model, and these decisions build it.

1. **A question is one native human gate, and it blocks what waits for your
   answer.** The filer names what waits: the work bead that declined, the
   anchor when the merge must wait, one member of an epic. The gate names the
   bead it is about in its await id, so the question is found on that bead
   even when it does not wait itself. An epic, or a convoy with open children,
   is blocked only when the filer names it, because blocking one pauses every
   part of it that has not started. A question carries no pack metadata, and
   the visit bead kind goes. Cost: a filer whose subject is one of those must
   say what waits, or the writer files nothing. Routed work that waits leaves
   the pool's offer until you answer, and a question that blocks a PR's anchor
   holds its merge.
2. **A question nothing waits on is not a gate.** A conversation you open is
   only its task, and it holds nothing. Work a person owes is an ordinary bead
   assigned to them, and news nothing waits on is mail. Cost: an open
   conversation about a PR no longer holds its merge, as an open visit does
   today. A sitting that wants the merge to wait asks a question on the anchor.
   A first reaction or a closing check on an epic reaches you as a
   conversation, without Accept, because nothing on the epic waits.
3. **escalate.sh is the one writer of questions.** It reads the bead's
   questions before it files, so each situation is asked once. It keeps the
   one-day quiet period after you call a situation moot or benign, and a filer
   can still withdraw its own question. gc-helm.sh demand, mol-visit and every
   copy of the visit-filing block go. Cost: two situations on one bead are two
   gates. They fold into one board row and one sitting.
4. **Every caller keeps its call.** The polecat decline stays escalate.sh, then
   await-ruling.sh, then run-cancel.sh, and await-ruling.sh still makes the
   work bead wait on the question, releases the claim and arms the re-sling.
   Only `--pool` retires. Cost: the callers whose subject can be an epic say
   what they do there, and every reader that looked for a visit reads the
   bead's gates.
5. **No session claims a question.** A gate is unassigned while it is owed, or
   assigned to the one person who owes the answer. The answer is one
   `bd gate resolve` whose reason leads with `ruled:`, `moot:` or `benign:`,
   and the record goes on the bead's notes. When two answer one question, the
   first resolve wins and the other is told. Cost: Accept or a filer's
   withdrawal can answer a question while a sitting discusses it, and the
   sitting learns it at its sign-off.
6. **A sitting is a manual converse session holding one conversation task.**
   Engage files the task, or takes the bead's own, starts a session named for
   it and attaches you. The session claims the task, and that claim keeps a
   second sitting off it. A second live sitting on one question is warned
   about, never refused. Recovery resumes the sitting first: attaching wakes
   it and replays the conversation, and a sitting whose session was closed
   comes back as a new session under the same name, which takes its task
   back. converse-claim, the put-back, the fold, the restart forensics and
   engage's reclaim go, and converse needs no work query. Cost: a question in
   a sitting is two beads, the gate and the task. A sitting whose session was
   closed comes back with its record, not its transcript. converse-reap
   stays, because Gas City does not end a manual session when its work
   closes.
7. **A sitting ends by answering, holding or dismissing.** A hold keeps the
   task and the session. Dismiss closes the task and answers nothing. Cost:
   dismissing a sitting no longer clears an escalation from the board. It
   stays until it is answered or its filer withdraws it.
8. **The board is how a question reaches you.** The town's city.toml also
   turns off core's notify-on-human-gate-creation, next to the re-ask order it
   already turns off, because both mail a mailbox you do not read. Cost: a
   town-repo commit. No mail or nudge announces a question, which is today's
   behavior.
9. **The board reads gates and conversations directly and ranks them as
   today.** A question folds onto the bead it is about, and a conversation
   onto the bead its task tracks. A row is in session while a live sitting
   holds its conversation. Accept answers only the question that put a
   recommendation to you. While another question still blocks the bead, the
   row offers Discuss and names that question. Cost: the board gains a gate
   read and a conversation read that no test covers today. A recommendation
   beside another open question waits until that question is answered, where
   today's Accept closed every waiting question on the bead with one click.
10. **Cutover is one migration run per store, right after the pack update.**
    Each open visit becomes a question that blocks what waited on it, or
    joins the gate already asking the same question. A visit nothing waits on
    becomes a conversation in your queue, unless it held a PR's merge, which a
    question on the anchor keeps holding. Framing, notes, waits and every
    reference to a visit move with it. Cost: for the few minutes until the migration has run and
    the board has been rebuilt, the board can miss an open visit or a new
    question, a ruled finding is not yet released, and a sitting live at
    cutover is ended and has to be engaged again.
11. **The build is four beads onto this branch, in order:** the writer and its
    callers, the readers, converse and the board, then the cutover. Cost: four
    PRs to review here instead of one.

## The platform this rides

Every fact below was read on 2026-10-19 against the installed gc 1.4.3 and bd
1.3.1, against Gas City's upstream source at 1e05ae624, and against its packs at
520e95cb2. The facts the sitting ruling rests on were read again on 2026-10-20
at the same commits, and checked at upstream 2aeead4e2, where some cited files
moved by a few lines and none of the cited behavior changed. The installed gc
is built from a local commit that upstream does not contain. Where a fact
matters, it was read at upstream, and the core orders it names are
byte-identical in both. Gas City paths are relative to the Gas City source tree
at 1e05ae624, and bd paths to bd's v1.3.1 source.

| Mechanism | What this design uses it for | Where it was read |
|---|---|---|
| `bd gate create --type=human --blocks <bead> --title --reason --await-id` | Files a question. It adds one `blocks` dependency from the bead it names onto the gate, so that bead waits. The reason is appended to the description, after a line naming that bead. No assignee, metadata or label can be set at create, and nothing dedups. No field names the blocked bead, so a `blocks` edge another bead adds onto the gate looks like the first. | bd `cmd/bd/gate.go` (flags 1282-1288, edge 352-368, description 411-437); `bd gate create --help` |
| `await_type` is written only when a bead is created, and `bd create` has no flag for it | Why every question is filed through `bd gate create`. `bd create -t gate` is accepted but leaves the await type empty, which declares nothing to a reader. `bd update --type` changes a type in either direction, leaves the await fields where they were, and no upstream test covers it, so no reader is built on re-typing a bead. | bd `internal/storage/issueops/update.go` 28 and `internal/storage/issueops/helpers.go` 152; `cmd/bd/create.go` 917-967; `cmd/bd/update.go` 251-252 and `internal/storage/issueops/aggregate.go` 125 |
| `bd dep add <a> <b> --type=tracks`, and `bd create --deps "tracks:<b>"` | A subject that does not wait tracks its question, unless it is a convoy, and a conversation task tracks what it is about. `tracks` is a well-known type that never blocks, cascades nothing and is outside the cycle check. The first bead tracks the second. | bd `internal/types/types.go` 1271, 1313-1320, 1335-1336; `internal/storage/issueops/blocked_state.go` 213-219; `cmd/bd/dep.go` 370, 410; `cmd/bd/create_deps.go` 145-153 |
| One dependency type per ordered pair | Why a subject that waits carries only its `blocks` edge onto its question. A second type on the same pair is refused until the first is removed with `bd dep remove`. | bd `internal/storage/issueops/dependencies.go` 263-284; `issueops/errors.go` 206-208 |
| `bd gate list <bead> --json` | Lists a bead's questions for the writer's dedup and for every reader. It returns the bead's outgoing dependencies of any type that are gates, `blocks` and `tracks` alike, with `await_type` and `await_id`. It lists every gate that is not closed unless `--all`, and at most 50 unless `--limit 0`. With no gates it prints `null`. | bd `cmd/bd/gate.go` 79-98 and `filterIssueGates` 129-144; `internal/storage/issueops/dependencies.go` 1318-1319; `cmd/bd/gate_proxied_server.go` 450-488; `cmd/bd/output.go` 68-87 |
| `bd dep list <bead> --direction=up --type tracks --json` | Lists the conversations that track a bead or a question. Each row carries the tracking bead's id, title, status, type and assignee. | bd `cmd/bd/dep.go` 917, 1011-1012, 1557-1558; `internal/storage/issueops/relations.go` 60-61, 106-130 |
| A `blocks` edge blocks whatever its blocker's type | An open task blocks exactly like a gate. Work a person owes is an ordinary bead the waiting bead blocks on, and re-typing a gate releases nothing. | bd `internal/storage/issueops/blocked_state.go` 213-219 |
| `bd gate resolve <id> --reason` | The answer. It closes the gate with that close reason and recomputes `is_blocked` for the beads it blocked. It skips the close checks, the assignee check among them, so anyone may answer. On a gate already closed it changes nothing, keeps the first reason and still reports `Gate resolved` with exit 0, so a resolver learns it lost a race only by reading the gate back. | bd `cmd/bd/gate.go` 559-574; `cmd/bd/gate_proxied_server.go` 409-446; `internal/storage/issueops/close.go` 339-384 |
| `bd close` refuses a blocked bead, a bead with open children, and a bead assigned to another actor, each without `--force`, and a close removes none of the bead's dependency rows | A question holds the close of what it blocks, and a `tracks` edge holds nothing. A bead a gate blocks closes only once the gate closes or the edge is removed with `bd dep remove` (section 11). A dismiss falls back to `--force` past the assignee check (section 7). | bd `internal/storage/issueops/close.go` 150-160, 203-205, 339-384; `cmd/bd/close_direct.go` 84 |
| A blocked parent's state cascades to its `parent-child` descendants, and through no other edge | Why an epic, or a convoy with open children, is blocked only when the filer names it, and why a convoy with none, such as an input convoy, can wait. | bd `internal/storage/issueops/blocked_state.go` 227-240; `docs/component-model.md`, I1's shape law |
| A convoy's members are every bead it tracks, whatever their type. `gc convoy land` refuses a convoy while a member is open, autoclose waits for every member, and gc-toolkit's graduation counts every tracked bead | Why a convoy that does not wait carries no edge onto its question (section 1). | Gas City `internal/convoy/membership.go` 151-164; `cmd/gc/cmd_convoy.go` 2160-2173, 2393-2417; gc-toolkit `assets/scripts/convoy-graduate.sh` 123-130 |
| `bd ready` excludes gates, and a plain `bd list` hides them (`--include-gates` or `--type gate` shows them) | Why no pool's demand reaches a question, and why the board reads questions by type. | bd `internal/storage/sqlbuild/ready.go` 16-22; `internal/workapi/list.go` 433-434 |
| `bd update --claim` is a compare-and-swap | The sitting's claim on its conversation task. It succeeds on an open bead whose assignee is empty, the claiming actor, or one of the store's claim pools. It sets `in_progress`, the assignee and a lease, and is idempotent for its holder. It refuses a bead another actor holds. | bd `internal/storage/issueops/claim.go` 91, 114-118, 147-148, 341-352 |
| Agent `work_query`, and its three-tier default | The default finds the conversation task assigned to the session, so converse needs no work query of its own. Its second tier, `bd ready --assignee`, finds the task open, and its first tier finds it in progress after a restart. Its third tier offers routed work and is closed to a manual session whose alias is not its template's name, so a sitting is offered nothing but its task. The current runtime takes no wake demand from a work query. | Gas City `internal/config/workquery.go` 528-536, 605-613, 780-793, 957, 972-977; `internal/config/config.go` 3626-3643; `cmd/gc/city_runtime.go` 3349-3352, 4625 |
| `gc hook --claim` claims an open bead already assigned to the session, of any type but `message`, and returns one it already holds in progress. In a manual session it claims under the session's alias, which is also the session's bd actor | The sitting's first step (section 6). | Gas City `cmd/gc/cmd_hook_claim.go` 797-910, 1267-1288; `cmd/gc/cmd_hook.go` 291-299, 460-473, 522, 540-547; `internal/session/lifecycle.go` 76-79 |
| Assigned work wakes the session whose identity it carries, and an unassigned, unrouted bead wakes nothing | Why a conversation in the operator's queue, assigned to `human`, which no session carries, starts no session. | Gas City `cmd/gc/build_desired_state.go` 1938-1950, 3215; `cmd/gc/assigned_work_scope.go` 382-431; `cmd/gc/compute_awake_set.go` 454-495 |
| Gas City's releases of a dead holder's claims. An agent's default on_death runs for pool instances only. Core's orphan-sweep resets an in-progress bead only when it can show the holder dead, and it counts a bead whose `gc.session_name` it cannot resolve as unverifiable and leaves it, which is every bead `gc hook --claim` claimed in a manual session. Both list without `--include-gates`, so neither sees a gate | Why a sitting's recovery runs through its alias, and why engage needs no reclaim (section 6). | Gas City `cmd/gc/cmd_start.go` 159-176; `internal/config/workquery.go` 1351-1378; `internal/bootstrap/packs/core/assets/scripts/orphan-sweep.sh` 89, 106, 277, 335, 345, 632-634; `cmd/gc/cmd_hook_claim.go` 2073-2075 |
| A manual session does not end when its work closes. It stays until it is closed or drained, and a wait hold or an idle-sleep setting only puts it to sleep. An attached session is woken even when drained, unless a wait hold is set. `gc session attach` wakes a dormant session, and `wake_mode = "resume"` resumes the session's own transcript by its session key. A closed session does not reserve its alias: a new session under it starts a fresh transcript and takes the in-progress work still assigned to the alias. `gc session close` releases no claim held under the alias. No closer the controller runs on its own ends a manual session because its work closed: the stale-session closers exempt one that has started its conversation, and the core reaper prunes one only once it has drained. `gc session list` leaves a closed session out, whatever state it is asked for | Why converse-reap stays, how a sitting resumes, and why a held conversation is found by its assignee rather than by its session (section 6). | Gas City `cmd/gc/compute_awake_set.go` 432-440, 583-594, 668-693; `internal/session/manager.go` 1264-1271, 1344-1362; `internal/session/names.go` 639-641; `cmd/gc/cmd_session.go` 1894-1897, 1946; `cmd/gc/city_runtime.go` 3915; `cmd/gc/session_reconciler.go` 1057-1060; `cmd/gc/session_beads.go` 3500; `internal/bootstrap/packs/core/assets/scripts/reaper.sh` 69, 1402-1404; a live `gc session list --state closed`, which returned no row on 2026-10-20, as `formulas/mol-witness-patrol.toml` 424 records |
| The pool execution backstop nudges, then drains, a pool session that holds in-progress work and is quiet for 90 seconds, with no attachment exemption | Why a sitting is not a pool session. | Gas City `cmd/gc/execution_backstop.go` 321-322, 405-421 |
| Core notify-on-human-gate-creation and renudge-stale-human-gates | Turned off in this city (section 5). Both act only on an open human gate, and mail its assignee, then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT` (default `human`). | Gas City `internal/bootstrap/packs/core/assets/scripts/notify-on-human-gate-creation.sh` 1-80, 173-181; the town's city.toml 304-311 |
| Core escalate.sh hook and its incident reminder | Prior art for the writer's quiet period. It is a mail hook for maintenance scripts, and it is not this pack's writer. | Gas City `internal/bootstrap/packs/core/assets/scripts/escalate.sh` 1-22; `docs/getting-started/troubleshooting.md` 877-905 |
| A city's order override can set an exec order's environment | The alternative section 5 rejects. | Gas City `internal/config/config.go` 2383-2385; `internal/orders/override.go` 162-166; `cmd/gc/order_store.go` 229-235 |
| bd stores the actor that creates a bead as its `created_by`. Gas City runs each exec order as the actor `order:<name>`, and `gc bd` runs bd in its caller's environment | The migration tells a visit gate-visit-sweep filed from every other visit (section 11). | bd `cmd/bd/create.go` 531 and `cmd/bd/main.go` 813-822; Gas City `cmd/gc/order_store.go` 197, and `cmd/gc/cmd_bd.go` 165-193 and 686-702 |

Two premises of the initiative's ruling (tk-xexv7bo, turn 3) did not hold when
they were re-verified, and the design is reshaped around both. Each is recorded
under [Gap records](#gap-records).

- **`gc.continuation_group` does not reach a gate.** The hook claim preassigns
  open beads that share both `gc.root_bead_id` and `gc.continuation_group`
  (Gas City `cmd/gc/cmd_hook_claim.go` 3362-3372). The reconciler's backstop
  covers only task beads under a graph.v2 root
  (`cmd/gc/build_desired_state.go` 6453-6466, its checks at 6598-6612 and
  6659-6664). A gate has no workflow root, so same-subject continuity comes from
  the conversation task, which names its bead (section 6).
- **Nothing native releases a gate a dead session claimed.** Core's orphan-sweep
  and an agent's default on_death release list without `--include-gates`, so
  their listings hide gates, and Gas City's dead-assignee release covers pool-routed
  work (`cmd/gc/pool_session_name.go` 196-404). bd frees an expired lease only
  when something runs `bd reclaim`, and nothing in Gas City does: the hook
  claim's `auto_reclaim_stale_claims` setting would, but it is not wired at
  this commit (`cmd/gc/cmd_hook.go` 550-560). A lease lasts five minutes,
  which no config or flag changes (bd `internal/storage/issueops/lease.go`
  19-42), and a held sitting is quiet for hours. The sitting ruling answers
  this by never claiming a gate: a sitting claims an ordinary task under its
  alias (section 6).

One premise of the sitting ruling (tk-4t0uev0) did not hold either. The ruling
read Gas City's on_death and orphan-sweep as releasing a dead sitting's task.
Both list tasks and miss gates, as the ruling found, but neither releases a
sitting's task. An agent's default on_death runs only for pool instances, keyed
by the instance's qualified name, and a sitting is a manual session. Core's
orphan-sweep counts a bead claimed through `gc hook --claim` in a manual session
as unverifiable and leaves it (see the platform section; the sweep was read, not
run). The ruling's conclusion holds on another fact. The task's assignee is the
sitting's alias, a closed session does not reserve its alias, and a new session
under it takes the in-progress task as its own. So engage's reclaim still
retires, and recovery runs through the alias (section 6).

One more upstream fact frames the design. No upstream pack asks a human through
`bd gate create`. The build pack's human-gate steps park the session with
`gc session wait --sleep` and mail the human once
(`gascity/assets/workflows/github-pr-review/human-gate-comment.md` in the packs),
and Gas Town asks in the live conversation or escalates by mail
(`gastown/agents/witness/prompt.template.md` 332-341). So nothing upstream
competes with this use of human gates, and nothing upstream fills the board's
role.

## 1. What a question is, and what a conversation is

A question and a conversation are two native objects. A question is a human
gate, the platform's bead for a wait only a person can end. A conversation is an
ordinary task that a converse session holds while the operator talks with it.
Each carries its meaning in native fields, so another pack reading the city sees
a gate something waits on and a task someone holds, and needs no knowledge of
gc-toolkit to read either.

### A question

A question is one native human gate:

```
gc bd gate create --type=human --blocks <waiter> --await-id <subject>:<key> \
  --title "<the question, at most 140 characters>" --reason "<the framing>"
```

When the waiter is another bead than the subject, the subject also tracks the
gate, unless the subject is a convoy (below):

```
gc bd dep add <subject> <gate> --type=tracks
```

**It blocks what waits for the answer.** The filer names that bead (section 2):
the work bead that declined, the anchor when the merge must wait, one member of
an epic. bd records the gate as a `blocks` dependency of the waiter. The waiter
leaves `bd ready` and the pool's offer until the gate closes, and `bd close`
refuses it while the gate is open. Three consequences follow, and the first
decision asks the operator to accept them.

- **Routed work waits.** A work bead that declines on a question leaves the
  pool's offer until the question is answered, and its re-sling waits on the
  same edge (section 4).
- **A question holds a PR's merge when it blocks the anchor.** gctk merge holds
  on any live `blocks` blocker of the anchor
  (`services/gctk/internal/cli/merge.go` 552-567), and finalize-gate keeps its
  clause on the same edge (section 4). The merge-path questions, a review's
  needs-you questions and a sitting's question about the merge block the
  anchor, so they hold it as an open visit does today. A question about the PR
  that blocks only a rework child holds the merge through that child, because
  an anchor carries a `blocks` edge onto each rework child it has. A
  conversation about the PR holds nothing (below).
- **An epic, or a convoy with open children, is blocked only when the filer
  names it.** A blocked epic, or an owned convoy whose members are
  `parent-child` children, cascades its blocked state to every descendant
  (I1's shape law, `docs/component-model.md`). bd cascades only through
  `parent-child` edges, and an epic and an owned convoy are the parents the
  pack files work under. So the writer never blocks an epic, or a convoy with
  an open `parent-child` child, unless the call names it as what waits
  (section 2). Any other convoy pauses nothing when it is blocked, and it waits
  as any subject does. An input convoy tracks its one work bead rather than
  parenting it, and the malformed-convoy refusals file on one (section 3). An
  integration convoy whose branch is graduating has closed its members, and it
  anchors the graduation PR, so the merge-path questions on that PR hold it as
  they hold any other. A filer that names an epic or a convoy with open
  children states that pausing the unstarted parts is the point. A question
  about one part blocks that part, and an epic tracks the question when it is
  the subject. Work already in flight is not stopped, because a blocker gates
  claims, not running sessions.

The doctrine that a conversation does not freeze its subject stays, in native
form: a conversation blocks nothing, and a question holds only what waits on it
(`docs/human-engagement.md` on main, "A conversation does not freeze its
subject; a merge hold is an opt-in"). What retires is the machinery that kept a
visit's own wait off its subject: converse-hold's demand filed on the visit, its
opt-in `--hold-merge`, and the cut-short sign-off that moved the demand onto the
anchor. A sitting that wants the merge to wait asks a question on the anchor
(section 7).

**Its subject** is the bead the question is about, named at the head of its await
id. The board shows the question on the subject's row. When the subject is the
waiter, the `blocks` edge is the subject's own edge onto the gate. When it is
not, the writer adds the subject's `tracks` edge, because `bd gate list
<subject>` reads only the edges that leave the subject, of any type. A convoy is
the exception. Gas City counts every bead a convoy tracks as one of its members,
so a tracked question would hold the convoy's landing, its autoclose and its
graduation, and would be listed among its work (see the platform section). A
convoy that does not wait carries no edge onto its question, and its questions
are found by their await id among the store's gates, which
`bd gate list --json --limit 0` returns when it is given no bead, the closed
ones too with `--all`. Questions on a convoy are rare, so the wider read costs
little. bd keeps one dependency type per ordered pair, so a subject carries one
of the two edges, never both. Other beads can wait on the same question through
`blocks` edges of their own, as a rework child waits on the question its bring-current conflict
filed on its anchor (section 4). bd records what a gate blocks only as those
edges, so the await id is what tells the subject from a waiter. A reader that
asks what a bead's questions are keeps the human gates whose await id names that
bead, as the writer's dedup, engage, the board's fold and the migration do. A
reader that asks whether a bead waits on a person counts every open human gate
the bead's own `blocks` edges reach, as finalize-gate, gctk merge, the liveness
classifier and Accept do (section 8).

**Its title** is the question as the board's NEEDS cell shows it, at most 140
characters, the cap gc-helm.sh takeaway already enforces. bd's default title is
`Gate: human`, so the writer always passes one.

**Its description** carries the framing: the filer's message, and the original
id when the writer redirected an ephemeral subject (section 2). A question the
liveness sweep raises names, in its message, the command that re-reads the
current state. That replaces the `visit.recheck` hook.

**Its await id** names the subject and the situation, as `<subject>:<key>`. The
key is the filer's `--key`. A sitting's own question uses the key
`conversation` (section 7). escalate.sh refuses a subject or a key outside
`[A-Za-z0-9._-]` (`assets/scripts/escalate.sh` 124, 133), so the colon splits the
two. bd stores the await id and returns it from `bd gate list`. bd's gate check
skips human gates (bd `cmd/bd/gate.go` 712-731), and core's two human-gate
orders read a gate's type, status, age and addressee, never its await id. So the
pack's meaning for a human gate's await id collides with nothing in the
platform. gc-helm.sh demand already names its gated bead in its await id
(`gc-demand:<gated>[:<topic>]`, gc-helm.sh 1442).

**Its assignee** is empty while the question is owed, or the one person who owes
the answer. No session claims a question: a sitting holds a conversation task
instead (below). Gas City's notify and renudge orders act on a human gate while
it is open, and mail its assignee, or the escalation recipient when it has none.
A claim would move the gate to in progress, which both skip, and nothing claims
a question, so in a city that keeps those orders on, a question stays loud until
it is answered, whether or not a sitting is discussing it. In this
city both orders are off, and the board is the reach (section 5). Nothing in the
pack asks a question of a named person today, and the writer gains no flag for
one. Work a person must do is not a question. It is an ordinary bead assigned to
that person, and the bead that waits for it carries a `blocks` edge onto it,
which bd honors whatever the blocker's type.

**Its answer** is its close reason, written by `bd gate resolve` (section 7).

**It carries no pack metadata.** Every fact the visit kept in a pack key is a
native field of the question or of the conversation:

| The visit carried | After |
|---|---|
| `task_kind=visit` | `issue_type=gate` with `await_type=human` for a question; an ordinary task for a conversation |
| `gc.routed_to=human`, the board's human partition | `await_type=human`, or a conversation assigned to `human` |
| a `tracks` edge to the subject and `gc.continuation_group=<subject>` | the question's await id, with the subject's `blocks` or `tracks` edge onto it, read with `bd gate list <subject>`; the conversation task's `tracks` edge |
| `escalation_key` | the key in the question's await id |
| the title `visit: <subject> — <headline>`, and `gc.takeaway` on a demand gate | the question's title, or the conversation's |
| `gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, `gc.hold_demand` | the gate itself |
| `gc.outcome`, `gc.outcome_reason`, `gc.ruling` | the question's close reason (section 7) |
| `pr_number`, `pr_url` and `anchor_bead`, stamped on PR-comment visits so the merge held | the question's `blocks` edge on the anchor |
| `visit.recheck` | a command in the question's description, or in the notes a migrated visit left (section 11) |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | arguments to the sign-off (section 7) |
| the visit's assignee, the sitting that held it | the conversation task's assignee |

Molecule steps stamp `gc.continuation_group` for Gas City's own preassignment
(`formulas/mol-polecat-work.toml` 55, `formulas/mol-review.toml` 145). That use
is not the visit's, and it stays.

### A conversation

A conversation is an ordinary task that tracks what it is about:

```
gc bd create -t task --title "<what the conversation is about>" \
  --description "<the seed>" --deps "tracks:<bead>" --assignee human
```

`--deps "tracks:<bead>"` makes the new task track the bead (see the platform
section). The bead is the one the operator engaged. When engage is given a bead,
the sitting serves every question on it. When engage is given one question, the
task tracks that gate.

- **It blocks nothing, and nothing waits on it.** An open conversation does not
  hold its bead's readiness, close or merge. When something must wait for what
  the operator decides, the sitting asks a question on that bead (section 7).
- **Its assignee says who holds it.** It is `human` while the conversation
  waits in the operator's queue, which is where a conversation the operator
  opens without engaging it sits. It is the sitting's alias while a sitting
  holds it: the session claims it, which sets `in_progress`, the assignee and
  a lease. The alias names the task's own id (section 6), so a held
  conversation is known by its assignee alone, even once its sitting's session
  has closed and left the session list. That alias is what a recovery resumes
  (section 6).
- **Its title** is what the conversation is about, and the board shows it where
  a question's title would be. **Its description** is the seed: the operator's
  concern, or the question engage started from.
- **It closes when the sitting ends,** answered or dismissed, and returns to the
  operator's queue when a sitting is cut short (section 7). What was said goes
  on the subject's notes, as today.

A conversation carries no pack metadata. A reader outside the pack sees a task,
held by a session or in a person's queue, that references a bead.

## 2. The one filing writer

**escalate.sh files every question.** It already has the most callers, and it
already resolves the subject's store. Its flags stay as they are: `--subject`,
`--key`, `--message` and `--retract`. `--pool` retires, because a gate is not
routed, and so do the routes that forward it: upstream-finding.sh's own `--pool`
(upstream-finding.sh 57, 411), and reconcile-rig-checkouts.sh's
`RECONCILE_ESCALATION_POOL` knob, which tries a pool before the board
(reconcile-rig-checkouts.sh 166-169, 184-195). `--blocks <bead>` joins them. It
names what waits when that is another bead than the subject.

It files in six steps:

1. **It resolves the subject's store** with escalation-rig.sh, unchanged. A gate
   must sit in its subject's store, because a `blocks` edge across stores holds
   nothing (I1, `docs/component-model.md`). A `--blocks` bead must sit in the
   same store, and the writer refuses one that does not.
2. **It redirects an ephemeral subject** (a wisp, or a subject proven to name no
   placeable bead) to the rig's standing triage subject, as today. The original
   id goes in the framing, so `escalation_raised_by` retires.
3. **It reads the subject's gates** with `bd gate list <subject> --all --limit 0
   --json`, or the store's gates with the same flags when the subject is a
   convoy that does not wait (section 1). A human gate with the same await id that is not closed means the
   situation is already asked, so the writer prints that gate's id and exits 0.
   When the call names a waiter the gate does not block yet, the writer first
   adds that waiter's `blocks` edge and reads it back. A gate the subject only
   waits on names another bead in its await id, so it never matches. This is the
   idempotency the initiative's ruling asks for. bd has none at create, so two writers racing
   in the same instant can both file. The board folds both, and the sitting
   answers both with one reason.
4. **It keeps the quiet period.** If the newest closed human gate with the same
   await id closed with a reason headed `moot:` or `benign:` less than
   `GC_ESCALATE_VERDICT_WINDOW` seconds ago (default 86400), it files nothing and
   says so. A caller whose question carries a wait passes 0, as today, because a
   wait needs an open gate to sit on.
5. **It settles what waits.** The waiter is the `--blocks` bead, else the
   subject. An epic, or a convoy with an open `parent-child` child, is never the
   waiter by default, because blocking one pauses every unstarted part of it
   (section 1). Without `--blocks`, the writer files nothing on one, says why,
   and exits 3, a code escalate.sh does not use today. The caller then names
   what waits, or opens a conversation instead (section 3). Any other convoy is
   an ordinary waiter.
6. **It files the gate** (section 1), blocking the waiter. When the waiter is
   another bead, it adds the subject's `tracks` edge, unless the subject is a
   convoy (section 1). It reads the gate and its edges back.

`--retract` withdraws the filer's own question. It resolves each human gate on
the subject with that await id that is not closed, with the reason
`moot: <message>`. It claims nothing, because no session claims a question. A
sitting may be discussing the question when the retract lands, and the retract
answers it anyway, because the situation it asked about is gone. The sitting
learns it at its sign-off, which reads each gate back (section 7). A retract
interrupted part way leaves gates the next retract for the situation finds and
resolves, and resolving a gate already closed changes nothing.

**One open question per subject and situation.** The initiative's ruling says
one open ask per subject, and the operator still sees exactly that: every question on a bead
folds into the bead's one board row, and one sitting answers all of them. In the
store, two situations on one bead stay two gates, such as two PR comments, or a
review question beside a merge failure. Keeping them apart lets each filer
withdraw its own question when its situation clears, and keeps the quiet period
per situation.

What becomes of escalate.sh's other behavior:

| Today | After |
|---|---|
| Dedup on `escalation_key` and `gc.continuation_group` (escalate.sh 393-461) | Step 3: the await id `<subject>:<key>`, among the gates `bd gate list <subject>` returns |
| The verdict window over closed visits' `gc.outcome` (463-531) | Step 4: the closed gate's reason |
| The `escalation.recurrences` tally on the closed visit | Retires. `escalation.recurrence_last` has no reader, and only the tally reads `recurrences`. |
| `--retract` leaves an engaged visit alone and closes the rest through visit-close.sh (257-337) | Resolves every open gate under the key |
| The ephemeral-subject triage bucket (536-605) | Kept. The bucket is a standing subject the gate blocks, and it is not visit machinery. |
| The route check and repoint through pool-route.sh | Retires |
| Its copy of the gate-visit block (383-650) | Replaced by steps 3 to 6 |

The quiet period is the one behavior the writer adds to native calls, and it has
upstream prior art. Core's own escalate.sh does not re-send an unchanged incident
for a day (`GC_ESCALATE_REMINDER_SECONDS`, default 86400). The pack's period
answers the same need, a detector that re-fires a condition a person already
looked at, and keys it on the person's verdict.

**The other minters fold into it:**

- **`gc-helm.sh demand`**, the pack's only human-gate minter (gc-helm.sh
  1460-1669), retires. park's plain gate is not a question (section 8). first-reaction-dispose.sh files its ruling and recommend
  question through escalate.sh with the key `first-reaction`, and the waits, prs
  and converse-settle skills call escalate.sh. A task only a named person can
  perform, which the waits skill teaches through `demand --assignee` and no
  caller passes, is an ordinary bead assigned to that person, which the waiting
  bead blocks on. converse-hold.sh and converse-signoff.sh, demand's other
  callers, retire or shrink (section 7).
- **`gc-helm.sh open`** files a conversation, not a question: an ordinary task in
  the operator's queue (section 1), with no session yet. Engage takes it when
  the operator engages its bead (section 6). The operator's intake, a sitting
  that opens a conversation on another bead, the waits skill and helm-svc's
  POST /helm/open all reach it that way.
- **The gate-visit block** in mol-validate-close and mol-feedback-distiller
  becomes an escalate.sh call with the keys `validate-close` and
  `distiller-contention`. Today both reuse an open keyless visit on the subject.
  With their own keys, their questions show beside the operator's conversation
  instead of disappearing into it.
- **mol-visit** retires. Nothing pours it.
- **gate-visit-sweep** retires. There is no visit left to make.

**converse-hold's PR-anchor case retires.** converse-hold.sh files its demand on
the visit when the subject is in `pre_open_gate`, `pull_request` or `merged`
(converse-hold.sh 210-213, 234-244), which kept the conversation's own wait off
the anchor. A conversation now holds nothing, so there is no wait to keep off.
A held sitting keeps its conversation, and a question it asks blocks only what
waits (section 7).

## 3. Every caller outside converse

The list was re-derived from main at 35cf7c70f. Every call keeps escalate.sh's
flags, except the `--pool` that upstream-finding.sh and
reconcile-rig-checkouts.sh forward. The column on the right is what changes
around the call.

| Caller | Its move |
|---|---|
| mol-polecat-work's decline arms: load-context's unreadable, parked and duplicate refusals; the blocked-work fallback; the unclear-requirements instruction; workspace-setup's malformed convoy, target guard, branch divergence and missing branch; the bring-current question through bring-current-audit.sh; submit's branch-shape, landing-target and hand-off refusals | The call is unchanged. The gate blocks the work bead, except in two arms. The malformed-convoy refusal files on the input convoy (`formulas/mol-polecat-work.toml` 430), which pauses nothing when blocked and so is its own waiter (section 1), and it cancels the run without a wait. The bring-current question is filed on the anchor (bring-current-audit.sh 339), so the merge waits too, and await-ruling.sh adds its wait as the work bead's own edge onto the gate (`formulas/mol-polecat-work.toml` 726, section 4). await-ruling.sh then releases the claim and arms the re-sling, and run-cancel.sh ends the run. The verdict window stays off where a wait follows. |
| `template-fragments/polecat-doctrine.template.md` (Escalation and the decline protocol) and `template-fragments/pool-worker-no-consent-ui.template.md` | The same three calls in the same order. The text says "the human gate escalate.sh files" where it said "the visit escalate.sh opens". A work bead that is an epic, or a convoy with open children, meets step 5's refusal, and the doctrine says to name the work bead with `--blocks`, because the work is what waits. Every polecat does what it does today. |
| mol-validate, mol-rig-demo, mol-refinery-patrol, mol-witness-patrol, mol-dog-shutdown-dance | Unchanged calls. The malformed-convoy refusals of mol-validate and mol-rig-demo file on the input convoy, as mol-polecat-work's does (`formulas/mol-validate.toml` 90, `formulas/mol-rig-demo.toml` 111). A refinery or witness patrol call whose subject is a graduating integration convoy blocks it as it blocks any other bead (section 1). mol-witness-patrol's check-refinery finds its open `witness-refinery-queue` questions with `bd gate list` and retracts them as today. |
| mol-deacon-patrol | It names escalate.sh in prose only. Its "becomes a visit" wording says the call files a question. |
| The deacon, refinery and witness prompts | Unchanged calls. The deacon prompt's stale "converse pool" default goes. |
| `template-fragments/visit-close.template.md`, which the deacon, mechanik, proactive, refinery and witness prompts include | Its `--retract` call is unchanged. The fragment is renamed (section 9). |
| pr-facts.sh, the merge-path families | Unchanged calls. Each question blocks the anchor, so it holds the merge as the visit did. pr-facts.sh stops stamping `pr_url`, `pr_number` and `anchor_bead` on the comment and unengaged-thread questions. `visit_for`, the dispose refresh, the merge-blocked-approval retire, the retire on a disposed anchor and the write-back's awaiting and resolved replies read the anchor's gates by await id. The dispose retract after a landed close (`retract_dispose_visits`) goes, both its call at pr-facts.sh 1779 and the full-pass sweep that retries it (1298-1335). bead-rehome.sh withdraws the retry's own question before the close (section 4), so a landed close leaves none open. |
| gctk merge (one-anchor-per-pr, seed-audit-merge-gate) and record-failure-cap.sh | Unchanged calls. gctk merge reads a human gate on the anchor as a person's hold (section 4). |
| gate-ensure.sh, branch-supersession.sh, reconcile-rig-checkouts.sh, rejection-repool.sh | Unchanged calls. branch-supersession.sh's lookup reads gates. reconcile-rig-checkouts.sh's pool knob, `RECONCILE_ESCALATION_POOL` or its prior name `RECONCILE_MAYOR_ADDR`, retires with `--pool`, and so does its pool attempt that falls back to the board call (reconcile-rig-checkouts.sh 166-169, 184-195). Nothing sets the knob, so its call stays the board call it makes today. |
| deferred-dispatch.sh | Unchanged call. Its sling-failed question blocks the armed bead, so the re-sling waits for the answer as well as for the cleared cap (deferred-dispatch.sh 1608-1614). On an epic, or a convoy with open children, nothing else waits on the answer, because the cap already holds the arm, so it opens a conversation on the bead instead. |
| liveness-sweep.sh, finding.sh | Unchanged calls. Their subjects are an anchor, a standing triage subject or the finding's anchor, none of them an epic, so each question blocks its subject. liveness-sweep.sh puts its recheck command in the message instead of stamping `visit.recheck`, and its disposition text names escalate.sh where it named `gc-helm.sh demand`. finding.sh records the gate's id (section 4). |
| upstream-finding.sh | Its own `--pool` option and the forwarding of it (upstream-finding.sh 57, 411) retire with escalate.sh's, and so do the cases in upstream-finding.test.sh that pin the forwarding. No caller passes the option, so every call is unchanged. Its question blocks its own send task, so the operator answers the question, sent or declined, before the task can close: bd refuses to close a bead an open gate blocks, where today the send task closes as the answer (`docs/outbound-sends.md`). |
| The gascity-keeper sub-pack's refinery fragment | Its call passes flags escalate.sh rejects, behind `\|\| true`. tk-vfgmu8k fixes it to escalate.sh's flags, and this design keeps those flags. |
| first-reaction-dispose.sh | escalate.sh with the key `first-reaction`, blocking the subject, so the subject waits for the operator as it does today. Its `--visit` option, which blocked the subject on a visit, retires. A first reaction on an epic, or a convoy with open children, which only the operator's own react reaches, finds nothing on it that waits for the answer, so it opens a conversation carrying its takeaway and reason instead (decision 2). |
| mol-validate-close, mol-feedback-distiller | escalate.sh with their own keys (section 2). mol-validate-close escalates on doubt, which an open child that is real work raises, so on an epic, or a convoy with open children, it opens a conversation instead of pausing that work. |
| gc-helm.sh engage and open, the operator's intake, helm-svc POST /helm/open | No escalate.sh call. They file and take conversations (sections 6 and 8). |
| The waits, prs and converse-settle skills | escalate.sh where they called `gc-helm.sh demand` (section 9). The waits skill's own escalate.sh call is unchanged. |

## 4. What an open or answered question means to other machinery

| Meaning today | Read by | After |
|---|---|---|
| **An open visit refuses its subject's finalization** | finalize-gate.sh `clause_no_open_visit`, run by gctk merge before approval and before the merge, and by bead-rehome.sh | The question holds natively: gctk merge holds on a live blocker, and `bd close` refuses a blocked bead. The clause stays as an explicit precondition, re-expressed as "no open human gate blocks this bead", because a close path that passes `--force` skips bd's refusal. A question the bead only tracks holds nothing, and neither does a conversation. `--except-key` keeps its meaning: the caller's own questions under that key, assigned to no person, do not hold the act they ask to retry. bd still refuses the close while they block the bead, so the retry withdraws them first (below). |
| **Any live bead carrying the PR's `pr_number` holds the merge**, which is how a PR-comment visit held its PR | gctk merge `inflightHolder` (merge.go 1509-1554) | No longer stamped on questions. The question blocks the anchor. The probe stays for its other holders. |
| **The merge's machine state** | gctk merge's blocker classification (merge.go 553-567, `stuckHolder` 1582-1592) | It records a pool-routed blocker as progressing, an unrouted one as "an unrouted blocker no automated actor will clear", and nothing for a blocker routed to `human`, which is how a demand gate reads today (merge.test.sh 1307-1309). A gate carries no route, so gctk merge reads a gate whose await type is `human` as that person's hold and records no machine state. Its bead reader decodes no issue type or await type today, so a gate without a route would read as unrouted (merge.go 1582-1592), and the reader learns the await type. |
| **An open visit sets the PR's needs-attention status** | gctk pr-status `anchorOpenVisit` (`services/gctk/internal/cli/prstatus.go` 107-192) and `services/gctk/prstatus/prstatus.go` 121-123 | An open human gate whose await id names the anchor. A conversation about the anchor does not set it. |
| **The proceed ruling:** await-ruling.sh blocks the work bead on the visit and arms its re-sling | `assets/scripts/await-ruling.sh` | The wait is a `blocks` edge from the work bead onto the gate. await-ruling.sh finds the gate by its await id on the subject, which is `--subject` as today, else the work bead. When the work bead is the waiter the writer filed for, the gate's own edge is the wait. When it is not, as for the bring-current question a rework child files on its anchor, await-ruling.sh adds the work bead's edge, because the child's `related` edge to its anchor holds nothing (`assets/scripts/bd-lib.sh` 195). Either way it reads the edge back before it releases the claim, clears the route and arms the re-sling, in today's order, so the re-sling cannot fire before the answer. It survives because a formula-slung bead needs the arm. Closing the gate makes the work bead ready, and only the arm re-slings it on its formula. |
| **Review release:** a needs-you finding is released only by a closed visit carrying `gc.ruling`, following `gc.folded_into` and `gc.superseded_by` | finding.sh close-answered, run by gate-ensure.sh; review-answer.sh; pr-facts.sh's review dismissal | finding.sh stamps the gate's id as `finding.gate`. A needs-you finding is ruled once that gate has closed with a reason headed `ruled:`, or once the finding records its ruling as `finding.ruling_bead`, which the migration writes for a finding whose visit was ruled before the cutover (section 11). Its release then waits, as today, until no fix unit on its lane and no ruling's rework child is live, and the close records the ruling's bead as `finding.ruling_bead`. It still follows `gc.superseded_by`. Questions do not fold (section 7), so the `gc.folded_into` hop retires. `finding.ruling_visit` becomes `finding.ruling_bead`, named like `source_ruling_bead` because it names a gate for a ruling given after the cutover and a visit for one given before. pr-facts.sh's review dismissal and review-answer.sh read it there. |
| **Liveness:** a subject covered by a live visit is conversing, and one named by `gc.demand_for` is held by design | liveness-classify.sh 113-149, liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh | A bead whose `blocks` edge reaches an open human gate is held by design. A bead tracked by a conversation that a live session holds, directly or through one of its questions, is conversing. The sweep's live-visit guards read the bead's gates and conversations. A conversation task is itself a named wait while what it tracks is open, through the classifier's existing `tracks` arm (liveness-classify.sh 155). The same arm reads a subject that tracks an open question as a named wait, because it reads every outgoing `tracks` edge to a live bead and the sweep's live set includes gates. |
| **Orphan disposal** | orphan-dispose.sh's visit arm; the witness patrol's recovery steps | The visit arm retires. The recovery reads a bead as orphaned when no live session carries its owner, and it skips a bead routed to `human` (mol-witness-patrol.toml 245-250, orphan-dispose.sh 433). A conversation is assigned, not routed, and no session carries either of its owners: `human`, which Gas City reserves from session aliases (Gas City `internal/session/names.go` 159-160), or the alias of a sitting whose session has closed. So both skips also drop a task assigned to `human` or to an alias that names the task's own id. A conversation whose session was closed then stays in progress under the sitting's alias until a session under that alias takes it back (section 6). salvage-scope-gate loses its visit arm with orphan-dispose.sh's, and its test keeps the two classifiers in step. It does not reach a question, because no session claims one. |
| **A ruling's rework child** | `source_ruling_bead` (rework-child.sh, gate-ensure.sh, duplicate-sweep.sh, liveness-sweep.sh, live-work.sh) | Readers unchanged. The value is the ruling sitting's conversation task from now on, so one sign-off's rework is found again whichever questions it answered. |
| **A PR comment's disposition** | `pr_comment_disposition=visit:<id>` (pr-facts.sh; doctor check-feedback-routing-owed) | `question:<id>`. pr-facts.sh reads the kind and the named bead's status (`conversation_fix_landed`, pr-facts.sh 186, and the write-back at 4332-4333). The migration rewrites every `visit:<id>` (section 11), naming the gate for a visit it migrated and the visit itself for one closed before the cutover, so the prefix names a question rather than a gate. |
| **Others** | bd-lib.sh's anchor children; bead-rehome.sh's outcome stamp on a visit it rehomes; pr-post.sh's recognition of the reminder's `gc:visit` marker, which pr-visit-comment.sh writes | The anchor children lose the visit. The stamp retires, because a gate is never rehomed, only its subject. pr-post.sh recognizes the reminder's new marker (section 7). |

**A retry withdraws its own question before it closes.** pr-facts.sh is the one
caller of `--except-key`, through bead-rehome.sh. It closes an anchor whose PR
was closed with a pre-recorded disposition, and on every attempt it names the
key under which it reports a refused close (pr-facts.sh 1758-1768). Today that
report is a visit, whose `tracks` edge blocks nothing, so the close goes through
once finalize-gate excepts it. The report is now a question that blocks the
anchor, and bd refuses an unforced close while it is open (bead-rehome.sh
553-563 closes unforced). So bead-rehome.sh closes in these steps:

1. **It reads what would hold the close.** finalize-gate runs with
   `--except-key` as today. bead-rehome.sh also reads the bead's live blockers
   and open children, which are what an unforced `bd close` refuses on. Anything
   other than the bead's own questions under that key holds the close, and so
   does one of those questions that a person is assigned. Then it resolves and
   closes nothing, and the bead stays open with its successor pointer recorded,
   as a held close leaves it today.
2. **It resolves each excepted question** with a reason that names the retry and
   carries no outcome word. The retry has not shown the premise gone yet, so the
   quiet period does not start. A sitting discussing one of them does not hold
   the close: the retry answers first, and the sitting learns it at its
   sign-off (section 7).
3. **It closes the bead**, unforced, as today.

Only a blocker or an open child that appeared after step 1 can refuse step 3.
The bead then stays open with its question withdrawn, and pr-facts.sh files its
report again under the same key, which nothing mutes. A pass that stops between
two steps leaves a state the next pass completes, because a question already
resolved stays resolved, and resolving it again changes nothing. Every unrelated
blocker still holds the close, because step 1 reads it.

The doctor checks:

- **check-visit-outcome-recorded retires.** A question's answer is its close
  reason, written by the close itself. A gate a person closes by hand with no
  headed reason fails safe both ways: its finding stays held, and the quiet
  period does not start.
- **check-hq-marooned-work** drops its visit exemption. Gates are already exempt
  as infrastructure. A conversation is assigned, to `human` in the queue or to
  its sitting's alias, and the check passes an assigned bead. One a person
  released with `gc bd release-if-current` is unassigned until it is bound
  again, and it tracks an open bead, so the check exempts a task that tracks a
  bead that is not closed, as the liveness classifier's `tracks` arm does.
- **check-wait-is-an-edge** keeps its terminal-wait exemption and keys it on the
  gate type. `terminal_wait_key = "gc.demand_for"` in `lifecycle/lifecycle.toml`
  `[holds]` becomes a type rule.
- **check-blocked-work-armed** keeps its rule. A visit's route no longer counts
  as a dispatch path, and a work bead blocked by a human gate needs its arm,
  which await-ruling.sh writes.
- **check-state-space** adds every retired key to `RETIRED_KEYS`, so a leftover
  on a live bead is reported.
- **check-until-resolved-owed** changes only its finding text.
- **check-feedback-routing-owed** reads only whether a disposition is present,
  so only its comments change.
- **check-armed-dispatch-owed** takes hold-lib.sh's demand-gate rule from the
  gate type.
- **check-routed-work-claimable** does not change. A conversation is assigned,
  never routed.

## 5. How a question reaches the operator

The operator reads the board, not mail. That is why the town's city.toml already
disables renudge-stale-human-gates (304-311). Core's notify order mails a human
gate's addressee only while the gate is open, and the addressee is its assignee,
then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT`, which defaults to
the `human` mailbox. A question is filed open and unassigned, so every question
mails that mailbox. notification-wisp-reap exists to close those notices.

**The board alone is the reach.** The town's city.toml adds an override that
disables notify-on-human-gate-creation beside the renudge override, and the
comment over both names the board as this city's reach for a human gate. The
override is a commit to the town repo, not to gc-toolkit. It lands before the
cutover, so the gates the migration files mail nobody.

**Re-asking is the board's ordering.** An open question stays on the board,
owed and ordered by how long it has been owed, until it is answered, its filer
withdraws it, or, for the question that put a recommendation to the operator,
Accept answers it (section 8). Nothing re-mails. No session claims a question,
so a question a sitting is discussing is still open and unassigned: in a city
that runs core's two orders, they keep asking until the answer lands, which is
the native reading of a debt a person still owes. In this city both are off.

**notification-wisp-reap keeps one pass.** Its gate-notice pass retires with the
notify order. Its second pass collapses repeated `ESCALATION:` mails that core's
maintenance escalations send. Those are not human gates, so that pass stays.

`docs/human-engagement.md` on main names the visit as this city's reach for a
human gate and the notify order's mail as a record nobody reads, in "How the
model rides the platform" and in "How a sitting ends: a demand bead and an
edge". Unit C rewrites both to name the board as the reach and both core orders
as off in this city. `docs/gascity/human-engagement.md` states what the two
orders do, which does not change.

The alternative was to keep the orders and give them an addressee someone reads.
The town can point the two orders at another recipient by setting
`GC_ESCALATION_RECIPIENT` in an order override's environment (see the platform
section). Any recipient is still a mailbox or a session, and the operator reads
neither. They have no session to nudge, and pointing the orders at an agent would
wake that agent on every question. The alternative was rejected.

## 6. The sitting, its claim and its recovery

**A sitting is a manual session of the converse agent the operator chose,
holding one conversation task.** It is a manual session because the pool
execution backstop drains a pool session that holds in-progress work and is
quiet for 90 seconds, with no attachment exemption, and a sitting is quiet
whenever the operator is reading or thinking (see the platform section). A
manual session has no such clock: its work closing does not end it, idleness
only sleeps it, and attaching wakes it.

**Engage** (gc-helm.sh engage, the tmux picker, and helm-svc's engage route)
takes these steps:

1. **It reads the bead's conversations:** the tasks that are not closed and
   track the bead or one of its open human gates (`bd dep list --direction=up
   --type tracks` on each), kept when the task is assigned to `human` or to an
   alias that names the task's own id (section 1). The session list says which
   of those sittings are live. A converse session is one whose template
   contains `converse`, as converse-reap reads it today (converse-reap.sh
   72-79). A closed session is not in the list (see the platform section), so a
   conversation whose sitting's session has closed is found by its assignee.
2. **A conversation held by a session in the list is a live sitting,** and
   engage attaches the operator to it. That is the dedup the ruling calls a
   convention: engage never starts a second sitting beside a live one.
3. **Otherwise engage takes a conversation** in the operator's queue, or one
   whose session has closed, or files a new one (section 1). A concern passed
   with `--reason`, `--template` or `--skill` seeds the new task, or joins the
   notes of the one engage takes.
4. **It starts the sitting:** `gc session new converse-<model> --alias <task>
   --no-attach`, as today with the visit's id. The `v-` fallback for an id the
   runtime refuses as an alias stays. Engage still starts the session before it
   binds the task, because the alias is the reservation, and a bind that loses
   its race closes the session it started (gc-helm.sh 4145-4150, 4295-4323). A
   session still in the list under that alias that no longer holds the task,
   as a sitting cut short leaves it (section 7), is closed first, because a
   session that is not closed keeps its alias.
5. **It binds the task to the session's alias** with a conditional update from
   the assignee step 1 read, `human`, empty or that alias, so a racing engage
   loses cleanly, and the task is known as held from the bind on. Then it
   attaches the operator, as today.

**The sitting claims its task with a plain `gc hook --claim`.** The default work
query finds the task assigned to the session, open through its second tier and
in progress through its first, and its routed tier is closed to a session whose
alias is not its template's name (see the platform section). So converse needs
no work query of its own, and pool-demand-wiring.test.sh keeps its rule that
converse agents define none, beside its `min_active_sessions = 0` and
no-`scale_check` rules. The claim sets `in_progress`, a lease and the session
stamps, under the session's alias. It is bd's compare-and-swap: it takes a task
that is unassigned or already the session's, and refuses one another session
holds, so the claim is what keeps a second sitting off one conversation.
converse-claim.sh retires.

**One live sitting per question is a convention, not a rule.** Engage attaches
rather than starting a second sitting, and nothing promotes two. Two engages on
two targets, a bead and one of its questions, can still leave two live sittings
that both serve one question. Nothing refuses that state. The board folds both
onto the bead's row, either sitting may answer, and the first resolve wins
(section 7). Engage warns when the question it starts on already has a live
sitting it is not attaching to.

**No sitting is demand-spawned.** No pool's demand reaches a question, because
`bd ready` excludes gates. A work query generates no wake demand, and a
conversation task is assigned, never routed. Assigned work wakes only the
session whose identity it carries, and a conversation in the operator's queue
is assigned to `human`, which no session carries. So a sitting starts only when
the operator engages.

**Recovery resumes the sitting first.** The task's assignee is the sitting's
alias, and that alias is what recovery resumes. A sitting whose session sleeps,
or whose runtime stopped, resumes when the operator attaches: attach wakes a
dormant session, and `wake_mode = "resume"` replays its transcript by the
session's own key. Its claim is idempotent for its holder, so nothing is
re-asked. A sitting whose session was closed cannot replay its transcript.
Engage starts a new session under the same alias, which a closed session does
not reserve, and the new session takes the in-progress task as its own through
the hook claim's first tier. The record carries over in the task's and the
subject's notes, and the transcript does not.

A session under any other alias is refused, because the claim is bd's
compare-and-swap. Nothing in Gas City releases a sitting's claim on its own:
on_death runs only for pool instances, orphan-sweep leaves a bead it cannot show
orphaned, and `gc session close` releases nothing held under the alias (see the
platform section). The pack's witness recovery skips the task too (section 4).
The alias is the way back in. A person who means to move a
task to another session releases it with `gc bd release-if-current`, which
reopens a bead only while the named holder still holds it (Gas City
`internal/beads/bdstore_conditional_release.go` 78-91). No question needs a
reclaim, because no session claims one, so engage's reclaim from a gone sitting
retires (gc-helm.sh 4057-4108).

**The put-back retires, and so does a shared session serving many subjects.** A
sitting's session is bound to one conversation task, which names its bead. The
put-back released the claims outside the sitting's group (converse-claim.sh
305-344). The work query offers the session only what is assigned to its own
identities, which is its task, so the put-back has nothing left to do.

**Same-subject continuity comes from the task, not from the continuation
group.** Gas City's continuation preassignment does not reach a gate (see the
platform section). It is not needed: the task names the bead, and the sitting
serves every question on it. A question filed on the bead while the sitting runs
is found at the sitting's next read of the bead's gates (converse-continue).

**converse-reap stays, keyed on conversation tasks.** Gas City does not end a
manual session when its work closes. It stays until it is closed or drained, and
no closer the controller runs on its own ends one because its work closed (see
the platform section). The nearest native one, the core reaper, prunes a session
only after it has drained. A sitting cannot drain itself at its sign-off: an
attached operator's pane would be destroyed, and the attached override would
wake the session straight back up. So converse-reap closes an unattached
converse session whose task has closed or is gone, and one whose task is back in
the operator's queue, as a sitting cut short leaves it (section 7), once the
session is older than the reap's own interval. The age keeps the reap off a
session engage has started and not yet bound. It reads the task's id from the
session's alias, and it strips the `v-` prefix, which today leaves those
sessions unreaped (converse-reap.sh 110-112). Its retirement trigger: Gas City
ends a manual session once its claimed work has closed and nobody is attached.
Unit C records it in `docs/warrants.md` with that trigger.

## 7. Hold, record and close

**The record** is unchanged doctrine: the sitting appends to the subject's
notes, and it writes the subject's headline with gc-helm.sh takeaway.

**A hold** is the operator owing an answer later. The sitting keeps its task
claimed, and the session stays, because the converse agents keep
`idle_timeout = "0"`. The hold appends to the subject's notes and writes what
the operator owes as the subject's headline. The questions the sitting serves
stay open and owed. When something must wait for the later answer and no open
question holds it, as when the merge must not land before the operator rules,
the sitting asks that question through escalate.sh with the key `conversation`,
blocking what waits. converse-hold.sh retires, and so do its demand, its
`gc.hold_demand` stamp, its `gc.gate_visit` stamp and `--hold-merge`. An
unanchored subject moves to `held` and back through lifecycle.sh, now from the
hold and settle skills, and only with a question that blocks it, because
check-wait-is-an-edge requires a held bead to carry a live edge.

A hold does not use `gc session wait --sleep`. That command sets a wait hold, and
the controller then drains the session (Gas City `cmd/gc/cmd_wait.go` 406-416),
which would destroy an attached operator's pane. While the hold is set, the
controller does not count an attachment as a reason to wake the session
(`cmd/gc/compute_awake_set.go` 591). Upstream uses it for an agent waiting on a
bead, and a sitting is a person and an agent in one pane.

**A restarted sitting** reads its task. Its `gc hook --claim` returns the task as
an existing assignment. The task's and the subject's notes say what was said and
what is owed, and with `wake_mode = "resume"` it also has its transcript. The
BEGAN restart forensics retire: converse-claim.sh's diagnosis (258-284) and the
prompt's yes, unknown, recheck and no rules inferred from `gc.hold_demand`
whether a hold had begun, and the claimed task now states it.

**The answer** is one call:

```
gc bd gate resolve <gate> --reason "<outcome>: <one line>"
```

The outcome is one of three words:

- `ruled`: the operator decided. It releases a needs-you finding.
- `moot`: the premise no longer holds. A filer's retract writes this. It starts
  the quiet period.
- `benign`: the premise holds, but it needs nobody. It starts the quiet period.

One bd call writes the close and its reason together. visit-close.sh stamped
`gc.outcome` and `gc.outcome_reason` before it closed, and read them back,
because those were two writes. That guard retires with the stamps. The premise
re-check's moot or benign close is this same call, so converse-close-out.sh
retires. The board's sittings card falls back to a closed sitting's reason for
its headline when the sitting left no takeaway
(`services/helm/internal/board/model.go` 658-669), and it reads the
conversation task's close reason there, where it read the visit's
`gc.outcome_reason`.

**The first answer wins.** bd resolves a gate already closed without changing it,
and reports success either way (see the platform section). So the sign-off reads
each gate back after its resolve. A close reason other than the one it wrote
means that another answer reached the question first. That can be a retract, an
Accept, another sitting, or a person at the command line. The sign-off reports
that answer to the operator instead of claiming its own. Each of those answers
is legal, nothing prevents it, and the one that loses is told.

**Leaving a question open** needs nothing, because the sitting never claimed it.
A sitting cut short writes its record, leaves its questions open and owed,
returns its task to the operator's queue, assigned to `human`, and drains, as a
cut-short sitting drains today. converse-reap closes the session once nobody is
attached, or the next engagement closes it first, and that engagement starts a
fresh session on the same conversation (section 6). The ruled-no
sign-off's second demand on the anchor retires, because a question that holds
the anchor already blocks it.

**Dismiss** ends a sitting. It closes the sitting's task with a reason that
names the dismissal, and it answers nothing. converse-reap then closes the
session once nobody is attached, as it closes a dismissed sitting's session
today, so the pane is never taken from under the operator who pressed the key.
The close falls back to `--force` when bd refuses an operator closing a task its
sitting holds, as dismiss does for a visit today (gc-helm.sh 2682-2687). Today
dismiss closes the visit, which for an escalation removes the question until its
detector re-files it. After this, the question stays on the board. That is the
cost the seventh decision names.

**There is no fold.** A sitting serves the questions of the bead its task
tracks. Two conversations on one bead are two tasks, and the board folds both
onto the bead's row. A duplicate question from a race is answered with the same
reason as its twin. Today a fold also moved `pr_number`, `pr_url` and
`anchor_bead` to the holder so the merge stayed held. A question holds the merge
through its own edge. converse-fold.sh, `visit-close.sh --into` and
`gc.folded_into` retire.

**converse-signoff.sh stays as one call**, rewritten. It is glue the epic's third
test allows, because the settle skill needs its steps in one order every time:

1. route a ruling's rework through converse-rework.sh, unchanged, with the
   conversation task as `source_ruling_bead`;
2. write the subject's headline;
3. resolve each question the ruling answers, read each back, and report any that
   another answer reached first;
4. release a `held` subject;
5. close the conversation task;
6. update the PR reminder.

`gc.ruling`, `gc.pr_visit_summary` and `gc.pr_visit_actions` retire. The ruling
is the resolve reason, and the summary and actions are passed to the reminder
directly.

**The PR reminder stays** (tk-wxrh1z): a comment on the subject's PR when a
sitting engages, edited in place when it ends. It is keyed by the conversation
task's id, and pr-visit-comment.sh is renamed pr-sitting-comment.sh.

## 8. The board's read path

**What it reads.** The board reads, per store, the human gates that are open,
and those closed inside the sittings window (default 24 hours), with a
gate-typed search, because a plain listing hides gates and a gate carries no
pack marker. The supervisor backend already unions a `type=gate` page into its
scan (`services/helm/internal/source/supervisor.go` 554-585). It reads the
conversations from their tasks: the tasks that are not closed, track a bead, and
are assigned to `human` or to an alias that names the task's own id (section 1).
The session list it already reads for owner liveness
(`services/helm/internal/source/gccli.go` 155-166) says which of those sittings
are live, and it leaves a closed session out. A question's subject is the bead its await id names (section 1).
Any other bead it blocks is a waiter, whose row lists the question among what it
waits on, as a bead blocked by a demand lists the demand today (`waitingSplit`,
`services/helm/internal/board/derive.go` 317). A conversation's bead is the bead
its task tracks, or the subject of the question it tracks. `visitFilter`,
`resolveVisitSubjects` and the visit-identity spelling retire.

**How they fold.** `wrapperTarget` (derive.go 2571-2595) treats a human gate as a
wrapper whose subject is the bead its await id names, and a conversation task as
a wrapper whose subject is its conversation's bead, so a question with waiters
and a conversation on a question both fold onto one row. `applyFold` keeps its
meanings:

- **Held:** a bead with an open question or an open conversation is held. The
  stranded arm of `severity` (derive.go 696) reads it as before.
- **Owed:** an open human gate makes its subject owed even while work on the
  subject is in flight, which is the visit's rule today. A demand alone yields to
  live work (derive.go 2666), but gate-visit-sweep gives every unassigned demand
  a visit, so a demand already follows the visit's rule in effect. One rule keeps
  that behavior. A conversation not in session makes its bead owed, as an open
  visit does: one in the operator's queue, or one whose sitting's session has
  closed. A conversation in session does not, because the operator is in it.
- **Owed since:** the earliest open gate's or owed conversation's
  `updated_at`, which is what the visit's clock was.
- **Needs:** the question's title, or `N× — a · b` over several. A held row with
  no open question shows its conversation's title, or reads "in conversation"
  while a sitting holds it, as a held row reads today (derive.go 976-983).

**In session:** a bead is in session when one of its conversations is held by a
session that is not closed, read against the session list the way the board
reads every owner's liveness (derive.go 79-83). Today `engagedVisit` reads a
visit's status, session and assignee, never whether the session lives
(derive.go 432-442), so a dead sitting still reads engaged. `classifyVisits` becomes the same classification
over conversations, read against liveness.

**Accept answers the recommendation's question and nothing else.** A
recommendation is `gc.recommended_formula` on the subject. Only
first-reaction-dispose.sh's recommend exit sets it (first-reaction-dispose.sh
822-841), and that exit files the question that puts it to the operator through
escalate.sh with the key `first-reaction` (section 2). So the recommendation's
gate is the subject's open human gate with the await id
`<subject>:first-reaction`, or both of them when a race filed two. The `--visit`
option, which held a recommendation on a question the caller filed, retires
(section 3), so no recommendation rides on another question. A subject whose
recommendation has no open gate under that await id offers Discuss only, because
nothing asks the operator to accept it. That is the case of a first reaction on
an epic, or a convoy with open children, which opens a conversation instead
(section 3).

Accept is offered while all three hold:

1. The subject carries `gc.recommended_formula`.
2. The recommendation's gate is open and unassigned. A gate assigned to a person
   is that person's to answer.
3. No other open human gate blocks the subject. That counts the subject's own
   questions under any other key, the questions it waits on that name another
   bead, and a gate assigned to a person.

A live sitting on the subject does not withhold Accept. gc-helm.sh accept warns
that a sitting is discussing the subject, and the sitting learns at its sign-off
that the recommendation's question was answered (section 7).

**Why Accept answers one gate.** Separate situations on one bead stay separate
gates (section 2), and each gate's close does something of its own. A `ruled:`
close releases a needs-you finding (section 4). Any close releases what waits on
the gate, so a rework child waiting on its anchor's bring-current question would
be re-slung without the decision it waits for. An Accept that resolved every gate
on the subject would spend one click as several answers the operator never gave.
Today's Accept already closes every waiting question on the subject. It resolves
every open, unassigned demand there (gc-helm.sh 2830-2849) and dismisses every
visit (3151-3156). A dismissed visit carries no `gc.ruling`, so a needs-you
finding whose visit Accept dismissed stays held with its question gone from the
board. Carried over to gates, the same sweep would close the finding's gate with
`ruled:` and release the finding on a ruling nobody gave.

**Why it waits for the others.** Every question blocks what waits on it, so the
subject's next step waits for each answer that blocks it (section 1). A formula
sling reads no `blocks` edge (`docs/gascity/routing-model.md` on main, "A
`blocks` dep between work beads does not hold a graph.v2 dispatch"). An Accept
that resolved only its own gate while another stayed open would start the work
before that question was answered. mol-polecat-work's load-context would cancel
such a run, and a formula with no such check would run past the question. So
Accept is offered only once the recommendation's question is the last question
blocking the subject.

While another question blocks the subject, the row offers Discuss, and the wire
field `accept_withheld` names each open question that holds Accept back. Discuss
engages the subject, and its sitting answers each of the subject's questions on
its own terms. A question the subject only waits on is answered in its own
bead's sitting. Once the others are answered or withdrawn, the row offers Accept
again if the recommendation's gate is still open and unassigned.

gc-helm.sh accept re-reads the three conditions live before it writes anything,
because a board row can be stale and a command can be copied. When one fails, it
refuses and writes nothing. When the third fails, the refusal names each open
question by id and title, with Discuss as the way forward. Otherwise it resolves
the recommendation's gate with `ruled: accepted <formula>`, reads back that no
open human gate blocks the subject, and slings. A question filed between the
read and the resolve shows in that read-back, and a sling can fail. Either way
Accept reopens the recommendation's gate, and nothing is dispatched. The resolve
comes before the sling, today's order (gc-helm.sh 3110-3138), so the run never
finds the recommendation's own gate open. The dispatch is recorded as today:
`gc.recommended_formula_dispatched` lands in the write that strips
`gc.recommended_formula`. A re-run that finds the marker skips the three
conditions, since the run that wrote it already answered the gate. It finishes
that record and never slings again. Accept no longer runs dismiss. A sitting on
the subject is the operator's to end.

**Ranking is unchanged.** `rankScore` (derive.go 734-741) and its inputs are
untouched. Every input a visit supplied, held and the owed clock among them, now
comes from a question or a conversation. A board test pins that a subject ranks
the same with a question as it did with a visit, and the same with a queued
conversation as with an unengaged conversation visit.

**The wire model.** In `services/helm/internal/board/model.go` and
`services/helm/web/src/contract.ts`, `held`, `accept_formula` and
`recommendation` keep their meaning, and `acceptable` reads Accept's three
conditions. `accept_withheld` is new. It is set on a row that meets Accept's
first two conditions and fails the third, and it names the questions that fail
it the way Needs names gates: the gate's title, or `N× — a · b` over several. It
is null on every other row. The web and text boards print it beside Discuss as
the reason Accept is not offered. `visit_state` is renamed `sitting_state`. The
web marker reads "in session" or "waiting" without the word visit. The sittings
card lists the conversations, from their tasks and the session list. gctk
pr-status's `OpenVisit` phase input reads an open human gate whose await id
names the anchor.

**The verbs** (gc-helm.sh, and helm-svc's POST routes that run it):

| Verb | After |
|---|---|
| engage, `--new-subject` | Section 6. `--new-subject` still creates the subject first (gc.origin=operator), then engages it. |
| open (POST /helm/open) | Files a conversation in the operator's queue without engaging it. `parseOpenStdout` keeps its sentences. `--allow-duplicate`, which engage passes today to file a second visit, retires. A bead has one open conversation in the queue, so a second concern on a bead whose conversation is open joins it: open appends the new reason and body to that task's notes. |
| accept (POST /helm/accept) | Resolves only the recommendation's gate, then slings, as above. While another question blocks the subject, it refuses, writes nothing and names each open question. It runs no dismiss. |
| dismiss (POST /helm/dismiss) | Ends the sitting (section 7). On a subject with no live sitting it does nothing and says so. |
| park, takeaway | Unchanged. park's plain gate has no await type and is not a question, and takeaway writes the subject's headline. |
| demand | Retires into escalate.sh (section 2). |

**The operator's hands do not change.** The tmux bindings keep their keys and
what they show:

- **prefix+b and prefix+B** (tmux-pick-helm.sh) engage a picked row.
- **prefix+a** (tmux-visit-prompt.sh) runs the operator's intake. gc-visit-open.sh
  is renamed operator-intake.sh, because it never filed a visit itself. Its
  fallback, which ran `gc-helm.sh open`, files a conversation in the queue. The
  prompt's match for "first reaction slung", which the intake no longer prints,
  is corrected with it.
- **prefix+A** (tmux-new-subject.sh) runs `engage --new-subject`.
- **prefix+X** (tmux-dismiss-sitting.sh) runs dismiss under the pane's session.

## 9. Skills, prompts and fragments

The sitting doctrine stays: premise re-check, prep, the hand-back's shape and the
record discipline. Only text that depends on the visit bead changes.

| File | What changes |
|---|---|
| `skills/converse-recheck-premise` | The premise is read from the conversation's seed and from each question's title and framing. A moot or benign verdict on a question is `gc bd gate resolve` with that headword, in place of converse-close-out.sh. A conversation whose premise has died is closed with the record written. |
| `skills/converse-prep` | It reads the conversation task with its notes, its bead's questions with theirs, and the subject's notes. A recheck command named in a question's framing, or in the notes a migrated visit left (section 11), is run, in place of the `visit.recheck` hook. |
| `skills/converse-hold` | The hold of section 7, in place of converse-hold.sh, the visit demand and `--hold-merge`. The dismiss line at the foot of every framing stays. |
| `skills/converse-settle` | converse-signoff.sh's new shape. The resolve replaces visit-close.sh and the guarded stamps, each resolve is read back, and the reminder update passes its text directly. A cross-store follow-up waits through escalate.sh. |
| `skills/converse-continue` | It re-reads its bead's questions and serves any new one, and it re-runs `gc hook --claim` after a restart. |
| `skills/waits` | One section on asking a person: escalate.sh files a human gate on what waits, and await-ruling.sh arms the re-sling. Work a person must perform is an ordinary bead assigned to them, which the waiting bead blocks on. The demand-gate, visit and gate-visit-sweep sections go. |
| `skills/prs` | A merge hold is a question on the anchor through escalate.sh. The not-needed successor names the gate. |
| `skills/work` | Accept and the intake are described on gates and conversations. Taking a recommendation in a sitting answers the recommendation's gate alone, as Accept does, and its sling waits until no other question blocks the bead (section 8). "Ask for a visit" becomes "ask the operator". |
| `skills/handoff` | A converse session closes or returns its conversation task before it drains. |
| `skills/learning-distill` | The contention question goes through escalate.sh. |
| `agents/_converse/prompt.template.md` | Its definitions of visit, subject, topic and demand become two: a question and a conversation. The claim block becomes `gc hook --claim`. The BEGAN rules, the fold and the finish arm go. The cut-short path returns the task to the queue. The ending says the thread ends when its conversation closes. |
| `agents/converse-{opus,fable,codex}/agent.toml` | Their header comments say the alias is the conversation task's id. They gain no work query. |
| `template-fragments/visit-close.template.md` | Renamed `ask-close.template.md`, and its `define` with it, so the include line in each prompt that includes it changes: the deacon, mechanik, proactive, refinery and witness prompts. A role never resolves another role's question, and withdraws its own with `--retract`. |
| `template-fragments/polecat-doctrine.template.md`, `template-fragments/pool-worker-no-consent-ui.template.md` | The decline wording of section 3, with the `--blocks` sentence for a work bead that is an epic, or a convoy with open children. The calls are unchanged. |

Every prompt change re-renders `generated/seed-audit/agents/*.md` in the same
commit, because gctk merge holds a merge whose renders are stale.

## 10. What retires, and the keys

**The retire list.** The initiative's list was confirmed on main, and the rest of
main's visit machinery was added to it:

| Piece | Fate |
|---|---|
| The visit bead kind, `task_kind=visit` | Retires. A conversation is an ordinary task. |
| gate-visit-sweep, its order and script | Retires. |
| converse-claim.sh, converse-fold.sh, converse-close-out.sh, converse-hold.sh | Retire. |
| visit-close.sh, the guarded close | Retires. |
| The BEGAN and `gc.hold_demand` restart forensics | Retire. |
| engage's reclaim from a gone sitting | Retires. No session claims a question, and a new session under a closed sitting's alias takes its task back (section 6). |
| mol-visit.toml, and every copy of the gate-visit block with gate-visit.test.sh | Retire. |
| visit-identity.sh | Retires, with its Go readings: gctk pr-status's `visitCovers` and the board's `resolveVisitSubjects`. gcbd's `DependsOn`, which only `visitCovers` calls, goes with the `gcbd_test.go` case that pins its edge spellings. |
| converse-recheck-hook.sh | Retires with `visit.recheck`. |
| orphan-dispose.sh's visit arm | Retires. |
| gc-helm.sh demand | Retires into escalate.sh, and a person's task becomes an ordinary assigned bead. |
| notification-wisp-reap | Its gate-notice pass retires, and its escalation pass stays. |
| converse-reap, its order and script | Stays, keyed on conversation tasks (section 6). |
| gc-visit-open.sh | Renamed operator-intake.sh, and its fallback files a conversation. |
| pr-visit-comment.sh | Renamed pr-sitting-comment.sh, and keyed by the conversation task. |
| `template-fragments/visit-close.template.md` | Renamed ask-close.template.md. |
| finalize-gate.sh's `clause_no_open_visit` | Re-expressed on gates (section 4). |

**The keys.** A key goes only when its last reader moves. Each retired key joins
`RETIRED_KEYS` in `doctor/check-state-space/run.sh`. The migration script reads
some of these keys on the beads it converts: `escalation_key`, `gc.demand_for`,
`gc.demand_topic`, `gc.ruling`, `gc.folded_into`, `visit.recheck`,
`finding.visit` and `finding.ruling_visit` (section 11). It removes
`gc.gate_visit` with a gate's other pack keys and reads nothing from it. It is
the last script to use them, so they stay registered until the follow-up that
deletes the script retires them (section 12).

| Key | Fate | The readers that move first |
|---|---|---|
| `gc.gate_visit` | Goes. The migration removes it without reading it, because the sweep stamps a demand with any visit open on the demand's subject, whatever that visit asks (section 11). | gate-visit-sweep.sh |
| `gc.hold_demand` | Goes. | converse-claim.sh, converse-signoff.sh |
| `gc.ruling` | Goes. The migration reads it once, on closed visits, to carry a ruling given before the cutover onto its finding (section 11). | finding.sh close-answered, which reads the close reason or `finding.ruling_bead` |
| `gc.folded_into` | Goes. The migration's walk reads it once, on closed visits (section 11). | finding.sh, visit-close.sh |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | Go. | pr-visit-comment.sh |
| `visit.recheck` | Goes. The migration reads it once, on open visits, to carry the re-check onto the gate (section 11). | converse-recheck-hook.sh. Its writer, liveness-sweep.sh, puts the command in the message. |
| `escalation_key` | Goes. The key in the await id carries it. | await-ruling.sh, branch-supersession.sh, pr-facts.sh, finding.sh, finalize-gate.sh `--except-key`, mol-witness-patrol's check-refinery, converse-hold.sh, converse-signoff.sh, converse-fold.sh, the formula copies |
| `escalation_raised_by` | Goes. | None. It is never read. |
| `escalation.recurrences`, `escalation.recurrence_last` | Go. | escalate.sh's tally |
| `triage.scope` | Stays. | The triage subject is not a visit. |
| `triage.last_seen` | Stays. Its registry text is corrected: it holds the in-scope ids, not a time. | |
| `triage.hold` | Stays. It has readers outside visits and no writer, and its retirement belongs to the liveness subsystem. | |
| `gc.outcome` and `gc.outcome_reason` on visits | Go. `gc.outcome` on molecule steps stays. | The board's sittings headline. Their writers stop with it: visit-close.sh, gc-helm.sh dismiss, and bead-rehome.sh on a visit it rehomes. |
| `finding.visit` | Renamed `finding.gate`. The migration converts it on every live finding (section 11). | finding.sh, review-answer.sh |
| `finding.ruling_visit` | Renamed `finding.ruling_bead`. The migration renames it on every finding that carries it (section 11). | pr-facts.sh's review dismissal, review-answer.sh |
| `source_ruling_bead` | Stays. Its value is the ruling sitting's conversation task from now on. | |
| `epic_ruling_evidence` | Stays. Its value is the gate's id from now on. | |
| `pr_number`, `pr_url`, `anchor_bead` as stamped on visits | No longer stamped on questions. The keys stay on anchors and their children. | gctk merge's `pr_number` probe, gctk pr-status's in-flight count |
| `gc.demand_for` | Goes. | gc-helm.sh, its writer; converse-claim.sh, converse-signoff.sh and gate-visit-sweep.sh; liveness-classify.sh, with liveness-sweep.sh and liveness-sweep-precheck.sh, which source it; liveness-recheck.sh; hold-lib.sh, with deferred-dispatch.sh through it; live-work.sh; pr-facts.sh; pre-open-rebase.sh; the board; check-blocked-work-armed; check-wait-is-an-edge's `terminal_wait_key` |
| `gc.demand_topic` (written and read, never registered) | Goes. | gc-helm.sh demand, converse-signoff.sh |
| `gc.routed_to=human` and `gc.takeaway` on gates | No longer stamped on gates. Both stay the subject-level markers they are, and a conversation in the queue is assigned to `human` rather than routed. | A reader that told a visit or a demand by its route, such as bead-context.sh, reads the gate's await type instead. |
| `gc.continuation_group` | Stays, for molecule steps. Its registry text, which describes the visit's fence, is rewritten. | |
| `pr_comment_disposition=visit:<id>` | Becomes `question:<id>`. The migration rewrites every one (section 11). | pr-facts.sh |

**The tests that retire, with what they cover:**

- gate-visit.test.sh: the filing invariants of the block's copies.
- gate-visit-sweep.test.sh: one visit per human gate, and the `gc.gate_visit` stamp.
- converse-claim.test.sh: the claim's verdicts, BEGAN, and the finish close.
- converse-hold.test.sh: the demand, `gc.hold_demand` and `--hold-merge`.
- converse-fold-scope.test.sh: the topic, the holder and the hold's premise gate.
- converse-close-out.test.sh: the moot and benign close through visit-close.sh.
- visit-close.test.sh: the outcome pair, the fold and its merge-hold key transfer.
- visit-identity.test.sh: coverage by the `tracks` edge with the stamp fallback.
- doctor/check-visit-outcome-recorded and its run.test.sh: a closed visit carries `gc.outcome`.
- liveness-recheck.test.sh's `visit.recheck` cases.
- notification-wisp-reap.test.sh's gate-notice cases.
- gc-helm.test.sh's demand and topic cases, and gc-helm-engage.test.sh's reclaim cases.

These tests are rewritten on gates and conversations rather than retired:
escalate.test.sh, which adds the `--blocks` waiter and the epic refusal,
await-ruling.test.sh, which adds the waiter's edge for a subject that is not the
work bead, decline-wiring.test.sh, visit-close-wiring.test.sh (as the ask-close
wiring), finding.test.sh, finalize-gate.test.sh, bead-rehome.test.sh, which adds
the retry's withdrawal before the close, first-reaction-dispose's tests, which
add the epic's conversation, upstream-finding.test.sh, whose `--pool` cases go,
reconcile-rig-checkouts.test.sh, whose unroutable-pool run goes,
review-answer.test.sh, merge.test.sh, the prstatus tests, pr-facts.test.sh,
gc-helm-engage.test.sh, gc-helm-accept.test.sh, gc-helm-open.test.sh,
gc-helm.test.sh's dismiss cases, converse-signoff.test.sh, which adds the
read-back that reports an earlier answer, converse-reap.test.sh, which adds the
`v-` alias, pr-visit-comment.test.sh and its wiring test,
liveness-classify.test.sh, liveness-sweep.test.sh, the
`*-escalation-wiring.test.sh` set, pool-demand-wiring.test.sh, the
check-hq-marooned-work test, and the board's Go and web tests.
formula-marker-coverage.test.sh loses the gate-visit markers.

## 11. Migrating the open visits

The cutover runs a one-shot script once per store: the city store, and every rig
store the pack runs on, suspended rigs included. It has a dry-run mode, and the
test suite runs it against a fixture store. It is not a standing sweep. The
cutover deletes it once every store reports no open visit (section 12).

The migration keeps every wait that holds today and adds none. A visit becomes a
question when something waits on it: a bead with a `blocks` or `until` edge onto
it, a demand it was filed for or that holds it, a finding or a routed PR comment
it answers, or, for an escalation, the subject that waits on its situation. A
visit on a PR anchor is a question too, because an open visit holds its anchor's
merge through finalize-gate today. A visit nothing waits on becomes a
conversation in the operator's queue.

For each open or in-progress visit, it does the following, in this order. Each
write is read back before the next, and the visit closes last, so a run that
stops part way leaves the visit open for the rerun to finish:

1. **It reads the subject and the key.** The subject is the visit's `tracks`
   target, else its `gc.continuation_group`. The key is its `escalation_key`,
   else `conversation`. A visit gate-visit-sweep filed is the exception,
   because the sweep files a visit only to put one demand to a person. While
   that demand is open, the visit's key is the demand's topic, its
   `gc.demand_topic` or else `conversation`, so step 3 takes the demand as the
   visit's question. The sweep's visit is one whose creator is the sweep's
   order (see the platform section) and whose framing names the demand
   (gate-visit-sweep.sh 156-160).
2. **A visit whose subject has closed still moves onto it**, because the
   question it asks can outlive its subject. A subject that no longer exists is
   replaced by the rig's standing triage subject, as escalate.sh does for an
   ephemeral subject, and the framing names the missing id.
3. **A demand gate that already asks the visit's question becomes the
   question.** A demand asks it when its `gc.demand_for` names the visit's
   subject or the visit itself, and its topic, `gc.demand_topic` or else
   `conversation`, is the visit's key. A `gc.gate_visit` that names the visit
   does not show that. The sweep stamps a demand with any visit already open on
   the demand's subject, whatever that visit asks (gate-visit-sweep.sh
   132-137), so a first reaction's demand can name the visit of a review
   question beside it. Taken as the review question, that demand would let
   Accept's `ruled: accepted` close release the review's finding. A demand on
   the subject that asks another question stays a question of its own, and the
   pass after the visits re-points it. When more than one demand asks the
   visit's question, the oldest is the visit's gate and the others share its
   await id. converse-hold leaves such a pair, its demand on the visit and the
   second one its `--hold-merge` files on the subject (converse-hold.sh
   286-308). The pair stays the duplicate a race can also leave, which the
   board folds and one ruling answers (section 2). A demand keeps blocking what
   it blocks, because its filer chose that, so the migration adds no wait on an
   epic or a convoy that is not there today.

   Step 3 takes each demand that asks the visit's question, and every demand
   filed on the visit itself, whatever it asks. A demand it takes is shaped
   here. Its subject is the visit's subject, and its await id is
   `<subject>:<topic>` from its own topic. Its title becomes its takeaway,
   through `bd update --title`. The await id is written last, after the title
   and any edge move below, through `bd update --await-id`, because it is what
   marks a gate as shaped. A gate is shaped when the part of its await id before
   the first colon is a bead it blocks, one that tracks it, or a convoy, which
   tracks no question (section 1). A demand's own
   await id, `gc-demand:<gated>[:<topic>]` (gc-helm.sh 1442), also names the
   bead it blocks, but its first part is `gc-demand`, so it is not shaped until
   the script rewrites it. Its pack keys stay until its visit has closed, so a
   rerun takes the same demands from the same keys and writes the same title and
   await id. The pass after the visits removes them.

   converse-hold's demands take the visit's `escalation_key` as their topic
   (converse-hold.sh 187-189), so a held visit and its demands ask one
   question. A held visit the sweep filed is the exception, because step 1
   gives it the topic of the demand it was filed for, so the hold stays a
   question of its own beside that demand. converse-hold files its first demand
   on the visit itself when the subject is a PR anchor (converse-hold.sh
   210-213, 234-244), so that demand blocks the visit, not the subject. bd
   refuses to close a blocked bead and keeps a closed bead's edges, so the edge
   of a demand filed on the visit moves before the visit can close, and before
   the demand's await id is written. The subject's `blocks` edge onto the
   demand is added and read back. Then the visit's edge onto it is removed with
   `bd dep remove`, and read back as gone. The anchor's merge waits on the
   moved demand, as it waited on the open visit through finalize-gate.
4. **Otherwise, when something waits on the visit, it files the question
   through escalate.sh**, with the quiet period off. The title is the visit's
   headline, the framing is the visit's description, and the await id is
   `<subject>:<key>`. The question blocks the subject, unless the subject is an
   epic, or a convoy with open children. Then it blocks the first bead that
   waited on the visit through a `blocks` edge, an epic tracks it and a convoy
   does not (section 1), and the waits step 5 moves cover the rest. escalate.sh's dedup merges a visit into a gate already asking the
   same situation, so nothing is asked twice. It returns that gate without the
   merged visit's framing (section 2), which step 6 carries. An escalation on an
   epic, or a convoy with open children, that nothing else waits on becomes a
   conversation, as below.
5. **It moves the waits.** Every bead that waits on the visit through a `blocks`
   edge gets the same edge onto the gate, and so does every bead whose `until`
   edge names the visit. Each is read back. That covers await-ruling.sh's work
   beads, first-reaction-dispose.sh's `--visit` holds,
   `gc-helm.sh takeaway --waiting-on` and edges placed by hand. Left on the
   visit alone, a `blocks` wait would release its work when step 8 closes the
   visit, before anyone has answered, and an `until` edge would dispose its bead
   as resolved. The old edges stay, and hold nothing once the visit is closed.
6. **It carries the visit's framing and notes onto the gate.** Both are
   appended to the gate's notes under a line naming the visit, unless the
   gate's notes already carry that line. The framing is the visit's
   description, and it is left out only when the gate's description already
   contains it, as the description of a gate step 4 filed for this visit does.
   Other gates lack it. A demand step 3 took has its own filer's framing, and
   converse-hold's has only demand's stock sentence (converse-hold.sh 243-244,
   gc-helm.sh 1491). A gate step 4's dedup returned has the framing of the
   visit it was filed for. Without the carry, the visit's question and
   evidence would leave with its close.

   A visit that carries a `visit.recheck` stamp needs one thing more. The
   stamp's one writer is liveness-sweep.sh. It stamps an absolute path to
   liveness-recheck.sh, which takes the visit's id, and the framing it writes
   tells the sitting to run that stamp (liveness-sweep.sh 467-471, 530 and 565).
   A gate carries no stamp, so step 6 also appends the command
   `liveness-recheck.sh <visit-id>` under the visit's line, with the script
   named rather than the stamp's path, whether or not the framing is left out.
   The command reads the census the closed visit keeps (liveness-recheck.sh
   95-105).
7. **A visit nothing waits on becomes a conversation.** The script files a task
   in the operator's queue that tracks the subject (section 1), titled with the
   visit's headline, with the visit's framing as its description and its notes
   carried under a line naming the visit. A rerun finds that task by the line
   and files no second one. This covers the operator's own conversation visits,
   the keyless visits mol-validate-close and mol-feedback-distiller filed, and
   an escalation on an epic, or a convoy with open children, that nothing else
   waits on.
8. **It closes the visit** with the reason `migrated: gate <id>` or
   `migrated: conversation <id>`, unforced. A visit bd still refuses, because
   something other than the moved demand blocks it, stays open and is reported.
   Nothing is forced.

**A human gate no visit asks is re-pointed too.** gate-visit-sweep files no
visit for a gate assigned to a person, a gate whose gated bead has closed, or a
gate stamped `gc.gate_visit=skip` (gate-visit-sweep.sh 17-28). A demand whose
question no open visit asks, such as a first reaction's beside a review
question, is taken by no visit in step 3. After the visits, the script shapes
each open human gate that is not yet shaped, the way step 3 does, with the await
id written last. Its subject is its `gc.demand_for`, else the one bead it
blocks, and its await id becomes `<subject>:<topic>`. A gate that blocks several
beads and names none of them is reported and left for a person. Last, the pass
removes the pack keys from every open human gate that is shaped:
`gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, and the route and takeaway
keys a demand carries. The pass leaves alone every gate that step 3 takes for a
visit still open, because the next run's step 3 finishes it from those keys. The
removal is a gate's last write, so a rerun after it finds the gate's title and
await id in place, and leaves them as they are.

**Every live reference to a visit is re-pointed, after the visits.** The records
in the table below name a visit and are read after the cutover. A finding can
name a visit that a fold or a re-home closed, so for a finding the script walks
from the named visit to the one that holds the question now, as finding.sh's
`ruled_visit` does today (finding.sh 1262-1281). The walk follows
`gc.folded_into`, `gc.superseded_by` and the `migrated:` close reason the
script writes, so it runs after the visit pass, and a rerun converts what an
earlier pass left. The walk is a copy inside the script, because when the script
runs the pack's finding.sh no longer reads visits. It is deleted with the
script. A disposition's reader reads only the status of the bead it names, so a
disposition follows only the `migrated:` reason.

| Reference | Read after the cutover by | The script writes |
|---|---|---|
| `finding.visit` on an open needs-you finding | finding.sh close-answered, which gate-ensure.sh runs every pass | Where the walk ends at a gate, through a visit the script migrated, `finding.gate`, naming that gate. Where it ends at a visit closed with `gc.ruling`, `finding.ruling_bead`, naming that visit, and the finding stays open. close-answered then releases it once no fix unit on its lane and no ruling's rework child is live, as it does today (finding.sh 1372-1396), so a ruled finding whose rework is still in flight stays held until the rework lands. Where it ends at a visit closed with no ruling, nothing has answered the finding, as today, and its notes name the visit. `finding.visit` is removed in every case. Where the walk ends at a gate, a `finding.reply` not yet posted that names the visit is rewritten to name the gate. |
| `finding.ruling_visit` on a closed finding | pr-facts.sh's review dismissal, which counts a needs-you finding as answered only when it records its ruling (pr-facts.sh 4745, 4794), and review-answer.sh | Renamed `finding.ruling_bead`, with its value kept, on every finding that carries it, so a review whose findings were released before the cutover is still dismissed. |
| `pr_comment_disposition=visit:<id>` on an anchor | pr-facts.sh, which reads the kind and the named bead's status (section 4) | `question:<id>`, naming the gate for a visit the script migrated, and the visit itself for one closed before the cutover. |

Until the script has run on a store, the new readers find none of them, so they
release nothing early. For those minutes a needs-you finding stays held and a
routed comment reads as unanswered.

A visit held by a live sitting is migrated like any other, and its question is
filed unassigned. Then the script closes that sitting's session, so the operator
re-engages the subject on the new path. Last, it closes the "Human gate awaiting
you" notices still open in the city store, which nothing else will close once
the notify order is off.

**Nothing lost, nothing doubled.** Every open visit ends as an open question that
asks its question, or as a conversation in the operator's queue, on its subject
or on the triage subject that stands in for a missing one. Each carries the
visit's framing and notes, and every bead that waited on the visit waits on its
question. A merge an open visit held stays held. A visit joins a gate only when
the two ask one question, so no answer to one question closes another. A rerun
finds each gate and each conversation again. escalate.sh's dedup finds a gate
step 4 filed by its await id on the subject, step 3 matches the same demands
from the pack keys they keep until their visit has closed, and step 7 finds its
task by the visit's line. The rerun adds only the edges, framing, notes and
references still missing, removes a visit's edge onto a moved demand if it is
still there, and closes only the visits left over. It reports, per store, the
visits it migrated into questions, those it merged into a gate already there,
those it turned into conversations, and any it could not close.

Its test stops a run after each write and reruns it, the write that removes a
gate's pack keys among them. After every rerun, each open visit has become one
question or one conversation with its framing, notes, waits and references
moved, each gate has the title and await id an uninterrupted run gives it, and
every visit but the ones the report names is closed. The fixture store holds the
states this section names:

- **A recommendation beside a review question.** An anchor carries a first
  reaction's demand under the topic `first-reaction`, with
  `gc.recommended_formula` on the anchor, and finding.sh's separate
  `review-needs-you.<finding>` visit, which the demand's `gc.gate_visit` names.
  The run leaves two gates, `<anchor>:first-reaction` and
  `<anchor>:review-needs-you.<finding>`, and the finding names the second. Then
  the board withholds Accept, a stale `gc-helm.sh accept <anchor>` refuses, and
  the review question and its finding stay open, as in unit C's acceptance case
  (section 12).
- **A sweep's visit for a recommendation.** The run closes the visit into the
  first reaction's demand and leaves the one gate `<anchor>:first-reaction`, so
  the board offers Accept.
- **A held visit with a substantial description and no notes**, whose demand's
  description is empty. The gate the visit closes into carries that description
  in its notes.
- **A liveness sweep's visit with its `visit.recheck` stamp and census.** The
  gate it becomes carries `liveness-recheck.sh <visit-id>` in its notes, and
  that command prints the census after the visit has closed.
- **An operator's conversation visit on a plain bead.** The run leaves one task
  in the operator's queue that tracks the bead with the visit's framing and
  notes, the board shows the bead owed with that task's title, and a rerun files
  no second task.
- **An operator's conversation visit on a PR anchor.** The run leaves a question
  `<anchor>:conversation` that blocks the anchor, so the merge stays held.
- **An escalation visit on an epic with open children and no waiter.** The run
  leaves a conversation in the queue, and no edge onto the epic, so the epic's
  children stay ready.

## 12. Cutover and the build

**The cutover order:**

1. **The town's city.toml turns off notify-on-human-gate-creation** (section 5),
   any time before step 3.
2. **The operator approves and merges this integration branch to main.** That is
   the one reviewed unit the initiative asks for.
3. **The rig checkout sync moves the pack to that main.** One pack serves every
   rig, so every rig switches at once. gate-visit-sweep's order disappears,
   escalate.sh files gates, and engage files conversations. The board and gctk
   are built binaries, so they switch when the helm-build and gctk-build orders
   next rebuild them, inside their five-minute cooldown. The cutover runs both
   orders by hand with `gc order run` as soon as the pack moves, so the old
   board's window is one build long. Until the new board is up, the old one
   reads visits and does not read the new gates as questions. Demand gates
   already on the board stay there, and the migration merges the visits the
   sweep made for them.
4. **The migration runs on every store, city first, once the new board is up.**
   Until it finishes, open visits are not on the board, a ruled finding and a
   routed comment that name a visit wait for it, and a sitting that was live at
   step 3 is running an old prompt against new scripts. The migration ends that
   sitting after carrying its visit over.
5. **The operator checks** that no store has an open visit and that the board
   shows every question and every queued conversation. A follow-up commit on
   main then deletes the migration script and its test, and retires the keys
   only the script still read (section 10). Unit D files that follow-up as a
   bead blocked on the cutover, so it is tracked from the start.

**How each rig cuts over.** Every rig's code switches together at step 3. Every
rig's store is migrated by its own run at step 4. A suspended rig's store is
migrated too, and its questions surface when the rig is resumed.

**The build is four beads onto integration/tk-iirrmiw, in this order.** Each is
its own PR on the branch, and each keeps the suite green. The convoy's
implementation child, tk-xgj6mg7, builds unit A. When it starts, it files units
B, C and D as members of this convoy, each blocked on the unit before it, as its
brief allows when the design calls for a split:

| Unit | What it carries |
|---|---|
| A. The writer and its callers | escalate.sh on gates, with the subject in the await id, `--blocks` and the refusal for an epic or a convoy with open children, the subject's `tracks` edge, and the retract by resolve. await-ruling.sh, with the waiter's edge. upstream-finding.sh's `--pool` and reconcile-rig-checkouts.sh's pool knob retired. first-reaction-dispose, mol-validate-close, deferred-dispatch.sh and mol-feedback-distiller on escalate.sh, with the conversation their epic case opens. mol-visit and the formula copies of the gate-visit block retired. The polecat doctrine and pool-worker fragments, the ask-close fragment, and the deacon, refinery and witness prompts. The registry entries of the keys the writer stops writing. |
| B. The readers | finalize-gate. gctk merge and pr-status. finding.sh and review-answer.sh. pr-facts.sh. branch-supersession.sh. The liveness scripts, with conversing read from conversations, hold-lib.sh, deferred-dispatch.sh, bead-context.sh and pre-open-rebase.sh. orphan-dispose.sh and the witness patrol. bead-rehome.sh, with the retry's withdrawal before the close. The doctor checks, `RETIRED_KEYS`, and the docs that teach these components (section 13). |
| C. Converse and the board | The conversation task, and gc-helm.sh engage, open, accept and dismiss on it. The converse prompt and agent headers, the five converse skills and the shared skills. Accept on the recommendation's gate alone, pinned by the acceptance case below. converse-signoff.sh rewritten, converse-reap re-keyed with its warrant in `docs/warrants.md`, and the converse scripts that retire. gc-helm.sh demand retired here, with its last callers: converse-hold.sh, converse-signoff.sh, and the waits, prs and converse-settle skills. pr-sitting-comment.sh and operator-intake.sh. The tmux scripts. The board's source, derive, model, wire contract with `accept_withheld`, web and text board. gate-visit-sweep's order and script. The human-engagement docs and the board's README. |
| D. The cutover | The migration script, with its copy of the visit walk, and its test, which stops a run after each write and holds section 11's fixtures. notification-wisp-reap's gate pass retired. The cutover runbook in its own spec. The remaining docs. |

The order follows the dependency. B's readers read what A's writer files, and C's
sittings answer what A files and B reads. A's callers open a conversation
through `gc-helm.sh open`, which files a visit until C turns it into a
conversation, so the branch is consistent at each unit's head. A, B and C each
leave the integration branch consistent for the suite, though not deployable
before D. The branch is never deployed until it graduates as a whole. Each of
the four PRs is about one subsystem. The single build is the alternative, at the
cost of one PR across every file this design names.

**Unit C's acceptance case: a recommendation beside a review question.** The
fixture is one anchor with two open questions. A first reaction's recommend exit
filed `<anchor>:first-reaction` and stamped `gc.recommended_formula`, and
finding.sh filed a needs-you finding's question as
`<anchor>:review-needs-you.<finding>` (finding.sh 918-924).
gc-helm-accept.test.sh and the board's derive tests pin each step:

1. **The board withholds Accept.** Both gates fold onto the anchor's row, and
   Needs prints both titles. `acceptable` is false, and `accept_withheld` names
   the review question.
2. **A stale Accept refuses.** `gc-helm.sh accept <anchor>` exits non-zero and
   names the review question. Both gates stay open, the finding stays held,
   `gc.recommended_formula` stays, and nothing is slung.
3. **Discuss answers the review question.** Engage files a conversation that
   tracks the anchor and starts its sitting. The sitting rules the review
   question, and that `ruled:` close is what releases the finding (section 4).
   The operator leaves the recommendation, so the sign-off leaves its gate open
   and closes the conversation.
4. **Accept answers the recommendation alone.** With the recommendation's gate
   the last one open and unassigned, the row offers Accept, and
   `accept_withheld` is null. Accept resolves that gate with
   `ruled: accepted <formula>`, slings the formula and records the dispatch. The
   review question's close reason is still the sitting's ruling.
5. **A late question stops the dispatch.** A question filed after Accept's live
   read and before its resolve shows in the read-back. Accept reopens the
   recommendation's gate, and nothing is slung.

A second fixture makes the other question one the anchor only waits on. Its
await id names another bead, and the anchor waits on it through a `blocks` edge
of its own. That question folds onto its own bead's row, and the anchor's row
lists it among what it waits on. Accept is withheld the same way, with
`acceptable` false and `accept_withheld` naming that question. A stale
`gc-helm.sh accept <anchor>` refuses, names that question and slings nothing.

A third fixture puts a live sitting on the anchor beside an open recommendation
and no other question. The row is in session and offers Accept. Accept warns
that a sitting is discussing the anchor and answers the recommendation, and the
sitting's sign-off then reports that the question was already answered.

## 13. Sequencing with the siblings

**tk-1tfzr71.1 (the foundation rule) and tk-1tfzr71.3 (the docs split) have
landed on main** since this branch was cut at 35cf7c70f, and so has
tk-1tfzr71.2, which added `docs/warrants.md`. Before a unit edits a page the
split moved, the integration branch takes main, so the units edit the pages
where main has them.

- The foundation rule's branch touched the mechanik prompt beside its
  visit-close include, which unit A changes. Both re-render
  `generated/seed-audit/agents/mechanik.md`, because the mechanik prompt includes
  the fragment. That is a generated-only conflict, settled by re-rendering.
- The docs split moved the Gas City facts into `docs/gascity/` and the pack's
  conversation model into `docs/human-engagement.md`. The pages it left that
  this design changes are `docs/human-engagement.md`,
  `docs/gascity/human-engagement.md`, `docs/gascity/agent-types.md` (its
  conversations section), `docs/gascity/packs.md` and `docs/gascity/README.md`
  (their visit mentions). Their section names and anchors are unchanged.
- `docs/warrants.md` records the warrants in force. converse-reap's entry is
  unit C's (section 6).

**The other docs that teach visits are this design's to update,** in the unit
whose behavior they describe:

- Unit B: `docs/finalize-gate.md`, `docs/refinery-merge-cadence.md`,
  `docs/state-machine.md`, `docs/authority-map.md`, and
  `docs/component-model.md` (its primitives, invariants and placement rows).
- Unit C: `docs/human-engagement.md`, the conversation facts in
  `docs/gascity/human-engagement.md`, `docs/architecture.md` (how humans
  engage), and `services/helm/README.md`.
- Unit D: `docs/gascity/agent-types.md`, `README.md`, and every other doc that
  mentions visits: `docs/quota-park-recovery.md`,
  `docs/lifecycle-composition.md`, `docs/gascity/packs.md`,
  `docs/outbound-sends.md`, `docs/steering.md`, `docs/install.md`,
  `docs/bead-store-resolution.md`, `docs/deferred-dispatch.md`,
  `docs/review-correctness.md`, `docs/gascity/README.md`,
  `docs/epic-stewardship.md`, `docs/review-demo.md`, `docs/product-goals.md`
  and `docs/feedback-learning.md`.

**The specs that record the visit design stay as written.** Among them are the
conversation-as-continuation-group design, the spine port, the converse claim
scoping, the hold model, the reap, the cutover and engage ordering, the gate
snippet, the guarded close, the finalize gate and the board's wrapper fold. They
are historical record by definition (`docs/file-structure.md`). The central docs
stop citing them as authority once they are rewritten, and this spec's
description names what it supersedes.

## Gap records

Each claim that Gas City cannot express something is dated and was re-verified
against upstream before it justified anything here. Each is answered by reshaping
the feature, not by a wrapper.

| Date | Claim | How it is answered |
|---|---|---|
| 2026-10-19 | `bd gate create` has no idempotency. | The writer reads `bd gate list` before it creates (section 2). |
| 2026-10-19 | A gate records what it blocks only as `blocks` edges. No field names the bead it was filed for, and a bead that waits on the question adds an edge just like the first. | The await id names the subject, as `<subject>:<key>`, and a subject that does not wait tracks the gate, unless it is a convoy (section 1). |
| 2026-10-19 | Continuation preassignment applies only within one workflow root, so it never reaches a gate. | A sitting holds one conversation task, which names its bead (section 6). |
| 2026-10-19 | Nothing native releases a gate claimed by a session that died. The listings of orphan-sweep and the on_death release hide gates, the dead-assignee release covers pool-routed work, and lease reclaim, which nothing in Gas City runs at this commit, would rob a live held sitting. | No session claims a gate (section 1). |
| 2026-10-20 | Nothing native releases a task a manual session claimed through `gc hook --claim` once the session is gone. on_death runs only for pool instances, orphan-sweep counts such a bead unverifiable, and `gc session close` releases nothing held under the alias. | A sitting's alias names its task's id, so engage finds the task by its assignee, and a new session under a closed session's alias takes the task back, so engage restarts a sitting under the same alias. The witness's recovery skips such a task. A person moves a task with `gc bd release-if-current` (sections 4 and 6). Nothing is kept for this gap. |
| 2026-10-19 | A manual session is not ended when its work closes, and a pool sitting would be drained by the execution backstop while the operator reads. | converse-reap, keyed on conversation tasks. Its trigger is in section 6, and its warrant goes in `docs/warrants.md`. |
| 2026-10-19 | Core's human-gate orders reach a person only by mail and nudge, and an override can only point them at another mailbox or session. This city's operator has no session and reads the board, not a mailbox. | The board is the reach, and core's two orders are off (section 5). |

This design adds no pack noun. Its conventions live in native fields: the
outcome word at the head of a gate's close reason, which finding release and the
quiet period read; the subject at the head of its await id, which tells a
question's subject from the beads that wait on it; and a sitting's alias, named
for its conversation task, which tells the board, engage and converse-reap which
task a sitting holds, from its session or, once that has closed, from the task's
assignee. The glue it keeps is the quiet period, which mirrors core escalate's
incident reminder, converse-signoff.sh's one ordered call, and converse-reap.
