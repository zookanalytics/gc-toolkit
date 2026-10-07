#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-open.sh — pre_open_gate -> pull_request.
# Covers: adopting an existing OPEN or MERGED PR (one lifecycle transition, never
# a twin) and refreshing an OPEN PR's body from the anchor's current pr_summary
# before the flip (the marked region re-spliced, operator text and pr-stack's
# section kept, a failed edit holding the anchor, a pre-markers body having its
# region established over the legacy prefix, a body with no managed region,
# whether hand-written or a malformed marker shape, adopted as it stands rather
# than rewritten);
# refusing fork/foreign/uncertifiable rows; the closed-unmerged headstone (fresh
# PR + supersede note; same-head close is a human decision left alone); holds
# gating the create path; the all-lanes-green gate over every check the anchor
# declares, which no head move disturbs; the moved-head refusal on the created
# PR; the comment-not-approval verdict replay; and the de-duplicated ## Summary
# heading. The phase model: a draft create when an open-as-draft check gates the
# PR, the draft-to-ready arm (its prefilter, holds, must-fix, loud enumeration
# failure, and the draft_readied record a held ready PR still takes), adoption's
# opened_as_draft only for the refinery's own draft, one resolve per anchor, a
# failing or missing resolver holding the create, and heads read from one pass
# fetch.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pr-open-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# pr-open.sh flips the anchor to pull_request through lifecycle.sh, which execs
# gctk.
harness_build_gctk
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-open.sh" "$HERE/pr-summary-region.sh" "$HERE/lifecycle.sh" \
  "$HERE/lane-state.sh" "$HERE/finding.sh" "$HERE/review-checks.sh"
SUT="$SD/pr-open.sh"

pre() { # id branch extra-json [check_set]  (4th arg empty = no check_set key)
  local cs="${4-correctness}"
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s%s}}' \
    "$1" "$1" "$1" "$2" "${cs:+,\"check_set\":\"$cs\"}" "${3:-}"
}
prrow() { # num state branch head base [mergedAt] [headrepo]
  printf '{"number":%s,"url":"https://github.com/zook/gc-toolkit/pull/%s","state":"%s","mergedAt":%s,"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","headRepository":{"name":"%s"},"headRepositoryOwner":{"login":"%s"},"isCrossRepository":false}' \
    "$1" "$1" "$2" "${6:-null}" "$5" "$3" "$4" "${7:-gc-toolkit}" "${8:-zook}"
}

# A closed approve review bead backing <anchor>'s <lane> (default correctness) — the
# green record lane-state.sh derives, in place of the retired check.<lane>=green
# marker. reviewed_oid is what a local backing bead must carry to green a lane.
rev() { # anchor [lane] [oid]
  printf '{"id":"rev-%s","status":"closed","assignee":"","notes":"approve","metadata":{"task_kind":"review","anchor_bead":"%s","check_name":"%s","reviewed_oid":"%s","signoff_verdict":"approve"}}' \
    "$1" "$1" "${2:-correctness}" "${3:-sha-r}"
}
# An open must-fix finding on <anchor> — finding.sh open-must-fix reads it by
# disposition, so no blocks edge is needed here (merge.sh reads the edge).
finding() { # id anchor [disposition] [lane]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.disposition":"%s","finding.lane":"%s","finding.key":"%s:0"}}' \
    "$1" "$2" "${3:-must-fix}" "${4:-correctness}" "${4:-correctness}"
}
# An anchor like pre(), but targeting integration/<convoy> instead of main — the
# owned-convoy checkpoint tk-6bji7k.9 marks with a banner and a base: label.
pre_int() { # id branch convoy
  pre "$1" "$2" | jq -c --arg t "integration/$3" '.metadata.merged_target=$t'
}
# The labels on a PR view fixture, sorted and comma-joined.
pv_labels() { jq -r '[.labels[]?.name] | sort | join(",")' "$GH_DIR/pr_view_$1.json"; }

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

echo "# a declared check short of green holds"
store "[$(pre B2 polecat/b2)]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "lane 'correctness' does not derive green" "a lane short of green holds the open"
eq "$(meta B2 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
# The pre-open gate SET is resolved at the REVIEWED head — the same index the body
# render and gate-ensure dispatch read — so the head is fetched before the lanes
# are judged. The lane's green itself stays row-only (--no-remote): a commit
# landing on the branch does not move it.
has "$(cat "$STUB_GH_LOG")" "commits/" "the head is fetched to resolve the gate at the reviewed head"

