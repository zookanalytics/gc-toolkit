---
name: Splitting gc-toolkit's city-scope half into gc-toolkit-city
description: Work record for tk-iunfnh. What the city-scope import of gc-toolkit actually contributed (measured, not assumed), why the four city-scope orders did NOT move, why the dog is city-scope on purpose, and the silent bd.dog name collision that is the real reason the dog needed a city-level import. Read it before moving anything else across the gc-toolkit / gc-toolkit-city line.
---

# Splitting gc-toolkit's city-scope half

`gc-toolkit` was the only pack in the city imported at both city and rig
scope. The pack carries orders of both scopes, so the city-scope import met
its five rig-scope orders with a registration nothing could claim, and `gc`
dropped each one with a warning on every invocation:

```
order "deferred-dispatch" declares scope = "rig": dropped the unbound
city-scope registration nothing could claim (still registered on rig(s)
gascity, gc-toolkit, shutupandlisten, signal-loom)
```

The fix moves the city-scope half into `packs/gc-toolkit-city`, imported at
city scope, and leaves `gc-toolkit` rig-scope only.

## Method

Every claim below was measured in a throwaway city, never the live one: a
directory holding a copy of `city.toml`, `pack.toml`, `packs.lock` and
`.gc/site.toml`, with `rigs/*` symlinked to the live checkouts and
`rigs/gc-toolkit` pointed at either a `git archive` export of `origin/main`
(the control) or this branch's worktree. Both sides were compared on
`gc config show`, `gc order list`, `gc formula show`, and every
`doctor/*/run.sh`.

## What the city-scope import actually contributed

Two things, and only two. The orders were not among them.

**All nine pack orders register identically without it.** The four
city-scope orders register once each at city scope, the five rig-scope
orders on four rigs each, and `gc order list` stdout is byte-identical with
the city import present or absent. Order scope is a property of the order,
so a rig-level import registers a pack's city-scope orders at city scope
perfectly well.

**`dog` disappears entirely** (roster 66 to 65), and **`session_live` is
stripped from the city-scope agents** `deacon`, `mechanik` and
`core.control-dispatcher`.

## The four city-scope orders stay in gc-toolkit

The bead proposed moving them. They register correctly where they are, and
moving them would cost something real: each one execs
`$PACK_DIR/assets/scripts/<script>.sh`, and `$PACK_DIR` for a sub-pack is
the sub-pack. Moving the orders means either forking four scripts and their
tests into the sub-pack, or writing a `../..` escape into four `exec` lines.
`check-cadence-live` also reads `$GC_PACK_DIR/orders`, so a split roster
would need a second copy of that check in a pack that ships no `doctor/`.

Forking shared content is the one thing a sibling sub-pack exists to avoid.
`packs/gascity-keeper` states the property it is built on: it composes
alongside the core pack rather than duplicating its formulas, scripts,
fragments, doctor checks or `lifecycle/`. Moving the orders would trade that
away for no measured gain.

## The dog is city-scope on purpose

The bead asked whether the dog's city scope is itself the thing to revisit.
It is not.

Warrants are filed by two detectors at different scopes. The witness is
rig-scope and files into its own rig store; the deacon is city-scope, patrols
every rig, and has no rig in hand when it files. Both write an unprefixed
`gc.routed_to`, so one city-wide pool claims warrants across every rig store.
A rig-scope dog would need the deacon to name a target rig per warrant, and
would split the kill power into four pools. `docs/authority-map.md` keeps
that power in one place deliberately.

## Why the dog needed a city-level import: a silent name collision

A `scope = "city"` agent does hoist to city scope from a rig-level import, so
the scope alone does not explain the disappearance. The `bd` pack ships its
own city-scope agent named `dog` (the Dolt maintenance dog behind
`mol-dog-backup` and friends). With gc-toolkit imported at city scope both
resolve, qualified apart as `bd.dog` and `gc-toolkit.dog`; with it imported
at rig scope only, gc-toolkit's loses its qualifier, meets `bd.dog`, and is
dropped.

Nothing reports this. `gc config show` exits 0, stderr is unchanged, and the
roster is one agent shorter.

Controlled test: with the city import removed, copying `agents/dog` to
`agents/warden` and changing nothing else brought the roster back to 66 with
`warden` present at city scope, while gc-toolkit's `dog` stayed absent. Same
pack, same scope, same import shape; the name is the discriminator. The
finding is written up in `docs/gascity-packs.md` section 7, which previously
described agent collisions as fatal at load rather than silent.

