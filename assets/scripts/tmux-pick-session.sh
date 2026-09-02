#!/bin/sh
# tmux-pick-session.sh — Gas City session picker (prefix+S).
#
# Usage: tmux-pick-session.sh [--all] [--city-path <path>] [--refresh-cache]
#
# Default filter hides the sessions an operator does not reach one at a
# time: the polecats (folded into the per-rig count), control-dispatcher,
# deacon, witness, dog (the warrant-executor pool), boot. The
# currently-attached session is always shown.
# --all disables the filter; toggle from inside the menu via [.].
# --city-path is the absolute path of the city this binding belongs
# to — baked in by tmux-bindings.sh at install time so the API URL is
# deterministic even though the key fires from tmux's bare env.
# --refresh-cache refetches the role map and exits without rendering. The
# picker spawns it detached on each keypress; nothing else calls it.
#
# Rig + identity derivation, in the order the awk block tries them:
#   1. GC_AGENT is "<rig>/<pack>.<role>". Both fields come from it.
#   2. The session name is "<rig>--<pack>__<agent>". The rig is the part
#      before "--"; the display is the rest, with "__" rendered as ".".
#   3. GC_AGENT is set but carries no slash. The agent is city-scoped:
#      the rig is "city" and the display is GC_AGENT.
#   4. Nothing answers. The rig is "city" and the display is the raw
#      session name.
# Rule 2 must precede rule 3. A pool instance carries its own tmux
# session name in GC_AGENT rather than an address, so it satisfies both,
# and rule 3 would file it under a rig that does not exist.
# `switch-client -t` always targets the raw tmux session_name; the
# derived display is label-only.
#
# Role comes from the agent template, never from the session name. A codex
# polecat runs under a character name ("hicks") and a converse runs on a
# "-<n>-pool" slot, so the name carries the scheduling fact and not the
# role. The template rides the supervisor-API row already fetched for
# titles, and a keypress reads both from a cache instead of the API. A
# session the cached map does not cover has no role at all: it is neither
# folded into a rig's count nor hidden, because the name shape that would
# guess for it is exactly what the template is here to replace.
#
# Sort order:
#   1. [city] group — alphabetical
#   2. each rig group, rigs alphabetical, polecats last within rig
#   Pane sub-rows always appear directly under their session row.
#
# Visual indicators:
#   *  — session is attached
#   ▣  — session has more than one tmux window (interactive working
#         environment, vs single-window agent runtimes)
#   •  — pane is the active pane within its window (only on inline
#         pane sub-rows)
#   ▫  — menu title only: the role map is older than the roster it groups,
#         or missing entirely
#
# Multi-pane sessions get inline pane sub-rows in the SAME display-menu
# (`choose-tree -F` cannot be used: its "session: window: pane:" prefix is
# hardcoded in tmux's window-tree.c).
set -e

ALL=0
EXPLICIT_CITY_PATH=""
REFRESH_ONLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --all) ALL=1; shift ;;
        --refresh-cache) REFRESH_ONLY=1; shift ;;
        --city-path) EXPLICIT_CITY_PATH="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
TAB="$(printf '\t')"

# sq <string> — POSIX shell-quote for safe embedding in a tmux command.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Supervisor API discovery — see gc-toolkit-status-line.sh for the
# canonical comment. Port honors ~/.gc/supervisor.toml; city name is
# resolved by matching the current city path against [[cities]] entries
# in ~/.gc/cities.toml. Keep in lockstep with status-line.
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
    # No cwd walk-up — see gc-toolkit-status-line.sh for rationale.
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

# --- Role cache ----------------------------------------------------------
# Per-session facts are "session_name\ttemplate\ttitle": one supervisor-API
# row answers both the role and the title, and a second source for either
# would put another subprocess on a keypress. The keypress reads them from a
# file and never makes the call. The call costs one to two seconds on an idle
# city and several on a busy one, so in front of an operator it is both a
# visible delay and, exactly when the city is busiest, a timeout. The fetch
# runs detached, for the NEXT keypress, which makes the rendered map as old
# as the gap between keypresses — the title marker is how the operator sees
# that.

