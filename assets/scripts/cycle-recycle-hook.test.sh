#!/usr/bin/env bash
# cycle-recycle-hook.test.sh — hermetic test for the shipped hook
# overlays/cycle-recycle/.claude/hooks/cycle-recycle.sh: the refinery git-op
# defer guard, and the drift trigger.
#
# Over its threshold the hook recycles a refinery (gc handoff, then gc session
# reset) unless a git op is in flight in the refinery's working directory or in
# the rig's canonical checkout (GC_RIG_ROOT). A git-op marker counts, and so
# does a dirty tracked file anywhere in either tree, the bead store's files
# under .beads/ included. The hook exits 0 with an empty stdout either way, so
# from outside a guard that defers every turn looks like a hook with nothing to
# do. This test tells the two apart.
#
# The hook also recycles a session when a pack file its prompt or patrol
# formula comes from changed on disk after the session's first prompt, at a
# turn's end and, under --prompt, before a prompt, which it then blocks.
# The drift cases age real files and read a transcript whose first record
# carries the session's start.
#
# It runs the SHIPPED script, never a copy, against real git repos. gc and tmux
# are stubbed by pointing HOME at the sandbox: the hook prepends "$HOME/go/bin"
# to PATH itself, so a stub placed there wins over the real one. Every run
# starts from env -i, so no live GC_* variable reaches the hook.
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
# GC_HANDOFF_RC and GC_RESET_RC make those calls fail. The tmux stub answers the
# hook's attachment query with TMUX_ATTACHED.
mkdir -p "$SANDBOX/home/go/bin"
cat > "$SANDBOX/home/go/bin/gc" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GC_LOG"
case "$1 $2" in
  "session reset") exit "${GC_RESET_RC:-0}" ;;
  handoff*) exit "${GC_HANDOFF_RC:-0}" ;;
esac
exit 0
STUB
cat > "$SANDBOX/home/go/bin/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "${TMUX_ATTACHED:-0}"
STUB
chmod +x "$SANDBOX/home/go/bin/gc" "$SANDBOX/home/go/bin/tmux"

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

echo "cycle-recycle hook: pack drift"

# The pack a city imports from its rigs/gc-toolkit checkout. GC_RIG_ROOT is the
# rig checkout above, which carries no patrol formula, so the hook reads this
# one. Every file starts two hours old, the ones the hook watches and the ones
# it does not: hook settings reach a live session through Claude Code's
# settings watcher, so a change to them is no drift.
PACK="$SANDBOX/city/rigs/gc-toolkit"
WATCHED="agents/refinery/prompt.template.md agents/deacon/prompt.template.md
formulas/mol-refinery-patrol.toml formulas/mol-deacon-patrol.toml
template-fragments/visit-close.template.md template-fragments/scratch-reclaim.template.md"
UNWATCHED="docs/notes.md overlays/cycle-recycle/.claude/settings.json"
epoch_stamp() { date -d "@$1" '+%Y%m%d%H%M.%S' 2>/dev/null || date -r "$1" '+%Y%m%d%H%M.%S'; }
# age <file> <seconds ago> — a negative age stamps the file in the future.
age() { touch -t "$(epoch_stamp "$(($(date +%s) - $2))")" "$1"; }
age_pack() { local f; for f in $WATCHED $UNWATCHED; do age "$PACK/$f" 7200; done; }
for f in $WATCHED $UNWATCHED; do mkdir -p "$(dirname "$PACK/$f")"; printf 'text\n' > "$PACK/$f"; done
age_pack

# The session's first prompt was an hour ago, under the context threshold. The
# records before it carry no timestamp, as a Claude transcript's first lines do.
DRIFT_T="$SANDBOX/drift-session.jsonl"
{
    printf '%s\n' '{"type":"last-prompt","sessionId":"drift-session"}' '{"type":"mode","mode":"normal"}'
    jq -nc --arg ts "$(jq -nr --argjson t "$(($(date +%s) - 3600))" '$t | todate' | sed 's/Z$/.157Z/')" \
        '{type: "user", timestamp: $ts, message: {content: "startup prompt"}}'
    printf '%s\n' '{"type":"assistant","message":{"usage":{"input_tokens":100,"cache_read_input_tokens":1000,"cache_creation_input_tokens":10}}}'
} > "$DRIFT_T"
NOSTART_T="$SANDBOX/no-start.jsonl"
printf '%s\n' '{"type":"last-prompt","sessionId":"no-start"}' > "$NOSTART_T"
PROMPT_TEXT="Run gc prime to check merge queue and begin processing."

