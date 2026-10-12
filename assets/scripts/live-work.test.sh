#!/usr/bin/env bash
# Hermetic test for assets/scripts/live-work.sh, the definition of live work an
# automated disposal must never close. Covers:
#   (DEF)     the key list is non-empty and unique and names the marks of the
#             two shapes a disposal must never close: an anchor mid-PR and work
#             slung to a pool; the plain-work types are the work allowlist
#   (ROW)     live_work_reasons is empty for a plain open bead and names every
#             mark otherwise: each key with a non-blank value, a non-open
#             status, an assignee, and a type outside the allowlist, a missing
#             one included; a blank value, a disposition pointer and an
#             unknown key are no mark
#   (EDGES)   live_work_edge_reasons names a convoy that tracks the bead,
#             whatever its status, an open child, and a convoy parent; a closed
#             child and a bead waiting on this one are no mark; an unreadable
#             list of dependents refuses
#   (READERS) the until consumer and its doctor mirror source this file, apply
#             $LIVE_WORK_JQ and ask both predicates
#   (NO-COPY) no other file in the pack defines these defs
# A reader with a private copy drifts silently: it keeps the marks it copied and
# misses every mark added later. The behavioral half lives beside each reader
# (deferred-dispatch.test.sh, doctor/check-until-resolved-owed/run.test.sh).
# Reads the repo only; no gc, no city, no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
LIB="$HERE/live-work.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# shellcheck source=live-work.sh
. "$LIB" || { echo "FAIL - cannot source $LIB" >&2; exit 1; }
[ -n "${LIVE_WORK_JQ:-}" ] && ok "(DEF) sourcing the file exposes \$LIVE_WORK_JQ" \
    || bad "(DEF) sourcing the file exposes \$LIVE_WORK_JQ"

echo "# the keys"
KEYS_JSON="$(jq -nc "$LIVE_WORK_JQ"'live_work_keys' 2>/dev/null)"
eq "$(printf '%s' "$KEYS_JSON" | jq -r 'type == "array" and length > 0 and all(.[]; type == "string" and length > 0)' 2>/dev/null)" \
   "true" "(DEF) live_work_keys is a non-empty list of non-empty strings"
eq "$(printf '%s' "$KEYS_JSON" | jq -r 'length == (unique | length)' 2>/dev/null)" \
   "true" "(DEF) live_work_keys names each key once"
for k in merge_result pr_url branch gc.routed_to gc.execution_routed_to gc.dispatch_when_ready task_kind gc.root_bead_id; do
    eq "$(printf '%s' "$KEYS_JSON" | jq -r --arg k "$k" 'index($k) != null' 2>/dev/null)" \
       "true" "(DEF) live_work_keys names $k"
done
eq "$(jq -nc "$LIVE_WORK_JQ"'live_work_plain_types' 2>/dev/null)" '["task","bug","feature","chore","spike"]' \
   "(DEF) the plain-work types are the work allowlist"

echo "# the row"
row() { printf '%s' "$1" | jq -c "$LIVE_WORK_JQ"'live_work_reasons' 2>/dev/null; }
PLAIN='{"id":"a","issue_type":"task","status":"open","assignee":"","metadata":{}}'
eq "$(row "$PLAIN")" "[]" "(ROW) a plain open, unassigned bead carries no mark"
for t in task bug feature chore spike; do
    eq "$(row "{\"id\":\"a\",\"issue_type\":\"$t\",\"status\":\"open\"}")" "[]" "(ROW) a $t with no metadata at all carries no mark"
done
for k in $(printf '%s' "$KEYS_JSON" | jq -r '.[]'); do
    eq "$(row "$(jq -nc --arg k "$k" '{id:"a", issue_type:"task", status:"open", metadata: {($k): "v"}}')")" \
       "$(jq -nc --arg k "$k" '[$k + "=v"]')" "(ROW) $k marks live work"
    for blank in empty space; do
        case "$blank" in empty) v='' ;; space) v=' ' ;; esac
        eq "$(row "$(jq -nc --arg k "$k" --arg v "$v" '{id:"a", issue_type:"task", status:"open", metadata: {($k): $v}}')")" \
           "[]" "(ROW) a blank ($blank) $k is no mark"
    done
done
eq "$(row '{"id":"a","issue_type":"task","status":"open","metadata":{"pr_number":1092}}')" '["pr_number=1092"]' \
   "(ROW) a numeric value marks too"
