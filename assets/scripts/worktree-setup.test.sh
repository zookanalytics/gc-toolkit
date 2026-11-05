#!/usr/bin/env bash
# Hermetic test for worktree-setup.sh: staging a non-empty target, the
# provisioning (bead redirect, local excludes) a re-run completes, and --sync,
# which saves what a home's move would lose and moves it to the default-branch
# tip.
#
# Uses a real temp git rig (a clone of a bare remote, so origin/HEAD resolves)
# and drives the real script. No live city, gc, or network. Covers:
#   (e) a file staged from a non-empty target loses to the file the checkout
#       brought, and a file only the stage holds comes back;
#   (f) a normal run leaves no stage dir behind, and the provider settings gc
#       stages into a new home before pre_start come back;
#   (h) a staged directory loses to a checked-out file at the same path: the
#       existing file wins and the whole losing source subtree is dropped, and
#       the entries past it still come back;
#   (i) --sync moves a detached home behind the remote to the default-branch
#       tip, on its per-target branch with the upstream it was made with. What
#       gc writes there untracked survives, as does a session's untracked file,
#       nothing is saved or printed, and the next sync follows the tip again
#       without rewriting the repository's shared config;
#   (j) a detached HEAD on a commit no ref holds is saved as head, under
#       refs/gc-toolkit/home-save/<per-target branch>/<UTC time>/, and the home
#       still moves;
#   (k) a commit only the per-target branch holds is saved before the move
#       resets that branch to the tip;
#   (l) a detached home whose per-target branch alone holds a commit saves it
#       as branch, and does not save HEAD, which the default branch holds;
#   (m) a commit another ref holds is not saved: one a squash-landed branch's
#       remote-tracking ref holds, or one a tag holds;
#   (n) a post-checkout hook that fails the add leaves a half-built worktree
#       (git keeps it), and the re-run gives it the bead redirect and the Gas
#       City exclude marker, so runtime files stay out of git status, and moves
#       it with that hook off;
#   (o) a re-run keeps a non-empty redirect, so a deliberate one survives, and
#       rewrites an empty one;
#   (p) a main checkout (.git is a directory) is never given a redirect, its
#       exclude file is left alone, and --sync leaves its branch alone;
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
#   (s) a home on a branch not its own moves to its own branch at the tip, and
#       the other branch keeps its commit, so nothing is saved;
#   (t) in a rig that tracks a provider settings file, gc's merge into it is a
#       tracked change, which the move keeps, at the tip and past it, saving
#       nothing;
#   (u) a tracked change in a file the tip changes is saved as changes, and the
#       forced move brings the tip's file;
#   (v) an untracked file in the way of one the tip adds does not stop the
#       move, which replaces it;
#   (w) a repository with no origin is left where it is, silently;
#   (x) with origin/HEAD unset the run fails with a line saying why, and the
#       home stays where it is;
#   (y) a move git cannot make fails the run with git's reason, so the session
#       does not start;
#   (z) a commit whose reach git cannot read is saved.

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
# sync_in <rig> <home> <agent> — the --sync run's stderr alone; a non-zero exit
# is appended as "exit <rc>"
sync_in()     { { sh "$SCRIPT" "$1" "$2" "$3" --sync >/dev/null; } 2>&1 || echo "exit $?"; }
sync_stderr() { sync_in "$RIG" "$1" "$2"; }
# saves <repo> <per-target branch> — the save refs a home's syncs left, one per line
saves() { git -C "$1" for-each-ref --format='%(refname)' "refs/gc-toolkit/home-save/$2/"; }
# saved <repo> <per-target branch> <name> — the commit a home's save of <name> holds
saved() { git -C "$1" for-each-ref --format='%(objectname)' "refs/gc-toolkit/home-save/$2/*/$3"; }
# land one commit on the remote's main, as a merged PR would
advance_remote() {
    echo "$1" > "$SRC/$1"; git -C "$SRC" add -A; git -C "$SRC" commit -qm "$1"
    git -C "$SRC" push -q "$TMP/remote.git" main
}
tip()       { git -C "$TMP/remote.git" rev-parse main; }
head_of()   { git -C "$1" rev-parse HEAD; }
branch_of() { git -C "$1" symbolic-ref -q --short HEAD || echo DETACHED; }
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

