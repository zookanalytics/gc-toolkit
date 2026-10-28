#!/usr/bin/env bash
# blocker-holder.test.sh — whether an automated actor holds an anchor's live
# blockers, over the hermetic bd stub. Seeds each blocker as a store bead with a
# `BLOCKER|blocks|ANCHOR` edge, and a run as a workflow root naming its input
# convoy plus a `CONVOY|tracks|BEAD` edge, which the harness's run-lib stub
# serves. Asserts the one line the script prints, actor, stuck or none, and
# that a read that does not resolve prints nothing and exits 2.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/blocker-holder-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"; harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/blocker-holder.sh"
SUT="$SD/blocker-holder.sh"

anchor() { printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request"}}' "$1"; }
# A blocker: id, status, assignee, then metadata entries to append.
blk() { # <id> <status> <assignee> [<extra-metadata>]
  printf '{"id":"%s","status":"%s","assignee":"%s","notes":"","metadata":{"task_kind":"rework"%s}}' "$1" "$2" "$3" "${4:-}"
}
# A graph.v2 run over <bead>: its input convoy and its workflow root, whose
# status says whether the run is live. The convoy's tracks edge is seeded
# separately in STUB_DEPS.
convoy() { printf '{"id":"%s","status":"open","assignee":"","notes":"","issue_type":"convoy","metadata":{}}' "$1"; }
root()   { printf '{"id":"%s","status":"%s","assignee":"","notes":"","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"%s"}}' "$1" "$2" "$3"; }
POUR=',"gc.execution_routed_to":"rig/gc-toolkit.polecat","source_review_bead":"rv-1"'

echo "# a blocker routed to a pool is held"
store "[$(anchor A1), $(blk B1 open '' ',"gc.routed_to":"rig/gc-toolkit.polecat"')]"
printf 'B1|blocks|A1\n' > "$STUB_DEPS"
out=$("$SUT" --anchor A1); rc=$?
eq "$rc" 0 "an answer exits 0"
eq "$out" "actor B1 routed to rig/gc-toolkit.polecat" "a pool route is an actor"

echo "# a rework the refinery holds, its route cleared, is held"
store "[$(anchor A2), $(blk B2 open 'rig/gc-toolkit.refinery' "$POUR")]"
printf 'B2|blocks|A2\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A2)" "actor B2 claimed by rig/gc-toolkit.refinery" "a claim is an actor, the refinery's hand-back included"

echo "# a poured rework its live run works is held"
store "[$(anchor A3), $(blk B3 open '' "$POUR"), $(convoy C3), $(root R3 in_progress C3)]"
printf 'B3|blocks|A3\nC3|tracks|B3\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A3)" "actor B3 worked by run R3" "a live run working the blocker is an actor"

echo "# a poured rework whose run has ended is held by nothing: the stamp outlives the run"
store "[$(anchor A4), $(blk B4 open '' "$POUR"), $(convoy C4), $(root R4 closed C4)]"
printf 'B4|blocks|A4\nC4|tracks|B4\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A4)" "stuck B4" "an execution stamp with no live run is no actor"

echo "# a blocker with no route, claim or run is stuck"
store "[$(anchor A5), $(blk B5 open '')]"
printf 'B5|blocks|A5\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A5)" "stuck B5" "an unmarked live blocker is stuck"

echo "# a blocker routed to a person is theirs: neither an actor nor stuck"
store "[$(anchor A6), $(blk B6 open '' ',"gc.routed_to":"human"')]"
printf 'B6|blocks|A6\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A6)" "none" "a human route answers none"
store "[$(anchor A6b), $(blk B6b open 'human')]"
printf 'B6b|blocks|A6b\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A6b)" "stuck B6b" "a claim in the name human is no actor either"

echo "# one actor answers for the anchor, whichever blocker is listed first"
store "[$(anchor A7), $(blk B7s open ''), $(blk B7a open '' "$POUR"), $(convoy C7), $(root R7 open C7)]"
printf 'B7s|blocks|A7\nB7a|blocks|A7\nC7|tracks|B7a\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A7)" "actor B7a worked by run R7" "a stuck blocker listed first does not hide the actor after it"

echo "# only live blockers count, a missing status reading open"
store "[$(anchor A8), $(blk B8c closed ''), $(blk B8e '' '')]"
printf 'B8c|blocks|A8\nB8e|blocks|A8\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A8)" "none" "a closed blocker and an empty status hold nothing"
store "[$(anchor A8n), {\"id\":\"B8n\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{}}]"
printf 'B8n|blocks|A8n\n' > "$STUB_DEPS"
eq "$("$SUT" --anchor A8n)" "stuck B8n" "a blocker with no status at all reads open"
store "[$(anchor A9)]"
: > "$STUB_DEPS"
eq "$("$SUT" --anchor A9)" "none" "an anchor nothing blocks answers none"

echo "# a read that does not resolve prints nothing and exits 2"
store "[$(anchor A10), $(blk B10 open '')]"
printf 'B10|blocks|A10\n' > "$STUB_DEPS"
out=$(STUB_DEP_GARBAGE="--direction=down" "$SUT" --anchor A10 2>/dev/null); rc=$?
eq "$rc" 2 "an unreadable blocker list exits 2"
eq "$out" "" "…printing no answer"
out=$(RUN_LIB_STUB_FAIL="runs:B10" "$SUT" --anchor A10 2>/dev/null); rc=$?
eq "$rc" 2 "an unreadable run read exits 2"
eq "$out" "" "…printing no answer, since a run it could not read might be live"

echo "# blocker lines the loops cannot be handed print nothing and exit 2"
# 400 blockers with 400-byte ids make about 160 KB of lines, past the 64 KB
# above which bash backs a here-string with a temp file, so a loop fed one
# under a zero file-size limit would run zero times and answer none. Only the
# last blocker is routed, so an answer means the loop read every line.
pad=$(printf '%0400d' 0)
big="[$(anchor A11)"; : > "$STUB_DEPS"
for i in $(seq 1 399); do
  big="$big, $(blk "B11-$i-$pad" open '')"
  printf 'B11-%s-%s|blocks|A11\n' "$i" "$pad" >> "$STUB_DEPS"
done
store "$big, $(blk "B11-400-$pad" open '' ',"gc.routed_to":"rig/gc-toolkit.polecat"')]"
printf 'B11-400-%s|blocks|A11\n' "$pad" >> "$STUB_DEPS"
mkdir -p "$TMP/bh-tmp"
out=$(TMPDIR="$TMP/bh-tmp" "$SUT" --anchor A11)
eq "$out" "actor B11-400-$pad routed to rig/gc-toolkit.polecat" "the long list answers with no limit on file size"
out=$( (ulimit -f 0; trap '' XFSZ; TMPDIR="$TMP/bh-tmp" "$SUT" --anchor A11) 2>/dev/null); rc=$?
eq "$rc" 2 "lines that cannot be written to the temp file exit 2"
eq "$out" "" "…printing no answer, never none"
# The first loop answers from routes and claims, and the second reads runs
# only. A read that ends the first loop at its first line stands in for lines
# lost under it: B14 is routed and no run works it, so answering from the
# second loop alone would call it stuck.
store "[$(anchor A14), $(blk B14 open '' ',"gc.routed_to":"rig/gc-toolkit.polecat"')]"
printf 'B14|blocks|A14\n' > "$STUB_DEPS"
out=$(
  read() { # the script's first read gets nothing; every other read, a stub's too, is bash's
    case "$0" in */blocker-holder.sh) [ -n "${_bh_lost:-}" ] || { _bh_lost=1; return 1; } ;; esac
    builtin read "$@"
  }
  export -f read
  TMPDIR="$TMP/bh-tmp" "$SUT" --anchor A14 2>/dev/null
); rc=$?
eq "$rc" 2 "lines lost under the first loop exit 2"
eq "$out" "" "…printing no answer, never stuck"
eq "$(TMPDIR="$TMP/bh-tmp" "$SUT" --anchor A14)" "actor B14 routed to rig/gc-toolkit.polecat" "…where the whole list answers actor"
# The second loop reads the file again, one run read per line. A run read that
# empties the file stands in for lines lost under that loop: B13b's live run is
# then never read, and answering from B13a alone would say stuck.
store "[$(anchor A13), $(blk B13a open ''), $(blk B13b open '' "$POUR"), $(convoy C13), $(root R13 in_progress C13)]"
printf 'B13a|blocks|A13\nB13b|blocks|A13\nC13|tracks|B13b\n' > "$STUB_DEPS"
eq "$(TMPDIR="$TMP/bh-tmp" "$SUT" --anchor A13)" "actor B13b worked by run R13" "the second loop reads the run behind the second blocker"
printf '#!/usr/bin/env bash\nfor f in %q/blocker-holder.*; do [ -f "$f" ] && : > "$f"; done\nexec %q "$@"\n' "$TMP/bh-tmp" "$RUN_LIB_STUB_CMD" > "$TMP/runs-emptying"
chmod +x "$TMP/runs-emptying"
out=$(TMPDIR="$TMP/bh-tmp" RUN_LIB_STUB_CMD="$TMP/runs-emptying" "$SUT" --anchor A13 2>/dev/null); rc=$?
eq "$rc" 2 "lines lost under the second loop exit 2"
eq "$out" "" "…printing no answer, never stuck"
eq "$(ls -A "$TMP/bh-tmp")" "" "no run leaves a temp file behind"
mkdir -p "$TMP/mkbin"
printf '#!/usr/bin/env bash\necho "mktemp: No space left on device" >&2\nexit 1\n' > "$TMP/mkbin/mktemp"
chmod +x "$TMP/mkbin/mktemp"
out=$(PATH="$TMP/mkbin:$PATH" "$SUT" --anchor A13 2>/dev/null); rc=$?
eq "$rc" 2 "a temp file that cannot be created exits 2"
eq "$out" "" "…printing no answer"

echo "# usage"
"$SUT" >/dev/null 2>&1; rc=$?
eq "$rc" 1 "no --anchor is a usage error"
"$SUT" --anchor A1 --bogus >/dev/null 2>&1; rc=$?
eq "$rc" 1 "an unknown argument is a usage error"

echo "----- blocker-holder: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
