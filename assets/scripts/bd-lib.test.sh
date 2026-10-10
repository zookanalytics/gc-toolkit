#!/usr/bin/env bash
# bd-lib.test.sh — hermetic tests for the bd_list memoization and the
# bd_live_children read.
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

# --- bd_live_children: one read, the live children grouped by anchor ----------
unset GC_RECONCILE_BD_CACHE
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
has "$(cat "$TMP/err")" "landed without its metadata and was closed" "…and stderr says so"

# A bead with some keys right and some wrong is left open and reported.
store '[]'
id=$(STUB_DROP_KEYS="new-1:check_name" bd_create "$META" "partial" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create: a partial read-back returns 2, prints the id and leaves the bead open"
has "$(cat "$TMP/err")" "did not read back as written (partial)" "…and stderr names the partial read-back"

# A read-back that fails proves nothing about the bead, so nothing is closed.
store '[]'
id=$(STUB_SHOW_FAIL=1 bd_create "$META" "unread" -t task 2>"$TMP/err"); rc=$?
eq "$rc|$id|$(bstatus new-1)" "2|new-1|open" "bd_create: an unreadable read-back returns 2, prints the id and closes nothing"
has "$(cat "$TMP/err")" "(unreadable)" "…and stderr names the unreadable read-back"

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
has "$(grep '^bd update new-1' "$STUB_GC_LOG")" "--db /x/.beads" "…and so does the close of a bare bead"
store '[]'; reset_log
id=$(bd_create "$META" "pinned" -t task --db=/y/.beads)
has "$(grep '^bd show new-1' "$STUB_GC_LOG")" "--db /y/.beads" "…the --db=<path> spelling too"

# A create changes what a list answers, so the per-pass cache is dropped.
export GC_RECONCILE_BD_CACHE="$CACHE"; mkdir -p "$CACHE"; bd_cache_clear
store '[]'
bd_list --status=open >/dev/null
eq "$(cache_files)" 1 "bd_create: (a cached list before the create)"
id=$(bd_create "$META" "cache" -t task)
eq "$(cache_files)" 0 "bd_create: the create drops the per-pass bd_list cache"
unset GC_RECONCILE_BD_CACHE

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
