---
name: The Delivery layer and the Epic Checkpoint
description: The design for the level under an epic, which epic tk-wmwcdlc builds along with the Epic Checkpoint. It settles what a Delivery is as a bead, when one is filed and by whom, how a filer finds an open one, how a Delivery shows on the helm board, what closes it and where later work goes, and the Epic Checkpoint that follows its landing, which is run by hand first. It also settles what becomes of the child epics already filed, and lists the implementation units. Read it to review the design or to build one of its units.
---

# The Delivery layer and the Epic Checkpoint

## The decision

The model in
[epics.md](../../docs/epics.md#deliveries-and-epic-checkpoints)
delivers an epic through Deliveries, and an Epic Checkpoint follows each one.
This level is SAFe's Feature, as epics.md also calls it, and it is named
Delivery here because bd's `feature` type is a work item (fact 1). Unit 1
carries the name into the docs. This design builds the level from what bd and
the pack already do with a child epic, and an epic takes it only when the
operator aims a Delivery under it. It adds no bead type, no metadata key and no
state. The goals consolidation, the epic's other scope item, already stands in
[epics.md](../../docs/epics.md#deliveries-and-epic-checkpoints), and
the checkpoint below reads the measured and graded criteria it brought.

- **A Delivery is an epic-typed bead whose parent is the epic it delivers.** Its
  Stories are its children. The board, the work checks, priority, parks and
  bd's close rule already treat a child epic as this level needs. Each bd type
  is used only with its own meaning, so a Story may be bd's `feature` and no
  container ever is (section 1).
- **A Delivery carries an aim, not a hypothesis.** Its aim is the portion of
  its epic's hypothesis that its landing tests, a step toward the hypothesis
  and never a hypothesis of its own. Its description states the aim and what
  lands. The epic's checkpoint makes the one ruling, so a Delivery never needs
  a ruling of its own.
- **The layer is opt-in per epic.** An epic may reach its hypothesis entirely
  on Stories under itself, entirely through Deliveries, or through any mix.
  Only the operator's aim ever adds the layer, and an epic without it works
  exactly as an epic works today (section 2).
- **A Delivery is filed by the decision that aims it.** That decision is the
  operator's: the sitting that elaborates an epic, the approval of a design
  whose units deliver it, or a checkpoint's continue or shift ruling. A
  product area alone never calls for one. Agents file Stories into the open
  Delivery whose aim covers them, and otherwise under the epic (section 2).
- **A Delivery shows as a row of its own, nested under its epic's, with no
  board change.** Unit 4 makes a landed Delivery's row ask for its checkpoint
  (section 3).
- **A Delivery closes at the Epic Checkpoint that follows its landing**, as one
  of the ruling's writes. Work found after it lands goes under the epic, and
  into the next Delivery once a checkpoint aims one (section 4).
- **The Epic Checkpoint is a sitting on the epic, run by hand from a recipe.**
  It re-reads the landed work, re-runs the measures, and records the ruling in
  the fields epic stewardship already registers. It closes each Delivery that
  has landed, once it has confirmed every Story under it is still closed. On
  continue or shift it files the next Delivery when the ruling aims one, and on
  close it settles the epic's other open work, item by item, before it closes
  the epic (section 5).
- **Each child epic already filed is read against the rule.** One that holds
  bounded work becomes a Delivery. One that groups an area with no end is
  dissolved into its epic (section 6).

## Facts this design rests on

Each was read on 2026-10-28, at gc-toolkit main ec0a1401, in bd 1.3.2, or in
Gas City upstream main 221b1476d. Each fact about gc-toolkit's code was read
again on 2026-10-29, at main 3db3f983.

1. **bd's types.** `bd types` describes `epic` as a "Large body of work spanning
   multiple issues" and `feature` as a "New feature or enhancement". It
   describes `story` as a "User story describing a feature from the user's
   perspective", and `milestone` as marking "completion of a set of related
   issues (contains no work itself)". Gas City's Tutorial 06 (Beads) files a
   single change with `--type feature`.
2. **The board's rows.** Of the issue types, both board sources give a row of
   its own only to epic, decision and convoy (`typedAnchorKinds`,
   `services/helm/internal/source/beads.go:487`, also read at
   `supervisor.go:692`). `assignGroupRoots`
   (`services/helm/internal/board/derive.go:3025`) nests a row under the row
   its parent-child edge climbs to. So a child epic's row sits under its
   parent's, and a member's row, such as a PR's, sits under the child epic's.
   A child epic whose members have all closed reads
   `all N closed — close or extend` (`derive.go:1093`) and bands LOW
   (`derive.go:800`). The sources differ in what an epic's row carries. The
   default source, the direct store reader, carries each row's metadata
   (`newAnchor`, `beads.go:1315`). The supervisor source, the fallback
   (`selectSource`, `services/helm/cmd/helm-svc/main.go:225`), builds an
   epic's row with no metadata (`gatherEpics`, `supervisor.go:350`), though
   the `/beads` list it reads carries it. The native-gates branch builds the
   row the same way. The built-once board reads through the supervisor API, and
   the direct reader goes
   ([built-once-target.md](../../docs/built-once-target.md#board)).
3. **What counts as work.** `doctor/check-blocked-work-armed` counts bug,
   feature, task, chore and spike as work (`run.sh:75`), and the comment over
   that list names epic, milestone and story as containers whose children are
   the routed work. `assets/scripts/live-work.sh` holds the same five as plain
   work (`live_work_plain_types`, `live-work.sh:72`). A bead of any other type
   carries a mark of live work there, so the until consumer never disposes of
   it. `docs/deferred-dispatch.md` and the waits skill name the same five. The
   gc-toolkit store held three story-typed beads on 2026-10-29, all closed. The
   proactive scan, the refinery's find-work and the witness's read of the
   refinery's queue each pass `--exclude-type=epic`.
4. **Priority and parks pass through a parent of any type.** `priority-lib.sh`'s
   `prio_follows` follows any parent-child parent, and `prio_live` skips a
   closed or pinned one, so a member of a closed epic follows nothing.
   `hold-lib.sh` walks every ancestor, and bd's ready cascade runs down
   parent-child edges. Neither follows a `tracks` edge, except from a
   workflow's synthetic input convoy (`priority-lib.sh:130`). `gc-helm.sh park`
   refuses a bead that is in flight itself, but not one whose children are,
   and a park holds only work that has not started. So a Story already running
   under a parked bead still merges and closes
   ([steering.md](../../docs/steering.md#in-flight)).
5. **Closing.** The finalize-gate clause (`finalize-gate.sh`
   `clause_epic_ruling_recorded`) and I15 hold only an epic that carries
   `epic_hypothesis`. bd refuses to close a bead with an open child unless the
   close is forced (bd's `enforceClosePolicyForTargetInTx`,
   `internal/storage/issueops/close.go:150`;
   [steer-by-epic, fact 5](../tk-rl8gz4b.2/steer-by-epic.md#facts-this-design-rests-on)).
   The same policy refuses, unless forced, to close a bead that has an open
   direct blocker, such as the gate of a park on it (`close.go:153-159`).
   `bd epic close-eligible` closes every epic in the store whose children are
   all complete, and takes no scope.
6. **Listing an epic's open child epics.**
   `gc bd list --parent <epic> -t epic --limit 0` lists them. Run on an epic
   with four open child epics and one closed child, it returned the four.
7. **Convoys.** A Gas City convoy's members are `tracks` edges, and Tutorial 06
   says they "are not children of the convoy". An unowned convoy closes itself
   when its members close. An owned one has a "manual lifecycle, no
   auto-close" and ends with `gc convoy land` (Gas City's CLI reference).
8. **Follow-up placement.** `assets/scripts/converse-parent.sh` prints a
   subject's own parent, whatever that parent's status.
9. **What a sitting may close.** The converse prompt lets a sitting close two
   kinds of subject: a no-work one, and the anchor of a PR the ruling retires
   (`agents/_converse/prompt.template.md:8-12`). No converse prompt or skill
   names an epic ruling or a checkpoint.
10. **One checkpoint has run by hand.** Sitting tk-sbz0v3 judged goal-one
    (tk-y0abyu) on 2026-10-26, and its record is on tk-h2s7hj.4. Re-running the
    measures was mechanical, because the census ran unchanged from history
    against fixed commits. Judgment went to whether the measures captured what
    mattered, and whether a batch could move a number that all the city's other
    work also moves. The graded criteria never got a measure.
11. **Child epics on file.** No gc-toolkit epic has an open child epic. Two
    other rigs hold open child epics, and none carries `epic_hypothesis`. One
    holds the first phase of a product area, the case the operator approved.
    The others are numbered tracks of one epic.
12. **Work in flight on the same files.** The native-gates branch
    (`integration/tk-iirrmiw`) rewrites `docs/steering.md`,
    `docs/epic-stewardship.md`, the work skill, the converse prompt and skills,
    and `derive.go`. It also edits every file unit 7 changes but
    `live-work.test.sh`. Among them, it rewords the comment over
    `live-work.sh`'s plain-work list and the one-line description in
    `doctor/check-blocked-work-armed/doctor.toml`. A trial merge on 2026-10-29
    found that main's copies of those two files merge cleanly with the
    branch's head, bd518614, and that with unit 7's edits on them both
    conflict. On the branch a ruling's `epic_ruling_evidence` is "the human
    gate the ruling cleared". Landing bead tk-1tfzr71.4 carries the branch to
    main, and it closes when the branch lands. The convoy the branch is named
    for, tk-iirrmiw, is closed, and what waited on it waits on tk-1tfzr71.4.
    Steer-by-epic's unit 11 (tk-rl8gz4b.14), which states a checkpoint's
    priority and park moves, is parked.

## 1. What a Delivery is as a bead

**An epic-typed bead whose parent is its epic.** bd's epic type means a body of
work that spans several issues (fact 1), and a Delivery is one. Each reader
below already treats a child epic the way a Delivery needs (facts 2 to 5):

- the board gives it a row and nests it under its epic's;
- the stranded-work check and the work queues do not take it for work;
- its Stories follow its priority, which follows the epic's, and a park on the
  epic holds its unstarted Stories;
- bd refuses its close while a Story under it is open.

"Delivery" names a position: an epic under an epic that carries no hypothesis.
It adds no type, key or state, so it needs no warrant
([foundation.md](../../docs/foundation.md#boundaries), test 2). A child epic
that carries a hypothesis of its own is an epic, not a Delivery, and epic
stewardship holds it as one.

**What it carries.** Its title names what it lands and starts with `Delivery: `,
because the board shows the title. Its description opens with two lines:

- `Aim:` the portion of its epic's hypothesis that its landing tests, a step
  toward the hypothesis and never a hypothesis of its own;
- `Done when:` what lands, as Stories or as checks a person can run.

It carries no `epic_hypothesis`, no `epic_handle` and no ruling field. A
hypothesis is answered by a ruling, and the epic's checkpoint makes the one
ruling. A Delivery with a hypothesis of its own would need its own continue,
shift or close after every landing, and the close gate would hold it until it
had one (fact 5).

**Its Stories.** A Story is a child of its Delivery, or of the epic itself when
no open Delivery's aim covers it (section 2). It is typed by its work: task,
bug, chore, spike, or bd's `feature`. Until unit 7 lands it is never bd's
`story` type, which the stranded-work check names a container and live-work.sh
does not count as plain work (fact 3). Unit 7 makes both read `story` as plain
work, and from then on a Story may be story-typed. PR-finishing work stays
outside every epic and Delivery
([steering.md](../../docs/steering.md#pr-finishing-work)).

**Each bd type keeps its own meaning.** A bd type is used only with its own
semantics, or not at all. So bd's `feature`, which bd and Gas City use for a
single change (fact 1), types a Story and never a container, the Delivery
included. `milestone` stays reserved for a marker that holds no work, which is
what bd says it is (fact 1). A filing rule against a type would bind only this
pack's filers, while the stores go on receiving beads of that type from
everyone else, so the design keeps each type to bd's meaning rather than
banning any.

**Rejected.**

- *bd's `feature` type.* bd describes it as a feature or enhancement, Gas City's
  tutorial files a single change with it (fact 1), and the pack's checks count
  it as work (fact 3). A container of that type would give it a meaning it
  does not have. The board gives it no row, and a row would be new work in the
  board's direct store reader, which tk-1tfzr71.24 retires
  ([built-once-target.md](../../docs/built-once-target.md#3-the-lanes)).
- *A convoy.* A convoy is the engine's dispatch-time grouping, which
  [epics.md](../../docs/epics.md#scope) leaves to the engine. Its members are
  `tracks` edges, which priority and parks do not follow (fact 4), so each Story
  would need a second, parent-child edge to its epic. A Story's PR row would
  then nest under the epic, beside the Delivery's row rather than under it
  (fact 2). An unowned convoy also closes when its last member does, before
  anyone has judged the landing (fact 7).
- *bd's `milestone` type.* It marks completion and holds no work (fact 1), so
  it stays reserved for such a marker. Stories would hang off it by `blocks`
  edges, which priority, parks and the board's nesting do not follow, and it
  gets no row either.
- *A label on the Stories.* A label groups beads with no row, no aim and no end.
- *A hypothesis of its own, the benefit hypothesis SAFe gives this level.* SAFe
  judges at this level too. Here the operator judges only the epic, which keeps
  one ruling per checkpoint.
- *The aim in a metadata key.* Nothing reads it but the checkpoint sitting,
  which reads prose. A key waits for machinery that reads it (unit 6).

## 2. When work becomes a Delivery, and how it is filed

**The layer is opt-in per epic.** An epic may reach its hypothesis entirely on
Stories filed under itself, entirely through Deliveries, or through any mix of
the two. Only the operator's aim ever adds the layer. An epic the operator never
aims a Delivery under works exactly as an epic works today. Its Stories go
under it, and its checkpoint comes when the operator calls a sitting on it
(section 5).

**A Delivery is filed by the decision that aims it.** That decision is the
operator's, made at one of three points:

- the sitting that elaborates an epic and aims its first Delivery;
- the approval of a design whose units deliver it, after which the units are
  filed as its Stories;
- an Epic Checkpoint's continue or shift ruling that aims the next one.

Each Delivery spends the operator's judgment at a checkpoint, so the operator
decides how many there are. A product area, a theme or a wish to find work on
the board does not file one. Work the operator wants to find gets a Delivery
only when it is a bounded step toward the epic's hypothesis, and then its row
comes with it.

**How it is filed.** The filer lists the epic's open Deliveries first (fact 6).
Work an open Delivery's aim already covers goes into that one. A list that
errors is not an empty answer, so a Delivery is filed only once the list
succeeds. A new Delivery goes to no pool, because its Stories are the work:

```bash
gc bd list --parent <epic> -t epic --limit 0 --json
gc bd create "Delivery: <what it lands>" -t epic --parent <epic> \
  -d "Aim: <the portion of the epic's hypothesis its landing tests>
Done when: <what lands>" --json
```

**Where a filer puts a Story.** A Story goes under the open Delivery whose aim
covers it. When no open Delivery's aim covers it, it goes under the epic itself,
and the next checkpoint gathers it into a Delivery or leaves it there. An epic's
members filed before this layer stay where they are, and its next checkpoint
follows their landing.

**An epic may have more than one open Delivery.** Each lands on its own. A
checkpoint reads every Delivery of the epic. It may close each one that has
landed, under its one ruling, and it reads the others as work in flight. A
shift ruling re-aims those in the same pass, and a close ruling settles each of
them before the epic closes (section 5).

**Rejected.**

- *A Delivery for each product area that has none open* (PR #1349's rule). Its
  trigger is an area, which never lands, so its Delivery would never end
  ([epics.md](../../docs/epics.md#epics-are-mortal)).
- *Agents filing Deliveries on their own judgment.* Each Delivery spends the
  operator's judgment at a checkpoint, so filing one is the operator's call.
- *One open Delivery per epic.* Independent steps of one epic would share one
  Delivery, which lands only when its slowest Story does, so the faster step's
  checkpoint would come late.
- *Every Story under a Delivery.* Every epic would have to take the layer, and
  work filed between a landing and the next checkpoint, or before the layer,
  would have nowhere to go.

## 3. How a Delivery is shown

A Delivery is an open epic, so both board sources give it a row, and the row
nests under its epic's. A Story's row, such as its PR's, nests under the
Delivery's (fact 2). The row's name is its title. None of this needs a board
change.

The row a Delivery shows once it has landed needs one change. Today it reads
`all N closed — close or extend` and bands LOW (fact 2). "Extend" asks for the
one thing a landed Delivery must not take, and the low band hides the checkpoint
the Delivery waits for. Unit 4 rewords the row of a landed Delivery (an
epic-typed child of an epic, with no hypothesis, whose members have all closed)
to name the checkpoint it waits for, and bands it with the rows the operator
owes. The change sits in the board's derivation, which the built-once shape
keeps, and adds no field to the board's wire contract. The derivation tells a
Delivery from a child epic with a hypothesis of its own by the
`epic_hypothesis` key in the row's metadata. The supervisor source, the one the
built-once shape keeps, builds an epic's row with no metadata (fact 2), so
there every child epic would read as a Delivery. Unit 4 therefore makes that
source carry an epic's metadata on its row, as the direct store reader already
does. The direct store reader, which tk-1tfzr71.24 retires, takes no new work.

**Rejected.** *A row of a new kind for Deliveries.* A child epic already has a
row, and a new kind would be a new read in the board's direct store reader,
which tk-1tfzr71.24 retires.

## 4. How a Delivery ends

**It closes at the Epic Checkpoint that follows its landing.** The checkpoint
sitting closes it as one of the ruling's writes, with a close reason that names
the ruling (section 5). A Delivery has landed when every Story under it has
closed. bd refuses its close while a Story under it is open (fact 5), so it
cannot close before then. Between its landing and its checkpoint it stays open,
and that open row is what shows the operator a checkpoint is owed.

**What it takes before and after.** Until its checkpoint, a Delivery takes only
work its aim covers, such as a follow-up that finishes one of its Stories. A
follow-up still open at the checkpoint is settled with the operator before the
Delivery closes (section 5, write 3). Other work found after it lands goes
under its epic. Once closed, a Delivery takes nothing. Later work for the same
part of the product goes under the epic, and the next checkpoint gathers it
into a Delivery it aims or leaves it there (section 2). A part of the product
with a hypothesis of its own is an epic of its own, and one that is only ever
improvable is ordinary flow
([epics.md](../../docs/epics.md#epics-are-mortal)).

Today, a follow-up a sitting files from a Story of a closed Delivery would land
under the closed Delivery, because `converse-parent.sh` prints the subject's own
parent whatever its status (fact 8). There it would follow no priority (fact 4)
and sit under no open row. Unit 2 makes the script print the nearest open
ancestor.

**Rejected.**

- *Closing a Delivery when its last Story closes, from the refinery or an
  order.* It would close before anyone judged the landing, and its row would
  leave the board, so nothing would show that a checkpoint is owed. It is also
  machinery ahead of the hand runs.
- *`bd epic close-eligible`.* It closes every epic in the store whose children
  are complete, through a close that runs no finalize gate, so it would close
  stewarded epics without their ruling (fact 5).
- *Keeping a Delivery open after its checkpoint, for its area's later work.*
  That is the standing container the retired rule would have made.

## 5. The Epic Checkpoint

**What prompts it.** A Delivery's landing. By hand, the operator calls a
sitting on the epic once the Delivery's row shows it has landed (unit 4). An
epic with no Deliveries gets a checkpoint when the operator calls a sitting on
it, as today.

Nothing prompts a checkpoint while nothing lands, and that gap is known. A
Delivery that stalls before it lands is inspected only by a sitting the
operator calls. Unit 6's machinery may add a nudge on a Delivery's age,
designed from what the hand runs record.

**What it re-reads.** The ruling is the operator's, and the judge is never the
worker that built the Delivery, so the sitting reads the work itself rather than
the workers' accounts of it
([epics.md](../../docs/epics.md#how-an-epic-closes)):

- each Story's merged change on main and its closed bead, read directly;
- the epic's closure checks, each re-run;
- its measured criteria, re-run by one method at the commit of the latest
  landing the checkpoint reads and at the previous checkpoint's commit. A
  measure that the city's other work also moves is read against that work, so
  the landed work is not credited with the whole change (fact 10);
- its graded criteria, each graded by the operator. A criterion with no way to
  grade it is recorded as such;
- its leading indicators and its backstop invariant;
- each landed Delivery's aim, and what its landing showed about that portion of
  the hypothesis;
- the epic's other open work: open Deliveries, members under the epic itself,
  and PRs in flight.

**How it records the ruling.** On the operator's agreement, the sitting makes
these writes in order:

1. It appends the checkpoint record to the epic's notes, under
   `## Epic Checkpoint after <Delivery ids>, <date>`, naming each Delivery it
   closes. The record holds the ruling, each measure with its commit and
   method, the grades, the indicators, and what comes next. On a close, what
   comes next names each piece of the epic's other open work and what becomes
   of it (write 5). While checkpoints run by hand, it also holds what was
   mechanical, what took judgment and what the contract lacked.
2. It records the ruling on the epic, in the fields
   [epic stewardship](../../docs/epic-stewardship.md#recording-a-ruling)
   registers: `epic_ruling`, `epic_ruling_reason` (on a close, the outcome),
   `epic_ruling_at`, `epic_ruling_by`, and `epic_ruling_evidence`. The evidence
   is the sitting's visit until the native-gates cutover, and the human gate
   the ruling cleared after it (fact 12).
3. It closes each landed Delivery, with the ruling as the close reason. Before
   each close it confirms that every Story under the Delivery is still closed.
   A follow-up opened under it since it landed is settled with the operator
   first, in one of the ways write 5 settles an item. Every close here and in
   write 6 is made the same way, and none is forced. The close waits until
   nothing under the bead is open, and a bead whose PR was retired stays open
   until the refinery's next pass over that PR completes the retirement. The
   sitting then releases the bead from each open blocker on it, such as a
   park, as [steering.md](../../docs/steering.md#releasing-a-park) releases a
   park, which starts nothing because nothing under the bead is open. A gate
   that also holds other beads stays open, and only this bead's edge onto it
   is removed. Only then does the sitting close the bead. A Delivery can land
   while it is parked (fact 4), and bd refuses to close a bead that an open
   park still blocks (fact 5).
4. On continue or shift, it files the next Delivery with its aim when the
   ruling aims one, after re-aiming the epic's contract fields on a shift. It
   then sets the epic's next priority and park with the verbs on main:
   `gc-helm.sh priority`, and `gc-helm.sh park` or the close of the park
   gate, as
   [steer-by-epic section 6](../tk-rl8gz4b.2/steer-by-epic.md#6-a-checkpoint-records-the-next-priority)
   decides.
5. On close, it settles the epic's other open work before it releases
   anything. bd refuses to close the epic while a child of it is open
   (fact 5), and an epic can still hold other Deliveries (section 2), Stories
   under the epic itself, and PRs in flight under either. The operator decides
   each item, whatever the outcome, as
   [epics.md](../../docs/epics.md#how-an-epic-closes) asks of a disproven
   epic's surviving work, and the sitting carries out the decision. Meanwhile
   the epic's park, if it has one, keeps each unstarted item still under the
   epic from starting. Each item goes one of these ways:
   - Work that still coheres around a hypothesis moves to the epic that owns
     it, which the sitting files if no epic does yet. In the same store the
     bead takes a new parent, as
     [steering.md](../../docs/steering.md#placing-a-bead) places a bead: that
     epic's open Delivery whose aim covers it, else the epic itself
     (section 2). A run or PR in flight goes on under the new parent. bd
     resolves an edge only within one store, so work whose epic is in another
     rig's store is filed again there. This bead then closes as re-homed onto
     the new one, through the prs skill's retire path when it has a PR in
     flight and through the disposition writer otherwise. A whole Delivery does
     not move, because its aim answers this epic's hypothesis, so its Stories
     move one by one.
   - Work worth doing on its own, which serves no hypothesis, moves out to
     ordinary flow with no parent. That is a decision about the item, never
     the default for whatever is left.
   - Work that served only this hypothesis is retired. A PR in flight is
     retired through the prs skill, which closes the PR and disposes of its
     anchor. Any other bead closes as the work skill closes a bead that needs
     no work: a run in flight is stopped and an arm disarmed first, and the
     disposition writer closes it with the sitting's visit as the evidence
     that ruled it out.
6. It closes each other Delivery, then the epic, the way write 3 makes every
   close. A Delivery's close reason is the ruling, as in write 3. The finalize
   gate and I15 accept the epic's close on the close ruling with its outcome.

Each ruling overwrites the epic's last one, so each checkpoint's lasting record
is its block in the epic's notes and the close reasons of the Deliveries it
closed. It is also why one checkpoint may read and close every Delivery of the
epic that has landed by then, under one ruling, rather than one sitting for
each. Two sittings run back to back would each write the epic's ruling fields,
and the second would overwrite the first's.

**By hand first.** The recipe is a pack skill (unit 3), not a formula. It names
the writes a sitting makes in order. The machinery that would gather the
evidence, file the sitting when a Delivery lands and make the writes in one
call is designed from what the hand runs record (unit 6). The converse prompt
gains the closes a checkpoint makes (fact 9): each landed Delivery, the open
work the ruling retires or re-homes, and on a close ruling each other Delivery
and the epic.

**Rejected.**

- *A formula that files the checkpoint when a Delivery lands, built now.* This
  epic's scope runs checkpoints by hand first. The one hand run so far found
  that what mattered was judgment about the measures, not their mechanics
  (fact 10).
- *An owed checkpoint as a gate on the epic.* bd's cascade holds every
  unstarted descendant of a blocked bead, so the gate would hold the epic's
  other work until the operator ruled.
- *The ruling recorded on the Delivery.* The ruling answers the epic's
  hypothesis, and the close gate and I15 read it on the epic.
- *The checkpoint record in a file or a bead of its own.* A sitting writes no
  files, and the epic's next sitting primes from the epic's notes.
- *Closing the epic over its open work.* bd closes a bead with an open child
  only when the close is forced (fact 5), and the work would then sit under a
  closed epic, where it follows no priority (fact 4) and sits under no open
  row.
- *Sending whatever is left to ordinary flow.*
  [epics.md](../../docs/epics.md#how-an-epic-closes) rules that out as a
  default. Work begun for a disproven hypothesis is evaluated before it goes
  on, and work that still coheres around a hypothesis is rehomed onto an epic
  that owns it.

## 6. The child epics already filed

At a sitting on each epic that has open child epics, asked for in that epic's
own store (unit 5), each child is read against section 1:

- A child epic that holds bounded work, such as the first phase of a product
  area that the operator approved, gets its `Aim:` and `Done when:` lines and
  its `Delivery: ` title. It goes on as a Delivery that closes at its
  checkpoint.
- A child epic that groups an area, a theme or a track with no end is
  dissolved. Its open members move under the epic, or under the Delivery whose
  aim covers them. It then closes through the disposition writer, the way
  section 5's write 3 makes every close, so a park on it is released first. It
  carries no hypothesis, so neither the finalize-gate clause nor I15 holds the
  close (fact 5).
- A child epic that carries a hypothesis of its own is an epic and stays one.

**Rejected.** *Leaving them as they are.* A child epic with no aim and no end
keeps taking its area's work and never closes, which the operator retired PR
#1349 to prevent.

## Implementation units

Each unit is filed under tk-wmwcdlc. Units 1 to 4, 6 and 7 are each one
reviewable change, pack-side, and none needs a Gas City change. Each updates
the central documents its change makes stale. Unit 5 is sittings, not a
change. Units 1 to 4 and 7 edit files the native-gates branch also changes
(fact 12), so each waits for the branch to land and is written against what it
leaves. Unit 7 is severable. Without it a Story is never story-typed, and no
other unit depends on it.

| # | Unit | Section | Needs | Done when |
|---|---|---|---|---|
| 1 | **The model in the epic docs.** `docs/epics.md` states the Delivery and the Epic Checkpoint as built, and the layer as opt-in per epic, naming the level Delivery with one sentence that maps it to SAFe's Feature. `docs/epic-stewardship.md` says the close gate and I15 never hold a Delivery and the checkpoint closes it, names the level the same way, and narrows its direction to unit 6. `docs/steering.md` places work under a Delivery as under an epic, and names the Delivery level in its priority rule. | 1–5 | tk-1tfzr71.4 | The three docs state the model. None calls the Delivery layer unbuilt, none names the level a Feature outside the sentence that maps it, and none names a sub-epic. |
| 2 | **Filing into a Delivery.** The work skill's "File new work" states section 2's rule, the list of open Deliveries and the Delivery's create. `converse-parent.sh` prints the nearest open parent-child ancestor, with its test. | 2, 4 | 1, tk-1tfzr71.4 | The skill suites pass with the rule stated. `converse-parent.sh` prints the epic for a Story under a closed Delivery of an open epic, and an empty line for a Story under a closed epic with no open ancestor. |
| 3 | **The Epic Checkpoint by hand.** A pack skill that a sitting on an epic follows after a Delivery lands: the evidence, the record, and section 5's writes in order. The converse prompt names the closes a checkpoint makes. | 5 | 1, tk-1tfzr71.4 | The skill and prompt suites pass, with the prompt's pins moved with its sentence. |
| 4 | **A landed Delivery asks for its checkpoint.** The board's derivation rewords a landed Delivery's row to name its checkpoint and bands it with the rows the operator owes. The supervisor source carries an epic's metadata on its row, as the direct store reader does. The derivation's comments say Delivery where they say sub-epic. | 3 | 1, tk-1tfzr71.4 | A board fixture renders a landed Delivery that way, and a landed top-level epic and a landed child epic with a hypothesis as before. A supervisor source test reads an epic's `epic_hypothesis` off its row. The direct store reader is unchanged, and the wire contract gains no field. |
| 5 | **The child epics on file.** A sitting on each epic that has an open child epic, asked for in that epic's store, reads each child against section 6. It is not a PR. | 6 | 1, 2 | No open child epic of an epic, in any rig store, lacks both an `Aim:` line and a hypothesis. |
| 6 | **The checkpoint's machinery.** A design, drawn from the hand-run records, for what they show to be mechanical. Plausibly that is a formula that files the checkpoint and gathers its evidence when a Delivery lands, and one verb that makes the ruling's writes. It may add a nudge on the age of a Delivery that has not landed, designed from the same records. | 5 | 3, and two checkpoints run from the skill | The operator approves the design at its PR. |
| 7 | **A Story may be story-typed.** A census of the story-typed beads in every rig store comes first, so that any bead a rig uses as a container is known before the check reads the type as work. Then `assets/scripts/live-work.sh` adds `story` to `live_work_plain_types`. `doctor/check-blocked-work-armed` adds it to its work list in `run.sh` and to the set its `doctor.toml` names, and drops it from the containers the comment over the list names. `docs/deferred-dispatch.md` and the waits skill, which name the plain-work types, add it too. The proactive scan's own type list, which admits a type only by a deliberate choice, is left as it is. | 1 | tk-1tfzr71.4 | The census's counts are in the PR. `live-work.test.sh` pins the six types, and the check's test reports a blocked, unarmed story-typed bead as stranded work. No pack file names `story` a container. |

A successor bead under the epic (tk-wmwcdlc.2) waits on this spec, and its
dispatch is armed. Once the spec merges, it files this epic's first Delivery,
which the operator's approval of this design aims (section 2). It files units 1
to 5 and 7 as that Delivery's Stories and unit 6 under the epic, so this epic's
own checkpoint is one of the two hand runs unit 6 waits for. It wires the edges
the table gives, arms the units for the polecat pool, and holds unit 6 behind a
park whose gate the operator closes after the second checkpoint run from the
skill. It also appends two notes. The note on tk-rl8gz4b.14 says that unit 3
applies steer-by-epic section 6's moves, so a second recipe is not written. The
note on tk-rctkrj says that its create-time classifier proposes no contract for
a Delivery.

Unit 3 is done when its skill and the prompt land. Its Done when asks for no
run of the skill, because unit 3 is a Story of the first Delivery, and that
Delivery's checkpoint runs only once every Story under it has closed
(section 4). Unit 6's Needs and its park track the runs.

## What waiting costs

Until the units land:

- **Agents keep improvising the level.** Bounded work is filed flat under a
  broad epic, where no row names it, or under a child epic that carries no aim
  and that nothing closes.
- **Nothing asks for a checkpoint.** A landed child epic reads
  `all N closed — close or extend` in the low band, and "extend" invites more
  work into it.
- **A follow-up from a Story of a closed child epic lands under that epic**,
  where it follows no priority and no open row shows it.
- **Checkpoints run without a recipe**, as goal-one's did, so their records
  differ and the machinery has less to be designed from.
- **The child epics on file keep collecting work** with no aim and no end.
- **A Story is never story-typed.** bd's own type for a user story stays out of
  use for one, because two pack readers do not count it as work.

## Risks

- **A Delivery reads as an epic to any reader that counts epics.** Such a reader
  tells the two apart by the Delivery's parent and its missing hypothesis. The
  create-time classifier that tk-rctkrj owns proposes a contract for an epic
  that lacks one, so it has to apply the same test, or it would ask for a
  hypothesis on every Delivery.
- **Checkpoints spend the operator's attention.** Only the operator's aim files
  a Delivery (section 2), and one checkpoint may close every Delivery that has
  landed by then (section 5).
- **A landed Delivery waits on the operator.** It takes only work its aim
  covers while it waits, but it stays open until its checkpoint. Unit 4 bands
  it with what the operator owes, and unit 6 files the checkpoint once the
  hand runs show how.
- **A shift can strand another open Delivery's aim, and a close can strand the
  epic's other open work.** The checkpoint reads every open Delivery of the
  epic. A shift re-aims each one in the same ruling. A close settles each open
  Delivery, Story and PR under the epic with the operator, item by item, before
  the epic closes (section 5).