# run_drift [hook args] — the shipped hook as DRIFT_AGENT (the alpha refinery
# unless set), run from the clean worktree, its payload naming DRIFT_TRANSCRIPT
# (DRIFT_T unless set) and carrying PROMPT_TEXT. TMUX_UNDER_TEST, TMUX_ATTACHED,
# GC_HANDOFF_RC and GC_RESET_RC reach it when set. Sets RC, OUT, ERR and CALLS.
run_drift() {
    : > "$SANDBOX/gc.log"
    ( cd "$WT" && jq -nc --arg t "${DRIFT_TRANSCRIPT:-$DRIFT_T}" --arg p "$PROMPT_TEXT" '{transcript_path: $t, prompt: $p}' \
        | env -i PATH="$PATH" HOME="$SANDBOX/home" GC_LOG="$SANDBOX/gc.log" \
            GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
            GC_AGENT="${DRIFT_AGENT-alpha/gc-toolkit.refinery}" GC_RIG_ROOT="${DRIFT_RIG_ROOT:-$RIG}" \
            GC_CITY_PATH="$SANDBOX/city" GC_SESSION_ID=session-1 \
            ${TMUX_UNDER_TEST:+TMUX="$TMUX_UNDER_TEST"} TMUX_ATTACHED="${TMUX_ATTACHED:-0}" \
            GC_HANDOFF_RC="${GC_HANDOFF_RC:-0}" GC_RESET_RC="${GC_RESET_RC:-0}" \
            sh "$HOOK" "$@" >"$SANDBOX/out" 2>"$SANDBOX/err" )
    RC=$?
    OUT=$(cat "$SANDBOX/out"); ERR=$(cat "$SANDBOX/err"); CALLS=$(cat "$SANDBOX/gc.log")
}
# drift_verdict — "recycled" when the hook sent the drift handoff and then
# reset the session, "none" when it called no gc, else what it did instead.
drift_verdict() {
    case "$CALLS" in
        "") echo none ;;
        "handoff pack drift: "*"
session reset session-1") echo recycled ;;
        *) echo "neither, gc calls [$CALLS], stderr [$ERR]" ;;
    esac
}
blocked() { printf '%s' "$OUT" | jq -r 'select(.decision == "block") | "block"' 2>/dev/null; }

# --- 6. no watched file changed: nothing recycles ------------------------------
for f in $UNWATCHED; do age "$PACK/$f" 60; done
run_drift
eq "$(drift_verdict)" "none" "a change to the docs or the hook settings recycles nothing"
eq "$OUT" "" "and prints nothing"
run_drift --prompt
eq "$(drift_verdict)" "none" "before a prompt, no drift lets the prompt through"
eq "$OUT" "" "with no block decision"
age_pack

# --- 7. a watched file changed after the first prompt: the turn's end recycles -
for f in agents/refinery/prompt.template.md formulas/mol-refinery-patrol.toml \
         template-fragments/visit-close.template.md; do
    age "$PACK/$f" 60
    run_drift
    eq "$(drift_verdict)" "recycled" "a turn's end recycles when $f changed"
    has_file=$(case "$CALLS" in *"$f"*) echo yes ;; *) echo no ;; esac)
    eq "$has_file" "yes" "the handoff names $f"
    eq "$OUT$RC" "0" "the turn-end recycle prints nothing and exits 0"
    age_pack
done

# --- 8. before a prompt: recycle, carry the prompt, then block it ---------------
age "$PACK/formulas/mol-refinery-patrol.toml" 60
run_drift --prompt
eq "$(drift_verdict)" "recycled" "a drifted session recycles before the prompt reaches it"
eq "$(blocked)" "block" "and blocks the prompt"
eq "$RC" "0" "the prompt-time recycle exits 0"
carried=$(case "$CALLS" in *"$PROMPT_TEXT"*) echo yes ;; *) echo no ;; esac)
eq "$carried" "yes" "the handoff carries the blocked prompt"

