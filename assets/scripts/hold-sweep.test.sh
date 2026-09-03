#!/usr/bin/env bash
# Hermetic test for assets/scripts/hold-sweep.sh (tk-a44ar4).
#
# WHAT THE SCRIPT IS FOR. A non-empty `triage.hold` hides a bead from the
# liveness sweep — liveness-sweep.sh classifies it `held-by-design` and
# liveness-sweep-precheck.sh drops it from the survivor set. The condition that
# would end the hold is therefore the only thing standing between a hidden bead
# and a permanently hidden one, and prose is not a thing a pass can evaluate.
# `hold` records that condition as metadata; `reconcile` evaluates every live
# hold each cycle and releases the ones whose condition has fired.
#
# What is exercised:
#   * hold writes marker + condition + stamps and APPENDS to notes — a
#     replacing write here would destroy rulings recorded on a held bead, which
#     is the one clobber this machinery must never make;
#   * hold's fail-closed refusals — no --until, a condition no pass can
#     evaluate, a closed bead. A hold with no checkable condition is exactly
#     the defect, so the writer refuses to create one;
#   * each condition shape at both verdicts: merged-within inside and outside
#     its window, bead-closed with every named bead closed and with one still
#     open, date before and after it arrives;
#   * every hold that must NOT be released: unconditioned (an operator's
#     silence is a disposition, not a mistake to overwrite), a malformed
#     condition, and a condition naming a bead this store cannot read;
#   * RELEASE IS NOT CLOSE AND NOT DISPATCH — status is untouched and no
#     `gc sling` is ever issued;
#   * the empty-marker and closed-bead exclusions, and that a live non-`open`
#     status is still swept;
#   * the condition key is read from the lifecycle declaration, not only
#     hardcoded, so the declaration beside the markers is load-bearing;
#   * the FALSE-EMPTY-BOARD guard — an unreadable listing exits non-zero
#     instead of printing a summary byte-identical to a healthy empty board.
#     "I could not read the holds" and "nothing is held" reading alike is the
#     same silence this pass exists to remove;
#   * the QUIET PATH — an empty store still passes, so the guard above did not
#     strand the ordinary no-holds case;
#   * a POSITIVE CONTROL over the shipped order file, so a passing suite cannot
#     mean the cadence that evaluates these conditions was quietly un-shipped.
#
# No live city, Dolt, network, gc or bd — only jq, stubs, and a tmpdir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/hold-sweep.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

[ -x "$SUT" ] || chmod +x "$SUT" 2>/dev/null

# --- stubs -------------------------------------------------------------------
# $TMP/beads.json is the store: an array of beads. The merge probe reads
# `closed_at` off beads carrying merge_result=merged, so the fixtures below
# date those relative to now.
BIN="$TMP/bin"; mkdir -p "$BIN"

cat > "$BIN/bd" <<'STUB'
#!/usr/bin/env bash
# The script reaches the store through `gc bd`; a direct `bd` is the regression
# this guard catches, so only the gc stub may run this one.
[ -n "${VIA_GC_BD:-}" ] || { echo "stub bd: called directly, not through gc bd" >&2; exit 127; }
set -u
STORE="${STUB_STORE:?}"
# Global flags precede the verb, as they do for real bd.
while [ "${1:-}" = "--db" ]; do shift 2 || shift || true; done
if [ -n "${STUB_BD_LIST_FAIL:-}" ] && [ "${1:-}" = "list" ]; then
    echo "bd: simulated listing failure" >&2; exit 1
