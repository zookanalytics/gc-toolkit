#!/usr/bin/env bash
# Hermetic test for direct-merge-push.sh, the refinery's direct-mode landing.
#
# Runs the real script against real git repositories: a bare origin, the rig
# cloned from it, and the prep worktree the rebase step leaves at
# <rig git dir>/gc-refinery-prep. lifecycle.sh and gc are stubs that log their
# calls. Proves:
#   - a prepared head that fast-forwards origin/main lands there by commit id,
#     is read back from origin, and is recorded and closed through one
#     lifecycle transition handed the rig as GC_RIG_ROOT, with no scratch
#     worktree, no scratch file and no local branch moved;
#   - a prepared head origin/main moved past since it was prepared lands
#     nothing, records nothing and exits 4, and one that shares no history with
#     origin/main exits 1;
#   - a prepared head origin/main already carries closes as that tip;
#   - a push refused for branch protection promotes the bead to
#     merge_strategy=pr and exits 3, and any other refused push, a push origin
#     does not read back, or a transition that does not land, exits 1;
#   - an unresolvable rig and a missing prepared head land nothing;
#   - the script never drains the session.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-direct-merge-push-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1' want '$2'"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "missing '$2' in: $1" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq is required"  >&2; exit 1; }

unset GC_RIG_ROOT GC_RIG GC_CITY_PATH GC_PACK_DIR 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# The script under test, beside a stub lifecycle.sh that logs each transition
# and the GC_RIG_ROOT it was handed, and fails when LC_FAIL is set.
SUT="$TMP/sut"
mkdir -p "$SUT" "$TMP/bin"
cp "$HERE/direct-merge-push.sh" "$SUT/"
chmod +x "$SUT/direct-merge-push.sh"
cat > "$SUT/lifecycle.sh" <<'LC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LC_LOG"
echo "${GC_RIG_ROOT:-<unset>}" >> "$FAKE_LC_LOG.root"
[ -z "${LC_FAIL:-}" ] || { echo "lifecycle: refused" >&2; exit 1; }
LC
chmod +x "$SUT/lifecycle.sh"
# gc answers the roster for `rig list` and logs every call.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GC_LOG"
case "$1 $2" in
  "rig list") cat "$FAKE_ROSTER" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

commit() { git -C "$1" commit -q --allow-empty -m "$2"; git -C "$1" rev-parse HEAD; }
wt_count() { git -C "$1" worktree list --porcelain | grep -c '^worktree '; }

# setup <dir>: origin with main and polecat/wb one commit ahead, the rig
# cloned from it, and the prep worktree staged at polecat/wb. Sets D, BASE,
# FEATURE and PREP.
setup() {
  D="$1"
  mkdir -p "$D/tmp"
  git init -q --bare -b main "$D/origin.git"
  git init -q -b main "$D/seed"
  BASE=$(commit "$D/seed" "base")
  git -C "$D/seed" push -q "$D/origin.git" main
  git -C "$D/seed" checkout -q -b polecat/wb
  FEATURE=$(commit "$D/seed" "feature")
  git -C "$D/seed" push -q "$D/origin.git" polecat/wb
  git -C "$D/seed" checkout -q main
  git clone -q "$D/origin.git" "$D/rig"
  PREP="$(git -C "$D/rig" rev-parse --path-format=absolute --git-common-dir)/gc-refinery-prep"
  git -C "$D/rig" worktree add -q -f --detach "$PREP" origin/polecat/wb
  printf '{"rigs":[{"name":"myrig","path":"%s"}]}\n' "$D/rig" > "$D/roster.json"
  : > "$D/gc.log"; : > "$D/lc.log"
}

# run [<env>...]: the script from a directory outside every repository, with
# GC_RIG_ROOT naming the rig unless the case overrides it. Sets RC and OUT.
run() {
  OUT=$(cd "$D/tmp" && env TMPDIR="$D/tmp" GC_RIG_ROOT="$D/rig" GC_RIG=myrig FAKE_ROSTER="$D/roster.json" \
    FAKE_GC_LOG="$D/gc.log" FAKE_LC_LOG="$D/lc.log" "$@" "$SUT/direct-merge-push.sh" --work wb --target main 2>&1)
  RC=$?
}
no_drain() {
  if grep -q 'runtime drain-ack' "$D/gc.log"; then bad "$1: the script does not drain the session"; else ok "$1: the script does not drain the session"; fi
}
no_transition() {
  if [ -s "$D/lc.log" ]; then bad "$1: no lifecycle transition" "$(cat "$D/lc.log")"; else ok "$1: no lifecycle transition"; fi
}

echo "── a prepared head that fast-forwards main lands by commit id ──"
setup "$TMP/ff"
RIG_HEAD_BEFORE=$(git -C "$D/rig" rev-parse HEAD)
run
eq "$RC" 0 "ff: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "ff: origin/main is the prepared head"
eq "$(git -C "$D/rig" rev-parse origin/main)" "$FEATURE" "ff: the rig's origin/main is read back at the prepared head"
case "$(cat "$D/lc.log")" in
  "transition wb --to merged --close --set merged_sha=$FEATURE --set merged_target=main --unset rejection_reason --append-notes Merged to main at "*)
    ok "ff: recorded and closed through one lifecycle transition" ;;
  *) bad "ff: recorded and closed through one lifecycle transition" "$(cat "$D/lc.log")" ;;
