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
#               the engine: its dependencies are installed when it has none or
#               lacks one its package.json lists, its own provision:browser
#               runs before the capture starts, and the capture runs the
#               checkout's CLI under node
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
#   (SANDBOX)   the engine runs under sandbox-exec, with a profile that denies
#               the city's directories, the loopback ports but its own server's,
#               every Unix socket but the resolver's, and signals outside the
#               sandbox, and allows what the engine's arguments name; the
#               variables that point at the city do not reach it
#   (NO-SANDBOX) a host without sandbox-exec stops the capture before anything
#               is installed
#   (CITY)      a known city whose rig map does not read, a working directory
#               that holds the city's directory, and one inside it in no rig's
#               worktree each stop the capture; a rig worktree inside the city
#               is allowed, with its git directories
#   (PORTS)     a --serve-dir with no --port gets a free one; a port a server
#               already answers on, and a --base-url on this host, stop the
#               capture
#   (ISOLATION) on a host with sandbox-exec, a terminal capture whose command
#               reads the city's files, its stores, gc's home and a service on
#               its loopback, and lists the city's variables, reaches none of
#               them, though the same command run outside the sandbox does; and
#               a capture's own server answers it on each of a run of free
#               ports, which opens neither another loopback service nor a Unix
#               socket
#   (SHELLS)    under zsh and macOS's bash 3.2, the shells an agent can source
#               the library in, the skill's resolve block runs, and an engine
#               call hands the engine the arguments and the profile this suite's
#               bash does and drops the variables that point at the city
# What each capture adds to the policy is tested beside it, in
# rig-demo-capture.test.sh and demo-screenshot.test.sh.
#
# The behavior cases run under `env -i`, with a PATH of a coreutils symlink farm
# and stubs for node, npm, npx, gc, ffmpeg and sandbox-exec, so nothing reaches
# the network, a browser, or a city. Every stub but sandbox-exec logs its call
# to $CALLLOG. The sandbox-exec stub keeps the profile it was handed and the
# environment the engine runs in, then runs the engine. The ISOLATION case
# runs the host's own sandbox-exec instead.
#
# run-tests-scope: tree
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/demo-engine-lib.sh"
VIDEO="$HERE/rig-demo-capture.sh"
SHOT="$HERE/demo-screenshot.sh"
SKILLS="$(cd "$HERE/../../skills" && pwd)"
SKILL="$SKILLS/demo-capture/SKILL.md"
for f in "$LIB" "$VIDEO" "$SHOT" "$SKILL"; do
  [ -f "$f" ] || { echo "not found: $f" >&2; exit 2; }
done

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }
eq()    { if [ "$1" = "$2" ]; then printf 'ok   - %s\n' "$3"; else printf 'FAIL - %s\n     want: %s\n     got:  %s\n' "$3" "$2" "$1"; FAIL=1; fi; }

TMPD="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/demo-engine-lib-test.XXXXXX")" && pwd -P)"
API_PID=""; API_SOCK=""
trap '[ -z "$API_PID" ] || kill "$API_PID" 2>/dev/null; rm -rf "$TMPD" ${API_SOCK:+"$API_SOCK"}' EXIT

# Only the tools the two captures call. env -i keeps everything else off PATH.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail dirname mkdir mktemp rm tee wc cat od awk env readlink git; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done

# Stubs. node answers --version, hands a checkout's CLI to $ENGINE_STUB, answers
# the free-port pick with $FREE_PORT, and says a server answers on the port it
# is asked about when that port is $PORT_ANSWERS. npm and npx stand in for the
# installers: each prints what an
# installer prints, to the stdout it was given, and fails on NPM_INSTALL_RC or
# INSTALL_RC. npx hands the published engine's CLI to $ENGINE_STUB. gc lists
# the sprintshow rig at $SS_RIG beside another rig, or prints $RIGS_JSON, or
# fails on GC_RC, lists the cities in $GC_HOME's registry the way `gc cities
# --json` prints them, or fails on CITIES_RC, and answers the pack command
# `gc gc-toolkit scripts-dir` with $PACK_SCRIPTS. ffmpeg is the host's, so the
# video fetches none. sandbox-exec
# keeps the profile in $SANDBOX_PROFILE and the engine's environment in
# $SANDBOX_ENV, then runs the engine.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
BIN="$TMPD/bin"; mkdir -p "$BIN"
ln -s "$JQ" "$BIN/jq"
cat >"$BIN/node" <<'NODE'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "${NODE_VERSION:-v24.0.0}"; exit 0; fi
if [ "${1:-}" = "-e" ] && [ $# -ge 3 ]; then
  printf 'node port-check %s\n' "$3" >>"${CALLLOG:?}"; [ "$3" != "${PORT_ANSWERS:-}" ] || exit 3; exit 0
fi
if [ "${1:-}" = "-e" ]; then printf 'node port-pick\n' >>"${CALLLOG:?}"; printf '%s' "${FREE_PORT-50123}"; exit 0; fi
printf 'node' >>"${CALLLOG:?}"; printf ' [%s]' "$@" >>"$CALLLOG"; printf '\n' >>"$CALLLOG"
case "${1:-}" in */src/cli.ts) shift; exec "${ENGINE_STUB:?}" "$@" ;; esac
echo "node stub: unexpected call: $*" >&2; exit 97
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
if [ "${1:-} ${2:-}" = "cities --json" ]; then
  if [ "${CITIES_RC:-0}" != 0 ]; then echo 'gc cities: parsing registry: toml: expected a value' >&2; exit "$CITIES_RC"; fi
  sed -n 's/^ *path = "\(.*\)"$/\1/p' "${GC_HOME:?}/cities.toml" \
    | jq -Rnc --arg r "$GC_HOME/cities.toml" '{cities: [inputs | {name: "fixture", path: .}], ok: true, registry_path: $r, schema_version: "1"}'
  exit 0
