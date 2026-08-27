#!/bin/sh
# tmux-pick-helm.sh — Gas City Helm picker (pick-a-row → land).
#
# Usage: tmux-pick-helm.sh [--city-path <path>] [--all]
#
# Renders `helm-svc board --json` (the Go board, services/helm) as a tmux
# display-menu; picking a row runs `gc-helm.sh open <bead>`, which files a VISIT
# on that bead so a converse session holds it. Bound as the sibling of the
# live-session picker (prefix+S = "what's running"; this = "what needs me").
#
# TWO MENUS, ONE SCRIPT. Bare, this renders the operator's QUEUE — what is owed
# by a person, oldest first, each row headlined by the demand itself. --all
# renders the city overview, headlined by the object, and is bound one keystroke
# away (prefix+B). They are the same rows, ranked and labelled to answer
# different questions, and the queue is the one a keystroke should reach first:
# the overview sorts by severity then subtree size, where a demand owed by a
# person has a subtree of one.
#
# The helm-svc binary is resolved at the path the launcher/builder deploy
# to (<state-root>/bin/helm-svc — see gc-helm-svc.sh / gc-helm-build.sh),
# falling back to PATH. An absent binary and an unreadable board each get their
# own line; neither is ever rendered as an empty board.
#
# --city-path is baked in by tmux-bindings.sh at install time so `gc`'s
# city discovery is deterministic from tmux's bare env.
set -e

CITY_PATH=""
ALL=""
MENU_TITLE=" Helm — what needs you "
while [ $# -gt 0 ]; do
    case "$1" in
        --city-path) CITY_PATH="${2:-}"; shift 2 ;;
        --all) ALL="--all"; MENU_TITLE=" Helm — city overview "; shift ;;
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
# An empty board and an unreadable one are opposite answers, so neither the
# exit code nor the stderr may be discarded here.
BOARD_ERR="$(mktemp "${TMPDIR:-/tmp}/gc-helm-pick.XXXXXX" 2>/dev/null || printf '')"
if [ -n "$BOARD_ERR" ]; then trap 'rm -f "$BOARD_ERR"' EXIT; fi
BOARD_RC=0
# The DONE band keeps an answered row in a view the operator leaves open.
# Neither menu here is that, and the one action either of them offers is `open`,
# so a closed row would spend a hotkey on something already answered.
BOARD=$(GC_HELM_DONE_WINDOW=0 "$HELM_SVC" board --json --limit=36 ${ALL:+--all} 2>"${BOARD_ERR:-/dev/null}") || BOARD_RC=$?

if [ "$BOARD_RC" -ne 0 ]; then
    WHY=""
    if [ -n "$BOARD_ERR" ]; then
        # One line for a one-line menu bar; a gather failure names every rig
        # in the city over several lines.
        WHY=$(tr '\n\t' '  ' < "$BOARD_ERR" | sed 's/  */ /g; s/^ *//; s/ *$//' | cut -c1-160)
    fi
    [ -n "$WHY" ] || WHY="helm-svc board exited $BOARD_RC with no diagnostic"
    gcmux display-message -d 10000 "Helm: BOARD UNREADABLE — $WHY"
    # Exit 0 like the missing-binary arm: the key is bound with a foreground
    # `run-shell`, which pops its own window over the message on a non-zero
    # status.
    exit 0
fi

COUNT=$(printf '%s' "$BOARD" | jq 'length' 2>/dev/null || echo 0)
case "$COUNT" in ''|*[!0-9]*) COUNT=0 ;; esac

if [ "$COUNT" -eq 0 ]; then
    if [ -n "$ALL" ]; then
        gcmux display-message -d 4000 "Helm: no open anchors need attention. (Nothing floats.)"
    else
        gcmux display-message -d 5000 "Helm: nothing needs you. prefix+B for the city overview."
    fi
    exit 0
fi

# Per-row command prefix: cd into the city so the open path resolves it.
CMD_PREFIX=""
[ -n "$CITY_PATH" ] && CMD_PREFIX="cd $(sq "$CITY_PATH") && "
SQ_ATTN=$(sq "$ATTN")

# One TSV row per anchor: held, severity, id, rig, title, frontier, needs.
#
# Every cell carries a placeholder when it is empty. IFS=TAB is IFS WHITESPACE,
# so an empty field collapses against its neighbour and every later column
# shifts left — a row with no title would render its frontier as its title.
ROWS=$(printf '%s' "$BOARD" | jq -r '
    def nz(v; d): (v // "") | if . == "" then d else . end;
    .[] | [(if .held then "●" else "·" end), nz(.severity; "?"), .id, nz(.rig; "?"),
           (nz(.title; "—")[0:38]), (nz(.frontier; "—")[0:34]),
           (nz(.needs; "—")[0:48])] | @tsv')

HOTKEYS="abcdefghijklmnopqrstuvwxyz0123456789"
set --
i=1
while IFS="$TAB" read -r glyph sev id rig title frontier needs; do
    [ -n "$id" ] || continue
    # The queue's headline is the DEMAND — helm-svc puts the authored
    # gc.takeaway in `needs`, and what the operator owes is the whole reason the
    # row is on this menu. The bead's own title names the object and follows it.
    # The overview asks the other question, so it leads with the object.
    if [ -n "$ALL" ]; then
        label=$(printf '  %s %-8s %-11s [%s] %s — %s  ' "$glyph" "$sev" "$id" "$rig" "$title" "$frontier")
    else
        label=$(printf '  %s %-8s %-11s [%s] %s — %s  ' "$glyph" "$sev" "$id" "$rig" "$needs" "$title")
    fi

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

gcmux display-menu -T "$MENU_TITLE" -x C -y C -- "$@"