# --- (i) a detached home behind the remote moves to the tip on --sync, back on
#         its per-target branch with the upstream it was made with. What gc
#         writes into a home untracked survives the move: its provider settings
#         under an excluded path, and the marker gc's prune leaves in a home it
#         keeps. So does a session's untracked file. A move that loses nothing
#         saves and prints nothing, and the next sync follows the tip again. ---
P="$TMP/i"; mkdir -p "$P"
run "$P/agentI" agentI
BR=$(branch_of "$P/agentI")
git -C "$P/agentI" checkout -q --detach
mkdir -p "$P/agentI/.claude" "$P/agentI/.scratch"
echo '{"hooks":{}}' > "$P/agentI/.claude/settings.json"
echo 'reason=dirty' > "$P/agentI/.worktree-stale"
echo keep > "$P/agentI/.scratch/notes"
advance_remote i1.txt
ERR=$(sync_stderr "$P/agentI" agentI)
eq "$(head_of "$P/agentI")" "$(tip)"         "(i) a detached home moves to the remote tip"
eq "$(branch_of "$P/agentI")" "$BR"          "(i) back on its per-target branch"
eq "$(git -C "$P/agentI" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(i) which keeps the upstream it was made with"
eq "$(cat "$P/agentI/.claude/settings.json")" '{"hooks":{}}' "(i) gc's provider settings survive the move"
eq "$(cat "$P/agentI/.worktree-stale")" "reason=dirty" "(i) and so does the marker gc's prune leaves"
eq "$(cat "$P/agentI/.scratch/notes")" "keep" "(i) and a session's untracked file"
eq "$(saves "$RIG" "$BR")" ""                "(i) a move that loses nothing saves nothing"
eq "$ERR" ""                                 "(i) and prints nothing"
advance_remote i2.txt
CONFIG_INODE=$(ls -i "$RIG/.git/config" | awk '{print $1}')
ERR=$(sync_stderr "$P/agentI" agentI)
eq "$(head_of "$P/agentI")" "$(tip)"         "(i) the next sync follows the tip"
eq "$(branch_of "$P/agentI")" "$BR"          "(i) on the same branch"
eq "$ERR" ""                                 "(i) and prints nothing either"
eq "$(ls -i "$RIG/.git/config" | awk '{print $1}')" "$CONFIG_INODE" \
    "(i) a sync leaves the config every worktree of the repository shares unwritten"

# --- (j) a detached HEAD on a commit no ref holds is saved as head before the
#         move, under a ref named for the home's per-target branch and the UTC
#         time, and the home still reaches the tip. ---------------------------
P="$TMP/j"; mkdir -p "$P"
run "$P/agentJ" agentJ
BR=$(branch_of "$P/agentJ")
git -C "$P/agentJ" checkout -q --detach
echo local > "$P/agentJ/local.txt"; git -C "$P/agentJ" add local.txt; git -C "$P/agentJ" commit -qm local
LOCAL=$(head_of "$P/agentJ")
advance_remote j1.txt
ERR=$(sync_stderr "$P/agentJ" agentJ)
eq "$(saved "$RIG" "$BR" head)" "$LOCAL"     "(j) the commit no ref held is saved as head"
eq "$(saves "$RIG" "$BR" | grep -cE "^refs/gc-toolkit/home-save/$BR/[0-9]{8}T[0-9]{6}Z/head\$")" "1" \
    "(j) at refs/gc-toolkit/home-save/<per-target branch>/<UTC time>/head"
eq "$(head_of "$P/agentJ")" "$(tip)"         "(j) and the home still moves to the tip"
eq "$(branch_of "$P/agentJ")" "$BR"          "(j) on its per-target branch"
eq "$ERR" ""                                 "(j) printing nothing"

