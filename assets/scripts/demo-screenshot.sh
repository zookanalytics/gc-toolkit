#!/usr/bin/env bash
# demo-screenshot.sh — the demo check's screenshot modality: render one state of
# the surface a change affects and save it as a PNG, which demo-deliver.sh then
# attaches to the PR inline and uncommitted.
#
# The SprintShow engine's screenshot command takes every PNG. It drives a demo
# script's steps in the engine's headless browser, checks each step's proof
# through the step runner the engine's videos use, and saves the state the last
# step leaves. demo-engine-lib.sh finds the engine, provisions its browser and
# runs its CLI, as it does for the video capture. A screenshot needs neither
# ffmpeg nor a narration key.
#
# A surface is one of three kinds, and each has a subcommand:
#   page      an app page. A demo:capture script drives the app to the state,
#             in the format and against the app targets a video uses, and the
#             capture is that state: the viewport, the whole page, or one
#             element. Each step's proof is checked, and a step whose proof
#             fails still yields the capture, which shows what failed.
#   terminal  a command's output, as a terminal window shows it, colour
#             included. The command runs with bash from --cwd and its stdout and
#             stderr are captured together; --text names output captured
#             earlier instead.
#   markdown  markdown as GitHub shows a PR comment. GitHub's own renderer, its
#             markdown API, turns the file into HTML in the context of the rig's
#             origin, so #123 and @name link as they do on the PR, and the HTML is
#             drawn in a comment box with GitHub's comment styles. github.com's
#             page script finishes some blocks after the API returns, such as a
#             mermaid diagram or math, and markdown holding one is refused,
#             because the page drawn here has no script.
# A terminal or markdown surface has no app to drive. demo-screenshot.mjs,
# beside this script, draws it as a page of its own, and the engine serves that
# page from a directory and captures the surface's element, with a one-step
# script whose proof is that the surface is drawn.
#
# It FAILS CLOSED. A missing engine, an engine with no screenshot command, a
# browser that cannot be installed, a renderer that errors or refuses its
# surface, or a capture that leaves no PNG behind all exit 1, because a capture
# that quietly produces nothing is the undelivered visual this modality exists
# to end, and one that shows a surface unfinished misleads whoever reads it.
#
# Usage:
#   demo-screenshot.sh page --script <demo.md> --output <file.png>
#       ( --serve-dir <dir> | --serve <command> | --base-url <url> ) [--port <n>]
#       [--cwd <dir>] [--selector <css> | --full-page]
#   demo-screenshot.sh terminal --output <file.png> ( --command <command> | --text <file> )
#       [--cwd <dir>] [--title <text>] [--columns <n>] [--max-lines <n>]
#   demo-screenshot.sh markdown --file <file.md> --output <file.png>
#       [--repo <owner/name>] [--title <text>] [--expand]
#
#   --output     the PNG to write. Write it outside the repo tree: a screenshot
#                is delivered to the PR, never committed.
#   page:
#   --script     the demo:capture script whose steps drive the app to the state.
#   --serve-dir  serve a static directory, on a free port unless --port names one.
#   --serve      spawn a dev-server command, wait for it on --port, then tear it
#                down. --cwd is its working directory. With --port, the
#                command's environment carries the port as PORT, and --port 0
#                picks a free one, so captures side by side never share a
#                server.
#   --base-url   drive a server that is already running.
#                Exactly one of --serve-dir / --serve / --base-url is required.
#   --selector   capture this element instead of the viewport.
#   --full-page  capture the whole scrollable page instead of the viewport.
#                At most one of --selector / --full-page is given.
#   terminal:
#   --command    the command to run with bash from --cwd (default: here). The
#                capture shows it after a $ prompt, then what it printed.
#   --text       a file of output captured earlier, rendered as it stands.
#                Exactly one of --command / --text is required.
#   --title      the window's title bar text.
#   --columns    the widest line, in columns, before a line wraps (default 120).
#   --max-lines  the lines shown before the rest is cut and counted (default 200).
#   markdown:
#   --file       the markdown to render.
#   --repo       the owner/name its #123 and @name references resolve in
#                (default: the rig's origin).
#   --title      a header bar above the comment body.
#   --expand     open every <details>, which GitHub shows collapsed.
#
# The last line names the PNG and its size in pixels. For --command it also
# gives the command's exit status, which does not decide this script's: a
# command that fails can still print the surface the change affects.
#
# Exit: 0 captured, 3 a page captured with at least one step whose proof failed,
#   2 bad arguments, 1 anything that stopped the capture.
set -u

