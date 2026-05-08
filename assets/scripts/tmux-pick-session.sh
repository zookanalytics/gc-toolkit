#!/bin/sh
# tmux-pick-session.sh — Gas City session picker.
# Companion design notes: tmux-pick-session.md (alongside this file).
#
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
#   Pane sub-rows always appear directly under their session row.
#
# Visual indicators:
#   *  — session is attached
#   ▣  — session has more than one tmux window (interactive working
#         environment, vs single-window agent runtimes)
#   •  — pane is the active pane within its window (only on inline
#         pane sub-rows)
#
# Sessions with more than one pane get inline pane sub-rows in the
# SAME display-menu (NOT a chained sub-menu, NOT a popup). We can't
# use `choose-tree -F` because its leading "session: window: pane:"
# triplet is hardcoded in tmux's window-tree.c and ignores the format
# flag. See tmux-pick-session.md for the full rationale, alternatives
# considered, and hotkey allocation rule.
set -e

ALL=0
[ "${1:-}" = "--all" ] && ALL=1

gcmux() { tmux ${GC_TMUX_SOCKET:+-L "$GC_TMUX_SOCKET"} "$@"; }
SCRIPT="$(readlink -f "$0" 2>/dev/null || echo "$0")"
ACTIVE=$(gcmux display-message -p '#{client_session}' 2>/dev/null || true)
TAB="$(printf '\t')"

# One row per pane across all sessions. pane_title can contain `|`,
# so the awk pre-pass joins fields 6+ back into the title.
PANES=$(gcmux list-panes -aF '#{session_name}|#{window_index}|#{pane_index}|#{pane_active}|#{pane_current_command}|#{pane_title}' 2>/dev/null || true)

LIST=$(gcmux list-sessions -F '#{session_name}|#{session_attached}|#{session_windows}|#{E:GC_AGENT}' | awk -F'|' \
    -v all="$ALL" -v active="$ACTIVE" -v panes="$PANES" '
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
}
{
    name = $1; attached = $2 + 0; sw = $3 + 0; agent = $4
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
    win_marker = (sw > 1 ? "▣" : " ")
    pc = pane_count[name] + 0

    # Session row — sort key cols 1-4 (rig_sort, sub_pri, name, "0"),
    # then payload (S, rig, marker, win_marker, name, display).
    printf "%s\t%d\t%s\t0\tS\t%s\t%s\t%s\t%s\t%s\n", \
        rig_sort, sub_pri, name, rig, marker, win_marker, name, display

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
}' | sort -t"$TAB" -k1,1 -k2,2n -k3,3 -k4,4 | cut -f5-)

MAX_RIG=$(printf '%s\n' "$LIST" | awk -F"$TAB" 'NF { if (length($2) > m) m = length($2) } END { print (m+0) }')
[ -z "$MAX_RIG" ] || [ "$MAX_RIG" -lt 4 ] && MAX_RIG=4

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
menu_idx=0
ACTIVE_IDX=-1
while IFS="$TAB" read -r row_type rig c3 c4 c5 c6 c7 c8; do
    [ -z "$row_type" ] && continue
    pad=$((MAX_RIG - ${#rig}))
    [ "$pad" -lt 0 ] && pad=0
    if [ "$row_type" = "S" ]; then
        marker="$c3"; win_marker="$c4"; name="$c5"; display="$c6"
        label=$(printf '  [%s]%*s  %s%s  %s  ' "$rig" "$pad" '' "$marker" "$win_marker" "$display")
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
