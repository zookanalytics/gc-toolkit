#!/usr/bin/env bash
# Hermetic test for assets/scripts/gc-deacon-ledger.sh — the deacon's rolling
# incident ledger. A stubbed `gc bd` over a JSON store; no live city, Dolt, or
# network. Covers find-or-create idempotence, the entry format, the closed
# category and artifact-ref sets, one-line normalisation, rotation on both
# bounds, the continues: walk `show --since` makes across a rotation, and the
# store pinning that keeps an escalation's entry out of a rig ledger.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/gc-deacon-ledger.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { if grep -qF -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (missing '$2' in: $1)"; fi; }
hasnt() { if grep -qF -- "$2" <<< "$1"; then bad "$3 (found '$2')"; else ok "$3"; fi; }
matches() { if grep -qE -- "$2" <<< "$1"; then ok "$3"; else bad "$3 (no match for /$2/ in: $1)"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
# Models the bd surface this script uses, including the two answers that shape
# its control flow: `show` returns an OBJECT when nothing resolves, and
# `create --json` can hand back an empty id although the bead landed.
set -u
S="${STUB_STORE:?}"
printf '[%s] %s\n' "${GC_RIG:-<unset>}" "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = bd ] || exit 0
shift
verb="${1:-}"; shift || true
row='{id, status, created_at, comment_count: ((.comments // []) | length), description, title}'
case "$verb" in
  list)
    statuses=""; label=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --status)   shift; statuses="${1:-}" ;;
        --label=*)  label="${1#--label=}" ;;
        --label)    shift; label="${1:-}" ;;
      esac
      shift || true
    done
    jq -c --arg st ",$statuses," --arg l "$label" "
      [ .[]
        | select(\$st == \",,\" or (.status as \$s | \$st | contains(\",\" + \$s + \",\")))
        | select(\$l == \"\" or ((.labels // []) | index(\$l)))
        | $row ]" "$S"
    ;;
  show)
    out=$(jq -c --arg id "${1:-}" "[ .[] | select(.id == \$id) | $row ]" "$S")
    [ "$(printf '%s' "$out" | jq 'length')" = 0 ] && out='{"error":"no issues found"}'
    printf '%s\n' "$out"
    ;;
  create)
    title=""; body=""; label=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="${1:-}" ;;
        -d)      shift; body="${1:-}" ;;
        -l)      shift; label="${1:-}" ;;
      esac
      shift || true
    done
    n=$(( $(jq 'length' "$S") + 1 )); id="led-$n"
    tmp=$(mktemp)
    jq -c --arg id "$id" --arg t "$title" --arg b "$body" --arg l "$label" \
          --arg c "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + [{id:$id, status:"open", title:$t, description:$b, labels:[$l], created_at:$c, comments:[]}]' \
      "$S" > "$tmp" && mv "$tmp" "$S"
    [ -n "${STUB_CREATE_EMPTY_ID:-}" ] && { echo '{"id":""}'; exit 0; }
    printf '{"id":"%s"}\n' "$id"
    ;;
  comment)
    [ -n "${STUB_COMMENT_FAIL:-}" ] && { echo "bd: refused" >&2; exit 1; }
    jq -e --arg id "${1:-}" 'any(.[]; .id == $id)' "$S" >/dev/null || { echo "bd: no such issue" >&2; exit 1; }
    tmp=$(mktemp)
    jq -c --arg id "${1:-}" --arg t "${2:-}" \
      'map(if .id == $id then .comments = ((.comments // []) + [{text: $t}]) else . end)' \
      "$S" > "$tmp" && mv "$tmp" "$S"
    ;;
  comments) jq -c --arg id "${1:-}" '[ .[] | select(.id == $id) | (.comments // [])[] ]' "$S" ;;
  close)
    tmp=$(mktemp)
    jq -c --arg id "${1:-}" 'map(if .id == $id then .status = "closed" else . end)' "$S" > "$tmp" && mv "$tmp" "$S"
    ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_GC_LOG="$TMP/gc.log"
export GC_CITY_PATH="$TMP"
# A caller that has bound a rig — escalate.sh exports one before it files. The
# ledger must ignore it; the assertions at the end prove it does.
export GC_RIG=gc-toolkit
unset STUB_CREATE_EMPTY_ID STUB_COMMENT_FAIL 2>/dev/null || true

