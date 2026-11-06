#!/usr/bin/env bash
# Hermetic test for assets/scripts/scaffolding-sweep.sh — arm 9 of the merge
# cadence, and the per-anchor sweep pr-facts.sh's disposition arm runs before
# its close. Covers: the sweep condition (machine scaffolding on a DISPOSED
# anchor, by either disposition marker) and every way it fails to hold (a live
# anchor, a merged anchor, no disposition, no anchor_bead, an anchor that does
# not resolve); the scope boundary (task_kind=visit and task_kind=review left
# standing, a rebase_hold freeze left to the operator); the close ordering (a
# rework closed before the finding it blocks, under the store's blocks-refusal);
# the disposal shape (gc.outcome=moot, the reason APPENDED to the dispatch note,
# status closed, both read back); a claimed bead swept anyway; closed and
# non-scaffolding beads untouched; idempotence across passes; a write that does
# not read back; and an unreadable enumeration, which sweeps nothing and says so.
# --anchor: the sweep scoped to one anchor, the whole blocker set a disposed
# anchor's close meets cleared in one pass, and its exit codes. The finding
# scope: a finding is mooted only when it objects to the disposed diff, and a
# human comment on a line the PR left unchanged, or one whose line can never be
# checked, is carried forward to a bug bead through bead-rehome.sh, filed once
# across retries; an unreadable comment list carries nothing forward on a guess.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-scaffolding-sweep-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/scaffolding-sweep.sh"
SUT="$SD/scaffolding-sweep.sh"
run() { "$SUT" 2>&1; }

scaf() { # id anchor kind [status]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"dispatch note","title":"%s on %s","metadata":{"task_kind":"%s","anchor_bead":"%s"}}' \
    "$1" "${4:-open}" "$3" "$2" "$3" "$2"
}
# extra: a JSON metadata fragment, already comma-prefixed when non-empty.
anchor() { # id merge_result [extra_meta]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"anchor %s","metadata":{"merge_result":"%s"%s}}' \
    "$1" "$1" "$2" "${3:-}"
}
# The anchor names a successor through bd's supersedes edge, which bead-rehome.sh
# records with the close. The edge rides the row as `gc bd list` prints it, the
# row bd_disposed_to reads.
sup() { jq -c '.dependencies = [{issue_id: .id, depends_on_id: "SUCC", type: "supersedes"}]'; }
DISP='"gc.pr_close_disposition_kind":"not-needed"'  # pr-dispose recorded intent

echo "# the sweep condition: machine scaffolding on a disposed anchor (a supersedes edge)"
store "[$(scaf F1 ADISP finding),$(scaf V1 ADISP validation),$(scaf RW1 ADISP rework),$(anchor ADISP pull_request | sup)]"
out=$(run); rc=$?
eq "$rc" 0 "a completed pass exits 0"
eq "$(bstatus F1)"  "closed" "the finding is retired"
eq "$(bstatus V1)"  "closed" "the validation pass is retired"
eq "$(bstatus RW1)" "closed" "the rework is retired"
eq "$(meta F1 gc.outcome)" "moot" "…recorded as moot, not as a verdict"
eq "$(bstatus ADISP)" "open" "the anchor itself is NEVER closed by this arm"
eq "$(jq -r '.[] | select(.id == "ADISP") | [.dependencies[]? | .type + ">" + .depends_on_id] | join(",")' "$STUB_STORE")" "supersedes>SUCC" "…and the anchor is otherwise untouched"
has "$out" "3 scaffolding bead(s) closed" "the pass counts what it closed"
has "$out" "closed finding F1" "…and names each"
n=$(notes F1)
has "$n" "dispatch note" "the dispatch note survives (notes are APPENDED)"
has "$n" "retired as moot" "the reason is recorded on the bead"
has "$n" "ADISP" "…naming the anchor"
has "$n" "superseded by SUCC" "…and the disposition that made it moot"

echo "# the other disposition marker: a pre-recorded PR-close disposition"
store "[$(scaf F2 ADISP2 finding),$(anchor ADISP2 pull_request ",$DISP")]"
run >/dev/null
eq "$(bstatus F2)" "closed" "a pr_close_disposition_kind is a disposed anchor too"
has "$(notes F2)" "pr_close_disposition=not-needed" "…and the note names it"

