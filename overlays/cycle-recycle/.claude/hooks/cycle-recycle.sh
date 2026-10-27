#!/bin/sh
# cycle-recycle.sh — deterministic proactive recycle for patrol agents.
# Runs as a Claude Code `Stop` hook (every turn boundary) and, with --prompt, as
# a `UserPromptSubmit` hook (before a prompt starts a turn), so the recycle is
# enforced regardless of LLM state. Self-gates to witness | deacon | refinery;
# no-ops for everyone else. It recycles a session for either of two reasons,
# both read from the session transcript named on hook stdin:
#   * context: at a turn's end, the context is over an absolute 200K threshold;
#   * drift: a pack file the session's prompt or patrol formula comes from
#     changed on disk after the session's first prompt, so the session runs
#     text the pack no longer holds.
# A recycle writes a durable HANDOFF (`gc handoff`) and triggers a restart
# (`gc session reset`); the inheriting session re-adopts its wisp via its
# startup reconcile. Under --prompt only drift recycles, and once the restart
# is requested the hook blocks the prompt, which the HANDOFF carries instead.
# Policy: docs/cycle-recycle.md.
#
# Invariants:
#   * NEVER prompt the operator (heartbeat-no-consent-ui).
#   * ALWAYS exit 0; stdout stays empty (diagnostics to stderr), except for the
#     block decision under --prompt, and under `--measure` and `--drift`, which
#     print what they read and act on nothing.
#   * Nothing to recycle (the common path) stays cheap: two bounded transcript
#     reads, one stat over the watched pack files, no network.
#   * DEFER while an operator is attached or the refinery is mid git-op;
#     uncertain -> skip. PreCompact stays the reactive net, as it is when the
#     transcript is unreadable or carries no usage entry.

set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

TAIL_BYTES=2097152   # newest 2MiB of the transcript holds the latest usage entry
HEAD_LINES=200       # the transcript's first records hold its first prompt
THRESHOLD=200000
MODE="${1:-}"

# The payload the provider hands every hook on stdin; none when the hook runs
# by hand.
PAYLOAD=""
[ -t 0 ] || PAYLOAD=$(cat 2>/dev/null)

# measure_context <transcript-path> — print the session's live context size in
# tokens, or nothing when no usage entry is readable. The newest usage entry's
# prompt-side input + cache reads + cache writes IS the current context size;
# after a compaction the newest entry reads low again. Same quantity gascity
# injects on UserPromptSubmit (cmd/gc/context_inject.go), so the hook and the
# rest of the city measure the same thing. The `grep` prefilter keeps the
# common path off jq for the bulk of a transcript, and a first line the tail
# cut mid-record simply fails to parse and is skipped.
measure_context() {
    tail -c "$TAIL_BYTES" "$1" 2>/dev/null | grep '"usage"' | jq -Rrn '
        [ inputs
          | (try fromjson catch empty)
          | .message.usage // empty
          | ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
             + (.cache_creation_input_tokens // 0))
          | select(. > 0) ]
        | last // empty' 2>/dev/null
}

# transcript_path — the payload's `transcript_path`, when it names a readable
# file.
transcript_path() {
    t=$(printf '%s' "$PAYLOAD" | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -n "$t" ] && [ -r "$t" ] && printf '%s' "$t"
}

# session_start <transcript-path> — the epoch second of the transcript's first
# timestamped record, which is the session's first prompt, or nothing until a
# record carries a timestamp. Gas City renders that prompt at launch, seconds
# before the record.
session_start() {
    head -n "$HEAD_LINES" "$1" 2>/dev/null | jq -Rr '
        (try fromjson catch empty) | objects | .timestamp // empty | strings
        | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch empty)' 2>/dev/null | head -n 1
}

