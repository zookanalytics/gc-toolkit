# Agent brief

> **Status:** sibling principle to `document-spec.md`. Filed separately
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

In gc-toolkit's doc-type taxonomy (see `document-spec.md`), the brief
is a **sub-flavour of doc-type 1 (Reference manual)**: the subset of
reference manuals an agent role-template loads as context. A reference
manual that is not part of the brief is still a reference manual; the
brief is the subset agents consume routinely.

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

Today the list lives in this doc and in the "Agent Brief" section of
`agents/mechanik/prompt.template.md`. The two are kept in sync by hand.

When the doc-keeper config block ships (parent `tk-yw3zb`), the
canonical list moves into pack/rig config: **config IS the index**. At
that point this doc retains the concept definition and the prompt
template references config rather than enumerating files.

## Cross-reference

`document-spec.md` (sibling) — gc-toolkit's full doc-type taxonomy.
The agent brief is a sub-flavour of doc-type 1 (Reference manual) there.
