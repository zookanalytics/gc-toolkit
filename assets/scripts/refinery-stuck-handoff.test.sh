#!/usr/bin/env bash
# Hermetic test for the witness patrol's stuck-handoff check (check-refinery).
#
# check-refinery files a human gate ONLY on a refinery handoff that has sat past
# the stuck bound. Transient churn (a fresh handoff, a rebase task the fix pool
# is working) and gating anchors (the cadence's own, carrying merge_result) are
# never gated, because a false gate here is the defect the block guards against.
# The counterpart withdraws a gate only when the handoff's own row shows it left
# the refinery; absence from the queue listing alone withdraws nothing. A bead
# something holds (hold-lib.sh) is waiting, not stuck, as a landing bead waits
# on its effort, and a wait is aged from the close that released its last hold
# when that is later than its last write. A gate that blocks several handoffs is
# withdrawn only once every one of them has left, which a section at the end
# proves through the real helper. A monitor that cannot see the queue is a
# condition with no bead of its own, and the patrol's run is a wisp, so it is
# reported as a patrol finding.
#
# The queue is read at the refinery's live identity, resolved by the real
# resolve-route.sh against a stubbed roster. The store stub answers only that
# owner's queue and lists any other address as a valid empty array, the way bd
# does, so a block that read an address it never resolved would see an empty
# queue and report it clean. The withdrawal starts from the store's open human
# gates and reads each gate's waiting beads from the gate's end, the way bd
# serves both reads.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-stuck-handoff-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in '$1')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

BLOCK="$(awk '
  /# >>> refinery-stuck-handoff/ {f=1; next}
  /# <<< refinery-stuck-handoff/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between refinery-stuck-handoff markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

has "$BLOCK" 'gc bd list' "the block reads the queue itself"
has "$BLOCK" 'human-gate.sh' "the block files a stuck handoff's human gate through human-gate.sh"
has "$BLOCK" 'patrol-finding.sh' "the block reports a blind monitor as a patrol finding"
has "$BLOCK" 'resolve-route.sh' "the block resolves the refinery address"
has "$BLOCK" 'gc bd gate list' "the withdrawal starts from the store's human gates"
hasnt "$BLOCK" 'gc session nudge' "the block nudges no count"

# {{binding_prefix}} must be substituted exactly as the materializer does it.
# The patrol's steps are never materialized: each session fills the token by
# hand from the unrendered formula, so a wrong or empty prefix is a live input.
# An empty prefix renders gc-toolkit/refinery, the address a wisp poured with
# binding_prefix='' builds and no agent holds. A prefix missing its trailing dot
# renders an address whose role is not a refinery's. The block also names the
# pack's binding through the same token, so an empty or misspelled prefix names
# no pack and stops the block before it reads anything, while a dotless one
# still names the pack and reaches the address checks.
render() { printf '%s\n' "$BLOCK" | sed "s|{{binding_prefix}}|$1|g"; }
render gc-toolkit. > "$TMP/block.sh"
render '' > "$TMP/block-noprefix.sh"
render typo. > "$TMP/block-typo.sh"
render gc-toolkit > "$TMP/block-nodot.sh"

bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

# Stub `gc` (bd list, bd gate list, bd dep list, agent list, and `gc-toolkit
# scripts-dir`, which names the stub pack), and stub human-gate.sh and
# patrol-finding.sh in that pack, so the real pack scripts are never reached.
# Each stub logs its arguments led by its own name. The stub pack also holds a
# copy of the real resolver and of bd-lib.sh and hold-lib.sh.
mkdir -p "$TMP/bin" "$TMP/rig/assets/scripts"
cp "$ROOT/assets/scripts/resolve-route.sh" "$ROOT/assets/scripts/bd-lib.sh" "$ROOT/assets/scripts/hold-lib.sh" "$TMP/rig/assets/scripts/"
chmod +x "$TMP/rig/assets/scripts/resolve-route.sh"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
case "$1 $2" in
  "gc-toolkit scripts-dir")
    [ -n "${STUB_PACK:-}" ] || exit 1
    printf '%s/assets/scripts\n' "$STUB_PACK"
    ;;
  "agent list")
    [ -n "${STUB_AGENTS_FAIL:-}" ] && { echo "gc: agent list unavailable" >&2; exit 1; }
    printf '%s\n' "${STUB_AGENTS:-}"
    ;;
  "bd gate")
    printf '%s\n' "$*" >> "$LIST_LOG"
    case "$3" in
      list)
        # The store's gates. bd prints null when there are none, the default
        # fixture here.
        if [ "${GATES_RC:-0}" != "0" ]; then
          echo "gc bd gate list: store unavailable" >&2; exit "${GATES_RC}"
        fi
        cat "$GATES_FIXTURE"
        ;;
      *) echo "unexpected gate call: $*" >&2; exit 99 ;;
    esac
    ;;
  "bd dep")
    printf '%s\n' "$*" >> "$LIST_LOG"
    # bd dep list <gate> --direction=up --type blocks --json: the beads that
    # wait on the gate, an empty array for a gate nothing waits on.
    case "$* " in *" --direction=up "*) ;; *) echo "dep list read from the wrong end: $*" >&2; exit 64 ;; esac
    case "$* " in *" --type blocks "*) ;; *) echo "dep list read without --type blocks: $*" >&2; exit 64 ;; esac
    # A gate mapped to a string is one whose read fails, with nothing on stdout.
    if [ "$(jq -r --arg g "$4" '.[$g] | type' "$DEPS_FIXTURE")" = string ]; then
      echo "gc bd dep list: store unavailable" >&2; exit 1
    fi
    jq -c --arg g "$4" '.[$g] // []' "$DEPS_FIXTURE"
    ;;
  "bd list")
    printf '%s\n' "$*" >> "$LIST_LOG"
    case "$*" in *--json*) ;; *) echo "gc bd list called without --json" >&2; exit 64 ;; esac
    case "$*" in
      *--id=*)
        # The withdrawal's by-id read of its candidate handoffs, modelled on bd:
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
        # The fixture is QUEUE_OWNER's queue. bd lists an address no agent
        # holds as a valid empty array, so every other assignee reads [].
        case "$* " in
          *" --assignee=$QUEUE_OWNER "*) cat "$QUEUE_FIXTURE" ;;
          *) echo "[]" ;;
        esac
        ;;
    esac
    ;;
  *)
    echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
for S in human-gate patrol-finding; do
  printf '#!/usr/bin/env bash\nprintf '"'"'%%s %%s\\n'"'"' %s "$*" >> "$CALLS_LOG"\n' "$S" \
    > "$TMP/rig/assets/scripts/$S.sh"
  chmod +x "$TMP/rig/assets/scripts/$S.sh"
done
export PATH="$TMP/bin:$PATH"

