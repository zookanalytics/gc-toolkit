#!/usr/bin/env bash
# liveness-sweep-delta.test.sh — the liveness sweep reports a DELTA, and the
# only park it offers is one it can actually perform (bead tk-snnpp, operator
# decision 2026-08-10).
#
# Three defects this pins, each of which failed SILENTLY in the field:
#
#   1. PARK WAS PROSE. The generated visit body offered "route / gate / park
#      into a named scope / kill". Three of those change the bead's class; the
#      park did not — the formula has no notion of scope membership, so a bead
#      "parked" in a note was a candidate again on the very next pass and every
#      sitting re-litigated it. The park that works is a real dependency edge
#      onto a scope bead, which makes the bead blocker-blocked and drops it from
#      `gc bd ready` before it ever reaches the candidate set.
#   2. THE CENSUS WAS THE WHOLE BACKLOG. "Unnamed" is the resting state of any
#      filed-but-not-active bead, so a full-population report returned ~93 of
#      113 open beads on this rig — a stable set, re-listed every pass, burying
#      the one bead that changed. The fix is delta reporting against a baseline
#      stamped on the standing subject.
#   3. TAKEAWAY-PARKED BEADS READ AS UNNAMED. A `gc.takeaway` stamp is a human
#      holding the bead awaiting their own answer; it carries no structural
#      edge, so without an explicit filter the sweep re-litigated precisely the
#      beads a human had touched most recently.
#
# The two computational blocks are EXTRACTED VERBATIM from the shipped formula
# (`# >>> classify-candidates` / `# >>> sweep-delta`) and executed against
# fixtures, so the test cannot drift from the instruction an agent actually
# runs. Hermetic: reads the repo, stubs `gc`; no city, no Dolt, no network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FORMULA="$ROOT/formulas/mol-liveness-sweep.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { grep -qF -- "$2" "$3" && ok "$1" || bad "$1" "missing: $2"; }
hasnt() { grep -qiF -- "$2" "$3" && bad "$1" "still present: $2" || ok "$1"; }

extract() { # extract() <marker> <file> — the lines between # >>> and # <<<
    awk -v m="$1" '$0 ~ ("# >>> " m) {inb=1; next} $0 ~ ("# <<< " m) {inb=0} inb' "$2"
}

[ -s "$FORMULA" ] || { echo "missing $FORMULA"; exit 1; }

extract classify-candidates "$FORMULA" > "$TMP/classify.sh"
extract sweep-delta         "$FORMULA" > "$TMP/delta.sh"
[ -s "$TMP/classify.sh" ] || { echo "no marked classify-candidates block"; exit 1; }
[ -s "$TMP/delta.sh" ]    || { echo "no marked sweep-delta block"; exit 1; }

echo "── the extracted blocks are valid shell ──"
bash -n "$TMP/classify.sh" && ok "classify-candidates: valid bash" \
    || bad "classify-candidates: valid bash" "bash -n failed"
bash -n "$TMP/delta.sh" && ok "sweep-delta: valid bash" \
    || bad "sweep-delta: valid bash" "bash -n failed"

# --- 1. classify: which beads reach the candidate set ------------------------
# READY is `gc bd ready --unassigned` output; LIVE is the open+in_progress
# listing the continuation-group check reads. c-plain carries NO metadata key at
# all — the shape most beads have on a real store, and the one a strict `== ""`
# comparison silently misses.
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"c-plain","title":"an ordinary idle bug","type":"bug"},
  {"id":"c-routed","title":"already dispatched","type":"task","metadata":{"gc.routed_to":"rig/rig.polecat"}},
  {"id":"c-visit","title":"visit: something","type":"task","metadata":{"task_kind":"visit"}},
  {"id":"c-subject","title":"triage: a scope","type":"task","metadata":{"task_kind":"triage-subject"}},
  {"id":"c-ingroup","title":"subject of a live visit","type":"task","metadata":{}},
  {"id":"c-takeaway","title":"parked by a human","type":"epic","metadata":{"gc.takeaway":"needs operator ratify; resume on ping","gc.takeaway_by":"proactive"}},
  {"id":"c-takeaway-empty","title":"hold was cleared","type":"task","metadata":{"gc.takeaway":""}}
]
JSON
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"v-1","title":"visit: c-ingroup — a live sitting","metadata":{"task_kind":"visit","gc.continuation_group":"c-ingroup"}}
]
JSON

LIVE="$TMP/live.json" READY="$TMP/ready.json"
export LIVE READY
# shellcheck disable=SC1090
. "$TMP/classify.sh"
SURVIVORS="$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | sort | join(",")')"

echo "── classify keeps only genuinely unnamed beads ──"
eq "$SURVIVORS" "c-plain,c-takeaway-empty" "survivors are exactly the unnamed beads"
# Each drop asserted on its own so a regression names the class it broke.
for drop in c-routed:worked c-visit:conversing c-subject:held-by-design \
            c-ingroup:live-visit-in-group c-takeaway:takeaway-held; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done
