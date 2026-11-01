#!/usr/bin/env bash
# Hermetic test for worktree-setup.sh: staging a non-empty target, --sync, and
# the provisioning (bead redirect, local excludes) a re-run completes.
#
# Uses a real temp git rig (a clone of a bare remote, so origin/HEAD resolves)
# and drives the real script. No live city, gc, or network. Covers:
#   (e) a file staged from a non-empty target loses to the file the checkout
#       brought, and a file only the stage holds comes back;
#   (f) a normal run leaves no stage dir behind;
#   (h) a staged directory loses to a checked-out file at the same path: the
#       existing file wins and the whole losing source subtree is dropped, and
#       the entries past it still come back;
#   (i) --sync moves a detached, clean worktree that is behind the remote to
#       the default-branch tip, back on its per-target branch, silently, and the
#       next sync fast-forwards it;
#   (j) a detached HEAD carrying a commit no ref reaches stays put, and one
#       stderr line names the worktree and the reason;
#   (k) a detached worktree with an uncommitted tracked change stays put, the
#       change intact, with the same one-line warning;
#   (l) a per-target branch holding a commit the tip lacks is never reset: the
#       worktree is detached at the tip instead and the branch keeps its commit;
#   (m) an untracked file the tip would overwrite blocks the move: the worktree
#       stays put, the file intact, the run still exits 0, and the warning
#       carries git's reason.
#   (n) a post-checkout hook that fails the add leaves a half-built worktree
#       (git keeps it), and the re-run gives it the bead redirect and the Gas
#       City exclude marker, so runtime files stay out of git status;
#   (o) a re-run keeps a non-empty redirect, so a deliberate one survives, and
#       rewrites an empty one;
#   (p) a main checkout (.git is a directory) is never given a redirect, and
#       its exclude file is left alone;
#   (q) a worktree whose git metadata is gone still gets its redirect, and the
#       run still exits 0.
#   (r) gc's writes stay out of git status in the worktree and in the rig
#       checkout that shares its exclude file: the skill links its ownership
#       manifests name under .agents/skills/, the manifest itself,
#       .gc/settings.json and .beads.gate.lock. Everything else a person keeps
#       there still shows and stages, in both: a plain file, a link of their
#       own, a new skill directory, and changes to a skill the repo tracks. A
#       link gc adds later is hidden by the next run, a manifest name git
#       would read as a pattern or that ends in a newline is never written, and
#       without jq or a readable manifest the run still succeeds and adds no
#       name;
#   (s) a detached HEAD on a commit the tip lacks moves once a ref reaches it,
#       such as a squash-landed branch's remote-tracking ref, a tag or another
#       branch;
#   (t) a per-target branch left behind by a rewritten default branch is reset
#       to the tip when another ref reaches its commits;
#   (u) a per-target branch holding a commit only it reaches is not reset: the
#       attached worktree is detached at the tip and the branch keeps the commit;
#   (v) a worktree on a branch that is not its own stays on it, and fast-forwards
#       to its upstream when it can;
#   (w) a worktree on its own branch with an uncommitted tracked change stays put
#       with the change intact and one stderr line, both when the branch has
#       diverged and when the next commit touches the changed file;
#   (x) a per-target branch with no upstream moves to the tip and gains one;
#   (y) a remote-tracking ref alone, a tag alone or another branch alone reaching
#       a per-target branch's commit is enough to reset that branch;
#   (z) when git cannot read a commit's reach or the tree's status, a detached
#       worktree stays where it is and no branch is reset;
#   (aa) a repository with no origin is left where it is, silently;
#   (ab) a per-target branch ahead of its upstream, as a rewind of the default
#        branch to an ancestor leaves it, is not at the tip even though its
#        fast-forward succeeds: the worktree is detached at the tip when only the
#        branch reaches its commits, the branch is reset when another ref does, and
#        a tracked change keeps it there with one stderr line. A branch not its own
#        stays there, silently;
#   (ac) a per-target branch at the tip, or fast-forwarded to it, says nothing
#        about an uncommitted tracked change;
#   (ad) a per-target branch at an upstream that is not the default branch reaches
#        the tip and tracks the default branch from then on;
#   (ae) with origin/HEAD unset a per-target branch still fast-forwards, and one
#        stderr line says why the sync goes no further.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/worktree-setup.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-worktree-setup-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# Host signing of commits and tags must not make this suite need a signing agent.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
present() { [ -e "$1" ] && ok "$2" || bad "$2 (missing $1)"; }
absent()  { [ -e "$1" ] && bad "$2 (present $1)" || ok "$2"; }

# --- A bare remote + a rig clone (clone sets refs/remotes/origin/HEAD). -------
SRC="$TMP/src"; git init -q -b main "$SRC"
echo seed > "$SRC/README.md"; git -C "$SRC" add -A; git -C "$SRC" commit -qm init
git clone -q --bare "$SRC" "$TMP/remote.git"
RIG="$TMP/rig"; git clone -q "$TMP/remote.git" "$RIG"

STAGE_PREFIX=".gascity-worktree-stage"
run() { sh "$SCRIPT" "$RIG" "$1" "$2" ${3:+"$3"} >>"$TMP/run.log" 2>&1; }
# stage dirs left in a parent, one basename per line
stages() { local d; for d in "$1/$STAGE_PREFIX"*; do [ -e "$d" ] || continue; echo "${d##*/}"; done; }
# the --sync run's stderr alone; a non-zero exit is appended as "exit <rc>"
sync_stderr() { { sh "$SCRIPT" "$RIG" "$1" "$2" --sync >/dev/null; } 2>&1 || echo "exit $?"; }
# land one commit on the remote's main, as a merged PR would
advance_remote() {
    echo "$1" > "$SRC/$1"; git -C "$SRC" add -A; git -C "$SRC" commit -qm "$1"
    git -C "$SRC" push -q "$TMP/remote.git" main
}
tip()       { git -C "$TMP/remote.git" rev-parse main; }
head_of()   { git -C "$1" rev-parse HEAD; }
branch_of() { git -C "$1" symbolic-ref -q --short HEAD || echo DETACHED; }
lines()     { printf '%s' "$1" | grep -c '' || true; }   # "" counts as 0
has()       { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (stderr '$1' lacks '$2')" ;; esac; }
lacks()     { case "$1" in *"$2"*) bad "$3 ('$1' has '$2')" ;; *) ok "$3" ;; esac; }
# the run's exit status, captured so an expected failure does not end the suite
rc_of()     { local rc=0; sh "$SCRIPT" "$@" >>"$TMP/run.log" 2>&1 || rc=$?; echo "$rc"; }
# whether the exclude file git resolves for a checkout carries the Gas City marker
marker_in() {
    grep -qF "# Gas City worktree infrastructure (local excludes)" \
        "$(git -C "$1" rev-parse --path-format=absolute --git-path info/exclude)" && echo yes || echo no
}

