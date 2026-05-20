# Agent brief

> **Status:** sibling principle to [document-spec.md](./document-spec.md). Filed
> separately because parent `tk-yiwfz` (which adopts the doc-spec) is still
> in proposal state and we want the two adoptions decoupled — adopting
> "agent brief" as a named concept does not require waiting on doc-spec
> adoption, and revising the doc-spec does not require revising this
> doc.
>
> **Beads:** `tk-yw3zb.2` (initial rename and concept). `tk-13a8x` (rework
> from a hand-maintained Gas City surface summary to index + learnings).
> **Parent:** `tk-yw3zb` (doc-keeper agent-brief maintenance machinery
> for gc-toolkit).

## Definition

The **agent brief** is the canonical reference material an agent working
in or on Gas City needs to load. It is a **named concept, not a named
file**: designating the brief as a concept rather than picking a single
filename lets downstream infrastructure (config, drift-audit,
doc-update workers) refer to the brief without enumerating its
contents, and lets member docs keep their existing names.

In gc-toolkit's doc-type taxonomy (see
[document-spec.md](./document-spec.md)), the brief is an
**agent-context set**: a cross-type designation over the docs an agent
role-template loads as routine context. The designation spans doc-types
rather than being a subset of any one of them. A doc in the brief
keeps its own doc-type classification; the brief is the union an agent
consumes.

## Today's canonical brief

Two reference docs under `docs/` collectively comprise the brief — one
index into upstream Gas City documentation, plus one gc-toolkit-specific
process doc:

- **[`gascity-reference.md`](../gascity-reference.md)** — index of
  canonical Gas City documentation at `docs.gascityhall.com`. The
  index points; it does not paraphrase. Also carries the bar (see
  below) and the refresh procedure.
- **[`gascity-local-patching.md`](../gascity-local-patching.md)** —
  recommended process when a city must carry local fixes against
  `gascity` ahead of upstream.

The brief is **reference**, not **instruction**. Institutional Gas City
knowledge belongs here so an agent (today: `mechanik`) can do its job
without re-researching how Gas City works each time. Operational
doctrine — what to do, when to do it, how to avoid known pitfalls —
does **not** belong in the brief; it belongs alongside the agents that
follow it.

Three previously-bundled "learnings" — upstream engagement, rebase
conventions, polecat patterns — moved out to template-fragments with
two homes. **Upstream engagement** is broadly applicable to any
consumer carrying local gascity patches; it lives in core gc-toolkit
at `template-fragments/upstream-engagement.template.md` and is
injected into the mayor and mechanik prompts. **Rebase conventions**
and **polecat patterns** are gascity-rig-specific (they assume a fork
relationship to upstream `gascity`); together with
`refinery-rebase-handling` they ship in the opt-in
`packs/gascity-keeper/` sub-pack at
`packs/gascity-keeper/template-fragments/`. Their injection into the
gascity rig's polecat and refinery is wired via `[[rigs.patches]]`
blocks in the importing city's `city.toml` (see
`packs/gascity-keeper/pack.toml` for the example block). Mechanik in
a non-gascity rig does not receive the gascity-rig-specific
fragments.

## The bar

A doc lives under `docs/gascity-*.md` only when **all four** hold:

1. **It's about gc-toolkit's _use_ of Gas City, not Gas City itself.**
   Generic Gas City knowledge belongs upstream — file a PR to
   `gastownhall/gascity`.
2. **The learning is durable, not bead-tied.** One-incident gotchas
   live in `specs/<bead-id>/` or working memory.
3. **Someone owns keeping it current** as upstream Gas City evolves.
4. **It's non-obvious** — a competent new contributor wouldn't infer
   it from upstream docs plus the code.

If any of the four fail, the content does not belong in the brief.
The same bar is stated in [`gascity-reference.md`](../gascity-reference.md)
so the rule is discoverable from the index itself.

## Where the canonical list lives

This doc is the **single canonical location** for the brief membership
list ("Today's canonical brief" section above). Downstream
configuration, drift-audit tooling, and doc-update workers point here.

The "Agent Brief" section of
[`agents/mechanik/prompt.template.md`](../../agents/mechanik/prompt.template.md)
carries an **operational rendering** of the canonical list — the same
bullets inlined into the prompt because agents must remain
self-contained at boot. If the two diverge, this doc is authoritative
and the prompt rendering must be re-synced from it.

When the doc-keeper config block ships (parent `tk-yw3zb`), the
canonical list moves into pack/rig config: **config IS the index**. At
that point this doc retains the concept definition, the bar, and the
prompt template references config rather than enumerating files.

## Cross-reference

[document-spec.md](./document-spec.md) (sibling) — gc-toolkit's full
doc-type taxonomy. The agent brief spans multiple doc-types in that
taxonomy; the unified framing lives here rather than in the taxonomy
itself.
