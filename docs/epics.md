---
name: Epics — what an epic is, what it carries, and when it closes
description: gc-toolkit's stance on epics — the contract an epic carries (hypothesis, Belongs/Boundaries, closure condition, leading indicators), the hypothesis-answered closure model, epic mortality, the unit an epic lands as, and progressive elaboration. Read it to write or judge an epic. Not how a bead becomes a member of one — that is membership.
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
elaborated — the form every epic follows.

**Boundaries.** The form of an epic, not the scope content of any particular
epic: a given epic's own Belongs/Boundaries is authored on that epic, not here.
Not how a bead becomes a member of an epic — that classification by the
`parent-child` edge is the membership mechanism, settled in
[specs/tk-xgj2ko/membership-mechanics.md](../specs/tk-xgj2ko/membership-mechanics.md).
Not dispatch-time grouping (whether two beads should have been one convoy),
which the engine owns. Not a standing theme or initiative layer above epics,
which is deliberately deferred. Filing conventions are
[file-structure.md](file-structure.md); where epics sit in the workflow is
[architecture.md](architecture.md); what the operator judges a change against is
[product-goals.md](product-goals.md).

## The contract an epic carries

An epic carries four fields. Together they make it first-class: readable on its
own, verifiable against an outcome, and scoped at its edges. The shape follows
the current BMAD epic template (`Outcome`, `Boundaries`, `Done when`) and SAFe's
epic hypothesis, reusing [file-structure.md](file-structure.md)'s
Mandate/Boundaries vocabulary so epics and docs read the same way.

**Hypothesis statement.** One sentence: for whom, what changes, and the signal
that shows it worked. This is the epic's goal sharpened into a claim that can be
answered, not a theme that can only be worked on. It is what makes the epic
readable without opening a child.

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
pivot-or-persevere call before the full cost is spent. They are not a progress
bar of closed tickets.

The floor for an epic to exist is lower than the full contract: a hypothesis
sentence plus boundaries is enough to file one and to classify work into it (see
[Elaboration is progressive](#elaboration-is-progressive)). The closure
condition and indicators are filled in as the epic is elaborated.

## How an epic closes

An epic closes when its hypothesis is answered, following SAFe's model, never as
a side effect of its last PR merging. Units land, then get evaluated against the
hypothesis, and the close is a ruling that follows a validation step. This holds
for a single-unit epic too: the one unit lands, the hypothesis is judged, and
only then does the epic close. An epic is never closed by the automatic
transition that closes an ordinary bead when its last child merges.

The ruling can be persevere, pivot, or close. An epic whose hypothesis is
disproven closes just as validly as one whose hypothesis holds; surviving work
continues as ordinary flow without the epic. The mechanism that runs the
validation and slings an epic's next unit is epic stewardship, a separate
concern from this contract.

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
own. Review effectiveness collapses past a few hundred changed lines and
AI-assisted changes inflate diffs, so an epic reviewed as a single PR cannot be
judged; the unit keeps each review at a size a human can actually read.

The user-facing shape of a unit is one PR from a branch into main, fully
reviewed, as the operator's last gate before the work is live. Mid-flight,
reviewable pieces — a mockup, a unit spec — land as PRs into an integration
branch for operator review; nothing reaches main until everything the unit's
spec carries has come along with it. Convoys are an engine-internal grouping and
never materialize to the operator as a unit.

A spec that spans more than one unit is not a unit-spec. It is an epic-level
elaboration artifact, and the units it describes are filed and land separately.

## Elaboration is progressive

A thin epic is legal at intake. The floor is one hypothesis sentence plus
boundaries — enough to read the epic and to classify work into it — and the rest
of the contract is filled in as the epic is elaborated. Obvious work under the
epic proceeds in parallel with that flesh-out; there is no freeze of all work
behind a fully elaborated epic.

The city has a natural tendency to elaborate: it generates the elaboration work
itself and surfaces drafts for operator review, rather than waiting for a human
to write the contract up front. Create-time classification proposes an epic's
hypothesis, boundaries, and closure condition; the operator confirms, recorded
as a dated decision on the epic. A periodic scope-reading audit re-reads the
epic against completed work and proposes updates in place. That generation-and-
audit machinery is epic stewardship, authored separately from this contract.

## Worked example: this epic

The template applied to `tk-rctkrj`, the epic this contract descends from. Its
hypothesis and closure condition are the create-time draft, proposed for the
operator to ratify; the live contract for an epic is carried on the epic itself.

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
- A new epic is filed with at least the floor contract (hypothesis plus
  boundaries), and the city proposes a contract for an epic that lacks one.
- An epic closes by a ruling on its hypothesis after a validation step, and an
  area with no provable hypothesis is not filed as an epic.

**Leading indicators.**

- The share of open work beads that are members of an epic trends up.
- Operator board-reading questions of the form "is this work grouped under an
  epic?" stop recurring.
- Epics close with a recorded hypothesis ruling rather than a last-PR auto-close.
