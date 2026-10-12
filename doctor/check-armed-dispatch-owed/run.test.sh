#!/usr/bin/env bash
# Hermetic test for doctor/check-armed-dispatch-owed. Stub gc/bd only; no live
# city, Dolt, or network. Covers: the OWED finding (open arm whose own blocks
# edges closed long ago but that never dispatched), the STRANDED finding (armed
# at a non-open status), the narrowing exemptions (still waiting on its own open
# blocker; dispatchable only recently, within the reconcile window; mid-dispatch
# via a slung marker; delivered via merge_result; closed; assigned; capped at the
# configured sling-failure cap, which reconcile has already escalated), the
# fail-closed probes (a row whose edges were read short, unreadable blocker
# listing, unreadable or non-array armed listing, unreadable rig list, an
# unresolvable blocker, a scan that cannot report, no scratch directory), the
# suspended-rig skip, and the quiet path (no armed beads). A store costs two
# reads: one armed listing, whose rows carry each bead's own dependency edges,
# then one `bd list --id` for the blockers' statuses, with no dependency read
# and nothing per armed bead. The stores are scanned at once and reported in
# rig order, and the rig and order registries are read at once. The cases that
# assert those mechanisms assert them directly, not just the findings.
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
# line_of <text> <needle> — the number of the first line of <text> holding <needle>
line_of() { printf '%s\n' "$1" | grep -n -F -- "$2" | head -1 | cut -d: -f1; }

mkdir -p "$TMP/bin" "$TMP/stores" "$TMP/alpha" "$TMP/pack/orders" "$TMP/empty-city" "$TMP/tmpdir"
# The interval the owed window takes from the pack, as orders/deferred-dispatch.toml declares it.
printf '[order]\ntrigger = "cooldown"\ninterval = "5m"\nscope = "rig"\n' > "$TMP/pack/orders/deferred-dispatch.toml"
cat > "$TMP/rigs.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha"}]}
EOF
# rigs_of <name>... — a rig list naming those stores, in that order
rigs_of() {
    local r sep="" body=""
    for r in "$@"; do
        mkdir -p "$TMP/$r"
        body="$body$sep$(jq -nc --arg n "$r" --arg p "$TMP/$r" '{name:$n,path:$p}')"; sep=","
    done
    printf '{"rigs":[%s]}\n' "$body" > "$TMP/rigs-multi.json"
}

{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
# REG_BARRIER makes each registry read wait until both have started, and fail
# once it has waited 20s. Read one after the other, the first never gets past.
reg_barrier() {
  [ -n "${REG_BARRIER:-}" ] || return 0
  : > "$REG_BARRIER/$1"
  waited=0
  while [ ! -e "$REG_BARRIER/rigs" ] || [ ! -e "$REG_BARRIER/orders" ]; do
    [ "$waited" -lt 200 ] || exit 3
    sleep 0.1; waited=$((waited + 1))
  done
}
case "$1 $2" in
  "rig list") reg_barrier rigs; rc="${RIGS_RC:-0}"; [ "$rc" -eq 0 ] || exit "$rc"; cat "$RIGS_JSON" ;;
  # The order registry, for the cadence window. With no ORDERS_JSON it answers
  # nothing, the shape of a registry that did not read.
  "order list") reg_barrier orders; [ -n "${ORDERS_JSON:-}" ] && cat "$ORDERS_JSON"; exit 0 ;;
  "bd "*)     shift; VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@" ;;
  *) exit 0 ;;
