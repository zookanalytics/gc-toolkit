---
name: Decision record — helm board hierarchy UX beyond indentation
description: Why the board's parent rows became collapsible, summarizing headers (over focus/drill-in or a different grouping axis), how the #878/#911 ordering and degrade invariants are preserved, the owed-visibility trade-off a fold makes, and what is deferred to named siblings.
---

# Helm board hierarchy: collapsible, summarizing parent headers

Follow-up to PR#911 (anchor tk-t6gd5x), which shipped the `group_parent`
containment tree and rendered each family by indenting titles by depth. The
operator ruled the indent-only rendering insufficient — "we simply indent
titles, best practices from 40 years ago" (PR#911 review, visit tk-vc5itp,
finding tk-a00r4b) — and funded this iteration from the landed shape.

## What this builds

A parent row (a family root, or a nested sub-epic) is a navigable, summarizing
header rather than an indented title:

- **A disclosure control folds its subtree.** The fold is a view state kept in
  `localStorage`, so it survives the 30s poll and the next visit — a parent
  keeps its "room" between glances, the durable-place principle the Attention
  Canvas brief is built on (`specs/tk-eemvf/design/attention-canvas-design-brief.md`).
- **A summary states what the fold leaves legible.** The needs-you count
  (`owed` descendants) shows folded or not — the one signal a fold must never
  swallow. The per-band breakdown (`section` counts in SECTION_ORDER) shows
  only when folded, because an expanded parent has its rows below to carry it.
- **An expand-all escape hatch** appears only while something is folded, so a
  row folded away is never lost.

The change is confined to the web render layer (`services/helm/web/src/App.tsx`,
`styles.css`, `App.test.tsx`, rebuilt `dist/`). The board wire already carries
everything a summarizing header needs: the containment tree (`group_root` /
`group_parent`), the rolled-up tri-state (`phase` / `frontier`, from tk-ikpyzn.6),
progress counts, and the per-section band. The summary reads those fields; it
does not re-derive their state. No Go or wire change.

## Why this direction, of the three the bead named

- **Collapsible subtrees with summarizing parents** (this) directly answers the
  critique and the brief's bar: "a great tile lets the operator finish a thought
  without drilling in," and §10's open question "does zooming out cluster,
  summarize, or just shrink?" — the answer here is *summarize*. It is the
  lowest-regret increment: it builds on PR#911's plumbing and the tk-ikpyzn.6
  roll-up, and it is pure view state, so it is cheap to revise.
- **Focus / drill-in with a breadcrumb** is a larger navigation model, and a
  drill-in plane already exists (`src/drill/`). Deferred as a candidate for the
  design pass rather than built speculatively here.
- **A different grouping axis** would discard the dependency-containment model
  #911 just established; no evidence yet that another axis serves the operator
  better. Left to the design pass to weigh.

## Invariants preserved (#878 / #911)

- **Owed-first family order.** Folding happens in `visibleRows`, after
  `flattenFamilies` lays the families out, and it only *removes* rows — it never
  reorders them. Family order, sibling order, and the owed-first partition are
  untouched.
- **Stable positions (no reshuffle by attention).** A fold is an operator
  action, never attention-driven; a row's place among its siblings does not
  move.
- **Safe degrade when `group_parent` is unstamped.** A family with no stamped
  parents degrades to a flat one-level list under its root (unchanged from
  #911); that root is still a parent and still folds.

## The owed-visibility trade-off (for operator review)

Folding a parent hides its descendant rows, which can include ones the operator
owes. Three things keep that honest rather than hiding the queue: the folded
header shows an unmissable `● N need you`; the "owed by you" cover-sheet still
counts those rows; and expand-all is always one click away. The alternative —
refusing to fold a subtree with an owed descendant, or force-expanding it — was
rejected as too rigid for a first iteration. This is the one behavior worth an
explicit ruling when the direction is reviewed.

## Deferred, and tracked

- **tk-ikpyzn.9** — progress/N-M column meaningful only on parents, not leaf
  rows. Left to its own bead; this change does not touch `progressCell`.
- **Focus / drill-in with a breadcrumb** — a candidate for the design pass
  (tk-ikpyzn.12), not built here.
- **A wire-level subtree summary for CLI parity** — the summary is web-only
  because folding is a web interaction with no CLI equivalent (tk-ikpyzn.3, the
  CLI/web parity bead, is held). If the CLI later summarizes, the counts move to
  the derive layer so the two surfaces cannot diverge.

## Coordination with the design pass (tk-ikpyzn.12)

The broad design pass revalidates the whole board's direction, including the
brief's spatial-canvas vision, and is armed behind PR#936. This bead is scoped
to the hierarchy UX *within the landed table*, iterating from PR#911 as its
charter directs; it is not the canvas rewrite. If the design pass sets a
different direction, this fold/summarize layer is cheap to retire — it is view
state over unchanged wire.
