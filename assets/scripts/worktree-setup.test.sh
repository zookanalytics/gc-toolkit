#!/usr/bin/env bash
# Hermetic test for worktree-setup.sh: staging a non-empty target, the
# provisioning (bead redirect, local excludes) a re-run completes, and --sync,
# which fast-forwards a home to the default-branch tip, or fails its start and
# reports what in the home stopped it.
#
# Uses a real temp git rig (a clone of a bare remote, so origin/HEAD resolves)
# and drives the real script, with a stub in place of patrol-finding.sh that
# records each call. No live city, gc, store or network. Covers:
#   (e) a file staged from a non-empty target loses to the file the checkout
#       brought, and a file only the stage holds comes back;
#   (f) a normal run leaves no stage dir behind, and the provider settings gc
#       stages into a new home before pre_start come back;
#   (h) a staged directory loses to a checked-out file at the same path: the
#       existing file wins and the whole losing source subtree is dropped, and
#       the entries past it still come back;
#   (i) --sync moves a detached home on the tip's history to the tip, back on
#       its per-target branch, which tracks origin/main. What gc writes there
#       stays and is no edit, the run prints and reports nothing and records
#       the report's clear, and the next sync fast-forwards the branch without
#       rewriting the repository's shared config;
#   (j) a detached HEAD on a commit the tip lacks fails the start: the home
#       stays, and one report under the home's key names the commits and the
#       move that clears them;
#   (k) a change to a tracked file fails the start, the change intact;
#   (l) a detached home whose per-target branch holds a commit the tip lacks
#       moves to the tip detached, and the branch keeps its commit;
#   (m) an untracked file gc did not write fails the start, the file intact,
#       and the report lists five such files and counts the rest;
#   (n) a post-checkout hook that fails the add leaves a half-built worktree
#       (git keeps it), and the re-run gives it the bead redirect and the Gas
#       City exclude marker, so runtime files stay out of git status, and
#       fast-forwards it, which runs no checkout hook. A detached home's move
#       succeeds though that hook then fails the checkout that moved it;
#   (o) a re-run keeps a non-empty redirect, so a deliberate one survives, and
#       rewrites an empty one;
#   (p) a main checkout (.git is a directory) is never given a redirect, its
#       exclude file is left alone, and --sync leaves its branch alone and
#       reports nothing;
#   (q) a worktree whose git metadata is gone still gets its redirect, and the
#       run still exits 0;
#   (r) gc's writes stay out of git status in the worktree and in the rig
#       checkout that shares its exclude file: the skill links its ownership
#       manifests name under .agents/skills/, the manifest itself,
#       .gc/settings.json and .beads.gate.lock, and none of them fails a sync.
#       Everything else a person keeps there still shows and stages, in both:
#       a plain file, a link of their own, a new skill directory, and changes
#       to a skill the repo tracks. A link gc adds later is hidden by the next
#       run, a manifest name git would read as a pattern or that ends in a
#       newline is never written, and without jq or a readable manifest the
#       run still succeeds and adds no name;
#   (s) a home on a branch not its own fails the start and stays on it;
#   (t) in a rig that tracks a provider settings file, gc's merge into it is
#       no edit, and the home fast-forwards with it; when the tip changes that
#       file, git refuses the fast-forward, which fails the start with git's
#       reason, and the report names the move to make by hand, for a home on
#       its branch and for a detached one. After that move, and gc's merge
#       made again, the next start goes through;
#   (u) a path gc writes that the rig's .gitignore re-includes is no edit
#       either, and a person's file beside it still fails the start;
#   (v) a rebase, a merge and a bisect a session left stopped each fail the
#       start, their state kept;
#   (w) a repository with no origin is left where it is, silently and with no
#       report;
#   (x) with origin/HEAD unset, or naming a branch that is gone, the start
#       fails, the home stays, and the report names the fix;
#   (y) a detached home whose per-target branch another worktree holds moves
#       to the tip detached;
#   (z) after a rewrite of the default branch, a home on the old history fails
#       its start, the move its report names lets the next start through, and
#       that start records the clear under the report's key;
#   (aa) a report that does not land still fails the start, and the run says
#        so;
#   (ab) a HEAD that names no commit fails the start.

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

