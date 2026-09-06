#!/usr/bin/env bash
# wisp-orphan-purge.test.sh — hermetic suite for wisp-orphan-purge.sh.
# The shared test-harness.sh stub models beads, not Dolt, so this suite writes
# its own `gc` that simulates `gc dolt list|sql|compact` over a per-table state
# file. The DELETE really decrements that state, so the batch loop terminates on
# the same signal it uses in production — a table's row count falling — and a
# broken loop hangs or miscounts here rather than passing vacuously.
# No live city, no Dolt, no network: the GC_* identity vars are stripped once at
# the top and the suite refuses to run if any survived, because every fallback
# in the script under test ends at a real database.
set -uo pipefail

for v in GC_CITY GC_CITY_PATH GC_RIG GC_RIG_ROOT GC_AGENT GC_SESSION_NAME GC_TOOL; do
    unset "$v"
done
for v in GC_CITY GC_CITY_PATH GC_RIG GC_RIG_ROOT GC_AGENT GC_SESSION_NAME GC_TOOL; do
    if [ -n "${!v:-}" ]; then
        echo "FAIL - $v survived the strip; refusing to run against a live city" >&2
        exit 1
    fi
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/wisp-orphan-purge.sh"
[ -x "$SUT" ] || { echo "FAIL - $SUT is not executable" >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-wisp-orphan-purge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac; }

BIN="$TMP/bin"; mkdir -p "$BIN"
export STUB_STATE="$TMP/state"
export STUB_GC_LOG="$TMP/gc.log"
export STUB_DB_DIR="$TMP/dbs/lx"

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
# Simulates `gc dolt` over $STUB_STATE/<table> files holding "<total> <orphans>".
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "dolt" ] || { echo "stub gc: unsupported command ${1:-}" >&2; exit 1; }
shift
case "${1:-}" in
  list)
    printf '%s\t%s\n' "${STUB_DB_NAME:-lx}" "${STUB_DB_DIR:?}"
    exit 0 ;;
  compact)
    exit "${STUB_COMPACT_RC:-0}" ;;
  sql) shift ;;
  *) echo "stub gc: unsupported dolt verb ${1:-}" >&2; exit 1 ;;
esac

Q=""
while [ $# -gt 0 ]; do
  case "$1" in -q) Q="${2:-}"; shift ;; -r) shift ;; esac
  shift
done

emit() { printf '{"rows": [%s]}\n' "$1"; }
tbl_of() { # first known table named in the query
  local t
  for t in wisp_events wisp_labels wisp_comments wisp_dependencies; do
    case "$1" in *"$t"*) printf '%s' "$t"; return 0 ;; esac
  done
  return 1
}
read_state() { awk '{print $1, $2}' "$STUB_STATE/$1" 2>/dev/null; }

