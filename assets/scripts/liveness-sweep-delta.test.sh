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
#   6. A WORK BEAD A LIVE MOLECULE WAS DRIVING READ AS UNNAMED (bead tk-8rm3q).
#      mol-polecat-work stamps assignee and gc.routed_to on the molecule root and
#      its steps, never on the work bead its input convoy tracks, so an actively
#      worked bead carried no worker signal and re-surfaced every pass — it even
#      fooled the agent who had just dispatched it. Class 1 gained the
#      worked-via-convoy discriminator: the convoys a non-closed bead names as
#      gc.input_convoy_id, and the members those convoys track. Its hard half is
#      the husk — a tracks edge is not coverage unless a LIVE bead names the
#      convoy, or a dead synthetic convoy hides the highest-priority idle bead.
#   7. A SECOND STANDING-RECORD IDIOM WAS NEVER ADDED TO THE EXCLUSION LIST
#      (bead tk-rw2ra). Class 4(a) excluded `task_kind=triage-subject` as one
#      hand-maintained select line, so when mol-feedback-distiller began
#      creating `task_kind=feedback-pattern` cluster anchors — open, unrouted
#      and unassigned by the same design — they classified as UNNAMED: 13 of
#      the 42 new waits in the 2026-08-14T05:05Z pass, 31% of that census.
#      A standing record is the worst false positive available here because it
#      NEVER closes, so each one inflates the carried count of every future
#      pass forever and the population grows with every distiller run. The fix
#      is a NAMED list (`standing_kinds`), so idiom four is one string and a
#      fixture; its inverse defect is over-breadth — a kind stamp is not a
#      standing record unless it is listed.
#   8. MACHINE CONVOYS WERE OPERATOR CANDIDATES (bead tk-gri6a, operator ruling
#      2026-08-14). Every sling mints an `input convoy for <bead>` wrapper; it
#      orphans when its work bead closes and then stays open forever, so classify
#      handed the operator transient machine scaffolding as work needing a
#      disposition — 40 open city-wide when this was filed, seven of them in the
#      gc-toolkit ready set that day. gc-helm.sh and supervisor.go both already
#      dropped exactly these two title prefixes; the sweep that GENERATES the
#      operator's work did not. Its inverse defect is new here and not present in
#      either of those two: they read `gc convoy list` and see only convoys,
#      while this block reads every ready bead, so a title-prefix test alone
#      would hide a real bug whose TITLE talks about a convoy. Hence the
#      issue_type=convoy guard.
#
# The four computational blocks are EXTRACTED VERBATIM from the shipped formula
# (`# >>> open-prs` / `# >>> worked-via-convoy` / `# >>> classify-candidates` /
# `# >>> sweep-delta`) and executed against fixtures, so the test cannot drift
# from the instruction an agent actually runs. Hermetic: reads the repo, stubs
# `gc` and `gh`; no city, no Dolt, no network.
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
extract worked-via-convoy   "$FORMULA" > "$TMP/worked.sh"
extract stamp-handoff       "$FORMULA" > "$TMP/stamp.sh"
extract read-handoff        "$FORMULA" > "$TMP/read.sh"
extract landed-husks        "$FORMULA" > "$TMP/husk.sh"
extract refile-guard        "$FORMULA" > "$TMP/refile.sh"
[ -s "$TMP/classify.sh" ] || { echo "no marked classify-candidates block"; exit 1; }
[ -s "$TMP/delta.sh" ]    || { echo "no marked sweep-delta block"; exit 1; }
[ -s "$TMP/openprs.sh" ]  || { echo "no marked open-prs block"; exit 1; }
[ -s "$TMP/worked.sh" ]   || { echo "no marked worked-via-convoy block"; exit 1; }
[ -s "$TMP/stamp.sh" ]    || { echo "no marked stamp-handoff block"; exit 1; }
[ -s "$TMP/read.sh" ]     || { echo "no marked read-handoff block"; exit 1; }
[ -s "$TMP/husk.sh" ]     || { echo "no marked landed-husks block"; exit 1; }
[ -s "$TMP/refile.sh" ]   || { echo "no marked refile-guard block"; exit 1; }

echo "── the extracted blocks are valid shell ──"
bash -n "$TMP/classify.sh" && ok "classify-candidates: valid bash" \
    || bad "classify-candidates: valid bash" "bash -n failed"
bash -n "$TMP/delta.sh" && ok "sweep-delta: valid bash" \
    || bad "sweep-delta: valid bash" "bash -n failed"
bash -n "$TMP/openprs.sh" && ok "open-prs: valid bash" \
    || bad "open-prs: valid bash" "bash -n failed"
bash -n "$TMP/worked.sh" && ok "worked-via-convoy: valid bash" \
    || bad "worked-via-convoy: valid bash" "bash -n failed"
bash -n "$TMP/stamp.sh" && ok "stamp-handoff: valid bash" \
    || bad "stamp-handoff: valid bash" "bash -n failed"
bash -n "$TMP/read.sh" && ok "read-handoff: valid bash" \
    || bad "read-handoff: valid bash" "bash -n failed"
bash -n "$TMP/husk.sh" && ok "landed-husks: valid bash" \
    || bad "landed-husks: valid bash" "bash -n failed"
