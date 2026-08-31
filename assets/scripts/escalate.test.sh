#!/usr/bin/env bash
# Hermetic test for assets/scripts/escalate.sh — one open visit per situation.
# Stubbed gc; no live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/escalate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
hasin() { grep -qF -- "$2" <<< "$1"; }
has()   { if hasin "$1" "$2"; then ok "$3"; else bad "$3 (missing '$2')"; fi; }
hasnt() { if hasin "$1" "$2"; then bad "$3 (found '$2')"; else ok "$3"; fi; }

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
STORE="${STUB_STORE:?}"; DEPS="${STUB_DEPS:?}"
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
[ "${1:-}" = "bd" ] || exit 0
shift
case "${1:-}" in
  list)
    [ -n "${STUB_LIST_FAIL:-}" ] && { echo "bd: down" >&2; exit 1; }
    fields=(); statuses=""; limit=0
    shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --status=*) statuses="${1#--status=}" ;;
        --limit=*) limit="${1#--limit=}" ;;
        --metadata-field) shift; fields+=("${1:-}") ;;
      esac
      shift || true
    done
    out=$(jq -c --arg st ",$statuses," '
      [ .[] | select(.status as $s | $st | contains("," + $s + ",")) ]' "$STORE")
    for f in ${fields[@]+"${fields[@]}"}; do
      k="${f%%=*}"; v="${f#*=}"
      out=$(printf '%s' "$out" | jq -c --arg k "$k" --arg v "$v" \
        '[ .[] | select((.metadata[$k] // "") == $v) ]')
    done
    case "$limit" in ''|0|*[!0-9]*) : ;; *) out=$(printf '%s' "$out" | jq -c --argjson n "$limit" '.[0:$n]') ;; esac
    printf '%s\n' "$out" ;;
  show)
    out=$(jq -c --arg id "$2" '[.[] | select(.id == $id)]' "$STORE")
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      echo '{"error":"no issues found"}'
    else printf '%s\n' "$out"; fi ;;
  create)
    [ -n "${STUB_CREATE_FAIL:-}" ] && { echo "bd: refused" >&2; exit 1; }
    shift
    title=""; body=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="$1" ;;
        -d) shift; body="$1" ;;
      esac
      shift || true
    done
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp)
    jq -c --arg id "vis-$n" --arg t "$title" --arg d "$body" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,"metadata":{},"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"vis-%s"}\n' "$n" ;;
  update)
    shift; id="$1"; shift
    if [ -n "${STUB_UPD_FAIL:-}" ]; then exit 1; fi
    tmp=$(mktemp); cp "$STORE" "$tmp"
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; k="${1%%=*}"; v="${1#*=}"
          jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
            'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp" ;;
      esac
      shift || true
    done
    mv "$tmp" "$STORE"; echo "updated $id" ;;
  dep)
    [ "${2:-}" = "add" ] && printf '%s|%s|%s\n' "$3" "$4" "${5#--type=}" >> "$DEPS"
    echo "dep added" ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_DEPS="$TMP/deps" STUB_GC_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq"
unset GC_RIG STUB_LIST_FAIL STUB_CREATE_FAIL STUB_UPD_FAIL 2>/dev/null || true

reset() {
  printf '%s' "${1:-[]}" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; printf '0' > "$STUB_SEQ"
}
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
field()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .[$k]) // "<absent>"' "$STUB_STORE"; }
visits() { cat "$STUB_SEQ"; }   # creates issued since reset (the seed bead is vis-0)

echo "# files a visit in the canonical gate-visit shape"
reset
out=$("$SUT" --subject tk-stuck --key merge-conflict --message "PR#7 is CONFLICTING; needs a human rebase decision" 2>&1); rc=$?
eq "$rc" 0 "filing exits 0"
eq "$(visits)" "1" "exactly one visit filed"
has "$(field vis-1 title)" "visit: tk-stuck — PR#7 is CONFLICTING" "title carries the visit brand, subject and headline"
eq "$(meta vis-1 gc.routed_to)" "gc-toolkit.converse" "routed to the default converse pool"
eq "$(meta vis-1 gc.continuation_group)" "tk-stuck" "continuation group is the subject"
eq "$(meta vis-1 task_kind)" "visit" "task_kind=visit stamped"
eq "$(meta vis-1 escalation_key)" "merge-conflict" "escalation_key stamped"
has "$(cat "$STUB_DEPS")" "vis-1|tk-stuck|tracks" "visit tracks the subject (never parent-child)"
hasnt "$(cat "$STUB_DEPS")" "parent-child" "no parent-child edge"
has "$out" "filed visit vis-1" "reports what it filed"

echo "# rig qualification and --pool override"
reset
GC_RIG=myrig "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-1 gc.routed_to)" "myrig/gc-toolkit.converse" "GC_RIG qualifies the default pool"
reset
"$SUT" --subject tk-a --key k1 --message m --pool other/rig.converse >/dev/null 2>&1
eq "$(meta vis-1 gc.routed_to)" "other/rig.converse" "--pool overrides the default"