fi
if [ "${1:-} ${2:-}" = "rig list" ]; then
  if [ "${GC_RC:-0}" != 0 ]; then echo 'gc: the city did not answer' >&2; exit "$GC_RC"; fi
  if [ -n "${RIGS_JSON:-}" ]; then printf '%s\n' "$RIGS_JSON"; exit 0; fi
  [ -z "${SS_RIG:-}" ] || printf '{"rigs":[{"name":"gc-toolkit","path":"/nowhere"},{"name":"sprintshow","path":"%s"}]}\n' "$SS_RIG"
fi
[ "${1:-} ${2:-}" != "gc-toolkit scripts-dir" ] || printf '%s\n' "${PACK_SCRIPTS:?}"
exit 0
GC
printf '#!/usr/bin/env bash\nexit 0\n' >"$BIN/ffmpeg"
cat >"$BIN/sandbox-exec" <<'SBX'
#!/usr/bin/env bash
[ "${1:-}" = "-p" ] && [ $# -ge 3 ] || { echo "sandbox-exec stub: expected -p <profile> <command...>" >&2; exit 64; }
printf '%s\n' "$2" >"${SANDBOX_PROFILE:-/dev/null}"
env >"${SANDBOX_ENV:-/dev/null}"
shift 2
exec "$@"
SBX
chmod +x "$BIN"/node "$BIN"/npm "$BIN"/npx "$BIN"/gc "$BIN"/ffmpeg "$BIN"/sandbox-exec
# The same stubs without npx, without node, without ffmpeg, and without
# sandbox-exec.
NONPX="$TMPD/bin-nonpx"; mkdir -p "$NONPX"
for s in jq node npm gc ffmpeg sandbox-exec; do ln -s "$BIN/$s" "$NONPX/$s"; done
NONODE="$TMPD/bin-nonode"; mkdir -p "$NONODE"
for s in jq npx npm gc ffmpeg sandbox-exec; do ln -s "$BIN/$s" "$NONODE/$s"; done
NOFFMPEG="$TMPD/bin-noffmpeg"; mkdir -p "$NOFFMPEG"
for s in jq node npx npm gc sandbox-exec; do ln -s "$BIN/$s" "$NOFFMPEG/$s"; done
NOSBX="$TMPD/bin-nosandbox"; mkdir -p "$NOSBX"
for s in jq node npx npm gc ffmpeg; do ln -s "$BIN/$s" "$NOSBX/$s"; done
NOGC="$TMPD/bin-nogc"; mkdir -p "$NOGC"
for s in jq node npx npm ffmpeg sandbox-exec; do ln -s "$BIN/$s" "$NOGC/$s"; done

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
CALLLOG="$TMPD/calls.log"; OUTF="$TMPD/stdout"; ERRF="$TMPD/stderr"
SANDBOX_PROFILE="$TMPD/sandbox.profile"; SANDBOX_ENV="$TMPD/sandbox.env"

# Each capture as this suite drives it: the file it writes, the call that
# starts its capture, and the call that shows the capture runs on a local
# checkout or on the published package.
output_of() { case "$1" in video) echo "$WORK/clip.mp4" ;; screenshot) echo "$WORK/shot.png" ;; esac; }
start_of() { case "$1" in video) echo "engine lint $SCRIPT" ;; screenshot) echo "engine screenshot " ;; esac; }
local_call() { case "$1" in video) echo "node [$ENGINE/src/cli.ts] [run] [$SCRIPT]" ;; screenshot) echo "node [$ENGINE/src/cli.ts] [screenshot]" ;; esac; }
published_call() { case "$1" in video) echo "npx --yes @zookanalytics/sprintshow run $SCRIPT" ;; screenshot) echo "npx --yes @zookanalytics/sprintshow screenshot " ;; esac; }

