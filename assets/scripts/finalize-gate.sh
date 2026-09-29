#!/usr/bin/env bash
# finalize-gate.sh — the composable "may this bead be finalized?" precondition set.
#
# Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR
# (merge.sh) or closing the bead (bead-rehome.sh). This gate is the single place
# that answers, for one bead, whether every precondition for that act holds. It
# is a SET of independent clauses run in order; the first to refuse stops the set
# and names why. Today the set is one clause; a later precondition (an epic's
# goal-met, say) is one more `clause_* "$1" || return 1` line in
# finalize_gate_check.
#
# Clause no-open-visit: an OPEN visit whose SUBJECT is this bead refuses the
# bead's finalization. A visit is a subject-scoped conversation a person owes an
# answer to (formulas/mol-visit.toml). A visit's coverage is its outgoing
# `tracks` edge to the subject, so the trackers are read here by the subject's
# INCOMING tracks edges: bd's own `-t tracks --direction=up` returns exactly the
# beads whose tracks edge points at this bead, which is the coverage relation
# visit-identity.sh reads from the other end. Among those, an OPEN task_kind=visit
# holds finalization. A `tracks` edge is non-blocking, so the gate holds only THIS
# bead's finalization and touches neither the bead's readiness nor its children
# (docs/finalize-gate.md).
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
# when an OPEN visit tracks the bead, or when the probe fails closed; prints
# nothing and returns 0 when no open visit tracks it.
#
# The trackers are read by the bead's incoming `tracks` edges, not by scanning
# every open bead: the reverse edge names exactly the visits (and tracking
# convoys) pointing here, so the probe is local to this one bead. Among the
# returned rows, an OPEN task_kind=visit is a held finalization.
clause_no_open_visit() {
    _fgv_bead="$1"
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
    return 0
}

# finalize_gate_check <bead-id> — run the clause set in order; the first clause to
# refuse prints its reason (on stdout) and stops the set.
finalize_gate_check() {
    [ -n "${1:-}" ] || { echo "$PROG: check requires a bead id" >&2; return 2; }
    clause_no_open_visit "$1" || return 1
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
