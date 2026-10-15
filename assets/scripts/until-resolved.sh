#!/usr/bin/env bash
# until-resolved.sh — whether an `until` edge has resolved its bead, read and
# decided in one place. An `until` edge says "X resolves me", where a `blocks`
# edge says "X must land before me". A bead is owed a disposal once it is open
# and unassigned, every one of its `until` targets has closed, and no `blocks`
# blocker of its own is still open. It is disposed only when it also carries no
# live work, as live-work.sh (which this file sources) defines it.
#
# Sourced (never executed) by deferred-dispatch.sh, whose reconcile pass
# disposes an owed bead through bead-rehome, and by
# doctor/check-until-resolved-owed, which reports an owed bead that pass has
# left undisposed. Both select, decide and re-read through the two functions
# below, so the doctor reports what the pass does. until-resolved.test.sh
# fails when either stops sourcing this file or another file defines these
# names of its own.
#
# Each function takes, as its first argument, the command that reads the
# caller's store: a function that runs `gc bd` against that one store, with the
# pinning and time bound the caller needs, given bd's own arguments.
#
# until_scan <reader>
#   One listing of the store, then one status read of every bead the
#   candidates' edges name, decided per candidate in one jq pass. A candidate
#   is an OPEN, UNASSIGNED bead with at least one `until` edge: any other
#   status is a deliberate hold, and an assignee is a live worker. Prints one
#   TAB-separated row per candidate:
#     id  state  successor  owed-since  until-targets  blocks-blockers  detail  marks
#   state is one of:
#     waiting     an `until` target is not closed (detail: those targets)
#     unresolved  an edge names a bead the status read did not return, such as
#                 one in another store, so the bead cannot be decided (detail:
#                 those ids)
#     blocked     every `until` target has closed, but a `blocks` blocker is
#                 not closed (detail: those blockers)
#     owed        every `until` target has closed, and no `blocks` blocker is
#                 open
#   For an owed bead, successor is the `until` target that closed last, and
#   owed-since is when the bead became owed: the latest of its `until` targets'
#   closes, its `until` edges' creation, and its `blocks` blockers' closes.
#   marks are the live-work marks its listed row carries. An empty column is
#   "-": TAB is IFS whitespace, so an empty field would collapse and shift the
#   rest. Exit 1 when the listing fails or does not parse, and 2 when the status
#   read does. Either way nothing is printed, so an unread store never reads as
#   one with nothing owed.
#
# until_fresh <reader> <id> <successor>
#   The bead, every edge it has, and the beads that depend on it, as the store
#   holds them now. A caller reads them just before it acts, because a scan
#   ages while a pass runs. `bd show` gives each edge with its target's status,
#   but it leaves out an edge whose target has no row in this store, such as
#   one in another store or an external reference. The bead's `bd list` row
#   carries every edge it has, so the two reads together say which edges the
#   store cannot decide. Prints "<verdict>\t<detail>", where the verdict is
#   one of:
#     gone        the bead has no `until` edge to <successor> any more: someone
#                 removed the edge that made it owed, which is how a person
#                 keeps it
#     waiting     an `until` target is not closed (detail: those targets)
#     unresolved  an `until`, `blocks` or `parent-child` edge names a bead this
#                 store has no row for, so the bead cannot be decided (detail:
#                 those ids)
#     blocked     a `blocks` blocker is not closed (detail: those blockers)
#     live        the bead or its edges carry live work (detail: the marks)
#     clear       still owed, and nothing marks it live
#   Exit 1 when a read fails or does not parse.

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

until_scan() { # reader -> one row per candidate on stdout; exit 1 listing unreadable, 2 status read unreadable
    local reader="$1" listing cands ids statuses='[]'
    [ -n "${UNTIL_RESOLVED_JQ:-}" ] || return 1
    # An `until` edge carries no metadata key to scope on, so the listing is the
    # whole store; --brief keeps the status, assignee, issue type, metadata and
    # edges this reads, and drops the free-form text.
    listing="$("$reader" list --brief --json --limit 0 </dev/null 2>/dev/null)" || return 1
    [ -n "$listing" ] || return 1
    cands="$(printf '%s' "$listing" | scrub | jq -c "$UNTIL_RESOLVED_JQ"'
        if type == "array" then .[] | objects | until_candidate
        else error("the listing is not an array") end' 2>/dev/null)" || return 1
    [ -n "$cands" ] || return 0
    ids="$(printf '%s\n' "$cands" | jq -rs '[ .[] | (.until + .blocks)[] ] | unique | join(",")' 2>/dev/null)" || return 1
    if [ -n "$ids" ]; then
        # --all so a closed bead is returned; the include flags so a gate,
        # infra or template bead is not hidden and read as missing. --id drops
        # an id with no row, so a bead absent from the answer is unresolved,
        # never closed.
        statuses="$("$reader" list --id "$ids" --all --include-gates --include-infra --include-templates --brief --json --limit 0 </dev/null 2>/dev/null)" || return 2
        [ -n "$statuses" ] || return 2
    fi
    { printf '%s' "$statuses" | scrub; printf '\n'; printf '%s\n' "$cands"; } \
        | jq -rn "$UNTIL_RESOLVED_JQ"'(input | until_status_map) as $m | inputs | until_judge($m) | until_row' 2>/dev/null \
        || return 2
}

