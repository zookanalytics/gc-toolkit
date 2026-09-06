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
export STUB_BD_ID_RC=0
export PATH="$BIN:$PATH"

# --- stubs -----------------------------------------------------------------
# `gc bd list --json` emits metadata as an OBJECT, which is what the running
# binary does; a stub that emitted a string would let a parse the tool never
# needs pass for a parse it does.
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
# A --rig <name> travels right after the top-level command group. Strip it,
# keeping the group as $1 so the case key stays "<group> <sub>"; the captured
# name lets bd statuses/list read a per-rig fixture (statuses.<rig>.json,
# beads.<rig>.json) where a multi-store test writes one, and fall back to the
# shared file otherwise. Single-store tests never pass --rig, so nothing here
# changes for them.
grp="${1:-}"; rig=""
if [ "${2:-}" = "--rig" ]; then rig="${3:-}"; set -- "$grp" "${@:4}"; fi
case "${1:-} ${2:-}" in
  "agent list")   cat "${STUB_AGENTS:?}" ;;
  "session list") cat "${STUB_SESSIONS:?}" ;;
  "rig list")     if [ -n "${STUB_RIGS:-}" ]; then cat "$STUB_RIGS"; else echo '{"rigs":[]}'; fi ;;
  "bd statuses")
    sf="${STUB_STATUSES:?}"
    [ -n "$rig" ] && [ -f "${STUB_STATUSES%.json}.$rig.json" ] && sf="${STUB_STATUSES%.json}.$rig.json"
    cat "$sf" ;;
  "bd list")
    want=""; has_id=0
    while [ $# -gt 0 ]; do
      case "$1" in --status) want="$2"; shift ;; --status=*) want="${1#--status=}" ;; --id|--id=*) has_id=1 ;; esac
      shift
    done
    # The branch pass alone scopes its closed-lookup with --id; STUB_BD_ID_RC
    # lets a test fail exactly that read while the unscoped worktree-side ledger
    # reads keep answering.
    [ "$has_id" = "1" ] && [ "${STUB_BD_ID_RC:-0}" != "0" ] && { echo "gc: simulated ledger failure" >&2; exit "${STUB_BD_ID_RC}"; }
    bf="${STUB_BEADS:?}"
    [ -n "$rig" ] && [ -f "${STUB_BEADS%.json}.$rig.json" ] && bf="${STUB_BEADS%.json}.$rig.json"
    # Bind the row before testing it: the argument to `contains` is evaluated
    # against the string being searched, so a bare `.status` in there reads the
    # status field of $want.
    jq -c --arg want ",$want," '[ .[] | . as $b | select($want | contains("," + $b.status + ",")) ]' "$bf"
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
bead_to() { # <file> <id> <status> <hours-since-close> <work_dir> <branch>
    local f="$1" id="$2" st="$3" hrs="$4" wd="$5" br="$6"
    local at; at="$(date -u -d "@$((NOW - hrs * HOUR))" +%Y-%m-%dT%H:%M:%SZ)"
    [ -s "$f" ] || echo '[]' > "$f"
    jq -c --arg id "$id" --arg st "$st" --arg at "$at" --arg wd "$wd" --arg br "$br" \
        '. += [{id: $id, status: $st, closed_at: $at, updated_at: $at,
                metadata: ({} | if $wd == "" then . else .work_dir = $wd end
                              | if $br == "" then . else .branch  = $br end)}]' \
        "$f" > "$f.n" && mv "$f.n" "$f"
}
# The default store the single-repo tests write. bead_to on a named file is the
# multi-store form, where one rig stays readable while another cannot be read.
bead() { bead_to "$STUB_BEADS" "$@"; }

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

