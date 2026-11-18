---
name: Gas City search for a demo script's surface
description: Use when reviewing how the pack learns which surface a demo script drives, the capture engine's surface command that mol-rig-demo's capture step asks through demo-engine-lib.sh, or why rig-demo-capture.sh refuses only two app targets.
---

# Gas City search for a demo script's surface

The pack learns which surface a demo script drives, a page, a terminal or an
iOS app, only from the SprintShow engine's own `surface` command. Before this
change, `demo_engine_script_kind` in `demo-engine-lib.sh` copied the engine's
parser rule in five lines of awk, because the engine's CLI could not report a
script's surface (tk-sll4qin). In conversation tk-qp4a638 the operator objected
to that kind of code ("Custom parsing for random fields in a markdown file is
NOT a sustainable process, especially when calling across rigs") and ruled to
remove the copy once the engine could answer. The engine's command merged at
sprintshow 419d65b (ss-r4hgj).

## The change

1. **The library asks the engine.** `demo_engine_script_kind` runs
   `sprintshow surface <demo.md>` through `demo_engine_cli`, inside the
   capture's sandbox, and prints the surface the answer names. It resolves the
   engine first when nothing chose one. When the engine names no surface it
   prints nothing and exits 1 with the reason, and for an engine that has no
   `surface` command the reason names the command.
2. **The formula asks only when it needs the answer.** `mol-rig-demo`'s
   capture step asks for a pour that names no app target. A script the engine
   names `page` or `ios` takes the rig's `ui_serve_command`. Any other script
   takes no app: a `terminal` script brings none up, and a script whose surface
   the engine does not name, or names as a surface the pack does not drive, is
   handed to the capture with no app, so the engine refuses it if it needs one.
   `ios` takes the start command because the awk rule read an iOS script as a
   page script, so a no-target pour gave it the start command on main, and
   tk-wozuj9r builds the pack's iOS capture on that.
3. **The capture reads no surface.** `rig-demo-capture.sh` dropped both of its
   surface checks, because the engine makes each of them itself. It still
   refuses two app targets, which the engine does not refuse.

## What the engine does, read at sprintshow b4d0b82

- `surfaceCommand` in `src/cli.ts` prints `{"surface": surfaceOf(demo)}` as
  the only thing on stdout and exits 0. A script that is missing or does not
  parse throws, and `main`'s catch prints the reason on stderr and exits 1, with
  nothing on stdout. `surfaceOf` in `src/demo-script.ts` answers `terminal`,
  `ios` or `page`.
- An engine with no `surface` command takes the default branch of `main`'s
  switch: `unknown command: surface` on stderr, its help on stdout, exit 1. The
  branch reads the same at 9e8d75f, before the command. The published package's
  versions are 0.0.0-stage and 0.1.0, both released on 2026-11-13, before
  419d65b, so a city that runs the published package has no `surface` command
  until the engine publishes a release that carries it.
- `serverFor` in `src/run.ts` hands an iOS app script to `ensureIosApp` and a
  page script to `ensureServer`, and refuses a terminal script given
  `--base-url`, `--serve`, `--serve-dir` or `--port`. `ensureServer` in
  `src/server.ts` refuses a page script given none of the three ("no server"),
  and `ensureIosApp` refuses an iOS app script given `--serve-dir` or none
  ("no app"). These run before a browser or a device is spent.
- `ensureServer` does not refuse two app targets. It takes `--base-url`, then
  `--serve-dir`, then `--serve`, and says nothing of the others.

So `rig-demo-capture.sh`'s refusals of an app target or `--port` for a
terminal script, and of no app target for a page script, were copies of engine
refusals, and they are gone. Its refusal of two app targets copies none, so it
stays. Its captures now need no `surface` command, so they run on an engine
that has none.

What dropping the copies costs: a script given the wrong app target is refused
after the engine resolves and lints it, and exits 1 instead of 2, with the
engine's own message. A terminal script given `--serve` starts its copy and
stops it before the engine refuses.

## Where the search looked

Read on 2026-11-17 at upstream `gastownhall/gascity` `main`,
bc6bc28712204b83fb2145147a8038c021322271: every page under `docs/`, less the
generated schemas and the diagrams, for `demo script`, `demo capture`,
`sprintshow`, `playwright`, `screenshot` and the word `surface`. The hits are a
session tutorial's screenshots and `surface` used for an API's, a CLI's or a
config's set of commands. The earlier search for this capture, in
`specs/tk-sll4qin/gas-city-search.md`, read `Rig.FormulaVars` and
`gc formula show`, which hold a value a city sets for a rig, not a fact about a
file on a branch.

## What Gas City ships for the need

Nothing. Which surface a demo script drives is the capture engine's decision,
made by its parser from the script, and Gas City has no notion of a demo
script. The engine's `surface` command is the primitive that covers the need,
and the pack composes it.

## How the change composes it

- The ask runs through `demo_engine_cli`, the one place that runs the engine's
  CLI inside the capture's sandbox, so it takes the same engine and the same
  sandbox as the capture that follows.
- An executable run in the engine's place has one name, the library's
  `DEMO_ENGINE_BIN`. `rig-demo-capture.sh` had a second, `SPRINTSHOW_BIN`, which
  it copied into the library's before each capture, so a pour that set only
  that one asked the default engine for the surface and captured with the
  other (review tk-w4i1vzo). The capture now reads the library's name, and
  nothing in the city set the other.
- The answer is read as the command's contract states it: one JSON object on
  stdout, its `surface` a string. Anything else names no surface.
- The change adds no command, flag, metadata key, bead kind or state. It moves
  a fact the pack copied back to the tool that owns it, and removes two checks
  and the capture's second name for the engine override.
