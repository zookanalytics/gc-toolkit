#!/usr/bin/env bash
# upstream-gc-sync.sh — read-only drift detector for the vendored gastown pack.
#
# Walks agents/*/PROVENANCE.md in the current pack root, finds entries with
# Status: vendored, parses each Source line for the rig-relative path and
# commit pin, and asks the gascity rig what's changed between the pin and
# an upstream tip (default: origin/main). Emits a markdown report on stdout.
#
# Read-only: never mutates PROVENANCE files, never bumps pins, never touches
# vendored content. Pin-bump and apply are follow-up tools (v2). Pack-level
# (non-agent) drift is surfaced under "uncovered drift" for the same reason.
#
# Exit code 0 on a clean run regardless of drift count. Non-zero only on
# operational failures (rig path missing, ref unreachable, malformed args).

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: upstream-gc-sync.sh [options]

Detect upstream drift in the vendored gastown pack. Run from a pack root
that contains agents/*/PROVENANCE.md.

Options:
  --rig-path <path>     Path to the upstream rig checkout
                        (default: gc rig path gascity)
  --upstream-ref <ref>  Ref to compare each pin against
                        (default: origin/main)
  --with-diff           Include unified diffs per agent (verbose)
  -h, --help            Show this help

Exit 0 on clean run regardless of drift count.
EOF
}

RIG_PATH=""
UPSTREAM_REF="origin/main"
WITH_DIFF=0

while [ $# -gt 0 ]; do
    case "$1" in
        --rig-path)
            [ $# -ge 2 ] || { echo "ERROR: --rig-path requires a value" >&2; exit 2; }
            RIG_PATH="$2"; shift 2 ;;
        --upstream-ref)
            [ $# -ge 2 ] || { echo "ERROR: --upstream-ref requires a value" >&2; exit 2; }
            UPSTREAM_REF="$2"; shift 2 ;;
        --with-diff)
            WITH_DIFF=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [ -z "$RIG_PATH" ]; then
    if ! RIG_PATH=$(gc rig path gascity 2>/dev/null); then
        echo "ERROR: 'gc rig path gascity' failed; pass --rig-path explicitly." >&2
        exit 2
    fi
fi

if [ ! -d "$RIG_PATH" ]; then
    echo "ERROR: rig path does not exist: $RIG_PATH" >&2
    exit 2
fi

if ! git -C "$RIG_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: not a git checkout: $RIG_PATH" >&2
    exit 2
fi

if [ ! -d agents ]; then
    echo "ERROR: no agents/ directory in $(pwd); run from a pack root." >&2
    exit 2
fi

# PROVENANCE Source lines in the gc-toolkit pack are workspace-relative,
# prefixed with rigs/gascity/. Strip that to get the rig-relative path.
GASCITY_PREFIX="rigs/gascity/"

# Pack-level subtrees that PROVENANCE.md doesn't cover. Listed for the
# "uncovered drift" tail of the report so v2 knows what to handle.
PACK_BASE="examples/gastown/packs/gastown"
PACK_NON_AGENT_PATHS=(
    "$PACK_BASE/pack.toml"
    "$PACK_BASE/embed.go"
    "$PACK_BASE/formulas"
    "$PACK_BASE/orders"
    "$PACK_BASE/assets"
    "$PACK_BASE/commands"
    "$PACK_BASE/doctor"
    "$PACK_BASE/overlay"
    "$PACK_BASE/template-fragments"
)

if ! UPSTREAM_TIP=$(git -C "$RIG_PATH" rev-parse --short "$UPSTREAM_REF" 2>/dev/null); then
    echo "ERROR: cannot resolve $UPSTREAM_REF in $RIG_PATH" >&2
    exit 2
fi

# Parallel arrays keep ordering deterministic (sorted by directory iteration).
declare -a vendored_names=()
declare -a vendored_paths=()
declare -a vendored_pins=()

for prov in agents/*/PROVENANCE.md; do
    [ -f "$prov" ] || continue
    agent_name=$(basename "$(dirname "$prov")")

    status_line=$(grep -m1 '^\*\*Status:\*\*' "$prov" || true)
    status=$(printf '%s' "$status_line" \
        | sed -E 's/^\*\*Status:\*\*[[:space:]]+//; s/[[:space:]].*$//')
    if [ "$status" != "vendored" ]; then
        continue
    fi

    # Source line shape: **Source:** `<path>` @ gascity `<pin>`
    source_line=$(grep -m1 '^\*\*Source:\*\*' "$prov" || true)
    if [ -z "$source_line" ]; then
        echo "WARN: $prov: vendored agent missing Source line" >&2
        continue
    fi

    src_path=$(printf '%s' "$source_line" | awk -F'`' '{print $2}')
    pin=$(printf '%s' "$source_line" | awk -F'`' '{print $4}')

    if [ -z "$src_path" ] || [ -z "$pin" ]; then
        echo "WARN: $prov: could not parse Source: $source_line" >&2
        continue
    fi

    rel_path="${src_path#"$GASCITY_PREFIX"}"
    rel_path="${rel_path%/}"

    vendored_names+=("$agent_name")
    vendored_paths+=("$rel_path")
    vendored_pins+=("$pin")
