#!/usr/bin/env bash
# Hermetic test for assets/scripts/rework-child.sh — the one writer of a rework
# child. Stubbed gc; no live city, Dolt, or network. Its callers' suites pin the
# filing sequence end to end, each under its own provenance: signoff.test.sh for
# a review verdict and converse-rework.test.sh for an operator ruling. This suite
# pins the writer's own contract: exactly one provenance, the required work-order
# flags, the refusals that come before any write, the stdout result line its
# callers parse, a provenance key that matches only its own children on its own
# anchor, a child joined to its anchor before anchor_bead lands on it, one read
# of an edge that already stands, and every metadata key it writes registered in
# lifecycle.toml.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/rework-child.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-rework-child-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"; DEPS="${STUB_DEPS:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "sling" ]; then
  # A graph.v2 pour retires gc.routed_to and stamps gc.execution_routed_to=<pool>.
  shift; pool=""; bead=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --rig|--on) shift ;;
      -*) ;;
      *) if [ -z "$pool" ]; then pool="$1"; elif [ -z "$bead" ]; then bead="$1"; fi ;;
    esac
    shift || true
  done
  tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-rc.XXXXXX")
  jq -c --arg id "$bead" --arg p "$pool" \
    'map(if .id == $id then (.metadata["gc.execution_routed_to"] = $p | .metadata |= del(.["gc.routed_to"])) else . end)' \
    "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  exit 0
fi
# Any other non-bd command (agent list for pool-route, session wake/nudge) is a
# quiet success: pool-route reads the empty agent set as unreadable and returns
# the route unverified.
[ "${1:-}" = "bd" ] || exit 0
shift
case "${1:-}" in
  show)
    out=$(jq -c --arg id "$2" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  update)
    shift; id="$1"; shift
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-rc.XXXXXX"); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  create)
    shift; title="$1"; shift
    # --deps <type:id> rides the insert, as an edge row from the new bead.
    cmeta='{}'; cdeps=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --metadata) shift; cmeta="${1:-}" ;;
        --deps) shift; cdeps="$cdeps ${1:-}" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    printf '%s\n' "$title" >> "${STUB_CREATED:?}"
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-rc.XXXXXX")
    jq -c --arg id "fix-$n" --argjson m "$cmeta" '. + [{"id":$id,"status":"open","assignee":"","metadata":$m,"notes":""}]' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    for d in $cdeps; do printf 'fix-%s|%s|%s\n' "$n" "${d#*:}" "${d%%:*}" >> "$DEPS"; done
    printf '{"id":"fix-%s"}\n' "$n" ;;
  dep)
    shift
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
          [ -z "$typ" ] || [ "$ty" = "$typ" ] || continue
          other=""
          [ "$dir" = "down" ] && [ "$f" = "$id" ] && other="$t"
          [ "$dir" = "up" ] && [ "$t" = "$id" ] && other="$f"
          [ -n "$other" ] || continue
          row=$(jq -c --arg id "$other" '(.[] | select(.id == $id)) // {"id":$id,"metadata":{}}' "$STORE")
          [ "$first" = 1 ] || out="$out,"
          out="$out$row"; first=0
        done < "$DEPS"
        printf '%s]\n' "$out" ;;
      add)
        # `dep add A B --type T` is "A depends on B". STUB_DEP_ADD_FAIL refuses
        # it, as bd refuses a second type on a pair that already carries one.
        [ -z "${STUB_DEP_ADD_FAIL:-}" ] || { echo "Error: dependency refused" >&2; exit 1; }
        a="${2:-}"; b="${3:-}"; ty=""; shift 3 || true
        while [ $# -gt 0 ]; do
          case "$1" in --type=*) ty="${1#--type=}" ;; --type|-t) shift; ty="${1:-}" ;; esac
          shift || true
        done
        printf '%s|%s|%s\n' "$a" "$b" "$ty" >> "$DEPS"; echo "dep added" ;;
      *)
        # `dep S --blocks D` is "D depends on S".
        src="${1:-}"; shift || true
        [ "${1:-}" = "--blocks" ] && printf '%s|%s|blocks\n' "${2:-}" "$src" >> "$DEPS"
        echo "dep added" ;;
    esac ;;
  list)
    shift
    statuses=""; fields=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
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
export STUB_STORE="$TMP/store.json" STUB_DEPS="$TMP/deps" STUB_GC_LOG="$TMP/gc.log"
export STUB_SEQ="$TMP/seq" STUB_CREATED="$TMP/created"

