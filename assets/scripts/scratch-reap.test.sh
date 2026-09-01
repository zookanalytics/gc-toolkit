#!/usr/bin/env bash
# Tests for scratch-reap.sh against a synthetic scratch root. Real filesystem,
# no stubs: every property here is a question about what survives on disk.
#
# Covers the two horizons and the boundary between them (a tree past the
# remove horizon goes, one past only the empty horizon keeps its directories,
# a fresh one is untouched); the age reading, which takes the NEWEST entry in
# a tree so one stale file cannot condemn an active session; the live-session
# hold, exercised against a real process carrying CLAUDE_CODE_SESSION_ID; the
# read-only tree that refuses deletion until it is chmod-ed; stray files above
# the session trees; the budget yield, which must report zero for the tier it
# skipped rather than its plan; --dry-run; and the root rails, which are what
# keep a recursive delete off any directory that is not a scratch root.
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
export SCRATCH_REAP_EMPTY_AFTER=$((12 * HOUR))
export SCRATCH_REAP_REMOVE_AFTER=$((72 * HOUR))

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

# --- the two horizons ------------------------------------------------------
reset_root
mk_session slug-a ancient 100
mk_session slug-a middling 24
mk_session slug-a fresh 1
OUT="$(run)"

if exists "$ROOT/slug-a/ancient"; then bad "past the remove horizon: tree is gone"; else ok "past the remove horizon: tree is gone"; fi
if exists "$ROOT/slug-a/middling/scratchpad"; then ok "past the empty horizon: directories survive"; else bad "past the empty horizon: directories survive"; fi
if exists "$ROOT/slug-a/middling/scratchpad/f"; then bad "past the empty horizon: files are gone"; else ok "past the empty horizon: files are gone"; fi
if exists "$ROOT/slug-a/fresh/scratchpad/f"; then ok "inside both horizons: untouched"; else bad "inside both horizons: untouched"; fi
has "$OUT" "removed 1 trees, emptied 1" "summary counts each tier"

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

# A tree already down to bare directories has nothing to empty, so it is not
# re-listed every pass; it waits for the remove horizon.
reset_root
mk_session slug-b husk 24
rm -f "$ROOT/slug-b/husk/scratchpad/f"
touch -d "@$((NOW - 24 * HOUR))" "$ROOT/slug-b/husk/scratchpad" "$ROOT/slug-b/husk"
OUT="$(run)"
has "$OUT" "emptied 0" "a tree with no files left is not counted as emptied"
if exists "$ROOT/slug-b/husk/scratchpad"; then ok "the husk waits for the remove horizon"; else bad "the husk waits for the remove horizon"; fi

# --- live sessions are held whatever their mtime ---------------------------
reset_root
mk_session slug-c live-abc 100
mk_session slug-c dead-abc 100
env CLAUDE_CODE_SESSION_ID=live-abc sleep 25 &
SLEEPER=$!
run > /dev/null
kill "$SLEEPER" 2>/dev/null; wait "$SLEEPER" 2>/dev/null
if exists "$ROOT/slug-c/live-abc/scratchpad/f"; then ok "a session with a running process is held past both horizons"; else bad "a session with a running process is held past both horizons"; fi
if exists "$ROOT/slug-c/dead-abc"; then bad "its equally stale neighbour is still reaped"; else ok "its equally stale neighbour is still reaped"; fi

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

# --- empty slug directories, but only at the top ---------------------------
reset_root
mk_session slug-f gone 100
mk_session slug-g emptied 24
run > /dev/null
if exists "$ROOT/slug-f"; then bad "a slug directory that lost its last session is pruned"; else ok "a slug directory that lost its last session is pruned"; fi
if exists "$ROOT/slug-g/emptied/scratchpad"; then ok "an emptied scratchpad inside a session is NOT pruned"; else bad "an emptied scratchpad inside a session is NOT pruned"; fi

# --- the budget yields the cheaper tiers, and reports zero for them ---------
# A slow `du` on PATH spends the budget inside the pass, which is the only way
# a fixture this small can reach the guard.
reset_root
mk_session slug-k ancient 100
mk_session slug-k middling 24
SLOWBIN="$TMP/slowbin"; mkdir -p "$SLOWBIN"
REAL_DU="$(command -v du)"
printf '#!/bin/sh\nsleep 2\nexec %s "$@"\n' "$REAL_DU" > "$SLOWBIN/du"
chmod +x "$SLOWBIN/du"
OUT="$(PATH="$SLOWBIN:$PATH" SCRATCH_REAP_BUDGET=1 run)"
if exists "$ROOT/slug-k/ancient"; then bad "over budget: removal still runs"; else ok "over budget: removal still runs"; fi
if exists "$ROOT/slug-k/middling/scratchpad/f"; then ok "over budget: the empty tier yields"; else bad "over budget: the empty tier yields"; fi
has "$OUT" "yielded at the empty batch" "over budget: the yield is reported"
has "$OUT" "emptied 0" "over budget: a yielded tier reports zero, not its plan"

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

OUT="$(SCRATCH_REAP_REMOVE_AFTER=60 SCRATCH_REAP_EMPTY_AFTER=120 run)"; RC=$?
eq "$RC" 2 "a remove horizon shorter than the empty horizon is refused"
if exists "$ROOT/slug-i/ancient/scratchpad/f"; then ok "the refused run deleted nothing"; else bad "the refused run deleted nothing"; fi

OUT="$(SCRATCH_REAP_EMPTY_AFTER=notanumber run)"; RC=$?
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

echo
echo "scratch-reap.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
