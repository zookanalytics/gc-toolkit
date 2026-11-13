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
# rig checkout when the city has one and the published npm package otherwise.
# demo-engine-lib.sh finds it, provisions its browser and runs its CLI, as it
# does for the screenshot capture. Capture is engine-driven (the engine drives
# Playwright headlessly): the only path available to a pool session, which
# carries no browser MCP.
#
# A script drives one of the engine's two surfaces, and the engine's parser
# tells them apart: a script that declares **Terminal:** among its head lines,
# the lines above its first ## heading, drives a bash session in the engine's
# own terminal, and any other drives an app in a page. Both take the same
# options. A page script needs the app it drives: one app target, named with
# the flags below or taken from the rig's demo guide with --guide. A terminal
# script brings up no app, and the engine refuses an app target or a --port
# for one, so this script refuses them first. Its shell starts in --cwd.
#
# The engine runs inside the sandbox demo-engine-lib.sh defines, where the live
# city cannot be reached, so a --serve command, a terminal's commands or a page
# that reads the city's stores or its API fails there, and the clip shows the
# app on fixture data, or shows the failure, and never live state. The one
# server outside the sandbox a clip can reach is a rig's app that --base-url
# names, as below.
#
# It FAILS CLOSED. A host with no sandbox, a capture the sandbox refuses, a
# missing engine, a browser that cannot be installed, a script the linter
# rejects, a capture that errors, or an output file that never appears all exit
# 1, because a capture that quietly produces nothing is the silent non-delivery
# the rig-demo mol exists to prevent. A clip in which a step failed its proof is
# a different result: the engine exits non-zero for it too, but the clip shows
# what failed, so it exits 3 and names the clip and the working files the engine
# kept.
#
# Usage:
#   rig-demo-capture.sh --script <demo.md> --output <file.mp4> \
#       [ --serve-dir <dir> | --serve <command> | --base-url <url> | --guide <worktree> ] [options]
#
#   --script     demo:capture-format markdown to drive (required; must exist).
#   --output     MP4 output path (required). Write outside the repo tree — a
#                demo clip is an artifact, delivered to a PR, never committed.
#   --serve-dir  serve a static directory with the engine's built-in server.
#   --serve      spawn a dev-server command, wait for it, then tear it down.
#                With --port, the command's environment carries the port as
#                PORT, and --port 0 picks a free one first.
#   --base-url   drive a deployed preview, or an app that a worktree of a rig
#                serves on this host. Any other server on this host is refused,
#                as is the app of a rig that city.toml sets to
#                app_reads_city = "true".
#                A page script takes exactly one of --serve-dir / --serve /
#                --base-url, or --guide; it is how this rig's app is reached. A
#                terminal script takes none of the three.
#   --guide      a worktree of the rig at the commit to demo, whose demo guide,
#                the docs/review-demo.md that commit carries, names the app in
#                its section "Bring the app up": its app target, --cwd and
#                --port, each directory relative to the worktree's root. The
#                command, or a terminal script's shell, runs in the guide's
#                --cwd, or at the worktree's root when the guide names none.
#                A terminal script takes no app target, so only the directory
#                applies to one. --guide names the whole app, so it takes no
#                app target, --cwd or --port beside it.
#   --port       port for --serve (default 5173) or --serve-dir (default: a free
#                port). A port that a server already answers on is refused.
#   --cwd        working directory for the --serve command, the directory a
#                relative --serve-dir resolves against, and where a terminal
#                script's shell starts (default: here).
#   --mode       walkthrough (default, one continuous take) | proof (one checked
#                screenshot per step).
#   --no-narrate force a silent clip even when OPENAI_API_KEY is set.
#   --music      background-music file mixed under the narration.
#   --keep       keep the engine's .captures/<run>/ working dir.
#
# Narration is best-effort: with OPENAI_API_KEY set the clip is voiced, without
# it the clip is silent and captioned. A missing key never fails the capture.
# The last line says whether the clip is narrated or silent.
#
# $SPRINTSHOW_BIN, when set and executable, overrides engine resolution and is
# invoked in its place, inside the same sandbox — the seam the hermetic test
# drives with a stub engine, and an escape hatch for a caller that has already
# resolved the engine.
#
# Exit: 0 captured and every step's proof held (output exists and is non-empty),
# 3 captured but at least one step failed its proof, 2 bad arguments, a page
# script with no app among them, or a guide that names its app wrongly, 1
# anything that stopped the capture.
set -u