ANCHOR='{"id":"anc-1","status":"open","assignee":"","notes":"","metadata":{"merge_result":"pull_request","branch":"polecat/anc-1","target":"main"}}'
# reset [<extra-bead-json>...]: seed the store with the anchor and clear the logs.
reset() {
  local rows="$ANCHOR" b
  for b in "$@"; do rows="$rows,$b"; done
  printf '[%s]\n' "$rows" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_CREATED"; printf '0' > "$STUB_SEQ"
}
meta()    { jq -r --arg id "$1" --arg k "$2" 'first(.[] | select(.id == $id) | .metadata[$k]) // ""' "$STUB_STORE"; }
created() { wc -l < "$STUB_CREATED" | tr -d ' '; }
WORK=(--anchor anc-1 --branch polecat/anc-1 --target main --title "Rework PR#42: t" --reason "r")
ROUTE="gc-toolkit/gc-toolkit.polecat"

echo "# --- exactly one provenance ---"
reset
OUT=$("$SUT" "${WORK[@]}" 2>&1); RC=$?
eq "$RC" "1" "no provenance is a usage error"
has "$OUT" "--review-bead or --ruling-bead is required" "…naming both flags"
OUT=$("$SUT" "${WORK[@]}" --review-bead rv-1 --ruling-bead vis-1 2>&1); RC=$?
eq "$RC" "1" "two provenances are a usage error"
has "$OUT" "name one provenance" "…saying a child answers one authority"
eq "$(created)" "0" "neither files a child"
eq "$(grep -c 'bd ' "$STUB_GC_LOG")" "0" "…or touches the store"

echo "# --- the work order is the caller's, and every part of it is required ---"
for drop in --branch --target --title --reason; do
  args=(--review-bead rv-1); skip=""
  for a in "${WORK[@]}"; do
    if [ -n "$skip" ]; then skip=""; continue; fi
    if [ "$a" = "$drop" ]; then skip=1; continue; fi
    args+=("$a")
  done
  OUT=$("$SUT" "${args[@]}" 2>&1); RC=$?
  eq "$RC" "1" "a missing $drop is a usage error"
done
eq "$(created)" "0" "no child is filed on a usage error"

echo "# --- refusals before any write ---"
reset
OUT=$("$SUT" "${WORK[@]}" --anchor anc-gone --review-bead rv-1 2>&1); RC=$?
eq "$RC" "2" "an anchor that does not resolve is refused"
has "$OUT" "does not resolve" "…naming why"
OUT=$("$SUT" "${WORK[@]}" --review-bead rv-1 --pool other-rig/gc-toolkit.polecat 2>&1); RC=$?
eq "$RC" "2" "a route no pool in this store claims is refused"
has "$OUT" "no live pool claims" "…naming the route"
eq "$(created)" "0" "neither refusal files a child"

echo "# --- the result line: filed, then in flight ---"
reset
RES=$("$SUT" "${WORK[@]}" --review-bead rv-1 2>/dev/null); RC=$?
eq "$RC" "0" "a filed child exits 0"
eq "$RES" "fix-1 $ROUTE filed" "stdout is '<child> <route> filed'"
eq "$(meta fix-1 source_review_bead)" "rv-1" "a review's child carries source_review_bead"
eq "$(meta fix-1 source_ruling_bead)" "" "…and no source_ruling_bead"
eq "$(meta fix-1 existing_pr)" "" "with no --pr-url, no PR field is stamped"
RES=$("$SUT" "${WORK[@]}" --review-bead rv-1 2>/dev/null); RC=$?
eq "$RC" "0" "the re-run exits 0"
eq "$RES" "fix-1 $ROUTE in-flight" "stdout is '<child> <route> in-flight' for a child already dispatched"
eq "$(created)" "1" "…and files no second child"

echo "# --- the result line: adopted ---"
reset '{"id":"c1","status":"open","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-1","source_ruling_bead":"vis-1"}}'
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 --pr-url https://github.com/o/r/pull/42 --pr-number 42 2>/dev/null); RC=$?
eq "$RC" "0" "an adopted child exits 0"
eq "$RES" "c1 $ROUTE adopted" "stdout is '<child> <route> adopted'"
eq "$(meta c1 existing_pr)" "https://github.com/o/r/pull/42" "--pr-url keeps the rework on that PR"
eq "$(meta c1 pr_number)" "42" "--pr-number names it"
eq "$(created)" "0" "nothing new is created"

