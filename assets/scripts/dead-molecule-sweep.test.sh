#!/usr/bin/env bash
# Hermetic test for assets/scripts/dead-molecule-sweep.sh.
#
# The sweep enumerates the non-closed workflow roots in one store and hands each
# to dead-molecule-dispose.sh. It holds no safety of its own, so this test
# proves exactly two things: it finds every non-closed workflow root (and
# nothing else), and it reports each root's verdict faithfully — disposing the
# dead husk while the real disposer refuses the live molecule, the held one with
# an open escalation, and the one whose source is mid-PR, all in a single store.
# Preview touches nothing; an unreadable listing is not an empty backlog.
#
# No live city, Dolt, network, gc or bd — stubs from test-harness.sh only. The
# sweep and the disposer are copied into a private dir so the sweep's sibling
# resolution of the disposer hits the copy, never the live tree.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-dead-molecule-sweep-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
unset GC_RIG_ROOT   # or the stubs' --db would point at a real .beads

mk_sut_dir "$TMP/sut" "$HERE/dead-molecule-sweep.sh" "$HERE/dead-molecule-dispose.sh"
SWEEP="$TMP/sut/dead-molecule-sweep.sh"

# Five molecules in one store, one of each verdict the disposer can reach:
#   tk-d* DEAD husk        — disposes.
#   tk-l* LIVE molecule    — a member runs under live session lx-live; refused.
#   tk-h* HELD             — an open escalation visit tracks its work bead; refused.
#   tk-p* SOURCE mid-PR    — its work bead carries merge_result=pull_request; refused.
#   tk-u* SOURCE PR ref    — its work bead carries pr_number with no merge_result; refused.
# Plus a non-workflow bead the enumeration must not pick up.
fixture() {
  store '[
    {"id":"tk-d","status":"in_progress","assignee":"","title":"mol","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-dc","gc.session_name":"pool-slot-gone"}},
    {"id":"tk-d1","status":"blocked","assignee":"","title":"load","metadata":{"gc.step_ref":"m.load","gc.root_bead_id":"tk-d","gc.routed_to":"gc-toolkit/gc-toolkit.polecat","gc.session_id":"lx-dead"}},
    {"id":"tk-dw","status":"open","assignee":"","title":"work d","metadata":{}},
    {"id":"tk-dc","status":"open","assignee":"","title":"convoy d","metadata":{}},

    {"id":"tk-l","status":"in_progress","assignee":"","title":"mol","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-lc","gc.session_name":"pool-slot-gone"}},
    {"id":"tk-l1","status":"in_progress","assignee":"","title":"impl","metadata":{"gc.step_ref":"m.impl","gc.root_bead_id":"tk-l","gc.session_id":"lx-live"}},
    {"id":"tk-lw","status":"open","assignee":"","title":"work l","metadata":{}},
    {"id":"tk-lc","status":"open","assignee":"","title":"convoy l","metadata":{}},

    {"id":"tk-h","status":"in_progress","assignee":"","title":"mol","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-hc","gc.session_name":"pool-slot-gone"}},
    {"id":"tk-h1","status":"blocked","assignee":"","title":"load","metadata":{"gc.step_ref":"m.load","gc.root_bead_id":"tk-h","gc.session_id":"lx-dead"}},
    {"id":"tk-hw","status":"open","assignee":"","title":"work h","metadata":{}},
    {"id":"tk-hc","status":"open","assignee":"","title":"convoy h","metadata":{}},
    {"id":"tk-hv","status":"open","assignee":"","title":"visit","metadata":{"escalation_key":"held","task_kind":"visit"}},

    {"id":"tk-p","status":"in_progress","assignee":"","title":"mol","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-pc","gc.session_name":"pool-slot-gone"}},
    {"id":"tk-p1","status":"blocked","assignee":"","title":"load","metadata":{"gc.step_ref":"m.load","gc.root_bead_id":"tk-p","gc.session_id":"lx-dead"}},
    {"id":"tk-pw","status":"open","assignee":"","title":"work p","metadata":{"merge_result":"pull_request"}},
    {"id":"tk-pc","status":"open","assignee":"","title":"convoy p","metadata":{}},

    {"id":"tk-u","status":"in_progress","assignee":"","title":"mol","metadata":{"gc.kind":"workflow","gc.formula_contract":"graph.v2","gc.input_convoy_id":"tk-uc","gc.session_name":"pool-slot-gone"}},
    {"id":"tk-u1","status":"blocked","assignee":"","title":"load","metadata":{"gc.step_ref":"m.load","gc.root_bead_id":"tk-u","gc.session_id":"lx-dead"}},
    {"id":"tk-uw","status":"open","assignee":"","title":"work u","metadata":{"pr_number":"77"}},
    {"id":"tk-uc","status":"open","assignee":"","title":"convoy u","metadata":{}},

    {"id":"tk-plain","status":"open","assignee":"","title":"not a molecule","metadata":{}}
  ]'
  : > "$STUB_GC_LOG"; : > "$STUB_SESSION_LOG"
  printf 'tk-dc|tracks|tk-dw\ntk-lc|tracks|tk-lw\ntk-hc|tracks|tk-hw\ntk-pc|tracks|tk-pw\ntk-uc|tracks|tk-uw\ntk-hv|tracks|tk-hw\n' > "$STUB_DEPS"
  printf '%s' '{"sessions":[{"id":"lx-live","session_name":"","alias":"","state":"active"}]}' > "$TMP/sessions.json"
  export STUB_SESSIONS="$TMP/sessions.json" STUB_SESSION_LIST_RC=""
}