fi
case "${1:-}" in
  list)
    shift
    key=""; all=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --has-metadata-key) shift; key="${1:-}" ;;
        --all) all=1 ;;
        *) : ;;
      esac
      shift || true
    done
    jq -c --arg k "$key" --argjson all "$all" '
      [ .[]
        | select($k == "" or (.metadata | has($k)))
        | select($all == 1 or .status != "closed") ]' "$STORE"
    ;;
  show)
    id="${2:-}"
    out="$(jq -c --arg id "$id" '[ .[] | select(.id == $id) ]' "$STORE")"
    if [ "$(printf '%s' "$out" | jq 'length')" = "0" ]; then
      # bd answers an OBJECT, not an empty array, when nothing resolves.
      echo '{"error":"no issues found matching the provided IDs","schema_version":1}'
    else
      printf '%s\n' "$out"
    fi
    ;;
  update)
    shift
    id="${1:-}"; shift || true
    sets=(); unsets=(); note=""; note_mode=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata) shift; sets+=("${1:-}") ;;
        --unset-metadata) shift; unsets+=("${1:-}") ;;
        --append-notes) shift; note="${1:-}"; note_mode="append" ;;
        # Modelled deliberately: bd's --notes REPLACES. A stub that ignored it
        # would let a destructive-write regression pass the append assertions.
        --notes) shift; note="${1:-}"; note_mode="replace" ;;
        *) : ;;
      esac
      shift || true
    done
    tmp="$(mktemp)"
    cp "$STORE" "$tmp"
    for kv in ${sets[@]+"${sets[@]}"}; do
      k="${kv%%=*}"; v="${kv#*=}"
      jq -c --arg id "$id" --arg k "$k" --arg v "$v" \
        'map(if .id == $id then .metadata[$k] = $v else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    for k in ${unsets[@]+"${unsets[@]}"}; do
      jq -c --arg id "$id" --arg k "$k" \
        'map(if .id == $id then (.metadata |= del(.[$k])) else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    done
    if [ "$note_mode" = "append" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = ((.notes // "") + (if (.notes // "") == "" then "" else "\n" end) + $n) else . end)' \
        "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    elif [ "$note_mode" = "replace" ]; then
      jq -c --arg id "$id" --arg n "$note" \
        'map(if .id == $id then .notes = $n else . end)' "$tmp" > "$tmp.n" && mv "$tmp.n" "$tmp"
    fi
    mv "$tmp" "$STORE"
    echo "updated $id"
    ;;
  *) echo "bd stub: unsupported '${1:-}'" >&2; exit 2 ;;
esac
STUB

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "bd" ]; then
    shift
    printf '%s\n' "$*" >> "${STUB_BD_LOG:-/dev/null}"
    VIA_GC_BD=1 exec "$(dirname "$0")/bd" "$@"
fi
# Releasing must never dispatch. Any sling at all is a failure, so the stub
# records it rather than refusing, and the assertions below count the log.
if [ "${1:-}" = "sling" ]; then
    shift; printf '%s\n' "$*" >> "${STUB_SLING_LOG:?}"; exit 0
fi
echo "gc stub: unsupported '${1:-}'" >&2; exit 2
STUB
chmod +x "$BIN/bd" "$BIN/gc"

export PATH="$BIN:$PATH"
export STUB_STORE="$TMP/beads.json"
export STUB_SLING_LOG="$TMP/sling.log"
export BEADS_ACTOR="test-actor"
unset GC_AGENT GC_RIG GC_RIG_ROOT GC_PACK_DIR 2>/dev/null || true

store() { printf '%s' "$1" > "$STUB_STORE"; : > "$STUB_SLING_LOG"; }
meta()  { jq -r --arg id "$1" --arg k "$2" '(.[] | select(.id == $id) | .metadata[$k]) // "<absent>"' "$STUB_STORE"; }
notes() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .notes) // ""' "$STUB_STORE"; }
status_of() { jq -r --arg id "$1" '(.[] | select(.id == $id) | .status) // ""' "$STUB_STORE"; }
slings() { wc -l < "$STUB_SLING_LOG" | tr -d ' '; }
# A UTC stamp N hours in the past, so the merge-window fixtures are dated
# against the same clock the script reads.
ago() { date -u -d "@$(( $(date -u +%s) - ($1 * 3600) ))" +%Y-%m-%dT%H:%M:%SZ; }
day_offset() { date -u -d "@$(( $(date -u +%s) + ($1 * 86400) ))" +%Y-%m-%d; }

MERGE_2H="$(ago 2)"
MERGE_200H="$(ago 200)"

