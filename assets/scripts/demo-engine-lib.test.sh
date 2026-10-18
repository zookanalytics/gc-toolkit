#!/usr/bin/env bash
# demo-engine-lib.test.sh — the demo captures' one engine policy, checked
# through each capture that sources it.
#
# demo-engine-lib.sh holds Node to the SprintShow engine's floor, finds the
# engine, provisions the browser it launches, and runs its CLI, for
# rig-demo-capture.sh, the video, and demo-screenshot.sh, the screenshot. Each
# behavior below runs through both scripts, so a change to the policy is proven
# on every capture that runs it:
#   (FLOOR)     a Node below the engine's floor of 22.18, or no node at all,
#               stops the capture before anything is installed
#   (LOCAL)     a rig named sprintshow whose package.json names the engine is
#               the engine: its dependencies are installed when it has none, its
#               own provision:browser runs before the capture starts, and the
#               capture runs the checkout's CLI under node
#   (REJECT)    a rig named sprintshow that is not the engine is passed over,
#               and nothing runs in it
#   (PUBLISHED) with no local engine, or with a rig list that cannot be read,
#               the browser comes from the published package's own Playwright
#               and the capture runs on that package
#   (FAIL)      a dependency install or a browser install that fails, or no npx
#               for the published package, stops the capture: exit 1 with the
#               reason, and nothing is captured
#   (STDERR)    the installers' output goes to stderr, so a capture's stdout
#               carries only its own report
#   (READERS)   each capture sources the library, calls demo_engine_resolve,
#               runs the engine through demo_engine_cli, and runs none of the
#               library's steps itself. The demo:capture skill's examples do
#               the same, sourcing the library from the pack gc loaded, and its
#               resolve block and its engine call run against the stubs
#   (NO-COPY)   no other script in assets/scripts, and no pack skill's example
#               code, finds the engine, provisions its browser, checks Node's
#               version or names the CLI's entry
# What each capture adds to the policy is tested beside it, in
# rig-demo-capture.test.sh and demo-screenshot.test.sh.
#
# The behavior cases run under `env -i`, with a PATH of a coreutils symlink farm
# and stubs for node, npm, npx, gc and ffmpeg, so nothing reaches the network, a
# browser, or a city. Every stub logs its call to $CALLLOG.
#
# run-tests-scope: tree
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/demo-engine-lib.sh"
VIDEO="$HERE/rig-demo-capture.sh"
SHOT="$HERE/demo-screenshot.sh"
RENDERER="$HERE/demo-screenshot.mjs"
SKILLS="$(cd "$HERE/../../skills" && pwd)"
SKILL="$SKILLS/demo-capture/SKILL.md"
for f in "$LIB" "$VIDEO" "$SHOT" "$RENDERER" "$SKILL"; do
  [ -f "$f" ] || { echo "not found: $f" >&2; exit 2; }
done

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }
eq()    { if [ "$1" = "$2" ]; then printf 'ok   - %s\n' "$3"; else printf 'FAIL - %s\n     want: %s\n     got:  %s\n' "$3" "$2" "$1"; FAIL=1; fi; }

TMPD="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/demo-engine-lib-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$TMPD"' EXIT

# Only the tools the two captures call. env -i keeps everything else off PATH.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail dirname mkdir mktemp rm tee wc cat od awk; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done

# Stubs. node answers --version, hands a checkout's CLI to $ENGINE_STUB, and
# otherwise stands in for the screenshot's renderer, leaving a page at
# --output. npm and npx stand in for the installers: each prints what an
# installer prints, to the stdout it was given, and fails on NPM_INSTALL_RC or
# INSTALL_RC. npx hands the published engine's CLI to $ENGINE_STUB. gc lists
# the sprintshow rig at $SS_RIG beside another rig, or fails on GC_RC, and
# answers the pack command `gc gc-toolkit scripts-dir` with $PACK_SCRIPTS.
# ffmpeg is the host's, so the video fetches none.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
BIN="$TMPD/bin"; mkdir -p "$BIN"
ln -s "$JQ" "$BIN/jq"
cat >"$BIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "${NODE_VERSION:-v24.0.0}"; exit 0; fi
printf 'node' >>"${CALLLOG:?}"; printf ' [%s]' "$@" >>"$CALLLOG"; printf '\n' >>"$CALLLOG"
case "${1:-}" in */src/cli.ts) shift; exec "${ENGINE_STUB:?}" "$@" ;; esac
o=""; prev=""
for a in "$@"; do [ "$prev" = "--output" ] && o="$a"; prev="$a"; done
printf '<!doctype html><div id="surface">drawn</div>\n' >"$o"
exit 0
NODE
cat >"$BIN/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s (in %s)\n' "$*" "$PWD" >>"${CALLLOG:?}"
case "$*" in
  install)
    if [ "${NPM_INSTALL_RC:-0}" != 0 ]; then echo 'npm ERR! network request failed'; exit "$NPM_INSTALL_RC"; fi
    echo 'added 412 packages in 9s' ;;
  "run provision:browser")
    if [ "${INSTALL_RC:-0}" != 0 ]; then echo 'Failed to install browsers'; exit "$INSTALL_RC"; fi
    echo 'chromium-headless-shell is already installed' ;;
