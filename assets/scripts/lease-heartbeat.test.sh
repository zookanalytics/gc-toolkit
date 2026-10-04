#!/usr/bin/env bash
# Hermetic test for lease-heartbeat.sh — the holder-side claim-lease keepalive
# that wraps a long command and refreshes the bead's lease while it runs.
#
# No live city, Dolt, or network: a stub `gc` on PATH records every
# `bd heartbeat <id>` it is asked for, and the cadence knobs are
# turned down (INTERVAL=1, POLL=1) so a 3-second command exercises several ticks
# in a few seconds. What it proves: the command's exit status is propagated, the
# lease is refreshed up front and again during a long run, a failing or missing
# heartbeat never fails the command, and misuse exits 2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/lease-heartbeat.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-lease-heartbeat-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
ge()  { [ "$1" -ge "$2" ] && ok "$3" || bad "$3 (got '$1' want >= '$2')"; }

# --- stub gc: record each `bd heartbeat <id>`, honor a configurable exit code --
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "heartbeat" ]; then
    printf '%s\n' "${3:-}" >> "$HB_LOG"
    exit "${FAKE_GC_HB_RC:-0}"
fi
exit 0
EOF
chmod +x "$TMP/bin/gc"
export HB_LOG="$TMP/hb.log"
# Intercept `gc` with the stub; `timeout`, `sleep`, etc. still resolve normally.
export PATH="$TMP/bin:$PATH"

hb_count() { [ -f "$HB_LOG" ] && wc -l < "$HB_LOG" | tr -d ' ' || echo 0; }

# run <expected-rc-var> <args...> : run the wrapper without tripping set -e.
run() { set +e; bash "$SCRIPT" "$@"; RC=$?; set -e; }

[ -x "$SCRIPT" ] && ok "lease-heartbeat.sh is executable" || bad "lease-heartbeat.sh missing or not executable"
bash -n "$SCRIPT" && ok "lease-heartbeat.sh parses (bash -n)" || bad "lease-heartbeat.sh failed bash -n"

# --- exit-status propagation ------------------------------------------------
: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-prop -- bash -c 'exit 7'
eq "$RC" "7" "propagates a non-zero command exit status"

: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-prop -- bash -c 'exit 0'
eq "$RC" "0" "propagates a zero command exit status"

# --- the command actually runs, and the lease is refreshed WHILE it runs ----
: > "$HB_LOG"
rm -f "$TMP/ran"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-live -- bash -c "sleep 3; : > '$TMP/ran'"
eq "$RC" "0" "a long command still exits 0 under the wrapper"
[ -f "$TMP/ran" ] && ok "the wrapped command ran to completion" || bad "the wrapped command did not run"
ge "$(hb_count)" "2" "the lease is refreshed up front AND at least once during a 3s run"
# every recorded heartbeat named the bead we asked for, nothing else
STRAY="$(grep -cv '^tk-live$' "$HB_LOG" || true)"
eq "${STRAY:-0}" "0" "every heartbeat targeted the wrapped bead id"

# --- entry heartbeat fires even for an instantaneous command ----------------
: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-fast -- true
eq "$RC" "0" "an instant command exits 0"
ge "$(hb_count)" "1" "the up-front heartbeat fires even when the command is instant"

# --- a failing heartbeat must never fail the wrapped command ----------------
: > "$HB_LOG"
FAKE_GC_HB_RC=1 LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-hbfail -- bash -c 'exit 0'
eq "$RC" "0" "a heartbeat that exits non-zero does not fail the command"

# --- misuse exits 2 ---------------------------------------------------------
run tk-x -- ; eq "$RC" "2" "missing command exits 2"
run tk-x bash -c 'exit 0'; eq "$RC" "2" "missing -- separator exits 2"
run; eq "$RC" "2" "missing bead id exits 2"

# --- wiring: the long pool-claim paths must actually call the keepalive -------
# A regression guard: if a later edit drops the wrapper from a long test run,
# that path silently stops refreshing its lease. Not a correctness proof of the
# formula, just that the wiring is still present.
ROOT="$(cd "$HERE/../.." && pwd)"
for f in formulas/mol-polecat-work.toml formulas/mol-review.toml; do
    if grep -q 'lease-heartbeat.sh' "$ROOT/$f"; then
        ok "$f wires the lease keepalive"
    else
        bad "$f no longer references lease-heartbeat.sh"
    fi
done

echo "----"
echo "lease-heartbeat.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