# capture <video|screenshot> [VAR=VAL ...] [FROM=<dir>] [-- <app target...>]:
# run that capture against the stubs, from $WORK or the FROM directory, serving
# $WORK/app unless an app target follows --, with stdout in $OUTF, stderr in
# $ERRF and the exit status in $RC. $STUB_PATH replaces the stub directory for
# one call.
capture() {
  local cap="$1" from="$WORK"; shift
  local -a argv envs target=(--serve-dir "$WORK/app")
  while [ $# -gt 0 ]; do
    case "$1" in
      --) shift; target=("$@"); break ;;
      FROM=*) from="${1#FROM=}" ;;
      *) envs+=("$1") ;;
    esac
    shift
  done
  case "$cap" in
    video)      argv=(bash "$VIDEO" --script "$SCRIPT" --output "$(output_of video)" "${target[@]}") ;;
    screenshot) argv=(bash "$SHOT" page --script "$SCRIPT" "${target[@]}" --output "$(output_of screenshot)") ;;
  esac
  : >"$CALLLOG"; rm -f "$(output_of "$cap")" "$SANDBOX_PROFILE" "$SANDBOX_ENV"
  ( cd "$from" && env -i PATH="${STUB_PATH:-$BIN}:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
      ENGINE_STUB="$ENGINE_STUB" SANDBOX_PROFILE="$SANDBOX_PROFILE" SANDBOX_ENV="$SANDBOX_ENV" \
      ${envs[@]+"${envs[@]}"} "${argv[@]}" >"$OUTF" 2>"$ERRF" )
  RC=$?
}
profile() { cat "$SANDBOX_PROFILE" 2>/dev/null; }
# profile_line <text>: the first line of the last profile holding it, or 0;
# profile_last <text>: the last such line.
profile_line() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$SANDBOX_PROFILE" 2>/dev/null || echo 0; }
profile_last() { awk -v s="$1" 'index($0, s) { n = NR } END { print n + 0 }' "$SANDBOX_PROFILE" 2>/dev/null || echo 0; }
calls() { cat "$CALLLOG"; }
err() { cat "$ERRF"; }
# line_of <substring>: the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }
# not_captured <cap>: nothing started a capture, and no file was written.
not_captured() {
  ok "($1) nothing is captured" "[ '$(line_of "$(start_of "$1")")' = 0 ] && [ ! -e '$(output_of "$1")' ]"
}
# not_run <cap>: the engine's capture command never ran, and no file was
# written. A video's lint names no app target, so it may run first.
not_run() {
  local call; case "$1" in video) call="engine run " ;; screenshot) call="engine screenshot " ;; esac
  ok "($1) the capture never runs" "[ '$(line_of "$call")' = 0 ] && [ ! -e '$(output_of "$1")' ]"
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

  echo "# ($cap) LOCAL: a checkout whose node_modules lacks a package its package.json depends on has its dependencies installed first"
  printf '{"name":"@zookanalytics/sprintshow","dependencies":{"@example/pty":"^1.1.0","playwright":"^1.63.0"}}\n' >"$ENGINE/package.json"
  mkdir -p "$ENGINE/node_modules/playwright"; printf '{"name":"playwright"}\n' >"$ENGINE/node_modules/playwright/package.json"
  capture "$cap" SS_RIG="$ENGINE"
  eq "$RC" 0 "($cap) a checkout missing a dependency captures"
  I=$(line_of "npm install (in $ENGINE)"); P=$(line_of "provision:browser")
  ok "($cap) the dependencies are installed in the checkout before the browser is provisioned (install line $I, provision line $P)" "[ '$I' -gt 0 ] && [ '$P' -gt '$I' ]"
  mkdir -p "$ENGINE/node_modules/@example/pty"; printf '{"name":"@example/pty"}\n' >"$ENGINE/node_modules/@example/pty/package.json"
  capture "$cap" SS_RIG="$ENGINE"
  eq "$RC" 0 "($cap) a checkout with every dependency installed captures"
  hasnt "npm install" "$(calls)" "($cap) and does not reinstall them"
  printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"
  rm -rf "$ENGINE/node_modules"; mkdir -p "$ENGINE/node_modules"

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

