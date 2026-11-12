#!/usr/bin/env bash
# Hermetic test for refinery-prep.sh, the refinery patrol's rebase step. Runs
# the real script, with the real detached-job.sh and refinery-requeue.sh,
# against real git repositories (refinery-test-lib.sh). Proves:
#   - a branch behind its target takes a merge of the target in a tree of the
#     refinery's own under its home, at worktrees/<bead>, which records the
#     branch and the commit the prep read on it, and the home's own HEAD never
#     moves;
#   - a branch that already carries its target is the prepared head as it
#     stands, with no merge;
#   - a merge that conflicts is aborted and sent back to the pool through the
#     requeue, with the reason "Conflicts with <target> at <commit>", and the
#     tree is removed;
#   - a target or a branch origin does not carry parks the bead behind a human
#     gate, with merge_result=blocked, still assigned to the refinery;
#   - a tree an earlier iteration left is removed before the next is staged;
#   - a bead not assigned to this refinery, or with no branch, is not prepared.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-prep-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-prep.sh refinery-requeue.sh detached-job.sh
}
run() { OUT=$("$SUT/refinery-prep.sh" "$@" 2>&1); RC=$?; }
held() { git -C "$HOME_DIR/worktrees/$1" for-each-ref --format='%(refname:strip=3) %(objectname)' refs/worktree/refinery/ 2>/dev/null; }

echo "# a branch behind its target takes a merge of the target in the refinery's tree"
fresh
READ=$(branch_with polecat/a a.txt)
work a polecat/a
MAIN=$(main_with later.txt)
HOME_HEAD=$(git -C "$HOME_DIR" rev-parse HEAD)
run --bead a
eq "$RC" 0 "the prep exits 0"
TREE="$HOME_DIR/worktrees/a"
[ -f "$TREE/a.txt" ] && [ -f "$TREE/later.txt" ] && rt_ok "the tree holds the branch's work and the target's" || rt_bad "the tree holds the branch's work and the target's"
eq "$(git -C "$TREE" rev-parse HEAD^1) $(git -C "$TREE" rev-parse HEAD^2)" "$READ $MAIN" "the prepared head merges the target into the commit read"
eq "$(held a)" "polecat/a $READ" "the tree records the branch and the commit the prep read on it"
eq "$(git -C "$HOME_DIR" rev-parse HEAD)" "$HOME_HEAD" "the home's own HEAD never moves"
eq "$(git -C "$HOME_DIR" status --porcelain --untracked-files=no)" "" "…and its tracked files are untouched"

echo "# a branch that already carries its target is the prepared head as it stands"
fresh
READ=$(branch_with polecat/b b.txt)
work b polecat/b
run --bead b
eq "$RC" 0 "the prep exits 0"
eq "$(git -C "$HOME_DIR/worktrees/b" rev-parse HEAD)" "$READ" "no merge commit is made"
has "$OUT" "already carries main" "it says the branch already carries the target"

echo "# a merge that conflicts goes back to the pool with the conflict reason"
fresh
branch_with polecat/c same.txt >/dev/null
work c polecat/c
git -C "$SEED" checkout -q main && git -C "$SEED" pull -q origin main
printf 'base side\n' > "$SEED/same.txt" && git -C "$SEED" add same.txt && git -C "$SEED" commit -q -m "same on main" && git -C "$SEED" push -q origin main
MAIN=$(tip main)
run --bead c
eq "$RC" 3 "the prep says the work went back (exit 3)"
eq "$(meta c rejection_reason)" "Conflicts with main at $MAIN" "the reason names the target and its commit"
eq "$(bassignee c)" "" "the bead goes back unassigned"
has "$(logged gc)" "sling --rig rig-a rig-a/gc-toolkit.polecat c --on mol-polecat-work" "it is slung on mol-polecat-work"
[ ! -e "$HOME_DIR/worktrees/c" ] && rt_ok "the tree is removed" || rt_bad "the tree is removed"
grep -q "worktrees/c$" <<< "$(git -C "$RIG" worktree list --porcelain)" && rt_bad "git still lists the tree" || rt_ok "git lists no tree for it"

echo "# a target origin does not carry parks the bead behind a gate"
fresh
branch_with polecat/t t.txt >/dev/null
work t polecat/t '{"target":"integration/gone"}'
run --bead t
eq "$RC" 4 "the prep parks (exit 4)"
has "$(logged scripts)" "human-gate --subject t --key refinery-target-missing" "the gate is keyed refinery-target-missing"
eq "$(meta t merge_result)" "blocked" "the bead records blocked"
eq "$(bassignee t)" "$GC_AGENT" "…and stays with the refinery, held by its gate"
STUB_HUMAN_GATE_RC=1 run --bead t
eq "$RC" 1 "a gate that does not land parks nothing (exit 1)"

echo "# a branch origin does not carry parks the bead behind a gate"
fresh
work g polecat/gone
run --bead g
eq "$RC" 4 "the prep parks (exit 4)"
has "$(logged scripts)" "human-gate --subject g --key refinery-branch-missing" "the gate is keyed refinery-branch-missing"

echo "# a tree an earlier iteration left is removed before the next is staged"
fresh
branch_with polecat/old old.txt >/dev/null
branch_with polecat/new new.txt >/dev/null
work old polecat/old
work new polecat/new
run --bead old
eq "$RC" 0 "the first prep exits 0"
printf 'scratch\n' > "$HOME_DIR/worktrees/old/left-behind.txt"
run --bead new
eq "$RC" 0 "the next prep exits 0"
[ ! -e "$HOME_DIR/worktrees/old" ] && rt_ok "the earlier tree, dirty, is removed" || rt_bad "the earlier tree, dirty, is removed"
[ -d "$HOME_DIR/worktrees/new" ] && rt_ok "the new tree is staged" || rt_bad "the new tree is staged"

echo "# a bead not assigned to this refinery, or with no branch, is not prepared"
fresh
branch_with polecat/z z.txt >/dev/null
work z polecat/z '{}' open "rig-a/gc-toolkit.polecat-1"
run --bead z
eq "$RC" 1 "a bead another agent holds is not prepared"
[ ! -e "$HOME_DIR/worktrees/z" ] && rt_ok "no tree is staged for it" || rt_bad "no tree is staged for it"
put '{"id":"nb","title":"No branch","status":"open","assignee":"rig-a/gc-toolkit.refinery","issue_type":"task","notes":"","metadata":{}}'
run --bead nb
eq "$RC" 1 "a bead with no branch is not prepared"
run
eq "$RC" 2 "no bead is usage"

echo
echo "refinery-prep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
