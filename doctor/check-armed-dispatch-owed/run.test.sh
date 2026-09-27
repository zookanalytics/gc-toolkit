#!/usr/bin/env bash
# Hermetic test for doctor/check-armed-dispatch-owed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the OWED finding (open arm whose own blocks
# edges closed long ago but that never dispatched), the STRANDED finding (armed
# at a non-open status), the narrowing exemptions (still waiting on its own open
# blocker; dispatchable only recently, within the reconcile window; mid-dispatch
# via a slung marker; delivered via merge_result; closed; assigned; capped at the
# configured sling-failure cap, which reconcile has already escalated), the
# fail-closed probes (a batch dep read that fails outright, a candidate the batch
# dep read drops as unresolvable, unreadable blocker listing, unreadable armed
# listing, unreadable rig list, an unresolvable blocker), the
# suspended-rig skip, and the quiet path (no armed beads). The check reads
# dependencies in bulk: one `bd dep list` for the whole candidate set (edge
# records) then one `bd list --id` for the blockers' statuses — so a store costs
# a fixed number of queries, not one per armed bead. The batch-once case asserts
# that mechanism directly, not just its behavior.
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
# The stub models exactly the three reads the check makes, and the failure shapes
# the real bd shows for each:
#   * `bd list --has-metadata-key ...`  → the armed listing (per-rig fixture).
#   * `bd dep list <id...> --json`       → a FLAT array of edge records across all
#      requested ids ({issue_id, depends_on_id, type}), at rc=0. An id in
#      BD_FAIL_DEP is one bd cannot resolve: it is DROPPED from the array with a
#      per-id "(skipped)" warning on stderr and rc STAYS 0 — one bad id does not
#      poison the batch. A fully-resolvable read is silent on stderr.
#      BD_HARDFAIL_DEP names a store whose whole dep read fails outright (rc!=0),
#      the shape a broken db or a timeout shows.
#   * `bd list --id <csv> --all ...`     → the named blocker beads, DROPPING ids
#      with no row (real --id is silent about a miss). BD_FAIL_BLOCKERS fails it.
# DEP_CALLS, when set, gets one line per `bd dep list` invocation, so a test can
# assert the read happens once per store rather than once per bead.
cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
is_dep_list=""; [ "$sub" = "dep" ] && [ "${1:-}" = "list" ] && { is_dep_list=1; shift; }
db=""; id_csv=""; dep_ids=(); prev=""; inc_gates=false; inc_infra=false; inc_templates=false
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
    -*) : ;;
    *) [ -n "$is_dep_list" ] && dep_ids+=("$a") ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
case "$sub" in
  list)
    if [ -n "$id_csv" ]; then
      [ "$name" = "${BD_FAIL_BLOCKERS:-}" ] && exit 3
      f="$STORES/$name.blockers.json"
      if [ -f "$f" ]; then
        # Model bd's default hiding: a gate/infra/template blocker is returned
        # only when the matching --include flag was passed.
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
      f="$STORES/$name.armed.json"; if [ -f "$f" ]; then cat "$f"; else printf '[]'; fi
    fi ;;
  dep)
    [ -n "$is_dep_list" ] || { printf '[]'; exit 0; }
    [ "${#dep_ids[@]}" -gt 0 ] || { printf '[]'; exit 0; }
    [ -n "${DEP_CALLS:-}" ] && echo "$name ${dep_ids[*]}" >> "$DEP_CALLS"
    # A whole-store hard failure (broken db, timeout): rc!=0, no array.
    [ "$name" = "${BD_HARDFAIL_DEP:-}" ] && exit 3
    # Real bd resolves each requested id on its own: one it cannot find is DROPPED
    # from the result with a "(skipped)" warning on stderr and rc=0, never a
    # poisoned batch. An id in BD_FAIL_DEP models exactly that dropped id.
    kept=()
    for did in "${dep_ids[@]}"; do
      case " ${BD_FAIL_DEP:-} " in
        *" $did "*) printf 'warning: resolving %s: no issue found matching "%s" (skipped)\n' "$did" "$did" >&2 ;;
        *) kept+=("$did") ;;
      esac
    done
    f="$STORES/$name.edges.json"
    if [ -f "$f" ] && [ "${#kept[@]}" -gt 0 ]; then
      want=$(printf '%s\n' "${kept[@]}" | jq -R . | jq -sc .)
      jq -c --argjson want "$want" '[ .[] | select(.issue_id as $s | $want | index($s)) ]' "$f"
    else printf '[]'; fi ;;
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

