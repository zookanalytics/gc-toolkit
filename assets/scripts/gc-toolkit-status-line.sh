#!/bin/sh
# gc-toolkit-status-line.sh — tmux status-right helper for gc-toolkit agents.
#
# Usage: gc-toolkit-status-line.sh <agent-name>
#
# Replaces gastown's status-line.sh as the body of #(...) in status-right.
# Renders two composable slots followed by hook/mail counts:
#
#   [<title>] [<indicator>] | 🪝 N | 📬 M
#
# The agent name is intentionally NOT rendered here — it lives on the
# left side of the status bar (see tmux-status-line-override.sh, which
# also overrides status-left with a short-name form of $AGENT). When
# title, indicator, and both counts are all empty, this script emits
# nothing and tmux shows just " %H:%M".
#
# - <title>     : from `gc session list --json`. Hidden when title equals
#                 the agent name (the gascity default — no operator-set
#                 title yet). Cached in /tmp/gc-title-<slug> for
#                 TITLE_TTL seconds to avoid hammering Dolt every
#                 5-second tmux refresh.
# - <indicator> : verbatim contents of /tmp/gc-status-<slug>.indicator
#                 if the file exists. Any gc-toolkit script can write or
#                 clear this file; the next status refresh picks it up.
#                 Last-writer-wins. Writers MUST `rm -f` the file when
#                 their work completes (trap on EXIT is the safe pattern).
#
# Width budget: total output capped at BUDGET chars; truncate title
# first (with ellipsis), then indicator. Counts always render — they're
# the cheap, structural slots.
#
# Failure mode: every external call is wrapped so tmux never sees an
# error. The script always exits 0.

set -u

agent="${1:-}"
[ -z "$agent" ] && exit 0

# Filesystem-safe slug: replace path-/dot-bearing characters with `-`.
slug=$(printf '%s' "$agent" | sed 's|[./]|-|g')

TITLE_CACHE="/tmp/gc-title-${slug}"
# TTL: titles change rarely (operator-initiated, via /thread-title or
# gc session rename). gc hook + gc mail check already take 5-20s per
# refresh on a loaded Dolt server, so a too-short TTL is meaningless
# — the cache mtime is set when the previous run finished its
# `gc session list --json` query, and a 15s window can be entirely
# consumed by the other gc calls in this script. 60s keeps the slot
# fresh enough that an operator rename appears within one or two
# tmux status-interval ticks, and matches the rough cadence at which
# titles actually change.
TITLE_TTL=60
INDICATOR_FILE="/tmp/gc-status-${slug}.indicator"

# BUDGET caps total bytes emitted by this script. tmux-theme.sh sets
# status-right-length=80 and appends " %H:%M" after the #() expansion,
# which is ~6 cells. Leave headroom so the time slot is never crowded.
BUDGET=72

# --- Fixed segments: hook / mail counts (always render) -----------------

w=$(gc hook "$agent" 2>/dev/null | grep -c . || true)
m=$(gc mail check "$agent" 2>/dev/null | awk '{print $1+0}' || true)

hook_seg=""
[ "${w:-0}" -gt 0 ] && hook_seg=" | 🪝 ${w}"
mail_seg=""
[ "${m:-0}" -gt 0 ] && mail_seg=" | 📬 ${m}"

# --- Title slot ---------------------------------------------------------
# Cached in /tmp/gc-title-<slug>. Cache hit when file is younger than
# TITLE_TTL. Cache contents are the already-filtered title (empty
# string means "hide the slot").

title=""
read_cache=0
if [ -f "$TITLE_CACHE" ]; then
    cache_mtime=$(stat -c %Y "$TITLE_CACHE" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ $(( now - cache_mtime )) -lt "$TITLE_TTL" ]; then
        read_cache=1
        title=$(cat "$TITLE_CACHE" 2>/dev/null || true)
    fi
fi

if [ "$read_cache" -eq 0 ]; then
    raw_title=$(gc session list --state active --json 2>/dev/null \
        | jq -r --arg a "$agent" \
            '.sessions | map(select(.agent_name == $a)) | .[0].title // ""' 2>/dev/null \
        || true)
    # Hide when title is the default (equals the agent name).
    if [ "$raw_title" = "$agent" ] || [ "$raw_title" = "null" ]; then
        title=""
    else
        title="$raw_title"
    fi
    # Update cache (best-effort; tmux must not see errors).
    printf '%s' "$title" > "$TITLE_CACHE" 2>/dev/null || true
fi

# --- Indicator slot -----------------------------------------------------
indicator=""
if [ -f "$INDICATOR_FILE" ]; then
    # tr -d '\n' so multi-line writes don't break the status bar.
    indicator=$(tr -d '\n' < "$INDICATOR_FILE" 2>/dev/null || true)
fi

# --- Width budget enforcement -------------------------------------------
# Compute byte-length of fixed footprint (counts only — the agent name
# no longer lives on this side of the status bar). Whatever's left is
# shared between title and indicator. Truncate title first (the bead's
# rule), then indicator. Multi-byte characters cost more bytes than
# cells, so byte-length is a conservative over-estimate; the visible
# output may be a few cells under budget. Acceptable for a status bar.

fixed="${hook_seg}${mail_seg}"
fixed_len=${#fixed}
remaining=$(( BUDGET - fixed_len ))
[ "$remaining" -lt 0 ] && remaining=0

# Trim helper: $1 = string, $2 = max bytes. If shorter than max,
# returns as-is. Else cuts to (max-1) bytes and appends "…". If
# max < 4 (no room for any visible content + ellipsis), returns
# empty string.
trim() {
    s="$1"
    max="$2"
    if [ "$max" -lt 4 ]; then
        printf ''
        return
    fi
    if [ ${#s} -le "$max" ]; then
        printf '%s' "$s"
    else
        cut_to=$(( max - 1 ))
        printf '%s…' "$(printf '%s' "$s" | cut -c1-"$cut_to")"
    fi
}

# When indicator is also present, split remaining width half-and-half
# so neither slot starves the other. When indicator is empty, give
# title the full remaining width (minus the leading space). No fixed
# upper cap — operator-set titles are the primary content of the
# right side now that the agent prefix is gone.
if [ -n "$title" ]; then
    if [ -n "$indicator" ]; then
        title_max=$(( remaining / 2 ))
    else
        title_max=$remaining
    fi
    # -1 reserves the leading space we emit before the title.
    title=$(trim "$title" $(( title_max - 1 )))
    if [ -n "$title" ]; then
        remaining=$(( remaining - ${#title} - 1 ))
    fi
fi

if [ -n "$indicator" ]; then
    # +1 for the leading space before the indicator.
    indicator=$(trim "$indicator" $(( remaining - 1 )))
fi

# --- Emit ----------------------------------------------------------------
# Every non-empty segment carries its own leading-space (or pipe-space
# for counts), so concatenation is order-only — no separator joins.
# When all four are empty the script emits nothing and tmux renders
# just the trailing " %H:%M" from gastown's status-right format.
[ -n "$title" ] && printf ' %s' "$title"
[ -n "$indicator" ] && printf ' %s' "$indicator"
[ -n "$hook_seg" ] && printf '%s' "$hook_seg"
[ -n "$mail_seg" ] && printf '%s' "$mail_seg"
exit 0
