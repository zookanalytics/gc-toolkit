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
# commit.gpgSign says so, as `git merge` would sign it. A merge that conflicts
# pushes nothing, names the files, and leaves the hand-off open. So does a push
# that origin refuses. A hand-off that is closed or still waits on a blocker, a
# landing bead that records no integration branch or no target, and a target
# origin does not carry bring nothing current. No case checks anything out:
# the rig's checkout is left as it was, with no worktree added and no
# temporary file behind, so the block has nothing to remove.
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

# gc answers `bd show <id> --json` from STORE, a JSON array of beads, and
# `bd close <id> --reason <text>` closes the bead in STORE and logs the reason.
mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
case "${1:-} ${2:-}" in
  "bd show")
    jq -c --arg id "$3" '[.[] | select(.id == $id)]' "$STORE"; exit 0 ;;
  "bd close")
    printf 'close %s %s\n' "$3" "${5:-}" >> "$GC_LOG"
    jq -c --arg id "$3" 'map(if .id == $id then .status = "closed" else . end)' "$STORE" > "$STORE.new" && mv "$STORE.new" "$STORE"
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gc"
export STORE="$TMP/store.json" GC_LOG="$TMP/gc.log"

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
# hand-off ho-1, whose one blocker has closed, and the landing bead land-1,
# which records the branch and main as its target. The edit changes the store.
setup() {
  rm -rf "$ORIGIN" "$SEED" "$RIG" "$TMP/tmpd"
  mkdir -p "$TMP/tmpd"
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
    -e "s#{{ .RigRoot }}#$RIG#g" > "$TMP/block.sh"
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

  # Both sides change one line: a conflict pushes nothing.
  setup; commit_on main shared.txt "main's line"; commit_on integration/land-1 shared.txt "the effort's line"
  OWN=$(head_of integration/land-1)
  run "$sh"
  [ "$RC" -ne 0 ] && ok "[$sh] conflict: the block exits non-zero" || bad "[$sh] conflict: the block reported success"
  eq "$(head_of integration/land-1) $(status_of ho-1)" "$OWN open" "[$sh] conflict: the branch is not pushed and the hand-off stays open"
  grep -qF "pushed nothing: merging origin/main into integration/land-1 conflicts in shared.txt" "$TMP/err" \
    && ok "[$sh] conflict: it says it pushed nothing, and names the file" || bad "[$sh] conflict: it does not say it pushed nothing, naming the file"
  untouched && ok "[$sh] conflict: the rig's checkout is untouched" || bad "[$sh] conflict: the rig's checkout changed, or a worktree or file was left"

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