# --- (e) a non-empty target: the file the checkout brought wins over a staged
#         one, and what only the stage holds comes back. ----------------------
P="$TMP/e"; mkdir -p "$P/agentE"
echo STALE > "$P/agentE/README.md"; echo extra > "$P/agentE/extra.txt"
run "$P/agentE" agentE
present "$P/agentE/.git"                     "(e) worktree created over non-empty target"
eq "$(cat "$P/agentE/README.md")" "seed"     "(e) checked-out file not clobbered by a staged one"
present "$P/agentE/extra.txt"                "(e) stage-only file comes back"
eq "$(stages "$P")" ""                       "(e) no stage dir left when an existing file wins"

# --- (f) a normal run cleans its stage dir. -----------------------------------
# Seed the target with content so staging fires, then confirm nothing leaks.
P="$TMP/f"; mkdir -p "$P/agentF/.claude"; echo s > "$P/agentF/.claude/settings.json"
run "$P/agentF" agentF
present "$P/agentF/.git"                     "(f) worktree created over non-empty target"
present "$P/agentF/.claude/settings.json"   "(f) pre-existing content restored"
eq "$(stages "$P")" ""                       "(f) staging cleaned up after itself"

# --- (h) a staged DIRECTORY loses to a checked-out file at the same path. The
#         file wins and the whole losing subtree is dropped: recursing would
#         mkdir over the file and end the run. ------------------------------
P="$TMP/h"; mkdir -p "$P/agentH/README.md"
echo STALE > "$P/agentH/README.md/nested.txt"; echo solo > "$P/agentH/solo.txt"
eq "$(rc_of "$RIG" "$P/agentH" agentH)" "0"  "(h) a staged dir losing to a file does not end the run"
eq "$(cat "$P/agentH/README.md")" "seed"     "(h) checked-out file not clobbered by a staged dir"
present "$P/agentH/solo.txt"                 "(h) stage-only entry still comes back past the collision"
eq "$(stages "$P")" ""                       "(h) no stage dir left when a staged dir loses to a file"

# --- (i) a detached, clean worktree behind the remote moves to the tip on
#         --sync and lands back on its per-target branch, tracking origin/main,
#         so the next sync takes the fast-forward path. Untracked files stay. --
P="$TMP/i"; mkdir -p "$P"
run "$P/agentI" agentI
BR=$(branch_of "$P/agentI")
git -C "$P/agentI" checkout -q --detach
mkdir -p "$P/agentI/.scratch"; echo keep > "$P/agentI/.scratch/notes"
advance_remote i1.txt
ERR=$(sync_stderr "$P/agentI" agentI)
eq "$(head_of "$P/agentI")" "$(tip)"         "(i) detached worktree advanced to the remote tip"
eq "$(branch_of "$P/agentI")" "$BR"          "(i) back on its per-target branch"
eq "$(git -C "$P/agentI" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(i) per-target branch tracks origin/main"
eq "$(cat "$P/agentI/.scratch/notes")" "keep" "(i) untracked file survives the move"
eq "$ERR" ""                                 "(i) a safe move prints nothing"
advance_remote i2.txt
ERR=$(sync_stderr "$P/agentI" agentI)
eq "$(head_of "$P/agentI")" "$(tip)"         "(i) the next sync fast-forwards the per-target branch"
eq "$(branch_of "$P/agentI")" "$BR"          "(i) and stays on it"
eq "$ERR" ""                                 "(i) a fast-forward prints nothing"

# --- (j) a detached HEAD carrying a commit no ref reaches stays put: moving it
#         would orphan the commit. One stderr line names the worktree and why.
P="$TMP/j"; mkdir -p "$P"
run "$P/agentJ" agentJ
git -C "$P/agentJ" checkout -q --detach
echo local > "$P/agentJ/local.txt"; git -C "$P/agentJ" add local.txt; git -C "$P/agentJ" commit -qm local
LOCAL=$(head_of "$P/agentJ")
advance_remote j1.txt
ERR=$(sync_stderr "$P/agentJ" agentJ)
eq "$(head_of "$P/agentJ")" "$LOCAL"         "(j) HEAD with a local commit not moved"
eq "$(branch_of "$P/agentJ")" "DETACHED"     "(j) still detached"
has "$ERR" "$P/agentJ"                       "(j) warning names the worktree"
has "$ERR" "holds commits no ref reaches"    "(j) warning names the reason"
eq "$(lines "$ERR")" "1"                     "(j) exactly one stderr line"

# --- (k) a detached worktree with an uncommitted change to a tracked file stays
#         put with the change intact, and says so in one stderr line. ---------
P="$TMP/k"; mkdir -p "$P"
run "$P/agentK" agentK
git -C "$P/agentK" checkout -q --detach
BEFORE=$(head_of "$P/agentK")
echo edited >> "$P/agentK/README.md"
advance_remote k1.txt
ERR=$(sync_stderr "$P/agentK" agentK)
eq "$(head_of "$P/agentK")" "$BEFORE"        "(k) HEAD with a dirty tracked tree not moved"
eq "$(tail -n 1 "$P/agentK/README.md")" "edited" "(k) uncommitted change intact"
has "$ERR" "$P/agentK"                       "(k) warning names the worktree"
has "$ERR" "uncommitted changes to tracked files" "(k) warning names the reason"
eq "$(lines "$ERR")" "1"                     "(k) exactly one stderr line"

