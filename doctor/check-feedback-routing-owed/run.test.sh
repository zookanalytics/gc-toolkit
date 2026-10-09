#!/usr/bin/env bash
# Hermetic test for doctor/check-feedback-routing-owed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the FINDING (an aged commented/changes_requested
# posture with no disposition), the narrowing exemptions (a recorded disposition;
# an unengaged-thread marker AT the posture's head; a marker at a DIFFERENT head,
# which does NOT exempt; a posture still within the owed window; a closed anchor; a
# posture with no @since instant; a posture that is neither commented nor
# changes_requested), the configurable window, the fail-closed probes (unreadable
# posture listing, unreadable rig list), the suspended-rig skip, and the quiet path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-feedback-routing-owed-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/pack"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; db=""; prev=""
for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
name=$(basename "$(dirname "$db")")
case "$sub" in
  # The only list the check makes: posture-bearing anchors (--has-metadata-key).
  # A rig named in BD_FAIL_LIST cannot answer (fail-closed probe).
  list) [ "$name" = "${BD_FAIL_LIST:-}" ] && exit 3
        f="$STORES/$name.posture.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
clear_stores() { rm -f "$TMP/stores/"*.json; }

OLD="2020-01-01T00:00:00Z"
RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Anchor fixtures. The posture value is <posture>@<oid>@<since>; the check ages
# from <since> and matches an unengaged marker against <oid>.
posture_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.posture.json"; }
pcommented() { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"commented@oidA@%s"}}' "$1" "${2:-$OLD}"; }
pchanges()   { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"changes_requested@oidA@%s"}}' "$1" "${2:-$OLD}"; }
pdisp()      { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"commented@oidA@%s","pr_comment_disposition":"rework:x9"}}' "$1" "${2:-$OLD}"; }
punengaged() { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"commented@oidA@%s","pr_unengaged_threads":"%s"}}' "$1" "${3:-$OLD}" "${2:-oidA}"; }
pclosed()    { printf '{"id":"%s","status":"closed","metadata":{"pr_posture":"commented@oidA@%s"}}' "$1" "${2:-$OLD}"; }
pnodate()    { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"commented@oidA"}}' "$1"; }
papproved()  { printf '{"id":"%s","status":"open","metadata":{"pr_posture":"approved@oidA@%s"}}' "$1" "${2:-$OLD}"; }

# --- 1. FINDING: an aged commented posture with no disposition ----------------
posture_store alpha "$(pcommented a-1)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an aged commented posture with no disposition warns (exit 1)"
has "$OUT" "recorded but not routed" "the headline names the defect"
has "$OUT" "alpha bead a-1" "the finding names the rig and bead"
has "$OUT" "no pr_comment_disposition" "…and the missing routing record"
clear_stores

# --- 2. FINDING: an aged changes_requested posture with no disposition --------
posture_store alpha "$(pchanges a-2)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an aged changes_requested posture with no disposition warns (exit 1)"
has "$OUT" "pr_posture=changes_requested" "the finding names the posture"
has "$OUT" "alpha bead a-2" "…and the bead"
clear_stores

# --- 3. EXEMPT: a recorded disposition means it was routed --------------------
posture_store alpha "$(pdisp a-3)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a posture carrying a disposition is routed, not flagged"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 4. EXEMPT: an unengaged-thread marker AT the posture's head --------------
posture_store alpha "$(punengaged a-4 oidA)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an unengaged marker at the posture head is a tracked hold, not flagged"
hasnt "$OUT" "alpha bead a-4" "…and the anchor is not reported"
clear_stores

# --- 5. DISCRIMINATE: an unengaged marker at a DIFFERENT head does NOT exempt -
posture_store alpha "$(punengaged a-5 oidB)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a stale unengaged marker (other head) does not exempt an aged posture"
has "$OUT" "alpha bead a-5" "…the finding still fires"
clear_stores

# --- 6. EXEMPT: still within the owed window ----------------------------------
posture_store alpha "$(pcommented a-6 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a posture recorded just now is within the window, not flagged"
hasnt "$OUT" "alpha bead a-6" "a recent posture is not reported"
clear_stores

# --- 7. EXEMPT: a closed anchor owes no routing ------------------------------
posture_store alpha "$(pclosed a-7)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed anchor is not flagged"
clear_stores

# --- 8. EXEMPT: a posture with no @since instant is skipped -------------------
posture_store alpha "$(pnodate a-8)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a posture with no @since instant cannot be aged, so it is skipped"
hasnt "$OUT" "alpha bead a-8" "…and not reported"
clear_stores

# --- 9. EXEMPT: a posture that is neither commented nor changes_requested -----
posture_store alpha "$(papproved a-9)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an approved posture is not operator feedback, not flagged"
clear_stores

# --- 10. the owed window honors GC_FEEDBACK_ROUTING_OWED_SECONDS --------------
posture_store alpha "$(pcommented a-10 "$RECENT")"
OUT=$(GC_FEEDBACK_ROUTING_OWED_SECONDS=0 run_check); RC=$?
eq "$RC" "1" "with the window at 0s, even a just-recorded posture is owed"
has "$OUT" "alpha bead a-10" "…and reported"
clear_stores

# --- 11. FAIL CLOSED: unreadable posture listing -----------------------------
posture_store alpha "$(pcommented a-11)"
OUT=$(BD_FAIL_LIST=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable posture listing warns (exit 1)"
has "$OUT" "could not list posture-bearing anchors" "the listing failure is named"
hasnt "$OUT" "recorded but not routed" "…and is NOT reported as a firm finding"
clear_stores

# --- 12. FAIL CLOSED: unreadable rig list ------------------------------------
OUT=$(RIGS_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns (exit 1)"
has "$OUT" "cannot determine" "the rig-list failure is named"

# --- 13. SUSPENDED rig is skipped, not queried -------------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
posture_store alpha "$(pcommented a-13)"
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped and the check passes"
has "$OUT" "skipped (suspended" "the skip is noted"
clear_stores

# --- 14. QUIET PATH: no posture-bearing anchors ------------------------------
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no posture-bearing anchors passes"
has "$OUT" "OK:" "the quiet headline is printed"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
