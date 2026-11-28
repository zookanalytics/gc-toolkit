#!/usr/bin/env bash
# Hermetic test for the patrol-wisp LEAK GUARD of the refinery, the one agent
# that still reconciles a patrol wisp.
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
#      Reconcile stays assignee-BLIND and matches by TITLE. The per-rig
#      refinery then narrows to THIS rig: several rigs run this
#      pack and pour the same patrol title into one shared store, so title
#      alone collides across rigs. A wisp is this rig's when its assignee
#      segment or pour-stamped gc.rig names this rig, or when it names no rig
#      yet (a fresh orphan); one naming another rig is left for that rig.
#   3. A WISP IS AN EPHEMERAL MOLECULE. `--include-infra` is required or every
#      wisp query reads empty, and `--type=wisp` is not an issue type at all —
#      it errors. Either way the caller concludes "no wisp" and the row it was
#      looking for leaks.
#
# The guard is the RECONCILE (agents/refinery/prompt.template.md,
# `patrol-wisp-reconcile`), extracted verbatim from the shipped instructions so
# the test cannot drift from what the agent actually reads: title-scoped,
# rig-scoped, assignee-blind, ephemeral-aware collection. The refinery's pour is
# no block of text but a script, `refinery-patrol.sh next`, whose own suite
# (refinery-patrol.test.sh) runs its guard.
#
# No live city, Dolt, network, or wisps — only jq and a tmpdir.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-patrol-wisp-reconcile-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }

# Several rigs run this pack and share one bead store. The test drives the
# reconcile as THIS_RIG and plants a foreign OTHER_RIG wisp to prove the sweep
# leaves it be.
THIS_RIG="rig-a"
OTHER_RIG="rig-b"

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
{ printf '#!%s\n' "${BASH:-/usr/bin/env bash}"; cat; } > "$TMP/bin/gc" <<'STUB'
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
    store="$GC_FIXTURE"
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
       ] | if $lim > 0 then .[0:$lim] else . end' "$store"
    ;;
  "bd mol")
    # gc bd mol burn <id> --force
    if [ "${3:-}" = "burn" ]; then
      echo "$4" >> "$GC_BURNED"
      [ "${GC_BURN_FAILS:-0}" = "1" ] && exit 1
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

# --- Runner. -----------------------------------------------------------------
# It reads $AGENT_ID and the extracted snippet file the agent loop writes. Each
# run sets GC_CITY_PATH, as every session's environment does.

# run_reconcile <fixture-json> -> "<survivor>|<burned,ids>"
run_reconcile() {
  printf '%s' "$1" > "$TMP/fixture.json"
  local script="${2:-$TMP/reconcile.sh}"
  # Clear both sinks: a snippet that dies before writing $TMP/wisp would
  # otherwise be scored against the previous agent's survivor.
  : > "$TMP/burned"; : > "$TMP/wisp"
  ( export PATH="$TMP/bin:$PATH" GC_FIXTURE="$TMP/fixture.json" \
           GC_BURNED="$TMP/burned" GC_UPDATED="$TMP/updated" GC_AGENT="$AGENT_ID" \
           GC_RIG="$AGENT_RIG" GC_CITY_PATH="/city"
    # shellcheck disable=SC1090,SC1091
    . "$script"
    printf '%s' "$WISP" > "$TMP/wisp" )
  printf '%s|%s' "$(cat "$TMP/wisp")" "$(sort "$TMP/burned" | paste -sd, -)"
}


# --- Fixtures. ---------------------------------------------------------------
# fx substitutes the placeholders: @T@ patrol title, @A@ this rig's agent
# address, @O@ a foreign agent address, @R@/@X@ this/other rig name. Every wisp
# row carries the shape bd returns for one: issue_type `molecule`, ephemeral true.