# --- (l) the per-target branch holds a commit the tip lacks, so it is never
#         reset: the worktree is detached at the tip instead, and the branch
#         keeps its commit. ---------------------------------------------------
P="$TMP/l"; mkdir -p "$P"
run "$P/agentL" agentL
BR=$(branch_of "$P/agentL")
BASE=$(head_of "$P/agentL")
echo mine > "$P/agentL/mine.txt"; git -C "$P/agentL" add mine.txt; git -C "$P/agentL" commit -qm mine
MINE=$(head_of "$P/agentL")
git -C "$P/agentL" checkout -q --detach "$BASE"
advance_remote l1.txt
ERR=$(sync_stderr "$P/agentL" agentL)
eq "$(head_of "$P/agentL")" "$(tip)"         "(l) worktree advanced to the remote tip"
eq "$(branch_of "$P/agentL")" "DETACHED"     "(l) detached at the tip, off the diverged branch"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(l) per-target branch keeps its own commit"
eq "$ERR" ""                                 "(l) a safe move prints nothing"

# --- (m) an untracked file the tip would overwrite blocks the checkout: the
#         worktree and its per-target branch stay put, the file is intact, the
#         run still exits 0, and the stderr line carries git's reason. --------
P="$TMP/m"; mkdir -p "$P"
run "$P/agentM" agentM
BR=$(branch_of "$P/agentM")
git -C "$P/agentM" checkout -q --detach
BEFORE=$(head_of "$P/agentM")
echo mine > "$P/agentM/m1.txt"
advance_remote m1.txt
ERR=$(sync_stderr "$P/agentM" agentM)
eq "$(head_of "$P/agentM")" "$BEFORE"        "(m) blocked checkout leaves HEAD where it was"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$BEFORE" "(m) per-target branch not reset by the refused checkout"
eq "$(cat "$P/agentM/m1.txt")" "mine"        "(m) untracked file not overwritten"
has "$ERR" "$P/agentM"                       "(m) warning names the worktree"
has "$ERR" "git checkout origin/main failed" "(m) warning names the failed checkout"
has "$ERR" "untracked working tree files"    "(m) warning carries git's reason"
eq "$(lines "$ERR")" "1"                     "(m) exactly one stderr line, so the run exited 0"

# --- (n) a post-checkout hook that fails the add: git keeps the worktree, so the
#         first run leaves it half-built, and the re-run completes it. The rig
#         is its own clone because the exclude file is shared by all of a
#         repo's worktrees, and the other cases' worktrees already marked $RIG's.
HR="$TMP/hookrig"; git clone -q "$TMP/remote.git" "$HR"
mkdir -p "$TMP/hooks"; printf '#!/bin/sh\nexit 1\n' > "$TMP/hooks/post-checkout"
chmod +x "$TMP/hooks/post-checkout"
git -C "$HR" config core.hooksPath "$TMP/hooks"
P="$TMP/n"; mkdir -p "$P"; W="$P/agentN"
eq "$(rc_of "$HR" "$W" agentN --sync)" "1"   "(n) the hook failure fails the first run"
present "$W/.git"                            "(n) git kept the worktree the failed add made"
absent  "$W/.beads/redirect"                 "(n) the failed run left no bead redirect"
eq "$(marker_in "$W")" "no"                  "(n) the failed run left no exclude marker"
eq "$(rc_of "$HR" "$W" agentN --sync)" "0"   "(n) the re-run succeeds"
eq "$(cat "$W/.beads/redirect" 2>/dev/null)" "$HR/.beads" "(n) the re-run writes the bead redirect"
eq "$(marker_in "$W")" "yes"                 "(n) the re-run writes the Gas City exclude marker"
mkdir -p "$W/.claude"; echo x > "$W/.claude/settings.json"
eq "$(git -C "$W" status --porcelain)" ""    "(n) runtime files stay out of git status"

# --- (o) a re-run keeps a non-empty bead redirect, so a deliberate one survives,
#         and rewrites an empty one, which points nowhere. --------------------
P="$TMP/o"; mkdir -p "$P"
run "$P/agentO" agentO
echo "/elsewhere/.beads" > "$P/agentO/.beads/redirect"
run "$P/agentO" agentO --sync
eq "$(cat "$P/agentO/.beads/redirect")" "/elsewhere/.beads" "(o) a deliberate redirect survives a re-run"
: > "$P/agentO/.beads/redirect"
run "$P/agentO" agentO --sync
eq "$(cat "$P/agentO/.beads/redirect")" "$RIG/.beads" "(o) an empty redirect is rewritten"

# --- (p) a main checkout (.git is a directory) is never provisioned: its .beads
#         is the rig's own store, not a pointer to one. A fresh clone, so its
#         exclude file carries no marker from another case. ------------------
MAIN="$TMP/main"; git clone -q "$TMP/remote.git" "$MAIN"
mkdir -p "$MAIN/.beads"; echo store > "$MAIN/.beads/config.yaml"
eq "$(rc_of "$MAIN" "$MAIN" agentP --sync)" "0" "(p) a main checkout target exits 0"
absent "$MAIN/.beads/redirect"               "(p) a main checkout is never given a bead redirect"
eq "$(marker_in "$MAIN")" "no"               "(p) a main checkout's exclude file is left alone"

# --- (q) a worktree whose git metadata is gone (its admin dir under the rig's
#         .git/worktrees removed) still gets its redirect, and the run exits 0:
#         git resolves no exclude file for it and cannot stage from it. -------
P="$TMP/q"; mkdir -p "$P"
run "$P/agentQ" agentQ
rm -f "$P/agentQ/.beads/redirect"
ADMIN=$(sed -n 's/^gitdir: //p' "$P/agentQ/.git")
case "$ADMIN" in   # git records the real path
    "$(cd "$RIG" && pwd -P)/.git/worktrees/"?*) rm -rf "$ADMIN" ;;
    *) bad "(q) admin dir '$ADMIN' is not under $RIG/.git/worktrees" ;;
