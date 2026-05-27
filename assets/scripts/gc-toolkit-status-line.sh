#!/bin/sh
# gc-toolkit-status-line.sh — tmux status-right helper for gc-toolkit agents.
#
# Usage: gc-toolkit-status-line.sh <agent-name> [city-path]
#
# `city-path` is the absolute path of the city this agent belongs to —
# baked into the status-right command by tmux-status-line-override.sh
# at install time. Used to translate path→name via ~/.gc/cities.toml
# so the API call hits the right city in multi-city setups. Falls back
# to $GC_CITY_PATH / $GC_CITY / $GC_CITY_ROOT (legacy callers); if none
# are set the title slot is skipped silently. No cwd walk-up — see
# gc_city_name() for rationale.
#
# Replaces gastown's status-line.sh as the body of #(...) in status-right.
# Renders two composable slots, hook/mail counts, and a timing slot:
#
#   [<title>] [<indicator>] | 🪝 N | 📬 M | ⏱ T ms
#
# The agent name is intentionally NOT rendered here — it lives on the
# left side of the status bar (see tmux-status-line-override.sh, which
# also overrides status-left with a short-name form of $AGENT). When
# title, indicator, and both counts are all empty, this script emits
# nothing and tmux shows just " %H:%M".
#
# - <title>     : from the supervisor API (/v0/city/<name>/sessions).
#                 Hidden when title equals the agent name (the gascity
#                 default — no operator-set title yet). The server's
#                 CachingStore memoizes the response, so per-pane tmux
#                 refreshes collapse to one Dolt walk per cache window;
#                 no local /tmp cache is needed.
# - <indicator> : verbatim contents of /tmp/gc-status-<slug>.indicator
#                 if the file exists. Any gc-toolkit script can write or
#                 clear this file; the next status refresh picks it up.
#                 Last-writer-wins. Writers MUST `rm -f` the file when
#                 their work completes (trap on EXIT is the safe pattern).
# - <timing>    : wall time across the three downstream queries below
#                 (gc hook, gc mail check, supervisor sessions curl).
#                 Always rendered. Surfaces when the status refresh
#                 starts paying real cost. Falls back to whole-second
#                 precision on dates without %N support — the value
#                 stays numeric but loses sub-second resolution.
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
EXPLICIT_CITY_PATH="${2:-}"

# Filesystem-safe slug: replace path-/dot-bearing characters with `-`.
slug=$(printf '%s' "$agent" | sed 's|[./]|-|g')

INDICATOR_FILE="/tmp/gc-status-${slug}.indicator"

# Resolve supervisor base URL + city name. Honor ~/.gc/supervisor.toml
# port override; fall back to the default 8372. City name is looked
# up in ~/.gc/cities.toml by matching the current city path against
# each [[cities]] entry's path. The path comes from the explicit
# argument captured at install time by tmux-status-line-override.sh
# (deterministic in tmux's bare env); $GC_CITY_PATH / $GC_CITY /
# $GC_CITY_ROOT are diagnostic fallbacks. When no [[cities]] entry
# matches we fall back to basename of the path; when no path is
# available at all gc_city_name() returns empty and the caller skips
# the API call. The helpers are duplicated across status-line / picker;
# keep them in lockstep.
gc_api_base() {
    port=8372
    cfg="${GC_HOME:-$HOME/.gc}/supervisor.toml"
    if [ -f "$cfg" ]; then
        v=$(awk -F= '/^[[:space:]]*port[[:space:]]*=/ { gsub(/[[:space:]]/,"",$2); print $2; exit }' "$cfg" 2>/dev/null)
        [ -n "$v" ] && port=$v
    fi
    printf 'http://127.0.0.1:%s' "$port"
}
gc_city_name() {
    cfg="${GC_HOME:-$HOME/.gc}/cities.toml"
    city_path="${EXPLICIT_CITY_PATH:-${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}}"
    # No cwd walk-up: reproducing gc's findCity heuristics here risks
    # diverging silently from the canonical implementation, and the
    # explicit arg + env chain already covers every real callsite
    # (status-line / picker baked at install time).
    # Caller treats empty output as "no API available".
    [ -z "$city_path" ] && return
    city_path="${city_path%/}"
    if [ -f "$cfg" ]; then
        name=$(awk -v want="$city_path" '
            BEGIN { in_block=0; p=""; n=""; found=0 }
            /^\[\[cities\]\]/ {
                if (in_block && p == want && n != "") { print n; found=1; exit }
                in_block=1; p=""; n=""; next
            }
            /^\[/ {
                if (in_block && p == want && n != "") { print n; found=1; exit }
                in_block=0; next
            }
            in_block && /^[[:space:]]*path[[:space:]]*=[[:space:]]*"[^"]*"/ {
                v=$0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); p=v
            }
            in_block && /^[[:space:]]*name[[:space:]]*=[[:space:]]*"[^"]*"/ {
                v=$0; sub(/^[^"]*"/, "", v); sub(/".*$/, "", v); n=v
            }
            END {
                if (!found && in_block && p == want && n != "") print n
            }
        ' "$cfg")
        [ -n "$name" ] && { printf '%s' "$name"; return; }
    fi
    basename "$city_path"
}

