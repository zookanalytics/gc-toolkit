#!/usr/bin/env bash
# pace-lib.sh — visit order and time budget for a merge-cadence arm that walks
# the gating set. Sourced, never executed.
#
# An arm that visits every gating anchor costs time in proportion to the set,
# and the pass that runs it has a fixed budget. A stopping point alone is not
# enough: an arm stopped part-way that started at the same anchor next pass
# would revisit the head of its list forever while the tail went unvisited. So
# the arm visits anchors in id order starting after the last one it finished,
# wraps, and records each anchor as it finishes it. Every anchor is then
# reached within a bounded number of passes, whether a pass ended at its
# deadline or was killed mid-anchor.
#
#   pace_order <cursor-file>      Rows (compact JSON, one per line) on stdin are
#                                 written to stdout in id order, starting after
#                                 the id the cursor file names and wrapping. An
#                                 absent or empty cursor file starts at the
#                                 lowest id. With no cursor path the rows pass
#                                 through unchanged, and so does a reorder that
#                                 fails.
#   pace_note <cursor-file> <id>  Record <id> as the last anchor finished. An
#                                 empty cursor path records nothing. Non-zero
#                                 when the write failed.
#   pace_spent <deadline>         True once the clock reaches <deadline> (epoch
#                                 seconds). An empty deadline is never spent.
#
# The walk itself:
#   pace_start <cursor-file> <deadline>
#   while IFS= read -r row; do
#     ...                         the arm's free skips: tests on the row alone
#     pace_visit <group> "$id"; case $? in 1) continue ;; 2) break ;; esac
#     ...                         the first read that costs, and the rest
#   done
#   pace_end
#
# pace_start takes the deadline as the arm received it. A value that is not
# epoch seconds leaves the walk unpaced, and the first such value warns once
# per process, so each arm hands its --deadline through unchecked.
#
# pace_visit goes after the arm's free skips and before its first read that
# costs: a gh call, a bead read or write, a git probe. A walk that starts past
# its deadline is guaranteed one visit, and an anchor the arm then skips for
# free would spend that visit and leave the walk with no progress made.
#
# pace_visit's group says how the anchor is paced. `rest` anchors rotate: an
# anchor is recorded as finished when the walk's next visit begins, so a walk
# the deadline stops, or a kill interrupts, resumes at the anchor it was on.
# `first` anchors come before the rest and rotate the same way on a cursor of
# their own, PACE_FIRST_CURSOR (the cursor file's path with `.first` appended),
# which the caller orders them by: `pace_order "$PACE_FIRST_CURSOR"` after
# pace_start. Acting on a first anchor usually takes it out of the walk's set,
# but one the arm holds stays in it, and in a fixed order the same held anchors
# would lead every pass while the deadline kept the group's tail waiting.
# `exempt` anchors are never stopped and never recorded. Past the deadline
# pace_visit returns 1 for a `first` anchor (skip it, and reach the rest) and 2
# for a `rest` anchor (stop the walk). One anchor of each paced group is always
# visited first, so a walk started past its deadline still makes progress on
# both. After the walk, PACE_VISITED counts the paced anchors visited,
# PACE_FIRST_SKIPPED the `first` anchors the deadline left for the next pass,
# and PACE_RESUME_AT names the rest anchor the deadline stopped at, if it did.
#
# Seen marks are what a walk saw of each anchor at its last visit, so an arm can
# put first the anchors that changed since then. A mark is a one-line string
# the arm builds from facts it reads without a per-anchor call, such as a PR's
# head and review count; two marks that differ mean the anchor changed between
# the visits.
#   pace_seen_start <seen-file>   Load the marks the file holds, one
#                                 "<id>\t<mark>\t<epoch>" line each, the last
#                                 line for an id winning, and rewrite it without
#                                 duplicates or marks older than
#                                 PACE_SEEN_TTL_SECS (14 days). PACE_SEEN_FRESH
#                                 is 1 when no mark loaded. An empty path loads
#                                 nothing and records nothing.
#   pace_seen_changed <id> <mark> True when the walk last saw <id> with another
#                                 mark, or never saw it. A walk with no marks at
#                                 all has no last visit to compare against, so
#                                 nothing reads as changed and its caller seeds
#                                 the marks with pace_seen_put instead.
#   pace_seen_get <id>            The mark last recorded for <id>, if any.
#   pace_seen_put <id> <mark>     Record <mark> for <id> now.
# pace_visit's optional third argument is the mark to record for the anchor in
# hand. It is recorded when the visit finishes, which is when the cursor
# records the anchor, so a visit the deadline refused or a kill cut short
# leaves the last mark standing. pace_seen_mark <mark> replaces it mid-visit,
# for an arm that knows only at the end which mark the visit earned.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=pace-lib.sh
#   . "$SCRIPTS_DIR/pace-lib.sh" || { echo "$PROG: cannot source pace-lib.sh" >&2; exit 1; }

