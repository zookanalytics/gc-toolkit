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
#                                 absent or empty cursor starts at the lowest id;
#                                 a reorder that fails writes the rows unchanged.
#   pace_note <cursor-file> <id>  Record <id> as the last anchor finished. An
#                                 empty cursor path records nothing. Non-zero
#                                 when the write failed.
#   pace_spent <deadline>         True once the clock reaches <deadline> (epoch
#                                 seconds). An empty deadline is never spent.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=pace-lib.sh
#   . "$SCRIPTS_DIR/pace-lib.sh" || { echo "$PROG: cannot source pace-lib.sh" >&2; exit 1; }

pace_order() { # <cursor-file>; rows on stdin
  local after="" rows ordered
  rows=$(cat)
  if [ -n "${1:-}" ] && [ -r "$1" ]; then
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
