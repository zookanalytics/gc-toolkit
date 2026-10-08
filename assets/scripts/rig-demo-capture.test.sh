#!/usr/bin/env bash
# rig-demo-capture.test.sh — hermetic coverage of the rig-demo capture core.
# The script resolves a capture engine, lints a script, drives the capture, and
# checks the produced file. The test drives the engine through the script's own
# $SPRINTSHOW_BIN override seam with a stub, and runs under `env -i` with a PATH
# of only a coreutils symlink farm — no host node, npx, gc, or sprintshow — so
# nothing touches the network or the real engine, and each case plants exactly
# the lint result, run result, and output-file outcome it means to exercise.
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
# which is why every happy case must set $SPRINTSHOW_BIN.
FARM="$TMPD/farm"; mkdir -p "$FARM"
for c in bash sed tr head dirname mkdir wc cat; do
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
STUB="$TMPD/sprintshow-stub"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "lint" ]; then exit "${LINT_RC:-0}"; fi
if [ "${1:-}" = "run" ]; then
  printf '%s\n' "$*" >>"${RUNLOG:?}"
  o=""; prev=""
  for a in "$@"; do [ "$prev" = "-o" ] && o="$a"; prev="$a"; done
  [ "${RUN_RC:-0}" != 0 ] && exit "${RUN_RC}"
  [ -n "${RUN_NOFILE:-}" ] && exit 0
  if [ -n "${RUN_EMPTY:-}" ]; then : >"$o"; else printf 'mp4-bytes\n' >"$o"; fi
  exit 0
fi
exit 0
STUB
chmod +x "$STUB"

RUNLOG="$TMPD/run.log"
# run [KEY=VAL ...] -- <sut args...>; per-call knobs, combined stdout+stderr.
run() {
  local lint_rc=0 run_rc=0 nofile="" empty=""
  while [ $# -gt 0 ]; do
    case "$1" in
      LINT_RC=*)   lint_rc="${1#*=}" ;;
      RUN_RC=*)    run_rc="${1#*=}" ;;
      RUN_NOFILE=*) nofile="${1#*=}" ;;
      RUN_EMPTY=*) empty="${1#*=}" ;;
      --) shift; break ;;
      *) break ;;
    esac
    shift
  done
  : >"$RUNLOG"; rm -f "$OUT"
  ( cd "$TMPD" && env -i PATH="$FARM" RUNLOG="$RUNLOG" SPRINTSHOW_BIN="$STUB" \
      LINT_RC="$lint_rc" RUN_RC="$run_rc" RUN_NOFILE="$nofile" RUN_EMPTY="$empty" \
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

echo "# engine-resolution contract: the marked block prefers the local rig, guards the package name, and falls back to npm"
BLOCK="$(sed -n '/# >>> rig-demo-engine-resolve/,/# <<< rig-demo-engine-resolve/p' "$SUT")"
has 'select(.name=="sprintshow")' "$BLOCK" "it resolves the local sprintshow rig by name"
has '@zookanalytics/sprintshow' "$BLOCK" "it guards on the engine package name"
has 'npx tsx' "$BLOCK" "it runs the local engine via npx tsx (no build step)"
has 'npx --yes @zookanalytics/sprintshow' "$BLOCK" "it falls back to the published package"

echo
if [ "$FAIL" -eq 0 ]; then echo "PASS: all rig-demo-capture assertions passed"; else echo "FAIL: rig-demo-capture had failures"; fi
exit "$FAIL"
