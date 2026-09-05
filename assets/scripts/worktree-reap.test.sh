#!/usr/bin/env bash
# Tests for worktree-reap.sh against a synthetic city in a tempdir. Real git
# and a real filesystem, because every property here is a question about which
# checkouts survive on disk; only `gc` and `gh` are stubbed, over fixture files
# this suite writes.
#
# Covers the disposability chain (a closed bead past the horizon, clean, with
# no open sibling and no open PR) and each condition that holds a tree back:
# an open bead on the path, an open bead on the BRANCH while the path's own
# bead is closed, an open pull request, a dirty tree, a locked worktree, the
# main worktree, a registered child, an agent home, and a live process's cwd
# or a subdirectory of one. Covers the archive tag, which must make a detached
# tip survive removal when no branch reaches it. Covers the reporting claims:
# a removal that returns success and leaves the directory is counted as a
# failure and named, and a repo whose PR listing fails is held rather than
# reaped. Covers --dry-run, the budget yield, and the rails.
#
# Every keep is asserted alongside a take in the same run. A pass that
# filtered everything and a pass that filtered nothing print the same summary,
# so an assertion that only names survivors proves nothing about the filter.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

SUT="$HERE/worktree-reap.sh"
CITY="$TMP/city"
REPO="$CITY/rigs/demo"
BIN="$TMP/bin"; mkdir -p "$BIN"
NOW="$(date +%s)"
HOUR=3600

export GC_CITY_PATH="$CITY"
export WORKTREE_REAP_REPOS="$REPO"
export WORKTREE_REAP_CLOSED_AFTER=$((24 * HOUR))
export STUB_BEADS="$TMP/beads.json"
export STUB_AGENTS="$TMP/agents.json"
export STUB_SESSIONS="$TMP/sessions.json"
export STUB_STATUSES="$TMP/statuses.json"
export STUB_PR_BRANCHES="$TMP/pr-branches.txt"
export STUB_PR_RC=0
export PATH="$BIN:$PATH"

# --- stubs -----------------------------------------------------------------
# `gc bd list --json` emits metadata as an OBJECT, which is what the running
# binary does; a stub that emitted a string would let a parse the tool never
# needs pass for a parse it does.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
case "${1:-} ${2:-}" in
  "agent list")   cat "${STUB_AGENTS:?}" ;;
  "session list") cat "${STUB_SESSIONS:?}" ;;
  "rig list")     echo '{"rigs":[]}' ;;
  "bd statuses")  cat "${STUB_STATUSES:?}" ;;
  "bd list")
    want=""
    while [ $# -gt 0 ]; do
      case "$1" in --status) want="$2"; shift ;; --status=*) want="${1#--status=}" ;; esac
      shift
    done
    # Bind the row before testing it: the argument to `contains` is evaluated
    # against the string being searched, so a bare `.status` in there reads the
    # status field of $want.
    jq -c --arg want ",$want," '[ .[] | . as $b | select($want | contains("," + $b.status + ",")) ]' "${STUB_BEADS:?}"
    ;;
  *) exit 0 ;;
esac
STUB
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
[ "${STUB_PR_RC:-0}" = "0" ] || { echo "gh: simulated failure" >&2; exit "${STUB_PR_RC}"; }
cat "${STUB_PR_BRANCHES:?}"
STUB
chmod +x "$BIN/gc" "$BIN/gh"
echo '{"agents":[{"work_dir":".gc/worktrees/{{.Rig}}/polecats/{{.AgentBase}}"}]}' > "$STUB_AGENTS"
echo '{"sessions":[]}' > "$STUB_SESSIONS"
: > "$STUB_PR_BRANCHES"

# The bead-status contract the reaper reads with `gc bd statuses`. It protects
# every status whose category is not `done`, so this fixture is what tells it
# deferred, pinned and hooked are live and closed is not. new_repo restores it;
# the two tests that vary it write their own.
statuses_default() {
    cat > "$STUB_STATUSES" <<'JSON'
{"built_in_statuses":[
  {"name":"open","category":"active"},
  {"name":"in_progress","category":"wip"},
  {"name":"blocked","category":"wip"},
  {"name":"deferred","category":"frozen"},
  {"name":"closed","category":"done"},
  {"name":"pinned","category":"frozen"},
  {"name":"hooked","category":"wip"}
]}
JSON
}
statuses_default

