#!/usr/bin/env bash
# Hermetic test for assets/scripts/merge.sh — the single writer of merged truth.
# Covers: the happy path (pinned read, --squash --match-head-commit, ONE
# lifecycle transition closing with merged_sha); every validate hold in order
# (merge_hold, duplicate anchor + escalate, retarget, non-green check, unclosed
# child via metadata AND dep edge, tracking_only opt-out, the universal approval
# rule + veto, CLEAN/UNSTABLE handling, BLOCKED naming its cause from
# reviewThreads + reviewDecision, an UNKNOWN merge state read again within one
# budget per pass so one pass lands every approved clean PR); the check
# resolver, whose crash holds the merge and whose absence holds the pass; a
# broken lane or finalize helper, which holds only its own anchor; the recorded
# pr_posture hold, read off the anchor; identity refusals (fork, url/branch
# mismatch); the record for a PR already merged and the live anchor identity
# both it and the merge stand on;
# the terminal full-authorization re-read; the loud non-zero exit when the
# record half fails after a merge; the cap that turns a record failing every
# pass into one visit a person can claim; and the reads that fail closed when
# they stop partway (a cut-short reviews or threads stream, a list or dep probe
# that exited non-zero after printing an array or printed unreadable bytes
# after it).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")"
# merge.sh names its own directory through cd and pwd, which drop the doubled
# slash that a TMPDIR ending in / leaves in mktemp's path. Assertions compare
# that name with paths built on TMP, so TMP is resolved before any is built.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
# merge.sh's shell records every landing through lifecycle.sh, which execs
# gctk, and the same build is the gctk arm's binary.
harness_build_gctk
harness_init

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/merge.sh" "$HERE/lifecycle.sh" "$HERE/record-failure-cap.sh" \
  "$HERE/lane-state.sh" "$HERE/finding.sh" "$HERE/finalize-gate.sh" "$HERE/review-checks.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "${STUB_ESC_LOG:?}"\n' > "$SD/escalate.sh"
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
SUT="$SD/merge.sh"

# check_set declares the lane; the anchor carries no check.<lane> marker — a
# lane's green is DERIVED from a backing review bead, not stored on the anchor.
anchor() { # id num extra-json
  printf '{"id":"%s","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"%s","pr_url":"https://github.com/zook/gc-toolkit/pull/%s","branch":"polecat/x%s","merged_target":"main","check_set":"correctness"%s}}' \
    "$1" "$2" "$2" "$2" "${3:-}"
}
# A closed approve review bead backing <anchor>'s <lane> (default correctness) — the
# green record lane-state.sh derives, in place of the retired check.<lane>=green
# marker. reviewed_oid is what a local backing bead must carry to green a lane.
rev() { # anchor [lane] [oid]
  printf '{"id":"rev-%s","status":"closed","assignee":"","notes":"approve","metadata":{"task_kind":"review","anchor_bead":"%s","check_name":"%s","reviewed_oid":"%s","signoff_verdict":"approve"}}' \
    "$1" "$1" "${2:-correctness}" "${3:-sha-r}"
}
# An open finding on <anchor>, its disposition and lane settable. A must-fix
# finding also carries a blocks edge onto the anchor (wired in STUB_DEPS by the
# caller), which is what merge.sh's blocker probe reads.
finding() { # id anchor [disposition] [lane]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"task_kind":"finding","anchor_bead":"%s","finding.disposition":"%s","finding.lane":"%s","finding.key":"%s:0"}}' \
    "$1" "$2" "${3:-must-fix}" "${4:-correctness}" "${4:-correctness}"
}
prview() { # num state mergeState extra-json
  printf '{"state":"%s","isDraft":false,"baseRefName":"main","headRefName":"polecat/x%s","headRefOid":"sha-%s","headRepository":{"name":"gc-toolkit"},"headRepositoryOwner":{"login":"zook"},"isCrossRepository":false,"mergeStateStatus":"%s","mergeable":"MERGEABLE","reviewDecision":"","url":"https://github.com/zook/gc-toolkit/pull/%s","mergeCommit":{"oid":"merged-sha-%s"}%s}' \
    "$2" "$1" "$1" "$3" "$1" "$1" "${4:-}"
}
# A visit on <anchor>, tracking it via a tracks edge (wired in STUB_DEPS by the
# caller). Its OPEN existence is the whole signal the finalize gate reads.
visit() { # id anchor [status]
  printf '{"id":"%s","status":"%s","assignee":"","notes":"","title":"visit: %s","metadata":{"task_kind":"visit","gc.continuation_group":"%s"}}' \
    "$1" "${3:-open}" "$2" "$2"
}
# A non-city APPROVED review, given at the live head (sha-<num>) unless [oid]
# names another commit. The UNIVERSAL approval merge rule requires one standing
# on every PR, whatever commit it was given at. A test whose anchor should reach
# the CLEAN/BLOCKED/re-read/merge stages must carry one; a test that holds before
# the approval gate (merge_hold, duplicate, retarget, non-green lane, unclosed
# child, tracking_only) never reads it, so one is harmless there too.
approved() { # num [oid]
  printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-%s","submitted_at":"2026-08-20T01:00:00Z","id":1}]' \
    "${2:-$1}" > "$GH_DIR/reviews_$1.json"
}

# One node of the open-PR list merge.sh reads for its visit order: PR <num> at
# head sha-<num>, carrying each account's latest APPROVED or CHANGES_REQUESTED
# review as a login:STATE pair.
openpr() { # num [login:STATE ...]
  local n="$1" r revs="[]"; shift
  for r in "$@"; do
    revs=$(printf '%s' "$revs" | jq -c --arg l "${r%%:*}" --arg s "${r#*:}" \
      '. + [{state: $s, submittedAt: "2026-08-20T01:00:00Z", databaseId: (length + 1), author: {login: $l}}]')
  done
  jq -cn --argjson n "$n" --argjson r "$revs" \
    '{number: $n, isDraft: false, headRefOid: "sha-\($n)", latestOpinionatedReviews: {nodes: $r}}'
}
openprs() { local IFS=,; printf '[%s]' "$*" > "$GH_DIR/open_prs.json"; }
paced_views() { grep -o '^pr view [0-9]*' "$STUB_GH_LOG" | awk '{ print $3 }' | awk '!seen[$0]++' | paste -sd, -; }

# TWO ARMS, ONE BODY. The merge writer exists twice during the gctk migration —
# `gctk merge` (services/gctk) and the shell fallback in merge.sh — and a caller
# cannot tell which answered. So every assertion below runs against both: arm
# "shell" forces merge's fallback with GCTK_FALLBACK=merge, arm "gctk" reaches
# the freshly built binary through merge.sh, which also proves the preference
# wiring. GCTK_BIN names that build in both arms, because the shell records
# every landing through lifecycle.sh, and lifecycle.sh has no fallback.
suite() {

echo "# happy path"
store "[$(anchor M1 10), $(rev M1)]"
printf '%s' "$(prview 10 OPEN CLEAN)" > "$GH_DIR/pr_view_10.json"
approved 10
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "a clean merge pass exits 0"
has "$out" "merged + recorded M1" "the merge is reported"
ghlog=$(cat "$STUB_GH_LOG")
has "$ghlog" "pr view 10 --repo github.com/zook/gc-toolkit --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,reviewDecision,url" "the pinned read asks the exact field set"
has "$ghlog" "pr merge 10 --repo github.com/zook/gc-toolkit --squash --match-head-commit sha-10" "the merge is squash + head-matched"
eq "$(bstatus M1)" "closed" "the anchor closed"
eq "$(meta M1 merge_result)" "merged" "merge_result recorded"
eq "$(meta M1 merged_sha)" "merged-sha-10" "merged_sha recorded from mergeCommit.oid"
has "$(notes M1)" "Merged to main at merged-s" "the close reason names the landing"
eq "$(grep -c '^bd update M1' "$STUB_GC_LOG" || true)" "1" "ONE lifecycle update carried close+record"

echo "# a resolver that dies mid-run holds the merge (never reads empty as 'no lanes')"
# first_notgreen_lane captures the resolver's exit status: a crash prints nothing,
# and an empty lane list would read as all-green and merge on approval alone. Here
# the lane IS backed green and the PR IS approved, so ONLY the resolver's failure
# can hold it — proving the merge does not proceed on approval alone when it dies.
store "[$(anchor MR1 61), $(rev MR1)]"
printf '%s' "$(prview 61 OPEN CLEAN)" > "$GH_DIR/pr_view_61.json"
approved 61
cp "$SD/review-checks.sh" "$TMP/review-checks.real"
printf '#!/usr/bin/env bash\nexit 3\n' > "$SD/review-checks.sh"; chmod +x "$SD/review-checks.sh"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
cp "$TMP/review-checks.real" "$SD/review-checks.sh"; chmod +x "$SD/review-checks.sh"
has "$out" "lane state unreadable" "a resolver crash holds the merge as lane-state-unreadable"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 61" "the PR is NOT merged on approval alone when the resolver died"
eq "$(bstatus MR1)" "open" "the anchor stays open"

echo "# a missing check resolver holds the whole pass before it reads a PR"
# A pack-integrity gap, not one anchor's state: with no resolver every anchor
# would read as having no lanes, so the pass exits 1 rather than hold each one.
store "[$(anchor MR2 62), $(rev MR2)]"
printf '%s' "$(prview 62 OPEN CLEAN)" > "$GH_DIR/pr_view_62.json"
approved 62
mv "$SD/review-checks.sh" "$TMP/review-checks.moved"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
mv "$TMP/review-checks.moved" "$SD/review-checks.sh"
eq "$rc" 1 "a missing check resolver fails the pass"
has "$out" "merge: the check resolver is missing ($SD/review-checks.sh); merge held" "…naming the resolver it could not find"
eq "$(cat "$STUB_GH_LOG")" "" "…before it reads a single PR"
eq "$(bstatus MR2)" "open" "…and the anchor stays open"

echo "# a broken lane or finalize helper holds its own anchor, never the pass"
# Only the check resolver is required up front. lane-state.sh and finalize-gate.sh
# fail where they are called, which holds that one open PR, and a PR that has
# already merged still gets its record, which needs neither helper.
for helper in lane-state.sh finalize-gate.sh; do
  case "$helper" in
    lane-state.sh) why="PR#65 lane state unreadable on anchor HM1; merge held" ;;
    finalize-gate.sh) why="PR#65 finalize gate refused (fail-closed); merge held (anchor HM1)" ;;
  esac
  store "[$(anchor HM1 65), $(rev HM1), $(anchor HM2 66)]"
  printf '%s' "$(prview 65 OPEN CLEAN)" > "$GH_DIR/pr_view_65.json"
  printf '%s' "$(prview 66 MERGED CLEAN)" > "$GH_DIR/pr_view_66.json"
  approved 65
  chmod -x "$SD/$helper"
  : > "$STUB_GH_LOG"
  out=$("$SUT" 2>&1); rc=$?
  chmod +x "$SD/$helper"
  eq "$rc" 0 "a non-executable $helper leaves the pass at exit 0"
  has "$out" "merge: $why" "…holding the open PR at the $helper call"
  hasnt "$(cat "$STUB_GH_LOG")" "pr merge 65" "…which does not merge"
  has "$out" "merge: recovered HM2" "…while the PR already merged gets its record"
  eq "$(bstatus HM2)" "closed" "…and its anchor closes"
  has "$out" "merge: 0 merged, 1 recovered, 1 held, 0 skipped, 0 record-failed" "…in one pass that reads both anchors"
done

echo "# merge_hold"
store "[$(anchor M2 11 ',"merge_hold":"true"')]"
printf '%s' "$(prview 11 OPEN CLEAN)" > "$GH_DIR/pr_view_11.json"
approved 11
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merge_hold set (operator gate); merge held" "merge_hold holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# one-anchor-per-PR holds + escalates once"
store "[$(anchor M3 12), $(anchor M3b 12)]"
printf '%s' "$(prview 12 OPEN CLEAN)" > "$GH_DIR/pr_view_12.json"
approved 12
: > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"
out=$("$SUT" 2>&1)
has "$out" "claimed by more than one open anchor" "the duplicate holds every anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "no merge under a duplicate claim"
has "$(cat "$STUB_ESC_LOG")" "--subject M3 --key one-anchor-per-pr.12" "escalate.sh got the situation key"

# The duplicate guard is repo-qualified the same way the in-flight holder
# filter is (REPO_Q_DEF): a second anchor of this number is a duplicate unless
# its own pr_url names a DIFFERENT repository. An absent or unparseable pr_url
# names no repository ("?") and must still hold — matching the live PR's url
# byte for byte would drop it and merge the same PR twice.
echo "# one-anchor-per-PR: a same-number anchor with no pr_url still holds"
store "[$(anchor M3c 42), $(printf '%s' "$(anchor M3d 42)" | jq -c 'del(.metadata.pr_url)')]"
printf '%s' "$(prview 42 OPEN CLEAN)" > "$GH_DIR/pr_view_42.json"
approved 42
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "claimed by more than one open anchor" "an anchor of this number whose pr_url is ABSENT names no repository and still holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and neither anchor merged"

