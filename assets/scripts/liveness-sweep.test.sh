#!/usr/bin/env bash
# liveness-sweep.test.sh — hermetic tests for liveness-sweep.sh (stubbed
# gc/gh/escalate.sh; no city, Dolt, or network). Ports the delta and
# classification assertions from the retired liveness-sweep-delta.test.sh
# (which extracted blocks from formulas/mol-liveness-sweep.toml) and adds the
# exec-order surface: state-file baseline, escalate.sh filing, the census
# stamp, and the absorbed triage recurrence.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/liveness-sweep.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-liveness-sweep-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The census phases its pre-open gates against review-checks.toml; the SUT runs
# in place, so by default it would read the live pack's index and classify these
# fixtures' synthetic lanes (codex, ci) as non-pre-open. Point the override at a
# missing file so the census takes its pre-phase drop and these fixtures are
# judged on their lane names alone, hermetically. The phase-aware path has its
# own case at the end, with a controlled index.
export GC_REVIEW_CHECKS_INDEX="$TMP/no-such-index.toml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }

[ -x "$SCRIPT" ] || chmod +x "$SCRIPT" 2>/dev/null || true
bash -n "$SCRIPT" && ok "liveness-sweep.sh parses" || bad "liveness-sweep.sh parses" "bash -n failed"

mkdir -p "$TMP/bin" "$TMP/show"

# --- gc stub -------------------------------------------------------------------
# Serves the census reads from fixture files, `bd show` from $SHOW_DIR/<id>.json,
# the refile guard's closed listing from $PRIOR_VISITS, and records every write.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
sub="$1 ${2:-}"
args="$*"
case "$sub" in
  "bd ready")
    [ -n "${GC_READY_FAIL:-}" ] && exit 1
    cat "$FAKE_READY"; exit 0 ;;
  "bd list")
    case "$args" in
      *anchor_bead=*)
        # The edge-less wedge's lane fix-unit census: reworks for an anchor,
        # served from $SHOW_DIR/reworks-<anchor>.json (default []).
        aid=""
        for a in "$@"; do case "$a" in anchor_bead=*) aid="${a#anchor_bead=}"; break ;; esac; done
        f="$SHOW_DIR/reworks-$aid.json"
        if [ -f "$f" ]; then cat "$f"; else printf '[]\n'; fi
        exit 0 ;;
      *--status=closed*)
        # Model the server-side --metadata-field KEY=VALUE narrow: the store
        # returns only rows whose metadata[KEY] equals VALUE. A stamp-keyed
        # query (gc.continuation_group=<subject>) therefore hides a visit whose
        # stamp landed empty — the refile-guard defect. Without this the mock
        # would serve every prior regardless of the field, so a stamp-only query
        # and a task_kind query are indistinguishable and the bug cannot repro.
        if [ -n "${PRIOR_VISITS:-}" ] && [ -f "${PRIOR_VISITS:-}" ]; then
          mf=""; prev=""
          for a in "$@"; do
            [ "$prev" = "--metadata-field" ] && { mf="$a"; break; }
            case "$a" in --metadata-field=*) mf="${a#--metadata-field=}"; break ;; esac
            prev="$a"
          done
          if [ -n "$mf" ]; then
            jq --arg k "${mf%%=*}" --arg v "${mf#*=}" \
               '[.[] | select(((.metadata // {})[$k] // "") == $v)]' "$PRIOR_VISITS"
          else
            cat "$PRIOR_VISITS"
          fi
        fi
        exit "${GC_LIST_RC:-0}" ;;
      *blocked,deferred*) cat "${FAKE_WIDEN:-/dev/null}" 2>/dev/null || printf '[]'; exit 0 ;;
      *open,in_progress*) cat "$FAKE_LIVE"; exit 0 ;;
      *) printf '[]\n'; exit 0 ;;
    esac ;;
  "bd show")
    id="$3"
    case " ${GC_SHOW_FAIL:-} " in *" $id "*) exit 1 ;; esac
    f="$SHOW_DIR/$id.json"
    if [ -f "$f" ]; then cat "$f"; else printf '[]\n'; fi
    exit 0 ;;
  "bd dep")
    # `dep list <id> ...` → the finding's blockers, served from
    # $SHOW_DIR/dep-<id>.json (default []). Only the landed-fix-wedge backstop
    # reads this; the id is the token after "list" so a --db pin cannot shift it.
    depid=""; seen_list=0
    for a in "$@"; do
      [ "$seen_list" = 1 ] && { depid="$a"; break; }
      [ "$a" = list ] && seen_list=1
    done
    f="$SHOW_DIR/dep-$depid.json"
    if [ -f "$f" ]; then cat "$f"; else printf '[]\n'; fi
    exit 0 ;;
  "bd create")
    printf 'bd create %s\n' "$*" >> "$GC_CALLS"
    printf '{"id":"tk-subj-new"}\n'; exit 0 ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$GC_CALLS"; exit 0 ;;
  "session list")
    # The holder-liveness read. GC_SESSION_FAIL = an outage (unreadable list).
    [ -n "${GC_SESSION_FAIL:-}" ] && exit 1
    if [ -n "${FAKE_SESSIONS:-}" ] && [ -f "${FAKE_SESSIONS:-}" ]; then cat "$FAKE_SESSIONS"; else printf '{"sessions":[]}\n'; fi
    exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# gh stub: only zook/gc-toolkit answers, with #521/#522 open (so #520 merged and
# #999 closed stay VISIBLE through the intersection). GH_FAIL = a real outage.
# It serves $GH_PRS verbatim, which is how a test ages a PR: the sweep asks for
# url,updatedAt and reads both, so a stub that answered only url would classify
# every PR ageless and hide the case these tests are about.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
repo=""
while [ $# -gt 0 ]; do case "$1" in --repo) repo="$2"; shift 2 ;; *) shift ;; esac; done
case "$repo" in
  */zook/gc-toolkit|zook/gc-toolkit) cat "$GH_PRS" ;;
  *) printf '[]\n' ;;
esac
GH
chmod +x "$TMP/bin/gh"

iso_ago() { date -u -d "-$1 days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ; }
gh_prs() { # gh_prs <days-since-update:521> <days-since-update:522>
    printf '[{"url":"https://github.com/zook/gc-toolkit/pull/521","updatedAt":"%s"},{"url":"https://github.com/zook/gc-toolkit/pull/522","updatedAt":"%s"}]\n' \
        "$(iso_ago "$1")" "$(iso_ago "$2")" > "$TMP/gh-prs.json"
}
gh_prs 0 0
export GH_PRS="$TMP/gh-prs.json"

# escalate.sh stub: records the call, answers like the real tool. A --retract
# call is recorded apart, in $ESC_RETRACTS and $ESC_RETRACT_BODIES, so every
# filing assertion reads filings alone. ESC_FAIL fails a filing and
# ESC_RETRACT_FAIL a retraction.
cat > "$TMP/bin/escalate.sh" <<'ESC'
#!/usr/bin/env bash
retract=0
for a in "$@"; do [ "$a" = "--retract" ] && retract=1; done
if [ "$retract" = 1 ]; then
  [ -n "${ESC_RETRACT_FAIL:-}" ] && { echo "escalate: visit-close.sh did not close the visit" >&2; exit 1; }
else
  [ -n "${ESC_FAIL:-}" ] && { echo "escalate: down" >&2; exit 1; }
fi
subject=""; key=""; message=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) subject="$2"; shift 2 ;;
    --key)     key="$2"; shift 2 ;;
    --message) message="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ "$retract" = 1 ]; then
  printf '%s %s\n' "$subject" "$key" >> "$ESC_RETRACTS"
  printf '%s\n---\n' "$message" >> "$ESC_RETRACT_BODIES"
  echo "escalate: retracted visit v-stale on $subject [$key] as moot"
  exit 0
fi
printf '%s\n---\n' "$message" >> "$ESC_BODIES"
printf '%s %s\n' "$subject" "$key" >> "$ESC_CALLS"
echo "escalate: filed visit tk-visit1 on $subject [$key] -> gc-toolkit.converse"
ESC
chmod +x "$TMP/bin/escalate.sh"

export PATH="$TMP/bin:$PATH"
export SHOW_DIR="$TMP/show" GC_CALLS="$TMP/gc-calls" ESC_CALLS="$TMP/esc-calls" ESC_BODIES="$TMP/esc-bodies"
export ESC_RETRACTS="$TMP/esc-retracts" ESC_RETRACT_BODIES="$TMP/esc-retract-bodies"
export GC_ESCALATE_TOOL="$TMP/bin/escalate.sh"
export GC_RIG=testrig
export LIVENESS_SWEEP_STATE_DIR="$TMP/state"
# The stubs answer instantly, so the per-call timeout only ever adds a fork.
# 0 makes bounded() a passthrough (same no-bound behavior as `timeout 0`).
export LIVENESS_SWEEP_CALL_TIMEOUT=0
unset GC_RIG_ROOT GC_PACK_STATE_DIR 2>/dev/null || true
BASELINE_FILE="$TMP/state/testrig/reported"

