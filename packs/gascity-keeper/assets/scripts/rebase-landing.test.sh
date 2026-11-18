#!/usr/bin/env bash
# Hermetic test for rebase-landing.sh, which asks the operator to land a
# finished gascity rebase and checks what their push did once they answer.
#
# The gate's message is the only place the operator reads the push, so the
# suite runs the range-diff, the push and the stand-down exactly as the message
# writes them, against real repositories it builds under a directory whose name
# holds a space, and then lets finish read the result.
# Every outcome of finish is pinned: a landing closes the bead in one write and
# moves the rig checkout only when that discards nothing, an unrun push asks
# again, and a main that moved goes back to the keeper without a close. A
# refused read or write writes nothing after it and exits 1.
#
# The script runs from a copy laid out as the pack lays it out, beside stubs of
# the gc-toolkit scripts it calls (rig-root.sh, human-gate.sh, await-ruling.sh)
# and the real bd-lib.sh, under a stub gc that serves the bead and logs each
# call. No live city, store or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_SRC="$(cd "$HERE/../../../../assets/scripts" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk rebase-landing-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"

PASS=0; FAIL=0
# shellcheck source=../../../../assets/scripts/test-harness.sh
. "$KIT_SRC/test-harness.sh"   # ok, bad, eq, has and hasnt

# Git reads no config but its own, and signs nothing.
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# --- the pack's layout -------------------------------------------------------
KIT="$TMP/kit/assets/scripts"
SCRIPT="$TMP/kit/packs/gascity-keeper/assets/scripts/rebase-landing.sh"
mkdir -p "$KIT" "$(dirname "$SCRIPT")" "$TMP/bin" "$TMP/state"
cp "$HERE/rebase-landing.sh" "$SCRIPT"
cp "$KIT_SRC/bd-lib.sh" "$KIT/bd-lib.sh"
STATE="$TMP/state"; LOG="$TMP/calls.log"
export STATE LOG

# The stub gc logs every call on one line, serves the bead and the convoy from
# the state directory, and refuses an update of a bead named in update_fail.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" | tr '\n' ' ' >> "$LOG"; echo >> "$LOG"
case "$1 $2" in
  "convoy status") cat "$STATE/convoy.json" ;;
  "bd show") cat "$STATE/show.json" ;;
  "bd update") grep -qx "$3" "$STATE/update_fail" 2>/dev/null && exit 1 ;;
esac
exit 0
GC
cat > "$KIT/rig-root.sh" <<'SH'
#!/usr/bin/env bash
[ "$*" = "--rig gascity" ] || { echo "rig-root stub: unexpected $*" >&2; exit 2; }
[ -n "${STUB_RIG:-}" ] || exit 1
printf '%s\n' "$STUB_RIG"
SH
cat > "$KIT/human-gate.sh" <<'SH'
#!/usr/bin/env bash
printf 'human-gate %s\n' "$*" | tr '\n' ' ' >> "$LOG"; echo >> "$LOG"
while [ $# -gt 0 ]; do
  case "$1" in --message) printf '%s' "$2" > "$STATE/gate-message"; shift 2 ;; *) shift ;; esac
done
[ -f "$STATE/gate_fail" ] && exit 1
echo "human-gate: filed gate gc-gate1" >&2
echo "gc-gate1"
SH
cat > "$KIT/await-ruling.sh" <<'SH'
#!/usr/bin/env bash
printf 'await-ruling %s\n' "$*" >> "$LOG"
[ -f "$STATE/await_fail" ] && exit 1
exit 0
SH
cat > "$KIT/stand-down.sh" <<'SH'
#!/usr/bin/env bash
printf 'stand-down %s\n' "$*" >> "$LOG"
SH
chmod +x "$TMP/bin/gc" "$KIT/rig-root.sh" "$KIT/human-gate.sh" "$KIT/await-ruling.sh" "$KIT/stand-down.sh" "$SCRIPT"
PATH="$TMP/bin:$PATH"