echo "# one-anchor-per-PR: a same-number anchor with an unparseable pr_url still holds"
store "[$(anchor M3e 43), $(printf '%s' "$(anchor M3f 43)" | jq -c '.metadata.pr_url = "TBD"')]"
printf '%s' "$(prview 43 OPEN CLEAN)" > "$GH_DIR/pr_view_43.json"
approved 43
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "claimed by more than one open anchor" "an anchor of this number whose pr_url is UNPARSEABLE still holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and neither anchor merged"

echo "# one-anchor-per-PR: a same-number anchor in ANOTHER repository does not hold"
store "[$(anchor M3g 44), $(rev M3g), $(printf '%s' "$(anchor M3h 44)" | jq -c '.metadata.pr_url = "https://github.com/other/repo/pull/44"')]"
printf '%s' "$(prview 44 OPEN CLEAN)" > "$GH_DIR/pr_view_44.json"
approved 44
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M3g" "a same-number anchor whose pr_url names a DIFFERENT repository is a different PR and does not hold"

# The wildcard is symmetric. When it is THIS anchor whose pr_url is absent, it
# names no repository and must collide with every same-number anchor, including
# one whose pr_url resolves to a DIFFERENT repository. Keying this anchor to the
# origin remote instead of its own row would merge it while a foreign
# same-number anchor sits unresolved.
echo "# one-anchor-per-PR: a URL-less THIS anchor is the wildcard against a foreign same-number anchor"
store "[$(printf '%s' "$(anchor M3i 45)" | jq -c 'del(.metadata.pr_url)'), $(printf '%s' "$(anchor M3j 45)" | jq -c '.metadata.pr_url = "https://github.com/other/repo/pull/45"')]"
printf '%s' "$(prview 45 OPEN CLEAN)" > "$GH_DIR/pr_view_45.json"
approved 45
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "open anchor (M3i + M3j)" "this anchor's OWN absent pr_url makes it the wildcard that holds against a foreign same-number anchor"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and the URL-less anchor is not merged past the unresolved foreign twin"

echo "# retarget holds"
store "[$(anchor M4 13)]"
printf '%s' "$(prview 13 OPEN CLEAN)" | jq -c '.baseRefName = "release"' > "$GH_DIR/pr_view_13.json"
approved 13
out=$("$SUT" 2>&1)
has "$out" "base 'release' != merged_target 'main'" "a retargeted PR holds"

echo "# a lane short of green holds"
store "[$(anchor M5 14)]"
printf '%s' "$(prview 14 OPEN CLEAN)" > "$GH_DIR/pr_view_14.json"
# No approver: the lane gate precedes the approval gate, and a GitHub approval
# would back this bead-less lane green through the fallback (the M5c case), hiding
# the hold this tests.
echo '[]' > "$GH_DIR/reviews_14.json"
out=$("$SUT" 2>&1)
has "$out" "lane 'correctness' does not derive green" "an unreviewed lane holds"

echo "# every other lane state holds too"
store "[$(anchor M5b 15)]"
printf '%s' "$(prview 15 OPEN CLEAN)" > "$GH_DIR/pr_view_15.json"
echo '[]' > "$GH_DIR/reviews_15.json"
out=$("$SUT" 2>&1)
has "$out" "lane 'correctness' does not derive green" "a fixing lane holds the merge"

echo "# a correctness lane with no local review bead derives green from an operator's GitHub approval"
# The fallback-backed anchor: no review-outcome bead, but a human APPROVED the
# PR. The shared derivation backs the lane off that approval, so a correctness-only
# anchor is not stranded on lane state — it merges without a local review bead.
store "[$(anchor M5c 47)]"
printf '%s' "$(prview 47 OPEN CLEAN)" > "$GH_DIR/pr_view_47.json"
printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-47","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_47.json"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M5c" "an operator's GitHub approval backs the correctness lane green when no local review bead exists"

echo "# unclosed children hold: metadata key, dep edge, tracking_only opt-out"
store "[$(anchor M6 16), $(rev M6), {\"id\":\"rw-1\",\"status\":\"blocked\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"16\"}}]"
printf '%s' "$(prview 16 OPEN CLEAN)" > "$GH_DIR/pr_view_16.json"
approved 16
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead rw-1 (blocked)" "a pr_number child holds (blocked counts)"

store "[$(anchor M7 17), $(rev M7), {\"id\":\"rw-2\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"merge_result\":\"pre_open_gate\"}}]"
printf '%s' "$(prview 17 OPEN CLEAN)" > "$GH_DIR/pr_view_17.json"
approved 17
printf 'rw-2|blocks|M7\n' > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead rw-2" "a dep-edge blocker holds even carrying merge_result"

store "[$(anchor M8 18), $(rev M8), {\"id\":\"trk-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"18\",\"tracking_only\":\"true\"}}]"
printf '%s' "$(prview 18 OPEN CLEAN)" > "$GH_DIR/pr_view_18.json"
approved 18
: > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M8" "a tracking_only pr_number reference does not hold"

# The comment arm's visit path holds the merge through this probe and nothing
# else: escalate.sh files the visit DEPENDING on its subject, so a blocks edge
# back would be a cycle, and pr_number is what is left to hold on.
store "[$(anchor M9 19), $(rev M9), {\"id\":\"vis-1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"19\",\"task_kind\":\"visit\",\"anchor_bead\":\"M9\"}}]"
printf '%s' "$(prview 19 OPEN CLEAN)" > "$GH_DIR/pr_view_19.json"
approved 19
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead vis-1" "an open visit stamped with the PR holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 19" "…and nothing merged"
store "[$(anchor M9b 20), $(rev M9b), {\"id\":\"vis-2\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"pr_number\":\"20\",\"task_kind\":\"visit\",\"anchor_bead\":\"M9b\"}}]"
printf '%s' "$(prview 20 OPEN CLEAN)" > "$GH_DIR/pr_view_20.json"
approved 20
out=$("$SUT" 2>&1)
has "$out" "merged + recorded M9b" "closing the visit is the release, and it performs"


# A referencing bead is qualified by the repository ITS OWN pr_url names: bd
# matches the bare number, and the same number in another repository is a
# different PR. Unknown is not foreign, so only a url resolving elsewhere is
# dropped — which is what keeps the number-only children above holding.
kid() { # id num extra-metadata-json
  printf '{"id":"%s","status":"open","assignee":"","notes":"","metadata":{"pr_number":"%s"%s}}' "$1" "$2" "${3:-}"
}
: > "$STUB_DEPS"
store "[$(anchor Q1 24), $(rev Q1), $(kid fgn-1 24 ',"pr_url":"https://github.com/other/repo/pull/24"')]"
printf '%s' "$(prview 24 OPEN CLEAN)" > "$GH_DIR/pr_view_24.json"
approved 24
out=$("$SUT" 2>&1)
has "$out" "merged + recorded Q1" "a same-numbered bead in ANOTHER repository does not hold this merge"

store "[$(anchor Q2 25), $(rev Q2), $(kid loc-1 25 ',"pr_url":"https://github.com/zook/gc-toolkit/pull/25"')]"
printf '%s' "$(prview 25 OPEN CLEAN)" > "$GH_DIR/pr_view_25.json"
approved 25
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead loc-1" "a child carrying THIS repository's pr_url still holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 25" "…and nothing merged"

# pr-facts.sh stamps pr_url beside pr_number on every child it files, so what a
# url compare drops is the whole in-flight probe. Both ways of naming this
# repository without matching it byte for byte stay holders.
store "[$(anchor Q3 26), $(rev Q3), $(kid case-1 26 ',"pr_url":"https://GitHub.com/Zook/GC-Toolkit/pull/26"')]"
printf '%s' "$(prview 26 OPEN CLEAN)" > "$GH_DIR/pr_view_26.json"
approved 26
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead case-1" "repository identity is case-insensitive, so a differently-cased url holds"
# …and the case can differ on the checkout's side just as well: the repository
# a remote url names is the same repository whatever case it is written in.
store "[$(printf '%s' "$(anchor Q3b 29)" | jq -c '.metadata.pr_url = "https://github.com/Zook/GC-Toolkit/pull/29"'), $(rev Q3b), $(kid case-2 29 ',"pr_url":"https://github.com/zook/gc-toolkit/pull/29"')]"
printf '%s' "$(prview 29 OPEN CLEAN)" \
  | jq -c '.url = "https://github.com/Zook/GC-Toolkit/pull/29"
           | .headRepositoryOwner.login = "Zook" | .headRepository.name = "GC-Toolkit"' > "$GH_DIR/pr_view_29.json"
approved 29
out=$(STUB_ORIGIN_URL="https://github.com/Zook/GC-Toolkit" "$SUT" 2>&1)
has "$out" "unclosed rework/review bead case-2" "…and a differently-cased ORIGIN matches the url a bead carries"

store "[$(anchor Q4 27), $(rev Q4), $(kid junk-1 27 ',"pr_url":"TBD"')]"
printf '%s' "$(prview 27 OPEN CLEAN)" > "$GH_DIR/pr_view_27.json"
approved 27
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead junk-1" "an unparseable pr_url names no repository and still holds"

# The edge is the claim, and an edge is local by construction: a dep-edge holder
# is never qualified by the url it happens to carry.
store "[$(anchor Q5 28), $(rev Q5), $(kid dep-fgn 28 ',"pr_url":"https://github.com/other/repo/pull/28"')]"
printf '%s' "$(prview 28 OPEN CLEAN)" > "$GH_DIR/pr_view_28.json"
approved 28
printf 'dep-fgn|blocks|Q5\n' > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "unclosed rework/review bead dep-fgn" "a dep-edge blocker holds whatever repository its url names"
: > "$STUB_DEPS"

echo "# an open must-fix finding holds the merge, and the hold names it"
# A must-fix finding blocks its anchor by the same `blocks` edge a rework child
# uses, so the in-flight probe already holds. Target 4's change is that the hold
# NAMES the finding rather than reporting it as an unclosed rework bead.
store "[$(anchor MF1 46), $(rev MF1), $(finding fnd-mf1 MF1)]"
printf 'fnd-mf1|blocks|MF1\n' > "$STUB_DEPS"
printf '%s' "$(prview 46 OPEN CLEAN)" > "$GH_DIR/pr_view_46.json"
approved 46
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "held by must-fix finding fnd-mf1" "the hold names the finding by its disposition"
hasnt "$out" "unclosed rework/review bead fnd-mf1" "…and does not report the finding as a rework child"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 46" "…and nothing merged over the open must-fix"

echo "# closing the must-fix finding releases the merge, nothing else written"
# The edge survives the close; the blocker probe holds only on a LIVE blocker,
# so the finding's own close is the release — no marker to clear, no edge to cut.
store "[$(anchor MF1 46), $(rev MF1), $(printf '%s' "$(finding fnd-mf1 MF1)" | jq -c '.status = "closed"')]"
printf 'fnd-mf1|blocks|MF1\n' > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded MF1" "every lane green and no open must-fix: the merge lands"
: > "$STUB_DEPS"

echo "# an OPEN visit on the anchor holds the merge (finalize gate), and the hold names it"
# The visit tracks the anchor (non-blocking), so no earlier blocker probe sees it;
# the finalize gate reads its open existence and holds THIS anchor's merge.
store "[$(anchor MV1 47), $(rev MV1), $(visit vis-mv1 MV1)]"
printf 'vis-mv1|tracks|MV1\n' > "$STUB_DEPS"
printf '%s' "$(prview 47 OPEN CLEAN)" > "$GH_DIR/pr_view_47.json"
approved 47
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "held by open visit vis-mv1" "an open visit holds the merge, naming the visit"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 47" "…and nothing merged under the open visit"
eq "$(bstatus MV1)" "open" "…and the anchor stays open"

echo "# a CLOSED visit on the anchor does not hold the merge"
store "[$(anchor MV2 48), $(rev MV2), $(visit vis-mv2 MV2 closed)]"
printf 'vis-mv2|tracks|MV2\n' > "$STUB_DEPS"
printf '%s' "$(prview 48 OPEN CLEAN)" > "$GH_DIR/pr_view_48.json"
approved 48
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded MV2" "a closed visit is no hold: the merge lands"
: > "$STUB_DEPS"

echo "# a visit filed mid-pass is caught by the terminal re-read (a visit does not move the head)"
# The anchor validates clean, then an open visit is filed before the merge. It is
# subject-local — no head move — so --match-head-commit cannot catch it; only the
# terminal finalize-gate re-assert can. The store gains the visit on MV3's SECOND
# read (the terminal re-read), via the same STUB_SHOW_HOOK seam the other
# terminal-re-read cases use.
store "[$(anchor MV3 49), $(rev MV3)]"
: > "$STUB_DEPS"
printf '%s' "$(prview 49 OPEN CLEAN)" > "$GH_DIR/pr_view_49.json"
approved 49
MV3_HOOK_COUNT="$TMP/hookcount_mv3"; : > "$MV3_HOOK_COUNT"
cat > "$TMP/hook_mv3.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "MV3" ] || exit 0
n=\$(cat "$MV3_HOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$MV3_HOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
  jq -c '. + [{"id":"vis-mv3","status":"open","assignee":"","notes":"","title":"visit: MV3","issue_type":"task","metadata":{"task_kind":"visit","gc.continuation_group":"MV3"}}]' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
  printf 'vis-mv3|tracks|MV3\n' >> "\$STUB_DEPS"
fi
HOOK
chmod +x "$TMP/hook_mv3.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/hook_mv3.sh" "$SUT" 2>&1)
has "$out" "changed between validation and the merge" "the terminal re-read holds on a mid-pass visit"
has "$out" "held by open visit vis-mv3" "…and names the mid-pass visit"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 49" "…and nothing merged"
: > "$STUB_DEPS"

