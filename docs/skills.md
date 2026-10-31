---
name: Skills Conventions
description: Use when you write, file or change a gc-toolkit skill, or decide which agents and other consumers see it.
---

# Skills Conventions

A skill is a directory with a `SKILL.md` file — the
[Agent Skills standard](https://agentskills.io/specification). The same file
format has **two consumers**, and a skill that stays disciplined serves both:

- **Gas City** convention-discovers `skills/<name>/` and surfaces each as
  `gc-toolkit.<name>` (see [`install.md`](install.md) and `gc skill list`).
- **Claude, Codex, and other Agent-Skills consumers** read the *same*
  `SKILL.md` — Claude Code via a plugin marketplace, other harnesses directly.

## Scope

**Mandate.** How gc-toolkit authors a skill, where the skill's files live, and
how the skill is exposed to each consumer.

**Boundaries.** This governs the *shape and placement* of skills, not what any
individual skill does — that is its own `SKILL.md` body. It does not restate
the Agent Skills spec ([agentskills.io/specification](https://agentskills.io/specification)
is canonical), and it does not cover prompt fragments, which are a
Gas-City-only prompt-injection surface living in `template-fragments/`.

## The two axes

Every gc-toolkit skill is placed along two independent axes:

- **Portability** — *can it run without Gas City?* Decides whether the skill
  is dual-use (also a native Claude / Codex skill) or Gas-City-only.
- **Visibility** — *which agents see it inside Gas City?* Decides pack-scope
  vs agent-scope. A Gas City concept only.

### Axis 1: Portability

*Mnemonic: portability is purity.* A skill is **portable** if and only if its
body and scripts reach for nothing that only exists inside Gas City. It is
**Gas-City-bound** the moment it depends on any of:

- the `gc` CLI (`gc handoff`, `gc bd`, `gc session`, …);
- Gas City environment (`$GC_TEMPLATE`, `$GC_ALIAS`, `$GC_*`);
- beads, worktrees, or the routing model;
- prompt fragments or any pack-composition artifact.

Example: [`handoff`](../skills/handoff/SKILL.md) branches on `$GC_TEMPLATE`
and drives `gc handoff` — Gas-City-bound, correctly, because it exists to
operate a running city. Portability is a property you preserve by keeping the
runtime out of the skill, not a flag you set.

Declare the axis with the spec's `compatibility` frontmatter field:

```yaml
compatibility: Portable — no Gas City runtime required.
# or
compatibility: Requires Gas City (gc CLI, $GC_* env, beads).
```

### Axis 2: Visibility (Gas City)

- **Pack-scope** — discovered from `skills/<name>/` at the pack root,
  available to every importing agent as `gc-toolkit.<name>`. The default.
- **Agent-scope** — bound to a single agent, surfaced via
  `gc skill list --agent <rig>/gc-toolkit.<agent>`. On a name collision, the
  agent-scoped variant wins.

Use agent-scope when a skill only makes sense for one role and would be noise
in every other agent's list.

> **Open item — confirm the agent-scope path against the loader.** No skill
> is agent-scoped today. The convention this doc adopts is
> `agents/<agent>/skills/<name>/SKILL.md`; verify the loader discovers it
> before relying on it.

**Name a pack skill by its catalog name.** A skill or formula that sends an
agent to another pack skill writes the skill's catalog name,
`gc-toolkit.<name>`, never its path, `skills/<name>/SKILL.md`. The agent's
catalog links each name into the installed pack, the copy of gc-toolkit the
city imports. A path resolves against whatever tree the agent stands in. In
another rig it names nothing, and in a gc-toolkit worktree it opens that
tree's copy, such as a branch under review. A path that names a file to edit
stays a path, as when the feedback distiller names the files its proposals
change.

## Directory layout

```
gc-toolkit/
├── .claude-plugin/
│   └── marketplace.json        # portability contract (not created yet — see below)
├── skills/                     # pack-scope skills (Gas City discovers flat)
│   └── <name>/
│       ├── SKILL.md
│       ├── references/         # on-demand detail (progressive disclosure)
│       ├── scripts/            # portable skills: pure scripts only
│       └── assets/
└── agents/
    └── <agent>/
        └── skills/<name>/      # agent-scope (see Open item above)
```

**Keep pack-scope skills flat in one `skills/` dir.** Do not group into
subdirectories: the spec requires a skill's `name` to equal its immediate
parent directory, and recursive discovery by Gas City's loader is unverified.
Separate the tiers by **frontmatter, not by directory**.

## Frontmatter

```yaml
---
name: <skill-name>              # MUST equal the directory name; lowercase, hyphens
description: <what it is for, when to load it>   # the only trigger
compatibility: <portability statement>           # see Axis 1
---
```

- **`name` equals the directory name.** Lowercase letters, numbers, hyphens.
- **`description` is the trigger, and the only trigger.** It is the
  always-loaded metadata both consumers match against, so it says what the skill
  is for and when to load it, in the words an agent has in mind when it feels
  the need. Put every "when to load this" cue here, not in the body, including
  a neighboring skill to load instead. Skills under-trigger far more often than
  they over-trigger, so a shorter description still has to carry the words a
  real need used.
- **`description` carries only what decides whether to load the skill.** Every
  agent holds it in context in every session, whether or not the skill loads. It
  does not summarize the skill's contents or list its sections, state a rule the
  skill applies, name a finding or verdict the skill produces, or carry a step
  number. Those belong in the body. A list of occasions belongs here when each
  item is something an agent sets out to do ("holding its merge until something
  is settled"), and in the body when each item is a part of the skill ("the two
  binary verdicts"). A skill loaded only by name, such as a converse step from
  its table, needs no more than a short identifier.
- **`compatibility` declares the portability axis** — a recommended local
  convention (the spec treats the field as optional), so the boundary is
  legible without reading the body.
- **Claude Code extension fields** (`disable-model-invocation`,
  `user-invocable`, `allowed-tools`, `context: fork`, `agent:`) are honored by
  Claude and ignored by consumers that don't implement them.

## Composition and exposure

A recurring design wish: *loading skill A makes B and C available, hidden
otherwise.* **Neither runtime offers a first-class "skill unlocks skill"
edge.** Every installed skill's `name` + `description` is always loaded as
startup metadata; the axis you control is *invocation* (Claude) or *agent
scope* (Gas City), not conditional visibility.

- A skill's body **can invoke another skill**, even one with
  `disable-model-invocation: true` — the idiomatic "A leads to B".
- `disable-model-invocation: true` prevents auto-triggering while leaving the
  skill invocable; `user-invocable: false` only hides the `/` menu entry.
- **Progressive disclosure** — helper content as `references/` files inside
  one skill — is the right answer when B and C are *steps of* A: zero
  metadata cost, invisible until A reads them.
- In Gas City, the closest analog to "expose B only alongside A" is
  agent-scoping both to the same agent.

**Rule of thumb.** Parts of A → fold into A as `references/`. Reusable but
default-hidden → separate skills with `disable-model-invocation: true`,
invoked from A's body. True "appears only after A loads" does not exist in
either runtime; do not design as if it did.

## The portability contract

Portable skills are exported to non-Gas-City consumers through a Claude Code
plugin marketplace manifest at `.claude-plugin/marketplace.json`, listing
**only** skills whose `compatibility` declares them portable.

> **Open item — the manifest does not exist yet.** No skill currently declares
> itself portable, so a stub would be an empty list. Create it in the same
> change that exports the first portable skill.

Gas City needs no manifest — it discovers everything in `skills/` by
convention. The manifest is the one-way export gate for the curated,
genuinely-runnable-outside subset: no `gc` CLI, no `$GC_*`, no beads.

## Validation

- `name` matches the directory; frontmatter parses, so an unquoted value holds
  no `: ` or ` #`; `description` is present. `compatibility` is recommended, not
  required.
- Portable skills contain no reference to `gc `, `$GC_`, beads, or fragments
  anywhere in the body or `scripts/`.
- No skill or formula names a pack skill to load by its path.
  `assets/scripts/skill-needs.test.sh` fails on one that does.
- The same suite scores every description against needs agents recorded in their
  own words, and fails when the skill that answers a need does not score highest.
  It also fails a description over its character limit, one with a sentence
  opening on `Covers`, and one that names a step number.
- Every skill in `marketplace.json` declares portable `compatibility`.
  (Vacuous until the manifest exists.)
- Inside Gas City, `gc skill list` shows the skill where expected and
  `gc doctor` reports no unintended `skill-collision`.