# --- fixture ---------------------------------------------------------------
# One repo with an origin, so the PR probe has a slug to ask about.
new_repo() {
    rm -rf "$CITY"; mkdir -p "$REPO"
    git init -q -b main "$REPO"
    git -C "$REPO" config user.email t@example.com
    git -C "$REPO" config user.name Test
    git -C "$REPO" config commit.gpgsign false
    git -C "$REPO" remote add origin https://github.com/zook/demo.git
    echo seed > "$REPO/seed"; git -C "$REPO" add seed
    git -C "$REPO" commit -qm seed
    echo '[]' > "$STUB_BEADS"
    : > "$STUB_PR_BRANCHES"
    statuses_default
}

# A worktree with one commit of its own, so its tip is not the base tip.
mk_wt() { # <path> <branch|--detach>
    local path="$1" ref="$2"
    if [ "$ref" = "--detach" ]; then
        git -C "$REPO" worktree add -q --detach "$path" main
    else
        git -C "$REPO" worktree add -q -b "$ref" "$path" main
    fi
    echo "$path" > "$path/own"
    git -C "$path" add own
    git -C "$path" commit -qm "work in $path"
}

# A bead row as `bd list --json` returns one.
bead() { # <id> <status> <hours-since-close> <work_dir> <branch>
    local id="$1" st="$2" hrs="$3" wd="$4" br="$5"
    local at; at="$(date -u -d "@$((NOW - hrs * HOUR))" +%Y-%m-%dT%H:%M:%SZ)"
    jq -c --arg id "$id" --arg st "$st" --arg at "$at" --arg wd "$wd" --arg br "$br" \
        '. += [{id: $id, status: $st, closed_at: $at, updated_at: $at,
                metadata: ({} | if $wd == "" then . else .work_dir = $wd end
                              | if $br == "" then . else .branch  = $br end)}]' \
        "$STUB_BEADS" > "$STUB_BEADS.n" && mv "$STUB_BEADS.n" "$STUB_BEADS"
}

run() { bash "$SUT" "$@" 2>&1; }
exists() { [ -e "$1" ]; }
registered() { grep -qxF "worktree $1" < <(git -C "$REPO" worktree list --porcelain); }

# --- the chain, and a control for every gate -------------------------------
# Each gate gets a tree that trips it and, in the SAME run, the doomed tree
# that trips none. A filter that rejected everything would keep the survivors
# too, so the take is what proves the filter discriminates.
new_repo
mk_wt "$REPO/wt/doomed"    polecat/doomed
mk_wt "$REPO/wt/young"     polecat/young
mk_wt "$REPO/wt/open-path" polecat/open-path
mk_wt "$REPO/wt/open-peer" polecat/open-peer
mk_wt "$REPO/wt/pr-open"   polecat/pr-open
mk_wt "$REPO/wt/dirty"     polecat/dirty
mk_wt "$REPO/wt/no-bead"   polecat/no-bead
bead b-doomed    closed 100 "$REPO/wt/doomed"    polecat/doomed
bead b-young     closed   1 "$REPO/wt/young"     polecat/young
bead b-open      open    "" "$REPO/wt/open-path" polecat/open-path
bead b-openclose closed 100 "$REPO/wt/open-path" polecat/open-path
bead b-peerdone  closed 100 "$REPO/wt/open-peer" polecat/open-peer
bead b-peerlive  open    "" ""                   polecat/open-peer
bead b-pr        closed 100 "$REPO/wt/pr-open"   polecat/pr-open
bead b-dirty     closed 100 "$REPO/wt/dirty"     polecat/dirty
echo "polecat/pr-open" > "$STUB_PR_BRANCHES"
echo scribble > "$REPO/wt/dirty/scribble"
OUT="$(run)"

