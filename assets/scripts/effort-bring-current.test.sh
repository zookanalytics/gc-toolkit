#!/usr/bin/env bash
# Hermetic test for the refinery prompt's effort-bring-current block, the
# method by which the refinery carries out a hand-off that brings an
# integration effort's branch current with the default branch. The block runs
# as extracted from agents/refinery/prompt.template.md, against a real git
# origin (a bare repository under the test's temp dir) and a stub gc, so the
# git it runs is the git that ships.
#
# A branch that holds nothing its target lacks is fast-forwarded to it, a
# branch with commits of its own takes a merge of the target, and a branch
# already current is pushed as it is. Each case closes the hand-off once the
# push has landed. The merge commit is signed exactly when the repository's
# commit.gpgSign says so, as `git merge` would sign it.
#
# A merge that conflicts pushes nothing and goes to a polecat, never to a
# person: the block files the merge as a task whose target is the effort's
# branch and whose merge strategy is direct, under the hand-off's parent when it
# has one, with the hand-off and the landing bead waiting on it. Its description
# lists the conflicted files one per line, as git names them, unquoted where git
# allows, and asks the operator only for a product decision. The block then
# settles the task and slings it to the rig's polecat pool on mol-polecat-work
# with --merge direct, so the task lands as a fast-forward of the effort's
# branch whatever merge strategy the rig defaults to, and its merge commit is
# never squashed. It files no human gate, and the hand-off stays open. A create
# that writes the task but answers no id is followed by a read of what the
# hand-off waits on, which finds the task, and the block goes on with it. A
# create that wrote nothing stops the block before anything is sent, and so
# does a hand-off that cannot be read after a create that answered no id,
# saying how to find the task. A settle or a send that does not land stops the
# block, naming the step to finish from, and a run of it then finds the
# hand-off waiting on the task and does nothing more.
#
# A push that origin refuses leaves the branch and the hand-off as they were. A
# hand-off that is closed or still waits on a blocker, a landing bead that
# records no integration branch or no target, and a target origin does not
# carry bring nothing current. No case checks anything out: the rig's checkout
# is left as it was, with no worktree added and no temporary file behind, so
# the block has nothing to remove.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PROMPT="$ROOT/agents/refinery/prompt.template.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-effort-bring-current-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
NL=$'\n'

[ -f "$PROMPT" ] || { echo "refinery prompt not found: $PROMPT" >&2; exit 1; }
BLOCK="$(awk '/# >>> effort-bring-current$/ { f = 1; next } /# <<< effort-bring-current$/ { f = 0 } f' "$PROMPT")"
[ -n "$BLOCK" ] && ok "the block is found between its markers" || bad "the effort-bring-current block is missing from $PROMPT"

# git reads only this config: no signing, a known identity. The signing case
# turns signing on in the rig's own config.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig" HOME="$TMP/home"
mkdir -p "$HOME"
git config --file "$GIT_CONFIG_GLOBAL" user.name "Test"
git config --file "$GIT_CONFIG_GLOBAL" user.email "test@example.invalid"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