# --- fixtures (the classification population from the retired delta test) -----
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"c-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"c-routed","title":"already dispatched","issue_type":"task","metadata":{"gc.routed_to":"rig/rig.polecat"}},
  {"id":"root-landed","title":"the ROOT of a spent molecule, still routed","issue_type":"task","metadata":{"gc.kind":"workflow","gc.routed_to":"rig/rig.polecat","gc.input_convoy_id":"conv-landed"}},
  {"id":"root-live","title":"the ROOT of an in-flight molecule, routed","issue_type":"task","metadata":{"gc.kind":"workflow","gc.routed_to":"rig/rig.polecat","gc.input_convoy_id":"conv-anchorlive"}},
  {"id":"c-visit","title":"visit: something","issue_type":"task","metadata":{"task_kind":"visit"}},
  {"id":"c-subject","title":"triage: a scope","issue_type":"task","metadata":{"task_kind":"triage-subject"}},
  {"id":"c-pattern","title":"a distiller cluster anchor","issue_type":"task","metadata":{"task_kind":"feedback-pattern"}},
  {"id":"c-docupdate","title":"a doc-update bead nobody routed","issue_type":"task","metadata":{"task_kind":"doc-update"}},
  {"id":"c-ingroup","title":"subject of a live visit","issue_type":"task","metadata":{}},
  {"id":"c-trackedvisit","title":"subject of a live visit whose stamp landed EMPTY","issue_type":"task","metadata":{}},
  {"id":"c-takeaway","title":"a sitting ended here and left its takeaway","issue_type":"epic","metadata":{"gc.takeaway":"needs operator ratify"}},
  {"id":"c-takeaway-empty","title":"hold was cleared","issue_type":"task","metadata":{"gc.takeaway":""}},
  {"id":"c-demand-live","title":"a person owes an answer here","issue_type":"task","metadata":{"gc.takeaway":"holding — which of the two?"}},
  {"id":"c-demand-widen","title":"its demand is deferred, not closed","issue_type":"task","metadata":{"gc.takeaway":"holding — parked on a person"}},
  {"id":"c-pr-open","title":"parked on an open PR","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/zook/gc-toolkit/pull/521"}},
  {"id":"c-pr-case","title":"same PR, different case + trailing path","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://GitHub.com/zook/gc-toolkit/pull/522/files"}},
  {"id":"c-pr-merged","title":"landed — surfaces for close-out","issue_type":"task","metadata":{"merge_result":"merged","pr_url":"https://github.com/zook/gc-toolkit/pull/520"}},
  {"id":"c-pr-closed","title":"rejected — closed unmerged","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/zook/gc-toolkit/pull/999"}},
  {"id":"c-pr-otherrepo","title":"number 521 in another repository","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/someone/elsewhere/pull/521"}},
  {"id":"c-pr-nourl","title":"marker but no pr_url","issue_type":"task","metadata":{"merge_result":"pull_request"}},
  {"id":"c-preopen-green","title":"pre-open, codex green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"green"}},
  {"id":"c-preopen-multigreen","title":"pre-open, two gates green (spaced)","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex, ci","check.codex":"green","check.ci":"green"}},
  {"id":"c-preopen-approval","title":"pre-open, green + approval sentinel","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,approval","check.codex":"green"}},
  {"id":"c-preopen-fixable","title":"pre-open, fixable — stalled","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"fixing"}},
  {"id":"c-preopen-partial","title":"pre-open, one of two markers absent","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,ci","check.codex":"green"}},
  {"id":"c-preopen-nomarker","title":"pre-open, no marker at all","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
  {"id":"c-preopen-noset","title":"pre-open, marker but check_set unset","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check.codex":"green"}},
  {"id":"c-preopen-none","title":"pre-open, check_set=none opt-out","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"none"}},
  {"id":"c-hold","title":"operator decided this waits","issue_type":"task","metadata":{"triage.hold":"deferred; operator direction pending"}},
  {"id":"c-hold-bare","title":"held, no reason named","issue_type":"task","metadata":{"triage.hold":"true"}},
  {"id":"c-hold-empty","title":"hold was cleared","issue_type":"task","metadata":{"triage.hold":""}},
  {"id":"c-worked","title":"a work bead a live molecule is driving","issue_type":"bug","metadata":{}},
  {"id":"c-husk-tracked","title":"tracked only by a dead synthetic convoy","issue_type":"bug","metadata":{}},
  {"id":"c-inputconvoy","title":"input convoy for c-plain","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-slingconvoy","title":"sling-c-plain","issue_type":"convoy"},
  {"id":"c-synthconvoy","title":"a machine convoy under another name","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-synthconvoy-bool","title":"a machine convoy whose gc.synthetic reads back as a boolean","issue_type":"convoy","metadata":{"gc.synthetic":true}},
  {"id":"c-realconvoy","title":"an unowned floating convoy — the orphan to catch","issue_type":"convoy","metadata":{}},
  {"id":"c-titletalk","title":"input convoy for tk-x never closes","issue_type":"bug","metadata":{}},
  {"id":"c-slingtalk","title":"sling-created convoys are never reaped","issue_type":"bug","metadata":{}},
  {"id":"c-wisp-order","title":"order:liveness-sweep:rig:testrig","issue_type":"task","metadata":{}},
  {"id":"c-ordertalk","title":"order: wisps outlive the pass that cut them","issue_type":"bug","metadata":{}},
  {"id":"c-wisp-other","title":"a wisp of some other kind","issue_type":"task","metadata":{}},
  {"id":"c-husk-step-1","title":"load context","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-husk-step-2","title":"implement","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-live-step","title":"a step of an in-flight workflow","issue_type":"task","metadata":{"gc.root_bead_id":"root-live"}},
  {"id":"c-noconvoy-step","title":"a step whose root names no convoy","issue_type":"task","metadata":{"gc.root_bead_id":"root-noconvoy"}},
  {"id":"c-rootvisit-step","title":"a step of a root a live visit tracks","issue_type":"task","metadata":{"gc.root_bead_id":"root-underconversation"}},
  {"id":"c-parented","title":"a parent whose child is still open","issue_type":"epic","metadata":{}},
  {"id":"c-trackslive","title":"tracks a not-closed bead","issue_type":"task","metadata":{},"dependencies":[{"depends_on_id":"m-live","type":"tracks"}]}
]
JSON
# LIVE carries: the standing sweep subject, the visits (v-2 is the su-ab9je
# empty-stamp shape, v-root tracks a workflow root), the live molecule that
# names conv-live, and the open demand on c-demand-live. blocked-child gates
# c-parented via the reverse parent-child index.
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"tk-subject","status":"open","title":"triage: unnamed waits (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits"}},
  {"id":"v-1","status":"open","title":"visit: c-ingroup","metadata":{"task_kind":"visit","gc.continuation_group":"c-ingroup"}},
  {"id":"v-2","status":"open","title":"visit: c-trackedvisit","metadata":{"task_kind":"visit","gc.continuation_group":""},"dependencies":[{"issue_id":"v-2","depends_on_id":"c-trackedvisit","type":"tracks"}]},
  {"id":"v-root","status":"open","title":"visit: root-underconversation","metadata":{"task_kind":"visit","gc.continuation_group":"root-underconversation"},"dependencies":[{"issue_id":"v-root","depends_on_id":"root-underconversation","type":"tracks"}]},
  {"id":"m-live","status":"open","title":"a live molecule","metadata":{"gc.input_convoy_id":"conv-live"}},
  {"id":"d-open","status":"open","title":"Rule: which of the two?","metadata":{"gc.demand_for":"c-demand-live"}},
  {"id":"child-open","status":"open","title":"an open child of c-parented","metadata":{},"dependencies":[{"depends_on_id":"c-parented","type":"parent-child"}]}
]
JSON
# WIDEN is every not-closed status LIVE omits. The deferred demand proves the
# demand index reads ALIVE and not LIVE: not closed is not answered.
cat > "$TMP/widen.json" <<'JSON'
[
  {"id":"d-deferred","status":"deferred","title":"Rule: the other one?","metadata":{"gc.demand_for":"c-demand-widen"}}
]
JSON
export FAKE_READY="$TMP/ready.json" FAKE_LIVE="$TMP/live.json" FAKE_WIDEN="$TMP/widen.json"

# The holder-liveness session set: lx-live-1 is listed (a visit it holds still
# converses); a session absent from this set (e.g. lx-dead-9) is a gone sitting.
# The existing visits above are all UNCLAIMED, so they cover regardless of this.
cat > "$TMP/sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-live-1","state":"active","closed":false,"session_name":"s-lx-live-1","alias":"","name":"testrig__conv-lx-live-1","agent_name":"testrig/testrig.tk-livevisit"}
]}
JSON
export FAKE_SESSIONS="$TMP/sessions.json"

