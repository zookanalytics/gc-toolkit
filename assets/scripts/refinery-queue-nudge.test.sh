#!/usr/bin/env bash
# Hermetic test for the witness-patrol REFINERY QUEUE NUDGE guard.
#
# THE GUARDRAIL: mol-witness-patrol's check-refinery step nudges the refinery
# only when the queue it just listed is non-empty, and the nudge reports the
# count it measured. The nudge is the step's only channel for a real merge
# backlog; sending it on a schedule regardless of queue state costs that
# channel its meaning, because a genuine backlog then arrives worded exactly
# like the empty-queue sends.
#
# The guard was prose ("Nudge if needed") until a formula rewrite dropped it,
# which is why it is executable here: this test EXECUTES the real block
# extracted verbatim from the formula (between the `refinery-queue-nudge`
# markers), so it cannot drift from the shipped instruction.
#
# No live city, Dolt, network, or sessions — only jq, bash and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in '$1')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# --- Extract the REAL block from the formula. --------------------------------
# If the markers or the guard are removed/renamed, extraction yields nothing and
# the check below fails loudly — the guardrail cannot silently disappear again.
BLOCK="$(awk '
  /# >>> refinery-queue-nudge/ {f=1; next}
  /# <<< refinery-queue-nudge/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between refinery-queue-nudge markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

# The listing and the nudge must live in ONE block: a nudge that cannot see the
# count it asserts is the defect this guard exists to prevent.
has "$BLOCK" 'gc bd list' "the block measures the queue itself"
has "$BLOCK" 'gc session nudge' "the block owns the nudge"

# {{binding_prefix}} is substituted the way the materializer does.
render() { printf '%s\n' "$BLOCK" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }
render > "$TMP/block.sh"

bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

# --- Stub the city. ----------------------------------------------------------
# `gc bd list` replays a fixture; `gc session nudge` records target + message.
# The stub REFUSES a listing that is not asked for as JSON, so an edit that
# drops --json fails here instead of silently parsing prose.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "bd list")
    printf '%s\n' "$*" >> "$LIST_LOG"
    case "$*" in *--json*) ;; *) echo "gc bd list called without --json" >&2; exit 64 ;; esac
    [ -n "${QUEUE_STDERR:-}" ] && printf '%s\n' "$QUEUE_STDERR" >&2
    cat "$QUEUE_FIXTURE"
    ;;
  "session nudge")
    shift 2
    printf '%s\t%s\n' "$1" "$2" >> "$NUDGE_LOG"
    ;;
  *)
    echo "unexpected gc invocation: $*" >&2; exit 99 ;;
esac
STUB
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# run <script> <fixture-json> [stderr-noise] -> stdout of the nudge log
run() {
  : > "$TMP/nudges"; : > "$TMP/lists"
  printf '%s' "$2" > "$TMP/queue.json"
  QUEUE_FIXTURE="$TMP/queue.json" NUDGE_LOG="$TMP/nudges" LIST_LOG="$TMP/lists" \
  QUEUE_STDERR="${3:-}" GC_RIG="${GC_RIG_OVERRIDE-gc-toolkit}" \
    bash "$1" >/dev/null 2>&1 || true
  cat "$TMP/nudges"
}

TWO='[
  {"id":"tk-aaa","updated_at":"2026-08-24T09:00:00Z","title":"handoff one"},
  {"id":"tk-bbb","updated_at":"2026-08-26T11:00:00Z","title":"handoff two"}
]'

# --- 1. Empty queue sends NOTHING. -------------------------------------------
eq "$(run "$TMP/block.sh" '[]')" "" \
   "empty queue sends no nudge"

# --- 2. A non-empty queue sends exactly one nudge that carries the count. ----
SENT="$(run "$TMP/block.sh" "$TWO")"
eq "$(printf '%s' "$SENT" | grep -c . || true)" "1" \
   "non-empty queue sends exactly one nudge"
has "$SENT" "gc-toolkit/gc-toolkit.refinery" "nudge is addressed to the rig's refinery"
has "$SENT" "2" "message carries the measured depth"
has "$SENT" "2026-08-24T09:00:00Z" "message carries the OLDEST bead's timestamp"
# The count only describes a backlog if the listing it came from is the
# refinery's open queue and nothing wider.
LISTED="$(cat "$TMP/lists")"
has "$LISTED" "--assignee=gc-toolkit/gc-toolkit.refinery" "the count comes from the refinery's own queue"
has "$LISTED" "--status=open" "the count comes from OPEN beads only"
has "$LISTED" "--limit=0" "the count is not truncated by a default page size"
hasnt "$SENT" "Work beads waiting for merge" \
   "message no longer asserts a backlog as a fixed phrase"

# --- 3. An unparseable listing is not a count of zero, and not a backlog. ----
# stdout polluted with a warning ahead of the JSON: nothing was measured, so
# nothing may be asserted.
eq "$(run "$TMP/block.sh" 'warning: config drift
[]')" "" \
   "unparseable listing sends no nudge"

# --- 3b. A JSON body that is not a bead array is not a depth. ----------------
# `jq length` counts an object's FIELDS, so an error body would otherwise read
# as a one-bead backlog and send a nudge naming a bead that does not exist.
eq "$(run "$TMP/block.sh" '{"error":"store unavailable"}')" "" \
   "an error object is not counted as a queue of one"

# --- 4. Target address follows GC_RIG. ---------------------------------------
# Unbound rig: the address degrades to the bare prefixed identity, no leading /.
UNRIGGED="$(GC_RIG_OVERRIDE= run "$TMP/block.sh" "$TWO")"
has "$UNRIGGED" "gc-toolkit.refinery" "unset GC_RIG still addresses the refinery"
hasnt "$UNRIGGED" "/gc-toolkit.refinery" "unset GC_RIG emits no leading slash"

# --- 5. MUTATE THE GUARD. ----------------------------------------------------
# Cases 1 and 3 only prove something if removing the condition makes them fail.
# There is exactly one condition, so replacing it with `true` must flip BOTH; a
# mutant that stays silent means those assertions pass for an unrelated reason.
render | sed -e 's|^if \[ "$DEPTH" -gt 0 \]; then|if true; then|' > "$TMP/unguarded.sh"
grep -q '^if true; then' "$TMP/unguarded.sh" \
  && ok "mutant built — the guard line matched" \
  || bad "mutant did not build — the guard line changed shape; update this test"
bash -n "$TMP/unguarded.sh" 2>/dev/null \
  && ok "mutant (guard removed) is valid bash" \
  || bad "mutant failed bash -n"
[ -n "$(run "$TMP/unguarded.sh" '[]')" ] \
  && ok "control: unguarded, an empty queue DOES nudge (case 1 is live)" \
  || bad "control FAILED — empty queue is silent even unguarded, so case 1 proves nothing"
[ -n "$(run "$TMP/unguarded.sh" 'warning: config drift
[]')" ] \
  && ok "control: unguarded, an unparseable listing DOES nudge (case 3 is live)" \
  || bad "control FAILED — unparseable listing is silent even unguarded, so case 3 proves nothing"
[ -n "$(run "$TMP/unguarded.sh" '{"error":"store unavailable"}')" ] \
  && ok "control: unguarded, an error object DOES nudge (case 3b is live)" \
  || bad "control FAILED — error object is silent even unguarded, so case 3b proves nothing"

echo
echo "refinery-queue-nudge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
