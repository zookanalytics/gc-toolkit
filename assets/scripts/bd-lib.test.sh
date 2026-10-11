#!/usr/bin/env bash
# bd-lib.test.sh — hermetic tests for the bd_list memoization and the anchor
# graph reads and writes (bd_anchor_children, bd_anchor_link, bd_create_child,
# bd_anchor_backfill, bd_live_children).
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
kv_calls()   { grep -c '^bd kv' "$STUB_GC_LOG" 2>/dev/null; }
edges()      { LC_ALL=C sort "$STUB_DEPS" | paste -sd' ' -; }
ids_of()     { printf '%s' "$1" | jq -r '[ .[].id ] | sort | join(",")'; }
mark_store() { printf '%s=%s\n' "$ANCHOR_JOINED_KEY" 2026-10-11T00:00:00Z > "$STUB_KV"; }
ALL=open,in_progress,blocked,deferred,hooked,pinned,closed
LIVE=open,in_progress,blocked,deferred,hooked,pinned
unset GC_RECONCILE_BD_CACHE

# One anchor in every shape a child can take: closed children with the edge, a
# visit joined by its tracks edge, an open review filed without the edge, a
# closed review filed without it, a convoy tracking the anchor, and a bead moved
# to another anchor that still carries its old edge.
store '[
  {"id":"tk-anc","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-two","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-r1","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-r2","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-vis","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"visit"}},
  {"id":"tk-bare","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-cbare","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-cv","status":"open","metadata":{}},
  {"id":"tk-mv","status":"closed","metadata":{"anchor_bead":"tk-two","task_kind":"rework"}}
]'
printf '%s\n' 'tk-r1|related|tk-anc' 'tk-r2|related|tk-anc' 'tk-vis|tracks|tk-anc' \
  'tk-cv|tracks|tk-anc' 'tk-mv|related|tk-anc' 'tk-r2|blocks|tk-anc' > "$STUB_DEPS"

# An unmarked store reads every child by anchor_bead, the read before the edge.
: > "$STUB_KV"; reset_log
kids=$(bd_anchor_children tk-anc "$ALL"); rc=$?
eq "$rc" 0 "unmarked: bd_anchor_children reads the anchor"
eq "$(ids_of "$kids")" "tk-bare,tk-cbare,tk-r1,tk-r2,tk-vis" \
  "unmarked: every bead naming the anchor in anchor_bead, closed included, edge or not"
eq "$(list_calls):$(dep_calls)" "1:0" "unmarked: …in one anchor_bead read, and no edge read"
has "$(grep '^bd list' "$STUB_GC_LOG")" "--status=$ALL" "unmarked: …over the statuses asked for"
reset_log
live=$(bd_anchor_children tk-anc "$LIVE")
eq "$(ids_of "$live")" "tk-bare,tk-r2" "a live read answers the live children, edge or not"
eq "$(list_calls):$(dep_calls):$(kv_calls)" "1:0:0" "…from one anchor_bead read, without asking for the mark"

# A marked store reads the live children by anchor_bead and the closed ones
# through the edge.
mark_store; reset_log
kids=$(bd_anchor_children tk-anc "$ALL"); rc=$?
eq "$rc" 0 "marked: bd_anchor_children reads the anchor"
eq "$(ids_of "$kids")" "tk-bare,tk-r1,tk-r2,tk-vis" \
  "marked: the live children whatever their edge, and the closed dependents naming the anchor (a tracks-joined visit is one; a convoy and a moved bead are not)"
eq "$(printf '%s' "$kids" | jq -r '[ .[] | select(.id == "tk-bare") | .status ] | .[0]')" "open" \
  "marked: an open review filed without the edge is read, so it holds its lane"
eq "$(printf '%s' "$kids" | jq -r '[ .[] | select(.id == "tk-cbare") ] | length')" "0" \
  "marked: a closed child without the edge is not read: the edge answers for the closed ledger"
eq "$(printf '%s' "$kids" | jq -r '[ .[] | .id ] | length')" "$(printf '%s' "$kids" | jq -r '[ .[] | .id ] | unique | length')" \
  "marked: …and no child is answered twice"
