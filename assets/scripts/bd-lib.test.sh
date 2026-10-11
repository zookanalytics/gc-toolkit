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

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
