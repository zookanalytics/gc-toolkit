#!/usr/bin/env bash
# demo-screenshot.test.sh — hermetic coverage of the screenshot modality.
#
# demo-screenshot.sh validates its arguments, resolves the SprintShow engine and
# provisions its browser, prepares what the driver renders (a command's captured
# output, or GitHub's rendering of a markdown file), runs the driver, and checks
# the PNG it leaves. Every case runs under `env -i` with a PATH of a coreutils
# symlink farm and stubs for node, npm, npx, gc and gh, so nothing reaches the
# network, a browser, or a city. The node stub stands in for the driver: it logs
# its argv, keeps a copy of the file it was handed, and leaves the PNG, or the
# failure, each case plants.
#
# The driver's renderers are pure functions of their input, so the last part
# imports demo-screenshot.mjs into a real node, when the host has Node 18 or
# later, and checks what they emit; without one those cases are skipped.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/demo-screenshot.sh"
DRIVER="$HERE/demo-screenshot.mjs"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }
[ -f "$DRIVER" ] || { echo "not found: $DRIVER" >&2; exit 2; }

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

# Stubs. node answers --version with $NODE_VERSION and otherwise stands in for
# the driver; npx stands in for the published engine and hands a driver call to
# node; npm records what it runs and where; gc lists the sprintshow rig at
# $SS_RIG; gh stands in for GitHub's markdown renderer. Each logs to $CALLLOG.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
BIN="$TMPD/bin"; mkdir -p "$BIN"
ln -s "$JQ" "$BIN/jq"
cat >"$BIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "${NODE_VERSION:-v24.0.0}"; exit 0; fi
printf 'node' >>"${CALLLOG:?}"; printf ' [%s]' "$@" >>"$CALLLOG"; printf '\n' >>"$CALLLOG"
o=""; prev=""
for a in "$@"; do
  [ "$prev" = "--output" ] && o="$a"
  [ "$prev" = "--text" ] && cp "$a" "${HANDED:?}"
  [ "$prev" = "--html" ] && cp "$a" "${HANDED:?}"
  prev="$a"
done
# A PNG signature and an IHDR chunk naming a 1948x1132 image.
png() { printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x07\x9c\x00\x00\x04\x6c\x08\x06\x00\x00\x00' >"$1"; }
case "${DRIVER_MODE:-png}" in
  png)     png "$o" ;;
  failed)  png "$o"; echo "demo-screenshot.mjs: 2 step(s) failed their proof"; exit 3 ;;
  failed-nofile) echo "demo-screenshot.mjs: 2 step(s) failed their proof"; exit 3 ;;
  error)   echo "demo-screenshot.mjs: boom" >&2; exit 1 ;;
  nofile)  : ;;
  empty)   : >"$o" ;;
  notpng)  echo 'not a png' >"$o" ;;
esac
exit 0
NODE
cat >"$BIN/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s (in %s)\n' "$*" "$PWD" >>"${CALLLOG:?}"
if [ "$*" = "run provision:browser" ] && [ "${INSTALL_RC:-0}" != 0 ]; then
  printf 'Failed to install browsers\n'; exit "$INSTALL_RC"
fi
exit 0
NPM
cat >"$BIN/npx" <<'NPX'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"${CALLLOG:?}"
[ "$1 $2 $3" = "--yes --package=@zookanalytics/sprintshow --" ] || { echo "npx stub: unexpected call: $*" >&2; exit 97; }
shift 3
case "$1" in
  playwright)
    if [ "${INSTALL_RC:-0}" != 0 ]; then printf 'Failed to install browsers\n'; exit "$INSTALL_RC"; fi
    exit 0 ;;
  node) shift; exec "$(dirname "$0")/node" "$@" ;;
esac
echo "npx stub: unexpected call: $*" >&2; exit 97
NPX
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
[ -n "${GH_EMPTY:-}" ] || printf '<p dir="auto"><strong>Approve.</strong></p>\n<details>\n<summary>trail</summary>\n<p dir="auto">x</p>\n</details>\n'
exit 0
GH
chmod +x "$BIN"/node "$BIN"/npm "$BIN"/npx "$BIN"/gc "$BIN"/gh

# A local engine checkout with its deps installed.
ENGINE="$TMPD/sprintshow"; mkdir -p "$ENGINE/node_modules"
printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"

