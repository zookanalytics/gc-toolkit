---
name: Holding new work on Gas City's hold, with the po working the queue
description: Use when building or reviewing the effort that retires the placement marker (tk-rl8gz4b.28), before giving the po or mechanik a job, or when a change would write, read or lift a hold on new work.
---

# Holding new work on Gas City's hold, with the po working the queue

New work that no epic holds carries Gas City's `hold:mayor` label, the platform's
coordination hold, which the po works in this city. The queue is one native read,
`gc beads list --label hold:mayor`. The po, for Product Owner, is the operator's
prioritization partner: a session the operator opens for a sitting, and each sitting
starts fresh. Its sittings are backlog refinement over the queue and portfolio sync
over the epics. Both open from the rig's stated target and sequence the work by WSJF,
worked live with nothing stored. Placing a bead is one verb, `gc-helm.sh place`,
which sets the parent, slings the bead and lifts the hold. `placement=pending`,
`assets/scripts/placement.sh` and `gc-helm.sh unplaced` all go.

The operator ruled this design's three questions, the seat's name and charter, and
its method in conversation tk-lfi5zph on 2026-11-05, and the next section records
those rulings. Every other answer below is proposed until the operator approves this
design's PR. The rulings it rests on are quoted with where they were said, and text
from the initiative's description (tk-rl8gz4b.28) is named as that. What Gas City
ships is cited in [the search record](gas-city-search.md), read at the commits named
there.

## What the operator ruled

The operator kept this design's direction, amended it, and ruled its three questions
as recommended: "1 - yes PO. 2 - yes. 3 - yes." The quotes in this section are from
conversation tk-lfi5zph on 2026-11-05.

