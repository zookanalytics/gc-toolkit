#!/usr/bin/env bash
# demo-screenshot.test.sh — hermetic coverage of the screenshot modality.
#
# demo-screenshot.sh validates its arguments, resolves the SprintShow engine,
# reads the engine's help for its screenshot command, prepares what a kind
# captures (an app page's script and target, or a terminal or markdown surface
# the renderer draws as a page of its own), runs the engine's screenshot
# command, and checks the PNG it leaves. demo-engine-lib.sh holds Node to the
# engine's floor, finds the engine, provisions its browser and runs its CLI,
# and demo-engine-lib.test.sh checks that through this script. Every case runs
# under `env -i` with a PATH of a coreutils symlink farm and stubs for node,
# npm, gc and gh, so nothing reaches the network, a browser, or a city. The
# node stub hands the engine checkout's CLI to an engine stub, and otherwise
# stands in for the renderer: it logs its argv, keeps a copy of the file it was
# handed, and leaves a page at --output. The engine stub keeps the script and
# the page it was handed, and leaves the PNG, or the failure, each case plants.
#
# The renderers are pure functions of their input, so the last part imports
# demo-screenshot.mjs into a real node, when the host has Node 18 or later, and
# checks what they emit; without one those cases are skipped. There the gh stub
# answers with HTML GitHub's markdown API returned, kept verbatim, and the node
# stub runs the real renderer on it, so a markdown capture is checked end to
# end on what GitHub actually sends.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/demo-screenshot.sh"
RENDERER="$HERE/demo-screenshot.mjs"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
[ -f "$RENDERER" ] || { echo "not found: $RENDERER" >&2; exit 2; }

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }
eq()    { if [ "$1" = "$2" ]; then printf 'ok   - %s\n' "$3"; else printf 'FAIL - %s\n     want: %s\n     got:  %s\n' "$3" "$2" "$1"; FAIL=1; fi; }

TMPD="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/demo-screenshot-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMPD"' EXIT

# Only the tools the script calls. env -i keeps everything else off PATH.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail dirname mkdir mktemp rm tee wc cat od awk cp git; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done

# Stubs. node answers --version with $NODE_VERSION, hands the checkout's CLI to
# $ENGINE_STUB, answers the free-port pick (-e) with $FREE_PORT, runs the real
# renderer or pick under $REAL_NODE when that is set, and otherwise stands in
# for the renderer, failing on $RENDER_RC; npm records what
# it runs and where; gc lists the sprintshow rig at $SS_RIG; gh stands in for
# GitHub's markdown renderer, answering with the file $GH_HTML when that is
# set. Each logs to $CALLLOG.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
BIN="$TMPD/bin"; mkdir -p "$BIN"
ln -s "$JQ" "$BIN/jq"
cat >"$BIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "${NODE_VERSION:-v24.0.0}"; exit 0; fi
printf 'node' >>"${CALLLOG:?}"; printf ' [%s]' "$@" >>"$CALLLOG"; printf '\n' >>"$CALLLOG"
case "${1:-}" in */src/cli.ts) shift; exec "${ENGINE_STUB:?}" "$@" ;; esac
if [ "${1:-}" = "-e" ]; then [ -z "${REAL_NODE:-}" ] || exec "$REAL_NODE" "$@"; printf '%s' "${FREE_PORT-50123}"; exit 0; fi
[ -z "${REAL_NODE:-}" ] || exec "$REAL_NODE" "$@"
o=""; prev=""
for a in "$@"; do
  [ "$prev" = "--output" ] && o="$a"
  [ "$prev" = "--text" ] && cp "$a" "${HANDED:?}"
  [ "$prev" = "--html" ] && cp "$a" "${HANDED:?}"
  prev="$a"
done
if [ "${RENDER_RC:-0}" != 0 ]; then echo "demo-screenshot.mjs: boom" >&2; exit "$RENDER_RC"; fi
printf '<!doctype html><div id="surface">drawn by the renderer</div>\n' >"$o"
exit 0
NODE
cat >"$BIN/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s (in %s)\n' "$*" "$PWD" >>"${CALLLOG:?}"
exit 0
NPM
cat >"$BIN/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 $2" = "rig list" ] && [ -n "${SS_RIG:-}" ]; then printf '{"rigs":[{"name":"sprintshow","path":"%s"}]}\n' "$SS_RIG"; fi
exit 0
GC
cat >"$BIN/gh" <<'GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${CALLLOG:?}"
prev=""; for a in "$@"; do [ "$prev" = "--input" ] && cp "$a" "${GH_REQ:?}"; prev="$a"; done
if [ "${GH_RC:-0}" != 0 ]; then echo 'HTTP 502: Bad Gateway (https://api.github.com/markdown)' >&2; exit "$GH_RC"; fi
if [ -n "${GH_HTML:-}" ]; then cat "$GH_HTML"; exit 0; fi
[ -n "${GH_EMPTY:-}" ] || printf '<p dir="auto"><strong>Approve.</strong></p>\n<details>\n<summary>trail</summary>\n<p dir="auto">x</p>\n</details>\n'
exit 0
GH
chmod +x "$BIN"/node "$BIN"/npm "$BIN"/gc "$BIN"/gh

# The engine's CLI. help lists the screenshot command unless $ENGINE_OLD is set,
# and exits $HELP_RC. screenshot logs the PORT its environment carries, which a
# --serve command it spawns would inherit, keeps the script it was handed and
# the page a --serve-dir serves, then leaves what $ENGINE_MODE plants.
ENGINE_STUB="$TMPD/engine"
cat >"$ENGINE_STUB" <<'ENGINE'
#!/usr/bin/env bash
printf 'engine' >>"${CALLLOG:?}"; printf ' [%s]' "$@" >>"$CALLLOG"; printf '\n' >>"$CALLLOG"
case "${1:-}" in
  help)
    printf 'Usage:\n  sprintshow run <demo.md> [options]\n'
    [ -n "${ENGINE_OLD:-}" ] || printf '  sprintshow screenshot <demo.md> -o <file.png> [options]\n'
    if [ "${HELP_RC:-0}" != 0 ]; then echo 'SyntaxError: Unexpected token' >&2; exit "$HELP_RC"; fi
    exit 0 ;;
  screenshot) ;;
  *) echo "engine stub: unexpected command: $*" >&2; exit 97 ;;
