---
name: Epics — what an epic is, what it carries, and when it closes
description: Use when you write or judge an epic, rule on one, or decide whether work is an epic, a Delivery or ordinary flow. Not how a bead becomes a member of one — that is membership.
---

# Epics

An epic is a bounded, testable hypothesis about the product, with a declared
scope and a condition that answers it. It is not a title over a pile of beads.
gc-toolkit borrows the shape from established agile and AI-dev practice rather
than inventing one ([foundation.md](foundation.md): the pack borrows before it
invents); the sources it draws on are SAFe's epic hypothesis and lean funnel,
BMAD-Method's epic template, and Shape Up's ban on standing containers.

## Scope

**Mandate.** What makes a body of work an epic: the contract every epic
carries, how an epic closes, the unit of work it lands as, and how it is
elaborated — the form every epic follows — and the Delivery and the Epic
Checkpoint, the level an epic may land through and the sitting that judges a
landing.

**Boundaries.** The form of an epic, not the scope content of any particular
epic: a given epic's own Belongs/Boundaries is authored on that epic, not here.
Not how a bead becomes a member of an epic — classification by the
`parent-child` edge is the membership mechanism, a separate concern. Not
dispatch-time grouping (whether two beads should have been one convoy),
which the engine owns. Not a standing theme or initiative layer above epics,
which is deliberately deferred. Filing conventions are
[file-structure.md](file-structure.md); where epics sit in the workflow is
[architecture.md](architecture.md); what the operator judges a change against is
[product-goals.md](product-goals.md). The design behind the Delivery and the Epic
Checkpoint, with the alternatives it rejected and the units that build them, is
[specs/tk-wmwcdlc.1/deliveries-and-epic-checkpoints.md](../specs/tk-wmwcdlc.1/deliveries-and-epic-checkpoints.md).

## The contract an epic carries

An epic carries five fields. Together they make it first-class: readable on its
own, verifiable against an outcome, and scoped at its edges. Four follow the
current BMAD epic template (`Outcome`, `Boundaries`, `Done when`) and SAFe's
epic hypothesis, reusing [file-structure.md](file-structure.md)'s
Mandate/Boundaries vocabulary so epics and docs read the same way; the handle is
gc-toolkit's own, for operator legibility.

**Handle.** A short phrase, three to five words, that names the epic wherever it
is surfaced — the Helm board, a brief, a cross-reference. It is the operator's
context handle: a stable phrase that calls the whole epic to mind without
re-reading the hypothesis. It is not a bead `label`, which is a first-class,
many-per-bead grouping primitive; the handle is a single phrase that belongs to
the epic. It sits on the epic alone, and a child does not inherit it: a child
may carry its own short name, but that name is never the epic's handle.

**Hypothesis statement.** One sentence: for whom, what changes, and the signal
that shows it worked. This is the epic's goal sharpened into a claim that can be
answered, not a theme that can only be worked on. It is what makes the epic
readable without opening a child. A rough first statement that sets the general
direction is enough to start; sharpening it as evidence comes in is expected,
not a reopening.

**Belongs and Boundaries.** The epic's scope, in the two-part form every
authoritative doc uses. *Belongs* is the hypothesis plus the work it owns.
*Boundaries* names the axis the epic is cut on — a capability, a service, a
surface — and the adjacent work it is *not*, pointing at the epic that owns that
instead ("not the merge cadence, owned by the merge workflow"). A boundary marks
an edge and names where the neighbor lives; it does not catalog members.

**Closure condition.** Three to six checks a person can run without opening a
child, each of which fails today. Closing every child is not one of them: an
epic's completion is defined by the outcome it can be tested against, not by the
state of its members. This is the property that makes an epic more than a bag of
beads.

**Leading indicators.** One to three signals, watched while the epic is in
flight, that say whether the hypothesis is being borne out. They inform the
continue-or-shift call before the full cost is spent. They are not a progress
bar of closed tickets.

