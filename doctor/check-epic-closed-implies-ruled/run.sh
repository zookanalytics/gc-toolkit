#!/usr/bin/env bash
# doctor/check-epic-closed-implies-ruled — I15: a closed epic was ruled closed.
# An epic closes on a ruling on its hypothesis, never as a side effect of its last
# unit merging (docs/epics.md). The ruling is continue, shift, or close, and only
# close is terminal; a close ruling carries its outcome (epic_ruling_reason). A
# CLOSED issue_type=epic other than a Delivery that lacks the close ruling with
# its outcome was therefore closed by hand without its ruling, on a ruling that
# keeps it open, or with no outcome (error). An incomplete Epic, one with no
# hypothesis and no epic parent, is held to the same ruling. A Delivery, an epic
# whose parent is an epic and that carries no hypothesis, has no ruling of its
# own: its epic carries it.
# finalize-gate.sh clause_epic_ruling_recorded applies the same predicate to the
# close paths that run the gate, and this is the after-the-fact backstop for a
# bare `gc bd close`, which runs no gate.
# One shape is out of scope: an epic that names its successor through a
# duplicates or supersedes edge was retired into it by bead-rehome.sh, which IS
# an explicit terminal state (the same exemption check-closed-implies-landed
# makes) — a deliberate disposition, not a silent close. The listing's rows
# carry every edge, one onto a bead in another rig's store included.
# Read-only, ledger-only, offline-safe. Exit 0=OK 1=Warning 2=Error. stdout:
# first line = message, then "  - detail" lines. Probes bounded; an UNREADABLE
# store warns (1), never passes.

set -u

errors=(); warnings=(); notes=()
# >>> doctor-budget
# One deadline for the whole check, anchored at process start. `gc doctor
# --check-timeout` (default 60s) abandons an overrunning check and discards
# everything it had buffered, so a check that has not printed by then is never
# heard. A per-probe constant does not hold that line: the probes below run
# once per rig, so their ceilings sum. Each probe gets the time still left
# instead, capped at half the budget so one wedged store cannot eat the rest,
# and a probe that no longer fits is refused with 124 — `timeout`'s own expiry
# code, which every caller's "this store was NOT checked" arm already handles.
# GC_DOCTOR_CHECK_TIMEOUT overrides the default, in whole seconds. Nothing
# exports it: the runner passes GC_CITY_PATH and GC_PACK_DIR and no budget.
BUDGET_DEFAULT=60; BUDGET_RESERVE=5; BUDGET_MIN_PROBE=2
budget_now() { if [ -n "${EPOCHSECONDS:-}" ]; then printf %s "$EPOCHSECONDS"; else date +%s; fi; }
budget_init() {
    BUDGET_TOTAL="${GC_DOCTOR_CHECK_TIMEOUT:-$BUDGET_DEFAULT}"; BUDGET_TOTAL="${BUDGET_TOTAL%s}"
    case "$BUDGET_TOTAL" in ''|*[!0-9]*) BUDGET_TOTAL="$BUDGET_DEFAULT" ;; esac
    BUDGET_CAP=$(( BUDGET_TOTAL / 2 ))
    BUDGET_DEADLINE=$(( $(budget_now) - SECONDS + BUDGET_TOTAL - BUDGET_RESERVE ))
}
budget_slice() {
    local left=$(( BUDGET_DEADLINE - $(budget_now) ))
    [ "$left" -le "$BUDGET_CAP" ] || left="$BUDGET_CAP"
    [ "$left" -ge 0 ] || left=0
    printf %s "$left"
}
budget_spent() { [ "$(budget_slice)" -lt "$BUDGET_MIN_PROBE" ]; }
run_bounded() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@" </dev/null; else "$@" </dev/null; fi; }
# A probe fed from a pipe cannot borrow run_bounded's </dev/null.
run_piped() { local s; s=$(budget_slice); [ "$s" -ge "$BUDGET_MIN_PROBE" ] || return 124
    if command -v timeout >/dev/null 2>&1; then timeout "$s" "$@"; else "$@"; fi; }
budget_init
# <<< doctor-budget
detail() { local v; for v in "$@"; do printf '  - %s\n' "$v"; done; }
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The reading of a disposition, $DISPOSITION_JQ. Unsourceable, a retired epic
# cannot be told from one closed without its ruling, so the check warns.
# shellcheck source=../../assets/scripts/bd-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/bd-lib.sh" || {
    echo "cannot determine whether closed epics were ruled (I15)"
    detail "assets/scripts/bd-lib.sh could not be sourced from this pack, so a retired epic cannot be told from one closed without its ruling; nothing was scanned"
    exit 1
}

# rig-map.sh prints the map when the listing reads and only its reason when it
# does not, so one capture holds whichever came back.
RIG_MAP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/assets/scripts/rig-map.sh"

