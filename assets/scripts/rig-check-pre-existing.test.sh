#!/usr/bin/env bash
# Hermetic test for rig-check-pre-existing.sh, the writer of
# rig_check_pre_existing.<check>: a caller's judgment that one recorded fail of
# a check is red on the base too and carried by a tracker. Proves:
#   - the value names the commit, the failed record as `gctk rig <check>
#     --check` prints it, and every tracker, as one JSON object, and reads back
#     as written;
#   - a second write for the same record adds its trackers, and one for another
#     record replaces them: a run at the same commit with another command or
#     another scope, or a fail at another commit, so a judgment never carries
#     over to a run it did not see;
#   - each check keeps its own key;
#   - setup and build, which gctk rig does not record, take the work bead's
#     self_review_setup_build as their record: the mark holds the note of the
#     failed check at that commit, with the command it ran, so a note of
#     another command starts the judgment over, and no gctk call is made;
#   - with no recorded fail of the named commit to mark (a pass, nothing
#     recorded, another commit's fail, no gctk binary), a bead that does not
#     read, or a write that does not read back, it exits 1 and writes nothing;
#   - a check outside test, lint, typecheck, setup and build, an abbreviated
#     or missing commit, no tracker, and a worktree that is not a directory
#     are refused before anything is written;
#   - its two callers, extracted verbatim from the formulas, mark the record
#     they judge on the bead whose readers act on it: the self-review
#     (self-review-pre-existing) the work bead at the worktree's HEAD, and the
#     refinery (refinery-pre-existing-mark) the anchor at the prep worktree's
#     head, or the work bead when it is its own anchor.
# Runs against the harness's stub gc over a JSON store, with real git and the
# gctk built from this checkout for the records. No live city.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rig-check-pre-existing-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The writer and its callers read records and commits through real git, which
# harness_init stubs, so the real one is found first.
GIT_DIR_REAL="$(dirname "$(command -v git)")"
# Host signing of commits must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
harness_init
[ -n "$GCTK_BUILT" ] || { echo "FAIL - $GCTK_BUILD_ERR"; exit 1; }

SUT="$TMP/sut"
mk_sut_dir "$SUT" "$HERE/rig-check-pre-existing.sh"

# The fixture rig: a work commit, and a prep worktree at the base commit, each
# with its own records under the clone's git common directory. A PATH with the
# stub gc ahead of the real git, for the writer and its callers.
mkdir -p "$TMP/gconly"
ln -s "$BIN/gc" "$TMP/gconly/gc"
REAL_PATH="$TMP/gconly:$GIT_DIR_REAL:$PATH"
REPO="$TMP/rig"
G="$GIT_DIR_REAL/git"
"$G" -c init.defaultBranch=main init -q "$REPO"
"$G" -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
"$G" -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work
PREP="$REPO/.git/gc-refinery-prep"
"$G" -C "$REPO" worktree add -q --detach "$PREP" HEAD~1
WORK_HEAD=$("$G" -C "$REPO" rev-parse HEAD)
PREP_HEAD=$("$G" -C "$REPO" rev-parse HEAD~1)
[ -n "$WORK_HEAD" ] && [ -n "$PREP_HEAD" ] && [ "$WORK_HEAD" != "$PREP_HEAD" ] \
  && ok "the fixture rig has a work head and a prep head" || bad "the fixture rig has a work head and a prep head"

# rec <dir> <gctk rig args...> : record a run the way a caller's gate call does.
rec() { local d="$1"; shift; ( cd "$d" && PATH="$REAL_PATH" "$GCTK_BUILT" rig "$@" ) >/dev/null 2>&1; }
# recorded <dir> <check> : the record `--check` prints there.
recorded() { ( cd "$1" && PATH="$REAL_PATH" "$GCTK_BUILT" rig "$2" --check 2>/dev/null ); }
# value <bead> <check> : the key's value as compact JSON with sorted keys, parsed
# from the text bd keeps.
value() { jq -cS --arg id "$1" --arg k "rig_check_pre_existing.$2" '.[] | select(.id == $id) | .metadata[$k] // empty | if type == "string" then fromjson else . end' "$STUB_STORE"; }
# mark <commit> <record> <tracker...> : the value a write is expected to leave.
mark() { local c="$1" r="$2"; shift 2; jq -cSn --arg c "$c" --argjson r "$r" '{commit: $c, record: $r, trackers: $ARGS.positional}' --args "$@"; }
# run <args...> : the writer, from the work tree unless --worktree says otherwise.
run() { OUT=$(cd "$REPO" && PATH="$REAL_PATH" bash "$SUT/rig-check-pre-existing.sh" "$@" 2>&1); RC=$?; }

