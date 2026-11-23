#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-setup.sh, mol-polecat-work's
# workspace-setup.
#
# It runs against a real git repository with a real bare origin. The compiled
# fake gc keeps the bead in the harness's store, which its reads serve and its
# writes change, and a wrapper runs the real git. Both record each call in one
# log, and the wrapper copies the store when a merge starts, so a case can read
# what the bead carried before the merge moved HEAD. The pack scripts it calls
# past the bead are stubs that record their calls, except hand-back.sh,
# decline.sh and work-lib.sh, which are the real ones, and run-lib.stub.sh
# answers which runs work a bead. No live city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-setup-test.XXXXXX")"
# git prints a worktree by its resolved path.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" tag.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

BASE="integration/c1"
PACK="$TMP/pack"; mkdir -p "$PACK"
cp "$HERE/work-setup.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/bd-lib.sh" "$HERE/hand-back.sh" "$PACK/"
RUNS="$TMP/runs.json"
# The runs file answers run-lib.sh, not the runs of the store.
export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$RUNS"
unset RUN_LIB_STUB_CMD
# One log holds the fake gc's calls, git's and the stub pack scripts', in order.
export REAL_GIT CALLS="$STUB_GC_LOG" STORE="$STUB_STORE" AT_MERGE="$TMP/store-at-merge.json" RIG_ROOT_STUB="$TMP/rig"

cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "merge" ]; then cp "$STORE" "$AT_MERGE"; fi
exec "$REAL_GIT" "$@"
SH
# The fake gc answers the store. A case sets STUB_LIST_FAIL for a store whose
# list does not answer, STUB_LIST_OBJECT for one that answers with no array,
# STUB_SHOW_FAIL for a show that does not answer, STUB_UPDATE_FAIL=tk-w for a
# store that refuses every write, and STUB_UPDATE_FAIL_ON for one that refuses
# the write carrying a text, as an outage or a guard does. STUB_HOOK_CURRENT is
# the claim gc hook current names, and STUB_SESSIONS the session list.
chmod +x "$BIN/git"

recorder() { # <name> <log word>
  cat > "$PACK/$1" <<STUB
#!/usr/bin/env bash
printf '$2 %s\n' "\$*" >> "\$CALLS"
exit "\${$3:-0}"
STUB
  chmod +x "$PACK/$1"
}
recorder await-ruling.sh await AWAIT_RC
recorder run-cancel.sh cancel CANCEL_RC
recorder human-gate.sh gate GATE_RC
cat > "$PACK/rig-root.sh" <<'SH'
#!/usr/bin/env bash
[ -z "${NO_RIG_ROOT:-}" ] || exit 0
printf '%s\n' "$RIG_ROOT_STUB"
SH
chmod +x "$PACK/rig-root.sh"
cat > "$PACK/bring-current-audit.sh" <<'SH'
#!/usr/bin/env bash
printf 'bca %s\n' "$*" >> "$CALLS"
verb="${1:-}"; shift; bead=""
while [ $# -gt 0 ]; do case "$1" in --bead) bead="${2:-}"; shift 2 ;; *) shift ;; esac; done
case "$verb" in
  add) gc bd update "$bead" --set-metadata 'conflict_audit=[{"path":"shared.txt"}]' ;;
  ask) [ -z "${ASK_FAIL:-}" ] || exit 1; gc bd update "$bead" --set-metadata 'conflict_question={"paths":["shared.txt"]}' ;;
  anchor) a=$(gc --harness-read meta "$bead" anchor_bead); [ "$a" != "<absent>" ] || a="$bead"; printf '%s\n' "$a" ;;
esac
SH
chmod +x "$PACK/bring-current-audit.sh"

# --- Histories. ------------------------------------------------------------------
g() { "$REAL_GIT" -C "$@"; }
commit_in() { # <repo> <file> <content> <message>
  printf '%s\n' "$3" > "$1/$2"
  g "$1" add "$2" && g "$1" commit -qm "$4"
}
O="$TMP/origin.git"
"$REAL_GIT" init -q --bare "$O"
SEED="$TMP/seed"
"$REAL_GIT" clone -q "$O" "$SEED" 2>/dev/null
commit_in "$SEED" shared.txt "merge base" "the merge base"
g "$SEED" push -q origin HEAD:main
g "$SEED" checkout -q -b polecat/w1 origin/main
commit_in "$SEED" work.txt "work" "the PR's change"
g "$SEED" push -q origin polecat/w1
g "$SEED" checkout -q -b polecat/w2 origin/main
commit_in "$SEED" shared.txt "PR side" "the PR edits shared.txt"
g "$SEED" push -q origin polecat/w2
g "$SEED" checkout -q -b "$BASE" origin/main
commit_in "$SEED" moved.txt "moved" "the base moves"
commit_in "$SEED" shared.txt "base side" "the base edits shared.txt"
g "$SEED" push -q origin "$BASE"
W1="$(g "$O" rev-parse refs/heads/polecat/w1)"
W2="$(g "$O" rev-parse refs/heads/polecat/w2)"
BASE_TIP="$(g "$O" rev-parse "refs/heads/$BASE")"

# clone <branch> — a fresh clone at $C with <branch> checked out, and an origin of
# its own at $CO, a copy of $O, so a case's fetches stay its own.
N=0
clone() {
  N=$((N + 1)); C="$TMP/clone-$N"; CO="$TMP/origin-$N.git"
  cp -R "$O" "$CO"
  "$REAL_GIT" clone -q "$CO" "$C" && g "$C" checkout -q -B "$1" "origin/$1"
}