# Fixtures: a demo script, a static app, a markdown file, captured output.
WORK="$TMPD/work"; mkdir -p "$WORK"
SCRIPT="$WORK/demo.md"; printf '# Demo: fixture\n\n**Start:** `/`\n' >"$SCRIPT"
APP="$WORK/app"; mkdir -p "$APP"; printf '<!doctype html><title>x</title>\n' >"$APP/index.html"
MD="$WORK/comment.md"; printf '**Approve.** Nothing needs you.\n\n<details>\n<summary>trail</summary>\n\nx\n</details>\n' >"$MD"
TXT="$WORK/out.txt"; printf 'line one\nline two\n' >"$TXT"
OUT="$WORK/shots/shot.png"
CALLLOG="$TMPD/calls.log"; HANDED="$TMPD/handed"; GH_REQ="$TMPD/gh-request.json"

# run [VAR=VAL ...] -- <sut args...>: combined stdout and stderr, run from $WORK.
# The local engine is listed unless a case sets SS_RIG itself.
run() {
  local envs=(SS_RIG="$ENGINE")
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  : >"$CALLLOG"; rm -f "$HANDED" "$GH_REQ"
  ( cd "$WORK" && env -i PATH="$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" \
      CALLLOG="$CALLLOG" HANDED="$HANDED" GH_REQ="$GH_REQ" "${envs[@]}" bash "$SUT" "$@" 2>&1 )
}
calls() { cat "$CALLLOG"; }
# line_of <substring>: the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }

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
eq "$(calls)" "" "no usage error reached the engine, the renderer or the driver"

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

echo "# page: the local engine is provisioned, then the driver runs with every option, by absolute path"
rm -rf "$WORK/shots"
out="$(run -- page --script demo.md --serve-dir app --output shots/shot.png --port 4321 --selector '#board' --full-page)"; rc=$?
eq "$rc" 0 "a capture exits 0"
has "engine = local sprintshow rig ($ENGINE)" "$out" "it resolves the local engine checkout"
has "npm run provision:browser (in $ENGINE)" "$(calls)" "it provisions the browser through the engine's own Playwright"
P=$(line_of "provision:browser"); D=$(line_of "node [")
ok "the browser is provisioned before the driver runs (provision line $P, driver line $D)" "[ '$P' -gt 0 ] && [ '$D' -gt '$P' ]"
has "[$DRIVER] [page] [--output] [$OUT] [--script] [$SCRIPT] [--serve-dir] [$APP] [--port] [4321] [--selector] [#board] [--full-page] [--engine] [$ENGINE]" "$(calls)" "the driver gets the kind, every option, absolute paths, and the engine"
has "captured $OUT (page, 1948x1132 px, " "$out" "the last line names the PNG and its pixel size"
ok "the PNG is on disk, in the directory --output named" "[ -s '$OUT' ]"
hasnt "npm install" "$(calls)" "a checkout with its deps does not reinstall them"

echo "# page: --serve with --cwd, and --base-url, are forwarded"
out="$(run -- page --script "$SCRIPT" --serve 'npm run dev' --port 5175 --cwd "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "a --serve capture exits 0"
has "[--serve] [npm run dev] [--port] [5175] [--cwd] [$APP]" "$(calls)" "the dev-server command, its port and its directory reach the driver"
out="$(run -- page --script "$SCRIPT" --base-url http://localhost:3000 --output "$OUT")"; rc=$?
eq "$rc" 0 "a --base-url capture exits 0"
has "[--base-url] [http://localhost:3000]" "$(calls)" "the base URL reaches the driver"

echo "# page: a step whose proof failed still yields the capture -> exit 3"
out="$(run DRIVER_MODE=failed -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 3 "a capture with a failed proof exits 3"
has "captured $OUT (page, 1948x1132 px, " "$out" "it names the PNG"
has "but 2 step(s) failed their proof" "$out" "it counts the failed steps"
out="$(run DRIVER_MODE=failed-nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a failed-proof report with no PNG exits 1"

echo "# fail closed: no PNG, an empty one, or a file that is not a PNG"
out="$(run DRIVER_MODE=error -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a driver error exits 1"
has "capture failed (the driver exited 1)" "$out" "it reports the driver's failure"
out="$(run DRIVER_MODE=nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "success with no file exits 1"
has "does not exist" "$out" "it catches the missing PNG"
out="$(run DRIVER_MODE=empty -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "an empty file exits 1"
has "is empty" "$out" "it catches the empty PNG"
out="$(run DRIVER_MODE=notpng -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a file that is not a PNG exits 1"
has "is not a PNG" "$out" "it checks the PNG signature"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01' >"$OUT"
out="$(run DRIVER_MODE=nofile -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a PNG left by an earlier run does not pass for this one"
ok "the earlier PNG was removed before the capture" "[ ! -e '$OUT' ]"

