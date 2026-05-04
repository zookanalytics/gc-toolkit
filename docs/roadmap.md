# gc-toolkit roadmap

A living planning document. Primary purpose: **a new conversation about
gc-toolkit can open this file and quickly find where we are and what the
next concrete step is.** Secondary purpose: describe the pack to external
adopters. What's currently true and what's coming; reasons for abandoned
approaches belong in `docs/adr/`, not here.

## Thesis

gc-toolkit takes an idea to implementation with the fewest human steps, and
makes the human steps that do exist high-bandwidth — the human sees what
matters, engages where judgment is needed, and skims the rest.

Every addition to the pack — formula, agent, convention, channel — should
either reduce human steps or make a remaining human step more efficient for
the human. If it does neither, it doesn't belong.

gc-toolkit augments the `gastown` example pack; it does not replace it.
Overrides are welcome where our opinions differ. Forks of gastown itself
belong nowhere.

## What the pack is today

- One agent: `mechanik`, a city-scoped structural engineer for the pack
  itself — owns formulas, agent configs, dispatch patterns, conventions.
- Two reference docs under `docs/`: one describing current Gas City surface
  area, one tracking pack/city v2 direction.
- No formulas yet. No other agents yet.

This roadmap describes what fills out from here.

## Guiding primitives

These are the ideas every addition should be consistent with.

### Branded context channels

Every user-facing surface — agent name, document path, bead type, subject
prefix — must carry a recognizable brand. When the user sees "architect" or
opens `architecture.md`, the brand pre-loads the mental model: they know
the scope, the shape of the conversation, what context to bring.

Branded surfaces are what make engagement high-bandwidth. The user skips
to the actual question fast because the surface itself told them the rest.
General text has no such association and forces re-orientation every time.

**Rule of thumb**: before adding a new surface, state its brand in one
sentence. If you can't, don't add it.

### Three hats (for any specialist agent)

Any agent dedicated to a domain — architect today, others possibly later —
is expected to wear three hats within that domain:

1. **Partner** — reactive. There for you. Answers questions, consults
   when invited, records decisions as they land.
2. **Active** — seeks out. Patrols for drift between what's described and
   what's actually true. Catches domain decisions hiding in non-domain
   conversations and promotes them to durable records. "Nobody asked" is
   not a suitable excuse. Being smart about this is part of the job —
   no spammy drift alerts.
3. **Library** — keeps the data. Knows what artifacts exist, where they
   live, and how to retrieve the relevant ones fast. Extensible via tool
   configuration — a specialist can use purpose-built tools as they prove
   their keep.

Continuous responsibilities (hat 2, hat 3) can only live in a dedicated
agent — a formula-only role can't patrol or maintain an index between
invocations. That's why specialist work in gc-toolkit picks dedicated
agents over formula roles when the three-hat pattern applies.

### Consult beads

Agent-to-human dialogue travels on **consult beads**. One bead per
conversation. The bead holds the back-and-forth until resolved, then
moves forward like any other unit of work.

The metaphor is a Slack conversation: a topic, a thread, a resolution.
Research side-quests spawn sub-beads; the parent goes on hold until the
children return with answers.

Distinct faces — architect consult vs. other specialist consult — come
from metadata and presentation, not from separate bead types.

Consult beads need a discoverability surface so they don't sit silent.
A dedicated city-level `concierge` agent pushes a notification on
consult creation and runs the triage conversation with the overseer
("what's open?", "let's look at the review queue"). When the overseer
commits to resolving a specific consult, concierge spawns a
`consult-host` session for that bead and switches the overseer's tmux
client into it; the host loads the bead in full and converses
directly. Consults are filed as dependencies of the bead whose work
they block, so closing a consult unblocks the parent. See
`docs/design/consult-surfacing.md` (v1 surfacing model) and
`docs/design/consult-session-v2-impl.md` (v2 session-per-consult, as
built).

### Merge-strategy agnosticism

gc-toolkit's opinions apply whether a rig uses `direct`, `mr`, `pr`, or
any future merge strategy. Nothing in the pack should assume a particular
strategy. When a consuming rig picks a strategy, it picks it — gc-toolkit
adapts.

## What we're building

### The architect

A dedicated conversational agent that wears the three hats for a rig's
architecture. First specialist agent the pack will ship.

**Partner**: consults during `mol-idea-to-plan`. Answers architecture
questions on demand. Records decisions as ADRs.

**Active**: watches for drift between `architecture.md` and the actual
code. Catches architectural foundation decisions that get answered as
one-off planning answers and promotes them into ADRs so they're durable.

**Library**: maintains a per-rig `architecture.md` (living) and a
`docs/adr/NNNN-<slug>.md` log (immutable once accepted). Knows what
architectural surface the rig has. Extensible via tool configuration as
specific code-comprehension tools prove themselves.

**First job on any rig**: first-pass ingestion. Read the repo, pull in
whatever architectural signal exists (docs, READMEs, recent commits,
critical code paths), produce a draft `architecture.md` and an initial
ADR set, then come back to the user with a consult: *here's what I
inferred; confirm or correct*. That first consultation is also the first
real test of the engagement model.