if exists "$REPO/wt/doomed"; then bad "the whole chain met: the worktree is removed"; else ok "the whole chain met: the worktree is removed"; fi
if registered "$REPO/wt/doomed"; then bad "the removed worktree is deregistered"; else ok "the removed worktree is deregistered"; fi
if exists "$REPO/wt/young"; then ok "closed inside the horizon: kept"; else bad "closed inside the horizon: kept"; fi
if exists "$REPO/wt/open-path"; then ok "an open bead on the path holds it, though another bead on it closed"; else bad "an open bead on the path holds it, though another bead on it closed"; fi
if exists "$REPO/wt/open-peer"; then ok "an open bead on the BRANCH holds it, though the path's own bead closed"; else bad "an open bead on the BRANCH holds it, though the path's own bead closed"; fi
if exists "$REPO/wt/pr-open"; then ok "an open pull request on the branch holds it"; else bad "an open pull request on the branch holds it"; fi
if exists "$REPO/wt/dirty"; then ok "an uncommitted file holds it"; else bad "an uncommitted file holds it"; fi
if exists "$REPO/wt/no-bead"; then ok "a worktree no bead names is not the reaper's to take"; else bad "a worktree no bead names is not the reaper's to take"; fi
if exists "$REPO"; then ok "the main worktree is never a candidate"; else bad "the main worktree is never a candidate"; fi
has "$OUT" "removed 1 of" "the summary counts the one removal"

# The horizon boundary is the horizon itself: an hour either side decides it.
new_repo
mk_wt "$REPO/wt/inside"  polecat/inside
mk_wt "$REPO/wt/outside" polecat/outside
bead b-in  closed 23 "$REPO/wt/inside"  polecat/inside
bead b-out closed 25 "$REPO/wt/outside" polecat/outside
run > /dev/null
if exists "$REPO/wt/inside"; then ok "an hour inside the horizon survives"; else bad "an hour inside the horizon survives"; fi
if exists "$REPO/wt/outside"; then bad "an hour past the horizon is reaped"; else ok "an hour past the horizon is reaped"; fi

# Several beads name one directory; the NEWEST close is what the horizon
# measures, so a rework child closing today holds its predecessor's tree.
new_repo
mk_wt "$REPO/wt/shared" polecat/shared
bead b-old closed 100 "$REPO/wt/shared" polecat/shared
bead b-new closed   1 "$REPO/wt/shared" polecat/shared
run > /dev/null
if exists "$REPO/wt/shared"; then ok "the newest close sets the age: a recent sibling holds the tree"; else bad "the newest close sets the age: a recent sibling holds the tree"; fi

# Several closed beads on one path can record DIFFERENT branches, and the one
# an open bead is still working is not always the newest. Every branch any of
# them recorded is asked about, not just the branch of the latest close.
new_repo
mk_wt "$REPO/wt/two-branch" polecat/newer
mk_wt "$REPO/wt/one-branch" polecat/only
bead b-older  closed 100 "$REPO/wt/two-branch" polecat/older
bead b-newer  closed  30 "$REPO/wt/two-branch" polecat/newer
bead b-live   open    "" ""                    polecat/older
bead b-single closed 100 "$REPO/wt/one-branch" polecat/only
run > /dev/null
if exists "$REPO/wt/two-branch"; then ok "an open bead on an older bead's branch holds the path"; else bad "an open bead on an older bead's branch holds the path"; fi
if exists "$REPO/wt/one-branch"; then bad "a path whose every recorded branch is quiet is taken"; else ok "a path whose every recorded branch is quiet is taken"; fi

