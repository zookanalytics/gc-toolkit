#!/usr/bin/env bash
# Hermetic test for branch-push.sh, the lease push every city writer of a
# branch goes through. Runs the real script against real git repositories: a
# bare origin and a clone. Proves:
#   - a head that descends from the commit read lands while the branch still
#     holds that commit;
#   - a branch that moved after the read refuses the push and keeps the commit
#     someone else pushed, even when the new head descends from that commit
#     too, which a plain push would have landed;
#   - a head that does not descend from the commit read sends nothing, so the
#     lease never forces;
#   - --new creates an absent branch and refuses one that exists;
#   - --from-origin leases on what origin's branch holds when it reads, creates
#     a branch origin does not carry, and sends nothing when the read does not
#     answer;
#   - a branch that already holds the head is a success;
#   - a push the server refuses for another reason exits 1;
#   - usage and a head that is not a commit exit before anything is sent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-branch-push-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

SUT="$HERE/branch-push.sh"

# fixture <name>: a bare origin with main and feat/x one commit apart, a clone
# of it at $D/clone, and R, the commit the clone read on feat/x.
fixture() {
  D="$TMP/$1"
  mkdir -p "$D"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  git -C "$D/seed" commit -q --allow-empty -m base
  git -C "$D/seed" remote add origin "$D/origin.git"
  git -C "$D/seed" push -q origin main
  git -C "$D/seed" checkout -q -b feat/x
  git -C "$D/seed" commit -q --allow-empty -m work
  git -C "$D/seed" push -q origin feat/x
  git clone -q "$D/origin.git" "$D/clone"
  R=$(git -C "$D/clone" rev-parse origin/feat/x)
}
# commit_on <repo> <parent> <message>: a commit on <parent>, printed.
commit_on() {
  git -C "$1" commit-tree -p "$2" -m "$3" "$(git -C "$1" rev-parse "$2^{tree}")"
}
tip() { git -C "$D/origin.git" rev-parse "refs/heads/$1" 2>/dev/null || echo "<absent>"; }
# someone_pushes <commit-message>: another writer moves feat/x on origin.
someone_pushes() {
  git -C "$D/seed" fetch -q origin
  git -C "$D/seed" reset -q --hard origin/feat/x
  git -C "$D/seed" commit -q --allow-empty -m "$1"
  git -C "$D/seed" push -q origin feat/x
  git -C "$D/seed" rev-parse HEAD
}

echo "# a head that descends from the commit read lands"
fixture lands
N=$(commit_on "$D/clone" "$R" next)
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from "$R" 2>&1); RC=$?
eq "$RC" 0 "the push exits 0"
eq "$(tip feat/x)" "$N" "origin's branch holds the new head"
has "$OUT" "feat/x on origin holds $N" "it says what the branch holds"

echo "# a branch that moved after the read refuses the push"
fixture moved
N=$(commit_on "$D/clone" "$R" mine)
THEIRS=$(someone_pushes theirs)
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from "$R" 2>&1); RC=$?
eq "$RC" 3 "a branch that moved after the read exits 3"
eq "$(tip feat/x)" "$THEIRS" "the commit someone else pushed stays"

echo "# the lease binds the push to the commit read, even over a head that descends from the moved branch"
fixture binds
THEIRS=$(someone_pushes theirs)
git -C "$D/clone" fetch -q origin
N=$(commit_on "$D/clone" "$THEIRS" "mine on theirs")
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from "$R" 2>&1); RC=$?
eq "$RC" 3 "a branch that moved after the read exits 3"
eq "$(tip feat/x)" "$THEIRS" "nothing landed over the commit someone else pushed"
has "$OUT" "moved after the writer read $R" "it names the commit the writer read"

echo "# a head that does not descend from the commit read sends nothing"
fixture rewrite
BASE=$(git -C "$D/clone" rev-parse origin/main)
N=$(commit_on "$D/clone" "$BASE" rewrite)
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from "$R" 2>&1); RC=$?
eq "$RC" 4 "a rewrite exits 4"
eq "$(tip feat/x)" "$R" "the branch keeps the commit read"
has "$OUT" "does not descend from $R" "it says the head does not descend from the read"

