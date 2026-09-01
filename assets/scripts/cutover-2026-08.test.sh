#!/usr/bin/env bash
# Hermetic test for assets/scripts/cutover-2026-08.sh `sweep` (stub harness).
# Pins: dry-run writes nothing; --apply strips exactly the healer keys each
# bead carries; molecule retirement closes unblocked-first across passes with
# the root last, and never touches the work bead the molecule drives
# (metadata.branch survives); the closed-bead decision table — MERGED records
# merged+merged_sha, an unreadable mergeCommit records unverified:PR#<n>,
# CLOSED records abandoned, OPEN is reported LOUDLY with no write; the
# merged-with-no-sha sentinel unverified:pre-rewrite; idempotence (a second
# --apply run performs zero writes).
# No live city, Dolt, network, gc, bd or gh — stubs from test-harness.sh plus
# thin `gc rig list` / bare-`bd` shims.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/cutover-2026-08.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# grep -q fed by a here-string, never a pipe (pipefail eats the match).
hasin() { grep -q -- "$2" <<< "$1"; }
lineof() { grep -n -- "$1" "$STUB_GC_LOG" | head -n 1 | cut -d: -f1; }

# The SUT enumerates rigs via `gc rig list` and reaches each store with
# `gc bd ... --db <path>`; shim both onto the harness gc stub, which ignores
# the --db it is handed because each run already points at one fixture store.
mkdir -p "$TMP/bin2" "$TMP/rig"
export STUB_RIGS="$TMP/rigs.json"
printf '{"rigs":[{"name":"gc-toolkit","path":"%s"}]}\n' "$TMP/rig" > "$STUB_RIGS"
cat > "$TMP/bin2/gc" <<SHIM
#!/usr/bin/env bash
if [ "\${1:-}" = "rig" ] && [ "\${2:-}" = "list" ]; then cat "\$STUB_RIGS"; exit 0; fi
exec "$BIN/gc" "\$@"
SHIM
cat > "$TMP/bin2/bd" <<'SHIM'
#!/usr/bin/env bash
# The SUT reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches.
echo "stub bd: called directly, not through gc bd" >&2; exit 127
SHIM
chmod +x "$TMP/bin2/gc" "$TMP/bin2/bd"
export PATH="$TMP/bin2:$PATH"

# Fixture: healer-carrying beads, one molecule (root + chained steps + control),
# the work bead it drives, and the closed-anchor decision table.
store '[
 {"id":"hb-1","status":"open","assignee":"","title":"anchor with healer keys","metadata":{"check_set_healed":"1","stale_gate_head":"abc","branch":"feat/hb1"}},
 {"id":"hb-2","status":"open","assignee":"","title":"bead with one healer key","metadata":{"reconcile_rig":"gc-toolkit"}},
 {"id":"root-m","status":"open","assignee":"","title":"mol-polecat-work root","metadata":{"gc.kind":"workflow"}},
 {"id":"s1","status":"open","assignee":"","title":"load context","metadata":{"gc.root_bead_id":"root-m"}},
 {"id":"s2","status":"open","assignee":"","title":"implement","metadata":{"gc.root_bead_id":"root-m"}},
 {"id":"c1","status":"open","assignee":"","title":"finalize control","metadata":{"gc.root_bead_id":"root-m","gc.kind":"workflow-finalize"}},
 {"id":"work-1","status":"open","assignee":"gc-toolkit.polecat","title":"the driven work bead","metadata":{"branch":"feat/work","merge_result":"pre_open_gate"}},
 {"id":"cb-merged","status":"closed","assignee":"","title":"closed over merged PR","metadata":{"merge_result":"pull_request","pr_number":"101","pr_url":"https://github.com/zook/gc-toolkit/pull/101"}},
 {"id":"cb-unv","status":"closed","assignee":"","title":"closed, merged PR, no mergeCommit","metadata":{"merge_result":"pull_request","pr_number":"102","pr_url":"https://github.com/zook/gc-toolkit/pull/102"}},
 {"id":"cb-closed","status":"closed","assignee":"","title":"closed over closed PR","metadata":{"merge_result":"pull_request","pr_number":"103","pr_url":"https://github.com/zook/gc-toolkit/pull/103"}},
 {"id":"cb-open","status":"closed","assignee":"","title":"closed over OPEN PR","metadata":{"merge_result":"pull_request","pr_number":"104","pr_url":"https://github.com/zook/gc-toolkit/pull/104"}},
 {"id":"cb-nopr","status":"closed","assignee":"","title":"closed pre_open_gate, no PR","metadata":{"merge_result":"pre_open_gate"}},
 {"id":"cb-nosha","status":"closed","assignee":"","title":"closed merged, no sha","metadata":{"merge_result":"merged","merged_sha":""}}
]'
printf 's1|blocks|s2\ns2|blocks|c1\n' >> "$STUB_DEPS"
echo '{"state":"MERGED","mergeCommit":{"oid":"deadbeefcafe1234"},"url":"https://github.com/zook/gc-toolkit/pull/101"}' > "$GH_DIR/pr_view_101.json"
echo '{"state":"MERGED","mergeCommit":null,"url":"https://github.com/zook/gc-toolkit/pull/102"}' > "$GH_DIR/pr_view_102.json"
echo '{"state":"CLOSED","url":"https://github.com/zook/gc-toolkit/pull/103"}' > "$GH_DIR/pr_view_103.json"
echo '{"state":"OPEN","url":"https://github.com/zook/gc-toolkit/pull/104"}' > "$GH_DIR/pr_view_104.json"

