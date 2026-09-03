#!/usr/bin/env bash
# Hermetic test for assets/scripts/pre-open-rebase.sh — the conflict observer for
# pre_open_gate anchors, the arm that files a rebase child for a branch GitHub
# cannot yet be asked about. Covers: a conflicting branch dispatching ONE child
# stamped prepare_mode and routed, carrying no PR facts; a branch that still
# merges dispatching nothing; the branch allowlist (polecat/* rebases, every
# other shape merges, a graduation merges whatever its branch is named) and its
# agreement with pr-facts.sh's copy; the vetoes (merge_hold, rebase_hold, a
# rebase_hold on a bead naming the branch, a live demand, no fix pool); dedup on
# branch and head against a live child, a stranded child re-routed rather than
# buried, and an unstamped orphan adopted by title; the read-backs that leave a
# child unrouted when prepare_mode or the route did not persist; anchors that
# already carry a PR left to pr-facts.sh; and an unreadable enumeration failing
# loudly rather than reporting a false all-clear.
# The premise under the ref guard is asserted directly: `git merge-tree` exits 1
# for a ref it cannot resolve as well as for a conflict.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
# conflicts; one branch touches a different file and still merges.
SRC="$TMP/src"; WORK="$TMP/work"
git init -q -b main "$SRC"
(
  cd "$SRC"
  git config user.email t@t; git config user.name t
  printf 'l1\nl2\nl3\n' > f.txt
  git add f.txt; git commit -qm base
  BASE=$(git rev-parse HEAD)
  for spec in "polecat/tk-c1:C1" "integration/conv:CONV" "polecat/tk-grad:GRAD" "polecat/tk-hold:HOLD"; do
    git checkout -q -b "${spec%%:*}" "$BASE"
    printf 'l1\n%s\nl3\n' "${spec#*:}" > f.txt
    git commit -qam "${spec%%:*}"
  done
  git checkout -q -b polecat/tk-ok "$BASE"
  echo g > g.txt; git add g.txt; git commit -qm ok
  git checkout -q main
  printf 'l1\nMAIN\nl3\n' > f.txt
  git commit -qam main-moves
) >/dev/null 2>&1
git clone -q "$SRC" "$WORK"
C1_HEAD=$(git -C "$SRC" rev-parse polecat/tk-c1)

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/pre-open-rebase.sh"
SUT="$SD/pre-open-rebase.sh"
POOL="loomington/gc-toolkit.polecat"

run() { ( cd "$WORK" && "$SUT" "$@" 2>&1 ); }

pre() { # id branch [extra-metadata-json]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"anchor %s","description":"d","metadata":{"merge_result":"pre_open_gate","branch":"%s","merged_target":"main"%s}}' \
    "$1" "$1" "$2" "${3:-}"
}
reset() { # <row-json>...
  local IFS=,; store "[$*]"
  : > "$STUB_DEPS"; : > "$STUB_GC_LOG"; : > "$STUB_SESSION_LOG"
  export STUB_DROP_KEYS="" STUB_LIST_FAIL=""
}
newborn() { jq -r '[ .[] | select(.id | startswith("new-")) ][0].id // "<none>"' "$STUB_STORE"; }
newcount() { jq '[ .[] | select(.id | startswith("new-")) ] | length' "$STUB_STORE"; }

echo "# the premise the ref guard rests on"
( cd "$WORK" && git merge-tree --write-tree main nosuchref >/dev/null 2>&1 ); rc=$?
eq "$rc" "1" "git merge-tree exits 1 for an UNRESOLVABLE ref, exactly as it does for a conflict"
( cd "$WORK" && git merge-tree --write-tree origin/main origin/polecat/tk-c1 >/dev/null 2>&1 ); rc=$?
eq "$rc" "1" "...and 1 for a real conflict, so the exit status alone cannot tell them apart"
( cd "$WORK" && git merge-tree --write-tree origin/main origin/polecat/tk-ok >/dev/null 2>&1 ); rc=$?
eq "$rc" "0" "...and 0 for a branch that still merges"

echo "# a conflicting polecat branch dispatches one rebase child"
reset "$(pre A1 polecat/tk-c1)"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "filed rebase-mode rework" "the arm reports the mode it dispatched"
eq "$(newcount)" "1" "exactly one child is filed"
K=$(newborn)
eq "$(meta "$K" branch)" "polecat/tk-c1" "the child names the branch to bring current"
eq "$(meta "$K" target)" "main" "the child names the target it must merge into"
eq "$(meta "$K" prepare_mode)" "rebase" "a polecat/* branch is disposable, so the mode is rebase"
eq "$(meta "$K" "gc.routed_to")" "$POOL" "the child is routed to the fix pool"
eq "$(meta "$K" merge_strategy)" "mr" "the child lands through the refinery"
has "$(meta "$K" rejection_reason)" "head $C1_HEAD" "the reason names the head in the phrasing pr-facts.sh dedups on"
has "$(meta "$K" rejection_reason)" "force-with-lease" "a rebase-mode work order names the force-push it needs"
has "$(meta "$K" rejection_reason)" "Do NOT open a PR" "the child is told the anchor opens its own PR"
eq "$(meta "$K" pr_number)" "<absent>" "no pr_number rides a child filed before any PR exists"
eq "$(meta "$K" pr_url)" "<absent>" "no pr_url either"
eq "$(meta "$K" existing_pr)" "<absent>" "and no existing_pr to adopt"
has "$(cat "$STUB_DEPS")" "$K|blocks|A1" "the child blocks the anchor it was filed for"
has "$(cat "$STUB_SESSION_LOG")" "wake $POOL" "the fix pool is woken"