esac
exit 0
NPM
cat >"$BIN/npx" <<'NPX'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"${CALLLOG:?}"
if [ "${1:-} ${2:-}" = "--yes @zookanalytics/sprintshow" ]; then shift 2; exec "${ENGINE_STUB:?}" "$@"; fi
if [ "${1:-} ${2:-} ${3:-} ${4:-}" = "--yes --package=@zookanalytics/sprintshow -- playwright" ]; then
  if [ "${INSTALL_RC:-0}" != 0 ]; then echo 'Failed to install browsers'; exit "$INSTALL_RC"; fi
  echo 'chromium-headless-shell is already installed'; exit 0
fi
echo "npx stub: unexpected call: $*" >&2; exit 97
NPX
cat >"$BIN/gc" <<'GC'
#!/usr/bin/env bash
if [ "${1:-} ${2:-}" = "rig list" ]; then
  if [ "${GC_RC:-0}" != 0 ]; then echo 'gc: the city did not answer' >&2; exit "$GC_RC"; fi
  [ -z "${SS_RIG:-}" ] || printf '{"rigs":[{"name":"gc-toolkit","path":"/nowhere"},{"name":"sprintshow","path":"%s"}]}\n' "$SS_RIG"
fi
[ "${1:-} ${2:-}" != "gc-toolkit scripts-dir" ] || printf '%s\n' "${PACK_SCRIPTS:?}"
exit 0
GC
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/ffmpeg"
chmod +x "$BIN"/node "$BIN"/npm "$BIN"/npx "$BIN"/gc "$BIN"/ffmpeg
# The same stubs without npx, without node, and without ffmpeg.
NONPX="$TMPD/bin-nonpx"; mkdir -p "$NONPX"
for s in jq node npm gc ffmpeg; do ln -s "$BIN/$s" "$NONPX/$s"; done
NONODE="$TMPD/bin-nonode"; mkdir -p "$NONODE"
for s in jq npx npm gc ffmpeg; do ln -s "$BIN/$s" "$NONODE/$s"; done
NOFFMPEG="$TMPD/bin-noffmpeg"; mkdir -p "$NOFFMPEG"
for s in jq node npx npm gc; do ln -s "$BIN/$s" "$NOFFMPEG/$s"; done

# The engine's CLI: help lists its commands, lint passes, run writes the clip
# and the engine's closing report, and screenshot writes the PNG.
ENGINE_STUB="$TMPD/engine"
cat >"$ENGINE_STUB" <<'ENGINE'
#!/usr/bin/env bash
printf 'engine %s\n' "$*" >>"${CALLLOG:?}"
o=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; prev="$a"; done
case "${1:-}" in
  help) printf 'Usage:\n  sprintshow run <demo.md> [options]\n  sprintshow screenshot <demo.md> -o <file.png> [options]\n' ;;
  run)
    printf 'mp4-bytes\n' >"$o"
    printf '\n✅ silent demo → %s\n' "$o" ;;
  screenshot)
    # A PNG signature and an IHDR chunk naming a 1x1 image.
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00' >"$o"
    printf '\n✅ screenshot → %s\n' "$o" ;;
esac
exit 0
ENGINE
chmod +x "$ENGINE_STUB"

# The engine checkout, with its dependencies installed, and a rig named
# sprintshow that is not the engine.
ENGINE="$TMPD/sprintshow"; mkdir -p "$ENGINE/node_modules"
printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"
OTHER="$TMPD/other"; mkdir -p "$OTHER/node_modules"
printf '{"name":"sprintshow-notes"}\n' >"$OTHER/package.json"

