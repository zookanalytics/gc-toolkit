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
# A --db path selects the store a bd call reads and writes, ahead of GC_RIG and
# the working directory, as it does for the real gc bd. Without one the call
# answers from the ambient store, STUB_STORE. STUB_DBS maps each rig's .beads
# path to its store file, and a path it does not map is refused the way bd
# refuses a store it cannot open. The pair is lifted out before the dispatch
# below, so positional arguments keep their places.
if [ "${1:-}" = "bd" ]; then
  db=""; rest=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --db)   db="${2:-}"; shift; shift || true ;;
      --db=*) db="${1#--db=}"; shift ;;
      *)      rest+=("$1"); shift ;;
    esac
  done
  set -- ${rest[@]+"${rest[@]}"}
  if [ -n "$db" ]; then
    STORE=$(printf '%s' "${STUB_DBS:-}" | jq -r --arg p "$db" '.[$p] // empty' 2>/dev/null)
    [ -n "$STORE" ] || { echo "bd: no beads database at $db" >&2; echo '{"error":"no beads database"}'; exit 1; }
  fi
fi
if [ "${1:-}" = "agent" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_AGENTS:-}"
  exit 0
fi
# The city's rig set, by id prefix. escalate.sh reads this to pin the store to
# the subject's own rig when the route defaults to the board and GC_RIG is unset.
if [ "${1:-}" = "rig" ] && [ "${2:-}" = "list" ]; then
  [ -n "${STUB_RIG_LIST_FAIL:-}" ] && { echo "gc: rig list unavailable" >&2; exit 1; }
  printf '%s\n' "${STUB_RIGS:-}"
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
    title=""; body=""; meta="{}"
    while [ $# -gt 0 ]; do
      case "$1" in
        --title) shift; title="$1" ;;
        -d) shift; body="$1" ;;
        --metadata) shift; meta="${1:-}"; [ -n "$meta" ] || meta="{}" ;;
      esac
      shift || true
    done
    # A create that returns an id but drops the metadata — the readback guard's
    # reason to exist. Distinct from STUB_UPD_FAIL, which no longer touches the
    # identity stamps now that they ride the create.
    [ -n "${STUB_CREATE_NOMETA:-}" ] && meta="{}"
    # One create can fail while another lands: the run that mints a standing
    # subject issues two, and the fail-open arm is only reachable when the
    # first fails by itself.
    case "${STUB_CREATE_FAIL_MATCH:-}" in
      "") : ;;
      *) case "$title" in *"$STUB_CREATE_FAIL_MATCH"*) echo "bd: refused" >&2; exit 1 ;; esac ;;
    esac
    n=$(cat "$STUB_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$STUB_SEQ"
    tmp=$(mktemp "${STUB_TMP:-${TMPDIR:-/tmp}}/gctk-escalate-test.XXXXXX")
    # The real `gc bd create` stamps --metadata (a JSON object) into the bead
    # atomically with the create; model that so the create carries the identity
    # the same way, and a run whose follow-up writes are lost still leaves a
    # dedup-complete visit.
    jq -c --arg id "vis-$n" --arg t "$title" --arg d "$body" --argjson m "$meta" \
      '. + [{"id":$id,"status":"open","assignee":"","title":$t,"description":$d,"metadata":$m,"notes":""}]' \
      "$STORE" > "$tmp" && mv "$tmp" "$STORE"
    printf '{"id":"vis-%s"}\n' "$n" ;;
  update)
    shift; id="$1"; shift
    if [ -n "${STUB_UPD_FAIL:-}" ]; then exit 1; fi
    case "${STUB_UPD_FAIL_MATCH:-}" in
      "") : ;;
      *) case "$*" in *"$STUB_UPD_FAIL_MATCH"*) exit 1 ;; esac ;;
    esac
    tmp=$(mktemp "${STUB_TMP:-${TMPDIR:-/tmp}}/gctk-escalate-test.XXXXXX"); cp "$STORE" "$tmp"
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
    # bd writes an edge into the store the call addressed, so the line names it.
    [ "${2:-}" = "add" ] && printf '%s|%s|%s|%s\n' "$3" "$4" "${5#--type=}" "$(basename "$STORE")" >> "$DEPS"
    echo "dep added" ;;
esac
STUB
chmod +x "$BIN/gc"

# Fake visit-close.sh for the --retract path: record each call as
# `<visit>|<subject>|<outcome>|<reason>` and, so the not-closed arm can be
# exercised, exit non-zero when STUB_VISIT_CLOSE_FAIL is set, or for the one
# visit STUB_VISIT_CLOSE_FAIL_ID names — as the real visit-close.sh exits
# non-zero when the close does not land. escalate.sh reaches
# it through the GC_ESCALATE_VISIT_CLOSE_TOOL override, so the real one beside the
# SUT is never touched.
cat > "$BIN/visit-close.sh" <<'VC'
#!/usr/bin/env bash
visit=""; subject=""; outcome=""; reason=""
while [ $# -gt 0 ]; do
  case "$1" in
    --visit)   visit="${2:-}";   shift 2 ;;
    --subject) subject="${2:-}"; shift 2 ;;
    --outcome) outcome="${2:-}"; shift 2 ;;
    --reason)  reason="${2:-}";  shift 2 ;;
    --force)   shift ;;
    *)         shift ;;
  esac
