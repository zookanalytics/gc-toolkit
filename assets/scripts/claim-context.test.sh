#!/usr/bin/env bash
# Hermetic test for assets/scripts/claim-context.sh, the one read a session
# orients from after gc hook --claim.
#
# What it holds:
#   - a formula step's claim prints the step's gc.step_ref and instructions,
#     its workflow's formula and input convoy, and the work bead's title,
#     status, assignee, priority, type, metadata, notes and description, from
#     two store reads, the step and the convoy;
#   - the step's instructions print ahead of the workflow, and --no-step
#     leaves them out at no change in reads;
#   - a step whose record lacks its root, or carries it without metadata,
#     reads the root, one read more;
#   - a workflow with no input convoy, and a convoy that tracks no bead or more
#     than one, print no work bead and say why;
#   - a claimed bead in no workflow is the work bead, printed once with or
#     without --no-step, from one read;
#   - a claimed workflow root reads as one, with its convoy's work bead;
#   - an empty metadata, notes or description reads as (none);
#   - a `gc bd:` notice line ahead of the JSON is not a failed read;
#   - an unreadable claimed bead, root or convoy exits 1 and names the read to
#     make by hand, after what did read, and so does a read that answers with
#     another bead's record;
#   - a call with no bead, two beads or an unknown flag exits 2 and reads
#     nothing;
#   - the polecat claim contract runs this script by its pack path with no
#     flag, the form that prints the step's instructions, and names the flag
#     the script takes for a result that carries them.
#
# The harness's gc stub serves each bead from a JSON store and logs every call,
# which is how the reads are counted.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-claim-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/claim-context.sh"
SUT="$SD/claim-context.sh"

