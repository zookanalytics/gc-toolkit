---
name: Personas mechanics findings — skill load paths, subagent loading, scoping, assume-persona
description: Findings write-up for tk-ohrlc — the four deferred "Mechanics" questions behind docs/personas.md, answered against CURRENT Claude Code docs (verified 2026-06-14) with per-answer provenance. Settles where skill files load from, how a subagent consumes a skill, how to scope process-skills to a persona without bloating plain workers, and the assume-persona entry point. Findings only — folds into docs/personas.md "Mechanics" section later, after operator discussion.
---

# Personas — Mechanics findings (tk-ohrlc)

This is the **findings write-up** for the four deferred "Mechanics" questions that
`docs/personas.md` left as a TBD stub. It is **not** a
doc edit — per the dispatch note (epic `tk-ae96t`, 2026-06-14) the
deliverable is investigation results that return to the epic host for operator
discussion. Settled mechanics get folded into `docs/personas.md` later, after that
discussion and the first persona implementation.

Everything below is grounded in the **current** Claude Code documentation, fetched
and cross-checked on **2026-06-14** (the area changes fast, so training memory was
not trusted). Load-bearing claims were re-verified against the primary doc pages,
not just secondary summaries.

## Provenance

| Source | URL | Used for | Verified |
|---|---|---|---|
| Skills (Claude Code docs) | https://code.claude.com/docs/en/skills | Q1 load paths/discovery; Q3 scoping/visibility; Q4 invocation | 2026-06-14 (page fetched in full) |
| Subagents (Claude Code docs) | https://code.claude.com/docs/en/sub-agents | Q2 subagent skill loading; Q4 `--agent`/`initialPrompt` | 2026-06-14 (page fetched in full) |
| Plugins reference | https://code.claude.com/docs/en/plugins-reference | Q1/Q3 plugin skill packaging + namespacing | 2026-06-14 (via research agent) |
| Settings | https://code.claude.com/docs/en/settings | Q3 `skillOverrides`, `skillListingBudgetFraction`, `maxSkillDescriptionChars` | 2026-06-14 |
| Agent SDK — Skills | https://code.claude.com/docs/en/agent-sdk/skills | Q4 SDK angle (supplementary) | 2026-06-14 (via research agent — flagged less central) |
| Agent Skills open standard | https://agentskills.io | Q1 cross-tool standard `SKILL.md` follows | 2026-06-14 (referenced by skills doc) |

> **URL note.** The skills page cross-links subagents as `/en/sub-agents`
> (hyphenated); the page also resolves at `/en/subagents`. Both forms work; this
> write-up cites the hyphenated form the docs themselves use.

> **Method note.** Four focused `claude-code-guide` agents (live WebFetch/WebSearch)
> produced the first-pass answers; the maintainer then re-fetched `skills` and
> `sub-agents` directly to lock down the load-bearing claims (the subagent `skills:`
> field, flat-vs-nested discovery, the invocation/visibility table, and the
> `disable-model-invocation` ↔ preload interaction). Where the two disagreed, the
> primary-source page wins and the correction is called out inline.

---

## Q1 — Where skill files actually load from (flat vs. nested discovery)

**A skill is a directory, not a flat file.** Each skill is `<skill-name>/SKILL.md`
(a directory whose required entrypoint is `SKILL.md`); the directory may also hold
supporting files (scripts, references, templates) that load only when referenced.