bash -n "$TMP/refile.sh" && ok "refile-guard: valid bash" \
    || bad "refile-guard: valid bash" "bash -n failed"

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
for blk in classify.sh delta.sh openprs.sh worked.sh stamp.sh read.sh husk.sh refile.sh; do
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
  {"id":"c-pattern","title":"pattern: a distiller cluster anchor","issue_type":"task","metadata":{"task_kind":"feedback-pattern"}},
  {"id":"c-docupdate","title":"a doc-update bead nobody has routed","issue_type":"task","metadata":{"task_kind":"doc-update"}},
  {"id":"c-ingroup","title":"subject of a live visit","issue_type":"task","metadata":{}},
  {"id":"c-takeaway","title":"parked by a human","issue_type":"epic","metadata":{"gc.takeaway":"needs operator ratify; resume on ping","gc.takeaway_by":"proactive"}},
  {"id":"c-takeaway-empty","title":"hold was cleared","issue_type":"task","metadata":{"gc.takeaway":""}},
  {"id":"c-pr-open","title":"done, parked on an open PR awaiting approval","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521","pr_url":"https://github.com/zookanalytics/signal-loom/pull/521"}},
  {"id":"c-pr-case","title":"same PR, written with a different case and a trailing path","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"522","pr_url":"https://GitHub.com/zookanalytics/signal-loom/pull/522/files"}},
  {"id":"c-pr-merged","title":"landed — finishable, must surface for close-out","issue_type":"task","metadata":{"merge_result":"merged","pr_number":"520","pr_url":"https://github.com/zookanalytics/signal-loom/pull/520"}},
  {"id":"c-pr-closed","title":"rejected — PR closed unmerged, needs a sitting","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"999","pr_url":"https://github.com/zookanalytics/signal-loom/pull/999"}},
  {"id":"c-pr-otherrepo","title":"number 521 — but in a different repository","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521","pr_url":"https://github.com/someone/elsewhere/pull/521"}},
  {"id":"c-pr-nourl","title":"marker but no pr_url to check liveness against","issue_type":"task","metadata":{"merge_result":"pull_request","pr_number":"521"}},
  {"id":"c-preopen-green","title":"pre-open, codex green, review closed — waits on pre-open-resolve","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"green@756d5d7d3"}},
  {"id":"c-preopen-multigreen","title":"pre-open, two gates both green (spaced list)","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex, ci","check.codex":"green@aa11","check.ci":"green@aa11"}},
  {"id":"c-preopen-approval","title":"pre-open, codex green + non-marker approval sentinel","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,approval","check.codex":"green@bb22"}},
  {"id":"c-preopen-fixable","title":"pre-open, fixable verdict, nothing in flight — genuinely stalled","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"fixable@4b366f6f"}},
  {"id":"c-preopen-partial","title":"pre-open, two gates but one marker absent","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,ci","check.codex":"green@cc33"}},
  {"id":"c-preopen-nomarker","title":"pre-open, check_set names codex but no marker at all","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
  {"id":"c-preopen-noset","title":"pre-open, green marker but check_set unset","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check.codex":"green@dd44"}},
  {"id":"c-preopen-none","title":"pre-open, check_set=none opt-out — no positive green evidence","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"none"}},
  {"id":"c-hold","title":"operator decided this waits","issue_type":"task","metadata":{"triage.hold":"deferred; operator may take a different direction","triage.hold_by":"operator"}},
  {"id":"c-hold-bare","title":"held, but the stamp names no reason","issue_type":"task","metadata":{"triage.hold":"true"}},
  {"id":"c-hold-empty","title":"hold was cleared","issue_type":"task","metadata":{"triage.hold":""}},
  {"id":"c-worked","title":"a work bead a live molecule is driving","issue_type":"bug","metadata":{}},
  {"id":"c-husk-tracked","title":"tracked only by a dead synthetic convoy","issue_type":"bug","metadata":{}},
  {"id":"c-inputconvoy","title":"input convoy for c-plain","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-slingconvoy","title":"sling-c-plain","issue_type":"convoy"},
  {"id":"c-synthconvoy","title":"a convoy the machinery minted under some other name","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-realconvoy","title":"an unowned floating convoy — the orphan the observer must CATCH","issue_type":"convoy","metadata":{}},
  {"id":"c-titletalk","title":"input convoy for tk-x never closes once its work bead lands","issue_type":"bug","metadata":{}},
  {"id":"c-slingtalk","title":"sling-created convoys are never reaped","issue_type":"bug","metadata":{}},
  {"id":"c-husk-step-1","title":"Load context and verify assignment","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-husk-step-2","title":"Implement the solution","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-live-step","title":"a step of a workflow whose anchor is still in flight","issue_type":"task","metadata":{"gc.root_bead_id":"root-live"}},
  {"id":"c-noconvoy-step","title":"a step whose root names no input convoy","issue_type":"task","metadata":{"gc.root_bead_id":"root-noconvoy"}},
  {"id":"c-rootvisit-step","title":"a step of a root a live stall visit already names","issue_type":"task","metadata":{"gc.root_bead_id":"root-underconversation"}}
]
JSON
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"v-1","title":"visit: c-ingroup — a live sitting","metadata":{"task_kind":"visit","gc.continuation_group":"c-ingroup"}},
  {"id":"v-stall","title":"visit: root-underconversation — workflow stalled with an unclaimable frontier","metadata":{"task_kind":"visit","gc.continuation_group":"subj-stalled","stall_root":"root-underconversation"}}
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

# The worked half of class 1 (bead tk-8rm3q). A `gc` stub answering
# `gc bd show <convoy>` from per-id fixtures in $CONVOY_DIR, emitting the gc bd
# SHOW dependency shape (.dependency_type + .id) — NOT the gc bd LIST shape
# (.type + .depends_on_id). The block MUST read the show shape; a fixture in the
# show shape read with the wrong key would yield nothing, so "c-worked dropped"
# below is exactly what pins the key against a silent regression. GC_CONVOY_FAIL
# makes one convoy read fail the way a real outage does (non-zero, no output).
mkdir -p "$TMP/bin" "$TMP/convoys"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# `gc bd list` — the refile-guard's closed-visit read. Serves $PRIOR_VISITS when
# set; with it unset the stub prints nothing, which is how an unreadable listing
# looks and is exactly the fail-open case the guard must survive.
if [ "$1" = "bd" ] && [ "$2" = "list" ]; then
    if [ -n "${GC_LIST_FAIL:-}" ]; then exit 1; fi
    if [ -n "${PRIOR_VISITS:-}" ] && [ -f "$PRIOR_VISITS" ]; then cat "$PRIOR_VISITS"; fi
    exit 0
