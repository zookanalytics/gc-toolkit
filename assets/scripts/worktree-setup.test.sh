#!/usr/bin/env bash
# Hermetic test for worktree-setup.sh's orphaned-stage self-heal.
#
# Uses a real temp git rig (a clone of a bare remote, so origin/HEAD resolves)
# and drives the real script. No live city, gc, or network. Covers:
#   (a) a legacy un-scoped orphan beside a not-yet-worktree target is reclaimed;
#   (b) an orphan beside an ALREADY-created worktree is reclaimed (the sync path
#       is where surviving orphans actually sit, since the target got created on
#       a later run);
#   (c) a stage dir named for a DIFFERENT target is left untouched — the parent
#       is shared by every agent, so this is the concurrency/cross-target guard;
#   (d) a target-scoped orphan (post-scoping crash) is reclaimed;
#   (e) an orphan never clobbers an existing file (existing wins);
#   (f) a normal run leaves no stage dir behind, and the one it creates carries
#       the target's name.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/worktree-setup.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

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
stages() { ls -1a "$1" 2>/dev/null | grep -F "$STAGE_PREFIX" || true; }

# --- (a) legacy orphan beside a fresh (not-yet-worktree) target. --------------
P="$TMP/a"; mkdir -p "$P"
O="$P/$STAGE_PREFIX.LEG001"; mkdir -p "$O/.claude"
echo x > "$O/.claude/settings.json"; echo unique-a > "$O/marker.txt"
run "$P/agentA" agentA
present "$P/agentA/.git"                    "(a) target became a worktree"
present "$P/agentA/marker.txt"              "(a) legacy orphan file reclaimed"
eq "$(cat "$P/agentA/marker.txt" 2>/dev/null)" "unique-a" "(a) reclaimed content intact"
present "$P/agentA/.claude/settings.json"   "(a) nested orphan dir reclaimed"
eq "$(stages "$P")" ""                      "(a) no stage dir left in the parent"

# --- (b) orphan beside an ALREADY-created worktree (the sync path). -----------
P="$TMP/b"; mkdir -p "$P"
run "$P/agentB" agentB                       # create the worktree first
present "$P/agentB/.git"                     "(b) worktree created on first run"
O="$P/$STAGE_PREFIX.LEG002"; mkdir -p "$O"; echo leftover > "$O/leftover.txt"
run "$P/agentB" agentB --sync                  # second run: production sync path + adopt
present "$P/agentB/leftover.txt"             "(b) orphan reclaimed on the --sync path"
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

# --- (e) existing files win — an orphan never clobbers a live file, and is
#         still fully reclaimed: the losing source is dropped, not left behind. --
P="$TMP/e"; mkdir -p "$P"
run "$P/agentE" agentE
echo LIVE > "$P/agentE/keep.txt"
O="$P/$STAGE_PREFIX.LEG003"; mkdir -p "$O"; echo STALE > "$O/keep.txt"; echo extra > "$O/extra.txt"
run "$P/agentE" agentE
eq "$(cat "$P/agentE/keep.txt")" "LIVE"      "(e) existing file not clobbered by orphan"
present "$P/agentE/extra.txt"                "(e) orphan-only file still adopted"
absent  "$O"                                "(e) orphan dir removed though a staged file lost"
eq "$(stages "$P")" ""                       "(e) no stage dir left when an existing file wins"

# --- (f) a normal run cleans its stage dir; created stage carries the name. ---
# Seed the target with content so staging fires, then confirm nothing leaks and
# any stage dir observed mid-run would be target-scoped (asserted via the guard
# in (c): a bare-named leftover would be treated as legacy and swept).
P="$TMP/f"; mkdir -p "$P/agentF/.claude"; echo s > "$P/agentF/.claude/settings.json"
run "$P/agentF" agentF
present "$P/agentF/.git"                     "(f) worktree created over non-empty target"
present "$P/agentF/.claude/settings.json"   "(f) pre-existing content restored"
eq "$(stages "$P")" ""                       "(f) staging cleaned up after itself"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