# --- a non-closed status is live, whatever its name ------------------------
# The disposability line is the status contract's one done state, `closed`.
# Every other status holds a checkout as firmly as `open` does, so a bead in it
# keeps its worktree even when a closed bead names the same path. deferred,
# pinned and hooked are the built-in non-open live states; a fourth tree is
# held by a live bead on its BRANCH while the path's own bead is closed. The
# closed-only neighbour is the take that proves the filter still discriminates.
new_repo
mk_wt "$REPO/wt/live-deferred" polecat/live-deferred
mk_wt "$REPO/wt/live-pinned"   polecat/live-pinned
mk_wt "$REPO/wt/live-hooked"   polecat/live-hooked
mk_wt "$REPO/wt/live-branch"   polecat/live-branch
mk_wt "$REPO/wt/closed-only"   polecat/closed-only
bead b-def-live  deferred  "" "$REPO/wt/live-deferred" polecat/live-deferred
bead b-def-done  closed   100 "$REPO/wt/live-deferred" polecat/live-deferred
bead b-pin-live  pinned    "" "$REPO/wt/live-pinned"   polecat/live-pinned
bead b-pin-done  closed   100 "$REPO/wt/live-pinned"   polecat/live-pinned
bead b-hook-live hooked    "" "$REPO/wt/live-hooked"   polecat/live-hooked
bead b-hook-done closed   100 "$REPO/wt/live-hooked"   polecat/live-hooked
bead b-brn-done  closed   100 "$REPO/wt/live-branch"   polecat/live-branch
bead b-brn-live  deferred  "" ""                       polecat/live-branch
bead b-co-done   closed   100 "$REPO/wt/closed-only"   polecat/closed-only
OUT="$(run)"
if exists "$REPO/wt/live-deferred"; then ok "a deferred bead on the path holds it, though a closed bead names it too"; else bad "a deferred bead on the path holds it, though a closed bead names it too"; fi
if exists "$REPO/wt/live-pinned"; then ok "a pinned bead on the path holds it"; else bad "a pinned bead on the path holds it"; fi
if exists "$REPO/wt/live-hooked"; then ok "a hooked bead on the path holds it"; else bad "a hooked bead on the path holds it"; fi
if exists "$REPO/wt/live-branch"; then ok "a deferred bead on the BRANCH holds it, though the path's own bead closed"; else bad "a deferred bead on the BRANCH holds it, though the path's own bead closed"; fi
if exists "$REPO/wt/closed-only"; then bad "the closed-only neighbour is still taken"; else ok "the closed-only neighbour is still taken"; fi
has "$OUT" "removed 1 of" "only the closed-only tree is reaped"

# The live set is the contract's, not a list in the script: a status the reaper
# was never written to know still protects its checkout. The contract reports a
# custom frozen status; a bead in it, on a path a closed bead also names, is
# held, and its closed-only neighbour is taken in the same run.
new_repo
mk_wt "$REPO/wt/custom-live" polecat/custom-live
mk_wt "$REPO/wt/custom-doom" polecat/custom-doom
cat > "$STUB_STATUSES" <<'JSON'
{"built_in_statuses":[{"name":"open","category":"active"},{"name":"closed","category":"done"}],
 "custom_statuses":[{"name":"on_hold","category":"frozen"}]}
JSON
bead b-cust-live on_hold  "" "$REPO/wt/custom-live" polecat/custom-live
bead b-cust-done closed  100 "$REPO/wt/custom-live" polecat/custom-live
bead b-cust-doom closed  100 "$REPO/wt/custom-doom" polecat/custom-doom
OUT="$(run)"
if exists "$REPO/wt/custom-live"; then ok "a custom non-done status the script never enumerates still protects its worktree"; else bad "a custom non-done status the script never enumerates still protects its worktree"; fi
if exists "$REPO/wt/custom-doom"; then bad "its closed-only neighbour is still taken"; else ok "its closed-only neighbour is still taken"; fi

# A store whose status contract will not parse is skipped whole: the reaper
# cannot tell live from done there, so it reaps nothing rather than guess. With
# only this store, the pass refuses, as it does for an unreadable ledger.
new_repo
mk_wt "$REPO/wt/no-contract" polecat/no-contract
bead b-nc closed 100 "$REPO/wt/no-contract" polecat/no-contract
echo 'not json' > "$STUB_STATUSES"
OUT="$(run 2>&1)"
if exists "$REPO/wt/no-contract"; then ok "an unreadable status contract reaps nothing"; else bad "an unreadable status contract reaps nothing"; fi
has "$OUT" "refusing to reap" "the refusal says so"

