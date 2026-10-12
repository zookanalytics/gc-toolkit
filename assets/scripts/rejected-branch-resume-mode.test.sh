#!/usr/bin/env bash
# Hermetic test for the rejected-branch-resume-mode block in
# formulas/mol-polecat-work.toml (workspace-setup step).
#
# A rejected branch is resumed under an open PR, so the resume brings it
# current without rewriting what reviewers have seen. The block's contract:
#   - with a rejection_reason on the bead, it MERGES origin/<base> into the
#     branch. The PR head stays an ancestor, so the push that follows is a
#     plain fast-forward;
#   - it never rebases and never pushes, whatever prepare_mode says, and when
#     the bead carries no prepare_mode at all;
#   - a conflicting merge is left mid-merge, for the worker to resolve into a
#     merge commit;
#   - before the merge moves HEAD, it records the round on the bead.
#     bring_current_from is the PR head, which is origin's copy of the branch,
#     or HEAD when origin has none. bring_current_scope is merge-only for a
#     "stale base at head" or "Conflicts with" rejection, and with-work for any
#     other. The last round's conflict_audit and conflict_question are cleared;
#   - it merges only once bring_current_from reads back from the bead, and when
#     it does not, the block exits 1 having merged nothing;
#   - it unsets rejection_reason;
#   - with no rejection_reason it does nothing.
#
# It EXECUTES the block extracted verbatim from the formula against a real git
# repository with a real bare origin. A gc stub keeps the bead in a JSON store
# that its reads serve and its writes change, and a wrapper runs the real git.
# Both record each call in one log, so a case can read which commands ran, and
# the wrapper copies the store when a merge starts, so a case can read what the
# bead carried before the merge moved HEAD. The block's base is rendered as an
# integration branch, which is not main, so a block that merged a fixed main
# would merge nothing here. No live city, Dolt, network, or PRs.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-polecat-work.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rejected-branch-resume-mode-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
REAL_GIT="$(command -v git)" || { echo "git is required for this test" >&2; exit 1; }
[ -s "$TOML" ] || { echo "missing $TOML" >&2; exit 1; }

# Git reads only the configuration pinned here, so a host's signing, hooks or
# default branch cannot reach a case.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" tag.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

BASE="integration/c1"

# --- Extract the block and render {{base_branch}}. ----------------------------
awk '
  $0 ~ /# >>> rejected-branch-resume-mode$/ {f=1; next}
  $0 ~ /# <<< rejected-branch-resume-mode$/ {f=0}
  f' "$TOML" > "$TMP/raw.sh"
[ -s "$TMP/raw.sh" ] \
  && ok "the block is extracted between the rejected-branch-resume-mode markers" \
  || bad "the block is extracted between the rejected-branch-resume-mode markers" "empty: the markers are missing from $TOML"
# The block lives inside a TOML `"""` string, which eats a trailing backslash
# before any agent sees it.
case "$(cat "$TMP/raw.sh")" in
  *\\*) bad "the block is backslash-free (TOML would eat it)" "found a backslash" ;;
  *)    ok  "the block is backslash-free (TOML would eat it)" ;;
esac
sed "s#{{base_branch}}#$BASE#g" "$TMP/raw.sh" > "$TMP/block.sh"
VARS="$(grep -o '{{[^}]*}}' "$TMP/block.sh" | sort -u | tr '\n' ' ')"
eq "$VARS" "" "every formula var in the block is rendered"
bash -n "$TMP/block.sh" && ok "the block is valid bash" || bad "the block is valid bash" "bash -n failed"

# --- Stubs. ---------------------------------------------------------------------
# The gc stub keeps the beads in $STORE. `bd show <id>` serves that bead, and
# `bd update <id>` applies each --set-metadata and --unset-metadata to it, so a
# read-back sees what the block wrote. With DROP_WRITES set, an update exits 0
# and changes nothing, which is how a write that never landed looks to the
# block. The git wrapper copies the store to $AT_MERGE when a merge starts.
BIN="$TMP/bin"; mkdir -p "$BIN"
export REAL_GIT CALLS="$TMP/calls.log" STORE="$TMP/store.json" AT_MERGE="$TMP/store-at-merge.json"
cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "merge" ]; then cp "$STORE" "$AT_MERGE"; fi
exec "$REAL_GIT" "$@"
SH
cat > "$BIN/gc" <<'SH'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "$CALLS"
[ "${1:-}" = "bd" ] || exit 0
verb="${2:-}"; id="${3:-}"
case "$verb" in
  show) jq -c --arg id "$id" '[.[] | select(.id == $id)]' "$STORE" ;;
  update)
    [ -z "${DROP_WRITES:-}" ] || exit 0
    shift 3
    while [ $# -ge 2 ]; do
      case "$1" in
        --set-metadata)   k="${2%%=*}"; v="${2#*=}"; f='.metadata[$k] = $v' ;;
        --unset-metadata) k="$2"; v=""; f='.metadata |= del(.[$k])' ;;
        *) shift; continue ;;
      esac
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" "map(if .id == \$id then $f else . end)" "$STORE" > "$STORE.new" \
        && mv "$STORE.new" "$STORE"
      shift 2
    done ;;
