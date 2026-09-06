#!/usr/bin/env bash
# pin-keepalive.sh — assert the durable awake-pin on standing conversational
# named sessions, so the session reconciler's config-drift restart keeps
# deferring on them. The reconciler defers unconditionally while a session
# carries metadata.pin_awake, and pin_awake is settable only by `gc session
# pin`, never from config — so the only way to make "exempt from config-drift
# restart" declarative in a pack, with no gascity fork, is a pack-side order
# that asserts the pin from OUTSIDE the session. Run that way there is no
# startup race, and a pin dropped by a full session re-materialization is
# re-asserted on the next pass.
#
# A standing conversational named session is a configured named singleton
# (metadata.configured_named_session=true — the pack's [[named_session]]
# declarations, session_origin=named) whose provider is the interactive one
# (default "claude"), which is what separates mechanik from the claude-watch
# singletons (deacon, witness, refinery) and from the ephemeral claude pool
# workers (polecat, converse). Today that predicate selects mechanik; a
# converse sitting inherits it the moment its reshape makes it a configured
# named conversational session, with no change here.
#
# DUAL MODE, ONE PREDICATE:
#   pin-keepalive.sh --check   the condition order's CHECK. Read-only. Decides
#                              cheaply whether a pass is owed and prints its
#                              verdict. Exit 0 = run the exec, non-zero = do not
#                              — the condition-order contract, mirrored from
#                              liveness-sweep-precheck.sh.
#   pin-keepalive.sh           the EXEC. Pins every unpinned target, then leaves
#                              the cadence window spent. Exit 0 = pass ran,
#                              1 = aborted on an unreadable roster, 2 = usage.
# The check is this same file in --check mode so enumerate_targets has ONE
# definition and check and exec cannot drift; the read-only contract is a mode,
# structurally — only the exec branch ever calls `gc session pin`.
#
# A condition trigger has no interval, so the cadence lives in the cooldown
# stamp here: the check SKIPs and spends the window on a fully-pinned roster,
# the exec spends it when a pass starts, and a RUN verdict never spends it —
# more callers evaluate a check than dispatch from it. Cheap when nothing is
# owed: almost every tick short-circuits on the stamp before any gc read, and
# a real classification is a bounded handful of reads.
#
# FAIL-OPEN, like liveness-sweep: any unreadable roster or session probe RUNS
# the pass — a probe that cannot be read excludes nothing. Pinning is
# idempotent, so an over-run costs a redundant `gc session pin`, while an
# under-run leaves a live conversation exposed to a config-drift restart.
#
# The supervisor that runs exec orders carries no GC_CITY, and sessions and
# their beads live in the CITY store, so the city is resolved from the env
# chain and then from `gc service list --json`, and passed as --city to every
# gc call.
#
# NOT set -e: every failure is handled and routed to the correct side.
set -uo pipefail

PROG=pin-keepalive

# The interactive/conversational provider. mechanik is "claude"; the watchers
# (deacon, witness, refinery) are "claude-watch" and are deliberately excluded.
PROVIDER="${PIN_KEEPALIVE_PROVIDER:-claude}"
# The cadence. A pin is durable and only drops on a full re-materialization, and
# a just-recreated session matches current config, so the exposure this closes
# is rarely urgent — a coarse window keeps the check cheap.
INTERVAL="${PIN_KEEPALIVE_INTERVAL:-300}"
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=300 ;; esac
CALL_TIMEOUT="${PIN_KEEPALIVE_CALL_TIMEOUT:-20}"
KILL_AFTER="${PIN_KEEPALIVE_KILL_AFTER:-5}"
LOG_KEEP="${PIN_KEEPALIVE_LOG_KEEP:-400}"

MODE=exec
FORCE=0
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE=check ;;
        --force)   FORCE=1 ;;      # check: classify inside the window, don't spend it
        --dry-run) DRY_RUN=1 ;;    # exec: enumerate and report, pin nothing, stamp nothing
        -h|--help) sed -n '/^# DUAL MODE/,/^# NOT set -e/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$PROG: unexpected argument: $1" >&2; exit 2 ;;
    esac
    shift
done

# The trap reads DECIDED to tell an abort — which fails to the mode's safe side
# — from a real verdict that has already chosen its own exit code.
DECIDED=0