# The live roster: this rig's refinery, another rig's under the same binding,
# and agents of other roles. The fixture queue belongs to this rig's refinery.
AGENTS_DEFAULT='{"agents":[{"qualified_name":"gc-toolkit/gc-toolkit.refinery"},
  {"qualified_name":"gascity/gc-toolkit.refinery"},
  {"qualified_name":"gc-toolkit/gc-toolkit.polecat"},{"qualified_name":"gc-toolkit.dog"}]}'

# What each gate the fixtures name blocks, as bd dep list --direction=up prints
# it. A gate the store's listing does not carry is never read, so one map serves
# every case and the listing decides which gates exist. tk-g-dark's read fails.
DEPS_DEFAULT='{
  "tk-g-gone":  [{"id":"tk-gone","dependency_type":"blocks"}],
  "tk-g-gone2": [{"id":"tk-gone","dependency_type":"blocks"}],
  "tk-g-lost":  [{"id":"tk-lost","dependency_type":"blocks"}],
  "tk-g-stuck": [{"id":"tk-stuck","dependency_type":"blocks"}],
  "tk-g-both":  [{"id":"tk-gone","dependency_type":"blocks"},{"id":"tk-still","dependency_type":"blocks"}],
  "tk-g-noid":  [{"id":"tk-gone","dependency_type":"blocks"},{"dependency_type":"blocks"}],
  "tk-g-dark":  "fails"
}'

# run <fixture-json> [stderr-noise] [list-rc] [shell-prelude] [gates-json] [handoff-json]
#   -> the calls log. Runs from a non-repo cwd, with gc naming the stub pack. The
# 5th arg is what the
# store's gate listing prints; omitted it prints null, as bd does with no gates,
# so the queue-only tests never withdraw. The 6th is the rows the by-id read of
# the candidate handoffs serves; omitted leaves it an empty array, so every
# candidate reads as unread. Overrides, set on the call: BLOCK_FILE_OVERRIDE
# (a block rendered with another prefix), AGENTS_OVERRIDE (the roster),
# AGENTS_FAIL (an unreadable roster), QUEUE_OWNER_OVERRIDE (whose queue the
# fixture is), GATES_RC_OVERRIDE (fails the gate listing), DEPS_OVERRIDE (what
# each gate blocks), HANDOFF_RC_OVERRIDE (fails the by-id read),
# HANDOFF_FILTER_OVERRIDE=0 (serves its rows unfiltered), GC_RIG_OVERRIDE.
run() {
  : > "$TMP/calls"; : > "$TMP/lists"
  printf '%s' "$1" > "$TMP/queue.json"
  printf '%s' "${5:-null}" > "$TMP/gates.json"
  printf '%s' "${DEPS_OVERRIDE:-$DEPS_DEFAULT}" > "$TMP/deps.json"
  printf '%s' "${6:-[]}" > "$TMP/handoffs.json"
  { printf '%s\n' "${4:-}"; cat "${BLOCK_FILE_OVERRIDE:-$TMP/block.sh}"; } > "$TMP/run.sh"
  ( cd "$TMP"
    QUEUE_FIXTURE="$TMP/queue.json" CALLS_LOG="$TMP/calls" LIST_LOG="$TMP/lists" \
    GATES_FIXTURE="$TMP/gates.json" GATES_RC="${GATES_RC_OVERRIDE:-0}" \
    DEPS_FIXTURE="$TMP/deps.json" HANDOFF_FIXTURE="$TMP/handoffs.json" \
    HANDOFF_RC="${HANDOFF_RC_OVERRIDE:-0}" HANDOFF_FILTER="${HANDOFF_FILTER_OVERRIDE:-1}" \
    QUEUE_STDERR="${2:-}" GC_RIG="${GC_RIG_OVERRIDE-gc-toolkit}" LIST_RC="${3:-0}" \
    STUB_AGENTS="${AGENTS_OVERRIDE-$AGENTS_DEFAULT}" STUB_AGENTS_FAIL="${AGENTS_FAIL:-}" \
    QUEUE_OWNER="${QUEUE_OWNER_OVERRIDE-gc-toolkit/gc-toolkit.refinery}" \
    STUB_PACK="$TMP/rig" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/nocity" \
      bash "$TMP/run.sh" > "$TMP/out" 2>&1 || true )
  cat "$TMP/calls"
}
out() { cat "$TMP/out"; }

# Timestamps relative to the block's real `date`: far past is stuck, ~now churns.
OLD1="2020-01-01T00:00:00Z"
OLD2="2020-06-01T00:00:00Z"
FRESH="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

STUCK_ONE='[{"id":"tk-stuck","updated_at":"'"$OLD1"'","title":"handoff","metadata":{}}]'
GATED="$(run "$STUCK_ONE")"
eq "$(printf '%s' "$GATED" | grep -c . || true)" "1" "a handoff past the bound files once"
has "$GATED" "human-gate --subject tk-stuck" "the gate's subject is the stuck handoff"
has "$GATED" "--key witness-refinery-queue " "the gate carries the situation key"
# The next pass detects the same stuck handoff again, so the call declares the
# quiet window that lets a person's moot or benign answer stand.
has "$GATED" "--quiet-window 86400" "the stuck-handoff call declares a day-long quiet window"
LISTED="$(cat "$TMP/lists")"
has "$LISTED" "--assignee=gc-toolkit/gc-toolkit.refinery" "the queue read is the refinery's own"
has "$LISTED" "--status=open" "the queue read is OPEN beads only"
has "$LISTED" "--has-metadata-key=branch" "the queue read is scoped to branch-bearing work"
has "$LISTED" "--exclude-type=epic" "the queue read excludes epics"
has "$LISTED" "--limit=0" "the queue read is not truncated by a default page size"
has "$LISTED" "gate list --json --limit 0" "the store's gates are listed whole, not the first page"

# Fresh churn is not stuck.
eq "$(run '[{"id":"tk-fresh","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]')" "" \
   "a fresh handoff (recent updated_at) files nothing"

# A gating anchor carries merge_result — the cadence's, never gated even old.
eq "$(run '[{"id":"tk-gate","updated_at":"'"$OLD1"'","title":"anchor","metadata":{"merge_result":"pull_request"}}]')" "" \
   "an old gating anchor (merge_result set) files nothing"

# Mixed: one stuck handoff, one fresh, one old gating anchor -> exactly the stuck one.
MIXED='[
  {"id":"tk-stuck","updated_at":"'"$OLD1"'","title":"handoff","metadata":{}},
  {"id":"tk-fresh","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}},
  {"id":"tk-gate","updated_at":"'"$OLD2"'","title":"anchor","metadata":{"merge_result":"pre_open_gate"}}
]'
MIXED_CALLS="$(run "$MIXED")"
eq "$(printf '%s' "$MIXED_CALLS" | grep -c . || true)" "1" "a mixed queue files exactly the stuck handoff"
has "$MIXED_CALLS" "tk-stuck" "the gate is for the stuck handoff"
hasnt "$MIXED_CALLS" "tk-fresh" "the fresh handoff is not gated"
hasnt "$MIXED_CALLS" "tk-gate" "the gating anchor is not gated"