PROG=demo-screenshot
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RENDERER="$HERE/demo-screenshot.mjs"
# shellcheck source=demo-engine-lib.sh
. "$HERE/demo-engine-lib.sh" || { echo "$PROG: cannot source demo-engine-lib.sh beside this script" >&2; exit 1; }

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
usage_err() { echo "$PROG: $1" >&2; usage >&2; exit 2; }
fail() { echo "$PROG: $1" >&2; exit 1; }

KIND="${1:-}"
case "$KIND" in
  page|terminal|markdown) shift ;;
  -h|--help) usage; exit 0 ;;
  '') usage_err "a kind is required: page, terminal or markdown" ;;
  *)  usage_err "unknown kind '$KIND': page, terminal or markdown" ;;
esac

OUTPUT=""; SCRIPT=""; SERVE_DIR=""; SERVE_CMD=""; BASE_URL=""; PORT=""; CWD=""
SELECTOR=""; FULL_PAGE=0; COMMAND=""; TEXT=""; TITLE=""; COLUMNS=""; MAX_LINES=""
FILE=""; REPO=""; EXPAND=0
# Each kind takes only its own flags.
case "$KIND" in
  page)     ALLOWED=" --output --script --serve-dir --serve --base-url --port --cwd --selector --full-page " ;;
  terminal) ALLOWED=" --output --command --text --cwd --title --columns --max-lines " ;;
  markdown) ALLOWED=" --output --file --repo --title --expand " ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in -h|--help) usage; exit 0 ;; esac
  case "$ALLOWED" in *" $1 "*) ;; *) usage_err "$KIND takes no '$1'" ;; esac
  case "$1" in
    --full-page) FULL_PAGE=1; shift; continue ;;
    --expand)    EXPAND=1; shift; continue ;;
  esac
  [ $# -gt 1 ] || usage_err "$1 needs a value"
  case "$1" in
    --output)    OUTPUT="$2" ;;
    --script)    SCRIPT="$2" ;;
    --serve-dir) SERVE_DIR="$2" ;;
    --serve)     SERVE_CMD="$2" ;;
    --base-url)  BASE_URL="$2" ;;
    --port)      PORT="$2" ;;
    --cwd)       CWD="$2" ;;
    --selector)  SELECTOR="$2" ;;
    --command)   COMMAND="$2" ;;
    --text)      TEXT="$2" ;;
    --title)     TITLE="$2" ;;
    --columns)   COLUMNS="$2" ;;
    --max-lines) MAX_LINES="$2" ;;
    --file)      FILE="$2" ;;
    --repo)      REPO="$2" ;;
  esac
  shift 2
done

