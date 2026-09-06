#!/usr/bin/env bash
# Hermetic test for the witness-patrol refinery stuck-handoff escalation.
#
# check-refinery escalates ONLY a refinery handoff that has sat past the stuck
# bound. Transient churn (a fresh handoff, a rebase task the fix pool is
# working) and gating anchors (the cadence's own, carrying merge_result) must
# never escalate, and a false escalation here is the defect this block fixes. A
# count-nudge is gone: it went stale the moment the assignee set drained.
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
render() { printf '%s\n' "$BLOCK" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }
render > "$TMP/block.sh"

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
    # A failing listing writes nothing to stdout, the way the real one does.
    if [ "${LIST_RC:-0}" != "0" ]; then
      echo "gc bd list: store unavailable" >&2; exit "${LIST_RC}"
    fi
    [ -n "${QUEUE_STDERR:-}" ] && printf '%s\n' "$QUEUE_STDERR" >&2
    cat "$QUEUE_FIXTURE"
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

# run <fixture-json> [stderr-noise] [list-rc] [shell-prelude] -> the escalate log.
# Runs from a non-repo cwd so the block's git-toplevel probe finds nothing and
# GC_RIG_ROOT (the stub) wins.
run() {
  : > "$TMP/esc"; : > "$TMP/lists"
  printf '%s' "$1" > "$TMP/queue.json"
  { printf '%s\n' "${4:-}"; cat "$TMP/block.sh"; } > "$TMP/run.sh"
  ( cd "$TMP"
    QUEUE_FIXTURE="$TMP/queue.json" ESC_LOG="$TMP/esc" LIST_LOG="$TMP/lists" \
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

# Nothing to assert on a broken or empty read.
eq "$(run '[]')" "" "an empty queue escalates nothing"
has "$(out)" "no stuck handoffs" "an empty queue is reported apart from an unreadable one"
eq "$(run 'warning: config drift
[]')" "" "an unparseable listing escalates nothing"
eq "$(run '{"error":"store unavailable"}')" "" "an error object escalates nothing"
eq "$(run 'null')" "" "a null listing escalates nothing"
eq "$(run '' '' 1)" "" "a failed listing escalates nothing"
has "$(out)" "unreadable" "a failed listing reports why it is silent"

# unset GC_RIG still names the refinery in the message, with no leading slash.
URIG="$(GC_RIG_OVERRIDE= run "$STUCK_ONE")"
has "$URIG" "gc-toolkit.refinery" "unset GC_RIG still names the refinery"
hasnt "$URIG" "/gc-toolkit.refinery" "unset GC_RIG emits no leading slash"

# The block is instruction text an agent runs, so it lands in whatever shell the
# caller has already set up, including a strict one.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  has "$(run "$STUCK_ONE" '' 0 "$PRELUDE")" "--subject tk-stuck" \
     "$PRELUDE: a stuck handoff still escalates"
  eq "$(run '' '' 1 "$PRELUDE")" "" \
     "$PRELUDE: a failed listing escalates nothing"
  has "$(out)" "unreadable" "$PRELUDE: a failed listing still reaches the diagnostic"
  eq "$(run '[]' '' 0 "$PRELUDE")" "" \
     "$PRELUDE: an empty queue escalates nothing"
done

# The read and the escalation share one queue: exactly one bd list, no nudge.
eq "$(printf '%s\n' "$BLOCK" | grep -c 'gc bd list' || true)" "1" \
   "the block reads the queue exactly once"
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

echo
echo "refinery-stuck-escalate: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
