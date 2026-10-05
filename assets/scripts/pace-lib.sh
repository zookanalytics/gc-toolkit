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
#     ...
#     pace_visit <group> "$id"; case $? in 1) continue ;; 2) break ;; esac
#     ...
#   done
#   pace_end
#
# pace_visit's group says how the anchor is paced. `rest` anchors rotate: the
# previous rest anchor is recorded before this one starts, so a walk the
# deadline stops here, or a kill interrupts, resumes at this anchor. `first`
# anchors come before the rotation and count against the deadline, but move no
# cursor, because acting on one takes it out of the walk's set. `exempt`
# anchors are never stopped and never recorded. Past the deadline pace_visit
# returns 1 for a `first` anchor (skip it, and reach the rotation) and 2 for a
# `rest` anchor (stop the walk). One anchor of each paced group is always
# visited first, so a walk started past its deadline still makes progress on
# both. After the walk, PACE_VISITED counts the paced anchors visited,
# PACE_FIRST_SKIPPED the `first` anchors the deadline left for the next pass,
# and PACE_RESUME_AT names the rest anchor the deadline stopped at, if it did.
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
  PACE_DEADLINE="${2:-}"
  PACE_VISITED=0
  PACE_FIRST_VISITED=0
  PACE_FIRST_SKIPPED=0
  PACE_REST_VISITED=0
  PACE_FINISHED=""
  PACE_RESUME_AT=""
  PACE_WARNED=0
}

_pace_record() { # <id>
  pace_note "$PACE_CURSOR" "$1" && return 0
  [ "$PACE_WARNED" = 1 ] \
    || echo "${PROG:-pace}: WARN cannot record progress in $PACE_CURSOR; the next pass starts the rotation over" >&2
  PACE_WARNED=1
  return 0
}

pace_visit() { # <first|rest|exempt> <anchor-id>
  case "$1" in
    exempt) return 0 ;;
    first)
      if [ "$PACE_FIRST_VISITED" -gt 0 ] && pace_spent "$PACE_DEADLINE"; then
        PACE_FIRST_SKIPPED=$((PACE_FIRST_SKIPPED + 1))
        return 1
      fi
      PACE_FIRST_VISITED=$((PACE_FIRST_VISITED + 1)) ;;
    *)
      if [ -n "$PACE_FINISHED" ]; then
        _pace_record "$PACE_FINISHED"
        PACE_FINISHED=""
      fi
      if [ "$PACE_REST_VISITED" -gt 0 ] && pace_spent "$PACE_DEADLINE"; then
        # shellcheck disable=SC2034 # read by the arm that sourced this file
        PACE_RESUME_AT="$2"
        return 2
      fi
      PACE_REST_VISITED=$((PACE_REST_VISITED + 1))
      PACE_FINISHED="$2" ;;
  esac
  PACE_VISITED=$((PACE_VISITED + 1))
  return 0
}

pace_end() {
  [ -n "$PACE_FINISHED" ] && _pace_record "$PACE_FINISHED"
  PACE_FINISHED=""
  return 0
}
