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
        */*) errors+=("orders/$1.toml: pool \"$pool\" is rig-qualified — must be BARE (a qualified pool strands the wisp in every importer)") ;;
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

check_order "liveness-sweep" "mol-liveness-sweep"
check_order "triage-recurrence" "mol-triage-recurrence"
check_formula "mol-liveness-sweep.toml"
check_formula "mol-triage-recurrence.toml"
check_recheck

if [ "${#errors[@]}" -eq 0 ]; then
    echo "OK: liveness sweep + triage recurrence wired (orders bare-pool/rig-scope; formulas fail-safe with marked gate-visit copies; claim-time re-check shipped, stamped and hooked)"
    exit 0
fi
echo "liveness machinery mis-wired: ${#errors[@]} problem(s)"
printf '%s\n' "${errors[@]}"
exit 2
