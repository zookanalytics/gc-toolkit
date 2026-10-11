#!/usr/bin/env bash
# Hermetic test for assets/scripts/bring-current-guard.sh, the guard that holds a
# bring-current round to the worker's audit and routes a conflicted one to
# triage.
#
# classify, over real git histories built here:
#   clean: a merge of the base git made on its own; a generated-tier conflict;
#     a generated-only commit after the merge; a commit of the bead's own work
#     on a with-work bead, listed as a note.
#   conflicted, each item named with the evidence of what git's replay shows:
#     a conflict where both sides only added lines and the resolution kept both
#     whole (either order, a closer each, blank lines dropped); one that took a
#     side, interleaved, deduplicated or rewrote; a hunk whose merge base had
#     lines; a merge commit that edits a file the merge did not conflict on; a
#     commit of its own on a merge-only bead; a merge of a branch that is not the
#     base; an octopus; a rewritten history; a modify/delete and a binary
#     conflict; a git read that fails (the generated-tier attributes, a commit's
#     own change), which never reads as clean.
#   none: nothing pushed, or nothing merged in. unreadable: an unreadable base,
#     a commit list that cannot be read.
# guard, with gc, gh, escalate.sh and review-outcome.sh stubbed:
#   a branch with no review to keep is left alone; a clean round is recorded on
#   the anchor and reopens nothing; a conflicted round whose audit misses an item
#   or carries an incomplete entry is refused (exit 3) and writes nothing; a
#   covered one stores the audit and evidence, reopens triage with the round's
#   time, and supersedes the triage lane, reading GitHub not at all; a re-run is
#   idempotent, and one after triage ruled reopens nothing; an opted-out
#   check_set records without reopening; a merge-only bead owes entries for its
#   own commits; a pre-open-rebase child and a re-queued anchor are guarded; an
#   earlier round awaiting triage rides into the next record; no stamp and
#   nothing pushed is refused; the resume stamp marks the start; the anchor
#   resolves from the branch; a failed write or supersede exits 1.
# decide: refuses with no conflicted round, a lane the anchor does not declare,
#   or a round another review already ruled on; records the ruling, unions the
#   reopened lanes, supersedes each, renders the round's account; a dismissal
#   files the visit composed from the audit FIRST, then re-requests and
#   dismisses with a note composed from it; no approval dismisses nothing; a
#   visit that does not land dismisses nothing; a retry carries out what was
#   recorded.
# The resume block, extracted from mol-polecat-work, stamps the start and the
# scope and clears the last round's audit before its merge, and the filers'
# rejection prefixes it reads are pinned.
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
mk_sut_dir "$SD" "$HERE/bring-current-guard.sh" "$HERE/bring-current-audit.sh"
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
# review-outcome.sh supersede-lane, logged; STUB_RO_RC fails it.
cat > "$SD/review-outcome.sh" <<'RO'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_RO_LOG:?}"
exit "${STUB_RO_RC:-0}"
RO
chmod +x "$SD/review-outcome.sh"
export STUB_ESC_LOG="$TMP/esc.log"; : > "$STUB_ESC_LOG"
export STUB_RO_LOG="$TMP/ro.log"; : > "$STUB_RO_LOG"
export STUB_ESC_RC=0 STUB_ESC_NOVISIT="" STUB_RO_RC=0

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
cls() { # [to] [scope] — the class and evidence for A..to
  ( cd "$R" && "$SUT" classify --from "$A" --to "${1:-HEAD}" --base refs/remotes/origin/main --scope "${2:-with-work}" )
}
class() { printf '%s\n' "$1" | head -1; }

echo "# classify: a merge of the base git made on its own is clean"
scenario clean 'printf "1\n2\n3\n" > a.txt; printf "x\n" > b.txt' \
  'printf "1 ours\n2\n3\n" > a.txt' 'printf "x main\n" > b.txt'
bring
eq "$(git -C "$R" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" "3" "the bring-current is one merge commit"
out=$(cls)
eq "$(class "$out")" "clean" "a merge git made on its own is clean"
hasnt "$out" "audit " "…and names no item"
CLEAN_R="$R"; CLEAN_A="$A"; CLEAN_H=$(git -C "$R" rev-parse HEAD)

echo "# classify: nothing pushed is no round at all"
eq "$(class "$(cls "$A")")" "none" "a head equal to the start adds nothing"

echo "# classify: both sides adding a block at one place, kept whole, is a conflict that kept both"
scenario insert 'printf "top\nmid\nbottom\n" > list.txt' \
  'printf "top\nmid\nours-1\nours-2\nbottom\n" > list.txt' 'printf "top\nmid\ntheirs-1\nbottom\n" > list.txt'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "list.txt" "the insertions conflict"
resolve list.txt 'top\nmid\nours-1\nours-2\ntheirs-1\nbottom\n'
out=$(cls)
eq "$(class "$out")" "conflicted" "any conflict owes an account, however it was resolved"
has "$out" "audit list.txt: conflicted where both sides only added lines; the resolution keeps both additions whole" "…with the evidence that both additions were kept whole"
restart; bring
resolve list.txt 'top\nmid\ntheirs-1\nours-1\nours-2\nbottom\n'
has "$(cls)" "the resolution keeps both additions whole" "…in either order"
restart; bring
resolve list.txt 'top\nmid\nours-1\ntheirs-1\nours-2\nbottom\n'
out=$(cls)
has "$out" "audit list.txt: conflicted, and the resolution is not the two sides' additions kept whole" "interleaving one block into the other is not keeping them whole"
restart; bring
resolve list.txt 'top\nmid\nours-1\nours-2\nbottom\n'
has "$(cls)" "is not the two sides' additions kept whole" "…and neither is dropping main's addition"

echo "# classify: two blocks ending in the same fi need that closer twice; git's union keeps it once"
scenario closer 'printf "echo start\necho end\n" > t.sh' \
  'printf "echo start\nif a; then\n  echo a\nfi\necho end\n" > t.sh' \
  'printf "echo start\nif b; then\n  echo b\nfi\necho end\n" > t.sh'
