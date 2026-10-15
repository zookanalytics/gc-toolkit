#!/usr/bin/env bash
# queue-priority.sh — the priority a bead competes at in a pool's queue is
# computed from what it follows (assets/scripts/priority-lib.sh, docs/steering.md),
# and the bd priority field is where a claim reads it and a pour copies it once.
# This script writes that field:
#   settle <bead> [--print] [--db <path>]
#       compute the bead's priority and write it to the bead and to every live
#       workflow poured for it (the input convoy, the root and each open step),
#       then read it back. --print computes the same priority and writes
#       nothing, for a writer that puts it in the same `bd update` as a route.
#   move <bead> (<P0-P4> | --shift <±n>) [--dry-run] [--db <path>]
#       the writer `gc-helm.sh priority` runs: set the bead's own input, then
#       write every bead that follows it, directly or through others (members,
#       the PR-finishing work of each anchor among them, and the live workflow
#       of each), and read it all back.
#   reconcile [--dry-run] [--pool <target>] [--db <path>]
#       one pass of orders/queue-priority.toml: read the beads `bd ready` offers
#       the rig's polecat pool, ephemeral ones included as the pool's claim
#       reads them, and settle each one queued at a priority other than its
#       own, for the raw writes no writer sees, such as a hand
#       `bd update --priority` on an epic or a hand re-parent. The pool is
#       --pool, else the one agent the roster (`gc agent list`) places in the
#       rig under the name polecat.
#
# A claimed bead (in_progress or hooked) keeps the priority it was claimed at: a
# claim already made stands. Two writes reach one anyway. A live workflow root
# is rewritten, because a pour promotes its own root to in_progress with no
# claim behind it, and later fan-out takes the root's priority. A move writes
# the moved bead's own input whether or not the bead is claimed, because
# everything that follows the bead is computed from it: a P-value is the bead's
# priority field, and a shift is its priority_shift. A closed or pinned bead is
# never written.
#
# Every listing asks for every class of bead bd hides by default (qp_list),
# because a bead of any class can be followed, so the three writers read the
# same beads and compute the same priority for each.
#
# One lock per store serializes the three writers, so neither a pass nor a
# settle that read an old priority can write it back over a move. It is a flock
# on queue-priority.lock in the store's own .beads directory, the one path every
# caller names the same way whatever its environment. A move and a settle wait
# for it (QUEUE_PRIORITY_LOCK_WAIT_SECS); a pass that finds it held skips its
# tick. Only this process holds the descriptor: every gc child runs with fd 9
# closed, so a process a gc call starts cannot outlive the writer holding it.
# The holder records itself in queue-priority.holder and clears the record when
# it exits, while it still holds the lock. A pass reports the lock wedged only
# when the writer the record names is still running past the stall bound
# (QUEUE_PRIORITY_LOCK_STALL_SECS). A record whose writer has exited names no
# holder: the lock is held by a writer that has not recorded itself yet, or the
# record was left by one that was killed, so the pass skips its tick.
#
# Callers: gc-helm.sh priority (move), orders/queue-priority.toml (reconcile),
# and the writers that route, sling or release a bead (settle).
# Exit codes: 0 ok; 1 a read, a write, a read-back or the lock failed; 2 usage,
# a move refused before anything was written, or a pass that finds no one
# polecat pool to read.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="queue-priority"
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=priority-lib.sh
. "$SCRIPTS_DIR/priority-lib.sh" || { echo "$PROG: cannot source priority-lib.sh beside this script" >&2; exit 1; }