done
printf '%s|%s|%s|%s\n' "$visit" "$subject" "$outcome" "$reason" >> "${STUB_VISIT_CLOSE_LOG:?}"
[ -n "${STUB_VISIT_CLOSE_FAIL:-}" ] && exit 4
[ -n "${STUB_VISIT_CLOSE_FAIL_ID:-}" ] && [ "$visit" = "$STUB_VISIT_CLOSE_FAIL_ID" ] && exit 4
exit 0
VC
chmod +x "$BIN/visit-close.sh"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/store.json" STUB_DEPS="$TMP/deps" STUB_GC_LOG="$TMP/gc.log" STUB_SEQ="$TMP/seq"
# The stub keeps its scratch here, so a case that points the SUT's TMPDIR at a
# missing directory breaks only the SUT's own temp files, not the stub store.
export STUB_TMP="$TMP"
export GC_ESCALATE_VISIT_CLOSE_TOOL="$BIN/visit-close.sh" STUB_VISIT_CLOSE_LOG="$TMP/visit-close.log"
unset GC_RIG STUB_LIST_FAIL STUB_CREATE_FAIL STUB_UPD_FAIL STUB_AGENTS_FAIL \
      STUB_CREATE_FAIL_MATCH STUB_UPD_FAIL_MATCH STUB_LIST_IGNORE_FIELDS STUB_RIG_LIST_FAIL \
      STUB_CREATE_NOMETA 2>/dev/null || true
# The live agent set the route is matched against. converse exists ONLY
# rig-scoped, which is what makes the bare name unroutable.
export STUB_AGENTS='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse"},
  {"qualified_name":"myrig/gc-toolkit.converse"},{"qualified_name":"other/rig.converse"},
  {"qualified_name":"gc-toolkit.dog"}]}'
# The city's rigs, keyed by id prefix. The subject in these cases is tk-a, so a
# board-route caller derives its store from prefix 'tk' -> gc-toolkit, and pins
# every call to that rig's .beads path, which maps to the ambient store file:
# a case below that seeds STUB_STORE seeds the store the subject lives in.
export STUB_RIGS='{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":"/nonexistent-rig"}]}'
export STUB_DBS="{\"/nonexistent-rig/.beads\":\"$STUB_STORE\"}"
# Most cases below are a rig-bound caller; the rig-less ones drop GC_RIG themselves.
export GC_RIG=gc-toolkit

# The store's standing triage subject, already open. An ephemeral subject is
# redirected onto it, so seeding it keeps a create count counting visits
# rather than the mint.
STANDING='{"id":"sub-0","status":"open","assignee":"","title":"triage: escalations raised from an ephemeral subject (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"ephemeral-subject-findings"},"notes":""}'

reset() {
  printf '%s' "${1:-[]}" > "$STUB_STORE"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; printf '0' > "$STUB_SEQ"
  : > "$STUB_VISIT_CLOSE_LOG"; unset STUB_VISIT_CLOSE_FAIL STUB_VISIT_CLOSE_FAIL_ID 2>/dev/null || true
}
meta()   { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
field()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .[$k]) // "<absent>"' "$STUB_STORE"; }
visits() { cat "$STUB_SEQ"; }   # creates issued since reset (the seed bead is vis-0)
vclog()  { cat "$STUB_VISIT_CLOSE_LOG"; }        # visit-close.sh calls the retract made
vccount(){ wc -l < "$STUB_VISIT_CLOSE_LOG" | tr -d ' '; }   # how many calls

echo "# files a visit in the canonical gate-visit shape"
reset
out=$("$SUT" --subject tk-stuck --key merge-conflict --message "PR#7 is CONFLICTING; needs a human rebase decision" 2>&1); rc=$?
eq "$rc" 0 "filing exits 0"
eq "$(visits)" "1" "exactly one visit filed"
has "$(field vis-1 title)" "visit: tk-stuck — PR#7 is CONFLICTING" "title carries the visit brand, subject and headline"
eq "$(meta vis-1 gc.routed_to)" "human" "parked on the board (the default route, since the converse pool is retired)"
eq "$(meta vis-1 gc.continuation_group)" "tk-stuck" "continuation group is the subject"
eq "$(meta vis-1 task_kind)" "visit" "task_kind=visit stamped"
eq "$(meta vis-1 escalation_key)" "merge-conflict" "escalation_key stamped"
has "$(cat "$STUB_DEPS")" "vis-1|tk-stuck|tracks" "visit tracks the subject (never parent-child)"
hasnt "$(cat "$STUB_DEPS")" "parent-child" "no parent-child edge"
has "$out" "filed visit vis-1" "reports what it filed"

echo "# the default route is human, and --pool overrides it"
# The converse routed-pool is retired: the default is the board (human), which
# needs no live-agent match. --pool still routes to a pool.
reset
GC_RIG=gc-toolkit "$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-1 gc.routed_to)" "human" "the default route is the board"
reset
GC_RIG=other "$SUT" --subject tk-a --key k1 --message m --pool other/rig.converse >/dev/null 2>&1
eq "$(meta vis-1 gc.routed_to)" "other/rig.converse" "--pool overrides the default"