# bd show fixtures: the worked-via-convoy and landed-husk chains.
printf '%s\n' '[{"id":"conv-live","issue_type":"convoy","dependencies":[{"id":"c-worked","dependency_type":"tracks","status":"open"}]}]' > "$TMP/show/conv-live.json"
printf '%s\n' '[{"id":"root-landed","metadata":{"gc.input_convoy_id":"conv-landed"}}]' > "$TMP/show/root-landed.json"
printf '%s\n' '[{"id":"conv-landed","issue_type":"convoy","dependencies":[{"id":"anchor-landed","dependency_type":"tracks","status":"closed"}]}]' > "$TMP/show/conv-landed.json"
printf '%s\n' '[{"id":"anchor-landed","status":"closed","metadata":{"merge_result":"merged"}}]' > "$TMP/show/anchor-landed.json"
printf '%s\n' '[{"id":"root-live","metadata":{"gc.input_convoy_id":"conv-anchorlive"}}]' > "$TMP/show/root-live.json"
printf '%s\n' '[{"id":"conv-anchorlive","issue_type":"convoy","dependencies":[{"id":"anchor-live","dependency_type":"tracks","status":"open"}]}]' > "$TMP/show/conv-anchorlive.json"
printf '%s\n' '[{"id":"anchor-live","status":"open","metadata":{"merge_result":"pull_request"}}]' > "$TMP/show/anchor-live.json"
printf '%s\n' '[{"id":"root-noconvoy","metadata":{}}]' > "$TMP/show/root-noconvoy.json"
printf '%s\n' '[{"id":"root-underconversation","metadata":{"gc.input_convoy_id":"conv-uc"}}]' > "$TMP/show/root-underconversation.json"
printf '%s\n' '[{"id":"conv-uc","issue_type":"convoy","dependencies":[{"id":"anchor-uc","dependency_type":"tracks","status":"open"}]}]' > "$TMP/show/conv-uc.json"
printf '%s\n' '[{"id":"anchor-uc","status":"open","metadata":{}}]' > "$TMP/show/anchor-uc.json"

run_sweep() { # run_sweep [baseline-csv|ABSENT] -> RC/OUT
    rm -rf "$TMP/state"; mkdir -p "$TMP/state/testrig"
    [ "${1:-ABSENT}" = "ABSENT" ] || printf '%s\n' "$1" > "$BASELINE_FILE"
    : > "$GC_CALLS"; : > "$ESC_CALLS"; : > "$ESC_BODIES"
    : > "$ESC_RETRACTS"; : > "$ESC_RETRACT_BODIES"
    RC=0
    OUT="$(bash "$SCRIPT" 2>"$TMP/err")" || RC=$?
    ERR="$(cat "$TMP/err")"
}

# The full unnamed set this population classifies to (ports the retired
# delta-test survivor assertion, plus the two structural-edge candidates the
# exec script now folds in: c-parented is gated by its open child, and
# c-trackslive by its outgoing tracks edge to a live bead).
EXPECT_SURVIVORS="c-docupdate,c-hold-empty,c-husk-tracked,c-live-step,c-noconvoy-step,c-ordertalk,c-plain,c-pr-closed,c-pr-merged,c-pr-nourl,c-pr-otherrepo,c-preopen-fixable,c-preopen-nomarker,c-preopen-none,c-preopen-noset,c-preopen-partial,c-realconvoy,c-slingtalk,c-takeaway,c-takeaway-empty,c-titletalk,c-wisp-other"

echo "── first run: absent baseline → full census filed, baseline advanced ──"
run_sweep ABSENT
eq "$RC" "0" "the pass completes"
eq "$(cat "$BASELINE_FILE" 2>/dev/null)" "$EXPECT_SURVIVORS" \
   "the baseline advances to exactly the unnamed set (classification pinned)"
eq "$(cat "$ESC_CALLS")" "tk-subject liveness-sweep" \
   "ONE batch visit via escalate.sh, on the standing subject, key liveness-sweep"
grep -q "New this pass:" "$ESC_BODIES" && ok "the body lists the new candidates" \
    || bad "the body lists the new candidates" "$(cat "$ESC_BODIES")"
grep -q "c-plain — an ordinary idle bug" "$ESC_BODIES" \
    && ok "a new candidate is enumerated id — title" || bad "candidate enumeration" "$(head -5 "$ESC_BODIES")"
grep -Eq 'sweep.new_ids=[a-z0-9,-]*c-plain' "$GC_CALLS" \
    && ok "the census rides the visit as machine state (sweep.new_ids)" \
    || bad "sweep.new_ids stamp" "$(grep 'bd update tk-visit1' "$GC_CALLS" || true)"
grep -q 'visit.recheck=.*liveness-recheck.sh' "$GC_CALLS" \
    && ok "visit.recheck stamps the resolved liveness-recheck.sh path" \
    || bad "visit.recheck stamp" "$(cat "$GC_CALLS")"

echo "── a routed workflow ROOT is topology, never routed-and-claimable ──"
# gc.routed_to on a root names the run; it is not an offer. The hook refuses a
# workflow-topology candidate (hookCandidateClaimable) and the controller's
# demand loop refuses to count one (demandRowServable), both keyed on gc.kind,
# so no worker can ever take the row. Calling it claimable published a count of
# pool demand that nothing could serve. c-routed is the discriminator: an
# ordinary routed bead keeps the claimable class.
FUNNEL="$(printf '%s' "$OUT" | grep 'funnel:' || true)"
# Exact count per class: a substring match would accept "topology 20" too.
funnel_count() { printf '%s' "$FUNNEL" | sed 's/.*funnel: //; s/ \xc2\xb7 /\n/g' \
    | awk -v c="$1" '$1 == c { print $2; found = 1 } END { if (!found) print "<absent>" }'; }
eq "$(funnel_count topology)" "2" "both routed roots classify as topology"
eq "$(funnel_count routed-and-claimable)" "1" "routed-and-claimable holds only c-routed"
for r in root-landed root-live; do
    case ",$(cat "$BASELINE_FILE")," in
        *",$r,"*) bad "dropped $r" "a topology root reached the unnamed set" ;;
        *) ok "dropped $r" ;;
    esac
done

echo "── each named class drops, each inverse-defect shape stays visible ──"
for drop in c-routed c-visit c-subject c-pattern c-ingroup c-trackedvisit \
            c-demand-live c-demand-widen \
            c-pr-open c-pr-case c-preopen-green c-preopen-multigreen \
            c-preopen-approval c-hold c-hold-bare c-worked c-inputconvoy \
            c-slingconvoy c-synthconvoy c-synthconvoy-bool c-wisp-order c-husk-step-1 c-husk-step-2 \
            c-rootvisit-step c-parented c-trackslive; do
    case ",$EXPECT_SURVIVORS," in
        *",$drop,"*) bad "dropped $drop" "still in the survivor set" ;;
        *) ok "dropped $drop" ;;
    esac
done
for keep in c-pr-merged c-pr-closed c-pr-otherrepo c-pr-nourl c-preopen-fixable \
            c-preopen-partial c-preopen-nomarker c-preopen-noset c-preopen-none \
            c-husk-tracked c-live-step c-noconvoy-step c-titletalk c-slingtalk \
            c-ordertalk c-wisp-other \
            c-realconvoy c-docupdate c-takeaway c-takeaway-empty c-hold-empty; do
    case ",$(cat "$BASELINE_FILE")," in
        *",$keep,"*) ok "kept $keep" ;;
        *) bad "kept $keep" "was hidden — the inverse defect" ;;
    esac
done

echo "── the hold is a live demand bead, never the takeaway stamp ──"
# Read as a hold, `gc.takeaway` exempts a bead from every later pass, because a
# sitting stamps it at the hold, REPLACES it with its outcome at sign-off, and
# nothing clears it. c-takeaway is that shape and is a candidate above; these
# pin what does hold, and that it holds for the demand's sake.
run_sweep ABSENT
if grep -q "c-demand-live" "$ESC_BODIES"; then
    bad "an open demand holds its bead" "c-demand-live was reported"
else ok "an open demand holds its bead"; fi
if grep -q "c-demand-widen" "$ESC_BODIES"; then
    bad "a deferred demand still holds" "c-demand-widen was reported"
else ok "a deferred demand still holds (the index reads ALIVE, not LIVE)"; fi
grep -q "c-takeaway — a sitting ended here" "$ESC_BODIES" \
    && ok "a takeaway with no demand is reported — the sitting ended" \
    || bad "takeaway alone no longer exempts" "$(cat "$ESC_BODIES")"
# Mutate the guard: with the demand closed (gone from every not-closed listing)
# the same bead, takeaway and all, has to come back.
jq 'map(select(.id != "d-open"))' "$TMP/live.json" > "$TMP/live-nodemand.json"
FAKE_LIVE="$TMP/live-nodemand.json" run_sweep ABSENT
grep -q "c-demand-live" "$ESC_BODIES" \
    && ok "the demand closes → the bead it held is reported again" \
    || bad "closed demand releases" "$(cat "$ESC_BODIES")"

echo "── the delta splits new from carried; index 0 is a real hit ──"
PARTIAL="$(printf '%s' "$EXPECT_SURVIVORS" | cut -d, -f2-)"   # all but the FIRST id
run_sweep "$PARTIAL"
grep -q "delta: 1 new, 21 carried" <<< "$OUT" \
    && ok "baseline missing one id → exactly 1 new (and position 0 counts as carried)" \
    || bad "delta split" "$OUT"
grep -q "c-docupdate" "$ESC_BODIES" && ok "the new one is enumerated" || bad "new enumeration" "$(cat "$ESC_BODIES")"
grep -q "Carried (still unnamed from earlier passes" "$ESC_BODIES" \
    && ok "carried ids listed as bare ids, not re-litigated" || bad "carried line" "$(cat "$ESC_BODIES")"

echo "── a departed bead is pruned from the next baseline ──"
run_sweep "$EXPECT_SURVIVORS,z-departed"
eq "$(cat "$BASELINE_FILE")" "$EXPECT_SURVIVORS" \
   "a dispositioned bead (z-departed) leaves the baseline, so a regression re-reports it"

