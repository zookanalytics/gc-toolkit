---
name: Converse on native human gates — a gate belongs to the bead it blocks, a conversation is a task
description: The design for tk-0ur8r9p, the design child of convoy tk-iirrmiw under initiative tk-1tfzr71.4, rewritten to the ruling of sitting tk-4t0uev0, revised to the ruling of sitting tk-yf4nt2d, and held to the terms sitting tk-tdt71ue ruled. Its Terms section defines subject, human gate, conversation and sitting once, marks the words that retire, escalation among them, and every section uses only those terms. Any wait a person must clear before work moves, an answer, an approval or an action, becomes one native human gate about the bead it blocks. Any pack, formula or person may file one, human-gate.sh, which is escalate.sh renamed, is an optional helper that keeps one open gate per bead and key and the quiet period a call declares, and a gate is cleared by resolving it with the outcome at the head of its reason, never claimed by a session. A conversation becomes an ordinary task that tracks the one bead it is about, never a gate, held by a manual converse session named for it. The helm board reads both directly. The visit bead kind, the sweep that turned gates into visits, and the scripts that kept the two in step retire. It settles what a human gate blocks and carries, what a conversation is, the helper, its name and which of its conveniences stay, every caller and reader, how a gate reaches the operator, the sitting's claim, recovery and ending, the board's read path, the skills and prompts, the retire list and keys, the migration of open visits, the cutover, the build breakdown and the sequencing with the epic's other members. It also records the platform facts it was verified against, how Gas City and its packs use human gates today, and the premises of the initiative's ruling and of the first sitting ruling that did not hold, and it supersedes the specs that record the visit design. Read it to approve the design at its checkpoint or to build one of its units.
---

# Converse on native human gates: a gate belongs to the bead it blocks, a conversation is a task

## Terms

These four words name what this design builds, and each is defined here once.
Every section of this spec uses them only in these senses, and so does every
prompt, skill, doc and message the build writes.

- **Subject.** The bead a human gate or a conversation is about. A human gate's
  subject is the bead that waits on it through a `blocks` edge. A gate usually
  has one, and a gate that a second bead also waits on is about both. A
  conversation's subject is the one bead it tracks. Any bead can be a subject,
  such as a work bead, an epic or a PR's anchor. Its notes carry the durable
  outcome of every answer and conversation about it, so whoever works it next
  inherits what was decided.
- **Human gate.** Gas City's native bead for a wait a person must clear before
  work moves (`issue_type=gate`, `await_type=human`). The wait can be for an
  answer, an approval or an action. Its title and description say what the
  person must clear, and its await id carries the filer's situation key. It is
  unassigned while the operator owes it, or assigned to the one person who must
  clear it, and no session claims it. Any pack, formula or person may file one,
  and every reader treats it the same, whoever filed it. Resolving it clears
  it, and its resolve reason is the answer, headed `ruled:`, `moot:` or
  `benign:` (section 7).
- **Conversation.** An ordinary task that carries one dialogue about one
  subject. It is a fresh bead filed for that dialogue, never the subject itself,
  and it tracks its subject, which is always a bead and never a gate. Its
  description is the ask: the concern the operator brought, or the gate engage
  was pointed at. It blocks nothing, and nothing waits on it. It is assigned
  to `human` while it waits in the operator's queue, and to its sitting's alias
  while a sitting holds it. Two dialogues about one bead are two conversations.
- **Sitting.** The live hosting of one conversation by one converse session. A
  sitting is not a bead. Its session is a manual session whose alias names its
  conversation's id, and the conversation's assignee is that alias, which is
  how a sitting is found and resumed. A session never sits on a subject
  directly: engage files a fresh conversation, or adopts one the bead has in the
  operator's queue, and binds the session to it.

So a dialogue's ask lives on its conversation, an answer in the resolve reason
of the gate it clears, and the durable outcome on the subject's notes.

**Retired words.** These name today's objects, and the spec uses them only for
those objects, where it says what retires and how the cutover converts it.

- **Visit** is today's pack task (`task_kind=visit`) that is both a request to
  the operator and the place the conversation about it happens. After the
  cutover there is none: a wait a person must clear is a human gate, and a
  dialogue is a conversation.
- **Demand** is today's human gate that `gc-helm.sh demand` files, with pack
  keys and an await id that names the bead it blocks. The verb retires, and
  the migration makes each open one a plain human gate (section 11). Gas City's
  own demand is another word, the work a pool counts when it decides how many
  sessions to run, and the spec keeps that sense where it says a pool's
  demand, wake demand, a demand pass or demand-spawned.
- **Question** names no object. In prose it describes only a human gate that
  asks for an answer.
- **Escalation** names nothing. A gate the helper files is like any other human
  gate once it is filed, with the same type, the same reader rule and the same
  lifecycle, so the act is filing a human gate, whoever files it. The helper is
  renamed from escalate.sh to human-gate.sh (section 2). Identifiers that carry
  the word, such as `escalation_key`, are today's names or Gas City's, and the
  spec uses them only as names.

## What the operator approves here

Today, when the city needs you to answer, approve or act, it files a visit, a
task bead of the pack's own, and the visit is also where your conversation with
converse takes place. Some of those waits are filed first as native human
gates, a sweep files visits for them, and the rest of the pack reads the
visits. After this change anything you must clear before work moves is a native
human gate on the bead that waits, and your conversation with converse is an
ordinary task that a converse session holds while you talk. Nothing converts
one into the other, and the board reads both directly. Your sitting with
converse, the record it leaves, the board's ranking and the keys you press stay
as they are. The ruling
of sitting tk-4t0uev0 set this model, the ruling of sitting tk-yf4nt2d revised
it, the ruling of sitting tk-tdt71ue fixed its words in the Terms above, and
these decisions build it.

1. **A human gate is about the bead it blocks.** The filer files it on the bead
   that waits: the work bead that declined, the anchor when the merge must
   wait, one member of an epic. Its await id carries only the situation key,
   which bd calls the gate's condition identifier, and no other field or edge
   ties it to a bead. A bead's human gates are the open human gates its
   `blocks` edges reach, and every reader finds them that way. A gate carries
   no pack metadata, and the visit bead kind goes. Cost: a gate that a second
   bead also waits on is about both, and shows on both their rows. Routed work
   that waits leaves the pool's offer until the gate is cleared, and a gate
   that blocks a PR's anchor holds its merge.
2. **Every wait a person must clear before work moves is a human gate, and
   nothing else is.** The wait can be for an answer, an approval, or an action
   they must perform. What nothing waits on is not a gate. A conversation you
   open is only its task and holds nothing, work a person owes that nothing
   waits on is an ordinary bead assigned to them, and news is mail. Cost: an
   open conversation about a PR no longer holds its merge, as an open visit
   does today. A sitting that wants the merge to wait files a human gate on the
   anchor.
3. **human-gate.sh, today's escalate.sh, is an optional helper, not the one
   writer.** Any pack, formula or person may file a human gate directly with
   `bd gate create`, and every reader treats it the same. The helper keeps one
   open gate per bead and key, because it reads the bead's gates before it
   files. It also keeps the quiet period after you call a situation moot or
   benign, as an option each recurring detector declares at its own call site,
   off by default, so a new occurrence of an event is never muted by an answer
   to an earlier one. Of its other conveniences it keeps a filer's withdrawal
   of its own gate by key. It drops its own choice of store, and the copies two
   of its callers make, because Gas City already files a gate in the store of
   the bead it blocks. It drops the redirect that filed a patrol wisp's gate on
   the rig's standing triage bead, because that bead waits on nothing. It is
   renamed, because the Terms retire the word escalation, and every call names
   human-gate.sh. gc-helm.sh demand, mol-visit and every copy of the
   visit-filing block go. Cost: two situations on one bead are two gates. They
   always fold into one board row. One sitting serves both only by engage's
   default of attaching to a live sitting before it starts one, which is a
   convention, not a guarantee (section 6). A detector that should declare a
   window and does not asks again after your moot or benign answer, until its
   call site is fixed. A call that names a wisp, a session or a bead it could
   not read or place, such as the three patrol checks that name their own run,
   files a patrol finding instead, which reaches you through its first
   reaction. The old name stays as a hand-off to the new one until no run
   poured before the cutover can still call it (section 10).
4. **A human gate blocks like any other gate, and what it blocks is each
   caller's choice.** A gate on a bead with open children pauses every part of
   it that has not started, through Gas City's parent-child cascade, and the
   helper no longer refuses such a bead. Each caller that can land on a parent
   says at its call site whether it blocks the parent, blocks one member, or
   opens a conversation instead. Every caller but those that now file a patrol
   finding (the third decision) keeps its call under the helper's new name: the
   polecat decline stays human-gate.sh, then await-ruling.sh, then
   run-cancel.sh, and await-ruling.sh still makes the work bead wait on the
   gate, releases the claim and arms the re-sling. Of the helper's flags only
   `--pool` retires, and a caller that re-detects one condition every pass adds
   its quiet window. Cost: a part
   filed later under a bead that waits on a gate starts blocked until the gate
   is cleared. A first reaction on a bead with open children pauses its
   unstarted parts until you answer, while a closing check or a failed re-sling
   on one opens a conversation, without Accept. Each recurring detector's call
   site says whether it wants a window and why, and every reader that looked
   for a visit reads the bead's gates.
5. **No session claims a human gate.** A gate is unassigned while you owe it,
   or assigned to the one person who must clear it. Clearing it is one
   `bd gate resolve` whose reason leads with `ruled:`, `moot:` or `benign:`,
   and the record goes on the subject's notes. When two clear one gate, the
   first resolve wins and the other is told. Cost: Accept or a filer's
   withdrawal can clear a gate while a sitting discusses it, and the sitting
   learns it at its sign-off.
6. **A sitting runs in a manual converse session that holds one
   conversation.** Engage works on a bead: pointed at a gate, it takes the bead
   the gate blocks, because a conversation always tracks a bead, never a gate.
   A concern you bring to engage opens a fresh conversation, even when the bead
   has one, because a distinct concern is a distinct dialogue. Without one, engage
   attaches you to a live sitting on the bead, or adopts a conversation the
   bead has in your queue, or files one. It starts a session named for the
   conversation, binds the conversation to that session and attaches you. Two
   things keep a second sitting off one conversation: only one open session
   can hold the name, and the bind lands only while the conversation's holder
   is still the one engage read. A second live sitting on one bead or one gate
   is warned about, never refused. A sitting handed off goes back to your
   queue, assigned to you, through the same guarded update. Recovery resumes
   the sitting first: attaching wakes it and replays its transcript, and a
   sitting whose session was closed comes back as a new session under the same
   name, which takes its conversation back. converse-claim, the put-back, the
   fold, the restart forensics and engage's reclaim go, and converse needs no
   work query. Cost: a gate discussed in a sitting is two beads, the gate and
   the conversation. A sitting whose session was closed comes back with its
   record, not its transcript. converse-reap stays, because Gas City does not
   end a manual session when its work closes.
7. **A sitting ends by answering, holding or dismissing.** A hold keeps the
   conversation and the session. Dismiss closes the conversation and answers
   nothing. Cost: dismissing a sitting no longer takes a human gate off the
   board. The gate stays until it is answered or its filer withdraws it.
8. **The board is how a human gate reaches you.** Core's
   notify-on-human-gate-creation and renudge-stale-human-gates are Gas City's
   native way a human gate reaches a person. Both mail a mailbox you do not
   read, so this city opts out of them: the town's city.toml already turns off
   the re-ask order, and it gains an override that turns off the notify order.
   Cost: a town-repo commit. No mail or nudge announces a gate, which is
   today's behavior.
9. **The board reads gates and conversations directly and ranks them as
   today.** A gate shows on the row of each bead it blocks, and a conversation
   on the bead it tracks. A row is in session while a live sitting holds
   its conversation. A first reaction that needs you files a human gate on its
   bead under the key `first-reaction`. Its title and framing state the
   recommendation, and its edge says what it holds, so the beads alone say
   which gate carries the recommendation and what it blocks. Accept clears
   only that gate, and it dispatches only when that gate records Accept's own
   answer, so an answer a sitting gave first stands. While another human gate
   still blocks the bead, the row offers Discuss and names that gate. Cost:
   the board gains a gate read and a conversation read that no test covers
   today. A recommendation beside another open gate waits until that gate is
   cleared, where today's Accept closed every visit and demand waiting on the
   bead with one click.
10. **Cutover is one migration run per store, right after the pack update.**
    Each open visit becomes a human gate on what waited on it, or joins the
    gate already open for the same situation. The gate of a visit escalate.sh
    filed also blocks the bead that visit is about, as every gate the helper
    files after the cutover does, unless that bead has open children, where
    the migration opens a conversation instead of pausing them. A visit
    nothing waits on becomes a conversation in your queue, unless it held a
    PR's merge, which a gate on the anchor keeps holding. Framing, notes, waits
    and every reference to a visit move with it. Cost: the bead such a visit is
    about leaves the pool's offer at the cutover, and its close waits for your
    answer, where today such a visit holds only an anchor's merge.
    For the few minutes until the migration has run and the board has been
    rebuilt, the board can miss an open visit or a new gate, a ruled finding
    is not yet released, and a sitting live at cutover is ended and has to be
    engaged again.
11. **The build is four beads onto this branch, in order:** the helper and its
    callers, the readers, converse and the board, then the cutover. Cost: four
    PRs to review here instead of one.

## The platform this rides

The facts below were read against the installed gc 1.4.3 and bd 1.3.1, against
Gas City's upstream source at 1e05ae624, and against its packs at 520e95cb2,
most of them on 2026-10-19. The facts the first sitting ruling rests on were
read again on 2026-10-20 at the same commits, and checked at upstream 2aeead4e2,
where some cited files moved by a few lines and none of the cited behavior
changed. The facts the second joint review asked for were first read on
2026-10-20 at the same commits. In bd they are the reopen, the cascade's reach
and the children listing, the `until` edge, and the conditional update with the
lease it drops. In Gas City they are the alias reservation, release-if-current,
a session's origin and the session capacity defaults, which hold at 2aeead4e2
too. The facts the second sitting ruling (tk-yf4nt2d) rests on were read on
2026-10-21. In bd they are the `blocks` listing the one reader rule uses and the
await id's own definition. In Gas City they are how `gc bd` picks a store,
core's two human-gate orders and how a formula cooks a gate, read at
1e05ae624. Their code is byte-identical at 2aeead4e2, where
`docs/reference/specs/formula-spec-v2.md` gained seven lines above the lines
cited here. The cited behavior is unchanged at upstream b941bd330. The facts the
helper's rename rests on, how a step's text is poured into its bead and where
core's maintenance scripts look for core's escalate.sh hook, were read on
2026-10-21 at 1e05ae624, and their code is the same at 2aeead4e2 and
b941bd330. The facts the migration's release of a held visit rests on were read
on 2026-10-22: bd's assignee check at a close, and in Gas City the identities
`gc session close` releases work under and what release-if-current prints, which
behave the same at b941bd330. How the upstream packs ask a person was read at
their main, 820c7ca0d5. The gc-toolkit
facts were read at 35cf7c70f, and a doc read on main instead, because it
landed there after 35cf7c70f, is cited as main's. The installed gc is
built from a local commit that upstream does not contain. Where a fact matters,
it was read at upstream, and the core orders it names are byte-identical in
both. Gas City paths are relative to the Gas City source tree at 1e05ae624, and
bd paths to bd's v1.3.1 source.

