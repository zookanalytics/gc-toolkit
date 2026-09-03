#!/usr/bin/env bash
# Hermetic test for the patrol-wisp LEAK GUARDS of every patrolling agent:
# witness, deacon and refinery.
#
# THE LEAK: a mol-<agent>-patrol wisp that no query can see survives every
# reconcile pass and accumulates one row per interrupted pour. Three
# mechanisms feed it, and each has a guard exercised here:
#
#   1. POUR-THEN-ASSIGN IS NOT ATOMIC. `gc bd mol wisp` and `gc bd update
#      --assignee` are separate writes, so a session that dies in between
#      leaves a wisp owned by nobody.
#   2. AN --assignee-SCOPED RECONCILE CANNOT SEE THAT WISP. It matches no
#      query on this restart or any later one, so it is unreachable garbage.
#      Reconcile is by TITLE instead: `gc bd` is pinned to one store, and each
#      agent is the sole owner of its patrol-formula title within it.
#   3. A WISP IS AN EPHEMERAL MOLECULE. `--include-infra` is required or every
#      wisp query reads empty, and `--type=wisp` is not an issue type at all —
#      it errors. Either way the caller concludes "no wisp" and the row it was
#      looking for leaks.
#
# Two guards per agent, both executed here, extracted verbatim from the shipped
# instructions so the test cannot drift from what the agent actually reads:
#
#   - RECONCILE (agents/<agent>/prompt.template.md, `patrol-wisp-reconcile`) —
#     title-scoped, assignee-blind, ephemeral-aware collection.
#   - POUR (formulas/mol-<agent>-patrol.toml, `patrol-wisp-pour`) — a failed
#     assign rolls the pour back and refuses to burn the current wisp.
#
# No live city, Dolt, network, or wisps — only jq and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
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

# --- Stub `gc`. --------------------------------------------------------------
# Serves `gc bd list` from a fixture and records every `gc bd mol burn` /
# `gc bd update` so the assertions can see what a snippet DID, not just what it
# printed. Honours the same flags the real queries pass.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'STUB'
#!/usr/bin/env bash
# Fixture-backed stand-in for the parts of `gc` the snippets touch. Anything
# not matched below (e.g. `gc runtime drain-ack`) is a silent no-op.
set -u

# The issue types bd accepts. A wisp is stored as `molecule`; there is no
# `wisp` type, and asking for one is an ERROR, not an empty result. The stub
# refuses what bd refuses, so a query that could never work cannot pass this
# test by looking like "nothing found".
VALID_TYPES=" bug feature task epic chore decision agent convergence convoy event gate merge-request message molecule rig role session spec step "