# --- HOLD --------------------------------------------------------------------
echo "# hold"
store '[{"id":"b-1","status":"open","metadata":{},"notes":"operator: this must not be dispatched before the naming call"}]'
out="$("$SUT" hold b-1 --until bead-closed:b-9 --reason "sequenced behind the naming call" 2>&1)"; rc=$?
eq "$rc" 0 "hold exits 0"
eq "$(meta b-1 triage.hold)" "sequenced behind the naming call" "hold writes the prose marker"
eq "$(meta b-1 triage.hold_until)" "bead-closed:b-9" "hold records the release condition as metadata"
eq "$(meta b-1 triage.hold_by)" "test-actor" "hold records who held it"
has "$(meta b-1 triage.hold_at)" "T" "hold records when"
has "$(notes b-1)" "operator: this must not be dispatched" "hold APPENDS to notes (the prior ruling survives)"
has "$(notes b-1)" "until=bead-closed:b-9" "hold's own note names the condition"
has "$out" "held b-1 until bead-closed:b-9" "hold says what it did"

echo "# hold refusals — a hold nothing can end is the defect itself"
store '[{"id":"b-1","status":"open","metadata":{},"notes":""}]'
out="$("$SUT" hold b-1 --reason "just because" 2>&1)"; rc=$?
eq "$rc" 2 "hold without --until is a usage error"
eq "$(meta b-1 triage.hold)" "<absent>" "a refused hold writes no marker"
has "$out" "review-by date" "the refusal names the escape hatch for an unexpressible wait"

out="$("$SUT" hold b-1 --until "when signal-loom is happier" 2>&1)"; rc=$?
eq "$rc" 2 "hold refuses a condition no pass can evaluate"
eq "$(meta b-1 triage.hold)" "<absent>" "a refused hold writes no marker"

out="$("$SUT" hold b-1 --until "merged-within:0h" 2>&1)"; rc=$?
eq "$rc" 2 "hold refuses a zero-hour window"

out="$("$SUT" hold b-1 --until "bead-closed:" 2>&1)"; rc=$?
eq "$rc" 2 "hold refuses bead-closed with no bead named"

out="$("$SUT" hold b-1 --until "date:2026-99-99" 2>&1)"; rc=$?
eq "$rc" 2 "hold refuses an impossible review-by date"

store '[{"id":"b-3","status":"closed","metadata":{},"notes":""}]'
out="$("$SUT" hold b-3 --until date:2099-01-01 2>&1)"; rc=$?
eq "$rc" 1 "hold refuses a closed bead"

out="$("$SUT" hold b-nope --until date:2099-01-01 2>&1)"; rc=$?
eq "$rc" 1 "hold refuses a bead that does not resolve (bd's object-shaped miss)"

echo "# hold warns when the condition is already true"
store '[{"id":"b-1","status":"open","metadata":{},"notes":""},
        {"id":"b-9","status":"closed","metadata":{},"notes":""}]'
out="$("$SUT" hold b-1 --until bead-closed:b-9 2>&1)"
has "$out" "ALREADY true" "hold on a spent condition says so"
# The mirror case: a hint that fires unconditionally says nothing.
store '[{"id":"b-1","status":"open","metadata":{},"notes":""},
        {"id":"b-9","status":"open","metadata":{},"notes":""}]'
out="$("$SUT" hold b-1 --until bead-closed:b-9 2>&1)"
hasnt "$out" "ALREADY true" "hold on a live condition does not claim it is spent"