echo "── an unchanged population files nothing and still advances ──"
run_sweep "$EXPECT_SURVIVORS"
eq "$(cat "$ESC_CALLS")" "" "0 new → no visit filed"
grep -q "nothing new — nothing filed" <<< "$OUT" && ok "…and says so" || bad "quiet-pass line" "$OUT"

echo "── a live visit on the subject skips AND leaves the baseline alone ──"
jq '. + [{"id":"v-batch","status":"in_progress","title":"visit: tk-subject","metadata":{"task_kind":"visit","gc.continuation_group":"tk-subject"}}]' \
    "$TMP/live.json" > "$TMP/live-held.json"
FAKE_LIVE="$TMP/live-held.json" run_sweep "c-plain"
eq "$(cat "$ESC_CALLS")" "" "no second visit stacked on a held sitting"
eq "$(cat "$BASELINE_FILE")" "c-plain" \
   "the baseline is NOT advanced — unseen candidates must not retire"
# The su-ab9je shape: the stamp landed empty, only the tracks edge names it.
jq '. + [{"id":"v-edge","status":"open","title":"visit: tk-subject","metadata":{"task_kind":"visit","gc.continuation_group":""},"dependencies":[{"issue_id":"v-edge","depends_on_id":"tk-subject","type":"tracks"}]}]' \
    "$TMP/live.json" > "$TMP/live-edge.json"
FAKE_LIVE="$TMP/live-edge.json" run_sweep "c-plain"
eq "$(cat "$ESC_CALLS")" "" "an edge-only visit (empty stamp) still reads as live"

echo "── the re-file guard suppresses only a dispositioned identical SET ──"
NEWKEY="$(printf '%s' "$EXPECT_SURVIVORS" | tr ',' '\n' | sort | paste -sd, -)"
prior() { printf '[{"id":"%s","metadata":{"task_kind":"visit","gc.outcome":"%s","sweep.new_ids":"%s","gc.continuation_group":"tk-subject"}}]' "$3" "$1" "$2" > "$TMP/prior.json"; }
prior dispositioned "$NEWKEY" v-done
PRIOR_VISITS="$TMP/prior.json" run_sweep ABSENT
eq "$(cat "$ESC_CALLS")" "" "the same NEW set, already dispositioned, is not re-filed"
grep -q "not re-filed" <<< "$OUT" && ok "…and says which visit disposed it" || bad "refile line" "$OUT"
eq "$(cat "$BASELINE_FILE")" "$EXPECT_SURVIVORS" "…and the baseline advances (the set WAS seen)"
# A cut-short sitting did not dispose of its agenda: file again.
prior cut-short "$NEWKEY" v-cut
PRIOR_VISITS="$TMP/prior.json" run_sweep ABSENT
eq "$(cat "$ESC_CALLS")" "tk-subject liveness-sweep" "a cut-short prior files again"
# A FAILING listing files even when its payload matches (rc is the evidence).
prior dispositioned "$NEWKEY" v-failed
PRIOR_VISITS="$TMP/prior.json" GC_LIST_RC=1 run_sweep ABSENT
eq "$(cat "$ESC_CALLS")" "tk-subject liveness-sweep" \
   "a failing closed-visit listing files, even when what it printed matches"
# The empty-stamp shape: a dispositioned prior identified ONLY by its tracks
# edge still suppresses. The stamp-keyed server query could not see it and
# re-filed a settled agenda; the edge-union resolution (visit_covers) does.
printf '[{"id":"v-edge-done","metadata":{"task_kind":"visit","gc.outcome":"dispositioned","sweep.new_ids":"%s","gc.continuation_group":""},"dependencies":[{"issue_id":"v-edge-done","depends_on_id":"tk-subject","type":"tracks"}]}]' \
    "$NEWKEY" > "$TMP/prior.json"
PRIOR_VISITS="$TMP/prior.json" run_sweep ABSENT
eq "$(cat "$ESC_CALLS")" "" "an empty-stamp, edge-only dispositioned prior still suppresses the re-file"
# …and visit_covers must DISCRIMINATE by subject: a dispositioned prior with the
# same set but covering a DIFFERENT subject (no edge here, stamp names another)
# is not this subject's prior, so it files.
printf '[{"id":"v-elsewhere","metadata":{"task_kind":"visit","gc.outcome":"dispositioned","sweep.new_ids":"%s","gc.continuation_group":"some-other-subject"}}]' \
    "$NEWKEY" > "$TMP/prior.json"
PRIOR_VISITS="$TMP/prior.json" run_sweep ABSENT
eq "$(cat "$ESC_CALLS")" "tk-subject liveness-sweep" "a dispositioned prior on a DIFFERENT subject does not suppress this one"

echo "── fail-safe: an unreadable listing aborts, files nothing, keeps the baseline ──"
GC_READY_FAIL=1 run_sweep "old-baseline"
eq "$RC" "1" "unreadable ready listing → exit 1"
eq "$(cat "$ESC_CALLS")" "" "…nothing filed"
eq "$(cat "$BASELINE_FILE")" "old-baseline" "…baseline untouched"

echo "── liveness words are three-valued and a failed probe reports, never hides ──"
GH_FAIL=1 run_sweep "$EXPECT_SURVIVORS"
grep -q "pr=unverified" <<< "$OUT" && ok "a failed gh read is 'unverified'" || bad "pr liveness" "$OUT"
grep -q "c-pr-open" <<< "$(cat "$BASELINE_FILE")" \
    && ok "a live-PR bead is REPORTED when liveness is unverified" \
    || bad "unverified keeps the bead visible" "$(cat "$BASELINE_FILE")"
GC_SHOW_FAIL="conv-live" run_sweep "$EXPECT_SURVIVORS"
grep -q "convoy=unverified" <<< "$OUT" && ok "a failed convoy read is 'unverified'" || bad "convoy liveness" "$OUT"
grep -q "c-worked" <<< "$(cat "$BASELINE_FILE")" \
    && ok "a failed convoy read leaves its member a candidate (reported)" \
    || bad "failed convoy read hides nothing" "$(cat "$BASELINE_FILE")"
GC_SHOW_FAIL="anchor-landed" run_sweep "$EXPECT_SURVIVORS"
grep -q "husk=unverified" <<< "$OUT" && ok "a failed anchor read is 'unverified'" || bad "husk liveness" "$OUT"
grep -q "c-husk-step-1" <<< "$(cat "$BASELINE_FILE")" \
    && ok "a failed anchor read keeps the step a candidate (reported)" \
    || bad "failed anchor read hides nothing" "$(cat "$BASELINE_FILE")"

echo "── a PR-gated anchor is a named wait only while its PR MOVES ──"
# The defect: an anchor parked on a PR that stopped is invisible to every pass.
# The PR names the wait, so it is not an unnamed wait and the batch visit skips
# it; nothing else looks. It has to become its own escalation, on the anchor.
gh_prs 0 0
run_sweep "$EXPECT_SURVIVORS"
grep -q anchor-stale "$ESC_CALLS" \
    && bad "a moving PR stays gated" "escalated anyway: $(cat "$ESC_CALLS")" \
    || ok "a PR updated today stays gated — nothing escalated"

gh_prs 9 0
run_sweep "$EXPECT_SURVIVORS"
eq "$(grep -c anchor-stale "$ESC_CALLS")" "1" "a PR idle past the threshold escalates exactly once"
grep -q '^c-pr-open anchor-stale$' "$ESC_CALLS" \
    && ok "…with the ANCHOR as subject and one stable key" || bad "stale subject/key" "$(cat "$ESC_CALLS")"
grep -q 'c-pr-case' "$ESC_CALLS" \
    && bad "the sibling PR that is still moving is untouched" "c-pr-case escalated too" \
    || ok "the sibling PR that is still moving is untouched"
grep -q 'bd update c-pr-open --set-metadata stale_escalated_at=' "$GC_CALLS" \
    && ok "…and the anchor is stamped stale_escalated_at" || bad "stale_escalated_at stamp" "$(cat "$GC_CALLS")"
grep -q 'stale_escalated_to=gc-toolkit.converse' "$GC_CALLS" \
    && ok "…and stale_escalated_to records the route escalate.sh reported" \
    || bad "stale_escalated_to stamp" "$(cat "$GC_CALLS")"
grep -q '9 day' "$ESC_BODIES" && ok "the body states how long the PR has been idle" || bad "body age" "$(cat "$ESC_BODIES")"
grep -q 'pull/521' "$ESC_BODIES" && ok "…and names the PR" || bad "body names the PR" "$(cat "$ESC_BODIES")"
case ",$(cat "$BASELINE_FILE")," in
    *",c-pr-open,"*) bad "a stale gate is never doubled into the batch" "it entered the baseline too" ;;
    *) ok "a stale gate is escalated alone, never also batched as an unnamed wait" ;;
esac

echo "── the dedup is the anchor's own stamp, so a wiped state dir cannot lose it ──"
# run_sweep deletes the state directory on every call, which IS the recycle the
# /tmp marker file could not survive: here the ONLY thing that can suppress a
# second escalation is durable bead state.
stamp_pr_open() { jq --arg t "$1" 'map(if .id == "c-pr-open" then .metadata.stale_escalated_at = $t else . end)' \
    "$TMP/ready.json" > "$TMP/ready-stamped.json"; }
