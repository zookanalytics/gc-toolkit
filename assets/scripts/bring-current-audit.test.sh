#!/usr/bin/env bash
# Hermetic test for assets/scripts/bring-current-audit.sh: the worker's audit of
# a bring-current round, and the messages composed from a round's record.
#
# add: records an entry and reads it back; replaces the entry for the same path
#   and keeps the others; flattens control characters to one line; refuses an
#   unknown rating, an empty field, an unreadable bead, and a write that does not
#   read back, recording nothing.
# show: prints a bead's entries and question, and an anchor's record.
# render: composes from the anchor's record the round's account as one
#   collapsed block (a summary line that tallies the entries and names the
#   lanes that re-check, what the round needed, the ruling, each judgment entry
#   in full beside the guard's evidence for its own round, each routine entry on
#   one line with its whole decision, an item no entry covers beside its
#   evidence alone, the generated renders), the same shape whether or not the
#   ruling lifts the approval and free of the clause every lift used to carry;
#   the ask a lifting ruling opens the verdict with, empty when the approval
#   stands, its reason clipped so its closing sentence survives; and the
#   dismissal note that says the same ask, or the guard's own ruling told as the
#   guard's with the entries no triage comment carries. Refuses an anchor with
#   no record, and any other form.
# ask: records the question and files ONE visit on the anchor composed from the
#   entries so far and the question; resolves the anchor through anchor_bead,
#   then the branch, then the bead itself; refuses an empty question; a visit
#   that does not land, or a question that does not read back, exits 1.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bring-current-audit-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/bring-current-audit.sh"
SUT="$SD/bring-current-audit.sh"
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
exit "${STUB_ESC_RC:-0}"
ESC
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
export STUB_ESC_RC=0

bead() { # id [extra-metadata]
  printf '{"id":"%s","status":"in_progress","assignee":"polecat","notes":"","title":"Merge main into PR#7 (branch polecat/x1): base rewritten","metadata":{"task_kind":"rework","anchor_bead":"AN1","branch":"polecat/x1","target":"main"%s}}' "$1" "${2:-}"
}
anchorrow() { # id [extra-metadata]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"the PR","metadata":{"merge_result":"pull_request","pr_number":"7","pr_url":"https://github.com/zook/gc-toolkit/pull/7","branch":"polecat/x1"%s}}' "$1" "${2:-}"
}
audit() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .metadata.conflict_audit // "[]") | if type == "string" then . else tojson end' "$STUB_STORE"; }
add() { "$SUT" add "$@" 2>&1; }