# --- RECONCILE: bead-closed --------------------------------------------------
echo "# reconcile: bead-closed"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"sequenced behind the naming call","triage.hold_until":"bead-closed:b-9"},"notes":"the ruling: this bead is NOT gated on the naming call"},
        {"id":"b-9","status":"closed","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "reconcile exits 0 on a clean pass"
eq "$(meta b-1 triage.hold)" "" "a fired hold is EMPTIED, which is the pack's cleared-hold shape"
eq "$(meta b-1 triage.hold_cleared_by)" "test-actor" "the release records who released it"
has "$(meta b-1 triage.hold_cleared_at)" "T" "the release records when"
eq "$(meta b-1 triage.hold_until)" "bead-closed:b-9" "the condition that fired survives as the record"
has "$(notes b-1)" "the ruling: this bead is NOT gated" "release APPENDS to notes (the ruling survives)"
has "$(notes b-1)" "hold released" "the release is recorded in notes"
has "$out" "released b-1" "the pass says what it released"

echo "# release is not close and not dispatch"
eq "$(status_of b-1)" "open" "release leaves the bead's status alone"
eq "$(slings)" "0" "release dispatches nothing"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"bead-closed:b-8,b-9"},"notes":""},
        {"id":"b-8","status":"closed","metadata":{},"notes":""},
        {"id":"b-9","status":"open","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "bead-closed holds while ANY named bead is still open"
has "$out" "1 waiting" "the pass counts it as waiting"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"bead-closed:b-8,b-9"},"notes":""},
        {"id":"b-8","status":"closed","metadata":{},"notes":""},
        {"id":"b-9","status":"closed","metadata":{},"notes":""}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 triage.hold)" "" "bead-closed fires once EVERY named bead has closed"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"bead-closed:b-gone"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "a condition naming a bead this store cannot read never releases"
has "$out" "UNREADABLE b-1" "and the unreadable condition is named"

# --- RECONCILE: merged-within ------------------------------------------------
# The reported case: "re-open when any PR has merged within the last 48h",
# which fired repeatedly with nothing acting on it.
echo "# reconcile: merged-within"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"held pending merge MOVEMENT","triage.hold_until":"merged-within:48h"},"notes":""},
        {"id":"m-1","status":"closed","closed_at":"'"$MERGE_2H"'","metadata":{"merge_result":"merged","merged_sha":"abc"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "" "a merge inside the window releases the hold"
has "$out" "released b-1" "the pass says so"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"held pending merge MOVEMENT","triage.hold_until":"merged-within:48h"},"notes":""},
        {"id":"m-1","status":"closed","closed_at":"'"$MERGE_200H"'","metadata":{"merge_result":"merged","merged_sha":"abc"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "held pending merge MOVEMENT" "a merge outside the window holds"
has "$out" "1 waiting" "the pass counts it as waiting"

# An unmerged anchor is not a merge: merge_result exists in other values, and
# counting one would release every hold the moment any PR was opened.
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"merged-within:48h"},"notes":""},
        {"id":"m-1","status":"open","closed_at":"'"$MERGE_2H"'","metadata":{"merge_result":"pull_request"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "only merge_result=merged counts as a merge"
has "$out" "UNREADABLE b-1" "with no merge to read, the probe is unreadable and never releases"

# --- RECONCILE: date ---------------------------------------------------------
echo "# reconcile: date (the review-by date)"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"no operator reason supplied","triage.hold_until":"date:'"$(day_offset -1)"'"},"notes":""}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-1 triage.hold)" "" "a review-by date that has arrived releases the hold"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"no operator reason supplied","triage.hold_until":"date:'"$(day_offset 7)"'"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "no operator reason supplied" "a review-by date still ahead holds"
has "$out" "1 waiting" "the pass counts it as waiting"

# --- RECONCILE: what must never be released ----------------------------------
echo "# reconcile: holds that must NOT be released"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"the silence IS the disposition"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "an unconditioned hold does not fail the pass"
eq "$(meta b-1 triage.hold)" "the silence IS the disposition" "an unconditioned hold is NOT released (guessing would overwrite a disposition)"
has "$out" "UNCONDITIONED b-1" "but it is named every pass, so it is never silent"
has "$out" "1 unconditioned" "and counted in the summary"
has "$out" "--until date:YYYY-MM-DD" "the report says how to end the silence"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"whenever it feels right"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "a malformed condition never releases"
has "$out" "UNREADABLE b-1" "and is named"