echo "# scope boundary: human visits and review beads are left standing"
store "[$(scaf F3 ADISP3 finding),{\"id\":\"VIS3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"visit\",\"metadata\":{\"task_kind\":\"visit\",\"anchor_bead\":\"ADISP3\"}},{\"id\":\"REV3\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"review\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"ADISP3\"}},$(anchor ADISP3 pull_request | sup)]"
out=$(run)
eq "$(bstatus F3)"  "closed" "the finding on the disposed anchor is retired"
eq "$(bstatus VIS3)" "open"  "a human visit on the same anchor is left standing"
eq "$(bstatus REV3)" "open"  "a review bead is left to review-sweep, not this arm"
has "$out" "1 scaffolding bead(s) closed" "…so only the one machine bead is swept"

echo "# a live anchor's scaffolding is in flight, not moot"
store "[$(scaf F4 ALIVE finding),$(anchor ALIVE pull_request)]"
out=$(run)
eq "$(bstatus F4)" "open" "an anchor with no disposition marker is left alone"
has "$out" "0 scaffolding bead(s) closed" "…and nothing is swept"

echo "# a merged anchor is a landing, not a disposal (close-answered's, not this arm's)"
store "[$(scaf F5 AMRG finding),$(anchor AMRG merged | sup)]"
run >/dev/null
eq "$(bstatus F5)" "open" "scaffolding on a merged anchor is left alone even with a successor named"

echo "# reworks close before the findings they block, in one pass"
# The edges finding.sh writes: a fix unit blocks the anchor and every must-fix
# finding it answers, and the finding blocks the anchor.
store "[$(scaf FB ABLK finding),$(scaf RB ABLK rework),$(anchor ABLK pull_request | sup)]"
printf 'RB|blocks|FB\nRB|blocks|ABLK\nFB|blocks|ABLK\n' >> "$STUB_DEPS"
out=$(STUB_ENFORCE_BLOCKS=1 run); rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(bstatus RB)" "closed" "the rework closes (nothing blocks it)"
eq "$(bstatus FB)" "closed" "…and the finding it blocked closes the same pass"
has "$out" "2 scaffolding bead(s) closed" "…with nothing held for a retry"
: > "$STUB_DEPS"

echo "# an operator's rebase_hold freeze is left standing"
store "[$(scaf RH AHOLD rework | jq -c '.metadata.rebase_hold = "operator is reviewing this branch"'),$(scaf FH AHOLD finding),$(anchor AHOLD pull_request ",$DISP")]"
out=$(run); rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(bstatus RH)" "open" "a frozen rework on a disposed anchor is not closed out from under the operator"
has "$out" "carries rebase_hold" "…and the pass says why it is left"
eq "$(bstatus FH)" "closed" "the unfrozen finding beside it is still retired"

echo "# a claimed scaffolding bead is swept too"
store "[$(scaf F6 ADISP6 rework in_progress),$(anchor ADISP6 pull_request | sup)]"
run >/dev/null
eq "$(bstatus F6)" "closed" "a claimed rework on a disposed anchor has nothing left to produce"

echo "# untestable conditions are not satisfied conditions"
store "[{\"id\":\"F7\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"t\",\"metadata\":{\"task_kind\":\"finding\"}}]"
run >/dev/null
eq "$(bstatus F7)" "open" "a finding carrying no anchor_bead is left alone"
store "[$(scaf F8 AGONE finding)]"
out=$(run)
eq "$(bstatus F8)" "open" "a finding whose anchor does not resolve is left alone"
has "$out" "does not resolve" "…and the pass says which anchor it could not read"

echo "# only scaffolding beads, only live ones (idempotence across passes)"
store "[{\"id\":\"W1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"work\",\"metadata\":{\"anchor_bead\":\"A9\"}},$(scaf F9 A9 finding closed),$(anchor A9 pull_request | sup)]"
out=$(run)
eq "$(bstatus W1)" "open" "a bead carrying no scaffolding task_kind is not this arm's business"
has "$out" "no live scaffolding beads" "…and an all-closed population is nothing to do"