# `gc rig list` names the stores this check scans, and it can fail transiently:
# a momentary Dolt or lock blip returns a non-zero rc a later call clears. This
# check files an all-rigs BLOCKING finding when it cannot enumerate, so a single
# blip must not stand in for "stores unscannable" — retry a non-zero rc a bounded
# number of times, each attempt drawn from the same doctor budget. An rc of 0 is
# never retried: rc=0 with no rigs is a genuinely empty city.
RIGS_MAX_ATTEMPTS=3
rigs_attempt=0
while : ; do
    rigs_attempt=$((rigs_attempt + 1))
    rigs_raw=$(run_bounded "$RIG_MAP" 2>&1); rigs_rc=$?
    [ "$rigs_rc" -eq 0 ] && break
    [ "$rigs_attempt" -ge "$RIGS_MAX_ATTEMPTS" ] && break
    budget_spent && break
    sleep 1
done
scopes=$(printf '%s' "$rigs_raw" | jq -r '.rigs[]? | select((.path // "") != "")
    | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path, ((.suspended // false) | tostring)]
    | join("\u001f")' 2>/dev/null)
if [ "$rigs_rc" -ne 0 ] || [ -z "$scopes" ]; then
    echo "cannot determine whether closed epics were ruled (I15)"
    detail "\`gc rig list --json\` failed (rc=$rigs_rc) or listed no rig paths after $rigs_attempt attempt(s); there is no set of bead stores to scan."
    [ "$rigs_rc" -eq 0 ] || [ -z "$rigs_raw" ] || detail "$rigs_raw"
    exit 1
fi

# bash backs a `<<<` here-string longer than a pipe buffer with a temp file in
# $TMPDIR. Under disk pressure that file cannot be created, the redirection fails
# without stopping this check (it is set -u, not set -e), and the loop it feeds
# runs zero times: a non-empty set read as empty, which falls through to the OK
# line. Each enumeration below is staged into a file under this checked, templated
# temp dir and read with a plain `< "$file"`, which keeps the loop in the current
# shell so the finding arrays survive it. A staging failure is loud, never a
# forged all-clear. The dir and its files die with this process.
ENUM_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gctk-check-epic-closed-implies-ruled.XXXXXX" 2>/dev/null) || {
    echo "cannot determine whether closed epics were ruled (I15)"
    detail "could not create a temp directory to stage the store enumerations (mktemp -d failed — e.g. /tmp under disk pressure); nothing was scanned, so this run is not an all-clear"
    exit 1
}
trap 'rm -rf "$ENUM_TMP" 2>/dev/null' EXIT
if ! printf '%s\n' "$scopes" > "$ENUM_TMP/scopes"; then
    echo "cannot determine whether closed epics were ruled (I15)"
    detail "could not stage the store enumeration (temp-file write failed — e.g. /tmp under disk pressure); nothing was scanned, so this run is not an all-clear"
    exit 1
fi
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    label="${rig_name:-<city>}"
    if [ "$suspended" = "true" ]; then
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi
    # Every epic in the store, open ones too, because a closed Delivery's parent
    # epic may still be open, and only closed ones are judged.
    raw=$(run_bounded gc bd list --db "$rig_path/.beads" --type=epic --all \
        --json --limit 0 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
        # `--limit 0` lists every epic, and an empty store returns `[]`, not
        # empty output — so empty here is an unreadable probe, not "no epics".
        warnings+=("$label: could not list epics in $rig_path/.beads (rc=$rc) — this store was NOT checked")
        continue
    fi
    # A closed epic with no hypothesis is exempt only as a Delivery, one whose
    # parent-child edge reaches an epic. A list row carries the edge but not the
    # far bead's type, so the edge is read against this store's own epics, and a
    # parent in another rig's store reads as no epic parent, as the finalize gate
    # reads it. One with no epic parent is an incomplete Epic, fixed by recording
    # its hypothesis and the ruling (docs/epics.md).
    # bd returns an {"error":...} object when a query does not resolve
    # (bead-context.sh). Iterating it with `.[]?` would yield zero rows at exit 0
    # and report the store OK; `error` on a non-array aborts jq non-zero, caught
    # below as "NOT checked" — an all-clear is only a clean array.
    rows=$(printf '%s' "$raw" | scrub | jq -r "$DISPOSITION_JQ"'
        (if type != "array" then error("not an array") else . end)
        | (reduce .[] as $e ({}; .[($e.id // "") | tostring] = true)) as $epic
        | .[]
        | select(((.status // "") | tostring) == "closed")
        | (.metadata // {}) as $m
        | ((.id // "?") | tostring | gsub("[[:cntrl:]]"; " ")) as $id
        | ((($m.epic_ruling // "") | tostring)) as $ruling
        | ((($m.epic_hypothesis // "") | tostring)) as $hyp
        | disposed_to as $disposed
        | ((($m.epic_ruling_reason // "") | tostring | test("\\S"))) as $reasoned
        | any(.dependencies[]?; edge_type == "parent-child"
                                and ($epic[edge_target] // false)) as $epicparent
        # "ruled" only for the close ruling with its outcome recorded: close is the
        # one terminal ruling docs/epics.md defines, and it carries its outcome.
        # It is read before the hypothesis, so an Epic ruled closed with no
        # hypothesis is ruled. A close with no outcome is "noreason"; continue and
        # shift keep an epic open, so a closed epic carrying either is
        # "nonterminal"; an off-enum value ("pending", a typo) is not a ruling and
        # reads as unruled. The finalize gate applies the same predicate.
        | (if ($ruling == "close" and $reasoned) then "ruled"
           elif $disposed != "" then "exempt-disposed"
           elif ($hyp == "" and $epicparent) then "exempt-delivery"
           elif $hyp == "" then "incomplete"
           elif $ruling == "close" then "noreason"
           elif ($ruling == "continue" or $ruling == "shift") then "nonterminal"
           else "unruled" end) as $verdict
        | [$verdict, $id, ($ruling | gsub("[[:cntrl:]]"; " "))] | join("\u001f")' 2>/dev/null)
    if [ $? -ne 0 ]; then
        warnings+=("$label: epic listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi
    [ -n "$rows" ] || continue
    if ! printf '%s\n' "$rows" > "$ENUM_TMP/rows"; then
        warnings+=("$label: could not stage the closed-epic enumeration (temp-file write failed — e.g. /tmp under disk pressure) — this store was NOT checked")
        continue
    fi
    n_disposed=0; n_delivery=0
    while IFS=$'\037' read -r kind id ruling; do
        [ -n "$kind" ] || continue
        # Recording the ruling on the closed epic clears the finding; no reopen is
        # needed for that. An epic is not a merge anchor, so lifecycle.sh refuses
        # to reopen it, and the reopen offered here is bd's own.
        update="gc bd --db $rig_path/.beads update $id"
        reopen="reopen it (\`gc bd --db $rig_path/.beads reopen $id\`)"
        retired="If it was retired into a successor, record that disposition (\`bead-rehome.sh --origin $id --successor <bead> --kind <kind>\`)."
        remedy="If the close stands, record its ruling and outcome: \`$update --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=\"<outcome>\"\`. If the epic should go on, $reopen and record continue or shift. $retired"
        case "$kind" in
            incomplete)
                errors+=("$label epic $id: CLOSED with no hypothesis (epic_hypothesis) and no epic parent, so it is an incomplete Epic, not a Delivery, and it was not ruled close with its outcome (docs/epics.md). If the close stands, record the hypothesis the operator states or approves, with the close ruling and its outcome: \`$update --set-metadata epic_hypothesis=\"<hypothesis>\" --set-metadata epic_ruling=close --set-metadata epic_ruling_reason=\"<outcome>\"\`. If the epic should go on, $reopen and record its hypothesis with continue or shift. $retired") ;;
            unruled)
                errors+=("$label epic $id: CLOSED carrying a hypothesis but no close ruling (epic_ruling '${ruling:-<none>}') — an epic closes on the close ruling, the one terminal ruling of continue/shift/close, never by its last unit merging (docs/epics.md). $remedy") ;;
            noreason)
                errors+=("$label epic $id: CLOSED on the close ruling but no outcome (epic_ruling_reason) — a close ruling carries its outcome: the hypothesis held, was disproven, stalled, or ran past its cost (docs/epics.md). $remedy") ;;
            nonterminal)
                errors+=("$label epic $id: CLOSED on the non-terminal ruling '$ruling' — continue and shift keep an epic open, and it closes only on the close ruling (docs/epics.md). $remedy") ;;
            exempt-disposed) n_disposed=$((n_disposed + 1)) ;;
            exempt-delivery) n_delivery=$((n_delivery + 1)) ;;
        esac
    done < "$ENUM_TMP/rows"
    if [ "$n_disposed" -gt 0 ]; then
        notes+=("$label: $n_disposed closed epic(s) name a successor (retired into it), so they were not judged")
    fi
    if [ "$n_delivery" -gt 0 ]; then
        notes+=("$label: $n_delivery closed Delivery epic(s), under an epic and with no hypothesis of their own, have no ruling to read: their epic carries it")
    fi
done < "$ENUM_TMP/scopes"

if budget_spent; then
    warnings+=("this run reached its ${BUDGET_TOTAL}s doctor budget before every probe ran — what follows is partial, and an arm skipped for time is not an arm that passed")
fi
if [ "${#errors[@]}" -ne 0 ]; then
    echo "closed-but-unruled epics (I15): ${#errors[@]} epic(s)"
    detail "${errors[@]}"
    detail ${warnings[@]+"${warnings[@]}"}
    detail ${notes[@]+"${notes[@]}"}
    exit 2
fi
if [ "${#warnings[@]}" -ne 0 ]; then
    echo "epic-closed-implies-ruled holds with gaps (I15)"
    detail "${warnings[@]}"
    detail ${notes[@]+"${notes[@]}"}
    exit 1
fi
echo "OK: every closed epic other than a Delivery was ruled closed with its outcome, or carries an explicit disposition"
detail ${notes[@]+"${notes[@]}"}
exit 0
