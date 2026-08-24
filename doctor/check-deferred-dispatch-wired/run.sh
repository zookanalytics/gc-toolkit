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


# --- the FEEDER half ---------------------------------------------------------
# Both halves above shipped, worked, and moved nothing (tk-ku1uvv). Measured in
# the gc-toolkit store on 2026-08-24: 252 ready work beads, all unrouted, 51 of
# them over 30 days old and the oldest 123 days, while `deferred-dispatch.sh
# list` correctly reported "no pending dispatches in this store" and the
# dispatcher and polecat pools were ACTIVE on all four rigs. Nothing ever called
# `arm`. That failure is invisible from inside the mechanism — every part of it
# was healthy, and a queue nobody feeds looks exactly like a queue with nothing
# owed. It is the same silence as a missing order, one layer further up.
feeder="$dir/assets/scripts/dispatch-feeder.sh"
feeder_order="$dir/orders/dispatch-feeder.toml"
feeder_test="$dir/assets/scripts/deferred-dispatch.test.sh"

if [ ! -s "$feeder" ]; then
    errors+=("missing script: assets/scripts/dispatch-feeder.sh — without a feeder, arm/reconcile is a machine with an empty hopper, which is the state tk-ku1uvv measured")
else
    [ -x "$feeder" ] || errors+=("assets/scripts/dispatch-feeder.sh is not executable — the order runs it by path")
    for verb in feed status; do
        grep -qE "^[[:space:]]*$verb\)" "$feeder" \
            || errors+=("dispatch-feeder.sh: no '$verb' verb — the documented surface is feed/status")
    done

    # THE defining constraint. The feeder must call the shipped `arm` verb, not
    # sling for itself. Arming keeps two existing fail-closed layers in the
    # path — arm refuses a closed or already-dispatched bead, reconcile refuses
    # one that is held or already routed — and a feeder that slings directly
    # bypasses both while re-implementing a dispatcher that is already written
    # and already tested. It is also the acceptance criterion on the bead.
    #
    # Both directions are asserted against CODE, not prose. This file explains
    # at length why it must not sling, so a grep over the whole text matches
    # the explanation and fails a correct script — a check that cannot survive
    # its own subject documenting itself is one the next author deletes.
    code_only() { grep -v '^[[:space:]]*#' "$1"; }
    code_only "$feeder" | grep -q 'deferred-dispatch.sh' \
        || errors+=("dispatch-feeder.sh: no reference to deferred-dispatch.sh in executable code — the feeder must call the shipped arm verb, not carry its own dispatch path")
    code_only "$feeder" | grep -qE '(ARM_TOOL|deferred-dispatch\.sh)"? arm ' \
        || errors+=("dispatch-feeder.sh: no 'arm' invocation — a feeder that does not arm is not feeding this pipeline")
    if code_only "$feeder" | grep -qE '(^|[^-[:alnum:]_])gc sling'; then
        errors+=("dispatch-feeder.sh: calls 'gc sling' directly — that is a SECOND dispatch path, bypassing arm's refusals (closed, already dispatched) and reconcile's (held, already routed). The feeder arms; orders/deferred-dispatch.toml slings")
    fi

    # Readiness comes from bd, exactly as it does in the reconcile half. A
    # private re-implementation here would drift from the predicate every other
    # reader uses, and drift on THIS side means auto-dispatching blocked work.
    grep -q -- '--ready' "$feeder" \
        || errors+=("dispatch-feeder.sh: no '--ready' read — readiness must be asked of bd, not re-implemented")

    # Oldest first. The 123-day head of the queue is the whole reason this
    # exists; a newest-first or priority-first feeder leaves exactly the beads
    # that motivated it untouched forever, and the bead's acceptance criterion
    # is that the 31d+ bucket strictly decreases.
    grep -q 'sort_by((.created_at' "$feeder" \
        || errors+=("dispatch-feeder.sh: candidates are no longer sorted oldest-created first — the 31d+ tail would starve behind every fresh arrival, which is the exact backlog shape this feeder was built to drain")

    # Bounded BY CONSTRUCTION. An unbounded feeder over a 252-deep queue is a
    # spend incident, not a fix. Both caps are enforced in the script; neither
    # may become a thing a caller is merely asked to pass.
    for knob in DISPATCH_FEEDER_ENABLED DISPATCH_FEEDER_MAX_IN_FLIGHT DISPATCH_FEEDER_MAX_PER_TICK; do
        grep -q "$knob" "$feeder" \
            || errors+=("dispatch-feeder.sh: $knob is gone — the enable flag and both caps are what keep a feeder over a 252-deep queue from being a spend incident, and they must be enforced here rather than asked of a caller")
    done

    # The in-flight cap must be counted from the feeder's OWN marker, never
    # from gc.dispatch_when_ready. Reconcile clears that key the instant it
    # slings, so counting it would drop every dispatched bead out of the tally
    # within one 2m tick and the cap would bind on nothing.
    grep -q 'gc.auto_armed_by' "$feeder" \
        || errors+=("dispatch-feeder.sh: the gc.auto_armed_by marker is gone — if the cap counts gc.dispatch_when_ready instead, reconcile clears that key on dispatch and every in-flight bead leaves the tally within one tick, so the cap binds on nothing")

    # Fail closed, both reads, and for different reasons. An unreadable
    # candidate listing that prints "0 armed" is indistinguishable from a quiet
    # board — the same disappearing-queue failure the reconcile half guards.
    # An unreadable in-flight count read as zero is worse than under-reporting:
    # it hands the pass a full budget and blows the cap.
    grep -q 'NOT treating this as an empty queue' "$feeder" \
        || errors+=("dispatch-feeder.sh: an unreadable candidate listing no longer fails loudly — a feeder that cannot see the queue and prints a zero summary reads exactly like a board with nothing ready, which is how 252 beads aged out unnoticed")
    grep -q 'blow the cap' "$feeder" \
        || errors+=("dispatch-feeder.sh: an unreadable in-flight count no longer refuses — read as 0 it does not merely under-report, it hands the pass a full budget and defeats the cap, which is the one way this file becomes the spend incident it was written to avoid")