# A city for the sandbox's cases. gc's home lists it, and the environment names
# it, one of its rigs and that rig's store. Its rig map lists that rig, a rig
# whose checkout lies outside the city's directory, and the engine. Each place
# holds a secret no capture may reach. The rig is a git repository with a
# worktree inside the city's directory, as a polecat's is.
CITY="$TMPD/city"; RIGA="$CITY/rigs/alpha"; OUTRIG="$TMPD/outside-rig"; GCH="$TMPD/gchome"
mkdir -p "$CITY/.beads" "$CITY/.gc/notes" "$RIGA/.beads" "$OUTRIG/.beads" "$GCH"
printf 'SECRET-CITY-CONFIG\n' >"$CITY/city.toml"
printf 'SECRET-CITY-STORE\n' >"$CITY/.beads/issues.jsonl"
printf 'SECRET-RIG-STORE\n' >"$RIGA/.beads/issues.jsonl"
printf 'SECRET-OUTSIDE-RIG-STORE\n' >"$OUTRIG/.beads/issues.jsonl"
printf '# SECRET-GC-HOME\n[[cities]]\n  path = "%s"\n  name = "fixture"\n' "$CITY" >"$GCH/cities.toml"
USERHOME="$TMPD/user-home"; USERCITY="$TMPD/user-city"; mkdir -p "$USERHOME/.gc" "$USERCITY"
printf '[[cities]]\n  path = "%s"\n  name = "fixture"\n' "$USERCITY" >"$USERHOME/.gc/cities.toml"
RIGS_JSON=$(jq -nc --arg a "$RIGA" --arg o "$OUTRIG" --arg e "$ENGINE" \
  '{rigs: [{name: "alpha", path: $a}, {name: "outside", path: $o}, {name: "sprintshow", path: $e}]}')
CITY_ENV=(GC_HOME="$GCH" GC_CITY_PATH="$CITY" GC_RIG_ROOT="$RIGA" GT_ROOT="$CITY" BEADS_DIR="$RIGA/.beads"
  BD_ROUTING_MODE=direct DOLT_PORT=3307 TMUX=/tmp/tmux-0/default RIGS_JSON="$RIGS_JSON")
git -C "$RIGA" init -q && git -C "$RIGA" -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -q --allow-empty -m init \
  || { echo "test setup: cannot make the rig's git repository" >&2; exit 2; }
RWT="$CITY/.gc/worktrees/alpha/wt"; mkdir -p "$(dirname "$RWT")"
git -C "$RIGA" worktree add -q --detach "$RWT" HEAD >/dev/null 2>&1 || { echo "test setup: cannot add the rig's worktree" >&2; exit 2; }

