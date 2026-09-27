#!/usr/bin/env bash
# Hermetic test for doctor/check-armed-dispatch-owed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the OWED finding (open arm whose own blocks
# edges closed long ago but that never dispatched), the STRANDED finding (armed
# at a non-open status), the narrowing exemptions (still waiting on its own open
# blocker; dispatchable only recently, within the reconcile window; mid-dispatch
# via a slung marker; delivered via merge_result; closed; capped at the
# configured sling-failure cap, which reconcile has already escalated), the
# fail-closed probes
# (unreadable dep list, unreadable armed listing, unreadable rig list), the
# suspended-rig skip, and the quiet path (no armed beads).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-armed-dispatch-owed-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
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
  # The only list the check makes: armed beads (--has-metadata-key). Per-rig
  # fixture; a rig named in BD_FAIL_LIST cannot answer (fail-closed probe).
  list) [ "$name" = "${BD_FAIL_LIST:-}" ] && exit 3
        f="$STORES/$name.armed.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  # `dep list <id> --json`: real bd answers an ARRAY of the bead's own edges, or
  # an ERROR OBJECT for an unresolvable/unreadable query. $2=list, $3=id.
  dep) [ "$2" = "list" ] || { printf '[]'; exit 0; }
       did="$3"
       [ "$did" = "${BD_FAIL_DEP:-}" ] && { printf '{"error":"simulated dep failure"}'; exit 0; }
       f="$STORES/$name.dep.$did.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
clear_stores() { rm -f "$TMP/stores/"*.json; }