esac
printf 'engine-env PORT=%s\n' "${PORT-unset}" >>"$CALLLOG"
o=""; d=""; prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && o="$a"
  [ "$prev" = "--serve-dir" ] && d="$a"
  prev="$a"
done
cp "$2" "${SCRIPT_HANDED:?}"
[ -z "$d" ] || [ ! -f "$d/index.html" ] || cp "$d/index.html" "${SERVED:?}"
# A PNG signature and an IHDR chunk naming a 1948x1132 image.
png() { printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x07\x9c\x00\x00\x04\x6c\x08\x06\x00\x00\x00' >"$1"; }
case "${ENGINE_MODE:-png}" in
  png)     png "$o"; printf '\n✅ screenshot → %s\n' "$o" ;;
  failed)  png "$o"; printf '\n✅ screenshot → %s\n   ⚠️  2 step(s) failed their proof — the screenshot shows the state they left\n' "$o"; exit 3 ;;
  failed-nofile) printf '   ⚠️  2 step(s) failed their proof — the screenshot shows the state they left\n'; exit 3 ;;
  error)   echo '✖ screenshot: no visible `#board` to capture' >&2; exit 1 ;;
  nofile)  : ;;
  empty)   : >"$o" ;;
  notpng)  echo 'not a png' >"$o" ;;
esac
exit 0
ENGINE
chmod +x "$ENGINE_STUB"

# A local engine checkout with its deps installed.
ENGINE="$TMPD/sprintshow"; mkdir -p "$ENGINE/node_modules"
printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"
CLI="$ENGINE/src/cli.ts"

# Fixtures: a demo script, a static app, a markdown file, captured output.
WORK="$TMPD/work"; mkdir -p "$WORK"
SCRIPT="$WORK/demo.md"; printf '# Demo: fixture\n\n**Start:** `/`\n' >"$SCRIPT"
APP="$WORK/app"; mkdir -p "$APP"; printf '<!doctype html><title>x</title>\n' >"$APP/index.html"
MD="$WORK/comment.md"; printf '**Approve.** Nothing needs you.\n\n<details>\n<summary>trail</summary>\n\nx\n</details>\n' >"$MD"
TXT="$WORK/out.txt"; printf 'line one\nline two\n' >"$TXT"
OUT="$WORK/shots/shot.png"
CALLLOG="$TMPD/calls.log"; HANDED="$TMPD/handed"; GH_REQ="$TMPD/gh-request.json"
SCRIPT_HANDED="$TMPD/script-handed"; SERVED="$TMPD/served"

# run [VAR=VAL ...] -- <sut args...>: combined stdout and stderr, run from $WORK.
# The local engine is listed unless a case sets SS_RIG itself.
run() {
  local envs=(SS_RIG="$ENGINE")
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  : >"$CALLLOG"; rm -f "$HANDED" "$GH_REQ" "$SCRIPT_HANDED" "$SERVED"
  ( cd "$WORK" && env -i PATH="$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" HANDED="$HANDED" \
      GH_REQ="$GH_REQ" ENGINE_STUB="$ENGINE_STUB" SCRIPT_HANDED="$SCRIPT_HANDED" SERVED="$SERVED" \
      "${envs[@]}" bash "$SUT" "$@" 2>&1 )
}
calls() { cat "$CALLLOG"; }
# line_of <substring>: the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }
# surface_dir: the directory the last capture of a drawn surface served, which
# holds its page and sits beside its script.
surface_dir() { sed -n 's/.*\[screenshot\] \[\(.*\)\.md\] \[--serve-dir\].*/\1/p' "$CALLLOG" | head -n 1; }

echo "# usage errors exit 2 and run nothing"
out="$(run --)"; rc=$?
eq "$rc" 2 "no kind exits 2"
out="$(run -- photo --output "$OUT")"; rc=$?
eq "$rc" 2 "an unknown kind exits 2"
has "unknown kind 'photo'" "$out" "it names the unknown kind"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP")"; rc=$?
eq "$rc" 2 "a missing --output exits 2"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$WORK/shot.jpg")"; rc=$?
eq "$rc" 2 "an --output that is not a .png exits 2"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$WORK/held#state.png")"; rc=$?
eq "$rc" 2 "an --output name holding '#' exits 2"
has "alt text" "$out" "it says gh would read the '#' as alt text"
out="$(run -- page --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 2 "page without --script exits 2"
out="$(run -- page --script "$SCRIPT" --output "$OUT")"; rc=$?
eq "$rc" 2 "page with no app target exits 2"
has "exactly one of --serve-dir / --serve / --base-url (got 0)" "$out" "it names the app-target requirement"
out="$(run -- page --script "$SCRIPT" --output "$OUT" --serve-dir "$APP" --base-url http://localhost:3000)"; rc=$?
eq "$rc" 2 "page with two app targets exits 2"
out="$(run -- page --script "$SCRIPT" --output "$OUT" --serve-dir "$APP" --selector '#board' --full-page)"; rc=$?
eq "$rc" 2 "page with both --selector and --full-page exits 2"
has "page takes --selector or --full-page, not both" "$out" "it says the two capture areas exclude each other"
eq "$(calls)" "" "the pair is refused before the engine's browser is provisioned"
out="$(run -- page --script "$SCRIPT" --output "$OUT" --serve-dir "$APP" --command ls)"; rc=$?
eq "$rc" 2 "a flag of another kind exits 2"
has "page takes no '--command'" "$out" "it names the flag the kind does not take"
for bad in 0 07 abc -1; do
  out="$(run -- page --script "$SCRIPT" --output "$OUT" --serve-dir "$APP" --port "$bad")"; rc=$?
  eq "$rc" 2 "--port $bad exits 2"
