#!/usr/bin/env bash
# deferred-dispatch.sh — a pending dispatch is a fact about the work, so it
# lives on the work bead, not in an agent's context. `gc sling` pours
# immediately and reads no `blocks` deps, so sequencing needs a durable hold:
#   arm <bead> --target <agent> [--sling-arg --on --sling-arg <formula>] [--reason "..."]
# records the arm through `gctk bead arm`, and the deferred-dispatch order's
# pass, `gctk bead start-armed` (orders/deferred-dispatch.toml, cooldown,
# scope="rig"), slings the bead once nothing holds it (docs/deferred-dispatch.md).
# `arm` and `disarm` hand their calls to gctk's bead verbs, which own the arm's
# keys and hold the bead's dispatch lock: this script keeps them for the callers
# that name it, until they call the verbs. `list` answers "what dispatches are
# owed?" from the start's dry run, naming what holds each held arm.
#
# `arm` is the default move for a blocked follow-up you file or keep back by
# hand: arm it instead of leaving it unrouted for someone to route once its
# blocker lands, and the start routes it the moment nothing holds it, so a
# sitting can queue everything and drain, with nothing left to remember. The
# bead resolves by id, so the arm lands from any seat, rig-scoped or not.
# Callers: agents sequencing dependent work; first-reaction-dispose.sh
# --then-route. Work for a named agent takes no arm: Gas City's hand-off
# reaches it (docs/deferred-dispatch.md).
# doctor/check-blocked-work-armed flags a blocked work bead that was never
# armed and carries no route.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="deferred-dispatch"

# The store, pinned: `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read in a rig-scoped env answers about
# whatever rig gc resolves rather than the one meant. `--db` overrides it.
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"

# The arm's verbs, its start and its dry run are gctk's, from the binary the
# city builds.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
# Answers in $REPLY rather than on stdout, because a caller writing
# `f="$(mktemp_tracked)"` would run the append inside a command-substitution
# subshell: the registry the EXIT trap reads is the caller's, and the
# subshell's copy of it dies with the substitution, leaking every allocation.
mktemp_tracked() { REPLY="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch.XXXXXX")" || return 1; TMPFILES+=("$REPLY"); }

bd_() {
    if [ -n "$BD_DB" ]; then gc bd --db "$BD_DB" "$@"; else gc bd "$@"; fi
}

actor() { printf '%s' "${GC_AGENT:-${BEADS_ACTOR:-${USER:-unknown}}}"; }

usage() {
    cat <<'EOF'
Usage:
  deferred-dispatch.sh arm <bead> --target <agent> [--sling-arg --on --sling-arg <formula>] [--reason <text>] [--db <path>]
  deferred-dispatch.sh disarm <bead> [--reason <text>] [--db <path>]
  deferred-dispatch.sh list [--db <path>]
  deferred-dispatch.sh list --json [--db <path>]

Verbs:
  arm        Record a pending dispatch on <bead>, through gctk bead arm: the
             deferred-dispatch order's pass (gctk bead start-armed) slings it
             once nothing holds it. This is the move for a blocked follow-up
             you file or keep back by hand: arm it instead of leaving it
             unrouted for someone to route once its blocker lands, so you can
             queue everything and drain with nothing to remember. The formula
             is the one --sling-arg --on names, or the target's default. gctk
             bead arm refuses a bead that is not open, is dispatched already, is
             armed another way, or waits on a bead in another store.
  disarm     Remove a pending dispatch, through gctk bead disarm. The bead is
             left otherwise untouched, and a bead with no arm is a success
             that writes nothing.
  list       Show every armed bead in this store and what the next pass of the
             start would do with it, as its dry run says: held (and by what),
             dispatchable, closed or delivered, stranded or capped. With --json
             it prints the armed beads alone, as bd lists them, with no hold.

--sling-arg names the formula the start pours, as the pair --on <formula>
(e.g. --sling-arg --on --sling-arg mol-pr-from-issue); an arm passes gc sling
nothing else.
EOF
}

# gctk_bead <verb> [args...] runs gctk's bead verb in the store this call is
# pinned to, and returns its exit.
gctk_bead() {
    local verb="$1"; shift
    [ -x "$GCTK" ] || { echo "$PROG: no gctk binary at '$GCTK' to run gctk bead $verb; GCTK_BIN names one, or GC_CITY_PATH the city whose build it is" >&2; return 1; }
    "$GCTK" bead "$verb" "$@" ${BD_DB:+--db "$BD_DB"}
}