fi
[ "$1" = "bd" ] && [ "$2" = "show" ] || exit 0
id="$3"
[ -n "${GC_CONVOY_FAIL:-}" ] && [ "$id" = "$GC_CONVOY_FAIL" ] && exit 1
# GC_SHOW_FAIL is a space-separated id list; a real outage is non-zero and silent.
case " ${GC_SHOW_FAIL:-} " in *" $id "*) exit 1 ;; esac
f="$CONVOY_DIR/$id.json"
[ -f "$f" ] && cat "$f" || printf '%s\n' '[]'
GC
chmod +x "$TMP/bin/gc"
export CONVOY_DIR="$TMP/convoys"
# conv-live is named by a LIVE molecule in ALIVE and tracks c-worked → worked.
printf '%s\n' '[{"id":"conv-live","issue_type":"convoy","dependencies":[{"id":"c-worked","dependency_type":"tracks","status":"open"}],"dependents":null}]' > "$TMP/convoys/conv-live.json"
# conv-husk tracks c-husk-tracked but NO live bead names it → never read, and
# even if it were, its member is not coverage. This is the husk, the hard half.
printf '%s\n' '[{"id":"conv-husk","issue_type":"convoy","metadata":{"gc.synthetic":"true"},"dependencies":[{"id":"c-husk-tracked","dependency_type":"tracks","status":"open"}],"dependents":null}]' > "$TMP/convoys/conv-husk.json"
# ALIVE is the not-closed set the block reads input convoys from. m-live is a
# live molecule naming conv-live; nothing names conv-husk.
cat > "$TMP/alive.json" <<'JSON'
[
  {"id":"m-live","title":"a live molecule driving a work bead","metadata":{"gc.input_convoy_id":"conv-live"}},
  {"id":"c-worked","title":"a work bead a live molecule is driving","metadata":{}},
  {"id":"c-husk-tracked","title":"tracked only by a dead synthetic convoy","metadata":{}}
]
JSON
# Exported like LIVE/READY: the block reads $ALIVE, and shellcheck cannot follow
# the sourced file to see the read, so export marks it used-externally (SC2034).
ALIVE="$TMP/alive.json"; export ALIVE
# shellcheck disable=SC1090
. "$TMP/worked.sh"
echo "── worked-via-convoy resolves live molecules FORWARD to the work beads they drive ──"
eq "$CONVOY_LIVENESS" "verified" "every convoy a live molecule names answered → verified"
eq "$(printf '%s' "$WORKED" | jq -r 'sort | join(",")')" "c-worked" \
   "only a LIVE-named convoy's member is worked; a husk-tracked bead is not"

# Class 0(b), the landed-anchor husk (bead tk-st143). The chain the block walks
# is root -> gc.input_convoy_id -> tracks member -> that anchor's own state, so
# the fixtures are one file per link. root-landed's anchor is closed AND merged:
# the workflow is finished and its step beads are teardown backlog. root-live's
# anchor carries merge_result=pull_request, which is the whole discrimination —
# a marker a LIVE molecule wears mid-flight (a rework anchor carries it from the
# round being reworked), so its steps stay candidates. root-noconvoy names no
# input convoy at all: nothing to have landed, so not a husk either.
printf '%s\n' '[{"id":"root-landed","issue_type":"task","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"conv-landed"}}]' > "$TMP/convoys/root-landed.json"
printf '%s\n' '[{"id":"conv-landed","issue_type":"convoy","dependencies":[{"id":"anchor-landed","dependency_type":"tracks","status":"closed"}],"dependents":null}]' > "$TMP/convoys/conv-landed.json"
printf '%s\n' '[{"id":"anchor-landed","status":"closed","metadata":{"merge_result":"merged","pr_number":"57"}}]' > "$TMP/convoys/anchor-landed.json"
printf '%s\n' '[{"id":"root-live","issue_type":"task","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"conv-anchorlive"}}]' > "$TMP/convoys/root-live.json"
printf '%s\n' '[{"id":"conv-anchorlive","issue_type":"convoy","dependencies":[{"id":"anchor-live","dependency_type":"tracks","status":"open"}],"dependents":null}]' > "$TMP/convoys/conv-anchorlive.json"
printf '%s\n' '[{"id":"anchor-live","status":"open","metadata":{"merge_result":"pull_request","pr_number":"58"}}]' > "$TMP/convoys/anchor-live.json"
printf '%s\n' '[{"id":"root-noconvoy","issue_type":"task","metadata":{"gc.kind":"workflow"}}]' > "$TMP/convoys/root-noconvoy.json"
# root-underconversation's anchor is OPEN and unmarked, so the husk rule keeps
# its step — which is what makes the root-fold assertion below attributable to
# the fold alone rather than to class 0(b) dropping it for another reason.
printf '%s\n' '[{"id":"root-underconversation","issue_type":"task","metadata":{"gc.kind":"workflow","gc.input_convoy_id":"conv-uc"}}]' > "$TMP/convoys/root-underconversation.json"
printf '%s\n' '[{"id":"conv-uc","issue_type":"convoy","dependencies":[{"id":"anchor-uc","dependency_type":"tracks","status":"open"}],"dependents":null}]' > "$TMP/convoys/conv-uc.json"
printf '%s\n' '[{"id":"anchor-uc","status":"open","metadata":{}}]' > "$TMP/convoys/anchor-uc.json"
# shellcheck disable=SC1090
. "$TMP/husk.sh"
echo "── landed-anchor husks resolve per ROOT, and only a landed anchor drops one ──"
eq "$HUSK_LIVENESS" "verified" "every root, convoy and anchor read → verified"
eq "$(printf '%s' "$HUSK_STEPS" | jq -r 'join(",")')" "c-husk-step-1,c-husk-step-2" \
   "every step bead of a landed root drops at once, and only those"
eq "$(printf '%s' "$HUSK_ROOTS" | jq -r 'join(",")')" "root-landed" \
   "the teardown set is the ROOT ids, which is what a reaper acts on"

