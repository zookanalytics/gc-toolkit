---
name: Human engagement — gc-toolkit's subject, human gate and conversation model
description: gc-toolkit's own model for engaging a person — the subject, the human gate and the conversation, how a gate reaches the operator, the way in through Engage, how a conversation starts, how a sitting claims, holds, answers and ends, Accept, how a parked subject comes back, how a po sitting opens, the helm board, and the ground the pack builds itself. A pack convention; the Gas City primitives it rides are gascity/human-engagement.md.
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
  the conversation onto the gate. Neither edge holds anything. A conversation
  on an open PR holds the PR's merge until it closes, and otherwise blocks
  nothing: the PR's anchor depends on it (*A conversation on an open PR holds
  its merge*, below). Its description is the ask, the concern the operator
  brought or the gate engage was pointed at. It is assigned to `human` while it
  waits in the operator's queue, and to its sitting's alias while a sitting
  holds it. Two dialogues about one bead are two conversations.
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
human gate reaches the operator, the way in through Engage, how a conversation
starts, how a sitting claims, holds, answers and ends,
Accept, how a parked subject comes back, how a po sitting opens, the helm
board, and the ground the pack builds itself.

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
  filer's own gate as moot once the situation has gone. Two writers in the
  same instant can each file, because bd keeps no idempotency at create. Both
  gates then stand, and the bead moves once a person has cleared each. The
  helper closes neither, because another bead may already wait on it. Every
  reader finds a bead's human gates one way, through the bead's `blocks` edges
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

## The way in

The operator comes in through Engage. A bare `gc-helm` on a terminal opens
engage's form on starting a conversation, with the cursor in the subject. The
form's pages are tabs at its top, and each page has a key of its own, which its
tab shows before its name:

- **Start a conversation**, Ctrl+N, takes a subject, a bead, a PR, or a rig's
  name or prefix for a new topic, and the question (*Engage*, below).
- **Return to a conversation**, Ctrl+R, lists the open conversations
  (*Returning to a conversation*, below).
- **People**, Ctrl+P, lists the seats the operator sits with: mechanik, of
  which the city has one, and each rig's po, the Product Owner, by its rig's
  name and prefix. The city's HQ has none.

A page's key goes straight to that page from any page and any field, and the
key of the page on screen does nothing. In the question, Ctrl+N and Ctrl+P go
to their pages rather than to the line below and above, and ↓ and ↑ move
between its lines. Start a conversation comes back as the operator left it,
with what they typed and the cursor in the field it was in. The screen that
shows a save or a start as it runs is not a page, and the pages' keys do
nothing there.

↑ from the subject reaches the tabs, and ←/→ move along them, wrapping around
at either end, as they cycle a value on the form's choosers. ↓ goes back down
to the subject. On a list page ←/→ move along the tabs at once. The tabs are no
field Tab moves through, so the question stays one Tab after the subject.
`gc-helm attach` opens the form on the return page.

The People page is the one way Engage opens a person. Each row shows the state
Gas City's session list gives the seat's session, such as active or asleep,
and whether a terminal is attached, or no session when the list holds none, as
for a po that has never run. The session is the one the city's agent roster
(`gc agent list`) names for the seat, so a seat the roster names no session
for, or several, is not listed. When the roster cannot be read, the page lists
no seat and says the seats did not read, and the other pages still list. A
suspended rig's po reads rig suspended, since Gas City starts no session in a
suspended rig, and the page says why it cannot start and how to resume the rig. The page reads the city again every ten seconds
while it is on screen. ↑/↓ pick a seat, a line says what Enter does for it, and
Enter leaves the terminal and then runs the seat's command, `gc-helm mechanik`
or `gc-helm po --rig <name>`, as the form runs a conversation's attach. So all
the command prints stays on the terminal and its exit status is the form's.
Each command attaches to the seat's session, starting it first when it is not
running (*A po sitting*, below). Gas City's attach carries no message, so a
seat takes no question, and the sitting's purpose is given in the sitting. The
subject on the start page takes no seat. A bare `gc-helm` without a terminal
prints its usage and exits 2, so no script blocks on a form.

## How a conversation starts

A conversation starts three ways: the operator engages a bead or a gate, the
operator's intake files one, or something asks the operator to talk a bead
over with `gc-helm.sh open`. A conversation in the queue starts no session,
because assigned work wakes only the session whose identity it carries and no
session carries `human`. A sitting starts only when the operator engages.

### A conversation on an open PR holds its merge

A conversation on an open PR holds the PR's merge until it closes, and
otherwise blocks nothing. The subject counts as an open PR when it is the PR's
anchor (`merge_result=pull_request`, not closed), or a bead whose
`anchor_bead` names that anchor, such as the PR's review, rework or
supplement. The hold is bd's own: the anchor depends on the conversation
through a `blocks` edge, so bd counts the anchor blocked while the
conversation is open and lets it go once the conversation closes.

- **Opening the conversation adds the edge.** `gc-helm.sh open` adds it for a
  conversation it files and for one a second concern joins in the queue, and
  every way a conversation starts goes through `open`, engage's included.
  Engage adds it again whenever it starts a sitting, so a conversation filed
  before its PR opened, or one whose sitting lifted the hold, holds the merge
  once it is engaged, and the sitting's hold adds it when the PR has opened
  since the sitting started. bd takes an edge it already holds as a no-op. A
  read of the anchor that does not answer files nothing, and an edge the store
  refuses is reported with its repair.