pace_order() { # <cursor-file>; rows on stdin
  local after="" rows ordered
  if [ -z "${1:-}" ]; then
    cat
    return 0
  fi
  rows=$(cat)
  if [ -r "$1" ]; then
    IFS= read -r after < "$1" || true
  fi
  if ordered=$(printf '%s\n' "$rows" | jq -c -s --arg after "$after" '
       sort_by(.id) | (map(select(.id > $after)) + map(select((.id > $after) | not))) | .[]' 2>/dev/null) \
     && [ -n "$ordered" ]; then
    printf '%s\n' "$ordered"
  else
    printf '%s\n' "$rows"
  fi
}

pace_note() { # <cursor-file> <id>
  [ -n "${1:-}" ] || return 0
  { printf '%s\n' "$2" > "$1.tmp" && mv -f "$1.tmp" "$1"; } 2>/dev/null
}

pace_spent() { # <deadline-epoch-secs>
  [ -n "${1:-}" ] && [ "$(date +%s)" -ge "$1" ]
}

pace_start() { # <cursor-file> <deadline-epoch-secs>
  PACE_CURSOR="${1:-}"
  PACE_FIRST_CURSOR="${1:+$1.first}"
  PACE_DEADLINE="${2:-}"
  case "$PACE_DEADLINE" in
    *[!0-9]*)
      [ "${PACE_DEADLINE_WARNED:-0}" = 1 ] \
        || echo "${PROG:-pace}: WARN --deadline '$PACE_DEADLINE' is not epoch seconds; this pass is not paced" >&2
      PACE_DEADLINE_WARNED=1
      PACE_DEADLINE="" ;;
  esac
  PACE_VISITED=0
  PACE_FIRST_VISITED=0
  PACE_FIRST_SKIPPED=0
  PACE_REST_VISITED=0
  PACE_FINISHED=""
  PACE_FIRST_FINISHED=""
  PACE_RESUME_AT=""
  PACE_WARNED=0
  PACE_SEEN_ID=""
  PACE_SEEN_PENDING=""
}

declare -gA PACE_SEEN=()
pace_seen_start() { # <seen-file>
  local ttl now kept id mark _at
  declare -gA PACE_SEEN=()
  PACE_SEEN_FILE="${1:-}"
  PACE_SEEN_FRESH=1
  PACE_SEEN_WARNED=0
  [ -n "$PACE_SEEN_FILE" ] && [ -r "$PACE_SEEN_FILE" ] || return 0
  ttl="${PACE_SEEN_TTL_SECS:-1209600}"
  case "$ttl" in ''|*[!0-9]*) ttl=1209600 ;; esac
  printf -v now '%(%s)T' -1
  kept=$(awk -F'\t' -v cut="$(( now - 10#$ttl ))" '
    NF == 3 && $1 != "" && $2 != "" && $3 ~ /^[0-9]+$/ && $3 + 0 >= cut + 0 { m[$1] = $0 }
    END { for (k in m) print m[k] }' "$PACE_SEEN_FILE" 2>/dev/null) || kept=""
  while IFS=$'\t' read -r id mark _at; do
    [ -n "$id" ] && [ -n "$mark" ] || continue
    PACE_SEEN["$id"]="$mark"
    PACE_SEEN_FRESH=0
  done <<< "$kept"
  { { [ -z "$kept" ] || printf '%s\n' "$kept"; } > "$PACE_SEEN_FILE.tmp" \
      && mv -f "$PACE_SEEN_FILE.tmp" "$PACE_SEEN_FILE"; } 2>/dev/null
  return 0
}

