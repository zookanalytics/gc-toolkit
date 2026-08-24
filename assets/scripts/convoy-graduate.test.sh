#!/usr/bin/env bash
# Hermetic test for assets/scripts/convoy-graduate.sh — convoy graduation.
# Covers: the happy path (assignee/branch/target/merge_strategy/graduation);
# the non-vacuous-completion guard (no recorded merge onto the branch = no
# graduation); operator holds on the convoy bead and on a separate bead naming
# the branch; a live branch owner; idempotency via metadata.branch; fail-closed
# skips on unreadable probes; and the GC_AGENT-unset skip.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
SUT="$HERE/convoy-graduate.sh"
[ -x "$SUT" ] || chmod +x "$SUT"

export STUB_CONVOYS="$TMP/convoys.json"
export GC_AGENT="rig/gc-toolkit.refinery"
unset GC_RIG 2>/dev/null || true

convoys() { printf '%s' "$1" > "$STUB_CONVOYS"; }
cbead() { # id extra
  printf '{"id":"%s","status":"open","assignee":"","notes":"","issue_type":"convoy","metadata":{%s}}' "$1" "${2:-}"
}
landed() { # id branch
  printf '{"id":"%s","status":"closed","assignee":"","notes":"","metadata":{"merged_target":"%s","merge_result":"merged"}}' "$1" "$2"
}
cv() { # id target closed total
  printf '{"id":"%s","owned":true,"fields":{"target":"%s"},"progress":{"closed":%s,"total":%s}}' "$1" "$2" "$3" "$4"
}

echo "# happy path"
convoys "{\"convoys\":[$(cv cv-1 integration/feat 2 2)]}"
store "[$(cbead cv-1), $(landed w-1 integration/feat)]"
out=$("$SUT" --target main 2>&1); rc=$?
eq "$rc" 0 "graduation pass exits 0"
has "$out" "graduating cv-1 — integration/feat -> main (mr" "the convoy graduates"
eq "$(bassignee cv-1)" "$GC_AGENT" "assignee = the refinery"
eq "$(meta cv-1 branch)" "integration/feat" "branch = the integration branch"
eq "$(meta cv-1 target)" "main" "target = the graduation target"
eq "$(meta cv-1 merge_strategy)" "mr" "merge_strategy = mr (human-approved PR)"
eq "$(meta cv-1 graduation)" "true" "graduation marker stamped"

echo "# idempotent: branch present means already initiated"
out=$("$SUT" --target main 2>&1)
has "$out" "1 skipped" "a graduated convoy is not re-assigned"

echo "# vacuous completion refuses"
convoys "{\"convoys\":[$(cv cv-2 integration/empty 1 1)]}"
store "[$(cbead cv-2)]"
out=$("$SUT" 2>&1)
has "$out" "no bead records a merge onto 'integration/empty'" "no recorded landing = no graduation"
has "$out" "1 vacuous" "…counted apart"
eq "$(meta cv-2 branch)" "<absent>" "…and nothing was assigned"

echo "# incomplete or un-owned convoys are not candidates"
convoys "{\"convoys\":[$(cv cv-3 integration/x 1 2), {\"id\":\"cv-4\",\"owned\":false,\"fields\":{\"target\":\"integration/y\"},\"progress\":{\"closed\":1,\"total\":1}}]}"
store "[$(cbead cv-3), $(cbead cv-4)]"
out=$("$SUT" 2>&1)
has "$out" "no complete owned integration convoys" "open members / un-owned convoys never reach the gates"

echo "# operator hold on the convoy bead"
convoys "{\"convoys\":[$(cv cv-5 integration/h 1 1)]}"
store "[$(cbead cv-5 '"merge_hold":"true"'), $(landed w-5 integration/h)]"
out=$("$SUT" 2>&1)
has "$out" "operator gate); not graduated" "merge_hold on the convoy vetoes"
eq "$(meta cv-5 branch)" "<absent>" "…and nothing was assigned"

echo "# hold on a SEPARATE bead naming the branch"
convoys "{\"convoys\":[$(cv cv-6 integration/f 1 1)]}"
store "[$(cbead cv-6), $(landed w-6 integration/f),
        {\"id\":\"rb-1\",\"status\":\"blocked\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"integration/f\",\"rebase_hold\":\"true\"}}]"
out=$("$SUT" 2>&1)
has "$out" "rb-1 holds branch 'integration/f'" "a held sibling bead vetoes (even blocked — not-open is not gone)"

echo "# live unheld branch owner"
convoys "{\"convoys\":[$(cv cv-7 integration/g 1 1)]}"
store "[$(cbead cv-7), $(landed w-7 integration/g),
        {\"id\":\"own-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"branch\":\"integration/g\"}}]"
out=$("$SUT" 2>&1)
has "$out" "own-1 already owns branch 'integration/g'" "a live owner blocks a duplicate graduation"

echo "# unreadable probes fail closed"
convoys "{\"convoys\":[$(cv cv-8 integration/z 1 1)]}"
store "[$(cbead cv-8), $(landed w-8 integration/z)]"
out=$(STUB_LIST_FAIL=1 "$SUT" 2>&1); rc=$?
eq "$rc" 0 "a probe failure does not abort the pass"
hasnt "$out" "graduating cv-8" "…but nothing graduates on a read that could not answer"

echo "# rig scoping: a convoy absent from this rig's ledger is skipped"
convoys "{\"convoys\":[$(cv cv-9 integration/other 1 1)]}"
store "[$(landed w-9 integration/other)]"
out=$("$SUT" 2>&1)
has "$out" "1 skipped" "a foreign rig's convoy is not graduated here"

echo "# GC_AGENT unset skips"
out=$(env -u GC_AGENT "$SUT" 2>&1); rc=$?
eq "$rc" 0 "no identity exits 0"
has "$out" "GC_AGENT unset; skip" "…and says why"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
