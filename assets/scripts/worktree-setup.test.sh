#!/usr/bin/env bash
# Hermetic test for worktree-setup.sh's orphaned-stage self-heal and for its
# --sync of a detached worktree.
#
# Uses a real temp git rig (a clone of a bare remote, so origin/HEAD resolves)
# and drives the real script. No live city, gc, or network. Covers:
#   (a) a legacy un-scoped orphan is NOT adopted — it carries no target
#       attribution, so it is quarantined out of the stage namespace with its
#       contents intact, never merged into the running target;
#   (b) this target's own scoped orphan beside an ALREADY-created worktree is
#       reclaimed (the sync path is where surviving orphans actually sit);
#   (c) a stage dir named for a DIFFERENT target is left untouched — the parent
#       is shared by every agent, so this is the concurrency/cross-target guard;
#   (d) a target-scoped orphan (post-scoping crash) is reclaimed;
#   (e) an orphan never clobbers an existing file (existing wins) and is still
#       fully reclaimed (the losing source is dropped);
#   (f) a normal run leaves no stage dir behind, and the one it creates carries
#       the target's name;
#   (g) two targets share one parent: a legacy orphan is never consumed by the
#       wrong one — unprovable ownership means quarantine, not adoption.
#   (h) a staged directory loses to an existing file at the same path: the
#       existing file wins and the whole losing source subtree is dropped, so
#       the orphan dir is still fully reclaimed rather than stranded.
#   (i) --sync moves a detached, clean worktree that is behind the remote to
#       the default-branch tip, back on its per-target branch, silently;
#   (j) a detached HEAD carrying a commit the remote lacks stays put, and one
#       stderr line names the worktree and the reason;
#   (k) a detached worktree with an uncommitted tracked change stays put, the
#       change intact, with the same one-line warning;
#   (l) a per-target branch holding a commit the tip lacks is never reset: the
#       worktree is detached at the tip instead and the branch keeps its commit;
#   (m) an untracked file the tip would overwrite blocks the move: the worktree
#       stays put, the file intact, the run still exits 0, and the warning
#       carries git's reason.
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

# --- (a) a legacy un-scoped orphan is quarantined, not adopted. ---------------
# It carries no target name, so the run cannot prove it is agentA's; adopting it
# would leak another target's files. The worktree is still created, and the
# orphan is preserved under the .gascity-worktree-orphan.* name for a sweep.
P="$TMP/a"; mkdir -p "$P"
O="$P/$STAGE_PREFIX.LEG001"; mkdir -p "$O/.claude"
echo x > "$O/.claude/settings.json"; echo unique-a > "$O/marker.txt"
run "$P/agentA" agentA
present "$P/agentA/.git"                     "(a) target became a worktree"
absent  "$P/agentA/marker.txt"              "(a) legacy orphan NOT adopted into the worktree"
absent  "$P/agentA/.claude/settings.json"   "(a) nested legacy content NOT adopted"
present "$P/.gascity-worktree-orphan.LEG001/marker.txt" "(a) legacy orphan quarantined, content preserved"
eq "$(cat "$P/.gascity-worktree-orphan.LEG001/marker.txt" 2>/dev/null)" "unique-a" "(a) quarantined content unchanged"
eq "$(stages "$P")" ""                       "(a) no active stage dir left in the parent"

# --- (b) this target's OWN scoped orphan beside an already-created worktree is
#         reclaimed on the sync path (where surviving orphans actually sit). ----
P="$TMP/b"; mkdir -p "$P"
run "$P/agentB" agentB                       # create the worktree first
present "$P/agentB/.git"                     "(b) worktree created on first run"
O="$P/$STAGE_PREFIX.agentB.CRASH2"; mkdir -p "$O"; echo leftover > "$O/leftover.txt"
run "$P/agentB" agentB --sync                  # second run: production sync path + adopt
present "$P/agentB/leftover.txt"             "(b) scoped orphan reclaimed on the --sync path"
absent  "$O"                                "(b) scoped orphan dir removed after adopt"
eq "$(stages "$P")" ""                       "(b) no stage dir left after adopt"

# --- (c) a DIFFERENT target's stage dir is left untouched. -------------------
P="$TMP/c"; mkdir -p "$P"
run "$P/agentC" agentC
FOREIGN="$P/$STAGE_PREFIX.otherguy.LIVE99"; mkdir -p "$FOREIGN"; echo secret > "$FOREIGN/secret.txt"
run "$P/agentC" agentC
present "$FOREIGN/secret.txt"                "(c) foreign target's stage left in place"
absent  "$P/agentC/secret.txt"              "(c) foreign contents not merged into us"

