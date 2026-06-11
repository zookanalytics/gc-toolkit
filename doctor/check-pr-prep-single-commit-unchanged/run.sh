#!/usr/bin/env bash
# Pack doctor check: mol-upstream-gc-pr-prep preserves the single-commit
# (N=1) path after batch (multi-commit) support was added (tk-ur4o2).
#
# Batch support generalized metadata.commit_sha into an ordered SHA list and
# added a branch_name var. The backward-compat contract is: a single SHA with
# no branch_name MUST still produce branch `upstream-pr/<short-sha>`, a single
# cherry-pick, and a single-commit draft -- byte-for-byte today's behavior.
# This is the regression case for that contract: it pins the structural pieces
# that keep the N=1 path intact, so a later refactor of the batch loop cannot
# silently drop the single-commit special case.
#
# Invariants pinned:
#   1. [vars.commit_sha] is still `required = true` (the N=1 dispatch contract).
#   2. [vars.branch_name] exists and defaults to "" -- omitting `as <branch>`
#      must select today's upstream-pr/<short-sha> naming, not a batch name.
#   3. workspace-setup keeps the N=1 branch rule: a `[ "$N" -eq 1 ]` arm that
#      sets BRANCH="upstream-pr/$SHORT_SHA" from `rev-parse --short`.
#   4. cherry-pick applies each SHA via a `for SHA in $COMMIT_SHA` loop running
#      `git cherry-pick "$SHA"` (N=1 == one iteration == one pick).
#
# The shell-literal greps use -F (fixed strings): they assert the exact bash
# the formula's polecat runs, not prose about it.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

dir="${GC_PACK_DIR:-.}"
file="$dir/packs/gascity-keeper/formulas/mol-upstream-gc-pr-prep.toml"
violations=()

if [ ! -f "$file" ]; then
    echo "mol-upstream-gc-pr-prep.toml: missing file $file"
    exit 2
fi

# --- 1 + 2: var declarations, scoped to the right [vars.X] table. ---
# A bare grep for `required = true` / `default = ""` would mis-attribute
# (requesting_keeper is also required) -- so track the current var table.
report=$(awk '
    /^\[vars\.commit_sha\][[:space:]]*$/   { cur="commit_sha";  seen_commit=1; next }
    /^\[vars\.branch_name\][[:space:]]*$/  { cur="branch_name"; seen_branch=1; next }
    /^\[/                                   { cur="" }
    cur=="commit_sha"  && $0 ~ /required[[:space:]]*=[[:space:]]*true/ { commit_required=1 }
    cur=="branch_name" && $0 ~ /default[[:space:]]*=[[:space:]]*""/    { branch_default_empty=1 }
    END {
        printf "seen_commit=%d\n", seen_commit+0
        printf "seen_branch=%d\n", seen_branch+0
        printf "commit_required=%d\n", commit_required+0
        printf "branch_default_empty=%d\n", branch_default_empty+0
    }
' "$file")

extract() { echo "$report" | awk -F= -v k="$1" '$1==k {print $2; exit}'; }
seen_commit=$(extract seen_commit)
seen_branch=$(extract seen_branch)
commit_required=$(extract commit_required)
branch_default_empty=$(extract branch_default_empty)

[ "$seen_commit" = "1" ] || violations+=("[vars.commit_sha] table missing")
[ "$commit_required" = "1" ] || \
    violations+=("[vars.commit_sha] is no longer 'required = true' (N=1 dispatch contract broken)")
[ "$seen_branch" = "1" ] || \
    violations+=("[vars.branch_name] table missing (batch override var dropped)")
[ "$branch_default_empty" = "1" ] || \
    violations+=("[vars.branch_name] no longer defaults to \"\" -- omitting it must select today's upstream-pr/<short-sha> path")

# --- 3: workspace-setup keeps the N=1 -> upstream-pr/<short-sha> branch rule. ---
grep -qF '[ "$N" -eq 1 ]' "$file" || \
    violations+=("workspace-setup missing the single-commit guard '[ \"\$N\" -eq 1 ]'")
grep -qF 'BRANCH="upstream-pr/$SHORT_SHA"' "$file" || \
    violations+=("workspace-setup no longer sets BRANCH=\"upstream-pr/\$SHORT_SHA\" for the single-commit case")
grep -qF 'rev-parse --short' "$file" || \
    violations+=("workspace-setup no longer derives the short sha via 'rev-parse --short'")

# --- 4: cherry-pick applies each sha (N=1 == one pick). ---
grep -qF 'for SHA in $COMMIT_SHA' "$file" || \
    violations+=("cherry-pick no longer loops 'for SHA in \$COMMIT_SHA' over the ordered list")
grep -qF 'git cherry-pick "$SHA"' "$file" || \
    violations+=("cherry-pick no longer runs 'git cherry-pick \"\$SHA\"' per commit")

if [ ${#violations[@]} -eq 0 ]; then
    echo "mol-upstream-gc-pr-prep preserves the single-commit (N=1) path: required commit_sha, empty-default branch_name, upstream-pr/<short-sha> branch, per-sha cherry-pick"
    exit 0
fi

echo "${#violations[@]} single-commit (N=1) backward-compat gap(s) in mol-upstream-gc-pr-prep -- see tk-ur4o2"
for v in "${violations[@]}"; do
    echo "$v"
done
exit 2
