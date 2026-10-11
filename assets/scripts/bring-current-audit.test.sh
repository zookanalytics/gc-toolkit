#!/usr/bin/env bash
# Hermetic test for assets/scripts/bring-current-audit.sh: the worker's audit of
# a bring-current round, and the messages composed from a round's record.
#
# add: records an entry and reads it back; replaces the entry for the same path
#   and keeps the others; flattens control characters to one line; refuses an
#   unknown rating, an empty field, an unreadable bead, and a write that does not
#   read back, recording nothing.
# show: prints a bead's entries and question, and an anchor's record.
# render: composes the comment, the dismissal note and the re-ask visit from the
#   anchor's record (the headline counts, judgment entries first, each entry's
#   collision, decision and check beside the guard's evidence, triage's ruling,
#   the generated renders); refuses an anchor with no record.
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
    {path: "docs/a.md", collided: "main added a FAQ; the branch added a usage section at the same spot", resolution: "kept both, the FAQ first", check: "the section order", rating: "routine"},
    {path: "b.sh", collided: "main renamed run to start; the branch added a call to run", resolution: "pointed the new call at start", check: "the new call site in b.sh", rating: "judgment"},
    {path: "c.sh", collided: "the rename broke a caller the merge did not conflict on", resolution: "renamed the caller too", check: "c.sh callers", rating: "judgment"}],
  triage: {review: "RV1", reopen: ["correctness"], add: ["arch"], dismiss: true, reason: "the rename changes what the new call does", at: "t"}}')
store "[$(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$REC" | jq -Rc .)")]"

echo "# render --as comment: the round's account, as triage's verdict posts it"
out=$("$SUT" render --anchor AN1 --as comment); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "**Bringing this branch current with main**" "a heading"
has "$out" "needed 2 conflicted files resolved by hand, and 1 edit beyond what git merges on its own" "a headline that counts what the round needed"
has "$out" "The worker rated 1 routine and 2 judgment (\`b.sh\` and \`c.sh\`)" "…and how the worker rated it, naming the judgment calls"
has "$out" "**Triage:** arch and correctness run again on the merged code, and the approval given before the round no longer covers what would land, so the PR needs a fresh human review. Why: the rename changes what the new call does." "triage's ruling and its reason"
has "$out" "- \`b.sh\`, judgment. Collided: main renamed run to start; the branch added a call to run. Decided: pointed the new call at start. Check: the new call site in b.sh. Git: conflicted where the merge base had lines" "each entry: collision, decision, check, and the guard's evidence"
first=$(printf '%s\n' "$out" | grep -n '^- `' | head -1)
has "$first" "judgment" "judgment entries come first"
has "$out" "Generated files the merge re-rendered, which need no entry: \`generated/x.md\`." "the generated renders are named"

echo "# render --as dismissal: one paragraph a dismissed approver reads"
out=$("$SUT" render --anchor AN1 --as dismissal)
has "$out" "Bringing this branch current with main (pushed head 0123456789ab) took judgment this approval did not see." "it opens with what happened"
has "$out" "b.sh: pointed the new call at start." "…names each decision"
has "$out" "Triage: the rename changes what the new call does." "…carries triage's reason"
eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "…in one paragraph"

echo "# render --as visit: the re-ask, title line first"
out=$("$SUT" render --anchor AN1 --as visit --logins "human1")
eq "$(printf '%s\n' "$out" | head -1)" "PR#7 approval dismissed: triage ruled that bringing it current took judgment" "the title names the PR and what happened"
has "$out" "changed code the approval from human1 did not see" "…the body names the approver"
has "$out" "File by file:" "…lists the entries"
has "$out" "Your call: review the change on the PR and approve again to let it land, or say what to change." "…and ends with the operator's call"

echo "# render: an anchor with no record is refused"
store "[$(anchorrow AN1)]"
"$SUT" render --anchor AN1 --as comment >/dev/null 2>&1; rc=$?
eq "$rc" "1" "it exits 1"

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
