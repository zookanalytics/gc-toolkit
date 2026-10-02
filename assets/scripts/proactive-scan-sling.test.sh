#!/usr/bin/env bash
# proactive-scan-sling.test.sh — the scheduled intake trigger, hermetic.
#
# proactive-scan-sling.sh is the exec of a cooldown order; its whole contract is:
#   1. THE GATE. Run the picker's `scan --sling` only when `deliverable` says a
#      slung reaction can be claimed on this rig; otherwise skip as a clean
#      exit 0, so a rig with no live proactive pool routes nothing to nobody.
#   2. PASS-THROUGH. On the run side it hands the picker exactly `scan --sling`
#      and nothing else, and (via exec) the picker's exit code is the wrapper's.
#   3. FAIL-CLOSED on a missing engine (exit non-zero), never a silent skip.
#   4. THE ORDER DECLARATION. orders/proactive-scan-sling.toml is a rig-scoped
#      cooldown order naming this script, with an interval, a timeout, and no
#      `idempotent` key (the sweep writes; single-flight per rig guards it).
# Hermetic: stubs the picker via GC_PROACTIVE_TOOL; no city, no Dolt, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SCRIPT="$ROOT/assets/scripts/proactive-scan-sling.sh"
ORDER="$ROOT/orders/proactive-scan-sling.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-proactive-scan-sling-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3" "found '$2' in: $1" ;; *) ok "$3" ;; esac; }

[ -s "$SCRIPT" ] || { echo "missing $SCRIPT"; exit 1; }
[ -x "$SCRIPT" ] || { echo "$SCRIPT is not executable"; exit 1; }

echo "── the script is valid shell ──"
bash -n "$SCRIPT" && ok "proactive-scan-sling.sh: valid bash" || bad "proactive-scan-sling.sh: valid bash" "bash -n failed"

# --- the picker stub ---------------------------------------------------------
# Stands in for tools/gc-proactive.sh, serving exactly the two verbs the wrapper
# calls: `deliverable` (prints its verdict, exits STUB_DELIVERABLE_RC) and `scan`
# (logs its full argv so the test can prove what was handed to it, exits
# STUB_SCAN_RC). It refuses any other verb the way the real tool's main() dies on
# an unknown one — so a wrapper that called something else would fail loudly.
STUB="$TMP/gc-proactive.sh"
cat > "$STUB" <<'PICKER'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_LOG:?}"
verb="${1:-}"; shift || true
case "$verb" in
  deliverable)
    printf '%s\n' "${STUB_DELIVERABLE_MSG:-yes: live}"
    exit "${STUB_DELIVERABLE_RC:-0}" ;;
  scan)
    printf 'scan args: %s\n' "$*"
    printf 'ran\n' >> "${STUB_SCAN_LOG:?}"
    exit "${STUB_SCAN_RC:-0}" ;;
  *) echo "picker stub: unsupported verb '$verb'" >&2; exit 2 ;;
esac
PICKER
chmod +x "$STUB"

STUB_LOG="$TMP/picker.log"
STUB_SCAN_LOG="$TMP/scan.log"

OUT=""; RC=0
run() { # run <deliverable_rc> <deliverable_msg> <scan_rc>
  : > "$STUB_LOG"; : > "$STUB_SCAN_LOG"
  OUT="$(GC_PROACTIVE_TOOL="$STUB" STUB_LOG="$STUB_LOG" STUB_SCAN_LOG="$STUB_SCAN_LOG" \
         STUB_DELIVERABLE_RC="$1" STUB_DELIVERABLE_MSG="$2" STUB_SCAN_RC="$3" \
         "$SCRIPT" 2>&1)"; RC=$?
}
scanran() { [ -s "$STUB_SCAN_LOG" ]; }

# ============================================================================
# 1. THE GATE
# ============================================================================
echo "── deliverable yes → the sweep runs scan --sling ──"
run 0 "yes: live" 0
eq "$RC" "0" "a deliverable pool runs the sweep (exit 0)"
scanran && ok "scan --sling was invoked" || bad "scan --sling was invoked" "the scan log is empty"
has "$OUT" "scan args: --sling" "and it is handed exactly --sling"

echo "── deliverable no → clean skip, no scan ──"
run 1 "no: pool absent" 0
eq "$RC" "0" "a rig with no live pool skips as a clean exit 0"
scanran && bad "no scan on a skip" "scan --sling ran anyway" || ok "no scan on a skip"
has "$OUT" "no sweep this rig" "and it says why it skipped"
has "$OUT" "no: pool absent" "surfacing the deliverable verdict"

# ============================================================================
# 2. PASS-THROUGH — exactly scan --sling, and the picker's exit is the wrapper's
# ============================================================================
echo "── the wrapper adds no arguments of its own ──"
run 0 "yes: live" 0
eq "$(grep -c '^scan --sling$' "$STUB_LOG")" "1" "the picker saw 'scan --sling' verbatim"
eq "$(grep -c '^deliverable$' "$STUB_LOG")" "1" "deliverable was checked exactly once, with no args"

echo "── on the run side the picker's failure is the wrapper's failure ──"
run 0 "yes: live" 4
eq "$RC" "4" "a failing scan --sling propagates its exit code (exec hands off)"

# ============================================================================
# 3. FAIL-CLOSED on a missing engine
# ============================================================================
echo "── a missing / non-executable picker fails closed (non-zero) ──"
OUT="$(GC_PROACTIVE_TOOL="$TMP/does-not-exist" "$SCRIPT" 2>&1)"; RC=$?
eq "$RC" "1" "no engine → exit 1, not a silent skip"
has "$OUT" "picker not executable" "and says what is missing"

# ============================================================================
# 4. THE ORDER DECLARATION
# ============================================================================
echo "── orders/proactive-scan-sling.toml is a rig-scoped cooldown order ──"
[ -s "$ORDER" ] || bad "orders/proactive-scan-sling.toml exists" "missing $ORDER"
O="$(cat "$ORDER" 2>/dev/null)"
has "$O" 'trigger = "cooldown"' "it is cooldown-triggered"
has "$O" 'scope = "rig"' "it is rig-scoped (reacts over the rig's own store)"
has "$O" 'assets/scripts/proactive-scan-sling.sh' "exec names this script"
has "$O" 'interval =' "a cooldown trigger declares an interval (the cadence)"
has "$O" 'timeout =' "it bounds the exec with a timeout"
# The key itself, not the word: the comment explains WHY the key is absent.
eq "$(grep -cE '^[[:space:]]*idempotent[[:space:]]*=' "$ORDER")" "0" "no idempotent key — the sweep writes, single-flight guards it"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
