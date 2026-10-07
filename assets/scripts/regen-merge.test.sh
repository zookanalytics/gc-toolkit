#!/usr/bin/env bash
# Hermetic test for assets/scripts/regen-merge.sh — a merge conflict confined to
# generated/seed-audit, classified off the object store and resolved by a render
# of the merged inputs. Real git over a fixture repository whose renderer is a
# stub committed into the tree, so no `gc` is needed: the stub writes
# generated/seed-audit as a pure function of inputs/*, which is the property the
# real renderer has and the resolution rests on.
# Covers classify's verdicts (regenerable, a hand-written conflict beside the
# generated one, a merged tree with no renderer, a clean merge, an unresolvable
# rev, unrelated histories) and resolve: the merge committed with both parents,
# the tree rendered from the merged inputs, a generated path only one side
# changed kept as that side committed it, the commit naming what it resolved,
# no hook run; and every refusal leaving the stopped merge for the caller's abort
# and committing nothing: a hand-written conflict, no renderer, an unstaged
# change or an untracked file besides the conflicts (left in place), a failed
# render, a hung render, a render that moves a path neither side changed or only
# one side changed, and a render that writes outside its tree, changing a
# tracked file, creating a file, or both (every write undone, even where the
# abort writes back a path the merge deleted).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/regen-merge.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-regen-merge-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false
unset STUB_RENDER_FAIL STUB_RENDER_DRIFT STUB_RENDER_OUTSIDE STUB_RENDER_CREATE STUB_RENDER_SLEEP REGEN_MERGE_RENDER_TIMEOUT 2>/dev/null || true

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1' want '$2')"; fi; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2' in: $1)" ;; esac; }
hasnt() { case "$1" in *"$2"*) bad "$3 (found '$2' in: $1)" ;; *) ok "$3" ;; esac; }

command -v git >/dev/null 2>&1 || { echo "git required" >&2; exit 1; }

