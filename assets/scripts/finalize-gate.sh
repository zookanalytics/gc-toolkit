#!/usr/bin/env bash
# finalize-gate.sh — the composable "may this bead be finalized?" precondition set.
#
# Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR
# (merge.sh) or closing the bead (bead-rehome.sh). This gate is the single place
# that answers, for one bead, whether every precondition for that act holds. It
# is a SET of independent clauses run in order; the first to refuse stops the set
# and names why. The clauses are no-open-visit, epic-ruling-recorded (a stewarded
# epic closes only on the close ruling, not its last unit merging), and
# no-orphan-gate. A later precondition is one more `clause_* "$1" || return 1`
# line in finalize_gate_check.
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
# One exception, named by the caller: --except-key <escalation-key> is the
# situation key under which that caller files, through escalate.sh, its report of
# a refused finalization of this bead. That report asks for the retry, so holding
# the retry on it would keep the bead from ever finalizing once the obstruction
# it reported cleared. A visit is excepted only when it carries that
# escalation_key, is stamped for this bead (gc.continuation_group), and nobody is
# engaged in it: it is open, with no assignee and no bound session
# (gc.session_name). That is the helm board's engagement test (engagedVisit in
# services/helm/internal/board/derive.go). Engage binds a visit's assignee while
# it is still open, so an open visit with an assignee is already engaged. Every
# visit filed under the key for this bead is excepted alike, twins included. A
# visit a person has engaged holds like any other, and so does every visit under
# another key. Each visit is read once, so a visit engaged after that read does
# not hold an act already under way.
#
# Clause no-orphan-gate: the backstop for a gate whose conversation died without
# a decision. A converse hold can leave a human demand gate (gc.demand_for=<this
# bead>) the work blocks on: its conversation demand on a pre-PR item, or the
# opt-in merge hold on a PR anchor. Ending the sitting is meant to resolve or
# re-ask it, but a path that closes the visit and leaves the gate open strands
# it — open, still blocking, its gc.gate_visit naming a closed visit the sweep
# never re-offers. no-open-visit cannot see it (the visit is closed), so this
# clause refuses finalize while such an orphan stands and names how to clear it.
# It is the consistency net: any path that still orphans a gate is caught here,
# not silent.
#
# FAIL CLOSED. A tracker list that does not read, or does not answer with a JSON
# array, refuses the finalization: an unreadable probe is never an all-clear,
# because the act it guards cannot be taken back.
#
# Usage:
#   finalize-gate.sh check <bead-id> [--except-key <escalation-key>]
#     exit 0 — every clause passed; the bead may be finalized (no output)
#     exit 1 — a clause refuses (an open visit, a stewarded epic not ruled
#              closed, an orphan gate, or a probe that failed closed); the
#              one-line reason is printed to stdout for the caller to log
#     exit 2 — usage error
#
# Sourcing the script (BASH_SOURCE != $0) defines finalize_gate_check without
# running anything, for a caller that would rather call the function than fork.
set -u

PROG="finalize-gate"

# bd-lib.sh supplies the guarded store readers bd_json / bd_list: one place strips
# the `gc bd:` rig-store notice and the C0 bytes a `gc bd --json` read can carry,
# so every probe here inherits that defence instead of each re-deriving it. Resolve
# it beside this file, which works whether finalize-gate is run or sourced.
_fg_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_fg_dir/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

