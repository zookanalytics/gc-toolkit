#!/usr/bin/env bash
# Tests for worktree-reap.sh against real git repositories in a tempdir and a
# stub gc. No live city, no network, no bd.
#
# Covers the two gates and their order: a closed bead is what clears a worktree,
# and the squash commit on the default branch — not tip-reachability, which a
# squash-merge destroys — is what clears the branch behind it. Covers what holds
# a worktree: an open bead, a modification, an untracked file, a live process
# standing in it, and a ledger that answers with an error or with nothing.
# Covers the one shape that does NOT hold: a pure deletion, whose content is in
# HEAD, and which would otherwise strand every worktree older than a file the
# default branch dropped. Covers the shape rails that keep an agent's session
# worktree and the rig checkout out of the candidate set, --dry-run's promise
# that it reports what a run would take, and the budget yield. Covers nested
# child bead ids (tk-x.1.1), which the grammar must consume whole in both the
# branch and worktree passes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/worktree-reap.sh"
RIG="$TMP/rig"
SESS="$TMP/sessions/agent-a"
BIN="$TMP/bin"
export STUB_OPEN="$TMP/open.json" STUB_BD_RC=""
mkdir -p "$BIN"
cd "$TMP" || exit 1

cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  rig)
    printf '{"rigs":[{"name":"testrig","path":"%s","hq":false}]}\n' "${STUB_RIG_PATH:?}" ;;
  bd)
    [ -n "${STUB_BD_RC:-}" ] && { echo "gc bd: simulated failure" >&2; exit "$STUB_BD_RC"; }
    cat "${STUB_OPEN:?}" ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$BIN/gc"
export PATH="$BIN:$PATH"
export STUB_RIG_PATH="$RIG"

# A private global config: the suite must not write the user's own, and
# init.defaultBranch has to be pinned so the fixture's branch names are known.
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global init.defaultBranch main
run() { bash "$SUT" "$@" 2>&1; }
open_beads() { printf '%s\n' "$1" > "$STUB_OPEN"; }
gitr() { git -C "$RIG" "$@"; }

# A clone of a bare origin, one commit on main, plus the session directory the
# per-bead worktrees hang off.
build_city() {
    rm -rf "$TMP/origin.git" "$RIG" "$TMP/sessions"
    git init -q --bare "$TMP/origin.git"
    git init -q "$TMP/seed" && cd "$TMP/seed" || exit 1
    git config user.email t@t && git config user.name t
    echo base > file.txt && git add . && git commit -qm "base"
    git remote add origin "$TMP/origin.git" && git push -q origin HEAD:main
    cd "$TMP" || exit 1; rm -rf "$TMP/seed"
    git clone -q "$TMP/origin.git" "$RIG"
    gitr config user.email t@t; gitr config user.name t
    mkdir -p "$SESS"
    open_beads '[{"id":"tk-keep1"}]'
    export STUB_BD_RC=""
}

# A per-bead worktree in the shape mol-polecat-work pours, on polecat/<bead>.
mk_wt() { # <bead> [--commit]
    local bead="$1" p="$SESS/worktrees/$1"
    gitr worktree add -q "$p" -b "polecat/$bead" >/dev/null 2>&1
    if [ "${2:-}" = "--commit" ]; then
        echo "$bead" > "$p/$bead.txt"
        git -C "$p" add . && git -C "$p" commit -qm "work on $bead"
    fi
    printf '%s' "$p"
}

# The squash commit a merge leaves on the default branch: the branch's own
# commits never become ancestors, only its bead id in a message.
land_squash() { # <bead>
    git -C "$RIG" commit -q --allow-empty -m "feat: whatever ($1) (#7)"
    gitr push -q origin main
    gitr fetch -q origin
}

exists() { [ -e "$1" ]; }
has_branch() { gitr show-ref --verify --quiet "refs/heads/$1"; }

