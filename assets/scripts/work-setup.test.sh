#!/usr/bin/env bash
# Hermetic test for assets/scripts/work-setup.sh, mol-polecat-work's
# workspace-setup.
#
# It runs against a real git repository with a real bare origin. A gc stub keeps
# the bead in a JSON store that its reads serve and its writes change, and a
# wrapper runs the real git. Both record each call in one log, and the wrapper
# copies the store when a merge starts, so a case can read what the bead carried
# before the merge moved HEAD. The pack scripts it calls past the bead are stubs
# that record their calls, except hand-back.sh, decline.sh and work-lib.sh, which
# are the real ones, and run-lib.stub.sh answers which runs work a bead. No live
# city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-setup-test.XXXXXX")"
# git prints a worktree by its resolved path.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" tag.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

BASE="integration/c1"
PACK="$TMP/pack"; BIN="$TMP/bin"; mkdir -p "$PACK" "$BIN"
cp "$HERE/work-setup.sh" "$HERE/work-lib.sh" "$HERE/decline.sh" "$HERE/bd-lib.sh" "$HERE/hand-back.sh" "$PACK/"
RUNS="$TMP/runs.json"
export GC_RUN_LIB="$HERE/run-lib.stub.sh" RUN_LIB_STUB_RUNS="$RUNS"
export REAL_GIT CALLS="$TMP/calls.log" STORE="$TMP/store.json" AT_MERGE="$TMP/store-at-merge.json" RIG_ROOT_STUB="$TMP/rig"

cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "merge" ]; then cp "$STORE" "$AT_MERGE"; fi
exec "$REAL_GIT" "$@"
SH
# bd list answers every row that records the branch it asks for. Every update
# refuses under DROP_WRITES, and one naming DROP_WRITE_WITH refuses, the way a
# store outage or a guard does.
cat > "$BIN/gc" <<'SH'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "$CALLS"
case "${1:-} ${2:-}" in
  "runtime drain-ack") printf 'drain\n' >> "$CALLS"; exit 0 ;;
  "hook current") [ -n "${HOOK_CURRENT:-}" ] || exit 1; printf '%s\n' "$HOOK_CURRENT"; exit 0 ;;
  "convoy status") printf '{"children":[{"id":"tk-w"}]}\n'; exit 0 ;;
esac
[ "${1:-}" = "bd" ] || exit 0
verb="${2:-}"; id="${3:-}"
case "$verb" in
  show)
    [ -z "${SHOW_DOWN:-}" ] || exit 1
    jq -c --arg id "$id" '[.[] | select(.id == $id)]' "$STORE" ;;
  list)
    field=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --metadata-field) field="$2"; shift 2 ;; *) shift ;; esac; done
    jq -c --arg b "${field#branch=}" '[.[] | select((.metadata.branch // "") == $b)]' "$STORE" ;;
  update)
    [ -z "${DROP_WRITES:-}" ] || exit 1
    [ -z "${DROP_WRITE_WITH:-}" ] || case "$*" in *"$DROP_WRITE_WITH"*) exit 1 ;; esac
    shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)   k="${2%%=*}"; v="${2#*=}"; f='.metadata[$k] = $v'; shift 2 ;;
        --unset-metadata) k="$2"; v=""; f='.metadata |= del(.[$k])'; shift 2 ;;
        --status=*)       k="status"; v="${1#--status=}"; f='.status = $v'; shift ;;
        --assignee=*)     k="assignee"; v="${1#--assignee=}"; f='.assignee = $v'; shift ;;
        --if-assignee=*|--if-status=*) shift; continue ;;
        --append-notes)   k="notes"; v="$2"; f='.notes = ((.notes // "") + $v)'; shift 2 ;;
        *) shift; continue ;;
      esac
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" "map(if .id == \$id then $f else . end)" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    done ;;
esac
exit 0
SH
chmod +x "$BIN/git" "$BIN/gc"

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
  anchor) gc bd show "$bead" | jq -r '.[0] | .metadata.anchor_bead // .id' ;;
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
set_meta() { # <key> <value> — what another writer put on the bead between runs
  jq -c --arg k "$1" --arg v "$2" 'map(.metadata[$k] = $v)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
}
bead() { # <branch> [<metadata json>] — the bead, its work_dir the clone
  jq -nc --arg b "$1" --arg d "$C" --argjson m "${2:-null}" '[{id: "tk-w", status: "open", assignee: "", metadata: ({branch: $b, work_dir: $d} + ($m // {}))}]'
}
meta() { jq -r --arg k "$1" '.[0].metadata // {} | if has($k) then .[$k] else "<absent>" end' "${2:-$STORE}"; }
at_merge() { if [ -f "$AT_MERGE" ]; then meta "$1" "$AT_MERGE"; else echo "<no merge ran>"; fi; }
parents() { g "$C" rev-list --parents -n 1 HEAD | cut -d' ' -f2-; }
called() { grep -qxF -- "$1" "$CALLS"; }
rewrites() { grep -cE '^git (rebase|push|reset|commit|cherry-pick|am)( |$)' "$CALLS"; }
last_line() { printf '%s\n' "$OUT" | tail -n 1; }