KEEPER="gascity/gascity-keeper.keeper"
BRANCH="rebase/gc-iss"

# repos — origin, a clone that is the rig checkout on main at the pre-rebase tip
# PRE, the new upstream tip ONTO, and the rebased branch at NEW, which the
# rebase run pushed. PRE and NEW both descend from the old upstream commit.
repos() {
  rm -rf "$TMP/origin.git" "$TMP/rig" "$TMP/other"
  git init -q --bare "$TMP/origin.git"
  git -C "$TMP/origin.git" symbolic-ref HEAD refs/heads/main
  git init -q "$TMP/rig"
  git -C "$TMP/rig" symbolic-ref HEAD refs/heads/main
  git -C "$TMP/rig" remote add origin "$TMP/origin.git"
  ( cd "$TMP/rig" || exit 1
    echo base > base.txt && git add base.txt && git commit -q -m "old upstream"
    git branch upstream
    echo fork > fork.txt && git add fork.txt && git commit -q -m "fork commit"
    git checkout -q upstream
    echo up > up.txt && git add up.txt && git commit -q -m "new upstream"
    git checkout -q -b "$BRANCH"
    echo fork > fork.txt && git add fork.txt && git commit -q -m "fork commit, rebased"
    git checkout -q main
    git push -q origin main "$BRANCH"
  ) || { echo "could not build the repositories" >&2; exit 1; }
  PRE=$(git -C "$TMP/rig" rev-parse main)
  ONTO=$(git -C "$TMP/rig" rev-parse upstream)
  NEW=$(git -C "$TMP/rig" rev-parse "$BRANCH")
  export STUB_RIG="$TMP/rig"
}

# bead <status> [<key=value>...] — the rebase bead the stub serves, with the
# facts a finished rebase run leaves on it unless a key overrides one, and
# `<key>=` drops it.
bead() {
  local status=$1; shift
  jq -n --arg st "$status" --arg pre "$PRE" --arg onto "$ONTO" --arg br "$BRANCH" --arg k "$KEEPER" '
    {branch: $br, target: "main", pre_rebase_tip: $pre, rebase_onto_sha: $onto,
     backup_ref: "refs/backups/main-pre-rebase-x", requesting_keeper: $k}
    + ($ARGS.positional | map(capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}) | add // {})
    | with_entries(select(.value != ""))
    | [{id: "gc-iss", status: $st, metadata: .}]' --args "$@" > "$STATE/show.json"
}

reset_case() {
  : > "$LOG"
  rm -f "$STATE/update_fail" "$STATE/gate_fail" "$STATE/await_fail" "$STATE/gate-message"
  printf '{"children":[{"id":"gc-iss"}]}' > "$STATE/convoy.json"
}