# The exact live situation from the bug report. created_at orders the sweep:
# the survivor is the NEWEST pour, since a cycle pours its successor after it.
# w-run   in_progress patrol wisp, owned      -> SURVIVOR (newest of ours)
# w-orph  open patrol wisp, NO assignee       -> the LEAK: must be BURNED, not
#                                                skipped as "not mine"
# w-other open molecule root, different title -> untouched (not ours to adopt
#                                                OR to burn) even though it is
#                                                newest — the title filter runs
#                                                before the recency pick
FX_LEAK='[
  {"id":"w-run",   "status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-orph",  "status":"open",       "title":"@T@","assignee":"",   "created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-other", "status":"open",       "title":"mol-doc-keeper-drift-audit","assignee":"@A@","created_at":"2026-09-18T03:09:00Z","issue_type":"molecule","ephemeral":true}
]'
FX_ONLY_ORPHAN='[
  {"id":"w-orph","status":"open","title":"@T@","assignee":"","created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true}
]'
FX_NO_PATROL='[
  {"id":"w-other","status":"open","title":"mol-doc-keeper-drift-audit","assignee":"@A@","created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true}
]'
# Surplus reduces to exactly one — the newest pour (w-a) — and the older wisps
# are burned regardless of status.
FX_SURPLUS='[
  {"id":"w-a","status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:09:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-b","status":"open",       "title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-c","status":"open",       "title":"@T@","assignee":"",   "created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true}
]'
# The reported failure: a completed cycle awaiting burn (w-done, in_progress,
# older) coexists with the fresh successor it poured (w-fresh, open, newer).
# Adopt the successor and burn the completed cycle, never the reverse.
FX_COMPLETED_SUCCESSOR='[
  {"id":"w-done", "status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-fresh","status":"open",       "title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true}
]'
# A partial reconcile can leave BOTH the completed cycle and its successor
# in_progress (the successor was adopted, the completed one never burned).
# created_at still separates them: adopt the newer, burn the older.
FX_TWO_INPROGRESS='[
  {"id":"w-stale","status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-live", "status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true}
]'
# Cross-rig: several rigs pour the same title into one shared store. A foreign
# rig's wisp — assignee names @O@ — must be neither adopted as the survivor nor
# burned as surplus; only this rig's wisps (w-mine, w-orph) are reconciled.
# w-foreign is newest of the three, to prove the rig filter runs before the
# recency pick.
FX_CROSS_RIG='[
  {"id":"w-foreign","status":"in_progress","title":"@T@","assignee":"@O@","created_at":"2026-09-18T03:09:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-mine",   "status":"in_progress","title":"@T@","assignee":"@A@","created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-orph",   "status":"open",       "title":"@T@","assignee":"",   "created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true}
]'
# A not-yet-assigned orphan carries no assignee, so the pour stamps its rig as
# gc.rig. A foreign stamp (@X@) is skipped; this rig's (@R@) is adopted.
FX_CROSS_RIG_ORPHAN='[
  {"id":"w-foreign","status":"open","title":"@T@","assignee":"","metadata":{"gc.rig":"@X@"},"created_at":"2026-09-18T03:05:00Z","issue_type":"molecule","ephemeral":true},
  {"id":"w-mine",   "status":"open","title":"@T@","assignee":"","metadata":{"gc.rig":"@R@"},"created_at":"2026-09-18T03:00:00Z","issue_type":"molecule","ephemeral":true}
]'

fx() {
  local s="${1//@T@/$TITLE}"
  s="${s//@A@/$AGENT_ID}"           # this rig's agent address
  s="${s//@O@/$OTHER_RIG/$AGENT-1}" # a foreign rig's agent address
  s="${s//@R@/$THIS_RIG}"           # this rig's name (a gc.rig value)
  s="${s//@X@/$OTHER_RIG}"          # a foreign rig's name (a gc.rig value)
  printf '%s' "$s"
}

# --- Per-agent contracts. ----------------------------------------------------
# Fields: agent | scope. The refinery runs per rig, with GC_RIG set and a
# rig-prefixed assignee.
AGENTS=(
  "refinery rig"
)
# The files the loop reads through paths it builds from each agent's name.
# run-tests --affected selects a suite only by a path it names, so they are
# named here, and the loop fails on a file it reads that this list leaves out.
READS=(
  agents/refinery/prompt.template.md
)

