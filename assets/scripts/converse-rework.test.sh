#!/usr/bin/env bash
# Hermetic test for assets/scripts/converse-rework.sh — an operator ruling's entry
# to rework — run end to end through rework-child.sh, the one writer of a rework
# child that signoff.sh files through too. Stubbed gc; no live city, Dolt, or
# network. The child is the fix unit a review verdict files (task_kind=rework,
# anchor_bead, branch, target, merge_strategy=mr, PR fields), sourced by
# source_ruling_bead rather than source_review_bead; it blocks the anchor and is
# slung with mol-polecat-work. The assertions pin: the child's full work order,
# that it carries source_ruling_bead and NOT a minted source_review_bead, the
# blocks edge, the dispatch read-back, idempotency on the ruling, the identity
# riding in the create so a lost create id is adopted rather than twinned, a
# review's child never adopted for a ruling, the open-PR-only guard, and the
# no-double-dispatch refusal on a partial pour.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/converse-rework.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-converse-rework-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"; DEPS="${STUB_DEPS:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "sling" ]; then
  # `gc sling [--rig X] <pool> <bead> --on <formula>`: a graph.v2 pour retires
  # gc.routed_to and stamps gc.execution_routed_to=<pool>, the read-back the SUT
  # proves the pour by. STUB_SLING_NOPOUR models a pour that exits success but
  # never stamps the route (a partial pour), so the SUT must refuse a bare-route
  # fallback rather than double-dispatch the work.
  shift; pool=""; bead=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rig|--on) shift ;;
      -*) ;;
      *) if [ -z "$pool" ]; then pool="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
    esac
    shift || true
  done
  if [ -z "${STUB_SLING_NOPOUR:-}" ] && [ -n "$bead" ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX")
    jq -c --arg id "$bead" --arg p "$pool" \
      'map(if .id == $id then (.metadata["gc.execution_routed_to"] = $p | .metadata |= del(.["gc.routed_to"])) else . end)' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  fi
  exit 0
fi
# Any non-bd command (agent list for pool-route, session wake/nudge) is a quiet
# success: pool-route reads an empty agent set as UNREADABLE and returns the
# route UNVERIFIED (exit 0), which is enough for the dispatch to proceed.
[ "${1:-}" = "bd" ] || exit 0
shift
bead_json() { jq -c --arg id "$1" '[.[] | select(.id == $id)]' "$STORE"; }
case "${1:-}" in
  show)
    out=$(bead_json "$2")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  update)
    shift; id="$1"; shift
    [ -n "${STUB_UPD_FAIL:-}" ] && grep -qx "$id" "$STUB_UPD_FAIL" 2>/dev/null && { echo "bd: denied (stub)" >&2; exit 1; }
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX"); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
        --status=*) st="${1#--status=}"
          jq -c --arg id "$id" --arg s "$st" \
            'map(if .id == $id then .status = $s else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  create)
    shift; title="$1"; shift
    [ -n "${STUB_CREATE_FAIL:-}" ] && exit 1
    # --metadata lands in the same insert as the bead, as bd applies it.
    cmeta='{}'
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata) shift; cmeta="${1:-}" ;;
        --metadata=*) cmeta="${1#--metadata=}" ;;
      esac
      shift || true
    done
    printf '%s' "$cmeta" | jq -e 'type == "object"' >/dev/null 2>&1 \
      || { echo "bd: --metadata is not a JSON object (stub)" >&2; exit 1; }
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    printf '%s\n' "$title" >> "${STUB_CREATED:?}"
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-cr.XXXXXX")
    jq -c --arg id "fix-$n" --argjson m "$cmeta" '. + [{"id":$id,"status":"open","assignee":"","metadata":$m,"notes":""}]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    # STUB_CREATE_NOID: the insert lands but no id comes back, as when the call
    # is killed after its write commits.
    [ -n "${STUB_CREATE_NOID:-}" ] && exit 1
    printf '{"id":"fix-%s"}\n' "$n" ;;
  dep)
    shift
    # `dep S --blocks D` is "D depends on S"; --direction=down lists what an id
    # depends on, =up what depends on it.
    case "${1:-}" in
      list)
        shift; id="$1"; shift
        dir=""; typ=""
        while [ $# -gt 0 ]; do
          case "$1" in --direction=*) dir="${1#--direction=}" ;; -t) shift; typ="$1" ;; esac
          shift || true
        done
        out="["; first=1
        while IFS='|' read -r f t ty; do
          [ -n "$f" ] || continue
          [ "$ty" = "$typ" ] || continue
          other=""
          [ "$dir" = "down" ] && [ "$f" = "$id" ] && other="$t"
          [ "$dir" = "up" ] && [ "$t" = "$id" ] && other="$f"
          [ -n "$other" ] || continue
          row=$(jq -c --arg id "$other" '(.[] | select(.id == $id)) // {"id":$id,"metadata":{}}' "$STORE")
          [ "$first" = 1 ] || out="$out,"
          out="$out$row"; first=0
        done < "$DEPS"
        printf '%s]\n' "$out" ;;
      *)
        src="${1:-}"; shift || true
        [ "${1:-}" = "--blocks" ] && printf '%s|%s|blocks\n' "${2:-}" "$src" >> "$DEPS"
        echo "dep added" ;;
    esac ;;
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "bd: list unavailable (stub)" >&2; exit 1; }
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --status) shift; statuses="${1:-}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
        --metadata-field=*) fields+=("${1#--metadata-field=}") ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st "$statuses" '[ .[] | (.status // "open") as $b
      | select($st == "" or (($st | split(",")) | index($b))) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      out=$(printf '%s' "$out" | jq -c --arg k "${f%%=*}" --arg v "${f#*=}" \
        '[ .[] | select(((((.metadata // {})[$k]) // "") | tostring) == $v) ]')
    done
    printf '%s\n' "$out" ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export GC_RIG="gc-toolkit"