### Review legs

"Partner passes" that sit between polecat-done and refinery-handoff.
Each one runs a short formula, produces structured output (approved /
suggested-change-applied / suggested-change-for-human), and only the
third bubbles to the human.

Gastown already ships `mol-review-leg` as a reusable primitive — gc-toolkit
composes specialists on top of it.

Configuration: some legs are pack defaults (available when a rig
imports gc-toolkit); others are opt-in per rig. A rig without UX
concerns shouldn't get a UX review leg.

The word *gate* is deliberately avoided. These are partners engaging in
the work, not walls it has to break through.

### Visual design surfaces

Future. Text is a poor medium for some design questions — "tabs vs
drawer," comparing layouts, evaluating visual tradeoffs. Planning
workflow should eventually be able to produce 2-4 visual candidates per
design question so the human can compare them.

This is not a Phase 1 commitment. It's noted here so the surface gets
invented intentionally when we get to it, rather than bolted on.

## Decisions

### Settled

- **Architect is a dedicated agent**, not a role inside a planning formula.
  Reason: the Active and Library hats require persistence between
  invocations.
- **Engagement travels on consult beads**, one bead per conversation,
  sub-beads for research side-quests. Metadata and presentation give
  distinct faces.
- **Merge-strategy agnostic**: gc-toolkit does not default or force a
  merge strategy. Consuming rigs choose.
- **Review legs, not gates**: the language matters. Passes are partners,
  not walls.
- **Pack is publishable and public**: all artifacts reference only public
  projects. No private rig names appear in pack artifacts.
- **Architect reads from rig-stored artifacts**: everything the architect
  reasons about is stored in the consuming rig. Architect is either
  opinionated about paths or discovers and tracks them (design choice is
  open; both are acceptable). Pack-level architect carries no rig-specific
  knowledge.
- **Consult bead surfacing channel**: a dedicated city-level `concierge`
  agent pushes on creation and runs the triage conversation with the
  overseer; on resolution, it spawns a `consult-host` session for the
  bead and switches the overseer's tmux client into it. Consults are
  filed as dependencies of the parent bead. Details in
  `docs/design/consult-surfacing.md` (v1 surfacing) and
  `docs/design/consult-session-v2-impl.md` (v2 session-per-consult).

### Open

- **Architect: opinionated paths vs. discovery**: the architect either
  expects artifacts at known paths or learns where they live per-rig.
  Both are acceptable; we'll pick one (or allow both) when we build.
- **Review leg configuration shape**: which legs are pack-default vs
  per-rig opt-in, and where that configuration lives, is not yet drawn.
- **Architect tool-configuration interface**: the `[tools]` extensibility
  is noted but not designed. No current OSS codebase-comprehension
  tool is committed to.
- **Planning formula override scope**: `mol-idea-to-plan` will likely
  need extension points for the architect to attach to. Whether that
  means overriding gastown's formula or contributing a pre/post-step
  extension mechanism is open.
- **Sub-bead ergonomics**: the Slack-conversation metaphor works if
  creating, tracking, and resolving sub-beads feels natural. The
  existing bead CLI may or may not meet that bar; we'll learn by use.

## Near-term

The next durable artifacts, in rough order. Not a contract.

1. **First-pass ingestion A/B experiment (before the architect exists).**
   Run two or more polecats on a pilot rig, each using a different
   ingestion strategy, and compare the outputs. This is the pattern the
   Anthropic skill-creator uses to develop new skills
   (https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md).
   The outputs teach us what a good `architecture.md` + initial ADR set
   looks like on a real codebase, which then crystallizes into the
   architect's prompt and formulas. Doing this first (before the agent)
   trades "pure build" for "learn by doing" and is likely faster.
2. `agents/architect/` — agent.toml, prompt template. Three-hat scope.
   Informed by what the A/B experiment taught us.
3. Architect's first formula: `mol-architect-ingest`, crystallizing the
   best of the A/B experiment outputs.
4. Architect's patrol formula (Active hat) for drift and
   question-promotion.
5. Consult-bead surfacing channel — `concierge` agent landed (v1
   model from `docs/design/consult-surfacing.md`); session-per-consult
   v2 (Shape A — direct tmux attach, brand evaporates in-session)
   landed on top, per `docs/design/consult-session-v2-impl.md`.
   Pending build-signals from operating data:
   - second consult-producing specialist (forces the
     `consult-layer.md` pattern past one example);
   - cold-start-latency feel under sustained use (revisit warm pools
     only if the lazy spawn turns out to hurt engagement);
   - re-engagement frequency within minutes vs. hours (revisit the
     fresh-spawn-only default if short-cycle re-engagement becomes
     common).
6. First review-leg specialist: likely a planning/architecture-consistency
   leg that runs when a polecat finishes work against a plan the
   architect helped shape.

## Changelog

Significant roadmap shifts — redirections, abandoned approaches, moved
primitives — belong in `docs/adr/` rather than in this document's
history. The roadmap describes what gc-toolkit currently is and is
becoming; learnings about what we chose *not* to do live alongside
the decisions themselves.