# pack_drift <transcript-path> <role> — print, one per line and relative to the
# pack, each watched file of <role> whose mtime is later than the session's
# first prompt: the role's prompt template and every fragment a prompt can
# include, which Gas City renders into the prompt at launch, and the role's
# patrol formula, whose steps the session reads as it reaches them and keeps. A
# fast-forward rewrites only the files whose content changed, so an mtime is
# when the new text reached the checkout. The pack is the first of GC_RIG_ROOT
# and the city's rigs/gc-toolkit that carries the role's formula. Prints nothing
# when no file changed, or when the start, the pack or the times cannot be read:
# uncertain -> no drift. An mtime later than now counts as no change, so a file
# stamped in the future cannot recycle a session on every turn.
pack_drift() {
    start=$(session_start "$1")
    case "$start" in '' | *[!0-9]*) return 0 ;; esac
    pack=""
    for c in "${GC_RIG_ROOT:-}" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
        [ -n "$c" ] && [ -f "$c/formulas/mol-$2-patrol.toml" ] && { pack="$c"; break; }
    done
    [ -n "$pack" ] || return 0
    now=$(date +%s)
    (
        cd "$pack" 2>/dev/null || exit 0
        set -- "agents/$2/prompt.template.md" "formulas/mol-$2-patrol.toml" template-fragments/*.template.md
        for f do
            shift
            [ -f "$f" ] && set -- "$@" "$f"
        done
        [ "$#" -gt 0 ] || exit 0
        # GNU stat first: BSD stat refuses -c and prints nothing, while GNU stat
        # reads -f as a file-system query and would print that instead.
        { stat -c '%Y %n' "$@" 2>/dev/null || stat -f '%m %N' "$@" 2>/dev/null; } \
            | awk -v s="$start" -v n="$now" '$1 ~ /^[0-9]+$/ && $1 > s && $1 <= n { sub(/^[0-9]+ /, ""); print }'
    )
}

# `--measure` prints the context size this hook would compare against its
# threshold and exits, acting on nothing. It is how doctor/check-recycle-capable
# asserts the measurement against the shipped script rather than a copy of it.
if [ "$MODE" = --measure ]; then
    T=$(transcript_path)
    [ -n "$T" ] && measure_context "$T"
    exit 0
fi

# `--drift <role>` prints the files the drift check finds changed for <role>
# and exits, acting on nothing. It takes the role as an argument rather than
# from GC_AGENT, so doctor/check-recycle-capable drives it with GC_AGENT empty,
# and a script predating it self-gates out instead of recycling the doctor.
if [ "$MODE" = --drift ]; then
    T=$(transcript_path)
    case "${2:-}" in
      witness | deacon | refinery) [ -n "$T" ] && pack_drift "$T" "$2" ;;
    esac
    exit 0
fi

# --- 1. Self-gate: patrol roles only -------------------------------------
AGENT="${GC_AGENT:-}"
[ -n "$AGENT" ] || exit 0
base="${AGENT##*/}"   # "gc-toolkit/gc-toolkit.witness" -> "gc-toolkit.witness"; "deacon" -> "deacon"
role="${base##*.}"    # "gc-toolkit.witness" -> "witness"; "deacon" -> "deacon"
case "$role" in
  witness | deacon | refinery) : ;;
  *) exit 0 ;; # not a patrol agent — no-op, never interrupt focused work
esac

# --- 2. Measure: the transcript named on hook stdin -----------------------
# Reading the session's own transcript keeps the measurement local to the turn
# that triggered the hook. Nothing outside the session has to publish a context
# size or a start time for the recycle to work.
TRANSCRIPT="$(transcript_path)"
[ -n "$TRANSCRIPT" ] || exit 0 # no readable transcript -> skip (PreCompact stays the net)

# The context check runs at a turn's end only: before a prompt, the context is
# what it was when the last turn ended. An unreadable or missing usage entry is
# unknown, which is no context recycle.
SUBJECT=""; BODY=""
if [ "$MODE" != --prompt ]; then
  TOKENS="$(measure_context "$TRANSCRIPT")"
  case "$TOKENS" in
    '' | *[!0-9]*) : ;;
    *) [ "$TOKENS" -ge "$THRESHOLD" ] && SUBJECT="context cycle: context reached $TOKENS tokens" ;;
  esac
