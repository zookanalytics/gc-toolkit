#!/usr/bin/env bash
# Test for self-review-check.sh — the exit condition of the self-review check
# loop in mol-polecat-work.
#
# It EXECUTES the real shipped script against the compiled fake gc, as gc and
# as the bd the script calls itself, over a store each case writes, the
# run-lib.sh stub (the run of the root each case names), a real fixture git
# worktree, and the real `gctk` built from this checkout, whose records the
# cases write by running `gctk rig` in the fixture the way an iteration does. So
# the exit-code contract (0 verified-green, 75 for a read the script could not
# make, 1 for every other state), the record reads and the exhaustion note are
# pinned against the code that ships, not a paraphrase.
set -uo pipefail

TMP="$(mktemp -d "${TMPDIR:-/tmp}/self-review-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
HERE="$(cd "$(dirname "$0")" && pwd)"
# The fixture worktree and gctk rig run the real git, which harness_init puts
# beneath the harness's git stub and the test floor's refusal.
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_build_gctk
[ -n "$GCTK_BUILT" ] || { echo "FAIL - $GCTK_BUILD_ERR"; exit 1; }
harness_init
ln -sf "$REAL_GIT" "$BIN/git"
# The script reads and writes through bd itself, which the fake answers under
# that name.
ln -s gc "$BIN/bd"
# The runs file each case writes answers run-lib.sh, not the runs of the store.
unset RUN_LIB_STUB_CMD
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
SCRIPT="$HERE/self-review-check.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }
CALLS="$STUB_GC_LOG"

# --- fixture repo ------------------------------------------------------------
WT="$TMP/worktree"
mkdir -p "$WT"
git -C "$WT" init -q
git -C "$WT" config user.email t@example.com
git -C "$WT" config user.name  Test
echo base > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm base
echo more > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm work
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)
OLD_SHA=$(git -C "$WT" rev-parse HEAD~1)
# The step's note of setup and build at <commit>, as rig-checks.sh writes it:
# setup <s>, build <b>, the build command [bc], default make, and the setup
# command [sc], default none.
noted() {
  printf '{"commit":%s,"setup":%s,"build":%s,"setup_command":%s,"build_command":%s}' \
    "$(json_str "$1")" "$(json_str "$2")" "$(json_str "$3")" "$(json_str "${5-}")" "$(json_str "${4-make}")"
}
# Unless a case says otherwise, setup and build passed at HEAD.
SB_GREEN=$(noted "$HEAD_SHA" none pass)
# A second worktree of the same clone, at HEAD~1, and a third at HEAD: records
# live under the clone's git common directory, which every worktree shares.
git -C "$WT" worktree add -q --detach "$TMP/old" "$OLD_SHA"
git -C "$WT" worktree add -q --detach "$TMP/twin" "$HEAD_SHA"

# record <dir> <check> <gctk rig args...> : write a record the way an
# iteration does, by running the check through gctk rig in <dir>.
record() { local d="$1"; shift; ( cd "$d" && "$GCTK_BUILT" rig "$@" ) >/dev/null 2>&1; }
# green [dir] : test, lint and typecheck each pass at <dir>'s HEAD (default the
# fixture worktree); typecheck as a rig that declares no command for it.
green() {
  local d="${1:-$WT}"
  record "$d" test --scope affected --command true
  record "$d" lint --command true
  record "$d" typecheck --nothing-declared
}
clear_records() { rm -rf "${WT:?}/.git/gc-rig-checks"; }
# recorded <check> : the record `--check` prints at the fixture worktree's HEAD.
recorded() { ( cd "$WT" && "$GCTK_BUILT" rig "$1" --check 2>/dev/null ); }
# go_json_str <text> : the text as a JSON string the way gctk writes it, Go's
# encoder, which escapes <, > and & as well as what json_str escapes.
go_json_str() {
  local j; j=$(json_str "$1")
  j="${j//</\\u003c}"; j="${j//>/\\u003e}"; j="${j//&/\\u0026}"
  printf '%s' "$j"
}
# premark <commit> <record> [tracker...] : a pre-existing mark, in the shape
# rig-check-pre-existing.sh writes.
premark() {
  local c="$1" r="$2" t trackers=""; shift 2
  for t in "$@"; do trackers+="${trackers:+,}$(json_str "$t")"; done
  printf '{"commit":%s,"record":%s,"trackers":[%s]}' "$(json_str "$c")" "$r" "$trackers"
}
# pour_vars : the vars the case's pour renders, in the pour's order, as
# POUR_NAMES and POUR_VALUES. A command defaults to what green and SB_GREEN
# ran, and a case sets VAR_<NAME> to declare another, or to empty for a command
# the rig does not declare.
pour_vars() {
  POUR_NAMES=(base_branch setup_command typecheck_command lint_command build_command affected_tests_command test_command binding_prefix)
  POUR_VALUES=("${VAR_BASE-main}" "${VAR_SETUP-}" "${VAR_TYPECHECK-}" "${VAR_LINT-true}" "${VAR_BUILD-make}"
    "${VAR_AFFECTED-true}" "${VAR_TEST-}" gc-toolkit.)
}
# pair <name> <key> <value> : appends "<key>":<value> to the JSON members the
# variable <name> holds, when the value is not empty.
pair() {
  [ -n "$3" ] || return 0
  printf -v "$1" '%s%s%s:%s' "${!1}" "${!1:+,}" "$(json_str "$2")" "$(json_str "$3")"
}

