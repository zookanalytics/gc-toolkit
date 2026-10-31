#!/usr/bin/env bash
# Hermetic test for mol-rig-demo's capture block, the rig-demo-capture-run
# region of the capture step.
#
# rig-demo-capture.sh exits 1 when no clip appears and 3 when the clip records a
# step failing its proof. On either, the block appends a note naming which one,
# files a human gate on the request bead through human-gate.sh, cancels the run
# through run-cancel.sh only if the gate landed, and drains only if the cancel
# landed. On success it records the clip path on the request bead.
#
# A step's blocks can run under a strict shell, where a failing command whose
# status nothing catches ends the block on the spot. For this block that abort
# skips the gate and the cancel, which leaves the run claimed with no gate
# behind it. So every case runs twice, once under `set -euo pipefail` and
# once under a plain shell, and both runs must reach the same end.
#
# EXECUTES the real block extracted verbatim between the formula markers, with
# the pour vars rendered at their defaults, against a stub capture, a fake `gc`,
# and stub human-gate and cancel scripts. No live city, browser, or network.
#
# A capture's sandbox refuses a rig's own checkout, so the app runs from a
# detached worktree of it, which the step's rig-demo-app-root region makes. The
# last cases run that region and the capture block with the real capture, sandbox
# library and workspace scripts, against a fixture city, a stub engine and a
# stub sandbox-exec that keeps the profile it was handed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-rig-demo.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-demo-capture-arm-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract the REAL block from the formula. --------------------------------
# A removed or renamed marker extracts nothing, and the checks below fail loudly.
MARKER=rig-demo-capture-run
awk -v m="$MARKER" '
  $0 ~ ("# >>> " m "$") {f=1; next}
  $0 ~ ("# <<< " m "$") {f=0}
  f' "$TOML" \
  | sed -e 's/{{rig_name}}/demo-rig/g' -e 's/{{capture_mode}}/walkthrough/g' \
        -e 's/{{serve_port}}/5173/g' -e 's/{{narrate}}/true/g' \
        -e 's/{{binding_prefix}}/gc-toolkit./g' > "$TMP/block.sh"

echo "# the region extracts as runnable bash"
if [ ! -s "$TMP/block.sh" ]; then
  bad "extraction EMPTY: the $MARKER markers are missing"
  echo "PASS=$PASS FAIL=$FAIL"
  exit 1
fi
ok "extracted between the markers"
eq "$(grep -c "^# >>> $MARKER\$" "$TOML")" "1" "exactly one region"
case "$(cat "$TMP/block.sh")" in
  *\\*) bad "contains a backslash, which TOML line-ending escapes will mangle" ;;
  *)    ok  "backslash-free (safe inside a TOML triple-quoted string)" ;;
esac
case "$(cat "$TMP/block.sh")" in
  *'{{'*) bad "a pour var the test does not render" "$(grep -o '{{[a-z_]*}}' "$TMP/block.sh" | sort -u | tr '\n' ' ')" ;;
  *)      ok  "every pour var in the region is rendered" ;;
esac
bash -n "$TMP/block.sh" && ok "syntactically valid bash" || bad "failed bash -n"
{ printf 'set -euo pipefail\n'; cat "$TMP/block.sh"; } > "$TMP/strict.sh"
cp "$TMP/block.sh" "$TMP/plain.sh"

# --- Fakes. --------------------------------------------------------------------
# gc: the block reaches `bd update` (the failure note, or the clip path on
# success) and `runtime drain-ack`. The capture, human-gate and cancel stubs sit in
# a stub pack, $STUB_PACK, which gc names for `gc gc-toolkit scripts-dir`.
# Each fake records its verb into one ordered log and its argv into its own file.
mkdir -p "$TMP/bin" "$TMP/pack/assets/scripts" "$TMP/cwd"
SHEBANG="#!${BASH:-/usr/bin/env bash}"
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "bd update")         printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "$FAKE_DIR/gc.argv" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG" ;;
esac
exit 0
GC
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/rig-demo-capture.sh" <<'CAP'
printf 'CAPTURE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/capture.argv"
exit "$FAKE_CAPTURE_RC"
CAP
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/human-gate.sh" <<'GATE'
printf 'GATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/gate.argv"
exit "${FAKE_GATE_RC:-0}"
GATE
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/run-cancel.sh" <<'CANCEL'
printf 'CANCEL\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/cancel.argv"
exit "${FAKE_CANCEL_RC:-0}"
CANCEL
chmod +x "$TMP/bin/gc" "$TMP/pack/assets/scripts/"*.sh
export PATH="$TMP/bin:$PATH"
export STUB_PACK="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH="" GIT_CEILING_DIRECTORIES="$TMP"

