#!/usr/bin/env bash
# Hermetic test for assets/scripts/migrate-lane-states.sh.
# Covers: dry-run reports and writes nothing; green@/fixable@ rewrite to bare
# lane states (including a multi-gate check_set); a park clears the legacy
# marker and writes merge_hold=signoff_cap + signoff_cap=<gate> (never plain
# merge_hold=true), with escalate.sh invoked with GC_RIG pinned to the rig
# being iterated (never an inherited GC_RIG) and a rig-qualified --pool; a
# park write that does not land leaves the legacy marker standing for a
# retry, with the visit already filed; a second --apply run is a true no-op
# once everything has landed; a listing that is unparseable (non-array, or a
# non-zero exit) is refused, never read as "nothing to migrate"; a check.<g>
# key outside the anchor's check_set is left alone and reported, not counted
# as attention; and a city-scope (no rig name) park is refused rather than
# guessed at, since no rig-qualified pool exists to route its visit through.
# No live city, Dolt, network, gc, bd, gh or escalate.sh — stubs from
# test-harness.sh plus a thin `gc rig list` / `gc bd list` shim (the
# cutover-2026-08.test.sh pattern) and a recording escalate.sh stub.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/migrate-lane-states.sh"
SUT="$SD/migrate-lane-states.sh"

# escalate.sh resolves as a sibling of the SUT; a recorder there is what the
# park arm reaches. It logs the GC_RIG it was invoked under (the whole point
# of finding 2) plus every argument, and fails only for a subject named in
# STUB_ESCALATE_FAIL.
export STUB_ESCALATE_LOG="$TMP/escalate.log"
: > "$STUB_ESCALATE_LOG"
export STUB_ESCALATE_FAIL=""
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
{
  printf 'GC_RIG=%s ' "${GC_RIG-<unset>}"
  printf '%s\n' "$*"
} >> "${STUB_ESCALATE_LOG:?}"
subj=""
while [ $# -gt 0 ]; do
  case "$1" in --subject) subj="${2:-}"; shift 2 ;; *) shift ;; esac
done
case " ${STUB_ESCALATE_FAIL:-} " in *" $subj "*) exit 1 ;; esac
exit 0
ESC
chmod +x "$SD/escalate.sh"

# The SUT enumerates rigs via `gc rig list` (which the shared harness stub
# does not implement) and reaches each store with `gc bd ... --db <path>`;
# shim both onto the harness gc stub. STUB_BD_LIST_GARBAGE, when set, answers
# `gc bd list` with its literal content at rc 0 — the "logged a line, or
# printed {\"error\":...}, but still exited 0" shape no rc check alone catches.
mkdir -p "$TMP/bin2"
export STUB_RIGS="$TMP/rigs.json"
export STUB_BD_LIST_GARBAGE=""
cat > "$TMP/bin2/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "rig" ] && [ "\${2:-}" = "list" ]; then cat "\${STUB_RIGS:?}"; exit 0; fi
if [ "\${1:-}" = "bd" ] && [ "\${2:-}" = "list" ] && [ -n "\${STUB_BD_LIST_GARBAGE:-}" ]; then
  printf '%s\n' "\$STUB_BD_LIST_GARBAGE"; exit 0
fi
exec "$BIN/gc" "\$@"
SHIM
chmod +x "$TMP/bin2/gc"
export PATH="$TMP/bin2:$PATH"

mkdir -p "$TMP/rig"
printf '{"rigs":[{"name":"gc-toolkit","path":"%s","suspended":false}]}\n' "$TMP/rig" > "$STUB_RIGS"

anchor() { # id merge_result check_set extra-metadata-json-fragment(starts with a comma)
  printf '{"id":"%s","status":"open","assignee":"","title":"t-%s","metadata":{"merge_result":"%s","check_set":"%s"%s}}' \
    "$1" "$1" "$2" "$3" "${4:-}"
}