This is why the dog ships in the sub-pack rather than being made rig-scope or
left where it was: a city-scope import is what restores the qualifier.

## Consequences of the move

**The dog's address changed** from `gc-toolkit.dog` to `gc-toolkit-city.dog`.
Four sites addressed it as `{{binding_prefix}}dog`, and `binding_prefix` is
one var shared with `refinery`, `polecat` and `converse`, so it cannot carry
two bindings. They now use a `warrant_route` var defaulting to the new
address, declared in `mol-deacon-patrol`, `mol-witness-patrol` and
`mol-dog-shutdown-dance`, and forwarded on the two patrols' re-pour lines the
way `binding_prefix` and `event_timeout` already are.

The default matters more than the forwarding here. A `--root-only` patrol
pour stamps no `gc.var.*`, so the agent hand-substitutes from the raw TOML
and reads the declared default. `{{binding_prefix}}dog` against a default of
`""` hand-substitutes to a bare `dog`; `{{warrant_route}}` reads as the whole
address.

**`[global] session_live` moved rather than being copied.** A city-scope
pack's `[global]` reaches every agent in the city, so the sub-pack's single
declaration reproduces the control exactly: 46 of 66 agents on both sides,
the same 20 without (four provider entries). Declared on the rig-scope pack
it reached 41, missing precisely the city-scope agents. A city that imports
gc-toolkit without the sub-pack now gets no tmux chrome at all, which
`docs/install.md` states.

**The hooks reach the parent tree through `{{.ConfigDir}}/../..`.** Both
scripts take a config dir and resolve `tmux-pick-session.sh` and
`gc-toolkit-status-line.sh` under it, so the argument has to name the
gc-toolkit pack root, not the sub-pack. `{{.ConfigDir}}` is the only token
that resolves in a `[global]` entry; `.RigRoot`, `.CityPath`, `.PackDir`,
`.PackRoot` and `.WorkDir` all survive literally and silently no-op. The
resolved paths were confirmed executable, and the directory handed to them
was confirmed to contain both scripts they call.

## This is a coordinated change: the city config is not in this repo

The city's `pack.toml` names the import, and it lives at the city root, not
here. Landing the pack alone is not half the change, it is a regression, and
`reconcile-rig-checkouts` fast-forwards the live rig checkout every 15
minutes, so it applies itself without anyone acting.

Measured, with this branch live and the city config untouched: 65 agents
instead of 66, the gc-toolkit dog absent, `session_live` on 0 of 65 agents
instead of 46 of 66, and the five order warnings still firing. The pack no
longer declares the hooks and the sub-pack that does is not imported.

The city-root `pack.toml` edit has to land with the merge:

```toml
# was
[imports.gc-toolkit]
source = "rigs/gc-toolkit"

# now
[imports.gc-toolkit-city]
source = "rigs/gc-toolkit/packs/gc-toolkit-city"
```

The per-rig `[rigs.imports.gc-toolkit]` blocks in `city.toml` stay as they
are. Confirm with `gc order list 2>&1 >/dev/null` (silent) and
`gc config show | grep -c '^\[\[agent\]\]'` (66).

## Acceptance

Control is `origin/main` at f51aa02 in the old dual-scope shape; branch is
this worktree with `[imports.gc-toolkit-city]` at the city and gc-toolkit on
the rigs.

| Surface | Result |
|---|---|
| `gc order list` stderr | five warnings on control, none on branch |
| `gc order list` stdout | identical |
| `gc config show` stderr | identical |
| Agent roster | identical, 66 both sides |
| `session_live` coverage | 46 of 66 both sides |
| Formula roster | identical, 22 both sides |
| Formula step graphs | identical except the three edited files; step counts unchanged |
| `doctor/*/run.sh` | identical exit codes and output, except one live-city timing artifact about the gascity checkout |
| `doctor/*/run.test.sh` | green, except `check-seed-audit-current`, which fails the same two cases on control |
| `tools/lint-learned.sh` | one finding, identical on control (`step-close-env-id` at the same line) |
| `render-seed-audit.sh` output | all 14 agent prompts byte-identical, the dog's included; only the three edited formula recipes differ |

The rendered audit's `INDEX.md` moves every gc-toolkit formula's scope column
from `city` to `gc-toolkit`. That is the artifact reporting the new install
shape, since the scenario city it builds now imports the core pack on rigs
alone. `generated/seed-audit/` itself stays the committed stub, as it is on
main.
