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
# Renders two composable slots plus hook/mail counts:
#
#   [<title>] [<indicator>] | 🪝 N | 📬 M
#
# The agent name is intentionally NOT rendered here — it lives on the
# left side of the status bar (see tmux-status-line-override.sh, which
# also overrides status-left with a short-name form of $AGENT). When
# title, indicator, and both counts are all empty, this script emits
# nothing and tmux shows just " %H:%M".
#
# - <title>     : from the supervisor API (/v0/city/<name>/sessions).
#                 Hidden when title equals the agent name (the gascity
#                 default — no operator-set title yet). The title slot
#                 requests view=summary — the lean read-model view (no
#                 per-session enrichment).
# - <indicator> : verbatim contents of /tmp/gc-status-<slug>.indicator
#                 if the file exists. Any gc-toolkit script can write or
#                 clear this file; the next status refresh picks it up.
#                 Last-writer-wins. Writers MUST `rm -f` the file when
#                 their work completes (trap on EXIT is the safe pattern).
#                 Read LIVE on every render (never cached) so the
#                 [spawning …] feedback appears and clears on the next
#                 refresh rather than being delayed by up to one TTL.
#
# TTL cache (perf): the three fork-heavy queries — `gc hook`,
# `gc mail count`, and the supervisor `curl` — are cached together in
# one per-(city,agent) file for GC_STATUSLINE_TTL seconds (default 30).
# tmux re-evaluates status #() on every redraw (status-interval is a MAX,
# not a minimum), so without a cache an actively-attached pane forks
# gc+curl into Beads/the supervisor ~1×/second. With the cache, a render
# inside the TTL is a pure file read: no gc/curl fork. Each underlying
# query is additionally bounded by `timeout 2s` (run_bounded) so a wedged
# backend can never hang tmux. Structure adapted from gascity-packs
# v0.3.1 gastown/assets/scripts/status-line.sh. Overrides:
# GC_STATUSLINE_TTL (seconds), GC_STATUSLINE_CACHE_DIR (path).
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

# --- TTL cache helpers --------------------------------------------------
# Adapted from gascity-packs v0.3.1 status-line.sh. run_bounded caps each
# backend query at 2s (no-op when `timeout` is unavailable); is_number /
# cache_mtime guard the freshness math; json_array_count returns the
# element count of a JSON array emitted by the bounded command.
run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 2s "$@"
    else
        "$@"
    fi
}

is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

cache_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

json_array_count() {
    if ! command -v jq >/dev/null 2>&1; then
        printf '0'
        return 0
    fi
    n=$(run_bounded "$@" 2>/dev/null | jq 'if type == "array" then length else 0 end' 2>/dev/null || true)
    case "$n" in
        ''|*[!0-9]*) printf '0' ;;
        *) printf '%s' "$n" ;;
    esac
}

# BUDGET caps total bytes emitted by this script. tmux-theme.sh sets
# status-right-length=80 and appends " %H:%M" after the #() expansion,
# which is ~6 cells. Leave headroom so the time slot is never crowded.
BUDGET=72

# --- Cache the three fork-heavy queries ---------------------------------
# hook count, mail unread count, and the supervisor title curl share one
# per-(city,agent) cache file. Layout: line 1 = "<hook> <mail>" (two
# integers), line 2 = the raw title (may be empty or contain spaces;
# never a newline). A render within the TTL reads this file and forks
# neither gc nor curl.
cache_ttl="${GC_STATUSLINE_TTL:-30}"
is_number "$cache_ttl" || cache_ttl=30
if [ -n "${GC_STATUSLINE_CACHE_DIR:-}" ]; then
    cache_dir="$GC_STATUSLINE_CACHE_DIR"
    cache_private=0
else
    cache_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
    uid=$(id -u 2>/dev/null || printf 'unknown')
    cache_dir="$cache_base/gc-statusline-$uid"
    cache_private=1
