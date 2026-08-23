#!/usr/bin/env bash
# Hermetic test for doctor/check-human-route-states-the-ask (tk-wfufb9).
#
# THE RULE the check guards: `gc.routed_to=human` means ONLY a human can perform
# the next action, and the writer owes `blocked_reason` naming the judgment
# being asked for. Every pack writer of the marker already sets the pair in one
# update; hand-written routes drop the second half, and the marker then reads as
# a deliberate decision that nobody actually made.
#
# What is exercised here:
#   * the WARNING arm — marker present, ask absent, and the two spellings of
#     absent (key missing, key present but blank);
#   * every shape that must NOT be flagged: an ask that is recorded, a route
#     that is not `human`, and a PADDED " human " (byte equality, so that is a
#     different check question and must not be double-diagnosed here);
#   * the `blocked` arm, which is the reason this is a check and not just board
#     rendering — the helm gather is open-only, so a blocked human bead is on no
#     board anywhere and this line is the only place it is ever said;
#   * the QUERY itself. If `--limit 0`, the `--status` widening or the
#     `key=value` metadata filter drift, the check silently stops seeing beads:
#     the default 50-row window truncates, a bare `--metadata-field` key matches
#     NOTHING, and the open-only default hides every blocked bead;
#   * the fail-CLOSED arms. Every probe that cannot be read must warn, never
#     pass — a store the check could not open hides exactly the beads it exists
#     to find, and reporting OK there reproduces the original defect.
#
# The `bd` stub below is deliberately as strict as the real tool: it answers []
# for a bare `--metadata-field` key, exactly as bd does, so a check that sent one
# would false-empty here the way it would in production rather than passing on a
# stub that was kinder than the thing it stands in for.
#
# No live city, Dolt, network, or beads — only jq, stub `gc`/`bd`, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$CHECK" ] || chmod +x "$CHECK" 2>/dev/null

CITY="$TMP/testcity"
mkdir -p "$CITY" "$TMP/stores" "$TMP/bin"

cat > "$TMP/rigs.json" <<EOF
{"schema_version":"1","ok":true,"rigs":[
  {"name":"testcity","path":"$CITY"},
  {"name":"alpha","path":"$TMP/alpha"},
  {"name":"beta","path":"$TMP/beta"}
]}
EOF

