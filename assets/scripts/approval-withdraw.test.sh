#!/usr/bin/env bash
# Hermetic test for assets/scripts/approval-withdraw.sh, which dismisses the
# approvals on an anchor's PR when the validator rules a fresh whole-diff review
# warranted, and for the mol-validate block that runs it.
#
# approval-withdraw.sh, with gc and gh stubbed:
#   every outside approval not yet dismissed is dismissed: an account's older
#   approval, its newer one, and one behind a later CHANGES_REQUESTED, never the
#   CHANGES_REQUESTED itself, the city's own approval or a dismissed review; the
#   judgment is noted on the anchor and the review ids stamped on the pass
#   before the first dismissal, and a note or stamp that does not land
#   dismisses nothing; nobody is re-requested; the message opens with the
#   reason; a PR with no approval standing, and an anchor with no PR, write
#   nothing; an approval carrying an inline comment above the anchor's routing
#   marks waits, recording nothing, until the feedback loop has read it; a
#   retry dismisses only the recorded reviews still APPROVED, never an
#   approval given after them, and notes nothing twice; a dismissal that fails
#   exits 1 with the set recorded; unreadable reviews, an unresolved login, a
#   pr_url naming another PR, a malformed stamp and bad usage dismiss nothing.
# the mol-validate block (formulas/mol-validate.toml, rule-convergence), run
# verbatim against stub scripts:
#   a reviewer's batch supersedes its lane and a human batch every lane, and
#   either then withdraws the approvals with the same reason; a supersede that
#   fails withdraws nothing, and a withdrawal that fails fails the block; no
#   other place in the formula runs the withdrawal, so a converged batch keeps
#   its approval.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-approval-withdraw-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/approval-withdraw.sh"
SUT="$SD/approval-withdraw.sh"

NUM=7
PURL="https://github.com/zook/gc-toolkit/pull/$NUM"
REASON="The fix rewrites how merge.sh reads approvals"
anchorrow() { # [pr-metadata]
  printf '{"id":"AN1","status":"open","assignee":"","notes":"","title":"the PR","metadata":{"merge_result":"pull_request","check_set":"correctness"%s}}' \
    "${1-,\"pr_number\":\"$NUM\",\"pr_url\":\"$PURL\"}"
}
passrow() { # [extra-metadata]
  printf '{"id":"VP1","status":"in_progress","assignee":"validator","notes":"","title":"Validate PR#%s","metadata":{"task_kind":"validation","anchor_bead":"AN1","check_name":"correctness","reviewed_oid":"abc123"%s}}' \
    "$NUM" "${1:-}"
}
rv() { # id login state day
  printf '{"id":%s,"user":{"login":"%s"},"state":"%s","body":"","commit_id":"c%s","submitted_at":"2026-10-%02dT00:00:00Z"}' \
    "$1" "$2" "$3" "$1" "$4"
}
reviews() { printf '[%s]' "$1" > "$GH_DIR/reviews_$NUM.json"; }
fresh() { : > "$STUB_GH_LOG"; : > "$STUB_GC_LOG"; }
withdraw() { "$SUT" --pass VP1 --reason "$REASON" 2>&1; }
ghlog() { cat "$STUB_GH_LOG"; }

# The operator approved twice, at an older head and a newer one; a second
# account approved; a third approved and then requested changes. The city's own
# approval and an already-dismissed review stand beside them.
MIXED="$(rv 501 human1 APPROVED 1),$(rv 502 human2 APPROVED 2),$(rv 503 gc-city-bot APPROVED 2),$(rv 504 human1 APPROVED 3),$(rv 505 human3 APPROVED 3),$(rv 506 human3 CHANGES_REQUESTED 4),$(rv 507 human2 DISMISSED 4)"

echo "# every outside approval not yet dismissed is dismissed"
store "[$(anchorrow), $(passrow)]"
reviews "$MIXED"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "it exits 0"
has "$(ghlog)" "DISMISS repos/zook/gc-toolkit/pulls/$NUM/reviews/501/dismissals" "the operator's older approval is dismissed"
has "$(ghlog)" "DISMISS repos/zook/gc-toolkit/pulls/$NUM/reviews/504/dismissals" "…and their newer one"
has "$(ghlog)" "DISMISS repos/zook/gc-toolkit/pulls/$NUM/reviews/502/dismissals" "another account's approval is dismissed"
has "$(ghlog)" "DISMISS repos/zook/gc-toolkit/pulls/$NUM/reviews/505/dismissals" "an approval behind its author's later CHANGES_REQUESTED is dismissed"
hasnt "$(ghlog)" "reviews/506/dismissals" "the CHANGES_REQUESTED is left alone"
hasnt "$(ghlog)" "reviews/503/dismissals" "the city's own approval is left alone"
hasnt "$(ghlog)" "reviews/507/dismissals" "a review already dismissed is not dismissed again"
hasnt "$(ghlog)" "REREQUEST" "nobody is re-requested: the change is not pushed yet"
has "$(ghlog)" "message=$REASON. The validator ruled that this change needs a fresh whole-diff review, so this approval does not cover the code that will land." \
   "the message opens with the reason, punctuated, and says why the approval no longer covers the PR"