esac
exit 0
SH
chmod +x "$BIN/git" "$BIN/gc"

# --- Histories. -----------------------------------------------------------------
# A bare origin whose main holds the merge base. polecat/w1 adds a file of its
# own, polecat/w2 edits shared.txt, and the base branch moves past the merge
# base with a file of its own and an edit of shared.txt.
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

# clone <branch> — a fresh clone at $C with <branch> checked out, and an origin
# of its own at $CO, a copy of $O, so a block that pushes changes only its case.
N=0
clone() {
  N=$((N + 1)); C="$TMP/clone-$N"; CO="$TMP/origin-$N.git"
  cp -R "$O" "$CO"
  "$REAL_GIT" clone -q "$CO" "$C" && g "$C" checkout -q -B "$1" "origin/$1"
}
# run_block <bead-json> — the block run in $C as a polecat runs it, against a
# store holding that bead, on a fresh call log. Sets RC.
run_block() {
  : > "$CALLS"; rm -f "$AT_MERGE"
  printf '%s' "$1" > "$STORE"
  ( cd "$C" && PATH="$BIN:$PATH" WORK_BEAD_ID=tk-w bash "$TMP/block.sh" ) > "$TMP/out" 2>&1
  RC=$?
}
bead() { # <branch> [<metadata json>]
  jq -nc --arg b "$1" --argjson m "${2:-null}" '[{id: "tk-w", metadata: ({branch: $b} + ($m // {}))}]'
}
# meta <key> — the bead's metadata value in the store, or <absent>. at_merge
# <key> reads it from the copy the git wrapper took when the merge started.
meta() { jq -r --arg k "$1" '.[0].metadata // {} | if has($k) then .[$k] else "<absent>" end' "${2:-$STORE}"; }
at_merge() { if [ -f "$AT_MERGE" ]; then meta "$1" "$AT_MERGE"; else echo "<no merge ran>"; fi; }
parents() { g "$C" rev-list --parents -n 1 HEAD | cut -d' ' -f2-; }
called() { grep -qxF -- "$1" "$CALLS"; }
rewrites() { grep -cE '^git (rebase|push|reset|commit|cherry-pick|am)( |$)' "$CALLS"; }

echo "# a rejected branch is brought current by merging the base in"
clone polecat/w1
STALE="stale base at head $W1: PR#1 conflicts with '$BASE'."
run_block "$(bead polecat/w1 "$(jq -nc --arg r "$STALE" '{rejection_reason: $r, prepare_mode: "merge",
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
eq "$(at_merge conflict_audit) $(at_merge conflict_question)" "<absent> <absent>" \
  "(1) before the merge runs, the last round's audit and question are cleared"
eq "$(meta bring_current_from) $(meta bring_current_scope)" "$W1 merge-only" "(1) the round stays on the bead for the hand-off to read"
eq "$(meta rejection_reason)" "<absent>" "(1) rejection_reason is unset"

echo "# the push that follows is a plain fast-forward"
g "$C" push -q origin HEAD:polecat/w1 >/dev/null 2>&1 \
  && ok "(2) a push with no force flag fast-forwards the PR branch" \
  || bad "(2) a push with no force flag fast-forwards the PR branch" "rejected: the resume rewrote the branch"

echo "# with prepare_mode=rebase, or none at all, the resume still merges and rewrites nothing"
for m in '{"rejection_reason":"tests failed","prepare_mode":"rebase"}' \
         '{"rejection_reason":"tests failed"}'; do
  case "$m" in *prepare_mode*) label="prepare_mode=rebase" ;; *) label="no prepare_mode" ;; esac
  clone polecat/w1
  run_block "$(bead polecat/w1 "$m")"
  eq "$(parents)" "$W1 $BASE_TIP" "(3) $label: the branch is merged, its PR head kept"
  eq "$(rewrites)" "0" "(3) $label: nothing rebases, resets, commits, cherry-picks or pushes"
