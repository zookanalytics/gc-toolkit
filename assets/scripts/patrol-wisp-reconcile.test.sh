#!/usr/bin/env bash
# Hermetic test for the witness patrol-wisp LEAK GUARDS (tk-fj56a).
#
# THE BUG: an UNASSIGNED mol-witness-patrol wisp leaks and survives every
# reconcile pass indefinitely (one found live at ~3.5h old, 2026-07-28, only by
# an unscoped title sweep run as a positive control). Two mechanisms, one leak:
#
#   1. POUR-THEN-ASSIGN IS NOT ATOMIC. `gc bd mol wisp` and `gc bd update
#      --assignee` are separate writes. A session that dies, is recycled, or
#      fails the update in between leaves a wisp owned by nobody.
#   2. EVERY RECONCILE QUERY WAS --assignee-SCOPED. An unowned wisp matches
#      none of them, on this restart or any future one, so it is unreachable
#      garbage that accumulates one row per interrupted pour.
#
# This is DISTINCT from the ephemeral-blindness bug (tk-1waw2): --include-infra
# fixes the infra-visibility axis, this fixes the assignee axis. Both queries
# had to widen for the leak to close.
#
# THE FIX, in two halves, both exercised here:
#   - RECONCILE BY TITLE, not assignee (agents/witness/prompt.template.md, `patrol-wisp-reconcile`)
#     so an orphaned wisp is visible and collectable.
#   - GUARD THE POUR (formulas/mol-witness-patrol.toml, `patrol-wisp-pour`) so a
#     failed assign rolls the pour back and refuses to burn the current wisp,
#     rather than leaking the new one and dropping the loop.
#
# The test EXECUTES both snippets extracted verbatim from the shipped
# instructions, against a stub `gc`, so it cannot drift from what the witness
# actually reads. No live city, Dolt, network, or wisps — only jq and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PROMPT="$ROOT/agents/witness/prompt.template.md"
TOML="$ROOT/formulas/mol-witness-patrol.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# extract <marker> <file> — the lines between the markers, exclusive. If the
# markers or the snippet are removed/renamed, extraction yields nothing and the
# checks below fail loudly: the guard cannot silently disappear.
extract() {
  awk -v m="$1" '
    $0 ~ ("# >>> " m "$") {f=1; next}
    $0 ~ ("# <<< " m "$") {f=0}
    f' "$2"
}

RECONCILE="$(extract patrol-wisp-reconcile "$PROMPT")"
POUR="$(extract patrol-wisp-pour "$TOML")"

[ -n "$RECONCILE" ] \
  && ok "reconcile extracted between patrol-wisp-reconcile markers" \
  || bad "reconcile extraction EMPTY — markers missing from $PROMPT"
[ -n "$POUR" ] \
  && ok "pour guard extracted between patrol-wisp-pour markers" \
  || bad "pour extraction EMPTY — markers missing from $TOML"

