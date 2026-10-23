#!/usr/bin/env bash
# Hermetic test for mol-validate's load-dispatch refusal arms.
#
# A malformed validation dispatch cannot be ruled and never will be on a retry.
# Two shapes are malformed: an input convoy without exactly one tracked member,
# and a member carrying no anchor_bead. A bare `exit 1` there would leave the
# step `open` and routed, so the pool would re-offer the same unrulable pass
# every cycle, and bare witness mail is a record no query returns.
#
# Each arm files a human gate through human-gate.sh on the malformed unit (the
# input convoy, or the pass) and, only if that gate landed, cancels the run
# through run-cancel.sh, then drains, the same contract mol-polecat-work's
# load-context arm keeps. A pass closed before its run reached load-dispatch was
# withdrawn, so its run is cancelled with nothing asked. This
# EXECUTES the real snippets extracted verbatim from the formula against a fake
# `gc` and stub scripts, so the test cannot drift from the shipped instruction.
# No live city, Dolt, or network.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-validate.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-mol-validate-refuse-gate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$TOML" ] || { echo "formula not found: $TOML" >&2; exit 1; }

# --- Extract a REAL arm from the formula. ------------------------------------
# The flag-flip pulls the lines between the markers (exclusive). If a marker is
# removed or renamed, which is exactly what a wholesale reconciliation against
# base does, extraction yields nothing and the checks below fail loudly.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$TOML"
}

# --- Fakes shared by both arms. ----------------------------------------------
# gc : `runtime drain-ack` records DRAIN so the ordered verb log is provable,
#      and `bd show` answers the validation pass at $FAKE_PASS_STATUS.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
  "bd show") printf '[{"id":"%s","status":"%s"}]\n' "$3" "${FAKE_PASS_STATUS:-open}"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# human-gate.sh, run-cancel.sh resolved out of $GC_PACK_DIR exactly as the arm
# resolves them. Each records its verb into the ordered trace and its argv where
# the assertions can read it, and returns a code the assertions control.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/human-gate.sh" <<'GATE'
#!/usr/bin/env bash
printf 'GATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_GATE:-/dev/null}"
exit "${FAKE_GATE_RC:-0}"
GATE
cat > "$TMP/pack/assets/scripts/run-cancel.sh" <<'CANCEL'
#!/usr/bin/env bash
printf 'CANCEL\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_CANCEL:-/dev/null}"
exit "${FAKE_CANCEL_RC:-0}"
CANCEL
chmod +x "$TMP/pack/assets/scripts/human-gate.sh" "$TMP/pack/assets/scripts/run-cancel.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH=""

# run <arm.sh> <VALIDATION_PASS> <ANCHOR> returns "<rc>|<ordered verb log>"
#   FAKE_*_RC control each stub's exit; FAKE_GATE/CANCEL capture argv.
run() {
  : > "$TMP/log"; : > "$TMP/gate"; : > "$TMP/cancel"
  local rc=0
  VALIDATION_PASS="$2" ANCHOR="$3" CLAIMED_STEP_BEAD_ID=st-load \
  FAKE_LOG="$TMP/log" FAKE_GATE="$TMP/gate" FAKE_CANCEL="$TMP/cancel" \
  FAKE_GATE_RC="${FAKE_GATE_RC:-0}" FAKE_CANCEL_RC="${FAKE_CANCEL_RC:-0}" \
    bash "$1" > "$TMP/out" 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/log")"
}

