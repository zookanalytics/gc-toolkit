#!/usr/bin/env bash
# rig-demo-capture.sh — resolve the SprintShow engine and capture one narrated,
# captioned MP4 from a demo:capture script against a rig's app.
#
# This is the executable core of the reusable rig-demo mol (formulas/
# mol-rig-demo.toml): the mechanical half — engine resolution, lint, capture,
# and a liveness check on the produced file — with no Gas City bead, convoy, or
# routing knowledge, so the mol, the video review modality, and an operator at a
# shell all drive it the same way. The agent-judgment half (which rig, which
# scenario, writing the script from a bead) stays in the formula and the
# gc-demo-script skill.
#
# The engine is @zookanalytics/sprintshow, consumed from the local `sprintshow`
# rig checkout when the city has one and the published npm package otherwise,
# per skills/demo-capture/SKILL.md. Capture is engine-driven (the engine drives
# Playwright headlessly): the only path available to a pool session, which
# carries no browser MCP.
#
# It FAILS CLOSED. A missing engine, a script the linter rejects, a capture that
# errors, or an output file that never appears all exit non-zero, because a
# capture that quietly produces nothing is the silent non-delivery the rig-demo
# mol exists to prevent.
#
# Usage:
#   rig-demo-capture.sh --script <demo.md> --output <file.mp4> \
#       ( --serve-dir <dir> | --serve <command> | --base-url <url> ) [options]
#
#   --script     demo:capture-format markdown to drive (required; must exist).
#   --output     MP4 output path (required). Write outside the repo tree — a
#                demo clip is an artifact, delivered to a PR, never committed.
#   --serve-dir  serve a static directory with the engine's built-in server.
#   --serve      spawn a dev-server command, wait for it, then tear it down.
#   --base-url   drive a server that is already running.
#                Exactly one of --serve-dir / --serve / --base-url is required;
#                it is how this rig's app is reached, the one rig-specific input.
#   --port       port for --serve / --serve-dir (default 5173).
#   --cwd        working directory for the --serve command.
#   --mode       walkthrough (default, one continuous take) | proof (one checked
#                screenshot per step).
#   --no-narrate force a silent clip even when OPENAI_API_KEY is set.
#   --music      background-music file mixed under the narration.
#   --keep       keep the engine's .captures/<run>/ working dir.
#
# Narration is best-effort: with OPENAI_API_KEY set the clip is voiced, without
# it the clip is silent and captioned. A missing key never fails the capture.
#
# $SPRINTSHOW_BIN, when set and executable, overrides engine resolution and is
# invoked in its place — the seam the hermetic test drives with a stub engine,
# and an escape hatch for a caller that has already resolved the engine.
#
# Exit: 0 captured (output exists and is non-empty), 2 bad arguments, 1 anything
# that stopped the capture.
set -u

PROG=rig-demo-capture

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

SCRIPT=""; OUTPUT=""; SERVE_DIR=""; SERVE_CMD=""; BASE_URL=""
PORT=""; SERVE_CWD=""; MODE="walkthrough"; NO_NARRATE=0; MUSIC=""; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --script)     shift; [ $# -gt 0 ] || { echo "$PROG: --script needs a value" >&2; exit 2; }; SCRIPT="$1" ;;
    --output|-o)  shift; [ $# -gt 0 ] || { echo "$PROG: --output needs a value" >&2; exit 2; }; OUTPUT="$1" ;;
    --serve-dir)  shift; [ $# -gt 0 ] || { echo "$PROG: --serve-dir needs a value" >&2; exit 2; }; SERVE_DIR="$1" ;;
    --serve)      shift; [ $# -gt 0 ] || { echo "$PROG: --serve needs a value" >&2; exit 2; }; SERVE_CMD="$1" ;;
    --base-url)   shift; [ $# -gt 0 ] || { echo "$PROG: --base-url needs a value" >&2; exit 2; }; BASE_URL="$1" ;;
    --port)       shift; [ $# -gt 0 ] || { echo "$PROG: --port needs a value" >&2; exit 2; }; PORT="$1" ;;
    --cwd)        shift; [ $# -gt 0 ] || { echo "$PROG: --cwd needs a value" >&2; exit 2; }; SERVE_CWD="$1" ;;
    --mode)       shift; [ $# -gt 0 ] || { echo "$PROG: --mode needs a value" >&2; exit 2; }; MODE="$1" ;;
    --music)      shift; [ $# -gt 0 ] || { echo "$PROG: --music needs a value" >&2; exit 2; }; MUSIC="$1" ;;
    --no-narrate) NO_NARRATE=1 ;;
    --keep)       KEEP=1 ;;
    -h|--help)    usage; exit 0 ;;
    -*) echo "$PROG: unknown flag '$1'" >&2; usage >&2; exit 2 ;;
    *)  echo "$PROG: unexpected argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# --- required inputs -----------------------------------------------------
[ -n "$SCRIPT" ] || { echo "$PROG: --script is required" >&2; usage >&2; exit 2; }
[ -n "$OUTPUT" ] || { echo "$PROG: --output is required" >&2; usage >&2; exit 2; }
[ -f "$SCRIPT" ] || { echo "$PROG: --script '$SCRIPT' does not exist" >&2; exit 1; }
case "$MODE" in walkthrough|proof) ;; *) echo "$PROG: --mode must be walkthrough or proof, not '$MODE'" >&2; exit 2 ;; esac

# Exactly one app-target. The engine needs one way to reach the app and rejects
# more than one; enforce it here so the error names the rig-specific input.
TARGETS=0
[ -n "$SERVE_DIR" ] && TARGETS=$((TARGETS + 1))
[ -n "$SERVE_CMD" ] && TARGETS=$((TARGETS + 1))
[ -n "$BASE_URL" ] && TARGETS=$((TARGETS + 1))
if [ "$TARGETS" -ne 1 ]; then
  echo "$PROG: give exactly one of --serve-dir / --serve / --base-url (got $TARGETS)" >&2
  usage >&2; exit 2