echo "# --new creates an absent branch and refuses one that exists"
fixture new
N=$(commit_on "$D/clone" "$R" fresh)
OUT=$("$SUT" --repo "$D/clone" --branch feat/y --head "$N" --new 2>&1); RC=$?
eq "$RC" 0 "an absent branch is created"
eq "$(tip feat/y)" "$N" "origin's new branch holds the head"
N2=$(commit_on "$D/clone" "$N" again)
OUT=$("$SUT" --repo "$D/clone" --branch feat/y --head "$N2" --new 2>&1); RC=$?
eq "$RC" 3 "a branch that exists refuses --new (exit 3)"
eq "$(tip feat/y)" "$N" "the existing branch keeps its head"

echo "# a branch that already holds the head is a success"
fixture same
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$R" --from "$R" 2>&1); RC=$?
eq "$RC" 0 "pushing the commit the branch holds exits 0"
eq "$(tip feat/x)" "$R" "the branch is unchanged"

echo "# a push the server refuses for another reason exits 1"
fixture hook
printf '#!/bin/sh\necho "policy says no" >&2\nexit 1\n' > "$D/origin.git/hooks/pre-receive"
chmod +x "$D/origin.git/hooks/pre-receive"
N=$(commit_on "$D/clone" "$R" refused)
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from "$R" 2>&1); RC=$?
eq "$RC" 1 "a refused push exits 1"
has "$OUT" "policy says no" "it carries what the server said"
eq "$(tip feat/x)" "$R" "nothing landed"

echo "# --from-origin takes what origin's branch holds now as the read"
fixture origin-read
N=$(commit_on "$D/clone" "$R" "from origin")
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from-origin 2>&1); RC=$?
eq "$RC" 0 "a head that descends from the branch as origin holds it lands"
eq "$(tip feat/x)" "$N" "origin's branch holds the new head"
N2=$(commit_on "$D/clone" "$R" "beside it")
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N2" --from-origin 2>&1); RC=$?
eq "$RC" 4 "a head that does not hold origin's branch sends nothing"
eq "$(tip feat/x)" "$N" "the branch keeps what it holds"
OUT=$("$SUT" --repo "$D/clone" --branch feat/z --head "$N" --from-origin 2>&1); RC=$?
eq "$RC" 0 "a branch origin does not carry is created"
eq "$(tip feat/z)" "$N" "origin's new branch holds the head"
git -C "$D/clone" remote set-url origin "$D/no-such-origin.git"
OUT=$("$SUT" --repo "$D/clone" --branch feat/x --head "$N" --from-origin 2>&1); RC=$?
eq "$RC" 1 "a read of origin that does not answer exits 1"
has "$OUT" "did not read" "it says the branch did not read"

echo "# usage and a head that is not a commit"
fixture usage
"$SUT" --repo "$D/clone" --branch feat/x --head "$R" >/dev/null 2>&1; eq "$?" 2 "neither --from nor --new is usage"
"$SUT" --repo "$D/clone" --branch feat/x --head "$R" --from "$R" --new >/dev/null 2>&1; eq "$?" 2 "both --from and --new is usage"
"$SUT" --repo "$D/clone" --branch feat/x --head "$R" --new --from-origin >/dev/null 2>&1; eq "$?" 2 "both --new and --from-origin is usage"
"$SUT" --repo "$D/clone" --branch 'bad..name' --head "$R" --new >/dev/null 2>&1; eq "$?" 2 "a malformed branch name is usage"
"$SUT" --repo "$D/clone" --branch feat/x --head deadbeef --from "$R" >/dev/null 2>&1; eq "$?" 1 "a head that is not a commit exits 1"
eq "$(tip feat/x)" "$R" "nothing was sent by any of them"

echo
echo "branch-push: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
