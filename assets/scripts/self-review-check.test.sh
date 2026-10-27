#!/usr/bin/env bash
# Test for self-review-check.sh — the exit condition of the self-review check
# loop in mol-polecat-work.
#
# It EXECUTES the real shipped script against stub `bd` / `gc` binaries, the
# run-lib.sh stub (the run of the root each case names), a real fixture git
# worktree, and the real `gctk` built from this checkout, whose
# records the cases write by running `gctk rig` in the fixture the way an
# iteration does. So the exit-code contract (0 verified-green, 1 everything
# else, fail-closed on any unreadable state), the record reads and the
# exhaustion handback are pinned against the code that ships, not a paraphrase.
set -uo pipefail

TMP="$(mktemp -d "${TMPDIR:-/tmp}/self-review-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # harness_build_gctk
harness_build_gctk
[ -n "$GCTK_BUILT" ] || { echo "FAIL - $GCTK_BUILD_ERR"; exit 1; }
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
SCRIPT="$HERE/self-review-check.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# --- stubs -------------------------------------------------------------------
# Both stubs read $TMP/state.env, so each case varies the bead metadata the
# script sees without re-writing the stubs.
mkdir -p "$TMP/bin"

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# bd show <id> --json | bd list … --json | bd update <id> …
. "$STATE"
case "$1" in
show)
  case "$2" in
  "$ROOT_ID")
    printf '[{"id":"%s","metadata":{"gc.kind":"workflow"' "$ROOT_ID"
    [ -n "$MD_ROOT_ISSUE" ] && printf ',"gc.var.issue":"%s"' "$MD_ROOT_ISSUE"
    [ -n "$MD_ROOT_VARS" ] && printf ',%s' "$MD_ROOT_VARS"
    printf '}}]'
    ;;
  "$ISSUE_ID")
    printf '[{"id":"%s","metadata":{' "$ISSUE_ID"
    sep=""
    [ -n "$MD_WORK_DIR" ]    && { printf '%s"work_dir":"%s"' "$sep" "$MD_WORK_DIR"; sep=","; }
    [ -n "$MD_BRANCH" ]      && { printf '%s"branch":"%s"' "$sep" "$MD_BRANCH"; sep=","; }
    [ -n "$MD_GATE" ]        && { printf '%s"self_review_passed_sha":"%s"' "$sep" "$MD_GATE"; sep=","; }
    [ -n "$MD_ROUTE" ]       && { printf '%s"gc.execution_routed_to":"%s"' "$sep" "$MD_ROUTE"; sep=","; }
    [ -n "$MD_ABORTED_AT" ]  && { printf '%s"aborted_at":"%s"' "$sep" "$MD_ABORTED_AT"; sep=","; }
    # A pre-existing mark is JSON kept as a string, as bd keeps it.
    [ -n "$MD_PRE_LINT" ]    && { printf '%s"rig_check_pre_existing.lint":%s' "$sep" "$(printf '%s' "$MD_PRE_LINT" | jq -Rs .)"; sep=","; }
    [ -n "$MD_PRE_TEST" ]    && { printf '%s"rig_check_pre_existing.test":%s' "$sep" "$(printf '%s' "$MD_PRE_TEST" | jq -Rs .)"; sep=","; }
    [ -n "$MD_SETUP_BUILD" ] && { printf '%s"self_review_setup_build":%s' "$sep" "$(printf '%s' "$MD_SETUP_BUILD" | jq -Rs .)"; sep=","; }
    [ -n "$MD_PRE_BUILD" ]   && { printf '%s"rig_check_pre_existing.build":%s' "$sep" "$(printf '%s' "$MD_PRE_BUILD" | jq -Rs .)"; sep=","; }
    printf '}}]'
    ;;
  *)
    # An iteration bead: the root pointer for the GC_WISP_ID fallback, the
    # gc.control_for lineage the budget lookup joins the control bead on, and
    # optionally the budget stamped on the subject itself.
    printf '[{"id":"%s","metadata":{"gc.root_bead_id":"%s","gc.control_for":"self-review"' "$2" "$ROOT_ID"
    [ -n "$MD_SUBJECT_MAX" ] && printf ',"gc.max_attempts":"%s"' "$MD_SUBJECT_MAX"
    printf '}}]'
    ;;
  esac
  ;;