fi
cache_city="${EXPLICIT_CITY_PATH:-${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}}"
safe_agent=$(printf '%s' "$agent" | tr -c 'A-Za-z0-9._-' '_')
cache_key=$(printf '%s\n%s\n' "$cache_city" "$agent" | cksum | awk '{print $1}')
cache="$cache_dir/gc-statusline-${safe_agent}-${cache_key}.cache"

w=0
m=0
raw_title=""

now=$(date +%s 2>/dev/null || printf '0')
mtime=$(cache_mtime "$cache")
if is_number "$now" && is_number "$mtime" && [ "$mtime" -gt 0 ] && [ "$((now - mtime))" -lt "$cache_ttl" ]; then
    # Cache hit — read counts (line 1) and raw title (line 2). IFS= on the
    # title read preserves embedded spaces.
    {
        read -r w m
        IFS= read -r raw_title
    } < "$cache" 2>/dev/null || true
    is_number "${w:-}" || w=0
    is_number "${m:-}" || m=0
else
    # Cache miss/stale — run the fork-heavy queries, each bounded by 2s.

    # gc hook ready-work count (array length — 0 when idle). json_array_count
    # parses the JSON array, so it is correct regardless of pretty-printing
    # and for the empty-array case.
    w=$(json_array_count gc hook "$agent")

    # gc mail unread count. gc-toolkit uses `gc mail count` (not gastown's
    # `gc mail check`) — a deliberate perf divergence (PR #74).
    m=$(run_bounded gc mail count "$agent" --json 2>/dev/null | jq -r '.unread // 0' 2>/dev/null || echo 0)
    is_number "$m" || m=0

    # Supervisor title. One HTTP round-trip, lean view=summary read-model.
    # Skip entirely when no city resolves — `/v0/city//sessions` would just
    # 404 and add latency. run_bounded (timeout 2s) is the bound when the
    # `timeout` binary exists; curl --max-time is the fallback bound when it
    # does not. curl -f silences the body during the ~1-2s 503 window after
    # `gc start`; jq fails closed when input is empty.
    city_name=$(gc_city_name)
    if [ -n "$city_name" ]; then
        raw_title=$(run_bounded curl -sf --max-time 2 \
            "$(gc_api_base)/v0/city/$city_name/sessions?state=active&view=summary" 2>/dev/null \
            | jq -r --arg a "$agent" \
                '.items | map(select(.alias == $a)) | .[0].title // ""' 2>/dev/null \
            || true)
    fi

    # Persist atomically (temp + rename) so a concurrent reader — e.g. a
    # second pane attached to the same agent — never sees a torn write.
    mkdir -p "$cache_dir" 2>/dev/null || true
    [ "$cache_private" = 1 ] && chmod 700 "$cache_dir" 2>/dev/null || true
    tmp="$cache.$$.tmp"
    if printf '%s %s\n%s\n' "${w:-0}" "${m:-0}" "$raw_title" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    fi
fi

is_number "${w:-}" || w=0
is_number "${m:-}" || m=0

# --- Fixed segments: hook / mail counts (always render) -----------------
hook_seg=""
[ "$w" -gt 0 ] && hook_seg=" | 🪝 ${w}"
mail_seg=""
[ "$m" -gt 0 ] && mail_seg=" | 📬 ${m}"

# --- Title slot presentation --------------------------------------------
# Pure string work (no fork), runs every render. Hide when title is the
# gascity default. For most agents that means title == alias; for thread
# agents gascity strips the `-adhoc-<hex>` suffix when assigning the
# default, so the title equals the role name instead (e.g. alias
# `gc-toolkit.mayor-thread-adhoc-6d0c0eb30f` → default title
# `gc-toolkit.mayor-thread`). Strip the suffix and compare both.
title=""
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
# Compute byte-length of fixed footprint (the counts — the agent name no
# longer lives on this side of the status bar, and the timing slot has
# been removed). Whatever's left is shared between title and indicator.
# Truncate title first (the bead's rule), then indicator. Multi-byte
# characters cost more bytes than cells, so byte-length is a conservative
# over-estimate; the visible output may be a few cells under budget.
# Acceptable for a status bar.

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