gh_prs 9 0
stamp_pr_open "$(iso_ago 1)"
FAKE_READY="$TMP/ready-stamped.json" run_sweep "$EXPECT_SURVIVORS"
grep -q anchor-stale "$ESC_CALLS" \
    && bad "a stamped anchor inside the floor is not re-raised" "re-escalated: $(cat "$ESC_CALLS")" \
    || ok "a stamped anchor inside the floor is not re-raised, fresh state dir and all"
grep -q "inside the 3d floor" <<< "$OUT" && ok "…and the pass says so" || bad "floor line" "$OUT"

stamp_pr_open "$(iso_ago 5)"
FAKE_READY="$TMP/ready-stamped.json" run_sweep "$EXPECT_SURVIVORS"
eq "$(grep -c anchor-stale "$ESC_CALLS")" "1" \
   "past the floor the same anchor is raised again — bounded retry, not once-forever"

stamp_pr_open "not-a-timestamp"
FAKE_READY="$TMP/ready-stamped.json" run_sweep "$EXPECT_SURVIVORS"
eq "$(grep -c anchor-stale "$ESC_CALLS")" "1" \
   "an unreadable stamp re-raises rather than muting the anchor forever"

echo "── an unverifiable age reports, and a failed escalation stamps nothing ──"
printf '[{"url":"https://github.com/zook/gc-toolkit/pull/521"},{"url":"https://github.com/zook/gc-toolkit/pull/522","updatedAt":"%s"}]\n' \
    "$(iso_ago 0)" > "$TMP/gh-prs.json"
run_sweep "$EXPECT_SURVIVORS"
grep -q '^c-pr-open anchor-stale$' "$ESC_CALLS" \
    && ok "a PR GitHub gave no updatedAt for is REPORTED, never held" || bad "ageless PR" "$(cat "$ESC_CALLS")"
grep -q 'no readable last-update time' "$ESC_BODIES" \
    && ok "…and the body says the age is unknown instead of inventing one" || bad "ageless body" "$(cat "$ESC_BODIES")"

gh_prs 9 0
GH_FAIL=1 run_sweep "$EXPECT_SURVIVORS"
grep -q anchor-stale "$ESC_CALLS" \
    && bad "an unread PR set escalates no stale gate" "escalated on data it never read" \
    || ok "an unread PR set escalates no stale gate — the bead falls to the batch instead"

ESC_FAIL=1 run_sweep "$EXPECT_SURVIVORS"
grep -q stale_escalated "$GC_CALLS" \
    && bad "a failed escalation stamps nothing" "stamped anyway: $(grep stale_escalated "$GC_CALLS")" \
    || ok "a failed escalation stamps nothing — the next pass retries it"

rm -rf "$TMP/state"; mkdir -p "$TMP/state/testrig"; : > "$GC_CALLS"; : > "$ESC_CALLS"
bash "$SCRIPT" --dry-run >/dev/null 2>&1
eq "$(cat "$ESC_CALLS")" "" "--dry-run escalates no stale gate"
grep -q stale_escalated "$GC_CALLS" && bad "--dry-run stamps no anchor" "it stamped one" \
    || ok "--dry-run stamps no anchor"
gh_prs 0 0

echo "── a stale PR the merge cadence settled waiting on the operator's review is not escalated ──"
# A settled wait the operator's review queue already names. The merge cadence
# settled the PR at the head its posture was read at, and the posture still owes
# a review. It classifies gated, never stale-gate. The controls fall outside that
# settled reading: a posture read at another head than the settled verdict, a PR
# the cadence has not settled, and an approved PR, settled or not. merge.sh
# records no verdict at many holds an approved PR can reach, so a settled verdict
# beside an approval can be one recorded before it, and an approved PR still idle
# past the threshold is held by something the visit surfaces.
T="$(iso_ago 3)"
raise_case() { # raise_case <pr_posture> <pr.machine>: c-pr-open's PR idle 9 days
    jq --arg p "$1" --arg m "$2" \
        'map(if .id == "c-pr-open" then .metadata += {"pr_posture": $p, "pr.machine": $m} else . end)' \
        "$TMP/ready.json" > "$TMP/ready-pr.json"
    gh_prs 9 0
    FAKE_READY="$TMP/ready-pr.json" run_sweep "$EXPECT_SURVIVORS"
    FUNNEL="$(printf '%s' "$OUT" | grep 'funnel:' || true)"
}
for c in "review_required@sha-521@$T|settled@sha-521@$T|a settled stale PR awaiting the operator's first review" \
         "changes_requested@sha-521@$T|settled@sha-521@$T|a settled stale PR awaiting the operator's re-review"; do
    p="${c%%|*}"; rest="${c#*|}"; m="${rest%%|*}"; what="${rest#*|}"
    raise_case "$p" "$m"
    eq "$(grep -c anchor-stale "$ESC_CALLS")" "0" "$what is not escalated"
    eq "$(funnel_count stale-gate)" "<absent>" "…and classifies gated, not stale-gate"
    case ",$(cat "$BASELINE_FILE")," in
        *",c-pr-open,"*) bad "…and is not batched as an unnamed wait" "it entered the baseline" ;;
        *) ok "…and is not batched as an unnamed wait" ;;
    esac
done
for c in "review_required@sha-old@$T|settled@sha-521@$T|a review owed at an earlier head than the settled verdict" \
         "approved@sha-521@$T|settled@sha-521@$T|an approved stale PR whose settled verdict may predate the approval" \
         "approved@sha-old@$T|settled@sha-521@$T|an approval read at an earlier head than the settled verdict" \
         "review_required@sha-521@$T|progressing@sha-521@$T|a PR the merge cadence has not settled" \
         "approved@sha-521@$T|progressing@sha-521@$T|an approved PR with a review, fix or blocker still in flight" \
         "approved@sha-521@$T||an approved PR the merge cadence never recorded" \
         "review_required@sha-521@$T|blocked@sha-521@$T|a PR blocked on something no review clears"; do
    p="${c%%|*}"; rest="${c#*|}"; m="${rest%%|*}"; what="${rest#*|}"
    raise_case "$p" "$m"
    grep -q '^c-pr-open anchor-stale$' "$ESC_CALLS" \
        && ok "control: $what still escalates" || bad "control: $what still escalates" "$(cat "$ESC_CALLS")"
done
gh_prs 0 0

echo "── a stale-gate visit is retracted, moot, once its premise is gone ──"
# The pass that files the visit owns its premise. A visit nobody is engaged in is
# retracted through escalate.sh --retract once the PR moves or lands, or the
# merge cadence settles it waiting on the operator's review, and only on evidence
# this pass read.
stale_live() { # stale_live <c-pr-open metadata to add> <visit fields to merge> -> $TMP/live-stale.json
    jq --argjson m "$1" --argjson v "$2" '. + [
        {"id":"c-pr-open","status":"open","title":"parked on an open PR",
         "metadata":({"merge_result":"pull_request","pr_url":"https://github.com/zook/gc-toolkit/pull/521"} + $m)},
        ({"id":"v-stale","status":"open","assignee":"","title":"visit: stale PR gate: c-pr-open",
          "metadata":{"task_kind":"visit","escalation_key":"anchor-stale","gc.continuation_group":"c-pr-open"},
          "dependencies":[{"issue_id":"v-stale","depends_on_id":"c-pr-open","type":"tracks"}]} * $v)]' \
        "$TMP/live.json" > "$TMP/live-stale.json"
}
retract_run() { FAKE_LIVE="$TMP/live-stale.json" run_sweep "$EXPECT_SURVIVORS"; }

gh_prs 0 0; stale_live '{}' '{}'; retract_run
eq "$(cat "$ESC_RETRACTS")" "c-pr-open anchor-stale" "a PR that moved again: its visit is retracted, on the anchor, under the filing key"
grep -q 'moved 0 day(s) ago, inside the 2-day threshold' "$ESC_RETRACT_BODIES" \
    && ok "…and the reading says the PR moved" || bad "moved reading" "$(cat "$ESC_RETRACT_BODIES")"
grep -q 'stale-gate visits: 1 retracted, 0 kept, 0 failed' <<< "$OUT" \
    && ok "…and the pass counts it" || bad "retract tally" "$OUT"
eq "$(cat "$ESC_CALLS" | grep -c anchor-stale)" "0" "…and nothing is filed in the same pass"

gh_prs 9 0; stale_live '{}' '{}'; retract_run
eq "$(cat "$ESC_RETRACTS")" "" "a PR still stale, unapproved and not awaiting review: its visit stands"
grep -q 'stale-gate visits: 0 retracted, 1 kept, 0 failed' <<< "$OUT" \
    && ok "…and the pass counts it kept" || bad "kept tally" "$OUT"

# An approval is not the premise's end, settled or not. merge.sh records no
# verdict at many holds an approved PR can reach, so a settled verdict beside it
# can predate it, and an approved PR still idle past the threshold is held by
# something the visit surfaces.
for m in "settled@sha-521@$T" "progressing@sha-521@$T" "settled@sha-new@$T" ""; do
    stale_live "{\"pr_posture\":\"approved@sha-521@$T\",\"pr.machine\":\"$m\"}" '{}'; retract_run
    eq "$(cat "$ESC_RETRACTS")" "" "an approved PR whose pr.machine is '$m': its visit stands"
done