bring
eq "$(grep -c '^fi$' "$R/t.sh")" "1" "the shared fi sits outside the markers"
resolve t.sh 'echo start\nif a; then\n  echo a\nfi\nif b; then\n  echo b\nfi\necho end\n'
has "$(cls)" "audit t.sh: conflicted where both sides only added lines" "each block whole, closer and all, kept both"
restart; bring
resolve t.sh 'echo start\nif a; then\n  echo a\nif b; then\n  echo b\nfi\necho end\n'
has "$(cls)" "audit t.sh: conflicted, and the resolution is not the two sides' additions kept whole" "the union that keeps one fi for two blocks drops a line ours wrote"

echo "# classify: only blank lines may differ, and each hunk takes its own order"
scenario sections 'printf "head\nmid\ntail\n" > s.txt' \
  'printf "head\n\n# a\nA\nmid\n\n# c\nC\ntail\n" > s.txt' \
  'printf "head\n\n# b\nB\nmid\n\n# d\nD\ntail\n" > s.txt'
bring
resolve s.txt 'head\n\n# a\nA\n# b\nB\nmid\n\n# d\nD\n\n# c\nC\ntail\n'
has "$(cls)" "keeps both additions whole" "a dropped blank separator, and one hunk in each order, kept both"
restart; bring
resolve s.txt 'head\n\n# a\nA\n# b\nB\nmid\n\n# d\nD\n# c\nC changed\ntail\n'
has "$(cls)" "is not the two sides' additions kept whole" "…while a changed line in either block is not"

echo "# classify: a line both blocks share is kept once only by a rewrite"
scenario prefix 'printf "top\nend\n" > p.txt' \
  'printf "top\nimport x\nuse-a\nend\n" > p.txt' 'printf "top\nimport x\nuse-b\nend\n" > p.txt'
bring
resolve p.txt 'top\nimport x\nuse-a\nuse-b\nend\n'
has "$(cls)" "is not the two sides' additions kept whole" "deduplicating the shared line is a rewrite"
restart; bring
resolve p.txt 'top\nimport x\nuse-a\nimport x\nuse-b\nend\n'
has "$(cls)" "keeps both additions whole" "…and both blocks whole, the shared line in each, kept both"

echo "# classify: a hunk whose merge base had lines is named as one git could not merge"
scenario modify 'printf "x=1\n" > v.txt' 'printf "x=2\n" > v.txt' 'printf "x=3\n" > v.txt'
bring
resolve v.txt 'x=2\n'
out=$(cls)
eq "$(class "$out")" "conflicted" "taking one side of a changed line is conflicted"
has "$out" "audit v.txt: conflicted where the merge base had lines that one or both sides changed, so git could not merge it on its own" "…and the evidence says what the base had"
MODIFY_R="$R"; MODIFY_A="$A"; MODIFY_H=$(git -C "$R" rev-parse HEAD)

echo "# classify: a merge commit that edits a file the merge did not conflict on is an item"
R="$CLEAN_R"; A="$CLEAN_A"
git -C "$R" reset -q --hard "$CLEAN_H"
printf 'extra\n' > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -q --amend --no-edit
out=$(cls)
eq "$(class "$out")" "conflicted" "an edit the merge did not need is not clean"
has "$out" "audit c.txt: changed beyond what merging" "…named by the file it touched"

echo "# classify: a commit of its own is the bead's work, or an item on a merge-only bead"
git -C "$R" reset -q --hard "$CLEAN_H"
printf '1 ours\n2 fixed\n3\n' > "$R/a.txt"; git -C "$R" commit -qam "fix: adapt to main"
out=$(cls HEAD with-work)
eq "$(class "$out")" "clean" "on a with-work bead the merge is still clean"
has "$out" "note  commit:" "…and the commit is listed as a note"
has "$out" "\"fix: adapt to main\" is a commit of the bead's own work" "…named by its subject"
out=$(cls HEAD merge-only)
eq "$(class "$out")" "conflicted" "on a merge-only bead a commit of its own is an edit beyond the merge"
has "$out" "audit a.txt: changed by" "…and each file it changes is an item"
FIXUP_H=$(git -C "$R" rev-parse HEAD)

echo "# classify: the generated tier owes no entry, in a conflict and in a commit of its own"
scenario generated \
  'printf "generated/** linguist-generated\n" > .gitattributes; mkdir -p generated; printf "r0\n" > generated/r.txt' \
  'printf "r-ours\n" > generated/r.txt' 'printf "r-main\n" > generated/r.txt'
bring
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "generated/r.txt" "the render conflicts"
resolve generated/r.txt 'r-rendered-from-both\n'
out=$(cls)
eq "$(class "$out")" "clean" "a regenerated render is machine-written, not a choice"
has "$out" "note  generated/r.txt: a generated render" "…listed as a note"
GEN_R="$R"; GEN_A="$A"; GEN_MERGE=$(git -C "$R" rev-parse HEAD)
printf 'r-rendered-again\n' > "$R/generated/r.txt"; git -C "$R" commit -qam "chore: regenerate"
eq "$(class "$(cls HEAD merge-only)")" "clean" "…and so is a commit that touches only the generated tier, even on a merge-only bead"
GEN_REGEN=$(git -C "$R" rev-parse HEAD)
printf 'hand edit\n' > "$R/notes.txt"; git -C "$R" add notes.txt; git -C "$R" commit -qm "docs: a note"
has "$(cls HEAD merge-only)" "audit notes.txt: changed by" "a commit outside the tier is an item on a merge-only bead"

echo "# classify: a git read that fails is never clean"
REAL_GIT=$(command -v git)
mkdir -p "$TMP/failgit"
cat > "$TMP/failgit/git" <<SHIM
#!/usr/bin/env bash
sub=""; i=1
while [ "\$i" -le "\$#" ]; do
  case "\${!i}" in
    -c|-C) i=\$((i + 2)) ;;
    -*) i=\$((i + 1)) ;;
    *) sub="\${!i}"; break ;;
  esac
done
[ -n "\${FAIL_GIT:-}" ] && [ "\$sub" = "\$FAIL_GIT" ] && exit 128
exec "$REAL_GIT" "\$@"
SHIM
chmod +x "$TMP/failgit/git"
failcls() { # <git-subcommand> <from> <to> [scope]
  ( cd "$R" && FAIL_GIT="$1" PATH="$TMP/failgit:$PATH" "$SUT" classify --from "$2" --to "$3" --base refs/remotes/origin/main --scope "${4:-with-work}" )
}
R="$GEN_R"; A="$GEN_A"
eq "$(class "$(failcls no-such-subcommand "$A" "$GEN_REGEN")")" "clean" \
   "control: the shim refusing nothing leaves the generated-tier round clean"