# Edge fixtures — the flat array a batch `bd dep list` returns for the store
# (issue_id blocked-by depends_on_id). A parent-child edge is included in one
# case to prove the check filters to `blocks` only.
edges_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.edges.json"; }
e_blk() { printf '{"issue_id":"%s","depends_on_id":"%s","type":"blocks"}' "$1" "$2"; }
e_pc()  { printf '{"issue_id":"%s","depends_on_id":"%s","type":"parent-child"}' "$1" "$2"; }

# Blocker fixtures — the beads named as a blocker, with the status/closed_at the
# `bd list --id` lookup resolves. An open blocker omits closed_at, like real bd.
blockers_store() { local n="$1"; shift; local IFS=,; printf '[%s]' "$*" > "$TMP/stores/$n.blockers.json"; }
b_closed() { printf '{"id":"%s","status":"closed","closed_at":"%s"}' "$1" "$2"; }
b_open()   { printf '{"id":"%s","status":"open"}' "$1"; }
# A closed GATE blocker — bd list hides it unless --include-gates is passed, so
# this exercises the include flags the status lookup must carry.
b_closed_gate() { printf '{"id":"%s","status":"closed","closed_at":"%s","issue_type":"gate"}' "$1" "$2"; }

OLD="2020-01-01T00:00:00Z"
RECENT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- 1. OWED: open arm, own blocks closed long ago, held only by an ancestor --
armed_store alpha "$(aarmed a-1)"
edges_store alpha "$(e_pc a-1 epic)" "$(e_blk a-1 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
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
edges_store alpha "$(e_pc a-3 epic)" "$(e_blk a-3 b-0)"
blockers_store alpha "$(b_open b-0)"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm with an open own blocker is correctly waiting (exit 0)"
has "$OUT" "OK:" "the quiet headline is printed"
clear_stores

# --- 4. EXEMPT: dispatchable only recently (within the reconcile window) -----
armed_store alpha "$(aarmed a-4)"
edges_store alpha "$(e_blk a-4 b-0)"
blockers_store alpha "$(b_closed b-0 "$RECENT")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an arm whose blocker closed just now is within cadence, not flagged"
hasnt "$OUT" "alpha bead a-4" "a recently-dispatchable arm is not reported"
clear_stores

# --- 5. EXEMPT: mid-dispatch (a slung marker present) ------------------------
armed_store alpha "$(aslung a-5)"
edges_store alpha "$(e_blk a-5 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a mid-dispatch arm (slung marker) is left to reconcile, not flagged"
clear_stores

# --- 6. EXEMPT: delivered by another path (merge_result) --------------------
armed_store alpha "$(amr a-6)"
edges_store alpha "$(e_blk a-6 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
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
edges_store alpha "$(e_blk a-7b b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "an assigned (HELD) arm is not owed a dispatch, not flagged"
hasnt "$OUT" "alpha bead a-7b" "a handed-off/held arm is not reported as owed"
clear_stores

# --- 7c. EXEMPT: a capped arm whose own blockers closed long ago — the reconcile
#          pass already escalated it, so it is surfaced, not silent -----------
armed_store alpha "$(acapped a-7c)"
edges_store alpha "$(e_blk a-7c b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "a capped arm (fail count at the cap) is exempt, not flagged as owed"
hasnt "$OUT" "alpha bead a-7c" "a capped arm is not reported"
clear_stores

# --- 7d. DISCRIMINATE: below the cap is still owed (the test is >=, not just
#          any nonzero fail count) --------------------------------------------
armed_store alpha "$(acapped a-7d 2)"
edges_store alpha "$(e_blk a-7d b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm below the cap (2 < 3) is still owed and flagged"
has "$OUT" "alpha bead a-7d" "a sub-cap owed arm is still reported"
clear_stores

# --- 7e. the cap honors GC_MAX_DISPATCH_SLING_FAILURES, exactly as
#          deferred-dispatch.sh reads the configured cap ----------------------
armed_store alpha "$(acapped a-7e 2)"
edges_store alpha "$(e_blk a-7e b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(GC_MAX_DISPATCH_SLING_FAILURES=2 run_check); RC=$?
eq "$RC" "0" "with the cap lowered to 2, a 2-failure arm is capped and exempt"
hasnt "$OUT" "alpha bead a-7e" "the configured-cap override matches deferred-dispatch.sh"
clear_stores

# --- 8. FAIL CLOSED: the batch dep read fails outright (rc!=0) ---------------
armed_store alpha "$(aarmed a-8)"
edges_store alpha "$(e_blk a-8 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_HARDFAIL_DEP=alpha run_check); RC=$?
eq "$RC" "1" "a batch dep read that fails outright warns rather than passing (exit 1)"
has "$OUT" "could not batch-read dependency edges" "the store-not-checked reason is named"
hasnt "$OUT" "owed but not firing" "a failed dep read is NOT reported as a firm finding"
clear_stores