for SPEC in "${AGENTS[@]}"; do
  read -r AGENT SCOPE <<<"$SPEC"
  TITLE="mol-$AGENT-patrol"
  AGENT_RIG="$THIS_RIG"
  AGENT_ID="$THIS_RIG/$AGENT-1"
  PROMPT="$ROOT/agents/$AGENT/prompt.template.md"
  echo
  echo "== $AGENT =="

  NEEDS="${PROMPT#"$ROOT"/}"
  for F in $NEEDS; do
    case " ${READS[*]} " in
      *" $F "*) ok "$AGENT: READS names $F" ;;
      *) bad "$AGENT: READS leaves out $F, so run-tests --affected cannot select this suite when it changes" ;;
    esac
  done

  RECONCILE="$(extract patrol-wisp-reconcile "$PROMPT")"

  [ -n "$RECONCILE" ] \
    && ok "$AGENT: reconcile extracted between patrol-wisp-reconcile markers" \
    || bad "$AGENT: reconcile extraction EMPTY — markers missing from $PROMPT"

  printf '%s\n' "$RECONCILE" > "$TMP/reconcile.sh"
  # The snippet is read as instructions by an agent, but it must still be
  # runnable shell — a syntax error ships a broken instruction.
  bash -n "$TMP/reconcile.sh" \
    && ok "$AGENT: extracted reconcile is syntactically valid bash" \
    || bad "$AGENT: extracted reconcile failed bash -n"

  # --- Reconcile. ------------------------------------------------------------
  eq "$(run_reconcile "$(fx "$FX_LEAK")")" "w-run|w-orph" \
     "$AGENT: REGRESSION: the unassigned orphan is collected and burned; the running wisp survives"

  # A completed cycle awaiting burn (in_progress, older) beside the fresh
  # successor it poured (open, newer). Adopt the successor and burn the completed
  # cycle. Selecting by status adopts the completed cycle and burns the fresh
  # successor instead.
  eq "$(run_reconcile "$(fx "$FX_COMPLETED_SUCCESSOR")")" "w-fresh|w-done" \
     "$AGENT: REGRESSION: adopts the fresh successor and burns the completed-awaiting-burn cycle"

  # CONTROL, so the assertion above cannot pass for the wrong reason: drop the
  # created_at sort and the snippet falls back to in_progress-first order, which
  # adopts the completed cycle and burns the fresh successor — the reported bug.
  sed 's/ | sort -r / | cat /' "$TMP/reconcile.sh" > "$TMP/reconcile-nosort.sh"
  if cmp -s "$TMP/reconcile.sh" "$TMP/reconcile-nosort.sh"; then
    bad "$AGENT: control did not mutate the created_at sort — its shape changed, re-check the sed"
  else
    eq "$(run_reconcile "$(fx "$FX_COMPLETED_SUCCESSOR")" "$TMP/reconcile-nosort.sh")" "w-done|w-fresh" \
       "$AGENT: CONTROL: the pre-fix in_progress-first order adopts the completed cycle and burns the fresh successor"
  fi

  # The same discrimination when a partial reconcile left BOTH in_progress — the
  # fix reads created_at, not status, so the newer is adopted either way.
  eq "$(run_reconcile "$(fx "$FX_TWO_INPROGRESS")")" "w-live|w-stale" \
     "$AGENT: REGRESSION: with two in_progress wisps, adopts the newer and burns the older"

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
     "$AGENT: reconciles surplus to exactly one, preferring the newest pour"

  eq "$(run_reconcile '[]')" "|" "$AGENT: empty store yields no wisp and no burn"

  # The refinery coexists across rigs in one store, so it must leave a foreign
  # rig's wisp alone.
  if [ "$SCOPE" = rig ]; then
    # A foreign rig's patrol wisp in the shared store is neither kept as the
    # survivor nor burned — this rig's in_progress wisp survives and its orphan
    # is the only surplus. This is the reported collision: a title-only sweep
    # kept the foreign wisp and burned this rig's.
    eq "$(run_reconcile "$(fx "$FX_CROSS_RIG")")" "w-mine|w-orph" \
       "$AGENT: REGRESSION: a foreign rig's patrol wisp is left untouched; this rig's is reconciled"

    # The orphan signal is the pour-stamped gc.rig, since an unassigned wisp has
    # no assignee segment to read: a foreign gc.rig is skipped, this rig's adopted.
    eq "$(run_reconcile "$(fx "$FX_CROSS_RIG_ORPHAN")")" "w-mine|" \
       "$AGENT: REGRESSION: a foreign gc.rig orphan is skipped; this rig's gc.rig orphan is adopted"
  fi

  # --- Static guard: wisp-query invariants over every fenced block. ----------
  # Nothing else in the pack locks these four invariants down, so they are
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
  RIGGED=$(printf '%s\n' "$Q" | grep -c -- "GC_RIG" || true)
  eq "${RIGGED:-0}" "${TOTAL:-0}" "$AGENT: every wisp query is rig-scoped (passes \$GC_RIG to jq)"
done

echo
echo "patrol-wisp-reconcile: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