# The absent condition is an EMPTY field in the pass's own rows, and TAB is IFS
# whitespace: a run of tabs collapses to one delimiter. Read the columns in the
# wrong order and an unconditioned hold arrives carrying its prose as its
# condition, which reports the largest class of holds — the ones with no
# condition at all — as merely unreadable. Prove the two classes stay apart in
# one pass, where a shifted column would swap them.
store '[{"id":"b-none","status":"open","metadata":{"triage.hold":"date:2000-01-01"},"notes":""},
        {"id":"b-bad","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"garbage"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
has "$out" "UNCONDITIONED b-none" "a hold with no condition reads as unconditioned even when its PROSE looks like a condition"
has "$out" "UNREADABLE b-bad" "and the malformed one beside it still reads as unreadable"
has "$out" "1 unconditioned, 1 unreadable" "the two classes are counted apart"
eq "$(meta b-none triage.hold)" "date:2000-01-01" "and neither is released"

echo "# what is and is not a live hold"
store '[{"id":"b-empty","status":"open","metadata":{"triage.hold":"","triage.hold_until":"date:2000-01-01"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
has "$out" "of 0 held" "an EMPTY triage.hold is a CLEARED hold, not a hold"

store '[{"id":"b-closed","status":"closed","metadata":{"triage.hold":"h","triage.hold_until":"date:2000-01-01"},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"
has "$out" "of 0 held" "a closed bead's hold is not swept"

store '[{"id":"b-wip","status":"in_progress","metadata":{"triage.hold":"h","triage.hold_until":"date:2000-01-01"},"notes":""}]'
"$SUT" reconcile >/dev/null 2>&1
eq "$(meta b-wip triage.hold)" "" "EVERY non-closed status is live: an in_progress hold is swept too"

echo "# dry run"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"date:2000-01-01"},"notes":""}]'
out="$("$SUT" reconcile --dry-run 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "--dry-run writes nothing"
has "$out" "DRY-RUN would release b-1" "--dry-run says what it would do"

# --- RELEASE by hand ---------------------------------------------------------
echo "# release"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"date:2099-01-01"},"notes":"keep me"}]'
out="$("$SUT" release b-1 --reason "the premise died" 2>&1)"; rc=$?
eq "$rc" 0 "release exits 0"
eq "$(meta b-1 triage.hold)" "" "release empties the marker"
has "$(notes b-1)" "keep me" "release appends to notes rather than replacing"
has "$(notes b-1)" "the premise died" "release records why"
eq "$(status_of b-1)" "open" "release does not close"
eq "$(slings)" "0" "release does not dispatch"

store '[{"id":"b-1","status":"open","metadata":{},"notes":""}]'
out="$("$SUT" release b-1 2>&1)"; rc=$?
eq "$rc" 1 "release refuses a bead that carries no hold"

# --- LIST --------------------------------------------------------------------
echo "# list"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"waiting on the call","triage.hold_until":"date:2099-01-01"},"notes":""},
        {"id":"b-2","status":"open","metadata":{"triage.hold":"no reason given"},"notes":""}]'
out="$("$SUT" list 2>&1)"
has "$out" "b-1 [WAITING]" "list gives each hold its verdict"
has "$out" "b-2 [UNCONDITIONED]" "list names the holds nothing can end"
has "$out" "waiting on the call" "list shows the prose beside the condition"
out="$("$SUT" list --json 2>&1)"
eq "$(printf '%s' "$out" | jq -r 'length')" "2" "list --json answers an array of the live holds"
eq "$(printf '%s' "$out" | jq -r '.[0].until')" "date:2099-01-01" "list --json carries the condition"

store '[]'
out="$("$SUT" list 2>&1)"
has "$out" "no live holds" "list is quiet on an empty store"

# --- the declaration is load-bearing -----------------------------------------
# The condition key is declared beside the markers it qualifies. A script that
# only hardcoded it would let the declaration drift into being a comment.
echo "# lifecycle declaration"
mkdir -p "$TMP/pack/lifecycle"
{ echo '[holds]'; echo 'marker_keys = ["triage.hold"]'; echo 'release_condition_key = "triage.custom_until"'; } > "$TMP/pack/lifecycle/lifecycle.toml"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.custom_until":"date:2000-01-01"},"notes":""}]'
(GC_PACK_DIR="$TMP/pack" "$SUT" reconcile >/dev/null 2>&1)
eq "$(meta b-1 triage.hold)" "" "the condition key is read from the lifecycle declaration"