store '[{"id":"tk-w","status":"open","metadata":{}}]'

echo "# a write names the commit, the failed record and its trackers"
rec "$REPO" test --scope affected --command false
R1=$(recorded "$REPO" test)
eq "$(printf '%s' "$R1" | jq -r '.result + " " + .commit')" "fail $WORK_HEAD" "the fixture records a test fail at the work head"
run --bead tk-w --check test --commit "$WORK_HEAD" --trackers "tk-t1 tk-t2"
eq "$RC" 0 "a first write exits 0"
eq "$(value tk-w test)" "$(mark "$WORK_HEAD" "$R1" tk-t1 tk-t2)" "it records the commit, the record --check reads there, and both trackers"
has "$OUT" "records test's fail at $WORK_HEAD as pre-existing, for the run of 'false' (scope affected): tk-t1, tk-t2" "it says what it recorded, and for which run"

echo "# a second write for the same record adds its trackers"
run --bead tk-w --check test --commit "$WORK_HEAD" --trackers "tk-t3,tk-t1"
eq "$RC" 0 "a second write exits 0"
eq "$(value tk-w test)" "$(mark "$WORK_HEAD" "$R1" tk-t1 tk-t2 tk-t3)" "the trackers are joined, each once"

echo "# a run that replaces the record takes the judgment with it"
rec "$REPO" test --scope affected --command 'exit 3'
R2=$(recorded "$REPO" test)
[ -n "$R2" ] && [ "$R2" != "$R1" ] && ok "a run with another command replaces the record" || bad "a run with another command replaces the record"
run --bead tk-w --check test --commit "$WORK_HEAD" --trackers "tk-t4"
eq "$(value tk-w test)" "$(mark "$WORK_HEAD" "$R2" tk-t4)" "a write for the other command's fail keeps none of the first run's trackers"
rec "$REPO" test --scope full --command 'exit 3'
R3=$(recorded "$REPO" test)
eq "$(printf '%s' "$R3" | jq -r '.scope + " " + .command')" "full exit 3" "a run of the same command with another scope replaces it too"
run --bead tk-w --check test --commit "$WORK_HEAD" --trackers "tk-t5"
eq "$(value tk-w test)" "$(mark "$WORK_HEAD" "$R3" tk-t5)" "…and a write for it starts over as well"

echo "# a write for another commit replaces the value"
rec "$PREP" test --scope affected --command false
RP=$(recorded "$PREP" test)
run --bead tk-w --check test --commit "$PREP_HEAD" --worktree "$PREP" --trackers "tk-t9"
eq "$RC" 0 "a write read in another worktree exits 0"
eq "$(value tk-w test)" "$(mark "$PREP_HEAD" "$RP" tk-t9)" "an earlier commit's trackers do not carry over"

echo "# each check keeps its own key"
rec "$REPO" lint --command false
RL=$(recorded "$REPO" lint)
run --bead tk-w --check lint --commit "$WORK_HEAD" --trackers "tk-l1"
eq "$(value tk-w lint)" "$(mark "$WORK_HEAD" "$RL" tk-l1)" "lint has its own value"
eq "$(value tk-w test)" "$(mark "$PREP_HEAD" "$RP" tk-t9)" "…and the test value is unchanged"

