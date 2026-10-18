#!/usr/bin/env bash
# cycle-recycle-hook.test.sh — hermetic test for the refinery git-op defer guard
# in the shipped Stop hook overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh.
#
# Over its threshold the hook recycles a refinery (gc handoff, then gc session
# reset) unless a git op is in flight in the refinery's working directory or in
# the rig's canonical checkout (GC_RIG_ROOT). A git-op marker counts, and so
# does a dirty tracked file anywhere in either tree, the bead store's files
# under .beads/ included. The hook exits 0 with an empty stdout either way, so
# from outside a guard that defers every turn looks like a hook with nothing to
# do. This test tells the two apart.
#
# It runs the SHIPPED script, never a copy, against real git repos. gc is
# stubbed by pointing HOME at the sandbox: the hook prepends "$HOME/go/bin" to
# PATH itself, so a stub placed there wins over the real gc. Every run starts
# from env -i, so no live GC_* variable reaches the hook.
#
# The test lives under assets/scripts/ rather than beside the hook because
# everything under overlays/cycle-recycle/.claude/ is staged into the patrol
# agents' work dirs, where a test file would ship to production sessions.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/../.."
HOOK="$REPO/overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
eq()  { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3" "got '$1', want '$2'"; fi; }

[ -s "$HOOK" ] || { echo "FATAL: missing hook script: $HOOK" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git required" >&2; exit 1; }

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/gctk-cycle-recycle-hook-test.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# The gc stub logs every call, so a recycle reads as handoff, then session reset.
mkdir -p "$SANDBOX/home/go/bin"
cat > "$SANDBOX/home/go/bin/gc" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GC_LOG"
STUB
chmod +x "$SANDBOX/home/go/bin/gc"

# The newest usage entry totals 251100 tokens, over the hook's 200K threshold.
TRANSCRIPT="$SANDBOX/session-1.jsonl"
printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":250000,"cache_creation_input_tokens":1000}}}' > "$TRANSCRIPT"
RECYCLED_CALLS="handoff context cycle: context reached 251100 tokens
session reset refinery-1"

# new_repo <dir> — one commit tracking a README and the bead store's files
# under .beads/, as a repo that commits them does.
new_repo() {
    mkdir -p "$1/.beads"
    git -C "$1" init -q
    printf 'readme\n' > "$1/README.md"
    printf 'issue_prefix: tk\n' > "$1/.beads/config.yaml"
    printf '{}\n' > "$1/.beads/metadata.json"
    git -C "$1" add -A
    git -C "$1" -c user.email=t@example.com -c user.name=Tester -c commit.gpgsign=false commit -qm init
}
# reset_repo <dir> — back to the commit: no changes, no git-op markers.
reset_repo() {
    local gd
    gd=$(git -C "$1" rev-parse --absolute-git-dir)
    rm -rf "${gd:?}/rebase-merge" "${gd:?}/rebase-apply"
    rm -f "${gd:?}/MERGE_HEAD" "${gd:?}/CHERRY_PICK_HEAD" "${gd:?}/REVERT_HEAD"
    git -C "$1" reset -q --hard
    git -C "$1" clean -qfd
}
dirty() { printf 'changed\n' >> "$1"; }

WT="$SANDBOX/refinery"   # the refinery's own worktree, its working directory
RIG="$SANDBOX/rig"       # the rig's canonical checkout, GC_RIG_ROOT
new_repo "$WT"; new_repo "$RIG"

# run_hook <cwd> [agent] — the shipped hook at the end of a turn over its
# threshold, as the hook wiring runs it. Sets RC, OUT, ERR and CALLS.
run_hook() {
    : > "$SANDBOX/gc.log"
    ( cd "$1" && printf '{"transcript_path":"%s"}' "$TRANSCRIPT" \
        | env -i PATH="$PATH" HOME="$SANDBOX/home" GC_LOG="$SANDBOX/gc.log" \
            GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
            GC_AGENT="${2:-alpha/gc-toolkit.refinery}" GC_RIG_ROOT="$RIG" \
            GC_CITY_PATH="$SANDBOX/city" GC_SESSION_ID=refinery-1 \
            sh "$HOOK" >"$SANDBOX/out" 2>"$SANDBOX/err" )
    RC=$?
    OUT=$(cat "$SANDBOX/out"); ERR=$(cat "$SANDBOX/err"); CALLS=$(cat "$SANDBOX/gc.log")
}
# verdict — what the last run did: recycled, deferred by the git-op guard
# (with gc never called), or neither, which names what happened instead.
verdict() {
    if [ "$CALLS" = "$RECYCLED_CALLS" ]; then
        echo recycled
    elif [ -z "$CALLS" ] && case "$ERR" in *"refinery mid git-op"*) true ;; *) false ;; esac; then
        echo deferred
    else
        echo "neither, gc calls [$CALLS], stderr [$ERR]"
    fi
}
# expect <verdict> <cwd> <label> [agent] — run the hook and assert its verdict
# and the invariants it keeps on every path: exit 0, and nothing on stdout.
expect() {
    run_hook "$2" "${4:-}"
    eq "$(verdict)" "$1" "$3"
    eq "$RC" "0" "$3: exits 0"
    eq "$OUT" "" "$3: prints nothing on stdout"
}