# --- Stub `gc`. --------------------------------------------------------------
# Serves `gc bd list` from a fixture and records every `gc bd mol burn` /
# `gc bd update` so the assertions can see what the snippet DID, not just what
# it printed. Honours the same flags the real reconcile passes.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Fixture-backed stand-in for the parts of `gc` the snippets touch. Anything
# not matched below (e.g. the fallback's closing `gc hook`) is a silent no-op.
set -u
case "${1:-} ${2:-}" in
  "bd list")
    status=all
    assignee=""   # empty = flag absent = no assignee filter
    type=""
    infra=0
    for a in "$@"; do
      case "$a" in
        --status=*)      status="${a#--status=}" ;;
        --assignee=*)    assignee="${a#--assignee=}" ;;
        --type=*)        type="${a#--type=}" ;;
        --include-infra) infra=1 ;;
      esac
    done
    # An unknown --type is REFUSED the way the CLI refuses it: the diagnostic
    # goes to stderr, stdout stays EMPTY, and the exit is non-zero. A caller
    # piping into `jq -r '.[0].id // empty'` reads that as "no wisp" and never
    # sees the error, so a stub that accepted `wisp` would hide a dead path.
    case "$type" in
      ""|bug|feature|task|epic|chore|decision|agent|convergence|convoy|event|gate|merge-request|message|molecule|rig|role|session|spec|step) ;;
      *) echo "Error: invalid issue type \"$type\"" >&2; exit 1 ;;
    esac
    # Wisps are molecule roots, which are infra: without --include-infra the
    # real CLI returns none of them, in JSON mode as well as text mode. Every
    # row in these fixtures is a molecule root, so hiding infra empties the
    # whole result.
    [ "$infra" = "1" ] || { echo '[]'; exit 0; }
    # `--assignee` is HONOURED here on purpose: it is the flag whose presence
    # caused the leak, so the stub must reproduce its filtering or a regressed
    # query would silently still pass this test.
    jq -c --arg s "$status" --arg a "$assignee" \
      '[ .[]
         | select(.status == $s)
         | select($a == "" or (.assignee // "") == $a) ]' "$GC_FIXTURE"
    ;;
  "bd mol")
    # gc bd mol burn <id> --force
    if [ "${3:-}" = "burn" ]; then
      echo "$4" >> "$GC_BURNED"
      [ "${GC_BURN_FAILS:-0}" = "1" ] && exit 1
      exit 0
    fi
    # gc bd mol wisp <formula> --root-only ... --json
    if [ "${3:-}" = "wisp" ]; then
      [ "${GC_POUR_EMPTY:-0}" = "1" ] && { echo '{}'; exit 0; }
      echo '{"new_epic_id":"w-new"}'
      exit 0
    fi
    ;;
  "bd update")
    echo "$3" >> "$GC_UPDATED"
    # Fail every update (GC_ASSIGN_FAILS) or just one target id
    # (GC_ASSIGN_FAILS_ID) — the latter isolates "the claim failed but a fresh
    # pour is still assignable" from "every write is failing".
    [ "${GC_ASSIGN_FAILS:-0}" = "1" ] && exit 1
    [ "$3" = "${GC_ASSIGN_FAILS_ID:-}" ] && exit 1
    exit 0
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gc"

printf '%s\n' "$RECONCILE" > "$TMP/reconcile.sh"
printf '%s\n' "$POUR"      > "$TMP/pour.sh"
# The snippets are read as instructions by an agent, but they must still be
# runnable shell — a syntax error ships a broken instruction.
bash -n "$TMP/reconcile.sh" \
  && ok "extracted reconcile is syntactically valid bash" \
  || bad "extracted reconcile failed bash -n"
bash -n "$TMP/pour.sh" \
  && ok "extracted pour guard is syntactically valid bash" \
  || bad "extracted pour guard failed bash -n"

# run_reconcile <fixture-json> -> "<survivor>|<burned,ids>"
run_reconcile() {
  printf '%s' "$1" > "$TMP/fixture.json"
  : > "$TMP/burned"
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" GC_AGENT="witness-1"
    # shellcheck disable=SC1091
    . "$TMP/reconcile.sh"
    printf '%s' "$WISP" > "$TMP/wisp" )
  printf '%s|%s' "$(cat "$TMP/wisp")" "$(sort "$TMP/burned" | paste -sd, -)"
}

# --- Fixture: the exact live situation from the bug report. -------------------
# w-run   in_progress patrol wisp, owned            -> SURVIVOR (in_progress first)
# w-orph  open patrol wisp, NO assignee             -> the LEAK: must be BURNED,
#                                                      not skipped as "not mine"
# w-other open molecule root, different title       -> untouched (not ours to
#                                                      adopt OR to burn)
LEAK='[
  {"id":"w-run",   "status":"in_progress","title":"mol-witness-patrol","assignee":"witness-1"},
  {"id":"w-orph",  "status":"open",       "title":"mol-witness-patrol","assignee":""},
  {"id":"w-other", "status":"open",       "title":"mol-doc-keeper-drift-audit","assignee":"witness-1"}
]'
eq "$(run_reconcile "$LEAK")" "w-run|w-orph" \
   "REGRESSION: the unassigned orphan is collected and burned; the running wisp survives"

# The orphan is collected even when it is the ONLY wisp left — the restart case
# where the pouring session died before assigning and never came back. Under the
# old --assignee filter this returned nothing, the agent concluded "no wisp",
# poured a fresh one, and leaked this row forever.
ONLY_ORPHAN='[
  {"id":"w-orph","status":"open","title":"mol-witness-patrol","assignee":""}
]'
eq "$(run_reconcile "$ONLY_ORPHAN")" "w-orph|" \
   "REGRESSION: a lone unassigned orphan is ADOPTED as the wisp, not re-poured around"