for cap in video screenshot; do
  echo "# ($cap) SANDBOX: the engine runs under sandbox-exec, in a profile that keeps the city out of reach"
  capture "$cap" SS_RIG="$ENGINE" "${CITY_ENV[@]}"
  eq "$RC" 0 "($cap) a capture in a city exits 0"
  has "$(local_call "$cap")" "$(calls)" "($cap) the engine still runs on the checkout's CLI"
  for place in "$GCH" "$CITY" "$RIGA" "$OUTRIG" "$ENGINE"; do
    has "(deny file-read-data file-write* (subpath \"$place\"))" "$(profile)" "($cap) the profile denies the city's directory ${place#"$TMPD"/}"
  done
  has "(allow file-read-data file-write* (subpath \"$WORK\"))" "$(profile)" "($cap) it allows the working directory and the output's, which the engine's arguments name"
  has "/sprintshow/[^.]\"))" "$(profile)" "($cap) it allows the engine checkout's files but not its dot-directories"
  has "(deny file-read-data file-write* (subpath \"$RIGA/.beads\"))" "$(profile)" "($cap) and denies every store again after what it allows"
  C=$(profile_line "(subpath \"$CITY\"))"); A=$(profile_line "(allow file-read-data file-write* (subpath \"$WORK\"))"); D=$(profile_last "(subpath \"$RIGA/.beads\"))")
  ok "($cap) the city is denied, then the run's own directories allowed, then the stores denied (lines $C, $A, $D)" "[ '$C' -gt 0 ] && [ '$A' -gt '$C' ] && [ '$D' -gt '$A' ]"
  has "(deny network-outbound (remote ip \"localhost:*\"))" "$(profile)" "($cap) it denies every loopback port"
  has "(allow network-outbound (remote ip \"localhost:50123\"))" "$(profile)" "($cap) but the free one its own server is given"
  has "--port 50123" "$(calls)" "($cap) and the engine serves on that port"
  has "(deny network-outbound (remote unix-socket))" "$(profile)" "($cap) it denies Unix sockets"
  has "(allow network-outbound (remote unix-socket (path-literal \"/private/var/run/mDNSResponder\")))" "$(profile)" "($cap) but the system resolver's"
  U=$(profile_line "(deny network-outbound (remote unix-socket))"); L=$(profile_line "(allow network-outbound (remote ip \"localhost:50123\"))")
  ok "($cap) the Unix socket rules come before the loopback port's allow, which a later deny on Unix sockets takes back (lines $U, $L)" "[ '$U' -gt 0 ] && [ '$L' -gt '$U' ]"
  has "(deny signal)" "$(profile)" "($cap) it denies signals"
  has "(allow signal (target same-sandbox))" "$(profile)" "($cap) but to its own processes"
  for v in GC_HOME GC_CITY_PATH GC_RIG_ROOT GT_ROOT BEADS_DIR BD_ROUTING_MODE DOLT_PORT TMUX; do
    hasnt "$v=" "$(cat "$SANDBOX_ENV")" "($cap) $v does not reach the engine"
  done
  has "CALLLOG=" "$(cat "$SANDBOX_ENV")" "($cap) the rest of the environment does"

  echo "# ($cap) NO-SANDBOX: a host without sandbox-exec stops the capture before anything is installed"
  STUB_PATH="$NOSBX" capture "$cap" SS_RIG="$ENGINE"
  eq "$RC" 1 "($cap) no sandbox-exec exits 1"
  has "sandbox-exec not found, so this host has no sandbox to keep a capture away from the live city" "$(err)" "($cap) it says there is no sandbox"
  eq "$(calls)" "" "($cap) nothing is installed, and nothing runs, without a sandbox"
  not_captured "$cap"

  echo "# ($cap) CITY: a known city whose rig map does not read stops the capture"
  capture "$cap" SS_RIG="$ENGINE" GC_RC=1 GC_CITY_PATH="$CITY"
  eq "$RC" 1 "($cap) an unread rig map in a known city exits 1"
  has "the city's rig map did not read" "$(err)" "($cap) it says the rig checkouts are unknown"
  not_captured "$cap"
  capture "$cap" SS_RIG="$ENGINE" GC_RC=1
  eq "$RC" 0 "($cap) with no city known, an unread rig map leaves nothing unknown"

  echo "# ($cap) REGISTRY: gc's own read of its registry names the cities to deny, in the home the environment names and the user's own"
  capture "$cap" SS_RIG="$ENGINE" GC_HOME="$GCH"
  eq "$RC" 0 "($cap) a city only the registry names captures"
  has "(deny file-read-data file-write* (subpath \"$CITY\"))" "$(profile)" "($cap) and that city is denied"
  capture "$cap" SS_RIG="$ENGINE" GC_HOME="$GCH" HOME="$USERHOME"
  eq "$RC" 0 "($cap) with a registry in each home, it captures"
  has "(deny file-read-data file-write* (subpath \"$CITY\"))" "$(profile)" "($cap) the city GC_HOME's registry lists is denied"
  has "(deny file-read-data file-write* (subpath \"$USERCITY\"))" "$(profile)" "($cap) and so is the one the user's own registry lists"
  capture "$cap" SS_RIG="$ENGINE" GC_RC=1 GC_HOME="$GCH"
  eq "$RC" 1 "($cap) a city only the registry names is known, so an unread rig map exits 1"
  has "the city's rig map did not read" "$(err)" "($cap) it says the rig checkouts are unknown"
  not_captured "$cap"
  capture "$cap" SS_RIG="$ENGINE" GC_HOME="$GCH" CITIES_RC=1
  eq "$RC" 1 "($cap) a registry gc does not read exits 1"
  has "gc did not read the city registry in $GCH" "$(err)" "($cap) it names the home"
  has "gc cities: parsing registry" "$(err)" "($cap) and passes on gc's reason"
  not_captured "$cap"
  STUB_PATH="$NOGC" capture "$cap" SS_RIG="$ENGINE" GC_HOME="$GCH"
  eq "$RC" 1 "($cap) a registry with no gc to read it exits 1"
  has "gc did not read the city registry in $GCH" "$(err)" "($cap) it says so"
  not_captured "$cap"
  capture "$cap" SS_RIG="$ENGINE" CITIES_RC=1
  eq "$RC" 0 "($cap) a home with no registry asks gc for nothing"

  echo "# ($cap) CITY: a working directory that holds the city's, or lies in it outside any rig worktree, stops the capture"
  capture "$cap" FROM="$TMPD" SS_RIG="$ENGINE" "${CITY_ENV[@]}"
  eq "$RC" 1 "($cap) a working directory that holds the city's exits 1"
  has "$TMPD holds " "$(err)" "($cap) it names the directory and what it holds"
  not_captured "$cap"
  capture "$cap" FROM="$CITY/.gc/notes" SS_RIG="$ENGINE" "${CITY_ENV[@]}"
  eq "$RC" 1 "($cap) a working directory in the city's, in no rig worktree, exits 1"
  has "$CITY/.gc/notes lies in $CITY" "$(err)" "($cap) it says the directory lies in the city's"
  not_captured "$cap"
  capture "$cap" FROM="$RIGA" SS_RIG="$ENGINE" "${CITY_ENV[@]}"
  eq "$RC" 1 "($cap) a rig's own checkout, which holds its store, exits 1"
  has "$RIGA holds " "$(err)" "($cap) it names the checkout"
  has "capture from a rig worktree" "$(err)" "($cap) and says where a capture can run instead"
  not_captured "$cap"
  capture "$cap" FROM="$RWT" SS_RIG="$ENGINE" "${CITY_ENV[@]}"
  eq "$RC" 0 "($cap) a rig worktree in the city's directory captures"
  has "(allow file-read-data file-write* (subpath \"$RWT\"))" "$(profile)" "($cap) the worktree is allowed"
  has "(allow file-read-data file-write* (subpath \"$RIGA/.git/worktrees/wt\"))" "$(profile)" "($cap) with its own git directory"
  has "(allow file-read-data (subpath \"$RIGA/.git\"))" "$(profile)" "($cap) and its repository's, to read"
  hasnt "(allow file-read-data file-write* (subpath \"$RIGA\"))" "$(profile)" "($cap) and the rig's checkout stays denied"

  echo "# ($cap) PORTS: a port a server answers on, and a --base-url on this host, stop the capture"
  capture "$cap" SS_RIG="$ENGINE" PORT_ANSWERS=5175 -- --serve 'npm run dev' --port 5175 --cwd "$WORK/app"
  eq "$RC" 1 "($cap) a --serve port a server already answers on exits 1"
  has "a server already answers on port 5175" "$(err)" "($cap) it names the port"
  not_run "$cap"
  capture "$cap" SS_RIG="$ENGINE" PORT_ANSWERS=5173 -- --serve 'npm run dev' --cwd "$WORK/app"
  eq "$RC" 1 "($cap) a --serve with no --port is checked on the engine's own 5173"
  capture "$cap" SS_RIG="$ENGINE" -- --serve 'npm run dev' --port 5175 --cwd "$WORK/app"
  eq "$RC" 0 "($cap) a --serve port nothing answers on captures"
  has "(allow network-outbound (remote ip \"localhost:5175\"))" "$(profile)" "($cap) and the sandbox opens it"
  for url in http://localhost:3000 http://127.0.0.1:8372/v0 'http://[::1]:5173/'; do
    capture "$cap" SS_RIG="$ENGINE" -- --base-url "$url"
    eq "$RC" 1 "($cap) --base-url $url exits 1"
    has "names a server on this host" "$(err)" "($cap) it says the server runs outside the sandbox"
    not_run "$cap"
  done
  capture "$cap" SS_RIG="$ENGINE" -- --base-url https://preview.example.com
  eq "$RC" 0 "($cap) a deployed preview captures"
  hasnt "(allow network-outbound (remote ip" "$(profile)" "($cap) and opens no loopback port"
