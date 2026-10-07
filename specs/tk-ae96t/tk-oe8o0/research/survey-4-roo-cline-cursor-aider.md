---
name: Prior-art survey 4 — Roo Code, Cline, Cursor & Aider
description: Full primary-source survey — Roo Code custom modes' fileRegex edit-fence, Cline rules, Cursor's four-mode rule activation taxonomy (always / glob-auto / description-requested / manual), and Aider's read-only vs editable file split. Persisted from the mechanik-thread design session (2026-06-13); indexed by prior-art.md.
---

# Persona-System Prior Art Survey

**Model recap:** persona = (a) portable identity, (b) *owns* (artifacts written AND/OR an edit-restriction), (c) *knows* (read context), (d) *processes* (methods); normally transient, occasionally a standing/addressable agent.

## Provenance

| System | Mechanism/artifact | Source (URL + repo/path) | Surveyed at |
|---|---|---|---|
| Roo Code custom modes | Custom mode def: `slug`/`name`/`roleDefinition`/`groups`+`fileRegex`; `.roomodes` / global `custom_modes.yaml` | https://docs.roocode.com/features/custom-modes (→ roocodeinc.github.io/Roo-Code/features/custom-modes); repo `RooCodeInc/Roo-Code`, `RooCodeInc/Roo-Code-Docs/.roomodes` | 2026-06-13 |
| Cline rules | `.clinerules` file or `.clinerules/` dir of `.md`/`.txt`; global `~/Documents/Cline/Rules`; YAML `paths:` frontmatter | https://docs.cline.bot/customization/cline-rules; repo `cline/cline`, community `cline/clinerules` | 2026-06-13 |
| Cursor rules | `.cursor/rules/*.mdc` (frontmatter: `description`/`globs`/`alwaysApply`); legacy `.cursorrules`; User vs Project rules | https://docs.cursor.com/en/context/rules (→ cursor.com/docs); forum.cursor.com/t/.../104879 | 2026-06-13 |
| Aider | `CONVENTIONS.md` + read-only/editable file split (`/read-only`, `--read`, `/add`); `.aider.conf.yml` `read:` | https://aider.chat/docs/usage/conventions.html; https://aider.chat/docs/config/options.html; repo `Aider-AI/aider` | 2026-06-13 |

> Honesty note: all four primary docs sites issue host redirects (Roo→GitHub Pages, Cursor→`cursor.com/docs`); I followed each and the field-level detail below is from the redirected primary pages, cross-checked against community sources. The Cursor "Manual" type is also rendered "ManualOnly" in one doc surface — same concept.

---

## 1. Roo Code — custom modes (closest analogue; the only one with true edit-restriction)

- **Definition format.** YAML or JSON object. Project modes in workspace-root `.roomodes`; global modes in `settings/custom_modes.yaml` (or `.json`). Top-level props: `slug` (`^[a-zA-Z0-9-]+$`), `name`, `description`, `roleDefinition`, `whenToUse` (opt), `customInstructions` (opt), `groups`.
- **Portable identity.** Yes, explicitly. `roleDefinition` is the persona ("personality and expertise"); a mode defined in global `custom_modes.yaml` travels across all projects, and a same-`slug` project `.roomodes` mode **completely overrides** the global one (all global props ignored). This is exactly your portable-identity-with-per-deployment-override split.
- **Owned/managed files — RESTRICTS edits (the headline match).** The `edit` entry in `groups` becomes a two-element array carrying a `fileRegex` + optional `description`:
  ```yaml
  groups:
    - read
    - - edit
      - fileRegex: \.(js|ts)$
        description: JS/TS files only
  ```
  (JSON: `["edit", { "fileRegex": "\\.(js|ts)$", "description": "..." }]`.) A blocked write raises a `FileRestrictionError` naming the mode, allowed pattern, description, attempted path, and tool. This is a *negative* ownership (a fence on which files may be edited), not a positive "declares artifacts it writes" manifest — maps to the second half of your "owns" ("a restriction on which files it may edit").