done
out="$(run -- page --script "$SCRIPT" --output "$OUT" --serve-dir)"; rc=$?
eq "$rc" 2 "a flag with no value exits 2"
out="$(run -- terminal --output "$OUT")"; rc=$?
eq "$rc" 2 "terminal with neither --command nor --text exits 2"
out="$(run -- terminal --output "$OUT" --command ls --text "$TXT")"; rc=$?
eq "$rc" 2 "terminal with both --command and --text exits 2"
out="$(run -- terminal --output "$OUT" --text "$TXT" --cwd "$WORK")"; rc=$?
eq "$rc" 2 "terminal --cwd beside --text exits 2"
out="$(run -- markdown --output "$OUT")"; rc=$?
eq "$rc" 2 "markdown without --file exits 2"
for bad in nope a/b/c /a a/ 'a b/c'; do
  out="$(run -- markdown --file "$MD" --output "$OUT" --repo "$bad")"; rc=$?
  eq "$rc" 2 "markdown --repo '$bad' exits 2"
done
eq "$(calls)" "" "no usage error reached the engine, the renderer or GitHub"

echo "# inputs that do not exist exit 1"
out="$(run -- page --script "$WORK/nope.md" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a missing --script exits 1"
out="$(run -- page --script "$SCRIPT" --serve-dir "$WORK/nope" --output "$OUT")"; rc=$?
eq "$rc" 1 "a missing --serve-dir exits 1"
out="$(run -- terminal --text "$WORK/nope.txt" --output "$OUT")"; rc=$?
eq "$rc" 1 "a missing --text exits 1"
out="$(run -- terminal --command ls --cwd "$WORK/nope" --output "$OUT")"; rc=$?
eq "$rc" 1 "a missing --cwd exits 1"
out="$(run -- markdown --file "$WORK/nope.md" --output "$OUT")"; rc=$?
eq "$rc" 1 "a missing --file exits 1"

echo "# the engine: its help must list the screenshot command, read before anything is run or rendered"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "an engine with the command captures"
P=$(line_of "provision:browser"); H=$(line_of "engine [help]"); S=$(line_of "engine [screenshot]")
ok "the browser is provisioned, then the help is read, then the capture runs (lines $P, $H, $S)" "[ '$P' -gt 0 ] && [ '$H' -gt '$P' ] && [ '$S' -gt '$H' ]"
rm -f "$WORK/ran" "$OUT"
out="$(run ENGINE_OLD=1 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "an engine without the screenshot command exits 1"
has "the SprintShow engine ($ENGINE) has no screenshot command" "$out" "it names the engine that lacks the command"
has "lists 'sprintshow screenshot'" "$out" "it says what the engine must offer"
hasnt "engine [screenshot]" "$(calls)" "nothing is captured"
ok "no PNG is written" "[ ! -e '$OUT' ]"
out="$(run ENGINE_OLD=1 -- terminal --command 'echo ran >ran' --cwd "$WORK" --output "$OUT")"; rc=$?
eq "$rc" 1 "a terminal on an engine without the command exits 1"
ok "the command does not run" "[ ! -e '$WORK/ran' ]"
hasnt "[$RENDERER]" "$(calls)" "the renderer does not run"
out="$(run ENGINE_OLD=1 -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a markdown capture on an engine without the command exits 1"
hasnt "gh api" "$(calls)" "GitHub's renderer is not asked"
out="$(run HELP_RC=1 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "an engine whose CLI does not run exits 1"
has "the SprintShow engine's CLI did not run ('sprintshow help' exited 1): SyntaxError: Unexpected token" "$out" "it says the CLI failed, with the CLI's own error"
hasnt "has no screenshot command" "$out" "a CLI that failed is not reported as one without the command"
hasnt "engine [screenshot]" "$(calls)" "nothing is captured when the CLI fails"

echo "# page: the engine's screenshot command runs with the options it is given, by absolute path, on the engine checkout"
rm -rf "$WORK/shots"
out="$(run -- page --script demo.md --serve-dir app --output shots/shot.png --port 4321 --selector '#board')"; rc=$?
eq "$rc" 0 "a capture exits 0"
has "node [$CLI] [screenshot] [$SCRIPT] [--serve-dir] [$APP] [--port] [4321] [--selector] [#board] [-o] [$OUT] [--scale] [2]" "$(calls)" "the checkout's CLI captures with the script, its options, absolute paths, and a scale of 2"
hasnt "[$RENDERER]" "$(calls)" "a page is not drawn by the renderer"
hasnt "--transparent" "$(calls)" "a page keeps its own background"
has "captured $OUT (page, 1948x1132 px, " "$out" "the last line names the PNG and its pixel size"
ok "the PNG is on disk, in the directory --output named" "[ -s '$OUT' ]"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --full-page --output "$OUT")"; rc=$?
eq "$rc" 0 "a --full-page capture exits 0"
has "node [$CLI] [screenshot] [$SCRIPT] [--serve-dir] [$APP] [--full-page] [-o] [$OUT] [--scale] [2]" "$(calls)" "--full-page reaches the engine"

echo "# page: --serve with --cwd, and --base-url, are forwarded"
out="$(run -- page --script "$SCRIPT" --serve 'npm run dev' --port 5175 --cwd "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "a --serve capture exits 0"
has "[--serve] [npm run dev] [--port] [5175] [--cwd] [$APP]" "$(calls)" "the dev-server command, its port and its directory reach the engine"
out="$(run -- page --script "$SCRIPT" --base-url http://localhost:3000 --output "$OUT")"; rc=$?
eq "$rc" 0 "a --base-url capture exits 0"
has "[--base-url] [http://localhost:3000]" "$(calls)" "the base URL reaches the engine"