echo "# idempotent: one open visit per key per durable subject"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-a","task_kind":"visit"},"notes":""}]'
out=$("$SUT" --subject tk-a --key k1 --message "again" 2>&1); rc=$?
eq "$rc" 0 "an already-open situation exits 0"
eq "$(visits)" "0" "no second visit filed"
has "$out" "already open" "says the visit already exists"

reset '[{"id":"vis-0","status":"in_progress","assignee":"conv/1","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a CLAIMED (in_progress) visit also suppresses"

echo "# a closed visit does not suppress; a different subject/key does not suppress"
reset '[{"id":"vis-0","status":"closed","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a closed visit re-opens the situation"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-OTHER"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "same key on ANOTHER subject does not suppress"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k2","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a different key on the same subject does not suppress"

echo "# shared-key dedup survives the row window (both filters ride the listing)"
# 21 open visits share key k1 on OTHER subjects; ours is the 21st row. A
# key-only listing truncated at --limit=20 would drop ours and re-file a
# duplicate every pass; the subject filter on the listing itself dedups exactly.
crowd="["
for i in $(seq 1 20); do
  crowd="$crowd{\"id\":\"other-$i\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"escalation_key\":\"k1\",\"gc.continuation_group\":\"tk-other-$i\"},\"notes\":\"\"},"
done
crowd="$crowd{\"id\":\"vis-0\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"escalation_key\":\"k1\",\"gc.continuation_group\":\"tk-a\"},\"notes\":\"\"}]"
reset "$crowd"
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "the crowded-key situation exits 0"
eq "$(visits)" "0" "no duplicate filed past the 20-row window"
has "$out" "already open" "the existing visit was found"
has "$(cat "$STUB_GC_LOG")" "--metadata-field gc.continuation_group=tk-a" "the subject filter rides the listing itself"

echo "# an ephemeral subject dedups on the key alone"
# A patrol wisp is burned and re-poured every cycle, so its id names no durable
# subject. A situation it raises is identified by its key alone.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"doctor-fork-rate","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
out=$("$SUT" --subject lx-wisp-bbbbb --key doctor-fork-rate --message "fork rate high" 2>&1); rc=$?
eq "$rc" 0 "a differing ephemeral subject exits 0"
eq "$(visits)" "0" "the next cycle's wisp files no duplicate"
has "$out" "already open" "the previous cycle's visit was found"
hasnt "$(grep '^bd list' "$STUB_GC_LOG")" "gc.continuation_group" "the wisp subject does not ride the dedup listing"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-wisp-aaa"},"notes":""}]'
"$SUT" --subject tk-wisp-bbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a rig store's tk-wisp- ids are ephemeral too"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
"$SUT" --subject lx-wisp-aaaaa --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "the same wisp subject still dedups"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k2","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
"$SUT" --subject lx-wisp-bbbbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a different key still files, ephemeral subject or not"

reset '[{"id":"vis-0","status":"closed","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
"$SUT" --subject lx-wisp-bbbbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a closed visit re-opens the situation for a wisp subject too"

# Only the -wisp- infix is ephemeral: a durable id that merely contains the
# letters keeps per-subject dedup.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-other"},"notes":""}]'
"$SUT" --subject tk-wispy --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a bead id merely containing 'wisp' is still durable"

# A key crowded with open visits on distinct ephemeral subjects is still one
# open situation.
crowd="["
for i in $(seq 1 20); do
  crowd="$crowd{\"id\":\"other-$i\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"escalation_key\":\"doctor-fork-rate\",\"gc.continuation_group\":\"lx-wisp-c$i\"},\"notes\":\"\"},"
done
reset "${crowd%,}]"
"$SUT" --subject lx-wisp-fresh --key doctor-fork-rate --message m >/dev/null 2>&1
eq "$(visits)" "0" "20 cycles of one key file no 21st visit"

echo "# an ephemeral subject still records what raised the visit"
reset
"$SUT" --subject lx-wisp-aaaaa --key doctor-fork-rate --message "fork rate high" >/dev/null 2>&1
eq "$(meta vis-1 gc.continuation_group)" "lx-wisp-aaaaa" "the raising wisp is still stamped"
has "$(cat "$STUB_DEPS")" "vis-1|lx-wisp-aaaaa|tracks" "the visit still tracks the raising wisp"
has "$(field vis-1 title)" "visit: lx-wisp-aaaaa" "and the title still names it"

echo "# an unreadable listing files anyway (a duplicate beats a mute)"
reset
STUB_LIST_FAIL=1 "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "unreadable dedup listing still files"
eq "$(visits)" "1" "the visit exists"

echo "# failures are loud"
reset
out=$(STUB_CREATE_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "a failed create exits 1"
has "$out" "no id" "and says the create returned nothing"
reset
out=$(STUB_UPD_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "stamps that do not read back exit 1"
has "$out" "repair:" "and print the repair command"

echo "# usage"
out=$("$SUT" --subject tk-a --key k1 2>&1); rc=$?
eq "$rc" 2 "missing --message is a usage error"
out=$("$SUT" --subject tk-a --key "bad key!" --message m 2>&1); rc=$?
eq "$rc" 2 "a key outside [A-Za-z0-9._-] is rejected"
out=$("$SUT" --subject tk-a --key k1 --message m --nonsense 2>&1); rc=$?
eq "$rc" 2 "an unknown argument is rejected"

echo
echo "escalate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