done

echo "# ISOLATION: a terminal capture whose command reads the city reaches none of it, through the host's own sandbox"
if [ ! -x /usr/bin/sandbox-exec ] || ! /usr/bin/sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
  echo "# ISOLATION: SKIPPED (no working sandbox-exec on this host; NO-SANDBOX shows that a capture there never runs)"
else
  # The engine for this case: help lists the terminal surface, and a terminal
  # script's one step runs its command in bash, in --cwd, and keeps what it
  # prints in $CMD_OUT, then logs the step as the engine does.
  EXEC_STUB="$TMPD/engine-exec"
  cat >"$EXEC_STUB" <<'ENGINE'
#!/usr/bin/env bash
case "${1:-}" in
  help) printf 'Usage:\n  sprintshow screenshot <demo.md> -o <file.png> [options]\n\nterminal scripts:\n  A script that declares **Terminal:** drives a bash session.\n'; exit 0 ;;
  screenshot) ;;
  *) exit 97 ;;
esac
o=""; cwd=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; [ "$prev" = "--cwd" ] && cwd="$a"; prev="$a"; done
cmd=$(sed -n 's/^   `run \(.*\)`$/\1/p' "$2")
( cd "$cwd" && bash -c "$cmd" ) >"${CMD_OUT:?}" 2>&1
printf 'step 1/1: The command runs\n  · `%s` exited %s\n' "$cmd" "$?"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00' >"$o"
printf '\n✅ screenshot → %s\n' "$o"
ENGINE
  chmod +x "$EXEC_STUB"
  REALSBX="$TMPD/bin-realsandbox"; mkdir -p "$REALSBX"; ln -s /usr/bin/sandbox-exec "$REALSBX/sandbox-exec"
  # A service on the loopback interface stands in for the supervisor's API and
  # the Dolt server, and one on a Unix socket for the session server, when the
  # host has a node to run them. A Unix socket's path has a short limit, so it
  # sits directly under /tmp.
  APIPORT=""; REAL_NODE="$(command -v node || true)"
  if [ -n "$REAL_NODE" ]; then
    API_SOCK="$(mktemp -u /tmp/demo-engine-lib-test.XXXXXX)"
    "$REAL_NODE" -e 'const net = require("net"); net.createServer((c) => c.end("SECRET-SOCKET\n")).listen(process.argv[2]); const s = net.createServer((c) => c.end("SECRET-API\n")); s.listen(0, "127.0.0.1", () => require("fs").writeFileSync(process.argv[1], String(s.address().port)));' "$TMPD/api.port" "$API_SOCK" &
    API_PID=$!
    for _ in $(seq 1 100); do [ -s "$TMPD/api.port" ] && break; sleep 0.1; done
    APIPORT="$(cat "$TMPD/api.port" 2>/dev/null)"
  fi
  [ -n "$APIPORT" ] || echo "# ISOLATION: the loopback service is SKIPPED (no node on this host to run one)"
  printf 'FIXTURE-OK\n' >"$WORK/fixture.txt"
  # The command reads each place the city keeps state in, lists its rigs, asks
  # the loopback service, prints every variable that points at the city, and
  # reads the fixture beside it.
  PROBE="cat '$CITY/city.toml' '$CITY/.beads/issues.jsonl' '$RIGA/.beads/issues.jsonl' '$OUTRIG/.beads/issues.jsonl' '$GCH/cities.toml'; echo rigs: '$CITY'/rigs/*; ${APIPORT:+(exec 3<>/dev/tcp/127.0.0.1/$APIPORT && cat <&3);} env | awk '/^(GC|GT|BEADS|BD|DOLT)_/ || /^TMUX=/ { print \"CITY-VARIABLE \" \$0 }'; cat fixture.txt"
  CMD_OUT="$TMPD/command.out"; : >"$CMD_OUT"
  out=$( cd "$WORK" && env -i PATH="$REALSBX:$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
      ENGINE_STUB="$EXEC_STUB" CMD_OUT="$CMD_OUT" SS_RIG="$ENGINE" "${CITY_ENV[@]}" \
      bash "$SHOT" terminal --command "$PROBE" --cwd "$WORK" --output "$WORK/probe.png" 2>&1 ); rc=$?
  inside="$(cat "$CMD_OUT")"
  eq "$rc" 0 "(ISOLATION) the capture runs, in the host's sandbox"
  has "captured $WORK/probe.png (terminal, " "$out" "(ISOLATION) and leaves its PNG"
  has "FIXTURE-OK" "$inside" "(ISOLATION) the command reads the fixture in its working directory"
  has "Operation not permitted" "$inside" "(ISOLATION) the city's files are refused to it"
  for secret in SECRET-CITY-CONFIG SECRET-CITY-STORE SECRET-RIG-STORE SECRET-OUTSIDE-RIG-STORE SECRET-GC-HOME "rigs: $CITY/rigs/alpha" CITY-VARIABLE ${APIPORT:+SECRET-API}; do
    hasnt "$secret" "$inside" "(ISOLATION) the command does not reach ${secret//"$TMPD"\//}"
  done
  # The same command, run outside the sandbox with the same environment, reaches
  # every one, so the case above tells a sandboxed run from one that is not.
  outside=$( cd "$WORK" && env -i PATH="$BIN:$FARM" HOME="$TMPD" "${CITY_ENV[@]}" bash -c "$PROBE" 2>&1 )
  for secret in SECRET-CITY-CONFIG SECRET-CITY-STORE SECRET-RIG-STORE SECRET-OUTSIDE-RIG-STORE SECRET-GC-HOME "rigs: $CITY/rigs/alpha" "CITY-VARIABLE GC_CITY_PATH=" ${APIPORT:+SECRET-API}; do
    has "$secret" "$outside" "(ISOLATION) outside the sandbox the same command reaches ${secret//"$TMPD"\//}"
  done

  # A capture's own server answers it, and opening its port opens nothing else.
  # This runs on several free ports, because a profile with its network rules in
  # the wrong order answers on some ports and refuses others.
  if [ -n "$APIPORT" ]; then
    SERVE_STUB="$TMPD/engine-serve"
    cat >"$SERVE_STUB" <<'ENGINE'