echo "# a rejected branch is brought current by merging the base in"
clone polecat/w1
STALE="stale base at head $W1: PR#1 conflicts with '$BASE'."
setup_run "$(bead polecat/w1 "$(jq -nc --arg r "$STALE" '{rejection_reason: $r, prepare_mode: "merge",
  conflict_audit: "entries from an earlier round", conflict_question: "a question from an earlier round"}')")"
eq "$RC" "0" "(1) the resume exits 0"
eq "$(parents)" "$W1 $BASE_TIP" "(1) HEAD is a merge commit of the PR head and origin/$BASE, in that order"
called "git merge --no-edit origin/$BASE" \
  && ok "(1) the base is merged in by git merge --no-edit origin/$BASE" \
  || bad "(1) the base is merged in by git merge --no-edit origin/$BASE" "$(grep '^git ' "$CALLS" | tr '\n' ';')"
eq "$(rewrites)" "0" "(1) nothing rebases, resets, commits, cherry-picks or pushes"
eq "$(g "$CO" rev-parse refs/heads/polecat/w1)" "$W1" "(1) origin's branch is untouched: the resume pushes nothing"
eq "$(at_merge bring_current_from)" "$W1" "(1) before the merge runs, bring_current_from is the PR head"
eq "$(at_merge bring_current_scope)" "merge-only" "(1) before the merge runs, the stale-base rejection's scope is merge-only"
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
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r, prepare_mode: "merge"}')")"
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
  setup_run "$(bead polecat/w1 "${m:-null}")"
  eq "$RC" "0" "(7) $label: exits 0"
  eq "$(g "$C" rev-parse HEAD)" "$W1" "(7) $label: HEAD stays at the PR head"
  eq "$(grep -c '^git merge --no-edit' "$CALLS")" "0" "(7) $label: nothing merges the base in"
done

echo "# the scope is merge-only for a stale-base or conflict rejection, and with-work for any other"
scope_case() { # <label> <rejection_reason> <scope>
  clone polecat/w1
  setup_run "$(bead polecat/w1 "$(jq -nc --arg r "$2" '{rejection_reason: $r}')")"
  eq "$(at_merge bring_current_scope)" "$3" "(8) $1 is stamped $3 before the merge runs"
}
scope_case "a stale-base rejection" "$STALE" merge-only
scope_case "a conflict rejection" "$CONFLICTS" merge-only
scope_case "a failed-tests rejection" "tests failed" with-work

echo "# a round that does not land stops before the merge"
clone polecat/w1
printf '%s' "$(bead polecat/w1 '{"rejection_reason":"tests failed"}')" > "$STORE"
: > "$CALLS"; rm -f "$AT_MERGE"
again DROP_WRITES=1
eq "$RC" "1" "(9) exits 1"
eq "$(grep -c '^git merge --no-edit' "$CALLS")" "0" "(9) git merge is not run"
eq "$(g "$C" rev-parse HEAD)" "$W1" "(9) HEAD stays at the PR head"
eq "$(meta rejection_reason)" "tests failed" "(9) rejection_reason stays, so a re-run resumes the same rejection"

echo "# the commit that concludes a conflicted merge clears the rejection"
clone polecat/w2
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r}')")"
printf 'both sides\n' > "$C/shared.txt"; g "$C" add shared.txt
tool --conclude-merge --bead tk-w
eq "$RC" "0" "(11) --conclude-merge exits 0"
eq "$(parents)" "$W2 $BASE_TIP" "(11) its commit concludes the merge"
eq "$(meta rejection_reason)" "<absent>" "(11) and clears the rejection"

echo "# a merge that does not conclude leaves the rejection"
clone polecat/w2
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r}')")"
tool --conclude-merge --bead tk-w
[ "$RC" != "0" ] && ok "(12) a commit git refuses, the conflict unresolved, fails --conclude-merge" || bad "(12) a commit git refuses, the conflict unresolved, fails --conclude-merge" "it exited 0"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(12) the merge is still in progress"
eq "$(meta rejection_reason)" "$CONFLICTS" "(12) and the rejection stays"
clone polecat/w2
printf 'an edit nobody committed\n' > "$C/shared.txt"
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r}')")"
eq "$RC" "1" "(13) a merge git refuses to start exits 1"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "" "(13) git refuses to start a merge over an uncommitted edit"
eq "$(meta rejection_reason)" "$CONFLICTS" "(13) and the rejection stays"

