#!/bin/sh
# cycle-recycle.sh — deterministic proactive context recycle for patrol agents.
#
# Runs as a Claude Code `Stop` hook (fires at the end of every turn). Because
# the harness runs the hook regardless of LLM state, the recycle is genuinely
# enforced — unlike the soft "Apply cycle-recycle" prose that used to live in
# the patrol formulas, which degraded exactly as context filled (the bug this
# fixes, tk-g8pfg: the fuller the context, the less reliably the model ran the
# end-of-wisp check, so context climbed and the check was skipped harder).
#
# Self-gates to the three long-running patrol roles (witness, deacon, refinery)
# and no-ops for every other agent (ephemeral polecats, bead-hosts, mayor,
# mechanik) so a focused worker is never recycled mid-task.
#
# When the agent's measured input_tokens crosses 200K — an absolute
# work-product threshold (= 20% of a 1M window; a 200K-window agent would fire
# at its own compaction edge), see template-fragments/cycle-recycle.template.md
# for the full rationale — it writes a durable HANDOFF mail (`gc handoff`) and
# triggers a restart (`gc session reset`).
#
# pour-next-before-burn on the hook path: a generic Stop hook fires at a turn
# boundary that may be mid-wisp and cannot reliably reconstruct the patrol
# formula's pour vars (binding_prefix, target_branch, rig_name,
# default_merge_strategy) — those live in the agent's own prompt, not in env.
# So the inheriting session re-establishes its wisp via its Tier-2/3
# startup-adopt path (the acceptance-named resume mechanism), which pours/adopts
# with the correct vars. The trigger token count is carried in the HANDOFF body
# so the new session has context before it re-derives its wisp.
#
# Invariants:
#   * NEVER prompt the operator (heartbeat-no-consent-ui): the threshold IS the
#     directive. No AskUserQuestion / consent UI at the boundary.
#   * ALWAYS exit 0 so the Stop event is never blocked, and keep stdout empty
#     (all diagnostics to stderr) so Claude never parses a stray block decision.
#   * Under threshold is the common path and must stay cheap: one bounded curl.
#   * Over threshold, DEFER (never force) the recycle while an operator is
#     attached or the refinery is mid git-op; uncertain -> skip. PreCompact
#     stays the net for any deferred turn.
#
# If the supervisor API is unreachable or input_tokens is unknown, the check
# skips silently — Claude's PreCompact hook remains the reactive safety net at
# the model's own compaction edge. No fallback heuristic.

set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

# --- 1. Self-gate: patrol roles only -------------------------------------
AGENT="${GC_AGENT:-}"
[ -n "$AGENT" ] || exit 0
base="${AGENT##*/}"   # "gc-toolkit/gc-toolkit.witness" -> "gc-toolkit.witness"; "deacon" -> "deacon"
role="${base##*.}"    # "gc-toolkit.witness" -> "witness"; "deacon" -> "deacon"
case "$role" in
  witness | deacon | refinery) : ;;
  *) exit 0 ;; # not a patrol agent — no-op, never interrupt focused work
esac

# --- 2. Measure context: input_tokens from the supervisor API ------------
API_URL="${GC_API_URL:-http://127.0.0.1:8372}"
CITY="$(gc cities --json 2>/dev/null | jq -r --arg p "${GC_CITY:-}" '.cities[] | select(.path == $p) | .name' 2>/dev/null)"
[ -n "$CITY" ] || exit 0 # cannot resolve city name -> skip (PreCompact stays the net)

TOKENS="$(curl -sf --max-time 3 "$API_URL/v0/city/$CITY/agent/$AGENT" 2>/dev/null | jq -r '.input_tokens // 0' 2>/dev/null || echo 0)"
case "$TOKENS" in
  '' | *[!0-9]*) exit 0 ;; # empty / null / non-numeric -> unknown, skip silently
esac
[ "$TOKENS" -ge 200000 ] || exit 0 # under threshold -> cheap no-op (the common path)

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
echo "cycle-recycle: $AGENT at input_tokens=$TOKENS (>=200000) — handoff + reset" >&2

# `gc handoff` (non-auto) writes the durable HANDOFF mail AND stops the runtime
# for controller-restartable classes; for on-demand named patrol sessions it
# only writes mail and returns. Non-auto is required so controller-restartable
# patrols actually recycle — `--auto` would mail-only and never restart them.
if ! gc handoff "context cycle: input_tokens reached $TOKENS" >&2; then
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
