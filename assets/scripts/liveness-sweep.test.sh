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
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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
      *--status=closed*)
        if [ -n "${PRIOR_VISITS:-}" ] && [ -f "${PRIOR_VISITS:-}" ]; then cat "$PRIOR_VISITS"; fi
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
  "bd create")
    printf 'bd create %s\n' "$*" >> "$GC_CALLS"
    printf '{"id":"tk-subj-new"}\n'; exit 0 ;;
  "bd update")
    printf 'bd update %s\n' "$*" >> "$GC_CALLS"; exit 0 ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

# gh stub: only signal-loom answers, with #521/#522 open (so #520 merged and
# #999 closed stay VISIBLE through the intersection). GH_FAIL = a real outage.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
[ -n "${GH_FAIL:-}" ] && exit 1
repo=""
while [ $# -gt 0 ]; do case "$1" in --repo) repo="$2"; shift 2 ;; *) shift ;; esac; done
case "$repo" in
  */zookanalytics/signal-loom|zookanalytics/signal-loom)
    printf '%s\n' '[{"url":"https://github.com/zookanalytics/signal-loom/pull/521"},{"url":"https://github.com/zookanalytics/signal-loom/pull/522"}]' ;;
  *) printf '[]\n' ;;
esac
GH
chmod +x "$TMP/bin/gh"

# escalate.sh stub: records the call, answers like the real tool.
cat > "$TMP/bin/escalate.sh" <<'ESC'
#!/usr/bin/env bash
[ -n "${ESC_FAIL:-}" ] && { echo "escalate: down" >&2; exit 1; }
subject=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) subject="$2"; shift 2 ;;
    --key)     key="$2"; shift 2 ;;
    --message) printf '%s\n---\n' "$2" >> "$ESC_BODIES"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s %s\n' "$subject" "$key" >> "$ESC_CALLS"
echo "escalate: filed visit tk-visit1 on $subject [$key] -> gc-toolkit.converse"
ESC
chmod +x "$TMP/bin/escalate.sh"

export PATH="$TMP/bin:$PATH"
export SHOW_DIR="$TMP/show" GC_CALLS="$TMP/gc-calls" ESC_CALLS="$TMP/esc-calls" ESC_BODIES="$TMP/esc-bodies"
export GC_ESCALATE_TOOL="$TMP/bin/escalate.sh"
export GC_RIG=testrig
export LIVENESS_SWEEP_STATE_DIR="$TMP/state"
unset GC_RIG_ROOT GC_PACK_STATE_DIR 2>/dev/null || true
BASELINE_FILE="$TMP/state/testrig/reported"