REPORT=""
say() { printf '%s\n' "$*"; REPORT="$REPORT$*"$'\n'; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload; strip all
# but LF before any jq read of bd/session output. The TAB-splitting in
# enumerate_targets splits jq's own output, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

if command -v timeout >/dev/null 2>&1; then
    if timeout -k 1 1 true >/dev/null 2>&1; then
        bounded() { timeout -k "$KILL_AFTER" "$CALL_TIMEOUT" "$@"; }
    else
        bounded() { timeout "$CALL_TIMEOUT" "$@"; }
    fi
else
    bounded() { "$@"; }
fi

# --- city -------------------------------------------------------------------
# Env chain first, so a hand run probes the city its operator meant; then the
# CLI, which is the only source the scheduled order has (its supervisor env
# carries no GC_CITY).
CITY="${PIN_KEEPALIVE_CITY:-${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}}"
if [ -z "$CITY" ]; then
    CITY="$(bounded gc service list --json 2>/dev/null | scrub | jq -r '.city_path // empty' 2>/dev/null)"
fi
CITY_FLAG=()
[ -n "$CITY" ] && CITY_FLAG=(--city "$CITY")

# --- state dir + cadence stamp ----------------------------------------------
# City+pack scoped. This order is city-scoped and registers once, so a single
# stamp is correct — no per-rig key. GC_PACK_STATE_DIR is set only on the rig
# branch of the order-exec env, so a city-scoped run derives the dir from the
# resolved city, the way boot-health does, with a TMPDIR last resort.
if [ -n "${GC_PACK_STATE_DIR:-}" ]; then
    STATE_BASE="$GC_PACK_STATE_DIR"
elif [ -n "$CITY" ]; then
    STATE_BASE="$CITY/.gc/runtime/packs/gc-toolkit"
else
    STATE_BASE="${TMPDIR:-/tmp}/gc"
fi
STATE_DIR="${PIN_KEEPALIVE_STATE_DIR:-$STATE_BASE/pin-keepalive}"
STAMP="$STATE_DIR/last-pass"
LOG="$STATE_DIR/pass.log"

# rename(2) consults the directory's mode, never the stamp's own, so writing a
# temp file in $STATE_DIR probes exactly the permission the real write needs and
# a read-only last-pass still takes the window. What rename cannot replace is a
# $STAMP that is not a regular file, refused here too.
spend_window() { # spend_window <epoch-seconds>
    local tmp="$STAMP.$$.tmp"
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if printf '%s\n' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STAMP" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# shellcheck disable=SC2329  # reached through the EXIT trap
flush_report() {
    [ -n "$REPORT" ] || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    { printf '=== %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MODE"; printf '%s' "$REPORT"; } >> "$LOG" 2>/dev/null || return 0
    if [ -w "$LOG" ]; then
        tail -n "$LOG_KEEP" "$LOG" > "$LOG.trim" 2>/dev/null && mv "$LOG.trim" "$LOG" 2>/dev/null
    fi
    return 0
}

# An abort before a verdict must not read as "nothing to do": the check runs the
# pass (fail-open), the exec reports the abort. Placed after the helpers it uses.
# shellcheck disable=SC2329  # reached through the EXIT trap
on_exit() {
    local rc=$?
    if [ "$DECIDED" -eq 0 ]; then
        if [ "$MODE" = check ]; then
            say "$PROG check: ABORTED before deciding (rc=$rc) — NOT a fully-pinned roster; running the pass."
            flush_report
            exit 0
        fi
        say "$PROG exec: ABORTED before completing (rc=$rc)."
        flush_report
        exit 1
    fi
    flush_report
    exit "$rc"
}
trap on_exit EXIT

command -v jq >/dev/null 2>&1 || {
    # Can't classify; the check runs the pass, the exec cannot pin.
    if [ "$MODE" = check ]; then say "$PROG check: jq is missing — running the pass."; DECIDED=1; exit 0; fi
    say "$PROG exec: jq is missing — cannot pin."; DECIDED=1; exit 1
}

# Append an alias to the newline-separated TARGETS list.
add_target() {
    if [ -z "$TARGETS" ]; then TARGETS="$1"; else TARGETS="$TARGETS
$1"; fi
}

# --- the predicate: standing conversational named sessions that are unpinned --
# Sets TARGETS (newline-separated session aliases to pin) and ENUM_STATUS:
#   ok         every read succeeded
#   list_fail  the session roster was unreadable
#   probe_fail the roster read, but a candidate's session bead did not — its
#              alias is still added to TARGETS, because a probe that cannot be
#              read excludes nothing (fail-open); the pin is idempotent, and an
#              under-run would leave that session exposed to a config-drift restart
# A candidate is conversational (provider match) and named (non-empty alias, a
# cheap pre-filter — a pool instance has no canonical alias); its session bead
# then confirms configured_named_session=true (the authoritative "standing
# named" gate) and reports pin_awake. Read-only: no writes, no pins.
enumerate_targets() {
    TARGETS=""
    ENUM_STATUS=ok
    local sess cand id alias b cns pin
    sess="$(bounded gc session list "${CITY_FLAG[@]}" --state all --json 2>/dev/null | scrub)"
    if ! printf '%s' "$sess" | jq -e '(.sessions // empty) | type == "array"' >/dev/null 2>&1; then
        ENUM_STATUS=list_fail
        return 0
    fi
    cand="$(printf '%s' "$sess" | jq -r --arg p "$PROVIDER" '
        .sessions[]
        | select((.provider // "") == $p)
        | select((.alias // "") != "")
        | (.id // "") + "\t" + (.alias // "")' 2>/dev/null)"
    while IFS="$(printf '\t')" read -r id alias; do
        [ -n "$id" ] || continue
        b="$(bounded gc bd show "$id" "${CITY_FLAG[@]}" --json 2>/dev/null | scrub)"
        if ! printf '%s' "$b" | jq -e '(if type=="array" then .[0] else . end) | type == "object"' >/dev/null 2>&1; then
            ENUM_STATUS=probe_fail
            add_target "$alias"
            continue
        fi
        cns="$(printf '%s' "$b" | jq -r '(if type=="array" then .[0] else . end) | .metadata.configured_named_session // ""' 2>/dev/null)"
        pin="$(printf '%s' "$b" | jq -r '(if type=="array" then .[0] else . end) | .metadata.pin_awake // ""' 2>/dev/null)"
        if [ "$cns" = "true" ] && [ "$pin" != "true" ]; then
            add_target "$alias"
        fi
    done <<EOF
$cand
EOF
    return 0
}

count_lines() { printf '%s\n' "$1" | awk 'NF { n++ } END { print n + 0 }'; }

# A resolvable city is the floor for both modes: sessions and their beads are in
# the city store, and without it there is nothing to read and nowhere reliable
# to stamp. Refuse rather than storm a doomed exec every tick.
if [ -z "$CITY" ]; then
    if [ "$MODE" = check ]; then
        say "$PROG check: cannot resolve the city (env chain empty and \`gc service list\` gave none) — SKIP."
        [ "$FORCE" -eq 0 ] && { spend_window "$(date -u +%s)" || true; }
        DECIDED=1
        exit 1
    fi
    say "$PROG exec: cannot resolve the city — cannot pin. ABORTED."
    DECIDED=1
    exit 1
fi

NOW="$(date -u +%s)"

if [ "$MODE" = check ]; then
    # Cooldown: the answer on almost every tick, before any gc read.
    if [ "$FORCE" -eq 0 ] && [ -f "$STAMP" ]; then
        LAST="$(cat "$STAMP" 2>/dev/null)"
        case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
        ELAPSED=$((NOW - LAST))
        if [ "$LAST" -gt 0 ] && [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt "$INTERVAL" ]; then
            DECIDED=1
            exit 1
        fi
    fi
    # Refuse to run without a writable stamp: with no cadence floor this check
    # would dispatch a pass on every dispatch tick.
    STAMP_WRITABLE=0
    if ( mkdir -p "$STATE_DIR" 2>/dev/null && : > "$STAMP.probe" 2>/dev/null ); then
        { [ ! -e "$STAMP" ] || [ -f "$STAMP" ]; } && STAMP_WRITABLE=1
    fi
    rm -f "$STAMP.probe" 2>/dev/null || true
    if [ "$STAMP_WRITABLE" -eq 0 ]; then
        say "$PROG check: CANNOT WRITE the cooldown stamp at $STAMP — refusing to run rather than dispatch every tick. pin-keepalive is OFF until the state dir is writable."
        DECIDED=1
        exit 1
    fi

    enumerate_targets
    if [ "$ENUM_STATUS" != "ok" ]; then
        say "$PROG check — city $CITY · window $STAMP"
        say "  roster/session probe UNREADABLE ($ENUM_STATUS) — a probe that cannot be read excludes nothing."
        say "RUN: cannot prove every standing conversational session is pinned."
        DECIDED=1
        exit 0
    fi
    N="$(count_lines "$TARGETS")"
    say "$PROG check — city $CITY · provider $PROVIDER · window $STAMP"
    if [ "$N" -gt 0 ]; then
        say "  unpinned standing conversational named session(s): $(printf '%s' "$TARGETS" | tr '\n' ' ')"
        say "RUN: $N session(s) owe a pin."
        DECIDED=1
        exit 0
    fi
    say "SKIP: every standing conversational named session is pinned — no pass."
    if [ "$FORCE" -eq 0 ]; then
        spend_window "$NOW" || say "  WARN: cannot stamp the cadence window at $STAMP — the next tick reclassifies."
    fi
    DECIDED=1
    exit 1
fi

# --- exec -------------------------------------------------------------------
# Stamp at pass start, so a crash mid-pass still leaves a cadence floor. The
# single-flight order-tracking bead already bars a second concurrent exec.
if [ "$DRY_RUN" -eq 0 ]; then
    spend_window "$NOW" || say "$PROG exec: WARN: cannot stamp the cadence window at $STAMP"
fi

enumerate_targets
if [ "$ENUM_STATUS" = "list_fail" ]; then
    say "$PROG exec: session roster UNREADABLE — cannot pin. ABORTED."
    DECIDED=1
    exit 1
fi

PINNED=0
FAILED=0
while IFS= read -r alias; do
    [ -n "$alias" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then
        say "$PROG exec: DRY-RUN would pin $alias"
        continue
    fi
    if bounded gc session pin "$alias" "${CITY_FLAG[@]}" >/dev/null 2>&1; then
        say "$PROG exec: pinned $alias"
        PINNED=$((PINNED + 1))
    else
        say "$PROG exec: FAILED to pin $alias"
        FAILED=$((FAILED + 1))
    fi
done <<EOF
$TARGETS
EOF

say "$PROG exec: pinned $PINNED, failed $FAILED (probe_status=$ENUM_STATUS)"
DECIDED=1
exit 0