# gc answers `bd show <id> --json` from STORE, a JSON array of beads;
# STUB_SHOW_FAIL_AFTER_CREATE makes it fail once a create has written its task.
# `bd close <id> --reason <text>` closes the bead in STORE and logs the reason.
# `bd create` keeps each flag's value as a file under CREATE, adds task-1 to
# STORE, with its title, and a blocks edge onto each bead its --deps names as
# blocks:<id>, and answers task-1's id. STUB_CREATE_FAIL makes it write nothing
# and fail, and STUB_CREATE_NOID makes it write the task and answer a warning
# line before the JSON, which leaves no id to read.
# `<binding> scripts-dir` names STUB_SCRIPTS, and `sling` logs its arguments;
# STUB_SLING_FAIL makes it fail.
mkdir -p "$TMP/bin" "$TMP/scripts"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
case "${1:-} ${2:-}" in
  "bd show")
    [ -z "${STUB_SHOW_FAIL_AFTER_CREATE:-}" ] || [ ! -e "$CREATE/title" ] || { echo "gc bd: the store did not answer" >&2; exit 1; }
    jq -c --arg id "$3" '[.[] | select(.id == $id)]' "$STORE"; exit 0 ;;
  "bd close")
    printf 'close %s %s\n' "$3" "${5:-}" >> "$GC_LOG"
    jq -c --arg id "$3" 'map(if .id == $id then .status = "closed" else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    exit 0 ;;
  "bd create")
    printf 'create\n' >> "$GC_LOG"
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
            then .dependencies += [{id: "task-1", title: $title, dependency_type: "blocks", status: "open"}] else . end)
        + [{id: "task-1", title: $title, status: "open", metadata: $meta, dependencies: []}]' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    [ -z "${STUB_CREATE_NOID:-}" ] || { printf 'warning: the index is stale\n{"id":"task-1"}\n'; exit 0; }
    echo '{"id":"task-1"}'
    exit 0 ;;
  "gc-toolkit scripts-dir")
    printf '%s\n' "$STUB_SCRIPTS"; exit 0 ;;
esac
if [ "${1:-}" = sling ]; then
  shift
  printf 'sling %s\n' "$*" >> "$GC_LOG"
  [ -z "${STUB_SLING_FAIL:-}" ] || { echo "gc sling: the controller did not answer" >&2; exit 1; }
fi
exit 0
STUB
chmod +x "$TMP/bin/gc"
# The pack's scripts the block calls log each call; STUB_SETTLE_FAIL makes
# queue-priority.sh fail. human-gate.sh only logs, so a call to it shows in the
# log.
for s in queue-priority human-gate; do
  { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; printf 'NAME=%s\n' "$s"; cat; } > "$TMP/scripts/$s.sh" <<'STUB'
printf '%s %s\n' "$NAME" "$*" >> "$GC_LOG"
case "$NAME" in
  queue-priority) [ -z "${STUB_SETTLE_FAIL:-}" ] || exit 1 ;;
esac
exit 0
STUB
  chmod +x "$TMP/scripts/$s.sh"
done
export STORE="$TMP/store.json" GC_LOG="$TMP/gc.log" CREATE="$TMP/create" STUB_SCRIPTS="$TMP/scripts" \
  GC_AGENT="rig-1/gc-toolkit.refinery"

