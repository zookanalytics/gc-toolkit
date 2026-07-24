#!/usr/bin/env bash
# Hermetic test for rebase-check.sh, the exit condition of the `rebase` check
# loop in mol-upstream-gc-rebase.
#
# This script decides whether a rebase is finished and safe to install/push, so
# every wrong PASS force-pushes an unverified history onto the fork's main
# branch and every wrong FAIL burns an iteration. The cases below pin both
# directions, with particular attention to the two ways a stale stamp could
# certify the wrong tree:
#
#   - check_passed_sha left over from an earlier HEAD (gate ran, then more
#     commits landed), and
#   - a `git rebase --abort` that returns HEAD to the pre-rebase tip, which an
#     old check_passed_sha stamped on that same tip would otherwise match.
#
# The second half pins the exhaustion handback: on the LAST failing attempt the
# script reassigns the work bead to the requesting keeper with
# `aborted_at=rebase-loop-exhausted`, because nothing else runs after the control
# bead closes `gc.outcome=fail`. Both directions matter — a handback one attempt
# early tells the operator a healthy loop failed, and a missing one strands the
# rebase with no pending item anywhere.
#
# EXECUTES the real shipped script against stub `bd` / `gc` binaries and a real
# temporary git repo. No live city, Dolt, network, or worktrees.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/rebase-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

[ -f "$SCRIPT" ] || { echo "missing $SCRIPT" >&2; exit 1; }

# --- stubs -------------------------------------------------------------------
# Both stubs read $TMP/state.env, so each case can vary the bead metadata the
# script sees without re-writing the stubs.
mkdir -p "$TMP/bin"

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# bd show <id> --json | bd dep tree <id> --json | bd list … --json | bd update <id> …
. "$STATE"
case "$1" in
dep)
  # bd dep tree <convoy> --json — the convoy plus its direct members, in the
  # shape the real command emits (depth 0 for the convoy itself, depth 1 with
  # parent_id set for each tracked member).
  if [ "$2" = "tree" ]; then
    [ "$DEP_TREE_FAILS" = "1" ] && { echo "stub: dep tree unavailable" >&2; exit 1; }
    printf '[{"id":"%s","depth":0,"parent_id":"","issue_type":"convoy"}' "$CONVOY_ID"
    i=1
    while [ "$i" -le "$CONVOY_MEMBERS" ]; do
      if [ "$i" = "1" ]; then
        member="$ISSUE_ID"
      else
        member="$ISSUE_ID-extra$i"
      fi
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
    [ -n "$MD_WORK_DIR" ]   && { printf '%s"work_dir":"%s"' "$sep" "$MD_WORK_DIR"; sep=","; }
    [ -n "$MD_ONTO" ]       && { printf '%s"rebase_onto_sha":"%s"' "$sep" "$MD_ONTO"; sep=","; }
    [ -n "$MD_GATE" ]       && { printf '%s"check_passed_sha":"%s"' "$sep" "$MD_GATE"; sep=","; }
    [ -n "$MD_KEEPER" ]     && { printf '%s"requesting_keeper":"%s"' "$sep" "$MD_KEEPER"; sep=","; }
    [ -n "$MD_NOTIFY" ]     && { printf '%s"notify_recipient":"%s"' "$sep" "$MD_NOTIFY"; sep=","; }
    [ -n "$MD_ABORTED_AT" ] && { printf '%s"aborted_at":"%s"' "$sep" "$MD_ABORTED_AT"; sep=","; }
    [ -n "$MD_BACKUP" ]     && { printf '%s"backup_ref":"%s"' "$sep" "$MD_BACKUP"; sep=","; }
    # conflict_questions as the formula writes it: a JSON array inside a string.
    # MD_QUESTIONS is a count; the entries are built here so the escaping
    # survives the state file instead of being mangled on the way in.
    if [ -n "$MD_QUESTIONS" ]; then
      printf '%s"conflict_questions":"[' "$sep"; sep=","
      i=1
      while [ "$i" -le "$MD_QUESTIONS" ]; do
        [ "$i" -gt 1 ] && printf ','
        printf '{\\"commit_sha\\":\\"sha%s\\"}' "$i"
        i=$((i + 1))
      done
      printf ']"'
    fi
    printf '}}]'
    ;;
  *)
    # An iteration bead: the root pointer for the GC_WISP_ID fallback, and the
    # gc.control_for lineage the budget lookup joins the control bead on.
    printf '[{"id":"%s","metadata":{"gc.root_bead_id":"%s","gc.control_for":"rebase"' "$2" "$ROOT_ID"
    [ -n "$MD_SUBJECT_MAX" ] && printf ',"gc.max_attempts":"%s"' "$MD_SUBJECT_MAX"
    printf '}}]'
    ;;
  esac
  ;;
