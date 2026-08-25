#!/usr/bin/env bash
# lifecycle.sh — THE writer of anchor lifecycle transitions (lifecycle/lifecycle.toml).
#   lifecycle.sh transition <bead-id> --to <state> [--expect <state>] [--set k=v]...
#     [--unset k]... [--assignee <a>] [--route <pool>] [--close] [--append-notes <t>] [--json]
#   lifecycle.sh state <bead-id>
#   lifecycle.sh reopen <bead-id>
# transition: validate the edge against the declared machine, perform ONE atomic
# `gc bd update` carrying every field, re-read and verify each written field.
# --close only into a closed state, and a closed state requires --close (status
# and merge_result move together). Human states also stamp gc.routed_to=human
# in the same call unless --route is given.
# reopen: repair a bead closed while merge_result is a NON-closed state — set
# status=open, merge_result untouched. Human-invoked only (docs/authority-map.md).
# Callers: pr-open.sh, merge.sh, pr-facts.sh, mol-refinery-patrol.
# Exits: 0 ok; 1 illegal edge / --expect mismatch / bd refusal / usage;
# 2 post-write verification mismatch (or unreadable bead).
# CAVEAT (docs/gascity-routing-model.md row 46): clearing an assignee on a bead
# another actor holds in_progress is refused by bd, and the refusal drops the
# WHOLE atomic update — a caller that passes --assignee "" must hold the claim.
set -u

PROG="lifecycle"

# The one scrubber the pack standardizes on: strips control chars that break
# `--json` parsing while keeping TAB/LF/CR.
scrub() { tr -d '\000-\010\013\014\016-\037'; }

# >>> lifecycle-state-table
# Mirrors lifecycle/lifecycle.toml exactly; lifecycle.test.sh fails on drift.
LIFECYCLE_STATES="unanchored pre_open_gate pull_request merged abandoned retargeted blocked refused_false_completion"
LIFECYCLE_HUMAN_STATES="abandoned retargeted blocked refused_false_completion"
LIFECYCLE_CLOSED_STATES="merged"
LIFECYCLE_TRANSITIONS="
unanchored>pre_open_gate
unanchored>pull_request
unanchored>merged
unanchored>blocked
unanchored>refused_false_completion
pre_open_gate>pull_request
pre_open_gate>unanchored
pull_request>merged
pull_request>abandoned
pull_request>retargeted
pull_request>unanchored
abandoned>unanchored
retargeted>pull_request
retargeted>unanchored
blocked>unanchored
refused_false_completion>unanchored
"
# <<< lifecycle-state-table

