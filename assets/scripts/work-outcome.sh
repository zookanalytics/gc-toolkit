#!/bin/sh
# work-outcome.sh — the one gc.work_outcome stamp a converse visit gets before
# it closes. Sourced, never executed, by every script that closes a visit:
# visit-close.sh (the guarded close behind the sitting's own close,
# converse-close-out.sh, escalate.sh --retract and pr-facts.sh's visit retires),
# gc-helm.sh (dismiss), bead-rehome.sh (a visit origin) and converse-claim.sh
# (the stranded close it finishes). A rule about this key changes here, once.
#
# A visit is a plain task bead, so its close runs the runtime's work-record
# gate, which wants gc.work_outcome, one of shipped | no-op | blocked |
# abandoned. A visit ships no commit of its own: the work a sitting routes lands
# on other beads, each with its own outcome. So no-op is the visit's honest
# value. shipped would trip the gate's gc.work_commit and gc.work_branch checks
# instead.
#
# work_outcome_noop <bead> <bd-command>...
#   Stamps gc.work_outcome=no-op on <bead>, unless the bead already records a
#   work outcome: that value is another writer's word and is left as it is.
#   <bd-command> is how the caller reaches its store, `gc bd` or a wrapper such
#   as bead-rehome.sh's `bd_at <path>`, so the stamp lands in the store the
#   close does.
#
#   The stamp is a write of its own and never rides a caller's precondition
#   stamp, so a store that refuses the key fails this write alone. A store can
#   exit 0 on a --set-metadata that wrote nothing, so the value is read back and
#   the write repaired once. Nothing here gates the close, and the function
#   always returns 0. By default the gate only warns, so a missing value costs
#   the ledger one field, while a visit held open over it strands a sitting the
#   board could otherwise report. Where GC_WORK_RECORD_ENFORCE makes the gate
#   block such a close, each caller already reports a close that did not take.
#   A bead that does not read is not written, because nothing proves its key
#   empty.
#
# POSIX sh: gc-helm.sh and converse-claim.sh run under /bin/sh, so the helpers
# keep their state in _wo-prefixed globals rather than `local`.
#
# `scrub` is a name resolved at call time, so the fenced copy below defines it
# for these helpers. A sourcing script keeps its own `# >>> control-char-scrub`
# block for its own scrubs, and the copies stay byte-identical.
# Test: work-outcome.test.sh.

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# work_outcome_read <bead> <bd-command>... — print the bead's gc.work_outcome,
# empty when it records none. Returns non-zero when the bead did not read: an
# answer that is not an array holding a bead is no proof the key is empty.
work_outcome_read() {
    _wor_bead="${1-}"
    [ -n "$_wor_bead" ] && [ $# -ge 2 ] || return 1
    shift
    "$@" show "$_wor_bead" --json 2>/dev/null | scrub \
        | jq -er 'if type == "array" and ((.[0].id // "") != "")
                  then ((.[0].metadata // {})["gc.work_outcome"] // "") | tostring
                  else error("unread") end' 2>/dev/null
}

work_outcome_noop() {
    _won_bead="${1-}"
    [ -n "$_won_bead" ] && [ $# -ge 2 ] || return 0
    shift
    _won_now=$(work_outcome_read "$_won_bead" "$@") || return 0
    [ -z "$_won_now" ] || return 0
    "$@" update "$_won_bead" --set-metadata gc.work_outcome=no-op >/dev/null 2>&1 || true
    _won_now=$(work_outcome_read "$_won_bead" "$@") || _won_now=""
    [ "$_won_now" = "no-op" ] \
        || "$@" update "$_won_bead" --set-metadata gc.work_outcome=no-op >/dev/null 2>&1 || true
    return 0
}