eq "$(meta VP1 approval_dismissed)" "501,502,504,505" "the dismissed reviews are recorded on the pass"
has "$(notes AN1)" "Validation pass VP1 ruled that a fresh whole-diff review is warranted, so the approvals from human1, human2 and human3 on PR#$NUM (reviews 501,502,504,505) are dismissed: $REASON." \
   "the judgment is noted on the anchor"
has "$out" "dismissed the approvals from human1, human2 and human3 (reviews 501,502,504,505)" "the outcome is reported"

echo "# a retry finishes the recorded set and dismisses nothing given after it"
store "[$(anchorrow), $(passrow ',"approval_dismissed":"501,504"')]"
reviews "$(rv 501 human1 DISMISSED 1),$(rv 504 human1 APPROVED 3),$(rv 508 human1 APPROVED 5)"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "it exits 0"
has "$(ghlog)" "reviews/504/dismissals" "the recorded approval still standing is dismissed"
hasnt "$(ghlog)" "reviews/501/dismissals" "…the one already dismissed is not"
hasnt "$(ghlog)" "reviews/508/dismissals" "…and an approval given after the withdrawal stands"
hasnt "$(cat "$STUB_GC_LOG")" "--append-notes" "nothing is noted twice"
eq "$(meta VP1 approval_dismissed)" "501,504" "the recorded set is unchanged"
reviews "$(rv 501 human1 DISMISSED 1),$(rv 504 human1 DISMISSED 3),$(rv 508 human1 APPROVED 5)"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "once the recorded set reads dismissed, a retry exits 0"
has "$out" "reads dismissed" "…saying so"
hasnt "$(ghlog)" "DISMISS" "…and dismisses nothing"

echo "# one approval: singular wording, and a numeric id reads back"
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 501 human1 APPROVED 1)"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(jq -r '.[] | select(.id == "VP1") | .metadata.approval_dismissed | type' "$STUB_STORE")" "number" "the store keeps a lone id as a number"
eq "$(meta VP1 approval_dismissed)" "501" "…and the stamp still reads back"
has "$(notes AN1)" "so the approval from human1 on PR#$NUM (review 501) is dismissed" "the note is singular"
has "$(ghlog)" "reviews/501/dismissals" "…and the approval is dismissed"

echo "# a PR with no approval standing, or no PR at all, writes nothing"
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 503 gc-city-bot APPROVED 1),$(rv 506 human3 CHANGES_REQUESTED 2),$(rv 509 human2 COMMENTED 2),$(rv 507 human2 DISMISSED 3)"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "no approval standing exits 0"
has "$out" "no approval stands on PR#$NUM" "…saying so"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
eq "$(meta VP1 approval_dismissed)" "<absent>" "…stamping nothing on the pass"
eq "$(notes AN1)" "" "…and noting nothing on the anchor"
store "[$(anchorrow ''), $(passrow)]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "an anchor with no PR exits 0"
has "$out" "has no pull request" "…saying so"
eq "$(ghlog)" "" "…without reading GitHub"

echo "# the record lands before any dismissal, or nothing is dismissed"
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 501 human1 APPROVED 1)"
fresh
out=$(STUB_UPDATE_FAIL="AN1" withdraw); rc=$?
eq "$rc" "1" "a note the anchor refuses exits 1"
hasnt "$(ghlog)" "DISMISS" "…and dismisses nothing"
eq "$(meta VP1 approval_dismissed)" "<absent>" "…and stamps nothing"
store "[$(anchorrow), $(passrow)]"
fresh
out=$(STUB_DROP_KEYS="VP1:approval_dismissed" withdraw); rc=$?
eq "$rc" "1" "a stamp that does not read back exits 1"
has "$out" "did not read back" "…saying so"
hasnt "$(ghlog)" "DISMISS" "…and dismisses nothing"