- **While the conversation is open, the PR is held.** The merge pass holds a
  PR while an open bead blocks its anchor. The PR reads `needs-attention` with
  `held: blocked`, naming the conversation, by the one definition its labels,
  the board and engage read
  ([state-machine.md](state-machine.md#the-status-label-github-projection)): a
  conversation is a bead a person owes the next move on. The edge holds only
  the merge. Reviews, reworks and supplements keep running, because each is a
  bead the anchor waits on, which the edge does not block.
- **Every close frees the merge.** The sign-off, a dismiss, the premise
  re-check's moot or benign close and a close by hand each end the hold with
  the close itself, and nothing writes a release. A close that does not land
  leaves the conversation open and the merge held. A conversation handed back
  to the operator's queue is still open, so it still holds the merge.
- **A sitting that is helping the PR land lifts the hold**, the shepherd case,
  and so does one whose conversation has nothing to do with whether the PR
  should land. It removes the edge with
  `gc bd dep remove <anchor> <conversation>`, records why on the conversation
  and says so in its framing. The lift lasts for that sitting: a later sitting
  that engage starts on the conversation holds the merge again, and the
  conversation form's save again (`open --conversation`) leaves the hold of a
  conversation a sitting has taken as that sitting left it.
- **A hold the operator wants to outlast the conversation** is a gate of its
  own on the anchor, under a key that names what it waits for.

Before a PR opens, its anchor is the work itself, and an edge onto the
conversation would stop that work: the pool's offer, the work gate at
load-context, the refinery's hand-off and the bead's close. So a pre-open
anchor takes no edge, and a conversation on any subject that is no open PR
files a gate only when something must wait for its answer (*The sitting*,
below).

### Engage

`gc-helm engage` (helm-svc's engage route runs it) takes
these steps:

1. **It takes the bead.** Given a bead, it works on that bead. Given a gate, it
   works on the one bead still waiting on the gate, read from the gate's
   `blocks` dependents. With several still waiting, as when an anchor and its
   rework child both wait on the anchor's bring-current gate, it works on the
   bead `--from` names when that bead is one of them, and a gate that no longer
   holds the `--from` bead starts nothing. Otherwise it works on the bead whose
   `blocks` edge onto the gate is oldest, then the lowest id. An edge's age
   never changes while a priority can, so engaging the question again lands on
   the same bead and finds the conversation filed there, and since
   `gc bd gate create --blocks` writes a gate with its first edge, that bead is
   normally the one the question was asked about. A conversation filed on the
   question carries a note naming the other beads the gate holds, and one that
   `open` or engage lands on that does not name them as they stand takes the
   same note, once, so the sitting sees each bead its answer reaches. The note
   stays out of the conversation's ask, because the beads waiting on a gate
   change while the question does not, and a save again finds its conversation
   by the ask. `accept`, `dismiss` and
   `handback` refuse such a gate, naming its beads, because a pick there would
   act on a bead nobody named. With none waiting, engage says nothing waits on
   the gate, names any closed bead the gate was about, and starts nothing, and
   the operator clears the gate.
2. **It reads the bead's conversations:** the open tasks that track the bead
   in the conversation shape, with the session list saying which of their
   sittings are live.
3. **A concern opens a fresh conversation.** A `--reason`, `--template` or
   `--skill`, or the operator's choice of a new conversation when engage asks,
   files a new task whose description is that concern, even when the bead has
   a conversation already, because a distinct concern is a distinct dialogue.
4. **Without one, it attaches first.** A conversation a live session holds is
   a live sitting, and engage attaches the operator to it rather than starting
   a second. A session the list shows with no state is live, since Gas City's
   own wait for a new session reads it as a create still under way. Otherwise
   it takes the bead's conversation from the queue, or one
   whose sitting's session has closed, or files a new one. Pointed at a gate,
   engage makes the conversation it landed on reply to the gate before it
   starts or attaches anything, and a reply the store refuses starts nothing.
5. **It starts the sitting:**
   `gc session new converse-<model> --alias <task> --no-attach`, under the
   prefix `c-` when the runtime refuses the bare id as an alias. A session
   still holding that alias that no longer holds the task, as a sitting cut
   short leaves it, is closed first once it is older than the bind wait and
   unattached, and the session whose alias the task is bound to is never
   closed. A spawn the runtime refuses because a session holds the alias spawns
   nothing. A task bound to that alias is that session's, since the session's
   claim runs as its alias, even while the session list does not show the
   session: a sitting another engage started seconds before can be missing
   from a list the supervisor answers from its read cache. Engage attaches the
   operator to that session as to a live sitting, and finds it by its alias
   until the list names it. A task bound to no such alias is waited on for the
   bind of the engage that holds the alias, and the session is named as left
   over only when no bind comes within the bind wait.
6. **It binds the task to the session's alias** with
   `gc bd update <task> --if-assignee <holder> --if-status <status> --assignee
   <alias>`, where the holder and the status are the ones engage read, or the
   queue and `open` for a conversation it filed. A bind misses when another
   engage or a hand-off landed first, or when a dismiss closed the task, since
   a dismiss keeps the holder and changes the status. A task already assigned
   to the alias, as a sitting whose session closed leaves it, needs no bind, so
   no guarded write covers the spawn's window, and the task is read again: it
   must still be assigned to the alias and not closed. A bind that misses, or a
   read that finds the task taken or closed, closes the session this engage
   started. Then engage waits for the reconciler to start the session, and
   attaches the operator.

**Engage offers what holds the bead.** It reads the reasons
`gctk pr status --json` gives (`prstatus.Read` and `prstatus.Reasons`),
the one definition the PR's `held:` labels and the board's row read: each open
human gate reached from the bead through its open `blocks` edges, so a gate on a
rework or a review the anchor waits on is offered from the PR, each bead a person
owes the next move on that the same edges reach, such as a decision or another PR
waiting on a review that the PR's rework waits for, and the PR's own review
threads or blocked verdict. The conversation form lists them under the bead's
conversations. A gate or a bead is a row, and choosing it makes it the subject.
A gate chosen there keeps the bead it was listed under, which the screen names
under the subject, and the form looks it up and saves it with `--from` naming
that bead, so a gate several beads wait on is about that bead while the bead
still waits on the gate. A gate the bead waits on only through another bead,
such as a gate on its rework, is looked up as if it were typed: it is about the
bead engage takes from it. A gate that no longer holds the bead by the time the
form looks it up or saves it is refused, so the question is never filed on
another bead in its place. A gate the operator types names no such bead, and
neither does one whose subject the operator edits after choosing it, so a gate
several beads wait on is about the bead engage takes from it, as on the command
line.
The PR's own threads and
verdict are lines that no row stands for, because engaging the PR is how a
person acts on them. The form says when what holds the bead did not read, so a
bead it could not read does not look like one that nothing holds. An engage
that asks nothing, as `--no-input` and the board's route do, names each and how
to engage it, a gate with `--from` naming the bead, unless it was pointed at a
gate or a conversation. A conversation
on the bead answers no gate until it replies to one.

**On a terminal, engage opens the conversation form.** An engage whose
command line names no concern (`--reason`, `--template` or `--skill`) and not
`--no-input` hands the terminal to helm-svc's `form` command
(`services/helm/internal/form`), on its page for starting a conversation
(*The way in*, above). The page holds, in this order, the subject, a
multiline question, in which Enter adds a line, the model, shown with each
word of its name capitalized and Claude-Opus as the default, and whether to
attach once the sitting starts, which is on unless `--no-attach` is given. The
subject is a bead id, a PR number or URL, or a rig's whole name or prefix, such
as `gc-toolkit` or `tk`, matched ignoring case and the spaces around it, which
starts a new topic in that rig. Part of a name names no rig, and the form
completes none. Only text the operator types in the subject is matched to a
rig. The subject the command line names is a reference, as the flag-driven
engage reads it, and so is a bead the form puts there, such as a gate chosen
from what holds a subject, so each is looked up even when a rig carries the
same name. `--rig` fills in the subject with the rig's name, which names the
rig of exactly that name, as `open --new-subject --rig` does, until the
operator edits it. A line under the subject shows the rig it names, or a
bead's own rig, and is not a field. Tab moves through the fields in that
order, so the question is one Tab after the subject, and wraps around at
either end. ↑ and ↓ move between the fields once the cursor is on a field's
first or last row, with the question's rows counted as the screen shows them,
and stop at the last field, while ↑ from the subject reaches the tabs. The
form opens on the question when the command line names the subject or a new
topic's rig. A tab in the question stays a tab, shown as ␉, and a line break
written as LF, CR or CRLF is one line break. The field leaves out every other control
character, such as BEL or ESC, and U+FFFD, the replacement character. It leaves
out U+FDD0 as well, since inside the field that noncharacter stands for a tab.
The command line fills in the fields, and typing never waits for a read.
A `--model` that names no variant engage offers is refused before the form
opens, as the flag-driven engage refuses it.
While the operator types, the form reads `gc-helm.sh conversations` for the
subject: the bead it resolves to, the rig a conversation about it is held in,
whether a sitting can start there, its open conversations and what holds it.
It reads the city's rigs with each one's prefix, so a rig's name or prefix
typed as the subject is known as the rig and is not looked up as a bead. A
rig's name wins over a bead of the same id, so typed text settles only once
the rigs are read: until then the screen marks where it would file as still
being checked, whatever its lookup answered, and Ctrl+S files nothing. When
the rigs did not read, Ctrl+S reads them again. The screen shows where a
submit would file before it does: a conversation on the subject in its own
rig, or a new subject in the rig the subject names. A name or prefix that more
than one rig carries names none of them, and a PR number that several live
anchors record waits for the operator to pick the anchor. A result read for an
earlier subject never stands in for the current one, and no result changes a
conversation the operator chose. A conversation chosen from the list is
started as it is, and a question typed beside it is not sent into it.

**A suspended rig turns attaching off.** Gas City starts no session for an
agent in a suspended rig, so no sitting can start there. In a suspended rig,
whether the subject names it or it is a bead's own rig, the destination is
still settled, Attach reads no with the reason beside it, and no key turns it
on. Ctrl+S saves the question and leaves, starting no sitting, and the form
says the conversation waits in the operator's queue until the rig resumes
(`gc rig resume <rig>`). An open conversation chosen there is not started:
Ctrl+S reads the subject again, keeping the conversation chosen, and once a
read finds the rig resumed, the next Ctrl+S starts it. Once the subject names
a rig that is not suspended, attaching is the operator's own choice again.
`conversations <ref>` says a subject's rig is suspended as `rig_suspended`,
which refuses nothing, and engage on the command line still refuses to start a
sitting in a suspended rig.

**The variants are the converse templates engage offers.** Each is an
`agents/converse-*` template named `converse-<provider>-<model>`, and the name
after `converse-` is what `--model` takes and what the form shows capitalized:
`claude-opus` (the default), `claude-fable`, `codex-sol` and `codex-astra` read
Claude-Opus, Claude-Fable, Codex-Sol and Codex-Astra. engage withdraws
`converse-opus`, `converse-fable` and `converse-codex`: it offers none of them,
and each stays configured only for the sittings already open on it. Gas City's
reconciler wakes no session whose template is not configured, drains one that
holds no work, and closes one whose process is gone, releasing the conversation
it held, so a template goes only once no open sitting runs on it.

Ctrl+S saves the question only once the destination is settled. `open` files
it as a new conversation (`--allow-duplicate` and `--if-subject` on a subject,
`--new-subject --rig` on a topic), with the field's question as its ask and
titled by `conversation_title`, and the form says it is saved. `--if-subject`
names the subject the screen shows, and `open` refuses the save when the
reference names another bead by then, such as a subject closed onto a successor
in another rig, so a question is filed only where the screen said. The reference
goes as the operator typed it, so `open` resolves it again, and a PR whose
anchor moved while the operator typed is refused too. A gate goes as itself, so
the conversation replies to the gate the screen showed, and a chosen gate goes
with `--from` naming the bead it was listed under, so `open` takes that bead
among several waiting and files nothing once it has stopped waiting on the
gate. On a gate the question is optional, and the empty box shows the gate's
own question as what holds the subject lists it. Left empty, the save passes
`open` no `--reason`, so the conversation is titled from the gate's title and
its ask is what the gate asks. Every other subject needs the operator's
question. Then `engage
<conversation> --no-input --no-attach` starts the sitting. Once it has started,
the form leaves the terminal, and then attaches it to the sitting through
`engage <conversation> --no-input`, which waits for the session to start, as
engage does on the command line. The attach runs after the form's last screen,
so all that engage prints stays on the terminal, its reason when it attaches
nothing included, and the form exits with engage's status. With attaching off,
the form leaves the sitting to prepare, and says that
the conversation is saved and how to return to it. An attach holds a
conversation no live sitting holds, as after a start that failed or a sitting
that ended before the attach reached it, in a new sitting on the model the
start ran on, and after a start that failed, Enter attaches that way. A save
that files the conversation and then fails, as when the store refuses
its reply onto the gate, says the conversation holds the question and what
did not complete, and starts nothing. r sends the save again naming that
conversation (`--conversation`), and `open` completes it by its id rather than
file a second, wherever it stands by then, even when a sitting another terminal
started has taken it out of the queue. It adds the hold on an open PR's merge
only while the conversation still waits in the queue, so a hold that such a
sitting lifted stays lifted. A conversation closed since, or one that holds
another ask, is refused, and nothing is filed. A save whose answer was
lost leaves the form without the conversation's id. For that save, with
`--allow-duplicate`, a concern that a conversation waiting in the queue holds as
its whole ask lands on that conversation. Leaving while the save or the start
still runs waits until it lands,
because a verb the form leaves behind dies at its next line of output, and a save
cut off there can leave a new subject without its conversation. A second Ctrl+C
leaves at once, and the form then says what it does not know. A form that
something else ends, such as an interrupt, a termination or a terminal that
fails, leaves as a second Ctrl+C does while a save or a start runs, and as Esc
does otherwise, so it keeps a question it did not save. A hangup, as when the
terminal's window closes, ends the form before it can keep anything.
A save that fails
leaves the question in the form and reads the subject again, so a subject that
names another bead now is on screen before the next Ctrl+S can file there. A new
subject filed whose conversation was not becomes the subject of the next save,
so the retry files onto it. The form kills a verb that runs past two minutes,
and a save killed once its subject was filed still names the subject, because
`open` answers it the moment it is filed. A subject whose create landed but
whose reply was lost is one the form never learns, and a retry after that files
a second subject. A save refused because a read failed,
or because of a refusal that can change, such as a downed controller, reads it again
for the next Ctrl+S. A question the form did not save is kept in a file under
`GC_HELM_DRAFT_DIR` (else `$XDG_STATE_HOME/gc/engage-drafts`, else
`~/.local/state/gc/engage-drafts`) when it closes, and before the terminal goes
to a sitting picked from the return list, and the form names the file and the
command that files it again. The command reads the file whole, trailing newlines
included, because engage files through `open --allow-duplicate`, which lands on
the conversation an earlier save filed only when the ask matches exactly.

Engage warns when it starts a sitting while another live sitting tracks the
bead, or replies to a gate the bead waits on. **One sitting per bead is a
convention, not a guarantee.** The alias and the bind keep a second sitting
off one conversation, not off one bead: a concern of its own, two engages
racing on a bead with no conversation, or a gate two beads wait on can each
put two sittings on one bead. The board folds both onto the bead's row, either
may answer a gate, and the first answer wins.

**The visit's comment on its PR.** When the subject carries a PR, a comment on
it shows the visit. It is a view of the conversation, drawn from the
conversation's values word for word (`assets/scripts/pr-sitting-comment.sh`).
While the conversation is open, the comment names the visit and the bead it is
on, the conversation's id and the subject's, and the visit's topic, which is
the conversation's title. The sitting writes that title in its own words in
the title step of its prep, and again only when it moves to a different topic.
The comment goes up then, so a conversation that closes before then posts
nothing. Once the conversation closes, those lines stay and the conclusion and
the actions follow them. The conclusion is the last hand-back recorded on the
conversation, the text the operator's tab prints when the sitting ends. The
actions are the conversation's comments. The sign-off writes one for the ruling
and one for each act it takes, the sitting writes one for work it sends and one
for a close at its premise re-check, and a dismiss writes one for the
dismissal. Each write that changes what the comment
shows draws it again: the sign-off, a dismiss and the premise re-check's close
once the conversation reads closed, and a hand-back recorded after the close.
The comment is keyed by the conversation's id under the marker
`<!-- gc:sitting:<task> -->`, and `pr-post.sh` counts a post that carries it as
the city's own.

A PR comment can be a public record, and no person reads this one before it
posts. Nothing typed to open a conversation reaches it, because that text stays
on the conversation as its description, and neither does a dismiss's reason.
The comment shows what the visit writes, so the visit keeps other rigs and
their beads out of its topic, its closing hand-back and its actions, and detail
about another rig stays in the thread and in notes, which the comment does not
show. Nothing filters the comment, so a slip publishes what the visit wrote.

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
`GC_INTAKE_DEFAULT_RIG` moves the default). Converse is `scope = "rig"`, so a
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
capture that is not a member of an epic is not routed: it waits, held, for the
po's backlog refinement with the operator ([steering.md](steering.md)).

The fallback path files a conversation in the operator's queue directly,
through `gc-helm.sh open`, which is where filing a conversation lives. It runs
on `--no-react`, when `tools/gc-proactive.sh deliverable` answers that the
proactive pool is not registered, is suspended or is capped at zero slots, and
when the reaction would file nothing: the subject already has an open first
reaction or a live owner owns it, a live workflow already drives it, it is
already routed or armed, a hold holds it, or an open human gate blocks it. A
react path that could not deliver would leave a routed reaction bead nobody
picks up and no conversation at all, the one outcome this channel exists to
prevent. A roster the deliverable check cannot read answers yes, because
absence of evidence is not evidence the pool is gone.

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
subject and engages it in one gesture. It files the subject bead in the rig
`--rig` names, files its one conversation, spawns the sitting and binds it.
The rig is always the operator's choice: a topic carries no id prefix to derive
one from, and a bead filed in the wrong rig can draw public comments there. The
positional text, or `--reason` without one, is the question. The subject's
description keeps it unchanged, newlines included, with a provenance line after
it, and its title is the label `conversation_title` derives from the
question's opening, so a question longer than a bead title is filed whole.
Absent `--reason` or `--template` the question is the conversation's opener
too. On a terminal, `--new-subject` with no concern opens the conversation form
on a new topic, and `prefix+A` runs it in a new tmux window
(`assets/scripts/tmux-new-subject.sh`), because a form does not fit tmux's
one-line command prompt. `gc-helm open --new-subject --rig <rig>` files the
subject and its conversation without starting a sitting, which is how the form
saves a new topic before it starts one.

The subject is created marked `gc.reaction_owned=1` in the same create, so
the proactive scan never observes it unmarked. Three gates read the marker:
the scan's precision filter drops a marked bead, the reaction-absent guard
refuses to file one, and a reaction that reaches a marked subject anyway
closes its own reaction bead without acting
(`first-reaction-dispose.sh --stand-down`). The engage is the reaction, and
the marker stays, so no later scan reacts. If a later step refuses the live
spawn, a bad model or a suspended rig, the subject's one conversation still
waits in the queue, so the topic is never lost.

### Returning to a conversation

`gc-helm conversations` lists every open conversation in the city's stores and
where it stands. It reads every task in a live status and keeps those the
shared conversation rule (`conversation.sh`) picks out by their own rows, so a
conversation is listed whatever its sitting's state, one bound to a sitting
that ended before it claimed it included. A rig whose store does not answer, or
whose ledger is not there, is named as not listed, and the list exits 4 after
printing the rest. A conversation's readiness is queued while it waits in the
operator's queue, starting while its sitting's session has not started,
preparing until the sitting records its first hand-back after its session was
created (`gc.handback_at`, which `gc-helm handback` stamps on each framing),
ready once it has, and ended when its sitting's session has closed while the
conversation stays open. Each row says whether a terminal is attached to the
sitting. `gc-helm attach` opens the conversation form on that list, those no
terminal is attached to first, by readiness and then newest first, and reads it
again every ten seconds while it is on screen. What is picked is a
conversation, so a read that re-sorts the list keeps it picked, and one that
leaves the list leaves nothing picked until ↑/↓ picks again. A list longer than
the terminal shows the page the pick is on, and a last line counts the rows
above and below, so the row picked is always on screen, through a resize and a
read that moves it. The form's rows on a subject are paged the same way. The
form wraps its text at spaces to the terminal's width, so a destination, a
refusal or a status is shown whole and the rows page around the lines it takes,
while a row stays one line, which a narrower terminal cuts at its edge. A read
again that fails keeps the rows the last read gave, and the screen says since
when the list has not been refreshed, that it may be out of date, and why the
read failed. Enter attaches to the one picked, and a sitting held anew there
runs on engage's default model, since the list shows none.
`gc-helm attach <conversation>` is engage's attach for a script or a shortcut:
it attaches to a live sitting once it has started, and holds a conversation
whose sitting ended, or one in the queue, in a new sitting first. Starting and
returning are two pages of one form, and its tabs move between them.

## The sitting

A sitting's session is a manual session of the converse agent the operator
chose. It is manual because the controller's work ladder paces a pool session
that holds a claim, nudging one that stays quiet and then recycling it, and a
sitting is quiet whenever the operator is reading or thinking. A manual session
has no such clock: its work closing does not end it, idleness only sleeps it,
and attaching wakes it. The idle sleep its template sets never reaches a sitting
that holds its conversation or has a client attached.

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
hold. On an open PR's anchor that wait is the conversation itself, whose edge
holds the merge, and a review or rework of an open PR waits on nothing the
conversation adds, because the edge holds the anchor and not the subject. The
gates the conversation replies to stay open and owed. When something else must
wait for the answer and no gate the conversation replies to holds it, as when
a pre-open anchor's PR must not open before the operator rules, the sitting
files a human gate through the helper on the bead that must wait: that
anchor, or the one member of an epic whose work waits. A gate another
conversation filed there asks that conversation's question, and its ruling
releases the bead whether or not this one is settled. So the key names the
conversation, `conversation.<conversation id>`: a resumed hold finds the gate
it filed, and two conversations on one bead each hold with a gate of their
own, so the merge waits for both rulings. The sitting replies to its gate, so
a resumed or handed-off conversation knows the gate
it owes. Without that need it files nothing: a conversation freezes no work,
and an open PR's reviews and reworks keep moving while the operator and the
sitting talk. The gate is what holds the subject: bd reads the subject as blocked while
the gate is open, and the hold writes no lifecycle state or route, so the
subject keeps its state, its route and any deferred-dispatch arm
([state-machine.md](state-machine.md#the-machine)). A hold does not use
`gc session wait --sleep`, which sets a wait hold the controller then drains,
destroying an attached operator's pane.

**Answering a gate.** A sitting answers only the gates its conversation
replies to: the gate engage was pointed at, one its hold filed, and any other
human gate the operator rules on within the subject's universe, which the
converse prompt defines as the subject with its dependents and related items,
and for an epic the work under it and in flight across it. To answer a gate
its conversation does not reply to yet, the sitting adds the reply, so the
graph records which conversation answered which gate. Before it
resolves a gate, it names every bead the answer releases, read from the gate's
`blocks` dependents, so an answer that releases a bead beyond the subject is
given knowingly. It also settles the subject's dispatch path first, at the
sign-off and on a turn that does not sign off alike. The hold kept the
subject's arm and route, and an answer that clears the subject's last blocker
releases it to them, so a ruling that sends the subject anywhere else
withdraws both before the answer. The record and the headline go on the
subject alone: a rework child waiting on its anchor's bring-current gate, or a
member of an epic whose gate the epic's sitting answers, reads the answer in
the gate's resolve reason, through its own `blocks` edge. A gate with no tie to
the subject takes its own conversation, so its outcome never lands in the
notes of a bead that is not about it.

**The first answer wins.** bd resolves a gate already closed without changing
it and reports success either way, so every resolver reads the gate back. A
close reason other than its own means another answer reached the gate first: a
filer's withdrawal, an Accept, another sitting, or a person at the command
line. That answer stands, and the resolver reports it instead of claiming its
own.

**The sign-off** is `assets/scripts/converse-signoff.sh`, which writes the
durable trace in one order every time:

1. what a ruling does to an open PR it reaches, the subject, the PR whose
   merge the conversation holds or a PR that a gate it answers releases: its
   rework, through `converse-rework.sh`, with
   the conversation as the rework child's `source_ruling_bead`, so a ruling
   that changes what the PR's branch must contain becomes work the refinery
   lands; or its retirement, through `pr-dispose.sh`, which records the
   disposition and closes the PR;
2. the subject's headline;
3. `ruled: <the ruling>` on each open gate the conversation replies to that the
   ruling answers, each read back, with an earlier answer reported;
4. the subject's recommendation, when the ruling takes it (`--accept`): the
   recommendation's gate, which step 3 leaves, is answered by Accept's writer
   (below), which sends the formula once;
5. the conversation's close, whose reason is the headline the sitting settled
   on;
6. the comment that shows the visit on the subject's PR, drawn again from the
   conversation.

As it goes, it records the rework or the retirement, the ruling once the gates
carry it, and the recommendation taken on the conversation, each a comment in
plain words, which that comment lists as the visit's actions.

A ruling that leaves the subject waiting on work the sitting sent also gets the
subject checked once that work lands. Right after the headline, whose
`--waiting-on` edges hold the subject until the work closes, the sign-off
appends the sitting's `--close-brief` to the subject's notes and arms the
subject's validating closer (`mol-validate-close`) in the subject's own rig,
the waits skill's way of having a bead checked and closed once other work
lands. A subject held for placement then has its `hold:mayor` lifted, every
spelling of it, because the deferred-dispatch pass sends no arm while that
label holds the subject. Each of these writes lands before any gate is
answered, and one that does not land stops the sign-off. Once the work closes,
the deferred-dispatch pass slings the closer, which checks the brief against
what landed and closes the subject or puts it to the operator. No closer is
armed for a subject that something else sends on once its wait clears: its own
arm, a route or an assignee, the recommendation the ruling takes, or the
refinery's merge or its members, for an anchor or an epic. A subject in the
city's own store is refused, because no pool runs a closer there, so a person
closes it on a human gate that names the work.

It resolves no gate its conversation does not reply to: a gate the sitting
never took up stays for whoever owes it, and a gate it replies to that the
ruling leaves owed stays open with its reply in place. It reads those gates
from the conversation's own row (`gc bd list --id <task>`), whose edges keep a
reply onto a gate in another store. Every read it depends on runs before its
first write, and it stops short, with nothing posted, when the store refuses a
write, so a re-run repeats each write safely. A gate can be what holds a
merge, and resolving it releases the merge, so whatever the ruling puts in the
merge's way lands before any gate is resolved. A ruling that reaches an open
PR must say what it does to the PR (`--rework`, `--no-rework` or `--retire`),
and the rework child's `blocks` edge or the closed PR is in place before step
3. It reaches the subject when the subject is an open PR, the PR whose merge
the conversation holds, the anchor that depends on the conversation, which a
conversation on the PR's review reaches through nothing else, and each open
PR that a gate it answers releases, such as a member of an epic subject. The
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
which runs steps 1 to 3 for the gates it names, and step 4 when the ruling
takes the recommendation, and stops there, leaving the conversation open for
the sign-off.

A ruling is not an approval. The merge counts only an Approve review on GitHub
from an account other than the city's (the merge condition in
[state-machine.md](state-machine.md)), and nothing the sign-off writes is one.
So when a ruling leaves an open PR standing with no such review, the headline
ends by saying the PR still needs the operator's Approve on GitHub, and keeps
saying so after the operator approves, until the PR merges or another headline
replaces it. The sitting also passes on a line the sign-off prints with the
PR's link. A PR whose reviews cannot be read counts as needing one, and on a
host with neither `timeout` nor `gtimeout` no PR's reviews can be. A PR with an
approval and a standing request for changes needs no Approve, and its line
names whose request holds the merge.

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
replies to stays open and owed, for its filer or the next sitting. The close
frees an open PR's merge the conversation held, with nothing written for it.
With no argument it infers the current sitting from the session it runs in. The close
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
`gc runtime drain-ack`. Gas City holds that stop while a client is attached
([gascity/human-engagement.md](gascity/human-engagement.md#a-stop-the-v2-reconciler-makes-waits-while-a-client-is-attached)),
so the pane stays live under the tab, with a title that leads with `done`
(*How a pane dies when no sitting is live*, below), and the session stops
within about five minutes of the detach. Its record then
reads drained, and the core reaper's `gc session prune --state drained --before
24h` closes it a day later. A sitting that holds no open conversation, such as
one whose conversation was closed by hand, is stopped by its template's idle
sleep, `sleep_after_idle = "10m"`: Gas City sleeps a session that holds no
claimed or assigned work and has no client attached once ten minutes have
passed since its last detach or terminal output
([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)).
That record stays asleep, holding no process, until something closes it.

**Iterating on a document.** A sitting writes no files, so it changes a document
by sending work, and a worker sent on a short ruling makes every call the ruling
left open. When more than one call stands between a document's text and what the
operator wants, the sitting settles them with the operator item by item, reading
the operator's guidance for its intent and pushing back where it disagrees, and
then sends one rework that carries the decisions. The big picture between
sittings is the subject's notes: the dated rulings and the newest
`## Current state` block. That block with no open question left is the scaffold.
It names only what changes, by section or once for the whole document, and gives
each change its direction and substance, with exact words only where the wording
itself was settled. Its first lines are the rules the worker follows for what the
block leaves open, the wording included. The ruling's line names the block,
`converse-rework.sh` files the rework on the ordinary lane and `mol-polecat-work`
runs it, so the loop needs no formula, key or script of its own. With no PR open,
the work is sent as a sign-off sends any other, and its bead names the block. The
`gc-toolkit.converse-iterate-document` skill holds the steps and the block's form.

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
sitting's sign-off later reports the gate already cleared. A conversation that
holds an open PR's merge withholds no Accept either: it is no human gate, and
it holds only the merge, which no dispatch reaches.

`gc-helm.sh accept` runs under the bead's acceptance lock, a `flock` on one
file per bead under `<city>/.gc/runtime/packs/gc-toolkit`, from before its live
read of the three conditions to its last write, and refuses, writing nothing,
while another Accept holds it. On an open gate it records the acceptance's
dispatch input on the gate (`gc.acceptance`: its token, the formula and each
var), resolves the gate with `ruled: accepted <formula> accept:<token>` once
that write has exited 0, reads its own answer back to tell it from one another
reached first, reads that no other open human gate blocks the bead, slings the
formula titled
`<formula> accept:<token>`, and records the dispatch by stripping
`gc.recommended_formula` beside `gc.recommended_formula_dispatched`. An answer
another reached first stands, and Accept slings nothing. A gate filed in the
meantime, or a sling that poured no root, reopens the recommendation's gate. A
run that stopped after its resolve leaves an unfinished acceptance, which the
board keeps owed and the next Accept finishes under the same token, slinging
only when no root carries the token. That sling carries the vars the
acceptance recorded, whoever finishes it: the board's Accept passes none, and
a run given vars other than the recorded ones dispatches nothing. The lock's
warrant is in [warrants.md](warrants.md).

A sitting takes a recommendation through the same writer. When the operator
rules to take it, the sign-off's `--accept` leaves the recommendation's gate
out of its `ruled:` answers and runs `gc-helm.sh accept` once the ruling's other
writes have landed. Under the lock, that run finishes an acceptance the
board's Accept left unfinished instead of sending the formula again, and a
board Accept that runs after the sitting's finds the recommendation
dispatched. Gas City's launch lock refuses a second pour only while the first
root is live, so a sling of the sitting's own would pour the formula again
once the stopped Accept's root had finished.
A var the ruling settles for the dispatch, such as a design convoy's
`design_gated` ([design-convoy.md](design-convoy.md)), rides the sign-off's
`--var` to Accept's sling. The sign-off refuses `--accept`, writing nothing,
while a human gate the ruling does not answer still holds the subject. The
recommendation's gate is one under the key `first-reaction` that blocks the
subject: a gate under that key on an epic's member asks the member's
recommendation, which Accept on the epic never answers. So the sign-off also
refuses `--accept` unless the ruling answers one of the subject's own gates
under the key, and each gate Accept would answer there.

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
record of what the sitting concluded. A subject a sitting's ruling leaves
waiting on work comes back through the validating closer the sign-off arms
instead ([The sitting](#the-sitting)), which checks it once that work lands.

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
on sits beside it, under the subject's own parent when one applies, or under
the nearest open bead above that parent once it has closed
(`assets/scripts/converse-parent.sh`), and the sign-off's
`takeaway --waiting-on <work>` then takes. Work that genuinely
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
  closed takes the cancel without the park, and `--route` is refused there. A
  claim a live session holds is not taken: the headline lands, the holder is
  nudged to stop and give the bead back, and the release exits 4 until it has.
  `assets/scripts/stand-down.sh` runs this write for work a human gate holds, after
  it removes the arm that would re-sling the work, and goes on to answer the gate,
  or to leave one that also holds another open bead, and close the bead.

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
([gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder)).
Each also sets `sleep_after_idle = "10m"`, an idle sleep that skips a session
holding claimed or assigned work, so it never reaches a held sitting. A held
sitting therefore ends when its conversation closes, and only two things mark a
conversation done: the sitting's sign-off and the operator's `gc-helm dismiss`.
The sign-off is terminal, so converse takes it only when nothing important is
still pending. Closing the conversation ends the session too, whichever path
closes it. The sitting's own last act is `gc runtime drain-ack`, after the
sign-off or a moot or benign close, and it never claims again: a closed
conversation has no next turn in that session. `gc-helm dismiss` closes the
conversation and then stops the session that held it, also through
`drain-ack`, so the controller ends the session outside the verb's process; a
dismiss typed into the sitting's own pane acks its own session last. Either
stop waits while a client is attached, so a sitting the operator is watching
stays live under the tab until it detaches (*How a pane dies when no sitting
is live*, below). The idle sleep is the backstop for a sitting that holds no
open conversation, such as one whose conversation was closed by hand. A
sitting whose conversation is still open, because the operator walked away
before any sign-off, keeps its session running indefinitely: the operator
re-attaches or dismisses.

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
The row leads the operator's queue (services/helm/README.md, "A sitting that
failed to start").

Two endings the idle setting does not own:

- **A settled sitting ends itself, not by a runtime clock.** A sitting is a
  manual session, which Gas City keeps desired for as long as it is neither
  closed nor drained
  ([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)),
  so the `no-wake-reason` drain that collects an ended pool session in about
  a minute never reaches it. Its own `drain-ack` ends it, `gc-helm dismiss`
  stops it, and the idle sleep above stops one that outlives its conversation
  anyway. See *How a pane dies when no sitting is live*, below.
- **No max-age restart reaches a sitting.** No `converse-<model>` template
  sets `max_session_age`, and only the legacy reconciler reads it
  ([gascity/human-engagement.md](gascity/human-engagement.md#max_session_age)).

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
output, only the reading appended to its subject: the premise re-check's moot or
benign close. The sign-off exists because an unanswered framing left in a
vanishing thread reads as a crash; where no framing was ever posted there is
no question to abandon. An earlier sitting on the same conversation may have
held and been cut short, leaving its hold's headline on the subject, waiting
on the gates this close resolves. So the close reads the subject first. A
headline that still waits, on a subject no open blocker holds any more, is
replaced with the reading, settled. The conversation closes only once those
writes have exited 0.

*A restart is not an ending.* A wake that reaches a session mid-hold gets its
conversation back from `gc hook --claim` as an existing assignment. Draining
then would end a sitting the operator has not ruled on, and running the loop
from its premise re-check could close a conversation the operator is part way
through, so the converse prompt's restart rule reads the conversation's
`holding:` line and re-opens the hold rather than doing either. A wake nudge
that names `gc hook --claim` alone, rather than sending the session through the
prompt's claim block, skips that rule, so every `converse-<model>` template
holds its `nudge` empty. Emptiness is not what protects a held sitting: a
sitting runs as a manual session, never pool_managed, and neither the work
ladder nor a claim backstop governs a session that is not pool_managed
([gascity/human-engagement.md](gascity/human-engagement.md#the-controllers-backstops-govern-pool-sessions-only)).
What the empty field reaches is the launch delivery, where the prompt is
prepended to it and still arrives.

Attachment is the one reading signal the runtime has. The v2 reconciler holds
a stop it makes, an idle stop or the stop a drain-ack asks for, while a client
is attached
([gascity/human-engagement.md](gascity/human-engagement.md#a-stop-the-v2-reconciler-makes-waits-while-a-client-is-attached)),
and a detached reader is still indistinguishable from abandonment. That is why
the trace is written when the hold begins rather than bought with a longer
clock.

## A po sitting

Each rig has its own po, the operator's prioritization partner for that rig's
work: a named session of the rig, which the operator opens for one sitting at a
time, a backlog refinement over the rig's `hold:mayor` queue or a portfolio
sync over the rig's epics ([steering.md](steering.md)). A sitting ends when
the po runs `gc runtime drain-ack`, and the next sitting starts a new
conversation. The rig's row on Engage's People page opens one from whatever
state the seat is in, with no other command, and so does `gc-helm po --rig
<rig>`.

Both are Gas City's attach on the rig's po, `gc session attach
<rig>/<binding>.po`, Gas City's name for a rig's named session, where
`<binding>` is the name the city imports the pack under. Both take that name
from `gc agent list`, so they open the same seat whatever the binding is
([gascity/human-engagement.md](gascity/human-engagement.md#what-an-attach-does-to-a-session-that-is-not-running)).
A live sitting is attached to as it stands. Any other seat, one whose sitting
ended, one whose sitting slept once its idle limit passed (`sleep_after_idle`)
or one with no session yet, is started by the city's controller: the attach
asks for the start, waits for the session to run and then attaches. The start
gives the po its prompt as its first message, and because the po wakes fresh
(`wake_mode = "fresh"`), it opens a new conversation, so a sitting that slept
comes back as a new one. A po still ending its last sitting is attached as it
ends until the controller begins to stop it. While that stop runs, the attach
fails, saying the session is stopping, and `gc-helm po --rig <rig>` names the re-run, which
opens a new sitting once the stop is done. The operator says what a sitting is
for in the sitting. A sitting the attach starts itself, as it does
while the city's controller is down, or when the po's last sitting ends
between the attach's check that it is running and the attach itself, gets the
po's prompt too, which the attach sends once the session runs.

## How a pane dies when no sitting is live

The section above answers "what ends a **held** sitting". Once a sitting
ends, its session goes with it as soon as no client is attached, and with the
session its pane.

**The sitting ends its own session.** A sitting is a manual session, and Gas
City keeps a manual session desired for as long as it is neither closed nor
drained and its template is still configured, so the `no-wake-reason` drain,
which begins when a live session has no wake reason left, never begins for a
sitting
([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)).
So a sitting ends its own session: once its conversation has closed and every
write that must follow the close has run, its last act is
`gc runtime drain-ack`, so the controller stops the session. `gc-helm dismiss`
stops the session that held the conversation it closes the same way. The
template's idle sleep, `sleep_after_idle`, is the backstop for a sitting that
outlives its conversation: it stops a session that holds no claimed or
assigned work and has no client attached once ten minutes have passed since
its last detach or terminal output.

**Viewing a sitting holds its stop.** The v2 reconciler holds a stop while a
client is attached to the session, the stop a drain-ack asks for included
([gascity/human-engagement.md](gascity/human-engagement.md#a-stop-the-v2-reconciler-makes-waits-while-a-client-is-attached)).
So after a sign-off or a dismiss the pane stays live under the operator's tab,
and the tab's title leads with `done`. That title is the `set-titles-string`
each `converse-<model>` template's `session_live` sets,
`#{?#{GC_DRAIN_ACK},done · ,}#T`, which tmux sends an attached client: the
pane's own title, led by `done · ` while the session's tmux environment holds
`GC_DRAIN_ACK`. Gas City sets that flag at every `gc runtime drain-ack` of the
session, the sitting's own and an operator's alike
([gascity/human-engagement.md](gascity/human-engagement.md#a-drain-ack-sets-gc_drain_ack-in-the-sessions-tmux-environment)),
so nothing in the pack writes the title at the ending, and a tab reads done
once its sitting has drained, whichever way the sitting ended: its
conversation closed by the sign-off, a moot or benign close or a dismiss, or
handed back to the queue by a sitting low on context. tmux reads the flag when
it next draws the title. It does so at once when the pane prints, as the
agent's pane does after the sitting's own drain-ack, and otherwise at the
client's next status refresh, every 15 seconds on the city's tmux server,
which keeps tmux's default `status-interval`. So a dismiss from outside the
sitting shows on the tab within 15 seconds
([specs/tk-7w7qdls/idle-sleep-probe.md](../specs/tk-7w7qdls/idle-sleep-probe.md#the-done-mark-on-gas-citys-drain-flag)).
The mark renames nothing. It changes only the title tmux sends an attached
client, so the pane's own title, the agent's own session name and the session
record that `gc session list` and the board show keep the title
`gctk session title` gave them. A restart starts a fresh tmux session, which
holds no flag, so a restarted sitting reads live until it drains again. A
`/rename`, which is how `gctk session title` names the agent, cannot make the
mark. Gas City types one into a running session only at its next boundary, and
in the probe one that the sitting's own agent queued with its drain-ack had
not landed two minutes later
([specs/tk-7w7qdls/idle-sleep-probe.md](../specs/tk-7w7qdls/idle-sleep-probe.md#why-the-done-mark-is-not-a-typed-rename)).
One that lands while an attached operator has typed in the box goes onto that
text, and both go to the model as one message. At a dismiss, a submit to a
sitting that is not running resumes it.
The session stops within about five minutes of the
detach, because the held stop retries with a backoff from ten seconds, doubling,
to five minutes. The city's tmux server carries several clients at once: the
operator's main connection, and a terminal tab on each sitting the operator
opened with `gc-helm engage`. The server's global `detach-on-destroy` is off,
which moves every client of a destroyed session to the most recently active
other session. Each `converse-<model>` template sets the option on for its own
session (`session_live` in its `agent.toml`), so a plain client on a sitting
exits when the sitting's session is destroyed under it, and tmux shows
`[exited]`; a detach exits it with `[detached]`. A client attached with
`-f no-detach-on-destroy`, as the operator's main connection is, and every
client on any other session still move on. `gc-helm engage` runs its attach
as a child, so when the tab's client exits it reads the conversation. A
closed conversation prints how it closed and the last hand-back the sitting
recorded on it (`gc-helm handback`, which the sitting runs before each
framing and its sign-off). A conversation back in the operator's queue, as a
sitting cut short leaves it, prints the same hand-back and the command that
takes the conversation up again. A conversation its sitting still holds prints
the command that re-attaches. Claude draws in tmux's alternate screen with no
history, so nothing of the pane survives to recover, and the record on the
conversation is what the tab prints.

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
  `drain-ack`, an operator's from `gc-helm dismiss`, or its idle sleep.

**What the design holds to.** A conversation is done when the sitting closes
it, at its sign-off or at a moot or benign close before any framing, or when
the operator dismisses it. Neither a stop nor the idle sleep closes one. The
agent runs while its sitting holds an open conversation or a client is
attached, and stops otherwise: the drain-ack's stop once the tab detaches, and
the idle sleep for a sitting that holds nothing. A tab reads done once its
sitting has drained, from Gas City's own drain flag. Attaching to a stopped
sitting resumes its thread. Nothing copies the pane, and no pane, live or
dead, stays on screen after its session ends, so what a tab prints is the
record on the conversation.

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
- **One board, and its verbs in gc-helm.sh.** The web page that
  `services/helm/` serves is the board's one view for people, and it reads
  one document per rig (*The rig board* in
  [services/helm/README.md](../services/helm/README.md)). The page shows two
  views of the rig's work. Needs you is one entry per need, such as a
  question, a pull request waiting on the operator's review or a ruling, with
  the beads the need holds beneath it. It leads with how many needs count, and
  how many of each kind, and folds apart the needs about parked work or work
  held for the Product Owner. The Work queue is the work in the order it is
  expected to land. The Epics tab shows both for each epic and each
  Delivery, and the Needs you and Work queue tabs show them across the rig,
  each object drawn and ordered one way wherever it appears.
  `helm-svc board --json` prints the board model's rows for agents, and the
  sidecar's `/helm` answer serves the same model. Both run the one
  `internal/source` gather and the one `internal/board` derivation, so a
  change to the gather, the ranking or the anchor kinds reaches the JSON and
  the `/helm` answer together, and not the page. A new tile field also owes
  the model's TypeScript mirror, `web/src/contract.ts`, which
  `services/helm/web/contract_parity_test.go` holds equal to the Go contract.
  `gc-helm.sh` keeps the write verbs (`open`, `engage`, `react`, `takeaway`,
  `dismiss`, `accept`, `park`, `priority`) that have no Go equivalent, and
  helm-svc's POST routes run `open`, `engage`, `accept` and `dismiss`.

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
converse prompt or skills, the sign-off, the converse templates, or the board.
The Gas City facts it links are re-verified by the refresh procedure in
[gascity/human-engagement.md](gascity/human-engagement.md#refresh-procedure);
when one of them moves, re-derive the seam here that rests on it.