stale_live "{\"pr_posture\":\"review_required@sha-521@$T\",\"pr.machine\":\"settled@sha-521@$T\"}" '{}'; retract_run
eq "$(cat "$ESC_RETRACTS")" "c-pr-open anchor-stale" "a stale PR now awaiting the operator's review: its visit is retracted"
grep -q 'waits on a review from the operator' "$ESC_RETRACT_BODIES" \
    && ok "…and the reading names the review queue" || bad "review-owed reading" "$(cat "$ESC_RETRACT_BODIES")"

stale_live '{"merge_result":"abandoned"}' '{}'; retract_run
eq "$(cat "$ESC_RETRACTS")" "c-pr-open anchor-stale" "an anchor that left pull_request: its visit is retracted"
grep -q 'no longer gates on a pull request (merge_result=abandoned)' "$ESC_RETRACT_BODIES" \
    && ok "…and the reading names the state it left for" || bad "left-pull_request reading" "$(cat "$ESC_RETRACT_BODIES")"

printf '[{"url":"https://github.com/zook/gc-toolkit/pull/522","updatedAt":"%s"}]\n' "$(iso_ago 0)" > "$TMP/gh-prs.json"
stale_live '{}' '{}'; retract_run
eq "$(cat "$ESC_RETRACTS")" "c-pr-open anchor-stale" "a PR gone from the open list of a repository that answered: its visit is retracted"
grep -q 'pull/521 is no longer open (merged or closed)' "$ESC_RETRACT_BODIES" \
    && ok "…and the reading says the PR left the open list" || bad "not-open reading" "$(cat "$ESC_RETRACT_BODIES")"

gh_prs 0 0; stale_live '{}' '{}'
GH_FAIL=1 retract_run
eq "$(cat "$ESC_RETRACTS")" "" "an unread PR set retracts nothing: absence from it is not evidence"

# The anchor landed: it is gone from the alive census, and a show of it reads closed.
jq 'map(select(.id != "c-pr-open"))' "$TMP/ready.json" > "$TMP/ready-landed.json"
jq '. + [{"id":"v-stale","status":"open","assignee":"","title":"visit: stale PR gate: c-pr-open",
          "metadata":{"task_kind":"visit","escalation_key":"anchor-stale","gc.continuation_group":"c-pr-open"}}]' \
    "$TMP/live.json" > "$TMP/live-landed.json"
printf '%s\n' '[{"id":"c-pr-open","status":"closed","metadata":{"merge_result":"merged"}}]' > "$TMP/show/c-pr-open.json"
FAKE_READY="$TMP/ready-landed.json" FAKE_LIVE="$TMP/live-landed.json" run_sweep "$EXPECT_SURVIVORS"
eq "$(cat "$ESC_RETRACTS")" "c-pr-open anchor-stale" "an anchor that landed and closed: its visit is retracted"
grep -q 'c-pr-open closed (merge_result=merged)' "$ESC_RETRACT_BODIES" \
    && ok "…and the reading says it closed, merged" || bad "closed reading" "$(cat "$ESC_RETRACT_BODIES")"
GC_SHOW_FAIL="c-pr-open" FAKE_READY="$TMP/ready-landed.json" FAKE_LIVE="$TMP/live-landed.json" run_sweep "$EXPECT_SURVIVORS"
eq "$(cat "$ESC_RETRACTS")" "" "a subject missing from the census whose close does not read back keeps its visit"
grep -q 'its close did not read back' <<< "$OUT" && ok "…and the pass says why" || bad "unread close" "$OUT"
rm -f "$TMP/show/c-pr-open.json"

# A visit a person is engaged in is theirs to close, premise or not: here the PR
# moved, so only the engagement keeps the visit open.
gh_prs 0 0
for v in '{"assignee":"human-1"}' '{"metadata":{"gc.session_name":"s-lx-live-1"}}' '{"status":"in_progress"}'; do
    stale_live '{}' "$v"; retract_run
    eq "$(cat "$ESC_RETRACTS")" "" "an engaged visit ($v) is never retracted"
done

stale_live '{}' '{}'
ESC_RETRACT_FAIL=1 retract_run
grep -q 'could not retract the stale-gate visit on c-pr-open' <<< "$ERR" \
    && ok "a retraction that fails is reported" || bad "failed retract warn" "$ERR"
grep -q 'stale-gate visits: 0 retracted, 0 kept, 1 failed' <<< "$OUT" \
    && ok "…and counted failed, for the next pass to retry" || bad "failed tally" "$OUT"

rm -rf "$TMP/state"; mkdir -p "$TMP/state/testrig"; : > "$ESC_RETRACTS"
OUT="$(FAKE_LIVE="$TMP/live-stale.json" bash "$SCRIPT" --dry-run 2>/dev/null)"
eq "$(cat "$ESC_RETRACTS")" "" "--dry-run retracts nothing"
grep -q 'dry-run: would retract the stale-gate visit on c-pr-open' <<< "$OUT" \
    && ok "…and says what it would retract" || bad "dry-run retract line" "$OUT"

echo "── the standing subject is created on first run, idempotently ──"
jq '[.[] | select(.id != "tk-subject")]' "$TMP/live.json" > "$TMP/live-nosubj.json"
FAKE_LIVE="$TMP/live-nosubj.json" run_sweep ABSENT
grep -q 'bd create .*triage: unnamed waits' "$GC_CALLS" \
    && ok "no subject → one is created" || bad "subject creation" "$(cat "$GC_CALLS")"
grep -q 'triage.scope=unnamed-waits' "$GC_CALLS" \
    && ok "…stamped task_kind + triage.scope" || bad "subject stamps" "$(cat "$GC_CALLS")"
eq "$(cat "$ESC_CALLS")" "tk-subj-new liveness-sweep" "…and the visit files on the new subject"

echo "── recurrence: a changed scope set files ONE visit and stamps last_seen ──"
recur_live() { # recur_live <last_seen-json-or-absent> <extra-live-rows...>
    jq --argjson extra "$2" ". + [{\"id\":\"subj-ideas\",\"status\":\"open\",\"title\":\"triage: held ideas\",\"metadata\":{\"task_kind\":\"triage-subject\",\"triage.scope\":\"kind:idea\"$1}}] + \$extra" \
        "$TMP/live.json" > "$TMP/live-recur.json"
}
IDEA='[{"id":"idea-1","status":"open","title":"an idea","metadata":{"task_kind":"idea"}}]'
recur_live '' "$IDEA"     # last_seen ABSENT, one candidate
FAKE_LIVE="$TMP/live-recur.json" run_sweep "$EXPECT_SURVIVORS,idea-1"
grep -q "subj-ideas triage-recurrence" "$ESC_CALLS" \
    && ok "a never-evaluated subject with candidates files" || bad "recurrence first file" "$(cat "$ESC_CALLS"; echo; cat "$TMP/err")"
grep -q 'bd update subj-ideas --set-metadata triage.last_seen=idea-1' "$GC_CALLS" \
    && ok "…and stamps last_seen AFTER the visit" || bad "last_seen stamp" "$(cat "$GC_CALLS")"

recur_live ',"triage.last_seen":"idea-1"' "$IDEA"   # unchanged set
FAKE_LIVE="$TMP/live-recur.json" run_sweep "$EXPECT_SURVIVORS,idea-1"
grep -q "subj-ideas: skipped-unchanged" <<< "$OUT" \
    && ok "an unchanged set skips (the park-shaped case)" || bad "recurrence unchanged" "$OUT"
grep -q "subj-ideas triage-recurrence" "$ESC_CALLS" \
    && bad "no visit on an unchanged set" "filed anyway" || ok "no visit on an unchanged set"

recur_live ',"triage.last_seen":"idea-1"' '[]'      # scope EMPTIED
FAKE_LIVE="$TMP/live-recur.json" run_sweep "$EXPECT_SURVIVORS"
grep -q "subj-ideas triage-recurrence" "$ESC_CALLS" \
    && ok "an emptied scope is a change — one last visit names what left" \
    || bad "recurrence emptied" "$(cat "$ESC_CALLS")"
grep -q "Left: idea-1" "$ESC_BODIES" && ok "…and the body names the leaver" || bad "leaver named" "$(cat "$ESC_BODIES")"
grep -q 'bd update subj-ideas --set-metadata triage.last_seen=$' "$GC_CALLS" \
    && ok "…and the stamp records the empty set" || bad "empty-set stamp" "$(grep subj-ideas "$GC_CALLS" || true)"

recur_live '' '[]'                                   # absent + empty scope
FAKE_LIVE="$TMP/live-recur.json" run_sweep "$EXPECT_SURVIVORS"
grep -q "subj-ideas: skipped-no-candidates" <<< "$OUT" \
    && ok "absent last_seen + empty scope → skip" || bad "recurrence empty skip" "$OUT"
grep -q 'bd update subj-ideas --set-metadata triage.last_seen=$' "$GC_CALLS" \
    && ok "…and the ABSENT key is stamped to the empty set" || bad "absent-key stamp" "$(cat "$GC_CALLS")"

recur_live ',"triage.last_seen":""' "$IDEA"          # live visit on the subject
jq '. + [{"id":"v-ideas","status":"in_progress","title":"visit: subj-ideas","metadata":{"task_kind":"visit","gc.continuation_group":"subj-ideas"}}]' \
    "$TMP/live-recur.json" > "$TMP/live-recur2.json"
