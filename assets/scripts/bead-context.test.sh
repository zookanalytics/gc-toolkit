#!/usr/bin/env bash
# Hermetic test for assets/scripts/bead-context.sh.
#
# The tool's value is reading a bead's context correctly across the three
# `gc bd show --json` quirks and across stores, so the assertions target each:
# a `gc bd:` notice line leading stdout is stripped; the ARRAY-vs-`{"error":…}`
# OBJECT shapes are told apart; a dependency in ANOTHER rig's store is read from
# THAT store and folded into the counts, not reported unknown; and an open — or
# unresolvable — blocks-blocker fails the actionable verdict closed.
#
# `gc` is stubbed over a file-per-bead ledger under each fake rig; a direct `bd`
# is the regression the stub fails on. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/bead-context.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bead-context-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

# --- fake city --------------------------------------------------------------
R_TK="$TMP/rigs/gc-toolkit"; R_OR="$TMP/rigs/otherrig"; HQ="$TMP/hq"
mkdir -p "$TMP/bin" "$R_TK/.beads" "$R_OR/.beads" "$HQ/.beads"
cat > "$TMP/rigs.json" <<JSON
{"rigs":[
  {"name":"gc-toolkit","path":"$R_TK","prefix":"tk","hq":false},
  {"name":"otherrig","path":"$R_OR","prefix":"or","hq":false},
  {"name":"loomington","path":"$HQ","prefix":"lx","hq":true}
]}
JSON
export FAKE_RIGS="$TMP/rigs.json"
export FAKE_GC_LOG="$TMP/gc.log"; : > "$FAKE_GC_LOG"
export FAKE_BD_LOG="$TMP/bd.log"; : > "$FAKE_BD_LOG"
export STUB_ROOT="$TMP"
export STUB_PREFACE=""

bead() { cat > "$1/.beads/$2.json"; }   # bead <store-repo> <id>  (object on stdin)

# tk-main: a metadata-rich anchor. Its blocks deps are one same-store closed
# (embedded status), one FOREIGN closed in the otherrig store (no embedded
# status — the cross-store case), and a same-store open parent-child (never a
# blocker).
bead "$R_TK" tk-main <<'J'
{"id":"tk-main","title":"main anchor","status":"open","issue_type":"task","assignee":null,
 "metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat",
   "branch":"polecat/tk-main","target":"main","existing_pr":"https://example/pr/9","pr_number":"9",
   "merge_result":"pull_request","check_set":"codex","check.codex":"green@deadbeef",
   "gc.superseded_by":"tk-succ","gc.superseded_by_store":"rig:gc-toolkit"},
 "dependencies":[
   {"id":"tk-c1","dependency_type":"blocks","status":"closed"},
   {"id":"or-far","dependency_type":"blocks"},
   {"id":"tk-par","dependency_type":"parent-child","status":"open"}]}
