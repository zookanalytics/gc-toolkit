#!/usr/bin/env bash
# Pack doctor check: the P3 liveness machinery is shipped and wired.
#
# P3 (operating-principles.md): no idle beads — every open bead is
# worked, gated, conversing, or held-by-design; the sweep normalizes the
# rest into visits, and triage recurrence keeps scoped triage
# conversations alive when warranted. This check guards the wiring so
# the machinery can't be silently un-shipped: both orders present with
# the bare-pool + rig-scope shape (the doc-keeper order's recorded
# lesson — a qualified pool strands the wisp in every importer), both
# formulas present with their fail-safe aborts and marked gate-visit
# copies.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
errors=()

check_order() { # name formula
    local f="$dir/orders/$1.toml"
    if [ ! -s "$f" ]; then errors+=("missing order: orders/$1.toml"); return; fi
    grep -q '^\[order\]' "$f" || errors+=("orders/$1.toml: no [order] block")
    grep -qE "^formula *= *\"$2\"" "$f" || errors+=("orders/$1.toml: formula is not \"$2\"")
    grep -qE '^trigger *= *"cooldown"' "$f" || errors+=("orders/$1.toml: trigger is not cooldown")
    grep -qE '^scope *= *"rig"' "$f" || errors+=("orders/$1.toml: scope is not rig")
    local pool
    pool="$(grep -E '^pool *= *"' "$f" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    case "$pool" in
        */*) errors+=("orders/$1.toml: pool \"$pool\" is rig-qualified — must be BARE (doc-keeper lesson: a qualified pool strands the wisp in every importer)") ;;
        "")  errors+=("orders/$1.toml: no pool") ;;
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

check_order "liveness-sweep" "mol-liveness-sweep"
check_order "triage-recurrence" "mol-triage-recurrence"
check_formula "mol-liveness-sweep.toml"
check_formula "mol-triage-recurrence.toml"

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: liveness sweep + triage recurrence wired (orders bare-pool/rig-scope; formulas fail-safe with marked gate-visit copies)"
    exit 0
fi
echo "liveness machinery mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
