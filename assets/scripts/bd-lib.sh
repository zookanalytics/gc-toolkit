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

# bd_list <gc-bd-list-args...> — a guarded array read. --limit=0 so a
# client-side filter sees every row; a non-zero exit or a non-array (an errored
# ledger) returns non-zero without printing, so a caller reads "could not tell"
# rather than an empty "none". stdin is /dev/null so a `gc bd list` inside a
# `while read` loop cannot consume the loop's own driving input.
bd_list() {
  local raw rc
  raw=$(gc bd list "$@" --limit=0 --json </dev/null 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ -n "$raw" ] || return 1
  raw=$(printf '%s' "$raw" | scrub)
  printf '%s' "$raw" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  printf '%s' "$raw"
}
