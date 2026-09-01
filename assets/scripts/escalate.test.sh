#!/usr/bin/env bash
# Hermetic test for assets/scripts/escalate.sh — one open visit per situation.
# Stubbed gc; no live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/escalate.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-escalate-test.XXXXXX")"
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
printf '[%s] %s\n' "${GC_RIG:-<unset>}" "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = "agent" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_AGENTS:-}"
  exit 0
fi
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
    # A bd that silently ignored --metadata-field. Every caller re-checks the
    # rows it matched; this is what exercises those re-checks.
    [ -n "${STUB_LIST_IGNORE_FIELDS:-}" ] && fields=()
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
    # One create can fail while another lands: the run that mints a standing
    # subject issues two, and the fail-open arm is only reachable when the
    # first fails by itself.
    case "${STUB_CREATE_FAIL_MATCH:-}" in
      "") : ;;
      *) case "$title" in *"$STUB_CREATE_FAIL_MATCH"*) echo "bd: refused" >&2; exit 1 ;; esac ;;
    esac
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-escalate-test.XXXXXX")
    jq -c --arg id "vis-$n" --arg t "$title" --arg d "$body" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,"metadata":{},"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"vis-%s"}\n' "$n" ;;
  update)
    shift; id="$1"; shift
    if [ -n "${STUB_UPD_FAIL:-}" ]; then exit 1; fi
    case "${STUB_UPD_FAIL_MATCH:-}" in
      "") : ;;
      *) case "$*" in *"$STUB_UPD_FAIL_MATCH"*) exit 1 ;; esac ;;
    esac
    tmp=$(mktemp "${TMPDIR:-/tmp}/gctk-escalate-test.XXXXXX"); cp "$STORE" "$tmp"
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
unset GC_RIG STUB_LIST_FAIL STUB_CREATE_FAIL STUB_UPD_FAIL STUB_AGENTS_FAIL \
      STUB_CREATE_FAIL_MATCH STUB_UPD_FAIL_MATCH STUB_LIST_IGNORE_FIELDS 2>/dev/null || true
# The live agent set the route is matched against. converse exists ONLY
# rig-scoped, which is what makes the bare name unroutable.
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse"},
  {"qualified_name":"myrig/gc-toolkit.converse"},{"qualified_name":"other/rig.converse"},
  {"qualified_name":"gc-toolkit.dog"}]}'
# Most cases below are a rig-bound caller; the rig-less ones drop GC_RIG themselves.
export GC_RIG=gc-toolkit

# The store's standing triage subject, already open. An ephemeral subject is
# redirected onto it, so seeding it keeps a create count counting visits
# rather than the mint.
STANDING='{"id":"sub-0","status":"open","assignee":"","title":"triage: escalations raised from an ephemeral subject (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"ephemeral-subject-findings"},"notes":""}'

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
eq "$(meta vis-1 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "routed to the rig-qualified converse pool"
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
GC_RIG=other "$SUT" --subject tk-a --key k1 --message m --pool other/rig.converse >/dev/null 2>&1
eq "$(meta vis-1 gc.routed_to)" "other/rig.converse" "--pool overrides the default"

echo "# an unroutable route refuses BEFORE anything is created"
# Nothing filed is the point: a visit that exists and routes nowhere is worse
# than a loud refusal, because the caller reads exit 0 as "a human was asked".
reset
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "a rig-less caller's bare default exits 1"
eq "$(visits)" "0" "and files NOTHING — the refusal precedes the create"
has "$out" "matches no live agent identity" "says the route names no agent"
has "$out" "gc-toolkit/gc-toolkit.converse" "names the live rig-qualified forms"
has "$out" "repair:" "and prints the repair"

reset
out=$("$SUT" --subject tk-a --key k1 --message m --pool no/such.pool 2>&1); rc=$?
eq "$rc" 1 "an unknown --pool exits 1"
eq "$(visits)" "0" "and files nothing"

