# Outcome — rethinking gc-toolkit from the ground up

> **Filing note.** `specs/` directories are keyed by bead id
> ([file-structure.md](../../docs/file-structure.md)). This work was authored on
> a contribution branch outside the city, so `tk-rethink` is a placeholder slug;
> re-key the directory to the tracking bead at intake.

This document is the first gate of a three-phase effort — **outcome → spec →
implementation**, each reviewed before the next begins. It states what a
ground-up rebuild of gc-toolkit must deliver and what it must not attempt. The
spec ([spec.md](spec.md)) makes it concrete; the implementation realizes the
spec. Nothing here restates [foundation.md](../../docs/foundation.md) or
[architecture.md](../../docs/architecture.md) — it traces to them.

## Why rebuild

The pack works, but its composition contradicts its own boundaries in ways
[architecture.md](../../docs/architecture.md) already names as transitional:

1. **The composition boundary.** gc-toolkit imports the gastown example pack
   wholesale and patches eight agents by fragment injection
   (`pack.toml`). Foundation says gastown "is an example pack, not an upstream."
   Architecture marks the wholesale import as "transitional… deliberately not
   encoded here as the architecture."
2. **The conversation model.** The shipped host-and-board composition
   (epic `tk-q4xaj`) is superseded by the ratified continuation-group direction
   (`tk-h9pq5`), which is built entirely from primitives Gas City already ships.
3. **The molecule-check interlock** — the loop that makes "automated to
   resolution" first-class — is "mostly unrealized"; most work is still a single
   agent doing a single task.

Each drift is individually known and individually fixable, but they interlock:
the roster shape comes from gastown, the conversation model routes around the
roster, and the interlock needs both settled. A ground-up recomposition —
built beside the operational pack and cut over in stages — resolves them
together instead of three partial migrations that each inherit the others'
debt.

## Outcomes

Each outcome names the belief or architectural commitment it delivers. These
are the acceptance tests for the whole effort; the spec must show how each is
met, and the implementation must trace every shipped capability to one.

### O1. A gc-toolkit-native composition — no wholesale upstream import
The new pack imports no example pack as a roster. Roles the pack needs are
authored natively as gc-toolkit's own opinions; anything genuinely reusable
from elsewhere is borrowed piecemeal *with citation*, not inherited by import.
*(foundation: The pack borrows before it invents — and its Boundaries;
architecture: the composition boundary transition.)*

### O2. Conversation grounded on continuation groups
The conversation system is the `tk-h9pq5` direction realized: the subject
bead's id is the conversation's identity, turns are routed child beads, warm
sessions vacuum turns via the continuation group, cold sessions reconstitute
from the record. No resident host object, no attention board, no reverse links.
*(foundation: Human attention is the budget; architecture: how agents exist
and converse.)*

### O3. A delivery spine on bare primitives
Delivery composes beads (open until landed), checks (head-pinned, re-opened by
any new commit), and routing (worker claims; single-writer lands when green).
The pack stays landing-strategy-neutral except where a check must hold:
agent-initiated code is pinned to the gated path. *(foundation: Agents make
their edges visible; architecture: Delivery, "How a bead finally lands.")*

### O4. The molecule-check interlock designed in, not retrofitted
New-work formulas are authored so that a molecule step signs off the check it
satisfies, and a check that has not run runs itself rather than blocking
silently. The rebuild does not claim to *complete* the interlock — it commits
to never shipping a formula whose shape forecloses it. *(architecture: the
molecule-check interlock.)*

### O5. Lessons carried forward, never re-learned
Every doctrine the current pack earned from a real failure — the
template-fragments, the cycle-recycle overlay, the patrol fixes pinned to
beads like `lx-ody8m` and `tk-1waw2` — has an explicit home in the new
composition or an explicit, recorded reason it is no longer needed. Silent
loss of a hard-won fix is a review-blocking defect. *(foundation: Agents
improve; the no-cheap-restart boundary.)*

### O6. The doc spine is phase zero
The rebuild files its own decisions the way the pack files everything:
central claims refreshed in `docs/`, work records under `specs/<bead-id>/`,
per [file-structure.md](../../docs/file-structure.md). At cutover, central
docs are updated in place to speak the new truth — this effort produces no
parallel doc tree. *(foundation: Decisions have a home; goal G3.)*

### O7. A minimal resident roster, earned by the three-hats test
Every resident (named-session) agent in the new pack passes the test in
architecture.md: partner + active patrol + library, all three, or it is a
molecule routed to a disposable role. Patrols are molecules. The default
roster size is zero residents; each one is an argued exception.
*(architecture: "A domain earns a standing agent by needing all three hats.")*

### O8. Every surface branded
Each role name, bead type, doc path, and turn subject the new pack introduces
states its brand in one sentence at the point it is defined, or the surface is
not added. *(architecture: "Every surface a conversation presents is
branded.")*

## Non-goals

- **No Gas City source changes.** The rebuild composes the runtime as shipped;
  anything needing an upstream change is filed through the existing fork &
  upstream system, not built here.
- **No intake front door.** Architecture names intake as thin and explicitly
  declines to invent one; this effort inherits that restraint.
- **No big-bang cutover.** The operational city keeps running on the current
  pack; the rebuild lands as a staged parallel tree with a phased, reversible
  cutover plan. Decommissioning the old composition is cutover work, not
  rebuild work.
- **No process for its own sake.** No new review leg, consult, or metric
  enters the new pack without the corrective action it triggers being named.
- **No restating upstream.** The spec cites Gas City's canonical docs and
  [gascity-packs.md](../../docs/gascity-packs.md); it does not copy them.

## Constraints

- **Authoring environment.** This branch is authored outside the city's own
  delivery pipeline, so the self-hosting rule ("its steward dispatches, it
  does not hand-edit") is knowingly excepted for the rebuild's bootstrap; the
  exception ends at intake, when the work is re-keyed to a bead and further
  changes ride Delivery.
- **No gastown source at hand.** The authoring environment cannot fetch the
  gastown pack, so no prompt text can be vendored from it. This constraint
  points the same direction as O1: native roles are written fresh, taking
  their opinions from the pack's own fragments and formulas.
- **No runtime to validate against.** There is no `gc` binary or live city in
  the authoring environment. Validation here is documentary — conformance to
  the pack spec and to [gascity-packs.md](../../docs/gascity-packs.md)'s trap
  list — plus review. First-run validation (`gc doctor`, a staging rig) is the
  first cutover step and is specified, not performed, by this effort.

## Definition of done for this branch

1. This outcome document, reviewed and revised.
2. A spec that maps every outcome above to concrete structure — pack layout,
   roster, formulas, conversation wiring, sub-pack boundaries, cutover stages —
   reviewed against the architecture consistency test and the
   [gascity-packs.md](../../docs/gascity-packs.md) trap list.
3. An implementation of the new pack as a staged tree in this repository,
   consistent with the spec, with every capability carrying its
   belief → primitive → composition trace, reviewed and revised.
4. All three phases committed with their review findings addressed, on one
   branch, pushed for human review.

The branch's own review is mode 2 work: it needs a human conversation to move.
What lands beyond it — intake, cutover, decommissioning — is future beads.