# Two stuck handoffs -> one call each (one open gate per bead and key is the
# helper's).
TWO_STUCK='[
  {"id":"tk-s1","updated_at":"'"$OLD1"'","title":"a","metadata":{}},
  {"id":"tk-s2","updated_at":"'"$OLD2"'","title":"b","metadata":{}}
]'
eq "$(printf '%s' "$(run "$TWO_STUCK")" | grep -c . || true)" "2" \
   "two stuck handoffs file once each"

# A raw control byte in a bead string (here a stuck handoff's title) aborts jq on
# the whole array, which would blind this monitor. The control-byte strip
# rescues the parse, so the stuck handoff is still gated and the read is never
# mistaken for unreadable.
CTL="$(printf 'x\001y')"
CTRL_STUCK='[{"id":"tk-ctl","updated_at":"'"$OLD1"'","title":"handoff '"$CTL"'","metadata":{}}]'
CTRL_CALLS="$(run "$CTRL_STUCK")"
has "$CTRL_CALLS" "human-gate --subject tk-ctl" "a raw control byte in the queue does not blind the stuck-handoff read"
has "$CTRL_CALLS" "--key witness-refinery-queue " "the rescued read gates the stuck handoff normally"
hasnt "$(out)" "unreadable" "a control byte is stripped, not treated as unreadable"

# An empty queue is a valid array with nothing stuck: nothing is filed.
eq "$(run '[]')" "" "an empty queue files nothing"
has "$(out)" "no stuck handoffs" "an empty queue is reported apart from an unreadable one"

# A genuinely unreadable queue — not a JSON array even after the control-byte
# strip, or a failed listing — reports the BLIND MONITOR loudly, under its own
# key, as a patrol finding that names no stuck bead.
blind() {
  local calls; calls="$(run "$@")"
  has "$calls" "patrol-finding --scope witness-findings --key witness-refinery-queue-unreadable" \
     "an unreadable read reports the blind monitor as a patrol finding"
  hasnt "$calls" "human-gate " "the blind monitor files no human gate"
  hasnt "$calls" "--subject tk-" "the blind-monitor report names no stuck bead"
}
blind 'warning: config drift
[]'
blind '{"error":"store unavailable"}'
blind 'null'
blind '' '' 1
has "$(out)" "unreadable" "a failed listing still reports it is unreadable"

# Unset GC_RIG leaves no rig to qualify the name with. A city-scoped refinery
# still resolves, and the message names it with no leading slash.
CITY_REFINERY='{"agents":[{"qualified_name":"gc-toolkit.refinery"}]}'
URIG="$(GC_RIG_OVERRIDE='' AGENTS_OVERRIDE="$CITY_REFINERY" QUEUE_OWNER_OVERRIDE=gc-toolkit.refinery run "$STUCK_ONE")"
has "$URIG" "gc-toolkit.refinery" "unset GC_RIG still names the refinery"
hasnt "$URIG" "/gc-toolkit.refinery" "unset GC_RIG emits no leading slash"
# Two rigs' refineries and no rig to choose between them: no queue is guessed.
AMBIG="$(GC_RIG_OVERRIDE='' run "$STUCK_ONE")"
has "$AMBIG" "patrol-finding --scope witness-findings --key witness-refinery-queue-unroutable" \
   "unset GC_RIG with several rigs' refineries reports the blind monitor as a patrol finding"
hasnt "$AMBIG" "human-gate " "and files no human gate"
eq "$(cat "$TMP/lists")" "" "and reads no queue it would have to guess"

# The block is instruction text an agent runs, so it lands in whatever shell the
# caller has already set up, including a strict one.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  has "$(run "$STUCK_ONE" '' 0 "$PRELUDE")" "human-gate --subject tk-stuck" \
     "$PRELUDE: a stuck handoff is still gated"
  has "$(run '' '' 1 "$PRELUDE")" "--key witness-refinery-queue-unreadable" \
     "$PRELUDE: a failed listing reports the blind monitor"
  has "$(out)" "unreadable" "$PRELUDE: a failed listing still reaches the diagnostic"
  eq "$(run '[]' '' 0 "$PRELUDE")" "" \
     "$PRELUDE: an empty queue files nothing"
done

# The stuck-handoff read and the filings share one queue: the refinery queue is
# read exactly once (never re-read per bead). The withdrawal lists the store's
# gates once, reads each gate's waiting beads from one call site, and reads its
# candidate handoffs once, by id. No nudge.
eq "$(printf '%s\n' "$BLOCK" | grep -c 'bd list --assignee' || true)" "1" \
   "the refinery queue is read exactly once"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'gc bd gate list' || true)" "1" \
   "the store's gates are listed exactly once"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'gc bd dep list' || true)" "1" \
   "a gate's waiting beads are read from one call site"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'bd list --id=' || true)" "1" \
   "the candidate handoffs are read exactly once, by id"
eq "$(awk '
  /# >>> refinery-stuck-handoff/ {inside = 1}
  /# <<< refinery-stuck-handoff/ {inside = 0; next}
  !inside && /gc session nudge/ && /refinery/ {print FNR ": " $0}
' "$TOML")" "" "no refinery nudge anywhere in the formula"

# A TOML basic multi-line string rewrites a backslash, so the block has to stay
# free of them to survive the pour intact.
case "$BLOCK" in
  *'\'*) bad "block contains a backslash — the TOML \"\"\" string mangles it" ;;
  *)     ok "block is backslash-free" ;;
esac

# --- A held bead is waiting, not stuck -----------------------------------------
# A landing bead sits in the queue from the moment its effort is stood up, so it
# is past the bound long before its effort's beads close. Its blockers are read
# by id, served here from the 6th run() argument with the withdrawal's rows.
# blocked <id> <updated_at> <blocker>...: a queue row with a blocks edge onto each.
blocked() { local id="$1" when="$2"; shift 2
  jq -nc --arg id "$id" --arg u "$when" --args '{id: $id, updated_at: $u, title: "handoff",
    metadata: {branch: ("integration/" + $id)},
    dependencies: [ $ARGS.positional[] as $b | {issue_id: $id, depends_on_id: $b, type: "blocks"} ]}' "$@"; }
