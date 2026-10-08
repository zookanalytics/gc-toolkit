#!/usr/bin/env bash
# Hermetic test for assets/scripts/pre-open-rebase.sh — the conflict observer for
# pre_open_gate anchors, the arm that files a merge-in child for a branch GitHub
# cannot yet be asked about. Covers: a conflicting branch dispatching ONE child
# stamped prepare_mode=merge and routed, carrying no PR facts; a branch that still
# merges dispatching nothing; every branch shape brought current by merge (no
# shape rebases or force-pushes, polecat/* and a graduation included) and this
# site's agreement with pr-facts.sh's copy; the vetoes (merge_hold, rebase_hold, a
# rebase_hold on a bead naming the branch, a live demand, no fix pool); a branch
# whose edited code main deleted getting the operator's supersession decision
# instead of a child, a pending decision holding without a second escalation, and
# a decision that cannot be recorded falling through to the ordinary child; dedup on
# branch and head against a live child, a stranded child re-routed rather than
# buried, and an unstamped orphan adopted by title; the read-backs that leave a
# child unrouted when prepare_mode or the route did not persist; anchors that
# already carry a PR left to pr-facts.sh; and an unreadable enumeration failing
# loudly rather than reporting a false all-clear.
# The premise under the ref guard is asserted directly: `git merge-tree` exits 1
# for a ref it cannot resolve as well as for a conflict.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-pre-open-rebase-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
# Captured before harness_init shadows PATH with the stub bin.
REAL_GIT="$(command -v git)"
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init

# The observation this arm makes IS a git operation. The harness git stub exits
# 0 for every command it does not recognise, so `merge-tree` under it reads
# CLEAN for every anchor and this suite would pass against a script that
# observes nothing. Real git over a real fixture repository; only the bead store
# is stubbed.
cat > "$BIN/git" <<GITW
#!/usr/bin/env bash
exec "$REAL_GIT" "\$@"
GITW
chmod +x "$BIN/git"

# --- fixture repository ---------------------------------------------------------
# One base point. Four branches edit line 2 and then main edits it too, so each
# conflicts; one branch touches a different file and still merges. One more
# branch edits a line inside a block of pin.sh that main then deletes outright:
# its conflict is a landed change superseding it, not drift.
SRC="$TMP/src"; WORK="$TMP/work"
git init -q -b main "$SRC"
(
  cd "$SRC" || exit 1
  git config user.email t@t; git config user.name t
  printf 'l1\nl2\nl3\n' > f.txt
  {
    printf 'check_pin() {\n'
    printf '  marker=$(gc bd show "$1" --json | jq -r ".[0].metadata.check")\n'
    printf '  if [ "${marker#*@}" != "$(git rev-parse HEAD)" ]; then\n'
    printf '    echo "stale pin on $1: the marker names an older commit than the head"\n'
    printf '    echo "a review bound to an older commit proves nothing about this one"\n'
    printf '    return 1\n  fi\n'
    printf '  echo "pin current for $1, so the verdict still binds to this head"\n}\n'
  } > pin.sh
  git add f.txt pin.sh; git commit -qm base
  BASE=$(git rev-parse HEAD)
  for spec in "polecat/tk-c1:C1" "integration/conv:CONV" "polecat/tk-grad:GRAD" "polecat/tk-hold:HOLD"; do
    git checkout -q -b "${spec%%:*}" "$BASE"
    printf 'l1\n%s\nl3\n' "${spec#*:}" > f.txt
    git commit -qam "${spec%%:*}"
  done
  git checkout -q -b polecat/tk-ok "$BASE"
  echo g > g.txt; git add g.txt; git commit -qm ok
  git checkout -q -b polecat/tk-moot "$BASE"
  sed -i 's/proves nothing about this one/proves nothing about this head/' pin.sh
  git commit -qam moot
  git checkout -q main
  printf 'l1\nMAIN\nl3\n' > f.txt
  git commit -qam main-moves
  : > pin.sh
  git commit -qam "remove the commit pin"
) >/dev/null 2>&1
git clone -q "$SRC" "$WORK"
C1_HEAD=$(git -C "$SRC" rev-parse polecat/tk-c1)

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pre-open-rebase.sh" "$HERE/branch-supersession.sh" "$HERE/pool-route.sh"
SUT="$SD/pre-open-rebase.sh"
POOL="loomington/gc-toolkit.polecat"
# escalate.sh's contract for the supersession guard: one visit per subject+key,
# stamped and routed at the board so the guard can find the visit it filed and
# count it as asking somebody. STUB_ESC_RC models a refusal.
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
[ -n "${STUB_ESC_RC:-}" ] && exit "$STUB_ESC_RC"
subj=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subj="${1:-}" ;;
    --key)     shift; key="${1:-}" ;;
  esac
  shift || true
