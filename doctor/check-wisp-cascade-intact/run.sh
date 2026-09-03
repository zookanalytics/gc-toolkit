#!/usr/bin/env bash
# doctor/check-wisp-cascade-intact — every bead store enforces the wisp
# auxiliary cascade in its own schema. wisp_labels, wisp_events and
# wisp_comments each carry a FOREIGN KEY on issue_id, and wisp_child_counters
# one on parent_id, all REFERENCES wisps(id) ON DELETE CASCADE.
#
# The constraint carries two properties the code does not carry itself.
# Deleting a wisp through the bulk path issues DELETE FROM wisps plus the
# sync-plane dependency delete and touches no auxiliary table, so the cascade
# is what removes those rows. Writing an auxiliary row that names a wisp with
# no row in wisps is refused only by the constraint; without it the write is
# accepted and the row is an orphan the moment it lands. A store missing the
# constraint therefore accumulates auxiliary rows unreachable from any wisp,
# and nothing in the store's own behaviour reports it.
#
# Schema is asserted, not row counts. A store can be arbitrarily far behind on
# cleanup and still be correct going forward, while a store missing the
# constraint is accumulating whatever its current counts say; and counting
# orphans means a join across the largest tables in the store, which a check
# on a cadence must not issue.
#
# Read-only. Exit 0=OK 1=Warning 2=Error. stdout: message, then "  - detail"
# lines. Probes bounded; an UNREADABLE store warns (1), never passes.

set -u

BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# Severity for a store missing the constraint. A store that has already
# accumulated orphan rows cannot take the constraint back until those rows are
# gone — ADD CONSTRAINT validates existing rows and fails on the first
# violation — so the finding names work sequenced behind a purge rather than
# work that can be done on sight. Raise it to "error" once no store carries a
# standing backlog, which is the point at which every finding is a fresh
# divergence repairable immediately.
SEVERITY="${GC_DOCTOR_WISP_CASCADE_SEVERITY:-warn}"

# issue_id on the three row tables, parent_id on the counter table. Names, not
# shapes: a constraint under a different name enforcing the same edge reads as
# missing here, and renaming one is a schema migration that has to reach every
# store anyway.
EXPECTED="fk_wisp_labels_issue fk_wisp_events_issue fk_wisp_comments_issue fk_wisp_child_counters_parent"
EXPECTED_COUNT=4

FK_QUERY="SELECT CONSTRAINT_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
 WHERE CONSTRAINT_SCHEMA = DATABASE()
   AND CONSTRAINT_TYPE = 'FOREIGN KEY'
   AND CONSTRAINT_NAME IN ('fk_wisp_labels_issue','fk_wisp_events_issue','fk_wisp_comments_issue','fk_wisp_child_counters_parent')"

# Zero constraints is ambiguous on its own: a store with no wisp plane at all
# answers exactly as one that lost the cascade. Only that case pays for the
# second query.
PLANE_QUERY="SELECT COUNT(*) AS n FROM INFORMATION_SCHEMA.TABLES
 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'wisps'"

errors=(); warnings=(); notes=()
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }

rigs_raw=$(run_bounded gc rig list --json 2>/dev/null); rigs_rc=$?
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine wisp cascade integrity"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    raw=$(run_bounded gc bd sql --db "$rig_path/.beads" --json "$FK_QUERY" 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        warnings+=("$label: could not read INFORMATION_SCHEMA from $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    present=$(printf '%s' "$raw" | jq -r '.[]?.CONSTRAINT_NAME // empty' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: constraint listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    missing=()
    for want in $EXPECTED; do
        found=no
        while IFS= read -r have; do
            [ "$have" = "$want" ] && { found=yes; break; }
        done <<< "$present"
        [ "$found" = "yes" ] || missing+=("$want")
    done

    [ "${#missing[@]}" -ne 0 ] || continue

    if [ "${#missing[@]}" -eq "$EXPECTED_COUNT" ]; then
        plane=$(run_bounded gc bd sql --db "$rig_path/.beads" --json "$PLANE_QUERY" 2>/dev/null)
        if [ "$(printf '%s' "$plane" | jq -r '.[0].n // 0' 2>/dev/null)" = "0" ]; then
            notes+=("$label: no wisps table — this store carries no wisp plane, so the cascade does not apply")
            continue
        fi
    fi

    finding="$label: $rig_path/.beads is missing ${#missing[@]} of the wisp cascade constraints (${missing[*]}) — the bulk wisp delete leaves the matching auxiliary rows behind, and a write naming a wisp with no row in wisps is accepted rather than refused. Repair is ALTER TABLE <table> ADD CONSTRAINT <name> FOREIGN KEY (issue_id, or parent_id on wisp_child_counters) REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE, which validates existing rows and so has to follow a purge of this store's orphaned auxiliary rows"
    if [ "$SEVERITY" = "error" ]; then errors+=("$finding"); else warnings+=("$finding"); fi
done <<< "$scopes"

if [ "${#errors[@]}" -ne 0 ]; then
    echo "wisp cascade not enforced: ${#errors[@]} store(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "wisp cascade incomplete: ${#warnings[@]} finding(s)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every store enforces the wisp auxiliary cascade on wisps(id)"
detail ${notes[@]+"${notes[@]}"}
exit 0
