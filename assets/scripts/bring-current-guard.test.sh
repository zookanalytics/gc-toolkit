#!/usr/bin/env bash
# Hermetic test for assets/scripts/bring-current-guard.sh, the guard that keeps
# an approval from covering code a bring-current changed by judgment.
#
# classify, over real git histories built here:
#   mechanical: a clean merge of the base; nothing pushed; a conflict where both
#     sides inserted a block at one place, kept whole in either order, including
#     two blocks that end in the same `fi`; a generated-tier conflict, and a
#     generated-only commit after the merge.
#   judgment: a conflict resolved by taking one side, by keeping both versions of
#     one changed line, or by git's own union, which keeps one shared `fi` for
#     two blocks; a merge commit that also edits a file the merge did not
#     conflict on; a commit of its own after the merge; a merge of a branch that
#     is not the base; an octopus merge; a pushed head that does not descend from
#     the start; a modify/delete conflict; a binary conflict; an unreadable base.
# guard, with gc, gh and escalate.sh stubbed:
#   a bead that is not a merge-in child, and a mechanical bring-current, write
#   nothing; a judgment on an approved PR files the visit FIRST, then
#   re-requests and dismisses each standing approval; an unapproved PR, the
#   city's own approval, and an already-answered situation dismiss nothing; a
#   visit that does not land, unreadable reviews, an unresolved login, and a
#   pr_url naming another PR dismiss nothing and exit 1; a dismissal that does
#   not land is noted on the visit; the resume stamp wins over --from, and no
#   start point at all is judgment; the anchor resolves from the branch when the
#   bead does not name it; a re-run after the dismissal files nothing more.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-bring-current-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"
harness_init
# The guard reads real histories, so the harness's git stub goes; its gc and gh
# stubs stay. Git's own configuration is pinned to a file here, so a host's
# conflict style, rerere or signing cannot reach a case.
rm -f "$BIN/git"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
git config --file "$GIT_CONFIG_GLOBAL" user.name "tester"
git config --file "$GIT_CONFIG_GLOBAL" user.email "tester@example.com"
git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" tag.gpgsign false
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main
git config --file "$GIT_CONFIG_GLOBAL" advice.detachedHead false

SD="$TMP/scripts"
mk_sut_dir "$SD" "$HERE/bring-current-guard.sh"
SUT="$SD/bring-current-guard.sh"
# escalate.sh's contract: ONE visit per subject+key, stamped so the caller can
# find it again, logged to the gh log too so a case can read the order of the
# visit and the dismissals. STUB_ESC_RC refuses; STUB_ESC_NOVISIT answers 0 and
# files nothing, as escalate.sh does inside a closed visit's verdict window.
cat > "$SD/escalate.sh" <<'ESC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_ESC_LOG:?}"
printf 'ESCALATE %s\n' "$*" >> "${STUB_GH_LOG:?}"
[ "${STUB_ESC_RC:-0}" = "0" ] || exit "$STUB_ESC_RC"
[ -z "${STUB_ESC_NOVISIT:-}" ] || exit 0
subj=""; key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) shift; subj="${1:-}" ;;
    --key)     shift; key="${1:-}" ;;
  esac
  shift || true
