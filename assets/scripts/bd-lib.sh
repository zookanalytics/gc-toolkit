#!/usr/bin/env bash
# bd-lib.sh — the guarded reads of the bead store, shared by every script that
# queries it, the read of a bead's human gates every reader of them makes and
# the order its open gates under one key are read in, the one-write create every
# script files a stamped bead through, the metadata read-back that gates handing
# such a bead on, the close that unmakes a bead no reader can find, the birth,
# settle and route of PR-finishing work, the validation pass's work order, the
# gating-PR read's field set, the per-rig key an order's state lives under, and
# the pass lock that lets an order run one pass at a time. Sourced, never
# executed.
#
# A caller resolves this file beside itself and sources it:
#   # shellcheck source=bd-lib.sh
#   . "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 1; }
#
# Every read goes through `gc bd`, never `bd`: `bd` takes its store from the
# ambient environment, so a stale one answers from the wrong store or trips the
# circuit breaker (tools/lint-learned.d/raw-bd-invocation.sh). Both readers strip
# the `gc bd:` rig-store notice line (a store can emit it on stdout) and pipe the
# JSON through `scrub`, which strips the C0 bytes a JSON string may not carry raw
# — either contaminant otherwise aborts jq on the whole payload. `scrub` is a name
# resolved at call time, so the fenced copy below defines it for these helpers; a
# sourcing script keeps its own `# >>> control-char-scrub` block for its own direct
# scrubs, and the copies stay byte-identical (formula bodies carry no include
# mechanism, so an identical copy is the pack's sharing idiom for that block).

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# bd_json <gc-bd-args...> — one `gc bd` read as JSON, the `gc bd:` rig-store
# notice line stripped and control chars scrubbed. The notice (a store can emit
# it on stdout) is removed with a text-mode grep BEFORE scrub, while the newline
# that delimits its line still stands; one such line otherwise aborts jq on the
# whole payload. stdin is /dev/null so a call inside a `while read` loop cannot
# consume the loop's own driving input, the guard bd_list already carries.
bd_json() { gc bd "$@" --json </dev/null 2>/dev/null | grep -a -vE '^gc bd:' | scrub; }

# row_meta <show-json> <key> — one metadata value off a `gc bd show --json` row,
# as a string. A key that is absent and a row that will not parse both read as
# empty.
row_meta() { printf '%s' "$1" | jq -r --arg k "$2" '(.[0].metadata[$k] // "") | tostring' 2>/dev/null; }

# bd_list memoization — opt-in, off by default.
#
# When GC_RECONCILE_BD_CACHE names a directory, bd_list serves a repeated query
# from a file in it instead of re-hitting the server. The refinery-reconcile
# order turns it on for one pass: it clears the whole cache before every arm,
# invalidates it (bd_cache_clear) at a write it then re-reads in the same arm,
# and removes the directory when the pass ends. The hard max age is the backstop
# for a clear a new arm forgets. When the variable is unset, every branch below
# is skipped and bd_list behaves exactly as it did before.

# Hard upper bound on a cached entry's age, in seconds. An older entry is
# refetched, so a cache a killed pass left on disk cannot answer a later one
# with stale rows.
GC_BD_CACHE_MAX_AGE=90

# _bd_norm_csv <csv> — the comma list sorted, so argument order does not matter.
_bd_norm_csv() { printf '%s' "$1" | tr ',' '\n' | LC_ALL=C sort | paste -sd, -; }

# _bd_cache_key <gc-bd-list-args...> — a stable digest of $PWD and the argument
# list. $PWD is in the key because `gc bd` answers from the store the cwd
# resolves, so two worktrees must not share an entry. A --status CSV is sorted
# first, so `--status=open,closed` and `--status=closed,open` are one entry.
_bd_cache_key() {
  local out="" a prev=""
  for a in "$@"; do
    case "$a" in
      --status=*) out="$out --status=$(_bd_norm_csv "${a#--status=}")" ;;
      *)
        if [ "$prev" = "--status" ]; then
          out="$out $(_bd_norm_csv "$a")"
        else
          out="$out $a"
        fi ;;
    esac
    prev="$a"
  done
  printf '%s\n%s' "$PWD" "$out" | sha256sum | cut -d' ' -f1
}

# _bd_cache_mtime <file> — epoch mtime, portable across GNU and BSD stat.
_bd_cache_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'; }

# _bd_cache_file <read-args...> — the cache entry for one read, or nothing when
# the cache is off.
_bd_cache_file() {
  [ -n "${GC_RECONCILE_BD_CACHE:-}" ] && [ -d "${GC_RECONCILE_BD_CACHE}" ] || return 0
  printf '%s/%s.json' "$GC_RECONCILE_BD_CACHE" "$(_bd_cache_key "$@")"
}

# _bd_cache_hit <file> — print the entry when it is fresh; non-zero otherwise.
_bd_cache_hit() {
  local age cached
  [ -n "${1:-}" ] && [ -f "$1" ] || return 1
  age=$(( $(date +%s) - $(_bd_cache_mtime "$1") ))
  [ "$age" -ge 0 ] && [ "$age" -le "$GC_BD_CACHE_MAX_AGE" ] || return 1
  cached=$(cat "$1" 2>/dev/null) || return 1
  printf '%s' "$cached"
}

# _bd_cache_drop <read-args...> — forget one read's entry, so the next read of
# it refetches. A no-op when the cache is off. An edge write changes no bead's
# fields, so it drops the edge reads it touched rather than every entry.
_bd_cache_drop() {
  local f
  f=$(_bd_cache_file "$@")
  [ -z "$f" ] || rm -f "$f" 2>/dev/null
  return 0
}

# _bd_cache_put <file> <json> — store a validated read. A no-op without a file.
_bd_cache_put() {
  [ -n "${1:-}" ] || return 0
  printf '%s' "$2" > "$1.$$.tmp" 2>/dev/null \
    && mv -f "$1.$$.tmp" "$1" 2>/dev/null \
    || rm -f "$1.$$.tmp" 2>/dev/null
  return 0
}