is_state() { # <name>
  case " $LIFECYCLE_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_human_state() { # <name>
  case " $LIFECYCLE_HUMAN_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_closed_state() { # <name>
  case " $LIFECYCLE_CLOSED_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

edge_legal() { # <from> <to>  (a self-edge is always legal: idempotent re-record)
  [ "$1" = "$2" ] && return 0
  case "$LIFECYCLE_TRANSITIONS" in *"
$1>$2
"*) return 0 ;; *) return 1 ;; esac
}

read_bead() { # <id> -> the bead object, or nothing
  gc bd show "$1" --json 2>/dev/null | scrub | jq -c '.[0] // empty' 2>/dev/null
}

# Current state off a bead object: merge_result, "unanchored" when absent.
state_of() { # <bead-json>; echoes state, or "?<raw>" for an undeclared value
  local mr
  mr=$(printf '%s' "$1" | jq -r '(.metadata.merge_result // "") | tostring' 2>/dev/null)
  if [ -z "$mr" ]; then printf 'unanchored'; return 0; fi
  if is_state "$mr" && [ "$mr" != "unanchored" ]; then printf '%s' "$mr"; return 0; fi
  printf '?%s' "$mr"
  return 1
}

cmd_state() { # <bead-id>
  local id="${1:-}" bead st
  [ -n "$id" ] || { echo "$PROG: state needs a bead id" >&2; exit 1; }
  bead=$(read_bead "$id")
  if [ -z "$bead" ]; then
    echo "$PROG: $id unreadable — cannot answer its state" >&2; exit 2
  fi
  st=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${st#?}' — not a state lifecycle.toml declares" >&2
    exit 1
  }
  printf '%s\n' "$st"
  exit 0
}

cmd_transition() {
  local id="${1:-}"; shift || true
  [ -n "$id" ] || { echo "$PROG: transition needs a bead id" >&2; exit 1; }
  local TO="" EXPECT="" ROUTE="" ROUTE_SET=0 ASSIGNEE="" ASSIGNEE_SET=0
  local CLOSE=0 NOTES="" NOTES_SET=0 JSON=0
  local SETS=() UNSETS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --to)           TO="${2:-}"; shift 2 ;;
      --expect)       EXPECT="${2:-}"; shift 2 ;;
      --set)          SETS+=("${2:-}"); shift 2 ;;
      --unset)        UNSETS+=("${2:-}"); shift 2 ;;
      --assignee)     ASSIGNEE="${2-}"; ASSIGNEE_SET=1; shift 2 ;;
      --route)        ROUTE="${2:-}"; ROUTE_SET=1; shift 2 ;;
      --close)        CLOSE=1; shift ;;
      --append-notes) NOTES="${2:-}"; NOTES_SET=1; shift 2 ;;
      --json)         JSON=1; shift ;;
      *) echo "$PROG: unknown argument '$1'" >&2; exit 1 ;;
    esac
  done
  [ -n "$TO" ] || { echo "$PROG: transition needs --to <state>" >&2; exit 1; }
  is_state "$TO" || { echo "$PROG: '$TO' is not a declared state" >&2; exit 1; }
  # status and merge_result move together: a close on a non-terminal state (or
  # a terminal state left open) is the closed-means-landed violation (I5).
  if [ "$CLOSE" = 1 ] && ! is_closed_state "$TO"; then
    echo "$PROG: --close refused with --to $TO — '$TO' is not a closed state (closed_states: $LIFECYCLE_CLOSED_STATES); a closed bead on a non-terminal merge_result is invisible to every open-bead consumer" >&2
    exit 1
  fi
  if [ "$CLOSE" = 0 ] && is_closed_state "$TO"; then
    echo "$PROG: --to $TO requires --close — a closed state must close in the same atomic write, or the bead is left open+$TO" >&2
    exit 1
  fi
  local kv
  for kv in ${SETS[@]+"${SETS[@]}"}; do
    case "${kv%%=*}" in
      merge_result) echo "$PROG: merge_result is written by --to, never by --set" >&2; exit 1 ;;
      gc.routed_to) echo "$PROG: route via --route, never by --set" >&2; exit 1 ;;
    esac
  done

  local bead cur
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id unreadable — refusing to transition blind" >&2; exit 2; }
  cur=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${cur#?}'; repair it before transitioning" >&2
    exit 1
  }
  if [ -n "$EXPECT" ] && [ "$cur" != "$EXPECT" ]; then
    echo "$PROG: $id is '$cur', not the expected '$EXPECT'; transition refused" >&2
    exit 1
  fi
  if ! edge_legal "$cur" "$TO"; then
    echo "$PROG: illegal edge $cur -> $TO for $id (declared machine: lifecycle/lifecycle.toml)" >&2
    exit 1
  fi
  # Human states route to a human as part of the same transition.
  if [ "$ROUTE_SET" = 0 ] && is_human_state "$TO"; then
    ROUTE="human"; ROUTE_SET=1
  fi

  local ARGS=()
  if [ "$TO" = "unanchored" ]; then
    ARGS+=(--unset-metadata merge_result)
  else
    ARGS+=(--set-metadata "merge_result=$TO")
  fi
  for kv in ${SETS[@]+"${SETS[@]}"}; do ARGS+=(--set-metadata "$kv"); done
  local k
  for k in ${UNSETS[@]+"${UNSETS[@]}"}; do ARGS+=(--unset-metadata "$k"); done
  [ "$ROUTE_SET" = 1 ] && ARGS+=(--set-metadata "gc.routed_to=$ROUTE")
  [ "$ASSIGNEE_SET" = 1 ] && ARGS+=(--assignee="$ASSIGNEE")
  [ "$CLOSE" = 1 ] && ARGS+=(--status=closed)
  [ "$NOTES_SET" = 1 ] && ARGS+=(--append-notes "$NOTES")

  # ONE atomic write carrying every field of the transition.
  local out rc
  out=$(gc bd update "$id" "${ARGS[@]}" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "$PROG: $id $cur -> $TO refused by bd (rc=$rc): $out" >&2
    exit 1
  fi

  # Re-read and verify every written field; a write that reported success but
  # did not land must never be reported as a transition.
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id $cur -> $TO written but the read-back failed; UNVERIFIED" >&2; exit 2; }
  local BAD="" got v
  got=$(printf '%s' "$bead" | jq -r '(.metadata.merge_result // "") | tostring')
  if [ "$TO" = "unanchored" ]; then
    [ -z "$got" ] || BAD="$BAD merge_result='$got'(want absent)"
  else
    [ "$got" = "$TO" ] || BAD="$BAD merge_result='$got'(want '$TO')"
  fi
  for kv in ${SETS[@]+"${SETS[@]}"}; do
    k="${kv%%=*}"; v="${kv#*=}"
    got=$(printf '%s' "$bead" | jq -r --arg k "$k" '(.metadata[$k] // "") | tostring')
    [ "$got" = "$v" ] || BAD="$BAD $k='$got'(want '$v')"
  done
  for k in ${UNSETS[@]+"${UNSETS[@]}"}; do
    got=$(printf '%s' "$bead" | jq -r --arg k "$k" '(.metadata[$k] // "") | tostring')
    [ -z "$got" ] || BAD="$BAD $k='$got'(want unset)"
  done
  if [ "$ROUTE_SET" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    [ "$got" = "$ROUTE" ] || BAD="$BAD gc.routed_to='$got'(want '$ROUTE')"
  fi
  if [ "$ASSIGNEE_SET" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.assignee // "") | tostring')
    [ "$got" = "$ASSIGNEE" ] || BAD="$BAD assignee='$got'(want '$ASSIGNEE')"
  fi
  if [ "$CLOSE" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
    [ "$got" = "closed" ] || BAD="$BAD status='$got'(want closed)"
  fi
  if [ "$NOTES_SET" = 1 ] && [ -n "$NOTES" ]; then
    got=$(printf '%s' "$bead" | jq -r '(.notes // "") | tostring')
    case "$got" in *"$NOTES"*) : ;; *) BAD="$BAD notes(missing appended text)" ;; esac
  fi
  if [ -n "$BAD" ]; then
    echo "$PROG: $id $cur -> $TO wrote but did NOT verify:$BAD" >&2
    exit 2
  fi

  if [ "$JSON" = 1 ]; then
    jq -nc --arg id "$id" --arg from "$cur" --arg to "$TO" \
      '{id: $id, from: $from, to: $to, ok: true}'
  else
    echo "$PROG: $id $cur -> $TO"
  fi
  exit 0
}

cmd_reopen() { # <bead-id> — repair a wrongly-closed bead (closed + non-closed state)
  local id="${1:-}"; shift || true
  [ -n "$id" ] || { echo "$PROG: reopen needs a bead id" >&2; exit 1; }
  [ $# -eq 0 ] || { echo "$PROG: reopen takes no options — it only sets status=open" >&2; exit 1; }
  local bead st status
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id unreadable — refusing to reopen blind" >&2; exit 2; }
  st=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${st#?}'; repair it before reopening" >&2
    exit 1
  }
  status=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
  if [ "$status" != "closed" ]; then
    echo "$PROG: $id is not closed (status='$status') — nothing to repair" >&2
    exit 1
  fi
  if [ "$st" = "unanchored" ]; then
    echo "$PROG: $id is closed with no merge_result — a closed unanchored bead is legal; reopen refused" >&2
    exit 1
  fi
  if is_closed_state "$st"; then
    echo "$PROG: $id is closed as '$st', a closed state — that close is legitimate; reopen refused" >&2
    exit 1
  fi

  local out rc
  out=$(gc bd update "$id" --status=open 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "$PROG: $id reopen refused by bd (rc=$rc): $out" >&2
    exit 1
  fi
  # Same read-back discipline as transition: verify status flipped and
  # merge_result stayed put before reporting the repair.
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id reopen written but the read-back failed; UNVERIFIED" >&2; exit 2; }
  local BAD="" got
  got=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
  [ "$got" = "open" ] || BAD="$BAD status='$got'(want open)"
  got=$(printf '%s' "$bead" | jq -r '(.metadata.merge_result // "") | tostring')
  [ "$got" = "$st" ] || BAD="$BAD merge_result='$got'(want '$st' unchanged)"
  if [ -n "$BAD" ]; then
    echo "$PROG: $id reopen wrote but did NOT verify:$BAD" >&2
    exit 2
  fi
  echo "$PROG: $id reopened — status closed -> open, merge_result '$st' unchanged"
  exit 0
}

case "${1:-}" in
  transition) shift; cmd_transition "$@" ;;
  state)      shift; cmd_state "$@" ;;
  reopen)     shift; cmd_reopen "$@" ;;
  *)
    echo "usage: lifecycle.sh transition <bead-id> --to <state> [--expect <state>] [--set k=v]... [--unset k]... [--assignee <a>] [--route <pool>] [--close] [--append-notes <text>] [--json]" >&2
    echo "       lifecycle.sh state <bead-id>" >&2
    echo "       lifecycle.sh reopen <bead-id>   # repair a bead closed on a non-closed merge_result" >&2
    exit 1 ;;
esac