PROG=rig-demo-capture
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=demo-engine-lib.sh
. "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh beside this script" >&2; exit 1; }

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

SCRIPT=""; OUTPUT=""; SERVE_DIR=""; SERVE_CMD=""; BASE_URL=""; GUIDE=""
PORT=""; SERVE_CWD=""; MODE="walkthrough"; NO_NARRATE=0; MUSIC=""; KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --script)     shift; [ $# -gt 0 ] || { echo "$PROG: --script needs a value" >&2; exit 2; }; SCRIPT="$1" ;;
    --output|-o)  shift; [ $# -gt 0 ] || { echo "$PROG: --output needs a value" >&2; exit 2; }; OUTPUT="$1" ;;
    --serve-dir)  shift; [ $# -gt 0 ] || { echo "$PROG: --serve-dir needs a value" >&2; exit 2; }; SERVE_DIR="$1" ;;
    --serve)      shift; [ $# -gt 0 ] || { echo "$PROG: --serve needs a value" >&2; exit 2; }; SERVE_CMD="$1" ;;
    --base-url)   shift; [ $# -gt 0 ] || { echo "$PROG: --base-url needs a value" >&2; exit 2; }; BASE_URL="$1" ;;
    --guide)      shift; [ -n "${1:-}" ] || { echo "$PROG: --guide needs a value" >&2; exit 2; }; GUIDE="$1" ;;
    --port)       shift; [ $# -gt 0 ] || { echo "$PROG: --port needs a value" >&2; exit 2; }; PORT="$1" ;;
    --cwd)        shift; [ -n "${1:-}" ] || { echo "$PROG: --cwd needs a value" >&2; exit 2; }; SERVE_CWD="$1" ;;
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

# The engine resolves relative --script / --serve-dir against its own cwd, which
# its CLI shares with this script; absolute paths make the capture independent
# of where this script runs.
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac; }

# --- the script's surface, and the app it drives ---------------------------
# The engine's parser reads a script as a terminal script when a line above its
# first ## heading declares **Terminal:**, in any case, each line read without
# the blanks around it (parseDemoScript in the engine's src/demo-script.ts).
KIND=$(awk '
  { l = $0; sub(/^[ \t]+/, "", l); sub(/[ \t\r]+$/, "", l) }
  l ~ /^##[ \t]+[^ \t]/ { exit }
  tolower(l) ~ /^\*\*terminal:\*\*/ { k = "terminal"; exit }
  END { print (k == "" ? "page" : k) }' "$SCRIPT")
case "$KIND" in
  page|terminal) ;;
  *) echo "$PROG: could not read the head lines of '$SCRIPT', which say whether it drives a page or a terminal" >&2; exit 1 ;;
esac

# --guide names the whole app, from the guide at the commit its worktree holds.
if [ -n "$GUIDE" ]; then
  if [ -n "$SERVE_DIR$SERVE_CMD$BASE_URL$SERVE_CWD$PORT" ]; then
    echo "$PROG: --guide names the whole app, so give it without --serve-dir / --serve / --base-url / --cwd / --port, or name the app with those instead" >&2
    usage >&2; exit 2
  fi
  [ -d "$GUIDE" ] || { echo "$PROG: --guide '$GUIDE' is not a directory" >&2; exit 1; }
  GUIDE=$(abspath "$GUIDE")
  demo_engine_guide "$GUIDE" || exit 2
  # The app runs in the guide's directory, or at the worktree's root when it
  # names none, so a command or a shell runs the commit the worktree holds.
  SERVE_CWD="${DEMO_GUIDE_CWD:-$DEMO_GUIDE_ROOT}"
  if [ "$KIND" = page ]; then
    SERVE_DIR="$DEMO_GUIDE_SERVE_DIR"; SERVE_CMD="$DEMO_GUIDE_SERVE"; BASE_URL="$DEMO_GUIDE_BASE_URL"
    PORT="$DEMO_GUIDE_PORT"
    if [ -z "$DEMO_GUIDE" ]; then
      echo "$PROG: the commit checked out in $DEMO_GUIDE_ROOT carries no docs/review-demo.md, so nothing names the app this page script drives; name it with --serve-dir / --serve / --base-url" >&2
      exit 2
    fi
    if [ -z "$SERVE_DIR$SERVE_CMD$BASE_URL" ]; then
      echo "$PROG: $DEMO_GUIDE names no app: its section \"Bring the app up\" has no **Serve:**, **Serve dir:** or **Base URL:** line. Add one, or name the app with --serve-dir / --serve / --base-url" >&2
      exit 2
    fi
    echo "$PROG: the app is the one $DEMO_GUIDE names" >&2
  fi
