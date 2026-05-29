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
# Post-tk-kdu2v5 the doctrine lives in a single shared fragment file
# (template-fragments/layered-startup-discovery.template.md) with two
# named blocks consumed by deacon and refinery via inject_fragments_append.
# The check inspects each block's region separately.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
fragment="$dir/template-fragments/layered-startup-discovery.template.md"
violations=()

if [ ! -f "$fragment" ]; then
    echo "1 startup-discovery gap(s) — see rigs/gc-toolkit/specs/tk-fyzvk for context"
    echo "template-fragments/layered-startup-discovery.template.md: missing fragment file"
    exit 2
fi

check_block() {
    local block_name="$1"
    local label="$2"
    # Extract the block content between `{{ define "block_name" }}` and `{{ end }}`.
    local block
    block=$(awk -v name="$block_name" '
        $0 ~ "\\{\\{ *define \"" name "\" *\\}\\}" { capture = 1; next }
        capture && /\{\{ *end *\}\}/ { capture = 0 }
        capture { print }
    ' "$fragment")

    if [ -z "$block" ]; then
        violations+=("$label: missing {{ define \"$block_name\" }} block in template-fragments/layered-startup-discovery.template.md")
        return
    fi
    # Tier 2: routed work bead query must include --has-metadata-key=branch
    if ! printf '%s' "$block" | grep -q -- "--has-metadata-key=branch"; then
        violations+=("$label: missing tier-2 routed-work-bead query (--has-metadata-key=branch)")
    fi
    # Tier 3: open-patrol-wisp adoption must include --type=molecule + --status=open
    if ! printf '%s' "$block" | grep -E -q -- "(--status=open[^|]*--type=molecule|--type=molecule[^|]*--status=open)"; then
        violations+=("$label: missing tier-3 open-patrol-wisp query (--status=open --type=molecule)")
    fi
}

check_block "layered-startup-discovery-refinery" "refinery"
check_block "layered-startup-discovery-deacon" "deacon"

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery + deacon startup discovery includes tiers 2 and 3"
    exit 0
fi

echo "${#violations[@]} startup-discovery gap(s) — see rigs/gc-toolkit/specs/tk-fyzvk for context"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