# shellcheck disable=SC1090
. "$TMP/classify.sh"
SURVIVORS="$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | sort | join(",")')"

echo "── classify keeps only genuinely unnamed beads ──"
eq "$SURVIVORS" \
   "c-docupdate,c-hold-empty,c-husk-tracked,c-live-step,c-noconvoy-step,c-plain,c-pr-closed,c-pr-merged,c-pr-nourl,c-pr-otherrepo,c-preopen-fixable,c-preopen-nomarker,c-preopen-none,c-preopen-noset,c-preopen-partial,c-realconvoy,c-slingtalk,c-takeaway-empty,c-titletalk" \
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
            c-pattern:held-by-design-standing-record \
            c-ingroup:live-visit-in-group c-takeaway:takeaway-held \
            c-pr-open:gated-on-an-open-pr c-pr-case:gated-case-and-path-insensitive \
            c-hold:operator-held c-hold-bare:operator-held-reasonless; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done

# The inverse for class 4(a) (bead tk-rw2ra). `standing_kinds` is a MEMBERSHIP
# test, not "carries a task_kind at all" — the over-broad rule that would hide
# every kind-stamped bead. A doc-update bead is ordinary work: nothing has
# routed it, so it is exactly the unnamed wait this sweep exists to surface.
echo "── a task_kind outside the standing list is ordinary work and stays visible ──"
for keep in c-docupdate:a-kind-stamp-is-not-a-standing-record-unless-listed; do
    id="${keep%%:*}"; why="${keep##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && ok "kept $id ($why)" || bad "kept $id ($why)" "was hidden — the inverse defect"
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

# Class 2's OTHER gate: merge_result=pre_open_gate (bead tk-5ttye). The old
# carve-out assumed a pre-open anchor never reaches the candidate set (the review
# bead's `blocks` edge), which fails the moment that review CLOSES — its gate is
# then verdict-based on the anchor's own markers, not an open PR. A pre-open
# anchor with every check_set gate recorded green@ is waiting on
# pre-open-resolve.sh: a NAMED wait, dropped.
echo "── a pre-open anchor, all gates green, is a named wait and drops ──"
for drop in c-preopen-green:codex-green-review-closed-waits-on-pre-open-resolve \
            c-preopen-multigreen:every-gate-in-a-spaced-list-green \
            c-preopen-approval:non-marker-approval-sentinel-dropped-codex-green; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done

# The inverse defect for the pre-open gate: the same "carries pre_open_gate, skip
# it" naivety would hide a fixable verdict with nothing in flight (genuinely
# stalled), or an absent/unset marker (the tk-t46nq / tk-qs1j6 hole). Each must
# stay VISIBLE — the verdict-based test drops ONLY positive all-green evidence.
echo "── a pre-open marker is not a gate: non-green, absent, or unset stays visible ──"
for keep in c-preopen-fixable:fixable-with-nothing-in-flight-is-stalled-work \
            c-preopen-partial:one-of-two-gates-unmarked-so-not-all-green \
            c-preopen-nomarker:check_set-names-a-gate-but-no-marker-at-all \
            c-preopen-noset:a-green-marker-but-check_set-unset \
            c-preopen-none:the-none-opt-out-is-no-positive-green-evidence; do
    id="${keep%%:*}"; why="${keep##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && ok "kept $id ($why)" || bad "kept $id ($why)" "was hidden — the inverse defect"
done

# Class 1's molecule indirection and its husk (bead tk-8rm3q). c-worked is
# tracked by conv-live, which a LIVE molecule (m-live) names → dropped as
# worked. c-husk-tracked is tracked by conv-husk, which NO live bead names → it
# is NOT coverage and the bead stays a candidate; dropping on the tracks edge
# alone would hide it, the inverse defect the husk rule exists to prevent.
echo "── class 1: a molecule-driven work bead is dropped; a husk-tracked one is kept ──"
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-worked")' >/dev/null 2>&1 \
    && bad "dropped c-worked (worked-via-convoy)" "still a candidate" \
    || ok "dropped c-worked (worked-via-convoy)"
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-husk-tracked")' >/dev/null 2>&1 \
    && ok "kept c-husk-tracked (husk convoy — no live namer is not coverage)" \
    || bad "kept c-husk-tracked (husk)" "was hidden — dropped on the tracks edge alone"

# Class 0 (bead tk-gri6a): the machine convoys the machinery mints for its own
# bookkeeping are not work. Same two title prefixes gc-helm.sh:1118 and
# supervisor.go gatherConvoys already drop, plus gc.synthetic. Note c-slingconvoy
# carries NO metadata key at all — the shape measured on the live store, and the
# one a gc.synthetic-only filter would silently miss.
echo "── class 0: machine convoy scaffolding is not work and drops ──"
for drop in c-inputconvoy:the-per-sling-input-convoy-wrapper \
            c-slingconvoy:a-sling-convoy-carrying-no-metadata-at-all \
            c-synthconvoy:gc.synthetic-catches-a-machine-convoy-under-another-name; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done

# THE INVERSE DEFECT of class 0, which does not exist in gc-helm.sh or
# supervisor.go: those two read `gc convoy list` and see only convoys, while this
# block reads every ready bead of every type. A bare title-prefix test would hide
# a real bug whose TITLE talks about a machine convoy — including the beads
# filed against this very defect. The issue_type=convoy guard is what prevents
# it, and a non-machine convoy stays visible because an unowned floating convoy
# is the orphan the observer must CATCH, not residue to hide.
echo "── class 0 drops what the machinery minted, never what merely names it ──"
for keep in c-titletalk:a-bug-whose-title-starts-with-input-convoy-for \
            c-slingtalk:a-bug-whose-title-starts-with-sling- \
            c-realconvoy:a-non-machine-unowned-convoy-is-the-orphan-to-catch; do
    id="${keep%%:*}"; why="${keep##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && ok "kept $id ($why)" || bad "kept $id ($why)" "was hidden — the inverse defect"
done

