#!/usr/bin/env bash
# rig-demo-capture.test.sh — hermetic coverage of the rig-demo capture core.
# The script resolves a capture engine, provisions its browser, lints a script,
# drives the capture, and checks the produced file. Most cases drive the engine
# through the script's own $SPRINTSHOW_BIN override seam with a stub. The
# resolution cases instead put stub node, npx, npm and gc on PATH, so engine
# resolution and browser provisioning run as written. Every case runs under
# `env -i` with a PATH of only a coreutils symlink farm and those stubs — no host
# node, npx, gc, or sprintshow — so nothing touches the network or the real
# engine, and each case plants exactly the install result, lint result, run
# result, and output-file outcome it means to exercise.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/rig-demo-capture.sh"
[ -x "$SUT" ] || { echo "not found or not executable: $SUT" >&2; exit 2; }

FAIL=0
ok()    { if eval "$2"; then printf 'ok   - %s\n' "$1"; else printf 'FAIL - %s\n' "$1"; FAIL=1; fi; }
has()   { case "$2" in *"$1"*) printf 'ok   - %s\n' "$3" ;; *) printf 'FAIL - %s\n     wanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'FAIL - %s\n     unwanted substring: %s\n     in: %s\n' "$3" "$1" "$2"; FAIL=1 ;; *) printf 'ok   - %s\n' "$3" ;; esac; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/rig-demo-capture.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

# Only the coreutils the script actually calls; env -i keeps everything else off
# PATH, so a path that should resolve the real engine instead finds nothing —
# which is why every happy case either sets $SPRINTSHOW_BIN or puts the
# resolution stubs on PATH.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head tail dirname mkdir mktemp rm tee wc cat; do
  p="$(command -v "$c")" || { echo "test setup: required tool '$c' not found" >&2; exit 2; }
  ln -s "$p" "$FARM/$c"
done

# Fixtures: a script file, a serve dir, and an output path under TMPD.
SCRIPT="$TMPD/demo.md"; printf '# Demo: fixture\n\n**Start:** `/`\n' >"$SCRIPT"
SERVE_DIR="$TMPD/app"; mkdir -p "$SERVE_DIR"; printf '<!doctype html><title>x</title>\n' >"$SERVE_DIR/index.html"
OUT="$TMPD/out.mp4"

# Stub engine, driven through $SPRINTSHOW_BIN. `lint` exits $LINT_RC. `run` logs
# its argv to $RUNLOG, finds the -o path, and (unless told otherwise) writes
# bytes there; $RUN_RC fails the run, $RUN_NOFILE leaves no file, $RUN_EMPTY
# leaves an empty one — the three ways a capture can "succeed" yet deliver nothing.
# $RUN_REPORT prints the engine's closing report for a clip of that kind
# (narrated, silent), in the engine's words. $RUN_FAILED writes the clip, prints
# that report with its failed-proof line for that many steps, and exits 1, as
# the engine does when a step of a captured clip fails its proof. $RUN_LATE_RC
# writes the clip and then exits with that code without any report.
STUB="$TMPD/sprintshow-stub"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "lint" ]; then exit "${LINT_RC:-0}"; fi
if [ "${1:-}" = "run" ]; then
  printf '%s\n' "$*" >>"${RUNLOG:?}"
  o=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; prev="$a"; done
  [ "${RUN_RC:-0}" != 0 ] && exit "${RUN_RC}"
  if [ -n "${RUN_FAILED:-}" ]; then
    [ -n "${RUN_NOFILE:-}" ] || printf 'mp4-bytes\n' >"$o"
    printf 'step 1/2: Open the board\n  ✓ proof held\nstep 2/2: Expand the row\n  ✗ _Prove:_ did not hold: `visible .row`\n\n'
    printf '✅ %s demo → %s\n' "${RUN_REPORT:-narrated}" "$o"
    printf '   ⚠️  %s step(s) failed their proof — video and frames kept: .captures/fixture-123\n' "$RUN_FAILED"
    exit 1
  fi
  [ -n "${RUN_NOFILE:-}" ] && exit 0
  if [ -n "${RUN_EMPTY:-}" ]; then : >"$o"; else printf 'mp4-bytes\n' >"$o"; fi
  [ "${RUN_LATE_RC:-0}" != 0 ] && exit "${RUN_LATE_RC}"
  [ -n "${RUN_REPORT:-}" ] && printf '\n✅ %s demo → %s\n' "$RUN_REPORT" "$o"
  exit 0
fi
exit 0
STUB
chmod +x "$STUB"