esac
GC
# The stub models the two reads the check makes, and the failure shapes the real
# bd shows for each:
#   * `bd list --has-metadata-key ...`  → the armed listing (per-rig fixture).
#      Like real bd's, each row carries its own dependency edges ({issue_id,
#      depends_on_id, type}, taken from the store's edge fixture) and
#      dependency_count, the number of its `blocks` edges. A fixture row that
#      sets either keeps its own, which is how a case models a row read short.
#      BD_FAIL_LIST fails the read, and BD_BLANK_LIST answers whitespace at rc 0.
#   * `bd list --id <csv> --all ...`     → the named blocker beads, DROPPING ids
#      with no row (real --id is silent about a miss). BD_FAIL_BLOCKERS fails it.
# `bd dep list` is no read the check makes, so the stub fails it.
# CALL_LOG, when set, gets one line per read ("<store> <read> <args>"), so a case
# can assert what the check read. For the armed listing only, BD_BARRIER_DIR and
# BD_BARRIER_N make each read wait until N have started (failing after 20s),
# BD_SLOW_STORE and BD_SLOW_SECS slow one store, BD_REAP_SCAN_AT removes the
# check's scratch from under it as a scratch reaper would, and BD_DONE gets the
# store's name once its listing has answered.
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/bd" <<'BD'
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
sub="$1"; shift
db=""; id_csv=""; prev=""; inc_gates=false; inc_infra=false; inc_templates=false
valueflag() { case "$1" in --db|--id|--limit|--actor|--type|--direction|--database|--max-rows|--offset|--has-metadata-key) return 0;; *) return 1;; esac; }
for a in "$@"; do
  if valueflag "$prev"; then
    case "$prev" in --db) db="$a" ;; --id) id_csv="$a" ;; esac
    prev="$a"; continue
  fi
  case "$a" in
    --include-gates) inc_gates=true ;;
    --include-infra) inc_infra=true ;;
    --include-templates) inc_templates=true ;;
  esac
  prev="$a"
done
name=$(basename "$(dirname "$db")")
read="$sub"
if [ "$sub" = "list" ]; then
  if [ -n "$id_csv" ]; then read="list-id"; else read="list-armed"; fi
