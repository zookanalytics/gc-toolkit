#!/usr/bin/env bash
# Pack doctor check: the P3 liveness machinery is shipped and wired.
#
# P3 (specs/2026-08-fresh-start/operating-principles.md): no idle beads
# — every open bead is worked, gated, conversing, or held-by-design; the
# sweep normalizes the rest into visits, and triage recurrence keeps
# scoped triage conversations alive when warranted. This check guards
# the wiring so the machinery can't be silently un-shipped: both orders
# present with the bare-pool + rig-scope shape (a qualified pool strands
# the wisp in every importer), both formulas present with their
# fail-safe aborts and marked gate-visit copies.
#
# It also guards the CLAIM-TIME re-check (bead tk-gvas6), because that
# half fails silently in a way the others do not: a sweep with no
# re-check still files a perfectly well-formed visit, and the sitting
# reads a census that is hours or days out of date without anything
# saying so. Measured once already — 60% of one body wrong on arrival,
# five of ten candidates merged AND deployed in the 41.5h between the
# pass and the sitting. Three pieces, each useless without the others:
# the script exists and is executable, the sweep stamps the visit, and
# the converse loop runs the stamp.
#
# And it guards the MECHANICAL PRECHECK (bead tk-7h51d), which fails
# silently in the worst way of the three. The liveness-sweep order is
# `condition`-triggered and its check IS that script, so a missing,
# non-executable, mis-named or too-slow precheck makes the check command
# fail — and a failing condition check reads as NOT DUE. The sweep then
# never fires on any rig, with every order, formula and pool still
# perfectly correct and nothing anywhere reporting an error. The two
# numeric guards are the same failure from the other side: an `interval`
# key a condition trigger ignores, and a `check_timeout` below the
# script's own worst case, which kills the check mid-read and reads —
# again — as not due.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
errors=()

check_order() { # name formula trigger
    local f="$dir/orders/$1.toml"
    if [ ! -s "$f" ]; then errors+=("missing order: orders/$1.toml"); return; fi
    grep -q '^\[order\]' "$f" || errors+=("orders/$1.toml: no [order] block")
    grep -qE "^formula *= *\"$2\"" "$f" || errors+=("orders/$1.toml: formula is not \"$2\"")
    grep -qE "^trigger *= *\"$3\"" "$f" || errors+=("orders/$1.toml: trigger is not $3")
    grep -qE '^scope *= *"rig"' "$f" || errors+=("orders/$1.toml: scope is not rig")
    local pool
    pool="$(grep -E '^pool *= *"' "$f" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    case "$pool" in
        */*) errors+=("orders/$1.toml: pool \"$pool\" is rig-qualified — must be BARE (a qualified pool strands the wisp in every importer)") ;;
        "")  errors+=("orders/$1.toml: no pool") ;;
    esac
}

# The sweep's mechanical precheck (bead tk-7h51d). Guarded harder than the rest
# because its failure mode is TOTAL and silent: the order is condition-
# triggered, so if this script is missing, not executable, or not the thing the
# order actually names, the check command simply fails — and a failing condition
# check reads as NOT DUE. The sweep would then never fire again on any rig, with
# every other file in this directory still perfectly correct and nothing
# anywhere saying so.
check_precheck() {
    local s="$dir/assets/scripts/liveness-sweep-precheck.sh"
    local f="$dir/orders/liveness-sweep.toml"
    if [ ! -s "$s" ]; then
        errors+=("missing the sweep precheck: assets/scripts/liveness-sweep-precheck.sh — the liveness-sweep order's check would fail, and a failing condition check reads as NOT DUE, so the sweep would never fire")
        return
    fi
    [ -x "$s" ] || errors+=("assets/scripts/liveness-sweep-precheck.sh is not executable — the order's check would fail on every tick and the sweep would never fire")
    [ -s "$f" ] || return
    grep -qE '^check *= *".*liveness-sweep-precheck\.sh"' "$f" \
        || errors+=("orders/liveness-sweep.toml: its check does not name assets/scripts/liveness-sweep-precheck.sh")
    # A condition trigger IGNORES `interval`, so one here is an inert second
    # copy of the cadence that a later editor would change with no effect. The
    # window lives in LIVENESS_SWEEP_INTERVAL in the script.
    if grep -qE '^interval *= *"' "$f"; then
        errors+=('orders/liveness-sweep.toml: has an `interval` key, which a condition trigger IGNORES — the cadence lives in LIVENESS_SWEEP_INTERVAL in the precheck script, and a second copy here would silently do nothing')
    fi
    # check_timeout must exceed the script's own worst case (three bounded
    # store reads at LIVENESS_SWEEP_CALL_TIMEOUT each, default 45s). A check
    # killed by this deadline reads as not-due — a silent skip — whereas the
    # script's internal bound turns a wedged store into "unreadable" and runs
    # the pass. The per-call bound is read out of the script rather than
    # duplicated here, so raising it there cannot leave this check asserting an
    # inequality that no longer holds.
    local ct call worst
    ct="$(grep -E '^check_timeout *= *"' "$f" | head -1 | sed 's/.*"\([0-9]*\)s".*/\1/')"
    call="$(sed -n 's/^CALL_TIMEOUT="${LIVENESS_SWEEP_CALL_TIMEOUT:-\([0-9]*\)}"/\1/p' "$s" | head -1)"
    case "$call" in
        ''|*[!0-9]*)
            errors+=("assets/scripts/liveness-sweep-precheck.sh: cannot read its CALL_TIMEOUT default — the check_timeout inequality below cannot be verified")
            return ;;
    esac
    worst=$(( 3 * call ))
    case "$ct" in
        ''|*[!0-9]*) errors+=("orders/liveness-sweep.toml: no parseable check_timeout — the default is 10s, far below the precheck's worst case, so a slow store would silently never fire the sweep") ;;
        *) [ "$ct" -gt "$worst" ] || errors+=("orders/liveness-sweep.toml: check_timeout ${ct}s does not exceed the precheck's worst case (${worst}s) — a check killed by the deadline reads as NOT DUE, which is the silent skip the precheck exists to prevent") ;;
    esac
}

