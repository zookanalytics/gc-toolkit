#!/usr/bin/env bash
# hold-lib.sh — the single definition of a hold: whether a bead's work is held,
# and by which blocker. Sourced, never executed.
#
# A bead is held when it, or one of its parent-child ancestors, has a `blocks`
# edge onto a bead that is still open. A park and a prerequisite hold the same
# way, so nothing here tells them apart. One kind of blocker is the exception: a
# demand gate on an ancestor does not hold the bead, because the operator ruled
# that waiting on their decision is not a hold. A demand gate is the gate
# `gc-helm.sh demand` files, and it names the bead it gates in `gc.demand_for`.
# A demand gate on the bead itself still holds it. A visit holds nothing, since
# it links to its subject by a `tracks` edge.
#
# Where bd's own cascade decides the same question, this follows it: a blocker
# that is closed or pinned holds nothing, and an ancestor that is closed or
# pinned neither holds the bead nor passes on a hold from further up.
#
# The predicate fails closed. An ancestor or a blocker the walk cannot read
# holds the bead, marked unread so a reader can say so.
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
# never read, so it holds the bead as an unread one does.
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
  # A demand gate: filed for a pending operator decision, naming the bead it gates.
  def hold_is_demand_gate:
    (.metadata // {}) | if type == "object" then ((.["gc.demand_for"] // "") | tostring | test("[^[:space:]]")) else false end;

  # Over a graph (an object keyed by bead id, null for an id that was asked for
  # and not found): the ids the walk reads next, comma-joined. The ancestors come
  # first, generation by generation, and the blockers once no ancestor is left.
  def hold_unread_parents:
    . as $g | [ .[] | select(. != null) | select(hold_done | not) | hold_parent_ids[]
                | select(. as $i | $g | has($i) | not) ] | unique | join(",");
  def hold_unread_blockers:
    . as $g | [ .[] | select(. != null) | hold_blocker_ids[]
                | select(. as $i | $g | has($i) | not) ] | unique | join(",");

  # The beads whose blockers can hold this one, nearest first: the bead itself,
  # then each ancestor over $g, as {id, bead, ancestor}, where bead is null for
  # an ancestor the walk could not read. A done ancestor ends its line of the walk.
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
      (hold_parent_ids as $p | up($p; $p + [$self]));

  # What holds this bead over $g, nearest first, one entry per blocker:
  # {by, title, on, unread}. by is the blocker, on is the bead whose edge it
  # sits on, and unread marks one the walk could not read. An unread ancestor
  # is its own entry, with by and on both naming it.
  def hold_holds($g):
    [ hold_chain($g) as $c
      | if $c.bead == null then {by: $c.id, title: "", on: $c.id, unread: true}
        elif $c.ancestor and ($c.bead | hold_done) then empty
        else
          ($c.bead | hold_blocker_ids[]) as $x | ($g[$x] // null) as $t
          | if $t == null then {by: $x, title: "", on: $c.id, unread: true}
            elif ($t | hold_done) then empty
            elif $c.ancestor and ($t | hold_is_demand_gate) then empty
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
  # blockers on it and on its ancestors. A demand gate on an ancestor never held
  # it, so its close does not count. Null when none has closed.
  def hold_released_at($g):
    [ hold_chain($g) as $c
      | select($c.bead != null)
      | select(($c.ancestor | not) or ($c.bead | hold_done | not))
      | ($c.bead | hold_blocker_ids[]) as $x | ($g[$x] // null) as $t
      | select($t != null)
      | select((($t.status // "") | tostring) == "closed")
      | select(($c.ancestor and ($t | hold_is_demand_gate)) | not)
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
# which the predicate reads as unread.
#
# The ancestors are read first, one read per generation, and then every blocker
# on the seed beads and their ancestors in one more read. So the reads grow with
# the depth of the tree, never with the number of beads. Returns non-zero when a
# read fails or does not parse, and the caller then treats every seed bead as
# unread rather than as free.
hold_graph() {
    local reader="$1" seed="$2" out="$3" want level=0
    jq -c '[ .[]? | objects | select(((.id // "") | tostring) != "") | {key: (.id | tostring), value: .} ] | from_entries' \
        "$seed" > "$out" 2>/dev/null || return 1
    [ -s "$out" ] || return 1
    while :; do
        want="$(jq -r "$HOLD_JQ"'hold_unread_parents' "$out" 2>/dev/null)" || return 1
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