# --- (k) a commit only the per-target branch holds is saved, as head since the
#         home is on that branch, before the move resets the branch to the tip.
P="$TMP/k"; mkdir -p "$P"
run "$P/agentK" agentK
BR=$(branch_of "$P/agentK")
echo mine > "$P/agentK/mine.txt"; git -C "$P/agentK" add mine.txt; git -C "$P/agentK" commit -qm mine
MINE=$(head_of "$P/agentK")
advance_remote k1.txt
ERR=$(sync_stderr "$P/agentK" agentK)
eq "$(saved "$RIG" "$BR" head)" "$MINE"      "(k) the branch's own commit is saved"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$(tip)" "(k) and the branch is reset to the tip"
eq "$(branch_of "$P/agentK")" "$BR"          "(k) with the home on it"
eq "$ERR" ""                                 "(k) printing nothing"

# --- (l) a detached home whose per-target branch alone holds a commit: the move
#         resets that branch, so its commit is saved as branch. HEAD, which the
#         default branch holds, is not saved. ----------------------------------
P="$TMP/l"; mkdir -p "$P"
run "$P/agentL" agentL
BR=$(branch_of "$P/agentL")
BASE=$(head_of "$P/agentL")
echo mine > "$P/agentL/mine-l.txt"; git -C "$P/agentL" add mine-l.txt; git -C "$P/agentL" commit -qm mine-l
MINE=$(head_of "$P/agentL")
git -C "$P/agentL" checkout -q --detach "$BASE"
advance_remote l1.txt
ERR=$(sync_stderr "$P/agentL" agentL)
eq "$(saved "$RIG" "$BR" branch)" "$MINE"    "(l) the branch's commit is saved as branch"
eq "$(saved "$RIG" "$BR" head)" ""           "(l) and HEAD, which origin/main holds, is not saved"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$(tip)" "(l) the branch is reset to the tip"
eq "$(branch_of "$P/agentL")" "$BR"          "(l) with the home on it"
eq "$ERR" ""                                 "(l) printing nothing"

# --- (m) a commit another ref holds is not saved. A detached HEAD on a
#         squash-landed branch's commit, which its remote-tracking ref holds,
#         moves to the tip with nothing saved, and so does a per-target branch
#         on a commit a tag holds. ---------------------------------------------
P="$TMP/m"; mkdir -p "$P"
run "$P/agentM" agentM
BR=$(branch_of "$P/agentM")
git -C "$P/agentM" checkout -q --detach
echo landed > "$P/agentM/landed.txt"; git -C "$P/agentM" add landed.txt; git -C "$P/agentM" commit -qm landed
git -C "$P/agentM" push -q origin HEAD:refs/heads/polecat/m-work
git -C "$RIG" fetch -q origin
advance_remote m1.txt
ERR=$(sync_stderr "$P/agentM" agentM)
eq "$(head_of "$P/agentM")" "$(tip)"         "(m) a HEAD a remote-tracking ref holds moves to the tip"
eq "$(saves "$RIG" "$BR")" ""                "(m) with nothing saved"
eq "$ERR" ""                                 "(m) and nothing printed"
echo tagged > "$P/agentM/tagged.txt"; git -C "$P/agentM" add tagged.txt; git -C "$P/agentM" commit -qm tagged
git -C "$RIG" tag m-pin "$(head_of "$P/agentM")"
advance_remote m2.txt
ERR=$(sync_stderr "$P/agentM" agentM)
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$(tip)" "(m) a per-target branch on a commit a tag holds is reset to the tip"
eq "$(saves "$RIG" "$BR")" ""                "(m) with nothing saved either"
eq "$ERR" ""                                 "(m) or printed"

# --- (n) a post-checkout hook that fails the add: git keeps the worktree, so the
#         first run leaves it half-built, and the re-run completes it. The
#         re-run's move runs with hooks off, so the same hook does not fail it.
#         The rig is its own clone because the exclude file is shared by all of a
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
advance_remote n1.txt
eq "$(rc_of "$HR" "$W" agentN --sync)" "0"   "(n) the re-run succeeds"
eq "$(head_of "$W")" "$(tip)"                "(n) and moves the worktree to the tip, the failing hook off"
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
eq "$(branch_of "$MAIN")" "main"             "(p) and --sync leaves its branch alone"

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