esac
eq "$(rc_of "$RIG" "$P/agentQ" agentQ --sync)" "0" "(q) a worktree with no git metadata still exits 0"
eq "$(cat "$P/agentQ/.beads/redirect" 2>/dev/null)" "$RIG/.beads" "(q) it still gets its bead redirect"

# --- (r) gc's writes stay out of git status, in the worktree and in the rig
#         checkout, which shares its exclude file. gc's skill links are hidden
#         by the exact names its ownership manifest records, so what a person
#         keeps under .agents/skills/ still shows: a skill the repo tracks, a
#         new skill, a plain file and a link of their own. Its own rig, so no
#         other case's exclude file is reused. --------------------------------
SR="$TMP/skillsrc"; git init -q -b main "$SR"
mkdir -p "$SR/.agents/skills/tracked-skill"
echo seed > "$SR/README.md"; echo skill > "$SR/.agents/skills/tracked-skill/SKILL.md"
git -C "$SR" add -A; git -C "$SR" commit -qm init
git clone -q --bare "$SR" "$TMP/skills.git"
SKR="$TMP/skillrig"; git clone -q "$TMP/skills.git" "$SKR"
P="$TMP/r"; mkdir -p "$P"; W="$P/agentR"
# gc_link <checkout> <name>... — what gc's skill pass leaves in a checkout's
# .agents/skills/: a link per name to a skill directory by its absolute path,
# and the ownership manifest recording every name it linked there.
gc_link() {
    local co="$1" name json="" sep=""; shift
    for name in "$@"; do
        mkdir -p "$TMP/linked/$name"
        [ -L "$co/.agents/skills/$name" ] || ln -s "$TMP/linked/$name" "$co/.agents/skills/$name"
        json="$json$sep\"$name\":\"$TMP/linked/$name\""; sep=","
    done
    printf '{"targets":{%s}}' "$json" > "$co/.agents/skills/.gc-skill-ownership.json"
}
# gc_writes <checkout> — the rest of what gc and bd leave in a checkout: the
# staged session settings and bd's workspace gate.
gc_writes() { mkdir -p "$1/.gc"; echo '{}' > "$1/.gc/settings.json"; : > "$1/.beads.gate.lock"; }
# The rig checkout's links exist before the agent starts: a skill from an
# imported pack, and a bare name from an agent-local skill.
gc_link "$SKR" gc-toolkit.work local-skill; gc_writes "$SKR"
eq "$(rc_of "$SKR" "$W" agentR --sync)" "0" "(r) the run succeeds"
gc_link "$W" gc-toolkit.work local-skill; gc_writes "$W"
eq "$(git -C "$W" status --porcelain)" ""    "(r) gc's writes stay out of the worktree's git status"
eq "$(git -C "$SKR" status --porcelain)" ""  "(r) and out of the rig checkout's, which shares the exclude file"
# A person's plain file and their own link to a skill directory, in each.
for CO in "$W" "$SKR"; do
    echo notes > "$CO/.agents/skills/README.md"
    ln -s tracked-skill "$CO/.agents/skills/alias-skill"
done
for CO in "$W" "$SKR"; do
    ST=$(git -C "$CO" status --porcelain)
    has "$ST" "?? .agents/skills/README.md"   "(r) a file a person adds there shows (${CO##*/})"
    has "$ST" "?? .agents/skills/alias-skill" "(r) and so does a link of their own (${CO##*/})"
    ADDED=$(git -C "$CO" add -A --dry-run)
    has "$ADDED" "add '.agents/skills/README.md'"   "(r) git add -A stages the file (${CO##*/})"
    has "$ADDED" "add '.agents/skills/alias-skill'" "(r) and the link (${CO##*/})"
    lacks "$ADDED" "gc-toolkit.work" "(r) and none of gc's links (${CO##*/})"
done
mkdir -p "$W/.agents/skills/new-skill"; echo mine > "$W/.agents/skills/new-skill/SKILL.md"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/new-skill/" "(r) a skill directory a person adds still shows"
echo more >> "$W/.agents/skills/tracked-skill/SKILL.md"
echo extra > "$W/.agents/skills/tracked-skill/notes.md"
has "$(git -C "$W" status --porcelain)" " M .agents/skills/tracked-skill/SKILL.md" "(r) an edit to a tracked skill still shows"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/tracked-skill/notes.md" "(r) and so does a new file inside it"
# A link gc adds later, such as a skill local to this worktree's agent, shows
# until the next run reads the worktree's manifest.
gc_link "$W" gc-toolkit.work local-skill later-skill
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/later-skill" "(r) a link gc adds later shows before the next run"
eq "$(rc_of "$SKR" "$W" agentR --sync)" "0" "(r) the next run succeeds"
lacks "$(git -C "$W" status --porcelain)" "later-skill" "(r) and hides it"
# A manifest name git would read as a pattern is never written, so it cannot
# hide what a person keeps there. Nor is a name that ends in a newline, which
# would reach the file as the name before it.
printf '{"targets":{"*":"%s","README*":"%s","a b":"%s",".":"%s","..":"%s","README.md\\n":"%s"}}' \
    "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" \
    > "$W/.agents/skills/.gc-skill-ownership.json"
eq "$(rc_of "$SKR" "$W" agentR --sync)" "0" "(r) a run over a manifest of pattern names succeeds"
EXF=$(git -C "$W" rev-parse --path-format=absolute --git-path info/exclude)
eq "$(grep '^\.agents/skills/' "$EXF" | grep -v '^\.agents/skills/[A-Za-z0-9._-]*$' || true)" "" \
    "(r) no name git would read as a pattern reaches the exclude file"