store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"date:2000-01-01"},"notes":""}]'
out="$(GC_PACK_DIR="$TMP/pack" "$SUT" reconcile 2>&1)"
eq "$(meta b-1 triage.hold)" "h" "and a key the declaration does not name is not the condition"
has "$out" "UNCONDITIONED" "so that hold reads as unconditioned, not as released"

# --- the false-empty-board guard ---------------------------------------------
# For a pass whose whole job is to end a silence, "I could not read the board"
# and "nothing is held" must not read alike.
echo "# unreadable board"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"date:2000-01-01"},"notes":""}]'
out="$(STUB_BD_LIST_FAIL=1 "$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 1 "an unreadable listing exits non-zero"
has "$out" "NOT treating this as an empty board" "and says why"
hasnt "$out" "0 released, 0 waiting" "it never prints a clean-looking summary"
eq "$(meta b-1 triage.hold)" "h" "and nothing is released from a board it could not read"

out="$(STUB_BD_LIST_FAIL=1 "$SUT" list 2>&1)"; rc=$?
eq "$rc" 1 "list on an unreadable board exits non-zero too"

# The quiet path: the guard above must not have stranded the ordinary case.
echo "# quiet path"
store '[]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "an empty store is a clean pass"
has "$out" "of 0 held" "and reports zero holds"

store '[{"id":"b-1","status":"open","metadata":{},"notes":""}]'
out="$("$SUT" reconcile 2>&1)"; rc=$?
eq "$rc" 0 "a store with no holds at all is a clean pass"

# --- the store the reads are pinned to ---------------------------------------
# `gc bd` resolves its ledger from the invoking rig and ignores BEADS_DIR, so a
# rig-scoped pass that does not pin --db reads whatever rig gc resolves.
echo "# store pinning"
export STUB_BD_LOG="$TMP/bd.log"
store '[{"id":"b-1","status":"open","metadata":{"triage.hold":"h","triage.hold_until":"date:2099-01-01"},"notes":""}]'

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "GC_RIG_ROOT pins the reads to that rig's store"

: > "$STUB_BD_LOG"
("$SUT" reconcile >/dev/null 2>&1)
hasnt "$(cat "$STUB_BD_LOG")" "--db" "with no GC_RIG_ROOT and no --db, nothing is pinned"

: > "$STUB_BD_LOG"
(GC_RIG_ROOT="$TMP/rigroot" "$SUT" reconcile --db "$TMP/explicit/.beads" >/dev/null 2>&1)
has "$(cat "$STUB_BD_LOG")" "--db $TMP/explicit/.beads" "an explicit --db overrides GC_RIG_ROOT"
hasnt "$(cat "$STUB_BD_LOG")" "--db $TMP/rigroot/.beads" "and the rig-root default is not also passed"
unset STUB_BD_LOG

# --- positive control over the shipped cadence -------------------------------
# The condition metadata is only half the mechanism: without the order nothing
# evaluates it and a hold outlives its premise exactly as before.
echo "# shipped order"
ORDER="$ROOT/orders/hold-sweep.toml"
[ -s "$ORDER" ] && ok "orders/hold-sweep.toml ships" || bad "orders/hold-sweep.toml is missing"
o="$(cat "$ORDER" 2>/dev/null)"
has "$o" 'trigger = "cooldown"' "the order is cooldown-triggered"
has "$o" 'scope = "rig"' "the order is rig-scoped (one store per registration)"
has "$o" 'hold-sweep.sh reconcile' "the order runs this script's reconcile verb"
if grep -qE '^[[:space:]]*no_work_gate' "$ORDER"; then
    bad "the order does not opt out of the single-flight gate (no_work_gate is set)"
else
    ok "the order does not opt out of the single-flight gate"
fi

# The shipped declaration, not the test's synthetic one.
LC="$ROOT/lifecycle/lifecycle.toml"
has "$(cat "$LC" 2>/dev/null)" 'release_condition_key = "triage.hold_until"' "lifecycle.toml declares the condition key the script reads"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