echo "# setup and build: the mark holds the self-review's note"
# note <build result> <build command> : the self-review's note at the work head.
note() { jq -nc --arg c "$WORK_HEAD" --arg b "$1" --arg bc "$2" '{commit: $c, setup: "none", build: $b, setup_command: "", build_command: $bc}'; }
# set_note <note> : the note on tk-w, its other keys kept.
set_note() { jq --arg n "$1" '(.[] | select(.id == "tk-w") | .metadata.self_review_setup_build) = $n' "$STUB_STORE" > "$TMP/store.new" && mv "$TMP/store.new" "$STUB_STORE"; }
N1=$(note fail make)
set_note "$N1"
GCTK_BIN="$TMP/no-gctk" run --bead tk-w --check build --commit "$WORK_HEAD" --trackers "tk-b1"
eq "$RC" 0 "a build mark exits 0, with no gctk binary to call"
eq "$(value tk-w build)" "$(mark "$WORK_HEAD" "$N1" tk-b1)" "it holds the note of the failed build at that commit"
has "$OUT" "records build's fail at $WORK_HEAD as pre-existing, for the run of 'make': tk-b1" "…and names the build command"
run --bead tk-w --check build --commit "$WORK_HEAD" --trackers "tk-b2"
eq "$(value tk-w build)" "$(mark "$WORK_HEAD" "$N1" tk-b1 tk-b2)" "a second write for the same note adds its tracker"
N2=$(note fail 'make all')
set_note "$N2"
run --bead tk-w --check build --commit "$WORK_HEAD" --trackers "tk-b3"
eq "$(value tk-w build)" "$(mark "$WORK_HEAD" "$N2" tk-b3)" "a note of another build command starts the judgment over"
: > "$STUB_GC_LOG"
run --bead tk-w --check setup --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "a setup the note does not record as failed exits 1"
has "$OUT" "notes no setup fail at $WORK_HEAD" "…and says there is nothing to mark"
run --bead tk-w --check build --commit "$PREP_HEAD" --trackers "tk-x"
eq "$RC" 1 "a note at another commit than the one named exits 1"
set_note "$(note pass make)"
run --bead tk-w --check build --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "a note of a build that passed exits 1"
eq "$(grep -c 'bd update' "$STUB_GC_LOG")" 0 "none of them wrote anything"

echo "# no recorded fail of the named commit to mark"
: > "$STUB_GC_LOG"
rec "$REPO" typecheck --command true
run --bead tk-w --check typecheck --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "a recorded pass exits 1"
has "$OUT" "no recorded typecheck fail at $WORK_HEAD" "…and says there is nothing to mark"
run --bead tk-w --check lint --commit "$PREP_HEAD" --worktree "$PREP" --trackers "tk-x"
eq "$RC" 1 "nothing recorded at the commit exits 1"
run --bead tk-w --check lint --commit "$PREP_HEAD" --trackers "tk-x"
eq "$RC" 1 "a fail recorded at another commit than the one named exits 1"
GCTK_BIN="$TMP/no-gctk" run --bead tk-w --check lint --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "no gctk binary to read the record exits 1"
has "$OUT" "no gctk binary" "…and names what is missing"
eq "$(grep -c 'bd update' "$STUB_GC_LOG")" 0 "none of them wrote anything"
eq "$(value tk-w typecheck)" "" "…so typecheck has no value"

echo "# the store does not take it"
rec "$REPO" typecheck --command false
STUB_SHOW_FAIL=1 run --bead tk-w --check typecheck --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "an unreadable bead exits 1"
eq "$(value tk-w typecheck)" "" "…and nothing is written"
store '[{"id":"tk-w","status":"open","metadata":{}}]'
STUB_DROP_KEYS="tk-w:rig_check_pre_existing.typecheck" run --bead tk-w --check typecheck --commit "$WORK_HEAD" --trackers "tk-x"
eq "$RC" 1 "a write that does not read back exits 1"
has "$OUT" "did not read back as written" "…and says so"

