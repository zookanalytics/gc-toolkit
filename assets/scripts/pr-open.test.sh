#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-open.sh — pre_open_gate -> pull_request.
# Covers: adopting an existing OPEN or MERGED PR (one lifecycle transition, never
# a twin) and refreshing an OPEN PR's body from the anchor's current pr_summary
# before the flip (the marked region re-spliced, operator text and pr-stack's
# section kept, a failed edit holding the anchor, a pre-markers body having its
# region established over the legacy prefix, an unrecognizable or malformed shape
# holding rather than flipping stale);
# refusing fork/foreign/uncertifiable rows; the closed-unmerged headstone (fresh
# PR + supersede note; same-head close is a human decision left alone); holds
# gating the create path; the all-lanes-green gate over every gate the anchor
# declares, which no head move disturbs; the moved-head refusal on the created
# PR; the comment-not-approval verdict replay; and the de-duplicated ## Summary
# heading.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-open-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-open.sh" "$HERE/lifecycle.sh" \
  "$HERE/lane-state.sh" "$HERE/finding.sh"
SUT="$SD/pr-open.sh"

pre() { # id branch extra-json [check_set]  (4th arg empty = no check_set key)
  local cs="${4-codex}"
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s%s}}' \
    "$1" "$1" "$1" "$2" "${cs:+,\"check_set\":\"$cs\"}" "${3:-}"
}
prrow() { # num state branch head base [mergedAt] [headrepo]
  printf '{"number":%s,"url":"https://github.com/zook/gc-toolkit/pull/%s","state":"%s","mergedAt":%s,"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","headRepository":{"name":"%s"},"headRepositoryOwner":{"login":"%s"},"isCrossRepository":false}' \
    "$1" "$1" "$2" "${6:-null}" "$5" "$3" "$4" "${7:-gc-toolkit}" "${8:-zook}"
}

# A closed approve review bead backing <anchor>'s <lane> (default codex) — the
# green record lane-state.sh derives, in place of the retired check.<lane>=green
# marker. reviewed_oid is what a local backing bead must carry to green a lane.
rev() { # anchor [lane] [oid]
  printf '{"id":"rev-%s","status":"closed","assignee":"","notes":"approve","metadata":{"task_kind":"review","anchor_bead":"%s","check_name":"%s","reviewed_oid":"%s","signoff_verdict":"approve"}}' \
    "$1" "$1" "${2:-codex}" "${3:-sha-r}"
}
# An open must-fix finding on <anchor> — finding.sh open-must-fix reads it by
# disposition, so no blocks edge is needed here (merge.sh reads the edge).
finding() { # id anchor [disposition] [lane]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.disposition":"%s","finding.lane":"%s","finding.key":"%s:0"}}' \
    "$1" "$2" "${3:-must-fix}" "${4:-codex}" "${4:-codex}"
}

echo "# adopt an existing OPEN PR"
store "[$(pre A1 polecat/a1)]"
printf '[%s]' "$(prrow 41 OPEN polecat/a1 sha-a1 main)" > "$GH_DIR/pr_list_polecat_a1.json"
prrow 41 OPEN polecat/a1 sha-a1 main | jq '. + {body:"A body with no managed markers, left as it stands."}' > "$GH_DIR/pr_view_41.json"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "adoption pass exits 0"
has "$out" "already has PR#41 (OPEN); flipped to pull_request" "the open PR was adopted"
eq "$(meta A1 merge_result)" "pull_request" "anchor flipped"
eq "$(meta A1 pr_url)" "https://github.com/zook/gc-toolkit/pull/41" "pr_url recorded"
eq "$(meta A1 pr_number)" "41" "pr_number recorded"
eq "$(meta A1 merged_target)" "main" "merged_target recorded"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no twin PR was opened"
eq "$(grep -c '^bd update A1' "$STUB_GC_LOG" || true)" "1" "ONE atomic update carried the flip"

echo "# a MERGED sibling PR flips too"
store "[$(pre A2 polecat/a2)]"
printf '[%s]' "$(prrow 42 MERGED polecat/a2 sha-a2 main '"2026-08-20T00:00:00Z"')" > "$GH_DIR/pr_list_polecat_a2.json"
out=$("$SUT" 2>&1)
has "$out" "PR#42 (MERGED); flipped" "a merged PR still flips the anchor onto the observer's scan"