echo "# a live pool that does not read this rig's store is refused too"
# GC_RIG picks the store `gc bd create` writes to as well as the route, so a
# valid identity from ANOTHER rig never lists the store its visit lands in:
# well-formed is not reachable.
reset
out=$("$SUT" --subject tk-a --key k1 --message m --pool other/rig.converse 2>&1); rc=$?
eq "$rc" 1 "a cross-rig pool exits 1"
eq "$(visits)" "0" "and files nothing"
has "$out" "never reads" "says the pool does not read this store"

echo "# a rig-less caller's rig-qualified --pool selects the store too"
# The other half of the same invariant: the identity is live, so the route
# passes, and with GC_RIG unset the create lands in whatever store the ambient
# environment picks — well-formed, verified, and still in a store that pool
# never lists. Adopting the pool's rig is what keeps route and store together.
reset
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m \
  --pool gc-toolkit/gc-toolkit.converse 2>&1); rc=$?
eq "$rc" 0 "a rig-qualified --pool from a rig-less caller files"
eq "$(visits)" "1" "the visit exists"
eq "$(meta vis-1 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "routed to the pool it named"
hasnt "$(cat "$STUB_GC_LOG")" "[<unset>] bd " "no bd call ran against the ambient store"
has "$(cat "$STUB_GC_LOG")" "[gc-toolkit] bd create" "the create ran in the pool's rig store"
has "$out" "adopting rig 'gc-toolkit'" "and the adoption is announced"

reset
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m --pool no/such.pool 2>&1); rc=$?
eq "$rc" 1 "adopting a rig is not a bypass — an unheld pool is still refused"
eq "$(visits)" "0" "and files nothing"

reset
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m --pool gc-toolkit.dog 2>&1); rc=$?
eq "$rc" 0 "a bare pool a city agent holds still files"
has "$(cat "$STUB_GC_LOG")" "[<unset>] bd create" "and keeps the ambient store — there is no rig to adopt"

echo "# an unreadable agent set is not proof — it files, loudly unverified"
reset
out=$(STUB_AGENTS_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "an unreadable agent set still files"
eq "$(visits)" "1" "the visit exists"
has "$out" "UNVERIFIED" "and says the route was never verified"

echo "# a control byte in the agent set does not silently mute the check"
# A raw C0 byte anywhere in the payload aborts jq on the WHOLE document, which
# reads here as an empty identity set — the fail-open arm above, so the route
# would file UNVERIFIED and the check that just refused it would be gone. The
# scrub is what keeps the refusal reachable; without it this case files.
reset
out=$(STUB_AGENTS="$(printf '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse","work_query":"a\002b"}]}')" \
  env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "the bare default is still refused past a control byte"
eq "$(visits)" "0" "and nothing is filed"
has "$out" "matches no live agent identity" "the route was actually checked, not skipped"

echo "# idempotent: one open visit per key per durable subject"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a","task_kind":"visit"},"notes":""}]'
out=$("$SUT" --subject tk-a --key k1 --message "again" 2>&1); rc=$?
eq "$rc" 0 "an already-open situation exits 0"
eq "$(visits)" "0" "no second visit filed"
has "$out" "already open" "says the visit already exists"

reset '[{"id":"vis-0","status":"in_progress","assignee":"conv/1","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a CLAIMED (in_progress) visit also suppresses"

echo "# an already-open visit that routes nowhere is repointed, not counted"
# The create-side gate cannot reach a visit that already exists. One filed
# before it carries the unroutable name still, and every later pass matches
# that visit and exits 0 — the same mute, entered from the other side.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a repointed situation exits 0"
eq "$(visits)" "0" "no second visit filed"
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "the stale route is repaired in place"
has "$out" "repointing it at" "and the repoint is announced"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "a visit with NO route is repointed too"
eq "$(visits)" "0" "and still files nothing"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"other/rig.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "a cross-rig route is repointed at this store's pool"

echo "# a visit parked on the operator is left where it is"
# gc.routed_to=human is the city's "no agent will take it" marker, not a pool
# name that failed to resolve; repointing it hands an operator-owned item back
# to a pool.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"human","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a human-routed visit exits 0"
eq "$(meta vis-0 gc.routed_to)" "human" "and keeps its route"
eq "$(visits)" "0" "and files nothing"

