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
#   4. THE CLASS-2 GATE HALF WAS MISSING (bead tk-yyfjv, operator ruling
#      2026-08-11). A bead whose work is done, pushed and parked on an OPEN pull
#      request awaiting a human approval has no open blocker and no bd-level
#      gate, so `gc bd ready` returns it and it classified as UNNAMED — six of
#      ten candidates in one measured signal-loom pass. The fix is an
#      intersection against the live open PRs, and its whole difficulty is the
#      inverse defect: a "carries merge_result, skip it" rule would hide
#      REJECTED work permanently, exactly when it most needs a sitting.
#   5. AN OPERATOR HOLD HAD NO MACHINE-READABLE MARKER (same bead, the ratified
#      scope rider). tk-0tln5's hold existed only as the word HELD in its title,
#      so the sweep re-nominated it every pass forever, and the only disposition
#      the menu offered for it was park — which the operator had rejected for
#      this scope. Class 4 gained `triage.hold`, a stamp rather than an edge.
#
# The three computational blocks are EXTRACTED VERBATIM from the shipped formula
# (`# >>> open-prs` / `# >>> classify-candidates` / `# >>> sweep-delta`) and
# executed against fixtures, so the test cannot drift from the instruction an
# agent actually runs. Hermetic: reads the repo, stubs `gc` and `gh`; no city,
# no Dolt, no network.
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
extract open-prs            "$FORMULA" > "$TMP/openprs.sh"
[ -s "$TMP/classify.sh" ] || { echo "no marked classify-candidates block"; exit 1; }
[ -s "$TMP/delta.sh" ]    || { echo "no marked sweep-delta block"; exit 1; }
[ -s "$TMP/openprs.sh" ]  || { echo "no marked open-prs block"; exit 1; }

echo "── the extracted blocks are valid shell ──"
bash -n "$TMP/classify.sh" && ok "classify-candidates: valid bash" \
    || bad "classify-candidates: valid bash" "bash -n failed"
bash -n "$TMP/delta.sh" && ok "sweep-delta: valid bash" \
    || bad "sweep-delta: valid bash" "bash -n failed"
bash -n "$TMP/openprs.sh" && ok "open-prs: valid bash" \
    || bad "open-prs: valid bash" "bash -n failed"

# The blocks live inside a TOML `"""` string, so TOML consumes escapes before an
# agent ever sees them: a trailing backslash joins two lines, backslash-n becomes
# a real newline, and jq's backslash-paren interpolation is not a valid TOML
# escape at all and fails the whole formula to parse. This test extracts the RAW
# file text while the agent runs the PARSED string — so a backslash anywhere in a
# marked block means the two texts differ and this test stops pinning what
# actually runs. Assert the file parses AND that the blocks are backslash-free;
# the parse check alone would miss a trailing backslash, which parses fine and
# silently rewrites the shell.
echo "── the formula parses as TOML and the blocks survive it unchanged ──"
python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$FORMULA" 2>/dev/null \
    && ok "formula parses as TOML" || bad "formula parses as TOML" "tomllib rejected it"
for blk in classify.sh delta.sh openprs.sh; do
    grep -q '[\]' "$TMP/$blk" \
        && bad "${blk%.sh}: no backslash (TOML would eat it)" "found a backslash" \
        || ok "${blk%.sh}: no backslash (TOML would eat it)"
done