# The rule both probes apply to a tracker row, as a jq definition spliced ahead
# of each probe's program, which binds $s to the bead and $ex to the excepted
# escalation key (empty for none). A visit holds while it is open or
# in_progress, except an open one filed under $ex for $s that nobody is engaged
# in (see the block comment above).
_FGV_HOLDS_JQ='
  def holds:
    ((.status // "open") | tostring) as $st
    | $st == "in_progress"
      or ($st == "open"
          and ($ex == ""
               or ((.metadata.escalation_key // "") | tostring) != $ex
               or ((.metadata["gc.continuation_group"] // "") | tostring) != $s
               or ((.assignee // "") | tostring) != ""
               or ((.metadata["gc.session_name"] // "") | tostring) != ""));'

# clause_no_open_visit <bead-id> [<except-key>] — prints a one-line refusal
# reason and returns 1 when an OPEN visit covers the bead, or when a probe fails
# closed; prints nothing and returns 0 when no open visit covers it. Coverage is
# the shared visit identity: PROBE 1 reads the incoming tracks edge, PROBE 2 the
# gc.continuation_group fallback (see the block comment above). Both probes judge
# a row by the one holds rule above.
clause_no_open_visit() {
    _fgv_bead="$1"
    _fgv_except="${2:-}"

    # PROBE 1 — the subject's incoming tracks edges. bd_json strips the notice and
    # the C0 bytes; empty output is an unreadable read (bd_json cannot signal a
    # non-zero rc through its scrub), and `error` on a non-array aborts jq non-zero
    # — both read as fail-closed, since an all-clear is only a clean array naming
    # no open visit.
    _fgv_raw=$(bd_json dep list "$_fgv_bead" --direction=up -t tracks)
    [ -n "$_fgv_raw" ] || {
        echo "open-visit probe unreadable (incoming tracks edges) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    _fgv_hit=$(printf '%s' "$_fgv_raw" \
        | jq -r --arg s "$_fgv_bead" --arg ex "$_fgv_except" "$_FGV_HOLDS_JQ"'
            if type != "array" then error("not an array")
            else [ .[]?
                     | select((.metadata.task_kind // "") == "visit")
                     | select(holds)
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
    # bd_list reads the whole set (--limit 0) and returns non-zero on an
    # unreadable or non-array answer, so its own guard is the fail-closed path.
    _fgv_stamped=$(bd_list --status open,in_progress \
        --metadata-field "gc.continuation_group=$_fgv_bead") || {
        echo "open-visit probe unreadable ('gc bd list' failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    _fgv_cands=$(printf '%s' "$_fgv_stamped" \
        | jq -r --arg s "$_fgv_bead" --arg ex "$_fgv_except" "$_FGV_HOLDS_JQ"'
            if type != "array" then error("not an array")
            else ( .[]?
                     | select((.metadata.task_kind // "") == "visit")
                     | select((.metadata["gc.continuation_group"] // "") == $s)
                     | select(holds)
                     | .id ) end' 2>/dev/null) || {
        echo "open-visit probe unreadable (stamp filter failed) — refusing finalize on $_fgv_bead (fail-closed)"
        return 1
    }
    for _fgv_v in $_fgv_cands; do
        # The stamp is the fallback only for a visit with no tracks edge; a stamped
        # visit that has one is covered by that edge (PROBE 1's domain). An
        # unreadable edge probe is treated as no edge — holding, fail-closed.
        _fgv_edge=$(bd_json dep list "$_fgv_v" --direction=down -t tracks \
            | jq -r 'if type != "array" then "unreadable" elif length > 0 then "yes" else "no" end' 2>/dev/null)
        if [ "$_fgv_edge" != "yes" ]; then
            echo "held by open visit $_fgv_v — its subject $_fgv_bead owes a conversation before finalize (covered by gc.continuation_group; tracks edge not yet written)"
            return 1
        fi
    done
    return 0
}

# clause_epic_ruling_recorded <bead-id> — holds finalization of a stewarded epic
# (issue_type=epic carrying an epic_hypothesis) until its hypothesis is ruled
# closed. An epic closes on a ruling, never as a side effect of its last unit
# merging (docs/epics.md). The ruling is continue, shift, or close, and only close
# is terminal: continue and shift keep the epic open, so they hold it here as an
# absent ruling does. A close ruling carries its outcome (epic_ruling_reason), and
# one recorded without it holds too. A non-epic bead passes untouched. FAIL
# CLOSED: an unreadable probe refuses.
#
# Neither finalize path wired today reaches an undisposed epic. merge.sh
# finalizes merge anchors, and bead-rehome.sh stamps the epic's disposition before
# it runs the gate, which this clause passes. The clause therefore holds only a
# gate-running close that reaches an undisposed epic. A bare `gc bd close` runs no
# gate, and doctor/check-epic-closed-implies-ruled (I15) reports it after the fact.
clause_epic_ruling_recorded() {
    _fgr_bead="$1"
    # This probe runs for EVERY finalize (every merge.sh and bead-rehome.sh close,
    # epic or not). bd_json carries the strip of the `gc bd:` rig-store notice and
    # the C0 scrub a `gc bd --json` read needs (bead-context.sh); empty output is an
    # unreadable read (bd_json cannot signal a non-zero rc through its scrub), read
    # here as fail-closed — the act this guards cannot be taken back.
    _fgr_raw=$(bd_json show "$_fgr_bead")
    [ -n "$_fgr_raw" ] || {
        echo "epic-ruling probe unreadable ('gc bd show' failed) — refusing finalize on $_fgr_bead (fail-closed)"
        return 1
    }
    # One jq emission reads the five fields the clause needs, unit-separated (\037).
    # A non-array (bd returns an object when nothing resolves) aborts jq non-zero,
    # read as unreadable. The hypothesis and the ruling's reason are emitted as
    # presence flags, not their text: a value may hold a newline that jq -r would
    # decode to a real newline and split the read across lines, dropping the
    # ruling and falsely holding; the disposition and ruling are id/enum values
    # with any newline stripped likewise. A reason of whitespace alone is absent.
    _fgr_fields=$(printf '%s' "$_fgr_raw" | jq -r '
        if type != "array" then error("not an array")
        else [ (.[0].issue_type // .[0].type // ""),
               (.[0].metadata.epic_hypothesis // "" | tostring | length > 0 | tostring),
               (.[0].metadata["gc.superseded_by"] // "" | tostring | gsub("[\\n\\r]"; " ")),
               (.[0].metadata.epic_ruling // "" | tostring | gsub("[\\n\\r]"; " ")),
               (.[0].metadata.epic_ruling_reason // "" | tostring | test("\\S") | tostring) ]
             | join("\u001f") end' 2>/dev/null) || {
        echo "epic-ruling probe unreadable (field read failed) — refusing finalize on $_fgr_bead (fail-closed)"
        return 1
    }
    IFS=$'\037' read -r _fgr_type _fgr_hashyp _fgr_disposed _fgr_ruling _fgr_hasreason <<< "$_fgr_fields"
    [ "$_fgr_type" = "epic" ] || return 0   # not an epic: this clause does not apply
    # The predicate doctor/check-epic-closed-implies-ruled (I15) applies to a
    # closed epic: an epic is held once it carries a hypothesis, unless it is
    # disposed or ruled close with its outcome. An epic that never carried a
    # hypothesis predates the model, and a disposition pointer (bead-rehome's
    # gc.superseded_by) is a recorded terminal reason, so both pass.
    [ "$_fgr_hashyp" = true ] || return 0
    [ -n "$_fgr_disposed" ] && return 0
    # Only the close ruling, with its outcome recorded, releases the epic. A
    # non-terminal ruling and a value outside the enum (a draft like "pending", a
    # typo) both hold, each with its own reason, so an epic never closes "ruled"
    # on a value that does not end it.
    case "$_fgr_ruling" in
        close)
            [ "$_fgr_hasreason" = true ] && return 0
            echo "held: epic $_fgr_bead is ruled close but carries no epic_ruling_reason — a close ruling carries its outcome (the hypothesis held, was disproven, stalled, or ran past its cost) (docs/epics.md)" ;;
        continue|shift)
            echo "held: epic $_fgr_bead carries the non-terminal ruling '$_fgr_ruling' — continue and shift keep an epic open, and it closes only on the close ruling (docs/epics.md)" ;;
        *)
            echo "held: epic $_fgr_bead carries a hypothesis but no valid epic_ruling (found '${_fgr_ruling:-<none>}') — a stewarded epic closes on the close ruling (continue/shift/close, only close is terminal), not by its last unit merging (docs/epics.md)" ;;
    esac
    return 1
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
    # bd_list reads the whole set (--limit 0), strips the notice and the C0 bytes,
    # and returns non-zero on an unreadable or non-array answer, so its own guard
    # is the fail-closed path.
    _fgo_raw=$(bd_list --include-gates --has-metadata-key gc.demand_for \
        --status open,in_progress,blocked) || {
        echo "orphan-gate probe unreadable ('gc bd list' failed) — refusing finalize on $_fgo_bead (fail-closed)"
        return 1
    }
    _fgo_gates=$(printf '%s' "$_fgo_raw" | jq -r --arg s "$_fgo_bead" '
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
        # bd_json strips the notice and the C0 bytes, and reads stdin from
        # /dev/null, so it cannot consume the gate rows driving this loop.
        _fgo_vst=$(bd_json show "$_fgo_gv" \
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

# finalize_gate_check <bead-id> [<except-key>] — run the clause set in order;
# the first clause to refuse prints its reason (on stdout) and stops the set.
finalize_gate_check() {
    [ -n "${1:-}" ] || { echo "$PROG: check requires a bead id" >&2; return 2; }
    # Every clause reads the store as it stands now. A refinery pass memoizes
    # bd_list (GC_RECONCILE_BD_CACHE, bd-lib.sh), and merge.sh re-asserts this gate
    # in the terminal window to catch a visit filed after its first check; a probe
    # served from that cache would answer the re-assert with the first check's rows.
    local GC_RECONCILE_BD_CACHE=""
    clause_no_open_visit "$1" "${2:-}" || return 1
    clause_epic_ruling_recorded "$1" || return 1
    clause_no_orphan_gate "$1" || return 1
    # A further precondition is one more `clause_* "$1" || return 1` here.
    return 0
}

# Executable entry. A sourced load stops above with the functions defined.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        check)
            shift
            _fg_bead="${1:-}"; [ $# -gt 0 ] && shift
            case "$_fg_bead" in -*) echo "$PROG: check requires a bead id before its options" >&2; exit 2 ;; esac
            _fg_except=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --except-key)
                        [ -n "${2:-}" ] || { echo "$PROG: --except-key needs an escalation key" >&2; exit 2; }
                        # escalate.sh's own key charset, so the key can only name a
                        # situation that script could have filed.
                        case "$2" in *[!A-Za-z0-9._-]*) echo "$PROG: --except-key must contain only [A-Za-z0-9._-] (got '$2')" >&2; exit 2 ;; esac
                        _fg_except="$2"; shift 2 ;;
                    *) echo "$PROG: unknown argument '$1'" >&2; exit 2 ;;
                esac
            done
            finalize_gate_check "$_fg_bead" "$_fg_except"; exit $? ;;
        *) echo "usage: $PROG check <bead-id> [--except-key <escalation-key>]" >&2; exit 2 ;;
    esac
fi