J
bead "$R_TK" tk-c1  <<'J'
{"id":"tk-c1","title":"closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
bead "$R_TK" tk-par <<'J'
{"id":"tk-par","title":"parent","status":"open","issue_type":"epic","metadata":{}}
J
bead "$R_OR" or-far <<'J'
{"id":"or-far","title":"foreign closed blocker","status":"closed","issue_type":"task","metadata":{}}
J
# tk-blocked: one same-store OPEN blocks dep — actionable must be NO.
bead "$R_TK" tk-blocked <<'J'
{"id":"tk-blocked","title":"held","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"tk-op","dependency_type":"blocks","status":"open"}]}
J
bead "$R_TK" tk-op <<'J'
{"id":"tk-op","title":"open blocker","status":"open","issue_type":"task","metadata":{}}
J
# tk-failclosed: a blocks dep whose store no rig carries and which bd could not
# embed a status for — the verdict must fail closed to NO, never read as landed.
bead "$R_TK" tk-failclosed <<'J'
{"id":"tk-failclosed","title":"fail-closed","status":"open","issue_type":"task","metadata":{},
 "dependencies":[{"id":"zz-ghost","dependency_type":"blocks"}]}
J
# lx-city lives in the HQ store, which no --rig value names — only --db reaches.
bead "$HQ" lx-city <<'J'
{"id":"lx-city","title":"city bead","status":"open","issue_type":"task","metadata":{}}
J

# tk-ctrl carries a raw C0 byte in its notes, the payload real bd emits that
# aborts a naive jq. Written with a literal SOH (\001) so scrub is exercised.
printf '{"id":"tk-ctrl","title":"ctl\001note","status":"open","issue_type":"task","metadata":{}}\n' \
  > "$R_TK/.beads/tk-ctrl.json"

# tk-nul carries a raw NUL (\000), the one C0 byte that trips grep's binary
# heuristic: the notice-strip must run in text mode (grep -a) or grep drops the
# whole payload and the bead reads as unresolved. Distinct from tk-ctrl's SOH,
# which grep passes through and only scrub must remove.
printf '{"id":"tk-nul","title":"nul","status":"open","issue_type":"task","notes":"a\000b","metadata":{}}\n' \
  > "$R_TK/.beads/tk-nul.json"

cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# Only the surface bead-context.sh touches. Every call is logged so the test can
# prove which store was asked, not merely what came back.
set -u
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
preface() { [ -n "${STUB_PREFACE:-}" ] && echo 'gc bd: answering from the rig "fake" store'; }
miss() { printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; echo "Issue $1 not found" >&2; exit 1; }
# Stream the payload through `cat`, not `"$(cat)"`: command substitution drops a
# raw NUL byte (bash: "ignored null byte in input"), and the NUL is exactly the
# C0 byte real `gc bd show` can emit that the tool must survive. Wrapping in
# brackets keeps the array shape the tool discriminates on.
serve() { preface; printf '['; cat "$1"; printf ']\n'; exit 0; }
case "${1:-} ${2:-}" in
  "rig list") preface; cat "$FAKE_RIGS"; exit 0 ;;
esac
[ "${1:-}" = bd ] || { echo "gc: unsupported ($*)" >&2; exit 1; }
shift
DB=""; ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db)  DB="$2"; shift 2 ;;
    show)  ID="${2:-}"; shift $(( $# < 2 ? $# : 2 )) ;;
    *)     shift ;;
  esac
done
[ -n "$ID" ] || { echo "gc bd: no id" >&2; exit 1; }
if [ -n "$DB" ]; then
  [ -f "$DB/$ID.json" ] && serve "$DB/$ID.json"
  miss "$ID"
fi
# Unpinned: a live id resolves from whichever store holds it.
for d in "$STUB_ROOT"/rigs/*/.beads "$STUB_ROOT"/hq/.beads; do
  [ -f "$d/$ID.json" ] && serve "$d/$ID.json"
done
miss "$ID"
GC

cat > "$TMP/bin/bd" <<'BD'
#!/usr/bin/env bash
# The tool reaches every store through `gc bd`; a direct `bd` is the regression
# this stub exists to fail on. It records the call so one assertion reads the
# whole run.
printf '%s\n' "$*" >> "$FAKE_BD_LOG"
echo "stub bd: called directly instead of through gc bd" >&2
exit 127
BD
chmod +x "$TMP/bin/gc" "$TMP/bin/bd"
export PATH="$TMP/bin:$PATH"

run()  { OUT=$("$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }
runj() { run "$@" --json; JQ=$(printf '%s' "$OUT" | jq -r "$JQF" 2>/dev/null); }
# Bounded variant for a call that could spin before a fix: a wedged SUT surfaces
# as timeout's rc 124 (a test failure) instead of hanging the whole suite.
runb() { OUT=$(timeout 10 "$SUT" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err"); }

# --- basic resolution + rendering -------------------------------------------
run tk-main
eq "$RC" 0 "a resolvable bead reports (rc)"
has "$OUT" "Status      open"        "  ... status"
has "$OUT" "Type        task"        "  ... type from issue_type"
has "$OUT" "Store       gc-toolkit"  "  ... store resolved from the id prefix"
has "$(cat "$FAKE_GC_LOG")" "show tk-main --json --brief-deps" \
  "  ... via a --brief-deps read, so a hub bead's dependency bodies are never fetched"

# --- metadata that decides an anchor's fate ---------------------------------
has "$OUT" "branch        polecat/tk-main" "branch renders"
has "$OUT" "target        main"            "target renders"
has "$OUT" "merge_result  pull_request"    "merge_result renders"
has "$OUT" "check.codex   green@deadbeef"  "per-gate check.<g> lane renders"
has "$OUT" "successor     tk-succ in rig:gc-toolkit" "successor pointer renders with its store"

# --- the stdout notice line is stripped, not parsed as JSON -----------------
STUB_PREFACE=1 run tk-main
eq "$RC" 0 "a leading \`gc bd:\` notice line does not break the read (rc)"
has "$OUT" "Status      open" "  ... and the bead still renders"
STUB_PREFACE=""

# --- dependency counts, and the cross-store resolution folded into them -----
# tk-main's blocks deps are one same-store closed (embedded status) and one
# FOREIGN closed in the otherrig store (no embedded status). The output is
# counts, not a row per edge; the cross-store read still happens to produce the
# closed-blocker count, proven by the gc-log line below.
JQF='.dependencies.total'            runj tk-main
eq "$JQ" 3 "every dependency is counted (two blocks, one parent-child)"
JQF='.dependencies.blockers.closed'  runj tk-main
eq "$JQ" 2 "both blocks-blockers count closed — the same-store and the cross-store one"
JQF='.dependencies.blockers.open'    runj tk-main
eq "$JQ" 0 "no blocks-blocker is open"
JQF='.dependencies.by_status.closed' runj tk-main
eq "$JQ" 2 "the by-status tally counts the two closed edges"
JQF='.dependencies.by_status.open'   runj tk-main
eq "$JQ" 1 "  ... and the one open parent-child edge"
has "$(cat "$FAKE_GC_LOG")" "bd --db $R_OR/.beads show or-far" \
  "the cross-store blocker's status is read from the otherrig store it lives in"

# --- actionability ----------------------------------------------------------
JQF='.actionable'  runj tk-main
eq "$JQ" true "all blocks-blockers closed (one of them cross-store) reads actionable"

run tk-blocked
has "$OUT" "Actionable  NO"    "an open blocks-blocker fails the verdict"
has "$OUT" "tk-op"             "  ... and names the open blocker"
has "$OUT" "blockers    1 open · 0 closed" "  ... and the human block shows the blocker counts"
JQF='.dependencies.blockers.open'  runj tk-blocked
eq "$JQ" 1 "  ... counted as one open blocker"
JQF='.open_blockers | join(",")'   runj tk-blocked
eq "$JQ" tk-op "  ... named in open_blockers"
JQF='.actionable'                  runj tk-blocked
eq "$JQ" false "  ... actionable=false"

# A blocker whose store no rig carries, with no embedded status, is UNKNOWN, and
# unknown must fail closed — counted as an open blocker, never as landed.
JQF='.dependencies.by_status.unknown'  runj tk-failclosed
eq "$JQ" 1 "an unplaceable blocker's status is unknown, not assumed closed"
JQF='.dependencies.blockers.open'      runj tk-failclosed
eq "$JQ" 1 "  ... and it counts as an open blocker (fail closed)"
JQF='.open_blockers | join(",")'       runj tk-failclosed
eq "$JQ" zz-ghost "  ... named in open_blockers"
JQF='.actionable'                      runj tk-failclosed
eq "$JQ" false "  ... so the actionable verdict fails closed"

# --- the object-vs-array shape, and store pinning ---------------------------
run tk-missing
eq "$RC" 4 "a not-found id (\`{\"error\":…}\` object) is reported, not parsed as a bead"
has "$ERR" "did not resolve to a bead" "  ... with a diagnostic"

run lx-city --db "$HQ/.beads"
eq "$RC" 0 "--db reaches the HQ store, which no --rig value names"
has "$OUT" "Store       loomington" "  ... and the rig is recovered from the db path"

JQF='.status'  runj or-far --store rig:otherrig
eq "$JQ" closed "--store rig:<name> pins the read to that rig's store"

# --- control bytes in notes do not abort the read ---------------------------
run tk-ctrl
eq "$RC" 0 "a raw C0 byte in notes is scrubbed before jq, not fatal"
has "$OUT" "Status      open" "  ... and the bead renders"

# A raw NUL is the C0 byte that trips grep's binary heuristic; without a text-mode
# notice strip grep drops the payload and the bead reads as unresolved (rc 4).
run tk-nul
eq "$RC" 0 "a raw NUL in notes does not switch the notice-strip to binary and drop the payload"
has "$OUT" "Status      open" "  ... and the bead still renders"

# --- usage ------------------------------------------------------------------
run;                       eq "$RC" 2 "no id is a usage error"
run tk-main extra-id;      eq "$RC" 2 "a second id is a usage error"
run tk-main --store nope;  eq "$RC" 2 "a --store that is not rig:<name> is a usage error"
run --nope tk-main;        eq "$RC" 2 "an unknown flag is a usage error"

# --store / --db with no following value must fail usage, not loop forever: a
# failed `shift 2` under set -u without set -e leaves $1 unconsumed and the loop
# re-reads it. runb bounds the call so the pre-fix hang is a failure, not a wedge.
runb tk-main --store;  eq "$RC" 2 "a --store with no value is a usage error, not a hang"
has "$ERR" "needs a value" "  ... with a diagnostic"
runb tk-main --db;     eq "$RC" 2 "a --db with no value is a usage error, not a hang"

# --- the raw-bd regression guard: no probe ever bypassed gc bd --------------
eq "$(wc -l < "$FAKE_BD_LOG" | tr -d ' ')" "0" \
  "no store was reached through a direct \`bd\` at any point in the run"

echo
echo "bead-context: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
