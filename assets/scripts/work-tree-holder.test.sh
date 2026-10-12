#!/usr/bin/env bash
# Hermetic test for work-tree-holder.sh, the tree signal in mol-polecat-work's
# load-context duplicate-dispatch gate.
#
# A session running mol-polecat-work never claims its work bead, so the gate
# cannot see a run in flight from the bead's assignee. The script reads the
# work's tree instead, and answers whether a live session is working it.
#
# What it holds:
#   1. ADOPTABLE — no tree outside this session's directory, this session's own
#      tree, a tree whose directory has no listed session (a crashed run), and
#      a tree whose slot session is on other work or idle. A slot session on
#      other work is the pool-slot reuse and rework-adoption shape that a gate
#      parking on any session in the slot would refuse.
#   2. HELD — a live session in the tree's directory whose claim is this work:
#      the bead itself, a step of a molecule tracking it, a bead on the same
#      branch (the anchor, a sibling rework child), or a bead recording the
#      same tree. A pre-assigned open step and an asleep session count. A tree
#      that is a session's own directory is held by that session.
#   3. FAIL CLOSED — a failed git worktree list, an unreadable session list or
#      bead listing, a tree no session directory accounts for, and a claim
#      whose molecule cannot be traced to its work. Held outranks undecided.
#   4. The finding names the tree by its resolved path and counts its
#      uncommitted paths, so the holder's work can be salvaged.
#
# Runs the real script against real git repositories laid out like pool slots
# ($ROOT/slots/<slot>/worktrees/<bead>) and a fake gc that serves the session
# list and the bead listing. No live city, Dolt, or network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/work-tree-holder.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-work-tree-holder-test.XXXXXX")"
# git lists a worktree by its resolved path, so every fixture path is built on
# a resolved root, a TMPDIR behind a symlink (as macOS's is) included.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1${2:+ ($2)}"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3" "got '$1' want '$2'"; }
has() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "'$2' not in '$1'" ;; esac; }
no()  { case "$1" in *"$2"*) bad "$3" "'$2' unexpectedly in '$1'" ;; *) ok "$3" ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "jq is required for this test" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required for this test" >&2; exit 1; }
[ -x "$SCRIPT" ] || { echo "script not found or not executable: $SCRIPT" >&2; exit 1; }

# The session environment of a live city exports GC_*; the script reads GC_DIR
# and GC_RIG_ROOT, so the suite owns both.
unset "${!GC_@}" 2>/dev/null || true
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR 2>/dev/null || true
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# --- Fake gc. -----------------------------------------------------------------
# `session list` serves $FAKE_SESSIONS and fails when it is unset. `bd list`
# serves the open and in_progress rows of $FAKE_BEADS, or with --id the named
# rows of any status, and fails under FAKE_LIST_FAIL / FAKE_ID_FAIL. Every call
# is logged, so a case can assert what the script read.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GC_LOG"
case "$1 $2" in
  "session list")
    [ -n "${FAKE_SESSIONS:-}" ] || exit 1
    printf '%s' "$FAKE_SESSIONS" ;;
  "bd list")
    ids=""; prev=""
    for a in "$@"; do [ "$prev" = "--id" ] && ids="$a"; prev="$a"; done
    if [ -n "$ids" ]; then
      [ -z "${FAKE_ID_FAIL:-}" ] || exit 1
      printf '%s' "$FAKE_BEADS" | jq -c --arg ids "$ids" '($ids | split(",")) as $w | [.[] | select(.id as $i | any($w[]; . == $i))]'
    else
      [ -z "${FAKE_LIST_FAIL:-}" ] || exit 1
      printf '%s' "$FAKE_BEADS" | jq -c --arg hide "${FAKE_LIST_HIDE:-}" '($hide | split(",")) as $h | [.[] | select(.status == "open" or .status == "in_progress") | select(.id as $i | any($h[]; . == $i) | not)]'
    fi ;;
  *) exit 1 ;;
esac
GC
chmod +x "$TMP/bin/gc"
export PATH="$TMP/bin:$PATH"

