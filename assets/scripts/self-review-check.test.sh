#!/usr/bin/env bash
# Test for self-review-check.sh — the exit condition of the self-review check
# loop in mol-polecat-work.
#
# It EXECUTES the real shipped script against stub `bd` / `gc` binaries and a
# real fixture git worktree, so the exit-code contract (0 verified-green, 1
# everything else, fail-closed on any unreadable state) and the exhaustion
# handback are pinned against the code that ships, not a paraphrase.
set -uo pipefail

TMP="$(mktemp -d "${TMPDIR:-/tmp}/self-review-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SCRIPT="$(cd "$(dirname "$0")" && pwd)/self-review-check.sh"
[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# --- stubs -------------------------------------------------------------------
# Both stubs read $TMP/state.env, so each case varies the bead metadata the
# script sees without re-writing the stubs.
mkdir -p "$TMP/bin"

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
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

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
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
MD_GATE="${MD_GATE-$HEAD_SHA}"
MD_ROUTE="${MD_ROUTE-gc-toolkit/gc-toolkit.polecat}"
MD_ABORTED_AT="${MD_ABORTED_AT-}"
MD_MAX_ATTEMPTS="${MD_MAX_ATTEMPTS-3}"
MD_SUBJECT_MAX="${MD_SUBJECT_MAX-}"
UPDATE_FAILS="${UPDATE_FAILS-0}"
EOF
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
# GC_ITERATION default 1 keeps the gate cases far from the budget so they never
# trip the handback.
run_case() {
  local desc="$1" want="$2"
  : > "$CALLS"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 \
      GC_ITERATION="${ITERATION-1}" bash "$SCRIPT" ) >"$TMP/out" 2>&1
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
  unset UPDATE_FAILS ITERATION
}

# --- 1. happy path -----------------------------------------------------------
reset_env; write_state
run_case "PASS when tree is clean and the stamp names HEAD" 0
assert_out "PASS names the verified HEAD" "PASS: self-review green"

# --- 2. gate not yet run -----------------------------------------------------
reset_env; MD_GATE=""; write_state
run_case "FAIL when no self_review_passed_sha is recorded" 1
assert_out "says the checks have not passed yet" "not passed yet"

# --- 3. stale stamp ----------------------------------------------------------
reset_env; MD_GATE="$OLD_SHA"; write_state
run_case "FAIL when the stamp is stale (an older HEAD)" 1
assert_out "names the stale-stamp reason" "stamp is stale"

# --- 4. dirty worktree -------------------------------------------------------
reset_env; write_state
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
reset_env; DEP_TREE_FAILS=1; write_state
run_case "PASS via gc.var.issue fallback when membership is unreadable but the stamp is green" 0
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
reset_env; GC_COLD=1; write_state
run_case "PASS under a cold gc (resolution is bd-only)" 0
refute_call "resolution must not shell out to gc convoy" "gc convoy"

# --- 12. exhaustion handback -------------------------------------------------
# The last failing attempt (GC_ITERATION >= gc.max_attempts) hands the work bead
# back itself, because nothing runs after the budget is spent.
reset_env; MD_GATE=""; ITERATION=3; MD_MAX_ATTEMPTS=3; write_state
run_case "FAIL on the last attempt with no green stamp" 1
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
run_case "FAIL mid-budget without a green stamp" 1
refute_call "no handback before the last attempt" "aborted_at=self-review-exhausted"

# --- 15. budget read from the subject bead when carried there ----------------
reset_env; MD_GATE=""; ITERATION=3; MD_MAX_ATTEMPTS=""; MD_SUBJECT_MAX=3; write_state
run_case "FAIL on the last attempt with the budget on the subject bead" 1
assert_call "resolves the budget from the subject when the control list is empty" "aborted_at=self-review-exhausted"

echo
echo "self-review-check: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
