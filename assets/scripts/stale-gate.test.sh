#!/usr/bin/env bash
# Hermetic test for assets/scripts/stale-gate.sh, the one definition of the
# stale-PR gate. Covers:
#   (DEF)     sourcing the file exposes $STALE_GATE_KEY and $STALE_GATE_JQ and
#             runs nothing; executed as `stale-gate.sh key` it prints the key,
#             and any other use is a usage error
#   (KEY)     the key is in the charset escalate.sh and finalize-gate.sh accept
#   (VISIT)   unengaged_stale_gate_visit names an open visit under the key that
#             nobody is engaged in, and nothing else
#   (READERS) liveness-sweep.sh, liveness-sweep-precheck.sh and merge.sh source
#             this file, and gctk merge runs it for the key
#   (NO-COPY) no other file in the pack names the key or defines the premise
# A reader with a private copy drifts silently: a renamed key would leave
# merge.sh holding every approved PR behind its visit again, and the precheck
# reading visits the pass no longer files. The behavioral half lives beside each
# reader: merge.test.sh renames the key in its scripts directory and runs both
# merge implementations against it, liveness-sweep-precheck.test.sh does the
# same for the precheck, and liveness-sweep.test.sh files and retracts under it.
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/stale-gate.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

echo "# the definition"
# shellcheck disable=SC1090  # the same file, followed at the source below
SOURCED_OUT=$(. "$LIB" 2>&1)
eq "$SOURCED_OUT" "" "(DEF) sourcing the file prints nothing"
# shellcheck source=stale-gate.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${STALE_GATE_KEY:-}" ] && ok "(DEF) sourcing the file exposes \$STALE_GATE_KEY" \
    || bad "(DEF) sourcing the file exposes \$STALE_GATE_KEY"
[ -n "${STALE_GATE_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$STALE_GATE_JQ" \
    || bad "(DEF) sourcing the file exposes \$STALE_GATE_JQ"
[ -x "$LIB" ] && ok "(DEF) the file is executable, for gctk merge to run" \
    || bad "(DEF) the file is executable, for gctk merge to run"
OUT=$("$LIB" key 2>/dev/null); RC=$?
eq "$RC" "0" "(DEF) \`stale-gate.sh key\` exits 0"
eq "$OUT" "$STALE_GATE_KEY" "(DEF) …and prints the key the sourced definition names"
"$LIB" >/dev/null 2>&1; eq "$?" "2" "(DEF) run with no argument, it is a usage error"
"$LIB" keys >/dev/null 2>&1; eq "$?" "2" "(DEF) run with an unknown argument, it is a usage error"
case "$STALE_GATE_KEY" in
    *[!A-Za-z0-9._-]*) bad "(KEY) the key is in the charset escalate.sh and finalize-gate.sh accept" ;;
    *) ok "(KEY) the key is in the charset escalate.sh and finalize-gate.sh accept" ;;
esac

echo "# the visits the key names"
visit() { # <visit fields to merge>
    jq -cn --arg k "$STALE_GATE_KEY" --argjson v "$1" \
        '{id: "v-1", status: "open", assignee: "",
          metadata: {task_kind: "visit", escalation_key: $k, "gc.continuation_group": "a-1"}} * $v'
}
picks() { printf '%s' "$1" | jq "$STALE_GATE_JQ"' unengaged_stale_gate_visit'; }
eq "$(picks "$(visit '{}')")" "true" "(VISIT) an open visit under the key that nobody engaged"
eq "$(picks "$(visit '{"metadata":{"escalation_key":"anchor-other"}}')")" "false" "(VISIT) not a visit under another key"
eq "$(picks "$(visit '{"assignee":"human-1"}')")" "false" "(VISIT) not one bound by an assignee"
eq "$(picks "$(visit '{"metadata":{"gc.session_name":"s-conv-1"}}')")" "false" "(VISIT) not one bound to a session"
eq "$(picks "$(visit '{"status":"in_progress"}')")" "false" "(VISIT) not one claimed (in_progress)"
eq "$(picks "$(visit '{"status":"closed"}')")" "false" "(VISIT) not one closed"
eq "$(picks "$(visit '{"metadata":{"task_kind":"rework"}}')")" "false" "(VISIT) not a bead of another kind"
eq "$(picks '{"id":"v-2"}')" "false" "(VISIT) not a bead with no metadata"

echo "# every reader reads the one definition"
for r in assets/scripts/liveness-sweep.sh assets/scripts/liveness-sweep-precheck.sh assets/scripts/merge.sh; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    grep -qE '^[[:space:]]*\.[[:space:]].*stale-gate\.sh' "$f" \
        && ok "(READERS) $r sources stale-gate.sh" \
        || bad "(READERS) $r sources stale-gate.sh"
done
GO="$ROOT/services/gctk/internal/cli/merge.go"
grep -qF 'scriptCapture("stale-gate.sh", "key")' "$GO" \
    && ok "(READERS) gctk merge runs stale-gate.sh for the key" \
    || bad "(READERS) gctk merge runs stale-gate.sh for the key"

echo "# no private copies"
# A copy is the key spelled out, or a jq def of the premise under one of its
# names. Specs and generated renders are history and output, not readers, and a
# test names the key to build its fixtures.
COPY_RE="$STALE_GATE_KEY|def (unengaged_stale_gate_visit|settled_posture|review_owed)[[:space:]]*:"
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    hits=$(grep -rlE "$COPY_RE" "$ROOT/$d" 2>/dev/null | grep -vxF "$LIB" \
        | grep -vE '\.test\.sh$|_test\.go$' || true)
    [ -n "$hits" ] && COPIES="$COPIES $hits"
done
eq "$(printf '%s' "$COPIES" | sed 's#'"$ROOT"'/##g' | tr -s ' ' | sed 's/^ //')" "" \
   "(NO-COPY) no file but stale-gate.sh names the key or defines the premise"

echo
echo "stale-gate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