# What the captures capture.
WORK="$TMPD/work"; mkdir -p "$WORK/app"
SCRIPT="$WORK/demo.md"; printf '# Demo: fixture\n\n**Start:** `/`\n' >"$SCRIPT"
printf '<!doctype html><title>x</title>\n' >"$WORK/app/index.html"
TXT="$WORK/output.txt"; printf 'line one\n' >"$TXT"
CALLLOG="$TMPD/calls.log"; OUTF="$TMPD/stdout"; ERRF="$TMPD/stderr"

# Each capture as this suite drives it: the file it writes, the call that
# starts its capture, and the call that shows the capture runs on a local
# checkout or on the published package.
output_of() { case "$1" in video) echo "$WORK/clip.mp4" ;; screenshot) echo "$WORK/shot.png" ;; esac; }
start_of() { case "$1" in video) echo "engine lint $SCRIPT" ;; screenshot) echo "engine screenshot " ;; esac; }
local_call() { case "$1" in video) echo "node [$ENGINE/src/cli.ts] [run] [$SCRIPT]" ;; screenshot) echo "node [$ENGINE/src/cli.ts] [screenshot]" ;; esac; }
published_call() { case "$1" in video) echo "npx --yes @zookanalytics/sprintshow run $SCRIPT" ;; screenshot) echo "npx --yes @zookanalytics/sprintshow screenshot " ;; esac; }

# capture <video|screenshot> [VAR=VAL ...]: run that capture against the stubs,
# from $WORK, with stdout in $OUTF, stderr in $ERRF and the exit status in $RC.
# $STUB_PATH replaces the stub directory for one call.
capture() {
  local cap="$1"; shift
  local -a argv
  case "$cap" in
    video)      argv=(bash "$VIDEO" --script "$SCRIPT" --output "$(output_of video)" --serve-dir "$WORK/app") ;;
    screenshot) argv=(bash "$SHOT" terminal --text "$TXT" --output "$(output_of screenshot)") ;;
  esac
  : >"$CALLLOG"; rm -f "$(output_of "$cap")"
  ( cd "$WORK" && env -i PATH="${STUB_PATH:-$BIN}:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
      ENGINE_STUB="$ENGINE_STUB" "$@" "${argv[@]}" >"$OUTF" 2>"$ERRF" )
  RC=$?
}
calls() { cat "$CALLLOG"; }
err() { cat "$ERRF"; }
# line_of <substring>: the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }
# not_captured <cap>: nothing started a capture, and no file was written.
not_captured() {
  ok "($1) nothing is captured" "[ '$(line_of "$(start_of "$1")")' = 0 ] && [ ! -e '$(output_of "$1")' ]"
}

