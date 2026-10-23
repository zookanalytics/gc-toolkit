#!/usr/bin/env bash
# hold-lib.sh — the single definition of a hold: whether a bead's work is held,
# and by which blocker. Sourced, never executed.
#
# A bead is held when it, or one of its parent-child ancestors, has a `blocks`
# edge onto a bead that is still open. A park and a prerequisite hold the same
# way, so nothing here tells them apart. One kind of blocker is the exception: a
# human gate on an ancestor does not hold the bead, because the operator ruled
# that waiting on their decision is not a hold. A human gate is a bead of type
# `gate` whose await type is `human`, whoever filed it (human-gate.sh, or the
# native `bd gate create --type=human`). A human gate on the bead itself still
# holds it. A conversation holds nothing, since it links to its subject by a
# `tracks` edge.
#
# Where bd's own cascade decides the same question, this follows it: a blocker
# that is closed or pinned holds nothing, and an ancestor that is closed or
# pinned neither holds the bead nor passes on a hold from further up.
#
# A hold holds work that has not started. A bead whose work has started is in
# flight: it carries a branch, a merge_result or a rejection_reason. A hold on
# an ancestor leaves it running, so only a blocker on the bead itself holds it,
# and an armed re-dispatch of work already begun fires under a parked epic.
#
# A read that fails fails the whole walk, and the caller then treats every bead
# it was for as unread, never as free. A read that answers without an id it was
# asked for says this store holds no such bead: one in another store, or one
# deleted. What that means depends on where the edge sits.
#   * A hold on an ancestor reaches the bead only through bd's cascade, which
#     passes a hold down from an ancestor row this store holds. So an ancestor
#     the store does not return, or a blocker it does not return on an
#     ancestor, holds nothing and passes nothing down, as in bd.
#   * A blocker on the bead itself is the bead's own sequencing. One the store
#     does not return holds the bead, marked unread so a reader can say so: the
#     walk cannot tell whether it is open, and a dispatch on a guess is what an
#     arm exists to prevent.
# An ancestor past HOLD_MAX_DEPTH is never asked for, so it holds the bead as
# unread too.
#
# Readers: deferred-dispatch.sh slings an armed bead only when nothing holds it,
# and its `list` and pass log name the blocker that does.
# doctor/check-armed-dispatch-owed counts no held arm as owed. hold-lib.test.sh
# fails when a reader stops sourcing this file or defines the predicate itself,
# and it runs the predicate over hold-lib.fixture.json, the cases a copy of it
# in another language must agree with.
#
# A caller sources it beside itself:
#   # shellcheck source=hold-lib.sh
#   . "$SCRIPTS_DIR/hold-lib.sh" || { echo "$PROG: cannot source hold-lib.sh" >&2; exit 1; }
# then builds the graph the predicate reads, and applies the defs the way the
# in-variable jq convention does (dispatch-path.sh):
#   hold_graph <reader> <seed-file> <graph-file>
#   jq -r --slurpfile g <graph-file> "$HOLD_JQ"' .[] | hold_summary($g[0]) ' <seed-file>
# A program built in a double-quoted string expands the variable in place.

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# How many generations of ancestors the walk reads. An ancestor past it is
# never asked for, so it holds the bead as an unread one does.
HOLD_MAX_DEPTH=16