# --- fixtures (the classification population from the retired delta test) -----
cat > "$TMP/ready.json" <<'JSON'
[
  {"id":"c-plain","title":"an ordinary idle bug","issue_type":"bug"},
  {"id":"c-routed","title":"already dispatched","issue_type":"task","metadata":{"gc.routed_to":"rig/rig.polecat"}},
  {"id":"c-visit","title":"visit: something","issue_type":"task","metadata":{"task_kind":"visit"}},
  {"id":"c-subject","title":"triage: a scope","issue_type":"task","metadata":{"task_kind":"triage-subject"}},
  {"id":"c-pattern","title":"a distiller cluster anchor","issue_type":"task","metadata":{"task_kind":"feedback-pattern"}},
  {"id":"c-docupdate","title":"a doc-update bead nobody routed","issue_type":"task","metadata":{"task_kind":"doc-update"}},
  {"id":"c-ingroup","title":"subject of a live visit","issue_type":"task","metadata":{}},
  {"id":"c-trackedvisit","title":"subject of a live visit whose stamp landed EMPTY","issue_type":"task","metadata":{}},
  {"id":"c-takeaway","title":"parked by a human","issue_type":"epic","metadata":{"gc.takeaway":"needs operator ratify"}},
  {"id":"c-takeaway-empty","title":"hold was cleared","issue_type":"task","metadata":{"gc.takeaway":""}},
  {"id":"c-pr-open","title":"parked on an open PR","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/zookanalytics/signal-loom/pull/521"}},
  {"id":"c-pr-case","title":"same PR, different case + trailing path","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://GitHub.com/zookanalytics/signal-loom/pull/522/files"}},
  {"id":"c-pr-merged","title":"landed — surfaces for close-out","issue_type":"task","metadata":{"merge_result":"merged","pr_url":"https://github.com/zookanalytics/signal-loom/pull/520"}},
  {"id":"c-pr-closed","title":"rejected — closed unmerged","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/zookanalytics/signal-loom/pull/999"}},
  {"id":"c-pr-otherrepo","title":"number 521 in another repository","issue_type":"task","metadata":{"merge_result":"pull_request","pr_url":"https://github.com/someone/elsewhere/pull/521"}},
  {"id":"c-pr-nourl","title":"marker but no pr_url","issue_type":"task","metadata":{"merge_result":"pull_request"}},
  {"id":"c-preopen-green","title":"pre-open, codex green","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"green@756d5d7"}},
  {"id":"c-preopen-multigreen","title":"pre-open, two gates green (spaced)","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex, ci","check.codex":"green@aa11","check.ci":"green@aa11"}},
  {"id":"c-preopen-approval","title":"pre-open, green + approval sentinel","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,approval","check.codex":"green@bb22"}},
  {"id":"c-preopen-fixable","title":"pre-open, fixable — stalled","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex","check.codex":"fixable@4b366f"}},
  {"id":"c-preopen-partial","title":"pre-open, one of two markers absent","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex,ci","check.codex":"green@cc33"}},
  {"id":"c-preopen-nomarker","title":"pre-open, no marker at all","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"codex"}},
  {"id":"c-preopen-noset","title":"pre-open, marker but check_set unset","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check.codex":"green@dd44"}},
  {"id":"c-preopen-none","title":"pre-open, check_set=none opt-out","issue_type":"task","metadata":{"merge_result":"pre_open_gate","check_set":"none"}},
  {"id":"c-hold","title":"operator decided this waits","issue_type":"task","metadata":{"triage.hold":"deferred; operator direction pending"}},
  {"id":"c-hold-bare","title":"held, no reason named","issue_type":"task","metadata":{"triage.hold":"true"}},
  {"id":"c-hold-empty","title":"hold was cleared","issue_type":"task","metadata":{"triage.hold":""}},
  {"id":"c-worked","title":"a work bead a live molecule is driving","issue_type":"bug","metadata":{}},
  {"id":"c-husk-tracked","title":"tracked only by a dead synthetic convoy","issue_type":"bug","metadata":{}},
  {"id":"c-inputconvoy","title":"input convoy for c-plain","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-slingconvoy","title":"sling-c-plain","issue_type":"convoy"},
  {"id":"c-synthconvoy","title":"a machine convoy under another name","issue_type":"convoy","metadata":{"gc.synthetic":"true"}},
  {"id":"c-realconvoy","title":"an unowned floating convoy — the orphan to catch","issue_type":"convoy","metadata":{}},
  {"id":"c-titletalk","title":"input convoy for tk-x never closes","issue_type":"bug","metadata":{}},
  {"id":"c-slingtalk","title":"sling-created convoys are never reaped","issue_type":"bug","metadata":{}},
  {"id":"c-husk-step-1","title":"load context","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-husk-step-2","title":"implement","issue_type":"task","metadata":{"gc.root_bead_id":"root-landed"}},
  {"id":"c-live-step","title":"a step of an in-flight workflow","issue_type":"task","metadata":{"gc.root_bead_id":"root-live"}},
  {"id":"c-noconvoy-step","title":"a step whose root names no convoy","issue_type":"task","metadata":{"gc.root_bead_id":"root-noconvoy"}},
  {"id":"c-rootvisit-step","title":"a step of a root under a live stall visit","issue_type":"task","metadata":{"gc.root_bead_id":"root-underconversation"}},
  {"id":"c-parented","title":"a parent whose child is still open","issue_type":"epic","metadata":{}},
  {"id":"c-trackslive","title":"tracks a not-closed bead","issue_type":"task","metadata":{},"dependencies":[{"depends_on_id":"m-live","type":"tracks"}]}
]
JSON
# LIVE carries: the standing sweep subject, the visits (v-2 is the su-ab9je
# empty-stamp shape), the stall visit, and the live molecule that names
# conv-live. blocked-child gates c-parented via the reverse parent-child index.
cat > "$TMP/live.json" <<'JSON'
[
  {"id":"tk-subject","status":"open","title":"triage: unnamed waits (this rig)","metadata":{"task_kind":"triage-subject","triage.scope":"unnamed-waits"}},
  {"id":"v-1","status":"open","title":"visit: c-ingroup","metadata":{"task_kind":"visit","gc.continuation_group":"c-ingroup"}},
  {"id":"v-stall","status":"open","title":"visit: root-underconversation","metadata":{"task_kind":"visit","gc.continuation_group":"subj-stalled","stall_root":"root-underconversation"}},
  {"id":"v-2","status":"open","title":"visit: c-trackedvisit","metadata":{"task_kind":"visit","gc.continuation_group":""},"dependencies":[{"issue_id":"v-2","depends_on_id":"c-trackedvisit","type":"tracks"}]},
  {"id":"m-live","status":"open","title":"a live molecule","metadata":{"gc.input_convoy_id":"conv-live"}},
  {"id":"child-open","status":"open","title":"an open child of c-parented","metadata":{},"dependencies":[{"depends_on_id":"c-parented","type":"parent-child"}]}
]
JSON
printf '[]\n' > "$TMP/widen.json"
export FAKE_READY="$TMP/ready.json" FAKE_LIVE="$TMP/live.json" FAKE_WIDEN="$TMP/widen.json"

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
    RC=0
    OUT="$(bash "$SCRIPT" 2>"$TMP/err")" || RC=$?
    ERR="$(cat "$TMP/err")"
}