reset() { printf '%s' "${1:-[]}" > "$STUB_STORE"; : > "$STUB_GC_LOG"; }
openids()  { jq -r '[.[] | select(.status == "open") | .id] | join(" ")' "$STUB_STORE"; }
entries()  { jq -r --arg id "$1" '.[] | select(.id == $id) | (.comments // [])[].text' "$STUB_STORE"; }
ecount()   { entries "$1" | grep -c . ; }
desc()     { jq -r --arg id "$1" '.[] | select(.id == $id) | .description' "$STUB_STORE"; }
bstatus()  { jq -r --arg id "$1" '.[] | select(.id == $id) | .status' "$STUB_STORE"; }
# Rewrite a bead's created_at to N days ago, for the age bound.
age_days() { local d; d=$(date -u -d "@$(( $(date -u +%s) - $2 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ)
             local t; t=$(mktemp); jq -c --arg id "$1" --arg c "$d" 'map(if .id == $id then .created_at = $c else . end)' "$STUB_STORE" > "$t" && mv "$t" "$STUB_STORE"; }
# Plant a ledger entry at a chosen age, bypassing append.
plant()    { local d; d=$(date -u -d "@$(( $(date -u +%s) - $2 ))" +%Y-%m-%dT%H:%M:%SZ)
             local t; t=$(mktemp); jq -c --arg id "$1" --arg x "$d $3" 'map(if .id == $id then .comments = ((.comments // []) + [{text: $x}]) else . end)' "$STUB_STORE" > "$t" && mv "$t" "$STUB_STORE"; }

echo "# find-or-create is idempotent"
reset
FIRST=$("$SUT" current 2>/dev/null); rc=$?
eq "$rc" 0 "current exits 0 on an empty store"
eq "$FIRST" "led-1" "current creates the first ledger"
eq "$("$SUT" current 2>/dev/null)" "led-1" "a second current reuses the open ledger"
eq "$(jq 'length' "$STUB_STORE")" "1" "no duplicate ledger bead"
has "$(desc led-1)" "escalation warrant deviation boot config recovery cleanup note" \
  "the ledger body carries the closed category set a reader needs"

echo
echo "# append writes one entry in the agreed format"
reset
out=$("$SUT" append cleanup "killed 3 orphaned subagents" "bead:tk-9" 2>&1); rc=$?
eq "$rc" 0 "append exits 0"
matches "$(entries led-1)" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z \[cleanup\] killed 3 orphaned subagents -> bead:tk-9$' \
  "the entry is <UTC-ts> [<category>] <one-line> -> <artifact-ref>"
has "$out" "led-1:" "append reports the ledger it wrote to"
"$SUT" append note "no ref given" >/dev/null 2>&1
matches "$(entries led-1)" '\[note\] no ref given -> -$' "an omitted artifact-ref records as -"

echo
echo "# the closed sets are enforced, and a refusal writes nothing"
reset
out=$("$SUT" append gossip "something happened" 2>&1); rc=$?
eq "$rc" 2 "an unknown category exits 2"
has "$out" "unknown category 'gossip'" "and says which categories exist"
eq "$(jq 'length' "$STUB_STORE")" "0" "a refused append creates no ledger and writes no entry"
out=$("$SUT" append note "a line" "slack:C123" 2>&1); rc=$?
eq "$rc" 2 "an artifact-ref of an unknown kind exits 2"
has "$out" "names no known kind" "and says what a ref may be"
eq "$(jq 'length' "$STUB_STORE")" "0" "a refused ref writes nothing either"
out=$("$SUT" append 2>&1); rc=$?
eq "$rc" 2 "append with no arguments exits 2"

echo
echo "# an entry is one bounded line, whatever it was handed"
reset
"$SUT" append recovery "$(printf 'restarted dolt\nafter   a wedged\tgoroutine')" >/dev/null 2>&1
eq "$(ecount led-1)" "1" "a multi-line message is still one entry"
has "$(entries led-1)" "restarted dolt after a wedged goroutine" "newlines and runs collapse to single spaces"
reset
LONG=$(printf 'x%.0s' $(seq 1 400))
GC_DEACON_LEDGER_MAX_LINE=80 "$SUT" append note "$LONG" >/dev/null 2>&1
LINE=$(entries led-1)
eq "${#LINE}" "$(( 21 + 7 + 80 + 5 ))" "an over-long line is truncated to the bound"
has "$LINE" "..." "and is marked as truncated"

echo
echo "# rotation on the entry bound"
reset
export GC_DEACON_LEDGER_MAX_ENTRIES=3
for i in 1 2 3; do "$SUT" append note "entry $i" >/dev/null 2>&1; done
eq "$(openids)" "led-1" "under the bound, one open ledger"
"$SUT" append note "entry 4" >/dev/null 2>&1
eq "$(bstatus led-1)" "closed" "at the bound the full ledger closes"
eq "$(openids)" "led-2" "and a fresh one is open"
has "$(entries led-1)" "rotated -> led-2" "the closed ledger names its successor"
has "$(desc led-2)" "continues:led-1" "the successor points back at its predecessor"
has "$(entries led-2)" "entry 4" "the append that triggered rotation lands on the NEW ledger"
eq "$(entries led-2 | grep -c 'entry 4')" "1" "and lands exactly once"
unset GC_DEACON_LEDGER_MAX_ENTRIES

echo
echo "# rotation on the age bound"
reset
"$SUT" current >/dev/null 2>&1
age_days led-1 9
"$SUT" append note "after the age bound" >/dev/null 2>&1
eq "$(bstatus led-1)" "closed" "a ledger past the age bound closes"
has "$(entries led-2)" "after the age bound" "and the entry lands on its successor"
reset
"$SUT" current >/dev/null 2>&1
age_days led-1 3
"$SUT" append note "inside the age bound" >/dev/null 2>&1
eq "$(bstatus led-1)" "open" "a ledger inside the age bound does not rotate"

echo
echo "# show: window, ordering, and the continues: walk across a rotation"
reset
"$SUT" current >/dev/null 2>&1
plant led-1 $((100 * 3600)) "[note] four days back"
plant led-1 $((3 * 3600))   "[cleanup] three hours back"
plant led-1 60              "[boot] a minute back"
jq -c 'map(if .id == "led-1" then .comments = ((.comments // []) + [{text: "a human left a plain comment"}]) else . end)' \
  "$STUB_STORE" > "$TMP/s" && mv "$TMP/s" "$STUB_STORE"
out=$("$SUT" show --since 48h 2>/dev/null)
hasnt "$out" "four days back" "--since drops entries outside the window"
has "$out" "three hours back" "and keeps the ones inside it"
has "$out" "a minute back" "including the newest"
hasnt "$out" "a human left a plain comment" "a comment that is not an entry is not shown"
eq "$(printf '%s\n' "$out" | grep -n 'three hours back' | cut -d: -f1)" \
   "$(( $(printf '%s\n' "$out" | grep -n 'a minute back' | cut -d: -f1) - 1 ))" \
   "entries print oldest first"
out=$("$SUT" show 2>/dev/null)
has "$out" "four days back" "show with no window prints the whole ledger"

echo "## across a rotation"
export GC_DEACON_LEDGER_MAX_ENTRIES=3
"$SUT" append note "the rotating entry" >/dev/null 2>&1
unset GC_DEACON_LEDGER_MAX_ENTRIES
eq "$(openids)" "led-2" "the rotation happened"
out=$("$SUT" show --since 48h 2>/dev/null)
has "$out" "the rotating entry" "the window shows the new ledger"
has "$out" "three hours back" "and follows continues: back for the rest of the window"
hasnt "$out" "four days back" "without dragging in what the window excludes"
eq "$(printf '%s\n' "$out" | grep -n '^# led-1' | cut -d: -f1)" "1" "the older ledger prints first"
out=$("$SUT" show --since 5m 2>/dev/null)
hasnt "$out" "three hours back" "a shorter window stops the walk sooner"

echo
echo "# show refuses a duration it cannot read, and is quiet on an empty city"
reset
out=$("$SUT" show --since 3fortnights 2>&1); rc=$?
eq "$rc" 2 "an unparseable --since exits 2"
has "$out" "is not a duration" "and says what a duration looks like"
out=$("$SUT" show 2>&1); rc=$?
eq "$rc" 0 "show on a store with no ledger exits 0"
has "$out" "nothing recorded yet" "and says so rather than creating one"
eq "$(jq 'length' "$STUB_STORE")" "0" "show never creates a ledger"

echo
echo "# a create that answers with an empty id does not duplicate the ledger"
reset
STUB_CREATE_EMPTY_ID=1 "$SUT" append note "landed anyway" >/dev/null 2>&1
eq "$(jq 'length' "$STUB_STORE")" "1" "exactly one ledger bead exists"
has "$(entries led-1)" "landed anyway" "and the entry reached the bead the create really made"

echo
echo "# more than one open ledger: newest wins, extras are named"
reset '[{"id":"led-old","status":"open","title":"t","description":"","labels":["deacon-ledger"],"created_at":"2026-01-01T00:00:00Z","comments":[]},
       {"id":"led-new","status":"open","title":"t","description":"","labels":["deacon-ledger"],"created_at":"2026-06-01T00:00:00Z","comments":[]}]'
