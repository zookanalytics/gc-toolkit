#!/usr/bin/env bash
# bd-lib.test.sh — hermetic tests for the bd_list memoization and the anchor
# graph reads and writes (bd_anchor_children, bd_anchor_link, bd_create_child,
# bd_live_children).
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

# --- the anchor graph -----------------------------------------------------------
dep_calls()  { grep -c '^bd dep list' "$STUB_GC_LOG" 2>/dev/null; }
dep_adds()   { grep -c '^bd dep add' "$STUB_GC_LOG" 2>/dev/null; }
edges()      { LC_ALL=C sort "$STUB_DEPS" | paste -sd' ' -; }
ids_of()     { printf '%s' "$1" | jq -r '[ .[].id ] | sort | join(",")'; }
unset GC_RECONCILE_BD_CACHE

# A migrated anchor: its children carry the related edge, a convoy tracks it,
# a visit is joined by its tracks edge, and one bead moved to another anchor
# still carries its old edge.
store '[
  {"id":"tk-anc","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-two","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-r1","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-r2","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-vis","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"visit"}},
  {"id":"tk-cv","status":"open","metadata":{}},
  {"id":"tk-mv","status":"open","metadata":{"anchor_bead":"tk-two","task_kind":"rework"}}
]'
printf '%s\n' 'tk-r1|related|tk-anc' 'tk-r2|related|tk-anc' 'tk-vis|tracks|tk-anc' \
  'tk-cv|tracks|tk-anc' 'tk-mv|related|tk-anc' 'tk-r2|blocks|tk-anc' > "$STUB_DEPS"
reset_log
kids=$(bd_anchor_children tk-anc open,in_progress,blocked,deferred,hooked,pinned,closed); rc=$?
eq "$rc" 0 "bd_anchor_children reads a migrated anchor"
eq "$(ids_of "$kids")" "tk-r1,tk-r2,tk-vis" \
  "its children are the dependents naming it in anchor_bead: a tracks-joined visit is one, a convoy and a moved bead are not"
eq "$(dep_calls)" 1 "…in one edge read"
eq "$(list_calls)" 0 "…and no anchor_bead metadata query"
live=$(bd_anchor_children tk-anc open,in_progress,blocked,deferred,hooked,pinned)
eq "$(ids_of "$live")" "tk-r2,tk-vis" "the status list filters the rows: a closed child is not live"
eq "$(printf '%s' "$kids" | jq -r '[ .[] | select(.id == "tk-r2") | .metadata.task_kind ] | .[0]')" "review" \
  "a row carries the child's metadata"

# The edge read rides the bd_list memo when the order turns it on.
export GC_RECONCILE_BD_CACHE="$CACHE"; bd_cache_clear; reset_log
bd_anchor_children tk-anc open >/dev/null; bd_anchor_children tk-anc closed >/dev/null
eq "$(dep_calls)" 1 "cache: two reads of one anchor's children, any statuses, hit the server once"
unset GC_RECONCILE_BD_CACHE

# A store that does not answer, and an anchor that does not resolve, are "could
# not tell", never "no children".
export STUB_DEP_PARTIAL=1
kids=$(bd_anchor_children tk-anc open); rc=$?
unset STUB_DEP_PARTIAL
[ "$rc" -ne 0 ] && ok "a failed edge read is reported non-zero" || bad "a failed edge read read as no children"
eq "$kids" "" "…with nothing printed"
kids=$(bd_anchor_children tk-gone open); rc=$?
[ "$rc" -ne 0 ] && ok "an anchor that does not resolve is reported non-zero" || bad "a missing anchor read as no children"

