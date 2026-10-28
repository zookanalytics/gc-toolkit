#!/usr/bin/env bash
# Hermetic test for mol-rig-demo's capture block, the rig-demo-capture-run
# region of the capture step.
#
# rig-demo-capture.sh exits 1 when no clip appears and 3 when the clip records a
# step failing its proof. On either, the block appends a note naming which one,
# files a visit through escalate.sh, cancels the run through run-cancel.sh only
# if the visit landed, and drains only if the cancel landed. On success it
# records the clip path on the request bead.
#
# A step's blocks can run under a strict shell, where a failing command whose
# status nothing catches ends the block on the spot. For this block that abort
# skips the escalation and the cancel, which leaves the run claimed with no
# visit behind it. So every case runs twice, once under `set -euo pipefail` and
# once under a plain shell, and both runs must reach the same end.
#
# EXECUTES the real block extracted verbatim between the formula markers, with
# the pour vars rendered at their defaults, against a stub capture, a fake `gc`,
# and stub escalate and cancel scripts. No live city, browser, or network.
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
# success) and `runtime drain-ack`. The capture, escalate and cancel stubs sit in
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
{ printf '%s\n' "$SHEBANG"; cat; } > "$TMP/pack/assets/scripts/escalate.sh" <<'ESC'
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "$FAKE_DIR/escalate.argv"
exit "${FAKE_ESC_RC:-0}"
ESC
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
#   FAKE_ESC_RC and FAKE_CANCEL_RC set the escalate and cancel stubs' exits.
run() {
  : > "$TMP/log"; : > "$TMP/gc.argv"; : > "$TMP/capture.argv"; : > "$TMP/escalate.argv"; : > "$TMP/cancel.argv"
  local rc=0
  ( cd "$TMP/cwd" &&
    REQUEST_BEAD=tk-req SCRIPT_PATH="$TMP/cwd/walkthrough.md" OUT="$OUT" \
    SERVE_DIR="$TMP/cwd/site" SERVE_CMD="" BASE_URL="" RIG_PATH="$TMP/cwd" \
    SCRIPTS="$TMP/pack/assets/scripts" CLAIMED_STEP_BEAD_ID=st-capture \
    FAKE_LOG="$TMP/log" FAKE_DIR="$TMP" FAKE_CAPTURE_RC="$2" \
    FAKE_ESC_RC="${FAKE_ESC_RC:-0}" FAKE_CANCEL_RC="${FAKE_CANCEL_RC:-0}" \
      bash "$TMP/$1.sh" ) > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

for MODE in strict plain; do
  echo "# $MODE shell: a clean capture records the clip on the request bead"
  eq "$(run "$MODE" 0)" "0|CAPTURE;UPDATE;" "$MODE: exit 0 records the clip, with no escalation or cancel"
  has "$(cat "$TMP/capture.argv")" "--output $OUT" "$MODE: the capture writes the clip the block records"
  has "$(cat "$TMP/gc.argv")" "bd update tk-req --set-metadata demo_mp4_path=$OUT" "$MODE: the clip path lands on the request bead"

  echo "# $MODE shell: no clip escalates, cancels, and drains"
  eq "$(run "$MODE" 1)" "1|CAPTURE;UPDATE;ESCALATE;CANCEL;DRAIN;" "$MODE: exit 1 escalates, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/escalate.argv")" "--subject tk-req --key rig-demo-capture-failed" "$MODE: the visit is filed on the request bead under the capture key"
  has "$(cat "$TMP/escalate.argv")" "produced no MP4" "$MODE: exit 1 is reported as no clip"
  has "$(cat "$TMP/cancel.argv")" "--step mol-rig-demo.capture --bead st-capture" "$MODE: the cancel names the capture step and the claimed bead"

  echo "# $MODE shell: a clip with a failed proof escalates, cancels, and drains"
  eq "$(run "$MODE" 3)" "1|CAPTURE;UPDATE;ESCALATE;CANCEL;DRAIN;" "$MODE: exit 3 escalates, cancels the run, drains, and exits 1"
  has "$(cat "$TMP/escalate.argv")" "the clip at $OUT recorded at least one step failing its proof" "$MODE: the visit names the failed-proof clip"
  has "$(cat "$TMP/gc.argv")" "--append-notes rig-demo: capture failed for demo-rig" "$MODE: the request bead's note records the failure"
  has "$(cat "$TMP/gc.argv")" "failing its proof" "$MODE: and names the failed proof"

  echo "# $MODE shell: a release path that does not land stops short of the drain"
  eq "$(FAKE_ESC_RC=1 run "$MODE" 3)" "1|CAPTURE;UPDATE;ESCALATE;" "$MODE: no visit filed, so no cancel and no drain"
  eq "$(FAKE_CANCEL_RC=1 run "$MODE" 3)" "1|CAPTURE;UPDATE;ESCALATE;CANCEL;" "$MODE: the cancel did not land, so no drain"
done

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