fi

# A page script needs exactly one app target. The engine needs one way to reach
# the app and rejects more than one; enforce it here so the error names the
# rig-specific input. A terminal script brings up no app, and the engine
# refuses an app target or a --port for one, so this names that refusal before
# the browser is provisioned.
TARGETS=0
[ -n "$SERVE_DIR" ] && TARGETS=$((TARGETS + 1))
[ -n "$SERVE_CMD" ] && TARGETS=$((TARGETS + 1))
[ -n "$BASE_URL" ] && TARGETS=$((TARGETS + 1))
if [ "$KIND" = terminal ]; then
  if [ "$TARGETS" -ne 0 ] || [ -n "$PORT" ]; then
    echo "$PROG: '$SCRIPT' is a terminal script, which runs in the engine's own terminal and takes no --serve-dir / --serve / --base-url or --port; its shell starts in --cwd" >&2
    usage >&2; exit 2
  fi
elif [ "$TARGETS" -ne 1 ]; then
  echo "$PROG: give exactly one of --serve-dir / --serve / --base-url, or --guide (got $TARGETS)" >&2
  usage >&2; exit 2
fi
# Only a command can be told which port to take; --serve-dir takes a free one
# by itself.
[ "$PORT" != 0 ] || [ -n "$SERVE_CMD" ] || { echo "$PROG: --port 0 picks a free port for a --serve command; give it with --serve only" >&2; exit 2; }
[ -z "$SERVE_CWD" ] || [ -d "$SERVE_CWD" ] || { echo "$PROG: --cwd '$SERVE_CWD' is not a directory" >&2; exit 1; }
[ -z "$MUSIC" ] || [ -f "$MUSIC" ] || { echo "$PROG: --music '$MUSIC' does not exist" >&2; exit 1; }

