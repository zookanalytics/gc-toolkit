#!/usr/bin/env bash
# Pack doctor check: refinery's two pickup paths reject rebase beads.
#
# A bead poured on mol-upstream-gc-rebase (or its sibling rework mol)
# requires `git push --force-with-lease HEAD:main`, which refinery
# MUST NOT do (the "NEVER force-push to main/master" rule is absolute).
# If a rebase bead ever leaks into refinery's assignee scan, the rebase
# polecat's terminal push step is bypassed and refinery escalates to
# mayor — at best a noisy stall, at worst a lost rebase.
#
# This check enforces that both pickup paths carry an explicit
# routing-guard that detects rebase beads (by metadata.molecule_id
# title or metadata.backup_ref) and rejects them before they enter
# the merge flow. The fix is structural defense-in-depth: even if the
# upstream leak source is unknown, refinery never silently absorbs a
# rebase bead.
#
# Context: rigs/gc-toolkit/.beads — see the rebase-routing-leak bead
# for the in-flight gc-j8e7j incident that motivated this check.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
violations=()

check_file() {
    local file="$1"
    local label="$2"
    if [ ! -f "$file" ]; then
        violations+=("$label: missing file $file")
        return
    fi
    # The guard must mention rebase-bead detection via molecule title.
    if ! grep -q "mol-upstream-gc-rebase" "$file"; then
        violations+=("$label: missing rebase-bead routing-guard (no reference to mol-upstream-gc-rebase)")
        return
    fi
    # The guard must check metadata.backup_ref as the durable fallback marker.
    if ! grep -q "backup_ref" "$file"; then
        violations+=("$label: rebase-bead routing-guard missing backup_ref fallback marker")
    fi
    # The guard must reject (not merge) — look for the leak label.
    if ! grep -q -i "ROUTING LEAK" "$file"; then
        violations+=("$label: rebase-bead routing-guard missing reject/leak handling (no ROUTING LEAK label)")
    fi
}

check_file "$dir/patches/refinery-prompt.template.md" "patches/refinery-prompt.template.md"
check_file "$dir/formulas/mol-refinery-patrol.toml" "mol-refinery-patrol.toml"

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery prompt + mol-refinery-patrol guard against rebase-bead routing leaks"
    exit 0
fi

echo "${#violations[@]} rebase-routing-guard gap(s) — refinery could silently absorb a rebase bead"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