# --- the branch pass drops what the worktree pass leaves behind -------------
# `git worktree remove` leaves the branch, so a polecat/<bead-id> ref outlives
# its checkout. The pass drops one once its bead has CLOSED and its content is
# on the default branch — by reachability, or by the squash signal of its bead
# id on a commit subject. origin/main is the authority, built here with plumbing
# so the working tree and local main stay put. Every take is asserted beside a
# keep in one run: an open bead, a still-unmerged tip, a ref naming no bead, and
# a ref outside the polecat family are all held while the merged, closed
# neighbours go — and a dry run over the same fixture takes none of them.
land() { # <subject> — append a commit to origin/main, working tree untouched
    local parent tree c
    parent="$(git -C "$REPO" rev-parse -q --verify refs/remotes/origin/main)"
    tree="$(git -C "$REPO" rev-parse "${parent}^{tree}")"
    c="$(git -C "$REPO" commit-tree "$tree" -p "$parent" -m "$1")"
    git -C "$REPO" update-ref refs/remotes/origin/main "$c"
}
gone_upstream() { # <branch> — an origin upstream configured but never fetched
    git -C "$REPO" config "branch.$1.remote" origin
    git -C "$REPO" config "branch.$1.merge" "refs/heads/$1"
}
branch_exists() { git -C "$REPO" show-ref --verify --quiet "refs/heads/$1"; }

new_repo
# origin/main starts at the reachable branch's tip, so that branch is an
# ancestor of it; the squash subjects land on top.
mk_wt "$REPO/wt/reach" polecat/zz-reach
REACH="$(git -C "$REPO" rev-parse polecat/zz-reach)"
git -C "$REPO" worktree remove --force "$REPO/wt/reach"
git -C "$REPO" update-ref refs/remotes/origin/main "$REACH"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# squash-landed: closed bead, its id on a default-branch subject, worktree gone
mk_wt "$REPO/wt/drop" polecat/zz-drop
git -C "$REPO" worktree remove --force "$REPO/wt/drop"
land "feat: the drop (zz-drop) (#1)"
# open bead: landed all the same, but a live bead holds its branch
mk_wt "$REPO/wt/open" polecat/zz-open
git -C "$REPO" worktree remove --force "$REPO/wt/open"
land "feat: the open (zz-open) (#2)"
# unmerged: closed, but its content reached the default branch nowhere
mk_wt "$REPO/wt/unmgd" polecat/zz-unmgd
git -C "$REPO" worktree remove --force "$REPO/wt/unmgd"
# gone upstream, at the default-branch base: git's own -d takes it
git -C "$REPO" branch polecat/zz-gone main
gone_upstream polecat/zz-gone
# gone upstream, squash-merged: -d declines the unmerged tip, -D takes it
mk_wt "$REPO/wt/gsq" polecat/zz-gsq
git -C "$REPO" worktree remove --force "$REPO/wt/gsq"
gone_upstream polecat/zz-gsq
land "feat: gone and squashed (zz-gsq) (#3)"
# names no bead, and a ref outside the family: both left alone
git -C "$REPO" branch polecat/roadmap main
git -C "$REPO" branch claude/research main
# a suffix ref: its bead-looking prefix zz-drop is a closed, landed bead, but
# its whole name is not a bead id — it is a different branch a live bead holds
# (zz-armowner), with an unmerged tip. Reading the whole ref, not a prefix,
# names no bead, so the pass leaves it alone; a prefix match would read it as
# zz-drop and force-delete the live work.
mk_wt "$REPO/wt/arm" polecat/zz-drop-arm
git -C "$REPO" worktree remove --force "$REPO/wt/arm"

bead zz-reach closed 100 "" polecat/zz-reach
bead zz-drop  closed 100 "" polecat/zz-drop
bead zz-open  open    "" "" polecat/zz-open
bead zz-unmgd closed 100 "" polecat/zz-unmgd
bead zz-gone  closed 100 "" polecat/zz-gone
bead zz-gsq   closed 100 "" polecat/zz-gsq
bead zz-armowner open "" "" polecat/zz-drop-arm