# check_arm <marker> <fire-VP> <fire-ANCHOR> <noop-VP> <noop-ANCHOR> <key> <subject>
check_arm() {
  local marker="$1" fvp="$2" fanc="$3" nvp="$4" nanc="$5" key="$6" subj="$7"
  local A="$TMP/$marker.sh"
  extract "$marker" > "$A"

  [ -s "$A" ] && ok "$marker: extracted between markers" || { bad "$marker: extraction EMPTY — markers missing"; return; }
  eq "$(grep -c "^# >>> $marker\$" "$TOML")" "1" "$marker: exactly one region"
  case "$(cat "$A")" in
    *\\*) bad "$marker: contains a backslash — TOML line-ending escapes will mangle it" ;;
    *)    ok  "$marker: backslash-free (safe inside a TOML triple-quoted string)" ;;
  esac
  bash -n "$A" && ok "$marker: syntactically valid bash" || bad "$marker: failed bash -n"

  # The case the arm exists for: a malformed dispatch. The gate, then the cancel,
  # then the drain; exits 1.
  eq "$(run "$A" "$fvp" "$fanc")" "1|GATE;CANCEL;DRAIN;" \
     "$marker: refusal files a gate, cancels the run, drains, exits 1"
  run "$A" "$fvp" "$fanc" >/dev/null
  has "$(cat "$TMP/gate")"  "--key $key"                "$marker: the gate names --key $key"
  has "$(cat "$TMP/gate")"  "--subject $subj"           "$marker: the gate blocks the malformed unit"
  case "$(cat "$TMP/gate")" in
    *--quiet-window*) bad "$marker: the gate declares a quiet window; a refusal is an event of this run" ;;
    *) ok "$marker: the gate declares no quiet window" ;;
  esac
  has "$(cat "$TMP/cancel")" "--step mol-validate.load-dispatch --bead st-load" "$marker: the cancel names THIS step"

  # A well-formed dispatch is a no-op: the arm falls through and load-dispatch
  # proceeds.
  eq "$(run "$A" "$nvp" "$nanc")" "0|" "$marker: well-formed dispatch is a no-op"

  # No gate recorded (human-gate.sh exits non-zero): NEVER cancel or drain, so
  # the step stays claimed and the next worker retries the ask.
  eq "$(FAKE_GATE_RC=1 run "$A" "$fvp" "$fanc")" "1|GATE;" \
     "$marker: the gate fails, so no cancel and no drain"
  # The gate landed but the cancel did not: do NOT drain, since the run is still
  # live.
  eq "$(FAKE_CANCEL_RC=1 run "$A" "$fvp" "$fanc")" "1|GATE;CANCEL;" \
     "$marker: cancel fails after the gate, so no drain"
}

# malformed convoy: fires on an empty VALIDATION_PASS; subject is the convoy.
check_arm validate-malformed-convoy-refuse "" ""      "tk-vp" ""       validate-malformed-convoy "{{convoy_id}}"
# no anchor_bead: fires on an empty ANCHOR (the pass exists); subject is the pass.
check_arm validate-no-anchor-refuse        "tk-vp" "" "tk-vp" "tk-anch" validate-no-anchor        "tk-vp"

# A pass closed before its run reached load-dispatch was withdrawn: the run is
# cancelled with nothing asked, and an open pass falls through.
W="$TMP/validate-withdrawn-pass.sh"
extract validate-withdrawn-pass > "$W"
[ -s "$W" ] && ok "validate-withdrawn-pass: extracted between markers" || bad "validate-withdrawn-pass: extraction EMPTY — markers missing"
bash -n "$W" && ok "validate-withdrawn-pass: syntactically valid bash" || bad "validate-withdrawn-pass: failed bash -n"
eq "$(FAKE_PASS_STATUS=closed run "$W" tk-vp tk-anch)" "1|CANCEL;DRAIN;" \
   "validate-withdrawn-pass: a closed pass cancels the run with nothing asked, drains, exits 1"
has "$(cat "$TMP/cancel")" "--step mol-validate.load-dispatch --bead st-load" "validate-withdrawn-pass: the cancel names THIS step"
has "$(cat "$TMP/cancel")" "tk-vp was closed" "validate-withdrawn-pass: the reason names the pass"
eq "$(FAKE_PASS_STATUS=open run "$W" tk-vp tk-anch)" "0|" "validate-withdrawn-pass: an open pass falls through"
eq "$(FAKE_PASS_STATUS=closed FAKE_CANCEL_RC=1 run "$W" tk-vp tk-anch)" "1|CANCEL;" \
   "validate-withdrawn-pass: a cancel that does not land is not drained"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
