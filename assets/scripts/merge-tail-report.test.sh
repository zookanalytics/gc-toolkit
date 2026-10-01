#!/usr/bin/env bash
# Hermetic test for assets/scripts/merge-tail-report.sh — the dropped-merge-tail
# reporter refinery-reconcile runs at each pass's start. Covers:
#   - no marker / a `decided` or `held` marker = no finding (the prior pass made
#     its merge decision);
#   - a `started` or `reached` marker with gating anchors still open = exactly one
#     patrol-finding, keyed per rig, priority 1, naming the anchors, with the
#     phase-specific wording (before vs inside the merge arm);
#   - a `reached` marker with an empty tail = no finding (the drop self-cleared);
#   - a failed anchor read = no finding (fails closed: a broken read is not proof
#     the tail is empty);
#   - an unrecognized/empty phase = no finding;
#   - an absent patrol-finding.sh, or one that fails = no crash;
#   - the exit is always 0, so the reporter never fails the pass it reports on.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-merge-tail-report-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# Copy the SUT (and bd-lib.sh beside it) into a private dir so its sibling source
# resolves there, and the harness gc stub on PATH serves the store reads.
SUT="$TMP/sut"
mk_sut_dir "$SUT" "$HERE/merge-tail-report.sh"
REPORT="$SUT/merge-tail-report.sh"

MARKER="$TMP/merge-decision"
PF="$TMP/patrol-finding-stub.sh"
export PF_LOG="$TMP/pf.log"
export PF_COUNT="$TMP/pf.count"
# A patrol-finding stub. It records its argv space-joined (so a `has` sees each
# flag with its value) — but the --message carries newlines, so argv lines are
# not call boundaries; a separate one-token-per-call file counts invocations.
cat > "$PF" <<'PFS'
#!/usr/bin/env bash
printf 'x\n' >> "${PF_COUNT:?}"
printf '%s\n' "$*" >> "${PF_LOG:?}"
exit "${PF_RC:-0}"
PFS
chmod +x "$PF"

# Two open anchors carrying merge_result=pull_request, and one merged anchor that
# the enumeration must exclude.
ANCHORS='[
  {"id":"tk-aaa","status":"open","metadata":{"merge_result":"pull_request","pr_number":"882","pr_posture":"approved"}},
  {"id":"tk-bbb","status":"open","metadata":{"merge_result":"pull_request","pr_number":"891"}},
  {"id":"tk-ccc","status":"closed","metadata":{"merge_result":"merged","pr_number":"870"}}
]'

write_marker() { printf '%s\t%s\t%s\n' "$1" "2026-09-30T12:00:00Z" "abc123def456" > "$MARKER"; }
run() { GC_PATROL_FINDING_TOOL="$PF" "$REPORT" --marker "$MARKER" --rig myrig; }

echo "# a missing marker is the first pass — nothing to judge, nothing filed"
rm -f "$MARKER"; : > "$PF_LOG"; store "$ANCHORS"
run; rc=$?
eq "$rc" 0 "no marker exits 0"
[ -s "$PF_LOG" ] && bad "filed a finding with no marker" || ok "no marker files nothing"

echo "# a completed merge decision (decided / held) files nothing"
for ph in decided held; do
  write_marker "$ph"; : > "$PF_LOG"; store "$ANCHORS"
  run; rc=$?
  eq "$rc" 0 "a '$ph' marker exits 0"
  [ -s "$PF_LOG" ] && bad "a '$ph' marker filed a finding — a made decision is not a drop" || ok "a '$ph' marker files nothing"
done

echo "# an empty / unrecognized phase asserts nothing"
: > "$MARKER"; : > "$PF_LOG"; store "$ANCHORS"
run; rc=$?
eq "$rc" 0 "an empty marker exits 0"
[ -s "$PF_LOG" ] && bad "an empty marker filed a finding" || ok "an empty marker files nothing"
printf 'garbage\t\t\n' > "$MARKER"; : > "$PF_LOG"
run; rc=$?
[ -s "$PF_LOG" ] && bad "an unrecognized phase filed a finding" || ok "an unrecognized phase files nothing"

echo "# a pass killed before the merge arm ('started') with anchors open files one finding"
write_marker started; : > "$PF_LOG"; : > "$PF_COUNT"; store "$ANCHORS"
run; rc=$?
eq "$rc" 0 "a 'started' drop exits 0"
pf=$(cat "$PF_LOG")
eq "$(wc -l < "$PF_COUNT" | tr -d ' ')" "1" "exactly one patrol-finding was filed"
has "$pf" "--key reconcile-merge-tail-dropped-myrig" "…keyed per rig so recurrence dedups to one bead"
has "$pf" "--priority 1" "…at priority 1 (nothing is landing)"
has "$pf" "--rig myrig" "…in the rig's store"
has "$pf" "--scope refinery-findings" "…scoped to the refinery"
has "$pf" "--type bug" "…as a bug"
has "$pf" "killed before it reached the merge arm" "…with the before-arm wording"
has "$pf" "2 approved-candidate anchor(s)" "…counting the open gating anchors"
has "$pf" "tk-aaa" "…naming the first anchor"
has "$pf" "PR#882" "…with its PR number"
has "$pf" "tk-bbb" "…naming the second anchor"
has "$pf" "abc123def456" "…with the head the pass would have landed on"
has "$pf" "2026-09-30T12:00:00Z" "…and the dropped pass's timestamp"
hasnt "$pf" "tk-ccc" "…and never the merged anchor (merge_result != pull_request)"

echo "# a pass killed inside the merge arm ('reached') names that phase"
write_marker reached; : > "$PF_LOG"; store "$ANCHORS"
run; rc=$?
eq "$rc" 0 "a 'reached' drop exits 0"
has "$(cat "$PF_LOG")" "killed inside the merge arm" "…with the inside-arm wording"

echo "# a drop whose tail already landed files nothing (self-clearing)"
write_marker reached; : > "$PF_LOG"; store '[]'
run; rc=$?
eq "$rc" 0 "an empty tail exits 0"
[ -s "$PF_LOG" ] && bad "filed a finding with no open gating anchors" || ok "an empty tail files nothing"

echo "# a failed anchor read files nothing (fails closed)"
write_marker reached; : > "$PF_LOG"; store "$ANCHORS"
STUB_LIST_FAIL=1 run; rc=$?
eq "$rc" 0 "a failed read exits 0"
[ -s "$PF_LOG" ] && bad "filed on a failed read — a broken read is not proof the tail is empty" || ok "a failed read files nothing"

echo "# patrol-finding failing or absent never fails the reporter"
write_marker reached; : > "$PF_LOG"; store "$ANCHORS"
PF_RC=1 run; rc=$?
eq "$rc" 0 "a patrol-finding that fails still exits 0"
out=$(write_marker reached; store "$ANCHORS"; GC_PATROL_FINDING_TOOL="$TMP/nope.sh" "$REPORT" --marker "$MARKER" --rig myrig 2>&1); rc=$?
eq "$rc" 0 "an absent patrol-finding.sh still exits 0"
has "$out" "went unrecorded" "…and says the drop went unrecorded"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