RUNLOG="$TMPD/run.log"
# run [KEY=VAL ...] -- <sut args...>; per-call knobs, combined stdout+stderr.
run() {
  local lint_rc=0 run_rc=0 nofile="" empty="" report="" failed="" late_rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      LINT_RC=*)   lint_rc="${1#*=}" ;;
      RUN_RC=*)    run_rc="${1#*=}" ;;
      RUN_NOFILE=*) nofile="${1#*=}" ;;
      RUN_EMPTY=*) empty="${1#*=}" ;;
      RUN_REPORT=*) report="${1#*=}" ;;
      RUN_FAILED=*) failed="${1#*=}" ;;
      RUN_LATE_RC=*) late_rc="${1#*=}" ;;
      --) shift; break ;;
      *) break ;;
    esac
    shift
  done
  : >"$RUNLOG"; rm -f "$OUT"
  ( cd "$TMPD" && env -i PATH="$FARM" RUNLOG="$RUNLOG" SPRINTSHOW_BIN="$STUB" \
      LINT_RC="$lint_rc" RUN_RC="$run_rc" RUN_NOFILE="$nofile" RUN_EMPTY="$empty" \
      RUN_REPORT="$report" RUN_FAILED="$failed" RUN_LATE_RC="$late_rc" \
      bash "$SUT" "$@" 2>&1 )
}

echo "# happy path: lint + capture + a non-empty file -> exit 0"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture exits 0" "[ '$rc' = 0 ]"
ok "output file exists and is non-empty" "[ -s '$OUT' ]"
RL="$(cat "$RUNLOG")"
has "run $SCRIPT" "$RL" "it runs the given script"
has "--mode walkthrough" "$RL" "walkthrough is the default mode"
has "-o $OUT" "$RL" "the output path is forwarded"
has "--serve-dir $SERVE_DIR" "$RL" "the serve-dir target is forwarded"
has "captured $OUT" "$out" "it reports the captured file"

echo "# --mode proof is forwarded"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --mode proof)"; rc=$?
ok "proof mode exits 0" "[ '$rc' = 0 ]"
has "--mode proof" "$(cat "$RUNLOG")" "proof mode is forwarded"

echo "# --base-url and --serve are each forwarded; --no-narrate too"
out="$(run -- --script "$SCRIPT" --output "$OUT" --base-url http://localhost:3000)"; rc=$?
ok "base-url exits 0" "[ '$rc' = 0 ]"
has "--base-url http://localhost:3000" "$(cat "$RUNLOG")" "base-url is forwarded"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve 'npm run dev' --port 4321 --no-narrate --cwd "$SERVE_DIR")"; rc=$?
ok "serve exits 0" "[ '$rc' = 0 ]"
RL="$(cat "$RUNLOG")"
has "--serve npm run dev" "$RL" "serve command is forwarded"
has "--port 4321" "$RL" "port is forwarded"
has "--no-narrate" "$RL" "no-narrate is forwarded"

echo "# fail closed: lint rejects the script -> exit 1, no capture"
out="$(run LINT_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "lint failure exits 1" "[ '$rc' = 1 ]"
has "failed lint" "$out" "it says the script failed lint"
hasnt "run $SCRIPT" "$(cat "$RUNLOG")" "no capture runs after a lint failure"

echo "# fail closed: the engine errors -> exit 1"
out="$(run RUN_RC=3 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture error exits 1" "[ '$rc' = 1 ]"
has "capture failed" "$out" "it reports the capture failure"

echo "# fail closed: the engine succeeds but produces NO file -> exit 1"
out="$(run RUN_NOFILE=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing output exits 1" "[ '$rc' = 1 ]"
has "does not exist" "$out" "it catches the silent non-delivery"

echo "# fail closed: the engine produces an EMPTY file -> exit 1"
out="$(run RUN_EMPTY=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "empty output exits 1" "[ '$rc' = 1 ]"
has "is empty" "$out" "it catches an empty clip"

echo "# the last line says whether the clip is narrated or silent, from the engine's report"
out="$(run RUN_REPORT=narrated -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a narrated capture exits 0" "[ '$rc' = 0 ]"
has "captured $OUT (narrated," "$out" "it reports a narrated clip"
out="$(run RUN_REPORT=silent -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a silent capture exits 0" "[ '$rc' = 0 ]"
has "captured $OUT (silent," "$out" "it reports a silent clip"
out="$(run 'RUN_REPORT=narrated + music bed' -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
has "captured $OUT (narrated," "$out" "a music bed does not hide the narration"

