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
  raw=$(gc bd list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  _bd_cache_put "$cache_file" "$raw"
  printf '%s' "$raw"
}

# The anchor graph. A bead that hangs off a PR anchor (a review, a rework
# child, a finding, a validation pass, a visit) carries anchor_bead=<anchor>
# and a `related` edge onto the anchor, child -> anchor, the side parent-child
# uses. So an anchor's children are its dependents, one edge read
# (`gc bd dep list <anchor> --direction=up`), where an anchor_bead metadata
# query has no index to use and reads every bead in the statuses it asks for.
# A child is a dependent whose anchor_bead names the anchor. A bead moved to
# another anchor keeps its old edge but leaves the old anchor's set, and
# anchor_bead stays the read from a child up to its anchor. bd keeps one edge
# per ordered pair, so a child joined to its anchor by another type (a visit's
# `tracks` edge) is a member through that edge.
#
# `related` holds nothing: it gates neither bd ready nor a close, and merge.sh's
# blocker probe reads the `blocks` edges down from the anchor, never these.
#
# An anchor none of whose children carries the edge is read by its anchor_bead
# metadata instead, and migrated: its anchor_bead children, every status, are
# joined in one `dep add --file` write, which bd commits as one transaction, so
# no anchor reads with some of its children joined and others missing.
# bd_anchor_link migrates an anchor before it joins a new child to it.
ANCHOR_EDGE_TYPE=related
_BD_ANCHOR_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

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
  raw=$(gc bd dep list "$1" --direction=up --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  _bd_cache_put "$cache_file" "$raw"
  printf '%s' "$raw"
}