case "$Q" in
  *information_schema.tables*)
    name="${Q##*table_name = \'}"; name="${name%%\'*}"
    if [ -e "$STUB_STATE/$name" ] || [ "$name" = wisps ] && [ -z "${STUB_NO_WISPS_TABLE:-}" ]; then
      emit '{"n":"1"}'
    else
      emit '{"n":"0"}'
    fi
    exit 0 ;;
  *"COUNT(*) AS n FROM"*.wisps)
    if [ -s "$STUB_STATE/.wisps" ]; then emit "{\"n\":\"$(cat "$STUB_STATE/.wisps")\"}"
    else emit "{\"n\":\"${STUB_WISPS:-5}\"}"; fi
    exit 0 ;;
  *"COALESCE(SUM(CASE WHEN NOT EXISTS"*)
    t="$(tbl_of "$Q")" || { echo "stub: no table in census" >&2; exit 1; }
    set -- $(read_state "$t")
    # Dolt renders an uncast SUM() over a million rows in scientific notation.
    if [ -n "${STUB_FLOAT_ORPHANS:-}" ]; then
      emit "{\"total\":\"${1:-0}\",\"orphans\":\"2.094721e+06\"}"; exit 0
    fi
    emit "{\"total\":\"${1:-0}\",\"orphans\":\"${2:-0}\"}"; exit 0 ;;
  *"COUNT(*) AS n FROM"*)
    t="$(tbl_of "$Q")" || { echo "stub: no table in count" >&2; exit 1; }
    set -- $(read_state "$t")
    emit "{\"n\":\"${1:-0}\"}"; exit 0 ;;
  *DELETE\ FROM*)
    t="$(tbl_of "$Q")" || { echo "stub: no table in delete" >&2; exit 1; }
    # STUB_DELETE_FAIL models a DELETE that fails at the server: it removes no
    # rows and exits nonzero with text outside sql_failed's patterns, the shape a
    # text-only check reads as an empty batch.
    if [ "${STUB_DELETE_FAIL:-}" = "$t" ]; then
      echo "${STUB_SQL_FAIL_MSG:-transient write failure}" >&2
      exit "${STUB_SQL_FAIL_RC:-7}"
    fi
    lim="${Q##*LIMIT }"; lim="${lim%%;*}"; lim="${lim// /}"
    set -- $(read_state "$t"); total="${1:-0}"; orph="${2:-0}"
    n="$orph"; [ "$n" -gt "$lim" ] && n="$lim"
    # STUB_EAT_LIVE models a predicate that reached a live-linked row.
    extra=0
    if [ "${STUB_EAT_LIVE:-}" = "$t" ] && [ ! -e "$STUB_STATE/.ate-$t" ]; then
      extra="${STUB_EAT_LIVE_N:-1}"; : > "$STUB_STATE/.ate-$t"
      # STUB_WISPS_DROP models wisp-compact expiring wisps during the run, which
      # legitimately moves their children into the orphan class.
      [ -n "${STUB_WISPS_DROP:-}" ] && \
        printf '%s\n' "$(( ${STUB_WISPS:-5} - STUB_WISPS_DROP ))" > "$STUB_STATE/.wisps"
    fi
    printf '%s %s\n' "$((total - n - extra))" "$((orph - n))" > "$STUB_STATE/$t"
    printf '{}\n'; exit 0 ;;
  *DOLT_COMMIT*)
    if [ -n "${STUB_NOTHING_TO_COMMIT:-}" ]; then
      echo "error on line 1 for query CALL DOLT_COMMIT('-m', 'x'): nothing to commit" >&2
      printf '{}\n'; exit 0
    fi
    if [ -n "${STUB_COMMIT_ERR:-}" ]; then
      echo "error on line 1 for query CALL DOLT_COMMIT('-m', 'x'): $STUB_COMMIT_ERR" >&2
      printf '{}\n'; exit 0
    fi
    # STUB_COMMIT_FAIL models a commit that fails at the server with a nonzero
    # exit and text outside sql_failed's patterns.
    if [ -n "${STUB_COMMIT_FAIL:-}" ]; then
      echo "${STUB_SQL_FAIL_MSG:-transient write failure}" >&2
      exit "${STUB_SQL_FAIL_RC:-7}"
    fi
    printf '{}\n'; exit 0 ;;
esac
printf '{}\n'
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"

reset_state() { # <events> <events_orph> <labels> <labels_orph> <comments> <comments_orph> <deps> <deps_orph>
    rm -rf "$STUB_STATE"; mkdir -p "$STUB_STATE" "$STUB_DB_DIR/.dolt"
    printf '%s %s\n' "$1" "$2" > "$STUB_STATE/wisp_events"
    printf '%s %s\n' "$3" "$4" > "$STUB_STATE/wisp_labels"
    printf '%s %s\n' "$5" "$6" > "$STUB_STATE/wisp_comments"
    printf '%s %s\n' "$7" "$8" > "$STUB_STATE/wisp_dependencies"
    : > "$STUB_GC_LOG"
    unset STUB_EAT_LIVE STUB_EAT_LIVE_N STUB_NOTHING_TO_COMMIT STUB_COMMIT_ERR STUB_WISPS_DROP
    unset STUB_NO_WISPS_TABLE STUB_COMPACT_RC
    unset STUB_DELETE_FAIL STUB_COMMIT_FAIL STUB_SQL_FAIL_MSG STUB_SQL_FAIL_RC
    export STUB_WISPS=5
}
orphans_of() { awk '{print $2}' "$STUB_STATE/$1"; }
total_of()   { awk '{print $1}' "$STUB_STATE/$1"; }

echo "# wisp-orphan-purge.sh"

# --- the fail-closed core: an empty `wisps` makes every child row an orphan ---
reset_state 100 90  50 40  10 10  5 0
export STUB_WISPS=0
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "empty wisps table refuses the run"
has "$out" "refusing" "empty wisps names the refusal"
eq "$(orphans_of wisp_events)" "90" "empty wisps deleted nothing"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "empty wisps issued no DELETE"

# mirror: the same fixture with wisps present does purge
reset_state 100 90  50 40  10 10  5 0
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "0" "populated wisps proceeds"
eq "$(orphans_of wisp_events)" "0" "purge drained wisp_events orphans"
eq "$(total_of wisp_events)" "10" "purge left exactly the live-linked rows"
eq "$(orphans_of wisp_labels)" "0" "purge drained wisp_labels orphans"
eq "$(total_of wisp_dependencies)" "5" "table with no orphans is untouched"
has "$out" "removed: 140 rows" "reports the total removed"

