#!/bin/sh
# tmux-pick-session.sh — Gas City session picker.
# Usage: tmux-pick-session.sh [--all]
#
# Default filter hides polecat-*, control-dispatcher, deacon, witness,
# dog, boot. The currently-attached session is always shown.
# --all disables the filter; toggle from inside the menu via [.].
#
# Sort order:
#   1. [city] group (sessions with no `--` in name) — alphabetical
#   2. each rig group, rigs alphabetical, polecats last within rig
set -e

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
ACTIVE=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)

LIST=$(gcmux list-sessions -F '#{session_name}|#{session_attached}' | awk -F'|' -v all="$ALL" -v active="$ACTIVE" '
{
    name = $1; attached = $2 + 0
    if (!all && name != active) {
        if (name ~ /polecat/) next
        if (name ~ /control-dispatcher/) next
        if (name ~ /deacon/) next
        if (name ~ /witness/) next
        if (name ~ /dog/) next
        if (name ~ /boot/) next
    }
    if (name ~ /--/) {
        rig = name; sub(/--.*/, "", rig)
        rig_sort = rig
    } else {
        rig = "city"; rig_sort = "0city"
    }
    sub_pri = (name ~ /polecat/ ? 9 : 5)
    marker  = (attached > 0 ? "*" : " ")
    printf "%s_%d_%s\t%s\t%s\t%s\n", rig_sort, sub_pri, name, rig, marker, name
}' | sort | cut -f2-)

MAX_RIG=$(printf '%s\n' "$LIST" | awk -F'\t' 'NF { if (length($1) > m) m = length($1) } END { print (m+0) }')
[ -z "$MAX_RIG" ] || [ "$MAX_RIG" -lt 4 ] && MAX_RIG=4

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
menu_idx=0
ACTIVE_IDX=-1
TAB="$(printf '\t')"
while IFS="$TAB" read -r rig marker name; do
    [ -z "$name" ] && continue
    pad=$((MAX_RIG - ${#rig}))
    label=$(printf '  [%s]%*s  %s  %s  ' "$rig" "$pad" '' "$marker" "$name")
    if [ "$i" -le ${#HOTKEYS} ]; then
        key=$(printf '%s' "$HOTKEYS" | cut -c"$i")
    else
        key=""
    fi
    set -- "$@" "$label" "$key" "switch-client -t $name"
    [ "$name" = "$ACTIVE" ] && ACTIVE_IDX=$menu_idx
    i=$((i+1))
    menu_idx=$((menu_idx+1))
done <<LIST_EOF
$LIST
LIST_EOF

set -- "$@" "" "" ""
if [ "$ALL" -eq 1 ]; then
    set -- "$@" "  [ show fewer ]  " "." "run-shell '$SCRIPT'"
else
    set -- "$@" "  [ show all ]  " "." "run-shell '$SCRIPT --all'"
fi

if [ "$ACTIVE_IDX" -ge 0 ]; then
    gcmux display-menu -T " Sessions " -x C -y C -C "$ACTIVE_IDX" "$@"
else
    gcmux display-menu -T " Sessions " -x C -y C "$@"
fi