echo "# a branch that still merges is left alone"
reset "$(pre A2 polecat/tk-ok)"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a clean merge files no child"
has "$OUT" "clean=1" "and is counted as observed-clean, not skipped"

echo "# the branch allowlist"
reset "$(pre A3 integration/conv)"
OUT=$(run --fix-pool "$POOL")
K=$(newborn)
eq "$(meta "$K" prepare_mode)" "merge" "a non-polecat branch is shared, so the mode is merge"
has "$(jq -r --arg k "$K" '.[]|select(.id==$k)|.title' "$STUB_STORE")" "Merge main into shared branch" \
  "the title names its own mode, so nobody working it by hand rebases"
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

reset "$(pre AA polecat/tk-c1)" "$(printf '{"id":"S1","status":"open","assignee":"","title":"stranded","metadata":{"branch":"polecat/tk-c1","rejection_reason":"stale base at head %s: ..."}}' "$C1_HEAD")"
OUT=$(run --fix-pool "$POOL")
eq "$(newcount)" "0" "a child stranded by a lost route stamp is not twinned"
has "$OUT" "re-routing stranded rework S1" "it is re-routed instead"
eq "$(meta S1 "gc.routed_to")" "$POOL" "and the route it was missing is stamped"

reset "$(pre AB polecat/tk-c1)" '{"id":"O1","status":"open","assignee":"","title":"Rebase polecat/tk-c1 onto main: base moved, the branch no longer merges","metadata":{}}'
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
eq "$(meta new-2 "gc.routed_to")" "<absent>" "and the child is left unrouted rather than routable-and-rewriting"
hasnt "$OUT" "filed rebase-mode rework" "it is not counted as dispatched"

reset "$(pre AE polecat/tk-c1)"
export STUB_DROP_KEYS="new-2:gc.routed_to"
OUT=$(run --fix-pool "$POOL")
has "$OUT" "did not record gc.routed_to" "a dropped route is caught by its own read-back"
hasnt "$OUT" "filed rebase-mode rework" "and is not counted as dispatched"
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

echo "# the mirrored predicates agree with pr-facts.sh"
norm() { sed -e 's/\$fix_branch/$BR/g' -e 's/\$branch/$BR/g' -e 's/[[:space:]][[:space:]]*/ /g' -e 's/^ //' -e 's/ $//'; }
fence() { awk -v m="$1" '$0 ~ ("# >>> " m) {f=1; next} $0 ~ ("# <<< " m) {f=0} f' "$2"; }
A=$(fence stale-base-dispatch-mode "$HERE/pr-facts.sh" | sed -n '/^ *case /,/^ *esac/p' | norm)
B=$(fence pre-open-dispatch-mode "$HERE/pre-open-rebase.sh" | sed -n '/^ *case /,/^ *esac/p' | norm)
# Both non-empty first: a fence renamed in either file would otherwise make two
# empty strings compare equal and retire this guard silently.
if [ -n "$A" ] && [ -n "$B" ]; then ok "both dispatch-mode fences are present and non-empty"
else bad "a dispatch-mode fence is missing (pr-facts='$A' pre-open='$B')"; fi
eq "$B" "$A" "the branch allowlist is identical to pr-facts.sh's once the variable name is normalised"

GA=$(fence stale-base-dispatch-mode "$HERE/pr-facts.sh" | grep -c 'grad.*=.*"true".*prepare_mode=merge')
GB=$(fence pre-open-dispatch-mode "$HERE/pre-open-rebase.sh" | grep -c 'grad.*=.*"true".*prepare_mode=merge')
eq "$GB" "$GA" "and so is the graduation override"

TA=$(fence takeaway-hold-discriminator "$HERE/pr-facts.sh")
TB=$(fence takeaway-hold-discriminator "$HERE/pre-open-rebase.sh")
if [ -n "$TA" ] && [ -n "$TB" ]; then ok "both takeaway-hold-discriminator fences are present and non-empty"
else bad "a takeaway-hold-discriminator fence is missing"; fi
eq "$TB" "$TA" "the demand discriminator is a byte-identical copy of pr-facts.sh's"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