# The whole of the 211: a green lane is green however far the branch has moved
# since the verdict, so the head the PR opens at is not the check's business.
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
# marker-bearing check publishes rather than waiting on a marker no arm writes.
echo "# a second declared check with no marker holds the publish"
store "[$(pre B3 polecat/b3 '' 'correctness,triage'), $(rev B3)]"
echo "sha-b3" > "$GH_DIR/head_polecat_b3"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "lane 'triage' does not derive green" "the unbacked second lane holds"
eq "$(meta B3 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR is published past an unanswered check"
has "$(cat "$STUB_GH_LOG")" "commits/" "…the head is fetched to resolve the gate at the reviewed head"

echo "# an empty check_set is never the checkless opt-out"
store "[$(pre B4 polecat/b4 '' '')]"
echo "sha-b4" > "$GH_DIR/head_polecat_b4"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an unnormalized anchor is held, not published"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and nothing is opened under it"
hasnt "$(cat "$STUB_GH_LOG")" "commits/" "an unnormalized check_set holds before the head is ever fetched"

echo "# check_set=none publishes: checkless BY CHOICE is not a missing marker"
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
        {\"id\":\"rev-c1\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"VERDICT: APPROVE ok\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"C1\",\"check_name\":\"correctness\",\"reviewed_oid\":\"sha-c1\",\"signoff_verdict\":\"approve\"}}]"
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
has "$ghlog" "<!-- gc:city -->" "the replayed verdict carries the city's provenance mark (posted through pr-post.sh)"
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
has "$(cat "$STUB_GH_LOG")" "$(printf 're-gated at `sha-d1-n`.\n\n<!-- gc:city -->')" "the pointer comment carries the city's provenance mark"

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
  # The anchor plus the closed approve bead that greens its correctness lane, emitted
  # as two array elements (the store composes them with commas).
  echo "sha-$1" > "$GH_DIR/head_polecat_$1"
  printf '{"id":"%s","status":"open","issue_type":"%s","title":"%s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"polecat/%s","merged_target":"main","check_set":"correctness"}}, ' \
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

# The label writer pr-open delegates to. It is absent from the SUT dir above, where
# the reconcile/mark-base calls are best-effort and silently no-op without it (no
# earlier case asserts a label). Installed now so the cases below exercise the real
# status: reconcile and the base: mark, and can read the labels back off the PR.
cp "$HERE/pr-status-label.sh" "$SD/pr-status-label.sh"

echo "# an integration-targeted PR opens with a checkpoint banner and the base: label (tk-6bji7k.9)"
# The base is integration/<convoy-id>, so the body leads with a standing banner
# naming the integration base and the mint-a-phase meaning, and the PR list carries
# the sibling base: integration label — both set here where the base is known.
store "[$(pre_int INT1 polecat/int1 tk-5kk1zh), $(rev INT1)]"
echo "sha-int1" > "$GH_DIR/head_polecat_int1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/91"
printf '%s' "$(prrow 91 OPEN polecat/int1 sha-int1 integration/tk-5kk1zh)" > "$GH_DIR/pr_view_91.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta INT1 merge_result)" "pull_request" "the integration checkpoint opens and flips"
ibody=$(cat "$GH_DIR/pr_create_body.txt")
has "$ibody" "[!IMPORTANT]" "the created body carries an alert banner"
has "$ibody" 'merges into `integration/tk-5kk1zh`, not `main`' "…naming the integration base, not main"
has "$ibody" "mints this phase" "…and states that approving it mints a phase"
has "$ibody" "runs at graduation" "…and that the broader review runs at graduation"
has "$(pv_labels 91)" "base: integration" "the base: integration label is stamped on the PR"

echo "# a main-targeted PR gets no banner and no base: label — the default is unmarked"
store "[$(pre M1 polecat/m1), $(rev M1)]"
echo "sha-m1" > "$GH_DIR/head_polecat_m1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/92"
printf '%s' "$(prrow 92 OPEN polecat/m1 sha-m1 main)" > "$GH_DIR/pr_view_92.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta M1 merge_result)" "pull_request" "the mainline PR opens"
hasnt "$(cat "$GH_DIR/pr_create_body.txt")" "[!IMPORTANT]" "no checkpoint banner on a main-targeted PR"
hasnt "$(pv_labels 92)" "base:" "no base: label on a main-targeted PR"

echo "# adopting an OPEN integration PR splices the banner in and stamps the base: label"
# The body carries the marked region with a stale summary; the refresh re-splices a
# freshly composed region, and for an integration target that region now leads with
# the banner. The adoption path also stamps the base: label, like the create path.
store "[$(pre_int INT2 polecat/int2 tk-5kk1zh)]"
STALEI=$(printf '%s\n' '<!-- gc:pr-summary -->' '## Summary' '' 'Old summary.' '' \
  '## Refinery handoff' '' '- Issue: INT2' '<!-- /gc:pr-summary -->')
prrow 93 OPEN polecat/int2 sha-int2 integration/tk-5kk1zh | jq --arg b "$STALEI" '. + {body:$b}' > "$GH_DIR/pr_view_93.json"
printf '[%s]' "$(prrow 93 OPEN polecat/int2 sha-int2 integration/tk-5kk1zh)" > "$GH_DIR/pr_list_polecat_int2.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
eq "$(meta INT2 merge_result)" "pull_request" "the integration PR is adopted and flips"
inewbody=$(jq -r '.body' "$GH_DIR/pr_view_93.json")
has "$inewbody" "[!IMPORTANT]" "the refreshed body carries the checkpoint banner"
has "$inewbody" 'integration/tk-5kk1zh' "…naming the integration base"
has "$(pv_labels 93)" "base: integration" "adoption also stamps the base: label"

echo "# the phase model: an open-as-draft check opens the PR as a draft, and a later arm surfaces it"
# A controlled index so the test does not depend on the live pack's review-checks.toml:
# correctness reads the diff (pre-open), demo needs the preview (open-as-draft).
DR_IDX="$TMP/draft-index.toml"
printf '[checks.correctness]\nmethod="m"\npurpose="p"\nphase="pre-open"\n[checks.triage]\nmethod="m"\npurpose="p"\nphase="pre-open"\n[checks.demo]\nmethod="m"\npurpose="p"\nphase="open-as-draft"\n' > "$DR_IDX"
pr_anchor() { # id branch num check_set [opened_as_draft] [draft_readied]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t","metadata":{"merge_result":"pull_request","branch":"%s","merged_target":"main","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","check_set":"%s"%s%s}}' \
    "$1" "$2" "$3" "$3" "$4" \
    "${5:+,\"opened_as_draft\":\"$5\"}" \
    "${6:+,\"draft_readied\":\"$6\"}"
}
rev_lane() { # id anchor lane oid
  printf '{"id":"%s","status":"closed","assignee":"","notes":"approve","metadata":{"task_kind":"review","anchor_bead":"%s","check_name":"%s","reviewed_oid":"%s","signoff_verdict":"approve"}}' \
    "$1" "$2" "$3" "$4"
}

# create: the pre-open gate (correctness) is green and demo is open-as-draft, so
# the PR opens as a DRAFT and the anchor records opened_as_draft at the flip — the
# preview the demo needs can deploy, but it is not surfaced for review yet.
store "[$(pre DR1 polecat/dr1 '' 'correctness,demo'), $(rev DR1)]"
echo "sha-dr1" > "$GH_DIR/head_polecat_dr1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/70"
printf '%s' "$(prrow 70 OPEN polecat/dr1 sha-dr1 main)" > "$GH_DIR/pr_view_70.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "opened PR#70" "a demo-bearing anchor opens once its pre-open gate is green"
eq "$(meta DR1 merge_result)" "pull_request" "the anchor flips to pull_request"
has "$(cat "$STUB_GH_LOG")" "pr create --repo github.com/zook/gc-toolkit --base main --head polecat/dr1" "the create is pinned to origin"
has "$(cat "$STUB_GH_LOG")" "--draft" "it opens as a draft because demo is open-as-draft"
eq "$(meta DR1 opened_as_draft)" "sha-dr1" "the flip records opened_as_draft at the reviewed head"

# draft -> ready: a draft the refinery opened (opened_as_draft set), every
# open-as-draft gate green, is flipped out of draft AND records draft_readied.
store "[$(pr_anchor DR2 polecat/dr2 71 'correctness,demo' sha-dr2), $(rev_lane rev-DR2-c DR2 correctness sha-dr2), $(rev_lane rev-DR2-d DR2 demo sha-dr2)]"
printf '%s' "$(prrow 71 OPEN polecat/dr2 sha-dr2 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_71.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "flipped draft -> ready for review" "the draft is surfaced once its open-as-draft gates are green"
has "$(cat "$STUB_GH_LOG")" "pr ready 71" "gh pr ready flips it out of draft"
eq "$(meta DR2 draft_readied)" "sha-dr2" "the flip records draft_readied so the arm never re-reads it"

# draft -> ready HOLDS while an open-as-draft gate is not yet green.
store "[$(pr_anchor DR3 polecat/dr3 72 'correctness,demo' sha-dr3), $(rev_lane rev-DR3-c DR3 correctness sha-dr3)]"
printf '%s' "$(prrow 72 OPEN polecat/dr3 sha-dr3 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_72.json"
echo '[]' > "$GH_DIR/reviews_72.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 72" "a draft whose open-as-draft gate is still ungreen stays a draft"

# a check_set of only pre-open checks never opens a draft (the empty-phase collapse).
store "[$(pre DR4 polecat/dr4 '' 'correctness,triage'), $(rev DR4), $(rev_lane rev-DR4-t DR4 triage sha-dr4)]"
echo "sha-dr4" > "$GH_DIR/head_polecat_dr4"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/73"
printf '%s' "$(prrow 73 OPEN polecat/dr4 sha-dr4 main)" > "$GH_DIR/pr_view_73.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "opened PR#73" "an all-pre-open anchor opens"
hasnt "$(cat "$STUB_GH_LOG")" "--draft" "…and never as a draft — the empty-phase collapse"

echo "# the draft-to-ready arm's cheap metadata prefilter — no PR read, no resolver fork per pass"
# An anchor with no opened_as_draft opened ready; the arm must not even read its PR.
store "[$(pr_anchor DR5 polecat/dr5 74 'correctness,demo'), $(rev_lane rev-DR5-c DR5 correctness sha-dr5), $(rev_lane rev-DR5-d DR5 demo sha-dr5)]"
printf '%s' "$(prrow 74 OPEN polecat/dr5 sha-dr5 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_74.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr view 74" "an opened-ready anchor (no opened_as_draft) is skipped before any PR read"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 74" "…and never flipped"

# An already-readied anchor (draft_readied set) is skipped before any PR read —
# which is also what keeps the arm off a PR an operator re-drafted after readying.
store "[$(pr_anchor DR6 polecat/dr6 75 'correctness,demo' sha-dr6 sha-dr6), $(rev_lane rev-DR6-c DR6 correctness sha-dr6), $(rev_lane rev-DR6-d DR6 demo sha-dr6)]"
printf '%s' "$(prrow 75 OPEN polecat/dr6 sha-dr6 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_75.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
hasnt "$(cat "$STUB_GH_LOG")" "pr view 75" "a readied anchor (draft_readied set) is skipped — an operator's re-draft is never re-flipped"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 75" "…and never flipped"

echo "# the draft-to-ready arm respects operator holds, must-fix findings, and PR state"
# A held draft is the operator's: never surfaced, even with every gate green.
store "[$(pr_anchor DR7 polecat/dr7 76 'correctness,demo' sha-dr7 | jq -c '.metadata.merge_hold="true"'), $(rev_lane rev-DR7-c DR7 correctness sha-dr7), $(rev_lane rev-DR7-d DR7 demo sha-dr7)]"
printf '%s' "$(prrow 76 OPEN polecat/dr7 sha-dr7 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_76.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "held (merge_hold" "a held draft is not surfaced"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 76" "…gh pr ready is never called on a held draft"

# A draft with an open must-fix finding is not surfaced over work the city has
# ruled must change, even with every open-as-draft gate green.
store "[$(pr_anchor DR8 polecat/dr8 77 'correctness,demo' sha-dr8), $(rev_lane rev-DR8-c DR8 correctness sha-dr8), $(rev_lane rev-DR8-d DR8 demo sha-dr8), $(finding fnd-dr8 DR8 must-fix demo)]"
printf '%s' "$(prrow 77 OPEN polecat/dr8 sha-dr8 main)" | jq -c '. + {isDraft:true}' > "$GH_DIR/pr_view_77.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "open must-fix finding" "a draft with an open must-fix finding is not surfaced"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 77" "…gh pr ready is never called over an open must-fix"

# A PR already out of draft (surfaced externally, or adopted ready) records
# draft_readied so the arm stops reading it every pass, and is not re-flipped.
store "[$(pr_anchor DR9 polecat/dr9 78 'correctness,demo' sha-dr9), $(rev_lane rev-DR9-c DR9 correctness sha-dr9), $(rev_lane rev-DR9-d DR9 demo sha-dr9)]"
printf '%s' "$(prrow 78 OPEN polecat/dr9 sha-dr9 main)" > "$GH_DIR/pr_view_78.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta DR9 draft_readied)" "sha-dr9" "an already-ready draft records draft_readied"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 78" "…and is not re-flipped"

echo "# adoption stamps opened_as_draft only on a draft the refinery opened as one"
# The marker hands the ready flip to the draft-to-ready arm, so it goes only on a
# draft the city opened as a draft and nobody re-drafted since. An adopted READY PR,
# an operator's own draft, and a city PR someone converted back to draft are all
# adopted WITHOUT it, so the arm never surfaces a PR somebody parked.
adopt_row() { # num branch head isDraft author
  prrow "$1" OPEN "$2" "$3" main | jq -c --argjson d "$4" --arg a "$5" '. + {isDraft:$d, author:{login:$a}}'
}
adopt_fixture() { # id num isDraft author — anchor + PR list/view fixtures
  store "[$(pre "$1" "polecat/$1" '' 'correctness,demo')]"
  printf '[%s]' "$(adopt_row "$2" "polecat/$1" "sha-$1" "$3" "$4")" > "$GH_DIR/pr_list_polecat_$1.json"
  adopt_row "$2" "polecat/$1" "sha-$1" "$3" "$4" | jq '. + {body:"A hand-written body."}' > "$GH_DIR/pr_view_$2.json"
}
adopt_fixture ad1 81 false gc-city-bot
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta ad1 merge_result)" "pull_request" "an adopted READY PR whose check_set names demo flips"
eq "$(meta ad1 opened_as_draft)" "<absent>" "…without opened_as_draft: it is not a draft"
adopt_fixture ad2 82 true johnzook
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta ad2 merge_result)" "pull_request" "an operator's own draft is adopted"
eq "$(meta ad2 opened_as_draft)" "<absent>" "…without opened_as_draft, so the refinery never readies it"
has "$out" "did not open as one" "…and the pass says the flip is not the refinery's"
adopt_fixture ad3 83 true gc-city-bot
printf '[{"event":"ready_for_review"},{"event":"convert_to_draft"}]' > "$GH_DIR/timeline_83.json"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta ad3 merge_result)" "pull_request" "a city PR someone re-drafted is adopted"
eq "$(meta ad3 opened_as_draft)" "<absent>" "…without opened_as_draft: the conversion was someone parking it"
adopt_fixture ad4 84 true gc-city-bot
printf '[{"event":"labeled"},{"event":"commented"}]' > "$GH_DIR/timeline_84.json"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta ad4 opened_as_draft)" "sha-ad4" "the refinery's own never-re-drafted draft records opened_as_draft at its head"
adopt_fixture ad5 85 true gc-city-bot
out=$(STUB_TIMELINE_RC=1 GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta ad5 merge_result)" "pre_open_gate" "an unreadable draft owner holds the adoption at pre_open_gate"
has "$out" "draft ownership unreadable" "…and says why"

