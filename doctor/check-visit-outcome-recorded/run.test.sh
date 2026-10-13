#!/usr/bin/env bash
# Hermetic test for doctor/check-visit-outcome-recorded. Stub gc/bd only; no
# city, no network. A CLOSED visit (task_kind=visit) must carry a non-empty
# gc.outcome; an open visit, a non-visit, and a stamped closed visit are all out
# of scope. Every store is read at once, and a store whose read fails, is cut by
# the budget, or answers with something other than one JSON array is reported
# as NOT checked.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-visit-outcome-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "check-visit-outcome-recorded: jq is required" >&2; exit 1; }

mkdir -p "$TMP/bin" "$TMP/stores"
# rigs <name[:suspended]>... — the rig list the check enumerates
rigs() {
  local r name sus sep="" body=""
  for r in "$@"; do
    name="${r%%:*}"; sus=false
    [ "$r" = "$name:suspended" ] && sus=true
    mkdir -p "$TMP/$name"
    body="$body$sep$(jq -nc --arg n "$name" --arg p "$TMP/$name" --argjson s "$sus" '{name:$n,path:$p,suspended:$s}')"
    sep=","
  done
  printf '{"rigs":[%s]}\n' "$body" > "$TMP/rigs.json"
}
rigs alpha
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
case "$1 $2" in
  "rig list")
    rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# Deliberately looser than bd: it serves the whole store whatever the query