echo "# …but a repoint that does not land is loud, not a quiet success"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(STUB_UPD_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "a failed repoint exits 1"
has "$out" "repair:" "and prints the repair command"

echo "# an unreadable agent set cannot condemn an existing route either"
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(STUB_AGENTS_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "an unprovable route leaves the visit alone"
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit.converse" "the route is not rewritten on no evidence"
has "$out" "UNVERIFIED" "and says so"

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
crowd="$crowd{\"id\":\"vis-0\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"gc.routed_to\":\"gc-toolkit/gc-toolkit.converse\",\"escalation_key\":\"k1\",\"gc.continuation_group\":\"tk-a\"},\"notes\":\"\"}]"
reset "$crowd"
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "the crowded-key situation exits 0"
eq "$(visits)" "0" "no duplicate filed past the 20-row window"
has "$out" "already open" "the existing visit was found"
has "$(cat "$STUB_GC_LOG")" "--metadata-field gc.continuation_group=tk-a" "the subject filter rides the listing itself"

echo "# an ephemeral subject dedups on the key alone"
# A patrol wisp is burned and re-poured every cycle, so its id names no durable
# subject. A situation it raises is identified by its key alone.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"doctor-fork-rate","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
out=$("$SUT" --subject lx-wisp-bbbbb --key doctor-fork-rate --message "fork rate high" 2>&1); rc=$?
eq "$rc" 0 "a differing ephemeral subject exits 0"
eq "$(visits)" "0" "the next cycle's wisp files no duplicate"
has "$out" "already open" "the previous cycle's visit was found"
hasnt "$(grep 'bd list' "$STUB_GC_LOG")" "gc.continuation_group" "the wisp subject does not ride the dedup listing"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-wisp-aaa"},"notes":""}]'
"$SUT" --subject tk-wisp-bbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a rig store's tk-wisp- ids are ephemeral too"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
"$SUT" --subject lx-wisp-aaaaa --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "the same wisp subject still dedups"

reset "[$STANDING,{\"id\":\"vis-0\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"escalation_key\":\"k2\",\"gc.continuation_group\":\"lx-wisp-aaaaa\"},\"notes\":\"\"}]"
"$SUT" --subject lx-wisp-bbbbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a different key still files, ephemeral subject or not"

reset "[$STANDING,{\"id\":\"vis-0\",\"status\":\"closed\",\"assignee\":\"\",\"metadata\":{\"escalation_key\":\"k1\",\"gc.continuation_group\":\"lx-wisp-aaaaa\"},\"notes\":\"\"}]"
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
  crowd="$crowd{\"id\":\"other-$i\",\"status\":\"open\",\"assignee\":\"\",\"metadata\":{\"gc.routed_to\":\"gc-toolkit/gc-toolkit.converse\",\"escalation_key\":\"doctor-fork-rate\",\"gc.continuation_group\":\"lx-wisp-c$i\"},\"notes\":\"\"},"
done
reset "${crowd%,}]"
"$SUT" --subject lx-wisp-fresh --key doctor-fork-rate --message m >/dev/null 2>&1
eq "$(visits)" "0" "20 cycles of one key file no 21st visit"

# The two arms meet here: the key-only match must carry its own route out of
# the listing, exactly as the subject-narrowed one does. A routable match is
# left alone; a route-less one is repaired rather than counted as satisfied,
# which is the state the cycles of wisp-subject visits are already in.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"doctor-fork-rate","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
out=$("$SUT" --subject lx-wisp-bbbbb --key doctor-fork-rate --message m 2>&1)
hasnt "$out" "repointed" "a routable key-only match is not repointed"
hasnt "$(cat "$STUB_GC_LOG")" "bd update vis-0" "and its route is not rewritten"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"doctor-fork-rate","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
out=$("$SUT" --subject lx-wisp-bbbbb --key doctor-fork-rate --message m 2>&1); rc=$?
eq "$rc" 0 "an unroutable visit matched by key alone exits 0"
eq "$(visits)" "0" "and no duplicate is filed"
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "the key-only match is repointed too"
has "$out" "repointed" "and says so"

echo "# an ephemeral subject is filed on a durable standing subject"
# The sitting writes its outcome to the subject and its takeaway to the item,
# which is the subject when the visit names no stall_root
# (agents/converse/prompt.template.md step 7). A wisp is burned at the end of
# its iteration, so a visit filed on one carries both writes to a bead that is
# gone before anyone claims it.
reset
out=$("$SUT" --subject lx-wisp-aaaaa --key doctor-fork-rate --message "fork rate high" 2>&1); rc=$?
eq "$rc" 0 "an ephemeral subject files"
eq "$(visits)" "2" "the standing subject is minted alongside the visit"
eq "$(meta vis-1 task_kind)" "triage-subject" "the minted bead is a standing triage subject"
eq "$(meta vis-1 triage.scope)" "ephemeral-subject-findings" "carrying the scope the lookup filters on"
has "$(field vis-1 title)" "triage: escalations raised from an ephemeral subject" "and a title that says what hangs there"
eq "$(meta vis-2 gc.continuation_group)" "vis-1" "the visit's group is the standing subject, not the wisp"
has "$(cat "$STUB_DEPS")" "vis-2|vis-1|tracks" "and its tracks edge points there too"
hasnt "$(cat "$STUB_DEPS")" "lx-wisp-aaaaa" "nothing is wired to the wisp"
has "$(field vis-2 title)" "visit: vis-1" "the title names the durable subject"
eq "$(meta vis-2 escalation_raised_by)" "lx-wisp-aaaaa" "the raising wisp survives as provenance"
has "$(field vis-2 description)" "lx-wisp-aaaaa" "and the body names it, for the sitting that reads it"
has "$out" "is ephemeral and cannot receive" "the redirect is announced"
has "$(cat "$STUB_GC_LOG")" "--metadata-field task_kind=triage-subject" "both markers ride the standing-subject lookup"
has "$(cat "$STUB_GC_LOG")" "--metadata-field triage.scope=ephemeral-subject-findings" "including the scope"

echo "# …reusing the one that is already open, never minting a second"
reset "[$STANDING]"
"$SUT" --subject lx-wisp-bbbbb --key doctor-fork-rate --message m >/dev/null 2>&1
eq "$(visits)" "1" "only the visit is created"
eq "$(meta vis-1 gc.continuation_group)" "sub-0" "it hangs on the standing subject already there"
eq "$(meta vis-1 escalation_raised_by)" "lx-wisp-bbbbb" "with this cycle's wisp recorded"

echo "# two findings share the bucket but keep their own escalation_key"
# The subject no longer tells them apart, so the key is the only thing that
# does. The converse fold check resolves a visit's topic as stall_root, else
# the key, else the subject, and a redirected visit names no stall_root
# (agents/converse/prompt.template.md). A visit that reached the bucket
# without its own key would fold into its sibling and close unread.
reset "[$STANDING]"
"$SUT" --subject lx-wisp-aaaaa --key doctor-dolt-noms-size --message m >/dev/null 2>&1
"$SUT" --subject lx-wisp-bbbbb --key doctor-check-cadence-live --message m >/dev/null 2>&1
eq "$(visits)" "2" "each situation files its own visit"
eq "$(meta vis-1 gc.continuation_group)" "sub-0" "both hang on the one standing subject"
eq "$(meta vis-2 gc.continuation_group)" "sub-0" "sharing the bucket"
eq "$(meta vis-1 escalation_key)" "doctor-dolt-noms-size" "the first carries its own key"
eq "$(meta vis-2 escalation_key)" "doctor-check-cadence-live" "and the second a different one"

# A closed subject cannot receive an append or a takeaway either.
reset "[$(printf '%s' "$STANDING" | sed 's/"status":"open"/"status":"closed"/')]"
"$SUT" --subject lx-wisp-ccccc --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "2" "a CLOSED standing subject is not reused — a fresh one is minted"

echo "# a durable subject is never redirected"
reset
"$SUT" --subject tk-stuck --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "no standing subject is minted"
eq "$(meta vis-1 gc.continuation_group)" "tk-stuck" "the subject stays the bead the caller named"
eq "$(meta vis-1 escalation_raised_by)" "<absent>" "and no provenance is invented"
hasnt "$(cat "$STUB_GC_LOG")" "task_kind=triage-subject" "the standing-subject lookup never runs"

echo "# the redirect never runs on a path that files nothing"
# The mint sits after the dedup and after the route check, so neither a
# suppressed escalation nor a refused one leaves a bucket behind.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"lx-wisp-aaaaa"},"notes":""}]'
"$SUT" --subject lx-wisp-bbbbb --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a deduped ephemeral escalation mints nothing"

reset
out=$("$SUT" --subject lx-wisp-aaaaa --key k1 --message m --pool no/such.pool 2>&1); rc=$?
eq "$rc" 1 "an unroutable ephemeral escalation still exits 1"
eq "$(visits)" "0" "and mints nothing — the refusal precedes every create"

echo "# a standing subject that cannot be minted files on the wisp, loudly"
# The trade the whole script is built on: a visit whose disposition will be
# lost has still asked a human, and filing nothing asks nobody.
reset
out=$(STUB_CREATE_FAIL_MATCH="triage:" "$SUT" --subject lx-wisp-aaaaa --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "the escalation still files"
eq "$(visits)" "1" "exactly the visit"
eq "$(meta vis-1 gc.continuation_group)" "lx-wisp-aaaaa" "on the wisp, nothing durable having been resolved"
has "$out" "will be lost when it burns" "and says what that costs"

echo "# markers that do not read back cost the NEXT escalation, not this one"
reset
out=$(STUB_UPD_FAIL_MATCH="triage.scope" "$SUT" --subject lx-wisp-aaaaa --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "the escalation files"
eq "$(meta vis-2 gc.continuation_group)" "vis-1" "the visit hangs on it — an unmarked bead is still durable"
has "$out" "markers did not read back" "the lost markers are reported"
has "$out" "repair:" "with the repair that makes it findable again"

# A listing that ignored its filters answers with an unrelated open bead. The
# re-check refuses it, so the visit is never wired to a bead nobody escalated
# about.
reset '[{"id":"other","status":"open","assignee":"","title":"an unrelated open bead","metadata":{},"notes":""}]'
STUB_LIST_IGNORE_FIELDS=1 "$SUT" --subject lx-wisp-aaaaa --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-1 task_kind)" "triage-subject" "an unfiltered answer is refused and a bucket minted instead"
eq "$(meta vis-2 gc.continuation_group)" "vis-1" "the visit hangs on the minted bucket"
hasnt "$(cat "$STUB_DEPS")" "|other|" "and no edge reaches the unrelated bead"

# The same fail-open the dedup listing takes: an unreadable lookup mints a
# second bucket rather than dropping the subject.
reset "[$STANDING]"
STUB_LIST_FAIL=1 "$SUT" --subject lx-wisp-aaaaa --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "2" "an unreadable lookup mints a duplicate bucket rather than filing on the wisp"

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

echo "# the deacon's filed visits reach its incident ledger"
# escalate.sh calls the ledger by sibling path, so the SUT runs from a private
# copy with a RECORDING gc-deacon-ledger.sh beside it. Nothing here touches the
# real ledger script; what is under test is which calls escalate.sh makes.
LSUT="$TMP/sut"; mkdir -p "$LSUT"
cp "$SUT" "$LSUT/escalate.sh"; chmod +x "$LSUT/escalate.sh"
cat > "$LSUT/gc-deacon-ledger.sh" <<'LSTUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_LEDGER_LOG:?}"
[ -n "${STUB_LEDGER_FAIL:-}" ] && exit 1
exit 0
LSTUB
chmod +x "$LSUT/gc-deacon-ledger.sh"
export STUB_LEDGER_LOG="$TMP/ledger.log"
ledger() { cat "$STUB_LEDGER_LOG" 2>/dev/null; }
lreset() { reset "${1:-[]}"; : > "$STUB_LEDGER_LOG"; }

lreset
out=$(GC_AGENT=deacon "$LSUT/escalate.sh" --subject tk-a --key dolt-backup-loomington \
        --message "manifest is 30h old (>12h = 2x backup cadence)" 2>&1); rc=$?
eq "$rc" 0 "filing still exits 0 with the ledger wired in"
eq "$(ledger | grep -c .)" "1" "a filed visit appends exactly one ledger entry"
has "$(ledger)" "append escalation" "recorded under the escalation category"
has "$(ledger)" "dolt-backup-loomington: manifest is 30h old" "carrying the situation key and the headline"
has "$(ledger)" "bead:vis-1" "and pointing at the visit it filed"

lreset
GC_AGENT=gc-toolkit/gc-toolkit.polecat "$LSUT/escalate.sh" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(ledger | grep -c .)" "0" "a polecat's escalation writes nothing to the deacon's ledger"
lreset
GC_AGENT="" "$LSUT/escalate.sh" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(ledger | grep -c .)" "0" "an unidentified caller writes nothing either"

echo "## a repeat is not a second incident"
lreset
GC_AGENT=deacon "$LSUT/escalate.sh" --subject tk-a --key k1 --message m >/dev/null 2>&1
GC_AGENT=deacon "$LSUT/escalate.sh" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "the second call dedups as before"
eq "$(ledger | grep -c .)" "1" "and appends nothing the second time"

echo "## a ledger that fails never costs the visit"
lreset
out=$(STUB_LEDGER_FAIL=1 GC_AGENT=deacon "$LSUT/escalate.sh" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a failed ledger append does not change the exit"
eq "$(visits)" "1" "the visit is filed"
has "$out" "ledger entry was not written" "and the loss is reported"
lreset
rm -f "$LSUT/gc-deacon-ledger.sh"
out=$(GC_AGENT=deacon "$LSUT/escalate.sh" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a missing ledger script does not change the exit either"
has "$out" "absent from the ledger" "and says the visit went unrecorded"

echo "# usage"
out=$("$SUT" --subject tk-a --key k1 2>&1); rc=$?
eq "$rc" 2 "missing --message is a usage error"
out=$("$SUT" --subject tk-a --key "bad key!" --message m 2>&1); rc=$?
eq "$rc" 2 "a key outside [A-Za-z0-9._-] is rejected"
out=$("$SUT" --subject tk-a --key k1 --message m --nonsense 2>&1); rc=$?
eq "$rc" 2 "an unknown argument is rejected"

echo "# a moot or benign verdict suppresses a re-file inside the window"
# The open-visit dedup above sees only OPEN visits, so without this window a
# detector whose condition outlives the sitting re-files the identical
# situation on its next cycle. moot and benign are the two verdicts that mean
# no human was needed, so only they suppress.
ago() { date -u -d "@$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ; }
closed_visit() {  # id key subject outcome age_seconds [recurrences]
  printf '{"id":"%s","status":"closed","title":"t","description":"d","notes":"","closed_at":"%s","metadata":{"task_kind":"visit","escalation_key":"%s","gc.continuation_group":"%s","gc.outcome":"%s"%s}}' \
    "$1" "$(ago "$5")" "$2" "$3" "$4" "${6:+,\"escalation.recurrences\":\"$6\"}"
}

for verdict in moot benign; do
  reset "[$(closed_visit v-old k1 tk-a "$verdict" 3600)]"
  out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
  eq "$rc" 0 "a $verdict verdict an hour old exits 0"
  eq "$(visits)" "0" "and files NOTHING — the sitting already answered this"
  has "$out" "was answered '$verdict'" "names the verdict it is honoring"
  has "$out" "v-old" "and the visit that carries it"
  eq "$(meta v-old escalation.recurrences)" "1" "the suppressed repeat is tallied, not silent"
  eq "$(meta v-old escalation.recurrence_last)" "$(meta v-old escalation.recurrence_last)" "and stamped with when"
done

echo "# the tally counts up from what the visit already carries"
reset "[$(closed_visit v-old k1 tk-a moot 3600 7)]"
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta v-old escalation.recurrences)" "8" "an existing tally increments"

echo "# the window only holds while it is open"
reset "[$(closed_visit v-old k1 tk-a moot 90000)]"
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a verdict older than the window files"
eq "$(visits)" "1" "the visit exists"
eq "$(meta v-old escalation.recurrences)" "<absent>" "and nothing is tallied on the expired verdict"

echo "# only moot and benign suppress — every other outcome means the sitting acted"
for verdict in ruled routed disposed folded cut-short; do
  reset "[$(closed_visit v-old k1 tk-a "$verdict" 3600)]"
  "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
  eq "$(visits)" "1" "a '$verdict' verdict does not suppress"
done
reset "[$(closed_visit v-old k1 tk-a "" 3600)]"
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a closed visit with no outcome at all does not suppress"

echo "# the window is scoped to the situation, exactly like the open dedup"
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
"$SUT" --subject tk-a --key k2 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a different key on the same subject is unaffected"
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
"$SUT" --subject tk-b --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a different subject under the same key is unaffected"

echo "# the NEWEST verdict decides, across every outcome, not the moot the filter reached first"
# The lookup takes the newest closed visit and suppresses only when THAT one is
# moot or benign. An older moot still inside the window must not mute a
# situation a later sitting has since ruled on; both orderings are checked.
reset "[$(closed_visit v-ruled k1 tk-a ruled 600),$(closed_visit v-moot k1 tk-a moot 3600)]"
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "an older moot INSIDE the window behind a newer ruling does not suppress"
reset "[$(closed_visit v-ruled k1 tk-a ruled 200000),$(closed_visit v-moot k1 tk-a moot 3600)]"
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1)
eq "$(visits)" "0" "a newer moot behind an older ruling does suppress"
has "$out" "v-moot" "and it is the newest verdict that is named"

echo "# an ephemeral subject matches on the key alone, as its open dedup does"
# A patrol wisp is burned and re-poured every cycle, so its id cannot identify
# a situation from one call to the next.
reset "[$(closed_visit v-old wedged-lx-1 tk-wisp-aaa moot 3600)]"
out=$("$SUT" --subject tk-wisp-bbb --key wedged-lx-1 --message m 2>&1); rc=$?
eq "$rc" 0 "a wisp subject honors the verdict its predecessor earned"
eq "$(visits)" "0" "and files nothing"

echo "# an OPEN visit still outranks the window"
reset "[{\"id\":\"v-open\",\"status\":\"open\",\"title\":\"t\",\"description\":\"d\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"visit\",\"escalation_key\":\"k1\",\"gc.continuation_group\":\"tk-a\",\"gc.routed_to\":\"gc-toolkit/gc-toolkit.converse\"}},$(closed_visit v-old k1 tk-a moot 3600)]"
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1)
has "$out" "already open" "the open-visit answer is the one given"
eq "$(meta v-old escalation.recurrences)" "<absent>" "and the closed verdict is not tallied for it"

echo "# the window is tunable and can be turned off"
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
GC_ESCALATE_VERDICT_WINDOW=0 "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "GC_ESCALATE_VERDICT_WINDOW=0 disables the window"
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
GC_ESCALATE_VERDICT_WINDOW=600 "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a window narrower than the verdict's age files"
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
GC_ESCALATE_VERDICT_WINDOW=notanumber "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "0" "a malformed window falls back to the default rather than opening the gate"

echo "# a closed visit with an unparseable or missing timestamp never suppresses"
# Absent is unknown, and unknown must file: the mute this script exists to end
# is worse than a duplicate.
reset '[{"id":"v-old","status":"closed","title":"t","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"k1","gc.continuation_group":"tk-a","gc.outcome":"moot"}}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a verdict with no closed_at files"
reset '[{"id":"v-old","status":"closed","title":"t","description":"d","notes":"","closed_at":"not-a-date","metadata":{"task_kind":"visit","escalation_key":"k1","gc.continuation_group":"tk-a","gc.outcome":"moot"}}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(visits)" "1" "a verdict with an unparseable closed_at files"

echo "# a recurrence that cannot be recorded still suppresses"
# The tally is evidence, not the gate: losing it must not re-open the storm.
reset "[$(closed_visit v-old k1 tk-a moot 3600)]"
out=$(STUB_UPD_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a failed tally write still exits 0"
eq "$(visits)" "0" "and still files nothing"
has "$out" "could not record the recurrence" "and says the tally was lost"

echo
echo "escalate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