# The variables the capture step sets before this block: the request bead, the
# resolved script, the clip path, the app target, and the scripts dir.
OUT="$TMP/rig-demo/tk-req/demo-rig-walkthrough.mp4"

# run <strict|plain> <capture exit> prints "<rc>|<ordered verb log>"
#   FAKE_GATE_RC and FAKE_CANCEL_RC set the human-gate and cancel stubs' exits.
run() {
  : > "$TMP/log"; : > "$TMP/gc.argv"; : > "$TMP/capture.argv"; : > "$TMP/gate.argv"; : > "$TMP/cancel.argv"
  local rc=0
  ( cd "$TMP/cwd" &&
    REQUEST_BEAD=tk-req SCRIPT_PATH="$TMP/cwd/walkthrough.md" OUT="$OUT" \
    SERVE_DIR="$TMP/cwd/site" SERVE_CMD="" BASE_URL="" APP_ROOT="$TMP/cwd" \
    SCRIPTS="$TMP/pack/assets/scripts" CLAIMED_STEP_BEAD_ID=st-capture \
    FAKE_LOG="$TMP/log" FAKE_DIR="$TMP" FAKE_CAPTURE_RC="$2" \
    FAKE_GATE_RC="${FAKE_GATE_RC:-0}" FAKE_CANCEL_RC="${FAKE_CANCEL_RC:-0}" \
      bash "$TMP/$1.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

for MODE in strict plain; do
  echo "# $MODE shell: a clean capture records the clip on the request bead"
  eq "$(run "$MODE" 0)" "0|CAPTURE;UPDATE;" "$MODE: exit 0 records the clip, with no gate or cancel"
  has "$(cat "$TMP/capture.argv")" "--output $OUT" "$MODE: the capture writes the clip the block records"
  has "$(cat "$TMP/gc.argv")" "bd update tk-req --set-metadata demo_mp4_path=$OUT" "$MODE: the clip path lands on the request bead"

  echo "# $MODE shell: no clip files a gate, cancels, and drains"
  eq "$(run "$MODE" 1)" "1|CAPTURE;UPDATE;GATE;CANCEL;DRAIN;" "$MODE: exit 1 files a gate, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/gate.argv")" "--subject tk-req --key rig-demo-capture-failed" "$MODE: the gate blocks the request bead under the capture key"
  has "$(cat "$TMP/gate.argv")" "produced no MP4" "$MODE: exit 1 is reported as no clip"
  case "$(cat "$TMP/gate.argv")" in
    *--quiet-window*) bad "$MODE: the gate declares a quiet window; a failed capture is an event of this run" ;;
    *) ok "$MODE: the gate declares no quiet window" ;;
  esac
  has "$(cat "$TMP/cancel.argv")" "--step mol-rig-demo.capture --bead st-capture" "$MODE: the cancel names the capture step and the claimed bead"

  echo "# $MODE shell: a clip with a failed proof files a gate, cancels, and drains"
  eq "$(run "$MODE" 3)" "1|CAPTURE;UPDATE;GATE;CANCEL;DRAIN;" "$MODE: exit 3 files a gate, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/gate.argv")" "the clip at $OUT recorded at least one step failing its proof" "$MODE: the gate names the failed-proof clip"
  has "$(cat "$TMP/gc.argv")" "--append-notes rig-demo: capture failed for demo-rig" "$MODE: the request bead's note records the failure"
  has "$(cat "$TMP/gc.argv")" "failing its proof" "$MODE: and names the failed proof"

  echo "# $MODE shell: a release path that does not land stops short of the drain"
  eq "$(FAKE_GATE_RC=1 run "$MODE" 3)" "1|CAPTURE;UPDATE;GATE;" "$MODE: no gate filed, so no cancel and no drain"
  eq "$(FAKE_CANCEL_RC=1 run "$MODE" 3)" "1|CAPTURE;UPDATE;GATE;CANCEL;" "$MODE: the cancel did not land, so no drain"
done