echo "# a board-route caller whose GC_RIG is not the subject's rig files in the subject's store"
# `human` names no store, and `gc bd` only WARNS on a GC_RIG that names no bound
# rig before answering from the working directory, so a stale or misspelled
# export cannot be trusted to select the store. The subject's own rig
# (tk -> gc-toolkit) is the store the visit belongs in, and every call is pinned
# there by path, so the caller's GC_RIG is overridden, loudly, not obeyed.
reset
out=$(GC_RIG=myrig "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "GC_RIG naming a rig other than the subject's still files"
eq "$(visits)" "1" "the visit exists"
eq "$(meta vis-1 gc.continuation_group)" "tk-a" "in the store the subject lives in"
has "$out" "lives in rig 'gc-toolkit'" "and the override names the rig the subject lives in"
eq "$(grep -c ' bd ' "$STUB_GC_LOG")" "$(grep ' bd ' "$STUB_GC_LOG" | grep -c -- '--db /nonexistent-rig/.beads')" "every bd call is pinned to the subject's store by path"
has "$(cat "$STUB_GC_LOG")" "[gc-toolkit] bd create" "and GC_RIG is rebound to the subject's rig for the calls it reaches"

echo "# a rig-less board-route caller pins the store to the subject's own rig"
# The board route ('human') names no store, so a rig-less caller cannot let the
# create fall to the ambient store — the visit and its tracks edge would land
# severed from the subject. escalate derives the store from the subject's id
# prefix (tk -> gc-toolkit) and files there.
reset
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a rig-less board-route caller files once it derives the subject's rig"
eq "$(visits)" "1" "the visit exists"
eq "$(meta vis-1 gc.routed_to)" "human" "routed to the board"
has "$(cat "$STUB_GC_LOG")" "[gc-toolkit] bd create" "the create runs under the derived rig, not the ambient store"
has "$(cat "$STUB_GC_LOG")" "bd create -t task --title visit: tk-a" "the visit create is the one pinned"
has "$(grep 'bd create' "$STUB_GC_LOG")" "--db /nonexistent-rig/.beads" "  ... to the subject's store by path"
has "$out" "deriving rig 'gc-toolkit'" "and says which store it pinned"

echo "# a city-store subject's visit lands in the city store, wherever the caller sits"
# The city's own store has no rig name `gc bd` honors: GC_RIG set to the city's
# rig name draws a warning and is ignored, and the call answers from the
# caller's working directory. Only a path selects it. The ambient store stands
# in for a caller's rig checkout here, so whether the caller's GC_RIG is its own
# rig (gc-toolkit), the city's rig name as escalation-rig.sh prints it, or
# unset, the visit, its tracks edge and every read must reach the city store
# by path.
CITY_STORE="$TMP/city.json"
CITY_RIGS='{"rigs":[{"name":"loomington","prefix":"lx","path":"/city","hq":true},
  {"name":"gc-toolkit","prefix":"tk","path":"/nonexistent-rig"}]}'
CITY_DBS="{\"/nonexistent-rig/.beads\":\"$STUB_STORE\",\"/city/.beads\":\"$CITY_STORE\"}"
run_city() { # <caller GC_RIG, empty = unset> <escalate args...>
  local rig="$1"; shift
  if [ -n "$rig" ]; then
    GC_RIG="$rig" STUB_RIGS="$CITY_RIGS" STUB_DBS="$CITY_DBS" "$SUT" "$@"
  else
    env -u GC_RIG STUB_RIGS="$CITY_RIGS" STUB_DBS="$CITY_DBS" "$SUT" "$@"
  fi
}
city_visits() { jq -r '[.[] | select(.metadata.task_kind == "visit") | .metadata["gc.continuation_group"]] | join(",")' "$CITY_STORE"; }
# A logged call runs onto further lines when an argument carries newlines, as an
# ephemeral subject's visit body does, so each entry is rejoined before it is read.
bd_calls() { awk '/^\[[^]]*\] /{if (c != "") print c; c=$0; next} {c=c " " $0} END{if (c != "") print c}' "$STUB_GC_LOG" | grep ' bd '; }
pinned_to_city() { [ "$(bd_calls | grep -c .)" = "$(bd_calls | grep -c -- '--db /city/.beads')" ]; }
for caller in gc-toolkit loomington ""; do
  label="GC_RIG=${caller:-<unset>}"
  reset; printf '[]' > "$CITY_STORE"
  out=$(run_city "$caller" --subject lx-hq1 --key k1 --message m 2>&1); rc=$?
  eq "$rc" 0 "$label: an lx- subject's escalation files"
  eq "$(city_visits)" "lx-hq1" "  ... its visit is in the city store"
  eq "$(jq 'length' "$STUB_STORE")" "0" "  ... and nothing landed in the caller's rig store"
  has "$(cat "$STUB_DEPS")" "vis-1|lx-hq1|tracks|city.json" "  ... the tracks edge is written in the city store, beside its subject"
  if pinned_to_city; then ok "  ... every bd call was pinned to the city store by path"
  else bad "  ... every bd call was pinned to the city store by path ($(grep ' bd ' "$STUB_GC_LOG" | grep -v -- '--db /city/.beads' | head -n 1))"; fi
done
reset; printf '[]' > "$CITY_STORE"
out=$(run_city gc-toolkit --subject lx-hq1 --key k1 --message m 2>&1)
has "$out" "lives in rig 'loomington'" "a rig caller's GC_RIG is overridden with a warning that names the subject's rig"

