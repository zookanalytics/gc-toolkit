---
name: Gas City search for a rig's start command
description: Use when deciding where a rig declares how its app starts for a demo capture and a sitting's live copy, or when reviewing mol-rig-demo's pour that names no app target, the terminal script a video capture takes, or the rule demo-engine-lib.sh holds for which surface a demo script drives.
---

# Gas City search for a rig's start command

A rig's app starts from one command the rig declares, `ui_serve_command`, which
a city sets among the rig's `[rigs.formula_vars]` in its `city.toml`, beside the
rig's check commands. A demo capture of the rig's app and a sitting's live copy
of its UI each run it. A rig's `docs/review-demo.md`, its demo guide, is plain
text that agents read, and nothing reads lines out of it. The change grows
operational surface, so the arch check asks what Gas City already ships for it
([review-arch.md](../../docs/review-arch.md#the-checks), check 1).

## The surface

1. **A pour with no app target.** `mol-rig-demo` declines only a pour that
   names more than one of `serve_dir`, `serve_cmd` and `base_url`. A page
   script whose pour names none takes the command the `rig_name` rig declares
   as its `ui_serve_command`, which the capture step reads with
   `gc formula show mol-rig-demo --rig <rig_name> --json`. A terminal script's
   pour names none, and its shell starts at the root of the worktree the
   capture runs from.
   `serve_port`, the port of a `serve_dir` server, defaults to empty, a free
   port.
2. **More callers of the start command.** A sitting's live copy reads
   `ui_serve_command` and passes it to `gctk rig serve`, as on main. The demo
   check's capture and the demo:capture skill's Demo a PR read it the same way
   and pass it to a capture as `--serve`. The var's description in
   `mol-rig-demo` names each caller, and the demo:capture skill gives the
   command's contract where a rig's author reads it.
3. **A terminal script through the video capture.** `rig-demo-capture.sh`
   takes a terminal script with no app target, and refuses one given an app
   target or a port, as the engine does.
4. **The engine's rule for a script's surface, in one place.**
   `demo_engine_script_kind` in `demo-engine-lib.sh` reads whether a demo
   script drives a page or a terminal, by the engine's own rule.
   `rig-demo-capture.sh` and `mol-rig-demo`'s capture step read it there.

The change adds no formula var, since `mol-rig-demo` declares
`ui_serve_command` on main. It adds no metadata key, bead kind or lifecycle
state, so it carries no warrant.

## Where the search looked

Read on 2026-11-14 at upstream `gastownhall/gascity` `main`,
cf33557276ef8dbba499919bd35c30dd78163206: `internal/config/config.go`
(`Rig`, `Rig.FormulaVars`), `docs/guides/gastown-config-recipes.md` ("Default a
formula var for one rig"), `cmd/gc/cmd_formula.go` (`rigFormulaVarsForScope`,
`formulaShowJSONFromRecipe`), `internal/sling/sling.go`
(`mergeRigFormulaVars`), `docs/reference/config.md` (`Service`), and every page
under `docs/` for `dev server`, `screenshot`, `demo capture` and `playwright`,
each hit read in its context. Earlier reads for this bead, at upstream `main`
dba20336edcde787ab8c50a2ba3c6b99590f73d6 and
dc5486b999b3187b85a1e4c12c799580ad299d60, covered every page under
`docs/guides/` and `ServiceProcessConfig`.

## What Gas City ships for the need

- **`formula_vars`.** `Rig.FormulaVars` "provides rig-scoped defaults for
  formula vars. Keys match var names declared in formula `[vars.<name>]`
  blocks." The guide "Default a formula var for one rig" shows a city setting
  one under `[rigs.formula_vars]`: such values "fill formula `[vars]` values
  when a formula runs in that rig and the caller passed no explicit `--var`",
  and "`gc formula show` renders them as `(rig default="...")`".
  `gc formula show <formula> --rig <name> --json` gives each declared var's
  value for the named rig as `rig_default` (`rigFormulaVarsForScope` takes the
  named rig's map, and `formulaShowJSONFromRecipe` sets `RigDefault` on each
  declared var the map holds).
- **Nothing that names a rig's app.** No field of `Rig` names how a rig's app
  starts or how it is demoed. A city service with `kind = "proxy_process"`
  runs one process per name from the city's configuration, served under the
  controller's `/svc/`, which fits neither a capture's copy in each worktree
  nor a sitting's copy in its own tree. The docs' hits for the search terms are
  a session tutorial's screenshots and the session interrupt's API text.

## How the change composes it

- **The start command is a formula var, as the check commands are.** The
  town's `city.toml` sets gc-toolkit's `lint_command`, `affected_tests_command`
  and `ui_serve_command` side by side among its `formula_vars`. As `gctk rig`
  runs the check command a step passes and reads no var, `gctk rig serve` and
  the capture scripts run the start command their caller passes, and each
  caller reads the var.
- **What runs follows the commit.** The var holds one value for every branch of
  the rig, so it names an entry point every branch carries, and the program it
  runs is the commit's own. gc-toolkit's command runs `helm-fixture` from the
  tree, as its `affected_tests_command` calls `tools/run-tests.sh`, so an edit
  to how the app starts is an edit to that program, reviewed with the code.
- **Each caller reads the var for the rig being demoed.** `mergeRigFormulaVars`
  fills a pour's vars from the `formula_vars` of the rig of the agent the
  formula is slung to, which need not be `rig_name`. So `mol-rig-demo` reads
  `ui_serve_command` with `gc formula show mol-rig-demo --rig <rig_name>
  --json`, as the live copy reads it for its rig, and not as
  `{{ui_serve_command}}` rendered at the pour. Read as data, a `$PORT` in the
  command also reaches the copy as written, where a value rendered into the
  step's shell would expand there first.
- **A script's surface is the engine's rule.** No Gas City primitive covers
  which surface a demo script drives. The SprintShow engine's parser decides it
  (`parseDemoScript` and `surfaceOf` in the engine's `src/demo-script.ts`, at
  f99ca29), and its CLI has no command that reports it. So
  `demo-engine-lib.sh` mirrors the rule once, for the capture and the formula.

## Why the guide holds no start line

The operator, on how the branch read the guide (conversation tk-qp4a638):
"Custom parsing for random fields in a markdown file is NOT a sustainable
process, especially when calling across rigs. The consolidation could have taken
the same path as all the tests and expected a command for what to run with some
clearly defined APIs." Offered a start command the rig declares as it declares
its test commands, with the guide kept as plain text, they answered "Yes
declared command as recommended." So the capture flags stay the defined
interface, and a rig's guide says in prose what a capture needs beyond the
command, such as the directory a terminal session's commands run in. Every demo
path starts a terminal script's shell at the root of the worktree it captures
from, and a script whose commands run below the root changes into that
directory in its first step. So no value read from a guide becomes a capture
flag, and what `--cwd` opens to the capture's sandbox stays that worktree.

The capture options are the SprintShow engine's own: `--serve`, `--serve-dir`,
`--base-url`, `--port` and `--cwd` (the engine's `src/cli.ts` help, and its
README's "Run a demo" and "Terminal demos"). The pack's captures pass them on in
the engine's terms, and a caller fills `--serve` with the rig's start command.