SCRIPT=$(abspath "$SCRIPT")
OUTPUT=$(abspath "$OUTPUT")
case "$SERVE_DIR" in ''|/*) ;; *) [ -z "$SERVE_CWD" ] || SERVE_DIR="$SERVE_CWD/$SERVE_DIR" ;; esac
[ -z "$SERVE_DIR" ] || SERVE_DIR=$(abspath "$SERVE_DIR")
[ -z "$MUSIC" ] || MUSIC=$(abspath "$MUSIC")

# The output's parent must exist; the engine does not create it.
OUT_DIR=$(dirname "$OUTPUT")
mkdir -p "$OUT_DIR" || { echo "$PROG: cannot create output directory '$OUT_DIR'" >&2; exit 1; }

# --- the engine ------------------------------------------------------------
# demo-engine-lib.sh finds the engine, provisions its browser and runs its CLI
# in its sandbox. What only a clip needs stays here: ffmpeg to assemble it,
# which is a host ffmpeg when there is one and otherwise a checkout's
# ffmpeg-static binary, fetched on first use. $SPRINTSHOW_BIN overrides the
# engine, and runs in the same sandbox.
if [ -n "${SPRINTSHOW_BIN:-}" ] && [ -x "${SPRINTSHOW_BIN}" ]; then
  DEMO_ENGINE_BIN="$SPRINTSHOW_BIN"
else
  demo_engine_resolve || exit 1
  if [ -n "$DEMO_ENGINE_DIR" ]; then
    command -v ffmpeg >/dev/null 2>&1 || [ -x "$DEMO_ENGINE_DIR/node_modules/ffmpeg-static/ffmpeg" ] || ( cd "$DEMO_ENGINE_DIR" && npm run provision:ffmpeg ) >&2 || { echo "$PROG: could not provision ffmpeg (no host ffmpeg and ffmpeg-static fetch failed)" >&2; exit 1; }
  fi
fi
sprintshow() { demo_engine_cli "$@"; }

# The engine sets no PORT for a --serve command, and the sandbox refuses a port
# a server already answers on, so a capture that runs beside another takes a
# port of its own. --port 0 names one that is free when it is read here, and
# stays so unless another process binds it before the command does. The
# command's environment carries the port as PORT, as a screenshot's does.
if [ "$PORT" = 0 ]; then
  PORT=$(demo_engine_free_port) || { echo "$PROG: could not find a free port for the --serve command" >&2; exit 1; }
fi
[ -z "$SERVE_CMD" ] || [ -z "$PORT" ] || export PORT

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
elif [ -n "$BASE_URL" ]; then
  set -- "$@" --base-url "$BASE_URL"
else
  # A terminal script: its shell starts in --cwd, or here.
  [ -z "$SERVE_CWD" ] || set -- "$@" --cwd "$SERVE_CWD"
fi
[ -z "$PORT" ]     || set -- "$@" --port "$PORT"
[ "$NO_NARRATE" -eq 1 ] && set -- "$@" --no-narrate
[ -z "$MUSIC" ]    || set -- "$@" --music "$MUSIC"
[ "$KEEP" -eq 1 ]  && set -- "$@" --keep

echo "$PROG: capturing $SCRIPT ($MODE) -> $OUTPUT" >&2
REPORT=$(mktemp "${TMPDIR:-/tmp}/rig-demo-capture.XXXXXX") || { echo "$PROG: cannot create a file for the engine's report" >&2; exit 1; }
trap 'rm -f "$REPORT"' EXIT
sprintshow "$@" | tee "$REPORT"
RC=${PIPESTATUS[0]}

# The engine exits non-zero both when it could not capture and when a step of
# the clip it captured failed its proof. Its closing report tells them apart: it
# is printed only once the clip is assembled, says whether the clip is narrated
# or silent, counts the failed steps, and names the working directory it kept,
# relative to the engine's own working directory, which is ours.
NARRATION=$(sed -n -E 's/.* (narrated|silent)( \+ music bed)? demo .*/\1/p' "$REPORT" | tail -n 1)
FAILED=$(sed -n -E 's/.* ([0-9]+) step\(s\) failed their proof.*/\1/p' "$REPORT" | tail -n 1)
KEPT=$(sed -n -E 's/.* failed their proof.* kept: (.+)$/\1/p' "$REPORT" | tail -n 1)
case "$KEPT" in ""|/*) ;; *) KEPT="$(pwd)/$KEPT" ;; esac

if [ "$RC" -ne 0 ]; then
  if [ -n "$FAILED" ] && [ -s "$OUTPUT" ]; then
    echo "$PROG: captured $OUTPUT (${NARRATION:-narration unreported}), but $FAILED step(s) failed their proof${KEPT:+; the engine kept its working files in $KEPT}"
    exit 3
  fi
  echo "$PROG: capture failed (sprintshow run exited $RC)" >&2
  exit 1
fi

# --- the produced file must exist and carry bytes ------------------------
# The engine reports success on stdout, but the deliverable is the file. A zero
# exit with no MP4 is the exact silent non-delivery this fails closed on.
[ -f "$OUTPUT" ] || { echo "$PROG: capture reported success but '$OUTPUT' does not exist" >&2; exit 1; }
[ -s "$OUTPUT" ] || { echo "$PROG: capture produced '$OUTPUT' but it is empty" >&2; exit 1; }

echo "$PROG: captured $OUTPUT (${NARRATION:-narration unreported}, $(wc -c <"$OUTPUT" | tr -d ' ') bytes)"
exit 0
