#!/usr/bin/env bash
# Tests for review-run.sh against real git repositories, a bare origin among
# them, with gc, gctk, gh and the scripts it calls beside it stubbed. The gctk
# stub answers `review step` from a fixture each case sets, and every stub logs
# the calls it gets.
#
# Covers triage's read cancelling a run that must stop with no result, a run
# that does not read as one included, cancelling nothing for a step that is not
# triage's or whose ref does not read, stopping with nothing made when its check
# of the run does not answer, and making the run's workspace private to its
# user; a verb the held step does not own refused; output writing what
# gctk printed as the step's gc.output_json, from the step's own file, and
# writing nothing for an output gctk refuses, a shadow round handing gctk its
# writes; triage's withdrawal; the push returning the PR to draft before it
# pushes, with a lease on the head the round judged, pushing nothing when the
# draft does not answer or the branch moved, weighing a failed push by the
# branch on origin (landed, unmoved and to run again, moved, or not read), and
# nothing in a shadow run; the
# post of the head's comment, or the edit of the one its mark finds, nothing
# when there is nothing to answer, and nothing in a shadow run; a deferred fix
# filed with its wait on the PR's bead in its create, and armed, found rather
# than filed again, armed then when the call that filed it did not arm it, and
# left as it stands when it is armed, closed or routed; a
# question put to a gate; a person's batch, whose human findings the round's
# read lists and the finding verb rules through finding.sh, a deferral's
# follow-up taking the PR's target; triage's read at a head that already
# passed, its read of the check index naming the scripts directory beside it
# for any binding, its read of the rig's guidance for triage at the head, and
# stopping when that does not read; the repair's read again keeping the round's
# commit and uncommitted edit and showing them, and stopping the run on a
# worktree that is not at the head or past it; and the reads making each step's
# worktree in its own part of the workspace, and stopping when it does not land.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only
PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-run-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
unset "${!GC_@}" "${!BEADS_@}" GCTK_SCRIPTS_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# The scripts directory: the script under test and review-workspace.sh with the
# lib it sources, and a stub for every other script it calls, each logging.
SD="$TMP/scripts"; mkdir -p "$SD"
cp "$HERE/review-run.sh" "$HERE/review-workspace.sh" "$HERE/gctk-resolve.sh" "$SD/"
LOG="$TMP/calls.log"; export LOG
for s in decline.sh human-gate.sh pr-post.sh demo-deliver.sh review-evidence.sh finding.sh; do
    { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SD/$s" <<'STUB'
printf '%s %s\n' "${0##*/}" "$*" >> "$LOG"
case "${0##*/}" in
    human-gate.sh) echo "tk-gate1" ;;
    pr-post.sh) [ "$1" = comment ] && echo "https://github.com/o/r/pull/7#issuecomment-9" ;;
    finding.sh) exit "${STUB_RC_FINDING:-0}" ;;
