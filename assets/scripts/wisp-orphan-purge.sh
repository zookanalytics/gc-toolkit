#!/usr/bin/env bash
# wisp-orphan-purge.sh — delete wisp child rows whose owning wisp is gone, then
# reclaim the space they held.
# `wisp-compact` expires rows from `wisps` and leaves their children behind, so
# `wisp_events`, `wisp_labels`, `wisp_comments` and `wisp_dependencies`
# accumulate rows no wisp points at. Every commit carries that bulk, so a store
# re-grows to the same size after any reclaim: a reclaim repacks chunks and
# never removes a row, which is why this deletes first and reclaims second.
# Orphan means `issue_id` has no row in `wisps`. That predicate rides inside the
# DELETE, so a wisp created or expired mid-run is judged at delete time and the
# run needs no snapshot to be race-free.
# Guards, all fail-closed: an empty or unreadable `wisps` makes every child row
# look orphaned, so a zero count refuses the run; a missing table refuses it; a
# batch that removes nothing ends the table rather than spinning; and a table
# whose live-linked rows dropped over its own purge aborts the pass before the
# next table and before the reclaim.
# Batched because one transaction over millions of rows reaps the connection.
# Each batch commits its own tables, so an interrupted run leaves durable work
# and a clean working set, and re-running resumes. A concurrent writer
# committing `-A` may sweep a batch into its own commit first, which lands the
# same rows and leaves nothing to commit.
# Callers: operators, and any cadence that needs the store's dead weight gone.
# Safe against a live city: the managed Dolt server stays up and
# `gc dolt compact --gc-only` needs no stop.
# Exit: 0 pass completed, 1 aborted on a guard or a failed step, 2 usage.
set -uo pipefail

PROG="wisp-orphan-purge"
GC="${GC_TOOL:-gc}"
CHILD_TABLES="wisp_events wisp_labels wisp_comments wisp_dependencies"

DB="${WISP_PURGE_DB:-lx}"
BATCH="${WISP_PURGE_BATCH:-50000}"
DRY_RUN=0
RECLAIM=1

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "$PROG: $1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --db) [ $# -ge 2 ] || die "--db needs a database name" 2; DB="$2"; shift ;;
        --batch-size) [ $# -ge 2 ] || die "--batch-size needs a count" 2; BATCH="$2"; shift ;;
        --dry-run) DRY_RUN=1 ;;
        --no-reclaim) RECLAIM=0 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unexpected argument: $1" 2 ;;
    esac
    shift
done

command -v jq >/dev/null 2>&1 || die "jq is required"
case "$DB" in ''|*[!A-Za-z0-9_]*) die "--db must be alphanumeric/underscore, got '$DB'" 2 ;; esac
case "$BATCH" in ''|*[!0-9]*) die "--batch-size must be a positive integer, got '$BATCH'" 2 ;; esac
[ "$BATCH" -gt 0 ] || die "--batch-size must be a positive integer, got '$BATCH'" 2

# --- SQL ---------------------------------------------------------------------
# `gc dolt sql -q ... -r json` emits one JSON object per statement: `{}` for a
# statement with no result set, `{"rows":[...]}` otherwise. Values arrive as
# strings over the server and as numbers from a direct `dolt sql`, so every read
# interpolates them as strings and accepts both. A `USE <db>` prefix sets the
# database: DOLT_ADD and DOLT_COMMIT resolve against the session's database and
# reject a qualified `CALL <db>.DOLT_ADD(...)` with "Empty database name".
run_sql() { "$GC" dolt sql -q "$1" -r json 2>&1; }

sql_failed() { # <output>
    case "$1" in *"error on line"*|*"Error "*) return 0 ;; *) return 1 ;; esac
}

# Reads named columns out of the LAST result set the statement list produced.
sql_row() { # <sql> <jq-expression over .rows[0]>
    local out
    out="$(run_sql "$1")" || { printf '%s\n' "$out" >&2; return 1; }
    if sql_failed "$out"; then printf '%s\n' "$out" >&2; return 1; fi
    printf '%s\n' "$out" \
        | jq -r 'select(type == "object" and has("rows") and (.rows | length) > 0) | .rows[0] | '"$2" 2>/dev/null \
        | tail -1
}

numeric() { # <value> <what>
    case "$1" in ''|*[!0-9]*) die "unreadable $2: '$1'" ;; esac
}

table_exists() { # <table>
    local n
    n="$(sql_row "SELECT COUNT(*) AS n FROM information_schema.tables WHERE table_schema = '$DB' AND table_name = '$1'" '"\(.n)"')" || return 1
    [ "${n:-0}" -gt 0 ] 2>/dev/null
}