**Locations and precedence** ([skills §Where skills live](https://code.claude.com/docs/en/skills)):

| Scope | Path | Visible in |
|---|---|---|
| Managed/enterprise | managed-settings location | all users on the machine |
| Personal | `~/.claude/skills/<name>/SKILL.md` | all your projects |
| Project | `.claude/skills/<name>/SKILL.md` | this project only |
| Plugin | `<plugin>/skills/<name>/SKILL.md` | where the plugin is enabled |

> Collision rule, quoted: *"When skills share the same name across levels,
> enterprise overrides personal, and personal overrides project. Plugin skills use a
> `plugin-name:skill-name` namespace, so they cannot conflict with other levels."*
> Note the counter-intuitive bit: **personal overrides project**. A skill also
> beats a same-named `.claude/commands/` command.

**Flat WITHIN a `.claude/skills/`, but discovery spans MANY `.claude/skills/`
directories.** This is the precise answer to the flat-vs-nested question, and it is
the crux for the persona design:

- Inside a single `skills/` directory, discovery is **one level deep**:
  `skills/<name>/SKILL.md`. You **cannot** group as
  `skills/<persona>/<process>/SKILL.md` and have the inner skill discovered.
- But Claude Code discovers skills across **multiple** `.claude/skills/` directories
  ([skills §Automatic discovery from parent and nested directories](https://code.claude.com/docs/en/skills)),
  quoted: *"Project skills load from `.claude/skills/` in your starting directory and
  in every parent directory up to the repository root… When you work with files in
  subdirectories below your starting directory, Claude Code also discovers skills
  from nested `.claude/skills/` directories on demand. For example, if you're editing
  a file in `packages/frontend/`, Claude Code also looks for skills in
  `packages/frontend/.claude/skills/`. This supports monorepo setups…"*
- `.claude/skills/` inside an `--add-dir`/`/add-dir` directory is also loaded
  (an explicit exception — `permissions.additionalDirectories` does **not** load skills).
- A skill folder can become a one-folder plugin by adding `.claude-plugin/plugin.json`
  — it then loads as `<name>@skills-dir` and can bundle agents/hooks/MCP.

**SKILL.md frontmatter** (current field set, [skills §frontmatter reference](https://code.claude.com/docs/en/skills)):
`name` (display only; the **directory name** is what you type to invoke),
`description` (drives auto-selection; combined `description`+`when_to_use` capped at
1,536 chars), `argument-hint`, `arguments`, `disable-model-invocation`,
`user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort`,
`context` (`fork`), `agent` (subagent type when `context: fork`), `paths` (globs
that gate auto-activation). Bundled scripts resolve via `${CLAUDE_SKILL_DIR}`.

**Cost model:** in a regular session, **descriptions are always in context** so
Claude knows what exists; **the body loads only on invocation** and then persists for
the rest of the session (re-attached on compaction within a shared budget). This
matters for Q3.

**Persona implication.** "A persona owns several process-skills grouped together"
cannot be expressed as nested skill dirs under one `.claude/skills/`. The three real
ways to express the grouping:
1. **Flat naming convention** — `architect`, `architect-review`, `architect-adr`
   under one `.claude/skills/`. Simple; no isolation (see Q3).
2. **A plugin per persona** — `persona-architect/skills/{identity,review,adr}/SKILL.md`,
   invoked `/persona-architect:review`. Gives grouping **and** namespacing **and**
   on/off gating (see Q3). Cleanest for "ride with the persona."
3. **Package-scoped `.claude/skills/`** — only helps if personas map to monorepo
   subtrees; not a natural fit for role-based personas. Noted for completeness.

---

## Q2 — How a subagent consumes / loads a skill

**Subagents are `.claude/agents/<name>.md`** (also `~/.claude/agents/`, managed, and
plugin scopes). Unlike skills, **agent files are discovered recursively** — subfolders
like `agents/review/` are fine; identity comes only from the `name` frontmatter field,
and duplicate names within a scope are silently de-duplicated
([sub-agents](https://code.claude.com/docs/en/sub-agents)).

**A subagent runs in its own fresh context window.** Its system prompt is the agent
file's markdown body only (plus minimal env like cwd) — *"Subagents receive only this
system prompt … not the full Claude Code system prompt."* It does **not** inherit the
parent's conversation history or the skills the parent already invoked. So skills do
**not** leak parent→child.

**Two distinct ways a subagent gets a skill — this is the key finding:**

1. **Preload at startup via the `skills:` frontmatter field**
   ([sub-agents §Preload skills into subagents](https://code.claude.com/docs/en/sub-agents#preload-skills-into-subagents)),
   quoted: *"Skills to preload into the subagent's context at startup. The full skill
   content is injected, not just the description. Subagents can still invoke unlisted
   project, user, and plugin skills through the Skill tool."*
   ```yaml
   ---
   name: api-implementer
   description: Implement API endpoints
   skills:
     - api-conventions
     - error-handling-patterns
   ---
   Implement API endpoints. Follow the conventions from the preloaded skills.
   ```
   The full SKILL.md **body** (not just the description) lands in the subagent's
   context at spawn. **This is the primitive that makes "process-skills ride with the
   persona" real.**

2. **Invoke on demand via the Skill tool.** A subagent can discover and invoke any
   project/user/plugin skill at runtime — *unless* `Skill` is omitted from its `tools`
   allowlist or listed in `disallowedTools`. Per the docs, to preload you use the
   `skills` field **rather than** listing `Skill` in `tools`; to forbid skill use
   entirely, omit/deny `Skill`.

**Important interaction (verified, and an easy trap):** *"You cannot preload skills
that set `disable-model-invocation: true`, since preloading draws from the same set of
skills Claude can invoke."* So the field that hides a skill from plain-worker context
(Q3) **also** makes it ineligible for `skills:` preload. The two levers are mutually
exclusive on the same skill — see Q3 for the consequence.

**Inverse mechanism for completeness:** a *skill* with `context: fork` (+ `agent:`)
runs **its own content as the task** inside a forked subagent
([skills §Run skills in a subagent](https://code.claude.com/docs/en/skills)). That is
the opposite direction from `skills:` preload: `context: fork` pushes a skill *into* a
chosen agent; `skills:` pulls skills *into* an agent you defined. The docs note both
use the same underlying system.

**Persona implication.** A persona realized as a **subagent** can carry exactly its
process-skills via `skills:` — they enter the persona's isolated context and never
touch a plain worker's context. A persona realized as a **plain in-session skill load**
(Q4) does not get this isolation; its process-skills are governed by normal in-context
discovery (Q3).

---

## Q3 — Scoping process-skills to a persona (without bloating plain workers)

**The bloat is real and the docs confirm the mechanism.** Every project/personal skill
in scope has its **description injected into every session's context** so Claude can
choose it; only the body is lazy. Descriptions share a **skill-listing budget**
(tunable via `skillListingBudgetFraction` / `SLASH_COMMAND_TOOL_CHAR_BUDGET`; each
entry capped 1,536 chars, tunable via `maxSkillDescriptionChars`). There is **no
native per-agent *visibility* scoping** of project/personal skills — a plain polecat
sees them all. So curation must come from one of these four levers:

| Lever | What it does | Keeps it out of plain workers? | Catch |
|---|---|---|---|
| **`disable-model-invocation: true`** (skill frontmatter) | *"removes the skill from Claude's context entirely"* — description gone, body loads only on explicit `/name` | **Yes** (description not in context) | **Not auto-invocable and not `skills:`-preloadable.** Must be invoked by name. |
| **`skillOverrides`** (settings, `.claude/settings.local.json`) | per-skill `on` / `name-only` / `user-invocable-only` / `off`; the `/skills` menu writes it | Yes (`name-only` trims, `off` hides) | Local settings, not committed-with-the-skill; **does not affect plugin skills**. |
| **Plugin, disabled by default** | a disabled plugin's skills cost **zero** context; enable per-persona | **Yes** until enabled | Enable is **session-wide / all-or-nothing**; enabled plugin skills are globally visible and **not** affected by `skillOverrides`. |
| **Subagent `skills:` preload** (Q2) | process-skills enter the **persona-subagent's** isolated context only | **Yes** (never in main/plain context) | Persona must be a subagent; preloaded skill cannot be `disable-model-invocation`. |

**Capability vs. visibility — do not conflate (a likely operator trap).**
`allowed-tools` on a skill scopes **what the skill may do** (pre-approves tools while
active); it does **not** scope **who sees** the skill. Visibility is governed by
`disable-model-invocation` / `user-invocable` / `skillOverrides`, not `allowed-tools`.
(`user-invocable: false` only hides from the `/` menu — the description stays in
context and the Skill tool can still invoke it.)

**The central tension for the persona model.** The epic's rule is *"a persona's
process-skills ride with the persona; a plain polecat stays minimal."* The docs give
two clean ways to honor it, and they pull in opposite directions on one field:

- **Path A — Persona = subagent, process-skills preloaded.** Keep process-skills as
  normal (model-invocable) project skills and `skills:`-preload them into the
  persona-subagent. Isolation is automatic for the *persona's* context. **But** because
  they remain normal project skills, their descriptions still sit in every plain
  worker's context — so pair this with `skillOverrides: name-only|off` (local settings)
  to suppress them from plain workers. Slightly clunky (settings-side, not
  committed-with-skill), but fully documented.
- **Path B — Persona + process-skills as a disabled-by-default plugin.** Grouping +
  namespacing + zero-cost-when-disabled, all in one unit; enable for the persona
  context. **But** enabling is session-wide (no per-agent gate) and plugin skills
  ignore `skillOverrides`. A persona-subagent shipped in the same plugin can preload
  the plugin's skills.
- **Path C — `disable-model-invocation: true` on every process-skill.** Out of
  everyone's context; invoked only by explicit `/name`. **But** then they are **not**
  `skills:`-preloadable and **not** auto-selectable, so the persona's identity skill
  must explicitly tell the agent to `/invoke` each process-skill at the right moment.
  Maximum thrift, most manual.

These are genuine trade-offs, which is why the epic routed them back for discussion.
A reasonable default to put in front of the operator: **Path A** when personas are run
as subagents inside Gas City (matches the existing agent model and the `skills:`
primitive), falling back to **Path B (plugin)** if/when personas need to be distributed
across rigs or toggled as a unit. Recommendation only — not a decision.

**Local prior art worth flagging.** This rig already hit a sharp edge here:
agent-local skills are SourceDir-keyed, and the gc-toolkit importer overlay can
manufacture a colliding *phantom* agent (a compose error) when trying to scope a skill
to an imported agent (memory: *skill-scoping-imported-agents*). That is a Gas City
import-layer concern, **not** a documented Claude Code feature — so per-agent skill
scoping via the importer should be treated as unsupported/fragile, and the Path A/B/C
options above (native frontmatter + plugins) are the load-bearing mechanisms.

---

## Q4 — The assume-persona entry point (load a persona-skill in plain claude)

**In-session, two documented ways to load a skill**, both of which load the same
SKILL.md body and **persist for the rest of the session**:
1. **User invokes `/skill-name`** (the directory name is the command).
2. **Claude auto-selects** on `description` match — unless the skill is
   `disable-model-invocation: true`.

So the lightweight "assume persona X" in a plain session is simply **invoke
`/persona-x`** (the persona's identity skill); its body — the always-on identity — then
rides the rest of the session.

**There is no bare `claude --skill X` flag** to boot a fresh session already wearing a
skill. But there **is** a documented "boot-as-an-identity" path, which the first-pass
research under-reported:

- **`--agent <name>` / the `agent` setting** runs a **subagent as the main session**.
  That agent definition can:
  - **`skills:`-preload** the persona's process-skills (Q2), and
  - carry an **`initialPrompt`** — quoted: *"Auto-submitted as the first user turn when
    this agent runs as the main session agent (via `--agent` or the `agent` setting).
    Commands and skills are processed. Prepended to any user-provided prompt."*
    So `initialPrompt` can `/invoke` the persona identity skill (or seed the first
    task) at boot.

That combination — an agent definition whose body is (or loads) the persona identity,
whose `skills:` preloads the persona's processes, and whose `initialPrompt` kicks the
first turn — **is** the cleanest documented "assume-persona at startup" for Claude Code,
routed through an *agent* rather than a bare skill flag. It dovetails with Gas City's
existing agent model.

**Other surfaces (documented, lesser fits):**
- **Headless `claude -p`:** include `/skill-name` in the prompt string to trigger it;
  `--append-system-prompt` appends **raw text**, not a skill (bypasses the skill
  machinery — usable to hardcode identity, but you lose skill packaging/versioning).
- **Agent SDK (supplementary, from the SDK skills page):** skills are
  filesystem-discovered; `setting_sources` must include `user`/`project`; a `skills`
  option selects which are available; invocation is model-driven — no programmatic
  "force this skill at startup." Flagged as SDK-doc-sourced and less central to the
  Gas City use case.

**Persona implication.** Two entry points, pick per situation:
- **Switch within a live plain session** → `/invoke` the persona identity skill.
- **Spawn an agent that *is* the persona** → an `.claude/agents/` definition (or the
  `--agent` boot path) with `skills:` preloads + `initialPrompt`. This is the natural
  home for the epic's "an AGENT = a persona instantiated as a standing/addressable
  instance."

---

## Synthesis — how the four answers wire into the persona model

`docs/personas.md` asserts: *a persona IS a skill; a persona = tight always-on
IDENTITY + advisory OWNS + PROCESSES (each a skill); identity is portable; an AGENT =
a persona instantiated as a standing instance; curate skills per consumer, NOT global.*
The mechanics land as:

- **"A persona is a skill" → yes, mechanically.** The identity is one `SKILL.md`;
  `/invoke` it to wear it; it persists for the session. ✔
- **"Processes are skills that ride with the persona" → use the subagent `skills:`
  preload (Path A) or a per-persona plugin (Path B).** Native per-agent *visibility*
  scoping of plain project skills does **not** exist, so "ride with the persona, not
  global" is achieved by preload-into-the-persona-subagent and/or plugin gating, with
  `skillOverrides` trimming any process-skills that must remain plain project skills. ✔ (with the Path-A/B/C trade-off for the operator)
- **"An AGENT = persona as a standing instance" → `.claude/agents/<persona>.md` with
  `skills:` + `initialPrompt`, bootable via `--agent`.** ✔
- **"References/knows fold INTO process-skills (self-contained)" → supported.** A skill
  directory bundles its own reference files, lazy-loaded via `${CLAUDE_SKILL_DIR}`. ✔
- **Grouping caveat to carry into the doc:** there is **no nested skill-dir grouping**
  within one `.claude/skills/`; persona grouping is a **naming convention** or a
  **plugin boundary**, not a directory tree.

### Open questions to settle with the operator (before folding into docs/personas.md)
1. **Persona runtime form:** subagent-preload (Path A) vs. per-persona plugin (Path B)
   vs. manual `disable-model-invocation` (Path C) — pick the default; they trade
   isolation vs. distributability vs. thrift.
2. **Plain-worker thrift:** are we willing to manage `skillOverrides` in settings to
   keep Path-A process-skills out of plain polecats, or does that push us to Path B?
3. **Distribution:** do we ever target >1 framework / cross-rig persona sharing? If yes,
   Path B (plugin) earns its weight; if no, Path A is lighter.
4. **The `disable-model-invocation` ↔ preload exclusivity** is a hard constraint to
   encode in whatever convention we adopt — a process-skill cannot be both "hidden from
   plain context" and "preloaded into the persona-subagent." Decide per-skill class.

## Uncertain / not documented
- **Per-agent skill *visibility* scoping** (a skill seen only by persona X, hidden from
  all others, without plugins/settings) is **not** a documented native feature. The
  closest primitives are `skills:` preload, plugin gating, and `skillOverrides`.
- **Precedence when the same skill name exists in both a root `.claude/skills/` and a
  nested package `.claude/skills/`** is not spelled out (likely nearest-wins; untested).
- **`skillOverrides` interaction with subagent `skills:` preload** — whether a
  `name-only`/`off` override suppresses a skill that a subagent then preloads — is not
  documented; assume preload still injects the body (preload reads the skill set Claude
  can invoke, and only `disable-model-invocation` is documented to block it).
- **SDK force-invoke at startup** — no documented API to start an SDK agent already
  carrying a specific skill (only `setting_sources` + a `skills` selection); treat the
  SDK section as supplementary.
- The **canonical docs host** served as `code.claude.com/docs/en/…` on 2026-06-14;
  `docs.claude.com` mirrors it. Re-verify these specifics before implementation — this
  surface moves quickly.
