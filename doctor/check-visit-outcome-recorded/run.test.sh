#!/usr/bin/env bash
# Hermetic test for doctor/check-visit-outcome-recorded. Stub gc/bd only; no
# city, no network. A CLOSED visit (task_kind=visit) must carry a non-empty
# gc.outcome; an open visit, a non-visit, and a stamped closed visit are all out
# of scope.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
    rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# Deliberately looser than bd: it serves the whole store whatever the query
# filters on, so a fixture can feed the check rows the real `--has-metadata-key`
# would have withheld. That is what proves the check's own visit/closed/outcome
# predicate rather than the query's.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
printf '%s\n' "$*" >> "${BD_ARGS:-/dev/null}"
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores" BD_ARGS="$TMP/bd-args.log"
run_check() { : > "$BD_ARGS"; RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }

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
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }

echo "── shipped executable and valid bash ──"
[ -x "$CHECK" ] && ok "run.sh is executable" || bad "run.sh is executable (chmod +x it)"
bash -n "$CHECK" && ok "run.sh: valid bash" || bad "run.sh: valid bash"

echo "── a store whose every closed visit is stamped passes ──"
store "$(vis v-1 closed moot)" "$(vis v-2 closed folded)" "$(vis v-3 in_progress ABSENT)" "$(obs o-1)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "all closed visits stamped (plus an open one and an observation) passes"
has "$OUT" "OK:" "the pass message is the OK line"
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--all" "the scan spans every status"
has "$ARGS" "--has-metadata-key task_kind" "task_kind is the candidate net"
has "$ARGS" "--limit 0" "the scan is not truncated by a default limit"
has "$ARGS" "--include-gates" "hidden categories are included, since a hidden visit holds an outcome too"

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

echo "── rig enumeration failure fails closed ──"
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` cannot pass"
has "$OUT" "cannot determine" "and it says why"

echo "── the detail list caps, and the headline count is the true total ──"
args=(); i=0
while [ "$i" -lt 30 ]; do args+=("$(vis "v-m$i" closed ABSENT)"); i=$((i + 1)); done
store "${args[@]}"
OUT=$(GC_DOCTOR_VISIT_OUTCOME_DETAILS=5 run_check); RC=$?
eq "$RC" "1" "30 unstamped closed visits warn"
has "$OUT" "30 across" "the headline count is the true total, not the printed cap"
has "$OUT" "and 25 more" "the detail list caps and says how many it withheld"

echo
echo "check-visit-outcome-recorded: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