fi
[ -z "$MUSIC" ] || [ -f "$MUSIC" ] || { echo "$PROG: --music '$MUSIC' does not exist" >&2; exit 1; }

# The engine resolves relative --script / --serve-dir against its own cwd, which
# the npx-tsx form does not change; absolute paths make the capture independent
# of where this script runs.
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac; }
SCRIPT=$(abspath "$SCRIPT")
OUTPUT=$(abspath "$OUTPUT")
[ -z "$SERVE_DIR" ] || SERVE_DIR=$(abspath "$SERVE_DIR")
[ -z "$MUSIC" ] || MUSIC=$(abspath "$MUSIC")

# The output's parent must exist; the engine does not create it.
OUT_DIR=$(dirname "$OUTPUT")
mkdir -p "$OUT_DIR" || { echo "$PROG: cannot create output directory '$OUT_DIR'" >&2; exit 1; }

# >>> rig-demo-engine-resolve
# Resolve the SprintShow engine into a `sprintshow` shell function, mirroring
# skills/demo-capture/SKILL.md: prefer the local `sprintshow` rig checkout
# (guarded by package.json .name so an unrelated rig of that name is not run),
# provisioning its deps and ffmpeg on first use; fall back to the published npm
# package. $SPRINTSHOW_BIN overrides both. assets/scripts/rig-demo-capture.test.sh
# extracts this block and checks the resolution order; keep the markers.
scrub() { tr -d '\000-\037'; }
if [ -n "${SPRINTSHOW_BIN:-}" ] && [ -x "${SPRINTSHOW_BIN}" ]; then
  sprintshow() { "$SPRINTSHOW_BIN" "$@"; }
else
  command -v node >/dev/null 2>&1 || { echo "$PROG: node not found; the SprintShow engine needs Node >= 22.18. doctor/check-demo-toolchain names this gap." >&2; exit 1; }
  command -v npx  >/dev/null 2>&1 || { echo "$PROG: npx not found; it ships with Node and runs the engine." >&2; exit 1; }
  SS_DIR=""
  if command -v gc >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    SS_DIR=$(gc rig list --json 2>/dev/null | scrub | jq -r '.rigs[]? | objects | select(.name=="sprintshow") | .path // empty' 2>/dev/null | head -n1)
  fi
  if [ -n "$SS_DIR" ] && [ "$(jq -r '.name // empty' "$SS_DIR/package.json" 2>/dev/null)" = "@zookanalytics/sprintshow" ]; then
    [ -d "$SS_DIR/node_modules" ] || ( cd "$SS_DIR" && npm install ) || { echo "$PROG: 'npm install' failed in the sprintshow rig checkout" >&2; exit 1; }
    command -v ffmpeg >/dev/null 2>&1 || [ -x "$SS_DIR/node_modules/ffmpeg-static/ffmpeg" ] || ( cd "$SS_DIR" && npm run provision:ffmpeg ) || { echo "$PROG: could not provision ffmpeg (no host ffmpeg and ffmpeg-static fetch failed)" >&2; exit 1; }
    sprintshow() { npx tsx "$SS_DIR/src/cli.ts" "$@"; }
    echo "$PROG: engine = local sprintshow rig ($SS_DIR)" >&2
  else
    sprintshow() { npx --yes @zookanalytics/sprintshow "$@"; }
    echo "$PROG: engine = published @zookanalytics/sprintshow (no local rig checkout)" >&2
  fi
fi
# <<< rig-demo-engine-resolve

# --- lint before capturing ----------------------------------------------
# The linter reads the script exactly as the driver will; a script that lints
# clean is one the capture will not silently skip steps from. Fail closed on a
# lint error — a broken script captures nothing worth watching.
if ! sprintshow lint "$SCRIPT"; then
  echo "$PROG: demo script '$SCRIPT' failed lint; refusing to capture" >&2
  exit 1
fi

# --- capture --------------------------------------------------------------
set -- run "$SCRIPT" --mode "$MODE" -o "$OUTPUT"
if [ -n "$SERVE_DIR" ]; then
  set -- "$@" --serve-dir "$SERVE_DIR"
elif [ -n "$SERVE_CMD" ]; then
  set -- "$@" --serve "$SERVE_CMD"
  [ -z "$SERVE_CWD" ] || set -- "$@" --cwd "$SERVE_CWD"
else
  set -- "$@" --base-url "$BASE_URL"
fi
[ -z "$PORT" ]     || set -- "$@" --port "$PORT"
[ "$NO_NARRATE" -eq 1 ] && set -- "$@" --no-narrate
[ -z "$MUSIC" ]    || set -- "$@" --music "$MUSIC"
[ "$KEEP" -eq 1 ]  && set -- "$@" --keep

echo "$PROG: capturing $SCRIPT ($MODE) -> $OUTPUT" >&2
if ! sprintshow "$@"; then
  echo "$PROG: capture failed (sprintshow run exited non-zero)" >&2
  exit 1
fi

# --- the produced file must exist and carry bytes ------------------------
# The engine reports success on stdout, but the deliverable is the file. A zero
# exit with no MP4 is the exact silent non-delivery this fails closed on.
[ -f "$OUTPUT" ] || { echo "$PROG: capture reported success but '$OUTPUT' does not exist" >&2; exit 1; }
[ -s "$OUTPUT" ] || { echo "$PROG: capture produced '$OUTPUT' but it is empty" >&2; exit 1; }

echo "$PROG: captured $OUTPUT ($(wc -c <"$OUTPUT" | tr -d ' ') bytes)"
exit 0