for st in in_progress blocked deferred hooked pinned closed; do
    eq "$(row "{\"id\":\"a\",\"issue_type\":\"task\",\"status\":\"$st\"}")" "[\"status=$st\"]" "(ROW) status $st marks live work"
done
eq "$(row '{"id":"a","issue_type":"task","status":"open","assignee":"rig/rig.polecat"}')" '["assignee=rig/rig.polecat"]' \
   "(ROW) an assignee marks live work"
for t in epic convoy decision spec event gate molecule message; do
    eq "$(row "{\"id\":\"a\",\"issue_type\":\"$t\",\"status\":\"open\"}")" "[\"issue_type=$t\"]" "(ROW) a $t is not plain work"
done
eq "$(row '{"id":"a","status":"open"}')" '["issue_type="]' "(ROW) a row with no issue_type refuses (an unread mark is a mark)"
for case in '{"gc.superseded_by":"x-1"}' '{"gc.takeaway":"waits on x-1"}' '{"gc.first_reaction":"actionable"}' '{"gc.routed_to_hint":"rig/rig.polecat"}'; do
    eq "$(row "$(jq -nc --argjson m "$case" '{id:"a", issue_type:"task", status:"open", metadata:$m}')")" "[]" \
       "(ROW) $case is no mark"
done
eq "$(row '{"id":"a","issue_type":"task","status":"open","metadata":{"merge_result":"pull_request","gc.routed_to":"rig/rig.polecat"}}' | jq -r 'length')" \
   "2" "(ROW) every mark is named, not just the first"
LONG="$(printf 'x%.0s' $(seq 1 200))"
eq "$(row "{\"id\":\"a\",\"issue_type\":\"task\",\"status\":\"open\",\"metadata\":{\"work_dir\":\"$LONG\"}}" | jq -r '.[0] | length')" \
   "89" "(ROW) a long value is cut to 80 characters after its key (work_dir= is 9)"

echo "# the edges"
edges() { printf '%s' "$1" | jq -c --argjson up "$2" "$LIVE_WORK_JQ"'live_work_edge_reasons($up)' 2>/dev/null; }
eq "$(edges '{"id":"a","dependencies":null}' '[]')" "[]" "(EDGES) no edges, no mark"
eq "$(edges '{"id":"a"}' '[{"id":"c-1","dependency_type":"tracks","issue_type":"convoy","status":"open"}]')" \
   '["tracked by convoy c-1 (open)"]' "(EDGES) an open convoy tracking it marks live work"
eq "$(edges '{"id":"a"}' '[{"id":"c-1","dependency_type":"tracks","issue_type":"convoy","status":"closed"}]')" \
   '["tracked by convoy c-1 (closed)"]' "(EDGES) a closed convoy tracking it marks live work (a pour once ran over it)"
eq "$(edges '{"id":"a"}' '[{"id":"k-1","dependency_type":"parent-child","issue_type":"task","status":"open"}]')" \
   '["open child k-1"]' "(EDGES) an open child marks live work"
eq "$(edges '{"id":"a"}' '[{"id":"k-1","dependency_type":"parent-child","issue_type":"task","status":"closed"}]')" \
   "[]" "(EDGES) a closed child is no mark"
eq "$(edges '{"id":"a"}' '[{"id":"b-1","dependency_type":"blocks","issue_type":"task","status":"open"},{"id":"u-1","dependency_type":"until","issue_type":"task","status":"open"}]')" \
   "[]" "(EDGES) a bead waiting on this one, or resolved by it, is no mark"
eq "$(edges '{"id":"a","dependencies":[{"id":"cv-1","dependency_type":"parent-child","issue_type":"convoy","status":"open"}]}' '[]')" \
   '["child of convoy cv-1"]' "(EDGES) a convoy parent marks live work"
eq "$(edges '{"id":"a","dependencies":[{"id":"e-1","dependency_type":"parent-child","issue_type":"epic","status":"open"},{"id":"x-1","dependency_type":"until","issue_type":"task","status":"closed"}]}' '[]')" \
   "[]" "(EDGES) an epic parent or an until target is no mark"
for up in '{"error":"no issue found"}' 'null' '"x"'; do
    eq "$(edges '{"id":"a"}' "$up")" '["dependents=unreadable"]' "(EDGES) dependents read as $up refuse"
done

echo "# every reader sources the one definition"
# Comment lines are left out, so a reader that names the definition in prose
# but no longer calls it still fails.
READERS="assets/scripts/deferred-dispatch.sh
doctor/check-until-resolved-owed/run.sh"
for r in $READERS; do
    f="$ROOT/$r"
    if [ ! -f "$f" ]; then bad "(READERS) $r exists"; continue; fi
    code="$(grep -vE '^[[:space:]]*#' "$f")"
    grep -qE '^[[:space:]]*\.[[:space:]].*live-work\.sh' <<< "$code" \
        && ok "(READERS) $r sources live-work.sh" \
        || bad "(READERS) $r sources live-work.sh"
    grep -q 'LIVE_WORK_JQ' <<< "$code" \
        && ok "(READERS) $r applies \$LIVE_WORK_JQ" \
        || bad "(READERS) $r applies \$LIVE_WORK_JQ"
    grep -q 'live_work_reasons' <<< "$code" \
        && ok "(READERS) $r asks live_work_reasons" \
        || bad "(READERS) $r asks live_work_reasons"
    grep -q 'live_work_edge_reasons' <<< "$code" \
        && ok "(READERS) $r asks live_work_edge_reasons" \
        || bad "(READERS) $r asks live_work_edge_reasons"
done

echo "# no private copies"
# Specs and generated renders are history and output, not readers.
DEF_RE='def[[:space:]]+(live_work_keys|live_work_plain_types|live_work_reasons|live_work_edge_reasons)'
COPIES=""
for d in agents assets doctor formulas lifecycle orders overlays packs services skills template-fragments tools; do
    [ -d "$ROOT/$d" ] || continue
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in "$LIB"|"$HERE/live-work.test.sh") continue ;; esac
        COPIES="$COPIES ${f#"$ROOT"/}"
    done <<< "$(grep -rlE "$DEF_RE" "$ROOT/$d" 2>/dev/null)"
done
eq "${COPIES# }" "" "(NO-COPY) no file outside live-work.sh defines its own live-work defs"

echo
echo "live-work: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