export STUB_STORE="$TMP/store.json"
export STUB_DEPS="$TMP/deps"
export STUB_GC_LOG="$TMP/gc.log"
export STUB_SEQ="$TMP/seq"
export STUB_CREATED="$TMP/created"

# reset <anchor-json>: seed the store with one anchor and clear the logs.
reset() {
  printf '%s\n' "$1" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_CREATED"; printf '0' > "$STUB_SEQ"
  unset STUB_SLING_NOPOUR STUB_UPD_FAIL STUB_CREATE_FAIL STUB_CREATE_NOID STUB_LIST_FAIL 2>/dev/null || true
}
meta()    { jq -r --arg id "$1" --arg k "$2" 'first(.[] | select(.id == $id) | .metadata[$k]) // ""' "$STUB_STORE"; }
created() { wc -l < "$STUB_CREATED" | tr -d ' '; }
# Does the child block the anchor? The edge is recorded dependent|blocker, so a
# child (arg 1) blocking the anchor (arg 2) is the line "<anchor>|<child>|blocks".
blocks_anchor() { grep -qxF "$2|$1|blocks" "$STUB_DEPS"; }

ANCHOR_PR='[{"id":"anc-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","branch":"polecat/anc-1","target":"main","existing_pr":"https://github.com/o/r/pull/42","pr_url":"https://github.com/o/r/pull/42","pr_number":"42"}}]'

echo "# --- happy path: a ruling on an open PR mints the fix unit and dispatches it ---"
reset "$ANCHOR_PR"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC" "0" "exit 0 on a clean mint+dispatch"
eq "$(created)" "1" "exactly one rework child created"
eq "$(meta fix-1 task_kind)" "rework" "child is task_kind=rework"
eq "$(meta fix-1 anchor_bead)" "anc-1" "child names the anchor"
eq "$(meta fix-1 branch)" "polecat/anc-1" "child resumes the anchor's branch"
eq "$(meta fix-1 target)" "main" "child lands where the anchor lands"
eq "$(meta fix-1 merge_strategy)" "mr" "child is merge_strategy=mr"
eq "$(meta fix-1 source_ruling_bead)" "vis-1" "child names the ruling's visit as source_ruling_bead"
eq "$(meta fix-1 source_review_bead)" "" "child carries NO source_review_bead (a ruling has no verdict)"
eq "$(meta fix-1 existing_pr)" "https://github.com/o/r/pull/42" "child keeps the rework on this PR (existing_pr)"
eq "$(meta fix-1 pr_number)" "42" "child carries pr_number"
has "$(meta fix-1 rejection_reason)" "apply the amendment" "rejection_reason carries the ruling"
has "$(meta fix-1 rejection_reason)" "vis-1" "rejection_reason names the visit"
if blocks_anchor fix-1 anc-1; then ok "child blocks the anchor (merge held by the edge)"; else bad "child does NOT block the anchor"; fi
eq "$(meta fix-1 gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "child was slung (execution_routed_to read back)"
has "$OUT" "filed rework fix-1 on anchor anc-1" "reports the filed child"
eq "$(meta fix-1 prepare_mode)" "" "prepare_mode left unset (resume defaults merge; refinery re-stamps)"

echo "# --- idempotency: a second run on the same ruling files no second child ---"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment directly to docs/material-layers.md" 2>&1); RC=$?
eq "$RC" "0" "exit 0 on the re-run"
eq "$(created)" "1" "still exactly one child (dedup on source_ruling_bead)"
has "$OUT" "already dispatched" "re-run reports the child is already in flight"

