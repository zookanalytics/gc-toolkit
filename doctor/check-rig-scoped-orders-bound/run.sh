#!/usr/bin/env bash
# Pack doctor check: a scope="rig" order is never LIVE with no rig bound.
#
# Background (tk-gi2pc). An order that declares `scope = "rig"` with a BARE
# pool is the deliberate shape for a pack imported by several rigs: the bare
# pool is qualified per importing rig at fire time, so each importer sweeps its
# own store. orders/liveness-sweep.toml says so in its own header, and
# check-liveness-sweep-wired asserts that shape is present.
#
# The shape being CORRECT is not the same as the shape being BOUND. Order
# discovery scans this pack's orders/ twice — once at city scope and once per
# importing rig (gascity internal/orderdiscovery/discovery.go, ScanAll) — and
# the `scope` field is consulted only on the rig pass, where it promotes a
# scope="city" order. On the CITY pass it is not read at all, so a scope="rig"
# order is also registered once with no rig bound. That copy is a strand
# generator, and it fails silently at every step:
#
#   * with no rig, the bare pool cannot be qualified (qualifyPool returns it
#     unchanged), so resolveOrderStoreTarget routes the wisp to the CITY store;
#   * nothing at city scope can claim a bare rig-pool name, so the workflow root
#     sits open, unassigned, and unclaimable until someone closes it by hand;
#   * the order keeps its cooldown, so it re-strands every interval.
#
# That is how mol-liveness-sweep and mol-triage-recurrence went dark for hours
# with every configuration file correct — the two orders had no city.toml
# `enabled = false` override, which is the hand-maintained workaround the
# doc-keeper orders carry. A workaround every new order must remember is the
# failure class this check exists to end: it turns "somebody forgot" into a
# doctor error at the moment the order is added, instead of a silent patrol
# outage discovered days later through session-model findings.
#
# THE DURABLE FIX LANDED — this check is now the regression gate it was
# written to become (gc-xaqpf, closed 2026-08-11). The guard lives where this
# header always said it belonged, in the discovery path rather than this pack:
# gascity internal/orderdiscovery/discovery.go, where ScanAll calls
# dropUnboundRigScoped and removes the city-pass registration for any order
# whose file explicitly declares scope="rig". The patch site and the
# correct-vs-catastrophic detail are written up in
# specs/tk-gi2pc/rig-scoped-order-unbound-firing.md.
#
# SO A GREEN VERDICT IS NOW THE EXPECTED ONE, and the load-time lines it comes
# with are the fix working, not a symptom:
#
#   gc order list: order "liveness-sweep" declares scope = "rig": dropped the
#   unbound city-scope registration nothing could claim (still registered on
#   rig(s) …)
#
# Read that as evidence, not as a normalization hiding the defect from us. The
# drop happens inside ScanAll — the single discovery entry point the FIRING
# path consumes, not a display layer over it — and it is unconditional
# (`OnUnboundRigScoped` is an optional log handler; a nil one still drops).
# Nothing can fire unbound, which is why nothing is left for this check to
# find. It still fails loudly if that guard is ever reverted, because the
# dropped registration would reappear in `gc order list` with an empty rig.
#
# This distinction is not academic: reading those drop lines as a live defect
# is what produced bead tk-0c7tw, which reported the check as "invisible to
# its own condition" when it was simply green for the right reason.
#
# WHAT IS FLAGGED — a LIVE registration with no rig bound whose order file
# declares scope="rig". Two ways an entry is judged, in priority order:
#   1. its own source file, read from disk — this generalizes past our own
#      orders to any order in the city with the same exposure;
#   2. failing that, its name matching one of THIS pack's rig-scoped orders —
#      we know what our own files declare without reading them.
#
# WHAT IS NOT FLAGGED:
#   * A disabled unbound copy. `gc order list` omits disabled orders, so the
#     existing city.toml overrides keep the doc-keeper pair green — the strand
#     is already neutralized there and this check has nothing to add.
#   * A scope="city" order with no rig. That is the whole point of city scope.
#   * An unbound entry from another pack whose source file cannot be read. It
#     is reported in the details and left out of the verdict: we cannot know
#     what it declares, and guessing would make this check cry wolf on packs
#     that ship no on-disk source.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"

# `gc doctor` applies no timeout to pack checks, so an unbounded probe against
# a wedged control plane would hang the whole doctor run.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded
        # call rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