# How long a move or a settle waits for the lock, and how long a holder may hold
# it before a pass reports it wedged. The stall bound sits above the order's
# timeout, so a pass still running never reads as a wedged one.
LOCK_WAIT_SECS="${QUEUE_PRIORITY_LOCK_WAIT_SECS:-300}"
case "$LOCK_WAIT_SECS" in ''|*[!0-9]*) LOCK_WAIT_SECS=300 ;; esac
LOCK_STALL_SECS="${QUEUE_PRIORITY_LOCK_STALL_SECS:-900}"
case "$LOCK_STALL_SECS" in ''|*[!0-9]*) LOCK_STALL_SECS=900 ;; esac
# The pass budget, in seconds from the start of the pass (0 = unpaced). A pass
# starts settling a bead only while one settle's allowance is left in it, and
# leaves the rest at their old priority for the next pass, so the order's
# timeout never kills it between a write and its read-back.
# queue-priority.test.sh holds the budget below the order's timeout and the
# stall bound above it.
PASS_BUDGET_SECS="${QUEUE_PRIORITY_PASS_BUDGET_SECS:-240}"
case "$PASS_BUDGET_SECS" in ''|*[!0-9]*) PASS_BUDGET_SECS=240 ;; esac
PASS_BUDGET_SECS=$((10#$PASS_BUDGET_SECS))
SETTLE_ALLOWANCE_SECS="${QUEUE_PRIORITY_SETTLE_ALLOWANCE_SECS:-60}"
case "$SETTLE_ALLOWANCE_SECS" in ''|*[!0-9]*) SETTLE_ALLOWANCE_SECS=60 ;; esac
SETTLE_ALLOWANCE_SECS=$((10#$SETTLE_ALLOWANCE_SECS))
# Ids per `bd update`, so one write never carries an argument list past what
# the store answers in one call.
WRITE_BATCH=40

BD_DB=""
DRY_RUN=0

TMPFILES=()
# The exit releases the lock, and the holder record is cleared before it, while
# this process still holds the lock, so no later reader takes this writer's
# record for the next holder's.
LOCK_HELD=0
cleanup() {
    [ "$LOCK_HELD" = 1 ] && { : > "$BD_DB/queue-priority.holder"; } 2>/dev/null
    [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"
    return 0
}
trap cleanup EXIT
# Answers in $REPLY, so the allocation lands in this shell's registry rather than
# a command substitution's copy of it.
mktemp_tracked() { REPLY="$(mktemp "${TMPDIR:-/tmp}/gctk-queue-priority.XXXXXX")" || return 1; TMPFILES+=("$REPLY"); }

bd_() { gc bd --db "$BD_DB" "$@" 9>&-; }
now_epoch() { date -u +%s; }

usage() {
    cat <<'EOF'
Usage:
  queue-priority.sh settle <bead> [--print] [--db <path>]
  queue-priority.sh move <bead> (<P0-P4> | --shift <±n>) [--dry-run] [--db <path>]
  queue-priority.sh reconcile [--dry-run] [--pool <target>] [--db <path>]

Verbs:
  settle     Compute the bead's priority, write it to the bead and to every live
             workflow poured for it, and read it back. Exits 1 when the priority
             cannot be computed or does not read back. A bead that follows
             nothing keeps its own priority, and its workflows take it. --print
             computes the same priority, prints the number and writes nothing.
  move       The writer gc-helm.sh priority runs. A P-value sets a bead that
             follows nothing; --shift sets the shift of a bead that follows a
             parent or an anchor. It then writes every bead that follows the
             bead, directly or through others, held beads included, and reads
             them back. It refuses the form that does not fit the bead, and a
             workflow's convoy, root or step. --dry-run prints what it would
             write.
  reconcile  One pass of orders/queue-priority.toml: settle every bead the
             polecat pool's ready queue offers at a priority other than its own.
             It reads the queue and what each queued bead follows, never the
             whole store. --dry-run takes no lock and writes nothing.

The bead's store is --db, else the rig its id prefix names (gc rig list), else
$GC_RIG_ROOT/.beads. reconcile reads $GC_RIG_ROOT/.beads unless --db names
another, and the queue of --pool, else of the one agent gc agent list places in
$GC_RIG under the name polecat. That agent's name carries the binding the rig
imports the pack under, so a pass that finds no such agent, or several, reads
nothing and exits 2.
EOF
}

# resolve_db <bead-id> — pin BD_DB to the store that holds the bead, unless
# --db already did.
resolve_db() {
    [ -n "$BD_DB" ] && return 0
    local prefix="${1%%-*}" path=""
    path="$(gc rig list --json 2>/dev/null 9>&- | scrub | jq -r --arg p "$prefix" '.rigs[]? | objects | select((.prefix // "") == $p) | .path // empty' 2>/dev/null | head -n1)"
    if [ -n "$path" ] && [ -d "$path/.beads" ]; then BD_DB="$path/.beads"; return 0; fi
    if [ -n "${GC_RIG_ROOT:-}" ] && [ -d "$GC_RIG_ROOT/.beads" ]; then BD_DB="$GC_RIG_ROOT/.beads"; return 0; fi
    return 1
}

# take_lock <wait|nowait> <verb> — take the store's lock on fd 9 and record this
# process as its holder. Returns 0 holding it, 1 when another holder keeps it
# (past the wait, or at once for nowait), 2 when the writer the holder record
# names is still running past the stall bound, and 3 when no lock can be taken:
# no flock on PATH, or a lock file this process cannot create or open.
# LOCK_NOTE names the holder for 1 and 2 and the cause for 3.
take_lock() {
    local mode="$1" verb="$2" lock="$BD_DB/queue-priority.lock" holder="$BD_DB/queue-priority.holder"
    local held_pid="" held_since="" held_verb="" elapsed=""
    LOCK_NOTE=""
    command -v flock >/dev/null 2>&1 || { LOCK_NOTE="flock not found on PATH"; return 3; }
    ( : >> "$lock" ) 2>/dev/null || { LOCK_NOTE="cannot create $lock"; return 3; }
    exec 9>>"$lock" || { LOCK_NOTE="cannot open $lock"; return 3; }
    local got=0
    if flock -n 9; then
        got=1
    elif [ "$mode" = wait ]; then
        echo "$PROG: waiting up to ${LOCK_WAIT_SECS}s for the priority lock on $BD_DB ($(holder_note))" >&2
        flock -w "$LOCK_WAIT_SECS" 9 && got=1
    fi
    if [ "$got" = 1 ]; then
        printf '%s %s %s\n' "$$" "$(now_epoch)" "$verb" > "$holder" 2>/dev/null || true
        LOCK_HELD=1
        return 0
    fi
    [ -r "$holder" ] && read -r held_pid held_since held_verb < "$holder"
    # A writer records itself only after its flock succeeds, so a record whose
    # writer has exited is not the holder's: the lock was taken by a writer that
    # has not recorded itself yet, or the record was left by one that was killed.
    case "$held_pid" in
        ''|*[!0-9]*) ;;
        *) if ! kill -0 "$held_pid" 2>/dev/null; then
               LOCK_NOTE="a writer that has not recorded itself yet; pid $held_pid, which the record names, has exited"
               return 1
           fi ;;
    esac
    case "$held_since" in ''|*[!0-9]*) ;; *) elapsed=$(( $(now_epoch) - held_since )) ;; esac
    LOCK_NOTE="${held_verb:-a writer}, pid ${held_pid:-unknown}${elapsed:+, ${elapsed}s elapsed}"
    if [ -n "$elapsed" ] && [ "$elapsed" -gt "$LOCK_STALL_SECS" ]; then return 2; fi
    return 1
}
holder_note() {
    local p="" _since="" v=""
    [ -r "$BD_DB/queue-priority.holder" ] && read -r p _since v < "$BD_DB/queue-priority.holder"
    printf 'held by %s, pid %s' "${v:-a writer}" "${p:-unknown}"
}

# The one listing of the store: every read here asks for every class of bead a
# listing hides by default, gates, infrastructure beads, template molecules and
# ephemeral rows, because a bead of any class can be followed. Settle, the move
# and the pass then read the same beads, so each computes the priority the
# others compute.
qp_list() {
    bd_ list "$@" --include-gates --include-infra --include-templates --include-ephemeral --brief --json --limit 0 2>/dev/null
}
# The walk's reader (priority-lib.sh): the named beads at every status.
qp_read() { qp_list --id "$1" --all; }