out=$(failcls check-attr "$A" "$GEN_MERGE")
eq "$(class "$out")" "conflicted" "an attribute read that fails exempts nothing"
has "$out" "audit generated/r.txt: conflicted" "…so the render's conflict is an item like any file's"
out=$(failcls diff-tree "$GEN_MERGE" "$GEN_REGEN" merge-only)
eq "$(class "$out")" "conflicted" "on a merge-only bead, a commit of its own whose change cannot be read is an item"
has "$out" "\"chore: regenerate\" is a commit of its own, and what it changed could not be read" "…and says so"
out=$(failcls rev-list "$A" "$GEN_REGEN")
eq "$(class "$out")" "unreadable" "a history whose commits cannot be listed is unreadable"
has "$out" "could not be listed" "…and says so"

echo "# classify: merging anything but the base is an item, and so is an octopus"
R="$CLEAN_R"; A="$CLEAN_A"
git -C "$R" checkout -q -b other "$CLEAN_A~1"
printf 'other\n' > "$R/o.txt"; git -C "$R" add o.txt; git -C "$R" commit -qm "other work"
git -C "$R" push -q origin other 2>/dev/null; git -C "$R" fetch -q origin
git -C "$R" checkout -q polecat/x1; git -C "$R" reset -q --hard "$CLEAN_A"
git -C "$R" merge --no-edit -q origin/other >/dev/null 2>&1
out=$(cls)
eq "$(class "$out")" "conflicted" "a merge of a branch that is not the base is conflicted"
has "$out" "audit commit:" "…as an item keyed by the commit"
has "$out" "which is not on refs/remotes/origin/main" "…saying which"
git -C "$R" reset -q --hard "$CLEAN_A"
git -C "$R" merge --no-edit -q origin/main origin/other >/dev/null 2>&1
out=$(cls)
eq "$(git -C "$R" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" "4" "the octopus has three parents"
has "$out" "merges 3 parents at once" "an octopus merge is an item"

echo "# classify: a pushed head that does not descend from the start is a rewritten history"
git -C "$R" checkout -q -B rewritten "$CLEAN_A~1"
printf '1 rebased\n2\n3\n' > "$R/a.txt"; git -C "$R" commit -qam "feat: the PR's change, rewritten"
out=$(cls)
eq "$(class "$out")" "conflicted" "a rewritten history is conflicted"
has "$out" "audit history: the pushed head" "…as the history item"
git -C "$R" checkout -q polecat/x1

echo "# classify: a modify/delete conflict and a binary conflict are named as such"
scenario delete 'printf "keep\n" > d.txt' 'printf "keep changed\n" > d.txt' 'git rm -q d.txt'
bring
resolve d.txt 'keep changed\n'
has "$(cls)" "audit d.txt: conflicted over a file one side deleted or renamed" "keeping a file the base deleted was a choice"
scenario binary 'printf "a\000b\n" > bin.dat' 'printf "a\000ours\n" > bin.dat' 'printf "a\000main\n" > bin.dat'
bring
resolve bin.dat 'a\000ours\n'
has "$(cls)" "audit bin.dat: is a binary file in conflict" "a binary conflict is an item"

echo "# classify: an unreadable base is unreadable"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$CLEAN_H"
out=$( cd "$R" && "$SUT" classify --from "$A" --to HEAD --base refs/remotes/origin/nope )
eq "$(class "$out")" "unreadable" "a base that does not read is unreadable"

# --- guard -----------------------------------------------------------------------
NUM=1
# A hand-off bead: the merge-in child pr-facts.sh mints, by default.
child() { # id [extra-metadata] [title]
  printf '{"id":"%s","status":"in_progress","assignee":"polecat","notes":"","title":"%s","metadata":{"task_kind":"rework","anchor_bead":"AN1","branch":"polecat/x1","target":"main","prepare_mode":"merge","merge_strategy":"mr","existing_pr":"https://github.com/zook/gc-toolkit/pull/1","pr_url":"https://github.com/zook/gc-toolkit/pull/1","pr_number":"1"%s}}' \
    "$1" "${3:-Merge main into PR#1 (branch polecat/x1): base rewritten, PR conflicts}" "${2:-}"
}
anchorrow() { # id [extra-metadata]
  printf '{"id":"%s","status":"open","assignee":"","notes":"","title":"the PR","metadata":{"merge_result":"pull_request","pr_number":"1","pr_url":"https://github.com/zook/gc-toolkit/pull/1","branch":"polecat/x1","target":"main","check_set":"correctness,triage"%s}}' "$1" "${2:-}"
}
approve() { # login id [state] [submitted_at]
  printf '{"id":%s,"user":{"login":"%s"},"state":"%s","body":"","commit_id":"%s","submitted_at":"%s"}' \
    "$2" "$1" "${3:-APPROVED}" "$A" "${4:-2026-08-20T01:00:00Z}"
}
reviews() { printf '[%s]' "$1" > "$GH_DIR/reviews_$NUM.json"; }
# One audit entry, and the metadata fragment carrying a set of them as the text
# bd stores.
entry() { # <path> [rating]
  jq -nc --arg p "$1" --arg r "${2:-routine}" \
    '{path: $p, collided: "main changed \($p) while the branch changed it too", resolution: "kept the branch version of \($p) because main only reworded it", check: "read \($p) end to end", rating: $r}'
}
audit_meta() { # <entry-json>...
  printf ',"conflict_audit":%s' "$(printf '%s\n' "$@" | jq -sc . | jq -Rc .)"
}
fresh() { : > "$STUB_GH_LOG"; : > "$STUB_ESC_LOG"; : > "$STUB_RO_LOG"; }
guard() { ( cd "$R" && "$SUT" guard "$@" 2>&1 ); }
rec_of() { jq -c --arg id "$1" '(.[] | select(.id == $id) | .metadata.bring_current_record // null) | if type == "string" then fromjson else . end' "$STUB_STORE"; }
visit_of() { jq -r '[ .[] | select((.metadata.task_kind // "") == "visit") | select((.status // "open") != "closed") | .id ] | .[0] // "<none>"' "$STUB_STORE"; }
order_ok() { # <first> <then> — <first> is logged before <then> in the gh log
  local f t
  f=$(grep -n -- "$1" "$STUB_GH_LOG" | head -1 | cut -d: -f1)
  t=$(grep -n -- "$2" "$STUB_GH_LOG" | head -1 | cut -d: -f1)
  [ -n "$f" ] && [ -n "$t" ] && [ "$f" -lt "$t" ]
}

