---
name: Skills Conventions
description: How gc-toolkit authors, files, and exposes skills so the same SKILL.md serves Gas City and, where it stays portable, Claude / Codex / other Agent-Skills consumers. Covers the portability and visibility axes, directory layout, frontmatter, and what skill-to-skill composition is and is not possible.
---

# Skills Conventions

A skill is a directory with a `SKILL.md` file — the
[Agent Skills standard](https://agentskills.io/specification). gc-toolkit
ships skills for one reason above all: the same file format has **two
consumers**, and a skill that stays disciplined serves both.

- **Gas City** convention-discovers `skills/<name>/` and surfaces each as
  `gc-toolkit.<name>` (see [`install.md`](install.md) and `gc skill list`).
- **Claude, Codex, and other Agent-Skills consumers** read the *same*
  `SKILL.md`. Claude Code installs them via a plugin marketplace; the
  agentskills.io standard lets other harnesses read the directories
  directly.

One format, two consumers. The whole of this doc follows from that.

## Scope

**Mandate.** How gc-toolkit authors a skill, where the skill's files
live, and how the skill is exposed to each consumer — the rules that keep
one `SKILL.md` serving both runtimes.

**Boundaries.** This governs the *shape and placement* of skills, not
what any individual skill *does* — that is the skill's own `SKILL.md`
body. It does not restate the Agent Skills spec (the canonical reference
is [agentskills.io/specification](https://agentskills.io/specification);
a surveyed copy lives in [`../specs/tk-1k0fay/anthropic-skills.md`](../specs/tk-1k0fay/anthropic-skills.md)),
and it does not cover prompt fragments, which are a Gas-City-only prompt-
injection surface, not skills — those live in `template-fragments/`.

## Use Cases

| Query | Convention it implies |
|---|---|
| "Where does a new skill go?" | `skills/<name>/SKILL.md`, flat. Agent-only skills go under the agent. |
| "Can this skill run outside Gas City?" | The [portability axis](#axis-1-portability): portable if it touches no Gas City runtime. |
| "Which agents can see this skill?" | The [visibility axis](#axis-2-visibility-gas-city): pack-scope (every importer) vs agent-scope (one agent). |
| "How do I expose a core skill to Claude / Codex?" | Keep it portable; list it in the [marketplace manifest](#the-portability-contract). |
| "Can loading skill A reveal skills B and C?" | No first-class gating exists; see [Composition and exposure](#composition-and-exposure). |

## The two axes

Every gc-toolkit skill is placed along two independent axes. Keep them
separate in your head — conflating them is the usual source of confusion.

- **Portability** — *can it run without Gas City?* Decides whether the
  skill is dual-use (also a native Claude / Codex skill) or Gas-City-only.
- **Visibility** — *which agents see it inside Gas City?* Decides pack-scope
  vs agent-scope. This axis is a Gas City concept; it does not exist for the
  portable consumers.

A skill is `(portable | gascity-bound) × (pack-scope | agent-scope)`. Most
core primitives are `portable × pack-scope`; most operational skills are
`gascity-bound`, at whichever scope fits.

### Axis 1: Portability

*Mnemonic: portability is purity.* A skill is **portable** if and only if
its body and scripts reach for nothing that only exists inside Gas City.

A skill is **Gas-City-bound** the moment it depends on any of:

- the `gc` CLI (`gc handoff`, `gc mail`, `gc bd`, `gc session`, …);
- Gas City environment (`$GC_TEMPLATE`, `$GC_ALIAS`, `$GC_*`);
- beads, mail, worktrees, or the routing model;
- prompt fragments or any pack-composition artifact.

The two skills shipping today are both Gas-City-bound by this test:
[`handoff`](../skills/handoff/SKILL.md) branches on `$GC_TEMPLATE` and
drives `gc handoff`; `session-title` reads and writes session state
through `gc`. Neither is portable, and that is correct — they exist to
operate a running city.

A **portable** skill (a "core primitive") is the dual-use case the
foundation calls for: authored once, discoverable in Gas City *and*
loadable natively by Claude / Codex. Portability is a property you
preserve by keeping the Gas City runtime out of the skill, not a flag you
set.

Declare the axis with the spec's own `compatibility` frontmatter field so
both consumers — and the next author — can read it:

```yaml
# portable core primitive
compatibility: Portable — no Gas City runtime required.
```
```yaml
# Gas-City-bound skill
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
```

### Axis 2: Visibility (Gas City)

Inside Gas City, a skill is exposed at one of two scopes:

- **Pack-scope** — discovered from `skills/<name>/` at the pack root.
  Available to every agent that imports gc-toolkit, qualified as
  `gc-toolkit.<name>`. This is the default.
- **Agent-scope** — bound to a single agent, surfaced via
  `gc skill list --agent <rig>/gc-toolkit.<agent>`. On a name collision
  with a pack-scope skill, **the agent-scoped variant wins** (see the
  `skill-collision` doctor note in [`install.md`](install.md)).

Use agent-scope when a skill only makes sense for one role — a polecat-only
or mechanik-only workflow — and would be noise in every other agent's skill
list.

> **Open item — confirm the agent-scope path against the loader.** No
> skill is agent-scoped today, and `gascity-agents.md` does not document
> the on-disk location. The convention this doc adopts is
> `agents/<agent>/skills/<name>/SKILL.md`; verify the loader actually
> discovers that path before relying on it, and update this line to a flat
> statement once confirmed.

## Directory layout

```
gc-toolkit/
├── .claude-plugin/
│   └── marketplace.json        # portability contract: lists the portable skills
├── skills/                     # pack-scope skills (Gas City discovers flat)
│   ├── <portable-core>/        # compatibility: portable → also native in Claude/Codex
│   │   ├── SKILL.md
│   │   ├── references/         # on-demand detail (progressive disclosure)
│   │   ├── scripts/            # pure scripts only — no gc, no $GC_*
│   │   └── assets/
│   └── <gascity-bound>/        # compatibility: requires Gas City
│       └── SKILL.md
└── agents/
    └── <agent>/
        └── skills/<name>/      # agent-scope skills (see Open item above)
            └── SKILL.md
```

**Keep pack-scope skills flat in one `skills/` dir.** Do not group them
into `skills/core/` vs `skills/gascity/` subdirectories. Two reasons: the
spec requires a skill's `name` to equal its *immediate parent directory*,
and whether Gas City's loader discovers skills recursively is unverified.
Separate the tiers by **frontmatter, not by directory** — `compatibility`
carries portability; the marketplace manifest carries the curated export
set. One discovery surface, zero duplication.

## Frontmatter

Skills follow the Agent Skills spec, plus two conventions this repo holds:

```yaml
---
name: <skill-name>              # MUST equal the directory name; lowercase, hyphens
description: <what it does AND when to use it>   # the trigger — keyword-rich
compatibility: <portability statement>           # see Axis 1
---
```

- **`name` equals the directory name.** Lowercase letters, numbers, and
  hyphens; no leading/trailing or consecutive hyphens.
- **`description` is the trigger, and the only trigger.** It is the always-
  loaded metadata both consumers match against; put every "when to use
  this" cue here, not in the body. Be specific and a little pushy — skills
  under-trigger far more often than they over-trigger.
- **`compatibility` declares the portability axis.** Required on every
  gc-toolkit skill so the boundary is legible without reading the body.
- **Claude Code extension fields** (`disable-model-invocation`,
  `user-invocable`, `allowed-tools`, `context: fork`, `agent:`) are
  honored by Claude and ignored by consumers that don't implement them.
  Use them where they help; see [Composition and exposure](#composition-and-exposure).

## Composition and exposure

A recurring design wish: *loading skill XYZ makes XYA and XYB available,
and XYA/XYB stay hidden otherwise.* **Neither runtime offers a first-class
"skill unlocks skill" dependency edge.** Plan around the mechanisms that do
exist.

**Why hiding is hard.** Every installed skill's `name` + `description` is
always loaded as startup metadata (~100 tokens each). There is no native
way to keep a skill out of that always-loaded set until a sibling
activates — in Claude or in Gas City. The axis you actually control is
*invocation* (Claude) or *agent scope* (Gas City), not conditional
visibility.

**In Claude / Claude Code:**

- A skill's body **can invoke another skill** (the Skill tool) — and this
  works even when the target sets `disable-model-invocation: true`. This is
  the idiomatic "A leads to B."
- `disable-model-invocation: true` keeps a skill from auto-triggering while
  leaving it invocable by another skill or the user. Closest thing to "only
  reached when XYZ calls it" — but the name still sits in metadata.
- `user-invocable: false` only hides a skill from the `/` menu; the model
  can still auto-trigger it. It does not gate.
- **Progressive disclosure** — keeping the helper content as `references/`
  files inside *one* skill — is the right answer when XYA/XYB are *steps of*
  XYZ rather than independently-triggerable tasks. They cost zero metadata
  and are invisible until XYZ reads them.
- A single composite skill (one `SKILL.md`, branching body) gives true
  gating at the cost of modularity.

**In Gas City:** the scoping axis is the *agent*, not the skill. The
closest analog to "expose B only alongside A" is to agent-scope both to the
same agent so they never appear in other agents' lists.

**The rule of thumb.** If B and C are *part of* A → fold them into A as
`references/`. If they are *reusable but should default-hide* → separate
skills with `disable-model-invocation: true`, invoked from A's body
(Claude) and agent-scoped to A's owner (Gas City). True "appears only after
A loads" is not available in either runtime; do not design as if it were.

## The portability contract

Portable skills are exported to non-Gas-City consumers through a Claude
Code plugin marketplace manifest at `.claude-plugin/marketplace.json`. The
manifest lists **only** the skills whose `compatibility` declares them
portable; Gas-City-bound and agent-scoped skills are never listed there.

This is the one-way export gate: Gas City discovers everything in
`skills/` by convention and needs no manifest; the manifest exists solely
to give Claude Code (`/plugin marketplace add zookanalytics/gc-toolkit`)
and other Agent-Skills harnesses a curated, runnable subset. The skill
directory is shared by both consumers — the manifest, not a second copy,
is what distinguishes them.

A skill earns a place in the manifest only when it is genuinely portable:
it runs to completion with no `gc` CLI, no `$GC_*`, and no beads. If
exporting a skill would require those, it is Gas-City-bound by definition
and stays out of the manifest.

## Validation

- `name` matches the directory; frontmatter parses; `description` and
  `compatibility` are present.
- Portable skills contain no reference to `gc `, `$GC_`, beads, mail, or
  fragments anywhere in the body or `scripts/`.
- Every skill in `marketplace.json` declares portable `compatibility`, and
  no Gas-City-bound or agent-scoped skill appears in it.
- Inside Gas City, `gc skill list` (and `gc skill list --agent <name>` for
  agent-scope) shows the skill where expected; `gc doctor` reports no
  `skill-collision` you did not intend.
