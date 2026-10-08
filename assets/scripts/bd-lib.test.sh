#!/usr/bin/env bash
# bd-lib.test.sh — hermetic tests for the bd_list memoization.
#
# The cache is off unless GC_RECONCILE_BD_CACHE names a directory, and the
# refinery-reconcile order is its only caller (it clears per arm and removes the
# dir at END). harness_init unsets every GC_* var, so each cache case exports the
# variable after setup. Call counts come from STUB_GC_LOG, where the stub gc logs
# every invocation one per line; a `gc bd list` logs a line starting `bd list`.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bd-lib-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
harness_init
. "$HERE/bd-lib.sh"

store '[{"id":"tk-a","status":"open","assignee":"","title":"a","notes":"","metadata":{"anchor_bead":"tk-anc"}}]'

CACHE="$TMP/cache"
list_calls() { grep -c '^bd list' "$STUB_GC_LOG" 2>/dev/null; }
reset_log()  { : > "$STUB_GC_LOG"; }
cache_files() { find "$CACHE" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# --- the variable unset: byte-identical to before, no caching -----------------
unset GC_RECONCILE_BD_CACHE 2>/dev/null || true
reset_log
a=$(bd_list --status=open); rc=$?
b=$(bd_list --status=open)
eq "$rc" 0 "unset: bd_list returns 0 on a readable array"
has "$a" 'tk-a' "unset: bd_list returns the row"
eq "$a" "$b" "unset: repeated reads agree"
eq "$(list_calls)" 2 "unset: every call hits the server (no cache)"

# --- cache on: a repeated query is served from disk ---------------------------
export GC_RECONCILE_BD_CACHE="$CACHE"; mkdir -p "$CACHE"
reset_log
m1=$(bd_list --status=open); m2=$(bd_list --status=open)
eq "$(list_calls)" 1 "cache: a repeated query hits the server once"
eq "$m1" "$m2" "cache: the hit returns the same bytes as the miss"
has "$m1" 'tk-a' "cache: the served row is the real one"

# --- a different query is a miss ----------------------------------------------
bd_cache_clear; reset_log
bd_list --status=open >/dev/null; bd_list --status=blocked >/dev/null
eq "$(list_calls)" 2 "cache: a different --status is a separate entry (miss)"
eq "$(cache_files)" 2 "cache: two distinct queries store two files"

# --- a --status CSV is order-insensitive --------------------------------------
bd_cache_clear; reset_log
bd_list --status=open,closed >/dev/null; bd_list --status=closed,open >/dev/null
eq "$(list_calls)" 1 "cache: open,closed and closed,open are one entry"

# --- an entry past the hard max age is refetched ------------------------------
bd_cache_clear; reset_log
bd_list --status=deferred >/dev/null                       # store
f=$(find "$CACHE" -maxdepth 1 -type f -name '*.json' | head -1)
touch -d "$(jq -nr --argjson t "$(( $(date -u +%s) - GC_BD_CACHE_MAX_AGE - 100 ))" '$t | todate')" "$f"
bd_list --status=deferred >/dev/null                       # expired -> refetch
eq "$(list_calls)" 2 "cache: an entry older than GC_BD_CACHE_MAX_AGE is refetched"

# --- bd_cache_clear drops every entry -----------------------------------------
bd_cache_clear
eq "$(cache_files)" 0 "bd_cache_clear empties the cache dir"

# --- bd_cache_clear is a no-op (rc 0) when the cache is off --------------------
unset GC_RECONCILE_BD_CACHE
if bd_cache_clear; then ok "bd_cache_clear is a no-op (rc 0) when the variable is unset"; else bad "bd_cache_clear failed when unset"; fi

# --- a set-but-missing cache dir disables caching, never errors ----------------
export GC_RECONCILE_BD_CACHE="$TMP/absent"
reset_log
bd_list --status=open >/dev/null; rc=$?; bd_list --status=open >/dev/null
eq "$rc" 0 "missing dir: bd_list still reads cleanly"
eq "$(list_calls)" 2 "missing dir: caching is disabled (no hit)"

# --- only a successful array is cached: a server error is not served or stored -
export GC_RECONCILE_BD_CACHE="$CACHE"; bd_cache_clear; reset_log
export STUB_LIST_FAIL=1
bd_list --status=open; rc=$?
unset STUB_LIST_FAIL
eq "$rc" 1 "cache: a server error returns non-zero (could not tell)"
eq "$(cache_files)" 0 "cache: a server error is not stored"
# and the next good read is a real miss, not a served error
reset_log
bd_list --status=open >/dev/null
eq "$(list_calls)" 1 "cache: the read after an error is a fresh miss"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