# _bd_anchor_migrated <anchor> <up-json> — 0 when a child of <anchor> carries
# the membership edge, the mark that the anchor's children were joined.
_bd_anchor_migrated() {
  printf '%s' "$2" | jq -e --arg a "$1" --arg t "$ANCHOR_EDGE_TYPE" '
    any(.[]; ((.dependency_type // "") == $t)
             and (((.metadata.anchor_bead // "") | tostring) == $a))' >/dev/null 2>&1
}

# _bd_anchor_stamp <anchor> <children-json> <up-json> — join every child that
# is not yet on its pair with <anchor>, in one write. A child the up read shows
# on the pair already, whatever its type, is left out, because bd refuses a
# second type on a pair and one refused pair refuses the whole batch. Non-zero
# = the write did not land, and then none of the batch did.
_bd_anchor_stamp() {
  local on kids edges
  on=$(printf '%s' "$3" | jq -c '[ .[] | (.id // "") | tostring ]' 2>/dev/null) || return 1
  kids=$(printf '%s' "$2" | jq -c '[ .[] | (.id // "") | tostring ]' 2>/dev/null) || return 1
  edges=$(jq -nc --arg a "$1" --arg t "$ANCHOR_EDGE_TYPE" --argjson on "$on" --argjson kids "$kids" '
    $kids | unique | .[] | . as $k
    | select($k != "" and $k != $a and (any($on[]; . == $k) | not))
    | {from: $k, to: $a, type: $t}' 2>/dev/null) || return 1
  [ -n "$edges" ] || return 0
  printf '%s\n' "$edges" | gc bd dep add --file - >/dev/null 2>&1
}

# _bd_csv_covers <csv> <required-csv> — 0 when <csv> names every status in
# <required-csv>.
_bd_csv_covers() {
  local s
  for s in $(printf '%s' "$2" | tr ',' ' '); do
    case ",$1," in *",$s,"*) : ;; *) return 1 ;; esac
  done
  return 0
}

# bd_anchor_children <anchor> <status-csv> — the children of <anchor> in those
# statuses, as one array of bead rows: the bd_list contract, so non-zero without
# output means "could not tell", never "none". A row carries the bead's own
# fields and metadata, but not its outgoing .dependencies. The edge read rides
# the bd_list memo. An anchor not yet migrated answers from its anchor_bead
# metadata, and a read that asked for every status migrates it.
bd_anchor_children() {
  local anchor="${1:-}" statuses="${2:-}" up rows
  [ -n "$anchor" ] && [ -n "$statuses" ] || return 1
  up=$(_bd_anchor_up "$anchor" --cached) || return 1
  if _bd_anchor_migrated "$anchor" "$up"; then
    printf '%s' "$up" | jq -c --arg a "$anchor" --arg st "$statuses" '
      ($st | split(",")) as $want
      | [ .[] | select(((.metadata.anchor_bead // "") | tostring) == $a)
              | select(((.status // "") | tostring | ascii_downcase) as $s | any($want[]; . == $s)) ]' 2>/dev/null || return 1
    return 0
  fi
  rows=$(bd_list --metadata-field anchor_bead="$anchor" --status="$statuses") || return 1
  if _bd_csv_covers "$statuses" "$_BD_ANCHOR_STATUSES" \
     && _bd_anchor_stamp "$anchor" "$rows" "$up"; then
    _bd_cache_drop dep list "$anchor" --direction=up
  fi
  printf '%s' "$rows"
}

# _bd_on_pair <child> <anchor> — 0 when <child> has an edge onto <anchor>, of
# any type.
_bd_on_pair() {
  gc bd dep list "$1" --direction=down --json </dev/null 2>/dev/null | scrub \
    | jq -e --arg a "$2" 'type == "array" and any(.[]; (.id // "") == $a)' >/dev/null 2>&1
}

# _bd_anchor_link_now <anchor> [<child>...] — bd_anchor_link's work, with the
# bd_list memo off: a migration that read a stale scan would join only part of
# the anchor's children.
_bd_anchor_link_now() {
  local GC_RECONCILE_BD_CACHE=""
  local anchor="${1:-}" up kids child
  shift || true
  [ -n "$anchor" ] || return 1
  up=$(_bd_anchor_up "$anchor") || return 1
  if ! _bd_anchor_migrated "$anchor" "$up"; then
    kids=$(bd_list --metadata-field anchor_bead="$anchor" --status="$_BD_ANCHOR_STATUSES") || return 1
    _bd_anchor_stamp "$anchor" "$kids" "$up" || return 1
  fi
  for child in "$@"; do
    [ -n "$child" ] && [ "$child" != "$anchor" ] || continue
    gc bd dep add "$child" "$anchor" --type "$ANCHOR_EDGE_TYPE" </dev/null >/dev/null 2>&1 \
      || _bd_on_pair "$child" "$anchor" || return 1
  done
  return 0
}

# bd_anchor_link <anchor> [<child>...] — join each <child> to <anchor> by the
# membership edge, for a bead whose anchor_bead is stamped after it exists. The
# anchor is migrated first, so the first edge it carries never stands beside an
# older sibling that has none. Idempotent: a pair already joined, by this type
# or another, is left as it is. Non-zero = the anchor did not migrate or an edge
# did not land, so the caller must not count the child as joined.
bd_anchor_link() {
  local rc
  _bd_anchor_link_now "$@"; rc=$?
  _bd_cache_drop dep list "${1:-}" --direction=up
  return "$rc"
}

# bd_create_child <anchor> <gc bd create args...> — `gc bd create` for a bead
# that hangs off <anchor>. The membership edge rides the create (--deps), so the
# bead is born joined to its anchor or not at all, once bd_anchor_link has
# migrated the anchor. Prints the create's stdout and returns its exit status;
# an anchor that did not migrate creates nothing and returns non-zero. stdin
# passes through to the create (--body-file -).
bd_create_child() {
  local anchor="${1:-}"
  shift || true
  [ -n "$anchor" ] || return 1
  bd_anchor_link "$anchor" || return 1
  gc bd create "$@" --deps "$ANCHOR_EDGE_TYPE:$anchor"
}

# bd_live_children <anchor>... — the live children of each named anchor, in
# one edge read across all of them. Prints one line per anchor that has any:
#   <anchor>\t<child ids, sorted, comma-joined>\t<1 when one is a rework child, else 0>
# A walking arm compares the id list with what it saw at its last visit, so a
# child that opened or closed since then shows without a read per anchor. No
# anchor prints nothing. Non-zero without output = the store did not answer,
# which is also the answer when a named id does not resolve. An anchor not yet
# migrated shows only the children already joined to it.
bd_live_children() {
  local raw rc
  [ "$#" -gt 0 ] || return 0
  raw=$(gc bd dep list "$@" --direction=up --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw" | jq -r '
    ($ARGS.positional) as $anchors
    | [ .[] | { a: ((.metadata.anchor_bead // "") | tostring), id: ((.id // "") | tostring),
                st: ((.status // "") | tostring | ascii_downcase),
                rw: (((.metadata.task_kind // "") | tostring) == "rework") }
            | . as $r
            | select($r.a != "" and $r.id != "" and any($anchors[]; . == $r.a))
            | select(any(["open","in_progress","blocked","deferred","hooked","pinned"][]; . == $r.st)) ]
    | unique_by(.id) | group_by(.a)[]
    | [ .[0].a, (map(.id) | sort | join(",")), (if any(.[]; .rw) then "1" else "0" end) ]
    | @tsv' --args "$@" 2>/dev/null
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