echo "# a stop to ask a person leaves the rejection, so the next run merges again"
for how in molecule bare; do
  clone polecat/w2
  setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r, anchor_bead: "tk-a", work_holder: "sess-me"}')" | jq -c 'map(.status = "in_progress" | .assignee = "sess-me")')"
  set_meta conflict_audit '[{"path":"resolved-before-the-stop.txt"}]'
  : > "$CALLS"
  if [ "$how" = molecule ]; then
    TOOL_ENV=HOOK_CURRENT=tk-step tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
    grep -q '^await tk-w --key bring-current-question\.tk-w --subject tk-a ' "$CALLS" \
      && ok "(14) molecule: the bead waits on the question's gate on its anchor" \
      || bad "(14) molecule: the bead waits on the question's gate on its anchor"
    grep -q '^cancel --step mol-polecat-work.workspace-setup ' "$CALLS" && ok "(14) molecule: and its run is cancelled" || bad "(14) molecule: and its run is cancelled"
    eq "$(meta work_holder)" "<absent>" "(14) molecule: this run lets go of the work"
  else
    TOOL_ENV=HOOK_CURRENT=tk-w tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
    eq "$(meta gc.routed_to)" "human" "(14) bare: the bead parks to a person"
  fi
  eq "$RC" "0" "(14) $how: --stop-merge exits 0"
  grep -qx 'drain' "$CALLS" && ok "(14) $how: it drains" || bad "(14) $how: it drains"
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
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r}')")"
TOOL_ENV=ASK_FAIL=1 tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
eq "$RC" "1" "(16) a question that reaches no gate stops the stop"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(16) and the merge stays open"
clone polecat/w2
setup_run "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r, anchor_bead: "tk-a"}')")"
TOOL_ENV="HOOK_CURRENT=tk-step AWAIT_RC=1" tool --stop-merge --bead tk-w --path shared.txt --collided c --question q
eq "$RC" "1" "(16b) a wait that does not land stops the stop"
eq "$(grep -cE '^(cancel|drain)( |$)' "$CALLS")" "0" "(16b) and nothing cancels or drains"

clone polecat/w1
setup_run "$(bead polecat/w1 "$(jq -nc --arg r "$STALE" '{rejection_reason: $r}')")" DROP_WRITE_WITH=bring_current_from
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
eq "$(meta work_holder)" "sess-me" "(20) the session that entered it is recorded"
eq "$(meta gc.work_branch)" "polecat/tk-w" "(20) gc.work_branch is the branch HEAD is on"

fresh_run "$(jq -nc --arg d "$TREE" '[{id: "tk-w", status: "open", assignee: "", metadata: {branch: "polecat/tk-w", work_dir: $d, work_holder: "sess-gone"}}]')"
eq "$RC" "0" "(21) a re-entry exits 0"
eq "$(last_line)" "$TREE" "(21) it reuses the recorded tree"
eq "$(meta work_holder)" "sess-me" "(21) the session that re-entered it is recorded"

"$REAL_GIT" -C "$RIG" worktree remove --force "$TREE"
GONE="$TMP/gone-tree"
fresh_run "$(jq -nc --arg d "$GONE" '[{id: "tk-w", status: "open", assignee: "", metadata: {work_dir: $d}}]')" GC_DIR="$TMP/slot2"
eq "$RC" "0" "(22) a recorded tree no longer on disk: a new one is made"
eq "$(meta work_dir)" "$TMP/slot2/worktrees/tk-w" "(22) and recorded"

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
setup_run "$(bead polecat/w1 '{"work_holder":"sess-me"}')"
eq "$RC" "1" "(32) a local branch diverged from origin: stops"
grep -q '^gate --subject tk-w --key polecat-branch-divergence ' "$CALLS" && ok "(32) files a gate under its key" || bad "(32) files a gate under its key"
grep -q '^await tk-w --key polecat-branch-divergence --formula mol-polecat-work$' "$CALLS" && ok "(32) the work waits on it" || bad "(32) the work waits on it"
grep -q '^cancel --step mol-polecat-work.workspace-setup ' "$CALLS" && ok "(32) cancels the run" || bad "(32) cancels the run"
grep -qx 'drain' "$CALLS" && ok "(32) drains" || bad "(32) drains"
eq "$(meta work_holder)" "<absent>" "(32) lets go of the work"
has "$(grep '^gate ' "$CALLS")" "clearing it re-slings tk-w" "(32) the gate says clearing it re-slings"