# --- Fixture builders. --------------------------------------------------------
# A pool session: alias null, its address in agent_name, its slot as work_dir.
sess() { # <id> <slot-dir> [state]
  jq -nc --arg id "$1" --arg d "$2" --arg st "${3:-active}" '{id: $id, session_name: ("pool__polecat-" + $id), name: ("pool__polecat-" + $id), agent_name: ("rig/rig." + ($d | split("/") | last)), alias: null, state: $st, work_dir: $d}'
}
sessions() { printf '%s\n' "$@" | jq -sc '{sessions: .}'; }
# Bead rows in the shape `bd list --json` prints: metadata an object, edges as
# {issue_id, depends_on_id, type}.
work() { # <id> <status> [branch] [work_dir] [assignee]
  jq -nc --arg id "$1" --arg st "$2" --arg b "${3:-}" --arg wd "${4:-}" --arg a "${5:-}" '{id: $id, status: $st, assignee: (if $a == "" then null else $a end), metadata: ({} + (if $b == "" then {} else {branch: $b} end) + (if $wd == "" then {} else {work_dir: $wd} end)), dependencies: []}'
}
step() { # <id> <root> <assignee> [status]
  jq -nc --arg id "$1" --arg r "$2" --arg a "$3" --arg st "${4:-in_progress}" '{id: $id, status: $st, assignee: $a, metadata: {"gc.root_bead_id": $r, "gc.step_ref": "mol-polecat-work.implement"}, dependencies: []}'
}
root() { # <id> <convoy>
  jq -nc --arg id "$1" --arg c "$2" '{id: $id, status: "in_progress", assignee: null, metadata: {"gc.kind": "workflow", "gc.input_convoy_id": $c, "gc.var.convoy_id": $c}, dependencies: [{issue_id: $id, depends_on_id: ($id + "-finalize"), type: "tracks"}]}'
}
convoy() { # <id> <member> [status]
  jq -nc --arg id "$1" --arg m "$2" --arg st "${3:-open}" '{id: $id, issue_type: "convoy", status: $st, assignee: null, metadata: {}, dependencies: [{issue_id: $id, depends_on_id: $m, type: "tracks"}]}'
}
beads() { printf '%s\n' "$@" | jq -sc '.'; }
# A molecule run by <session> over <work>: its claimed step, root and convoy.
molecule() { # <tag> <session-id> <work-id> [step-status]
  step "st-$1" "root-$1" "$2" "${4:-in_progress}"
  root "root-$1" "cv-$1"
  convoy "cv-$1" "$3"
}

# fresh — a new repository with this session's slot ($ME) and a peer slot
# ($PEER), both linked worktrees of the rig checkout ($REPO), as pool slots are.
fresh() {
  CASE=$((${CASE:-0} + 1))
  R="$TMP/c$CASE"
  REPO="$R/repo"; ME="$R/slots/me"; PEER="$R/slots/peer"
  git init -q -b main "$REPO"
  git -C "$REPO" -c commit.gpgsign=false commit -q --allow-empty -m init
  git -C "$REPO" worktree add -q --detach "$ME"
  git -C "$REPO" worktree add -q --detach "$PEER"
  unset FAKE_SESSIONS FAKE_LIST_FAIL FAKE_ID_FAIL FAKE_LIST_HIDE
  FAKE_BEADS='[]'
  : > "$R/gc.log"
}
tree_at() { git -C "$REPO" worktree add -q --detach "$1"; }        # <path>
branch_at() { git -C "$REPO" worktree add -q -b "$2" "$1"; }       # <path> <branch>

# run [args...] — the script as the gate calls it, from this session's slot.
# Prints "<rc>|<stdout>"; $R/gc.log holds the gc calls.
run() {
  local rc=0 out
  out=$(cd "$ME" && GC_DIR="$ME" GC_RIG_ROOT="${RIG:-$REPO}" FAKE_GC_LOG="$R/gc.log" \
        FAKE_SESSIONS="${FAKE_SESSIONS:-}" FAKE_BEADS="$FAKE_BEADS" \
        FAKE_LIST_FAIL="${FAKE_LIST_FAIL:-}" FAKE_ID_FAIL="${FAKE_ID_FAIL:-}" FAKE_LIST_HIDE="${FAKE_LIST_HIDE:-}" \
        "$SCRIPT" "$@") || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# --- 1. Adoptable. ------------------------------------------------------------

fresh
out=$(run --bead tk-w --work-dir "" --branch "")
eq "$out" "0|" "fresh work (nothing recorded, no polecat/<bead> anywhere): adoptable, says nothing"
eq "$(cat "$R/gc.log")" "" "fresh work: no session list or bead listing is read"

fresh
branch_at "$ME/worktrees/tk-w" polecat/tk-w
echo wip > "$ME/worktrees/tk-w/wip.txt"
eq "$(run --bead tk-w --work-dir "$ME/worktrees/tk-w" --branch polecat/tk-w)" "0|" \
   "this session's own tree, uncommitted work and all: a resume, adoptable"
eq "$(cat "$R/gc.log")" "" "own tree: no session list is read"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "0" "a gone holder (no listed session in the tree's slot): adoptable"
has "$out" "no listed session works in $PEER" "gone holder: the finding names the empty slot"

# Pool-slot reuse: the per-bead tree outlives its run, and the session now in
# the slot is on other work.
fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule o lx-peer tk-other)" "$(work tk-other open polecat/tk-other "$PEER/worktrees/tk-other")" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "0" "slot reuse: the slot's session is working other work, so the tree is adoptable"
has "$out" "working other work (tk-other)" "slot reuse: the finding names the other work"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "0" "the slot's session holds no claim (idle between beads): adoptable"
has "$out" "holds no claim" "idle slot session: the finding says so"