# Fixture: two verdicts that survive as lane states (one under a multi-gate
# check_set, proving the comma-split match), one park, and one legacy marker
# on a gate the anchor's check_set does not declare.
rows_json="$(anchor G1 pull_request codex ',"check.codex":"green@1111111111111111111111111111111111111111"'),\
$(anchor G2 pull_request "codex,lint" ',"check.lint":"green@2222222222222222222222222222222222222222"'),\
$(anchor F1 pull_request codex ',"check.codex":"fixable@3333333333333333333333333333333333333333"'),\
$(anchor P1 pull_request codex ',"check.codex":"exception@4444444444444444444444444444444444444444","blocked_reason":"legal review needed"'),\
$(anchor U1 pull_request codex ',"check.other":"exception@5555555555555555555555555555555555555555"')"
store "[$rows_json]"

echo "# dry-run (the default) reports everything and writes NOTHING"
cp "$STUB_STORE" "$TMP/store.before"
out=$("$SUT" --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "dry-run exits 0 (nothing here needs an operator yet)"
has "$out" "DRY-RUN" "dry-run announces itself"
has "$out" 'would rewrite check.codex="green@1111111111111111111111111111111111111111" -> green' "G1 dry-run line"
has "$out" 'would rewrite check.lint="green@2222222222222222222222222222222222222222" -> green' "G2 (multi-gate check_set) dry-run line"
has "$out" 'would rewrite check.codex="fixable@3333333333333333333333333333333333333333" -> fixing' "F1 dry-run line"
has "$out" 'would file visit [gate-park-migrated], then clear check.codex="exception@4444444444444444444444444444444444444444"' "P1 dry-run park line"
has "$out" 'check.other="exception@5555555555555555555555555555555555555555" names a gate outside check_set' "U1 reported as an undeclared marker"
cmp -s "$STUB_STORE" "$TMP/store.before"; eq "$?" 0 "dry-run left the store byte-identical"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "dry-run issued zero bd updates"
eq "$(wc -l < "$STUB_ESCALATE_LOG" | tr -d ' ')" "0" "dry-run filed no visits"

echo
echo "# --apply: lane-state rewrites, and a park writes merge_hold=signoff_cap"
echo "#   + signoff_cap=<gate>, with the visit filed under the ITERATED rig's"
echo "#   GC_RIG, never one inherited from the caller's shell"
: > "$STUB_GC_LOG"
export GC_RIG="some-other-rig"   # what a gc-helm shell or agent session exports
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "apply run exits 0"
eq "$(meta G1 check.codex)" "green" "G1 rewritten to green"
eq "$(meta G2 check.lint)" "green" "G2 (multi-gate check_set) rewritten to green"
eq "$(meta F1 check.codex)" "fixing" "F1 rewritten to fixing"
eq "$(meta P1 check.codex)" "<absent>" "P1 legacy marker cleared"
eq "$(meta P1 merge_hold)" "signoff_cap" "P1 parked under merge_hold=signoff_cap, never plain true"
eq "$(meta P1 signoff_cap)" "codex" "P1 signoff_cap names the gate that parked it"
eq "$(meta U1 check.other)" "exception@5555555555555555555555555555555555555555" "U1's undeclared marker is untouched"
esc="$(cat "$STUB_ESCALATE_LOG")"
has "$esc" "GC_RIG=gc-toolkit" "escalate.sh ran with GC_RIG pinned to the rig this pass is walking"
hasnt "$esc" "GC_RIG=some-other-rig" "…never the GC_RIG inherited from the caller's shell"
has "$esc" "--subject P1" "the visit names the anchor"
has "$esc" "--key gate-park-migrated" "the visit uses the migration's dedup key"
has "$esc" "--pool gc-toolkit/gc-toolkit.converse" "the visit routes through this rig's converse pool"
unset GC_RIG

echo
echo "# --apply again: a true no-op for everything that already landed"
cp "$STUB_STORE" "$TMP/store.after1"
: > "$STUB_GC_LOG"; : > "$STUB_ESCALATE_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "second apply exits 0"
eq "$(grep -c '^bd update' "$STUB_GC_LOG" || true)" "0" "second apply issued zero bd updates"
eq "$(wc -l < "$STUB_ESCALATE_LOG" | tr -d ' ')" "0" "second apply filed no new visits"
cmp -s "$STUB_STORE" "$TMP/store.after1"; eq "$?" 0 "second apply left the store byte-identical"
has "$out" "gc-toolkit: 0 lane state(s) migrated, 0 park(s) carried, 1 undeclared marker(s) left for gate-ensure, 0 needing an operator" "the undeclared marker is still reported, never counted as attention"

echo
echo "# --apply: a park write that does NOT land leaves the legacy marker"
echo "#   standing for a retry — the visit is filed BEFORE the write, so a"
echo "#   retry recovers instead of stranding a hold with nothing on the board"
tmpf=$(mktemp)
jq -c '. + [{"id":"P2","status":"open","assignee":"","title":"t-P2","metadata":{"merge_result":"pull_request","check_set":"codex","check.codex":"exception@6666666666666666666666666666666666666666","blocked_reason":"needs licensing review"}}]' \
  "$STUB_STORE" > "$tmpf" && mv "$tmpf" "$STUB_STORE"
export STUB_UPDATE_FAIL="P2"   # models a write that is lost/timed out: reports nothing, changes nothing
: > "$STUB_GC_LOG"; : > "$STUB_ESCALATE_LOG"
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "a park whose write does not land exits 1"
eq "$(meta P2 check.codex)" "exception@6666666666666666666666666666666666666666" "P2's legacy marker stands, untouched"
eq "$(meta P2 merge_hold)" "<absent>" "P2 is not parked"
eq "$(grep -c -- '--subject P2' "$STUB_ESCALATE_LOG" || true)" "1" "the visit was filed once even though the park did not land"
has "$out" "legacy marker left in place" "the failure is reported as recoverable, not a stuck hold"

echo "# …and a re-run recovers: the same row is picked up again and parks cleanly"
export STUB_UPDATE_FAIL=""
out=$("$SUT" --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "the retry exits 0"
eq "$(meta P2 check.codex)" "<absent>" "P2's legacy marker is cleared on retry"
eq "$(meta P2 merge_hold)" "signoff_cap" "P2 is parked on retry"
eq "$(meta P2 signoff_cap)" "codex" "P2 signoff_cap on retry"
eq "$(grep -c -- '--subject P2' "$STUB_ESCALATE_LOG" || true)" "2" "escalate.sh was asked again on retry (its own --key dedup keeps this from duplicating on the board — exercised in escalate.test.sh, not here)"

echo
echo "# an unparseable listing is refused, never read as 'nothing to migrate'"
mkdir -p "$TMP/badrig"
printf '{"rigs":[{"name":"badrig","path":"%s","suspended":false}]}\n' "$TMP/badrig" > "$STUB_RIGS"
export STUB_BD_LIST_GARBAGE='{"error":"boom"}'
out=$("$SUT" --apply 2>&1); rc=$?
eq "$rc" 1 "a non-array listing (rc 0) exits 1"
has "$out" "badrig: listing unparseable — this store was NOT migrated" "the loud NOT-migrated message names the rig"
hasnt "$out" "nothing to migrate" "garbage is never read as an empty, fully-migrated store"
export STUB_BD_LIST_GARBAGE=""

echo "# …and a listing that exits non-zero is refused the same way"
export STUB_LIST_FAIL="1"
out=$("$SUT" --apply 2>&1); rc=$?
eq "$rc" 1 "a failed listing exits 1"
has "$out" "badrig: listing unparseable — this store was NOT migrated" "…reported the same way"
export STUB_LIST_FAIL=""

echo
echo "# city scope (no rig name): no rig-qualified pool exists, so a park is"
echo "#   refused loudly rather than guessed at"
mkdir -p "$TMP/city"
printf '{"rigs":[{"name":"","path":"%s","suspended":false}]}\n' "$TMP/city" > "$STUB_RIGS"
store '[{"id":"C1","status":"open","assignee":"","title":"t-C1","metadata":{"merge_result":"pull_request","check_set":"codex","check.codex":"exception@7777777777777777777777777777777777777777","blocked_reason":"city scope park"}}]'
: > "$STUB_ESCALATE_LOG"
out=$("$SUT" --apply 2>&1); rc=$?
eq "$rc" 1 "a city-scope park needs an operator"
has "$out" "city-scope park needs an operator" "the reason is reported"
eq "$(meta C1 check.codex)" "exception@7777777777777777777777777777777777777777" "C1's legacy marker is left untouched"
eq "$(meta C1 merge_hold)" "<absent>" "C1 is not parked"
eq "$(wc -l < "$STUB_ESCALATE_LOG" | tr -d ' ')" "0" "no visit filed at city scope — nothing to route it through"

echo
echo "migrate-lane-states.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