# --- (d) a target-scoped orphan of THIS target is reclaimed. -----------------
P="$TMP/d"; mkdir -p "$P"
O="$P/$STAGE_PREFIX.agentD.CRASH1"; mkdir -p "$O"; echo resume > "$O/resume.txt"
run "$P/agentD" agentD
present "$P/agentD/resume.txt"               "(d) target-scoped orphan reclaimed"
absent  "$O"                                "(d) scoped orphan dir removed"

# --- (e) existing files win during adoption — a scoped orphan never clobbers a
#         live file, and is still fully reclaimed: the losing source is dropped. --
P="$TMP/e"; mkdir -p "$P"
run "$P/agentE" agentE
echo LIVE > "$P/agentE/keep.txt"
O="$P/$STAGE_PREFIX.agentE.CRASH3"; mkdir -p "$O"; echo STALE > "$O/keep.txt"; echo extra > "$O/extra.txt"
run "$P/agentE" agentE
eq "$(cat "$P/agentE/keep.txt")" "LIVE"      "(e) existing file not clobbered by orphan"
present "$P/agentE/extra.txt"                "(e) orphan-only file still adopted"
absent  "$O"                                "(e) orphan dir removed though a staged file lost"
eq "$(stages "$P")" ""                       "(e) no stage dir left when an existing file wins"

# --- (f) a normal run cleans its stage dir; created stage carries the name. ---
# Seed the target with content so staging fires, then confirm nothing leaks. The
# stage dir it creates mid-run is target-scoped (STAGE_SLUG in the name), so a
# crash would leave a reclaimable scoped orphan, not an unattributable legacy one.
P="$TMP/f"; mkdir -p "$P/agentF/.claude"; echo s > "$P/agentF/.claude/settings.json"
run "$P/agentF" agentF
present "$P/agentF/.git"                     "(f) worktree created over non-empty target"
present "$P/agentF/.claude/settings.json"   "(f) pre-existing content restored"
eq "$(stages "$P")" ""                       "(f) staging cleaned up after itself"

# --- (g) two targets share one parent: a legacy orphan is never consumed by the
#         wrong one. Its owner is unprovable, so it is quarantined, not adopted. --
P="$TMP/g"; mkdir -p "$P"
run "$P/agentG1" agentG1                     # first target becomes a worktree
run "$P/agentG2" agentG2                     # a second target shares the parent
O="$P/$STAGE_PREFIX.LEGX"; mkdir -p "$O"; echo owned-by-g2 > "$O/foreign.txt"
run "$P/agentG1" agentG1 --sync                # agentG1 runs with the legacy orphan present
absent  "$P/agentG1/foreign.txt"             "(g) legacy orphan NOT merged into agentG1"
absent  "$P/agentG2/foreign.txt"             "(g) legacy orphan NOT merged into agentG2"
present "$P/.gascity-worktree-orphan.LEGX/foreign.txt" "(g) legacy orphan quarantined, contents preserved"
eq "$(stages "$P")" ""                       "(g) no active stage dir left in the shared parent"

# --- (h) a staged DIRECTORY loses to an existing file at the same path. The
#         existing file wins, and the whole losing source subtree is dropped, so
#         the orphan dir is still fully reclaimed instead of leaking: recursing
#         would mkdir over the file, strand the subtree, and defeat the rmdir. ---
P="$TMP/h"; mkdir -p "$P"
run "$P/agentH" agentH
echo LIVE > "$P/agentH/collision"            # target holds a FILE where the orphan holds a DIR
O="$P/$STAGE_PREFIX.agentH.CRASH4"; mkdir -p "$O/collision"
echo STALE > "$O/collision/nested.txt"; echo solo > "$O/solo.txt"
run "$P/agentH" agentH
eq "$(cat "$P/agentH/collision")" "LIVE"     "(h) existing file not clobbered by a staged dir"
present "$P/agentH/solo.txt"                 "(h) orphan-only entry still adopted past the collision"
absent  "$P/agentH/collision/nested.txt"    "(h) losing staged subtree dropped, not merged under the file"
absent  "$O"                                "(h) orphan dir removed though a staged dir lost to a file"
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

# --- (j) a detached HEAD carrying a commit the remote lacks stays put: moving
#         it would orphan the commit. One stderr line names the worktree and why.
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
has "$ERR" "commits that are not on origin/main" "(j) warning names the reason"
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