# Rework adoption: a rework child arrives with no work_dir while the anchor's
# surviving tree still has the branch checked out.
fresh
branch_at "$PEER/worktrees/tk-a" polecat/tk-a
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule o lx-peer tk-other)" "$(work tk-other open polecat/tk-other "$PEER/worktrees/tk-other")" "$(work tk-a open polecat/tk-a "$PEER/worktrees/tk-a")")
out=$(run --bead tk-c --work-dir "" --branch polecat/tk-a)
eq "${out%%|*}" "0" "rework child whose branch the anchor's old tree holds, slot session on other work: adoptable"
has "$out" "worktree $PEER/worktrees/tk-a" "rework adoption: the finding names the anchor's tree"

fresh
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)" "0|" \
   "a recorded work_dir with no directory behind it: nothing to adopt from anyone"

# --- 2. Held by a live session working this work. ------------------------------

fresh
tree_at "$PEER/worktrees/tk-w"
echo a > "$PEER/worktrees/tk-w/a.txt"; echo b > "$PEER/worktrees/tk-w/b.txt"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "1" "live peer running a molecule over this bead in its recorded work_dir: held"
has "$out" "worktree $PEER/worktrees/tk-w (uncommitted paths: 2)" "held: names the resolved tree and counts its uncommitted paths"
has "$out" "pool__polecat-lx-peer" "held: names the holder session"
has "$out" "working tk-w" "held: names the work it is on"

# The bead under this session's own claim, its branch checked out in the peer's
# tree, and no work_dir recorded.
fresh
branch_at "$PEER/worktrees/tk-w" polecat/tk-w
echo wip > "$PEER/worktrees/tk-w/wip.txt"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w in_progress polecat/tk-w "" lx-me)")
out=$(run --bead tk-w --work-dir "" --branch polecat/tk-w)
eq "${out%%|*}" "1" "live peer has the recorded branch checked out and is working this bead: held"
has "$out" "(uncommitted paths: 1)" "branch tree: counts the peer's uncommitted path"

# workspace-setup cuts polecat/<bead> before it records metadata.branch.
fresh
branch_at "$PEER/worktrees/tk-w" polecat/tk-w
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w open)")
out=$(run --bead tk-w --work-dir "" --branch "")
eq "${out%%|*}" "1" "no branch recorded, a live peer has polecat/<bead> checked out for it: held"

fresh
branch_at "$PEER/worktrees/tk-c1" polecat/tk-a
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-c1)" "$(work tk-c1 open polecat/tk-a "$PEER/worktrees/tk-c1")" "$(work tk-a open polecat/tk-a)")
out=$(run --bead tk-c2 --work-dir "" --branch polecat/tk-a)
eq "${out%%|*}" "1" "a sibling rework child on the same branch is live in the tree: held"
has "$out" "working tk-c1 on polecat/tk-a" "sibling: names the sibling and the shared branch"

# A direct-routed holder claims the work bead itself: no molecule root.
fresh
branch_at "$PEER/worktrees/tk-a" polecat/tk-a
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(work tk-a in_progress polecat/tk-a "$PEER/worktrees/tk-a" lx-peer)")
out=$(run --bead tk-c --work-dir "" --branch polecat/tk-a)
eq "${out%%|*}" "1" "the anchor itself is live in the tree under a direct claim: held"
has "$out" "working tk-a on polecat/tk-a" "anchor: names it"

# The holder's work records this tree as its work_dir under another branch,
# through a symlinked path: -ef, not string equality, decides.
fresh
tree_at "$PEER/worktrees/tk-w"
ln -s "$PEER/worktrees/tk-w" "$R/link-to-tree"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-x)" "$(work tk-x open polecat/tk-x "$R/link-to-tree")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "1" "the holder's work records this tree (by a symlinked path) as its work_dir: held"
has "$out" "working tk-x in this worktree" "same tree: names the bead that records it"