row_count() { sql_row "SELECT COUNT(*) AS n FROM $DB.$1" '"\(.n)"'; }

# Total rows, and how many of them no wisp claims.
census() { # <table> -> "<total> <orphans>"
    sql_row "SELECT COUNT(*) AS total, COALESCE(SUM(CASE WHEN NOT EXISTS (SELECT 1 FROM $DB.wisps w WHERE w.id = $DB.$1.issue_id) THEN 1 ELSE 0 END), 0) AS orphans FROM $DB.$1" '"\(.total) \(.orphans)"'
}

human() { # <bytes>
    [ -n "$1" ] || { printf 'unknown'; return 0; }
    awk -v b="$1" 'BEGIN { split("B KiB MiB GiB TiB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        printf (i == 1 ? "%d%s" : "%.2f%s"), b, u[i] }'
}

# --- pre-flight --------------------------------------------------------------
echo "$PROG: database=$DB batch=$BATCH dry_run=$DRY_RUN reclaim=$RECLAIM"

DB_PATH="$("$GC" dolt list 2>/dev/null | awk -F'\t' -v d="$DB" '$1 == d {print $2; exit}')"
[ -n "$DB_PATH" ] || die "database '$DB' is not in \`gc dolt list\`"
size_bytes() {
    [ -d "$DB_PATH/.dolt" ] || { echo ""; return 0; }
    du -sb "$DB_PATH/.dolt" 2>/dev/null | awk '{print $1}'
}

table_exists wisps || die "table $DB.wisps does not exist — refusing to treat every child row as an orphan"

# The fail-closed core. An empty `wisps` satisfies the orphan predicate for
# every child row, so a zero here — a genuinely empty store, a table mid
# migration, a read that failed open — would authorise deleting all of them.
# Nothing downstream distinguishes that from a correct purge.
LIVE_WISPS="$(sql_row "SELECT COUNT(*) AS n FROM $DB.wisps" '"\(.n)"')" || die "cannot count $DB.wisps"
numeric "$LIVE_WISPS" "wisp count"
[ "$LIVE_WISPS" -gt 0 ] || die "$DB.wisps is empty — every child row would look orphaned; refusing"

for t in $CHILD_TABLES; do
    table_exists "$t" || die "table $DB.$t does not exist"
done

declare -A BEFORE_TOTAL BEFORE_ORPH AFTER_TOTAL AFTER_ORPH DELETED

SIZE_BEFORE="$(size_bytes)"
echo
echo "$PROG: before ($LIVE_WISPS live wisps, .dolt $(human "$SIZE_BEFORE"))"
printf '  %-20s %12s %12s %12s\n' table total orphans live
TOTAL_ORPHANS=0
for t in $CHILD_TABLES; do
    row="$(census "$t")" || die "cannot census $DB.$t"
    total="${row%% *}"; orph="${row##* }"
    numeric "$total" "row total for $DB.$t"; numeric "$orph" "orphan count for $DB.$t"
    printf '  %-20s %12s %12s %12s\n' "$t" "$total" "$orph" "$((total - orph))"
    BEFORE_TOTAL[$t]="$total"; BEFORE_ORPH[$t]="$orph"
    TOTAL_ORPHANS=$((TOTAL_ORPHANS + orph))
done
echo "  orphans to delete: $TOTAL_ORPHANS"

if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "$PROG: --dry-run — nothing deleted, nothing committed, no reclaim run."
    exit 0
fi

