#!/usr/bin/env bash
# demo-engine-lib.sh — the one definition of how a demo capture finds the
# SprintShow engine and provisions the browser it launches. Sourced, never
# executed.
#
# The engine is the npm package @zookanalytics/sprintshow. A city that has the
# engine's source as a rig uses that checkout: the rig `gc rig list` names
# sprintshow, taken only when its package.json names the package, so an
# unrelated rig of that name is passed over. A checkout without node_modules
# has its dependencies installed first. Any other city uses the published
# package through npx.
#
# The browser is installed through the engine's own Playwright before every
# capture, local or published. The engine launches the chromium-headless-shell
# revision its Playwright pins, so only that Playwright's installer knows which
# build to fetch and where to keep it. The installer skips a build that is
# already installed, so a capture on a provisioned host downloads nothing.
#
#   demo_engine_resolve  Finds the engine and installs what it needs before a
#                        capture: a checkout's dependencies, and the browser.
#                        Sets DEMO_ENGINE_DIR to the checkout, or to empty for
#                        the published package, and says on stderr which
#                        engine it chose. The installers write to stderr too,
#                        so the caller's stdout carries only its own report.
#                        Returns 1, having said why on stderr, when an install
#                        fails or the published package has no npx to run it.
#   demo_engine_find     The lookup alone: sets DEMO_ENGINE_DIR the same way,
#                        installs nothing, and returns 0.
#
# DEMO_ENGINE_PACKAGE names the package, for the caller's own npx call on the
# published path. Messages start with the caller's $PROG.
#
# Each capture keeps what only it needs. rig-demo-capture.sh provisions ffmpeg
# for a checkout and runs the engine's CLI; demo-screenshot.sh holds Node to the
# floor its driver needs and runs its driver. demo-engine-lib.test.sh checks
# this policy through both, and fails when either stops sourcing this file or
# runs a step of it itself.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=demo-engine-lib.sh
#   . "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh" >&2; exit 1; }
#   demo_engine_resolve || exit 1

DEMO_ENGINE_PACKAGE=@zookanalytics/sprintshow

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

_demo_engine_say() { echo "${PROG:-demo-engine-lib}: $1" >&2; }

demo_engine_find() {
  local dir=""
  DEMO_ENGINE_DIR=""
  if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    dir=$(gc rig list --json 2>/dev/null | scrub | jq -r '.rigs[]? | objects | select(.name=="sprintshow") | .path // empty' 2>/dev/null | head -n1)
  fi
  if [ -n "$dir" ] && [ "$(jq -r '.name // empty' "$dir/package.json" 2>/dev/null)" = "$DEMO_ENGINE_PACKAGE" ]; then
    DEMO_ENGINE_DIR=$dir
  fi
  return 0
}

demo_engine_resolve() {
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
