#!/usr/bin/env bash
# Hermetic test for assets/scripts/pr-open.sh — pre_open_gate -> pull_request.
# Covers: adopting an existing OPEN or MERGED PR (flip only, one lifecycle
# transition, never a twin); refusing fork/foreign/uncertifiable rows; the
# closed-unmerged headstone (fresh PR + supersede note; same-head close is a
# human decision left alone); holds gating the create path; the check_set
# green@live-head gate over every gate the anchor declares; the moved-head
# refusal on the created PR; and the comment-not-approval verdict replay.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pr-open.sh" "$HERE/lifecycle.sh"
SUT="$SD/pr-open.sh"

# escalate.sh resolves as a sibling of the SUT, so a recorder in the SUT dir is
# what the guard reaches — the real one proves its own routing in escalate.test.sh,
# and here the assertion is on the situation key pr-open hands it.
export STUB_ESCALATE_LOG="$TMP/escalate.log"
: > "$STUB_ESCALATE_LOG"
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_ESCALATE_LOG:?}"
ESC
chmod +x "$SD/escalate.sh"

pre() { # id branch extra-json [check_set]  (4th arg empty = no check_set key)
  local cs="${4-codex}"
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"t %s","description":"d %s","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s%s}}' \
    "$1" "$1" "$1" "$2" "${cs:+,\"check_set\":\"$cs\"}" "${3:-}"
}
prrow() { # num state branch head base [mergedAt] [headrepo]
  printf '{"number":%s,"url":"https://github.com/zook/gc-toolkit/pull/%s","state":"%s","mergedAt":%s,"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","headRepository":{"name":"%s"},"headRepositoryOwner":{"login":"%s"},"isCrossRepository":false}' \
    "$1" "$1" "$2" "${6:-null}" "$5" "$3" "$4" "${7:-gc-toolkit}" "${8:-zook}"
}

echo "# adopt an existing OPEN PR"
store "[$(pre A1 polecat/a1)]"
printf '[%s]' "$(prrow 41 OPEN polecat/a1 sha-a1 main)" > "$GH_DIR/pr_list_polecat_a1.json"
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

echo "# holds gate the create path"
store "[$(pre B1 polecat/b1 ',"merge_hold":"true","check.codex":"green@sha-b1"')]"
echo "sha-b1" > "$GH_DIR/head_polecat_b1"
out=$("$SUT" 2>&1)
has "$out" "held (merge_hold" "merge_hold holds the create"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR published past the hold"

echo "# a declared gate not green at the live head holds"
store "[$(pre B2 polecat/b2 ',"check.codex":"green@stale-oid"')]"
echo "sha-b2" > "$GH_DIR/head_polecat_b2"
out=$("$SUT" 2>&1)
has "$out" "check 'codex' not green at live head" "a stale marker holds the open"
eq "$(meta B2 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"

# The gate is the anchor's whole declared set: a set naming a second reviewer
# publishes only once that reviewer has answered, and a set naming no
# marker-bearing gate publishes rather than waiting on a marker no arm writes.
echo "# a second declared gate with no marker holds the publish"
store "[$(pre B3 polecat/b3 ',"check.codex":"green@sha-b3"' 'codex,triage')]"
echo "sha-b3" > "$GH_DIR/head_polecat_b3"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "check 'triage' not green at live head (have 'none'" "the unmarked second gate holds"
eq "$(meta B3 merge_result)" "pre_open_gate" "anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR is published past an unanswered gate"

echo "# an empty check_set is never the gateless opt-out"
store "[$(pre B4 polecat/b4 '' '')]"
echo "sha-b4" > "$GH_DIR/head_polecat_b4"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an unnormalized anchor is held, not published"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and nothing is opened under it"

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
store "[$(pre C1 polecat/c1 ',"check.codex":"green@sha-c1"'),
        {\"id\":\"rev-c1\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"VERDICT: COMMENT ok\",\"metadata\":{\"task_kind\":\"review\",\"anchor_bead\":\"C1\"}}]"
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
store "[$(pre E1 polecat/e1 ',"check.codex":"green@sha-e1","pr_summary":"Compares heads instead of branch names, so a moved head is refused."')]"
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

echo "# no carried summary keeps today's body"
# The current text is a poor summary, not an empty one: an anchor whose handoff
# carried nothing must still open with a body.
store "[$(pre E2 polecat/e2 ',"check.codex":"green@sha-e2"')]"
echo "sha-e2" > "$GH_DIR/head_polecat_e2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/82"
printf '%s' "$(prrow 82 OPEN polecat/e2 sha-e2 main)" > "$GH_DIR/pr_view_82.json"
out=$("$SUT" 2>&1)
has "$out" "opened PR#82" "the PR was opened"
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E2" "the description is the summary when nothing was carried"
hasnt "$body" "<details>" "no empty demotion section when there is nothing to demote"

echo "# a whitespace-only summary is the absent case"
store "[$(pre E3 polecat/e3 ',"check.codex":"green@sha-e3","pr_summary":"   \n  "')]"
echo "sha-e3" > "$GH_DIR/head_polecat_e3"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/83"
printf '%s' "$(prrow 83 OPEN polecat/e3 sha-e3 main)" > "$GH_DIR/pr_view_83.json"
out=$("$SUT" 2>&1)
body=$(cat "$GH_DIR/pr_create_body.txt")
has "$body" "## Summary"$'\n'$'\n'"d E3" "blank prose falls back rather than publishing an empty summary"
hasnt "$body" "<details>" "…and demotes nothing"

echo "# a head that moved between gate and create refuses the stamp"
store "[$(pre C2 polecat/c2 ',"check.codex":"green@sha-c2"')]"
echo "sha-c2" > "$GH_DIR/head_polecat_c2"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/78"
printf '%s' "$(prrow 78 OPEN polecat/c2 sha-c2-moved main)" > "$GH_DIR/pr_view_78.json"
out=$("$SUT" 2>&1)
has "$out" "not the reviewed 'sha-c2'" "the moved head is refused"
eq "$(meta C2 merge_result)" "pre_open_gate" "nothing stamped; the anchor re-adopts next pass"

echo "# closed-unmerged headstone: supersede at a NEW head"
store "[$(pre D1 polecat/d1 ',"check.codex":"green@sha-d1-new"')]"
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
store "[$(pre D2 polecat/d2 ',"check.codex":"green@sha-d2"')]"
printf '[%s]' "$(prrow 52 CLOSED polecat/d2 sha-d2 main)" > "$GH_DIR/pr_list_polecat_d2.json"
echo "sha-d2" > "$GH_DIR/head_polecat_d2"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "not reopening a human's decision" "same-head close is respected"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no replacement PR is opened"

# --- the shared-input-artifact guard -------------------------------------------
# A bead-local planning document must not land on the default branch by itself.
# Each case below is one of the three conditions, because each one exempts a
# population that has to keep publishing.

cmpfx() { # <base> <head> <changed-path>...
  local base="$1" head="$2" names="" p
  shift 2
  for p in "$@"; do names="$names${names:+,}$(printf '{"filename":"%s"}' "$p")"; done
  printf '{"files":[%s]}' "$names" \
    > "$GH_DIR/compare_$(printf '%s' "$base...$head" | tr '/' '_').json"
}
guard_ready() { # <id> <branch> <pr-number> — head fixture + create/read-back pair
  echo "sha-$1" > "$GH_DIR/head_$(printf '%s' "$2" | tr '/' '_')"
  export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/$3"
  printf '%s' "$(prrow "$3" OPEN "$2" "sha-$1" main)" > "$GH_DIR/pr_view_$3.json"
  : > "$STUB_GH_LOG"; : > "$STUB_ESCALATE_LOG"; : > "$STUB_DEPS"
}

echo "# a spec-only diff onto the default branch with no convoy above it is refused"
store "[$(pre G1 polecat/g1 ',"check.codex":"green@sha-G1"')]"
guard_ready G1 polecat/g1 90
cmpfx main polecat/g1 specs/G1/carve.md
out=$("$SUT" 2>&1)
has "$out" "is a planning artifact aimed at 'main'" "the anti-pattern is named"
has "$out" "no convoy stands above the anchor" "…and both conditions are stated"
has "$out" "seed the artifact on an owned convoy's integration branch" "the remedy is in the refusal"
has "$out" "--set-metadata planning_artifact_ok=true" "…and so is the deliberate override"
eq "$(meta G1 merge_result)" "pre_open_gate" "the anchor stays pre_open_gate"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "no PR was opened"
has "$(cat "$STUB_ESCALATE_LOG")" "--key planning-artifact-to-default-branch" \
    "one deduped visit carries it to a person"

echo "# a doc riding with code is a normal PR"
store "[$(pre G2 polecat/g2 ',"check.codex":"green@sha-G2"')]"
guard_ready G2 polecat/g2 91
cmpfx main polecat/g2 specs/G2/notes.md assets/scripts/thing.sh
out=$("$SUT" 2>&1)
has "$out" "opened PR#91" "a mixed diff publishes"
hasnt "$out" "planning artifact" "…and the guard says nothing about it"
eq "$(meta G2 merge_result)" "pull_request" "anchor flipped"

echo "# a docs/ refresh is the central tier doing its job, not a planning artifact"
# The doc-keeper's whole output is single-file docs/*.md onto the default
# branch; docs/file-structure.md makes that tier authoritative-about-now, so it
# is not bead-local content and the guard must not touch it.
store "[$(pre G3 polecat/g3 ',"check.codex":"green@sha-G3"')]"
guard_ready G3 polecat/g3 92
cmpfx main polecat/g3 docs/gascity-reference.md
out=$("$SUT" 2>&1)
has "$out" "opened PR#92" "a docs-only PR publishes"
hasnt "$(cat "$STUB_ESCALATE_LOG")" "planning-artifact" "…and nothing is escalated"

echo "# a convoy above the anchor is the exemption the remedy produces"
store "[$(pre G4 polecat/g4 ',"check.codex":"green@sha-G4"'),
        {\"id\":\"cv-G4\",\"status\":\"open\",\"issue_type\":\"convoy\",\"metadata\":{}}]"
guard_ready G4 polecat/g4 93
cmpfx main polecat/g4 specs/G4/carve.md
printf 'G4|parent-child|cv-G4\n' >> "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "opened PR#93" "work under a convoy publishes"
eq "$(meta G4 merge_result)" "pull_request" "anchor flipped"

echo "# a convoy two levels up still exempts"
store "[$(pre G5 polecat/g5 ',"check.codex":"green@sha-G5"'),
        {\"id\":\"ep-G5\",\"status\":\"open\",\"issue_type\":\"epic\",\"metadata\":{}},
        {\"id\":\"cv-G5\",\"status\":\"open\",\"issue_type\":\"convoy\",\"metadata\":{}}]"
guard_ready G5 polecat/g5 94
cmpfx main polecat/g5 specs/G5/carve.md
printf 'G5|parent-child|ep-G5\nep-G5|parent-child|cv-G5\n' >> "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "opened PR#94" "the walk climbs past a non-convoy parent"

echo "# a non-convoy parent is not a convoy ancestor"
# The shape of the second cited violation: the bead had a parent, and the
# parent was a plain task, so no integration branch existed anywhere above it.
store "[$(pre G6 polecat/g6 ',"check.codex":"green@sha-G6"'),
        {\"id\":\"tk-G6\",\"status\":\"open\",\"issue_type\":\"task\",\"metadata\":{}}]"
guard_ready G6 polecat/g6 95
cmpfx main polecat/g6 specs/G6/state-model.md specs/G6/surface.md
printf 'G6|parent-child|tk-G6\n' >> "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "is a planning artifact" "a task parent does not exempt"
hasnt "$(cat "$STUB_GH_LOG")" "pr create" "…and no PR was opened"

echo "# a convoy graduation PR is spec-only onto the default branch BY DESIGN"
store "[$(pre G7 integration/cv-G7 ',"check.codex":"green@sha-G7","graduation":"true"')]"
guard_ready G7 integration/cv-G7 96
cmpfx main integration/cv-G7 specs/G7/carve.md
out=$("$SUT" 2>&1)
has "$out" "opened PR#96" "the graduation anchor publishes"
hasnt "$out" "planning artifact" "…and the guard never looks at it"

echo "# the waiver publishes, and files nothing"
store "[$(pre G8 polecat/g8 ',"check.codex":"green@sha-G8","planning_artifact_ok":"true"')]"
guard_ready G8 polecat/g8 97
cmpfx main polecat/g8 specs/G8/carve.md
out=$("$SUT" 2>&1)
has "$out" "opened PR#97" "an operator who meant it gets the PR"
hasnt "$(cat "$STUB_ESCALATE_LOG")" "planning-artifact" "…and no visit is filed against their decision"

echo "# a target that is not the default branch is never even compared"
store "[{\"id\":\"G9\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"title\":\"t G9\",\"description\":\"d G9\",\"metadata\":{\"merge_result\":\"pre_open_gate\",\"branch\":\"polecat/g9\",\"merged_target\":\"integration/cv-G9\",\"check_set\":\"codex\",\"check.codex\":\"green@sha-G9\"}}]"
echo "sha-G9" > "$GH_DIR/head_polecat_g9"
export STUB_PR_CREATE_URL="https://github.com/zook/gc-toolkit/pull/98"
printf '%s' "$(prrow 98 OPEN polecat/g9 sha-G9 integration/cv-G9)" > "$GH_DIR/pr_view_98.json"
: > "$STUB_GH_LOG"; : > "$STUB_ESCALATE_LOG"; : > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "opened PR#98" "an integration-branch PR publishes"
hasnt "$(cat "$STUB_GH_LOG")" "/compare/" "the compare read is skipped entirely"

echo "# an unreadable compare does not stall the queue"
# A guard that cannot read the diff has no evidence of the anti-pattern, and
# the compare is re-read every pass — so refusing here would strand a
# legitimate PR for as long as the endpoint stays unhappy.
store "[$(pre GA polecat/ga ',"check.codex":"green@sha-GA"')]"
guard_ready GA polecat/ga 99
out=$("$SUT" 2>&1)
has "$out" "planning-artifact guard did not evaluate" "the unevaluated guard says so"
has "$out" "opened PR#99" "…and the create proceeds"

echo "# an empty prefix list turns the guard off"
store "[$(pre GB polecat/gb ',"check.codex":"green@sha-GB"')]"
guard_ready GB polecat/gb 100
cmpfx main polecat/gb specs/GB/carve.md
out=$(PR_OPEN_PLANNING_PATHS="" "$SUT" 2>&1)
has "$out" "opened PR#100" "a rig that files its local tier elsewhere can opt out"
hasnt "$out" "planning artifact" "…and hears nothing from the guard"

echo "# unreadable enumeration fails loudly"
out=$(STUB_LIST_FAIL=1 "$SUT" 2>&1); rc=$?
eq "$rc" 1 "an unreadable enumeration exits non-zero"
has "$out" "false all-clear" "…and says why"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