fi
[ -n "${CALL_LOG:-}" ] && printf '%s %s %s\n' "$name" "$read" "$*" >> "$CALL_LOG"
case "$read" in
  list-id)
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
    else printf '[]'; fi ;;
  list-armed)
    if [ -n "${BD_BARRIER_DIR:-}" ]; then
      : > "$BD_BARRIER_DIR/$name"
      waited=0
      while set -- "$BD_BARRIER_DIR"/*; [ "$#" -lt "$BD_BARRIER_N" ]; do
        [ "$waited" -lt 200 ] || exit 3
        sleep 0.1; waited=$((waited + 1))
      done
    fi
    [ "$name" = "${BD_SLOW_STORE:-}" ] && sleep "$BD_SLOW_SECS"
    [ "$name" = "${BD_REAP_SCAN_AT:-}" ] && rm -rf "${TMPDIR:?}"/gctk-check-armed-dispatch-owed.*
    [ "$name" = "${BD_FAIL_LIST:-}" ] && exit 3
    if [ "$name" = "${BD_BLANK_LIST:-}" ]; then
      printf '  '
    else
      f="$STORES/$name.armed.json"; e="$STORES/$name.edges.json"
      edges='[]'; [ -f "$e" ] && edges=$(cat "$e")
      if [ -f "$f" ]; then
        jq -c --argjson e "$edges" '[ .[] | .id as $id
          | .dependencies = (.dependencies // [ $e[] | select(.issue_id == $id) ])
          | .dependency_count = (if has("dependency_count") then .dependency_count
                                 else ([ .dependencies[] | select(.type == "blocks") ] | length) end) ]' "$f"
      else printf '[]'; fi
    fi
    printf '%s\n' "$name" >> "${BD_DONE:-/dev/null}" ;;
  dep) exit 3 ;;
  *) printf '[]'; exit 0 ;;
esac
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH" STORES="$TMP/stores"

# GC_CITY_PATH is pinned to a fixture city, so the dispatch budget the window is
# derived from never comes from the AMBIENT city.toml. The check's own TMPDIR is
# a directory of its own, so the suite can see what a run leaves behind.
run_check() {
    RIGS_JSON="${RIGS_JSON:-$TMP/rigs.json}" GC_PACK_DIR="$TMP/pack" GC_CITY_PATH="${CITY_DIR:-$TMP/empty-city}" \
        TMPDIR="${CHECK_TMPDIR:-$TMP/tmpdir}" bash "$CHECK" 2>&1
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
# An open arm whose row states its own dependency_count ($2, raw JSON), so the
# count can disagree with the edges the row carries.
acounted() { printf '{"id":"%s","status":"open","dependency_count":%s,"metadata":{"gc.dispatch_when_ready":"rig/pool","gc.dispatch_when_ready_armed_at":"2020-01-01T00:00:00Z"}}' "$1" "$2"; }

# Edge fixtures — the edges the stub hands each listed bead as its own
# dependencies (issue_id blocked-by depends_on_id). A parent-child edge is
# included in one case to prove the check filters to `blocks` only.
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

# --- 8. FAIL CLOSED: a row read short — it counts two `blocks` edges and names
#          one. Judged on the one, a candidate still waiting on the other would
#          read as owed, so it is NOT checked ---------------------------------
armed_store alpha "$(acounted a-8 2)"
edges_store alpha "$(e_blk a-8 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a row naming fewer blockers than it counts warns rather than passing (exit 1)"
has "$OUT" "alpha bead a-8: its row in the listing of $TMP/alpha/.beads names 1 \`blocks\` blocker(s) but counts 2" "the short row is named, with what it names and what it counts"
hasnt "$OUT" "owed but not firing" "a candidate read short is NOT reported as a firm owed finding"
clear_stores

# --- 8a. FAIL CLOSED: a row with no count — a listing that carries no
#          dependency_count cannot show its edges arrived whole ---------------
armed_store alpha "$(acounted a-8a null)"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a row with no dependency_count warns rather than passing (exit 1)"
has "$OUT" "alpha bead a-8a: its row in the listing of $TMP/alpha/.beads names 0 \`blocks\` blocker(s) but counts none" "the uncounted row is named"
hasnt "$OUT" "owed but not firing" "an uncounted candidate is NOT reported as owed off its armed_at"
clear_stores

# --- 8f. a short row costs only its own candidate: each row counts its own
#          edges, so a co-resident row read whole is still judged ------------
armed_store alpha "$(acounted a-8f1 2)" "$(aarmed a-8f2)"
edges_store alpha "$(e_blk a-8f1 b-0)" "$(e_blk a-8f2 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "a short row beside an owed arm warns (exit 1)"
has "$OUT" "alpha bead a-8f1: its row" "the short row is NOT checked"
has "$OUT" "alpha bead a-8f2: armed and" "the co-resident owed arm is still reported"
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

# --- 8e. a finding made before a later read in its store failed still stands -
armed_store alpha "$(astatus a-8e1 deferred)" "$(aarmed a-8e2)"
edges_store alpha "$(e_blk a-8e2 b-0)"
blockers_store alpha "$(b_closed b-0 "$OLD")"
OUT=$(BD_FAIL_BLOCKERS=alpha run_check); RC=$?
eq "$RC" "1" "a stranded arm beside an unreadable blocker listing warns (exit 1)"
has "$OUT" "alpha bead a-8e1: armed for dispatch at status=deferred" "the stranded arm is still reported"
has "$OUT" "could not read blocker statuses for 1 armed bead(s)" "and the failed read is named"
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

# --- 9b. FAIL CLOSED: a listing that is not one JSON array is unreadable, not
#          an empty store ------------------------------------------------------
OUT=$(BD_BLANK_LIST=alpha run_check); RC=$?
eq "$RC" "1" "a listing of whitespace at rc 0 warns rather than passing (exit 1)"
has "$OUT" "alpha: could not list armed beads in $TMP/alpha/.beads (rc=0) — this store was NOT checked" "the store is named as NOT checked"
hasnt "$OUT" "OK:" "it never reads as a clean pass"

# --- 10. FAIL CLOSED: unreadable rig list ------------------------------------
OUT=$(RIGS_RC=2 run_check); RC=$?
eq "$RC" "1" "an unreadable rig list warns (exit 1)"
has "$OUT" "cannot determine" "the rig-list failure is named"

# --- 11. SUSPENDED rig is skipped, not queried -------------------------------
cat > "$TMP/rigs-susp.json" <<EOF
{"rigs":[{"name":"alpha","path":"$TMP/alpha","suspended":true}]}
EOF
CALLS="$TMP/calls"; rm -f "$CALLS"
OUT=$(RIGS_JSON="$TMP/rigs-susp.json" CALL_LOG="$CALLS" run_check); RC=$?
eq "$RC" "0" "a suspended rig is skipped and the check passes"
has "$OUT" "skipped (suspended" "the skip is noted"
eq "$( [ -f "$CALLS" ] && grep -c . "$CALLS" || echo 0)" "0" "the suspended rig's store is never read"

# --- 12. QUIET PATH: no armed beads ------------------------------------------
clear_stores
OUT=$(run_check); RC=$?
eq "$RC" "0" "a store with no armed beads passes"
has "$OUT" "OK:" "the quiet headline is printed"

# --- 13. A STORE COSTS TWO READS: one armed listing, then one blocker read for
#          all its candidates. The listing carries each bead's own edges, so
#          there is no dependency read, and nothing is read per armed bead. ---
armed_store alpha "$(aarmed m-1)" "$(aarmed m-2)" "$(aarmed m-3)"
edges_store alpha "$(e_blk m-1 x-1)" "$(e_blk m-2 x-2)" "$(e_blk m-3 x-3)"
blockers_store alpha "$(b_closed x-1 "$OLD")" "$(b_closed x-2 "$OLD")" "$(b_closed x-3 "$OLD")"
CALLS="$TMP/calls"; rm -f "$CALLS"
OUT=$(CALL_LOG="$CALLS" run_check); RC=$?
eq "$RC" "1" "three owed candidates warn (exit 1)"
has "$OUT" "alpha bead m-1" "the first owed candidate is reported"
has "$OUT" "alpha bead m-2" "the second owed candidate is reported"
has "$OUT" "alpha bead m-3" "the third owed candidate is reported"
eq "$(grep -c '^alpha list-armed ' "$CALLS")" "1" "the store's armed beads are listed once"
eq "$(grep '^alpha list-armed ' "$CALLS" | grep -c -- '--brief')" "1" "the armed listing omits the free text"
eq "$(grep -c '^alpha list-id ' "$CALLS")" "1" "the three candidates' blockers are read in ONE call"
eq "$(grep -c '^alpha list-id .*--id x-1,x-2,x-3 ' "$CALLS")" "1" "that call names every blocker once"
eq "$(grep -vc -E '^alpha list-(armed|id) ' "$CALLS")" "0" "the store makes no other read, so no dependency read"
clear_stores

# --- 14. the stores are scanned at once ---------------------------------------
# Each store's listing waits until all three have started, and fails once it has
# waited 20s. Read one after the other, no listing gets past.
rigs_of alpha beta gamma
for s in alpha beta gamma; do
    armed_store "$s" "$(aarmed "o-$s")"; edges_store "$s" "$(e_blk "o-$s" "b-$s")"; blockers_store "$s" "$(b_open "b-$s")"
done
mkdir -p "$TMP/barrier"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_BARRIER_DIR="$TMP/barrier" BD_BARRIER_N=3 run_check); RC=$?
eq "$RC" "0" "three listings that each wait for all three to start finish clean"
hasnt "$OUT" "NOT checked" "and every store is checked"
clear_stores

# --- 15. findings come out in rig order, however the scans interleave --------
# alpha's listing is slowed so beta's scan finishes first; the report still
# lists alpha's finding before beta's, as the rig list orders them.
rigs_of alpha beta
armed_store alpha "$(aarmed o-1)"; edges_store alpha "$(e_blk o-1 b-1)"; blockers_store alpha "$(b_closed b-1 "$OLD")"
armed_store beta "$(aarmed o-2)"; edges_store beta "$(e_blk o-2 b-2)"; blockers_store beta "$(b_closed b-2 "$OLD")"
: > "$TMP/done"
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_SLOW_STORE=alpha BD_SLOW_SECS=2 BD_DONE="$TMP/done" run_check); RC=$?
eq "$(tr '\n' ' ' < "$TMP/done")" "beta alpha " "premise: beta's listing answered first"
eq "$RC" "1" "an owed arm in each of two stores warns"
LA=$(line_of "$OUT" "alpha bead o-1"); LB=$(line_of "$OUT" "beta bead o-2")
if [ -n "$LA" ] && [ -n "$LB" ] && [ "$LA" -lt "$LB" ]; then ok "alpha's finding is reported before beta's, in rig order"
else bad "alpha's finding is reported before beta's, in rig order (alpha line '${LA}', beta line '${LB}')"; fi
clear_stores

# --- 16. a store the budget cuts is named, and does not starve the others ----
rigs_of alpha beta gamma
armed_store alpha "$(aarmed o-3)"; edges_store alpha "$(e_blk o-3 b-3)"; blockers_store alpha "$(b_closed b-3 "$OLD")"
S=$(date +%s)
OUT=$(RIGS_JSON="$TMP/rigs-multi.json" BD_SLOW_STORE=beta BD_SLOW_SECS=60 GC_DOCTOR_CHECK_TIMEOUT=12 run_check); RC=$?
E=$(( $(date +%s) - S ))
if [ "$E" -lt 12 ]; then ok "the check returns inside its 12s budget (took ${E}s)"
else bad "the check returns inside its 12s budget (took ${E}s)"; fi
eq "$RC" "1" "a store the budget cut warns"
has "$OUT" "beta: could not list armed beads in $TMP/beta/.beads (rc=124) — this store was NOT checked" "the wedged store is named as cut"
has "$OUT" "alpha bead o-3" "a store scanned beside it is still judged"
has "$OUT" "doctor budget before every store was scanned" "and it says the budget, not the data, ended the run"
clear_stores

# --- 17. a scan that cannot report is a store NOT checked, never a pass -------
# The scans report through the check's scratch. Removed mid-run, as a scratch
# reaper would remove it, the scan's report is lost and its store is named.
mkdir -p "$TMP/scratch"
armed_store alpha "$(aarmed r-1)"
OUT=$(CHECK_TMPDIR="$TMP/scratch" BD_REAP_SCAN_AT=alpha run_check); RC=$?
eq "$RC" "1" "a run whose scan lost its scratch warns instead of passing"
has "$OUT" "alpha: the scan of $TMP/alpha/.beads ended without reporting — this store was NOT checked" "the store whose report was lost is named"
hasnt "$OUT" "OK:" "it never reads as a clean pass"
clear_stores

# --- 18. no scratch directory, no scan ----------------------------------------
OUT=$(CHECK_TMPDIR="$TMP/no-such-dir" run_check); RC=$?
eq "$RC" "1" "with no scratch directory the check warns instead of passing"
has "$OUT" "could not create a scratch directory" "the warning names the missing scratch"

# --- the owed window is the deferred-dispatch order's cadence window ----------
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
armed_store alpha "$(aarmed w-1)"
edges_store alpha "$(e_blk w-1 c-1)"
blockers_store alpha "$(b_closed c-1 "$(ago 1200)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "0" "an arm ready for 1200s is inside a 2160s window (the 900s one called it owed)"
hasnt "$OUT" "alpha bead w-1" "…so it is not reported"
blockers_store alpha "$(b_closed c-1 "$(ago 2500)")"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" run_check); RC=$?
eq "$RC" "1" "an arm ready for 2500s, past the window, is owed"
has "$OUT" "(> 2160s)" "…and the finding states the window"
# No registry: the window falls back to the 30m minimum, and says so.
blockers_store alpha "$(b_closed c-1 "$(ago 1500)")"
OUT=$(run_check); RC=$?
eq "$RC" "0" "with no registry, an arm ready for 1500s is inside the 1800s minimum window"
has "$OUT" "did not read, so the owed window uses the 1800s minimum floor" "…and the fallback is noted"
blockers_store alpha "$(b_closed c-1 "$(ago 2000)")"
OUT=$(run_check); RC=$?
eq "$RC" "1" "with no registry, an arm ready for 2000s is owed"
has "$OUT" "(> 1800s)" "…against the minimum window"

# --- 19. the rig and order registries are read at once -----------------------
# Each registry read waits until the other has started, and fails once it has
# waited 20s. Read one after the other, the first fails: an order registry read
# first leaves the window on its fallback, and a rig list read first leaves no
# store to scan.
blockers_store alpha "$(b_closed c-1 "$(ago 2000)")"
mkdir -p "$TMP/regbar"
OUT=$(ORDERS_JSON="$TMP/orders-busy.json" REG_BARRIER="$TMP/regbar" run_check); RC=$?
eq "$RC" "0" "rig and order reads that each wait for the other both answer"
hasnt "$OUT" "did not read" "the order registry read beside the rig list sets the window"
clear_stores

echo "── every run removes its scratch ──"
eq "$(ls -A "$TMP/tmpdir")" "" "no run above left anything in its TMPDIR"

if grep -qE '^[[:space:]]*OWED_WINDOW_SECONDS=[0-9]' "$CHECK"; then
    bad "the check carries no owed-window constant of its own"
else ok "the check carries no owed-window constant of its own"; fi
grep -qF 'assets/scripts/order-cadence.sh' "$CHECK" && ok "the check sources assets/scripts/order-cadence.sh" \
    || bad "the check sources assets/scripts/order-cadence.sh"

echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