# A row read as a JSON array, from either shape a listing answers in. The
# parentheses make it one term wherever a program places it, because jq before
# 1.8 does not compile a bare `if ... end` followed by `as`, an index or a field.
ROWS_JQ='(if type == "object" and ((.issues // null) | type) == "array" then .issues elif type == "array" then . else error("not a listing") end)'

# What a reader prints for a computed priority: the bead, its level, and what it
# follows.
# shellcheck disable=SC2016  # jq program, single-quoted on purpose
DERIVATION_JQ='
  def sgn: if . > 0 then "+\(.)" else "\(.)" end;
  if has("error") then "unreadable: \(.error)"
  elif .kind == "none" then "P\(.priority), set directly"
  elif .kind == "workflow" then "P\(.priority), the priority of \(.via)"
  else "P\(.priority): \(.kind) \(.via) P\(.base), shift \(.shift | sgn)" end'

# A bead the writers may rewrite: live and unclaimed, or a workflow root.
# shellcheck disable=SC2016  # jq program, single-quoted on purpose
WRITABLE_JQ='
  def writable:
    ((.status // "") | tostring) as $s
    | if $s == "closed" or $s == "pinned" then false
      elif $s == "in_progress" or $s == "hooked" then
        ((((.metadata // {}) | if type == "object" then . else {} end)["gc.kind"] // "") | tostring) == "workflow"
      else true end;'

# A bead found through another belongs to the workflow only when the library
# says it follows that bead as part of a workflow, so a settle writes the beads
# whose priority the function computes from the subject and no others.
# shellcheck disable=SC2016  # jq program, single-quoted on purpose
POURED_JQ='def poured_for($on): prio_live and (prio_follows | .kind == "workflow" and .on == [$on]);'

# workflow_rows <subject-row-json> — every live workflow poured for the
# subject, printed as one JSON array of rows: each input convoy gascity made for
# it, the live root poured over that convoy, and the root's live steps. A
# subject that is itself a convoy, slung as it is, has its roots poured over it
# directly. A subject that is itself a workflow root has its own steps: a root
# whose input convoy is gone, or that a launch poured with none, follows no
# convoy, so it is the bead its steps were poured for. Each bead is one that
# follows the bead it was found through (POURED_JQ), so an input convoy that
# tracks more than one bead, which follows none of them, is no bead's workflow.
# Returns 1 when a read fails, so a settle never reports a workflow it could not
# read as settled.
workflow_rows() {
    local row="$1" subject is_convoy raw ids convoys all c roots root_ids="" r steps
    subject="$(printf '%s' "$row" | jq -r '.id')"
    is_convoy="$(printf '%s' "$row" | jq -r '(.issue_type // "") == "convoy"')"
    printf '%s' "$row" | jq -e '(((.metadata // {}) | if type == "object" then . else {} end)["gc.kind"] // "" | tostring) == "workflow"' >/dev/null 2>&1 \
        && root_ids="$subject"
    # A row of `dep list` carries none of the convoy's own edges, so each convoy
    # is read again to count the beads it tracks.
    raw="$(bd_ dep list "$subject" --direction up -t tracks --json 2>/dev/null)" || return 1
    ids="$(printf '%s' "$raw" | scrub | jq -r "$ROWS_JQ"' | [ .[] | objects | select((.issue_type // "") == "convoy") | .id | tostring ] | unique | join(",")' 2>/dev/null)" || return 1
    convoys='[]'
    if [ -n "$ids" ]; then
        raw="$(qp_read "$ids")" || return 1
        convoys="$(printf '%s' "$raw" | scrub | jq -c --arg on "$subject" "$PRIORITY_JQ$POURED_JQ$ROWS_JQ"' | [ .[] | objects | select(poured_for($on)) ]' 2>/dev/null)" || return 1
        [ -n "$convoys" ] || return 1
    fi
    all="$convoys"
    for c in $(printf '%s' "$convoys" | jq -r '.[].id') $( [ "$is_convoy" = true ] && printf '%s' "$subject" ); do
        raw="$(qp_list --metadata-field "gc.input_convoy_id=$c")" || return 1
        roots="$(printf '%s' "$raw" | scrub | jq -c --arg on "$c" "$PRIORITY_JQ$POURED_JQ$ROWS_JQ"' | [ .[] | objects | select(poured_for($on)) ]' 2>/dev/null)" || return 1
        [ -n "$roots" ] || return 1
        all="$(jq -cn --argjson a "$all" --argjson b "$roots" '$a + $b')" || return 1
        root_ids="$root_ids $(printf '%s' "$roots" | jq -r '.[].id')"
    done
    for r in $root_ids; do
        raw="$(qp_list --metadata-field "gc.root_bead_id=$r")" || return 1
        steps="$(printf '%s' "$raw" | scrub | jq -c --arg on "$r" "$PRIORITY_JQ$POURED_JQ$ROWS_JQ"' | [ .[] | objects | select(poured_for($on)) ]' 2>/dev/null)" || return 1
        [ -n "$steps" ] || return 1
        all="$(jq -cn --argjson a "$all" --argjson b "$steps" '$a + $b')" || return 1
    done
    printf '%s\n' "$all"
}

# write_priorities <plan-file> — the plan is a JSON array of {id, to}; write each
# bead's priority, grouped by level in batches, then read every one back.
# WROTE counts the beads written. Returns 1 when a write fails or a bead does
# not read back at the level written, naming each in MISMATCH.
WROTE=0
MISMATCH=""
write_priorities() {
    local plan="$1" p ids n i id batch rows
    WROTE=0; MISMATCH=""
    n="$(jq 'length' "$plan" 2>/dev/null)" || return 1
    [ "$n" -gt 0 ] || return 0
    for p in 0 1 2 3 4; do
        ids="$(jq -r --argjson p "$p" '[ .[] | select(.to == $p) | .id ] | unique | .[]' "$plan")"
        [ -n "$ids" ] || continue
        batch=()
        i=0
        while IFS= read -r id; do
            batch+=("$id"); i=$((i + 1))
            if [ "$i" -ge "$WRITE_BATCH" ]; then
                bd_ update "${batch[@]}" --priority "$p" >/dev/null 2>&1 || { MISMATCH="the write of P$p to ${batch[*]} failed"; return 1; }
                WROTE=$((WROTE + i)); batch=(); i=0
            fi
        done <<< "$ids"
        if [ "$i" -gt 0 ]; then
            bd_ update "${batch[@]}" --priority "$p" >/dev/null 2>&1 || { MISMATCH="the write of P$p to ${batch[*]} failed"; return 1; }
            WROTE=$((WROTE + i))
        fi
    done
    rows="$(qp_read "$(jq -r '[ .[].id ] | unique | join(",")' "$plan")")" || { MISMATCH="the read-back did not answer"; return 1; }
    MISMATCH="$(printf '%s' "$rows" | scrub | jq -r --slurpfile plan "$plan" "$ROWS_JQ"' as $rows
        | ($rows | map({key: (.id | tostring), value: .priority}) | from_entries) as $got
        | [ $plan[0][] | select(($got[.id] // null) != .to)
            | "\(.id) reads P\($got[.id] // "?"), not P\(.to)" ] | join("; ")' 2>/dev/null)" \
        || { MISMATCH="the read-back did not parse"; return 1; }
    [ -z "$MISMATCH" ]
}

# settle_subject <subject-row-json> <priority> <plan-file> — add to the plan
# the subject itself, when it may be rewritten and reads another level, and
# every bead of its live workflows that reads another level. Returns 1 when a
# workflow could not be read. SKIPPED names a claimed subject left as it is.
SKIPPED=""
settle_subject() {
    local row="$1" p="$2" plan="$3" wf next
    SKIPPED=""
    wf="$(workflow_rows "$row")" || return 1
    next="$(jq -c --argjson self "$row" --argjson p "$p" --argjson wf "$wf" "$WRITABLE_JQ"'
        . + [ ([$self] + $wf)[] | select(writable) | select(.priority != $p) | {id: (.id | tostring), to: $p} ]
        | unique_by(.id)' "$plan")" || return 1
    printf '%s\n' "$next" > "$plan" || return 1
    if ! printf '%s' "$row" | jq -e "$WRITABLE_JQ"'writable' >/dev/null 2>&1; then
        SKIPPED="$(printf '%s' "$row" | jq -r '"\(.id) (\(.status // ""))"')"
    fi
    return 0
}

# --- settle --------------------------------------------------------------------
cmd_settle() {
    local bead="" print=0
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: settle needs a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --print) print=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: settle: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    resolve_db "$bead" || { echo "$PROG: settle: cannot tell which store holds $bead; pass --db <path>" >&2; return 1; }

    if [ "$print" = 0 ]; then
        local lock_rc=0
        take_lock wait settle || lock_rc=$?
        if [ "$lock_rc" != 0 ]; then
            echo "$PROG: settle: could not take the priority lock on $BD_DB ($LOCK_NOTE), so $bead was not settled" >&2
            return 1
        fi
    fi

    local seed graph raw result row p
    mktemp_tracked || return 1; seed="$REPLY"
    mktemp_tracked || return 1; graph="$REPLY"
    raw="$(qp_read "$bead")" || { echo "$PROG: settle: could not read $bead from $BD_DB" >&2; return 1; }
    printf '%s' "$raw" | scrub | jq -c --arg b "$bead" "$ROWS_JQ"' | [ .[] | objects | select(.id == $b) ]' > "$seed" 2>/dev/null \
        || { echo "$PROG: settle: the read of $bead from $BD_DB did not parse" >&2; return 1; }
    jq -e 'length == 1' "$seed" >/dev/null 2>&1 || { echo "$PROG: settle: $bead does not resolve in $BD_DB" >&2; return 1; }
    priority_graph qp_read "$seed" "$graph" || { echo "$PROG: settle: could not read what $bead follows" >&2; return 1; }
    result="$(jq -c --slurpfile g "$graph" "$PRIORITY_JQ"'.[0] | priority_of($g[0])' "$seed" 2>/dev/null)"
    if [ -z "$result" ] || printf '%s' "$result" | jq -e 'has("error")' >/dev/null 2>&1; then
        echo "$PROG: settle: cannot compute the priority of $bead: $(printf '%s' "$result" | jq -r '.error // "the function did not answer"' 2>/dev/null)" >&2
        return 1
    fi
    p="$(printf '%s' "$result" | jq -r '.priority')"
    if [ "$print" = 1 ]; then
        printf '%s\n' "$p"
        return 0
    fi

    local plan
    mktemp_tracked || return 1; plan="$REPLY"
    echo '[]' > "$plan"
    row="$(jq -c '.[0]' "$seed")"
    settle_subject "$row" "$p" "$plan" || { echo "$PROG: settle: could not read the workflows poured for $bead, so it was not settled" >&2; return 1; }
    if ! write_priorities "$plan"; then
        echo "$PROG: settle: $bead did not settle at P$p: $MISMATCH" >&2
        return 1
    fi
    echo "$PROG: settled $bead at $(printf '%s' "$result" | jq -r "$DERIVATION_JQ")${SKIPPED:+; claimed, left as it is: $SKIPPED}; $( [ "$WROTE" -gt 0 ] && printf 'wrote %s bead(s): %s' "$WROTE" "$(jq -r '[ .[].id ] | join(" ")' "$plan")" || printf 'nothing to write')"
}

# --- move ----------------------------------------------------------------------
# The move over one listing of the store's live beads: the moved bead's new
# input applied, the form checked against what it follows, then every bead that
# follows it, found down the followers index, computed again. Prints one object:
# {refusal} when the form does not fit, else {self, writes, claimed, errors}.
# shellcheck disable=SC2016  # jq program, single-quoted on purpose
MOVE_JQ='
  ($rows | map({key: (.id | tostring), value: .}) | from_entries) as $g0
  # A bead the live listing lacks is closed, pinned or in no store: none is
  # followed, so each reads as absent.
  | ([ $rows[] | prio_follows.on[] ] | unique | map(select(. as $x | $g0 | has($x) | not))) as $miss
  | (reduce $miss[] as $m ($g0; .[$m] = null)) as $before
  | $before[$b] as $row
  | ($row | priority_of($before)) as $was
  | ($row | prio_follows) as $f
  | ([ $f.on[] | ($before[.] // null) | select(. != null) | select(prio_live) ] | length > 0) as $follows
  | ($row | priority_subject($before) | .id) as $subject
  | if $follows and $f.kind == "workflow" then
      {refusal: "\($b) is part of the workflow poured for \($subject) and takes its priority, so it takes no priority of its own. Move \($subject) instead."}
    elif $level != null and $follows then
      ($was | if has("error") then {refusal: "\($b) follows \(.via // "a bead") and its priority cannot be computed: \(.error)"}
       else ($level - .base) as $n
         | (if $n > 0 then "+\($n)" else "\($n)" end) as $sh
         | {refusal: "\($b) follows \(.kind) \(.via), at P\(.base), so its priority is that plus its own shift. P\($level) is --shift \($sh): gc-helm.sh priority \($b) --shift \($sh)."} end)
    elif $shift != null and ($follows | not) then
      {refusal: "\($b) follows nothing, so it has no shift. Set its priority directly: gc-helm.sh priority \($b) P<0-4>."}
    else
      ($before | .[$b] = (if $level != null then ($row | .priority = $level)
                          else ($row | .metadata = (((.metadata // {}) | if type == "object" then . else {} end) + {priority_shift: $shift})) end)) as $g
      | priority_followers($g) as $idx
      | def down($front; $seen):
          if ($front | length) == 0 then $seen
          else ([ $front[] | ($idx[.] // [])[] ] | unique | map(select(. as $x | $seen | index($x) | not))) as $next
            | down($next; $seen + $next) end;
        down([$b]; [$b]) as $all
      # Compared against the store as it reads now ($before), computed with the
      # new input applied ($g).
      | [ $all[] | . as $id | ($before[$id] // null) | select(. != null) | {row: ., r: ($g[$id] | priority_of($g))} ] as $res
      | {self: (($res[] | select(.row.id == $b) | .r) // {id: $b, error: "not computed"}),
         was: $was,
         writes: [ $res[] | select(.r | has("error") | not)
                   | select(.row | writable or (.id == $b and $level != null))
                   | select(.row.priority != .r.priority)
                   | {id: (.row.id | tostring), from: .row.priority, to: .r.priority} ],
         claimed: [ $res[] | select(.r | has("error") | not) | select(.row | writable | not)
                    | select(.row.id != $b or $level == null)
                    | select(.row.priority != .r.priority)
                    | {id: (.row.id | tostring), status: .row.status, to: .r.priority} ],
         errors: [ $res[] | select(.r | has("error")) | {id: (.row.id | tostring), error: .r.error} ]}
    end'

cmd_move() {
    local bead="" level="" shift_n="" a npos=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --shift) shift; shift_n="${1:-}"; [ -n "$shift_n" ] || { echo "$PROG: move: --shift needs a signed whole number, such as -1 or +2" >&2; return 2; } ;;
            --shift=*) shift_n="${1#--shift=}" ;;
            --dry-run) DRY_RUN=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            -h|--help) usage; return 0 ;;
            *)
                a="$1"
                case "$a" in -[0-9]*|+[0-9]*) echo "$PROG: move: a shift is passed as --shift $a" >&2; return 2 ;; -*) echo "$PROG: move: unknown flag '$a'" >&2; return 2 ;; esac
                npos=$((npos + 1))
                case "$npos" in
                    1) bead="$a" ;;
                    2) level="$a" ;;
                    *) echo "$PROG: move takes one <bead> and one priority" >&2; return 2 ;;
                esac ;;
        esac
        shift || true
    done
    [ -n "$bead" ] || { echo "$PROG: move needs a bead id" >&2; return 2; }
    if [ -n "$level" ] && [ -n "$shift_n" ]; then
        echo "$PROG: move: a P-value and --shift are the two forms of a move, and a move takes one. A P-value sets a bead that follows nothing; --shift sets a bead that follows a parent or an anchor. Nothing was written." >&2
        return 2
    fi
    if [ -z "$level" ] && [ -z "$shift_n" ]; then
        echo "$PROG: move needs a priority, P0 to P4, or --shift <±n>. Nothing was written." >&2
        return 2
    fi
    local level_json=null shift_json=null
    if [ -n "$level" ]; then
        case "$level" in [Pp][0-4]) level="${level#?}" ;; [0-4]) : ;;
            *) echo "$PROG: move: '$level' is not a priority; give P0 to P4. Nothing was written." >&2; return 2 ;; esac
        level_json="$level"
    else
        case "$shift_n" in [+-][0-9]*|[0-9]*) : ;; *) shift_n="x" ;; esac
        case "${shift_n#[+-]}" in ''|*[!0-9]*)
            echo "$PROG: move: --shift takes a signed whole number of levels, such as -1 (one level sooner) or +2 (two levels later). Nothing was written." >&2; return 2 ;; esac
        shift_json="$(printf '%s' "${shift_n#+}" | sed 's/^-0*\([0-9]\)/-\1/; s/^0*\([0-9]\)/\1/')"
        [ "$shift_json" = "-0" ] && shift_json=0
    fi

    resolve_db "$bead" || { echo "$PROG: move: cannot tell which store holds $bead; pass --db <path>. Nothing was written." >&2; return 1; }
    if [ "$DRY_RUN" != 1 ]; then
        local lock_rc=0
        take_lock wait move || lock_rc=$?
        if [ "$lock_rc" != 0 ]; then
            echo "$PROG: move: could not take the priority lock on $BD_DB ($LOCK_NOTE). Nothing was written." >&2
            return 1
        fi
    fi

    # The live beads of every class, among them every bead that can follow the
    # moved one: gc-helm.sh demand files its gate under the gated bead's parent,
    # so the gate follows that parent like any member.
    local listing raw one status out
    mktemp_tracked || return 1; listing="$REPLY"
    raw="$(qp_list --status=open,in_progress,blocked,deferred,hooked)" \
        || { echo "$PROG: move: could not list the store $BD_DB to find what follows $bead. Nothing was written." >&2; return 1; }
    printf '%s' "$raw" | scrub | jq -c "$ROWS_JQ" > "$listing" 2>/dev/null \
        || { echo "$PROG: move: the listing of $BD_DB did not parse. Nothing was written." >&2; return 1; }
    if ! jq -e --arg b "$bead" 'any(.[]; .id == $b)' "$listing" >/dev/null 2>&1; then
        raw="$(qp_read "$bead")" || { echo "$PROG: move: could not read $bead from $BD_DB. Nothing was written." >&2; return 1; }
        one="$(printf '%s' "$raw" | scrub | jq -c --arg b "$bead" "$ROWS_JQ"' | [ .[] | objects | select(.id == $b) ] | first // empty' 2>/dev/null)"
        if [ -z "$one" ]; then
            echo "$PROG: move: $bead does not resolve in $BD_DB. Nothing was written." >&2
            return 1
        fi
        status="$(printf '%s' "$one" | jq -r '.status // ""')"
        case "$status" in
            closed|pinned)
                echo "$PROG: move: $bead is $status, so nothing that follows it waits in a queue. Nothing was written." >&2
                return 2 ;;
        esac
        # A live bead the listing missed, written after it was read, joins it.
        mktemp_tracked || return 1
        jq -c --argjson one "$one" '. + [$one]' "$listing" > "$REPLY" 2>/dev/null && listing="$REPLY" \
            || { echo "$PROG: move: could not add $bead to the listing of $BD_DB. Nothing was written." >&2; return 1; }
    fi

    out="$(jq -c -n --slurpfile rows "$listing" --arg b "$bead" --argjson level "$level_json" --argjson shift "$shift_json" \
        "$PRIORITY_JQ$WRITABLE_JQ"'$rows[0] as $rows | '"$MOVE_JQ" 2>/dev/null)"
    if [ -z "$out" ]; then
        echo "$PROG: move: could not compute what follows $bead. Nothing was written." >&2
        return 1
    fi
    if printf '%s' "$out" | jq -e 'has("refusal")' >/dev/null 2>&1; then
        echo "$PROG: move: $(printf '%s' "$out" | jq -r '.refusal') Nothing was written." >&2
        return 2
    fi
    if printf '%s' "$out" | jq -e '.self | has("error")' >/dev/null 2>&1; then
        echo "$PROG: move: the priority of $bead cannot be computed: $(printf '%s' "$out" | jq -r '.self.error'). Nothing was written." >&2
        return 1
    fi

    local derivation plan errors claimed n
    derivation="$(printf '%s' "$out" | jq -r ".self | $DERIVATION_JQ")"
    errors="$(printf '%s' "$out" | jq -r '[ .errors[] | "\(.id) (\(.error))" ] | join("; ")')"
    claimed="$(printf '%s' "$out" | jq -r '[ .claimed[] | "\(.id) (\(.status), P\(.to) once released)" ] | join(", ")')"
    mktemp_tracked || return 1; plan="$REPLY"
    printf '%s' "$out" | jq -c '[ .writes[] | {id, to} ]' > "$plan"
    n="$(jq 'length' "$plan")"
    if [ "$DRY_RUN" = 1 ]; then
        echo "priority $bead $derivation (dry run, nothing written)"
        echo "would write $n bead(s)$( [ "$n" -gt 0 ] && printf ': %s' "$(printf '%s' "$out" | jq -r '[ .writes[] | "\(.id) P\(.from)->P\(.to)" ] | join(", ")')")"
        [ -z "$claimed" ] || echo "claimed, left as they are: $claimed"
        [ -z "$errors" ] || echo "unreadable, left as they are: $errors"
        return 0
    fi

    # The bead's own input first: a shift is metadata the function reads, and a
    # P-value is the priority field itself, written below with the rest.
    if [ -n "$shift_n" ]; then
        bd_ update "$bead" --set-metadata "priority_shift=$shift_json" >/dev/null 2>&1 \
            || { echo "$PROG: move: the write of priority_shift=$shift_json to $bead failed. Nothing else was written." >&2; return 1; }
        local got_shift
        got_shift="$(qp_read "$bead" | scrub | jq -r --arg b "$bead" "$ROWS_JQ"' | [ .[] | select(.id == $b) | (.metadata // {}).priority_shift // "" | tostring ] | first // ""' 2>/dev/null)"
        if [ "${got_shift#+}" != "$shift_json" ]; then
            echo "$PROG: move: $bead reads priority_shift '${got_shift}', not $shift_json, after the write. Nothing else was written." >&2
            return 1
        fi
    fi
    if ! write_priorities "$plan"; then
        echo "$PROG: move: $bead moved to $derivation, but the work that follows it did not all settle: $MISMATCH. The queue-priority pass settles what is queued; re-run the move to finish the rest." >&2
        return 1
    fi
    echo "priority $bead $derivation"
    if [ "$n" -gt 0 ]; then
        echo "re-ranked $n bead(s): $(printf '%s' "$out" | jq -r '[ .writes[] | "\(.id) P\(.from)->P\(.to)" ] | join(", ")')"
    else
        echo "no other bead needed a new priority"
    fi
    [ -z "$claimed" ] || echo "claimed, left as they are: $claimed"
    if [ -n "$errors" ]; then
        echo "unreadable, left as they are: $errors" >&2
        return 1
    fi
    return 0
}

# --- reconcile -----------------------------------------------------------------
# The controller keeps an exec order's output only when it exits non-zero, so a
# pass that exits 0 having skipped its work, or left some of it, says so in the
# per-run file the controller names in GC_ORDER_OUTCOME_FILE (gascity's
# exec-order outcome contract). Pairs follow the reason: a bead the pass left
# for the next one, and what it left undone on it.
declare_outcome() { # <skipped|partial> <reason> [<bead-id> <what-was-left>]...
    [ -n "${GC_ORDER_OUTCOME_FILE:-}" ] || return 0
    local outcome="$1" reason="$2"; shift 2
    jq -nc --arg o "$outcome" --arg r "$reason" \
        '{outcome: $o, reason: $r,
          scopes: ($ARGS.positional | [range(0; length; 2) as $i | {scope: .[$i], reason: .[$i + 1]}])}' \
        --args "$@" > "$GC_ORDER_OUTCOME_FILE" 2>/dev/null || true
}

settle_fits_budget() {
    [ "$PASS_BUDGET_SECS" -gt 0 ] || return 0
    [ $(( PASS_T0 + PASS_BUDGET_SECS - $(now_epoch) )) -ge "$SETTLE_ALLOWANCE_SECS" ]
}

# resolve_pool <rig> — the rig's polecat pool, in REPLY: the qualified name of
# the one agent the roster places in the rig under the name polecat. gascity
# names an imported agent <rig>/<binding>.<name>, and the binding is the key the
# city imports the pack under, so only the roster knows the name the pool's work
# is routed to. Returns 1 when the roster cannot be read or lists no agents, and
# 2 when it names no such agent in the rig or several. POOL_NOTE says which.
POOL_NOTE=""
resolve_pool() {
    local rig="$1" raw found n
    REPLY=""; POOL_NOTE=""
    raw="$(if command -v timeout >/dev/null 2>&1; then timeout 15 gc agent list --json; else gc agent list --json; fi 2>/dev/null 9>&-)" \
        || { POOL_NOTE="gc agent list failed"; return 1; }
    found="$(printf '%s' "$raw" | scrub | jq -c --arg rig "$rig" '
        if ((.agents // null) | type) != "array" or (.agents | length) == 0 then error("no agents listed")
        else [ .agents[] | objects
               | select(((.dir // "") | tostring) == $rig and ((.name // "") | tostring) == "polecat")
               | (.qualified_name // "") | tostring | select(. != "") ] | unique end' 2>/dev/null)"
    [ -n "$found" ] || { POOL_NOTE="gc agent list answered with no readable agent list"; return 1; }
    n="$(printf '%s' "$found" | jq 'length')"
    case "$n" in
        1) REPLY="$(printf '%s' "$found" | jq -r '.[0]')"; return 0 ;;
        0) POOL_NOTE="no agent in rig $rig is named polecat" ;;
        *) POOL_NOTE="$n agents in rig $rig are named polecat: $(printf '%s' "$found" | jq -r 'join(", ")')" ;;
    esac
    return 2
}

cmd_reconcile() {
    local pool=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --pool) shift; pool="${1:-}" ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: reconcile: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    [ -n "$BD_DB" ] || BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
    [ -n "$BD_DB" ] || { echo "$PROG: reconcile: no store to read: GC_RIG_ROOT is unset and no --db was given" >&2; return 2; }
    [ -n "$pool" ] || [ -n "${GC_RIG:-}" ] || { echo "$PROG: reconcile: no pool to read: GC_RIG is unset and no --pool was given" >&2; return 2; }

    PASS_T0="$(now_epoch)"
    if [ -z "$pool" ]; then
        local pool_rc=0
        resolve_pool "$GC_RIG" || pool_rc=$?
        case "$pool_rc" in
            0) pool="$REPLY" ;;
            1)
                echo "$PROG: reconcile: could not read the agent roster to find the polecat pool of rig $GC_RIG ($POOL_NOTE); NOT treating its queue as empty" >&2
                return 1 ;;
            *)
                echo "$PROG: reconcile: cannot tell which queue to read: $POOL_NOTE. Name the pool with --pool <rig>/<binding>.polecat" >&2
                return 2 ;;
        esac
    fi
    if [ "$DRY_RUN" != 1 ]; then
        local lock_rc=0
        take_lock nowait reconcile || lock_rc=$?
        case "$lock_rc" in
            0) ;;
            1)
                echo "$PROG: the priority lock on $BD_DB is held ($LOCK_NOTE); skipping this tick"
                declare_outcome skipped "the priority lock is held ($LOCK_NOTE)"
                return 0 ;;
            2)
                echo "$PROG: reconcile: the priority lock on $BD_DB has been held past ${LOCK_STALL_SECS}s ($LOCK_NOTE); its holder is wedged and nothing is settling" >&2
                return 1 ;;
            *)
                echo "$PROG: reconcile: the priority lock cannot be taken ($LOCK_NOTE); refusing to write without it" >&2
                return 1 ;;
        esac
    fi

    local raw ids seed graph rows
    mktemp_tracked || return 1; seed="$REPLY"
    mktemp_tracked || return 1; graph="$REPLY"
    mktemp_tracked || return 1; rows="$REPLY"
    # The queue as the pool's claim reads it, ephemeral beads included.
    raw="$(bd_ ready --metadata-field "gc.routed_to=$pool" --unassigned --include-ephemeral --json --limit 0 2>/dev/null)" \
        || { echo "$PROG: reconcile: could not read the queue for $pool; NOT treating it as empty" >&2; return 1; }
    ids="$(printf '%s' "$raw" | scrub | jq -r "$ROWS_JQ"' | [ .[] | objects | (.id // "") | tostring | select(. != "") ] | unique | join(",")' 2>/dev/null)" \
        || { echo "$PROG: reconcile: the queue for $pool did not parse; NOT treating it as empty" >&2; return 1; }
    # Only the ids are taken from the queue. Each queued bead is read again
    # through qp_read, so the pass computes from the rows settle and the move
    # read, and a bead claimed or closed since the queue was read has left it.
    if [ -n "$ids" ]; then
        raw="$(qp_read "$ids")" || { echo "$PROG: reconcile: could not read the beads queued for $pool" >&2; return 1; }
    else
        raw='[]'
    fi
    printf '%s' "$raw" | scrub | jq -c "$ROWS_JQ"' | [ .[] | objects
        | select(((.status // "") | tostring) == "open" and ((.assignee // "") | tostring) == "") ]' > "$seed" 2>/dev/null \
        || { echo "$PROG: reconcile: the read of the beads queued for $pool did not parse" >&2; return 1; }
    local queued
    queued="$(jq 'length' "$seed")"
    if [ "$queued" = 0 ]; then
        echo "$PROG: the queue for $pool is empty"
        return 0
    fi
    priority_graph qp_read "$seed" "$graph" \
        || { echo "$PROG: reconcile: could not read what the queued beads follow" >&2; return 1; }
    # One line for each queued bead whose priority cannot be computed, then one
    # for each subject (the bead a workflow bead was poured for) of the queued
    # beads at a stale priority: its row and priority, those queued beads, and
    # every bead between one of them and the subject that reads another level.
    # Subjects come most urgent first, so a short pass fixes the head first.
    jq -c --slurpfile g "$graph" "$PRIORITY_JQ$WRITABLE_JQ"'
        $g[0] as $g
        | [ .[] | objects | priority_of($g) as $r | priority_chain($g) as $c
            | {id: (.id | tostring), stored: .priority, r: $r, chain: $c, subject: ($c | last),
               sp: ($c | last | priority_of($g))} ] as $q
        | ($q[] | select((.r | has("error")) or (.sp | has("error"))) | {id, error: (.r.error // .sp.error)}),
          ([ $q[] | select(((.r | has("error")) or (.sp | has("error"))) | not) | select(.stored != .r.priority) ]
           | group_by(.subject.id | tostring)
           | map(.[0].sp.priority as $p | (.[0].subject.id | tostring) as $s
               | {subject: .[0].subject, sp: .[0].sp, rank: (map(.r.priority) | min), first: (map(.id) | min),
                  queued: [ .[] | {id, stored} ],
                  chain: ([ .[] | .chain[] | select(((.id // "") | tostring) != $s) | select(writable)
                            | select(.priority != $p) | {id: (.id | tostring), to: $p} ] | unique_by(.id))})
           | sort_by(.rank, .first) | .[])' "$seed" > "$rows" 2>/dev/null \
        || { echo "$PROG: reconcile: could not compute the queued beads' priorities" >&2; return 1; }

    local line subject sp derivation queued_note missing next failed=0 settled=0 stale=0 left=0 wf_plan
    local -a left_ids=() scopes=()
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        if printf '%s' "$line" | jq -e 'has("error")' >/dev/null 2>&1; then
            echo "$PROG: WARN the priority of queued $(printf '%s' "$line" | jq -r '.id') cannot be computed: $(printf '%s' "$line" | jq -r '.error')" >&2
            failed=$((failed + 1)); continue
        fi
        stale=$((stale + $(printf '%s' "$line" | jq '.queued | length')))
        subject="$(printf '%s' "$line" | jq -r '.subject.id')"
        sp="$(printf '%s' "$line" | jq -r '.sp.priority')"
        derivation="$(printf '%s' "$line" | jq -r ".sp | $DERIVATION_JQ")"
        queued_note="$(printf '%s' "$line" | jq -r '[ .queued[] | "\(.id) was P\(.stored)" ] | join(", ")')"
        if ! settle_fits_budget; then
            left=$((left + 1)); left_ids+=("$subject"); scopes+=("$subject" "settle left for the next pass")
            continue
        fi
        mktemp_tracked || { failed=$((failed + 1)); continue; }; wf_plan="$REPLY"
        echo '[]' > "$wf_plan"
        if ! settle_subject "$(printf '%s' "$line" | jq -c '.subject')" "$sp" "$wf_plan"; then
            echo "$PROG: WARN could not read the workflows poured for $subject; left at its old priority" >&2
            failed=$((failed + 1)); continue
        fi
        # The beads between each queued bead and its subject join the plan: a
        # workflow poured for a step of another workflow is not one of the
        # workflows poured for the subject, and still follows it.
        next="$(jq -c --argjson line "$line" '. + $line.chain | unique_by(.id)' "$wf_plan")" && printf '%s\n' "$next" > "$wf_plan" \
            || { echo "$PROG: WARN could not plan the queued beads of $subject; left at their old priority" >&2; failed=$((failed + 1)); continue; }
        # A queued bead the plan does not reach would stay stale on every pass,
        # so the pass names it and counts the subject failed.
        missing="$(jq -r --argjson line "$line" 'map(.id) as $ids | [ $line.queued[].id | select(. as $q | $ids | index($q) | not) ] | join(" ")' "$wf_plan")"
        if [ "$DRY_RUN" = 1 ]; then
            echo "$PROG: DRY-RUN would settle $subject at $derivation, queued $queued_note: $(jq -r '[ .[] | "\(.id)->P\(.to)" ] | join(" ")' "$wf_plan")"
            if [ -n "$missing" ]; then
                echo "$PROG: WARN settling $subject would not reach queued $missing" >&2
                failed=$((failed + 1))
            else
                settled=$((settled + 1))
            fi
            continue
        fi
        if ! write_priorities "$wf_plan"; then
            echo "$PROG: WARN $subject did not settle at P$sp: $MISMATCH" >&2
            failed=$((failed + 1)); continue
        fi
        if [ -n "$missing" ]; then
            echo "$PROG: WARN settled $subject at $derivation, but its writes did not reach queued $missing, left at the old priority" >&2
            failed=$((failed + 1)); continue
        fi
        echo "$PROG: settled $subject at $derivation (queued $queued_note)${SKIPPED:+, claimed $SKIPPED left as it is}: wrote $WROTE bead(s)"
        settled=$((settled + 1))
    done < "$rows"

    if [ "$left" -gt 0 ]; then
        echo "$PROG: the pass budget is spent; left $left bead(s) for the next pass: ${left_ids[*]}"
        [ "$failed" != 0 ] || declare_outcome partial "pass budget spent: $left bead(s) left for the next pass" "${scopes[@]}"
    fi
    echo "$PROG: $queued queued for $pool, $stale at a stale priority, $settled settled, $left left for the next pass, $failed failed"
    [ "$failed" = 0 ]
}

# --- main ----------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    settle)    cmd_settle "$@" ;;
    move)      cmd_move "$@" ;;
    reconcile) cmd_reconcile "$@" ;;
    -h|--help|help) usage; exit 0 ;;
    "") usage >&2; exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