echo "# engine resolution"
rm -rf "$ENGINE/node_modules"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "a checkout without its deps captures"
I=$(line_of "npm install (in $ENGINE)"); P=$(line_of "provision:browser")
ok "its deps are installed before the browser is provisioned (install line $I, provision line $P)" "[ '$I' -gt 0 ] && [ '$P' -gt '$I' ]"
mkdir -p "$ENGINE/node_modules"
out="$(run INSTALL_RC=1 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a failed browser install exits 1"
has "could not provision the browser ('npm run provision:browser' failed in the sprintshow rig checkout)" "$out" "it says the browser could not be provisioned"
has "Failed to install browsers" "$out" "the installer's own message reaches the caller"
hasnt "node [" "$(calls)" "the driver does not run after a failed install"
OTHER="$TMPD/other"; mkdir -p "$OTHER/node_modules"; printf '{"name":"sprintshow-notes"}\n' >"$OTHER/package.json"
out="$(run SS_RIG="$OTHER" -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "a rig named sprintshow that is not the engine is passed over"
has "engine = published @zookanalytics/sprintshow" "$out" "it falls back to the published engine"
hasnt "(in $OTHER)" "$(calls)" "nothing runs in the other rig"
out="$(run SS_RIG= -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "the published engine captures"
has "npx --yes --package=@zookanalytics/sprintshow -- playwright install chromium-headless-shell" "$(calls)" "it installs the browser through the published engine's Playwright"
has "npx --yes --package=@zookanalytics/sprintshow -- node $DRIVER page" "$(calls)" "it runs the driver beside the published engine"
hasnt "[--engine]" "$(calls)" "the driver finds the published engine itself"
hasnt "npm " "$(calls)" "it runs npm in no checkout"
out="$(run SS_RIG= INSTALL_RC=1 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "a failed published install exits 1"
has "the published engine's 'playwright install chromium-headless-shell' failed" "$out" "it says which install failed"
out="$(run NODE_VERSION=v22.17.1 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 1 "Node below 22.18 exits 1"
has "below the engine's floor of 22.18" "$out" "it names the floor"
out="$(run NODE_VERSION=v22.18.0 -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
eq "$rc" 0 "Node 22.18 captures"
mv "$BIN/node" "$BIN/node.off"
out="$(run -- page --script "$SCRIPT" --serve-dir "$APP" --output "$OUT")"; rc=$?
mv "$BIN/node.off" "$BIN/node"
eq "$rc" 1 "no node exits 1"
has "node not found" "$out" "it says node is missing"

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
has "[terminal] [--output] [$OUT] [--text] [" "$(calls)" "the driver renders the captured output"
has "[--prompt] [$CMD] [--title] [gc-toolkit] [--columns] [100] [--max-lines] [50]" "$(calls)" "the command is the prompt line, and the window options reach the driver"
out="$(run -- terminal --text "$TXT" --output "$OUT")"; rc=$?
eq "$rc" 0 "captured output renders"
has "[--text] [$TXT]" "$(calls)" "the driver gets the captured output's absolute path"
hasnt "[--prompt]" "$(calls)" "output captured earlier has no prompt line"
hasnt "exited" "$out" "no exit status is claimed for output this run did not produce"

echo "# markdown: GitHub's renderer, in the repository's context, then the driver"
out="$(run -- markdown --file "$MD" --repo octo/widgets --title 'Rendered comment' --expand --output "$OUT")"; rc=$?
eq "$rc" 0 "a markdown capture exits 0"
has "gh api --hostname github.com markdown --input " "$(calls)" "it asks GitHub's markdown API on github.com"
eq "$(jq -r '.text' "$GH_REQ" 2>/dev/null)" "$(cat "$MD")" "the request carries the file's text as it stands"
eq "$(jq -r '.mode + " " + .context' "$GH_REQ" 2>/dev/null)" "gfm octo/widgets" "it renders GitHub-flavoured, in the --repo context"
has "<summary>trail</summary>" "$(cat "$HANDED" 2>/dev/null)" "the driver gets the HTML GitHub returned"
has "[--title] [Rendered comment] [--expand]" "$(calls)" "the header and the expand option reach the driver"
G=$(line_of "gh api"); D=$(line_of "node [")
ok "the renderer answers before the driver runs (gh line $G, driver line $D)" "[ '$G' -gt 0 ] && [ '$D' -gt '$G' ]"
RIG="$TMPD/rig"; git init -q "$RIG" && git -C "$RIG" remote add origin git@github.com:zookanalytics/gc-toolkit.git
out="$(run GC_RIG_ROOT="$RIG" -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 0 "the rig's origin gives the context"
eq "$(jq -r '.context' "$GH_REQ" 2>/dev/null)" "zookanalytics/gc-toolkit" "references resolve in the rig's origin"
NOGIT="$TMPD/norepo"; mkdir -p "$NOGIT"
out="$(cd "$NOGIT" && env -i PATH="$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" HANDED="$HANDED" GH_REQ="$GH_REQ" SS_RIG="$ENGINE" bash "$SUT" markdown --file "$MD" --output "$OUT" 2>&1)"; rc=$?
eq "$rc" 0 "no origin still renders"
has "render without a repository context" "$out" "it says references render without a context"
eq "$(jq -r 'has("context")' "$GH_REQ" 2>/dev/null)" "false" "the request names no context"
out="$(run GH_RC=1 -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "a renderer failure exits 1"
has "GitHub's markdown renderer failed: HTTP 502" "$out" "it passes the renderer's error on"
hasnt "node [" "$(calls)" "the driver does not run without the rendering"
out="$(run GH_EMPTY=1 -- markdown --file "$MD" --output "$OUT")"; rc=$?
eq "$rc" 1 "an empty rendering exits 1"
has "returned nothing" "$out" "it says the renderer returned nothing"

