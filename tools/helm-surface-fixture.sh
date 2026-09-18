#!/usr/bin/env bash
# helm-surface-fixture.sh — hermetic assertions for the gc-helm.sh operator
# surface: the WRITE verbs (open, react, takeaway) and the contract that the
# operator's entry point is this runnable script, not a `gc helm` subcommand.
#
# The board itself — its render, ranking, severity bands, and the held glyph —
# is `helm-svc board` (services/helm). Its derivation is proven by
# services/helm/internal/board (derive_test.go) and its CLI render by
# services/helm/cmd/helm-svc (board_test.go, board_render_test.go,
# main_test.go); none of it is driven from here.
#
# What this fixture locks down:
#
#   • verb dispatch + validation — open/react/takeaway routing and the
#     fail-closed arg checks that reject a call before it reaches Dolt;
#   • react wiring — react <id> is a thin front door over
#     tools/gc-proactive.sh `sling`, on the codex-gated mr path;
#   • the operator-surface contract — the script prints its own usage, and no
#     operator-facing surface file advertises a phantom `gc helm` CLI.
#
# HERMETIC BY DESIGN. The write verbs resolve a rig through the tool's
# GC_HELM_FIXTURE hook (a canned rigs.json under a temp dir), and react runs on
# gc-proactive.sh's --dry-run path, so these assertions write NOTHING to Dolt
# and need no live city. An OPT-IN takeaway round-trip (GC_HELM_SMOKE_BEAD=<id>)
# exercises the live write path on a bead the operator chooses — the fixture
# never invents or closes a bead of its own.
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
# stands in for `gc rig list`); react reads it to rig-qualify its pool target.
cat > "$FXDIR/rigs.json" <<'JSON'
[{"name":"gc-toolkit","path":"/tmp/fx-gc-toolkit","prefix":"tk"}]
JSON

echo "── hermetic: verb dispatch + fail-closed validation ──"
has  "help lists the open verb"  "open"  "$("$TOOL" help 2>&1 || true)"
ec=0; "$TOOL" open 2>/dev/null || ec=$?;            eq "open with no bead errors (exit 2)"        "2" "$ec"
ec=0; "$TOOL" bogus-verb 2>/dev/null || ec=$?;      eq "unknown verb errors (exit 2)"             "2" "$ec"
# takeaway: a thin metadata-writer verb; bead-id AND text
# are BOTH required — missing either fails closed (exit 2). Whitespace-only text
# counts as missing (it collapses to empty before the check).
ec=0; "$TOOL" takeaway 2>/dev/null || ec=$?;        eq "takeaway with no bead errors (exit 2)"    "2" "$ec"
ec=0; "$TOOL" takeaway tk-x 2>/dev/null || ec=$?;   eq "takeaway with no text errors (exit 2)"    "2" "$ec"
ec=0; "$TOOL" takeaway tk-x "   " 2>/dev/null || ec=$?; eq "takeaway with whitespace-only text errors (exit 2)" "2" "$ec"
has  "help lists the takeaway verb" "takeaway"           "$("$TOOL" help 2>&1 || true)"
has  "usage documents takeaway"     "takeaway <bead-id>" "$("$TOOL" --help 2>&1 || true)"
# --release is a recognized boolean flag on takeaway. Probe it WITHOUT a bead so
# the parse-level error (missing bead-id) proves the flag was consumed — not
# rejected as unknown — and no Dolt write is reached. The usage advertises it.
REL_OUT="$("$TOOL" takeaway --release 2>&1 || true)"
has    "takeaway --release is a recognized flag (not unknown)" "needs <bead-id>" "$REL_OUT"
absent "takeaway --release is not rejected as unknown"         "unknown flag"    "$REL_OUT"
has    "usage documents the takeaway --release flag"           "--release"       "$("$TOOL" --help 2>&1 || true)"
# The retired --note flag is now an UNKNOWN flag (takeaway is takeaway-only).
NOTE_OUT="$("$TOOL" takeaway tk-x sometext --note whatever 2>&1 || true)"
has    "the retired takeaway --note flag is now rejected as unknown" "unknown flag" "$NOTE_OUT"

