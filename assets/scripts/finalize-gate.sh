#!/usr/bin/env bash
# finalize-gate.sh — the composable "may this bead be finalized?" precondition set.
#
# Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR
# (merge.sh) or closing the bead (bead-rehome.sh). This gate is the single place
# that answers, for one bead, whether every precondition for that act holds. It
# is a SET of independent clauses run in order; the first to refuse stops the set
# and names why. The set is two clauses — no-open-visit, and epic-ruling-recorded
# (an epic closes by a recorded hypothesis ruling, not its last unit merging) —
# and a later precondition is one more `clause_* "$1" || return 1` line in
# finalize_gate_check.
#
# Clause no-open-visit: an OPEN visit whose SUBJECT is this bead refuses the
# bead's finalization. A visit is a subject-scoped conversation a person owes an
# answer to (formulas/mol-visit.toml). Its coverage of a subject is the shared
# visit identity (assets/scripts/visit-identity.sh): the visit's outgoing `tracks`
# edge, or — the fallback for a visit whose edge has not landed — its
# `gc.continuation_group` stamp. This clause reads both from the subject's end, so
# it agrees with the board, converse, and the sweeps on which visits stand open,
# and each read stays local to this one bead rather than scanning every open bead:
#   - the subject's INCOMING tracks edges (`-t tracks --direction=up`) name the
#     visits whose edge points here;
#   - the visits STAMPED with this subject (`--metadata-field
#     gc.continuation_group=<bead>`) name the ones covering it by the fallback.
#     escalate.sh leaves that state reachable: it stamps the visit at creation,
#     then adds the tracks edge in a separate write it does not read back, so a
#     stamped-but-not-yet-edged visit is open and owed here while its edge is
#     absent. A stamped visit that already carries a tracks edge is covered by the
#     edge, not the fallback, so it is not counted a second time.
# Among either, an OPEN task_kind=visit holds finalization. A `tracks` edge is
# non-blocking, so the gate holds only THIS bead's finalization and touches
# neither the bead's readiness nor its children (docs/finalize-gate.md).
#
# FAIL CLOSED. A tracker list that does not read, or does not answer with a JSON
# array, refuses the finalization: an unreadable probe is never an all-clear,
# because the act it guards cannot be taken back.
#
# Usage:
#   finalize-gate.sh check <bead-id>
#     exit 0 — every clause passed; the bead may be finalized (no output)
#     exit 1 — a clause refuses (an open visit, or a probe that failed closed);
#              the one-line reason is printed to stdout for the caller to log
#     exit 2 — usage error
#
# Sourcing the script (BASH_SOURCE != $0) defines finalize_gate_check without
# running anything, for a caller that would rather call the function than fork.
set -u