ORIGIN="$TMP/origin.git"; SEED="$TMP/seed"; RIG="$TMP/rig"
# commit_on <ref> <file> <text>: a commit on origin's <ref> that writes <text>
# to <file>, made from the seed clone.
commit_on() {
  git -C "$SEED" fetch -q origin
  git -C "$SEED" checkout -q --detach "origin/$1"
  printf '%s\n' "$3" > "$SEED/$2"
  git -C "$SEED" add "$2"
  git -C "$SEED" commit -q -m "$1: $2"
  git -C "$SEED" push -q origin "HEAD:refs/heads/$1"
}
head_of() { git -C "$ORIGIN" rev-parse "refs/heads/$1"; }
signed() { git -C "$ORIGIN" cat-file -p "refs/heads/$1" | grep -c '^gpgsig' || true; }
# setup [<jq edit>]: origin carries main and integration/land-1, both at one
# base commit; the rig's checkout is a clone of it. The store holds the
# hand-off ho-1, under the epic ep-1 and with its one blocker closed, and the
# landing bead land-1, which records the branch and main as its target. The
# edit changes the store.
setup() {
  rm -rf "$ORIGIN" "$SEED" "$RIG" "$TMP/tmpd" "$CREATE"
  mkdir -p "$TMP/tmpd" "$CREATE"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$SEED" 2>/dev/null
  printf 'base\n' > "$SEED/shared.txt"
  git -C "$SEED" add shared.txt
  git -C "$SEED" commit -q -m base
  git -C "$SEED" push -q origin HEAD:refs/heads/main HEAD:refs/heads/integration/land-1
  git clone -q "$ORIGIN" "$RIG"
  RIG_HEAD=$(git -C "$RIG" rev-parse HEAD)
  jq -nc '[
    {id: "ho-1", status: "open", metadata: {}, dependencies: [{id: "out-1", dependency_type: "blocks", status: "closed"}, {id: "ep-1", dependency_type: "parent-child", status: "open"}]},
    {id: "land-1", status: "open", metadata: {branch: "integration/land-1", target: "main"}, dependencies: []}
  ]' > "$STORE"
  [ -z "${1:-}" ] || { jq -c "$1" "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"; }
  : > "$GC_LOG"
}
# run <shell>: the block with its placeholders filled in. Sets RC; its output
# is in $TMP/out and $TMP/err.
run() {
  printf '%s\n' "$BLOCK" | sed -e 's#<the hand-off>#ho-1#g' -e 's#<the landing bead it names>#land-1#g' \
    -e "s#{{ .RigRoot }}#$RIG#g" -e 's#{{ .BindingName }}#gc-toolkit#g' -e 's#{{ .BindingPrefix }}#gc-toolkit.#g' \
    -e 's#{{ .RigName }}#rig-1#g' > "$TMP/block.sh"
  RC=0
  if [ "$1" = zsh ]; then
    PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmpd" zsh -f "$TMP/block.sh" > "$TMP/out" 2> "$TMP/err" || RC=$?
  else
    PATH="$TMP/bin:$PATH" TMPDIR="$TMP/tmpd" bash "$TMP/block.sh" > "$TMP/out" 2> "$TMP/err" || RC=$?
  fi
}
status_of() { jq -r --arg id "$1" '.[] | select(.id == $id) | .status' "$STORE"; }
# untouched: the rig's checkout is where setup left it, with no worktree added
# and no temporary file left behind.
untouched() {
  [ "$(git -C "$RIG" rev-parse HEAD)" = "$RIG_HEAD" ] && [ -z "$(git -C "$RIG" status --porcelain)" ] \
    && [ "$(git -C "$RIG" worktree list | wc -l | tr -d ' ')" = "1" ] && [ -z "$(ls -A "$TMP/tmpd")" ]
}

# The signing case needs ssh-keygen with -Y sign (OpenSSH 8.0 and later).
SIGNKEY=""
if command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -q -t ed25519 -N '' -C test -f "$TMP/signkey" >/dev/null 2>&1 \
   && printf 'x\n' | ssh-keygen -Y sign -n git -f "$TMP/signkey" >/dev/null 2>&1; then
  SIGNKEY="$TMP/signkey"
else
  echo "note - ssh-keygen cannot sign here; the signed-merge case is skipped"
fi

# conflict: main and the effort's branch each change shared.txt and add
# other.txt, so merging main into the branch conflicts in both files. Sets OWN
# and MAIN to the two heads.
conflict() {
  commit_on main shared.txt "main's line"; commit_on main other.txt "main's file"
  commit_on integration/land-1 shared.txt "the effort's line"; commit_on integration/land-1 other.txt "the effort's file"
  OWN=$(head_of integration/land-1); MAIN=$(head_of main)
}
# What a conflict sends, in order: the task's create, its settle, and its sling
# to the rig's polecat pool with a direct landing.
SENT="create
queue-priority settle task-1
sling rig-1/gc-toolkit.polecat task-1 --on mol-polecat-work --merge direct"

SHELLS=(bash)
command -v zsh >/dev/null 2>&1 && SHELLS+=(zsh) || echo "note - zsh not present; running under bash only"

