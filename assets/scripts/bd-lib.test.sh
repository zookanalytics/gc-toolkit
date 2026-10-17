#!/usr/bin/env bash
# bd-lib.test.sh — hermetic tests for the bd_list memoization, the anchor
# graph reads and writes (bd_anchor_children, bd_anchor_link, bd_create_child,
# bd_anchor_backfill, bd_live_children), and the per-rig state key, the pass
# lock and pass_child (state_key, rig_state_key, take_pass_lock, pass_child).
#
# The cache is off unless GC_RECONCILE_BD_CACHE names a directory, and the
# refinery-reconcile order is its only caller (it clears per arm and removes the
# dir at END). harness_init unsets every GC_* var, so each cache case exports the
# variable after setup. Call counts come from STUB_GC_LOG, where the stub gc logs
# every invocation one per line; a `gc bd list` logs a line starting `bd list`.
#
# row_meta, the metadata read the library shares with every script that sources
# it, is pinned first; it reads no store.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bd-lib-test.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
. "$HERE/test-harness.sh"
harness_init
. "$HERE/bd-lib.sh"

# --- row_meta: one metadata value off a show row, as a string -----------------
ROW='[{"id":"tk-m","metadata":{"branch":"polecat/tk-m","pr_number":42,"gc.routed_to":"rig/pool"}}]'
eq "$(row_meta "$ROW" branch)" "polecat/tk-m" "row_meta reads a metadata value"
eq "$(row_meta "$ROW" pr_number)" "42" "…a number as its string"
eq "$(row_meta "$ROW" gc.routed_to)" "rig/pool" "…a dotted key whole"
eq "$(row_meta "$ROW" target)" "" "…an absent key as empty"
eq "$(row_meta '{"error":"no issues found"}' branch)" "" "…and a row that is not a show array as empty"

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

# --- bd_create: the metadata rides the create, and is read back -------------
# The stub mints new-<store length + 1>, keeps --metadata with its JSON types,
# and applies STUB_DROP_KEYS to the keys of the bead it mints.
create_calls() { grep -c '^bd create' "$STUB_GC_LOG" 2>/dev/null; }
update_calls() { grep -c '^bd update' "$STUB_GC_LOG" 2>/dev/null; }
META='{"task_kind":"review","anchor_bead":"tk-anc","check_name":"triage"}'
store '[]'; reset_log
id=$(bd_create "$META" "Review branch b -> main (triage): t" -t task 2>"$TMP/err"); rc=$?
eq "$rc" 0 "bd_create: a create whose metadata reads back returns 0"
eq "$id" "new-1" "…and prints the new id"
eq "$(meta new-1 task_kind)|$(meta new-1 anchor_bead)|$(meta new-1 check_name)" "review|tk-anc|triage" \
  "…and the bead carries every key of the payload"
eq "$(create_calls)" 1 "…filed by one create"
eq "$(update_calls)" 0 "…with no second write to stamp it"
has "$(grep '^bd create' "$STUB_GC_LOG")" '--metadata {"task_kind":"review","anchor_bead":"tk-anc","check_name":"triage"}' \
  "…and the payload is carried on the create itself"
eq "$(cat "$TMP/err")" "" "…and says nothing on stderr"

# A body on stdin reaches the create, so --body-file - works through the helper.
store '[]'
id=$(printf 'the body\n' | bd_create "$META" "with body" -t task --body-file -); rc=$?
eq "$rc|$(jq -r '.[0].description' "$STUB_STORE")" "0|the body" "bd_create: --body-file - reads the caller's stdin"

# --status and --notes ride the same create.
store '[]'
id=$(bd_create '{"task_kind":"review"}' "closed at birth" -t task --status=closed --notes "n1"); rc=$?
eq "$rc|$(bstatus new-1)|$(notes new-1)" "0|closed|n1" "bd_create: --status and --notes pass through to the one create"

# A payload that is not a JSON object with a key is refused before any create.
for bad_meta in '' '{}' '[]' '"x"' '{' 'null'; do
  store '[]'; reset_log
  out=$(bd_create "$bad_meta" "never" -t task 2>&1); rc=$?
  eq "$rc|$(create_calls)" "1|0" "bd_create: payload '$bad_meta' is refused and nothing is created"
done
has "$out" "refusing to file a bead without a metadata object" "…and the refusal says why"