esac
eq "$(wc -l < "$D/lc.log" | tr -d ' ')" 1 "ff: exactly one transition"
eq "$(cat "$D/lc.log.root")" "$D/rig" "ff: the transition is handed the rig as GC_RIG_ROOT"
eq "$(wt_count "$D/rig")" 2 "ff: no worktree is added; the rig and its prep worktree remain"
eq "$(ls -A "$D/tmp" | wc -l | tr -d ' ')" 0 "ff: nothing is written under TMPDIR"
eq "$(git -C "$D/rig" rev-parse HEAD)" "$RIG_HEAD_BEFORE" "ff: the rig's HEAD does not move"
eq "$(git -C "$D/rig" for-each-ref --format='%(refname)' refs/heads/ | tr '\n' ' ')" "refs/heads/main " "ff: no local branch is created"
no_drain ff

echo "── the roster names the rig when GC_RIG_ROOT is empty ──"
setup "$TMP/roster"
run GC_RIG_ROOT=
eq "$RC" 0 "roster: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "roster: the prepared head landed on the rig's origin"
eq "$(cat "$D/lc.log.root")" "$D/rig" "roster: the transition is handed the rig the roster named"

echo "── origin/main moved past the prepared head: nothing lands, exit 4 ──"
setup "$TMP/moved"
MOVED=$(commit "$D/seed" "landed while the gate ran")
git -C "$D/seed" push -q "$D/origin.git" main
run
eq "$RC" 4 "moved: exits 4"
has "$OUT" "is not a fast-forward of origin/main" "moved: it says the target moved"
eq "$(git -C "$D/origin.git" rev-parse main)" "$MOVED" "moved: origin/main is untouched"
no_transition moved
no_drain moved

echo "── origin/main shares no history with the prepared head: nothing lands ──"
setup "$TMP/unrelated"
git -C "$D/seed" checkout -q --orphan unrelated
UNRELATED=$(commit "$D/seed" "an unrelated root")
git -C "$D/seed" push -q -f "$D/origin.git" HEAD:main
run
eq "$RC" 1 "unrelated: exits 1"
has "$OUT" "share no history" "unrelated: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$UNRELATED" "unrelated: origin/main is untouched"
no_transition unrelated
no_drain unrelated

echo "── origin/main already carries the prepared head: it closes as that tip ──"
setup "$TMP/landed"
git -C "$D/seed" checkout -q polecat/wb
AHEAD=$(commit "$D/seed" "landed on top")
git -C "$D/seed" push -q "$D/origin.git" "HEAD:main"
run
eq "$RC" 0 "landed: exits 0"
eq "$(git -C "$D/origin.git" rev-parse main)" "$AHEAD" "landed: origin/main stays at its tip"
has "$(cat "$D/lc.log")" "--set merged_sha=$AHEAD " "landed: the transition records the tip that carries the work"

echo "── a push refused for branch protection promotes the bead ──"
setup "$TMP/protected"
cat > "$D/origin.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
echo "GH006: Protected branch update failed for refs/heads/main." >&2
exit 1
HOOK
chmod +x "$D/origin.git/hooks/pre-receive"
run
eq "$RC" 3 "protected: exits 3"
has "$(cat "$D/gc.log")" "bd update wb --set-metadata merge_strategy=pr" "protected: the bead is promoted to merge_strategy=pr"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "protected: origin/main is untouched"
no_transition protected
no_drain protected

echo "── any other refused push stops ──"
setup "$TMP/refused"
cat > "$D/origin.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
echo "the remote is read-only today" >&2
exit 1
HOOK
chmod +x "$D/origin.git/hooks/pre-receive"
run
eq "$RC" 1 "refused: exits 1"
has "$OUT" "Push failed:" "refused: it says the push failed"
has "$OUT" "the remote is read-only today" "refused: it prints what the remote said"
case "$(cat "$D/gc.log")" in *"merge_strategy=pr"*) bad "refused: the bead is not promoted" ;; *) ok "refused: the bead is not promoted" ;; esac
no_transition refused
no_drain refused

echo "── a push origin does not read back stops before any bead state moves ──"
setup "$TMP/unverified"
cat > "$D/origin.git/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
read -r old new ref
git update-ref "$ref" "$old"
HOOK
chmod +x "$D/origin.git/hooks/post-receive"
run
eq "$RC" 1 "unverified: exits 1"
has "$OUT" "PUSH FAILED — origin/main is $BASE, want $FEATURE" "unverified: it names what origin holds"
no_transition unverified
no_drain unverified

echo "── a transition that does not land is reported ──"
setup "$TMP/lcfail"
run LC_FAIL=1
eq "$RC" 1 "lcfail: exits 1"
eq "$(git -C "$D/origin.git" rev-parse main)" "$FEATURE" "lcfail: the landing stands"
has "$OUT" "so wb has landed, but the transition recording it as merged did not land" "lcfail: it says the work landed unrecorded"
no_drain lcfail

echo "── an unresolvable rig lands nothing ──"
setup "$TMP/nomatch"
run GC_RIG_ROOT= GC_RIG=no-such-rig
eq "$RC" 1 "nomatch: exits 1"
has "$OUT" "cannot resolve the rig root" "nomatch: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "nomatch: nothing pushed"
no_transition nomatch
no_drain nomatch

echo "── no prepared head lands nothing ──"
setup "$TMP/noprep"
git -C "$D/rig" worktree remove --force "$PREP"
run
eq "$RC" 1 "noprep: exits 1"
has "$OUT" "no prepared head in $PREP" "noprep: it says why"
eq "$(git -C "$D/origin.git" rev-parse main)" "$BASE" "noprep: nothing pushed"
no_transition noprep

echo "── usage ──"
for args in "" "--work wb" "--target main" "--work wb --target main --extra" "--work"; do
  # shellcheck disable=SC2086 # each case is a word list
  ( cd "$TMP" && "$SUT/direct-merge-push.sh" $args ) >/dev/null 2>&1
  eq "$?" 2 "usage: '$args' exits 2"
done

echo "-----"
echo "direct-merge-push: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
