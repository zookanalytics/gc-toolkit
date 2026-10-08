#!/usr/bin/env bash
# Hermetic test for doctor/check-refinery-patrol-live (I14). Stubs gc only.
# It fires on a refinery whose queue has waited past the bound while its patrol
# wisp has not moved, or is gone, and stays SILENT on the two healthy shapes it
# must not report: an idle refinery whose wisp rests beside an empty queue, and
# a refinery that has not yet had the bound to take work that just arrived.
# The stub applies the filters real bd applies server-side (assignee, status,
# type, exclude-type, has-metadata-key), so a row the real store would never
# return cannot reach the check here either. It also hides ephemeral wisps
# unless the call passes --include-infra. That is stricter than bd, which lists
# them for an explicit --type molecule too, and it holds the wisp probe to the
# patrol formula's own wisp lookup, --type molecule --include-infra. The last
# section pins the queue probe to the filters find-work-select uses, so the
# queue this check ages stays the queue the patrol takes from.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-refinery-patrol-live-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

unset GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES GC_DOCTOR_CHECK_TIMEOUT GC_CITY GC_CITY_ROOT
mkdir -p "$TMP/bin" "$TMP/stores"
export STORES="$TMP/stores" CALLS="$TMP/calls.log" STATUS_JSON="$TMP/status.json"
: > "$CALLS"

