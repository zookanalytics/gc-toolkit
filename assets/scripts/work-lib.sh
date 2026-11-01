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
#
# The store's answer decides, not a jq filter's: `gc bd show` exits 1 and prints
# an error object for a bead it does not have, and exits non-zero with no JSON
# when it cannot answer. A filter fed either one yields an empty value with exit
# 0, which a step would read as an absent field.
#
# A caller sets PROG and SCRIPT_DIR before it sources this file, and STEP and
# FORMULA before it calls work_stop_with_gate. WORK_READ_TRIES and WORK_READ_WAIT bound
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
  gc session list --state all --json </dev/null 2>/dev/null | scrub | jq -r --arg o "$1" '
    if type == "object" and (.sessions | type) == "array" and all(.sessions[]; type == "object") then
      [ .sessions[] | select(((.alias // "") == $o) or ((.alias // "") | endswith($o))
                             or ((.session_name // "") == $o) or ((.id // "") == $o)) ] | length
    else empty end' 2>/dev/null
}

# A store that cannot answer is no fact about the work: no gate and no cancel,
# so the step is offered again once the store answers.
work_outage() {
  echo "$PROG: $1. The store did not answer, so nothing was asked and nothing was cancelled, and this step goes back to the pool." >&2
  gc runtime drain-ack
  exit 1
}

work_stop_with_gate() {
  "$SCRIPT_DIR/decline.sh" --step "$STEP" --reason "$3" --subject "$WORK_ID" --key "$1" --formula "$FORMULA" --message "$2"
  exit 1
}