echo "# usage is refused before any write"
: > "$STUB_GC_LOG"
for args in \
  "--bead tk-w --check format --commit $WORK_HEAD --trackers tk-x" \
  "--bead tk-w --check test --commit ${WORK_HEAD:0:12} --trackers tk-x" \
  "--bead tk-w --check test --trackers tk-x" \
  "--bead tk-w --check test --commit $WORK_HEAD --trackers ," \
  "--bead tk-w --check test --commit $WORK_HEAD --trackers tk-x;rm" \
  "--bead tk-w --check test --commit $WORK_HEAD --trackers tk-x --worktree $TMP/missing" \
  "--check test --commit $WORK_HEAD --trackers tk-x"; do
  # shellcheck disable=SC2086 # each case is a whitespace-separated argument list
  run $args
  eq "$RC" 2 "usage: $args"
done
eq "$(grep -c 'bd update' "$STUB_GC_LOG")" 0 "no refused call wrote anything"

echo "# the callers, as the formulas ship them"
ROOT="$(cd "$HERE/../.." && pwd)"
# block <toml> <marker> : the marked block, its placeholders filled for check
# lint and trackers tk-t1 and tk-t2, and the binding the pour renders.
block() {
  awk -v m="$2" '$0 ~ ("# >>> " m "$") {f = 1; next} $0 ~ ("# <<< " m "$") {f = 0} f' "$ROOT/formulas/$1" \
    | sed -e 's/^CHECK=".*"$/CHECK="lint"/' -e 's/^TRACKERS=".*"$/TRACKERS="tk-t1 tk-t2"/' \
          -e 's/{{binding_prefix}}/gc-toolkit./g'
}
# The pack the callers find the writer in, and the refinery's block finds
# rig-root.sh in to resolve the rig, which the stub gc names.
PACK="$TMP/pack"
mk_sut_dir "$PACK/assets/scripts" "$HERE/rig-check-pre-existing.sh" "$HERE/rig-root.sh"

block mol-polecat-work.toml self-review-pre-existing > "$TMP/self-review.sh"
[ -s "$TMP/self-review.sh" ] && ok "self-review-pre-existing extracts" || bad "self-review-pre-existing extracts"
store '[{"id":"tk-w","status":"open","metadata":{}}]'
( cd "$REPO" && env PATH="$REAL_PATH" STUB_PACK="$PACK" WORK_BEAD_ID=tk-w bash "$TMP/self-review.sh" ) >/dev/null 2>&1
eq "$(value tk-w lint)" "$(mark "$WORK_HEAD" "$RL" tk-t1 tk-t2)" "the self-review marks lint's record at the worktree's HEAD on the work bead"

block mol-refinery-patrol.toml refinery-pre-existing-mark > "$TMP/refinery.sh"
[ -s "$TMP/refinery.sh" ] && ok "refinery-pre-existing-mark extracts" || bad "refinery-pre-existing-mark extracts"
rec "$PREP" lint --command false
RPL=$(recorded "$PREP" lint)
store '[{"id":"tk-anchor","status":"open","metadata":{}},{"id":"tk-child","status":"open","metadata":{"anchor_bead":"tk-anchor"}},{"id":"tk-fresh","status":"open","metadata":{}}]'
# From a directory outside any repo, as a patrol shell may be, so the rig root
# names the rig, gc names the pack, and the cwd lends the block nothing.
( cd "$TMP" && env PATH="$REAL_PATH" GC_RIG_ROOT="$REPO" STUB_PACK="$PACK" WORK=tk-child bash "$TMP/refinery.sh" ) >/dev/null 2>&1
eq "$(value tk-anchor lint)" "$(mark "$PREP_HEAD" "$RPL" tk-t1 tk-t2)" "the refinery marks the prep worktree's lint record on a rework child's anchor"
eq "$(value tk-child lint)" "" "…and not the child"
( cd "$TMP" && env PATH="$REAL_PATH" GC_RIG_ROOT="$REPO" STUB_PACK="$PACK" WORK=tk-fresh bash "$TMP/refinery.sh" ) >/dev/null 2>&1
eq "$(value tk-fresh lint)" "$(mark "$PREP_HEAD" "$RPL" tk-t1 tk-t2)" "the refinery marks a work bead that is its own anchor"

echo "---"
echo "rig-check-pre-existing.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