echo "# page: a --serve command is told its port as PORT, and --port 0 picks a free one"
out="$(run -- page --script "$SCRIPT" --serve 'npm run dev' --port 5175 --cwd "$APP" --output "$OUT")"; rc=$?
has "engine-env PORT=5175" "$(calls)" "--port reaches the engine's environment as PORT, which its --serve command inherits"
out="$(run FREE_PORT=50123 -- page --script "$SCRIPT" --serve 'go run ./cmd/helm-fixture' --port 0 --cwd "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "a --port 0 capture exits 0"
has "[--serve] [go run ./cmd/helm-fixture] [--port] [50123] [--cwd] [$APP]" "$(calls)" "the engine waits on the free port the pick found"
has "engine-env PORT=50123" "$(calls)" "and the --serve command inherits it as PORT"
P=$(line_of "node [-e]"); H=$(line_of "[help]"); S=$(line_of "[screenshot]")
ok "the port is picked after the engine resolves and before the capture (lines $H, $P, $S)" "[ '$H' -gt 0 ] && [ '$P' -gt '$H' ] && [ '$S' -gt '$P' ]"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
has "engine-env PORT=unset" "$(calls)" "a capture with no --serve command sets no PORT"
out="$(run -- page --script "$SCRIPT" --serve 'npm run dev' --output "$OUT")"; rc=$?
has "engine-env PORT=unset" "$(calls)" "nor does a --serve capture with no --port, which waits on the engine's own default"
for target in "--serve-dir $APP" "--base-url http://localhost:3000"; do
  # shellcheck disable=SC2086 # the target is a flag and its value
  out="$(run -- page --script "$SCRIPT" $target --port 0 --output "$OUT")"; rc=$?
  eq "$rc" 2 "--port 0 with ${target%% *} exits 2"
  has "give it with --serve only" "$out" "it says --port 0 is for a --serve command"
done
for got in "" 0 abc; do
  out="$(run FREE_PORT="$got" -- page --script "$SCRIPT" --serve 'go run ./cmd/helm-fixture' --port 0 --output "$OUT")"; rc=$?
  eq "$rc" 1 "a free-port pick that answers '$got' exits 1"
  has "could not find a free port for the --serve command" "$out" "it says no port was found"
  hasnt "[screenshot]" "$(calls)" "and nothing is captured"
done

echo "# page: a step whose proof failed still yields the capture -> exit 3"
out="$(run ENGINE_MODE=failed -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 3 "a capture with a failed proof exits 3"
has "captured $OUT (page, 1948x1132 px, " "$out" "it names the PNG"
has "but 2 step(s) failed their proof" "$out" "it counts the failed steps"
out="$(run ENGINE_MODE=failed-nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a failed-proof report with no PNG exits 1"

echo "# terminal and markdown: a drawn surface whose one step fails its proof is no capture -> exit 1"
out="$(run ENGINE_MODE=failed -- terminal --text "$TXT" --output "$OUT")"; rc=$?
eq "$rc" 1 "a terminal surface the engine cannot prove is drawn exits 1"
has "capture failed (sprintshow screenshot exited 3)" "$out" "it reports the engine's exit"
hasnt "captured $OUT (" "$out" "it reports no capture"
out="$(run ENGINE_MODE=failed -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a markdown surface the engine cannot prove is drawn exits 1"
has "capture failed (sprintshow screenshot exited 3)" "$out" "it reports the engine's exit"
hasnt "captured $OUT (" "$out" "it reports no capture"

echo "# fail closed: no PNG, an empty one, or a file that is not a PNG"
out="$(run ENGINE_MODE=error -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "an engine error exits 1"
has "capture failed (sprintshow screenshot exited 1)" "$out" "it reports the engine's failure"
has "no visible \`#board\` to capture" "$out" "the engine's own error reaches the caller"
out="$(run ENGINE_MODE=nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "success with no file exits 1"
has "does not exist" "$out" "it catches the missing PNG"
out="$(run ENGINE_MODE=empty -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "an empty file exits 1"
has "is empty" "$out" "it catches the empty PNG"
out="$(run ENGINE_MODE=notpng -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a file that is not a PNG exits 1"
has "is not a PNG" "$out" "it checks the PNG signature"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01' >"$OUT"
out="$(run ENGINE_MODE=nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a PNG left by an earlier run does not pass for this one"
ok "the earlier PNG was removed before the capture" "[ ! -e '$OUT' ]"