# filters on, so a fixture can feed the check rows the real `--status closed
# --metadata-field task_kind=visit` would have withheld. That is what proves the
# check's own visit/closed/outcome predicate rather than the query's.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
printf '%s\n' "$*" >> "${BD_ARGS:-/dev/null}"
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
# A barrier: each read waits here until BD_BARRIER_N reads have started, and
# fails once it has waited 20s. A check that reads its stores one at a time
# never has two reads started, so none of its reads gets past.
if [ -n "${BD_BARRIER_DIR:-}" ]; then
  : > "$BD_BARRIER_DIR/$name"
  waited=0
  while set -- "$BD_BARRIER_DIR"/*; [ "$#" -lt "$BD_BARRIER_N" ]; do
    [ "$waited" -lt 200 ] || exit 3
    sleep 0.1; waited=$((waited + 1))
  done
fi
[ "$name" = "${BD_SLOW_STORE:-}" ] && sleep "$BD_SLOW_SECS"
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
if [ "$name" = "${BD_BAD_STORE:-}" ]; then
  printf '%s' "$BD_BAD_OUTPUT"
else
  f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
fi
printf '%s\n' "$name" >> "${BD_DONE:-/dev/null}"
# A read can answer in full and still fail, the way a cut read leaves a
# listing behind.
[ "$name" = "${BD_EXIT_AFTER_STORE:-}" ] && exit 3
exit 0
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
mkdir -p "$TMP/tmpdir"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" BD_ARGS="$TMP/bd-args.log" BD_DONE="$TMP/bd-done.log"
# The check's own TMPDIR is a directory of its own, so the suite can see what a
# run leaves behind.
run_check() { : > "$BD_ARGS"; : > "$BD_DONE"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" TMPDIR="${CHECK_TMPDIR:-$TMP/tmpdir}" bash "$CHECK" 2>&1; }
# line_of <text> <needle> — the number of the first line of <text> holding <needle>
line_of() { printf '%s\n' "$1" | grep -n -F -- "$2" | head -1 | cut -d: -f1; }

# vis <id> <status> <outcome|ABSENT|EMPTY> — a visit bead
vis() {
  local md
  case "$3" in
    ABSENT) md='{"task_kind":"visit"}' ;;
    EMPTY)  md='{"task_kind":"visit","gc.outcome":""}' ;;
    *)      md=$(jq -nc --arg o "$3" '{task_kind:"visit","gc.outcome":$o}') ;;
  esac
  jq -nc --arg id "$1" --arg st "$2" --argjson md "$md" \
    '{id:$id,status:$st,title:("visit: "+$id),metadata:$md}'
}
# obs <id> — a closed observation (task_kind, but not a visit)
obs() { jq -nc --arg id "$1" '{id:$id,status:"closed",title:"obs",metadata:{task_kind:"observation"}}'; }
# store_in <name> <bead>... — that store's whole contents; store <bead>... is alpha's
store_in() { local name="$1" IFS=,; shift; printf '[%s]' "$*" > "$TMP/stores/$name.json"; }
store() { store_in alpha "$@"; }

echo "── shipped executable and valid bash ──"
[ -x "$CHECK" ] && ok "run.sh is executable" || bad "run.sh is executable (chmod +x it)"
bash -n "$CHECK" && ok "run.sh: valid bash" || bad "run.sh: valid bash"

echo "── a store whose every closed visit is stamped passes ──"
store "$(vis v-1 closed moot)" "$(vis v-2 closed folded)" "$(vis v-3 in_progress ABSENT)" "$(obs o-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "all closed visits stamped (plus an open one and an observation) passes"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--status closed" "the read asks for closed beads only"
has "$ARGS" "--metadata-field task_kind=visit" "and only for visits"
has "$ARGS" "--brief" "and leaves out their free text"
has "$ARGS" "--all" "--all rides with --status, since bd list hides pinned beads from a --status listing without it"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"
has "$ARGS" "--include-gates" "hidden categories are included, since a hidden visit holds an outcome too"
has "$ARGS" "--include-infra" "infrastructure beads are included"
has "$ARGS" "--include-templates" "template beads are included"

echo "── a closed visit with no gc.outcome is a WARNING and is named ──"
store "$(vis v-1 closed moot)" "$(vis v-miss closed ABSENT)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a closed visit missing gc.outcome is a warning, not an error"
has "$OUT" "v-miss" "the unstamped closed visit is named"
has "$OUT" "1 " "the headline carries the count"
hasnt "$OUT" "v-1" "the stamped visit is not flagged"

echo "── an EMPTY gc.outcome counts as unrecorded ──"
store "$(vis v-empty closed EMPTY)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "gc.outcome=\"\" is treated as no outcome"
has "$OUT" "v-empty" "the empty-outcome visit is named"

echo "── an OPEN visit and a non-visit are out of scope ──"
store "$(vis v-open open ABSENT)" "$(obs o-2)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open visit and a closed observation, both without gc.outcome, do not warn"
has "$OUT" "OK:" "and it reports OK"

echo "── a store that cannot be read warns, never passes ──"
store "$(vis v-1 closed moot)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store is a warning"
has "$OUT" "NOT checked" "and it says the store was not checked"
OUT=$(BD_EXIT_AFTER_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a read that prints a whole listing and then fails is a warning too"
has "$OUT" "alpha: could not list closed visits in $TMP/alpha/.beads (rc=3) — this store was NOT checked" "its listing is not judged"

echo "── a listing that is not one JSON array is unreadable, never an empty store ──"
for shape in '{}' '[] []' '"[]"'; do
  OUT=$(BD_BAD_STORE=alpha BD_BAD_OUTPUT="$shape" run_check); RC=$?
  eq "$RC" "1" "a store answering $shape warns"
  has "$OUT" "could not be parsed — this store was NOT checked" "and says $shape left the store unchecked"
done

echo "── rig enumeration failure fails closed ──"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` cannot pass"
has "$OUT" "cannot determine" "and it says why"

echo "── no scratch directory, no pass ──"
OUT=$(CHECK_TMPDIR="$TMP/no-such-dir" run_check); RC=$?
eq "$RC" "1" "a check that cannot make the scratch its reads land in warns"
has "$OUT" "could not create a scratch directory" "and it says why"
eq "$(cat "$BD_ARGS")" "" "and it reads no store"

echo "── the detail list caps, and the headline count is the true total ──"
args=(); i=0
while [ "$i" -lt 30 ]; do args+=("$(vis "v-m$i" closed ABSENT)"); i=$((i + 1)); done
store "${args[@]}"
OUT=$(GC_DOCTOR_VISIT_OUTCOME_DETAILS=5 run_check); RC=$?
eq "$RC" "1" "30 unstamped closed visits warn"
has "$OUT" "30 across" "the headline count is the true total, not the printed cap"
has "$OUT" "and 25 more" "the detail list caps and says how many it withheld"

echo "── every store is read at once ──"
rigs alpha beta gamma delta
for s in alpha beta gamma delta; do store_in "$s" "$(vis "v-$s" closed moot)"; done
mkdir -p "$TMP/barrier"
OUT=$(BD_BARRIER_DIR="$TMP/barrier" BD_BARRIER_N=4 run_check); RC=$?
eq "$RC" "0" "four reads that each wait for all four to start finish clean"
has "$OUT" "across 4 store(s)" "and every store is checked"
eq "$(grep -c . "$BD_ARGS")" "4" "each store is read exactly once"

echo "── a suspended store is noted, and never read ──"
rigs alpha beta:suspended
store_in alpha "$(vis v-alpha closed moot)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a suspended store does not fail the check"
has "$OUT" "beta: skipped (suspended" "the suspended store is named"
hasnt "$(cat "$BD_ARGS")" "$TMP/beta/.beads" "and its store is not queried"
has "$OUT" "across 1 store(s)" "the checked count leaves it out"

echo "── the report keeps rig order, however the reads finish ──"
rigs alpha beta
store_in alpha "$(vis v-alpha closed ABSENT)"
store_in beta "$(vis v-beta closed ABSENT)"
OUT=$(BD_SLOW_STORE=alpha BD_SLOW_SECS=2 run_check); RC=$?
eq "$(tr '\n' ' ' < "$BD_DONE")" "beta alpha " "premise: beta's read finished first"
eq "$RC" "1" "two unstamped visits warn"
LA=$(line_of "$OUT" "v-alpha"); LB=$(line_of "$OUT" "v-beta")
if [ -n "$LA" ] && [ -n "$LB" ] && [ "$LA" -lt "$LB" ]; then ok "alpha's finding is reported before beta's, in rig order"
else bad "alpha's finding is reported before beta's, in rig order (alpha line '${LA}', beta line '${LB}')"; fi

echo "── a store whose read fails is named, and the others are still judged ──"
rigs alpha beta gamma
store_in alpha "$(vis v-alpha closed ABSENT)"
store_in beta "$(vis v-beta closed ABSENT)"
store_in gamma "$(vis v-gamma closed moot)"
OUT=$(BD_FAIL_STORE=beta run_check); RC=$?
eq "$RC" "1" "a failed store among readable ones warns"
has "$OUT" "v-alpha" "a finding in another store is still reported"
hasnt "$OUT" "v-beta" "nothing is reported from the store that was not read"
has "$OUT" "beta: could not list closed visits in $TMP/beta/.beads (rc=3) — this store was NOT checked" "the failed store is named, with its rc"
has "$OUT" "across 2 store(s)" "the checked count leaves it out"

echo "── a read cut by the budget is named, and does not starve the others ──"
rigs alpha beta gamma
for s in alpha beta gamma; do store_in "$s" "$(vis "v-$s" closed moot)"; done
S=$(date +%s)
OUT=$(BD_SLOW_STORE=beta BD_SLOW_SECS=60 GC_DOCTOR_CHECK_TIMEOUT=12 run_check); RC=$?
E=$(( $(date +%s) - S ))
if [ "$E" -lt 12 ]; then ok "the check returns inside its 12s budget (took ${E}s)"
else bad "the check returns inside its 12s budget (took ${E}s)"; fi
eq "$RC" "1" "a store the budget cut warns"
has "$OUT" "beta: could not list closed visits in $TMP/beta/.beads (rc=124) — this store was NOT checked" "the wedged store is named as cut"
has "$OUT" "across 2 store(s)" "the stores read beside it are still checked"
has "$OUT" "doctor budget before every probe ran" "and it says the budget, not the data, ended the run"

echo "── every run removes its scratch ──"
eq "$(ls -A "$TMP/tmpdir")" "" "no run above left anything in its TMPDIR"

echo
echo "check-visit-outcome-recorded: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
