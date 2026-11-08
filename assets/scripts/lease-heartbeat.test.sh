#!/usr/bin/env bash
# Hermetic test for lease-heartbeat.sh — the holder-side claim-lease keepalive
# that wraps a long command and refreshes the bead's lease while it runs.
#
# No live city, Dolt, or network: a stub `gc` on PATH records every
# `bd heartbeat <id>` it is asked for, and the cadence knobs are
# turned down (INTERVAL=1, POLL=1) so a 3-second command exercises several ticks
# in a few seconds. What it proves: the command's exit status is propagated, the
# lease is refreshed up front and again during a long run, a failing or missing
# heartbeat never fails the command, a refused heartbeat is reported once on
# stderr, an empty bead id runs the command plain, and misuse exits 2.
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
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 ('$2' not in '$1')" ;; esac; }

# --- stub gc: record each `bd heartbeat <id>`, honor a configurable exit code --
# A refusal prints the store's own wording, so the report's reason is checkable.
# `gc-toolkit scripts-dir` names the pack, $STUB_PACK, as gc does for the
# binding the city imports the pack under, and fails when none is set.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'EOF'
if [ "${1:-} ${2:-}" = "gc-toolkit scripts-dir" ]; then
    [ -n "${STUB_PACK:-}" ] || exit 1
    printf '%s/assets/scripts\n' "$STUB_PACK"; exit 0
fi
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "heartbeat" ]; then
    printf '%s\n' "${3:-}" >> "$HB_LOG"
    rc="${FAKE_GC_HB_RC:-0}"
    [ "$rc" -eq 0 ] || echo "Error: heartbeat ${3:-}: issue not claimable: ${3:-} status open" >&2
    exit "$rc"
fi
exit 0
EOF
chmod +x "$TMP/bin/gc"
export HB_LOG="$TMP/hb.log"
# Intercept `gc` with the stub; `timeout`, `sleep`, etc. still resolve normally.
export PATH="$TMP/bin:$PATH"

hb_count() { [ -f "$HB_LOG" ] && wc -l < "$HB_LOG" | tr -d ' ' || echo 0; }

# run <args...> : run the wrapper without tripping set -e; its status lands in RC.
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
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-live -- bash -c "sleep 3; : > '$TMP/ran'" 2> "$TMP/err"
eq "$RC" "0" "a long command still exits 0 under the wrapper"
[ -f "$TMP/ran" ] && ok "the wrapped command ran to completion" || bad "the wrapped command did not run"
ge "$(hb_count)" "2" "the lease is refreshed up front AND at least once during a 3s run"
# every recorded heartbeat named the bead we asked for, nothing else
STRAY="$(grep -cv '^tk-live$' "$HB_LOG" || true)"
eq "${STRAY:-0}" "0" "every heartbeat targeted the wrapped bead id"
eq "$(wc -c < "$TMP/err" | tr -d ' ')" "0" "heartbeats the store accepts write nothing to stderr"

# --- entry heartbeat fires even for an instantaneous command ----------------
: > "$HB_LOG"
LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-fast -- true
eq "$RC" "0" "an instant command exits 0"
ge "$(hb_count)" "1" "the up-front heartbeat fires even when the command is instant"

# --- a failing heartbeat must never fail the wrapped command ----------------
: > "$HB_LOG"
FAKE_GC_HB_RC=1 LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-hbfail -- bash -c 'exit 0' 2> /dev/null
eq "$RC" "0" "a heartbeat that exits non-zero does not fail the command"

# --- a refused heartbeat is reported once, not swallowed --------------------
# A keepalive aimed at a bead the holder never claimed is refused on every tick.
# The holder must hear about it, once, while the command runs to its own status.
: > "$HB_LOG"
rm -f "$TMP/ran"
FAKE_GC_HB_RC=1 LEASE_HEARTBEAT_INTERVAL=1 LEASE_HEARTBEAT_POLL=1 run tk-refused -- bash -c "sleep 3; : > '$TMP/ran'; exit 3" 2> "$TMP/err"
eq "$RC" "3" "a refused heartbeat leaves the command's exit status intact"
[ -f "$TMP/ran" ] && ok "the command runs to completion under refused heartbeats" || bad "the command did not run under refused heartbeats"
ge "$(hb_count)" "2" "the wrapper keeps trying across the run"
eq "$(grep -cF 'heartbeat on tk-refused failed' "$TMP/err" || true)" "1" "the refusal is reported exactly once across several failed ticks"
has "$(cat "$TMP/err")" "issue not claimable" "the report carries the store's reason"

# --- an empty bead id runs the command plain --------------------------------
# An unset claim variable in a caller must cost the keepalive, never the run.
: > "$HB_LOG"
rm -f "$TMP/ran"
run "" -- bash -c ": > '$TMP/ran'; exit 4" 2> "$TMP/err"
eq "$RC" "4" "an empty bead id still runs the command and propagates its status"
[ -f "$TMP/ran" ] && ok "an empty bead id runs the wrapped command" || bad "an empty bead id did not run the command"
eq "$(hb_count)" "0" "an empty bead id makes no heartbeat call"
has "$(cat "$TMP/err")" "no bead id given" "an empty bead id is reported on stderr"

# --- misuse exits 2 ---------------------------------------------------------
run tk-x -- 2> /dev/null; eq "$RC" "2" "missing command exits 2"
run tk-x bash -c 'exit 0' 2> /dev/null; eq "$RC" "2" "missing -- separator exits 2"
run 2> /dev/null; eq "$RC" "2" "missing bead id exits 2"

echo "----"
echo "lease-heartbeat.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