# --- the driver's renderers, in a real node ---------------------------------
NODE_BIN=""
for c in "$(command -v node 2>/dev/null)" /opt/homebrew/bin/node /usr/local/bin/node; do
  [ -n "$c" ] && [ -x "$c" ] || continue
  v=$("$c" --version 2>/dev/null | sed 's/^v//'); m=${v%%.*}
  case "$m" in ''|*[!0-9]*) continue ;; esac
  [ "$m" -ge 18 ] && { NODE_BIN="$c"; break; }
done
if [ -z "$NODE_BIN" ]; then
  echo "# the driver's renderers: SKIPPED (no Node 18 or later on this host)"
else
  echo "# the driver's renderers ($NODE_BIN)"
  # js <expression>: what the expression evaluates to, with the driver imported as m.
  js() { "$NODE_BIN" --input-type=module -e "import * as m from '$DRIVER'; const v = await ($1); process.stdout.write(typeof v === 'string' ? v : JSON.stringify(v));" 2>&1; }

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
  r=$(js "m.terminalDocument({ text: 'a\nb\nc\n', maxLines: 1 })")
  has '[2 more line(s) not shown]' "$r" "a cut says how many lines it hid"
  r=$(js "m.terminalDocument({ text: 'x'.repeat(300) + '\n', columns: 100 })")
  has 'width: 100ch' "$r" "a wide output wraps at --columns"
  r=$(js "m.commentDocument({ fragment: '<details><summary>s</summary>x</details><detailsx>', title: 'a&b', expand: true })")
  has '<details open><summary>s</summary>' "$r" "--expand opens each <details>"
  has '</details><detailsx>' "$r" "an element merely named like details is left alone"
  has '<div class="comment-header">a&amp;b</div>' "$r" "the header is escaped"
  r=$(js "m.commentDocument({ fragment: '<details><summary>s</summary></details>' })")
  hasnt 'details open' "$r" "a <details> stays collapsed without --expand"
  hasnt '<div class="comment-header">' "$r" "no title draws no header"
  r=$(js "(() => { try { m.parseArgs(['page', '--output', 'o.png', '--script', 'd.md']); return 'parsed'; } catch (e) { return e.message; } })()")
  has 'exactly one of --base-url, --serve-dir, --serve (got 0)' "$r" "the driver refuses a page with no app target"
  r=$(js "(() => { try { m.parseArgs(['terminal', '--output', 'o.png', '--text', 't', '--html', 'h']); return 'parsed'; } catch (e) { return e.message; } })()")
  eq "$r" 'terminal takes no --html' "the driver refuses a flag of another kind"
  r=$(js "m.parseArgs(['markdown', '--output', 'o.png', '--html', 'h', '--expand'])")
  eq "$r" '{"kind":"markdown","output":"o.png","html":"h","expand":true}' "the driver parses a markdown call"
  mkdir -p "$TMPD/npx-cache/node_modules/.bin" "$TMPD/npx-cache/node_modules/@zookanalytics/sprintshow"
  printf '{"name":"@zookanalytics/sprintshow"}\n' >"$TMPD/npx-cache/node_modules/@zookanalytics/sprintshow/package.json"
  r=$(js "m.findEngine(undefined, '/usr/bin:$TMPD/npx-cache/node_modules/.bin:/bin')")
  eq "$r" "$TMPD/npx-cache/node_modules/@zookanalytics/sprintshow" "without --engine it finds the published engine npx put on PATH"
  r=$(js "String(m.findEngine(undefined, '/usr/bin:/bin'))")
  eq "$r" 'null' "with no engine on PATH it finds none"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all demo-screenshot assertions passed"; else echo "FAIL: demo-screenshot had failures"; fi
exit "$FAIL"