done
[ -n "$subj" ] && [ -n "$key" ] || exit 2
vid=$(gc bd create "visit: $subj — $key" -t task --json | jq -r '.id // empty')
[ -n "$vid" ] || exit 1
gc bd update "$vid" --set-metadata "escalation_key=$key" \
  --set-metadata "gc.continuation_group=$subj" --set-metadata "task_kind=visit" \
  --set-metadata "gc.routed_to=human" >/dev/null
ESC
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log" STUB_ESC_RC=""; : > "$STUB_ESC_LOG"

run() { ( cd "$WORK" && "$SUT" "$@" 2>&1 ); }

pre() { # id branch [extra-metadata-json]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"anchor %s","description":"d","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s}}' \
    "$1" "$1" "$2" "${3:-}"
}
reset() { # <row-json>...
  local IFS=,; store "[$*]"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_SESSION_LOG"; : > "$STUB_ESC_LOG"
  export STUB_DROP_KEYS="" STUB_LIST_FAIL="" STUB_ESC_RC=""
}
newborn() { jq -r '[ .[] | select(.id | startswith("new-")) ][0].id // "<none>"' "$STUB_STORE"; }
newcount() { jq '[ .[] | select(.id | startswith("new-")) ] | length' "$STUB_STORE"; }
kidcount() { jq '[ .[] | select(.id | startswith("new-")) | select((.title // "") | startswith("visit:") | not) ] | length' "$STUB_STORE"; }

echo "# the premise the ref guard rests on"
( cd "$WORK" && git merge-tree --write-tree main nosuchref >/dev/null 2>&1 ); rc=$?
eq "$rc" "1" "git merge-tree exits 1 for an UNRESOLVABLE ref, exactly as it does for a conflict"
( cd "$WORK" && git merge-tree --write-tree origin/main origin/polecat/tk-c1 >/dev/null 2>&1 ); rc=$?
eq "$rc" "1" "...and 1 for a real conflict, so the exit status alone cannot tell them apart"
( cd "$WORK" && git merge-tree --write-tree origin/main origin/polecat/tk-ok >/dev/null 2>&1 ); rc=$?
eq "$rc" "0" "...and 0 for a branch that still merges"

echo "# a conflicting polecat branch dispatches one merge-in child"
reset "$(pre A1 polecat/tk-c1)"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "filed merge-mode rework" "the arm reports the mode it dispatched"
eq "$(newcount)" "1" "exactly one child is filed"
K=$(newborn)
eq "$(meta "$K" branch)" "polecat/tk-c1" "the child names the branch to bring current"
eq "$(meta "$K" target)" "main" "the child names the target it must merge into"
eq "$(meta "$K" prepare_mode)" "merge" "every branch shape is brought current by merge, polecat/* included"
eq "$(meta "$K" "gc.routed_to")" "$POOL" "the child is routed to the fix pool"
eq "$(meta "$K" merge_strategy)" "mr" "the child lands through the refinery"
eq "$(meta "$K" task_kind)" "rework" "the child carries the rework role marker"
eq "$(meta "$K" anchor_bead)" "A1" "and names its anchor, so a metadata read tells it from the anchor it shares a branch with"
has "$(meta "$K" rejection_reason)" "head $C1_HEAD" "the reason names the head in the phrasing pr-facts.sh dedups on"
hasnt "$(meta "$K" rejection_reason)" "force-with-lease" "a merge-in work order never names a force-push"
has "$(meta "$K" rejection_reason)" "Do NOT rebase it and do NOT force-push it" "and forbids the rewrite in words"
has "$(meta "$K" rejection_reason)" "Do NOT open a PR" "the child is told the anchor opens its own PR"
eq "$(meta "$K" pr_number)" "<absent>" "no pr_number rides a child filed before any PR exists"
eq "$(meta "$K" pr_url)" "<absent>" "no pr_url either"
eq "$(meta "$K" existing_pr)" "<absent>" "and no existing_pr to adopt"
has "$(cat "$STUB_DEPS")" "$K|blocks|A1" "the child blocks the anchor it was filed for"
has "$(cat "$STUB_SESSION_LOG")" "wake $POOL" "the fix pool is woken"