eq "$(list_calls):$(dep_calls):$(kv_calls)" "1:1:1" "marked: …in one mark read, one live anchor_bead read and one edge read"
has "$(grep '^bd list' "$STUB_GC_LOG")" "--status=$LIVE" "marked: …the anchor_bead read covering the live statuses only"
eq "$(dep_adds)" 0 "marked: a read writes nothing"
eq "$(printf '%s' "$kids" | jq -r '[ .[] | select(.id == "tk-r1") | .metadata.task_kind ] | .[0]')" "review" \
  "marked: a closed row carries the child's metadata"
reset_log
closed=$(bd_anchor_children tk-anc closed)
eq "$(ids_of "$closed")" "tk-r1,tk-vis" "marked: a closed-only read answers from the edge alone"
eq "$(list_calls):$(dep_calls)" "0:1" "marked: …with no anchor_bead read"

# A child that closes between the live read and the edge read is reported once,
# as the live read saw it. _bd_call is the hook every read goes through, so the
# test closes tk-r2 in the store right after the first of the two reads answers:
# the edge read going first would miss it, and no de-duplication would answer
# it twice.
_bd_call() {
  gc bd "$@"; local rc=$?
  if [ "${1:-}" != kv ] && [ ! -e "$TMP/flipped" ]; then
    : > "$TMP/flipped"
    jq -c 'map(if .id == "tk-r2" then .status = "closed" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
  fi
  return "$rc"
}
rm -f "$TMP/flipped"
kids=$(bd_anchor_children tk-anc "$ALL")
_bd_call() { gc bd "$@"; }
eq "$(printf '%s' "$kids" | jq -r '[ .[] | select(.id == "tk-r2") | .status ] | join(",")')" "open" \
  "marked: a child that closes between the two reads is reported once, live"
jq -c 'map(if .id == "tk-r2" then .status = "open" else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"

# Every read goes through _bd_call, so a script that pins its reads redefines it
# and the anchor reads follow (liveness-sweep.sh's --db pin).
_bd_call() { printf '%s\n' "$*" >> "$TMP/hook.log"; gc bd "$@"; }
: > "$TMP/hook.log"
bd_anchor_children tk-anc "$ALL" >/dev/null
_bd_call() { gc bd "$@"; }
eq "$(cut -d' ' -f1-2 "$TMP/hook.log" | paste -sd, -)" "kv get,list --metadata-field,dep list" \
  "the mark, the live read and the edge read all go through _bd_call"

# The mark and the reads ride the bd_list memo when the order turns it on.
export GC_RECONCILE_BD_CACHE="$CACHE"; bd_cache_clear; reset_log
bd_anchor_children tk-anc "$ALL" >/dev/null; bd_anchor_children tk-anc "$ALL" >/dev/null
bd_anchor_children tk-anc closed >/dev/null
eq "$(kv_calls):$(list_calls):$(dep_calls)" "1:1:1" "cache: repeated reads of one anchor hit the server once per read"
unset GC_RECONCILE_BD_CACHE

# "Could not tell" is never "no children".
reset_log
export STUB_DEP_PARTIAL=1
kids=$(bd_anchor_children tk-anc "$ALL"); rc=$?
unset STUB_DEP_PARTIAL
[ "$rc" -ne 0 ] && ok "marked: a failed edge read is reported non-zero" || bad "a failed edge read read as no closed children"
eq "$kids" "" "…with nothing printed"
export STUB_LIST_FAIL=1
kids=$(bd_anchor_children tk-anc "$ALL"); rc=$?
unset STUB_LIST_FAIL
[ "$rc" -ne 0 ] && ok "marked: a failed live read is reported non-zero" || bad "a failed live read read as no live children"
kids=$(bd_anchor_children tk-gone "$ALL"); rc=$?
[ "$rc" -ne 0 ] && ok "marked: an anchor that does not resolve is reported non-zero" || bad "a missing anchor read as no children"
# A mark that does not read is an unmarked store: the read falls back to
# anchor_bead, which answers every child.
reset_log
kids=$(STUB_KV_FAIL=1 bd_anchor_children tk-anc "$ALL"); rc=$?
eq "$rc:$(ids_of "$kids")" "0:tk-bare,tk-cbare,tk-r1,tk-r2,tk-vis" \
  "an unreadable mark reads every child by anchor_bead"
