#!/usr/bin/env bash
# Tests for review-run.sh against real git repositories, a bare origin among
# them, with gc, gctk, gh and the scripts it calls beside it stubbed. The gctk
# stub answers `review step` from a fixture each case sets, and every stub logs
# the calls it gets.
#
# Covers prepare making the workspace, cancelling a run that must stop with no
# result, and stopping with nothing made when its check of the run does not
# answer; a verb the held step does not own refused; output writing what
# gctk printed as the step's gc.output_json, from the step's own file, and
# writing nothing for an output gctk refuses, a shadow round handing gctk its
# writes; triage's withdrawal; the push returning the PR to draft before it
# pushes, with a lease on the head the round judged, pushing nothing when the
# draft does not answer or the branch moved, and nothing in a shadow run; the
# post of the head's comment, or the edit of the one its mark finds, nothing
# when there is nothing to answer, and nothing in a shadow run; a deferred fix
# filed waiting on the PR's bead and armed, found rather than filed again; a
# question put to a gate; the record asking a person when the loop exhausted
# its attempts, and removing the workspace, which a shadow run keeps; and the
# reads making each step's worktree in its own part of the workspace, and
# stopping when it does not land.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only
PASS=0; FAIL=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-review-run-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
unset "${!GC_@}" "${!BEADS_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# The scripts directory: the script under test and review-workspace.sh with the
# lib it sources, and a stub for every other script it calls, each logging.
SD="$TMP/scripts"; mkdir -p "$SD"
cp "$HERE/review-run.sh" "$HERE/review-workspace.sh" "$HERE/gctk-resolve.sh" "$SD/"
LOG="$TMP/calls.log"; export LOG
for s in decline.sh human-gate.sh pr-post.sh demo-deliver.sh review-evidence.sh; do
    { printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$SD/$s" <<'STUB'
printf '%s %s\n' "${0##*/}" "$*" >> "$LOG"
case "${0##*/}" in
    human-gate.sh) echo "tk-gate1" ;;
    pr-post.sh) [ "$1" = comment ] && echo "https://github.com/o/r/pull/7#issuecomment-9" ;;
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
    "bd show") printf '[{"id":"%s","metadata":{"gc.var.repair_target":"rig/gc-toolkit.polecat"}}]\n' "$3" ;;
    "bd list") printf '%s\n' "${STUB_LIST:-[]}" ;;
    "bd create") echo '{"id":"tk-new"}' ;;
    "bd dep") ;;
esac
STUB
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$BIN/gctk" <<'STUB'
printf 'gctk %s\n' "$*" >> "$LOG"
case "$1 $2" in
    "review step")
        case " $* " in *" --prepare "*)
            [ -z "${STUB_PREPARE_WHY:-}" ] || { echo "gctk review step: run tk-run must stop with no result: $STUB_PREPARE_WHY" >&2; exit 3; }
            [ -z "${STUB_PREPARE_RC:-}" ] || { echo "gctk review step: GitHub did not answer for https://github.com/o/r/pull/7" >&2; exit "$STUB_PREPARE_RC"; } ;;
        esac
        cat "$STUB_FACTS" ;;
    "review output") [ -z "${STUB_REFUSE:-}" ] || { echo "gctk review output: $STUB_REFUSE; write it again" >&2; exit 3; }
        echo '{"review":"x","iteration":1}' ;;
    "review comment") [ -f "$STUB_GCTK_OUT" ] && cat "$STUB_GCTK_OUT" ;;
    "review record") printf '%s\n' "${STUB_RECORD:-tk-pr: review passed at x into main}" ;;
    "pr draft") [ -z "${STUB_ORIGIN:-}" ] || git -C "$STUB_ORIGIN" rev-parse polecat/tk-pr > "$STUB_ORIGIN.at-draft"
        exit "${STUB_RC_DRAFT:-0}" ;;
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

# facts <ref> <output> <iteration> [shadow] — the held step's facts.
facts() {
    jq -n --arg ref "$1" --arg out "$2" --argjson n "$3" --argjson shadow "${4:-false}" --arg h "$HEAD1" \
        '{step: "tk-step", ref: $ref, output: $out, iteration: $n, run: "tk-run", pr_bead: "tk-pr",
          pr: "https://github.com/o/r/pull/7", branch: "polecat/tk-pr", target: "main", first_head: $h,
          head: $h, shadow: $shadow, change: {head: $h, why: "the whole PR"}}' > "$STUB_FACTS"
}
run() { : > "$LOG"; OUT=$(bash "$SD/review-run.sh" "$@" 2>&1); RC=$?; }
called() { grep -c -- "$1" "$LOG"; }

