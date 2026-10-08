#!/usr/bin/env bash
# Hermetic test for doctor/check-until-resolved-owed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the OWED finding (open, unassigned bead whose
# `until` targets closed long ago but that was never disposed); the exemptions
# (an until target still open; closed only recently, within the reconcile window;
# an assigned bead; a non-open bead; a bead held by its own open `blocks` blocker;
# a bead with a `blocks` edge but no `until` edge — the scope guard, only `until`
# disposes); the multi-target rule (owed only when ALL until targets closed, owed-
# since the latest); the fail-closed probes (unreadable open listing, unreadable
# status listing, an until target the status read drops as unresolvable, an
# unreadable rig list); the gate-target resolution (bd hides gates unless asked);
# the suspended-rig skip; the quiet path; and that a store's statuses are read in
# ONE batch, not one call per candidate.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-until-resolved-owed-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
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
# The stub models the two reads the check makes, and the failure shapes real bd
# shows for each:
#   * `bd list --brief --json` (no --id)  → the OPEN beads for this rig
#     (<name>.open.json): each bead's status, assignee, and its own outgoing edges
#     under `.dependencies` in the list-edge shape ({depends_on_id, type}).
#     BD_FAIL_LIST names a store whose open listing fails outright.
#   * `bd list --id <csv> --all ...`       → the referenced target/blocker beads
#     (<name>.refs.json), DROPPING ids with no row (real --id is silent about a
#     miss) and hiding a gate/infra/template row unless the matching --include
#     flag was passed. BD_FAIL_REFS fails it. ID_CALLS, when set, gets one line
#     per --id listing, so a test can assert it runs once per store.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
db=""; id_csv=""; prev=""; inc_gates=false; inc_infra=false; inc_templates=false
valueflag() { case "$1" in --db|--id|--limit|--actor|--type|--direction|--database|--max-rows|--offset) return 0;; *) return 1;; esac; }
for a in "$@"; do
  if valueflag "$prev"; then
    case "$prev" in --db) db="$a" ;; --id) id_csv="$a" ;; esac
    prev="$a"; continue
  fi
  case "$a" in
    --include-gates) inc_gates=true ;;
    --include-infra) inc_infra=true ;;
    --include-templates) inc_templates=true ;;
    *) : ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
case "$sub" in
  list)
    if [ -n "$id_csv" ]; then
      [ -n "${ID_CALLS:-}" ] && echo "$name $id_csv" >> "$ID_CALLS"
      [ "$name" = "${BD_FAIL_REFS:-}" ] && exit 3
      f="$STORES/$name.refs.json"
      if [ -f "$f" ]; then
        want=$(printf '%s' "$id_csv" | tr ',' '\n' | jq -R . | jq -sc .)
        jq -c --argjson want "$want" --argjson ig "$inc_gates" --argjson ii "$inc_infra" --argjson it "$inc_templates" '
          [ .[]
            | select(.id as $i | $want | index($i))
            | select( (.issue_type // "task") as $t
                      | if   $t == "gate"                                     then $ig
                        elif ($t == "agent" or $t == "role" or $t == "message") then $ii
                        elif $t == "template"                                 then $it
                        else true end ) ]' "$f"
      else printf '[]'; fi
    else
      [ "$name" = "${BD_FAIL_LIST:-}" ] && exit 3
      f="$STORES/$name.open.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
    fi ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" bash "$CHECK" 2>&1
}
clear_stores() { rm -f "$TMP/stores/"*.json; }

