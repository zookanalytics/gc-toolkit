---
name: Human engagement — gc-toolkit's subject and visit model
description: gc-toolkit's own model for engaging a person — the subject and visit nouns, how a conversation starts, how a sitting holds and ends, what a person owes as a demand bead and an edge, the helm boards, and the ground the pack builds itself. A pack convention; the Gas City primitives it rides are gascity/human-engagement.md.
---

# Human engagement

This page is gc-toolkit's model for engaging a person, not Gas City
behavior. The Gas City primitives it rides — continuation groups, human
gates and the core orders that surface them, extmsg, pending interactions,
and how a session and its pane end — are stated, each with its date, in
[gascity/human-engagement.md](gascity/human-engagement.md). Where a passage
below relies on one of them, it links there.

**Vocabulary.** The pack's model has two
technical nouns. A **subject** is the durable thing a dialogue is about —
the bead; its id is the continuation-group identity; its notes and visit
history are the dialogue's record, spanning its whole life (an epic may
see hundreds of visits). A **visit** is a filed request for one bounded
sitting of that dialogue: a bead the converse role claims, linked to its
subject by a `tracks` edge (never `parent-child`, which would transmit the
subject's blocked state to the visit), whose
outcome is recorded to the subject and which closes when it resolves —
out loud, with a sign-off, if it was ever *held*; silently against its
subject if its premise died or it turned out to need no human, in which
case it never becomes a sitting at all. At most one sitting is live per
subject (the continuation-group vacuum serializes pending visits into
it). "Conversation" is deliberately **not** a technical term in this
pack — it reverts to plain speech, which also leaves upstream's extmsg
"conversation" (an external channel thread) unambiguous.

gc-toolkit's conversation model is a bet on Gas City's own momentum: the
runtime is steadily growing the primitives a human conversation needs, and
the pack composes those primitives rather than inventing beside them
([architecture.md](architecture.md), "How agents exist and converse"). The
bet pays only if the pack tracks where upstream is going, which is why the
primitives, their verified status and their direction have a page of their
own. This page is the model the pack builds on them.

## Scope

**Mandate.** gc-toolkit's model for engaging a person: the subject and visit
nouns, the producers that file a visit, how a sitting holds and ends, what a
person owes as a demand bead and an edge, the helm boards, and the ground the
pack builds itself.

**Boundaries.** The Gas City primitives the model rides are
[gascity/human-engagement.md](gascity/human-engagement.md), and the routing
mechanics are [gascity/routing-model.md](gascity/routing-model.md). How the
pack's lifecycles compose, and how completion propagates back to a waiting
conversation, is [lifecycle-composition.md](lifecycle-composition.md). The
converse prompt and its skills are the sitting's procedure as an agent runs
it; this page is the model they implement.

## The principle

When Gas City ships a primitive that covers something the pack built
bespoke, the pack re-derives its machinery on the primitive and retires
the bespoke part. The conversation model itself is the standing example:
`gc.continuation_group` is a live core primitive that carries the whole
subject-visit binding for free, so the visit/converse spine
(`specs/tk-h9pq5/`) rides it rather than a bespoke per-bead binding.
Expect the same trade wherever upstream covers bespoke ground; that is
what riding an ecosystem means.

## How the model rides the platform

Each primitive below is stated, with its evidence and date, in
[gascity/human-engagement.md](gascity/human-engagement.md). What follows is
the seam the pack builds at each.

- **Continuation groups carry the identity of a conversation.** The
  subject bead's id **is** the group, stamped on every visit beside its
  `tracks` edge. Each visit gets a sitting of its own, which reconstitutes
  the conversation from the subject's record and ends when its visit
  closes. No reverse links, no bespoke binding.

- **A visit is routed to the board and holds no session.** A visit parks
  on the helm board (`gc.routed_to=human`) and holds no session;
  `gc-helm engage` spawns the conversation session when an operator draws
  it off the board. The read side is exact string match, so a direct stamp
  is rig-qualified, and under a `default_sling_formula` a bare sling is a
  formula attach that leaves no claim route — stamp, don't sling, or sling
  with `--no-formula` ([gascity/routing-model.md](gascity/routing-model.md)).

- **A conversation role is the upstream worker contract with its close
  replaced by a hold.** Upstream's `gc-role-worker` contract words the
  session boundary as continue only within the same group or root,
  otherwise drain
  ([gascity/human-engagement.md](gascity/human-engagement.md#the-gc-roles-worker-contract)).
  A sitting takes the narrowest reading of it: it works the one visit its
  claim hands it and drains as soon as that visit closes, so it never
  claims again and never reaches a turn on another subject. A visit is
  routed to the board, never to a converse pool, so a sitting's claim
  returns the visit `gc-helm engage` bound to it. A conversation role is
  `gc-role-worker`'s contract with the execute/close clause replaced by
  hold-for-operator; the delta is expressed against that fragment, not a
  bespoke prompt. The roles pack's planning roles (`requirements-planner`,
  `task-decomposer`) are a standing adoption question wherever the pack
  plans or decomposes (see the tripwire under Watch items below).

- **The pack supplies the attention channel core leaves out.** A filed
  visit parks on the helm board under `gc.routed_to=human` — the board's
  exact gather predicate — and holds no session; the operator draws it off
  the board and `gc-helm engage` spawns a `converse-<model>` sitting on
  demand. So `routed_to=human` is the pack's deliberate board lane: a human
  question's canonical form is a visit, the dialogue-carrying refinement of
  the human gate, never a competitor to it, and an open human gate is a
  legitimate named wait.

- **A human gate reaches the operator as a visit.** Gas City's durable tier
  has the wait, the human gate, and a mail-and-renudge reach, but gives a
  gate no surface identity of its own. The pack gives it one by filing a
  visit for it: `orders/gate-visit-sweep.toml` files one converse visit for
  every open human gate, the visit carries the framing, the conversation and
  the owner, and the board ranks it. The core notify-on-human-gate-creation
  and renudge-stale-human-gates orders still fire on every gate, and their
  mail goes to the `human` mailbox, which the operator does not read, so it
  is a durable record rather than the reach (see [How a sitting
  ends](#how-a-sitting-ends-a-demand-bead-and-an-edge)). The sweep is
  therefore a converter from the platform's gate to the pack's visit, and
  the pack carries both objects for one question.

- **Questions gate work with core edges.** A decision-needed visit can
  block its dependents with core `blocks` edges — "a human approval is just
  a check nothing non-human can yet satisfy" composes directly, no bespoke
  gate machinery.

- **External channels meet the model at the subject bead.** Upstream's
  `extmsg` is a different plane from gc-toolkit's beads-as-turns — extmsg
  is channel-shaped and session-bound; ours is operator-internal and
  record-durable — and the two are complementary, not competing. The
  boundary, on the record: **when an external channel arrives, the subject
  bead is the natural binding anchor — the two models meet at the subject
  bead.** A Slack thread about a piece of work should bind where that
  work's conversation already lives, not beside it.

- **There is no flag-for-attention.** `gc.attention` has no upstream
  meaning, and the pack does not use it either. "An agent believes a human
  should look at this" has exactly one form — file a visit on the subject —
  so the board derives what is pressing from real state (open visits, human
  gates, stranded work) rather than from self-assertions with no lifecycle.

## How a conversation starts: operator-origin intake (2026-08-14)

Every other visit producer in the pack is **agent-origin** and attaches to a
bead that already exists — a first reaction files one when its reaction
concludes the next move is the operator's,
`liveness-sweep.sh` files one on a stall, `gc-helm.sh open` files one
on a row the operator picked off the board. None of them answers "I need an
agent on topic X," where X has no bead yet. That affordance existed under the
retired `-thread` model (a keystroke, any moment) and was not carried across
when threads were dropped for converse. Converse supplies the persistence
threads lacked; `assets/scripts/gc-visit-open.sh` supplies the intake:

```sh
gc-visit-open "why does the refinery hold siblings for a full pass?"
gc-visit-open tk-abc12                     # an existing bead is its own subject
gc-visit-open "a gascity topic" --rig gascity
gc-visit-open "just talk to me about X" --no-react
```

It creates the subject bead from the topic string — the string is the durable
**body**, which is what the converse session reads at claim time, and the title
is a one-line label derived from it — and then opens the conversation one of
two ways.

**The topic is a paragraph, and the title is not the topic.** The key exists so
the operator can type as much as they need to (the popup is sized multi-line to
invite it), and `bd create` refuses a title over 500 bytes — so passing the
topic through as the title made the key fail on exactly the input it was built
for: a 579-character paragraph filed nothing at all, and said only that the
create "returned no id" (tk-wp50s). The title is now collapsed to one line and
cut back to a word boundary with an ellipsis if it is long; the body always
carries what was typed, verbatim.

**The bare CLI's default rig is fixed: `gc-toolkit`** (`--rig` overrides,
`GC_VISIT_DEFAULT_RIG` moves the default). Converse is `scope = "rig"`: a
sitting spawns from the `converse-<model>` template of the subject's own rig,
so a topic that is not rig-specific still has to land somewhere. The CLI
default is deliberately *not* inferred from cwd: the command is fired from
wherever the operator happens to be sitting, and a destination that varies
silently with the shell's directory is the worst failure mode an intake path
can have.

**The `prefix+a` keybinding picks the rig rather than defaulting it.** After the
message popup, `tmux-visit-prompt.sh` shows a chooser of every rig except the
hq/city-workspace store — that store runs no reaction pool, so a topic filed
there would park on the board with nobody to engage it, and it is dropped from
the picker rather than offered. A suspended rig is still tagged, not withheld,
since `gc rig suspend` keeps the beads store accessible and a report filed there
is recorded and triaged on resume. A rig with no agents running is idle, not
paused, and is offered untagged. The picker is defaulted to
the rig of the pane the key was pressed in (its `GC_RIG`, else the
`<rig>__<agent>` session-name prefix; absent on a pane that names no rig, where
the operator just picks). Enter confirms that default or the operator picks
another, and the choice rides through as `--rig`. This is board context, not
cwd: the pane belongs to one rig explicitly, and the operator sees and confirms
the target in the chooser rather than having it vary under them. A broken or
empty `gc rig list` skips the chooser and leaves the intake on the CLI default.

**A target with no reaction agent is refused, not filed.** `gc-visit-open.sh`
reads the roster before it files: a rig with neither a proactive pool nor a
registered converse cannot engage an operator topic, so the intake refuses such
a target and files nothing rather than stranding the topic on the board. This
backstops the chooser exclusion and also catches a `--rig` target, a
non-interactive caller, or a bead id whose own rig is pool-less. Registration is
the bar, not liveness: a suspended rig keeps its registered agents and still
files (triaged on resume). An unreadable roster refuses nothing, so a degraded
data plane never blocks an intake.

**Two paths, and the choice is not a preference.** The preferred path files a
first reaction at the new subject. The reaction triages the subject and takes
one of its five dispositions. On the two that put the subject to the operator, a
ruling or a recommend, it files a human gate on the subject, and
`gate-visit-sweep` files the visit that resolves it on its next pass (see "How a
sitting ends" below). A
ruling is Discuss-only: the reaction judges the capture a genuine fork, an
irreversible or destructive action, or a policy call, and the operator arrives at
a framed conversation with a first-reaction card already written. A recommend
adds an action the operator can Accept: the reaction names the move and the
execution mol, and the visit offers Accept beside Discuss. When the reaction
judges the action clear and reversible, it routes the capture, holds it, or hands
it to a validating closer, and puts nothing to the operator. A capture that is
not a member of an epic is not routed: it waits for the operator's placement
sitting ([steering.md](steering.md)). The script
files nothing on the reaction path; a second visit would split one conversation
into two sittings of the same subject.

`gc.origin=operator`, stamped here, is a fact the reaction weighs, not a gate.
An operator capture is triaged on its merits like a bead that reached the
reaction any other way — the origin does not force the visit exit. What the
preferred path buys is that a capture the reaction does send back to the
operator arrives framed, carrying the card the reaction wrote, rather than as a
bare topic.

The fallback path (`--no-react`, or automatically) files the visit
immediately, through `gc-helm.sh open --reason/--body`. **Visit filing lives
in exactly one place** — that verb's marked `gate-visit` block — and the intake
script calls it rather than copying it, so the metadata shape, the
subject-exists gate, the one-open-visit-per-subject gate and the board cache
bust are inherited. `assets/scripts/gate-visit.test.sh` now sweeps
`assets/scripts/*.sh` as well as `formulas/*.toml`, so that copy is guarded on
the same terms as the formula ones.

**Why the fallback stays.** The react path is fire-and-forget:
`tools/gc-proactive.sh sling` files a reaction bead for the subject —
`task_kind=reaction`, routed to the proactive pool, naming the subject in
`gc.reaction_subject` and by a `tracks` edge — and returns 0. It pours
nothing on the subject and leaves the subject's own route alone, and a visit
appears only once a proactive session has claimed that reaction bead and put
the subject to the operator. Proactive is always-on
(`max_active_sessions = 2` bounds how many reactions run at once, and routed
reaction beads queue until a slot frees; what one `scan --sling` sweep hands
out is bounded separately by `GC_PROACTIVE_SLING_CAP`), so a queued reaction
is picked up rather than dropped — but the path is still chosen by asking
`tools/gc-proactive.sh deliverable` first (exit 0/1 plus the reason, printed
either way), and the fallback files the visit directly whenever the answer is
no. That verb answers no on a positive
finding in this city's agent roster: the pool is not registered, it is
suspended, or it is capped at zero slots. A roster it cannot read answers yes,
because absence of evidence is not evidence the pool is gone. The seam is
fail-safe by design: a react path that could not tell would leave a routed
reaction bead nobody picks up and *no visit at all* — a topic that looks filed
and is silently forgotten, the one outcome this channel exists to prevent.

Note what is *not* here: there is no mail-to-visit bridge, and no seam for one.
A mailbox whose endpoint spins up a visit per message was considered and
rejected outright (operator ruling, 2026-08-14) — a mail is already a bead and
a visit is already a bead, so the bridge converts bead to bead for an extra hop
and tick of latency, and it puts a background process on the critical path of
"the operator wants to talk about X." If external-origin intake is ever wanted,
gascity has its own external-messaging process and it belongs there.

The key binding that fires this from anywhere is tracked separately (tk-bn1oi).

**The intake also stamps `gc.origin=operator` on the subject** (both paths: a
topic it creates, and an existing bead pointed at — never over an origin
already recorded). The prose line in the body says the same thing to a human
and is not a predicate: it has already drifted across two script generations
plus one an agent typed by hand, and a `--desc-contains` sweep for it matches
beads that merely *quote* it — three of thirteen live hits, including the bead
that specified this change. The key, not the prose line, is what the reaction
reads when it weighs a subject's origin.
Subjects filed before it existed are carried across by
`assets/scripts/backfill-operator-origin.sh`, which owns the anchored
line-match, once, where a wrong match is visible and re-runnable.

## Start talking now: create-and-engage a fresh subject

The intake above files a topic and lets the reaction triage it: the operator
gets a board row, not a conversation. When the operator wants to talk *now*
about something that has no bead yet, `gc-helm engage --new-subject` creates the
subject and engages it in one gesture. It files the subject bead in a chosen
rig, files its one visit, spawns the `converse-<model>` sitting, and binds it —
the same spawn-on-engage path a parked visit takes, with the subject created up
front. The positional text is the subject's title and, absent
`--reason`/`--template`, its opener; `--rig` names the rig the subject is created
in (an interactive prompt over the converse-capable rigs otherwise, since a
brand-new subject has no id prefix to derive a rig from), and `--no-input`
requires it. `prefix+A` is the keystroke — the sibling of `prefix+a`, which files
a topic for triage — and it opens the real interactive prompt in a new tmux
window, because the choice of rig, subject, and model does not fit tmux's
one-line command-prompt.

The created subject is operator-origin, so the force-to-visit invariant still
holds — but engage files that one visit itself, so the async worker must not file
a second. The subject is created marked `gc.reaction_owned=1`, in the same
`gc bd create` write so the proactive scan never observes it unmarked. Three
gates read the marker: `scan_precision_filter` drops a marked bead (the primary,
race-free gate, so a sweep never files a first reaction for it),
`reaction_absent_guard` refuses to file one as a no-op, and a reaction that
reaches a marked subject anyway closes its own reaction bead without acting
(`first-reaction-dispose.sh --stand-down`, which
`agents/proactive/prompt.template.md` runs before it reacts). The engage counts
as the reaction, and the marker stays, so no later scan reacts. The invariant is
preserved, not relaxed: the subject gets exactly one operator-filed visit. If a
later gate refuses the live spawn — a bad model, a suspended rig — the subject's
one visit is still filed and parked on the board, so the topic is never lost; the
operator engages it once the blocker is cleared.

## How a parked conversation comes back (2026-08-22)

A sitting that reaches a conclusion **parks** its subject with a
`gc.takeaway` — one board-visible headline of what was settled or what is
being waited for. That stamp does three unrelated jobs, and two of them
conspired:

1. it parks the board row (`gather_meta_anchors` emits `kind:"parked"`,
   floored at `LOW`, because a conversation that reached a takeaway wants
   nothing and only has to stay findable); and
2. it **muted the stall detector** — the liveness sweep read a
   takeaway on a root or its anchor as a wait a human named and owns.

So the one automation in the city that files visits was silenced by the exact
stamp that recorded the wait. A subject that had dispatched work could not be
brought back *by* the system — only by the operator noticing a row. Measured:
`tk-z9nln` parked with *"next sitting when findings land"*; the findings landed
at 17:54Z; the operator found it by eye at 22:13Z, **4h19m** later, and the
audit's headline sat in a merged file, untold.

**The un-mute.** A takeaway exempts nothing anywhere in the liveness family —
`liveness-sweep.sh`, its precheck, and `liveness-recheck.sh`. The wait it names
does, for as long as that wait is live, and no shared predicate expresses that
because every shape the wait takes is already a rule those scripts apply. A
`blocks` blocker, which is what both `takeaway --waiting-on` and `demand` write,
keeps the bead out of `bd ready` — the set the sweep classifies. A child reaches
the parent-child arm and a `tracks` target reaches its own. The one read added
for this is an index of open demand beads, which covers the demand whose
`blocks` edge did not land: `gc-helm.sh` warns on stderr when that happens and
nothing repairs it, so the bead reads ready while a person owes an answer.
`triage.hold` still mutes on presence alone, because it names its wait in prose
with no edge to discharge.

A parked subject whose routed work has all landed therefore returns as an
ordinary unnamed wait in the sweep's batch triage visit, and the takeaway is
never cleared: that stamp is the record of what the sitting concluded, and the
visit is additive. What does not exist yet is the **push** — a visit filed
straight back onto the board for a `gc.origin=operator` subject, carrying
the landed id set as its own dedup key. The batch visit is a queue a sitting
works through; the push would be the subject's own conversation resuming.

**"Routed work" is wider than the board's `disposition_due`, and it has to
be.** The board derives disposition-due from `waiting_on` alone — the `blocks`
edges `gc-helm takeaway --waiting-on` writes. But the canonical converse shape
files routed work as a **child** of the subject, and a parent cannot be blocked
by its own descendant:

```
$ gc bd dep add tk-z9nln tk-wvrga -t blocks
Error: tk-z9nln cannot be blocked by its descendant tk-wvrga:
blocked status cascades to descendants, so tk-wvrga would inherit
the block and never close
```

The guard is correct. The consequence is that the default shape produces zero
`waiting_on` edges, so a readiness test keyed on them can never fire for it —
including for the very subject the incident was measured on. The sweep
therefore reads the **union** of the subject's `blocks` edges and its children
(`bd list --parent`, the only way to ask, since a parent-child edge is stored
on the child). Readiness is: at least one recorded wait exists, and every one
of them is closed.

The two surfaces are knowingly out of step until the board can see children at
all — a parked row currently hardcodes `children:[]` (tk-a9k0l). The board
stays quiet and correct; the sweep is what pushes.

**What is still not covered.** Work routed with *neither* recording — a sibling
bead named only in the takeaway prose — is invisible to both. So is an
agent-origin park, by the ruling's own scope. Both wait for an eye.

That gap is what the next section closes, by making the sibling the
canonical shape and the edge mandatory rather than optional.

## How a sitting ends: a demand bead and an edge

A bead is either ready, and therefore moving, or blocked on a named bead
by an edge. There is no third state. A sitting that reaches an open
question no longer parks its subject on a sentence and waits for someone
to come back and read it; it files what the person owes as its own bead
and blocks the waiting work on that bead.

What a person owes is a native human gate — `issue_type=gate`,
`await_type=human` — that blocks the waiting work. A ruling files
unassigned; a task only a named person can perform is assigned to them, and
the assignment is what tells the two apart. Either way it carries
`gc.routed_to=human`, so it lands in the operator's partition of the board,
and the authored 140-character headline is its TITLE — the same primitive
`gc.takeaway` already enforced, now attached to the thing that is actually
owed. Stamping the gate identity is what feeds core's
notify-on-human-gate-creation and renudge-stale-human-gates orders and lists
it under `gc bd gate list`; a bare `blocks` edge fires none of them. The work
it gates carries a `blocks` edge to it and is therefore not `bd ready`.
Resolving the gate makes that work ready and the pool claims it, so
discharging a decision advances the pipeline rather than the operator's
to-do list.

A gate is hidden from `bd list` by default, so every reader of the demand
convention — the hold check in `signoff.sh` and `pr-facts.sh`, the liveness
sweeps, converse's own discharge lookup — passes `--include-gates`. The
`gc.demand_for` key they match on is unchanged; only the visibility flag is
new.

The writer is `assets/scripts/gc-helm.sh demand`. It resolves the gated
bead first, files the demand, wires the edge, and then reads the edge back
off the gated bead — exiting non-zero when it did not land, because a
demand with no edge leaves the work reading ready while a person still
owes an answer, which is precisely the state the verb exists to remove.
One open demand per gated bead and topic: a resumed sitting that re-states
the same question under the same topic (`--topic`, the visit's
escalation_key) refreshes its own demand rather than giving one wait two
blockers. The topic scopes the lookup so two sittings on one shared
standing-scope bucket each keep their own demand — without it the second
would refresh the first's gate in place and overwrite the operator question
it holds. An absent topic matches on the gated bead alone, the behaviour
every caller that files no topic keeps.

`converse-hold.sh` passes the visit's escalation_key as the topic on every
demand a sitting files. The discharge in `converse-signoff.sh` resolves only
demands the sitting itself filed, never the first unassigned demand on the
item. The conversation demand is the one `gc.hold_demand` names, the id
`converse-hold.sh` stamps on the visit. Any other demand, such as a
`--hold-merge` demand on the anchor or a hold that predates the stamp, is found
by the same topic-scoped lookup, keyed on the visit's escalation_key. So a
sign-off under a standing scope resolves or re-states its own operator question
and leaves a sibling topic's untouched.

The gate is the STATE; the visit is its RESOLUTION. Because the operator does
not read the "human" mailbox, the notify order is a durable record, not the
reach — the visit is the attention channel. `orders/gate-visit-sweep.toml`
files one converse visit on the gated bead of every open human gate, so the
question arrives as a conversation with framing and an owner. One visit per
gate: the sweep records the visit it filed (or the sitting already standing
for the gated bead) on the gate as `gc.gate_visit=<visit-id>`, and never
re-offers a stamped gate — a sitting that ends with the gate still open (a
benign close, a cut-short hold, an operator dismiss) must not re-file a
visit every cooldown; the return trip for a cut-short hold rides the
liveness sweep, as before. Stamping `gc.gate_visit=skip` on a gate before the
sweep reaches it suppresses its visit, which is the operator's selection
point when the default is too much; `gc bd update <gate> --unset-metadata
gc.gate_visit` re-offers one. A gate assigned to a person gets
no visit — the work is theirs to perform and close, and converse's discharge
skips assigned demands on purpose — and neither does a gate whose gated bead
is no longer open, which the sweep names on stderr until it is resolved by
hand.

The proactive first reaction is the gate's producer for a bead it cannot carry
forward on its own. Its ruling and recommend exits (`first-reaction-dispose.sh`)
file the gate through `gc-helm.sh demand` under the topic `first-reaction`, with
the reaction's takeaway as the question, and hold the subject on it. The topic
keeps the gate the reaction's own: a re-run refreshes it, and a demand a sitting
already holds on the subject keeps its question. The sweep's next pass files the
visit, so a gated subject can wait up to one pass, a 5-minute cooldown, with no
visit. A sitting resolves the gate when the operator rules, through converse's
discharge. On a recommend, Accept is the operator's answer: `gc-helm.sh accept`
resolves every open, unassigned demand on the subject, the reaction's gate among
them, before it dispatches the recommended mol. The order matters because the
dispatch starts the run at once, and `mol-polecat-work`'s load-context cancels a
run whose work bead still has an open blocker. A demand that will not resolve
stops Accept before the dispatch. When the dispatch does not land, because a
demand would not resolve or the sling failed, Accept reopens the demands it
resolved, so the question stands. When a reopen does not land or cannot be read
back, Accept exits 4 and names the demands to check and reopen by hand. Accept
dismisses the subject's visits only after the dispatch lands. Dismissing the
visit without an answer leaves the gate open and the question owed, with no
second visit offered unless `gc.gate_visit` is unset.

### Two visit channels: keyless conversation, keyed escalation

A visit reaches a person two ways. Both channels file through the one
`gate-visit` snippet, whose copies `assets/scripts/gate-visit.test.sh` holds to
the same invariants. Each channel keeps one open visit per situation, and they
differ in what names the situation.

A **conversation visit** is keyless, and its subject names its situation.
`gc-helm.sh open` files the operator's board pick, and `gate-visit-sweep` and
`gc-visit-open.sh` file through it. It folds a second ask into whatever visit is
already open on the subject. The one deliberate exception is `gc-helm.sh
engage` when the operator asks for a new visit, which passes `--allow-duplicate`
to file a fresh visit for a distinct concern. The formula copies of the snippet,
in `mol-visit`, `mol-validate-close` and `mol-feedback-distiller`, first look
for a conversation visit already open on the subject and reuse it. That check
matters when a step runs twice, either because a later command in it failed and
the block is re-run or because a second session takes a re-offered step.
Without it the second run files a second visit, which goes on asking after the
first one is answered. Both paths read coverage through
`assets/scripts/visit-identity.sh`. It reads the visit's `tracks` edge and falls
back to the `gc.continuation_group` stamp.

An **escalation visit** is keyed. `assets/scripts/escalate.sh` stamps
`escalation_key` and keeps one open visit per subject and key. It also carries a
verdict window, which declines to re-raise a situation a person already ruled
moot or benign. That is what a detector that re-fires every cycle needs. A
formula copy never reuses an escalation visit. `escalate.sh --retract` closes
one as moot when its own situation clears, and the formula's question would
close with it, unasked.

### A conversation does not freeze its subject; a merge hold is an opt-in

What the conversation demand gates is the choice that keeps a sitting from
freezing the work it is about. A conversation about a PR anchor files its demand
against the VISIT, not the anchor: the conversation cannot conclude until the
operator answers, and the anchor keeps moving, so a conversation opened to help
a stuck PR land does not itself hold it from landing. This is the default, and it
needs no detection — the sitting never flags a hold it did not mean. The visit is
itself the sitting that resolves that demand, so `converse-hold.sh` records it on
the gate as `gc.gate_visit=<visit>` at filing time and `gate-visit-sweep.toml`
files no second visit for it.

When the sitting decides the merge must wait on the operator — the PR should not
land until this is settled — it takes one explicit step: `--hold-merge` on
`converse-hold.sh`, which files a second demand against the ANCHOR. That is the
same `blocks` edge the merge sweep already honors — `merge.sh` holds on any open
dep-edge blocker of the anchor, and `pr-facts.sh` and `pre-open-rebase.sh` read
the anchor as held by matching `gc.demand_for=<anchor>` — so it pauses the PR
with no change to any of them. The conversation demand on the visit never matches
`gc.demand_for=<anchor>`, which is why the default no longer freezes the merge. A
shepherd sitting simply omits the flag, and the PR stays on the merge track. The
sign-off (`converse-signoff.sh`) discharges whichever demands the sitting filed:
the visit demand always, the anchor demand only when the explicit hold was taken.

A cut-short sign-off (`--ruled no`) is the one other time a sitting's question
holds the merge. The conversation wait cannot ride the closing visit — a demand
left on a closed visit is a gate `gate-visit-sweep` names on stderr forever and
no return trip re-offers — so `converse-signoff.sh` moves it onto the ANCHOR:
the liveness sweep re-offers the next sitting from `gc.demand_for=<anchor>`, and
the merge holds until the abandoned question is answered or the demand is
resolved. The moved wait carries the sitting's topic, so it refreshes this
sitting's own demand on the anchor and never a sibling sitting's. A ruled
sign-off that answers `--rework` holds the merge too, through the rework child's
`blocks` edge, until the rework lands. It also returns every review lane to
`unreviewed`, so the branch is re-reviewed at the head the rework lands rather
than merged on reviews of the head the ruling outdated. A ruled sign-off also
records its ruling on the visit as `gc.ruling`, and a review finding deferred to
the visit (`finding.sh` needs-you) is released only by a visit that closed
carrying one. A fold hands the finding on to the visit it folds into, and a
visit closed moot, benign, dismissed or cut short releases nothing.

A pre-PR (unanchored) item is the one case the conversation demand still gates
directly, because its `held` lifecycle state is a hold marker that
`doctor/check-wait-is-an-edge` requires a live edge for. There is no merge to
freeze there, so the hold stays on the item as before.

### The shape constraint, and why it is the hard part

beads REFUSES a `blocks` edge from a parent to its own descendant. The
guard is correct — blocked status cascades to descendants, so the
descendant would inherit the block it exists to lift:

```
$ gc bd dep add <parent> <descendant> -t blocks
Error: <parent> cannot be blocked by its descendant <descendant>:
blocked status cascades to descendants, so <descendant> would inherit
the block and never close
```

The canonical converse shape filed routed work as a CHILD of the subject,
and a child can therefore never express its wait on its own parent as an
edge. That is very likely why metadata markers — `triage.hold`,
`gc.takeaway`-as-a-park — were reached for instead of edges in the first
place. So this is not only "use edges". It requires that routed work stop
being filed as a child of the thing it waits on.

**The replacement shape is the sibling.** A demand, and any work a sitting
routes, takes the SUBJECT'S OWN parent — or no parent at all, when the
subject has none. `gc-helm.sh demand` does this itself, reading the parent
off the gated bead (a `parent-child` edge is stored on the child, so the
gated bead's own row is where its parent is legible). Converse does the
same by hand for work it routes, and the sign-off's
`takeaway --waiting-on <work-bead>` then takes, where against a child it
was refused.

### What happens to routed work already filed as a child

Nothing. It is not re-parented and not migrated. Both readers already
handle it, deliberately: the liveness sweep reads the union of a subject's
`blocks` edges and its children, and the board gives a parked row the same
child roll-up (`services/helm/internal/source/beads.go`, `gatherMetadataAnchors`)
for exactly this reason. That union is the legacy reading and stays.
What changes is what gets filed from here on. A child is covered by the
sweep alone; a sibling with an edge is covered by the sweep, by the board,
and by `bd ready` — which is the one that makes the work move without a
person in the loop.

Converting the existing backlog of parked subjects and `triage.hold` prose
is separate work. It makes the edge the board's primary source and leaves
the metadata as a derived view. `gc.routed_to=human` and `gc.takeaway`
stay readable throughout; nothing here breaks a live hold.

### Where prose alone is still correct

`gc-helm.sh takeaway` keeps writing prose with no edge at two call sites,
and both are right. Both pass `--no-wait`, which is how they say so: the
headline reads the same whether a sitting settled its subject or parked it
on prose, and `lifecycle/lifecycle.toml` `[holds]` declares the marker a
hold unless the writer stamped `gc.takeaway_settled` beside it. The flag is
that stamp. It asserts nothing about the sentence and blanks nothing —
`doctor/check-wait-is-an-edge` reads the key, never the prose.

- **A settled sitting.** The takeaway records what the sitting concluded.
  Nothing is owed and nothing is waiting, so there is no bead to point an
  edge at. The stamp is a record, not a gate.
- **A stand-down (`takeaway … --release --no-wait`).** The dispatch's premise
  is falsified and the work should NOT happen. That is a disposal: the anchor
  is parked, and the molecule beneath it — no live session will ever close its
  chain — is REAPED, every step and its workflow root force-closed. A mere
  de-route cannot end it: an open step, even unrouted, keeps workflow-finalize
  blocked, so the molecule never reaps and its held steps keep drawing
  re-dispatches. A stood-down molecule should die, not park. The one molecule
  spared is the releasing session's own — a sitting disposing the anchor it runs
  on — which closes its chain the normal way and
  only sheds its husk pins. An edge would assert a wait that does not exist.

  An anchor CLOSED before the stand-down reaches it — a fold that landed after
  the pour, leaving the molecule routed behind it — takes the reap without the
  park. Reopening it would make work whose disposition already landed visible
  as open again, so the verb keeps the disposition, skips the reopen, the
  unassign and the route stamp, and reaps the molecule anyway. `--route` is
  refused there and exits non-zero: a pool that claimed a disposed bead would
  cut a branch for superseded work.

Everywhere else the takeaway carries its wait as an edge —
`--waiting-on` for work a pool owes, a demand bead for what a person owes.
A headline written with neither the edge nor the flag is a subject parked on
a sentence, and it is reported as one: that is the third shape, and the check
exists to find it while somebody can still say what the wait was.
No agent in this pack writes a `triage.hold` any more; the sweep's
disposition menu offers `demand` in its place
(`assets/scripts/liveness-sweep.sh`). The readers of `triage.hold` remain,
because live holds predate this and keep working.

## How a held sitting ends

Every `converse-<model>` template sets `idle_timeout = "0"`, which takes a
sitting off the idle ladder entirely: Gas City never registers a template whose
idle timeout is at or below zero with its idle tracker
([gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder)). A held
converse sitting therefore ends when its VISIT closes: the agent's sign-off, or
the operator's `gc-helm dismiss <subject>`. The sign-off is terminal — it stamps
the outcome and closes the visit — so converse takes it only when nothing
important is still pending; a turn that hands the operator important information
(a live decision, a routing answer, anything they may want to respond to) posts
the hand-back and leaves the visit open, ending that sitting on a later turn.
Closing the visit ends the session too, whichever path closes it. The
sitting's own last act is `gc runtime drain-ack`, after the sign-off, a fold,
a moot or benign close, or a finish, and it never claims again: a closed
visit has no next turn in that session. `gc-helm dismiss` closes the visit
and then stops the session that held it, also through `drain-ack`, so the
controller ends the session outside the verb's process; a dismiss typed into
the sitting's own pane acks its own session last. The pack's `converse-reap`
order (`assets/scripts/converse-reap.sh`) is the backstop: it closes any
converse session whose visit reads closed or gone, whether or not anyone is
attached. Viewing a sitting does not hold it open (*How a pane dies when no
sitting is live*, below). A sitting whose visit is still OPEN — the operator
walked away before any sign-off — is the harder, separate case, untouched here.

A visit can also outlive its sitting: the sitting's create fails after
`gc-helm engage` bound the visit to it, or its session is closed while the
visit is still open. Gas City frees neither claim, because its releases keep a
claim routed to `human`
([gascity/human-engagement.md](gascity/human-engagement.md#no-release-frees-a-claim-routed-to-human)).
The witness's orphan recovery frees it instead. It resolves the visit's holder
against `gc session list`, and once that sitting is gone it clears the visit's
assignee and session pins, keeps its route, continuation group and task_kind,
and writes the headline `gc-helm engage` writes when it reclaims a visit from a
gone sitting (`assets/scripts/orphan-dispose.sh`). It releases only the claim
it found gone. A visit that `gc-helm engage` binds to a fresh sitting after the
patrol listed it, or that is settled meanwhile, keeps what that writer left.
engage's reclaim and its bind drop every session pin the visit still carries.
The patrol resolves a visit's holder from `gc.session_id` ahead of its
assignee, so a gone sitting's pin beside a fresh binding would read the fresh
sitting's visit as orphaned. Within one patrol the board reads the visit as
parked, and the operator can engage it again.

Two endings the idle setting does not own:

- **A settled sitting ends itself, not by a runtime clock.** A sitting is a
  manual session, which Gas City keeps desired for as long as it is neither
  closed nor drained
  ([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)),
  so the `no-wake-reason` drain that collects an ended pool session in about
  a minute never reaches it. Its own `drain-ack` ends it, `gc-helm dismiss`
  stops it, and `converse-reap` above closes one that outlives its closed
  visit anyway. See *How a pane dies when no sitting is live*, below.
- **No max-age restart reaches a sitting.** No `converse-<model>` template
  sets `max_session_age`, and an unset age is off. Setting one would end
  long sittings instead of refreshing them. Gas City's max-age restart defers
  while the session holds open assigned work and has no attachment rung
  ([gascity/human-engagement.md](gascity/human-engagement.md#max_session_age)),
  and a sitting's visit is assigned to it, so the restart would fire on the
  first tick after the visit closes and destroy the pane and its scrollback
  under an attached operator. The restarted session would wake unattached
  with its visit closed, and `converse-reap` would collect it.

The cost is real: a held visit nobody answers keeps its sitting's session
running indefinitely, where an idle clock would recycle it. Nothing rations
sittings either. `max_active_sessions` does not cap a manual session
([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)),
so every unanswered hold is one more live provider process. `gc-helm dismiss` is the release
valve, and converse puts it at the foot of every framing it posts as a
copyable line, so ending a sitting is a switch in the thread rather than an
errand the operator has to remember.
It is the verb rather than a bare `gc bd close` because a held visit is
assigned to the session holding it, and a session restarted mid-hold closes
under a different identity string than the one on the bead: bd refuses that
close outright. `dismiss` stamps `gc.outcome=dismissed`, then closes, escalating
to `--force` only when the plain close is refused. The stamp is a precondition
of the close, not a best-effort write beside it: the verb closes only the visits
it can read as OPEN, so a visit closed without an outcome is one no re-run
reaches. A refused stamp leaves that visit open, and the run exits 4. It writes
nothing to the subject: the subject's DONE row, once it closes, leaves the board
only by ageing out of `GC_HELM_DONE_WINDOW`, with no per-row clear.

`prefix+X` ends a sitting the same way from the keyboard, whether or not
converse's copyable line is on screen. After a y/n confirm,
`assets/scripts/tmux-dismiss-sitting.sh` looks the pane's session up in
`gc session list`, refuses one that is not a converse sitting, and runs the
argument-free dismiss under that session's identity, so dismiss itself infers
which subject the sitting is on. It passes `--operator`, because the keystroke
comes from outside the sitting, and dismiss stops the session with an
operator ack. That ack runs with no session identity or incarnation token.
The key's job inherits the sitting's tmux environment, and Gas City refuses
an operator ack whose caller names the session it stops. Nothing is typed
into the pane.

The ending the pack cannot reach from config at all is the pane itself: Gas
City's stop destroys the tmux session, its pane and its scrollback on every
stop path
([gascity/human-engagement.md](gascity/human-engagement.md#stopping-a-session-destroys-its-pane)),
so any stop takes the thread whole. Retiring the session rather than
destroying it is upstream work, evaluated in
`specs/tk-ghlg1e/layout-stability.md`.

A hold has no timeout *in the pack's doctrine* and none in converse's config,
but the runtime under it does end sittings for every role that still sets a
timeout, and converse gets that back the moment someone puts a number in
`idle_timeout`. What the runtime does there — what counts as idle, the rungs
that defer a stop and the cap on the assigned-work defer, the attachment
rung, the scrollback a stop clears, why `[daemon] wisp_ttl` is unrelated, and
what a `wake_mode = "resume"` restart replays — is Gas City behavior, stated
in [gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder).
Read it as what the runtime does, not as what converse experiences.

*Seam:* **nothing pack-owned runs at kill time**, so there is no
warn-before-reap. The converse contract stamps the subject's takeaway when
the hold *begins* (not only at close) because that stamp IS the demand —
the gate the board reads and dependent work blocks on — so it has to land
before the wait, not because a pane might be lost; a failed resume then
still finds a dated record of what the sitting was waiting for. Every
deliberate close of a **held** sitting ends with a sign-off block naming the
outcome and the subject to look at next.

*Longevity is not the remedy, and taking the clock off is not longevity.*
Raising `idle_timeout` only widens the window in which a dead thread looks
alive, which is why the trace is written in advance rather than bought with a
bigger number. Taking the clock off rests on different ground: a thread the
operator is reading must not end without them, and the widened window is the
price of that. Neither move retires the trace, because the endings the clock
never owned are still there.

*The size of that trace (2026-08-22, `tk-9tbbk.1`):* the takeaway is the
board's NEEDS cell — one line in a terminal table — and it is capped at
**140 characters**, which `gc-helm takeaway` now enforces by refusing a
longer text rather than trimming it. While the cap was documentation
alone it ran 22-for-23 against: the stored takeaways averaged
597 characters and were 91% of all the NEEDS text on the board, and
converse wrote all five of the longest. Whatever does not fit is detail,
and detail belongs in the subject's notes or the thread.

*The limit of a written trace, and what closes it (2026-08-22,
`tk-2plde`):* the takeaway is **one string, frozen when it is written**.
That is enough for a reap — the record survives — and not enough for a
wait. A sitting that ROUTES work out of a subject records "routed —
tk-hgmob slung; nothing further needed here" and the subject goes on
saying exactly that after tk-hgmob merges, because nothing in the city
re-reads prose. The operator's framing: *"waiting, holding, those are
graph states, not comments."* So a routed wait is also written as a
**`blocks` edge** — `gc-helm takeaway <subject> "…" --waiting-on
<work-bead>` writes both in one call — and the board re-derives on every
render whether the blocker has closed, promoting the row to *"blocker
landed — dispose or resume"* when it has. Without the edge the wait is
unaskable: tk-yps55 sat parked for 29 hours after its fix merged and
cost a whole sitting to rediscover that it was finished, on a parked
budget where roughly 40% of the reserved rows were already terminal.
Pass `--waiting-on` for every bead a sitting routes work into; a wait
recorded only in prose is a wait nothing will ever re-ask. A wait whose
work has ALREADY landed on the subject's own branch is the one the verb
folds for you: its deliverable is in the subject's head, so the subject's
own merge is what lands it, and `takeaway` writes no edge there — an edge
would gate that merge on work that merges with it, which `merge.sh` holds
on with no release — and a sitting whose every wait is such a rider is
stamped settled, the same shape `--no-wait` writes. Landed is proven, not
assumed from the shared branch: the wait is closed, or handed off to the
refinery. A same-branch wait still open under a pool keeps its edge, because
its work may not be on the branch yet and the subject must not merge past it.

*Where that edge cannot be written, and what re-asks the wait instead
(2026-08-22, `tk-a9k0l`):* the canonical converse shape files the routed
work as a **child** of the subject, and beads refuses a `blocks` edge
from a parent to its own descendant — `cannot be blocked by its
descendant: blocked status cascades to descendants` — so `--waiting-on`
is not available for exactly that shape, and no amount of hygiene makes
it available. The relation the board re-asks there is the
**parent-child roll-up**: a `parked` subject with children is banded by
them rather than floored at LOW, so open work under a parked
conversation reads as the frontier it is. Both boards do this
(`assets/scripts/gc-helm.sh`, `services/helm/internal/`). It also
matters that a plain child bead is not an anchor of its own: it reaches
the board ONLY through its parent's roll-up, so while these kinds
carried a hardcoded empty child set, parking a subject deleted its open
children from every surface. Measured on `tk-z9nln`: the row read
`m_total=0`, and the deliverable it was waiting for was open,
unassigned, unrouted and on no board at all. Pushing the operator once
the last child closes is a separate piece of work (`tk-2cyxo`); the
board stays quiet for that state and only stops mis-stating it.

*The converse of that rule (added 2026-08-14, tk-mndjz):* a visit that
never held closes **silently** — no sign-off, no thread output at all,
only the note appended to its subject. That covers a visit folded into a
sibling sitting, and one whose premise died between filing and claiming
or turned out to name a state that needs no human (`gc.outcome=moot` /
`benign`; an open PR awaiting the operator's own review is the canonical
case). The sign-off exists because an unanswered framing left in a
vanishing thread reads as a crash; where no framing was ever posted there
is no question to abandon, and holding a sitting anyway spends the
attention the whole engagement model is trying to conserve.

*A third way a held sitting can end, and the only one the pack owns
outright:* not an interruption and not a deliberate close, but the claim
loop. A wake nudge reaches a session that is mid-hold, `gc hook --claim`
answers with `reason=existing_assignment`, and the visit it hands back
is the one that session is already holding. Re-claiming produces that
same bead every time. Neither of the claimer's other two verdicts is
safe there: `work` sends the session back through a visit loop that ends
at the close, which ends a sitting the operator has not ruled on, and
`drain` acknowledges a stop while the operator may still be reading the
thread. Without a third verdict the loop has nowhere left to go but the
sitting it is holding.

`assets/scripts/converse-claim.sh` has that third verdict, `action=hold`,
keyed on the `existing_assignment` reason. That reason is not itself proof
of a held sitting. `gc hook --claim` returns it for any bead already
`in_progress` under this session's identity, which covers both a sitting
underway and a claim that died before its premise was ever re-checked. So
the loop states the fact and leaves the sitting where it found it, with
nothing claimed, released, or closed, and the prompt decides which case this
is. Adoption still writes. The same hook result re-stamps the session
identity on the visit, which is how a respawn becomes the recorded holder of
a hold it inherited, and it pre-assigns open same-group siblings when the
visit carries `gc.root_bead_id`. Those siblings are later turns of the same
conversation, so the hold names them on its output line and keeps them rather
than putting them back.

The prompt's arm makes that choice from a trace on the visit's own bead:
`gc.hold_demand`, the id of the demand a sitting files on its way into a hold,
stamped on the visit before it waits. It lives on the visit, not the shared
item, so a sibling holding the same item cannot forge it. Present, the hold is
real and the arm re-opens it and skips the premise re-check. Absent, the arm
does not close on the missing key. A visit whose bead will not read is held,
not closed, because absence of a trace on an unreadable bead is not evidence
of a dead premise. An item that still carries an open demand re-checks the
premise and closes only a moot one, which re-opens and re-stamps a live legacy
hold rather than abandoning it. A clean read with no key and no such demand is
a claim that never began, and re-checks the premise at step 2 where it can
close. Which of two shapes a readable visit is, a thread still carrying its
own framing or a fresh session respawned onto a hold whose scrollback a restart
took, is a question about this session's scrollback that no script can read, so
the claimer states the fact and the prompt makes the choice.

*The one shape that verdict gets wrong, and the fourth that covers it:* a
sitting does not end in a single write. When converse does sign off — the
sitting settled with nothing important left to hand the operator — the prompt
posts the sign-off, then stamps `gc.outcome` on the visit, reads it back, and
closes last of all. A
session that dies between the stamp and the close leaves a visit that is
`in_progress`, assigned, and carrying a final outcome. It is complete in
every way except the one that ends it, and the claim result says only
`existing_assignment`, so the hold answers and the prompt goes back to
waiting. The close never runs. Two nets catch what the missing close would
otherwise strand. When a session claims the visit again, as a respawn does,
`action=finish` performs the close (below). When no session claims it again,
`assets/scripts/liveness-sweep.sh` is the backstop: it counts a visit as
`conversing` only while its holder session is listed in a live state, so a
visit stranded by a dead session — one gone from the session list, or lingering
in it as archived or closed — returns its subject to the unnamed-wait census
rather than masking it.

`action=finish` is keyed on the stamp. Every path that writes `gc.outcome`
closes the visit immediately after it, so a `task_kind=visit` still open
while carrying one is a sitting whose record is already complete. The
claimer performs that close itself rather than returning an instruction to
perform it, and escalates to `--force` when bd's close-authority guard
refuses the two renderings of this session's own identity. The prompt's
arm re-checks that the close took, which is also what performs it on the
claimer-less path, and posts nothing. The stamp lands only after the
sign-off, so a visit carrying it already had its last word, and the pane
that finishes the close is a different thread in any case.

Two constraints follow for anyone tuning this. With the idle clock off no
clock ends a held sitting, so the wake path is the only pack-owned way one
ends without a ruling, and `action=hold` with the visit-trace check the
prompt gates it on is the whole of that guard; re-arming `idle_timeout` adds
a clock, not a substitute for it. And a
wake nudge that names the claimer directly rather than sending the
session through the prompt's claim block skips the block where the hold
verdict is read.

Every `converse-<model>` template holds that field empty, but emptiness is not
what protects a held sitting. A sitting runs as a manual session, never
pool_managed, and no claim backstop governs a session that is not
pool_managed, so no backstop nudge and no drain reaches a converse sitting
whatever this field holds
([gascity/human-engagement.md](gascity/human-engagement.md#the-controllers-backstops-govern-pool-sessions-only)).
What the empty field does reach is the launch delivery, where the prompt is
prepended to it and still arrives, so the second constraint above is what any
text put here has to satisfy.

Attachment is the one reading signal the runtime has, and only this city's
gascity fork reads it: there an attached terminal defers the idle stop, a
detached reader is still indistinguishable from abandonment, and the max-age
restart ignores attachment altogether
([gascity/human-engagement.md](gascity/human-engagement.md#the-idle-ladder)).
That is why the trace is written when the hold begins rather than bought with
a longer clock, and why no converse template sets `max_session_age` (*How a
held sitting ends*, above). Design record: `specs/tk-bzm86/design-doc.md`.

*This section is about a sitting that is still **held**.* How the session
and its pane go once the sitting has ended is *How a pane dies when no
sitting is live*, below.

## How a pane dies when no sitting is live

The section above answers "what ends a **held** sitting". Once a sitting
ends, its session goes with it, and with the session its pane.

**The sitting ends its own session.** A sitting is a manual session, and Gas
City keeps a manual session desired for as long as it is neither closed nor
drained and its template is still configured, so the `no-wake-reason` drain,
which begins when a live session has no wake reason left, never begins for a
sitting
([gascity/human-engagement.md](gascity/human-engagement.md#a-manual-session-stays-up-until-it-is-closed)).
Nothing idle-sleeps one either: that takes a `[chat_sessions] idle_timeout`
or a `[session_sleep]` policy, and this city sets neither (`gc config show`,
2026-10-05). So a sitting ends its own session: once its visit has closed and
every write that must follow the close has run, its last act is
`gc runtime drain-ack`, and the controller stops the session. `gc-helm
dismiss` stops the session that held the visit it closes the same way. The
`converse-reap` order (`orders/converse-reap.toml`, a five-minute cooldown)
runs `assets/scripts/converse-reap.sh`, which closes any converse session
whose visit reads closed or gone with `gc session close`, attached or not: the
backstop for a session that outlives its closed visit.

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
as a child, so when the tab's client exits it reads the visit. A closed visit
prints how it closed and the last hand-back the sitting recorded on it
(`gc-helm handback`, which the sitting runs before each framing and its
sign-off); a visit still open prints the command that re-attaches. Claude
draws in tmux's alternate screen with no history, so nothing of the pane
survives to recover, and the record on the visit is what the tab prints.

Three things about that path are worth knowing before trusting a pane:

- **Nothing is typed into the pane; the pane is taken whole.** Gas City's
  stop kills the tmux session and then signals the pane's captured process
  tree (`KillSessionWithProcessesExcluding`), with no Ctrl-C keystroke
  injection into the pane first
  ([gascity/human-engagement.md](gascity/human-engagement.md#stopping-a-session-destroys-its-pane)).
  So a reply typed into the composer but not submitted when the sitting ends
  goes with the pane.
- **A restart ends the tab too.** A restart destroys the session's tmux
  session and starts a fresh one, so a plain client on the sitting exits as
  it does at the end. The visit still reads open, so the tab prints the
  re-attach command, and `wake_mode = "resume"` brings the thread back.
- **A pool session ends differently, and a sitting is outside it.** A pool
  session left with no wake reason is drained as `no-wake-reason` about a
  minute after its last wake reason goes, and the reconciler acknowledges
  that drain on the agent's behalf, so its stop event reads
  `"drain acknowledged by agent"` even when the agent never ran
  `gc runtime drain-ack`
  ([gascity/human-engagement.md](gascity/human-engagement.md#a-pool-session-with-no-wake-reason-is-drained)).
  A sitting's stop event reads the same, and there it is the sitting's own
  `drain-ack`.

**What the design holds to.** A sitting ends its session as soon as its
visit closes, whichever path closes it, and nothing holds a session open
because someone is viewing it. Nothing copies the pane, and no pane, live or
dead, stays on screen after its session ends, so what a tab prints is the
record on the visit.

**What follows for the pack.** The record has to be written before the pane
matters: the takeaway stamped at hold time, the outcome appended as soon as
a sitting settles anything, each hand-back recorded on the visit as it is
posted, and the sign-off posted at close. What it does not protect is the
operator's *own* unsent words.

## Watch items — moving now, re-verify before building on them

- **The roles pack's growth** — every new upstream role is a standing
  question against a hand-authored one here. Recorded tripwire: when
  upstream ships a role covering something the pack hand-authors,
  re-argue adoption for that role specifically (`tk-h9pq5` Q5).
- **Dashboard surface** — upstream ships `gc dashboard` (Vite SPA over
  the supervisor API); the pack's sanctioned augmentation seam is the
  `proxy_process` `/svc/` route (`services/helm/` already uses it). Any
  conversation surface work should land behind that seam, not in new
  bespoke plumbing.
- **Two helm boards — RESOLVED for the gather (2026-08-22, `tk-134d7`),
  still open for retirement.** The board existed **twice**, and the
  operator's two surfaces were not the same program:

  | | reached by | implementation | gather |
  |---|---|---|---|
  | terminal | `prefix+b` (`tmux-pick-helm.sh:52` → `gc-helm.sh --json`) | `assets/scripts/gc-helm.sh`, POSIX sh | its own, direct `gc bd list` per rig |
  | web | the dashboard | `services/helm/`, Go + React | the beads library / supervisor API |

  `services/helm/internal/board` is documented as "ported field-for-field
  from `gc-helm.sh`", and that port is a **snapshot, not a link**: nothing
  keeps the two in step and neither reads the other. The divergence is
  not hypothetical. `tk-2v08m` fixed the visits-invisible defect in the Go
  board alone (every file it touched is under `services/helm/`) and closed
  honestly on that scope; the terminal board — the one behind `prefix+b` —
  still had it eleven days later, along with the false-stranded defect,
  and `tk-fkeft` fixed both there. Each fix was correct and each board was
  right about itself; the operator still spent that window reading a board
  that was wrong in a way the other one no longer was.

  **The operator picked the middle future (2026-08-22): share one gather
  behind a seam.** Of the three that were coherent — keep them
  independent, share one gather, retire one — `tk-134d7` implemented the
  second. `services/helm` now builds `helm-svc board`, a terminal renderer
  over the SAME `internal/source` gather and `internal/board` derivation
  the dashboard serves, and the shared model was widened to carry the
  whole of `gc-helm.sh`'s 34-field `--json` contract. Verified equal on
  live data at the time it landed — identical anchor sets, all 34 fields
  equal on all 55 rows — with the evidence and the three chosen
  divergences in `specs/tk-134d7/parity-and-benchmark.md`.

  **What is still open is retirement, and `prefix+b` still runs the
  bash.** `tmux-pick-helm.sh` was deliberately NOT repointed: `gc-helm.sh`
  keeps verbs (`open`, `react`, `takeaway`, `demand`) that have no Go
  equivalent, so retiring it is a separate piece of work and still the
  operator's call.
  Until the script is gone there are still two programs, and the tripwire
  stands — but it is now cheaper to honour, because the field sets are
  pinned against each other by
  `services/helm/cmd/helm-svc/contract_parity_test.go`, which fails when
  either side grows or drops a field.

  **The tripwire, as it now reads:** a change to either board's gather,
  ranking, or anchor kinds is still a standing question against the other
  — the parity test compares field SETS, not values, so a derivation that
  changes meaning without changing shape passes it. Say in the PR which
  board you touched and whether the sibling needs the same change.
  `tk-2v08m` did say so, in as many words, which is the only reason
  `tk-fkeft` was findable.

  **Declared divergence: converse sittings, Go board only (2026-08-26,
  `tk-ghlg1e.1`).** The Go board now carries a conversation record beside
  the ranked list — running sittings plus those closed inside
  `GC_HELM_SITTINGS_WINDOW`, each with the `gc.outcome` it closed on — and
  renders it in both `helm-svc board` and the dashboard
  (`services/helm/README.md`, *Converse sittings*). `gc-helm.sh` has no
  counterpart and needs none to stay in parity: the record rides the
  envelope beside `tiles`, so no `Tile` field and no anchor kind changed
  and the field-set test is untouched. What an operator on `prefix+b` does
  not get is the section itself. Building it in bash is a separate
  decision, in the same class as the bash-only verbs above.

## What upstream does not ship (the pack's actual seam)

Revised 2026-08-08 after the build-factory trial and operator probing —
this is the genuinely native ground, and it is deliberately small. A
definition first, because everything below uses it:

> **A visit** is a filed request for one bounded sitting of a
> subject's dialogue, stored as a bead linked to the subject by a
> `tracks` edge and never as its child, whose body says what that
> sitting would be for ("ratify this plan", "review posted — decision
> needed"), whose metadata routes it to the operator
> (`gc.routed_to=human`, the helm board) and names the subject's
> continuation group, whose `gc.outcome` records how it
> resolved, and which closes when it does (the subject never closes
> this way). A visit that is *held* becomes the sitting it asked for,
> and ends out loud, with a sign-off naming the outcome and the
> subject to look at next, because the ending is the one part of a
> sitting the operator cannot reconstruct from the record ("How a held
> sitting ends", above). A visit that is claimed and found not to need
> a human never becomes a sitting at all: it closes silently against
> its subject, because a visit is a request for attention and the loop
> has to be able to answer it with *no*. The sequence of visits under
> a subject is the dialogue's durable spine — board-legible,
> cold-reconstructable, no provider transcript required.
>
> **A sitting is not a unit of work, and it acts on its subject's
> universe in coordination with the operator.** It files beads, slings
> them to a pool, wires edges, appends an outcome to the subject; and on
> an operator-agreed ruling it acts on the subject's PR — commenting,
> replying to and resolving review threads, and retiring it, which closes
> the PR and disposes the anchor as superseded. It writes no files and
> makes no commits, because moving a bead forward is what a molecule does,
> so a sitting that finds work needing doing routes it to one, and where
> nothing can reach the work, the gap is itself a bead to file. The one
> line it does not cross is a repo change. What reaches the operator is the
> point where the operator is needed for a judgment, which is narrower than
> judgment and narrower still than action.
>
> **A visit body is written at FILING time and read at CLAIM time**, and
> those are routinely a day or more apart — a queued visit holds its
> place indefinitely at zero session cost, which is a feature of the
> spine and a hazard for any body that states facts. A body whose claims
> can go stale therefore carries `visit.recheck`: the PATH to an
> executable taking the visit's bead id as its only argument, which the
> converse loop runs during prep and whose corrected output supersedes
> the body. Verified 2026-08-14; the measured failure it answers is bead
> tk-gvas6 — a sweep census claimed 41.5 hours after it was cut, by
> which time five of its ten candidates had merged and deployed.

- **The hold on the gate.** Upstream has the *wait* (human gates,
  `blocks` edges — work durably stops). It has no role that services
  the wait: every upstream role's contract is claim → execute → close;
  none claims a bead and deliberately sits `in_progress` for a human,
  having rebuilt the subject's context and framed the choice, then
  records the answer to the subject and closes only the visit. Gate and
  hold are two halves of one mechanism: the gate makes the work wait;
  the hold (the converse role, on a visit) makes the wait worth arriving
  at instead of a parked bead you cold-start yourself.
- **The board's judgment — as a lens, never a dependency.** Ranking
  what deserves the operator's glance, derived from real graph state
  (open visits, human gates, stranded work), with visual consistency.
  **Constraint (operator, 2026-08-08): everything works without the
  board** — work moves entirely on graph state; the board renders it
  and must never be a mechanism anything depends on.
- **Ratification and record-residency for filed trees.** Upstream's
  build factory *does* decompose brief → requirements → plan → tree of
  beads (corrected after the trial; an earlier revision claimed
  otherwise). What it lacks is the gate — no edge can wait on a human
  before the tree lands — and the record-resident plan (files in
  `plans/`, not rev-pinned on the brief bead, so re-planning re-files
  instead of diffing). The native ground is the gate on the tree, not
  the tree-making.

Everything else in the conversation model is assembly of the primitives
above — which is the point.

## Refresh procedure

This page states the pack's own model, so it changes with the pack's code:
update it in the same PR as a change to a visit producer, the converse
prompt or skills, `gc-helm.sh`, or the board. The Gas City facts it links are
re-verified by the refresh procedure in
[gascity/human-engagement.md](gascity/human-engagement.md#refresh-procedure);
when one of them moves, re-derive the seam here that rests on it.