eq "$(list_calls):$(dep_calls)" "1:0" "…in the one read an unmarked store makes"
: > "$STUB_KV"

# --- bd_anchor_link: one edge per child, nothing else ---------------------------
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-new","status":"open","metadata":{"task_kind":"rework"}},
  {"id":"tk-vv","status":"open","metadata":{"task_kind":"visit"}}
]'
printf '%s\n' 'tk-vv|tracks|tk-old' > "$STUB_DEPS"
reset_log
if bd_anchor_link tk-old tk-new tk-vv; then ok "bd_anchor_link joins children to an anchor"; else bad "bd_anchor_link failed"; fi
eq "$(edges)" "tk-new|related|tk-old tk-vv|tracks|tk-old" \
  "…one edge for the named child, a pair another type holds counted as joined, and no sibling touched"
eq "$(list_calls)" 0 "…with no anchor_bead read"
if bd_anchor_link tk-old tk-new; then ok "bd_anchor_link is idempotent"; else bad "a repeated bd_anchor_link failed"; fi
eq "$(grep -c '' "$STUB_DEPS")" 2 "…and adds no second edge"
err=$(STUB_DEP_ADD_FAIL=tk-o1 bd_anchor_link tk-old tk-o1 2>&1 >/dev/null); rc=$?
eq "$rc" 1 "a join bd refuses is reported non-zero"
has "$err" "simulated refusal for tk-o1" "…printing bd's reason"

# --- bd_create_child: the edge rides the create ---------------------------------
: > "$STUB_DEPS"
reset_log
out=$(printf 'the body' | bd_create_child tk-old "a child" -t task --body-file - --metadata '{"anchor_bead":"tk-old","task_kind":"review"}' --json); rc=$?
nid=$(printf '%s' "$out" | jq -r '.id')
eq "$rc" 0 "bd_create_child creates the bead"
eq "$(jq -r --arg id "$nid" '.[] | select(.id == $id) | .description' "$STUB_STORE")" "the body" \
  "…with stdin reaching the create"
eq "$(edges)" "$nid|related|tk-old" "…born joined to its anchor, with no older sibling touched"
has "$(grep '^bd create' "$STUB_GC_LOG")" "--deps related:tk-old" "…the edge riding the create itself"
eq "$(list_calls):$(dep_adds)" "0:0" "…in the create alone"
reset_log
if printf 'x' | bd_create_child tk-gone "orphan" -t task --body-file - --json >/dev/null 2>&1; then
  bad "bd_create_child created a child of an anchor that does not resolve"
else
  ok "bd_create_child refuses an anchor that does not resolve"
fi
eq "$(jq -r '[ .[] | select(.title == "orphan") ] | length' "$STUB_STORE")" 0 "…and creates nothing"
# The create forgets the anchor's memoized edge read, so the same pass sees it.
mark_store
export GC_RECONCILE_BD_CACHE="$CACHE"; bd_cache_clear
bd_anchor_children tk-old closed >/dev/null
nid2=$(bd_create_child tk-old "a closed child" -t task --metadata '{"anchor_bead":"tk-old","task_kind":"review"}' --status=closed --json | jq -r '.id')
eq "$(ids_of "$(bd_anchor_children tk-old closed)")" "$nid2" "cache: a child created in the pass is read in the same pass"
unset GC_RECONCILE_BD_CACHE
: > "$STUB_KV"

