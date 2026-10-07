#!/usr/bin/env bash
# Hermetic test for the witness-patrol refinery stuck-handoff escalation.
#
# check-refinery escalates ONLY a refinery handoff that has sat past the stuck
# bound. Transient churn (a fresh handoff, a rebase task the fix pool is
# working) and gating anchors (the cadence's own, carrying merge_result) must
# never escalate, and a false escalation here is the defect this block fixes. A
# count-nudge is gone: it went stale the moment the assignee set drained. The
# counterpart retract withdraws a visit only when the handoff's own row shows it
# left the refinery; absence from the queue listing alone withdraws nothing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-stuck-escalate-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in '$1')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

BLOCK="$(awk '
  /# >>> refinery-stuck-escalate/ {f=1; next}
  /# <<< refinery-stuck-escalate/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between refinery-stuck-escalate markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

has "$BLOCK" 'gc bd list' "the block reads the queue itself"
has "$BLOCK" 'escalate.sh' "the block escalates a stuck handoff"
hasnt "$BLOCK" 'gc session nudge' "the block no longer nudges a count"

# {{binding_prefix}} must be substituted exactly as the materializer does it.
# The empty-prefix render is the wrong address a wisp poured with
# binding_prefix='' lists under.
render() { printf '%s\n' "$BLOCK" | sed "s|{{binding_prefix}}|$1|g"; }
render gc-toolkit. > "$TMP/block.sh"
render '' > "$TMP/block-noprefix.sh"

bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

