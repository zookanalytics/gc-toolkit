#!/usr/bin/env bash
# Tests for scratch-reap.sh against a synthetic scratch root. Real filesystem,
# no stubs: every property here is a question about what survives on disk.
#
# Covers the horizon and its boundary (a tree past it goes whole, a tree inside
# it is untouched); the age reading, which takes the NEWEST entry in a tree so
# one stale file cannot condemn an active session; the live-session hold,
# exercised against a real process carrying CLAUDE_CODE_SESSION_ID; the
# read-only tree that refuses deletion until it is chmod-ed; stray files above
# the session trees, and stray symlinks, which are unlinked without a chmod
# that would reach their targets; the large-file report, which must name a
# stray dump as well as a file inside a tree; the budget yield, which must
# report zero for the tier it skipped and name none of its files, while still
# naming the files of the tier that ran; --dry-run; and the root rails, which
# are what keep a recursive delete off any directory that is not a scratch
# root.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out the shell tools
PASS=0; FAIL=0

SUT="$HERE/scratch-reap.sh"
ROOT="$TMP/claude-$(id -u)"
NOW="$(date +%s)"

HOUR=3600
export SCRATCH_REAP_ROOT="$ROOT"
export SCRATCH_REAP_INACTIVE_AFTER=$((24 * HOUR))

# A session tree: <slug>/<id>/scratchpad/f, aged to <hours> old throughout.
mk_session() { # <slug> <id> <hours-old> [file-bytes]
    local d="$ROOT/$1/$2" ts=$((NOW - $3 * HOUR)) bytes="${4:-4096}"
    mkdir -p "$d/scratchpad"
    head -c "$bytes" /dev/zero > "$d/scratchpad/f"
    find "$d" -depth -exec touch -h -d "@$ts" {} +
}
exists() { [ -e "$1" ]; }

reset_root() { chmod -R u+w "$ROOT" 2>/dev/null; rm -rf "$ROOT"; mkdir -p "$ROOT"; }
run() { bash "$SUT" "$@" 2>&1; }

# --- the horizon and its boundary ------------------------------------------
reset_root
mk_session slug-a ancient 100
mk_session slug-a fresh 1
OUT="$(run)"

if exists "$ROOT/slug-a/ancient"; then bad "past the horizon: the tree is removed whole"; else ok "past the horizon: the tree is removed whole"; fi
if exists "$ROOT/slug-a/fresh/scratchpad/f"; then ok "inside the horizon: untouched"; else bad "inside the horizon: untouched"; fi
has "$OUT" "removed 1 session trees" "the summary counts what it removed"
has "$OUT" "kept 1 trees" "the summary counts what it kept"

# The boundary is the horizon itself, not some larger round number: a tree one
# hour the safe side of it survives, one hour the other side does not.
reset_root
mk_session slug-a just-inside 23
mk_session slug-a just-outside 25
run > /dev/null
if exists "$ROOT/slug-a/just-inside/scratchpad/f"; then ok "an hour inside the horizon survives"; else bad "an hour inside the horizon survives"; fi
if exists "$ROOT/slug-a/just-outside"; then bad "an hour past the horizon is reaped"; else ok "an hour past the horizon is reaped"; fi

# A tree is aged by its NEWEST entry, so one stale file in an active session
# does not condemn the session.
reset_root
mk_session slug-b mixed 100
touch -d "@$NOW" "$ROOT/slug-b/mixed/scratchpad/recent"
run > /dev/null
if exists "$ROOT/slug-b/mixed/scratchpad/f"; then ok "newest entry sets the age: a stale sibling survives"; else bad "newest entry sets the age: a stale sibling survives"; fi

# The control for that: the same tree with nothing recent in it does go.
reset_root
mk_session slug-b mixed 100
run > /dev/null
if exists "$ROOT/slug-b/mixed"; then bad "without the recent entry the same tree is reaped"; else ok "without the recent entry the same tree is reaped"; fi

# A directory mtime counts too, so a tree whose only recent activity was a
# mkdir still reads as active.
reset_root
mk_session slug-b dironly 100
touch -d "@$NOW" "$ROOT/slug-b/dironly/scratchpad"
run > /dev/null
if exists "$ROOT/slug-b/dironly/scratchpad/f"; then ok "a recent directory mtime holds the tree"; else bad "a recent directory mtime holds the tree"; fi