eq "$(grep -cxE '\.agents/skills/\.{1,2}' "$EXF" || true)" "0" "(r) nor the names . and .."
eq "$(grep -cxF '.agents/skills/README.md' "$EXF" || true)" "0" "(r) nor a name that ends in a newline"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/README.md" "(r) so a person's file still shows"
# With no jq, or a manifest jq cannot read, the run still succeeds and adds no
# name, so a link it cannot read shows rather than anything being hidden.
mkdir -p "$TMP/nojq"; printf '#!/bin/sh\nexit 127\n' > "$TMP/nojq/jq"; chmod +x "$TMP/nojq/jq"
gc_link "$W" gc-toolkit.work local-skill later-skill unread-skill
eq "$(PATH="$TMP/nojq:$PATH" rc_of "$SKR" "$W" agentR --sync)" "0" "(r) a run without jq succeeds"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/unread-skill" "(r) and leaves the link it could not read showing"
echo '{"targets":' > "$W/.agents/skills/.gc-skill-ownership.json"
eq "$(rc_of "$SKR" "$W" agentR --sync)" "0" "(r) a run over a manifest jq cannot read succeeds"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/unread-skill" "(r) and adds no name either"

# --- (s) a detached HEAD on a commit the tip lacks moves once a ref reaches it,
#         because a squash merge never brings a branch's commits onto the tip. A
#         remote-tracking ref reaches it first, then only a tag, then only another
#         branch. ----------------------------------------------------------------
P="$TMP/s"; mkdir -p "$P"
run "$P/agentS" agentS
BR=$(branch_of "$P/agentS")
git -C "$P/agentS" checkout -q --detach
echo landed > "$P/agentS/landed.txt"; git -C "$P/agentS" add landed.txt; git -C "$P/agentS" commit -qm landed
LANDED=$(head_of "$P/agentS")
git -C "$P/agentS" push -q origin HEAD:refs/heads/polecat/s-work
git -C "$RIG" fetch -q origin
advance_remote s1.txt
ERR=$(sync_stderr "$P/agentS" agentS)
eq "$(head_of "$P/agentS")" "$(tip)"         "(s) a HEAD a remote-tracking ref reaches moves to the tip"
eq "$(branch_of "$P/agentS")" "$BR"          "(s) back on its per-target branch"
eq "$ERR" ""                                 "(s) a safe move prints nothing"
eq "$(git -C "$RIG" rev-parse refs/remotes/origin/polecat/s-work)" "$LANDED" "(s) the ref that reaches the commit is untouched"
git -C "$P/agentS" checkout -q --detach "$LANDED"
git -C "$TMP/remote.git" update-ref -d refs/heads/polecat/s-work
git -C "$RIG" update-ref -d refs/remotes/origin/polecat/s-work
git -C "$RIG" tag s-pin "$LANDED"
advance_remote s2.txt
ERR=$(sync_stderr "$P/agentS" agentS)
eq "$(head_of "$P/agentS")" "$(tip)"         "(s) a HEAD only a tag reaches moves to the tip"
eq "$ERR" ""                                 "(s) and prints nothing"
git -C "$P/agentS" checkout -q --detach "$LANDED"
git -C "$RIG" tag -d s-pin >/dev/null
git -C "$RIG" branch s-keep "$LANDED"
advance_remote s3.txt
ERR=$(sync_stderr "$P/agentS" agentS)
eq "$(head_of "$P/agentS")" "$(tip)"         "(s) a HEAD only another branch reaches moves to the tip"
eq "$ERR" ""                                 "(s) and that prints nothing either"

# --- (t) a rewritten default branch leaves a per-target branch unable to
#         fast-forward. Another ref reaches its commits, so it is reset to the
#         tip. Its own remote, since this rewrites main. ------------------------
TS="$TMP/tsrc"; git init -q -b main "$TS"
echo seed > "$TS/README.md"; git -C "$TS" add -A; git -C "$TS" commit -qm init
echo old > "$TS/old.txt"; git -C "$TS" add -A; git -C "$TS" commit -qm old
git clone -q --bare "$TS" "$TMP/t.git"
TR="$TMP/trig"; git clone -q "$TMP/t.git" "$TR"
P="$TMP/t"; mkdir -p "$P"; W="$P/agentT"
eq "$(rc_of "$TR" "$W" agentT)" "0"          "(t) the worktree is made"
BR=$(branch_of "$W"); OLD=$(head_of "$W")
git -C "$TS" push -q "$TMP/t.git" "$OLD:refs/heads/before-rewrite"
git -C "$TS" reset -q --hard HEAD~1
echo new > "$TS/new.txt"; git -C "$TS" add -A; git -C "$TS" commit -qm new
git -C "$TS" push -q --force "$TMP/t.git" main
NEW=$(git -C "$TMP/t.git" rev-parse main)
ERR=$( { sh "$SCRIPT" "$TR" "$W" agentT --sync >/dev/null; } 2>&1 || echo "exit $?")
eq "$(head_of "$W")" "$NEW"                  "(t) moved to the rewritten tip"
eq "$(branch_of "$W")" "$BR"                 "(t) on its per-target branch, reset"
eq "$(git -C "$TR" rev-parse "refs/heads/$BR")" "$NEW" "(t) the branch reads the new tip"
eq "$(git -C "$TR" rev-parse refs/remotes/origin/before-rewrite)" "$OLD" "(t) the ref that reaches the old commits is untouched"
eq "$ERR" ""                                 "(t) a safe move prints nothing"

# --- (u) the per-target branch itself holds a commit only it reaches, with the
#         worktree attached to it. The branch is not reset: the worktree goes to
#         the tip detached, and the commit stays on the branch. -----------------
P="$TMP/u"; mkdir -p "$P"
run "$P/agentU" agentU
BR=$(branch_of "$P/agentU")
echo mine > "$P/agentU/mine-u.txt"; git -C "$P/agentU" add mine-u.txt; git -C "$P/agentU" commit -qm mine-u
MINE=$(head_of "$P/agentU")
advance_remote u1.txt
ERR=$(sync_stderr "$P/agentU" agentU)
eq "$(head_of "$P/agentU")" "$(tip)"         "(u) worktree advanced to the remote tip"
eq "$(branch_of "$P/agentU")" "DETACHED"     "(u) detached, off the branch that holds the commit"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(u) the branch keeps its commit"
eq "$ERR" ""                                 "(u) a safe move prints nothing"
advance_remote u2.txt
ERR=$(sync_stderr "$P/agentU" agentU)
eq "$(head_of "$P/agentU")" "$(tip)"         "(u) the next sync still reaches the tip"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(u) and the branch still keeps its commit"