fi
if [ -z "$SUBJECT" ]; then
  DRIFT="$(pack_drift "$TRANSCRIPT" "$role")"
  if [ -n "$DRIFT" ]; then
    SUBJECT="pack drift: text this session runs changed after it started"
    BODY="Changed on disk after this session's first prompt: $(printf '%s\n' "$DRIFT" | tr '\n' ' ' | sed 's/ $//')."
  fi
fi
[ -n "$SUBJECT" ] || exit 0 # nothing to recycle -> cheap no-op (the common path)

# --- 2.5. Safety guards: defer (don't force) the recycle at a bad moment --
# `gc session reset` preserves identity/alias/mail/queued work but resets the
# conversation, so don't land it (a) under an operator attached to watch/debug
# the pane, or (b) on the refinery mid git-op. These run only on the rare
# recycle path. Bias: uncertain -> SKIP (exit 0) — deferring only delays the
# recycle (the hook re-checks next turn; PreCompact stays the reactive net),
# whereas a mistimed restart interrupts an operator or a multi-turn merge. Under
# --prompt a deferral lets the prompt through.

# (a) Attached session (all patrol roles): defer while a tmux client is watching.
if [ -n "${TMUX:-}" ]; then
  attached="$(tmux display-message -p '#{session_attached}' 2>/dev/null || true)"
  case "$attached" in
    0) : ;; # no client attached -> safe to recycle
    '' | *[!0-9]*) # query failed / non-numeric -> uncertain -> defer
      echo "cycle-recycle: attachment state unknown; deferring recycle" >&2; exit 0 ;;
    *) # one or more clients attached -> defer
      echo "cycle-recycle: session attached ($attached client(s)); deferring recycle" >&2; exit 0 ;;
  esac
fi

# (b) Refinery mid git-op: defer while a rebase/merge is in flight or a tracked
# tree is dirty, in either the refinery's own worktree (CWD) or the rig's
# canonical checkout ($GC_RIG_ROOT). Witness/deacon are idle pollers with no
# long git ops, so this is refinery-only. Untracked files are normal scratch and
# are ignored. doctor/check-recycle-capable applies the same test to the rig's
# canonical checkout, and its suite runs this script to prove the two agree.
if [ "$role" = refinery ]; then
  _git_busy() { # $1=dir; exit 0 if a git op is in progress or the tree is dirty
    [ -n "$1" ] || return 1
    ( cd "$1" 2>/dev/null || exit 1
      git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 1
      gd="$(git rev-parse --git-dir 2>/dev/null)" || exit 1
      for m in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        [ -e "$gd/$m" ] && exit 0
      done
      [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] && exit 0
      exit 1 )
  }
  if _git_busy "$PWD" || _git_busy "${GC_RIG_ROOT:-}"; then
    echo "cycle-recycle: refinery mid git-op (rebase/merge or dirty tree); deferring recycle" >&2
    exit 0
  fi
fi

# --- 3. Recycle (HANDOFF mail + restart) ----------------------------------
echo "cycle-recycle: $AGENT: $SUBJECT${BODY:+ ($BODY)} — handoff + reset" >&2

# The prompt never reaches this session, so the HANDOFF carries it to the next.
if [ "$MODE" = --prompt ]; then
  PROMPT=$(printf '%s' "$PAYLOAD" | jq -r '.prompt // empty' 2>/dev/null)
  [ -z "$PROMPT" ] || BODY="$BODY

The session recycled before this prompt reached it:

$PROMPT"
fi