echo "# a fork's same-named branch is never adopted"
store "[$(pre A3 polecat/a3)]"
printf '[%s]' "$(prrow 43 OPEN polecat/a3 sha-a3 main null gc-toolkit stranger)" > "$GH_DIR/pr_list_polecat_a3.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "none is ours (name collision)" "the fork row is refused, not adopted"
eq "$(meta A3 merge_result)" "pre_open_gate" "the anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and no PR is opened into the collision"

echo "# adopting an OPEN PR refreshes its stale body from the current pr_summary"
# A rework restamped pr_summary and the anchor returned to pre_open_gate with the
# original PR still open. The body the create wrote carries the OLD summary
# between its markers; adoption re-splices the current one before the flip and
# leaves text outside the markers — an operator note, pr-stack's own section —
# in place.
store "[$(pre RF1 polecat/rf1 ',"pr_summary":"NEW: the republished summary after the rework."')]"
STALE1=$(printf '%s\n' \
  '<!-- gc:pr-summary -->' '## Summary' '' 'OLD: the summary from before the rework.' '' \
  '## Refinery handoff' '' '- Issue: RF1' '<!-- /gc:pr-summary -->' '' \
  '<!-- gc:branch-beads -->' '## Beads on this branch' '- RF1' '<!-- /gc:branch-beads -->' '' \
  'Operator note: keep this line.')
prrow 71 OPEN polecat/rf1 sha-rf1 main | jq --arg b "$STALE1" '. + {body:$b}' > "$GH_DIR/pr_view_71.json"
printf '[%s]' "$(prrow 71 OPEN polecat/rf1 sha-rf1 main)" > "$GH_DIR/pr_list_polecat_rf1.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF1 merge_result)" "pull_request" "the anchor flips after the refresh"
newbody=$(jq -r '.body' "$GH_DIR/pr_view_71.json")
has "$newbody" "NEW: the republished summary after the rework." "the current pr_summary reached the published body"
hasnt "$newbody" "OLD: the summary from before the rework." "…and the stale summary is gone"
has "$newbody" "Operator note: keep this line." "operator text outside the markers is preserved"
has "$newbody" "## Beads on this branch" "pr-stack's appended section is preserved"
has "$(cat "$STUB_GH_LOG")" "pr edit 71" "the body was edited in place, not re-created"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no twin PR"

echo "# a body refresh that fails to land holds the anchor at pre_open_gate"
store "[$(pre RF2 polecat/rf2 ',"pr_summary":"NEW: a summary that never lands."')]"
STALE2=$(printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'OLD summary.' '<!-- /gc:pr-summary -->')
prrow 72 OPEN polecat/rf2 sha-rf2 main | jq --arg b "$STALE2" '. + {body:$b}' > "$GH_DIR/pr_view_72.json"
printf '[%s]' "$(prrow 72 OPEN polecat/rf2 sha-rf2 main)" > "$GH_DIR/pr_list_polecat_rf2.json"
: > "$STUB_GH_LOG"
out=$(STUB_PR_EDIT_RC=1 "$SUT" 2>&1)
eq "$(meta RF2 merge_result)" "pre_open_gate" "a failed body edit leaves the anchor at pre_open_gate"
has "$out" "body refresh failed to land" "…and says why"

echo "# a pre-markers body has the region ESTABLISHED over its legacy prefix, not left stale"
# A create that predates the markers wrote the managed content first (## Summary
# through the ## Refinery handoff bullets) with no markers. That IS the stale-body
# case adoption exists to close, so the refresh wraps a fresh region over that
# prefix and keeps what follows it — here an operator note — rather than flipping
# the stale summary through untouched.
store "[$(pre RF3 polecat/rf3 ',"pr_summary":"NEW: the republished summary after the rework."')]"
STALE3=$(printf '%s\n' \
  '## Summary' '' 'OLD: the summary a legacy body predates.' '' \
  '## Refinery handoff' '' '- Issue: RF3' '- Source branch: polecat/rf3' '- Target: main' '' \
  'Operator note: keep this legacy line.')