# setup_run <bead-json> [<VAR=value>...] — a fresh call log and a store holding that
# bead, then the script in $C. Sets RC and OUT (stdout).
setup_run() {
  local bead="$1"; shift
  : > "$CALLS"; rm -f "$AT_MERGE"
  printf '%s' "$bead" > "$STORE"
  again "$@"
}
# again [<VAR=value>...] — the script run in $C against the store as the last run
# left it, the way the bead's next run reaches it.
again() {
  OUT=$(cd "$C" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me "$@" "$PACK/work-setup.sh" --bead tk-w --base "$BASE" 2>"$TMP/err"); RC=$?
}
tool() { # <args...> — another mode of the script, in $C
  OUT=$(cd "$C" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me ${TOOL_ENV:-} "$PACK/work-setup.sh" "$@" 2>"$TMP/err"); RC=$?
}
set_meta() { # <key> <value> — what another writer put on the bead between runs, through bd
  STUB_GC_LOG=/dev/null gc bd update tk-w --set-metadata "$1=$2" >/dev/null
}
# row <id> <metadata members> [<status>] [<assignee>] — a bead's row, open and
# unassigned unless a status and an assignee are given.
row() {
  printf '{"id":%s,"status":%s,"assignee":%s,"metadata":{%s}}' \
    "$(json_str "$1")" "$(json_str "${3:-open}")" "$(json_str "${4:-}")" "$2"
}
# kv <key> <value>... — JSON members, each value a string.
kv() {
  local out=""
  while [ $# -ge 2 ]; do out+="${out:+,}$(json_str "$1"):$(json_str "$2")"; shift 2; done
  printf '%s' "$out"
}
# rejected <reason> [<members>] — the metadata of a bead a check sent back: its
# rejection reason, and any further JSON members.
rejected() { printf '{"rejection_reason":%s%s}' "$(json_str "$1")" "${2:+,$2}"; }
# bead <branch> [<metadata json>] [<status> <assignee>] — the bead, its work_dir
# the clone. A key the metadata repeats takes the metadata's value.
bead() {
  local m="${2:-}"; m="${m#\{}"; m="${m%\}}"
  printf '[%s]' "$(row tk-w "$(kv branch "$1" work_dir "$C")${m:+,$m}" "${3:-open}" "${4:-}")"
}
# meta <key> [<id>] — the key on the bead, tk-w unless another is named, read
# through the fake.
meta() { "$HARNESS_FAKE_GC" --harness-read meta "${2:-tk-w}" "$1"; }
at_merge() { if [ -f "$AT_MERGE" ]; then STUB_STORE="$AT_MERGE" meta "$1"; else echo "<no merge ran>"; fi; }
parents() { g "$C" rev-list --parents -n 1 HEAD | cut -d' ' -f2-; }
called() { grep -qxF -- "$1" "$CALLS"; }
rewrites() { grep -cE '^git (rebase|push|reset|commit|cherry-pick|am)( |$)' "$CALLS"; }
last_line() { printf '%s\n' "$OUT" | tail -n 1; }

echo "# a rejected branch is brought current by merging the base in"
clone polecat/w1
MERGE_ONLY="Conflicts with $BASE at $BASE_TIP"
setup_run "$(bead polecat/w1 "$(rejected "$MERGE_ONLY" '"prepare_mode":"merge","conflict_audit":"entries from an earlier round",
  "conflict_question":"a question from an earlier round"')")"
eq "$RC" "0" "(1) the resume exits 0"
eq "$(parents)" "$W1 $BASE_TIP" "(1) HEAD is a merge commit of the PR head and origin/$BASE, in that order"
called "git merge --no-edit origin/$BASE" \
  && ok "(1) the base is merged in by git merge --no-edit origin/$BASE" \
  || bad "(1) the base is merged in by git merge --no-edit origin/$BASE" "$(grep '^git ' "$CALLS" | tr '\n' ';')"
eq "$(rewrites)" "0" "(1) nothing rebases, resets, commits, cherry-picks or pushes"
eq "$(g "$CO" rev-parse refs/heads/polecat/w1)" "$W1" "(1) origin's branch is untouched: the resume pushes nothing"
eq "$(at_merge bring_current_from)" "$W1" "(1) before the merge runs, bring_current_from is the PR head"
eq "$(at_merge bring_current_scope)" "merge-only" "(1) before the merge runs, the conflict rejection's scope is merge-only"
eq "$(at_merge conflict_audit) $(at_merge conflict_question)" "<absent> <absent>" "(1) before the merge runs, the last round's audit and question are cleared"
eq "$(meta bring_current_from) $(meta bring_current_scope)" "$W1 merge-only" "(1) the round stays on the bead for the hand-off to read"
eq "$(meta rejection_reason)" "<absent>" "(1) rejection_reason is unset"
eq "$(last_line)" "$C" "(1) the last line printed is the worktree"

g "$C" push -q origin HEAD:polecat/w1 >/dev/null 2>&1 \
  && ok "(2) a push with no force flag fast-forwards the PR branch" \
  || bad "(2) a push with no force flag fast-forwards the PR branch" "rejected: the resume rewrote the branch"

for m in '{"rejection_reason":"tests failed","prepare_mode":"rebase"}' '{"rejection_reason":"tests failed"}'; do
  case "$m" in *prepare_mode*) label="prepare_mode=rebase" ;; *) label="no prepare_mode" ;; esac
  clone polecat/w1
  setup_run "$(bead polecat/w1 "$m")"
  eq "$(parents)" "$W1 $BASE_TIP" "(3) $label: the branch is merged, its PR head kept"
  eq "$(rewrites)" "0" "(3) $label: nothing rebases, resets, commits, cherry-picks or pushes"
done

echo "# a conflicting merge is left mid-merge for the worker"
clone polecat/w2
CONFLICTS="Conflicts with $BASE at $BASE_TIP; resume in prepare_mode=merge"
setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS" '"prepare_mode":"merge"')")"
eq "$RC" "3" "(4) a conflict exits 3"
eq "$(last_line)" "$C" "(4) the last line printed is still the worktree"
has "$(cat "$TMP/err")" "shared.txt" "(4) the conflicted file is listed"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(4) the clone is mid-merge, merging origin/$BASE"
eq "$(g "$C" diff --name-only --diff-filter=U)" "shared.txt" "(4) the conflict is left for the worker to resolve"
eq "$(g "$C" rev-parse HEAD)" "$W2" "(4) HEAD is still the PR head"
GITDIR="$(g "$C" rev-parse --absolute-git-dir)"
{ [ ! -e "$GITDIR/rebase-merge" ] && [ ! -e "$GITDIR/rebase-apply" ]; } && ok "(4) no rebase is in progress" || bad "(4) no rebase is in progress"
eq "$(rewrites)" "0" "(4) nothing rebases, resets, commits, cherry-picks or pushes"
eq "$(meta rejection_reason)" "$CONFLICTS" "(4) the rejection stays while the merge is unconcluded"