#!/usr/bin/env bash
case "${1:-}" in
  help) printf 'Usage:\n  sprintshow screenshot <demo.md> -o <file.png> [options]\n'; exit 0 ;;
  screenshot) ;;
  *) exit 97 ;;
esac
o=""; port=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; [ "$prev" = "--port" ] && port="$a"; prev="$a"; done
"${REAL_NODE:?}" "${KNOCK:?}" "$port" "${APIPORT:?}" "${API_SOCK:?}" >"${CMD_OUT:?}" 2>&1
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00' >"$o"
printf '\n✅ screenshot → %s\n' "$o"
ENGINE
    chmod +x "$SERVE_STUB"
    KNOCK="$TMPD/knock.js"
    cat >"$KNOCK" <<'JS'
const net = require("net");
const [port, other, sock] = process.argv.slice(2);
const knock = (to) => new Promise((done) => {
  const s = net.connect(to);
  s.setTimeout(3000, () => { s.destroy(); done("timeout"); });
  s.once("connect", () => { s.destroy(); done("reached"); });
  s.once("error", (e) => done(e.code));
});
net.createServer((c) => c.end()).listen(Number(port), async () => {
  console.log("own-v4", await knock({ host: "127.0.0.1", port: Number(port) }));
  console.log("own-v6", await knock({ host: "::1", port: Number(port) }));
  console.log("other", await knock({ host: "127.0.0.1", port: Number(other) }));
  console.log("socket", await knock({ path: sock }));
  process.exit(0);
});
JS
    for _ in 1 2 3 4 5 6 7 8; do
      port=$("$REAL_NODE" -e 'const s = require("net").createServer(); s.listen(0, "127.0.0.1", () => { process.stdout.write(String(s.address().port)); s.close(); });')
      : >"$CMD_OUT"
      out=$( cd "$WORK" && env -i PATH="$REALSBX:$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
          ENGINE_STUB="$SERVE_STUB" REAL_NODE="$REAL_NODE" KNOCK="$KNOCK" APIPORT="$APIPORT" API_SOCK="$API_SOCK" \
          CMD_OUT="$CMD_OUT" FREE_PORT="$port" SS_RIG="$ENGINE" "${CITY_ENV[@]}" \
          bash "$SHOT" page --script "$SCRIPT" --serve-dir "$WORK/app" --output "$WORK/own.png" 2>&1 ); rc=$?
      inside="$(cat "$CMD_OUT")"
      eq "$rc" 0 "(ISOLATION) a capture given port $port runs"
      has "own-v4 reached" "$inside" "(ISOLATION) its own server answers on port $port"
      hasnt "own-v6 EPERM" "$inside" "(ISOLATION) and is not refused over IPv6"
      hasnt "other reached" "$inside" "(ISOLATION) and no other loopback service answers"
      hasnt "socket reached" "$inside" "(ISOLATION) and no Unix socket does"
    done
    outside=$("$REAL_NODE" "$KNOCK" "$port" "$APIPORT" "$API_SOCK" 2>&1)
    has "other reached" "$outside" "(ISOLATION) outside the sandbox the loopback service answers"
    has "socket reached" "$outside" "(ISOLATION) and so does the Unix socket"
  fi