echo "# approval is a UNIVERSAL merge rule: every PR needs a standing non-city APPROVED"
store "[$(anchor A1 20), $(rev A1)]"
printf '%s' "$(prview 20 OPEN CLEAN)" > "$GH_DIR/pr_view_20.json"
echo '[]' > "$GH_DIR/reviews_20.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review stands" "a correctness-only anchor with no approval holds — the rule is universal, not a check_set token"

approved 20
out=$("$SUT" 2>&1)
has "$out" "merged + recorded A1" "an external APPROVED at the live head satisfies it"

echo "# an approval stands across later pushes until it is dismissed"
# Approved at an older head, then pushed again (a rework, a merge-in, a CI fix)
# with every other gate green.
approved 20 OLD
store "[$(anchor A1 20), $(rev A1)]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded A1" "an approval given at an older head still satisfies the rule after a push"
has "$(cat "$STUB_GH_LOG")" "pr merge 20 --repo github.com/zook/gc-toolkit --squash --match-head-commit sha-20" "…and the merge is pinned to the live head it validated, not the approved commit"

echo "# a dismissed review is dropped: it neither approves nor hides an older approval"
printf '[{"user":{"login":"human1"},"state":"DISMISSED","commit_id":"sha-OLD","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20), $(rev A1)]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review stands" "a dismissed approval holds the PR"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 20" "…and nothing merged"

# human1 approved at an older head, then requested changes, and that request was
# dismissed once its fix landed. GitHub reports the dismissed request as DISMISSED.
printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-OLD","submitted_at":"2026-08-20T01:00:00Z","id":1},{"user":{"login":"human1"},"state":"DISMISSED","commit_id":"sha-20","submitted_at":"2026-08-21T01:00:00Z","id":2}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20), $(rev A1)]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded A1" "a later dismissed review does not hide its author's older approval"
has "$(cat "$STUB_GH_LOG")" "pr merge 20 --repo github.com/zook/gc-toolkit --squash --match-head-commit sha-20" "…and the PR merges on that approval, pinned to the live head"

# human1 approved at an older head; human2's CHANGES_REQUESTED was dismissed
# later. One approval stands and no veto does.
printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-OLD","submitted_at":"2026-08-20T01:00:00Z","id":1},{"user":{"login":"human2"},"state":"DISMISSED","commit_id":"sha-20","submitted_at":"2026-08-21T01:00:00Z","id":2}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20), $(rev A1)]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded A1" "another reviewer's dismissed CHANGES_REQUESTED leaves an older approval standing"
has "$(cat "$STUB_GH_LOG")" "pr merge 20 --repo github.com/zook/gc-toolkit --squash --match-head-commit sha-20" "…and the PR merges on human1's approval"

printf '[{"user":{"login":"gc-city-bot"},"state":"APPROVED","commit_id":"sha-20","submitted_at":"2026-08-20T01:00:00Z","id":1}]' > "$GH_DIR/reviews_20.json"
store "[$(anchor A1 20), $(rev A1)]"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "a self-approval by the city account never counts"

echo "# the universal rule arms for every PR with no check_set token and no opt-out"
store "[$(anchor A2 21), $(rev A2)]"
printf '%s' "$(prview 21 OPEN CLEAN)" > "$GH_DIR/pr_view_21.json"
echo '[]' > "$GH_DIR/reviews_21.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "a plain correctness anchor, never opted in, is held for approval just the same"

echo "# an unresolved acting login holds even an approved, green PR"
# With no login the city cannot tell an external approver from its own review,
# so the universal rule holds every PR rather than count an approval it cannot
# attribute.
store "[$(anchor A3 63), $(rev A3)]"
printf '%s' "$(prview 63 OPEN CLEAN)" > "$GH_DIR/pr_view_63.json"
approved 63
: > "$STUB_GH_LOG"
out=$(STUB_SELF_LOGIN="" "$SUT" 2>&1)
has "$out" "merge: WARN acting login unresolved; cannot distinguish an external approver from the city's own review" "an unresolved login warns that the approval gate holds every PR"
has "$out" "PR#63 approval required but the acting login is unresolved; merge held (anchor A3)" "…and holds the approved, green PR"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a standing CHANGES_REQUESTED vetoes every candidate"
store "[$(anchor A4 23), $(rev A4)]"
printf '%s' "$(prview 23 OPEN CLEAN)" > "$GH_DIR/pr_view_23.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_23.json"
out=$("$SUT" 2>&1)
has "$out" "standing CHANGES_REQUESTED" "the veto holds a correctness-only anchor too"

# A standing approval does not outrank a veto: human1's approval from an older
# head still stands, and human2's CHANGES_REQUESTED still holds the PR.
printf '%s' "$(prview 23 OPEN CLEAN)" > "$GH_DIR/pr_view_23.json"
printf '[{"user":{"login":"human1"},"state":"APPROVED","commit_id":"sha-old","submitted_at":"2026-08-18T00:00:00Z","id":1},{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":2}]' > "$GH_DIR/reviews_23.json"
store "[$(anchor A4 23), $(rev A4)]"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "reviewer 'human2' has a standing CHANGES_REQUESTED" "a standing CHANGES_REQUESTED vetoes an approval that stands from an older head"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 23" "…and nothing merged"

echo "# BLOCKED where thread resolution is required names the unresolved-thread cause"
store "[$(anchor U1 30), $(rev U1)]"
printf '%s' "$(prview 30 OPEN BLOCKED)" > "$GH_DIR/pr_view_30.json"
approved 30
echo '{"threads":[{"id":"t1","isResolved":false},{"id":"t2","isResolved":false}]}' > "$GH_DIR/threads_30.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#30 is BLOCKED by branch protection: 2 unresolved review thread(s) hold required_review_thread_resolution" "BLOCKED names the unresolved-thread cause and how many"
has "$out" "merge held (anchor U1)" "…and still holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and a BLOCKED PR is never merged"

echo "# BLOCKED where thread resolution is OFF names the approval, never the open thread"
store "[$(anchor U1a 39), $(rev U1a)]"
printf '%s' "$(prview 39 OPEN BLOCKED)" > "$GH_DIR/pr_view_39.json"
approved 39
echo '{"threads":[{"id":"t1","isResolved":false},{"id":"t2","isResolved":false}]}' > "$GH_DIR/threads_39.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
has "$out" "PR#39 is BLOCKED by branch protection: waiting on an approving review (1 required" "an open thread is not the cause when required_review_thread_resolution is off"
hasnt "$out" "PR#39 is BLOCKED by branch protection: 2 unresolved review thread(s) hold" "…and the open threads are never named as the gate"

echo "# BLOCKED with every thread resolved names the approval wait instead"
store "[$(anchor U1b 33), $(rev U1b)]"
printf '%s' "$(prview 33 OPEN BLOCKED)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_33.json"
approved 33
echo '{"threads":[{"id":"t1","isResolved":true}]}' > "$GH_DIR/threads_33.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
has "$out" "waiting on an approving review (1 required, reviewDecision='REVIEW_REQUIRED')" "BLOCKED with resolved threads names the approval wait"
has "$out" "merge held (anchor U1b)" "…and still holds"

echo "# BLOCKED whose reviewThreads cannot be read (thread resolution required) is named, never guessed"
store "[$(anchor U1c 34), $(rev U1c)]"
printf '%s' "$(prview 34 OPEN BLOCKED)" > "$GH_DIR/pr_view_34.json"
approved 34
echo '{"threads":[{"id":"t1","isResolved":false}]}' > "$GH_DIR/threads_34.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$(STUB_GQL_READ_FAIL=1 "$SUT" 2>&1)
has "$out" "review-thread resolution is required but its reviewThreads could not be read to count them" "an unreadable connection is named, not guessed"
has "$out" "merge held (anchor U1c)" "…and still holds"

echo "# BLOCKED whose branch rules cannot be read is named as such, never guessed"
store "[$(anchor U1e 45), $(rev U1e)]"
printf '%s' "$(prview 45 OPEN BLOCKED)" > "$GH_DIR/pr_view_45.json"
approved 45
printf '{"message":"Not Found"}' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
has "$out" "the rules for 'main' could not be read to name the cause" "unreadable branch rules are named, not guessed"
has "$out" "merge held (anchor U1e)" "…and still holds"
rm -f "$GH_DIR/rules_main.json"

store "[$(anchor U2 31), $(rev U2)]"
printf '%s' "$(prview 31 OPEN UNSTABLE ',"statusCheckRollup":[]')" > "$GH_DIR/pr_view_31.json"
approved 31
out=$("$SUT" 2>&1)
has "$out" "merged + recorded U2" "UNSTABLE with zero required contexts proceeds"

store "[$(anchor U3 32), $(rev U3)]"
printf '%s' "$(prview 32 OPEN UNSTABLE ',"statusCheckRollup":[{"name":"ci","conclusion":"FAILURE"}]')" > "$GH_DIR/pr_view_32.json"
approved 32
printf '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"}]}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
has "$out" "a REQUIRED check is not green" "UNSTABLE with a red required check holds"
rm -f "$GH_DIR/rules_main.json"

echo "# identity refusals"
store "[$(anchor I1 40)]"
printf '%s' "$(prview 40 OPEN CLEAN)" | jq -c '.headRepositoryOwner.login = "stranger" | .isCrossRepository = true' > "$GH_DIR/pr_view_40.json"
approved 40
out=$("$SUT" 2>&1)
has "$out" "not this repository's own branch; merge held" "a fork head is refused"

store "[$(anchor I2 41)]"
printf '%s' "$(prview 41 OPEN CLEAN)" | jq -c '.headRefName = "other/branch"' > "$GH_DIR/pr_view_41.json"
approved 41
out=$("$SUT" 2>&1)
has "$out" "records branch 'polecat/x41' but PR#41 is opened from 'other/branch'" "a head-branch mismatch is refused"

echo "# terminal re-read holds on a mid-pass write"
store "[$(anchor T1 50), $(rev T1)]"
printf '%s' "$(prview 50 OPEN CLEAN)" > "$GH_DIR/pr_view_50.json"
approved 50
# The gh stub runs AFTER the fresh re-read: model the mid-pass write by having
# the reviews file swap the marker via a hook — instead, simplest: drop the
# check marker between reads is not injectable, so assert the hold via
# merge_hold appearing only in the terminal read using STUB_DROP_KEYS inverse:
# store the hold from the start but drop it from the FIRST update path is not a
# read; so exercise the re-read by pre-setting a hold the early gate misses is
# impossible — covered instead by asserting the re-read HAPPENS:
: > "$STUB_GC_LOG"
out=$("$SUT" 2>&1)
shows=$(grep -c '^bd show T1' "$STUB_GC_LOG" || true)
[ "$shows" -ge 2 ] && ok "the anchor is re-read at least twice (validation + terminal)" \
                   || bad "expected >=2 anchor reads, got $shows"
has "$out" "merged + recorded T1" "…and a clean pass still merges"