# The full unnamed set this population classifies to (ports the retired
# delta-test survivor assertion, plus the two structural-edge candidates the
# exec script now folds in: c-parented is gated by its open child, and
# c-trackslive by its outgoing tracks edge to a live bead).
EXPECT_SURVIVORS="c-docupdate,c-hold-empty,c-husk-tracked,c-live-step,c-noconvoy-step,c-plain,c-pr-closed,c-pr-merged,c-pr-nourl,c-pr-otherrepo,c-preopen-fixable,c-preopen-nomarker,c-preopen-none,c-preopen-noset,c-preopen-partial,c-realconvoy,c-slingtalk,c-takeaway-empty,c-titletalk"

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

echo "── each named class drops, each inverse-defect shape stays visible ──"
for drop in c-routed c-visit c-subject c-pattern c-ingroup c-trackedvisit \
            c-takeaway c-pr-open c-pr-case c-preopen-green c-preopen-multigreen \
            c-preopen-approval c-hold c-hold-bare c-worked c-inputconvoy \
            c-slingconvoy c-synthconvoy c-husk-step-1 c-husk-step-2 \
            c-rootvisit-step c-parented c-trackslive; do
    case ",$EXPECT_SURVIVORS," in
        *",$drop,"*) bad "dropped $drop" "still in the survivor set" ;;
        *) ok "dropped $drop" ;;
    esac
done
for keep in c-pr-merged c-pr-closed c-pr-otherrepo c-pr-nourl c-preopen-fixable \
            c-preopen-partial c-preopen-nomarker c-preopen-noset c-preopen-none \
            c-husk-tracked c-live-step c-noconvoy-step c-titletalk c-slingtalk \
            c-realconvoy c-docupdate c-takeaway-empty c-hold-empty; do
    case ",$(cat "$BASELINE_FILE")," in
        *",$keep,"*) ok "kept $keep" ;;
        *) bad "kept $keep" "was hidden — the inverse defect" ;;
    esac
done

echo "── the delta splits new from carried; index 0 is a real hit ──"
PARTIAL="$(printf '%s' "$EXPECT_SURVIVORS" | cut -d, -f2-)"   # all but the FIRST id
run_sweep "$PARTIAL"
grep -q "delta: 1 new, 18 carried" <<< "$OUT" \
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
prior() { printf '[{"id":"%s","metadata":{"task_kind":"visit","gc.outcome":"%s","sweep.new_ids":"%s"}}]' "$3" "$1" "$2" > "$TMP/prior.json"; }
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

echo
echo "liveness-sweep: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
