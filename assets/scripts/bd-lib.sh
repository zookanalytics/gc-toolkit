#!/usr/bin/env bash
# bd-lib.sh — the guarded reads of the bead store, shared by every script that
# queries it. Sourced, never executed.
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
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  if [ -n "$cache_file" ]; then
    printf '%s' "$raw" > "$cache_file.$$.tmp" 2>/dev/null \
      && mv -f "$cache_file.$$.tmp" "$cache_file" 2>/dev/null \
      || rm -f "$cache_file.$$.tmp" 2>/dev/null
  fi
  printf '%s' "$raw"
}