# An anchor none of whose children carries the edge yet: the read answers from
# the anchor_bead metadata, and a read covering every status migrates it in one
# write that skips the pair a visit's tracks edge already holds.
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-o2","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"finding"}},
  {"id":"tk-ov","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"visit"}},
  {"id":"tk-cv","status":"open","metadata":{}}
]'
printf '%s\n' 'tk-ov|tracks|tk-old' 'tk-cv|tracks|tk-old' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
reset_log
live=$(bd_anchor_children tk-old open,in_progress,blocked,deferred,hooked,pinned); rc=$?
eq "$rc" 0 "an anchor not yet migrated still reads"
eq "$(ids_of "$live")" "tk-o2,tk-ov" "…its live children, from the anchor_bead metadata"
eq "$(dep_adds)" 0 "…and a live-only read joins nothing: it never saw the closed children"
reset_log
all=$(bd_anchor_children tk-old open,in_progress,blocked,deferred,hooked,pinned,closed)
eq "$(ids_of "$all")" "tk-o1,tk-o2,tk-ov" "a read of every status answers every child"
eq "$(dep_adds)" 1 "…and migrates the anchor in one write"
eq "$(edges)" "tk-cv|tracks|tk-old tk-o1|related|tk-old tk-o2|blocks|tk-old tk-o2|related|tk-old tk-ov|tracks|tk-old" \
  "…joining every child the pair of which is free, and leaving the visit on its tracks edge"
reset_log
all=$(bd_anchor_children tk-old open,in_progress,blocked,deferred,hooked,pinned,closed)
eq "$(ids_of "$all")" "tk-o1,tk-o2,tk-ov" "the migrated anchor answers the same children"
eq "$(list_calls)" 0 "…from the edge read alone"

# With the memo on, a migration forgets only the anchor's edge read: the next
# read of the anchor sees its new edges, and an unrelated entry still serves.
printf '%s\n' 'tk-ov|tracks|tk-old' 'tk-cv|tracks|tk-old' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
export GC_RECONCILE_BD_CACHE="$CACHE"; bd_cache_clear
bd_list --status=closed >/dev/null
reset_log
bd_anchor_children tk-old open,in_progress,blocked,deferred,hooked,pinned,closed >/dev/null
eq "$(dep_adds)" 1 "cache: a read with the memo on still migrates the anchor"
bd_list --status=closed >/dev/null
eq "$(list_calls)" 1 "cache: …and an unrelated memo entry survives it (only the fallback scan hit the server)"
reset_log
bd_anchor_children tk-old open >/dev/null
eq "$(dep_calls):$(list_calls)" "1:0" "cache: the anchor's edge read is refetched and answers from its new edges"
unset GC_RECONCILE_BD_CACHE

# The batch is one transaction: a pair taken by another type between the read
# and the write refuses it whole, and the anchor stays unmigrated.
printf '%s\n' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-o2","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"finding"}}
]'
up_before=$(gc bd dep list tk-old --direction=up --json)
printf '%s\n' 'tk-o2|discovered-from|tk-old' >> "$STUB_DEPS"
if _bd_anchor_stamp tk-old "$(jq -c '[ .[] | select(.metadata.anchor_bead == "tk-old") ]' "$STUB_STORE")" "$up_before"; then
  bad "a batch with a refused pair reported success"
else
  ok "a batch with a refused pair reports failure"
fi
eq "$(grep -c related "$STUB_DEPS")" 0 "…and writes none of its edges"

# --- bd_anchor_link: migrate, then join -----------------------------------------
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-new","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"rework"}},
  {"id":"tk-vv","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"visit"}}
]'
printf '%s\n' 'tk-vv|tracks|tk-old' > "$STUB_DEPS"
if bd_anchor_link tk-old tk-new tk-vv; then ok "bd_anchor_link joins children to an anchor"; else bad "bd_anchor_link failed"; fi
eq "$(edges)" "tk-new|related|tk-old tk-o1|related|tk-old tk-vv|tracks|tk-old" \
  "…migrating the anchor's older children first, and counting a pair another type holds as joined"
