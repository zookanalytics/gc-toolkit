#!/usr/bin/env bash
# Test for self-review-check.sh — the exit condition of the self-review check
# loop in mol-polecat-work.
#
# It EXECUTES the real shipped script against stub `bd` / `gc` binaries, a real
# fixture git worktree, and the real `gctk` built from this checkout, whose
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
# bd show <id> --json | bd dep tree <id> --json | bd list … --json | bd update <id> …
. "$STATE"
case "$1" in
dep)
  if [ "$2" = "tree" ]; then
    [ "$DEP_TREE_FAILS" = "1" ] && { echo "stub: dep tree unavailable" >&2; exit 1; }
    printf '[{"id":"%s","depth":0,"parent_id":"","issue_type":"convoy"}' "$CONVOY_ID"
    i=1
    while [ "$i" -le "$CONVOY_MEMBERS" ]; do
      if [ "$i" = "1" ]; then member="$ISSUE_ID"; else member="$ISSUE_ID-extra$i"; fi
      printf ',{"id":"%s","depth":1,"parent_id":"%s","issue_type":"task"}' "$member" "$CONVOY_ID"
      i=$((i + 1))
    done
    printf ']'
    exit 0
  fi
  exit 1
  ;;
show)
  case "$2" in
  "$ROOT_ID")
    printf '[{"id":"%s","metadata":{"gc.input_convoy_id":"%s"' "$ROOT_ID" "$CONVOY_ID"
    [ -n "$MD_ROOT_ISSUE" ] && printf ',"gc.var.issue":"%s"' "$MD_ROOT_ISSUE"
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

write_state() {
  local issue_id="${ISSUE_ID-gc-issue}"
  cat > "$STATE" <<EOF
ROOT_ID="${ROOT_ID-wisp-1}"
CONVOY_ID="${CONVOY_ID-convoy-1}"
CONVOY_MEMBERS="${CONVOY_MEMBERS-1}"
ISSUE_ID="$issue_id"
MD_ROOT_ISSUE="${MD_ROOT_ISSUE-$issue_id}"
DEP_TREE_FAILS="${DEP_TREE_FAILS-0}"
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
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
# GC_ITERATION default 1 keeps the gate cases far from the budget so they never
# trip the handback.
run_case() {
  local desc="$1" want="$2"
  : > "$CALLS"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 \
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
  unset ROOT_ID CONVOY_ID CONVOY_MEMBERS ISSUE_ID MD_ROOT_ISSUE DEP_TREE_FAILS GC_COLD
  unset MD_WORK_DIR MD_BRANCH MD_GATE MD_ROUTE MD_ABORTED_AT MD_MAX_ATTEMPTS MD_SUBJECT_MAX
  unset UPDATE_FAILS ITERATION MD_PRE_LINT MD_PRE_TEST GCTK
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
reset_env; write_state; green; record "$WT" lint --command false
run_case "FAIL when a check's record at HEAD is a fail" 1
assert_out "names the red check" "not green at $HEAD_SHA: lint"

# --- 3d. a red check marked pre-existing at HEAD ------------------------------
reset_env; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)" tk-t1); write_state
run_case "PASS when the red check's record is marked pre-existing at HEAD" 0
assert_out "names the tracker that carries it" "pre-existing, tracked by tk-t1"

reset_env; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$OLD_SHA" "$(recorded lint)" tk-t1); write_state
run_case "FAIL when the pre-existing mark names another commit" 1

reset_env; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)"); write_state
run_case "FAIL when the pre-existing mark names no tracker" 1

# --- 3d2. a run that replaced the marked record --------------------------------
# gctk rig replaces a commit's record when a call declares another run, and the
# new run's fail is not the one judged pre-existing.
reset_env; green; record "$WT" lint --command false
MD_PRE_LINT=$(premark "$HEAD_SHA" "$(recorded lint)" tk-t1); write_state
record "$WT" lint --command 'exit 3'
run_case "FAIL when a run with another command replaced the marked record at HEAD" 1
assert_out "says the mark judged another run" "judged another run's fail"

reset_env; green; record "$WT" test --scope affected --command false
MD_PRE_TEST=$(premark "$HEAD_SHA" "$(recorded test)" tk-t1); write_state
record "$WT" test --scope full --command false
run_case "FAIL when a full-suite run replaced the marked record of the affected subset" 1

# --- 3e. some checks recorded, one not ----------------------------------------
reset_env; MD_GATE="$HEAD_SHA"; write_state
record "$WT" test --scope affected --command true
record "$WT" lint --command true
run_case "FAIL when a check has no record, even beside a stamp naming HEAD" 1
assert_out "names the check with no record" "nothing recorded at $HEAD_SHA for: typecheck"

# --- 3f. a run poured before its checks were recorded --------------------------
reset_env; MD_GATE="$HEAD_SHA"; write_state
run_case "PASS on a stamp naming HEAD when nothing is recorded" 0
assert_out "says the stamp stood in" "by the stamp of a run poured before its checks were recorded"
reset_env; MD_GATE="$OLD_SHA"; write_state
run_case "FAIL on a stamp naming an older HEAD when nothing is recorded" 1

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

# --- 5. fail-closed on an absent worktree ------------------------------------
reset_env; MD_WORK_DIR="$TMP/does-not-exist"; write_state
run_case "FAIL (fail-closed) when recorded work_dir does not exist" 1

# --- 6. fail-closed on a non-git work_dir ------------------------------------
reset_env; MD_WORK_DIR="$TMP"; write_state
run_case "FAIL (fail-closed) when work_dir is not a git worktree" 1

# --- 7. fail-closed when membership is unreadable and no gc.var.issue --------
reset_env; DEP_TREE_FAILS=1; MD_ROOT_ISSUE=""; write_state
run_case "FAIL (fail-closed) when convoy membership is unreadable and no gc.var.issue" 1

# --- 8. resilient fallback: membership unreadable but gc.var.issue set --------
reset_env; DEP_TREE_FAILS=1; write_state; green
run_case "PASS via gc.var.issue fallback when membership is unreadable but the records are green" 0
assert_out "warns that the one-member invariant went unverified" "membership unverified"

# --- 9. fail-closed on a malformed convoy (two members) ----------------------
reset_env; CONVOY_MEMBERS=2; write_state
run_case "FAIL (fail-closed) when the convoy has more than one tracked member" 1

# --- 10. fail-closed when gc.var.issue disagrees with the member -------------
reset_env; MD_ROOT_ISSUE="gc-other"; write_state
run_case "FAIL (fail-closed) when gc.var.issue disagrees with the convoy member" 1

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