# bead <id> <status> <route> [reason]  — reason omitted means the KEY is absent,
# which is the commonest shape on the live board and is not the same as a key
# present and blank (tested separately below).
bead() {
    local id="$1" st="$2" route="$3"
    if [ "$#" -ge 4 ]; then
        printf '{"id":"%s","status":"%s","title":"t %s","metadata":{"gc.routed_to":"%s","blocked_reason":"%s"}}' \
               "$id" "$st" "$id" "$route" "$4"
    else
        printf '{"id":"%s","status":"%s","title":"t %s","metadata":{"gc.routed_to":"%s"}}' \
               "$id" "$st" "$id" "$route"
    fi
}
store() { # store <name> <bead-json>...
    local name="$1"; shift
    local IFS=,
    printf '[%s]' "$*" > "$TMP/stores/$name.json"
}
clear_stores() { rm -f "$TMP"/stores/*.json; }

# --- Stubs ------------------------------------------------------------------
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list")
      rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"
      cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
chmod +x "$TMP/bin/gc"

# `bd list`: answers per store from $STORES/<rig>.json, keyed off the --db path.
# Every invocation appends its full argv to $BD_ARGS so the query itself can be
# asserted. It also FILTERS the way the real tool does — see the header: a
# metadata filter with no `=` selects nothing, and a status not named by
# --status is excluded. A stub that ignored either would certify a check that
# cannot see half the beads it is looking for.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BD_ARGS"
db=""; mdf=""; statuses=""; prev=""
for a in "$@"; do
  case "$prev" in
    --db) db="$a" ;;
    --metadata-field) mdf="$a" ;;
    --status|-s) statuses="$a" ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
[ "$name" = "${BD_EMPTY_STORE:-}" ] && exit 0
f="$STORES/$name.json"
[ -f "$f" ] || { printf '[]'; exit 0; }
# Served VERBATIM: real `bd --json` emits bead text with control characters
# UNESCAPED, which is not valid JSON and is exactly what the check strips before
# parsing. A stub that filtered such a store through jq would die on it here and
# never let the check see the payload it exists to survive.
[ "$name" = "${BD_RAW_STORE:-}" ] && { cat "$f"; exit 0; }
# A bare key (no `=`) matches nothing, exactly as bd does.
case "$mdf" in
  *=*) key="${mdf%%=*}"; val="${mdf#*=}" ;;
  *)   printf '[]'; exit 0 ;;
esac
# BD_LENIENT models a server-side matcher that NORMALIZES before comparing —
# which real bd does not, but which the check must not depend on it not doing.
# Under it a padded " human " comes back from the query, and the check has to
# refuse it on its own.
jq -c --arg k "$key" --arg v "$val" --arg st "$statuses" --arg lax "${BD_LENIENT:-}" \
   '($st | split(",")) as $ok
    | [ .[] | select(((.metadata[$k] // "") | if $lax == "" then . else (sub("^ +";"") | sub(" +$";"")) end) == $v)
            | select(.status as $s | ($ok | index($s)) != null) ]' "$f"
BD
chmod +x "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"
export STORES="$TMP/stores"
BD_ARGS="$TMP/bd-args.log"
export BD_ARGS

run_check() {
    : > "$BD_ARGS"
    RIGS_JSON="${RIGS_JSON_OVERRIDE:-$TMP/rigs.json}" \
    GC_PACK_DIR="$ROOT" bash "$CHECK" 2>&1
}

# --- 0. Positive control ----------------------------------------------------
# Prove the fixture and the stub are real before trusting any verdict computed
# from them. A stub that answered [] to everything would make every clean case
# pass for the wrong reason — the exact fail-open this check exists to remove.
store alpha "$(bead a-x open human)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "positive control: the harness can produce a finding at all"
has "$OUT" "a-x" "positive control: …and the finding names the fixture bead"
clear_stores
OUT=$(run_check); RC=$?
eq "$RC" "0" "positive control: an empty city is clean, so findings are not constant"

# --- 1. The WARNING arm, both spellings of a missing ask ---------------------
store alpha "$(bead a-1 open human)" "$(bead a-2 open human '   ')"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a human route with no ask WARNS (it is a debt, not a break)"
has "$OUT" "a-1" "…naming the bead whose blocked_reason key is absent"
has "$OUT" "a-2" "…and the bead whose blocked_reason is present but blank"
has "$OUT" "2 bead(s)" "…and counting both"
has "$OUT" "docs/gascity-routing-model.md" "…and citing the rule it enforces"
clear_stores

# --- 2. What must NOT be flagged --------------------------------------------
store alpha \
  "$(bead a-ok open human 'land as-is, split the findings, or abandon')" \
  "$(bead a-pool open alpha/pack.polecat)" \
  "$(bead a-pad open ' human ')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a recorded ask, a pool route and a PADDED sentinel are all clean here"
hasnt "$OUT" "a-ok" "…the ask was stated, so the check has nothing to say"
hasnt "$OUT" "a-pool" "…a non-human route belongs to check-routed-work-claimable"
# Byte equality, like every reader of the marker. Padding is that sibling
# check finding; diagnosing it twice would give one bead two repairs.
hasnt "$OUT" "a-pad" "…and a padded route is NOT a finding here"

# …and the check refuses it ON ITS OWN, not because the query happened to.
# Under a matcher that normalizes, the padded bead comes back and the check has
# to reject it itself — otherwise one bead gets two diagnoses and two repairs.
OUT=$(BD_LENIENT=1 run_check); RC=$?
eq "$RC" "0" "…even when the query itself hands the padded route back"
hasnt "$OUT" "a-pad" "…because the check re-asserts byte equality after the filter"
clear_stores

# --- 3. The blocked arm — invisible to every board --------------------------
store alpha "$(bead a-blk blocked human)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a BLOCKED human bead with no ask is flagged too"
has "$OUT" "a-blk" "…named"
has "$OUT" "no helm board shows it either" \
    "…and told apart, because the helm gather is open-only"
clear_stores

# --- 4. The query itself ----------------------------------------------------
# Each of these, dropped, silently shrinks what the check can see: the default
# 50-row window truncates a real ledger, the open-only default hides every
# blocked bead, and a bare metadata key matches nothing at all.
store alpha "$(bead a-q open human)"
OUT=$(run_check)
ARGS=$(cat "$BD_ARGS")
has "$ARGS" "--limit 0" "the listing is uncapped (the 50-row default drops findings)"
has "$ARGS" "--status open,blocked" "…covers both statuses the marker is written on"
has "$ARGS" "--metadata-field gc.routed_to=human" "…and filters server-side on key=value"
has "$ARGS" "--db $TMP/alpha/.beads" "…once per store, by path"
eq "$(grep -c -- '--status open,blocked' "$BD_ARGS")" "3" \
   "…and every store in the city is scanned, city root included"

# The comma form is load-bearing: bd keeps only the LAST of repeated --status
# flags, so a split spelling would silently drop `open` and report nothing.
hasnt "$ARGS" "--status open --status blocked" \
      "the statuses are one comma-joined value, not repeated flags"
clear_stores

# --- 5. Fail-CLOSED: every unreadable probe warns ---------------------------
store alpha "$(bead a-1 open human)"

OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list WARNS rather than passing"
has "$OUT" "no set of bead stores to scan" "…and says why"

printf '{"schema_version":"1","ok":true,"rigs":[]}' > "$TMP/rigs-empty.json"
OUT=$(RIGS_JSON_OVERRIDE="$TMP/rigs-empty.json" run_check); RC=$?
eq "$RC" "1" "a rig list with no paths WARNS"
has "$OUT" "listed no rig paths" "…and says why"

OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store that errors WARNS"
has "$OUT" "alpha: could not list human-routed beads" "…naming the store"
has "$OUT" "was NOT checked" "…and saying plainly that it was not checked"

OUT=$(BD_EMPTY_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a store answering NOTHING is not the same as answering []"
has "$OUT" "returned no output" "…and warns rather than reading it as clean"

# A store that errors must not swallow the findings of the stores that answered.
store beta "$(bead b-1 open human)"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
has "$OUT" "b-1" "a failed store does not suppress another store findings"
has "$OUT" "was NOT checked" "…and both are reported together"
clear_stores

# --- 6. Payload safety ------------------------------------------------------
# A title carrying control characters must not break jq mid-store, and must not
# be able to forge the 0x1F the rows are joined on.
# printf expands both escapes, so these reach the file as RAW bytes inside a
# JSON string — invalid JSON, and the shape bd actually emits.
printf '[{"id":"a-ctl","status":"open","title":"tab\ttab and a US \037 here","metadata":{"gc.routed_to":"human"}}]' \
    > "$TMP/stores/alpha.json"
OUT=$(BD_RAW_STORE=alpha run_check); RC=$?
eq "$RC" "1" "a title carrying control characters still yields its finding"
has "$OUT" "a-ctl" "…with the bead named"
has "$OUT" "1 bead(s)" "…exactly once, so no smuggled separator split the row"
clear_stores

# --- 7. The clean city ------------------------------------------------------
store alpha "$(bead a-ok open human 'operator call on a destructive prune')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a city whose human routes all state their ask passes"
has "$OUT" "OK: every human-routed bead states the judgment" "…and says so"

echo ""
echo "check-human-route-states-the-ask: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