echo "# a branch a landed change superseded gets the operator's decision, not a child"
( cd "$WORK" && git merge-tree --write-tree --quiet origin/main origin/polecat/tk-moot >/dev/null 2>&1 ); rc=$?
eq "$rc" "1" "the superseded branch really conflicts (premise of the next checks)"
reset "$(pre AM polecat/tk-moot)"
OUT=$(run --fix-pool "$POOL")
eq "$(kidcount)" "0" "no merge-in child is filed for a branch whose edited code main deleted"
has "$(cat "$STUB_ESC_LOG")" "--subject AM --key rework-base-supersession" "the supersession decision is filed on the anchor instead"
has "$OUT" "filed decision" "the guard's answer is in the pass log"
has "$OUT" "held=1" "and the anchor is counted held, not skipped or reworked"
hasnt "$(cat "$STUB_SESSION_LOG")" "wake $POOL" "the fix pool is not woken"

echo "# a pending supersession decision holds without asking again"
reset "$(pre AN polecat/tk-moot)" '{"id":"VN","status":"open","assignee":"","title":"visit","notes":"","metadata":{"escalation_key":"rework-base-supersession","gc.continuation_group":"AN","task_kind":"visit","gc.routed_to":"human"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(kidcount)" "0" "an open decision on the anchor files no child"
eq "$(cat "$STUB_ESC_LOG")" "" "and no second escalation"
has "$OUT" "VN is still open" "the pending decision is named"

echo "# a supersession that cannot be recorded falls through to the ordinary child"
reset "$(pre AO polecat/tk-moot)"
export STUB_ESC_RC=1
OUT=$(run --fix-pool "$POOL")
eq "$(kidcount)" "1" "with no visit behind it, the guard holds nothing and the child is filed as before"
has "$OUT" "could not be filed" "and the pass log says why"
export STUB_ESC_RC=""

echo "# a branch that still merges is left alone"
reset "$(pre A2 polecat/tk-ok)"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a clean merge files no child"
has "$OUT" "clean=1" "and is counted as observed-clean, not skipped"

echo "# a shared branch is brought current the same way"
reset "$(pre A3 integration/conv)"
OUT=$(run --fix-pool "$POOL")
K=$(newborn)
eq "$(meta "$K" prepare_mode)" "merge" "an integration branch is brought current by merge, like every shape"
has "$(jq -r --arg k "$K" '.[]|select(.id==$k)|.title' "$STUB_STORE")" "Merge main into integration/conv" \
  "the title names the merge, so nobody working it by hand rebases"
has "$(meta "$K" rejection_reason)" "Do NOT rebase it and do NOT force-push it" "the work order forbids the rewrite"
hasnt "$(meta "$K" rejection_reason)" "force-with-lease" "and never names a force-push"

reset "$(pre A4 polecat/tk-grad ',"graduation":"true"')"
run --fix-pool "$POOL" >/dev/null
eq "$(meta "$(newborn)" prepare_mode)" "merge" "a graduation merges whatever its branch is named"

echo "# operator and human holds"
reset "$(pre A5 polecat/tk-hold ',"merge_hold":"true"')"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "merge_hold dispatches nothing"
has "$OUT" "a hold is set (operator gate)" "and says which gate held it"

reset "$(pre A6 polecat/tk-hold ',"rebase_hold":"true"')"
eq "$(run --fix-pool "$POOL" >/dev/null; newcount)" "0" "rebase_hold dispatches nothing"

reset "$(pre A7 polecat/tk-c1)" '{"id":"D1","status":"open","assignee":"","title":"demand","metadata":{"gc.demand_for":"A7"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a live demand dispatches nothing — the rebase is one horn of what it asks"
has "$OUT" "an open demand holds it" "and says so"

