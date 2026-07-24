---
name: Requirements — docs/architecture.md (gc-toolkit 30k-ft guide)
description: The brief and scoping decisions for tk-d6imi — why docs/architecture.md exists, its altitude, its distinct subject vs the other central docs, and the organizing spine it must follow.
---

# Requirements — write `docs/architecture.md` (gc-toolkit)

This is the durable decision record for **tk-d6imi**: the brief that scoped a
new central `docs/architecture.md` and the calls made while writing it. The
authoritative artifact is `docs/architecture.md` itself; this file preserves
*why it was written that way*.

## Goal

Write a concise, **30,000-ft architectural guide** to how gc-toolkit's concepts
are *implemented*. It names the core features the pack delivers, the
**architectural pattern** behind each, how they play together, and where each is
defined — so the repo reads as one coherent system, and both what's built and
what's built next can be checked for consistency against it.

## Audience & altitude

- **Primary reader:** operator strategic reference — wants the *mental model* of
  what the pack is and how it's implemented. NOT a contributor how-to.
- **Altitude:** 30,000 ft. Broad architectural terms. **Name the pattern; don't
  tutorialize.** No code, no config syntax, no CLI-flag references, no
  file-line detail in prose.
- **NOT a decision-tree.** It explains *how we implement the concepts
  architecturally*, not "where to put your change."
- **Concise & scannable.** Target ~1–2 pages, consistent per-capability
  micro-structure. Each pattern is a phrase; interplay is a line; resist
  expanding into how-to.

## Distinctness (one doc per subject — link, don't duplicate)

- `foundation.md` = the **why** (beliefs/goals) → link.
- `roadmap.md` = the **where-to** (direction/primitives) → link.
- `README.md` = pitch/install; `file-structure.md` = filing conventions → link.
- `architecture.md` = **how it's built & how it coheres** (patterns + interplay
  + definition-sites). This is its distinct subject.

## Organizing spine: two flows + support, on one composition substrate

The pack exists to run **two flows**; everything else supports them, all wired
by one substrate.

- **Flow 1 — Attention** (the Bead-Universe Operating Model; epic `tk-q4xaj`):
  pre-advance work before it claims human attention.
- **Flow 2 — Delivery** (filed bead → landed, live change).
- **Support layers:** engine health, fork & upstream, doc & knowledge cohesion.
- **Composition substrate:** how all of the above is wired and where each lives.

## Per-capability entry contract

For each capability: **what it delivers · the architectural pattern that
implements it · how it plays with the rest · where it's defined.** A small
two-flows diagram is welcome IF it aids the at-a-glance "how they play together"
— optional, keep it minimal.

## Forward lever

Close with a short note (a few sentences, not a routing tree): the doc is the
consistency map — new capabilities should slot into one of these flows/layers
and reuse its pattern; that's how "what gets built next" stays coherent.

## Verification (accuracy is the point of a cohesion doc)

- **Verify every "where defined" against the actual files** before asserting it.
  The file-level survey wins over the brief; correct any pattern name or
  definition-site the brief got wrong.
- Ground every pattern claim in the pack (`pack.toml`, the fragments, the
  formulas, the docs). If a claimed pattern isn't how it actually works, fix the
  doc.

## Deliverables

1. `docs/architecture.md` — the guide (central tier; standard frontmatter per
   `file-structure.md`).
2. `specs/tk-d6imi/requirements.md` — this brief as the durable decision record
   (local tier; per the filing-documentation rule it must not live only as a
   bead comment).

## Acceptance criteria

- [ ] `docs/architecture.md` exists; central-tier frontmatter; ~1–2 pages; scannable.
- [ ] Organized as two flows + support + composition substrate; each capability
      entry carries delivers / pattern / plays-with / defined-in.
- [ ] Patterns named at 30k ft; no code / CLI / decision-tree.
- [ ] Every definition-site verified against real files.
- [ ] Links (not restatements) to `foundation.md`, `roadmap.md`,
      `file-structure.md`, `work-bead-state-machine.md`,
      `gascity-local-patching.md`; references epic `tk-q4xaj`.
- [ ] `specs/tk-d6imi/requirements.md` committed.
- [ ] PR opened; passes the standard merge-gate. (Owned convoy: closed = landed.)

## Process

- Owned convoy anchors this to landed (closed = landed).
- Standard merge-gate applies (human approval + codex). **Do not self-merge.**
- mechanik reviews before it lands.
