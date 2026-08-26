#!/usr/bin/env bash
# Hermetic tests for the prefix+b Helm picker (tk-00o34c).
#
# THE DEFECT. The picker ran the board as `... 2>/dev/null || printf '[]'`, so
# every failure arrived as an empty array and rendered "nothing needs you". When
# helm-svc could no longer read the city's bead stores — a schema skew that
# lasted three days — prefix+b reported the all-clear. An outage and a quiet
# city were the same pixels, and the exit code and diagnostic that would have
# separated them were both discarded.
#
# helm-svc board already exits 3 on a failed gather and prints why. These pin
# that the picker keeps both: a distinguishable message carrying the reason, and
# an empty board that still reads as empty.
#
# The real script runs against a stub tmux (which records every subcommand it is
# handed) and a stub helm-svc whose exit code and stderr each case controls. No
# tmux server, no city, no helm service.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICK="$HERE/tmux-pick-helm.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The picker resolves helm-svc from GC_SERVICE_STATE_ROOT, then GC_CITY_PATH,
# then PATH. Strip the ambient city so no case can reach the live binary and
# gather against the running city.
unset GC_CITY GC_CITY_PATH GC_CITY_ROOT GC_SERVICE_STATE_ROOT GC_TMUX_SOCKET
for _leak in GC_CITY GC_CITY_PATH GC_SERVICE_STATE_ROOT; do
    if [ -n "$(eval "printf '%s' \"\${$_leak:-}\"")" ]; then
        echo "REFUSING TO RUN: $_leak is still set — this suite must not reach a live city." >&2
        exit 1
    fi
done
unset _leak

