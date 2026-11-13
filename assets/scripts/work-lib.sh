#!/usr/bin/env bash
# work-lib.sh — what mol-polecat-work's step scripts share. Sourced, never
# executed.
#
# A step script reads its work bead once, through work_read, and passes the
# fields along. Gas City leaves the bead a run works open and unassigned, and a
# step reaches it only through the input convoy it was poured over, or through
# the bead itself for a claimant with no poured workflow.
#
#   work_resolve <convoy> <bead>  WORK_ID is the bead, 0; 1 the store did not
#                                 answer; 2 the convoy tracks no single bead
#   work_read <id>                WORK_ROW is the bead's row, 0; 1 the store did
#                                 not answer; 3 the store has no such bead
#   work_meta <key>               the row's metadata value, "" when absent
#   work_field <jq-filter>        one field of the row, "" when absent
#   work_is_self <name>           whether <name> is one this session goes by
#   work_owner_listed <name>      how many listed sessions go by <name>, "" when
#                                 the list cannot be read
#   work_outage <what>            stops the step, having asked nothing
#   work_stop_with_gate <key> <message> <reason>
#                                 a person must rule before the work goes on, so
#                                 the run ends on a gate its work bead waits on
#   work_drain                    ends the session's run
#   work_held_by_proof            whether the sitting WORK_HELD_BY names holds the
#                                 work bead: 0, or 1 having said why not
#   work_held_stop <why>          stops a sitting's call, ending nothing
#
# The store's answer decides, not a jq filter's: `gc bd show` exits 1 and prints
# an error object for a bead it does not have, and exits non-zero with no JSON
# when it cannot answer. A filter fed either one yields an empty value with exit
# 0, which a step would read as an absent field.
#
# A converse sitting calls work-setup.sh and work-submit.sh with --held-by
# <conversation>, which the caller puts in WORK_HELD_BY. The sitting's claim is
# the conversation, it outlives the call, and it is in the conversation to hear
# why a call stopped. So under WORK_HELD_BY nothing here files a gate, cancels a
# run or drains: work_outage and work_stop_with_gate say why and stop, and
# work_drain does nothing.
#
# A caller sets PROG and SCRIPT_DIR before it sources this file, and STEP and
# FORMULA before it calls work_stop_with_gate. It sources run-lib.sh before it
# calls work_held_by_proof. WORK_READ_TRIES and WORK_READ_WAIT bound
# the retry; a suite sets the wait to 0.

WORK_READ_TRIES="${WORK_READ_TRIES:-3}"
WORK_READ_WAIT="${WORK_READ_WAIT:-5}"
WORK_ID=""
WORK_ROW=""

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

work_resolve() {
  local convoy="$1" bead="$2" try=1 raw
  if [ -n "$bead" ]; then
    WORK_ID="$bead"
    return 0
  fi
  while :; do
    if raw=$(gc convoy status "$convoy" --json </dev/null 2>/dev/null) && printf '%s' "$raw" | scrub | jq -e '.children | type == "array"' >/dev/null 2>&1; then
      WORK_ID=$(printf '%s' "$raw" | scrub | jq -r 'if (.children | length) == 1 then .children[0].id else empty end')
      [ -n "$WORK_ID" ] && return 0
      return 2
    fi
    [ "$try" -lt "$WORK_READ_TRIES" ] || return 1
    try=$((try + 1))
    sleep "$WORK_READ_WAIT"
  done
}

work_read() {
  local id="$1" try=1 raw rc
  while :; do
    raw=$(gc bd show "$id" --json </dev/null 2>/dev/null); rc=$?
    raw=$(printf '%s\n' "$raw" | grep -a -vE '^gc bd:' | scrub)
    if [ "$rc" = 0 ] && printf '%s' "$raw" | jq -e --arg id "$id" 'type == "array" and .[0].id == $id' >/dev/null 2>&1; then
      WORK_ROW="$raw"
      return 0
    fi
    if printf '%s' "$raw" | jq -e 'type == "object" and ((.error // "") | tostring | test("no issues? found"))' >/dev/null 2>&1; then
      return 3
    fi
    [ "$try" -lt "$WORK_READ_TRIES" ] || return 1
    try=$((try + 1))
    sleep "$WORK_READ_WAIT"
  done
}