echo "# a close that does not read back is reported, never counted"
store "[$(scaf FX ADX finding),$(anchor ADX pull_request | sup)]"
out=$(STUB_DROP_KEYS="FX:status" run); rc=$?
eq "$rc" 0 "a stuck write does not fail the arm (the next pass retries)"
eq "$(bstatus FX)" "open" "the bead really did not close"
has "$out" "did not read back" "…and the pass says so"
has "$out" "0 scaffolding bead(s) closed" "…without counting it swept"
has "$out" "1 write(s) held for retry" "…and reports it held for retry"

echo "# an unreadable enumeration sweeps nothing"
store "[$(scaf FY ADY finding),$(anchor ADY pull_request | sup)]"
out=$(STUB_LIST_FAIL=1 run); rc=$?
eq "$rc" 1 "an unreadable scaffolding listing exits 1"
eq "$(bstatus FY)" "open" "…and closes nothing"
has "$out" "false all-clear" "…rather than reporting one"

# bead-rehome.sh, the close a carried-forward finding takes: on success it
# closes the origin and records its supersedes edge onto the successor.
# STUB_REHOME_RC models a refusal that closes nothing, and STUB_REHOME_NOEDGE a
# close whose edge did not write.
cat > "$SD/bead-rehome.sh" <<'REHOME'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_REHOME_LOG:?}"
origin=""; succ=""
while [ $# -gt 0 ]; do
  case "$1" in
    --origin)    shift; origin="${1:-}" ;;
    --successor) shift; succ="${1:-}" ;;
  esac
  shift || true
done
[ -z "${STUB_REHOME_RC:-}" ] || exit "$STUB_REHOME_RC"
gc bd update "$origin" --status=closed >/dev/null 2>&1 || exit 5
[ -z "${STUB_REHOME_NOEDGE:-}" ] || exit 4
gc bd dep add "$origin" "$succ" --type supersedes >/dev/null 2>&1 || exit 4
REHOME
chmod +x "$SD/bead-rehome.sh"
export STUB_REHOME_LOG="$TMP/rehome.log"; : > "$STUB_REHOME_LOG"

# The live beads still blocking <id>, under the store's edges.
open_blockers() {
  local n=0 b
  for b in $(awk -F'|' -v id="$1" '$2 == "blocks" && $3 == id { print $1 }' "$STUB_DEPS"); do
    [ "$(bstatus "$b")" = "closed" ] || n=$((n + 1))
  done
  printf '%s' "$n"
}
# A human finding pr-facts.sh filed from a PR comment: the locus names what the
# comment was on, and finding.comment_id is the comment, when one was recorded.
hfind() { # id anchor locus [comment-id]
  printf '{"id":"%s","status":"open","assignee":"","notes":"dispatch note","title":"finding[human]: objection %s","description":"Locus: %s\\n\\nThe objection %s.\\n\\nRaised by human:op reviewing anchor %s.","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.lane":"human","finding.source":"human:op","finding.disposition":"must-fix"%s}}' \
    "$1" "$1" "$3" "$1" "$2" "$2" "${4:+,\"finding.comment_id\":\"$4\"}"
}
# The bugs born discovered-from <finding>, one id a line: the beads that carry
# its objection forward.
carriers() {
  local b
  for b in $(awk -F'|' -v f="$1" '$2 == "discovered-from" && $3 == f { print $1 }' "$STUB_DEPS"); do
    [ "$(jq -r --arg b "$b" '.[] | select(.id == $b) | .issue_type // "task"' "$STUB_STORE")" = "bug" ] && printf '%s\n' "$b"
  done
}
# The bead that carries <finding>'s objection forward, if one was filed.
carrier() { local c; c=$(carriers "$1" | head -1); printf '%s' "${c:-<none>}"; }
# The bead <id> names through its own supersedes edge, or <none>.
succ_of() { awk -F'|' -v id="$1" '$1 == id && $2 == "supersedes" { print $3; f = 1; exit } END { if (!f) print "<none>" }' "$STUB_DEPS"; }
# PR #<n>'s inline review comments: 501 sits on an added line, and 502 and 504
# on lines the diff left unchanged, 504 in a file at the repository root.
comments() { # num
  printf '[{"id":501,"path":"assets/scripts/a.sh","diff_hunk":"@@ -10,3 +10,4 @@\\n context\\n+added line"},{"id":502,"path":"docs/b.md","diff_hunk":"@@ -5,3 +5,3 @@\\n context\\n unchanged line"},{"id":504,"path":"README.md","diff_hunk":"@@ -1,3 +1,3 @@\\n context\\n unchanged line"}]' > "$GH_DIR/comments_$1.json"
}
PRD() { printf ',%s,"pr_number":"%s"' "$DISP" "$1"; }   # a disposed anchor with a PR

