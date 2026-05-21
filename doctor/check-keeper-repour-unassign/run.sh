#!/usr/bin/env bash
# Pack doctor check: gascity-keeper re-pours-to-pool clear the parked
# assignee before slinging.
#
# When the mol-upstream-gc-rebase polecat dispatches a focused rework or
# escalates via conflict_questions, it parks the work bead with
# `assignee=$REQUESTING_KEEPER` and `gc.routed_to=$REQUESTING_KEEPER`.
# The keeper later re-pours via `gc sling <pool> <bead> --on ...`. `gc
# sling` stamps `gc.routed_to` but does NOT clear `assignee`, so without
# an explicit `gc bd update <bead> --assignee ""` the pool reconciler
# sees a stale claim, skips the bead, and the rebase strands.
#
# Discriminator: re-pour slings use the `<bead>` placeholder + a concrete
# mol name (`--on mol-...`). Initial-dispatch slings use a shell-var
# (`"$BEAD"`) that was just populated by `gc bd create`; those don't have
# a stale assignee to clear and are out of scope. The Communication
# quick-reference at the foot of the prompt uses `<bead> --on <mol>`
# (placeholder mol) and is also out of scope.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
violations=()

check_unassign_before_repour() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        violations+=("$label: missing file $file")
        return
    fi
    local sling_lines
    sling_lines=$(grep -nE 'gc sling [^ ]+/gc-toolkit\.polecat <bead> --on mol-' "$file" | cut -d: -f1)
    if [ -z "$sling_lines" ]; then
        return
    fi
    while IFS= read -r line_no; do
        local start=$((line_no - 10))
        if [ "$start" -lt 1 ]; then start=1; fi
        local window
        window=$(sed -n "${start},${line_no}p" "$file")
        if ! echo "$window" | grep -qE -- '--assignee +""'; then
            violations+=("$label:$line_no: re-pour sling without preceding '--assignee \"\"' (parked-assignee race; see tk-1h9ipf)")
        fi
    done <<< "$sling_lines"
}

check_unassign_before_repour \
    "$dir/packs/gascity-keeper/agents/keeper/prompt.template.md" \
    "gascity-keeper/keeper/prompt.template.md"

if [ ${#violations[@]} -eq 0 ]; then
    echo "keeper re-pours-to-pool clear the parked assignee before sling"
    exit 0
fi

echo "${#violations[@]} parked-assignee race violation(s) in keeper prompt"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