DRY="$(run --dry-run)"
has "$DRY" "would drop 4 stale local branches" "--dry-run reports the branch plan"
has "$DRY" "zz-gsq" "--dry-run names a branch it would drop"
if branch_exists polecat/zz-reach && branch_exists polecat/zz-gsq; then ok "--dry-run drops no branch"; else bad "--dry-run drops no branch"; fi

OUT="$(run)"
if branch_exists polecat/zz-reach; then bad "a closed bead's branch reachable from the default branch is dropped"; else ok "a closed bead's branch reachable from the default branch is dropped"; fi
if branch_exists polecat/zz-drop; then bad "a closed bead's branch squash-landed on the default branch is dropped"; else ok "a closed bead's branch squash-landed on the default branch is dropped"; fi
if branch_exists polecat/zz-gone; then bad "a gone-upstream branch at the default-branch base is dropped by git branch -d"; else ok "a gone-upstream branch at the default-branch base is dropped by git branch -d"; fi
if branch_exists polecat/zz-gsq; then bad "a gone-upstream squash-merged branch falls from -d through to -D"; else ok "a gone-upstream squash-merged branch falls from -d through to -D"; fi
if branch_exists polecat/zz-open; then ok "an OPEN bead holds its branch, though its id landed on the default branch"; else bad "an OPEN bead holds its branch, though its id landed on the default branch"; fi
if branch_exists polecat/zz-unmgd; then ok "a closed bead whose content reached no default branch keeps its branch"; else bad "a closed bead whose content reached no default branch keeps its branch"; fi
if branch_exists polecat/roadmap; then ok "a polecat ref naming no bead is left alone"; else bad "a polecat ref naming no bead is left alone"; fi
if branch_exists claude/research; then ok "a ref outside the polecat family is never a candidate"; else bad "a ref outside the polecat family is never a candidate"; fi
if branch_exists polecat/zz-drop-arm; then ok "a suffix ref whose bead-looking prefix is a closed landed bead is left alone"; else bad "a suffix ref whose bead-looking prefix is a closed landed bead is left alone"; fi
has "$OUT" "dropped 4 stale local branches (1 via git branch -d, 3 via -D)" "the summary counts the drops and splits them by delete verb"

# A live bead on the branch holds it even when its content is on the default
# branch: the ref is a resumable claim, not disposable cruft, until it closes.
new_repo
mk_wt "$REPO/wt/live" polecat/zz-live
LIVE_TIP="$(git -C "$REPO" rev-parse polecat/zz-live)"
git -C "$REPO" worktree remove --force "$REPO/wt/live"
git -C "$REPO" update-ref refs/remotes/origin/main "$LIVE_TIP"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
mk_wt "$REPO/wt/donebr" polecat/zz-done
git -C "$REPO" worktree remove --force "$REPO/wt/donebr"
land "feat: done (zz-done) (#9)"
bead zz-live deferred "" "" polecat/zz-live
bead zz-done closed  100 "" polecat/zz-done
run > /dev/null
if branch_exists polecat/zz-live; then ok "a deferred bead's branch is held though reachable from the default branch"; else bad "a deferred bead's branch is held though reachable from the default branch"; fi
if branch_exists polecat/zz-done; then bad "its closed neighbour is dropped in the same run"; else ok "its closed neighbour is dropped in the same run"; fi

