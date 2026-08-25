# gc-toolkit

A pack for [Gas City](https://github.com/gastownhall/gascity), the multi-agent
runtime. gc-toolkit gets work done by relentlessly focusing on high-bandwidth
human interaction: agents do the cheap work before they interrupt, the surface
makes judgment easier rather than transferring work back to the operator, and
every lesson compounds into the pack so attention is never spent twice
([docs/foundation.md](docs/foundation.md) is the charter).

The pack is its workflows. Every component belongs to one of six:

| Workflow | What it does | Entry points |
|---|---|---|
| **work** | a filed bead becomes a pushed branch | `mol-polecat-work`, `lifecycle/lifecycle.toml`, `assets/scripts/lifecycle.sh` |
| **review** | a gate verdict lands on the anchor | polecat-codex pool, `assets/scripts/signoff.sh`, [skills/signoff-review](skills/signoff-review/SKILL.md) |
| **merge** | gates green at the live head become a landed PR | `orders/refinery-reconcile.toml` + 5 arms ([docs/refinery-merge-cadence.md](docs/refinery-merge-cadence.md)) |
| **visit** | a human decision is prepared, framed, and held for | `mol-visit`, converse, `assets/scripts/escalate.sh`, the helm board |
| **feedback** | corrective lessons become standing pack behavior | feedback miner/distiller orders ([docs/feedback-learning.md](docs/feedback-learning.md)) |
| **patrol** | drift between recorded and true state is repaired | witness / deacon patrols, `orders/liveness-sweep.toml`, `doctor/` |

## Roster

All agents are native to this pack — no gastown import.

| Agent | Kind | Job |
|---|---|---|
| `polecat` | worker pool | claims routed work beads, implements, hands off |
| `polecat-codex` | review pool | claims review beads, runs [signoff-review](skills/signoff-review/SKILL.md), writes one verdict via `signoff.sh` |
| `refinery` | patrol | merge judgment: rejection, blocked/refused calls; the mechanical cadence runs as an order |
| `witness` | patrol | rig recovery: orphaned beads, stalled workflows |
| `deacon` | patrol | city infra health: dolt, doctor sweep |
| `dog` | warrant executor | due-process recovery of wedged sessions ([authority-map.md](docs/authority-map.md)); demand-scaled 0→2 |
| `converse` | conversation role | holds subject conversations, claims visits |
| `mechanik` | named session | city-scoped structural engineer: formulas, prompts, conventions |
| `proactive` | optional | default-disabled first-reaction pass |

## Usage

Import gc-toolkit from a rig in your `city.toml`:

```toml
[[rigs]]
name = "my-rig"
prefix = "mr"

[rigs.imports.gc-toolkit]
source = "rigs/gc-toolkit"
```

gc-toolkit provides a `mechanik` named-session template. Declare it once at
the city level:

```toml
[[named_session]]
template = "mechanik"
```

Then:

```bash
gc start
gc session attach mechanik
```

See [docs/install.md](docs/install.md) for the full install reference — remote
imports, the opt-in `gascity-keeper` sub-pack, the helm `[[service]]` stanza,
and `gc doctor` verification of the nine structural checks.

## Developing this pack

Run `assets/scripts/render-seed-audit.sh --install-hook` once per clone. It
wires `assets/hooks/pre-commit`, which regenerates `generated/seed-audit/` —
the rendered standing prompt of every agent and compiled recipe of every
formula, against a synthetic city — whenever a commit touches a renderer
input (`agents/`, `template-fragments/`, `formulas/`, `packs/`, `pack.toml`,
or the renderer itself). Nothing under `generated/` is hand-edited;
`doctor/check-seed-audit-current` warns when the artifact is stale or absent,
and `render-seed-audit.sh --check` verifies it exactly.

## Docs

- [docs/foundation.md](docs/foundation.md) — beliefs and operating discipline (the charter)
- [docs/architecture.md](docs/architecture.md) — how the workflows compose Gas City's primitives, and the consistency test for new work
- [docs/state-machine.md](docs/state-machine.md) — the anchor state machine: every state, every transition, every writer
- [docs/component-model.md](docs/component-model.md) — the primitives, and every invariant bound to its doctor check
- [docs/install.md](docs/install.md) — wiring gc-toolkit into a city
- [docs/gascity-reference.md](docs/gascity-reference.md) — index of canonical Gas City documentation and the pack's local supplements

## Related

- [gascity](https://github.com/gastownhall/gascity) — the runtime gc-toolkit is built on
- [gascity-packs](https://github.com/gastownhall/gascity-packs) — community packs

## License

[MIT](LICENSE)