echo "# a clip in which a step failed its proof -> exit 3, naming the clip and the engine's kept working files"
# env -i drops PWD, so the script's pwd is the physical path, which differs from
# the logical one where TMPDIR runs through a symlink (macOS /var).
TMPD_PWD="$(cd "$TMPD" && pwd -P)"
out="$(run RUN_FAILED=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a failed step proof exits 3" "[ '$rc' = 3 ]"
ok "the clip stays on disk" "[ -s '$OUT' ]"
has "1 step(s) failed their proof" "$out" "it counts the failed steps"
has "captured $OUT (narrated)" "$out" "it names the clip and its narration"
has "kept its working files in $TMPD_PWD/.captures/fixture-123" "$out" "it names the kept working files by absolute path"
hasnt "capture failed" "$out" "a clip with a failed step is not reported as a failed capture"

echo "# fail closed: a failed-proof report with no clip on disk -> exit 1"
out="$(run RUN_FAILED=2 RUN_NOFILE=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "a failed-proof report without a clip exits 1" "[ '$rc' = 1 ]"
has "capture failed" "$out" "it reports the capture failure"

echo "# fail closed: the engine writes the file, then errors with no report -> exit 1"
out="$(run RUN_LATE_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "an error after the file was written exits 1" "[ '$rc' = 1 ]"
has "capture failed (sprintshow run exited 1)" "$out" "a file without the engine's report is not a captured clip"

echo "# usage errors (exit 2)"
out="$(run -- --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing --script exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing --output exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT")"; rc=$?
ok "no app target exits 2" "[ '$rc' = 2 ]"
has "exactly one of --serve-dir" "$out" "it names the app-target requirement"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --base-url http://x)"; rc=$?
ok "two app targets exits 2" "[ '$rc' = 2 ]"
out="$(run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR" --mode fast)"; rc=$?
ok "bad --mode exits 2" "[ '$rc' = 2 ]"

echo "# a --script that does not exist -> exit 1"
out="$(run -- --script "$TMPD/nope.md" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "missing script file exits 1" "[ '$rc' = 1 ]"
has "does not exist" "$out" "it says the script is missing"

# Engine resolution, driven without $SPRINTSHOW_BIN. Stubs on PATH stand in for
# node, npx, npm, gc and a host ffmpeg; jq is the real one, because the script
# reads the rig list and the engine's package.json with it. npm and npx log
# every call to $CALLLOG in order, stand in for Playwright's installer, and hand
# lint and run to the engine stub. $INSTALL_RC fails the install the way
# Playwright's CLI does: a message on stdout and exit 1.
JQ="$(command -v jq)" || { echo "test setup: required tool 'jq' not found" >&2; exit 2; }
RBIN="$TMPD/resolve-bin"; mkdir -p "$RBIN"
ln -s "$JQ" "$RBIN/jq"
printf '#!/usr/bin/env bash\necho v24.0.0\n' >"$RBIN/node"
printf '#!/usr/bin/env bash\nexit 0\n' >"$RBIN/ffmpeg"
cat >"$RBIN/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1 $2" = "rig list" ] && [ -n "${SS_RIG:-}" ]; then printf '{"rigs":[{"name":"sprintshow","path":"%s"}]}\n' "$SS_RIG"; fi
exit 0
GC
cat >"$RBIN/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s (in %s)\n' "$*" "$PWD" >>"${CALLLOG:?}"
if [ "$*" = "run provision:browser" ] && [ "${INSTALL_RC:-0}" != 0 ]; then
  printf 'Failed to install browsers\nError: download failed\n'; exit "$INSTALL_RC"
fi
exit 0
NPM
cat >"$RBIN/npx" <<'NPX'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >>"${CALLLOG:?}"
case "$1 $2" in
  "tsx "*) shift 2; exec "${ENGINE_STUB:?}" "$@" ;;
  "--yes @zookanalytics/sprintshow") shift 2; exec "${ENGINE_STUB:?}" "$@" ;;
  "--yes --package=@zookanalytics/sprintshow")
    if [ "${INSTALL_RC:-0}" != 0 ]; then printf 'Failed to install browsers\nError: download failed\n'; exit "$INSTALL_RC"; fi
    exit 0 ;;
