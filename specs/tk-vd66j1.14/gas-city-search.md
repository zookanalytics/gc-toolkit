---
name: Gas City search for a capture of a rig's own app on this host
description: The search the arch check asks for on the label that keeps a rig's own servers out of a demo capture's reach, app_reads_city among a rig's formula vars in city.toml, and on how a capture tells whose server answers a --base-url on this host. Read it when deciding whether either can move onto something Gas City ships, such as a rig setting that is not a formula var, or a command that names the process behind a port.
---

# Gas City search for a capture of a rig's own app on this host

A demo capture can reach a rig's own app on this host through `--base-url`,
unless the city labels the rig as one whose app reads the city. The capture
sandbox otherwise holds every capture to its own server's loopback port. That
adds operational surface: a formula var in which the city labels a rig, and an
allowance in `demo_engine_cli` with the reads that decide it. So the arch check
asks what Gas City already ships for each
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

The label is a setting Gas City already lets a city make for each rig, a value
in the rig's `formula_vars`, and a capture reads it the way Gas City shows it,
through `gc formula show --rig`. Gas City ships no command that names the
process behind a port, so the library asks `lsof`, the tool Gas City uses for
the same two reads and lists among the universal dependencies its doctor
checks. The change also composes the rig map's `hq` entry, which keeps the
city's own repository from ever counting as a rig's.

## The surface

1. **The label.** `mol-rig-demo` declares the var `app_reads_city`, with the
   default `"false"`. A city labels a rig whose app reads the city by setting
   `app_reads_city = "true"` among the rig's `[rigs.formula_vars]` in
   `city.toml`. `demo-engine-lib.sh` reads the rig's value with
   `gc formula show mol-rig-demo --rig <rig> --json`. A read that fails, a
   formula that declares no such var, and any value but `"false"` each count as
   the label. The rig whose repository holds the library, the pack's own
   source, counts as labelled whatever `city.toml` says.
2. **The allowance.** `demo_engine_cli` takes a `--base-url` on this host when
   the URL's port is none that a variable pointing at the city names, and every
   process of this user that listens on the port works in a worktree of a rig
   that carries no label. A rig's checkout, which holds its store, is no such
   worktree, and neither is the city's own repository nor a directory in no
   rig's repository. The sandbox then opens that one port. Every other
   `--base-url` on this host keeps the refusal, which names why.

The change adds no metadata key, bead kind or lifecycle state, so it carries no
warrant.

## Where the search looked

Read on 2026-11-04 at upstream `main`:

- `gastownhall/gascity` 3203354c33ae: `docs/`, `engdocs/`, `cmd/` and
  `internal/`.
- `gastownhall/gascity-packs` 796d7ecd73cf, every pack directory.

The terms were `formula_vars`, the fields of `[[rigs]]`, `patches`, `env`,
`default_branch`, `hq`, `lsof`, `ListenPort`, `LISTEN`, `cwd`, `preview`,
`base_url`, `base-url`, `dev server`, `localhost:`, `screenshot`, `playwright` and
`sandbox-exec`, then each hit in its context. For the label, the same gascity
commit was read again on 2026-11-05: the whole of `config.Rig` in
`internal/config/config.go`, and `gc formula show` in `cmd/gc/cmd_formula.go`.
Pages are cited by title and link, and source by package and symbol at those
commits.

## What Gas City ships near the label