echo "# a local commit origin has not seen leaves the stamp at origin's copy of the branch"
clone polecat/w1
commit_in "$C" local.txt "local" "a commit origin has not seen"
AHEAD="$(g "$C" rev-parse HEAD)"
setup_run "$(bead polecat/w1 '{"rejection_reason":"tests failed"}')"
eq "$(at_merge bring_current_from)" "$W1" "(5) bring_current_from is the PR head origin holds, not the local commit past it"
eq "$(parents)" "$AHEAD $BASE_TIP" "(5) the base is merged into the local head"

echo "# a branch origin does not have is stamped with HEAD from before the merge"
clone polecat/w1
g "$C" checkout -q -b polecat/w3
commit_in "$C" local.txt "local" "a commit origin never saw"
LOCAL="$(g "$C" rev-parse HEAD)"
setup_run "$(bead polecat/w3 '{"rejection_reason":"tests failed"}')"
eq "$(at_merge bring_current_from)" "$LOCAL" "(6) bring_current_from is the head the resume started from, not its merge commit"
eq "$(parents)" "$LOCAL $BASE_TIP" "(6) the base is merged in"

echo "# without a rejection nothing merges"
for m in '' '{"rejection_reason":""}'; do
  case "$m" in '') label="no rejection_reason" ;; *) label="an empty rejection_reason" ;; esac
  clone polecat/w1
  setup_run "$(bead polecat/w1 "$m")"
  eq "$RC" "0" "(7) $label: exits 0"
  eq "$(g "$C" rev-parse HEAD)" "$W1" "(7) $label: HEAD stays at the PR head"
  eq "$(grep -c '^git merge --no-edit' "$CALLS")" "0" "(7) $label: nothing merges the base in"
done

echo "# the scope is merge-only for a conflict rejection, and with-work for any other"
scope_case() { # <label> <rejection_reason> <scope>
  clone polecat/w1
  setup_run "$(bead polecat/w1 "$(rejected "$2")")"
  eq "$(at_merge bring_current_scope)" "$3" "(8) $1 is stamped $3 before the merge runs"
}
scope_case "a conflict rejection" "$CONFLICTS" merge-only
scope_case "a failed-tests rejection" "tests failed" with-work

echo "# a round that does not land stops before the merge"
clone polecat/w1
printf '%s' "$(bead polecat/w1 '{"rejection_reason":"tests failed"}')" > "$STORE"
: > "$CALLS"; rm -f "$AT_MERGE"
again STUB_UPDATE_FAIL=tk-w
eq "$RC" "1" "(9) exits 1"
eq "$(grep -c '^git merge --no-edit' "$CALLS")" "0" "(9) git merge is not run"
eq "$(g "$C" rev-parse HEAD)" "$W1" "(9) HEAD stays at the PR head"
eq "$(meta rejection_reason)" "tests failed" "(9) rejection_reason stays, so a re-run resumes the same rejection"

echo "# the commit that concludes a conflicted merge clears the rejection"
clone polecat/w2
setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS")")"
printf 'both sides\n' > "$C/shared.txt"; g "$C" add shared.txt
tool --conclude-merge --bead tk-w
eq "$RC" "0" "(11) --conclude-merge exits 0"
eq "$(parents)" "$W2 $BASE_TIP" "(11) its commit concludes the merge"
eq "$(meta rejection_reason)" "<absent>" "(11) and clears the rejection"

echo "# a merge that does not conclude leaves the rejection"
clone polecat/w2
setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS")")"
tool --conclude-merge --bead tk-w
[ "$RC" != "0" ] && ok "(12) a commit git refuses, the conflict unresolved, fails --conclude-merge" || bad "(12) a commit git refuses, the conflict unresolved, fails --conclude-merge" "it exited 0"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(12) the merge is still in progress"
eq "$(meta rejection_reason)" "$CONFLICTS" "(12) and the rejection stays"
clone polecat/w2
printf 'an edit nobody committed\n' > "$C/shared.txt"
setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS")")"
eq "$RC" "1" "(13) a merge git refuses to start exits 1"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "" "(13) git refuses to start a merge over an uncommitted edit"
eq "$(meta rejection_reason)" "$CONFLICTS" "(13) and the rejection stays"

echo "# a stop to ask a person leaves the rejection, so the next run merges again"
for how in molecule bare; do
  clone polecat/w2
  setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS" '"anchor_bead":"tk-a"')" in_progress sess-me)"
  set_meta conflict_audit '[{"path":"resolved-before-the-stop.txt"}]'
  : > "$CALLS"
  if [ "$how" = molecule ]; then
    TOOL_ENV=STUB_HOOK_CURRENT=tk-step tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
    grep -q '^cancel --step mol-polecat-work.workspace-setup ' "$CALLS" && ok "(14) molecule: and its run is cancelled" || bad "(14) molecule: and its run is cancelled"
  else
    TOOL_ENV=STUB_HOOK_CURRENT=tk-w tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
    eq "$(grep -c '^cancel ' "$CALLS")" "0" "(14) bare: no run works it, so nothing is cancelled"
    has "$(notes tk-w)" "Stopped bringing the branch current" "(14) bare: its notes say why it stopped"
  fi
  grep -q '^await tk-w --key bring-current-question\.tk-w --subject tk-a --formula mol-polecat-work$' "$CALLS" \
    && ok "(14) $how: the bead waits on the question's gate on its anchor, armed to re-sling" \
    || bad "(14) $how: the bead waits on the question's gate on its anchor, armed to re-sling" "$(grep '^await' "$CALLS")"
  eq "$(grep -cE '^bd update tk-w .*(gc\.routed_to|gc\.takeaway)' "$CALLS")" "0" "(14) $how: and nothing parks it on a route or a headline"
  eq "$(grep -c '^bca ask --bead tk-w --path shared.txt --collided c --question q$' "$CALLS")" "1" "(14) $how: the question is asked once, with what collided"
  eq "$RC" "0" "(14) $how: --stop-merge exits 0"
  grep -qx 'runtime drain-ack' "$CALLS" && ok "(14) $how: it drains" || bad "(14) $how: it drains"
  eq "$(g "$C" rev-parse HEAD) $(g "$C" rev-parse -q --verify MERGE_HEAD)" "$W2 " "(14) $how: the merge is aborted, HEAD at the PR head"
  eq "$(meta rejection_reason)" "$CONFLICTS" "(14) $how: the rejection stays on the bead"
  [ "$(meta conflict_question)" != "<absent>" ] && ok "(14) $how: beside the question" || bad "(14) $how: beside the question"
  rm -f "$AT_MERGE"
  again
  eq "$RC" "3" "(15) $how: the next run's resume reaches the conflict again"
  eq "$(at_merge bring_current_from) $(at_merge bring_current_scope)" "$W2 merge-only" "(15) $how: it starts a new round from the PR head"
  eq "$(at_merge conflict_audit) $(at_merge conflict_question)" "<absent> <absent>" "(15) $how: clearing the question and the entries recorded before it, before it merges"
  eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(15) $how: and merges the base in again"
  eq "$(meta rejection_reason)" "$CONFLICTS" "(15) $how: the rejection stays until that merge concludes"