# --- bd_anchor_backfill: join what the edge read does not reach -----------------
store '[
  {"id":"tk-old","status":"open","metadata":{"merge_result":"pull_request"}},
  {"id":"tk-o1","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-o2","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"finding"}},
  {"id":"tk-o3","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"rework"}},
  {"id":"tk-ok","status":"closed","metadata":{"anchor_bead":"tk-old","task_kind":"review"}},
  {"id":"tk-ov","status":"open","metadata":{"anchor_bead":"tk-old","task_kind":"visit"}},
  {"id":"tk-cv","status":"open","metadata":{}}
]'
printf '%s\n' 'tk-ok|related|tk-old' 'tk-ov|tracks|tk-old' 'tk-cv|tracks|tk-old' 'tk-o2|blocks|tk-old' > "$STUB_DEPS"
before=$(edges)
reset_log
out=$(bd_anchor_backfill tk-old --check); rc=$?
eq "$rc" 0 "backfill --check reads the anchor"
eq "$(printf '%s\n' "$out" | paste -sd, -)" "tk-o1,tk-o2,tk-o3" \
  "…naming each child its edge read does not reach, closed or live, and not one on the pair by another type"
eq "$(edges)" "$before" "…and writes nothing"
reset_log
out=$(bd_anchor_backfill tk-old); rc=$?
eq "$rc:$(printf '%s\n' "$out" | paste -sd, -)" "0:tk-o1,tk-o2,tk-o3" "backfill joins them and names them"
eq "$(dep_adds)" 1 "…in one write"
eq "$(edges)" "tk-cv|tracks|tk-old tk-o1|related|tk-old tk-o2|blocks|tk-old tk-o2|related|tk-old tk-o3|related|tk-old tk-ok|related|tk-old tk-ov|tracks|tk-old" \
  "…each child on the pair once, the visit left on its tracks edge"
out=$(bd_anchor_backfill tk-old); rc=$?
eq "$rc:$out" "0:" "a second backfill joins nothing"
# bd refuses the one-transaction write when one pair is refused; each pair is
# then joined alone, so the refused pair costs only itself.
printf '%s\n' 'tk-ok|related|tk-old' 'tk-ov|tracks|tk-old' > "$STUB_DEPS"
out=$(STUB_DEP_ADD_FAIL=tk-o2 bd_anchor_backfill tk-old 2>"$TMP/bf.err"); rc=$?
eq "$rc" 1 "backfill reports a pair bd refused"
eq "$(printf '%s\n' "$out" | paste -sd, -)" "tk-o1,tk-o3" "…after joining every other child pair by pair"
eq "$(grep -c '|related|' "$STUB_DEPS")" 3 "…so the refused pair is the only one left out"
has "$(cat "$TMP/bf.err")" "could not join tk-o2 to anchor tk-old" "…naming the refused pair"
has "$(cat "$TMP/bf.err")" "simulated refusal for tk-o2" "…with bd's reason"
export STUB_DEP_PARTIAL=1
bd_anchor_backfill tk-old >/dev/null 2>&1; rc=$?
unset STUB_DEP_PARTIAL
eq "$rc" 2 "backfill exits 2 when a read does not answer"

# --- bd_live_children: one read, the live children grouped by anchor ----------
store '[
  {"id":"tk-r2","status":"open","metadata":{"anchor_bead":"tk-anc","task_kind":"review"}},
  {"id":"tk-f1","status":"in_progress","metadata":{"anchor_bead":"tk-anc","task_kind":"finding"}},
  {"id":"tk-w1","status":"blocked","metadata":{"anchor_bead":"tk-two","task_kind":"rework"}},
  {"id":"tk-v1","status":"open","metadata":{"anchor_bead":"tk-two","task_kind":"validation"}},
  {"id":"tk-c1","status":"closed","metadata":{"anchor_bead":"tk-anc","task_kind":"rework"}},
  {"id":"tk-x1","status":"open","metadata":{"task_kind":"rework"}},
  {"id":"tk-e1","status":"open","metadata":{"anchor_bead":""}}
]'
reset_log
lc=$(bd_live_children); rc=$?
eq "$rc" 0 "bd_live_children reads the store"
eq "$(printf '%s\n' "$lc" | sort | paste -sd';' -)" "tk-anc	tk-f1,tk-r2	0;tk-two	tk-v1,tk-w1	1" \
  "one line per anchor: its live child ids sorted, and whether a rework child is among them"
eq "$(list_calls)" 1 "…in one read of the store"
export STUB_LIST_FAIL=1
lc=$(bd_live_children); rc=$?
unset STUB_LIST_FAIL
[ "$rc" -ne 0 ] && ok "an unreadable store is reported non-zero" || bad "an unreadable store read as no children"
eq "$lc" "" "…with nothing printed, so no caller reads it as no children"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