# Fixtures are written relative to real time because the check ages them with
# jq's `now`; every age below sits well clear of a minute boundary.
ago() { jq -nr --argjson t "$(( $(date -u +%s) - $1 ))" '$t | todate'; }
# work <id> <assignee> <age-seconds> [merge_result] [branch] [issue_type]
work() { jq -nc --arg id "$1" --arg a "$2" --arg u "$(ago "$3")" --arg mr "${4:-}" \
        --arg br "${5-polecat/$1}" --arg ty "${6:-task}" '
    {id: $id, title: ("work " + $id), status: "open", issue_type: $ty, assignee: $a,
     created_at: $u, updated_at: $u,
     metadata: ((if $br == "" then {} else {branch: $br} end)
                + (if $mr == "" then {} else {merge_result: $mr} end))}'; }
# wisp <id> <assignee> <age-seconds> [status] [title]
wisp() { jq -nc --arg id "$1" --arg a "$2" --arg u "$(ago "$3")" --arg s "${4:-in_progress}" \
        --arg t "${5:-mol-refinery-patrol}" '
    {id: $id, title: $t, status: $s, issue_type: "molecule", ephemeral: true, assignee: $a,
     created_at: $u, updated_at: $u, metadata: {}}'; }
# store <rig> [row...]: the whole store for one rig.
store() { local rig="$1"; shift
    if [ "$#" -eq 0 ]; then printf '[]' > "$STORES/$rig.json"
    else printf '%s\n' "$@" | jq -s '.' > "$STORES/$rig.json"; fi; }
# agent <qualified-name> [running] [suspended]
agent() { jq -nc --arg qn "$1" --argjson r "${2:-true}" --argjson s "${3:-false}" '
    {name: ($qn | split(".") | last), qualified_name: $qn, scope: "rig", running: $r, suspended: $s}'; }
# roster [agent...]: gc status over a fixed rig list, cold being suspended.
roster() { printf '%s\n' "$@" | jq -s --arg tmp "$TMP" '{agents: ., rigs: [
    {name: "alpha", path: ($tmp + "/alpha"), suspended: false},
    {name: "beta",  path: ($tmp + "/beta"),  suspended: false},
    {name: "cold",  path: ($tmp + "/cold"),  suspended: true}]}' > "$STATUS_JSON"; }

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
[ "${1:-}" = "--city" ] && shift 2
case "${1:-} ${2:-}" in
  "status --json")
    rc="${STATUS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$STATUS_JSON" ;;
  "bd list")
    shift 2
    db=""; assignee=""; status=""; type=""; xtype=""; key=""; infra=0; prev=""
    for a in "$@"; do
      case "$prev" in
        --db) db="$a" ;;
        --assignee) assignee="$a" ;;
        --status) status="$a" ;;
        --type) type="$a" ;;
        --exclude-type) xtype="$a" ;;
        --has-metadata-key) key="$a" ;;
      esac
      [ "$a" = "--include-infra" ] && infra=1
      prev="$a"
    done
    rig=$(basename "$(dirname "$db")")
    [ "$rig" = "${BD_FAIL_STORE:-}" ] && exit 3
    [ -n "$type" ] && [ "$rig" = "${BD_WISP_FAIL_STORE:-}" ] && exit 3
    f="$STORES/$rig.json"; [ -f "$f" ] || { printf '[]'; exit 0; }
    jq -c --arg a "$assignee" --arg s "$status" --arg t "$type" --arg x "$xtype" \
          --arg k "$key" --argjson infra "$infra" '
      ($s | split(",") | map(select(. != ""))) as $S
      | [.[] | select($a == "" or .assignee == $a)
             | select(if ($S | length) > 0 then (.status as $st | $S | index($st)) != null
                      else .status != "closed" end)
             | select($t == "" or .issue_type == $t)
             | select($x == "" or .issue_type != $x)
             | select($k == "" or ((.metadata // {}) | has($k)))
             | select($infra == 1 or (.ephemeral // false) == false)]' "$f" ;;
  *) echo "stub gc: unexpected call: $*" >&2; exit 64 ;;
esac
GC
chmod +x "$TMP/bin/gc"

run() { OUT="$(env PATH="$TMP/bin:$PATH" GC_CITY_PATH="$TMP/city" GC_PACK_DIR="$REPO" "$@" bash "$CHECK" 2>&1)"; RC=$?; }

A=alpha/gc-toolkit.refinery; B=beta/gc-toolkit.refinery; C=cold/gc-toolkit.refinery
default_roster() { roster "$(agent "$A")" "$(agent "$B")" "$(agent alpha/gc-toolkit.witness)" \
    "$(agent alpha/gc-toolkit.refinery-2)" "$(agent "$C")"; }
default_roster
store beta "$(wisp be-wisp-idle "$B" 18000)"

echo "── 1. a cycling patrol and an idle one are both healthy ──"
store alpha "$(work tk-old "$A" 5430)" "$(wisp tk-wisp-new "$A" 330)"
run
eq "$RC" "0" "a queue waiting 90m behind a wisp that moved 5m ago is OK"
has "$OUT" "$A: 1 bead(s) wait in its find-work queue, the oldest (tk-old) for 90m; patrol wisp tk-wisp-new moved 5m ago, so the patrol is cycling" \
    "the cycling patrol is named with its wisp, which the stub lists only under --include-infra"
has "$OUT" "$B: find-work queue empty, so a resting patrol is idle" "a 5h-old wisp beside an empty queue reads as idle"
has "$OUT" "$C: skipped (rig cold is suspended" "a refinery on a suspended rig is skipped as a note"
hasnt "$OUT" "witness" "a non-refinery agent is not judged"
hasnt "$OUT" "refinery-2" "a numbered refinery, which the queue is not assigned to, is not judged"

echo "── 2. a stalled patrol beside a waiting queue is an error ──"
store alpha "$(work tk-old "$A" 5430)" "$(work tk-fresh "$A" 150)" "$(wisp tk-wisp-stale "$A" 4230)"
run
eq "$RC" "2" "a queue waiting 90m behind a wisp unmoved for 70m is an error"
has "$OUT" "refinery patrol not cycling (I14): 1 finding(s)" "the summary counts the one stalled refinery"
has "$OUT" "$A: STALLED. 2 bead(s) wait in its find-work queue, the oldest (tk-old) for 90m, and its patrol wisp tk-wisp-stale (in_progress) last moved 70m ago, past the 60m bound." \
    "the finding names the queue, its oldest bead and the stale wisp"
has "$OUT" "Nothing in that queue moves until the patrol cycles" "the finding states the stake"
has "$OUT" "\`gc session peek $A\` shows what it is doing" "a running session is pointed at peek"
has "$OUT" "$B: find-work queue empty" "the healthy refinery beside it is still a note"

echo "── 3. work that just arrived after a long idle is not a stall ──"
store alpha "$(work tk-fresh "$A" 630)" "$(wisp tk-wisp-idle "$A" 18000)"
run
eq "$RC" "0" "a 10m wait behind a 5h-old wisp is inside the bound"
has "$OUT" "$A: 1 bead(s) wait in its find-work queue, the oldest (tk-fresh) for 10m, inside the 60m bound" "the fresh wait is a note"

echo "── 4. no patrol wisp at all ──"
store alpha "$(work tk-old "$A" 5430)"
run
eq "$RC" "2" "a waiting queue with no patrol wisp is an error"
has "$OUT" "$A: STALLED. 1 bead(s) wait in its find-work queue, the oldest (tk-old) for 90m, and no mol-refinery-patrol wisp is assigned to it, so its loop has dropped." \
    "the dropped loop is named"

echo "── 5. a refinery with no running session ──"
roster "$(agent "$A" false)" "$(agent "$B")"
store alpha "$(work tk-old "$A" 5430)" "$(wisp tk-wisp-stale "$A" 4230)"
run
eq "$RC" "2" "the stall is reported whether or not a session is running"
has "$OUT" "gc status reports no running session for it." "the finding says no session is running"
hasnt "$OUT" "gc session peek" "and points at no session that is not there"
default_roster

echo "── 6. what find-work never takes is not queue ──"
store alpha "$(work tk-anchor "$A" 5430 pre_open_gate)" "$(work tk-nobranch "$A" 5430 "" "")" \
    "$(work tk-epic "$A" 5430 "" "polecat/tk-epic" epic)" "$(wisp tk-wisp-stale "$A" 4230)"
run
eq "$RC" "0" "a parked gating anchor, a branchless bead and an epic leave the queue empty"
has "$OUT" "$A: find-work queue empty" "so the stale wisp rests beside an empty queue"

echo "── 7. only this refinery's patrol wisps date its patrol ──"
store alpha "$(work tk-old "$A" 5430)" "$(wisp tk-wisp-stale "$A" 4230)" \
    "$(wisp tk-wisp-foreign lx-wisp-abc 90)" "$(wisp tk-wisp-other "$A" 90 in_progress mol-other-loop)"
run
eq "$RC" "2" "a fresh wisp assigned elsewhere, or titled for another formula, is not movement"
has "$OUT" "its patrol wisp tk-wisp-stale (in_progress) last moved 70m ago" "the stale patrol wisp is the one judged"

echo "── 8. the newest of several wisps dates the patrol ──"
store alpha "$(work tk-old "$A" 5430)" "$(wisp tk-wisp-done "$A" 18000)" "$(wisp tk-wisp-next "$A" 210 open)"
run
eq "$RC" "0" "a finished iteration awaiting burn beside its fresh, unclaimed successor is cycling"
has "$OUT" "patrol wisp tk-wisp-next moved 3m ago" "the successor is the wisp read"

echo "── 9. the bound ──"
store alpha "$(work tk-old "$A" 9030)" "$(wisp tk-wisp-stale "$A" 4230)"
run GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES=120
eq "$RC" "0" "a wisp unmoved for 70m is inside a 120m bound"
run GC_DOCTOR_REFINERY_PATROL_STALL_MINUTES=bogus
eq "$RC" "2" "an unparseable bound falls back to 60m"

echo "── 10. unreadable probes warn, never pass ──"
run STATUS_RC=1
eq "$RC" "1" "an unreadable roster warns"
has "$OUT" "cannot read the city roster" "and says so"
store alpha "$(work tk-old "$A" 5430)" "$(wisp tk-wisp-stale "$A" 4230)"
run BD_FAIL_STORE=alpha
eq "$RC" "1" "an unreadable queue warns"
has "$OUT" "$A: could not list its find-work queue" "naming the refinery it could not check"
has "$OUT" "$B: find-work queue empty" "while the other refinery is still read"
run BD_WISP_FAIL_STORE=alpha
eq "$RC" "1" "an unreadable wisp listing warns rather than reporting a dropped loop"
has "$OUT" "its patrol wisps in $TMP/alpha/.beads could not be listed" "naming the listing that failed"
hasnt "$OUT" "STALLED" "and asserting no stall it could not see"

echo "── 11. the roster ──"
roster "$(agent alpha/gc-toolkit.witness)"
run
eq "$RC" "1" "a roster with agents but no refinery warns"
has "$OUT" "no refinery in the roster" "and says why"
roster
run
eq "$RC" "0" "an empty roster has nothing to check"
roster "$(agent "$A" true true)" "$(agent "$B")"
run
eq "$RC" "0" "a suspended refinery is not judged, stale queue or not"
has "$OUT" "$A: suspended, so its patrol is not expected to cycle" "and is reported as a note"
default_roster

echo "── 12. read-only ──"
others=$(grep -vE '^(--city [^ ]+ )?(status --json|bd list )' "$CALLS" || true)
eq "$others" "" "every call the check made was a status read or a bd list"
hasnt "$(cat "$CALLS")" "$TMP/cold/.beads" "a suspended rig's store is never queried"

echo "── 13. the queue is find-work's queue ──"
FW_BLOCK=$(sed -n '/# >>> find-work-select/,/# <<< find-work-select/p' "$REPO/formulas/mol-refinery-patrol.toml")
FW_FLAGS=$(printf '%s\n' "$FW_BLOCK" | grep 'gc bd list' | grep -oE -- '--[a-z-]+=[^ ]+' \
    | grep -vE -- '^--(rig|assignee|limit)=' || true)
eq "$(printf '%s\n' "$FW_FLAGS" | grep -c -- '^--')" "3" "find-work-select filters on three flags besides rig, assignee and limit"
# Flag-value pairs of the check's queue probe, one per line.
# shellcheck disable=SC2016  # the sed address matches the literal text $(run_bounded in run.sh
PROBE_PAIRS=$(sed -n '/queue_raw=\$(run_bounded/,/--limit 0/p' "$CHECK" | tr '\\\n' '  ' \
    | grep -oE -- '--[a-z-]+ [^ -][^ ]*' || true)
for f in $FW_FLAGS; do
    want="${f%%=*} ${f#*=}"
    case $'\n'"$PROBE_PAIRS"$'\n' in
        *$'\n'"$want"$'\n'*) ok "the queue probe carries find-work's $f" ;;
        *) bad "the queue probe carries find-work's $f (probe pairs: $(printf '%s' "$PROBE_PAIRS" | tr '\n' ','))" ;;
    esac
done
has "$FW_BLOCK" 'select((.metadata.merge_result // "") == "")' "find-work drops a bead carrying merge_result"
has "$(cat "$CHECK")" 'select(((.metadata.merge_result // "") | tostring) == "")' "and so does the check"

echo
echo "── $PASS passed, $FAIL failed ──"
[ "$FAIL" -eq 0 ]
