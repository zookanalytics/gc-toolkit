#!/bin/sh
# tmux-pick-helm.sh — Gas City Helm picker (pick-a-row → land).
#
# Usage: tmux-pick-helm.sh [--city-path <path>]
#
# Renders the ranked board from `helm-svc board --json` (the Go board,
# services/helm) as a tmux display-menu; picking a row runs
# `gc-helm.sh open <bead>`, which files a VISIT on that bead so a converse
# session holds it. Bound as the sibling of the live-session picker
# (prefix+S = "what's running"; this = "what needs me").
#
# The helm-svc binary is resolved at the path the launcher/builder deploy
# to (<state-root>/bin/helm-svc — see gc-helm-svc.sh / gc-helm-build.sh),
# falling back to PATH; absent, the picker shows one clear line and exits.
#
# --city-path is baked in by tmux-bindings.sh at install time so `gc`'s
# city discovery is deterministic from tmux's bare env.
set -e

CITY_PATH=""
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; shift 2 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
TAB="$(printf '\t')"

# sq <string> — POSIX shell-quote $1 for safe embedding in a run-shell body.
sq() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
ATTN="$(dirname "$SCRIPT")/gc-helm.sh"
[ -x "$ATTN" ] || { gcmux display-message -d 4000 "Helm: gc-helm.sh not found"; exit 0; }

# Deterministic city discovery from tmux's bare env.
if [ -n "$CITY_PATH" ]; then
    export GC_CITY_PATH="$CITY_PATH"
    cd "$CITY_PATH" 2>/dev/null || true
fi

# Resolve helm-svc at its deployed path: GC_SERVICE_STATE_ROOT when set (the
# supervisor's env), else the default state root under the city, else PATH.
HELM_SVC=""
for cand in \
    "${GC_SERVICE_STATE_ROOT:+$GC_SERVICE_STATE_ROOT/bin/helm-svc}" \
    "${GC_CITY_PATH:+$GC_CITY_PATH/.gc/services/helm/bin/helm-svc}"; do
    [ -n "$cand" ] && [ -x "$cand" ] && { HELM_SVC="$cand"; break; }
done
[ -n "$HELM_SVC" ] || HELM_SVC="$(command -v helm-svc 2>/dev/null || true)"
if [ -z "$HELM_SVC" ]; then
    gcmux display-message -d 6000 "Helm: helm-svc binary not found (build it: assets/scripts/gc-helm-build.sh)"
    exit 0
fi

# Cap at the hotkey alphabet (a-z0-9 = 36) so every row is one keystroke.
BOARD=$("$HELM_SVC" board --json --limit=36 2>/dev/null || printf '[]')
COUNT=$(printf '%s' "$BOARD" | jq 'length' 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

if [ "$COUNT" -eq 0 ]; then
    gcmux display-message -d 4000 "Helm: nothing needs you. (Nothing floats.)"
    exit 0
fi

# Per-row command prefix: cd into the city so the open path resolves it.
CMD_PREFIX=""
[ -n "$CITY_PATH" ] && CMD_PREFIX="cd $(sq "$CITY_PATH") && "
SQ_ATTN=$(sq "$ATTN")

# One TSV row per anchor: held, severity, id, rig, title, frontier.
ROWS=$(printf '%s' "$BOARD" | jq -r '
    .[] | [(if .held then "●" else "·" end), (.severity//"?"), .id, (.rig//"?"),
           ((.title//"")[0:38]), ((.frontier//"")[0:34])] | @tsv')

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
while IFS="$TAB" read -r glyph sev id rig title frontier; do
    [ -n "$id" ] || continue
    label=$(printf '  %s %-8s %-11s [%s] %s — %s  ' "$glyph" "$sev" "$id" "$rig" "$title" "$frontier")

    # Background the open: a cold visit-file plus converse spawn takes
    # seconds and must never freeze the tmux server.
    cmd="run-shell -b \"${CMD_PREFIX}${SQ_ATTN} open ${id}\""

    if [ "$i" -le ${#HOTKEYS} ]; then
        key=$(printf '%s' "$HOTKEYS" | cut -c"$i")
    else
        key=""
    fi
    set -- "$@" "$label" "$key" "$cmd"
    i=$((i + 1))
done <<ROWS_EOF
$ROWS
ROWS_EOF

gcmux display-menu -T " Helm — what needs you " -x C -y C -- "$@"