# --- 1. classify: which beads reach the candidate set ------------------------
# READY is `gc bd ready --unassigned` output; LIVE is the open+in_progress
# listing the continuation-group check reads. c-plain carries NO metadata key at
# all — the shape most beads have on a real store, and the one a strict `== ""`
# comparison silently misses.
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"c-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"c-routed","title":"already dispatched","issue_type":"task","metadata":{"gc.routed_to":"rig/rig.polecat"}},
  {"id":"c-visit","title":"visit: something","issue_type":"task","metadata":{"task_kind":"visit"}},
  {"id":"c-subject","title":"triage: a scope","issue_type":"task","metadata":{"task_kind":"triage-subject"}},
  {"id":"c-ingroup","title":"subject of a live visit","issue_type":"task","metadata":{}},
  {"id":"c-takeaway","title":"parked by a human","issue_type":"epic","metadata":{"gc.takeaway":"needs operator ratify; resume on ping","gc.takeaway_by":"proactive"}},
  {"id":"c-takeaway-empty","title":"hold was cleared","issue_type":"task","metadata":{"gc.takeaway":""}},
  {"id":"c-pr-open","title":"done, parked on an open PR awaiting approval","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521","pr_url":"https://github.com/zookanalytics/signal-loom/pull/521"}},
  {"id":"c-pr-case","title":"same PR, written with a different case and a trailing path","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"522","pr_url":"https://GitHub.com/zookanalytics/signal-loom/pull/522/files"}},
  {"id":"c-pr-merged","title":"landed — finishable, must surface for close-out","issue_type":"task","metadata":{"merge_result":"merged","pr_number":"520","pr_url":"https://github.com/zookanalytics/signal-loom/pull/520"}},
  {"id":"c-pr-closed","title":"rejected — PR closed unmerged, needs a sitting","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"999","pr_url":"https://github.com/zookanalytics/signal-loom/pull/999"}},
  {"id":"c-pr-otherrepo","title":"number 521 — but in a different repository","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521","pr_url":"https://github.com/someone/elsewhere/pull/521"}},
  {"id":"c-pr-nourl","title":"marker but no pr_url to check liveness against","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521"}},
  {"id":"c-hold","title":"operator decided this waits","issue_type":"task","metadata":{"triage.hold":"deferred; operator may take a different direction","triage.hold_by":"operator"}},
  {"id":"c-hold-bare","title":"held, but the stamp names no reason","issue_type":"task","metadata":{"triage.hold":"true"}},
  {"id":"c-hold-empty","title":"hold was cleared","issue_type":"task","metadata":{"triage.hold":""}}
]
JSON
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"v-1","title":"visit: c-ingroup — a live sitting","metadata":{"task_kind":"visit","gc.continuation_group":"c-ingroup"}}
]
JSON

# `gh` stub for the open-prs block: answers ONLY for signal-loom, and only with
# the PRs that are genuinely open. #520 is merged and #999 is closed-unmerged, so
# neither appears — which is exactly how the intersection keeps them visible.
# GH_FAIL makes the stub fail the way a real outage does (non-zero, no output).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
repo=""
while [ $# -gt 0 ]; do
    case "$1" in --repo) repo="$2"; shift 2 ;; *) shift ;; esac
done
case "$repo" in
  */zookanalytics/signal-loom|zookanalytics/signal-loom)
    printf '%s\n' '[{"url":"https://github.com/zookanalytics/signal-loom/pull/521"},{"url":"https://github.com/zookanalytics/signal-loom/pull/522"}]' ;;
  *) printf '%s\n' '[]' ;;
esac
GH
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"; export PATH

LIVE="$TMP/live.json" READY="$TMP/ready.json"
export LIVE READY
# shellcheck disable=SC1090
. "$TMP/openprs.sh"
echo "── the open-PR read is batched, repo-qualified, and self-reporting ──"
eq "$PR_LIVENESS" "verified" "every repository the beads name answered → verified"
eq "$(printf '%s' "$OPEN_PRS" | jq 'length')" "2" "the open PRs of the repos the beads name"
# The repos come from the BEADS' pr_urls, never from gh's ambient context.
eq "$(printf '%s' "$PRREPOS" | sort | tr '\n' ' ')" \
   "github.com/someone/elsewhere github.com/zookanalytics/signal-loom " \
   "repos derived from the beads' own pr_url, both of them, deduped"
# shellcheck disable=SC1090
. "$TMP/classify.sh"
SURVIVORS="$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | sort | join(",")')"