case "${1:-} ${2:-}" in
  "bd list")
    status=all
    assignee=""   # empty = flag absent = no assignee filter
    type=""
    infra=false
    limit=0       # 0 = unlimited, as bd reads it
    for a in "$@"; do
      case "$a" in
        --status=*)      status="${a#--status=}" ;;
        --assignee=*)    assignee="${a#--assignee=}" ;;
        --type=*)        type="${a#--type=}" ;;
        --limit=*)       limit="${a#--limit=}" ;;
        --include-infra) infra=true ;;
      esac
    done
    if [ -n "$type" ]; then
      case "$VALID_TYPES" in
        *" $type "*) ;;
        *) echo "Error: invalid issue type \"$type\"" >&2; exit 1 ;;
      esac
    fi
    # `--assignee` and `--include-infra` are HONOURED here on purpose: they are
    # the flags whose presence and absence caused the leak, so the stub must
    # reproduce their filtering or a regressed query would silently still pass.
    jq -c --arg s "$status" --arg a "$assignee" --arg t "$type" \
          --argjson infra "$infra" --argjson lim "$limit" \
      '[ .[]
         | select($s == "all" or .status == $s)
         | select($a == "" or (.assignee // "") == $a)
         | select($t == "" or (.issue_type // "") == $t)
         | select($infra or ((.ephemeral // false) | not))
       ] | if $lim > 0 then .[0:$lim] else . end' "$GC_FIXTURE"
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

# --- Runners. ----------------------------------------------------------------
# Both read $AGENT_ID and the extracted snippet files the agent loop writes.

# run_reconcile <fixture-json> -> "<survivor>|<burned,ids>"
run_reconcile() {
  printf '%s' "$1" > "$TMP/fixture.json"
  # Clear both sinks: a snippet that dies before writing $TMP/wisp would
  # otherwise be scored against the previous agent's survivor.
  : > "$TMP/burned"; : > "$TMP/wisp"
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" GC_AGENT="$AGENT_ID"
    # shellcheck disable=SC1091
    . "$TMP/reconcile.sh"
    printf '%s' "$WISP" > "$TMP/wisp" )
  printf '%s|%s' "$(cat "$TMP/wisp")" "$(sort "$TMP/burned" | paste -sd, -)"
}

# run_pour <assign-fails> <pour-empty> <burn-fails> <gc-bead-id> [fixture] [script]
#   -> "<exit>|<burned,ids>|<updated,ids>"
run_pour() {
  : > "$TMP/burned"; : > "$TMP/updated"
  printf '%s' "${5:-[]}" > "$TMP/fixture.json"
  local script="${6:-$TMP/pour.sh}" rc=0
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" GC_AGENT="$AGENT_ID" \
           GC_BEAD_ID="${4:-}" \
           GC_ASSIGN_FAILS="${1:-0}" GC_POUR_EMPTY="${2:-0}" GC_BURN_FAILS="${3:-0}"
    bash "$script" >/dev/null 2>&1 ) || rc=$?
  printf '%s|%s|%s' "$rc" \
    "$(sort "$TMP/burned" | paste -sd, -)" "$(sort "$TMP/updated" | paste -sd, -)"
}

# --- Fixtures. ---------------------------------------------------------------
# @T@ is the agent's patrol title; fx substitutes it. Every wisp row carries the
# shape bd returns for one: issue_type `molecule`, ephemeral true.

# The exact live situation from the bug report.
# w-run   in_progress patrol wisp, owned      -> SURVIVOR (in_progress first)
# w-orph  open patrol wisp, NO assignee       -> the LEAK: must be BURNED, not
#                                                skipped as "not mine"
# w-other open molecule root, different title -> untouched (not ours to adopt
#                                                OR to burn)
FX_LEAK='[
  {"id":"w-run",   "status":"in_progress","title":"@T@","assignee":"@A@","issue_type":"molecule","ephemeral":true},
  {"id":"w-orph",  "status":"open",       "title":"@T@","assignee":"",   "issue_type":"molecule","ephemeral":true},
  {"id":"w-other", "status":"open",       "title":"mol-doc-keeper-drift-audit","assignee":"@A@","issue_type":"molecule","ephemeral":true}
]'
FX_ONLY_ORPHAN='[
  {"id":"w-orph","status":"open","title":"@T@","assignee":"","issue_type":"molecule","ephemeral":true}
]'
FX_NO_PATROL='[
  {"id":"w-other","status":"open","title":"mol-doc-keeper-drift-audit","assignee":"@A@","issue_type":"molecule","ephemeral":true}
]'
FX_SURPLUS='[
  {"id":"w-a","status":"in_progress","title":"@T@","assignee":"@A@","issue_type":"molecule","ephemeral":true},
  {"id":"w-b","status":"open",       "title":"@T@","assignee":"@A@","issue_type":"molecule","ephemeral":true},
  {"id":"w-c","status":"open",       "title":"@T@","assignee":"",   "issue_type":"molecule","ephemeral":true}
]'
# For the pour snippet that resolves the current wisp itself: w-cur is ours,
# w-orph is an unowned wisp of the same title, w-decoy is ours but not a patrol.
FX_CURRENT='[
  {"id":"w-orph", "status":"in_progress","title":"@T@","assignee":"",   "issue_type":"molecule","ephemeral":true},
  {"id":"w-decoy","status":"in_progress","title":"mol-doc-keeper-drift-audit","assignee":"@A@","issue_type":"molecule","ephemeral":true},
  {"id":"w-cur",  "status":"in_progress","title":"@T@","assignee":"@A@","issue_type":"molecule","ephemeral":true}
]'