# shellcheck disable=SC2016,SC2034  # jq source, its $names are jq's; read by the scripts that source this file
HOLD_JQ='
  # The edges a bead carries, as {to, type}, from either shape bd prints them
  # in: a listing gives {depends_on_id, type}, a show gives {id, dependency_type}.
  def hold_edges:
    [ (.dependencies // [])[]? | objects
      | if has("depends_on_id") then {to: (.depends_on_id // ""), type: (.type // "")}
        else {to: (.id // ""), type: (.dependency_type // .type // "")} end
      | {to: (.to | tostring), type: (.type | tostring)}
      | select(.to != "") ];
  def hold_parent_ids: [ hold_edges[] | select(.type == "parent-child") | .to ] | unique;
  def hold_blocker_ids: [ hold_edges[] | select(.type == "blocks") | .to ] | unique;
  # Closed or pinned. bd counts neither as a blocker, and its cascade stops at either.
  def hold_done: ((.status // "") | tostring) as $s | ($s == "closed" or $s == "pinned");
  # A human gate: a pending operator decision, which blocks the bead it gates.
  def hold_is_human_gate:
    ((.issue_type // "") | tostring) == "gate" and ((.await_type // "") | tostring) == "human";
  # Why the bead is in flight, as a reader prints it, or "" when it is not.
  def hold_flight_why:
    (.metadata // {}) | if type == "object" then
      (if ((.merge_result // "") | tostring) != "" then "merge_result=\(.merge_result | tostring)"
       elif ((.rejection_reason // "") | tostring) != "" then "rejection_reason set"
       elif ((.branch // "") | tostring) != "" then "branch \(.branch | tostring)"
       else "" end) | gsub("[[:cntrl:]]"; " ")
    else "" end;
  def hold_in_flight: hold_flight_why != "";
  # An id the walk asked for and the store did not return. An id never asked
  # for is not absent, only unread.
  def hold_absent($g; $id): ($g | has($id)) and $g[$id] == null;

  # The beads whose blockers can hold this one, nearest first: the bead itself,
  # then each ancestor over $g (an object keyed by bead id, null for an id that
  # was asked for and not found), as {id, bead, ancestor}, where bead is null
  # for an ancestor the walk has no row for. A done ancestor, or one with no
  # row, ends its line of the walk, and a bead in flight has no ancestor to walk.
  def hold_chain($g):
    def up($ids; $seen):
      if ($ids | length) == 0 then empty
      else
        ($ids[] | {id: ., bead: ($g[.] // null), ancestor: true}),
        (( [ $ids[] | ($g[.] // null) | select(. != null) | select(hold_done | not) | hold_parent_ids[] ]
           | unique | map(select(. as $i | $seen | index($i) | not)) ) as $next
         | up($next; $seen + $next))
      end;
    ((.id // "") | tostring) as $self
    | {id: $self, bead: ., ancestor: false},
      (if hold_in_flight then empty else (hold_parent_ids as $p | up($p; $p + [$self])) end);

  # The ids the walk reads next, comma-joined: first the ancestors the seed
  # beads walk to that $g does not hold yet, generation by generation, so an
  # ancestor nothing walks to is never read; then, once no ancestor is left,
  # every blocker on the beads $g holds.
  def hold_unread_ancestors($g):
    [ .[]? | objects | hold_chain($g) | select(.ancestor and .bead == null) | .id
      | select(. as $i | $g | has($i) | not) ] | unique | join(",");
  def hold_unread_blockers:
    . as $g | [ .[] | select(. != null) | hold_blocker_ids[]
                | select(. as $i | $g | has($i) | not) ] | unique | join(",");

  # What holds this bead over $g, nearest first, one entry per blocker:
  # {by, title, on, unread}. by is the blocker, on is the bead whose edge it
  # sits on, and unread marks one with no row: a blocker on the bead itself
  # that the store did not return, or an ancestor past the depth cap, which is
  # its own entry with by and on both naming it. An absent ancestor, and an
  # absent blocker on an ancestor, hold nothing.
  def hold_holds($g):
    [ hold_chain($g) as $c
      | if $c.bead == null then
          (if hold_absent($g; $c.id) then empty else {by: $c.id, title: "", on: $c.id, unread: true} end)
        elif $c.ancestor and ($c.bead | hold_done) then empty
        else
          ($c.bead | hold_blocker_ids[]) as $x | ($g[$x] // null) as $t
          | if $t == null then
              (if $c.ancestor and hold_absent($g; $x) then empty else {by: $x, title: "", on: $c.id, unread: true} end)
            elif ($t | hold_done) then empty
            elif $c.ancestor and ($t | hold_is_human_gate) then empty
            else {by: $x, title: (($t.title // "") | tostring), on: $c.id, unread: false} end
        end ]
    | reduce .[] as $h ([]; if any(.[]; .by == $h.by) then . else . + [$h] end);
  def hold_held($g): (hold_holds($g) | length) > 0;

  # One hold as a reader prints it, for the bead whose id is $self.
  def hold_label($self):
    (if .unread and .by == .on and .on != $self then "ancestor \(.by) (unreadable)"
     else
       (if .unread then "\(.by) (unreadable)" elif .title != "" then "\(.by) \"\(.title)\"" else .by end)
       + (if .on != $self then " on ancestor \(.on)" else "" end)
     end) | gsub("[[:cntrl:]]"; " ");
  # Every hold on this bead in one line: the nearest, then how many more. Empty
  # when nothing holds it.
  def hold_summary($g):
    ((.id // "") | tostring) as $self | hold_holds($g) as $h
    | if ($h | length) == 0 then ""
      else ($h[0] | hold_label($self))
           + (if ($h | length) > 1 then " (+\(($h | length) - 1) more)" else "" end) end;

  # When the last hold on this bead released: the latest close among the
  # blockers on it and, unless it is in flight, on its ancestors. A human gate
  # on an ancestor never held it, so its close does not count. Null when none
  # has closed.
  def hold_released_at($g):
    [ hold_chain($g) as $c
      | select($c.bead != null)
      | select(($c.ancestor | not) or ($c.bead | hold_done | not))
      | ($c.bead | hold_blocker_ids[]) as $x | ($g[$x] // null) as $t
      | select($t != null)
      | select((($t.status // "") | tostring) == "closed")
      | select(($c.ancestor and ($t | hold_is_human_gate)) | not)
      | (($t.closed_at // "") | tostring) | select(. != "") ] | max;
'

# hold_graph <reader> <seed-file> <graph-file> — read everything the predicate
# needs about the beads in <seed-file>, a JSON array of them in the shape `bd
# list --json` prints (each with its own `dependencies`), into <graph-file>, an
# object keyed by bead id. <reader> is a command the caller defines: given a
# comma-joined list of ids, it prints those beads as a JSON array from the
# caller's own store, at every status and of every class bd hides by default
# (--all --include-gates --include-infra --include-templates), and exits
# non-zero when the read fails. An id it does not return is recorded as null,
# which the predicate reads as absent from the store.
#
# The ancestors the seed beads walk to are read first, one read per generation,
# and then every blocker on the seed beads and those ancestors in one more read.
# So the reads grow with the depth of the tree, never with the number of beads,
# and a bead in flight costs no ancestor read. Returns non-zero when a read
# fails or does not parse, and the caller then treats every seed bead as unread
# rather than as free.
hold_graph() {
    local reader="$1" seed="$2" out="$3" want level=0
    jq -c '[ .[]? | objects | select(((.id // "") | tostring) != "") | {key: (.id | tostring), value: .} ] | from_entries' \
        "$seed" > "$out" 2>/dev/null || return 1
    [ -s "$out" ] || return 1
    while :; do
        want="$(jq -r --slurpfile g "$out" "$HOLD_JQ"'hold_unread_ancestors($g[0])' "$seed" 2>/dev/null)" || return 1
        [ -n "$want" ] || break
        [ "$level" -lt "$HOLD_MAX_DEPTH" ] || break
        level=$((level + 1))
        hold_graph_read "$reader" "$want" "$out" || return 1
    done
    want="$(jq -r "$HOLD_JQ"'hold_unread_blockers' "$out" 2>/dev/null)" || return 1
    [ -z "$want" ] || hold_graph_read "$reader" "$want" "$out" || return 1
    return 0
}

# hold_graph_read <reader> <ids-csv> <graph-file> — one read, merged into the
# graph, with each asked-for id the read did not return recorded as null.
hold_graph_read() {
    local reader="$1" want="$2" out="$3" raw next
    raw="$("$reader" "$want" </dev/null)" || return 1
    raw="$(printf '%s' "$raw" | scrub)"
    printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    next="$(printf '%s' "$raw" | jq -c --slurpfile g "$out" --arg want "$want" '
        reduce (.[] | objects | select(((.id // "") | tostring) != "")) as $b ($g[0]; .[$b.id | tostring] = $b)
        | reduce ($want | split(",")[] | select(length > 0)) as $w (.; if has($w) then . else .[$w] = null end)' 2>/dev/null)" || return 1
    [ -n "$next" ] || return 1
    printf '%s\n' "$next" > "$out"
}