echo "# add: an entry is recorded and read back"
store "[$(bead B1), $(anchorrow AN1)]"
out=$(add --bead B1 --path docs/a.md --rating routine --collided "main reworded the intro; the branch added a paragraph after it" \
  --resolution "kept both, main's wording first" --check "the intro reads in order"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "recorded docs/a.md (routine) on B1" "…and says what it recorded"
eq "$(audit B1 | jq -r '.[0] | .path + "|" + .rating + "|" + .resolution')" "docs/a.md|routine|kept both, main's wording first" "the entry is stored on the bead"

echo "# add: a second path is added, and the same path is replaced"
add --bead B1 --path b.sh --rating judgment --collided "main renamed run to start; the branch called run" \
  --resolution "called start" --check "the new call site" >/dev/null
add --bead B1 --path docs/a.md --rating judgment --collided "x" --resolution "rewrote the intro" --check "y" >/dev/null
eq "$(audit B1 | jq -r 'map(.path) | join(",")')" "b.sh,docs/a.md" "each path has one entry"
eq "$(audit B1 | jq -r '.[] | select(.path == "docs/a.md") | .rating + "|" + .resolution')" "judgment|rewrote the intro" "…and a re-add replaces it"

echo "# add: control characters become one line"
add --bead B1 --path c.txt --rating routine --collided "$(printf 'line one\nline\ttwo')" --resolution "kept" --check "c" >/dev/null
eq "$(audit B1 | jq -r '.[] | select(.path == "c.txt") | .collided')" "line one line two" "newlines and tabs fold to single spaces"

echo "# add: refuses an unknown rating, an empty field, an unreadable bead, and a write that does not read back"
before=$(audit B1)
out=$(add --bead B1 --path d.txt --rating mechanical --collided "c" --resolution "r" --check "k"); rc=$?
eq "$rc" "1" "a rating outside routine and judgment exits 1"
has "$out" "routine or judgment" "…naming the enum"
out=$(add --bead B1 --path d.txt --rating routine --collided "c" --resolution "  " --check "k"); rc=$?
eq "$rc" "1" "an empty resolution exits 1"
eq "$(audit B1)" "$before" "…and nothing was recorded"
out=$(add --bead NOPE --path d.txt --rating routine --collided "c" --resolution "r" --check "k"); rc=$?
eq "$rc" "1" "a bead that does not read exits 1"
out=$(STUB_UPDATE_FAIL="B1" add --bead B1 --path d.txt --rating routine --collided "c" --resolution "r" --check "k"); rc=$?
eq "$rc" "1" "a write that does not read back exits 1"
has "$out" "did not read back" "…and says so"
"$SUT" add --bead B1 >/dev/null 2>&1; rc=$?
eq "$rc" "2" "missing arguments are a usage error"

echo "# show: a bead's entries and question, and an anchor's record"
eq "$("$SUT" show --bead B1 | jq -r '.conflict_audit | length')" "3" "a bead's entries"
eq "$("$SUT" show --bead B1 | jq -r '.conflict_question')" "null" "…and no question yet"
eq "$("$SUT" show --anchor AN1)" "null" "an anchor with no round shows null"

# --- render -----------------------------------------------------------------------
REC=$(jq -nc '{head: "0123456789abcdef0123456789abcdef01234567", from: "f", target: "main", bead: "B1", class: "conflicted",
  evidence: [
    {covered: true, kind: "conflict", path: "docs/a.md", commit: "c1", detail: "conflicted where both sides only added lines; the resolution keeps both additions whole"},
    {covered: true, kind: "conflict", path: "b.sh", commit: "c1", detail: "conflicted where the merge base had lines that one or both sides changed, so git could not merge it on its own"},
    {covered: true, kind: "beyond", path: "c.sh", commit: "c1", detail: "changed beyond what merging x produces"},
    {covered: false, kind: "generated", path: "generated/x.md", commit: "c1", detail: "a generated render"}],
  audit: [
    {path: "docs/a.md", collided: "main added a FAQ; the branch added a usage section at the same spot", resolution: "kept both, the FAQ first. Each section reads on its own, so the order only follows the table of contents.", check: "the section order", rating: "routine"},
    {path: "b.sh", collided: "main renamed run to start; the branch added a call to run", resolution: "pointed the new call at start", check: "the new call site in b.sh", rating: "judgment"},
    {path: "c.sh", collided: "the rename broke a caller the merge did not conflict on", resolution: "renamed the caller too", check: "c.sh callers", rating: "judgment"}],
  triage: {review: "RV1", reopen: ["correctness"], add: ["arch"], dismiss: true, reason: "the merge points the new call at start, so it now starts the service; decide whether it should. Look at the call site in b.sh", at: "t"}}')
# The same round, ruled with the approval kept.
KEPT=$(printf '%s' "$REC" | jq -c '.triage.dismiss = false | .triage.reason = "the rename reaches b.sh and c.sh, which correctness and arch can check"')
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -Rc .)")]"

