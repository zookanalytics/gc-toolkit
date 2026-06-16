#!/bin/sh
# gc-context-size.sh — report a bead-host's live context fill, model window,
# and recycle-band state, read from the host's OWN Claude transcript tail.
#
# Usage:
#   gc-context-size.sh [--json]
#
# Output (default — one line of key=value fields):
#   fill=<int> window=<int> pct=<int> soft=<int> edge=<int> band=<state> fill_h=<~Nk>
# With --json, the same fields as a single JSON object.
#
# band states:
#   below   — fill under the soft band; the host says nothing about recycling
#   offer   — fill in [soft, edge); the host offers a recycle gently (one line)
#   edge    — fill at/above edge (~0.80×window); the host offers firmly
#   unknown — transcript unreadable (no file yet); the caller skips silently
#
# Context source is the transcript tail, NOT the supervisor API (GC_API_URL is
# not exported to agents, so that call collapses to a 404). Live fill = input +
# both cache tiers on the last usage-bearing line. Window is 1,000,000 when the
# transcript's harness-injected model id carries the `[1m]` suffix — `.message.
# model` records only the bare family and drops the suffix (verified live), so
# the file is also scanned for the exact id, anchored to `claude-…[1m]` so a
# bare `[1m]` token in a skill listing can't false-match. Otherwise a 200K
# fail-safe: a missed 1M only offers early, and the PreCompact hook still nets
# the hard compaction edge.
#
# Tunables (env vars):
#   GC_CTX_SOFT_FRAC   — soft-band fraction of the window, in percent (default 55)
#   GC_CTX_SOFT_FLOOR  — soft-band floor in tokens (default 120000)
#   GC_CTX_EDGE_FRAC   — edge fraction of the window, in percent (default 80)

set -eu

JSON=0
[ "${1:-}" = "--json" ] && JSON=1

emit() {  # emit <fill> <window> <soft> <edge> <band>
  _fill=$1 _win=$2 _soft=$3 _edge=$4 _band=$5
  _pct=0
  [ "$_win" -gt 0 ] && _pct=$(( _fill * 100 / _win ))
  _fh="$(( _fill / 1000 ))k"
  if [ "$JSON" -eq 1 ]; then
    printf '{"fill":%d,"window":%d,"pct":%d,"soft":%d,"edge":%d,"band":"%s","fill_h":"%s"}\n' \
      "$_fill" "$_win" "$_pct" "$_soft" "$_edge" "$_band" "$_fh"
  else
    printf 'fill=%d window=%d pct=%d soft=%d edge=%d band=%s fill_h=%s\n' \
      "$_fill" "$_win" "$_pct" "$_soft" "$_edge" "$_band" "$_fh"
  fi
}

# Locate this host's transcript: project slug (pwd with / and . → -) + the
# Claude provider session UUID. Fall back to the newest *.jsonl if the id is
# unset (rare). Using $GC_SESSION_ID instead would find nothing — it is the gc
# id, not the provider's filename.
SLUG=$(pwd | sed 's:[/.]:-:g')
DIR="$HOME/.claude/projects/$SLUG"
JSONL="$DIR/${CLAUDE_CODE_SESSION_ID:-}.jsonl"
if [ ! -f "$JSONL" ]; then
  # shellcheck disable=SC2012  # mtime ordering; filenames are session UUIDs (no spaces)
  JSONL=$(ls -t "$DIR"/*.jsonl 2>/dev/null | head -1 || true)
fi
if [ -z "${JSONL:-}" ] || [ ! -f "$JSONL" ]; then
  emit 0 200000 0 0 unknown
  exit 0
fi

# Live fill: input + both cache tiers on the last usage-bearing line.
FILL=$(grep '"usage"' "$JSONL" 2>/dev/null | tail -1 \
  | jq '[.message.usage.input_tokens,
         .message.usage.cache_read_input_tokens,
         .message.usage.cache_creation_input_tokens] | add // 0' 2>/dev/null || echo 0)
[ -n "$FILL" ] || FILL=0
case "$FILL" in *[!0-9]*) FILL=0 ;; esac

# Window from the transcript's own model id (no GC_MODEL env). The bare-family
# record drops the [1m] suffix, so scan the file for the harness-injected id.
MODEL=$(grep '"model"' "$JSONL" 2>/dev/null | tail -1 | jq -r '.message.model // .model // empty' 2>/dev/null || true)
if printf '%s' "$MODEL" | grep -qiE '\[1m\]|gemini' \
   || grep -qE 'claude-[a-z0-9.-]+\[1m\]' "$JSONL" 2>/dev/null; then
  WINDOW=1000000
else
  WINDOW=200000
fi

# Bands — window-relative so one policy holds on a 200K and a 1M host.
SOFT=$(( WINDOW * ${GC_CTX_SOFT_FRAC:-55} / 100 ))
FLOOR=${GC_CTX_SOFT_FLOOR:-120000}
[ "$SOFT" -lt "$FLOOR" ] && SOFT=$FLOOR
EDGE=$(( WINDOW * ${GC_CTX_EDGE_FRAC:-80} / 100 ))

if [ "$FILL" -ge "$EDGE" ]; then
  BAND=edge
elif [ "$FILL" -ge "$SOFT" ]; then
  BAND=offer
else
  BAND=below
fi

emit "$FILL" "$WINDOW" "$SOFT" "$EDGE" "$BAND"
