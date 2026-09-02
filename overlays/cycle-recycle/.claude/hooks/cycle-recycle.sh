#!/bin/sh
# cycle-recycle.sh — deterministic proactive context recycle for patrol agents.
# Runs as a Claude Code `Stop` hook (every turn boundary), so the recycle is
# enforced regardless of LLM state. Self-gates to witness | deacon | refinery;
# no-ops for everyone else. Over an absolute 200K context threshold (measured
# from the session transcript named on hook stdin) it writes a durable HANDOFF
# (`gc handoff`) and triggers a restart (`gc session reset`); the inheriting
# session re-adopts its wisp via its startup reconcile. Policy:
# docs/cycle-recycle.md.
#
# Invariants:
#   * NEVER prompt the operator (heartbeat-no-consent-ui).
#   * ALWAYS exit 0; stdout stays empty (diagnostics to stderr), except under
#     `--measure`, which prints the measurement and acts on nothing.
#   * Under threshold (the common path) stays cheap: one bounded transcript
#     tail, no network.
#   * Over threshold, DEFER while an operator is attached or the refinery is
#     mid git-op; uncertain -> skip. PreCompact stays the reactive net, as it
#     is when the transcript is unreadable or carries no usage entry.

set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

TAIL_BYTES=2097152   # newest 2MiB of the transcript holds the latest usage entry
THRESHOLD=200000

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

# transcript_from_stdin — the `transcript_path` the provider hands every hook.
transcript_from_stdin() {
    [ -t 0 ] && return 0   # no hook payload (invoked by hand) -> measure nothing
    t=$(cat 2>/dev/null | jq -r '.transcript_path // empty' 2>/dev/null)
    [ -n "$t" ] && [ -r "$t" ] && printf '%s' "$t"
}

# `--measure` prints the context size this hook would compare against its
# threshold and exits, acting on nothing. It is how doctor/check-recycle-capable
# asserts the measurement against the shipped script rather than a copy of it.
if [ "${1:-}" = --measure ]; then
    T=$(transcript_from_stdin)
    [ -n "$T" ] && measure_context "$T"
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

# --- 2. Measure context: the transcript named on hook stdin ---------------
# Reading the session's own transcript keeps the measurement local to the turn
# that triggered the hook. Nothing outside the session has to publish a context
# size for the recycle to work.
TRANSCRIPT="$(transcript_from_stdin)"
[ -n "$TRANSCRIPT" ] || exit 0 # no readable transcript -> skip (PreCompact stays the net)

TOKENS="$(measure_context "$TRANSCRIPT")"
case "$TOKENS" in
  '' | *[!0-9]*) exit 0 ;; # no usage entry / unreadable -> unknown, skip silently
esac
[ "$TOKENS" -ge "$THRESHOLD" ] || exit 0 # under threshold -> cheap no-op (the common path)

# --- 2.5. Safety guards: defer (don't force) the recycle at a bad moment --
# `gc session reset` preserves identity/alias/mail/queued work but resets the
# conversation, so don't land it (a) under an operator attached to watch/debug
# the pane, or (b) on the refinery mid git-op. These run only on the rare
# over-threshold path. Bias: uncertain -> SKIP (exit 0) — deferring only delays
# the recycle (the hook re-checks next turn; PreCompact stays the reactive net),
# whereas a mistimed restart interrupts an operator or a multi-turn merge.

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
# are ignored (mirrors the formula's rig ff-merge dirtiness check).
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

# --- 3. Over threshold: recycle (HANDOFF mail + restart) ------------------
echo "cycle-recycle: $AGENT at context=$TOKENS tokens (>=$THRESHOLD) — handoff + reset" >&2

# `gc handoff` (non-auto) writes the durable HANDOFF mail AND stops the runtime
# for controller-restartable classes; for on-demand named patrol sessions it
# only writes mail and returns. Non-auto is required so controller-restartable
# patrols actually recycle — `--auto` would mail-only and never restart them.
if ! gc handoff "context cycle: context reached $TOKENS tokens" >&2; then
  echo "cycle-recycle: gc handoff failed (non-fatal); reset still attempted" >&2
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
if [ -n "$RESET_TARGET" ]; then
  if ! gc session reset "$RESET_TARGET" >&2; then
    echo "cycle-recycle: gc session reset failed (non-fatal); controller will reconcile" >&2
  fi
fi

exit 0