echo "# render --as comment: the round's account, one collapsed block in triage's verdict"
out=$("$SUT" render --anchor AN1 --as comment); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(printf '%s\n' "$out" | head -1)" "<details>" "it opens a collapsed block"
eq "$(printf '%s\n' "$out" | tail -1)" "</details>" "…and closes it"
has "$out" "<summary>Bring-current round: 2 judgment, 1 routine; arch and correctness re-check the merged code; approval lifted</summary>" "the summary tallies the entries, names the lanes that re-check, and says the approval was lifted"
has "$out" "needed 2 conflicted files resolved by hand, and 1 edit beyond what git merges on its own." "…what the round needed"
has "$out" "Triage: arch and correctness run again on the merged code, and the approval is lifted. Why: the merge points the new call at start" "…triage's ruling and its reason"
hasnt "$out" "no longer covers what would land" "…without the clause every lift used to carry"
hasnt "$out" "fresh human review" "…in any form"
has "$out" "- \`b.sh\`, judgment. Collided: main renamed run to start; the branch added a call to run. Decided: pointed the new call at start. Check: the new call site in b.sh. Git: conflicted where the merge base had lines" "a judgment entry in full: collision, decision, check, and the guard's evidence"
has "$out" "- \`docs/a.md\`, routine: kept both, the FAQ first. Each section reads on its own, so the order only follows the table of contents."$'\n' "a routine entry on one line: its whole decision"
hasnt "$out" "Check: the section order" "…with no check or evidence"
first=$(printf '%s\n' "$out" | grep -n '^- `' | head -1)
has "$first" "judgment" "judgment entries come first"
has "$out" "Generated files the merge re-rendered, which need no entry: \`generated/x.md\`." "the generated renders are named"

echo "# render --as comment: a ruling that keeps the approval writes the same account and never says it was removed"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$KEPT" | jq -Rc .)")]"
kept=$("$SUT" render --anchor AN1 --as comment)
has "$kept" "<summary>Bring-current round: 2 judgment, 1 routine; arch and correctness re-check the merged code</summary>" "the summary names no lift"
has "$kept" "Triage: arch and correctness run again on the merged code. Why: the rename reaches b.sh and c.sh" "…nor does the ruling"
hasnt "$kept" "approval" "…and no line mentions the approval"
eq "$(printf '%s\n' "$kept" | grep -E '^- ' )" "$(printf '%s\n' "$out" | grep -E '^- ')" "the file-by-file account is the same, lifted or not"
eq "$(printf '%s\n' "$kept" | grep -c '<details>')" "1" "…in the same one collapsed block"

echo "# render --as ask: what a lift needs from the operator, and nothing when the approval stands"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as ask); rc=$?
eq "$rc" "0" "it exits 0"
eq "$out" "Needs you: the merge points the new call at start, so it now starts the service; decide whether it should. Look at the call site in b.sh. Your approval is lifted until you decide." "the ask names triage's decision and what happens to the approval"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$KEPT" | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as ask); rc=$?
eq "$rc" "0" "a ruling that keeps the approval exits 0"
eq "$out" "" "…and asks nothing"

echo "# render --as dismissal: one paragraph a dismissed approver reads, saying the same ask"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -Rc .)")]"
ask=$("$SUT" render --anchor AN1 --as ask)
out=$("$SUT" render --anchor AN1 --as dismissal)
eq "$out" "$ask The triage comment on this PR has the round in full." "it is the ask, then where the round is told in full"
eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "…in one paragraph"
hasnt "$out" "did not see" "…and never says the approval predates the round"

echo "# render --as comment: a routine entry keeps a later decision, and an abbreviation does not end it"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -c '.audit[0].resolution = "kept both sections. Also dropped the --legacy flag."
  | .audit += [{path: "lib/retry.sh", collided: "c", resolution: "Kept the base retry, e.g. the 3x backoff, and dropped the branch.", check: "k", rating: "routine"}]' | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as comment)
has "$out" "- \`docs/a.md\`, routine: kept both sections. Also dropped the --legacy flag."$'\n' "a decision after the first sentence is in the line"
has "$out" "- \`lib/retry.sh\`, routine: Kept the base retry, e.g. the 3x backoff, and dropped the branch."$'\n' "…and an abbreviation does not cut the line short"

