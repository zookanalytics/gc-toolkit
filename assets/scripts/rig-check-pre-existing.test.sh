#!/usr/bin/env bash
# Hermetic test for rig-check-pre-existing.sh, the writer of
# rig_check_pre_existing.<check>: a caller's judgment that a check's failure at
# one commit is red on the base too and carried by a tracker. Proves:
#   - the value names the commit and every tracker, as one JSON object, and
#     reads back as written;
#   - a second write for the same commit adds its trackers, and one for another
#     commit replaces them, so the key always describes one commit;
#   - each check keeps its own key;
#   - a bead that does not read, or a write that does not read back, exits 1;
#   - a check outside test, lint and typecheck, an abbreviated or missing
#     commit, and no tracker are refused before anything is written;
#   - its two callers, extracted verbatim from the formulas, mark the commit
#     they judge on the bead whose readers act on it: the self-review
#     (self-review-pre-existing) the work bead at the worktree's HEAD, and the
#     refinery (refinery-pre-existing-mark) the anchor at the prep worktree's
#     head, or the work bead when it is its own anchor.
# Runs against the harness's stub gc over a JSON store, with real git for the
# callers' commits. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-check-pre-existing-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The callers read their commit from git, which harness_init stubs, so the
# real one is found first.
GIT_DIR_REAL="$(dirname "$(command -v git)")"
# Host signing of commits must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SUT="$TMP/sut"
mk_sut_dir "$SUT" "$HERE/rig-check-pre-existing.sh"
A=0123456789abcdef0123456789abcdef01234567
B=fedcba9876543210fedcba9876543210fedcba98

# value <bead> <check> : the key's value as compact JSON, parsed from the text bd keeps.
value() { jq -c --arg id "$1" --arg k "rig_check_pre_existing.$2" '.[] | select(.id == $id) | .metadata[$k] // empty | if type == "string" then fromjson else . end' "$STUB_STORE"; }
run() { OUT=$(bash "$SUT/rig-check-pre-existing.sh" "$@" 2>&1); RC=$?; }

store '[{"id":"tk-w","status":"open","metadata":{}}]'

echo "# a write names the commit and its trackers"
run --bead tk-w --check test --commit "$A" --trackers "tk-t1 tk-t2"
eq "$RC" 0 "a first write exits 0"
eq "$(value tk-w test)" "{\"commit\":\"$A\",\"trackers\":[\"tk-t1\",\"tk-t2\"]}" "it records the commit and both trackers"
has "$OUT" "records test's fail at $A as pre-existing: tk-t1, tk-t2" "it says what it recorded"

echo "# a second write for the same commit adds its trackers"
run --bead tk-w --check test --commit "$A" --trackers "tk-t3,tk-t1"
eq "$RC" 0 "a second write exits 0"
eq "$(value tk-w test)" "{\"commit\":\"$A\",\"trackers\":[\"tk-t1\",\"tk-t2\",\"tk-t3\"]}" "the trackers are joined, each once"

echo "# a write for another commit replaces the value"
run --bead tk-w --check test --commit "$B" --trackers "tk-t9"
eq "$(value tk-w test)" "{\"commit\":\"$B\",\"trackers\":[\"tk-t9\"]}" "an earlier commit's trackers do not carry over"

echo "# each check keeps its own key"
run --bead tk-w --check lint --commit "$B" --trackers "tk-l1"
eq "$(value tk-w lint)" "{\"commit\":\"$B\",\"trackers\":[\"tk-l1\"]}" "lint has its own value"
eq "$(value tk-w test)" "{\"commit\":\"$B\",\"trackers\":[\"tk-t9\"]}" "…and the test value is unchanged"

echo "# the store does not take it"
STUB_SHOW_FAIL=1 run --bead tk-w --check typecheck --commit "$A" --trackers "tk-x"
eq "$RC" 1 "an unreadable bead exits 1"
eq "$(value tk-w typecheck)" "" "…and nothing is written"
store '[{"id":"tk-w","status":"open","metadata":{}}]'
STUB_DROP_KEYS="tk-w:rig_check_pre_existing.typecheck" run --bead tk-w --check typecheck --commit "$A" --trackers "tk-x"
eq "$RC" 1 "a write that does not read back exits 1"
has "$OUT" "did not read back as written" "…and says so"

echo "# usage is refused before any write"
: > "$STUB_GC_LOG"
for args in \
  "--bead tk-w --check build --commit $A --trackers tk-x" \
  "--bead tk-w --check test --commit ${A:0:12} --trackers tk-x" \
  "--bead tk-w --check test --trackers tk-x" \
  "--bead tk-w --check test --commit $A --trackers ," \
  "--bead tk-w --check test --commit $A --trackers tk-x;rm" \
  "--check test --commit $A --trackers tk-x"; do
  # shellcheck disable=SC2086 # each case is a whitespace-separated argument list
  run $args
  eq "$RC" 2 "usage: $args"