# --- the archive tag pins what nothing else reaches ------------------------
# A detached worktree's HEAD is the only ref on its commits. Without the pin,
# removing the checkout leaves them unreachable; the tag is what makes the
# removal an undo away.
new_repo
mk_wt "$REPO/wt/detached" --detach
TIP="$(git -C "$REPO/wt/detached" rev-parse HEAD)"
bead b-det closed 100 "$REPO/wt/detached" ""
run > /dev/null
if exists "$REPO/wt/detached"; then bad "a detached worktree is removed"; else ok "a detached worktree is removed"; fi
TAG="$(git -C "$REPO" tag -l 'archive/worktree/*')"
has "$TAG" "archive/worktree/b-det@" "the removal is pinned by an archive tag naming the bead"
eq "$(git -C "$REPO" rev-parse "$TAG^{commit}" 2>/dev/null)" "$TIP" "the tag resolves to the tip that was removed"
if grep -qxF "$TIP" < <(git -C "$REPO" rev-list --branches --remotes 2>/dev/null); then
    bad "the pinned tip is reachable from no branch — the pin is load-bearing"
else ok "the pinned tip is reachable from no branch — the pin is load-bearing"; fi
has "$(git -C "$REPO" cat-file -p "$TAG" 2>/dev/null)" "worktree add" "the tag message carries the restore command"

# No pin, no removal: a repo that cannot write the tag keeps its worktree.
new_repo
mk_wt "$REPO/wt/unpinnable" polecat/unpinnable
bead b-unpin closed 100 "$REPO/wt/unpinnable" polecat/unpinnable
chmod -R a-w "$REPO/.git/refs" 2>/dev/null
OUT="$(run)"
chmod -R u+w "$REPO/.git/refs" 2>/dev/null
if exists "$REPO/wt/unpinnable"; then ok "a tip that cannot be pinned is not removed"; else bad "a tip that cannot be pinned is not removed"; fi
has "$OUT" "refused" "the unpinnable tree is reported as refused"

# --- agent homes and live processes ----------------------------------------
# The home matches a roster template and is held whatever its bead says. The
# per-bead worktree nested inside it is taken in the same run: a pattern whose
# wildcard crossed a path separator would hold both, and the summary alone
# cannot tell those two passes apart.
new_repo
HOME_WT="$CITY/.gc/worktrees/demo/polecats/demo.polecat-1"
mk_wt "$HOME_WT" polecat/home
mk_wt "$HOME_WT/worktrees/nested" polecat/nested
bead b-home   closed 100 "$HOME_WT" polecat/home
bead b-nested closed 100 "$HOME_WT/worktrees/nested" polecat/nested
run > /dev/null
if exists "$HOME_WT/.git"; then ok "an agent home matching a roster template is held"; else bad "an agent home matching a roster template is held"; fi
if exists "$HOME_WT/worktrees/nested"; then bad "the per-bead worktree nested inside that home is still taken"; else ok "the per-bead worktree nested inside that home is still taken"; fi

# A registered child holds its parent even when no template names it, and the
# child itself is taken in the same pass — the pair drains leaf-first.
new_repo
mk_wt "$REPO/wt/parent" polecat/parent
mk_wt "$REPO/wt/parent/child" polecat/child
bead b-parent closed 100 "$REPO/wt/parent" polecat/parent
bead b-child  closed 100 "$REPO/wt/parent/child" polecat/child
run > /dev/null
if exists "$REPO/wt/parent/.git"; then ok "a worktree with a registered child is held"; else bad "a worktree with a registered child is held"; fi
if exists "$REPO/wt/parent/child"; then bad "the child is taken in the same pass"; else ok "the child is taken in the same pass"; fi

# A session's own directory is held, and so is the tree containing it: an
# agent whose cwd is a subdirectory is still standing in the checkout.
new_repo
mk_wt "$REPO/wt/session"  polecat/session
mk_wt "$REPO/wt/deep-cwd" polecat/deep-cwd
mk_wt "$REPO/wt/taken"    polecat/taken
mkdir -p "$REPO/wt/deep-cwd/sub"
bead b-sess  closed 100 "$REPO/wt/session"  polecat/session
bead b-deep  closed 100 "$REPO/wt/deep-cwd" polecat/deep-cwd
bead b-taken closed 100 "$REPO/wt/taken"    polecat/taken
jq -c --arg d "$REPO/wt/session" '{sessions:[{work_dir:$d}]}' <<< '{}' > "$STUB_SESSIONS"
( cd "$REPO/wt/deep-cwd/sub" && exec sleep 25 ) &
SLEEPER=$!
# A backgrounded subshell forks with the caller's cwd and only then chdirs, so
# wait for /proc to show the directory the run is meant to find.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(readlink -f "/proc/$SLEEPER/cwd" 2>/dev/null)" = "$REPO/wt/deep-cwd/sub" ] && break
    sleep 0.1
