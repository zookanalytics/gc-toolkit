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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
if [ "$1" = "show" ]; then
  [ -n "${BD_SHOW_FAIL:-}" ] && exit 3
  f="$STORES/$name.show.json"
  if [ -f "$f" ]; then cat "$f"; else printf '{"error":"no issues found matching the provided IDs"}'; fi
  exit 0
fi
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
iso_ago() { date -u -d "@$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
step() { # id root [extra-metadata-json-fragment] [top-level-fragment]
    printf '{"id":"%s","status":"open"%s,"metadata":{"gc.root_bead_id":"%s"%s}}' \
        "$1" "${4:-}" "$2" "${3:-}"
}
steps()  { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }
roots()  { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.show.json"; }
clear_fixtures() { rm -f "$TMP/stores/alpha.json" "$TMP/stores/alpha.show.json"; }

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
printf '{"error":"no issues found matching the provided IDs"}' > "$TMP/stores/alpha.show.json"
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
OUT=$(BD_SHOW_FAIL=1 run_check); RC=$?
eq "$RC" "1" "a failed root resolution warns — a partial root map must not pass"
has "$OUT" "NOT checked" "the warning says the store was skipped"
clear_fixtures

# --- 9. the root map must never cross jq's argv boundary -------------------------
# MAX_ARG_STRLEN caps a SINGLE argv string at 131072 B independently of ARG_MAX,
# and `bd show` answers each root's full description and notes. The fixture holds
# a REAL finding under the oversized map because the failure mode is a silent
# clean pass on the busiest store, not a crash.
gt() { if [ "$1" -gt "$2" ]; then ok "$3"; else bad "$3 (got '$1', want > '$2')"; fi; }
FAT=$(head -c 200000 /dev/zero | tr '\0' 'x')
# Padding in description/notes: the projection drops it, so §9 alone does not
# prove the staging file — §10 does.
root_fat() { # root_fat <id> <status> <closed_at>
    printf '{"id":"%s","status":"%s","closed_at":"%s","description":"%s","notes":"%s"}' \
        "$1" "$2" "$3" "$FAT" "$FAT"
}

steps "$(step s-10 r-10)"
roots "$(root_fat r-10 closed "$OLD")"
gt "$(wc -c < "$TMP/stores/alpha.show.json" | tr -d ' ')" 131072 \
   "positive control: the root fixture really does exceed MAX_ARG_STRLEN"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a root map larger than the argv cap is still JOINED, not skipped"
has "$OUT" "s-10" "the finding under an oversized root map is reported"
has "$OUT" "r-10" "the finalized molecule is named"
hasnt "$OUT" "could not be computed" "the join is not reported as uncomputable"
hasnt "$OUT" "NOT checked" "the oversized store is not reported as unchecked"

# The same cap falls on the ACCUMULATOR: batching the ids bounds what goes OUT
# to `bd show`, nothing bounds the map coming BACK.
steps "$(step s-11 r-11 ',"gc.outcome":"pass"')" "$(step s-12 r-12)"
roots "$(root_fat r-11 closed "$OLD")" "$(root_fat r-12 closed "$OLD")"
OUT=$(GC_DOCTOR_ROOT_CHUNK=1 RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "the root map survives being accumulated one chunk at a time"
has "$OUT" "s-11" "the reopened step under a fat multi-chunk map is reported"
has "$OUT" "s-12" "the never-closed step under a fat multi-chunk map is reported"
hasnt "$OUT" "could not resolve molecule roots" "accumulating fat roots is not a failed probe"
hasnt "$OUT" "NOT checked" "a chunked fat root map does not skip the store"

# A fat root that is HEALTHY must stay quiet: the projection must not manufacture
# a finding by dropping the status the join filters on.
steps "$(step s-13 r-13 "" ",\"updated_at\":\"$RECENT\"")"
roots "$(root_fat r-13 in_progress "")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an oversized root map for a LIVE molecule still passes"
hasnt "$OUT" "s-13" "the live molecule's step is not named as a finding"
clear_fixtures

# --- 10. ...and molecule COUNT alone breaches it, with no fat bead in sight ------
# Every bead small, simply a lot of them, so the map is over the cap even after
# projection. That is what makes the staging file load-bearing: a projection-only
# fix passes §9 and puts the check back to skipping the busiest store.
MANY=2500
jq -nc --arg ca "$OLD" --argjson n "$MANY" \
   '[range(0;$n) | {id:("m-r"+(.|tostring)), status:"closed", closed_at:$ca}]' \
   > "$TMP/stores/alpha.show.json"
jq -nc --argjson n "$MANY" \
   '[range(0;$n) | {id:("m-s"+(.|tostring)), status:"open",
                    metadata:{"gc.root_bead_id":("m-r"+(.|tostring))}}]' \
   > "$TMP/stores/alpha.json"
gt "$(jq -c '.[] | {id, status, closed_at}' "$TMP/stores/alpha.show.json" | wc -c | tr -d ' ')" 131072 \
   "positive control: even the PROJECTED root map for this store exceeds the argv cap"
# One chunk, so the assertion is about size, not about how often the stub is asked.
OUT=$(GC_DOCTOR_ROOT_CHUNK="$MANY" RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1); RC=$?
eq "$RC" "2" "a store with more molecules than fit on argv is still joined"
has "$OUT" "$MANY molecule(s)" "every finalized molecule in the large store is reported"
hasnt "$OUT" "NOT checked" "a large store is not skipped"
hasnt "$OUT" "could not be computed" "the join over a large store is computed"
clear_fixtures

# --- 11. an unstageable root map fails CLOSED ------------------------------------
# Staging trades an argv string for a file, so an unusable file is a new way to
# lose the join; it must warn like every other broken probe.
steps "$(step s-14 r-14)"
roots "{\"id\":\"r-14\",\"status\":\"closed\",\"closed_at\":\"$OLD\"}"
OUT=$(TMPDIR="$TMP/nonexistent" run_check); RC=$?
eq "$RC" "1" "an unstageable root map warns, never passes"
has "$OUT" "stage the molecule-root map" "the staging failure names its cause"
hasnt "$OUT" "s-14" "no verdict is reported from a join that never ran"
clear_fixtures

# --- 12. a root payload that is neither array nor object is a failed probe -------
# Staging rewrote the branch that classifies the payload, so the shape it must
# still reject gets its own case: corrupt bytes are a broken probe, not an empty
# root map, which would reclassify every step under them as cross-store.
steps "$(step s-15 r-15)"
printf '"neither-array-nor-object"' > "$TMP/stores/alpha.show.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a root payload that is neither array nor object is a WARNING"
has "$OUT" "could not resolve molecule roots" "corrupt root bytes are reported as a failed probe"
hasnt "$OUT" "reported, not judged" "corrupt bytes are not downgraded to unresolved-root notes"
clear_fixtures

echo
echo "check-step-terminal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