is_number() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}
cache_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

# Cache location, keyed by city so one city's roster cannot answer another's.
# GC_PICKER_CACHE_DIR overrides the directory; the default is per-uid and
# 0700, because the cached rows carry session titles.
roles_cache_init() {
    if [ -n "${GC_PICKER_CACHE_DIR:-}" ]; then
        ROLES_CACHE_DIR="$GC_PICKER_CACHE_DIR"
        ROLES_CACHE_PRIVATE=0
    else
        uid=$(id -u 2>/dev/null || printf 'unknown')
        ROLES_CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/gc-picker-$uid"
        ROLES_CACHE_PRIVATE=1
    fi
    safe_city=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
    city_key=$(printf '%s\n' "$1" | cksum | awk '{print $1}')
    ROLES_CACHE="$ROLES_CACHE_DIR/roles-$safe_city-$city_key.cache"
    # The throttle counts attempts, not successes. Counting successes means a
    # supervisor that answers slowly is never throttled at all, which is the
    # one state where a pile-up of overlapping fetches costs something.
    ROLES_STAMP="$ROLES_CACHE.attempt"
}

# Refetch, then replace the file atomically. A failed or empty fetch keeps
# the last good map: an unreachable supervisor is not evidence that the city
# has no sessions, and an empty map ungroups every rig at once.
roles_cache_refresh() {
    mkdir -p "$ROLES_CACHE_DIR" 2>/dev/null || true
    if [ "$ROLES_CACHE_PRIVATE" = 1 ]; then
        chmod 700 "$ROLES_CACHE_DIR" 2>/dev/null || true
    fi
    : > "$ROLES_STAMP" 2>/dev/null || true
    # A longer bound than the keypress could ever have afforded. Raising it
    # was not an option while the fetch blocked the menu — it only traded a
    # wrong grouping for a hanging key — but nothing waits on this one, and
    # a busy supervisor outruns three seconds often enough that the shorter
    # bound would leave the map to age untouched.
    facts=$(curl -sf --max-time 15 \
        "$(gc_api_base)/v0/city/$CITY_NAME/sessions" 2>/dev/null \
        | jq -r '.items[]? | select(.session_name != null)
                 | "\(.session_name)\t\(.template // "")\t\(.title // "")"' 2>/dev/null \
        || true)
    [ -n "$facts" ] || return 0
    # Temp + rename, so overlapping refreshes cannot interleave a half-written
    # map into a keypress that is reading one.
    tmp="$ROLES_CACHE.$$.tmp"
    if printf '%s\n' "$facts" > "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$ROLES_CACHE" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    fi
}

CITY_NAME=$(gc_city_name)
FACTS=""
ROLES_AGE=""
if [ -n "$CITY_NAME" ]; then
    roles_cache_init "$CITY_NAME"
fi
if [ "$REFRESH_ONLY" -eq 1 ]; then
    if [ -n "$CITY_NAME" ]; then
        roles_cache_refresh
    fi
    exit 0
fi
if [ -n "$CITY_NAME" ]; then
    now=$(date +%s 2>/dev/null || printf '0')
    mtime=$(cache_mtime "$ROLES_CACHE")
    if is_number "$now" && is_number "$mtime" && [ "$mtime" -gt 0 ]; then
        FACTS=$(cat "$ROLES_CACHE" 2>/dev/null || true)
        ROLES_AGE=$((now - mtime))
        if [ "$ROLES_AGE" -lt 0 ]; then ROLES_AGE=0; fi
    fi

    # Refresh for the next keypress. The subshell exits at once and the fetch
    # is reparented with all three descriptors redirected, so the `run-shell`
    # that fired the binding keeps no output to wait on. Throttled, because
    # [.] re-invokes the picker immediately and would otherwise refetch the
    # roster the previous keypress just fetched.
    REFRESH_EVERY="${GC_PICKER_REFRESH_EVERY:-10}"
    is_number "$REFRESH_EVERY" || REFRESH_EVERY=10
    attempted=$(cache_mtime "$ROLES_STAMP")
    is_number "$attempted" || attempted=0
    if [ "$attempted" -eq 0 ] || ! is_number "$now" \
        || [ "$((now - attempted))" -ge "$REFRESH_EVERY" ]; then
        # shellcheck disable=SC2086 # ${EXPLICIT_CITY_PATH:+…} expands to 0 or 2 fields
        ( "$SCRIPT" --refresh-cache ${EXPLICIT_CITY_PATH:+--city-path "$EXPLICIT_CITY_PATH"} \
            >/dev/null 2>&1 </dev/null & )
    fi
fi

# Menu title. The grouping is only as current as the cached map, so the
# marker rides the title rather than a row: it is a fact about every count
# and every hidden row at once. No map at all — first keypress, cleared
# cache, no reachable city — reads differently from a stale one, because it
# groups nothing and hides nothing rather than grouping by old facts.
STALE_AFTER="${GC_PICKER_STALE_AFTER:-120}"
is_number "$STALE_AFTER" || STALE_AFTER=120
MENU_TITLE=" Sessions "
if [ -z "$FACTS" ]; then
    MENU_TITLE=" Sessions ▫ no roles "
elif is_number "$ROLES_AGE" && [ "$ROLES_AGE" -ge "$STALE_AFTER" ]; then
    if [ "$ROLES_AGE" -lt 3600 ]; then
        age_word="$((ROLES_AGE / 60))m"
    elif [ "$ROLES_AGE" -lt 86400 ]; then
        age_word="$((ROLES_AGE / 3600))h"
    else
        age_word="$((ROLES_AGE / 86400))d"
    fi
    MENU_TITLE=" Sessions ▫ roles $age_word old "
fi

ACTIVE=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)