done

count=${#vendored_names[@]}
generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat <<EOF
# Gastown vendor drift report

**Generated:** $generated_at
**Upstream rig:** $RIG_PATH
**Upstream ref:** $UPSTREAM_REF (tip $UPSTREAM_TIP)
**Vendored agents found:** $count

EOF

drift_total=0

if [ "$count" -eq 0 ]; then
    echo "_No vendored agents found in agents/*/PROVENANCE.md._"
    echo
else
    for i in "${!vendored_names[@]}"; do
        agent="${vendored_names[$i]}"
        rel="${vendored_paths[$i]}"
        pin="${vendored_pins[$i]}"

        echo "## agent: \`$agent\`"
        echo
        echo "- **Source:** \`$rel\`"
        echo "- **Pin:** \`$pin\`"
        echo "- **Upstream tip:** \`$UPSTREAM_TIP\`"

        if ! git -C "$RIG_PATH" cat-file -e "${pin}^{commit}" 2>/dev/null; then
            echo
            echo "_PIN UNREACHABLE: \`$pin\` not in $RIG_PATH; fetch upstream and retry._"
            echo
            continue
        fi

        log_output=$(git -C "$RIG_PATH" log --oneline "$pin..$UPSTREAM_REF" -- "$rel" 2>/dev/null || true)
        if [ -z "$log_output" ]; then
            commit_count=0
        else
            commit_count=$(printf '%s\n' "$log_output" | wc -l | tr -d ' ')
        fi

        diff_files=$(git -C "$RIG_PATH" diff --name-only "$pin..$UPSTREAM_REF" -- "$rel" 2>/dev/null || true)
        if [ -z "$diff_files" ]; then
            file_count=0
        else
            file_count=$(printf '%s\n' "$diff_files" | wc -l | tr -d ' ')
        fi

        echo "- **Commits since pin:** $commit_count"
        echo "- **Changed files:** $file_count"
        echo

        if [ "$commit_count" -eq 0 ]; then
            echo "_Clean — no upstream changes since pin._"
            echo
            continue
        fi

        drift_total=$((drift_total + commit_count))

        echo "### Commits"
        echo
        echo '```'
        printf '%s\n' "$log_output"
        echo '```'
        echo

        diff_stat=$(git -C "$RIG_PATH" diff --stat "$pin..$UPSTREAM_REF" -- "$rel" 2>/dev/null || true)
        if [ -n "$diff_stat" ]; then
            echo "### Diff stat"
            echo
            echo '```'
            printf '%s\n' "$diff_stat"
            echo '```'
            echo
        fi

        if [ "$WITH_DIFF" -eq 1 ]; then
            echo "### Diff"
            echo
            echo '```diff'
            git -C "$RIG_PATH" diff "$pin..$UPSTREAM_REF" -- "$rel" || true
            echo '```'
            echo
        fi
    done
fi

echo "## Uncovered drift (pack-level)"
echo
echo "PROVENANCE.md only covers per-agent paths. These pack-level paths"
echo "drift independently and need a separate sync mechanism (v2)."
echo

if [ "$count" -eq 0 ]; then
    echo "_No vendored agents — cannot infer pack-level pin._"
else
    pack_pin="${vendored_pins[0]}"
    echo "_Pack-level pin (heuristic — first vendored agent's pin): \`$pack_pin\`_"
    echo

    uncovered_total=0
    for path in "${PACK_NON_AGENT_PATHS[@]}"; do
        log_output=$(git -C "$RIG_PATH" log --oneline "$pack_pin..$UPSTREAM_REF" -- "$path" 2>/dev/null || true)
        if [ -z "$log_output" ]; then
            echo "- \`$path\` — clean"
            continue
        fi
        commit_count=$(printf '%s\n' "$log_output" | wc -l | tr -d ' ')
        echo "- \`$path\` — $commit_count commits since \`$pack_pin\`:"
        printf '%s\n' "$log_output" | sed 's/^/    - /'
        uncovered_total=$((uncovered_total + commit_count))
    done

    echo
    echo "_Uncovered total: $uncovered_total commits across pack-level paths._"
fi

echo
echo "---"
echo "_Per-agent drift total: $drift_total commits across $count vendored agents._"