echo "# --anchor sweeps only the one anchor it names"
store "[$(scaf FA1 AONE finding),$(scaf FA2 ATWO finding),$(anchor AONE pull_request ",$DISP"),$(anchor ATWO pull_request ",$DISP")]"
out=$("$SUT" --anchor AONE 2>&1); rc=$?
eq "$rc" 0 "a settled anchor exits 0"
eq "$(bstatus FA1)" "closed" "the named anchor's finding is retired"
eq "$(bstatus FA2)" "open" "…and another disposed anchor's is left for arm 9"
out=$("$SUT" --anchor ANONE 2>&1); rc=$?
eq "$rc" 0 "an anchor with no live scaffolding exits 0"
has "$out" "no live scaffolding beads on ANONE" "…and says so"
out=$(STUB_LIST_FAIL=1 "$SUT" --anchor AONE 2>&1); rc=$?
eq "$rc" 1 "an unreadable enumeration of the anchor exits 1, sweeping nothing"
"$SUT" --anchor >/dev/null 2>&1; eq "$?" 2 "--anchor with no id is a usage error"
"$SUT" --bogus >/dev/null 2>&1; eq "$?" 2 "an unknown argument is a usage error"

echo "# --anchor clears the whole blocker set a disposed anchor's close meets"
# What bead-rehome.sh's non-force close refuses on, scaffolding-wise: a claimed
# fix unit, the must-fix finding it answers, and a validation pass, each with a
# blocks edge on the anchor.
store "[$(scaf RW ADONE rework in_progress),$(scaf FM ADONE finding),$(scaf VP ADONE validation),$(anchor ADONE pull_request ",$DISP")]"
printf 'RW|blocks|FM\nRW|blocks|ADONE\nFM|blocks|ADONE\nVP|blocks|ADONE\n' > "$STUB_DEPS"
: > "$STUB_GC_LOG"
out=$(STUB_ENFORCE_BLOCKS=1 "$SUT" --anchor ADONE 2>&1); rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(open_blockers ADONE)" "0" "nothing left open blocks the anchor's close"
eq "$(bstatus ADONE)" "open" "…and the anchor itself is still not this sweep's to close"
has "$out" "3 scaffolding bead(s) closed" "…all three retired in one pass"
eq "$(grep -c '^bd show ADONE ' "$STUB_GC_LOG")" "1" "…reading the anchor once, not once per bead"
: > "$STUB_DEPS"