echo "# each anchor's gates are resolved once, and a resolver that fails holds the create"
# A counting shim stands in for review-checks.sh: it logs each call and runs the
# real resolver, or fails when RC_FAIL is set.
mv "$SD/review-checks.sh" "$SD/review-checks.real.sh"
cat > "$SD/review-checks.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${RC_CALL_LOG:?}"
[ -z "${RC_FAIL:-}" ] || exit 1
exec "$(dirname "$0")/review-checks.real.sh" "$@"
SH
chmod +x "$SD/review-checks.sh"
export RC_CALL_LOG="$TMP/rc-calls.log"
store "[$(pre ro1 polecat/ro1 '' 'correctness,demo'), $(rev ro1)]"
echo "sha-ro1" > "$GH_DIR/head_polecat_ro1"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/86"
printf '%s' "$(prrow 86 OPEN polecat/ro1 sha-ro1 main)" > "$GH_DIR/pr_view_86.json"
: > "$RC_CALL_LOG"; : > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "opened PR#86" "the anchor opens"
eq "$(grep -c -- '--resolve' "$RC_CALL_LOG")" "1" "its gates are resolved ONCE for the create gate, the draft decision and the body"
has "$(cat "$STUB_GH_LOG")" "--draft" "the draft decision reads that one answer"
has "$(cat "$GH_DIR/pr_create_body.txt")" 'Draft-stage gates `demo`' "…and so does the body"
store "[$(pre ro2 polecat/ro2 '' 'correctness,demo'), $(rev ro2)]"
echo "sha-ro2" > "$GH_DIR/head_polecat_ro2"
: > "$STUB_GH_LOG"
out=$(RC_FAIL=1 GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "gate set unreadable" "a failed resolve is reported"
eq "$(meta ro2 merge_result)" "pre_open_gate" "…the anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and no PR opens, ready or draft"
rm -f "$SD/review-checks.sh"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" "1" "a missing resolver fails the arm"
has "$out" "check resolver is missing" "…and says so"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…before anything is opened"
mv "$SD/review-checks.real.sh" "$SD/review-checks.sh"

echo "# heads come from one pass fetch; an anchor held on a red lane pays no API read"
store "[$(pre hf1 polecat/hf1 '' 'correctness')]"
echo "sha-hf1" > "$GH_DIR/head_polecat_hf1"
: > "$STUB_GH_LOG"
out=$(STUB_FETCHED_HEAD=sha-hf1 GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "lane 'correctness' does not derive green; held" "an ungreen anchor is held"
hasnt "$(cat "$STUB_GH_LOG")" "commits/polecat/hf1" "…on the head the pass fetch answered, with no API read of it"
store "[$(pre hf2 polecat/hf2 '' 'correctness'), $(rev hf2)]"
echo "sha-hf2" > "$GH_DIR/head_polecat_hf2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/87"
printf '%s' "$(prrow 87 OPEN polecat/hf2 sha-hf2 main)" > "$GH_DIR/pr_view_87.json"
: > "$STUB_GH_LOG"
out=$(STUB_FETCHED_HEAD=sha-hf2 GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "opened PR#87" "a green anchor opens at the fetched head"
eq "$(grep -c 'commits/polecat/hf2' "$STUB_GH_LOG")" "1" "…confirmed by one API read just before the create"
store "[$(pre hf3 polecat/hf3 '' 'correctness'), $(rev hf3)]"
echo "sha-hf3-new" > "$GH_DIR/head_polecat_hf3"
: > "$STUB_GH_LOG"
out=$(STUB_FETCHED_HEAD=sha-hf3-old GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
has "$out" "moved since the pass fetch" "a branch that moved after the fetch is caught"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…no PR opens at the stale head"
eq "$(meta hf3 merge_result)" "pre_open_gate" "…and the anchor re-gates next pass"

echo "# the draft-to-ready arm fails loudly when the store will not enumerate"
store "[$(pr_anchor re1 polecat/re1 88 'correctness,demo' sha-re1)]"
out=$(STUB_LIST_FAIL_ON="merge_result=pull_request" GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1); rc=$?
eq "$rc" "1" "an unreadable pull_request enumeration fails the arm"
has "$out" "could not enumerate pull_request anchors" "…naming what it could not read"
has "$out" "0 readied" "…after still reporting the pass summary"

echo "# a PR GitHub reads ready records draft_readied even while held"
# Holds stop the flip, not the record: a held anchor whose PR is already ready
# (readied by hand, then held) records draft_readied, so gate-ensure dispatches its
# ready-for-review and merge phases instead of pinning it at the draft stage.
store "[$(pr_anchor dh1 polecat/dh1 89 'correctness,demo' sha-dh1 | jq -c '.metadata.rebase_hold="true"')]"
printf '%s' "$(prrow 89 OPEN polecat/dh1 sha-dh1 main)" > "$GH_DIR/pr_view_89.json"
: > "$STUB_GH_LOG"
out=$(GC_REVIEW_CHECKS_INDEX="$DR_IDX" "$SUT" 2>&1)
eq "$(meta dh1 draft_readied)" "sha-dh1" "a held anchor whose PR reads ready records draft_readied"
hasnt "$(cat "$STUB_GH_LOG")" "pr ready 89" "…and nothing is flipped"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