# Class 0(b) (bead tk-st143): a graph.v2 workflow whose ANCHOR landed owes no
# more work, but mol-polecat-work closes no step ever, so its step beads stay
# open, stay ready, and arrive as unnamed waits on every pass — 16 of them across
# two dead roots in the incident this was written for. There is no disposition a
# sitting can take on one: routing it re-implements landed work on a branch whose
# PR already merged. They are teardown backlog, and a reaper retires them.
echo "── class 0(b): the step beads of a landed workflow are teardown, not waits ──"
for drop in c-husk-step-1:a-step-of-a-root-whose-anchor-closed-and-merged \
            c-husk-step-2:every-step-of-that-root-drops-not-just-the-frontier; do
    id="${drop%%:*}"; why="${drop##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && bad "dropped $id ($why)" "still a candidate" || ok "dropped $id ($why)"
done

# THE INVERSE DEFECT of class 0(b), and the one that made two live stalls
# invisible in the sibling implementation of this test: every OTHER
# terminal-looking marker is a state a live molecule wears mid-flight.
# merge_result=pull_request in particular is what a REWORK molecule's anchor
# already carries from the round being reworked, so reading it as completion
# hides a workflow that is genuinely in flight.
echo "── only closed-or-merged is landed: a mid-flight marker keeps its steps visible ──"
for keep in c-live-step:merge_result-pull_request-is-mid-flight-not-landed \
            c-noconvoy-step:a-root-naming-no-convoy-has-no-anchor-to-have-landed; do
    id="${keep%%:*}"; why="${keep##*:}"
    printf '%s' "$CANDIDATES" | jq -e --arg i "$id" 'any(.[]; .id == $i)' >/dev/null 2>&1 \
        && ok "kept $id ($why)" || bad "kept $id ($why)" "was hidden — the inverse defect"
done

# Class 3's root fold, the cross-FORMULA half (bead tk-st143). A root-scoped
# stall visit hangs off the stalled-workflows subject and this sweep's batch
# visit off the unnamed-waits subject, so gc.continuation_group can never fold
# them: both filed, about one frozen workflow, and the operator held three
# concurrent sittings on the same shape. The key is gc.root_bead_id matched
# against a live visit's stall_root. c-rootvisit-step's own root has an OPEN,
# unmarked anchor, so class 0(b) keeps it — the fold is the only thing that can
# drop it, which is what makes this assertion attributable.
echo "── class 3: a candidate whose ROOT is already under a live visit folds into it ──"
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-rootvisit-step")' >/dev/null 2>&1 \
    && bad "dropped c-rootvisit-step (a live visit names its root)" "still a candidate" \
    || ok "dropped c-rootvisit-step (a live visit names its root)"
# The inverse: the fold is a MEMBERSHIP test against the stall_root values, not
# "carries a gc.root_bead_id at all" — the over-broad rule would hide every step
# bead in the rig, which is the population this sweep most needs to see.
printf '%s' "$CANDIDATES" | jq -e 'any(.[]; .id == "c-live-step")' >/dev/null 2>&1 \
    && ok "kept c-live-step (a root no live visit names is not under conversation)" \
    || bad "kept c-live-step" "the root fold dropped a root nothing is conversing about"

# The husk probe is three-valued exactly as the other two, and a failed read
# REPORTS: the root contributes no husk steps, so its candidates stay visible.
# Its own READY fixture, so the verified run above keeps its word.
echo "── the landed-husk probe is three-valued and reports rather than hides ──"
printf '%s\n' '[{"id":"c-orphan-step","title":"a step whose root cannot be read","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}}]' > "$TMP/ready-husk.json"
HUSK_SAVE_STEPS="$HUSK_STEPS"; HUSK_SAVE_ROOTS="$HUSK_ROOTS"; HUSK_SAVE_LIVENESS="$HUSK_LIVENESS"
READY="$TMP/ready-husk.json"; GC_SHOW_FAIL="anchor-landed"; export GC_SHOW_FAIL
# shellcheck disable=SC1090
. "$TMP/husk.sh"
eq "$HUSK_LIVENESS" "unverified" "a failed anchor read is 'unverified', never a silent empty"
eq "$(printf '%s' "$HUSK_STEPS" | jq 'length')" "0" \
   "a failed read contributes no husk steps (the bead stays a candidate, reported)"
unset GC_SHOW_FAIL
printf '%s\n' '[{"id":"c-plain","title":"an ordinary idle bug","issue_type":"bug"}]' > "$TMP/ready-noroot.json"
READY="$TMP/ready-noroot.json"
# shellcheck disable=SC1090
. "$TMP/husk.sh"
eq "$HUSK_LIVENESS" "none" "no ready bead names a workflow root → 'none', distinct from the other two"
READY="$TMP/ready.json"
HUSK_STEPS="$HUSK_SAVE_STEPS"; HUSK_ROOTS="$HUSK_SAVE_ROOTS"; HUSK_LIVENESS="$HUSK_SAVE_LIVENESS"

# Under 'set -e', where recording the failure is HARDER than aborting — the same
# control the open-prs and worked-via-convoy blocks carry. The healthy read is
# run the same way as a positive control, so a future edit that breaks
# errexit-safety anywhere in the block fails here rather than passing vacuously.
echo "── the landed-husk read survives 'set -e', which is where reporting is hard ──"
# shellcheck disable=SC2016  # $1/$HUSK_LIVENESS are for the CHILD shell to expand
HUSKX_RUN='. "$1"; printf "%s" "$HUSK_LIVENESS"'
HUSKX_FAIL="$(GC_SHOW_FAIL=anchor-landed READY="$TMP/ready.json" CONVOY_DIR="$TMP/convoys" \
    bash -e -c "$HUSKX_RUN" _ "$TMP/husk.sh" 2>/dev/null)"
eq "$HUSKX_FAIL" "unverified" \
   "under 'set -e' a failed anchor read still records 'unverified' (never aborts the pass)"