- **Known/context files.** No declarative read-glob. Read access is a coarse capability (`read` in `groups`); there is no per-mode "these are my inputs" list. Weaker than your *knows*.
- **Processes.** `customInstructions` / `roleDefinition` carry method as prose; modes also compose with Roo's orchestration (e.g. Boomerang/sub-task handoff between modes). No formal workflow binding in the schema.
- **Instantiation.** Transient-by-default and **switchable/addressable**: one active mode at a time, user- or AI-switched (`whenToUse` drives automated selection). Not a standing daemon, but the named, switchable profile is the strongest "becomes addressable" parallel here.
- **Closeness:** Very high — the only surveyed system that unifies portable role + per-project override + hard edit-restriction by regex.
- **Worth borrowing:** The `fileRegex`-on-`edit` shape and the `FileRestrictionError` surface — a ready blueprint for your "owns" fence (and consider a positive write-manifest as the complement Roo lacks).

## 2. Cline — rules / `.clinerules`

- **Definition format.** Plain Markdown/text. Single `.clinerules` file *or* a `.clinerules/` directory whose `.md`/`.txt` files are concatenated into the system prompt. Optional numeric prefixes for ordering. Global rules in `~/Documents/Cline/Rules`; workspace rules take precedence on conflict. Also ingests Cursor/Windsurf rules and `AGENTS.md`.
- **Portable identity.** Partial. Global-vs-workspace split gives portability of *instructions*, but there is **no named role/persona object** — rules are ambient guidance, not an identity you instantiate or switch to. (Cline's separate Plan/Act distinction is a workflow phase, not a persona.)
- **Owned/managed files.** None. Docs show **no file-edit-restriction mechanism** within rules; rules cannot fence editable files. No write-manifest either.
- **Known/context files.** Conditional activation via YAML frontmatter `paths:` globs (e.g. `src/components/**`, `*.test.ts`) — a rule loads only when context files match. This is *input-gated activation* (closest to your *knows*), but it scopes *when the rule applies*, not *what the persona reads*.
- **Processes.** Method-as-prose in the rule body; toggleable on/off via the Rules panel (the "self-improving"/AI-editable angle). No structured workflow binding.
- **Instantiation.** Fully transient/ambient — text appended to the prompt; nothing standing or addressable.
- **Closeness:** Low–moderate — portable-vs-project and glob-gated activation only; no identity, no ownership.
- **Worth borrowing:** The runtime **toggle UI** for rules and AGENTS.md interop; the `paths:` glob is a lightweight precedent for declaring context relevance.

## 3. Cursor — rules (`.cursor/rules/*.mdc`)

- **Definition format.** `.mdc` = YAML frontmatter (`description`, `globs`, `alwaysApply`) + Markdown body, one file per rule under `.cursor/rules/` (nestable). Plain `.md` w/o frontmatter is ignored for conditional loading. Legacy: single-file `.cursorrules` (deprecated, still read).
- **Portable identity.** Partial. **User Rules** = global (across projects, Chat-only); **Project Rules** = per-repo. Like Cline, this is portable *instruction*, not a named/switchable persona object.
- **Owned/managed files — context only.** Primary doc states plainly: **"Rules provide context only — they do not restrict file editing."** No ownership/fence. The `globs` field looks ownership-like but only controls *auto-attachment of the rule*, not write permission.
- **Known/context files.** Strongest declarative *knows* of the four, via four activation types keyed on frontmatter:
  - **Always** (`alwaysApply: true`) — every request;
  - **Auto Attached** (`globs` set) — loads when a matching file is in context;
  - **Agent Requested** (`description` set, `alwaysApply: false`) — model decides from the description;
  - **Manual** (neither) — only via `@rule-name`.
- **Processes.** Method-as-prose in the body; no workflow binding.
- **Instantiation.** Transient/ambient; `@rule-name` makes a rule *referenceable* but not an agent. No standing/addressable persona.
- **Closeness:** Moderate on *knows* (rich glob/description/always taxonomy) and portable-vs-project; **zero on *owns*** by explicit design.
- **Worth borrowing:** The four-mode activation taxonomy (always / glob-auto / description-requested / manual) is the cleanest vocabulary for your *knows* loading semantics — adopt the naming directly.

## 4. Aider — `CONVENTIONS.md` + read-only/editable split

- **Definition format.** Convention = ordinary Markdown (`CONVENTIONS.md`, name conventional, not magic). Loaded via `/read-only CONVENTIONS.md`, `aider --read CONVENTIONS.md`, or `.aider.conf.yml` `read: [CONVENTIONS.md, ...]`. Verbatim recommendation: *"It's best to load the conventions file with `/read CONVENTIONS.md` or `aider --read CONVENTIONS.md`"* (so it's read-only + prompt-cached).
- **Portable identity.** Weak. A conventions file is portable project context, but there is **no role/persona/mode** at all — Aider has no named agent identity construct.
- **Owned/managed files — an inverted, per-session ownership.** Aider's core distinction is the one place your *owns* and *knows* both appear, as a runtime split of the chat file set:
  - **Editable** files (`/add`) — the model may write them;
  - **Read-only** files (`/read-only`, `--read`) — referenced, never edited.
  This is effectively a *positive editable-set* (the inverse of Roo's negative regex fence): ownership is "which files I'm allowed to edit this session," chosen per session rather than declared on a persona. No glob/regex; it's an explicit file list. (Note an open request, `Aider-AI/aider#3425`, to separate read-only vs editable via `.aiderignore` — i.e. this is list-based, not pattern-based, today.)
- **Known/context files.** The read-only set *is* the declared read context; `.aider.conf.yml read:` makes it project-persistent. Matches your *knows* well, by explicit path.
- **Processes.** Conventions body carries method-as-prose; Aider's own architect/code modes are workflow phases, not personas.
- **Instantiation.** Per-session, transient; nothing standing/addressable.
- **Closeness:** Moderate on *owns*/*knows* (clean editable-vs-readable split, persistable), but no identity and no patterns.
- **Worth borrowing:** The **editable-set ⊕ read-only-set** framing — pairs naturally with Roo's regex fence: your "owns" could express *both* a positive write-manifest (Aider-style) and a negative edit-fence (Roo-style), and Aider shows read-only context should be **prompt-cached**.

---

## Synthesis for your model

- **Owns (edit-restriction):** Only **Roo Code** enforces it — regex fence on the `edit` capability with a typed `FileRestrictionError`. **Aider** offers the positive complement (per-session editable set). **Cursor explicitly does not restrict edits; Cline has no such mechanism.** Borrow Roo's regex-fence shape + Aider's positive editable-set; your "owns" can carry both a write-manifest and an edit-fence, which no single system does.
- **Knows (read context):** **Cursor's** four-type activation (always / glob-auto / description-requested / manual) is the richest declarative vocabulary; **Cline's** `paths:` and **Aider's** read-only set are simpler precedents. Borrow Cursor's taxonomy naming.
- **Portable identity + per-deployment override:** **Roo** is the only true match (global mode ⇄ project `.roomodes` override by `slug`); Cline/Cursor only split global-vs-project *instructions* with no identity object.
- **Instantiation (standing/addressable):** None run a persona as a standing daemon; **Roo's** switchable named modes (and Cursor's `@rule-name` reference) are the nearest "becomes addressable" precedents — your transient-load-then-promote-to-standing-agent design appears to be **net-new** relative to all four.
- **Processes:** Uniformly weak — all four encode method as prose in a role/rules body; none bind a persona to a structured workflow. This is open design space.

**Sources:** [Roo custom modes](https://docs.roocode.com/features/custom-modes) · [Roo-Code-Docs `.roomodes`](https://github.com/RooCodeInc/Roo-Code-Docs/blob/main/.roomodes) · [Cline rules](https://docs.cline.bot/customization/cline-rules) · [cline/clinerules](https://github.com/cline/clinerules) · [Cursor rules](https://docs.cursor.com/en/context/rules) · [Cursor MDC forum](https://forum.cursor.com/t/cursor-rules-mdc-clarification/104879) · [Aider conventions](https://aider.chat/docs/usage/conventions.html) · [Aider options](https://aider.chat/docs/config/options.html) · [aider#3425 read-only vs editable](https://github.com/Aider-AI/aider/issues/3425)