| Mechanism | What this design uses it for | Where it was read |
|---|---|---|
| `bd gate create --type=human --blocks <bead> --title --reason --await-id` | Files a human gate. It adds one `blocks` dependency from the bead it names onto the gate, so that bead waits. The reason is appended to the description, after a line naming that bead. No assignee, metadata or label can be set at create, and nothing dedups. No structured field names the blocked bead. Only that first line does, for the bead the gate was filed on, and nothing updates it. A `blocks` edge another bead adds onto the gate is the same as the first, so the gate is about every bead it blocks. bd calls the await id a condition identifier, the `gh:pr` gate's PR number or the `gh:run` gate's run id, so a human gate's await id is free for the filer's situation key. On a bead that is not in the store it runs against, the create fails and files nothing. | bd `cmd/bd/gate.go` (flags 1282-1288, missing bead 340-343, edge 352-368, description 411-437); `internal/types/types.go` 165-166; `bd gate create --help` |
| `await_type` is written only when a bead is created, and `bd create` has no flag for it | Why every human gate is filed through `bd gate create`. `bd create -t gate` is accepted but leaves the await type empty, which declares nothing to a reader, as park's gate does by design (section 8). `bd update --type` changes a type in either direction, leaves the await fields where they were, and no upstream test covers it, so no reader is built on re-typing a bead. | bd `internal/storage/issueops/update.go` 28 and `internal/storage/issueops/helpers.go` 152; `cmd/bd/create.go` 917-967 and `internal/types/types.go` 745-748, 767-770; `cmd/bd/update.go` 251-252 and `internal/storage/issueops/aggregate.go` 125 |
| `bd dep add <a> <b> --type=tracks`, and `bd create --deps "tracks:<b>"` | A conversation tracks the one bead it is about, never a gate. That edge says only what the conversation concerns: no reader finds a bead's gates through a `tracks` edge, because a gate is reached through `blocks` edges alone (section 1). `tracks` is a well-known type that never blocks, cascades nothing and is outside the cycle check. The first bead tracks the second. | bd `internal/types/types.go` 1271, 1313-1320, 1335-1336; `internal/storage/issueops/blocked_state.go` 213-219; the cycle check, `internal/storage/issueops/dependencies.go` 445-446 and `internal/types/types.go` 1389-1395; `cmd/bd/dep.go` 370, 410; `cmd/bd/create_deps.go` 145-153 |
| One dependency type per ordered pair | Why the migration does not block a subject whose own edge onto its visit is `until`: the subject cannot carry both edges onto the gate, and its `until` edge says the answer resolves it (section 11). A second type on the same pair is refused until the first is removed with `bd dep remove`. | bd `internal/storage/issueops/dependencies.go` 263-284; `issueops/errors.go` 206-208 |
| `bd gate list --json`, with or without a bead | Given no bead, it lists the store's gates, which the migration reads for the human gates no visit covers and check-refinery reads for its own (sections 3 and 11). Given a bead, it returns the bead's outgoing dependencies of any type that are gates, without the type of the edge that reaches each, so it is not the one reader rule's read (next row). It lists every gate that is not closed unless `--all`, and at most 50 unless `--limit 0`. With no gates it prints `null`, but the no-bead form can print `[]` through a proxied server, so a reader takes either as none. | bd `cmd/bd/gate.go` 79-121 and `filterIssueGates` 129-144; `internal/storage/domain/db/issue_search.go` 70 and 568; `internal/storage/issueops/dependencies.go` 1318-1319; `cmd/bd/gate_proxied_server.go` 450-488; `cmd/bd/output.go` 68-87 |
| `bd dep list <bead> --type blocks --json`, `bd dep list <gate> --direction=up --type blocks --json`, and `bd dep list <bead> --direction=up --type tracks --json` | The first is the one reader rule's read. It lists what the bead depends on through `blocks` edges, open and closed alike, and each row carries the far bead's fields, `issue_type`, `status`, `await_type`, `await_id`, `assignee` and `title` among them, with the edge's `dependency_type`. A field whose value is empty is left out of the row, so an unassigned gate has no `assignee` key. A reader keeps the rows that are human gates (section 1). The second lists the beads that wait on a gate through `blocks` edges, open and closed alike, which is how a reader that starts from a gate learns what it blocks (sections 3, 6 and 8). The third lists the conversations that track a bead. Each prints an empty array when nothing matches. | bd `cmd/bd/dep.go` 917, 1010-1016, 1048-1052, 1557-1558; `issueops/relations.go` 23; `internal/types/types.go` 34-44, 165-166 and 1133-1136; `internal/storage/issueops/relations.go` 52-68, 106-130 |
| A `blocks` edge blocks whatever its blocker's type | What the one reader rule rests on. An open blocker of any type holds a bead the same way, so only a gate's `await_type` says that a person must clear the wait, and a reader keeps the human gates among a bead's `blocks` blockers. Re-typing a gate releases nothing. | bd `internal/storage/issueops/blocked_state.go` 213-219 |
| `bd gate resolve <id> --reason` | Clearing a human gate. It closes the gate with that close reason and recomputes `is_blocked` for the beads it blocked. It skips the close checks, the assignee check among them, so anyone may clear it. On a gate already closed it changes nothing, keeps the first reason and still reports `Gate resolved` with exit 0, so a resolver learns it lost a race only by reading the gate back. | bd `cmd/bd/gate.go` 559-574; `cmd/bd/gate_proxied_server.go` 409-446; `internal/storage/issueops/close.go` 339-384 |
| `bd reopen <id> --reason` reopens a closed bead of any type, a gate included. It sets `open`, clears `closed_at` and the close reason, drops the lease, records the reason as a comment, and recomputes `is_blocked` for the beads that wait on the bead, so what a reopened gate blocked is blocked again. On a bead that is not closed it changes nothing | Accept's way back from its own accepted close, when a gate filed after its live read shows or its sling fails (section 8). Today's Accept reopens a demand the same way after a failed sling (gc-toolkit `assets/scripts/gc-helm.sh` 2901-2921). | bd `cmd/bd/reopen.go` 15-20, 64-67, 91-99; `internal/storage/issueops/reopen.go` 48-50, 63-68, 100-117; `internal/storage/issueops/blocked_state.go` 455-475; `internal/storage/domain/db/issue.go` 1113-1114 |
| `bd close` refuses a blocked bead, a bead with open children, and a bead assigned to any actor but the one closing it, whatever its status, each without `--force`, and a close removes none of the bead's dependency rows | A human gate holds the close of what it blocks, and a conversation's `tracks` edge holds nothing. A bead a gate blocks closes only once the gate closes or the edge is removed with `bd dep remove` (section 11). A dismiss falls back to `--force` past the assignee check (section 7). The migration releases a visit from its holder before it closes it, so that close stays unforced and still meets the blocker and child checks (section 11). | bd `internal/storage/issueops/close.go` 150-160, 203-205, 339-384; `cmd/bd/close_direct.go` 84; `cmd/bd/show_unit_helpers.go` 27-35; `internal/validation/issue.go` 165-174 |
| A blocked bead's state cascades to its `parent-child` children and their descendants, whatever their types and the bead's, and through no other edge. A child added under a blocked bead is blocked as it is added. `bd list --parent <bead>` lists the bead's children, and also any bead with no parent whose id is the bead's id followed by a dot. Without `--all` or `--status` it leaves out the closed and pinned children, which are the ones the cascade never blocks. By default it also hides gate, infra, template and wisp children, which the cascade does block, and `--include-gates`, `--include-infra`, which admits the wisp plane too, and `--include-templates` list them. It hides a bead flagged pinned, which bd defines as a context marker rather than a work item | What a gate on a parent pauses, which is why each caller that can land on a parent states what its gate blocks (sections 1 and 3), and how the migration tests a bead for an open child in one call (section 11). | bd `internal/storage/issueops/blocked_state.go` 206-240 and 499-511; `internal/storage/issueops/create.go` 321-325 and 507-523; `internal/storage/issueops/dependencies.go` 324-331; `internal/storage/sqlbuild/filter.go` 174-178; `internal/workapi/list.go` 242-250, 351-357 and 428-452; `cmd/bd/list.go` 465-479; `internal/types/types.go` 158; `docs/component-model.md`, I1's shape law |
| `bd dep add <a> <b> --type=until` says that <b> resolves <a>. `until` is a well-known reference type outside bd's ready calculation, and bd only displays it: nothing in bd acts when <b> closes. The pack's deferred-dispatch reconcile pass closes <a> as resolved once <a> is open and unassigned, every `until` target of it has closed, no `blocks` blocker of its own is open, and <a> carries no live work | Why the migration moves a visit's `until` waits onto its gate, as it moves its `blocks` waits (section 11). | bd `internal/types/types.go` 1273-1274, 1333-1337; `cmd/bd/dep_relation.go` 47; gc-toolkit `assets/scripts/until-resolved.sh` 1-25 and `assets/scripts/deferred-dispatch.sh` 1301-1414 |
| A convoy's members are every bead it tracks, whatever their type, beside its legacy `parent-child` children. A `blocks` dependency of the convoy is no member. `gc convoy land` refuses a convoy while a member is open, autoclose waits for every member, and gc-toolkit's graduation counts every tracked bead | Why a convoy needs no exception. A gate it waits on is reached through the convoy's own `blocks` edge, and a conversation about it tracks it from the conversation's side, so neither becomes a member (section 1). | Gas City `internal/convoy/membership.go` 121-164; `cmd/gc/cmd_convoy.go` 2160-2173, 2393-2417; gc-toolkit `assets/scripts/convoy-graduate.sh` 123-130 |
| `bd ready` excludes gates, and a plain `bd list` hides them (`--include-gates` or `--type gate` shows them) | Why no pool's demand reaches a human gate, and why the board reads gates by type. | bd `internal/storage/sqlbuild/ready.go` 16-22; `internal/workapi/list.go` 433-434 |
| `gc bd` runs each call against the store that owns the bead it names, ahead of `GC_RIG` and the working directory. A by-id read or write, `show`, `dep list`, `dep tree`, `update`, `close`, `reopen` or `delete`, routes by the id's prefix. Any other call, `gate create` and `gate resolve` among them, routes to the store of the first argument whose prefix names a store and that exists there, city-prefixed ids first. That scan reads each word that does not start with `-`, so a value joined to its flag by `=` is not seen. An explicit `--rig` or `--city` outranks the bead, and a `--db` reaches bd unread, so bd uses the store it names whatever the routing chose | Why the helper picks no store of its own. `gate create --blocks <bead>` names the bead, so a gate lands beside the bead it blocks whoever files it, and a bead that exists nowhere fails the create (section 2). The helper passes the bead as its own word after `--blocks`, and passes no `--rig`, `--city` or `--db`. | Gas City `cmd/gc/bd_subject_route.go` 10-43; `cmd/gc/cmd_bd.go` 688, 807-815, 1027, 1032-1077 and 1094-1125; `cmd/gc/cmd_bd_by_id.go` 958-972 |
| `bd update --claim` is a compare-and-swap | The sitting's claim on its conversation task. It succeeds on an open bead whose assignee is empty, the claiming actor, or one of the store's claim pools. It sets `in_progress`, the assignee and a lease, and is idempotent for its holder. It refuses a bead another actor holds. | bd `internal/storage/issueops/claim.go` 91, 114-118, 147-148, 341-352 |
| `bd update --if-assignee <x>` applies the update only while the assignee still reads `<x>`, checked inside the update's transaction, and `''` means unassigned. A mismatch writes nothing and exits 13. It needs a field change and cannot combine with `--claim`. An assignee change on an in-progress bead another actor holds is refused unless it names that holder this way or passes `--force`. An update that changes the holder, or moves the bead out of `in_progress`, drops the claim's lease | Half of what keeps a second sitting off a conversation: engage's bind. Also the hand-off that returns a conversation to the operator's queue (section 6), and the migration's release of an open visit bound to a sitting (section 11). | bd `cmd/bd/update.go` 488-505, 824, 930-975, 997-1004; `internal/storage/issueops/execution.go` 160-170; `internal/storage/issueops/update_cas.go` 34-59; `internal/storage/issueops/aggregate.go` 160-174; `internal/storage/issueops/update.go` 189-209, 492-497 |
| Agent `work_query`, and its three-tier default | The default finds the conversation task assigned to the session, so converse needs no work query of its own. Its second tier, `bd ready --assignee`, finds the task open, and its first tier finds it in progress after a restart. Its third tier offers routed work and is closed to a manual session whose alias is not its template's name, so a sitting is offered nothing but its task. The current runtime takes no wake demand from a work query. | Gas City `internal/config/workquery.go` 528-536, 605-613, 780-793, 957, 972-977; `internal/config/config.go` 3626-3643; `cmd/gc/city_runtime.go` 3349-3352, 4625 |
| `gc hook --claim` claims an open bead its work query offers that is already assigned to the session, of any type but `message`, and returns one it already holds in progress. The default query's assigned tiers read `bd list` and `bd ready`, which leave gates out, so it never offers a session a gate, even one assigned to the session's alias. In a manual session it claims under the session's alias, which is also the session's bd actor | The sitting's first step (section 6). | Gas City `cmd/gc/cmd_hook_claim.go` 502-512, 797-910, 1267-1288; `internal/config/workquery.go` 605-613, 780-785; `cmd/gc/cmd_hook.go` 291-299, 460-473, 522, 540-547; `internal/session/lifecycle.go` 76-79 |
| `gc session new --alias <a>` reserves the alias under a city-wide lock, and refuses it while another session that is not closed holds it as its alias, its session name or its identity | The other half of what keeps a second sitting off a conversation: engage starts the sitting under the task's id before it binds the task (section 6). | Gas City `cmd/gc/cmd_session.go` 336-351 and 465-480; `internal/session/names.go` 288-327, 630-702 |
| Assigned work wakes the session whose identity it carries, and an unassigned, unrouted bead wakes nothing | Why a conversation in the operator's queue, assigned to `human`, which no session carries, starts no session. | Gas City `cmd/gc/build_desired_state.go` 1938-1950, 3215; `cmd/gc/assigned_work_scope.go` 382-431; `cmd/gc/compute_awake_set.go` 454-495 |
| Gas City's releases of a dead holder's claims. An agent's default on_death runs for pool instances only. Core's orphan-sweep resets an in-progress bead only when it can show the holder dead, and it counts a bead whose `gc.session_name` it cannot resolve as unverifiable and leaves it, which is every bead `gc hook --claim` claimed in a manual session. Both list without `--include-gates`, so neither sees a gate | Why a sitting's recovery runs through its alias, and why engage needs no reclaim (section 6). | Gas City `cmd/gc/cmd_start.go` 159-176; `internal/config/workquery.go` 1351-1378; `internal/bootstrap/packs/core/assets/scripts/orphan-sweep.sh` 89, 106, 277, 335, 345, 632-634; `cmd/gc/cmd_hook_claim.go` 2073-2075 |
| `gc bd release-if-current <id> <holder>` runs `bd update <id> --if-assignee <holder> --if-status in_progress --status open --assignee ""`, so it leaves the bead open and unassigned. When the bead is no longer in progress under that holder, bd writes nothing. The command prints `released` or `skipped` and exits 0 either way, so only its output or a read-back tells the two apart | The migration's release of a visit in progress before it closes the visit, because bd refuses to close a bead another actor holds (section 11). Released, the visit is open and unassigned, as a visit no sitting holds is today, until the migration closes it. A conversation is never released this way: assigned to nobody, it would be a state neither the board nor engage reads as a conversation, so a conversation's hand-off reassigns the task to `human` with the same guard instead (section 6). | Gas City `internal/beads/bdstore_conditional_release.go` 78-99; `cmd/gc/cmd_bd.go` 124-137 and 919-946 |
| A manual session does not end when its work closes. It stays until it is closed or drained, and a wait hold or an idle-sleep setting only puts it to sleep. An attached session is woken even when drained, unless a wait hold is set. `gc session attach` wakes a dormant session, and `wake_mode = "resume"` resumes the session's own transcript by its session key. A closed session does not reserve its alias: a new session under it starts a fresh transcript and takes the in-progress work still assigned to the alias. `gc session close` releases no claim held under the alias. No closer the controller runs on its own ends a manual session because its work closed: the stale-session closers exempt one that has started its conversation, and the core reaper prunes one only once it has drained. `gc session list` leaves a closed session out, whatever state it is asked for | Why converse-reap stays, how a sitting resumes, and why a held conversation is found by its assignee rather than by its session (section 6). Also why the migration releases a visit whose sitting it has ended (section 11). | Gas City `cmd/gc/compute_awake_set.go` 432-440, 583-594, 668-693; `internal/session/manager.go` 1264-1271, 1344-1362; `internal/session/names.go` 639-641; `cmd/gc/cmd_session.go` 1894-1897, 1946; `cmd/gc/session_beads.go` 969-975; `cmd/gc/work_location.go` 220-225; `cmd/gc/city_runtime.go` 3915; `cmd/gc/session_reconciler.go` 1057-1060; `cmd/gc/session_beads.go` 3500; `internal/bootstrap/packs/core/assets/scripts/reaper.sh` 69, 1402-1404; a live `gc session list --state closed`, which returned no row on 2026-10-20, as `formulas/mol-witness-patrol.toml` 424 records |
| The pool execution backstop nudges, then drains, a pool session that holds in-progress work and is quiet for 90 seconds, with no attachment exemption. It governs only a session marked `pool_managed`, and Gas City marks one so only when the controller started it as neither a named nor a manual session, which is the origin `ephemeral`. `gc session new` with an alias gives a session the origin `manual` | Why a sitting's session is not a pool session, and why engage's `gc session new` keeps it out of the backstop's reach (section 6). | Gas City `cmd/gc/idle_nudge.go` 57-59; `cmd/gc/execution_backstop.go` 321-322, 405-421, 691; `cmd/gc/cmd_session.go` 289, 418, 698-704; `cmd/gc/session_origin.go` 172-181; `cmd/gc/reconcile_arms_metadata.go` 103, 131-133; `cmd/gc/session_beads.go` 1918, 2205-2206 |
| A template's `min_active_sessions` defaults to 0, so a template that leaves it out or writes 0 keeps no session running for its own sake. A template with a `scale_check` gets a demand pass of its own | Why the converse templates' declared pool starts no sitting, and what pool-demand-wiring.test.sh guards (section 6). | Gas City `internal/config/session_capacity.go` 27-33; `cmd/gc/allocator_scalecheck_lane.go` 107-124 |
| Core notify-on-human-gate-creation and renudge-stale-human-gates | Gas City's native reach for a human gate. The town turns the second off today, and turns the first off before the cutover (section 5). The first mails a gate's addressee once, when the gate is created, and nudges it as well when the addressee is a session rather than `human`. The second mails it again once the gate has been open an hour, and at most once an hour after that. Both act only on an open human gate, never read its await id, and address its assignee, then `gc.deferred_assignee`, then `$GC_ESCALATION_RECIPIENT` (default `human`). | Gas City `internal/bootstrap/packs/core/orders/notify-on-human-gate-creation.toml` 1-30 and `renudge-stale-human-gates.toml` 1-37; `internal/bootstrap/packs/core/assets/scripts/notify-on-human-gate-creation.sh` 1-80, 173-181, and `renudge-stale-human-gates.sh` 68-74; the town's city.toml 304-311 |
| Core escalate.sh hook and its incident reminder. It suppresses a repeat only for a call that names an `--incident-key`, and only while the incident's fingerprint, by default its subject and message, is unchanged since its last delivered notice, for `GC_ESCALATE_REMINDER_SECONDS` (default 86400). Core's maintenance scripts run the script `GC_ESCALATE_SCRIPT` names, else `assets/scripts/escalate.sh` in the first system pack `GC_ESCALATE_SEARCH_PACKS` names (default `gastown maintenance bd core`), so that path is where a pack overrides the hook, and an override must accept core's flags | Prior art for the helper's quiet period, and for making it an option each call declares (section 2). It is a mail hook for maintenance scripts, and it is not this pack's helper, which today sits at the override's path with flags of its own. That is one reason the helper is renamed (section 2). | Gas City `internal/bootstrap/packs/core/assets/scripts/escalate.sh` 1-22 and `reaper.sh` 34-51; `docs/getting-started/troubleshooting.md` 877-905 |
| A city's order override can set an exec order's environment | The alternative section 5 rejects. | Gas City `internal/config/config.go` 2383-2385; `internal/orders/override.go` 162-166; `cmd/gc/order_store.go` 229-235 |
| bd stores the actor that creates a bead as its `created_by`. Gas City runs each exec order as the actor `order:<name>`, and `gc bd` runs bd in its caller's environment | The migration tells a visit gate-visit-sweep filed from every other visit (section 11). | bd `cmd/bd/create.go` 531 and `cmd/bd/main.go` 813-822; Gas City `cmd/gc/order_store.go` 197, and `cmd/gc/cmd_bd.go` 165-193 and 686-702 |
| A formula's step is poured into a bead whose description is the step's text as the formula read at the pour, with its variables substituted | Why escalate.sh's old name stays as a hand-off to human-gate.sh: a run poured before the cutover keeps its steps' text, and mol-polecat-work's load-context looks for escalate.sh on every run, so without the old name every such run would stop at its first step (section 10). | Gas City `internal/molecule/molecule.go` 1460-1468; gc-toolkit `formulas/mol-polecat-work.toml` 177-181 |

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
  19-42), and a held sitting is quiet for hours. The first sitting ruling
  (tk-4t0uev0) answers this by never claiming a gate: a sitting claims an
  ordinary task under its alias (section 6).

One premise of the first sitting ruling (tk-4t0uev0) did not hold either. The
ruling read Gas City's on_death and orphan-sweep as releasing a dead sitting's
task. Both list tasks and miss gates, as the ruling found, but neither releases
a sitting's task. An agent's default on_death runs only for pool instances,
keyed by the instance's qualified name, and a sitting's session is a manual
session.
Core's orphan-sweep counts a bead claimed through `gc hook --claim` in a manual
session as unverifiable and leaves it (see the platform section; the sweep was
read, not run). The ruling's conclusion holds on another fact. The task's
assignee is the sitting's alias, a closed session does not reserve its alias,
and a new session under it takes the in-progress task as its own. So engage's
reclaim still retires, and recovery runs through the alias (section 6).

**How Gas City and its packs use human gates today.** The human gate is a core
Gas City concept. `bd gate create` files one unless its `--type` names another
await type, and only a manual close ends one, `bd gate resolve` or `bd close`,
because `bd gate check` skips it (bd `cmd/bd/gate.go` 307, 534 and 1283,
`cmd/bd/close.go` 636-651). Gas City's core pack ships two orders built for it.
notify-on-human-gate-creation mails a human gate's addressee when the gate is
created, and renudge-stale-human-gates mails again while the gate stays open
(see the platform section). Those orders are the native way a human
gate reaches a person. This city opts out of both, for the reasons decision 8
and section 5 give.

No upstream pack files an `await_type=human` gate today: no file in the packs
at 820c7ca0d5 runs `gate create` or sets a human await type. Their human
checkpoints take other shapes. The build pack's human-gate steps and the
superpowers pack's approval steps park the session with
`gc session wait --sleep --on-beads` and mail the human once
(`gascity/assets/workflows/github-pr-review/human-gate-comment.md` 30-42, and
the triage, issue-fix and brainstorming steps that make the same two calls).
The pr-review pack's adopt formula stops at an ordinary step bead that a
maintainer closes (`pr-review/formulas/mol-adopt-pr.formula.toml` 388-421). Gas
Town's idea-to-plan formula asks the person directly, in the session they are
attached to (`gastown/formulas/mol-idea-to-plan.toml` 207-221), and its
witness hands what it cannot settle to the mayor by mail
(`gastown/agents/witness/prompt.template.md` 332-342). A formula's gate field
does cook a gate bead, a sibling that blocks its step
(Gas City `docs/reference/specs/formula-spec-v2.md` 618-624,
`internal/formula/compile.go` 523-562). The cook carries none of the field's
type, id or timeout into the bead's fields. The type and id survive only in its
title (`internal/molecule/molecule.go` 1459-1487, `compile.go` 528). The spec
counts no bundled formula that uses one (`formula-spec-v2.md` 1057-1062). So
this design files the native object that core's orders are built for, which no
upstream pack files yet. No upstream surface lists open human gates for a
person either. Gas City's dashboard has a "Needs you" list, but it fetches no
gate, and it finds work that waits on a person by bead metadata and hold labels.
Both files are under the dashboard's
`internal/api/dashboardspa/web/frontend/src` tree: `supervisor/beadReads.ts`
40-47 and 152, and `attention/beadsNeedingAttention.ts` 62-68. Nothing upstream
fills the board's role.