for sh in "${SHELLS[@]}"; do
  # The branch holds nothing main lacks: a fast-forward, no merge commit.
  setup; commit_on main a.txt "from main"
  MAIN=$(head_of main)
  run "$sh"
  eq "$RC" "0" "[$sh] fast-forward: the block succeeds"
  eq "$(head_of integration/land-1)" "$MAIN" "[$sh] fast-forward: the branch now points at main's head, with no merge commit"
  eq "$(status_of ho-1)" "closed" "[$sh] fast-forward: the hand-off is closed"
  grep -qF "close ho-1 Brought integration/land-1 current with main at $(git -C "$RIG" rev-parse --short "$MAIN")" "$GC_LOG" \
    && ok "[$sh] fast-forward: the close names the head it pushed" || bad "[$sh] fast-forward: the close reason does not name the pushed head"
  untouched && ok "[$sh] fast-forward: the rig's checkout is untouched" || bad "[$sh] fast-forward: the rig's checkout changed, or a worktree or file was left"

  # The branch carries a commit of its own: main is merged in, unsigned while
  # the repository does not sign.
  setup; commit_on main a.txt "from main"; commit_on integration/land-1 b.txt "from the effort"
  MAIN=$(head_of main); OWN=$(head_of integration/land-1)
  run "$sh"
  eq "$RC" "0" "[$sh] merge: the block succeeds"
  eq "$(git -C "$ORIGIN" rev-list --parents -n 1 refs/heads/integration/land-1 | cut -d' ' -f2-)" "$OWN $MAIN" \
    "[$sh] merge: the branch's head is a merge of main into the branch's own head"
  eq "$(git -C "$ORIGIN" log -1 --format=%s refs/heads/integration/land-1)" "Merge origin/main into integration/land-1 (ho-1)" \
    "[$sh] merge: the merge commit names the target, the branch and the hand-off"
  eq "$(git -C "$ORIGIN" ls-tree --name-only refs/heads/integration/land-1 | tr '\n' ' ')" "a.txt b.txt shared.txt " \
    "[$sh] merge: the merge carries both sides' files"
  eq "$(signed integration/land-1)" "0" "[$sh] merge: a repository that does not sign gets no signature"
  eq "$(status_of ho-1)" "closed" "[$sh] merge: the hand-off is closed"
  untouched && ok "[$sh] merge: the rig's checkout is untouched" || bad "[$sh] merge: the rig's checkout changed, or a worktree or file was left"

  # A repository that signs gets a signed merge commit. tools/run-tests.sh
  # turns signing off through GIT_CONFIG_COUNT entries, which outrank the
  # repository's config, so the case turns it on with an entry after them. It
  # signs with the key the test made, so it needs no signing agent.
  if [ -n "$SIGNKEY" ]; then
    setup; commit_on main a.txt "from main"; commit_on integration/land-1 b.txt "from the effort"
    git -C "$RIG" config gpg.format ssh
    git -C "$RIG" config user.signingkey "$SIGNKEY"
    n=$((10#${GIT_CONFIG_COUNT:-0}))
    export "GIT_CONFIG_KEY_$n=commit.gpgsign" "GIT_CONFIG_VALUE_$n=true" "GIT_CONFIG_COUNT=$((n + 1))"
    run "$sh"
    export "GIT_CONFIG_COUNT=$n"; unset "GIT_CONFIG_KEY_$n" "GIT_CONFIG_VALUE_$n"
    eq "$RC $(signed integration/land-1)" "0 1" "[$sh] signed merge: the merge commit carries a signature when commit.gpgSign is on"
  fi

  # The branch already carries main: nothing new is pushed.
  setup; commit_on integration/land-1 b.txt "from the effort"
  OWN=$(head_of integration/land-1)
  run "$sh"
  eq "$RC $(head_of integration/land-1) $(status_of ho-1)" "0 $OWN closed" "[$sh] current: a branch already current is left as it is and the hand-off closes"

  # Both sides change two files: the merge conflicts, so nothing is pushed, and
  # the merge goes to a polecat as a task, never to a person.
  setup; conflict
  run "$sh"
  eq "$RC" "0" "[$sh] conflict: the block succeeds once the merge is sent to a polecat"
  eq "$(head_of integration/land-1) $(status_of ho-1)" "$OWN open" "[$sh] conflict: the branch is not pushed and the hand-off stays open"
  eq "$(cat "$GC_LOG")" "$SENT" \
    "[$sh] conflict: it files the task, then settles it and slings it to the rig's polecat pool on mol-polecat-work with --merge direct"
  grep -qxF "sling rig-1/gc-toolkit.polecat task-1 --on mol-polecat-work --merge direct" "$GC_LOG" \
    && ok "[$sh] conflict: the sling pins the task's landing with --merge direct, which outranks the rig's default strategy, so a squash never drops the merge" \
    || bad "[$sh] conflict: the sling does not pin the task's landing with --merge direct"
  grep -q '^human-gate' "$GC_LOG" && bad "[$sh] conflict: a human gate was filed" || ok "[$sh] conflict: no human gate is filed"
  eq "$(cat "$CREATE/title")" "Merge origin/main into integration/land-1 and resolve its conflicts" "[$sh] conflict: the task's title names the merge"
  eq "$(cat "$CREATE/t") $(cat "$CREATE/parent") $(jq -c . "$CREATE/metadata") $(cat "$CREATE/deps")" \
    'task ep-1 {"target":"integration/land-1","merge_strategy":"direct"} blocks:ho-1,blocks:land-1' \
    "[$sh] conflict: the task sits under the hand-off's epic, targets the effort's branch, records direct as its merge strategy, and the hand-off and the landing bead wait on it"
  [ -e "$CREATE/unknown" ] && bad "[$sh] conflict: the create passed arguments the stub does not know: $(tr '\n' ' ' < "$CREATE/unknown")" \
    || ok "[$sh] conflict: the create passes only the title and the flags read above"
  BRIEF=$(cat "$CREATE/d")
  for want in "merging origin/main at $MAIN into it at $OWN conflicts in these files, one per line:${NL}${NL}other.txt${NL}shared.txt${NL}${NL}It pushed nothing, and ho-1 waits on this task." \
              "whose second parent is origin/main, and never rebase or squash it" "say for each file what collided and what you decided" \
              "git show --remerge-diff" "Your checks run on the merged tree" \
              "A check that fails the same way at origin/main is a failure of main's own, so treat it as pre-existing" \
              "so that git diff --quiet origin/integration/land-1 HEAD exits 0" "Say so in the notes you hand off with, and name the merge commit" \
              "Ask the operator only when a resolution needs a product decision"; do
    case "$BRIEF" in
      *"$want"*) ok "[$sh] conflict: the task's description says \"${want%%"$NL"*}\"" ;;
      *) bad "[$sh] conflict: the task's description does not say \"${want%%"$NL"*}\"" ;;
    esac
  done
  grep -qF "pushed nothing: merging origin/main into integration/land-1 conflicts in other.txt, shared.txt, so task-1 sends the merge to a polecat, and ho-1 comes back to you once task-1 lands" "$TMP/out" \
    && ok "[$sh] conflict: it says it pushed nothing, names the files and the task" || bad "[$sh] conflict: it does not say it pushed nothing, naming the files and the task"
  untouched && ok "[$sh] conflict: the rig's checkout is untouched" || bad "[$sh] conflict: the rig's checkout changed, or a worktree or file was left"

  # A conflicted path keeps its spaces and its characters outside ASCII: the
  # description lists it on a line of its own, and git does not quote it.
  setup
  commit_on main "My Notes.md" "main's notes"; commit_on main "café.md" "main's café"
  commit_on integration/land-1 "My Notes.md" "the effort's notes"; commit_on integration/land-1 "café.md" "the effort's café"
  run "$sh"
  case "$(cat "$CREATE/d")" in
    *"one per line:${NL}${NL}My Notes.md${NL}café.md${NL}${NL}It pushed nothing"*) ok "[$sh] paths: the description lists each conflicted path on its own line, as it is" ;;
    *) bad "[$sh] paths: the description does not list each conflicted path on its own line, as it is" ;;
  esac
  grep -qF "conflicts in My Notes.md, café.md, so task-1 sends the merge" "$TMP/out" \
    && ok "[$sh] paths: the message names the paths as they are, joined by commas" || bad "[$sh] paths: the message does not name the paths as they are, joined by commas"

  # A hand-off with no parent files its task with none.
  setup 'map(if .id == "ho-1" then .dependencies |= map(select(.dependency_type != "parent-child")) else . end)'; conflict
  run "$sh"
  eq "$RC" "0" "[$sh] conflict, no parent: the block succeeds"
  eq "$(cat "$GC_LOG")" "$SENT" "[$sh] conflict, no parent: the task is filed and sent all the same"
  [ -e "$CREATE/parent" ] && bad "[$sh] conflict, no parent: the task was filed under '$(cat "$CREATE/parent")'" \
    || ok "[$sh] conflict, no parent: the task is filed with no parent"

  # A create that wrote nothing stops before anything is sent, and says the
  # block can run again.
  setup; conflict
  export STUB_CREATE_FAIL=1; run "$sh"; unset STUB_CREATE_FAIL
  eq "$([ "$RC" -ne 0 ] && echo stopped) $(cat "$GC_LOG") $(head_of integration/land-1) $(status_of ho-1)" "stopped create $OWN open" \
    "[$sh] create fails: the block stops with nothing sent, pushed or closed"
  grep -qF "the create of its task wrote nothing; run the block again" "$TMP/err" \
    && ok "[$sh] create fails: it says the create wrote nothing and the block can run again" || bad "[$sh] create fails: it does not say the create wrote nothing"

  # A create that writes the task but answers no id: the hand-off waits on the
  # task it wrote, so the block finds the task there and sends it all the same.
  setup; conflict
  export STUB_CREATE_NOID=1; run "$sh"; unset STUB_CREATE_NOID
  eq "$RC $(cat "$GC_LOG" | tr '\n' '|')" "0 $(printf '%s\n' "$SENT" | tr '\n' '|')" \
    "[$sh] create answers no id: the block finds the task the create wrote among what the hand-off waits on, then settles and sends it"
  eq "$(head_of integration/land-1) $(status_of ho-1)" "$OWN open" "[$sh] create answers no id: the branch is not pushed and the hand-off stays open"

  # A create that answers no id and a hand-off that cannot be read then: the
  # block stops with nothing more sent, saying how to find the task.
  setup; conflict
  export STUB_CREATE_NOID=1 STUB_SHOW_FAIL_AFTER_CREATE=1; run "$sh"; unset STUB_CREATE_NOID STUB_SHOW_FAIL_AFTER_CREATE
  eq "$([ "$RC" -ne 0 ] && echo stopped) $(cat "$GC_LOG")" "stopped create" "[$sh] create answers no id, hand-off unread: the block stops with nothing sent"
  grep -qF "reading ho-1 did not settle whether the create wrote it. gc bd show ho-1 lists what it waits on: finish from the settle with the open task titled \"Merge origin/main into integration/land-1 and resolve its conflicts\", or run the block again when it waits on none" "$TMP/err" \
    && ok "[$sh] create answers no id, hand-off unread: it says how to find the task and what to do either way" \
    || bad "[$sh] create answers no id, hand-off unread: it does not say how to find the task"

  # A settle that does not land stops the block before the send, and names the
  # settle as the step to finish from. A run of it then finds the hand-off
  # waiting on the task and does nothing more.
  setup; conflict
  export STUB_SETTLE_FAIL=1; run "$sh"; unset STUB_SETTLE_FAIL
  eq "$([ "$RC" -ne 0 ] && echo stopped) $(cat "$GC_LOG" | tr '\n' '|')" "stopped create|queue-priority settle task-1|" \
    "[$sh] settle fails: the block stops before the send"
  grep -qF "filed task-1 for the conflict in other.txt, shared.txt, but task-1 was not settled, so it was not sent; finish from the settle" "$TMP/err" \
    && ok "[$sh] settle fails: it names the settle as the step to finish from" || bad "[$sh] settle fails: it does not name the settle as the step to finish from"
  grep -q '^human-gate' "$GC_LOG" && bad "[$sh] settle fails: a human gate was filed" || ok "[$sh] settle fails: no human gate is filed"
  : > "$GC_LOG"; run "$sh"
  eq "$([ "$RC" -ne 0 ] && echo refused) $(wc -l < "$GC_LOG" | tr -d ' ') $(head_of integration/land-1)" "refused 0 $OWN" \
    "[$sh] settle fails: a run of the block again files, sends and pushes nothing"
  grep -qF "ho-1 does not read as open with every blocker closed" "$TMP/err" \
    && ok "[$sh] settle fails: the run again says the hand-off waits" || bad "[$sh] settle fails: the run again does not say the hand-off waits"

  # A sling that exits non-zero stops the block once the task is settled, and
  # names the send as the step to finish from.
  setup; conflict
  export STUB_SLING_FAIL=1; run "$sh"; unset STUB_SLING_FAIL
  eq "$([ "$RC" -ne 0 ] && echo stopped) $(cat "$GC_LOG" | tr '\n' '|')" "stopped $(printf '%s\n' "$SENT" | tr '\n' '|')" \
    "[$sh] send fails: the block stops after the settle and the sling"
  grep -qF "filed task-1 for the conflict in other.txt, shared.txt and settled it, but its sling exited non-zero; finish from the send" "$TMP/err" \
    && ok "[$sh] send fails: it names the send as the step to finish from" || bad "[$sh] send fails: it does not name the send as the step to finish from"
  grep -q '^human-gate' "$GC_LOG" && bad "[$sh] send fails: a human gate was filed" || ok "[$sh] send fails: no human gate is filed"

  # Origin refuses the push: the hand-off stays open.
  setup; commit_on main a.txt "from main"
  printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod +x "$ORIGIN/hooks/pre-receive"
  BASE=$(head_of integration/land-1)
  run "$sh"
  eq "$([ "$RC" -ne 0 ] && echo refused) $(head_of integration/land-1) $(status_of ho-1)" "refused $BASE open" \
    "[$sh] refused push: the block exits non-zero, and the branch and the hand-off are as they were"

  # What the block refuses before it pushes anything.
  for edit in \
    'map(if .id == "ho-1" then .dependencies[0].status = "open" else . end)' \
    'map(if .id == "ho-1" then .status = "closed" else . end)' \
    'map(if .id == "land-1" then .metadata.branch = "polecat/land-1" else . end)' \
    'map(if .id == "land-1" then .metadata = {target: "main"} else . end)' \
    'map(if .id == "land-1" then .metadata = {branch: "integration/land-1"} else . end)' \
    'map(if .id == "land-1" then .metadata.target = "trunk" else . end)'; do
    setup "$edit"; commit_on main a.txt "from main"
    BASE=$(head_of integration/land-1)
    run "$sh"
    if [ "$RC" -ne 0 ] && [ "$(head_of integration/land-1)" = "$BASE" ] && ! grep -q '^close' "$GC_LOG" && untouched; then
      ok "[$sh] refused: $edit brings nothing current"
    else
      bad "[$sh] refused: $edit still brought the branch current or closed the hand-off (rc=$RC)"
    fi
  done
done

echo
echo "effort-bring-current: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