echo "# guard: a branch with no review to keep current is left alone"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[{\"id\":\"FW1\",\"status\":\"in_progress\",\"assignee\":\"polecat\",\"notes\":\"\",\"title\":\"fresh work\",\"metadata\":{\"branch\":\"polecat/x1\",\"target\":\"main\"}}]"
fresh
out=$(guard --bead FW1 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "carries no review to keep current" "…and says why"
eq "$(cat "$STUB_GH_LOG")$(cat "$STUB_RO_LOG")" "" "…reading GitHub and reopening nothing"

echo "# guard: a clean round is recorded on the anchor and reopens nothing"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$CLEAN_H"
store "[$(child MI1), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI1 --from "$A" --to "$CLEAN_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "was clean" "…reporting the round clean"
eq "$(rec_of AN1 | jq -r '.class')" "clean" "the anchor carries the round's record, class clean"
eq "$(rec_of AN1 | jq -r '.head')" "$CLEAN_H" "…at the pushed head"
eq "$(meta AN1 bring_current_reopened)" "<absent>" "no lane is reopened"
eq "$(cat "$STUB_RO_LOG")" "" "…and nothing is superseded"
eq "$(cat "$STUB_GH_LOG")" "" "GitHub is not read at all"

echo "# guard: a conflicted round whose audit misses an item is refused, and writes nothing"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[$(child MI2), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI2 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "3" "it exits 3: the worker completes the audit"
has "$out" "does not cover the round" "…saying the audit does not cover it"
has "$out" "NEEDS AN ENTRY  v.txt" "…naming the item that needs an entry"
has "$out" "bring-current-audit.sh add --bead MI2 --path <path>" "…and the command that records one"
eq "$(rec_of AN1)" "null" "nothing is recorded on the anchor"
eq "$(cat "$STUB_RO_LOG")" "" "…and nothing reopened"
store "[$(child MI2 "$(audit_meta "$(entry v.txt bogus)")"), $(anchorrow AN1)]"
out=$(guard --bead MI2 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "3" "an entry whose rating is neither routine nor judgment is refused too"
has "$out" "rating is bogus" "…and says what is wrong with it"
store "[$(child MI2 "$(audit_meta "$(entry w.txt)")"), $(anchorrow AN1)]"
out=$(guard --bead MI2 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "3" "an entry for a path the round did not touch covers nothing"

echo "# guard: a covered conflicted round is stored and routed to triage, and GitHub is not touched"
store "[$(child MI3 "$(audit_meta "$(entry v.txt judgment)")"), $(anchorrow AN1)]"
reviews "$(approve human1 501)"
fresh
out=$(guard --bead MI3 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "triage is reopened" "…reporting the round routed to triage"
REC=$(rec_of AN1)
eq "$(printf '%s' "$REC" | jq -r '.class')" "conflicted" "the record is conflicted"
eq "$(printf '%s' "$REC" | jq -r '.bead')" "MI3" "…names the bead that pushed it"
eq "$(printf '%s' "$REC" | jq -r '.from')" "$A" "…and where the round began"
eq "$(printf '%s' "$REC" | jq -r '.audit[0].path + " " + .audit[0].rating')" "v.txt judgment" "the worker's entry is stored with the record"
has "$(printf '%s' "$REC" | jq -r '.evidence[] | select(.path == "v.txt") | .detail')" "the merge base had lines" "…beside the guard's evidence for it"
eq "$(printf '%s' "$REC" | jq -r '.triage')" "null" "triage has not ruled yet"
eq "$(meta AN1 bring_current_reopened)" "triage" "triage is the lane the round reopens"
ROUND_AT=$(meta AN1 bring_current_round_at)
case "$ROUND_AT" in 20*Z) ok "…stamped with the round's time" ;; *) bad "bring_current_round_at is '$ROUND_AT'" ;; esac
has "$(cat "$STUB_RO_LOG")" "supersede-lane --anchor AN1 --lane triage" "the triage lane's standing review is superseded"
eq "$(cat "$STUB_GH_LOG")" "" "no GitHub read, and no approval dismissed: the guard renders no verdict"

echo "# guard: a re-run of the same round keeps its time"
fresh
out=$(guard --bead MI3 --from "$MODIFY_H" --to "$MODIFY_H"); rc=$?
eq "$rc" "3" "without the stamp, a re-run whose push added nothing is refused: nothing records the start"
has "$out" "nothing records where MI3's work" "…and says what to stamp"
store "[$(child MI3 "$(audit_meta "$(entry v.txt judgment)"),\"bring_current_from\":\"$A\""), $(jq -c '.[] | select(.id == "AN1")' "$STUB_STORE")]"
out=$(guard --bead MI3 --from "$MODIFY_H" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "with the resume stamp a re-run after the push still reads the round"
eq "$(meta AN1 bring_current_round_at)" "$ROUND_AT" "…and keeps the round's time"
eq "$(meta AN1 bring_current_reopened)" "triage" "…and reopens triage once"

echo "# guard: once triage has ruled on the round, a re-run reopens nothing"
jq -c 'map(if .id == "AN1" then .metadata.bring_current_record = ((.metadata.bring_current_record | fromjson) | .triage = {review: "RV9", reopen: [], add: [], dismiss: false, reason: "routine", at: "x"} | tojson) else . end)' "$STUB_STORE" > "$STUB_STORE.n" && mv "$STUB_STORE.n" "$STUB_STORE"
fresh
out=$(guard --bead MI3 --from "$MODIFY_H" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "triage has ruled on it" "…saying the round is settled"
eq "$(rec_of AN1 | jq -r '.triage.review')" "RV9" "the ruling stays in the record"
eq "$(cat "$STUB_RO_LOG")" "" "…and nothing is reopened again"

echo "# guard: an anchor that opted out of review records the round and owes no triage"
store "[$(child MI4 "$(audit_meta "$(entry v.txt)")"), $(anchorrow AN1 | jq -c '.metadata.check_set = "none"')]"
fresh
out=$(guard --bead MI4 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "opts out of review" "…saying why no triage is owed"
eq "$(rec_of AN1 | jq -r '.class')" "conflicted" "the round is recorded"
eq "$(meta AN1 bring_current_reopened)" "<absent>" "…and no lane is reopened"

echo "# guard: a failed record write or supersede hands nothing off"
store "[$(child MI5 "$(audit_meta "$(entry v.txt)")"), $(anchorrow AN1)]"
fresh
out=$(STUB_UPDATE_FAIL="AN1" guard --bead MI5 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "a record that does not land exits 1"
eq "$(cat "$STUB_RO_LOG")" "" "…before any lane is reopened"
fresh
out=$(STUB_RO_RC=2 guard --bead MI5 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "1" "a supersede that fails exits 1, so the hand-off retries"

echo "# guard: on a merge-only bead a commit of its own owes entries; on a with-work bead it does not"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$FIXUP_H"
store "[$(child MI6 ",\"bring_current_from\":\"$A\",\"bring_current_scope\":\"merge-only\""), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI6 --to "$FIXUP_H"); rc=$?
eq "$rc" "3" "a merge-only bead's fix-up commit owes an entry"
has "$out" "NEEDS AN ENTRY  a.txt" "…for the file it changed"
store "[$(child MI6 ",\"bring_current_from\":\"$A\",\"bring_current_scope\":\"with-work\""), $(anchorrow AN1)]"
fresh
out=$(guard --bead MI6 --to "$FIXUP_H"); rc=$?
eq "$rc" "0" "a with-work bead's own commit owes none"
eq "$(rec_of AN1 | jq -r '.class')" "clean" "…and its clean merge is recorded clean"
has "$(rec_of AN1 | jq -r '.evidence[].detail')" "a commit of the bead's own work" "…with its own commit as a note"

echo "# guard: a pre-open-rebase child is guarded, whatever its title, through its anchor"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
PRE_CHILD=$(child MI7 "$(audit_meta "$(entry v.txt)")" "Merge main into polecat/x1: base moved, the branch no longer merges" \
  | jq -c 'del(.metadata.pr_number, .metadata.pr_url, .metadata.existing_pr)')
PRE_ANCHOR=$(anchorrow AN1 | jq -c '.metadata.merge_result = "pre_open_gate" | del(.metadata.pr_number, .metadata.pr_url)')
store "[$PRE_CHILD, $PRE_ANCHOR]"
fresh
out=$(guard --bead MI7 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(rec_of AN1 | jq -r '.class')" "conflicted" "the pre-open anchor carries the round"
eq "$(meta AN1 bring_current_reopened)" "triage" "…and triage is reopened"

echo "# guard: an anchor the refinery re-queued is guarded as its own anchor"
REQ=$(anchorrow AN2 "$(audit_meta "$(entry v.txt)"),\"bring_current_from\":\"$A\",\"bring_current_scope\":\"merge-only\",\"existing_pr\":\"https://github.com/zook/gc-toolkit/pull/1\"" \
  | jq -c 'del(.metadata.merge_result, .metadata.pr_number)')
store "[$REQ]"
fresh
out=$(guard --bead AN2 --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(rec_of AN2 | jq -r '.class')" "conflicted" "the re-queued anchor records its own round"
has "$(cat "$STUB_RO_LOG")" "--anchor AN2 --lane triage" "…and reopens its own triage lane"

echo "# guard: an earlier round still awaiting triage rides into the next round's record"
R="$CLEAN_R"; A="$CLEAN_A"; git -C "$R" reset -q --hard "$CLEAN_H"
EARLIER=$(jq -nc --arg h "$MODIFY_H" '{head: $h, from: "f0", target: "main", bead: "MI0", class: "conflicted",
  evidence: [{covered: true, kind: "conflict", path: "v.txt", commit: "x", detail: "conflicted where the merge base had lines"}],
  audit: [{path: "v.txt", collided: "c", resolution: "r", check: "k", rating: "judgment"}], triage: null}')
store "[$(child MI8), $(anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$EARLIER" | jq -Rc .),\"bring_current_reopened\":\"triage\",\"bring_current_round_at\":\"2026-10-01T00:00:00Z\"")]"
fresh
out=$(guard --bead MI8 --from "$A" --to "$CLEAN_H"); rc=$?
eq "$rc" "0" "a clean round on top of an undecided one exits 0"
REC=$(rec_of AN1)
eq "$(printf '%s' "$REC" | jq -r '.class')" "conflicted" "the record stays conflicted: the earlier round still owes triage"
eq "$(printf '%s' "$REC" | jq -r '.audit[0].path + "@" + .audit[0].round')" "v.txt@$MODIFY_H" "…carrying the earlier entry, tagged with its round"
eq "$(printf '%s' "$REC" | jq -r '.from')" "f0" "…from where the earlier round began"
eq "$(printf '%s' "$REC" | jq -r '.head')" "$CLEAN_H" "…up to the new head"

echo "# guard: a bead that does not name its anchor finds it on the branch"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" reset -q --hard "$MODIFY_H"
store "[$(child MI9 "$(audit_meta "$(entry v.txt)")" | jq -c 'del(.metadata.anchor_bead)'), $(anchorrow AN9)]"
fresh
out=$(guard --bead MI9 --from "$A" --to "$MODIFY_H"); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(rec_of AN9 | jq -r '.class')" "conflicted" "the round lands on the branch's anchor"

# --- decide ----------------------------------------------------------------------
decide() { ( cd "$R" && "$SUT" decide "$@" 2>&1 ); }
ROUND=$(jq -nc --arg h "$MODIFY_H" '{head: $h, from: "f0", target: "main", bead: "MI3", class: "conflicted",
  evidence: [{covered: true, kind: "conflict", path: "v.txt", commit: "x", detail: "conflicted where the merge base had lines that one or both sides changed, so git could not merge it on its own"}],
  audit: [{path: "v.txt", collided: "main set x to 3 for the new default while the branch set it to 2 for its feature", resolution: "kept 2 because the feature reads it", check: "the feature path that reads x", rating: "judgment"}], triage: null}')
round_anchor() { # [check_set]
  anchorrow AN1 ",\"bring_current_record\":$(printf '%s' "$ROUND" | jq -Rc .),\"bring_current_reopened\":\"triage\",\"bring_current_round_at\":\"2026-10-01T00:00:00Z\"" \
    | jq -c --arg cs "${1:-correctness,triage,arch}" '.metadata.check_set = $cs'
}

echo "# decide: refuses with no conflicted round, or a lane the anchor does not declare"
store "[$(anchorrow AN1)]"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen none --reason "routine"); rc=$?
eq "$rc" "1" "no conflicted round to rule on exits 1"
store "[$(round_anchor)]"
out=$(decide --anchor AN1 --review-bead RV1 --reopen pm --reason "x"); rc=$?
eq "$rc" "1" "a lane the anchor does not declare is refused"
has "$out" "does not declare" "…saying so"
eq "$(rec_of AN1 | jq -r '.triage')" "null" "…and nothing is written"
out=$(decide --anchor AN1 --review-bead RV1 --reopen none --reason " "); rc=$?
eq "$rc" "1" "a ruling with no reason is refused"

echo "# decide: nothing reopens"
store "[$(round_anchor)]"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen none --reason "adjacent edits, both kept" --body-out "$TMP/body1"); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(rec_of AN1 | jq -c '.triage | {review, reopen, dismiss, reason}')" '{"review":"RV1","reopen":[],"dismiss":false,"reason":"adjacent edits, both kept"}' "the ruling is recorded in the anchor's record"
eq "$(meta AN1 bring_current_reopened)" "triage" "no lane is added"
eq "$(cat "$STUB_RO_LOG")$(cat "$STUB_GH_LOG")" "" "…nothing is superseded and GitHub is not touched"
has "$(cat "$TMP/body1")" "**Triage:** nothing reopens. Why: adjacent edits, both kept." "the rendered account carries the ruling"
has "$(cat "$TMP/body1")" "Collided: main set x to 3 for the new default while the branch set it to 2 for its feature." "…and each entry's collision"
has "$(cat "$TMP/body1")" "Decided: kept 2 because the feature reads it." "…what was decided"
has "$(cat "$TMP/body1")" "Check: the feature path that reads x." "…what to check"
has "$(cat "$TMP/body1")" "Git: conflicted where the merge base had lines" "…and the guard's evidence"
out=$(decide --anchor AN1 --review-bead RV2 --reopen none --reason "again"); rc=$?
eq "$rc" "1" "a second review cannot re-rule a round already ruled on"

echo "# decide: lanes run again, and added lanes count as reopened"
store "[$(round_anchor)]"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen correctness --add arch --reason "the merged default changes behaviour" --body-out "$TMP/body2"); rc=$?
eq "$rc" "0" "it exits 0"
eq "$(meta AN1 bring_current_reopened)" "triage,correctness,arch" "the reopened lanes are unioned in"
has "$(cat "$STUB_RO_LOG")" "supersede-lane --anchor AN1 --lane correctness" "the reopened lane is superseded"
hasnt "$(cat "$STUB_RO_LOG")" "--lane arch" "…an added lane has no review to supersede"
has "$(cat "$TMP/body2")" "arch and correctness run again on the merged code" "…and the account says what reruns"
fresh
out=$(STUB_RO_RC=2 decide --anchor AN1 --review-bead RV1 --reopen correctness --reason "the merged default changes behaviour"); rc=$?
eq "$rc" "2" "a supersede that fails exits 2, so the verdict call retries"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen none --reason "changed my mind"); rc=$?
eq "$rc" "0" "a retry by the same review exits 0"
has "$(cat "$STUB_RO_LOG")" "--lane correctness" "…and carries out what was recorded, not the new flags"
eq "$(rec_of AN1 | jq -r '.triage.reason')" "the merged default changes behaviour" "…leaving the ruling as recorded"

