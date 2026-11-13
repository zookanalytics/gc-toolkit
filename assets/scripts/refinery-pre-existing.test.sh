#!/usr/bin/env bash
# Hermetic test for refinery-pre-existing.sh, the refinery's path for a failed
# check already red on the target. Runs the real script against real git
# repositories and a fake gc (refinery-test-lib.sh), with stubs for
# preexisting-failure.sh and rig-check-pre-existing.sh that log their calls.
# Proves:
#   - a failure already tracked is confirmed, nothing is filed, and the tracker
#     is marked on the bead at the prepared head and printed, and the gate's
#     record names the check tracked at that head;
#   - an untracked failure is filed with its key and its evidence, then marked;
#   - a tracked failure the gate's record does not take lands nothing;
#   - a rework child's mark goes on the anchor it names;
#   - a lookup that does not answer, a filing that does not land, or a failure
#     given no evidence lands nothing, and nothing is marked;
#   - a mark that does not land leaves the landing going ahead;
#   - a bead whose branch the refinery's tree does not hold gets no write.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-pre-existing-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

fresh() {
  rm -rf "${TMP:?}"/*
  rt_init refinery-pre-existing.sh
  cat > "$SUT/preexisting-failure.sh" <<'PF'
#!/usr/bin/env bash
echo "preexisting-failure $*" >> "$LOGS/scripts.log"
case "$1" in
  key) echo "$3" ;;
  find) [ -z "${PF_FIND_RC:-}" ] || exit "$PF_FIND_RC"; echo "${PF_FOUND:-}" ;;
  file) [ -z "${PF_FILE_RC:-}" ] || exit "$PF_FILE_RC"; printf '%s\n' "$4" > "$LOGS/filed.txt"; echo "tk-filed" ;;
esac
PF
  chmod +x "$SUT/preexisting-failure.sh"
  branch_with polecat/a a.txt >/dev/null
  work a polecat/a
  prepared a polecat/a
  HEAD_A=$(git -C "$HOME_DIR/worktrees/a" rev-parse HEAD)
}
run() { OUT=$(printf '%s\n' "${EVIDENCE-FAIL: TestFoo (pkg/x)}" | "$SUT/refinery-pre-existing.sh" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

echo "# a failure already tracked is confirmed and marked"
fresh
PF_FOUND=tk-old run --bead a --check test --test TestFoo
eq "$RC" 0 "the path exits 0, so the landing goes ahead"
eq "$OUT" "tk-old" "it prints the tracker"
hasnt "$(logged scripts)" "preexisting-failure file" "nothing is filed"
has "$(logged scripts)" "rig-check-pre-existing --bead a --check test --commit $HEAD_A --worktree $HOME_DIR/worktrees/a --trackers tk-old" "the tracker is marked on the bead at the prepared head"
eq "$(cat "$(gate_dir)/tracked")" "test $HEAD_A" "the gate's record names the check tracked at the prepared head"

echo "# an untracked failure is filed with its evidence, then marked"
fresh
run --bead a --check lint --lint shellcheck assets/scripts/x.sh
eq "$RC" 0 "the path exits 0"
eq "$OUT" "tk-filed" "it prints the new tracker"
has "$(logged scripts)" "preexisting-failure key --lint shellcheck assets/scripts/x.sh" "the key comes from the script"
has "$(cat "$LOGS/filed.txt")" "FAIL: TestFoo (pkg/x)" "the filing carries the evidence"
has "$(cat "$LOGS/filed.txt")" "while the refinery merged a" "…and where it was seen"
has "$(logged scripts)" "--trackers tk-filed" "the new tracker is marked"
eq "$(cat "$(gate_dir)/tracked")" "lint $HEAD_A" "the gate's record names the check filed at the prepared head"

echo "# a rework child's mark goes on its anchor"
fresh
work ch polecat/a '{"task_kind":"rework","anchor_bead":"an"}'
rm -rf "$HOME_DIR/worktrees/a"; git -C "$HOME_DIR" worktree prune
prepared ch polecat/a
PF_FOUND=tk-old run --bead ch --check test --test TestFoo
eq "$RC" 0 "the path exits 0"
has "$(logged scripts)" "rig-check-pre-existing --bead an --check test" "the mark goes on the anchor"

echo "# a lookup, a filing or evidence that is missing lands nothing"
fresh
PF_FIND_RC=1 run --bead a --check test --test TestFoo
eq "$RC" 1 "a lookup that does not answer exits 1"
hasnt "$(logged scripts)" "rig-check-pre-existing" "…and marks nothing"
fresh
PF_FILE_RC=1 run --bead a --check test --test TestFoo
eq "$RC" 1 "a filing that does not land exits 1"
fresh
EVIDENCE="" run --bead a --check test --test TestFoo
eq "$RC" 1 "a failure given no evidence exits 1"
hasnt "$(logged scripts)" "preexisting-failure file" "…and files nothing"

echo "# a tracked failure the gate's record does not take lands nothing"
fresh
mkdir -p "$(gate_dir)/tracked"
PF_FOUND=tk-old run --bead a --check test --test TestFoo
eq "$RC" 1 "the path exits 1, so nothing lands"
has "$ERR" "is tracked as tk-old, but the gate's record of it did not write" "it says the record did not write"
hasnt "$(logged scripts)" "rig-check-pre-existing" "nothing is marked"

echo "# a mark that does not land leaves the landing going ahead"
fresh
PF_FOUND=tk-old STUB_RIG_CHECK_PRE_EXISTING_RC=1 run --bead a --check test --test TestFoo
eq "$RC" 0 "the path still exits 0"
has "$ERR" "the mark on a did not land" "it says the mark did not land"

echo "# a bead whose branch the refinery's tree does not hold gets no write"
fresh
branch_with polecat/b b.txt >/dev/null
work b polecat/b
PF_FOUND=tk-old run --bead b --check test --test TestFoo
eq "$RC" 1 "a bead this iteration did not prepare is refused"
hasnt "$(logged scripts)" "rig-check-pre-existing" "nothing is marked"
run --bead a --check test
eq "$RC" 2 "no failure named is usage"

echo
echo "refinery-pre-existing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