for cap in video screenshot; do
  echo "# ($cap) FLOOR: Node below the engine's floor stops the capture before anything is installed"
  capture "$cap" SS_RIG="$ENGINE" NODE_VERSION=v22.17.1
  eq "$RC" 1 "($cap) Node 22.17 exits 1"
  has "Node 22.17.1 is below the engine's floor of 22.18" "$(err)" "($cap) it names the floor"
  eq "$(calls)" "" "($cap) nothing is installed, and nothing runs, for a Node below the floor"
  not_captured "$cap"
  capture "$cap" SS_RIG="$ENGINE" NODE_VERSION=v22.18.0
  eq "$RC" 0 "($cap) Node 22.18 captures"
  STUB_PATH="$NONODE" capture "$cap" SS_RIG="$ENGINE"
  eq "$RC" 1 "($cap) no node exits 1"
  has "node not found; the SprintShow engine needs Node >= 22.18" "$(err)" "($cap) it says node is missing"
  eq "$(calls)" "" "($cap) nothing is installed, and nothing runs, without node"
  not_captured "$cap"

  echo "# ($cap) LOCAL: the engine checkout, its browser provisioned before the capture starts"
  capture "$cap" SS_RIG="$ENGINE"
  eq "$RC" 0 "($cap) a capture on the local engine exits 0"
  has "engine = local sprintshow rig ($ENGINE)" "$(err)" "($cap) it says it chose the checkout"
  has "npm run provision:browser (in $ENGINE)" "$(calls)" "($cap) the checkout's own provision:browser runs, in the checkout"
  P=$(line_of "provision:browser"); S=$(line_of "$(start_of "$cap")")
  ok "($cap) the browser is provisioned before the capture starts (provision line $P, capture line $S)" "[ '$P' -gt 0 ] && [ '$S' -gt '$P' ]"
  hasnt "npm install" "$(calls)" "($cap) a checkout with its dependencies does not reinstall them"
  hasnt "playwright install" "$(calls)" "($cap) the published package's installer does not run"
  hasnt "npx " "$(calls)" "($cap) a checkout's CLI runs without npx"
  has "$(local_call "$cap")" "$(calls)" "($cap) the capture runs the checkout's CLI under node"
  ok "($cap) the captured file is on disk" "[ -s '$(output_of "$cap")' ]"

  echo "# ($cap) LOCAL: a checkout without its dependencies has them installed first; STDERR: the installers write nothing to stdout"
  rm -rf "$ENGINE/node_modules"
  capture "$cap" SS_RIG="$ENGINE"
  mkdir -p "$ENGINE/node_modules"
  eq "$RC" 0 "($cap) a checkout without node_modules captures"
  I=$(line_of "npm install (in $ENGINE)"); P=$(line_of "provision:browser")
  ok "($cap) the dependencies are installed in the checkout before the browser is provisioned (install line $I, provision line $P)" "[ '$I' -gt 0 ] && [ '$P' -gt '$I' ]"
  has "added 412 packages" "$(err)" "($cap) the dependency install's output reaches stderr"
  has "is already installed" "$(err)" "($cap) the browser install's output reaches stderr"
  hasnt "added 412 packages" "$(cat "$OUTF")" "($cap) the dependency install writes nothing to stdout"
  hasnt "is already installed" "$(cat "$OUTF")" "($cap) the browser install writes nothing to stdout"
  has "captured $(output_of "$cap")" "$(tail -n 1 "$OUTF")" "($cap) the last line on stdout is the capture's report"

  echo "# ($cap) FAIL: the dependency install fails"
  rm -rf "$ENGINE/node_modules"
  capture "$cap" SS_RIG="$ENGINE" NPM_INSTALL_RC=1
  mkdir -p "$ENGINE/node_modules"
  eq "$RC" 1 "($cap) a failed dependency install exits 1"
  has "'npm install' failed in the sprintshow rig checkout" "$(err)" "($cap) it says the install failed"
  has "npm ERR! network request failed" "$(err)" "($cap) the installer's own message reaches the caller"
  hasnt "provision:browser" "$(calls)" "($cap) no browser is provisioned after a failed install"
  not_captured "$cap"

  echo "# ($cap) FAIL: the checkout's browser install fails"
  capture "$cap" SS_RIG="$ENGINE" INSTALL_RC=1
  eq "$RC" 1 "($cap) a failed browser install exits 1"
  has "could not provision the browser ('npm run provision:browser' failed in the sprintshow rig checkout)" "$(err)" "($cap) it says the browser could not be provisioned"
  has "Failed to install browsers" "$(err)" "($cap) the installer's own message reaches the caller"
  not_captured "$cap"

  echo "# ($cap) REJECT: a rig named sprintshow that is not the engine is passed over"
  capture "$cap" SS_RIG="$OTHER"
  eq "$RC" 0 "($cap) the capture still runs"
  has "engine = published @zookanalytics/sprintshow" "$(err)" "($cap) it falls back to the published package"
  hasnt "(in $OTHER)" "$(calls)" "($cap) nothing runs in the other rig"
  hasnt "$OTHER/src/cli.ts" "$(calls)" "($cap) the other rig's CLI does not run"
  has "$(published_call "$cap")" "$(calls)" "($cap) the capture runs on the published package"

  echo "# ($cap) PUBLISHED: no local engine"
  capture "$cap"
  eq "$RC" 0 "($cap) a capture on the published package exits 0"
  has "engine = published @zookanalytics/sprintshow (no local rig checkout)" "$(err)" "($cap) it says it chose the published package"
  has "npx --yes --package=@zookanalytics/sprintshow -- playwright install chromium-headless-shell" "$(calls)" "($cap) the browser comes from the published package's Playwright"
  P=$(line_of "playwright install"); S=$(line_of "$(start_of "$cap")")
  ok "($cap) the browser is provisioned before the capture starts (provision line $P, capture line $S)" "[ '$P' -gt 0 ] && [ '$S' -gt '$P' ]"
  hasnt "npm " "$(calls)" "($cap) npm runs in no checkout"
  has "$(published_call "$cap")" "$(calls)" "($cap) the capture runs on the published package"
  ok "($cap) the captured file is on disk" "[ -s '$(output_of "$cap")' ]"
  hasnt "is already installed" "$(cat "$OUTF")" "($cap) the published package's installer writes nothing to stdout"
  has "captured $(output_of "$cap")" "$(tail -n 1 "$OUTF")" "($cap) the last line on stdout is the capture's report"

  echo "# ($cap) PUBLISHED: the rig list cannot be read"
  capture "$cap" SS_RIG="$ENGINE" GC_RC=1
  eq "$RC" 0 "($cap) the capture still runs"
  has "engine = published @zookanalytics/sprintshow" "$(err)" "($cap) an unread rig list names no checkout"
  hasnt "(in $ENGINE)" "$(calls)" "($cap) nothing runs in a checkout the list did not name"

  echo "# ($cap) FAIL: the published package's browser install fails"
  capture "$cap" INSTALL_RC=1
  eq "$RC" 1 "($cap) a failed published install exits 1"
  has "could not provision the browser (the published engine's 'playwright install chromium-headless-shell' failed)" "$(err)" "($cap) it says which install failed"
  has "Failed to install browsers" "$(err)" "($cap) the installer's own message reaches the caller"
  not_captured "$cap"

  echo "# ($cap) FAIL: no npx to run the published package"
  STUB_PATH="$NONPX" capture "$cap"
  eq "$RC" 1 "($cap) no npx exits 1"
  has "npx not found" "$(err)" "($cap) it says npx is missing"
  not_captured "$cap"