list)
  # The ralph control-bead lookup (gc.root_bead_id + gc.kind=ralph).
  if [ -n "$MD_MAX_ATTEMPTS" ]; then
    printf '[{"id":"control-1","metadata":{"gc.kind":"ralph","gc.step_id":"rebase","gc.max_attempts":"%s"}}]' "$MD_MAX_ATTEMPTS"
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
  echo "city import compound-engineering ... locked but not cached at /nonexistent; run 'gc import install'" >&2
  exit 1
fi
if [ "$1" = "convoy" ]; then
  # Resolution must be bd-only (tk-9l9ka). Record the call so a regression that
  # reintroduces the dependency is visible, and fail the way a cold cache would.
  printf 'gc convoy %s\n' "$2" >> "$CALLS"
  echo "stub: rebase-check.sh must not shell out to gc convoy" >&2
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
# Every write the script attempts lands here, one line per call, so a case can
# assert on the handback without a live store.
export CALLS="$TMP/calls.log"

# --- fixture repo ------------------------------------------------------------
# UPSTREAM_SHA is the tip the rebase targets; HEAD carries one replayed commit
# on top of it. DIVERGENT_SHA models a commit that is NOT an ancestor of HEAD.
WT="$TMP/worktree"
mkdir -p "$WT"
git -C "$WT" init -q
git -C "$WT" config user.email t@example.com
git -C "$WT" config user.name  Test
echo base > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm base
UPSTREAM_SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q -b divergent
echo other > "$WT/g"; git -C "$WT" add g; git -C "$WT" commit -qm divergent
DIVERGENT_SHA=$(git -C "$WT" rev-parse HEAD)
git -C "$WT" checkout -q master 2>/dev/null || git -C "$WT" checkout -q main
echo kept > "$WT/f"; git -C "$WT" add f; git -C "$WT" commit -qm "kept commit"
HEAD_SHA=$(git -C "$WT" rev-parse HEAD)

write_state() {
  # MD_ROOT_ISSUE defaults to the convoy's member, mirroring a real molecule
  # root (verified on gc-wjkmo: gc.var.issue == the single member gc-c05nr).
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
MD_ONTO="${MD_ONTO-$UPSTREAM_SHA}"
MD_GATE="${MD_GATE-$HEAD_SHA}"
MD_KEEPER="${MD_KEEPER-gascity/gascity-keeper.keeper}"
MD_NOTIFY="${MD_NOTIFY-human}"
MD_ABORTED_AT="${MD_ABORTED_AT-}"
MD_BACKUP="${MD_BACKUP-refs/backup/pre-rebase-gc-issue}"
MD_QUESTIONS="${MD_QUESTIONS-}"
MD_MAX_ATTEMPTS="${MD_MAX_ATTEMPTS-25}"
MD_SUBJECT_MAX="${MD_SUBJECT_MAX-}"
UPDATE_FAILS="${UPDATE_FAILS-0}"
EOF
}

# Run the script in a cwd that is deliberately NOT the fixture worktree: the
# script must resolve the worktree from bead metadata, never from cwd.
# GC_ITERATION is the attempt the runtime is on; default 1 keeps the gate cases
# far from the budget so they never trip the handback.
run_case() {
  local desc="$1" want="$2"
  : > "$CALLS"
  ( cd "$TMP" && GC_WISP_ID="${ROOT_ID-wisp-1}" GC_BEAD_ID=iter-1 \
      GC_ITERATION="${ITERATION-1}" bash "$SCRIPT" ) >"$TMP/out" 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then
    ok "$desc (exit $got)"
  else
    bad "$desc (got exit $got, want $want)"
    sed 's/^/       /' "$TMP/out"
  fi
}

# Assertions over the writes the last run_case attempted.
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

reset_env() {
  unset ROOT_ID CONVOY_ID CONVOY_MEMBERS ISSUE_ID MD_WORK_DIR MD_ONTO MD_GATE
  unset MD_KEEPER MD_NOTIFY MD_ABORTED_AT MD_BACKUP MD_MAX_ATTEMPTS MD_SUBJECT_MAX MD_QUESTIONS
  unset UPDATE_FAILS ITERATION MD_ROOT_ISSUE DEP_TREE_FAILS GC_COLD
}

# --- 1. happy path -----------------------------------------------------------
reset_env; write_state
run_case "PASS when rebase is done, tree clean, and gate green at HEAD" 0

# --- 2. rebase still in progress --------------------------------------------
reset_env; write_state
mkdir -p "$WT/.git/rebase-merge"
run_case "FAIL while a rebase is in progress (rebase-merge)" 1
rmdir "$WT/.git/rebase-merge"