FAKE_LIVE="$TMP/live-recur2.json" run_sweep "$EXPECT_SURVIVORS,idea-1"
grep -q "subj-ideas: skipped-live-visit" <<< "$OUT" \
    && ok "a live visit on the subject skips" || bad "recurrence live-visit skip" "$OUT"
grep -q 'bd update subj-ideas' "$GC_CALLS" \
    && bad "…and stamps NOTHING on that path" "stamped anyway: $(grep subj-ideas "$GC_CALLS")" \
    || ok "…and stamps NOTHING on that path (the set was never shown)"

echo "── the pass owns the cadence window and spends it before it reads ──"
# liveness-sweep-precheck.sh, the order's `check`, never spends this stamp on
# a RUN verdict. A check is evaluated by callers that never dispatch — the
# controller tick, the API order evaluator, `gc order check` — so a check that
# stamped its own RUN hands the pass to whichever caller asks first.
STAMP_FILE="$TMP/state/testrig/last-pass"
run_sweep ABSENT
STAMPED="$(cat "$STAMP_FILE" 2>/dev/null)"
case "${STAMPED:-x}" in
    ''|*[!0-9]*) bad "a completed pass stamps the window" "got '${STAMPED:-<none>}', want epoch seconds" ;;
    *) ok "a completed pass stamps the window" ;;
esac
# BEFORE the reads: an aborting pass must still have spent the window, or the
# check keeps saying RUN and a degraded store dispatches a pass every tick.
GC_READY_FAIL=1 run_sweep "old-baseline"
[ -s "$STAMP_FILE" ] && ok "a pass that aborts on an unreadable listing still spent the window" \
    || bad "a pass that aborts still spent the window" "no stamp; every tick would dispatch"
# A dry run is not a pass.
rm -rf "$TMP/state"; mkdir -p "$TMP/state/testrig"
bash "$SCRIPT" --dry-run >/dev/null 2>&1
[ -f "$STAMP_FILE" ] && bad "--dry-run does not spend the window" "it wrote $STAMP_FILE" \
    || ok "--dry-run does not spend the window"
# liveness-sweep-precheck.sh's writability guard probes the state DIRECTORY;
# the write it stands for is this one. A last-pass whose own mode is read-only
# must still take the new window, or the guard passes, the pass runs, the
# window never closes, and the order dispatches another pass on every tick.
if [ "$(id -u)" -eq 0 ]; then
    ok "a read-only last-pass still takes the window (skipped: running as root)"
else
    rm -rf "$TMP/state"; mkdir -p "$TMP/state/testrig"
    STALE="$(( $(date -u +%s) - 99999 ))"
    printf '%s\n' "$STALE" > "$STAMP_FILE"
    chmod 400 "$STAMP_FILE"
    bash "$SCRIPT" >/dev/null 2>"$TMP/err"
    chmod 600 "$STAMP_FILE" 2>/dev/null || true
    [ "$(cat "$STAMP_FILE" 2>/dev/null)" != "$STALE" ] \
        && ok "a read-only last-pass still takes the window" \
        || bad "a read-only last-pass still takes the window" "still reads $STALE — the cadence has no floor"
    grep -q "cannot stamp the cadence window" "$TMP/err" \
        && bad "and never reached the warn arm" "$(cat "$TMP/err")" \
        || ok "and never reached the warn arm"
fi

echo "── landed-fix wedge: a must-fix finding whose fix unit CLOSED escalates its anchor ──"
# The deadlock's silent shape: an anchor at pre_open_gate held by a must-fix
# finding whose fix unit has landed (closed), which gate-ensure's close-answered
# should have closed. The anchor is blocked by its own finding, so it never
# reaches `bd ready` or the classify census — this backstop scans ALIVE.
printf '[]\n' > "$TMP/ready.json"
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"w-anchor","status":"open","title":"wedged at pre_open_gate","metadata":{"merge_result":"pre_open_gate","branch":"polecat/w-anchor"}},
  {"id":"w-find","status":"open","title":"must-fix finding","metadata":{"task_kind":"finding","finding.disposition":"must-fix","anchor_bead":"w-anchor"}}
]
JSON
printf '[]\n' > "$TMP/widen.json"
printf '%s\n' '[{"id":"w-fix","status":"closed","metadata":{"task_kind":"rework"}}]' > "$TMP/show/dep-w-find.json"
run_sweep
grep -q '^w-anchor landed-fix-wedge$' "$ESC_CALLS" \
    && ok "a must-fix finding whose fix unit closed escalates its wedged anchor" \
    || bad "landed-fix wedge escalated" "esc-calls: $(cat "$ESC_CALLS")"
grep -q 'the fix is on the branch' "$ESC_BODIES" \
    && ok "…and the visit body names the landed-fix wedge" || bad "wedge body" "$(cat "$ESC_BODIES")"

echo "── …but a fix unit still IN FLIGHT is not a wedge — nothing escalated ──"
printf '%s\n' '[{"id":"w-fix","status":"open","metadata":{"task_kind":"rework"}}]' > "$TMP/show/dep-w-find.json"
run_sweep
grep -q 'w-anchor landed-fix-wedge' "$ESC_CALLS" \
    && bad "an in-flight fix unit's finding escalated" "esc-calls: $(cat "$ESC_CALLS")" \
    || ok "an in-flight fix unit's finding is left for its landing — nothing escalated"

echo "── …and a must-fix finding NO fix unit blocks is a live objection, not a wedge ──"
printf '[]\n' > "$TMP/show/dep-w-find.json"
run_sweep
grep -q 'w-anchor landed-fix-wedge' "$ESC_CALLS" \
    && bad "an unanswered objection escalated as a wedge" "esc-calls: $(cat "$ESC_CALLS")" \
    || ok "a finding no fix unit blocks is not a wedge — nothing escalated"

echo "── edge-less wedge: a must-fix finding with NO edge whose lane fix LANDED escalates ──"
# The silent shape the original backstop missed: the close-ordering edge was never
# hung, so the finding has no blocker at all, yet its lane's fix unit has closed.
# Caught from the lane census (anchor_bead + rework), not the finding's edges.
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"we-anchor","status":"open","title":"edge-less wedge at pre_open_gate","metadata":{"merge_result":"pre_open_gate","branch":"polecat/we-anchor"}},
  {"id":"we-find","status":"open","title":"edge-less must-fix finding","metadata":{"task_kind":"finding","finding.disposition":"must-fix","finding.lane":"codex","anchor_bead":"we-anchor"}}
]
JSON
printf '[]\n' > "$TMP/show/dep-we-find.json"   # edge-less: the finding has no blocker
printf '%s\n' '[{"id":"we-fix","status":"closed","metadata":{"task_kind":"rework","anchor_bead":"we-anchor","source_review_bead":"we-rev"}}]' > "$TMP/show/reworks-we-anchor.json"
run_sweep
grep -q '^we-anchor landed-fix-wedge$' "$ESC_CALLS" \
    && ok "an edge-less finding whose lane fix landed escalates its wedged anchor" \
    || bad "edge-less wedge escalated" "esc-calls: $(cat "$ESC_CALLS")"
grep -q 'edge-less' "$ESC_BODIES" \
    && ok "…and the visit body names the edge-less shape" || bad "edge-less body" "$(cat "$ESC_BODIES")"

echo "── …but an edge-less finding whose lane fix is still IN FLIGHT is not a wedge ──"
printf '%s\n' '[{"id":"we-fix","status":"open","metadata":{"task_kind":"rework","anchor_bead":"we-anchor","source_review_bead":"we-rev"}}]' > "$TMP/show/reworks-we-anchor.json"
run_sweep
grep -q 'we-anchor landed-fix-wedge' "$ESC_CALLS" \
    && bad "an edge-less finding with an in-flight lane fix escalated" "esc-calls: $(cat "$ESC_CALLS")" \
    || ok "an edge-less finding whose lane fix is in flight is left for its landing — nothing escalated"