LAND="$(blocked tk-land "$OLD1" tk-e1 tk-sum)"
OPEN_BLOCKERS='[{"id":"tk-e1","status":"open","title":"effort bead","metadata":{}},{"id":"tk-sum","status":"open","title":"summary task","metadata":{}}]'
eq "$(run "[$LAND]" "" "" "" "" "$OPEN_BLOCKERS")" "" "a held landing bead past the stuck bound files no gate"
has "$(out)" "no stuck handoffs" "and the queue reads as churning normally"
has "$(cat "$TMP/lists")" "--id=tk-e1,tk-sum" "its blockers are read by id"
HELD_AND_STUCK="$(run "[$LAND,{\"id\":\"tk-stuck\",\"updated_at\":\"$OLD2\",\"title\":\"handoff\",\"metadata\":{}}]" "" "" "" "" "$OPEN_BLOCKERS")"
eq "$(printf '%s' "$HELD_AND_STUCK" | grep -c . || true)" "1" "an unheld handoff past the bound beside it still files one gate"
has "$HELD_AND_STUCK" "human-gate --subject tk-stuck" "the gate is the unheld handoff's"
hasnt "$HELD_AND_STUCK" "tk-land" "and not the held landing bead's"
# Released a minute ago, last written years ago: the wait starts at the release.
JUST="$(date -u -r "$(( $(date -u +%s) - 60 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '-60 seconds' +%Y-%m-%dT%H:%M:%SZ)"
RELEASED='[{"id":"tk-e1","status":"closed","closed_at":"'"$OLD2"'","metadata":{}},{"id":"tk-sum","status":"closed","closed_at":"'"$JUST"'","metadata":{}}]'
eq "$(run "[$LAND]" "" "" "" "" "$RELEASED")" "" "a landing bead its summary task released a minute ago is not stuck"
LONG_GONE='[{"id":"tk-e1","status":"closed","closed_at":"2020-03-01T00:00:00Z","metadata":{}},{"id":"tk-sum","status":"closed","closed_at":"'"$OLD2"'","metadata":{}}]'
LG="$(run "[$LAND]" "" "" "" "" "$LONG_GONE")"
has "$LG" "human-gate --subject tk-land" "one released past the bound and still not taken is stuck"
has "$LG" "since $OLD2" "and its wait is dated from the release, not its last write"
# Held only by a blocker the store does not return: find-work never takes it,
# so it is stuck past the bound, and the gate names the blocker.
GHOSTED="$(run "[$(blocked tk-ghosted "$OLD1" tk-ghost)]" "" "" "" "" '[]')"
has "$GHOSTED" "human-gate --subject tk-ghosted" "a bead held only by an unreadable blocker is gated past the bound"
has "$GHOSTED" "waits on tk-ghost (unreadable), a blocker this store does not return" "the gate names the blocker it waits on"
# A walk of the holds that cannot read blinds the monitor.
WALK="$(HANDOFF_RC_OVERRIDE=1 run "[$LAND]" "" "" "" "" "$OPEN_BLOCKERS")"
has "$WALK" "patrol-finding --scope witness-findings --key witness-refinery-queue-unreadable" "a hold walk that cannot read reports the blind monitor as a patrol finding"
hasnt "$WALK" "--subject tk-" "naming no stuck bead"
has "$(out)" "could not read what holds the handoffs past the stuck bound" "and says why"
has "$(HANDOFF_RC_OVERRIDE=1 run "$STUCK_ONE")" "human-gate --subject tk-stuck" "a past-bound bead with no blocker needs no hold read"
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  eq "$(run "[$LAND]" "" "" "$PRELUDE" "" "$OPEN_BLOCKERS")" "" "$PRELUDE: a held landing bead files no gate"
  has "$(HANDOFF_RC_OVERRIDE=1 run "[$LAND]" "" "" "$PRELUDE" "" "$OPEN_BLOCKERS")" "--key witness-refinery-queue-unreadable" \
     "$PRELUDE: a hold walk that cannot read still reports the blind monitor"
done

# --- Withdrawal: a departed handoff's gate is resolved moot --------------------
# A handoff that an open witness-refinery-queue human gate blocks and that the
# readable queue no longer carries is only a candidate. The block reads each
# candidate by id and withdraws its gates through human-gate.sh --retract only
# when that row shows the handoff left: closed, carrying a merge_result,
# unassigned, or assigned to something other than a refinery. Every other bead
# those gates block must have left the same way. The store's gate listing is the
# 5th run() argument and the by-id rows the 6th.
# gate <id> [await-id] [status] [await-type] -> one row as bd gate list prints it.
gate() {
  printf '{"id":"%s","issue_type":"gate","await_type":"%s","await_id":"%s","status":"%s","title":"stuck handoff"}' \
    "$1" "${4:-human}" "${2:-witness-refinery-queue}" "${3:-open}"
}
QUEUE_OTHER='[{"id":"tk-still","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]'
G_GONE="[$(gate tk-g-gone)]"
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

RET="$(run "$QUEUE_OTHER" "" "" "" "$G_GONE" "$H_CLOSED")"
has "$RET" "human-gate --retract" "a closed handoff gone from the queue has its gate withdrawn"
has "$RET" "--subject tk-gone" "the withdrawal names the departed handoff as the subject"
has "$RET" "--key witness-refinery-queue " "the withdrawal carries the situation key"
has "$RET" "Refinery handoff tk-gone is closed," "the withdrawal's reading names what the handoff's own row showed"
hasnt "$RET" "--quiet-window" "a withdrawal declares no quiet window"
has "$(grep -e 'dep list' "$TMP/lists" || true)" "dep list tk-g-gone --direction=up --type blocks --json" \
   "the gate's waiting beads are read from the gate's end"
IDREAD="$(grep -e '--id=' "$TMP/lists" || true)"
has "$IDREAD" "--id=tk-gone" "the candidate is read by id"
has "$IDREAD" "--all" "the by-id read includes closed beads"

# Still in the queue: the premise holds, so it is no candidate and is not read.
QUEUE_SUBJ='[{"id":"tk-gone","updated_at":"'"$FRESH"'","title":"handoff","metadata":{}}]'
RET2="$(run "$QUEUE_SUBJ" "" "" "" "$G_GONE" "$H_CLOSED")"
hasnt "$RET2" "--retract" "a handoff still in the queue keeps its gate open"
hasnt "$(cat "$TMP/lists")" "--id=" "a handoff still in the queue is not read by id"

# A gate that blocks two handoffs is about both, and --retract on either one
# resolves it for both. So it stays open while one of them is still in the queue,
# and the line that reports the kept gate names the handoff that keeps it.
RBOTH="$(run "$QUEUE_OTHER" "" "" "" "[$(gate tk-g-both)]" "$H_CLOSED")"
hasnt "$RBOTH" "--retract" "a gate on two handoffs is not withdrawn while one of them is still in the queue"
has "$(out)" "tk-gone is closed, but its gate tk-g-both also blocks tk-still, which is still in the queue; every gate on tk-gone stays open" \
   "the kept gate is reported with the handoff that keeps it open"
has "$(grep -e '--id=' "$TMP/lists" || true)" "--id=tk-gone " "only the departed handoff is read by id"
# Once both have left, the gate is withdrawn.
H_BOTH_LEFT='[{"id":"tk-gone","status":"closed","assignee":null,"title":"handoff","metadata":{"merge_result":"merged"}},
  {"id":"tk-still","status":"open","assignee":null,"title":"handoff","metadata":{"merge_result":"pull_request"}}]'
RBOTH2="$(run '[]' "" "" "" "[$(gate tk-g-both)]" "$H_BOTH_LEFT")"
has "$RBOTH2" "--retract --subject tk-gone" "a gate on two handoffs is withdrawn once both have left"
has "$RBOTH2" "--retract --subject tk-still" "and each departed handoff withdraws its own gates"
hasnt "$(out)" "stays open" "and nothing is reported kept"
has "$(grep -e '--id=' "$TMP/lists" || true)" "--id=tk-gone,tk-still" "both handoffs ride the one by-id read"
# Missing from the listing proves nothing about the other handoff either: a row
# that shows it still with the refinery keeps the shared gate, and so does no
# row at all.
H_GONE_STILL_HELD='[{"id":"tk-gone","status":"closed","assignee":null,"title":"handoff","metadata":{}},
  {"id":"tk-still","status":"open","assignee":"'"$REF"'","title":"handoff","metadata":{"branch":"polecat/tk-still"}}]'
