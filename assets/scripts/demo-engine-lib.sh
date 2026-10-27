#!/usr/bin/env bash
# demo-engine-lib.sh — the one definition of how a demo capture finds the
# SprintShow engine, provisions the browser it launches, and runs its CLI.
# Sourced, never executed.
#
# The engine is the npm package @zookanalytics/sprintshow. A city that has the
# engine's source as a rig uses that checkout: the rig `gc rig list` names
# sprintshow, taken only when its package.json names the package, so an
# unrelated rig of that name is passed over. A checkout without node_modules
# has its dependencies installed first, and its CLI runs from its TypeScript
# source under node, as the engine's own package scripts run it. Any other city
# uses the published package through npx.
#
# The engine's package requires Node 22.18 or later, and a checkout's CLI needs
# that release too, because it is where node starts stripping TypeScript without
# a flag. So Node is checked against that floor before anything is installed.
#
# The browser is installed through the engine's own Playwright before every
# capture, local or published. The engine launches the chromium-headless-shell
# revision its Playwright pins, so only that Playwright's installer knows which
# build to fetch and where to keep it. The installer skips a build that is
# already installed, so a capture on a provisioned host downloads nothing.
#
#   demo_engine_resolve  Checks Node against the engine's floor, finds the
#                        engine, and installs what it needs before a capture: a
#                        checkout's dependencies, and the browser. Sets
#                        DEMO_ENGINE_DIR to the checkout, or to empty for the
#                        published package, and says on stderr which engine it
#                        chose. The installers write to stderr too, so the
#                        caller's stdout carries only its own report. Returns 1,
#                        having said why on stderr, when Node is missing or
#                        below the floor, an install fails, or the published
#                        package has no npx to run it.
#   demo_engine_find     The lookup alone: sets DEMO_ENGINE_DIR the same way,
#                        installs nothing, and returns 0.
#   demo_engine_cli      Runs the CLI of the engine demo_engine_resolve chose
#                        with the arguments it is given, in the caller's working
#                        directory, and returns the CLI's exit status.
#
# DEMO_ENGINE_PACKAGE names the package. Messages start with the caller's $PROG.
#
# Each capture keeps what only it needs. rig-demo-capture.sh provisions ffmpeg
# for a checkout and records a clip with the CLI's `run`; demo-screenshot.sh
# saves a PNG with its `screenshot`. The demo:capture skill's examples run the
# engine through this file too. demo-engine-lib.test.sh checks this policy
# through each capture and through the skill's examples, and fails when any of
# them stops sourcing this file or runs a step of it itself.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=demo-engine-lib.sh
#   . "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh" >&2; exit 1; }
#   demo_engine_resolve || exit 1
#   demo_engine_cli <command> <arguments...>
# An agent's shell has no script beside it, so the skill sources this file from
# the pack gc loaded, as "$(gc <binding> scripts-dir)/demo-engine-lib.sh".

DEMO_ENGINE_PACKAGE=@zookanalytics/sprintshow

# The directory this library is sourced from, where rig-map.sh sits beside it.
# bash names the file being sourced in BASH_SOURCE, and zsh in $0.
DEMO_ENGINE_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)

_demo_engine_say() { echo "${PROG:-demo-engine-lib}: $1" >&2; }

_demo_engine_node_ok() {
  local ver major rest minor
  if ! command -v node >/dev/null 2>&1; then
    _demo_engine_say "node not found; the SprintShow engine needs Node >= 22.18. doctor/check-demo-toolchain names this gap."
    return 1
  fi
  ver=$(node --version 2>/dev/null | sed 's/^v//')
  major=${ver%%.*}; rest=${ver#*.}; minor=${rest%%.*}
  case "$major" in ''|*[!0-9]*) major=0 ;; esac
  case "$minor" in ''|*[!0-9]*) minor=0 ;; esac
  if [ "$major" -lt 22 ] || { [ "$major" -eq 22 ] && [ "$minor" -lt 18 ]; }; then
    _demo_engine_say "Node ${ver:-unknown} is below the engine's floor of 22.18"
    return 1
  fi
}

demo_engine_find() {
  local dir=""
  DEMO_ENGINE_DIR=""
  if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    dir=$("$DEMO_ENGINE_LIB_DIR/rig-map.sh" | jq -r '.rigs[]? | objects | select(.name=="sprintshow") | .path // empty' 2>/dev/null | head -n1)
  fi
  if [ -n "$dir" ] && [ "$(jq -r '.name // empty' "$dir/package.json" 2>/dev/null)" = "$DEMO_ENGINE_PACKAGE" ]; then
    DEMO_ENGINE_DIR=$dir
  fi
  return 0
}

demo_engine_resolve() {
  _demo_engine_node_ok || return 1
  demo_engine_find
  if [ -n "$DEMO_ENGINE_DIR" ]; then
    if [ ! -d "$DEMO_ENGINE_DIR/node_modules" ] && ! ( cd "$DEMO_ENGINE_DIR" && npm install ) >&2; then
      _demo_engine_say "'npm install' failed in the sprintshow rig checkout"
      return 1
    fi
    if ! ( cd "$DEMO_ENGINE_DIR" && npm run provision:browser ) >&2; then
      _demo_engine_say "could not provision the browser ('npm run provision:browser' failed in the sprintshow rig checkout)"
      return 1
    fi
    _demo_engine_say "engine = local sprintshow rig ($DEMO_ENGINE_DIR)"
  else
    if ! command -v npx >/dev/null 2>&1; then
      _demo_engine_say "npx not found; it ships with Node and runs the published engine"
      return 1
    fi
    if ! npx --yes --package="$DEMO_ENGINE_PACKAGE" -- playwright install chromium-headless-shell >&2; then
      _demo_engine_say "could not provision the browser (the published engine's 'playwright install chromium-headless-shell' failed)"
      return 1
    fi
    _demo_engine_say "engine = published $DEMO_ENGINE_PACKAGE (no local rig checkout)"
  fi
}

demo_engine_cli() {
  if [ -n "${DEMO_ENGINE_DIR:-}" ]; then
    node "$DEMO_ENGINE_DIR/src/cli.ts" "$@"
  else
    npx --yes "$DEMO_ENGINE_PACKAGE" "$@"
  fi
}