reset_env; write_state
mkdir -p "$WT/.git/rebase-apply"
run_case "FAIL while a rebase is in progress (rebase-apply)" 1
rmdir "$WT/.git/rebase-apply"

# --- 3. dirty worktree -------------------------------------------------------
reset_env; write_state
echo dirty >> "$WT/f"
run_case "FAIL when the worktree has uncommitted changes" 1
git -C "$WT" checkout -q -- f

# --- 4. gate not yet run -----------------------------------------------------
reset_env; MD_GATE=""; write_state
run_case "FAIL when no check_passed_sha is recorded" 1

# --- 5. stale gate stamp -----------------------------------------------------
reset_env; MD_GATE="$UPSTREAM_SHA"; write_state
run_case "FAIL when check_passed_sha is stale (gate ran at an older HEAD)" 1

# --- 6. the abort trap -------------------------------------------------------
# HEAD back at the pre-rebase tip with a matching stamp from an earlier run:
# the ancestry check is the only thing standing between this and a wrong PASS.
reset_env; MD_ONTO="$DIVERGENT_SHA"; MD_GATE="$HEAD_SHA"; write_state
run_case "FAIL when HEAD is not descended from rebase_onto_sha" 1

# --- 7. missing loop state ---------------------------------------------------
reset_env; MD_ONTO=""; write_state
run_case "FAIL when rebase_onto_sha was never stamped" 1

reset_env; MD_WORK_DIR=""; write_state
run_case "FAIL when the work bead has no work_dir" 1

reset_env; MD_WORK_DIR="$TMP/does-not-exist"; write_state
run_case "FAIL when the recorded work_dir is missing from disk" 1

reset_env; MD_WORK_DIR="$TMP"; write_state
run_case "FAIL when the recorded work_dir is not a git worktree" 1

reset_env; CONVOY_MEMBERS=0; write_state
run_case "FAIL when the convoy does not have exactly one tracked member" 1

# A convoy that gained a second member is just as malformed as an empty one:
# there is then no single work bead whose gate this script could certify.
reset_env; CONVOY_MEMBERS=2; write_state
run_case "FAIL when the convoy has more than one tracked member" 1

# --- 8. HEAD exactly at the upstream tip (empty kept set) --------------------
# A rebase that drops every divergent commit is legitimate: --is-ancestor is
# true for equal commits, so this must PASS rather than look like an abort.
git -C "$WT" checkout -q -B empty-kept "$UPSTREAM_SHA"
reset_env; MD_GATE="$UPSTREAM_SHA"; write_state
run_case "PASS when every commit was dropped and HEAD equals the upstream tip" 0

# --- 9. exhaustion handback --------------------------------------------------
# Back to the normal fixture (one kept commit on top of the upstream tip).
git -C "$WT" checkout -q -B kept "$HEAD_SHA"

# The last attempt fails: nothing runs after this, so the script itself has to
# put the work bead on the keeper's hook.
reset_env; MD_GATE=""; ITERATION=25; write_state
run_case "FAIL on the last attempt (gate never went green)" 1
assert_call "last attempt stamps aborted_at=rebase-loop-exhausted" "aborted_at=rebase-loop-exhausted"
assert_call "last attempt reassigns the work bead to the requesting keeper" "--assignee gascity/gascity-keeper.keeper"
assert_call "last attempt records the attempt count" "rebase_loop_attempts=25"
assert_call "last attempt nudges the keeper" "gc session nudge gascity/gascity-keeper.keeper"

# One attempt earlier the loop is healthy — a handback here would report a
# failure the operator does not have.
reset_env; MD_GATE=""; ITERATION=24; write_state
run_case "FAIL with budget left (attempt 24 of 25)" 1
refute_call "no handback while the loop still has attempts" "aborted_at="

# A green gate on the last attempt is a pass, not an exhaustion.
reset_env; ITERATION=25; write_state
run_case "PASS on the last attempt when the gate is green" 0
refute_call "a passing last attempt writes nothing to the work bead" "bd update"

# Idempotent: a retried exec of the same attempt (or an earlier abort path) must
# not append a second handback or overwrite the first reason.
reset_env; MD_GATE=""; MD_ABORTED_AT="install"; ITERATION=25; write_state
run_case "FAIL on the last attempt when aborted_at is already set" 1
refute_call "an existing aborted_at is left alone" "bd update"

# No keeper stamped at dispatch: fall back to notify_recipient, the same
# fallback the install/push aborts use.
reset_env; MD_GATE=""; MD_KEEPER=""; ITERATION=25; write_state
run_case "FAIL on the last attempt with no requesting_keeper" 1
assert_call "handback falls back to notify_recipient" "--assignee human"