# --- arguments -----------------------------------------------------------
[ -n "$OUTPUT" ] || usage_err "--output is required"
case "$OUTPUT" in *.png|*.PNG) ;; *) usage_err "--output must name a .png file (got '$OUTPUT')" ;; esac
# gh reads what follows a '#' in an attachment's path as the image's alt text,
# and the file's name is the alt text it shows otherwise.
case "${OUTPUT##*/}" in *'#'*) usage_err "--output's file name must not contain '#', which gh reads as the start of an image's alt text" ;; esac
posint() { case "$2" in ''|*[!0-9]*|0*) usage_err "$1 must be a positive integer (got '$2')" ;; esac; }
[ -z "$PORT" ] || [ "$PORT" = 0 ] || posint --port "$PORT"
[ -z "$COLUMNS" ] || posint --columns "$COLUMNS"
[ -z "$MAX_LINES" ] || posint --max-lines "$MAX_LINES"
case "$KIND" in
  page)
    [ -n "$SCRIPT" ] || usage_err "page needs --script"
    TARGETS=0
    [ -n "$SERVE_DIR" ] && TARGETS=$((TARGETS + 1))
    [ -n "$SERVE_CMD" ] && TARGETS=$((TARGETS + 1))
    [ -n "$BASE_URL" ] && TARGETS=$((TARGETS + 1))
    [ "$TARGETS" -eq 1 ] || usage_err "page needs exactly one of --serve-dir / --serve / --base-url (got $TARGETS)"
    # The engine refuses the pair too, but this script reaches the engine only
    # after provisioning its browser.
    if [ -n "$SELECTOR" ] && [ "$FULL_PAGE" -eq 1 ]; then usage_err "page takes --selector or --full-page, not both"; fi
    # Only a command can be told which port to take; --serve-dir takes a free
    # one by itself.
    [ "$PORT" != 0 ] || [ -n "$SERVE_CMD" ] || usage_err "--port 0 picks a free port for a --serve command; give it with --serve only"
    [ -f "$SCRIPT" ] || fail "--script '$SCRIPT' does not exist"
    [ -z "$SERVE_DIR" ] || [ -d "$SERVE_DIR" ] || fail "--serve-dir '$SERVE_DIR' is not a directory"
    [ -z "$CWD" ] || [ -d "$CWD" ] || fail "--cwd '$CWD' is not a directory" ;;
  terminal)
    if [ -n "$COMMAND" ] && [ -n "$TEXT" ]; then usage_err "terminal takes --command or --text, not both"; fi
    [ -n "$COMMAND" ] || [ -n "$TEXT" ] || usage_err "terminal needs --command or --text"
    [ -z "$TEXT" ] || [ -f "$TEXT" ] || fail "--text '$TEXT' does not exist"
    [ -z "$CWD" ] || [ -n "$COMMAND" ] || usage_err "--cwd is where --command runs; --text takes none"
    [ -z "$CWD" ] || [ -d "$CWD" ] || fail "--cwd '$CWD' is not a directory" ;;
  markdown)
    [ -n "$FILE" ] || usage_err "markdown needs --file"
    [ -f "$FILE" ] || fail "--file '$FILE' does not exist"
    case "$REPO" in
      '') ;;
      */*/*|/*|*/|*[!A-Za-z0-9_./-]*) usage_err "--repo must be owner/name (got '$REPO')" ;;
      */*) ;;
      *) usage_err "--repo must be owner/name (got '$REPO')" ;;
    esac ;;
esac
[ "$KIND" = page ] || [ -f "$RENDERER" ] || fail "demo-screenshot.mjs not found beside this script"

# The engine resolves relative paths against its own working directory, so every
# path it is handed is absolute.
abspath() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$(pwd)" "$1" ;; esac; }
OUTPUT=$(abspath "$OUTPUT")
[ -z "$SCRIPT" ] || SCRIPT=$(abspath "$SCRIPT")
[ -z "$SERVE_DIR" ] || SERVE_DIR=$(abspath "$SERVE_DIR")
[ -z "$CWD" ] || CWD=$(abspath "$CWD")
[ -z "$TEXT" ] || TEXT=$(abspath "$TEXT")

mkdir -p "$(dirname "$OUTPUT")" || fail "cannot create the output directory '$(dirname "$OUTPUT")'"
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/demo-screenshot.XXXXXX") || fail "cannot make a temp dir"
trap 'rm -rf "$TMPD"' EXIT

# --- the engine ------------------------------------------------------------
# demo-engine-lib.sh holds Node to the engine's floor, finds the engine,
# provisions its browser and runs its CLI. A sprintshow checkout that predates
# the screenshot command, or a published package without it, can capture
# nothing here, so the engine's own help is read for the command before a
# command runs or a renderer is called.
demo_engine_resolve || exit 1
ENGINE_HELP=$(demo_engine_cli help 2>"$TMPD/help.err")
HELP_RC=$?
[ "$HELP_RC" -eq 0 ] || fail "the SprintShow engine's CLI did not run ('sprintshow help' exited $HELP_RC): $(head -c 400 "$TMPD/help.err" | tr '\n' ' ')"
case "$ENGINE_HELP" in
  *"sprintshow screenshot "*) ;;
  *) fail "the SprintShow engine (${DEMO_ENGINE_DIR:-the published $DEMO_ENGINE_PACKAGE}) has no screenshot command, which every kind captures through; update it to a SprintShow whose 'sprintshow help' lists 'sprintshow screenshot'" ;;
esac

# draw <renderer options...>: the renderer draws the surface as the page
# $TMPD/surface/index.html, whose element #surface the capture crops to, and
# $TMPD/surface.md is the one-step script the engine captures it with.
draw() {
  mkdir -p "$TMPD/surface" || fail "cannot make a directory for the $KIND page"
  node "$RENDERER" "$KIND" "$@" --output "$TMPD/surface/index.html" \
    || fail "the renderer could not draw the $KIND surface"
  printf '%s\n' "# Demo: $KIND" '**Start:** `/`' '' '## Steps' \
      '1. **The surface is drawn**' '   _Prove:_ the surface is on the page `visible #surface`' \
      >"$TMPD/surface.md" || fail "cannot write the script that captures the $KIND page"
}

# --- what the engine captures --------------------------------------------
CMD_RC=""
case "$KIND" in
  page)
    # The engine reuses whatever already answers on a --serve port and spawns
    # nothing, so a capture that must not meet another one's server takes a
    # port of its own. The port is free when it is read here, and stays so
    # unless another process binds it before the command does.
    if [ "$PORT" = 0 ]; then
      PORT=$(node -e 'const s = require("net").createServer(); s.listen(0, "127.0.0.1", () => { process.stdout.write(String(s.address().port)); s.close(); });' 2>/dev/null)
      case "$PORT" in ''|*[!0-9]*|0*) fail "could not find a free port for the --serve command" ;; esac
    fi
    [ -z "$SERVE_CMD" ] || [ -z "$PORT" ] || export PORT
    set -- "$SCRIPT"
    if [ -n "$SERVE_DIR" ]; then set -- "$@" --serve-dir "$SERVE_DIR"
    elif [ -n "$SERVE_CMD" ]; then set -- "$@" --serve "$SERVE_CMD"
    else set -- "$@" --base-url "$BASE_URL"; fi
    [ -z "$PORT" ] || set -- "$@" --port "$PORT"
    [ -z "$CWD" ] || set -- "$@" --cwd "$CWD"
    [ -z "$SELECTOR" ] || set -- "$@" --selector "$SELECTOR"
    [ "$FULL_PAGE" -eq 0 ] || set -- "$@" --full-page ;;
  terminal)
    if [ -n "$COMMAND" ]; then
      # stdin is closed, so a command that would prompt reads end of input
      # instead of waiting on a terminal that is not there.
      ( cd "${CWD:-.}" && bash -c "$COMMAND" ) >"$TMPD/output.txt" 2>&1 </dev/null
      CMD_RC=$?
      set -- --text "$TMPD/output.txt" --prompt "$COMMAND"
    else
      set -- --text "$TEXT"
    fi
    [ -z "$TITLE" ] || set -- "$@" --title "$TITLE"
    [ -z "$COLUMNS" ] || set -- "$@" --columns "$COLUMNS"
    [ -z "$MAX_LINES" ] || set -- "$@" --max-lines "$MAX_LINES"
    draw "$@" ;;
  markdown)
    # The context is the repository the comment's references resolve in: --repo,
    # else this rig's origin, else the origin of the checkout this runs from.
    if [ -z "$REPO" ]; then
      u=""
      if [ -n "${GC_RIG_ROOT:-}" ] && [ -d "${GC_RIG_ROOT:-}" ]; then
        u=$(git -C "$GC_RIG_ROOT" remote get-url origin 2>/dev/null | tr -d '[:space:]')
      fi
      [ -n "$u" ] || u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
      case "$u" in
        git@github.com:*|https://github.com/*|ssh://git@github.com/*)
          REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
            -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
      esac
      case "$REPO" in */*/*|/*|*/) REPO="" ;; */*) : ;; *) REPO="" ;; esac
      [ -n "$REPO" ] || echo "$PROG: no GitHub origin found, so #123 and @name references render without a repository context" >&2
    fi
    command -v gh >/dev/null 2>&1 || fail "gh not found; GitHub's markdown renderer is reached through it"
    command -v jq >/dev/null 2>&1 || fail "jq not found; it builds the renderer's request"
    jq -n --rawfile text "$FILE" --arg ctx "$REPO" \
        '{text: $text, mode: "gfm"} + (if $ctx == "" then {} else {context: $ctx} end)' >"$TMPD/request.json" \
      || fail "cannot read '$FILE' into the renderer's request"
    if ! gh api --hostname github.com markdown --input "$TMPD/request.json" >"$TMPD/comment.html" 2>"$TMPD/gh.err"; then
      fail "GitHub's markdown renderer failed: $(head -c 400 "$TMPD/gh.err" | tr '\n' ' ')"
    fi
    [ -s "$TMPD/comment.html" ] || fail "GitHub's markdown renderer returned nothing for '$FILE'"
    set -- --html "$TMPD/comment.html"
    [ -z "$TITLE" ] || set -- "$@" --title "$TITLE"
    [ "$EXPAND" -eq 0 ] || set -- "$@" --expand
    draw "$@" ;;
esac
# A drawn surface is captured by its element, with no page background around
# its rounded corners.
[ "$KIND" = page ] || set -- "$TMPD/surface.md" --serve-dir "$TMPD/surface" --selector '#surface' --transparent

# --- capture --------------------------------------------------------------
# A GitHub comment shows an image at most as wide as its column, so a capture is
# taken at two device pixels per CSS pixel, and its text stays sharp there. A
# PNG left by an earlier run must not pass for this one.
rm -f "$OUTPUT"
echo "$PROG: capturing $KIND -> $OUTPUT" >&2
demo_engine_cli screenshot "$@" -o "$OUTPUT" --scale 2 | tee "$TMPD/report"
RC=${PIPESTATUS[0]}
case "$RC" in 0|3) ;; *) fail "capture failed (sprintshow screenshot exited $RC)" ;; esac

# --- the produced file must be a PNG -------------------------------------
[ -f "$OUTPUT" ] || fail "the capture reported success but '$OUTPUT' does not exist"
[ -s "$OUTPUT" ] || fail "the capture produced '$OUTPUT' but it is empty"
SIG=$(head -c 8 "$OUTPUT" | od -An -tx1 | tr -d ' \n')
[ "$SIG" = "89504e470d0a1a0a" ] || fail "'$OUTPUT' is not a PNG"
# The IHDR chunk holds the width and the height as 4-byte big-endian integers.
dim() { od -An -tu1 -j "$1" -N4 "$OUTPUT" | awk 'NF == 4 { print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4; exit }'; }
SIZE="$(dim 16)x$(dim 20) px, $(wc -c <"$OUTPUT" | tr -d ' ') bytes"

if [ "$RC" -eq 3 ]; then
  FAILED=$(sed -n -E 's/.* ([0-9]+) step\(s\) failed their proof.*/\1/p' "$TMPD/report" | tail -n 1)
  echo "$PROG: captured $OUTPUT ($KIND, $SIZE), but ${FAILED:-at least one} step(s) failed their proof"
  exit 3
fi
if [ -n "$CMD_RC" ]; then
  echo "$PROG: captured $OUTPUT (terminal, $SIZE); the command exited $CMD_RC"
else
  echo "$PROG: captured $OUTPUT ($KIND, $SIZE)"
fi
exit 0