fi

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

echo "# SHELLS: the library runs in the agent's own shell, which can be zsh or macOS's bash 3.2, and does there what it does under this suite's bash"
# A block run as skill_run runs one, through the shell named, in the city's
# environment. The engine call names a server and a port, so what the shell does
# with the arguments reaches the engine and the profile.
skill_block 2 | sed 's#<command> <arguments\.\.\.>#run demo.md --serve-dir app --port 5199 -o clip.mp4#' >"$TMPD/skill-serve.sh"
shell_run() {
  local sh="$1" blk="$2"
  : >"$CALLLOG"; rm -f "$SANDBOX_PROFILE" "$SANDBOX_ENV"
  ( cd "$WORK" && env -i PATH="$BIN:$FARM" HOME="$TMPD" TMPDIR="$TMPD" CALLLOG="$CALLLOG" \
      ENGINE_STUB="$ENGINE_STUB" PACK_SCRIPTS="$HERE" SANDBOX_PROFILE="$SANDBOX_PROFILE" SANDBOX_ENV="$SANDBOX_ENV" \
      "${CITY_ENV[@]}" "$sh" "$blk" >"$OUTF" 2>"$ERRF" )
  RC=$?
}
shell_run bash "$TMPD/skill-serve.sh"
eq "$RC" 0 "(shells) this suite's bash runs the engine call"
has "node [$ENGINE/src/cli.ts] [run] [demo.md] [--serve-dir] [app] [--port] [5199] [-o] [clip.mp4]" "$(calls)" "(shells) and the engine gets its arguments"
has '(allow network-outbound (remote ip "localhost:5199"))' "$(profile)" "(shells) and the profile opens the port they name"
SERVE_CALLS="$(calls)"; SERVE_PROFILE="$(profile)"
for sh in /bin/zsh /bin/bash; do
  if [ ! -x "$sh" ]; then echo "# SHELLS: $sh SKIPPED (not on this host)"; continue; fi
  shell_run "$sh" "$TMPD/skill-resolve.sh"
  eq "$RC" 0 "(shells) $sh runs the resolve block"
  has "engine = local sprintshow rig ($ENGINE)" "$(err)" "(shells) $sh chooses the local engine"
  shell_run "$sh" "$TMPD/skill-serve.sh"
  eq "$RC" 0 "(shells) $sh runs the engine call"
  eq "$(calls)" "$SERVE_CALLS" "(shells) $sh hands the engine the same arguments"
  eq "$(profile)" "$SERVE_PROFILE" "(shells) $sh builds the same profile"
  eq "$(grep -cE '^((GC|GT|BEADS|BD|DOLT)_|TMUX)' "$SANDBOX_ENV")" 0 "(shells) $sh drops the variables that point at the city"
done

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