# The bead a branch NAMES is not always the bead that HOLDS it. A rework or
# rebase child records its predecessor's branch in metadata.branch, or an open
# PR carries it as head, while the name-bead is closed and its content landed.
# The closed-and-squashed proof alone would drop the ref, but the tip is that
# live claimant's only local copy of unmerged work. That is the same
# OPEN_BRANCH / PR_BRANCH signal the worktree pass keeps a tree on. Both are
# held here while a closed-only neighbour no live bead claims is dropped in the
# same run.
new_repo
git -C "$REPO" update-ref refs/remotes/origin/main main
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
mk_wt "$REPO/wt/childbr" polecat/zz-base
git -C "$REPO" worktree remove --force "$REPO/wt/childbr"
land "feat: the base (zz-base) (#7)"
mk_wt "$REPO/wt/prbr" polecat/zz-prheld
git -C "$REPO" worktree remove --force "$REPO/wt/prbr"
land "feat: pr held (zz-prheld) (#8)"
mk_wt "$REPO/wt/neighbr" polecat/zz-neigh
git -C "$REPO" worktree remove --force "$REPO/wt/neighbr"
land "feat: the neighbour (zz-neigh) (#9)"
echo "polecat/zz-prheld" > "$STUB_PR_BRANCHES"
bead zz-base   closed 100 "" polecat/zz-base
bead zz-child  open    "" "" polecat/zz-base
bead zz-prheld closed 100 "" polecat/zz-prheld
bead zz-neigh  closed 100 "" polecat/zz-neigh
OUT="$(run)"
if branch_exists polecat/zz-base; then ok "a different live bead's claim on a closed, landed ref holds the branch"; else bad "a different live bead's claim on a closed, landed ref holds the branch"; fi
if branch_exists polecat/zz-prheld; then ok "an open PR's head holds a closed, landed branch"; else bad "an open PR's head holds a closed, landed branch"; fi
if branch_exists polecat/zz-neigh; then bad "a closed-only neighbour no live bead claims is dropped in the same run"; else ok "a closed-only neighbour no live bead claims is dropped in the same run"; fi
has "$OUT" "dropped 1 stale local branches" "only the unclaimed neighbour is dropped"

# A store the branch pass cannot read confirms nothing closed, so the family is
# held — the same fail-closed the worktree pass takes on a down ledger. The stub
# fails exactly the --id-scoped closed-lookup the branch pass makes; the live
# bead keeps the worktree-side ledger answering, so the pass reaches that step.
new_repo
mk_wt "$REPO/wt/held-br" polecat/zz-held
HELD_TIP="$(git -C "$REPO" rev-parse polecat/zz-held)"
git -C "$REPO" worktree remove --force "$REPO/wt/held-br"
git -C "$REPO" update-ref refs/remotes/origin/main "$HELD_TIP"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
bead zz-anchor open "" "" polecat/zz-anchor
bead zz-held closed 100 "" polecat/zz-held
STUB_BD_ID_RC=1 run > /dev/null
if branch_exists polecat/zz-held; then ok "a branch pass whose closed-lookup fails drops nothing"; else bad "a branch pass whose closed-lookup fails drops nothing"; fi

# A repo whose open-PR listing fails holds its whole BRANCH family, not just its
# worktrees. An empty PR_BRANCH map then means "unread", not "no open PR heads
# this ref", so a closed, landed branch an unseen PR could still head is kept.
# The keep is the PR-unreadable run; the take is a readable run over the same
# branch, which drops it — proving the hold, not another gate, is what saved it.
new_repo
mk_wt "$REPO/wt/heldpr" polecat/zz-heldpr
HELDPR_TIP="$(git -C "$REPO" rev-parse polecat/zz-heldpr)"
git -C "$REPO" worktree remove --force "$REPO/wt/heldpr"
git -C "$REPO" update-ref refs/remotes/origin/main "$HELDPR_TIP"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
bead zz-anchor open   ""  "" polecat/zz-anchor    # keeps the ledger answering
bead zz-heldpr closed 100 "" polecat/zz-heldpr    # closed, landed: droppable but for the hold
: > "$STUB_PR_BRANCHES"                            # no PR names it once the listing works
OUT="$(STUB_PR_RC=1 run)"
if branch_exists polecat/zz-heldpr; then ok "a repo whose PR listing fails holds its closed, landed branch"; else bad "a repo whose PR listing fails holds its closed, landed branch"; fi
has "$OUT" "held $REPO" "the branch-family hold is the repo hold already reported"
run > /dev/null                                    # PRs readable and empty: the same branch is a valid drop
if branch_exists polecat/zz-heldpr; then bad "with the PR listing readable the branch is dropped"; else ok "with the PR listing readable the branch is dropped"; fi