RBOTH3="$(run '[]' "" "" "" "[$(gate tk-g-both)]" "$H_GONE_STILL_HELD")"
hasnt "$RBOTH3" "--retract" "a gate shared with a handoff still assigned to the refinery stays open"
has "$(out)" "its gate tk-g-both also blocks tk-still, which stays assigned to $REF (status open)" \
   "the kept gate names what the other handoff's row showed"
has "$(out)" "tk-still is missing from the queue listing but is still unprepared" "the other handoff gets its own line"
RBOTH4="$(run '[]' "" "" "" "[$(gate tk-g-both)]" "$H_CLOSED")"
hasnt "$RBOTH4" "--retract" "a gate shared with a handoff the by-id read returned no row for stays open"
has "$(out)" "its gate tk-g-both also blocks tk-still, which could not be read" "the kept gate says the other handoff could not be read"
# --retract resolves every open gate under the key on its subject, so a gate of
# the departed handoff's own is not withdrawn beside one it shares with a
# handoff still in the queue.
RSOLO="$(run "$QUEUE_OTHER" "" "" "" "[$(gate tk-g-gone),$(gate tk-g-both)]" "$H_CLOSED")"
hasnt "$RSOLO" "--retract" "a departed handoff's own gate stays open while it shares another with a handoff still in the queue"
# A waiting row with no id names no bead to read, and what the gate also blocks
# is then unknown, so the gate stays open.
RNOID="$(run '[]' "" "" "" "[$(gate tk-g-noid)]" "$H_CLOSED")"
hasnt "$RNOID" "--retract" "a gate with a waiting row that has no id stays open"
has "$(grep -e '--id=' "$TMP/lists" || true)" "--id=tk-gone " "and only the row with an id is read by id"
# A gate whose waiting beads did not read may block a departed handoff beside a
# bead still in the queue, so while it stays unread no departed handoff is
# withdrawn.
RDARK="$(run '[]' "" "" "" "[$(gate tk-g-gone),$(gate tk-g-dark)]" "$H_CLOSED")"
hasnt "$RDARK" "--retract" "a gate whose waiting beads did not read keeps every departed handoff's gates open"
has "$(out)" "tk-gone is closed, but the beads gate tk-g-dark blocks could not be read" "the line names the gate that did not read"

# Two gates under the key on one handoff make one candidate. The helper's
# withdrawal resolves every open gate under the key among the bead's gates, so
# one call clears both.
RDUP="$(run "$QUEUE_OTHER" "" "" "" "[$(gate tk-g-gone),$(gate tk-g-gone2)]" "$H_CLOSED")"
eq "$(printf '%s' "$RDUP" | grep -c -e '--retract' || true)" "1" "two gates on one handoff make one withdrawal"
has "$(grep -e '--id=' "$TMP/lists" || true)" "--id=tk-gone " "and one candidate in the by-id read"

# The listing holds only gates that stand for this situation: open, human, under
# the key. bd prints null with no gates and [] through a proxied server, and a
# failed listing leaves nothing to withdraw.
for GL in null '[]' "[$(gate tk-g-gone witness-refinery-queue closed)]" \
          "[$(gate tk-g-gone witness-refinery-queue open timer)]" \
          "[$(gate tk-g-gone some-other-key)]"; do
  hasnt "$(run "$QUEUE_OTHER" "" "" "" "$GL" "$H_CLOSED")" "--retract" \
     "a gate listing of $GL withdraws nothing"
  hasnt "$(cat "$TMP/lists")" "--id=" "and reads no handoff by id"
done
RGF="$(GATES_RC_OVERRIDE=1 run "$STUCK_ONE" "" "" "" "$G_GONE" "$H_CLOSED")"
hasnt "$RGF" "--retract" "a failed gate listing withdraws nothing"
has "$RGF" "human-gate --subject tk-stuck" "and the stuck handoff beside it is still gated"

# Absence from the listing is not departure. A listing under a wrong address is
# a valid empty array with exit 0, and a handoff still open and assigned to the
# refinery keeps its gate through it.
RB="$(run '[]' "" "" "" "$G_GONE" "$H_HELD")"
hasnt "$RB" "--retract" "an empty listing does not withdraw a handoff still assigned to the refinery"
has "$(out)" "tk-gone is missing from the queue listing but is still unprepared and assigned to $REF (status open)" \
   "the kept gate is reported with what the handoff's row showed"

# A dotless binding_prefix renders the address gc-toolkit/gc-toolkitrefinery,
# which no handoff carries. The block reads it only when the roster cannot be
# read to refute it, and its listing comes back empty.
RBW="$(AGENTS_FAIL=1 BLOCK_FILE_OVERRIDE="$TMP/block-nodot.sh" run '[]' "" "" "" "$G_GONE" "$H_HELD")"
has "$(cat "$TMP/lists")" "--assignee=gc-toolkit/gc-toolkitrefinery" "the dotless-prefix render under an unreadable roster lists under the wrong address"
hasnt "$RBW" "--retract" "a wrong-address listing withdraws nothing while the handoff is still with the refinery"

# The assignee is compared by role, so any form of the refinery's address keeps
# the gate, and so does a status the queue read does not list.
for WHO in gc-toolkit.refinery gc-toolkit/refinery refinery; do
  hasnt "$(run '[]' "" "" "" "$G_GONE" "$(handoff open "\"$WHO\"")")" "--retract" \
     "a handoff assigned to $WHO is still with a refinery"
done
for ST in in_progress blocked; do
  hasnt "$(run '[]' "" "" "" "$G_GONE" "$(handoff "$ST" "\"$REF\"")")" "--retract" \
     "a handoff in status $ST, still assigned to the refinery, keeps its gate"
done