fx() { local s="${1//@T@/$TITLE}"; printf '%s' "${s//@A@/$AGENT_ID}"; }

# --- Per-agent contracts. ----------------------------------------------------
# Fields: agent | expected happy-path pour result | does the pour snippet also
# resolve and burn the CURRENT wisp? The refinery does it in the same block; the
# witness and deacon burn theirs from a later formula step, so their snippet
# burns nothing on the happy path.
AGENTS=(
  "witness  0||w-new      no"
  "deacon   0||w-new      no"
  "refinery 0|w-cur|w-new yes"
)

for SPEC in "${AGENTS[@]}"; do
  read -r AGENT POUR_OK BURNS_CURRENT <<<"$SPEC"
  TITLE="mol-$AGENT-patrol"
  AGENT_ID="$AGENT-1"
  PROMPT="$ROOT/agents/$AGENT/prompt.template.md"
  TOML="$ROOT/formulas/$TITLE.toml"
  echo
  echo "== $AGENT =="

  RECONCILE="$(extract patrol-wisp-reconcile "$PROMPT")"
  POUR="$(extract patrol-wisp-pour "$TOML")"

  [ -n "$RECONCILE" ] \
    && ok "$AGENT: reconcile extracted between patrol-wisp-reconcile markers" \
    || bad "$AGENT: reconcile extraction EMPTY — markers missing from $PROMPT"
  [ -n "$POUR" ] \
    && ok "$AGENT: pour guard extracted between patrol-wisp-pour markers" \
    || bad "$AGENT: pour extraction EMPTY — markers missing from $TOML"

  printf '%s\n' "$RECONCILE" > "$TMP/reconcile.sh"
  printf '%s\n' "$POUR"      > "$TMP/pour.sh"
  # The snippets are read as instructions by an agent, but they must still be
  # runnable shell — a syntax error ships a broken instruction.
  bash -n "$TMP/reconcile.sh" \
    && ok "$AGENT: extracted reconcile is syntactically valid bash" \
    || bad "$AGENT: extracted reconcile failed bash -n"
  bash -n "$TMP/pour.sh" \
    && ok "$AGENT: extracted pour guard is syntactically valid bash" \
    || bad "$AGENT: extracted pour guard failed bash -n"

  # --- Reconcile. ------------------------------------------------------------
  eq "$(run_reconcile "$(fx "$FX_LEAK")")" "w-run|w-orph" \
     "$AGENT: REGRESSION: the unassigned orphan is collected and burned; the running wisp survives"

  # The orphan is collected even when it is the ONLY wisp left — the restart
  # case where the pouring session died before assigning and never came back.
  # Under an --assignee filter this returns nothing, the agent concludes "no
  # wisp", pours a fresh one, and leaks this row forever.
  eq "$(run_reconcile "$(fx "$FX_ONLY_ORPHAN")")" "w-orph|" \
     "$AGENT: REGRESSION: a lone unassigned orphan is ADOPTED as the wisp, not re-poured around"

  # Widening off --assignee must not widen off the title: an unrelated molecule
  # root assigned to the same agent is still neither adopted nor burned.
  eq "$(run_reconcile "$(fx "$FX_NO_PATROL")")" "|" \
     "$AGENT: an unrelated molecule root is neither adopted nor burned"

  eq "$(run_reconcile "$(fx "$FX_SURPLUS")")" "w-a|w-b,w-c" \
     "$AGENT: reconciles surplus to exactly one, preferring the in_progress wisp"

  eq "$(run_reconcile '[]')" "|" "$AGENT: empty store yields no wisp and no burn"

  # --- Pour guard. -----------------------------------------------------------
  eq "$(run_pour 0 0 0 w-cur)" "$POUR_OK" \
     "$AGENT: happy path: pours and assigns the new wisp"

  # THE CORE GUARD: a failed assign must roll the pour back and report failure,
  # so the current wisp is never burned. Leaking w-new here IS the bug.
  eq "$(run_pour 1 0 0 w-cur)" "1|w-new|w-new" \
     "$AGENT: REGRESSION: a failed assign rolls the poured wisp back, exits non-zero, and burns no current wisp"

  # A pour that yields no id must not be assigned, must not be burned, and must
  # still stop the current wisp from being burned.
  eq "$(run_pour 0 1 0 w-cur)" "1||" \
     "$AGENT: an empty pour exits non-zero without assigning or burning"

  # Rollback is best-effort: if the burn also fails, the guard still exits
  # non-zero. The stray is then the title-scoped reconcile's problem — which is
  # exactly why that half of the fix has to be assignee-blind.
  eq "$(run_pour 1 0 1 w-cur)" "1|w-new|w-new" \
     "$AGENT: a failed rollback burn still exits non-zero (reconcile is the backstop)"

  # --- Resolving the CURRENT wisp, for the snippet that burns it itself. ------
  if [ "$BURNS_CURRENT" = "yes" ]; then
    # GC_BEAD_ID is empty on every fresh session, so the fallback query is the
    # live path, not a spare. It must find OUR patrol wisp: not the unowned
    # same-title orphan (reconcile's job, not this step's), and not our
    # in-progress non-patrol molecule.
    eq "$(run_pour 0 0 0 "" "$(fx "$FX_CURRENT")")" "0|w-cur|w-new" \
       "$AGENT: REGRESSION: with GC_BEAD_ID unset the fallback resolves our own patrol wisp and burns it"

    # CONTROL, so the assertion above cannot pass for the wrong reason: put the
    # pre-fix query shape back and watch the same fixture leak. `--type=wisp` is
    # refused by bd, so the current wisp never resolves — the next wisp is
    # poured and assigned, and the old one is left behind. That is the leak.
    sed 's/--type=molecule --include-infra --limit=0/--type=wisp --limit=1/' \
      "$TMP/pour.sh" > "$TMP/pour-mutated.sh"
    if cmp -s "$TMP/pour.sh" "$TMP/pour-mutated.sh"; then
      bad "$AGENT: control did not mutate the fallback query — its shape changed, re-check the sed"
    else
      eq "$(run_pour 0 0 0 "" "$(fx "$FX_CURRENT")" "$TMP/pour-mutated.sh")" "1||w-new" \
         "$AGENT: CONTROL: the pre-fix --type=wisp fallback leaves the current wisp unburned"
    fi
  fi

  # --- Static guard: no reconcile query may re-acquire an --assignee filter. --
  # Nothing else in the pack locks these three invariants down, so they are
  # asserted here, over every fenced block in the prompt rather than only the
  # marked one: a wisp query that drifts outside the markers still leaks.
  BLOCK=$(awk '
    /^[[:space:]]*```/ {f = !f; next}
    f' "$PROMPT")
  Q=$(printf '%s\n' "$BLOCK" | grep -- "gc bd list" | grep -- "--type=molecule" || true)
  TOTAL=$(printf '%s\n' "$Q" | grep -c . || true)
  SCOPED=$(printf '%s\n' "$Q" | grep -c -- "--assignee" || true)
  TITLED=$(printf '%s\n' "$Q" | grep -cF -- "$TITLE" || true)
  INFRA=$(printf '%s\n' "$Q" | grep -c -- "--include-infra" || true)

  [ "${TOTAL:-0}" -gt 0 ] \
    && ok "$AGENT: prompt still contains wisp queries to check ($TOTAL)" \
    || bad "$AGENT: no wisp queries found in the prompt — extraction broke"
  eq "${SCOPED:-0}" "0" \
     "$AGENT: no wisp query filters on --assignee (an orphaned wisp must stay visible)"
  eq "${TITLED:-0}" "${TOTAL:-0}" "$AGENT: every wisp query is still scoped to $TITLE"
  eq "${INFRA:-0}"  "${TOTAL:-0}" "$AGENT: every wisp query still carries --include-infra"
done

echo
echo "patrol-wisp-reconcile: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