GC_RESET_RC=1 run_drift --prompt
eq "$(drift_verdict)" "recycled" "a failed reset still sends the handoff"
eq "$OUT" "" "but the prompt goes through, since no restart backs a block"

GC_HANDOFF_RC=1 run_drift --prompt
eq "$(drift_verdict)" "recycled" "a failed handoff still requests the reset"
eq "$(blocked)" "block" "and still blocks, since the requested restart would end the turn mid-command"
reason=$(printf '%s' "$OUT" | jq -r '.reason // empty' 2>/dev/null)
says=$(case "$reason" in *"failed to send"*) echo yes ;; *) echo no ;; esac)
eq "$says" "yes" "the block reason says the prompt was not carried"

TMUX_UNDER_TEST=/tmp/tmux-test,1,0 TMUX_ATTACHED=1 run_drift --prompt
eq "$(drift_verdict)" "none" "with an operator attached the recycle defers"
eq "$OUT" "" "and the prompt goes through"
attached=$(case "$ERR" in *"attached"*) echo yes ;; *) echo no ;; esac)
eq "$attached" "yes" "the deferral names the attachment"

dirty "$WT/README.md"
run_drift --prompt
eq "$(drift_verdict)" "none" "a refinery mid git-op defers the drift recycle too"
eq "$OUT" "" "and lets the prompt through"
reset_repo "$WT"
age_pack

# --- 9. what counts as no drift -------------------------------------------------
age "$PACK/formulas/mol-refinery-patrol.toml" -86400
run_drift
eq "$(drift_verdict)" "none" "an mtime later than now is no evidence of a change"
age_pack

age "$PACK/formulas/mol-refinery-patrol.toml" 60
DRIFT_TRANSCRIPT="$NOSTART_T" run_drift
eq "$(drift_verdict)" "none" "a transcript with no timestamped record has no start to compare"
DRIFT_AGENT=gc-toolkit.deacon run_drift
eq "$(drift_verdict)" "none" "the refinery's formula is not the deacon's: a deacon does not recycle"
DRIFT_AGENT=alpha/gc-toolkit.polecat-1 run_drift
eq "$(drift_verdict)" "none" "a polecat is never recycled"
# A rig checkout that is itself the pack is read before the city's copy.
RIGPACK="$SANDBOX/rigpack"
mkdir -p "$RIGPACK/formulas"; printf 'text\n' > "$RIGPACK/formulas/mol-refinery-patrol.toml"
age "$RIGPACK/formulas/mol-refinery-patrol.toml" 7200
DRIFT_RIG_ROOT="$RIGPACK" run_drift
eq "$(drift_verdict)" "none" "a GC_RIG_ROOT that carries the formula is the pack read, not the city's"
age "$RIGPACK/formulas/mol-refinery-patrol.toml" 60
DRIFT_RIG_ROOT="$RIGPACK" run_drift
eq "$(drift_verdict)" "recycled" "and a change there recycles"
age_pack

age "$PACK/formulas/mol-deacon-patrol.toml" 60
DRIFT_AGENT=gc-toolkit.deacon run_drift
eq "$(drift_verdict)" "recycled" "the deacon recycles when its own formula changed"
age_pack

# --- 10. the context check stays at a turn's end --------------------------------
DRIFT_TRANSCRIPT="$TRANSCRIPT" run_drift --prompt
eq "$(drift_verdict)" "none" "before a prompt, a context over the threshold does not recycle"
eq "$OUT" "" "and blocks nothing"

# --- 11. --drift <role> prints what it finds and acts on nothing ----------------
age "$PACK/formulas/mol-refinery-patrol.toml" 60
age "$PACK/template-fragments/scratch-reclaim.template.md" 60
DRIFT_AGENT="" run_drift --drift refinery
eq "$OUT" "formulas/mol-refinery-patrol.toml
template-fragments/scratch-reclaim.template.md" "--drift prints each changed file, with GC_AGENT empty"
eq "$CALLS" "" "--drift calls no gc"
DRIFT_AGENT="" run_drift --drift polecat
eq "$OUT" "" "--drift reads no role but a patrol role's"
age_pack

echo "cycle-recycle-hook: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
