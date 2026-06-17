#!/usr/bin/env bash
# Regression test for tk-ehj8w: worktree-safe rebase-state detection in
# packs/gascity-keeper/formulas/mol-upstream-gc-rebase{,-rework}.toml.
#
# Those formulas run inside a LINKED git worktree (created by `git worktree
# add`). In a linked worktree, `.git` is a FILE (a gitdir pointer), not a
# directory, so a literal `.git/rebase-merge` path never resolves to anything —
# even mid-rebase. Every `[ -d .git/rebase-merge ]`-style guard therefore
# wrongly reported "not mid-rebase", which stranded the rebase/rework loop
# (start-fresh fired over an in-progress rebase; the rework entry guard fell
# through to a bogus classification=infeasible). The fix replaces each literal
# `.git/rebase-{merge,apply}` with `"$(git rev-parse --git-path
# rebase-{merge,apply})"`, which resolves the real per-worktree state dir
# (<main>/.git/worktrees/<name>/rebase-merge) whether `.git` is a directory
# (normal checkout) or a pointer file (linked worktree).
#
# This test drives a genuinely-conflicting rebase inside a linked worktree and
# proves both halves of the fix:
#   (a) the OLD literal-path guard is FALSE there         -> bug reproduced
#   (b) the NEW rev-parse guard is TRUE there             -> fix works
# It also exercises the secondary seqedit fix: the prefix-match awk drops a
# `pick <abbrev>` todo line for a full 40-char drop sha, and is a no-op when
# DROP_SHAS is empty.
#
# Fully hermetic: everything happens under a fresh temp dir with its own git
# repo and isolated git config. The real repo, its worktrees, and any live
# rebase (e.g. the held gc-5sacl rebase) are never touched. Exit 0 on success,
# 1 on any failed assertion.
#
# `set -e` is intentionally omitted: this test deliberately runs commands that
# return non-zero (a conflicting `git rebase`, `[ -d ]` probes expected false).
# Pass/fail is tracked explicitly and surfaced in the exit status.
set -uo pipefail

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
die() { echo "FATAL - $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap '
  git -C "$TMP/wt" rebase --abort >/dev/null 2>&1 || true
  git -C "$TMP/main" worktree remove --force "$TMP/wt" >/dev/null 2>&1 || true
  rm -rf "$TMP"
' EXIT

# Isolate from the operator git config (rebase.backend, hooks, identity, ...).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# --- Build a throwaway repo with two branches that conflict on one line. ------
git init -q "$TMP/main" || die "git init failed"
cd "$TMP/main" || die "cannot cd into repo"
printf 'base\n' > file.txt
git add file.txt
git commit -qm "base"
# Default branch name varies by git version (master vs main); capture it instead
# of hardcoding, so the test is robust across git versions.
MAIN_BRANCH="$(git symbolic-ref --short HEAD)" || die "cannot resolve default branch"

git checkout -q -b feature
printf 'feature change\n' > file.txt
git commit -qam "feature edit"

git checkout -q "$MAIN_BRANCH"
printf 'main change\n' > file.txt   # same line, different content -> conflict
git commit -qam "main edit"
cd "$TMP" || die "cannot return to temp root"

# --- Add a LINKED worktree on 'feature'; confirm .git is a FILE there. --------
git -C "$TMP/main" worktree add -q "$TMP/wt" feature || die "git worktree add failed"
[ -f "$TMP/wt/.git" ] || die "expected .git to be a FILE in the linked worktree"
ok ".git is a file in the linked worktree (the condition that breaks literal paths)"

# --- Drive a conflicting rebase so the worktree is genuinely mid-rebase. ------
cd "$TMP/wt" || die "cannot cd into worktree"
if git rebase "$MAIN_BRANCH" >/dev/null 2>&1; then
  die "rebase unexpectedly succeeded; expected a conflict to leave mid-rebase state"
fi
git rev-parse --verify -q REBASE_HEAD >/dev/null 2>&1 \
  || die "test setup error: not mid-rebase after a conflicting rebase"

# --- (bug) OLD literal-path guard is FALSE mid-rebase in a worktree. ----------
if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
  bad "OLD guard [ -d .git/rebase-merge ] is TRUE — bug NOT reproduced"
else
  ok "OLD guard [ -d .git/rebase-merge ] is FALSE mid-rebase (bug reproduced)"
fi

# --- (fix) NEW rev-parse guard is TRUE mid-rebase in a worktree. --------------
if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
  ok "NEW guard via 'git rev-parse --git-path rebase-merge' is TRUE mid-rebase (fix works)"
else
  bad "NEW guard is FALSE mid-rebase — fix does not detect the rebase state"
fi

cd "$TMP" || die "cannot leave worktree before seqedit check"

# --- (seqedit) full 40-char drop sha rewrites its abbreviated `pick` line. ----
# Mirror the sequence-editor the formula writes: git rebase -i emits ABBREVIATED
# hashes in the todo, while DROP_SHAS holds FULL shas; the awk must match the
# todo hash as a PREFIX of a full drop sha.
SEQ="$TMP/seqedit.sh"
cat > "$SEQ" <<'SEQEOF'
#!/bin/sh
todo=$1
awk -v drops="$DROP_SHAS" '
  BEGIN { n = split(drops, d, " ") }
  /^pick / {
    h = $2
    for (i = 1; i <= n; i++) {
      if (substr(d[i], 1, length(h)) == h) { sub(/^pick/, "drop"); break }
    }
  }
  { print }
' "$todo" > "$todo.tmp" && mv "$todo.tmp" "$todo"
SEQEOF
chmod +x "$SEQ"

FULL="$(git -C "$TMP/main" rev-parse HEAD)"            # 40-char drop sha
ABBREV="$(git -C "$TMP/main" rev-parse --short HEAD)"  # abbreviated, as a todo carries it
TODO="$TMP/todo"
printf 'pick %s main edit\npick deadbeef unrelated\n' "$ABBREV" > "$TODO"
export DROP_SHAS="$FULL"
"$SEQ" "$TODO"
if grep -qx "drop $ABBREV main edit" "$TODO" && grep -qx "pick deadbeef unrelated" "$TODO"; then
  ok "seqedit: full drop sha rewrites its abbreviated 'pick' line; unrelated line untouched"
else
  bad "seqedit: prefix-match failed (todo: $(tr '\n' '|' < "$TODO"))"
fi

# --- (seqedit) empty DROP_SHAS is a no-op. ------------------------------------
printf 'pick %s main edit\n' "$ABBREV" > "$TODO"
export DROP_SHAS=""
"$SEQ" "$TODO"
if grep -qx "pick $ABBREV main edit" "$TODO"; then
  ok "seqedit: empty DROP_SHAS is a no-op"
else
  bad "seqedit: empty DROP_SHAS changed the todo (todo: $(tr '\n' '|' < "$TODO"))"
fi

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
