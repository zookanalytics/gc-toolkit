#!/usr/bin/env bash
# bd-lib.sh — the guarded reads of the bead store, shared by every script that
# queries it, and the gating-PR read the merge and pr-facts arms share. Sourced,
# never executed.
#
# A caller resolves this file beside itself and sources it, the way
# visit-identity.sh is sourced:
#   # shellcheck source=bd-lib.sh
#   . "${GC_BD_LIB:-$SCRIPT_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh" >&2; exit 1; }
#
# Every read goes through `gc bd`, never `bd`: `bd` takes its store from the
# ambient environment, so a stale one answers from the wrong store or trips the
# circuit breaker (tools/lint-learned.d/raw-bd-invocation.sh). The JSON is piped
# through `scrub`, which strips the C0 bytes a JSON string may not carry raw —
# one such byte aborts jq on the whole payload. `scrub` is a name resolved at
# call time, so the fenced copy below defines it for these helpers; a sourcing
# script keeps its own `# >>> control-char-scrub` block for its own direct
# scrubs, and the copies stay byte-identical (formula bodies carry no include
# mechanism, so an identical copy is the pack's sharing idiom for that block).

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# bd_json <gc-bd-args...> — one `gc bd` read as JSON, control chars scrubbed.
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

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
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  _bd_cache_put "$cache_file" "$raw"
  printf '%s' "$raw"
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

# The gating-PR read. The merge arm (merge.sh) and the pr-facts arm
# (pr-facts.sh) both read each gating PR and decide on its merge state, so they
# read it with one field set and the two arms see the same facts.
# gh_pr_view_settled re-reads a PR whose merge state answered UNKNOWN, and
# merge.sh calls it before it judges a candidate's merge state.

# The pinned read's field set. pr-facts.sh asks for it plus labels. A re-read
# asks for the set its pinned read asked for, so the two answers compare field
# for field.
# shellcheck disable=SC2034  # read by the scripts that source this file
PR_FIELDS="state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url"

# GitHub computes a PR's mergeability lazily. The first read after the PR's base
# moves answers UNKNOWN and starts the computation, which finishes within
# seconds, and a PR nobody reads stays UNKNOWN. A re-read that answers a
# computed state decides its PR. One that answers UNKNOWN again spends one of
# the MERGE_STATE_REREADS that one run of the sourcing script gets, and an arm's
# run is one pass. Once they are spent, no PR is re-read for the rest of the run.
# So a computation stalled across the repository costs a pass at most
# MERGE_STATE_REREADS reads that decide nothing, however many PRs answer
# UNKNOWN. A PR's first re-read goes out at once, because its pinned read
# already started the computation, and each later one waits
# MERGE_STATE_REREAD_SECS.
MERGE_STATE_REREADS="${MERGE_STATE_REREADS:-3}"
MERGE_STATE_REREAD_SECS="${MERGE_STATE_REREAD_SECS:-5}"
case "$MERGE_STATE_REREADS" in ''|*[!0-9]*) MERGE_STATE_REREADS=3 ;; esac
case "$MERGE_STATE_REREAD_SECS" in ''|*[!0-9]*) MERGE_STATE_REREAD_SECS=5 ;; esac
MERGE_STATE_REREADS_SPENT=0

# gh_pr_view_settled <pr-number> <repo> <fields> <pinned-json> — read again a PR
# whose pinned read, <pinned-json> asked with --json <fields>, answered an
# UNKNOWN merge state. Sets PR_REREADS to the number of re-reads made, and
# returns:
#   0  a re-read answered a computed state. PR_REREAD_JSON holds that answer and
#      PR_REREAD_STATE its mergeStateStatus.
#   1  the state is still UNKNOWN and the run's re-reads are spent, by this PR's
#      re-reads or, with PR_REREADS=0, by earlier ones.
#   2  a re-read differs from the pinned read in a field other than
#      mergeStateStatus, mergeable and reviewDecision, so the PR changed after
#      the caller judged it. PR_REREAD_CHANGED names each such field with its
#      pinned and re-read values.
#   3  a re-read failed: gh exited non-zero, or printed nothing or something
#      other than a JSON object. That says nothing about the merge state, so it
#      spends nothing and is not reported as UNKNOWN.
# shellcheck disable=SC2034  # the PR_REREAD_* results are the caller's to read
gh_pr_view_settled() {
  local n="$1" repo="$2" fields="$3" pinned="$4" again verdict
  PR_REREADS=0; PR_REREAD_JSON=""; PR_REREAD_STATE=""; PR_REREAD_CHANGED=""
  while [ "$MERGE_STATE_REREADS_SPENT" -lt "$MERGE_STATE_REREADS" ]; do
    [ "$PR_REREADS" -eq 0 ] || sleep "$MERGE_STATE_REREAD_SECS"
    PR_REREADS=$((PR_REREADS + 1))
    again=$(gh pr view "$n" --repo "$repo" --json "$fields" 2>/dev/null) || return 3
    [ -n "$again" ] || return 3
    verdict=$(jq -rn --arg q "'" --argjson a "$pinned" --argjson b "$again" '
      def pinned: del(.mergeStateStatus, .mergeable, .reviewDecision);
      if ($b | type) != "object" then "unreadable"
      else
        [ ([$a, $b] | map(pinned | keys[]) | unique)[] as $k
          | select($a[$k] != $b[$k])
          | "\($k) \($q)\($a[$k] | tostring)\($q) -> \($q)\($b[$k] | tostring)\($q)" ] as $changed
        | if ($changed | length) > 0 then "changed " + ($changed | join(", "))
          else "state " + (($b.mergeStateStatus // "") | tostring) end
      end' 2>/dev/null) || return 3
    case "$verdict" in
      "changed "*) PR_REREAD_CHANGED="${verdict#changed }"; return 2 ;;
      "state "|"state UNKNOWN") MERGE_STATE_REREADS_SPENT=$((MERGE_STATE_REREADS_SPENT + 1)) ;;
      "state "*) PR_REREAD_JSON="$again"; PR_REREAD_STATE="${verdict#state }"; return 0 ;;
      *) return 3 ;;
    esac
  done
  return 1
}