# write_state : the store the case's script reads, and the run of its root.
# The root carries gc.var.issue, and gc.var.<name> for each var its pour
# rendered non-empty, as gascity stamps them. The work bead carries what
# workspace-setup and the checks recorded on it. The iteration iter-1 carries
# the root pointer for the GC_WISP_ID fallback, the gc.control_for lineage the
# budget lookup joins the control bead on, and optionally the budget stamped on
# the subject itself. The ralph control bead carries the budget unless
# MD_MAX_ATTEMPTS is empty. A key whose value is empty is not written.
write_state() {
  local issue_id="${ISSUE_ID-gc-issue}" root="${ROOT_ID-wisp-1}" root_meta issue_meta iter_meta i rows
  pour_vars
  root_meta='"gc.kind":"workflow"'
  pair root_meta gc.var.issue "${MD_ROOT_ISSUE-$issue_id}"
  for i in "${!POUR_NAMES[@]}"; do pair root_meta "gc.var.${POUR_NAMES[i]}" "${POUR_VALUES[i]}"; done
  issue_meta=""
  pair issue_meta work_dir "${MD_WORK_DIR-$WT}"
  pair issue_meta branch "${MD_BRANCH-polecat/gc-issue}"
  pair issue_meta gc.execution_routed_to "${MD_ROUTE-gc-toolkit/gc-toolkit.polecat}"
  pair issue_meta aborted_at "${MD_ABORTED_AT-}"
  # A pre-existing mark is JSON kept as a string, as bd keeps it.
  pair issue_meta rig_check_pre_existing.lint "${MD_PRE_LINT-}"
  pair issue_meta rig_check_pre_existing.test "${MD_PRE_TEST-}"
  pair issue_meta self_review_setup_build "${MD_SETUP_BUILD-$SB_GREEN}"
  pair issue_meta rig_check_pre_existing.build "${MD_PRE_BUILD-}"
  iter_meta=""
  pair iter_meta gc.root_bead_id "$root"
  pair iter_meta gc.control_for self-review
  pair iter_meta gc.max_attempts "${MD_SUBJECT_MAX-}"
  rows="{\"id\":$(json_str "$root"),\"metadata\":{$root_meta}}"
  rows+=",{\"id\":$(json_str "$issue_id"),\"metadata\":{$issue_meta}${MD_NOTES:+,\"notes\":$(json_str "$MD_NOTES")}}"
  rows+=",{\"id\":\"iter-1\",\"metadata\":{$iter_meta}}"
  if [ -n "${MD_MAX_ATTEMPTS-3}" ]; then
    rows+=",{\"id\":\"control-1\",\"metadata\":{\"gc.kind\":\"ralph\",\"gc.step_id\":\"self-review\",\"gc.max_attempts\":$(json_str "${MD_MAX_ATTEMPTS-3}"),\"gc.root_bead_id\":$(json_str "$root")}}"
  fi
  store "[$rows]"
  # The run of the root, as run-lib.sh would name it: by default it works the
  # case's issue, and RUN_BEAD="" is a run that names no bead.
  printf '[{"root":%s,"convoy":"convoy-1","bead":%s,"formula":"mol-polecat-work","live":true}]' \
    "$(json_str "$root")" "$(json_str "${RUN_BEAD-$issue_id}")" > "$TMP/runs.json"
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
# GC_ITERATION default 1 keeps the gate cases far from the budget so they never
# trip the exhaustion note. GC_COLD=1 is the ralph condition env with a cold
# import cache, where every gc call dies before doing any work,
# UPDATE_FAILS=1 a store that refuses the work bead's write, and SHOW_FAILS_ON
# names a bead whose read the store does not answer.
run_case() {
  local desc="$1" want="$2"
  : > "$CALLS"; : > "$TMP/gctk.calls"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 \
      GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json" \
      RUN_LIB_STUB_FAIL="${RUN_FAILS:+subject}" STUB_SHOW_FAIL_ON="${SHOW_FAILS_ON-}" \
      STUB_GC_FAIL="${GC_COLD:+1}" STUB_UPDATE_FAIL="${UPDATE_FAILS:+${ISSUE_ID-gc-issue}}" \
      GC_ITERATION="${ITERATION-1}" GCTK_BIN="${GCTK-$GCTK_BUILT}" bash "$SCRIPT" ) >"$TMP/out" 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then ok "$desc (exit $got)"
  else bad "$desc (got exit $got, want $want)"; sed 's/^/       /' "$TMP/out"; fi
}

assert_call() {
  if grep -qF -- "$2" "$CALLS" 2>/dev/null; then ok "$1"; else
    bad "$1"; sed 's/^/       /' "$CALLS" 2>/dev/null
  fi
}
refute_call() {
  if grep -qF -- "$2" "$CALLS" 2>/dev/null; then
    bad "$1"; sed 's/^/       /' "$CALLS"
  else ok "$1"; fi
}
assert_out() {
  if grep -qF -- "$2" "$TMP/out" 2>/dev/null; then ok "$1"; else
    bad "$1"; sed 's/^/       /' "$TMP/out" 2>/dev/null
  fi
}

reset_env() {
  unset ROOT_ID ISSUE_ID MD_ROOT_ISSUE RUN_BEAD RUN_FAILS GC_COLD SHOW_FAILS_ON
  unset MD_WORK_DIR MD_BRANCH MD_ROUTE MD_ABORTED_AT MD_MAX_ATTEMPTS MD_SUBJECT_MAX
  unset UPDATE_FAILS ITERATION MD_PRE_LINT MD_PRE_TEST MD_SETUP_BUILD MD_PRE_BUILD GCTK MD_NOTES
  unset VAR_BASE VAR_SETUP VAR_TYPECHECK VAR_LINT VAR_BUILD VAR_AFFECTED VAR_TEST
  clear_records
}

# --- 1. happy path -----------------------------------------------------------
reset_env; write_state; green
run_case "PASS when the tree is clean and every check's record at HEAD passes" 0
assert_out "PASS names the verified HEAD" "PASS: self-review green at $HEAD_SHA"
assert_out "a check the rig declares nothing for reads as a pass" "typecheck:"

# --- 2. checks not yet run ---------------------------------------------------
reset_env; write_state
run_case "FAIL when nothing is recorded at HEAD" 1
assert_out "says nothing is recorded" "nothing recorded at $HEAD_SHA for: test lint typecheck"

# --- 3. records at an older commit only --------------------------------------
reset_env; write_state; green "$TMP/old"
run_case "FAIL when only an older commit carries records" 1
assert_out "names the commit that has none" "nothing recorded at $HEAD_SHA"

# --- 3b. records another worktree wrote at HEAD ------------------------------
reset_env; write_state; green "$TMP/twin"
run_case "PASS on records another worktree of the clone wrote at HEAD" 0

# --- 3c. one check recorded red ----------------------------------------------
reset_env; VAR_LINT=false; write_state; green; record "$WT" lint --command false
run_case "FAIL when a check's record at HEAD is a fail" 1
assert_out "names the red check" "not green at $HEAD_SHA: lint"

# --- 3d. a red check marked pre-existing at HEAD ------------------------------
reset_env; VAR_LINT=false; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)" tk-t1); write_state
run_case "PASS when the red check's record is marked pre-existing at HEAD" 0
assert_out "names the tracker that carries it" "pre-existing, tracked by tk-t1"

