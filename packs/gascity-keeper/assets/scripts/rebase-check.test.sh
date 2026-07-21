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
# bd show <id> --json | bd list … --json | bd update <id> …
. "$STATE"
case "$1" in
show)
  case "$2" in
  "$ROOT_ID")
    printf '[{"id":"%s","metadata":{"gc.input_convoy_id":"%s"}}]' "$ROOT_ID" "$CONVOY_ID"
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
# gc convoy status <convoy> --json | gc session nudge <target> <message>
. "$STATE"
if [ "$1" = "convoy" ] && [ "$2" = "status" ]; then
  if [ "$CONVOY_MEMBERS" = "1" ]; then
    printf '{"children":[{"id":"%s"}]}' "$ISSUE_ID"
  else
    printf '{"children":[]}'
  fi
  exit 0
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
  cat > "$STATE" <<EOF
ROOT_ID="${ROOT_ID-wisp-1}"
CONVOY_ID="${CONVOY_ID-convoy-1}"
CONVOY_MEMBERS="${CONVOY_MEMBERS-1}"
ISSUE_ID="${ISSUE_ID-gc-issue}"
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
  unset UPDATE_FAILS ITERATION
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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