list)
  # The ralph control-bead lookup (gc.root_bead_id + gc.kind=ralph).
  if [ -n "$MD_MAX_ATTEMPTS" ]; then
    printf '[{"id":"control-1","metadata":{"gc.kind":"ralph","gc.step_id":"self-review","gc.max_attempts":"%s"}}]' "$MD_MAX_ATTEMPTS"
  else
    printf '[]'
  fi
  ;;
update)
  [ "$UPDATE_FAILS" = "1" ] && { echo "stub: write refused" >&2; exit 1; }
  printf 'bd update %s\n' "$*" >> "$CALLS"
  ;;
*)
  exit 1
  ;;
esac
BD

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# gc session nudge <target> <message>
#
# GC_COLD=1 models the ralph condition env with a cold import cache: every gc
# invocation dies on the import closure before doing any work. The checker must
# still reach a correct verdict, so no bead resolution may depend on gc.
. "$STATE"
if [ "$GC_COLD" = "1" ]; then
  printf 'gc %s\n' "$1" >> "$CALLS"
  echo "city import … locked but not cached at /nonexistent; run 'gc import install'" >&2
  exit 1
fi
if [ "$1" = "convoy" ]; then
  # Resolution must be bd-only: record the call so a regression that reintroduces
  # the dependency is visible, and fail the way a cold cache would.
  printf 'gc convoy %s\n' "$2" >> "$CALLS"
  echo "stub: self-review-check.sh must not shell out to gc convoy" >&2
  exit 1
fi
if [ "$1" = "session" ] && [ "$2" = "nudge" ]; then
  printf 'gc session nudge %s\n' "$3" >> "$CALLS"
  exit 0
fi
# The self-review step's note of setup and build lands in the state the bd stub
# serves, so the exit condition reads what the step wrote.
if [ "$1" = "bd" ] && [ "$2" = "update" ]; then
  for a in "$@"; do
    case "$a" in
    self_review_setup_build=*) printf 'MD_SETUP_BUILD=%q\n' "${a#self_review_setup_build=}" >> "$STATE" ;;
    esac
  done
  exit 0
fi
exit 0
GC

chmod +x "$TMP/bin/bd" "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"
export STATE="$TMP/state.env"
export CALLS="$TMP/calls.log"

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
# The step's note of setup and build at <commit>: setup <s>, build <b>, and the
# build command [bc], default make.
noted() { jq -nc --arg c "$1" --arg s "$2" --arg b "$3" --arg bc "${4:-make}" '{commit: $c, setup: $s, build: $b, setup_command: "", build_command: $bc}'; }
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
# premark <commit> <record> [tracker...] : a pre-existing mark, in the shape
# rig-check-pre-existing.sh writes.
premark() { local c="$1" r="$2"; shift 2; jq -cn --arg c "$c" --argjson r "$r" '{commit: $c, record: $r, trackers: $ARGS.positional}' --args "$@"; }
# pour_vars : the vars the case's pour renders, as one JSON object. A command
# defaults to what green and SB_GREEN ran, and a case sets VAR_<NAME> to declare
# another, or to empty for a command the rig does not declare.
pour_vars() {
  jq -nc --arg base "${VAR_BASE-main}" --arg setup "${VAR_SETUP-}" --arg typecheck "${VAR_TYPECHECK-}" \
    --arg lint "${VAR_LINT-true}" --arg build "${VAR_BUILD-make}" --arg affected "${VAR_AFFECTED-true}" \
    --arg test "${VAR_TEST-}" '{base_branch: $base, setup_command: $setup,
      typecheck_command: $typecheck, lint_command: $lint, build_command: $build,
      affected_tests_command: $affected, test_command: $test}'
}

