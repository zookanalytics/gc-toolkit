#!/usr/bin/env bash
# helm-surface-fixture.sh — hermetic assertions for the gc-helm.sh operator
# surface: the open verb's dispatch and the contract that the operator's entry
# point is this runnable script, not a `gc helm` subcommand.
#
# The board itself is helm-svc's web page (services/helm). Its rig read is
# proven by services/helm/internal/rigboard, its page by services/helm/web
# (src/rigboard/Board.test.tsx), and what `helm-svc board --json` prints by
# services/helm/cmd/helm-svc (board_test.go); none of it is driven from here.
#
# What this fixture locks down:
#
#   • verb dispatch + validation — open's routing and the fail-closed arg
#     checks that reject a call before it reaches Dolt;
#   • the operator-surface contract — the script prints its own usage, and no
#     operator-facing surface file advertises a phantom `gc helm` CLI.
#
# HERMETIC BY DESIGN. The write verbs resolve a rig through the tool's
# GC_HELM_FIXTURE hook (a canned rigs.json under a temp dir), so these
# assertions write NOTHING to Dolt and need no live city.
#
# Run:   tools/helm-surface-fixture.sh
# Exit:  0 iff every hermetic assertion passes.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../assets/scripts/gc-helm.sh"
[ -x "$TOOL" ] || { echo "fixture: $TOOL not executable" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "fixture: jq required" >&2; exit 2; }

FXDIR="$(mktemp -d "${TMPDIR:-/tmp}/gctk-helm-surface-fixture.XXXXXX")"
# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap
cleanup() { rm -rf "$FXDIR"; }
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        expected: [%s]\n        actual:   [%s]\n' "$1" "$2" "$3"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains: $2" "$3" ;; esac; }
absent() { case "$3" in *"$2"*) bad "$1" "absent: $2" "$3" ;; *) ok "$1" ;; esac; }

# The write verbs resolve a bead's rig through GC_HELM_FIXTURE/rigs.json (it
# stands in for `gc rig list`).
cat > "$FXDIR/rigs.json" <<'JSON'
[{"name":"gc-toolkit","path":"/tmp/fx-gc-toolkit","prefix":"tk"}]
JSON

echo "── hermetic: verb dispatch + fail-closed validation ──"
has  "help lists the open verb"  "open"  "$("$TOOL" help 2>&1 || true)"
ec=0; "$TOOL" open 2>/dev/null || ec=$?;            eq "open with no bead errors (exit 2)"        "2" "$ec"
ec=0; "$TOOL" bogus-verb 2>/dev/null || ec=$?;      eq "unknown verb errors (exit 2)"             "2" "$ec"

echo "── contract: operator surface is the runnable script, not a phantom gc subcommand ──"
# The regression this guards (PR #100 review): the docs/prompt advertised a
# `gc helm …` CLI that was never registered, so a bare invocation renders
# root gc help. Pack commands bind under the pack name (`gc <pack> <cmd>`), so
# no top-level helm subcommand can exist. The runnable surface is THIS
# script — run by helm-svc's write routes or run directly. These
# assertions lock the operator-facing docs to that reality.

# (a) the documented script entry actually runs and prints its own usage.
has  "script --help prints usage" "Usage:" "$("$TOOL" --help 2>&1 || true)"
has  "script -h prints usage"     "Usage:" "$("$TOOL" -h 2>&1 || true)"

# (b) no operator-facing surface file advertises the phantom CLI. The match is
#     the space-form ("gc helm …", incl. backtick-wrapped); the real
#     script name "gc-helm" (hyphen) is intentionally NOT matched.
SURFACE_FILES=(
    "$HERE/../assets/scripts/gc-helm.sh"
    "$HERE/../agents/_converse/prompt.template.md"
    "$HERE/../agents/_converse/PROVENANCE.md"
    "$HERE/../agents/converse-claude-opus/agent.toml"
    "$HERE/../agents/converse-claude-fable/agent.toml"
    "$HERE/../agents/converse-codex-sol/agent.toml"
    "$HERE/../agents/converse-codex-astra/agent.toml"
)
phantom=""
missing=""
for f in "${SURFACE_FILES[@]}"; do
    # A surface file that moved would otherwise drop out of the scan unnoticed,
    # and the absent-check below would pass on the files left.
    [ -f "$f" ] || { missing+="$f"$'\n'; continue; }
    hit="$(grep -nF 'gc helm' "$f" 2>/dev/null || true)"
    [ -n "$hit" ] && phantom+="$f: $hit"$'\n'
done
eq "every operator surface file the scan names exists" "" "$missing"
absent "no operator surface file advertises a phantom 'gc helm' CLI" "gc helm" "$phantom"

echo ""
echo "helm-surface-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
