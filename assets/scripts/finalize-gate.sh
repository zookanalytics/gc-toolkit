#!/usr/bin/env bash
# finalize-gate.sh — the composable "may this bead be finalized?" precondition set.
#
# Finalizing a bead is the terminal, hard-to-reverse act on it: merging its PR
# (merge.sh) or closing the bead (bead-rehome.sh). This gate is the single place
# that answers, for one bead, whether every precondition for that act holds. It
# is a SET of independent clauses run in order; the first to refuse stops the set
# and names why. The clauses are no-open-human-gate and epic-ruling-recorded (a
# stewarded epic closes only on the close ruling, not its last unit merging).
# A later precondition is one more `clause_* "$1" || return 1` line in
# finalize_gate_check.
#
# Clause no-open-human-gate: an open human gate that blocks this bead refuses
# the bead's finalization. A bead's human gates are the beads its `blocks` edges
# reach whose issue_type is `gate` and whose await_type is `human`, read by
# bd_human_gates in bd-lib.sh, the one read every reader of them makes. bd
# already refuses an unforced close of a blocked bead, and gctk merge holds on a
# live blocker, so the clause states the gate's hold as an explicit
# precondition: a close path that passes --force skips bd's refusal. A gate
# blocks only the beads whose edges reach it, so the clause holds this bead
# alone and reads nothing of its children. A conversation tracks its bead and
# blocks nothing, so it holds nothing here.
#
# One exception, named by the caller: --except-key <situation-key> is the key
# under which that caller files, through human-gate.sh, its report of a refused
# finalization of this bead. That report asks for the retry, so holding the
# retry on it would keep the bead from ever finalizing once the obstruction it
# reported cleared. A gate is excepted only when its await id is that key and no
# person is assigned it. Every gate under the key is excepted alike, twins
# included. A gate assigned to a person holds like any other, and so does every
# gate under another key. bd still refuses the close while an excepted gate
# blocks the bead, so the caller withdraws those gates before it closes
# (bead-rehome.sh).
#
# One reading, also named by the caller: --as-disposed reads the bead as carrying
# a disposition pointer (gc.superseded_by). bead-rehome.sh stamps that pointer
# before it runs this gate, so its --check, which writes nothing, asks about the
# bead as the close will leave it. Only the epic clause reads a pointer, so this
# releases no human gate, and a read that fails still refuses.
#
# FAIL CLOSED. A gate read that does not answer with a JSON array refuses the
# finalization: an unreadable probe is never an all-clear, because the act it
# guards cannot be taken back.
#
# Usage:
#   finalize-gate.sh check <bead-id> [--except-key <situation-key>] [--as-disposed]
#     exit 0 — every clause passed; the bead may be finalized (no output)
#     exit 1 — a clause refuses (an open human gate, a stewarded epic not ruled
#              closed, or a probe that failed closed); the one-line reason is
#              printed to stdout for the caller to log
#     exit 2 — usage error
#
# Sourcing the script (BASH_SOURCE != $0) defines finalize_gate_check without
# running anything, for a caller that would rather call the function than fork.
set -u

PROG="finalize-gate"

# bd-lib.sh supplies the guarded store readers: bd_human_gates, the one read of a
# bead's human gates, and bd_json. One place strips the `gc bd:` rig-store notice
# and the C0 bytes a `gc bd --json` read can carry, so every probe here inherits
# that defence instead of each re-deriving it. Resolve it beside this file, which
# works whether finalize-gate is run or sourced.
_fg_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_fg_dir/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }

# clause_no_open_human_gate <bead-id> [<except-key>] — prints a one-line refusal
# reason and returns 1 when an open human gate blocks the bead, or when the gate
# read fails closed; prints nothing and returns 0 when none does. Which gates are
# open is bd_open_human_gates' rule. Under <except-key>, a gate whose await id is
# that key and that no person is assigned does not hold (see the block comment
# above).
clause_no_open_human_gate() {
    _fgg_bead="$1"
    _fgg_except="${2:-}"
    _fgg_gates=$(bd_open_human_gates "$_fgg_bead") || {
        echo "open-human-gate probe unreadable ('gc bd dep list $_fgg_bead --type blocks' failed) — refusing finalize on $_fgg_bead (fail-closed)"
        return 1
    }
    _fgg_hit=$(printf '%s' "$_fgg_gates" | jq -r --arg ex "$_fgg_except" '
        [ .[]
          | select($ex == ""
                   or ((.await_id // "") | tostring) != $ex
                   or ((.assignee // "") | tostring) != "")
          | ((.id // "") | tostring) + "\t" + ((.title // "") | tostring | gsub("[[:cntrl:]]"; " ")) ]
        | .[0] // empty' 2>/dev/null) || {
        echo "open-human-gate probe unreadable (gate filter failed) — refusing finalize on $_fgg_bead (fail-closed)"
        return 1
    }
    if [ -n "$_fgg_hit" ]; then
        _fgg_id="${_fgg_hit%%$'\t'*}"
        _fgg_title="${_fgg_hit#*$'\t'}"
        echo "held by open human gate $_fgg_id${_fgg_title:+ (\"$_fgg_title\")} — a person owes an answer before $_fgg_bead is finalized"
        return 1
    fi
    return 0
}

# clause_epic_ruling_recorded <bead-id> [<as-disposed>] — holds finalization of a
# stewarded epic (issue_type=epic carrying an epic_hypothesis) until its hypothesis
# is ruled closed. An epic closes on a ruling, never as a side effect of its last unit
# merging (docs/epics.md). The ruling is continue, shift, or close, and only close
# is terminal: continue and shift keep the epic open, so they hold it here as an
# absent ruling does. A close ruling carries its outcome (epic_ruling_reason), and
# one recorded without it holds too. A non-epic bead passes untouched. FAIL
# CLOSED: an unreadable probe refuses.
#
# Neither finalize path wired today reaches an undisposed epic. merge.sh
# finalizes merge anchors, and bead-rehome.sh stamps the epic's disposition before
# it runs the gate, which this clause passes. Its --check, ahead of that stamp, asks
# with <as-disposed> set. The clause therefore holds only a gate-running close that
# reaches an undisposed epic. A bare `gc bd close` runs no
# gate, and doctor/check-epic-closed-implies-ruled (I15) reports it after the fact.
clause_epic_ruling_recorded() {
    _fgr_bead="$1"
    _fgr_as_disposed="${2:-}"
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
    [ -n "$_fgr_disposed$_fgr_as_disposed" ] && return 0
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

# finalize_gate_check <bead-id> [<except-key>] [<as-disposed>] — run the clause set
# in order; the first clause to refuse prints its reason (on stdout) and stops the
# set.
finalize_gate_check() {
    [ -n "${1:-}" ] || { echo "$PROG: check requires a bead id" >&2; return 2; }
    # Every clause reads the store as it stands now, because merge.sh re-asserts
    # this gate in the terminal window to catch a gate filed after its first
    # check. A refinery pass memoizes bd_list (GC_RECONCILE_BD_CACHE, bd-lib.sh),
    # so the memo is off for every clause's reads.
    local GC_RECONCILE_BD_CACHE=""
    clause_no_open_human_gate "$1" "${2:-}" || return 1
    clause_epic_ruling_recorded "$1" "${3:-}" || return 1
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
            _fg_except=""; _fg_as_disposed=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --except-key)
                        [ -n "${2:-}" ] || { echo "$PROG: --except-key needs a situation key" >&2; exit 2; }
                        # human-gate.sh's own key charset, so the key can only name a
                        # situation that script could have filed.
                        case "$2" in *[!A-Za-z0-9._-]*) echo "$PROG: --except-key must contain only [A-Za-z0-9._-] (got '$2')" >&2; exit 2 ;; esac
                        _fg_except="$2"; shift 2 ;;
                    --as-disposed) _fg_as_disposed=1; shift ;;
                    *) echo "$PROG: unknown argument '$1'" >&2; exit 2 ;;
                esac
            done
            finalize_gate_check "$_fg_bead" "$_fg_except" "$_fg_as_disposed"; exit $? ;;
        *) echo "usage: $PROG check <bead-id> [--except-key <situation-key>] [--as-disposed]" >&2; exit 2 ;;
    esac
fi