# Widening off --assignee must not widen off the title: an unrelated molecule
# root assigned to the same agent is still neither adopted nor burned.
NO_PATROL='[
  {"id":"w-other","status":"open","title":"mol-doc-keeper-drift-audit","assignee":"witness-1"}
]'
eq "$(run_reconcile "$NO_PATROL")" "|" \
   "an unrelated molecule root is neither adopted nor burned"

# Surplus reconciles to exactly one, and everything else burns.
SURPLUS='[
  {"id":"w-a","status":"in_progress","title":"mol-witness-patrol","assignee":"witness-1"},
  {"id":"w-b","status":"open",       "title":"mol-witness-patrol","assignee":"witness-1"},
  {"id":"w-c","status":"open",       "title":"mol-witness-patrol","assignee":""}
]'
eq "$(run_reconcile "$SURPLUS")" "w-a|w-b,w-c" \
   "reconciles surplus to exactly one, preferring the in_progress wisp"

eq "$(run_reconcile '[]')" "|" "empty store yields no wisp and no burn"

# --- The pour guard. ---------------------------------------------------------
# run_pour -> "<exit>|<burned,ids>|<updated,ids>"; env flags drive the failure.
run_pour() {
  : > "$TMP/burned"; : > "$TMP/updated"
  local rc=0
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" GC_AGENT="witness-1" \
           GC_ASSIGN_FAILS="${1:-0}" GC_POUR_EMPTY="${2:-0}" GC_BURN_FAILS="${3:-0}"
    bash "$TMP/pour.sh" >/dev/null 2>&1 ) || rc=$?
  printf '%s|%s|%s' "$rc" \
    "$(sort "$TMP/burned" | paste -sd, -)" "$(sort "$TMP/updated" | paste -sd, -)"
}

eq "$(run_pour 0 0 0)" "0||w-new" \
   "happy path: pours, assigns the new wisp, burns nothing (the caller burns the current one)"

# THE CORE GUARD: a failed assign must roll the pour back and report failure, so
# the caller never reaches its burn step. Leaking w-new here IS the bug.
eq "$(run_pour 1 0 0)" "1|w-new|w-new" \
   "REGRESSION: a failed assign rolls the poured wisp back and exits non-zero (caller must not burn)"

# A pour that yields no id must not be assigned, must not be burned, and must
# still stop the caller from burning.
eq "$(run_pour 0 1 0)" "1||" \
   "an empty pour exits non-zero without assigning or burning"

# Rollback is best-effort: if the burn also fails, the guard still exits
# non-zero. The stray is then the title-scoped reconcile's problem — which is
# exactly why that half of the fix has to be assignee-blind.
eq "$(run_pour 1 0 1)" "1|w-new|w-new" \
   "a failed rollback burn still exits non-zero (reconcile is the backstop)"