echo "── classify keeps only genuinely unnamed beads ──"
eq "$SURVIVORS" \
   "c-hold-empty,c-plain,c-pr-closed,c-pr-merged,c-pr-nourl,c-pr-otherrepo,c-takeaway-empty" \
   "survivors are exactly the unnamed beads"
# tk-tnwo0: the candidate's `type` is projected from `.issue_type` — the field
# real `gc bd list`/`gc bd ready` emit (the fixtures now carry it too). The old
# `map({id,title,type})` read `.type`, absent on every real row, so every
# candidate carried type=null. A populated type is what normalize's post-cap
# cohort grouping will consume.
eq "$(printf '%s' "$CANDIDATES" | jq -r '.[] | select(.id=="c-plain") | .type')" "bug" \
   "a survivor's type is populated from issue_type, never null"
# Each drop asserted on its own so a regression names the class it broke.
for drop in c-routed:worked c-visit:conversing c-subject:held-by-design \
            c-ingroup:live-visit-in-group c-takeaway:takeaway-held \
            c-pr-open:gated-on-an-open-pr c-pr-case:gated-case-and-path-insensitive \
            c-hold:operator-held c-hold-bare:operator-held-reasonless; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done

# THE INVERSE DEFECT, which is the whole difficulty of the class-2 gate half: a
# "carries merge_result, skip it" rule would hide rejected work permanently and
# silently, exactly when it most needs a sitting. Each of these is a bead the
# marker names but no LIVE open PR does, and every one must stay VISIBLE.
echo "── a gating marker is not a gate: only a LIVE open PR drops a bead ──"
for keep in c-pr-merged:merged-is-finishable-and-surfaces-for-close-out \
            c-pr-closed:closed-unmerged-was-rejected-and-needs-a-sitting \
            c-pr-otherrepo:a-pr-number-names-nothing-without-its-repository \
            c-pr-nourl:no-pr_url-means-no-liveness-check-so-report-it; do
    id="${keep%%:*}"; why="${keep##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && ok "kept $id ($why)" || bad "kept $id ($why)" "was hidden — the inverse defect"
done

# An unreadable probe must never read as "no open PRs". It cannot hide a bead
# (an unread repository contributes none), but the sitting is owed the word.
echo "── an unreadable open-PR probe reports rather than hides ──"
GH_FAIL=1 ; export GH_FAIL
# shellcheck disable=SC1090
. "$TMP/openprs.sh"
eq "$PR_LIVENESS" "unverified" "a failed read is 'unverified', never a silent empty answer"
eq "$(printf '%s' "$OPEN_PRS" | jq 'length')" "0" "a failed read contributes no open PRs"
# shellcheck disable=SC1090
. "$TMP/classify.sh"
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-pr-open")' >/dev/null 2>&1 \
    && ok "a live-PR bead is REPORTED when liveness is unverified (re-report, never hide)" \
    || bad "a live-PR bead is REPORTED when liveness is unverified" "it was hidden on a failed probe"
unset GH_FAIL

# The same failed read, under `set -e` — where reporting it is HARDER than not
# reporting it, and where the block's own comments say it must still work. A
# bare `ROWS=$(gh ...)` is a simple assignment whose exit status is the command
# substitution's, so errexit kills the pass on the transient `gh` failure that
# the `else` arm exists to disclose: no `unverified`, no WARN, no visit body —
# the classify step simply stops. The test above cannot see that, because this
# file runs under `set -u` alone; only a child shell with `-e` can.
#
# Asked for the word it reached, an aborted pass prints NOTHING, so the check is
# fail-closed. The healthy read is run the same way as a positive control: it
# proves the -e harness reaches the end of the block at all, so a future edit
# that breaks errexit-safety ANYWHERE in the block (not just at this one
# assignment) fails here rather than passing vacuously.
echo "── the open-PR read survives 'set -e', which is where reporting is hard ──"
# shellcheck disable=SC2016  # $1/$PR_LIVENESS are for the CHILD shell to expand
ERRX_RUN='. "$1"; printf "%s" "$PR_LIVENESS"'
ERRX_FAIL="$(GH_FAIL=1 READY="$TMP/ready.json" LIVE="$TMP/live.json" \
    bash -e -c "$ERRX_RUN" _ "$TMP/openprs.sh" 2>/dev/null)"