reset "$(pre A8 polecat/tk-c1)"
OUT=$(run)
eq "$(newcount)" "0" "no fix pool dispatches nothing"
has "$OUT" "no fix pool is configured" "and reports it for an operator to repair"

echo "# dedup, strands and orphans"
reset "$(pre A9 polecat/tk-c1)" '{"id":"K1","status":"in_progress","assignee":"someone","title":"live rework","metadata":{"branch":"polecat/tk-c1"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a LIVE child on the branch already owns the rewrite; no twin is filed"
has "$OUT" "already covers this branch" "and the arm says which child covers it"
eq "$(meta K1 task_kind)" "<absent>" "a claimed covering child is NOT re-stamped: a metadata write bypasses the claim guard, so backfilling the marker under a live holder is the stomp this refuses"
hasnt "$OUT" "re-stamped role marker on covering rework K1" "and no restamp is attempted on it"

echo "# a covering rework child parked for a person still covers the branch"
# converse-hold transitions an unanchored child to the `held` lifecycle state,
# which stamps merge_result=held; the child still owns the branch, so the
# merge_result test must not drop it and mint a merge-current twin every pass.
reset "$(pre AK polecat/tk-c1)" '{"id":"H1","status":"blocked","assignee":"","title":"held rework","metadata":{"branch":"polecat/tk-c1","task_kind":"rework","anchor_bead":"AK","merge_result":"held"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a rework child of this anchor parked in the held lifecycle state (merge_result=held) still owns the branch; no twin is filed"
has "$OUT" "already covers this branch" "and the held child is reported as the cover"
hasnt "$OUT" "re-stamped role marker on covering rework H1" "the held child already carries the marker; no restamp is attempted"

echo "# an unclaimed covering child that predates the role marker is backfilled in place"
# Routed (so past the stranded arm) but unclaimed and unmarked at this head: a
# child on the anchor's own branch a metadata read cannot tell from the anchor,
# the misread the marker exists to stop. The dup arm re-stamps it in place
# rather than route a fresh twin.
reset "$(pre AJ polecat/tk-c1)" "$(printf '{"id":"C2","status":"open","assignee":"","title":"covering rework","metadata":{"branch":"polecat/tk-c1","gc.routed_to":"%s","rejection_reason":"stale base at head %s: ..."}}' "$POOL" "$C1_HEAD")"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a covering child already owns the rewrite; no twin is filed"
has "$OUT" "re-stamped role marker on covering rework C2" "the unmarked covering child is given the role marker"
eq "$(meta C2 task_kind)" "rework" "task_kind is backfilled onto the covering child"
eq "$(meta C2 anchor_bead)" "AJ" "and anchor_bead names the anchor, so the two are now distinguishable"

reset "$(pre AA polecat/tk-c1)" "$(printf '{"id":"S1","status":"open","assignee":"","title":"stranded","metadata":{"branch":"polecat/tk-c1","rejection_reason":"stale base at head %s: ..."}}' "$C1_HEAD")"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a child stranded by a lost route stamp is not twinned"
has "$OUT" "re-routing stranded rework S1" "it is re-routed instead"
eq "$(meta S1 "gc.routed_to")" "$POOL" "and the route it was missing is stamped"

reset "$(pre AB polecat/tk-c1)" '{"id":"O1","status":"open","assignee":"","title":"Merge main into polecat/tk-c1: base moved, the branch no longer merges","metadata":{}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "an unstamped orphan carrying the deterministic title is adopted, never twinned"
has "$OUT" "adopting unstamped rework orphan O1" "and the adoption is reported"
eq "$(meta O1 branch)" "polecat/tk-c1" "the orphan gets the stamp its first pass lost"

# The freeze is read over every bead naming the branch, but a LIVE one is
# already a dedup match, so the arm it reaches alone is a settled bead the
# operator froze — the same order pr-facts.sh applies (dup, then frozen).
reset "$(pre AC polecat/tk-c1)" '{"id":"F1","status":"closed","assignee":"","title":"frozen","metadata":{"branch":"polecat/tk-c1","rebase_hold":"true"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a rebase_hold on any bead naming the branch is an operator freeze"
has "$OUT" "holds it with rebase_hold" "and is reported as one"

