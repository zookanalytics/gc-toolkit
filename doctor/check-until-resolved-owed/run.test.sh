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
# the suspended-rig skip; the quiet path; that a store's statuses are read in
# ONE batch, not one call per candidate; and the live-work report (a bead the
# pass never disposes because it carries live work, read from its row or from
# its edges, is reported as a decision for a person, never as the order not
# firing, and an unreadable edge read leaves it unchecked); and the owed window,
# the deferred-dispatch order's cadence window from assets/scripts/order-cadence.sh,
# with its minimum floor when the order registry does not read.
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

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/pack/orders" "$TMP/empty-city"
# The interval the owed window takes from the pack, as orders/deferred-dispatch.toml declares it.
printf '[order]\ntrigger = "cooldown"\ninterval = "5m"\nscope = "rig"\n' > "$TMP/pack/orders/deferred-dispatch.toml"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
case "$1 $2" in
  "rig list") rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  # The order registry, for the cadence window. With no ORDERS_JSON it answers
  # nothing, the shape of a registry that did not read.
  "order list") [ -n "${ORDERS_JSON:-}" ] && cat "$ORDERS_JSON"; exit 0 ;;
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
#   * `bd show <id> --json`               → the bead's row, from <name>.show.json
#     when that file names it, else from the open listing.
#   * `bd dep list <id> --direction=up`   → the beads that depend on it, from
#     <name>.up.json (an object of id → array), else []. BD_FAIL_UP names a store
#     whose dependents read answers an error object.
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
  show)
    sid=""; for a in "$@"; do case "$a" in --*|"$db") ;; *) [ -n "$sid" ] || sid="$a" ;; esac; done
    f="$STORES/$name.show.json"
    [ -f "$f" ] && jq -e --arg id "$sid" 'any(.[]; .id == $id)' "$f" >/dev/null 2>&1 || f="$STORES/$name.open.json"
    if [ -f "$f" ] && jq -e --arg id "$sid" 'any(.[]; .id == $id)' "$f" >/dev/null 2>&1; then
      jq -c --arg id "$sid" '[ .[] | select(.id == $id) ]' "$f"
    else
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    fi ;;
  dep)
    [ "$name" = "${BD_FAIL_UP:-}" ] && { echo '{"error":"simulated dependents failure","schema_version":1}'; exit 0; }
    did=""; for a in "$@"; do case "$a" in list|--*|"$db") ;; *) [ -n "$did" ] || did="$a" ;; esac; done
    f="$STORES/$name.up.json"
    if [ -f "$f" ]; then jq -c --arg id "$did" '.[$id] // []' "$f"; else printf '[]'; fi ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

# GC_CITY_PATH is pinned to a fixture city, so the dispatch budget the window is
# derived from never comes from the AMBIENT city.toml.
run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" GC_CITY_PATH="${CITY_DIR:-$TMP/empty-city}" bash "$CHECK" 2>&1
}
clear_stores() { rm -f "$TMP/stores/"*.json; }