reset_env; VAR_LINT=false; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$OLD_SHA" "$(recorded lint)" tk-t1); write_state
run_case "FAIL when the pre-existing mark names another commit" 1

reset_env; VAR_LINT=false; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)"); write_state
run_case "FAIL when the pre-existing mark names no tracker" 1

# --- 3d2. a run that replaced the marked record --------------------------------
# gctk rig replaces a commit's record when a call declares another run. When the
# replacing run is the declared one, its fail is not the one judged pre-existing;
# when it is not, its record answers nothing for the declared run.
reset_env; VAR_LINT='exit 3'; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)" tk-t1); write_state
record "$WT" lint --command 'exit 3'
run_case "FAIL when the declared run replaced the marked record of another command at HEAD" 1
assert_out "says the mark judged another run" "judged another run's fail"

reset_env; VAR_LINT=false; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)" tk-t1); write_state
record "$WT" lint --command 'exit 3'
run_case "FAIL when a run with another command replaced the declared run's marked record at HEAD" 1
assert_out "says the record is another run's" "lint: the record at $HEAD_SHA is of \"exit 3\", not of the declared \"false\", so it answers nothing here"

reset_env; VAR_AFFECTED=""; VAR_TEST=false; green; record "$WT" test --scope affected --command false
MD_PRE_TEST=$(premark "$HEAD_SHA" "$(recorded test)" tk-t1); write_state
record "$WT" test --scope full --command false
run_case "FAIL when the declared full-suite run replaced the marked record of the affected subset" 1
assert_out "says the test mark judged another run" "test: the pre-existing mark at $HEAD_SHA judged another run's fail"

# --- 3d2b. a record at HEAD that is not the declared run's ----------------------
# --check reports whatever is recorded at HEAD. A record counts only when it is
# the run the step declares: the same command and, for test, the same scope.
reset_env; VAR_LINT='tools/lint.sh'; write_state; green
run_case "FAIL when HEAD holds only a pass of a command the step does not declare" 1
assert_out "names the other command and the declared one" "lint: the record at $HEAD_SHA is of \"true\", not of the declared \"tools/lint.sh\""
assert_out "…and counts the check as unrecorded" "nothing recorded at $HEAD_SHA for: lint by the runs the step declares"

reset_env; write_state; green; record "$WT" test --scope full --command true
run_case "FAIL when HEAD holds a full-suite pass where the step declares the affected subset" 1
assert_out "names both scopes" "test: the record at $HEAD_SHA is of \"true\" (scope full), not of the declared \"true\" (scope affected)"

# The block records a pass that ran nothing, and the iteration may then run the
# repo's own gate in its place.
reset_env; VAR_LINT=""; write_state; green; record "$WT" lint --nothing-declared
record "$WT" lint --command 'printf ok'
run_case "PASS on another run's pass for a check the rig declares no command for" 0

