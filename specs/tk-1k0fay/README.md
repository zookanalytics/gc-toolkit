---
name: Ecosystem Skill-Artifact Audit (tk-1k0fay)
description: Pure-catalog survey across seven AI-agent skill (and skill-adjacent) ecosystems — Superpowers, BMAD-METHOD, Anthropic public skills, Spec Kit, Kiro Steering, Gas Town molecules, and Claude Code built-in skills.
---

# Ecosystem Skill-Artifact Audit — tk-1k0fay

This directory catalogs the ecosystem of AI-agent skill artifacts
(and skill-adjacent artifacts like molecules and commands) across
seven sources, so gc-toolkit can borrow before it invents.

**Surveyed:** 2026-05-24
**Producer:** Polecat `gc-toolkit.nux` per `mol-polecat-work`
**Scope:** Pure cataloging — no synthesis, no borrowing decisions,
no recommendations for what gc-toolkit should adopt. Each per-source
file describes what that source ships; [`matrix.md`](matrix.md)
indexes which sources cover which functional area.

## Reading order

1. [`matrix.md`](matrix.md) — start here. Cross-source coverage
   matrix indexed by functional area, plus Gaps and Overlaps
   sections. Use it to find which per-source file is relevant to
   a given question.

2. Per-source surveys. Each opens with a provenance table
   (Mechanik convention: artifact / producer / source URL+SHA /
   surveyed-at), then walks license, schema, full skill catalog,
   2-3 representative skills in detail, and notable conventions.

   - [`anthropic-skills.md`](anthropic-skills.md) — `anthropics/skills`
     (Apache-2.0 + source-available; canonical SKILL.md reference;
     17 skills incl. `skill-creator`, `pdf`, `mcp-builder`)
   - [`superpowers.md`](superpowers.md) — `obra/superpowers` (MIT;
     14 skills; multi-harness plugin; SessionStart hook injects
     `using-superpowers`)
   - [`bmad-method.md`](bmad-method.md) — `bmad-code-org/BMAD-METHOD`
     (MIT + BMad trademark; 44 skills across `core-skills` and
     phase-keyed `bmm-skills`; 6 named personas; `customize.toml`
     three-layer override)
   - [`spec-kit.md`](spec-kit.md) — `github/spec-kit` (MIT; 9
     `/speckit.*` commands; canonical `specs/<feature>/` per-feature
     filing convention; installs commands into 30+ harnesses
     including Claude Code as `speckit-<name>/SKILL.md`)
   - [`kiro-steering.md`](kiro-steering.md) — Kiro IDE Steering
     (proprietary; documentation openly readable; four
     **inclusion modes** — `always` / `fileMatch` / `manual` /
     `auto` — as the central convention; AGENTS.md interop)
   - [`gas-town.md`](gas-town.md) — `rigs/gascity/examples/gastown/`
     (MIT; 7 molecules + 6 agent roles + 1 command + 1 doctor
     check; TOML formula language; patrol-loop pattern with
     pour-next-wisp + burn-current)
   - [`claude-code-builtins.md`](claude-code-builtins.md) — Claude
     Code CLI v2.1.150 bundled skills (proprietary CLI;
     11+1 built-in skills compiled into the binary; consumer of
     the Anthropic SKILL.md schema + harness extensions)

## License summary

| Source | License | Vendorable? |
|---|---|---|
| `anthropics/skills` | Mix of Apache-2.0 skills, proprietary "source-available" document skills (`docx`, `pdf`, `pptx`, `xlsx`), and one skill (`doc-coauthoring`) with no LICENSE.txt — licensing unclear; no top-level LICENSE in the repo | Apache-2.0 skills yes; document skills no; `doc-coauthoring` unclear |
| `obra/superpowers` | MIT (Copyright Jesse Vincent 2025) | Yes |
| `bmad-code-org/BMAD-METHOD` | MIT (Copyright BMad Code, LLC 2025) + BMad trademark notice (see `TRADEMARK.md`) | Yes (software MIT); marks restricted |
| `github/spec-kit` | MIT (Copyright GitHub, Inc.) | Yes |
| Kiro Steering (kiro.dev) | Proprietary — Kiro IDE & CLI under AWS IP License; docs openly readable but not declared vendorable | No vendoring; pattern can be modeled |
| Gas Town (`rigs/gascity/examples/gastown/`) | MIT (Copyright Steve Yegge 2025) | Yes |
| Claude Code built-in skills | Proprietary — CLI-bundled; the public `anthropics/skills` repo is reference/demo material, not the bundled implementation source (only `claude-api` clearly overlaps) | No vendoring of bundled binary; per-source skills per their license |

## What's in scope vs out of scope

**In scope:**
- Catalog every named skill / molecule / command / steering doc per
  source.
- Capture the SKILL.md (or equivalent) format/schema for each
  source.
- For Gas Town, judge each molecule "adoptable as-is by gc-toolkit?
  (Y/N + note)" — the explicit audit ask.
- Cite source path + commit SHA (or stable URL) for every artifact
  mentioned.
- Declare each source's license.
- Cross-source matrix of functional-area coverage, plus gap and
  overlap analysis.

**Out of scope:**
- Deciding what to vendor or borrow.
- Designing gc-toolkit's own SKILL.md schema.
- Recommending which skills gc-toolkit should adopt.
- Refactoring or proposing changes to gc-toolkit itself.

These boundaries are repeated in the bead description and were
enforced across the survey. The "adoptable as-is" column on the
Gas Town catalog is descriptive (what would survive a copy-paste?),
not prescriptive.

## Provenance and survey method

Six external sources were surveyed by sub-agents (one per source,
parallel dispatch) with web/repo access; Gas Town and a tightly-
scoped Claude Code survey ran in the main thread. Each sub-agent
received the source URL, the survey requirements, and the
provenance-table format; each returned its per-source markdown
which was written verbatim to the corresponding file in this
directory.

Commit SHAs pinned at survey time:

| Source | Commit SHA | Surveyed |
|---|---|---|
| anthropics/skills | `690f15cac7f7b4c055c5ab109c79ed9259934081` | 2026-05-24 |
| obra/superpowers | `f2cbfbefebbfef77321e4c9abc9e949826bea9d7` | 2026-05-24 |
| bmad-code-org/BMAD-METHOD | `ee47e30cf6bffb00eddfba4f4943df40071a3388` | 2026-05-24 |
| github/spec-kit | `a08af08415432db2ae15b70e82400eaad9dbfd2f` | 2026-05-24 |
| Kiro Steering (kiro.dev docs) | (not git-versioned; docs URL pinned) | 2026-05-24 |
| Gas Town (`rigs/gascity`) | `9a012279e19d39160a5bfb2f927ec6f1719f9af1` | 2026-05-24 |
| Claude Code CLI | v2.1.150 | 2026-05-24 |

## Acceptance criteria (per the bead)

- [x] All seven per-source docs present at `specs/tk-1k0fay/`.
- [x] `matrix.md` and `README.md` present.
- [x] Every skill / molecule mentioned has a source path + SHA (or
  stable URL).
- [x] Every source has a license declared.
- [ ] PR merged to `main`. (Pending refinery review of this branch.)