# --- fixture --------------------------------------------------------------------
# inputs/*.txt are the render inputs. generated/seed-audit holds, per input, a
# two-line manifest record (path, then checksum), an index row (path, bytes) and
# a copy, the same shapes the real artifact commits. notes.txt is written by
# hand. The env knobs make the stub misbehave the ways a real render can.
R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t
mkdir -p "$R/inputs" "$R/assets/scripts"
cat > "$R/assets/scripts/render-seed-audit.sh" <<'RENDER'
#!/usr/bin/env bash
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/generated/seed-audit"
[ -z "${STUB_RENDER_SLEEP:-}" ] || sleep "$STUB_RENDER_SLEEP"
[ -z "${STUB_RENDER_FAIL:-}" ] || { echo "stub render exploded" >&2; exit 2; }
rm -rf "$OUT"; mkdir -p "$OUT/inputs"
: > "$OUT/SOURCES.txt"; : > "$OUT/INDEX.md"
for f in "$ROOT"/inputs/*.txt; do
  n="inputs/$(basename "$f")"
  printf '%s\n%s\n' "$n" "$(cksum < "$f" | cut -d' ' -f1)" >> "$OUT/SOURCES.txt"
  printf '| %s | %s |\n' "$n" "$(wc -c < "$f" | tr -d ' ')" >> "$OUT/INDEX.md"
  cp "$f" "$OUT/$n.md"
done
[ -z "${STUB_RENDER_DRIFT:-}" ] || echo "a line neither side committed" >> "$OUT/$STUB_RENDER_DRIFT"
[ -z "${STUB_RENDER_OUTSIDE:-}" ] || echo "stray" >> "$ROOT/$STUB_RENDER_OUTSIDE"
[ -z "${STUB_RENDER_CREATE:-}" ] || echo "stray" > "$ROOT/$STUB_RENDER_CREATE"
echo "wrote generated/seed-audit (stub)"
RENDER
chmod +x "$R/assets/scripts/render-seed-audit.sh"
render() { bash "$R/assets/scripts/render-seed-audit.sh" >/dev/null; }
printf 'a1\na2\na3\na4\na5\na6\n' > "$R/inputs/a.txt"
printf 'b1\nb2\nb3\nb4\nb5\nb6\n' > "$R/inputs/b.txt"
printf 'n1\nn2\nn3\n' > "$R/notes.txt"
render
git -C "$R" add -A; git -C "$R" commit -qm base
BASE=$(git -C "$R" rev-parse HEAD)
commit_on() { # <branch> <message> — commits the working tree, rendered, onto <branch>
  render; git -C "$R" add -A; git -C "$R" commit -qm "$2"
}
# feat moves the first line of b, main moves the last: the input merges cleanly,
# and its manifest record and index row conflict.
git -C "$R" checkout -q -b feat "$BASE"
sed -i 's/^b1$/b1 moved by feat/' "$R/inputs/b.txt"; commit_on feat "feat moves b"
FEAT=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q -b feat-hand "$FEAT"
sed -i 's/^n2$/n2 by feat/' "$R/notes.txt"; commit_on feat-hand "feat-hand also edits notes"
FEAT_HAND=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q -b feat-norender "$FEAT"
git -C "$R" rm -q assets/scripts/render-seed-audit.sh; git -C "$R" commit -qm "feat-norender drops the renderer"
git -C "$R" checkout -q -b feat-clean "$BASE"
echo other > "$R/other.txt"; git -C "$R" add other.txt; git -C "$R" commit -qm "feat-clean touches no input"
# feat-c also adds an input only it renders, so the copy of that input is a
# generated path one side changed.
git -C "$R" checkout -q -b feat-c "$FEAT"
printf 'c1\nc2\n' > "$R/inputs/c.txt"; commit_on feat-c "feat-c adds an input"
FEAT_C=$(git -C "$R" rev-parse HEAD)
git -C "$R" checkout -q main
sed -i 's/^b6$/b6 moved by main/' "$R/inputs/b.txt"
sed -i 's/^n2$/n2 by main/' "$R/notes.txt"
commit_on main "main moves b and notes"
MAIN=$(git -C "$R" rev-parse HEAD)
# main-gone also deletes notes.txt, so a merge into it drops a path the branch
# still has, and the caller's abort has to write that path back.
git -C "$R" checkout -q -b main-gone "$MAIN"
git -C "$R" rm -q notes.txt; commit_on main-gone "main-gone deletes notes"
git -C "$R" checkout -q --orphan unrelated
git -C "$R" rm -rqf . >/dev/null; echo u > "$R/u.txt"; git -C "$R" add u.txt; git -C "$R" commit -qm unrelated
git -C "$R" checkout -q -f main
# A hook that leaves a mark, so the commit resolve makes can be shown to run none.
mkdir -p "$TMP/hooks"
printf '#!/usr/bin/env bash\ntouch "%s"\n' "$TMP/hook-ran" > "$TMP/hooks/pre-commit"
chmod +x "$TMP/hooks/pre-commit"
git -C "$R" config core.hooksPath "$TMP/hooks"

classify() { "$SUT" classify --dir "$R" "$@" 2>&1; }

echo "# classify"
out=$(classify main feat); rc=$?
eq "$rc" 0 "a conflict confined to generated/seed-audit is regenerable"
eq "$out" "generated/seed-audit/SOURCES.txt" "…and the conflicted path is printed: the manifest record both sides rewrote"
out=$(classify main feat-hand); rc=$?
eq "$rc" 1 "a hand-written conflict beside the generated ones is not regenerable"
has "$out" "notes.txt" "…and the hand-written path is named"
out=$(classify main feat-norender); rc=$?
eq "$rc" 1 "a merged tree with no renderer is not regenerable, however generated the conflict"
out=$(classify main feat-clean); rc=$?
eq "$rc" 3 "two commits that merge cleanly have no conflict to classify"
out=$(classify main nosuchref); rc=$?
eq "$rc" 2 "a rev that names no commit cannot be classified"
out=$(classify main unrelated); rc=$?
eq "$rc" 2 "unrelated histories cannot be classified"
out=$("$SUT" classify --dir "$R" main 2>&1); rc=$?
eq "$rc" 2 "classify without both revs is a usage error"
out=$("$SUT" frobnicate 2>&1); rc=$?
eq "$rc" 2 "an unknown subcommand is a usage error"
eq "$(git -C "$R" rev-parse HEAD)" "$MAIN" "classifying moved no ref and checked nothing out"

# A stopped merge of <target> (main unless named) into <branch> in a fresh
# detached worktree, the state the refinery's prepare step hands resolve.
stopped_merge() { # <branch> [<target>] — prints the worktree
  local wt
  wt=$(mktemp -d "$TMP/wt.XXXXXX")
  git -C "$R" worktree add -q --detach "$wt" "$1" >/dev/null 2>&1
  git -C "$wt" merge --no-edit "${2:-main}" >/dev/null 2>&1 && echo "UNEXPECTED: $1 merged cleanly" >&2
  printf '%s' "$wt"
}
merging() { git -C "$1" rev-parse --verify --quiet MERGE_HEAD >/dev/null 2>&1 && echo yes || echo no; }

echo "# resolve: a conflict confined to the generated tree"
W=$(stopped_merge feat)
eq "$(merging "$W")" "yes" "the fixture merge stopped on its conflicts"
rm -f "$TMP/hook-ran"
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 0 "resolve commits the merge"
has "$out" "merge committed" "…and says so"
eq "$(merging "$W")" "no" "no merge is left in progress"
eq "$(git -C "$W" rev-parse HEAD^1)" "$FEAT" "the merge's first parent is the branch"
eq "$(git -C "$W" rev-parse HEAD^2)" "$MAIN" "…and its second is the target, so the branch is brought current, not rewritten"
has "$(cat "$W/inputs/b.txt")" "b1 moved by feat" "the merged input carries the branch's change"
has "$(cat "$W/inputs/b.txt")" "b6 moved by main" "…and the target's"
# Both sides grew b by the same 14 bytes, so both rewrote its index row to the
# same count and git merged that row cleanly, one growth short. Only a render of
# the merged input can count both.
has "$(cat "$W/generated/seed-audit/INDEX.md")" "| inputs/b.txt | 46 |" \
  "a row both sides rewrote alike, which merged clean but stale, carries the merged input's count"
render_in() { ( cd "$1" && bash assets/scripts/render-seed-audit.sh >/dev/null ); }
render_in "$W"
eq "$(git -C "$W" status --porcelain | wc -l | tr -d ' ')" "0" "the committed tree is exactly a render of the merged inputs"
msg=$(git -C "$W" log -1 --format=%B)
has "$msg" "generated/seed-audit/SOURCES.txt" "the commit message names what it resolved"
has "$msg" "regen-merge.sh" "…and how"
[ -e "$TMP/hook-ran" ] && bad "the commit ran the pre-commit hook" || ok "the commit ran no hook, so nothing re-rendered past the check"

echo "# resolve: a generated path only one side changed"
# git takes feat-c's copy of its new input, and a render of the merged inputs
# writes the same file back.
W=$(stopped_merge feat-c)
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 0 "a merge with a generated path only one side changed resolves"
eq "$(git -C "$W" diff --name-only "$FEAT_C" HEAD -- generated/seed-audit/inputs/c.txt.md)" "" \
  "…and keeps that path exactly as the side that changed it committed it"

echo "# resolve refuses, and leaves the stopped merge for the caller's abort"
refused() { # <worktree> <head-before> <label>
  eq "$(merging "$1")" "yes" "$3: the merge is still in progress for the caller to abort"
  eq "$(git -C "$1" rev-parse HEAD)" "$2" "$3: nothing was committed"
  git -C "$1" merge --abort >/dev/null 2>&1
  eq "$(merging "$1")" "no" "$3: the caller's abort ends the merge"
  git -C "$1" diff --cached --quiet && ok "$3: …and leaves nothing staged for a commit" || bad "$3: …and leaves nothing staged for a commit"
}
W=$(stopped_merge feat-hand)
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a hand-written conflict is refused"
has "$out" "notes.txt" "…naming the path a person has to resolve"
refused "$W" "$FEAT_HAND" "hand-written"

W=$(stopped_merge feat-norender)
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a merged tree with no renderer is refused"
has "$out" "carries no assets/scripts/render-seed-audit.sh" "…saying what is missing"
refused "$W" "$(git -C "$R" rev-parse feat-norender)" "no renderer"

# The render would read the edit and the commit would leave it out, and the
# undo after the render must only ever reach the render's own writes.
W=$(stopped_merge feat)
echo "an edit nobody staged" >> "$W/inputs/a.txt"
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "an unstaged change besides the conflicts is refused"
has "$out" "inputs/a.txt" "…naming the changed path"
has "$(cat "$W/inputs/a.txt")" "an edit nobody staged" "…and the change is left in place, not undone"
refused "$W" "$FEAT" "unstaged change"

# An untracked input is the same hazard: the renderer finds its inputs on disk,
# so the render would count the file and the commit would leave it out. `git
# diff` never lists it, and the removal after the render must never reach it.
W=$(stopped_merge feat)
printf 'd1\n' > "$W/inputs/d.txt"
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "an untracked file besides the conflicts is refused"
has "$out" "stay out of the commit: inputs/d.txt" "…naming the untracked path"
[ -e "$W/generated/seed-audit/inputs/d.txt.md" ] && bad "…before any render" || ok "…before any render"
eq "$(cat "$W/inputs/d.txt" 2>/dev/null)" "d1" "…and the file is left in place, not removed"
refused "$W" "$FEAT" "untracked file"

W=$(stopped_merge feat)
out=$(STUB_RENDER_FAIL=1 "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a failed render is refused"
has "$out" "the render failed" "…as a failed render"
has "$out" "stub render exploded" "…quoting the renderer"
refused "$W" "$FEAT" "failed render"

if command -v timeout >/dev/null 2>&1; then
  W=$(stopped_merge feat)
  t0=$(date +%s)
  out=$(STUB_RENDER_SLEEP=30 REGEN_MERGE_RENDER_TIMEOUT=1 "$SUT" resolve --dir "$W" 2>&1); rc=$?
  t1=$(date +%s)
  eq "$rc" 1 "a render that outlives its bound is refused"
  [ $((t1 - t0)) -lt 20 ] && ok "…at the bound, not when the render gives up" || bad "…at the bound (took $((t1 - t0))s)"
  refused "$W" "$FEAT" "hung render"
fi

# The discriminating cases. Every check before these passes: each unmerged path
# is generated and the render succeeds. The render also moves a generated file
# that neither side changed, or that only one side changed, so it disagrees with
# what the base or that side committed: a person's question, not a resolution.
W=$(stopped_merge feat)
out=$(STUB_RENDER_DRIFT=inputs/a.txt.md "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that moves a path neither side changed is refused"
has "$out" "generated/seed-audit/inputs/a.txt.md" "…naming the path it moved"
refused "$W" "$FEAT" "drifting render"

W=$(stopped_merge feat-c)
out=$(STUB_RENDER_DRIFT=inputs/c.txt.md "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that moves a path only one side changed is refused"
has "$out" "generated/seed-audit/inputs/c.txt.md" "…naming the path it moved"
refused "$W" "$FEAT_C" "one-sided drift"

W=$(stopped_merge feat)
out=$(STUB_RENDER_OUTSIDE=notes.txt "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that writes outside its tree is refused"
has "$out" "changed files outside generated/seed-audit" "…as such"
refused "$W" "$FEAT" "out-of-tree render"

# A file the render creates is no unstaged change, so `git diff` passes it, and
# the merge would be committed while the checks that run next read a file the
# push leaves out.
W=$(stopped_merge feat)
out=$(STUB_RENDER_CREATE=untracked-side-effect.txt "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that creates a file outside its tree is refused"
has "$out" "created files outside generated/seed-audit: untracked-side-effect.txt" "…naming the file"
[ -e "$W/untracked-side-effect.txt" ] && bad "…and the file is removed" || ok "…and the file is removed"
refused "$W" "$FEAT" "created file"

# Where the merge deleted a path the branch has, a file the render leaves there
# stops the caller's abort, which writes that path back.
W=$(stopped_merge feat main-gone)
[ -e "$W/notes.txt" ] && bad "the fixture merge deleted notes.txt" || ok "the fixture merge deleted notes.txt"
out=$(STUB_RENDER_CREATE=notes.txt "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that recreates a path the merge deleted is refused"
has "$out" "created files outside generated/seed-audit: notes.txt" "…naming the path"
refused "$W" "$FEAT" "recreated path"
eq "$(cat "$W/notes.txt" 2>/dev/null)" "$(git -C "$R" show "$FEAT:notes.txt")" "…and the abort writes the branch's copy back"

# A render that changes one file outside its tree and creates another is undone
# both ways before the refusal, because a created file left in place stops the
# caller's abort from ending the merge.
W=$(stopped_merge feat main-gone)
out=$(STUB_RENDER_OUTSIDE=inputs/a.txt STUB_RENDER_CREATE=notes.txt "$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 1 "a render that changes one file outside its tree and creates another is refused"
has "$out" "changed files outside generated/seed-audit" "…naming the change"
has "$out" "created files outside generated/seed-audit: notes.txt" "…and the created path"
eq "$(cat "$W/inputs/a.txt")" "$(git -C "$R" show "$FEAT:inputs/a.txt")" "…with the changed file restored"
refused "$W" "$FEAT" "changed and created"
eq "$(cat "$W/notes.txt" 2>/dev/null)" "$(git -C "$R" show "$FEAT:notes.txt")" "…and the abort writes the branch's copy back"

echo "# resolve with nothing to resolve"
W="$TMP/wt-idle"; git -C "$R" worktree add -q --detach "$W" feat >/dev/null 2>&1
out=$("$SUT" resolve --dir "$W" 2>&1); rc=$?
eq "$rc" 2 "resolve with no merge in progress is a usage error"
out=$("$SUT" resolve --dir "$TMP/not-a-repo" 2>&1); rc=$?
eq "$rc" 2 "…and so is a directory that is no worktree"

echo
echo "regen-merge: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