# Neither stamped: still record the abort durably, just with no one to route to.
reset_env; MD_GATE=""; MD_KEEPER=""; MD_NOTIFY=""; ITERATION=25; write_state
run_case "FAIL on the last attempt with no keeper and no notify_recipient" 1
assert_call "handback still stamps aborted_at with no route" "aborted_at=rebase-loop-exhausted"
refute_call "handback assigns nobody when no route is known" "--assignee"
refute_call "handback nudges nobody when no route is known" "session nudge"

# An unresolvable budget must not be guessed: no control bead, no handback.
reset_env; MD_GATE=""; MD_MAX_ATTEMPTS=""; ITERATION=25; write_state
run_case "FAIL when the budget cannot be resolved" 1
refute_call "an unknown budget never triggers a handback" "bd update"

# GC_BEAD_ID can be the control bead itself (no subject); the budget is then
# already on the bead the script was handed.
reset_env; MD_GATE=""; MD_MAX_ATTEMPTS=""; MD_SUBJECT_MAX=25; ITERATION=25; write_state
run_case "FAIL on the last attempt with the budget on the subject bead" 1
assert_call "budget read from the subject bead still hands back" "aborted_at=rebase-loop-exhausted"

# The operator's first question is "what was it stuck on" — the note carries the
# count of recorded conflict questions, read out of the JSON-in-a-string field.
reset_env; MD_GATE=""; ITERATION=25; MD_QUESTIONS=2; write_state
run_case "FAIL on the last attempt with conflict questions recorded" 1
assert_call "handback note counts the recorded conflict questions" "Recorded conflict questions: 2"
assert_call "handback note points at the worktree and backup ref" "refs/backup/pre-rebase-gc-issue"

# A refused write must not turn a FAIL into a PASS.
reset_env; MD_GATE=""; UPDATE_FAILS=1; ITERATION=25; write_state
run_case "FAIL is preserved when the handback write is refused" 1

# Failing before the work bead is resolved leaves nothing to stamp — the loop
# still reports FAIL rather than erroring out mid-handback.
reset_env; CONVOY_MEMBERS=0; ITERATION=25; write_state
run_case "FAIL on the last attempt before the work bead resolves" 1
refute_call "no handback without a resolved work bead" "bd update"

# --- 10. bd-only work-bead resolution (tk-9l9ka) -----------------------------
# The regression this section guards: resolution used to go through
# `gc convoy status`, which loads the city import closure. With any import cold
# in the condition env that call dies, the work bead came back empty, and the
# script failed here on every iteration — blind to an already-green gate, and
# with the exhaustion handback suppressed because it is gated on a resolved
# work bead. Nothing about deciding "is this rebase done" needs gc.

# The headline case: a green gate must still be certified when gc is unusable.
reset_env; GC_COLD=1; write_state
run_case "PASS with a green gate when every gc call dies on a cold import cache" 0
refute_call "resolution never shells out to gc convoy" "gc convoy"

# The same env must still produce correct FAILs, not just correct PASSes — a
# checker that ignored gc by always passing would satisfy the case above.
reset_env; GC_COLD=1; MD_GATE="$UPSTREAM_SHA"; write_state
run_case "FAIL on a stale gate stamp with a cold import cache" 1

# The bug's worst consequence: an exhausted loop that stranded the rebase with
# no aborted_at and nothing on anyone's hook. The handback needs the work bead,
# so it only works once resolution stops depending on gc.
reset_env; GC_COLD=1; MD_GATE=""; ITERATION=25; write_state
run_case "FAIL on the last attempt with a cold import cache" 1
assert_call "exhaustion handback still fires when gc is unusable" "aborted_at=rebase-loop-exhausted"
assert_call "cold-cache handback still routes to the keeper" "--assignee gascity/gascity-keeper.keeper"

# Fallback: membership unreadable (bd hiccup, not a malformed convoy) falls back
# to the work bead id the root carries.
reset_env; DEP_TREE_FAILS=1; write_state
run_case "PASS via the root's gc.var.issue when convoy membership is unreadable" 0

reset_env; DEP_TREE_FAILS=1; MD_ROOT_ISSUE=""; write_state
run_case "FAIL when membership is unreadable and the root has no gc.var.issue" 1

# Cross-check: two readable sources that disagree mean the molecule is wired
# wrong. Certifying a gate against the wrong bead is the false pass this whole
# script exists to prevent, so it must refuse rather than pick a side.
reset_env; MD_ROOT_ISSUE="gc-some-other-bead"; write_state
run_case "FAIL when the root's gc.var.issue disagrees with convoy membership" 1

# A root with no gc.var.issue at all (older molecule) still resolves from
# membership alone.
reset_env; MD_ROOT_ISSUE=""; write_state
run_case "PASS from convoy membership alone when the root has no gc.var.issue" 0

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