reset "$(pre ACL polecat/tk-c1)" '{"id":"F2","status":"open","assignee":"","title":"frozen and live","metadata":{"branch":"polecat/tk-c1","rebase_hold":"true"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a LIVE frozen bead dispatches nothing either"
has "$OUT" "already covers this branch" "reported as the dedup it is, because dedup is read first"

echo "# the read-backs: a stamp that did not persist leaves the child unrouted"
reset "$(pre AD polecat/tk-c1)"
export STUB_DROP_KEYS="new-2:prepare_mode"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "did not record prepare_mode" "a dropped prepare_mode is caught by the read-back"
eq "$(meta new-2 "gc.routed_to")" "<absent>" "and the child is left unrouted rather than routed with incomplete metadata"
hasnt "$OUT" "filed merge-mode rework" "it is not counted as dispatched"

reset "$(pre AE polecat/tk-c1)"
export STUB_DROP_KEYS="new-2:gc.routed_to"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "did not record gc.routed_to" "a dropped route is caught by its own read-back"
hasnt "$OUT" "filed merge-mode rework" "and is not counted as dispatched"
export STUB_DROP_KEYS=""

reset "$(pre AH polecat/tk-c1)"
export STUB_DROP_KEYS="new-2:task_kind"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "did not record task_kind=rework/anchor_bead" "a role marker that will not persist is caught before the route is stamped"
eq "$(meta new-2 "gc.routed_to")" "<absent>" "and the child is left unrouted rather than dispatched as an anchor-lookalike"
hasnt "$OUT" "filed merge-mode rework" "so a child a metadata read cannot tell from its anchor is never counted as dispatched"
export STUB_DROP_KEYS=""

echo "# what this arm does not enumerate"
reset '{"id":"P1","status":"open","assignee":"","notes":"","title":"pr anchor","description":"d","metadata":{"merge_result":"pull_request","branch":"polecat/tk-c1","merged_target":"main","pr_number":"7"}}'
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "an anchor that already carries a PR is pr-facts.sh's, not this arm's"
has "$OUT" "no pre-open anchors" "and the arm says it found none of its own"

echo "# a branch whose ref is gone is NOT read as a conflict"
reset "$(pre AF polecat/tk-vanished)"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "an unresolvable branch dispatches nothing, though merge-tree would exit 1 for it"
has "$OUT" "nothing observed" "and is reported as unobserved rather than clean"

echo "# a branch deleted on origin does not survive as a stale namespace ref"
# Planted at the conflicting commit: without --prune on the pass fetch the arm
# reads it as a live branch and dispatches a rebase for something nobody can push
# to. The anchor names it, so only the prune stands between that and a child.
reset "$(pre AP polecat/tk-ghost)"
git -C "$WORK" update-ref "refs/gc-toolkit/pre-open-rebase/heads/polecat/tk-ghost" \
  "$(git -C "$SRC" rev-parse polecat/tk-c1)"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a stale ref for a branch no longer on origin dispatches nothing"
eq "$(git -C "$WORK" rev-parse --verify --quiet refs/gc-toolkit/pre-open-rebase/heads/polecat/tk-ghost || echo gone)" "gone" \
  "and the pass fetch pruned it out of the namespace"

echo "# a pass that cannot fetch says so rather than reporting nothing to do"
reset "$(pre AQ polecat/tk-c1)"
git -C "$WORK" remote set-url origin "$TMP/no-such-remote"
OUT=$(run --fix-pool "$POOL"); rc=$?
git -C "$WORK" remote set-url origin "$SRC"
eq "$rc" "1" "an unfetchable origin exits non-zero"
has "$OUT" "NO anchor was observed this pass" "and says no anchor was observed, which is not the same as none needing a rebase"
eq "$(newcount)" "0" "and dispatches nothing"

echo "# an unreadable enumeration fails loudly"
reset "$(pre AG polecat/tk-c1)"
export STUB_LIST_FAIL=1
OUT=$(run --fix-pool "$POOL"); rc=$?
export STUB_LIST_FAIL=""
eq "$rc" "1" "an unreadable anchor enumeration exits non-zero"
has "$OUT" "false all-clear" "rather than reporting that nothing needs a rebase"