# --- (s) a home on a branch that is not its own moves to its own branch at the
#         tip. The other branch keeps its commit, so nothing is saved. ---------
P="$TMP/s"; mkdir -p "$P"
run "$P/agentS" agentS
BR=$(branch_of "$P/agentS")
git -C "$P/agentS" checkout -q -b person-branch
echo theirs > "$P/agentS/theirs.txt"; git -C "$P/agentS" add theirs.txt; git -C "$P/agentS" commit -qm theirs
THEIRS=$(head_of "$P/agentS")
advance_remote s1.txt
ERR=$(sync_stderr "$P/agentS" agentS)
eq "$(head_of "$P/agentS")" "$(tip)"         "(s) a home on another branch moves to the tip"
eq "$(branch_of "$P/agentS")" "$BR"          "(s) on its per-target branch"
eq "$(git -C "$RIG" rev-parse refs/heads/person-branch)" "$THEIRS" "(s) the other branch keeps its commit"
eq "$(saves "$RIG" "$BR")" ""                "(s) so nothing is saved"
eq "$ERR" ""                                 "(s) and nothing printed"

# --- (t) gc merges its hooks into a home's provider settings before pre_start
#         runs, and a rig can track that file, so the merge is a tracked change.
#         The move keeps a tracked change it does not overwrite, at the tip and
#         when the tip moves past it, and saves nothing. Its own remote, whose
#         main tracks .claude/settings.json. --------------------------------
TS="$TMP/tsrc"; git init -q -b main "$TS"
mkdir -p "$TS/.claude"; echo '{"repo":1}' > "$TS/.claude/settings.json"; echo seed > "$TS/README.md"
git -C "$TS" add -A; git -C "$TS" commit -qm init
git clone -q --bare "$TS" "$TMP/t.git"
TR="$TMP/trig"; git clone -q "$TMP/t.git" "$TR"
# land one commit on this remote's main, writing <content> to <path>
t_advance() { mkdir -p "$(dirname "$TS/$1")"; echo "$2" > "$TS/$1"; git -C "$TS" add -A; git -C "$TS" commit -qm "$1"; git -C "$TS" push -q "$TMP/t.git" main; }
P="$TMP/t"; mkdir -p "$P"; W="$P/agentT"
eq "$(rc_of "$TR" "$W" agentT)" "0"          "(t) the home is made"
BR=$(branch_of "$W")
echo '{"hooks":"gc","repo":1}' > "$W/.claude/settings.json"
ERR=$(sync_in "$TR" "$W" agentT)
eq "$(cat "$W/.claude/settings.json")" '{"hooks":"gc","repo":1}' "(t) at the tip, gc's merge survives the move"
eq "$ERR" ""                                 "(t) which prints nothing"
t_advance t1.txt t1
ERR=$(sync_in "$TR" "$W" agentT)
eq "$(head_of "$W")" "$(git -C "$TMP/t.git" rev-parse main)" "(t) the home moves to the new tip"
eq "$(cat "$W/.claude/settings.json")" '{"hooks":"gc","repo":1}' "(t) carrying gc's merge with it"
eq "$(saves "$TR" "$BR")" ""                 "(t) and saves nothing"
eq "$ERR" ""                                 "(t) or prints anything"

# --- (u) when the tip changes the file a tracked change sits in, git refuses the
#         move. The tracked changes are saved as changes, and the forced move
#         brings the tip's file, leaving the tracked tree clean. ----------------
t_advance .claude/settings.json '{"repo":2}'
ERR=$(sync_in "$TR" "$W" agentT)
eq "$(head_of "$W")" "$(git -C "$TMP/t.git" rev-parse main)" "(u) the home still moves to the tip"
eq "$(cat "$W/.claude/settings.json")" '{"repo":2}' "(u) with the tip's file"
eq "$(git -C "$TR" show "$(saved "$TR" "$BR" changes):.claude/settings.json" 2>&1)" '{"hooks":"gc","repo":1}' \
    "(u) and the change it overwrote is saved as changes"
eq "$(git -C "$W" status --porcelain --untracked-files=no)" "" "(u) the tracked tree is clean"
eq "$ERR" ""                                 "(u) the forced move prints nothing"