echo "--- preview is the default: every root judged, nothing written ---"
fixture
OUT=$("$SWEEP" --json 2>/dev/null); rc=$?
eq "$rc" "0" "preview exits 0"
printf '%s' "$OUT" | jq -e '.applied == false and .roots == 5' >/dev/null 2>&1 \
  && ok "the five workflow roots are enumerated (the plain bead is not)" \
  || bad "preview enumeration wrong: $OUT"
printf '%s' "$OUT" | jq -e '.previewed == 1 and .refused == 3 and .live == 1' >/dev/null 2>&1 \
  && ok "preview verdicts: 1 would-dispose, 1 live, 3 refused" \
  || bad "preview verdicts wrong: $OUT"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "preview issued no write at all"
eq "$(bstatus tk-d)" "in_progress" "preview left the dead husk's root alone"

echo "--- apply: the dead husk disposes, the other four are refused ---"
fixture
OUT=$("$SWEEP" --apply --json 2>/dev/null); rc=$?
eq "$rc" "0" "apply exits 0 (all roots ran, chains intact)"
printf '%s' "$OUT" | jq -e '.applied == true and .roots == 5 and .disposed == 1 and .live == 1 and .refused == 3' >/dev/null 2>&1 \
  && ok "tally: disposed=1 live=1 refused=3" \
  || bad "apply tally wrong: $OUT"
# The dead husk is gone.
eq "$(bstatus tk-d)" "closed" "the dead husk root is closed"
eq "$(bstatus tk-d1)" "closed" "the dead husk step is closed"
eq "$(meta tk-d1 gc.routed_to)" "<absent>" "the dead husk step is de-routed"
eq "$(meta tk-d1 gc.outcome)" "moot" "the dead husk step records moot"
# The live molecule is untouched.
eq "$(bstatus tk-l)" "in_progress" "the live molecule's root is untouched"
eq "$(bstatus tk-l1)" "in_progress" "the live molecule's step is untouched"
eq "$(meta tk-l1 gc.session_id)" "lx-live" "the live molecule keeps its session pin"
# The held molecule is untouched.
eq "$(bstatus tk-h)" "in_progress" "the held molecule's root is untouched"
eq "$(bstatus tk-hv)" "open" "the held molecule's escalation visit is untouched"
# The mid-PR molecule is untouched, merge_result intact.
eq "$(bstatus tk-p)" "in_progress" "the mid-PR molecule's root is untouched"
eq "$(meta tk-pw merge_result)" "pull_request" "the mid-PR work bead keeps its merge_result"
# The PR-reference molecule is untouched, pr_number intact.
eq "$(bstatus tk-u)" "in_progress" "the PR-reference molecule's root is untouched"
eq "$(meta tk-uw pr_number)" "77" "the PR-reference work bead keeps its pr_number"
# No work bead or convoy — the enumeration excludes them — is ever closed.
for B in tk-dw tk-dc tk-lw tk-hw tk-pw tk-uw tk-uc tk-plain; do
  eq "$(bstatus $B)" "open" "$B (work bead / convoy / non-molecule) is never touched"
done

echo "--- an unreadable root listing is not an empty backlog ---"
fixture
export STUB_LIST_FAIL="1"
OUT=$("$SWEEP" --apply --json 2>/dev/null); rc=$?
export STUB_LIST_FAIL=""
eq "$rc" "1" "an unreadable listing exits 1"
printf '%s' "$OUT" | jq -e '.result == "unreadable"' >/dev/null 2>&1 \
  && ok "it says unreadable, not a clean sweep" || bad "unreadable payload wrong: $OUT"
hasnt "$(cat "$STUB_GC_LOG")" "bd update" "an unreadable listing draws no write"

echo "--- text output names each root's verdict ---"
fixture
OUT=$("$SWEEP" --apply 2>&1)
has "$OUT" "disposed=1" "the summary line tallies the disposal"
has "$OUT" "tk-d	disposed" "the per-root line names the disposed husk"

echo "--- usage ---"
"$SWEEP" --db >/dev/null 2>&1; eq "$?" "2" "a value-taking flag at end of argv exits 2"
"$SWEEP" --nope >/dev/null 2>&1; eq "$?" "2" "an unknown flag exits 2"
"$SWEEP" extra >/dev/null 2>&1; eq "$?" "2" "a positional argument exits 2"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
