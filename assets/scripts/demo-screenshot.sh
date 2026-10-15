#!/usr/bin/env bash
# demo-screenshot.sh — the demo check's screenshot modality: render one state of
# the surface a change affects in a headless browser and save it as a PNG, which
# demo-deliver.sh then attaches to the PR inline and uncommitted.
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
#             drawn in a comment box with GitHub's comment styles.
#
# The browser is the SprintShow engine's: its Playwright and the
# chromium-headless-shell build that Playwright installs. demo-engine-lib.sh
# finds the engine and installs that build, as it does for the video capture.
# demo-screenshot.mjs, beside this script, drives it. A screenshot needs neither
# ffmpeg nor a narration key.
#
# It FAILS CLOSED. A missing engine, a browser that cannot be installed, a
# renderer that errors, or a capture that leaves no PNG behind all exit 1,
# because a capture that quietly produces nothing is the undelivered visual this
# modality exists to end.
#
# Usage:
#   demo-screenshot.sh page --script <demo.md> --output <file.png>
#       ( --serve-dir <dir> | --serve <command> | --base-url <url> ) [--port <n>]
#       [--cwd <dir>] [--selector <css>] [--full-page]
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
#                down. --cwd is its working directory.
#   --base-url   drive a server that is already running.
#                Exactly one of --serve-dir / --serve / --base-url is required.
#   --selector   capture this element instead of the viewport.
#   --full-page  capture the whole scrollable page instead of the viewport.
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
DRIVER="$HERE/demo-screenshot.mjs"
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
[ -z "$PORT" ] || posint --port "$PORT"
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
[ -f "$DRIVER" ] || fail "demo-screenshot.mjs not found beside this script"

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
# demo-engine-lib.sh finds the engine and provisions its browser. What only a
# screenshot needs stays here: the driver strips the TypeScript of a checkout
# natively, so Node must be at least the engine's floor, 22.18, before anything
# is installed; and the driver runs with the checkout as its --engine, or under
# npx beside the published package.
command -v node >/dev/null 2>&1 || fail "node not found; the SprintShow engine needs Node >= 22.18. doctor/check-demo-toolchain names this gap."
NODEVER=$(node --version 2>/dev/null | sed 's/^v//')
NODE_MAJOR=${NODEVER%%.*}; NODE_REST=${NODEVER#*.}; NODE_MINOR=${NODE_REST%%.*}
case "$NODE_MAJOR" in ''|*[!0-9]*) NODE_MAJOR=0 ;; esac
case "$NODE_MINOR" in ''|*[!0-9]*) NODE_MINOR=0 ;; esac
if [ "$NODE_MAJOR" -lt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -lt 18 ]; }; then
  fail "Node ${NODEVER:-unknown} is below the engine's floor of 22.18"
fi
demo_engine_resolve || exit 1
if [ -n "$DEMO_ENGINE_DIR" ]; then
  driver() { node "$DRIVER" "$@" --engine "$DEMO_ENGINE_DIR"; }
else
  driver() { npx --yes --package="$DEMO_ENGINE_PACKAGE" -- node "$DRIVER" "$@"; }
fi

# --- what the driver renders ---------------------------------------------
set -- "$KIND" --output "$OUTPUT"
CMD_RC=""
case "$KIND" in
  page)
    set -- "$@" --script "$SCRIPT"
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
      set -- "$@" --text "$TMPD/output.txt" --prompt "$COMMAND"
    else
      set -- "$@" --text "$TEXT"
    fi
    [ -z "$TITLE" ] || set -- "$@" --title "$TITLE"
    [ -z "$COLUMNS" ] || set -- "$@" --columns "$COLUMNS"
    [ -z "$MAX_LINES" ] || set -- "$@" --max-lines "$MAX_LINES" ;;
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
    set -- "$@" --html "$TMPD/comment.html"
    [ -z "$TITLE" ] || set -- "$@" --title "$TITLE"
    [ "$EXPAND" -eq 0 ] || set -- "$@" --expand ;;
esac

# --- capture --------------------------------------------------------------
# A PNG left by an earlier run must not pass for this one.
rm -f "$OUTPUT"
echo "$PROG: capturing $KIND -> $OUTPUT" >&2
driver "$@" | tee "$TMPD/report"
RC=${PIPESTATUS[0]}
case "$RC" in 0|3) ;; *) fail "capture failed (the driver exited $RC)" ;; esac

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
  echo "$PROG: captured $OUTPUT (page, $SIZE), but ${FAILED:-at least one} step(s) failed their proof"
  exit 3
fi
if [ -n "$CMD_RC" ]; then
  echo "$PROG: captured $OUTPUT (terminal, $SIZE); the command exited $CMD_RC"
else
  echo "$PROG: captured $OUTPUT ($KIND, $SIZE)"
fi
exit 0