done
eq "$(grep -c 'bd update' "$STUB_GC_LOG")" 0 "no refused call wrote anything"

echo "# the callers, as the formulas ship them"
ROOT="$(cd "$HERE/../.." && pwd)"
# block <toml> <marker> : the marked block, its placeholders filled for check
# lint and trackers tk-t1 and tk-t2.
block() {
  awk -v m="$2" '$0 ~ ("# >>> " m "$") {f = 1; next} $0 ~ ("# <<< " m "$") {f = 0} f' "$ROOT/formulas/$1" \
    | sed -e 's/^CHECK=".*"$/CHECK="lint"/' -e 's/^TRACKERS=".*"$/TRACKERS="tk-t1 tk-t2"/'
}
# The pack the callers find the writer in, and a PATH with the stub gc ahead of
# the real git.
PACK="$TMP/pack"
mk_sut_dir "$PACK/assets/scripts" "$HERE/rig-check-pre-existing.sh"
mkdir -p "$TMP/gconly" "$TMP/city/rigs"
ln -s "$BIN/gc" "$TMP/gconly/gc"
ln -s "$PACK" "$TMP/city/rigs/gc-toolkit"
CALLER_PATH="$TMP/gconly:$GIT_DIR_REAL:$PATH"
REPO="$TMP/rig"
G="$GIT_DIR_REAL/git"
"$G" -c init.defaultBranch=main init -q "$REPO"
"$G" -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
"$G" -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work
"$G" -C "$REPO" worktree add -q --detach "$REPO/.git/gc-refinery-prep" HEAD~1
WORK_HEAD=$("$G" -C "$REPO" rev-parse HEAD)
PREP_HEAD=$("$G" -C "$REPO" rev-parse HEAD~1)
[ -n "$WORK_HEAD" ] && [ -n "$PREP_HEAD" ] && [ "$WORK_HEAD" != "$PREP_HEAD" ] \
  && ok "the fixture rig has a work head and a prep head" || bad "the fixture rig has a work head and a prep head"

block mol-polecat-work.toml self-review-pre-existing > "$TMP/self-review.sh"
[ -s "$TMP/self-review.sh" ] && ok "self-review-pre-existing extracts" || bad "self-review-pre-existing extracts"
store '[{"id":"tk-w","status":"open","metadata":{}}]'
( cd "$REPO" && env PATH="$CALLER_PATH" GC_PACK_DIR="$PACK" WORK_BEAD_ID=tk-w bash "$TMP/self-review.sh" ) >/dev/null 2>&1
eq "$(value tk-w lint)" "{\"commit\":\"$WORK_HEAD\",\"trackers\":[\"tk-t1\",\"tk-t2\"]}" "the self-review marks the work bead at the worktree's HEAD"

block mol-refinery-patrol.toml refinery-pre-existing-mark > "$TMP/refinery.sh"
[ -s "$TMP/refinery.sh" ] && ok "refinery-pre-existing-mark extracts" || bad "refinery-pre-existing-mark extracts"
store '[{"id":"tk-anchor","status":"open","metadata":{}},{"id":"tk-child","status":"open","metadata":{"anchor_bead":"tk-anchor"}},{"id":"tk-fresh","status":"open","metadata":{}}]'
# From a directory outside any repo, as a patrol shell may be, so the rig root
# and the city are the only places the block can find its pieces.
( cd "$TMP" && env PATH="$CALLER_PATH" GC_RIG_ROOT="$REPO" GC_CITY_PATH="$TMP/city" WORK=tk-child bash "$TMP/refinery.sh" ) >/dev/null 2>&1
eq "$(value tk-anchor lint)" "{\"commit\":\"$PREP_HEAD\",\"trackers\":[\"tk-t1\",\"tk-t2\"]}" "the refinery marks a rework child's anchor at the prep worktree's head"
eq "$(value tk-child lint)" "" "…and not the child"
( cd "$TMP" && env PATH="$CALLER_PATH" GC_RIG_ROOT="$REPO" GC_CITY_PATH="$TMP/city" WORK=tk-fresh bash "$TMP/refinery.sh" ) >/dev/null 2>&1
eq "$(value tk-fresh lint)" "{\"commit\":\"$PREP_HEAD\",\"trackers\":[\"tk-t1\",\"tk-t2\"]}" "the refinery marks a work bead that is its own anchor"

echo "---"
echo "rig-check-pre-existing.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