echo "# dry-run (the default) reports everything and writes NOTHING"
cp "$STUB_STORE" "$TMP/store.before"
out=$(bash "$SUT" sweep --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "dry-run exits 1 while operator items remain"
has "$out" "DRY-RUN" "dry-run announces itself"
has "$out" "would strip [check_set_healed,stale_gate_head] from open bead hb-1" "dry-run names hb-1's exact keys"
has "$out" "would strip [reconcile_rig] from open bead hb-2" "dry-run names hb-2's key"
has "$out" "would retire molecule root-m" "dry-run names the molecule"
has "$out" "would repair closed bead cb-merged" "dry-run names the MERGED repair"
has "$out" "OPERATOR DECISION REQUIRED" "dry-run reports the OPEN-PR bead loudly"
cmp -s "$STUB_STORE" "$TMP/store.before"; eq "$?" 0 "dry-run left the store byte-identical"
upd=$(grep -c '^bd update' "$STUB_GC_LOG" || true)
eq "$upd" 0 "dry-run issued zero bd updates"

echo
echo "# --apply: healer keys stripped, exactly the present ones"
: > "$STUB_GC_LOG"
out=$(bash "$SUT" sweep --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "apply still exits 1 (cb-open and cb-nopr need the operator)"
eq "$(meta hb-1 check_set_healed)" "<absent>" "hb-1 check_set_healed stripped"
eq "$(meta hb-1 stale_gate_head)" "<absent>" "hb-1 stale_gate_head stripped"
eq "$(meta hb-1 branch)" "feat/hb1" "hb-1 non-healer key survives"
eq "$(meta hb-2 reconcile_rig)" "<absent>" "hb-2 reconcile_rig stripped"
l=$(grep -- '^bd update hb-1 ' "$STUB_GC_LOG" | head -n 1)
eq "$(grep -o -- '--unset-metadata' <<< "$l" | wc -l | tr -d ' ')" "2" "hb-1 update unsets exactly its 2 present keys"
hasnt "$l" "merge_result_healed" "absent healer keys are not blind-unset"

echo
echo "# --apply: molecule retired unblocked-first over passes, root last"
eq "$(bstatus s1)" "closed" "step s1 closed"
eq "$(bstatus s2)" "closed" "step s2 closed"
eq "$(bstatus c1)" "closed" "control c1 closed"
eq "$(bstatus root-m)" "closed" "root closed"
eq "$(meta s2 gc.outcome)" "cutover-retired" "steps carry gc.outcome=cutover-retired"
eq "$(meta root-m gc.outcome)" "cutover-retired" "root carries gc.outcome=cutover-retired"
n1=$(lineof 'update s1 '); n2=$(lineof 'update s2 '); n3=$(lineof 'update c1 '); n4=$(lineof 'update root-m ')
[ -n "$n1" ] && [ -n "$n2" ] && [ "$n1" -lt "$n2" ]; eq "$?" 0 "s1 (unblocked) closed before s2 (blocked by s1)"
[ -n "$n3" ] && [ "$n2" -lt "$n3" ]; eq "$?" 0 "s2 closed before c1 (blocked by s2)"
[ -n "$n4" ] && [ "$n3" -lt "$n4" ]; eq "$?" 0 "root closed last"

echo
echo "# --apply: the WORK bead the molecule drives is untouched"
eq "$(bstatus work-1)" "open" "work bead still open"
eq "$(meta work-1 branch)" "feat/work" "work bead branch metadata survives"
eq "$(meta work-1 merge_result)" "pre_open_gate" "work bead merge_result survives"
eq "$(bassignee work-1)" "gc-toolkit.polecat" "work bead assignee survives"
hasnt "$(cat "$STUB_GC_LOG")" "update work-1" "no write ever aimed at the work bead"

echo
echo "# --apply: the closed-bead decision table"
eq "$(meta cb-merged merge_result)" "merged" "MERGED PR: merge_result repaired to merged"
eq "$(meta cb-merged merged_sha)" "deadbeefcafe1234" "MERGED PR: merged_sha recorded from mergeCommit"
eq "$(meta cb-unv merge_result)" "merged" "MERGED PR, no mergeCommit: still repaired"
eq "$(meta cb-unv merged_sha)" "unverified:PR#102" "MERGED PR, no mergeCommit: unverified:PR#<n> sentinel"
eq "$(meta cb-closed merge_result)" "abandoned" "CLOSED PR: repaired to abandoned"
eq "$(meta cb-open merge_result)" "pull_request" "OPEN PR: bead NOT written"
has "$out" "OPERATOR DECISION REQUIRED" "OPEN PR: reported loudly"
has "$out" "cb-open" "OPEN PR report names the bead"
hasnt "$(cat "$STUB_GC_LOG")" "update cb-open" "OPEN PR: zero writes aimed at the bead"
eq "$(meta cb-nopr merge_result)" "pre_open_gate" "no PR identity: bead NOT written"
has "$out" "NO PR identity" "no PR identity: reported for the operator"
eq "$(meta cb-nosha merged_sha)" "unverified:pre-rewrite" "merged with empty sha: pre-rewrite sentinel"

echo
echo "# idempotence: a second --apply run performs zero writes"
cp "$STUB_STORE" "$TMP/store.after1"
: > "$STUB_GC_LOG"
out=$(bash "$SUT" sweep --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 1 "second run still exits 1 (operator items are not silently forgotten)"
upd=$(grep -c '^bd update' "$STUB_GC_LOG" || true)
eq "$upd" 0 "second --apply run issued zero bd updates"
cmp -s "$STUB_STORE" "$TMP/store.after1"; eq "$?" 0 "second --apply run left the store byte-identical"

echo
echo "# once the operator resolves the leftovers, sweep exits 0 clean"
tmpf=$(mktemp); jq -c '
  map(if .id == "cb-open" then .metadata.merge_result = "merged" | .metadata.merged_sha = "fixedbyhand"
      elif .id == "cb-nopr" then .metadata.merge_result = "abandoned"
      else . end)' "$STUB_STORE" > "$tmpf" && mv "$tmpf" "$STUB_STORE"
out=$(bash "$SUT" sweep --apply --rig gc-toolkit 2>&1); rc=$?
eq "$rc" 0 "clean ledger exits 0"
has "$out" "sweep: clean" "clean ledger says so"

echo
echo "cutover-2026-08.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