echo "── hermetic: react is the front-door over gc-proactive.sh sling (mr path, codex-gated) ──"
# react <id> is a THIN wrapper over tools/gc-proactive.sh `sling` — it owns no
# sling logic. Driven through the REAL gc-proactive.sh on its --dry-run path
# (GC_PROACTIVE_FIXTURE makes that path echo the resolved command instead of
# calling gc), so this proves the WIRING end-to-end: react → sling → files a
# reaction bead tracking the subject, routed to the proactive pool.
PROACTIVE_TOOL_REAL="$HERE/gc-proactive.sh"
if [ -x "$PROACTIVE_TOOL_REAL" ]; then
    RX="$(GC_RIG=gc-toolkit GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
          GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
    has    "react files a reaction bead"              "gc bd create"                    "$RX"
    has    "react stamps the reaction subject"        "gc.reaction_subject"             "$RX"
    absent "react no longer pins a merge path"        "--merge"                         "$RX"
    has    "react targets the rig-qualified pool"     "gc-toolkit/gc-toolkit.proactive" "$RX"
    has    "react passes the bead through to sling"   "tk-epic"                         "$RX"
    # --reason is accepted as operator intent but NOT forwarded (sling has none).
    RXR="$(GC_RIG=gc-toolkit GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
           GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --reason "pick a backend" --dry-run 2>&1 || true)"
    has    "react surfaces the operator --reason"     "pick a backend"                  "$RXR"
    absent "react does NOT forward --reason to sling" "--reason"                        "$RXR"
    # Regression (tk-82g33): react must SELF-SUPPLY GC_RIG so the sling can
    # rig-qualify its pool target even from a GC_RIG-less shell — the NORMAL
    # operator path (the prefix+b board picker and a bare shell both lack it).
    # The assertions above pre-set GC_RIG=gc-toolkit, which MASKS the bug by
    # letting resolve_pool_target read it from the environment; here we DROP it
    # with `env -u GC_RIG` and prove react derives gc-toolkit from the tk- bead's
    # own rig. The fixture's rigs.json already maps tk→gc-toolkit, so no fixture
    # data change is needed. "rig-qualify" is the fail-closed die() phrase —
    # asserting it absent proves the guard never fired.
    RXNR="$(env -u GC_RIG GC_PROACTIVE_TOOL="$PROACTIVE_TOOL_REAL" GC_PROACTIVE_FIXTURE="$FXDIR" \
            GC_HELM_FIXTURE="$FXDIR" "$TOOL" react tk-epic --dry-run 2>&1 || true)"
    has    "react self-supplies the rig (no GC_RIG → still rig-qualified)" \
           "gc-toolkit/gc-toolkit.proactive" "$RXNR"
    has    "react (no GC_RIG) still files a reaction bead"     "gc bd create"            "$RXNR"
    has    "react (no GC_RIG) still stamps the subject"        "gc.reaction_subject"     "$RXNR"
    has    "react (no GC_RIG) passes the bead through"         "tk-epic"                 "$RXNR"
    absent "react (no GC_RIG) never hits the fail-closed guard" "rig-qualify"            "$RXNR"
else
    printf '  skip  react→sling wiring (gc-proactive.sh not found at %s)\n' "$PROACTIVE_TOOL_REAL"
fi
# Dispatch + fail-closed validation for the new verb.
ec=0; "$TOOL" react 2>/dev/null || ec=$?;  eq "react with no bead errors (exit 2)" "2" "$ec"
has "help lists the react verb"  "react"            "$("$TOOL" help 2>&1 || true)"
has "usage documents react"      "react <bead-id>"  "$("$TOOL" --help 2>&1 || true)"

echo "── contract: operator surface is the runnable script, not a phantom gc subcommand ──"
# The regression this guards (PR #100 review): the docs/prompt advertised a
# `gc helm …` CLI that was never registered, so a bare invocation renders
# root gc help. Pack commands bind under the pack name (`gc <pack> <cmd>`), so
# no top-level helm subcommand can exist. The runnable surface is THIS
# script — reached via the prefix+b tmux picker (tmux-pick-helm.sh →
# gc-helm.sh) or run directly. These
# assertions lock the operator-facing docs to that reality.

# (a) the documented script entry actually runs and prints its own usage.
has  "script --help prints usage" "Usage:" "$("$TOOL" --help 2>&1 || true)"
has  "script -h prints usage"     "Usage:" "$("$TOOL" -h 2>&1 || true)"

