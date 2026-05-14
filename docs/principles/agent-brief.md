# Agent brief

> **Status:** sibling principle to [document-spec.md](./document-spec.md). Filed separately
> because parent `tk-yiwfz` (which adopts the doc-spec) is still in
> proposal state and we want the two adoptions decoupled — adopting
> "agent brief" as a named concept does not require waiting on doc-spec
> adoption, and revising the doc-spec does not require revising this
> doc.
>
> **Bead:** `tk-yw3zb.2` (this rename). **Parent:** `tk-yw3zb`
> (doc-keeper agent-brief maintenance machinery for gc-toolkit).

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
rather than being a subset of any one of them — today's brief comprises
two doc-type 1 (Reference manual) docs and one doc-type 2 (Versioned
reference) doc. A doc in the brief keeps its own doc-type classification;
the brief is the union an agent consumes.

## Today's canonical brief

Three reference docs under `docs/` collectively comprise the brief:

- **`gas-city-reference.md`** — current Gas City surface area
  (city.toml schema, CLI commands, pack structure, agent roles,
  formulas, beads, the Nine Concepts architecture).
- **`gas-city-pack-v2.md`** — pack/city v2 direction and open issues
  tracking the 1.0 release.
- **`gascity-local-patching.md`** — recommended process when a city
  must carry local fixes against `gascity` ahead of upstream.

These filenames stand. The brief framing is a designation over existing
files, not a rename: zero file moves.

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
that point this doc retains the concept definition and the prompt
template references config rather than enumerating files.

## Cross-reference

[document-spec.md](./document-spec.md) (sibling) — gc-toolkit's full
doc-type taxonomy. The agent brief spans multiple doc-types in that
taxonomy (currently doc-types 1 and 2); the unified framing lives here
rather than in the taxonomy itself.