PASS=0; FAIL=0
ok()    { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad()   { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()    { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()   { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (got: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (unexpectedly got: $1)" ;; *) ok "$3" ;; esac; }

[ -f "$PICK" ] && ok "tmux-pick-helm.sh present" || bad "tmux-pick-helm.sh missing at $PICK"

# --- fixture ------------------------------------------------------------------
CASE=0
fixture() { # -> ROOT STATE STUBS TMUXLOG; BOARD_RC/BOARD_OUT/BOARD_ERR drive the stub
    CASE=$((CASE + 1))
    local base="$TMP/case$CASE"
    ROOT="$base/scripts"; STATE="$base/state"; STUBS="$base/stubs"
    TMUXLOG="$base/tmux-calls"
    mkdir -p "$ROOT" "$STATE/bin" "$STUBS"
    cp "$PICK" "$ROOT/tmux-pick-helm.sh"
    # The picker refuses to run at all without its sibling opener.
    printf '#!/bin/sh\nexit 0\n' > "$ROOT/gc-helm.sh"
    chmod +x "$ROOT/gc-helm.sh"

    # Stub tmux: one line per subcommand, with the arguments, so a case can
    # assert on which surface the operator was shown.
    cat > "$STUBS/tmux" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_TMUX_LOG"
STUB
    chmod +x "$STUBS/tmux"

    # Stub helm-svc: exit code, stdout and stderr all come from the case.
    cat > "$STATE/bin/helm-svc" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_BOARD_OUT:-}" ] && printf '%s' "$STUB_BOARD_OUT"
[ -n "${STUB_BOARD_ERR:-}" ] && printf '%s' "$STUB_BOARD_ERR" >&2
exit "${STUB_BOARD_RC:-0}"
STUB
    chmod +x "$STATE/bin/helm-svc"
}

run_pick() { # -> RC, with the tmux calls in $(cat "$TMUXLOG")
    set +e
    STUB_TMUX_LOG="$TMUXLOG" \
    STUB_BOARD_RC="${BOARD_RC:-0}" STUB_BOARD_OUT="${BOARD_OUT:-}" \
    STUB_BOARD_ERR="${BOARD_ERR:-}" \
    GC_SERVICE_STATE_ROOT="${STATE_OVERRIDE-$STATE}" \
    PATH="$STUBS:/usr/bin:/bin" \
        sh "$ROOT/tmux-pick-helm.sh" >"$TMP/case$CASE/stdout" 2>"$TMP/case$CASE/stderr"
    RC=$?
    set -e
    CALLS="$(cat "$TMUXLOG" 2>/dev/null || true)"
}

# ==============================================================================
# A FAILED BOARD IS NOT AN EMPTY BOARD
# ==============================================================================

# --- case: the live failure — a schema skew the binary cannot read past -------
SKEW='helm-svc board: gather failed: no rig bead store could be read: rig gascity: schema version mismatch: database is at v66, binary knows up to v65 (1 migration ahead)'
fixture
BOARD_RC=3 BOARD_OUT="" BOARD_ERR="$SKEW"
run_pick
eq "$RC" 0 "(SKEW) the picker still exits cleanly"
has "$CALLS" "display-message" "(SKEW) the operator is shown a message"
has "$CALLS" "BOARD UNREADABLE" "(SKEW) named as unreadable, not as empty"
has "$CALLS" "schema version mismatch" "(SKEW) carrying the reason helm-svc gave"
hasnt "$CALLS" "nothing needs you" "(SKEW) never reported as the all-clear"
hasnt "$CALLS" "display-menu" "(SKEW) no board is rendered"

# --- case: an empty board still reads as empty --------------------------------
fixture
BOARD_RC=0 BOARD_OUT='[]' BOARD_ERR=""
run_pick
eq "$RC" 0 "(EMPTY) exits 0"
has "$CALLS" "nothing needs you" "(EMPTY) a genuinely quiet city says so"
hasnt "$CALLS" "BOARD UNREADABLE" "(EMPTY) and is not dressed as a failure"
hasnt "$CALLS" "display-menu" "(EMPTY) nothing to pick"

# --- case: a board with rows is rendered as a menu -----------------------------
fixture
BOARD_RC=0 BOARD_ERR="" BOARD_OUT='[{"id":"tk-abc12","rig":"gc-toolkit","severity":"HIGH","title":"a stranded epic","frontier":"7 open","held":true}]'
run_pick
eq "$RC" 0 "(ROWS) exits 0"
has "$CALLS" "display-menu" "(ROWS) the board is a menu"
has "$CALLS" "tk-abc12" "(ROWS) the row is on it"
hasnt "$CALLS" "BOARD UNREADABLE" "(ROWS) a readable board says nothing about readability"

# --- case: a failure with NO diagnostic is still distinguishable --------------
# The picker must not fall back to the quiet-city line just because the binary
# died without explaining itself — silence is the case that most looks like
# emptiness and least is.
fixture
BOARD_RC=3 BOARD_OUT="" BOARD_ERR=""
run_pick
eq "$RC" 0 "(SILENT) exits 0"
has "$CALLS" "BOARD UNREADABLE" "(SILENT) still reported as unreadable"
has "$CALLS" "exited 3" "(SILENT) naming the exit code, since there is nothing else to name"
hasnt "$CALLS" "nothing needs you" "(SILENT) not the all-clear"

# --- case: a non-gather failure is caught too ---------------------------------
# A usage error means the picker and the binary disagree about the flags — a
# deployment mismatch, and the one failure mode where the board is genuinely
# fine. It is still not an empty city.
fixture
BOARD_RC=2 BOARD_OUT="" BOARD_ERR='helm-svc board: unknown flag "--limit=36"'
run_pick
has "$CALLS" "BOARD UNREADABLE" "(USAGE) any non-zero exit is a failure, not an empty board"
has "$CALLS" "unknown flag" "(USAGE) with the binary's own words"

# --- case: a sprawling diagnostic is flattened and bounded --------------------
# The live message names every rig in the city, over several lines. A menu-bar
# message is one line; an unbounded one pushes its own useful half off-screen.
fixture
BOARD_RC=3 BOARD_OUT=""
BOARD_ERR="$(printf 'helm-svc board: gather failed:\nrig a: %s\nrig b: %s\n' \
    "$(printf 'x%.0s' $(seq 1 200))" "$(printf 'y%.0s' $(seq 1 200))")"
run_pick
has "$CALLS" "BOARD UNREADABLE" "(LONG) reported"
eq "$(grep -c '^' "$TMUXLOG")" "1" "(LONG) one tmux call, so the message is one line"
MSGLEN=$(awk 'END { print length($0) }' "$TMUXLOG")
[ "$MSGLEN" -le 220 ] && ok "(LONG) the message is bounded ($MSGLEN chars)" \
                      || bad "(LONG) the message ran to $MSGLEN chars"
hasnt "$CALLS" "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" \
    "(LONG) the tail is cut, not carried"

# --- case: an absent binary keeps its own line --------------------------------
fixture
STATE_OVERRIDE="$TMP/case$CASE/no-such-state"
BOARD_RC=0 BOARD_OUT='[]' BOARD_ERR=""
run_pick
unset STATE_OVERRIDE
eq "$RC" 0 "(NOBIN) exits 0"
has "$CALLS" "helm-svc binary not found" "(NOBIN) absent still reports absent"
hasnt "$CALLS" "BOARD UNREADABLE" "(NOBIN) which is a different state from a failing binary"

# ==============================================================================
# STATIC GUARD — the shape of the original defect must not come back
# ==============================================================================
# Anchored on the INVOCATION, not on prose that happens to quote the command —
# the header names `helm-svc board --json` too, and a guard that matches it
# passes over the defect it exists to catch.
BOARDLINE="$(grep '"$HELM_SVC" board' "$PICK" || true)"
[ -n "$BOARDLINE" ] && ok "(STATIC) the board invocation is where it is expected" \
                    || bad "(STATIC) no board invocation found in $PICK"
hasnt "$BOARDLINE" "2>/dev/null" \
    "(STATIC) the board's stderr is captured, never discarded"
hasnt "$BOARDLINE" "printf '[]'" \
    "(STATIC) a failed board is never substituted with an empty one"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
