#!/bin/sh
# tmux-pick-session.sh — Gas City session picker.
# Usage: tmux-pick-session.sh [--all]
#
# Default filter hides polecat-*, control-dispatcher, deacon, witness,
# dog, boot. The currently-attached session is always shown.
# --all disables the filter; toggle from inside the menu via [.].
#
# Rig + identity derivation (per-session GC_AGENT env):
#   - "<rig>/<pack>.<role>" → rig = <rig>,  display = <pack>.<role>
#   - "<pack>.<role>"       → rig = "city", display = <pack>.<role>
#   - empty (manual sessions) → fall back to legacy `--` substring on
#     the raw session name; display = raw session name.
# `switch-client -t` always targets the raw tmux session_name; the
# GC_AGENT-derived display is label-only.
#
# Sort order:
#   1. [city] group — alphabetical
#   2. each rig group, rigs alphabetical, polecats last within rig
#      (`/polecat/` substring on the parsed display name)
set -e

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
ACTIVE=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)

LIST=$(gcmux list-sessions -F '#{session_name}|#{session_attached}|#{E:GC_AGENT}' | awk -F'|' -v all="$ALL" -v active="$ACTIVE" '
{
    name = $1; attached = $2 + 0; agent = $3
    if (!all && name != active) {
        if (name ~ /polecat/) next
        if (name ~ /control-dispatcher/) next
        if (name ~ /deacon/) next
        if (name ~ /witness/) next
        if (name ~ /dog/) next
        if (name ~ /boot/) next
    }
    slash = index(agent, "/")
    if (slash > 0) {
        rig = substr(agent, 1, slash - 1)
        display = substr(agent, slash + 1)
        rig_sort = rig
    } else if (agent != "") {
        rig = "city"; rig_sort = "0city"
        display = agent
    } else if (name ~ /--/) {
        rig = name; sub(/--.*/, "", rig)
        rig_sort = rig
        display = name
    } else {
        rig = "city"; rig_sort = "0city"
        display = name
    }
    sub_pri = (display ~ /polecat/ ? 9 : 5)
    marker  = (attached > 0 ? "*" : " ")
    printf "%s_%d_%s\t%s\t%s\t%s\t%s\n", rig_sort, sub_pri, name, rig, marker, name, display
}' | sort | cut -f2-)

MAX_RIG=$(printf '%s\n' "$LIST" | awk -F'\t' 'NF { if (length($1) > m) m = length($1) } END { print (m+0) }')
[ -z "$MAX_RIG" ] || [ "$MAX_RIG" -lt 4 ] && MAX_RIG=4

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
menu_idx=0
ACTIVE_IDX=-1
TAB="$(printf '\t')"
while IFS="$TAB" read -r rig marker name display; do
    [ -z "$name" ] && continue
    [ -z "$display" ] && display=$name
    pad=$((MAX_RIG - ${#rig}))
    label=$(printf '  [%s]%*s  %s  %s  ' "$rig" "$pad" '' "$marker" "$display")
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