# --- prepare ---------------------------------------------------------------------
facts mol-pr-review.prepare "" 0
run prepare
eq "$RC" 0 "prepare goes on for a run that stands"
has "$OUT" "The run's workspace: $WS" "and prints the run's workspace"
eq "$(ls -ld "$WS" | cut -c1-10)" "drwx------" "which it makes, private to its user"
STUB_PREPARE_WHY="the PR's head is abc, no longer the run's head" run prepare
eq "$RC" 3 "prepare refuses a run that must stop"
has "$(cat "$LOG")" "decline.sh --step mol-pr-review.prepare --reason run tk-run must stop with no result: the PR's head is abc" \
    "and cancels it with no result, saying why"
STUB_PREPARE_RC=2 run prepare
eq "$RC" 2 "prepare stops, exit 2, when its check of the run does not answer"
has "$OUT" "GitHub did not answer" "and says which read did not answer"
eq "$(called decline.sh)" 0 "and cancels nothing, since a retry may find the run stands"
hasnt "$OUT" "The run's workspace" "and does not go on as if the run stood"

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
facts review-loop.iteration.1.rule-and-repair repair 1 true
: > "$WS/repair/shadow-writes.txt"
run push
eq "$(called 'pr draft')" 0 "a shadow run drafts nothing"
has "$(cat "$WS/repair/shadow-writes.txt")" "push: 1 commit(s) onto polecat/tk-pr" "and keeps the push it made none of"

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
eq "$RC" 0 "a fix outside the diff is deferred"
has "$(cat "$LOG")" "gc bd create Move the parser -t task" "to a bead of its own"
has "$(cat "$LOG")" "--deps discovered-from:tk-pr --metadata {\"target\":\"main\"}" "from the PR's bead, with the PR's target"
has "$(cat "$LOG")" "gc bd dep add tk-new tk-pr --type=blocks" "waiting on the PR's bead"
has "$(cat "$LOG")" "gctk bead arm tk-new --target rig/gc-toolkit.polecat --on mol-polecat-work" "and armed on the run's repair pool"
STUB_LIST='[{"id":"tk-old","title":"Move the parser","dependencies":[{"depends_on_id":"tk-pr","dependency_type":"discovered-from"}]}]' \
    run defer --title "Move the parser" --file "$TMP/defer.md"
eq "$(called 'bd create')/$OUT" "0/tk-old"$'\n'"review-run: tk-old already carries this fix" "a fix already filed is found, not filed again"

# --- question --------------------------------------------------------------------
run question --key c1-scope --message "Is the cap the operator's to set?"
has "$(cat "$LOG")" "human-gate.sh --subject tk-pr --key review-question-c1-scope --message Is the cap" "a question goes to a gate on the PR's bead"
has "$OUT" "tk-gate1" "and prints the gate"
run question --key "Bad Key" --message m
eq "$RC" 64 "a key that is no slug is a usage error"

# --- deliver ---------------------------------------------------------------------
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1
echo mp4 > "$TMP/cap.mp4"
run deliver --file "$TMP/cap.mp4"
has "$(cat "$LOG")" "demo-deliver.sh --file $TMP/cap.mp4 --pr https://github.com/o/r/pull/7" "a demo lane delivers its capture"
facts mol-pr-review-lane.review-loop.iteration.1.triage.item.1.lane lane 1 true
run deliver --file "$TMP/cap.mp4"
eq "$(called demo-deliver.sh)" 0 "a shadow run keeps it in the workspace"

# --- record ----------------------------------------------------------------------
facts mol-pr-review.record "" 0
STUB_RECORD="tk-pr: review did not pass at $FIX into main"$'\n'"tk-pr: the loop exhausted its attempts at $FIX" run record
eq "$RC" 0 "record records the result"
has "$(cat "$LOG")" "human-gate.sh --subject tk-pr --key review-loop-exhausted --message Review run tk-run exhausted its attempts at $FIX" \
    "and asks a person when the loop exhausted, at the last head it judged"
if [ -e "$WS" ]; then bad "record removes the run's workspace"; else ok "record removes the run's workspace"; fi
mkdir -p "$WS"
facts mol-pr-review.record "" 0 true
STUB_RECORD="tk-pr: the loop exhausted its attempts at $FIX" run record
eq "$(called human-gate.sh)" 0 "a shadow run's record files no gate"
if [ -d "$WS" ]; then ok "and keeps its workspace for the comparison"; else bad "and keeps its workspace for the comparison"; fi

# --- the reads make each step's worktree in its part ----------------------------
facts review-loop.iteration.1.triage triage 1
run triage
eq "$RC" 0 "triage reads"
eq "$(git -C "$WS/triage/wt" rev-parse HEAD 2>/dev/null)" "$HEAD1" "in its own worktree at the head"
has "$OUT" "The change to judge: git diff origin/main...$HEAD1 (the whole PR)" "and prints the change and the rule that chose it"
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