# --- (v) a branch that is not the worktree's own is someone's work, so it stays
#         where it is, silently, even when it cannot fast-forward. One that can
#         takes its upstream's commits and stays on the branch. ------------------
P="$TMP/v"; mkdir -p "$P"
run "$P/agentV" agentV
git -C "$P/agentV" checkout -q -b person-branch
echo theirs > "$P/agentV/theirs.txt"; git -C "$P/agentV" add theirs.txt; git -C "$P/agentV" commit -qm theirs
THEIRS=$(head_of "$P/agentV")
advance_remote v1.txt
ERR=$(sync_stderr "$P/agentV" agentV)
eq "$(head_of "$P/agentV")" "$THEIRS"        "(v) a branch not its own is not moved"
eq "$(branch_of "$P/agentV")" "person-branch" "(v) and stays checked out"
eq "$ERR" ""                                 "(v) and says nothing"
git -C "$P/agentV" checkout -q --track -b person-ff origin/main
advance_remote v2.txt
ERR=$(sync_stderr "$P/agentV" agentV)
eq "$(head_of "$P/agentV")" "$(tip)"         "(v) a branch not its own fast-forwards when it can"
eq "$(branch_of "$P/agentV")" "person-ff"    "(v) and stays on that branch"
eq "$ERR" ""                                 "(v) and that says nothing either"

# --- (w) a worktree on its own branch with an uncommitted change to a tracked
#         file stays put with the change intact and one stderr line. The branch
#         has diverged, then the next commit touches the changed file, which is
#         what a home with a tracked settings change meets. ----------------------
P="$TMP/w"; mkdir -p "$P"
run "$P/agentW" agentW
BR=$(branch_of "$P/agentW")
echo mine > "$P/agentW/mine-w.txt"; git -C "$P/agentW" add mine-w.txt; git -C "$P/agentW" commit -qm mine-w
BEFORE=$(head_of "$P/agentW")
echo edited >> "$P/agentW/README.md"
advance_remote w1.txt
ERR=$(sync_stderr "$P/agentW" agentW)
eq "$(head_of "$P/agentW")" "$BEFORE"        "(w) a diverged branch with a tracked change not moved"
eq "$(branch_of "$P/agentW")" "$BR"          "(w) and still on it"
eq "$(tail -n 1 "$P/agentW/README.md")" "edited" "(w) uncommitted change intact"
has "$ERR" "uncommitted changes to tracked files" "(w) warning names the reason"
eq "$(lines "$ERR")" "1"                     "(w) exactly one stderr line"
advance_remote w2.txt
run "$P/agentW2" agentW2 --sync
BEFORE=$(head_of "$P/agentW2")
echo edited > "$P/agentW2/w2.txt"
echo next > "$SRC/w2.txt"; git -C "$SRC" add -A; git -C "$SRC" commit -qm w2-next
git -C "$SRC" push -q "$TMP/remote.git" main
ERR=$(sync_stderr "$P/agentW2" agentW2)
eq "$(head_of "$P/agentW2")" "$BEFORE"       "(w) a change the next commit touches blocks the fast-forward"
eq "$(cat "$P/agentW2/w2.txt")" "edited"     "(w) that change intact too"
has "$ERR" "uncommitted changes to tracked files" "(w) and the warning names that reason"

# --- (x) a per-target branch with no upstream has nothing to fast-forward to, so
#         it moves to the tip and tracks the default branch from then on. --------
P="$TMP/x"; mkdir -p "$P"
run "$P/agentX" agentX
BR=$(branch_of "$P/agentX")
git -C "$P/agentX" branch -q --unset-upstream
advance_remote x1.txt
ERR=$(sync_stderr "$P/agentX" agentX)
eq "$(head_of "$P/agentX")" "$(tip)"         "(x) its own branch with no upstream reaches the tip"
eq "$(branch_of "$P/agentX")" "$BR"          "(x) and stays on it"
eq "$(git -C "$P/agentX" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(x) which now tracks origin/main"
eq "$ERR" ""                                 "(x) a safe move prints nothing"

# --- (y) one ref of each kind, alone, reaches the commit on a per-target branch
#         that cannot fast-forward, which is enough to reset the branch. ----------
for KIND in remote tag branch; do
    P="$TMP/y-$KIND"; mkdir -p "$P"; A="agentY$KIND"
    run "$P/$A" "$A"
    BR=$(branch_of "$P/$A")
    echo "$KIND" > "$P/$A/y-$KIND.txt"; git -C "$P/$A" add "y-$KIND.txt"; git -C "$P/$A" commit -qm "y-$KIND"
    PINNED=$(head_of "$P/$A")
    case "$KIND" in
        remote) PIN="refs/remotes/origin/y-pin-$KIND"; git -C "$RIG" update-ref "$PIN" "$PINNED" ;;
        tag)    PIN="refs/tags/y-pin-$KIND"; git -C "$RIG" tag "y-pin-$KIND" "$PINNED" ;;
        branch) PIN="refs/heads/y-pin-$KIND"; git -C "$RIG" branch "y-pin-$KIND" "$PINNED" ;;
    esac
    advance_remote "y-$KIND-tip.txt"
    ERR=$(sync_stderr "$P/$A" "$A")
    eq "$(head_of "$P/$A")" "$(tip)"         "(y) a commit only a $KIND ref reaches: moved to the tip"
    eq "$(branch_of "$P/$A")" "$BR"          "(y) on its per-target branch, reset ($KIND)"
    eq "$(git -C "$RIG" rev-parse "$PIN")" "$PINNED" "(y) the $KIND ref still reaches the commit"
    eq "$ERR" ""                             "(y) a safe move prints nothing ($KIND)"
