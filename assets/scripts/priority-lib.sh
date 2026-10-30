#!/usr/bin/env bash
# priority-lib.sh — the single definition of a bead's priority: the priority it
# competes at in a pool's queue, and how that priority is derived. Sourced,
# never executed.
#
# A bead's priority is the priority of the bead it follows, plus its own shift,
# kept within P0 to P4 at each level. What a bead follows:
#   * A workflow's input convoy, root and steps follow the bead the workflow was
#     poured for, at shift 0. A step follows its root (gc.root_bead_id), a root
#     its input convoy (gc.input_convoy_id), and an input convoy (gc.synthetic,
#     tracking exactly one bead) the bead it tracks.
#   * PR-finishing work, a bead carrying anchor_bead, follows its anchor. Once
#     the anchor's PR is approved, it runs at P0 whatever its shift. A PR is
#     approved when its anchor rests in pull_request (merge_result) and the
#     posture pr-facts.sh records there (pr_posture, stored as
#     <posture>@<oid>@<since>) reads approved before its first @, at the head
#     pr-facts.sh last read for the PR (pr_head_oid, the posture's <oid>). An
#     approval recorded at any other head is for code the PR no longer
#     carries. An anchor that rests anywhere else has no open PR to be
#     approved, whatever posture an earlier PR left on it, and leaving
#     pull_request clears pr_head_oid (lifecycle.toml exit_sets), so an anchor
#     that returns reads no approval until pr-facts.sh has read its PR again.
#   * A member follows its parent, and the most urgent one, the lowest
#     P-number, when it has several.
#   * A bead that follows nothing has its priority set directly: its bd
#     priority field is its own input.
# A bead is followed only when the store holds it and it is neither closed nor
# pinned, the two statuses bd's cascade stops at. A bead whose only candidates
# are closed, pinned or absent from the store follows nothing.
#
# The shift is the signed integer in priority_shift: +1 is one level later, -1
# is one level sooner, and absent or empty reads as 0. A workflow's convoy, root
# and steps carry no shift, and a bead that follows nothing has nothing to shift
# from, so neither reads one. A shift that is not a signed integer makes its
# bead unreadable, and so every bead that follows it: no priority is computed
# from a guess.
#
# The bd priority field holds the priority a bead competes at, because a pool's
# claim reads it and a pour copies it once. So a bead that follows something
# takes its priority from what it follows and its shift, never from its own
# field, and a hand edit of that field is overwritten at its next computation.
#
# Readers: queue-priority.sh settles a bead (settle), re-ranks the work that
# follows a moved bead (move, which `gc-helm.sh priority` runs), and re-settles
# the polecat queue (reconcile). pr-facts.sh reads prio_pr_approved alone, for
# the rank an anchor's PR-finishing work follows, which it settles that work to
# and records on the anchor. priority-lib.test.sh runs the function over
# priority-lib.fixture.json, the cases a copy of it in another language must
# agree with, and fails when another file defines it.
#
# A caller sources it beside itself:
#   # shellcheck source=priority-lib.sh
#   . "$SCRIPTS_DIR/priority-lib.sh" || { echo "$PROG: cannot source priority-lib.sh" >&2; exit 1; }
# then builds the graph the function reads, and applies the defs the way the
# in-variable jq convention does (dispatch-path.sh):
#   priority_graph <reader> <seed-file> <graph-file>
#   jq -c --slurpfile g <graph-file> "$PRIORITY_JQ"' .[] | priority_of($g[0]) ' <seed-file>

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# How many levels a priority is followed up, and how many generations of
# followed beads the walk reads. A bead whose chain runs past it is unreadable.
PRIORITY_MAX_DEPTH=16

