#!/usr/bin/env bash
# Pack doctor check: the deferred-dispatch mechanism stays wired end to end.
#
# WHAT IT GUARDS (tk-y0ygs). `gc sling` pours immediately and reads no `blocks`
# deps, so a dispatch that must wait for other work used to be held by an agent
# remembering not to sling yet — state about the work living outside the bead,
# invisible to everyone else, lost when the session died.
# `deferred-dispatch.sh arm` moves that record onto the bead;
# `orders/deferred-dispatch.toml` is the cadence that performs it.
#
# Both halves are needed and only one of them is visible when it breaks. `arm`
# writes its record and reports success whether or not anything consumes it, so
# a missing order, a non-executable script, or an exec path that drifted off the
# script's name produces a bead that looks correctly armed and a dispatch that
# never happens. Nothing else in the city reports that: the bead is open,
# unassigned, unrouted and blocked-looking — indistinguishable from work nobody
# has gotten to. That silence is exactly the failure the mechanism was built to
# remove, which is why the wiring is checked rather than assumed.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
script="$dir/assets/scripts/deferred-dispatch.sh"
order="$dir/orders/deferred-dispatch.toml"
errors=()

# --- the arm/reconcile half --------------------------------------------------
if [ ! -s "$script" ]; then
    errors+=("missing script: assets/scripts/deferred-dispatch.sh")
else
    [ -x "$script" ] || errors+=("assets/scripts/deferred-dispatch.sh is not executable — the order runs it by path")
    for verb in arm disarm list reconcile; do
        grep -qE "^[[:space:]]*$verb\)" "$script" \
            || errors+=("deferred-dispatch.sh: no '$verb' verb — the documented surface is arm/disarm/list/reconcile")
    done
    # Readiness must come from bd, not from a private re-implementation of the
    # blocking-dependency rules. A copy here would drift away from the predicate
    # every other reader uses, and drift means slinging blocked work.
    grep -q -- '--ready' "$script" \
        || errors+=("deferred-dispatch.sh: no '--ready' read — readiness must be asked of bd, not re-implemented")
fi

# --- the cadence half --------------------------------------------------------
if [ ! -s "$order" ]; then
    errors+=("missing order: orders/deferred-dispatch.toml — without it an armed dispatch is a record nobody performs")
else
    grep -q '^\[order\]' "$order" || errors+=("orders/deferred-dispatch.toml: no [order] block")
    grep -qE '^trigger *= *"cooldown"' "$order" \
        || errors+=("orders/deferred-dispatch.toml: trigger is not cooldown")
    grep -qE '^scope *= *"rig"' "$order" \
        || errors+=("orders/deferred-dispatch.toml: scope is not rig — one registration per store, and the per-rig single-flight gate depends on it")
    grep -qE '^no_work_gate' "$order" \
        && errors+=("orders/deferred-dispatch.toml: no_work_gate opts out of the open-work gates, and the first of them IS the single-flight guarantee against two slinging writers")

    # The exec line must actually reach the shipped script. A rename that
    # updates one side only retires the cadence silently.
    exec_line="$(grep -E '^exec *= *"' "$order" | head -1)"
    case "$exec_line" in
        *"assets/scripts/deferred-dispatch.sh"*) : ;;
        "") errors+=("orders/deferred-dispatch.toml: no exec line") ;;
        *)  errors+=("orders/deferred-dispatch.toml: exec does not point at assets/scripts/deferred-dispatch.sh ($exec_line)") ;;
    esac
    case "$exec_line" in
        *"deferred-dispatch.sh reconcile"*) : ;;
        *) [ -n "$exec_line" ] && errors+=("orders/deferred-dispatch.toml: exec does not run the 'reconcile' verb — any other verb makes the cadence a no-op") ;;
    esac

    # `timeout` must stay under order-tracking-sweep's --stale-after (10m in
    # core): that sweep closes a tracking bead it judges stale, and an un-gated
    # tracking bead is a second dispatch — here, a second slinging writer.
    tmo="$(grep -E '^timeout *= *"' "$order" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    case "$tmo" in
        "") errors+=("orders/deferred-dispatch.toml: no timeout — a wedged pass must be killed before order-tracking-sweep retires its single-flight gate") ;;
        *s) [ "${tmo%s}" -lt 600 ] 2>/dev/null || errors+=("orders/deferred-dispatch.toml: timeout $tmo is not below order-tracking-sweep's 10m --stale-after") ;;
        *m) [ "${tmo%m}" -lt 10 ] 2>/dev/null || errors+=("orders/deferred-dispatch.toml: timeout $tmo is not below order-tracking-sweep's 10m --stale-after") ;;
        *)  errors+=("orders/deferred-dispatch.toml: timeout '$tmo' is not a plain Ns/Nm duration this check can compare") ;;
    esac
fi

if [ "${#errors[@]}" -gt 0 ]; then
    echo "deferred-dispatch is not wired end to end: an armed dispatch would be recorded and never performed"
    printf '  - %s\n' "${errors[@]}"
    exit 2
fi

echo "OK: deferred-dispatch ships both halves — arm/reconcile script and the rig-scoped cooldown order that performs it"
exit 0