echo "# a board-route caller whose subject names no placeable bead redirects it to triage"
# zz-a is a bead-shaped id whose prefix no readable rig carries: escalation-rig
# PROVES it is no bead (exit 1), distinct from a store it merely could not read.
# There is no durable subject to scope a visit to and a tracks edge to it would
# fail, so it is ephemeral. The old path refused outright with GC_RIG unset,
# dropping the escalation; now it files on the standing triage subject in the
# ambient store — a duplicate-or-ambient visit beats a silent mute.
reset
out=$(env -u GC_RIG "$SUT" --subject zz-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a proven-no-bead subject files rather than refusing"
eq "$(visits)" "2" "the standing triage subject is minted alongside the visit"
eq "$(meta vis-1 task_kind)" "triage-subject" "the minted bead is the standing triage subject"
eq "$(meta vis-2 gc.continuation_group)" "vis-1" "the visit hangs on the triage subject, not zz-a"
eq "$(meta vis-2 escalation_raised_by)" "zz-a" "and zz-a survives as provenance"
hasnt "$(cat "$STUB_DEPS")" "|zz-a|" "no tracks edge is wired to the non-bead subject"
has "$out" "is ephemeral and cannot receive" "the redirect is announced"

echo "# a rig-less board-route caller REFUSES when the rig set is unreadable"
reset
out=$(env -u GC_RIG STUB_RIG_LIST_FAIL=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "an unreadable rig set on the board route exits 1 (fail closed)"
eq "$(visits)" "0" "and files nothing"
has "$out" "could not read" "and says the rig set was unreadable, not that the prefix is unknown"

echo "# a store helper that cannot run proves nothing, so a real subject is never redirected"
# escalation-rig's exit 1 proves the subject names no bead, and that subject is
# redirected onto the triage subject by --key alone. A bead-store.sh that cannot
# be run asked no store, so tk-a may still be a real bead: the board route with
# GC_RIG unset refuses, and a pinned GC_RIG files on tk-a itself.
reset
out=$(env -u GC_RIG GC_BEAD_STORE_TOOL="$TMP/no-such-bead-store.sh" "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "an unrunnable store helper on the board route exits 1 (fail closed)"
eq "$(visits)" "0" "and files nothing, on the triage subject or anywhere else"
has "$out" "cannot execute" "and the refusal says why the store is unproven"

reset
out=$(GC_RIG=gc-toolkit GC_BEAD_STORE_TOOL="$TMP/no-such-bead-store.sh" "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "with GC_RIG pinned it files under the pin"
eq "$(visits)" "1" "one visit, and no triage subject minted"
eq "$(meta vis-1 gc.continuation_group)" "tk-a" "the visit hangs on tk-a, not on the triage subject"
has "$(cat "$STUB_DEPS")" "vis-1|tk-a|tracks" "and tracks tk-a"

echo "# a stderr capture that cannot be opened proves nothing, so a real subject keeps its own dedup"
# bash runs no command whose redirection it cannot open and reports exit 1, the
# code escalation-rig gives a subject proven to name no bead. With TMPDIR missing,
# tk-a is still classified by escalation-rig's own answer: deduped on tk-a, not on
# the key alone, so an open visit for another subject under the same key does not
# swallow it.
reset '[{"id":"vis-o","status":"open","assignee":"","title":"visit: tk-other — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"k1","gc.continuation_group":"tk-other","gc.routed_to":"human"}}]'
out=$(TMPDIR="$TMP/no-such-tmpdir" "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "filing with an unusable TMPDIR exits 0"
eq "$(visits)" "1" "a visit is filed for tk-a, not deduped against tk-other's under the same key"
eq "$(meta vis-1 gc.continuation_group)" "tk-a" "on tk-a itself, not on the triage subject"
has "$(cat "$STUB_DEPS")" "vis-1|tk-a|tracks" "and it tracks tk-a"

echo "# the empty-identity fallback subject ('refinery') redirects to triage, never drops"
# mol-refinery-patrol's validate-identity step escalates with
# --subject "${GC_SESSION_ID:-refinery}"; with GC_SESSION_ID empty the literal
# "refinery" is no bead at all (no <prefix>-<id> shape). Filing a visit on it
# severed its tracks edge, and on the board route with GC_RIG unset the old path
# dropped the escalation outright — the exact silent mute this very escalation
# exists to report. It is ephemeral now: redirected onto the standing triage
# subject, under the pinned store or, failing that, the ambient one.
reset
out=$(GC_RIG=gc-toolkit "$SUT" --subject refinery --key refinery-empty-identity --message m 2>&1); rc=$?
eq "$rc" 0 "a bare non-bead subject files"
eq "$(visits)" "2" "redirected onto a freshly-minted triage subject"
eq "$(meta vis-2 gc.continuation_group)" "vis-1" "the visit hangs on the triage subject, not 'refinery'"
hasnt "$(cat "$STUB_DEPS")" "|refinery|" "and no tracks edge is wired to the non-bead literal"
hasnt "$(cat "$STUB_GC_LOG")" "--db" "with no store path to pin, every call answers from the GC_RIG store"

reset
out=$(env -u GC_RIG "$SUT" --subject refinery --key refinery-empty-identity --message m 2>&1); rc=$?
eq "$rc" 0 "and with GC_RIG unset it still files — the empty-identity drop is closed"
eq "$(visits)" "2" "on the standing triage subject in the ambient store"
eq "$(meta vis-2 escalation_raised_by)" "refinery" "the fallback literal survives as provenance"

echo "# a rig that reports no path has no store to pin"
# The prefix names a rig, but a rig with no path cannot be addressed by --db,
# and `gc bd` ignores an unbound rig's name as GC_RIG. Its store is unproven.
reset
out=$(env -u GC_RIG STUB_RIGS='{"rigs":[{"name":"gc-toolkit","prefix":"tk","path":""}]}' \
  "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "a rig-less caller refuses a subject whose rig reports no path"
eq "$(visits)" "0" "  ... and files nothing"
has "$out" "reports no path" "  ... naming why the store could not be proven"

echo "# a wisp subject files in the store its prefix names, and is never refused"
# A wisp is ephemeral whatever its prefix resolves to, so its visit hangs on the
# standing triage subject. When the prefix names a store, every call is pinned to
# it by path, as for a durable subject: an lx- wisp's triage visit lands in the
# city store whatever the caller's GC_RIG. When no store can be derived, the
# visit files in the ambient store rather than being refused, even with GC_RIG
# unset.
reset; printf '[]' > "$CITY_STORE"
out=$(run_city gc-toolkit --subject lx-wisp-aaaaa --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "an lx- wisp subject's escalation files"
eq "$(jq -r '[.[] | .metadata.task_kind] | join(",")' "$CITY_STORE")" "triage-subject,visit" "  ... its triage subject and its visit are in the city store"
eq "$(jq 'length' "$STUB_STORE")" "0" "  ... and nothing landed in the caller's rig store"
if pinned_to_city; then ok "  ... every bd call was pinned to the city store by path"
else bad "  ... every bd call was pinned to the city store by path ($(bd_calls | grep -v -- '--db /city/.beads' | head -n 1))"; fi

reset
out=$(env -u GC_RIG STUB_RIG_LIST_FAIL=1 "$SUT" --subject tk-wisp-aaa --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a wisp whose store cannot be derived still files with GC_RIG unset"
eq "$(visits)" "2" "  ... on a standing triage subject in the ambient store"
hasnt "$(cat "$STUB_GC_LOG")" "--db" "  ... unpinned, since no store path was proven"

echo "# an unroutable --pool is refused before anything is created"
# A --pool that names no live agent is refused BEFORE anything is created: a
# visit that exists and routes nowhere reads to the caller as "a human was asked".

reset
out=$("$SUT" --subject tk-a --key k1 --message m --pool gc-toolkit/nonexistent.pool 2>&1); rc=$?
eq "$rc" 1 "an unknown --pool (this rig, no such agent) exits 1"
eq "$(visits)" "0" "and files nothing"
has "$out" "matches no live agent identity" "says the route names no agent"
has "$out" "repair:" "and prints the repair"

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

echo "# an unreadable agent set is not proof — a --pool route files, loudly unverified"
# The board default needs no live-agent match, so the verify path is exercised
# by an explicit --pool: an unreadable agent set cannot disprove it, so it files
# and says so rather than muting a human.
reset
out=$(STUB_AGENTS_FAIL=1 "$SUT" --subject tk-a --key k1 --message m --pool gc-toolkit/gc-toolkit.converse 2>&1); rc=$?
eq "$rc" 0 "an unreadable agent set still files a --pool route"
eq "$(visits)" "1" "the visit exists"
has "$out" "UNVERIFIED" "and says the route was never verified"

echo "# a control byte in the agent set does not silently mute the --pool check"
# A raw C0 byte anywhere in the payload aborts jq on the WHOLE document, which
# reads as an empty identity set — the fail-open arm above, so an unroutable
# --pool would file UNVERIFIED and the check that should refuse it would be
# gone. The scrub is what keeps the refusal reachable; without it this files.
reset
out=$(STUB_AGENTS="$(printf '{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.converse","work_query":"a\002b"}]}')" \
  "$SUT" --subject tk-a --key k1 --message m --pool gc-toolkit/nonexistent.pool 2>&1); rc=$?
eq "$rc" 1 "an unroutable --pool is still refused past a control byte"
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

echo "# the create stamps the dedup keys, so a lost follow-up write cannot orphan a visit"
# The failure this closes: a visit created without its escalation_key — the
# stamp landing in a separate write that never ran — is invisible to the dedup
# listing, so the next identical escalation mints a second visit. Stamping the
# identity in the create means a run whose every post-create write fails still
# leaves a dedup-complete visit. STUB_UPD_FAIL fails every update to prove no
# follow-up write is relied on.
reset
STUB_UPD_FAIL=1
out1=$("$SUT" --subject tk-orphan --key stuck --message "first" 2>&1); rc1=$?
eq "$rc1" 0 "the first escalation succeeds with no follow-up update at all"
eq "$(visits)" "1" "one visit filed"
eq "$(meta vis-1 escalation_key)" "stuck" "the create stamped escalation_key without any update"
eq "$(meta vis-1 gc.continuation_group)" "tk-orphan" "…and the continuation_group the durable dedup also needs"
out2=$("$SUT" --subject tk-orphan --key stuck --message "second" 2>&1)
eq "$(visits)" "1" "the repeat dedups to the one open visit — no orphan, no duplicate"
has "$out2" "already open" "the repeat reports the visit is already open"
unset STUB_UPD_FAIL

echo "# an already-open visit that routes nowhere is repointed, not counted"
# The create-side gate cannot reach a visit that already exists. One filed
# before it carries the unroutable name still, and every later pass matches
# that visit and exits 0 — the same mute, entered from the other side.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$("$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 0 "a repointed situation exits 0"
eq "$(visits)" "0" "no second visit filed"
eq "$(meta vis-0 gc.routed_to)" "human" "the stale route is repaired in place — repointed to the board"
has "$out" "repointing it at" "and the repoint is announced"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-0 gc.routed_to)" "human" "a visit with NO route is repointed too — to the board"
eq "$(visits)" "0" "and still files nothing"

reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"other/rig.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
"$SUT" --subject tk-a --key k1 --message m >/dev/null 2>&1
eq "$(meta vis-0 gc.routed_to)" "human" "a cross-rig route is repointed to the board"

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

echo "# a rig-less caller with a bare --pool cannot confirm a rig-qualified route"
# The board route derives its store from the subject (above), and a rig-qualified
# --pool adopts its rig, but a BARE --pool does neither, so GC_RIG stays unset.
# The dedup listing then runs against whatever store the ambient environment
# picks, and nothing here says the matched visit lives in the store its
# rig-scoped pool reads. Counting it exits 0 on a visit that may have asked
# nobody — the same mute, entered from the dedup side — while the create path
# refuses this very caller. Repointing is wrong too: the route is likely sound.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message again --pool gc-toolkit.converse 2>&1); rc=$?
eq "$rc" 1 "an unconfirmable already-open route exits 1"
eq "$(visits)" "0" "and files nothing"
eq "$(meta vis-0 gc.routed_to)" "gc-toolkit/gc-toolkit.converse" "and leaves the route it cannot condemn"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "no write at all"
has "$out" "GC_RIG is unset" "says why the open visit cannot be counted"
has "$out" "--pool 'gc-toolkit/gc-toolkit.converse'" "and the repair names the row's own route"

# The repair the refusal names: --pool binds the store, and the dedup that
# could not be trusted rig-less is then a proved match in the pool's own store.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit/gc-toolkit.converse","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message again \
  --pool gc-toolkit/gc-toolkit.converse 2>&1); rc=$?
eq "$rc" 0 "naming that pool exits 0"
eq "$(visits)" "0" "still files nothing"
has "$out" "already open" "the situation is confirmed, not guessed"
has "$(cat "$STUB_GC_LOG")" "[gc-toolkit] bd list" "the dedup read ran in the pool's own store"

# A city identity carries no rig segment, so there is no store claim to
# reconcile and the rig-less caller's dedup stands on identity alone.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"gc-toolkit.dog","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message again 2>&1); rc=$?
eq "$rc" 0 "a bare city identity still suppresses for a rig-less caller"
eq "$(visits)" "0" "and files nothing"

# ...and so does the operator marker: `human` is a held route, not a rig.
reset '[{"id":"vis-0","status":"open","assignee":"","metadata":{"gc.routed_to":"human","escalation_key":"k1","gc.continuation_group":"tk-a"},"notes":""}]'
out=$(env -u GC_RIG "$SUT" --subject tk-a --key k1 --message again 2>&1); rc=$?
eq "$rc" 0 "a human-parked visit still suppresses for a rig-less caller"
eq "$(meta vis-0 gc.routed_to)" "human" "and keeps its route"

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
eq "$(meta vis-0 gc.routed_to)" "human" "the key-only match is repointed too — to the board"
has "$out" "repointed" "and says so"

echo "# an ephemeral subject is filed on a durable standing subject"
# The sitting writes its outcome and its takeaway to the subject
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
# does. The converse fold check (converse-fold.sh) resolves a visit's topic as
# the key, else the subject. A visit that reached the bucket without its own
# key would fold into its sibling and close unread.
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
out=$(STUB_CREATE_NOMETA=1 "$SUT" --subject tk-a --key k1 --message m 2>&1); rc=$?
eq "$rc" 1 "a create that drops the identity stamps is caught at read-back and exits 1"
has "$out" "repair:" "and print the repair command"

echo "# the deacon's filed visits reach its incident ledger"
# escalate.sh calls the ledger by sibling path, so the SUT runs from a private
# copy with a RECORDING gc-deacon-ledger.sh beside it. Nothing here touches the
# real ledger script; what is under test is which calls escalate.sh makes.
LSUT="$TMP/sut"; mkdir -p "$LSUT"
cp "$SUT" "$LSUT/escalate.sh"; chmod +x "$LSUT/escalate.sh"
# escalate.sh proves its route through the sibling pool-route.sh, so the private
# copy needs it beside escalate.sh too, or every filing here exits 1 before the
# ledger is reached.
cp "$HERE/pool-route.sh" "$LSUT/pool-route.sh"; chmod +x "$LSUT/pool-route.sh"
# and its bead-store reads come from the sibling bd-lib.sh, sourced the same way,
# so the private copy needs it beside escalate.sh too.
cp "$HERE/bd-lib.sh" "$LSUT/bd-lib.sh"
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

echo "# a --subject that is not one bead id is refused before the store is touched"
# An unquoted expansion that does not word-split (zsh) hands escalate.sh an id
# and the word beside it as one argument. Filed, the visit's group would be the
# joined string, which no later dedup or retract call matches, and its tracks
# edge would name no bead. The refusal comes before any gc call, so nothing is
# listed, created or closed.
gccalls() { grep -c . "$STUB_GC_LOG"; }
reset
out=$("$SUT" --subject "tk-a 2026-10-04T07:07:52Z" --key witness-refinery-queue --message m 2>&1); rc=$?
eq "$rc" 2 "an id joined to a timestamp by a space is a usage error"
eq "$(visits)" "0" "and files no visit"
eq "$(gccalls)" "0" "and makes no gc call at all"
has "$out" "--subject must be one bead id" "and names the subject as the fault"
has "$out" "read -r SID SWHEN" "and names the read-each-field fix"
reset
out=$("$SUT" --subject $'tk-a\ntk-b' --key k1 --message m 2>&1); rc=$?
eq "$rc" 2 "a newline-joined id list is refused too"
eq "$(visits)" "0" "and files no visit"
reset
out=$("$SUT" --subject $'tk-a\t2026-10-04T07:07:52Z' --key k1 --message m 2>&1); rc=$?
eq "$rc" 2 "a tab-joined pair is refused too"
eq "$(visits)" "0" "and files no visit"
reset
"$SUT" --subject tk-a --key witness-refinery-queue --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "the same call with the id alone files"
eq "$(meta vis-1 gc.continuation_group)" "tk-a" "with the id as the visit's group"
reset
"$SUT" --subject tk-9tbbk.2 --key k1 --message m >/dev/null 2>&1; rc=$?
eq "$rc" 0 "a child bead id (dotted) is one bead id and files"
eq "$(meta vis-1 gc.continuation_group)" "tk-9tbbk.2" "with the child id as the visit's group"
# The retract path takes the same guard. The seeded visit carries the joined
# string as its group, so an unguarded retract would match it and close it.
reset '[{"id":"vis-7","status":"open","assignee":"","title":"visit: tk-sub 2026-10-04T07:07:52Z — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"witness-refinery-queue","gc.continuation_group":"tk-sub 2026-10-04T07:07:52Z","gc.routed_to":"human"}}]'
out=$("$SUT" --retract --subject "tk-sub 2026-10-04T07:07:52Z" --key witness-refinery-queue --message m 2>&1); rc=$?
eq "$rc" 2 "--retract refuses a joined subject as a usage error"
eq "$(vccount)" "0" "and closes nothing, not even a visit whose group is the same joined string"
eq "$(gccalls)" "0" "and makes no gc call at all"

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

echo "# --retract closes the open visit for a subject as moot"
# The counterpart to filing: a self-healing subject (reconcile) whose divergence
# resolved retracts its lingering board visit, routing the moot close through
# visit-close.sh with the reading passed through as the outcome reason.
reset '[{"id":"vis-7","status":"open","assignee":"","title":"visit: tk-sub — diverged","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-sub","gc.routed_to":"human"}}]'
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message "rigs/alpha is back in sync" 2>&1); rc=$?
eq "$rc" 0 "retract exits 0 when it closes a visit"
eq "$(visits)" "0" "retract files no new visit"
eq "$(vccount)" "1" "retract calls visit-close.sh exactly once"
eq "$(vclog)" "vis-7|tk-sub|moot|rigs/alpha is back in sync" "closes the tracked visit as moot, subject and reading passed through"
has "$out" "retracted visit vis-7 on tk-sub" "reports what it retracted"

echo "# --retract is a no-op success when no open visit matches"
# Idempotent: a second pass, or a subject that never raised one, changes nothing.
reset '[]'
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 0 "retract with no matching visit exits 0"
eq "$(vccount)" "0" "and calls visit-close.sh not at all"
has "$out" "no open visit" "and says there was nothing to retract"

echo "# --retract fails closed when the open-visit lookup is unreadable"
# The mirror of the filing dedup's fail-OPEN (an unreadable listing files a
# duplicate — a duplicate beats a mute): retract must NOT read an unreadable
# lookup as "no visit" and let its caller close the subject, because that strands
# the still-open visit it could not see. A matching visit exists but the lookup
# is down, so retract exits non-zero and closes nothing.
reset '[{"id":"vis-7","status":"open","assignee":"","title":"visit: tk-sub — diverged","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-sub","gc.routed_to":"human"}}]'
out=$(STUB_LIST_FAIL=1 "$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 1 "retract exits 1 when the open-visit lookup is unreadable"
eq "$(vccount)" "0" "and closes no visit on an unreadable lookup"
has "$out" "could not read open visits" "and says the lookup was unreadable, not that there was nothing to retract"

echo "# --retract matches on BOTH the key and the subject"
# A visit for another subject, or another situation under this subject, is left
# alone — the same conjunction the filing dedup uses.
reset '[{"id":"vis-8","status":"open","assignee":"","title":"visit: tk-other — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-other","gc.routed_to":"human"}}]'
"$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m >/dev/null 2>&1
eq "$(vccount)" "0" "a visit whose continuation_group is another subject is not retracted"
reset '[{"id":"vis-8","status":"open","assignee":"","title":"visit: tk-sub — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"other-situation","gc.continuation_group":"tk-sub","gc.routed_to":"human"}}]'
"$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m >/dev/null 2>&1
eq "$(vccount)" "0" "a visit for another situation key is not retracted"

echo "# --retract leaves an in_progress (claimed) visit for its holder"
# A human already engaged it; the recheck-premise skill folds mootness in at
# their prep, so an unattended caller must not close it under them. Only OPEN
# visits are retracted.
reset '[{"id":"vis-9","status":"in_progress","assignee":"someone","title":"visit: tk-sub — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-sub","gc.routed_to":"human"}}]'
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 0 "retract exits 0 when the only match is claimed"
eq "$(vccount)" "0" "and does not close the claimed visit"
has "$out" "no open visit" "treating a claimed visit as none to retract"

echo "# --retract refuses an ephemeral subject"
# An ephemeral subject's visits hang on the standing triage bucket keyed by
# --key alone, so there is no one subject-scoped visit to retract.
reset '[]'
out=$("$SUT" --retract --subject tk-wisp-abc --key k --message m 2>&1); rc=$?
eq "$rc" 2 "retract on an ephemeral subject is a usage error"
eq "$(vccount)" "0" "and calls visit-close.sh not at all"

# A subject proven to name no bead is ephemeral in the same way: its visit was
# filed on the standing triage subject, so a subject-scoped lookup finds nothing
# and would report "no open visit" while that visit stays open. It is refused
# like a wisp, with and without a pinned GC_RIG.
reset "[$STANDING,"'{"id":"vis-5","status":"open","assignee":"","title":"visit: sub-0 — empty identity","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"refinery-empty-identity","gc.continuation_group":"sub-0","escalation_raised_by":"refinery","gc.routed_to":"human"}}]'
out=$("$SUT" --retract --subject refinery --key refinery-empty-identity --message m 2>&1); rc=$?
eq "$rc" 2 "retract on a subject proven to name no bead is a usage error"
eq "$(vccount)" "0" "and calls visit-close.sh not at all"
hasnt "$out" "no open visit" "rather than reporting nothing to retract while the triage visit stays open"
out=$(env -u GC_RIG "$SUT" --retract --subject refinery --key refinery-empty-identity --message m 2>&1); rc=$?
eq "$rc" 2 "and with GC_RIG unset it is the same usage error"

echo "# --retract reports a close that did not land"
# visit-close.sh guards its own close; a non-zero exit means the visit stays open
# for a human, and retract surfaces that as a failure rather than a false success.
reset '[{"id":"vis-7","status":"open","assignee":"","title":"visit: tk-sub — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-sub","gc.routed_to":"human"}}]'
out=$(STUB_VISIT_CLOSE_FAIL=1 "$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 1 "retract exits 1 when visit-close.sh does not close the visit"
has "$out" "did not close" "and says the visit stays open"

# A visit for the situation, open, with whoever is engaged in it.
rvisit() { # <id> [<assignee>] [<gc.session_name>]
  printf '{"id":"%s","status":"open","assignee":"%s","title":"visit: tk-sub — x","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"reconcile-diverged-alpha","gc.continuation_group":"tk-sub","gc.routed_to":"human"%s}}' \
    "$1" "${2:-}" "${3:+,\"gc.session_name\":\"$3\"}"
}

echo "# --retract closes every open visit of the situation, twins included"
# The filing dedup files a second visit when its listing is unreadable. The
# premise the caller judged gone is gone for both, so neither is left behind.
reset "[$(rvisit vis-1), $(rvisit vis-2)]"
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 0 "retract exits 0 when it closes every twin"
eq "$(vccount)" "2" "retract calls visit-close.sh once per twin"
has "$out" "retracted visit vis-1 on tk-sub" "reports the first twin"
has "$out" "retracted visit vis-2 on tk-sub" "reports the second twin"

echo "# --retract leaves an open visit engage has bound, by assignee or by session"
# Engage binds the visit while it is still open, before the sitting's claim
# promotes it. The board reads that as engaged, and so does retract.
reset "[$(rvisit vis-3 lx-sitting)]"
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 0 "retract exits 0 when the only match is bound by assignee"
eq "$(vccount)" "0" "and does not close the bound visit"
has "$out" "vis-3 on tk-sub [reconcile-diverged-alpha] is engaged (lx-sitting)" "and names who holds it"
reset "[$(rvisit vis-4 "" s-lx-sitting)]"
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$(vccount)" "0" "a visit bound by session is not closed either"
has "$out" "is engaged (session s-lx-sitting)" "and the session is named"

echo "# --retract closes the unengaged twin beside an engaged one"
reset "[$(rvisit vis-5 lx-sitting), $(rvisit vis-6)]"
out=$("$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 0 "retract exits 0"
eq "$(vclog)" "vis-6|tk-sub|moot|m" "only the unengaged twin is closed"

echo "# --retract tries every twin and reports a close that did not land"
reset "[$(rvisit vis-7), $(rvisit vis-8)]"
out=$(STUB_VISIT_CLOSE_FAIL_ID=vis-7 "$SUT" --retract --subject tk-sub --key reconcile-diverged-alpha --message m 2>&1); rc=$?
eq "$rc" 1 "retract exits 1 when one twin did not close"
eq "$(vccount)" "2" "and still tries the other"
has "$out" "did not close vis-7" "names the visit that stays open"
has "$out" "retracted visit vis-8 on tk-sub" "and reports the one that closed"

echo "# the city store's own visits answer the dedup, the verdict window and --retract"
# Each of these reads the store before it writes, and the ambient store holds
# none of the city's visits, so an unpinned read answers 'nothing there': it
# files a duplicate beside a visit already open, re-files a situation a sitting
# ruled moot, or retracts nothing.
CITY_OPEN='[{"id":"lx-v1","status":"open","assignee":"","title":"visit: lx-hq1 — m","description":"d","notes":"","metadata":{"task_kind":"visit","escalation_key":"k1","gc.continuation_group":"lx-hq1","gc.routed_to":"human"}}]'
reset; printf '%s' "$CITY_OPEN" > "$CITY_STORE"
out=$(run_city gc-toolkit --subject lx-hq1 --key k1 --message again 2>&1); rc=$?
eq "$rc" 0 "an open city-store visit dedups a rig caller's repeat"
eq "$(visits)" "0" "  ... nothing is filed in either store"
has "$out" "visit lx-v1 already open" "  ... the city store's visit is the one found"

reset; printf '[%s]' "$(closed_visit lx-v1 k1 lx-hq1 moot 3600)" > "$CITY_STORE"
out=$(run_city gc-toolkit --subject lx-hq1 --key k1 --message again 2>&1); rc=$?
eq "$rc" 0 "a moot verdict in the city store answers a rig caller's re-file"
eq "$(visits)" "0" "  ... nothing is filed"
eq "$(jq -r '.[0].metadata["escalation.recurrences"] // "<absent>"' "$CITY_STORE")" "1" "  ... and the recurrence is tallied on the city store's visit"

reset; printf '%s' "$CITY_OPEN" > "$CITY_STORE"
out=$(run_city gc-toolkit --retract --subject lx-hq1 --key k1 --message "resolved" 2>&1); rc=$?
eq "$rc" 0 "--retract from a rig caller exits 0"
eq "$(vclog)" "lx-v1|lx-hq1|moot|resolved" "  ... having found the city store's open visit and closed it as moot"

echo
echo "escalate.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