prrow 73 OPEN polecat/rf3 sha-rf3 main | jq --arg b "$STALE3" '. + {body:$b}' > "$GH_DIR/pr_view_73.json"
printf '[%s]' "$(prrow 73 OPEN polecat/rf3 sha-rf3 main)" > "$GH_DIR/pr_list_polecat_rf3.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF3 merge_result)" "pull_request" "the anchor flips after the region is established"
newbody=$(jq -r '.body' "$GH_DIR/pr_view_73.json")
has "$newbody" "NEW: the republished summary after the rework." "the current pr_summary reached the published body"
hasnt "$newbody" "OLD: the summary a legacy body predates." "…and the stale legacy summary is gone"
has "$newbody" "Operator note: keep this legacy line." "text after the legacy prefix is preserved"
has "$newbody" "<!-- gc:pr-summary -->" "the region is now marked, so a later pass splices in place"
has "$(cat "$STUB_GH_LOG")" "pr edit 73" "the body was edited in place, not re-created"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no twin PR"

echo "# a markerless body with no managed region is adopted as it stands, not rewritten"
# A hand-written body carries neither ## Summary nor the handoff block, so no MANAGED
# region has gone stale — only the operator's own text. Even with a differing
# pr_summary, adoption leaves it untouched and flips rather than clobber a body this
# arm never composed.
store "[$(pre RF3B polecat/rf3b ',"pr_summary":"NEW: a summary that must not overwrite a hand-written body."')]"
STALE3B=$(printf '%s\n' 'A free-form operator body.' '' 'No headings this arm can anchor on.')
prrow 78 OPEN polecat/rf3b sha-rf3b main | jq --arg b "$STALE3B" '. + {body:$b}' > "$GH_DIR/pr_view_78.json"
printf '[%s]' "$(prrow 78 OPEN polecat/rf3b sha-rf3b main)" > "$GH_DIR/pr_list_polecat_rf3b.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF3B merge_result)" "pull_request" "a body with no managed region still flips"
has "$out" "no managed gc:pr-summary region to refresh" "…and reports it was adopted as it stands"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 78" "the hand-written body is not rewritten"
has "$(jq -r '.body' "$GH_DIR/pr_view_78.json")" "A free-form operator body." "the operator's text is left intact"

echo "# a malformed marker shape is adopted as it stands, not rewritten"
# A lone open marker is neither a well-formed pair to splice nor a legacy prefix to
# establish — a shape the arm cannot reason about. It owns no region this refresh
# composed, so adoption leaves the broken markers untouched and flips.
store "[$(pre RF3C polecat/rf3c ',"pr_summary":"NEW: a summary a broken marker shape must not trigger a rewrite."')]"
STALE3C=$(printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'A body with a lone open marker.')
prrow 82 OPEN polecat/rf3c sha-rf3c main | jq --arg b "$STALE3C" '. + {body:$b}' > "$GH_DIR/pr_view_82.json"
printf '[%s]' "$(prrow 82 OPEN polecat/rf3c sha-rf3c main)" > "$GH_DIR/pr_list_polecat_rf3c.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF3C merge_result)" "pull_request" "a malformed marker shape still flips"
has "$out" "no managed gc:pr-summary region to refresh" "…and reports it was adopted as it stands"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 82" "the malformed markers are left untouched"

echo "# a legacy body with NOTHING after the handoff is established cleanly (the common freshly-created shape)"
# Every PR opened before this branch added the markers carries exactly this: the
# managed content and nothing else. The region is established over the whole body.
store "[$(pre RF3D polecat/rf3d ',"pr_summary":"NEW: the freshly-established summary."')]"
STALE3D=$(printf '%s\n' \
  '## Summary' '' 'OLD: a legacy body with nothing after the handoff.' '' \
  '## Refinery handoff' '' '- Issue: RF3D' '- Source branch: polecat/rf3d' '- Target: main')
prrow 84 OPEN polecat/rf3d sha-rf3d main | jq --arg b "$STALE3D" '. + {body:$b}' > "$GH_DIR/pr_view_84.json"
printf '[%s]' "$(prrow 84 OPEN polecat/rf3d sha-rf3d main)" > "$GH_DIR/pr_list_polecat_rf3d.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF3D merge_result)" "pull_request" "the anchor flips after the region is established"
newbody3d=$(jq -r '.body' "$GH_DIR/pr_view_84.json")
has "$newbody3d" "NEW: the freshly-established summary." "the current pr_summary reached the published body"
hasnt "$newbody3d" "OLD: a legacy body with nothing after the handoff." "…and the stale legacy summary is gone"
has "$newbody3d" "<!-- gc:pr-summary -->" "the region is now marked, so a later pass splices in place"
has "$(cat "$STUB_GH_LOG")" "pr edit 84" "the body was edited in place"