PROG="finalize-gate"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# clause_no_open_visit <bead-id> — prints a one-line refusal reason and returns 1
# when an OPEN visit covers the bead, or when a probe fails closed; prints nothing
# and returns 0 when no open visit covers it. Coverage is the shared visit
# identity: PROBE 1 reads the incoming tracks edge, PROBE 2 the
# gc.continuation_group fallback (see the block comment above).
clause_no_open_visit() {
    _fgv_bead="$1"

    # PROBE 1 — the subject's incoming tracks edges.
    _fgv_raw=$(gc bd dep list "$_fgv_bead" --direction=up -t tracks --json 2>/dev/null) || {
        echo "open-visit probe unreadable ('gc bd dep list' failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    # `error` on a non-array aborts jq non-zero, read below as unreadable — an
    # all-clear is only a clean array that named no open visit.
    _fgv_hit=$(printf '%s' "$_fgv_raw" | scrub \
        | jq -r '
            if type != "array" then error("not an array")
            else [ .[]?
                     | select((.metadata.task_kind // "") == "visit")
                     | select(((.status // "open") | tostring) as $st
                              | ($st == "open" or $st == "in_progress"))
                     | .id ] | .[0] // "" end' 2>/dev/null) || {
        echo "open-visit probe unreadable (tracker filter failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    if [ -n "$_fgv_hit" ]; then
        echo "held by open visit $_fgv_hit — its subject $_fgv_bead owes a conversation before finalize"
        return 1
    fi

    # PROBE 2 — the gc.continuation_group fallback: open visits stamped with this
    # subject whose tracks edge has not landed. A truncated page could hide one, so
    # the whole set is read (--limit 0) and the stamp re-checked in jq rather than
    # trusted from the server-side filter.
    _fgv_stamped=$(gc bd list --status open,in_progress \
        --metadata-field "gc.continuation_group=$_fgv_bead" --limit 0 --json 2>/dev/null) || {
        echo "open-visit probe unreadable ('gc bd list' failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    _fgv_cands=$(printf '%s' "$_fgv_stamped" | scrub \
        | jq -r --arg s "$_fgv_bead" '
            if type != "array" then error("not an array")
            else ( .[]?
                     | select((.metadata.task_kind // "") == "visit")
                     | select((.metadata["gc.continuation_group"] // "") == $s)
                     | select(((.status // "open") | tostring) as $st
                              | ($st == "open" or $st == "in_progress"))
                     | .id ) end' 2>/dev/null) || {
        echo "open-visit probe unreadable (stamp filter failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    for _fgv_v in $_fgv_cands; do
        # The stamp is the fallback only for a visit with no tracks edge; a stamped
        # visit that has one is covered by that edge (PROBE 1's domain). An
        # unreadable edge probe is treated as no edge — holding, fail-closed.
        _fgv_edge=$(gc bd dep list "$_fgv_v" --direction=down -t tracks --json 2>/dev/null \
            | scrub \
            | jq -r 'if type != "array" then "unreadable" elif length > 0 then "yes" else "no" end' 2>/dev/null)
        if [ "$_fgv_edge" != "yes" ]; then
            echo "held by open visit $_fgv_v — its subject $_fgv_bead owes a conversation before finalize (covered by gc.continuation_group; tracks edge not yet written)"
            return 1
        fi
    done
    return 0
}

# clause_epic_ruling_recorded <bead-id> — holds finalization of an
# issue_type=epic bead that carries no epic_ruling. An epic closes by a recorded
# ruling on its hypothesis — persevere, pivot, or close — after a validation
# step, never as a side effect of its last unit merging (docs/epics.md). This
# refuses the close paths that run the gate (bead-rehome.sh's close-with-
# successor, and merge.sh were an epic ever an anchor) until that ruling is
# recorded; epic-steward.sh files the visit that asks for it, and
# doctor/check-epic-closed-implies-ruled is the after-the-fact backstop for a
# bare `gc bd close` that never reaches this gate. A non-epic bead passes
# untouched. FAIL CLOSED: an unreadable probe refuses.
clause_epic_ruling_recorded() {
    _fgr_bead="$1"
    # This probe runs for EVERY finalize (every merge.sh and bead-rehome.sh close,
    # epic or not), so it must survive the two contaminants a `gc bd --json` read
    # can carry (bead-context.sh): a leading `gc bd:` rig-store notice line on
    # stdout, and raw C0 bytes. Strip the notice with `grep -a` (text mode, so a
    # NUL in the bead's notes cannot flip grep to binary and drop the payload)
    # BEFORE scrub removes the C0 bytes below. Without the strip, one notice line
    # would error jq and fail every finalize in the rig closed.
    _fgr_raw=$(gc bd show "$_fgr_bead" --json 2>/dev/null | grep -a -vE '^gc bd:') || {
        echo "epic-ruling probe unreadable ('gc bd show' failed) — refusing finalize on $_fgr_bead (fail-closed)"
        return 1
    }
    # A non-array (bd returns an object when nothing resolves) is unreadable, not
    # an all-clear — the act this guards cannot be taken back.
    _fgr_type=$(printf '%s' "$_fgr_raw" | scrub \
        | jq -r 'if type != "array" then error("not an array")
                 else (.[0].issue_type // .[0].type // "") end' 2>/dev/null) || {
        echo "epic-ruling probe unreadable (type filter failed) — refusing finalize on $_fgr_bead (fail-closed)"
        return 1
    }
    [ "$_fgr_type" = "epic" ] || return 0   # not an epic: this clause does not apply
    # The same rule doctor/check-epic-closed-implies-ruled (I14) applies: an epic
    # is held only once it has entered stewardship (carries a hypothesis) and is
    # neither ruled nor disposed. An epic that never carried a hypothesis predates
    # the model, and a disposition pointer (bead-rehome's gc.superseded_by) is a
    # recorded terminal reason — both pass.
    _fgr_hyp=$(printf '%s' "$_fgr_raw" | scrub \
        | jq -r '(.[0].metadata.epic_hypothesis // "") | tostring' 2>/dev/null)
    [ -n "$_fgr_hyp" ] || return 0
    _fgr_disposed=$(printf '%s' "$_fgr_raw" | scrub \
        | jq -r '(.[0].metadata["gc.superseded_by"] // "") | tostring' 2>/dev/null)
    [ -n "$_fgr_disposed" ] && return 0
    # The ruling must be one docs/epics.md defines (persevere|pivot|close). A
    # present-but-off-enum value — a draft like "pending", a typo — is not a
    # ruling, so the gate holds: otherwise an epic could close "ruled" on a value
    # that is not a ruling, and the I14 doctor backstop would report OK. The same
    # enum the steward's retract arm and doctor/check-epic-closed-implies-ruled use.
    _fgr_ruling=$(printf '%s' "$_fgr_raw" | scrub \
        | jq -r '(.[0].metadata.epic_ruling // "") | tostring' 2>/dev/null)
    case "$_fgr_ruling" in persevere|pivot|close) return 0 ;; esac
    echo "held: epic $_fgr_bead carries a hypothesis but no valid epic_ruling (found '${_fgr_ruling:-<none>}') — a stewarded epic closes by a recorded hypothesis ruling (persevere/pivot/close), not by its last unit merging (docs/epics.md)"
    return 1
}

# finalize_gate_check <bead-id> — run the clause set in order; the first clause to
# refuse prints its reason (on stdout) and stops the set.
finalize_gate_check() {
    [ -n "${1:-}" ] || { echo "$PROG: check requires a bead id" >&2; return 2; }
    clause_no_open_visit "$1" || return 1
    clause_epic_ruling_recorded "$1" || return 1
    # A further precondition is one more `clause_* "$1" || return 1` here.
    return 0
}

# Executable entry. A sourced load stops above with the functions defined.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        check) shift; finalize_gate_check "${1:-}"; exit $? ;;
        *) echo "usage: $PROG check <bead-id>" >&2; exit 2 ;;
    esac
fi