echo "# decide: a dismissal files the visit composed from the audit first, then re-requests and dismisses"
store "[$(round_anchor)]"
reviews "$(approve human1 501),$(approve human2 502),$(approve gc-city-bot 503)"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen correctness --dismiss-approval --reason "the merge chose the branch value over main's new default"); rc=$?
eq "$rc" "0" "it exits 0 once the visit holds the merge"
has "$(cat "$STUB_ESC_LOG")" "--subject AN1 --key bring-current-dismissal.1.$MODIFY_H" "the visit is filed on the anchor, keyed to the round"
has "$(cat "$STUB_ESC_LOG")" "PR#1 approval dismissed: triage ruled that bringing it current took judgment" "…headed by what happened"
has "$(cat "$STUB_ESC_LOG")" "the approval from human1 and human2 did not see" "…naming the approvers"
has "$(cat "$STUB_ESC_LOG")" "Collided: main set x to 3 for the new default" "…telling what collided, from the audit"
has "$(cat "$STUB_ESC_LOG")" "Triage ruled: the merge chose the branch value over main's new default." "…and why triage dismissed"
has "$(cat "$STUB_ESC_LOG")" "Your call: review the change on the PR and approve again" "…and what the operator decides"
V=$(visit_of)
hasnt "$V" "<none>" "an open visit stands"
eq "$(meta "$V" 'gc.continuation_group')" "AN1" "…on the anchor, so it holds the anchor's merge"
has "$(cat "$STUB_GH_LOG")" "reviewers[]=human1" "human1 is re-requested"
has "$(cat "$STUB_GH_LOG")" "reviewers[]=human2" "…and human2"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/1/reviews/501/dismissals" "human1's approval is dismissed"
has "$(cat "$STUB_GH_LOG")" "DISMISS repos/zook/gc-toolkit/pulls/1/reviews/502/dismissals" "…and human2's"
hasnt "$(cat "$STUB_GH_LOG")" "reviews/503/dismissals" "the city's own approval is never touched"
has "$(cat "$STUB_GH_LOG")" "v.txt: kept 2 because the feature reads it." "the dismissal note is composed from the audit"
has "$(cat "$STUB_GH_LOG")" "Triage: the merge chose the branch value" "…and carries triage's reason"
order_ok "ESCALATE" "DISMISS" && ok "the visit is filed before any dismissal" || bad "the visit must be filed before any dismissal"
order_ok "requested_reviewers" "reviews/501/dismissals" && ok "…and the re-request comes before the dismissal" || bad "the re-request must come before the dismissal"
eq "$(rec_of AN1 | jq -r '.triage.dismiss')" "true" "the ruling records the dismissal"