echo "# an approval carrying an inline comment the feedback loop has not routed waits"
# pr-facts.sh reads a dismissal as retiring the comments under the review, so a
# comment above both routing marks would never route once its review is gone.
cmt() { # id review-id login
  printf '{"id":%s,"pull_request_review_id":%s,"user":{"login":"%s"},"body":"rename this","path":"a.sh","line":1}' "$1" "$2" "$3"
}
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 501 human1 APPROVED 1),$(rv 502 human2 APPROVED 2)"
printf '[%s]' "$(cmt 901 501 human1),$(cmt 902 777 human9)" > "$GH_DIR/comments_$NUM.json"
fresh
out=$(withdraw); rc=$?
eq "$rc" "1" "an inline comment above both marks exits 1"
has "$out" "has not routed (comment 901)" "…naming that comment, and not one under a review it leaves alone"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
eq "$(meta VP1 approval_dismissed)" "<absent>" "…recording nothing on the pass"
eq "$(notes AN1)" "" "…and noting nothing on the anchor"
store "[$(anchorrow ",\"pr_number\":\"$NUM\",\"pr_url\":\"$PURL\",\"pr_comment_watermark\":\"901\""), $(passrow)]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "once the watermark has routed it, the withdrawal goes ahead"
has "$(ghlog)" "reviews/501/dismissals" "…and dismisses the approval that carried it"
store "[$(anchorrow ",\"pr_number\":\"$NUM\",\"pr_url\":\"$PURL\",\"pr_comment_watermark\":\"800\",\"pr_comment_answered\":\"901\""), $(passrow)]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "a comment its thread answered past the watermark lets it go ahead too"
mkdir -p "$TMP/shim"
cat > "$TMP/shim/gh" <<SHIM
#!/usr/bin/env bash
case " \$* " in *"/pulls/$NUM/comments"*) exit 1 ;; esac
exec "$BIN/gh" "\$@"
SHIM
chmod +x "$TMP/shim/gh"
store "[$(anchorrow), $(passrow)]"
fresh
out=$(PATH="$TMP/shim:$PATH" withdraw); rc=$?
eq "$rc" "1" "inline comments that cannot be read exit 1"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
rm -f "$GH_DIR/comments_$NUM.json"

echo "# a dismissal that fails exits 1, and the retry finishes it"
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 501 human1 APPROVED 1),$(rv 502 human2 APPROVED 2)"
fresh
out=$(STUB_DISMISS_RC=1 withdraw); rc=$?
eq "$rc" "1" "it exits 1 so the caller retries"
has "$out" "could not dismiss human1 (review 501), human2 (review 502)" "…naming what stands"
eq "$(meta VP1 approval_dismissed)" "501,502" "…with the set recorded"
fresh
out=$(withdraw); rc=$?
eq "$rc" "0" "the retry exits 0"
has "$(ghlog)" "reviews/501/dismissals" "…dismissing the first recorded approval"
has "$(ghlog)" "reviews/502/dismissals" "…and the second"
eq "$(notes AN1 | grep -o 'ruled that a fresh whole-diff review is warranted' | wc -l | tr -d ' ')" "1" "…and the anchor is noted once"

echo "# reads and arguments that fail dismiss nothing"
store "[$(anchorrow), $(passrow)]"
reviews "$(rv 501 human1 APPROVED 1)"
fresh
out=$(STUB_GH_LIST_RC=1 withdraw); rc=$?
eq "$rc" "1" "unreadable reviews exit 1"
eq "$(notes AN1)" "" "…noting nothing"
fresh
out=$(STUB_SELF_LOGIN="" withdraw); rc=$?
eq "$rc" "1" "an unresolved acting login exits 1"
has "$out" "the acting login is unresolved" "…and says so"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
store "[$(anchorrow ",\"pr_number\":\"$NUM\",\"pr_url\":\"https://github.com/zook/gc-toolkit/pull/8\""), $(passrow)]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "1" "a pr_url naming another PR exits 1"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
store "[$(anchorrow), $(passrow ',"approval_dismissed":"501;502"')]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "1" "a stamp that is not a list of review ids exits 1"
hasnt "$(ghlog)" "DISMISS" "…dismissing nothing"
store "[$(anchorrow)]"
fresh
out=$(withdraw); rc=$?
eq "$rc" "1" "an unreadable pass exits 1"
store "[$(anchorrow), $(passrow | jq -c 'del(.metadata.anchor_bead)')]"
out=$(withdraw); rc=$?
eq "$rc" "2" "a pass naming no anchor exits 2"
out=$("$SUT" --pass VP1 2>&1); rc=$?
eq "$rc" "2" "a missing --reason exits 2"
out=$("$SUT" --reason "$REASON" 2>&1); rc=$?
eq "$rc" "2" "a missing --pass exits 2"

