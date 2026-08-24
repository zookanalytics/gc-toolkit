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

echo
echo "check-step-terminal: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