The floor for an epic to exist is lower than the full contract: a handle, a
hypothesis sentence, and boundaries are enough to file one and to classify work
into it (see [Elaboration is progressive](#elaboration-is-progressive)). The
closure condition and indicators are filled in as the epic is elaborated. The
only hard gate is that a hypothesis exists at all — its wording is expected to
improve through the work, and nothing here is meant as a major gate on filing.

## How an epic closes

An epic closes when its hypothesis is answered, following SAFe's model, never as
a side effect of its last PR merging. Units land, then get evaluated against the
hypothesis, and the close is a ruling that follows that evaluation. This holds
for a single-unit epic too: the one unit lands, the hypothesis is judged, and
only then does the epic close. An epic is never closed by the automatic
transition that closes an ordinary bead when its last child merges.

Each evaluation ends in one of three rulings:

- **continue** — the hypothesis is not yet answered and the course holds. The
  next body of work aims at what is still short.
- **shift** — the evidence calls for a different course. The approach changes,
  the hypothesis may be re-aimed with it, and the next body of work follows the
  new direction.
- **close** — the hypothesis is answered. This is the only terminal ruling, and
  it carries its outcome: the hypothesis held, it was disproven, it cannot be
  met as stated, it stalled, or it ran past what it was worth.

A continue or shift ruling keeps the epic open, and only close ends it. An epic
whose hypothesis is disproven closes just as validly as one whose hypothesis
holds. The ruling is the operator's, made on evidence read directly, such as the
landed work and the measures re-run. The worker that built the units under
judgment never rules on them, because a worker's account of its own work is not
evidence.

A disproven epic's surviving work is not swept back into ordinary flow by
default: work begun to serve a disproven hypothesis is evaluated deliberately,
and work that still coheres around a hypothesis is rehomed onto an epic that
owns it rather than scattered.

The latest ruling and its reason are recorded on the epic (`epic_ruling`,
`epic_ruling_reason`). An epic that carries a hypothesis stays open until it is
ruled close with its outcome recorded, which
[epic stewardship](epic-stewardship.md) enforces.

## Epics are mortal

There are no standing epics. An area that is only ever "always improvable"
carries no hypothesis that can be answered, so it is not an epic — filing it as
one creates a container that never closes, which Shape Up bans as dead weight.
Such an area is ordinary flow, or a future theme once that layer exists.

A standing theme or initiative layer above epics, which would legitimately never
close and would spawn bounded epics, is deliberately deferred. Mechanisms for
epic mortality — attention decay, periodic re-evaluation — are left to future
work. Today the discipline is simpler: if you cannot state a hypothesis an epic
can be measured against, it is not an epic.

## The unit an epic lands as

An epic lands as a reviewed sequence of units, never as one omnibus PR. A unit
is material: a spec plus the implementation that solves something useful on its
own. An epic reviewed as a single PR mixes too many concerns for a reviewer to
judge any of them well; a unit keeps each review scoped to one coherent change a
human can hold in mind. The measure is scope — how many distinct concerns a
review must carry — not the line count of the diff.

What an epic cares about is that it is a collection of discrete units of
deliverable work, each separable and independently reviewable. How a unit
actually moves to main — the review gate, the integration branches that hold
mid-flight pieces, the convoys the engine groups work into — is the workflow's,
described in [architecture.md](architecture.md); an epic does not redefine it.

A spec that spans more than one unit is not a unit-spec. It is an epic-level
elaboration artifact, and the units it describes are filed and land separately.

## Elaboration is progressive

A thin epic is legal at intake. The floor is a handle, one hypothesis sentence,
and boundaries — enough to read the epic and to classify work into it — and the
rest of the contract is filled in as the epic is elaborated. Obvious work under
the epic proceeds in parallel with that flesh-out; there is no freeze of all work
behind a fully elaborated epic.

A thin epic needs no committed document: it lives as a filed bead carrying its
handle, hypothesis, and boundaries — a place to hang work before anything is
written down. When an epic is elaborated into a product brief, or a spec that
spans its units, that artifact is a committed repo document under `specs/`, the
same as any other durable record ([file-structure.md](file-structure.md)).

Elaboration is meant to come from the city rather than wait for a human to
write the contract up front: create-time classification proposing an epic's
hypothesis, boundaries, and closure condition for the operator to confirm,
recorded as a dated decision on the epic, and a periodic scope-reading audit
re-reading the epic against completed work and proposing updates in place.
Neither is built. Today the operator records the contract on the epic, and
[epic stewardship](epic-stewardship.md) enforces only the ruling that closes it.

## Deliveries and Epic Checkpoints

The Delivery is built from what bd and the pack already do with a child epic,
and the Epic Checkpoint runs by hand. The operator records each
ruling on the epic, and the pack checks that an epic closes only on the close
ruling with its outcome ([epic-stewardship.md](epic-stewardship.md)). Nothing
prompts an evaluation when work lands, so one happens when the operator calls a
sitting on the epic. The machinery a checkpoint may grow is
[direction](epic-stewardship.md#direction-the-checkpoints-machinery).

**Epic, Delivery, Story.** A Delivery is a bounded step toward an epic's
hypothesis: a group of Stories, worked in parallel where they can be, whose
landing tests a portion of the hypothesis. It is the level SAFe calls a Feature,
named Delivery here because bd's `feature` type is a work item, a single change.
A Story is one unit as defined above, one PR or a few.

**The layer is opt-in per epic.** An epic may reach its hypothesis entirely on
Stories under itself, entirely through Deliveries, or through any mix of the two.
Only the operator's aim adds the layer. An epic the operator never aims a
Delivery under works as any epic works: its Stories go under it, and its
checkpoint comes when the operator calls a sitting on it.

**What a Delivery is as a bead.** An epic-typed bead whose parent is the epic it
delivers, with its Stories as its children. "Delivery" names that position. It
adds no type, key or state, because each reader already treats a child epic the
way a Delivery needs:

- the helm board gives it a row of its own, nested under its epic's, and a
  Story's row, such as its PR's, nests under it;
- the stranded-work check and the queues of routed work do not take it for work,
  and it goes to no pool, because its Stories are the work;
- its Stories follow its priority, which follows the epic's, and a park on it or
  on the epic holds its unstarted Stories ([steering.md](steering.md));
- bd refuses its close while a Story under it is open.

Its title names what it lands and starts with `Delivery: `. Its description opens
with two lines:

- `Aim:` the portion of its epic's hypothesis that its landing tests, a step
  toward the hypothesis and never a hypothesis of its own;
- `Done when:` what lands, as Stories or as checks a person can run.

It carries no hypothesis, no handle and no ruling. A hypothesis is answered by a
ruling, and the epic's checkpoint makes the one ruling. A child epic that carries
a hypothesis of its own is an epic, not a Delivery, and
[epic stewardship](epic-stewardship.md) holds it as one.

**Each bd type keeps its own meaning.** A bd type is used only with its own
semantics, or not at all. So a Story is typed by its work, one of the types the
pack counts as plain work
([deferred-dispatch.md](deferred-dispatch.md#the-resolved-by-consumer-until)). It
may be bd's `feature`, and `feature` never types a container. `milestone` stays
reserved for a marker that holds no work, which is what bd says it is.

**When work becomes a Delivery.** A Delivery is filed by the decision that aims
it, and that decision is the operator's:

- the sitting that elaborates an epic and aims its first Delivery;
- the approval of a design whose units deliver it, after which the units are
  filed as its Stories;
- an Epic Checkpoint's continue or shift ruling that aims the next one.

Each Delivery spends the operator's judgment at a checkpoint, so the operator
decides how many there are. A product area, a theme or a wish to find work on the
board does not file one.

**Where a Story goes.** A Story goes under the open Delivery whose aim covers it.
When no open Delivery's aim covers it, it goes under the epic itself, and the next
checkpoint gathers it into a Delivery or leaves it there. An epic may have more
than one open Delivery, and each lands on its own. PR-finishing work stays outside
every epic and Delivery ([steering.md](steering.md#pr-finishing-work)).

**How a Delivery ends.** A Delivery has landed when every Story under it has
closed. It closes at the Epic Checkpoint that follows its landing, as one of the
ruling's writes, never on its own when its last Story closes. Between its landing
and its checkpoint it stays open, so its row stays on the board.

Until its checkpoint it takes only work its aim covers, such as a follow-up that
finishes one of its Stories, and a follow-up still open at the checkpoint is
settled with the operator before the Delivery closes. Other work found after it
lands goes under its epic. Once closed, a Delivery takes nothing. Later work for
the same part of the product goes under the epic, and the next checkpoint gathers
it into a Delivery it aims or leaves it there. A part of the product with a
hypothesis of its own is an epic of its own, and one that is only ever improvable
is ordinary flow ([Epics are mortal](#epics-are-mortal)).

**The Epic Checkpoint.** After a Delivery lands, the epic is evaluated against
its hypothesis at a sitting the operator judges, and the checkpoint rules
continue, shift, or close ([How an epic closes](#how-an-epic-closes)). Every
checkpoint has the same shape whatever it rules; only the next action differs.
Stories run in parallel, but an epic's checkpoints come one at a
time. The sitting re-reads the evidence the ruling needs, the landed work and the
measures re-run, rather than taking the worker's account, and it reads each landed
Delivery's aim against what its landing showed. The judge is never the worker that
built the Delivery.

**What a checkpoint writes.** The ruling goes on the epic, in the fields
[epic stewardship](epic-stewardship.md#recording-a-ruling) registers. Each ruling
overwrites the last, so the checkpoint's lasting record is its block in the epic's
notes and the close reasons of the Deliveries it closes. That is also why one
checkpoint reads and closes every Delivery of the epic that has landed by then,
under its one ruling.

A continue or shift ruling files the next Delivery when it aims one, and a shift
re-aims each Delivery still open. A close ruling settles the epic's other open
work with the operator, item by item, before the epic closes: its other
Deliveries, the Stories under it and the PRs in flight under either. Work that
still coheres around a hypothesis moves to the epic that owns it. Work worth doing
on its own moves to ordinary flow, by a decision about that item and never by
default. Work that served only this hypothesis is retired.

**A checkpoint is always qualified.** A checkpoint is any point where the city
evaluates something, and its qualifier names what is evaluated. An Epic
Checkpoint evaluates an epic against its hypothesis. A PR Checkpoint is the merge
workflow's checkpoint, a pull request that lands a stage on an integration branch
for review ([state-machine.md](state-machine.md)). A Bead Checkpoint evaluates a
single bead.

**Goals fold into the epic.** A goal is not a separate primitive. Its design
record (`specs/tk-yaor8a/`) already carried a goal at epic altitude, with no
bead or metadata of its own, so the epic is its home. The epic contract takes
four of its ideas:

- The checkpoint shape. Work advances in bounded batches, each closed by an
  evaluation that aims the next; here that is the Delivery and its Epic
  Checkpoint.
- Judge independence. The worker never renders the verdict on its own work.
- Measured and graded criteria. The closure condition holds numbers where
  reality has numbers, a baseline and a target the judge re-runs, and grades
  where it does not, qualities the operator grades at each checkpoint. A
  measured target met while a graded quality regressed does not answer the
  hypothesis.
- The anti-gaming invariant. A backstop holds throughout, so no capability is
  deleted to move a measure.

The goal verdicts collapse into the ruling: not-yet becomes continue, and met,
impossible, stalled, and exhausted each become close, with the one that applied
recorded as the close's outcome.

## Worked example: this epic

The template applied to `tk-rctkrj`, the epic this doc is filed under. Its handle,
hypothesis, and closure condition are the create-time draft, proposed for the
operator to ratify; the live contract for an epic is carried on the epic itself.

**Handle.** First-class epics.

**Hypothesis.** For the operator judging the city's work, a first-class epic —
one carrying a stated hypothesis, a declared scope, and reliable membership —
turns a scatter of related beads into a coherent initiative they can read and
steer, the signal being an initiative that reads as one body of work with a
visible goal rather than a title over scattered beads.

**Belongs.** The form an epic takes (this doc), the membership mechanism that
places work under the right epic, and the classification that runs at create
time and on a periodic audit.

**Boundaries.** The structure of epics and the mechanism that populates them,
not the scope content any particular epic declares (authored on that epic) and
not dispatch-time convoy grouping (an engine concern reconciled with, not
redefined). The standing theme/initiative layer is out of scope and deferred.

**Closure condition.**

- Every open work bead is either a member of an epic or explicitly recorded as
  standalone with a reason; no work is a silent orphan.
- The helm board renders each epic's work grouped under it, not scattered beside
  its own children.
- A new epic is filed with at least the floor contract (a handle, a hypothesis,
  and boundaries), and the city proposes a contract for an epic that lacks one.
- An epic closes by a ruling on its hypothesis after a validation step, and an
  area with no provable hypothesis is not filed as an epic.

**Leading indicators.**

- The share of open work beads that are members of an epic trends up.
- Operator board-reading questions of the form "is this work grouped under an
  epic?" stop recurring.
- Epics close with a recorded hypothesis ruling rather than a last-PR auto-close.
