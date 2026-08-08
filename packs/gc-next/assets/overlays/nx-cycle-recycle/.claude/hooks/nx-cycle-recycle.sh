#!/bin/sh
# nx-cycle-recycle.sh — deterministic context recycle for the converse role.
#
# The gc-next descendant of the live pack's cycle-recycle Stop hook
# (tk-g8pfg: prose-based recycling degrades exactly as context fills, so
# the harness enforces it). Two deliberate changes from the source, per the
# census (spec §7):
#
#   GATE    re-keyed from `witness|deacon|refinery` to `converse` — the
#           patrol roles are disposable cycles in gc-next and never
#           accumulate context; the one long-holding role is a converse
#           session mid-hold.
#   ACTION  record-then-drain, not handoff-mail + `gc session reset` — a
#           pool session has no singleton identity to reset into. Over
#           threshold, the hook nudges the role (via a marker file the
#           prompt honors) to write the outcome-so-far to the SUBJECT
#           bead, close the turn honestly, and drain; turn boundaries are
#           the release valve (tk-h9pq5).
#
# Invariants carried verbatim from the source:
#   * NEVER prompt the operator; the threshold IS the directive.
#   * ALWAYS exit 0; stdout stays empty (diagnostics to stderr).
#   * Under threshold stays cheap: one bounded curl.
#   * Over threshold, DEFER while an operator is attached; uncertain -> skip.
#     PreCompact remains the reactive net.
set -u
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"

# --- 1. Self-gate: the converse role only --------------------------------
AGENT="${GC_AGENT:-}"
[ -n "$AGENT" ] || exit 0
base="${AGENT##*/}"
role="${base##*.}"
case "$role" in
  converse | converse-*) : ;;
  *) exit 0 ;;
esac

THRESHOLD="${GC_NX_RECYCLE_TOKENS:-200000}"

# --- 2. Measure context (the source hook's supervisor probe, verbatim
# shape: resolve the city name, then the per-agent endpoint) --------------
API_URL="${GC_API_URL:-http://127.0.0.1:8372}"
SESSION="${GC_SESSION_NAME:-}"
[ -n "$SESSION" ] || exit 0
CITY="$(gc cities --json 2>/dev/null | jq -r --arg p "${GC_CITY:-}" '.cities[] | select(.path == $p) | .name' 2>/dev/null)"
[ -n "$CITY" ] || exit 0              # cannot resolve city -> skip; PreCompact is the net
TOKENS=$(curl -fsS --max-time 5 "$API_URL/v0/city/$CITY/agent/$AGENT" 2>/dev/null \
  | jq -r '.input_tokens // empty' 2>/dev/null) || TOKENS=""
[ -n "$TOKENS" ] || exit 0            # unknown -> skip; PreCompact is the net
[ "$TOKENS" -ge "$THRESHOLD" ] 2>/dev/null || exit 0

# --- 3. Defer while an operator is attached (uncertain -> DEFER, the
# source invariant: only a probe that definitely says "no clients"
# proceeds) ---------------------------------------------------------------
if ! CLIENTS=$(tmux list-clients -t "$SESSION" 2>/dev/null); then
  echo "nx-cycle-recycle: over threshold ($TOKENS) but attachment unknown; deferring" >&2
  exit 0
fi
ATTACHED=$(printf '%s' "$CLIENTS" | grep -c . || true)
if [ "${ATTACHED:-0}" -gt 0 ]; then
  echo "nx-cycle-recycle: over threshold ($TOKENS) but operator attached; deferring" >&2
  exit 0
fi

# --- 4. Record-then-drain directive --------------------------------------
# The Stop hook cannot write the subject-bead outcome itself (only the
# role knows what to record). It leaves the directive where the converse
# prompt checks at every turn start, and stderr says so.
MARKER="${GC_DIR:-${CLAUDE_PROJECT_DIR:-.}}/.nx-recycle-now"
printf 'tokens=%s threshold=%s\n' "$TOKENS" "$THRESHOLD" > "$MARKER" 2>/dev/null || true
echo "nx-cycle-recycle: $TOKENS >= $THRESHOLD — record-then-drain directive set for $SESSION" >&2
exit 0