out=$("$SUT" append note "which one" 2>&1)
eq "$(ecount led-new)" "1" "the entry goes to the newest open ledger"
eq "$(ecount led-old)" "0" "and not to the older one"
has "$out" "more than one open" "the race is reported"
has "$out" "led-old" "naming the bead to close by hand"

echo
echo "# a comment that will not land is reported, never swallowed"
reset
out=$(STUB_COMMENT_FAIL=1 "$SUT" append note "never lands" 2>&1); rc=$?
eq "$rc" 1 "a failed append exits 1"
has "$out" "could not append" "and says so on stderr"

echo
echo "# the store is pinned to the city, whatever rig the caller bound"
reset
"$SUT" append note "from a rig-bound caller" >/dev/null 2>&1
eq "$(grep -c '^\[gc-toolkit\]' "$STUB_GC_LOG")" "0" "no gc call inherits the caller's GC_RIG"
[ "$(grep -c '^\[<unset>\] bd' "$STUB_GC_LOG")" -gt 0 ] \
  && ok "every bd call runs with GC_RIG unset" \
  || bad "no bd call was logged at all"

echo
echo "# usage"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 2 "no command exits 2"
has "$out" "usage: gc-deacon-ledger.sh append" "and prints usage"
out=$("$SUT" rotate 2>&1); rc=$?
eq "$rc" 2 "an unknown command exits 2"

echo
echo "gc-deacon-ledger.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