# `gc handoff` (non-auto) writes the durable HANDOFF mail AND stops the runtime
# for controller-restartable classes; for on-demand named patrol sessions it
# only writes mail and returns. Non-auto is required so controller-restartable
# patrols actually recycle — `--auto` would mail-only and never restart them.
HANDOFF_OK=1
if [ -n "$BODY" ]; then
  gc handoff "$SUBJECT" "$BODY" >&2
else
  gc handoff "$SUBJECT" >&2
fi || { HANDOFF_OK=""; echo "cycle-recycle: gc handoff failed (non-fatal); reset still attempted" >&2; }

# Reap this session's scratch now. The recycle abandons the tree whole — the
# inheriting session gets a new id and a new tree — so the retiring session
# reclaims its own at once, with the certainty the hourly horizon reaper can
# only estimate: that pass holds any session carrying a live process, and this
# one is still live, so it would decline the very tree the recycle is leaving.
# The reaper stays the backstop for sessions that end without recycling, so a
# miss here costs a delayed reclaim, never the recycle. The session id names
# both the transcript file and the scratch directory; take it from the
# transcript this hook already read, fall back to the exported id, and reap
# nothing if neither is a bare id. scratch-reap.sh resolves as its PreToolUse
# sibling does, and carries every deletion rail.
SID="$(basename "$TRANSCRIPT" .jsonl 2>/dev/null)"
case "$SID" in '' | *[!A-Za-z0-9-]*) SID="${CLAUDE_CODE_SESSION_ID:-}" ;; esac
case "$SID" in '' | *[!A-Za-z0-9-]*) SID="" ;; esac
if [ -n "$SID" ]; then
  REAP=""
  for C in "${GC_RIG_ROOT:-}" "${GC_CITY_PATH:-}/rigs/gc-toolkit"; do
    [ -x "$C/assets/scripts/scratch-reap.sh" ] && { REAP="$C/assets/scripts/scratch-reap.sh"; break; }
  done
  if [ -n "$REAP" ]; then
    "$REAP" --session "$SID" >&2 \
      || echo "cycle-recycle: scratch self-reap failed (non-fatal); the hourly reaper is the backstop" >&2
  else
    echo "cycle-recycle: scratch-reap.sh not found; leaving this session's scratch to the hourly reaper" >&2
  fi
fi

# `gc session reset` is the actual restart trigger for on-demand named sessions
# (a no-op for controller-restartable ones, which gc handoff already stopped),
# and it clears any tripped named-session respawn circuit breaker. Best-effort:
# on failure the controller's reconcile loop converges the restart anyway.
# Target precedence GC_ALIAS -> GC_SESSION_ID: the refinery legitimately runs
# with an empty GC_ALIAS (it uses GC_AGENT as its mailbox), so falling back to
# the session ID keeps reset working for it. Both forms are accepted by
# `gc session reset` (alias or session ID).
RESET_TARGET="${GC_ALIAS:-${GC_SESSION_ID:-}}"
RESET_OK=""
if [ -n "$RESET_TARGET" ]; then
  if gc session reset "$RESET_TARGET" >&2; then
    RESET_OK=1
  else
    echo "cycle-recycle: gc session reset failed (non-fatal); controller will reconcile" >&2
  fi
fi

# Under --prompt, block the prompt so the old text never acts on it, but only
# once the restart is requested: a blocked prompt with no restart behind it
# would leave the session idle on the old text, dropping each prompt it is sent.
# A failed handoff still blocks: the reset is already requested, and a turn let
# through would be killed mid-command when it lands. Claude Code writes a
# blocked prompt's text to the session's transcript.
if [ "$MODE" = --prompt ] && [ -n "$RESET_OK" ]; then
  CARRIED="its HANDOFF mail carries this prompt"
  [ -n "$HANDOFF_OK" ] || CARRIED="its HANDOFF mail failed to send, so this prompt is kept only in this session's transcript"
  jq -n --arg reason "cycle-recycle: $SUBJECT. The session restarts on the current text, and $CARRIED." \
    '{decision: "block", reason: $reason}'
fi

exit 0