# A step assigned but not yet claimed is still the holder's.
fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w open)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w | cut -d'|' -f1)" "1" \
   "the slot session's next step is assigned and open (between steps): held"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER" asleep)")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w | cut -d'|' -f1)" "1" \
   "an asleep session with a claim on this work: listed, so not provably gone, held"

# A claim may carry any of a session's names: here the slot's agent address.
fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p rig/rig.peer tk-w)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w | cut -d'|' -f1)" "1" \
   "a claim under the holder's agent address (agent_name, not id): held"

fresh
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
out=$(run --bead tk-w --work-dir "$PEER" --branch polecat/tk-w)
eq "${out%%|*}" "1" "a recorded work_dir that is a live session's own directory: held by that session"
has "$out" "whose directory it is" "session directory: the finding says why"
no "$(cat "$R/gc.log")" "bd list" "session directory: no claim lookup is needed"

# The convoy is not in the open listing (closed early); the script fetches it.
fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(step st-p root-p lx-peer)" "$(root root-p cv-p)" "$(convoy cv-p tk-w closed)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w | cut -d'|' -f1)" "1" \
   "a convoy outside the open listing is fetched by id and traced: held"
has "$(cat "$R/gc.log")" "--id cv-p" "the missing convoy is fetched by id"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
FAKE_LIST_HIDE=root-p
eq "$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w | cut -d'|' -f1)" "1" \
   "a molecule root missing from the listing is fetched by id and traced: held"

# --- 3. Fail closed. ----------------------------------------------------------

fresh
tree_at "$PEER/worktrees/tk-w"
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "2" "an unreadable session list: undecided"
has "$out" "worktree $PEER/worktrees/tk-w (uncommitted paths: 0) could not be cleared: the session list could not be read" \
    "unreadable session list: names the tree and the reason"

fresh
branch_at "$R/elsewhere/tk-w" polecat/tk-w
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
out=$(run --bead tk-w --work-dir "" --branch polecat/tk-w)
eq "${out%%|*}" "2" "a tree no session directory accounts for: undecided"
has "$out" "no session directory accounts for it" "unattributable: the finding says so"

fresh
mkdir -p "$R/not-a-repo"
out=$(RIG="$R/not-a-repo" run --bead tk-w --work-dir "" --branch "")
eq "${out%%|*}" "2" "git cannot list the worktrees: undecided, even for fresh work"
has "$out" "git could not list the worktrees" "git failure: the finding says so"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_LIST_FAIL=1
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "2" "the bead listing cannot be read while a session sits in the slot: undecided"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)")
FAKE_LIST_HIDE=root-p; FAKE_ID_FAIL=1
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "2" "the holder's molecule root cannot be fetched: undecided"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(step st-p root-p lx-peer)" "$(jq -nc '{id: "root-p", status: "in_progress", metadata: {"gc.kind": "workflow"}, dependencies: []}')")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "2" "the holder's molecule names no input convoy: undecided"
has "$out" "molecule root-p names no input convoy" "untraced claim: the finding says which and why"

fresh
tree_at "$PEER/worktrees/tk-w"
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-gone)")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "2" "the holder's work bead cannot be read: undecided"
has "$out" "work tk-gone could not be read" "unreadable work: the finding names it"

# Held outranks undecided: the recorded tree is live, the branch tree is
# unattributable.
fresh
tree_at "$PEER/worktrees/tk-w"
branch_at "$R/elsewhere/tk-w" polecat/tk-w
FAKE_SESSIONS=$(sessions "$(sess lx-me "$ME")" "$(sess lx-peer "$PEER")")
FAKE_BEADS=$(beads "$(molecule p lx-peer tk-w)" "$(work tk-w open polecat/tk-w "$PEER/worktrees/tk-w")")
out=$(run --bead tk-w --work-dir "$PEER/worktrees/tk-w" --branch polecat/tk-w)
eq "${out%%|*}" "1" "one tree held, the other undecided: held"
has "$out" "no session directory accounts for it" "both findings are reported"

# --- 4. Usage. ----------------------------------------------------------------

fresh
eq "$(run --work-dir "" --branch "" | cut -d'|' -f1)" "64" "no --bead: usage"
eq "$(run --bead tk-w --work-dir | cut -d'|' -f1)" "64" "an option with no value: usage"
eq "$(run --bead tk-w --branch --work-dir x | cut -d'|' -f1)" "64" "an option followed by an option: usage"
eq "$(run --bead tk-w --bogus | cut -d'|' -f1)" "64" "an unknown argument: usage"

# --- Summary. -----------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