work_meta() {
  printf '%s' "$WORK_ROW" | jq -r --arg k "$1" '.[0].metadata[$k] // "" | tostring'
}

work_field() {
  printf '%s' "$WORK_ROW" | jq -r ".[0] | ($1) // \"\" | tostring"
}

work_is_self() {
  [ -n "$1" ] || return 1
  case "$1" in
    "${GC_SESSION_NAME:-}"|"${GC_SESSION_ID:-}"|"${GC_AGENT:-}"|"${GC_ALIAS:-}") return 0 ;;
  esac
  return 1
}

# An assignee is any of the forms a claim writes: the session name, the session
# id, or the agent address, which is a session's alias or the end of one.
work_owner_listed() {
  gc session list --json </dev/null 2>/dev/null | scrub | jq -r --arg o "$1" '
    if type == "object" and (.sessions | type) == "array" and all(.sessions[]; type == "object") then
      [ .sessions[] | select(((.alias // "") == $o) or ((.alias // "") | endswith($o))
                             or ((.session_name // "") == $o) or ((.id // "") == $o)) ] | length
    else empty end' 2>/dev/null
}

# A store that cannot answer is no fact about the work: no gate and no cancel,
# so the step is offered again once the store answers, and a sitting runs the
# call again.
work_outage() {
  [ -z "${WORK_HELD_BY:-}" ] || work_held_stop "$1. The store did not answer, so run this again once it answers"
  echo "$PROG: $1. The store did not answer, so nothing was asked and nothing was cancelled, and this step goes back to the pool." >&2
  gc runtime drain-ack
  exit 1
}

work_stop_with_gate() {
  [ -z "${WORK_HELD_BY:-}" ] || work_held_stop "$3"
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "$3" --subject "$WORK_ID" --key "$1" --formula "$FORMULA" --message "$2"
  exit 1
}

work_drain() {
  [ -n "${WORK_HELD_BY:-}" ] || gc runtime drain-ack
}

work_held_stop() {
  echo "$PROG: $1. Nothing was asked, cancelled or drained." >&2
  exit 1
}

# The reader run-lib.sh's verbs call: bd's own arguments, against this store.
work_bd() { gc bd "$@"; }

# The sitting holds the work bead when gc hook current names its conversation
# and the bead has a blocks edge onto it, which keeps every pool off the bead
# while the conversation is open. A bead someone else holds or is queued to take
# is refused whatever the hook and the edge say: one assigned to anyone, the
# refinery included; one a live run works, which only run-lib.sh tells, since
# Gas City leaves a bead under a run open, unassigned and unrouted; and one
# whose gc.routed_to names the pool queue that serves it once bd reports it
# ready (dispatch-path.sh). Every reason is named, the holder's first, so a bead
# the refinery has is refused as the refinery's whether or not its edge stands.
work_held_by_proof() {
  local why="" owner runs live route claimed
  owner=$(work_field .assignee)
  [ -z "$owner" ] || why="$why; it is assigned to $owner"
  runs=$(run_lib runs work_bd "$WORK_ID") || work_outage "could not read the runs that work $WORK_ID"
  live=$(printf '%s' "$runs" | jq -r '[.[] | select(.live) | .root] | join(", ")')
  [ -z "$live" ] || why="$why; a run works it ($live)"
  route=$(work_meta gc.routed_to)
  [ -z "$(printf '%s' "$route" | tr -d '[:space:]')" ] || why="$why; it is routed to $route"
  claimed=$(gc hook current --id-only </dev/null 2>/dev/null) || claimed=""
  [ "$claimed" = "$WORK_HELD_BY" ] || why="$why; gc hook current names ${claimed:-no bead}, not $WORK_HELD_BY"
  printf '%s' "$WORK_ROW" | jq -e --arg c "$WORK_HELD_BY" \
      'any(.[0].dependencies[]?; (.id // "") == $c and (.dependency_type // "") == "blocks")' >/dev/null 2>&1 \
    || why="$why; it has no blocks edge onto $WORK_HELD_BY"
  [ -n "$why" ] || return 0
  echo "$PROG: $WORK_ID is not held by $WORK_HELD_BY: ${why#; }. Nothing was written." >&2
  return 1
}