fi

# --- the feeder's cadence ----------------------------------------------------
if [ ! -s "$feeder_order" ]; then
    errors+=("missing order: orders/dispatch-feeder.toml — without it nothing calls the feeder and the hopper stays empty")
else
    grep -q '^\[order\]' "$feeder_order" || errors+=("orders/dispatch-feeder.toml: no [order] block")
    grep -qE '^trigger *= *"cooldown"' "$feeder_order" \
        || errors+=("orders/dispatch-feeder.toml: trigger is not cooldown")
    grep -qE '^scope *= *"rig"' "$feeder_order" \
        || errors+=("orders/dispatch-feeder.toml: scope is not rig — the in-flight cap is a PER-RIG cap and a city-scoped registration would apply one budget across every store")
    grep -qE '^(no_work_gate|idempotent)' "$feeder_order" \
        && errors+=("orders/dispatch-feeder.toml: no_work_gate/idempotent opts out of the single-flight gate — two concurrent passes would each read the same in-flight count and each spend the same budget, which is the one way the cap is defeated from outside the script")

    feeder_exec="$(grep -E '^exec *= *"' "$feeder_order" | head -1)"
    case "$feeder_exec" in
        *"assets/scripts/dispatch-feeder.sh"*) : ;;
        "") errors+=("orders/dispatch-feeder.toml: no exec line") ;;
        *)  errors+=("orders/dispatch-feeder.toml: exec does not point at assets/scripts/dispatch-feeder.sh ($feeder_exec)") ;;
    esac
    case "$feeder_exec" in
        *"dispatch-feeder.sh feed"*) : ;;
        *) [ -n "$feeder_exec" ] && errors+=("orders/dispatch-feeder.toml: exec does not run the 'feed' verb — any other verb makes the cadence a no-op and the hopper stays empty") ;;
    esac

    # The knobs must be declared HERE, in [order.env], because that is the
    # surface an operator overrides from city.toml with [[orders.overrides]] +
    # [orders.overrides.env]. Defaults living only inside the script would make
    # tuning tooling spend a pack change, which is exactly what the
    # 2026-08-20..23 spend controls were shaped to avoid.
    grep -q '^\[order.env\]' "$feeder_order" \
        || errors+=("orders/dispatch-feeder.toml: no [order.env] block — the caps and the enable flag must be declared where city.toml can override them, or tuning tooling spend becomes a pack change")
    for knob in DISPATCH_FEEDER_ENABLED DISPATCH_FEEDER_MAX_IN_FLIGHT DISPATCH_FEEDER_MAX_PER_TICK; do
        grep -q "^$knob" "$feeder_order" \
            || errors+=("orders/dispatch-feeder.toml: [order.env] does not declare $knob — an operator reading this file could not find the knob to turn")
    done

    ftmo="$(grep -E '^timeout *= *"' "$feeder_order" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    case "$ftmo" in
        "") errors+=("orders/dispatch-feeder.toml: no timeout — a wedged pass must be killed before order-tracking-sweep retires its single-flight gate and a second arming writer starts") ;;
        *s) [ "${ftmo%s}" -lt 600 ] 2>/dev/null || errors+=("orders/dispatch-feeder.toml: timeout $ftmo is not below order-tracking-sweep's 10m --stale-after") ;;
        *m) [ "${ftmo%m}" -lt 10 ] 2>/dev/null || errors+=("orders/dispatch-feeder.toml: timeout $ftmo is not below order-tracking-sweep's 10m --stale-after") ;;
        *)  errors+=("orders/dispatch-feeder.toml: timeout '$ftmo' is not a plain Ns/Nm duration this check can compare") ;;
    esac