done

echo "# a conflicting merge is left mid-merge for the worker"
clone polecat/w2
CONFLICTS="Conflicts with $BASE at $BASE_TIP; resume in prepare_mode=merge"
run_block "$(bead polecat/w2 "$(jq -nc --arg r "$CONFLICTS" '{rejection_reason: $r, prepare_mode: "merge"}')")"
eq "$(g "$C" rev-parse -q --verify MERGE_HEAD)" "$BASE_TIP" "(4) the clone is mid-merge, merging origin/$BASE"
eq "$(g "$C" diff --name-only --diff-filter=U)" "shared.txt" "(4) the conflict is left for the worker to resolve"
eq "$(g "$C" rev-parse HEAD)" "$W2" "(4) HEAD is still the PR head"
GITDIR="$(g "$C" rev-parse --absolute-git-dir)"
{ [ ! -e "$GITDIR/rebase-merge" ] && [ ! -e "$GITDIR/rebase-apply" ]; } \
  && ok "(4) no rebase is in progress" || bad "(4) no rebase is in progress"
eq "$(rewrites)" "0" "(4) nothing rebases, resets, commits, cherry-picks or pushes"

echo "# a local commit origin has not seen leaves the stamp at origin's copy of the branch"
clone polecat/w1
commit_in "$C" local.txt "local" "a commit origin has not seen"
AHEAD="$(g "$C" rev-parse HEAD)"
run_block "$(bead polecat/w1 '{"rejection_reason":"tests failed"}')"
eq "$(at_merge bring_current_from)" "$W1" "(5) bring_current_from is the PR head origin holds, not the local commit past it"
eq "$(parents)" "$AHEAD $BASE_TIP" "(5) the base is merged into the local head"

echo "# a branch origin does not have is stamped with HEAD from before the merge"
clone polecat/w1
g "$C" checkout -q -b polecat/w3
commit_in "$C" local.txt "local" "a commit origin never saw"
LOCAL="$(g "$C" rev-parse HEAD)"
run_block "$(bead polecat/w3 '{"rejection_reason":"tests failed"}')"
eq "$(at_merge bring_current_from)" "$LOCAL" "(6) bring_current_from is the head the resume started from, not its merge commit"
eq "$(parents)" "$LOCAL $BASE_TIP" "(6) the base is merged in"

echo "# without a rejection the block does nothing"
for m in '' '{"rejection_reason":""}'; do
  case "$m" in '') label="no rejection_reason" ;; *) label="an empty rejection_reason" ;; esac
  clone polecat/w1
  run_block "$(bead polecat/w1 "${m:-null}")"
  eq "$RC" "0" "(7) $label: the block exits 0"
  eq "$(g "$C" rev-parse HEAD)" "$W1" "(7) $label: HEAD stays at the PR head"
  eq "$(grep -c '^git ' "$CALLS")" "0" "(7) $label: git is not run"
  eq "$(grep -c '^gc bd update' "$CALLS")" "0" "(7) $label: nothing is written to the bead"
done

echo "# the scope is merge-only for a stale-base or conflict rejection, and with-work for any other"
scope_case() { # <label> <rejection_reason> <scope>
  clone polecat/w1
  run_block "$(bead polecat/w1 "$(jq -nc --arg r "$2" '{rejection_reason: $r}')")"
  eq "$(at_merge bring_current_scope)" "$3" "(8) $1 is stamped $3 before the merge runs"
}
scope_case "a stale-base rejection" "$STALE" merge-only
scope_case "a conflict rejection" "$CONFLICTS" merge-only
scope_case "a failed-tests rejection" "tests failed" with-work

echo "# a stamp that does not read back stops the block before it merges"
clone polecat/w1
DROP_WRITES=1 run_block "$(bead polecat/w1 '{"rejection_reason":"tests failed"}')"
eq "$RC" "1" "(9) the block exits 1"
eq "$(grep -c '^git merge' "$CALLS")" "0" "(9) git merge is not run"
eq "$(g "$C" rev-parse HEAD)" "$W1" "(9) HEAD stays at the PR head"
eq "$(grep -c -- '--unset-metadata rejection_reason' "$CALLS")" "0" "(9) rejection_reason is not cleared, so a re-run resumes the same rejection"

echo
echo "rejected-branch-resume-mode: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