write_state() {
  local issue_id="${ISSUE_ID-gc-issue}"
  cat > "$STATE" <<EOF
ROOT_ID="${ROOT_ID-wisp-1}"
ISSUE_ID="$issue_id"
MD_ROOT_ISSUE="${MD_ROOT_ISSUE-$issue_id}"
GC_COLD="${GC_COLD-0}"
MD_WORK_DIR="${MD_WORK_DIR-$WT}"
MD_BRANCH="${MD_BRANCH-polecat/gc-issue}"
MD_GATE="${MD_GATE-}"
MD_ROUTE="${MD_ROUTE-gc-toolkit/gc-toolkit.polecat}"
MD_ABORTED_AT="${MD_ABORTED_AT-}"
MD_MAX_ATTEMPTS="${MD_MAX_ATTEMPTS-3}"
MD_SUBJECT_MAX="${MD_SUBJECT_MAX-}"
UPDATE_FAILS="${UPDATE_FAILS-0}"
EOF
  # A JSON value carries quotes, so it is written shell-quoted.
  printf 'MD_PRE_LINT=%q\n' "${MD_PRE_LINT-}" >> "$STATE"
  printf 'MD_PRE_TEST=%q\n' "${MD_PRE_TEST-}" >> "$STATE"
  printf 'MD_SETUP_BUILD=%q\n' "${MD_SETUP_BUILD-$SB_GREEN}" >> "$STATE"
  printf 'MD_PRE_BUILD=%q\n' "${MD_PRE_BUILD-}" >> "$STATE"
  # The run of the root, as run-lib.sh would name it: by default it works the
  # case's issue, and RUN_BEAD="" is a run that names no bead.
  jq -nc --arg root "${ROOT_ID-wisp-1}" --arg bead "${RUN_BEAD-$issue_id}" \
    '[{root: $root, convoy: "convoy-1", bead: $bead, formula: "mol-polecat-work", live: true}]' > "$TMP/runs.json"
  # The root carries gc.var.<name> for each var the pour rendered non-empty, as
  # gascity stamps it, and the stub splices these pairs into its metadata.
  local stamps
  stamps=$(pour_vars | jq -c 'with_entries(select(.value != "") | .key |= "gc.var." + .)')
  stamps=${stamps#\{}
  printf 'MD_ROOT_VARS=%q\n' "${stamps%\}}" >> "$STATE"
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
# GC_ITERATION default 1 keeps the gate cases far from the budget so they never
# trip the handback.
run_case() {
  local desc="$1" want="$2"
  : > "$CALLS"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 \
      GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$TMP/runs.json" \
      RUN_LIB_STUB_FAIL="${RUN_FAILS:+subject}" \
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
  unset ROOT_ID ISSUE_ID MD_ROOT_ISSUE RUN_BEAD RUN_FAILS GC_COLD
  unset MD_WORK_DIR MD_BRANCH MD_GATE MD_ROUTE MD_ABORTED_AT MD_MAX_ATTEMPTS MD_SUBJECT_MAX
  unset UPDATE_FAILS ITERATION MD_PRE_LINT MD_PRE_TEST MD_SETUP_BUILD MD_PRE_BUILD GCTK
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

# --- 3d4. the step's own block, rendered as a pour renders it -------------------
# The self-review step's check block, rendered with the case's commands, runs in
# the fixture worktree against the gctk built from this checkout. The root stub
# stamps the same commands, as a pour does, and the block's note of setup and
# build reaches the state the bd stub serves, so the exit condition reads what
# the block wrote.
ROOT="$(cd "$HERE/../.." && pwd)"
awk '
  /^```bash$/ {buf = ""; f = 1; next}
  /^```$/ {if (f && buf ~ /# >>> self-review-lease-keepalive/) {printf "%s", buf; exit} f = 0; next}
  f {buf = buf $0 "\n"}' "$ROOT/formulas/mol-polecat-work.toml" > "$TMP/checks.tmpl"
grep -qF 'self_review_setup_build=' "$TMP/checks.tmpl" \
  && ok "the self-review check block extracts, with its note of setup and build" \
  || bad "the self-review check block did not extract with its note of setup and build"
# render_checks : the block, each placeholder filled with what the case's pour
# renders (pour_vars).
render_checks() {
  jq -Rr --argjson v "$(pour_vars)" \
    'reduce ($v | to_entries[]) as $e (.; split("{{" + $e.key + "}}") | join($e.value))' "$TMP/checks.tmpl"
}
# run_checks <shell> : the rendered block in the fixture worktree.
run_checks() {
  render_checks > "$TMP/checks.sh"
  ( cd "$WT" && env GC_PACK_DIR="" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/no-city" GCTK_BIN="$GCTK_BUILT" \
      WORK_BEAD_ID="${ISSUE_ID-gc-issue}" CLAIMED_ITER_BEAD=iter-1 "$1" "$TMP/checks.sh" ) >"$TMP/checks.out" 2>&1
}
reset_env; render_checks > "$TMP/checks.sh"
grep -qF '{{' "$TMP/checks.sh" \
  && bad "the block renders with a placeholder pour_vars does not fill" \
  || ok "pour_vars fills every placeholder in the block"
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="bash zsh"
for sh in $SHELLS; do
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD='exit 1'; write_state
  run_checks "$sh"
  run_case "$sh: FAIL after the step's own block ran a build that fails on a clean tree" 1
  assert_out "$sh: …naming the build" "not green at $HEAD_SHA: build"
  # The note the block wrote is the last MD_SETUP_BUILD line in the state.
  # shellcheck disable=SC1090  # the generated state file the stubs read
  BLOCK_NOTE=$(MD_SETUP_BUILD=""; . "$STATE"; printf '%s' "$MD_SETUP_BUILD")
  eq "$(printf '%s' "$BLOCK_NOTE" | jq -r '[.commit, .setup, .build, .build_command] | join(" ")')" "$HEAD_SHA none fail exit 1" \
    "$sh: the block notes HEAD, no setup, the failed build and its command"
  printf 'MD_PRE_BUILD=%q\n' "$(premark "$HEAD_SHA" "$BLOCK_NOTE" tk-b1)" >> "$STATE"
  run_case "$sh: PASS once a pre-existing mark holds the note the block wrote" 0
  reset_env; MD_SETUP_BUILD=""; VAR_BUILD=true; write_state
  run_checks "$sh"
  run_case "$sh: PASS after the step's own block ran a build that passes" 0
  # What setup and build leave that git does not ignore is put back, so the
  # checks after them run, and the block notes them, in one run of the block.
  reset_env; MD_SETUP_BUILD=""; VAR_SETUP='printf rewritten > f'; VAR_BUILD='printf out > dist.txt'; write_state
  run_checks "$sh"
  run_case "$sh: PASS after the block ran a setup that rewrites a tracked file and a build that leaves a file" 0
  eq "$(git -C "$WT" status --porcelain)/$(cat "$WT/f")" "/more" "$sh: …which leaves the tree HEAD holds"
  # Whatever the case left must not reach the cases after it.
  git -C "$WT" reset -q --hard; git -C "$WT" clean -fdq
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
    eq "$(recorded lint | jq -r '.command')" "true" "$sh: …which leaves the pass of another command at HEAD"
    run_case "$sh: FAIL when the declared lint run stopped beside another command's pass at HEAD ($crash)" 1
    assert_out "$sh: …naming that pass as another run's" "lint: the record at $HEAD_SHA is of \"true\", not of the declared $(jq -nr --arg c "$crash" '$c | @json'), so it answers nothing here"
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
reset_env; MD_GATE="$HEAD_SHA"; write_state
record "$WT" test --scope affected --command true
record "$WT" lint --command true
run_case "FAIL when a check has no record, even beside a stamp naming HEAD" 1
assert_out "names the check with no record" "nothing recorded at $HEAD_SHA for: typecheck"

# --- 3f. a run poured before its checks were recorded --------------------------
# Such a run notes no setup and build either; its stamp certified them.
reset_env; MD_GATE="$HEAD_SHA"; MD_SETUP_BUILD=""; write_state
run_case "PASS on a stamp naming HEAD when nothing is recorded" 0
assert_out "says the stamp stood in" "by the stamp of a run poured before its checks were recorded"
reset_env; MD_GATE="$OLD_SHA"; MD_SETUP_BUILD=""; write_state
run_case "FAIL on a stamp naming an older HEAD when nothing is recorded" 1
reset_env; MD_GATE="$HEAD_SHA"; MD_SETUP_BUILD=""; write_state; green
run_case "PASS on a stamp naming HEAD in place of the setup and build note, beside records that pass" 0
# Records of runs the step does not declare say nothing about its own, so the
# stamp still stands in where they are all that HEAD holds.
reset_env; MD_GATE="$HEAD_SHA"; MD_SETUP_BUILD=""; write_state
record "$WT" test --scope full --command true; record "$WT" lint --command 'printf other'
run_case "PASS on a stamp naming HEAD where only records of other runs are" 0
reset_env; MD_GATE="$HEAD_SHA"; MD_SETUP_BUILD=$(noted "$HEAD_SHA" none fail); write_state; green
run_case "FAIL when the note at HEAD says the build failed, even beside a stamp naming HEAD" 1

# --- 3g. no gctk binary ------------------------------------------------------
reset_env; GCTK=none; write_state; green
run_case "FAIL (fail-closed) with no gctk binary to read the records" 1
assert_out "names the missing binary" "no gctk binary"

# --- 4. dirty worktree -------------------------------------------------------
reset_env; write_state; green
echo dirt > "$WT/untracked"
run_case "FAIL when the worktree is dirty" 1
assert_out "names the dirty-tree reason" "worktree is dirty"
rm -f "$WT/untracked"

# --- 4b. a read gctk cannot make ---------------------------------------------
# Config hides the untracked file from step 4's status but not from gctk's, so
# --check reads nothing, and the verdict gives gctk's reason, not a red check.
reset_env; write_state; green
git -C "$WT" config status.showUntrackedFiles no
echo dirt > "$WT/untracked"
run_case "FAIL when gctk rig --check reads nothing at HEAD" 1
assert_out "gives gctk's reason" "gctk rig test --check read nothing at $HEAD_SHA: gctk rig test: machine failure, nothing recorded: the checkout has changes HEAD does not hold"
assert_out "…naming the file" "?? untracked"
grep -qF "not green" "$TMP/out" && bad "it does not call the code red" || ok "it does not call the code red"
rm -f "$WT/untracked"; git -C "$WT" config --unset status.showUntrackedFiles

# --- 5. fail-closed on an absent worktree ------------------------------------
reset_env; MD_WORK_DIR="$TMP/does-not-exist"; write_state
run_case "FAIL (fail-closed) when recorded work_dir does not exist" 1

# --- 6. fail-closed on a non-git work_dir ------------------------------------
reset_env; MD_WORK_DIR="$TMP"; write_state
run_case "FAIL (fail-closed) when work_dir is not a git worktree" 1

# --- 7. fail-closed when the run is unreadable and no gc.var.issue -----------
reset_env; RUN_FAILS=1; MD_ROOT_ISSUE=""; write_state
run_case "FAIL (fail-closed) when the run of the root is unreadable and no gc.var.issue" 1

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
refute_call "resolution must not shell out to gc convoy" "gc convoy"

# --- 12. exhaustion handback -------------------------------------------------
# The last failing attempt (GC_ITERATION >= gc.max_attempts) hands the work bead
# back itself, because nothing runs after the budget is spent.
reset_env; MD_GATE=""; ITERATION=3; MD_MAX_ATTEMPTS=3; write_state
run_case "FAIL on the last attempt with nothing recorded" 1
assert_call "last attempt stamps aborted_at=self-review-exhausted" "aborted_at=self-review-exhausted"
assert_call "last attempt reassigns to the witness (derived from the pool route)" "gc-toolkit/gc-toolkit.witness"
assert_call "last attempt clears the pool route" "gc.routed_to="
assert_call "last attempt clears the drained session pins" "--unset-metadata gc.session_id"
assert_call "last attempt nudges the witness (best effort)" "gc session nudge gc-toolkit/gc-toolkit.witness"

# --- 13. exhaustion is idempotent --------------------------------------------
# A work bead already carrying aborted_at is left alone: a retried exec of the
# same attempt must not append a second handback.
reset_env; MD_GATE=""; ITERATION=3; MD_MAX_ATTEMPTS=3; MD_ABORTED_AT="self-review-exhausted"; write_state
run_case "FAIL on the last attempt when already aborted" 1
refute_call "does not re-stamp an already-aborted bead" "aborted_at=self-review-exhausted"

# --- 14. no handback before the budget is spent ------------------------------
reset_env; MD_GATE=""; ITERATION=2; MD_MAX_ATTEMPTS=3; write_state
run_case "FAIL mid-budget with nothing recorded" 1
refute_call "no handback before the last attempt" "aborted_at=self-review-exhausted"

# --- 15. budget read from the subject bead when carried there ----------------
reset_env; MD_GATE=""; ITERATION=3; MD_MAX_ATTEMPTS=""; MD_SUBJECT_MAX=3; write_state
run_case "FAIL on the last attempt with the budget on the subject bead" 1
assert_call "resolves the budget from the subject when the control list is empty" "aborted_at=self-review-exhausted"

echo
echo "self-review-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
