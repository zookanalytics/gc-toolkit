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

- `docs/foundation.md` — guiding beliefs and operating discipline behind gc-toolkit
- `docs/install.md` — wiring gc-toolkit into a city (imports, sub-packs, patches, verification)
- `docs/roadmap.md` — (coming soon) the shape of the pack's evolution
- `docs/gascity-reference.md` — index of canonical Gas City documentation at `docs.gascityhall.com`, plus the bar for adding new `docs/gascity-*.md`
- `docs/gascity-local-patching.md` — recommended process for cities that must carry local `gascity` patches
- `docs/file-structure.md` — conventions for where docs and specs live in this pack
- `docs/skills.md` — how skills are authored, filed, and exposed so one `SKILL.md` serves both Gas City and (when portable) Claude / Codex

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