done

# --- (z) when git cannot answer, nothing moves that could lose a commit. A failed
#         reachability read or status leaves a detached worktree where it is, and
#         a failed reachability read never resets a branch. ----------------------
REAL_GIT=$(command -v git)
# git_failing <subcommand> — a PATH entry whose git fails that one subcommand.
git_failing() {
    local d="$TMP/fail-$1"; mkdir -p "$d"
    printf '#!/bin/sh\ncase " $* " in *" %s "*) exit 1 ;; esac\nexec "%s" "$@"\n' "$1" "$REAL_GIT" > "$d/git"
    chmod +x "$d/git"; echo "$d"
}
P="$TMP/z"; mkdir -p "$P"
run "$P/agentZ" agentZ
git -C "$P/agentZ" checkout -q --detach
BEFORE=$(head_of "$P/agentZ")
advance_remote z1.txt
ERR=$(PATH="$(git_failing rev-list):$PATH" sync_stderr "$P/agentZ" agentZ)
eq "$(head_of "$P/agentZ")" "$BEFORE"        "(z) a detached HEAD whose reach cannot be read stays"
has "$ERR" "$P/agentZ"                       "(z) and the warning names the worktree"
ERR=$(PATH="$(git_failing status):$PATH" sync_stderr "$P/agentZ" agentZ)
eq "$(head_of "$P/agentZ")" "$BEFORE"        "(z) a worktree whose status cannot be read stays"
has "$ERR" "git status failed"               "(z) and the warning says so"
run "$P/agentZ2" agentZ2
BR=$(branch_of "$P/agentZ2")
echo mine > "$P/agentZ2/mine-z.txt"; git -C "$P/agentZ2" add mine-z.txt; git -C "$P/agentZ2" commit -qm mine-z
MINE=$(head_of "$P/agentZ2")
advance_remote z2.txt
ERR=$(PATH="$(git_failing rev-list):$PATH" sync_stderr "$P/agentZ2" agentZ2)
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(z) a branch whose reach cannot be read is not reset"
eq "$(head_of "$P/agentZ2")" "$(tip)"        "(z) and the worktree reaches the tip"
eq "$(branch_of "$P/agentZ2")" "DETACHED"    "(z) detached, off that branch"

# --- (aa) a repository with no origin has nothing to sync with, so the worktree
#          stays where it is and the run says nothing. ----------------------------
NO="$TMP/noorigin"; git clone -q "$TMP/remote.git" "$NO"
P="$TMP/aa"; mkdir -p "$P"; W="$P/agentAA"
eq "$(rc_of "$NO" "$W" agentAA)" "0"         "(aa) the worktree is made"
git -C "$W" checkout -q --detach
BEFORE=$(head_of "$W")
git -C "$NO" remote remove origin
ERR=$( { sh "$SCRIPT" "$NO" "$W" agentAA --sync >/dev/null; } 2>&1 || echo "exit $?")
eq "$(head_of "$W")" "$BEFORE"               "(aa) not moved"
eq "$ERR" ""                                 "(aa) and says nothing"

# --- (ab) a branch ahead of its upstream merges as "Already up to date" and moves
#          nothing, so that success cannot be where a sync ends. A default branch
#          rewound to an ancestor leaves a per-target branch there with no new
#          commit on the remote. Each shape has its own remote and rig, since this
#          rewrites main and every other home's branch would count as a ref. --------
# rewound_home <name> — a remote, a rig and a home on its own branch at a commit
# main is about to drop. The rig's local main stays a commit behind, so only that
# branch and origin/main reach the commit. Sets RB, RR, W, BR, BASE and OLD.
rewound_home() {
    local src="$TMP/$1-src"
    git init -q -b main "$src"
    echo seed > "$src/README.md"; git -C "$src" add -A; git -C "$src" commit -qm init
    BASE=$(git -C "$src" rev-parse HEAD)
    RB="$TMP/$1.git"; git clone -q --bare "$src" "$RB"
    RR="$TMP/$1-rig"; git clone -q "$RB" "$RR"
    echo old > "$src/old.txt"; git -C "$src" add -A; git -C "$src" commit -qm old
    OLD=$(git -C "$src" rev-parse HEAD)
    git -C "$src" push -q "$RB" main
    mkdir -p "$TMP/$1"; W="$TMP/$1/agentAB"
    eq "$(rc_of "$RR" "$W" agentAB)" "0"     "(ab) the worktree is made ($1)"
    eq "$(head_of "$W")" "$OLD"              "(ab) on the commit main will drop ($1)"
    BR=$(branch_of "$W")
}
rewind_main()  { git -C "$RB" update-ref refs/heads/main "$BASE"; }
rewound_sync() { { sh "$SCRIPT" "$RR" "$W" agentAB --sync >/dev/null; } 2>&1 || echo "exit $?"; }

rewound_home ab-alone
rewind_main
ERR=$(rewound_sync)
eq "$(head_of "$W")" "$BASE"                 "(ab) a rewind's dropped commit only the branch reaches: worktree at the tip"
eq "$(branch_of "$W")" "DETACHED"            "(ab) detached, off the branch that holds the commit"
eq "$(git -C "$RR" rev-parse "refs/heads/$BR")" "$OLD" "(ab) the branch keeps the commit"
eq "$ERR" ""                                 "(ab) a safe move prints nothing"
ERR=$(rewound_sync)
eq "$(head_of "$W")" "$BASE"                 "(ab) the next sync stays at the tip"
eq "$(git -C "$RR" rev-parse "refs/heads/$BR")" "$OLD" "(ab) and the branch still keeps the commit"
eq "$ERR" ""                                 "(ab) and that prints nothing either"