echo "# an unreadable OPEN PR body holds the anchor rather than flipping a stale one"
# The reworked pr_summary must reach the published body before the flip. A body
# that cannot even be read leaves the current one possibly stale, so flipping
# would pass it through the very gate the refresh exists to close; the anchor
# holds for the next pass instead.
store "[$(pre RF4 polecat/rf4 ',"pr_summary":"NEW: a summary that must not flip past a stale body."')]"
printf '[%s]' "$(prrow 74 OPEN polecat/rf4 sha-rf4 main)" > "$GH_DIR/pr_list_polecat_rf4.json"
# no pr_view_74.json fixture, so `gh pr view` exits nonzero: the body is unreadable
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF4 merge_result)" "pre_open_gate" "an unreadable body leaves the anchor at pre_open_gate"
has "$out" "body unreadable" "…and says why"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 74" "no body was edited past an unreadable read"

echo "# an OPEN PR row with no head oid holds rather than flipping without a refresh"
# certify_row does not require headRefOid, so an OPEN row can arrive with none.
# Without a head the handoff section cannot be composed, so the anchor holds.
store "[$(pre RF5 polecat/rf5 ',"pr_summary":"NEW: a summary needing a head to compose."')]"
printf '[%s]' "$(prrow 75 OPEN polecat/rf5 '' main)" > "$GH_DIR/pr_list_polecat_rf5.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF5 merge_result)" "pre_open_gate" "a missing head oid leaves the anchor at pre_open_gate"
has "$out" "head oid unknown" "…and says why"

echo "# an unparseable OPEN PR body holds rather than flipping past a body it cannot splice"
store "[$(pre RF6 polecat/rf6 ',"pr_summary":"NEW: a summary the render never reaches."')]"
printf '[%s]' "$(prrow 76 OPEN polecat/rf6 sha-rf6 main)" > "$GH_DIR/pr_list_polecat_rf6.json"
printf '%s' 'not-json{' > "$GH_DIR/pr_view_76.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta RF6 merge_result)" "pre_open_gate" "an unparseable body leaves the anchor at pre_open_gate"
has "$out" "did not parse" "…and says why"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 76" "no body was edited past a parse failure"

echo "# a scratch file that cannot be created holds rather than flipping unrefreshed"
store "[$(pre RF7 polecat/rf7 ',"pr_summary":"NEW: a summary the scratch failure never composes."')]"
STALE7=$(printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'OLD summary.' '<!-- /gc:pr-summary -->')
prrow 79 OPEN polecat/rf7 sha-rf7 main | jq --arg b "$STALE7" '. + {body:$b}' > "$GH_DIR/pr_view_79.json"
printf '[%s]' "$(prrow 79 OPEN polecat/rf7 sha-rf7 main)" > "$GH_DIR/pr_list_polecat_rf7.json"
: > "$STUB_GH_LOG"
out=$(TMPDIR=/nonexistent/scratch-fail "$SUT" 2>&1)
eq "$(meta RF7 merge_result)" "pre_open_gate" "a scratch-file failure leaves the anchor at pre_open_gate"
has "$out" "scratch file unavailable" "…and says why"
hasnt "$(cat "$STUB_GH_LOG")" "pr edit 79" "no body was edited when scratch was unavailable"

echo "# holds gate the create path"
store "[$(pre B1 polecat/b1 ',"merge_hold":"true"')]"
echo "sha-b1" > "$GH_DIR/head_polecat_b1"
out=$("$SUT" 2>&1)
has "$out" "held (merge_hold" "merge_hold holds the create"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR published past the hold"

echo "# a declared gate short of green holds"
store "[$(pre B2 polecat/b2)]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "lane 'codex' does not derive green" "a lane short of green holds the open"
eq "$(meta B2 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
# The gate check is row-only (green is a state of the lane, not the head), so
# it is judged before the head fetch: a held anchor pays no network call.
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "an ungreen gate holds before the head is ever fetched"