# Stub `gc` (bd list only) and a stub escalate.sh resolved via GC_RIG_ROOT, which
# the block probes first — so the real pack escalate.sh is never reached.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "bd list")
    printf '%s\n' "$*" >> "$LIST_LOG"
    case "$*" in *--json*) ;; *) echo "gc bd list called without --json" >&2; exit 64 ;; esac
    case "$*" in
      *--has-metadata-key=escalation_key*)
        # The retract arm's open-escalation read, served from its own fixture
        # (default an empty array). It is never subject to the refinery-queue
        # read's injected failure, so a queue blip is tested in isolation.
        if [ -n "${ESC_LIST_FIXTURE:-}" ]; then cat "$ESC_LIST_FIXTURE"; else echo "[]"; fi
        ;;
      *--id=*)
        # The retract arm's by-id read of its candidate handoffs, modelled on bd:
        # an id it cannot resolve is dropped with exit 0, and a closed row comes
        # back only under --all. HANDOFF_FILTER=0 serves the fixture unfiltered,
        # a read that ignored its id filter. A fixture that does not parse (a raw
        # control byte) is served as-is, the way bd emits it.
        if [ "${HANDOFF_RC:-0}" != "0" ]; then
          echo "gc bd list: store unavailable" >&2; exit "${HANDOFF_RC}"
        fi
        ids=""; all=false
        for a in "$@"; do
          case "$a" in --id=*) ids="${a#--id=}" ;; --all) all=true ;; esac
        done
        if [ "${HANDOFF_FILTER:-1}" = "1" ] \
          && rows=$(jq -c --arg ids "$ids" --argjson all "$all" '
               ($ids | split(",")) as $want
               | if type == "array" then
                   [ .[] | select((.id // "") as $i | $want | index($i))
                         | select($all or ((.status // "") != "closed")) ]
                 else . end' "$HANDOFF_FIXTURE" 2>/dev/null); then
          printf '%s\n' "$rows"
        else
          cat "$HANDOFF_FIXTURE"
        fi
        ;;
      *)
        # A failing listing writes nothing to stdout, the way the real one does.
        if [ "${LIST_RC:-0}" != "0" ]; then
          echo "gc bd list: store unavailable" >&2; exit "${LIST_RC}"
        fi
        [ -n "${QUEUE_STDERR:-}" ] && printf '%s\n' "$QUEUE_STDERR" >&2
        cat "$QUEUE_FIXTURE"
        ;;
    esac
    ;;
  *)
    echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
cat > "$TMP/rig/assets/scripts/escalate.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ESC_LOG"
STUB
chmod +x "$TMP/rig/assets/scripts/escalate.sh"
export PATH="$TMP/bin:$PATH"

# run <fixture-json> [stderr-noise] [list-rc] [shell-prelude] [esc-list-json] [handoff-json]
#   -> the escalate log. Runs from a non-repo cwd so the block's git-toplevel
# probe finds nothing and GC_RIG_ROOT (the stub) wins. The 5th arg is the
# retract arm's open-escalation set; omitted leaves it an empty array, so the
# queue-only tests never retract. The 6th is the rows its by-id read of the
# candidate handoffs serves; omitted leaves it an empty array, so every
# candidate reads as unread. BLOCK_FILE_OVERRIDE runs another render,
# HANDOFF_RC_OVERRIDE fails the by-id read, and HANDOFF_FILTER_OVERRIDE=0 serves
# its rows unfiltered.
run() {
  : > "$TMP/esc"; : > "$TMP/lists"
  printf '%s' "$1" > "$TMP/queue.json"
  local esc_list=""
  if [ -n "${5:-}" ]; then printf '%s' "$5" > "$TMP/esc_list.json"; esc_list="$TMP/esc_list.json"; fi
  printf '%s' "${6:-[]}" > "$TMP/handoffs.json"
  { printf '%s\n' "${4:-}"; cat "${BLOCK_FILE_OVERRIDE:-$TMP/block.sh}"; } > "$TMP/run.sh"
  ( cd "$TMP"
    QUEUE_FIXTURE="$TMP/queue.json" ESC_LOG="$TMP/esc" LIST_LOG="$TMP/lists" \
    ESC_LIST_FIXTURE="$esc_list" HANDOFF_FIXTURE="$TMP/handoffs.json" \
    HANDOFF_RC="${HANDOFF_RC_OVERRIDE:-0}" HANDOFF_FILTER="${HANDOFF_FILTER_OVERRIDE:-1}" \
    QUEUE_STDERR="${2:-}" GC_RIG="${GC_RIG_OVERRIDE-gc-toolkit}" LIST_RC="${3:-0}" \
    GC_RIG_ROOT="$TMP/rig" GC_CITY_PATH="$TMP/nocity" \
      bash "$TMP/run.sh" > "$TMP/out" 2>&1 || true )
  cat "$TMP/esc"
}
out() { cat "$TMP/out"; }

# Timestamps relative to the block's real `date`: far past is stuck, ~now churns.
OLD1="2020-01-01T00:00:00Z"
OLD2="2020-06-01T00:00:00Z"
FRESH="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

STUCK_ONE='[{"id":"tk-stuck","updated_at":"'"$OLD1"'","title":"handoff","metadata":{}}]'
ESC="$(run "$STUCK_ONE")"
eq "$(printf '%s' "$ESC" | grep -c . || true)" "1" "a handoff past the bound escalates once"
has "$ESC" "--subject tk-stuck" "escalation names the stuck bead as the subject"
has "$ESC" "--key witness-refinery-queue" "escalation carries the situation key"
LISTED="$(cat "$TMP/lists")"
has "$LISTED" "--assignee=gc-toolkit/gc-toolkit.refinery" "the queue read is the refinery's own"
has "$LISTED" "--status=open" "the queue read is OPEN beads only"
has "$LISTED" "--has-metadata-key=branch" "the queue read is scoped to branch-bearing work"
has "$LISTED" "--exclude-type=epic" "the queue read excludes epics"
has "$LISTED" "--limit=0" "the queue read is not truncated by a default page size"

# Fresh churn is not stuck.
eq "$(run '[{"id":"tk-fresh","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]')" "" \
   "a fresh handoff (recent updated_at) does not escalate"

# A gating anchor carries merge_result — the cadence's, never escalated even old.
eq "$(run '[{"id":"tk-gate","updated_at":"'"$OLD1"'","title":"anchor","metadata":{"merge_result":"pull_request"}}]')" "" \
   "an old gating anchor (merge_result set) does not escalate"

# Mixed: one stuck handoff, one fresh, one old gating anchor -> exactly the stuck one.
MIXED='[
  {"id":"tk-stuck","updated_at":"'"$OLD1"'","title":"handoff","metadata":{}},
  {"id":"tk-fresh","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}},
  {"id":"tk-gate","updated_at":"'"$OLD2"'","title":"anchor","metadata":{"merge_result":"pre_open_gate"}}
]'
MESC="$(run "$MIXED")"
eq "$(printf '%s' "$MESC" | grep -c . || true)" "1" "a mixed queue escalates exactly the stuck handoff"
has "$MESC" "tk-stuck" "the escalation is for the stuck handoff"
hasnt "$MESC" "tk-fresh" "the fresh handoff is not escalated"
hasnt "$MESC" "tk-gate" "the gating anchor is not escalated"

# Two stuck handoffs -> one escalate call each (per-bead dedup is escalate.sh's).
TWO_STUCK='[
  {"id":"tk-s1","updated_at":"'"$OLD1"'","title":"a","metadata":{}},
  {"id":"tk-s2","updated_at":"'"$OLD2"'","title":"b","metadata":{}}
]'
eq "$(printf '%s' "$(run "$TWO_STUCK")" | grep -c . || true)" "2" \
   "two stuck handoffs escalate once each"

# THE BUG: a raw control byte in a bead string (here a stuck handoff's title)
# aborts jq on the whole array and silently blinded this monitor. The
# control-byte strip rescues the parse, so the stuck handoff still escalates and
# the read is never mistaken for unreadable.
CTL="$(printf 'x\001y')"
CTRL_STUCK='[{"id":"tk-ctl","updated_at":"'"$OLD1"'","title":"handoff '"$CTL"'","metadata":{}}]'
CESC="$(run "$CTRL_STUCK")"
has "$CESC" "--subject tk-ctl" "a raw control byte in the queue does not blind the stuck-handoff read"
has "$CESC" "--key witness-refinery-queue" "the rescued read escalates the stuck handoff normally"
hasnt "$(out)" "unreadable" "a control byte is stripped, not treated as unreadable"

# An empty queue is a valid array with nothing stuck: no escalation.
eq "$(run '[]')" "" "an empty queue escalates nothing"
has "$(out)" "no stuck handoffs" "an empty queue is reported apart from an unreadable one"

# A genuinely unreadable queue — not a JSON array even after the control-byte
# strip, or a failed listing — escalates the BLIND MONITOR loudly, under its own
# key and naming no stuck bead. The old silent stderr log was the defect.
blind() {
  local esc; esc="$(run "$@")"
  has "$esc" "--key witness-refinery-queue-unreadable" "unreadable read escalates the blind monitor"
  hasnt "$esc" "--subject tk-" "the blind-monitor escalation names no stuck bead"
}
blind 'warning: config drift
[]'
blind '{"error":"store unavailable"}'
blind 'null'
blind '' '' 1
has "$(out)" "unreadable" "a failed listing still reports it is unreadable"

# unset GC_RIG still names the refinery in the message, with no leading slash.
URIG="$(GC_RIG_OVERRIDE= run "$STUCK_ONE")"
has "$URIG" "gc-toolkit.refinery" "unset GC_RIG still names the refinery"
hasnt "$URIG" "/gc-toolkit.refinery" "unset GC_RIG emits no leading slash"

# The block is instruction text an agent runs, so it lands in whatever shell the
# caller has already set up, including a strict one.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  has "$(run "$STUCK_ONE" '' 0 "$PRELUDE")" "--subject tk-stuck" \
     "$PRELUDE: a stuck handoff still escalates"
  has "$(run '' '' 1 "$PRELUDE")" "--key witness-refinery-queue-unreadable" \
     "$PRELUDE: a failed listing escalates the blind monitor"
  has "$(out)" "unreadable" "$PRELUDE: a failed listing still reaches the diagnostic"
  eq "$(run '[]' '' 0 "$PRELUDE")" "" \
     "$PRELUDE: an empty queue escalates nothing"
done

# The stuck-handoff read and the escalations share one queue: the refinery queue
# is read exactly once (never re-read per bead). The retract arm reads the
# open-escalation set once and its candidate handoffs once, by id. No nudge.
eq "$(printf '%s\n' "$BLOCK" | grep -c 'bd list --assignee' || true)" "1" \
   "the refinery queue is read exactly once"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'has-metadata-key=escalation_key' || true)" "1" \
   "the open-escalation set is read exactly once"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'bd list --id=' || true)" "1" \
   "the candidate handoffs are read exactly once, by id"
eq "$(awk '
  /# >>> refinery-stuck-escalate/ {inside = 1}
  /# <<< refinery-stuck-escalate/ {inside = 0; next}
  !inside && /gc session nudge/ && /refinery/ {print FNR ": " $0}
' "$TOML")" "" "no refinery nudge anywhere in the formula"

# A TOML basic multi-line string rewrites a backslash, so the block has to stay
# free of them to survive the pour intact.
case "$BLOCK" in
  *'\'*) bad "block contains a backslash — the TOML \"\"\" string mangles it" ;;
  *)     ok "block is backslash-free" ;;
esac

# --- Retract arm: a departed handoff's escalation is withdrawn moot -----------
# A handoff that an open witness-refinery-queue visit escalates and that the
# readable queue no longer carries is only a candidate. The block reads each
# candidate by id and retracts its visit through escalate.sh --retract only when
# that row shows the handoff left: closed, carrying a merge_result, unassigned,
# or assigned to something other than a refinery. The open-escalation set is
# served from the 5th run() argument and the by-id rows from the 6th.
QUEUE_OTHER='[{"id":"tk-still","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]'
ESC_GONE='[{"id":"tk-v-gone","metadata":{"task_kind":"visit","escalation_key":"witness-refinery-queue","gc.continuation_group":"tk-gone"}}]'
REF="gc-toolkit/gc-toolkit.refinery"
# handoff <status> <assignee as JSON> [merge_result] -> tk-gone's row, as bd
# lists it.
handoff() {
  local mr=""
  [ -n "${3:-}" ] && mr=',"merge_result":"'"$3"'"'
  printf '[{"id":"tk-gone","status":"%s","assignee":%s,"title":"handoff","metadata":{"branch":"polecat/tk-gone"%s}}]' "$1" "$2" "$mr"
}
H_CLOSED="$(handoff closed null merged)"
H_HELD="$(handoff open "\"$REF\"")"