until_fresh() { # reader id successor -> "<verdict>\t<detail>" on stdout; exit 1 when a read fails or does not parse
    local reader="$1" id="$2" succ="$3" row listed up
    [ -n "${UNTIL_RESOLVED_JQ:-}" ] || return 1
    # `bd show` gives the bead's own edges with each target's status, and
    # `bd list --id` gives the bead's row with every edge it has, including one
    # whose target this store has no row for. The flags are the scan's status
    # read's, so the row comes back whatever the bead's status or class.
    # `bd dep list --direction=up` gives the beads that depend on it, because
    # `bd show` leaves a convoy's tracks edge out of its dependents.
    row="$("$reader" show "$id" --json </dev/null 2>/dev/null)" || return 1
    listed="$("$reader" list --id "$id" --all --include-gates --include-infra --include-templates --brief --json --limit 0 </dev/null 2>/dev/null)" || return 1
    up="$("$reader" dep list "$id" --direction=up --json </dev/null 2>/dev/null)" || return 1
    [ -n "$row" ] && [ -n "$listed" ] && [ -n "$up" ] || return 1
    { printf '%s' "$row" | scrub; printf '\n'; printf '%s' "$listed" | scrub; printf '\n'; printf '%s' "$up" | scrub; printf '\n'; } \
        | jq -rn --arg id "$id" --arg succ "$succ" "$UNTIL_RESOLVED_JQ"'
            input as $row | input as $listed | input as $up
            # `bd show` answers an array on a hit and an {"error": ...} object
            # on a miss, both at exit 0. `bd list --id` answers an array, with
            # no row for a bead the store does not hold.
            | ($row | if type == "array" then .[0]
                      elif type == "object" and (has("error") | not) then .
                      else null end) as $b
            | ($listed | if type == "array"
                         then [ .[] | objects | select(((.id // "") | tostring) == $id) ]
                              | if length == 1 then .[0] else null end
                         else null end) as $l
            | if ($b | type) == "object" and ($l | type) == "object" and ($up | type) == "array"
              then $b | until_fresh_verdict($l; $up; $succ)
              else error("unreadable") end' 2>/dev/null
}

UNTIL_RESOLVED_JQ=""
# shellcheck source=live-work.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/live-work.sh" 2>/dev/null || LIVE_WORK_JQ=""
if [ -n "${LIVE_WORK_JQ:-}" ]; then
    # Usage follows the in-variable jq convention (live-work.sh): prepend the
    # defs to a jq program. The live-work defs come first, because the decision
    # reads them.
    UNTIL_RESOLVED_JQ="$LIVE_WORK_JQ"'
  # One candidate from a row of `bd list --json`, whose .dependencies carry the
  # edges of the bead itself as {depends_on_id, type, created_at}. Empty for a
  # row that is not a candidate. An `until` edge whose target id is blank still
  # makes a candidate, and the decision reads it as unresolved.
  def until_candidate:
    def edges($t): [ (.dependencies // [])[]? | objects
                     | select(((.type // "") | tostring) == $t) ];
    def ids: [ .[] | ((.depends_on_id // "") | tostring) | select(length > 0) ] | unique;
    select(((.status // "") | tostring) == "open")
    | select(((.assignee // "") | tostring) == "")
    | edges("until") as $u
    | select(($u | length) > 0)
    | { id: ((.id // "") | tostring | gsub("[[:cntrl:]]"; " ")),
        until: ($u | ids),
        edged: ([ $u[] | ((.created_at // "") | tostring) | select(length > 0) ] | max // ""),
        blocks: (edges("blocks") | ids),
        marks: live_work_reasons };
  # $m for until_judge, from the array a status read (`bd list --id ... --json`)
  # returns: id -> {status, closed_at}.
  def until_status_map:
    if type != "array" then error("the status read is not an array") else . end
    | [ .[] | objects
        | { key: ((.id // "") | tostring),
            value: { status: ((.status // "") | tostring | ascii_downcase),
                     closed_at: ((.closed_at // "") | tostring) } } ]
    | from_entries;
  # One candidate, decided against $m. A target or blocker absent from $m was
  # not read, so it never counts as closed.
  def until_judge($m):
    def known: $m[.] != null;
    def closed: $m[.].status == "closed";
    . as $c
    | [ $c.until[] | select(known and (closed | not)) ] as $open_u
    | [ ($c.until + $c.blocks)[] | select(known | not) ] as $missing
    | [ $c.blocks[] | select(known and (closed | not)) ] as $open_b
    | if ($open_u | length) > 0 then $c + {state: "waiting", detail: $open_u}
      elif ($c.until | length) == 0 or ($missing | length) > 0 then $c + {state: "unresolved", detail: $missing}
      elif ($open_b | length) > 0 then $c + {state: "blocked", detail: $open_b}
      else $c + { state: "owed", detail: [],
                  succ: ([ $c.until[] | {id: ., at: $m[.].closed_at} ] | sort_by(.at) | last | .id),
                  since: ([ ($c.until[] | $m[.].closed_at), ($c.blocks[] | $m[.].closed_at), $c.edged ]
                          | map(select(. != "")) | max // "") }
      end;
  # A decided candidate as one TAB-separated row; an empty column is "-".
  def until_row:
    def col: if type == "array" then (if length == 0 then "-" else join(",") end)
             elif . == null or . == "" then "-"
             else tostring end;
    [ .id, .state, (.succ | col), (.since | col), (.until | col), (.blocks | col), (.detail | col),
      (if (.marks | length) == 0 then "-" else (.marks | join("; ")) end) ]
    | join("\t");
  # The verdict on a bead read fresh. Input: the bead row `bd show --json`
  # returns, whose .dependencies carry the status of each target and leave out
  # an edge whose target has no row in this store. $listed: the row of the same
  # bead from `bd list --json`, whose .dependencies carry every edge it has as
  # {depends_on_id, type}. $up: what `bd dep list <id> --direction=up --json`
  # returns. $succ: the successor the scan named. Once the edge to the
  # successor is found, the verdict is decided in the order until_judge decides
  # a candidate.
  def until_fresh_verdict($listed; $up; $succ):
    def etype: ((.dependency_type // .type // "") | tostring);
    def eid: ((.id // "") | tostring);
    def unclosed: (((.status // "") | tostring | ascii_downcase) != "closed");
    [ (.dependencies | if type == "array" then .[] else empty end) | objects ] as $d
    # Every edge the bead has, from either read, as {id, type}.
    | ([ $d[] | {id: eid, type: etype} ]
       + [ ($listed.dependencies | if type == "array" then .[] else empty end) | objects
           | {id: ((.depends_on_id // "") | tostring), type: ((.type // "") | tostring)} ]) as $all
    | ([ $d[] | {key: eid, value: true} ] | from_entries) as $shown
    | [ $all[] | select(.type == "until") | .id ] as $u
    | [ $d[] | select(etype == "until") | select(unclosed) | eid ] as $open_u
    # An edge `bd show` left out has no status to read. The verdict reads the
    # `until` and `blocks` targets, and live work reads the parent, whose type
    # says whether the bead is a member of a convoy.
    | ([ $all[] | select(.type == "until" or .type == "blocks" or .type == "parent-child")
         | .id | select(length > 0) | select($shown[.] | not) ] | unique) as $unseen
    | [ $d[] | select(etype == "blocks") | select(unclosed) | eid ] as $open_b
    | (live_work_reasons + live_work_edge_reasons($up)) as $marks
    | if ([ $u[] | select(. == $succ) ] | length) == 0 then "gone\t-"
      elif ($open_u | length) > 0 then "waiting\t\($open_u | join(","))"
      elif ($unseen | length) > 0 then "unresolved\t\($unseen | join(","))"
      elif ($open_b | length) > 0 then "blocked\t\($open_b | join(","))"
      elif ($marks | length) > 0 then "live\t\($marks | join("; "))"
      else "clear\t-" end;
'
fi
# The status the caller's `.` reads: non-zero when the definitions could not
# be built, so the caller can refuse rather than decide without them.
[ -n "$UNTIL_RESOLVED_JQ" ]