pace_seen_get() { # <id>
  printf '%s' "${PACE_SEEN[${1:-}]-}"
}

pace_seen_changed() { # <id> <mark>
  [ "${PACE_SEEN_FRESH:-1}" = 1 ] && return 1
  [ "${PACE_SEEN[${1:-}]-}" != "${2:-}" ]
}

pace_seen_put() { # <id> <mark>
  local m="${2:-}" now
  [ -n "${PACE_SEEN_FILE:-}" ] && [ -n "${1:-}" ] && [ -n "$m" ] || return 0
  m="${m//$'\t'/ }"; m="${m//$'\n'/ }"
  PACE_SEEN["$1"]="$m"
  printf -v now '%(%s)T' -1
  { printf '%s\t%s\t%s\n' "$1" "$m" "$now" >> "$PACE_SEEN_FILE"; } 2>/dev/null && return 0
  [ "${PACE_SEEN_WARNED:-0}" = 1 ] \
    || echo "${PROG:-pace}: WARN cannot record seen marks in $PACE_SEEN_FILE; the next pass compares against the last marks it could write" >&2
  PACE_SEEN_WARNED=1
  return 0
}

pace_seen_mark() { # <mark>
  PACE_SEEN_PENDING="${1:-}"
}

_pace_record() { # <cursor-file> <id>
  pace_note "$1" "$2" && return 0
  [ "$PACE_WARNED" = 1 ] \
    || echo "${PROG:-pace}: WARN cannot record progress in $1; the next pass starts the rotation over" >&2
  PACE_WARNED=1
  return 0
}

# The anchor in hand has finished once the walk's next visit begins, whichever
# group that visit is in.
_pace_flush() {
  if [ -n "$PACE_FIRST_FINISHED" ]; then
    _pace_record "$PACE_FIRST_CURSOR" "$PACE_FIRST_FINISHED"
    PACE_FIRST_FINISHED=""
  fi
  if [ -n "$PACE_FINISHED" ]; then
    _pace_record "$PACE_CURSOR" "$PACE_FINISHED"
    PACE_FINISHED=""
  fi
  if [ -n "${PACE_SEEN_ID:-}" ]; then
    pace_seen_put "$PACE_SEEN_ID" "${PACE_SEEN_PENDING:-}"
    PACE_SEEN_ID=""
    PACE_SEEN_PENDING=""
  fi
  return 0
}

pace_visit() { # <first|rest|exempt> <anchor-id> [<seen-mark>]
  _pace_flush
  case "$1" in
    exempt)
      PACE_SEEN_ID="$2"
      PACE_SEEN_PENDING="${3:-}"
      return 0 ;;
    first)
      if [ "$PACE_FIRST_VISITED" -gt 0 ] && pace_spent "$PACE_DEADLINE"; then
        PACE_FIRST_SKIPPED=$((PACE_FIRST_SKIPPED + 1))
        return 1
      fi
      PACE_FIRST_VISITED=$((PACE_FIRST_VISITED + 1))
      PACE_FIRST_FINISHED="$2" ;;
    *)
      if [ "$PACE_REST_VISITED" -gt 0 ] && pace_spent "$PACE_DEADLINE"; then
        # shellcheck disable=SC2034 # read by the arm that sourced this file
        PACE_RESUME_AT="$2"
        return 2
      fi
      PACE_REST_VISITED=$((PACE_REST_VISITED + 1))
      PACE_FINISHED="$2" ;;
  esac
  PACE_SEEN_ID="$2"
  PACE_SEEN_PENDING="${3:-}"
  PACE_VISITED=$((PACE_VISITED + 1))
  return 0
}

pace_end() {
  _pace_flush
}