# The absent-vs-empty distinction: an EMPTY takeaway is a cleared hold, not a
# hold, and a bead with no metadata at all must survive the `//` coalescing.
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-takeaway-empty")' >/dev/null 2>&1 \
    && ok "empty gc.takeaway is a cleared hold, not a hold" \
    || bad "empty gc.takeaway is a cleared hold, not a hold" "c-takeaway-empty was dropped"
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-plain")' >/dev/null 2>&1 \
    && ok "a bead with no metadata object survives" \
    || bad "a bead with no metadata object survives" "c-plain was dropped"

# --- 2. the delta split ------------------------------------------------------
# `gc` stub: the one read the block performs (gc bd show <subject> --json).
# FAKE_SUBJECT is the raw payload, so a case can inject a missing baseline or a
# control character in the notes.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "show" ] || exit 0
printf '%s\n' "${FAKE_SUBJECT:-[]}"
GC
chmod +x "$TMP/bin/gc"
PATH="$TMP/bin:$PATH"; export PATH
SWEEP_SUBJECT="tk-subject"; export SWEEP_SUBJECT

subject_json() { # subject_json <baseline-or-ABSENT> [raw-notes]
    local base="$1" notes="${2:-ordinary notes}" meta='"task_kind":"triage-subject"'
    [ "$base" = "ABSENT" ] || meta="$meta,\"sweep.reported\":\"$base\""
    # printf, not jq: the control-character case below needs the byte to land in
    # the payload RAW, which is what a real `bd show` emits and what kills jq.
    # jq would emit it escaped as a \u0001 sequence, which parses cleanly, and
    # the fixture would prove nothing.
    printf '[{"id":"tk-subject","notes":"%s","metadata":{%s}}]' "$notes" "$meta"
}

run_delta() { # run_delta <candidate-ids…> — sets NEW_COUNT/CARRIED_COUNT/CUR_IDS
    CANDIDATES="$(printf '%s\n' "$@" | jq -Rc '{id:., title:"t", type:"task"}' | jq -sc .)"
    export CANDIDATES
    # shellcheck disable=SC1090
    . "$TMP/delta.sh"
}

echo "── the delta splits new from carried ──"
FAKE_SUBJECT="$(subject_json "a,b")"; export FAKE_SUBJECT
run_delta a b c
eq "$NEW_COUNT" "1" "baseline a,b over a,b,c → 1 new"
eq "$(printf '%s' "$NEW" | jq -r '.[0].id')" "c" "the new one is c"
eq "$CARRIED_COUNT" "2" "a and b carry over"
eq "$CARRIED_IDS" "a, b" "carried ids listed for completeness, not re-litigated"
eq "$CUR_IDS" "a,b,c" "the baseline to stamp is the CURRENT set"

# `index` returns a POSITION and position 0 is a real hit. A truthiness test
# that treats 0 as a miss reports the first bead of the baseline as new on every
# single pass — the one bead guaranteed to be re-litigated forever.
FAKE_SUBJECT="$(subject_json "a")"; export FAKE_SUBJECT
run_delta a b
eq "$CARRIED_COUNT" "1" "index 0 counts as a hit (first baseline id is carried)"
eq "$(printf '%s' "$NEW" | jq -r '.[0].id')" "b" "only the genuinely new bead is new"

# First run, or a rig that has never reported: one full census, then deltas.
FAKE_SUBJECT="$(subject_json ABSENT)"; export FAKE_SUBJECT
run_delta a b c
eq "$NEW_COUNT" "3" "absent baseline → every candidate is new (first-run census)"
eq "$CARRIED_COUNT" "0" "absent baseline → nothing carried"

# A departed bead must leave the baseline, so a regression re-surfaces it.
FAKE_SUBJECT="$(subject_json "a,z")"; export FAKE_SUBJECT
run_delta a b
eq "$CUR_IDS" "a,b" "a dispositioned bead (z) is pruned from the next baseline"
eq "$NEW_COUNT" "1" "b is new; a is not"

# The subject's own notes are free text and routinely carry control characters;
# without the `tr -d` scrub jq dies, the baseline reads empty, and the whole
# backlog re-reports as new.
FAKE_SUBJECT="$(subject_json "a,b" "notes with a raw $(printf '\001') control char")"
export FAKE_SUBJECT
run_delta a b c
eq "$CARRIED_COUNT" "2" "control chars in the subject's notes do not destroy the baseline"

# --- 3. the instruction the sitting reads ------------------------------------
echo "── the visit body offers only the park the formula can perform ──"
hasnt "no bare 'park into a named scope' offer" "park into a named scope" "$FORMULA"
hasnt "no bare 'park-into-a-scope' menu item"   "park-into-a-scope"       "$FORMULA"
has "the park is a real dependency edge" 'gc bd dep add <bead> <scope>' "$FORMULA"
has "the edge is called load-bearing"    "load-bearing"                  "$FORMULA"
has "prose parking is called out as a no-op" "Parking in prose"          "$FORMULA"
has "closing the scope un-parks its beads"   "closing the scope"         "$FORMULA"

echo "── the baseline discipline is stated where it is performed ──"
has "class 4 names the takeaway hold"     "gc.takeaway" "$FORMULA"
has "the baseline is read from the subject" 'sweep.reported' "$FORMULA"
has "the skip path does not advance it"   "Do not advance the baseline on" "$FORMULA"
has "the visit is filed before the stamp" "File the visit BEFORE stamping" "$FORMULA"

echo
echo "liveness-sweep-delta: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