# --- The app root, through the real capture and its sandbox. ---------------------
APP_MARKER=rig-demo-app-root
awk -v m="$APP_MARKER" '
  $0 ~ ("# >>> " m "$") {f=1; next}
  $0 ~ ("# <<< " m "$") {f=0}
  f' "$TOML" | sed -e 's/{{rig_name}}/demo-rig/g' > "$TMP/app-root.sh"
echo "# the app root's region extracts as runnable bash"
[ -s "$TMP/app-root.sh" ] && ok "extracted between the $APP_MARKER markers" || bad "extraction EMPTY: the $APP_MARKER markers are missing"
eq "$(grep -c "^# >>> $APP_MARKER\$" "$TOML")" "1" "exactly one $APP_MARKER region"
{ printf 'set -euo pipefail\n'; cat "$TMP/app-root.sh" "$TMP/block.sh"; } > "$TMP/app-strict.sh"
cat "$TMP/app-root.sh" "$TMP/block.sh" > "$TMP/app-plain.sh"
bash -n "$TMP/app-plain.sh" && ok "the two regions run as one script" || bad "the two regions failed bash -n"

# A city whose one rig is a git repository holding a store and a committed site.
CITY="$TMP/city"; RIG="$CITY/rigs/demo-rig"; WS="$TMP/ws"; WT="$WS/gc-review-tk-req/wt"
mkdir -p "$RIG/.beads" "$RIG/site" "$TMP/home" "$WS"
printf '<!doctype html><title>x</title>\n' > "$RIG/site/index.html"
printf '.beads/\n' > "$RIG/.gitignore"
git -C "$RIG" init -q
git -C "$RIG" add .gitignore site
git -C "$RIG" -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -q -m init
RIG_HEAD="$(git -C "$RIG" rev-parse HEAD)"
printf '# Demo: fixture\n\n**Start:** `/`\n' > "$TMP/cwd/walkthrough.md"

# The stubs these cases add. The engine lints clean and writes the clip it is
# told to; sandbox-exec keeps the profile and runs the engine; node says no
# server answers on a port and picks a free one.
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/engine" <<'ENGINE'
case "${1:-}" in
  lint) exit 0 ;;
  run) printf '%s\n' "$*" >> "$FAKE_DIR/engine.argv"
       o=""; p=""; for a in "$@"; do [ "$p" = "-o" ] && o="$a"; p="$a"; done
       printf 'clip' > "$o" ;;
esac
exit 0
ENGINE
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/sandbox-exec" <<'SBX'
printf '%s\n' "$2" > "$FAKE_DIR/profile"
shift 2
exec "$@"
SBX
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/node" <<'NODE'
[ $# -ge 3 ] || printf '50123'
exit 0
NODE
chmod +x "$TMP/bin/engine" "$TMP/bin/sandbox-exec" "$TMP/bin/node"
# gc adds the rig list the sandbox denies by, here.
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "gc-toolkit scripts-dir") [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK" ;;
  "rig list")          printf '{"rigs":[{"name":"demo-rig","path":"%s"}]}\n' "$FAKE_RIG" ;;
  "bd update")         printf 'UPDATE\n' >> "$FAKE_LOG"; printf '%s\n' "$*" >> "$FAKE_DIR/gc.argv" ;;
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG" ;;
esac
exit 0
GC