# --- --dry-run mutates nothing ----------------------------------------------
reset_state 100 90  50 40  10 10  5 0
out="$("$SUT" --db lx --dry-run 2>&1)"; rc=$?
eq "$rc" "0" "--dry-run exits 0"
eq "$(orphans_of wisp_events)" "90" "--dry-run deleted nothing"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "--dry-run issued no DELETE"
hasnt "$(cat "$STUB_GC_LOG")" "DOLT_COMMIT" "--dry-run committed nothing"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "--dry-run ran no reclaim"
has "$out" "orphans to delete: 140" "--dry-run still reports the census"

# --- batching ----------------------------------------------------------------
reset_state 100 90  0 0  0 0  0 0
"$SUT" --db lx --batch-size 25 >/dev/null 2>&1
eq "$(orphans_of wisp_events)" "0" "batched purge drains the table"
# 4 batches drain 90 orphans (25/25/25/15); the 5th is the probe that ends the
# loop by removing nothing. It scans a table that is already drained, so it is
# cheap exactly when it runs.
eq "$(grep -c 'DELETE FROM wisp_events' "$STUB_GC_LOG")" "5" "90 orphans at batch 25 drains in 4 batches plus a terminating probe"
has "$(grep 'DELETE FROM wisp_events' "$STUB_GC_LOG" | head -1)" "LIMIT 25" "DELETE carries the batch limit"

# --- the delete predicate and the commit shape -------------------------------
reset_state 100 90  0 0  0 0  0 0
"$SUT" --db lx >/dev/null 2>&1
log="$(cat "$STUB_GC_LOG")"
has "$log" "NOT EXISTS (SELECT 1 FROM wisps w WHERE w.id = wisp_events.issue_id)" "DELETE is keyed on the missing wisp"
has "$log" "DOLT_ADD('wisp_events')" "commit stages only the purged table"
hasnt "$log" "DOLT_COMMIT('-A'" "commit never sweeps with -A"

# --- a concurrent writer that already swept the batch -------------------------
reset_state 100 90  0 0  0 0  0 0
export STUB_NOTHING_TO_COMMIT=1
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "0" "'nothing to commit' is not a failure"
eq "$(orphans_of wisp_events)" "0" "purge completes when a writer swept the commit"
unset STUB_NOTHING_TO_COMMIT

# mirror: a real commit error does abort
reset_state 100 90  0 0  0 0  0 0
export STUB_COMMIT_ERR="Error 1105 (HY000): dolt is read-only"
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a real commit error aborts"
has "$out" "commit failed" "commit failure is named"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "commit failure runs no reclaim"
unset STUB_COMMIT_ERR

# --- a mutating statement fails on status, not text --------------------------
# run_sql returns the server's exit code and folds its stderr into the output.
# A DELETE that exits nonzero with text outside sql_failed's patterns leaves the
# table unchanged; a text-only check reads that as an empty batch, ends the loop,
# and reports a clean pass with the orphans intact.
reset_state 100 90  0 0  0 0  0 0
export STUB_DELETE_FAIL=wisp_events STUB_SQL_FAIL_MSG="transient write failure" STUB_SQL_FAIL_RC=7
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a DELETE that fails on status alone aborts"
has "$out" "delete failed" "the delete failure is named"
has "$out" "transient write failure" "the delete failure surfaces the server text"
eq "$(orphans_of wisp_events)" "90" "a failed DELETE deleted nothing"
hasnt "$out" "orphans remaining: 90" "a failed DELETE does not report a clean pass"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "a failed DELETE runs no reclaim"
unset STUB_DELETE_FAIL STUB_SQL_FAIL_MSG STUB_SQL_FAIL_RC

# Mirror: a commit that exits nonzero with unmatched text must abort too, not
# fall through as a durable batch.
reset_state 100 90  0 0  0 0  0 0
export STUB_COMMIT_FAIL=1 STUB_SQL_FAIL_MSG="transient write failure" STUB_SQL_FAIL_RC=7
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a commit that fails on status alone aborts"
has "$out" "commit failed" "the commit failure is named"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "a status-only commit failure runs no reclaim"
unset STUB_COMMIT_FAIL STUB_SQL_FAIL_MSG STUB_SQL_FAIL_RC

# --- live rows lost mid-purge aborts before the reclaim ----------------------
reset_state 100 90  50 40  0 0  0 0
export STUB_EAT_LIVE=wisp_events STUB_EAT_LIVE_N=3
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a purge that reached a live row aborts"
has "$out" "reached a live wisp" "the abort names the cause"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "no reclaim after a live-row loss"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM wisp_labels" "abort stops before the next table"
unset STUB_EAT_LIVE STUB_EAT_LIVE_N