# --- live sessions are held whatever their mtime ---------------------------
reset_root
mk_session slug-c live-abc 100
mk_session slug-c dead-abc 100
env CLAUDE_CODE_SESSION_ID=live-abc sleep 25 &
SLEEPER=$!
OUT="$(run)"
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null
if exists "$ROOT/slug-c/live-abc/scratchpad/f"; then ok "a session with a running process is held past the horizon"; else bad "a session with a running process is held past the horizon"; fi
if exists "$ROOT/slug-c/dead-abc"; then bad "its equally stale neighbour is still reaped"; else ok "its equally stale neighbour is still reaped"; fi
has "$OUT" "held 1 live" "a held session is reported as held, not kept"

# --- read-only trees ------------------------------------------------------
# A Go module cache copied into scratch is mode 0555/0444: rm refuses it, and
# a caller that swallows the refusal frees nothing. The chmod is what makes
# the tree deletable, so this asserts on the tree, never on an exit code.
reset_root
mk_session slug-d readonly 100
mkdir -p "$ROOT/slug-d/readonly/scratchpad/modcache"
echo locked > "$ROOT/slug-d/readonly/scratchpad/modcache/pkg"
chmod 444 "$ROOT/slug-d/readonly/scratchpad/modcache/pkg"
chmod 555 "$ROOT/slug-d/readonly/scratchpad/modcache"
find "$ROOT/slug-d" -depth -exec touch -h -d "@$((NOW - 100 * HOUR))" {} + 2>/dev/null
run > /dev/null
if exists "$ROOT/slug-d/readonly"; then bad "a read-only subtree is still removed"; else ok "a read-only subtree is still removed"; fi

# --- stray files above the session trees -----------------------------------
reset_root
mk_session slug-e keeper 1
printf 'old\n' > "$ROOT/all.json";   touch -d "@$((NOW - 100 * HOUR))" "$ROOT/all.json"
printf 'new\n' > "$ROOT/fresh.json"; touch -d "@$NOW" "$ROOT/fresh.json"
printf 'old\n' > "$ROOT/slug-e/loose.json"; touch -d "@$((NOW - 100 * HOUR))" "$ROOT/slug-e/loose.json"
run > /dev/null
if exists "$ROOT/all.json"; then bad "a stale stray file at the root is deleted"; else ok "a stale stray file at the root is deleted"; fi
if exists "$ROOT/fresh.json"; then ok "a fresh stray file at the root survives"; else bad "a fresh stray file at the root survives"; fi
if exists "$ROOT/slug-e/loose.json"; then bad "a stale loose file beside the session trees is deleted"; else ok "a stale loose file beside the session trees is deleted"; fi
if exists "$ROOT/slug-e/keeper/scratchpad/f"; then ok "the live session beside it is untouched"; else bad "the live session beside it is untouched"; fi

# --- the large-file report -------------------------------------------------
# The report is what keeps a recurring writer visible, and a whole-store dump
# left loose at the root is exactly that writer, so a stray has to reach it
# the same way a file inside a doomed tree does.
reset_root
mk_session slug-l intree 100 $((9 * 1024 * 1024))
head -c $((10 * 1024 * 1024)) /dev/zero > "$ROOT/dump.json"
touch -d "@$((NOW - 100 * HOUR))" "$ROOT/dump.json"
OUT="$(run)"
has "$OUT" "reaped 10 MiB  $ROOT/dump.json" "a large stray file is named in the report"
has "$OUT" "reaped 9 MiB  $ROOT/slug-l/intree/scratchpad/f" "a large file inside a doomed tree is named in the report"

# A file the pass did not take is not reported as taken.
reset_root
mk_session slug-l kept 1 $((9 * 1024 * 1024))
OUT="$(run)"
if grep -q "reaped" <<< "$OUT"; then bad "a kept file is not named in the report"; else ok "a kept file is not named in the report"; fi

# --- empty slug directories, but only at the top ---------------------------
reset_root
mk_session slug-f gone 100
mk_session slug-g here 1
rm -f "$ROOT/slug-g/here/scratchpad/f"
run > /dev/null
if exists "$ROOT/slug-f"; then bad "a slug directory that lost its last session is pruned"; else ok "a slug directory that lost its last session is pruned"; fi
if exists "$ROOT/slug-g/here/scratchpad"; then ok "an empty scratchpad in a kept session is NOT pruned"; else bad "an empty scratchpad in a kept session is NOT pruned"; fi