done
clone polecat/w2
setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS")")"
TOOL_ENV=ASK_FAIL=1 tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
eq "$RC" "1" "(16) a question that reaches no gate stops the stop"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(16) and the merge stays open"
for held in tk-step tk-w; do
  clone polecat/w2
  setup_run "$(bead polecat/w2 "$(rejected "$CONFLICTS" '"anchor_bead":"tk-a"')")"
  TOOL_ENV="STUB_HOOK_CURRENT=$held AWAIT_RC=1" tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
  eq "$RC" "1" "(16b) holding $held: a wait that does not land stops the stop"
  eq "$(grep -cE '^(cancel|runtime drain-ack)( |$)' "$CALLS")" "0" "(16b) holding $held: and nothing cancels or drains"
  eq "$(grep -cE '^bd update tk-w .*(--status|--assignee)' "$CALLS")" "0" "(16b) holding $held: the stop releases no claim itself, so it stays held"
  hasnt "$(notes tk-w)" "Stopped bringing the branch current" "(16b) holding $held: and the notes record no stop"
done

clone polecat/w1
setup_run "$(bead polecat/w1 "$(rejected "$MERGE_ONLY")")" STUB_UPDATE_FAIL_ON=bring_current_from
eq "$RC" "1" "(16c) a round the store refuses stops the resume"
called "git merge --no-edit origin/$BASE" && bad "(16c) before the merge" || ok "(16c) before the merge"

echo "# a fresh run makes its worktree in the rig, whatever repo its directory is in"
RIG="$TMP/rig"; "$REAL_GIT" clone -q "$O" "$RIG"
SLOT="$TMP/slot"; mkdir -p "$SLOT"
OTHER="$TMP/other-repo"; "$REAL_GIT" init -q "$OTHER"
fresh_run() { # <bead-json> [<VAR=value>...] — the script in another repo's cwd
  local bead="$1"; shift
  : > "$CALLS"
  printf '%s' "$bead" > "$STORE"
  OUT=$(cd "$OTHER" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me GC_DIR="$SLOT" "$@" "$PACK/work-setup.sh" --bead tk-w --base "$BASE" 2>"$TMP/err"); RC=$?
}
FRESH='[{"id":"tk-w","status":"open","assignee":"","metadata":{}}]'
fresh_run "$FRESH"
TREE="$SLOT/worktrees/tk-w"
eq "$RC" "0" "(20) a fresh run exits 0"
eq "$(last_line)" "$TREE" "(20) it prints the tree, scoped to the bead under the session's directory"
grep -qxF "worktree $TREE" <<< "$("$REAL_GIT" -C "$RIG" worktree list --porcelain)" && ok "(20) the rig's checkout registers the tree" || bad "(20) the rig's checkout registers the tree"
grep -qxF "worktree $TREE" <<< "$("$REAL_GIT" -C "$OTHER" worktree list --porcelain)" && bad "(20) the repo the session sits in does not" || ok "(20) the repo the session sits in does not"
eq "$(g "$TREE" branch --show-current)" "polecat/tk-w" "(20) on polecat/<bead>"
eq "$(g "$TREE" rev-parse HEAD)" "$BASE_TIP" "(20) cut from the freshly fetched base"
eq "$(meta branch)" "polecat/tk-w" "(20) the branch is recorded"
eq "$(meta work_dir)" "$TREE" "(20) the tree is recorded"
eq "$(meta gc.work_branch)" "polecat/tk-w" "(20) gc.work_branch is the branch HEAD is on"

fresh_run "[$(row tk-w "$(kv branch polecat/tk-w work_dir "$TREE")")]"
eq "$RC" "0" "(21) a re-entry exits 0"
eq "$(last_line)" "$TREE" "(21) it reuses the recorded tree"

# Reached when a run stopped between recording its tree and recording its branch.
fresh_run "[$(row tk-w "$(kv work_dir "$TREE")")]" STUB_LIST_FAIL=1
eq "$RC" "0" "(21b) a recorded tree with no branch yet: the store is not asked who else is on a branch"
eq "$(last_line)" "$TREE" "(21b) and the tree is reused"

"$REAL_GIT" -C "$RIG" worktree remove --force "$TREE"
GONE="$TMP/gone-tree"
fresh_run "[$(row tk-w "$(kv work_dir "$GONE")")]" GC_DIR="$TMP/slot2"
eq "$RC" "0" "(22) a recorded tree no longer on disk: a new one is made"
eq "$(meta work_dir)" "$TMP/slot2/worktrees/tk-w" "(22) and recorded"

