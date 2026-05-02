# gc-toolkit

A [Gas City](https://github.com/gastownhall/gascity) pack with custom agents,
formulas, and planning workflows, extending
[gastown](https://github.com/gastownhall/gastown).

Where gastown ships the production crew (mayor, deacon, polecat, refinery,
witness, boot, dog), gc-toolkit adds the roles and workflows we use to
*shape* how a city operates — structural engineering, planning pipelines,
and architecture capture.

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

- `docs/roadmap.md` — (coming soon) the shape of the pack's evolution
- `docs/gas-city-reference.md` — Gas City surface area (city.toml, CLI, packs, formulas)
- `docs/gas-city-pack-v2.md` — Pack/City v2 direction and open issues
- `docs/gascity-local-patching.md` — recommended process for cities that must carry local `gascity` patches

## Usage

Add gc-toolkit to your `city.toml` workspace includes alongside gastown:

```toml
[workspace]
includes = [
    "https://github.com/gastownhall/gastown/tree/main",
    "https://github.com/zookanalytics/gc-toolkit/tree/main",
]
```

gc-toolkit provides a `mechanik` named session template. To start one:

```toml
[[named_session]]
template = "mechanik"
```

Then:

```bash
gc start
gc session attach mechanik
```

## Relationship to gastown

gc-toolkit **extends** gastown — it does not replace it. The common crew
comes from gastown; gc-toolkit adds planning-phase roles and formulas.
Where we diverge at the formula level (e.g., a rewritten `mol-idea-to-plan`
for our workflow), gc-toolkit's version overrides gastown's via pack
include order.

## Related

- [gascity](https://github.com/gastownhall/gascity) — the Gas City orchestrator
- [gastown](https://github.com/gastownhall/gastown) — base pack this extends
- [gascity-packs](https://github.com/gastownhall/gascity-packs) — community packs
- [gt-toolkit](https://github.com/Xexr/gt-toolkit) — Gas Town formula library (inspiration)

## License

[MIT](LICENSE)
