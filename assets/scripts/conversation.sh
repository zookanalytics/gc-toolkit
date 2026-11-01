#!/usr/bin/env bash
# conversation.sh — the single definition of a conversation's shape
# (specs/tk-0ur8r9p/design.md section 1). A conversation is an ordinary task
# that tracks the one bead it is about. It is assigned to `human` while it
# waits in the operator's queue, and to its sitting's alias while a sitting
# holds it. That alias names the task's own id, or its `c-` fallback when the
# runtime refuses the bare id, and a claim records it qualified by the
# session's rig and template binding (`<rig>/<binding>.<alias>`), so a held
# conversation is known by its assignee alone, even once its session has
# closed. Work a person owes is assigned to that person and tracks nothing,
# so the shape tells the two apart.
#
# Sourced (never executed). Two forms of the one rule:
#   $CONVERSATION_JQ        jq defs, the in-variable convention (standing-kinds.sh):
#                           prepend them and call
#                             conversation_alias     the assignee is the alias that
#                                                    names the task's own id
#                             conversation_subjects  the beads its tracks edges name
#                             conversation           the whole shape, on a bd list row
#   conversation_assignee   the same assignee rule in shell, for a reader that
#                           holds one bead's fields rather than a listing:
#                             conversation_assignee <assignee> <bead-id>
# conversation.test.sh runs both over one set of assignees, so they cannot
# drift apart.
# shellcheck disable=SC2034  # read by the scripts that source this file
CONVERSATION_JQ='
  def conversation_alias:
    (.id // "") as $id | ((.assignee // "") | tostring) as $a
    | $id != "" and any(($id, "c-" + $id); . as $n
        | $a == $n or ($a | endswith("/" + $n)) or ($a | endswith("." + $n)));
  def conversation_subjects:
    [ .dependencies[]? | select((.type // "") == "tracks") | (.depends_on_id // empty) ];
  def conversation:
    (.issue_type // "") == "task"
    and ((((.assignee // "") | tostring) == "human") or conversation_alias)
    and (conversation_subjects | length) == 1;
'

# conversation_assignee <assignee> <bead-id> — 0 when <assignee> is one a
# conversation carries: `human`, or the alias that names <bead-id>.
conversation_assignee() {
  local a="${1:-}" id="${2:-}"
  [ -n "$a" ] && [ -n "$id" ] || return 1
  case "$a" in
    human|"$id"|"c-$id"|*/"$id"|*/"c-$id"|*."$id"|*."c-$id") return 0 ;;
  esac
  return 1
}