# Mirror: the same drop, with wisps expiring during the run, is the ordinary
# case. `wisp-compact` expires wisps hourly and a purge takes tens of minutes,
# so a guard that fired here would abort nearly every real run.
reset_state 100 90  50 40  0 0  0 0
export STUB_EAT_LIVE=wisp_events STUB_EAT_LIVE_N=3 STUB_WISPS_DROP=2
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "0" "a live-linked drop explained by wisp expiry does not abort"
has "$out" "2 wisps expired during the run" "the run says what accounted for the drop"
has "$(cat "$STUB_GC_LOG")" "DELETE FROM wisp_labels" "the pass continues to the next table"
has "$(cat "$STUB_GC_LOG")" "compact --gc-only" "the pass still reclaims"
unset STUB_EAT_LIVE STUB_EAT_LIVE_N STUB_WISPS_DROP

# --- reclaim wiring ----------------------------------------------------------
reset_state 100 90  0 0  0 0  0 0
"$SUT" --db lx >/dev/null 2>&1
has "$(cat "$STUB_GC_LOG")" "dolt compact --gc-only --only-db lx" "reclaim runs the sanctioned command"

reset_state 100 90  0 0  0 0  0 0
"$SUT" --db lx --no-reclaim >/dev/null 2>&1
hasnt "$(cat "$STUB_GC_LOG")" "compact" "--no-reclaim skips the reclaim"

reset_state 100 0  50 0  10 0  5 0
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "0" "a store with no orphans exits 0"
hasnt "$(cat "$STUB_GC_LOG")" "compact" "nothing deleted runs no reclaim"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "nothing deleted issues no DELETE"

reset_state 100 90  0 0  0 0  0 0
export STUB_COMPACT_RC=3
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "3" "a failed reclaim surfaces its exit code"
has "$out" "rows are deleted and committed" "a failed reclaim says the rows still went"
eq "$(orphans_of wisp_events)" "0" "a failed reclaim does not undo the purge"
unset STUB_COMPACT_RC

# --- a missing child table refuses -------------------------------------------
reset_state 100 90  50 40  10 10  5 0
rm -f "$STUB_STATE/wisp_comments"
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a missing child table refuses the run"
has "$out" "wisp_comments does not exist" "the refusal names the table"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "a missing table issued no DELETE"

reset_state 100 90  50 40  10 10  5 0
export STUB_NO_WISPS_TABLE=1
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a missing wisps table refuses the run"
unset STUB_NO_WISPS_TABLE

# --- a census count too large to render as an integer ------------------------
# Dolt returns SUM() as a float, so past a million rows an uncast count arrives
# as `2.094721e+06`. The SQL casts it back; if that cast is ever dropped, the
# numeric guard has to refuse rather than treat the string as a row count.
reset_state 2117303 2094721  0 0  0 0  0 0
"$SUT" --db lx --dry-run >/dev/null 2>&1
has "$(cat "$STUB_GC_LOG")" "AS SIGNED) AS orphans" "census casts the orphan count back to an integer"

reset_state 2117303 2094721  0 0  0 0  0 0
export STUB_FLOAT_ORPHANS=1
out="$("$SUT" --db lx 2>&1)"; rc=$?
eq "$rc" "1" "a float-rendered orphan count refuses rather than deleting"
has "$out" "unreadable orphan count" "the refusal names the unreadable count"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "a float-rendered count issued no DELETE"
unset STUB_FLOAT_ORPHANS

# --- usage -------------------------------------------------------------------
help="$("$SUT" --help 2>&1)"; eq "$?" "0" "--help exits 0"
has "$help" "--batch-size <n>" "--help lists the flags"
has "$help" "wisp_dependencies" "--help carries the header description"
hasnt "$help" "set -uo pipefail" "--help stops at the header, not the shell directive"

reset_state 100 90  0 0  0 0  0 0
out="$("$SUT" --db 'lx; DROP DATABASE x' 2>&1)"; eq "$?" "2" "a non-identifier --db is rejected"
out="$("$SUT" --db lx --batch-size 0 2>&1)"; eq "$?" "2" "--batch-size 0 is rejected"
out="$("$SUT" --db lx --batch-size abc 2>&1)"; eq "$?" "2" "a non-numeric --batch-size is rejected"
out="$("$SUT" --wat 2>&1)"; eq "$?" "2" "an unknown flag is rejected"
out="$("$SUT" --db 2>&1)"; eq "$?" "2" "--db with no value is rejected"
hasnt "$(cat "$STUB_GC_LOG")" "DELETE FROM" "no usage error reached a DELETE"

reset_state 100 90  0 0  0 0  0 0
out="$("$SUT" --db nosuchdb 2>&1)"; rc=$?
eq "$rc" "1" "a database absent from \`gc dolt list\` refuses"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
