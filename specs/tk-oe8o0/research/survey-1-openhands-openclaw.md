---
name: Prior-art survey 1 — OpenHands & OpenClaw
description: Full primary-source survey behind the persona model — OpenHands microagents/skills (keyword triggers, repo.md, public registry) and OpenClaw's factored IDENTITY.md / SOUL.md bootstrap bundle plus heartbeat daemon. Persisted from the mechanik-thread design session (2026-06-13); indexed by prior-art.md.
---

# Persona-System Prior Art Survey: OpenHands & OpenClaw

## Provenance

| System | Mechanism / artifact | Source (URL + repo/path) | Surveyed at |
|---|---|---|---|
| OpenHands microagents (V0 layout) | `.openhands/microagents/` — `repo.md` + keyword-triggered `*.md` | https://docs.openhands.dev/usage/prompting/microagents-repo ; https://docs.openhands.dev/usage/prompting/microagents-keyword ; dir listing `github.com/All-Hands-AI/OpenHands/tree/main/.openhands/microagents` | 2026-06-13 |
| OpenHands Skills (V1, supersedes microagents) | `.agents/skills/<name>/SKILL.md`; legacy `.openhands/{microagents,skills}/` read for back-compat | https://docs.openhands.dev/usage/prompting/microagents-overview (redirect from docs.all-hands.dev) | 2026-06-13 |
| OpenHands public registry | `skills/<name>/SKILL.md`, `plugins/`, distributed via `@openhands/extensions` | https://github.com/OpenHands/skills | 2026-06-13 |
| OpenDevin lineage | Renamed → OpenHands (early 2025), maintained by All-Hands-AI | https://arxiv.org/abs/2407.16741 ; https://www.openhands.dev/blog/one-year-of-openhands-a-journey-of-open-source-ai-development | 2026-06-13 |
| OpenClaw | Bootstrap files `IDENTITY.md` / `SOUL.md` / `AGENTS.md` / `USER.md` / `TOOLS.md` / `BOOTSTRAP.md`; `SKILL.md` skills | https://docs.openclaw.ai/concepts/agent ; https://github.com/openclaw/openclaw ; https://www.freecodecamp.org/news/how-to-build-and-secure-a-personal-ai-agent-with-openclaw/ | 2026-06-13 |

**Honesty notes up front:**
- **OpenClaw is real**, not a misremembering. Repo `github.com/openclaw/openclaw`, docs at `docs.openclaw.ai`. Lineage: **Moltbot → Clawdbot → OpenClaw** (recent renames; no firm dates published — URLs still carry old names). I did **not** independently verify the "378k stars / fastest-growing repo" figures (came from a fetched page summary; treat as marketing).
- **OpenHands terminology has shifted.** "Microagents" is the **V0** name; **V1 renamed them "Skills"** and moved the canonical path to `.agents/skills/`. The `.openhands/microagents/` path you asked about still works (back-compat) but is **legacy**. I report the microagents model as asked and flag where V1 differs.
- The OpenHands `.openhands/microagents/repo.md` was **not** at that exact path on `main` when checked — the live dir now holds `documentation.md` + `glossary.md`. `repo.md` is the documented convention and exists in many repos, but the canonical self-hosted example has been reorganized. Don't assume a fixed filename on HEAD.
- I could **not** load the V1 `SKILL.md` full schema page (404) or the Stanza IDENTITY.md course page (403). Field lists for those are corroborated across secondary sources, flagged inline.

---

## 1. OpenHands microagents (`.openhands/microagents/`)

This is really **three sub-mechanisms** under one directory. I'll split where the model differs.