echo "# decide: no standing approval dismisses nothing; a visit that does not land dismisses nothing"
store "[$(round_anchor)]"
reviews "$(approve gc-city-bot 503)"
fresh
out=$(decide --anchor AN1 --review-bead RV1 --reopen none --dismiss-approval --reason "judgment"); rc=$?
eq "$rc" "0" "it exits 0"
has "$out" "no approval stands to dismiss" "the city's own approval is no approval"
eq "$(cat "$STUB_ESC_LOG")" "" "no visit is filed"
store "[$(round_anchor)]"
reviews "$(approve human1 501)"
fresh
out=$(STUB_ESC_RC=1 decide --anchor AN1 --review-bead RV1 --reopen none --dismiss-approval --reason "judgment"); rc=$?
eq "$rc" "2" "a visit that does not land exits 2, so the verdict call retries"
hasnt "$(cat "$STUB_GH_LOG")" "DISMISS" "…and nothing is dismissed"
store "[$(round_anchor)]"
fresh
out=$(STUB_DISMISS_RC=1 decide --anchor AN1 --review-bead RV1 --reopen none --dismiss-approval --reason "judgment"); rc=$?
eq "$rc" "0" "a dismissal that does not land exits 0: the visit holds the merge"
has "$(notes "$(visit_of)")" "the approval from human1 (review 501) could not be dismissed" "…and the visit carries the failure"
store "[$(round_anchor)]"
fresh
out=$(STUB_SELF_LOGIN="" decide --anchor AN1 --review-bead RV1 --reopen none --dismiss-approval --reason "judgment"); rc=$?
eq "$rc" "2" "an unresolved acting login exits 2"
eq "$(cat "$STUB_ESC_LOG")" "" "…filing no visit"