echo "cycle-recycle hook: the refinery git-op defer guard"

# --- 1. control: a clean refinery over its threshold recycles ---------------
expect recycled "$WT" "a clean worktree and rig checkout: the refinery recycles"

# --- 2. a dirty tracked file defers, in either tree ---------------------------
dirty "$WT/README.md"
expect deferred "$WT" "a dirty tracked file in the refinery's worktree defers"
reset_repo "$WT"

dirty "$RIG/README.md"
expect deferred "$WT" "a dirty tracked file in the rig checkout defers"
reset_repo "$RIG"

dirty "$RIG/README.md"; git -C "$RIG" add README.md
expect deferred "$WT" "a staged change defers"
reset_repo "$RIG"

mkdir -p "$WT/sub/deep"
dirty "$WT/README.md"
expect deferred "$WT/sub/deep" "run from a subdirectory, a dirty file at the top still defers"
reset_repo "$WT"

# --- 3. the bead store's tracked files count like any other -------------------
dirty "$WT/.beads/config.yaml"
expect deferred "$WT" "a dirty .beads/config.yaml in the refinery's worktree defers"
reset_repo "$WT"

dirty "$RIG/.beads/config.yaml"
expect deferred "$WT" "a dirty .beads/config.yaml in the rig checkout defers"
reset_repo "$RIG"

dirty "$WT/.beads/metadata.json"; git -C "$WT" add .beads/metadata.json
expect deferred "$WT" "a staged change under .beads/ defers"
reset_repo "$WT"

# --- 4. a git op in progress defers on a clean tree ---------------------------
for marker in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    gd=$(git -C "$WT" rev-parse --absolute-git-dir)
    case "$marker" in rebase-*) mkdir -p "$gd/$marker" ;; *) git -C "$WT" rev-parse HEAD > "$gd/$marker" ;; esac
    expect deferred "$WT" "$marker in progress defers, with no file dirty"
    reset_repo "$WT"
done

gd=$(git -C "$RIG" rev-parse --absolute-git-dir)
git -C "$RIG" rev-parse HEAD > "$gd/MERGE_HEAD"
expect deferred "$WT" "a merge in progress in the rig checkout defers"
reset_repo "$RIG"

# --- 5. what the guard leaves out --------------------------------------------
printf 'scratch\n' > "$WT/scratch.tmp"
expect recycled "$WT" "an untracked file is scratch, not a git op"
reset_repo "$WT"

dirty "$WT/README.md"
expect recycled "$WT" "the guard is the refinery's alone: a witness with a dirty tree recycles" alpha/gc-toolkit.witness
reset_repo "$WT"

echo "cycle-recycle-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
