#!/usr/bin/env bash
# Hermetic test for the witness-patrol refinery queue nudge guard.
#
# The nudge is the check-refinery step's only channel for a real merge backlog.
# Sending it regardless of queue state costs the channel its meaning: a genuine
# backlog then arrives worded exactly like the empty-queue sends.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-refinery-queue-nudge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in '$1')" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in '$1')" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

BLOCK="$(awk '
  /# >>> refinery-queue-nudge/ {f=1; next}
  /# <<< refinery-queue-nudge/ {f=0}
  f' "$TOML")"

[ -n "$BLOCK" ] \
  && ok "block extracted between refinery-queue-nudge markers" \
  || bad "block extraction EMPTY — markers missing from $TOML"

has "$BLOCK" 'gc bd list' "the block measures the queue itself"
has "$BLOCK" 'gc session nudge' "the block owns the nudge"

# {{binding_prefix}} must be substituted exactly as the materializer does it.
render() { printf '%s\n' "$BLOCK" | sed 's|{{binding_prefix}}|gc-toolkit.|g'; }
render > "$TMP/block.sh"

bash -n "$TMP/block.sh" \
  && ok "extracted block is syntactically valid bash" \
  || bad "extracted block failed bash -n"

mkdir -p "$TMP/bin"
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

# run <script> <fixture-json> [stderr-noise] [list-rc] [shell-prelude]
#   -> stdout of the nudge log; the run's own transcript lands in $TMP/out.
run() {
  : > "$TMP/nudges"; : > "$TMP/lists"
  printf '%s' "$2" > "$TMP/queue.json"
  { printf '%s\n' "${5:-}"; cat "$1"; } > "$TMP/run.sh"
  QUEUE_FIXTURE="$TMP/queue.json" NUDGE_LOG="$TMP/nudges" LIST_LOG="$TMP/lists" \
  QUEUE_STDERR="${3:-}" GC_RIG="${GC_RIG_OVERRIDE-gc-toolkit}" LIST_RC="${4:-0}" \
    bash "$TMP/run.sh" > "$TMP/out" 2>&1 || true
  cat "$TMP/nudges"
}
out() { cat "$TMP/out"; }

TWO='[
  {"id":"tk-aaa","updated_at":"2026-08-24T09:00:00Z","title":"handoff one"},
  {"id":"tk-bbb","updated_at":"2026-08-26T11:00:00Z","title":"handoff two"}
]'

eq "$(run "$TMP/block.sh" '[]')" "" \
   "empty queue sends no nudge"

SENT="$(run "$TMP/block.sh" "$TWO")"
eq "$(printf '%s' "$SENT" | grep -c . || true)" "1" \
   "non-empty queue sends exactly one nudge"
has "$SENT" "gc-toolkit/gc-toolkit.refinery" "nudge is addressed to the rig's refinery"
has "$SENT" "2" "message carries the measured depth"
has "$SENT" "2026-08-24T09:00:00Z" "message carries the OLDEST bead's timestamp"
LISTED="$(cat "$TMP/lists")"
has "$LISTED" "--assignee=gc-toolkit/gc-toolkit.refinery" "the count comes from the refinery's own queue"
has "$LISTED" "--status=open" "the count comes from OPEN beads only"
has "$LISTED" "--limit=0" "the count is not truncated by a default page size"
hasnt "$SENT" "Work beads waiting for merge" \
   "message no longer asserts a backlog as a fixed phrase"

# A listing that did not parse measured nothing, so it may assert nothing.
eq "$(run "$TMP/block.sh" 'warning: config drift
[]')" "" \
   "unparseable listing sends no nudge"

# jq length counts an object's FIELDS, so an error body would otherwise read as
# a one-bead backlog and nudge about a bead that does not exist.
eq "$(run "$TMP/block.sh" '{"error":"store unavailable"}')" "" \
   "an error object is not counted as a queue of one"

UNRIGGED="$(GC_RIG_OVERRIDE= run "$TMP/block.sh" "$TWO")"
has "$UNRIGGED" "gc-toolkit.refinery" "unset GC_RIG still addresses the refinery"
hasnt "$UNRIGGED" "/gc-toolkit.refinery" "unset GC_RIG emits no leading slash"