echo "# a finding is mooted only when it objects to the disposed diff"
store "[$(hfind FMC APR assets/scripts/x.sh:fn | jq -c '.metadata["finding.source"] = "machine:codex"'),$(hfind FPR APR 'PR review' 900),$(hfind FCH APR assets/scripts/a.sh:12 501),$(hfind FCX APR docs/b.md:7 502),$(hfind FGN APR docs/c.md:3 503),$(anchor APR pull_request "$(PRD 40)")]"
comments 40
: > "$STUB_GH_LOG"; : > "$STUB_GC_LOG"; : > "$STUB_REHOME_LOG"
out=$("$SUT" --anchor APR 2>&1); rc=$?
eq "$rc" 0 "the pass exits 0"
eq "$(meta FMC gc.outcome)" "moot" "a machine-lane finding is mooted with its diff"
has "$(notes FMC)" "machine-lane finding objects only to the diff it reviewed" "…and the note says why"
eq "$(meta FPR gc.outcome)" "moot" "a human finding naming no file objects to the PR as a whole, and is mooted"
eq "$(meta FCH gc.outcome)" "moot" "a human comment on a line the PR changed is mooted"
has "$(notes FCH)" "sits on a line PR#40 changed" "…and the note says so"
eq "$(meta FGN gc.outcome)" "moot" "a human comment no longer on the PR is mooted"
has "$(notes FGN)" "no longer on PR#40" "…and the note says so"
BUG=$(carrier FCX)
hasnt "$BUG" "<none>" "a human comment on a line the PR left unchanged is carried forward to a bead of its own"
eq "$(bstatus FCX)" "closed" "…the finding closes"
eq "$(meta FCX gc.outcome)" "<absent>" "…but not as moot"
eq "$(succ_of FCX)" "$BUG" "…naming the bead that carries it"
has "$(cat "$STUB_REHOME_LOG")" "--origin FCX --successor $BUG --kind re-homed" "…through bead-rehome.sh"
eq "$(bstatus "$BUG")" "open" "the carrier is open work"
eq "$(jq -r --arg b "$BUG" '.[] | select(.id == $b) | .title' "$STUB_STORE")" "objection FCX" "…titled with the objection"
BUGD=$(jq -r --arg b "$BUG" '.[] | select(.id == $b) | .description' "$STUB_STORE")
has "$BUGD" "The objection FCX." "…its description carries the objection"
has "$BUGD" "Carried forward from finding FCX when anchor APR was disposed" "…and where it came from"
has "$BUGD" "did not change" "…and why the disposal does not answer it"
eq "$(meta "$BUG" anchor_bead)" "<absent>" "…with no anchor_bead, so a first reaction can reach it"
has "$(cat "$STUB_GC_LOG")" "-t bug" "…filed as a bug"
has "$(cat "$STUB_GC_LOG")" "discovered-from:FCX" "…discovered from the finding"
eq "$(grep -c 'pulls/40/comments' "$STUB_GH_LOG")" "1" "the PR's comments are read once for every finding on the anchor"
has "$out" "1 finding(s) carried forward" "the pass counts what it carried forward"

echo "# a carried-forward finding is not filed twice"
# An earlier pass filed the bug, then lost the finding's close.
store "[$(hfind FC2 AP2 docs/b.md:7 502),{\"id\":\"BUG2\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"objection FC2\",\"issue_type\":\"bug\",\"metadata\":{}},$(anchor AP2 pull_request "$(PRD 41)")]"
printf 'BUG2|discovered-from|FC2\n' > "$STUB_DEPS"
comments 41
: > "$STUB_GC_LOG"; : > "$STUB_REHOME_LOG"
"$SUT" --anchor AP2 >/dev/null 2>&1
hasnt "$(cat "$STUB_GC_LOG")" "bd create" "no second carrier is filed"
eq "$(succ_of FC2)" "BUG2" "…the finding closes onto the one already filed"
: > "$STUB_DEPS"

echo "# a deferral's follow-up is not the carrier"
# finding.sh files a deferral's follow-up discovered-from the finding too: a
# task stamped source_finding, which waits for the anchor and is no bug.
store "[$(hfind FC4 AP7 docs/b.md:7 502),{\"id\":\"FUP4\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"follow-up FC4\",\"issue_type\":\"task\",\"metadata\":{\"source_finding\":\"FC4\"}},$(anchor AP7 pull_request "$(PRD 46)")]"
printf 'FUP4|discovered-from|FC4\n' > "$STUB_DEPS"
comments 46
: > "$STUB_GC_LOG"
"$SUT" --anchor AP7 >/dev/null 2>&1
has "$(cat "$STUB_GC_LOG")" "bd create" "a bug is filed beside the follow-up"
BUG4=$(carrier FC4)
hasnt "$BUG4" "<none>" "…born discovered-from the finding"
eq "$(succ_of FC4)" "$BUG4" "…and the finding closes onto the bug, not onto the follow-up"
eq "$(bstatus FUP4)" "open" "…which is left as it was"
: > "$STUB_DEPS"