# A rework after a hand-off, which takes the tree and its local branch and clears
# work_dir: only the branch is recorded.
NEW="$TMP/slot4/worktrees/tk-w"
fresh_run '[{"id":"tk-w","status":"open","assignee":"","metadata":{"branch":"polecat/w1","rejection_reason":"tests failed"}}]' GC_DIR="$TMP/slot4"
eq "$RC" "0" "(22b) a rework with its branch recorded and no tree: exits 0"
eq "$(last_line)" "$NEW" "(22b) it resumes in a fresh tree under the session's directory"
eq "$(meta work_dir)" "$NEW" "(22b) which is recorded"
eq "$(g "$NEW" branch --show-current)" "polecat/w1" "(22b) on the recorded branch"
eq "$(g "$NEW" rev-list --parents -n 1 HEAD | cut -d' ' -f2-)" "$W1 $BASE_TIP" "(22b) origin's branch, brought current by merge"
"$REAL_GIT" -C "$RIG" worktree remove --force "$NEW"; "$REAL_GIT" -C "$RIG" branch -q -D polecat/w1
# A rework on the tree an earlier hand-off left: detached at the pushed head,
# still recorded, its local branch deleted.
OLD="$TMP/slot5/worktrees/tk-w"; mkdir -p "$TMP/slot5/worktrees"
"$REAL_GIT" -C "$RIG" worktree add -q --detach "$OLD" "$W1"
fresh_run "[$(row tk-w "$(kv branch polecat/w1 work_dir "$OLD" rejection_reason "tests failed")")]" GC_DIR="$TMP/slot6"
eq "$RC" "0" "(22c) a rework whose recorded tree an earlier hand-off left: exits 0"
eq "$(last_line)" "$OLD" "(22c) it resumes in that tree"
eq "$(g "$OLD" branch --show-current)" "polecat/w1" "(22c) on the recorded branch"
eq "$(g "$OLD" rev-list --parents -n 1 HEAD | cut -d' ' -f2-)" "$W1 $BASE_TIP" "(22c) origin's branch, brought current by merge"

clone polecat/w1
g "$C" checkout -q --detach
setup_run "$(bead "" '{"branch":""}')" DROP_NOTHING=1 >/dev/null
eq "$(meta branch)" "polecat/tk-w" "(23) a bead with an empty branch cuts polecat/<bead> in its recorded tree"

clone polecat/w1
fresh_run "$FRESH" NO_RIG_ROOT=1 GC_DIR="$TMP/slot3"
eq "$RC" "1" "(24) no rig root: stops"
has "$(cat "$TMP/err")" "cannot resolve the rig root" "(24) and says so"
[ ! -e "$TMP/slot3/worktrees/tk-w" ] && ok "(24) and makes no tree" || bad "(24) and makes no tree"

echo "# metadata.branch is authoritative"
clone polecat/w1
g "$C" checkout -q --detach
setup_run "$(bead polecat/w1)"
eq "$(g "$C" branch --show-current)" "polecat/w1" "(30) a local branch at origin's tip is checked out"
eq "$(meta gc.work_branch)" "polecat/w1" "(30) gc.work_branch follows it"

clone polecat/w1
g "$C" checkout -q --detach
g "$C" branch -q -D polecat/w1
setup_run "$(bead polecat/w1)"
eq "$(g "$C" branch --show-current)" "polecat/w1" "(31) a branch only origin has is tracked"

clone polecat/w1
commit_in "$C" d.txt "local" "local"
g "$CO" update-ref refs/heads/polecat/w1 "$W1"
g "$SEED" checkout -q polecat/w1
commit_in "$SEED" other.txt "other" "origin moves"
g "$SEED" push -q "$CO" polecat/w1:polecat/w1
g "$SEED" reset -q --hard "$W1"
setup_run "$(bead polecat/w1)"
eq "$RC" "1" "(32) a local branch diverged from origin: stops"
grep -q '^gate --subject tk-w --key polecat-branch-divergence ' "$CALLS" && ok "(32) files a gate under its key" || bad "(32) files a gate under its key"
grep -q '^await tk-w --key polecat-branch-divergence --formula mol-polecat-work$' "$CALLS" && ok "(32) the work waits on it" || bad "(32) the work waits on it"
grep -q '^cancel --step mol-polecat-work.workspace-setup ' "$CALLS" && ok "(32) cancels the run" || bad "(32) cancels the run"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(32) drains" || bad "(32) drains"
has "$(grep '^gate ' "$CALLS")" "clearing it re-slings tk-w" "(32) the gate says clearing it re-slings"

clone polecat/w1
setup_run "$(bead polecat/never-existed)"
eq "$RC" "1" "(33) a branch that exists nowhere: stops, no different branch is made"
grep -q '^gate --subject tk-w --key polecat-missing-branch ' "$CALLS" && ok "(33) files a gate under its key" || bad "(33) files a gate under its key"
eq "$(g "$C" branch --list 'polecat/tk-w')" "" "(33) cuts no branch of its own"
order() { awk '/^(gate|await|cancel) / { print $1 } /^runtime drain-ack$/ { print "drain" }' "$CALLS" | tr '\n' ' '; }
eq "$(order)" "gate await cancel drain " "(33) in order: the gate, the wait, the cancel, the drain"
clone polecat/w1
setup_run "$(bead polecat/never-existed)" GATE_RC=1
eq "$(order)" "gate " "(34) a gate that does not land stops everything after it"
clone polecat/w1
setup_run "$(bead polecat/never-existed)" AWAIT_RC=1
eq "$(order)" "gate await " "(34) a wait that does not land stops the cancel"
clone polecat/w1
setup_run "$(bead polecat/never-existed)" CANCEL_RC=1
eq "$(order)" "gate await cancel " "(34) a cancel that does not land stops the drain"

echo "# a sibling's worktree holds the branch: the checkout that cannot be raced yields"
clone polecat/w1
g "$C" checkout -q --detach
PEER="$TMP/peer-tree"
g "$C" worktree add -q "$PEER" polecat/w1
SIB_BEADS="[$(row tk-w "$(kv branch polecat/w1 work_dir "$C")"),$(row tk-sib "$(kv branch polecat/w1 work_dir "$PEER")")]"
LIVE='[{"root":"r","convoy":"c","bead":"tk-sib","formula":"mol-polecat-work","live":true}]'
printf '%s' "$LIVE" > "$RUNS"
setup_run "$SIB_BEADS"
eq "$RC" "1" "(40) the checkout is refused: stops"
grep -q '^await tk-w --blocked-by tk-sib --formula mol-polecat-work$' "$CALLS" && ok "(40) the work waits on the sibling whose tree holds the branch" || bad "(40) the work waits on the sibling whose tree holds the branch" "$(grep -E '^(await|gate)' "$CALLS")"
grep -q '^cancel --step mol-polecat-work.workspace-setup --reason work bead tk-w waits on sibling tk-sib' "$CALLS" && ok "(40) cancels with that reason" || bad "(40) cancels with that reason"
eq "$(grep -c '^gate ' "$CALLS")" "0" "(40) asks nobody"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(40) drains" || bad "(40) drains"
has "$(notes tk-w)" "Yielded behind sibling tk-sib" "(40) the note says so"