run() { OUT=$("$SCRIPT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
calls() { grep -E "^$1" "$LOG" || true; }
operator_push() { git -C "$TMP/rig" push -q --force-with-lease="main:$PRE" origin "$BRANCH:main"; }

# --- ask ---------------------------------------------------------------------
echo "── ask: the gate the operator lands the rebase from ──"
repos; reset_case; bead open
run ask --convoy gc-convoy1
eq "$RC" 0 "(ask) exits 0 once the gate asks and the arm landed"
has "$(calls 'convoy status')" "convoy status gc-convoy1 --json" "(ask) the bead is the one the input convoy tracks"
has "$(calls human-gate)" "human-gate --subject gc-iss --key rebase-landing --message Land gascity rebase gc-iss: review its range-diff, then force-push $BRANCH onto main" \
  "(ask) one gate on the bead under rebase-landing, its first line the title"
MSG=$(cat "$STATE/gate-message")
has "$MSG" "  git -C $(printf %q "$TMP/rig") range-diff $ONTO $PRE $BRANCH" "(ask) the review is a range-diff of the fork's commits against their rebased forms, by full sha"
has "$MSG" "  git -C $(printf %q "$TMP/rig") push --force-with-lease=main:$PRE origin $BRANCH:main" "(ask) the push's lease is pinned to the pre-rebase tip, by full sha"
has "$MSG" "A refused push means main moved after the rebase. Clear this gate anyway" "(ask) the message says what a refused push means and what follows"
has "$MSG" "$(printf %q "$KIT/stand-down.sh") gc-iss --key rebase-landing --ruling" "(ask) the message names the stand-down for a rebase the operator drops"
hasnt "$MSG" "Asked again" "(ask) a first ask says nothing of an earlier gate"
has "$(calls 'bd update gc-gate1')" "bd update gc-gate1 --assignee human" "(ask) the gate is assigned to the operator, whose push it is"
has "$(calls await-ruling)" "await-ruling gc-iss --key rebase-landing --formula mol-upstream-gc-rebase-finish" "(ask) the bead is armed to run the landing check once the gate clears"
has "$OUT" "gc-iss waits on gate gc-gate1" "(ask) the summary names the gate"
hasnt "$(calls 'bd update gc-iss')" "bd update" "(ask) the bead itself is not written"

# The commands run as the message writes them.
RANGE=$(printf '%s\n' "$MSG" | sed -n 's/^  \(git -C .* range-diff .*\)$/\1/p')
PUSH=$(printf '%s\n' "$MSG" | sed -n 's/^  \(git -C .* push .*\)$/\1/p')
DROP=$(printf '%s\n' "$MSG" | sed -n "s/^To drop the rebase instead, .*: run \(.* --ruling '<why>'\)\.\$/\1/p")
if eval "$DROP" 2>"$TMP/drop.err"; then
  eq "$(calls stand-down)" "stand-down gc-iss --key rebase-landing --ruling <why>" "(ask) the stand-down runs as written"
else
  bad "(ask) the stand-down runs as written: $(cat "$TMP/drop.err")"
fi
if eval "$RANGE" >"$TMP/range.out" 2>&1 && grep -q 'fork commit' "$TMP/range.out"; then
  ok "(ask) the range-diff runs as written and shows the fork commit"
else
  bad "(ask) the range-diff runs as written: $(cat "$TMP/range.out")"
fi
git clone -q "$TMP/origin.git" "$TMP/other"
( cd "$TMP/other" && echo late > late.txt && git add late.txt && git commit -q -m late && git push -q origin main )
if eval "$PUSH" >/dev/null 2>&1; then
  bad "(ask) the push is refused once main moved after the rebase"
else
  ok "(ask) the push is refused once main moved after the rebase"
fi
git -C "$TMP/other" push -q --force origin "$PRE:main"
if eval "$PUSH" >/dev/null 2>&1 && [ "$(git --git-dir="$TMP/origin.git" rev-parse main)" = "$NEW" ]; then
  ok "(ask) the push lands the rebased tip on a main still at the pre-rebase tip"
else
  bad "(ask) the push lands the rebased tip on a main still at the pre-rebase tip"
fi

echo "── ask: the lease is a sha even when pre_rebase_tip names a ref ──"
repos; reset_case
git -C "$TMP/rig" update-ref refs/backups/main-pre-rebase-x "$PRE"
bead open pre_rebase_tip=refs/backups/main-pre-rebase-x
run ask --bead gc-iss
eq "$RC" 0 "(ask-ref) exits 0"
has "$(cat "$STATE/gate-message")" "--force-with-lease=main:$PRE origin" "(ask-ref) the ref resolves to its sha in the lease"

echo "── ask: what it refuses ──"
repos; reset_case; bead open rebase_onto_sha=
run ask --bead gc-iss
eq "$RC" 1 "(ask-facts) a bead with no rebase_onto_sha exits 1"
has "$ERR" "rebase_onto_sha" "(ask-facts) …and names the missing fact"
eq "$(calls human-gate)" "" "(ask-facts) …and files no gate"

repos; reset_case; bead open branch=rebase/gc-gone
run ask --bead gc-iss
eq "$RC" 1 "(ask-branch) a branch the rig checkout lacks exits 1"
eq "$(calls human-gate)" "" "(ask-branch) …and files no gate that names a push that cannot run"

repos; reset_case; bead open; touch "$STATE/gate_fail"
run ask --bead gc-iss
eq "$RC" 1 "(ask-gate) a gate that was not filed exits 1"
eq "$(calls 'bd update gc-gate1')$(calls await-ruling)" "" "(ask-gate) …and assigns and arms nothing"

repos; reset_case; bead open; echo gc-gate1 > "$STATE/update_fail"
run ask --bead gc-iss
eq "$RC" 1 "(ask-assign) an assignment the store refused exits 1"
eq "$(calls await-ruling)" "" "(ask-assign) …and arms nothing"

repos; reset_case; bead open; touch "$STATE/await_fail"
run ask --bead gc-iss
eq "$RC" 1 "(ask-arm) an arm that did not land exits 1"

repos; reset_case; bead open; STUB_RIG=""
run ask --bead gc-iss
eq "$RC" 1 "(ask-rig) no gascity rig in the roster exits 1"
eq "$(calls human-gate)" "" "(ask-rig) …and files no gate"

# --- finish: landed ----------------------------------------------------------
echo "── finish: the push landed ──"
repos; reset_case; bead open; operator_push
run finish --convoy gc-convoy1
eq "$RC" 0 "(landed) exits 0"
UPD=$(calls 'bd update gc-iss')
eq "$(printf '%s\n' "$UPD" | grep -c .)" 1 "(landed) the record and the close are one write"
has "$UPD" "--set-metadata gc.work_outcome=shipped --set-metadata gc.work_commit=$NEW --set-metadata gc.work_branch=main --set-metadata rig_update_result=reset: ${PRE:0:12} -> ${NEW:0:12} (worktree prune ran) --status=closed" \
  "(landed) Gas City's work record of the landing and the rig's sync are recorded as the bead closes"
has "$UPD" "Landed (" "(landed) …with a note of what landed"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$NEW" "(landed) the rig checkout, clean on main at the pre-rebase tip, is reset to the new main"
MAIL=$(calls 'mail send')
has "$MAIL" "mail send $KEEPER -s gascity rebase gc-iss landed" "(landed) the keeper is told"
has "$MAIL" "Rig checkout: reset:" "(landed) …with what the rig checkout did"
hasnt "$MAIL" "--notify" "(landed) …without asking for its turn"
eq "$(calls human-gate)$(calls await-ruling)" "" "(landed) nothing is asked again"

echo "── finish: the rig checkout follows only when that discards nothing ──"
repos; reset_case; bead open; operator_push; echo wip > "$TMP/rig/wip.txt"
run finish --bead gc-iss
eq "$RC" 0 "(dirty) exits 0"
has "$(calls 'bd update gc-iss')" "rig_update_result=skipped: branch=main dirty=1 (operator must sync) --status=closed" "(dirty) an untracked file leaves the checkout alone, said why, and still closes"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(dirty) …and HEAD stays put"

# An invalid status.showUntrackedFiles fails git status with no output, and
# leaves rev-parse and checkout working.
repos; reset_case; bead open; operator_push; echo wip > "$TMP/rig/fork.txt"
git -C "$TMP/rig" config status.showUntrackedFiles bogus
run finish --bead gc-iss
eq "$RC" 0 "(unreadable) exits 0"
has "$(calls 'bd update gc-iss')" "rig_update_result=error: git status failed in $TMP/rig (operator must sync) --status=closed" "(unreadable) a status git cannot read leaves the checkout alone, said why, and still closes"
eq "$(cat "$TMP/rig/fork.txt")" wip "(unreadable) …and keeps the tracked edit"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(unreadable) …and HEAD stays put"

# git status lists neither an ignored file nor, under
# status.showUntrackedFiles=no, an untracked one, and the landed tree adds
# up.txt.
repos; reset_case; bead open; operator_push
echo up.txt >> "$TMP/rig/.git/info/exclude"; echo operator-ignored > "$TMP/rig/up.txt"
run finish --bead gc-iss
eq "$RC" 0 "(ignored) exits 0"
UPD=$(calls 'bd update gc-iss')
has "$UPD" "rig_update_result=skipped: git checkout of origin/main refused in $TMP/rig: " "(ignored) an ignored file where the landed tree puts one leaves the checkout alone…"
has "$UPD" "up.txt (operator must sync) --status=closed" "(ignored) …names the file git named, and still closes"
eq "$(cat "$TMP/rig/up.txt")" operator-ignored "(ignored) …and keeps the file"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(ignored) …and HEAD stays put"

repos; reset_case; bead open; operator_push
git -C "$TMP/rig" config status.showUntrackedFiles no; echo operator-work > "$TMP/rig/up.txt"
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=skipped: git checkout of origin/main refused in $TMP/rig: " "(hidden-untracked) an untracked file git status hides leaves the checkout alone"
eq "$(cat "$TMP/rig/up.txt")" operator-work "(hidden-untracked) …and keeps the file"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(hidden-untracked) …and HEAD stays put"

repos; reset_case; bead open; operator_push
echo build.out >> "$TMP/rig/.git/info/exclude"; echo artifact > "$TMP/rig/build.out"
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=reset: ${PRE:0:12} -> ${NEW:0:12} (worktree prune ran)" "(ignored-aside) an ignored file the landed tree does not write leaves the move to go ahead…"
eq "$(cat "$TMP/rig/build.out")" artifact "(ignored-aside) …and is kept"

repos; reset_case; bead open; operator_push
printf '#!/bin/sh\necho ran > hook-ran\nexit 1\n' > "$TMP/rig/.git/hooks/post-checkout"; chmod +x "$TMP/rig/.git/hooks/post-checkout"
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=reset: ${PRE:0:12} -> ${NEW:0:12} (worktree prune ran)" "(hooks) a failing post-checkout hook does not make the move read as refused…"
if [ -e "$TMP/rig/hook-ran" ]; then bad "(hooks) …because the move runs no hook"; else ok "(hooks) …because the move runs no hook"; fi

repos; reset_case; bead open; operator_push; git -C "$TMP/rig" checkout -q -b feature
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=skipped: branch=feature dirty=0 (operator must sync)" "(branch) a checkout on another branch is left alone"

repos; reset_case; bead open; operator_push
( cd "$TMP/rig" && echo local > local.txt && git add local.txt && git commit -q -m "unpushed" )
LOCAL=$(git -C "$TMP/rig" rev-parse HEAD)
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=skipped: HEAD=${LOCAL:0:12} does not match pre_rebase_tip=${PRE:0:12} (operator must sync)" "(local-commit) a main with a commit of its own is left alone"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$LOCAL" "(local-commit) …and keeps that commit"

repos; reset_case; bead open; operator_push; git -C "$TMP/rig" reset -q --hard "$NEW"
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "rig_update_result=current: already at ${NEW:0:12} --status=closed" "(current) a checkout already at the new main needs nothing"

repos; reset_case; bead open; operator_push; echo gc-iss > "$STATE/update_fail"
run finish --bead gc-iss
eq "$RC" 1 "(refused-close) a landing record the store refused exits 1"
eq "$(calls 'mail send')" "" "(refused-close) …and tells no one it closed"

# --- finish: not pushed ------------------------------------------------------
echo "── finish: the push has not run ──"
repos; reset_case; bead open
run finish --bead gc-iss
eq "$RC" 0 "(unpushed) exits 0"
has "$(calls human-gate)" "human-gate --subject gc-iss --key rebase-landing" "(unpushed) the operator is asked again"
has "$(sed -n 2p "$STATE/gate-message")" "Asked again: when the last landing gate cleared, origin/main was still at the pre-rebase tip" "(unpushed) …in a gate that says why"
has "$(calls await-ruling)" "await-ruling gc-iss --key rebase-landing --formula mol-upstream-gc-rebase-finish" "(unpushed) …and armed again"
eq "$(calls 'bd update gc-iss')" "" "(unpushed) the bead is neither closed nor handed back"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(unpushed) the rig checkout is untouched"

# --- finish: main moved ------------------------------------------------------
echo "── finish: main moved after the rebase ──"
repos; reset_case; bead open
git clone -q "$TMP/origin.git" "$TMP/other"
( cd "$TMP/other" && echo late > late.txt && git add late.txt && git commit -q -m late && git push -q origin main )
MOVED=$(git --git-dir="$TMP/origin.git" rev-parse main)
run finish --bead gc-iss
eq "$RC" 0 "(race) exits 0"
UPD=$(calls 'bd update gc-iss')
has "$UPD" "bd update gc-iss --status=open --assignee=$KEEPER --set-metadata aborted_at=race-loss --append-notes Not landed (" "(race) the bead goes back to the keeper that requested the rebase"
has "$UPD" "origin/main was $MOVED, which is neither the tip of $BRANCH ($NEW) nor the pre-rebase tip ($PRE)" "(race) …its notes naming the three commits"
hasnt "$UPD" "gc.work_outcome" "(race) …with no landing recorded"
hasnt "$UPD" "status=closed" "(race) …and not closed"
has "$(calls 'mail send')" "mail send $KEEPER --notify -s gascity rebase gc-iss: main moved before it landed" "(race) the keeper is mailed and given its turn"
eq "$(calls human-gate)" "" "(race) no gate is filed"
eq "$(git -C "$TMP/rig" rev-parse HEAD)" "$PRE" "(race) the rig checkout is untouched"

repos; reset_case; bead open requesting_keeper=
git clone -q "$TMP/origin.git" "$TMP/other"
( cd "$TMP/other" && echo late > late.txt && git add late.txt && git commit -q -m late && git push -q origin main )
run finish --bead gc-iss
has "$(calls 'bd update gc-iss')" "--assignee=gascity/gascity-keeper.keeper" "(race-nokeeper) a bead that names no keeper goes to the rig's own"

# --- finish: what it refuses -------------------------------------------------
echo "── finish: what it refuses ──"
repos; reset_case; bead closed
run finish --bead gc-iss
eq "$RC" 0 "(closed) a closed bead exits 0"
eq "$(calls 'bd update')$(calls 'mail send')" "" "(closed) …and writes nothing"

repos; reset_case; bead in_progress; operator_push
run finish --bead gc-iss
eq "$RC" 1 "(held) a bead something holds exits 1"
eq "$(calls 'bd update')" "" "(held) …and writes nothing"

repos; reset_case; bead open pre_rebase_tip=; operator_push
run finish --bead gc-iss
eq "$RC" 1 "(facts) a bead with no pre_rebase_tip exits 1"
has "$ERR" "pre_rebase_tip" "(facts) …and names the missing fact"
eq "$(calls 'bd update')" "" "(facts) …and writes nothing"

repos; reset_case; bead open; operator_push; rm -rf "$TMP/origin.git"
run finish --bead gc-iss
eq "$RC" 1 "(fetch) a fetch that failed exits 1"
eq "$(calls 'bd update')$(calls 'mail send')" "" "(fetch) …and writes nothing"

repos; reset_case; bead open; printf '{"children":[{"id":"gc-iss"},{"id":"gc-two"}]}' > "$STATE/convoy.json"
run finish --convoy gc-convoy1
eq "$RC" 1 "(convoy) a convoy that tracks two beads exits 1"

run finish
eq "$RC" 2 "(usage) no bead exits 2"
run finish --bead 'gc-iss;rm'
eq "$RC" 2 "(usage) an id outside [A-Za-z0-9._-] exits 2"
run land --bead gc-iss
eq "$RC" 2 "(usage) an unknown verb exits 2"

echo
echo "rebase-landing: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