# --- Static guard: no reconcile query may re-acquire an --assignee filter. ----
# Staying assignee-blind keeps an orphaned patrol wisp visible; the checks below
# hold the --include-infra and title-scope invariants on the same queries.
WITNESS_BLOCK=$(awk '
  /^[[:space:]]*```/ {f = !f; next}
  f' "$PROMPT")
SCOPED=$(printf '%s\n' "$WITNESS_BLOCK" \
  | grep -- "gc bd list" | grep -- "--type=molecule" | grep -c -- "--assignee" || true)
eq "${SCOPED:-0}" "0" \
   "no witness wisp query filters on --assignee (an orphaned wisp must stay visible)"

# And every one of them still carries the two invariants it had before, so this
# fix cannot be read as licence to drop them.
TOTAL=$(printf '%s\n' "$WITNESS_BLOCK" | grep -- "gc bd list" | grep -c -- "--type=molecule" || true)
TITLED=$(printf '%s\n' "$WITNESS_BLOCK" \
  | grep -- "gc bd list" | grep -- "--type=molecule" | grep -cF -- "mol-witness-patrol" || true)
INFRA=$(printf '%s\n' "$WITNESS_BLOCK" \
  | grep -- "gc bd list" | grep -- "--type=molecule" | grep -c -- "--include-infra" || true)
[ "${TOTAL:-0}" -gt 0 ] \
  && ok "witness block still contains wisp queries to check ($TOTAL)" \
  || bad "no wisp queries found in the witness block — extraction broke"
eq "${TITLED:-0}" "${TOTAL:-0}" "every wisp query is still scoped to mol-witness-patrol"
eq "${INFRA:-0}"  "${TOTAL:-0}" "every wisp query still carries --include-infra"

# --- The refinery's current-wisp fallback. -----------------------------------
# next-iteration resolves the wisp it is about to burn from $GC_BEAD_ID, and
# falls back to a store query when that is unset. The fallback runs BEFORE the
# pour, so an empty result is not ambiguity about which of two wisps is
# current: it means the step pours and assigns NEXT, then refuses to burn, and
# two live wisps are left behind. The query must therefore actually resolve.
PATROL="$ROOT/formulas/mol-refinery-patrol.toml"
CURWISP="$(extract patrol-current-wisp "$PATROL")"

[ -n "$CURWISP" ] \
  && ok "current-wisp fallback extracted between patrol-current-wisp markers" \
  || bad "current-wisp extraction EMPTY — markers missing from $PATROL"

printf '%s\n' "$CURWISP" > "$TMP/curwisp.sh"
bash -n "$TMP/curwisp.sh" \
  && ok "extracted current-wisp fallback is syntactically valid bash" \
  || bad "extracted current-wisp fallback failed bash -n"

# run_curwisp <fixture-json> <GC_BEAD_ID> [script] -> the resolved CURRENT_WISP
run_curwisp() {
  printf '%s' "$1" > "$TMP/fixture.json"
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" \
           GC_AGENT="refinery-1" GC_BEAD_ID="$2"
    # shellcheck disable=SC1091
    . "${3:-$TMP/curwisp.sh}" 2>/dev/null
    printf '%s' "${CURRENT_WISP:-}" )
}

# w-run is the wisp being executed; w-doc is another molecule the same agent
# holds, which the title scope must exclude.
REFINERY_LIVE='[
  {"id":"w-run","status":"in_progress","title":"mol-refinery-patrol","assignee":"refinery-1"},
  {"id":"w-doc","status":"in_progress","title":"mol-doc-keeper-drift-audit","assignee":"refinery-1"}
]'

eq "$(run_curwisp "$REFINERY_LIVE" "")" "w-run" \
   "REGRESSION: with GC_BEAD_ID unset the fallback resolves the in_progress patrol wisp"
eq "$(run_curwisp "$REFINERY_LIVE" "w-env")" "w-env" \
   "GC_BEAD_ID wins when set, without consulting the store"
eq "$(run_curwisp '[{"id":"w-doc","status":"in_progress","title":"mol-doc-keeper-drift-audit","assignee":"refinery-1"}]' "")" "" \
   "an unrelated in_progress molecule is not mistaken for the patrol wisp"

# Two controls. Each removes one half of the fix and must yield nothing against
# the SAME fixture the assertion above resolves — if either ever returns w-run,
# the stub has stopped modelling the CLI and the assertion proves nothing.
sed 's/--type=molecule --include-infra/--type=wisp/' "$TMP/curwisp.sh" > "$TMP/curwisp-wisptype.sh"
eq "$(run_curwisp "$REFINERY_LIVE" "" "$TMP/curwisp-wisptype.sh")" "" \
   "CONTROL: --type=wisp is refused, so the fallback resolves nothing"
sed 's/ --include-infra//' "$TMP/curwisp.sh" > "$TMP/curwisp-noinfra.sh"
eq "$(run_curwisp "$REFINERY_LIVE" "" "$TMP/curwisp-noinfra.sh")" "" \
   "CONTROL: dropping --include-infra hides the wisp, JSON mode included"

# --- Static guard: the refused type filter must not return anywhere. ---------
# `wisp` is not an issue type. Every use of it is a query that can only ever
# read empty, and each one is swallowed by the `// empty` on the other side of
# the pipe, so nothing reports it. Sweep the two trees that carry agent-run
# shell: the formulas and the prompt templates.
for d in formulas agents; do
  [ -d "$ROOT/$d" ] \
    && ok "sweep target $d/ exists" \
    || bad "sweep target $d/ is missing — the sweep below would pass vacuously"
done
STRAY=$(grep -rl -- '--type=wisp' "$ROOT/formulas" "$ROOT/agents" 2>/dev/null \
  | sed "s|^$ROOT/||" | sort | paste -sd, - || true)
eq "${STRAY:-}" "" "no --type=wisp survives under formulas/ or agents/"

echo
echo "patrol-wisp-reconcile: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