check_formula() { # file
    local f="$dir/formulas/$1"
    if [ ! -s "$f" ]; then errors+=("missing formula: formulas/$1"); return; fi
    grep -q 'FAIL-SAFE' "$f" || errors+=("formulas/$1: fail-safe abort clause missing")
    grep -q '# >>> gate-visit' "$f" || errors+=("formulas/$1: no marked gate-visit copy")
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import tomllib,sys; tomllib.load(open('$f','rb'))" 2>/dev/null \
            || errors+=("formulas/$1: does not parse as TOML")
    fi
}

check_recheck() {
    local s="$dir/assets/scripts/liveness-recheck.sh"
    local f="$dir/formulas/mol-liveness-sweep.toml"
    local p="$dir/agents/converse/prompt.template.md"
    if [ ! -s "$s" ]; then
        errors+=("missing the claim-time re-check: assets/scripts/liveness-recheck.sh")
    elif [ ! -x "$s" ]; then
        # The converse hook guards on -x, so a non-executable copy is not a
        # loud failure — it is a re-check that silently never runs.
        errors+=("assets/scripts/liveness-recheck.sh is not executable — the converse hook's -x guard would skip it in silence")
    fi
    [ -s "$f" ] && { grep -q '# >>> visit-recheck-stamp' "$f" \
        || errors+=("formulas/mol-liveness-sweep.toml: no marked visit-recheck-stamp block — visits would ship with no re-checkable id lists"); }
    if [ -s "$p" ]; then
        grep -q 'visit.recheck' "$p" \
            || errors+=("agents/converse/prompt.template.md: no visit.recheck hook — nothing runs the re-check at claim time")
    else
        errors+=("missing agents/converse/prompt.template.md")
    fi
}

check_order "liveness-sweep" "mol-liveness-sweep" "condition"
check_order "triage-recurrence" "mol-triage-recurrence" "cooldown"
check_formula "mol-liveness-sweep.toml"
check_formula "mol-triage-recurrence.toml"
check_recheck
check_precheck

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: liveness sweep + triage recurrence wired (orders bare-pool/rig-scope; formulas fail-safe with marked gate-visit copies; claim-time re-check shipped, stamped and hooked; sweep precheck executable and gated with room under its check_timeout)"
    exit 0
fi
echo "liveness machinery mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
