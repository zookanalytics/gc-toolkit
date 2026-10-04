#!/usr/bin/env bash
# Hermetic test for mol-first-reaction.toml's live-intake consume block.
#
# A direct pour of a subject marked gc.reaction_owned=1 records the reaction
# (gc.proactive_reaction=1, the permanent proof) and consumes the one-shot intake
# marker. The invariant the consume must hold: the bead is NEVER left with NEITHER
# marker — that state is what a later proactive scan reads as unreacted and
# re-visits, filing the SECOND visit the whole feature exists to prevent. So the
# unset is gated on a read-back-PROVEN stamp: a stamp that fails, or that returns
# success without persisting, must leave the intake marker armed.
#
# The block is extracted between its `# >>> live-intake-consume` markers and run
# against a stateful `gc` stub, so no live city, Dolt, or gc is needed. The block
# is POSIX sh, run via sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FORMULA="$ROOT/formulas/mol-first-reaction.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-fr-intake-consume.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
keeps_a_marker() {  # $1 proactive-left, $2 intake-left, $3 label
  if [ "$1" = "1" ] || [ "$2" = "1" ]; then ok "$3"
  else bad "$3 (the bead has NEITHER marker — a second visit would be filed)"; fi
}

[ -f "$FORMULA" ] && ok "mol-first-reaction.toml present" || bad "formula missing at $FORMULA"

# Extract the consume block between its markers.
BLOCK="$(awk '/# >>> live-intake-consume/{f=1; next} /# <<< live-intake-consume/{f=0} f' "$FORMULA")"
[ -n "$BLOCK" ] && ok "live-intake-consume block extracted" || bad "could not extract live-intake-consume block"

# A stateful gc stub. $STATE/proactive and $STATE/intake hold the two markers;
# $STATE/unset_calls records every --unset-metadata gc.reaction_owned call.
# $STAMP_MODE controls the gc.proactive_reaction=1 write:
#   ok   -> persists it, exit 0 (normal)
#   fail -> writes nothing, exit 1 (the store refused the write)
#   drop -> exit 0 but persists nothing (a lying success — the case a bare
#           exit-code gate would miss, which the read-back must catch)
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "bd update")
    shift 2
    case "$*" in
      *"--set-metadata gc.proactive_reaction=1"*)
        case "${STAMP_MODE:-ok}" in
          fail) exit 1 ;;
          drop) exit 0 ;;
          *)    printf '1' > "$STATE/proactive"; exit 0 ;;
        esac ;;
      *"--unset-metadata gc.reaction_owned"*)
        printf '%s\n' "$*" >> "$STATE/unset_calls"
        : > "$STATE/intake"
        exit 0 ;;
    esac
    exit 0 ;;
  "bd show")
    pr="$(cat "$STATE/proactive" 2>/dev/null || true)"
    ik="$(cat "$STATE/intake" 2>/dev/null || true)"
    jq -n --arg pr "$pr" --arg ik "$ik" \
      '[{id:"tk-sub", metadata:
          ((if $pr=="1" then {"gc.proactive_reaction":"1"} else {} end)
         + (if $ik=="1" then {"gc.reaction_owned":"1"} else {} end))}]' ;;
esac
STUB
chmod +x "$TMP/bin/gc"

# run_consume <stamp-mode>: reset state (bead arrives MARKED and unreacted), run
# the extracted block, then read back the final marker state and the unset calls.
run_consume() {
  export STATE="$TMP/state.$1"; mkdir -p "$STATE"
  printf '1' > "$STATE/intake"
  : > "$STATE/proactive"
  : > "$STATE/unset_calls"
  STAMP_MODE="$1" WORK_BEAD_ID="tk-sub" PATH="$TMP/bin:$PATH" sh -c "$BLOCK" >/dev/null 2>&1 || true
  PR_LEFT="$(cat "$STATE/proactive" 2>/dev/null || true)"
  IK_LEFT="$(cat "$STATE/intake" 2>/dev/null || true)"
  UNSET_CALLED="$([ -s "$STATE/unset_calls" ] && echo yes || echo no)"
}

echo "# a proven stamp consumes the intake marker, leaving the permanent proof"
run_consume ok
eq "$UNSET_CALLED" "yes" "(OK) the intake marker is consumed once the stamp is proven"
eq "$IK_LEFT" "" "(OK) …gc.reaction_owned is gone"
eq "$PR_LEFT" "1" "(OK) …gc.proactive_reaction remains as the permanent proof"
keeps_a_marker "$PR_LEFT" "$IK_LEFT" "(OK-INVARIANT) the bead keeps at least one marker"

echo "# a stamp that FAILS leaves the intake marker armed (never both-empty)"
run_consume fail
eq "$UNSET_CALLED" "no" "(FAIL) the intake marker is NOT consumed when the stamp failed"
eq "$IK_LEFT" "1" "(FAIL) …gc.reaction_owned stays armed so the scan drop still covers the bead"
keeps_a_marker "$PR_LEFT" "$IK_LEFT" "(FAIL-INVARIANT) the bead keeps at least one marker"

echo "# a stamp that SILENTLY DROPS (exit 0, no persist) is caught by the read-back"
run_consume drop
eq "$UNSET_CALLED" "no" "(DROP) an unconfirmed stamp does not license the unset"
eq "$IK_LEFT" "1" "(DROP) …gc.reaction_owned stays armed"
keeps_a_marker "$PR_LEFT" "$IK_LEFT" "(DROP-INVARIANT) the bead keeps at least one marker"

echo
echo "first-reaction intake consume: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