# BUDGET caps total bytes emitted by this script. tmux-theme.sh sets
# status-right-length=80 and appends " %H:%M" after the #() expansion,
# which is ~6 cells. Leave headroom so the time slot is never crowded.
BUDGET=72

# --- Time downstream queries -------------------------------------------
# Brackets the three subprocess/network calls below. GNU date returns
# nanoseconds for %N; non-GNU returns the literal "N", so probe once
# and degrade to whole-second precision rather than poisoning the math.
case "$(date +%N 2>/dev/null)" in
    ''|N) NS_OK=0 ;;
    *)    NS_OK=1 ;;
esac
_ns_now() {
    t=$(date +%s%N 2>/dev/null)
    [ "$NS_OK" = 1 ] || t="${t%N}000000000"
    printf '%s' "$t"
}
start_t=$(_ns_now)

# --- Fixed segments: hook / mail counts (always render) -----------------

w=$(gc hook "$agent" 2>/dev/null | grep -c . || true)
m=$(gc mail count "$agent" --json 2>/dev/null | jq -r '.unread // 0' 2>/dev/null || echo 0)

hook_seg=""
[ "${w:-0}" -gt 0 ] && hook_seg=" | 🪝 ${w}"
mail_seg=""
[ "${m:-0}" -gt 0 ] && mail_seg=" | 📬 ${m}"

# --- Title slot ---------------------------------------------------------
# One HTTP round-trip per refresh; the server's CachingStore memoizes
# the underlying Dolt walk so concurrent panes don't fan out. curl -f
# silences the body during the ~1-2s cold-cache 503 window after
# `gc start`; jq fails closed when input is empty.
title=""
raw_title=""
city_name=$(gc_city_name)
# Skip the API call entirely when no city resolves — `/v0/city//sessions`
# would just 404 and add latency to every status refresh.
if [ -n "$city_name" ]; then
    raw_title=$(curl -sf --max-time 3 \
        "$(gc_api_base)/v0/city/$city_name/sessions?state=active" 2>/dev/null \
        | jq -r --arg a "$agent" \
            '.items | map(select(.alias == $a)) | .[0].title // ""' 2>/dev/null \
        || true)
fi
end_t=$(_ns_now)
elapsed_ms=$(( (${end_t:-0} - ${start_t:-0}) / 1000000 ))
timing_seg=" | ⏱ ${elapsed_ms}ms"
# Hide when title is the gascity default. For most agents that means
# title == alias; for thread agents gascity strips the `-adhoc-<hex>`
# suffix when assigning the default, so the title equals the role name
# instead (e.g. alias `gc-toolkit.mayor-thread-adhoc-6d0c0eb30f` →
# default title `gc-toolkit.mayor-thread`). Strip the suffix and
# compare both.
agent_role="${agent%-adhoc-*}"
if [ "$raw_title" = "$agent" ] || [ "$raw_title" = "$agent_role" ] || [ "$raw_title" = "null" ]; then
    title=""
else
    title="$raw_title"
fi

# --- Indicator slot -----------------------------------------------------
indicator=""
if [ -f "$INDICATOR_FILE" ]; then
    # tr -d '\n' so multi-line writes don't break the status bar.
    indicator=$(tr -d '\n' < "$INDICATOR_FILE" 2>/dev/null || true)
fi

# --- Width budget enforcement -------------------------------------------
# Compute byte-length of fixed footprint (counts + timing — the agent
# name no longer lives on this side of the status bar). Whatever's left
# is shared between title and indicator. Truncate title first (the
# bead's rule), then indicator. Multi-byte characters cost more bytes
# than cells, so byte-length is a conservative over-estimate; the
# visible output may be a few cells under budget. Acceptable for a
# status bar.

fixed="${hook_seg}${mail_seg}${timing_seg}"
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
[ -n "$timing_seg" ] && printf '%s' "$timing_seg"
exit 0
