#!/usr/bin/env bash
# Hermetic test for doctor/check-step-terminal (I8). Stub gc/bd only.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }
ge()  { if [ "$1" -ge "$2" ]; then ok "$3"; else bad "$3 (got '$1' want >= '$2')"; fi; }
lt()  { if [ "$1" -lt "$2" ]; then ok "$3"; else bad "$3 (got '$1' want < '$2')"; fi; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# Models the surface the check actually calls: the open-step listing, the
# id-scoped root listing (which DROPS ids it cannot resolve, exactly as bd
# does, so the check's own id-set comparison is what has to catch them), the
# --status pushdown, and `bd count`. Every --id argument is logged so the
# argv bound can be asserted rather than assumed.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
cmd="$1"; db=""; ids=""; status=""; prev=""
for a in "$@"; do
  case "$prev" in --db) db="$a" ;; --id) ids="$a" ;; --status|-s) status="$a" ;; esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
roots_f="$STORES/$name.roots.json"
steps_f="$STORES/$name.steps.json"
empty='{"issues":[],"meta":{"count":0},"schema_version":1}'
if [ -n "$ids" ]; then
  [ -n "${BD_ROOTS_FAIL:-}" ] && exit 3
  [ -n "${BD_ARGV_LOG:-}" ] && printf '%s\n' "${#ids}" >> "$BD_ARGV_LOG"
  if [ "$cmd" = "count" ]; then
    [ -n "${BD_COUNT_FAIL:-}" ] && exit 3
    [ -f "$roots_f" ] || { echo 0; exit 0; }
    jq --arg ids "$ids" '($ids|split(",")|map({key:.,value:true})|from_entries) as $w
        | [ .[] | select($w[.id] // false) ] | length' "$roots_f"
    exit 0
  fi
  [ -f "$roots_f" ] || { printf '%s' "$empty"; exit 0; }
  jq -c --arg ids "$ids" --arg st "$status" \
      '($ids|split(",")|map({key:.,value:true})|from_entries) as $w
       | [ .[] | select($w[.id] // false)
               | select($st == "" or (.status == $st)) ]
       | {issues: ., meta: {count: length}, schema_version: 1}' "$roots_f"
  exit 0
fi
[ -f "$steps_f" ] || { printf '%s' "$empty"; exit 0; }
jq -c '{issues: ., meta: {count: length}, schema_version: 1}' "$steps_f"
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
iso_ago() { date -u -d "@$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
step() { # id root [extra-metadata-json-fragment] [top-level-fragment]
    printf '{"id":"%s","status":"open"%s,"metadata":{"gc.root_bead_id":"%s"%s}}' \
        "$1" "${4:-}" "$2" "${3:-}"
}
steps()  { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.steps.json"; }
roots()  { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.roots.json"; }
clear_fixtures() { rm -f "$TMP/stores/alpha.steps.json" "$TMP/stores/alpha.roots.json"; }

OLD="$(iso_ago 7200)"       # 2h ago — well past the 300s grace
FRESH="$(iso_ago 10)"       # inside the grace window
RECENT="$(iso_ago 3600)"    # 1h — inside the 48h stall bound
STALE="$(iso_ago 259200)"   # 72h — past the 48h stall bound

# --- 1. live molecule, recently touched: clean ---------------------------------
steps "$(step s-1 r-1 ",\"updated_at\":\"$RECENT\"" "")"
roots "{\"id\":\"r-1\",\"status\":\"open\"}"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an open step under an open, recently-touched root is clean"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. NEVER-CLOSED: open step under a closed root -----------------------------
steps "$(step s-2 r-2)" "$(step s-3 r-2)"
roots "{\"id\":\"r-2\",\"status\":\"closed\",\"closed_at\":\"$OLD\"}"
OUT=$(run_check); RC=$?
eq "$RC" "2" "open steps under a closed root are an ERROR"
has "$OUT" "r-2" "the molecule is named"
has "$OUT" "s-2, s-3" "the steps are grouped into ONE finding per molecule"
has "$OUT" "never closed" "the never-closed shape is called out"

# --- 3. REOPENED: the step already carries gc.outcome ----------------------------
steps "$(step s-4 r-3 ',"gc.outcome":"pass"')"
roots "{\"id\":\"r-3\",\"status\":\"closed\",\"closed_at\":\"$OLD\"}"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a reopened completed step under a closed root is an ERROR"
has "$OUT" "gc.outcome" "the reopened shape is distinguished from never-closed"
has "$OUT" "RESET" "the finding says the step was reset after completing"

# --- 4. the settle grace window ---------------------------------------------------
steps "$(step s-5 r-4)"
roots "{\"id\":\"r-4\",\"status\":\"closed\",\"closed_at\":\"$FRESH\"}"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a root closed seconds ago is finalize-in-progress, not a strand"
has "$OUT" "settle" "the settle window is noted, not silent"

# --- 5. a root with an unparseable closed_at gets NO grace -------------------------
steps "$(step s-6 r-5)"
roots "{\"id\":\"r-5\",\"status\":\"closed\",\"closed_at\":\"not-a-time\"}"
OUT=$(run_check); RC=$?
eq "$RC" "2" "an unreadable closed_at does not buy the settle exemption"

# --- 6. STALL: open root, step untouched past the bound ----------------------------
steps "$(step s-7 r-6 ",\"x\":\"y\"" ",\"updated_at\":\"$STALE\"")"
roots "{\"id\":\"r-6\",\"status\":\"open\"}"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an open step under an OPEN root untouched past the bound is a WARNING"
has "$OUT" "48h" "the stall bound is named"
has "$OUT" "s-7" "the stalled step is named"
OUT=$(GC_DOCTOR_STEP_STALL_HOURS=100 RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "0" "the stall bound is env-tunable (100h clears a 72h-old step)"

# --- 7. unresolved root: note, not verdict -------------------------------------------
steps "$(step s-8 r-elsewhere ',"gc.root_store_ref":"other-rig"')"
roots ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a root resolving nowhere is a note (cross-store roots are legitimate)"
has "$OUT" "reported, not judged" "the unresolved root is still reported"

# --- 8. fail-CLOSED --------------------------------------------------------------
clear_fixtures
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
steps "$(step s-9 r-9)"
roots "{\"id\":\"r-9\",\"status\":\"open\"}"
OUT=$(BD_ROOTS_FAIL=1 run_check); RC=$?
eq "$RC" "1" "a failed root resolution warns — a partial root map must not pass"
has "$OUT" "NOT checked" "the warning says the store was skipped"
OUT=$(BD_COUNT_FAIL=1 run_check); RC=$?
eq "$RC" "1" "a failed existence probe warns — an unproven root set must not pass"
has "$OUT" "NOT checked" "the failed existence probe says the store was skipped"
clear_fixtures

# --- 9. a step whose root id is blank is not a root ----------------------------------
steps '{"id":"s-10","status":"open","metadata":{"gc.root_bead_id":"   "}}'
roots ""
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blank gc.root_bead_id names no molecule and raises nothing"
hasnt "$OUT" "NOT checked" "a blank root id is not a broken probe"

# --- 10. SCALE: more molecules than a materialized root map can carry ------------------
# The rejected shape passed every root through one argv string, which Linux caps
# at MAX_ARG_STRLEN (131072) regardless of ARG_MAX. The fixture is sized past
# that cap with every bead small, so molecule COUNT alone is what breaches it —
# trimming fields would not save a design that still materializes the map.
N=3000
jq -cn --argjson n "$N" '[range(0;$n) | {id: ("r-" + (.|tostring)), status: "open", closed_at: ""}]' \
    > "$TMP/stores/alpha.roots.json"
jq -cn --argjson n "$N" --arg ua "$RECENT" '[range(0;$n)
    | {id: ("s-" + (.|tostring)), status: "open", updated_at: $ua,
       metadata: {"gc.root_bead_id": ("r-" + (.|tostring))}}]' \
    > "$TMP/stores/alpha.steps.json"
MAPBYTES=$(wc -c < "$TMP/stores/alpha.roots.json")
ge "$MAPBYTES" "131073" "the fixture's root map alone exceeds MAX_ARG_STRLEN ($MAPBYTES bytes, $N small molecules)"

ARGV_LOG="$TMP/argv.log"; : > "$ARGV_LOG"
OUT=$(BD_ARGV_LOG="$ARGV_LOG" run_check); RC=$?
eq "$RC" "0" "$N healthy molecules return a real verdict, not a skipped store"
has "$OUT" "OK:" "the verdict at scale is the OK line"
hasnt "$OUT" "NOT checked" "the store past the old cap is CHECKED, not skipped"

# --- 11. the same scale still distinguishes real defects --------------------------------
jq -c --arg old "$OLD" '(.[0] | .status) = "closed" | (.[0] | .closed_at) = $old
    | (.[1] | .status) = "closed" | (.[1] | .closed_at) = $old' \
    "$TMP/stores/alpha.roots.json" > "$TMP/stores/alpha.roots.json.new"
mv "$TMP/stores/alpha.roots.json.new" "$TMP/stores/alpha.roots.json"
OUT=$(run_check); RC=$?
eq "$RC" "2" "two strands hidden among $N molecules are still an ERROR"
has "$OUT" "2 molecule(s)" "both strands are found, and only those two"
has "$OUT" "s-0" "the stranded step under the first closed root is named"
has "$OUT" "s-1." "the stranded step under the second closed root is named"

# --- 12. the argv bound holds regardless of molecule count -------------------------------
# Every id set handed to bd is one batch, so the widest argument the check can
# build is fixed by GC_DOCTOR_ROOT_CHUNK and not by the store.
WIDEST=$(sort -rn "$ARGV_LOG" | head -1)
CALLS=$(wc -l < "$ARGV_LOG")
lt "$WIDEST" "16384" "the widest --id argument across $CALLS lookups is $WIDEST bytes, far below the 131072 cap"
ge "$CALLS" "2" "the roots were resolved in batches, not one sweep"
: > "$ARGV_LOG"
OUT=$(BD_ARGV_LOG="$ARGV_LOG" GC_DOCTOR_ROOT_CHUNK=10 RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1)
WIDEST10=$(sort -rn "$ARGV_LOG" | head -1)
lt "$WIDEST10" "$WIDEST" "a smaller batch size narrows the widest argument ($WIDEST10 < $WIDEST), so the bound is the batch"
clear_fixtures

# --- 13. a closed root and an absent root inside ONE batch -----------------------------
# Classification reads root_missing before root_closed, and the existence probe
# runs only when a batch comes back short a row. A batch carrying both defects is
# what proves the probe names the absent id rather than condemning the whole short
# batch: were the closed root swept in with it, every strand would downgrade from
# an error to an orphan note and I8 would go quiet on the defect it exists to find.
steps "$(step s-11 r-closed)" "$(step s-12 r-gone ',"gc.root_store_ref":"other-rig"')"
roots "{\"id\":\"r-closed\",\"status\":\"closed\",\"closed_at\":\"$OLD\"}"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a closed root batched with an absent one is still an ERROR"
has "$OUT" "yet 1 step(s) never closed — s-11." "the strand keeps its verdict and names only its own step"
has "$OUT" "open step(s) s-12 name root r-gone" "the absent root beside it is still reported as a note"
has "$OUT" "1 molecule(s)" "the absent root did not become a second error"
clear_fixtures

echo
echo "check-step-terminal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