# --- the budget yields the stray tier, and reports zero for it -------------
# A slow `du` on PATH spends the budget inside the pass, which is the only way
# a fixture this small can reach the guard. Both tiers carry a file over the
# large-file floor, because the yield has to reach the report as well as the
# counts: the stray is still on disk and must not be named as taken, while the
# tree the pass did take must still be named.
reset_root
mk_session slug-k ancient 100 $((9 * 1024 * 1024))
head -c $((10 * 1024 * 1024)) /dev/zero > "$ROOT/stray.json"
touch -d "@$((NOW - 100 * HOUR))" "$ROOT/stray.json"
SLOWBIN="$TMP/slowbin"; mkdir -p "$SLOWBIN"
REAL_DU="$(command -v du)"
printf '#!/bin/sh\nsleep 2\nexec %s "$@"\n' "$REAL_DU" > "$SLOWBIN/du"
chmod +x "$SLOWBIN/du"
OUT="$(PATH="$SLOWBIN:$PATH" SCRATCH_REAP_BUDGET=1 run)"
if exists "$ROOT/slug-k/ancient"; then bad "over budget: tree removal still runs"; else ok "over budget: tree removal still runs"; fi
if exists "$ROOT/stray.json"; then ok "over budget: the stray tier yields"; else bad "over budget: the stray tier yields"; fi
has "$OUT" "yielded at the stray batch" "over budget: the yield is reported"
has "$OUT" "deleted 0 stray files" "over budget: a yielded tier reports zero, not its plan"
if grep -q "stray.json" <<< "$OUT"; then bad "over budget: a yielded large stray file is not named as reaped"; else ok "over budget: a yielded large stray file is not named as reaped"; fi
has "$OUT" "reaped 9 MiB  $ROOT/slug-k/ancient/scratchpad/f" "over budget: the tier that did run still names its files"

# --- dry run ---------------------------------------------------------------
reset_root
mk_session slug-h ancient 100
OUT="$(run --dry-run)"
if exists "$ROOT/slug-h/ancient/scratchpad/f"; then ok "--dry-run deletes nothing"; else bad "--dry-run deletes nothing"; fi
has "$OUT" "would remove 1 session trees" "--dry-run reports the plan"

# --- root rails ------------------------------------------------------------
reset_root
mk_session slug-i ancient 100
NOT_SCRATCH="$TMP/not-scratch"; mkdir -p "$NOT_SCRATCH/slug/id"; : > "$NOT_SCRATCH/slug/id/keep"
OUT="$(SCRATCH_REAP_ROOT="$NOT_SCRATCH" run)"; RC=$?
eq "$RC" 2 "a root not named claude-<uid> is refused"
if exists "$NOT_SCRATCH/slug/id/keep"; then ok "the refused root is untouched"; else bad "the refused root is untouched"; fi
has "$OUT" "refusing to reap" "the refusal says so"

OUT="$(SCRATCH_REAP_ROOT="$TMP/claude-$(id -u)-absent" run)"; RC=$?
eq "$RC" 0 "an absent root is nothing to do, not an error"

OUT="$(SCRATCH_REAP_INACTIVE_AFTER=0 run)"; RC=$?
eq "$RC" 2 "a zero horizon is refused"
if exists "$ROOT/slug-i/ancient/scratchpad/f"; then ok "the refused run deleted nothing"; else bad "the refused run deleted nothing"; fi

OUT="$(SCRATCH_REAP_INACTIVE_AFTER=notanumber run)"; RC=$?
eq "$RC" 2 "a non-numeric horizon is refused"

# --- symlinks are unlinked, never followed ---------------------------------
reset_root
OUTSIDE="$TMP/outside"; mkdir -p "$OUTSIDE"; : > "$OUTSIDE/precious"
mk_session slug-j linked 100
ln -s "$OUTSIDE" "$ROOT/slug-j/linked/scratchpad/link"
find "$ROOT/slug-j" -depth -exec touch -h -d "@$((NOW - 100 * HOUR))" {} + 2>/dev/null
run > /dev/null
if exists "$OUTSIDE/precious"; then ok "a symlink out of the root is not followed"; else bad "a symlink out of the root is not followed"; fi
if exists "$ROOT/slug-j"; then bad "the tree holding it is still removed"; else ok "the tree holding it is still removed"; fi

# A stray symlink is unlinked as it stands. chmod dereferences a symlink
# argument, so putting one through the stray tier's chmod would change the
# mode of its target, and the target can be any path this uid owns.
reset_root
GUARDED="$TMP/guarded"; mkdir -p "$GUARDED"; : > "$GUARDED/f"; chmod 400 "$GUARDED/f"
ln -s "$GUARDED/f" "$ROOT/stale-link"
touch -h -d "@$((NOW - 100 * HOUR))" "$ROOT/stale-link"
run > /dev/null
if [ -L "$ROOT/stale-link" ]; then bad "a stale loose symlink is unlinked"; else ok "a stale loose symlink is unlinked"; fi
eq "$(stat -c %a "$GUARDED/f")" 400 "the target of a stray symlink keeps its mode"
if exists "$GUARDED/f"; then ok "the target of a stray symlink survives"; else bad "the target of a stray symlink survives"; fi

echo
echo "scratch-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