## 1. What a human gate is, and what a conversation is

The Terms define a human gate and a conversation. This section gives each its
native shape: the call that files it, the edge that ties it to its subject, and
the fields it carries. Each carries its meaning in native fields, so another
pack reading the city sees a gate something waits on and a task someone holds,
and needs no knowledge of gc-toolkit to read either.

### A human gate

A human gate is filed with one native call:

```
gc bd gate create --type=human --blocks <bead> --await-id <key> \
  --title "<what the person must clear, at most 140 characters>" --reason "<the framing>"
```

Any pack, formula or person may file one with this call, and human-gate.sh is a
helper that makes the same call (section 2). Every reader treats a gate the
same whoever filed it, because each reads it by the one rule below.

**It is about the bead it blocks.** The filer files it on the bead that waits
for it: the work bead that declined, the anchor when the merge must wait, one
member of an epic. bd records the gate as a `blocks` dependency of that bead.
The bead leaves `bd ready` and the pool's offer until the gate closes, and
`bd close` refuses it while the gate is open. Another bead that must wait for
the same gate adds its own `blocks` edge onto it, as a rework child does onto
the bring-current gate its anchor waits on (section 4), and the gate is then
about both. bd records what a gate blocks only as those edges. Apart from the
first line of its description, which names the bead it was filed on, nothing
names one of them as the gate's own, and the design adds nothing.

**One reader rule.** A bead's human gates are the open human gates its `blocks`
edges reach. Every reader finds them that way: the helper's dedup, engage, the
board, finalize-gate, gctk merge, the liveness classifier, Accept and the
migration. The read is one call:

```
gc bd dep list <bead> --type blocks --json
```

It returns each bead the given bead depends on through a `blocks` edge, open or
closed, with its type, status, await type, await id and assignee. A reader keeps
the rows whose `issue_type` is `gate` and whose `await_type` is `human`, and the
open ones among them when it asks what still waits (see the platform section).
`bd gate list <bead>` is not that read, because it returns the gates a bead
reaches through an edge of any type and does not say which edge reaches them.

A reader that starts from a gate reads the same edges from the gate's end: the
beads that wait on it through `blocks` edges, with
`gc bd dep list <gate> --direction=up --type blocks --json` (see the platform
section). The board, check-refinery, pr-facts.sh's merge-blocked-approval
retire and engage pointed at a gate read it that way, because each starts from
gates and needs the beads they are about (sections 3, 6 and 8).

Three consequences follow, and the first and fourth decisions ask the operator
to accept them.

- **Routed work waits.** A work bead that declines on a human gate leaves the
  pool's offer until the gate is cleared, and its re-sling waits on the same
  edge (section 4).
- **A gate holds a PR's merge when it blocks the anchor.** gctk merge holds on
  any live `blocks` blocker of the anchor
  (`services/gctk/internal/cli/merge.go` 552-567), and finalize-gate keeps its
  clause on the same edge (section 4). The merge-path gates, a review's
  needs-you gates and a sitting's gate about the merge block the anchor, so
  they hold it as an open visit does today. A gate that blocks only a rework
  child holds the merge through that child, because an anchor carries a
  `blocks` edge onto each rework child it has. A conversation about
  the PR holds nothing (below).
- **A gate on a bead with open children pauses its unstarted parts.** A blocked
  bead cascades its blocked state to every `parent-child` descendant, whatever
  its type, and through no other edge (I1's shape law,
  `docs/component-model.md`, and the platform section). A human gate blocks
  like any other blocking gate, so a gate on an epic, on an owned convoy with
  children, or on a task with parts filed under it pauses every part that has
  not started. A child added later under a bead that waits on a gate is
  blocked as it is added, and stays blocked until the gate is cleared. Work
  already in flight is not stopped, because a blocker gates claims, not
  running sessions. What a gate blocks is the filer's call-site policy, as its
  quiet window is, and the helper refuses no bead for its shape. Each caller
  that can land on a parent says whether it blocks the parent, blocks one
  member, or opens a conversation instead (section 3). A convoy needs no
  exception, because its members are the beads it tracks, and a gate it waits
  on is reached through its `blocks` edge (see the platform section).

The doctrine that a conversation does not freeze its subject stays, in native
form: a conversation blocks nothing, and a human gate holds only what waits on
it (`docs/human-engagement.md` on main, "A conversation does not freeze its
subject; a merge hold is an opt-in"). What retires is the machinery that kept a
visit's own wait off its subject: converse-hold's demand filed on the visit, its
opt-in `--hold-merge`, and the cut-short sign-off that moved the demand onto the
anchor. A sitting that wants the merge to wait files a human gate on the anchor
(section 7).

**Its title** is what the person must clear, as the board's NEEDS cell shows it,
at most 140 characters, the cap gc-helm.sh takeaway already enforces. bd's
default title is `Gate: human <await id>`, so the filer always passes one.

**Its description** carries the framing. bd writes a first line naming the bead
the gate was filed on and puts the filer's reason after it (see the platform
section). A gate the liveness sweep raises names, in its message, the command
that re-reads the current state. That replaces the `visit.recheck` hook.

**Its await id** is the situation key alone, the filer's key, which bd calls the
gate's condition identifier. A gate a sitting files uses the key
`conversation` (section 7), and a first reaction's gate the key `first-reaction`
(section 8). The key is what tells two gates on one bead apart: the helper's
dedup, a filer's withdrawal, a declared quiet period and Accept each read it
among the gates the bead's `blocks` edges reach. The helper refuses a key
outside `[A-Za-z0-9._-]`, as escalate.sh does today
(`assets/scripts/escalate.sh` 123-124). bd stores the await id and returns it
with the gate. bd's gate check skips human gates (bd `cmd/bd/gate.go` 712-731),
and core's two human-gate orders read a gate's type, status, age and addressee,
never its await id. So the pack's keys collide with nothing in the platform.

**Its assignee** is empty while the operator owes the gate, or the one person
who must clear it. No session claims a gate: a sitting holds a conversation
instead (below). Gas City's notify and renudge orders act on a human gate while
it is open, and mail its assignee, or the recipient `$GC_ESCALATION_RECIPIENT`
names when it has none.
A claim would move the gate to in progress, which both skip, and nothing claims
a gate, so in a city that keeps those orders on, a gate stays loud until it is
cleared, whether or not a sitting is discussing it. In this city both orders are
off, and the board is the reach (section 5). An action only a named person can
perform, when work waits on it, is a human gate on the waiting bead, assigned to
that person. `bd gate create` takes no assignee, so
`gc bd update <gate> --assignee <person>` sets it after the create. In a city
that keeps the notify order on, its creation notice can reach that default
recipient before the update lands. Work a person owes that nothing waits on
stays an ordinary bead assigned to them.

**Clearing it** writes its close reason, through `bd gate resolve` (section 7).

**It carries no pack metadata.** Every fact the visit kept in a pack key is a
native field of the gate or of the conversation:

| The visit carried | After |
|---|---|
| `task_kind=visit` | `issue_type=gate` with `await_type=human` for a human gate; an ordinary task for a conversation |
| `gc.routed_to=human`, the board's human partition | `await_type=human`, or a conversation assigned to `human` |
| a `tracks` edge to the subject and `gc.continuation_group=<subject>` | the `blocks` edge of each bead the gate holds, read by the one reader rule; the conversation task's `tracks` edge |
| `escalation_key` | the gate's await id |
| the title `visit: <subject> — <headline>`, and `gc.takeaway` on a demand gate | the gate's title, or the conversation's |
| `gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, `gc.hold_demand` | the gate itself |
| `gc.outcome`, `gc.outcome_reason`, `gc.ruling` | the gate's close reason (section 7) |
| `pr_number`, `pr_url` and `anchor_bead`, stamped on PR-comment visits so the merge held | the gate's `blocks` edge on the anchor |
| `visit.recheck` | a command in the gate's description, or in the notes a migrated visit left (section 11) |
| `sweep.new_ids`, `sweep.carried_ids` and `sweep.pass_at`, the census a liveness sweep's visit carried | the ids and the time in that command (section 4) |
| `gc.pr_visit_summary`, `gc.pr_visit_actions` | arguments to the sign-off (section 7) |
| the visit's assignee, the sitting that held it | the conversation task's assignee |

Molecule steps stamp `gc.continuation_group` for Gas City's own preassignment
(`formulas/mol-polecat-work.toml` 55, `formulas/mol-review.toml` 145). That use
is not the visit's, and it stays.

### A conversation

A conversation is filed as an ordinary task that tracks its subject:

```
gc bd create -t task --title "<what the conversation is about>" \
  --description "<the ask>" --deps "tracks:<bead>" --assignee human
