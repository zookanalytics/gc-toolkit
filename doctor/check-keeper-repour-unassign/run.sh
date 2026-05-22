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
# Site discovery joins shell line-continuations before applying the
# discriminator, so a future prompt edit that wraps the sling command
# before `--on` cannot silently slip past this check. An expected-count
# assertion guards against drift in either direction: a removed site
# would pass the per-site loop vacuously, and a new site would pass the
# per-site loop locally but escape the audit until someone notices.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
violations=()

# Distinct keeper re-pour-to-pool sling sites in the keeper prompt:
#   1. Rebase-in-progress handback (focused-rework re-pour)
#   2. Conflict-questions "skip the commit" path
# If a site is added or removed, bump this counter and confirm the
# per-site `--assignee ""` discipline holds at the new site.
EXPECTED_SITES=2

# Print the line number of every re-pour sling site in $1. A site is a
# logical shell command whose JOINED text (line-continuations folded in)
# matches the placeholder-bead + concrete-mol discriminator. Reporting
# the head line lets the caller window-search backwards for the
# unassign without changing the existing per-site idiom.
find_repour_sites() {
    awk '
        function check_logical_line(    ok) {
            ok = (cmd ~ /gc sling [^ ]+\/gc-toolkit\.polecat <bead>/) \
              && (cmd ~ /--on mol-/)
            if (ok) print start
            cmd = ""
            start = 0
        }
        BEGIN { cmd = ""; start = 0 }
        {
            line = $0
            cont = sub(/\\$/, "", line)
            if (cmd == "") start = NR
            cmd = (cmd == "" ? line : cmd " " line)
            if (!cont) check_logical_line()
        }
        END { if (cmd != "") check_logical_line() }
    ' "$1"
}

check_unassign_before_repour() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        violations+=("$label: missing file $file")
        return
    fi

    local sling_lines found
    sling_lines=$(find_repour_sites "$file")
    if [ -z "$sling_lines" ]; then
        found=0
    else
        found=$(printf '%s\n' "$sling_lines" | wc -l | tr -d ' ')
    fi

    if [ "$found" -ne "$EXPECTED_SITES" ]; then
        violations+=("$label: expected $EXPECTED_SITES keeper re-pour sling sites, found $found. Site discovery is stale OR a sling site was added/removed; update EXPECTED_SITES in this script and verify each site has --assignee \"\"")
        return
    fi

    while IFS= read -r line_no; do
        [ -z "$line_no" ] && continue
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