echo "# terminal: the command runs in --cwd, stdout and stderr together, stdin closed"
mkdir -p "$WORK/repo"; printf 'from the reviewed tree\n' >"$WORK/repo/marker"
CMD='cat marker; echo "to stderr" >&2; if read -r line; then echo "read: $line"; else echo "stdin closed"; fi; exit 3'
# Input waits on the script's stdin, so a command that could read it would.
out="$(printf 'typed\n' | run -- terminal --command "$CMD" --cwd "$WORK/repo" --title 'gc-toolkit' --columns 100 --max-lines 50 --output "$OUT")"; rc=$?
eq "$rc" 0 "a command that exits 3 still captures"
has "captured $OUT (terminal, 1948x1132 px, " "$out" "it names the PNG"
has "the command exited 3" "$out" "the last line gives the command's exit status"
H="$(cat "$HANDED" 2>/dev/null)"
has "from the reviewed tree" "$H" "the command ran in --cwd"
has "to stderr" "$H" "stderr is captured with stdout"
has "stdin closed" "$H" "the command reads no input"
D=$(surface_dir)
case "$D" in "$TMPD"/demo-screenshot.*/surface) printf 'ok   - %s\n' "the surface is served from a directory of the capture's own" ;; *) printf 'FAIL - %s\n     got: %s\n' "the surface is served from a directory of the capture's own" "$D"; FAIL=1 ;; esac
has "node [$RENDERER] [terminal] [--text] [" "$(calls)" "the renderer draws the captured output"
has "[--prompt] [$CMD] [--title] [gc-toolkit] [--columns] [100] [--max-lines] [50] [--output] [$D/index.html]" "$(calls)" "the command is the prompt line, the window options reach the renderer, and its page is the one served"
has "node [$CLI] [screenshot] [$D.md] [--serve-dir] [$D] [--selector] [#surface] [--transparent] [-o] [$OUT] [--scale] [2]" "$(calls)" "the engine captures the drawn surface's element, with no page background, at a scale of 2"
R=$(line_of "[$RENDERER]"); S=$(line_of "engine [screenshot]")
ok "the surface is drawn before the engine captures it (renderer line $R, capture line $S)" "[ '$R' -gt 0 ] && [ '$S' -gt '$R' ]"
has "drawn by the renderer" "$(cat "$SERVED" 2>/dev/null)" "the page the engine serves is the renderer's"
eq "$(cat "$SCRIPT_HANDED" 2>/dev/null)" "# Demo: terminal
**Start:** \`/\`

## Steps
1. **The surface is drawn**
   _Prove:_ the surface is on the page \`visible #surface\`" "the engine's script opens the page and proves the surface is drawn"
out="$(run -- terminal --text "$TXT" --output "$OUT")"; rc=$?
eq "$rc" 0 "captured output renders"
has "[--text] [$TXT]" "$(calls)" "the renderer gets the captured output's absolute path"
hasnt "[--prompt]" "$(calls)" "output captured earlier has no prompt line"
hasnt "exited" "$out" "no exit status is claimed for output this run did not produce"
out="$(run RENDER_RC=1 -- terminal --text "$TXT" --output "$OUT")"; rc=$?
eq "$rc" 1 "a renderer that fails exits 1"
has "the renderer could not draw the terminal surface" "$out" "it says the surface was not drawn"
hasnt "engine [screenshot]" "$(calls)" "nothing is captured without a drawn surface"

echo "# markdown: GitHub's renderer, in the repository's context, then the renderer and the engine"
out="$(run -- markdown --file "$MD" --repo octo/widgets --title 'Rendered comment' --expand --output "$OUT")"; rc=$?
eq "$rc" 0 "a markdown capture exits 0"
has "gh api --hostname github.com markdown --input " "$(calls)" "it asks GitHub's markdown API on github.com"
eq "$(jq -r '.text' "$GH_REQ" 2>/dev/null)" "$(cat "$MD")" "the request carries the file's text as it stands"
eq "$(jq -r '.mode + " " + .context' "$GH_REQ" 2>/dev/null)" "gfm octo/widgets" "it renders GitHub-flavoured, in the --repo context"
has "<summary>trail</summary>" "$(cat "$HANDED" 2>/dev/null)" "the renderer gets the HTML GitHub returned"
D=$(surface_dir)
has "[--title] [Rendered comment] [--expand] [--output] [$D/index.html]" "$(calls)" "the header and the expand option reach the renderer"
has "node [$CLI] [screenshot] [$D.md] [--serve-dir] [$D] [--selector] [#surface] [--transparent] [-o] [$OUT] [--scale] [2]" "$(calls)" "the engine captures the drawn comment's element"
G=$(line_of "gh api"); R=$(line_of "[$RENDERER]"); S=$(line_of "engine [screenshot]")
ok "GitHub answers, then the renderer draws, then the engine captures (lines $G, $R, $S)" "[ '$G' -gt 0 ] && [ '$R' -gt '$G' ] && [ '$S' -gt '$R' ]"
has "# Demo: markdown" "$(cat "$SCRIPT_HANDED" 2>/dev/null)" "the engine's script names the kind"
RIG="$TMPD/rig"; git init -q "$RIG" && git -C "$RIG" remote add origin git@github.com:zookanalytics/gc-toolkit.git
out="$(run GC_RIG_ROOT="$RIG" -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 0 "the rig's origin gives the context"
eq "$(jq -r '.context' "$GH_REQ" 2>/dev/null)" "zookanalytics/gc-toolkit" "references resolve in the rig's origin"
NOGIT="$TMPD/norepo"; mkdir -p "$NOGIT"
out="$(cd "$NOGIT" && env -i PATH="$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" HANDED="$HANDED" GH_REQ="$GH_REQ" \
  ENGINE_STUB="$ENGINE_STUB" SCRIPT_HANDED="$SCRIPT_HANDED" SERVED="$SERVED" SS_RIG="$ENGINE" bash "$SUT" markdown --file "$MD" --output "$OUT" 2>&1)"; rc=$?
eq "$rc" 0 "no origin still renders"
has "render without a repository context" "$out" "it says references render without a context"
eq "$(jq -r 'has("context")' "$GH_REQ" 2>/dev/null)" "false" "the request names no context"
out="$(run GH_RC=1 -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a renderer failure exits 1"
has "GitHub's markdown renderer failed: HTTP 502" "$out" "it passes the renderer's error on"
hasnt "[$RENDERER]" "$(calls)" "nothing is drawn without GitHub's rendering"
hasnt "engine [screenshot]" "$(calls)" "nothing is captured without GitHub's rendering"
out="$(run GH_EMPTY=1 -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "an empty rendering exits 1"
has "returned nothing" "$out" "it says the renderer returned nothing"

echo "# markdown: gh and jq are checked with the arguments, before the engine is resolved"
# The stubs without gh, and without jq. A later PATH in run's arguments wins.
# With no jq the engine lookup cannot read the rig list and takes the published
# package, so that directory has an npx, which logs what it would install.
NOGH="$TMPD/bin-nogh"; mkdir -p "$NOGH"
for s in jq node npm gc; do ln -s "$BIN/$s" "$NOGH/$s"; done
NOJQ="$TMPD/bin-nojq"; mkdir -p "$NOJQ"
for s in node npm gc gh; do ln -s "$BIN/$s" "$NOJQ/$s"; done
cat >"$NOJQ/npx" <<'NPX'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"${CALLLOG:?}"
exit 0
NPX
chmod +x "$NOJQ/npx"
out="$(run PATH="$NOGH:$FARM" -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a markdown capture with no gh exits 1"
has "gh not found; GitHub's markdown renderer is reached through it" "$out" "it says gh is missing"
eq "$(calls)" "" "nothing is installed or provisioned, and the engine is not called, before it says so"
out="$(run PATH="$NOJQ:$FARM" -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a markdown capture with no jq exits 1"
has "jq not found; it builds the renderer's request" "$out" "it says jq is missing"
eq "$(calls)" "" "nor before it says jq is missing"

# --- the renderers, in a real node ------------------------------------------
NODE_BIN=""
for c in "$(command -v node 2>/dev/null)" /opt/homebrew/bin/node /usr/local/bin/node; do
  [ -n "$c" ] && [ -x "$c" ] || continue
  v=$("$c" --version 2>/dev/null | sed 's/^v//'); m=${v%%.*}
  case "$m" in ''|*[!0-9]*) continue ;; esac
  [ "$m" -ge 18 ] && { NODE_BIN="$c"; break; }
done
if [ -z "$NODE_BIN" ]; then
  echo "# the renderers: SKIPPED (no Node 18 or later on this host)"
else
  echo "# the renderers ($NODE_BIN)"
  # js <expression>: what the expression evaluates to, with the renderer imported
  # as m and node's readFileSync as read.
  js() { "$NODE_BIN" --input-type=module -e "import * as m from '$RENDERER'; import { readFileSync as read } from 'node:fs'; const v = await ($1); process.stdout.write(typeof v === 'string' ? v : JSON.stringify(v));" 2>&1; }

  r=$(js "m.ansiToHtml('\x1b[1;32mok\x1b[0m plain').html")
  eq "$r" '<span style="color:#0dbc79;font-weight:bold">ok</span> plain' "SGR colour and weight become a span, and a reset ends it"
  r=$(js "m.ansiToHtml('\x1b[38;5;208ma\x1b[48;2;1;2;3mb\x1b[39;49m c').html")
  eq "$r" '<span style="color:#ff8700">a</span><span style="color:#ff8700;background:#010203">b</span> c' "256-colour and truecolour, and 39/49 restore the defaults"
  r=$(js "m.ansiToHtml('\x1b[7minv\x1b[27m').html")
  eq "$r" '<span style="color:#1e1e1e;background:#cccccc">inv</span>' "inverse swaps the default colours"
  r=$(js "m.ansiToHtml('a\x1b[2Kb\x1b]0;title\x07c\x1b(Bd').html")
  eq "$r" 'abcd' "every escape that is not SGR draws nothing"
  r=$(js "m.ansiToHtml('10%\r\x1b[31m50%\r100%').html")
  eq "$r" '<span style="color:#cd3131">100%</span>' "a carriage return keeps the last redraw, with the styles earlier segments set"
  r=$(js "m.ansiToHtml('abc\r\r\nnext\r').html")
  eq "$r" 'abc
next' "a carriage return that ends a line redraws nothing"
  r=$(js "m.ansiToHtml('\x1b[38:2::1:2:3ma\x1b[48:5:208mb\x1b[39;49;4:3mc\x1b[4:0md').html")
  eq "$r" '<span style="color:#010203">a</span><span style="color:#010203;background:#ff8700">b</span><span style="text-decoration:underline">c</span>d' "a colon joins one parameter's sub-parameters: a colour, an underline style"
  r=$(js "m.ansiToHtml('\x1b[58;2;1;2;3ma\x1b[58:5:1mb\x1b[>4;2mc').html")
  eq "$r" 'abc' "an underline colour is skipped, and a CSI with a private marker sets nothing"
  r=$(js "m.ansiToHtml('<a href=\"x\">&</a>').html")
  eq "$r" '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;' "text is HTML-escaped"
  r=$(js "m.ansiToHtml('a\x07b\x08c\x00d').html")
  eq "$r" 'abcd' "control bytes draw nothing"
  r=$(js "m.ansiToHtml('ab\tc\nxyz').widest")
  eq "$r" '9' "the widest line counts a tab to its next stop"
  r=$(js "(() => { const o = m.ansiToHtml('1\n2\n3\n4\n', 2); return o.html + '|' + o.hidden; })()")
  eq "$r" '1
2|2' "lines past the cap are cut and counted, and a final newline is not a line"
  r=$(js "m.terminalDocument({ text: 'x\n', prompt: 'ls -l', title: '<t>', maxLines: 1 })")
  has '<span class="prompt">$</span> ls -l' "$r" "the command is the prompt line"
  has '<div class="title">&lt;t&gt;</div>' "$r" "the title is escaped"
  has 'width: 40ch' "$r" "a narrow output keeps the narrowest window"
  hasnt 'more line(s)' "$r" "output within the cap shows no cut line"
  has '<div class="terminal" id="surface">' "$r" "the terminal window is the surface a capture crops to"
  hasnt '<script' "$r" "the terminal page carries no script"
  r=$(js "m.terminalDocument({ text: 'a\nb\nc\n', maxLines: 1 })")
  has '[2 more line(s) not shown]' "$r" "a cut says how many lines it hid"
  r=$(js "m.terminalDocument({ text: 'x'.repeat(300) + '\n', columns: 100 })")
  has 'width: 100ch' "$r" "a wide output wraps at --columns"
  r=$(js "m.commentDocument({ fragment: '<details><summary>s</summary>x</details><detailsx>', title: 'a&b', expand: true })")
  has '<details open><summary>s</summary>' "$r" "--expand opens each <details>"
  has '</details><detailsx>' "$r" "an element merely named like details is left alone"
  has '<div class="comment-header">a&amp;b</div>' "$r" "the header is escaped"
  has '<div class="comment" id="surface">' "$r" "the comment box is the surface a capture crops to"
  r=$(js "m.commentDocument({ fragment: '<details><summary>s</summary></details>' })")
  hasnt 'details open' "$r" "a <details> stays collapsed without --expand"
  hasnt '<div class="comment-header">' "$r" "no title draws no header"
  r=$(js "(() => { try { m.parseArgs(['page', '--output', 'o.html', '--script', 'd.md']); return 'parsed'; } catch (e) { return e.message; } })()")
  eq "$r" "a kind is required: terminal or markdown (got 'page')" "the renderer draws no page kind, which the engine drives itself"
  r=$(js "(() => { try { m.parseArgs(['toString', '--output', 'o.html']); return 'parsed'; } catch (e) { return e.message; } })()")
  eq "$r" "a kind is required: terminal or markdown (got 'toString')" "a name every object inherits is no kind"
  r=$(js "(() => { try { m.parseArgs(['terminal', '--output', 'o.html', '--text', 't', '--html', 'h']); return 'parsed'; } catch (e) { return e.message; } })()")
  eq "$r" 'terminal takes no --html' "the renderer refuses a flag of another kind"
  r=$(js "m.parseArgs(['markdown', '--output', 'o.html', '--html', 'h', '--expand'])")
  eq "$r" '{"kind":"markdown","output":"o.html","html":"h","expand":true}' "the renderer parses a markdown call"

  # GitHub's markdown API output, kept verbatim. A mermaid fence comes back as
  # an enrichment section holding the fence's source and a loading spinner.
  cat >"$TMPD/mermaid.html" <<'HTML'
<section class="js-render-needs-enrichment render-needs-enrichment position-relative" data-identity="324bbaed-8ff8-4c0b-b999-1620f27986cc" data-host="https://viewscreen.githubusercontent.com" data-src="https://viewscreen.githubusercontent.com/markdown/mermaid?docs_host=https%3A%2F%2Fdocs.github.com" data-type="mermaid" aria-label="mermaid rendered output container">
  <div class="js-render-enrichment-target" data-json="{&quot;data&quot;:&quot;graph LR\n  A[Claim work] --&gt; B[Review]\n&quot;}" data-plain="graph LR
  A[Claim work] --&gt; B[Review]
" dir="auto">
    <div class="render-plaintext-hidden" dir="auto">
      <pre lang="mermaid" aria-label="Raw mermaid code" class="notranslate">graph LR
  A[Claim work] --&gt; B[Review]
</pre>
    </div>
  </div>
  <span class="js-render-enrichment-loader d-flex flex-justify-center flex-items-center width-full" style="min-height:100px" role="presentation">
    <span data-view-component="true">
  <svg style="box-sizing: content-box; color: var(--color-icon-primary);" width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true" data-view-component="true" class="octospinner mx-auto tmp-mx-auto anim-rotate">
    <circle cx="8" cy="8" r="7" stroke="currentColor" stroke-opacity="0.25" stroke-width="2" vector-effect="non-scaling-stroke" fill="none"></circle>
    <path d="M15 8a7.002 7.002 0 00-7-7" stroke="currentColor" stroke-width="2" stroke-linecap="round" vector-effect="non-scaling-stroke"></path>
</svg>    <span class="sr-only">Loading</span>
</span>
  </span>
</section>
HTML
  # Every other enrichment type opens the same section, with its own type.
  cat >"$TMPD/maps.html" <<'HTML'
<section class="js-render-needs-enrichment render-needs-enrichment position-relative" data-identity="01f85847-b958-48c9-bf40-aafd91a97b93" data-host="https://viewscreen.githubusercontent.com" data-src="https://viewscreen.githubusercontent.com/markdown/geojson?docs_host=https%3A%2F%2Fdocs.github.com" data-type="geojson" aria-label="geojson rendered output container">
</section>
<section class="js-render-needs-enrichment render-needs-enrichment position-relative" data-identity="0aa274a0-27f6-4428-a2a1-301fe158454a" data-host="https://viewscreen.githubusercontent.com" data-src="https://viewscreen.githubusercontent.com/markdown/topojson?docs_host=https%3A%2F%2Fdocs.github.com" data-type="topojson" aria-label="topojson rendered output container">
</section>
<section class="js-render-needs-enrichment render-needs-enrichment position-relative" data-identity="c1b5b5d3-c90b-4c1e-b75e-491f86bbd42b" data-host="https://viewscreen.githubusercontent.com" data-src="https://viewscreen.githubusercontent.com/markdown/stl?docs_host=https%3A%2F%2Fdocs.github.com" data-type="stl" aria-label="stl rendered output container">
</section>
HTML
  # Math, inline and on lines of its own, comes back as its TeX.
  cat >"$TMPD/math.html" <<'HTML'
<p dir="auto">Inline <math-renderer class="js-inline-math" style="display: inline-block" data-run-id="673979dbfab6cd1763fe9b43579747f0">$x^2 + 1$</math-renderer> here.</p>
<p dir="auto"><math-renderer class="js-display-math" style="display: block" data-run-id="e92a7e1d009e85a28f5b4de55c7a0d06">$$
E = mc^2
$$</math-renderer></p>
HTML
  # What draws from its own markup: a table, a picture and an emoji in GitHub's
  # wrapper elements, an issue link, and code that names the markers above as
  # text.
  cat >"$TMPD/drawn.html" <<'HTML'
<markdown-accessiblity-table><table role="table">
<thead>
<tr>
<th>a</th>
<th>b</th>
</tr>
</thead>
<tbody>
<tr>
<td>1</td>
<td>2</td>
</tr>
</tbody>
</table></markdown-accessiblity-table>
<p dir="auto"><a class="issue-link js-issue-link" data-error-text="Failed to load title" data-id="5862710674" data-permission-text="Title is private" data-url="https://github.com/zookanalytics/gc-toolkit/issues/1266" data-hovercard-type="pull_request" data-hovercard-url="/zookanalytics/gc-toolkit/pull/1266/hovercard" href="https://github.com/zookanalytics/gc-toolkit/pull/1266">#1266</a></p>
<p dir="auto"><themed-picture data-catalyst-inline="true"><picture><source media="(prefers-color-scheme: dark)" srcset="https://camo.githubusercontent.com/593b9d749a3d6d38d285dc0a0c1e8dab748afc1d424e03cd0064954796371962/68747470733a2f2f6578616d706c652e636f6d2f642e706e67" data-canonical-src="https://example.com/d.png"><img alt="pic" src="https://camo.githubusercontent.com/7b2d815f6cdd1b13c10bec8b2b9e1bde64ecab1aae71164f8b393dea9ddfb08d/68747470733a2f2f6578616d706c652e636f6d2f6c2e706e67" data-canonical-src="https://example.com/l.png"></picture></themed-picture></p>
<p dir="auto">Unicode 👍 ✅ <g-emoji class="g-emoji" alias="warning">⚠️</g-emoji> here.</p>
<p dir="auto"><code class="notranslate">&lt;math-renderer&gt;</code> and <code class="notranslate">js-render-needs-enrichment</code> as code.</p>
<div class="highlight highlight-text-html-basic" dir="auto"><pre class="notranslate"><span class="pl-kos">&lt;</span><span class="pl-ent">section</span> <span class="pl-c1">class</span>="<span class="pl-s">js-render-needs-enrichment</span>"<span class="pl-kos">&gt;</span><span class="pl-kos">&lt;</span><span class="pl-ent">math-renderer</span><span class="pl-kos">&gt;</span>$x$<span class="pl-kos">&lt;/</span><span class="pl-ent">math-renderer</span><span class="pl-kos">&gt;</span><span class="pl-kos">&lt;/</span><span class="pl-ent">section</span><span class="pl-kos">&gt;</span></pre></div>
HTML
  { printf '<details><summary>trail</summary>\n'; cat "$TMPD/mermaid.html"; printf '</details>\n'; } >"$TMPD/collapsed.html"
  r=$(js "m.unfinishedBlocks(read('$TMPD/mermaid.html', 'utf8'))")
  eq "$r" '["mermaid"]' "a mermaid fence, as GitHub's markdown API returns it, is a block github.com finishes"
  r=$(js "m.unfinishedBlocks(read('$TMPD/maps.html', 'utf8'))")
  eq "$r" '["geojson","topojson","stl"]' "every other enrichment section is one too, named by its type"
  r=$(js "m.unfinishedBlocks(read('$TMPD/math.html', 'utf8'))")
  eq "$r" '["math","math"]' "inline math and math on lines of its own are blocks github.com finishes"
  r=$(js "m.unfinishedBlocks('<p><diagram-viewer data-src=\"x\">a</diagram-viewer></p>')")
  eq "$r" '["<diagram-viewer>"]' "a custom element not known to draw from its own markup is one too"
  r=$(js "m.unfinishedBlocks(read('$TMPD/drawn.html', 'utf8'))")
  eq "$r" '[]' "GitHub's table, picture and emoji wrappers, an issue link, and code naming the markers are not"
  r=$(js "(() => { try { m.commentDocument({ fragment: read('$TMPD/mermaid.html', 'utf8') }); return 'drawn'; } catch (e) { return e.message; } })()")
  has "github.com finishes part of this comment with its page script, which this page does not carry: mermaid (1)." "$r" "a comment holding a mermaid block is not drawn, and the refusal names the block"
  r=$(js "(() => { try { m.commentDocument({ fragment: read('$TMPD/math.html', 'utf8') + read('$TMPD/mermaid.html', 'utf8'), expand: true }); return 'drawn'; } catch (e) { return e.message; } })()")
  has ": math (2), mermaid (1)." "$r" "the refusal counts each kind of block, in the order the comment holds them"
  r=$(js "(() => { try { m.commentDocument({ fragment: read('$TMPD/collapsed.html', 'utf8') }); return 'drawn'; } catch (e) { return e.message; } })()")
  has "mermaid (1)" "$r" "a block in a collapsed <details> is refused too, since --expand would show it"
  r=$(js "m.commentDocument({ fragment: read('$TMPD/drawn.html', 'utf8') })")
  has '<div class="markdown-body"><markdown-accessiblity-table><table role="table">' "$r" "a comment with no such block is drawn as GitHub returned it"
  has '<g-emoji class="g-emoji" alias="warning">' "$r" "an emoji in GitHub's wrapper is drawn as GitHub returned it"

  # Run as a script, the renderer writes the page and nothing else.
  printf '\033[31mred\033[0m\n' >"$TMPD/real.txt"
  out=$("$NODE_BIN" "$RENDERER" terminal --text "$TMPD/real.txt" --output "$TMPD/real.html" --title t 2>&1); rc=$?
  eq "$rc" 0 "the renderer exits 0 once the page is written"
  eq "$out" "" "the renderer prints nothing on success"
  has '<span style="color:#cd3131">red</span>' "$(cat "$TMPD/real.html" 2>/dev/null)" "the page holds the rendered output"
  out=$("$NODE_BIN" "$RENDERER" terminal --output "$TMPD/real.html" 2>&1); rc=$?
  eq "$rc" 2 "the renderer exits 2 on bad arguments"
  has "terminal needs --text" "$out" "it names what is missing"
  out=$("$NODE_BIN" "$RENDERER" markdown --html "$TMPD/nope.html" --output "$TMPD/real2.html" 2>&1); rc=$?
  eq "$rc" 1 "the renderer exits 1 when its input cannot be read"
  ok "no page is written for input that cannot be read" "[ ! -e '$TMPD/real2.html' ]"
  out=$("$NODE_BIN" "$RENDERER" markdown --html "$TMPD/mermaid.html" --output "$TMPD/refused.html" 2>&1); rc=$?
  eq "$rc" 1 "the renderer exits 1 for a comment it refuses"
  has "demo-screenshot.mjs: github.com finishes part of this comment" "$out" "it says why"
  ok "no page is written for a refused comment" "[ ! -e '$TMPD/refused.html' ]"

  echo "# page: the real node picks the free port"
  out="$(run REAL_NODE="$NODE_BIN" -- page --script "$SCRIPT" --serve 'go run ./cmd/helm-fixture' --port 0 --output "$OUT")"; rc=$?
  eq "$rc" 0 "a --port 0 capture exits 0 with the port the real node found"
  P=$(sed -n 's/^engine-env PORT=//p' "$CALLLOG" | head -n 1)
  ok "the port is one a server can listen on (got '$P')" "case '$P' in ''|*[!0-9]*|0*) false ;; *) [ '$P' -le 65535 ] ;; esac"
  has "[--port] [$P]" "$(calls)" "the engine waits on that port"

  echo "# markdown end to end, on HTML GitHub returned, through the real renderer"
  rm -f "$OUT"
  out="$(run REAL_NODE="$NODE_BIN" GH_HTML="$TMPD/mermaid.html" -- markdown --file "$MD" --output "$OUT")"; rc=$?
  eq "$rc" 1 "markdown GitHub returns with a mermaid block exits 1"
  has "which this page does not carry: mermaid (1)." "$out" "the renderer's refusal reaches the caller"
  has "the renderer could not draw the markdown surface" "$out" "the script says the surface was not drawn"
  hasnt "engine [screenshot]" "$(calls)" "nothing is captured"
  ok "no PNG is written" "[ ! -e '$OUT' ]"
  out="$(run REAL_NODE="$NODE_BIN" GH_HTML="$TMPD/drawn.html" -- markdown --file "$MD" --output "$OUT")"; rc=$?
  eq "$rc" 0 "markdown GitHub returns with no such block is drawn and captured"
  has '<markdown-accessiblity-table><table role="table">' "$(cat "$SERVED" 2>/dev/null)" "the page the engine serves is the real renderer's, drawn from GitHub's HTML"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all demo-screenshot assertions passed"; else echo "FAIL: demo-screenshot had failures"; fi
exit "$FAIL"