# --- (v) an untracked file in the way of one the tip adds does not keep the home
#         where it is: the forced move replaces it with the tip's file. With no
#         tracked change, nothing is saved. ---------------------------------
P="$TMP/v"; mkdir -p "$P"
run "$P/agentV" agentV
BR=$(branch_of "$P/agentV")
echo mine > "$P/agentV/v1.txt"
advance_remote v1.txt
ERR=$(sync_stderr "$P/agentV" agentV)
eq "$(head_of "$P/agentV")" "$(tip)"         "(v) an untracked file in the tip's way does not stop the move"
eq "$(cat "$P/agentV/v1.txt")" "v1.txt"      "(v) the tip's file replaces it"
eq "$(saves "$RIG" "$BR")" ""                "(v) nothing is saved"
eq "$ERR" ""                                 "(v) and nothing printed"

# --- (w) a repository with no origin has nothing to sync with, so the home stays
#         where it is and the run says nothing. --------------------------------
NO="$TMP/noorigin"; git clone -q "$TMP/remote.git" "$NO"
P="$TMP/w"; mkdir -p "$P"; W="$P/agentW"
eq "$(rc_of "$NO" "$W" agentW)" "0"          "(w) the home is made"
git -C "$W" checkout -q --detach
BEFORE=$(head_of "$W")
git -C "$NO" remote remove origin
ERR=$(sync_in "$NO" "$W" agentW)
eq "$(head_of "$W")" "$BEFORE"               "(w) not moved"
eq "$ERR" ""                                 "(w) and says nothing"

# --- (x) with origin/HEAD unset there is no default tip to move to, so the run
#         fails with a line saying why, and the home stays where it is. Its own
#         rig, since origin/HEAD is shared by all of a repo's worktrees, set so
#         its fetch does not put origin/HEAD back, as a current git otherwise
#         does. --------------------------------------------------------------
NH="$TMP/noheadrig"; git clone -q "$TMP/remote.git" "$NH"
P="$TMP/x"; mkdir -p "$P"; W="$P/agentX"
eq "$(rc_of "$NH" "$W" agentX)" "0"          "(x) the home is made"
BEFORE=$(head_of "$W")
git -C "$NH" config remote.origin.followRemoteHEAD never
git -C "$NH" remote set-head origin -d
advance_remote x1.txt
ERR=$(sync_in "$NH" "$W" agentX)
eq "$(head_of "$W")" "$BEFORE"               "(x) the home is not moved"
has "$ERR" "origin/HEAD is unset"            "(x) the run says why"
has "$ERR" "exit 1"                          "(x) and fails, so the session does not start"

# --- (y) a move git cannot make fails the run with git's reason, so the session
#         does not start: here another worktree has the home's branch checked
#         out. ---------------------------------------------------------------
P="$TMP/y"; mkdir -p "$P"
run "$P/agentY" agentY
BR=$(branch_of "$P/agentY")
git -C "$P/agentY" checkout -q --detach
git -C "$RIG" worktree add -q "$P/other" "$BR"
advance_remote y1.txt
ERR=$(sync_stderr "$P/agentY" agentY)
has "$ERR" "exit 1"                          "(y) a move git refuses fails the run"
has "$ERR" "$BR"                             "(y) with git's reason, which names the branch"
eq "$(branch_of "$P/agentY")" "DETACHED"     "(y) and the home stays where it was"

# --- (z) when git cannot say whether another ref holds a commit, the commit is
#         saved anyway, and the home still moves. ------------------------------
mkdir -p "$TMP/fail-rev-list"
printf '#!/bin/sh\ncase " $* " in *" rev-list "*) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$TMP/fail-rev-list/git"
chmod +x "$TMP/fail-rev-list/git"
P="$TMP/z"; mkdir -p "$P"
run "$P/agentZ" agentZ
BR=$(branch_of "$P/agentZ")
HELD=$(head_of "$P/agentZ")
advance_remote z1.txt
ERR=$(PATH="$TMP/fail-rev-list:$PATH" sync_stderr "$P/agentZ" agentZ)
eq "$(saved "$RIG" "$BR" head)" "$HELD"      "(z) a commit whose reach git cannot read is saved"
eq "$(head_of "$P/agentZ")" "$(tip)"         "(z) and the home still moves to the tip"
eq "$ERR" ""                                 "(z) printing nothing"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
