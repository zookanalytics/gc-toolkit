#!/usr/bin/env bash
# Hermetic test for mol-validate's load-dispatch refusal arms.
#
# A malformed validation dispatch cannot be ruled and never will be on a retry.
# Two shapes are malformed: an input convoy without exactly one tracked member,
# and a member carrying no anchor_bead. Before these arms existed load-dispatch answered both with a bare
# `exit 1`, which leaves the step `open` and routed so the pool re-offers the same
# unrulable pass every cycle, and the "escalation" the worker doctrine reached for
# was bare witness mail, a record no query returns.
#
# Each arm now files a tracked visit through escalate.sh and holds the molecule
# only if that visit landed, then drains, the same contract
# mol-polecat-work's load-context arm holds. This EXECUTES the real snippet
# extracted verbatim from the formula against a fake `gc` and stub scripts, so the
# test cannot drift from the shipped instruction. No live city, Dolt, or network.
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
# gc : only `runtime drain-ack` is reached (the arms write no bd notes); it
#      records DRAIN so the ordered verb log is provable.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "runtime drain-ack") printf 'DRAIN\n' >> "$FAKE_LOG"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# escalate.sh, molecule-hold.sh resolved out of $GC_PACK_DIR exactly as the arm
# resolves them. Each records its verb into the ordered trace and its argv where
# the assertions can read it, and returns a code the assertions control.
mkdir -p "$TMP/pack/assets/scripts"
cat > "$TMP/pack/assets/scripts/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf 'ESCALATE\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_ESC:-/dev/null}"
exit "${FAKE_ESC_RC:-0}"
ESC
cat > "$TMP/pack/assets/scripts/molecule-hold.sh" <<'HOLD'
#!/usr/bin/env bash
printf 'HOLD\n' >> "$FAKE_LOG"
printf '%s\n' "$*" >> "${FAKE_HOLD:-/dev/null}"
exit "${FAKE_HOLD_RC:-0}"
HOLD
chmod +x "$TMP/pack/assets/scripts/escalate.sh" "$TMP/pack/assets/scripts/molecule-hold.sh"
export GC_PACK_DIR="$TMP/pack" GC_RIG_ROOT="" GC_CITY_PATH=""

# run <arm.sh> <VALIDATION_PASS> <ANCHOR> returns "<rc>|<ordered verb log>"
#   FAKE_*_RC control each stub's exit; FAKE_ESC/HOLD capture argv.
run() {
  : > "$TMP/log"; : > "$TMP/esc"; : > "$TMP/hold"
  local rc=0
  VALIDATION_PASS="$2" ANCHOR="$3" CLAIMED_STEP_BEAD_ID=st-load \
  FAKE_LOG="$TMP/log" FAKE_ESC="$TMP/esc" FAKE_HOLD="$TMP/hold" \
  FAKE_ESC_RC="${FAKE_ESC_RC:-0}" FAKE_HOLD_RC="${FAKE_HOLD_RC:-0}" \
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

  # The case the arm exists for: a malformed dispatch. escalate, then hold, then
  # drain; exits 1.
  eq "$(run "$A" "$fvp" "$fanc")" "1|ESCALATE;HOLD;DRAIN;" \
     "$marker: refusal escalates, holds, drains, exits 1"
  run "$A" "$fvp" "$fanc" >/dev/null
  has "$(cat "$TMP/esc")"  "--key $key"                "$marker: escalate names --key $key"
  has "$(cat "$TMP/esc")"  "--subject $subj"           "$marker: escalate --subject names the malformed unit"
  has "$(cat "$TMP/hold")" "mol-validate.load-dispatch" "$marker: hold names THIS step"

  # A well-formed dispatch is a no-op: the arm falls through and load-dispatch
  # proceeds.
  eq "$(run "$A" "$nvp" "$nanc")" "0|" "$marker: well-formed dispatch is a no-op"

  # No release path recorded (escalate exits non-zero): NEVER hold or drain, so the
  # step stays claimable and the next worker retries the escalation.
  eq "$(FAKE_ESC_RC=1 run "$A" "$fvp" "$fanc")" "1|ESCALATE;" \
     "$marker: escalate fails, so no hold and no drain"
  # Release recorded but the hold did not land: do NOT drain, since the molecule can
  # still be re-offered.
  eq "$(FAKE_HOLD_RC=1 run "$A" "$fvp" "$fanc")" "1|ESCALATE;HOLD;" \
     "$marker: hold fails after escalate, so no drain"
}

# malformed convoy: fires on an empty VALIDATION_PASS; subject is the convoy.
check_arm validate-malformed-convoy-refuse "" ""      "tk-vp" ""       validate-malformed-convoy "{{convoy_id}}"
# no anchor_bead: fires on an empty ANCHOR (the pass exists); subject is the pass.
check_arm validate-no-anchor-refuse        "tk-vp" "" "tk-vp" "tk-anch" validate-no-anchor        "tk-vp"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