echo "# --- a provenance key matches only its own children ---"
reset '{"id":"c1","status":"open","assignee":"","notes":"","metadata":{"source_ruling_bead":"rv-1"}}'
RES=$("$SUT" "${WORK[@]}" --review-bead rv-1 2>/dev/null)
eq "$RES" "fix-1 $ROUTE filed" "a ruling's child is not adopted for a review whose id happens to match"
eq "$(meta c1 source_review_bead)" "" "…and is left unkeyed by the review"

echo "# --- a source's live child on another anchor refuses the filing ---"
# One visit signed off twice against different subjects: the first run's child
# names the first anchor. Adopting it would re-stamp it onto this anchor while
# its blocks edge still holds the first, so the source is refused before any
# write, even beside an undispatched child of its own on this anchor.
OTHER='{"id":"c9","status":"open","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-0","source_ruling_bead":"vis-1","branch":"polecat/anc-0","target":"main"}}'
writes() { grep -cE '^bd (update|create) |^bd dep [^ ]+ --blocks |^sling ' "$STUB_GC_LOG"; }
reset "$OTHER"
OUT=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>&1); RC=$?
eq "$RC" "2" "a live child of the same source on another anchor refuses the filing"
has "$OUT" "c9 on anchor anc-0" "…naming that child and its anchor"
eq "$(created)" "0" "…filing no second child"
eq "$(writes)" "0" "…and writing nothing"
eq "$(meta c9 anchor_bead)" "anc-0" "the other anchor's child keeps its anchor"
eq "$(meta c9 gc.execution_routed_to)" "" "…and is not dispatched"
reset "$OTHER" '{"id":"c1","status":"open","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-1","source_ruling_bead":"vis-1"}}'
OUT=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>&1); RC=$?
eq "$RC" "2" "the refusal holds beside an undispatched child on this anchor"
eq "$(writes)" "0" "…which is neither stamped nor dispatched"
# A live child carrying the key but no anchor_bead was filed before children
# carried the role marker. It names no other anchor, so it is adopted, and the
# work order stamps the marker it lacks.
reset '{"id":"c5","status":"open","assignee":"","notes":"","metadata":{"source_ruling_bead":"vis-1","branch":"polecat/anc-1","target":"main"}}'
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null); RC=$?
eq "$RES" "c5 $ROUTE adopted" "a live child of the source that names no anchor is adopted"
eq "$(meta c5 anchor_bead)" "anc-1" "…and stamped with this anchor"
eq "$(created)" "0" "…filing no second child"
# A dispatched child on the other anchor is refused the same way. Reported as
# in flight, it would tell the caller a rework stands on this anchor when none
# was filed here.
reset "$(printf '%s' "$OTHER" | jq -c '.metadata["gc.execution_routed_to"] = "gc-toolkit/gc-toolkit.polecat"')"
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null); RC=$?
eq "$RC" "2" "a dispatched child of the same source on another anchor refuses the filing too"
eq "$RES" "" "…reporting no child as in flight for this anchor"
eq "$(writes)" "0" "…and writing nothing"
reset '{"id":"c9","status":"closed","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-0","source_ruling_bead":"vis-1"}}'
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null); RC=$?
eq "$RES" "fix-1 $ROUTE filed" "a closed child on another anchor refuses nothing"

echo "# --- the blocks edge: one read when it stands, a read-back when written ---"
reset '{"id":"c1","status":"open","assignee":"","notes":"","metadata":{"task_kind":"rework","anchor_bead":"anc-1","source_ruling_bead":"vis-1"}}'
printf 'anc-1|c1|blocks\n' > "$STUB_DEPS"
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null); RC=$?
eq "$RES" "c1 $ROUTE adopted" "an adopted child whose edge stands is dispatched"
eq "$(grep -c '^bd dep list anc-1 ' "$STUB_GC_LOG")" "1" "…after one read of the anchor's blockers"
eq "$(grep -c '^bd dep c1 --blocks' "$STUB_GC_LOG")" "0" "…and no second edge"
reset
RES=$("$SUT" "${WORK[@]}" --review-bead rv-1 2>/dev/null); RC=$?
eq "$RES" "fix-1 $ROUTE filed" "a filed child is dispatched"
eq "$(grep -c '^bd dep fix-1 --blocks anc-1' "$STUB_GC_LOG")" "1" "…once its edge is written"
eq "$(grep -c '^bd dep list anc-1 ' "$STUB_GC_LOG")" "2" "…and read back after the write"