### 1a. Repository microagent (`repo.md`)
- **Definition format:** Markdown; YAML frontmatter **optional**. If present, supports an `agent` field (defaults to `CodeActAgent`). No frontmatter → loaded as the repo agent with defaults.
- **Portable identity (a):** **No.** This is the *anti-persona* — it is entirely project-specific by design (repo purpose, setup commands, dir structure, CI checks, dev guidelines). It travels with the *repo*, not with a role.
- **Owned/managed files (b):** **No.** Purely informational context; it does not declare artifacts it writes nor restrict which files may be edited. (The closest thing: OpenHands *instructs the agent* to **create** an `AGENTS.md` at repo root — but `repo.md` itself isn't a file-ownership contract.)
- **Known/context files (c):** Implicit only — it *is* the curated context. No declared input globs.
- **Processes (d):** Soft — embeds setup/build/test conventions as prose, not a bound workflow engine.
- **Instantiation:** **Always loaded** into context for that repo; transient (prompt injection, not a standing addressable agent).
- **Closeness to our model:** Low — it's the project-pinned (b/c) half with **zero** portable identity.
- **Worth borrowing:** The "always-on, repo-resolved context file the agent both *reads and is told to maintain*" is a clean precedent for your *owns* + *knows* resolved-per-deployment.

### 1b. Knowledge (keyword-triggered) microagents
- **Definition format:** Markdown + **required** YAML frontmatter. Confirmed fields: `name`, `description`, `triggers` (list of keywords). (V0 also documented a `type: knowledge` / `agent` field across versions.)
- **Portable identity (a):** **Yes — strongest match here.** These are explicitly "reusable across multiple projects," domain expertise (e.g. a `github`/`git` agent) that travels independent of any one repo. This is the "portable identity/knowledge" leg of your model.
- **Owned/managed files (b):** No.
- **Known/context files (c):** **No file-glob/fileMatch.** Verified: activation is **keyword-in-prompt only** — there is **no** filesystem/file-type-based conditional loading in the docs. (Some marketing copy claims "context-aware based on file types"; the primary docs do **not** support that — honest flag.)
- **Processes (d):** Encodes methods/SOPs as triggered prose.
- **Instantiation:** Transient, **lazy** — loaded only when a trigger keyword appears. Not addressable.
- **Closeness to our model:** Medium-high on (a)+(d); misses (b) and (c-as-glob).
- **Worth borrowing:** **Trigger-gated lazy loading** is exactly your "loaded transiently into a conversation/step." Borrow the `triggers:` frontmatter as a cheap activation gate — but note its weakness (keyword-only) and consider adding the file-glob *knows* dimension they lack.

### 1c. Task microagents (`pr_review.md`, `bug_fix.md`, `feature.md`)
- Workflow templates (the *processes* leg). Documented as present but not formally schema'd as a distinct type. Maps to your (d).

**V1 delta (Skills):** Same model, renamed. Canonical path `.agents/skills/<name>/SKILL.md` (+ optional `README.md`); user-level `~/.agents/skills/`; categories are **Permanent/Repository, Keyword-Triggered, Organization, Global**. "AgentSkills-style progressive disclosure." Public registry (`OpenHands/skills`, npm `@openhands/extensions`) gives a real **portable-persona distribution channel** — directly relevant to your "travels-with-it" leg.

---

## 2. OpenDevin (lineage)

Not a separate mechanism — **OpenDevin is the former name of OpenHands** (homage to Cognition's Devin; renamed early 2025; now All-Hands-AI). The microagents/skills system is OpenHands-era; surveying OpenDevin separately would be redundant. Honest note: I found **no** distinct "OpenDevin persona" artifact predating the OpenHands microagents design.

---

## 3. OpenClaw (the "identity.md" recollection — **confirmed real**)

Your operator's memory is accurate. OpenClaw uses a **bootstrap-file bundle** that is the closest whole-system analog to your persona model.

- **Definition format:** A workspace dir (`~/.openclaw/workspace/`) of **plain Markdown** bootstrap files, injected into the system prompt's "Project Context" on the first turn of a session. Blank files skipped; missing files leave a marker; `openclaw setup` scaffolds defaults. Config in `openclaw.json` (`agents.defaults.workspace`, etc.). Skills are `SKILL.md` folders with YAML frontmatter (`name`, `description`), loaded **on-demand**.
- **Portable identity (a):** **Yes — and explicitly *factored*.** This is the standout: identity is split across files by concern —
  - `IDENTITY.md` = **factual identity** (name, vibe, emoji; ~5–15 lines),
  - `SOUL.md` = **persona/boundaries/tone** ("what you do / what you never do / how you communicate"),
  - `AGENTS.md` = operating instructions/memory rules,
  - `USER.md` = user profile,
  - `TOOLS.md` = tool guidance,
  - `BOOTSTRAP.md` = one-time first-run ritual (self-deletes).
  Because it's all on-disk Markdown, copying the workspace ports the persona (portability is implied, not a first-class "travels-with-it-across-projects" abstraction — honest caveat).
- **Owned/managed files (b):** Partial — `MEMORY.md` + `memory/` daily logs are artifacts the agent **maintains**; `AGENTS.md` codifies memory/bill-tracking write rules. No formal "this persona may only edit X" restriction.
- **Known/context files (c):** The bootstrap bundle + `MEMORY.md` are declared, always-injected inputs. `HEARTBEAT.md` is the periodic checklist read on daemon wakeups. No glob/fileMatch inclusion.
- **Processes (d):** `AGENTS.md` (SOPs/safety rails, e.g. "always screenshot after filling a form"), `HEARTBEAT.md` (patrol checklist), `cron/jobs.json`, and `SKILL.md` skills.
- **Instantiation:** **Standing daemon** — one embedded agent per Gateway (`systemd`/`LaunchAgent`, `openclaw gateway`, default `ws://127.0.0.1:18789`), wakes on heartbeat (~30 min). **Addressable** via stable session IDs (JSONL sessions); supports mid-run queue modes (`/queue steer|followup|collect|interrupt`).
- **Closeness to our model:** **Highest of all surveyed.** It hits a (factored identity), partial b (maintained memory), c (declared context), d (SOPs + heartbeat + skills) — the main divergence from yours is **always-standing daemon** vs your **transient-by-default, standing-only-to-patrol**. (And OpenClaw's heartbeat = "patrol continuously" is precisely your standing-agent case.)
- **Worth borrowing:** The **multi-file identity factoring** — `IDENTITY.md` (terse facts) vs `SOUL.md` (persona/tone) vs `AGENTS.md` (operating rules) — is the single best idea to steal: it lets the *portable* core (identity+soul) stay clean while project/operational concerns live in separate, separately-resolved files. Also borrow `HEARTBEAT.md` as the explicit artifact that distinguishes "transient load" from "standing patrol."

---

## Synthesis for your model

| Your leg | Best precedent | Gap to mind |
|---|---|---|
| **(a) portable identity** | OpenClaw `IDENTITY.md`+`SOUL.md` (factored); OpenHands knowledge skills (reusable, registry-distributed) | OpenClaw doesn't abstract "across projects" first-class; OpenHands repo.md is the opposite (project-pinned) |
| **(b) owns (project-relative artifacts written)** | OpenClaw `MEMORY.md`/memory logs; OpenHands "create AGENTS.md" instruction | **Neither declares a write-scope/edit-restriction contract** — this is genuinely novel to your model; nobody surveyed restricts editable files per persona |
| **(c) knows (project-relative context read)** | OpenHands repo.md (always-on); OpenClaw bootstrap bundle | **No system supports glob/`fileMatch` context inclusion** — verified absent in OpenHands (keyword-only). Your per-deployment glob resolution is a differentiator |
| **(d) processes** | OpenHands task microagents + `triggers`; OpenClaw `AGENTS.md`/`HEARTBEAT.md`/skills | Well-trodden; lazy keyword-triggering is the cheap-win pattern |
| **instantiation (transient↔standing)** | OpenHands = transient/lazy injection; OpenClaw = standing daemon + heartbeat + addressable sessions | You want **both modes in one model** — neither system spans the full range; OpenClaw's session-ID addressability + queue-steer is a good standing-mode reference |

**Two things no surveyed system does that your model proposes** (so: green-field, verify you actually want the complexity): (1) **per-persona editable-file/owned-artifact scoping** (b as a contract, not just convention), and (2) **glob/`fileMatch`-based "knows" inclusion** resolved per deployment. The closest anyone gets to (c) is keyword triggers (OpenHands) and always-on bundles (both).

Sources: [OpenHands repo microagent docs](https://docs.openhands.dev/usage/prompting/microagents-repo), [OpenHands keyword skills docs](https://docs.openhands.dev/usage/prompting/microagents-keyword), [OpenHands skills overview](https://docs.openhands.dev/usage/prompting/microagents-overview), [OpenHands public skills registry](https://github.com/OpenHands/skills), [OpenHands `.openhands/microagents/` dir](https://github.com/All-Hands-AI/OpenHands/tree/main/.openhands/microagents), [OpenHands arXiv paper](https://arxiv.org/abs/2407.16741), [One Year of OpenHands](https://www.openhands.dev/blog/one-year-of-openhands-a-journey-of-open-source-ai-development), [OpenClaw agent runtime docs](https://docs.openclaw.ai/concepts/agent), [openclaw/openclaw repo](https://github.com/openclaw/openclaw), [freeCodeCamp OpenClaw guide](https://www.freecodecamp.org/news/how-to-build-and-secure-a-personal-ai-agent-with-openclaw/).