echo "# a refused bead-rehome leaves the finding for the next pass"
store "[$(hfind FC3 AP3 docs/b.md:7 502),$(anchor AP3 pull_request "$(PRD 42)")]"
comments 42
out=$(STUB_REHOME_RC=5 "$SUT" --anchor AP3 2>&1); rc=$?
eq "$rc" 0 "a refused close does not fail the pass (its blocker is the close's to report)"
eq "$(bstatus FC3)" "open" "the finding stays open"
has "$out" "did not read back" "…and the pass says so"
has "$out" "1 write(s) held for retry" "…holding it for a retry"
BUG3=$(carrier FC3)
"$SUT" --anchor AP3 >/dev/null 2>&1
eq "$(succ_of FC3)" "$BUG3" "the retry closes it onto the bug the first pass filed"
eq "$(carriers FC3 | wc -l | tr -d ' ')" "1" "…and files no twin"

echo "# a close that names no successor is not counted carried forward"
store "[$(hfind FC5 AP8 docs/b.md:7 502),$(anchor AP8 pull_request "$(PRD 47)")]"
comments 47
out=$(STUB_REHOME_NOEDGE=1 "$SUT" --anchor AP8 2>&1); rc=$?
eq "$(succ_of FC5)" "<none>" "the finding closed with no edge onto its bug"
has "$out" "did not read back" "…which the pass reports"
has "$out" "0 finding(s) carried forward" "…without counting it carried forward"

echo "# a human finding whose line can never be checked is carried forward"
store "[$(hfind FNI AP4 docs/b.md:7),$(hfind FNP ANOPR docs/b.md:7 502),$(anchor AP4 pull_request "$(PRD 43)"),$(anchor ANOPR pull_request ",$DISP")]"
comments 43
run >/dev/null
hasnt "$(carrier FNI)" "<none>" "a finding that recorded no comment id is carried forward"
has "$(jq -r --arg b "$(carrier FNI)" '.[] | select(.id == $b) | .description' "$STUB_STORE")" "records no comment id" "…saying why"
hasnt "$(carrier FNP)" "<none>" "a finding on an anchor that records no PR is carried forward"

echo "# a file at the repository root is a file; a Conversation comment, or no locus at all, names none"
store "[$(hfind FRT AP6 README.md:2 504),$(hfind FCV AP6 'PR conversation' 905),$(hfind FNL AP6 x | jq -c '.description = "The objection FNL, filed with no Locus line."'),$(anchor AP6 pull_request "$(PRD 45)")]"
comments 45
out=$("$SUT" --anchor AP6 2>&1); rc=$?
eq "$rc" 0 "the pass exits 0"
BUGR=$(carrier FRT)
hasnt "$BUGR" "<none>" "a comment on an unchanged line of a root-level file is carried forward, not mooted as an objection to the whole PR"
eq "$(succ_of FRT)" "$BUGR" "…the finding closes naming the bead that carries it"
eq "$(meta FCV gc.outcome)" "moot" "a Conversation comment objects to the PR as a whole, and is mooted"
has "$(notes FCV)" "names no file" "…and the note says so"
eq "$(meta FNL gc.outcome)" "moot" "a finding with no Locus line names no file, and is mooted"
eq "$(carrier FNL)" "<none>" "…with nothing carried forward from its first line"

echo "# an unreadable comment list leaves the finding for the next pass"
store "[$(hfind FUR AP5 docs/b.md:7 502),$(hfind FUM AP5 'PR review' 900),$(anchor AP5 pull_request "$(PRD 44)")]"
comments 44
out=$(STUB_GH_LIST_RC=1 run); rc=$?
eq "$rc" 0 "arm 9 completes its pass (exit 0)"
eq "$(bstatus FUR)" "open" "the finding whose line could not be read is left open"
eq "$(carrier FUR)" "<none>" "…and is not carried forward on a guess"
has "$out" "could not be read" "…and the pass says why"
has "$out" "1 finding(s) unread" "…counting it"
eq "$(bstatus FUM)" "closed" "a finding that needs no comment read is still retired"
store "[$(hfind FUR AP5 docs/b.md:7 502),$(anchor AP5 pull_request "$(PRD 44)")]"
STUB_GH_LIST_RC=1 "$SUT" --anchor AP5 >/dev/null 2>&1; rc=$?
eq "$rc" 3 "--anchor exits 3, so the caller does not close the anchor past it this pass"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