done

echo "# READERS: each capture sources the library, runs the engine through it, and runs none of its steps itself"
# Comment lines are left out, so a capture that names a step in prose but no
# longer runs it passes, and one that names the library but no longer sources
# it fails.
for f in "$VIDEO" "$SHOT"; do
  name="${f##*/}"
  code="$(grep -vE '^[[:space:]]*#' "$f")"
  if grep -qE '^[[:space:]]*\.[[:space:]].*demo-engine-lib\.sh' <<<"$code"; then
    printf 'ok   - %s\n' "($name) it sources demo-engine-lib.sh"
  else
    printf 'FAIL - %s\n' "($name) it sources demo-engine-lib.sh"; FAIL=1
  fi
  for fn in demo_engine_resolve demo_engine_cli; do
    if grep -qE "(^|[^[:alnum:]_])$fn([^[:alnum:]_]|\$)" <<<"$code"; then
      printf 'ok   - %s\n' "($name) it calls $fn"
    else
      printf 'FAIL - %s\n' "($name) it calls $fn"; FAIL=1
    fi
  done
  for step in 'rig list' 'package.json' 'npm install' 'provision:browser' 'playwright install' 'node --version' 'src/cli.ts' 'npx --yes' 'npx tsx'; do
    hasnt "$step" "$code" "($name) it runs no '$step' of its own"
  done
done

echo "# READERS: the demo:capture skill's examples resolve the engine through the library, from the pack gc loaded"
# A skill's examples are its fenced code blocks, read here without their
# comment lines, as the captures are.
code="$(awk '/^[[:space:]]*```/ { inb = !inb; next } inb' "$SKILL" | grep -vE '^[[:space:]]*#')"
has '. "$(gc <binding> scripts-dir)/demo-engine-lib.sh"' "$code" "(demo-capture skill) it sources demo-engine-lib.sh from the pack gc loaded"
for fn in demo_engine_resolve demo_engine_find demo_engine_cli; do
  if grep -qE "(^|[^[:alnum:]_])$fn([^[:alnum:]_]|\$)" <<<"$code"; then
    printf 'ok   - %s\n' "(demo-capture skill) it calls $fn"
  else
    printf 'FAIL - %s\n' "(demo-capture skill) it calls $fn"; FAIL=1
  fi
done
for step in 'rig list' 'package.json' 'npm install' 'provision:browser' 'playwright install' 'node --version' 'src/cli.ts' 'npx --yes' 'npx tsx'; do
  hasnt "$step" "$code" "(demo-capture skill) it runs no '$step' of its own"
done