echo "# --- guard: a non-PR anchor is refused, nothing filed ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"","branch":"polecat/anc-1","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor is not an open PR"
eq "$(created)" "0" "no child filed for a non-PR anchor"
has "$OUT" "not pull_request" "says why it refused"

echo "# --- guard: an open PR with no branch is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request","target":"main"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no branch"
eq "$(created)" "0" "no child filed when the branch is unknown"

echo "# --- guard: an open PR with no landing target is refused ---"
reset '[{"id":"anc-1","status":"open","metadata":{"merge_result":"pull_request","branch":"polecat/anc-1"}}]'
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "2" "exit 2 when the anchor names no target"
eq "$(created)" "0" "no child filed when the target is unknown"

echo "# --- no double-dispatch: a partial pour (no route stamped) refuses the bare-route fallback ---"
reset "$ANCHOR_PR"
export STUB_SLING_NOPOUR=1
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
unset STUB_SLING_NOPOUR
eq "$RC" "2" "exit 2 when the pour did not stamp the route"
eq "$(created)" "1" "the child is filed"
if blocks_anchor fix-1 anc-1; then ok "the child still blocks the anchor (merge stays held for the retry)"; else bad "the child does not block the anchor"; fi
eq "$(meta fix-1 gc.execution_routed_to)" "" "no bare route stamped (no double-dispatch)"
has "$OUT" "double-dispatch hazard" "says why it refused to bare-stamp"

echo "# --- fail-closed: an unreadable dedup query files nothing ---"
reset "$ANCHOR_PR"
export STUB_LIST_FAIL=1
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
unset STUB_LIST_FAIL
eq "$RC" "2" "exit 2 when the dedup query is unreadable"
eq "$(created)" "0" "no child filed on an unreadable dedup query"

echo "# --- identity at create: a create whose id never came back is adopted on the retry, not twinned ---"
# The child is in the store, but the run never learned its id, so nothing past the
# create ran: no work order, no edge, no pour. The dedup finds a prior child only
# by source_ruling_bead, so that key must ride in the create itself; a child born
# bare and keyed by a later write is invisible to the retry, which files a twin.
reset "$ANCHOR_PR"
export STUB_CREATE_NOID=1
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
unset STUB_CREATE_NOID
eq "$RC" "2" "exit 2 when the create returned no id"
has "$OUT" "returned no id" "says the create's id was lost"
eq "$(created)" "1" "the create landed exactly one child"
eq "$(meta fix-1 source_ruling_bead)" "vis-1" "the child carries the ruling's key from its create"
eq "$(meta fix-1 task_kind)" "rework" "…and its role marker"
eq "$(meta fix-1 anchor_bead)" "anc-1" "…and the anchor it belongs to"
eq "$(meta fix-1 branch)" "" "no work order was stamped on a child whose id never came back"
eq "$(meta fix-1 gc.execution_routed_to)" "" "…and it was never dispatched"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "apply the amendment" 2>&1); RC=$?
eq "$RC" "0" "the retry exits 0"
eq "$(created)" "1" "the retry files NO second child"
has "$OUT" "adopting existing open rework child fix-1" "…it adopts the child the lost-id create filed"
eq "$(meta fix-1 branch)" "polecat/anc-1" "the adopted child is stamped with the full work order"
has "$(meta fix-1 rejection_reason)" "apply the amendment" "…including the ruling as its rejection_reason"
eq "$(meta fix-1 gc.execution_routed_to)" "gc-toolkit/gc-toolkit.polecat" "the adopted child is dispatched on the retry"
eq "$(grep -cxF 'anc-1|fix-1|blocks' "$STUB_DEPS")" "1" "exactly one edge holds the anchor"

echo "# --- provenance: a review's rework child is never adopted for a ruling ---"
# The source key is the dedup key, so a live child a review verdict filed on the
# same anchor answers that review, not this ruling: the ruling files its own.
reset "$(printf '%s' "$ANCHOR_PR" | jq -c '. + [{"id":"rv-kid","status":"open","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-1","source_review_bead":"rv-1","branch":"polecat/anc-1","target":"main"}}]')"
OUT=$("$SUT" --anchor anc-1 --ruling-bead vis-1 --ruling "x" 2>&1); RC=$?
eq "$RC" "0" "exit 0"
eq "$(created)" "1" "the ruling files its own child beside the review's"
eq "$(meta fix-1 source_ruling_bead)" "vis-1" "…keyed on the ruling"
eq "$(meta rv-kid source_ruling_bead)" "" "the review's child is not re-keyed"
eq "$(meta rv-kid gc.execution_routed_to)" "" "…nor dispatched by the ruling"

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