RET="$(run "$QUEUE_OTHER" "" "" "" "$ESC_GONE" "$H_CLOSED")"
has "$RET" "--retract" "a closed handoff gone from the queue has its escalation retracted"
has "$RET" "--subject tk-gone" "the retract names the departed handoff as the subject"
has "$RET" "--key witness-refinery-queue" "the retract carries the situation key"
has "$RET" "Refinery handoff tk-gone is closed," "the retract's reading names what the handoff's own row showed"
IDREAD="$(grep -e '--id=' "$TMP/lists" || true)"
has "$IDREAD" "--id=tk-gone" "the candidate is read by id"
has "$IDREAD" "--all" "the by-id read includes closed beads"

# Still in the queue: the premise holds, so it is no candidate and is not read.
QUEUE_SUBJ='[{"id":"tk-gone","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]'
RET2="$(run "$QUEUE_SUBJ" "" "" "" "$ESC_GONE" "$H_CLOSED")"
hasnt "$RET2" "--retract" "a handoff still in the queue keeps its escalation open"
hasnt "$(cat "$TMP/lists")" "--id=" "a handoff still in the queue is not read by id"

# Absence from the listing is not departure. A listing under a wrong address is
# a valid empty array with exit 0, and a handoff still open and assigned to the
# refinery keeps its escalation through it.
RB="$(run '[]' "" "" "" "$ESC_GONE" "$H_HELD")"
hasnt "$RB" "--retract" "an empty listing does not retract a handoff still assigned to the refinery"
has "$(out)" "tk-gone is missing from the queue listing but is still unprepared and assigned to $REF (status open)" \
   "the kept escalation is reported with what the handoff's row showed"