setup_run "$SIB_BEADS" AWAIT_RC=1
grep -q '^gate --subject tk-w --key polecat-duplicate-dispatch ' "$CALLS" && ok "(41) the wait does not land: a person looks at the tree" || bad "(41) the wait does not land: a person looks at the tree"
setup_run "$SIB_BEADS" RUN_LIB_STUB_FAIL=all
eq "$RC" "1" "(41b) a run read that fails: stops"
eq "$(grep -cE '^(await|gate|cancel) ' "$CALLS")" "0" "(41b) it adopts nothing, waits on nothing and asks nobody"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(41b) the step goes back to the pool" || bad "(41b) the step goes back to the pool"
setup_run "$SIB_BEADS" STUB_LIST_FAIL=1
eq "$RC" "1" "(41c) a list of the branch's beads that fails: stops"
eq "$(grep -cE '^(await|gate|cancel) ' "$CALLS")" "0" "(41c) it takes the tree for no bead's and asks nobody"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(41c) the step goes back to the pool" || bad "(41c) the step goes back to the pool"
setup_run "$SIB_BEADS" STUB_LIST_OBJECT=1
eq "$RC" "1" "(41d) a list that answers with no array: stops"
eq "$(grep -cE '^(await|gate|cancel) ' "$CALLS")" "0" "(41d) it takes the tree for no bead's and asks nobody"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(41d) the step goes back to the pool" || bad "(41d) the step goes back to the pool"
setup_run "$(bead polecat/w1)"
eq "$RC" "1" "(42) a tree no bead records: stops"
grep -q '^gate --subject tk-w --key polecat-duplicate-dispatch ' "$CALLS" && ok "(42) a person looks at the tree" || bad "(42) a person looks at the tree"
has "$(grep '^gate ' "$CALLS")" "$PEER" "(42) the gate names the tree"

echo "# a tree no run works was left behind: a clean one is adopted, a dirty one goes to a person"
printf '[]' > "$RUNS"
setup_run "$SIB_BEADS"
eq "$RC" "0" "(43) no run works the bead that records the tree: exits 0"
eq "$(last_line)" "$PEER" "(43) the tree is the one this run enters"
eq "$(meta work_dir)" "$PEER" "(43) the bead records it"
eq "$(meta gc.work_branch)" "polecat/w1" "(43) on the branch"
eq "$(grep -cE '^(await|gate|cancel) ' "$CALLS")" "0" "(43) nothing waits, nobody is asked, nothing is cancelled"
printf '[{"root":"r","convoy":"c","bead":"tk-sib","formula":"mol-polecat-work","live":false}]' > "$RUNS"
setup_run "$SIB_BEADS"
eq "$RC" "0" "(43b) a run that has ended is no run: exits 0"
printf '[]' > "$RUNS"
printf 'loose\n' > "$PEER/loose.txt"
setup_run "$SIB_BEADS"
eq "$RC" "1" "(44) a dirty tree: stops"
grep -q '^gate --subject tk-w --key polecat-duplicate-dispatch ' "$CALLS" && ok "(44) a person looks at the tree" || bad "(44) a person looks at the tree"
has "$(grep '^gate ' "$CALLS")" "uncommitted paths" "(44) the gate says why"
rm -f "$PEER/loose.txt"

echo "# one record in flight decides, whatever the others beside it record"
ANCHOR_FIRST="[$(row tk-w "$(kv branch polecat/w1 work_dir "$C")"),$(row tk-anchor "$(kv branch polecat/w1 work_dir "$PEER")" open refinery),
  $(row tk-sib "$(kv branch polecat/w1 work_dir "$PEER")")]"
printf '%s' "$LIVE" > "$RUNS"
setup_run "$ANCHOR_FIRST"
eq "$RC" "1" "(46) a sibling adopted an anchor's tree, and the anchor lists first: stops"
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(46) the work waits on the sibling in flight, not on the anchor" || bad "(46) the work waits on the sibling in flight, not on the anchor" "$(grep -E '^(await|gate)' "$CALLS")"
eq "$(meta work_dir)" "$C" "(46) nothing adopts the tree"

echo "# a record names the tree however its path reached it, while git prints the real path"
ln -s "$PEER" "$TMP/peer-link"
LINKED="[$(row tk-w "$(kv branch polecat/w1 work_dir "$C")"),$(row tk-sib "$(kv branch polecat/w1 work_dir "$TMP/peer-link")")]"
setup_run "$LINKED"
eq "$RC" "1" "(46b) a sibling that records the tree through a symlink: stops"
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(46b) the work waits on it" || bad "(46b) the work waits on it" "$(grep -E '^(await|gate)' "$CALLS")"

