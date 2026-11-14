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
#   - a merge that conflicts pushes nothing and goes to a polecat, never to a
#     person: the call proves the polecat pool's route, files the merge as a
#     task whose target is the effort's branch and whose merge strategy is
#     direct, under the hand-off's parent when it has one, with the hand-off
#     and the landing bead waiting on it, then settles the task and slings it
#     on mol-polecat-work with --merge direct; it files no human gate and
#     leaves the hand-off open;
#   - the task's description lists the conflicted files one per line, as git
#     names them, unquoted where git allows, and asks the operator only for a
#     product decision;
#   - a pool with no route and a create that wrote nothing stop the call before
#     anything is sent; a create that answers no id is followed by a read of
#     what the hand-off waits on, which finds the task, and a hand-off that does
#     not read then stops the call, saying how to find the task; a settle or a
#     send that does not land stops the call, naming the step to finish from,
#     and a call again finds the hand-off waiting on the task and brings nothing
#     current;
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
# DEPS_EPIC puts the hand-off under the epic ep-1.
DEPS_CLOSED='[{"id":"out-1","dependency_type":"blocks","status":"closed"}]'
DEPS_EPIC='[{"id":"out-1","dependency_type":"blocks","status":"closed"},{"id":"ep-1","dependency_type":"parent-child","status":"open"}]'
LANDING_META='{"branch":"integration/land-1","target":"main"}'
fresh() {
  local deps="${1:-$DEPS_CLOSED}" landing="${2:-$LANDING_META}"
  rm -rf "${TMP:?}"/*
  rt_init effort-bring-current.sh
  wrap_gc
  git -C "$SEED" push -q origin main:refs/heads/integration/land-1
  put "$(jq -nc --argjson d "$deps" \
    '{id: "ho-1", title: "Bring current", status: "open", assignee: "rig-a/gc-toolkit.refinery", issue_type: "task", notes: "", metadata: {}, dependencies: $d}')"
  put "$(jq -nc --argjson m "$landing" \
    '{id: "land-1", title: "Landing", status: "open", assignee: "", issue_type: "task", notes: "", metadata: $m}')"
  HOME_HEAD=$(git -C "$HOME_DIR" rev-parse HEAD)
}
run() { OUT=$("$SUT/effort-bring-current.sh" --hand-off ho-1 --landing land-1 2>&1); RC=$?; }

# wrap_gc: the fixture's fake gc, with a create of its own. The create keeps
# each flag's value as a file under $CREATE, adds task-1 to the store, with its
# title, and adds a blocks edge onto it to the row of each bead its --deps names
# as blocks:<id>, as `gc bd show` reports a bead's dependencies. It answers
# task-1's id. The create and a sling log to scripts.log, where the stubbed
# scripts log, so that one log holds the order of what a conflict sends. A sling
# then exits as the fixture's does (STUB_SLING_RC). STUB_CREATE_FAIL makes the
# create write nothing and fail, STUB_CREATE_NOID makes it write the task and
# answer a warning line before the JSON, which leaves no id to read, and
# STUB_SHOW_FAIL_AFTER_CREATE makes a show fail once a create has written its
# task.
wrap_gc() {
  CREATE="$TMP/create"; mkdir -p "$CREATE"; export CREATE
  mv "$BIN/gc" "$BIN/gc-fixture"
  cat > "$BIN/gc" <<'GC'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "bd create")
    echo create >> "$LOGS/scripts.log"
    [ -z "${STUB_CREATE_FAIL:-}" ] || { echo '{"error":"the store did not answer"}'; exit 1; }
    printf '%s' "$3" > "$CREATE/title"; shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --json) shift ;;
        -t|--parent|-d|--metadata|--deps) printf '%s' "$2" > "$CREATE/${1#"${1%%[!-]*}"}"; shift 2 ;;
        *) printf '%s\n' "$1" >> "$CREATE/unknown"; shift ;;
      esac
    done
    jq -c --arg deps "$(cat "$CREATE/deps" 2>/dev/null)" --argjson meta "$(cat "$CREATE/metadata")" --arg title "$(cat "$CREATE/title")" '
      ($deps | split(",") | map(select(startswith("blocks:")) | ltrimstr("blocks:"))) as $waiters
      | map(if (.id as $id | $waiters | index($id)) != null
            then .dependencies = ((.dependencies // []) + [{id: "task-1", title: $title, dependency_type: "blocks", status: "open"}])
            else . end)
        + [{id: "task-1", title: $title, status: "open", assignee: "", issue_type: "task", notes: "", metadata: $meta, dependencies: []}]' \
      "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    [ -z "${STUB_CREATE_NOID:-}" ] || { printf 'warning: the index is stale\n{"id":"task-1"}\n'; exit 0; }
    echo '{"id":"task-1"}'
    exit 0 ;;
  "bd show")
    if [ -n "${STUB_SHOW_FAIL_AFTER_CREATE:-}" ] && [ -e "$CREATE/title" ]; then
      echo "gc bd: the store did not answer" >&2; exit 1
    fi ;;
  "sling "*)
    printf 'sling %s\n' "${*:2}" >> "$LOGS/scripts.log" ;;
esac
exec "$(dirname "$0")/gc-fixture" "$@"
GC
  chmod +x "$BIN/gc"
}

# commit_on <ref> <file> <text>: a commit on origin's <ref> that writes <text>
# to <file>, made from the seed clone.
commit_on() {
  git -C "$SEED" fetch -q origin
  git -C "$SEED" checkout -q --detach "origin/$1"
  printf '%s\n' "$3" > "$SEED/$2"
  git -C "$SEED" add "$2" && git -C "$SEED" commit -q -m "$1: $2"
  git -C "$SEED" push -q origin "HEAD:refs/heads/$1"
}
# conflict: main and the effort's branch each write shared.txt and other.txt,
# so merging main into the branch conflicts in both files. Sets OWN and MAIN to
# the two heads.
conflict() {
  commit_on main shared.txt "main's line"; commit_on main other.txt "main's file"
  commit_on integration/land-1 shared.txt "the effort's line"; commit_on integration/land-1 other.txt "the effort's file"
  OWN=$(tip integration/land-1); MAIN=$(tip main)
}
# What a conflict sends, in order: the pool's route, the task's create, its
# settle, and its sling to the rig's polecat pool with a direct landing.
SENT="pool-route gc-toolkit.polecat
create
queue-priority settle task-1
sling rig-a/gc-toolkit.polecat task-1 --on mol-polecat-work --merge direct"
NL=$'\n'
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

echo "# a merge that conflicts pushes nothing and sends the merge to a polecat"
fresh "$DEPS_EPIC"; conflict
run
eq "$RC" 4 "the hand-off says the merge conflicts and went to a polecat (exit 4)"
eq "$(tip integration/land-1) $(bstatus ho-1)" "$OWN open" "nothing is pushed, and the hand-off stays open"
eq "$(logged scripts)" "$SENT" \
  "it proves the pool's route, files the task, then settles it and slings it to the rig's polecat pool on mol-polecat-work with --merge direct"
hasnt "$(logged scripts)" "human-gate" "no human gate is filed"
eq "$(cat "$CREATE/title")" "Merge origin/main into integration/land-1 and resolve its conflicts" "the task's title names the merge"
eq "$(cat "$CREATE/t") $(cat "$CREATE/parent") $(jq -c . "$CREATE/metadata") $(cat "$CREATE/deps")" \
  'task ep-1 {"target":"integration/land-1","merge_strategy":"direct"} blocks:ho-1,blocks:land-1' \
  "the task sits under the hand-off's epic, targets the effort's branch, records direct as its merge strategy, and the hand-off and the landing bead wait on it"
if [ -e "$CREATE/unknown" ]; then
  rt_bad "the create passes only the title and the flags read above" "$(tr '\n' ' ' < "$CREATE/unknown")"
else
  rt_ok "the create passes only the title and the flags read above"
fi
BRIEF=$(cat "$CREATE/d")
for want in "merging origin/main at $MAIN into it at $OWN conflicts in these files, one per line:${NL}${NL}other.txt${NL}shared.txt${NL}${NL}It pushed nothing, and ho-1 waits on this task." \
            "whose second parent is origin/main, and never rebase or squash it" "say for each file what collided and what you decided" \
            "git show --remerge-diff" "Your checks run on the merged tree" \
            "A check that fails the same way at origin/main is a failure of main's own, so treat it as pre-existing" \
            "so that git diff --quiet origin/integration/land-1 HEAD exits 0" "Say so in the notes you hand off with, and name the merge commit" \
            "Ask the operator only when a resolution needs a product decision"; do
  has "$BRIEF" "$want" "the task's description says \"${want%%"$NL"*}\""
done
has "$OUT" "pushed nothing: merging origin/main into integration/land-1 conflicts in other.txt, shared.txt, so task-1 sends the merge to a polecat, and ho-1 comes back to the refinery once task-1 lands" \
  "it says it pushed nothing, and names the files and the task"
eq "$(git -C "$HOME_DIR" rev-parse HEAD)" "$HOME_HEAD" "the home's HEAD never moves"
[ ! -e "$HOME_DIR/worktrees" ] && rt_ok "no tree is added" || rt_bad "no tree is added"

echo "# a conflicted path keeps its spaces and its characters outside ASCII"
fresh "$DEPS_EPIC"
commit_on main "My Notes.md" "main's notes"; commit_on main "café.md" "main's café"
commit_on integration/land-1 "My Notes.md" "the effort's notes"; commit_on integration/land-1 "café.md" "the effort's café"
run
has "$(cat "$CREATE/d")" "one per line:${NL}${NL}My Notes.md${NL}café.md${NL}${NL}It pushed nothing" "the description lists each conflicted path on its own line, as it is"
has "$OUT" "conflicts in My Notes.md, café.md, so task-1 sends the merge" "the message names the paths as they are, joined by commas"

echo "# a hand-off with no parent files its task with none"
fresh; conflict
run
eq "$RC $(logged scripts)" "4 $SENT" "the task is filed and sent all the same"
[ -e "$CREATE/parent" ] && rt_bad "the task is filed with no parent" "filed under '$(cat "$CREATE/parent")'" || rt_ok "the task is filed with no parent"

echo "# a pool with no route files nothing"
fresh "$DEPS_EPIC"; conflict
export STUB_POOL_ROUTE_RC=1; run; unset STUB_POOL_ROUTE_RC
eq "$RC $(logged scripts | tr '\n' '|') $(tip integration/land-1) $(bstatus ho-1)" "1 pool-route gc-toolkit.polecat| $OWN open" \
  "the call stops with nothing filed, sent, pushed or closed"
has "$OUT" "the pool gc-toolkit.polecat resolves to no route, so no task was filed for it" "it says the pool has no route"

echo "# a create that wrote nothing stops before anything is sent"
fresh "$DEPS_EPIC"; conflict
export STUB_CREATE_FAIL=1; run; unset STUB_CREATE_FAIL
eq "$RC $(logged scripts | tr '\n' '|') $(tip integration/land-1) $(bstatus ho-1)" "1 pool-route gc-toolkit.polecat|create| $OWN open" \
  "the call stops with nothing sent, pushed or closed"
has "$OUT" "the create of its task wrote nothing; call again" "it says the create wrote nothing and a call again retries"

echo "# a create that answers no id: the task is found among what the hand-off waits on"
fresh "$DEPS_EPIC"; conflict
export STUB_CREATE_NOID=1; run; unset STUB_CREATE_NOID
eq "$RC $(logged scripts | tr '\n' '|')" "4 $(printf '%s\n' "$SENT" | tr '\n' '|')" \
  "the call finds the task the create wrote, then settles and sends it"
eq "$(tip integration/land-1) $(bstatus ho-1)" "$OWN open" "…pushing nothing, with the hand-off left open"

echo "# a create that answers no id, and a hand-off that does not read then"
fresh "$DEPS_EPIC"; conflict
export STUB_CREATE_NOID=1 STUB_SHOW_FAIL_AFTER_CREATE=1; run; unset STUB_CREATE_NOID STUB_SHOW_FAIL_AFTER_CREATE
eq "$RC $(logged scripts | tr '\n' '|')" "1 pool-route gc-toolkit.polecat|create|" "the call stops with nothing sent"
has "$OUT" "reading ho-1 did not settle whether the create wrote it. gc bd show ho-1 lists what it waits on: finish from the settle with the open task titled \"Merge origin/main into integration/land-1 and resolve its conflicts\", or call again when it waits on none" \
  "it says how to find the task and what to do either way"

echo "# a settle that does not land stops before the send"
fresh "$DEPS_EPIC"; conflict
export STUB_QUEUE_PRIORITY_RC=1; run; unset STUB_QUEUE_PRIORITY_RC
eq "$RC $(logged scripts | tr '\n' '|')" "1 pool-route gc-toolkit.polecat|create|queue-priority settle task-1|" \
  "the call stops before the send"
has "$OUT" "filed task-1 for the conflict in other.txt, shared.txt, but task-1 was not settled, so it was not sent; finish from the settle" \
  "it names the settle as the step to finish from"
hasnt "$(logged scripts)" "human-gate" "no human gate is filed"
reset_logs; run
eq "$RC $(logged scripts | grep -c . || true) $(tip integration/land-1)" "3 0 $OWN" \
  "a call again finds the hand-off waiting on the task, and files, sends and pushes nothing"
has "$OUT" "ho-1 does not read as open with every blocker closed" "…saying the hand-off waits"

echo "# a sling that exits non-zero stops once the task is settled"
fresh "$DEPS_EPIC"; conflict
export STUB_SLING_RC=1; run; export STUB_SLING_RC=0
eq "$RC $(logged scripts | tr '\n' '|')" "1 $(printf '%s\n' "$SENT" | tr '\n' '|')" "the call stops after the settle and the sling"
has "$OUT" "filed task-1 for the conflict in other.txt, shared.txt and settled it, but its sling exited non-zero; finish from the send" \
  "it names the send as the step to finish from"
hasnt "$(logged scripts)" "human-gate" "no human gate is filed"

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
