---
name: Human engagement — gc-toolkit's subject, human gate and conversation model
description: gc-toolkit's own model for engaging a person — the subject, the human gate and the conversation, how a gate reaches the operator, how a conversation starts, how a sitting claims, holds, answers and ends, Accept, how a parked subject comes back, the helm boards, and the ground the pack builds itself. A pack convention; the Gas City primitives it rides are gascity/human-engagement.md.
---

# Human engagement

This page is gc-toolkit's model for engaging a person, not Gas City
behavior. The Gas City primitives it rides — human gates and the core orders
that surface them, the task, edge and session facts a conversation rests on,
pending interactions, and how a session and its pane end — are stated, each
with its date, in [gascity/human-engagement.md](gascity/human-engagement.md).
Where a passage below relies on one of them, it links there.

**Vocabulary.** Four terms name the model, and every prompt, skill and doc in
the pack uses them only in these senses.

- **Subject.** The bead a human gate or a conversation is about. A gate's
  subject is the bead that waits on it through a `blocks` edge, and a gate
  that a second bead also waits on is about both. A conversation's subject is
  the one bead it tracks. Any bead can be a subject: a work bead, an epic, a
  PR's anchor. Its notes carry the durable outcome of every conversation about
  it, and the resolve reasons of the gates it waits on carry their answers, so
  whoever works it next inherits what was decided.
- **Human gate.** Gas City's native bead for a wait a person must clear before
  work moves (`issue_type=gate`, `await_type=human`): an answer, an approval or
  an action. Its title and description say what the person must clear, and its
  await id carries the filer's situation key. It is unassigned while the
  operator owes it, or assigned to the one person who must clear it, and no
  session claims it. Resolving it clears it, and its resolve reason is the
  answer, headed `ruled:`, `moot:` or `benign:`.
- **Conversation.** An ordinary task that carries one dialogue about one
  subject. It tracks its subject, which is always a bead and never a gate, and
  it replies to each human gate it answers, through bd's `replies-to` edge from
  the conversation onto the gate. Neither edge holds anything: a conversation
  blocks nothing, and nothing waits on it. Its description is the ask, the
  concern the operator brought or the gate engage was pointed at. It is
  assigned to `human` while it waits in the operator's queue, and to its
  sitting's alias while a sitting holds it. Two dialogues about one bead are
  two conversations.
- **Sitting.** The live hosting of one conversation by one converse session. A
  sitting is not a bead. Its session is a manual session whose alias names its
  conversation's id, and the conversation's assignee is that alias, which is
  how a sitting is found and resumed.

So a dialogue's ask lives on its conversation, an answer in the resolve reason
of the gate it clears, which the conversation replies to, and the durable
outcome on the subject's notes. A conversation carries no pack metadata: a
reader outside the pack sees a task, held by a session or in a person's queue,
that references a bead and replies to the gates it answers.
`assets/scripts/conversation.sh` holds the one definition of that shape, and
every reader that looks for conversations, engage and the board among them,
reads it.

gc-toolkit's engagement model is a bet on Gas City's own momentum: the
runtime is steadily growing the primitives a human conversation needs, and
the pack composes those primitives rather than inventing beside them
([architecture.md](architecture.md), "How humans engage"). The bet pays only
if the pack tracks where upstream is going, which is why the primitives, their
verified status and their direction have a page of their own. This page is the
model the pack builds on them.

## Scope

**Mandate.** gc-toolkit's model for engaging a person: the four terms, how a
human gate reaches the operator, how a conversation starts, how a sitting
claims, holds, answers and ends, Accept, how a parked subject comes back, the
helm boards, and the ground the pack builds itself.

**Boundaries.** The Gas City primitives the model rides are
[gascity/human-engagement.md](gascity/human-engagement.md), and the routing
mechanics are [gascity/routing-model.md](gascity/routing-model.md). How the
pack's lifecycles compose, and how completion propagates back to a waiting
conversation, is [lifecycle-composition.md](lifecycle-composition.md). The
converse prompt and its skills are the sitting's procedure as an agent runs
it; this page is the model they implement. The board's read path and wire
model are [services/helm/README.md](../services/helm/README.md).

## The principle

When Gas City ships a primitive that covers something the pack built
bespoke, the pack re-derives its machinery on the primitive and retires
the bespoke part. The engagement model itself is the standing example: a wait
a person must clear is Gas City's native human gate, a conversation is an
ordinary task, and a sitting claims it with the plain `gc hook --claim`, so
the pack carries no bead kind, no sweep and no claim of its own for either.
Expect the same trade wherever upstream covers bespoke ground; that is what
riding an ecosystem means.

## How the model rides the platform

Each primitive below is stated, with its evidence and date, in
[gascity/human-engagement.md](gascity/human-engagement.md). What follows is
the seam the pack builds at each.

- **A human gate is the wait, and every reader treats it alike.** Any pack,
  formula or person files one with
  `gc bd gate create --type=human --blocks <bead> --await-id <key>`, and the
  gate lands in the store of the bead it blocks. `assets/scripts/human-gate.sh`
  is an optional helper that makes the same call and adds what the call does
  not do: one open gate per bead and situation key, a quiet period after a
  `moot` or `benign` answer for a call that declares `--quiet-window`, the
  message as the gate's description, and `--retract`, which resolves the
  filer's own gate as moot once the situation has gone. Every reader finds a
  bead's human gates one way, through the bead's `blocks` edges
  (`bd_human_gates` in `assets/scripts/bd-lib.sh`), so a gate holds what it
  blocks whoever filed it. A gate on a bead with open children pauses every
  part of it that has not started, so a filer that can land on a parent says
  whether it blocks the parent, blocks one member, or opens a conversation
  instead.
- **A conversation is a task, and the alias is the binding.** A conversation
  tracks its subject (`--deps "tracks:<bead>"`) and replies to the gates it
  answers (`gc bd dep add <task> <gate> --type replies-to`), and neither edge
  holds anything. Its sitting's session is a manual session started under the
  conversation's id as its alias, and the conversation is assigned to that
  alias, so the default work query offers the session that one task and
  nothing else. The alias is reserved city-wide while a session that is not
  closed holds it, and the bind that hands the task to the session is a write
  guarded on the holder and the status the binder read, so two sittings never
  hold one conversation, and none is bound to one a dismiss has closed.