echo "# --- the membership edge: born joined, or joined before the stamp ---"
# A store marked joined reads an anchor's closed children through the child's
# edge onto it (bd-lib.sh's anchor graph), so the edge stands before anchor_bead
# lands on the child.
reset
RES=$("$SUT" "${WORK[@]}" --review-bead rv-1 2>/dev/null)
eq "$RES" "fix-1 $ROUTE filed" "a filed child is dispatched"
eq "$(grep -c '^fix-1|anc-1|related$' "$STUB_DEPS")" "1" "…joined to the anchor by a related edge"
eq "$(grep -c '^bd create .* --deps related:anc-1' "$STUB_GC_LOG")" "1" "…that rides its create"
eq "$(grep -c '^bd dep add fix-1 ' "$STUB_GC_LOG")" "0" "…so no separate join is written"
UNJOINED='{"id":"c1","status":"open","assignee":"","notes":"","metadata":{"source_ruling_bead":"vis-1"}}'
reset "$UNJOINED"
RES=$("$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null)
eq "$RES" "c1 $ROUTE adopted" "an adopted child that predates the edge is dispatched"
eq "$(grep -c '^c1|anc-1|related$' "$STUB_DEPS")" "1" "…once it is joined to the anchor"
JOIN_AT=$(grep -n '^bd dep add c1 anc-1 ' "$STUB_GC_LOG" | head -1 | cut -d: -f1)
STAMP_AT=$(grep -n '^bd update c1 ' "$STUB_GC_LOG" | head -1 | cut -d: -f1)
if [ -n "$JOIN_AT" ] && [ -n "$STAMP_AT" ] && [ "$JOIN_AT" -lt "$STAMP_AT" ]; then
  ok "…and the join lands before the work order stamps anchor_bead"
else
  bad "…and the join lands before the work order stamps anchor_bead (join at log line '${JOIN_AT:-none}', stamp at '${STAMP_AT:-none}')"
fi
reset "$UNJOINED"
OUT=$(STUB_DEP_ADD_FAIL=1 "$SUT" "${WORK[@]}" --ruling-bead vis-1 2>&1); RC=$?
eq "$RC" "2" "an adopted child bd will not join is refused"
has "$OUT" "could not be joined to anchor anc-1" "…naming the anchor"
eq "$(writes)" "0" "…and is neither stamped nor dispatched"
eq "$(meta c1 anchor_bead)" "" "…so anchor_bead never lands on it"
# bd keeps one edge per ordered pair, so a pair that already carries another
# type refuses a related edge, and that edge is the child's membership edge.
reset "$UNJOINED"
printf 'c1|anc-1|tracks\n' > "$STUB_DEPS"
RES=$(STUB_DEP_ADD_FAIL=1 "$SUT" "${WORK[@]}" --ruling-bead vis-1 2>/dev/null)
eq "$RES" "c1 $ROUTE adopted" "an adopted child already on the pair by another type counts as joined"

echo "# --- metadata-key drift against lifecycle.toml ---"
# A key the writer stamps that nothing registers is state no audit can account
# for. The provenance keys are written through a variable, outside the
# extraction, so they are checked by name.
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$HERE/../../lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
WRITTEN=$( { grep -hoE -- '--set-metadata "[A-Za-z_][A-Za-z0-9_.]*=' "$SUT" \
               | sed -E 's/^--set-metadata "//; s/=$//'
             printf '%s\n' source_review_bead source_ruling_bead; } | sort -u)
if grep -qx 'merge_strategy' <<< "$WRITTEN"; then
  ok "the extraction reads the writer's work-order stamps"
else
  bad "the extraction found no merge_strategy write (got: $(tr '\n' ' ' <<< "$WRITTEN"))"
fi
UNREGISTERED=$(printf '%s\n' "$WRITTEN" \
  | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every metadata key rework-child.sh writes is registered in lifecycle.toml"

echo
echo "===================="
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