# Every departure the row can show withdraws, and the reading names it.
RMR="$(run '[]' "" "" "" "$G_GONE" "$(handoff open null pull_request)")"
has "$RMR" "--retract --subject tk-gone" "a handoff carrying a merge_result has left"
has "$RMR" "carries merge_result=pull_request" "the reading names the merge_result"
# Prepared is a departure on its own, even with the refinery still the assignee.
has "$(run '[]' "" "" "" "$G_GONE" "$(handoff open "\"$REF\"" pre_open_gate)")" "--retract --subject tk-gone" \
   "a prepared handoff still assigned to the refinery has left"
RUN1="$(run '[]' "" "" "" "$G_GONE" "$(handoff open '""')")"
has "$RUN1" "--retract --subject tk-gone" "an unassigned handoff has left"
has "$RUN1" "is unassigned" "the reading says it is unassigned"
H_NOKEY='[{"id":"tk-gone","status":"open","title":"handoff","metadata":{"branch":"polecat/tk-gone"}}]'
has "$(run '[]' "" "" "" "$G_GONE" "$H_NOKEY")" "--retract --subject tk-gone" \
   "a handoff whose row carries no assignee has left"
RPC="$(run '[]' "" "" "" "$G_GONE" "$(handoff in_progress '"hq-wisp-abc"')")"
has "$RPC" "--retract --subject tk-gone" "a handoff reassigned to a worker has left"
has "$RPC" "is assigned to hq-wisp-abc, not a refinery" "the reading names the new assignee"

# A handoff that cannot be read keeps its gate: a failed read, an error object,
# and a row for some other bead are none of them a departure.
RU1="$(HANDOFF_RC_OVERRIDE=1 run '[]' "" "" "" "$G_GONE" "$H_CLOSED")"
hasnt "$RU1" "--retract" "a failed by-id read withdraws nothing"
has "$(out)" "could not read handoff tk-gone" "a failed by-id read is reported per candidate"
RU2="$(run '[]' "" "" "" "$G_GONE" '{"error":"no issues found matching the provided IDs"}')"
hasnt "$RU2" "--retract" "an error object from the by-id read withdraws nothing"
RU3="$(HANDOFF_FILTER_OVERRIDE=0 run '[]' "" "" "" "$G_GONE" '[{"id":"tk-other","status":"closed","assignee":null,"metadata":{}}]')"
hasnt "$RU3" "--retract" "a row for a different bead does not decide the candidate"

# bd drops an id it cannot resolve and still exits 0. The dropped candidate keeps
# its gate, and it does not silence a departed candidate read beside it.
RU4="$(run '[]' "" "" "" "[$(gate tk-g-gone),$(gate tk-g-lost)]" "$H_CLOSED")"
has "$RU4" "--retract --subject tk-gone" "a departed candidate is withdrawn beside an unresolvable one"
hasnt "$RU4" "--subject tk-lost" "a candidate the read dropped keeps its gate"
has "$(out)" "could not read handoff tk-lost" "the dropped candidate is reported"
eq "$(grep -c -e '--id=' "$TMP/lists" || true)" "1" "every candidate rides one by-id read"
has "$(cat "$TMP/lists")" "--id=tk-gone,tk-lost" "the one read names every candidate"

# A raw control byte in the handoff's row is stripped before the parse, as in
# the queue read.
H_CTL='[{"id":"tk-gone","status":"closed","assignee":null,"title":"handoff '"$CTL"'","metadata":{}}]'
has "$(run '[]' "" "" "" "$G_GONE" "$H_CTL")" "--retract --subject tk-gone" \
   "a raw control byte in the handoff's row does not blind the departure read"

# An unreadable queue never withdraws: the gate is QUEUE_RC, so a transient blip
# runs no candidate pass at all, and no gate listing is read.
RET4="$(run "" "" 1 "" "$G_GONE" "$H_CLOSED")"
hasnt "$RET4" "--retract" "an unreadable queue withdraws nothing (gated on QUEUE_RC)"
hasnt "$(cat "$TMP/lists")" "gate list" "an unreadable queue lists no gates"

# The withdrawal, like the filing, survives a strict shell.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  has "$(run "$QUEUE_OTHER" "" "" "$PRELUDE" "$G_GONE" "$H_CLOSED")" "--retract --subject tk-gone" \
     "$PRELUDE: a departed handoff's gate is still withdrawn"
  hasnt "$(run '[]' "" "" "$PRELUDE" "$G_GONE" "$H_HELD")" "--retract" \
     "$PRELUDE: a handoff still with the refinery keeps its gate"
  hasnt "$(HANDOFF_RC_OVERRIDE=1 run '[]' "" "" "$PRELUDE" "$G_GONE" "$H_CLOSED")" "--retract" \
     "$PRELUDE: a failed by-id read withdraws nothing"
  has "$(out)" "could not read handoff tk-gone" "$PRELUDE: a failed by-id read still reaches the diagnostic"
  hasnt "$(GATES_RC_OVERRIDE=1 run '[]' "" "" "$PRELUDE" "$G_GONE" "$H_CLOSED")" "--retract" \
     "$PRELUDE: a failed gate listing withdraws nothing"
  hasnt "$(run "$QUEUE_OTHER" "" "" "$PRELUDE" "[$(gate tk-g-both)]" "$H_CLOSED")" "--retract" \
     "$PRELUDE: a gate shared with a handoff still in the queue stays open"
  has "$(out)" "also blocks tk-still, which is still in the queue" "$PRELUDE: the kept gate still reaches the diagnostic"
  has "$(run '[]' "" "" "$PRELUDE" "[$(gate tk-g-both)]" "$H_BOTH_LEFT")" "--retract --subject tk-gone" \
     "$PRELUDE: a shared gate is still withdrawn once both handoffs have left"
  hasnt "$(run '[]' "" "" "$PRELUDE" "[$(gate tk-g-gone),$(gate tk-g-dark)]" "$H_CLOSED")" "--retract" \
     "$PRELUDE: a gate whose waiting beads did not read still withdraws nothing"
done

# --- The queue is read at a resolved address, never an assembled one ---------
# An empty or wrong prefix renders an address no agent holds. A read there is a
# valid empty array, which reads as a clean queue, so a stuck handoff would never
# be gated. Here tk-stuck is in the live queue and its gate is open.
G_STUCK_OPEN="[$(gate tk-g-stuck)]"
# An empty or misspelled prefix names no binding gc knows, so the block finds no
# pack: it stops loud before it reads, files or withdraws anything, and never
# falls back to a script outside the pack gc names.
for PFX in noprefix typo; do
  NCALLS="$(BLOCK_FILE_OVERRIDE="$TMP/block-$PFX.sh" run "$STUCK_ONE" "" "" "" "$G_STUCK_OPEN")"
  eq "$NCALLS" "" "$PFX: no binding gc knows, so nothing is filed or withdrawn"
  eq "$(cat "$TMP/lists")" "" "$PFX: no queue and no gate listing is read"
  hasnt "$(out)" "no stuck handoffs" "$PFX: an unread queue is never reported clean"
  has "$(out)" "human-gate.sh, patrol-finding.sh, resolve-route.sh, bd-lib.sh and hold-lib.sh not found in the pack" "$PFX: the stop names the scripts it could not reach"