# cc <args...> — the script. Sets RC, OUT and ERR, READS to the ids of the
# beads this run read, space-separated in order, and OTHER to every gc call it
# made that was not such a read.
cc() {
  : > "$STUB_GC_LOG"
  RC=0
  OUT=$("$SUT" "$@" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
  READS=$(sed -n 's/^bd show \([^ ]*\) --json$/\1/p' "$STUB_GC_LOG" | tr '\n' ' ' | sed 's/ $//')
  OTHER=$(grep -v '^bd show [^ ]* --json$' "$STUB_GC_LOG" || true)
}
nreads() { printf '%s\n' "$READS" | wc -w | tr -d ' '; }
# before <text> <a> <b>: <a> appears in <text> ahead of <b>.
before() {
  local ia ib
  ia=$(printf '%s\n' "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1)
  ib=$(printf '%s\n' "$1" | grep -nF -- "$3" | head -1 | cut -d: -f1)
  [ -n "$ia" ] && [ -n "$ib" ] && [ "$ia" -lt "$ib" ]
}

# The work bead as a convoy's record carries it: whole, notes included, behind
# its tracks edge. bd prints no assignee for an unassigned bead.
WORK='{"id":"tk-work","title":"Fix the thing","status":"open","priority":1,"issue_type":"bug",
  "description":"DESC-MARKER: what to build","notes":"NOTES-MARKER: a ruling appended after filing",
  "metadata":{"branch":"polecat/tk-work","rejection_reason":"REJ-MARKER"}}'
ROOT_META='{"gc.kind":"workflow","gc.formula_name":"mol-polecat-work","gc.input_convoy_id":"tk-convoy"}'

# step <id> <root deps JSON array> — a claimed formula step under tk-root.
step() {
  jq -nc --arg id "$1" --argjson deps "$2" '
    {id: $id, title: "Implement the solution", status: "in_progress", issue_type: "task",
     description: "STEP-MARKER: the step instructions",
     metadata: {"gc.root_bead_id": "tk-root", "gc.step_ref": "mol-polecat-work.implement"},
     dependencies: ($deps + [{id: "tk-prev", dependency_type: "blocks", status: "closed", title: "Verify pre-flights"}])}'
}
ROOT_DEP=$(jq -nc --argjson m "$ROOT_META" '{id: "tk-root", dependency_type: "tracks", title: "mol-polecat-work", status: "in_progress", metadata: $m}')
ROOT_ROW=$(jq -nc --argjson m "$ROOT_META" '{id: "tk-root", title: "mol-polecat-work", status: "in_progress", issue_type: "task", metadata: $m}')
# convoy <id> <tracked records JSON array> — an input convoy and its edges.
convoy() {
  jq -nc --arg id "$1" --argjson t "$2" '
    {id: $id, title: "convoy", status: "open", issue_type: "convoy", metadata: {"gc.synthetic": "true"},
     dependencies: (($t | map(. + {dependency_type: "tracks"}))
                    + [{id: "tk-epic", dependency_type: "parent-child", status: "open", title: "an epic"}])}'
}
WORK_ROW=$(jq -c '.' <<<"$WORK")
BASE_STORE="$(step tk-step "[$ROOT_DEP]"),$ROOT_ROW,$(convoy tk-convoy "[$WORK]"),$WORK_ROW"

echo "# a formula step"
store "[$BASE_STORE]"
cc tk-step
eq "$RC" 0 "a step claim exits 0"
has "$OUT" "Claimed tk-step, step mol-polecat-work.implement (in_progress)." "…names the claimed bead, its gc.step_ref and status"
has "$OUT" "## Implement the solution (tk-step)" "…the step's title, the way a step_reminder prints it"
has "$OUT" "STEP-MARKER: the step instructions" "…and its description, the step's instructions"
if before "$OUT" "STEP-MARKER" "Workflow tk-root"; then ok "…ahead of the workflow"; else bad "…ahead of the workflow (got: $OUT)"; fi
has "$OUT" "Workflow tk-root runs mol-polecat-work over input convoy tk-convoy." "…its workflow, formula and input convoy"
has "$OUT" "Work bead tk-work: Fix the thing" "…the work bead and its title"
has "$OUT" "Status open, assignee none, priority P1, type bug." "…its status, assignee, priority and type"
has "$OUT" '"rejection_reason": "REJ-MARKER"' "…its metadata"
has "$OUT" "NOTES-MARKER: a ruling appended after filing" "…its notes"
has "$OUT" "DESC-MARKER: what to build" "…its description"
hasnt "$OUT" "tk-epic" "…and no edge of the convoy but its tracks edges"
eq "$READS" "tk-step tk-convoy" "…from two reads: the step, whose record carries its root, and the convoy"
eq "$OTHER" "" "…and no other gc call"

cc tk-step --no-step
eq "$RC" 0 "--no-step exits 0"
hasnt "$OUT" "Step instructions" "…and leaves out the step's instructions, which a step_reminder carries"
hasnt "$OUT" "STEP-MARKER" "…its description too"
has "$OUT" "Claimed tk-step, step mol-polecat-work.implement (in_progress)." "…still names the claimed bead"
has "$OUT" "NOTES-MARKER" "…and still prints the work bead's notes"
eq "$(nreads)" 2 "…from the same two reads"

echo "# a step whose record does not carry its root"
store "[$(step tk-step "[]"),$ROOT_ROW,$(convoy tk-convoy "[$WORK]"),$WORK_ROW]"
cc tk-step
eq "$RC" 0 "no root in the step's record: exit 0"
has "$OUT" "Workflow tk-root runs mol-polecat-work over input convoy tk-convoy." "…the root is read"
has "$OUT" "NOTES-MARKER" "…and the work bead found through it"
eq "$READS" "tk-step tk-root tk-convoy" "…one read more, for the root"
store "[$(step tk-step '[{"id":"tk-root","dependency_type":"tracks","title":"mol-polecat-work"}]'),$ROOT_ROW,$(convoy tk-convoy "[$WORK]"),$WORK_ROW]"
cc tk-step
eq "$RC|$(nreads)" "0|3" "a root edge that carries no metadata: the root is read too"
has "$OUT" "over input convoy tk-convoy." "…and its convoy found"

echo "# workflows with no single work bead"
store "[$(step tk-step "[$(jq -nc '{id: "tk-root", dependency_type: "tracks", metadata: {"gc.kind": "workflow", "gc.formula_name": "mol-feedback-distiller"}}')]")]"
cc tk-step
eq "$RC" 0 "a workflow with no input convoy: exit 0"
has "$OUT" "Workflow tk-root runs mol-feedback-distiller with no input convoy, so it has no work bead. The step's instructions are the plan." \
    "…says it has no work bead"
has "$OUT" "STEP-MARKER" "…and prints the step's instructions"
eq "$(nreads)" 1 "…from one read"
store "[$(step tk-step "[$ROOT_DEP]"),$(convoy tk-convoy '[{"id":"tk-a","title":"A","status":"open"},{"id":"tk-b","title":"B","status":"closed"}]')]"
cc tk-step
eq "$RC" 0 "a convoy that tracks two beads: exit 0"
has "$OUT" "Input convoy tk-convoy tracks more than one bead, so this workflow has no single work bead:" "…says so"
has "$OUT" "  tk-a (open): A" "…and lists the first"
has "$OUT" "  tk-b (closed): B" "…and the second"
hasnt "$OUT" "Work bead" "…with no work bead section"
store "[$(step tk-step "[$ROOT_DEP]"),$(convoy tk-convoy '[]')]"
cc tk-step
eq "$RC" 0 "a convoy that tracks nothing: exit 0"
has "$OUT" "Input convoy tk-convoy tracks no bead, so this workflow has no work bead." "…says so"

echo "# a claimed bead in no workflow, and a claimed root"
store "[$BASE_STORE]"
cc tk-work
eq "$RC" 0 "a bead in no workflow: exit 0"
has "$OUT" "Claimed tk-work (open). It belongs to no workflow, so it is the work bead." "…is the work bead"
has "$OUT" "NOTES-MARKER" "…with its notes"
eq "$(printf '%s\n' "$OUT" | grep -c 'DESC-MARKER')" 1 "…and its description once"
hasnt "$OUT" "Step instructions" "…as the work bead, not as step instructions"
eq "$READS" "tk-work" "…from one read"
NO_FLAG="$OUT"
cc tk-work --no-step
eq "$RC|$OUT" "0|$NO_FLAG" "…and --no-step prints it the same"
cc tk-root
eq "$RC" 0 "a claimed workflow root: exit 0"
has "$OUT" "Claimed tk-root (in_progress), the root of a workflow, whose work runs as its step beads." "…reads as a root"
has "$OUT" "Work bead tk-work: Fix the thing" "…with its convoy's work bead"
hasnt "$OUT" "Step instructions" "…and no step instructions, since a root's work is its steps"
eq "$(nreads)" 2 "…from two reads"

echo "# empty fields and a notice line"
store "[$(step tk-step "[$ROOT_DEP]"),$(convoy tk-convoy '[{"id":"tk-bare","title":"Title only","status":"open"}]')]"
cc tk-step
has "$OUT" "Status open, assignee none, priority none, type none." "a record with no assignee, priority or type reads none for each"
has "$OUT" "Metadata:
(none)" "…no metadata reads (none)"
has "$OUT" "Notes:
(none)" "…no notes read (none)"
has "$OUT" "Description:
(none)" "…no description reads (none)"
store "[$BASE_STORE]"
STUB_SHOW_NOTICE=gc-toolkit cc tk-step
eq "$RC" 0 "a gc bd: notice line ahead of each read's JSON: exit 0"
has "$OUT" "NOTES-MARKER" "…and the work bead still reads"

echo "# reads that fail"
store "[$BASE_STORE]"
cc tk-missing
eq "$RC|$OUT" "1|" "an unreadable claimed bead: exit 1, and nothing printed"
has "$ERR" "tk-missing did not read. Read it with: gc bd show tk-missing --json" "…and the read to make is named"
STUB_SHOW_FAIL=1 cc tk-step
eq "$RC" 1 "a store that refuses the read: exit 1"
store "[$(jq -nc '{id: "tk-step", status: "open", metadata: {"gc.root_bead_id": "tk-gone", "gc.step_ref": "mol-x.a"}}')]"
cc tk-step
eq "$RC" 1 "an unreadable root: exit 1"
has "$OUT" "Claimed tk-step, step mol-x.a (open)." "…after printing the claimed bead"
has "$OUT" "Workflow tk-gone did not read. Read it with: gc bd show tk-gone --json" "…and naming the read to make"
store "[$(step tk-step "[$ROOT_DEP]")]"
cc tk-step
eq "$RC" 1 "an unreadable convoy: exit 1"
has "$OUT" "Workflow tk-root runs mol-polecat-work over input convoy tk-convoy." "…after printing the workflow"
has "$OUT" "Input convoy tk-convoy did not read. Read it with: gc bd show tk-convoy --json" "…and naming the read to make"
# SWAP=<asked>=<served>: a wrapper in front of the stub answers a read of one
# bead with another bead's record.
mkdir -p "$TMP/swap"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/swap/gc" <<WRAP
if [ "\${1:-} \${2:-}" = "bd show" ] && [ "\${3:-}" = "\${SWAP%%=*}" ]; then
  shift 3; exec "$BIN/gc" bd show "\${SWAP#*=}" "\$@"
fi
exec "$BIN/gc" "\$@"
WRAP
chmod +x "$TMP/swap/gc"
store "[$BASE_STORE]"
PATH="$TMP/swap:$PATH" SWAP=tk-convoy=tk-work cc tk-step
eq "$RC" 1 "a convoy read that answers with another bead: exit 1"
has "$OUT" "Input convoy tk-convoy did not read." "…reads as no convoy"
hasnt "$OUT" "Work bead" "…and prints no work bead from the wrong record"

echo "# usage"
cc
eq "$RC|$(nreads)" "2|0" "no bead: exit 2, and nothing read"
cc tk-step tk-other
eq "$RC|$(nreads)" "2|0" "two beads: exit 2, and nothing read"
cc tk-step --verbose
eq "$RC|$(nreads)" "2|0" "an unknown flag: exit 2, and nothing read"
cc --help
eq "$RC|$(nreads)" "0|0" "--help: exit 0, and nothing read"

echo "# the claim contract that runs it"
DOCTRINE="$ROOT_DIR/template-fragments/polecat-doctrine.template.md"
CALL=$(grep -F 'assets/scripts/claim-context.sh' "$DOCTRINE" | grep -v '^#' | head -1)
eq "$CALL" '"{{ .ConfigDir }}/assets/scripts/claim-context.sh" <bead_id>' \
   "polecat-doctrine runs the script by the pack's path on the claim's bead_id, with no flag, so a claimed result's read prints the step"
has "$(cat "$DOCTRINE")" "add \`--no-step\`" "…and names --no-step for a result that carries a step_reminder"
for P in polecat polecat-codex; do
  has "$(cat "$ROOT_DIR/agents/$P/prompt.template.md")" '{{ template "polecat-doctrine" . }}' "the $P prompt carries that contract"
done

echo
echo "claim-context.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
