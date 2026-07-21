#!/usr/bin/env bash
# Pack doctor check: patrol-agent startup discovery is complete and
# ephemeral-aware.
#
#   refinery + deacon — tiers 2 and 3 present (see below)
#   refinery + deacon + witness — every wisp reconcile query is
#                                 ephemeral-aware (--include-infra)
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
# The --include-infra assertion (tk-1waw2) covers a different failure of the
# same reconcile: patrol wisps are ephemeral and live in <store>.wisps, but
# `gc bd list` reads .issues by default. A --type=molecule query without
# --include-infra therefore returns empty even while wisps exist, the agent
# concludes it has no wisp, pours a fresh one, and leaks the prior one on
# every restart. The witness shipped that bug (three leaked wisps observed
# live 2026-06-26); deacon and refinery already comply, so the check locks
# the invariant in for all three.
#
# Post-tk-kdu2v5 the doctrine lives in a single shared fragment file
# (template-fragments/layered-startup-discovery.template.md) with named
# blocks consumed by deacon, refinery, and witness via
# inject_fragments_append. The check inspects each block's region
# separately. The witness block is reconcile-only by design — the witness
# monitors other agents' work rather than receiving branch-bearing work
# beads — so tiers 2 and 3 are not asserted against it.
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

# check_block <define-name> <label> [require_tiers]
# require_tiers=tiers → also assert the tier-2 and tier-3 queries.
check_block() {
    local block_name="$1"
    local label="$2"
    local require_tiers="${3:-}"
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
    if [ "$require_tiers" = "tiers" ]; then
        # Tier 2: routed work bead query must include --has-metadata-key=branch
        if ! printf '%s' "$block" | grep -q -- "--has-metadata-key=branch"; then
            violations+=("$label: missing tier-2 routed-work-bead query (--has-metadata-key=branch)")
        fi
        # Tier 3: open-patrol-wisp adoption must include --type=molecule + --status=open
        if ! printf '%s' "$block" | grep -E -q -- "(--status=open[^|]*--type=molecule|--type=molecule[^|]*--status=open)"; then
            violations+=("$label: missing tier-3 open-patrol-wisp query (--status=open --type=molecule)")
        fi
    fi
    # Ephemeral-awareness: every `gc bd list --type=molecule` reconcile must
    # carry --include-infra or it never sees a wisp. Score fenced code only —
    # the surrounding prose names the same flags while explaining why, and
    # must not read as a violation. Splice backslash continuations so a query
    # wrapped across lines is judged as one command.
    local code joined offenders
    code=$(printf '%s\n' "$block" | awk '
        /^[[:space:]]*```/ { in_fence = !in_fence; next }
        in_fence { print }
    ')
    joined=$(printf '%s\n' "$code" | sed -e :a -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')
    offenders=$(printf '%s\n' "$joined" \
        | grep -- "gc bd list" \
        | grep -- "--type=molecule" \
        | grep -cv -- "--include-infra" || true)
    if [ "${offenders:-0}" -gt 0 ]; then
        violations+=("$label: $offenders wisp query(ies) missing --include-infra (ephemeral wisps are invisible without it)")
    fi
}

check_block "layered-startup-discovery-refinery" "refinery" tiers
check_block "layered-startup-discovery-deacon" "deacon" tiers
check_block "layered-startup-discovery-witness" "witness"

if [ ${#violations[@]} -eq 0 ]; then
    echo "refinery + deacon startup discovery includes tiers 2 and 3; all wisp queries are ephemeral-aware"
    exit 0
fi

echo "${#violations[@]} startup-discovery gap(s) — see rigs/gc-toolkit/specs/tk-fyzvk for context"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
