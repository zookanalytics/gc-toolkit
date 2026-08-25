#!/bin/sh
# gc-toolkit-status-line.sh — tmux status-right helper for gc-toolkit agents.
# Usage: gc-toolkit-status-line.sh <agent-name> [city-path]
# Renders "[<title>] [<indicator>] | 🪝 N | 📬 M | ⏱ T.Ts" (empty slots
# omitted; the agent name lives on status-left, set by
# tmux-status-line-override.sh, which also bakes in city-path so the city
# lookup works from tmux's bare env). <title> comes from the supervisor API
# (hidden when it equals the agent name / role default); <indicator> is the
# live contents of /tmp/gc-status-<slug>.indicator (any script may write it;
# writers rm -f it when done). The three fork-heavy queries (gc hook,
# gc mail count, supervisor curl) share one per-(city,agent) TTL cache
# (GC_STATUSLINE_TTL, default 30s) because tmux re-evaluates #() on every
# redraw; each is also bounded at 10s. ⏱ is the last uncached wall time.
# Output is byte-capped at BUDGET; title truncates first, then indicator.
# Always exits 0 — tmux must never see an error.
set -u

agent="${1:-}"
[ -z "$agent" ] && exit 0
EXPLICIT_CITY_PATH="${2:-}"

# Filesystem-safe slug: replace path-/dot-bearing characters with `-`.
slug=$(printf '%s' "$agent" | sed 's|[./]|-|g')

INDICATOR_FILE="/tmp/gc-status-${slug}.indicator"

# Supervisor base URL (~/.gc/supervisor.toml port, default 8372) and city
# name (~/.gc/cities.toml path match, else basename; empty = skip the API).
# Helpers duplicated across status-line / picker — keep in lockstep.
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
    # No cwd walk-up (would diverge from gc's findCity); empty = no API.
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

# --- TTL cache helpers ---------------------------------------------------
run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 10s "$@"
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

# Nanosecond wall clock for the timing slot; NS_OK (set by the miss branch)
# degrades a non-GNU date to whole seconds instead of poisoning arithmetic.
_ns_now() {
    t=$(date +%s%N 2>/dev/null)
    [ "$NS_OK" = 1 ] || t="${t%N}000000000"
    printf '%s' "$t"
}

# Byte cap: status-right-length is 80 with " %H:%M" (~6 cells) appended.
BUDGET=72

# --- Cache: line 1 "<hook> <mail>", line 2 raw title, line 3 miss tenths --
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
display_tenths=""

now=$(date +%s 2>/dev/null || printf '0')
mtime=$(cache_mtime "$cache")
if is_number "$now" && is_number "$mtime" && [ "$mtime" -gt 0 ] && [ "$((now - mtime))" -lt "$cache_ttl" ]; then
    # Cache hit — read line 1 counts, line 2 title, line 3 tenths; IFS= keeps title spaces.
    {
        read -r w m
        IFS= read -r raw_title
        read -r display_tenths
    } < "$cache" 2>/dev/null || true
    is_number "${w:-}" || w=0
    is_number "${m:-}" || m=0
    is_number "${display_tenths:-}" || display_tenths=""
else
    # Cache miss/stale — run the fork-heavy queries (run_bounded, 10s).
    case "$(date +%N 2>/dev/null)" in ''|N) NS_OK=0 ;; *) NS_OK=1 ;; esac
    miss_start=$(_ns_now)

    # gc hook ready-work count (array length — 0 when idle).
    w=$(json_array_count gc hook "$agent")

    # gc mail unread count (`gc mail count`, the cheap form).
    m=$(run_bounded gc mail count "$agent" --json 2>/dev/null | jq -r '.unread // 0' 2>/dev/null || echo 0)
    is_number "$m" || m=0

    # Supervisor title (view=summary); skip when no city resolves; -f hides
    # the post-start 503 body.
    city_name=$(gc_city_name)
    if [ -n "$city_name" ]; then
        raw_title=$(run_bounded curl -sf --max-time 10 \
            "$(gc_api_base)/v0/city/$city_name/sessions?state=active&view=summary" 2>/dev/null \
            | jq -r --arg a "$agent" \
                '.items | map(select(.alias == $a)) | .[0].title // ""' 2>/dev/null \
            || true)
    fi
    miss_end=$(_ns_now)

    # Nanosecond delta to tenths of a second (round to nearest, +0.05s).
    display_tenths=$(( (miss_end - miss_start + 50000000) / 100000000 ))
    [ "$display_tenths" -lt 0 ] && display_tenths=0

    # Persist atomically (temp + rename).
    mkdir -p "$cache_dir" 2>/dev/null || true
    [ "$cache_private" = 1 ] && chmod 700 "$cache_dir" 2>/dev/null || true
    tmp="$cache.$$.tmp"
    if printf '%s %s\n%s\n%s\n' "${w:-0}" "${m:-0}" "$raw_title" "$display_tenths" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    fi
fi

is_number "${w:-}" || w=0
is_number "${m:-}" || m=0

# --- Timing slot (persistent) -------------------------------------------
# Render display_tenths as "⏱ N.Ns" (one decimal); empty until the first miss.
timing_seg=""
if is_number "${display_tenths:-}"; then
    timing_seg=" | ⏱ $(( display_tenths / 10 )).$(( display_tenths % 10 ))s"
fi

# --- Fixed segments: hook / mail counts (always render) -----------------
hook_seg=""
[ "$w" -gt 0 ] && hook_seg=" | 🪝 ${w}"
mail_seg=""
[ "$m" -gt 0 ] && mail_seg=" | 📬 ${m}"

# --- Title slot: hide the gascity default (alias, or the role name an
# ad-hoc session's `-adhoc-<hex>` suffix strips to) ------------------------
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

# --- Width budget: counts+timing are fixed; the rest is shared between
# title (truncated first) and indicator. Byte-length over-estimates cells,
# which is the safe direction for a status bar.

fixed="${hook_seg}${mail_seg}${timing_seg}"
fixed_len=${#fixed}
remaining=$(( BUDGET - fixed_len ))
[ "$remaining" -lt 0 ] && remaining=0

# trim <string> <max-bytes>: cut to max-1 + "…"; empty when max < 4.
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

# With an indicator present, split the remaining width half-and-half.
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

# --- Emit: each segment carries its own leading space; all empty = emit
# nothing and tmux shows just " %H:%M" ------------------------------------
[ -n "$title" ] && printf ' %s' "$title"
[ -n "$indicator" ] && printf ' %s' "$indicator"
[ -n "$hook_seg" ] && printf '%s' "$hook_seg"
[ -n "$mail_seg" ] && printf '%s' "$mail_seg"
[ -n "$timing_seg" ] && printf '%s' "$timing_seg"
exit 0