if bd_anchor_link tk-old tk-new; then ok "bd_anchor_link is idempotent"; else bad "a repeated bd_anchor_link failed"; fi
eq "$(grep -c '' "$STUB_DEPS")" 3 "…and adds no second edge"
if bd_anchor_link tk-gone tk-new; then bad "bd_anchor_link joined a child to an anchor that does not resolve"; else ok "an anchor that does not resolve joins nothing"; fi

# --- bd_create_child: the edge rides the create ---------------------------------
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}}
]'
: > "$STUB_DEPS"
reset_log
out=$(printf 'the body' | bd_create_child tk-old "a child" -t task --body-file - --metadata '{"anchor_bead":"tk-old","task_kind":"review"}' --json); rc=$?
nid=$(printf '%s' "$out" | jq -r '.id')
eq "$rc" 0 "bd_create_child creates the bead"
eq "$(jq -r --arg id "$nid" '.[] | select(.id == $id) | .description' "$STUB_STORE")" "the body" \
  "…with stdin reaching the create"
eq "$(edges)" "$nid|related|tk-old tk-o1|related|tk-old" \
  "…born joined to its anchor, after the anchor's older children were joined"
has "$(grep '^bd create' "$STUB_GC_LOG")" "--deps related:tk-old" "…the edge riding the create itself"
reset_log
if printf 'x' | bd_create_child tk-gone "orphan" -t task --body-file - --json >/dev/null; then
  bad "bd_create_child created a child of an anchor that does not resolve"
else
  ok "bd_create_child refuses an anchor that does not resolve"
fi
eq "$(grep -c '^bd create' "$STUB_GC_LOG")" 0 "…and creates nothing"

# --- bd_live_children: one edge read, the live children grouped by anchor -------
store '[
  {"id":"tk-anc","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-two","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-three","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-r2","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-f1","status":"in_progress","metadata":{"anchor_bead":"tk-anc","task_kind":"finding"}},
  {"id":"tk-w1","status":"blocked","metadata":{"anchor_bead":"tk-two","task_kind":"rework"}},
  {"id":"tk-v1","status":"open","metadata":{"anchor_bead":"tk-two","task_kind":"validation"}},
  {"id":"tk-c1","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"rework"}},
  {"id":"tk-cv","status":"open","metadata":{}},
  {"id":"tk-t1","status":"open","metadata":{"anchor_bead":"tk-three","task_kind":"review"}}
]'
printf '%s\n' 'tk-r2|related|tk-anc' 'tk-f1|related|tk-anc' 'tk-c1|related|tk-anc' 'tk-cv|tracks|tk-anc' \
  'tk-w1|related|tk-two' 'tk-v1|related|tk-two' 'tk-t1|related|tk-three' > "$STUB_DEPS"
reset_log
lc=$(bd_live_children tk-anc tk-two); rc=$?
eq "$rc" 0 "bd_live_children reads the store"
eq "$(printf '%s\n' "$lc" | sort | paste -sd';' -)" "tk-anc	tk-f1,tk-r2	0;tk-two	tk-v1,tk-w1	1" \
  "one line per named anchor: its live child ids sorted, and whether a rework child is among them"
eq "$(dep_calls)" 1 "…in one edge read across the anchors"
eq "$(list_calls)" 0 "…and no metadata query"
lc=$(bd_live_children); rc=$?
eq "$rc:$lc" "0:" "no anchor named reads nothing"
export STUB_DEP_PARTIAL=1
lc=$(bd_live_children tk-anc); rc=$?
unset STUB_DEP_PARTIAL
[ "$rc" -ne 0 ] && ok "an unreadable store is reported non-zero" || bad "an unreadable store read as no children"
eq "$lc" "" "…with nothing printed, so no caller reads it as no children"
lc=$(bd_live_children tk-anc tk-gone); rc=$?
[ "$rc" -ne 0 ] && ok "a named id that does not resolve fails the whole read" || bad "a missing anchor was dropped silently"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
