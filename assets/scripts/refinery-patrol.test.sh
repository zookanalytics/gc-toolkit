#!/usr/bin/env bash
# Hermetic test for refinery-patrol.sh, the refinery patrol's identity check
# and its pour of the next iteration, against a fake gc over a JSON store and
# real git repositories (refinery-test-lib.sh). Proves:
#   - identity passes a set GC_AGENT, and an empty one files a patrol finding
#     keyed refinery-empty-identity and exits 1;
#   - next pours the next wisp root-only with exactly the rig identity the
#     startup pour passes (target_branch, rig_name, binding_prefix), stamps
#     gc.rig, assigns it, then burns the current wisp, found as the newest
#     mol-refinery-patrol assigned to this refinery, or as GC_BEAD_ID;
#   - next removes the trees the iteration left under the refinery's home;
#   - a current wisp that cannot be named pours nothing, and an assign that
#     fails burns the new wisp and keeps the current one;
#   - a pour that yields no wisp assigns and burns nothing, and an assign whose
#     rollback burn also fails still exits 1 with the current wisp kept.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-patrol-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-patrol.sh
}
run() { OUT=$("$SUT/refinery-patrol.sh" "$@" 2>&1); RC=$?; }
wisp() { put "$(jq -nc --arg id "$1" --arg a "$2" --arg c "$3" '{id: $id, title: "mol-refinery-patrol", status: "in_progress", assignee: $a, issue_type: "molecule", created_at: $c, notes: "", metadata: {}}')"; }

echo "# identity"
fresh
run identity
eq "$RC" 0 "a set GC_AGENT passes"
GC_AGENT="" run identity
eq "$RC" 1 "an empty GC_AGENT exits 1"
has "$(logged scripts)" "patrol-finding --scope refinery-findings --key refinery-empty-identity" "…and files a patrol finding"

echo "# next pours the next wisp with the startup pour's vars, assigns it, and burns the current"
fresh
wisp w-old "$GC_AGENT" 2026-11-12T00:00:00Z
wisp w-cur "$GC_AGENT" 2026-11-12T01:00:00Z
wisp w-other rig-b/gc-toolkit.refinery 2026-11-12T03:00:00Z
branch_with polecat/a a.txt >/dev/null
prepared a polecat/a
run next
eq "$RC" 0 "next exits 0"
has "$(logged gc)" "bd mol wisp mol-refinery-patrol --root-only --var target_branch=main --var rig_name=rig-a --var binding_prefix=gc-toolkit. --json" "the pour passes exactly the rig identity"
NEXT=$(jq -r '[ .[] | select(.title == "mol-refinery-patrol" and .id != "w-old" and .id != "w-cur" and .id != "w-other") ][0].id' "$STORE")
eq "$(bassignee "$NEXT") $(meta "$NEXT" gc.rig)" "$GC_AGENT rig-a" "the new wisp is rig-stamped and assigned"
eq "$(bstatus w-cur)" "<absent>" "the current wisp, the newest of this refinery's, is burned"
eq "$(bstatus w-old) $(bstatus w-other)" "in_progress in_progress" "older and other refineries' wisps are left alone"
[ ! -e "$HOME_DIR/worktrees/a" ] && rt_ok "the iteration's tree is removed" || rt_bad "the iteration's tree is removed"
fresh
wisp w-1 "$GC_AGENT" 2026-11-12T00:00:00Z
wisp w-2 "$GC_AGENT" 2026-11-12T01:00:00Z
GC_BEAD_ID=w-1 run next
eq "$(bstatus w-1) $(bstatus w-2)" "<absent> in_progress" "GC_BEAD_ID names the current wisp when set"

echo "# a wisp that cannot be named or assigned keeps the current one"
fresh
run next
eq "$RC" 1 "no current wisp exits 1"
has "$OUT" "the current wisp could not be named" "it says why"
hasnt "$(logged gc)" "mol wisp" "…and pours nothing"
fresh
wisp w-cur "$GC_AGENT" 2026-11-12T01:00:00Z
STUB_UPDATE_FAIL=1 run next
eq "$RC" 1 "an assign that fails exits 1"
eq "$(bstatus w-cur)" "in_progress" "the current wisp is kept"
eq "$(jq '[ .[] | select(.title == "mol-refinery-patrol") ] | length' "$STORE")" "1" "the unassigned new wisp is burned"
fresh
wisp w-cur "$GC_AGENT" 2026-11-12T01:00:00Z
STUB_WISP_FAIL=1 run next
eq "$RC" 1 "a pour that yields no wisp exits 1"
hasnt "$(logged gc)" "bd update" "…assigns nothing"
eq "$(bstatus w-cur)" "in_progress" "…and keeps the current wisp"
fresh
wisp w-cur "$GC_AGENT" 2026-11-12T01:00:00Z
STUB_UPDATE_FAIL=1 STUB_BURN_FAIL=1 run next
eq "$RC" 1 "an assign that fails exits 1 when its rollback burn fails too"
eq "$(bstatus w-cur)" "in_progress" "…keeps the current wisp"
has "$OUT" "the startup reconcile collects it" "…and leaves the new wisp to the startup reconcile"
"$SUT/refinery-patrol.sh" bogus >/dev/null 2>&1; eq "$?" 2 "an unknown verb is usage"

echo
echo "refinery-patrol: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