reset_env; VAR_AFFECTED=""; VAR_TEST=true; write_state
record "$WT" lint --command true; record "$WT" typecheck --nothing-declared
SAME_TREE=$(git -C "$WT" commit-tree "$HEAD_SHA^{tree}" -p "$HEAD_SHA" -m same-tree)
git -C "$WT" worktree add -q --detach "$TMP/same-tree" "$SAME_TREE"
record "$TMP/same-tree" test --scope full --command true
run_case "PASS on the declared full-suite pass a commit with HEAD's tree recorded" 0
git -C "$WT" worktree remove --force "$TMP/same-tree"

reset_env; VAR_BASE=""; write_state; green
run_case "FAIL (fail-closed) when the root carries no stamp of what its pour rendered" 1
assert_out "names the missing stamp" "carries no gc.var.base_branch"

# --- 3d3. setup and build, which gctk rig does not record ----------------------
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none fail); write_state; green
run_case "FAIL when the build failed at HEAD, though every record there passes" 1
assert_out "names the failed build" "not green at $HEAD_SHA: build"

reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" fail pass); write_state; green
run_case "FAIL when setup failed at HEAD" 1
assert_out "names the failed setup" "not green at $HEAD_SHA: setup"

reset_env; MD_SETUP_BUILD=$(noted "$OLD_SHA" pass pass); write_state; green
run_case "FAIL when setup and build were noted at another commit" 1
assert_out "says nothing notes them at HEAD" "nothing recorded at $HEAD_SHA for: setup build"

reset_env; MD_SETUP_BUILD=""; write_state; green
run_case "FAIL when nothing notes setup and build" 1

reset_env; MD_SETUP_BUILD="{\"commit\":\"$HEAD_SHA\"}"; write_state; green
run_case "FAIL when the note at HEAD names no outcome" 1

# A setup or build failure red on the base too is marked like any other check,
# and the mark holds the note it judged in place of a record.
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none fail)
MD_PRE_BUILD=$(premark "$HEAD_SHA" "$MD_SETUP_BUILD" tk-b1); write_state; green
run_case "PASS when the failed build's note at HEAD is marked pre-existing" 0
assert_out "names the build's tracker" "build: the fail at $HEAD_SHA is pre-existing, tracked by tk-b1"
reset_env; VAR_BUILD='make all'; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none fail 'make all')
MD_PRE_BUILD=$(premark "$HEAD_SHA" "$(noted "$HEAD_SHA" none fail)" tk-b1); write_state; green
run_case "FAIL when the build mark holds a note of another command" 1
assert_out "says the build mark judged another run" "build: the pre-existing mark at $HEAD_SHA judged another run's fail"
# A note counts only while its commands are the ones the step declares.
reset_env; VAR_BUILD='make all'; write_state; green
run_case "FAIL when the note at HEAD is of another build command than the step declares" 1
assert_out "names the noted command and the declared one" "setup and build: the note at $HEAD_SHA is of setup \"\" and build \"make\", not of the declared setup \"\" and build \"make all\""
assert_out "…and counts setup and build as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" fail fail)
MD_PRE_BUILD=$(premark "$HEAD_SHA" "$MD_SETUP_BUILD" tk-b1); write_state; green
run_case "FAIL when setup failed too and only the build is marked" 1
assert_out "names the unmarked setup" "not green at $HEAD_SHA: setup"

# A command the step does not declare has none to match, so the iteration may
# run the repo's own in its place, and the note's outcome for it answers, as any
# run's record does for such a check.
OWN_SETUP='pnpm install --frozen-lockfile'; OWN_BUILD='pnpm build'
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass pass "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "PASS on the note of the repo's own setup and build when the step declares neither" 0
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none none ""); write_state; green
run_case "PASS on a note of none and no commands when the step declares neither" 0
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$OLD_SHA" pass pass "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "FAIL when the repo's own setup and build were noted at another commit" 1
assert_out "…counting them as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"
# Its outcome counts whichever way it went.
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass fail "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "FAIL when the repo's own build failed at HEAD" 1
assert_out "…naming that build" "not green at $HEAD_SHA: build"
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" fail pass "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "FAIL when the repo's own setup failed at HEAD" 1
assert_out "…naming that setup" "not green at $HEAD_SHA: setup"
reset_env; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass fail "$OWN_BUILD" "$OWN_SETUP")
MD_PRE_BUILD=$(premark "$HEAD_SHA" "$MD_SETUP_BUILD" tk-b1); write_state; green
run_case "PASS when a pre-existing mark holds the note of the repo's own failed build" 0
assert_out "…naming its tracker" "build: the fail at $HEAD_SHA is pre-existing, tracked by tk-b1"
# Each command is judged by itself, so the one the step does declare still has
# to match.
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass pass make "$OWN_SETUP"); write_state; green
run_case "PASS on the repo's own setup beside the declared build" 0
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass pass "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "FAIL when the build is not the declared one, though the step declares no setup" 1
assert_out "…counting both as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"
reset_env; VAR_SETUP="$OWN_SETUP"; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass pass "$OWN_BUILD" "$OWN_SETUP"); write_state; green
run_case "PASS on the repo's own build beside the declared setup" 0
reset_env; VAR_SETUP="$OWN_SETUP"; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" pass pass "$OWN_BUILD" 'npm ci'); write_state; green
run_case "FAIL when the setup is not the declared one, though the step declares no build" 1
assert_out "…counting both as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"
# A note that names no command says the declared one never ran.
reset_env; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none none ""); write_state; green
run_case "FAIL when the note ran no build, though the step declares one" 1
assert_out "…counting both as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"
reset_env; VAR_SETUP="$OWN_SETUP"; VAR_BUILD=""; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none none ""); write_state; green
run_case "FAIL when the note ran no setup, though the step declares one" 1
assert_out "…counting both as unrecorded" "nothing recorded at $HEAD_SHA for: setup build"