# The whole of the 211: a green lane is green however far the branch has moved
# since the verdict, so the head the PR opens at is not the gate's business.
echo "# a green lane publishes at a head no verdict ever named"
store "[$(pre B2b polecat/b2b), $(rev B2b)]"
echo "sha-b2b-moved-on" > "$GH_DIR/head_polecat_b2b"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/62"
printf '%s' "$(prrow 62 OPEN polecat/b2b sha-b2b-moved-on main)" > "$GH_DIR/pr_view_62.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta B2b merge_result)" "pull_request" "the anchor publishes"
has "$(cat "$STUB_GH_LOG")" "pr create" "…and the PR is opened"

# The gate is the anchor's whole declared set: a set naming a second reviewer
# publishes only once that reviewer has answered, and a set naming no
# marker-bearing gate publishes rather than waiting on a marker no arm writes.
echo "# a second declared gate with no marker holds the publish"
store "[$(pre B3 polecat/b3 '' 'codex,triage'), $(rev B3)]"
echo "sha-b3" > "$GH_DIR/head_polecat_b3"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "lane 'triage' does not derive green" "the unbacked second lane holds"
eq "$(meta B3 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR is published past an unanswered gate"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "…and the head was never fetched to decide it"

echo "# an empty check_set is never the gateless opt-out"
store "[$(pre B4 polecat/b4 '' '')]"
echo "sha-b4" > "$GH_DIR/head_polecat_b4"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an unnormalized anchor is held, not published"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and nothing is opened under it"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "an unnormalized check_set holds before the head is ever fetched"

echo "# check_set=none publishes: gateless BY CHOICE is not a missing marker"
store "[$(pre B5 polecat/b5 '' 'none')]"
echo "sha-b5" > "$GH_DIR/head_polecat_b5"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/61"
printf '%s' "$(prrow 61 OPEN polecat/b5 sha-b5 main)" > "$GH_DIR/pr_view_61.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#61" "the none sentinel opens instead of stranding at pre_open_gate"
eq "$(meta B5 merge_result)" "pull_request" "anchor flipped"

echo "# check_set=approval publishes: approval carries no marker and needs the PR"
store "[$(pre B6 polecat/b6 '' 'approval')]"
echo "sha-b6" > "$GH_DIR/head_polecat_b6"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/62"
printf '%s' "$(prrow 62 OPEN polecat/b6 sha-b6 main)" > "$GH_DIR/pr_view_62.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#62" "an approval-only set opens; merge.sh holds for the human review"
eq "$(meta B6 merge_result)" "pull_request" "anchor flipped"

