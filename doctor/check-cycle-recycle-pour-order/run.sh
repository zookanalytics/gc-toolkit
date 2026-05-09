#!/usr/bin/env bash
# Pack doctor check: cycle-recycle exit obeys "pour next before burn current".
#
# Every formula exit path obeys "pour next iteration before burning the
# current one" except, historically, cycle-recycle. This check enforces that
# wherever `gc handoff` appears in a cycle-recycle context, a `gc bd mol wisp`
# (NEXT pour) appears before it within the same code block. See
# rigs/gc-toolkit/specs/tk-fyzvk for the full diagnostic and rigs/gc-toolkit/
# specs/tk-6hm32 for the v3-vs-v4 placement decision.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
violations=()

# check_pour_before_handoff <file> <label>
#
# For each `gc handoff` occurrence in the file, walk back up to 40 lines
# and assert a `gc bd mol wisp` poured a NEXT wisp first. The window is
# generous enough to cover the surrounding shell block but tight enough
# that a far-away unrelated `mol wisp` (e.g. an example earlier in the
# file) won't satisfy the check spuriously.
check_pour_before_handoff() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        violations+=("$label: missing file $file")
        return
    fi
    local handoff_lines
    handoff_lines=$(grep -n "gc handoff " "$file" | cut -d: -f1)
    if [ -z "$handoff_lines" ]; then
        # No handoff in this file — nothing to enforce.
        return
    fi
    while IFS= read -r line_no; do
        local start=$((line_no - 40))
        if [ "$start" -lt 1 ]; then start=1; fi
        local window
        window=$(sed -n "${start},${line_no}p" "$file")
        # Pour-marker patterns we accept:
        #   1. `NEXT=$(... gc bd mol wisp ...)` — explicit NEXT capture, formula-style
        #   2. `gc bd mol wisp ... --root-only` — bare pour line, template-style
        if ! echo "$window" | grep -E -q "(NEXT=.*gc bd mol wisp|gc bd mol wisp .*--root-only)"; then
            violations+=("$label:$line_no: gc handoff without preceding 'gc bd mol wisp' pour (pour-before-burn violation)")
        fi
    done <<< "$handoff_lines"
}

check_pour_before_handoff "$dir/template-fragments/cycle-recycle.template.md" "cycle-recycle.template.md"
check_pour_before_handoff "$dir/formulas/mol-refinery-patrol.toml" "mol-refinery-patrol.toml"
check_pour_before_handoff "$dir/formulas/mol-witness-patrol.toml" "mol-witness-patrol.toml"
check_pour_before_handoff "$dir/formulas/mol-deacon-patrol.toml" "mol-deacon-patrol.toml"

if [ ${#violations[@]} -eq 0 ]; then
    echo "cycle-recycle pours next wisp before handoff in all patrol formulas"
    exit 0
fi

echo "${#violations[@]} pour-before-burn violation(s) — see rigs/gc-toolkit/specs/tk-fyzvk"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