# Armed-bead fixtures (the check reads status + the slung/merge_result/armed_at
# metadata off this listing).
armed_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.armed.json"; }
aarmed()  { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-2020-01-01T00:00:00Z}"; }
astatus() { printf '{"id":"%s","status":"%s","metadata":{"gc.dispatch_when_ready":"rig/pool"}}' "$1" "$2"; }
aslung()  { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_slung":"slinging@2020-01-01T00:00:00Z"}}' "$1"; }
amr()     { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","merge_result":"pull_request"}}' "$1"; }
aassigned() { printf '{"id":"%s","status":"open","assignee":"rig/rig.refinery","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-2020-01-01T00:00:00Z}"; }
# A capped arm: fail count defaults to the cap (3); $2 overrides it. Paired with
# a long-closed own blocker it would read as owed-but-not-firing without the cap
# exemption.
acapped() { printf '{"id":"%s","status":"open","metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_fail_count":"%s","gc.dispatch_when_ready_armed_at":"%s"}}' "$1" "${2:-3}" "${3:-2020-01-01T00:00:00Z}"; }

# Dep-list fixtures (the bead's own outgoing edges).
dep_fixture() { local n="$1" id="$2"; shift 2; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.dep.$id.json"; }
e_blk_closed() { printf '{"id":"%s","dependency_type":"blocks","status":"closed","closed_at":"%s"}' "$1" "$2"; }
e_blk_open()   { printf '{"id":"%s","dependency_type":"blocks","status":"open","closed_at":null}' "$1"; }
e_parent_open(){ printf '{"id":"%s","dependency_type":"parent-child","status":"open","closed_at":null}' "$1"; }

OLD="2020-01-01T00:00:00Z"
RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 1. OWED: open arm, own blocks closed long ago, held only by an ancestor --
armed_store alpha "$(aarmed a-1)"
dep_fixture alpha a-1 "$(e_parent_open epic)" "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an owed-but-not-firing arm warns (exit 1)"
has "$OUT" "owed but not firing" "the headline names the defect"
has "$OUT" "alpha bead a-1" "the finding names the rig and bead"
has "$OUT" "disarm a-1" "the finding names the disarm remedy for that bead"
clear_stores

# --- 2. STRANDED: armed at a non-open status ---------------------------------
armed_store alpha "$(astatus a-2 blocked)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm at a non-open status warns (exit 1)"
has "$OUT" "status=blocked" "the finding names the stranding status"
has "$OUT" "alpha bead a-2" "the stranded finding names the rig and bead"
clear_stores

# --- 3. EXEMPT: still waiting on its OWN open blocker ------------------------
armed_store alpha "$(aarmed a-3)"
dep_fixture alpha a-3 "$(e_parent_open epic)" "$(e_blk_open b-0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm with an open own blocker is correctly waiting (exit 0)"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 4. EXEMPT: dispatchable only recently (within the reconcile window) -----
armed_store alpha "$(aarmed a-4)"
dep_fixture alpha a-4 "$(e_blk_closed b-0 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose blocker closed just now is within cadence, not flagged"
hasnt "$OUT" "alpha bead a-4" "a recently-dispatchable arm is not reported"
clear_stores

# --- 5. EXEMPT: mid-dispatch (a slung marker present) ------------------------
armed_store alpha "$(aslung a-5)"
dep_fixture alpha a-5 "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a mid-dispatch arm (slung marker) is left to reconcile, not flagged"
clear_stores

# --- 6. EXEMPT: delivered by another path (merge_result) --------------------
armed_store alpha "$(amr a-6)"
dep_fixture alpha a-6 "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm carrying merge_result is retired by reconcile, not flagged"
clear_stores

# --- 7. EXEMPT: closed bead ---------------------------------------------------
armed_store alpha "$(astatus a-7 closed)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a closed armed bead owes no dispatch, not flagged"
clear_stores

# --- 7b. EXEMPT: an assigned (HELD) arm — reconcile will not sling over it ---
armed_store alpha "$(aassigned a-7b)"
dep_fixture alpha a-7b "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assigned (HELD) arm is not owed a dispatch, not flagged"
hasnt "$OUT" "alpha bead a-7b" "a handed-off/held arm is not reported as owed"
clear_stores

# --- 7c. EXEMPT: a capped arm whose own blockers closed long ago — the reconcile
#          pass already escalated it, so it is surfaced, not silent -----------
armed_store alpha "$(acapped a-7c)"
dep_fixture alpha a-7c "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a capped arm (fail count at the cap) is exempt, not flagged as owed"
hasnt "$OUT" "alpha bead a-7c" "a capped arm is not reported"
clear_stores

# --- 7d. DISCRIMINATE: below the cap is still owed (the test is >=, not just
#          any nonzero fail count) --------------------------------------------
armed_store alpha "$(acapped a-7d 2)"
dep_fixture alpha a-7d "$(e_blk_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm below the cap (2 < 3) is still owed and flagged"
has "$OUT" "alpha bead a-7d" "a sub-cap owed arm is still reported"
clear_stores

# --- 7e. the cap honors GC_MAX_DISPATCH_SLING_FAILURES, exactly as
#          deferred-dispatch.sh reads the configured cap ----------------------
armed_store alpha "$(acapped a-7e 2)"
dep_fixture alpha a-7e "$(e_blk_closed b-0 "$OLD")"
OUT=$(GC_MAX_DISPATCH_SLING_FAILURES=2 run_check); RC=$?
eq "$RC" "0" "with the cap lowered to 2, a 2-failure arm is capped and exempt"
hasnt "$OUT" "alpha bead a-7e" "the configured-cap override matches deferred-dispatch.sh"
clear_stores

# --- 8. FAIL CLOSED: an otherwise-dispatchable arm whose dep list is unreadable
armed_store alpha "$(aarmed a-8)"
dep_fixture alpha a-8 "$(e_blk_closed b-0 "$OLD")"
OUT=$(BD_FAIL_DEP=a-8 run_check); RC=$?
eq "$RC" "1" "an unreadable dep list warns rather than passing (exit 1)"
has "$OUT" "could not read its dependency edges" "the store-not-checked reason is named"
hasnt "$OUT" "owed but not firing" "an unreadable probe is NOT reported as a firm finding"
clear_stores

# --- 9. FAIL CLOSED: unreadable armed listing --------------------------------
armed_store alpha "$(aarmed a-9)"
OUT=$(BD_FAIL_LIST=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable armed listing warns (exit 1)"
has "$OUT" "could not list armed beads" "the listing failure is named"
clear_stores

# --- 10. FAIL CLOSED: unreadable rig list ------------------------------------
OUT=$(RIGS_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns (exit 1)"
has "$OUT" "cannot determine" "the rig-list failure is named"

# --- 11. SUSPENDED rig is skipped, not queried -------------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped and the check passes"
has "$OUT" "skipped (suspended" "the skip is noted"

# --- 12. QUIET PATH: no armed beads ------------------------------------------
clear_stores
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no armed beads passes"
has "$OUT" "OK:" "the quiet headline is printed"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