echo "# create the PR at the reviewed head"
store "[$(pre C1 polecat/c1),
        {\"id\":\"rev-c1\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"VERDICT: APPROVE ok\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"C1\",\"check_name\":\"codex\",\"reviewed_oid\":\"sha-c1\",\"signoff_verdict\":\"approve\"}}]"
echo "sha-c1" > "$GH_DIR/head_polecat_c1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/77"
printf '%s' "$(prrow 77 OPEN polecat/c1 sha-c1 main)" > "$GH_DIR/pr_view_77.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "create pass exits 0"
has "$out" "opened PR#77" "the PR was opened and reported"
eq "$(meta C1 merge_result)" "pull_request" "anchor flipped to pull_request"
eq "$(meta C1 pr_number)" "77" "pr_number recorded"
ghlog=$(cat "$STUB_GH_LOG")
has "$ghlog" "pr create --repo github.com/zook/gc-toolkit --base main --head polecat/c1" "create pinned to origin, base and head"
hasnt "$ghlog" "--draft" "the PR is non-draft"
has "$ghlog" "pr view 77 --repo github.com/zook/gc-toolkit" "read back BY NUMBER, pinned"
has "$ghlog" "pr comment 77" "the verdict was replayed as a comment"
hasnt "$ghlog" "pr review" "never an approval"

echo "# the body summarizes the diff, and demotes the dispatch text"
# A reviewer who was not in the originating conversation opens this body. The
# anchor's description is dispatch text — what the work was asked to do — so
# the polecat's pr_summary is the ## Summary and the description survives one
# level down.
store "[$(pre E1 polecat/e1 ',"pr_summary":"Compares heads instead of branch names, so a moved head is refused."'), $(rev E1)]"
echo "sha-e1" > "$GH_DIR/head_polecat_e1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/81"
printf '%s' "$(prrow 81 OPEN polecat/e1 sha-e1 main)" > "$GH_DIR/pr_view_81.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#81" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"Compares heads instead of branch names, so a moved head is refused." \
    "pr_summary is the summary a reviewer reads first"
has "$body" "<summary>Dispatch — what this work was asked to do</summary>" "the dispatch text is demoted, not dropped"
has "$body" "d E1" "…and it is still in the body"
has "$body" "## Refinery handoff" "the handoff block is unchanged"
has "$body" "<!-- gc:pr-summary -->" "the composed body is wrapped in a managed-region marker"
has "$body" "<!-- /gc:pr-summary -->" "…closed by its end marker, so an adoption can re-splice it"

echo "# a pr_summary that repeats the ## Summary heading is not published under two"
# Some polecats open their pr_summary with a Summary heading of their own; the
# region writes one already, so the stored one is stripped rather than doubled.
store "[$(pre E4 polecat/e4 ',"pr_summary":"## Summary\n\nDe-duplicates the heading the region writes."'), $(rev E4)]"
echo "sha-e4" > "$GH_DIR/head_polecat_e4"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/84"
printf '%s' "$(prrow 84 OPEN polecat/e4 sha-e4 main)" > "$GH_DIR/pr_view_84.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#84" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"De-duplicates the heading the region writes." "the stored heading is stripped; the region's own remains"
hasnt "$body" "## Summary"$'\n'$'\n'"## Summary" "no doubled Summary heading"

echo "# no carried summary keeps today's body"
# The current text is a poor summary, not an empty one: an anchor whose handoff
# carried nothing must still open with a body.
store "[$(pre E2 polecat/e2), $(rev E2)]"
echo "sha-e2" > "$GH_DIR/head_polecat_e2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/82"
printf '%s' "$(prrow 82 OPEN polecat/e2 sha-e2 main)" > "$GH_DIR/pr_view_82.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#82" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E2" "the description is the summary when nothing was carried"
hasnt "$body" "<details>" "no empty demotion section when there is nothing to demote"

echo "# a whitespace-only summary is the absent case"
store "[$(pre E3 polecat/e3 ',"pr_summary":"   \n  "'), $(rev E3)]"
echo "sha-e3" > "$GH_DIR/head_polecat_e3"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/83"
printf '%s' "$(prrow 83 OPEN polecat/e3 sha-e3 main)" > "$GH_DIR/pr_view_83.json"
out=$("$SUT" 2>&1)
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E3" "blank prose falls back rather than publishing an empty summary"
hasnt "$body" "<details>" "…and demotes nothing"

echo "# a head that moved between gate and create refuses the stamp"
store "[$(pre C2 polecat/c2), $(rev C2)]"
echo "sha-c2" > "$GH_DIR/head_polecat_c2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/78"
printf '%s' "$(prrow 78 OPEN polecat/c2 sha-c2-moved main)" > "$GH_DIR/pr_view_78.json"
out=$("$SUT" 2>&1)
has "$out" "not the reviewed 'sha-c2'" "the moved head is refused"
eq "$(meta C2 merge_result)" "pre_open_gate" "nothing stamped; the anchor re-adopts next pass"

echo "# closed-unmerged headstone: supersede at a NEW head"
store "[$(pre D1 polecat/d1), $(rev D1)]"
printf '[%s]' "$(prrow 50 CLOSED polecat/d1 sha-d1-old main)" > "$GH_DIR/pr_list_polecat_d1.json"
echo "sha-d1-new" > "$GH_DIR/head_polecat_d1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/51"
printf '%s' "$(prrow 51 OPEN polecat/d1 sha-d1-new main)" > "$GH_DIR/pr_view_51.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "superseding closed PR#50" "the fresh PR names the headstone"
eq "$(meta D1 pr_number)" "51" "the fresh PR is the recorded identity"
has "$(cat "$STUB_GH_LOG")" "pr comment 50" "the superseded PR got the pointer comment"

echo "# closed-unmerged at the SAME head is a human decision"
store "[$(pre D2 polecat/d2), $(rev D2)]"
printf '[%s]' "$(prrow 52 CLOSED polecat/d2 sha-d2 main)" > "$GH_DIR/pr_list_polecat_d2.json"
echo "sha-d2" > "$GH_DIR/head_polecat_d2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "not reopening a human's decision" "same-head close is respected"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no replacement PR is opened"

echo "# unreadable enumeration fails loudly"
out=$(STUB_LIST_FAIL=1 "$SUT" 2>&1); rc=$?
eq "$rc" 1 "an unreadable enumeration exits non-zero"
has "$out" "false all-clear" "…and says why"

echo "# an open must-fix finding holds the pre-open publish"
# The same finding graph merge.sh's blocker probe holds on, read here through
# the shared helper: no PR is published over work the city has ruled must change.
store "[$(pre MF1 polecat/mf1), $(rev MF1), $(finding fnd-mf1 MF1)]"
echo "sha-mf1" > "$GH_DIR/head_polecat_mf1"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "has an open must-fix finding (fnd-mf1)" "an unfixed must-fix finding holds the publish"
eq "$(meta MF1 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR published over an open must-fix"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "the must-fix read is row-local, judged before the head fetch"

echo "# closing the must-fix finding lets the publish proceed"
store "[$(pre MF2 polecat/mf2), $(rev MF2), $(printf '%s' "$(finding fnd-mf2 MF2)" | jq -c '.status = "closed"')]"
echo "sha-mf2" > "$GH_DIR/head_polecat_mf2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/95"
printf '%s' "$(prrow 95 OPEN polecat/mf2 sha-mf2 main)" > "$GH_DIR/pr_view_95.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "opened PR#95" "a closed must-fix finding no longer holds the publish"
eq "$(meta MF2 merge_result)" "pull_request" "…and the anchor publishes"

echo "# the opened title carries a conventional-commit type from the bead kind"
# A conventional-commit PR-title check requires a leading type token. The type
# is derived from the bead's issue_type, unless the title already opens with a
# recognized one — then it is kept, never double-prefixed. The bead id suffix
# survives in every case.
tanchor() { # id issue_type title  — a green pre_open_gate anchor + its head
  # The anchor plus the closed approve bead that greens its codex lane, emitted
  # as two array elements (the store composes them with commas).
  echo "sha-$1" > "$GH_DIR/head_polecat_$1"
  printf '{"id":"%s","status":"open","issue_type":"%s","title":"%s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"polecat/%s","merged_target":"main","check_set":"codex"}}, ' \
    "$1" "$2" "$3" "$1" "$1"
  rev "$1"
}
store "[$(tanchor ttbug  bug     'Reject a moved head'),
        $(tanchor tttask task    'Reshape the reconcile loop'),
        $(tanchor ttdoc  docs    'Document the merge cadence'),
        $(tanchor ttfeat feature 'Support integration branches'),
        $(tanchor ttpfx  task    'fix(pr-open): keep the bead id in the title'),
        $(tanchor ttbare ''      'Tidy the enumerate step')]"
# STUB_PR_CREATE_URL empty: create logs its args (the --title among them) and
# returns nothing, so the pass stops before the readback. The title is read
# from the logged create, where gh's arg log space-joins argv — so a title is
# the run between --title and the --body-file that always follows it.
export STUB_PR_CREATE_URL=""
: > "$STUB_GH_LOG"
"$SUT" >/dev/null 2>&1
tlog=$(cat "$STUB_GH_LOG")
has "$tlog" "--title fix: Reject a moved head (ttbug) --body-file"            "bug maps to fix"
has "$tlog" "--title chore: Reshape the reconcile loop (tttask) --body-file"  "task maps to chore"
has "$tlog" "--title docs: Document the merge cadence (ttdoc) --body-file"    "docs maps to docs"
has "$tlog" "--title feat: Support integration branches (ttfeat) --body-file" "feature maps to feat"
has "$tlog" "--title fix(pr-open): keep the bead id in the title (ttpfx) --body-file" \
    "an existing conventional prefix is kept, not double-prefixed"
hasnt "$tlog" "chore: fix(pr-open):" "…and no derived type is prepended to it"
has "$tlog" "--title chore: Tidy the enumerate step (ttbare) --body-file" \
    "a bead with no issue_type falls back to chore"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