# Open-bead fixtures (the check reads status + assignee + .dependencies here).
open_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.open.json"; }
# A bead with one until edge (+ optional extra edge JSON fragments appended).
o_until()  { printf '{"id":"%s","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2"; }
o_until2() { printf '{"id":"%s","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"},{"depends_on_id":"%s","type":"until"}]}' "$1" "$2" "$3"; }
o_until_blk() { printf '{"id":"%s","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"},{"depends_on_id":"%s","type":"blocks"}]}' "$1" "$2" "$3"; }
o_until_assigned() { printf '{"id":"%s","status":"open","assignee":"rig/rig.refinery","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2"; }
o_until_status() { printf '{"id":"%s","status":"%s","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2" "$3"; }
o_blocks_only() { printf '{"id":"%s","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"blocks"}]}' "$1" "$2"; }

# Referenced-bead fixtures (status + closed_at the --id lookup resolves).
refs_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.refs.json"; }
r_closed() { printf '{"id":"%s","status":"closed","closed_at":"%s"}' "$1" "$2"; }
r_open()   { printf '{"id":"%s","status":"open"}' "$1"; }
r_closed_gate() { printf '{"id":"%s","status":"closed","closed_at":"%s","issue_type":"gate"}' "$1" "$2"; }

OLD="2020-01-01T00:00:00Z"
RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 1. OWED: open, unassigned, until target closed long ago -----------------
open_store alpha "$(o_until u-1 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an owed-but-not-firing resolved-by bead warns (exit 1)"
has "$OUT" "owed but not firing" "the headline names the defect"
has "$OUT" "alpha bead u-1" "the finding names the rig and bead"
has "$OUT" "gc bd dep remove u-1" "the finding names the remove-edge remedy"
clear_stores

# --- 2. EXEMPT: until target still open --------------------------------------
open_store alpha "$(o_until u-2 x-0)"
refs_store alpha "$(r_open x-0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bead whose until target is still open is correctly waiting (exit 0)"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 3. EXEMPT: until target closed only recently (within the window) --------
open_store alpha "$(o_until u-3 x-0)"
refs_store alpha "$(r_closed x-0 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bead whose until target closed just now is within cadence, not flagged"
hasnt "$OUT" "alpha bead u-3" "a recently-resolved bead is not reported"
clear_stores

# --- 4. EXEMPT: an assigned bead (a live worker holds it) --------------------
open_store alpha "$(o_until_assigned u-4 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assigned resolved-by bead is left alone (exit 0)"
hasnt "$OUT" "alpha bead u-4" "an assigned bead is not reported as owed"
clear_stores

# --- 5. EXEMPT: a non-open bead is a deliberate hold -------------------------
open_store alpha "$(o_until_status u-5 blocked x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a non-open resolved-by bead is a deliberate hold, not flagged"
hasnt "$OUT" "alpha bead u-5" "a held-status bead is not reported"
clear_stores

# --- 6. SCOPE GUARD: ONLY until disposes — a blocks edge to a closed target
#          is never a candidate -----------------------------------------------
open_store alpha "$(o_blocks_only u-6 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a blocks edge to a closed target is never a resolved-by candidate (scope guard)"
hasnt "$OUT" "alpha bead u-6" "a blocks-only bead is not flagged"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 7. EXEMPT: until target closed, but an OPEN blocks blocker still holds it-
open_store alpha "$(o_until_blk u-7 x-0 y-0)"
refs_store alpha "$(r_closed x-0 "$OLD")" "$(r_open y-0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bead whose until target closed but whose own blocks blocker is open is correctly waiting"
hasnt "$OUT" "alpha bead u-7" "a bead still held by a blocks blocker is not flagged as owed"
clear_stores

# --- 8. MULTI-TARGET: owed only when ALL until targets closed ----------------
open_store alpha "$(o_until2 u-8 x-1 x-2)"
refs_store alpha "$(r_closed x-1 "$OLD")" "$(r_open x-2)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a bead with two until targets, one still open, is NOT owed (exit 0)"
clear_stores
open_store alpha "$(o_until2 u-8b x-1 x-2)"
refs_store alpha "$(r_closed x-1 "$OLD")" "$(r_closed x-2 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a bead with both until targets closed long ago is owed (exit 1)"
has "$OUT" "alpha bead u-8b" "the all-targets-closed bead is reported"
clear_stores

# --- 9. FAIL CLOSED: unreadable open listing ---------------------------------
open_store alpha "$(o_until u-9 x-0)"
OUT=$(BD_FAIL_LIST=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable open listing warns (exit 1)"
has "$OUT" "could not list open beads" "the listing failure is named"
hasnt "$OUT" "owed but not firing" "an unreadable store is NOT a firm finding"
clear_stores

# --- 10. FAIL CLOSED: unreadable status listing ------------------------------
open_store alpha "$(o_until u-10 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(BD_FAIL_REFS=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable status listing warns (exit 1)"
has "$OUT" "could not read until-target" "the status-read failure is named"
hasnt "$OUT" "owed but not firing" "an unresolved status set is NOT a firm finding"
clear_stores

# --- 11. FAIL CLOSED: an until target with no readable row (dropped by --id) --
open_store alpha "$(o_until u-11 ghost)"
refs_store alpha "$(r_closed other "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a candidate whose until target does not resolve warns (exit 1)"
has "$OUT" "could not resolve its until target" "the unresolved-target reason is named"
hasnt "$OUT" "owed but not firing" "an unresolved target is NOT reported as owed"
clear_stores

# --- 12. a CLOSED GATE until-target still resolves — bd hides gates unless
#          --include-gates is passed; the status read must carry it -----------
open_store alpha "$(o_until u-12 g-0)"
refs_store alpha "$(r_closed_gate g-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a bead resolved by a long-closed GATE target is owed and flagged"
has "$OUT" "alpha bead u-12" "the gate-resolved owed bead is reported"
hasnt "$OUT" "could not resolve" "a gate target is resolved, not dropped as unreadable"
clear_stores

# --- 13. FAIL CLOSED: unreadable rig list ------------------------------------
OUT=$(RIGS_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns (exit 1)"
has "$OUT" "cannot determine" "the rig-list failure is named"

# --- 14. SUSPENDED rig is skipped, not queried -------------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped and the check passes"
has "$OUT" "skipped (suspended" "the skip is noted"

# --- 15. QUIET PATH: no until beads ------------------------------------------
clear_stores
open_store alpha '{"id":"n-1","status":"open","assignee":"","dependencies":[]}'
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no resolved-by beads passes"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 16. BATCH ONCE: three owed candidates cost ONE status read, not three ---
open_store alpha "$(o_until m-1 x-1)" "$(o_until m-2 x-2)" "$(o_until m-3 x-3)"
refs_store alpha "$(r_closed x-1 "$OLD")" "$(r_closed x-2 "$OLD")" "$(r_closed x-3 "$OLD")"
IDLOG="$TMP/idcalls"; rm -f "$IDLOG"
OUT=$(ID_CALLS="$IDLOG" run_check); RC=$?
eq "$RC" "1" "three owed candidates warn (exit 1)"
has "$OUT" "alpha bead m-1" "the first owed candidate is reported"
has "$OUT" "alpha bead m-2" "the second owed candidate is reported"
has "$OUT" "alpha bead m-3" "the third owed candidate is reported"
IDN=$( [ -f "$IDLOG" ] && wc -l < "$IDLOG" | tr -d ' ' || echo 0 )
eq "$IDN" "1" "the store's target statuses are read in ONE batch, not one call per candidate"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