clone polecat/w1
setup_run "$(bead polecat/never-existed)"
eq "$RC" "1" "(33) a branch that exists nowhere: stops, no different branch is made"
grep -q '^gate --subject tk-w --key polecat-missing-branch ' "$CALLS" && ok "(33) files a gate under its key" || bad "(33) files a gate under its key"
eq "$(g "$C" branch --list 'polecat/tk-w')" "" "(33) cuts no branch of its own"
order() { grep -E '^(gate|await|cancel|drain)( |$)' "$CALLS" | awk '{print $1}' | tr '\n' ' '; }
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
SIB_BEADS="$(jq -nc --arg d "$C" --arg p "$PEER" '[{id: "tk-w", status: "open", assignee: "", metadata: {branch: "polecat/w1", work_dir: $d, work_holder: "sess-me"}},
  {id: "tk-sib", status: "open", assignee: "", metadata: {branch: "polecat/w1", work_dir: $p}}]')"
LIVE='[{"root":"r","convoy":"c","bead":"tk-sib","formula":"mol-polecat-work","live":true}]'
printf '%s' "$LIVE" > "$RUNS"
setup_run "$SIB_BEADS"
eq "$RC" "1" "(40) the checkout is refused: stops"
grep -q '^await tk-w --blocked-by tk-sib --formula mol-polecat-work$' "$CALLS" && ok "(40) the work waits on the sibling whose tree holds the branch" || bad "(40) the work waits on the sibling whose tree holds the branch" "$(grep -E '^(await|gate)' "$CALLS")"
grep -q '^cancel --step mol-polecat-work.workspace-setup --reason work bead tk-w waits on sibling tk-sib' "$CALLS" && ok "(40) cancels with that reason" || bad "(40) cancels with that reason"
eq "$(grep -c '^gate ' "$CALLS")" "0" "(40) asks nobody"
grep -qx 'drain' "$CALLS" && ok "(40) drains" || bad "(40) drains"
has "$(jq -r '.[0].notes // ""' "$STORE")" "Yielded behind sibling tk-sib" "(40) the note says so"
eq "$(meta work_holder)" "<absent>" "(40) lets go of the work"

setup_run "$SIB_BEADS" AWAIT_RC=1
grep -q '^gate --subject tk-w --key polecat-duplicate-dispatch ' "$CALLS" && ok "(41) the wait does not land: a person looks at the tree" || bad "(41) the wait does not land: a person looks at the tree"
setup_run "$SIB_BEADS" RUN_LIB_STUB_FAIL=all
grep -q '^await tk-w --blocked-by tk-sib ' "$CALLS" && ok "(41b) a run read that fails rules no run out: the work waits" || bad "(41b) a run read that fails rules no run out: the work waits"
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
eq "$(meta work_holder)" "sess-me" "(43) with this session holding it"
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
# A run that made its own tree before the checkout refused it leaves none behind.
RIG2="$TMP/rig2"; "$REAL_GIT" clone -q "$CO" "$RIG2" 2>/dev/null
g "$RIG2" fetch -q origin "+refs/heads/$BASE:refs/remotes/origin/$BASE"
PEER2="$TMP/peer2-tree"; g "$RIG2" worktree add -q "$PEER2" -b polecat/w1 origin/polecat/w1
OWN="$TMP/slot-adopt/worktrees/tk-w"
: > "$CALLS"
jq -nc --arg p "$PEER2" '[{id: "tk-w", status: "open", assignee: "", metadata: {branch: "polecat/w1"}},
  {id: "tk-sib", status: "open", assignee: "", metadata: {branch: "polecat/w1", work_dir: $p}}]' > "$STORE"
OUT=$(cd "$RIG2" && env PATH="$BIN:$PATH" WORK_READ_WAIT=0 GC_SESSION_ID=sess-me GC_DIR="$TMP/slot-adopt" RIG_ROOT_STUB="$RIG2" "$PACK/work-setup.sh" --bead tk-w --base "$BASE" 2>"$TMP/err"); RC=$?
eq "$RC" "0" "(45) a run that made its own tree adopts the one holding the branch: exits 0"
eq "$(last_line)" "$PEER2" "(45) and enters it"
[ ! -e "$OWN" ] && ok "(45) the empty tree it made is gone" || bad "(45) the empty tree it made is gone"

echo "# the store"
clone polecat/w1
setup_run "$(bead polecat/w1)" SHOW_DOWN=1
eq "$RC" "1" "(50) a store that does not answer: stops"
has "$(cat "$TMP/err")" "The store did not answer" "(50) says so"
grep -qx 'drain' "$CALLS" && ok "(50) goes back to the pool" || bad "(50) goes back to the pool"
eq "$(grep -cE '^(gate|cancel) ' "$CALLS")" "0" "(50) asks nothing and cancels nothing"

echo "# usage"
tool --base x; eq "$RC" "2" "no work named: usage error"
tool --bead a --convoy b --base x; eq "$RC" "2" "both named: usage error"
tool --bead a; eq "$RC" "2" "no --base: usage error"
tool --stop-merge --bead a --path p; eq "$RC" "2" "--stop-merge without its question: usage error"
tool --nope; eq "$RC" "2" "an unknown flag: usage error"

echo
echo "work-setup: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