# The stub in place of patrol-finding.sh writes one line per call: the key,
# report or cleared, the title and the message's first line, tab-separated.
# FINDING_RC is its exit status.
FINDING_LOG="$TMP/finding.log"; : > "$FINDING_LOG"
cat > "$TMP/finding-stub" <<'STUB'
#!/usr/bin/env bash
key=""; mode=report; title=""; msg=""
while [ $# -gt 0 ]; do
    case "$1" in
        --key) key="$2"; shift 2 ;;
        --title) title="$2"; shift 2 ;;
        --message) msg="$2"; shift 2 ;;
        --cleared) mode=cleared; shift ;;
        *) shift ;;
    esac
done
printf '%s\t%s\t%s\t%s\n' "$key" "$mode" "$title" "${msg%%$'\n'*}" >> "$FINDING_LOG"
exit "${FINDING_RC:-0}"
STUB
chmod +x "$TMP/finding-stub"
export GC_PATROL_FINDING_TOOL="$TMP/finding-stub" FINDING_LOG

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
# land one commit on the remote's main, as a merged PR would
advance_remote() {
    echo "$1" > "$SRC/$1"; git -C "$SRC" add -A; git -C "$SRC" commit -qm "$1"
    git -C "$SRC" push -q "$TMP/remote.git" main
}
tip()       { git -C "$TMP/remote.git" rev-parse main; }
head_of()   { git -C "$1" rev-parse HEAD; }
branch_of() { git -C "$1" symbolic-ref -q --short HEAD || echo DETACHED; }
has()       { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 ('$1' lacks '$2')" ;; esac; }
lacks()     { case "$1" in *"$2"*) bad "$3 ('$1' has '$2')" ;; *) ok "$3" ;; esac; }
# the run's exit status, captured so an expected failure does not end the suite
rc_of()     { local rc=0; sh "$SCRIPT" "$@" >>"$TMP/run.log" 2>&1 || rc=$?; echo "$rc"; }
# gitpath <home> <name> — the absolute path git gives a file in the home's git dir
gitpath()   { git -C "$1" rev-parse --path-format=absolute --git-path "$2"; }
# whether the exclude file git resolves for a checkout carries the Gas City marker
marker_in() {
    grep -qF "# Gas City worktree infrastructure (local excludes)" \
        "$(git -C "$1" rev-parse --path-format=absolute --git-path info/exclude)" && echo yes || echo no
}
# key_of <home> <agent> — the report key the script gives a home
key_of() { printf 'home-sync.gc-%s-%s' "$2" "$(printf '%s' "$1" | git hash-object --stdin | cut -c1-12)"; }
# calls <home> <agent> <report|cleared> — how many such calls the home's key got
calls() {
    awk -F'\t' -v k="$(key_of "$1" "$2")" -v m="$3" '$1 == k && $2 == m' "$FINDING_LOG" | wc -l | tr -d ' '
}
# reported <home> <agent> — the title and first message line of the home's last report
reported() {
    awk -F'\t' -v k="$(key_of "$1" "$2")" '$1 == k && $2 == "report" { line = $3 " | " $4 } END { print line }' "$FINDING_LOG"
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

# --- (i) a detached home on the tip's history moves to the tip on --sync, back
#         on its per-target branch, which tracks origin/main as the home was
#         made. What gc writes there stays, and none of it is an edit: its
#         provider settings, the city settings session start stages, bd's
#         workspace gate, and the marker gc's prune leaves in a home it keeps.
#         The run prints and reports nothing, and records that the home's
#         report has cleared. The next sync fast-forwards the branch, leaving
#         the config every worktree of the repository shares unwritten. -------
P="$TMP/i"; mkdir -p "$P"; W="$P/agentI"
run "$W" agentI
BR=$(branch_of "$W")
git -C "$W" checkout -q --detach
mkdir -p "$W/.claude" "$W/.gc"
echo '{"hooks":{}}' > "$W/.claude/settings.json"
echo '{}' > "$W/.gc/settings.json"; : > "$W/.beads.gate.lock"
echo 'reason=dirty' > "$W/.worktree-stale"
advance_remote i1.txt
ERR=$(sync_stderr "$W" agentI)
eq "$(head_of "$W")" "$(tip)"                "(i) a detached home moves to the remote tip"
eq "$(branch_of "$W")" "$BR"                 "(i) back on its per-target branch"
eq "$(git -C "$W" rev-parse --abbrev-ref '@{upstream}' 2>&1)" "origin/main" "(i) which tracks origin/main"
eq "$(cat "$W/.claude/settings.json")" '{"hooks":{}}' "(i) gc's provider settings stay"
eq "$(cat "$W/.worktree-stale")" "reason=dirty" "(i) and so does the marker gc's prune leaves"
eq "$ERR" ""                                 "(i) the run prints nothing"
eq "$(calls "$W" agentI report):$(calls "$W" agentI cleared)" "0:1" \
    "(i) reports nothing, and records that the home's report has cleared"
advance_remote i2.txt
CONFIG_INODE=$(ls -i "$RIG/.git/config" | awk '{print $1}')
ERR=$(sync_stderr "$W" agentI)
eq "$(head_of "$W"):$(branch_of "$W")" "$(tip):$BR" "(i) the next sync fast-forwards the branch to the tip"
eq "$ERR" ""                                 "(i) printing nothing either"
eq "$(ls -i "$RIG/.git/config" | awk '{print $1}')" "$CONFIG_INODE" \
    "(i) and leaves the config every worktree of the repository shares unwritten"

# --- (j) a detached HEAD on a commit the tip lacks fails the start. The home
#         stays where it is, and one report under the home's key names the
#         commits and the move that clears them, which stderr carries too. ----
P="$TMP/j"; mkdir -p "$P"; W="$P/agentJ"
run "$W" agentJ
git -C "$W" checkout -q --detach
echo local > "$W/local.txt"; git -C "$W" add local.txt; git -C "$W" commit -qm local
LOCAL=$(head_of "$W")
advance_remote j1.txt
ERR=$(sync_stderr "$W" agentJ)
has "$ERR" "exit 1"                          "(j) a HEAD the tip lacks fails the start"
eq "$(head_of "$W"):$(branch_of "$W")" "$LOCAL:DETACHED" "(j) and the home stays where it is"
eq "$(calls "$W" agentJ report)" "1"         "(j) one report, under the home's key"
REP=$(reported "$W" agentJ)
has "$REP" "Agent home agentJ did not start: commits origin/main lacks on its HEAD (1, newest $(git -C "$W" rev-parse --short HEAD))" \
    "(j) its title names the commits"
has "$REP" "$W did not start, because its sync found commits" "(j) its message names the home"
has "$REP" "git -C '$W' checkout --detach origin/HEAD" "(j) and the move that clears it"
has "$ERR" "git -C '$W' checkout --detach origin/HEAD" "(j) which the run's stderr carries too"

# --- (k) a change to a tracked file fails the start, the change intact. ------
P="$TMP/k"; mkdir -p "$P"; W="$P/agentK"
run "$W" agentK
BEFORE=$(head_of "$W")
echo edited >> "$W/README.md"
advance_remote k1.txt
ERR=$(sync_stderr "$W" agentK)
has "$ERR" "exit 1"                          "(k) a tracked change fails the start"
eq "$(head_of "$W"):$(tail -n 1 "$W/README.md")" "$BEFORE:edited" "(k) the home is not moved, and the change is intact"
REP=$(reported "$W" agentK)
has "$REP" "changes to files git tracks (README.md)" "(k) the report names the file"
has "$REP" "git -C '$W' reset --hard"        "(k) and how to discard the change"

# --- (l) a detached home whose per-target branch holds a commit the tip lacks
#         moves to the tip detached, and the branch keeps its commit. ---------
P="$TMP/l"; mkdir -p "$P"; W="$P/agentL"
run "$W" agentL
BR=$(branch_of "$W")
BASE=$(head_of "$W")
echo mine > "$W/mine.txt"; git -C "$W" add mine.txt; git -C "$W" commit -qm mine
MINE=$(head_of "$W")
git -C "$W" checkout -q --detach "$BASE"
advance_remote l1.txt
ERR=$(sync_stderr "$W" agentL)
eq "$(head_of "$W"):$(branch_of "$W")" "$(tip):DETACHED" "(l) the home moves to the tip, detached"
eq "$(git -C "$RIG" rev-parse "refs/heads/$BR")" "$MINE" "(l) and its branch keeps its commit"
eq "$ERR:$(calls "$W" agentL report)" ":0"   "(l) silently, with no report"

# --- (m) an untracked file gc did not write fails the start, the file intact.
#         The report lists five such files and counts the rest. ---------------
P="$TMP/m"; mkdir -p "$P"; W="$P/agentM"
run "$W" agentM
BEFORE=$(head_of "$W")
echo mine > "$W/findings.json"
advance_remote m1.txt
ERR=$(sync_stderr "$W" agentM)
has "$ERR" "exit 1"                          "(m) an untracked file fails the start"
eq "$(head_of "$W"):$(cat "$W/findings.json")" "$BEFORE:mine" "(m) the home and the file stay as they were"
has "$(reported "$W" agentM)" "files git does not track (findings.json)" "(m) the report names the file"
for N in 1 2 3 4 5; do echo n > "$W/note$N.md"; done
has "$(sync_stderr "$W" agentM)" "files git does not track (findings.json, note1.md, note2.md, note3.md, note4.md, and 1 more)" \
    "(m) five files are listed, and the rest counted"

# --- (n) a post-checkout hook that fails the add: git keeps the worktree, so the
#         first run leaves it half-built, and the re-run completes it. The
#         re-run's fast-forward is a merge, which runs no checkout hook. A
#         detached home moves by a checkout, and the hook's failure after it
#         does not fail the start. The rig is its own clone because the exclude
#         file is shared by all of a repo's worktrees, and the other cases'
#         worktrees already marked $RIG's.
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
eq "$(head_of "$W")" "$(tip)"                "(n) and fast-forwards the worktree to the tip"
eq "$(cat "$W/.beads/redirect" 2>/dev/null)" "$HR/.beads" "(n) the re-run writes the bead redirect"
eq "$(marker_in "$W")" "yes"                 "(n) the re-run writes the Gas City exclude marker"
mkdir -p "$W/.claude"; echo x > "$W/.claude/settings.json"
eq "$(git -C "$W" status --porcelain)" ""    "(n) runtime files stay out of git status"
BR=$(branch_of "$W")
git -C "$W" checkout -q --detach 2>/dev/null || true
advance_remote n2.txt
eq "$(rc_of "$HR" "$W" agentN --sync)" "0"   "(n) a detached home's move succeeds though the hook fails the checkout after it"
eq "$(head_of "$W"):$(branch_of "$W")" "$(tip):$BR" "(n) and the home is on its branch at the tip"
BASE=$(head_of "$W")
echo mine > "$W/mine-n.txt"; git -C "$W" add mine-n.txt; git -C "$W" commit -qm mine-n
git -C "$W" checkout -q --detach "$BASE" 2>/dev/null || true
advance_remote n3.txt
eq "$(rc_of "$HR" "$W" agentN --sync)" "0"   "(n) so does a move to the tip detached, its branch holding a commit the tip lacks"
eq "$(head_of "$W"):$(branch_of "$W")" "$(tip):DETACHED" "(n) which leaves the home detached at the tip"

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
eq "$(calls "$MAIN" agentP report):$(calls "$MAIN" agentP cleared)" "0:0" "(p) reporting nothing"

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
#         checkout, which shares its exclude file, and none of them fails a
#         sync. gc's skill links are hidden by the exact names its ownership
#         manifest records, so what a person keeps under .agents/skills/ still
#         shows: a skill the repo tracks, a new skill, a plain file and a link
#         of their own. The runs after a person's files land provision without
#         --sync, which those files would fail. Its own rig, so no other case's
#         exclude file is reused. ---------------------------------------------
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
eq "$(sync_in "$SKR" "$W" agentR)" ""        "(r) and none of them fails a sync"
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
eq "$(rc_of "$SKR" "$W" agentR)" "0"        "(r) the next run succeeds"
lacks "$(git -C "$W" status --porcelain)" "later-skill" "(r) and hides it"
# A manifest name git would read as a pattern is never written, so it cannot
# hide what a person keeps there. Nor is a name that ends in a newline, which
# would reach the file as the name before it.
printf '{"targets":{"*":"%s","README*":"%s","a b":"%s",".":"%s","..":"%s","README.md\\n":"%s"}}' \
    "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" "$TMP/linked/x" \
    > "$W/.agents/skills/.gc-skill-ownership.json"
eq "$(rc_of "$SKR" "$W" agentR)" "0"        "(r) a run over a manifest of pattern names succeeds"
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
eq "$(PATH="$TMP/nojq:$PATH" rc_of "$SKR" "$W" agentR)" "0" "(r) a run without jq succeeds"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/unread-skill" "(r) and leaves the link it could not read showing"
echo '{"targets":' > "$W/.agents/skills/.gc-skill-ownership.json"
eq "$(rc_of "$SKR" "$W" agentR)" "0"        "(r) a run over a manifest jq cannot read succeeds"
has "$(git -C "$W" status --porcelain)" "?? .agents/skills/unread-skill" "(r) and adds no name either"

# --- (s) a home on a branch not its own fails the start and stays on it. ----
P="$TMP/s"; mkdir -p "$P"; W="$P/agentS"
run "$W" agentS
BR=$(branch_of "$W")
git -C "$W" checkout -q -b person-branch
advance_remote s1.txt
ERR=$(sync_stderr "$W" agentS)
has "$ERR" "exit 1"                          "(s) another branch fails the start"
eq "$(branch_of "$W")" "person-branch"       "(s) and the home stays on it"
has "$(reported "$W" agentS)" "branch person-branch checked out, not its own $BR" "(s) the report names both branches"
has "$(reported "$W" agentS)" "git -C '$W' switch $BR" "(s) and the switch that clears it"

# --- (t) gc merges its hooks into a home's provider settings before pre_start
#         runs, and a rig can track that file, so the merge is a tracked change
#         in every home. It is no edit: the home fast-forwards with it, at the
#         tip and past it. When the tip changes that file, git refuses the
#         fast-forward, which fails the start with git's reason. gc merges
#         into the file again before every start, so a restart meets the same
#         refusal, and the report names the move to make by hand. Its own
#         remote, whose main tracks .claude/settings.json. --------------------
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
eq "$(sync_in "$TR" "$W" agentT)" ""         "(t) at the tip, gc's merge does not fail the start"
t_advance t1.txt t1
eq "$(sync_in "$TR" "$W" agentT)" ""         "(t) nor when the tip moves past it"
eq "$(head_of "$W")" "$(git -C "$TMP/t.git" rev-parse main)" "(t) the home fast-forwards to the new tip"
eq "$(cat "$W/.claude/settings.json")" '{"hooks":"gc","repo":1}' "(t) carrying gc's merge"
BEFORE=$(head_of "$W")
t_advance .claude/settings.json '{"repo":2}'
ERR=$(sync_in "$TR" "$W" agentT)
has "$ERR" "exit 1"                          "(t) a tip that changes the merged file fails the start"
has "$ERR" "a fast-forward to origin/main that git refused" "(t) which the run names"
has "$ERR" ".claude/settings.json"           "(t) with git's reason"
eq "$(head_of "$W"):$(cat "$W/.claude/settings.json")" "$BEFORE:{\"hooks\":\"gc\",\"repo\":1}" \
    "(t) the home and gc's merge stay as they were"
has "$(reported "$W" agentT)" "then make the move by hand with git -C '$W' merge --ff-only origin/HEAD" \
    "(t) the report names the move to make by hand"
git -C "$W" checkout -q -- .claude/settings.json; git -C "$W" merge -q --ff-only origin/HEAD
echo '{"hooks":"gc","repo":2}' > "$W/.claude/settings.json"
eq "$(sync_in "$TR" "$W" agentT)" ""         "(t) after that move, the next start goes through"
git -C "$W" checkout -q --detach
t_advance .claude/settings.json '{"repo":3}'
has "$(sync_in "$TR" "$W" agentT)" "exit 1"  "(t) a detached home's start fails the same way"
has "$(reported "$W" agentT)" "then make the move by hand with git -C '$W' checkout --detach origin/HEAD" \
    "(t) and its report names the detached move"
git -C "$W" checkout -q -- .claude/settings.json; git -C "$W" checkout -q --detach origin/HEAD
echo '{"hooks":"gc","repo":3}' > "$W/.claude/settings.json"
eq "$(sync_in "$TR" "$W" agentT)" ""         "(t) after the detached move, the next start goes through"
eq "$(head_of "$W"):$(branch_of "$W")" "$(git -C "$TMP/t.git" rev-parse main):$BR" \
    "(t) back on its own branch at the tip"

# --- (u) a path gc writes stays no edit when the rig's .gitignore re-includes
#         it, as a repository that tracks skills under .claude/skills/ does, so
#         git status shows gc's link there. A person's file beside it still
#         fails the start. Its own remote. ------------------------------------
US="$TMP/usrc"; git init -q -b main "$US"
mkdir -p "$US/.claude/skills/tracked"; echo skill > "$US/.claude/skills/tracked/SKILL.md"
printf '!/.claude/\n/.claude/*\n!/.claude/skills/\n' > "$US/.gitignore"; echo seed > "$US/README.md"
git -C "$US" add -A; git -C "$US" commit -qm init
git clone -q --bare "$US" "$TMP/u.git"
UR="$TMP/urig"; git clone -q "$TMP/u.git" "$UR"
P="$TMP/u"; mkdir -p "$P"; W="$P/agentU"
eq "$(rc_of "$UR" "$W" agentU)" "0"          "(u) the home is made"
mkdir -p "$TMP/linked/u-skill"; ln -s "$TMP/linked/u-skill" "$W/.claude/skills/gc-linked"
has "$(git -C "$W" status --porcelain)" "?? .claude/skills/gc-linked" "(u) git status shows gc's link"
eq "$(sync_in "$UR" "$W" agentU)" ""         "(u) and it does not fail the start"
echo mine > "$W/notes.txt"
ERR=$(sync_in "$UR" "$W" agentU)
has "$ERR" "files git does not track (notes.txt)" "(u) a person's file beside it does"
lacks "$ERR" "gc-linked"                     "(u) and the report leaves gc's link out"

# --- (v) a git operation a session left stopped partway fails the start, its
#         state kept for a person to finish or abort: a rebase stopped at an
#         edit, a merge stopped before its commit, and a bisect. Once each has
#         ended, the home starts. --------------------------------------------
P="$TMP/v"; mkdir -p "$P"; W="$P/agentV"
run "$W" agentV
BR=$(branch_of "$W")
advance_remote v1.txt
eq "$(sync_stderr "$W" agentV)" ""           "(v) the home starts at the tip"
GIT_SEQUENCE_EDITOR="sed -i.bak 's/^pick/edit/'" git -C "$W" rebase -q -i HEAD~1 >/dev/null 2>&1 || true
ERR=$(sync_stderr "$W" agentV)
has "$ERR" "exit 1"                          "(v) a rebase stopped at an edit fails the start"
has "$ERR" "a git operation stopped partway (rebase-merge)" "(v) which the report names"
present "$(gitpath "$W" rebase-merge)"       "(v) and the rebase stays"
git -C "$W" rebase --abort 2>/dev/null || true
git -C "$W" checkout -q -b side; echo side > "$W/side.txt"; git -C "$W" add side.txt; git -C "$W" commit -qm side
git -C "$W" checkout -q "$BR"
git -C "$W" merge -q --no-ff --no-commit side >/dev/null 2>&1 || true
ERR=$(sync_stderr "$W" agentV)
has "$ERR" "a git operation stopped partway (MERGE_HEAD)" "(v) so does a merge stopped before its commit"
present "$(gitpath "$W" MERGE_HEAD)"         "(v) and the merge stays"
git -C "$W" merge --abort 2>/dev/null || true; git -C "$W" branch -q -D side
git -C "$W" bisect start >/dev/null
ERR=$(sync_stderr "$W" agentV)
has "$ERR" "a git operation stopped partway (BISECT_LOG)" "(v) and so does a bisect"
git -C "$W" bisect reset >/dev/null 2>&1
eq "$(sync_stderr "$W" agentV)" ""           "(v) once each has ended, the home starts"

# --- (w) a repository with no origin has nothing to sync with, so the home stays
#         where it is, and the run says and reports nothing. -------------------
NO="$TMP/noorigin"; git clone -q "$TMP/remote.git" "$NO"
P="$TMP/w"; mkdir -p "$P"; W="$P/agentW"
eq "$(rc_of "$NO" "$W" agentW)" "0"          "(w) the home is made"
git -C "$W" checkout -q --detach
BEFORE=$(head_of "$W")
git -C "$NO" remote remove origin
eq "$(sync_in "$NO" "$W" agentW)" ""         "(w) a sync with no origin says nothing"
eq "$(head_of "$W"):$(calls "$W" agentW report):$(calls "$W" agentW cleared)" "$BEFORE:0:0" \
    "(w) and moves and reports nothing"

# --- (x) with origin/HEAD unset there is no default tip to move to, so the start
#         fails, the home stays where it is, and the report names the fix. Its
#         own rig, since origin/HEAD is shared by all of a repo's worktrees, set
#         so its fetch does not put origin/HEAD back, as a current git otherwise
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
has "$ERR" "exit 1"                          "(x) an unset origin/HEAD fails the start"
has "$(reported "$W" agentX)" "an origin/HEAD that names no commit" "(x) the report says why"
has "$(reported "$W" agentX)" "git -C '$W' remote set-head origin --auto" "(x) and how to set it"
git -C "$NH" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/gone
ERR=$(sync_in "$NH" "$W" agentX)
has "$ERR" "an origin/HEAD that names no commit" "(x) an origin/HEAD naming a branch that is gone fails the same way"

# --- (y) a detached home whose per-target branch another worktree holds moves
#         to the tip detached, since git cannot put it on that branch. --------
P="$TMP/y"; mkdir -p "$P"; W="$P/agentY"
run "$W" agentY
BR=$(branch_of "$W")
git -C "$W" checkout -q --detach
git -C "$RIG" worktree add -q "$P/other" "$BR"
advance_remote y1.txt
ERR=$(sync_stderr "$W" agentY)
eq "$(head_of "$W"):$(branch_of "$W")" "$(tip):DETACHED" "(y) the home moves to the tip, detached"
eq "$ERR" ""                                 "(y) silently"

# --- (z) after a rewrite of the default branch, as a fork's rebase makes, a
#         home on the old history fails its start, and the move its report
#         names lets the next start through. That start records the clear
#         under the report's key, and leaves the home detached at the new tip,
#         its branch still on the old history. Its own remote, since the
#         rewrite force-pushes main. ------------------------------------------
ZS="$TMP/zsrc"; git init -q -b main "$ZS"
echo seed > "$ZS/README.md"; git -C "$ZS" add -A; git -C "$ZS" commit -qm init
echo old > "$ZS/old.txt"; git -C "$ZS" add -A; git -C "$ZS" commit -qm old
git clone -q --bare "$ZS" "$TMP/z.git"
ZR="$TMP/zrig"; git clone -q "$TMP/z.git" "$ZR"
P="$TMP/z"; mkdir -p "$P"; W="$P/agentZ"
eq "$(rc_of "$ZR" "$W" agentZ)" "0"          "(z) the home is made"
BR=$(branch_of "$W"); OLD=$(head_of "$W")
git -C "$ZS" commit -q --amend -m rewritten; git -C "$ZS" push -q -f "$TMP/z.git" main
NEW=$(git -C "$TMP/z.git" rev-parse main)
ERR=$(sync_in "$ZR" "$W" agentZ)
has "$ERR" "exit 1"                          "(z) a home on the old history fails its start"
eq "$(head_of "$W")" "$OLD"                  "(z) and stays where it is"
has "$ERR" "git -C '$W' checkout --detach origin/HEAD" "(z) its report names the move"
git -C "$W" checkout -q --detach origin/HEAD
eq "$(sync_in "$ZR" "$W" agentZ)" ""         "(z) after that move, the next start goes through"
eq "$(head_of "$W"):$(branch_of "$W")" "$NEW:DETACHED" "(z) with the home detached at the new tip"
eq "$(git -C "$ZR" rev-parse "refs/heads/$BR")" "$OLD" "(z) and its branch still on the old history"
eq "$(calls "$W" agentZ report):$(calls "$W" agentZ cleared)" "1:1" \
    "(z) one report, and its clear under the same key"

# --- (aa) a report that does not land still fails the start, and the run's
#          stderr says so, with what it found. --------------------------------
P="$TMP/aa"; mkdir -p "$P"; W="$P/agentAA"
run "$W" agentAA
echo mine > "$W/aa.txt"
ERR=$(FINDING_RC=1 sync_stderr "$W" agentAA)
has "$ERR" "exit 1"                          "(aa) a report that does not land still fails the start"
has "$ERR" "the report on $W did not land"   "(aa) and the run says so"
has "$ERR" "files git does not track (aa.txt)" "(aa) with what it found"

# --- (ab) a HEAD that names no commit, such as a branch whose ref is gone,
#          fails the start. ---------------------------------------------------
P="$TMP/ab"; mkdir -p "$P"; W="$P/agentAB"
run "$W" agentAB
git -C "$W" update-ref -d "refs/heads/$(branch_of "$W")"
ERR=$(sync_stderr "$W" agentAB)
has "$ERR" "exit 1"                          "(ab) a HEAD that names no commit fails the start"
has "$(reported "$W" agentAB)" "a HEAD that names no commit" "(ab) which the report names"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
