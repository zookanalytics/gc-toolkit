#!/usr/bin/env bash
# Tests for tools/measure.sh over repositories the suite builds, since the tool
# reads only git objects. It sources test-harness.sh for the assertions only,
# because harness_init would stub git out.
#
# Covered: each end of a change counted on its own (a file a symlink or a
# binary replaces, a symlink or a binary a file replaces, a file whose last line
# repeats its replacing link's target, a plain edit), and the tree count leaving
# symlinks and binaries out; the repository's own agent instructions counted as
# docs; --pr's size section, measured from the merge base, with a row per
# subsystem the change touches, the kinds beside the pack, and the lines the
# change adds to each file the deletion plan lists at the merge base; --pr
# printing nothing for a merge base that does not carry the tool; and the shape
# of every row in tools/deletion-plan.tsv.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/measure.sh"
PLAN="$HERE/deletion-plan.tsv"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-measure-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=../assets/scripts/test-harness.sh
. "$HERE/../assets/scripts/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

# None of the session's repository settings may reach the git the tool drives.
unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --file "$GIT_CONFIG_GLOBAL" user.name T
git config --file "$GIT_CONFIG_GLOBAL" user.email t@e.com
git config --file "$GIT_CONFIG_GLOBAL" init.defaultBranch main

commit() { git add -A && git commit -q -m "$1"; }
# A kind's lines, from the kind table the tool prints first.
kind() { printf '%s\n' "$1" | awk -v k="$2" '$1 == k && NF == 2 { print $2; exit }'; }

mkdir -p "$TMP/ends/assets/scripts" && cd "$TMP/ends" && git init -q
printf 'a\nb\nc\n' > assets/scripts/to-link.sh
printf 'one\n' > assets/scripts/target.sh
ln -s target.sh assets/scripts/from-link.sh
printf 'p\nq\n' > assets/scripts/to-binary.sh
printf 'x\0y' > assets/scripts/from-binary.sh
commit base
BASE=$(git rev-parse HEAD)

echo "# each end of a change counts on its own"
git rm -q assets/scripts/to-link.sh && ln -s target.sh assets/scripts/to-link.sh && commit "a file becomes a symlink"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" -3 "a 3-line file a symlink replaces takes its 3 lines out"
git rm -q assets/scripts/from-link.sh && printf '1\n2\n3\n4\n' > assets/scripts/from-link.sh && commit "a symlink becomes a file"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" 4 "a 4-line file that replaces a symlink brings its 4 lines in"
printf 'bin\0ary' > assets/scripts/to-binary.sh && commit "a text file becomes binary"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" -2 "a 2-line file a binary replaces takes its 2 lines out"
printf 'now\ntext\nhere\n' > assets/scripts/from-binary.sh && commit "a binary becomes text"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" 3 "a 3-line file that replaces a binary brings its 3 lines in"
printf 'one\ntwo\nthree\n' > assets/scripts/target.sh && commit "an edit"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" 2 "an edit counts the lines it adds less the lines it removes"
eq "$(kind "$("$SUT" "$BASE" HEAD)" code)" 4 "a range counts each path at its two ends: -3, +4, -2, +3 and +2"
# git diffs a changed type's two blobs as text, so a link's target can match the
# file's last line and leave that line out of both of git's counts.
printf 'a\ntarget.sh' > assets/scripts/shares.sh && commit "a file ends with a link's target"
git rm -q assets/scripts/shares.sh && ln -s target.sh assets/scripts/shares.sh && commit "a symlink to that target replaces it"
eq "$(kind "$("$SUT" HEAD^ HEAD)" code)" -2 "a file a symlink replaces takes every line out, the one matching the link's target too"

echo "# the tree count leaves symlinks and binaries out"
out=$("$SUT" HEAD)
has "$out" "lines at $(git rev-parse --short HEAD)" "a single ref counts the tree at it"
eq "$(kind "$out" code)" 10 "only the three text files count: 3, 4 and 3 lines"

echo "# the repository's own agent instructions are docs, beside the pack"
mkdir -p "$TMP/instructions" && cd "$TMP/instructions" && git init -q
printf 'one\ntwo\n' > AGENTS.md
printf '@AGENTS.md\n' > CLAUDE.md
commit "instructions"
out=$("$SUT" HEAD)
eq "$(kind "$out" docs)" 3 "AGENTS.md and CLAUDE.md count as docs"
eq "$(kind "$out" code)" 0 "…and neither counts as code"
hasnt "$out" "unplaced" "…so no subsystem row is left to place them"