echo "# render --as ask: a long reason is clipped, so the ask's closing sentence and the dismissal note's pointer survive"
LONG="the merge points the new call at start$(printf ', and start now reads the retry settings from the merged config%.0s' $(seq 1 32))"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -c --arg r "$LONG" '.triage.reason = $r' | jq -Rc .)")]"
ask=$("$SUT" render --anchor AN1 --as ask)
has "$ask" "… Your approval is lifted until you decide." "the reason is clipped before the ask's closing sentence"
hasnt "$ask" "…." "…with no period after the clip mark"
out=$("$SUT" render --anchor AN1 --as dismissal)
eq "$out" "$ask The triage comment on this PR has the round in full." "the dismissal note is the clipped ask, then its pointer"
eq "$([ "${#out}" -lt 1990 ] && echo under)" "under" "…well inside the length the guard cuts a dismissal note to"
has "$("$SUT" render --anchor AN1 --as comment)" "Why: $LONG." "the account's ruling line carries the reason whole"

echo "# render: an item no entry covers is listed with the guard's evidence alone"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -c '.audit |= map(select(.path != "c.sh"))' | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as comment)
has "$out" "<summary>Bring-current round: 1 judgment, 1 routine, 1 without an entry;" "the summary counts the item no entry covers"
has "$out" "- \`c.sh\`, no entry from the worker. Git: changed beyond what merging x produces." "…and the account lists it with the guard's evidence"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -Rc .)")]"
hasnt "$("$SUT" render --anchor AN1 --as comment)" "no entry from the worker" "a round every entry covers lists no such item"

echo "# render: an entry carried from an earlier round is shown beside that round's evidence"
# Both rounds touched docs/a.md, so only the round tells the two pieces of
# evidence apart. Both entries are judgment calls, which the account shows in
# full with their evidence.
EARLY="abcdefabcdefabcdefabcdefabcdefabcdefabcd"
CARRY=$(jq -nc --arg e "$EARLY" '{head: "0123456789abcdef0123456789abcdef01234567", from: "f", target: "main", bead: "B1", class: "conflicted",
  evidence: [
    {covered: true, kind: "conflict", path: "docs/a.md", commit: "c2", detail: "conflicted where both sides only added lines; the resolution keeps both additions whole"},
    {covered: true, kind: "conflict", path: "docs/a.md", commit: "c1", detail: "conflicted where the merge base had lines that one or both sides changed", round: $e}],
  audit: [
    {path: "docs/a.md", collided: "main added a FAQ", resolution: "kept both", check: "the FAQ", rating: "judgment"},
    {path: "docs/a.md", collided: "main reworded the intro", resolution: "took main wording", check: "the intro", rating: "judgment", round: $e}],
  triage: null}')
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$CARRY" | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as comment)
has "$(printf '%s\n' "$out" | grep -F 'took main wording')" "Git: conflicted where the merge base had lines" "the earlier round's entry carries the earlier round's evidence"
has "$(printf '%s\n' "$out" | grep -F 'Decided: kept both')" "Git: conflicted where both sides only added lines" "…and this round's entry carries this round's"

echo "# render: a ruling the guard recorded itself is told as the guard's, not triage's"
GREC=$(printf '%s' "$REC" | jq -c --arg why "no triage lane is declared on this anchor (check_set 'correctness'), so no review weighs what the round changed" \
  '.triage = {by: "guard", reopen: ["correctness"], add: [], dismiss: true, reason: $why, at: "t"}')
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$GREC" | jq -Rc .)")]"
out=$("$SUT" render --anchor AN1 --as comment)
has "$out" "Ruling: correctness runs again on the merged code, and the approval is lifted. Why: no triage lane is declared on this anchor (check_set 'correctness'), so no review weighs what the round changed." "the comment carries the guard's ruling and its reason"
hasnt "$out" "Triage:" "…crediting nothing to triage"
out=$("$SUT" render --anchor AN1 --as dismissal)
has "$out" "Needs you: check what bringing this branch current with main changed by hand (pushed head 0123456789ab)." "the dismissal note opens with what it needs from the operator"
has "$out" " No triage lane is declared on this anchor (check_set 'correctness')" "…and why, as a sentence of its own"
has "$out" "Your approval is lifted until you have checked it. Where to look: b.sh: pointed the new call at start." "…then the entries, judgment first, since no triage comment carries them"
hasnt "$out" "Triage:" "…crediting no ruling to triage"
hasnt "$out" "triage comment" "…and pointing at no triage comment, since none is posted"
eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "…in one paragraph"
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$GREC" | jq -c --arg r "$LONG" '.triage.reason = $r' | jq -Rc .)")]"
has "$("$SUT" render --anchor AN1 --as dismissal)" "… Your approval is lifted until you have checked it. Where to look:" "a long reason of the guard's is clipped before the ask's closing sentence too"