# pour <strict|plain> <serve_dir> <serve_cmd> <base_url> [rig path] prints
# "<rc>|<ordered verb log>", with no workspace left by an earlier case.
pour() {
  : > "$TMP/log"; : > "$TMP/gc.argv"; : > "$TMP/engine.argv"; : > "$TMP/escalate.argv"; rm -f "$TMP/profile"
  REVIEW_WORKSPACE_DIR="$WS" "$HERE/review-workspace.sh" remove --review-bead tk-req >/dev/null
  local rc=0
  ( cd "$TMP/cwd" && env -i PATH="$PATH" HOME="$TMP/home" TMPDIR="$TMP" GC_CITY_PATH="$CITY" GIT_CEILING_DIRECTORIES="$TMP" \
      REVIEW_WORKSPACE_DIR="$WS" SPRINTSHOW_BIN="$TMP/bin/engine" STUB_PACK="$TMP/pack" \
      FAKE_LOG="$TMP/log" FAKE_DIR="$TMP" FAKE_RIG="$RIG" FAKE_ESC_RC=0 FAKE_CANCEL_RC=0 \
      REQUEST_BEAD=tk-req SCRIPT_PATH="$TMP/cwd/walkthrough.md" OUT="$OUT" \
      SERVE_DIR="$2" SERVE_CMD="$3" BASE_URL="$4" RIG_PATH="${5-$RIG}" \
      SCRIPTS="$HERE" CLAIMED_STEP_BEAD_ID=st-capture \
      bash "$TMP/app-$1.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

echo "# the sandbox refuses the rig's own checkout, which is why the app needs a worktree"
RC=0
( cd "$TMP/cwd" && env -i PATH="$PATH" HOME="$TMP/home" TMPDIR="$TMP" GC_CITY_PATH="$CITY" FAKE_RIG="$RIG" FAKE_DIR="$TMP" \
    SPRINTSHOW_BIN="$TMP/bin/engine" \
    "$HERE/rig-demo-capture.sh" --script "$TMP/cwd/walkthrough.md" --output "$OUT" --serve 'npm run dev' --cwd "$RIG" --port 5173 ) > "$TMP/out" 2>&1 || RC=$?
eq "$RC" 1 "a capture whose --cwd is the rig's checkout exits 1"
has "$(cat "$TMP/out")" "$RIG holds $RIG" "and names the checkout"

for MODE in strict plain; do
  echo "# $MODE shell: a serve_cmd runs from a detached worktree of the rig at its HEAD"
  eq "$(pour "$MODE" "" "npm run dev" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox, and the clip is recorded"
  has "$(cat "$TMP/engine.argv")" "--serve npm run dev" "$MODE: the engine runs the command"
  has "$(cat "$TMP/engine.argv")" "--cwd $WT" "$MODE: in the worktree"
  eq "$(git -C "$WT" rev-parse HEAD)" "$RIG_HEAD" "$MODE: which is at the rig's HEAD"
  eq "$(git -C "$WT" symbolic-ref -q HEAD || echo detached)" "detached" "$MODE: and detached"
  has "$(cat "$TMP/profile")" "(allow file-read-data file-write* (subpath \"$WT\"))" "$MODE: the sandbox opens the worktree"
  case "$(cat "$TMP/profile")" in
    *"(allow file-read-data file-write* (subpath \"$RIG\"))"*) bad "$MODE: the sandbox keeps the rig's checkout shut" ;;
    *) ok "$MODE: the sandbox keeps the rig's checkout shut" ;;
  esac

  echo "# $MODE shell: a relative serve_dir resolves against that worktree"
  eq "$(pour "$MODE" "site" "" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--serve-dir $WT/site" "$MODE: the engine serves the worktree's directory"

  echo "# $MODE shell: an absolute serve_dir is served as named"
  eq "$(pour "$MODE" "$TMP/cwd" "" "")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--serve-dir $TMP/cwd" "$MODE: the engine serves the directory named"

  echo "# $MODE shell: a deployed preview needs no worktree"
  eq "$(pour "$MODE" "" "" "https://preview.example.com")" "0|UPDATE;" "$MODE: the capture passes the sandbox"
  has "$(cat "$TMP/engine.argv")" "--base-url https://preview.example.com" "$MODE: the engine drives the preview"
  [ ! -e "$WS/gc-review-tk-req" ] && ok "$MODE: and no workspace is made" || bad "$MODE: and no workspace is made"

  echo "# $MODE shell: a rig the city does not list files the capture's visit and cancels the run"
  eq "$(pour "$MODE" "site" "" "" "")" "1|UPDATE;ESCALATE;CANCEL;DRAIN;" "$MODE: it escalates, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/out")" "demo-rig is not in gc rig list" "$MODE: it names the rig"
  has "$(cat "$TMP/escalate.argv")" "--subject tk-req --key rig-demo-capture-failed" "$MODE: the visit is filed on the request bead"
  has "$(cat "$TMP/escalate.argv")" "no worktree of demo-rig could be made" "$MODE: and says no worktree could be made"
  eq "$(cat "$TMP/engine.argv")" "" "$MODE: the engine never runs"

  echo "# $MODE shell: a checkout no worktree can be made from does the same"
  eq "$(pour "$MODE" "" "npm run dev" "" "$TMP/cwd")" "1|UPDATE;ESCALATE;CANCEL;DRAIN;" "$MODE: it escalates, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/out")" "HEAD is not a commit in $TMP/cwd" "$MODE: it names the checkout"
  has "$(cat "$TMP/escalate.argv")" "no worktree of demo-rig could be made" "$MODE: and says no worktree could be made"
  eq "$(cat "$TMP/engine.argv")" "" "$MODE: the engine never runs"
done

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