rewound_home ab-reached
git -C "$RB" update-ref refs/heads/before-rewind "$OLD"
rewind_main
ERR=$(rewound_sync)
eq "$(head_of "$W")" "$BASE"                 "(ab) a rewind's dropped commit another ref reaches: worktree at the tip"
eq "$(branch_of "$W")" "$BR"                 "(ab) on its per-target branch"
eq "$(git -C "$RR" rev-parse "refs/heads/$BR")" "$BASE" "(ab) which is reset to the tip"
eq "$(git -C "$W" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(ab) and still tracks origin/main"
eq "$(git -C "$RR" rev-parse refs/remotes/origin/before-rewind)" "$OLD" "(ab) the ref that reaches the commit is untouched"
eq "$ERR" ""                                 "(ab) a safe reset prints nothing"

rewound_home ab-dirty
echo edited >> "$W/README.md"
rewind_main
ERR=$(rewound_sync)
eq "$(head_of "$W")" "$OLD"                  "(ab) a tracked change keeps a branch ahead of the tip where it is"
eq "$(branch_of "$W")" "$BR"                 "(ab) and on that branch"
eq "$(tail -n 1 "$W/README.md")" "edited"    "(ab) the change intact"
has "$ERR" "uncommitted changes to tracked files" "(ab) the warning names the reason"
eq "$(lines "$ERR")" "1"                     "(ab) exactly one stderr line"

rewound_home ab-other
git -C "$W" checkout -q --track -b person-ahead origin/main
rewind_main
ERR=$(rewound_sync)
eq "$(head_of "$W")" "$OLD"                  "(ab) a branch not its own stays ahead of its upstream"
eq "$(branch_of "$W")" "person-ahead"        "(ab) and stays checked out"
eq "$ERR" ""                                 "(ab) and says nothing"

# A commit on its own branch with nothing new upstream is the same shape, with no
# rewind behind it.
P="$TMP/ab"; mkdir -p "$P"
run "$P/agentAB" agentAB
BR=$(branch_of "$P/agentAB")
echo mine > "$P/agentAB/mine-ab.txt"; git -C "$P/agentAB" add mine-ab.txt; git -C "$P/agentAB" commit -qm mine-ab
MINE=$(head_of "$P/agentAB")
ERR=$(sync_stderr "$P/agentAB" agentAB)
eq "$(head_of "$P/agentAB")" "$(tip)"        "(ab) a local commit with nothing new upstream: worktree at the tip"
eq "$(branch_of "$P/agentAB")" "DETACHED"    "(ab) detached, off the branch that holds it"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(ab) the branch keeps the local commit"
eq "$ERR" ""                                 "(ab) that move prints nothing"

# --- (ac) a per-target branch at the tip has nothing to do, so a tracked change is
#          no refusal: live homes carry one in .claude/settings.json, and a line at
#          every start would say nothing. The same goes for a fast-forward past it. --
P="$TMP/ac"; mkdir -p "$P"
run "$P/agentAC" agentAC
BR=$(branch_of "$P/agentAC")
echo edited >> "$P/agentAC/README.md"
ERR=$(sync_stderr "$P/agentAC" agentAC)
eq "$ERR" ""                                 "(ac) at the tip with a tracked change: says nothing"
eq "$(branch_of "$P/agentAC")" "$BR"         "(ac) stays on its per-target branch"
advance_remote ac1.txt
ERR=$(sync_stderr "$P/agentAC" agentAC)
eq "$(head_of "$P/agentAC")" "$(tip)"        "(ac) a fast-forward the change is not in the way of reaches the tip"
eq "$(branch_of "$P/agentAC")" "$BR"         "(ac) and stays on that branch"
eq "$(tail -n 1 "$P/agentAC/README.md")" "edited" "(ac) with the change intact"
eq "$ERR" ""                                 "(ac) and says nothing either"

# --- (ad) the fast-forward answers for the branch's upstream, and the default branch
#          is what a home follows. A branch at an upstream that is not the default
#          branch has nothing to fast-forward to and is not at the tip. ------------
P="$TMP/ad"; mkdir -p "$P"
run "$P/agentAD" agentAD
BR=$(branch_of "$P/agentAD")
git -C "$P/agentAD" push -q origin HEAD:refs/heads/ad-other
git -C "$P/agentAD" fetch -q origin
git -C "$P/agentAD" branch -q --set-upstream-to=origin/ad-other
advance_remote ad1.txt
ERR=$(sync_stderr "$P/agentAD" agentAD)
eq "$(head_of "$P/agentAD")" "$(tip)"        "(ad) its own branch at another upstream reaches the default tip"
eq "$(branch_of "$P/agentAD")" "$BR"         "(ad) and stays on it"
eq "$(git -C "$P/agentAD" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(ad) which now tracks origin/main"
eq "$ERR" ""                                 "(ad) a safe move prints nothing"

# --- (ae) with origin/HEAD unset there is no default tip to reach, so the
#          fast-forward is as far as a sync gets, and it says why. Its own rig, since
#          origin/HEAD is shared by all of a repo's worktrees, and set so its fetch
#          does not put origin/HEAD back, as a current git otherwise does. -----------
NH="$TMP/noheadrig"; git clone -q "$TMP/remote.git" "$NH"
P="$TMP/ae"; mkdir -p "$P"; W="$P/agentAE"
eq "$(rc_of "$NH" "$W" agentAE)" "0"         "(ae) the worktree is made"
BR=$(branch_of "$W")
git -C "$NH" config remote.origin.followRemoteHEAD never
git -C "$NH" remote set-head origin -d
advance_remote ae1.txt
ERR=$( { sh "$SCRIPT" "$NH" "$W" agentAE --sync >/dev/null; } 2>&1 || echo "exit $?")
eq "$(head_of "$W")" "$(tip)"                "(ae) its own branch still fast-forwards to its upstream"
eq "$(branch_of "$W")" "$BR"                 "(ae) and stays on it"
has "$ERR" "origin/HEAD is unset"            "(ae) the warning names the reason"
eq "$(lines "$ERR")" "1"                     "(ae) exactly one stderr line, so the run exited 0"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