echo "# neither dispatch site rebases any branch shape (tk-yu4sng: merge-in for all)"
fence() { awk -v m="$1" '$0 ~ ("# >>> " m) {f=1; next} $0 ~ ("# <<< " m) {f=0} f' "$2"; }
A=$(fence stale-base-dispatch-mode "$HERE/pr-facts.sh")
B=$(fence pre-open-dispatch-mode "$HERE/pre-open-rebase.sh")
# Both non-empty first: a fence renamed in either file would otherwise make two
# empty strings pass the checks below and retire this guard silently.
if [ -n "$A" ] && [ -n "$B" ]; then ok "both dispatch-mode fences are present and non-empty"
else bad "a dispatch-mode fence is missing (pr-facts len=${#A} pre-open len=${#B})"; fi
# The change this test guards: no shape is ever classified rebase, so nothing can
# force-push. An allowlist could let a new branch shape slip past into a rewrite;
# an unconditional merge cannot.
eq "$(printf '%s\n' "$A" | grep -c 'prepare_mode=rebase')" "0" "pr-facts.sh's stale-base dispatch never classifies a branch rebase"
eq "$(printf '%s\n' "$B" | grep -c 'prepare_mode=rebase')" "0" "pre-open-rebase.sh's dispatch never classifies a branch rebase"
[ "$(printf '%s\n' "$A" | grep -c 'prepare_mode=merge')" -ge 1 ] && ok "pr-facts.sh's stale-base dispatch sets prepare_mode=merge" || bad "pr-facts.sh's stale-base dispatch sets prepare_mode=merge"
[ "$(printf '%s\n' "$B" | grep -c 'prepare_mode=merge')" -ge 1 ] && ok "pre-open-rebase.sh's dispatch sets prepare_mode=merge" || bad "pre-open-rebase.sh's dispatch sets prepare_mode=merge"

TA=$(fence takeaway-hold-discriminator "$HERE/pr-facts.sh")
TB=$(fence takeaway-hold-discriminator "$HERE/pre-open-rebase.sh")
if [ -n "$TA" ] && [ -n "$TB" ]; then ok "both takeaway-hold-discriminator fences are present and non-empty"
else bad "a takeaway-hold-discriminator fence is missing"; fi
eq "$TB" "$TA" "the demand discriminator is a byte-identical copy of pr-facts.sh's"

echo "# pacing: --deadline stops the walk after one anchor and --cursor resumes after it"
# Three anchors on a branch that still merges, enumerated out of id order. A
# deadline of epoch 1 has always passed, so a pass observes exactly one.
reset "$(pre P3 polecat/tk-ok)" "$(pre P1 polecat/tk-ok)" "$(pre P2 polecat/tk-ok)"
PCUR="$TMP/preopen.cursor"; rm -f "$PCUR"
OUT=$(run --fix-pool "$POOL" --deadline 1 --cursor "$PCUR")
has "$OUT" "visited 1 of 3 pre-open anchors before the deadline; the next pass resumes at P2" "a passed deadline observes the lowest id, then names where the next pass resumes"
has "$OUT" "clean=1 " "…and only that one anchor was observed"
eq "$(cat "$PCUR" 2>/dev/null)" "P1" "the cursor records the anchor finished"
OUT=$(run --fix-pool "$POOL" --deadline 1 --cursor "$PCUR")
has "$OUT" "the next pass resumes at P3" "the next pass resumes after the cursor"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "visited 3 of 3 pre-open anchors" "with no pacing args every anchor is observed"
has "$OUT" "clean=3 " "…all three"

echo "# pacing: an anchor the walk skips for free does not spend its one visit past the deadline"
# Q1 names no branch, so the walk passes it without a probe. It leads the
# rotation and the deadline has passed, so the visit the walk is owed goes to
# Q2.
reset "$(pre Q1 "")" "$(pre Q2 polecat/tk-ok)"
rm -f "$PCUR"
OUT=$(run --fix-pool "$POOL" --deadline 1 --cursor "$PCUR")
has "$OUT" "clean=1 " "the visit goes to the first anchor that costs a probe"
has "$OUT" "visited 1 of 2 pre-open anchors" "…counted once"
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
