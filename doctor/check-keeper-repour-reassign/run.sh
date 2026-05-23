#!/usr/bin/env bash
# Pack doctor check: gascity-keeper re-pours-to-pool use `--reassign`
# on the sling.
#
# When the mol-upstream-gc-rebase polecat dispatches a focused rework or
# escalates via conflict_questions, it parks the work bead with
# `assignee=$REQUESTING_KEEPER` and `gc.routed_to=$REQUESTING_KEEPER`.
# The keeper later re-pours via `gc sling <pool> <bead> --on ...`. `gc
# sling` stamps `gc.routed_to` but does NOT clear `assignee` by default,
# so without `--reassign` the pool reconciler sees a stale claim, skips
# the bead, and the rebase strands.
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
# before `--reassign` cannot silently slip past this check. An
# expected-count assertion guards against drift in either direction: a
# removed site would pass the per-site loop vacuously, and a new site
# would pass the per-site loop locally but escape the audit until
# someone notices.
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
# per-site `--reassign` discipline holds at the new site.
EXPECTED_SITES=2

# For every re-pour sling site in $1, print "<head_line>\t<joined_cmd>".
# A site is a logical shell command whose JOINED text
# (line-continuations folded in) matches the placeholder-bead +
# concrete-mol discriminator. Returning the joined text lets the caller
# check `--reassign` without re-walking the file, which is robust to
# future edits that move the flag onto a different physical line.
find_repour_sites() {
    awk '
        function check_logical_line(    ok) {
            ok = (cmd ~ /gc sling [^ ]+\/gc-toolkit\.polecat <bead>/) \
              && (cmd ~ /--on mol-/)
            if (ok) print start "\t" cmd
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

check_reassign_on_repour() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        violations+=("$label: missing file $file")
        return
    fi

    local sites found
    sites=$(find_repour_sites "$file")
    if [ -z "$sites" ]; then
        found=0
    else
        found=$(printf '%s\n' "$sites" | wc -l | tr -d ' ')
    fi

    if [ "$found" -ne "$EXPECTED_SITES" ]; then
        violations+=("$label: expected $EXPECTED_SITES keeper re-pour sling sites, found $found. Site discovery is stale OR a sling site was added/removed; update EXPECTED_SITES in this script and verify each site carries --reassign")
        return
    fi

    while IFS=$'\t' read -r line_no cmd; do
        [ -z "$line_no" ] && continue
        if ! echo "$cmd" | grep -qE -- '(^|[[:space:]])--reassign([[:space:]]|$)'; then
            violations+=("$label:$line_no: re-pour sling without '--reassign' flag (parked-assignee race; see tk-1h9ipf)")
        fi
    done <<< "$sites"
}

check_reassign_on_repour \
    "$dir/packs/gascity-keeper/agents/keeper/prompt.template.md" \
    "gascity-keeper/keeper/prompt.template.md"

if [ ${#violations[@]} -eq 0 ]; then
    echo "keeper re-pours-to-pool use --reassign on the sling"
    exit 0
fi

echo "${#violations[@]} parked-assignee race violation(s) in keeper prompt"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