# skill_block <n>: the n-th fenced block of the skill's "Resolve the engine"
# section, with the binding filled in as an agent fills it in for a city that
# imports the pack as gc-toolkit.
skill_block() {
  awk -v want="$1" '
    /^## / { s = ($0 == "## Resolve the engine") }
    s && /^[[:space:]]*```/ { if (inb) { inb = 0; if (n == want) exit; next } n++; inb = 1; next }
    s && inb && n == want' "$SKILL" | sed 's#<binding>#gc-toolkit#g'
}
skill_block 1 >"$TMPD/skill-resolve.sh"
skill_block 2 | sed 's#<command> <arguments\.\.\.>#lint demo.md#' >"$TMPD/skill-call.sh"
# skill_run <block> [VAR=VAL ...]: run a block as a script of its own, in a
# fresh shell, from $WORK, against the stubs, the way capture runs a capture.
skill_run() {
  local blk="$1"; shift
  : >"$CALLLOG"
  ( cd "$WORK" && env -i PATH="${STUB_PATH:-$BIN}:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
      ENGINE_STUB="$ENGINE_STUB" PACK_SCRIPTS="$HERE" "$@" bash "$blk" >"$OUTF" 2>"$ERRF" )
  RC=$?
}
skill_run "$TMPD/skill-resolve.sh" SS_RIG="$ENGINE"
eq "$RC" 0 "(demo-capture skill) its resolve block resolves the local engine"
has "engine = local sprintshow rig ($ENGINE)" "$(err)" "(demo-capture skill) through the library, which says which engine it chose"
has "npm run provision:browser (in $ENGINE)" "$(calls)" "(demo-capture skill) the library provisions the browser"
hasnt "provision:ffmpeg" "$(calls)" "(demo-capture skill) with a host ffmpeg, no ffmpeg is fetched"
STUB_PATH="$NOFFMPEG" skill_run "$TMPD/skill-resolve.sh" SS_RIG="$ENGINE"
eq "$RC" 0 "(demo-capture skill) its resolve block resolves the local engine with no host ffmpeg"
P=$(line_of "provision:browser"); F=$(line_of "npm run provision:ffmpeg (in $ENGINE)")
ok "(demo-capture skill) with no host ffmpeg, the checkout fetches ffmpeg-static once the engine resolves (browser line $P, ffmpeg line $F)" "[ '$P' -gt 0 ] && [ '$F' -gt '$P' ]"
STUB_PATH="$NOFFMPEG" skill_run "$TMPD/skill-resolve.sh" SS_RIG="$ENGINE" NODE_VERSION=v22.17.1
eq "$RC" 1 "(demo-capture skill) a Node below the floor stops its resolve block"
has "Node 22.17.1 is below the engine's floor of 22.18" "$(err)" "(demo-capture skill) with the library's reason"
eq "$(calls)" "" "(demo-capture skill) and nothing, ffmpeg included, is fetched after the engine did not resolve"
skill_run "$TMPD/skill-call.sh" SS_RIG="$ENGINE"
eq "$RC" 0 "(demo-capture skill) its engine call runs in a fresh shell"
eq "$(calls)" "node [$ENGINE/src/cli.ts] [lint] [demo.md]
engine lint demo.md" "(demo-capture skill) on the checkout's CLI, with nothing installed first"
skill_run "$TMPD/skill-call.sh"
eq "$(calls)" "npx --yes @zookanalytics/sprintshow lint demo.md
engine lint demo.md" "(demo-capture skill) and on the published package when there is no checkout"

echo "# NO-COPY: no other script, and no skill's example code, finds the engine, provisions its browser, checks Node's version or names the CLI's entry"
# One grep finds the files that name a step anywhere; only those are read again
# without their comment lines, so a script that names a step in prose passes.
# A skill is read again as its fenced code blocks alone, so its prose can name
# a step too. The steps are the browser install, by either installer, the rig
# lookup's select, however a copy spaces them, the Node version read, and the
# path of the engine's CLI in a checkout.
STEPS='provision:browser|playwright[[:space:]]+install|\.name[[:space:]]*==[[:space:]]*"sprintshow"|node[[:space:]]+--version|src/cli\.ts'
COPIES=""
while IFS= read -r f; do
  case "$f" in ""|"$LIB"|*.test.sh) continue ;; esac
  code="$(grep -vE '^[[:space:]]*(#|//)' "$f")"
  grep -qE "$STEPS" <<<"$code" && COPIES="$COPIES ${f##*/}"
done <<<"$(grep -lE "$STEPS" "$HERE"/*.sh "$HERE"/*.mjs 2>/dev/null)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  code="$(awk '/^[[:space:]]*```/ { inb = !inb; next } inb' "$f" | grep -vE '^[[:space:]]*#')"
  grep -qE "$STEPS" <<<"$code" && COPIES="$COPIES skills/${f#"$SKILLS"/}"
done <<<"$(grep -lE "$STEPS" "$SKILLS"/*/SKILL.md 2>/dev/null)"
eq "${COPIES# }" "" "(NO-COPY) no script in assets/scripts outside demo-engine-lib.sh, and no pack skill's example code, finds the engine, provisions its browser, checks Node's version or names the CLI's entry"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all demo-engine-lib assertions passed"; else echo "FAIL: demo-engine-lib had failures"; fi
exit "$FAIL"
