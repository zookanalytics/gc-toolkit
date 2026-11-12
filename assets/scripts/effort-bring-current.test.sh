#!/usr/bin/env bash
# Hermetic test for effort-bring-current.sh, the refinery's hand-off that
# brings an integration effort's branch current with its target. Runs the real
# script and branch-push.sh against real git repositories, in the refinery's
# own worktree, with a fake gc over a JSON store (refinery-test-lib.sh).
# Proves:
#   - a branch that holds nothing its target lacks is fast-forwarded to it, a
#     branch with commits of its own takes a merge of the target, and a branch
#     already current is pushed as it is; each push goes under the lease on the
#     commit read, and the hand-off closes once it lands;
#   - the merge commit is signed exactly when the repository's commit.gpgSign
#     says so;
#   - a merge that conflicts pushes nothing, files a bring-current-conflict gate
#     on the hand-off naming the files, records the notice that hands it back,
#     and leaves the hand-off open;
#   - a push origin refuses leaves the hand-off open;
#   - a hand-off that is closed or still waits on a blocker, and a landing bead
#     that records no integration branch or no target, bring nothing current;
#   - nothing is checked out: the refinery's home is left as it was.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-effort-bring-current-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=refinery-test-lib.sh
. "$HERE/refinery-test-lib.sh"