eq "$ERRX_FAIL" "unverified" \
   "under 'set -e' a failed gh read still records 'unverified' (never aborts the pass)"
ERRX_OK="$(READY="$TMP/ready.json" LIVE="$TMP/live.json" \
    bash -e -c "$ERRX_RUN" _ "$TMP/openprs.sh" 2>/dev/null)"
eq "$ERRX_OK" "verified" "…and a healthy read runs to completion under 'set -e' too"

# No PR-parked candidate at all: nothing to ask about, and 'none' is a third
# state so an empty board is not mistaken for an unread one.
echo "── no PR-parked candidates → no GitHub call at all ──"
jq '[.[] | select((.metadata.merge_result // "") != "pull_request")]' "$TMP/ready.json" > "$TMP/ready-nopr.json"
READY="$TMP/ready-nopr.json"
# shellcheck disable=SC1090
. "$TMP/openprs.sh"
eq "$PR_LIVENESS" "none" "no PR-parked candidate → 'none', distinct from verified and unverified"
READY="$TMP/ready.json"
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

# The menu is the only place the sitting learns a hold exists. Offering park for
# a bead the operator simply wants held was itself part of the tk-yyfjv defect —
# it is the wrong mechanism, and it was the only one the menu had.
#
# Two assertions below are single-quoted on purpose: they are FIXED STRINGS to
# find in the formula and they contain backticks and a literal `$PR_LIVENESS`.
# Double-quoting would have the shell expand the very text being looked for, so
# each carries its own disable directive rather than being "fixed".
echo "── the visit body offers the hold, and distinguishes it from the park ──"
has "the menu offers a hold disposition" '**hold**'                      "$FORMULA"
has "the hold is a stamp with a reason"  'triage.hold=<the reason>'      "$FORMULA"
has "hold is distinguished from park"    'park is NOT it'                "$FORMULA"
# shellcheck disable=SC2016
has "unverified liveness is disclosed"   'If `$PR_LIVENESS` is `unverified`' "$FORMULA"

# Class 2's gate half, and the inverse defect that makes it hard.
echo "── class 2 states both halves and the husk rule ──"
has "class 2 is named gated"             '2. **gated**'                  "$FORMULA"
has "the gating-state marker is named"   'merge_result=pull_request'     "$FORMULA"
has "the marker alone is not the test"   'The marker alone is NOT the test' "$FORMULA"
has "merged stays visible"               'merged'                        "$FORMULA"
has "closed-unmerged stays visible"      'closed-unmerged'               "$FORMULA"
# shellcheck disable=SC2016
has "the read is batched per repository" 'One `gh pr list` per repository' "$FORMULA"

# Class 2(i)'s liveness test is "not closed", resolved against a widened set —
# so a convoy tracking a BLOCKED bead is gated, not a class-5 unnamed wait
# (bead tk-tnwo0, live case tk-dhue). LIVE is open+in_progress only, so a
# strict "present in LIVE" test drops blocked/deferred/pinned/hooked targets.
echo "── the edge check tests 'not closed', resolved against a widened ALIVE set ──"
has "the widening reads every non-closed status LIVE omits" 'blocked,deferred,pinned,hooked' "$FORMULA"
has "liveness is 'not closed', not 'present in LIVE'"       'not only when it is open'        "$FORMULA"
has "the edge check resolves against the widened set"       'against ALIVE'                   "$FORMULA"

echo
echo "liveness-sweep-delta: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
