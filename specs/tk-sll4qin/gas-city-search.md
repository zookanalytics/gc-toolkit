---
name: Gas City search for a rig's demo guide naming its app
description: Use when deciding whether a demo capture or a sitting's live copy of a rig's UI could take the rig's app from something Gas City ships instead of the rig's docs/review-demo.md, such as a rig's formula_vars or a city service, or when reviewing the --guide option, the terminal script a video capture takes, mol-rig-demo's pour that names no app target, or the live copy's serve command.
---

# Gas City search for a rig's demo guide naming its app

A rig names how to demo it in its `docs/review-demo.md`, and a capture can take
the rig's app from that guide. A sitting's live copy of the rig's UI runs the
command the guide names too. The change adds operational surface and retires a
formula var, so the arch check asks what Gas City already ships for it
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The surface

1. **The guide's lines.** The section `## Bring the app up` of a rig's
   `docs/review-demo.md` names the app a capture brings up, in the options the
   capture takes: `**Serve:**`, `**Serve dir:**` or `**Base URL:**`, and
   `**Cwd:**` and `**Port:**`. `demo_engine_guide` in `demo-engine-lib.sh`
   reads them. A `**Serve:**` command runs as a copy that `gctk rig serve`
   runs from the worktree's root, on a port of its own that it gets as
   `$PORT`, so `**Port:**` names only a `**Serve dir:**` server's port, and
   `**Cwd:**` names where a terminal script's shell starts.
2. **`--guide <worktree>`.** `rig-demo-capture.sh` and `demo-screenshot.sh`
   take the app the guide in that worktree names. It is a second way of
   naming the options a capture already takes, not an option of its own.
3. **A terminal script through the video capture.** `rig-demo-capture.sh`
   reads a script's kind as the engine's parser does, takes a terminal script
   with no app target, and refuses one given an app target or a port, as the
   engine does.
4. **A pour with no app target.** `mol-rig-demo` declines only a pour that names
   more than one of `serve_dir`, `serve_cmd` and `base_url`. A pour that names
   none hands the capture `--guide` and the worktree it makes, and `serve_port`,
   the port of a `serve_dir` server, defaults to empty, a free port.
5. **The live copy's serve command, and a retired var.** A sitting's live copy
   of a rig's UI, which the `converse-edit` skill starts through
   `gctk rig serve`, runs the command on the guide's `**Serve:**` line, which
   `demo_engine_guide` reads at the tree's commit. The skill sources the library
   a capture uses, so no flag or verb is added. A guide that names no serve
   command, such as one whose app is a static directory or a running address,
   gives no live copy. `mol-rig-demo` no longer declares `ui_serve_command`, the
   var a city set among a rig's `formula_vars` for the live copy's command.
   `ui_publish_command` and `ui_address_pattern` stay, because they name the
   city's publisher and not the rig's app.

The change adds no metadata key, bead kind or lifecycle state, so it carries no
warrant.

## Where the search looked

Read on 2026-11-13 at upstream `gastownhall/gascity` `main`,
dba20336edcde787ab8c50a2ba3c6b99590f73d6: `docs/reference/config.md`, every
page under `docs/guides/`, `cmd/gc/cmd_formula.go`, `cmd/gc/cmd_sling.go` and
`internal/config/config.go`. The terms were `formula_vars`, `FormulaVars`, the
fields of `[[rigs]]`, `[defaults.rig]`, `demo`, `screenshot`, `playwright`,
`video`, `preview`, `base_url`, `serve_cmd`, `serve_dir` and `dev server`, then
each hit in its context. Source is cited by package and symbol at that commit.

The live copy's part was read on 2026-11-14 at upstream `gastownhall/gascity`
`main`, dc5486b999b3187b85a1e4c12c799580ad299d60: `docs/reference/config.md`
(`Rig`, `Service`, `ServiceProcessConfig`), `internal/sling/sling.go`,
`cmd/gc/cmd_formula.go`, `cmd/gc/order_dispatch.go`,
`internal/formula/parser.go` and `internal/config/config.go`. The terms were
`formula_vars`, `FormulaVars`, `service`, `proxy_process`, `command`,
`unknown var`, `undeclared` and `not declared`, then each hit in its context.

## What Gas City ships near the need

- **Rig configuration.** `Rig` in the config reference
  (`docs/reference/config.md`, `config.Rig` in `internal/config`) names the
  rig's checkout, bead prefix, default branch and merge strategy, its
  suspension, formula layers, imports, session cap and sleep, overrides,
  patches, sling targets, federation, namespace, Dolt host and port, store
  proxy timeout, and `formula_vars`. No field names a rig's app, how it is
  served, or how it is demoed. `[defaults.rig]` (`PackRigDefaults`) holds only
  imports.