# --- 3d4. the step's own block, rendered as a pour renders it -------------------
# The self-review step's check call, rendered with the case's commands, runs
# rig-checks.sh in the fixture worktree against the gctk built from this
# checkout. The root carries the same commands, as a pour stamps them, and the
# block notes setup and build on the work bead in the store, so the exit
# condition reads what the block wrote.
ROOT="$(cd "$HERE/../.." && pwd)"
awk '
  /^```bash$/ {buf = ""; f = 1; next}
  /^```$/ {if (f && buf ~ /rig-checks\.sh" self-review/) {printf "%s", buf; exit} f = 0; next}
  f {buf = buf $0 "\n"}' "$ROOT/formulas/mol-polecat-work.toml" > "$TMP/checks.tmpl"
grep -qF 'rig-checks.sh" self-review' "$TMP/checks.tmpl" \
  && ok "the self-review check call extracts" \
  || bad "the self-review check call did not extract"
# render_checks : the block, each placeholder filled with what the case's pour
# renders (pour_vars).
render_checks() {
  local t i
  t=$(<"$TMP/checks.tmpl"); pour_vars
  for i in "${!POUR_NAMES[@]}"; do t=$(fill "$t" "${POUR_NAMES[i]}" "${POUR_VALUES[i]}"); done
  printf '%s\n' "$t" \
    | sed -e "s|\"<the work bead>\"|\"\${ISSUE_ID-gc-issue}\"|" \
          -e "s|\"\$(b='gc-toolkit.'; gc \"\${b%.}\" scripts-dir)/rig-checks.sh\"|\"$HERE/rig-checks.sh\"|"
}
# fill <text> <name> <value> : the text with each {{name}} in it replaced by the
# value, taken literally.
fill() {
  local t="$1" k="{{$2}}" out=""
  while [[ "$t" == *"$k"* ]]; do out+="${t%%"$k"*}$3"; t="${t#*"$k"}"; done
  printf '%s' "$out$t"
}
# run_checks <shell> : the rendered block in the fixture worktree.
run_checks() {
  render_checks > "$TMP/checks.sh"
  ( cd "$WT" && env GC_PACK_DIR="" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/no-city" GCTK_BIN="$GCTK_BUILT" \
      ISSUE_ID="${ISSUE_ID-gc-issue}" "$1" "$TMP/checks.sh" ) >"$TMP/checks.out" 2>&1
}
reset_env; render_checks > "$TMP/checks.sh"
grep -qF '{{' "$TMP/checks.sh" \
  && bad "the call renders with a placeholder pour_vars does not fill" \
  || ok "pour_vars fills every placeholder in the call"
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD='exit 1'; write_state
  run_checks "$sh"
  run_case "$sh: FAIL after the step's own block ran a build that fails on a clean tree" 1
  assert_out "$sh: …naming the build" "not green at $HEAD_SHA: build"
  BLOCK_NOTE=$(meta gc-issue self_review_setup_build)
  eq "$BLOCK_NOTE" "$(noted "$HEAD_SHA" none fail 'exit 1')" \
    "$sh: the block notes HEAD, no setup, the failed build and its command"
  MD_SETUP_BUILD="$BLOCK_NOTE"; MD_PRE_BUILD=$(premark "$HEAD_SHA" "$BLOCK_NOTE" tk-b1); write_state
  run_case "$sh: PASS once a pre-existing mark holds the note the block wrote" 0
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD=true; write_state
  run_checks "$sh"
  run_case "$sh: PASS after the step's own block ran a build that passes" 0
  # On a root stamped with neither command, the iteration gives the block the
  # repo's own, and its note names them.
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD=""; write_state
  VAR_SETUP=true VAR_BUILD=true run_checks "$sh"
  run_case "$sh: PASS after the block ran the repo's own setup and build where the step declares neither" 0
  eq "$(meta gc-issue self_review_setup_build)" "$(noted "$HEAD_SHA" pass pass true true)" \
    "$sh: …with a note that names them"
  # What setup and build leave that git does not ignore is put back, so the
  # checks after them run, and the block notes them, in one run of the block.
  reset_env; MD_SETUP_BUILD=""; VAR_SETUP='printf rewritten > f'; VAR_BUILD='printf out > dist.txt'; write_state
  run_checks "$sh"
  run_case "$sh: PASS after the block ran a setup that rewrites a tracked file and a build that leaves a file" 0
  eq "$(git -C "$WT" status --porcelain)/$(cat "$WT/f")" "/more" "$sh: …which leaves the tree HEAD holds"
  # Whatever the case left must not reach the cases after it.
  git -C "$WT" reset -q --hard; git -C "$WT" clean -fdq
  # A rig's command may run over several lines or hold a here-document. It reaches
  # the record whole, so the exit condition reads the run the step declares.
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD=$'true\ntrue'; VAR_AFFECTED=$'true\ntrue'
  VAR_LINT=$'cat <<EOF >/dev/null\nit\'s a "body" ) (\n\nEOF\ntrue'; write_state
  run_checks "$sh"
  run_case "$sh: PASS after the block ran multi-line commands and one holding a here-document" 0
  has "$(recorded lint)" "\"command\":$(go_json_str "$VAR_LINT")}" "$sh: …with the here-document's command recorded whole"
  has "$(recorded test)" "\"command\":$(go_json_str "$VAR_AFFECTED")}" "$sh: …and the multi-line test run"
  # A test run that leaves a file keeps its record, and the note the block
  # wrote before the run stands, so removing the file is all the loop needs.
  reset_env; MD_SETUP_BUILD=""; VAR_AFFECTED='printf x > cover.out'; VAR_BUILD=true; write_state
  run_checks "$sh"
  run_case "$sh: FAIL while the file a test run left is in the tree" 1
  rm -f "$WT/cover.out"
  run_case "$sh: PASS once that file is removed, without running the block again" 0
  # A declared run that stops short of a result, a crash or a command bash
  # cannot find, exits 4 and records nothing, which leaves the pass another
  # command recorded at HEAD. That pass must not converge the loop.
  for crash in 'kill -KILL $$' no-such-lint-command; do
    reset_env; MD_SETUP_BUILD=""; VAR_BUILD=true; VAR_LINT="$crash"; write_state
    record "$WT" lint --command true
    run_checks "$sh"
    grep -qF "gctk rig lint: machine failure, nothing recorded" "$TMP/checks.out" \
      && ok "$sh: the block's lint run of $crash stops at exit 4 with nothing recorded" \
      || { bad "$sh: the block's lint run of $crash stops at exit 4 with nothing recorded"; sed 's/^/       /' "$TMP/checks.out"; }
    has "$(recorded lint)" '"command":"true"}' "$sh: …which leaves the pass of another command at HEAD"
    run_case "$sh: FAIL when the declared lint run stopped beside another command's pass at HEAD ($crash)" 1
    assert_out "$sh: …naming that pass as another run's" "lint: the record at $HEAD_SHA is of \"true\", not of the declared $(json_str "$crash"), so it answers nothing here"
  done
done
# Records already at HEAD outlive an edit, so a build run over uncommitted
# changes must note nothing: those changes, not HEAD, are what it built.
reset_env; MD_SETUP_BUILD=""; VAR_BUILD=true; write_state; green
echo dirt > "$WT/untracked"
run_checks bash
rm -f "$WT/untracked"
run_case "FAIL when the block ran over uncommitted changes, beside records that pass" 1
assert_out "…because the block noted no setup and build" "nothing recorded at $HEAD_SHA for: setup build"

# --- 3e. some checks recorded, one not ----------------------------------------
reset_env; write_state
record "$WT" test --scope affected --command true
record "$WT" lint --command true
run_case "FAIL when a check has no record" 1
assert_out "names the check with no record" "nothing recorded at $HEAD_SHA for: typecheck"

# --- 3f. no gctk binary ------------------------------------------------------
reset_env; GCTK=none; write_state; green
run_case "NO VERDICT with no gctk binary to read the records" 75
assert_out "names the missing binary" "NO VERDICT: no gctk binary"

# shim <name> <body> : a gctk at $TMP/<name> that logs each call's arguments to
# $TMP/gctk.calls, which run_case empties, then runs <body>.
shim() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n%s\n' "$TMP/gctk.calls" "$2" > "$TMP/$1"
  chmod +x "$TMP/$1"
}
shim gctk-logged "exec $(printf %q "$GCTK_BUILT") \"\$@\""
shim gctk-usage 'echo "gctk rig test: unknown flag: --check" >&2; exit 2'
shim gctk-killed 'kill -KILL $$'

# --- 4. dirty worktree -------------------------------------------------------
reset_env; write_state; green
echo dirt > "$WT/untracked"
run_case "FAIL when the worktree is dirty" 1
assert_out "names the dirty-tree reason" "worktree is dirty"
rm -f "$WT/untracked"

# --- 4b. a change config hides from a plain status ---------------------------
# The clean-tree check reads status with gctk's flags, so a tree gctk would
# refuse to certify is a dirty tree before gctk is asked.
reset_env; GCTK="$TMP/gctk-logged"; write_state; green
git -C "$WT" config status.showUntrackedFiles no
echo dirt > "$WT/untracked"
run_case "FAIL as a dirty tree when config hides an untracked file from a plain status" 1
assert_out "gives the dirty-tree reason" "worktree is dirty"
assert_out "…naming the file" "?? untracked"
if [ -s "$TMP/gctk.calls" ]; then bad "…without asking gctk"; sed 's/^/       /' "$TMP/gctk.calls"
else ok "…without asking gctk"; fi
rm -f "$WT/untracked"; git -C "$WT" config --unset status.showUntrackedFiles

# --- 4c. a record store gctk cannot read -------------------------------------
# A plain file where the store's directory goes fails gctk's lookup with
# ENOTDIR, as it would for a suite run as root, which reads through a mode that
# refuses others. The run on the budget's last attempt spent no attempt, so it
# notes nothing.
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3; write_state; green
mv "$WT/.git/gc-rig-checks" "$TMP/records"; : > "$WT/.git/gc-rig-checks"
run_case "NO VERDICT on the budget's last attempt when gctk cannot read the record store" 75
assert_out "gives gctk's reason" "NO VERDICT: gctk rig test --check read nothing at $HEAD_SHA: gctk rig test: machine failure, nothing recorded: cannot read the record store"
assert_out "…a lookup that failed with ENOTDIR" "not a directory"
refute_call "…and notes nothing on the work bead" "--append-notes"
rm -f "$WT/.git/gc-rig-checks"; mv "$TMP/records" "$WT/.git/gc-rig-checks"
run_case "PASS on the same records once the store reads again" 0

# --- 4d. gctk's other exits ----------------------------------------------------
reset_env; GCTK="$TMP/gctk-usage"; write_state; green
run_case "FAIL when gctk refuses the call as wired" 1
assert_out "quotes gctk's refusal" "gctk rig test --check refused the call: gctk rig test: unknown flag: --check"
reset_env; GCTK="$TMP/gctk-killed"; write_state; green
run_case "NO VERDICT when gctk is stopped by a signal" 75
assert_out "names the exit" "NO VERDICT: gctk rig test --check exited 137"

# --- 5. fail-closed on an absent worktree ------------------------------------
reset_env; MD_WORK_DIR="$TMP/does-not-exist"; write_state
run_case "FAIL (fail-closed) when recorded work_dir does not exist" 1

# --- 6. fail-closed on a non-git work_dir ------------------------------------
reset_env; MD_WORK_DIR="$TMP"; write_state
run_case "FAIL (fail-closed) when work_dir is not a git worktree" 1

# --- 7. a bead the store does not answer for ---------------------------------
reset_env; RUN_FAILS=1; MD_ROOT_ISSUE=""; write_state
run_case "NO VERDICT when the run of the root is unreadable and no gc.var.issue" 75
reset_env; SHOW_FAILS_ON=gc-issue; write_state; green
run_case "NO VERDICT when the work bead cannot be read" 75
assert_out "names the read" "NO VERDICT: could not read work bead gc-issue"
reset_env; SHOW_FAILS_ON=wisp-1; write_state; green
run_case "NO VERDICT when the root cannot be read" 75
assert_out "names the read" "NO VERDICT: could not read root bead wisp-1"

# --- 8. resilient fallback: the run unreadable but gc.var.issue set -----------
reset_env; RUN_FAILS=1; write_state; green
run_case "PASS via gc.var.issue fallback when the run is unreadable but the records are green" 0
assert_out "warns that the one-member invariant went unverified" "membership unverified"

# --- 9. fail-closed on a malformed convoy (two members) ----------------------
# run-lib.sh names no bead for a run whose convoy tracks two.
reset_env; RUN_BEAD=""; write_state
run_case "FAIL (fail-closed) when the run names no bead, as for a convoy with two tracked members" 1
assert_out "names the run it could not use" "works no single bead"

# --- 10. fail-closed when gc.var.issue disagrees with the member -------------
# run-lib.sh names no bead for a root whose gc.var.issue disagrees with its convoy.
reset_env; MD_ROOT_ISSUE="gc-other"; RUN_BEAD=""; write_state
run_case "FAIL (fail-closed) when the run names no bead, as when gc.var.issue disagrees with the convoy member" 1

# --- 11. bd-only under a cold gc -------------------------------------------
# A cold import cache kills every gc call; the verdict must still be correct
# because resolution is bd-only, and gc convoy must never be reached.
reset_env; GC_COLD=1; write_state; green
run_case "PASS under a cold gc (resolution is bd-only, and the record reads call no gc)" 0
if grep -q '^convoy ' "$CALLS"; then bad "resolution must not shell out to gc convoy"; sed 's/^/       /' "$CALLS"
else ok "resolution must not shell out to gc convoy"; fi

# --- 12. exhaustion note ----------------------------------------------------
# The last failing attempt (GC_ITERATION >= gc.max_attempts) notes the
# exhaustion on the work bead, and that note is the condition's one write: the
# loop's last iteration asks a person through a gate from its own session, and
# this condition runs inside the control dispatcher's judgment of the control.
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3; write_state
run_case "FAIL on the last attempt with nothing recorded" 1
assert_call "last attempt notes the exhaustion on the work bead, naming the run" \
  "update gc-issue --append-notes Self-review loop of run wisp-1 exhausted its budget (attempt 3 of 3)"
assert_call "the note names the gate a last attempt still red asks through" "self-review-exhausted human gate"
if [ "$(grep -c '^bd update ' "$CALLS")" = 1 ]; then ok "the note is the condition's one write"; else
  bad "the note is the condition's one write"; sed 's/^/       /' "$CALLS"; fi
for flag in --set-metadata --unset-metadata --assignee --status; do
  refute_call "the note's write carries no $flag: it routes, assigns, reopens and stamps nothing" "$flag"
done
refute_call "nothing is nudged" "session nudge"

# --- 13. one note for a run ---------------------------------------------------
# A work bead whose notes already record this run's exhaustion is left alone: a
# retried exec of the same attempt must not append a second note.
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3
MD_NOTES="Self-review loop of run wisp-1 exhausted its budget (attempt 3 of 3) without a verified-green gate"; write_state
run_case "FAIL on the last attempt when the run's exhaustion is already noted" 1
refute_call "does not note the same run's exhaustion twice" "--append-notes"
# An earlier run's note, and the aborted_at an earlier hand-back stamped, say
# nothing about this run.
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3; MD_ABORTED_AT="self-review-exhausted"
MD_NOTES="Self-review loop of run wisp-0 exhausted its budget (attempt 3 of 3) without a verified-green gate"; write_state
run_case "FAIL on the last attempt of a later run on the same bead" 1
assert_call "an earlier run's note and aborted_at leave this run's note to be written" \
  "--append-notes Self-review loop of run wisp-1 exhausted its budget"

# --- 14. no note before the budget is spent ----------------------------------
reset_env; ITERATION=2; MD_MAX_ATTEMPTS=3; write_state
run_case "FAIL mid-budget with nothing recorded" 1
refute_call "no note before the last attempt" "--append-notes"

# --- 15. budget read from the subject bead when carried there ----------------
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=""; MD_SUBJECT_MAX=3; write_state
run_case "FAIL on the last attempt with the budget on the subject bead" 1
assert_call "resolves the budget from the subject when the control list is empty" "--append-notes"

# --- 16. the note needs no gc, and cannot change the verdict -----------------
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3; GC_COLD=1; write_state
run_case "FAIL on the last attempt under a cold gc" 1
assert_call "the note still lands, since it goes through bd alone" "--append-notes Self-review loop of run wisp-1"
reset_env; ITERATION=3; MD_MAX_ATTEMPTS=3; UPDATE_FAILS=1; write_state
run_case "FAIL on the last attempt when the store refuses the note" 1
assert_out "says the note did not land" "the exhaustion note did not land on gc-issue"

# --- 17. the step's last-attempt decline, run as the step writes it ----------
# The self-review step's last attempt, still red, declines its run with one
# decline.sh call. Rendered as a pour renders it and run against the real
# decline.sh, the call files the self-review-exhausted gate on the work bead,
# makes the work bead wait on it armed to re-sling mol-polecat-work, cancels the
# run at the iteration it holds and drains, in that order. The gate, the wait
# and the cancel are stand-ins that record their calls, in the log the fake
# writes its calls to; decline.test.sh holds what decline.sh does when one of
# them does not land.
DECLINE_CALL=$(grep -E '^`"\$\(b=.\{\{binding_prefix\}\}.; gc "\$\{b%\.\}" scripts-dir\)/decline\.sh" --step self-review ' "$ROOT/formulas/mol-polecat-work.toml")
if [ "$(printf '%s\n' "$DECLINE_CALL" | grep -c 'decline\.sh')" = 1 ]; then ok "the self-review step carries one decline.sh call for its last attempt"; else
  bad "the self-review step carries one decline.sh call for its last attempt (found: $DECLINE_CALL)"; fi
# The pack the fake's scripts-dir names: the real decline.sh beside them.
DPACK="$TMP/decline-pack/assets/scripts"; mkdir -p "$DPACK"
cp "$HERE/decline.sh" "$DPACK/"
for stub in human-gate:gate await-ruling:await run-cancel:cancel; do
  printf '#!/usr/bin/env bash\nprintf %s "$*" >> "$DCALLS"\n' "'${stub#*:} %s\\n'" > "$DPACK/${stub%%:*}.sh"
done
chmod +x "$DPACK"/*.sh
printf '%s\n' "$DECLINE_CALL" | sed -e 's/^`//' -e 's/`$//' \
  -e "s|{{binding_prefix}}|gc-toolkit.|g" -e 's|"<the work bead>"|"gc-issue"|' > "$TMP/decline.sh"
grep -q -e '{{' -e '<the work bead>' "$TMP/decline.sh" \
  && bad "the decline call renders with a placeholder a pour leaves unfilled" \
  || ok "a pour fills every placeholder in the decline call"
# The iteration this session's hook names, a step of the run.
store '[{"id":"iter-3","status":"in_progress","assignee":"me","metadata":{"gc.step_ref":"self-review.iteration.3"}}]'
for sh in $SHELLS; do
  : > "$TMP/decline.calls"
  ( cd "$TMP" && env STUB_PACK="$TMP/decline-pack" STUB_GC_LOG="$TMP/decline.calls" DCALLS="$TMP/decline.calls" \
      GC_SESSION_ID=me STUB_HOOK_CURRENT=iter-3 "$sh" "$TMP/decline.sh" ) >"$TMP/decline.out" 2>&1
  rc=$?
  eq "$rc" 0 "$sh: the last attempt's decline exits 0"
  eq "$(awk '/^(gate|await|cancel) / { print $1 } /^runtime drain-ack$/ { print "drain" }' "$TMP/decline.calls" | tr '\n' ';')" "gate;await;cancel;drain;" \
    "$sh: …filing the gate, then the wait, then the run's cancel, then the drain"
  assert_decline() { grep -qE -- "$2" "$TMP/decline.calls" && ok "$sh: $1" || { bad "$sh: $1"; sed 's/^/       /' "$TMP/decline.calls"; }; }
  assert_decline "…the gate blocks the work bead under self-review-exhausted" '^gate --subject gc-issue --key self-review-exhausted --message '
  assert_decline "…its message tells the person clearing it re-slings the work" 'clearing it re-slings gc-issue'
  assert_decline "…the work bead waits on that gate, armed to re-sling mol-polecat-work" '^await gc-issue --key self-review-exhausted --formula mol-polecat-work$'
  assert_decline "…and the run is cancelled at the iteration this session holds" '^cancel --step self-review --reason '
done

echo
echo "self-review-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