HUSKX_OK="$(READY="$TMP/ready.json" CONVOY_DIR="$TMP/convoys" \
    bash -e -c "$HUSKX_RUN" _ "$TMP/husk.sh" 2>/dev/null)"
eq "$HUSKX_OK" "verified" "…and a healthy read runs to completion under 'set -e' too"

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

# The worked-via-convoy liveness word is three-valued exactly as PR_LIVENESS:
# 'none' (no non-closed bead named a convoy), 'verified' (all reads answered),
# 'unverified' (a read failed). A failed read never hides a bead — the member is
# simply not marked worked, so it stays a candidate and is reported — but the
# sitting is owed the word or a list of actively-worked beads reads as a backlog.
echo "── the worked-via-convoy probe is three-valued and reports rather than hides ──"
printf '%s\n' '[{"id":"x","metadata":{}}]' > "$TMP/alive-none.json"
ALIVE="$TMP/alive-none.json"
# shellcheck disable=SC1090
. "$TMP/worked.sh"
eq "$CONVOY_LIVENESS" "none" "no convoy named → 'none', distinct from verified and unverified"
eq "$(printf '%s' "$WORKED" | jq 'length')" "0" "nothing named → nothing marked worked"
ALIVE="$TMP/alive.json"; GC_CONVOY_FAIL=conv-live; export GC_CONVOY_FAIL
# shellcheck disable=SC1090
. "$TMP/worked.sh"
eq "$CONVOY_LIVENESS" "unverified" "a failed convoy read is 'unverified', never a silent empty"
printf '%s' "$WORKED" | jq -e 'any(.[]; . == "c-worked")' >/dev/null 2>&1 \
    && bad "a failed read hides nothing" "c-worked was marked worked despite the read failing" \
    || ok "a failed read contributes no worked ids (the bead stays a candidate, reported)"
unset GC_CONVOY_FAIL

# Under 'set -e', where recording the failure is HARDER than aborting — the same
# control as the open-prs errexit test. A bare ROWS=$(gc ...) assignment would
# let errexit kill the pass on the very transient the else arm exists to report.
echo "── the worked-via-convoy read survives 'set -e' ──"
# shellcheck disable=SC2016
ERRX_WVC='. "$1"; printf "%s" "$CONVOY_LIVENESS"'
ERRX_WVC_FAIL="$(GC_CONVOY_FAIL=conv-live ALIVE="$TMP/alive.json" CONVOY_DIR="$TMP/convoys" PATH="$TMP/bin:$PATH" \
    bash -e -c "$ERRX_WVC" _ "$TMP/worked.sh" 2>/dev/null)"
eq "$ERRX_WVC_FAIL" "unverified" \
   "under 'set -e' a failed convoy read still records 'unverified' (never aborts the pass)"
ERRX_WVC_OK="$(ALIVE="$TMP/alive.json" CONVOY_DIR="$TMP/convoys" PATH="$TMP/bin:$PATH" \
    bash -e -c "$ERRX_WVC" _ "$TMP/worked.sh" 2>/dev/null)"
eq "$ERRX_WVC_OK" "verified" "…and a healthy read runs to completion under 'set -e' too"

# --- the classify→normalize handoff (bead tk-7uvm9) --------------------------
# classify and normalize are separate step beads and the pool re-offers each, so
# NO shell state crosses between them: classify stamps the post-edge-check
# survivors + both liveness words + its outcome on the ROOT bead, and normalize
# reads them back via its own gc.root_bead_id. These two blocks are that
# contract; before it, normalize inherited $CANDIDATES/$PR_LIVENESS from a shell
# it did not share and a fresh session had nothing to read.
echo "── stamp-handoff derives survivors = candidates − edge-drops and stamps the root ──"
# A gc stub that CAPTURES `bd update <root> --set-metadata …` so the stamp itself
# can be asserted. stamp-handoff takes the root from $ROOT (set in prose from the
# step bead's gc.root_bead_id), so no `bd show` is needed here.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "bd" ] && [ "$2" = "update" ]; then
    shift 2
    printf '%s\n' "$@" >> "$STAMP_CAP"
    exit 0
fi
exit 0
GC
chmod +x "$TMP/bin/gc"
PATH="$TMP/bin:$PATH"; export PATH
STAMP_CAP="$TMP/stamp-cap.txt"; export STAMP_CAP
: > "$STAMP_CAP"

ROOT="tk-root"; export ROOT
CANDIDATES="$(jq -nc '[{id:"s-1",title:"one",type:"bug"},{id:"s-2",title:"two",type:"task"},{id:"s-3",title:"three — dropped by the edge check",type:"epic"}]')"
export CANDIDATES
PR_LIVENESS="verified"; CONVOY_LIVENESS="none"; export PR_LIVENESS CONVOY_LIVENESS
EDGE_DROPS="s-3"; export EDGE_DROPS
# shellcheck disable=SC1090
. "$TMP/stamp.sh"
eq "$(printf '%s' "$SURVIVORS" | jq -r '[.[].id] | join(",")')" "s-1,s-2" \
   "the edge-check drop (s-3) is removed; s-1 and s-2 survive"
has "the stamp carries the survivor candidates" "sweep.candidates=[" "$STAMP_CAP"
has "the stamp carries pr liveness"     "sweep.pr_liveness=verified"   "$STAMP_CAP"
has "the stamp carries convoy liveness" "sweep.convoy_liveness=none"   "$STAMP_CAP"
has "the stamp records the pass outcome" "sweep.classify_outcome=pass" "$STAMP_CAP"

echo "── stamp-handoff with no edge drops keeps every candidate ──"
EDGE_DROPS=""; export EDGE_DROPS
# shellcheck disable=SC1090
. "$TMP/stamp.sh"
eq "$(printf '%s' "$SURVIVORS" | jq -r '[.[].id] | join(",")')" "s-1,s-2,s-3" \
   "empty EDGE_DROPS → the survivor set is the full candidate set"