- **Rig configuration.**
  [Gas City Configuration](https://docs.gascity.com/reference/config#rig),
  `Rig` (`config.Rig` in `internal/config`). Its fields name the rig's
  checkout, bead prefix, default branch and merge strategy, its suspension, its
  formula layers and pack imports, its session cap and idle sleep, patches to
  its agents, its sling targets, its federation and namespace, its Dolt host and
  port, its store proxy's idle timeout, and `formula_vars`. No field labels a
  rig, and none states what the rig's app reads. The label adds no field to
  `[[rigs]]`: it is a value in one the rig already has.
- **`formula_vars`** "provides rig-scoped defaults for formula vars. Keys match
  var names declared in formula `[vars.<name>]` blocks"
  (`config.Rig.FormulaVars`). The label is such a var: `mol-rig-demo` declares
  it, and a rig's value lives in the city's `city.toml`, outside the rig's
  repository, so no change the rig reviews can remove it. A capture runs from a
  review's step, from `mol-rig-demo`'s step and from an agent's own shell under
  the demo:capture skill, so the library reads the value itself rather than
  through one formula's step text.
- **`gc formula show --rig`**
  ([CLI reference](https://docs.gascity.com/reference/cli#gc-formula-show))
  prints each var a formula declares, with its `default`, and with the rig's own
  value as `rig_default` (`formulaVarJSON.RigDefault`, filled from
  `rigFormulaVarsForScope` in `cmd/gc/cmd_formula.go`). The library reads that
  output: the rig's value when present, else the default. It names the rig with
  `--rig`, because `resolveFormulaScope` refuses an explicit `--rig` that names
  no rig, while a `GC_RIG` that names none falls through to the working
  directory and then to the city, whose scope carries no rig's vars.
  `gc config show --json` (`newConfigShowCmd` in `cmd/gc/cmd_config.go`) dumps
  the whole resolved city configuration, each rig's `formula_vars` included,
  but no formula's default, so the library would have to restate the default
  for a rig that sets nothing. `gc formula show` resolves the var as a pour
  does, the rig's value over the formula's default, and it is the read the
  refinery already makes for a rig's check commands.
- **Agent patches' `env`**
  ([AgentOverride](https://docs.gascity.com/reference/config#agentoverride),
  `config.AgentOverride.Env`) put a variable in a session's environment. Any
  command line can unset the same variable, so it cannot hold a label a capture
  must honour.
- **The rig map.** `gc rig list --json`
  ([CLI reference](https://docs.gascity.com/reference/cli#gc-rig-list);
  `RigListItem` in `cmd/gc/cmd_rig.go`) lists each rig's name, path, prefix,
  default branch, `hq`, suspension, running state, sling targets, federation,
  namespace and store state. It carries no label. Its first entry is the city
  itself, with `hq` true. This change composes that field: a server in a
  worktree of the city's own repository never counts as a rig's own app. The
  library takes from the map the name it passes to `--rig`.
- **The pack's own repository.** A city names where it imports a pack from in
  the import's `source` (`config.Import.Source` in `internal/config`), a local
  path or a git URL, and Gas City loads a git import from a cached copy. This
  city imports gc-toolkit from its rig's checkout, a local path, so the library
  runs from there. The library finds the rig whose repository holds it with the
  read it uses for every directory: the repository's git common directory,
  matched against the rig map. A city that runs the pack from a copy in no
  rig's repository, such as the cache of a git import, labels its rig of the
  pack's source in `city.toml`.

## What Gas City ships near the owner of a port

- **No command names the process behind a port, or its working directory.**
  Gas City makes both reads internally. `portsByPIDFromLsof` in
  `cmd/gc/dolt_cleanup_discovery.go` lists listening ports with
  `lsof -nP -iTCP -sTCP:LISTEN` to find Dolt servers for `gc dolt cleanup`, and
  `liveWorktreeCwdEnumerator` in `cmd/gc/bead_worktree_liveness_fallback.go`
  lists each process's working directory with `lsof -a -d cwd -F0pn` to tell
  which worktrees a live process works in. The library makes the same two
  reads. Gas City's doctor checks that `lsof` is installed, among its universal
  dependencies (`doctor.NewBinaryCheck("lsof", ...)` in `cmd/gc/cmd_doctor.go`),
  so a host that runs Gas City has it.
- **A working directory alone does not identify a rig's app.** On the city's
  host, its Dolt server ran with its working directory in one rig's checkout,
  wherever the command that started it ran. So a server counts only from a
  worktree of the rig, never from its checkout, and a port that a variable
  pointing at the city names is refused whoever listens there. A session's
  environment names the Dolt server's port in `GC_DOLT_PORT` and
  `BEADS_DOLT_SERVER_PORT`.
- **Nothing contains one command.** The sandbox's own record,
  [specs/tk-r9wui2m/gas-city-search.md](../tk-r9wui2m/gas-city-search.md),
  found no Gas City primitive that does. This change keeps that sandbox and
  opens one more port in it.

## What gascity-packs ships near it

- gstack's `qa` skill (`gstack/skills/qa/SKILL.md`) drives a local app with its
  own browser, trying `http://localhost:3000`, `:4000` and `:8080`, with no
  sandbox and no check of whose server answers there.
- The `base_url` hits name the supervisor's API (`GC_API_BASE_URL`), not an app
  a capture drives.
- No pack labels a rig by what its app reads.