```

`--deps "tracks:<bead>"` makes the new task track the bead (see the platform
section), and that bead is the conversation's one subject. It is always a bead,
never a gate: engage pointed at a gate takes the bead the gate blocks, read from
the gate's `blocks` dependents (above), and files or finds the conversation on
that bead (section 6). The sitting serves every human gate on its subject, the
gates the subject's `blocks` edges reach, and its record and headline go on the
subject. A gate whose beads have all closed still has them as its subjects, and
the board gives it a row of its own (section 8).

A conversation and work a person owes that nothing waits on are both assigned
tasks, and their shape tells them apart. A conversation tracks the bead it is
about, and it is assigned to `human` or to the alias that names its own id.
Work a person owes is assigned to that person and tracks nothing (above). Every
reader that looks for conversations, engage and the board among them, reads
that shape (sections 6 and 8).

- **It blocks nothing, and nothing waits on it.** An open conversation does not
  hold its bead's readiness, close or merge. When something must wait for what
  the operator decides, the sitting files a human gate on that bead
  (section 7).
- **Its assignee says who holds it.** It is `human` while the conversation
  waits in the operator's queue, which is where a conversation the operator
  opens without engaging it sits. It is the sitting's alias while a sitting
  holds it: engage binds it to the alias, and the session's claim sets
  `in_progress` and a lease. The alias names the task's own id (section 6), so
  a held conversation is known by its assignee alone, even once its sitting's
  session has closed and left the session list. That alias is what a recovery
  resumes (section 6).
- **Its title** is what the conversation is about, and the board shows it where
  a gate's title would be. **Its description** is the ask: the operator's
  concern, or the gate engage was pointed at.
- **It closes when the sitting ends,** answered or dismissed, and returns to the
  operator's queue when a sitting is cut short or handed off (sections 6 and
  7). The outcome goes on the subject's notes, as today, and each answer is the
  resolve reason of the gate it clears.

A conversation carries no pack metadata. A reader outside the pack sees a task,
held by a session or in a person's queue, that references a bead.

## 2. human-gate.sh, the optional helper

**Any pack, formula or person may file a human gate** with the native call of
section 1, and every reader treats that gate exactly as it treats one the helper
filed, because each reads gates by the one reader rule. The helper is today's
escalate.sh, renamed human-gate.sh (below). It is for the two things that call
does not do: it keeps one open gate per bead and key, and it keeps the quiet
period a call declares. It already has the most callers, and they keep calling
it under its new name. Its flags stay `--subject`, `--key`,
`--message` and `--retract`, and `--subject` names the bead the gate blocks.
`--pool` retires, because a gate is not routed, and so do the routes that
forward it: upstream-finding.sh's own `--pool` (upstream-finding.sh 57, 411),
and reconcile-rig-checkouts.sh's `RECONCILE_ESCALATION_POOL` knob, which tries a
pool before the board (reconcile-rig-checkouts.sh 166-169, 184-195).
`--quiet-window <seconds>` joins them, the quiet period a call declares
(step 3).

It files in four steps:

1. **It refuses a wisp.** A `*-wisp-*` id names a patrol wisp, which is burned
   and re-poured every cycle, or a session (escalate.sh 138-160 and its test
   at 190). Neither is a bead that can wait: a gate on a patrol wisp would
   block nothing once the wisp burns, and the next cycle's wisp would file
   again. The helper files nothing on one, exits 2, and names the durable
   route, a patrol finding (below). A subject that names no bead fails step 2's
   read, and the helper files nothing and exits 1.
2. **It reads the bead's gates** by the one reader rule, closed ones included,
   with `gc bd dep list <subject> --type blocks --json`. An open human gate
   whose await id is the key means the situation is already asked, so the helper
   prints that gate's id and exits 0. That holds for a gate filed on another
   bead that this one already waits on: a rework child whose wait on its
   anchor's bring-current gate is in place files nothing more under that key.
   This is the idempotency the initiative's ruling asks for. bd has none at
   create, so two writers racing in the same instant can both file. The board
   folds both, and a sitting answers both with one reason.
3. **It keeps a quiet period the call declares.** With `--quiet-window`, the
   helper files nothing, and says so, while the newest closed human gate under
   the key among the bead's gates closed with a reason headed `moot:` or
   `benign:` less than that many seconds ago. It reads that gate in step 2's
   listing. Without the option there is no window. The window is the filer's
   policy, because only the filer knows the shape of what it files. The helper
   cannot tell a re-detection of one persisting condition, such as a patrol
   re-reporting a red check after a benign answer, from a new occurrence of an
   event, such as a second outage two hours after the first was answered
   benign under the same key. So each recurring detector declares its window at
   its own call site, with a one-line why. An event-shaped filer declares none,
   and keys each occurrence apart where several share a bead. Off is the
   default because it fails loud: a detector that forgot its window asks again
   on the board until its call site is fixed, where a default window would mute
   a real event without a trace. `GC_ESCALATE_VERDICT_WINDOW` stops being a
   global default. Converse owns no window: a sitting only writes close
   reasons.
4. **It files the gate** (section 1), blocking the subject, and reads the gate
   and its edge back. Gas City's `gc bd` runs the create in the store of the
   bead it names, so the gate sits beside the bead it blocks (below).

`--retract` withdraws the filer's own gate. It resolves each open human gate
under the key among the gates the bead's `blocks` edges reach, with the reason
`moot: <message>`. A gate that blocks several beads is resolved once, and every
bead it held is released. It claims nothing, because no session claims a gate.
A sitting may be discussing the gate when the retract lands, and the retract
clears it anyway, because the situation it asked about is gone. The sitting
learns it at its sign-off, which reads each gate back (section 7). A retract
interrupted part way leaves gates the next retract for the situation finds and
resolves, and resolving a gate already closed changes nothing.

**One open gate per bead and key.** The initiative's ruling says "one open ask
per subject", and the operator still sees exactly that: every human gate on a
bead folds into the bead's one board row, always. A sitting serves every gate on
its subject, and engage attaches to a live sitting on the bead before it starts
another, so one sitting answers them all in the normal path. That is engage's
default, a convention and not a guarantee (section 6). In the store, two
situations on one bead stay two gates, such as two PR comments, or a review's
needs-you gate beside a merge failure. Keeping them apart lets each filer
withdraw its own gate when its situation clears, and keeps a declared quiet
period per situation.

**The helper's other conveniences, and its name.** The ruling of sitting
tk-yf4nt2d left three conveniences to this design, each to keep or drop under
the epic's four tests (`docs/foundation.md` on main, "Boundaries"), and the
ruling of sitting tk-tdt71ue left it the helper's name:

- **A filer's withdrawal of its own gate by key is kept.** `--retract` is one
  call that runs a series of native steps: read the bead's gates, keep the open
  human gates under the key, and resolve each with a `moot:` reason. No native
  call withdraws by key. The third test allows exactly this glue, one call that
  runs native steps so that every filer takes them the same way and none
  assembles them in its own context. Its callers that stay are the witness
  patrol's check-refinery, reconcile-rig-checkouts.sh, the waits skill and the
  human-gate-withdraw fragment five prompts include, and each would otherwise
  carry the loop. pr-facts.sh's dispose retract is a caller today, and it goes
  (section 3). The
  key it withdraws by is the one the dedup reads, so the helper's two halves
  agree on what a situation is.
- **The helper's own choice of store is dropped.** Gas City's `gc bd` already
  runs a call in the store that owns the bead it names, ahead of `GC_RIG` and
  the working directory: a by-id read such as `dep list` by the id's prefix,
  and `gate create` and `gate resolve` by the first argument that exists in the
  store its prefix names (see the platform section). `gate create --blocks
  <bead>` names the bead, so the gate is created beside it, and a bead that
  exists nowhere fails the create. The helper's derivation, escalation-rig.sh
  over bead-store.sh with a `--db` pin on every call (escalate.sh 194-251),
  re-expresses that native mechanism, which the third test rules out. A gate
  filed directly lands in the same store by the same routing, so the two land
  alike. The derivation was needed while a visit was created with `bd create`,
  whose arguments name the subject only inside its title and metadata, where
  the routing cannot see it, before a separate `dep add` tracked the subject
  (escalate.sh 624-629). escalation-rig.sh's other callers, the deacon prompt
  and mol-dog-shutdown-dance, run it only to set `GC_RIG` for escalate.sh.
  Their derivations re-express the same mechanism, so they go with the
  helper's (section 3), and escalation-rig.sh retires (section 10).
- **The redirect of a wisp's gate onto the rig's standing triage bead is
  dropped.** The redirect files the gate on a standing bead that waits on
  nothing (escalate.sh 536-605), so the gate would be about a stand-in rather
  than about work that waits, which the ruling's first two items rule out. That
  bead is also a pack noun, a bead kind the pack defines
  (`task_kind=triage-subject`), and `docs/warrants.md` on main holds no warrant
  for it, which the second test requires before the pack builds further on
  one. The callers that pass a wisp or a session id are three patrol checks:
  the refinery patrol's empty-identity check
  (`formulas/mol-refinery-patrol.toml` 112) and the witness patrol's two checks
  that find its refinery-queue monitor blind, an unroutable refinery address and
  an unreadable queue (`formulas/mol-witness-patrol.toml` 932, 942). Each
  reports a condition with no bead of its own that persists until someone fixes
  it, which the pack files as a patrol finding: one durable bead per situation
  key, whose first reaction is slung when the finding is filed and files a human
  gate on the finding when it needs a person (`assets/scripts/patrol-finding.sh`
  1-28, 545-555). They move to
  patrol-finding.sh in unit A. The redirect also took a subject the store
  helper could not place, and without it the helper files nothing on a subject
  it cannot read (step 1). So the callers that file a gate because their bead
  could not be read or placed, the polecat's unreadable-work arms,
  rejection-repool.sh's unread handoff and the witness's unplaceable owner,
  file a patrol finding too, which lands in the filer's own store and names
  the bead in its text (section 3). The liveness sweep files on standing buckets of its own,
  which draw the same two objections. This design leaves them as they
  are (section 4), and the epic's patrols member, tk-1tfzr71.19, which owns the
  sweep's migration, carries the objections in its notes.
- **The helper is renamed human-gate.sh.** The Terms retire the word escalation,
  and the helper's name is where it would live on: in the call most filers
  run, written into the prompts, formulas, skills and docs agents read as
  instructions. The name escalate.sh also belongs to Gas City core's own
  escalate.sh, a mail hook for maintenance scripts that is not this helper,
  and `assets/scripts/escalate.sh` is the path at which a pack overrides that
  hook with core's flags, where this helper sits today with flags of its own
  (see the platform section). That clash is latent: core's default search
  list does not name gc-toolkit, and the town's city.toml sets no list, so no
  maintenance script calls this helper today. The new name says what the
  helper files, as
  patrol-finding.sh and upstream-finding.sh do. Unit A already decides every
  call site (section 3), so the new name is one more word in each call it
  reads, and the tests named for the helper are renamed with it (section 10).
  The old name stays as a hand-off that runs human-gate.sh with the same
  arguments. A run poured before the cutover keeps its steps' text, and
  mol-polecat-work's load-context looks for escalate.sh on every run, so
  without the hand-off every such run would stop at its first step (see the
  platform section). The hand-off retires under a dated debt (section 10).
  Keeping the old name would cost nothing to build, and it would leave the
  retired word in the call most filers make.

What becomes of escalate.sh's other behavior:

| Today | After |
|---|---|
| Dedup on `escalation_key` and `gc.continuation_group` (escalate.sh 393-461) | Step 2: an open human gate under the key among the gates the bead's `blocks` edges reach |
| The verdict window over closed visits' `gc.outcome` (463-531), on for every call unless the caller passes `GC_ESCALATE_VERDICT_WINDOW=0` | Step 3: the closed gate's reason, inside a window only a call that declares `--quiet-window` gets |
| The `escalation.recurrences` tally on the closed visit | Retires. `escalation.recurrence_last` has no reader, and only the tally reads `recurrences`. |
| `--retract` leaves an engaged visit alone and closes the rest through visit-close.sh (257-337) | Resolves every open gate under the key among the bead's gates (kept, above) |
| The subject's store, proven through escalation-rig.sh and pinned with `--db` (194-251) | Retires. `gc bd` runs each call in the bead's own store (dropped, above) |
| The ephemeral-subject triage bucket (536-605) | Retires. A wisp is refused (step 1), and the callers that passed a wisp or a bead they could not read file patrol findings (dropped, above) |
| The route check and repoint through pool-route.sh | Retires |
| The deacon's shift-record entry for what it files (663-682) | Kept, naming the gate. It records what the deacon did, so it stays with the deacon's calls |
| Its copy of the gate-visit block (383-650) | Replaced by steps 2 to 4 |

The quiet period is one of the helper's two additions to the native filing
call, and it has upstream prior art in the same shape. Core's own escalate.sh
does not re-send an unchanged incident for a day (`GC_ESCALATE_REMINDER_SECONDS`,
default 86400), and only for a call that names an `--incident-key` (see the
platform section). The pack's period answers the same need, a detector that
re-fires a condition a person already looked at, keys it on the person's
verdict, and is likewise on only where the call asks for it.

**The pack's other filers:**

- **`gc-helm.sh demand`**, the pack's only human-gate minter today (gc-helm.sh
  1460-1669), retires. park's plain gate is not a human gate (section 8).
  first-reaction-dispose.sh files its ruling and recommend gate through the
  helper with the key `first-reaction`, and the waits, prs and converse-settle
  skills teach the helper and the native call. An action only a named person
  can perform, which the waits skill teaches through `demand --assignee` and no
  caller passes, is a human gate on the bead that waits, assigned to that
  person after the create (section 1). converse-hold.sh and
  converse-signoff.sh, demand's other callers, retire or shrink (section 7).
- **`gc-helm.sh open`** files a conversation, not a gate: an ordinary task in
  the operator's queue (section 1), with no session yet. Engage takes it when
  the operator engages its bead (section 6). The operator's intake, a sitting
  that opens a conversation on another bead, the waits skill and helm-svc's
  POST /helm/open all reach it that way.
- **The gate-visit block** in mol-validate-close and mol-feedback-distiller
  becomes a helper call with the keys `validate-close` and
  `distiller-contention`. Today both reuse an open keyless visit on the subject.
  With their own keys, their gates show beside the operator's conversation
  instead of disappearing into it.
- **mol-visit** retires. Nothing pours it.
- **gate-visit-sweep** retires. There is no visit left to make.

**converse-hold's PR-anchor case retires.** converse-hold.sh files its demand on
the visit when the subject is in `pre_open_gate`, `pull_request` or `merged`
(converse-hold.sh 210-213, 234-244), which kept the conversation's own wait off
the anchor. A conversation now holds nothing, so there is no wait to keep off.
A held sitting keeps its conversation, and a gate it files blocks only what
waits (section 7).

## 3. Every caller outside converse

The list was re-derived from main at 35cf7c70f. Every call keeps the helper's
flags and names it human-gate.sh, where it named escalate.sh (section 2), except
the `--pool` that upstream-finding.sh and reconcile-rig-checkouts.sh forward. A
call that names a wisp, a session or a bead it could not read or place files a
patrol finding instead (section 2), and so does a report that nothing waits on
(the second decision). The table names each. A caller that re-detects one
condition every pass gains `--quiet-window` at its call site, with a one-line
why, and a caller that files an event declares none (section 2).
Unit A decides each call site, because today every call gets the day-long
window unless it passes `GC_ESCALATE_VERDICT_WINDOW=0`.

What a gate blocks is each caller's own policy (section 1). A caller whose bead
can have open `parent-child` children states at its call site whether its gate
blocks the parent, blocks one member, or gives way to a conversation, and the
table says which. Every other caller blocks the bead it names, because that bead
is what waits, and a part filed under that bead waits too. The pack's PR anchors
join their rework and review children through `related` edges, never
`parent-child` (`assets/scripts/bd-lib.sh` 195-197), and an input convoy tracks
its one work bead rather than parenting it. The column on the right is what
changes around the call.

| Caller | Its move |
|---|---|
| mol-polecat-work's decline arms: load-context's unreadable, parked and duplicate refusals; the blocked-work fallback; the unclear-requirements instruction; workspace-setup's malformed convoy, target guard, branch divergence and missing branch; the bring-current gate through bring-current-audit.sh; submit's branch-shape, landing-target and hand-off refusals | The call is unchanged, and the gate blocks the work bead. On a work bead with open children it blocks the parent, and its unstarted parts wait on the same answer, because what stopped the work stops its parts too. The malformed-convoy refusal, the bring-current gate and the unreadable-work refusals differ. The malformed-convoy refusal files on the input convoy (`formulas/mol-polecat-work.toml` 430) and cancels the run without a wait. The bring-current gate is filed on the anchor (bring-current-audit.sh 339), so the merge waits too, and await-ruling.sh adds the work bead's own edge onto that gate (`formulas/mol-polecat-work.toml` 726, section 4). await-ruling.sh then releases the claim and arms the re-sling, and run-cancel.sh ends the run. The unreadable-work refusals of load-context and workspace-setup file a patrol finding about the bead and cancel the run, because a bead that cannot be read cannot be blocked (section 2). Each decline is an event of its run and declares no quiet window, so the `GC_ESCALATE_VERDICT_WINDOW=0` the waiting arms pass today goes, and the arms that pass nothing lose the day-long window they get today. |
| `template-fragments/polecat-doctrine.template.md` (its Escalation section and the decline protocol) and `template-fragments/pool-worker-no-consent-ui.template.md` | The same three calls in the same order. The text names human-gate.sh and says "the human gate it files" where it said "the visit escalate.sh opens", and it says that the gate holds the work bead and every part filed under it. The Escalation section is retitled in the Terms' words. Every polecat does what it does today. |
| mol-validate, mol-rig-demo, mol-refinery-patrol, mol-witness-patrol, mol-dog-shutdown-dance | Unchanged calls, except three patrol checks. The refinery patrol's empty-identity check and the witness patrol's two blind-monitor checks pass a wisp or a session id, so they file a patrol finding through patrol-finding.sh instead (section 2). The malformed-convoy refusals of mol-validate and mol-rig-demo file on the input convoy, as mol-polecat-work's does (`formulas/mol-validate.toml` 90, `formulas/mol-rig-demo.toml` 111). A refinery or witness patrol call whose bead is a graduating integration convoy blocks it as it blocks any other bead, and that convoy has closed its members. mol-witness-patrol's check-refinery starts from its gates, because the handoffs it looks for have left the queue: it lists the store's open human gates under the key `witness-refinery-queue` with `bd gate list --json --limit 0`, reads the handoff each one blocks from the gate's `blocks` dependents (see the platform section), and retracts on that handoff as today once it has left the queue. mol-dog-shutdown-dance drops its escalation-rig.sh derivation and the open-warrant guard built on it, because a gate now lands in the warrant's own store or not at all (section 2). Two reports have nothing that waits. The dog's malformed-warrant report is filed after the warrant closes refused, and the witness recovery's report of an orphan whose work landed is filed just before the witness closes the bead, a close a gate on the bead would refuse. Each files a patrol finding instead of a gate (decision 2), and so does the witness's unplaceable-owner report, whose bead's store the witness cannot name (section 2). |
| mol-deacon-patrol | It names escalate.sh in prose only. Its "becomes a visit" wording says the call files a human gate, and it names human-gate.sh. |
| The deacon, refinery and witness prompts | Unchanged calls, except that the deacon prompt's escalation-rig.sh derivation and its stale "converse pool" default go, so it calls human-gate.sh directly (section 2). Each prompt's emergency names the bead it is about. The text says that a gate on a bead with open children pauses its unstarted parts, so the agent names the member that waits when only one does, and that an emergency with no bead of its own files a patrol finding, the route the helper's wisp refusal names. |
| `template-fragments/visit-close.template.md`, which the deacon, mechanik, proactive, refinery and witness prompts include | Its `--retract` call is unchanged. The fragment is renamed (section 9). |
| pr-facts.sh, the merge-path families | Unchanged calls. Each gate blocks the anchor, so it holds the merge as the visit did. pr-facts.sh stops stamping `pr_url`, `pr_number` and `anchor_bead` on the comment and unengaged-thread gates. `visit_for`, the dispose refresh, the retire on a disposed anchor and the write-back's awaiting and resolved replies read the anchor's gates by key. The merge-blocked-approval retire clears every open one, even in a pass with no live anchor (pr-facts.sh 1260-1294), so it lists the store's open human gates under its key and reaches each anchor through the gate's `blocks` dependents (section 1). The dispose retract after a landed close (`retract_dispose_visits`) goes, both its call at pr-facts.sh 1779 and the full-pass sweep that retries it (1298-1335). bead-rehome.sh withdraws the retry's own gate before the close (section 4), so a landed close leaves none open. |
| gctk merge (one-anchor-per-pr, seed-audit-merge-gate) and record-failure-cap.sh | Unchanged calls. gctk merge reads a human gate on the anchor as a person's hold (section 4). record-failure-cap.sh's gate holds the record it asks a person to make, so its message says to clear the gate first (section 11). |
| gate-ensure.sh, branch-supersession.sh, reconcile-rig-checkouts.sh, rejection-repool.sh | Unchanged calls. branch-supersession.sh's lookup reads gates, and its call declares a quiet window, because a benign ruling is its release: the window is what lets the next pass dispatch the ordinary merge-in child (branch-supersession.sh 46-52, 466-476). gate-ensure.sh's review-wedge gate holds the review bead out of the pool, so its message says to clear the gate as part of either repair it names (gate-ensure.sh 503-520). rejection-repool.sh files a patrol finding for a handoff it could not read, and a gate on the handoff for every other short stop (section 2). reconcile-rig-checkouts.sh's pool knob, `RECONCILE_ESCALATION_POOL` or its prior name `RECONCILE_MAYOR_ADDR`, retires with `--pool`, and so does its pool attempt that falls back to the board call (reconcile-rig-checkouts.sh 166-169, 184-195). Nothing sets the knob, so its call stays the board call it makes today. |
| deferred-dispatch.sh | The call is unchanged on a bead with no open children. Its sling-failed gate blocks the armed bead, so the re-sling waits for the answer as well as for the cleared cap (deferred-dispatch.sh 1626-1632). On a bead with open children, which it tests with the one call section 11 uses (step 4), it opens a conversation on the bead instead, because nothing else waits on the answer: the cap already holds the arm, and blocking the parent would pause its parts over a failed sling. |
| liveness-sweep.sh, finding.sh | Unchanged calls. Their beads are an anchor, a standing triage bucket, or the finding's anchor, and each gate blocks that bead. liveness-sweep.sh puts its census in the message as its re-check command, instead of stamping it and `visit.recheck` on a visit (section 4), and its disposition text names human-gate.sh where it named `gc-helm.sh demand`. finding.sh records the gate's id (section 4). |
| upstream-finding.sh | Its own `--pool` option and the forwarding of it (upstream-finding.sh 57, 411) retire with the helper's, and so do the cases in upstream-finding.test.sh that pin the forwarding. No caller passes the option, so every call is unchanged. Its gate is the operator's action, the send itself: it blocks the send bead that carries the command, so the operator clears the gate, sent or declined, before the bead can close. bd refuses to close a bead an open gate blocks, where today the send bead closes as the answer (`docs/outbound-sends.md`). |
| The gascity-keeper sub-pack's refinery fragment and its polecat-patterns fragment | The refinery fragment's call passes flags escalate.sh rejects, behind `\|\| true`. tk-vfgmu8k fixes it to escalate.sh's flags, and this design keeps those flags. Where the polecat-patterns fragment says "File an escalation visit (`escalate.sh`)", it says to file a human gate with human-gate.sh (`packs/gascity-keeper/template-fragments/polecat-patterns.template.md` 55-56). |
| first-reaction-dispose.sh | The helper with the key `first-reaction`, blocking the bead the reaction is about, so the bead waits for the operator as it does today. On a bead with open children it blocks the parent too, because the reaction's ruling or recommendation decides how the whole bead proceeds, so its unstarted parts wait with it, and Accept works there as on any bead (section 8). Its `--visit` option, which blocked the subject on a visit, retires. |
| mol-validate-close, mol-feedback-distiller | The helper with their own keys (section 2). mol-validate-close files a gate on doubt, which an open child that is real work raises, so on a bead with open children, tested with the same call, it opens a conversation instead, because blocking the parent would pause the very work its doubt is about. The distiller's gate blocks the contested pattern, whose rule waits on the ruling. |
| gc-helm.sh engage and open, the operator's intake, helm-svc POST /helm/open | No helper call. They file and take conversations (sections 6 and 8). |
| The waits, prs and converse-settle skills | The helper, or the native call, where they called `gc-helm.sh demand` (section 9). The waits skill's own call to the helper is unchanged. |
| A gate a sitting files, under the key `conversation` | It blocks the bead that must wait for the operator's later answer, which the sitting names: the anchor when the merge must wait, or the one member whose work waits (section 7). |

## 4. What an open or cleared human gate means to other machinery

| Meaning today | Read by | After |
|---|---|---|
| **An open visit refuses its subject's finalization** | finalize-gate.sh `clause_no_open_visit`, run by gctk merge before approval and before the merge, and by bead-rehome.sh | The gate holds natively: gctk merge holds on a live blocker, and `bd close` refuses a blocked bead. The clause stays as an explicit precondition, re-expressed by the one reader rule as "no open human gate blocks this bead", because a close path that passes `--force` skips bd's refusal. A conversation holds nothing. `--except-key` keeps its meaning: the caller's own gates under that key, assigned to no person, do not hold the act they ask to retry. bd still refuses the close while they block the bead, so the retry withdraws them first (below). |
| **Any live bead carrying the PR's `pr_number` holds the merge**, which is how a PR-comment visit held its PR | gctk merge `inflightHolder` (merge.go 1509-1554) | No longer stamped on gates. The gate blocks the anchor. The probe stays for its other holders. |
| **The merge's machine state** | gctk merge's blocker classification (merge.go 553-567, `stuckHolder` 1582-1592) | It records a pool-routed blocker as progressing, an unrouted one as "an unrouted blocker no automated actor will clear", and nothing for a blocker routed to `human`, which is how a demand gate reads today (merge.test.sh 1307-1309). A gate carries no route, so gctk merge reads a gate whose await type is `human` as that person's hold and records no machine state. Its bead reader decodes no issue type or await type today, so a gate without a route would read as unrouted (merge.go 1582-1592), and the reader learns the await type. |
| **An open visit sets the PR's needs-attention status** | gctk pr-status `anchorOpenVisit` (`services/gctk/internal/cli/prstatus.go` 107-192) and `services/gctk/prstatus/prstatus.go` 121-123 | An open human gate that blocks the anchor, by the one reader rule. A conversation about the anchor does not set it. The shared phase input `prstatus.Facts.OpenVisit`, which gctk pr-status and the board both fill, is renamed `OpenHumanGate`, and `anchorOpenVisit` becomes `anchorOpenHumanGate`. |
| **The proceed ruling:** await-ruling.sh blocks the work bead on the visit and arms its re-sling | `assets/scripts/await-ruling.sh` | The wait is a `blocks` edge from the work bead onto the gate. await-ruling.sh finds the gate under the key among the gates of `--subject` as today, else of the work bead, by the one reader rule. When the gate already blocks the work bead, that edge is the wait. When it does not, as for the bring-current gate a rework child files on its anchor, await-ruling.sh adds the work bead's edge, because the child's `related` edge to its anchor holds nothing (`assets/scripts/bd-lib.sh` 195), and the gate is then about both beads. Either way it reads the edge back before it releases the claim, clears the route and arms the re-sling, in today's order, so the re-sling cannot fire before the answer. It survives because a formula-slung bead needs the arm. Closing the gate makes the work bead ready, and only the arm re-slings it on its formula. |
| **Review release:** a needs-you finding is released only by a closed visit carrying `gc.ruling`, following `gc.folded_into` and `gc.superseded_by` | finding.sh close-answered, run by gate-ensure.sh; review-answer.sh; pr-facts.sh's review dismissal | finding.sh stamps the gate's id as `finding.gate`. A needs-you finding is ruled once that gate has closed with a reason headed `ruled:`, or once the finding records its ruling as `finding.ruling_bead`, which the migration writes for a finding whose visit was ruled before the cutover (section 11). Its release then waits, as today, until no fix unit on its lane and no ruling's rework child is live, and the close records the ruling's bead as `finding.ruling_bead`. It still follows `gc.superseded_by`. Gates do not fold (section 7), so the `gc.folded_into` hop retires. `finding.ruling_visit` becomes `finding.ruling_bead`, named like `source_ruling_bead` because it names a gate for a ruling given after the cutover and a visit for one given before. pr-facts.sh's review dismissal and review-answer.sh read it there. finding.sh's open-visits, which set-disposition's refusal reads, lists the open human gates that the anchor's and its rework children's `blocks` edges reach, by the one reader rule, and its `--visit` and `--unrelated-visit` options name gates (finding.sh 366-447, 629-660). |
| **Liveness:** a subject covered by a live visit is conversing, and one named by `gc.demand_for` is held by design | liveness-classify.sh 113-149, liveness-sweep.sh, liveness-sweep-precheck.sh, liveness-recheck.sh | A bead whose `blocks` edge reaches an open human gate is held by design. A bead tracked by a conversation that a live session holds is conversing. The sweep's live-visit guards read the bead's gates and conversations. A conversation task is itself a named wait while what it tracks is open, through the classifier's existing `tracks` arm (liveness-classify.sh 155). A gate carries no census, so liveness-sweep.sh writes its census into the gate's message as the re-check command, `liveness-recheck.sh --ids <new> --carried <carried> --pass-at <time>`, where it stamped `sweep.new_ids`, `sweep.carried_ids`, `sweep.pass_at` and `visit.recheck` on the visit. liveness-recheck.sh gains `--carried` and `--pass-at` beside `--ids`, and its form that takes a visit id goes. The sweep's re-file check, which skips a pass whose new set a visit closed `dispositioned` already covered (liveness-sweep.sh 489-520), reads the closed human gates under the same key among its bucket's gates instead, and skips when one closed with a reason headed `ruled:` names the same new set in its command. |
| **Orphan disposal** | orphan-dispose.sh's visit arm; the witness patrol's recovery steps | The visit arm retires. The recovery reads a bead as orphaned when no live session carries its owner, and it skips a bead routed to `human` (mol-witness-patrol.toml 245-250, orphan-dispose.sh 433). A conversation is assigned, not routed, and no session carries either of its owners: `human`, which Gas City reserves from session aliases (Gas City `internal/session/names.go` 159-160), or the alias of a sitting whose session has closed. So both skips also drop a task assigned to `human` or to an alias that names the task's own id. A conversation whose session was closed then stays in progress under the sitting's alias until a session under that alias takes it back (section 6). salvage-scope-gate loses its visit arm with orphan-dispose.sh's, and its test keeps the two classifiers in step. The recovery does not reach a gate, even one assigned to a person no session carries, because its candidates come from a plain `gc bd list`, which hides gates (mol-witness-patrol.toml 203, see the platform section). |
| **A ruling's rework child** | `source_ruling_bead` (rework-child.sh, gate-ensure.sh, duplicate-sweep.sh, liveness-sweep.sh, live-work.sh) | Readers unchanged. The value is the ruling sitting's conversation task from now on, so one sign-off's rework is found again whichever gates it answered. |
| **A PR comment's disposition** | `pr_comment_disposition=visit:<id>` (pr-facts.sh; doctor check-feedback-routing-owed) | `human:<id>`, beside the `rework:<id>` it sits with (pr-facts.sh 2811, 2844). pr-facts.sh reads the kind and the named bead's status (`conversation_fix_landed`, pr-facts.sh 186, and the write-back at 4332-4333). The migration rewrites every `visit:<id>` (section 11), naming the gate for a visit it migrated and the visit itself for one closed before the cutover, so the kind says that a person answers the comment, whichever bead records the answer. |
| **Others** | bd-lib.sh's anchor children; bead-rehome.sh's outcome stamp on a visit it rehomes; pr-post.sh's recognition of the reminder's `gc:visit` marker, which pr-visit-comment.sh writes | The anchor children lose the visit. The stamp retires, because a gate is never rehomed, only a bead it blocks. pr-post.sh recognizes the reminder's new marker (section 7). |

**A retry withdraws its own gate before it closes.** pr-facts.sh is the one
caller of `--except-key`, through bead-rehome.sh. It closes an anchor whose PR
was closed with a pre-recorded disposition, and on every attempt it names the
key under which it reports a refused close (pr-facts.sh 1758-1768). Today that
report is a visit, whose `tracks` edge blocks nothing, so the close goes through
once finalize-gate excepts it. The report is now a human gate that blocks the
anchor, and bd refuses an unforced close while it is open (bead-rehome.sh
553-563 closes unforced). So bead-rehome.sh closes in these steps:

1. **It reads what would hold the close.** finalize-gate runs with
   `--except-key` as today. bead-rehome.sh also reads the bead's live blockers
   and open children, which are what an unforced `bd close` refuses on. Anything
   other than the bead's own gates under that key holds the close, and so
   does one of those gates that a person is assigned. Then it resolves and
   closes nothing, and the bead stays open with its successor pointer recorded,
   as a held close leaves it today.
2. **It resolves each excepted gate** with a reason that names the retry and
   carries no outcome word. The retry has not shown the premise gone yet, so no
   quiet period starts, even for a filer that declares one. A sitting
   discussing one of them does not hold
   the close: the retry clears it first, and the sitting learns it at its
   sign-off (section 7).
3. **It closes the bead**, unforced, as today.

Only a blocker or an open child that appeared after step 1 can refuse step 3.
The bead then stays open with its gate withdrawn, and pr-facts.sh files its
report again under the same key, which nothing mutes. A pass that stops between
two steps leaves a state the next pass completes, because a gate already
resolved stays resolved, and resolving it again changes nothing. Every unrelated
blocker still holds the close, because step 1 reads it.

The doctor checks:

- **check-visit-outcome-recorded retires.** A gate's outcome is its close
  reason, written by the close itself. A gate a person closes by hand with no
  headed reason fails safe both ways: its finding stays held, and no quiet
  period starts.
- **check-hq-marooned-work** drops its visit exemption and adds none. Gates are
  already exempt as infrastructure. A conversation is always assigned, to
  `human` in the queue or to its sitting's alias, because every hand-off
  reassigns it rather than releasing it (section 6), and the check passes an
  assigned bead. A conversation someone unassigns by hand is not a state the
  design keeps, and in the city store the check reports an open one as
  marooned work.
  An exemption for every bead that tracks an open bead would also hide a
  marooned patrol finding, which is an unassigned bead that tracks the bead it
  is about, a `bug` unless its filer passes another type
  (`assets/scripts/patrol-finding.sh` 99, 500-523).
- **check-wait-is-an-edge** keeps its terminal-wait exemption and keys it on the
  gate type. `terminal_wait_key = "gc.demand_for"` in `lifecycle/lifecycle.toml`
  `[holds]` becomes a type rule.
- **check-blocked-work-armed** keeps its rule. A visit's route no longer counts
  as a dispatch path, and a work bead blocked by a human gate needs its arm,
  which await-ruling.sh writes.
- **check-state-space** adds every retired key to `RETIRED_KEYS`, so a leftover
  on a live bead is reported.
- **check-until-resolved-owed**, which reports a bead whose `until` targets
  have all closed and which the deferred-dispatch pass has left undisposed
  (see the platform section), changes only its finding text.
- **check-feedback-routing-owed** reads only whether a disposition is present,
  so only its comments change.
- **check-armed-dispatch-owed** takes hold-lib.sh's demand-gate rule from the
  gate type.
- **check-routed-work-claimable** does not change. A conversation is assigned,
  never routed.

## 5. How a human gate reaches the operator

Gas City's native reach for a human gate is core's two orders.
notify-on-human-gate-creation mails a gate's addressee when the gate is
created, and nudges an addressee that is a session.
renudge-stale-human-gates mails again while the gate stays open past an hour.
Both address the gate's assignee, then `gc.deferred_assignee`, then
`$GC_ESCALATION_RECIPIENT`, which defaults to the `human` mailbox (see the
platform section). A gate the operator owes is filed open and unassigned, so
every such gate mails that mailbox, and the operator reads the board, not mail.
That is why the town's city.toml already disables renudge-stale-human-gates
(304-311). notification-wisp-reap exists to close the creation notices.

**This city opts out of core's reminders, and the board alone is the reach.**
The town's city.toml adds an override that disables
notify-on-human-gate-creation beside the renudge override, and the comment over
both names the board as this city's reach for a human gate. The override is a
commit to the town repo, not to gc-toolkit. It lands before the cutover, so the
gates the migration files mail nobody. The opt-out is this city's choice of
addressee, not a claim that the orders miss anything: a city whose operator
reads mail keeps them, and every gate this design files reaches that operator
through them unchanged.

**Re-asking is the board's ordering.** An open gate stays on the board, owed and
ordered by how long it has been owed, until it is cleared, its filer withdraws
it, or, for the gate that put a recommendation to the operator, Accept clears it
(section 8). Nothing re-mails. No session claims a gate, so a gate a sitting is
discussing is still open and unassigned: in a city that runs core's two orders,
they keep asking until the answer lands, which is the native reading of a debt a
person still owes. In this city both are off.

**notification-wisp-reap keeps one pass.** Its gate-notice pass retires with the
notify order. Its second pass collapses repeated `ESCALATION:` mails, which
core's maintenance scripts send through core's escalate.sh hook. Those mails are
not human gates, so that pass stays.

`docs/human-engagement.md` on main names the visit as this city's reach for a
human gate and the notify order's mail as a record nobody reads, in "How the
model rides the platform" and in "How a sitting ends: a demand bead and an
edge". Unit C rewrites both to name core's two orders as the native reach, off
in this city, and the board as this city's reach.
`docs/gascity/human-engagement.md` states what the two orders do, which does not
change.

The alternative was to keep the orders and give them an addressee someone reads.
The town can point the two orders at another recipient by setting
`GC_ESCALATION_RECIPIENT` in an order override's environment (see the platform
section). Any recipient is still a mailbox or a session, and the operator reads
neither. They have no session to nudge, and pointing the orders at an agent would
wake that agent on every gate. The alternative was rejected.

## 6. The sitting, its claim and its recovery

**A sitting's session is a manual session of the converse agent the operator
chose, and it holds one conversation.** It is a manual session because the pool
execution backstop drains a pool session that holds in-progress work and is
quiet for 90 seconds, with no attachment exemption, and a sitting is quiet
whenever the operator is reading or thinking (see the platform section). A
manual session has no such clock: its work closing does not end it, idleness
only sleeps it, and attaching wakes it. Engage starts every sitting with
`gc session new`, which gives the session the origin `manual`. Gas City marks a
session `pool_managed` only when the controller started it as neither a named
nor a manual session, and the backstop governs only those, so a sitting's
session is never a pool session.

**Engage** (gc-helm.sh engage, the tmux picker, and helm-svc's engage route)
takes these steps:

1. **It takes the bead.** Given a bead, engage works on that bead. Given a
   gate, it works on the bead the gate blocks, read from the gate's `blocks`
   dependents (section 1), because a conversation always tracks a bead, never
   a gate (Terms). When the gate blocks more than one bead, engage names them
   and starts nothing, so the operator engages the one they mean. When it
   blocks none, engage says so and starts nothing: the gate holds nothing, and
   the operator clears it.
2. **It reads the bead's conversations:** the tasks that are not closed and
   track the bead (`bd dep list <bead> --direction=up --type tracks`), kept
   when the task is assigned to `human` or to an alias that names the task's
   own id (section 1). The session list says which of those sittings are live.
   A converse session is one whose template contains `converse`, as
   converse-reap reads it today (converse-reap.sh 72-79). A closed session is
   not in the list (see the platform section), so a conversation whose
   sitting's session has closed is found by its assignee.
3. **A concern opens a fresh conversation.** A concern passed with
   `--reason`, `--template` or `--skill`, or the operator's choice of a new
   conversation when engage asks, files a new task (section 1) whose
   description is that concern, even when the bead has a conversation in the
   queue or in session, because a distinct concern is a distinct dialogue
   (Terms). Today's engage files a fresh visit for one the same way
   (gc-helm.sh 3886-3898, 3982-3995).
4. **Without one, engage attaches first.** A conversation held by a session
   in the list is a live sitting, and engage attaches the operator to it
   rather than starting a second. Otherwise it takes a conversation in the
   operator's queue, or one whose session has closed, or files a new one
   (section 1). This attach-first default is what keeps a bead to one sitting
   in the normal path, and it is a convention, not a guarantee (below).
5. **It starts the sitting:** `gc session new converse-<model> --alias <task>
   --no-attach`, as today with the visit's id. Gas City reserves the alias
   under a city-wide lock and refuses it while another session that is not
   closed holds it (see the platform section), so of two engages of one task
   only one starts a sitting. The fallback for an id the runtime refuses as an
   alias stays, under the prefix `c-` where it was `v-`. Engage still starts
   the session before it binds the task, because the alias is the reservation,
   and a bind that loses its race closes the session it started (gc-helm.sh
   4145-4150, 4295-4323). A session still in the list under that alias that no
   longer holds the task, as a sitting cut short leaves it (section 7), is
   closed first, because a session that is not closed keeps its alias.
6. **It binds the task to the session's alias** with
   `gc bd update <task> --if-assignee <holder> --assignee <alias>`, where the
   holder is the task's assignee as engage read or filed it: `human`, or that
   alias. bd
   writes the bind only while the task's assignee still reads that holder (see
   the platform section). A racing engage, or a hand-off that landed first,
   makes the bind miss, and the engage that missed closes the session it
   started. The task is known as held from the bind on. Then engage attaches
   the operator, as today.

**The alias and the bind keep a second sitting off a conversation.** Only one
session that is not closed can hold the task's alias, and only one bind from
the holder engage read can land. The sitting then claims its task with a plain
`gc hook --claim`. The default work query finds the task assigned to the
session, open through its second tier and in progress through its first, and
its routed tier is closed to a session whose alias is not its template's name
(see the platform section). So converse needs no work query of its own. The
claim sets `in_progress`, a lease and the session stamps, under the session's
alias. It excludes nothing the bind has not already excluded: the hook claim
takes only a bead already assigned to the session, and bd's claim refuses a
bead another actor holds, `human` among them. converse-claim.sh retires.

**One sitting per bead is a convention, not a guarantee.** The board always
shows a bead's conversations on its one row, and engage's attach-first default
keeps the bead to one sitting in the normal path. Some paths still give two
live sittings where the default gives one. A concern the operator opens as its own
conversation (step 3) and two engages racing on a bead with no conversation,
which each file one, put two sittings on one bead. A gate that blocks two beads
is served by each bead's sitting. The alias and the bind keep a second sitting
off one conversation, not off one bead, so nothing refuses any of these. The
board folds both sittings onto the bead's row, either may answer a gate, and the
first resolve wins (section 7). Engage warns when it starts a sitting while
another live sitting serves the bead, or a gate the bead waits on.

**No sitting is demand-spawned.** No pool's demand reaches a human gate, because
`bd ready` excludes gates. A work query generates no wake demand, and a
conversation task is assigned, never routed. Assigned work wakes only the
session whose identity it carries, and a conversation in the operator's queue
is assigned to `human`, which no session carries. So a sitting starts only when
the operator engages.

The converse templates still declare a pool at zero, and the declaration stays.
Their `min_active_sessions = 0` is Gas City's default written out, so the
controller keeps no sitting running. They carry no `scale_check`, and no work
is routed to a converse template, so no demand pass counts anything for one
(see the platform section). pool-demand-wiring.test.sh keeps its three converse
rules. They serve no demand-spawned sitting: they are what keeps the paragraph
above true. A minimum above 0 would start sittings with no conversation behind
them, a `scale_check` would hand the controller a count to spawn them from, and
a work query of its own would change what a sitting's claim returns.

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

A session under any other alias finds nothing to claim, because the task is
assigned to the sitting's alias and bd's claim refuses a bead another actor
holds. Nothing in Gas City releases a sitting's claim on its own: on_death runs
only for pool instances, orphan-sweep leaves a bead it cannot show orphaned,
and `gc session close` releases nothing held under the alias (see the platform
section). The pack's witness recovery skips the task too (section 4). The alias
is the way back in.

**A hand-off returns the conversation to the operator's queue.** A sitting that
stops before the conversation ends, and a person who means to move a
conversation to another sitting, both use one guarded update:

```
gc bd update <task> --if-assignee <holder> --assignee human --status open
```

bd writes it only while the named sitting still holds the task, and the change
of holder drops the claim's lease (see the platform section). The task is then
the open, queued conversation it was before any sitting took it, so the board
shows it owed and engage takes it again. A sitting cut short returns its task
this way (section 7). Gas City's `gc bd release-if-current` would leave the
task open and assigned to nobody, a state neither the board nor engage reads as
a conversation, so no conversation is released with it (see the platform
section). Only the migration uses it, on a visit it is about to close
(section 11). The board gains no read for an unassigned bead that tracks an open bead either,
because a patrol finding is one and would be shown as a conversation
(section 4). No gate needs a reclaim, because no session claims one, so
engage's reclaim from a gone sitting retires (gc-helm.sh 4057-4108).

**The put-back retires, and so does a shared session serving many subjects.** A
sitting's session is bound to one conversation task, which names its bead. The
put-back released the claims outside the sitting's group (converse-claim.sh
305-344). The work query offers the session only what is assigned to its own
identities, which is its task, so the put-back has nothing left to do.

**Same-subject continuity comes from the task, not from the continuation
group.** Gas City's continuation preassignment does not reach a gate (see the
platform section). It is not needed: the task names the bead, and the sitting
serves every human gate on it. A gate filed on the bead while the sitting runs
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
session's alias, and it strips the fallback's `c-` prefix. Today's reap skips
an alias under the `v-` prefix, so those sessions stay unreaped
(converse-reap.sh 110-112). The cutover closes every session whose alias names
a visit (section 11), so the reap reads no `v-` alias. Its retirement trigger:
Gas City ends a manual session once its claimed work has closed and nobody is
attached. Unit C records it in `docs/warrants.md` with that trigger.

## 7. Hold, record and close

**The record** is unchanged doctrine: the sitting appends to the subject's
notes, and it writes the subject's headline with gc-helm.sh takeaway.

**A hold** is the operator owing an answer later. The sitting keeps its task
claimed, and the session stays, because the converse agents keep
`idle_timeout = "0"`. The hold appends to the subject's notes and writes what
the operator owes as the subject's headline. The gates the sitting serves
stay open and owed. When something must wait for the later answer and no open
gate holds it, as when the merge must not land before the operator rules,
the sitting files a human gate through the helper with the key `conversation`,
on the bead that must wait: the anchor when the merge must wait, or the one
member whose work waits. converse-hold.sh retires, and so do its demand, its
`gc.hold_demand` stamp, its `gc.gate_visit` stamp and `--hold-merge`. An
unanchored subject moves to `held` and back through lifecycle.sh, now from the
hold and settle skills, and only with a gate that blocks it, because
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

**Clearing a gate** is one call, whether the gate asked for an answer, an
approval or an action:

```
gc bd gate resolve <gate> --reason "<outcome>: <one line>"
```

The outcome is one of three words:

- `ruled`: the operator decided, approved or did what the gate asked. It
  releases a needs-you finding.
- `moot`: the premise no longer holds. A filer's retract writes this. It starts
  the quiet period of a filer that declares one (section 2).
- `benign`: the premise holds, but it needs nobody. It starts the quiet period
  of a filer that declares one.

The sitting owns no window. It writes the reason, and the filer's call decides
what the reason mutes.

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
means that another answer reached the gate first. That can be a retract, an
Accept, another sitting, or a person at the command line. The sign-off reports
that answer to the operator instead of claiming its own. Each of those answers
is legal, nothing prevents it, and the one that loses is told.

**Leaving a gate open** needs nothing, because the sitting never claimed it.
A sitting cut short writes its record, leaves its gates open and owed,
returns its task to the operator's queue with the hand-off of section 6, and
drains, as a cut-short sitting drains today. converse-reap closes the session
once nobody is attached, or the next engagement closes it first, and that
engagement starts a fresh session on the same conversation (section 6). The
ruled-no sign-off's second demand on the anchor retires, because a gate
that holds the anchor already blocks it.

**Dismiss** ends a sitting. It closes the sitting's task with a reason that
names the dismissal, and it answers nothing. converse-reap then closes the
session once nobody is attached, as it closes a dismissed sitting's session
today, so the pane is never taken from under the operator who pressed the key.
The close falls back to `--force` when bd refuses an operator closing a task its
sitting holds, as dismiss does for a visit today (gc-helm.sh 2682-2687). Today
dismiss closes the visit, which for a visit escalate.sh filed takes its matter
off the board until its detector files it again. After this, the gate stays on
the board. That is the cost the seventh decision names.

**There is no fold.** A sitting serves the human gates of the bead its
conversation tracks. Two conversations on one bead are two tasks, and the board
folds both onto the bead's row. A duplicate gate from a race is cleared with the
same reason as its twin. Today a fold also moved `pr_number`, `pr_url` and
`anchor_bead` to the holder so the merge stayed held. A gate holds the merge
through its own edge. converse-fold.sh, `visit-close.sh --into` and
`gc.folded_into` retire.

**converse-signoff.sh stays as one call**, rewritten. It is glue the epic's third
test allows, because the settle skill needs its steps in one order every time:

1. route a ruling's rework through converse-rework.sh, unchanged, with the
   conversation task as `source_ruling_bead`;
2. write the subject's headline;
3. resolve each gate the ruling answers, read each back, and report any that
   another answer reached first;
4. release a `held` subject;
5. close the conversation task;
6. update the PR reminder.

`gc.ruling`, `gc.pr_visit_summary` and `gc.pr_visit_actions` retire. The ruling
is the resolve reason, and the summary and actions are passed to the reminder
directly.

**The PR reminder stays** (tk-wxrh1z): a comment on the subject's PR when a
sitting engages, edited in place when it ends. It is keyed by the conversation
task's id, and pr-visit-comment.sh is renamed pr-sitting-comment.sh. Its marker
`<!-- gc:visit:<id> -->` becomes `<!-- gc:sitting:<task> -->`. pr-post.sh counts
a post carrying either marker as the city's own (pr-post.sh 72-76), because
reminders posted before the cutover keep the old one (section 10).

## 8. The board's read path

**What it reads.** The board reads, per store, the human gates that are open,
and those closed inside the sittings window (default 24 hours), with a
gate-typed search, because a plain listing hides gates and a gate carries no
pack marker. The supervisor backend already unions a `type=gate` page into its
scan (`services/helm/internal/source/supervisor.go` 554-585). What each gate
blocks comes from the gate's own `blocks` dependents. The gather already makes
one batched inbound read per rig and status pass (`attachEdges`,
`services/helm/internal/source/beads.go` 697-745). Today that read covers only
the anchors the gather keeps and only their `parent-child` children (beads.go
665-671 and 755), and the beads source gathers no gate (beads.go 471), so the
board adds the gates to that read and keeps their `blocks` dependents (unit C,
section 12). The supervisor backend has no such read, but its scan rows carry
each bead's own dependencies, so it inverts their `blocks` edges, as it already
inverts their `parent-child` edges to find children (`supervisor.go` 655-662).
It reads the conversations from their tasks: the tasks
that are not closed, track a bead, and are assigned to `human` or to an alias
that names the task's own id (section 1). The session list it already reads for
owner liveness (`services/helm/internal/source/gccli.go` 155-166) says which of
those sittings are live, and it leaves a closed session out. A gate's subjects
are the beads it blocks, and a conversation's subject is the one bead it tracks
(Terms). `visitFilter`, `resolveVisitSubjects` and the visit-identity spelling
retire.

**How they fold.** `wrapperTarget` (derive.go 2571-2595) treats a human gate as
a wrapper on each bead it blocks, and a conversation as a wrapper on the bead
it tracks, so a gate and a conversation each fold onto the rows of the
beads they concern. A gate that blocks two beads folds onto both their rows, and
each row lists it among what it waits on, as a bead blocked by a demand lists
the demand today (`waitingSplit`, derive.go 317). A gate none of whose beads has
a live row keeps a row of its own that states what it asks, as a wrapper whose
subject has no row does today (`foldWrappers`, derive.go 2440-2446), so no open
gate is off the board. `applyFold` keeps its meanings:

- **Held:** a bead with an open human gate or an open conversation is held. The
  stranded arm of `severity` (derive.go 696) reads it as before.
- **Owed:** an open human gate makes each bead it blocks owed even while work on
  the bead is in flight, which is the visit's rule today. A demand alone yields
  to live work (derive.go 2666), but gate-visit-sweep gives every unassigned
  demand a visit, so a demand already follows the visit's rule in effect. One
  rule keeps that behavior. A conversation not in session makes its bead owed,
  as an open visit does: one in the operator's queue, or one whose sitting's
  session has closed. A conversation in session does not, because the operator
  is in it.
- **Owed since:** the earliest open gate's or owed conversation's
  `updated_at`, which is what the visit's clock was.
- **Needs:** the gate's title, or `N× — a · b` over several. A held row with
  no open gate shows its conversation's title, or reads "in conversation"
  while a sitting holds it, as a held row reads today (derive.go 976-983).

**In session:** a bead is in session when one of its conversations is held by a
session that is not closed, read against the session list the way the board
reads every owner's liveness (derive.go 79-83). Today `engagedVisit` reads a
visit's status, session and assignee, never whether the session lives
(derive.go 432-442), so a dead sitting still reads engaged. `classifyVisits`
becomes the same classification over conversations, read against liveness.

**Accept clears the recommendation's gate and nothing else.** A recommendation
is `gc.recommended_formula` on the bead. Only first-reaction-dispose.sh's
recommend exit sets it (first-reaction-dispose.sh 822-841), and that exit files
the human gate that puts it to the operator through the helper with the key
`first-reaction`, blocking the bead (section 3). So the recommendation's gate is
the open human gate under the key `first-reaction` among the gates the bead's
`blocks` edges reach, or both of them when a race filed two. The `--visit`
option, which held a recommendation on a visit the caller filed, retires
(section 3), so no recommendation rides on another gate. A bead whose
recommendation has no open gate under that key offers Discuss only, because
nothing asks the operator to accept it.

**The graph explains itself.** A reader of the beads alone, with no knowledge of
the pack, can tell which gate carries the recommendation and what it blocks. The
gate's title is the recommendation as the operator is asked to accept it, and
its framing names the formula an Accept slings and the reason the reaction
gives for it. Its `blocks` edge, and the first line bd writes into its
description, name the bead it holds. The bead's `gc.recommended_formula` is the
copy Accept reads, and the gate carries no pack key. A gate never gets a first
reaction of its own, because the reaction's picker admits only the issue types
on its allowlist, `task`, `bug`, `feature` and `spike` by default
(`tools/gc-proactive.sh` 64-73).

Accept is offered while all three hold:

1. The bead carries `gc.recommended_formula`.
2. The recommendation's gate is open and unassigned. A gate assigned to a person
   is that person's to clear.
3. No other open human gate blocks the bead. The one reader rule counts every
   one, whichever bead it was filed on and whoever is assigned to it.

A live sitting on the bead does not withhold Accept. gc-helm.sh accept warns
that a sitting is discussing the bead, and the sitting learns at its sign-off
that the recommendation's gate was cleared (section 7).

**Why Accept clears one gate.** Separate situations on one bead stay separate
gates (section 2), and each gate's close does something of its own. A `ruled:`
close releases a needs-you finding (section 4). Any close releases what waits on
the gate, so a rework child waiting on its anchor's bring-current gate would be
re-slung without the decision it waits for. An Accept that resolved every gate
on the bead would spend one click as several answers the operator never gave.
Today's Accept already closes everything waiting on the operator there. It
resolves every open, unassigned demand on the bead (gc-helm.sh 2830-2849) and
dismisses every visit (3151-3156). A dismissed visit carries no `gc.ruling`, so
a needs-you finding whose visit Accept dismissed stays held with its visit gone
from the board. Carried over to gates, the same sweep would close the finding's
gate with `ruled:` and release the finding on a ruling nobody gave.

**Why it waits for the others.** Every human gate blocks what waits on it, so
the bead's next step waits for each gate that blocks it (section 1). A formula
sling reads no `blocks` edge (`docs/gascity/routing-model.md` on main, "A
`blocks` dep between work beads does not hold a graph.v2 dispatch"). An Accept
that resolved only its own gate while another stayed open would start the work
before that gate was cleared. mol-polecat-work's load-context would cancel such
a run, and a formula with no such check would run past the gate. So Accept is
offered only once the recommendation's gate is the last human gate blocking the
bead.

While another human gate blocks the bead, the row offers Discuss, and the wire
field `accept_withheld` names each open gate that holds Accept back. Discuss
engages the bead, and its sitting answers each of the bead's gates on its own
terms. A gate filed on another bead that this bead also waits on is about both,
so either bead's sitting can answer it. Once the others are cleared or
withdrawn, the row offers Accept again if the recommendation's gate is still
open and unassigned.

gc-helm.sh accept re-reads the three conditions live before it writes anything,
because a board row can be stale and a command can be copied. When one fails, it
refuses and writes nothing. When the third fails, the refusal names each open
gate by id and title, with Discuss as the way forward. Otherwise it answers in
these steps:

1. **It resolves the recommendation's gate** with the reason
   `ruled: accepted <formula>`, followed by a token unique to this run.
2. **It reads the gate back, and goes on only when the close reason is its
   own.** bd resolves a gate that is already closed without changing it, and
   reports success either way (see the platform section). A reason that is not
   its own write means another answer reached the gate first: a sitting's
   ruling, a filer's withdrawal, or a second Accept. Accept reports that
   answer, slings nothing and reopens nothing, because the first answer wins.
   The token tells two Accepts apart, since both write the same words, so two
   Accepts on one gate sling once.
3. **It reads back that no open human gate blocks the bead.** A gate filed
   between the live read and the resolve shows here.
4. **It slings the formula.**
5. **It records the dispatch** as today: `gc.recommended_formula_dispatched`
   lands in the write that strips `gc.recommended_formula`.

When step 3 finds a gate, or the sling fails, Accept reopens the
recommendation's gate with `bd reopen`, reads it back as open, and dispatches
nothing. That path starts only from Accept's own accepted close, so it never
undoes another answer. A reopen clears the close and its reason, and blocks
again what the gate blocked (see the platform section), as today's Accept puts
a demand back after a failed sling (gc-helm.sh 2901-2921). An answer that met
Accept's close in that window read Accept's answer and reported it. The
reopened gate is back on the board, owed, and that answer can be given again.
The resolve comes before the sling, today's order (gc-helm.sh 3110-3138), so the
run never finds the recommendation's own gate open. A re-run that finds the
dispatch marker skips the three conditions, since the run that wrote it already
cleared the gate. It finishes that record and never slings again. Accept no
longer runs dismiss. A sitting on the bead is the operator's to end.

**Ranking is unchanged.** `rankScore` (derive.go 734-741) and its inputs are
untouched. Every input a visit supplied, held and the owed clock among them, now
comes from a human gate or a conversation. A board test pins that a bead ranks
the same with a gate as it did with a visit, and the same with a queued
conversation as with an unengaged visit the operator opened.

**The wire model.** In `services/helm/internal/board/model.go` and
`services/helm/web/src/contract.ts`, `held`, `accept_formula` and
`recommendation` keep their meaning, and `acceptable` reads Accept's three
conditions. `accept_withheld` is new. It is set on a row that meets Accept's
first two conditions and fails the third, and it names the gates that fail
it the way Needs names gates: the gate's title, or `N× — a · b` over several. It
is null on every other row. The web and text boards print it beside Discuss as
the reason Accept is not offered. `visit_state` is renamed `sitting_state`. The
web marker reads "in session" or "waiting" without the word visit. The sittings
card lists the conversations, from their tasks and the session list. The phase
input gctk pr-status and the board share, `OpenVisit`, is renamed
`OpenHumanGate`, and it reads an open human gate that blocks the anchor.

**The verbs** (gc-helm.sh, and helm-svc's POST routes that run it):

| Verb | After |
|---|---|
| engage, `--new-subject` | Section 6. `--new-subject` still creates the subject first (gc.origin=operator), then engages it. |
| open (POST /helm/open) | Files a conversation in the operator's queue without engaging it. `parseOpenStdout` keeps its sentences. `--allow-duplicate` keeps its meaning, a fresh conversation even when the bead has one, which engage passes for a concern (section 6). Without it, a second concern on a bead whose conversation waits in the queue joins that conversation: open appends the new reason and body to that task's notes. |
| accept (POST /helm/accept) | Resolves only the recommendation's gate, reads it back, and slings only when the gate records Accept's own answer, as above. While another human gate blocks the bead, it refuses, writes nothing and names each open gate. It runs no dismiss. |
| dismiss (POST /helm/dismiss) | Ends the sitting (section 7). On a subject with no live sitting it does nothing and says so. |
| park, takeaway | Unchanged. park files its gate with `bd create --type=gate` (gc-helm.sh 1939), so the gate carries no await type, by design: it is a plain blocker that pauses the parked bead, not a human gate, and a reader takes an empty await type as declaring nothing (see the platform section). takeaway writes the subject's headline. |
| demand | Retires. Its callers move to the helper or to the native call (section 2). |

**The operator's hands do not change.** The tmux bindings keep their keys and
what they show:

- **prefix+b and prefix+B** (tmux-pick-helm.sh) engage a picked row.
- **prefix+a** runs the operator's intake. Its script, tmux-visit-prompt.sh, is
  renamed tmux-intake-prompt.sh, with its test and its bind line in
  tmux-bindings.sh (68). gc-visit-open.sh is renamed operator-intake.sh,
  because it never filed a visit itself. Its fallback, which ran
  `gc-helm.sh open`, files a conversation in the queue. The
  prompt's match for "first reaction slung", which the intake no longer prints,
  is corrected with it.
- **prefix+A** (tmux-new-subject.sh) runs `engage --new-subject`.
- **prefix+X** (tmux-dismiss-sitting.sh) runs dismiss under the pane's session.

## 9. Skills, prompts and fragments

The sitting doctrine stays: premise re-check, prep, the hand-back's shape and the
record discipline. Only text that depends on the visit bead changes.

| File | What changes |
|---|---|
| `skills/converse-recheck-premise` | The premise is read from the conversation's ask and from each gate's title and framing. A moot or benign verdict on a gate is `gc bd gate resolve` with that headword, in place of converse-close-out.sh. A conversation whose premise has died is closed with the record written. |
| `skills/converse-prep` | It reads the conversation task with its notes, its bead's gates with theirs, and the subject's notes. A recheck command named in a gate's framing, or in the notes a migrated visit left (section 11), is run, in place of the `visit.recheck` hook. |
| `skills/converse-hold` | The hold of section 7, in place of converse-hold.sh, the visit demand and `--hold-merge`. The dismiss line at the foot of every framing stays. |
| `skills/converse-settle` | converse-signoff.sh's new shape. The resolve replaces visit-close.sh and the guarded stamps, each resolve is read back, and the reminder update passes its text directly. A cross-store follow-up waits through the helper. |
| `skills/converse-continue` | It re-reads its bead's gates and serves any new one, and it re-runs `gc hook --claim` after a restart. |
| `skills/waits` | One section on waiting for a person: a human gate on the bead that waits, filed through human-gate.sh when one gate per key or a quiet window matters and with `gc bd gate create` otherwise, and await-ruling.sh arms the re-sling. An action only a named person can perform, when work waits on it, is such a gate assigned to that person after the create. Work a person owes that nothing waits on is an ordinary bead assigned to them. The skill states that a gate on a bead with open children pauses its unstarted parts, so the filer names the member that waits when only one does, and that a situation with no bead of its own is a patrol finding, because the helper refuses a wisp (section 2). The demand-gate, visit and gate-visit-sweep sections go. |
| `skills/prs` | A merge hold is a human gate on the anchor through the helper. The not-needed successor names the gate. |
| `skills/work` | Accept and the intake are described on gates and conversations. Taking a recommendation in a sitting clears the recommendation's gate alone, as Accept does, and its sling waits until no other human gate blocks the bead (section 8). "Ask for a visit" becomes "ask the operator". |
| `skills/handoff` | A converse session closes its conversation task, or returns it with the hand-off of section 6, before it drains. |
| `skills/learning-distill` | The contention gate goes through the helper. |
| `agents/_converse/prompt.template.md` | Its definitions of visit, subject, topic and demand become this spec's four terms, subject, human gate, conversation and sitting, worded as the Terms word them, and it uses no retired word. Universe keeps its definition, and hold is defined as section 7 states it. The claim block becomes `gc hook --claim`. The BEGAN rules, the fold and the finish arm go. The cut-short path returns the task to the queue. The ending says the thread ends when its conversation closes. |
| `agents/converse-{opus,fable,codex}/agent.toml` | Their header comments say the alias is the conversation task's id. They gain no work query. |
| `template-fragments/visit-close.template.md` | Renamed `human-gate-withdraw.template.md`, and its `define` with it, so the include line in each prompt that includes it changes: the deacon, mechanik, proactive, refinery and witness prompts. A role never resolves another role's gate, and withdraws its own with `--retract`. |
| `template-fragments/polecat-doctrine.template.md`, `template-fragments/pool-worker-no-consent-ui.template.md` | The decline wording of section 3, with its sentence that the gate holds the work bead and every part filed under it. The calls are unchanged. |

Every prompt change re-renders `generated/seed-audit/agents/*.md` in the same
commit, because gctk merge holds a merge whose renders are stale.

## 10. What retires, and the keys

**The retire list.** The initiative's list was confirmed on main, and the rest of
main's visit machinery was added to it:

| Piece | Fate |
|---|---|
| The visit bead kind, `task_kind=visit` | Retires. A conversation is an ordinary task. |
| gate-visit-sweep, its order and script | Retires, and so does its report of a gate whose bead has closed: the board gives such a gate a row of its own (section 8). |
| converse-claim.sh, converse-fold.sh, converse-close-out.sh, converse-hold.sh | Retire. |
| visit-close.sh, the guarded close | Retires. |
| The BEGAN and `gc.hold_demand` restart forensics | Retire. |
| engage's reclaim from a gone sitting | Retires. No session claims a gate, and a new session under a closed sitting's alias takes its task back (section 6). |
| mol-visit.toml, and every copy of the gate-visit block with gate-visit.test.sh | Retire. |
| visit-identity.sh | Retires, with its Go readings: gctk pr-status's `visitCovers` and the board's `resolveVisitSubjects`. gcbd's `DependsOn`, which only `visitCovers` calls, goes with the `gcbd_test.go` case that pins its edge spellings. |
| converse-recheck-hook.sh | Retires with `visit.recheck`. |
| orphan-dispose.sh's visit arm | Retires. |
| gc-helm.sh demand | Retires. Its callers file through the helper or the native call, and an action a named person must perform is a human gate assigned to them (section 2). |
| escalate.sh's own store derivation, its escalation-rig.sh call and the `--db` pin on every call, and the derivations in the deacon prompt and mol-dog-shutdown-dance | Retire. `gc bd` runs each call in the bead's own store (section 2). escalation-rig.sh has no caller left and retires with escalation-rig.test.sh. bead-store.sh stays for its other callers. |
| escalate.sh's ephemeral-subject redirect, and the standing bucket it mints | Retires. A wisp is refused, and the callers that passed a wisp, or a bead they could not read, file patrol findings (section 2). |
| notification-wisp-reap | Its gate-notice pass retires, and its pass over core's `ESCALATION:` mails stays. |
| converse-reap, its order and script | Stays, keyed on conversation tasks (section 6). |
| gc-visit-open.sh | Renamed operator-intake.sh, and its fallback files a conversation. |
| pr-visit-comment.sh | Renamed pr-sitting-comment.sh, and keyed by the conversation task. |
| `template-fragments/visit-close.template.md` | Renamed human-gate-withdraw.template.md. |
| finalize-gate.sh's `clause_no_open_visit` | Re-expressed on gates (section 4). |
| liveness-recheck.sh's form that takes a visit id | Retires. The census rides the re-check command in the gate's message (section 4). |

**Retired words in the names that stay.** Each surface this design keeps that
still carries a retired word in its name (Terms) is renamed, or carries a dated
debt with the trigger that retires it:

| Name | Fate |
|---|---|
| `OpenVisit`, the `prstatus.Facts` phase input gctk pr-status and the board share, and gctk's `anchorOpenVisit` | Renamed `OpenHumanGate` and `anchorOpenHumanGate` (sections 4 and 8). |
| `liveness-recheck.sh <visit-id>`, the command a migrated liveness gate would have named | Gone. The migration writes the visit's census as the new command, `--ids`, `--carried` and `--pass-at` (section 11), so no gate names a visit's id to re-check. |
| tmux-visit-prompt.sh, behind `prefix + a` | Renamed tmux-intake-prompt.sh, with its test and its bind line (section 8). |
| engage's `v-` alias fallback | Renamed `c-` (section 6). The cutover closes every converse session whose alias names a visit (section 11), so no reader keeps `v-`. |
| `visit_state` on the board's wire | Renamed `sitting_state` (section 8). |
| the PR reminder's marker `<!-- gc:visit:<id> -->` | Renamed `<!-- gc:sitting:<task> -->` (section 7). pr-post.sh keeps counting a post that carries the old marker as the city's own. Debt, dated 2026-10-20: the old marker is recognized while an open PR carries a reminder posted before the cutover, so that reminder never reads as an unanswered human comment. Trigger: no open PR carries one. The cutover's follow-up (section 12) checks, and drops the old marker or files its removal for when the last such PR closes. |
| escalate.sh, the helper | Renamed human-gate.sh (section 2). The old name stays as a hand-off that runs human-gate.sh with the same arguments and does nothing of its own. Debt, dated 2026-10-21: the hand-off stays while an open step bead's description names escalate.sh, because a run keeps the text its steps were poured with (see the platform section), or while a session that read the old name in its prompt before the cutover still runs. Trigger: neither remains. The cutover's follow-up (section 12) checks, and deletes the hand-off or files its deletion for when the last such run closes. |
| escalate.test.sh, escalation-binding.test.sh, refinery-stuck-escalate.test.sh and the `*-escalation-wiring.test.sh` set | Renamed in unit A beside the change to what each pins (below): escalate.test.sh becomes human-gate.test.sh, and the others take names in the Terms' words. |

**The keys.** A key goes only when its last reader moves. Each retired key joins
`RETIRED_KEYS` in `doctor/check-state-space/run.sh`. The migration script reads
some of these keys on the beads it converts: `escalation_key`, `gc.demand_for`,
`gc.demand_topic`, `gc.ruling`, `gc.folded_into`, `visit.recheck`,
`sweep.new_ids`, `sweep.carried_ids`, `sweep.pass_at`, `finding.visit` and
`finding.ruling_visit` (section 11). It removes
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
| `sweep.new_ids`, `sweep.carried_ids`, `sweep.pass_at` | Go. The census rides the re-check command in the gate's message (section 4). The migration reads them once, on open visits, to write that command (section 11). | liveness-sweep.sh, their writer, and its re-file check; liveness-recheck.sh's visit form |
| `escalation_key` | Goes. The gate's await id is the key. | await-ruling.sh, branch-supersession.sh, pr-facts.sh, finding.sh, finalize-gate.sh `--except-key`, mol-witness-patrol's check-refinery, converse-hold.sh, converse-signoff.sh, converse-fold.sh, the formula copies |
| `escalation_raised_by` | Goes, with the redirect that wrote it. | None. It is never read. |
| `escalation.recurrences`, `escalation.recurrence_last` | Go. | escalate.sh's tally |
| `triage.scope` | Stays for the liveness sweep's buckets. The helper mints no ephemeral-subject bucket any more. | The triage subject is not a visit. |
| `triage.last_seen` | Stays. Its registry text is corrected: it holds the in-scope ids, not a time. | |
| `triage.hold` | Stays. It has readers outside visits and no writer, and its retirement belongs to the liveness subsystem. | |
| `gc.outcome` and `gc.outcome_reason` on visits | Go. `gc.outcome` on molecule steps stays. | The board's sittings headline, and liveness-sweep.sh's re-file check, which reads `dispositioned` there (section 4). Their writers stop with it: visit-close.sh, gc-helm.sh dismiss, and bead-rehome.sh on a visit it rehomes. |
| `finding.visit` | Renamed `finding.gate`. The migration converts it on every live finding (section 11). | finding.sh, review-answer.sh |
| `finding.ruling_visit` | Renamed `finding.ruling_bead`. The migration renames it on every finding that carries it (section 11). | pr-facts.sh's review dismissal, review-answer.sh |
| `source_ruling_bead` | Stays. Its value is the ruling sitting's conversation task from now on. | |
| `epic_ruling_evidence` | Stays. Its value is the gate's id from now on. | |
| `pr_number`, `pr_url`, `anchor_bead` as stamped on visits | No longer stamped on gates. The keys stay on anchors and their children. | gctk merge's `pr_number` probe, gctk pr-status's in-flight count |
| `gc.demand_for` | Goes. | gc-helm.sh, its writer; converse-claim.sh, converse-signoff.sh and gate-visit-sweep.sh; liveness-classify.sh, with liveness-sweep.sh and liveness-sweep-precheck.sh, which source it; liveness-recheck.sh; hold-lib.sh, with deferred-dispatch.sh through it; live-work.sh; pr-facts.sh; pre-open-rebase.sh; the board; check-blocked-work-armed; check-wait-is-an-edge's `terminal_wait_key` |
| `gc.demand_topic` (written and read, never registered) | Goes. | gc-helm.sh demand, converse-signoff.sh |
| `gc.routed_to=human` and `gc.takeaway` on gates | No longer stamped on gates. Both stay the subject-level markers they are, and a conversation in the queue is assigned to `human` rather than routed. | A reader that told a visit or a demand by its route, such as bead-context.sh, reads the gate's await type instead. |
| `gc.continuation_group` | Stays, for molecule steps. Its registry text, which describes the visit's fence, is rewritten. | |
| `pr_comment_disposition=visit:<id>` | Becomes `human:<id>`. The migration rewrites every one (section 11). | pr-facts.sh |

**The tests that retire, with what they cover:**

- gate-visit.test.sh: the filing invariants of the block's copies.
- gate-visit-sweep.test.sh: one visit per human gate, and the `gc.gate_visit` stamp.
- converse-claim.test.sh: the claim's verdicts, BEGAN, and the finish close.
- converse-hold.test.sh: the demand, `gc.hold_demand` and `--hold-merge`.
- converse-fold-scope.test.sh: the topic, the holder and the hold's premise gate.
- converse-close-out.test.sh: the moot and benign close through visit-close.sh.
- visit-close.test.sh: the outcome pair, the fold and its merge-hold key transfer.
- visit-identity.test.sh: coverage by the `tracks` edge with the stamp fallback.
- escalation-rig.test.sh: the rig a bead's id names.
- doctor/check-visit-outcome-recorded and its run.test.sh: a closed visit carries `gc.outcome`.
- liveness-recheck.test.sh's cases for `visit.recheck` and the visit-id form.
- notification-wisp-reap.test.sh's gate-notice cases.
- gc-helm.test.sh's demand and topic cases, and gc-helm-engage.test.sh's reclaim cases.

These tests are rewritten on gates and conversations rather than retired:
escalate.test.sh, which adds the key's dedup through the bead's `blocks` edges,
a gate filed on a bead with open children, the refusal of a wisp and the
hand-off at the old name, and loses its store-pin and triage-redirect cases,
escalation-binding.test.sh, which keeps its rig binding for patrol-finding.sh's
call sites and drops it for the helper's, because the helper picks no store
(section 2), refinery-stuck-escalate.test.sh, which
pins the witness patrol's two blind-monitor checks on patrol-finding.sh,
await-ruling.test.sh, which adds the work bead's edge onto a gate filed on
another bead and drops its escalation-rig.sh stub, decline-wiring.test.sh,
visit-close-wiring.test.sh (as the human-gate-withdraw wiring), finding.test.sh,
finalize-gate.test.sh, bead-rehome.test.sh,
which adds the retry's withdrawal before the close, first-reaction-dispose's
tests, which add the gate on a bead with open children,
upstream-finding.test.sh, whose `--pool` cases go,
reconcile-rig-checkouts.test.sh, whose unroutable-pool run goes,
review-answer.test.sh, merge.test.sh, the prstatus tests, pr-facts.test.sh,
gc-helm-engage.test.sh, which adds the bind that misses, gc-helm-accept.test.sh,
which adds the read-back that stops Accept, gc-helm-open.test.sh,
gc-helm.test.sh's dismiss cases, converse-signoff.test.sh, which adds the
read-back that reports an earlier answer, converse-reap.test.sh, which adds the
`c-` alias, pr-visit-comment.test.sh and its wiring test, renamed with their
script, tmux-visit-prompt.test.sh, renamed with its script,
liveness-recheck.test.sh, which adds `--carried` and `--pass-at`,
liveness-classify.test.sh, liveness-sweep.test.sh, which adds the re-file check
on closed gates, the `*-escalation-wiring.test.sh` set, where
dog-escalation-wiring.test.sh loses its derivation cases,
pool-demand-wiring.test.sh, the check-hq-marooned-work test, and the board's Go
and web tests. formula-marker-coverage.test.sh loses the gate-visit markers.

## 11. Migrating the open visits

The cutover runs a one-shot script once per store: the city store, and every rig
store the pack runs on, suspended rigs included. It has a dry-run mode, and the
test suite runs it against a fixture store. It is not a standing sweep. The
cutover deletes it once every store reports no open visit (section 12).

The migration keeps every wait that holds today, and it adds one kind on
purpose: the subject of a visit escalate.sh filed waits on that visit's gate.
Today such a visit tracks its subject and blocks nothing. A subject waits on it
only where a filer added a wait of its own, as await-ruling.sh does for a
declined work bead, or where finalize-gate holds an anchor's merge. From the
cutover on, every gate the helper files blocks the bead its filer names
(sections 2 and 3). The migration files the gate for such a visit the same way,
so a gate means the same thing on either side of the cutover. Its own call-site
policy has one exception: it adds no pause to a tree that runs today, so such a
visit on a bead with open children that nothing else waits on becomes a
conversation (step 4).

A visit becomes a human gate when something waits on it: a bead with a `blocks`
edge onto it, or with an `until` edge, which says that the visit's close
resolves the bead (see the platform section); a demand it was filed for or that
holds it; a finding or a routed PR comment it answers; or, for a visit
escalate.sh filed, its subject. A visit on a PR anchor is a gate too, because
an open visit holds its anchor's merge through finalize-gate today. A visit
nothing waits on becomes a conversation in the operator's queue.

**The wait the cutover adds.** The subject of an open visit escalate.sh filed,
which nothing held before, leaves `bd ready` at the cutover, unless it has open
children (step 4). The subjects, read from the escalate.sh callers on main
(section 3), are these:

- **A PR anchor** under a merge-path or review gate: pr-facts.sh's
  families, gctk merge's one-anchor-per-pr and seed-audit gate,
  record-failure-cap.sh, branch-supersession.sh, and finding.sh's needs-you
  gate once its validation pass has closed. An anchor that already waits
  on a child changes nothing. For the rest the merge path changes nothing
  either, because every reader of anchors lists them with `bd list`, never
  `bd ready` (`services/gctk/internal/cli/merge.go` 210,
  `assets/scripts/bd-lib.sh` 151-157), and the merge stays held, through the
  edge where it was held through finalize-gate. What is new is that the
  anchor's close waits for the answer too. A PR merged outside the refinery
  while a gate holds its anchor records its landing once the gate is
  cleared.
- **A handoff the refinery holds**, under a gate the refinery patrol or the
  witness filed on it. It leaves `bd ready`, and nothing changes for the
  patrol, which finds its handoffs with `bd list --assignee`
  (`formulas/mol-refinery-patrol.toml` 156-166).
- **A task bead escalate.sh filed a visit on, with no arm:** a polecat's
  unreadable work bead and one whose requirements are unclear, the doctrine's
  plain blocker, an armed bead deferred-dispatch.sh could not sling, a wedged
  review bead, a refinery work bead refused for false completion or an invalid
  existing PR, a rejected handoff rejection-repool.sh could not return, a demo
  request, a validation pass with no anchor, a rig's reconcile bead, an
  upstream send task, an orphan the witness could not place, and a dog's
  warrant once orphan recovery reopens it. No pool is offered it. A re-sling
  of a work bead is cancelled at load-context, which arms it to re-sling once
  the answer lands (`formulas/mol-polecat-work.toml` 330-356). Its own close
  waits for the answer. check-blocked-work-armed reports one that is work and
  carries no route, arm or live run, as it reports a bead a demand blocks
  today.
- **A standing triage subject:** the liveness sweep's buckets and escalate.sh's
  ephemeral-subject bucket. Nothing changes, because no pool is ever offered
  one (`assets/scripts/standing-kinds.sh` 2-6). The ephemeral-subject bucket
  takes no new gate after the cutover (section 2).

That is wanted. Each subject is the bead its filer stopped on because it needs a
person. Offering it to a worker again would repeat what the gate reports, and
closing or merging it before the answer would clear the gate by accident.
reconcile-rig-checkouts.sh and record-failure-cap.sh are filers whose own remedy
is that close. reconcile-rig-checkouts.sh retracts its gate before it closes its
bead on a clean sync (`assets/scripts/reconcile-rig-checkouts.sh` 197-219), so
its self-heal is kept. record-failure-cap.sh asks a person to record a landed PR
by hand, and the record closes the anchor its gate's edge now holds, so its
message says to clear the gate first, and the merge cadence's retry of that
record waits for the answer too. The cap fires only once consecutive refusals
reach it, three by default, the point at which record-failure-cap.sh holds that
the retry will not converge (`assets/scripts/record-failure-cap.sh` 5-14), so
the gate stops a retry that was not healing.

**A sitting on a visit ends before the visit moves.** A live sitting can write
to the visit it holds at any moment: it appends notes, files demands when it
holds, or closes the visit. So before the run reads a visit, it closes every converse session that is
not closed and whose alias names the visit, under the bare id or the `v-`
prefix, and reads each back as gone from `gc session list`. From then on nothing
writes to the visit but the run, so step 6 carries the last note the sitting
wrote. When a session does not read back as gone, the run reports the visit and
leaves it as it is, for a rerun. A visit the sitting claimed still names the
sitting's alias, because closing a session releases nothing held under its
alias (see the platform section), so step 8 releases it before the close.

For each open or in-progress visit, once any sitting on it has ended, it does
the following, in this order. Each write is read back before the next, and the
visit closes last, so a run that stops part way leaves the visit open for the
rerun to finish:

1. **It reads the subject and the key.** The subject is the visit's `tracks`
   target, else its `gc.continuation_group`. The key is its `escalation_key`,
   else `conversation`. A visit gate-visit-sweep filed is the exception,
   because the sweep files a visit only to put one demand to a person. While
   that demand is open, the visit's key is the demand's topic, its
   `gc.demand_topic` or else `conversation`, so step 3 takes the demand as the
   visit's gate. The sweep's visit is one whose creator is the sweep's
   order (see the platform section) and whose framing names the demand
   (gate-visit-sweep.sh 156-160).
2. **A visit whose subject has closed waits on nothing through it**, because a
   closed bead does not move. Its gate blocks the beads that waited on the
   visit (step 4), and with none it becomes a conversation that tracks the
   closed subject (step 7), so what it asks outlives its subject on the
   board. A visit whose subject no longer exists takes the same path while
   other beads wait on it, because its gate blocks them and not the subject.
   With none, nothing can track the subject, so the run reports such a visit
   and leaves it open for a person.
3. **A demand that already covers the visit's situation becomes the visit's
   gate.** A demand covers it when its `gc.demand_for` names the visit's
   subject or the visit itself, and its topic, `gc.demand_topic` or else
   `conversation`, is the visit's key. A `gc.gate_visit` that names the visit
   does not show that. The sweep stamps a demand with any visit already open on
   the demand's subject, whatever that visit asks (gate-visit-sweep.sh
   132-137), so a first reaction's demand can name a review's visit beside it.
   Taken as the review's gate, that demand would let Accept's
   `ruled: accepted` close release the review's finding. A demand on the
   subject that covers another situation stays a gate of its own, and the pass
   after the visits shapes it. When more than one demand covers the visit's
   situation, the oldest is the visit's gate and the others carry the same
   await id. converse-hold leaves such a pair, its demand on the visit and the
   second one its `--hold-merge` files on the subject (converse-hold.sh
   286-308). The pair stays the duplicate a race can also leave, which the
   board folds and one ruling answers (section 2). A demand keeps blocking what
   it blocks, because its filer chose that, so the migration adds no wait on a
   bead with open children that is not there today.

   Step 3 takes each demand that covers the visit's situation, and every
   demand filed on the visit itself, whatever it asks. A demand it takes is shaped
   here. Its await id becomes its own topic, `gc.demand_topic` or else
   `conversation`, and its title becomes its takeaway, through
   `bd update --title`. The await id is written last, after the title and any
   edge move below, through `bd update --await-id`, because it is what marks a
   gate as shaped. A gate is shaped when its await id no longer starts with
   `gc-demand:`. A demand's own await id, `gc-demand:<gated>[:<topic>]`
   (gc-helm.sh 1442), names the bead it blocks, which a shaped gate leaves to
   its `blocks` edges (section 1). Its pack keys stay until its visit has
   closed, so a rerun takes the same demands from the same keys and writes the
   same title and await id. The pass after the visits removes them.

   converse-hold's demands take the visit's `escalation_key` as their topic
   (converse-hold.sh 187-189), so a held visit and its demands cover one
   situation. A held visit the sweep filed is the exception, because step 1
   gives it the topic of the demand it was filed for, so the hold stays a
   gate of its own beside that demand. converse-hold files its first demand
   on the visit itself when the subject is a PR anchor (converse-hold.sh
   210-213, 234-244), so that demand blocks the visit, not the subject. bd
   refuses to close a blocked bead and keeps a closed bead's edges, so the edge
   of a demand filed on the visit moves before the visit can close, and before
   the demand's await id is written. The subject's `blocks` edge onto the
   demand is added and read back. Then the visit's edge onto it is removed with
   `bd dep remove`, and read back as gone. The anchor's merge waits on the
   moved demand, as it waited on the open visit through finalize-gate.
4. **Otherwise, when something waits on the visit, it files the gate through
   the helper**, declaring no quiet window, so a recent moot or benign answer
   under the same key does not stop it. The title is the visit's headline, the
   framing is the visit's description, and the key is the visit's key. The gate
   blocks the subject, unless the subject has closed or no longer exists
   (step 2), has an open `parent-child` child, or holds its own `until` edge
   onto the visit. The
   migration's policy is to add no pause to a tree that runs today, and it reads
   the shape in one call, `gc bd list --parent <subject> --include-gates
   --include-infra --include-templates --json --limit 1`, which returns any
   child that is not closed or pinned, a gate or a wisp among them, the children
   the cascade blocks (see the platform section). A subject's own `until` edge
   says that the answer resolves it rather than holds it, and a bead cannot
   carry both edges onto one gate (see the platform section), so it keeps the
   `until` edge step 5 moves. When the gate does not block the subject, it
   blocks the first bead that waited on the visit through a `blocks` edge,
   passed to the helper as the bead the gate is about, and the waits step 5
   moves cover the rest. The helper's dedup merges a visit into a gate under
   the same key that already blocks that bead, so nothing is asked twice. It
   returns that gate without the merged visit's framing (section 2), which
   step 6 carries. A visit escalate.sh filed on a bead with open children,
   which nothing else waits on, becomes a conversation, as below. A visit whose
   only waiters hold `until` edges, on a subject the gate cannot block, is
   reported and left open for a person, because the migration has no bead to
   block: an `until` waiter is resolved by the answer, not blocked by it.
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
   visit it was filed for. Without the carry, what the visit asked and its
   evidence would leave with its close.

   A visit that carries a `visit.recheck` stamp needs one thing more. The
   stamp's one writer is liveness-sweep.sh. It stamps an absolute path to
   liveness-recheck.sh beside the census, `sweep.new_ids`, `sweep.carried_ids`
   and `sweep.pass_at`, and the framing it writes tells the sitting to run that
   stamp (liveness-sweep.sh 467-471, 530 and 557-570). A gate carries neither,
   so step 6 also appends, under the visit's line, the re-check command a
   liveness gate now carries in its message (section 4):
   `liveness-recheck.sh --ids <new> --carried <carried> --pass-at <time>`,
   built from the visit's census, with the script named rather than the
   stamp's path, whether or not the framing is left out. The command names no
   visit, and it re-checks the same census after the visit has closed.
7. **A visit nothing waits on becomes a conversation.** The script files a task
   in the operator's queue that tracks the subject (section 1), titled with the
   visit's headline, with the visit's framing as its description and its notes
   carried under a line naming the visit. A rerun finds that task by the line
   and files no second one. This covers the visits the operator opened,
   the keyless visits mol-validate-close and mol-feedback-distiller filed, a
   visit escalate.sh filed on a bead with open children that nothing else
   waits on, and a visit on a closed subject that nothing else waits on
   (step 2).
8. **It releases the visit from its holder, then closes it.** bd refuses an
   unforced close of an assigned bead by any actor but its assignee, and a
   visit a sitting claimed still names the sitting's alias after its session
   has closed (see the platform section). So the run reads the visit's holder
   and status, and releases a visit that names a holder with one write guarded
   on both: `gc bd release-if-current <visit> <holder>` for a visit in
   progress, and
   `gc bd update <visit> --if-assignee <holder> --if-status open --assignee ""`
   for an open one, such as a visit today's engage bound to a sitting's session
   that never claimed it (gc-helm.sh 4060-4067, 4278-4287 and 4301). It reads
   the visit back open and unassigned. A release that finds the visit changed
   since its read writes nothing, and the run reports the visit and leaves it
   open, for a rerun to release from the holder it reads then. A visit that
   names no holder, as a rerun finds one an earlier run released, goes straight
   to the close. The run closes the visit with the reason `migrated: gate <id>`
   or `migrated: conversation <id>`, unforced, so bd still refuses a visit that
   something other than the moved demand blocks, or that has an open child.
   Such a visit stays open and unassigned, and is reported. Nothing is forced.

**A human gate no visit covers is shaped too.** gate-visit-sweep files no visit
for a gate assigned to a person, a gate whose gated bead has closed, or a gate
stamped `gc.gate_visit=skip` (gate-visit-sweep.sh 17-28). A demand whose
situation no open visit covers, such as a first reaction's beside a review's
visit, is taken by no visit in step 3. After the visits, the script reads the
store's open gates (`bd gate list --json --limit 0`, see the platform section)
and shapes each open human gate that is not yet shaped, the way step 3 does,
with the await id written last: its await id becomes its topic,
`gc.demand_topic` or else `conversation`. It keeps every edge it has, because a
gate is about each bead it blocks. A demand whose `blocks` edge never landed has
none to keep, so once its keys go it is about no bead. The board gives it a row
of its own (section 8), the first line of its description still names the bead
its filer meant, and the run reports it. Last, the pass removes the pack keys
from every open human gate that is shaped:
`gc.demand_for`, `gc.demand_topic`, `gc.gate_visit`, and the route and takeaway
keys a demand carries. The pass leaves alone every gate that step 3 takes for a
visit still open, because the next run's step 3 finishes it from those keys. The
removal is a gate's last write, so a rerun after it finds the gate's title and
await id in place, and leaves them as they are.

**Every live reference to a visit is re-pointed, after the visits.** The records
in the table below name a visit and are read after the cutover. A finding can
name a visit that a fold or a re-home closed, so for a finding the script walks
from the named visit to the gate or visit that carries its situation now, as
finding.sh's `ruled_visit` does today (finding.sh 1262-1281). The walk follows
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
| `pr_comment_disposition=visit:<id>` on an anchor | pr-facts.sh, which reads the kind and the named bead's status (section 4) | `human:<id>`, naming the gate for a visit the script migrated, and the visit itself for one closed before the cutover. |

Until the script has run on a store, the new readers find none of them, so they
release nothing early. For those minutes a needs-you finding stays held and a
routed comment reads as unanswered.

A visit held by a live sitting is migrated like any other once that sitting has
ended (above), and its gate is filed unassigned, so the operator re-engages the
subject on the new path. After the visits, the script closes every other
converse session whose alias names a visit, under the bare id or the `v-`
prefix, such as a settled sitting today's reap skips (section 6), so no session
runs the old prompt past the cutover. Last, it closes the "Human gate awaiting you" notices
still open in the city store, which nothing else will close once the notify
order is off.

**Nothing lost, nothing doubled.** Every open visit ends as an open human gate
that asks what the visit asked, or as a conversation in the operator's queue,
unless step 2 or step 4 leaves it open for a person. Each carries the visit's
framing and every note on it, since a sitting that held it ended before the
carry, and every bead that waited on the visit waits on its gate. A
merge an open visit held stays held, and the subject of a visit escalate.sh
filed waits, the one wait the cutover adds (above). A visit joins a gate only
when the two cover one situation on one bead, so no answer to one situation
closes another. A rerun finds each gate and each conversation again. The
helper's dedup finds a gate step 4 filed by its key
among the gates of the bead it blocks, step 3 matches the same demands from the
pack keys they keep until their visit has closed, and step 7 finds its task by
the visit's line. The rerun adds only the edges, framing, notes and references
still missing, removes a visit's edge onto a moved demand if it is still there,
and closes only the visits left over. A sitting an earlier run ended is gone
from `gc session list`, so the rerun closes no session twice. It releases a
visit that still names a holder from the holder it reads, and a visit an
earlier run released goes straight to the close. It reports, per store, the
visits it migrated into gates, those it merged into a gate already there, those
it turned into conversations, and any it left open, could not release or could
not close, and the human gates it shaped that block no bead.

Its test stops a run after each write and reruns it, among them the write that
removes a gate's pack keys, the close of a sitting's session and the release of
its visit. After every rerun, each open visit has become one
gate or one conversation with its framing, notes, waits and references
moved, each gate has the title and await id an uninterrupted run gives it, and
every visit but the ones the report names is closed. The fixture store holds the
states this section names:

- **A recommendation beside a review's visit.** An anchor carries a first
  reaction's demand under the topic `first-reaction`, with
  `gc.recommended_formula` on the anchor, and finding.sh's separate
  `review-needs-you.<finding>` visit, which the demand's `gc.gate_visit` names.
  The run leaves two gates that block the anchor, under the keys
  `first-reaction` and `review-needs-you.<finding>`, and the finding names the
  second. Then the board withholds Accept, a stale `gc-helm.sh accept <anchor>`
  refuses, and the review gate and its finding stay open, as in unit C's
  acceptance case (section 12).
- **A sweep's visit for a recommendation.** The run closes the visit into the
  first reaction's demand and leaves one gate on the anchor, under the key
  `first-reaction`, so the board offers Accept.
- **A held visit with a substantial description and no notes**, whose demand's
  description is empty. The gate the visit closes into carries that description
  in its notes.
- **A liveness sweep's visit with its `visit.recheck` stamp and census.** The
  gate it becomes carries the re-check command with the visit's census in its
  notes, naming no visit, and that command prints the census after the visit
  has closed.
- **A visit the operator opened on a plain bead.** The run leaves one task
  in the operator's queue that tracks the bead with the visit's framing and
  notes, the board shows the bead owed with that task's title, and a rerun files
  no second task.
- **A visit the operator opened on a PR anchor.** The run leaves a gate
  under the key `conversation` that blocks the anchor, so the merge stays
  held.
- **A visit escalate.sh filed on an epic with open children and no waiter, and
  one on a plain task with an open child.** For each, the run leaves a
  conversation in the queue and no edge onto the parent, so its children stay
  ready.
- **A visit on a bead with an open child, whose only waiter holds an `until`
  edge, and a visit whose subject's own edge onto it is `until`.** The run
  reports each and leaves it open, so no waiter is resolved before anyone
  answers.
- **A visit on a closed subject with no other waiter, and one with no waiter on
  a subject that no longer exists.** The run leaves a conversation that tracks
  the closed subject, and it reports the other and leaves it open.
- **A visit escalate.sh filed on a plain bead with no waiter.** The run leaves
  a gate that blocks the bead, so the bead leaves `bd ready`, the wait the
  cutover adds.
- **A visit a live sitting holds, one held under the alias of a sitting whose
  session has closed, and an open visit bound to a sitting's session that does
  not exist.** For the first, the run closes the sitting's session before
  it reads the visit, and the note the sitting appended last is carried with
  the visit's other notes. For each, the run releases the visit from the holder
  it reads, reads it back open and unassigned, and closes it unforced with its
  `migrated:` reason.
- **A run stopped after it ended a sitting, and one stopped after it released
  the visit.** The rerun of the first releases the visit from the alias it
  still names, and the rerun of the second reads the visit unassigned and
  closes it. Neither rerun closes a session.
- **A visit whose holder changes between the run's read and its release, and a
  released visit with an open child.** The release of the first writes
  nothing, and the run reports the visit and leaves it open, for a rerun to
  release from its new holder. bd refuses the second's unforced close, and the
  run reports it and leaves it open and unassigned.

## 12. Cutover and the build

**The cutover order:**

1. **The town's city.toml turns off notify-on-human-gate-creation** (section 5),
   any time before step 3.
2. **The operator approves and merges this integration branch to main.** That is
   the one reviewed unit the initiative asks for.
3. **The rig checkout sync moves the pack to that main.** One pack serves every
   rig, so every rig switches at once. gate-visit-sweep's order disappears,
   human-gate.sh files gates, the hand-off at escalate.sh runs it for a run
   poured before the sync, and engage files conversations. The board and gctk
   are built binaries, so they switch when the helm-build and gctk-build orders
   next rebuild them, inside their five-minute cooldown. The cutover runs both
   orders by hand with `gc order run` as soon as the pack moves, so the old
   board's window is one build long. Until the new board is up, the old one
   reads visits and does not fold the new gates onto the beads they block.
   Demand gates already on the board stay there, and the migration merges the
   visits the sweep made for them.
4. **The migration runs on every store, city first, once the new board is up.**
   Until it finishes, open visits are not on the board, a ruled finding and a
   routed comment that name a visit wait for it, and a sitting that was live at
   step 3 is running an old prompt against new scripts. The migration ends that
   sitting before it carries the visit over, so the carry takes the sitting's
   last note, then releases the visit from the sitting and closes it
   (section 11).
5. **The operator checks** that no store has an open visit and that the board
   shows every human gate and every queued conversation. A follow-up commit on
   main then deletes the migration script and its test, and retires the keys
   only the script still read (section 10). It also checks the debts on the PR
   reminder's old marker and on the hand-off at escalate.sh (section 10). Unit D
   files that follow-up as a bead blocked on the cutover, so it is tracked from
   the start.

**How each rig cuts over.** Every rig's code switches together at step 3. Every
rig's store is migrated by its own run at step 4. A suspended rig's store is
migrated too, and its gates surface when the rig is resumed.

**The build is four beads onto integration/tk-iirrmiw, in this order.** Each is
its own PR on the branch, and each keeps the suite green. The convoy's
implementation child, tk-xgj6mg7, builds unit A. When it starts, it files units
B, C and D as members of this convoy, each blocked on the unit before it, as its
brief allows when the design calls for a split:

| Unit | What it carries |
|---|---|
| A. The helper and its callers | The helper on gates, renamed human-gate.sh with a hand-off at escalate.sh and every call renamed with it, with the key as the await id, the dedup and the quiet window read through the bead's `blocks` edges, the retract by resolve, the refusal of a wisp, and `--quiet-window` as the only quiet period: each caller that re-detects one condition declares its window at its call site with its why, the others declare none, and the `GC_ESCALATE_VERDICT_WINDOW=0` prefixes go. Its store derivation and its triage redirect retired, with the deacon prompt's and mol-dog-shutdown-dance's derivations and escalation-rig.sh. The calls that named a wisp, a session or a bead they could not read, and the reports that nothing waits on, on patrol-finding.sh (section 3). await-ruling.sh, with the work bead's edge onto a gate filed on another bead. upstream-finding.sh's `--pool` and reconcile-rig-checkouts.sh's pool knob retired. first-reaction-dispose, mol-validate-close, deferred-dispatch.sh and mol-feedback-distiller on the helper, each with its call-site policy on a bead with open children (section 3). mol-visit and the formula copies of the gate-visit block retired. The polecat doctrine and pool-worker fragments, the human-gate-withdraw fragment, and the deacon, refinery and witness prompts. The tests named for the helper, renamed with it (section 10). The registry entries of the keys the helper stops writing. |
| B. The readers | finalize-gate. gctk merge and pr-status, with `OpenHumanGate`. finding.sh and review-answer.sh. pr-facts.sh. branch-supersession.sh. The liveness scripts, with conversing read from conversations, the census in the re-check command and the re-file check on closed gates, hold-lib.sh, deferred-dispatch.sh, bead-context.sh and pre-open-rebase.sh. orphan-dispose.sh and the witness patrol. bead-rehome.sh, with the retry's withdrawal before the close. The doctor checks, `RETIRED_KEYS`, and the docs that teach these components (section 13). |
| C. Converse and the board | The conversation task, and gc-helm.sh engage, open, accept and dismiss on it, with engage's guarded bind and `c-` fallback, the hand-off, and Accept's read-back. The converse prompt and agent headers, the five converse skills and the shared skills. Accept on the recommendation's gate alone, pinned by the acceptance case below. converse-signoff.sh rewritten, converse-reap re-keyed with its warrant in `docs/warrants.md`, and the converse scripts that retire. gc-helm.sh demand retired here, with its last callers: converse-hold.sh, converse-signoff.sh, and the waits, prs and converse-settle skills. pr-sitting-comment.sh with its new marker, and operator-intake.sh. The tmux scripts, tmux-intake-prompt.sh among them. The board's source, with each gate's `blocks` dependents in its batched read, its derive, with a gate folded onto each bead it blocks, its model, its wire contract with `accept_withheld`, and its web and text boards. gate-visit-sweep's order and script. The human-engagement docs and the board's README. |
| D. The cutover | The migration script, with its copy of the visit walk, and its test, which stops a run after each write and holds section 11's fixtures. notification-wisp-reap's gate pass retired. The cutover runbook in its own spec. The remaining docs. |

The order follows the dependency. B's readers read what A's helper files, and
C's sittings answer what A files and B reads. A's callers open a conversation
through `gc-helm.sh open`, which files a visit until C turns it into a
conversation, so the branch is consistent at each unit's head. A, B and C each
leave the integration branch consistent for the suite, though not deployable
before D. The branch is never deployed until it graduates as a whole. Each of
the four PRs is about one subsystem. The single build is the alternative, at the
cost of one PR across every file this design names.

**Unit C's acceptance case: a recommendation beside a review gate.** The
fixture is one anchor with two open human gates that block it. A first
reaction's recommend exit filed one under the key `first-reaction` and stamped
`gc.recommended_formula`, and finding.sh filed a needs-you finding's gate under
the key `review-needs-you.<finding>` (finding.sh 918-924).
gc-helm-accept.test.sh and the board's derive tests pin each step:

1. **The board withholds Accept.** Both gates fold onto the anchor's row, and
   Needs prints both titles. `acceptable` is false, and `accept_withheld` names
   the review gate.
2. **A stale Accept refuses.** `gc-helm.sh accept <anchor>` exits non-zero and
   names the review gate. Both gates stay open, the finding stays held,
   `gc.recommended_formula` stays, and nothing is slung.
3. **Discuss answers the review gate.** Engage files a conversation that
   tracks the anchor and starts its sitting. The sitting rules the review
   gate, and that `ruled:` close is what releases the finding (section 4).
   The operator leaves the recommendation, so the sign-off leaves its gate open
   and closes the conversation.
4. **Accept answers the recommendation alone.** With the recommendation's gate
   the last one open and unassigned, the row offers Accept, and
   `accept_withheld` is null. Accept resolves that gate with
   `ruled: accepted <formula>` and its run's token, reads its own reason back,
   slings the formula and records the dispatch. The review gate's close reason
   is still the sitting's ruling.
5. **A late gate stops the dispatch.** A gate filed after Accept's live read
   and before its resolve shows in the read-back. Accept reopens the
   recommendation's gate, reads it back as open, and nothing is slung.
6. **An earlier answer stops Accept.** A sitting resolves the recommendation's
   gate with `ruled: declined` after Accept's live read and before its
   resolve. Accept's resolve changes nothing, its read-back finds the sitting's
   reason, and Accept reports that answer. Nothing is slung, nothing is
   reopened, and the gate keeps the sitting's reason. Two Accepts run on one
   open gate sling once: the one whose token reads back slings, and the other
   reports it.

A second fixture files the other gate on another bead first, and the anchor
then waits on it through a `blocks` edge of its own. The one reader rule counts
it among the anchor's gates. It folds onto both beads' rows, and Accept is
withheld the same way, with `acceptable` false and `accept_withheld` naming that
gate. A stale `gc-helm.sh accept <anchor>` refuses, names that gate and slings
nothing.

A third fixture puts a live sitting on the anchor beside an open recommendation
and no other gate. The row is in session and offers Accept. Accept warns that a
sitting is discussing the anchor and clears the recommendation's gate, and the
sitting's sign-off then reports that the gate was already cleared.

A fourth fixture puts the recommendation on a bead with an open child. The
first reaction's gate blocks the parent, the child leaves `bd ready` until the
gate is cleared, and the row offers Accept as on any bead.

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
| 2026-10-19 | `bd gate create` has no idempotency. | The helper reads the bead's gates by the one reader rule before it creates (section 2). |
| 2026-10-19 | A gate records what it blocks only as `blocks` edges. No structured field names the bead it was filed for, only the first line of its description, and a bead that waits on the gate adds an edge just like the first. | Nothing needs to name one. A human gate is about every bead it blocks, every reader reads it through those edges, and its await id carries only the situation key (section 1). The answer was revised on 2026-10-21 by the ruling of sitting tk-yf4nt2d, and the claim was re-read then. |
| 2026-10-19 | Continuation preassignment applies only within one workflow root, so it never reaches a gate. | A sitting holds one conversation task, which names its bead (section 6). |
| 2026-10-19 | Nothing native releases a gate claimed by a session that died. The listings of orphan-sweep and the on_death release hide gates, the dead-assignee release covers pool-routed work, and lease reclaim, which nothing in Gas City runs at this commit, would rob a live held sitting. | No session claims a gate (section 1). |
| 2026-10-20 | Nothing native releases a task a manual session claimed through `gc hook --claim` once the session is gone. on_death runs only for pool instances, orphan-sweep counts such a bead unverifiable, and `gc session close` releases nothing held under the alias. | A sitting's alias names its task's id, so engage finds the task by its assignee, and a new session under a closed session's alias takes the task back, so engage restarts a sitting under the same alias. The witness's recovery skips such a task. A hand-off returns a task to the operator's queue with a guarded update that names its holder (sections 4 and 6). Before the migration closes a visit whose sitting it ended, it releases the visit with Gas City's release-if-current, which names the holder too (section 11). Nothing is kept for this gap. |
| 2026-10-19 | A manual session is not ended when its work closes, and a pool sitting would be drained by the execution backstop while the operator reads. | converse-reap, keyed on conversation tasks. Its trigger is in section 6, and its warrant goes in `docs/warrants.md`. |
| 2026-10-19 | Core's human-gate orders, Gas City's native reach for a human gate, reach a person only by mail and nudge, and an override can only point them at another mailbox or session. This city's operator has no session and reads the board, not a mailbox. | The board is the reach, and core's two orders are off in this city (section 5). The orders were re-read on 2026-10-21. |

**What a reader must still learn.** The design adds no new kind of pack state. A
human gate is a native gate, a conversation is a native task, and neither
carries a pack key. That does not make it free of pack surface. A reader who
knows Gas City and bd, and not this pack, must still learn these conventions,
each carried by a native field, a flag or a name:

- the situation key a gate's await id carries, and the two keys the pack reads
  by name: `conversation`, the key of a gate a sitting files, and
  `first-reaction`, the gate Accept clears;
- the headwords `ruled:`, `moot:` and `benign:` at the head of a gate's close
  reason. `ruled:` releases a needs-you finding, and `moot:` or `benign:`
  starts the quiet period under the gate's key for a filer that declares one;
- human-gate.sh's `--quiet-window`, which a recurring detector declares at its
  call site and nothing turns on by default, its refusal of a wisp, and the
  hand-off at its old name, escalate.sh, until no run poured before the cutover
  calls it;
- a conversation's shape: a task that tracks one bead, never a gate, and is
  assigned to `human` or to the alias that names its own id, with the `c-`
  alias fallback;
- the board's wire fields `acceptable`, `accept_withheld` and `sitting_state`,
  and gctk's `OpenHumanGate`;
- the finding keys `finding.gate` and `finding.ruling_bead`, and the
  disposition `human:<id>`;
- the PR reminder's marker `<!-- gc:sitting:<task> -->`, and the liveness
  re-check command a gate's message carries;
- the `migrated:` reason the cutover writes on each visit it closes.

**The glue it keeps** composes native calls, as the epic's third test allows,
or stands in for a missing primitive under a warrant:

- human-gate.sh's read of a bead's gates before it files, the quiet period as
  an option each call declares, off by default, which mirrors the opt-in
  incident reminder of core's escalate.sh hook, and the withdrawal of a filer's
  own gate by key (section 2);
- the hand-off at escalate.sh, under its dated debt (section 10);
- await-ruling.sh's edge for a work bead onto a gate filed on another bead, its
  release of the claim and its re-sling arm (section 4);
- finalize-gate's clause on human gates, and bead-rehome.sh's withdrawal before
  a retried close (section 4);
- engage's alias-reservation bind: the session started under the task's id,
  the guarded bind, and the session closed when the bind misses (section 6);
- gc-helm.sh accept's live read of its three conditions, its read-back and its
  reopen (section 8);
- converse-signoff.sh's one ordered call (section 7);
- converse-reap, under its warrant (section 6);
- the PR reminder, pr-sitting-comment.sh (section 7);
- the board's derive rules: the fold, held, owed, in session, Accept's three
  conditions and the unchanged ranking (section 8);
- the one-shot migration script, which the cutover's follow-up deletes
  (sections 11 and 12).