# (b) no operator-facing surface file advertises the phantom CLI. The match is
#     the space-form ("gc helm …", incl. backtick-wrapped); the real
#     script name "gc-helm" (hyphen) is intentionally NOT matched.
SURFACE_FILES=(
    "$HERE/../assets/scripts/gc-helm.sh"
    "$HERE/../agents/converse/prompt.template.md"
    "$HERE/../agents/converse/agent.toml"
    "$HERE/../agents/converse/PROVENANCE.md"
)
phantom=""
for f in "${SURFACE_FILES[@]}"; do
    [ -f "$f" ] || continue
    hit="$(grep -nF 'gc helm' "$f" 2>/dev/null || true)"
    [ -n "$hit" ] && phantom+="$f: $hit"$'\n'
done
absent "no operator surface file advertises a phantom 'gc helm' CLI" "gc helm" "$phantom"

# ---------------------------------------------------------------------------
# Best-effort LIVE smokes (skipped cleanly when no city / gc is reachable).
# ---------------------------------------------------------------------------
# Opt-in: a takeaway + takeaway --release round-trip on
# an operator-chosen bead. The fixture never invents or closes a bead — it writes
# only to the bead the operator named, and every leg self-cleans (the unset
# undoes takeaway; the --release leg captures and restores the
# bead's prior lifecycle fields and unsets the marker it set).
if [ -n "${GC_HELM_SMOKE_BEAD:-}" ]; then
    echo "── live (opt-in): takeaway + takeaway --release round-trip on $GC_HELM_SMOKE_BEAD ──"
    bead="$GC_HELM_SMOKE_BEAD"
    # takeaway: write the headline, read back the THREE metadata fields, then
    # unset them (the clean-up leg — takeaway has no inverse verb).
    "$TOOL" takeaway "$bead" "helm-surface-fixture smoke takeaway" --by host >/dev/null 2>&1 \
        && ok "takeaway $bead" || bad "takeaway $bead" "exit 0" "non-zero"
    eq "bead now carries the gc.takeaway headline" "helm-surface-fixture smoke takeaway" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    eq "bead now carries gc.takeaway_by=host" "host" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway_by"] // ""')"
    eq "bead now carries a non-empty gc.takeaway_at stamp" "true" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '(.[0].metadata["gc.takeaway_at"] // "") != ""')"
    gc bd update "$bead" --unset-metadata gc.takeaway --unset-metadata gc.takeaway_at --unset-metadata gc.takeaway_by >/dev/null 2>&1 \
        && ok "unset the smoke takeaway (cleanup)" || bad "unset the smoke takeaway" "exit 0" "non-zero"
    eq "bead no longer carries gc.takeaway" "" \
        "$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    # --release leg: ONE call stamps the takeaway AND releases the bead (reopen,
    # unassign, clear route, mark reacted). Capture the prior lifecycle fields so
    # we can restore them — unlike the takeaway-only leg above, --release mutates
    # status/assignee/route.
    PRIOR_STATUS="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].status // "open"')"
    PRIOR_ASSIGNEE="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].assignee // ""')"
    PRIOR_ROUTE="$(gc bd show "$bead" --json 2>/dev/null | jq -r '.[0].metadata["gc.routed_to"] // ""')"
    "$TOOL" takeaway "$bead" "helm-surface-fixture release smoke" --by proactive --release --no-wait >/dev/null 2>&1 \
        && ok "takeaway --release $bead" || bad "takeaway --release $bead" "exit 0" "non-zero"
    RELJSON="$(gc bd show "$bead" --json 2>/dev/null)"
    eq "release stamps the gc.takeaway headline"      "helm-surface-fixture release smoke" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.takeaway"] // ""')"
    eq "release attributes the takeaway to proactive" "proactive" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.takeaway_by"] // ""')"
    eq "release reopens the bead (status=open)"       "open" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].status // ""')"
    eq "release clears the assignee"                  "" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].assignee // ""')"
    eq "release clears the pool route (gc.routed_to)" "" \
        "$(printf '%s' "$RELJSON" | jq -r '.[0].metadata["gc.routed_to"] // ""')"
    # Restore the prior lifecycle fields + unset the smoke takeaway.
    gc bd update "$bead" --status="$PRIOR_STATUS" --assignee="$PRIOR_ASSIGNEE" \
        --set-metadata gc.routed_to="$PRIOR_ROUTE" \
        --unset-metadata gc.takeaway --unset-metadata gc.takeaway_at --unset-metadata gc.takeaway_by >/dev/null 2>&1 \
        && ok "restore lifecycle + unset the release smoke (cleanup)" || bad "restore the release smoke" "exit 0" "non-zero"
else
    printf '  skip  live takeaway round-trip (set GC_HELM_SMOKE_BEAD=<id> to run)\n'
fi

echo ""
echo "helm-surface-fixture: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
