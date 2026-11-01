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
#       such as a squash-landed branch's remote-tracking ref or a tag;
#   (t) a per-target branch left behind by a rewritten default branch is reset
#       to the tip when another ref reaches its commits;
#   (u) a per-target branch holding a commit only it reaches is not reset: the
#       attached worktree is detached at the tip and the branch keeps the commit;
#   (v) a worktree on a branch that is not its own stays where it is.
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
#         remote-tracking ref reaches it first, then only a tag. -----------------
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
#         where it is, silently, even when it cannot fast-forward. --------------
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