# --- the closed-bead gate ---------------------------------------------------
build_city
A="$(mk_wt tk-aaa1)"
B="$(mk_wt tk-keep1)"
OUT="$(run)"
if exists "$A"; then bad "closed bead: the worktree is removed"; else ok "closed bead: the worktree is removed"; fi
if exists "$B"; then ok "open bead: the worktree is held"; else bad "open bead: the worktree is held"; fi
if has_branch polecat/tk-keep1; then ok "open bead: its branch is held"; else bad "open bead: its branch is held"; fi
has "$OUT" "held 1 worktrees" "the summary counts what it held"

# A polecat branch of a bead no longer live, whose tip is an ancestor of the
# default branch, is taken by git's own merged test — here freed by the
# worktree pass, then deleted.
if has_branch polecat/tk-aaa1; then bad "merged branch: freed by the worktree pass, then deleted"; else ok "merged branch: freed by the worktree pass, then deleted"; fi

# --- squash-merge: the tip test fails, the bead and the commit carry it ------
build_city
C="$(mk_wt tk-bbb2 --commit)"
gitr fetch -q origin
if gitr merge-base --is-ancestor refs/heads/polecat/tk-bbb2 origin/main 2>/dev/null; then
    bad "fixture: the branch must NOT be reachable from the default branch"
else
    ok "fixture: the branch is unreachable, as a squash-merge leaves it"
fi
run > /dev/null
if exists "$C"; then bad "closed bead, unmerged tip: the worktree still goes"; else ok "closed bead, unmerged tip: the worktree still goes"; fi
if has_branch polecat/tk-bbb2; then ok "no squash commit: the branch is held"; else bad "no squash commit: the branch is held"; fi

land_squash tk-bbb2
run > /dev/null
if has_branch polecat/tk-bbb2; then bad "squash commit on the default branch: the branch goes"; else ok "squash commit on the default branch: the branch goes"; fi

# The bead outranks the commit: an open bead keeps its branch even once a
# commit naming it is on the default branch.
build_city
mk_wt tk-keep1 --commit > /dev/null
land_squash tk-keep1
run > /dev/null
if has_branch polecat/tk-keep1; then ok "open bead: the branch is held despite a commit naming it"; else bad "open bead: the branch is held despite a commit naming it"; fi

# A live bead outranks a merged tip. A polecat/<bead> branch can be an ancestor
# of the default branch — a fast-forward land, or content that reached main
# another way — while its bead is still open. The open-bead guard has to run
# before the merged arm, or an hourly pass erases the local ref a resumable
# work item names. Its dead-bead sibling, merged the same way, proves the guard
# is narrow: it is still taken.
build_city
gitr branch polecat/tk-live1 origin/main >/dev/null 2>&1
gitr branch polecat/tk-gone1 origin/main >/dev/null 2>&1
open_beads '[{"id":"tk-keep1"},{"id":"tk-live1"}]'
run > /dev/null
if has_branch polecat/tk-live1; then ok "merged tip, live bead: the branch is held"; else bad "merged tip, live bead: the branch is held"; fi
if has_branch polecat/tk-gone1; then bad "merged tip, dead bead: the branch is still taken"; else ok "merged tip, dead bead: the branch is still taken"; fi

# A branch that names no bead is outside the owned family and left alone even
# when its tip is an ancestor of the default branch — only polecat/<bead> refs
# are the reaper's to take.
build_city
gitr branch roadmap origin/main >/dev/null 2>&1
run > /dev/null
if has_branch roadmap; then ok "a merged branch that names no bead is left alone"; else bad "a merged branch that names no bead is left alone"; fi

# --- nested child bead ids --------------------------------------------------
# A bead split off another can itself be split, so ids nest: tk-x.1.1. The
# grammar has to consume every .N segment. A grammar that stops at the first
# parses polecat/tk-nest1.1.1 as bead tk-nest1.1 — a shorter, different id — so
# the open-bead guard is keyed on the wrong bead and a merged tip erases a live
# child's local ref. Its dead-bead sibling, merged the same way, is still taken.
build_city
gitr branch polecat/tk-nest1.1.1 origin/main >/dev/null 2>&1
gitr branch polecat/tk-nest2.1.1 origin/main >/dev/null 2>&1
open_beads '[{"id":"tk-keep1"},{"id":"tk-nest1.1.1"}]'
run > /dev/null
if has_branch polecat/tk-nest1.1.1; then ok "nested id, merged tip, live bead: the branch is held"; else bad "nested id, merged tip, live bead: the branch is held"; fi
if has_branch polecat/tk-nest2.1.1; then bad "nested id, merged tip, dead bead: the branch is still taken"; else ok "nested id, merged tip, dead bead: the branch is still taken"; fi