esac
echo "npx stub: unexpected call: $*" >&2; exit 97
NPX
chmod +x "$RBIN"/node "$RBIN"/ffmpeg "$RBIN"/gc "$RBIN"/npm "$RBIN"/npx
# A local engine checkout with its deps installed. Its path is the one cd
# reports, since npm's log line records the directory it ran in as $PWD.
ENGINE="$(cd "$TMPD" && pwd)/sprintshow"; mkdir -p "$ENGINE/node_modules"
printf '{"name":"@zookanalytics/sprintshow"}\n' >"$ENGINE/package.json"
CALLLOG="$TMPD/calls.log"
# resolve_run [VAR=VAL ...] -- <sut args...>; the stubs above, never $SPRINTSHOW_BIN.
resolve_run() {
  local envs=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  : >"$RUNLOG"; : >"$CALLLOG"; rm -f "$OUT"
  ( cd "$TMPD" && env -i PATH="$RBIN:$FARM" RUNLOG="$RUNLOG" CALLLOG="$CALLLOG" ENGINE_STUB="$STUB" \
      ${envs[@]+"${envs[@]}"} bash "$SUT" "$@" 2>&1 )
}
# line_of <substring> — the first $CALLLOG line holding it, or 0 when none does.
line_of() { awk -v s="$1" 'index($0, s) { print NR; found = 1; exit } END { if (!found) print 0 }' "$CALLLOG"; }

echo "# local engine, browser already installed: the provisioning step runs, the installer downloads nothing, the capture proceeds"
out="$(resolve_run SS_RIG="$ENGINE" -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture exits 0" "[ '$rc' = 0 ]"
ok "output file exists and is non-empty" "[ -s '$OUT' ]"
has "engine = local sprintshow rig ($ENGINE)" "$out" "it resolves the local engine"
has "npm run provision:browser (in $ENGINE)" "$(cat "$CALLLOG")" "it runs the engine's own provision:browser in the engine checkout"
P=$(line_of "provision:browser"); L=$(line_of "lint $SCRIPT")
ok "the browser is provisioned before the engine first runs (provision line $P, lint line $L)" "[ '$P' -gt 0 ] && [ '$L' -gt '$P' ]"
has "run $SCRIPT" "$(cat "$RUNLOG")" "the capture runs after the provisioning step"

echo "# local engine, the install fails -> exit 1 with its message, no capture"
out="$(resolve_run SS_RIG="$ENGINE" INSTALL_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "failed install exits 1" "[ '$rc' = 1 ]"
has "could not provision the browser ('npm run provision:browser' failed in the sprintshow rig checkout)" "$out" "it says the browser could not be provisioned"
has "Failed to install browsers" "$out" "the installer's own message reaches the caller"
hasnt "lint $SCRIPT" "$(cat "$CALLLOG")" "nothing is linted after a failed install"
ok "nothing is captured after a failed install" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"

echo "# published engine: the browser comes from that engine's own Playwright, then the capture proceeds"
out="$(resolve_run -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "capture exits 0" "[ '$rc' = 0 ]"
has "engine = published @zookanalytics/sprintshow" "$out" "with no local rig it resolves the published engine"
has "npx --yes --package=@zookanalytics/sprintshow -- playwright install chromium-headless-shell" "$(cat "$CALLLOG")" "it installs the browser with the published engine's playwright"
P=$(line_of "playwright install"); L=$(line_of "lint $SCRIPT")
ok "the browser is provisioned before the engine first runs (provision line $P, lint line $L)" "[ '$P' -gt 0 ] && [ '$L' -gt '$P' ]"
hasnt "npm " "$(cat "$CALLLOG")" "it does not run npm in a checkout it does not have"
has "run $SCRIPT" "$(cat "$RUNLOG")" "the capture runs after the provisioning step"

echo "# published engine, the install fails -> exit 1 with its message, no capture"
out="$(resolve_run INSTALL_RC=1 -- --script "$SCRIPT" --output "$OUT" --serve-dir "$SERVE_DIR")"; rc=$?
ok "failed install exits 1" "[ '$rc' = 1 ]"
has "could not provision the browser (the published engine's 'playwright install chromium-headless-shell' failed)" "$out" "it says the browser could not be provisioned"
has "Failed to install browsers" "$out" "the installer's own message reaches the caller"
ok "nothing is captured after a failed install" "[ ! -s '$RUNLOG' ] && [ ! -e '$OUT' ]"

echo "# engine-resolution contract: the marked block prefers the local rig, guards the package name, and falls back to npm"
BLOCK="$(sed -n '/# >>> rig-demo-engine-resolve/,/# <<< rig-demo-engine-resolve/p' "$SUT")"
has 'select(.name=="sprintshow")' "$BLOCK" "it resolves the local sprintshow rig by name"
has '@zookanalytics/sprintshow' "$BLOCK" "it guards on the engine package name"
has 'npx tsx' "$BLOCK" "it runs the local engine via npx tsx (no build step)"
has 'npx --yes @zookanalytics/sprintshow' "$BLOCK" "it falls back to the published package"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all rig-demo-capture assertions passed"; else echo "FAIL: rig-demo-capture had failures"; fi
exit "$FAIL"