echo "# a claim a listed session holds is in flight too"
printf '[]' > "$RUNS"
# claimed <status> <assignee> — tk-w beside tk-sib, whose tree holds the branch,
# at that status under that assignee.
claimed() {
  printf '[%s,%s]' "$(row tk-w "$(kv branch polecat/w1 work_dir "$C")")" \
    "$(row tk-sib "$(kv branch polecat/w1 work_dir "$PEER")" "$1" "$2")"
}
CLAIMED="$(claimed in_progress hq-peer)"
printf '%s' '{"sessions":[{"session_name":"hq-peer"}]}' > "$TMP/sessions-peer.json"
printf '%s' '{"sessions":[]}' > "$TMP/sessions-none.json"
printf '%s' '{"sessions":[{"id":"sess-me"}]}' > "$TMP/sessions-me.json"
setup_run "$CLAIMED" STUB_SESSIONS="$TMP/sessions-peer.json"
eq "$RC" "1" "(47) a sibling claimed by a listed session: stops"
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(47) the work waits on it" || bad "(47) the work waits on it" "$(grep -E '^(await|gate)' "$CALLS")"
setup_run "$CLAIMED"
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(47) a session list that cannot be read proves nobody gone" || bad "(47) a session list that cannot be read proves nobody gone"
setup_run "$CLAIMED" STUB_SESSIONS="$TMP/sessions-none.json"
eq "$RC" "0" "(48) a claim no listed session holds: the tree was left behind, so it is adopted"
eq "$(last_line)" "$PEER" "(48) and entered"
setup_run "$(claimed in_progress sess-me)" STUB_SESSIONS="$TMP/sessions-me.json"
eq "$RC" "0" "(48b) a claim this session holds is no sibling to wait on"
setup_run "$(claimed open hq-peer)" STUB_SESSIONS="$TMP/sessions-peer.json"
eq "$RC" "0" "(48c) a bead open under a live name is handed off, not in flight"
setup_run "$(claimed in_progress "")" STUB_SESSIONS="$TMP/sessions-peer.json"
eq "$RC" "0" "(48d) in_progress with no assignee: no session holds it, whoever is listed"

echo "# a tree this bead recorded is read before it is reused, since no checkout refuses it"
REUSED="[$(row tk-w "$(kv branch polecat/w1 work_dir "$PEER")"),$(row tk-sib "$(kv branch polecat/w1 work_dir "$PEER")")]"
printf '%s' "$LIVE" > "$RUNS"
setup_run "$REUSED"
eq "$RC" "1" "(49) a sibling in flight adopted the tree this bead records: stops"
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(49) the work waits on it" || bad "(49) the work waits on it" "$(grep -E '^(await|gate)' "$CALLS")"
grep -q '^git checkout ' "$CALLS" && bad "(49) and touches nothing in the tree" || ok "(49) and touches nothing in the tree"
printf '[]' > "$RUNS"
setup_run "$REUSED"
eq "$RC" "0" "(49b) a sibling that records the tree with nothing in flight: this run reuses it"
eq "$(last_line)" "$PEER" "(49b) and enters it"
printf '[{"root":"r-me","convoy":"c-me","bead":"tk-w","formula":"mol-polecat-work","live":true}]' > "$RUNS"
setup_run "$REUSED"
eq "$RC" "0" "(49d) this run's own live root is no sibling: it reuses its tree"
printf '[]' > "$RUNS"
setup_run "$REUSED" STUB_LIST_FAIL=1
eq "$RC" "1" "(49c) a list that fails before a reuse: stops"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(49c) the step goes back to the pool" || bad "(49c) the step goes back to the pool"

# A run that made its own tree before the checkout refused it leaves none behind.
RIG2="$TMP/rig2"; "$REAL_GIT" clone -q "$CO" "$RIG2" 2>/dev/null
g "$RIG2" fetch -q origin "+refs/heads/$BASE:refs/remotes/origin/$BASE"
PEER2="$TMP/peer2-tree"; g "$RIG2" worktree add -q "$PEER2" -b polecat/w1 origin/polecat/w1
OWN="$TMP/slot-adopt/worktrees/tk-w"
: > "$CALLS"
printf '[%s,%s]' "$(row tk-w "$(kv branch polecat/w1)")" "$(row tk-sib "$(kv branch polecat/w1 work_dir "$PEER2")")" > "$STORE"
OUT=$(cd "$RIG2" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me GC_DIR="$TMP/slot-adopt" RIG_ROOT_STUB="$RIG2" "$PACK/work-setup.sh" --bead tk-w --base "$BASE" 2>"$TMP/err"); RC=$?
eq "$RC" "0" "(45) a run that made its own tree adopts the one holding the branch: exits 0"
eq "$(last_line)" "$PEER2" "(45) and enters it"
[ ! -e "$OWN" ] && ok "(45) the empty tree it made is gone" || bad "(45) the empty tree it made is gone"

echo "# a sitting sets its change up under --held-by"
# The change a sitting filed: open, unassigned and unrouted, its target the base,
# with a blocks edge onto the conversation tk-conv, which the sitting's hook names.
SIT="$TMP/sitting-home"; CTREE="$SIT/worktrees/tk-c"; mkdir -p "$SIT"
HELD_EDGE='{"id":"tk-conv","dependency_type":"blocks"}'
# change [<assignee>] [<metadata members>] [<dependencies>] [<further rows>] —
# the store holding the change: unassigned unless named, its target the base
# unless members are given, held by HELD_EDGE unless dependencies are given,
# and any further rows after it.
change() {
  printf '[{"id":"tk-c","status":"open","assignee":%s,"metadata":{%s},"dependencies":[%s]}%s]' \
    "$(json_str "${1:-}")" "${2-$(kv target "$BASE")}" "${3-$HELD_EDGE}" "${4:+,$4}"
}
sitting() { # [<VAR=value>...] — work-setup.sh --held-by, from the sitting's home
  : > "$CALLS"
  OUT=$(cd "$SIT" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-sit GC_DIR="$SIT" STUB_HOOK_CURRENT=tk-conv "$@" \
    "$PACK/work-setup.sh" --bead tk-c --held-by tk-conv 2>"$TMP/err"); RC=$?
}
ended() { grep -cE '^(runtime drain-ack|gate|await|cancel)( |$)' "$CALLS" | tr -d ' '; }
printf '[]' > "$RUNS"
printf '%s' '[{"root":"root-9","convoy":"cv-9","bead":"tk-c","formula":"mol-polecat-work","live":true}]' > "$TMP/runs-c.json"
for case in edge hook no-hook holder refinery pending head-changed run route target rejection; do
  envs=(); who=""; members="$(kv target "$BASE")"; deps="$HELD_EDGE"
  case "$case" in
    edge)     deps=""; want="no blocks edge onto tk-conv" ;;
    hook)     envs=(STUB_HOOK_CURRENT=tk-other); want="gc hook current names tk-other, not tk-conv" ;;
    no-hook)  envs=(STUB_HOOK_CURRENT=); want="gc hook current names no bead, not tk-conv" ;;
    holder)   who=sess-other; want="assigned to sess-other" ;;
    refinery) who=gc-toolkit/gc-toolkit.refinery; want="assigned to gc-toolkit/gc-toolkit.refinery" ;;
    pending)  members+=",$(kv merge_result pull_request_pending)"; want="its PR waits on the pending record (pull_request_pending)" ;;
    head-changed) members+=",$(kv merge_result pull_request_head_changed)"
              want="its PR waits on the pending record (pull_request_head_changed), which the landing order works and a sitting edits through gctk pr push --held-by" ;;
    run)      envs=("RUN_LIB_STUB_RUNS=$TMP/runs-c.json"); want="a run works it (root-9)" ;;
    route)    members+=",$(kv gc.routed_to gc-toolkit/gc-toolkit.polecat)"; want="routed to gc-toolkit/gc-toolkit.polecat" ;;
    target)   members=""; want="records no target" ;;
    rejection) members+=",$(kv branch polecat/tk-c rejection_reason "Conflicts with main")"
              want="carries a rejection reason, so a check sent it back" ;;
  esac
  change "$who" "$members" "$deps" > "$STORE"; cp "$STORE" "$TMP/store-before"
  sitting ${envs[@]+"${envs[@]}"}
  eq "$RC" "1" "(60) $case: refused"
  has "$(cat "$TMP/err")" "$want" "(60) $case: the refusal says so"
  { cmp -s "$STORE" "$TMP/store-before" && ! grep -q '^bd update' "$CALLS"; } \
    && ok "(60) $case: nothing is written" || bad "(60) $case: nothing is written"
  [ ! -e "$CTREE" ] && ok "(60) $case: no tree is made" || bad "(60) $case: no tree is made"
  eq "$(ended)" "0" "(60) $case: nothing gates, waits, cancels or drains"