# One row per pane across all sessions. pane_title can contain `|`,
# so the awk pre-pass joins fields 6+ back into the title.
PANES=$(gcmux list-panes -aF '#{session_name}|#{window_index}|#{pane_index}|#{pane_active}|#{pane_current_command}|#{pane_title}' 2>/dev/null || true)

LIST=$(gcmux list-sessions -F '#{session_name}|#{session_attached}|#{session_windows}|#{E:GC_AGENT}' | awk -F'|' \
    -v all="$ALL" -v active="$ACTIVE" -v panes="$PANES" -v facts="$FACTS" '
BEGIN {
    n_panes = split(panes, P, "\n")
    for (i = 1; i <= n_panes; i++) {
        if (P[i] == "") continue
        m = split(P[i], pf, "|")
        if (m < 5) continue
        sn = pf[1]; wi = pf[2]; pi = pf[3]; pa = pf[4] + 0; cmd = pf[5]
        title = ""
        if (m >= 6) {
            title = pf[6]
            for (j = 7; j <= m; j++) title = title "|" pf[j]
        }
        gsub(/[\t\r\n]/, " ", title)
        gsub(/[\t\r\n]/, " ", cmd)
        pane_count[sn]++
        idx = pane_count[sn]
        pn_wi[sn, idx] = wi
        pn_pi[sn, idx] = pi
        pn_pa[sn, idx] = pa
        pn_cmd[sn, idx] = cmd
        pn_title[sn, idx] = title
    }
    # Build session_name -> (role, gc title). Lines are
    # "<name>\t<template>\t<title>": the title takes the whole remainder, so a
    # tab inside it cannot shift a field, and embedded tabs/CR/LF are stripped
    # so the awk row stays well-formed (mirrors the PANES handler above).
    n_facts = split(facts, T, "\n")
    for (i = 1; i <= n_facts; i++) {
        if (T[i] == "") continue
        tab = index(T[i], "\t")
        if (tab == 0) continue
        sn = substr(T[i], 1, tab - 1)
        rest = substr(T[i], tab + 1)
        tab = index(rest, "\t")
        if (tab == 0) continue
        tmpl = substr(rest, 1, tab - 1)
        ti = substr(rest, tab + 1)
        gsub(/[\t\r\n]/, " ", ti)
        gc_title[sn] = ti
        # Role is the last dotted component of the template: both
        # "<rig>/<pack>.<role>" and the slashless "<pack>.<role>" end in it.
        sub(/^.*\//, "", tmpl)
        sub(/^.*\./, "", tmpl)
        gc_role[sn] = tmpl
    }
}
{
    name = $1; attached = $2 + 0; sw = $3 + 0; agent = $4

    # Derive rig BEFORE the filter so per-rig state (rig_seen,
    # worker_count) covers hidden sessions too: the count includes ALL
    # worker sessions in the rig, visible+hidden, and rig_seen drives the
    # always-on per-rig header in the END block.
    slash = index(agent, "/")
    if (slash > 0) {
        rig = substr(agent, 1, slash - 1)
        display = substr(agent, slash + 1)
        rig_sort = rig
    } else if (name ~ /--/) {
        rig = name; sub(/--.*/, "", rig)
        rig_sort = rig
        # substr past "<rig>--" rather than a sub() on the prefix: a rig
        # name may itself contain "-".
        display = substr(name, length(rig) + 3)
        gsub(/__/, ".", display)
    } else if (agent != "") {
        rig = "city"; rig_sort = "0city"
        display = agent
    } else {
        rig = "city"; rig_sort = "0city"
        display = name
    }

    # One predicate for the count, the hide and the sort rank: they must
    # agree. A worker is a polecat and no other pooled role. A converse and
    # a pooled refinery hold state an operator goes to, whatever slot they
    # happen to run on. A session the map does not cover is not a worker:
    # the only other thing to read is the name, and the name carries the
    # slot rather than the role, so it hides converses and promotes
    # character-named codex polecats. Uncovered means shown and uncounted.
    role = gc_role[name]
    is_worker = (role == "polecat" || role ~ /^polecat-/)
    if (is_worker) worker_count[rig]++
    rig_sort_of[rig] = rig_sort
    rig_seen[rig] = 1

    if (!all && name != active) {
        if (is_worker) next
        if (name ~ /control-dispatcher/) next
        if (name ~ /deacon/) next
        if (name ~ /witness/) next
        if (name ~ /dog/) next
        if (name ~ /boot/) next
    }
    sub_pri = (is_worker ? 9 : 5)
    marker  = (attached > 0 ? "*" : " ")
    win_marker = (sw > 1 ? "▣" : " ")
    pc = pane_count[name] + 0

    # Resolve session title with boring-suppression + truncation. Normalize
    # both sides before comparing: strip a leading "<rig>/" from the title
    # (gc titles often carry the rig prefix that the picker collapses out
    # of the display column), and from the display a trailing "-adhoc-<hex>"
    # (ad-hoc sessions get an adhoc-suffix while their canonical title set
    # by the session-title producer skill does not) or "-pool" (a pool
    # instance is aliased "<qualified>-<n>" while its session name carries
    # the slot suffix too).
    title = gc_title[name]
    if (title != "") {
        title_cmp = title
        rig_pfx = rig "/"
        if (substr(title, 1, length(rig_pfx)) == rig_pfx) {
            title_cmp = substr(title, length(rig_pfx) + 1)
        }
        display_cmp = display
        sub(/-adhoc-[0-9a-f]+$/, "", display_cmp)
        sub(/-pool$/, "", display_cmp)
        if (title_cmp == display_cmp) {
            title = ""
        } else if (length(title) > 40) {
            title = substr(title, 1, 39) "…"
        }
    }

    # Session row — sort key cols 1-4 (rig_sort, sub_pri, name, "0"),
    # then payload (S, rig, marker, win_marker, name, display, title).
    printf "%s\t%d\t%s\t0\tS\t%s\t%s\t%s\t%s\t%s\t%s\n", \
        rig_sort, sub_pri, name, rig, marker, win_marker, name, display, title

    # Pane sub-rows (only when session has >1 pane). Sort key col 4
    # uses zero-padded "1_<window>_<pane>" so panes sort within a
    # session by window-then-pane index, always after the "0" session row.
    if (pc > 1) {
        for (k = 1; k <= pc; k++) {
            wi = pn_wi[name, k]; pi = pn_pi[name, k]; pa = pn_pa[name, k]
            cmd = pn_cmd[name, k]; title = pn_title[name, k]
            pane_marker = (pa ? "•" : " ")
            seq = sprintf("1_%05d_%05d", wi+0, pi+0)
            printf "%s\t%d\t%s\t%s\tP\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", \
                rig_sort, sub_pri, name, seq, \
                rig, pane_marker, name, wi, pi, cmd, title
        }
    }
}
END {
    # Header rows are collapsed-mode only. sub_pri=-1 (col 2) makes them
    # sort ahead of S (5) and P (9) rows within the same rig_sort group.
    # A header renders for every rig with sessions, even all-hidden ones —
    # the picker is topology awareness, and a rig whose workers are all
    # hidden must not vanish from the menu.
    if (all) exit
    for (r in rig_seen) {
        rs = rig_sort_of[r]
        pc = worker_count[r] + 0
        printf "%s\t-1\t\t\tH\t%s\t%d\n", rs, r, pc
    }
}' | sort -t"$TAB" -k1,1 -k2,2n -k3,3 -k4,4 | cut -f5-)

MAX_RIG=$(printf '%s\n' "$LIST" | awk -F"$TAB" 'NF { if (length($2) > m) m = length($2) } END { print (m+0) }')
[ -z "$MAX_RIG" ] || [ "$MAX_RIG" -lt 4 ] && MAX_RIG=4

# Max display width across S rows that carry a title — used to align the
# `│` divider column. Rows without a title do not pad out to the divider.
MAX_DISPLAY=$(printf '%s\n' "$LIST" | awk -F"$TAB" '$1 == "S" && $7 != "" { if (length($6) > m) m = length($6) } END { print (m+0) }')

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
menu_idx=0
ACTIVE_IDX=-1
emitted_header=0
while IFS="$TAB" read -r row_type rig c3 c4 c5 c6 c7 c8; do
    [ -z "$row_type" ] && continue
    if [ "$row_type" = "H" ]; then
        # Per-rig grouped header — disabled (leading `-`) so it renders but is
        # not selectable. Does NOT consume a hotkey slot. Blank separator
        # between groups, but not before the first header.
        count="$c3"
        if [ "$emitted_header" -eq 1 ]; then
            set -- "$@" "" "" ""
            menu_idx=$((menu_idx + 1))
        fi
        if [ "$count" -gt 0 ]; then
            if [ "$count" -eq 1 ]; then
                noun="polecat"
            else
                noun="polecats"
            fi
            label="-  ── $rig • $count $noun ──  "
        else
            label="-  ── $rig ──  "
        fi
        set -- "$@" "$label" "" ""
        menu_idx=$((menu_idx + 1))
        emitted_header=1
        continue
    fi
    pad=$((MAX_RIG - ${#rig}))
    [ "$pad" -lt 0 ] && pad=0
    if [ "$row_type" = "S" ]; then
        marker="$c3"; win_marker="$c4"; name="$c5"; display="$c6"; title="$c7"
        if [ -n "$title" ]; then
            dpad=$((MAX_DISPLAY - ${#display}))
            [ "$dpad" -lt 0 ] && dpad=0
            label=$(printf '  [%s]%*s  %s%s  %s%*s  │ %s  ' "$rig" "$pad" '' "$marker" "$win_marker" "$display" "$dpad" '' "$title")
        else
            label=$(printf '  [%s]%*s  %s%s  %s  ' "$rig" "$pad" '' "$marker" "$win_marker" "$display")
        fi
        cmd_str="switch-client -t $name"
    else
        # P row payload: c3=pane_marker, c4=name, c5=window, c6=pane, c7=cmd, c8=title
        pane_marker="$c3"; name="$c4"; window="$c5"; pane="$c6"; pcmd="$c7"; ptitle="$c8"
        # Truncate noisy titles so menu rows stay scannable. Keep cmd full —
        # short already (ps comm).
        if [ ${#ptitle} -gt 30 ]; then
            ptitle="$(printf '%s' "$ptitle" | cut -c1-30)…"
        fi
        # Blank rig column to preserve alignment under the parent session row;
        # ↳ + indent makes the sub-row relationship visible.
        label=$(printf '  [%*s]%*s    %s ↳ %s:%s.%s %s  %s  ' "${#rig}" '' "$pad" '' "$pane_marker" "$name" "$window" "$pane" "$pcmd" "$ptitle")
        cmd_str="switch-client -t $name ; select-window -t $name:$window ; select-pane -t $name:$window.$pane"
    fi
    if [ "$i" -le ${#HOTKEYS} ]; then
        key=$(printf '%s' "$HOTKEYS" | cut -c"$i")
    else
        key=""
    fi
    set -- "$@" "$label" "$key" "$cmd_str"
    [ "$row_type" = "S" ] && [ "$name" = "$ACTIVE" ] && ACTIVE_IDX=$menu_idx
    i=$((i+1))
    menu_idx=$((menu_idx+1))
done <<LIST_EOF
$LIST
LIST_EOF

set -- "$@" "" "" ""
# Preserve --city-path through the self-reinvoke (tmux's bare env).
reinvoke_suffix=""
[ -n "$EXPLICIT_CITY_PATH" ] && reinvoke_suffix=" --city-path $(sq "$EXPLICIT_CITY_PATH")"

# Fixed keeper pin/unpin entry (',' — a punctuation slot, like '.'): the
# on_demand keeper has no pane when drained, so it needs a standalone
# action. tmux-keeper-toggle.sh owns state detection and the toggle; an
# unanswerable state degrades to a neutral [ keeper… ] label (toggle
# re-reads state itself). run-shell -b so a slow pin cannot freeze tmux.
KEEPER_TOGGLE="$(dirname "$SCRIPT")/tmux-keeper-toggle.sh"
# shellcheck disable=SC2086 # ${EXPLICIT_CITY_PATH:+…} expands to 0 or 2 fields
case "$("$KEEPER_TOGGLE" ${EXPLICIT_CITY_PATH:+--city-path "$EXPLICIT_CITY_PATH"} state 2>/dev/null || echo unknown)" in
    up)   keeper_label="  [ ✕ unpin keeper ]  " ;;
    down) keeper_label="  [ ⚡ pin keeper ]  " ;;
    *)    keeper_label="  [ keeper… ]  " ;;
esac
set -- "$@" "$keeper_label" "," "run-shell -b \"$KEEPER_TOGGLE toggle$reinvoke_suffix\""

if [ "$ALL" -eq 1 ]; then
    set -- "$@" "  [ show fewer ]  " "." "run-shell \"$SCRIPT$reinvoke_suffix\""
else
    set -- "$@" "  [ show all ]  " "." "run-shell \"$SCRIPT --all$reinvoke_suffix\""
fi

if [ "$ACTIVE_IDX" -ge 0 ]; then
    gcmux display-menu -T "$MENU_TITLE" -x C -y C -C "$ACTIVE_IDX" -- "$@"
else
    gcmux display-menu -T "$MENU_TITLE" -x C -y C -- "$@"
fi