done
# A dotless prefix still names the pack, and its address is one no agent holds,
# which reports the blind monitor.
NCALLS="$(BLOCK_FILE_OVERRIDE="$TMP/block-nodot.sh" run "$STUCK_ONE" "" "" "" "$G_STUCK_OPEN")"
has "$NCALLS" "patrol-finding --scope witness-findings --key witness-refinery-queue-unroutable" \
   "nodot: an address no agent holds reports the blind monitor as a patrol finding"
hasnt "$NCALLS" "--retract" "nodot: and withdraws no gate, though its handoff is unseen"
hasnt "$NCALLS" "--subject tk-stuck" "nodot: and files nothing about a queue it never read"
eq "$(cat "$TMP/lists")" "" "nodot: no queue and no gate listing is read"
has "$(out)" "no live refinery identity resolves" "nodot: the diagnostic says why"
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  NCALLS="$(BLOCK_FILE_OVERRIDE="$TMP/block-nodot.sh" run "$STUCK_ONE" '' 0 "$PRELUDE" "$G_STUCK_OPEN")"
  has "$NCALLS" "--key witness-refinery-queue-unroutable" \
     "$PRELUDE: an address no agent holds still reports the blind monitor"
  hasnt "$NCALLS" "--retract" "$PRELUDE: and still withdraws nothing"
done

# The read follows the identity that is live, not the string the template
# rendered: where the refinery is city-scoped, the rig-qualified name resolves
# to the bare identity, and that is the queue read.
CITY_CALLS="$(AGENTS_OVERRIDE="$CITY_REFINERY" QUEUE_OWNER_OVERRIDE=gc-toolkit.refinery run "$STUCK_ONE")"
has "$CITY_CALLS" "human-gate --subject tk-stuck" "a city-scoped refinery's stuck handoff is gated"
has "$(cat "$TMP/lists")" "--assignee=gc-toolkit.refinery " "the queue read is the live city-scoped identity"

# An unreadable roster proves nothing about the address. resolve-route.sh hands
# the rendered name back UNVERIFIED, so the queue there is still read and a stuck
# handoff in it is still gated. The candidate pass would compare each handoff's
# assignee against the role of that unproven name, so it does not run: tk-gone's
# gate, which a verified read withdraws above from the same closed row, stays
# open.
UCALLS="$(AGENTS_FAIL=1 run "$STUCK_ONE" "" "" "" "$G_GONE" "$H_CLOSED")"
has "$UCALLS" "human-gate --subject tk-stuck" "unreadable roster: a stuck handoff at the rendered address is still gated"
has "$(cat "$TMP/lists")" "--assignee=gc-toolkit/gc-toolkit.refinery " \
   "unreadable roster: the rig-qualified rendered address is the one read"
has "$(out)" "UNVERIFIED" "unreadable roster: the read is marked unproven"
hasnt "$UCALLS" "--retract" "unreadable roster: nothing is withdrawn on an unverified read"
hasnt "$(cat "$TMP/lists")" "gate list" "unreadable roster: no gate listing is read"

# Both faults at once: the dead address is read unverified and comes back empty,
# while the handoff is still held by the refinery. No live gate is withdrawn.
H_STUCK_HELD='[{"id":"tk-stuck","status":"open","assignee":"gc-toolkit/gc-toolkit.refinery","title":"handoff","metadata":{"branch":"polecat/tk-stuck"}}]'
DCALLS="$(AGENTS_FAIL=1 BLOCK_FILE_OVERRIDE="$TMP/block-noprefix.sh" run "$STUCK_ONE" "" "" "" "$G_STUCK_OPEN" "$H_STUCK_HELD")"
hasnt "$DCALLS" "--retract" "unreadable roster and empty prefix: no live gate is withdrawn"

# A prefix missing its trailing dot renders gc-toolkit/gc-toolkitrefinery, whose
# role is gc-toolkitrefinery. Read unverified, that name is the one the
# candidates' assignees would be compared against, and a handoff the refinery
# still holds would compare as reassigned. The verified-address gate keeps its
# gate open.
NDCALLS="$(AGENTS_FAIL=1 BLOCK_FILE_OVERRIDE="$TMP/block-nodot.sh" run "$STUCK_ONE" "" "" "" "$G_STUCK_OPEN" "$H_STUCK_HELD")"
has "$(cat "$TMP/lists")" "--assignee=gc-toolkit/gc-toolkitrefinery " \
   "unreadable roster and a dotless prefix: the unverified address is read"
hasnt "$NDCALLS" "--retract" "unreadable roster and a dotless prefix: a held handoff's gate is not withdrawn"

# --- A shared gate through the real helper ------------------------------------
# The cases above stub human-gate.sh, so they see the calls the block makes and
# not what a call does to a gate. Here the block runs the real human-gate.sh,
# bd-lib.sh and hold-lib.sh, in the pack the stub gc names, against a store stub that keeps the beads, the gates and the
# `blocks` edges (`<waiter>|blocks|<gate>` lines), and serves each read from
# that state the way bd does: a gate's waiting beads from the gate's end, a
# bead's gates from the bead's end. One gate blocks two handoffs. While one of
# them still sits stuck in the queue, the gate stays open and that handoff stays
# blocked; once it has left too, the gate is resolved moot.
mkdir -p "$TMP/sbin" "$TMP/srig/assets/scripts" "$TMP/s"
for S in human-gate.sh bd-lib.sh hold-lib.sh resolve-route.sh; do cp "$ROOT/assets/scripts/$S" "$TMP/srig/assets/scripts/"; done
chmod +x "$TMP/srig/assets/scripts/human-gate.sh" "$TMP/srig/assets/scripts/resolve-route.sh"
cp "$TMP/rig/assets/scripts/patrol-finding.sh" "$TMP/srig/assets/scripts/"
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/sbin/gc" <<'STUB'
set -u
STORE="${STUB_STORE:?}"; EDGES="${STUB_EDGES:?}"
save() { local t; t=$(mktemp "${STUB_TMP:?}/store.XXXXXX"); cat > "$t" && mv "$t" "$STORE"; }
# rows <newline-separated ids> -> those beads' rows, as a dep list prints them.
rows() { jq -c --arg ids "$1" '($ids | split("\n") | map(select(. != ""))) as $w
  | [ .[] | select(.id as $i | $w | index($i)) | . + {dependency_type: "blocks"} ]' "$STORE"; }
if [ "${1:-} ${2:-}" = "agent list" ]; then printf '%s\n' "$STUB_AGENTS"; exit 0; fi
if [ "${1:-} ${2:-}" = "gc-toolkit scripts-dir" ]; then [ -n "${STUB_PACK:-}" ] || exit 1; printf '%s/assets/scripts\n' "$STUB_PACK"; exit 0; fi
[ "${1:-}" = bd ] || { echo "stub gc: unexpected call: $*" >&2; exit 99; }
shift
case "${1:-} ${2:-}" in
  "gate list")
    # bd lists the gates that are not closed, and prints null when there are none.
    jq -c '[ .[] | select(.issue_type == "gate" and .status != "closed") ] | if length == 0 then null else . end' "$STORE"
    exit 0 ;;
  "dep list")
    bead="${3:-}"
    jq -e --arg id "$bead" 'any(.[]; .id == $id)' "$STORE" >/dev/null \
      || { printf '{"error":"no issue found matching %s"}\n' "$bead"; exit 1; }
    case "$* " in
      *" --direction=up "*) rows "$(awk -F'|' -v b="$bead" '$3 == b && $2 == "blocks" { print $1 }' "$EDGES")" ;;
      *) rows "$(awk -F'|' -v b="$bead" '$1 == b && $2 == "blocks" { print $3 }' "$EDGES")" ;;
    esac
    exit 0 ;;
  "gate resolve")
    id="${3:-}"; shift 3; reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) shift; reason="${1:-}" ;; esac; shift || true; done
    printf '%s|%s\n' "$id" "$reason" >> "$STUB_RESOLVES"
    jq -c --arg id "$id" --arg r "$reason" --arg at "$(jq -nr 'now | todate')" 'map(if .id == $id and .status != "closed"
      then .status = "closed" | .close_reason = $r | .closed_at = $at else . end)' "$STORE" | save
    echo "Gate resolved: $id"
    exit 0 ;;
  "gate create")
    printf '%s\n' "$*" >> "$STUB_CREATES"
    echo '{"error":"this store files no gate"}'
    exit 1 ;;