done
[ -n "$subj" ] && [ -n "$key" ] || exit 2
have=$(jq -r --arg s "$subj" --arg k "$key" '
  [ .[] | select((.status // "open") != "closed")
    | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
    | select(((.metadata.escalation_key // "") | tostring) == $k) | .id ] | .[0] // empty' "${STUB_STORE:?}")
[ -n "$have" ] && exit 0
vid=$(gc bd create "visit: $subj — $key" -t task --json | jq -r '.id // empty')
[ -n "$vid" ] || exit 1
gc bd update "$vid" --set-metadata "escalation_key=$key" \
  --set-metadata "gc.continuation_group=$subj" --set-metadata "task_kind=visit" >/dev/null
ESC
chmod +x "$SD/escalate.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
export STUB_ESC_RC=0 STUB_ESC_NOVISIT=""

# --- histories -----------------------------------------------------------------
# One case's repository: a bare origin and a clone at $R. main holds the merge
# base, the PR branch polecat/x1 carries the PR's change, and main moves past
# the base. Each argument is a shell snippet run in the clone before its commit.
# Sets R and A, the PR head a bring-current starts from.
scenario() { # <name> <base> <branch-change> <main-change>
  R="$TMP/$1"
  git init -q --bare "$TMP/$1.git"
  git init -q "$R"
  git -C "$R" remote add origin "$TMP/$1.git"
  ( cd "$R" && eval "$2" && git add -A && git commit -qm "base" )
  git -C "$R" push -q origin main 2>/dev/null
  git -C "$R" checkout -qb polecat/x1
  ( cd "$R" && eval "$3" && git add -A && git commit -qm "feat: the PR's change" )
  git -C "$R" push -q origin polecat/x1 2>/dev/null
  A=$(git -C "$R" rev-parse HEAD)
  git -C "$R" checkout -q main
  ( cd "$R" && eval "$4" && git add -A && git commit -qm "main moves" )
  git -C "$R" push -q origin main 2>/dev/null
  git -C "$R" checkout -q polecat/x1
  git -C "$R" fetch -q origin
}
# Start the bring-current over again from the PR head.
restart() { git -C "$R" merge --abort >/dev/null 2>&1; git -C "$R" reset -q --hard "$A"; }
# Merge the base in; a conflict is left for the case to resolve.
bring() { git -C "$R" merge --no-edit -q origin/main >/dev/null 2>&1; }
# Commit a resolution: each <path> <content> pair is written, then the merge
# is concluded.
resolve() { # <path> <content> [<path> <content>]...
  while [ $# -gt 1 ]; do printf '%b' "$2" > "$R/$1"; git -C "$R" add -- "$1"; shift 2; done
  git -C "$R" commit -q --no-edit >/dev/null 2>&1
}
cls() { # [to] — the verdict and reasons for A..to
  ( cd "$R" && "$SUT" classify --from "$A" --to "${1:-HEAD}" --base refs/remotes/origin/main )
}
verdict() { printf '%s\n' "$1" | head -1; }

echo "# classify: a clean merge of the base is mechanical"
scenario clean 'printf "1\n2\n3\n" > a.txt; printf "x\n" > b.txt' \
  'printf "1 ours\n2\n3\n" > a.txt' 'printf "x main\n" > b.txt'
bring
eq "$(git -C "$R" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" "3" "the bring-current is one merge commit"
out=$(cls)
eq "$(verdict "$out")" "mechanical" "a merge git made on its own took no judgment"
CLEAN_R="$R"; CLEAN_A="$A"; CLEAN_H=$(git -C "$R" rev-parse HEAD)

echo "# classify: nothing pushed is mechanical"
out=$(cls "$A")
eq "$(verdict "$out")" "mechanical" "a head equal to the start adds nothing"
has "$out" "nothing was pushed past" "…and says so"

echo "# classify: both sides inserting a block at one place, kept whole, is mechanical in either order"
scenario insert 'printf "top\nmid\nbottom\n" > list.txt' \
  'printf "top\nmid\nours-1\nours-2\nbottom\n" > list.txt' 'printf "top\nmid\ntheirs-1\nbottom\n" > list.txt'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "list.txt" "the insertions conflict"
resolve list.txt 'top\nmid\nours-1\nours-2\ntheirs-1\nbottom\n'
eq "$(verdict "$(cls)")" "mechanical" "ours then theirs keeps exactly both sides' changes"
restart; bring
resolve list.txt 'top\nmid\ntheirs-1\nours-1\nours-2\nbottom\n'
eq "$(verdict "$(cls)")" "mechanical" "…and so does theirs then ours"
restart; bring
resolve list.txt 'top\nmid\nours-1\ntheirs-1\nours-2\nbottom\n'
out=$(cls)
eq "$(verdict "$out")" "judgment" "interleaving one block into the other is not keeping them whole"
has "$out" "list.txt conflicted, and the resolution is not the two sides' insertions kept whole" "…and the reason names the file"
restart; bring
resolve list.txt 'top\nmid\nours-1\nours-2\nbottom\n'
eq "$(verdict "$(cls)")" "judgment" "dropping main's insertion is judgment"

echo "# classify: two blocks ending in the same fi need that closer twice; git's union keeps it once"
# The shared closer falls outside the conflict markers as common context, so a
# resolution pasting the two marked blocks together leaves one if unclosed.
scenario closer 'printf "echo start\necho end\n" > t.sh' \
  'printf "echo start\nif a; then\n  echo a\nfi\necho end\n" > t.sh' \
  'printf "echo start\nif b; then\n  echo b\nfi\necho end\n" > t.sh'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "t.sh" "the two blocks conflict"
eq "$(grep -c '^fi$' "$R/t.sh")" "1" "…with the shared fi outside the markers"
resolve t.sh 'echo start\nif a; then\n  echo a\nfi\nif b; then\n  echo b\nfi\necho end\n'
eq "$(verdict "$(cls)")" "mechanical" "each block whole, closer and all, is mechanical"
restart; bring
resolve t.sh 'echo start\nif a; then\n  echo a\nif b; then\n  echo b\nfi\necho end\n'
out=$(cls)
eq "$(verdict "$out")" "judgment" "the union that keeps one fi for two blocks drops a line ours wrote"
has "$out" "t.sh conflicted" "…named by file"

echo "# classify: only blank lines may differ, and each hunk takes its own order"
# Two sections both sides appended at one place, each opened by a blank line:
# git hoists the shared blank out of the conflict, and a resolution that drops
# the separator between the sections is still mechanical. A second hunk in the
# same file resolved in the other order is too.
scenario sections 'printf "head\nmid\ntail\n" > s.txt' \
  'printf "head\n\n# a\nA\nmid\n\n# c\nC\ntail\n" > s.txt' \
  'printf "head\n\n# b\nB\nmid\n\n# d\nD\ntail\n" > s.txt'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "s.txt" "the sections conflict"
resolve s.txt 'head\n\n# a\nA\n# b\nB\nmid\n\n# d\nD\n\n# c\nC\ntail\n'
eq "$(verdict "$(cls)")" "mechanical" "a dropped blank separator, and one hunk in each order, are mechanical"
restart; bring
resolve s.txt 'head\n\n# a\nA\n# b\nB\nmid\n\n# d\nD\n# c\nC changed\ntail\n'
eq "$(verdict "$(cls)")" "judgment" "…while a changed line in either block is not"

echo "# classify: a line both blocks share is kept once only by judgment"
# The mirror of the shared fi: git hoists a common first line out of the
# conflict too, and keeping it once for both blocks is a choice the guard does
# not make for anyone.
scenario prefix 'printf "top\nend\n" > p.txt' \
  'printf "top\nimport x\nuse-a\nend\n" > p.txt' 'printf "top\nimport x\nuse-b\nend\n" > p.txt'
bring
resolve p.txt 'top\nimport x\nuse-a\nuse-b\nend\n'
eq "$(verdict "$(cls)")" "judgment" "deduplicating the shared line is judgment"
restart; bring
resolve p.txt 'top\nimport x\nuse-a\nimport x\nuse-b\nend\n'
eq "$(verdict "$(cls)")" "mechanical" "…and both blocks whole, the shared line in each, is mechanical"

echo "# classify: both sides changing one line is judgment however it is resolved"
scenario modify 'printf "x=1\n" > v.txt' 'printf "x=2\n" > v.txt' 'printf "x=3\n" > v.txt'
bring
resolve v.txt 'x=2\n'
out=$(cls)
eq "$(verdict "$out")" "judgment" "taking one side chose between the two changes"
has "$out" "v.txt conflicted where both sides changed lines the merge base had" "…and the reason says so"
MODIFY_R="$R"; MODIFY_A="$A"; MODIFY_H=$(git -C "$R" rev-parse HEAD)
restart; bring
resolve v.txt 'x=2\nx=3\n'
eq "$(verdict "$(cls)")" "judgment" "keeping both versions of one changed line is judgment too"
restart; bring
resolve v.txt 'x=5\n'
eq "$(verdict "$(cls)")" "judgment" "…and so is a value neither side wrote"

echo "# classify: a merge commit that edits a file the merge did not conflict on is judgment"
R="$CLEAN_R"; A="$CLEAN_A"
git -C "$R" reset -q --hard "$CLEAN_H"
printf 'extra\n' > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -q --amend --no-edit
out=$(cls)
eq "$(verdict "$out")" "judgment" "an edit the merge did not need is judgment"
has "$out" "c.txt changed beyond what merging" "…named by the file it touched"

echo "# classify: a commit of its own after the merge is judgment"
git -C "$R" reset -q --hard "$CLEAN_H"
printf '1 ours\n2 fixed\n3\n' > "$R/a.txt"; git -C "$R" commit -qam "fix: adapt to main"
out=$(cls)
eq "$(verdict "$out")" "judgment" "a fix-up on top of the merge is judgment"
has "$out" "\"fix: adapt to main\" is a commit of its own, not part of a merge" "…named by its subject"
FIXUP_H=$(git -C "$R" rev-parse HEAD)

echo "# classify: the generated tier is exempt, in a conflict and in a commit of its own"
scenario generated \
  'printf "generated/** linguist-generated\n" > .gitattributes; mkdir -p generated; printf "r0\n" > generated/r.txt' \
  'printf "r-ours\n" > generated/r.txt' 'printf "r-main\n" > generated/r.txt'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "generated/r.txt" "the render conflicts"
resolve generated/r.txt 'r-rendered-from-both\n'
eq "$(verdict "$(cls)")" "mechanical" "a regenerated render is machine-written, not a choice"
printf 'r-rendered-again\n' > "$R/generated/r.txt"; git -C "$R" commit -qam "chore: regenerate"
eq "$(verdict "$(cls)")" "mechanical" "…and so is a commit that touches only the generated tier"
printf 'hand edit\n' > "$R/notes.txt"; git -C "$R" add notes.txt; git -C "$R" commit -qm "docs: a note"
eq "$(verdict "$(cls)")" "judgment" "a commit outside the tier is judgment again"

echo "# classify: merging anything but the base is judgment, and so is an octopus"
R="$CLEAN_R"; A="$CLEAN_A"
git -C "$R" checkout -q -b other "$CLEAN_A~1"
printf 'other\n' > "$R/o.txt"; git -C "$R" add o.txt; git -C "$R" commit -qm "other work"
git -C "$R" push -q origin other 2>/dev/null; git -C "$R" fetch -q origin
git -C "$R" checkout -q polecat/x1; git -C "$R" reset -q --hard "$CLEAN_A"
git -C "$R" merge --no-edit -q origin/other >/dev/null 2>&1
out=$(cls)
eq "$(verdict "$out")" "judgment" "a merge of a branch that is not the base is judgment"
has "$out" "which is not on refs/remotes/origin/main" "…and says which"
git -C "$R" reset -q --hard "$CLEAN_A"
git -C "$R" merge --no-edit -q origin/main origin/other >/dev/null 2>&1
out=$(cls)
eq "$(git -C "$R" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" "4" "the octopus has three parents"
eq "$(verdict "$out")" "judgment" "an octopus merge is judgment"
has "$out" "merges 3 parents at once" "…and says so"

echo "# classify: a pushed head that does not descend from the start is a rewritten history"
git -C "$R" checkout -q -B rewritten "$CLEAN_A~1"
printf '1 rebased\n2\n3\n' > "$R/a.txt"; git -C "$R" commit -qam "feat: the PR's change, rewritten"
out=$(cls)
eq "$(verdict "$out")" "judgment" "a rewritten history is judgment"
has "$out" "does not descend from" "…and says so"
git -C "$R" checkout -q polecat/x1

echo "# classify: a modify/delete conflict and a binary conflict are judgment"
scenario delete 'printf "keep\n" > d.txt' 'printf "keep changed\n" > d.txt' 'git rm -q d.txt'
bring
resolve d.txt 'keep changed\n'
out=$(cls)
eq "$(verdict "$out")" "judgment" "keeping a file the base deleted was a choice"
has "$out" "d.txt conflicted over a file one side deleted or renamed" "…and says so"
scenario binary 'printf "a\000b\n" > bin.dat' 'printf "a\000ours\n" > bin.dat' 'printf "a\000main\n" > bin.dat'
bring
resolve bin.dat 'a\000ours\n'
out=$(cls)
eq "$(verdict "$out")" "judgment" "a binary conflict is judgment"
has "$out" "bin.dat is a binary file in conflict" "…and says so"

echo "# classify: an unreadable base proves no merge is of it"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$CLEAN_H"
out=$( cd "$R" && "$SUT" classify --from "$A" --to HEAD --base refs/remotes/origin/nope )
eq "$(verdict "$out")" "judgment" "a base that does not read is judgment"

# --- guard -----------------------------------------------------------------------
NUM=1
mergein() { # id [extra-metadata] [title]
  printf '{"id":"%s","status":"in_progress","assignee":"polecat","notes":"","title":"%s","metadata":{"task_kind":"rework","anchor_bead":"AN1","branch":"polecat/x1","target":"main","prepare_mode":"merge","merge_strategy":"mr","existing_pr":"https://github.com/zook/gc-toolkit/pull/1","pr_url":"https://github.com/zook/gc-toolkit/pull/1","pr_number":"1"%s}}' \
    "$1" "${3:-Merge main into PR#1 (branch polecat/x1): base rewritten, PR conflicts}" "${2:-}"
}
anchorrow() { # id
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"the PR","metadata":{"merge_result":"pull_request","pr_number":"1","pr_url":"https://github.com/zook/gc-toolkit/pull/1","branch":"polecat/x1"}}' "$1"
}
approve() { # login id [state]
  printf '{"id":%s,"user":{"login":"%s"},"state":"%s","body":"","commit_id":"%s","submitted_at":"2026-08-20T01:00:00Z"}' \
    "$2" "$1" "${3:-APPROVED}" "$A"
}
reviews() { printf '[%s]' "$1" > "$GH_DIR/reviews_$NUM.json"; }
fresh() { : > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"; }
guard() { ( cd "$R" && "$SUT" guard "$@" 2>&1 ); }
visit_of() { jq -r '[ .[] | select((.metadata.task_kind // "") == "visit") | select((.status // "open") != "closed") | .id ] | .[0] // "<none>"' "$STUB_STORE"; }
order_ok() { # <first> <then> — <first> is logged before <then> in the gh log
  local f t
  f=$(grep -n -- "$1" "$STUB_GH_LOG" | head -1 | cut -d: -f1)
  t=$(grep -n -- "$2" "$STUB_GH_LOG" | head -1 | cut -d: -f1)
  [ -n "$f" ] && [ -n "$t" ] && [ "$f" -lt "$t" ]
}

echo "# guard: the merge-in child it acts on is the one pr-facts.sh mints"
# The guard knows a merge-in child by the title pr-facts.sh's conflict arm
# composes from the PR, its branch and its base. A reworded title there would
# stop the guard acting on any child, with nothing failing, so the two shapes
# are pinned together here.
eq "$(grep -c 'FIX_TITLE="Merge \$base into PR#\$num (branch \$fix_branch):"' "$HERE/pr-facts.sh")" "1" \
   "pr-facts.sh titles a merge-in child Merge <base> into PR#<n> (branch <branch>):"
eq "$(grep -c '"Merge \$target into PR#\$num (branch \$branch):"' "$HERE/bring-current-guard.sh")" "1" \
   "…and the guard matches that title, reading <base> from the child's target and <branch> from its branch"

echo "# guard: a bead that is not a merge-in child is left alone"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[$(mergein MI0 '' 'Address review comments on PR#1 (through review 5, comment 9)'), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI0 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "not a merge-in child of an open PR; nothing to guard" "…and says why"
eq "$(cat "$STUB_GH_LOG")" "" "…without reading GitHub or filing anything"

echo "# guard: a mechanical bring-current on an approved PR keeps the approval"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$CLEAN_H"
store "[$(mergein MI1), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI1 --from "$A" --to "$CLEAN_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "took no judgment" "…reporting the bring-current mechanical"
has "$out" "Any approval stands." "…and the approval standing"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "nothing is dismissed"
eq "$(cat "$STUB_ESC_LOG")" "" "no visit is filed"
hasnt "$(cat "$STUB_GH_LOG")" "reviews" "…and the reviews are not even read"

echo "# guard: a judgment bring-current on an approved PR files the visit, then re-requests and dismisses"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[$(mergein MI2), $(anchorrow AN1)]"
reviews "$(approve human1 501),$(approve human2 502),$(approve gc-city-bot 503)"
fresh
out=$(guard --bead MI2 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0 once the visit holds the merge"
has "$(cat "$STUB_ESC_LOG")" "--subject AN1 --key bring-current-judgment.1.$MODIFY_H" "the visit is filed on the anchor, keyed to the pushed head"
has "$(cat "$STUB_ESC_LOG")" "PR#1 approvals dismissed: bringing it current with main took judgment" "…headed by what happened"
has "$(cat "$STUB_ESC_LOG")" "v.txt conflicted" "…naming what changed"
has "$(cat "$STUB_ESC_LOG")" "Your call: review the change on the PR and approve again" "…and what the operator decides"
V=$(visit_of)
hasnt "$V" "<none>" "an open visit stands"
eq "$(meta "$V" 'gc.continuation_group')" "AN1" "…on the anchor, so it holds the anchor's merge"
has "$(cat "$STUB_GH_LOG")" "REREQUEST repos/zook/gc-toolkit/pulls/1/requested_reviewers" "the approver is re-requested"
has "$(cat "$STUB_GH_LOG")" "reviewers[]=human1" "…human1"
has "$(cat "$STUB_GH_LOG")" "reviewers[]=human2" "…and human2"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/1/reviews/501/dismissals" "human1's approval is dismissed"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/1/reviews/502/dismissals" "…and human2's"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/503/dismissals" "the city's own approval is never touched"
has "$(cat "$STUB_GH_LOG")" "message=Bringing this branch current with main took judgment (pushed head $(git -C "$R" rev-parse --short=12 HEAD))" "the dismissal names the pushed head"
order_ok "ESCALATE" "DISMISS" && ok "the visit is filed before any dismissal" || bad "the visit must be filed before any dismissal"
order_ok "requested_reviewers" "reviews/501/dismissals" && ok "…and the re-request comes before the dismissal" || bad "the re-request must come before the dismissal"
has "$out" "visit $V holds the merge, and the approvals from human1 and human2 are dismissed" "the outcome is reported"
has "$(cat "$STUB_ESC_LOG")" "so the approvals from human1 and human2 no longer cover what would land" "…and the visit names both approvals"

echo "# guard: a re-run after the dismissal files nothing more"
reviews "$(approve human1 501 DISMISSED),$(approve human2 502 DISMISSED)"
fresh
out=$(guard --bead MI2 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "no approval stands to dismiss" "…finding nothing left to dismiss"
eq "$(cat "$STUB_ESC_LOG")" "" "…and files no second visit"

echo "# guard: a judgment bring-current on an unapproved PR dismisses nothing"
store "[$(mergein MI3), $(anchorrow AN1)]"
reviews "$(approve gc-city-bot 503)"
fresh
out=$(guard --bead MI3 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "no approval stands to dismiss" "the city's own approval is no approval"
eq "$(cat "$STUB_ESC_LOG")" "" "no visit is filed"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and nothing is dismissed"

echo "# guard: a visit that does not land dismisses nothing"
store "[$(mergein MI4), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(STUB_ESC_RC=1 guard --bead MI4 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "it exits 1 so the caller retries"
has "$out" "the approval is NOT dismissed" "…saying the approval stands"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and nothing is dismissed"
fresh
out=$(STUB_ESC_NOVISIT=1 guard --bead MI4 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "a situation escalate.sh says is already answered exits 0"
has "$out" "is left standing" "…leaving the approval standing"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and dismissing nothing"

echo "# guard: a dismissal that does not land is noted on the visit, which still holds the merge"
store "[$(mergein MI5), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(STUB_DISMISS_RC=1 guard --bead MI5 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0: the visit holds the merge"
V=$(visit_of)
hasnt "$V" "<none>" "the visit stands"
has "$(notes "$V")" "Not every write on GitHub landed: the approval from human1 (review 501) could not be dismissed" "…and carries the failed dismissal"
has "$out" "not cleared:" "…which the output reports too"

echo "# guard: unreadable reviews, an unresolved login, or a pr_url naming another PR dismiss nothing"
store "[$(mergein MI6), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(STUB_GH_LIST_RC=1 guard --bead MI6 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "unreadable reviews exit 1"
eq "$(cat "$STUB_ESC_LOG")" "" "…filing no visit"
fresh
out=$(STUB_SELF_LOGIN="" guard --bead MI6 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "an unresolved acting login exits 1"
has "$out" "the acting login is unresolved" "…and says so"
store "[$(mergein MI7 ',"pr_url":"https://github.com/zook/gc-toolkit/pull/2"'), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI7 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "a pr_url naming another PR exits 1"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and dismisses nothing"

echo "# guard: the resume stamp marks the start, so a re-run after the push still sees the judgment"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$FIXUP_H"
store "[$(mergein MI8 ",\"bring_current_from\":\"$CLEAN_A\""), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI8 --from "$FIXUP_H" --to "$FIXUP_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$(cat "$STUB_ESC_LOG")" "is a commit of its own" "the stamp's range holds the fix-up, so the visit names it"
has "$(cat "$STUB_GH_LOG")" "reviews/501/dismissals" "…and the approval is dismissed"
store "[$(mergein MI9), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI9 --from "$FIXUP_H" --to "$FIXUP_H"); rc=$?
has "$out" "took no judgment" "without the stamp, --from bounds the range, and an empty push is mechanical"
store "[$(mergein MI10), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI10 --to "$FIXUP_H"); rc=$?
has "$(cat "$STUB_ESC_LOG")" "nothing records where this bring-current began" "with no start at all the guard cannot read the change, which is judgment"
has "$(cat "$STUB_GH_LOG")" "reviews/501/dismissals" "…so the approval is dismissed"

echo "# guard: a bead that does not name its anchor finds it on the branch"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[$(mergein MI11 | jq -c 'del(.metadata.anchor_bead)'), $(anchorrow AN9)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI11 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$(cat "$STUB_ESC_LOG")" "--subject AN9 " "the visit lands on the branch's anchor"

echo "# the resume block records the start before its merge, and the guard reads from there"
# mol-polecat-work's rejected-branch-resume-mode, run as a polecat runs it on a
# merge-in child: the stamp is the PR head from before the merge moved HEAD,
# so a guard re-run after the push, whose --from is the pushed head itself,
# still reads the whole bring-current.
RESUME=$(awk '/# >>> rejected-branch-resume-mode$/ {f=1; next} /# <<< rejected-branch-resume-mode$/ {f=0} f' \
  "$ROOT/formulas/mol-polecat-work.toml" | sed 's/{{base_branch}}/main/g')
[ -n "$RESUME" ] && ok "the resume block is extracted from the formula" || bad "the resume block is not extracted from the formula"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" merge --abort >/dev/null 2>&1; git -C "$R" reset -q --hard "$A"
store "[$(mergein MI12 ',"rejection_reason":"stale base at head sha-1: PR#1 conflicts with main."'), $(anchorrow AN1)]"
( cd "$R" && WORK_BEAD_ID=MI12 bash -c "$RESUME" ) >/dev/null 2>&1
eq "$(meta MI12 bring_current_from)" "$A" "the stamp is the PR head the bring-current started from"
eq "$(meta MI12 rejection_reason)" "<absent>" "…and the resume cleared the rejection as before"
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "v.txt" "the merge it ran stopped on the conflict"
resolve v.txt 'x=2\n'
H=$(git -C "$R" rev-parse HEAD)
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI12 --from "$H" --to "$H"); rc=$?
eq "$rc" "0" "the guard exits 0"
has "$(cat "$STUB_ESC_LOG")" "v.txt conflicted where both sides changed lines the merge base had" "a re-run after the push still sees the judgment, from the stamp"
has "$(cat "$STUB_GH_LOG")" "reviews/501/dismissals" "…and dismisses the approval"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
