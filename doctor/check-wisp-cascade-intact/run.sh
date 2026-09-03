#!/usr/bin/env bash
# doctor/check-wisp-cascade-intact — every bead store enforces the wisp
# auxiliary cascade in its own schema. wisp_labels, wisp_events and
# wisp_comments each carry a FOREIGN KEY on issue_id, and wisp_child_counters
# one on parent_id, all REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE.
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
US=$'\037'

# Severity for a store missing the constraint. A store that has already
# accumulated orphan rows cannot take the constraint back until those rows are
# gone — ADD CONSTRAINT validates existing rows and fails on the first
# violation — so the finding names work sequenced behind a purge rather than
# work that can be done on sight. Raise it to "error" once no store carries a
# standing backlog, which is the point at which every finding is a fresh
# divergence repairable immediately.
SEVERITY="${GC_DOCTOR_WISP_CASCADE_SEVERITY:-warn}"
case "$SEVERITY" in
    warn|error) ;;
    # A check about a constraint that went missing without a word does not get
    # to downgrade itself on a typo.
    *) echo "cannot determine wisp cascade integrity"
       printf '  - %s\n' "GC_DOCTOR_WISP_CASCADE_SEVERITY=\"$SEVERITY\" is neither warn nor error; refusing to guess a severity."
       exit 1 ;;
esac

# The four cascade edges, each as name:table:column. The referenced side is
# wisps(id) and both rules are CASCADE for all four, asserted per row below. A
# present foreign key is checked against its whole tuple, not just its name: a
# same-named key with a DELETE_RULE other than CASCADE, the wrong source column,
# or a different referenced table reads as present while still failing to clear
# the auxiliary rows on delete — the exact state this check has to gate against
# once lx is repaired. The canonical names stay the key: enforcing the same edge
# under a different name reads as missing here, and renaming one is a schema
# migration that has to reach every store anyway.
EXPECTED=(
    "fk_wisp_labels_issue:wisp_labels:issue_id"
    "fk_wisp_events_issue:wisp_events:issue_id"
    "fk_wisp_comments_issue:wisp_comments:issue_id"
    "fk_wisp_child_counters_parent:wisp_child_counters:parent_id"
)
REF_TABLE=wisps
REF_COLUMN=id

# The IN-clause is built from EXPECTED so the query and the comparison cannot
# name different sets: a constraint listed in one and not the other would read
# as permanently missing, or never be asked about at all.
in_clause=""
for want in "${EXPECTED[@]}"; do in_clause="${in_clause:+$in_clause,}'${want%%:*}'"; done

# REFERENTIAL_CONSTRAINTS carries both rules and the referenced table;
# KEY_COLUMN_USAGE carries the source and referenced columns. Joined on the
# constraint, one row per single-column foreign key yields the whole tuple the
# comparison below checks — the name alone, which is all TABLE_CONSTRAINTS
# exposes, proves a constraint exists, not that it cascades.
FK_QUERY="SELECT rc.CONSTRAINT_NAME AS name, rc.TABLE_NAME AS tbl, kcu.COLUMN_NAME AS col, rc.REFERENCED_TABLE_NAME AS ref_tbl, kcu.REFERENCED_COLUMN_NAME AS ref_col, rc.DELETE_RULE AS del_rule, rc.UPDATE_RULE AS upd_rule
 FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc
 JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
   ON kcu.CONSTRAINT_SCHEMA = rc.CONSTRAINT_SCHEMA
  AND kcu.CONSTRAINT_NAME = rc.CONSTRAINT_NAME
  AND kcu.TABLE_NAME = rc.TABLE_NAME
 WHERE rc.CONSTRAINT_SCHEMA = DATABASE()
   AND rc.CONSTRAINT_NAME IN ($in_clause)"

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
    | join("")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine wisp cascade integrity"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths; there is no set of bead stores to scan."
    exit 1
fi

declare -A GOT
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
    parsed=$(printf '%s' "$raw" | jq -r '.[]? | [.name, .tbl, .col, .ref_tbl, .ref_col, .del_rule, .upd_rule] | join("")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: constraint listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    # name -> "tbl<US>col<US>ref_tbl<US>ref_col<US>del_rule<US>upd_rule"
    GOT=()
    while IFS=$'\037' read -r gname gtbl gcol grtbl grcol gdel gupd; do
        [ -n "$gname" ] || continue
        GOT["$gname"]="$gtbl$US$gcol$US$grtbl$US$grcol$US$gdel$US$gupd"
    done <<< "$parsed"

    problems=(); absent=0
    for want in "${EXPECTED[@]}"; do
        name="${want%%:*}"; rest="${want#*:}"; etbl="${rest%%:*}"; ecol="${rest##*:}"
        got="${GOT[$name]:-}"
        if [ -z "$got" ]; then
            problems+=("$name (absent)"); absent=$((absent + 1)); continue
        fi
        [ "$got" = "$etbl$US$ecol$US$REF_TABLE$US$REF_COLUMN${US}CASCADE${US}CASCADE" ] && continue
        # Present but not the whole tuple — name each field that diverges, so
        # the finding says what to fix, not merely that something is off.
        IFS="$US" read -r gtbl gcol grtbl grcol gdel gupd <<< "$got"
        d=""
        [ "$gtbl" = "$etbl" ]        || d="${d:+$d; }table=$gtbl want $etbl"
        [ "$gcol" = "$ecol" ]        || d="${d:+$d; }column=$gcol want $ecol"
        [ "$grtbl" = "$REF_TABLE" ]  || d="${d:+$d; }references=$grtbl want $REF_TABLE"
        [ "$grcol" = "$REF_COLUMN" ] || d="${d:+$d; }referenced column=$grcol want $REF_COLUMN"
        [ "$gdel" = "CASCADE" ]      || d="${d:+$d; }ON DELETE=$gdel want CASCADE"
        [ "$gupd" = "CASCADE" ]      || d="${d:+$d; }ON UPDATE=$gupd want CASCADE"
        problems+=("$name ($d)")
    done

    [ "${#problems[@]}" -ne 0 ] || continue

    # Every expected name absent is ambiguous: a store with no wisp plane at all
    # answers the same way. A present-but-wrong constraint proves the plane
    # exists, so only the all-absent case pays for the second query.
    if [ "$absent" -eq "${#EXPECTED[@]}" ]; then
        plane=$(run_bounded gc bd sql --db "$rig_path/.beads" --json "$PLANE_QUERY" 2>/dev/null)
        if [ "$(printf '%s' "$plane" | jq -r '.[0].n // 0' 2>/dev/null)" = "0" ]; then
            notes+=("$label: no wisps table — this store carries no wisp plane, so the cascade does not apply")
            continue
        fi
    fi

    finding="$label: $rig_path/.beads is not enforcing ${#problems[@]} of ${#EXPECTED[@]} wisp cascade constraints (${problems[*]}) — a constraint that is absent or does not cascade lets the bulk wisp delete leave the matching auxiliary rows behind, and a write naming a wisp with no row in wisps is accepted rather than refused. Repair an absent constraint with ALTER TABLE <table> ADD CONSTRAINT <name> FOREIGN KEY (issue_id, or parent_id on wisp_child_counters) REFERENCES wisps(id) ON DELETE CASCADE ON UPDATE CASCADE; a constraint present with the wrong shape must be dropped (ALTER TABLE <table> DROP FOREIGN KEY \`<name>\`) and re-added the same way. Adding validates existing rows and so has to follow a purge of this store's orphaned auxiliary rows"
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