# --- 8a. FAIL CLOSED: a candidate the batch dep read cannot resolve ----------
#          bd drops it (rc=0, "(skipped)" on stderr), so its edges never arrive.
#          Without inspecting that stderr, its old armed_at reads as a firm owed
#          finding rather than "NOT checked" — the fail-closed hole this fixes.
armed_store alpha "$(aarmed a-8a)"
edges_store alpha "$(e_blk a-8a b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_DEP=a-8a run_check); RC=$?
eq "$RC" "1" "a candidate the dep read dropped as unresolvable warns rather than passing (exit 1)"
has "$OUT" "did not resolve every" "the store-not-checked reason names the incomplete read"
hasnt "$OUT" "owed but not firing" "a dropped (skipped) candidate is NOT reported as a firm owed finding"
clear_stores

# --- 8f. FAIL CLOSED, whole store: one dropped candidate among healthy ones --
#          A dropped id makes the batch read incomplete, so the store is NOT
#          checked as a whole — a co-resident owed arm is not reported off a read
#          that missed one of its candidates. The next pass re-reads.
armed_store alpha "$(aarmed a-8f1)" "$(aarmed a-8f2)"
edges_store alpha "$(e_blk a-8f2 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_DEP=a-8f1 run_check); RC=$?
eq "$RC" "1" "a dropped candidate fails the whole store closed (exit 1)"
has "$OUT" "did not resolve every" "the store-not-checked reason is named"
hasnt "$OUT" "alpha bead a-8f2" "a co-resident owed arm is NOT reported off an incomplete read"
clear_stores

# --- 8b. FAIL CLOSED: the blocker-status read is unreadable ------------------
armed_store alpha "$(aarmed a-8b)"
edges_store alpha "$(e_blk a-8b b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_BLOCKERS=alpha run_check); RC=$?
eq "$RC" "1" "an unreadable blocker listing warns (exit 1)"
has "$OUT" "could not read blocker statuses" "the blocker-listing failure is named"
hasnt "$OUT" "owed but not firing" "an unresolved blocker set is NOT a firm finding"
clear_stores

# --- 8c. FAIL CLOSED: a blocker edge points at a bead with no readable row ----
#          (the batch listing silently drops it; the candidate is NOT checked)
armed_store alpha "$(aarmed a-8c)"
edges_store alpha "$(e_blk a-8c ghost)"
blockers_store alpha "$(b_closed other "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a candidate with an unresolvable blocker warns (exit 1)"
has "$OUT" "could not resolve its blocker" "the unresolved-blocker reason is named"
hasnt "$OUT" "owed but not firing" "an unresolved blocker is NOT reported as owed"
clear_stores

# --- 8d. a CLOSED GATE blocker still resolves — bd list hides gates by default,
#          so the status lookup must pass --include-gates; the blocks edge names
#          a blocker of any type ------------------------------------------------
armed_store alpha "$(aarmed a-8d)"
edges_store alpha "$(e_blk a-8d g-0)"
blockers_store alpha "$(b_closed_gate g-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "an arm blocked only by a long-closed GATE is owed and flagged"
has "$OUT" "alpha bead a-8d" "the gate-blocked owed arm is reported (its gate blocker resolved)"
hasnt "$OUT" "could not resolve" "a gate blocker is resolved, not dropped as unreadable"
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

# --- 13. BATCH ONCE: three owed candidates cost ONE dep read, not three ------
#          This asserts the mechanism the fix exists for — the per-bead N+1 is
#          gone — not merely that three findings come back.
armed_store alpha "$(aarmed m-1)" "$(aarmed m-2)" "$(aarmed m-3)"
edges_store alpha "$(e_blk m-1 x-1)" "$(e_blk m-2 x-2)" "$(e_blk m-3 x-3)"
blockers_store alpha "$(b_closed x-1 "$OLD")" "$(b_closed x-2 "$OLD")" "$(b_closed x-3 "$OLD")"
DEPLOG="$TMP/depcalls"; rm -f "$DEPLOG"
OUT=$(DEP_CALLS="$DEPLOG" run_check); RC=$?
eq "$RC" "1" "three owed candidates warn (exit 1)"
has "$OUT" "alpha bead m-1" "the first owed candidate is reported"
has "$OUT" "alpha bead m-2" "the second owed candidate is reported"
has "$OUT" "alpha bead m-3" "the third owed candidate is reported"
DEPN=$( [ -f "$DEPLOG" ] && wc -l < "$DEPLOG" | tr -d ' ' || echo 0 )
eq "$DEPN" "1" "the store's dependency edges are read in ONE batch, not one call per bead"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