echo "── the phase-aware census asks the resolver, with a controlled index ──"
# A real index (not the missing-file fallback the rest of this file uses):
# correctness reads the diff (pre-open), demo needs the preview (open-as-draft).
# codex is declared NOWHERE — a legacy token the resolver defaults to pre-open,
# the case the old re-implemented phase filter DROPPED, classing a green
# legacy-token anchor as un-gated and flagging it.
PH_IDX="$TMP/phase-index.toml"
printf '[checks.correctness]\nmethod="m"\npurpose="p"\nphase="pre-open"\n[checks.demo]\nmethod="m"\npurpose="p"\nphase="open-as-draft"\n' > "$PH_IDX"
printf '%s\n' '[
  {"id":"ph-legacy-green","title":"pre-open, legacy codex green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"green"}},
  {"id":"ph-draft-pending","title":"pre-open green, open-as-draft demo pending","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"correctness,demo","check.correctness":"green"}},
  {"id":"ph-preopen-ungreen","title":"pre-open correctness ungreen","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"correctness,demo","check.demo":"green"}},
  {"id":"ph-mixed-case-green","title":"pre-open, mixed-case lane green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"correctness,Arch","check.correctness":"green","check.Arch":"green"}}
]' > "$TMP/ph-ready.json"
GC_REVIEW_CHECKS_INDEX="$PH_IDX" FAKE_READY="$TMP/ph-ready.json" run_sweep ABSENT
eq "$RC" "0" "the phase-aware pass completes"
# Only ph-preopen-ungreen is an unnamed wait: the legacy codex token gated pre-open
# (resolver default, not dropped) and its green read as converged; the open-as-draft
# demo did NOT hold the pre-open census; a genuinely ungreen pre-open lane still does.
# The mixed-case lane reads its marker under the token's own case (check.Arch), the
# key signoff stamps, so it reads green rather than flagged.
eq "$(cat "$BASELINE_FILE" 2>/dev/null)" "ph-preopen-ungreen" \
   "the resolver classes the legacy-token, draft-pending and mixed-case anchors gated; only the pre-open-ungreen one is unnamed"

echo "── holder liveness gates the conversing class (readable session list) ──"
# Two visits track two ready subjects: one held by a live session (lx-live-1 is
# in FAKE_SESSIONS), one by a gone session (lx-dead-9 is not). A third subject is
# a visit bead left in the ready set by that gone session. The live-held subject
# stays covered; the dead-held subject and the stranded visit bead return to the
# census. Two more visits track workflow ROOTS, so the ready steps under them are
# covered through gc.root_bead_id by the same holder test. Self-contained
# fixtures — the suite above clobbers the shared ones.
cat > "$TMP/hl-ready.json" <<'JSON'
[
  {"id":"hl-live-subj","title":"subject of a live-held visit","issue_type":"task","metadata":{}},
  {"id":"hl-dead-subj","title":"subject of a dead-held visit","issue_type":"task","metadata":{}},
  {"id":"hl-ready-deadvisit","title":"a visit stranded ready by a dead session","issue_type":"task","metadata":{"task_kind":"visit","gc.session_id":"lx-dead-9"}},
  {"id":"hl-live-root-step","title":"a step of a root a live-held visit tracks","issue_type":"task","metadata":{"gc.root_bead_id":"hl-live-root"}},
  {"id":"hl-dead-root-step","title":"a step of a root a dead-held visit tracks","issue_type":"task","metadata":{"gc.root_bead_id":"hl-dead-root"}}
]
JSON
cat > "$TMP/hl-live.json" <<'JSON'
[
  {"id":"tk-subject","status":"open","title":"triage: unnamed waits (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits"}},
  {"id":"hl-v-live","status":"in_progress","title":"visit: hl-live-subj","metadata":{"task_kind":"visit","gc.session_id":"lx-live-1"},"dependencies":[{"issue_id":"hl-v-live","depends_on_id":"hl-live-subj","type":"tracks"}]},
  {"id":"hl-v-dead","status":"in_progress","title":"visit: hl-dead-subj","metadata":{"task_kind":"visit","gc.session_id":"lx-dead-9"},"dependencies":[{"issue_id":"hl-v-dead","depends_on_id":"hl-dead-subj","type":"tracks"}]},
  {"id":"hl-v-liveroot","status":"in_progress","title":"visit: hl-live-root","metadata":{"task_kind":"visit","gc.session_id":"lx-live-1"},"dependencies":[{"issue_id":"hl-v-liveroot","depends_on_id":"hl-live-root","type":"tracks"}]},
  {"id":"hl-v-deadroot","status":"in_progress","title":"visit: hl-dead-root","metadata":{"task_kind":"visit","gc.session_id":"lx-dead-9"},"dependencies":[{"issue_id":"hl-v-deadroot","depends_on_id":"hl-dead-root","type":"tracks"}]}
]
JSON
printf '[]\n' > "$TMP/hl-widen.json"
printf '%s\n' '[{"id":"hl-live-root","metadata":{}}]' > "$TMP/show/hl-live-root.json"
printf '%s\n' '[{"id":"hl-dead-root","metadata":{}}]' > "$TMP/show/hl-dead-root.json"
FAKE_READY="$TMP/hl-ready.json" FAKE_LIVE="$TMP/hl-live.json" FAKE_WIDEN="$TMP/hl-widen.json" run_sweep ABSENT
BL="$(cat "$BASELINE_FILE" 2>/dev/null)"
case ",$BL," in *",hl-live-subj,"*) bad "live-held visit over-surfaces" "hl-live-subj surfaced though lx-live-1 is alive" ;; *) ok "a live-held visit keeps its subject out of the census" ;; esac
case ",$BL," in *",hl-dead-subj,"*) ok "a dead-held visit returns its subject to the census" ;; *) bad "dead-held subject hidden" "hl-dead-subj stayed masked (baseline: $BL)" ;; esac
case ",$BL," in *",hl-ready-deadvisit,"*) ok "a visit stranded ready by a gone session surfaces (arm 1)" ;; *) bad "stranded visit bead hidden" "hl-ready-deadvisit stayed conversing (baseline: $BL)" ;; esac
case ",$BL," in *",hl-live-root-step,"*) bad "a step under a live-held visit's root over-surfaces" "hl-live-root-step surfaced though its root's visit is held by lx-live-1" ;; *) ok "a step whose root a live-held visit tracks stays out of the census" ;; esac
case ",$BL," in *",hl-dead-root-step,"*) ok "a step whose root a dead-held visit tracks returns to the census" ;; *) bad "dead-held root step hidden" "hl-dead-root-step stayed masked (baseline: $BL)" ;; esac

echo "── a holder listed in a TERMINAL state (archived/closed) is dead, not live ──"
# A sitting that lingers in the list as closed/archived is dead, per helm's
# ownerLive — its held visit must stop covering its subject. A holder listed in
# any other state (asleep here) is live and keeps covering, so the gate excludes
# the terminal states only, not everything that is not "active".
cat > "$TMP/hl-term-sessions.json" <<'JSON'
{"sessions":[
  {"id":"lx-closed-7","state":"closed","closed":true,"session_name":"s-lx-closed-7","alias":"","name":"","agent_name":""},
  {"id":"lx-arch-8","state":"archived","closed":true,"session_name":"s-lx-arch-8","alias":"","name":"","agent_name":""},
  {"id":"lx-asleep-2","state":"asleep","closed":false,"session_name":"s-lx-asleep-2","alias":"","name":"","agent_name":""}
]}
JSON
cat > "$TMP/hl-term-ready.json" <<'JSON'
[
  {"id":"hl-closed-subj","title":"subject of a visit held by a CLOSED session","issue_type":"task","metadata":{}},
  {"id":"hl-arch-subj","title":"subject of a visit held by an ARCHIVED session","issue_type":"task","metadata":{}},
  {"id":"hl-asleep-subj","title":"subject of a visit held by an ASLEEP (live) session","issue_type":"task","metadata":{}}
]
JSON
cat > "$TMP/hl-term-live.json" <<'JSON'
[
  {"id":"tk-subject","status":"open","title":"triage: unnamed waits (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits"}},
  {"id":"hl-v-closed","status":"in_progress","title":"visit: hl-closed-subj","metadata":{"task_kind":"visit","gc.session_id":"lx-closed-7"},"dependencies":[{"issue_id":"hl-v-closed","depends_on_id":"hl-closed-subj","type":"tracks"}]},
  {"id":"hl-v-arch","status":"in_progress","title":"visit: hl-arch-subj","metadata":{"task_kind":"visit","gc.session_id":"lx-arch-8"},"dependencies":[{"issue_id":"hl-v-arch","depends_on_id":"hl-arch-subj","type":"tracks"}]},
  {"id":"hl-v-asleep","status":"in_progress","title":"visit: hl-asleep-subj","metadata":{"task_kind":"visit","gc.session_id":"lx-asleep-2"},"dependencies":[{"issue_id":"hl-v-asleep","depends_on_id":"hl-asleep-subj","type":"tracks"}]}
]
JSON
FAKE_SESSIONS="$TMP/hl-term-sessions.json" FAKE_READY="$TMP/hl-term-ready.json" FAKE_LIVE="$TMP/hl-term-live.json" FAKE_WIDEN="$TMP/hl-widen.json" run_sweep ABSENT
BLT="$(cat "$BASELINE_FILE" 2>/dev/null)"
case ",$BLT," in *",hl-closed-subj,"*) ok "a CLOSED but still-listed holder returns its subject to the census" ;; *) bad "closed-held subject hidden" "hl-closed-subj stayed masked (baseline: $BLT)" ;; esac
case ",$BLT," in *",hl-arch-subj,"*) ok "an ARCHIVED but still-listed holder returns its subject to the census" ;; *) bad "archived-held subject hidden" "hl-arch-subj stayed masked (baseline: $BLT)" ;; esac
case ",$BLT," in *",hl-asleep-subj,"*) bad "asleep-held visit over-surfaces" "hl-asleep-subj surfaced though lx-asleep-2 is a live (non-terminal) session" ;; *) ok "a non-terminal (asleep) holder keeps its subject covered" ;; esac

echo "── an unreadable session list keeps every visit covering (unprovable death) ──"
GC_SESSION_FAIL=1 FAKE_READY="$TMP/hl-ready.json" FAKE_LIVE="$TMP/hl-live.json" FAKE_WIDEN="$TMP/hl-widen.json" run_sweep ABSENT
BLF="$(cat "$BASELINE_FILE" 2>/dev/null)"
for hidden in hl-dead-subj hl-ready-deadvisit hl-live-subj hl-dead-root-step hl-live-root-step; do
  case ",$BLF," in *",$hidden,"*) bad "fail-open surfaced $hidden" "an unreadable session list must hide nothing new (baseline: $BLF)" ;; *) ok "unreadable session list → $hidden keeps covering" ;; esac
done

echo
echo "liveness-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
