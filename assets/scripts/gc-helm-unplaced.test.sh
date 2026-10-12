#!/usr/bin/env bash
# gc-helm-unplaced.test.sh — `gc-helm unplaced` lists the placement sitting's
# queue: every live bead in the city's stores marked placement=pending that
# nothing has placed since.
#
# Covered:
#   (QUEUE)    a marked bead with no parent, route, arm, assignee or live pour is
#              listed, from every rig store that answers
#   (PLACED)   a parent (either shape bd shows), a route, an arm, an assignee or
#              a live pour takes a bead out of the queue, marker or not, and a
#              bead whose marker is not pending is never listed
#   (BLOCKED)  a bead that also waits on a blocker is still in the queue
#   (ORDER)    rows come priority first, then oldest
#   (TEXT)     the plain form counts the rows and shows each takeaway under its
#              bead; an empty queue says so
#   (READ)     the verb reads the marker with the live statuses and writes
#              nothing
#   (COLD)     a suspended rig's store is not read, and the skip is named
#   (PARTIAL)  a store that does not answer, or whose read fails after printing
#              rows, is named and fails the run with 4 after the rows that were
#              read
#   (ARGS)     an unknown argument is refused
# Driven over a stubbed `gc` on PATH: no live city, Dolt or network.
set -u

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gc-helm.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-gc-helm-unplaced.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has()    { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnot() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
[ -f "$SCRIPT" ] && ok "gc-helm.sh present" || bad "gc-helm.sh missing at $SCRIPT"

# Three rig stores and one rig with no store. cold is suspended.
for r in alpha beta cold; do mkdir -p "$TMP/$r/.beads"; done
mkdir -p "$TMP/nostore"

# alpha's rows: one of each placed shape beside the beads still waiting.
cat > "$TMP/alpha.json" <<'JSON'
[
  {"id":"tk-a1","title":"doc-filing lint fails on main","issue_type":"bug","priority":2,"status":"open","created_at":"2026-10-11T05:12:25Z","metadata":{"placement":"pending","gc.takeaway":"ready to build once placed"}},
  {"id":"tk-a2","title":"placed by its parent field","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","parent":"tk-epic","metadata":{"placement":"pending"}},
  {"id":"tk-a3","title":"placed by its parent-child edge","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","dependencies":[{"issue_id":"tk-a3","depends_on_id":"tk-epic","type":"parent-child"}],"metadata":{"placement":"pending"}},
  {"id":"tk-a4","title":"routed by hand","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","metadata":{"placement":"pending","gc.routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-a5","title":"armed by hand","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","metadata":{"placement":"pending","gc.dispatch_when_ready":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-a6","title":"assigned by hand","issue_type":"task","priority":2,"status":"in_progress","assignee":"gc-toolkit.mechanik","created_at":"2026-10-11T01:00:00Z","metadata":{"placement":"pending"}},
  {"id":"tk-a7","title":"slung by hand","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","metadata":{"placement":"pending","gc.execution_routed_to":"gc-toolkit/gc-toolkit.polecat"}},
  {"id":"tk-a8","title":"a marker that is not pending","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-11T01:00:00Z","metadata":{"placement":"placed"}},
  {"id":"tk-a9","title":"prompt-update: add a rule","issue_type":"task","priority":1,"status":"open","created_at":"2026-10-12T09:00:00Z","metadata":{"placement":"pending","task_kind":"prompt-update"}},
  {"id":"tk-a10","title":"waits on a migration and on placement","issue_type":"task","priority":2,"status":"open","created_at":"2026-10-12T10:00:00Z","dependencies":[{"issue_id":"tk-a10","depends_on_id":"tk-mig","type":"blocks"}],"metadata":{"placement":"pending"}}
]
JSON
cat > "$TMP/beta.json" <<'JSON'
[
  {"id":"sl-b1","title":"pack defect the witness filed","issue_type":"bug","priority":2,"status":"open","created_at":"2026-10-10T20:00:00Z","metadata":{"placement":"pending"}}
]
JSON
cat > "$TMP/cold.json" <<'JSON'
[
  {"id":"su-c1","title":"in a suspended rig","issue_type":"task","priority":0,"status":"open","created_at":"2026-10-01T00:00:00Z","metadata":{"placement":"pending"}}
]
JSON

mkdir -p "$TMP/bin"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'GC'
printf '%s\n' "$*" >> "$FAKE_CALLS"
case "${1:-} ${2:-}" in
  "rig list")
    jq -n --arg t "$FAKE_TMP" '{rigs:[
      {name:"gc-toolkit", path:($t + "/alpha"), prefix:"tk", hq:false, suspended:false},
      {name:"signal-loom", path:($t + "/beta"), prefix:"sl", hq:false, suspended:false},
      {name:"shutupandlisten", path:($t + "/cold"), prefix:"su", hq:false, suspended:true},
      {name:"nostore", path:($t + "/nostore"), prefix:"ns", hq:false, suspended:false}]}' ;;
  "bd list")
    db=""; prev=""
    for a in "$@"; do [ "$prev" = "--db" ] && db="$a"; prev="$a"; done
    rig=$(basename "$(dirname "$db")")
    case " ${FAKE_DOWN:-} " in *" $rig "*) exit 1 ;; esac
    if [ -n "${FAKE_EMPTY:-}" ]; then printf '[]\n'; else cat "$FAKE_TMP/$rig.json"; fi
    case " ${FAKE_FAIL_AFTER:-} " in *" $rig "*) exit 1 ;; esac ;;
  *) : ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH" FAKE_TMP="$TMP" FAKE_CALLS="$TMP/calls"

