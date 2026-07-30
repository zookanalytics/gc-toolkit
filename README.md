# gc-toolkit

A pack for [Gas City](https://github.com/gastownhall/gascity), the multi-agent
runtime — custom agents, formulas, and planning workflows for getting work done
while spending human attention sparingly.

gc-toolkit is built directly on Gas City's primitives (beads, molecules, checks,
skills, roles, routing); it does not depend on a *fork* of the runtime. It is **not** an
extension of [gastown](https://github.com/gastownhall/gastown) — gastown is an
example pack for Gas City, not an upstream. gc-toolkit borrows what is genuinely
reusable from it (reusable molecules above all) and is otherwise an independent
implementation of its own approach. Part of the agent roster is still stood up by
importing gastown today, but that mechanism is transitional and being reduced —
not the architecture.

## Status

**Early.** Actively evolving. Prompts, formulas, and agent configs may change
without warning. No stable release yet.

## What's Here

### Agents

- **`mechanik`** — city-scoped structural engineer. Owns formulas, agent
  configs, dispatch patterns, quality gates, prompt engineering, and
  operational conventions. Analyzes patterns and designs improvements;
  does not grind beads.

### Formulas

Coming soon. The goal is a planning pipeline loosely inspired by gt-toolkit's
spec → plan → beads → deliver shape, but built for our own workflow and
opinions rather than cloned directly.

### Docs

- `docs/foundation.md` — guiding beliefs and operating discipline behind gc-toolkit
- `docs/architecture.md` — the 30,000-ft guide to how those beliefs are composed from Gas City's primitives, and the consistency test that keeps new work grounded
- `docs/install.md` — wiring gc-toolkit into a city (imports, sub-packs, patches, verification)
- `docs/roadmap.md` — the shape of the pack's evolution: what's true now and what's next
- `docs/gascity-reference.md` — index of canonical Gas City documentation at `docs.gascityhall.com`, plus the bar for adding new `docs/gascity-*.md`
- `docs/gascity-local-patching.md` — recommended process for cities that must carry local `gascity` patches
- `docs/file-structure.md` — conventions for where docs and specs live in this pack

## Usage

Import `gc-toolkit` from a rig in your `city.toml`:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

gc-toolkit provides a `mechanik` named session template. Declare it
once at the city level:

```toml
[[named_session]]
template = "mechanik"
```

Then:

```bash
gc start
gc session attach mechanik
```

See [`docs/install.md`](docs/install.md) for the full install
reference — remote imports, opt-in sub-packs (`gascity-keeper`),
`[[rigs.patches]]` fragment wiring, per-rig overrides, and `gc
doctor` verification.

## Relationship to gastown

gc-toolkit does **not** extend or augment gastown. Gastown is an *example pack*
for Gas City, not an upstream that gc-toolkit builds on; its operating model
diverges enough (notably the attention/board model) that gc-toolkit is best
understood as an independent implementation of its own approach, built directly
on Gas City.

What gc-toolkit takes from gastown is what is genuinely reusable — reusable
molecules above all. Part of the agent roster is also still stood up by importing
gastown today, with gc-toolkit's opinions patched in on top, but that mechanism
is transitional and being reduced — deliberately not the architecture. See
[`docs/architecture.md`](docs/architecture.md) for how the pieces fit together.

## Related

- [gascity](https://github.com/gastownhall/gascity) — the Gas City runtime gc-toolkit is built on
- [gastown](https://github.com/gastownhall/gastown) — an example pack for Gas City; gc-toolkit borrows reusable pieces but does not extend it
- [gascity-packs](https://github.com/gastownhall/gascity-packs) — community packs
- [gt-toolkit](https://github.com/Xexr/gt-toolkit) — Gas Town formula library (inspiration)

## License

[MIT](LICENSE)