# A create bd refuses: nothing filed, nothing printed, and the reason is reported.
store '[]'
id=$(STUB_CREATE_FAIL=1 bd_create "$META" "refused" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(jq 'length' "$STUB_STORE")" "1||0" "bd_create: a refused create returns 1, prints no id and files nothing"
has "$(cat "$TMP/err")" "bd create returned no id" "…and stderr says no id came back"

# bd answers a refusal as {"error": ...}; its reason reaches stderr.
cat > "$TMP/gc-refuse" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = bd ] && [ "${2:-}" = create ]; then echo '{"error":"title too long"}'; exit 1; fi
exec "$REAL_GC" "$@"
SHIM
chmod +x "$TMP/gc-refuse"
mkdir -p "$TMP/refuse-bin"; ln -sf "$TMP/gc-refuse" "$TMP/refuse-bin/gc"
store '[]'
id=$(REAL_GC="$(command -v gc)" PATH="$TMP/refuse-bin:$PATH" bd_create "$META" "x" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id" "1|" "bd_create: an error answer returns 1 with no id"
has "$(cat "$TMP/err")" "bd create returned no id: title too long" "…and names bd's own reason"

# A reply with no id can still be a bead that landed. It landed with its
# metadata, so the caller's own lookup by that metadata finds it.
store '[]'
id=$(STUB_CREATE_GARBAGE=1 bd_create "$META" "lost reply" -t task 2>/dev/null); rc=$?
eq "$rc|$id" "1|" "bd_create: a lost reply returns 1 with no id"
eq "$(meta new-1 anchor_bead)" "tk-anc" "…yet the bead that landed carries its metadata, findable by it"

# A bead that reads back with none of its keys is closed, so no reader meets it.
store '[]'; reset_log
id=$(STUB_DROP_KEYS="new-1:task_kind,anchor_bead,check_name" bd_create "$META" "bare" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id" "1|" "bd_create: a bead that landed bare returns 1 and prints no id"
eq "$(bstatus new-1)|$(meta new-1 gc.outcome)" "closed|abandoned" "…and is closed as abandoned"
has "$(notes new-1)" "Unmade by bd_create" "…with a note naming why"
has "$(cat "$TMP/err")" "did not read back carrying task_kind,anchor_bead,check_name, so no reader could find it; closed it" "…and stderr says so"
eq "$(update_calls)" 2 "…after one write of the whole payload that did not land either, then the close"

# A bead with some keys right and some wrong is left open and reported.
store '[]'
id=$(STUB_DROP_KEYS="new-1:check_name" bd_create "$META" "partial" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create: a partial read-back returns 2, prints the id and leaves the bead open"
has "$(cat "$TMP/err")" "did not read back as written (short: check_name)" "…and stderr names the key it is short of"

# A create whose metadata half-landed is written the whole payload once more, and
# a write that lands makes it whole. The shim drops DROP_ON_CREATE from the
# create's --metadata only, so the second write is the one that lands it.
cat > "$TMP/gc-dropcreate" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = bd ] && [ "${2:-}" = create ]; then
  args=()
  while [ $# -gt 0 ]; do
    if [ "$1" = --metadata ]; then
      args+=(--metadata "$(printf '%s' "$2" | jq -c --arg k "$DROP_ON_CREATE" 'del(.[($k | split(","))[]])')"); shift 2; continue
    fi
    args+=("$1"); shift
  done
  exec "$REAL_GC" "${args[@]}"
fi
exec "$REAL_GC" "$@"
SHIM
chmod +x "$TMP/gc-dropcreate"
mkdir -p "$TMP/dropcreate-bin"; ln -sf "$TMP/gc-dropcreate" "$TMP/dropcreate-bin/gc"
dropcreate() { REAL_GC="$(command -v gc)" PATH="$TMP/dropcreate-bin:$PATH" "$@"; }
store '[]'; reset_log
id=$(DROP_ON_CREATE=check_name dropcreate bd_create "$META" "repaired" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id" "0|new-1" "bd_create: a create short of a key that one more write lands returns 0 and prints the id"
eq "$(meta new-1 check_name)|$(bstatus new-1)" "triage|open" "…and the bead carries the key, open"
eq "$(update_calls)" 1 "…written in one update"
eq "$(cat "$TMP/err")" "" "…and says nothing on stderr"
store '[]'; reset_log
id=$(DROP_ON_CREATE=task_kind,anchor_bead,check_name dropcreate bd_create "$META" "bare at birth" -t task 2>/dev/null); rc=$?
eq "$rc|$id|$(meta new-1 anchor_bead)" "0|new-1|tk-anc" "…a bead that landed bare is written whole too, and kept once it reads back"

# --select names the keys the caller's probe finds the bead by. A bead still
# short of one after the second write is one no later run can find, so it is
# closed and nothing is filed. Short of another key, it is left open for the
# caller's next run, which finds it by the selected keys.
store '[]'; reset_log
id=$(STUB_DROP_KEYS="new-1:anchor_bead" bd_create --select task_kind,anchor_bead "$META" "unfindable" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id" "1|" "bd_create --select: a bead short of a selected key returns 1 and prints no id"
eq "$(bstatus new-1)|$(meta new-1 gc.outcome)" "closed|abandoned" "…and is closed as abandoned"
has "$(notes new-1)" "did not read back carrying anchor_bead" "…with a note naming the key"
has "$(cat "$TMP/err")" "did not read back carrying anchor_bead, so no reader could find it; closed it" "…and stderr says so"
store '[]'
id=$(STUB_DROP_KEYS="new-1:check_name" bd_create --select task_kind,anchor_bead "$META" "findable" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create --select: a bead short only of an unselected key returns 2 and stays open"
store '[]'
id=$(STUB_DROP_KEYS="new-1:anchor_bead" bd_create "$META" "no select" -t task 2>/dev/null); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create: with no --select, a bead short of some keys returns 2 and stays open"
store '[]'; reset_log
id=$(STUB_DROP_KEYS="new-1:anchor_bead" STUB_SHOW_FAIL=1 bd_create --select anchor_bead "$META" "unread" -t task 2>/dev/null); rc=$?
eq "$rc|$id|$(bstatus new-1)|$(update_calls)" "2|new-1|open|0" \
  "bd_create --select: a bead that does not read back is not judged unfindable: 2, open, and nothing written"
store '[]'; reset_log
out=$(bd_create --select task_kind,branch "$META" "never" -t task 2>&1); rc=$?
eq "$rc|$(create_calls)" "1|0" "bd_create --select: a key the payload does not carry is refused before any create"
has "$out" "names a key the payload does not carry" "…and the refusal says why"

# A read-back that fails proves nothing about the bead, so nothing is closed.
store '[]'; reset_log
id=$(STUB_SHOW_FAIL=1 bd_create "$META" "unread" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create: an unreadable read-back returns 2, prints the id and closes nothing"
eq "$(update_calls)" 0 "…and writes nothing"
has "$(cat "$TMP/err")" "(short: unreadable)" "…and stderr names the unreadable read-back"

# Values compare as text: a number written into the payload matches the same
# number read back as a string.
cat > "$TMP/stringify" <<'HOOK'
#!/usr/bin/env bash
tmp="$(mktemp "${STUB_STORE%/*}/.hook.XXXXXX")"
jq -c 'map(.metadata |= (if type == "object" then with_entries(.value |= tostring) else . end))' "$STUB_STORE" > "$tmp" && mv "$tmp" "$STUB_STORE"
HOOK
chmod +x "$TMP/stringify"
store '[]'
id=$(STUB_SHOW_HOOK="$TMP/stringify" bd_create '{"task_kind":"rework","pr_number":42}' "typed" -t task); rc=$?
eq "$rc|$(jq -r '.[0].metadata.pr_number | type' "$STUB_STORE")" "0|string" \
  "bd_create: a number in the payload matches the same value read back as text"

# --db sends the read-back and the close to the store the create wrote.
store '[]'; reset_log
id=$(STUB_DROP_KEYS="new-1:task_kind,anchor_bead,check_name" bd_create "$META" "pinned" -t task --db /x/.beads 2>/dev/null)
has "$(grep '^bd show new-1' "$STUB_GC_LOG")" "--db /x/.beads" "bd_create: the read-back carries the create's --db"
eq "$(grep -c '^bd update new-1.*--db /x/.beads' "$STUB_GC_LOG")" 2 "…and so do the second write and the close of a bare bead"
store '[]'; reset_log
id=$(bd_create "$META" "pinned" -t task --db=/y/.beads)
has "$(grep '^bd show new-1' "$STUB_GC_LOG")" "--db /y/.beads" "…the --db=<path> spelling too"

# --child-of files the bead as a child of its anchor: the membership edge rides
# the one create (bd_create_child), so the child is born joined or not filed.
ANC='[{"id":"tk-anc","status":"open","assignee":"","title":"anchor","notes":"","metadata":{}}]'
store "$ANC"; : > "$STUB_DEPS"; reset_log
id=$(bd_create --select task_kind,anchor_bead --child-of tk-anc "$META" "child" -t task --deps "blocks:tk-anc" 2>"$TMP/err"); rc=$?
eq "$rc|$id" "0|new-2" "bd_create --child-of: a child whose metadata reads back returns 0 and prints its id"
eq "$(create_calls)" 1 "…filed by one create"
has "$(grep '^bd create' "$STUB_GC_LOG")" "--deps related:tk-anc" "…which carries the membership edge"
grep -qxF "new-2|related|tk-anc" "$STUB_DEPS" && ok "…so the child depends on its anchor by that edge" || bad "the membership edge did not land"
grep -qxF "new-2|blocks|tk-anc" "$STUB_DEPS" && ok "…beside the caller's own --deps edge" || bad "the caller's --deps edge did not land"
store '[]'; : > "$STUB_DEPS"; reset_log
id=$(bd_create --child-of tk-anc "$META" "orphan" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(jq 'length' "$STUB_STORE")" "1||0" "bd_create --child-of: an anchor that does not resolve refuses the whole create"
store "$ANC"; reset_log
out=$(bd_create --child-of "" "$META" "never" -t task 2>&1); rc=$?
eq "$rc|$(create_calls)" "1|0" "bd_create --child-of '': refused before any create"
has "$out" "names no anchor" "…and the refusal says why"
store "$ANC"; reset_log
out=$(bd_create --child-of tk-other "$META" "never" -t task 2>&1); rc=$?
eq "$rc|$(create_calls)" "1|0" "bd_create --child-of: an anchor the payload's anchor_bead does not name is refused before any create"
has "$out" "is not the anchor_bead the payload names" "…and the refusal says why"
store "$ANC"; reset_log
out=$(bd_create --child-of 2>&1); rc=$?
eq "$rc|$(create_calls)" "1|0" "bd_create --child-of with no value: refused before any create"
store "$ANC"; reset_log
id=$(STUB_DROP_KEYS="new-2:anchor_bead" bd_create --child-of tk-anc --select anchor_bead "$META" "either order" -t task 2>/dev/null); rc=$?
eq "$rc|$id|$(bstatus new-2)" "1||closed" "bd_create: --child-of ahead of --select still applies the selection"

# A create changes what a list answers, so the per-pass cache is dropped.
export GC_RECONCILE_BD_CACHE="$CACHE"; mkdir -p "$CACHE"; bd_cache_clear
store '[]'
bd_list --status=open >/dev/null
eq "$(cache_files)" 1 "bd_create: (a cached list before the create)"
id=$(bd_create "$META" "cache" -t task)
eq "$(cache_files)" 0 "bd_create: the create drops the per-pass bd_list cache"
unset GC_RECONCILE_BD_CACHE

# --- bd_meta_readback: the verdict and the keys a bead is short of ------------
store '[{"id":"tk-m","status":"open","assignee":"","title":"m","notes":"","metadata":{"task_kind":"review","anchor_bead":"tk-anc","pr_number":42}}]'
eq "$(bd_meta_readback tk-m '{"task_kind":"review","anchor_bead":"tk-anc"}')" "landed	" \
  "bd_meta_readback: every key read back as written is landed, with no key named"
eq "$(bd_meta_readback tk-m '{"task_kind":"review","branch":"b","target":"main"}')" "partial	branch,target" \
  "…a missing key is partial, and the line names each key short, in the payload's order"
eq "$(bd_meta_readback tk-m '{"task_kind":"rework","anchor_bead":"tk-anc"}')" "partial	task_kind" \
  "…a key read back with another value is short too"
eq "$(bd_meta_readback tk-m '{"branch":"b","target":"main"}')" "bare	branch,target" \
  "…a bead carrying none of the payload's keys is bare"
eq "$(bd_meta_readback tk-m '{"pr_number":"42"}')" "landed	" \
  "…values compare as text, so a number read back matches the string written"
eq "$(bd_meta_readback tk-gone '{"task_kind":"review"}')" "unreadable	" "…a bead the store does not return is unreadable"
eq "$(STUB_SHOW_FAIL=1 bd_meta_readback tk-m '{"task_kind":"review"}')" "unreadable	" "…and so is a read that fails"

# false, null and true compare as their text too, so each reads back as itself
# whether bd kept it typed or as a string, and none of them reads as an empty
# value or a missing one.
store '[{"id":"tk-t","status":"open","assignee":"","title":"t","notes":"","metadata":{"f":false,"n":null,"t":true,"sf":"false","e":""}}]'
eq "$(bd_meta_readback tk-t '{"f":false,"n":null,"t":true}')" "landed	" \
  "bd_meta_readback: false, null and true read back typed are landed"
eq "$(bd_meta_readback tk-t '{"sf":false}')" "landed	" "…false matches the string false"
eq "$(bd_meta_readback tk-t '{"f":"false"}')" "landed	" "…and the string false matches false"
eq "$(bd_meta_readback tk-t '{"e":false}')" "partial	e" "…but false does not match an empty value"
eq "$(bd_meta_readback tk-t '{"e":null}')" "partial	e" "…nor does null"
eq "$(bd_meta_readback tk-t '{"f":""}')" "partial	f" "…and an empty string does not match false"
store '[{"id":"tk-u","status":"open","assignee":"","title":"u","notes":"","metadata":{}}]'
gc bd update tk-u --set-metadata f=false --set-metadata n=null >/dev/null
eq "$(bd_meta_readback tk-u '{"f":false,"n":null}')" "landed	" \
  "…and false and null written by --set-metadata read back landed"

# bd_meta_judge judges a reply the caller already holds, and reads nothing.
row='[{"id":"tk-r","metadata":{"task_kind":"review","anchor_bead":"tk-anc"}}]'
reset_log
eq "$(bd_meta_judge tk-r '{"task_kind":"review","check_name":"triage"}' "$row")" "partial	check_name" \
  "bd_meta_judge: a held reply is judged as bd_meta_readback judges a read"
eq "$(grep -c '^bd show' "$STUB_GC_LOG")" 0 "…with no read of its own"
eq "$(bd_meta_judge tk-other '{"task_kind":"review"}' "$row")" "unreadable	" "…a reply holding another bead is unreadable"
eq "$(bd_meta_judge tk-r '{"task_kind":"review"}' "")" "unreadable	" "…and so is an empty reply"
eq "$(bd_meta_judge tk-r '{"task_kind":"review"}' "not-json")" "unreadable	" "…and one no JSON reader parses"

# --- bd_meta_ensure: a bead is made whole before its caller hands it on ---------
WORK='{"task_kind":"rework","anchor_bead":"tk-anc","branch":"polecat/x","target":"main","pr_number":"7"}'
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc","branch":"polecat/x","target":"main","pr_number":"7"}}]'
reset_log
out=$(bd_meta_ensure tk-w "$WORK"); rc=$?
eq "$rc|$out|$(update_calls)" "0||0" "bd_meta_ensure: a bead already carrying the payload passes with no write"

store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc","gc.routed_to":""}}]'
reset_log
out=$(bd_meta_ensure tk-w "$WORK"); rc=$?
eq "$rc|$out" "0|" "bd_meta_ensure: a bead short of keys is written whole and passes once they read back"
eq "$(meta tk-w branch)|$(meta tk-w target)|$(meta tk-w pr_number)" "polecat/x|main|7" "…and now carries every key of the payload"
eq "$(update_calls)" 1 "…written in one update"
has "$(grep '^bd update tk-w' "$STUB_GC_LOG")" "--set-metadata task_kind=rework" "…which carries the keys already present as well"
eq "$(meta tk-w gc.routed_to)" "" "…and touches no key outside the payload"

store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc"}}]'
out=$(STUB_DROP_KEYS="tk-w:branch,pr_number" bd_meta_ensure tk-w "$WORK"); rc=$?
eq "$rc|$out" "1|branch,pr_number" "bd_meta_ensure: a write that does not land fails and names the keys still short"

reset_log
out=$(STUB_SHOW_FAIL=1 bd_meta_ensure tk-w "$WORK"); rc=$?
eq "$rc|$out" "1|unreadable" "bd_meta_ensure: a bead that does not read back fails as unreadable"
eq "$(update_calls)" 0 "…and is not written, since nothing shows who holds it"

# --row judges a reply the caller already read: a whole one passes with no read
# and no write, a short one is written and read back, and an unreadable one is
# refused with no write.
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{"task_kind":"rework","anchor_bead":"tk-anc"}}]'
reset_log
whole='[{"id":"tk-w","metadata":{"task_kind":"rework","anchor_bead":"tk-anc","branch":"polecat/x","target":"main","pr_number":"7"}}]'
out=$(bd_meta_ensure --row "$whole" tk-w "$WORK"); rc=$?
eq "$rc|$out|$(grep -c '^bd show' "$STUB_GC_LOG")|$(update_calls)" "0||0|0" \
  "bd_meta_ensure --row: a whole reply passes with no read and no write"
out=$(bd_meta_ensure --row "$(gc bd show tk-w --json)" tk-w "$WORK"); rc=$?
eq "$rc|$out|$(meta tk-w branch)" "0||polecat/x" "bd_meta_ensure --row: a short reply is written whole and read back"
reset_log
out=$(bd_meta_ensure --row "" tk-w "$WORK"); rc=$?
eq "$rc|$out|$(update_calls)" "1|unreadable|0" "bd_meta_ensure --row: an empty reply is unreadable, and nothing is written"

# The trailing arguments reach the read, the write and the read-back alike.
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{}}]'
reset_log
out=$(bd_meta_ensure tk-w "$WORK" --db /z/.beads); rc=$?
eq "$rc" 0 "bd_meta_ensure --db: the bead is made whole"
eq "$(grep -c '^bd show tk-w.*--db /z/.beads' "$STUB_GC_LOG")|$(grep -c '^bd update tk-w.*--db /z/.beads' "$STUB_GC_LOG")" "2|1" \
  "…with the read, the write and the read-back all sent to the store --db names"

# A value carrying '=' or a newline is one argument to --set-metadata.
store '[{"id":"tk-w","status":"open","assignee":"","title":"w","notes":"","metadata":{}}]'
out=$(bd_meta_ensure tk-w '{"rejection_reason":"Resume in prepare_mode=merge:\nsecond line"}'); rc=$?
eq "$rc|$(jq -r '.[0].metadata.rejection_reason' "$STUB_STORE")" "0|Resume in prepare_mode=merge:
second line" "bd_meta_ensure: a value with '=' and a newline is written whole"

# --- bd_unmake: a bead no reader can find is closed so it holds nothing --------
store '[{"id":"tk-x","status":"open","assignee":"","title":"x","notes":"","metadata":{}}]'
reset_log
bd_unmake tk-x "Unmade by test: why." --db /q/.beads; rc=$?
eq "$rc|$(bstatus tk-x)|$(meta tk-x gc.outcome)|$(notes tk-x)" "0|closed|abandoned|Unmade by test: why." \
  "bd_unmake: the bead is closed as abandoned with the note, and the call returns 0"
eq "$(grep -c '^bd update tk-x.*--db /q/.beads' "$STUB_GC_LOG")|$(grep -c '^bd show tk-x.*--db /q/.beads' "$STUB_GC_LOG")" "1|1" \
  "…in one write, read back from the store --db names"
store '[{"id":"tk-x","status":"open","assignee":"","title":"x","notes":"","metadata":{}}]'
STUB_DROP_KEYS="tk-x:status" bd_unmake tk-x "n"; rc=$?
eq "$rc|$(bstatus tk-x)" "1|open" "bd_unmake: a close that does not read back returns 1"
STUB_SHOW_FAIL=1 bd_unmake tk-x "n"; rc=$?
eq "$rc" 1 "…and so does one whose read-back fails"
export GC_RECONCILE_BD_CACHE="$CACHE"; mkdir -p "$CACHE"; bd_cache_clear
bd_list --status=open >/dev/null
bd_unmake tk-x "n" >/dev/null
eq "$(cache_files)" 0 "bd_unmake: the close drops the per-pass bd_list cache"
unset GC_RECONCILE_BD_CACHE

# --- bd_unmake_orphans: what a stamp-after-create producer left behind ---------
# Only an open bead with the title that nobody has taken and that is short of a
# selected key is closed; a whole bead, one someone holds, routed, poured or in
# flight, and one with another title are left alone.
store '[
  {"id":"tk-o1","status":"open","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{}},
  {"id":"tk-o2","status":"open","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{"task_kind":"review","anchor_bead":""}},
  {"id":"tk-w1","status":"open","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{"task_kind":"review","anchor_bead":"tk-anc"}},
  {"id":"tk-h1","status":"open","assignee":"lx-1","title":"Review branch b -> main (triage): t","notes":"","metadata":{}},
  {"id":"tk-r1","status":"open","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{"gc.routed_to":"pool"}},
  {"id":"tk-p1","status":"open","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{"gc.execution_routed_to":"pool"}},
  {"id":"tk-i1","status":"in_progress","assignee":"","title":"Review branch b -> main (triage): t","notes":"","metadata":{}},
  {"id":"tk-c1","status":"open","assignee":"","title":"Review branch b -> main (correctness): t","notes":"","metadata":{}}
]'
out=$(bd_unmake_orphans task_kind,anchor_bead "Review branch b -> main (triage):" "Unmade by test: orphan."); rc=$?
eq "$rc|$(printf '%s' "$out" | paste -sd, -)" "0|tk-o1,tk-o2" "bd_unmake_orphans: returns 0 and prints each bead it closed"
eq "$(bstatus tk-o1)|$(meta tk-o1 gc.outcome)|$(bstatus tk-o2)" "closed|abandoned|closed" \
  "…a bead short of every selected key and one with a selected key empty are closed as abandoned"
eq "$(bstatus tk-w1)|$(bstatus tk-h1)|$(bstatus tk-r1)|$(bstatus tk-p1)|$(bstatus tk-i1)|$(bstatus tk-c1)" \
  "open|open|open|open|in_progress|open" "…a whole bead, a held, routed, poured or in-flight one, and another title are left alone"
out=$(STUB_LIST_FAIL=1 bd_unmake_orphans task_kind "Review branch" "n"); rc=$?
eq "$rc|$out" "1|" "bd_unmake_orphans: a listing that does not answer returns 1 and closes nothing"

# --- validation_work_order: the shape mol-validate reads ----------------------
eq "$(validation_work_order tk-anc correctness abc123)" \
  '{"task_kind":"validation","anchor_bead":"tk-anc","check_name":"correctness","reviewed_oid":"abc123"}' \
  "validation_work_order: task_kind, anchor, lane and the reviewed head"
eq "$(validation_work_order tk-anc human "")" '{"task_kind":"validation","anchor_bead":"tk-anc","check_name":"human"}' \
  "…and an empty head leaves the pin out"
eq "$(printf '%s' "$(validation_work_order tk-anc human x)" | jq -r --arg s "$VALIDATION_SELECT" '. as $m | $s | split(",") | all(.[]; . as $k | $m | has($k))')" "true" \
  "…carrying every key VALIDATION_SELECT names"

# --- state_key: one directory name per identity --------------------------------
ck() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
eq "$(state_key gc-toolkit gc-toolkit)" "gc-toolkit" "state_key: a safe name that is its own identity is used as it is"
eq "$(state_key 'a/b' 'a/b')" "a_b-$(ck 'a/b')" "…a name with a character outside the safe set is its safe form and a checksum"
eq "$(state_key 'a_b' 'a_b')" "a_b" "…so it never lands on the name its safe form spells"
eq "$(state_key '..' '..')" "rig-$(ck '..')" "…a name that would climb out of its directory reads as rig"
eq "$(state_key '' '')" "rig-$(ck '')" "…and so does an empty one"
LONG="$(printf '%070d' 0 | tr 0 x)"
eq "$(state_key "$LONG" "$LONG")" "$(printf '%064d' 0 | tr 0 x)-$(ck "$LONG")" "…a name longer than 64 bytes is cut to 64, then the checksum"
eq "$(state_key dup /one/dup)" "dup-$(ck /one/dup)" "…and a name that reads other than its identity carries the identity's checksum"

# --- rig_state_key: GC_RIG, else the rig root, else _unscoped -----------------
eq "$(GC_RIG=gc-toolkit GC_RIG_ROOT=/x/gc-toolkit rig_state_key)" "gc-toolkit" "rig_state_key: GC_RIG names the rig"
eq "$(GC_RIG_ROOT=/one/dup rig_state_key)" "dup-$(ck /one/dup)" "…with only GC_RIG_ROOT, the root's last element and a checksum of the whole root"
[ "$(GC_RIG_ROOT=/one/dup rig_state_key)" != "$(GC_RIG_ROOT=/two/dup rig_state_key)" ] \
  && ok "…so two roots that end in one name keep apart" || bad "two roots that end in one name share a key"
eq "$(GC_RIG_ROOT=/one/dup/ rig_state_key)" "dup-$(ck /one/dup/)" "…a trailing slash still reads the last element"
eq "$(rig_state_key)" "_unscoped" "…and with neither the key is _unscoped"

# --- take_pass_lock: one pass at a time ------------------------------------------
lock_free() { ( exec 8>>"$1/pass.lock"; flock -n 8 ) 2>/dev/null; }
await_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done; [ -e "$1" ]; }
LD="$TMP/locks/rig"
out=$(take_pass_lock "$LD" 60; rc=$?
      printf 'rc=%s note=%s\n' "$rc" "$LOCK_NOTE"
      if lock_free "$LD"; then echo held=no; else echo held=yes; fi
      if { : >&9; } 2>/dev/null; then echo fd9=open; else echo fd9=closed; fi)
has "$out" "rc=0 note=" "take_pass_lock: a free lock is taken (0)"
has "$out" "held=yes" "…and held while the process that took it runs"
has "$out" "fd9=open" "…on fd 9"
read -r hpid hsince < "$LD/pass.holder"
eq "$hpid" "$$" "…recording the pid of the process that took it"
case "$hsince" in ''|*[!0-9]*) bad "…and when it took it (got '$hsince')" ;; *) ok "…and when it took it" ;; esac
lock_free "$LD" && ok "…and freed once that process exits" || bad "the lock outlived the process that took it"
( exec 9>>"$LD/pass.lock"; flock -n 9 || exit 1; : > "$TMP/lock-held"
  i=0; while [ ! -e "$TMP/lock-release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done ) </dev/null >/dev/null 2>&1 &
LH=$!
if await_file "$TMP/lock-held"; then
  printf '%s %s\n' "$LH" "$(( $(date -u +%s) - 5 ))" > "$LD/pass.holder"
  out=$(take_pass_lock "$LD" 60; rc=$?
        printf 'rc=%s note=%s\n' "$rc" "$LOCK_NOTE"
        if { : >&9; } 2>/dev/null; then echo fd9=open; else echo fd9=closed; fi)
  has "$out" "rc=1 note=pid $LH, " "take_pass_lock: a lock another pass took inside the stall bound is busy (1), naming that pass"
  has "$out" "s elapsed" "…and how long it has held the lock"
  has "$out" "fd9=closed" "…and a busy lock leaves no descriptor open"
  printf '%s 1\n' "$LH" > "$LD/pass.holder"
  eq "$(take_pass_lock "$LD" 60; echo "rc=$?")" "rc=2" "…one taken longer ago than the stall bound is stalled (2)"
  rm -f "$LD/pass.holder"
  eq "$(take_pass_lock "$LD" 60; echo "rc=$? note=$LOCK_NOTE")" "rc=1 note=pid unknown" "…and a holder that left no record is busy, by an unknown pid"
else
  bad "the holder fixture never took the lock"
fi
: > "$TMP/lock-release"; wait "$LH" 2>/dev/null
mkdir -p "$TMP/noflock"
eq "$(PATH="$TMP/noflock" take_pass_lock "$LD" 60; echo "rc=$? note=$LOCK_NOTE")" "rc=3 note=flock not found on PATH" \
  "take_pass_lock: with no flock on PATH there is no lock (3)"
mkdir -p "$TMP/locks/blocked/pass.lock"
eq "$(take_pass_lock "$TMP/locks/blocked" 60; echo "rc=$? note=$LOCK_NOTE")" "rc=3 note=cannot create $TMP/locks/blocked/pass.lock" \
  "…nor with a lock file that cannot be created"

# --- pass_child: nothing a pass runs holds the lock after it ----------------------
eq "$(pass_child sh -c 'exit 7'; echo "$?")" "7" "pass_child: returns the program's status"
# A pass that takes the lock and runs one program through pass_child. The
# program records whether it was handed fd 9, leaves a process running that
# keeps every descriptor it has, and waits for its release.
cat > "$TMP/pass.sh" <<'PASS'
. "$1"
take_pass_lock "$2" 60 || exit 9
pass_child "$3"
PASS
cat > "$TMP/prog.sh" <<'PROG'
#!/usr/bin/env bash
if { : >&9; } 2>/dev/null; then echo open; else echo closed; fi > "$PROG_DIR/fd9"
( exec sleep 300 ) </dev/null >/dev/null 2>&1 &
echo "$!" > "$PROG_DIR/daemon"
: > "$PROG_DIR/started"
i=0; while [ ! -e "$PROG_DIR/release" ] && [ "$i" -lt 6000 ]; do sleep 0.05; i=$((i + 1)); done
PROG
chmod +x "$TMP/prog.sh"
export PROG_DIR="$TMP/prog"; mkdir -p "$PROG_DIR"
LC="$TMP/locks/child"
bash "$TMP/pass.sh" "$HERE/bd-lib.sh" "$LC" "$TMP/prog.sh" </dev/null >/dev/null 2>&1 &
PP=$!
if await_file "$PROG_DIR/started"; then
  eq "$(cat "$PROG_DIR/fd9")" "closed" "pass_child: the program runs without fd 9"
  kill -9 "$PP" 2>/dev/null; wait "$PP" 2>/dev/null
  lock_free "$LC" && bad "killing the pass by itself freed the lock while its program ran on" \
    || ok "…the lock stays held while it runs, though the pass that started it was killed"
  : > "$PROG_DIR/release"
  i=0; while ! lock_free "$LC" && [ "$i" -lt 400 ]; do sleep 0.05; i=$((i + 1)); done
  lock_free "$LC" && ok "…and is freed once the program exits" || bad "the lock outlived the program pass_child ran"
  dpid="$(cat "$PROG_DIR/daemon" 2>/dev/null)"
  if [ -n "$dpid" ] && kill -0 "$dpid" 2>/dev/null; then
    ok "…while the process the program left behind still runs, holding no lock"
  else
    bad "the process the program leaves behind never ran, so nothing about it was proven"
  fi
  [ -n "$dpid" ] && kill "$dpid" 2>/dev/null
else
  bad "the pass fixture never started its program"
  : > "$PROG_DIR/release"; kill -9 "$PP" 2>/dev/null; wait "$PP" 2>/dev/null
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
