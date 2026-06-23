---
name: Personas mechanics — investigation record (tk-ohrlc)
description: Work record for tk-ohrlc — the investigation that settles the four deferred "Mechanics" questions behind docs/personas.md (skill load paths, subagent skill loading, persona-process scoping, the assume-persona entry point), verified against current Claude Code docs. Findings only; they return to epic tk-ae96t for operator discussion before anything folds into docs/personas.md.
---

# Personas mechanics — investigation record

> **Note — tk-ae96t.2 (PR #166).** The persona runtime-form trade-off this
> investigation frames as open — **Path A / B / C** (subagent-preload vs. per-persona
> plugin vs. `disable-model-invocation`) — was subsequently resolved by the first
> persona implementation: the architect ships **top-level / city-wide method-skills**
> plus a proof-point mol (`mol-architect-review`), with **no standing agent**. These
> remain the mechanics findings (verified 2026-06-14); the resolution lives in
> [`docs/personas.md`](../../docs/personas.md).

This directory is the bead-local record for **tk-ohrlc**, which **investigates** the
four deferred "Mechanics" questions that `docs/personas.md`
left as a TBD stub. The deliverable is a **findings write-up**, not a doc edit.

- **Findings:** [`research/mechanics.md`](research/mechanics.md) — the four questions
  answered, with per-answer provenance and an "Uncertain / not documented" section.

## Provenance

- **Parent epic:** `tk-ae96t` — the
  personas initiative (persona-as-skill). Origin: mechanik-thread design session,
  2026-06-13.
- **Why a separate write-up (not a doc edit):** `docs/personas.md` lives only on the
  **held** PR #123 (branch `polecat/tk-oe8o0`, intentionally unmerged until the first
  persona implementation), **not on `main`**. So the "Mechanics (deferred)" stub cannot
  be filled here. Per the dispatch note (epic tk-ae96t, 2026-06-14), findings are
  persisted standalone — mirroring how `tk-oe8o0`
  persisted its prior-art surveys under `specs/<bead>/research/` — and return to the
  epic host for operator discussion. Settled mechanics fold into `docs/personas.md`
  later, after that discussion and the first implementation.
- **Verification stance:** answers are grounded in the **current** Claude Code docs,
  fetched and cross-checked **2026-06-14** (not training memory — the skills/subagents
  surface changes fast). Load-bearing claims were re-verified directly against the
  primary doc pages. See the provenance table in `research/mechanics.md`.

## The four questions (and the one-line answers)

1. **Skill load paths — flat vs. nested.** A skill is a `<name>/SKILL.md` *directory*.
   Discovery is **flat within** a single `.claude/skills/` (no nested-dir grouping), but
   **spans many** `.claude/skills/` dirs (every parent to repo root + on-demand
   monorepo package dirs). Precedence: managed > personal > project; plugin skills are
   namespaced. → Persona grouping is a **naming convention or a plugin boundary**, not a
   directory tree.
2. **Subagent skill loading.** A subagent runs in a fresh isolated context (system
   prompt = its body; no parent leak). It can invoke skills via the Skill tool, and —
   key — its **`skills:` frontmatter preloads full skill bodies at startup**. That is the
   primitive that makes "process-skills ride with the persona."
3. **Persona-process scoping.** No native per-agent *visibility* scoping of project
   skills (every description sits in every session's context). Curate via: subagent
   `skills:` preload, a disabled-by-default **plugin**, `disable-model-invocation`
   (removes the description from context but blocks preload — a real exclusivity
   constraint), or `skillOverrides` settings. `allowed-tools` scopes **capability, not
   visibility** — don't conflate.
4. **Assume-persona entry point.** In-session: invoke the persona identity skill via its
   `/<skill-name>` command (it persists for the session). At boot: **`--agent <name>` / the `agent` setting** runs an
   agent as the main session, with `skills:` preloads + an `initialPrompt` (which
   processes commands/skills) — the cleanest documented "boot as the persona." No bare
   `claude --skill` flag exists.

## Status

- **Investigation:** complete (2026-06-14).
- **Next:** findings return to epic **tk-ae96t** for operator discussion. The
  Path A / B / C scoping trade-off (subagent-preload vs. per-persona plugin vs.
  `disable-model-invocation`) and the four open questions in
  [`research/mechanics.md`](research/mechanics.md#open-questions-to-settle-with-the-operator-before-folding-into-docspersonasmd)
  are the decisions to make **before** folding settled mechanics into `docs/personas.md`.