# --- purge -------------------------------------------------------------------
# The predicate lives in the DELETE, so each batch is judged against the `wisps`
# of that moment: a wisp expiring mid-run makes its children orphans and they
# go, a wisp created mid-run protects its children. LIMIT bounds the
# transaction.
# Progress comes from the table's own row count rather than ROW_COUNT(): over
# the server ROW_COUNT() reports the batch, but a direct `dolt sql` auto-commits
# a modifying statement and the following ROW_COUNT() reads -1. A count delta is
# right on both, and concurrent inserts only make it conservative.
DELETED_TOTAL=0
for t in $CHILD_TABLES; do
    want="${BEFORE_ORPH[$t]}"; cur="${BEFORE_TOTAL[$t]}"
    deleted=0
    if [ "$want" -gt 0 ]; then
        while :; do
            out="$(run_sql "USE $DB; DELETE FROM $t WHERE NOT EXISTS (SELECT 1 FROM wisps w WHERE w.id = $t.issue_id) LIMIT $BATCH;")"
            sql_failed "$out" && { printf '%s\n' "$out" >&2; die "delete failed on $DB.$t after $deleted rows"; }
            # Stage only this table: `-A` would sweep in a concurrent writer's
            # in-flight change. A writer that already swept ours leaves nothing.
            out="$(run_sql "USE $DB; CALL DOLT_ADD('$t'); CALL DOLT_COMMIT('-m', '$PROG: purge orphaned $t rows from $DB');")"
            if sql_failed "$out"; then
                case "$out" in
                    *"nothing to commit"*) : ;;
                    *) printf '%s\n' "$out" >&2; die "commit failed on $DB.$t after $deleted rows" ;;
                esac
            fi
            new="$(row_count "$t")" || die "cannot re-count $DB.$t after $deleted rows"
            numeric "$new" "row count for $DB.$t"
            removed=$((cur - new)); cur="$new"
            [ "$removed" -gt 0 ] || break
            deleted=$((deleted + removed))
            # Live progress only on a terminal; a log gets one line per table.
            [ -t 1 ] && printf '\r  %-20s deleted %s' "$t" "$deleted"
        done
        if [ "$deleted" -gt 0 ]; then
            [ -t 1 ] && printf '\r'
            printf '  %-20s deleted %s\n' "$t" "$deleted"
        fi
    fi
    DELETED[$t]="$deleted"
    DELETED_TOTAL=$((DELETED_TOTAL + deleted))

    # Abort before the next table and before the reclaim if this one lost rows a
    # wisp still points at. Live-linked rows may GROW during a run; only a drop
    # means the predicate reached something it must not.
    row="$(census "$t")" || die "cannot re-census $DB.$t"
    now_total="${row%% *}"; now_orph="${row##* }"
    numeric "$now_total" "row total for $DB.$t"; numeric "$now_orph" "orphan count for $DB.$t"
    was_total="${BEFORE_TOTAL[$t]}"; was_orph="${BEFORE_ORPH[$t]}"
    if [ "$((now_total - now_orph))" -lt "$((was_total - was_orph))" ]; then
        die "$DB.$t live-linked rows fell from $((was_total - was_orph)) to $((now_total - now_orph)) — the purge reached a live wisp; aborting before reclaim"
    fi
    AFTER_TOTAL[$t]="$now_total"; AFTER_ORPH[$t]="$now_orph"
done

# --- reclaim -----------------------------------------------------------------
# DELETE alone does not shrink the store and briefly grows it: Dolt keeps the
# deleted rows in history until a full GC rewrites oldgen.
RECLAIM_RC=0
if [ "$RECLAIM" -eq 1 ] && [ "$DELETED_TOTAL" -gt 0 ]; then
    FREE_KB="$(df -Pk "$DB_PATH" 2>/dev/null | awk 'NR == 2 {print $4}')"
    NEED_KB=$(( ${SIZE_BEFORE:-0} / 1024 ))
    if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$NEED_KB" ]; then
        echo "$PROG: skipping reclaim — $(human "$((FREE_KB * 1024))") free is under the $(human "${SIZE_BEFORE:-0}") the rewrite may transiently need." >&2
        echo "$PROG: rows are deleted and committed; run '$GC dolt compact --gc-only --only-db $DB' once there is room." >&2
        RECLAIM_RC=1
    else
        echo
        echo "$PROG: reclaiming ($GC dolt compact --gc-only --only-db $DB)"
        "$GC" dolt compact --gc-only --only-db "$DB" || RECLAIM_RC=$?
        [ "$RECLAIM_RC" -eq 0 ] || echo "$PROG: reclaim exited $RECLAIM_RC; rows are deleted and committed" >&2
    fi
fi

# --- report ------------------------------------------------------------------
SIZE_AFTER="$(size_bytes)"
LIVE_WISPS_AFTER="$(sql_row "SELECT COUNT(*) AS n FROM $DB.wisps" '"\(.n)"')"
echo
echo "$PROG: after ($LIVE_WISPS_AFTER live wisps, .dolt $(human "$SIZE_AFTER"))"
printf '  %-20s %12s %12s %12s %12s\n' table total orphans live removed
REMAINING=0
for t in $CHILD_TABLES; do
    at="${AFTER_TOTAL[$t]}"; ao="${AFTER_ORPH[$t]}"; d="${DELETED[$t]}"
    printf '  %-20s %12s %12s %12s %12s\n' "$t" "$at" "$ao" "$((at - ao))" "$d"
    REMAINING=$((REMAINING + ao))
done
echo "  removed: $DELETED_TOTAL rows; orphans remaining: $REMAINING"
[ -n "$SIZE_BEFORE" ] && [ -n "$SIZE_AFTER" ] && echo "  .dolt:   $(human "$SIZE_BEFORE") -> $(human "$SIZE_AFTER")"
[ "$REMAINING" -gt 0 ] && echo "  orphans appear as wisps expire; re-run to clear the remainder."

exit "$RECLAIM_RC"