esac
case "${1:-}" in
  show) jq -c --arg id "${2:-}" '[ .[] | select(.id == $id) ]' "$STORE"; exit 0 ;;
  list)
    ids=""; who=""; all=false
    for a in "$@"; do
      case "$a" in --id=*) ids="${a#--id=}" ;; --assignee=*) who="${a#--assignee=}" ;; --all) all=true ;; esac
    done
    if [ -n "$ids" ]; then
      jq -c --arg ids "$ids" --argjson all "$all" '($ids | split(",")) as $w
        | [ .[] | select(.id as $i | $w | index($i)) | select($all or .status != "closed") ]' "$STORE"
    else
      jq -c --arg w "$who" '[ .[] | select((.assignee // "") == $w and .status == "open"
        and .issue_type != "epic" and (.metadata.branch // "") != "") ]' "$STORE"
    fi
    exit 0 ;;
esac
echo "stub gc: unexpected bd call: $*" >&2; exit 99
STUB
chmod +x "$TMP/sbin/gc"
export STUB_STORE="$TMP/s/store.json" STUB_EDGES="$TMP/s/edges" STUB_TMP="$TMP/s" \
  STUB_RESOLVES="$TMP/s/resolves" STUB_CREATES="$TMP/s/creates" STUB_AGENTS="$AGENTS_DEFAULT"
# run_real -> one pass of the block against the store as it stands.
run_real() {
  : > "$TMP/calls"
  ( cd "$TMP"; unset GC_AGENT GC_BD_LIB
    PATH="$TMP/sbin:$PATH" CALLS_LOG="$TMP/calls" GC_RIG=gc-toolkit STUB_PACK="$TMP/srig" GC_RIG_ROOT="" GC_CITY_PATH="$TMP/nocity" \
      bash "$TMP/block.sh" > "$TMP/out" 2>&1 || true )
}
# The stuck-handoff gate's state, and the open human gates its own `blocks`
# edges reach, which is how the helper and every other reader finds them.
gate_status() { jq -r '.[] | select(.id == "tk-g-both") | .status' "$STUB_STORE"; }
open_gates_on() { PATH="$TMP/sbin:$PATH" gc bd dep list "$1" --type blocks --json \
  | jq -r '[ .[] | select(.issue_type == "gate" and .status != "closed") | .id ] | join(",")'; }

printf '[%s,%s,%s]' \
  '{"id":"tk-gone","issue_type":"task","title":"handoff","status":"closed","assignee":null,"updated_at":"'"$OLD1"'","metadata":{"branch":"polecat/tk-gone","merge_result":"merged"}}' \
  '{"id":"tk-still","issue_type":"task","title":"handoff","status":"open","assignee":"'"$REF"'","updated_at":"'"$OLD1"'","metadata":{"branch":"polecat/tk-still"}}' \
  '{"id":"tk-g-both","issue_type":"gate","await_type":"human","await_id":"witness-refinery-queue","status":"open","title":"stuck handoff","created_at":"2020-01-01T00:00:00Z"}' \
  > "$STUB_STORE"
printf 'tk-gone|blocks|tk-g-both\ntk-still|blocks|tk-g-both\n' > "$STUB_EDGES"
: > "$STUB_RESOLVES"; : > "$STUB_CREATES"

# Pass one: tk-gone has left, tk-still still sits stuck in the queue.
run_real
eq "$(cat "$STUB_RESOLVES")" "" "real helper: the shared gate is not resolved while tk-still is still in the queue"
eq "$(gate_status)" "open" "real helper: the shared gate stays open"
eq "$(open_gates_on tk-still)" "tk-g-both" "real helper: tk-still stays blocked by the gate"
eq "$(cat "$STUB_CREATES")" "" "real helper: tk-still's filing finds the gate it waits on and files no other"
eq "$(cat "$TMP/calls")" "" "real helper: no patrol finding is filed"
has "$(out)" "tk-gone is closed, but its gate tk-g-both also blocks tk-still, which is still in the queue" \
   "real helper: the kept gate is reported"
# A second pass with nothing changed changes nothing.
run_real
eq "$(cat "$STUB_RESOLVES")" "" "real helper: a second pass still leaves the shared gate open"

# Pass two: tk-still has merged too, so every bead the gate blocks has left.
jq -c 'map(if .id == "tk-still" then .status = "closed" | .assignee = null | .metadata.merge_result = "merged" else . end)' \
  "$STUB_STORE" > "$TMP/s/next.json" && mv "$TMP/s/next.json" "$STUB_STORE"
run_real
eq "$(grep -c . "$STUB_RESOLVES" || true)" "1" "real helper: the shared gate is resolved once both handoffs have left"
has "$(cat "$STUB_RESOLVES")" "tk-g-both|moot: Refinery handoff tk-gone is closed," \
   "real helper: it is resolved moot, with the departed handoff's reading"
eq "$(gate_status)" "closed" "real helper: the shared gate is closed"
eq "$(open_gates_on tk-still)" "" "real helper: tk-still is released once it has left"
eq "$(cat "$STUB_CREATES")" "" "real helper: the withdrawal files no gate"

echo
echo "refinery-stuck-handoff: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