- **`formula_vars`** "provides rig-scoped defaults for formula vars"
  (`config.Rig.FormulaVars`), and the guide "Default a formula var for one rig"
  (`docs/guides/gastown-config-recipes.md`) shows it filling a var "when a
  formula runs in that rig and the caller passed no explicit `--var`".
  `rigFormulaVarsForScope` in `cmd/gc/cmd_formula.go` reads them. A city could
  set `serve_cmd`, `serve_dir` or `base_url` there for each rig, and
  `mol-rig-demo` would read it with no code in the pack.
- **A city service.** `Service` with `kind = "proxy_process"`
  (`docs/reference/config.md`) runs the argv in its `process.command`
  (`ServiceProcessConfig`) as "a controller-supervised local process that is
  reverse-proxied under /svc/{name}". A city declares each one, by a name unique
  in the workspace.
- Nothing in the pages or the source searched names a demo, a screenshot or a
  dev server.

## Why `formula_vars` does not cover the need

- **It lives outside the rig's repository.** A rig's value sits in the city's
  `city.toml`. How an app comes up changes with its code, such as a new dev
  command or a moved directory, and a capture of a commit must bring up that
  commit's app. The guide is read at the commit the demo shows. A city value
  holds one answer for every commit, and nothing the rig reviews changes it.
  `app_reads_city` lives in `formula_vars` for the opposite reason: no change a
  rig reviews may remove it ([its search](../tk-vd66j1.14/gas-city-search.md)).
- **A pour reads it, and any other reader gets the city's one value.**
  `formula_vars` fill a formula's vars when the formula runs in the rig. The
  demo check captures inside a review session, and an agent demoing a PR
  captures from its own shell, and neither pours `mol-rig-demo`. Such a caller
  can read a rig's value with `gc formula show mol-rig-demo --rig <rig>
  --json`, as gc-toolkit's board capture read `ui_serve_command` before this
  change, but what it reads is still the city's value and not the commit's.
- **The live copy's command is the guide's too.** A live copy runs the app of
  the tree a sitting edits, so its command belongs to that tree's commit, as a
  capture's does. `formula_vars` holds one city value for every tree of the
  rig. Before this change the live copy read it as `ui_serve_command`, while
  gc-toolkit's guide named the same command on its `**Serve:**` line, and only
  helm-fixture's test held the two equal. A city service names one process per
  name in the city's configuration, served under the controller's `/svc/`, and
  no commit of a rig changes its command. So the live copy reads the guide's
  line through the reader a capture uses, and the pack stops declaring the var.
  The operator ruled the start command into one home: "Yes, file a follow-up.
  One place should be defined and populated" (conversation tk-k4nxcpk), then
  "yes do it" to making that change inside this PR (conversation tk-svexk7u).
- **A city's leftover value is inert.** The town's `city.toml` keeps
  `ui_serve_command` among gc-toolkit's `formula_vars` until the mechanik
  removes it once this lands (tk-4rzu5aq). Gas City carries a key that no
  formula declares and checks nothing about it. `mergeRigFormulaVars`
  (`internal/sling/sling.go`) and `orderFormulaVars`
  (`cmd/gc/order_dispatch.go`) fold every key of a rig's `formula_vars` into
  the vars of each formula slung or ordered in that rig.
  `collectVarValidationErrors` (`internal/formula/parser.go`), which
  `ValidateVars` and `ValidateProvidedVarDefs` call, checks only the vars a
  formula declares, and `formulaShowJSONFromRecipe` (`cmd/gc/cmd_formula.go`)
  gives a rig default only for a declared var. Every `mol-polecat-work` sling
  in gc-toolkit already passes `app_reads_city` and the three `ui_` keys, which
  that formula does not declare. No formula or order in the pack names
  `{{ui_serve_command}}`, so the leftover value fills nothing.
- **The operator ruled the guide the one place.** "docs/review-demo.md should
  be the singular doc" (the operator, 2026-11-12, quoted in tk-sll4qin).

The capture options the guide names are the SprintShow engine's own: `--serve`,
`--serve-dir`, `--base-url`, `--port` and `--cwd` (the engine's `src/cli.ts`
help, and its README's "Run a demo" and "Terminal demos"). The engine reads
them only from its command line, so the guide names them for the pack's
captures to pass on, in the engine's terms.