esac
exit "${STUB_RC_SIBLING:-0}"
STUB
done
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; echo 'echo "$STUB_RIG"'; } > "$SD/rig-root.sh"
chmod +x "$SD"/*.sh

# The rig: a bare origin holding main and the PR's branch at HEAD1, and a clone.
git init -q --bare "$TMP/origin.git"
git init -q "$TMP/seed"
gs() { git -C "$TMP/seed" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
echo a > "$TMP/seed/f"; gs add f; gs commit -q -m base; gs branch -M main
gs checkout -q -b polecat/tk-pr; echo b > "$TMP/seed/f"; gs commit -q -am head1
HEAD1="$(gs rev-parse HEAD)"
gs remote add origin "$TMP/origin.git"; gs push -q origin main polecat/tk-pr
git clone -q "$TMP/origin.git" "$TMP/rig"
export STUB_RIG="$TMP/rig"

# The stubs on PATH: gc, gctk and gh.
BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_FACTS="$TMP/facts.json" STUB_GCTK_OUT="$TMP/gctk.out"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gc" <<'STUB'
printf 'gc %s\n' "$*" >> "$LOG"
case "$1 $2" in
    "hook current") echo "${STUB_HELD:-tk-step}" ;;
    "bd update") exit "${STUB_RC_BD_UPDATE:-0}" ;;
    "bd show") [ -z "${STUB_RC_BD_SHOW:-}" ] || exit "$STUB_RC_BD_SHOW"
               if [ -n "${STUB_NO_POOL:-}" ]; then printf '[{"id":"%s","metadata":{}}]\n' "$3"
               else printf '[{"id":"%s","metadata":{"gc.var.repair_target":"rig/gc-toolkit.polecat","finding.follow_up":"tk-fu","gc.step_ref":"%s"}}]\n' "$3" "${STUB_STEP_REF:-}"; fi ;;
    "bd list") [ -z "${STUB_RC_BD_LIST:-}" ] || exit "$STUB_RC_BD_LIST"
               printf '%s\n' "${STUB_LIST:-[]}" ;;
    "bd create") echo '{"id":"tk-new"}' ;;
    "bd dep") ;;
esac
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gctk" <<'STUB'
printf 'gctk %s\n' "$*" >> "$LOG"
[ "$1 $2" != "review checks" ] || printf 'gctk-scripts-dir %s\n' "${GCTK_SCRIPTS_DIR:-unset}" >> "$LOG"
case "$1 $2" in
    "review step")
        case " $* " in *" --stands "*)
            [ -z "${STUB_STANDS_OUT:-}" ] || { echo "gctk review step: $STUB_STANDS_OUT" >&2; exit 3; }
            [ -z "${STUB_STANDS_RC:-}" ] || { echo "gctk review step: GitHub did not answer for https://github.com/o/r/pull/7" >&2; exit "$STUB_STANDS_RC"; } ;;
        esac
        cat "$STUB_FACTS" ;;
    "review output") [ -z "${STUB_REFUSE:-}" ] || { echo "gctk review output: $STUB_REFUSE; write it again" >&2; exit 3; }
        echo '{"review":"x","iteration":1}' ;;
    "review comment") [ -f "$STUB_GCTK_OUT" ] && cat "$STUB_GCTK_OUT" ;;
    "review guidance") [ -z "${STUB_RC_GUIDANCE:-}" ] || { echo "gctk review guidance: docs/review-$3.md would not read" >&2; exit "$STUB_RC_GUIDANCE"; }
        printf 'the rig guidance for %s, read in %s\n' "$3" "$PWD" ;;
    "pr draft") [ -z "${STUB_ORIGIN:-}" ] || git -C "$STUB_ORIGIN" rev-parse polecat/tk-pr > "$STUB_ORIGIN.at-draft"
        exit "${STUB_RC_DRAFT:-0}" ;;
    "bead holds") if [ -n "${STUB_HOLDS:-}" ]; then printf '%s\n' "$STUB_HOLDS"
                  else printf '{"id":"%s","status":"blocked","arm":null}\n' "$3"; fi ;;
    "bead arm") exit "${STUB_RC_ARM:-0}" ;;
esac
exit 0
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gh" <<'STUB'
printf 'gh %s\n' "$*" >> "$LOG"
[ "$1" = api ] && printf '%s' "${STUB_COMMENT_ID:-}"
exit 0
STUB
chmod +x "$BIN"/*
export PATH="$BIN:$PATH" GCTK_BIN="$BIN/gctk" REVIEW_WORKSPACE_DIR="$TMP/ws"
mkdir -p "$REVIEW_WORKSPACE_DIR"
WS="$TMP/ws/gc-review-tk-run"

# facts <ref> <output> <iteration> [shadow] [<change from> <why>] — the held
# step's facts, the change the whole PR unless a base and its rule are given.
facts() {
    jq -n --arg ref "$1" --arg out "$2" --argjson n "$3" --argjson shadow "${4:-false}" --arg h "$HEAD1" \
        --arg from "${5:-}" --arg why "${6:-the whole PR}" \
        '{step: "tk-step", ref: $ref, output: $out, iteration: $n, run: "tk-run", pr_bead: "tk-pr",
          pr: "https://github.com/o/r/pull/7", branch: "polecat/tk-pr", target: "main", first_head: $h,
          head: $h, shadow: $shadow,
          change: ({head: $h, why: $why} + (if $from == "" then {} else {from: $from} end))}' > "$STUB_FACTS"
}
run() { : > "$LOG"; OUT=$(bash "$SD/review-run.sh" "$@" 2>&1); RC=$?; }
called() { grep -c -- "$1" "$LOG"; }

# --- triage's read: whether the run stands ------------------------------------
facts review-loop.iteration.1.triage triage 1
export STUB_STEP_REF=review-loop.iteration.1.triage
STUB_STANDS_OUT="run tk-run must stop with no result: the PR's head is abc, no longer the run's head" run triage
eq "$RC" 3 "triage's read refuses a run that must stop"
has "$(cat "$LOG")" "decline.sh --step review-loop --reason run tk-run must stop with no result: the PR's head is abc" \
    "and cancels it with no result, saying why"
if [ -e "$WS" ]; then bad "and makes no workspace"; else ok "and makes no workspace"; fi
STUB_STANDS_OUT="tk-step is not a review run: its root tk-run names no pr_bead var" run triage
eq "$RC" 3 "triage's read refuses a run poured with no record to name"
has "$(cat "$LOG")" "decline.sh --step review-loop --reason tk-step is not a review run: its root tk-run names no pr_bead var" \
    "and cancels it the same way"
STUB_STANDS_RC=2 run triage
eq "$RC" 2 "triage's read stops, exit 2, when its check of the run does not answer"
has "$OUT" "GitHub did not answer" "and says which read did not answer"
eq "$(called decline.sh)" 0 "and cancels nothing, since a retry may find the run stands"
hasnt "$OUT" "The run's workspace" "and does not go on as if the run stood"
STUB_STEP_REF=mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane STUB_STANDS_OUT="x" run triage
eq "$RC/$(called decline.sh)" "3/0" "a step that is not triage's cancels nothing"
STUB_RC_BD_SHOW=1 STUB_STANDS_OUT="x" run triage
eq "$RC/$(called decline.sh)" "2/0" "a step whose ref does not read cancels nothing"
run triage
eq "$RC" 0 "triage's read goes on for a run that stands"
has "$OUT" "The run's workspace: $WS" "and prints the run's workspace"
eq "$(ls -ld "$WS" | cut -c1-10)" "drwx------" "which it makes, private to its user"
unset STUB_STEP_REF

# --- a verb the step does not own -----------------------------------------------
facts review-loop.iteration.1.triage triage 1
run push
eq "$RC" 3 "triage cannot push"
eq "$(called 'pr draft')" 0 "and nothing is drafted"
run lane --check arch
eq "$RC" 3 "triage cannot run a lane's read"

# --- output ----------------------------------------------------------------------
mkdir -p "$WS/triage"; echo '{"review":"triage"}' > "$WS/triage/output.json"
run output
eq "$RC" 0 "output writes a triage output that stands"
has "$(cat "$LOG")" "gctk review output tk-step --file $WS/triage/output.json" "from triage's own file"
has "$(cat "$LOG")" 'gc bd update tk-step --set-metadata gc.output_json={"review":"x","iteration":1}' \
    "as the step's gc.output_json, as gctk printed it"
STUB_REFUSE="iteration 1 judges x" run output
eq "$RC" 3 "an output gctk refuses exits 3"
eq "$(called 'bd update')" 0 "and nothing is written"
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1
run output
eq "$RC" 64 "a lane's output names its check"
mkdir -p "$WS/lane-arch"; echo '{"review":"lane"}' > "$WS/lane-arch/output.json"
run output --check arch
eq "$RC" 0 "a lane writes its output from its own part"
facts review-loop.iteration.1.rule-and-repair repair 1 true
mkdir -p "$WS/repair"; echo '{"review":"repair"}' > "$WS/repair/output.json"
run output
has "$(cat "$LOG")" "--writes $WS/repair/shadow-writes.txt" "a shadow round hands gctk its writes"

# --- withdraw --------------------------------------------------------------------
facts review-loop.iteration.1.triage triage 1
run withdraw --reason "it changes what the PR does"
eq "$RC" 0 "triage withdraws"
has "$(cat "$LOG")" "gctk pr withdraw tk-pr --head $HEAD1 --reason it changes what the PR does" "at the head it judged"
facts review-loop.iteration.1.triage triage 1 true
run withdraw --reason r
eq "$(called 'pr withdraw')" 0 "a shadow run withdraws nothing"
has "$OUT" "shadow run: wrote nothing" "and says what it would have done"

# --- push ------------------------------------------------------------------------
facts review-loop.iteration.1.rule-and-repair repair 1
run repair
eq "$RC" 0 "repair makes the run's worktree"
WT="$WS/repair/wt"
eq "$(git -C "$WT" rev-parse HEAD)" "$HEAD1" "at the head the round judged"
run push
eq "$RC" 0 "a worktree at the head pushes nothing"
eq "$(called 'pr draft')" 0 "and drafts nothing"
gw() { git -C "$WT" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "$@"; }
echo fix > "$WT/f"; gw commit -q -am fix; FIX="$(gw rev-parse HEAD)"
STUB_RC_DRAFT=2 run push
eq "$RC" 2 "a draft that does not answer pushes nothing"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)" "$HEAD1" "and the branch stays at the head"
STUB_ORIGIN="$TMP/origin.git" run push
eq "$RC" 0 "the repair's commits push"
eq "$(cat "$TMP/origin.git.at-draft")" "$HEAD1" "after the PR returned to draft, while the branch was still at the head"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)" "$FIX" "onto the PR's branch"
has "$OUT" "$FIX" "and prints the head it pushed"
# The branch moved past the head the round judged: the lease refuses.
facts review-loop.iteration.2.rule-and-repair repair 2
gw reset -q --hard "$HEAD1"; echo other > "$WT/f"; gw commit -q -am other
run push
eq "$RC" 1 "a push onto a branch that moved from the judged head does not land"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)" "$FIX" "and the branch keeps what is there"
has "$OUT" "moved from $HEAD1, the head the round judged, to $FIX" "and it names where the branch moved"
# A push that fails is weighed by the branch on origin: commits an earlier call
# landed read as pushed, a refusal that left the branch at the judged head runs
# again, and so does an origin that does not answer.
facts review-loop.iteration.1.rule-and-repair repair 1
gw reset -q --hard "$FIX"
run push
eq "$RC" 0 "a push whose commits an earlier call landed reads as pushed"
eq "$(printf '%s\n' "$OUT" | tail -n 1)" "$FIX" "and prints the head on origin"
# Origin takes the commits and still answers with a failure, as a push whose
# connection drops after the update does: the hook moves the branch itself,
# outside the push's quarantine, then refuses.
git -C "$TMP/origin.git" update-ref refs/heads/polecat/tk-pr "$HEAD1"
printf '%s\n' '#!/bin/sh' 'unset GIT_QUARANTINE_PATH GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES' \
    'while read -r old new ref; do git update-ref "$ref" "$new"; done' 'exit 1' > "$TMP/origin.git/hooks/pre-receive"
chmod +x "$TMP/origin.git/hooks/pre-receive"
run push
eq "$RC" 0 "a push that failed after its commits landed reads as pushed"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)/$(printf '%s\n' "$OUT" | tail -n 1)" "$FIX/$FIX" "and prints the head origin holds"
has "$OUT" "so the repair's commits are there" "and says why it reads the failure as a push"
git -C "$TMP/origin.git" update-ref refs/heads/polecat/tk-pr "$HEAD1"
printf '#!/bin/sh\nexit 1\n' > "$TMP/origin.git/hooks/pre-receive"; chmod +x "$TMP/origin.git/hooks/pre-receive"
run push
eq "$RC" 2 "a push origin refused while the branch stayed at the judged head exits 2, to run again"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)" "$HEAD1" "and the branch stays at the head"
has "$OUT" "still at $HEAD1" "and it says the branch did not move"
rm -f "$TMP/origin.git/hooks/pre-receive"
run push
eq "$RC" 0 "run again, the push lands"
eq "$(git -C "$TMP/origin.git" rev-parse polecat/tk-pr)" "$FIX" "onto the PR's branch"
git -C "$TMP/origin.git" update-ref refs/heads/polecat/tk-pr "$HEAD1"
git -C "$TMP/rig" remote set-url origin "$TMP/nowhere.git"
run push
eq "$RC" 2 "a push to an origin that does not answer exits 2, to run again"
git -C "$TMP/rig" remote set-url origin "$TMP/origin.git"
git -C "$TMP/origin.git" update-ref refs/heads/polecat/tk-pr "$FIX"
facts review-loop.iteration.1.rule-and-repair repair 1 true
: > "$WS/repair/shadow-writes.txt"
run push
eq "$(called 'pr draft')" 0 "a shadow run drafts nothing"
has "$(cat "$WS/repair/shadow-writes.txt")" "push: 1 commit(s) onto polecat/tk-pr" "and keeps the push it made none of"

# --- the repair's read keeps the round's work -------------------------------------
# A session that restarts reads the round again at the head it judged: the
# run's worktree keeps the commit the round made and the edit it has not
# committed, and the read shows both. A worktree that is not at that head or
# past it stops the run, and is kept as it stands.
facts review-loop.iteration.1.rule-and-repair repair 1
rm -rf "$WS/repair"
run repair
WT="$WS/repair/wt"
echo kept > "$WT/f"; gw commit -q -am "the round's fix"; KEPT="$(gw rev-parse HEAD)"
echo draft > "$WT/notes.txt"
run repair
eq "$RC" 0 "the repair's read again keeps the run's worktree"
eq "$(git -C "$WT" rev-parse HEAD)" "$KEPT" "with the commit the round made"
if [ -e "$WT/notes.txt" ]; then ok "…and the edit it has not committed"; else bad "…and the edit it has not committed"; fi
has "$OUT" "== The round's work already in the run's worktree, kept as it stands" "and the read shows the session what it kept"
has "$OUT" "the round's fix" "…the commit past the head"
has "$OUT" "?? notes.txt" "…and the uncommitted edit"
gw checkout -q --detach origin/main
run repair
eq "$RC" 3 "a run's worktree that is not at the head or past it stops the repair's read (exit 3)"
has "$OUT" "the run must stop" "and says the run must stop"
eq "$(git -C "$WT" rev-parse HEAD)" "$(git -C "$TMP/rig" rev-parse origin/main)" "and the worktree is kept as it stands"
if [ -e "$WT/notes.txt" ]; then ok "…with its uncommitted edit"; else bad "…with its uncommitted edit"; fi
git -C "$TMP/rig" worktree remove --force --force "$WT" 2>/dev/null; rm -rf "$WS/repair"

# --- post ------------------------------------------------------------------------
facts review-loop.iteration.1.rule-and-repair repair 1
rm -f "$STUB_GCTK_OUT"
run post
eq "$RC" 0 "an iteration with nothing to answer posts nothing"
eq "$(called pr-post.sh)" 0 "…no comment"
printf '%s\n' "<!-- gc:review-run tk-run $HEAD1 -->" "**Review**" > "$STUB_GCTK_OUT"
run post
has "$(cat "$LOG")" "pr-post.sh comment --repo github.com/o/r --pr 7 --body-file $WS/repair/comment-1.md" "the head's comment posts"
STUB_COMMENT_ID=4242 run post
has "$(cat "$LOG")" "pr-post.sh edit --repo github.com/o/r --comment 4242" "a retry edits the comment its mark finds"
facts review-loop.iteration.1.rule-and-repair repair 1 true
run post
eq "$(called pr-post.sh)" 0 "a shadow run posts nothing"
has "$OUT" "**Review**" "and prints the comment its output carries"

# --- defer -----------------------------------------------------------------------
facts review-loop.iteration.1.rule-and-repair repair 1
echo "Move the parser into its own package." > "$TMP/defer.md"
run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$OUT" "0/tk-new" "a fix outside the diff is deferred, printing its bead"
has "$(cat "$LOG")" "gc bd create Move the parser -t task" "to a bead of its own"
has "$(cat "$LOG")" "--deps blocked-by:tk-pr --metadata {\"target\":\"main\"}" "whose create carries its wait on the PR's bead, with the PR's target"
eq "$(called 'bd dep')" 0 "and adds no edge of its own onto the PR's bead, the one edge bd keeps between the two"
has "$(cat "$LOG")" "gctk bead arm tk-new --target rig/gc-toolkit.polecat --on mol-polecat-work" "and armed on the run's repair pool"
STUB_NO_POOL=1 run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$(called 'bd create')" "1/0" "a run that names no repair pool files nothing"
STUB_RC_ARM=1 run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC" 1 "an arm that does not land is run again"
has "$OUT" "tk-new waits on tk-pr and its arm did not land" "saying the fix is filed and waits"
# The bead an earlier call filed: its title, and its wait on the PR's bead.
filed() { # <status> [route]
    printf '[{"id":"tk-old","title":"Move the parser","status":"%s","metadata":{"gc.routed_to":"%s"},"dependencies":[{"issue_id":"tk-old","depends_on_id":"tk-pr","type":"blocks"}]}]' "$1" "${2:-}"
}
STUB_LIST=$(filed open) run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$OUT" "0/tk-old" "a retry after a create whose arm did not land finds the fix filed"
eq "$(called 'bd create')/$(called 'bd dep')" "0/0" "and files nothing again"
has "$(cat "$LOG")" "gctk bead holds tk-old" "and reads whether it is armed"
has "$(cat "$LOG")" "gctk bead arm tk-old --target rig/gc-toolkit.polecat --on mol-polecat-work" "and makes the arm the earlier call did not"
STUB_LIST=$(filed open) STUB_HOLDS='{"id":"tk-old","status":"blocked","arm":{"target":"rig/gc-toolkit.polecat","args":"[\"--on\",\"mol-polecat-work\"]"}}' \
    run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$OUT" "0/tk-old"$'\n'"review-run: tk-old already carries this fix, armed" "a clean re-run finds the fix filed and armed"
eq "$(called 'bd create')/$(called 'bd dep')/$(called 'bead arm')" "0/0/0" "and writes nothing"
STUB_LIST=$(filed closed) run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$(called 'bd create')/$(called 'bead arm')" "0/0/0" "a fix filed and closed since is found, and nothing is written"
has "$OUT" "tk-old already carries this fix, at status closed, so it is not armed" "saying why it is left as it stands"
STUB_LIST=$(filed open rig/gc-toolkit.polecat) run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$(called 'bd create')/$(called 'bead arm')" "0/0/0" "a fix filed and routed since is found, and nothing is written"
STUB_LIST=$(filed open) STUB_HOLDS='{"id":"tk-old","error":"the store did not answer"}' \
    run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$(called 'bead arm')" "2/0" "a found fix whose arm does not read is not armed blind"
STUB_LIST='[{"id":"tk-other","title":"Move the parser","status":"open","dependencies":[{"issue_id":"tk-other","depends_on_id":"tk-pr","type":"discovered-from"}]}]' \
    run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$OUT" "0/tk-new" "a bead of the same title that does not wait on the PR's bead is not taken for the fix"
STUB_RC_BD_LIST=1 run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$RC/$(called 'bd create')" "2/0" "a lookup that does not answer files nothing"

# --- question --------------------------------------------------------------------
run question --key c1-scope --message "Is the cap the operator's to set?"
has "$(cat "$LOG")" "human-gate.sh --subject tk-pr --key review-question-c1-scope --message Is the cap" "a question goes to a gate on the PR's bead"
has "$OUT" "tk-gate1" "and prints the gate"
run question --key "Bad Key" --message m
eq "$RC" 64 "a key that is no slug is a usage error"

# --- a person's batch: each comment a human finding, ruled by its grade ----------
facts review-loop.iteration.1.rule-and-repair repair 1
STUB_LIST='[{"id":"tk-f1","title":"rename the flag","status":"open","metadata":{"task_kind":"finding","finding.lane":"human","finding.fix_unit":"tk-ask"}},{"id":"tk-f9","title":"a lane finding","status":"open","metadata":{"task_kind":"finding","finding.lane":"correctness"}}]' \
    run repair
has "$OUT" "tk-f1 (ask tk-ask, unvalidated): rename the flag" "the round's read lists each human finding the batch's ask carries"
hasnt "$OUT" "tk-f9" "and no other finding"
run finding --finding tk-f1 --ruling declined --reason "A nit, P2 at most: the name reads as well as the one suggested, so it is answered and not fixed."
eq "$RC" 0 "a nit is ruled"
has "$(cat "$LOG")" "finding.sh set-disposition --finding tk-f1 --anchor tk-pr --disposition declined --reason A nit" "as declined on the finding, answered and not fixed"
has "$(cat "$LOG")" "--reply A nit, P2 at most" "with its answer as the reply the comment is owed"
run finding --finding tk-f1 --ruling deferred --reason "The fix reaches the parser, outside this PR's diff."
eq "$RC/$OUT" "0/tk-fu" "a fix outside the diff is deferred, printing its follow-up"
has "$(cat "$LOG")" "--disposition deferred --reason The fix reaches the parser" "through finding.sh"
has "$(cat "$LOG")" "--fix-pool rig/gc-toolkit.polecat" "on the run's repair pool"
has "$(cat "$LOG")" "gc bd update tk-fu --set-metadata target=main" "and its follow-up takes the PR's target"
run finding --finding tk-f1 --ruling must-fix --reason "P1: the flag is read before it is set."
has "$(cat "$LOG")" "--disposition must-fix" "a P1 is must-fix"
run finding --finding tk-f1 --ruling question --reason "Which name?"
eq "$RC" 64 "a question names its gate"
run finding --finding tk-f1 --ruling question --reason "Which name?" --gate tk-gate1
has "$(cat "$LOG")" "--disposition needs-you --reason Which name? --answer Which name? --visit tk-gate1" "a question rides its gate"
STUB_RC_FINDING=2 run finding --finding tk-f1 --ruling declined --reason r
eq "$RC" 2 "a ruling that does not land is run again"
facts review-loop.iteration.1.rule-and-repair repair 1 true
run finding --finding tk-f1 --ruling declined --reason r
eq "$(called finding.sh)" 0 "a shadow run rules nothing on the finding"

# --- deliver ---------------------------------------------------------------------
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1
echo mp4 > "$TMP/cap.mp4"
run deliver --file "$TMP/cap.mp4"
has "$(cat "$LOG")" "demo-deliver.sh --file $TMP/cap.mp4 --pr https://github.com/o/r/pull/7" "a demo lane delivers its capture"
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1 true
run deliver --file "$TMP/cap.mp4"
eq "$(called demo-deliver.sh)" 0 "a shadow run keeps it in the workspace"

# --- the reads make each step's worktree in its part ----------------------------
facts review-loop.iteration.1.triage triage 1
run triage
eq "$RC" 0 "triage reads"
eq "$(git -C "$WS/triage/wt" rev-parse HEAD 2>/dev/null)" "$HEAD1" "in its own worktree at the head"
has "$(cat "$LOG")" "gctk-scripts-dir $SD" \
    "its read of the check index names the pack's scripts beside review-run.sh, with none in the caller's environment and no binding gc knows"
has "$OUT" "The change to judge: git diff origin/main...$HEAD1 (the whole PR)" "and prints the change and the rule that chose it"
has "$OUT" "== The rig's guidance for triage at $HEAD1, empty when it keeps none
the rig guidance for triage, read in $WS/triage/wt" "and the rig's guidance for triage, read in its worktree"
has "$(cat "$LOG")" "gctk review guidance triage --at $HEAD1" "…at the head it judges"
STUB_RC_GUIDANCE=1 run triage
eq "$RC" 2 "triage's read stops, exit 2, when the rig's guidance does not read"
hasnt "$OUT" "Write the output to" "and names no output to write"
facts review-loop.iteration.1.triage triage 1 false "$HEAD1" "the head already passed into its target"
run triage
eq "$RC" 0 "triage reads at a head that already passed"
has "$OUT" "== The change to judge: none, because the head already passed into its target: pick only the checks an ask open on tk-pr sends back" \
    "and says there is no change to judge, so it picks only what an ask sends back"
hasnt "$OUT" "git diff" "and prints no diff to judge"
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1
run lane --check arch
eq "$RC" 0 "a lane reads"
eq "$(git -C "$WS/lane-arch/wt" rev-parse HEAD 2>/dev/null)" "$HEAD1" "in its own worktree at the head"
has "$(cat "$LOG")" "review-evidence.sh --anchor tk-pr --commit $HEAD1 --worktree $WS/lane-arch/wt" "with what gctk rig recorded there"
# A part the workspace cannot take, here a file where the step's directory goes.
: > "$WS/lane-pm"
run lane --check pm
eq "$RC" 1 "a lane's read whose worktree does not land stops there"
eq "$(called review-evidence.sh)" 0 "and reads nothing in its place"
rm -f "$WS/lane-pm"
facts review-loop.iteration.1.rule-and-repair repair 1
rm -rf "$WS/repair"; : > "$WS/repair"
run repair
eq "$RC" 1 "the repair's read whose worktree does not land stops there"
hasnt "$OUT" "Write the output to" "and names no worktree to work in"
rm -f "$WS/repair"

echo
echo "review-run.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