# A store whose live contract will not read holds its whole branch family, even
# while another store keeps the global ledger answering so the pass does not
# refuse outright. The unreadable store's live rows are skipped, so OPEN_BRANCH
# never learns a live claimant there; an independent closed-lookup must not then
# be trusted to drop its refs. The healthy store's own closed, landed branch is
# dropped in the same run — the take that proves the pass ran and discriminated.
new_repo                                   # $REPO is rig "demo": healthy
REPO2="$CITY/rigs/broken"                  # rig "broken": its status contract will not parse
git init -q -b main "$REPO2"
git -C "$REPO2" config user.email t@example.com
git -C "$REPO2" config user.name Test
git -C "$REPO2" config commit.gpgsign false
git -C "$REPO2" remote add origin https://github.com/zook/broken.git
echo seed > "$REPO2/seed"; git -C "$REPO2" add seed; git -C "$REPO2" commit -qm seed
# Rig mode: both stores come from `gc rig list`, named, so --rig is passed.
jq -n --arg r1 "$REPO" --arg r2 "$REPO2" \
    '{rigs:[{name:"demo",path:$r1,hq:false},{name:"broken",path:$r2,hq:false}]}' > "$TMP/rigs.json"
export STUB_RIGS="$TMP/rigs.json"
# demo: a live bead keeps its ledger answering, and a closed, landed branch is the take.
: > "$TMP/beads.demo.json"
bead_to "$TMP/beads.demo.json" d-live     open   ""  "" polecat/d-live
bead_to "$TMP/beads.demo.json" zz-healthy closed 100 "" polecat/zz-healthy
mk_wt "$REPO/wt/healthy" polecat/zz-healthy
HEALTHY_TIP="$(git -C "$REPO" rev-parse polecat/zz-healthy)"
git -C "$REPO" worktree remove --force "$REPO/wt/healthy"
git -C "$REPO" update-ref refs/remotes/origin/main "$HEALTHY_TIP"
git -C "$REPO" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
# broken: statuses will not parse, so its live rows are never read. Its closed,
# landed name-bead zz-bad would fall to the independent closed-lookup; a live
# child records polecat/zz-bad, the claimant the skipped live read cannot see.
# The family is held because the STORE is unreadable, not because the child was seen.
echo 'not json' > "$TMP/statuses.broken.json"
: > "$TMP/beads.broken.json"
bead_to "$TMP/beads.broken.json" zz-bad   closed 100 "" polecat/zz-bad
bead_to "$TMP/beads.broken.json" zz-child open   ""  "" polecat/zz-bad
BAD_TREE="$(git -C "$REPO2" rev-parse main^{tree})"
BAD_TIP="$(git -C "$REPO2" commit-tree "$BAD_TREE" -p "$(git -C "$REPO2" rev-parse main)" -m 'work in zz-bad')"
git -C "$REPO2" branch polecat/zz-bad "$BAD_TIP"
git -C "$REPO2" update-ref refs/remotes/origin/main "$BAD_TIP"
git -C "$REPO2" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
OUT="$(WORKTREE_REAP_REPOS= run)"
if git -C "$REPO2" show-ref --verify --quiet refs/heads/polecat/zz-bad; then ok "an unreadable store's branch family is held though its name-bead is closed and landed"; else bad "an unreadable store's branch family is held though its name-bead is closed and landed"; fi
if git -C "$REPO" show-ref --verify --quiet refs/heads/polecat/zz-healthy; then bad "the healthy store's closed, landed branch is dropped in the same run"; else ok "the healthy store's closed, landed branch is dropped in the same run"; fi
has "$OUT" "dropped 1 stale local branches" "only the healthy store's branch is dropped"
unset STUB_RIGS

echo
echo "worktree-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