# bd_cache_clear — drop every cached entry. A no-op when the cache is off or its
# directory is gone. Whole-directory, not per-key: a write that changes one
# anchor's rows also changes the enumerations and title probes keyed separately,
# and a pass issues few enough writes that clearing all of them costs nothing.
bd_cache_clear() {
  [ -n "${GC_RECONCILE_BD_CACHE:-}" ] && [ -d "${GC_RECONCILE_BD_CACHE}" ] || return 0
  find "$GC_RECONCILE_BD_CACHE" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  return 0
}

# _bd_call <gc-bd-args...> — the `gc bd` call bd_list and the anchor-graph
# reads make. A script that pins its reads to one store redefines it after
# sourcing this file (liveness-sweep.sh adds its --db pin and per-call time
# bound), and those reads follow the pin.
_bd_call() { gc bd "$@"; }

# bd_list <gc-bd-list-args...> — a guarded array read. --limit=0 so a
# client-side filter sees every row; a non-zero exit or a non-array (an errored
# ledger) returns non-zero without printing, so a caller reads "could not tell"
# rather than an empty "none". stdin is /dev/null so a `gc bd list` inside a
# `while read` loop cannot consume the loop's own driving input.
#
# With GC_RECONCILE_BD_CACHE set, a fresh entry for this ($PWD, args) is served
# verbatim and a validated result is stored. Only a rc=0 JSON array is ever
# cached, so the "could not tell" contract is unchanged: a server error is never
# served and never stored.
bd_list() {
  local raw rc cache_file cached
  cache_file=$(_bd_cache_file "$@")
  if cached=$(_bd_cache_hit "$cache_file"); then
    printf '%s' "$cached"; return 0
  fi
  raw=$(_bd_call list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  # Strip the `gc bd:` rig-store notice (a store can emit it on stdout) with a
  # text-mode grep before scrub removes the newline that delimits its line; one
  # such line otherwise fails the type==array check below and reads as "could
  # not tell" on every call in a notice-emitting store.
  raw=$(printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  _bd_cache_put "$cache_file" "$raw"
  printf '%s' "$raw"
}

# bd_human_gates <bead> — the bead's human gates: each bead its `blocks` edges
# reach whose issue_type is `gate` and whose await_type is `human`, open and
# closed alike. This is the one read every reader of a bead's human gates
# makes. It prints the rows `gc bd dep list <bead> --type blocks` returns, as
# one JSON array. For one bead, bd answers each edge with the whole row of the
# bead it reaches plus the edge's dependency_type, and these are the fields of
# that row the readers rely on: id, issue_type, await_type, await_id, status,
# assignee, title, description, created_at, close_reason and closed_at. bd
# leaves an empty field out, so a gate no person is assigned carries no
# assignee. A read that exits non-zero, or answers anything but an array, as bd
# answers a bead it cannot find, prints nothing and returns 1, so "no gate" and
# "could not read" stay apart. `bd gate list <bead>` is not this read: it
# returns the gates a bead reaches through an edge of any type, without saying
# which edge.
bd_human_gates() {
  local raw
  raw=$(_bd_call dep list "$1" --type blocks --json </dev/null 2>/dev/null) || return 1
  raw=$(printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub)
  printf '%s' "$raw" | jq -ce 'if type == "array"
    then [ .[] | select((.issue_type // "") == "gate" and (.await_type // "") == "human") ]
    else error("not an array") end' 2>/dev/null
}

# $HUMAN_GATE_JQ — the one rule of which human gates still hold the bead they
# block, as jq defs in the in-variable convention standing-kinds.sh describes,
# so every reader prepends the same text. A human gate holds in every status but
# closed, pinned included, because only its resolve clears the question it asks;
# gctk merge and pr-status read a gate the same way. The defs:
#   human_gate             on one row: issue_type gate and await_type human
#   open_human_gate($k)    on one row: a human gate that still holds, and when $k
#                          is not "", one under that situation key
#   open_human_gates       on a listing array: the ids of its open human gates,
#                          for a reader that classifies many beads from one
#                          listing that includes gates (`gc bd list
#                          --include-gates`, `gc bd gate list`)
#   gates_blocking($ids)   on one row: the ids among $ids that its own blocks
#                          edges reach, the gates that hold the bead
#   blocked_by_any($ids)   on one row: whether gates_blocking($ids) names any
# shellcheck disable=SC2034  # read by the scripts that source this file
HUMAN_GATE_JQ='
  def human_gate: (.issue_type // "") == "gate" and (.await_type // "") == "human";
  def open_human_gate($k):
    human_gate
    and (((.status // "open") | tostring | ascii_downcase) != "closed")
    and ($k == "" or ((.await_id // "") | tostring) == $k);
  def open_human_gates: [ .[] | select(open_human_gate("")) | .id ];
  def gates_blocking($ids):
    [ .dependencies[]? | select((.type // "") == "blocks")
      | (.depends_on_id // "") as $d | select(($ids | index($d)) != null) | $d ];
  def blocked_by_any($ids): (gates_blocking($ids) | length) > 0;
'

# bd_open_human_gates <bead> [<key>] — the bead's human gates that still hold it
# (open_human_gate above), and with <key> only those under that situation key,
# as one JSON array of the rows bd_human_gates prints: the read for a reader
# that asks which open gates hold one bead. A gate read that does not answer
# prints nothing and returns 1, so "none open" and "could not read" stay apart.
bd_open_human_gates() {
  local gates
  gates=$(bd_human_gates "${1:-}") || return 1
  printf '%s' "$gates" | jq -c --arg k "${2:-}" "$HUMAN_GATE_JQ"'[ .[] | select(open_human_gate($k)) ]' 2>/dev/null
}

# bd_gates_open_under_key <key> — the open gates under a situation key, read
# from a bd_human_gates array on stdin and printed as one JSON array, first to
# last by when each was created, then id. Two stand when racing writers both
# filed. The first is the one a caller names: human-gate.sh's dedup prints it,
# and await-ruling.sh makes the work bead wait on it, so every writer and
# reader of one situation orders the gates here. created_at is read as a time,
# its fractional seconds and its offset included, because as text a time with
# a fraction sorts ahead of the whole second it follows, and one with an offset
# sorts by its local clock. A gate whose created_at is absent or does not read
# as an RFC 3339 time sorts after every gate whose does. Input that is not an
# array prints nothing and returns 1. Which gates are open is open_human_gate's
# rule, above.
bd_gates_open_under_key() {
  jq -ce --arg k "$1" "$HUMAN_GATE_JQ"'
    def created_order:
      ([ (.created_at // "") | tostring
         | capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$") ]
       | .[0]) as $m
      | (if $m == null then null
         else try (
           (($m.d + "Z") | fromdateiso8601)
           - (if $m.z == "Z" then 0
              else ($m.z | capture("^(?<s>[+-])(?<h>[0-9]{2}):?(?<mi>[0-9]{2})$")) as $o
                | (($o.h | tonumber) * 3600 + ($o.mi | tonumber) * 60)
                | if $o.s == "-" then -. else . end
              end)
         ) catch null end) as $sec
      | if $sec == null then [1, 0, 0]
        else [0, $sec, (("0" + ($m.f // "")) | tonumber)] end;
    if type == "array"
    then [ .[] | select(open_human_gate($k)) ]
         | sort_by(created_order, (.id // "" | tostring))
    else error("not an array") end' 2>/dev/null || return 1
}

# The anchor graph. A bead that hangs off a PR anchor (a review, a rework
# child, a finding, a validation pass, a visit) names the anchor in
# anchor_bead, and that key is what makes it a child. Each child also has an
# edge onto its anchor, child -> anchor, the side parent-child uses, so the
# anchor's dependents include it. A pair with no edge is joined with a `related`
# edge, and a pair already carrying another type is joined by that edge.
#
# The live children are read by anchor_bead over the live statuses. That read
# scans only the live beads, and it is complete whatever filed the child, the
# edge or not. The closed children are read through the edge, one
# `gc bd dep list <anchor> --direction=up`, because an anchor_bead query that
# covers closed has no index to use and reads the whole closed ledger. A
# dependent is a closed child when its anchor_bead names the anchor. bd keeps
# one edge per ordered pair, so a child joined by another type (a visit's
# `tracks` edge) is one too, and a bead moved to another anchor leaves the old
# one's set with its old edge still in place.
#
# The edge answers for the closed children only in a store marked joined:
# `gc bd kv` carries ANCHOR_JOINED_KEY, which tools/anchor-edges-backfill.sh
# --mark sets after a run that found no child missing its edge. An unmarked
# store reads its closed children by anchor_bead too. Each child the pack files
# or adopts is joined to its anchor no later than anchor_bead lands on it
# (bd_create_child, bd_anchor_link), so a marked store stays joined. A child
# filed some other way without the edge still reads while it is live, and
# tools/anchor-edges-backfill.sh --check reports it.
#
# `related` holds nothing: it gates neither bd ready nor a close, and merge.sh's
# blocker probe reads the `blocks` edges down from the anchor, never these.
ANCHOR_EDGE_TYPE=related
ANCHOR_JOINED_KEY=anchor_edges.joined
_BD_ANCHOR_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

# _bd_store_joined — 0 when the store is marked joined (ANCHOR_JOINED_KEY in
# `gc bd kv`), served through the bd_list memo. An unset key and a read that did
# not answer are both non-zero, and either way the caller reads the closed
# children by anchor_bead, which is right whether the store is joined or not.
_bd_store_joined() {
  local cache_file cached found
  cache_file=$(_bd_cache_file kv get "$ANCHOR_JOINED_KEY")
  if cached=$(_bd_cache_hit "$cache_file"); then
    [ "$cached" = 1 ]; return
  fi
  # `kv get` exits 1 for an unset key and still prints {"found": false}, so the
  # answer is read from the JSON, not the exit status.
  found=$(_bd_call kv get "$ANCHOR_JOINED_KEY" --json </dev/null 2>/dev/null | scrub | jq -r '
    if type == "object" and has("found")
    then (if .found == true and ((.value // "") | tostring) != "" then "1" else "0" end)
    else empty end' 2>/dev/null)
  [ -n "$found" ] || return 1
  _bd_cache_put "$cache_file" "$found"
  [ "$found" = 1 ]
}

# _bd_anchor_up <anchor> [--cached] — every dependent of <anchor>, of any edge
# type, as one array of bead rows. --cached serves and stores it through the
# bd_list memo. Non-zero without output = the store did not answer; an anchor
# that does not resolve is that too, never an empty set.
_bd_anchor_up() {
  local raw rc cache_file="" cached
  [ "${2:-}" = --cached ] && cache_file=$(_bd_cache_file dep list "$1" --direction=up)
  if cached=$(_bd_cache_hit "$cache_file"); then
    printf '%s' "$cached"; return 0
  fi
  raw=$(_bd_call dep list "$1" --direction=up --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  _bd_cache_put "$cache_file" "$raw"
  printf '%s' "$raw"
}

# bd_anchor_children <anchor> <status-csv> — the children of <anchor> in those
# statuses, as one array of bead rows: the bd_list contract, so non-zero without
# output means "could not tell", never "none". A row carries the bead's own
# fields and metadata, but not its outgoing .dependencies. Every read rides the
# bd_list memo, and none writes. The live statuses are read by anchor_bead, and
# closed through the edge in a store marked joined, else by anchor_bead with
# them. The live read goes first, so a child that closes between the two reads
# is reported live rather than missed.
bd_anchor_children() {
  local anchor="${1:-}" statuses="${2:-}" s live="" closed="" rows='[]' up
  [ -n "$anchor" ] && [ -n "$statuses" ] || return 1
  for s in $(printf '%s' "$statuses" | tr ',' ' '); do
    if [ "$s" = closed ]; then closed=1; else live="${live:+$live,}$s"; fi
  done
  if [ -z "$closed" ]; then
    bd_list --metadata-field anchor_bead="$anchor" --status="$live"; return
  fi
  if ! _bd_store_joined; then
    bd_list --metadata-field anchor_bead="$anchor" --status="$statuses"; return
  fi
  if [ -n "$live" ]; then
    rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$live") || return 1
  fi
  up=$(_bd_anchor_up "$anchor" --cached) || return 1
  # Both arrays ride stdin: an anchor's rows can carry long descriptions, and
  # one jq argument is bounded by the OS per-argument limit.
  printf '%s\n%s' "$rows" "$up" | jq -sc --arg a "$anchor" '
    .[0] as $live | ([ $live[] | (.id // "") | tostring ]) as $seen
    | $live + [ .[1][]
        | select(((.metadata.anchor_bead // "") | tostring) == $a)
        | select(((.status // "") | tostring | ascii_downcase) == "closed")
        | select(((.id // "") | tostring) as $i | any($seen[]; . == $i) | not) ]' 2>/dev/null
}

# _bd_on_pair <child> <anchor> — 0 when <child> has an edge onto <anchor>, of
# any type.
_bd_on_pair() {
  gc bd dep list "$1" --direction=down --json </dev/null 2>/dev/null | scrub \
    | jq -e --arg a "$2" 'type == "array" and any(.[]; (.id // "") == $a)' >/dev/null 2>&1
}

# _bd_join <child> <anchor> — one membership edge. A pair already joined, by
# this type or another, counts as joined. Non-zero prints bd's refusal.
_bd_join() {
  local err
  err=$(gc bd dep add "$1" "$2" --type "$ANCHOR_EDGE_TYPE" </dev/null 2>&1 >/dev/null) && return 0
  _bd_on_pair "$1" "$2" && return 0
  echo "bd-lib: could not join $1 to anchor $2: $(printf '%s' "${err:-bd gave no reason}" | tr '\n' ' ')" >&2
  return 1
}

# bd_anchor_link <anchor> [<child>...] — join each <child> to <anchor> by the
# membership edge, for a bead that exists before anchor_bead is stamped on it.
# Idempotent. Non-zero = an edge did not land (bd's refusal is printed), so the
# caller must not count the child as joined.
bd_anchor_link() {
  local anchor="${1:-}" child rc=0
  shift || true
  [ -n "$anchor" ] || return 1
  for child in "$@"; do
    [ -n "$child" ] && [ "$child" != "$anchor" ] || continue
    _bd_join "$child" "$anchor" || rc=1
  done
  _bd_cache_drop dep list "$anchor" --direction=up
  return "$rc"
}

# bd_create_child <anchor> <gc bd create args...> — `gc bd create` for a bead
# that hangs off <anchor>. The membership edge rides the create (--deps), so the
# bead is born joined to its anchor or not at all. Prints the create's stdout
# and returns its exit status. stdin passes through to the create
# (--body-file -).
bd_create_child() {
  local anchor="${1:-}" rc
  shift || true
  [ -n "$anchor" ] || return 1
  gc bd create "$@" --deps "$ANCHOR_EDGE_TYPE:$anchor"; rc=$?
  _bd_cache_drop dep list "$anchor" --direction=up
  return "$rc"
}

# _bd_anchor_stamp <anchor> <children-json> <up-json> [--check] — join each
# child the up read does not show on its pair with <anchor>. A child on the pair
# already, whatever its type, is left out, because bd refuses a second type on a
# pair. Prints each id it joins, one per line; --check prints the ids it would
# join and writes nothing. The joins go in one `dep add --file` write, which bd
# commits as one transaction, so one refused pair refuses all of it; then each
# pair is joined alone, and only a pair bd refuses on its own is left out, with
# bd's reason printed. Exit 1 = a pair did not land; 2 = an input did not parse.
_bd_anchor_stamp() {
  local anchor="$1" check="${4:-}" missing edges k bad=0
  missing=$(printf '%s\n%s' "$2" "$3" | jq -rs --arg a "$anchor" '
    if (.[0] | type) != "array" or (.[1] | type) != "array" then error("unreadable") else . end
    | ([ .[1][] | (.id // "") | tostring ]) as $on
    | [ .[0][] | (.id // "") | tostring ] | unique | .[]
    | select(. != "" and . != $a) | . as $k | select(any($on[]; . == $k) | not)' 2>/dev/null) || return 2
  [ -n "$missing" ] || return 0
  if [ "$check" = --check ]; then printf '%s\n' "$missing"; return 0; fi
  edges=$(printf '%s\n' "$missing" | jq -Rc --arg a "$anchor" --arg t "$ANCHOR_EDGE_TYPE" \
    'select(. != "") | {from: ., to: $a, type: $t}' 2>/dev/null) || return 1
  if printf '%s\n' "$edges" | gc bd dep add --file - >/dev/null 2>&1; then
    printf '%s\n' "$missing"; return 0
  fi
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    if _bd_join "$k" "$anchor"; then printf '%s\n' "$k"; else bad=1; fi
  done <<STAMP_EOF
$missing
STAMP_EOF
  return "$bad"
}

# bd_anchor_backfill <anchor> [--check] — read the anchor_bead children of
# <anchor>, every status, and join each one its up read does not reach
# (_bd_anchor_stamp). Both reads skip the memo, so the comparison never rests on
# an older read. Prints the ids it joined, or with --check the ids it would
# join. Exit 1 = a join did not land; 2 = a read did not answer.
bd_anchor_backfill() {
  local GC_RECONCILE_BD_CACHE=""
  local anchor="${1:-}" check="${2:-}" up kids
  [ -n "$anchor" ] || return 2
  up=$(_bd_anchor_up "$anchor") || return 2
  kids=$(bd_list --metadata-field anchor_bead="$anchor" --status="$_BD_ANCHOR_STATUSES") || return 2
  _bd_anchor_stamp "$anchor" "$kids" "$up" "$check"
}

# bd_live_children — the live beads hung on each anchor through anchor_bead:
# its reviews, validation passes, findings, rework children and visits, in one
# read of the store. Prints one line per anchor that has any:
#   <anchor>\t<child ids, sorted, comma-joined>\t<1 when one is a rework child, else 0>
# A walking arm compares the id list with what it saw at its last visit, so a
# child that opened or closed since then shows without a read per anchor.
# Non-zero without output = the store did not answer.
bd_live_children() {
  local rows
  rows=$(bd_list --status=open,in_progress,blocked,deferred,hooked,pinned \
           --has-metadata-key anchor_bead) || return 1
  printf '%s' "$rows" | jq -r '
    [ .[] | { a: ((.metadata.anchor_bead // "") | tostring), id: ((.id // "") | tostring),
              rw: (((.metadata.task_kind // "") | tostring) == "rework") }
          | select(.a != "" and .id != "") ]
    | group_by(.a)[]
    | [ .[0].a, (map(.id) | sort | join(",")), (if any(.[]; .rw) then "1" else "0" end) ]
    | @tsv' 2>/dev/null
}

# bd_create [--select <keys>] [--child-of <anchor>] <metadata-json>
#   <gc-bd-create-args...> — file one bead with its metadata in the same write,
#   and print its id.
#
# The metadata a bead is born with is what its readers select it by: its
# task_kind, the anchor it hangs on, the key its producer dedups on. Written in
# a second `update --set-metadata`, it is missing whenever that write fails or
# the create's id never comes back. No reader can see such a bead, so nothing
# closes it, and the producer's next run files a stamped twin beside it.
# `gc bd create --metadata` lands the payload in the bead's own row insert, so
# the bead exists with its metadata or not at all.
#
# <metadata-json> must be a JSON object with at least one key. Anything else is
# refused before a create runs, so this helper never files a bead with no
# metadata. The other arguments are `gc bd create`'s own: the title, -t, -d or
# --body-file - (stdin reaches the create), --status, --notes, --deps, --db and
# the rest. The helper adds --metadata and --json.
#
# --child-of files the bead as a child of <anchor>, which the payload must name
# as its anchor_bead. A child's membership edge stands no later than its
# anchor_bead, and here anchor_bead lands with the create, so the edge rides the
# create too: it goes through bd_create_child, and the child is born joined to
# its anchor or not filed at all. An empty <anchor>, or one the payload's
# anchor_bead does not name, is refused before a create runs.
#
# The bead is read back from the store the create wrote, and every key must
# read back with the value written. A bead short of a key is written the whole
# payload once more and read back again (bd_meta_ensure). That write carries
# only the values the create carried, onto a bead filed a moment before.
#
# --select names, comma-joined, the payload keys the caller's own probe finds
# the bead by, and the caller keeps that list beside the probe. A bead still
# short of one of them after the second write is one no later run can find,
# while an edge it carries can still hold its anchor, so it is closed
# (bd_unmake) and reported as nothing filed. With no --select, a bead is closed
# only when it is still short of every key. A --select key the payload does not
# carry is refused before a create runs.
#
# Returns:
#   0  filed, and every key read back. Prints the id.
#   1  nothing a reader can find was filed. Either the payload, --select or
#      --child-of was refused, or bd refused the create (its reason goes to
#      stderr: a --child-of anchor that does not resolve is one), or no id
#      came back, or the bead stayed short of a --select key, or of every key,
#      and was closed (gc.outcome=abandoned) so that no reader meets it. A
#      create whose reply was lost can still have landed whole, so a caller
#      that files again first looks for the bead the way its own dedup does.
#   2  filed, but the read-back could not be made or did not show every key as
#      written. Prints the id. The bead carries every --select key, or some key
#      with no --select, so the caller's next run can find it, and a caller
#      hands it on only once bd_meta_ensure has made it whole.
bd_create() {
  local sel="" child="" anchor="" meta db="" prev="" a reply id row got short lost="" err
  while :; do
    case "${1:-}" in
      --select) sel="${2:-}" ;;
      --child-of) child=1; anchor="${2:-}" ;;
      *) break ;;
    esac
    shift 2 || { echo "bd_create: $1 takes a value; nothing filed" >&2; return 1; }
  done
  if [ -n "$child" ] && [ -z "$anchor" ]; then
    echo "bd_create: --child-of names no anchor; nothing filed" >&2
    return 1
  fi
  meta="${1:-}"
  shift || true
  printf '%s' "$meta" | jq -e 'type == "object" and length > 0' >/dev/null 2>&1 \
    || { echo "bd_create: refusing to file a bead without a metadata object; nothing filed" >&2; return 1; }
  meta=$(printf '%s' "$meta" | jq -c . 2>/dev/null) \
    || { echo "bd_create: could not normalize the metadata payload; nothing filed" >&2; return 1; }
  if [ -n "$sel" ] && ! printf '%s' "$meta" | jq -e --arg s "$sel" \
       '. as $m | ($s | split(",")) | all(.[]; . as $k | $m | has($k))' >/dev/null 2>&1; then
    echo "bd_create: --select '$sel' names a key the payload does not carry; nothing filed" >&2
    return 1
  fi
  if [ -n "$anchor" ] && ! printf '%s' "$meta" | jq -e --arg a "$anchor" \
       '((.anchor_bead // "") | tostring) == $a' >/dev/null 2>&1; then
    echo "bd_create: --child-of $anchor is not the anchor_bead the payload names; nothing filed" >&2
    return 1
  fi
  # The read-back, the second write and the close go to the store the create
  # wrote.
  for a in "$@"; do
    [ "$prev" = "--db" ] && db="$a"
    case "$a" in --db=*) db="${a#--db=}" ;; esac
    prev="$a"
  done
  if [ -n "$anchor" ]; then
    reply=$(bd_create_child "$anchor" "$@" --metadata "$meta" --json 2>/dev/null | scrub)
  else
    reply=$(gc bd create "$@" --metadata "$meta" --json 2>/dev/null | scrub)
  fi
  bd_cache_clear
  id=$(printf '%s' "$reply" | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
  if [ -z "$id" ] || [ "$id" = "null" ]; then
    err=$(printf '%s' "$reply" | jq -r 'if type == "object" then (.error // empty) else empty end' 2>/dev/null)
    echo "bd_create: bd create returned no id${err:+: $err}" >&2
    return 1
  fi
  row=$(bd_json show "$id" ${db:+--db "$db"} </dev/null)
  got=$(bd_meta_judge "$id" "$meta" "$row")
  [ "${got%%$'\t'*}" = landed ] && { printf '%s\n' "$id"; return 0; }
  if short=$(bd_meta_ensure --row "$row" "$id" "$meta" ${db:+--db "$db"}); then
    printf '%s\n' "$id"
    return 0
  fi
  if [ "$short" != unreadable ]; then
    if [ -n "$sel" ]; then
      lost=$(jq -rn --arg s "$sel" --arg q "$short" \
        '($q | split(",")) as $q | [ $s | split(",")[] | select(. as $k | any($q[]; . == $k)) ] | join(",")' 2>/dev/null)
    elif [ "$short" = "$(printf '%s' "$meta" | jq -r 'keys_unsorted | join(",")' 2>/dev/null)" ]; then
      lost="$short"
    fi
  fi
  if [ -n "$lost" ]; then
    if bd_unmake "$id" "Unmade by bd_create: this bead did not read back carrying $lost, which its producer finds it by, so no reader could find it. Its producer files it afresh." ${db:+--db "$db"}; then
      echo "bd_create: $id did not read back carrying $lost, so no reader could find it; closed it, nothing filed" >&2
    else
      echo "bd_create: $id did not read back carrying $lost, so no reader can find it, and it would not close; whatever its edges hold stays held until it is closed by hand" >&2
    fi
    return 1
  fi
  echo "bd_create: $id was filed but its metadata did not read back as written (short: $short)" >&2
  printf '%s\n' "$id"
  return 2
}

# bd_meta_judge <id> <metadata-json> <show-json> — how a bead carries a metadata
# payload, judged from a `gc bd show --json` reply the caller already holds, with
# no read of its own. Prints one line: a verdict, a tab, and the payload's keys
# that do not read back with the value written, comma-joined.
#   landed      every key reads back as written
#   bare        the bead carries none of the payload's keys
#   partial     some key is missing, or reads back with another value
#   unreadable  the reply does not hold the bead
# A value compares as its text, jq's tostring of it, because bd keeps a create's
# string values as strings while a --set-metadata write of the same key can
# store a number, a boolean or null. So "42" matches 42 and "false" matches
# false, while false, null and the empty string each match only themselves.
bd_meta_judge() {
  local id="${1:-}" meta="${2:-}" row="${3:-}" out
  out=$(printf '%s' "$row" | jq -r --arg id "$id" --argjson m "$meta" '
    if type == "array" and ((.[0].id // "") == $id) then
      ((.[0].metadata // {}) | if type == "object" then . else {} end) as $got
      | [ $m | to_entries[] | . as $e
          | select((($got | has($e.key))
                    and (($got[$e.key] | tostring) == ($e.value | tostring))) | not)
          | .key ] as $short
      | (if ($short | length) == 0 then "landed"
         elif ($m | keys | all(.[]; . as $k | ($got | has($k)) | not)) then "bare"
         else "partial" end) + "\t" + ($short | join(","))
    else "unreadable\t" end' 2>/dev/null)
  if [ -n "$out" ]; then printf '%s\n' "$out"; else printf 'unreadable\t\n'; fi
}

# bd_meta_readback <id> <metadata-json> [gc-bd-args...] — bd_meta_judge on a
# fresh read of the bead. The trailing arguments reach `gc bd show`, so the read
# follows the --db a write named.
bd_meta_readback() {
  local id="${1:-}" meta="${2:-}"
  shift 2 || true
  bd_meta_judge "$id" "$meta" "$(bd_json show "$id" "$@" </dev/null)"
}

# bd_meta_ensure [--row <show-json>] <id> <metadata-json> [gc-bd-args...] — make
# a bead that already exists carry a payload before its caller hands it on. The
# payload is judged against the bead: against --row, a `gc bd show --json` reply
# the caller already read, or else against a fresh read. When any key is short,
# every key is written in one update and read back again. Returns 0 once every
# key reads back as written. Otherwise prints the keys still short,
# comma-joined, or "unreadable" when the bead itself did not read back, and
# returns 1. A bead that does not read back before the write is not written:
# nothing then shows who holds it. The trailing arguments reach the read, the
# write and the read-back alike, so a --db sends all three to that store.
#
# A route or a sling makes a bead someone's work order, so a caller gates that
# act on this check and not on the exit of the write that filed the bead:
# bd_create prints the id of a bead whose read-back fell short (its rc 2), and
# `gc bd update` can exit 0 without writing. The write ignores bd's claim guard,
# so a caller runs this only on a bead nobody has taken.
bd_meta_ensure() {
  local row="" seen="" id meta got kv sets=()
  if [ "${1:-}" = "--row" ]; then row="${2:-}"; seen=1; shift 2 || true; fi
  id="${1:-}"; meta="${2:-}"
  shift 2 || true
  if [ -n "$seen" ]; then got=$(bd_meta_judge "$id" "$meta" "$row")
  else got=$(bd_meta_readback "$id" "$meta" "$@"); fi
  case "${got%%$'\t'*}" in
    landed) return 0 ;;
    unreadable) printf 'unreadable\n'; return 1 ;;
  esac
  while IFS= read -r -d '' kv; do
    sets+=(--set-metadata "$kv")
  done < <(printf '%s' "$meta" | jq -j 'to_entries[] | "\(.key)=\(.value | if type == "string" then . else tojson end)\u0000"' 2>/dev/null)
  if [ "${#sets[@]}" -gt 0 ]; then
    gc bd update "$id" "$@" "${sets[@]}" </dev/null >/dev/null 2>&1 || true
    bd_cache_clear
    got=$(bd_meta_readback "$id" "$meta" "$@")
    [ "${got%%$'\t'*}" = landed ] && return 0
  fi
  if [ "${got%%$'\t'*}" = unreadable ]; then printf 'unreadable\n'; else printf '%s\n' "${got#*$'\t'}"; fi
  return 1
}

# bd_unmake <id> <note> [gc-bd-args...] — close a bead its producer filed but no
# reader can find, so that nothing it carries holds anything. The close carries
# gc.outcome=abandoned and appends <note>, which names who unmade it and why.
# The trailing arguments reach the close and its read-back, so a --db sends both
# to that store. Returns 0 once the bead reads back closed, 1 otherwise: the
# update's exit cannot say, because `gc bd update` can exit 0 without writing.
bd_unmake() {
  local id="${1:-}" note="${2:-}" st
  shift 2 || true
  gc bd update "$id" "$@" --status=closed --set-metadata gc.outcome=abandoned --append-notes "$note" \
    </dev/null >/dev/null 2>&1 || true
  bd_cache_clear
  st=$(bd_json show "$id" "$@" </dev/null | jq -r --arg id "$id" '
    if type == "array" and ((.[0].id // "") == $id)
    then ((.[0].status // "") | tostring | ascii_downcase) else "" end' 2>/dev/null)
  [ "$st" = closed ]
}

# bd_unmake_orphans <select-keys> <title> <note> [gc-bd-args...] — close what a
# producer that stamped a bead in a second write after its create left behind:
# an open bead with that producer's <title> in its own, which nobody has taken
# (no assignee, no route, no pour) and which is short of a key in
# <select-keys>, the comma-joined keys the producer's probe finds its beads by.
# No probe can find such a bead, yet a blocks edge it carries still holds its
# anchor, and the producer files a whole bead beside it. bd_create never leaves
# one, so this finds only beads filed the older way. Each is closed through
# bd_unmake and its id printed. Returns 1 when the listing did not answer, else
# 0. The trailing arguments reach the listing and the closes.
bd_unmake_orphans() {
  local sel="${1:-}" title="${2:-}" note="${3:-}" rows oid
  shift 3 || true
  rows=$(bd_list --status=open --title-contains "$title" "$@") || return 1
  while IFS= read -r oid; do
    [ -n "$oid" ] || continue
    bd_unmake "$oid" "$note" "$@" && printf '%s\n' "$oid"
  done < <(printf '%s' "$rows" | jq -r --arg s "$sel" --arg t "$title" '
    ($s | split(",")) as $sel
    | .[]
    | select(((.status // "") | tostring | ascii_downcase) == "open")
    | select(((.title // "") | tostring) | contains($t))
    | select(((.assignee // "") | tostring) == "")
    | ((.metadata // {}) | if type == "object" then . else {} end) as $m
    | select((($m["gc.routed_to"] // "") | tostring) == "")
    | select((($m["gc.execution_routed_to"] // "") | tostring) == "")
    | select(any($sel[]; (($m[.] // "") | tostring) == ""))
    | .id' 2>/dev/null)
  return 0
}

# PR-finishing work, the reviews, validation passes, merge-ins, red-check fixes
# and review reworks that carry an anchor's branch to its merge, is filed one
# level sooner than its anchor (docs/steering.md, "PR-finishing work"). Each
# creator files its child carrying this shift in the create, so the child is
# born with it, and each creator's suite asserts it. A child adopted or re-routed
# later keeps the shift it carries: after its birth the shift is the child's own
# input, which a priority move may have set.
# shellcheck disable=SC2034  # read by the scripts that source this file
PR_FINISHING_SHIFT=-1

# pr_finishing_birth <metadata-json> — the create payload of a PR-finishing
# child: its work order with priority_shift added. Prints nothing and returns
# non-zero for a work order that is not a JSON object, an empty one included, so
# the create that would carry it files nothing.
pr_finishing_birth() {
  printf '%s' "${1:-}" | jq -ce --argjson s "$PR_FINISHING_SHIFT" \
    'if type == "object" then . + {priority_shift: $s} else error("not an object") end' 2>/dev/null
}

# The longest a settle of PR-finishing work waits for the store's priority lock
# when a script of the merge cadence or the refinery patrol runs it:
# gate-ensure.sh, pr-facts.sh, pre-open-rebase.sh and rejection-repool.sh. The
# cadence and the patrol each run their arms one after another, so a longer wait
# holds every arm after it. A bead whose settle times out in the cadence is
# settled by a later pass, and rejection-repool.sh files a human gate that asks
# for its re-run. queue-priority.sh's own default wait is longer, and
# rework-child.sh, which runs in a review or converse session rather than in the
# cadence, keeps it.
PR_FINISHING_LOCK_WAIT_SECS=30

# pr_finishing_settle <bead> — the cadence's settle of a bead of PR-finishing
# work: queue-priority.sh settle, which computes the bead's priority, writes it
# to the bead and to every live workflow poured for it, and reads it back
# (docs/steering.md#settle), waiting for the lock PR_FINISHING_LOCK_WAIT_SECS
# at most. The writer's narrative goes to stdout and its refusal to stderr, for
# the caller to keep or drop. GC_QUEUE_PRIORITY_TOOL names another writer, as
# each suite's harness does. Non-zero when the bead did not settle.
pr_finishing_settle() {
  QUEUE_PRIORITY_LOCK_WAIT_SECS="$PR_FINISHING_LOCK_WAIT_SECS" \
    "${GC_QUEUE_PRIORITY_TOOL:-$(dirname -- "${BASH_SOURCE[0]}")/queue-priority.sh}" settle "${1:-}" </dev/null
}

# route_finishing <child> <pool> — route a PR-finishing child to <pool> at its
# priority, for the creators that route a child rather than sling it
# (pr-facts.sh, pre-open-rebase.sh). The route makes the child claimable, so the
# child is settled first (pr_finishing_settle), and the route is then written
# alone, with no priority in it. No pool can claim the child before the route
# lands, and a priority move that runs between the two writes rewrites the child
# itself. Returns 1, having routed nothing, when the child does not settle; it
# is left unrouted for a later pass. A route write bd refuses can still exit 0,
# so the caller reads the route back.
route_finishing() {
  pr_finishing_settle "${1:-}" >/dev/null || return 1
  gc bd update "$1" --set-metadata gc.routed_to="${2:-}" </dev/null >/dev/null 2>&1 || true
}

# The keys a validation pass is found by: signoff.sh's machine-lane probe and
# pr-facts.sh's human-lane probe both select a pass by its task_kind, its anchor
# and its lane, so a pass short of one of them is one neither can find.
# shellcheck disable=SC2034  # read by the scripts that source this file
VALIDATION_SELECT="task_kind,anchor_bead,check_name"

# validation_work_order <anchor> <lane> <reviewed-oid> — the metadata a
# validation pass is filed with, the shape mol-validate reads, born carrying the
# PR-finishing shift. task_kind, anchor_bead and check_name are
# VALIDATION_SELECT. check_name is the lane: mol-validate rules the findings
# whose finding.lane matches it. reviewed_oid pins the head the batch was
# produced at, which mol-validate needs to back a machine lane; an empty
# <reviewed-oid> leaves the pin out.
validation_work_order() {
  pr_finishing_birth "$(jq -nc --arg a "${1:-}" --arg l "${2:-}" --arg o "${3:-}" \
    '{task_kind: "validation", anchor_bead: $a, check_name: $l}
     + (if $o == "" then {} else {reviewed_oid: $o} end)' 2>/dev/null)"
}

# The gating-PR read. The pr-facts arm (pr-facts.sh) and the merge arm
# (`gctk merge`, prFields in services/gctk/internal/cli/merge.go) both read each
# gating PR and decide on its merge state, so they read it with one field set
# and the two arms see the same facts. merge.test.sh holds the merge arm's reads
# to this set.

# The pinned read's field set. pr-facts.sh asks for it plus labels.
# shellcheck disable=SC2034  # read by the scripts that source this file
PR_FIELDS="state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url"

# Per-rig state and the pass lock. An order that runs once per rig keeps its
# state in a directory named for the rig, and a pass that must never overlap
# another over the same work holds a lock in that directory while it runs.

# state_key <readable> <identity> — a directory name for <identity> that reads
# as <readable>. A safe name that is its own identity is used as it is. Any
# other name is the safe form of <readable>, cut to 64 bytes, then a checksum of
# <identity>, so two identities never share a name and no name reaches outside
# the directory it is joined to.
state_key() {
  local readable="$1" identity="$2" safe
  safe="$(printf '%s' "$readable" | LC_ALL=C tr -c 'A-Za-z0-9._-' '_')"
  case "$safe" in ''|.|..) safe=rig ;; esac
  if [ "$safe" = "$readable" ] && [ "$readable" = "$identity" ] && [ "${#safe}" -le 64 ]; then
    printf '%s' "$safe"
  else
    printf '%s-%s' "${safe:0:64}" "$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
  fi
}

# rig_state_key — the state key of the rig this process runs for. The order
# runner sets GC_RIG and GC_RIG_ROOT together for a rig-scoped order (gascity
# cmd/gc/order_store.go), and the key is GC_RIG. With only GC_RIG_ROOT set, the
# root the store resolves from, the key is the root's last path element and a
# checksum of the whole root, so two roots that end in one name stay apart. With
# neither it is _unscoped.
rig_state_key() {
  local root
  if [ -n "${GC_RIG:-}" ]; then
    state_key "$GC_RIG" "$GC_RIG"
  elif [ -n "${GC_RIG_ROOT:-}" ]; then
    root="${GC_RIG_ROOT%/}"
    state_key "${root##*/}" "$GC_RIG_ROOT"
  else
    printf '_unscoped'
  fi
}

# take_pass_lock <dir> <stall-secs> — take the pass lock kept in <dir>: a
# non-blocking exclusive flock on <dir>/pass.lock, held on fd 9, with this
# process and the time it took the lock recorded in <dir>/pass.holder as
# "<pid> <epoch>". Returns 0 holding it; 1 when another pass holds it and took it
# no more than <stall-secs> ago; 2 when that pass took it longer ago than that;
# and 3 when no lock can be taken, because flock is not on PATH or the lock file
# cannot be created or opened. LOCK_NOTE names the holder for 1 and 2, as
# "pid <n>, <s>s elapsed", and the cause for 3. Only a 0 leaves fd 9 open.
#
# The lock depends on no bead surviving. The kernel releases it once no process
# has a descriptor on it, however each one exits, SIGKILL included. A descriptor
# a script opens stays open across exec, so every program the pass starts
# inherits fd 9. A program can outlive the pass that started it: a store read can
# bring up a Dolt server, and gc hands the descriptors it was given to what it
# starts. A program that kept fd 9 would hold the lock against every later pass,
# so a pass runs each program that can leave a process behind, a gc call or one
# of the pack's scripts, through pass_child.
# shellcheck disable=SC2034  # LOCK_NOTE is read by the scripts that source this file
take_pass_lock() {
  local dir="$1" stall="$2" lock="$1/pass.lock" holder="$1/pass.holder"
  local held_pid="" held_since="" elapsed=""
  LOCK_NOTE=""
  if ! command -v flock >/dev/null 2>&1; then
    LOCK_NOTE="flock not found on PATH"; return 3
  fi
  if ! mkdir -p "$dir" 2>/dev/null || ! ( : >> "$lock" ) 2>/dev/null; then
    LOCK_NOTE="cannot create $lock"; return 3
  fi
  exec 9>>"$lock" || { LOCK_NOTE="cannot open $lock"; return 3; }
  if flock -n 9; then
    printf '%s %s\n' "$$" "$(date -u +%s)" > "$holder" 2>/dev/null || true
    return 0
  fi
  exec 9>&-
  if [ -r "$holder" ]; then read -r held_pid held_since < "$holder" || true; fi
  case "$held_since" in
    ''|*[!0-9]*) ;;
    *) elapsed=$(( $(date -u +%s) - held_since )) ;;
  esac
  LOCK_NOTE="pid ${held_pid:-unknown}${elapsed:+, ${elapsed}s elapsed}"
  if [ -n "$elapsed" ] && [ "$elapsed" -gt "$stall" ]; then return 2; fi
  return 1
}

# pass_child <program> [args...] — run <program> for a pass that holds the pass
# lock, and return its status. <program> starts with fd 9 closed, so nothing it
# starts, or leaves running, holds the lock. The subshell it runs from keeps fd 9
# and waits on it, so the lock stays held while <program> runs, even after the
# pass that started it is killed by itself; the order runner stops a pass's whole
# process group (gascity cmd/gc/order_dispatch.go), <program> with it. The exit
# after <program> is what keeps bash from replacing the subshell with it. Name a
# program, not a shell function: bash closes fd 9 in the process it starts for a
# program, and a function runs in the subshell itself.
pass_child() { ( "$@" 9>&-; exit "$?" ); }
