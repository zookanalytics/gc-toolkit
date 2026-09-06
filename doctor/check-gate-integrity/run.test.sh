#!/usr/bin/env bash
# Hermetic test for doctor/check-gate-integrity (I6+I7 surface). Stub gc/bd.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-gate-integrity-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
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
  "bd "*)    shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The check reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub above may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
[ "$name" = "${BD_FAIL_STORE:-}" ] && exit 3
f="$STORES/$name.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"
run_check() { RIGS_JSON="$TMP/rigs.json" GC_PACK_DIR="$TMP" bash "$CHECK" 2>&1; }
bead() { printf '{"id":"%s","status":"open","metadata":%s}' "$1" "$2"; }
store() { local IFS=,; printf '[%s]' "$*" > "$TMP/stores/alpha.json"; }
OID="0123456789abcdef0123456789abcdef01234567"

# --- 1. healthy anchors pass ---------------------------------------------------
store "$(bead g-1 '{"merge_result":"pull_request","check_set":"codex","branch":"polecat/g-1","check.codex":"green"}')" \
      "$(bead g-2 '{"merge_result":"pre_open_gate","check_set":"none","branch":"polecat/g-2"}')" \
      "$(bead g-3 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"b\",\"check.codex\":\"fixing\",\"check.codex.reason\":\"prose, not a marker\",\"check.codex.attempts\":\"2@$OID\"}")" \
      "$(bead g-3b '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"unreviewed"}')" \
      "$(bead g-3c '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"reviewing"}')" \
      "$(bead g-3d '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"validating"}')" \
      "$(bead g-3e '{"merge_result":"pull_request","check_set":"codex","branch":"b"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "every lane state, the none sentinel, an absent marker and sidecar keys all pass"
has "$OUT" "OK:" "the pass message is the OK line"

# --- 2. missing / empty check_set on a gating anchor ------------------------------
store "$(bead g-4 '{"merge_result":"pull_request","branch":"b"}')" \
      "$(bead g-5 '{"merge_result":"pre_open_gate","check_set":"","branch":"b"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a gating anchor with no (or empty) check_set is an ERROR"
has "$OUT" "g-4" "the absent declaration is flagged"
has "$OUT" "g-5" "the explicitly empty declaration is flagged"
has "$OUT" "ungated" "the finding says what empty means to merge.sh"

# --- 3. markers outside the lane vocabulary ---------------------------------------
# The legacy grammar is the case that matters: an unmigrated anchor reads as a
# state no reader knows, and this check is what says so.
store "$(bead g-6 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"b\",\"check.codex\":\"green@$OID\"}")" \
      "$(bead g-7 "{\"merge_result\":\"pull_request\",\"check_set\":\"codex\",\"branch\":\"b\",\"check.codex\":\"exception@$OID\"}")" \
      "$(bead g-8 '{"merge_result":"pull_request","check_set":"codex","branch":"b","check.codex":"passed"}')"
OUT=$(run_check); RC=$?
eq "$RC" "2" "a marker outside the lane vocabulary is an ERROR"
has "$OUT" "g-6" "an unmigrated green@<oid> is flagged"
has "$OUT" "g-7" "an unmigrated exception@<oid> is flagged"
has "$OUT" "g-8" "a bare word that names no lane state is flagged"

# --- 4. a green lane needs no branch to be well-formed ------------------------------
# The old warning asked whether the marker's oid could be compared to a head.
# A lane state names no oid, so there is nothing a missing branch makes
# unverifiable here.
store "$(bead g-9 '{"merge_result":"pull_request","check_set":"codex","check.codex":"green"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a green lane on an anchor with no branch is well-formed"

# --- 5. non-gating anchors are out of scope ------------------------------------------
store "$(bead g-10 '{"merge_result":"abandoned"}')" \
      "$(bead g-11 '{"merge_result":"blocked","check.codex":"nonsense"}')"
OUT=$(run_check); RC=$?
eq "$RC" "0" "human-parked states carry no gate obligations"

# --- 6. fail-CLOSED --------------------------------------------------------------
OUT=$(RIGS_RC=1 run_check); RC=$?
eq "$RC" "1" "a failed \`gc rig list\` warns, never passes"
OUT=$(BD_FAIL_STORE=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable store warns"
has "$OUT" "NOT checked" "the warning says the store was skipped"
printf 'not json' > "$TMP/stores/alpha.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an unparseable store listing warns"

echo
echo "check-gate-integrity: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
