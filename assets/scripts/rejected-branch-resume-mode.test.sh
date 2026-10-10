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
#   - before the merge moves HEAD, it stamps bring_current_from with the PR
#     head, which is origin's copy of the branch, or HEAD when origin has none;
#   - it unsets rejection_reason;
#   - with no rejection_reason it does nothing.
#
# It EXECUTES the block extracted verbatim from the formula against a real git
# repository with a real bare origin. A gc stub serves the bead, a wrapper runs
# the real git, and both record each call in one log, so a case can read which
# commands ran and in what order. The block's base is rendered as an
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
BIN="$TMP/bin"; mkdir -p "$BIN"
export REAL_GIT CALLS="$TMP/calls.log"
cat > "$BIN/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$CALLS"
exec "$REAL_GIT" "$@"
SH
cat > "$BIN/gc" <<'SH'
#!/usr/bin/env bash
printf 'gc %s\n' "$*" >> "$CALLS"
if [ "${1:-}" = "bd" ] && [ "${2:-}" = "show" ]; then printf '%s' "${BEAD_JSON:-}"; fi
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
# run_block <bead-json> — the block run in $C as a polecat runs it, on a fresh
# call log. Sets RC.
run_block() {
  : > "$CALLS"
  ( cd "$C" && PATH="$BIN:$PATH" BEAD_JSON="$1" WORK_BEAD_ID=tk-w bash "$TMP/block.sh" ) > "$TMP/out" 2>&1
  RC=$?
}
bead() { # <branch> [<metadata json>]
  jq -nc --arg b "$1" --argjson m "${2:-null}" '[{id: "tk-w", metadata: ({branch: $b} + ($m // {}))}]'
}
parents() { g "$C" rev-list --parents -n 1 HEAD | cut -d' ' -f2-; }
called() { grep -qxF -- "$1" "$CALLS"; }
line_of() { grep -nxF -- "$1" "$CALLS" | head -1 | cut -d: -f1; }
rewrites() { grep -cE '^git (rebase|push|reset|commit|cherry-pick|am)( |$)' "$CALLS"; }

echo "# a rejected branch is brought current by merging the base in"
clone polecat/w1
run_block "$(bead polecat/w1 '{"rejection_reason":"stale base: the PR conflicts with its base","prepare_mode":"merge"}')"
eq "$RC" "0" "(1) the resume exits 0"
eq "$(parents)" "$W1 $BASE_TIP" "(1) HEAD is a merge commit of the PR head and origin/$BASE, in that order"
called "git merge --no-edit origin/$BASE" \
  && ok "(1) the base is merged in by git merge --no-edit origin/$BASE" \
  || bad "(1) the base is merged in by git merge --no-edit origin/$BASE" "$(grep '^git ' "$CALLS" | tr '\n' ';')"
eq "$(rewrites)" "0" "(1) nothing rebases, resets, commits, cherry-picks or pushes"
eq "$(g "$CO" rev-parse refs/heads/polecat/w1)" "$W1" "(1) origin's branch is untouched: the resume pushes nothing"
STAMP="gc bd update tk-w --set-metadata bring_current_from=$W1"
MERGE="git merge --no-edit origin/$BASE"
called "$STAMP" && ok "(1) bring_current_from is stamped with the PR head" \
  || bad "(1) bring_current_from is stamped with the PR head" "$(grep '^gc ' "$CALLS" | tr '\n' ';')"
[ -n "$(line_of "$STAMP")" ] && [ -n "$(line_of "$MERGE")" ] && [ "$(line_of "$STAMP")" -lt "$(line_of "$MERGE")" ] \
  && ok "(1) the stamp is written before the merge runs" \
  || bad "(1) the stamp is written before the merge runs" "stamp line '$(line_of "$STAMP")', merge line '$(line_of "$MERGE")'"
called "gc bd update tk-w --unset-metadata rejection_reason" \
  && ok "(1) rejection_reason is unset" \
  || bad "(1) rejection_reason is unset" "$(grep '^gc ' "$CALLS" | tr '\n' ';')"

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
run_block "$(bead polecat/w2 '{"rejection_reason":"stale base: the PR conflicts with its base","prepare_mode":"merge"}')"
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
called "gc bd update tk-w --set-metadata bring_current_from=$W1" \
  && ok "(5) bring_current_from is the PR head origin holds, not the local commit past it" \
  || bad "(5) bring_current_from is the PR head origin holds, not the local commit past it" "$(grep '^gc bd update' "$CALLS" | tr '\n' ';')"
eq "$(parents)" "$AHEAD $BASE_TIP" "(5) the base is merged into the local head"

echo "# a branch origin does not have is stamped with HEAD from before the merge"
clone polecat/w1
g "$C" checkout -q -b polecat/w3
commit_in "$C" local.txt "local" "a commit origin never saw"
LOCAL="$(g "$C" rev-parse HEAD)"
run_block "$(bead polecat/w3 '{"rejection_reason":"tests failed"}')"
called "gc bd update tk-w --set-metadata bring_current_from=$LOCAL" \
  && ok "(6) bring_current_from is the head the resume started from, not its merge commit" \
  || bad "(6) bring_current_from is the head the resume started from, not its merge commit" "$(grep '^gc bd update' "$CALLS" | tr '\n' ';')"
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

echo
echo "rejected-branch-resume-mode: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