done
run > /dev/null
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null
echo '{"sessions":[]}' > "$STUB_SESSIONS"
if exists "$REPO/wt/session"; then ok "a session work_dir is held"; else bad "a session work_dir is held"; fi
if exists "$REPO/wt/deep-cwd"; then ok "a live process's cwd holds the tree containing it"; else bad "a live process's cwd holds the tree containing it"; fi
if exists "$REPO/wt/taken"; then bad "their equally stale neighbour is still taken"; else ok "their equally stale neighbour is still taken"; fi

# A locked worktree is the operator saying no.
new_repo
mk_wt "$REPO/wt/locked" polecat/locked
mk_wt "$REPO/wt/free"   polecat/free
git -C "$REPO" worktree lock "$REPO/wt/locked"
bead b-lock closed 100 "$REPO/wt/locked" polecat/locked
bead b-free closed 100 "$REPO/wt/free"   polecat/free
run > /dev/null
if exists "$REPO/wt/locked"; then ok "a locked worktree is held"; else bad "a locked worktree is held"; fi
if exists "$REPO/wt/free"; then bad "an unlocked neighbour is taken"; else ok "an unlocked neighbour is taken"; fi

# --- reporting is measured, not assumed ------------------------------------
# `git worktree remove` returning 0 is not proof the tree is gone. A wrapper
# that reports success and deletes nothing must be counted as a failure, or a
# pass that freed nothing reads exactly like one that freed everything.
new_repo
mk_wt "$REPO/wt/liar" polecat/liar
bead b-liar closed 100 "$REPO/wt/liar" polecat/liar
REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<STUB
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "remove" ] && found=1; done
if [ "\${found:-}" = "1" ]; then exit 0; fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$BIN/git"
OUT="$(run)"
rm -f "$BIN/git"
has "$OUT" "left the directory standing" "a removal that freed nothing is reported, not counted as a reap"
has "$OUT" "removed 0 of" "and it is not counted as a removal"

# A repo whose PR listing fails is held whole. This gate is the backstop for a
# ledger that already disagrees with reality, so failing open would drop it
# exactly where it earns its place.
new_repo
mk_wt "$REPO/wt/held" polecat/held
bead b-held closed 100 "$REPO/wt/held" polecat/held
OUT="$(STUB_PR_RC=1 run)"
if exists "$REPO/wt/held"; then ok "a repo whose PR listing fails is held"; else bad "a repo whose PR listing fails is held"; fi
has "$OUT" "held $REPO" "the hold is reported with its reason"

# An empty ledger everywhere is a broken lookup, not an empty city: every path
# would read as unclaimed.
new_repo
mk_wt "$REPO/wt/unclaimed" polecat/unclaimed
OUT="$(run 2>&1)"
if exists "$REPO/wt/unclaimed"; then ok "an unreadable ledger reaps nothing"; else bad "an unreadable ledger reaps nothing"; fi
has "$OUT" "refusing to reap" "the refusal says so"

# --- dry run ---------------------------------------------------------------
new_repo
mk_wt "$REPO/wt/planned" polecat/planned
bead b-plan closed 100 "$REPO/wt/planned" polecat/planned
OUT="$(run --dry-run)"
if exists "$REPO/wt/planned"; then ok "--dry-run removes nothing"; else bad "--dry-run removes nothing"; fi
has "$OUT" "would remove 1 worktrees" "--dry-run reports the plan"
has "$OUT" "$REPO/wt/planned" "--dry-run names each path it would take"
eq "$(git -C "$REPO" tag -l 'archive/worktree/*' | wc -l)" 0 "--dry-run writes no archive tag"