# The worktree pass matches the same grammar with a full-line test, so a
# nested-id worktree is a candidate rather than skipped: its closed-bead sibling
# is reaped and an open one is held.
build_city
NLIVE="$(mk_wt tk-nest3.1.1)"
NDEAD="$(mk_wt tk-nest4.1.1)"
open_beads '[{"id":"tk-keep1"},{"id":"tk-nest3.1.1"}]'
run > /dev/null
if exists "$NLIVE"; then ok "nested id, open bead: the worktree is held"; else bad "nested id, open bead: the worktree is held"; fi
if exists "$NDEAD"; then bad "nested id, closed bead: the worktree is reaped"; else ok "nested id, closed bead: the worktree is reaped"; fi

# --- what holds a worktree --------------------------------------------------
build_city
M="$(mk_wt tk-ccc3)"; echo edited > "$M/file.txt"
U="$(mk_wt tk-ddd4)"; echo new > "$U/untracked.txt"
D="$(mk_wt tk-eee5)"; rm -f "$D/file.txt"
# An ignored file is content that exists nowhere else too. git status omits it
# by default, so a tracked .gitignore plus a local-only ignored file leaves the
# porcelain output empty — the shape the --force removal cannot afford to read
# as "nothing here". The .gitignore is committed so the only untracked content
# is the ignored file itself, or an untracked .gitignore would hold on its own.
G="$(mk_wt tk-iii8)"
printf 'secret.local\n' > "$G/.gitignore"; git -C "$G" add .gitignore; git -C "$G" commit -qm "ignore secret.local"
printf 'token\n' > "$G/secret.local"
run > /dev/null
if exists "$M"; then ok "a modification holds the worktree"; else bad "a modification holds the worktree"; fi
if exists "$U"; then ok "an untracked file holds the worktree"; else bad "an untracked file holds the worktree"; fi
if exists "$G"; then ok "an ignored file holds the worktree"; else bad "an ignored file holds the worktree"; fi
if exists "$D"; then bad "a pure deletion does NOT hold the worktree"; else ok "a pure deletion does NOT hold the worktree"; fi

# The deletion case is the one that matters at scale, so prove the reason it is
# safe rather than only the outcome: the content is still in the commit.
build_city
D2="$(mk_wt tk-fff6)"; rm -f "$D2/file.txt"
if git -C "$D2" cat-file -e HEAD:file.txt 2>/dev/null; then ok "the deleted file is still in HEAD, so removal loses nothing"; else bad "the deleted file is still in HEAD, so removal loses nothing"; fi

# A live process standing in the worktree holds it whatever the bead says.
build_city
L="$(mk_wt tk-ggg7)"
( cd "$L" && exec sleep 30 ) &
SLEEPER=$!
sleep 0.4
run > /dev/null
if exists "$L"; then ok "a live process standing in it holds the worktree"; else bad "a live process standing in it holds the worktree"; fi
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null

# --- the ledger fails closed ------------------------------------------------
build_city
E="$(mk_wt tk-hhh8)"
open_beads '[]'
OUT="$(run)"
if exists "$E"; then ok "an empty open-bead list holds everything"; else bad "an empty open-bead list holds everything"; fi
has "$OUT" "holding everything" "the empty ledger is reported, not silent"

build_city
F="$(mk_wt tk-iii9)"
export STUB_BD_RC=1
OUT="$(run)"
if exists "$F"; then ok "a ledger lookup that errors holds everything"; else bad "a ledger lookup that errors holds everything"; fi
export STUB_BD_RC=""