render \
  | sed -e 's#^if \[ "$QUEUE_RC" -ne 0 \] || \[ -z "$DEPTH" \]; then#if false; then#' \
        -e 's#^elif \[ "$DEPTH" -eq 0 \]; then#elif false; then#' > "$TMP/unguarded.sh"
grep -q '^if false; then' "$TMP/unguarded.sh" && grep -q '^elif false; then' "$TMP/unguarded.sh" \
  && ok "mutant built — both guard lines matched" \
  || bad "mutant did not build — a guard line changed shape; update this test"
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

[ -n "$(run "$TMP/unguarded.sh" '' '' 1)" ] \
  && ok "control: unguarded, a failed listing DOES nudge (case 4 is live)" \
  || bad "control FAILED — failed listing is silent even unguarded, so case 4 proves nothing"

eq "$(run "$TMP/block.sh" '' '' 1)" "" \
   "a failed listing sends no nudge"
has "$(out)" "unreadable" "a failed listing reports why it is silent"
eq "$(run "$TMP/block.sh" 'null')" "" "a null listing sends no nudge"
eq "$(run "$TMP/block.sh" '')" "" "an empty listing sends no nudge"
eq "$(run "$TMP/block.sh" '[]')" "" "an empty queue sends no nudge"
has "$(out)" "queue empty" "an empty queue is reported apart from an unreadable one"

# The block is instruction text an agent runs, so it lands in whatever shell
# the caller has already set up — including a strict one.
for PRELUDE in 'set -e' 'set -euo pipefail'; do
  eq "$(run "$TMP/block.sh" '' '' 1 "$PRELUDE")" "" \
     "$PRELUDE: a failed listing sends no nudge"
  has "$(out)" "unreadable" "$PRELUDE: a failed listing still reaches the diagnostic"

  eq "$(run "$TMP/block.sh" 'warning: config drift
[]' '' 0 "$PRELUDE")" "" \
     "$PRELUDE: an unparseable listing sends no nudge"
  has "$(out)" "unreadable" "$PRELUDE: an unparseable listing still reaches the diagnostic"

  eq "$(run "$TMP/block.sh" '[]' '' 0 "$PRELUDE")" "" \
     "$PRELUDE: an empty queue sends no nudge"
  has "$(run "$TMP/block.sh" "$TWO" '' 0 "$PRELUDE")" "gc-toolkit.refinery" \
     "$PRELUDE: a real backlog still nudges"
done

# Reverted to a plain assignment, the capture takes the shell down with the
# listing, so the arms above never run.
render | sed -e 's#^if \(QUEUE=$(gc bd list [^)]*)\); then QUEUE_RC=0; else QUEUE_RC=$?; fi#\1#' \
  > "$TMP/plaincapture.sh"
grep -q '^QUEUE=$(gc bd list' "$TMP/plaincapture.sh" \
  && ok "mutant built — the rc-capturing line matched" \
  || bad "mutant did not build — the capture changed shape; update this test"
run "$TMP/plaincapture.sh" '' '' 1 'set -e; QUEUE_RC=0' >/dev/null
hasnt "$(out)" "unreadable" \
  "control: without the rc capture, set -e exits before the diagnostic (the strict-shell arms are live)"

# The listing and the nudge must read the same queue: gating on a second,
# separately-run listing is the ungated form wearing a condition.
eq "$(awk '
  /# >>> refinery-queue-nudge/ {inside = 1}
  /# <<< refinery-queue-nudge/ {inside = 0; next}
  !inside && /gc session nudge/ && /refinery/ {print FNR ": " $0}
' "$TOML")" "" "no refinery nudge outside the block markers"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'gc session nudge' || true)" "1" \
   "the block carries exactly one nudge"
eq "$(printf '%s\n' "$BLOCK" | grep -c 'gc bd list' || true)" "1" \
   "the block lists the queue exactly once"

# A TOML basic multi-line string rewrites a backslash, so the block has to stay
# free of them to survive the pour intact.
case "$BLOCK" in
  *'\'*) bad "block contains a backslash — the TOML \"\"\" string mangles it" ;;
  *)     ok "block is backslash-free" ;;
esac

echo
echo "refinery-queue-nudge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