- **A sitting is the worker contract with its close replaced by a hold.**
  Upstream's `gc-role-worker` contract is claim, execute, close. A sitting
  claims its conversation, holds it `in_progress` while the operator thinks,
  records the answer to the subject, closes only the conversation, and then
  drains: a closed conversation ends its session. A session holds one
  conversation, so a sitting never claims across subjects,
  and the contract's continue-or-drain clause
  ([gascity/human-engagement.md](gascity/human-engagement.md#the-gc-roles-worker-contract))
  has nothing to choose between. The roles pack's planning roles
  (`requirements-planner`, `task-decomposer`) are a standing adoption question
  wherever the pack plans or decomposes (see the tripwire under Watch items
  below).
- **Questions gate work with core edges.** A gate blocks the bead that waits
  on it, so the bead leaves `bd ready` and the pool's offer, its merge holds,
  and bd refuses its close, until a person clears the gate. "A human approval
  is just a check nothing non-human can yet satisfy" composes directly, with no
  bespoke gate machinery.
- **External channels meet the model at the subject bead.** Upstream's
  `extmsg` is a different plane from gc-toolkit's beads — extmsg is
  channel-shaped and session-bound; ours is operator-internal and
  record-durable — and the two are complementary, not competing. When an
  external channel arrives, the subject bead is the natural binding anchor: a
  Slack thread about a piece of work should bind where that work's
  conversations already live, not beside it.
- **There is no flag-for-attention.** `gc.attention` has no upstream meaning,
  and the pack does not use it either. "An agent believes a human should look
  at this" has two forms: a human gate on the bead that waits, when work must
  wait for the answer, and a conversation on the bead (`gc-helm.sh open`) when
  nothing waits. The board derives what is pressing from real state (open
  gates, queued conversations, stranded work) rather than from self-assertions
  with no lifecycle.

## How a human gate reaches the operator

Gas City's native reach for a human gate is core's two orders.
notify-on-human-gate-creation mails a new gate's addressee, and
renudge-stale-human-gates mails it again while the gate stays open. Both
address the gate's assignee, then `gc.deferred_assignee`, then
`$GC_ESCALATION_RECIPIENT`, which defaults to the `human` mailbox
([gascity/human-engagement.md](gascity/human-engagement.md#human-gates-and-the-orders-that-surface-them)).
The operator of this city reads the board, not mail, so the town's `city.toml`
disables the renudge order, and the creation notice is a record in an unread
mailbox rather than the reach. A city whose operator reads mail keeps both, and
every gate the pack files reaches that operator through them unchanged.

**The board is the reach.** The helm board folds each open human gate onto the
row of every bead it blocks, shows the gate's title as that row's NEEDS, and
keeps the row owed, ordered by how long it has been owed, until the gate is
cleared, its filer withdraws it, or, for the gate that put a recommendation to
the operator, Accept clears it. A gate none of whose beads has a live row keeps
a row of its own that states what it asks, so no open gate is off the board.
Nothing re-mails, and no session claims a gate, so a gate a sitting is
discussing is still open and unassigned until the sitting answers it.

## How a conversation starts

A conversation starts three ways: the operator engages a bead or a gate, the
operator's intake files one, or something asks the operator to talk a bead
over with `gc-helm.sh open`. A conversation in the queue starts no session,
because assigned work wakes only the session whose identity it carries and no
session carries `human`. A sitting starts only when the operator engages.

### Engage

`gc-helm engage` (the tmux picker and helm-svc's engage route run it) takes
these steps:

1. **It takes the bead.** Given a bead, it works on that bead. Given a gate, it
   works on the one bead still waiting on the gate, read from the gate's
   `blocks` dependents. With several still waiting, as when an anchor and its
   rework child both wait on the anchor's bring-current gate, it names them and
   starts nothing, so the operator engages the one they mean. With none, it
   says nothing waits on the gate, names any closed bead the gate was about,
   and starts nothing, and the operator clears the gate.
2. **It reads the bead's conversations:** the open tasks that track the bead
   in the conversation shape, with the session list saying which of their
   sittings are live.
3. **A concern opens a fresh conversation.** A `--reason`, `--template` or
   `--skill`, or the operator's choice of a new conversation when engage asks,
   files a new task whose description is that concern, even when the bead has
   a conversation already, because a distinct concern is a distinct dialogue.
4. **Without one, it attaches first.** A conversation a live session holds is
   a live sitting, and engage attaches the operator to it rather than starting
   a second. Otherwise it takes the bead's conversation from the queue, or one
   whose sitting's session has closed, or files a new one. Pointed at a gate,
   engage makes the conversation it landed on reply to the gate and reads the
   reply back before it starts or attaches anything.
5. **It starts the sitting:**
   `gc session new converse-<model> --alias <task> --no-attach`, under the
   prefix `c-` when the runtime refuses the bare id as an alias. A session
   still holding that alias that no longer holds the task, as a sitting cut
   short leaves it, is closed first once it is older than the bind wait and
   unattached.
6. **It binds the task to the session's alias** with
   `gc bd update <task> --if-assignee <holder> --if-status <status> --assignee
   <alias>`, where the holder and the status are the ones engage read, or the
   queue and `open` for a conversation it filed. A task already assigned to the
   alias, as a sitting whose session closed leaves it, needs no bind. Either
   way the task must read back assigned to the alias and not closed. A bind
   misses when another engage or a hand-off landed first, or when a dismiss
   closed the task, since a dismiss keeps the holder and changes the status. A
   bind that misses, or a read-back that finds the task closed, closes the
   session this engage started. Then engage posts the PR reminder, waits for
   the reconciler to start the session, and attaches the operator.

Engage warns when it starts a sitting while another live sitting tracks the
bead, or replies to a gate the bead waits on. **One sitting per bead is a
convention, not a guarantee.** The alias and the bind keep a second sitting
off one conversation, not off one bead: a concern of its own, two engages
racing on a bead with no conversation, or a gate two beads wait on can each
put two sittings on one bead. The board folds both onto the bead's row, either
may answer a gate, and the first answer wins.

**The PR reminder.** When the subject carries a PR, engage leaves a comment on
it saying a sitting engaged, and the sign-off or a dismiss edits that same
comment in place when the sitting ends (`assets/scripts/pr-sitting-comment.sh`).
It is keyed by the conversation's id under the marker
`<!-- gc:sitting:<task> -->`, and `pr-post.sh` counts a post that carries it,
or the marker reminders carried before it, as the city's own.

### The operator's intake

Every other producer attaches to a bead that already exists. The operator's
intake, `assets/scripts/operator-intake.sh`, answers "I need an agent on topic
X" where X has no bead yet:

```sh
operator-intake "why does the refinery hold siblings for a full pass?"
operator-intake tk-abc12                     # an existing bead is its own subject
operator-intake "a gascity topic" --rig gascity
operator-intake "just talk to me about X" --no-react
```

It creates the subject bead from the topic string. The string is the durable
**body**, which is what the sitting reads, and the title is a one-line label
derived from it, collapsed to one line and cut back to a word boundary with an
ellipsis when it is long, because `bd create` refuses a title over 500 bytes.
A bead id, a PR number or URL, or a superseded id resolves through
`gc-helm.sh resolve` to the live bead that owns the work, which is the subject
as it is.

**The bare command's default rig is fixed: `gc-toolkit`** (`--rig` overrides,
`GC_VISIT_DEFAULT_RIG` moves the default). Converse is `scope = "rig"`, so a
sitting spawns from the subject's own rig, and a topic that is not rig-specific
still has to land somewhere. The default is deliberately not inferred from the
working directory: a destination that varies silently with the shell's
directory is the worst failure an intake path can have.

**`prefix+a` picks the rig rather than defaulting it.** After the message
popup, `assets/scripts/tmux-intake-prompt.sh` shows a chooser of every rig but
the city's own store, which runs no reaction pool. A suspended rig is tagged,
not withheld, since a suspended rig keeps its beads store and a report filed
there is triaged on resume. The chooser defaults to the rig of the pane the key
was pressed in, the choice rides through as `--rig`, and a broken or empty
`gc rig list` skips the chooser and leaves the intake on the default. The
typed text goes through a draft file that is removed only once the intake
confirms an id or the file is provably empty, so a thought is never lost.

**A target with no reaction agent is refused, not filed.** The intake reads
the roster before it files: a rig with neither a proactive pool nor a
registered converse cannot engage an operator topic, so it refuses such a
target and files nothing. Registration is the bar, not liveness, and an
unreadable roster refuses nothing, so a degraded data plane never blocks an
intake.

**Two paths, and the choice is not a preference.** The preferred path files a
first reaction at the subject. The reaction triages it and takes one of its
dispositions. On the two that put the subject to the operator, a ruling or
a recommend, it files a human gate on the subject under the key
`first-reaction`, which reaches the operator on the board. A ruling is
Discuss-only. A recommend also records the formula it recommends as
`gc.recommended_formula`, so the row offers Accept beside Discuss. When the
reaction judges the action clear and reversible, it routes the subject, holds
it, or hands it to a validating closer, and puts nothing to the operator. A
capture that is not a member of an epic is not routed: it waits for the
operator's placement sitting ([steering.md](steering.md)).

The fallback path files a conversation in the operator's queue directly,
through `gc-helm.sh open`, which is where filing a conversation lives. It
runs on `--no-react`, when `tools/gc-proactive.sh deliverable` answers that
the proactive pool is not registered, is suspended or is capped at zero slots,
and when the reaction would file nothing: the subject already has an open
first reaction or a live owner owns it, a live workflow already drives it, or
it is already routed or armed. A react path that could not deliver would leave
a routed reaction bead nobody picks up and no conversation at all, the one
outcome this channel exists to prevent. A roster the deliverable check cannot
read answers yes, because absence of evidence is not evidence the pool is gone.

**The intake stamps `gc.origin=operator` on the subject**, on both paths and
never over an origin already recorded. It is a fact the reaction weighs, not a
gate: an operator capture is triaged on its merits like any other bead, and
what the preferred path buys is that a capture the reaction sends back to the
operator arrives framed, carrying the card the reaction wrote.

There is no mail-to-conversation bridge. A mail is already a bead and a
conversation is already a bead, so a bridge converts bead to bead for an extra
hop and puts a background process on the critical path of "the operator wants
to talk about X". External-origin intake, if it is ever wanted, belongs in Gas
City's own external-messaging process.

### Start talking now: create-and-engage a fresh subject

The intake files a topic and lets the reaction triage it: the operator gets a
board row, not a conversation. When the operator wants to talk now about
something that has no bead yet, `gc-helm engage --new-subject` creates the
subject and engages it in one gesture. It files the subject bead in a chosen
rig, files its one conversation, spawns the sitting and binds it. The
positional text is the subject's title and, absent `--reason` or
`--template`, its opener. `--rig` names the rig, an interactive prompt over
the converse-capable rigs asks otherwise, and `--no-input` requires it.
`prefix+A` is the keystroke, and it opens the interactive prompt in a new tmux
window (`assets/scripts/tmux-new-subject.sh`), because the choice of rig,
subject and model does not fit tmux's one-line command prompt.

The subject is created marked `gc.reaction_owned=1` in the same create, so
the proactive scan never observes it unmarked. Three gates read the marker:
the scan's precision filter drops a marked bead, the reaction-absent guard
refuses to file one, and a reaction that reaches a marked subject anyway
closes its own reaction bead without acting
(`first-reaction-dispose.sh --stand-down`). The engage is the reaction, and
the marker stays, so no later scan reacts. If a later step refuses the live
spawn, a bad model or a suspended rig, the subject's one conversation still
waits in the queue, so the topic is never lost.

## The sitting

A sitting's session is a manual session of the converse agent the operator
chose. It is manual because the pool execution backstop drains a pool session
that holds in-progress work and is quiet for 90 seconds, and a sitting is quiet
whenever the operator is reading or thinking. A manual session has no such
clock: its work closing does not end it, idleness only sleeps it, and
attaching wakes it.

**The claim.** The sitting claims its conversation with a plain
`gc hook --claim`. The default work query finds the task assigned to the
session, open through its second tier and in progress through its first, and
its routed tier is closed to a session whose alias is not its template's name,
so the sitting is offered nothing but its task. The claim sets `in_progress`,
a lease and the session stamps under the session's alias. The converse
templates declare a pool at zero (`min_active_sessions = 0`) with no
`scale_check` and no work routed to them, so no demand pass counts anything for
one, and `assets/scripts/pool-demand-wiring.test.sh` keeps those three rules.

**Recovery resumes the sitting through its alias.** A sitting whose session
sleeps, or whose runtime stopped, resumes when the operator attaches:
`wake_mode = "resume"` replays its transcript. Its claim is idempotent for its
holder, so `gc hook --claim` returns the conversation as an existing
assignment. A sitting whose session was closed cannot replay its transcript.
Engage starts a new session under the same alias, which a closed session does
not reserve, and the new session takes the in-progress task as its own. The
record carries over in the task's and the subject's notes. The converse
prompt's restart rule reads the conversation's notes: the hold writes a
`holding:` line there before it posts the framing, so a conversation carrying
one re-opens at prep and the hold, and one without it re-checks the premise.
Nothing in Gas City releases a sitting's claim on its own, and the pack's
witness recovery skips a conversation too, so the alias is the way back in.

**The premise re-check.** The condition that justified a conversation, or a
gate it replies to, routinely dies before the operator engages it. The sitting
reads the premise from the conversation's ask and from the title and framing
of each gate it replies to, and checks it against live state. A gate whose
premise has died is resolved `moot:`, and one whose premise holds but needs
nobody `benign:`, with the reading as the answer. When the conversation's own
ask has died with it, the sitting appends the reading to the subject's notes
and closes the conversation with it, posting nothing and stamping no headline.
A gate's message is written when it is filed, so the sitting runs the re-check
command a gate names, as the liveness sweep's gate names
`liveness-recheck.sh`, through the pack's own copy, and its census supersedes
the message's lists.

**The hold** is the operator owing an answer later. The sitting keeps its task
claimed and the session stays, because the converse templates keep
`idle_timeout = "0"`. Before it posts its framing, the hold appends the
`holding:` line to the conversation's notes and the same line to the subject's,
and writes what the operator owes as the subject's headline,
`holding — <the one decision needed>`. The headline names the gate that holds
the subject with `--waiting-on`, or says `--no-wait` when nothing holds it but
the conversation, so `doctor/check-wait-is-an-edge` never reads an unedged
hold. The gates the conversation replies to stay open and owed. When something
must wait for the answer and no gate the conversation replies to holds it, as
when the merge must not land before the operator rules, the sitting files a
human gate through the helper on the bead that must wait: the anchor when the
merge must wait, or the one member whose work waits. A gate another
conversation filed there asks that conversation's question, and its ruling
releases the bead whether or not this one is settled. So the key names the
conversation, `conversation.<conversation id>`: a resumed hold finds the gate
it filed, and two conversations on one bead each hold with a gate of their
own, so the merge waits for both rulings. The sitting replies to its gate and
reads the reply back, so a resumed or handed-off conversation knows the gate
it owes. Without that need it files nothing: a conversation does not
freeze its subject, and a PR keeps moving while the operator and the sitting
talk. An unanchored subject that a gate blocks moves to `held` and back through
`lifecycle.sh`, because a held bead must carry a live edge. A hold does not use
`gc session wait --sleep`, which sets a wait hold the controller then drains,
destroying an attached operator's pane.

**Answering a gate.** A sitting answers only the gates its conversation
replies to: the gate engage was pointed at, one its hold filed, and any other
human gate the operator rules on within the subject's universe, which the
converse prompt defines as the subject with its dependents and related items,
and for an epic the work under it and in flight across it. To answer a gate
its conversation does not reply to yet, the sitting adds the reply and reads
it back, so the graph records which conversation answered which gate. Before it
resolves a gate, it names every bead the answer releases, read from the gate's
`blocks` dependents, so an answer that releases a bead beyond the subject is
given knowingly. The record and the headline go on the subject alone: a rework
child waiting on its anchor's bring-current gate, or a member of an epic whose
gate the epic's sitting answers, reads the answer in the gate's resolve
reason, through its own `blocks` edge. A gate with no tie to the subject takes
its own conversation, so its outcome never lands in the notes of a bead that is
not about it.

**The first answer wins.** bd resolves a gate already closed without changing
it and reports success either way, so every resolver reads the gate back. A
close reason other than its own means another answer reached the gate first: a
filer's withdrawal, an Accept, another sitting, or a person at the command
line. That answer stands, and the resolver reports it instead of claiming its
own.

**The sign-off** is `assets/scripts/converse-signoff.sh`, which writes the
durable trace in one order every time:

1. what a ruling does to an open PR it reaches, the subject or a PR that a
   gate it answers releases: its rework, through `converse-rework.sh`, with
   the conversation as the rework child's `source_ruling_bead`, so a ruling
   that changes what the PR's branch must contain becomes work the refinery
   lands; or its retirement, through `pr-dispose.sh`, which records the
   disposition and closes the PR;
2. the subject's headline;
3. `ruled: <the ruling>` on each open gate the conversation replies to that the
   ruling answers, each read back, with an earlier answer reported;
4. the release of a `held` subject;
5. the subject's recommendation, when the ruling takes it (`--accept`): the
   recommendation's gate, which step 3 leaves, is answered by Accept's writer
   (below), which sends the formula once;
6. the conversation's close, whose reason is the headline the sitting settled
   on;
7. the PR reminder.

It resolves no gate its conversation does not reply to: a gate the sitting
never took up stays for whoever owes it, and a gate it replies to that the
ruling leaves owed stays open with its reply in place. It reads those gates
from the conversation's own row (`gc bd list --id <task>`), whose edges keep a
reply onto a gate in another store. Every read it depends on runs before its
first write, and it stops short, with nothing posted, when any write does not
read back, so a re-run repeats each write safely. A gate can be what holds a
merge, and resolving it releases the merge, so whatever the ruling puts in the
merge's way lands before any gate is resolved. A ruling that reaches an open
PR must say what it does to the PR (`--rework`, `--no-rework` or `--retire`),
and the rework child's `blocks` edge or the closed PR is in place before step
3. It reaches the subject when the subject is an open PR, and each open PR
that a gate it answers releases, such as a member of an epic subject. The
rework or the retirement acts on one PR, which `--pr-anchor` names when the
ruling reaches more than one, and each other one stands. It runs in that PR's
own rig, with its store, pool and checkout, when a gate in another rig's store
releases it. The PR it acts on is recorded on the conversation first
(`gc.ruling_consequence`), so a re-run of the same ruling acts on the same PR.
A re-run that finds that PR closed, as a retirement leaves it once pr-facts
consummates it, goes on without it. A conversation owns one live rework, so
a second PR whose branch must change waits behind its gate, left owed, for a
ruling of its own. A
sitting signs off only when nothing important is pending; a turn that hands
the operator something to read or answer posts the hand-back and leaves the
conversation open. A gate the operator rules on during such a turn is answered
at once, so a dismiss that ends the sitting later leaves nothing the operator
ruled on open. It is answered through the same script with `--answer <gate>`,
which runs steps 1 to 3 for the gates it names, and step 5 when the ruling
takes the recommendation, and stops there, leaving the conversation open for
the sign-off.

**A sitting cut short** writes its record, signs off with `--ruled no`, which
leaves every gate its conversation replies to open and owed with its reply in
place and hands the conversation back to the operator's queue with one write
guarded on the sitting that holds it and on the status it read, and drains.
The task is then the queued conversation it was before any sitting took it,
so the board shows it owed and the next engagement takes it up from its
record. A dismiss closes the conversation and keeps its holder, so the status
guard is what keeps the hand-back from reopening a conversation the operator
dismissed while the sign-off ran.

**Dismiss** (`gc-helm dismiss`) ends a sitting. It closes the conversation a
live sitting holds on the bead, or the conversation an id names, with a reason
that names the dismissal, and it answers nothing: every gate the conversation
replies to stays open and owed, for its filer or the next sitting. With no
argument it infers the current sitting from the session it runs in. The close
falls back to `--force` when bd refuses an operator closing a conversation its
sitting holds. It then stops the converse session that held each conversation
it closed, with `gc runtime drain-ack`: the session it runs in acks itself,
last, and any other is acked as an operator. On a bead with no live sitting it
writes nothing and says so. `prefix+X` runs the same dismiss from the keyboard
after a y/n confirm (`assets/scripts/tmux-dismiss-sitting.sh`), under the
pane's own session. It passes `--operator`, because the keystroke comes from
outside the sitting, and dismiss stops the session with an operator ack. That
ack runs with no session identity or incarnation token: the key's job
inherits the sitting's tmux environment, and Gas City refuses an operator ack
whose caller names the session it stops.

**A sitting ends its own session.** Gas City does not end a manual session
when its work closes, so once a sitting's conversation has closed, or its
sign-off has handed the conversation back, its last act is
`gc runtime drain-ack`. The `converse-reap` order
(`assets/scripts/converse-reap.sh`, every five minutes) is the backstop: it
closes any converse session whose conversation has closed, is gone, or is back
in the operator's queue, attached or not, once the session is older than the
reap's interval, which keeps it off a session engage has started and not yet
bound. A session whose conversation closed or came back to the queue also
waits until the conversation has taken no write for that interval, because the
sitting records its last hand-back on the conversation on the tool call after
its sign-off, and the operator's tab prints that record once the session ends.
It reads the
conversation's id from the session's alias and strips the `c-` prefix. Its
warrant, with the trigger that retires it, is in [warrants.md](warrants.md).

## Accept

A first reaction's recommend exit puts its recommendation to the operator as a
human gate under the key `first-reaction` and records the formula as
`gc.recommended_formula` on the bead. Accept is the operator's answer to that
gate alone. The board offers it while all three hold:

1. the bead carries `gc.recommended_formula`;
2. the recommendation's gate is open and unassigned, or closed with an
   acceptance an earlier Accept did not finish;
3. no other open human gate blocks the bead.

Accept clears one gate because separate situations on one bead stay separate
gates, and each gate's close does something of its own: a `ruled:` close
releases a needs-you finding, and any close releases what waits on the gate.
It waits for the others because a formula sling reads no `blocks` edge, so an
Accept that slung while another gate stayed open would start the work before
that gate was cleared. While another gate blocks the bead, the row offers
Discuss and names the gates that withhold Accept (`accept_withheld`), and a
sitting answers them. A live sitting does not withhold Accept; Accept warns
when one tracks the bead or replies to the recommendation's gate, and that
sitting's sign-off later reports the gate already cleared.

`gc-helm.sh accept` runs under the bead's acceptance lock, a `flock` on one
file per bead under `<city>/.gc/runtime/packs/gc-toolkit`, from before its live
read of the three conditions to its last write, and refuses, writing nothing,
while another Accept holds it. On an open gate it records the acceptance's
dispatch input on the gate (`gc.acceptance`: its token, the formula and each
var) and reads it back, resolves the gate with
`ruled: accepted <formula> accept:<token>`, reads its own answer back, reads
back that no other open human gate blocks the bead, releases a bead that reads
`held` to `unanchored`, slings the formula titled `<formula> accept:<token>`,
and records the dispatch by stripping `gc.recommended_formula` beside
`gc.recommended_formula_dispatched`. A sitting's hold moves an unanchored
subject to `held` while the operator owes the answer of a gate that blocks it,
and mol-polecat-work's load-context cancels a run poured at a bead that still
reads `held`, so the release comes before the sling. An answer another reached
first stands, and Accept slings nothing. A gate filed in the meantime, or a
sling that poured no root, reopens the recommendation's gate. A run that
stopped after its resolve, or whose release did not land, leaves an unfinished
acceptance, which the board keeps owed and the next Accept finishes under the
same token, slinging only when no root carries the token. That sling carries
the vars the acceptance recorded, whoever finishes it: the board's Accept
passes none, and a run given vars other than the recorded ones dispatches
nothing. The lock's warrant is in [warrants.md](warrants.md).

A sitting takes a recommendation through the same writer. When the operator
rules to take it, the sign-off's `--accept` leaves the recommendation's gate
out of step 3 and runs `gc-helm.sh accept` at step 5, once the ruling's other
writes have landed and a `held` subject is released, because mol-polecat-work's
load-context cancels a run poured at a bead that still reads `held`. Under the
lock, that run finishes an acceptance the board's Accept left unfinished
instead of sending the formula again, and a board Accept that runs after the
sitting's finds the recommendation dispatched. Gas City's launch lock refuses
a second pour only while the first root is live, so a sling of the sitting's
own would pour the formula again once the stopped Accept's root had finished.
A var the ruling settles for the dispatch, such as a design convoy's
`design_gated` ([design-convoy.md](design-convoy.md)), rides the sign-off's
`--var` to Accept's sling. The sign-off refuses `--accept`, writing nothing,
while a human gate the ruling does not answer still holds the subject. The
recommendation's gate is one under the key `first-reaction` that blocks the
subject: a gate under that key on an epic's member asks the member's
recommendation, which Accept on the epic never answers. So the sign-off also
refuses `--accept` unless the ruling answers one of the subject's own gates
under the key, and each gate Accept would answer there. An
`--answer` turn releases nothing of its own, so Accept's writer releases a
subject that reads `held` before its sling.

## How a parked subject comes back

A sitting that reaches a conclusion leaves its subject with a `gc.takeaway`,
one board-visible headline of what was settled or what is being waited for. A
takeaway exempts nothing anywhere in the liveness family —
`liveness-sweep.sh`, its precheck and `liveness-recheck.sh`. The wait it names
does, for as long as that wait is live, and every shape the wait takes is a
rule those scripts already apply: a `blocks` blocker, which
`takeaway --waiting-on` and a human gate both write, keeps the bead out of
`bd ready`, the set the sweep classifies; a child reaches the parent-child arm;
and a `tracks` target reaches its own. A parked subject whose routed work has
all landed therefore returns as an ordinary unnamed wait in the sweep's batch
gate on the rig's triage subject, and the takeaway is never cleared: it is the
record of what the sitting concluded.

**Routed work is wider than the board's disposition-due.** The board derives
"blocker landed — dispose or resume" from the `blocks` edges
`gc-helm takeaway --waiting-on` writes. Routed work filed as a child of the
subject cannot carry that edge, because bd refuses a `blocks` edge from a
parent onto its own descendant
([gascity/human-engagement.md](gascity/human-engagement.md#a-parent-cannot-be-blocked-by-its-own-descendant)).
The sweep therefore reads the union of the subject's `blocks` edges and its
children, and readiness is that at least one recorded wait exists and every one
of them has closed. Work routed with neither recording, a sibling named only in
the takeaway's prose, is invisible to both.

**So routed work is filed beside the subject.** A dependency the subject waits
on is a sibling, taking the subject's own parent when one applies, and the
sign-off's `takeaway --waiting-on <work>` then takes. Work that genuinely
decomposes an epic subject is the one exception: it is the epic's member, and
containment carries the wait. Routed work already filed as a child stays where
it is, and both readers handle it.

**Where prose alone is correct.** `gc-helm.sh takeaway` writes prose with no
edge at two call sites, and both pass `--no-wait`, which stamps
`gc.takeaway_settled`: `lifecycle/lifecycle.toml` `[holds]` reads a takeaway
as a hold unless its writer stamped that key beside it.

- **A settled sitting.** The takeaway records what the sitting concluded.
  Nothing is owed and nothing is waiting, so there is no bead to point an edge
  at.
- **A stand-down (`takeaway … --release --no-wait`).** The dispatch's premise
  is falsified and the work should not happen. The anchor is parked, and the
  run beneath it is cancelled through gascity's run cancel. An anchor already
  closed takes the cancel without the park, and `--route` is refused there.
  `assets/scripts/stand-down.sh` runs this write for work a human gate holds, after
  it removes the arm that would re-sling the work, and goes on to answer the gate
  and close the bead.

Everywhere else a takeaway carries its wait as an edge: `--waiting-on` for
work a pool owes, a human gate for what a person owes. A headline written with
neither the edge nor the flag is a subject parked on a sentence, and
`doctor/check-wait-is-an-edge` reports it. No agent in the pack writes a
`triage.hold`; the liveness sweep's disposition menu offers a human gate in its
place.

## How a held sitting ends

Every `converse-<model>` template sets `idle_timeout = "0"`, which takes a
sitting off the idle ladder entirely: Gas City never registers a template whose
idle timeout is at or below zero with its idle tracker
([gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder)). A
held sitting therefore ends when its conversation closes: the sitting's
sign-off, or the operator's `gc-helm dismiss`. The sign-off is terminal, so
converse takes it only when nothing important is still pending. Closing the
conversation ends the session too, whichever path closes it. The sitting's own
last act is `gc runtime drain-ack`, after the sign-off or a moot or benign
close, and it never claims again: a closed conversation has no next turn in
that session. `gc-helm dismiss` closes the conversation and then stops the
session that held it, also through `drain-ack`, so the controller ends the
session outside the verb's process; a dismiss typed into the sitting's own
pane acks its own session last. The pack's `converse-reap` order
(`assets/scripts/converse-reap.sh`) is the backstop: it closes any converse
session whose conversation reads closed, gone or back in the operator's
queue, whether or not anyone is attached. Viewing a sitting does not hold it
open (*How a pane dies when no sitting is live*, below). A sitting whose
conversation is still open, because the operator walked away before any
sign-off, keeps its session running indefinitely.

A conversation can also outlive its sitting: the sitting's create fails after
`gc-helm engage` bound the conversation to it, or its session is closed while
the conversation is still open. The conversation keeps the alias of a sitting
whose session has ended. The board reads it as waiting for the operator,
because no live sitting holds it, and `gc-helm engage` takes it up again:
under the same alias, or bound to a fresh sitting's with a write guarded on the
holder it read, which also drops the session pins the gone sitting's claim
left.

A conversation whose sitting failed to start reads `start failed` on the
board instead, with the reason Gas City recorded: a startup timeout, a setup
timeout, a provider error such as a quota exceeded, the start's error, or
never started when Gas City recorded no cause
([gascity/human-engagement.md](gascity/human-engagement.md#a-failed-start-is-recorded-on-the-session-bead-and-in-a-startup-health-episode)).
The board reads that record itself, so the mark shows as soon as the failure
is recorded, and it stays until the conversation is engaged again or closed.
The row leads the operator's queue, so the tmux picker offers it
(services/helm/README.md, "A sitting that failed to start").

Two endings the idle setting does not own:

- **A settled sitting ends itself, not by a runtime clock.** A sitting is a
  manual session, which Gas City keeps desired for as long as it is neither
  closed nor drained
  ([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)),
  so the `no-wake-reason` drain that collects an ended pool session in about
  a minute never reaches it. Its own `drain-ack` ends it, `gc-helm dismiss`
  stops it, and `converse-reap` above closes one that outlives its
  conversation anyway. See *How a pane dies when no sitting is live*, below.
- **No max-age restart reaches a sitting.** No `converse-<model>` template
  sets `max_session_age`, and an unset age is off. Gas City's max-age restart
  defers while the session holds open assigned work and has no attachment
  rung ([gascity/human-engagement.md](gascity/human-engagement.md#max_session_age)),
  so it would fire on the first tick after the conversation closed and destroy
  the pane and its scrollback under an attached operator.

The cost is real: a held conversation nobody answers keeps its sitting's
session running, where an idle clock would recycle it, and
`max_active_sessions` does not cap a manual session. `gc-helm dismiss` is the
release valve, and converse puts it at the foot of every framing it posts as a
copyable line, so ending a sitting is a switch in the thread rather than an
errand the operator has to remember.

The ending the pack cannot reach from config at all is the pane itself: Gas
City's stop destroys the tmux session, its pane and its scrollback on every
stop path
([gascity/human-engagement.md](gascity/human-engagement.md#stopping-a-session-destroys-its-pane)),
so any stop takes the thread whole.

*Seam:* **nothing pack-owned runs at kill time**, so there is no
warn-before-reap. So the record is written in advance: the hold records what is
owed before it waits, the outcome is appended as soon as a sitting settles
anything, and every deliberate close of a held sitting ends with a sign-off
naming the outcome and the subject to look at next. Raising `idle_timeout`
would only widen the window in which a dead thread looks alive; taking the
clock off rests on different ground, that a thread the operator is reading
must not end without them.

*The size of that trace:* a takeaway is capped at **140 characters**, which
`gc-helm takeaway` enforces by refusing a longer text rather than trimming it.
Whatever does not fit is detail, and detail belongs in the subject's notes or
the thread.

*The limit of a written trace:* a takeaway is one string, frozen when it is
written. That is enough for a reap, because the record survives, and not
enough for a wait, because nothing in the city re-reads prose. So a routed wait
is also written as a `blocks` edge, `gc-helm takeaway <subject> "…"
--waiting-on <work-bead>`, and the board re-derives on every render whether the
blocker has closed, promoting the row to "blocker landed — dispose or resume"
when it has. A wait whose work has already landed on the subject's own branch
is the one the verb folds: its deliverable is in the subject's head, so the
subject's own merge lands it, and `takeaway` writes no edge there, because an
edge would gate that merge on work that merges with it. Landed is proven, not
assumed from the shared branch: the wait is closed, or handed off to the
refinery.

*A conversation that never held closes silently* — no sign-off, no thread
output, only the reading appended to its subject. That is step 2's moot or
benign close. The sign-off exists because an unanswered framing left in a
vanishing thread reads as a crash; where no framing was ever posted there is
no question to abandon. An earlier sitting on the same conversation may have
held and been cut short, leaving its subject `held`, which only a ruling's
sign-off, an Accept, this close or a person moves back. So the close reads
the subject's state first. A held subject that no open human gate still holds
goes back to `unanchored`, routed to `human`, and the reading replaces the
hold's headline. The conversation closes only once those writes read back.

*A restart is not an ending.* A wake that reaches a session mid-hold gets its
conversation back from `gc hook --claim` as an existing assignment. Draining
then would end a sitting the operator has not ruled on, and running the loop
from its premise re-check could close a conversation the operator is part way
through, so the converse prompt's restart rule reads the conversation's
`holding:` line and re-opens the hold rather than doing either. A wake nudge
that names `gc hook --claim` alone, rather than sending the session through the
prompt's claim block, skips that rule, so every `converse-<model>` template
holds its `nudge` empty. Emptiness is not what protects a held sitting: a
sitting runs as a manual session, never pool_managed, and no claim backstop
governs a session that is not pool_managed
([gascity/human-engagement.md](gascity/human-engagement.md#the-controllers-backstops-govern-pool-sessions-only)).
What the empty field reaches is the launch delivery, where the prompt is
prepended to it and still arrives.

Attachment is the one reading signal the runtime has, and only this city's
gascity fork reads it: there an attached terminal defers the idle stop, a
detached reader is still indistinguishable from abandonment, and the max-age
restart ignores attachment altogether
([gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder)).
That is why the trace is written when the hold begins rather than bought with
a longer clock, and why no converse template sets `max_session_age`.

## How a pane dies when no sitting is live

The section above answers "what ends a **held** sitting". Once a sitting
ends, its session goes with it, and with the session its pane.

**The sitting ends its own session.** A sitting is a manual session, and Gas
City keeps a manual session desired for as long as it is neither closed nor
drained and its template is still configured, so the `no-wake-reason` drain,
which begins when a live session has no wake reason left, never begins for a
sitting
([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)).
Nothing idle-sleeps one either: that takes a `[chat_sessions] idle_timeout` or
a `[session_sleep]` policy, and this city sets neither. So a sitting ends its
own session: once its conversation has closed and every write that must
follow the close has run, its last act is `gc runtime drain-ack`, and the
controller stops the session. `gc-helm dismiss` stops the session that held
the conversation it closes the same way. The `converse-reap` order
(`orders/converse-reap.toml`, a five-minute cooldown) runs
`assets/scripts/converse-reap.sh`, which closes any converse session whose
conversation reads closed, gone or back in the operator's queue with
`gc session close`, attached or not: the backstop for a session that outlives
its conversation.

**Viewing a sitting does not hold it open.** The city's tmux server carries
several clients at once: the operator's main connection, and a terminal tab
on each sitting the operator opened with `gc-helm engage`. The server's
global `detach-on-destroy` is off, which moves every client of a destroyed
session to the most recently active other session. Each `converse-<model>`
template sets the option on for its own session (`session_live` in its
`agent.toml`), so a plain client on a sitting exits when the sitting's
session ends, and tmux shows `[exited]`. A client attached with
`-f no-detach-on-destroy`, as the operator's main connection is, and every
client on any other session still move on. `gc-helm engage` runs its attach
as a child, so when the tab's client exits it reads the conversation. A
closed conversation prints how it closed and the last hand-back the sitting
recorded on it (`gc-helm handback`, which the sitting runs before each
framing and its sign-off); a conversation still open prints the command that
re-attaches. Claude draws in tmux's alternate screen with no history, so
nothing of the pane survives to recover, and the record on the conversation
is what the tab prints.

Three things about that path are worth knowing before trusting a pane:

- **Nothing is typed into the pane; the pane is taken whole.** Gas City's
  stop kills the tmux session and then signals the pane's captured process
  tree, with no Ctrl-C keystroke injected into the pane first
  ([gascity/human-engagement.md](gascity/human-engagement.md#stopping-a-session-destroys-its-pane)).
  So a reply typed into the composer but not submitted when the sitting ends
  goes with the pane.
- **A restart ends the tab too.** A restart destroys the session's tmux
  session and starts a fresh one, so a plain client on the sitting exits as
  it does at the end. The conversation still reads open, so the tab prints
  the re-attach command, and `wake_mode = "resume"` brings the thread back.
- **A pool session ends differently, and a sitting is outside it.** A pool
  session left with no wake reason is drained as `no-wake-reason` about a
  minute after its last wake reason goes, and the reconciler acknowledges that
  drain on the agent's behalf, so its stop event reads
  `"drain acknowledged by agent"` even when the agent never ran
  `gc runtime drain-ack`
  ([gascity/human-engagement.md](gascity/human-engagement.md#a-pool-session-with-no-wake-reason-is-drained)).
  A sitting's stop event reads the same, and there it is the sitting's own
  `drain-ack`.

**What the design holds to.** A sitting ends its session as soon as its
conversation closes, whichever path closes it, and nothing holds a session
open because someone is viewing it. Nothing copies the pane, and no pane,
live or dead, stays on screen after its session ends, so what a tab prints is
the record on the conversation.

**What follows for the pack.** The record has to be written before the pane
matters: what is owed recorded at hold time, the outcome appended as soon as
a sitting settles anything, each hand-back recorded on the conversation as it
is posted, and the sign-off posted at close. What it does not protect is the
operator's *own* unsent words.

## Watch items — moving now, re-verify before building on them

- **The roles pack's growth** — every new upstream role is a standing
  question against a hand-authored one here. When upstream ships a role
  covering something the pack hand-authors, re-argue adoption for that role
  specifically.
- **Dashboard surface** — upstream ships `gc dashboard` (a Vite SPA over the
  supervisor API); the pack's sanctioned augmentation seam is the
  `proxy_process` `/svc/` route, which `services/helm/` already uses. Any
  conversation surface work lands behind that seam, not in new bespoke
  plumbing. The supervisor API carries no `await_type`, so a board built on it
  alone folds no human gate ([gascity/human-engagement.md](gascity/human-engagement.md#where-a-question-surfaces)).
- **Two programs behind one board.** `prefix+b` runs `tmux-pick-helm.sh`,
  which reads the board from `helm-svc board` and engages through
  `gc-helm.sh`, and the dashboard serves the same `internal/source` gather and
  `internal/board` derivation. `gc-helm.sh` keeps the write verbs (`open`,
  `engage`, `react`, `takeaway`, `dismiss`, `accept`, `park`, `priority`) that
  have no Go equivalent, and helm-svc's POST routes run them. A change to the
  gather, the ranking or the anchor kinds is a standing question against both
  surfaces; say in the PR which one you touched and whether the other needs the
  same change.

## What upstream does not ship (the pack's actual seam)

This is the genuinely native ground, and it is deliberately small.

- **The hold on the gate.** Upstream has the wait (human gates, `blocks` edges
  — work durably stops) and a mail reach for it. It has no role that services
  the wait: every upstream role's contract is claim, execute, close, and none
  holds a conversation `in_progress` for a person, having rebuilt the subject's
  context and framed the choice, then records the answer to the subject and
  clears the gate. Gate and hold are two halves of one mechanism: the gate
  makes the work wait, and the sitting makes the wait worth arriving at instead
  of a parked bead you cold-start yourself.
- **The board's judgment — as a lens, never a dependency.** Ranking what
  deserves the operator's glance, derived from real graph state (open gates,
  queued conversations, stranded work), with visual consistency. Everything
  works without the board: work moves entirely on graph state, and the board
  renders it and is never a mechanism anything depends on.
- **Ratification and record-residency for filed trees.** Upstream's build
  factory decomposes a brief into requirements, a plan and a tree of beads.
  What it lacks is a gate before the tree lands and a record-resident plan, so
  re-planning re-files instead of diffing. The native ground is the gate on the
  tree, not the tree-making.

**A sitting is not a unit of work, and it acts on its subject's universe in
coordination with the operator.** It files beads, slings them to a pool, wires
edges, answers gates and appends an outcome to the subject; and on an
operator-agreed ruling it acts on the subject's PR — commenting, replying to
and resolving review threads, and retiring it, which closes the PR and disposes
the anchor as superseded. It writes no files and makes no commits, because
moving a bead forward is what a molecule does, so a sitting that finds work
needing doing routes it to one, and where nothing can reach the work, the gap
is itself a bead to file. The one line it does not cross is a repo change. What
reaches the operator is the point where the operator is needed for a judgment,
which is narrower than judgment and narrower still than action.

Everything else in the engagement model is assembly of the primitives above —
which is the point.

## Refresh procedure

This page states the pack's own model, so it changes with the pack's code:
update it in the same PR as a change to a human-gate filer, `gc-helm.sh`, the
converse prompt or skills, the sign-off, the reap, or the board. The Gas City
facts it links are re-verified by the refresh procedure in
[gascity/human-engagement.md](gascity/human-engagement.md#refresh-procedure);
when one of them moves, re-derive the seam here that rests on it.