# --- the resume block -------------------------------------------------------------
echo "# the filers' rejection prefixes are the ones the resume block reads as merge-only"
RESUME=$(awk '/# >>> rejected-branch-resume-mode$/ {f=1; next} /# <<< rejected-branch-resume-mode$/ {f=0} f' \
  "$ROOT/formulas/mol-polecat-work.toml" | sed 's/{{base_branch}}/main/g')
[ -n "$RESUME" ] && ok "the resume block is extracted from the formula" || bad "the resume block is not extracted from the formula"
has "$RESUME" '"stale base at head "*|"Conflicts with "*) RESUME_SCOPE=merge-only' "the block reads a conflict or stale-base rejection as merge-only"
eq "$(grep -c '"stale base at head \$head_oid: PR#\$num conflicts with' "$HERE/pr-facts.sh")" "1" "pr-facts.sh's merge-in child is rejected 'stale base at head …'"
eq "$(grep -c 'rejection_reason="stale base at head \$head_oid:' "$HERE/pre-open-rebase.sh")" "1" "…and so is pre-open-rebase.sh's child"
eq "$(grep -c 'REJECT_REASON="Conflicts with \$TARGET at' "$ROOT/formulas/mol-refinery-patrol.toml")" "1" "the refinery's prepare re-queue is rejected 'Conflicts with …'"

echo "# the resume block records the start and scope before its merge, and the guard reads from there"
R="$MODIFY_R"; A="$MODIFY_A"; git -C "$R" merge --abort >/dev/null 2>&1; git -C "$R" reset -q --hard "$A"
store "[$(child MI12 ",\"rejection_reason\":\"stale base at head sha-1: PR#1 conflicts with main.\"$(audit_meta "$(entry stale.txt)")"), $(anchorrow AN1)]"
( cd "$R" && WORK_BEAD_ID=MI12 bash -c "$RESUME" ) >/dev/null 2>&1
eq "$(meta MI12 bring_current_from)" "$A" "the stamp is the PR head the round started from"
eq "$(meta MI12 bring_current_scope)" "merge-only" "…a stale-base rejection makes the round merge-only"
eq "$(meta MI12 conflict_audit)" "<absent>" "…the last round's audit is cleared"
eq "$(meta MI12 rejection_reason)" "<absent>" "…and the resume cleared the rejection as before"
eq "$(git -C "$R" diff --name-only --diff-filter=U)" "v.txt" "the merge it ran stopped on the conflict"
resolve v.txt 'x=2\n'
H=$(git -C "$R" rev-parse HEAD)
fresh
out=$(guard --bead MI12 --from "$H" --to "$H"); rc=$?
eq "$rc" "3" "a re-run after the push still reads the round from the stamp, and its audit is owed"
has "$out" "NEEDS AN ENTRY  v.txt" "…naming the conflict"
( cd "$R" && "$SD/bring-current-audit.sh" add --bead MI12 --path v.txt --rating judgment \
    --collided "main set x to 3 while the branch set it to 2" --resolution "kept 2" --check "x" ) >/dev/null 2>&1
out=$(guard --bead MI12 --from "$H" --to "$H"); rc=$?
eq "$rc" "0" "with the entry recorded the hand-off proceeds"
eq "$(rec_of AN1 | jq -r '.audit[0].resolution')" "kept 2" "…and the entry rides into the anchor's record"
store "[$(child MI13 ",\"rejection_reason\":\"Review feedback on PR#1 is unanswered at head x.\"")]"
git -C "$R" reset -q --hard "$A"
( cd "$R" && WORK_BEAD_ID=MI13 bash -c "$RESUME" ) >/dev/null 2>&1
eq "$(meta MI13 bring_current_scope)" "with-work" "a feedback rejection carries work of its own"
STUB_UPDATE_FAIL="MI14" store "[$(child MI14 ",\"rejection_reason\":\"stale base at head sha-1: x\"")]"
git -C "$R" merge --abort >/dev/null 2>&1; git -C "$R" reset -q --hard "$A"
( cd "$R" && STUB_UPDATE_FAIL="MI14" WORK_BEAD_ID=MI14 bash -c "$RESUME" ) >/dev/null 2>&1; rc=$?
eq "$rc" "1" "a stamp that does not read back stops the block"
eq "$(git -C "$R" rev-parse HEAD)" "$A" "…before it merges anything"