echo "# render: an anchor with no record is refused"
store "[$(anchorrow AN1)]"
"$SUT" render --anchor AN1 --as comment >/dev/null 2>&1; rc=$?
eq "$rc" "1" "it exits 1"
"$SUT" render --anchor AN1 --as ask >/dev/null 2>&1; rc=$?
eq "$rc" "1" "…the ask form too"
"$SUT" render --anchor AN1 --as visit >/dev/null 2>&1; rc=$?
eq "$rc" "2" "a form other than comment, dismissal or ask is a usage error"

# --- ask ---------------------------------------------------------------------------
echo "# ask: the question is recorded, and one visit composed from the audit asks it on the anchor"
ENTRY=$(jq -nc '[{path: "docs/a.md", collided: "c", resolution: "kept both", check: "k", rating: "routine"}]')
store "[$(bead B2 ",\"conflict_audit\":$(printf '%s' "$ENTRY" | jq -Rc .)"), $(anchorrow AN1)]"
: > "$STUB_ESC_LOG"
out=$("$SUT" ask --bead B2 --path lib/retry.sh --collided "main deleted the retry loop; the branch extended it" \
  --question "keep the retry loop with the branch's extension, or drop both?" 2>&1); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "visit filed on AN1 (bring-current-question.B2)" "…naming the visit's subject and key"
eq "$(meta B2 conflict_question | jq -r '.paths[0] + "|" + .question')" "lib/retry.sh|keep the retry loop with the branch's extension, or drop both?" "the question is recorded on the bead"
esc=$(cat "$STUB_ESC_LOG")
has "$esc" "--subject AN1 --key bring-current-question.B2" "the visit is filed on the anchor"
has "$esc" "PR#7 needs a decision before it can be brought current with main" "…titled by what it needs"
has "$esc" "Nothing was pushed" "…saying nothing was pushed"
has "$esc" "The question: keep the retry loop with the branch's extension, or drop both?" "…asking the question"
has "$esc" "What collided in \`lib/retry.sh\`: main deleted the retry loop; the branch extended it." "…saying what collided"
has "$esc" "- \`docs/a.md\`, routine. Decided: kept both." "…carrying the entries so far"
has "$esc" "Record the answer in the notes of B2 as you release it" "…and how the answer reaches the worker"

echo "# ask: the anchor resolves through the branch, or is the bead itself"
store "[$(bead B3 | jq -c 'del(.metadata.anchor_bead)'), $(anchorrow AN5)]"
: > "$STUB_ESC_LOG"
"$SUT" ask --bead B3 --path x --collided "c" --question "q" >/dev/null 2>&1
has "$(cat "$STUB_ESC_LOG")" "--subject AN5 " "a bead naming no anchor asks on its branch's anchor"
store "[$(anchorrow AN6 ",\"target\":\"main\"" | jq -c 'del(.metadata.merge_result) | .metadata.existing_pr = .metadata.pr_url')]"
: > "$STUB_ESC_LOG"
"$SUT" ask --bead AN6 --path x --collided "c" --question "q" >/dev/null 2>&1
has "$(cat "$STUB_ESC_LOG")" "--subject AN6 " "an anchor the refinery re-queued asks on itself"

echo "# ask: an empty question, a visit that does not land, or a question that does not read back exits 1"
store "[$(bead B4), $(anchorrow AN1)]"
: > "$STUB_ESC_LOG"
"$SUT" ask --bead B4 --path x --collided "c" --question " " >/dev/null 2>&1; rc=$?
eq "$rc" "1" "an empty question exits 1"
eq "$(cat "$STUB_ESC_LOG")" "" "…filing nothing"
STUB_ESC_RC=1 "$SUT" ask --bead B4 --path x --collided "c" --question "q" >/dev/null 2>&1; rc=$?
eq "$rc" "1" "a visit that does not land exits 1"
store "[$(bead B4), $(anchorrow AN1)]"
: > "$STUB_ESC_LOG"
STUB_UPDATE_FAIL="B4" "$SUT" ask --bead B4 --path x --collided "c" --question "q" >/dev/null 2>&1; rc=$?
eq "$rc" "1" "a question that does not read back exits 1"
eq "$(cat "$STUB_ESC_LOG")" "" "…before any visit is filed"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