# fresh [<hand-off deps json>] [<landing metadata json>]: main and
# integration/land-1 at one base; the hand-off ho-1 and the landing bead land-1.
DEPS_CLOSED='[{"id":"out-1","dependency_type":"blocks","status":"closed"}]'
LANDING_META='{"branch":"integration/land-1","target":"main"}'
fresh() {
  local deps="${1:-$DEPS_CLOSED}" landing="${2:-$LANDING_META}"
  rm -rf "${TMP:?}"/*
  rt_init effort-bring-current.sh
  git -C "$SEED" push -q origin main:refs/heads/integration/land-1
  put "$(jq -nc --argjson d "$deps" \
    '{id: "ho-1", title: "Bring current", status: "open", assignee: "rig-a/gc-toolkit.refinery", issue_type: "task", notes: "", metadata: {}, dependencies: $d}')"
  put "$(jq -nc --argjson m "$landing" \
    '{id: "land-1", title: "Landing", status: "open", assignee: "", issue_type: "task", notes: "", metadata: $m}')"
  HOME_HEAD=$(git -C "$HOME_DIR" rev-parse HEAD)
}
run() { OUT=$("$SUT/effort-bring-current.sh" --hand-off ho-1 --landing land-1 2>&1); RC=$?; }
signed() { git -C "$ORIGIN" cat-file -p "refs/heads/$1" | grep -c '^gpgsig' || true; }

echo "# a branch with nothing of its own is fast-forwarded to its target"
fresh
MAIN=$(main_with later.txt)
run
eq "$RC" 0 "the hand-off exits 0"
eq "$(tip integration/land-1)" "$MAIN" "the branch is fast-forwarded to main"
eq "$(bstatus ho-1)" "closed" "the hand-off closes"
eq "$(git -C "$HOME_DIR" rev-parse HEAD)" "$HOME_HEAD" "the home's HEAD never moves"
[ ! -e "$HOME_DIR/worktrees" ] && rt_ok "no tree is added" || rt_bad "no tree is added"

echo "# a branch with commits of its own takes a merge of the target"
fresh
OURS=$(branch_with integration/land-1 unit.txt integration/land-1)
MAIN=$(main_with later.txt)
run
eq "$RC" 0 "the hand-off exits 0"
NEW=$(tip integration/land-1)
eq "$(git -C "$ORIGIN" rev-parse "$NEW^1") $(git -C "$ORIGIN" rev-parse "$NEW^2")" "$OURS $MAIN" "the merge commit joins the branch and its target"
eq "$(signed integration/land-1)" "0" "a repository that does not sign gets no signature"
has "$(git -C "$ORIGIN" log -1 --format=%s "$NEW")" "Merge origin/main into integration/land-1 (ho-1)" "the merge names the hand-off"

echo "# a repository that signs gets a signed merge"
# The signing needs ssh-keygen with -Y sign (OpenSSH 8.0 and later), and signs
# with a key the case makes, so it needs no signing agent. tools/run-tests.sh
# turns signing off through GIT_CONFIG_COUNT entries, which outrank the
# repository's config, so the case also turns it on with an entry after them.
fresh
if command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -q -t ed25519 -N '' -C test -f "$TMP/signkey" >/dev/null 2>&1 \
   && printf 'x\n' | ssh-keygen -Y sign -n git -f "$TMP/signkey" >/dev/null 2>&1; then
  branch_with integration/land-1 unit.txt integration/land-1 >/dev/null
  main_with later.txt >/dev/null
  git -C "$RIG" config gpg.format ssh
  git -C "$RIG" config user.signingkey "$TMP/signkey"
  git -C "$RIG" config commit.gpgSign true
  n=$((10#${GIT_CONFIG_COUNT:-0}))
  export "GIT_CONFIG_KEY_$n=commit.gpgsign" "GIT_CONFIG_VALUE_$n=true" "GIT_CONFIG_COUNT=$((n + 1))"
  run
  export "GIT_CONFIG_COUNT=$n"; unset "GIT_CONFIG_KEY_$n" "GIT_CONFIG_VALUE_$n"
  eq "$RC" 0 "the hand-off exits 0"
  eq "$(signed integration/land-1)" "1" "the merge commit is signed"
else
  echo "note - ssh-keygen cannot sign here; the signed-merge case is skipped"
fi

echo "# a branch already current is pushed as it is"
fresh
OURS=$(branch_with integration/land-1 unit.txt integration/land-1)
run
eq "$RC" 0 "the hand-off exits 0"
eq "$(tip integration/land-1)" "$OURS" "the branch is unchanged"
eq "$(bstatus ho-1)" "closed" "the hand-off closes"

echo "# a merge that conflicts pushes nothing and asks a person"
fresh
OURS=$(branch_with integration/land-1 same.txt integration/land-1)
git -C "$SEED" checkout -q main && git -C "$SEED" pull -q origin main
printf 'main side\n' > "$SEED/same.txt" && git -C "$SEED" add same.txt && git -C "$SEED" commit -q -m "same on main" && git -C "$SEED" push -q origin main
run
eq "$RC" 4 "the hand-off says the merge conflicts (exit 4)"
has "$OUT" "conflicts in same.txt" "it names the conflicted file"
eq "$(tip integration/land-1)" "$OURS" "nothing is pushed"
has "$(logged scripts)" "human-gate --subject ho-1 --key bring-current-conflict" "a bring-current-conflict gate is filed on the hand-off"
has "$(logged scripts)" "same.txt" "…naming the conflicted file"
has "$(logged scripts)" "deferred-dispatch notify ho-1 --agent rig-a/gc-toolkit.refinery" "the notice that hands it back is recorded"
eq "$(bstatus ho-1)" "open" "the hand-off stays open"

echo "# a push origin refuses leaves the hand-off open"
fresh
main_with later.txt >/dev/null
printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
run
eq "$RC" 1 "the hand-off exits 1"
eq "$(bstatus ho-1)" "open" "the hand-off stays open"

echo "# what is not ready brings nothing current"
fresh '[{"id":"out-1","dependency_type":"blocks","status":"open"}]'
BEFORE=$(tip integration/land-1)
main_with later.txt >/dev/null
run
eq "$RC" 3 "a hand-off whose blocker is open exits 3"
eq "$(tip integration/land-1)" "$BEFORE" "…and pushes nothing"
fresh '[]' '{"branch":"polecat/x","target":"main"}'
run
eq "$RC" 1 "a landing bead with no integration branch exits 1"
fresh '[]' '{"branch":"integration/land-1"}'
run
eq "$RC" 1 "a landing bead with no target exits 1"
fresh '[]' '{"branch":"integration/land-1","target":"release/gone"}'
run
eq "$RC" 1 "a target origin does not carry exits 1"
fresh
jq 'map(if .id == "ho-1" then .status = "closed" else . end)' "$STORE" > "$STORE.n" && mv "$STORE.n" "$STORE"
run
eq "$RC" 3 "a closed hand-off exits 3"

echo
echo "effort-bring-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