echo "# the audit-entry block passes the flags the audit script reads"
ENTRY_BLOCK=$(awk '/# >>> bring-current-audit-entry$/ {f=1; next} /# <<< bring-current-audit-entry$/ {f=0} f' "$ROOT/formulas/mol-polecat-work.toml")
[ -n "$ENTRY_BLOCK" ] && ok "the audit-entry block is extracted from the formula" || bad "the audit-entry block is not extracted from the formula"
for flag in --bead --path --rating --collided --resolution --check; do
  case "$ENTRY_BLOCK" in *"$flag "*) : ;; *) bad "the audit-entry block does not pass $flag"; continue ;; esac
  grep -q -- "      $flag) " "$HERE/bring-current-audit.sh" && ok "…$flag is one the audit script's add reads" || bad "bring-current-audit.sh add does not read $flag"
done

echo "# the stop-and-ask block asks once, aborts the merge, pushes nothing, parks or holds, and drains"
UNRES=$(awk '/# >>> bring-current-unresolvable$/ {f=1; next} /# <<< bring-current-unresolvable$/ {f=0} f' "$ROOT/formulas/mol-polecat-work.toml" \
  | sed -e 's/"<file>"/"v.txt"/' \
        -e 's/"<the two intents that met>"/"main set x to 3 while the branch set it to 2"/' \
        -e 's/"<the one decision you need>"/"which default wins?"/' \
        -e 's/"<the step you hold, e.g. mol-polecat-work.workspace-setup>"/"mol-polecat-work.workspace-setup"/')
[ -n "$UNRES" ] && ok "the stop-and-ask block is extracted from the formula" || bad "the stop-and-ask block is not extracted from the formula"
hasnt "$UNRES" "git push" "the block pushes nothing"
PK="$TMP/askpack/assets/scripts"; mkdir -p "$PK"
cat > "$PK/bring-current-audit.sh" <<'S'
#!/usr/bin/env bash
printf 'ASK %s\n' "$*" >> "${ASK_LOG:?}"; exit "${ASK_RC:-0}"
S
cat > "$PK/molecule-hold.sh" <<'S'
#!/usr/bin/env bash
printf 'HOLD %s\n' "$*" >> "${ASK_LOG:?}"; exit "${HOLD_RC:-0}"
S
chmod +x "$PK/bring-current-audit.sh" "$PK/molecule-hold.sh"
export ASK_LOG="$TMP/ask.log"
unres() { ( cd "$R" && GC_PACK_DIR="$TMP/askpack" WORK_BEAD_ID="$1" bash -c "$UNRES" ) >/dev/null 2>&1; }
R="$MODIFY_R"; A="$MODIFY_A"; restart; bring
store "[$(child MI20)]"
: > "$STUB_GC_LOG"; : > "$ASK_LOG"
unres MI20; rc=$?
eq "$rc" "0" "a bead with no molecule: the block exits 0"
has "$(cat "$ASK_LOG")" "ASK ask --bead MI20 --path v.txt --collided main set x to 3 while the branch set it to 2 --question which default wins?" "the question is asked once, with what collided"
eq "$(git -C "$R" rev-parse HEAD)" "$A" "the merge is aborted: HEAD is the head last reviewed"
[ -f "$R/.git/MERGE_HEAD" ] && bad "a merge is still in progress" || ok "…and no merge is left in progress"
eq "$(meta MI20 gc.routed_to)" "human" "the bead parks to a person"
eq "$(bassignee MI20)" "" "…its assignee cleared"
has "$(cat "$STUB_GC_LOG")" "runtime drain-ack" "…and the session drains"
restart; bring
store "[$(child MI21)]"
: > "$STUB_GC_LOG"; : > "$ASK_LOG"
( cd "$R" && GC_PACK_DIR="$TMP/askpack" WORK_BEAD_ID=MI21 CLAIMED_STEP_BEAD_ID=ST1 bash -c "$UNRES" ) >/dev/null 2>&1; rc=$?
eq "$rc" "0" "a molecule's step: the block exits 0"
has "$(cat "$ASK_LOG")" "HOLD --step mol-polecat-work.workspace-setup --bead ST1" "the molecule is held at the step"
eq "$(meta MI21 gc.routed_to)" "<absent>" "…and the bead is not parked as well"
restart; bring
store "[$(child MI22)]"
: > "$STUB_GC_LOG"; : > "$ASK_LOG"
( cd "$R" && ASK_RC=1 GC_PACK_DIR="$TMP/askpack" WORK_BEAD_ID=MI22 bash -c "$UNRES" ) >/dev/null 2>&1; rc=$?
eq "$rc" "1" "a question that reached no visit exits 1"
[ -f "$R/.git/MERGE_HEAD" ] && ok "…leaving the merge in progress, for the retry" || bad "the merge must not be aborted before a visit asks the question"
hasnt "$(cat "$STUB_GC_LOG")" "drain-ack" "…and not draining"
restart

echo "# every metadata key the bring-current scripts and their formula blocks write is registered"
REGISTERED=$(sed -n '/^# The metadata-key registry/,$p' "$ROOT/lifecycle/lifecycle.toml" \
  | sed 's/#.*//' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)
WRITTEN=$( { cat "$HERE/bring-current-guard.sh" "$HERE/bring-current-audit.sh"; printf '%s\n%s\n' "$RESUME" "$UNRES"; } \
  | grep -oE -- '--(set|unset)-metadata "?[A-Za-z_][A-Za-z0-9_.]*' | sed -E 's/^--(set|unset)-metadata "?//' | sort -u)
has "$WRITTEN" "bring_current_record" "the extraction reads the guard's writes"
has "$WRITTEN" "conflict_audit" "…and the audit script's"
has "$WRITTEN" "bring_current_scope" "…and the resume block's"
UNREGISTERED=$(printf '%s\n' "$WRITTEN" | grep -Fxv -f <(printf '%s\n' "$REGISTERED") | tr '\n' ' ' | sed 's/ *$//') || true
eq "$UNREGISTERED" "" "every key they write is registered in lifecycle.toml"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