# An empty binding_prefix renders the address gc-toolkit/refinery, which no
# handoff carries, so its listing comes back empty.
RBW="$(BLOCK_FILE_OVERRIDE="$TMP/block-noprefix.sh" run '[]' "" "" "" "$ESC_GONE" "$H_HELD")"
has "$(cat "$TMP/lists")" "--assignee=gc-toolkit/refinery" "the empty-prefix render lists under the wrong address"
hasnt "$RBW" "--retract" "a wrong-address listing retracts nothing while the handoff is still with the refinery"

# The assignee is compared by role, so any form of the refinery's address keeps
# the escalation, and so does a status the queue read does not list.
for WHO in gc-toolkit.refinery gc-toolkit/refinery refinery; do
  hasnt "$(run '[]' "" "" "" "$ESC_GONE" "$(handoff open "\"$WHO\"")")" "--retract" \
     "a handoff assigned to $WHO is still with a refinery"
done
for ST in in_progress blocked; do
  hasnt "$(run '[]' "" "" "" "$ESC_GONE" "$(handoff "$ST" "\"$REF\"")")" "--retract" \
     "a handoff in status $ST, still assigned to the refinery, keeps its escalation"
done

# Every departure the row can show retracts, and the reading names it.
RMR="$(run '[]' "" "" "" "$ESC_GONE" "$(handoff open null pull_request)")"
has "$RMR" "--retract --subject tk-gone" "a handoff carrying a merge_result has left"
has "$RMR" "carries merge_result=pull_request" "the reading names the merge_result"
# Prepared is a departure on its own, even with the refinery still the assignee.
has "$(run '[]' "" "" "" "$ESC_GONE" "$(handoff open "\"$REF\"" pre_open_gate)")" "--retract --subject tk-gone" \
   "a prepared handoff still assigned to the refinery has left"
