# Outcome — rethinking gc-toolkit from the ground up

> **Filing note.** `specs/` directories are keyed by bead id, with a topic slug
> as the accommodation for work not yet bead-tracked
> ([file-structure.md](../../docs/file-structure.md)). This work was authored on
> a contribution branch outside the city, so it files under the topic slug
> `2026-08-rethink`; re-key the directory to the tracking bead at intake.

This document is the first gate of a three-phase effort — **outcome → spec →
implementation**, each reviewed before the next begins. It states what a
ground-up rebuild of gc-toolkit must deliver and what it must not attempt. The
spec ([spec.md](spec.md)) makes it concrete; the implementation realizes the
spec. Nothing here restates [foundation.md](../../docs/foundation.md) or
[architecture.md](../../docs/architecture.md) — it traces to them.

## Why rebuild

The pack works, but its composition contradicts its boundaries or falls short
of its own named targets, in ways
[architecture.md](../../docs/architecture.md) already marks as transitional:

1. **The composition boundary.** gc-toolkit imports the gastown example pack
   wholesale and patches six agents by fragment injection
   (`pack.toml`). Foundation says gastown "is an example pack, not an upstream."
   Architecture marks the wholesale import as "transitional… deliberately not
   encoded here as the architecture."
2. **The conversation model.** The shipped host-and-board composition
   (epic `tk-q4xaj`) is superseded by the ratified continuation-group direction
   ([`tk-h9pq5`](../tk-h9pq5/design-doc.md)), which is built entirely from
   primitives Gas City already ships.
3. **The molecule-check interlock** — the loop that makes "automated to
   resolution" first-class — is "mostly unrealized"; most work is still a single
   agent doing a single task.

These are three of the four items architecture names as in transition, and they
interlock: the roster shape comes from gastown, the conversation model routes
around the roster, and the interlock needs both settled. A ground-up
recomposition — built beside the operational pack and cut over in stages —
resolves them together instead of three partial migrations that each inherit
the others' debt. The fourth transitional item, **intake**, stays open: this
effort chooses not to design a front door (architecture calls intake an area
to sharpen but declines to invent one there, and this rebuild makes the same
choice — recorded here as this effort's own scoping decision, not as a
prohibition it inherits).

## Outcomes

Each outcome names the belief or architectural commitment it delivers. These
are the acceptance tests for the whole effort; the spec must show how each is
met, and the implementation must trace every shipped capability to one. Some
outcomes name runtime behavior; since this branch has no runtime (see
Constraints), **the spec must state each outcome's documentary proxy** — the
inspectable structure whose presence Phase-3 review accepts in lieu of runtime
observation.

### O1. A gc-toolkit-native composition — no wholesale upstream import
The new pack imports no example pack as a roster. Roles the pack needs are
authored natively as gc-toolkit's own opinions; anything genuinely reusable
from elsewhere is borrowed piecemeal *with citation*, not inherited by import.
The spec must enumerate **every capability the gastown import currently
supplies beyond the six patched agents** — the dog pool, the base tmux
theming, and anything else an audit of `pack.toml` and `[global]` surfaces —
and assign each to native authorship, deliberate drop (with rationale), or a
named cutover step. Where the current pack splits opt-in capability into
sub-packs (`packs/gascity-keeper/`), the new composition keeps that boundary
pattern: rig-specific capability ships as an opt-in sub-pack, never in the
core. *(foundation: The pack borrows before it invents — and its Boundaries;
architecture: the composition boundary transition.)*

### O2. Conversation grounded on continuation groups
The conversation system is the [`tk-h9pq5`](../tk-h9pq5/design-doc.md)
direction realized: the subject bead's id is the conversation's identity,
turns are routed child beads carrying `gc.run_target = <conversation-role>`
and `gc.continuation_group = <subject-bead-id>`, warm sessions receive
follow-on turns through the continuation-group claim path, cold sessions
reconstitute from the subject bead's record. No resident host object, no
reverse links. Per that design, the `gc.attention` board / Helm picker is
**kept as the human-facing surface and rewired** — pick-a-row files-or-attaches
a turn instead of resuming a host. *(foundation: Human attention is the
budget; architecture: how agents exist and converse.)*

### O3. A delivery spine on bare primitives
Delivery composes beads (open until landed), checks (head-pinned, re-opened by
any new commit), and routing (worker claims; single-writer lands when green),
with the lifecycle owned by
[work-bead-state-machine.md](../../docs/work-bead-state-machine.md). The pack
stays landing-strategy-neutral except where a check must hold: agent-initiated
code is pinned to the gated path. *(foundation: Human attention is the budget —
the only human step is a check that needs a human; checks themselves: Agents
make their edges visible; architecture: Delivery, "How a bead finally lands.")*

### O4. The molecule-check interlock designed in, not retrofitted
Every new-work formula either **implements** step-signs-off-check — a step
that satisfies a gate stamps that gate's marker — or **carries a recorded
note** identifying which step will sign off which check when the interlock
lands. A formula with neither is a review-blocking defect. The rebuild does
not claim to complete the interlock (checks that run themselves remain a
target); it commits to never shipping a formula whose shape forecloses it.
*(architecture: the molecule-check interlock.)*

### O5. Lessons carried forward, never re-learned
Every doctrine **recorded in this repository** that the current pack earned
from a real failure — each `template-fragments/` entry, each overlay, each
`doctor/` check, each standing order, and the fix-doctrines encoded in the
formulas — has an explicit home in the new composition or an explicit,
recorded reason it is no longer needed. **The spec must carry the census**: an
enumerated inventory mapping each carried doctrine to its new home or its
retirement rationale, against which Phase-3 review checks. Doctrine the pack
currently inherits from gastown's base prompts cannot be enumerated in this
environment (see Constraints) and is deferred to first-run validation at
cutover. Silent loss of a censused doctrine is a review-blocking defect.
*(foundation: Agents improve; the no-cheap-restart boundary.)*