# shellcheck disable=SC2016,SC2034  # jq source, its $names are jq's; read by the scripts that source this file
PRIORITY_JQ='
  def prio_meta: (.metadata // {}) | if type == "object" then . else {} end;
  def prio_str($k): ((prio_meta[$k] // "") | tostring | gsub("^[[:space:]]+|[[:space:]]+$"; ""));
  # The edges a bead carries, as {to, type}, from either shape bd prints them
  # in: a listing gives {depends_on_id, type}, a show gives {id, dependency_type}.
  def prio_edges:
    [ (.dependencies // [])[]? | objects
      | if has("depends_on_id") then {to: (.depends_on_id // ""), type: (.type // "")}
        else {to: (.id // ""), type: (.dependency_type // .type // "")} end
      | {to: (.to | tostring), type: (.type | tostring)}
      | select(.to != "") ];
  # Closed or pinned: never followed, never written.
  def prio_live: ((.status // "") | tostring) as $s | ($s != "closed" and $s != "pinned");
  def prio_clamp: if . < 0 then 0 elif . > 4 then 4 else . end;
  # The bead its own field says, or null when the field is not a number.
  def prio_own:
    (.priority // null) as $p
    | (if ($p | type) == "number" then $p
       else (($p // "") | tostring | if test("^[0-9]+$") then tonumber else null end) end)
    | if . == null then null else (floor | prio_clamp) end;
  # The shift, as {ok, n}, or {ok: false, raw} for a value that is not a
  # signed integer.
  def prio_shift:
    (prio_meta.priority_shift // null) as $v
    | if $v == null then {ok: true, n: 0}
      else ($v | tostring | gsub("^[[:space:]]+|[[:space:]]+$"; "")) as $s
        | if $s == "" then {ok: true, n: 0}
          elif ($s | test("^[+-]?[0-9]+$")) then {ok: true, n: ($s | ltrimstr("+") | tonumber)}
          else {ok: false, raw: $s} end end;
  # Whether the PR of this anchor is approved, which ranks its PR-finishing work
  # at P0: it rests in pull_request, and the dated posture pr-facts.sh records
  # on it reads approved before its first @, at the oid after it, which is the
  # head pr-facts.sh last read for the PR (pr_head_oid).
  def prio_pr_approved:
    (prio_str("pr_posture") | split("@")) as $p
    | prio_str("merge_result") == "pull_request"
      and ($p[0] // "") == "approved"
      and ($p[1] // "") != ""
      and ($p[1] // "") == prio_str("pr_head_oid");

  # What this bead can follow: {kind, on}, where kind is workflow, anchor,
  # parent or none, and on lists the beads it could follow. priority_of
  # decides which of them it does follow.
  def prio_follows:
    ((.id // "") | tostring) as $self
    | prio_str("gc.root_bead_id") as $root
    | prio_str("gc.input_convoy_id") as $convoy
    | prio_str("anchor_bead") as $anchor
    | [ prio_edges[] | select(.type == "tracks") | .to ] as $tracked
    | ([ prio_edges[] | select(.type == "parent-child") | .to ]
       + (if ((.parent // "") | tostring) != "" then [(.parent | tostring)] else [] end)) as $parents
    | if $root != "" and $root != $self then {kind: "workflow", on: [$root]}
      elif prio_str("gc.kind") == "workflow" and $convoy != "" and $convoy != $self then {kind: "workflow", on: [$convoy]}
      elif ((.issue_type // "") | tostring) == "convoy" and (prio_str("gc.synthetic") | ascii_downcase) == "true"
           and ($tracked | unique | length) == 1 and $tracked[0] != $self then {kind: "workflow", on: [$tracked[0]]}
      elif $anchor != "" and $anchor != $self then {kind: "anchor", on: [$anchor]}
      else ($parents | unique | map(select(. != $self))) as $p
        | if ($p | length) > 0 then {kind: "parent", on: $p} else {kind: "none", on: []} end
      end;

  # The priority of this bead over $g, an object keyed by bead id (null for an id
  # the walk asked for and the store did not return):
  #   {id, priority, kind, via, base, shift, approved}
  # where kind is what it follows (workflow, anchor, parent, or none), via the
  # bead it follows, base the priority of that bead, shift its own shift, and
  # approved true when the bead is PR-finishing work whose anchor has an
  # approved PR, which puts it at P0 whatever base and shift say. A
  # bead that cannot be computed answers {id, error} instead: a followed bead
  # the walk has not read, a chain deeper than PRIORITY_MAX_DEPTH or one that
  # comes back to itself, a shift that is not a signed integer, or a priority
  # field that is not a number on a bead that follows nothing. An error names
  # the bead where the chain broke (at) and why (reason), so a bead that follows
  # an unreadable one says what to fix.
  def priority_of($g):
    def fault($id; $why): {id: $id, error: $why, at: $id, reason: $why};
    def calc($seen):
      ((.id // "") | tostring) as $id
      | if ($seen | index($id)) != null then fault($id; "its chain comes back to \($id)")
        elif ($seen | length) >= prio_depth then fault($id; "its chain is deeper than \(prio_depth) levels")
        else prio_follows as $f
          | [ $f.on[] | select(. as $x | $g | has($x) | not) ] as $unread
          | if ($unread | length) > 0 then fault($id; "\($unread | join(", ")) not read")
            else [ $f.on[] | ($g[.] // null) | select(. != null) | select(prio_live) ] as $cands
              | if ($cands | length) == 0 then
                  prio_own as $p
                  | if $p == null then fault($id; "its priority field is not a number")
                    else {id: $id, priority: $p, kind: "none", via: null, base: null, shift: 0, approved: false} end
                else
                  [ $cands[] | calc($seen + [$id]) ] as $rs
                  | ([ $rs[] | select(has("error")) ] | first) as $bad
                  | if $bad != null then
                      {id: $id, error: "follows \($bad.id), which is unreadable (\($bad.at): \($bad.reason))",
                       at: $bad.at, reason: $bad.reason}
                    else ($rs | sort_by(.priority, .id) | first) as $best
                      | (if $f.kind == "workflow" then {ok: true, n: 0} else prio_shift end) as $s
                      | ($f.kind == "anchor" and ($g[$best.id] | prio_pr_approved)) as $ap
                      | if ($s.ok | not) then fault($id; "its priority_shift is \"\($s.raw)\", not a signed integer")
                        else {id: $id, priority: (if $ap then 0 else (($best.priority + $s.n) | prio_clamp) end),
                              kind: $f.kind, via: $best.id, base: $best.priority, shift: $s.n, approved: $ap} end
                    end
                end
            end
        end;
    calc([]);

  # The rows of the chain of a workflow bead over $g, from the bead itself up to
  # the bead it was poured for, which comes last. A bead that is not a workflow
  # bead is its own subject, so its chain is itself alone. A chain that leaves
  # the graph ends at the last bead it reached.
  def priority_chain($g):
    def up($seen):
      ((.id // "") | tostring) as $id
      | if ($seen | index($id)) != null or ($seen | length) >= prio_depth then [.]
        else prio_follows as $f
          | if $f.kind != "workflow" then [.]
            else ($g[$f.on[0]] // null) as $n
              | if $n == null or ($n | prio_live | not) then [.] else [.] + ($n | up($seen + [$id])) end
            end
        end;
    up([]);

  # The bead a workflow bead was poured for, or the bead itself when it is not a
  # workflow bead: the last bead of its chain.
  def priority_subject($g): priority_chain($g) | last;

  # Every bead in $g that could follow each bead, as {<id>: [<follower id>...]},
  # over the beads that are neither closed nor pinned: the index a writer walks
  # down from a moved bead to everything that follows it.
  def priority_followers($g):
    reduce ($g[] | select(. != null) | select(prio_live)) as $r ({};
      (($r.id // "") | tostring) as $id
      | reduce ($r | prio_follows | .on[]) as $o (.; .[$o] = ((.[$o] // []) + [$id])));

  # The ids the walk reads next, comma-joined: the beads the seed beads follow,
  # generation by generation through the beads $g already holds, that $g does
  # not hold yet. A closed or pinned bead is not followed, so the walk stops at
  # one.
  def priority_unread($g):
    def reach($ids; $seen):
      if ($ids | length) == 0 then empty
      else
        ($ids[] | select(. as $i | $g | has($i) | not)),
        ([ $ids[] | ($g[.] // null) | select(. != null) | select(prio_live) | prio_follows.on[] ]
         | unique | map(select(. as $x | $seen | index($x) | not))) as $next
        | reach($next; $seen + $next)
      end;
    [ .[]? | objects | ((.id // "") | tostring) as $id | prio_follows.on as $on
      | reach($on; $on + [$id]) ] | unique | join(",");
'
# The depth cap reaches the program as a jq def, so the number lives once.
PRIORITY_JQ="def prio_depth: $PRIORITY_MAX_DEPTH;$PRIORITY_JQ"

# priority_graph <reader> <seed-file> <graph-file> — read everything the
# function needs about the beads in <seed-file>, a JSON array of them in the
# shape `bd list --json` prints (each with its own `dependencies` and metadata),
# into <graph-file>, an object keyed by bead id. <reader> is a command the caller
# defines: given a comma-joined list of ids, it prints those beads as a JSON
# array from the caller's own store, at every status (--all) and of every class
# a listing hides by default (gates, infrastructure beads, template molecules
# and ephemeral rows), and exits non-zero when the read fails. An id it does not
# return is recorded as null, which the function reads as absent from the
# store, so a reader that hides a class computes every bead that follows one of
# that class as following something else, or nothing.
#
# The beads the seed beads follow are read one generation per read, so the reads
# grow with the depth of the chains, never with the number of beads. Returns
# non-zero when a read fails or does not parse, and the caller then treats every
# seed bead as unreadable.
priority_graph() {
    local reader="$1" seed="$2" out="$3" want level=0
    jq -c '[ .[]? | objects | select(((.id // "") | tostring) != "") | {key: (.id | tostring), value: .} ] | from_entries' \
        "$seed" > "$out" 2>/dev/null || return 1
    [ -s "$out" ] || return 1
    while :; do
        want="$(jq -r --slurpfile g "$out" "$PRIORITY_JQ"'priority_unread($g[0])' "$seed" 2>/dev/null)" || return 1
        [ -n "$want" ] || break
        [ "$level" -lt "$PRIORITY_MAX_DEPTH" ] || break
        level=$((level + 1))
        priority_graph_read "$reader" "$want" "$out" || return 1
    done
    return 0
}

# priority_graph_read <reader> <ids-csv> <graph-file> — one read, merged into
# the graph, with each asked-for id the read did not return recorded as null.
priority_graph_read() {
    local reader="$1" want="$2" out="$3" raw next
    raw="$("$reader" "$want" </dev/null)" || return 1
    raw="$(printf '%s' "$raw" | scrub)"
    printf '%s' "$raw" | jq -e 'if type == "object" then ((.issues // null) | type) == "array" else type == "array" end' >/dev/null 2>&1 || return 1
    next="$(printf '%s' "$raw" | jq -c --slurpfile g "$out" --arg want "$want" '
        (if type == "object" then .issues else . end) as $rows
        | reduce ($rows[] | objects | select(((.id // "") | tostring) != "")) as $b ($g[0]; .[$b.id | tostring] = $b)
        | reduce ($want | split(",")[] | select(length > 0)) as $w (.; if has($w) then . else .[$w] = null end)' 2>/dev/null)" || return 1
    [ -n "$next" ] || return 1
    printf '%s\n' "$next" > "$out"
}