fi

# --- the feeder's regression cases -------------------------------------------
# They live in deferred-dispatch.test.sh rather than a suite of their own: this
# pack has no test discovery, suites are invoked by name, and the feeder cannot
# be reasoned about apart from the arm it calls. A separate file would be a
# suite nobody runs.
if [ ! -s "$feeder_test" ]; then
    errors+=("missing: assets/scripts/deferred-dispatch.test.sh — the feeder guards above would have no executable proof")
else
    grep -q 'FEEDOLDEST' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no oldest-first case — that the 123-day head of the queue is taken before fresh arrivals is unproven, and it is the acceptance criterion")
    grep -q 'FEEDARM' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no arm-not-sling case — that the feeder is a caller of arm rather than a second dispatch path is unproven")
    grep -q 'FEEDCAP' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no in-flight-cap case — the bound that keeps a feeder over a 252-deep queue from being a spend incident is unproven")
    grep -q 'FEEDTICK' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no per-tick-cap case — the backstop against a cold start emptying the queue in one pass is unproven")
    grep -q 'FEEDRESERVE' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no consumed-arm case — that a dispatched bead still holds its slot after reconcile cleared its arm is unproven, and getting it wrong makes the cap bind on nothing")
    grep -q 'FEEDOFF' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no disabled case — that the operator's off switch stops auto-arming AND leaves hand-written arms alone is unproven")
    grep -q 'FEEDEXCL' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no exclusion case — that step beads, convoys, epics, held and already-routed beads are never auto-armed is unproven, and 67 of the 330 live ready beads were formula step beads")
    grep -q 'FEEDBLIND' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no unreadable-queue case — that a feeder which cannot see the queue refuses instead of printing a healthy zero summary is unproven")
    grep -q 'FEEDCOUNT' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no unreadable-cap case — that a broken in-flight count is NOT read as zero in flight is unproven, and that is the one failure that defeats the cap")
    grep -q 'FEEDBADCAP' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no unparseable-knob case — that a typo'd or empty cap refuses instead of silently restoring the default is unproven")
    grep -q 'FEEDROLLBACK' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no failed-arm case — that a refused arm releases the slot it reserved is unproven, and without it every refusal permanently tightens the rig's cap")
    grep -q 'FEEDQUIET' "$feeder_test" \
        || errors+=("deferred-dispatch.test.sh: no quiet-path case — every refusal added above is a chance to break the empty-board pass, which is the pass that runs most of the time")
fi

if [ "${#errors[@]}" -gt 0 ]; then
    echo "deferred-dispatch is not wired end to end: a dispatch would be recorded and never performed, or ready work would never be armed at all"
    printf '  - %s\n' "${errors[@]}"
    exit 2
fi

echo "OK: deferred-dispatch ships all three halves — the arm/reconcile script, the rig-scoped cooldown order that performs it, and the capped feeder that keeps it fed"
exit 0