echo "── a malformed survivor set refuses to stamp (fail-closed, no partial handoff) ──"
( CANDIDATES='not json' EDGE_DROPS="" ROOT="tk-root" \
    bash -c '. "$1"' _ "$TMP/stamp.sh" >/dev/null 2>&1 ) \
  && bad "malformed CANDIDATES aborts the stamp" "block exited 0 on non-array input" \
  || ok "malformed CANDIDATES aborts the stamp"

echo "── read-handoff reads the survivor set and liveness words back from the root ──"
# A gc stub answering `gc bd show <root> --json` from $FAKE_ROOT — the raw
# payload, so a case can inject a missing key or the exact shape bd stores: a
# JSON-valued metadata is a STRING holding escaped JSON (verified against the
# live store), so the survivor array must survive a string → fromjson round-trip.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] && [ "$2" = "show" ] || exit 0
printf '%s\n' "${FAKE_ROOT:-[]}"
GC
chmod +x "$TMP/bin/gc"
ROOT="tk-root"; export ROOT
CANDS_JSON='[{"id":"s-1","title":"one","type":"bug"},{"id":"s-2","title":"two","type":"task"}]'
FAKE_ROOT="$(jq -nc --arg c "$CANDS_JSON" '[{"metadata":{"sweep.classify_outcome":"pass","sweep.candidates":$c,"sweep.pr_liveness":"unverified","sweep.convoy_liveness":"verified"}}]')"
export FAKE_ROOT
# shellcheck disable=SC1090
. "$TMP/read.sh"
eq "$HANDOFF_STATE" "ok" "a pass with a readable JSON-string survivor set → ok"
eq "$(printf '%s' "$CANDIDATES" | jq -r '[.[].id] | join(",")')" "s-1,s-2" \
   "the survivor set is recovered as an array (bd stores it as a string → fromjson)"
eq "$PR_LIVENESS" "unverified" "the pr liveness word is read back"
eq "$CONVOY_LIVENESS" "verified" "the convoy liveness word is read back"