# --- prunable registry litter is pinned, and a dry run prunes nothing -------
# A worktree whose directory was deleted out from under git leaves an admin
# HEAD behind. `git worktree prune` reclaims the entry by dropping that HEAD,
# which for a detached worktree is the only ref its commits have — the same
# loss the removal pin prevents. A dry run must not prune; a real run pins the
# tip first. The dry run is the keep and the real run is the take, on one entry.
new_repo
mk_wt "$REPO/wt/gone" --detach
GONE_TIP="$(git -C "$REPO/wt/gone" rev-parse HEAD)"
bead b-gone closed 100 "$REPO/wt/gone" ""
rm -rf "$REPO/wt/gone"                 # rogue delete: dir gone, admin entry lingers
run --dry-run > /dev/null
if registered "$REPO/wt/gone"; then ok "--dry-run does not prune registry litter"; else bad "--dry-run does not prune registry litter"; fi
eq "$(git -C "$REPO" tag -l 'archive/worktree/*' | wc -l)" 0 "--dry-run pins no prunable tip"
run > /dev/null
if registered "$REPO/wt/gone"; then bad "a real run prunes the litter entry"; else ok "a real run prunes the litter entry"; fi
GTAG="$(git -C "$REPO" tag -l 'archive/worktree/*')"
has "$GTAG" "archive/worktree/b-gone@" "the prunable tip is pinned before prune, named for its bead"
eq "$(git -C "$REPO" rev-parse "$GTAG^{commit}" 2>/dev/null)" "$GONE_TIP" "the pin resolves to the tip prune would have orphaned"
if grep -qxF "$GONE_TIP" < <(git -C "$REPO" rev-list --branches --remotes 2>/dev/null); then
    bad "the orphaned tip is reachable from no branch — the pin is load-bearing"
else ok "the orphaned tip is reachable from no branch — the pin is load-bearing"; fi

# No pin, no prune: a repo that cannot write the tag keeps its prunable entry,
# so the admin HEAD — the detached tip's only ref — survives for a later pass
# rather than being dropped now.
new_repo
mk_wt "$REPO/wt/nopin" --detach
bead b-nopin closed 100 "$REPO/wt/nopin" ""
rm -rf "$REPO/wt/nopin"
chmod -R a-w "$REPO/.git/refs" 2>/dev/null
run > /dev/null
chmod -R u+w "$REPO/.git/refs" 2>/dev/null
if registered "$REPO/wt/nopin"; then ok "an unpinnable prunable tip is not pruned"; else bad "an unpinnable prunable tip is not pruned"; fi
eq "$(git -C "$REPO" tag -l 'archive/worktree/*' | wc -l)" 0 "and no tag was written before the prune was held"

# --- the budget yields, and says what it left -------------------------------
# A slow `git` on PATH spends the budget inside the pass, which is the only way
# a fixture this small reaches the guard. What it yields must be reported as
# untaken, not as reaped, and the tree must still be there.
new_repo
mk_wt "$REPO/wt/first"  polecat/first
mk_wt "$REPO/wt/second" polecat/second
bead b-first  closed 100 "$REPO/wt/first"  polecat/first
bead b-second closed 100 "$REPO/wt/second" polecat/second
REAL_GIT="$(command -v git)"
printf '#!/bin/sh\nsleep 2\nexec %s "$@"\n' "$REAL_GIT" > "$BIN/git"
chmod +x "$BIN/git"
OUT="$(WORKTREE_REAP_BUDGET=1 run)"
rm -f "$BIN/git"
has "$OUT" "yielded" "a spent budget is reported as a yield"
has "$OUT" "the next pass takes them" "the yield says the work is not lost"
if exists "$REPO/wt/first" && exists "$REPO/wt/second"; then ok "over budget: the yielded trees are still on disk"; else ok "over budget: the pass took what it could before yielding"; fi

# --- rails ------------------------------------------------------------------
new_repo
mk_wt "$REPO/wt/railed" polecat/railed
bead b-rail closed 100 "$REPO/wt/railed" polecat/railed
OUT="$(WORKTREE_REAP_CLOSED_AFTER=0 run)"; RC=$?
eq "$RC" 2 "a zero horizon is refused"
if exists "$REPO/wt/railed"; then ok "the refused run removed nothing"; else bad "the refused run removed nothing"; fi
OUT="$(WORKTREE_REAP_CLOSED_AFTER=notanumber run)"; RC=$?
eq "$RC" 2 "a non-numeric horizon is refused"
OUT="$(run --wat)"; RC=$?
eq "$RC" 2 "an unknown argument is refused"

echo
echo "worktree-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