# --- arm ---------------------------------------------------------------------
# The --sling-arg values an arm records are the formula it pours, --on and its
# value, or none for the target's default: gctk bead arm takes nothing else.
cmd_arm() {
    local bead="" target="" reason="" args=() formula=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: arm requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) shift; target="${1:-}" ;;
            --reason) shift; reason="${1:-}" ;;
            --sling-arg) shift; args+=("${1:-}") ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: arm: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    [ -n "$target" ] || { echo "$PROG: arm requires --target <agent>" >&2; return 2; }
    case "${#args[@]}" in
        0) ;;
        1) case "${args[0]}" in --on=?*) formula="${args[0]#--on=}" ;; *) formula="" ;; esac ;;
        2) [ "${args[0]}" = --on ] && formula="${args[1]}" ;;
    esac
    if [ "${#args[@]}" -gt 0 ] && [ -z "$formula" ]; then
        echo "$PROG: arm: --sling-arg names the formula the start pours, as --on <formula>, and nothing else (got: ${args[*]})" >&2
        return 2
    fi
    gctk_bead arm "$bead" --target "$target" ${formula:+--on "$formula"} \
        --reason "${reason:-no reason was given}"
}

# --- disarm ------------------------------------------------------------------
# The verb removes the arm through gctk bead disarm, and its exit is the verb's.
cmd_disarm() {
    local bead="" reason=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: disarm requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --reason) shift; reason="${1:-}" ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: disarm: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    reason="${reason:-disarmed by $(actor)}"
    gctk_bead disarm "$bead" --reason "$reason"
}

# --- list --------------------------------------------------------------------
# The jq defs that print one dry-run line of `gctk bead start-armed` for a
# person: the state the start would leave the arm in, its first wait named by
# its bead and that bead's title when a wait holds it, then the arm's reason.
# shellcheck disable=SC2016  # jq source; its $names are jq's
LIST_JQ='
  def wait_label:
    (if ((.title // "") | tostring) != "" then "\(.id) \"\(.title)\"" else (.id | tostring) end)
    + (if .type == "waits-for" then " (waits-for, unjudged)" else "" end)
    + (if ((.ancestor // "") | tostring) != "" then " on ancestor \(.ancestor)" else "" end);
  def holds_line:
    (.waits // []) as $w
    | (if ($w | length) == 0 then "a wait"
       else ($w[0] | wait_label) + (if ($w | length) > 1 then " (+\($w | length - 1) more)" else "" end) end);
  def state:
    (.start // {}) as $s
    | if $s.action == "retire" and $s.case == "closed" then "CLOSED (dispatch no longer owed; the next pass retires the arm)"
      elif $s.action == "retire" then "DELIVERED — \($s.why)"
      elif $s.action == "start" then "DISPATCHABLE NOW" + (if ((.in_flight // "") != "") then " (in flight, \(.in_flight))" else "" end)
      elif $s.action == "sent" then "SENT — \($s.why)"
      elif $s.action == "hold" and ($s.case == "blocked" or $s.case == "held" or $s.case == "unjudged") then "HELD by " + holds_line
      elif $s.action == "hold" and $s.case == "status" then "STRANDED — \($s.why)"
      elif $s.action == "hold" then "HELD — \($s.why)"
      elif $s.action == "ask" and $s.case == "cap" then "CAPPED — \($s.why)"
      elif $s.action == "ask" then "UNFINISHED POUR — \($s.why)"
      elif $s.action == "fail" and $s.case == "malformed" then "MALFORMED — \($s.why)"
      elif $s.action == "fail" then "UNREAD — \($s.why)"
      else "\(($s.action // "?") | ascii_upcase) — \($s.why // "")" end;
  "\(.id) -> \((.arm // {}).target // "?") [\(state)]"
    + (if (((.arm // {}).reason // "") | tostring) != "" then " — \(.arm.reason)" else "" end)
  | gsub("[[:cntrl:]]"; " ")
'

cmd_list() {
    local as_json=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --json) as_json=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: list: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    # --json prints the armed beads as bd lists them and says nothing about what
    # holds them, so it makes that one read. A read that fails or answers no
    # array fails the verb, since an unreadable queue is not an empty one.
    if [ "$as_json" = 1 ]; then
        local listed
        listed="$(bd_ list --has-metadata-key gc.dispatch_when_ready --all --json --limit 0 2>/dev/null)" \
            && printf '%s' "$listed" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 \
            || { echo "$PROG: list: could not enumerate armed beads" >&2; return 1; }
        printf '%s\n' "$listed"
        return 0
    fi

    # The arms, as the start's dry run reads each one. Its exit 1 says an arm's
    # act failed, such as a read it could not make, and its line says why; a run
    # that printed no line at all, or exited otherwise, could not list them.
    local runs rc=0 n=0 line
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; runs="$REPLY"
    gctk_bead start-armed --dry-run > "$runs" 2>/dev/null || rc=$?
    if [ "$rc" -gt 1 ] || { [ "$rc" = 1 ] && [ ! -s "$runs" ]; }; then
        echo "$PROG: list: could not enumerate armed beads" >&2; return 1
    fi
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        n=$((n + 1))
        printf '%s\n' "$line"
    done < <(scrub < "$runs" | jq -r "$LIST_JQ" 2>/dev/null)
    [ "$n" -gt 0 ] || echo "$PROG: no pending dispatches in this store"
    return 0
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    arm)       cmd_arm "$@" ;;
    disarm)    cmd_disarm "$@" ;;
    list)      cmd_list "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
