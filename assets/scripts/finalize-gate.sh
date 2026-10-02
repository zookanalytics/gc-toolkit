#!/usr/bin/env bash
# finalize-gate.sh — the composable "may this bead be finalized?" precondition set.
#
# Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR
# (merge.sh) or closing the bead (bead-rehome.sh). This gate is the single place
# that answers, for one bead, whether every precondition for that act holds. It
# is a SET of independent clauses run in order; the first to refuse stops the set
# and names why. A later precondition (an epic's goal-met, say) is one more
# `clause_* "$1" || return 1` line in finalize_gate_check.
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
# Clause no-orphan-gate: the backstop for a gate whose conversation died without
# a decision. A converse hold files a human demand gate (gc.demand_for=<this
# bead>) the work blocks on; ending the sitting is meant to resolve or re-ask it,
# but a path that closes the visit and leaves the gate open strands it — open,
# still blocking, its gc.gate_visit naming a closed visit the sweep never
# re-offers. no-open-visit cannot see it (the visit is closed), so this clause
# refuses finalize while such an orphan stands and names how to clear it. It is
# the consistency net: any path that still orphans a gate is caught here, not
# silent.
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

# clause_no_orphan_gate <bead-id> — prints a one-line refusal reason and returns 1
# when the bead carries an ORPHAN gate: an open, unassigned human gate naming this
# bead as the work it holds (gc.demand_for), whose gc.gate_visit points at a visit
# that is no longer open. That is the shape a dismiss-without-a-decision leaves —
# the gate stays open and still blocks its bead, but gate-visit-sweep is idempotent
# on gc.gate_visit and never re-offers a stamped gate, so no conversation is left to
# re-ask the decision. clause_no_open_visit catches the live-visit case; this clause
# catches the dead-visit one it cannot see. A gate whose gc.gate_visit is unset (the
# sweep will offer a visit) or `skip` (deliberate operator suppression) is not an
# orphan. The gate lookup is the gc.demand_for convention signoff and the sweep
# share; --include-gates is load-bearing (a gate is hidden from a plain list).
clause_no_orphan_gate() {
    _fgo_bead="$1"
    _fgo_raw=$(gc bd list --include-gates --has-metadata-key gc.demand_for \
        --status open,in_progress,blocked --limit 0 --json 2>/dev/null) || {
        echo "orphan-gate probe unreadable ('gc bd list' failed) — refusing finalize on $_fgo_bead (fail-closed)"
        return 1
    }
    _fgo_gates=$(printf '%s' "$_fgo_raw" | scrub | jq -r --arg s "$_fgo_bead" '
        if type != "array" then error("not an array")
        else ( .[]?
                 | select((.metadata["gc.demand_for"] // "") == $s)
                 | select(((.assignee // "") | tostring) == "")
                 | [ .id, ((.metadata["gc.gate_visit"] // "") | tostring) ] | @tsv ) end' 2>/dev/null) || {
        echo "orphan-gate probe unreadable (gate filter failed) — refusing finalize on $_fgo_bead (fail-closed)"
        return 1
    }
    [ -n "$_fgo_gates" ] || return 0
    _fgo_tab=$(printf '\t')
    _fgo_hit=""
    while IFS="$_fgo_tab" read -r _fgo_g _fgo_gv; do
        [ -n "$_fgo_g" ] || continue
        # Unset -> the sweep will offer a visit; `skip`/`filed` -> handled or
        # unresolvable, not a dead-visit orphan. Everything else is a visit id:
        # read it back, and an id that is not open (closed, missing, unreadable)
        # is the orphan — a visit no longer there to carry the decision.
        case "$_fgo_gv" in ""|skip|filed) continue ;; esac
        _fgo_vst=$(gc bd show "$_fgo_gv" --json 2>/dev/null | scrub \
            | jq -r 'if type == "array" then (.[0].status // "missing") else "unreadable" end' 2>/dev/null)
        case "$_fgo_vst" in open|in_progress) continue ;; esac
        _fgo_hit="$_fgo_g"
        break
    done <<FGO_GATES
$_fgo_gates
FGO_GATES
    if [ -n "$_fgo_hit" ]; then
        echo "orphan gate $_fgo_hit on $_fgo_bead — its gc.gate_visit names a visit no longer open, so the human decision it holds is stranded with no conversation to re-ask. Re-ask it (gc bd update $_fgo_hit --unset-metadata gc.gate_visit) or resolve it (gc bd gate resolve $_fgo_hit) before finalize"
        return 1
    fi
    return 0
}

# finalize_gate_check <bead-id> — run the clause set in order; the first clause to
# refuse prints its reason (on stdout) and stops the set.
finalize_gate_check() {
    [ -n "${1:-}" ] || { echo "$PROG: check requires a bead id" >&2; return 2; }
    clause_no_open_visit "$1" || return 1
    clause_no_orphan_gate "$1" || return 1
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