done
change > "$STORE"
sitting STUB_SHOW_FAIL=1
eq "$RC" "1" "(61) a store that does not answer: stops"
has "$(cat "$TMP/err")" "The store did not answer" "(61) says so"
eq "$(ended)" "0" "(61) and nothing gates, cancels or drains"
sitting RUN_LIB_STUB_FAIL=all
eq "$RC $(ended)" "1 0" "(61) the runs cannot be read: stops, and nothing is ended"

change > "$STORE"
sitting
eq "$RC" "0" "(62) a sitting's setup exits 0"
eq "$(last_line)" "$CTREE" "(62) it prints the tree, under the sitting's home"
eq "$(g "$CTREE" branch --show-current)" "polecat/tk-c" "(62) on polecat/<bead>"
eq "$(g "$CTREE" rev-parse HEAD)" "$BASE_TIP" "(62) cut from the bead's target"
eq "$(meta branch tk-c) $(meta work_dir tk-c)" "polecat/tk-c $CTREE" "(62) the branch and the tree are recorded"
eq "$(ended)" "0" "(62) nothing gates, waits, cancels or drains"
commit_in "$CTREE" agreed.txt "agreed" "a step the operator agreed"
AGREED="$(g "$CTREE" rev-parse HEAD)"
sitting
eq "$RC" "0" "(63) the sitting's next run exits 0"
eq "$(last_line)" "$CTREE" "(63) it re-enters the tree the bead records"
eq "$(g "$CTREE" branch --show-current) $(g "$CTREE" rev-parse HEAD)" "polecat/tk-c $AGREED" "(63) on its branch, with the commit it holds"
eq "$(ended)" "0" "(63) and ends nothing"

# A sibling in flight that records the same tree: a polecat's call waits on it
# (49), and a sitting's is refused with no wait written.
PEERC="$TMP/peer-c"; mkdir -p "$PEERC"
change "" "$(kv target "$BASE" branch polecat/tk-c work_dir "$PEERC")" "$HELD_EDGE" \
  "$(row tk-sib "$(kv branch polecat/tk-c work_dir "$PEERC")")" > "$STORE"
printf '%s' '[{"root":"r","convoy":"c","bead":"tk-sib","formula":"mol-polecat-work","live":true}]' > "$RUNS"
sitting
eq "$RC" "1" "(64) a sibling in flight in the tree the change records: stops"
has "$(cat "$TMP/err")" "where tk-sib is in flight" "(64) names the sibling"
eq "$(ended)" "0" "(64) no wait is written, and nothing cancels or drains"
change "" "$(kv target "$BASE" branch polecat/never-existed)" > "$STORE"
printf '[]' > "$RUNS"
sitting GC_DIR="$TMP/sitting-home-2"
eq "$RC" "1" "(65) a recorded branch that exists nowhere: stops"
eq "$(ended)" "0" "(65) no gate is filed, and nothing cancels or drains"

echo "# the store"
clone polecat/w1
setup_run "$(bead polecat/w1)" STUB_SHOW_FAIL=1
eq "$RC" "1" "(50) a store that does not answer: stops"
has "$(cat "$TMP/err")" "The store did not answer" "(50) says so"
grep -qx 'runtime drain-ack' "$CALLS" && ok "(50) goes back to the pool" || bad "(50) goes back to the pool"
eq "$(grep -cE '^(gate|cancel) ' "$CALLS")" "0" "(50) asks nothing and cancels nothing"

echo "# usage"
tool --base x; eq "$RC" "2" "no work named: usage error"
tool --bead a --convoy b --base x; eq "$RC" "2" "both named: usage error"
tool --bead a; eq "$RC" "2" "no --base: usage error"
tool --stop-merge --bead a --path p; eq "$RC" "2" "--stop-merge without its question: usage error"
tool --nope; eq "$RC" "2" "an unknown flag: usage error"
tool --bead a --held-by c --base x; eq "$RC" "2" "--held-by with --base: usage error"
tool --convoy a --held-by c; eq "$RC" "2" "--held-by with --convoy: usage error"
tool --conclude-merge --bead a --held-by c; eq "$RC" "2" "--held-by with --conclude-merge: usage error"
tool --stop-merge --bead a --held-by c --path p --collided c --question q; eq "$RC" "2" "--held-by with --stop-merge: usage error"

echo
echo "work-setup: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