run() { : > "$FAKE_CALLS"; RC=0; OUT=$(sh "$SCRIPT" unplaced "$@" 2>"$TMP/err") || RC=$?; ERR=$(cat "$TMP/err"); CALLS=$(cat "$FAKE_CALLS"); }

echo "# the queue, as rows"
run --json
eq "$RC" "0" "(QUEUE) unplaced --json succeeds"
printf '%s' "$OUT" | jq -e 'type == "array"' >/dev/null 2>&1 && ok "(QUEUE) …and prints a JSON array" || bad "(QUEUE) …and prints a JSON array ($OUT)"
IDS=$(printf '%s' "$OUT" | jq -r '[.[].id] | join(" ")' 2>/dev/null)
eq "$IDS" "tk-a9 sl-b1 tk-a1 tk-a10" "(ORDER) the waiting beads, priority first and then oldest, from every store that answers"
for id in tk-a2 tk-a3; do hasnot " $IDS " " $id " "(PLACED) $id has a parent, so it is placed"; done
hasnot " $IDS " " tk-a4 " "(PLACED) a route places a bead"
hasnot " $IDS " " tk-a5 " "(PLACED) an arm places a bead"
hasnot " $IDS " " tk-a6 " "(PLACED) an assignee places a bead"
hasnot " $IDS " " tk-a7 " "(PLACED) a live pour places a bead"
hasnot " $IDS " " tk-a8 " "(PLACED) a marker that is not pending is not in the queue"
has " $IDS " " tk-a10 " "(BLOCKED) a bead that also waits on a blocker is in the queue"
eq "$(printf '%s' "$OUT" | jq -r '.[] | select(.id == "sl-b1") | .rig' 2>/dev/null)" "signal-loom" "(QUEUE) each row names its rig"
eq "$(printf '%s' "$OUT" | jq -r '.[] | select(.id == "tk-a1") | .takeaway' 2>/dev/null)" "ready to build once placed" \
   "(QUEUE) …and carries the reaction's takeaway"
eq "$(printf '%s' "$OUT" | jq -r '.[] | select(.id == "tk-a9") | [.type, .priority, .status, .created_at] | map(tostring) | join(" ")' 2>/dev/null)" \
   "task 1 open 2026-10-12T09:00:00Z" "(QUEUE) …and its type, priority, status and age"

echo "# what it reads, and what it does not"
has "$CALLS" "--metadata-field placement=pending" "(READ) it reads the marker"
has "$CALLS" "--status=open,in_progress,blocked,deferred,hooked,pinned" "(READ) …across every live status"
hasnot "$CALLS" "bd update" "(READ) it writes nothing"
hasnot "$CALLS" "bd create" "(READ) …and files nothing"
hasnot "$CALLS" "$TMP/cold/.beads" "(COLD) a suspended rig's store is not read"
hasnot " $IDS " " su-c1 " "(COLD) …so its bead is not listed"
has "$ERR" "rig shutupandlisten is suspended" "(COLD) …and the skip is named"
hasnot "$CALLS" "$TMP/nostore" "(READ) a rig with no store is not asked"

echo "# the plain form"
run
eq "$RC" "0" "(TEXT) unplaced succeeds"
has "$OUT" "unplaced: 4 bead(s) wait for placement" "(TEXT) it counts the queue"
has "$OUT" "tk-a1	P2	bug	gc-toolkit	2026-10-11	doc-filing lint fails on main" "(TEXT) …lists each bead on a line"
has "$OUT" "	ready to build once placed" "(TEXT) …with its takeaway beneath it"
FAKE_EMPTY=1 run
eq "$RC" "0" "(TEXT) an empty queue succeeds"
has "$OUT" "unplaced: no bead waits for placement" "(TEXT) …and says the queue is empty"

echo "# a store that does not answer"
FAKE_DOWN=beta run --json
eq "$RC" "4" "(PARTIAL) a store that does not answer fails the run"
has "$ERR" "signal-loom" "(PARTIAL) …naming the rig"
has "$ERR" "this list is partial" "(PARTIAL) …and saying the list is partial"
eq "$(printf '%s' "$OUT" | jq -r '[.[].id] | join(" ")' 2>/dev/null)" "tk-a9 tk-a1 tk-a10" "(PARTIAL) …after printing the rows it could read"
FAKE_FAIL_AFTER=beta run --json
eq "$RC" "4" "(PARTIAL) a read that prints its rows and then fails has not answered"
has "$ERR" "signal-loom" "(PARTIAL) …so its rig is named"
hasnot "$OUT" "sl-b1" "(PARTIAL) …and the rows it printed are not listed as the store's answer"

echo "# arguments"
run --nope
eq "$RC" "2" "(ARGS) an unknown argument is refused"
eq "$CALLS" "" "(ARGS) …before anything is read"

echo
echo "gc-helm unplaced: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
