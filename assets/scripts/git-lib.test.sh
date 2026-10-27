#!/usr/bin/env bash
# git-lib.test.sh — hermetic tests for git-lib.sh, the one read of a branch's
# head on a repository's origin, against real git and local repositories:
#
#   - each head comes from its branch's exact ref, never from a ref whose name
#     ends in it;
#   - a branch origin does not carry answers nothing, and the single read
#     fails on it while the many-branch read still answers for the others;
#   - an origin that does not answer fails the read with nothing printed, so a
#     caller can tell it from a branch origin lacks;
#   - the read runs in the repository it names, whatever the working directory;
#   - every call goes through git_remote_run, which a caller can redefine.
#
# No gc, store or network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-git-lib-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# shellcheck source=git-lib.sh
. "$HERE/git-lib.sh"

commit_on() { # <repo> <branch> <message> — a commit of its own on <branch>
  git -C "$1" checkout -q -B "$2" 2>/dev/null
  git -C "$1" commit -q --allow-empty -m "$3"
  git -C "$1" rev-parse HEAD
}

# origin carries feat, other, and a branch whose ref ends in feat's ref.
ORIGIN="$TMP/origin"; git init -q "$ORIGIN"
FEAT=$(commit_on "$ORIGIN" feat "feat")
OTHER=$(commit_on "$ORIGIN" other "other")
TAIL=$(commit_on "$ORIGIN" a/refs/heads/feat "a ref ending in feat's ref")
git clone -q "$ORIGIN" "$TMP/work" 2>/dev/null
WORK="$TMP/work"

echo "# a branch's head comes from its exact ref"
[ "$TAIL" != "$FEAT" ] && ok "the fixture's two refs ending in refs/heads/feat name different commits" \
  || bad "the fixture's two refs ending in refs/heads/feat name different commits"
eq "$(git -C "$WORK" ls-remote origin refs/heads/feat | wc -l | tr -d ' ')" "2" \
  "ls-remote itself answers refs/heads/feat with both refs"
OUT=$(remote_branch_head "$WORK" feat); rc=$?
eq "$rc" "0" "remote_branch_head reads feat"
eq "$OUT" "$FEAT" "…as the commit at refs/heads/feat, not the one at refs/heads/a/refs/heads/feat"
eq "$(remote_branch_head "$WORK" a/refs/heads/feat)" "$TAIL" "the longer branch reads as its own head"

echo "# many branches in one read"
OUT=$(remote_branch_heads "$WORK" feat other nonesuch); rc=$?
eq "$rc" "0" "remote_branch_heads answers when origin does"
eq "$(printf '%s\n' "$OUT" | sort)" "$(printf '%s\t%s\n%s\t%s\n' "$FEAT" feat "$OTHER" other | sort)" \
  "…one <oid>\\t<branch> line for each branch origin carries, from its exact ref"
eq "$(printf '%s\n' "$OUT" | grep -c nonesuch)" "0" "…and none for a branch origin does not carry"
eq "$(remote_branch_heads "$WORK" feat feat | wc -l | tr -d ' ')" "1" "a branch named twice answers once"

echo "# a branch origin does not carry"
OUT=$(remote_branch_head "$WORK" nonesuch); rc=$?
[ "$rc" -ne 0 ] && ok "remote_branch_head fails on it" || bad "remote_branch_head fails on it" "rc=$rc"
eq "$OUT" "" "…printing nothing"
OUT=$(remote_branch_heads "$WORK" nonesuch); rc=$?
eq "$rc,$OUT" "0," "remote_branch_heads answers it with no line and exit 0: origin answered"

echo "# an origin that does not answer"
git clone -q "$ORIGIN" "$TMP/gone" 2>/dev/null
git -C "$TMP/gone" remote set-url origin "$TMP/no-such-origin"
OUT=$(remote_branch_heads "$TMP/gone" feat); rc=$?
[ "$rc" -ne 0 ] && ok "remote_branch_heads fails when origin does not answer" || bad "remote_branch_heads fails when origin does not answer" "rc=$rc"
eq "$OUT" "" "…printing nothing"
OUT=$(remote_branch_head "$TMP/gone" feat); rc=$?
[ "$rc" -ne 0 ] && [ -z "$OUT" ] && ok "remote_branch_head fails the same way" || bad "remote_branch_head fails the same way" "rc=$rc out=$OUT"
remote_branch_heads "" feat >/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "a read that names no repository fails" || bad "a read that names no repository fails"
remote_branch_heads "$WORK" >/dev/null; rc=$?
[ "$rc" -ne 0 ] && ok "a read that names no branch fails" || bad "a read that names no branch fails"

echo "# the read runs in the repository it names"
# Another repository whose origin carries a feat of its own: the working
# directory's origin never answers for the named one.
ELSE_ORIGIN="$TMP/else-origin"; git init -q "$ELSE_ORIGIN"
ELSE_FEAT=$(commit_on "$ELSE_ORIGIN" feat "another repository's feat")
git clone -q "$ELSE_ORIGIN" "$TMP/else" 2>/dev/null
eq "$(cd "$TMP/else" && remote_branch_head "$WORK" feat)" "$FEAT" "from another checkout, the named repository's head is read"
eq "$(cd "$TMP/else" && remote_branch_head . feat)" "$ELSE_FEAT" "…and . names the working directory's own"
eq "$(cd "$TMP" && remote_branch_head "$WORK" feat)" "$FEAT" "…and from a directory that is no checkout at all"

echo "# every call goes through git_remote_run"
git_remote_run() { printf '%s\n' "$*" >> "$TMP/runner.log"; "$@"; }
: > "$TMP/runner.log"
remote_branch_heads "$WORK" feat other >/dev/null
eq "$(cat "$TMP/runner.log")" "git -C $WORK ls-remote origin refs/heads/feat refs/heads/other" \
  "a redefined runner runs the one ls-remote, pinned to the repository"
git_remote_run() { return 124; }
OUT=$(remote_branch_head "$WORK" feat); rc=$?
[ "$rc" -ne 0 ] && [ -z "$OUT" ] && ok "a runner that fails, as a timeout does, fails the read" || bad "a runner that fails fails the read" "rc=$rc out=$OUT"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