RUN1="$(run '[]' "" "" "" "$ESC_GONE" "$(handoff open '""')")"
has "$RUN1" "--retract --subject tk-gone" "an unassigned handoff has left"
has "$RUN1" "is unassigned" "the reading says it is unassigned"
H_NOKEY='[{"id":"tk-gone","status":"open","title":"handoff","metadata":{"branch":"polecat/tk-gone"}}]'
has "$(run '[]' "" "" "" "$ESC_GONE" "$H_NOKEY")" "--retract --subject tk-gone" \
   "a handoff whose row carries no assignee has left"
RPC="$(run '[]' "" "" "" "$ESC_GONE" "$(handoff in_progress '"lx-wisp-abc"')")"
has "$RPC" "--retract --subject tk-gone" "a handoff reassigned to a worker has left"
has "$RPC" "is assigned to lx-wisp-abc, not a refinery" "the reading names the new assignee"

# A handoff that cannot be read keeps its escalation: a failed read, an error
# object, and a row for some other bead are none of them a departure.
RU1="$(HANDOFF_RC_OVERRIDE=1 run '[]' "" "" "" "$ESC_GONE" "$H_CLOSED")"
hasnt "$RU1" "--retract" "a failed by-id read retracts nothing"
has "$(out)" "could not read handoff tk-gone" "a failed by-id read is reported per candidate"
RU2="$(run '[]' "" "" "" "$ESC_GONE" '{"error":"no issues found matching the provided IDs"}')"
hasnt "$RU2" "--retract" "an error object from the by-id read retracts nothing"
RU3="$(HANDOFF_FILTER_OVERRIDE=0 run '[]' "" "" "" "$ESC_GONE" '[{"id":"tk-other","status":"closed","assignee":null,"metadata":{}}]')"
hasnt "$RU3" "--retract" "a row for a different bead does not decide the candidate"