echo "── read-handoff distinguishes classify-failed from an unreadable handoff ──"
FAKE_ROOT="$(jq -nc '[{"metadata":{"sweep.classify_outcome":"fail"}}]')"; export FAKE_ROOT
# shellcheck disable=SC1090
. "$TMP/read.sh"
eq "$HANDOFF_STATE" "classify-failed" "outcome != pass → classify-failed (a known transient)"
# The distinct branch the bead exists for: classify SAID pass but the survivor
# stamp is gone — the old bare-outcome read could not tell this from a clean run.
FAKE_ROOT="$(jq -nc '[{"metadata":{"sweep.classify_outcome":"pass"}}]')"; export FAKE_ROOT
# shellcheck disable=SC1090
. "$TMP/read.sh"
eq "$HANDOFF_STATE" "unreadable" "outcome=pass but sweep.candidates absent → unreadable, not ok"
eq "$PR_LIVENESS" "unverified" "an absent liveness word defaults to unverified (report, don't hide)"
# outcome=pass but the stamp is present-but-not-an-array (corruption/truncation).
FAKE_ROOT="$(jq -nc '[{"metadata":{"sweep.classify_outcome":"pass","sweep.candidates":"{not an array"}}]')"; export FAKE_ROOT
# shellcheck disable=SC1090
. "$TMP/read.sh"
eq "$HANDOFF_STATE" "unreadable" "outcome=pass but the survivor stamp is unparseable → unreadable"

# --- 2. the delta split ------------------------------------------------------
# `gc` stub: the one read the block performs (gc bd show <subject> --json).
# FAKE_SUBJECT is the raw payload, so a case can inject a missing baseline or a
# control character in the notes.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
# `gc bd list` is the refile-guard's closed-visit read. With $PRIOR_VISITS unset
# the stub prints nothing, which is what an unreadable listing looks like and is
# the fail-open case the guard must survive. $GC_LIST_RC sets the read's exit
# status INDEPENDENTLY of what it printed, because that is the combination the
# guard has to get right: a real failure can arrive having already emitted a
# perfectly well-formed page.
if [ "$1" = "bd" ] && [ "$2" = "list" ]; then
    if [ -n "${PRIOR_VISITS:-}" ] && [ -f "$PRIOR_VISITS" ]; then cat "$PRIOR_VISITS"; fi
    exit "${GC_LIST_RC:-0}"
fi
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

# --- 2b. the re-file guard (bead tk-st143) -----------------------------------
# THE DEFECT. The step-3 skip deliberately does not advance the baseline, and a
# baseline can also be lost or reset, so the same NEW set can come round again
# after a sitting has already worked it. It did: su-qoma was a verbatim re-file
# of su-7j8b — same title, same set — which su-7j8b had closed out two days
# earlier with gc.outcome=dispositioned. The guard asks whether a CLOSED visit
# on this subject already carried exactly this agenda and disposed of it.
prior_visits() { # prior_visits <outcome> <new_ids-csv> [id]
    printf '[{"id":"%s","metadata":{"task_kind":"visit","gc.outcome":"%s","sweep.new_ids":"%s"}}]' \
        "${3:-v-prior}" "$1" "$2" > "$TMP/prior.json"
    PRIOR_VISITS="$TMP/prior.json"; export PRIOR_VISITS
}
run_refile() { # run_refile — needs $NEW from run_delta; sets REFILE_SUPPRESSED
    # shellcheck disable=SC1090
    . "$TMP/refile.sh"
}

echo "── the re-file guard suppresses an agenda a sitting already dispositioned ──"
FAKE_SUBJECT="$(subject_json ABSENT)"; export FAKE_SUBJECT
run_delta a b c
prior_visits dispositioned "a,b,c" v-done
run_refile
eq "$REFILE_SUPPRESSED" "v-done" "the same NEW set, already dispositioned, is not re-filed"

# The test is the id SET, not the title and not the string: the title is a pair
# of counts that collide by accident, and a stored list in another order is the
# same agenda. "Unless the underlying candidate set actually changed" is what
# the guard has to mean.
prior_visits dispositioned "c,a,b" v-order
run_refile
eq "$REFILE_SUPPRESSED" "v-order" "the comparison is a SET, so a different id order still matches"

echo "── and files in every case where the agenda is not proven disposed of ──"
prior_visits dispositioned "a,b" v-subset
run_refile
eq "$REFILE_SUPPRESSED" "" "a genuinely different candidate set files"
# gc.outcome is the sitting's own one-word verdict and the words are not
# interchangeable: a visit closed `cut-short` ran out of time with its agenda
# un-worked, and re-filing it is exactly right.
prior_visits cut-short "a,b,c" v-cut
run_refile
eq "$REFILE_SUPPRESSED" "" "a cut-short sitting did NOT dispose of its agenda — file it again"
# A visit filed before the sweep.new_ids stamp shipped carries no set to compare.
prior_visits dispositioned "" v-nostamp
run_refile
eq "$REFILE_SUPPRESSED" "" "a prior visit with no stamped id set cannot match — file"
# Fail-open, like every other probe in this formula: an unreadable listing
# proves nothing was dispositioned.
unset PRIOR_VISITS
run_refile
eq "$REFILE_SUPPRESSED" "" "an unreadable closed-visit listing files rather than suppresses"
# ...and "unreadable" is a property of the READ, not of the shape of what
# arrived. A failing listing can print a page first — a truncated or partial one
# parses as a perfectly good array and can match the key exactly. Piping the read
# through `tr` threw its status away (a pipeline reports the LAST command, and tr
# succeeds on anything), so the guard trusted that page, suppressed the visit,
# and step 5 then advanced the baseline over an agenda nobody was ever shown.
# Only the rc check can catch this one: the payload IS a matching array, so the
# shape check passes on its own.
prior_visits dispositioned "a,b,c" v-failed
GC_LIST_RC=1; export GC_LIST_RC
run_refile
eq "$REFILE_SUPPRESSED" "" "a FAILING listing files, even when what it printed is a matching array"
# The control for that case: the very same payload, read successfully, does
# suppress — so what the case pins is the exit status and nothing else.
GC_LIST_RC=0
run_refile
eq "$REFILE_SUPPRESSED" "v-failed" "control: the identical payload read cleanly still suppresses"
unset GC_LIST_RC
# Nothing new at all: the guard has no question to ask and step 4 files nothing
# anyway. Pinned because an empty NEW_KEY must not match an empty stored list.
prior_visits dispositioned "" v-empty
FAKE_SUBJECT="$(subject_json "a,b,c")"; export FAKE_SUBJECT
run_delta a b c
eq "$NEW_COUNT" "0" "control: nothing is new this pass"
run_refile
eq "$REFILE_SUPPRESSED" "" "an empty NEW set never matches an empty stored list"
unset PRIOR_VISITS

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

# Class 2's pre-open gate half (bead tk-5ttye): the carve-out that dropped
# merge_result=pre_open_gate is gone, replaced by a verdict-based gate on the
# anchor's own check_set / check.<name> markers.
echo "── class 2 covers the pre-open gate as a distinct, verdict-based test ──"
has "the pre-open gate is now covered"    'pre_open_gate` IS covered'      "$FORMULA"
has "the gate reads check_set markers"    'check_set` names the required'  "$FORMULA"
has "the test is verdict-based not head"  'verdict-based'                  "$FORMULA"
has "an all-green pre-open anchor drops"  'every gate in `check_set` records' "$FORMULA"
has "a fixable-with-nothing-in-flight surfaces" 'nothing in flight'        "$FORMULA"

# Class 2(i)'s liveness test is "not closed", resolved against a widened set —
# so a convoy tracking a BLOCKED bead is gated, not a class-5 unnamed wait
# (bead tk-tnwo0, live case tk-dhue). LIVE is open+in_progress only, so a
# strict "present in LIVE" test drops blocked/deferred/pinned/hooked targets.
echo "── the edge check tests 'not closed', resolved against a widened ALIVE set ──"
has "the widening reads every non-closed status LIVE omits" 'blocked,deferred,pinned,hooked' "$FORMULA"
has "liveness is 'not closed', not 'present in LIVE'"       'not only when it is open'        "$FORMULA"
has "the edge check resolves against the widened set"       'against ALIVE'                   "$FORMULA"

# Class 1's worked-via-convoy discriminator and its husk rule (bead tk-8rm3q).
echo "── class 1 states the worked-via-convoy discriminator and its husk rule ──"
has "class 1 names the discriminator"         'worked-via-convoy'   "$FORMULA"
has "the input convoy is the signal"          'gc.input_convoy_id'  "$FORMULA"
has "the read is via gc bd show"              'gc bd show'          "$FORMULA"
has "the show key is dependency_type"         'dependency_type'     "$FORMULA"
has "the husk requires a live namer"          'LIVE NAMER'          "$FORMULA"
has "a tracks edge alone is not coverage"     'not itself coverage' "$FORMULA"
# shellcheck disable=SC2016
has "unverified convoy liveness is disclosed" '`$CONVOY_LIVENESS` is `unverified`' "$FORMULA"

# The classify→normalize handoff (bead tk-7uvm9): shell state does not cross a
# step-bead boundary, so classify stamps the survivor set on the ROOT bead and
# normalize reads it back via its own gc.root_bead_id, fail-closed and able to
# tell a classify that failed from one whose output is unreadable.
echo "── the classify→normalize handoff is machine state on the root, not prose ──"
has "the handoff rides the root bead"             'gc.root_bead_id'         "$FORMULA"
has "the survivor set is stamped as metadata"     'sweep.candidates'        "$FORMULA"
has "classify stamps its outcome for normalize"   'sweep.classify_outcome'  "$FORMULA"
has "the stamp precedes the step close"           'AFTER the stamp above'   "$FORMULA"
has "normalize distinguishes an unreadable handoff" 'UNREADABLE'            "$FORMULA"
has "normalize reads the live listing fresh"      'built fresh in step 1'   "$FORMULA"

echo
echo "liveness-sweep-delta: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