echo "# metadata-key drift against lifecycle.toml"
# The registry is the exhaustive declaration of the state the pack writes, so a
# key this script stamps that nothing registers is state no audit accounts for.
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$ROOT/lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
WRITTEN=$(grep -hoE -- '--set(-metadata|-dated)? "?[A-Za-z_][A-Za-z0-9_.]*=' "$HERE/approval-withdraw.sh" \
  | sed -E 's/^--set(-metadata|-dated)? "?//; s/=$//' | sort -u)
eq "$WRITTEN" "approval_dismissed" "the extraction reads the one key the script writes"
UNREGISTERED=$(printf '%s\n' "$WRITTEN" \
  | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every metadata key approval-withdraw.sh writes is registered in lifecycle.toml"

echo "# the mol-validate block runs the withdrawal on every batch that has not converged"
TOML="$ROOT/formulas/mol-validate.toml"
BLOCK="$TMP/not-converged.sh"
awk '/# >>> validate-not-converged$/ {f=1; next} /# <<< validate-not-converged$/ {f=0} f' "$TOML" \
  | sed 's/^REASON="<.*>"$/REASON="the reason"/' > "$BLOCK"
[ -s "$BLOCK" ] && ok "the block is extracted from the formula" || bad "the block is not extracted from the formula"
eq "$(grep -c '^# >>> validate-not-converged$' "$TOML")" "1" "…from exactly one region"
grep -q '^REASON="the reason"$' "$BLOCK" && ok "…and its REASON placeholder is the one line the validator fills in" \
  || bad "the block's REASON placeholder was not found"
case "$(cat "$BLOCK")" in
  *\\*) bad "the block carries a backslash, which a TOML basic string would mangle" ;;
  *)    ok "the block carries no backslash" ;;
esac
bash -n "$BLOCK" && ok "…and is valid bash" || bad "the block fails bash -n"
STUBS="$TMP/stub-pack"
mkdir -p "$STUBS"
for s in review-outcome approval-withdraw; do
  cat > "$STUBS/$s.sh" <<STUB
#!/usr/bin/env bash
printf '%s %s\n' "$s" "\$*" >> "\$BLOCK_LOG"
exit "\${${s//-/_}_rc:-0}"
STUB
  chmod +x "$STUBS/$s.sh"
done
runblock() { # <lane> — prints "<rc>|<log>"
  : > "$TMP/block.log"
  local rc=0
  BLOCK_LOG="$TMP/block.log" SCRIPTS="$STUBS" LANE="$1" ANCHOR=AN1 VALIDATION_PASS=VP1 \
  review_outcome_rc="${review_outcome_rc:-0}" approval_withdraw_rc="${approval_withdraw_rc:-0}" \
    bash "$BLOCK" >/dev/null 2>&1 || rc=$?
  printf '%s|%s' "$rc" "$(tr '\n' ';' < "$TMP/block.log")"
}
eq "$(runblock correctness)" \
   "0|review-outcome supersede-lane --anchor AN1 --lane correctness --reason the reason;approval-withdraw --pass VP1 --reason the reason;" \
   "a reviewer's batch supersedes its lane, then withdraws the approvals with the same reason"
eq "$(runblock human)" \
   "0|review-outcome supersede-anchor --anchor AN1 --reason the reason;approval-withdraw --pass VP1 --reason the reason;" \
   "a human batch supersedes every lane, then withdraws the approvals"
eq "$(review_outcome_rc=2 runblock correctness)" "2|review-outcome supersede-lane --anchor AN1 --lane correctness --reason the reason;" \
   "a supersede that fails withdraws nothing and fails the block"
eq "$(approval_withdraw_rc=1 runblock human)" \
   "1|review-outcome supersede-anchor --anchor AN1 --reason the reason;approval-withdraw --pass VP1 --reason the reason;" \
   "a withdrawal that fails fails the block"
STEP=$(awk '/^id = "rule-convergence"$/ {f=1} f && /^\[\[steps\]\]$/ {exit} f' "$TOML")
has "$STEP" '[ -x "$c/assets/scripts/approval-withdraw.sh" ]' "the step resolves its scripts only where the withdrawal is present"
eq "$(grep -c 'approval-withdraw.sh" --pass' "$TOML")" "1" "the formula runs the withdrawal in one place"
eq "$(grep -c 'approval-withdraw.sh" --pass' "$BLOCK")" "1" "…the not-converged block, so a converged batch keeps its approval"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