# Open-bead fixtures (the check reads status + assignee + .dependencies here).
open_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.open.json"; }
# A bead with one until edge (+ optional extra edge JSON fragments appended).
# Every candidate names issue_type task: the check reports a bead of any other
# type as live work, which the pass never disposes.
o_until()  { printf '{"id":"%s","issue_type":"task","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2"; }
o_until2() { printf '{"id":"%s","issue_type":"task","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"},{"depends_on_id":"%s","type":"until"}]}' "$1" "$2" "$3"; }
o_until_blk() { printf '{"id":"%s","issue_type":"task","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"},{"depends_on_id":"%s","type":"blocks"}]}' "$1" "$2" "$3"; }
o_until_assigned() { printf '{"id":"%s","issue_type":"task","status":"open","assignee":"rig/rig.refinery","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2"; }
o_until_status() { printf '{"id":"%s","issue_type":"task","status":"%s","assignee":"","dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2" "$3"; }
o_blocks_only() { printf '{"id":"%s","issue_type":"task","status":"open","assignee":"","dependencies":[{"depends_on_id":"%s","type":"blocks"}]}' "$1" "$2"; }
# A bead with one until edge, a type and metadata of the caller's choosing.
o_until_meta() { printf '{"id":"%s","issue_type":"%s","status":"open","assignee":"","metadata":%s,"dependencies":[{"depends_on_id":"%s","type":"until"}]}' "$1" "$2" "$3" "$4"; }

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

# --- 17. LIVE WORK on the row: an anchor mid-PR is a decision, not a stall ---
open_store alpha "$(o_until_meta l-1 task '{"branch":"polecat/l-1","merge_result":"pull_request","pr_url":"https://github.com/o/r/pull/7"}' x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a resolved bead carrying live work warns (exit 1)"
has "$OUT" "left open because they carry live work" "the headline says why it is open"
has "$OUT" "alpha bead l-1" "the bead is named"
has "$OUT" "merge_result=pull_request" "the mark that makes it live is named"
has "$OUT" "gc bd dep remove l-1" "the remove-edge remedy is named"
hasnt "$OUT" "owed but not firing" "live work is not reported as the order failing"
clear_stores

# --- 18. LIVE WORK on the row: work slung to a pool, and a non-work type ------
open_store alpha "$(o_until_meta l-2 task '{"gc.routed_to":"rig/rig.polecat"}' x-0)" "$(o_until_meta l-3 epic '{}' x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "slung work and an epic warn (exit 1)"
has "$OUT" "gc.routed_to=rig/rig.polecat" "the route is named"
has "$OUT" "issue_type=epic" "the epic is named as not plain work"
hasnt "$OUT" "owed but not firing" "neither is reported as the order failing"
clear_stores

# --- 19. LIVE WORK on the edges: a clean row tracked by a convoy --------------
open_store alpha "$(o_until l-4 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
printf '%s' '{"l-4":[{"id":"c-1","dependency_type":"tracks","issue_type":"convoy","status":"open"}]}' > "$TMP/stores/alpha.up.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a convoy-tracked resolved bead warns (exit 1)"
has "$OUT" "tracked by convoy c-1 (open)" "the convoy is named"
hasnt "$OUT" "owed but not firing" "a pour is not reported as the order failing"
clear_stores

# --- 20. LIVE WORK on the edges: an open child; a closed one is no mark ------
open_store alpha "$(o_until l-5 x-0)" "$(o_until l-6 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
printf '%s' '{"l-5":[{"id":"k-1","dependency_type":"parent-child","issue_type":"task","status":"open"}],"l-6":[{"id":"k-2","dependency_type":"parent-child","issue_type":"task","status":"closed"}]}' > "$TMP/stores/alpha.up.json"
OUT=$(run_check); RC=$?
eq "$RC" "1" "the check warns (exit 1)"
has "$OUT" "open child k-1" "an open child makes l-5 live work"
has "$OUT" "owed but not firing" "l-6, whose only child is closed, is owed"
has "$OUT" "alpha bead l-6: its \`until\` resolved-by target(s) [x-0] have been closed" "l-6 is the owed finding"
clear_stores

# --- 21. FAIL CLOSED: an unreadable dependents read leaves the bead unchecked -
open_store alpha "$(o_until l-7 x-0)"
refs_store alpha "$(r_closed x-0 "$OLD")"
OUT=$(BD_FAIL_UP=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable dependents read warns (exit 1)"
has "$OUT" "NOT checked" "the bead is named as unchecked"
hasnt "$OUT" "owed but not firing" "an unread edge set is NOT a firm finding"
clear_stores

# --- 22. WINDOW: live work whose target closed just now is not reported ------
open_store alpha "$(o_until_meta l-8 task '{"gc.routed_to":"rig/rig.polecat"}' x-0)"
refs_store alpha "$(r_closed x-0 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "live work inside the reconcile window is not reported (exit 0)"
hasnt "$OUT" "alpha bead l-8" "the bead is not named"
clear_stores

# --- 23. WINDOW: the owed window is the deferred-dispatch order's cadence window
# check-cadence-live (I10) and this check read one definition
# (assets/scripts/order-cadence.sh): max(3×interval, one trip of the order
# dispatch rotation). 70 clock-driven registrations at the default budget of 4
# make a trip of ceil(70/4) = 18 passes, 2160s at 120s a pass, and the pack
# declares deferred-dispatch at 5m, so the window is 2160s.
ago() { jq -rn --argjson t "$(( $(date +%s) - $1 ))" '$t | todate'; }
{
    printf '{"orders":[{"name":"deferred-dispatch","rig":"alpha","trigger":"cooldown","interval":"5m"}'
    for i in $(seq 1 69); do printf ',{"name":"other-%s","rig":"","trigger":"cooldown","interval":"5m"}' "$i"; done
    printf ',{"name":"gated","rig":"alpha","trigger":"condition"}]}\n'
} > "$TMP/orders-busy.json"
open_store alpha "$(o_until w-1 x-0)"
refs_store alpha "$(r_closed x-0 "$(ago 1200)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "0" "a disposition owed for 1200s is inside a 2160s window (the 900s one called it owed)"
hasnt "$OUT" "alpha bead w-1" "…so it is not reported"
refs_store alpha "$(r_closed x-0 "$(ago 2500)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "1" "a disposition owed for 2500s, past the window, is owed"
has "$OUT" "(> 2160s)" "…and the finding states the window"
# No registry: the window falls back to the 30m minimum, and says so.
refs_store alpha "$(r_closed x-0 "$(ago 1500)")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "with no registry, a disposition owed for 1500s is inside the 1800s minimum window"
has "$OUT" "did not read, so the owed window uses the 1800s minimum floor" "…and the fallback is noted"
refs_store alpha "$(r_closed x-0 "$(ago 2000)")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "with no registry, a disposition owed for 2000s is owed"
has "$OUT" "(> 1800s)" "…against the minimum window"
clear_stores

if grep -qE '^[[:space:]]*OWED_WINDOW_SECONDS=[0-9]' "$CHECK"; then
    bad "the check carries no owed-window constant of its own"
else ok "the check carries no owed-window constant of its own"; fi
grep -qF 'assets/scripts/order-cadence.sh' "$CHECK" && ok "the check sources assets/scripts/order-cadence.sh" \
    || bad "the check sources assets/scripts/order-cadence.sh"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