# --- shape rails ------------------------------------------------------------
# Only <anything>/worktrees/<bead-id> is a candidate. The agent's own session
# worktree, a directory whose name is not a bead id, and a bead-named directory
# whose parent is not `worktrees` all fail the shape test.
build_city
gitr worktree add -q "$TMP/sessions/agent-b" -b gc-agent-b-abc123 >/dev/null 2>&1
gitr worktree add -q "$SESS/worktrees/not-a-bead" -b polecat/spare >/dev/null 2>&1
gitr worktree add -q "$TMP/elsewhere/tk-jjj0" -b polecat/tk-jjj0 >/dev/null 2>&1
run > /dev/null
if exists "$TMP/sessions/agent-b"; then ok "an agent session worktree is never a candidate"; else bad "an agent session worktree is never a candidate"; fi
if exists "$SESS/worktrees/not-a-bead"; then ok "a directory that is not a bead id is never a candidate"; else bad "a directory that is not a bead id is never a candidate"; fi
if exists "$TMP/elsewhere/tk-jjj0"; then ok "a bead id outside a worktrees/ parent is never a candidate"; else bad "a bead id outside a worktrees/ parent is never a candidate"; fi
if exists "$RIG/file.txt"; then ok "the rig checkout is never a candidate"; else bad "the rig checkout is never a candidate"; fi

# A branch that names no bead and is not merged is left alone.
build_city
gitr branch spare-work >/dev/null 2>&1
git -C "$RIG" commit -q --allow-empty -m "ahead"
gitr branch -f spare-work HEAD >/dev/null 2>&1
gitr reset -q --hard origin/main
run > /dev/null
if has_branch spare-work; then ok "an unmerged branch that names no bead is left alone"; else bad "an unmerged branch that names no bead is left alone"; fi

# --- --dry-run --------------------------------------------------------------
# The promise is that the plan matches the run, branches included: a dry run
# reads `git worktree list` unchanged, so a branch its worktree still pins has
# to be carried by hand or the count silently under-reports.
build_city
G="$(mk_wt tk-kkk1 --commit)"
land_squash tk-kkk1
OUT="$(run --dry-run)"
if exists "$G"; then ok "--dry-run removes no worktree"; else bad "--dry-run removes no worktree"; fi
if has_branch polecat/tk-kkk1; then ok "--dry-run deletes no branch"; else bad "--dry-run deletes no branch"; fi
has "$OUT" "DRY RUN" "--dry-run says so"
has "$OUT" "would take 1 worktrees" "--dry-run counts the worktree it would take"
has "$OUT" "and 1 branches" "--dry-run counts the branch its worktree still pins"
OUT="$(run)"
has "$OUT" "took 1 worktrees" "the run takes what the plan named"
has "$OUT" "and 1 branches" "the run takes the branch the plan named"

# --- the budget -------------------------------------------------------------
# The budget is read before the per-worktree gates, not after, so a pass with a
# backlog spends it removing rather than deciding. A slow `du` burns it on the
# first worktree; the second must then be left for the next pass.
build_city
mk_wt tk-lll2 > /dev/null
mk_wt tk-mmm3 > /dev/null
SLOWBIN="$TMP/slowbin"; mkdir -p "$SLOWBIN"
printf '#!/bin/sh\nsleep 4\nexec %s "$@"\n' "$(command -v du)" > "$SLOWBIN/du"
chmod +x "$SLOWBIN/du"
# The budget outlasts start-up but not one slow measurement, so the first
# worktree is taken and the second finds the budget spent.
OUT="$(PATH="$SLOWBIN:$PATH" WORKTREE_REAP_BUDGET=3 run)"
has "$OUT" "yielded in the worktrees pass" "a spent budget yields and says so"
LEFT=0
for W in tk-lll2 tk-mmm3; do exists "$SESS/worktrees/$W" && LEFT=$((LEFT + 1)); done
eq "$LEFT" "1" "a yielded pass takes one worktree and leaves the other"
has "$OUT" "took 1 worktrees" "a yielded pass reports what it actually took"

# --- one rig ----------------------------------------------------------------
build_city
mk_wt tk-nnn4 > /dev/null
OUT="$(run --rig nosuchrig)"
if exists "$SESS/worktrees/tk-nnn4"; then ok "--rig scopes the pass to the named rig"; else bad "--rig scopes the pass to the named rig"; fi
OUT="$(run --bogus)"; eq "$?" "2" "an unknown argument exits 2"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