# bd drops an id it cannot resolve and still exits 0. The dropped candidate keeps
# its escalation, and it does not silence a departed candidate read beside it.
ESC_TWO='[
  {"id":"tk-v-gone","metadata":{"task_kind":"visit","escalation_key":"witness-refinery-queue","gc.continuation_group":"tk-gone"}},
  {"id":"tk-v-lost","metadata":{"task_kind":"visit","escalation_key":"witness-refinery-queue","gc.continuation_group":"tk-lost"}}
]'
RU4="$(run '[]' "" "" "" "$ESC_TWO" "$H_CLOSED")"
has "$RU4" "--retract --subject tk-gone" "a departed candidate is retracted beside an unresolvable one"
hasnt "$RU4" "--subject tk-lost" "a candidate the read dropped keeps its escalation"
has "$(out)" "could not read handoff tk-lost" "the dropped candidate is reported"
eq "$(grep -c -e '--id=' "$TMP/lists" || true)" "1" "every candidate rides one by-id read"
has "$(cat "$TMP/lists")" "--id=tk-gone,tk-lost" "the one read names every candidate"

# A raw control byte in the handoff's row is stripped before the parse, as in
# the queue read.
H_CTL='[{"id":"tk-gone","status":"closed","assignee":null,"title":"handoff '"$CTL"'","metadata":{}}]'
has "$(run '[]' "" "" "" "$ESC_GONE" "$H_CTL")" "--retract --subject tk-gone" \
   "a raw control byte in the handoff's row does not blind the departure read"

# A malformed legacy group (a bead id with a trailing timestamp) resolves to no
# bead, so it is left for repair, never retracted.
ESC_BAD='[{"id":"tk-v-bad","metadata":{"task_kind":"visit","escalation_key":"witness-refinery-queue","gc.continuation_group":"tk-gone 2026-10-03T12:57:12Z"}}]'
RET3="$(run "$QUEUE_OTHER" "" "" "" "$ESC_BAD" "$H_CLOSED")"
hasnt "$RET3" "--retract" "a malformed-subject legacy escalation is left for repair"

# An unreadable queue never retracts: the gate is QUEUE_RC, so a transient blip
# runs no candidate pass at all.
RET4="$(run "" "" 1 "" "$ESC_GONE" "$H_CLOSED")"
hasnt "$RET4" "--retract" "an unreadable queue retracts nothing (gated on QUEUE_RC)"

# Scoped to the witness key: an escalation under another key is not retracted.
ESC_OTHERKEY='[{"id":"tk-v-x","metadata":{"task_kind":"visit","escalation_key":"some-other-key","gc.continuation_group":"tk-gone"}}]'
RET5="$(run "$QUEUE_OTHER" "" "" "" "$ESC_OTHERKEY" "$H_CLOSED")"
hasnt "$RET5" "--retract" "an escalation under another key is not retracted"

# The retract arm, like the escalate arm, survives a strict shell.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  has "$(run "$QUEUE_OTHER" "" "" "$PRELUDE" "$ESC_GONE" "$H_CLOSED")" "--retract --subject tk-gone" \
     "$PRELUDE: a departed handoff's escalation is still retracted"
  hasnt "$(run '[]' "" "" "$PRELUDE" "$ESC_GONE" "$H_HELD")" "--retract" \
     "$PRELUDE: a handoff still with the refinery keeps its escalation"
  hasnt "$(HANDOFF_RC_OVERRIDE=1 run '[]' "" "" "$PRELUDE" "$ESC_GONE" "$H_CLOSED")" "--retract" \
     "$PRELUDE: a failed by-id read retracts nothing"
  has "$(out)" "could not read handoff tk-gone" "$PRELUDE: a failed by-id read still reaches the diagnostic"
done

echo
echo "refinery-stuck-escalate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