echo "# --pr: the size section of a change, from its merge base"
mkdir -p "$TMP/pr" && cd "$TMP/pr" && git init -q
mkdir -p tools assets/scripts agents/polecat
cp "$SUT" tools/measure.sh
printf '%s\n' '# a comment' 'assets/scripts/retiring.sh	tk-retire' \
  'assets/scripts/retiring.test.sh	tk-retire' 'assets/scripts/gone.sh	tk-gone' > tools/deletion-plan.tsv
printf 'r1\nr2\n' > assets/scripts/retiring.sh
printf 't1\n' > assets/scripts/retiring.test.sh
printf 'g1\ng2\ng3\n' > assets/scripts/gone.sh
printf 'k\n' > assets/scripts/kept.sh
commit "main"
git checkout -q -b topic
printf 'r3\nr4\n' >> assets/scripts/retiring.sh
printf 't2\n' >> assets/scripts/retiring.test.sh
git rm -q assets/scripts/gone.sh
printf 'n1\nn2\nn3\nn4\nn5\n' > assets/scripts/new.sh
printf 'n\n' > assets/scripts/new.test.sh
printf 'k2\n' >> assets/scripts/kept.sh
printf 'p1\np2\np3\n' > agents/polecat/prompt.template.md
mkdir -p docs && printf 'doc\n' > docs/page.md
printf 'assets/scripts/kept.sh\ttk-late\n' >> tools/deletion-plan.tsv
commit "the change"
git checkout -q main
printf 'm1\nm2\n' > assets/scripts/main-only.sh && commit "main moves on"
MB=$(git merge-base main topic)
out=$("$SUT" --pr main topic); rc=$?
eq "$rc" 0 "--pr exits 0"
has "$out" "Net lines from the merge base \`$(git rev-parse --short "$MB")\`: runtime +8 and tests +2." \
  "the totals run from the merge base, so main's later commit is not counted"
has "$out" "| Subsystem | Runtime | Tests |
|---|---:|---:|
| shared | +5 | +2 |
| work | +3 | 0 |" "a row per subsystem the change touches, the most changed first"
has "$out" "Beside the pack: docs +1 and tooling +1." "the kinds beside the pack follow the table"
has "$out" "- \`assets/scripts/retiring.sh\` gains 2 lines, and tk-retire retires it.
- \`assets/scripts/retiring.test.sh\` gains 1 line, and tk-retire retires it." \
  "each planned file the change adds to is named with the lines it gains and the bead that retires it"
hasnt "$out" "gone.sh" "a planned file the change only deletes is not named"
hasnt "$out" "tk-late" "a row the change adds to the plan is not read, since the plan is read at the merge base"
eq "$("$SUT" --pr "$MB" topic)" "$out" "the merge base itself as BASE measures the same change"

git checkout -q -b docs-only main
mkdir -p docs && printf 'd\n' > docs/other.md && commit "docs only"
out=$("$SUT" --pr main docs-only)
has "$out" "No runtime or test lines change from the merge base \`$(git rev-parse --short main)\`." \
  "a change with no runtime or test lines says so"
hasnt "$out" "| Subsystem" "…with no subsystem table"
has "$out" "Beside the pack: docs +1." "…and still names the kinds beside the pack"
hasnt "$out" "deletion plan retires" "a change that adds to no planned file names none"

echo "# --pr prints nothing for a merge base that does not carry the tool"
mkdir -p "$TMP/elsewhere/src" && cd "$TMP/elsewhere" && git init -q
printf 'a\n' > src/a.sh && commit "a repository that does not measure itself"
git checkout -q -b topic
mkdir -p tools && cp "$SUT" tools/measure.sh && printf 'b\n' >> src/a.sh && commit "the head adds the tool"
out=$("$SUT" --pr main topic); rc=$?
eq "$rc" 0 "--pr exits 0"
eq "$out" "" "…and prints nothing: the rules describe gc-toolkit's tree"

echo "# usage"
"$SUT" --pr main >/dev/null 2>&1; eq "$?" 2 "--pr takes exactly a BASE and a HEAD"
"$SUT" a b c >/dev/null 2>&1; eq "$?" 2 "three refs are a usage error"

echo "# every row of tools/deletion-plan.tsv names a path and the bead that retires it"
eq "$(awk -F'\t' '!/^#/ && !(NF == 2 && $1 ~ /^[^ ]+$/ && $2 ~ /^[a-z]+-[0-9a-z]+(\.[0-9]+)*$/)' "$PLAN")" "" \
  "each row is a path, a tab and a bead id"
eq "$(awk -F'\t' '!/^#/ { print $1 }' "$PLAN" | LC_ALL=C sort | uniq -d)" "" "no path has two rows"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