echo "# record failure after a merge exits non-zero loudly"
store "[$(anchor R1 60), $(rev R1)]"
printf '%s' "$(prview 60 OPEN CLEAN)" > "$GH_DIR/pr_view_60.json"
approved 60
out=$(STUB_UPDATE_FAIL="R1" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a failed record exits non-zero"
has "$out" "MERGED but the lifecycle record FAILED" "…and says the PR did land"
has "$(cat "$STUB_GH_LOG")" "pr merge 60" "the merge itself was performed"

echo "# a PR already merged is the record this arm recovers"
# The window this closes: the merge lands, the pass is killed before the record,
# and the anchor says pull_request over a PR that is on main. Recovering it here
# rather than downstream is what makes it reachable — the arms are ordered, and a
# pass killed at its timeout loses the later ones.
store "[$(anchor S1 70)]"
printf '%s' "$(prview 70 MERGED CLEAN)" > "$GH_DIR/pr_view_70.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the recovering pass exits 0"
has "$out" "1 recovered" "a PR already merged is recovered, not skipped"
eq "$(bstatus S1)" "closed" "the anchor closed"
eq "$(meta S1 merge_result)" "merged" "merge_result recorded"
eq "$(meta S1 merged_sha)" "merged-sha-70" "merged_sha recorded from mergeCommit.oid"
has "$(notes S1)" "Merged to main at merged-s" "the note names where it landed"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 70" "nothing was merged — the PR was already on main"
# Never an empty merged_sha, the same invariant the merge path holds (I5).
store "[$(anchor S2 71)]"
printf '%s' "$(prview 71 MERGED CLEAN)" | jq -c 'del(.mergeCommit)' > "$GH_DIR/pr_view_71.json"
out=$("$SUT" 2>&1)
eq "$(meta S2 merged_sha)" "unverified:PR#71" "an unreadable mergeCommit records unverified, never empty"
eq "$(bstatus S2)" "closed" "…and the anchor still closes"
# A recovery that cannot record is the same false-durable-record class as one
# that fails after a merge, and it is just as loud.
store "[$(anchor S3 72)]"
printf '%s' "$(prview 72 MERGED CLEAN)" > "$GH_DIR/pr_view_72.json"
out=$(STUB_UPDATE_FAIL="S3" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a failed recovery exits non-zero"
has "$out" "is MERGED but the record failed" "…and says the PR did land"
eq "$(bstatus S3)" "open" "…leaving the anchor for the next pass"

# --- the record retry is bounded -----------------------------------------------
# Both record arms retry every pass with no memory of the last one. That is right
# for a store busy for a tick and useless for a cause the next pass meets
# unchanged, and the difference between the two is only visible in a count.
# record-failure-cap.sh keeps it on the anchor; escalate.sh spends it on one
# visit. STUB_CLOSE_FAIL is what makes this the real shape rather than a total
# outage: the close is refused, and the counter beside it still writes — which is
# bd's own asymmetry, its ownership check being a property of the close.
echo "# the record retry is bounded"
store "[$(anchor C1 80)]"
printf '%s' "$(prview 80 MERGED CLEAN)" > "$GH_DIR/pr_view_80.json"
: > "$STUB_ESC_LOG"
out=$(STUB_CLOSE_FAIL="C1" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a refused close still fails the pass loudly"
eq "$(bstatus C1)" "open" "…and leaves the anchor open"
eq "$(meta C1 merge_record_failures)" "1" "the first failure is counted on the anchor"
eq "$(cat "$STUB_ESC_LOG")" "" "…and one failure escalates nothing — the retry is still the answer"

# Under the cap, the count climbs and nothing is filed. The mirror below is what
# makes this assertion mean something: an escalation that never fires would
# satisfy it just as well.
out=$(STUB_CLOSE_FAIL="C1" "$SUT" 2>&1)
eq "$(meta C1 merge_record_failures)" "2" "a second failure counts again"
eq "$(cat "$STUB_ESC_LOG")" "" "…still under the cap, still nothing filed"

out=$(STUB_CLOSE_FAIL="C1" "$SUT" 2>&1)
eq "$(meta C1 merge_record_failures)" "3" "the third failure reaches the cap"
has "$out" "failed to record merged PR#80 3 times" "…the pass says the retry is not converging"
esc=$(cat "$STUB_ESC_LOG")
has "$esc" "--subject C1" "…and the anchor is escalated as the subject"
has "$esc" "--key merge-record-failed.80" "…keyed on the PR, so one visit covers every pass"
has "$esc" "still records merge_result=pull_request" "…naming the false-durable record a person has to repair"

# Past the cap the call stays unconditional: escalate.sh holds it to one open
# visit, and a visit closed without repairing the anchor is re-filed rather than
# lost to a crossing that already happened.
: > "$STUB_ESC_LOG"
out=$(STUB_CLOSE_FAIL="C1" "$SUT" 2>&1)
eq "$(meta C1 merge_record_failures)" "4" "the count keeps climbing past the cap"
has "$(cat "$STUB_ESC_LOG")" "--key merge-record-failed.80" "…and every later failure re-files rather than going quiet"

# The record that lands clears the count, so "consecutive" is what the anchor
# actually holds — a later unrelated failure starts its own budget.
: > "$STUB_ESC_LOG"
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass that finally records exits 0"
eq "$(bstatus C1)" "closed" "…the anchor closes"
eq "$(meta C1 merge_record_failures)" "<absent>" "…and the landed record clears the count"
eq "$(cat "$STUB_ESC_LOG")" "" "…filing nothing on the way out"

# The counter is not what closes the anchor: a cap that cannot count must not be
# what fails a pass, and must not stop the retry that is still the repair.
store "[$(anchor C2 81)]"
printf '%s' "$(prview 81 MERGED CLEAN)" > "$GH_DIR/pr_view_81.json"
: > "$STUB_ESC_LOG"
out=$(STUB_UPDATE_FAIL="C2" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a store refusing every write on the anchor still fails the pass"
has "$out" "could not count the record failure" "…and says the cap could not arm from it"
eq "$(bstatus C2)" "open" "…leaving the anchor for the next pass"

# Merged truth is recorded by `bd update --status=closed`, never by `bd close`.
# bd's ownership check is a property of the close verb and refuses a bead
# assigned to another principal, which every anchor here is ("rig/refinery").
# The harness models no acting identity, so no stub can answer this in either
# direction — the emitted command is what pins it, and the --status=closed
# assertion on the happy path above is its mirror.
hasnt "$(cat "$STUB_GC_LOG")" "bd close" "the record never uses the \`bd close\` verb, whose ownership check refuses a bead assigned to another principal"

# The enumerated row is a snapshot, and the record is written from the PR read
# that followed it. A mid-pass write can detach the anchor between the two:
# the live re-read is what sees that, before anything is written.
store "[$(anchor S4 73)]"
printf '%s' "$(prview 73 MERGED CLEAN)" > "$GH_DIR/pr_view_73.json"
cat > "$TMP/s4hook.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "S4" ] || exit 0
tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
jq -c 'map(if .id == "S4" then (.metadata |= del(.merge_result)) else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
HOOK
chmod +x "$TMP/s4hook.sh"
out=$(STUB_SHOW_HOOK="$TMP/s4hook.sh" "$SUT" 2>&1)
eq "$(bstatus S4)" "open" "an anchor detached since the enumeration is not closed"
eq "$(meta S4 merged_sha)" "<absent>" "…and nothing is recorded on it"
has "$out" "changed since enumeration" "…the live re-read is what catches it"
# The same-state move --expect cannot see: the anchor keeps merge_result and is
# re-pointed at another PR. Recording from the enumerated PR would stamp its
# merge commit, number and branch onto an anchor now gating a different one —
# a merged record that is false on the live bead.
store "[$(anchor S7 76)]"
printf '%s' "$(prview 76 MERGED CLEAN)" > "$GH_DIR/pr_view_76.json"
cat > "$TMP/s7hook.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "S7" ] || exit 0
tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
jq -c 'map(if .id == "S7" then (.metadata.pr_number = "77"
  | .metadata.pr_url = "https://github.com/zook/gc-toolkit/pull/77"
  | .metadata.branch = "polecat/x77") else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
HOOK
chmod +x "$TMP/s7hook.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/s7hook.sh" "$SUT" 2>&1)
eq "$(bstatus S7)" "open" "an anchor re-pointed at another PR is not closed"
eq "$(meta S7 merged_sha)" "<absent>" "…and no merge commit is stamped on it"
eq "$(meta S7 pr_number)" "77" "…the anchor keeps the PR it now gates"
has "$out" "anchor S7 changed since enumeration" "…and the skip names it"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…nothing was merged either"
# An anchor whose recorded PR identity disagrees with the PR being recorded is
# a repair only an operator can make — the record holds on it, as the merge does.
store "[$(anchor S8 78)]"
printf '%s' "$(prview 78 MERGED CLEAN)" | jq -c '.headRefName = "other/branch"' > "$GH_DIR/pr_view_78.json"
out=$("$SUT" 2>&1)
has "$out" "records branch 'polecat/x78' but PR#78 is opened from 'other/branch'" "a head-branch mismatch holds the record"
eq "$(bstatus S8)" "open" "…and nothing is recorded on it"
store "[$(anchor S9 79)]"
printf '%s' "$(prview 79 MERGED CLEAN)" | jq -c '.url = "https://github.com/zook/gc-toolkit/pull/99"' > "$GH_DIR/pr_view_79.json"
out=$("$SUT" 2>&1)
has "$out" "records pr_url 'https://github.com/zook/gc-toolkit/pull/79'" "a pr_url mismatch holds the record"
eq "$(bstatus S9)" "open" "…and nothing is recorded on it"
# --expect covers the rest of the window: a detach landing AFTER the re-read is
# seen only by the transition's own read. unanchored -> merged is a LEGAL edge,
# so edge legality does not cover this — only --expect does. The hook fires on
# the second show of SA, which is that read.
store "[$(anchor SA 90)]"
printf '%s' "$(prview 90 MERGED CLEAN)" > "$GH_DIR/pr_view_90.json"
rm -f "$TMP/sa.count"
cat > "$TMP/sahook.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "SA" ] || exit 0
n=\$(cat "$TMP/sa.count" 2>/dev/null || echo 0); n=\$((n + 1))
printf '%s' "\$n" > "$TMP/sa.count"
[ "\$n" -ge 2 ] || exit 0
tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
jq -c 'map(if .id == "SA" then (.metadata |= del(.merge_result)) else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
HOOK
chmod +x "$TMP/sahook.sh"
out=$(STUB_SHOW_HOOK="$TMP/sahook.sh" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "a detach landing after the re-read exits non-zero"
eq "$(bstatus SA)" "open" "…the anchor is not closed"
eq "$(meta SA merged_sha)" "<absent>" "…nothing is recorded on it"
has "$out" "record failed" "…and the refusal is reported, not swallowed"

echo "# closed-unmerged and draft PRs are pr-facts' business"
store "[$(anchor S5 74)]"
printf '%s' "$(prview 74 CLOSED CLEAN)" > "$GH_DIR/pr_view_74.json"
out=$("$SUT" 2>&1)
has "$out" "1 skipped" "a closed-unmerged PR is skipped"
eq "$(bstatus S5)" "open" "…and nothing is recorded for it"
store "[$(anchor S6 75)]"
printf '%s' "$(prview 75 OPEN CLEAN)" | jq -c '.isDraft = true' > "$GH_DIR/pr_view_75.json"
out=$("$SUT" 2>&1)
has "$out" "1 skipped" "a draft PR is skipped"

echo "# empty/absent check_set holds (empty is never the 'none' opt-out)"
store '[{"id":"E1","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"80","pr_url":"https://github.com/zook/gc-toolkit/pull/80","branch":"polecat/x80","merged_target":"main"}}]'
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
approved 80
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "an anchor with no check_set holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged ungated"
store '[{"id":"E2","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"81","pr_url":"https://github.com/zook/gc-toolkit/pull/81","branch":"polecat/x81","merged_target":"main","check_set":" , "}}]'
printf '%s' "$(prview 81 OPEN CLEAN)" > "$GH_DIR/pr_view_81.json"
approved 81
out=$("$SUT" 2>&1)
has "$out" "no normalized check_set" "a whitespace-only check_set holds too"
store '[{"id":"E3","status":"open","assignee":"rig/refinery","notes":"","title":"t","metadata":{"merge_result":"pull_request","pr_number":"82","pr_url":"https://github.com/zook/gc-toolkit/pull/82","branch":"polecat/x82","merged_target":"main","check_set":"none"}}]'
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
approved 82
out=$("$SUT" 2>&1)
has "$out" "merged + recorded E3" "the explicit 'none' sentinel still opts out"

echo "# empty mergeCommit read never records an empty merged_sha"
store "[$(anchor V1 61), $(rev V1)]"
printf '%s' "$(prview 61 OPEN CLEAN)" | jq -c 'del(.mergeCommit)' > "$GH_DIR/pr_view_61.json"
approved 61
out=$("$SUT" 2>&1); rc=$?
eq "$rc" 0 "the pass still exits 0 (the merge itself landed)"
has "$out" "recording merged_sha=unverified:PR#61" "the degraded record is loud"
eq "$(meta V1 merged_sha)" "unverified:PR#61" "merged_sha is never empty"
eq "$(bstatus V1)" "closed" "the anchor still closed"

echo '# a recorded commented posture holds the merge'
store "[$(anchor C1 70 ',"pr_posture":"commented@sha-70"')]"
printf '%s' "$(prview 70 OPEN CLEAN)" > "$GH_DIR/pr_view_70.json"
approved 70
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "carries review comments nothing has answered (commented@sha-70); merge held" "the posture read off the anchor holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 70" "…and nothing merged"
hasnt "$(cat "$STUB_GH_LOG")" "pulls/70/comments" "…without merge.sh asking GitHub anything about it"
eq "$(bstatus C1)" "open" "the anchor was not closed"

echo "# …a posture pinned to an OLD head still holds — a comment survives a head move"
store "[$(anchor C2 71 ',"pr_posture":"commented@sha-STALE"')]"
printf '%s' "$(prview 71 OPEN CLEAN)" > "$GH_DIR/pr_view_71.json"
approved 71
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "commented@sha-STALE); merge held" "the hold is not head-matched"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 71" "…and nothing merged"

echo "# …every other posture, and an ABSENT one, merge as before"
store "[$(anchor C3 72 ',"pr_posture":"approved@sha-72"'), $(rev C3)]"
printf '%s' "$(prview 72 OPEN CLEAN)" > "$GH_DIR/pr_view_72.json"
approved 72
out=$("$SUT" 2>&1)
has "$out" "merged + recorded C3" "an approved posture does not hold"
store "[$(anchor C4 73), $(rev C4)]"
printf '%s' "$(prview 73 OPEN CLEAN)" > "$GH_DIR/pr_view_73.json"
approved 73
out=$("$SUT" 2>&1)
has "$out" "merged + recorded C4" "an absent posture is a fact not yet recorded, never a hold"

echo "# …a comment landing mid-pass is caught by the terminal re-read"
store "[$(anchor C5 74), $(rev C5)]"
printf '%s' "$(prview 74 OPEN CLEAN)" > "$GH_DIR/pr_view_74.json"
approved 74
PHOOK_COUNT="$TMP/phookcount"; : > "$PHOOK_COUNT"
cat > "$TMP/phook.sh" <<HOOK
#!/usr/bin/env bash
# Records the posture on C5 immediately before its SECOND read (the terminal
# re-read): the validation read saw none, so only the re-read can catch it.
[ "\${1:-}" = "C5" ] || exit 0
n=\$(cat "$PHOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$PHOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
  jq -c 'map(if .id == "C5" then .metadata.pr_posture = "commented@sha-74" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/phook.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/phook.sh" "$SUT" 2>&1)
has "$out" "review comments went unanswered after validation; merge held" "the terminal re-read caught the mid-pass comment"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 74" "…and the merge was withheld"
eq "$(bstatus C5)" "open" "the anchor was not closed"

echo "# terminal re-read HOLDS on a real mid-pass write (hook mutates the store)"
store "[$(anchor T2 51), $(rev T2)]"
printf '%s' "$(prview 51 OPEN CLEAN)" > "$GH_DIR/pr_view_51.json"
approved 51
HOOK_COUNT="$TMP/hookcount"; : > "$HOOK_COUNT"
cat > "$TMP/hook.sh" <<HOOK
#!/usr/bin/env bash
# Sets merge_hold on T2 immediately before its SECOND read (the terminal
# re-read) — the validation read saw no hold, so only the re-read can catch it.
[ "\${1:-}" = "T2" ] || exit 0
n=\$(cat "$HOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$HOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
  jq -c 'map(if .id == "T2" then .metadata.merge_hold = "true" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/hook.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/hook.sh" "$SUT" 2>&1)
has "$out" "merge_hold was set after validation; merge held" "the terminal re-read caught the mid-pass hold"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 51" "…and the merge was withheld"
eq "$(bstatus T2)" "open" "the anchor was not closed"

echo "# a signoff_dismissed stamp landing mid-pass does NOT hold the merge"
# The marker records a dismissal; approval is a universal rule no dismissal arms or
# relaxes, so the terminal re-read has nothing to compare it against.
store "[$(anchor T2D 53), $(rev T2D)]"
printf '%s' "$(prview 53 OPEN CLEAN)" > "$GH_DIR/pr_view_53.json"
approved 53
: > "$HOOK_COUNT"
cat > "$TMP/hookd.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "T2D" ] || exit 0
n=\$(cat "$HOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$HOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
  jq -c 'map(if .id == "T2D" then .metadata.signoff_dismissed = "901@sha-53" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/hookd.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/hookd.sh" "$SUT" 2>&1)
hasnt "$out" "signoff_dismissed changed" "a mid-pass dismissal record is no hold reason"
has "$(cat "$STUB_GH_LOG")" "pr merge 53" "…and the approved, green PR merges"

echo "# terminal re-read HOLDS when a lane leaves green mid-pass — the shared lane-state derivation"
# The lane derived green at validation (a backing approve bead); the terminal
# re-read has to catch that SAME lane leaving green between validation and the
# merge, off the shared lane-state derivation the hold uses. The mid-pass write
# reopens the backing review — an in-flight review holds the lane out of green
# ahead of any approval fallback, a lane change no head move would show.
store "[$(anchor T3 52), $(rev T3)]"
printf '%s' "$(prview 52 OPEN CLEAN)" > "$GH_DIR/pr_view_52.json"
approved 52
: > "$HOOK_COUNT"
cat > "$TMP/hook3.sh" <<HOOK
#!/usr/bin/env bash
[ "\${1:-}" = "T3" ] || exit 0
n=\$(cat "$HOOK_COUNT" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$HOOK_COUNT"
if [ "\$n" = 2 ]; then
  tmp=\$(mktemp "${TMPDIR:-/tmp}/gctk-merge-test.XXXXXX")
  jq -c 'map(if .id == "rev-T3" then .status = "open" else . end)' "\$STUB_STORE" > "\$tmp" && mv "\$tmp" "\$STUB_STORE"
fi
HOOK
chmod +x "$TMP/hook3.sh"
: > "$STUB_GH_LOG"
out=$(STUB_SHOW_HOOK="$TMP/hook3.sh" "$SUT" 2>&1)
has "$out" "lane correctness is no longer green; merge held" "the terminal re-read catches the lane leaving green mid-pass"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 52" "…and the merge was withheld"
eq "$(bstatus T3)" "open" "the anchor was not closed"

echo "# generated-artifact freshness at the merge result"
# The arm exists because generated/seed-audit is rendered from the whole source
# tree and committed per branch: a PR carrying a render made at an older base
# overwrites inputs it never saw, and every other gate here is head-keyed, so
# nothing else notices the base moving underneath.
RENDER_LOG="$TMP/render.log"; : > "$RENDER_LOG"
cat > "$SD/render-seed-audit.sh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$RENDER_LOG"
printf '%s\n' "\${STUB_RENDER_OUT:-seed audit is current}"
exit "\${STUB_RENDER_RC:-0}"
STUB
chmod +x "$SD/render-seed-audit.sh"
export STUB_RENDER_RC=0 STUB_RENDER_OUT=""
mkdir -p "$TMP/repo/generated/seed-audit"; printf 'name = "t"\n' > "$TMP/repo/pack.toml"
# The body runs once per arm; S0 is the no-rendered-audit case, so drop any
# INDEX.md a prior arm's S1 rendered before asserting the probe stays idle.
rm -f "$TMP/repo/generated/seed-audit/INDEX.md"
export STUB_TOPLEVEL="$TMP/repo" STUB_FETCHED_HEAD="sha-80"

store "[$(anchor S0 80), $(rev S0)]"
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
approved 80
out=$("$SUT" 2>&1)
has "$out" "merged + recorded S0" "a repository carrying no rendered audit merges"
eq "$(wc -c < "$RENDER_LOG" | tr -d ' ')" "0" "…and the freshness probe never ran"

: > "$TMP/repo/generated/seed-audit/INDEX.md"
store "[$(anchor S1 81), $(rev S1)]"
printf '%s' "$(prview 81 OPEN CLEAN)" > "$GH_DIR/pr_view_81.json"
approved 81
export STUB_FETCHED_HEAD="sha-81"
out=$("$SUT" 2>&1)
has "$out" "merged + recorded S1" "a current merge result merges"
has "$(cat "$RENDER_LOG")" "--check-merge refs/gc-toolkit/merge-gate/base refs/gc-toolkit/merge-gate/head" \
  "…and the question was asked of the merge, in the probe's own ref namespace"

store "[$(anchor S2 82), $(rev S2)]"
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
approved 82
export STUB_FETCHED_HEAD="sha-82" STUB_RENDER_RC=1 STUB_RENDER_OUT="seed audit would be STALE at the merge"
: > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"
out=$("$SUT" 2>&1)
has "$out" "would land a stale generated/seed-audit; merge held" "a stale merge result holds"
has "$out" "seed audit would be STALE at the merge" "…quoting what the renderer found"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"
has "$(cat "$STUB_ESC_LOG")" "--key seed-audit-merge-gate.82" "…and one visit carries the situation to a human"
has "$(cat "$STUB_ESC_LOG")" "PR#82 would land a stale generated/seed-audit; the merge is held." \
  "…whose first line is a headline, since escalate.sh titles the visit from it"
has "$(cat "$STUB_ESC_LOG")" "seed audit would be STALE at the merge" "…carrying the renderer's own diagnosis"
eq "$(bstatus S2)" "open" "the anchor stays open"

store "[$(anchor S3 83), $(rev S3)]"
printf '%s' "$(prview 83 OPEN CLEAN)" > "$GH_DIR/pr_view_83.json"
approved 83
export STUB_FETCHED_HEAD="sha-83" STUB_RENDER_RC=2 STUB_RENDER_OUT="cannot tell"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "freshness could not be determined; merge held" "an unanswerable probe holds rather than passing"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

store "[$(anchor S4 84), $(rev S4)]"
printf '%s' "$(prview 84 OPEN CLEAN)" > "$GH_DIR/pr_view_84.json"
approved 84
export STUB_RENDER_RC=0 STUB_FETCH_RC=1
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "could not fetch 'main' and 'polecat/x84'" "an unreachable remote holds"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

store "[$(anchor S5 85), $(rev S5)]"
printf '%s' "$(prview 85 OPEN CLEAN)" > "$GH_DIR/pr_view_85.json"
approved 85
export STUB_FETCH_RC="" STUB_FETCHED_HEAD="sha-moved"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "head moved during the freshness probe (fetched 'sha-moved', validated 'sha-85')" \
  "a head that moved under the probe holds rather than answering about the wrong tree"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"
export STUB_TOPLEVEL="" STUB_FETCHED_HEAD=""

# --- the machine axis (lifecycle/lifecycle.toml [machine_axis]) ------------------
# Every hold above already decides what the cadence can do next and spends the
# answer on a log line. These assert that the answer is kept, so a reader learns
# whether an anchor is moving without re-implementing these predicates.
machine() { printf '%s' "$(meta "$1" pr.machine)"; }
pinned()  { local v; v="$(machine "$1")"; case "$v" in *@*@*) printf '%s' "${v%@*}" ;; *) printf '%s' "$v" ;; esac; }
reason()  { printf '%s' "$(meta "$1" pr.machine_reason)"; }

echo "# machine axis: a standing veto in the settled tail is settled — the operator re-reviews"
# Checks green at the live head, a non-city CHANGES_REQUESTED standing, and every
# rework child it filed already closed. GitHub keeps the veto standing across
# pushes and the city never dismisses it, so with nothing in flight the anchor is
# the operator's to clear by re-reviewing. The machine axis records `settled`,
# whose owed rule reads the standing changes_requested off the posture axis.
store "[$(anchor V1 80), $(rev V1),
        {\"id\":\"rw-v1a\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-a\"}},
        {\"id\":\"rw-v1b\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-b\"}},
        {\"id\":\"rw-v1c\",\"status\":\"closed\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"source_review_bead\":\"rev-c\"}}]"
printf 'rw-v1a|blocks|V1\nrw-v1b|blocks|V1\nrw-v1c|blocks|V1\n' > "$STUB_DEPS"
printf '%s' "$(prview 80 OPEN CLEAN)" > "$GH_DIR/pr_view_80.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_80.json"
out=$("$SUT" 2>&1)
has "$out" "standing CHANGES_REQUESTED" "the veto still holds"
has "$out" "run dry" "the settled-tail hold names why the row is the operator's"
eq "$(pinned V1)" "settled@sha-80" "a standing veto with nothing in flight records settled, whatever the past rework-child count"
case "$(machine V1)" in
  *@*@20[0-9][0-9]-*Z) ok "…dated at the turn it began" ;;
  *) bad "no @<since> component: '$(machine V1)'" ;;
esac

echo "# machine axis: a standing veto WITH a fix unit in flight stays progressing"
# The same veto, but an OPEN pool-routed rework child is still moving the anchor.
# The in-flight arm records `progressing` before the veto arm runs, so the row is
# the city's move until the fix lands, and only then does the settled tail begin.
store "[$(anchor V2 88), $(rev V2),
        {\"id\":\"rw-v2\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"rig/gc-toolkit.polecat\"}}]"
printf 'rw-v2|blocks|V2\n' > "$STUB_DEPS"
printf '%s' "$(prview 88 OPEN CLEAN)" > "$GH_DIR/pr_view_88.json"
printf '[{"user":{"login":"human2"},"state":"CHANGES_REQUESTED","commit_id":"sha-old","submitted_at":"2026-08-19T00:00:00Z","id":1}]' > "$GH_DIR/reviews_88.json"
out=$("$SUT" 2>&1)
eq "$(pinned V2)" "progressing@sha-88" "a veto with an open fix unit in flight stays progressing"

echo "# a lane short of green is progressing; the cap's park is the wedge"
# The shared predicate (also gate-ensure.sh's): merge_hold is the literal
# string "signoff_cap" AND signoff_cap is non-empty. signoff.sh writes that
# literal for its round-cap park; an operator's own hold writes merge_hold=true.
store "[$(anchor V3 82),
        $(anchor V4 83 ',"merge_hold":"signoff_cap","signoff_cap":"correctness","gc.routed_to":"human"')]"
: > "$STUB_DEPS"
printf '%s' "$(prview 82 OPEN CLEAN)" > "$GH_DIR/pr_view_82.json"
printf '%s' "$(prview 83 OPEN CLEAN)" > "$GH_DIR/pr_view_83.json"
# No approver: a GitHub approval would back V3's bead-less lane green through the
# fallback, hiding the lane-short-of-green state this records.
echo '[]' > "$GH_DIR/reviews_82.json"
approved 83
out=$("$SUT" 2>&1)
eq "$(pinned V3)" "progressing@sha-82" "a lane short of green is a check a review is due to raise"
eq "$(pinned V4)" "wedged-exception@sha-83" "merge_hold=signoff_cap with signoff_cap beside it is the convergence cap's wedge"

# An operator's own hold carries no signoff_cap, and the board must not read it
# as a wedge no automated actor will lift.
echo "# an operator hold with no cap stamp records no wedge"
store "[$(anchor V4b 90 ',"merge_hold":"true"')]"
printf '%s' "$(prview 90 OPEN CLEAN)" > "$GH_DIR/pr_view_90.json"
approved 90
out=$("$SUT" 2>&1)
has "$out" "merge_hold set (operator gate)" "the hold holds the merge"
eq "$(pinned V4b)" "<absent>" "…and nothing records it as the cap's wedge"

# An operator's own hold (merge_hold=true, not the literal "signoff_cap") is
# not the cap's wedge, even beside a signoff_cap value orphaned by an earlier
# park the operator has since taken over.
echo "# an operator hold beside a STALE orphan signoff_cap is not the cap's wedge"
store "[$(anchor V4c 91 ',"merge_hold":"true","signoff_cap":"correctness"')]"
printf '%s' "$(prview 91 OPEN CLEAN)" > "$GH_DIR/pr_view_91.json"
approved 91
out=$("$SUT" 2>&1)
has "$out" "merge_hold set (operator gate)" "the hold still holds the merge"
eq "$(pinned V4c)" "<absent>" "…but the orphaned signoff_cap does not make it the cap's wedge"

echo "# checks green and waiting on a person: settled, not wedged"
store "[$(anchor V5 84), $(rev V5)]"
printf '%s' "$(prview 84 OPEN CLEAN)" > "$GH_DIR/pr_view_84.json"
# Correctness is green (local backing), so the only thing left is the universal
# approval: no approver here, so the cadence settles waiting on a person.
echo '[]' > "$GH_DIR/reviews_84.json"
out=$("$SUT" 2>&1)
has "$out" "no external APPROVED review" "the approval hold fires"
eq "$(pinned V5)" "settled@sha-84" "the cadence is done; the pull request waits on an approval"

echo "# recording a verdict moves no route"
store "[$(anchor V8 87 ',"merge_hold":"signoff_cap","signoff_cap":"correctness","gc.routed_to":"human"')]"
: > "$STUB_DEPS"
printf '%s' "$(prview 87 OPEN CLEAN)" > "$GH_DIR/pr_view_87.json"
approved 87
out=$("$SUT" 2>&1)
eq "$(pinned V8)" "wedged-exception@sha-87" "the verdict is recorded"
eq "$(meta V8 'gc.routed_to')" "human" "…and the anchor keeps the park route the cap gave it"

echo "# an open blocker is progressing only when a POOL is behind it"
store "[$(anchor V6 85), $(rev V6),
        {\"id\":\"rw-v6\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"rig/gc-toolkit.polecat\"}},
        $(anchor V7 86), $(rev V7),
        {\"id\":\"dm-v7\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"human\"}}]"
printf 'rw-v6|blocks|V6\ndm-v7|blocks|V7\n' > "$STUB_DEPS"
printf '%s' "$(prview 85 OPEN CLEAN)" > "$GH_DIR/pr_view_85.json"
printf '%s' "$(prview 86 OPEN CLEAN)" > "$GH_DIR/pr_view_86.json"
approved 85
approved 86
out=$("$SUT" 2>&1)
eq "$(pinned V6)" "progressing@sha-85" "a pool-routed rework child is an actor that will act"
# The demand bead that makes an anchor `asking` blocks it the same way and has
# no automated actor behind it, so it must not read as the machine working.
eq "$(machine V7)" "<absent>" "a demand bead blocking the anchor is not the machine progressing"

# A hold no automated actor will clear, and no review verdict is owed on, records
# `blocked` with its cause — distinct from settled, so the board shows it as
# needs-attention rather than folding it into the awaiting-review tail.
echo "# an UNROUTED blocker no pool will claim records blocked, naming the holder"
# An unrouted rework husk vetoes the merge, but no pool will claim it (unlike V6)
# and no human route makes it an `asking` demand (unlike V7). It is neither
# progressing nor silence — record blocked so the board stops reading it as
# awaiting-review.
store "[$(anchor BK1 92), $(rev BK1),
        {\"id\":\"rw-bk1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{}}]"
printf 'rw-bk1|blocks|BK1\n' > "$STUB_DEPS"
printf '%s' "$(prview 92 OPEN CLEAN)" > "$GH_DIR/pr_view_92.json"
approved 92
out=$("$SUT" 2>&1)
eq "$(pinned BK1)" "blocked@sha-92" "an unrouted blocker no automated actor will clear records blocked, not silence"
has "$(reason BK1)" "rw-bk1" "…and the reason names the blocking bead"

echo "# a BLOCKED PR held by an unresolved review thread records blocked with the cause"
store "[$(anchor BK2 93), $(rev BK2)]"
: > "$STUB_DEPS"
printf '%s' "$(prview 93 OPEN BLOCKED)" > "$GH_DIR/pr_view_93.json"
approved 93
echo '{"threads":[{"id":"t1","isResolved":false}]}' > "$GH_DIR/threads_93.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
eq "$(pinned BK2)" "blocked@sha-93" "an unresolved required review thread is a blocked hold, not settled"
has "$(reason BK2)" "unresolved review thread" "…and the reason names the thread"

echo "# a BLOCKED PR merely awaiting an approving review stays settled (awaiting-review)"
store "[$(anchor BK3 94), $(rev BK3)]"
printf '%s' "$(prview 94 OPEN BLOCKED)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_94.json"
approved 94
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
eq "$(pinned BK3)" "settled@sha-94" "awaiting an approving review is the review wait, not a block"
eq "$(reason BK3)" "<absent>" "…and no blocked reason lingers on a settled row"

echo "# a base gone BEHIND records blocked; the branch must be brought current"
store "[$(anchor BK4 95), $(rev BK4)]"
: > "$STUB_DEPS"
printf '%s' "$(prview 95 OPEN BEHIND)" > "$GH_DIR/pr_view_95.json"
approved 95
out=$("$SUT" 2>&1)
eq "$(pinned BK4)" "blocked@sha-95" "a base gone BEHIND is a blocked hold, not settled"
has "$(reason BK4)" "moved ahead" "…and the reason says to bring the branch current"

# The conflicting-after-approval wedge: checks green, nothing in flight, but the
# branch conflicts with the base. No review verdict brings it current, so it is
# the operator's (or the merge-in cadence's), not the awaiting-review tail —
# record blocked, not settled, so the board stops reading it as a merge in
# progress. This is the state defect #911 masked for ~12h as "working".
echo "# a branch gone CONFLICTING (DIRTY) with nothing in flight records blocked, not settled"
store "[$(anchor BK5 97), $(rev BK5)]"
: > "$STUB_DEPS"
printf '%s' "$(prview 97 OPEN DIRTY)" > "$GH_DIR/pr_view_97.json"
approved 97
out=$("$SUT" 2>&1)
eq "$(pinned BK5)" "blocked@sha-97" "a conflicting branch with nothing in flight is a blocked hold, not settled"
has "$(reason BK5)" "conflicts" "…and the reason names the conflict and says to bring the branch current"

# pr-facts.sh files the merge-in rework; once it is in flight the in-flight arm
# records progressing BEFORE the DIRTY switch is reached, so "working" stays
# correct exactly while a rework is moving the branch.
echo "# …but a conflicting branch WITH a pool-routed merge-in in flight stays progressing, not blocked"
store "[$(anchor BK6 99), $(rev BK6),
        {\"id\":\"rw-bk6\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"gc.routed_to\":\"rig/gc-toolkit.polecat\",\"task_kind\":\"rework\",\"anchor_bead\":\"BK6\",\"branch\":\"polecat/x99\"}}]"
printf 'rw-bk6|blocks|BK6\n' > "$STUB_DEPS"
printf '%s' "$(prview 99 OPEN DIRTY)" > "$GH_DIR/pr_view_99.json"
approved 99
out=$("$SUT" 2>&1)
eq "$(pinned BK6)" "progressing@sha-99" "a conflicting branch with a pool-routed merge-in in flight is the city's move, not a wedge"
: > "$STUB_DEPS"
rm -f "$GH_DIR/rules_main.json"

# The reads below fail CLOSED: a read that stopped partway is unreadable as a
# whole, never the part that decoded. Each fixture is a pass the partial view
# would have merged or misfiled.

echo "# a reviews stream that stops decoding partway is unreadable, never a partial history"
# --paginate hands back two good rows and a third cut short. The stub prints a
# string element raw, so the third row arrives as half a JSON object.
store "[$(anchor RV1 120), $(rev RV1)]"
printf '%s' "$(prview 120 OPEN CLEAN)" > "$GH_DIR/pr_view_120.json"
jq -cn '[ {user:{login:"human1"},state:"APPROVED",commit_id:"sha-120",submitted_at:"2026-01-01T00:00:00Z",id:1},
          {user:{login:"human2"},state:"COMMENTED",commit_id:"sha-120",submitted_at:"2026-01-02T00:00:00Z",id:2},
          ({user:{login:"human3"},state:"CHANGES_REQUESTED",commit_id:"sha-120",submitted_at:"2026-01-03T00:00:00Z",id:3} | tojson | .[0:50]) ]' \
  > "$GH_DIR/reviews_120.json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#120 reviews history unreadable; merge held" "a reviews stream cut short is an unreadable history"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 120" "…and the PR is not squashed on the rows that decoded"

echo "# an enumeration that exits non-zero after printing [] fails the pass loudly"
store "[$(anchor EN1 121), $(rev EN1)]"
printf '%s' "$(prview 121 OPEN CLEAN)" > "$GH_DIR/pr_view_121.json"
approved 121
: > "$STUB_GH_LOG"
out=$(STUB_LIST_PARTIAL="merge_result=pull_request" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "an enumeration that exited non-zero fails the pass"
has "$out" "could not enumerate gating anchors" "…naming the unreadable enumeration"
hasnt "$out" "no gating anchors" "…never reporting the empty array as no anchors"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a referencing-bead read that exits non-zero after printing [] holds, never reads as no holder"
# The rework child names the PR only by pr_number, so the by_pr read is the one
# that would have found it.
store "[$(anchor BP1 122), $(rev BP1),
        {\"id\":\"rw-bp1\",\"status\":\"open\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{\"task_kind\":\"rework\",\"pr_number\":\"122\",\"pr_url\":\"https://github.com/zook/gc-toolkit/pull/122\"}}]"
printf '%s' "$(prview 122 OPEN CLEAN)" > "$GH_DIR/pr_view_122.json"
approved 122
: > "$STUB_GH_LOG"
out=$(STUB_LIST_PARTIAL="pr_number=" "$SUT" 2>&1)
has "$out" "PR#122 referencing-bead read failed; merge held" "a failed by_pr read holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and the in-flight rework it would have found is not merged past"

echo "# a dependency probe that exits non-zero after printing [] holds, never reads as no blockers"
store "[$(anchor DE1 128), $(rev DE1)]"
printf '%s' "$(prview 128 OPEN CLEAN)" > "$GH_DIR/pr_view_128.json"
approved 128
: > "$STUB_GH_LOG"
out=$(STUB_DEP_PARTIAL=1 "$SUT" 2>&1)
has "$out" "PR#128 dependency probe unreadable; merge held" "a failed dependency probe holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

# The same three reads at exit 0, with unreadable bytes after the array. The
# array gate fails the whole stream, so the rows ahead of the bytes are no
# answer. Each PR is approved and green, so a hold can come only from a read
# that refused the stream, and each case names the read that must.
echo "# an enumeration with unreadable bytes after its array fails the pass loudly"
store "[$(anchor TR1 130), $(rev TR1)]"
printf '%s' "$(prview 130 OPEN CLEAN)" > "$GH_DIR/pr_view_130.json"
approved 130
: > "$STUB_GH_LOG"
out=$(STUB_LIST_TRAILING="merge_result=pull_request" "$SUT" 2>&1); rc=$?
eq "$rc" 1 "an enumeration with bytes after its array fails the pass"
has "$out" "could not enumerate gating anchors" "…naming the unreadable enumeration"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a referencing-bead read with unreadable bytes after its array holds"
store "[$(anchor TR2 131), $(rev TR2)]"
printf '%s' "$(prview 131 OPEN CLEAN)" > "$GH_DIR/pr_view_131.json"
approved 131
: > "$STUB_GH_LOG"
out=$(STUB_LIST_TRAILING="pr_number=" "$SUT" 2>&1)
has "$out" "PR#131 referencing-bead read failed; merge held" "a by_pr read with bytes after its array holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a dependency probe with unreadable bytes after its array holds"
store "[$(anchor TR3 132), $(rev TR3)]"
printf '%s' "$(prview 132 OPEN CLEAN)" > "$GH_DIR/pr_view_132.json"
approved 132
: > "$STUB_GH_LOG"
out=$(STUB_DEP_TRAILING=1 "$SUT" 2>&1)
has "$out" "PR#132 dependency probe unreadable; merge held" "a dependency probe with bytes after its array holds the merge"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a review-thread read whose later page will not decode is unreadable, never a zero count"
# Page one decodes with no unresolved thread; page two is garbled. Read as a
# zero count, the BLOCKED PR would fall through to the approval wait (settled).
store "[$(anchor TH1 123), $(rev TH1)]"
printf '%s' "$(prview 123 OPEN BLOCKED)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_123.json"
approved 123
echo '{"threads":[]}' > "$GH_DIR/threads_123.json"
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$(STUB_GQL_THREADS_TAIL='{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNext' "$SUT" 2>&1)
eq "$(pinned TH1)" "blocked@sha-123" "a thread read cut short is a blocked hold, not the approval wait"
has "$(reason TH1)" "could not be read" "…and the reason says the threads could not be read"
rm -f "$GH_DIR/rules_main.json"

echo "# with the reconcile cache on, the pass reads the anchor enumeration once, not once per anchor"
store "[$(anchor DP1 124), $(rev DP1), $(anchor DP2 125), $(rev DP2)]"
for n in 124 125; do
  printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"
  approved "$n"
done
rm -rf "$TMP/bdcache"; mkdir -p "$TMP/bdcache"
: > "$STUB_GC_LOG"
out=$(GC_RECONCILE_BD_CACHE="$TMP/bdcache" "$SUT" 2>&1)
has "$out" "2 merged" "both anchors merge"
eq "$(grep -c -- '--metadata-field merge_result=pull_request' "$STUB_GC_LOG")" "1" "…on ONE read of the anchor enumeration, whatever the anchor count"
rm -rf "$TMP/bdcache"

echo "# isCrossRepository: null reaches the cross-repo gate as cross=null; only an absent key is unreadable"
store "[$(anchor XR1 126), $(rev XR1)]"
printf '%s' "$(prview 126 OPEN CLEAN)" | jq -c '.isCrossRepository = null' > "$GH_DIR/pr_view_126.json"
approved 126
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#126 is opened from 'zook/gc-toolkit' (cross=null), not this repository's own branch; merge held" "a null isCrossRepository is reported by the cross-repo gate"
hasnt "$out" "PR#126 head identity unreadable" "…not as an unreadable head identity"
printf '%s' "$(prview 126 OPEN CLEAN)" | jq -c 'del(.isCrossRepository)' > "$GH_DIR/pr_view_126.json"
out=$("$SUT" 2>&1)
has "$out" "PR#126 head identity unreadable; merge held" "an ABSENT isCrossRepository is the unreadable head identity"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and neither shape merges"

echo "# a referencing bead whose status is the empty string is not live; a null status is open"
# jq's `.status // "open"` substitutes only for null or absent.
store "[$(anchor ES1 127), $(rev ES1), {\"id\":\"blk-es1\",\"status\":\"\",\"assignee\":\"\",\"notes\":\"\",\"metadata\":{}}]"
printf 'blk-es1|blocks|ES1\n' > "$STUB_DEPS"
printf '%s' "$(prview 127 OPEN CLEAN)" > "$GH_DIR/pr_view_127.json"
approved 127
out=$("$SUT" 2>&1)
hasnt "$out" "PR#127 held by" "an empty-status blocker holds nothing"
has "$out" "merged + recorded ES1" "…and the merge proceeds"
store "[$(anchor ES2 127), $(rev ES2), {\"id\":\"blk-es2\",\"status\":null,\"assignee\":\"\",\"notes\":\"\",\"metadata\":{}}]"
printf 'blk-es2|blocks|ES2\n' > "$STUB_DEPS"
out=$("$SUT" 2>&1)
has "$out" "PR#127 held by unclosed rework/review bead blk-es2 (open); merge held" "the control: a null-status blocker reads as open and holds"
: > "$STUB_DEPS"

# GitHub computes mergeability lazily. A merge moves the base under every sibling,
# and each sibling's first read after it answers UNKNOWN while the computation that
# read started runs. pr_view_<n>.queue/<fields>/ scripts the reads of one field
# set in order; the fixture is the computed answer every later read gets.
unset MERGE_STATE_REREADS MERGE_STATE_REREAD_SECS
# The pinned read's field set, from bd-lib.sh, where merge.sh takes it. The queue
# is keyed by it, so a queued answer goes to the pinned read or a re-read of it
# and never to a read of another field set.
# shellcheck source=bd-lib.sh
PR_FIELDS=$(. "$HERE/bd-lib.sh" && printf '%s' "$PR_FIELDS")
queue_answer() { # num seq answer: read <seq> of the pinned field set gets <answer>
  mkdir -p "$GH_DIR/pr_view_$1.queue/$PR_FIELDS"
  printf '%s' "$3" > "$GH_DIR/pr_view_$1.queue/$PR_FIELDS/$2.json"
}
unknown_first() { # num
  queue_answer "$1" 01 "$(prview "$1" OPEN UNKNOWN)"
}
pinned_reads() { # num: reads of the pinned field set, re-reads included
  grep -c "^pr view $1 --repo github.com/zook/gc-toolkit --json $PR_FIELDS\$" "$STUB_GH_LOG" || true
}

echo "# one pass lands every approved clean PR, though each sibling first reads UNKNOWN after a merge"
store "[$(anchor RR1 150), $(rev RR1), $(anchor RR2 151), $(rev RR2), $(anchor RR3 152), $(rev RR3)]"
: > "$STUB_DEPS"
for n in 150 151 152; do
  printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"
  approved "$n"
done
unknown_first 151; unknown_first 152
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "merge: 3 merged," "the pass lands all three, not only the first"
for a in RR1 RR2 RR3; do eq "$(bstatus "$a")" "closed" "$a closed on its merge"; done
has "$out" "PR#151 answered UNKNOWN on the pinned read and CLEAN on re-read 1" "a sibling's computed CLEAN comes from the re-read"
eq "$(pinned_reads 151)" "2" "the first re-read finds the state computed and the sibling reads no further"
eq "$(pinned_reads 150)" "1" "a PR whose pinned read is already computed is not re-read"

echo "# an UNKNOWN that stays UNKNOWN is read until the pass's budget is spent, then held settled"
store "[$(anchor RR4 153), $(rev RR4)]"
printf '%s' "$(prview 153 OPEN UNKNOWN)" > "$GH_DIR/pr_view_153.json"
approved 153
# A sleep that records its argument and returns at once, so the suite pins the
# wait schedule without spending it.
mkdir -p "$TMP/sleepbin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$TMP/sleep.log" > "$TMP/sleepbin/sleep"
chmod +x "$TMP/sleepbin/sleep"; : > "$TMP/sleep.log"
: > "$STUB_GH_LOG"
out=$(PATH="$TMP/sleepbin:$PATH" "$SUT" 2>&1)
has "$out" "not mergeable yet (mergeStateStatus='UNKNOWN' after 3 re-read(s); the pass's re-read budget is spent); merge held" "a state still UNKNOWN when the budget is spent holds for the pass"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"
eq "$(pinned RR4)" "settled@sha-153" "…and records settled, like any unready state that owes a person nothing"
eq "$(pinned_reads 153)" "4" "the pinned read plus the default three re-reads"
eq "$(tr '\n' ' ' < "$TMP/sleep.log")" "5 5 " "the first re-read goes out at once and each later one waits the default 5s"

echo "# the budget belongs to the pass: once one PR spends it, a later UNKNOWN is not re-read"
# A mergeability computation stalled across the repository leaves every candidate
# UNKNOWN. The pass spends its three re-reads on the first and holds the rest on
# their pinned reads, so a stall costs the pass one PR's re-reads, not one per PR.
store "[$(anchor RR9 158), $(rev RR9), $(anchor RR10 159), $(rev RR10)]"
for n in 158 159; do
  printf '%s' "$(prview "$n" OPEN UNKNOWN)" > "$GH_DIR/pr_view_$n.json"
  approved "$n"
done
: > "$TMP/sleep.log"; : > "$STUB_GH_LOG"
out=$(PATH="$TMP/sleepbin:$PATH" "$SUT" 2>&1)
has "$out" "PR#158 not mergeable yet (mergeStateStatus='UNKNOWN' after 3 re-read(s); the pass's re-read budget is spent); merge held" "the first UNKNOWN spends the pass's three re-reads"
eq "$(pinned_reads 158)" "4" "…in its pinned read and three re-reads"
has "$out" "PR#159 not mergeable yet (mergeStateStatus='UNKNOWN'; not re-read, the pass's re-read budget is spent); merge held" "the next UNKNOWN holds without a re-read"
eq "$(pinned_reads 159)" "1" "…so its pinned read is its only read"
eq "$(pinned RR10)" "settled@sha-159" "…and records settled, as an UNKNOWN held on its pinned read does"
eq "$(tr '\n' ' ' < "$TMP/sleep.log")" "5 5 " "the pass waits only between the first PR's re-reads"

echo "# a re-read that answers a computed state spends none of the budget"
# Two siblings each answer UNKNOWN once and CLEAN on their first re-read. With a
# budget of one, both land only because a deciding re-read costs nothing.
store "[$(anchor RR11 160), $(rev RR11), $(anchor RR12 161), $(rev RR12)]"
for n in 160 161; do
  printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"
  unknown_first "$n"
  approved "$n"
done
out=$(MERGE_STATE_REREADS=1 "$SUT" 2>&1)
has "$out" "merge: 2 merged," "with a budget of one, both PRs whose first re-read computed land"
has "$out" "PR#161 answered UNKNOWN on the pinned read and CLEAN on re-read 1" "…the second re-read after the first one decided"

echo "# MERGE_STATE_REREADS=0 turns the re-read off"
store "[$(anchor RR5 154), $(rev RR5)]"
printf '%s' "$(prview 154 OPEN CLEAN)" > "$GH_DIR/pr_view_154.json"
unknown_first 154
approved 154
: > "$STUB_GH_LOG"
out=$(MERGE_STATE_REREADS=0 "$SUT" 2>&1)
has "$out" "not mergeable yet (mergeStateStatus='UNKNOWN'); merge held" "with no re-reads the pinned UNKNOWN holds for the pass"
eq "$(pinned_reads 154)" "1" "…on the pinned read alone"

echo "# a re-read that fails holds like a failed pinned read, not as GitHub still computing"
# An empty answer is gh failing, and an unparseable one is no answer either.
# Neither says anything about the merge state, so neither is recorded.
store "[$(anchor RR13 162), $(rev RR13), $(anchor RR14 163), $(rev RR14)]"
for n in 162 163; do
  printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"
  unknown_first "$n"
  approved "$n"
done
queue_answer 162 02 ""
queue_answer 163 02 "gh: not json"
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#162 view failed on re-read 1 of its UNKNOWN merge state; merge held (anchor RR13, retry next pass)" "an empty re-read holds as a failed view"
has "$out" "PR#163 view failed on re-read 1 of its UNKNOWN merge state; merge held (anchor RR14, retry next pass)" "…and so does an unparseable one"
hasnt "$out" "not mergeable yet" "…neither is reported as an UNKNOWN merge state"
eq "$(machine RR13)" "<absent>" "…the failed read records nothing"
eq "$(machine RR14)" "<absent>" "…for either PR"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged"

echo "# a re-read that finds the head moved holds, naming what changed"
store "[$(anchor RR6 155), $(rev RR6)]"
printf '%s' "$(prview 155 OPEN CLEAN)" | jq -c '.headRefOid = "sha-155-pushed"' > "$GH_DIR/pr_view_155.json"
unknown_first 155
# Approved at the pinned head, so the approval gate passes it and only the
# re-read sees the push.
approved 155
: > "$STUB_GH_LOG"
out=$("$SUT" 2>&1)
has "$out" "PR#155 changed between the pinned read and re-read 1 of its UNKNOWN merge state (headRefOid 'sha-155' -> 'sha-155-pushed'); merge held" "a head that moved between the reads holds, and the log names both heads"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge" "…and nothing merged on a head the gates never validated"

echo "# a re-read that computes DIRTY keeps DIRTY's handling"
store "[$(anchor RR7 156), $(rev RR7)]"
printf '%s' "$(prview 156 OPEN DIRTY)" > "$GH_DIR/pr_view_156.json"
unknown_first 156
approved 156
out=$("$SUT" 2>&1)
eq "$(pinned RR7)" "blocked@sha-156" "the computed DIRTY records blocked, as a pinned DIRTY does"
has "$(reason RR7)" "conflicts" "…and the reason names the conflict"

echo "# a re-read that computes BLOCKED names its cause from the re-read, not the pinned read"
store "[$(anchor RR8 157), $(rev RR8)]"
printf '%s' "$(prview 157 OPEN BLOCKED)" | jq -c '.reviewDecision = "REVIEW_REQUIRED"' > "$GH_DIR/pr_view_157.json"
queue_answer 157 01 "$(prview 157 OPEN UNKNOWN | jq -c '.reviewDecision = "APPROVED"')"
approved 157
printf '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"required_approving_review_count":1}}]' > "$GH_DIR/rules_main.json"
out=$("$SUT" 2>&1)
eq "$(pinned RR8)" "settled@sha-157" "the re-read's REVIEW_REQUIRED makes it the approval wait, not a rule nobody named"
# The approval gate records settled too, so the line is what proves the BLOCKED
# arm judged the re-read.
has "$out" "PR#157 is BLOCKED by branch protection: waiting on an approving review (1 required, reviewDecision='REVIEW_REQUIRED')" "…named at the BLOCKED arm, past the approval gate"
rm -f "$GH_DIR/rules_main.json"

echo "# landing first: a PR that can land, or has left the open list, is visited first and never paced"
# PC9's PR is approved and CLEAN, so it can land this pass; PD5's PR is not in
# the open list (it merged out of band and owes its record). PB1 and PB2's PRs
# carry no approval, so a visit there only refreshes a verdict. The ids sort the
# two groups the other way round, so the order the visits take is the order the
# arm chose. A deadline of epoch 1 has always passed, so exactly one of the
# paced anchors is visited per pass.
store "[$(anchor PB1 251), $(anchor PB2 252), $(anchor PC9 261), $(rev PC9), $(anchor PD5 270)]"
printf '%s' "$(prview 251 OPEN BLOCKED)" > "$GH_DIR/pr_view_251.json"
printf '%s' "$(prview 252 OPEN BLOCKED)" > "$GH_DIR/pr_view_252.json"
printf '%s' "$(prview 261 OPEN CLEAN)" > "$GH_DIR/pr_view_261.json"
printf '%s' "$(prview 270 MERGED CLEAN)" > "$GH_DIR/pr_view_270.json"
for n in 251 252; do echo '[]' > "$GH_DIR/reviews_$n.json"; done
approved 261
openprs "$(openpr 251)" "$(openpr 252)" "$(openpr 261 human1:APPROVED)"
MCUR="$TMP/merge.cursor"; rm -f "$MCUR"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1); rc=$?
eq "$rc" 0 "a paced pass exits 0"
eq "$(paced_views)" "261,270,251" "the landing group (approved, then left the open list) is visited before any paced anchor, and one paced anchor follows"
has "$out" "merged + recorded PC9" "the approved PR landed although the deadline had passed"
has "$out" "recovered PD5" "the PR that left the open list got its record although the deadline had passed"
has "$out" "visited 2 landing-first and 1 of 2 other anchors before the deadline; the next pass resumes at PB2" "the pass names its pacing and where the next pass resumes"
eq "$(cat "$MCUR" 2>/dev/null)" "PB1" "the cursor records the paced anchor the pass finished"
has "$(cat "$STUB_GH_LOG")" "pullRequests(states:OPEN" "one GraphQL read lists the open PRs"
hasnt "$(cat "$STUB_GH_LOG")" "pr list" "…and no gh pr list asks GitHub for every open PR's merge state at once"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
eq "$(paced_views)" "252" "the next pass resumes the paced rotation after the cursor"
has "$out" "the next pass resumes at PB1" "…and wraps past the highest id"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline "$(( $(date +%s) + 600 ))" --cursor "$MCUR" 2>&1)
has "$out" "visited 0 landing-first and 2 of 2 other anchors" "a deadline that has not passed visits every paced anchor"
hasnt "$out" "resumes at" "…and names no resume point"

echo "# approval is read from the reviews: an approved PR goes first whatever its merge state reads"
# GitHub leaves reviewDecision empty when the base requires no approving review,
# and reads every open PR's merge state UNKNOWN after a squash moves the base.
# PU3's reviews approve it and the posture arm recorded UNKNOWN at its head, so
# it is visited first; PU1 and PU2 carry no approval and are paced. The list
# read asks for neither field.
store "[$(anchor PU1 291 ',"pr_merge_state":"UNKNOWN@sha-291"'), $(anchor PU2 292 ',"pr_merge_state":"UNKNOWN@sha-292"'), $(anchor PU3 293 ',"pr_merge_state":"UNKNOWN@sha-293"')]"
for n in 291 292 293; do printf '%s' "$(prview "$n" OPEN UNKNOWN)" > "$GH_DIR/pr_view_$n.json"; echo '[]' > "$GH_DIR/reviews_$n.json"; done
openprs "$(openpr 291)" "$(openpr 292)" "$(openpr 293 human1:APPROVED)"
rm -f "$MCUR"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
eq "$(paced_views)" "293,291" "the approved PR is visited first and one unapproved PR follows under the passed deadline"
has "$out" "visited 1 landing-first and 1 of 2 other anchors before the deadline" "…the approved PR counted landing-first, the unapproved ones paced"
gql=$(awk '/api graphql/ { f = 1 } f { print } f && /-f repo=/ { exit }' "$STUB_GH_LOG")
has "$gql" "latestOpinionatedReviews" "the list read asks for each account's latest review"
hasnt "$gql" "reviewDecision" "…not for the review decision"
hasnt "$gql" "mergeStateStatus" "…and not for the merge state"
# The city's own review never approves: the rule that skips it at the gate skips
# it here too.
openprs "$(openpr 291)" "$(openpr 292)" "$(openpr 293 gc-city-bot:APPROVED)"
rm -f "$MCUR"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
has "$out" "visited 0 landing-first and 1 of 3 other anchors" "an approval from the acting login does not put a PR first"

echo "# what the merge holds for sure is paced, not visited first"
# Every PR here is approved, and PH4 is also vetoed by a second reviewer. PH1 to
# PH5 each carry something merge.sh holds on that no per-PR read can change this
# pass: an operator's merge_hold, review comments nothing has answered, a DIRTY
# merge state the posture arm recorded at the live head, the veto, and a draft.
# PH6's DIRTY state was recorded at an older head, PH7 reads CLEAN and PH8
# UNKNOWN, so those three are visited first, and each lands: its approval backs
# its lane, and its live merge state reads CLEAN.
store "[$(anchor PH1 231 ',"merge_hold":"true"'),
        $(anchor PH2 232 ',"pr_posture":"commented@sha-232@2026-10-06T00:00:00Z"'),
        $(anchor PH3 233 ',"pr_merge_state":"DIRTY@sha-233"'),
        $(anchor PH4 234),
        $(anchor PH5 235),
        $(anchor PH6 236 ',"pr_merge_state":"DIRTY@sha-old"'),
        $(anchor PH7 237 ',"pr_merge_state":"CLEAN@sha-237"'),
        $(anchor PH8 238 ',"pr_merge_state":"UNKNOWN@sha-238"')]"
for n in 231 232 233 234 235 236 237 238; do printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"; approved "$n"; done
openprs "$(openpr 231 human1:APPROVED)" "$(openpr 232 human1:APPROVED)" "$(openpr 233 human1:APPROVED)" \
  "$(openpr 234 human1:APPROVED human2:CHANGES_REQUESTED)" "$(openpr 235 human1:APPROVED | jq -c '.isDraft = true')" \
  "$(openpr 236 human1:APPROVED)" "$(openpr 237 human1:APPROVED)" "$(openpr 238 human1:APPROVED)"
rm -f "$MCUR"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
eq "$(paced_views)" "236,237,238,231" "the three that could land go first, then one held anchor under the passed deadline"
has "$out" "visited 3 landing-first and 1 of 5 other anchors before the deadline; the next pass resumes at PH2" "…and the five held ones are paced"
has "$out" "merged + recorded PH8" "the three visited first land, the last of them included"
hasnt "$(cat "$STUB_GH_LOG")" "pr merge 231" "…and the held anchor visited after them does not"
# An unresolved acting login holds every PR at the approval gate, so every open
# PR is paced; one that has left the open list still goes first for its record.
store "[$(anchor PS1 241), $(anchor PS2 242), $(anchor PS3 243)]"
for n in 241 242; do printf '%s' "$(prview "$n" OPEN CLEAN)" > "$GH_DIR/pr_view_$n.json"; approved "$n"; done
printf '%s' "$(prview 243 MERGED CLEAN)" > "$GH_DIR/pr_view_243.json"
openprs "$(openpr 241 human1:APPROVED)" "$(openpr 242 human1:APPROVED)"
rm -f "$MCUR"
: > "$STUB_GH_LOG"
out=$(STUB_SELF_LOGIN="" "$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
eq "$(paced_views)" "243,241" "with no acting login only the PR that left the open list goes first"
has "$out" "visited 1 landing-first and 1 of 2 other anchors" "…and every open PR is paced"

echo "# an unreadable open-PR list leaves the pass unpaced"
store "[$(anchor PE1 281), $(anchor PE2 282)]"
printf '%s' "$(prview 281 OPEN BLOCKED)" > "$GH_DIR/pr_view_281.json"
printf '%s' "$(prview 282 OPEN BLOCKED)" > "$GH_DIR/pr_view_282.json"
for n in 281 282; do echo '[]' > "$GH_DIR/reviews_$n.json"; done
openprs "$(openpr 281)" "$(openpr 282)"
: > "$STUB_GH_LOG"
out=$(STUB_OPEN_PRS_FAIL=1 "$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
has "$out" "open-PR list unreadable" "a list read that fails is reported"
has "$out" "visited 2 landing-first and 0 of 0 other anchors" "…and every anchor is visited, the deadline notwithstanding"
has "$(cat "$STUB_GH_LOG")" "pr view 282" "…the last one included"
printf 'not json' > "$GH_DIR/open_prs.json"
: > "$STUB_GH_LOG"
out=$("$SUT" --deadline 1 --cursor "$MCUR" 2>&1)
has "$out" "open-PR list unreadable" "a list that does not parse is reported the same way"
has "$out" "visited 2 landing-first and 0 of 0 other anchors" "…and leaves the pass unpaced"
rm -f "$GH_DIR/open_prs.json"

}

# An arm proves nothing about which implementation answered unless the hand-off
# is checked directly. merge's stdout is byte-identical across the two, so a
# sentinel on the resolved path is the discriminator: it names itself, the
# subcommand it was handed, and the helper directory the binary resolves its
# siblings in.
SENTINEL="$TMP/sentinel-gctk"
printf '#!/usr/bin/env bash\nprintf "SENTINEL-GCTK %%s dir=%%s\\n" "$*" "${GCTK_SCRIPTS_DIR:-}"\n' > "$SENTINEL"
chmod +x "$SENTINEL"

echo "## arm: shell fallback (GCTK_FALLBACK=merge)"
export GCTK_FALLBACK=merge
suite
# With a binary named, merge.sh keeps the call, and the landing it records
# still reaches that binary through lifecycle.sh.
store "[$(anchor SF1 133), $(rev SF1)]"
printf '%s' "$(prview 133 OPEN CLEAN)" > "$GH_DIR/pr_view_133.json"
approved 133
out=$(GCTK_BIN="$SENTINEL" "$SUT" 2>&1)
hasnt "$out" "SENTINEL-GCTK merge" "GCTK_FALLBACK=merge keeps merge.sh on its shell with a binary named"
has "$out" "SENTINEL-GCTK lifecycle transition SF1 --to merged" "…and the shell records the landing through lifecycle.sh, which execs that binary"
rm -f "$GH_DIR/pr_view_133.json" "$GH_DIR/reviews_133.json"
unset GCTK_FALLBACK

echo
echo "## arm: gctk merge (reached through merge.sh)"
if [ -n "$GCTK_BUILT" ]; then
    export GCTK_BIN="$GCTK_BUILT"
    suite
    out=$(GCTK_BIN="$SENTINEL" "$SUT" 2>&1)
    has "$out" "SENTINEL-GCTK merge" "merge.sh execs \$GCTK_BIN with the merge subcommand when it resolves"
    has "$out" "dir=$SD" "…exporting its own directory as GCTK_SCRIPTS_DIR"
    # The city chain itself is gctk-resolve.test.sh's. This is the one shape
    # most callers have — an agent session names its city by GC_CITY_PATH alone —
    # reached through merge.sh with GCTK_BIN unset.
    CITY="$TMP/city"
    mkdir -p "$CITY/.gc/services/gctk/bin"
    cp "$SENTINEL" "$CITY/.gc/services/gctk/bin/gctk"
    out=$(env -u GCTK_BIN -u GC_CITY -u GC_CITY_ROOT GC_CITY_PATH="$CITY" "$SUT" 2>&1)
    has "$out" "SENTINEL-GCTK merge" "GC_CITY_PATH alone resolves the deployed binary through merge.sh"

    # Run directly, the binary has no merge.sh to name the helper directory. It
    # refuses the pass rather than resolving every helper as a bare name through
    # PATH. A named directory that lacks a helper is the shared body's case.
    store "[$(anchor SD1 129), $(rev SD1)]"
    printf '%s' "$(prview 129 OPEN CLEAN)" > "$GH_DIR/pr_view_129.json"
    approved 129
    : > "$STUB_GH_LOG"
    out=$(env -u GCTK_SCRIPTS_DIR "$GCTK_BUILT" merge 2>&1); rc=$?
    eq "$rc" 1 "gctk merge run without GCTK_SCRIPTS_DIR exits 1"
    has "$out" "GCTK_SCRIPTS_DIR is unset" "…naming the missing directory"
    has "$out" "NOTHING is merged this pass" "…and saying nothing merged"
    eq "$(cat "$STUB_GH_LOG")" "" "…before it reads a single PR"
    out=$(GCTK_SCRIPTS_DIR="$SD" "$GCTK_BUILT" merge 2>&1)
    has "$out" "merged + recorded SD1" "the control: the same direct run with the helper directory named merges"
else
    bad "gctk was not built, so the gctk merge port was NOT exercised, and this suite is its acceptance bar"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