# Does an order FILE declare rig scope? Explicit only. An absent `scope`
# defaults to "rig" in the loader, but an unset field is not a declaration and
# the city-scope copy of such an order may well be intended — flagging it would
# turn every order that never thought about scope into an error.
declares_rig_scope() { # file
    grep -qE '^[[:space:]]*scope[[:space:]]*=[[:space:]]*"rig"' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# This pack's own rig-scoped orders, keyed by name. Used only as the fallback
# when a listed entry's source file cannot be read.
# ---------------------------------------------------------------------------
pack_rig_scoped=""
if [ -d "$dir/orders" ]; then
    for f in "$dir"/orders/*.toml; do
        [ -f "$f" ] || continue
        declares_rig_scope "$f" || continue
        pack_rig_scoped="$pack_rig_scoped$(basename "$f" .toml)
"
    done
else
    # Not fatal, but not silent either: with no orders/ we are not looking at
    # the pack, and the name-key fallback below is unavailable.
    warnings+=("no orders/ directory under GC_PACK_DIR ($dir) — the source-file arm still ran, but this pack's own orders could not be enumerated")
fi

is_pack_rig_scoped() { # name
    printf '%s' "$pack_rig_scoped" | grep -qxF "$1"
}

# ---------------------------------------------------------------------------
# The live registration listing. An unreadable probe is a WARNING, never a
# pass: "we could not tell" and "there is nothing wrong" are different answers,
# and collapsing them is the same fail-open this check was written to remove.
# ---------------------------------------------------------------------------
raw=$(run_bounded gc order list --json 2>/dev/null)
probe_rc=$?

if [ "$probe_rc" -ne 0 ] || [ -z "$raw" ]; then
    echo "cannot determine whether rig-scoped orders are bound"
    echo "\`gc order list --json\` failed (rc=$probe_rc) or returned nothing; re-run once the control plane answers."
    print_lines "${warnings[@]+"${warnings[@]}"}"
    exit 1
fi

if ! printf '%s' "$raw" | jq -e 'type == "object" and (.orders | type == "array")' >/dev/null 2>&1; then
    echo "cannot determine whether rig-scoped orders are bound"
    echo "\`gc order list --json\` returned a payload with no .orders array; the listing shape changed or the output is corrupt."
    print_lines "${warnings[@]+"${warnings[@]}"}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Every LIVE registration with no rig bound, as name<TAB>source.
# ---------------------------------------------------------------------------
unbound=$(printf '%s' "$raw" \
    | jq -r '.orders[]? | select(((.rig // "") | tostring) == "")
             | [(.name // ""), (.source // "")] | @tsv' 2>/dev/null)

while IFS=$'\t' read -r name src; do
    [ -n "$name" ] || continue
    if [ -n "$src" ] && [ -f "$src" ]; then
        if declares_rig_scope "$src"; then
            errors+=("$name: registered with NO rig bound, but $src declares scope = \"rig\" — every fire strands an unclaimable workflow root in the city store")
        fi
        continue
    fi
    if is_pack_rig_scoped "$name"; then
        errors+=("$name: registered with NO rig bound, and this pack ships orders/$name.toml with scope = \"rig\" — every fire strands an unclaimable workflow root in the city store (its listed source ${src:-<none>} was unreadable, so the pack's own file was used)")
        continue
    fi
    [ -n "$src" ] && notes+=("$name: registered with no rig bound; source $src is unreadable, so its declared scope is unknown (not this pack's order — reported, not judged)")
done <<< "$unbound"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "rig-scoped orders firing unbound: ${#errors[@]} order(s)"
    print_lines "${errors[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "Each of these re-strands on its own cooldown. The discovery-path guard that prevents this ALREADY LANDED (gascity internal/orderdiscovery/discovery.go, ScanAll -> dropUnboundRigScoped; gc-xaqpf, written up in specs/tk-gi2pc/rig-scoped-order-unbound-firing.md), so a finding here means that guard was reverted or a newer registration path bypasses it — restore the guard rather than paper over the symptom. Only as an interim stopgap, a deliberate city.toml \`[[orders.overrides]]\` with \`enabled = false\` and no \`rig\` key disables the unbound copy of one named order."
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "rig-scoped order binding partially determined"
    print_lines "${warnings[@]}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "OK: no scope=\"rig\" order is registered with an unbound (city-scope) copy"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