**The seat is the po, chartered as the prioritization partner.** "Name of po works
well", and "I prefer 'chartered as the prioritization partner' we have to make sure
that partner isn't downplayed to something not partner in practice." The vocabulary
is SAFe's. The operator is the Business Owner, with the veto and the final say. The
po is the Product Owner. A sitting over the queue is backlog refinement, and a
sitting over the epics, their parks and their priorities is a portfolio sync.
[The seat and its charter](#the-seat-and-its-charter) states the charter. The
operator's direction of 2026-10-31 called this seat the mayor (visit tk-2hdsjmg), and
this ruling renames it.

**WSJF is the sittings' method and vocabulary, and nothing more.** "Yes, adopt WSJF as
the method / vocabulary not the fields on a bead. 100% agree with your reasons on
why." No metadata key carries it and no score is stored.
[How a sitting sequences the work](#how-a-sitting-sequences-the-work) states the
method.

**1. Who places routine work: the po, once the operator agrees.**
(`docs/authority-map.md` says no agent does today.) The po brings the queue in pieces
that each fit one screen, with its recommendation for each bead and its reasons, and
it applies each ruling. Nothing starts without the operator's word, and the queue
waits between sittings for as long as the operator chooses. That keeps capacity in
the operator's hands, which is what the epic was filed for. The other option, a
standing rule under which the po places alone, can grow from this one later with
nothing rebuilt.

**2. The pile with no first reaction joins the queue at cut-over, one write per
bead.** gc-toolkit's intake is off, so many open beads there have had no first
reaction and carry no marker. Their count is on tk-hok6w. The write spends no tokens
and starts no work. The po's sittings then read one list, and turning intake back on
later reacts only to new beads. Intake stays off, as ruled on 2026-10-26. Some stale
beads will take a sitting's minute to close.

**3. The witness keeps filing findings and human gates, and sends the po no patrol
mail.** Gas Town's witness escalates by mailing `mayor/`, and the witness's target is
Gas Town's (visit tk-dbpz6t2). This stays a named difference from Gas Town
([the witness](#the-witness)).

**The label stays `hold:mayor`,** in the ruling as the sitting recorded it on this
design's bead. Gas City's dispatcher reads only its two fixed hold values, so a label
naming the po would hold nothing ([what a held bead is](#what-a-held-bead-is)). One
line beside the seat in `docs/architecture.md` says that the po works the platform's
coordination hold here.

## The seats at landing

| Seat | Owns | Runs |
|---|---|---|
| po | the queue's writes, and each placement, park and priority move the operator agrees to in a sitting; nothing else it was not ruled to own | when the operator opens it, fresh each sitting |
| mechanik | how the city works, and every town-repo edit | always, with the operator's standing conversation |
| a converse sitting | one bead's conversation | per conversation |
| patrols, pools, refinery | what they own today | unchanged |

The operator's words for the first two, from when the first was still called the
mayor: "mayor (overseer of all, owner of little)", "mechanik (gc-toolkit / Gas City
expert)", and "I'd also rather the mayor take something over the mechanik who is
designed to focus more on gc-toolkit effectiveness" (visit tk-2hdsjmg).

The operator tabled a per-rig seat in the same visit. Nothing here builds one or
closes it off: the verb names no seat, and one store's queue is one
`gc bd --rig <rig> list --label hold:mayor`. Gas City's published `oversight-rig`
pack is the nearest model, a rig-scoped `project-lead` it describes as taking
project-level scoping out of the mayor.

## The seat and its charter

The po is the operator's prioritization partner. The operator's words, from
conversation tk-lfi5zph on 2026-11-05 (typos fixed): "The operator is not all
knowing, the operator is pushing ideas, has unique knowledge, but needs a partner not
a note taker", and "Operator has veto power, but most of what the operator says is
what the operator thinks, not some ruling to be blindly followed if you disagree or
have a reason to be concerned about the direction, surfacing concerns is important.
Surfacing viable alternatives that should be evaluated in which the po thinks would
be better, is useful." The po's prompt carries the charter in these terms:

- It brings a recommendation for each piece of work, with its reasons.
- It says where it disagrees and why, and it raises the concerns it has about a
  direction, the operator's included.
- It proposes the viable alternatives it judges better, and recommends one of them.
- It takes what the operator says as the operator's thinking, to engage with, unless
  the operator clearly rules. When a ruling goes against its advice, it may say that
  it still disagrees, and it follows the ruling.
- It applies a placement, a park or a priority move once the operator agrees to it in
  the sitting.

SAFe's Product Owner has content authority over the team backlog. Here the operator
keeps the final say, as SAFe's Business Owner, so the po argues for its order and
applies each change once the operator agrees (ruling 1).

The operator opens each of its two kinds of sitting:

- **Backlog refinement** works the queue: what to place now, under which epic and at
  what priority, what to close, and what waits for a later sitting.
- **Portfolio sync** works the epics: which serve the target, which should park, and
  what their priorities should be. Work queued under an epic behind a landing, and
  the follow-ups filed under epics, never pass through the queue, so this sitting is
  where they are steered. The operator named the need it serves: "priority right now
  is supposed to be simplifying gc-toolkit's overall surface area and having more to
  gctk. Yet way too many PRs showing up that don't do that, so prioritization feels
  lost."

Its writes go through the levers that already exist. A placement is
`gc-helm.sh place`. A park is `gc-helm.sh park`, and closing the park's gate releases
it. A priority move is `gc-helm.sh priority`. The authority map's park and priority
rows already admit a sitting on the operator's ruling. The po also holds a bead with
`gc bd set-state <id> hold=mayor`, and closes one with its successor through
`assets/scripts/bead-rehome.sh`. It changes no repo, handles no escalation and runs no
rig's lifecycle.

## How a sitting sequences the work

A sitting opens from the rig's stated target, which the rig's `AGENTS.md` names.
gc-toolkit's is the built-once target, whose deletion schedule says what retires and
in what order. Work that does not serve the target surfaces as a proposal to park it,
or to leave it held for a later sitting, with the reason. Where a rig names no
target, the po asks the operator what the rig's work is for before it sequences
anything there.

The po sequences by WSJF, weighted shortest job first: cost of delay over job size,
as SAFe defines it. SAFe counts cost of delay as business value, time criticality,
and risk reduction or opportunity enablement. The operator's framing, "pressing vs
important vs easy", maps onto it: important is value, pressing is time criticality,
and easy is job size. A sitting reads each term against the target:

- **Value:** how far the work moves the rig toward its target.
- **Time criticality:** what waiting costs, such as harm the operator feels now, a
  date, or other work that waits on this.
- **Risk reduction or opportunity enablement:** what the work unblocks or makes safe,
  such as a retirement on the deletion schedule.
- **Job size:** what the work takes, in polecat runs, review rounds and the
  operator's time to review it.

The ruling as recorded names value and time criticality. The third term is SAFe's
own, and this design keeps it so that the sittings use WSJF as SAFe defines it.

The scores are relative and live. The po compares the beads in front of it with one
another, gives its reasoning in the sitting, and stores no score: no metadata key, and
no number in a note. A ruling lands on a lever that exists, a placement, a park or a
priority move, and the note that records it gives the reason in words. The sitting
gave three reasons for storing nothing, and the operator agreed with them. Time
criticality moves as time passes, so a stored score goes stale. A field on every bead
says that everything fits the model. And an order already has its home in priority,
parks and placement.

## What a held bead is

A held bead is open and unassigned, with no route and no arm, and it carries
`hold:mayor`. Gas City keeps such a bead out of the default work query, the hook,
pool demand and the route-restore sweeps.

The label's value names Gas City's default coordinator, but no code branches on who
that is. Gas City's own definition calls its two hold values label values that are
"not role names", and its dispatcher reads only that fixed pair
([the search record](gas-city-search.md#the-seats-name)). So a label of the pack's
own, such as one naming the po, would hold nothing, and the po works `hold:mayor`.

Three things about it are choices:

- **It carries no route.** Gas City's two texts disagree here. The conventions page
  says a pack that parks on a hold usually clears the route, and the session-model
  page says `gc.routed_to` only ever names a backing config identity. The
  `hold-label-routed-to` doctor check wants the route to equal the label's value,
  and its `--fix` writes it. Upstream issue 6069 reports that check as a bug and an
  open PR removes it. This design follows the documented contract, which costs one
  standing doctor warning until the fix reaches the fork. The deacon's patrol step
  today files a warning or runs its `--fix`, so it names this check as known and does
  neither. A route a `--fix` writes anyway is `mayor`, which names no agent in this
  city, so `check-routed-work-claimable` lists it among its notes as matching no live
  identity and judges it no failure. It does nothing while the hold stands, and
  `place` clears it.
- **A create carries the label in its own write** (`--labels hold:mayor`), and a
  bead that already exists takes `gc bd set-state <id> hold=mayor --reason "..."`.
  The conventions page asks for `set-state` every time, so that an audit event
  exists. On a create the bead's own record is that audit, and a `set-state` after
  the create would leave a window with an open bead in no queue, which is the
  reason the witness's block rides the marker on its create today. `set-state` also
  files a closed `event` bead as a child of the subject. The pack's findings already
  live with that.
- **The queue reads the label alone.** `placement.sh` inferred "placed" from six
  facts because no writer cleared the marker. A hold is lifted by a write, so
  nothing is inferred.

## 1. What keeps the po from becoming the dumping ground

The operator's account of why the city's earlier mayor was removed: "lots of items
naturally did go to the mayor to handle... As a mayor, it works well. As the dumping
ground of everything, it became a problem" (visit tk-2hdsjmg). This design's reading
of why: a resident agent with an inbox is the easiest thing to send work to. So it
removes the properties that made it easy, and leaves the prompt only the two paths
nothing can refuse.

- **Nothing upstream aims at it.** Gas City's defaults name the mayor: its warmup
  mail, its default city's one agent, and the `gc sling mayor` and
  `gc session attach mayor` its docs teach. Gas Town's roles mail `mayor/`. Only a
  reference that names the po reaches it, so each of those reaches no seat, as it
  does today.
- **Nothing is waiting to receive.** The seat is on demand and fresh, so no
  conversation accumulates what it was told. Plain mail wakes nothing. A nudge or a
  `--notify` mail does wake it, because Gas City materializes a named session on a
  direct reference. That wake gets one turn, whose only job is to say whose request
  it is.
- **It has no route to fill.** It declares `default_sling_formula = ""` and a
  `sling_query` that refuses with a message saying where the work goes, so a plain
  `gc sling` to the po fails at the caller. It needs both, because the city's
  `[agent_defaults]` gives every agent `mol-polecat-work` and a graph.v2 pour never
  runs the query. `gc sling --on <formula>` pours past the query for the same reason,
  and nothing refuses it.
- **Its queue has named writers.** `hold:mayor` is written only by the writers
  `docs/authority-map.md` lists.
- **One check covers every path that leaves a record.** Assignment, mail and
  `gc sling --on` cannot be refused by config, and any writer can set a label. So one
  doctor check holds one invariant, that the po receives nothing but its queue, and
  a new path shows up as a finding within one sweep of its first use. That is why
  there is one check, not a guard per path. A delivered nudge leaves nothing to read,
  so the check cannot see one.
- **A new ownership is a ruling.** `docs/authority-map.md` gains a row saying so,
  and `docs/architecture.md` lists what the seat owns.

### Every path that would reach it

| Path | What it does at landing |
|---|---|
| `quota-park-nudge.sh`'s default `mayor/`, and `gc-terminal-attach.sh`'s default session, `gc-toolkit.mayor` | Unchanged. No seat answers to `mayor` here, so each reaches no seat, as it does today. The build edits neither script, so `quota-park-nudge.sh`, which tk-1tfzr71.18 retires, takes no change. `GC_TERMINAL_DEFAULT_SESSION` stays, so the operator can choose a default terminal in the town's config. |
| Gas City's warmup mail, hard-coded to `mayor` with no config field | Unchanged, and it reaches no seat. It fires only at `gc start` on a failed check, and the same failure prints on stderr and stays in `gc doctor`. |
| `gc sling mayor "..."` and `gc session attach mayor`, which Gas City's docs teach | They name no agent here, as today. |
| Core's `orphan-sweep` and `spawn-storm-detect`, which go to `GC_ESCALATION_TARGET`, default `human` | Unchanged. The city does not set the variable, and the authority map's new row makes pointing it at the po a ruling. |
| Gas Town's witness, deacon, refinery and polecat, which all mail `mayor/` | The city does not import them, and their mail would reach no seat here. tk-1tfzr71.18 and .19 owe a replacement for that mail if they take those roles, and a note on each says so. See ruling 3. |
| `gc sling po "..."` | The seat has no formula of its own, so this reaches `sling_query`, which refuses. |
| `gc sling` to the po with a graph.v2 formula, by `--on` or `--formula` | Nothing refuses it. The run's steps route to the seat, which wakes and takes none of them, because its prompt takes no work from the hook. The check names the steps. |
| Assignment: `gc bd update --assignee`, `first-reaction-dispose.sh --assign` or `--then-assign`, or `gc-helm.sh takeaway --release --assign` | `first-reaction-dispose.sh` refuses the po's address. The others wake the seat and the check names them. |
| `gc mail send` to the po | Delivered, and it wakes nothing. The po's prompt treats unread mail as a sign of a path and says whose it is. The check names the sender. |
| `gc session nudge`, `gc mail send --notify` to the po | These materialize the seat and wake it, which costs one first turn. With nobody attached, its prompt says whose request it is and runs `gc runtime drain-ack`. The check names a `--notify` mail's sender and sees no nudge. |
| `hold:mayor` set on something that is not new work | The check names it: a bead with an anchor or a landing state. A branch alone does not count, because a run that ended can leave one on a bead the po holds again (section 6). |
| `dolt` maintenance's `alert_to`, `gc convoy --owner mayor` | Unset in this city, or display only. They stay as they are. |
| The operator typing a request at the po | It engages with what the operator says, as its charter asks. For anything to be done beyond its own writes, it files a bead or a human gate, or says whose job it is. |

A default that names a seat the city lacks has hidden a real problem once. The checkout
reconciler assigned its alerts to a mayor that did not exist, and a diverged checkout
went unseen for about a day (tk-dk78ru). That reconciler files a human gate now. The
defaults above that name the mayor reach no reader today, and this design leaves them
as they are.

`deacon-`, `refinery-` and `witness-human-gate-wiring.test.sh` keep their assertions.
Their reason changes: "there is no mayor mailbox to absorb it" becomes that the po's
mailbox is not an escalation channel. "Mail dedups nothing" goes, because `gc mail send`
has `--dedup` now.

### The witness

The later ruling asks which this is: a difference this effort ends, or one that
stays. It stays, because ruling 3 keeps it. The initiative's description says
"Escalations stay visits and gates", and `docs/built-once-target.md` gains it among
the witness's differences from Gas Town:

- **Reason:** Gas Town's witness mails the mayor for emergencies, failures,
  recovered and handed-off orphans and queue health. "Owner of little" rules that
  load out of the po. The missing dedup cited in the old comments is not the reason,
  since mail has it now.
- **What ends it:** an operator ruling that gives the po escalation handling.
- **Owed by tk-1tfzr71.19:** Gas Town's formula addresses `mayor/` literally, and that
  name reaches no seat in this city. So a copy taken by import would send its
  escalations to no reader. A copy must keep findings and human gates, or the import
  must be ruled.

### Where the po differs from Gas Town's mayor

A role's default is Gas Town's, and each difference names its reason and what ends
it (visit tk-dbpz6t2, said of the witness and applied here as this design's own
reading). The po takes the agent shape of Gas Town's mayor: `scope = "city"`,
`wake_mode = "fresh"`, `work_dir = ".gc/agents/po"`, `max_active_sessions = 1`. Each
difference below but the last ends with an operator ruling that gives the seat the job.

| Gas Town's mayor | This city's po | Reason |
|---|---|---|
| Named `mayor` | Named `po` | Gas City's defaults and Gas Town's roles aim at the name `mayor`, so a seat that answers to it takes their sends. SAFe's word names the job (ruled 2026-11-05) |
| The human's point of contact | The operator's prioritization partner, in backlog refinement and portfolio sync | The operator's charter (ruled 2026-11-05) |
| Dispatch liberally | Places, parks and moves priority once the operator agrees in a sitting | Owner of little, with the final say the operator's (ruling 1) |
| Fix directly when fast | Changes no repo | The pools do the work, and mechanik edits the town repo |
| Handles escalations | Files or points | Findings and human gates carry them (ruling 3) |
| Rig wake and sleep | Reads only | The operator's and mechanik's today |
| `gc handoff` when context fills | No handoff, no carried memory | A resident context is one symptom the record names |
| `idle_timeout = "1h"` | `sleep_after_idle = "1h"` | An idle kill keeps the conversation key, and `gc session attach` would then resume the old conversation. An idle drain clears the key. This ends when `gc session attach` honors `wake_mode` |

## 2. What "overseer of all" means at landing

The po may read anything. It writes only the queue's acts, and the parks and priority
moves the operator agrees to in a sitting. It reads inside a sitting, when the work or
the operator's question calls for it, and no schedule makes it read. It raises in the
sitting whatever it reads that bears on the work, whether the operator asked or not,
as [its charter](#the-seat-and-its-charter) says.

- **To open a sitting:** the rig's stated target, which the rig's `AGENTS.md` names
  ([how a sitting sequences the work](#how-a-sitting-sequences-the-work)).
- **For backlog refinement:** `gc beads list --label hold:mayor --format=json`, each
  bead's card with `gc bd show`, the open epics and what holds them, and the
  `AGENTS.md` of the bead's rig, since a rig can say where a kind of problem goes, as
  gc-toolkit's does for code its deletion plan retires.
- **For a portfolio sync:** the open epics in each store
  (`gc bd --rig <rig> list --type epic --status open`), what holds each, their
  priorities, and the work queued under each.
- **For the operator's questions:** `gc status`, `gc session list`, `gc rig list`,
  the board, open PRs, any bead.

It starts fresh for each sitting, through `wake_mode = "fresh"` and `on_demand`. A
detach does not end a sitting, because Gas City keeps a running on-demand session up
until its idle limit. So a sitting ends when the operator says it is done and the po
runs `gc runtime drain-ack`, or an hour after the operator detaches, through
`sleep_after_idle`. An attach inside that hour continues the sitting. Both ends drain
the session, which clears its conversation key, so the next attach is a new
conversation. Each ruling lands on its bead before the next piece, so nothing is
lost. The prompt forbids `gc handoff`, and the seat's `env` sets
`CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, because a handoff note or a memory file would
rebuild the resident context by another route. Unit 3 proves all of this live, since
it was read from the source and not run.

## 3. Which coordination jobs leave mechanik

Placement and the portfolio's levers, which both match the operator's sentence quoted
above:

- **The placement sitting** moves to the po, as backlog refinement. So does the batch
  sort in `.gc/agents/mechanik/placement-2026-10-31/`, the method on tk-hok6w's
  newest Current state block. The sorter's brief becomes the refinement skill,
  written with no rig's details in it, and it sequences by the method above.
- **Parks and priority moves** move to the po's portfolio sync, as the ruling of
  2026-11-05 set out, and each applies once the operator agrees in the sitting. The
  operator still runs `gc-helm.sh park` and `gc-helm.sh priority` directly, and a
  converse sitting still applies one that a ruling on its own subject calls for.
- **tk-rl8gz4b.17 stays mechanik's, smaller.** Its move 1 edits the town repo, which
  only mechanik does, and its timing stays the operator's. Its move 2 ran on
  2026-10-14 and the cut-over below replaces the marker it wrote, so a note says so.

## 4. Placing as one act, and how a hold lifts

`gc sling` reads no hold, so a sling leaves the label on. The hook then serves the
bead to nobody and the controller wakes nobody for it, the refinery after a hand-off
included. Nothing native places and lifts in one write, because a sling is a separate
command. So placing is one verb that runs the native writes in a set order and can be
run again.

```
gc-helm.sh place <bead> --under <epic> [--shift <±n>] [--route <rig>/<pool>] [--on <formula>]
gc-helm.sh place <bead> --standalone [--route <rig>/<pool>] [--on <formula>]
```

`--under`, `--shift` and `--standalone` come from tk-rl8gz4b.13, the verb this
replaces. `--route` takes the form `gc-helm.sh takeaway` gives it, and `--on` is
`gc sling`'s. With no `--route` it uses the polecat pool of the bead's rig, and with no
`--on` that pool's default formula. It writes in this order:

1. It refuses a closed bead and a bead carrying `anchor_bead`. A bead with no
   `hold:mayor` is refused, or reported as already placed when a live run works it.
2. It clears any route, because a `--fix` may have written one and
   `deferred-dispatch.sh arm` refuses a routed bead. With `--under`, it removes any
   relates-to edge between the two, sets the parent and reads it back. `--shift`
   writes the shift.
3. It runs `queue-priority.sh settle`, as `rework-child.sh` and `gate-ensure.sh` do
   before they sling, because a pour copies the priority once.
4. It dispatches, unless an assignee or a landing state shows that an earlier run of
   the verb already did and stopped before its lift. When `hold-lib.sh` says a blocker
   holds the bead or an ancestor, it arms the re-dispatch, so a park keeps holding.
   Otherwise it runs `gc sling`, whose exit 3 means a live run of that formula already
   works the bead, and it goes on.
5. It lifts, in one write: `gc bd update <bead> --remove-label hold:mayor
   --append-notes "Placed ..."`, and reads it back. This write leaves the route alone,
   because a sling that falls back to a plain route needs the one it wrote.

**Dispatch comes before the lift.** A sling that fails leaves the bead held, in the
queue, where someone is looking. Lifting first would leave an open, unrouted bead in
no queue, which is the shape this effort removes. If a crash lands between the two,
the run goes on with the hold still on it. The queue still lists the bead, the check
names it, and running `place` again finishes the lift without a second run.

**A hold lifts in one of these ways:**

- `place` lifts it.
- `gc-helm.sh takeaway --release --route` and `gc-helm.sh accept` lift it, because a
  route the operator writes through either is a placement.
- A close leaves the label on a closed bead, which nothing reads.
- `gc bd update <bead> --remove-label hold:mayor` lifts it by hand. An `until` edge
  onto a retiring bead takes this write too. A bead lifted this way with nothing else
  written is raw input again, so the scan reacts to it when intake is on and the
  sweep names it until then.
- `set-state` cannot do it, because it refuses an empty value and no state command
  removes a dimension.

A bare hand sling of a held bead is not caught when it runs. The check names it on
its next pass, and `place` finishes it. The work skill tells an agent to use `place`
for a held bead.

## 5. Whether the po may place routine work itself

Ruling 1 settles it: the po places a bead once the operator agrees in a sitting, and
never on its own. The authority map's rows read as follows:

- **Hold new work:** the same writers, with `hold:mayor` in place of the marker.
- **Place a held bead:** the operator directly, or the po once the operator agrees to
  the placement in a sitting. The po may never place without that agreement.
- **Park a bead, and write a bead's priority:** the rows already admit a sitting on
  the operator's ruling, and they name the po's portfolio sync among those sittings.
- **Close-with-successor:** the po joins its callers, on the operator's agreement in a
  sitting, as converse is today.

## 6. Who notices a placed bead whose run ended with the bead open

**At landing, the liveness sweep still does.** A placed bead carries no hold, so its
classifier reads it as an unnamed wait, which is what the sweep does with that shape
today. PR #1369 chased a pour's stale stamp hiding a marked bead from the queue. With
no marker and no inference, that shape no longer exists.

**After tk-1tfzr71.19 retires the sweep, its replacement owes this, as a doctor check
or a board view.** The shape is: open, no hold, no wait, no landing state, no live run
by `run-lib.sh`, and a pour's stamp left behind. The po reads that list in a
sitting and holds each bead with
`gc bd set-state <id> hold=mayor --reason "its run ended"`. That puts it in the one
queue, where `place` can send it again, since `place` refuses a bead with no hold. The
po is overseeing here and owns nothing new. The note tk-rl8gz4b.30 writes on
tk-1tfzr71.19 carries this.

**The cause stays where it is.** A graph.v2 run does not claim the bead it works, so
an ended run leaves nothing on the bead that says so. Gas City's nearest reads do not
tell this case apart: `gc convoy stranded` lists every unassigned tracked bead,
including those under a live run, and the orphan sweeps act on assigned beads or on a
branch with a session back-reference. tk-1tfzr71.12, which rebuilds the work formula
on core's base, is where this cause can be fixed.

**It is rare.** On 2026-11-01, of the beads `bd ready` offers in this rig's store, 6
of 525 carry a pour's stamp with no live run, and one of those has a PR. Each exit of
`mol-polecat-work` that can leave its bead open already writes where it went: a decline
files its gate and its wait, and a store-only run writes its record, with a closer when
the record finishes the bead. What remains is a hand cancel, a finding whose reaction
has ended, a store-only record nobody has closed, and old residue. That rate does not
justify a new detector before the sweep retires, so this design adds none.

## 7. How this squares with `docs/built-once-target.md`

The page says "What a person owes is a native human gate on the bead it blocks". This
design leaves that sentence true and adds placement beside it, because a held bead
owes nobody an answer:

- **A gate is one bead waiting on one person's judgment,** and something is overdue
  while it stands. Gas City's `await_type=human` means that, its orders can notify and
  renudge on it, and here a sitting can answer it.
- **A hold says the next actor is a seat.** It carries no debt. A bead can sit in the
  queue for weeks with nothing overdue, and the queue is worked in pieces when the
  operator chooses.
- **The operator steered this way on 2026-10-31:** "some conversation / visit or
  active agent that I engage to discuss open items... Not a fan of the fix cadence or
  fixed set to accept", and "I feel like 187 being done one at a time is going to
  consume quite a bit of tokens". A gate per bead is that one-at-a-time ask (quoted on
  tk-1tfzr71.17 and tk-hok6w). So tk-1tfzr71.17's "a native human gate for ... a
  placement" goes, and a note there says so.
- **They combine.** A held bead whose first reaction owes the operator a real question
  still files a gate through the ruling exit.

The page gains this under Human engagement:

> New work no epic holds is owed to nobody. It carries Gas City's `hold:mayor`, and the
> po, a fresh on-demand session chartered as the operator's prioritization partner,
> works that queue with the operator. A hold is the next actor's queue, and a gate is
> an answer someone owes.

It also lists the po's differences from Gas Town's mayor above, and states the witness's
difference in its Patrol section. That section's list arrives with tk-r4c0g67's
branch, whose line says the difference ends when this design rules. So the unit
rewrites that line if the branch has landed and writes the paragraph if it has not.

## 8. Moving each writer and reader

Each file was checked against `tools/deletion-plan.tsv` at d983f9f50, main once PR #1359
landed, and again at f78ca1f02, main on 2026-11-05. There every file exists, no row
has moved, and the files that name the marker are the same set.

| File | On the plan | What it does after this |
|---|---|---|
| `assets/scripts/first-reaction-dispose.sh` | no (tk-1tfzr71.17 rewrites parts) | Intake writes `set-state hold=mayor` with the reason it already builds and reads the label back. Its note names the queue read. `--assign` and `--then-assign` refuse the po's address. |
| `formulas/mol-witness-patrol.toml`, `bug-file` | no | `--labels hold:mayor` on the create, with its prose and the suite that pins it, `witness-route.test.sh`. |
| `formulas/mol-feedback-distiller.toml`, file-and-dispatch and 1b | no | The same, on each `prompt-update` and engineering bead, with `distiller-file-for-placement.test.sh`. |
| `skills/work/SKILL.md`, `agents/proactive/prompt.template.md`, its `agent.toml` and `PROVENANCE.md`, `formulas/mol-deacon-patrol.toml`'s prose, `skills/learning-distill/SKILL.md` | no | Wording, with the exact commands. The deacon's step gains the known check. |
| `assets/scripts/placement.sh` and its test | no | Deleted. |
| `assets/scripts/dispatch-path.sh` | no | Gains `has_dispatch_hold`, read the way Gas City's `HasDispatchHold` reads: either canonical value, trimmed, any case. The queue's readers already source this file. |
| `assets/scripts/gc-helm.sh` | no (tk-1tfzr71.24 rewrites parts) | `unplaced` goes with its suite, `gc-helm-unplaced.test.sh`. So do `stamp_hides_placement` and the failure it raises, and a surviving stamp only warns. `place` arrives, and the two routing verbs lift the hold. |
| `tools/gc-proactive.sh` | no | `(has_dispatch_hold \| not)` in the filter. |
| `doctor/check-blocked-work-armed` | no | Reads the label on the row it already has, so its second `bd list` and its "could not be read" warning go. |
| `assets/scripts/liveness-classify.sh`, `-recheck.sh`, `-sweep.sh`, `-sweep-precheck.sh` and their suites | **yes, tk-1tfzr71.19** | The smallest edit that lets `placement.sh` go: the source line drops, the predicate's name swaps, and the line of text a census gate carries names the new read. They gain no behavior, the PR's size line shows these lines against the retiring bead, and a note on it says why. |
| `assets/scripts/deferred-dispatch.sh` | no (tk-1tfzr71.16 rewrites parts) | Sources `dispatch-path.sh`, and its reconcile leaves a held bead alone, because a sling reads no hold, so a held bead with an arm would pour. `arm` still accepts one, because `place` arms and then lifts. |
| `lifecycle/lifecycle.toml`, `[metadata.placement]` | no | Marked retired by unit 1. The follow-up removes it and adds `placement` to `check-state-space`'s `RETIRED_KEYS`. |
| `docs/steering.md`, `docs/authority-map.md`, `docs/architecture.md`, `docs/component-model.md`, `docs/feedback-learning.md`, `docs/built-once-target.md`, `docs/human-engagement.md` | no | State what is true after landing. `architecture.md` gains the seats, with the line beside the po that it works the platform's coordination hold, and its "There is no mayor" sentence becomes that a situation needing a person is a human gate, not mail to the po. The authority map's human gate row loses "there is no mayor", and says a gate, not the po's mailbox, carries what a person owes. |
| `docs/review-demo.md` | no | Its example of a report command names `gc-helm.sh unplaced` and that verb's suite, so it takes another verb's. |
| `services/helm/internal/board/derive_test.go` | no | The fixture drops its marker. The board has no reader of it. |
| `deacon-`, `refinery-` and `witness-human-gate-wiring.test.sh` | no | The comment above. |

Left alone on purpose: `docs/warrants.md` and `docs/gascity/routing-model.md` state
Gas City's hold, which does not change. `formulas/mol-review.toml`'s "the mayor's" is
an example of a claim. `lifecycle.toml`'s "the mayor's beads" goes with tk-1tfzr71.14,
which retires the reconciler it describes. `doctor/check-hq-marooned-work/doctor.toml`
names a mayor among the city-scoped roles, and unit 3 names the po beside it.

### The beads already carrying the marker

The census on 2026-11-01 read every store, the suspended rigs' included, since they
share the city's Dolt server. 53 open beads carry the marker, across five stores and
three of them suspended. In the running rigs, 29 read as waiting and 3 as already
placed. The list is in this bead's notes, and the count moves as beads are filed.

The cut-over is the same commands run twice. A bead that still reads as waiting takes
`set-state hold=mayor --reason "held for placement before the native hold"`. A bead
already placed takes nothing. After landing, every bead also loses the key.

- **Before the effort's PR merges,** the first pass adds holds in the stores whose scan
  is on, which the town's `proactive-scan-sling` overrides say. Those are the stores
  where a scan would otherwise spend first reactions on these beads after landing. The
  old and new readers both read a bead with both as waiting, so no reader needs a
  transition mode. Two things live in that window do not know the hold, and the narrow
  pass keeps what they reach small. A placement through the old verbs leaves the hold
  on. The deacon's live step can answer the new doctor warning with its `--fix`, whose
  route takes the bead off `gc-helm.sh unplaced` until landing.
- **After it merges,** a bead armed behind tk-rl8gz4b.28 runs the pass in every store,
  for anything filed since as well. It runs `place` on a held bead that a live run, a
  landing state or a route other than the `mayor` a `--fix` writes shows was placed in
  the window. It unsets the key everywhere and lands the registry change above. By
  ruling 2, the same bead also holds the pile.

These are commands in a bead's description, so the repo gains no migration script.

## 9. The session's cost

On demand. The token cost does not decide it:

- A wake's first turn loads about 40k to 50k tokens, going by recent mechanik and
  deacon transcripts, and mechanik started 11 conversations over the last week. A first
  reaction is about 3.2M tokens (tk-1tfzr71.17). An idle session spends nothing.
- What decides it is what each mode invites. An always-up session is a live address
  that shows as active in `gc session list`, which is the resident agent the
  initiative's description records as a symptom.
- On demand fits how the seat works, since nothing here runs unattended, and held work
  wakes nothing, because Gas City leaves held beads out of wake readiness.

The operator's door is `gc session attach gc-toolkit.po`, or bare `po`. An on-demand
session materializes on that reference. The helm terminal's `?session=` passes its
guard once the session has been materialized, or from any start if the operator sets
`GC_TERMINAL_DEFAULT_SESSION`.

## What is ours, and what ends it

| Pack piece | Kind | What ends it |
|---|---|---|
| `gc-helm.sh place` | Glue: native writes in a set order, adding no state | `gc sling` lifting a hold, or tk-1tfzr71.24 folding it |
| `has_dispatch_hold` | Forced: shell readers need Gas City's predicate over JSON rows | A reader moving to Go or to a native filter |
| `doctor/check-po-queue-only` | A feature: the invariant "owner of little" needs in order to hold | An operator ruling that gives the seat more, which changes what it asserts |
| The po's agent, prompt and refinement skill, carrying the charter and the method | Configuration and prose on Gas City's agent and named-session primitives, modeled on Gas Town's mayor | Each difference above ends as it says |
| One known doctor warning | Contained debt from Gas City's check | Upstream's fix reaching the fork |

This design adds no pack noun. `hold:mayor` is Gas City's, the po is an agent
configured from Gas City's agent and named-session primitives, and WSJF stores nothing,
so no kind of object or state is the pack's own. It removes the one pack noun the
marker was, which never had a warrant.

## The units

`tk-rl8gz4b.30` files these under the epic, each with
`target=integration/tk-rl8gz4b.28`, and makes `tk-rl8gz4b.28` and the summary task wait
on each. They run in order, because they share files.

1. **The hold.** Writers and readers move to the label, `placement.sh` and `unplaced`
   go, and the registry entry is marked retired, per the table above. Steering's intake
   sections and the authority map's hold row are rewritten. Done when a first reaction,
   the witness and the distiller each leave a bead carrying the label with no marker,
   and the scan, the sweep and `check-blocked-work-armed` each leave it alone.
2. **Placing.** `gc-helm.sh place` and the two routing verbs. tk-rl8gz4b.13 closes,
   with this unit as its successor. Done when `place` on a held bead ends with a live
   run and no label; a failed sling leaves the label on; and a second run after a stop
   at any write finishes the job. Placing under a parked epic must arm instead of
   pouring. Steering's "Placing a bead" and the authority map's place row come with it.
3. **The seat.** `agents/po/` with its prompt, carrying the charter, the method and the
   exact commands; the refinement skill; the `pack.toml` stanza with
   `mode = "on_demand"`; the `agent.toml` with its empty `default_sling_formula`,
   refusing `sling_query`, `sleep_after_idle` and `env`; a line in mechanik's prompt
   saying placement and the portfolio sync are the po's; the po in
   `check-hq-marooned-work`'s list of city-scoped roles; and `architecture.md`,
   `built-once-target.md`, §4 of `component-model.md`, and the seed audit's render. The
   prompt and skill are pack content, so they name no rule that binds only gc-toolkit,
   and a sitting reads its target from the rig's `AGENTS.md`. The seat takes the
   `gh-origin-guard` overlay, as mechanik does, which touches that warrant, so the unit
   re-verifies it. Done when a live probe shows that
   an attach materializes the seat and starts a new conversation with no memory index,
   a detach leaves it up, `gc runtime drain-ack` or the idle limit ends it, and the next
   attach starts another conversation. Plain mail wakes nothing, and a nudge wakes it for
   one turn. The probe also tries `gc sling` to the seat. Without `--on` it should exit
   non-zero, and with `--on` the run pours and the check's first arm names its steps. The
   unit records any result that differs.
4. **The check.** `doctor/check-po-queue-only`, with its invariant in §3 of
   `component-model.md`. It reports an unheld bead or a run's step routed or assigned to
   the po, unread mail from any sender, a held bead that is not new work, and a held
   bead carrying an arm, an assignee or a live run. It exempts no sender. Gas City's
   warmup mail goes to `mayor`, not to this seat, and an exec order's mail carries the
   `human` sender too. Done when each arm fails on its fixture and the live city reads
   clean.
5. **The first pass.** A store-only bead running the first pass above. It waits on the
   four units and runs before the summary task.
6. **The follow-up.** Filed by unit 5, armed behind `tk-rl8gz4b.28`, and not waited on
   by it, since it runs after the merge. It runs the second pass and lands the registry
   change, in a PR of its own to main.

`tk-rl8gz4b.30` also writes the notes this design promises, on tk-1tfzr71.14, .17, .18
and .19 and on tk-rl8gz4b.17, when it files the units. They wait for the approval, since
until then the answers the operator has not ruled are proposed.

**Branches that overlap.** PR #1359 landed on main at d983f9f50, after the integration
branch was cut at c41d2ea1d. It rewrote much of this ground: `gc-helm.sh`,
`first-reaction-dispose.sh`, `deferred-dispatch.sh`, the liveness scripts, `lifecycle.toml`,
the witness formula and the docs above. Building on the older copies would mean rebuilding
them, so unit 1 merges origin/main into the integration branch first, and each later unit
branches from that. The merge brings comments and gate text naming `awaiting_placement` and
`gc-helm.sh unplaced`, which unit 1 moves with the rest. #1217 and #1373 edit the witness
formula or the docs here and add no reader of the marker, so they take no edge, and #1375,
which did the same, has landed on main. The effort's branch merges main again before its
PR. `tk-ssm8qns.12` deletes `hold-lib.sh`
in favor of `gctk bead holds`, and `place` calls whichever is on main when it is built.

## What this leaves in place

- **The cost of waiting for this effort:** `placement=pending` keeps working as it does,
  and its known gap stays open, since PR #1369 was retired for this.
- **Intake:** gc-toolkit's stays off (operator, 2026-10-26), and whether first reactions
  return there stays the operator's call, on the numbers on tk-hok6w.
- **A short queue read:** a store that fails inside `gc beads list` drops its rows with
  no notice, because the command prints the API's rows and leaves out its
  `partial_errors`. `gc-helm.sh unplaced` reports this today, and that goes. Nothing acts
  on a bead's absence from the queue, so a short read costs one sitting a look at those
  beads, and the store's failure shows in `gc doctor`. Its rows also carry no priority,
  so the po groups by subject and reads a bead's priority when it discusses that bead.
  Its JSON is an array from the direct read and `{"beads": [...], "_cache_age_s": n}`
  through the API, so the prompt's command and the check accept both, and rows from the
  API can lag by that age.
- **Hand slings:** see section 4.
- **A nudge to the seat:** it costs one first turn and leaves nothing for the check to
  read. `gc sling --on` to the seat is refused by nothing, and the check names it.
- **An order that is not stored:** a sitting's order lives only in the rulings it
  lands, so the next sitting works it out again from the target and the levers' state.
  That is the method as ruled, and it costs each sitting the time to do it.
