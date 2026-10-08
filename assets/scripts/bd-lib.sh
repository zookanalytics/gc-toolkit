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
  local raw rc cache_file="" cached age
  if [ -n "${GC_RECONCILE_BD_CACHE:-}" ] && [ -d "${GC_RECONCILE_BD_CACHE}" ]; then
    cache_file="$GC_RECONCILE_BD_CACHE/$(_bd_cache_key "$@").json"
    if [ -f "$cache_file" ]; then
      age=$(( $(date +%s) - $(_bd_cache_mtime "$cache_file") ))
      if [ "$age" -ge 0 ] && [ "$age" -le "$GC_BD_CACHE_MAX_AGE" ]; then
        cached=$(cat "$cache_file" 2>/dev/null) && { printf '%s' "$cached"; return 0; }
      fi
    fi
  fi
  raw=$(gc bd list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  # Strip the `gc bd:` rig-store notice (a store can emit it on stdout) with a
  # text-mode grep before scrub removes the newline that delimits its line; one
  # such line otherwise fails the type==array check below and reads as "could
  # not tell" on every call in a notice-emitting store.
  raw=$(printf '%s' "$raw" | grep -a -vE '^gc bd:' | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  if [ -n "$cache_file" ]; then
    printf '%s' "$raw" > "$cache_file.$$.tmp" 2>/dev/null \
      && mv -f "$cache_file.$$.tmp" "$cache_file" 2>/dev/null \
      || rm -f "$cache_file.$$.tmp" 2>/dev/null
  fi
  printf '%s' "$raw"
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