### O6. The doc spine is phase zero
The rebuild files its own decisions the way the pack files everything: work
records under `specs/`, per
[file-structure.md](../../docs/file-structure.md). On this branch, central
`docs/` receive at most transition markers of the kind architecture.md already
uses ("what is still in transition") — the in-place rewrite of central docs to
speak the new composition's truth is a **named cutover stage**, verified at
cutover, because until then the operational city still runs the old
composition and central docs must stay true to it. This effort produces no
parallel doc tree. *(foundation: Decisions have a home; goal G3.)*

### O7. A minimal resident roster, earned by the three-hats test
Every resident (named-session) agent in the new pack passes the test in
architecture.md: partner + active patrol + library, all three, or it is not a
resident. The default roster size is zero residents; each one is an argued
exception, and the keeper agent in the `gascity-keeper` sub-pack is argued
like any other. Patrol *procedures* are molecules; **where patrol continuity
lives** — resident loops that re-pour themselves versus self-pouring chains on
routed disposable sessions — is a decision the spec must settle explicitly and
on the record, because architecture currently carries both readings
("resident patrol loops" under Engine health; "nothing continuous can live in
a role that exists only between claim and drain" under three-hats).
*(architecture: "A domain earns a standing agent by needing all three hats.")*

### O8. Every surface branded
Each role name, bead type, doc path, and turn subject the new pack introduces
states its brand in one sentence at the point it is defined, or the surface is
not added. *(architecture: "Every surface a conversation presents is
branded.")*

### O9. The standing systems still stand
The rebuild re-grounds, and does not silently drop, the standing compositions
that keep the pack running unbabysat and its record true:
- **Engine health** — patrol/recycle continuity re-composed on the native
  roster (per the O7 decision), the cycle-recycle mechanism carried, and the
  anti-regression `doctor/` suite carried forward as the standing guard, so a
  lesson locked in once stays locked in.
- **Doc & knowledge cohesion** — the drift and memory audits ship in the new
  composition as routed molecules, unchanged in intent.
- **Fork & upstream** — inherited through the `gascity-keeper` sub-pack, whose
  contents are recomposed only where an outcome above requires it; its
  fork-specific opinions are not core-pack material.
*(foundation: Agents improve; Decisions have a home; architecture: Engine
health, Doc & knowledge cohesion, Fork & upstream.)*

## Non-goals

- **No Gas City source changes.** The rebuild composes the runtime as shipped;
  anything needing an upstream change is filed through the existing fork &
  upstream system, not built here.
- **No intake front door.** Named as this effort's own scoping choice in "Why
  rebuild"; intake remains an open area, untouched.
- **No big-bang cutover.** The operational city keeps running on the current
  pack; the rebuild lands as a staged parallel tree with a phased, reversible
  cutover plan. **The staged tree must live where the current pack does not
  load** — outside the well-known load-bearing directories (`formulas/`,
  `agents/`, `template-fragments/`, root `pack.toml`), following the existing
  opt-in sub-pack convention (`packs/<name>/`) — and must introduce **no
  artifact basename that shadows, and no agent name that collides with**, the
  live pack or its imports
  ([gascity-packs.md](../../docs/gascity-packs.md) §7). The spec names the
  location and the new pack's name. Decommissioning the old composition is
  cutover work, not rebuild work.
- **No process for its own sake.** No new review leg or consult enters the new
  pack without its judgment-bearing purpose named, and no metric without the
  corrective action it triggers.
- **No restating upstream.** The spec cites Gas City's canonical docs and
  [gascity-packs.md](../../docs/gascity-packs.md); it does not copy them.

## Constraints

- **Authoring environment.** This branch is authored outside the city's own
  delivery pipeline, so the self-hosting rule ("its steward dispatches, it
  does not hand-edit") is knowingly excepted for the rebuild's bootstrap; the
  exception ends at intake, when the work is re-keyed to a bead and further
  changes ride Delivery.
- **No gastown source at hand.** The authoring environment cannot fetch the
  gastown pack, so no prompt text can be vendored from it — and, as a review
  criterion, native prompts must be **written fresh from this pack's own
  fragments, formulas, and docs**, not reconstructed from memory of gastown's.
  This constraint points the same direction as O1.
- **No runtime to validate against.** There is no `gc` binary or live city in
  the authoring environment. Validation here is documentary — conformance to
  the pack spec and to [gascity-packs.md](../../docs/gascity-packs.md)'s trap
  list — plus review, against each outcome's documentary proxy. First-run
  validation (`gc doctor`, a staging rig) is the first cutover step and is
  specified, not performed, by this effort.

## Definition of done for this branch

1. This outcome document, reviewed and revised.
2. A spec that maps every outcome above to concrete structure — pack name and
   staging location, layout, roster, formulas, conversation wiring, sub-pack
   boundaries, the O5 doctrine census, each outcome's documentary proxy, and
   cutover stages — reviewed against the architecture consistency test and the
   [gascity-packs.md](../../docs/gascity-packs.md) trap list.
3. An implementation of the new pack as the staged tree the spec names,
   consistent with the spec, with every capability carrying its
   belief → primitive → composition trace, reviewed and revised.
4. All three phases committed with their review findings addressed, on one
   branch, pushed for human review.

The branch's own review is mode 2 work (needs conversation to move —
architecture.md, "How work moves"). What lands beyond it — intake, cutover,
decommissioning — is future beads.
