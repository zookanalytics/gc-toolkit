#!/usr/bin/env bash
# Pack doctor check: refinery + deacon startup discovery covers tiers 2 and 3.
#
# Tier-1 (in-progress wisp) was the historical query and is preserved.
# Tier-2 catches routed work beads with metadata.branch — these arrive when a
# polecat completes work after the inheriting session has already booted from
# the controller-driven respawn (handoff for controller-restartable, the
# chained reset for on-demand named) but before the boot-time tier-1 query
# fired. Without tier-2 the work bead is invisible to the inheriting session
# and sits open until manual nudge. See rigs/gc-toolkit/specs/tk-fyzvk for
# the full diagnostic.
#
# Tier-3 catches open patrol wisps left behind by pour-before-burn
# cycle-recycle, including pathological multi-wisp accumulation from a
# runaway event-watch loop.
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
    # Tier 2: routed work bead query must include --has-metadata-key=branch
    if ! grep -q -- "--has-metadata-key=branch" "$file"; then
        violations+=("$label: missing tier-2 routed-work-bead query (--has-metadata-key=branch)")
    fi
    # Tier 3: open-patrol-wisp adoption must include --type=molecule + --status=open
    if ! grep -E -q -- "(--status=open[^|]*--type=molecule|--type=molecule[^|]*--status=open)" "$file"; then
        violations+=("$label: missing tier-3 open-patrol-wisp query (--status=open --type=molecule)")
    fi
}

check_file "$dir/patches/refinery-prompt.template.md" "patches/refinery-prompt.template.md"
check_file "$dir/patches/deacon-prompt.template.md" "patches/deacon-prompt.template.md"

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery + deacon startup discovery includes tiers 2 and 3"
    exit 0
fi

echo "${#violations[@]} startup-discovery gap(s) — see rigs/gc-toolkit/specs/tk-fyzvk for context"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
