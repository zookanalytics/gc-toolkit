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
# Work assigned to a named agent owes a notice, not a sling (`notify`). A named
# session's hook offers it a bead by the bead's assignee once bd reports the
# bead ready, and under wake_mode = "resume" nothing wakes an idle named session
# into that hook when a wait lifts. So `notify` mails the agent at once when bd
# already reports the bead ready, and otherwise records the notice on the bead.
# A notice waits on bd's readiness, the predicate the hook reads, and not on what
# gctk bead holds answers: a bead bd keeps unready is one the hook does not
# offer, and a notice then would wake the agent for nothing. A notice is done
# once the agent's turn is requested, not once its mail is saved, because mail
# alone requests no turn; until then the record stays.
#
# `arm` is the default move for a blocked follow-up you file or keep back by
# hand: arm it instead of leaving it unrouted for someone to route once its
# blocker lands, and the start routes it the moment nothing holds it, so a
# sitting can queue everything and drain, with nothing left to remember. The
# bead resolves by id, so the arm lands from any seat, rig-scoped or not.
# Callers: agents sequencing dependent work; first-reaction-dispose.sh
# --then-route (arm) and --assign/--then-assign (notify).
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

# A notice owed to the named agent a bead is assigned to. Its presence is the
# record, and its value is the agent the notice goes to. The record stays until
# the agent's turn is requested. A repeat mints nothing, so a notice needs no
# marker or counter: the mail's dedup key keeps a second copy out of the agent's
# mailbox while the first notice about the bead is still there.
K_NOTIFY="gc.notify_when_ready"
NOTICE_DEDUP_PREFIX="ready-notice:"

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

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

actor() { printf '%s' "${GC_AGENT:-${BEADS_ACTOR:-${USER:-unknown}}}"; }

usage() {
    cat <<'EOF'
Usage:
  deferred-dispatch.sh arm <bead> --target <agent> [--sling-arg --on --sling-arg <formula>] [--reason <text>] [--db <path>]
  deferred-dispatch.sh notify <bead> --agent <named-agent> [--reason <text>] [--db <path>]
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
  notify     Tell <named-agent> that <bead>, assigned to it, is ready for its
             hook: gc mail send --notify, which requests the agent's turn and
             wakes it when it is not running, with the bead id in the mail.
             Under wake_mode = "resume" nothing else wakes an idle named
             session for a new assignee. The mail goes at once when bd
             reports the bead ready; otherwise the notice is recorded on the
             bead. When the mail requests no turn, because the send or its turn
             request failed or because an earlier notice about the bead is
             still in the agent's mailbox, gc session nudge requests it. The
             notice stays recorded until a turn is requested. The bead must be
             assigned to <named-agent>. A closed bead, or one the agent already
             claimed, owes no notice and exits 0.
  disarm     Remove a pending dispatch, through gctk bead disarm, and any
             notice owed. The bead is left otherwise untouched.
  list       Show every armed bead in this store and what the next pass of the
             start would do with it, as its dry run says: held (and by what),
             dispatchable, closed or delivered, stranded or capped; then every
             notice owed, and whether bd reports its bead ready. With --json it
             prints the armed beads alone, as bd lists them: no hold, and no
             notice owed.

--sling-arg names the formula the start pours, as the pair --on <formula>
(e.g. --sling-arg --on --sling-arg mol-pr-from-issue); an arm passes gc sling
nothing else.
EOF
}

# `bd show --json` answers an array on a hit and an {"error":...} object on a
# miss, both at rc=0 — discriminate on type, not exit status.
show_bead() { # id -> single bead object on stdout, or nothing (rc 1)
    local id="$1" raw
    raw="$(bd_ show "$id" --json 2>/dev/null)" || return 1
    printf '%s' "$raw" | scrub | jq -c '
        if type == "array" then (.[0] // empty)
        elif type == "object" then (if has("error") then empty else . end)
        else empty end' 2>/dev/null
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
# The verb withdraws everything this script owes on the bead: the arm, through
# gctk bead disarm, and then any notice owed, in a write of its own.
cmd_disarm() {
    local bead="" reason="" json agent
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
    gctk_bead disarm "$bead" --reason "$reason" || return 1
    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: disarm: could not read $bead to clear any notice owed on it" >&2; return 1; }
    agent="$(printf '%s' "$json" | jq -r --arg k "$K_NOTIFY" '(.metadata[$k] // "") | tostring' 2>/dev/null)" || agent=""
    [ -n "$agent" ] || return 0
    bd_ update "$bead" --unset-metadata "$K_NOTIFY" \
        --append-notes "$PROG: notice record cleared at $(now_utc) — $reason" >/dev/null 2>&1 || {
            echo "$PROG: disarm: failed to clear the notice owed on $bead" >&2; return 1; }
    echo "$PROG: cleared the notice to $agent on $bead"
}

# --- notify ------------------------------------------------------------------
# A child's stderr as one line, for the log line that says why the child failed.
stderr_text() { # file
    local text
    text="$(awk 'NF { printf "%s%s", sep, $0; sep = "; " }' "$1" 2>/dev/null | scrub)"
    printf '%s' "${text:-it printed no cause}"
}

# send_notice <id> <agent> [<title>] — tell <agent> that <id> is ready for it,
# and succeed only once the agent's turn is requested. The mail names the bead,
# and its --notify requests the turn, waking the agent when it is not running.
# gc mail send saves the mail before it requests the turn and still exits 0 when
# that request fails, so the proof is `notified` in its --json result, not its
# exit status. The dedup key keeps a second copy out of the agent's mailbox
# while the first notice about <id> is still there, and a send it suppresses
# requests no turn either. So whenever the mail requests none, whether the send
# failed, its turn request failed or the dedup key suppressed it, gc session
# nudge requests it, and that command's exit status is its outcome. Its
# --reference-bead makes a nudge still queued for the agent about <id> give way
# to this one. Whether the nudge succeeds or fails, its log line says why the
# mail requested no turn, with what gc mail send printed.
send_notice() {
    local id="$1" agent="$2" title="${3:-}" text out err why
    text="$id${title:+ ($title)} is assigned to you and ready to claim: run gc hook to pick it up."
    mktemp_tracked || { echo "$PROG: could not notify $agent that $id is ready: mktemp failed" >&2; return 1; }
    err="$REPLY"
    if ! out="$(gc mail send "$agent" --notify --dedup "$NOTICE_DEDUP_PREFIX$id" --json \
            -s "Ready for you: $id" -m "$text" 2>"$err")"; then
        why="gc mail send could not mail $agent about $id ($(stderr_text "$err"))"
    elif printf '%s' "$out" | scrub | jq -e 'select(type == "object") | .notified == true' >/dev/null 2>&1; then
        return 0
    elif printf '%s' "$out" | scrub | jq -e 'select(type == "object") | .already_done == true' >/dev/null 2>&1; then
        why="the notice mailed about $id earlier is still in its mailbox, so the dedup key sent no new mail and requested no turn"
    else
        why="the mail was saved but requested no turn ($(stderr_text "$err"))"
    fi
    if ! gc session nudge "$agent" "Ready for you: $text" --reference-bead "$id" >/dev/null 2>"$err"; then
        echo "$PROG: could not request $agent's turn for $id: $why, and gc session nudge failed: $(stderr_text "$err")" >&2
        return 1
    fi
    echo "$PROG: requested $agent's turn for $id with gc session nudge: $why"
}

# Why a notice to <agent> is no longer owed on a bead at <status> assigned to
# <assignee>, or nothing while it is owed.
notice_unowed_why() { # status assignee agent
    if [ "$1" = "closed" ]; then
        printf '%s' "the bead closed, so no notice is owed"
    elif [ "$2" != "$3" ]; then
        printf '%s' "the bead is no longer assigned to $3${2:+ (its assignee is $2)}, so the notice is moot"
    elif [ "$1" = "in_progress" ]; then
        printf '%s' "$3 already claimed the bead, so no notice is owed"
    fi
}

# retire_notice <sent|unowed> <id> <agent> — clear the notice on <id> once it
# was sent to <agent>, or once it is no longer owed to <agent>. The caller read
# <agent> from a listing, and notify can record a notice for another agent
# after that read, when the bead is reassigned while a pass runs. That notice
# belongs to the new agent, so the retire re-reads the bead and clears the
# record only while it still names <agent>. An unowed retire also needs the
# fresh read to show the notice still unowed, and records the reason that read
# gives. The fresh fields have their control characters replaced, as
# notice_rows prints them, so the two reads compare alike. bd has no
# conditional unset, so a notice recorded between the re-read and the unset is
# still lost. The re-read narrows that window from the pass's whole run to the
# gap between two store calls.
# rc 0: cleared, or already clear. rc 1: the bead was unreadable, or the write
# failed. rc 3: left, because the record names another agent now or the notice
# is owed again; RETIRE_NOTE says which. RETIRE_WHY is the reason recorded.
retire_notice() {
    local mode="$1" id="$2" agent="$3" json fresh f_status f_assignee f_agent
    RETIRE_NOTE=""
    RETIRE_WHY="notice sent to $agent: bd reports the bead ready"
    json="$(show_bead "$id")" || json=""
    [ -n "$json" ] || return 1
    fresh="$(printf '%s' "$json" | jq -r --arg k "$K_NOTIFY" '
        [ (.status // ""), (.assignee // ""), ((.metadata // {})[$k] // "") ]
        | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' 2>/dev/null)" || return 1
    IFS=$'\037' read -r f_status f_assignee f_agent <<< "$fresh"
    [ -n "$f_agent" ] || return 0
    if [ "$f_agent" != "$agent" ]; then
        RETIRE_NOTE="its record now names $f_agent, a notice recorded since it was read, so it stays for that notice's own send"
        return 3
    fi
    if [ "$mode" = unowed ]; then
        RETIRE_WHY="$(notice_unowed_why "$f_status" "$f_assignee" "$agent")"
        if [ -z "$RETIRE_WHY" ]; then
            RETIRE_NOTE="a fresh read shows the notice to $agent owed again, so it stays for the next pass"
            return 3
        fi
    fi
    bd_ update "$id" --unset-metadata "$K_NOTIFY" \
        --append-notes "$PROG: notice record cleared at $(now_utc) — $RETIRE_WHY" >/dev/null 2>&1
}

# One line per bead that carries a notice record:
# "<id>\037<status>\037<assignee>\037<agent>\037<bd_ready 0|1>\037<title>".
# The ready column is bd's answer for the bead, the readiness the agent's hook
# reads. Every column has its control characters replaced inside jq. The scrub
# removes only raw bytes, and jq decodes an escaped LF or unit separator in a
# string and prints it raw, so a title, an assignee or a notice value carrying
# one would split the line into a second row, with whatever bead, agent and
# readiness it spells, or shift its columns. Unreadable is not empty: a listing
# that fails, or answers no array, fails the read. A store that owes no notice
# costs the one listing, since there is nothing to ask bd's readiness about.
# Both snapshots reach jq over stdin, as armed_rows' do.
notice_rows() { # out
    local out="$1" all ready
    all="$(bd_ list --has-metadata-key "$K_NOTIFY" --all --brief --json --limit 0 2>/dev/null)" || return 1
    printf '%s' "$all" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    if printf '%s' "$all" | scrub | jq -e 'length == 0' >/dev/null 2>&1; then
        : > "$out"
        return
    fi
    ready="$(bd_ list --has-metadata-key "$K_NOTIFY" --ready --brief --json --limit 0 2>/dev/null)" || return 1
    printf '%s' "$ready" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    { printf '%s' "$ready" | scrub; printf '\n'; printf '%s' "$all" | scrub; } | jq -rn --arg k "$K_NOTIFY" '
        (input | map(.id)) as $ready
        | input | .[]
        | [ (.id // ""), (.status // ""), (.assignee // ""), ((.metadata // {})[$k] // ""),
            (if (.id as $i | $ready | index($i)) then "1" else "0" end), (.title // "") ]
        | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' > "$out" 2>/dev/null
}

cmd_notify() {
    local bead="" agent="" reason="" json status assignee rows
    local id rdy title ready="" bead_title=""
    bead="${1:-}"; shift || true
    case "$bead" in ""|-*) echo "$PROG: notify requires a bead id" >&2; return 2 ;; esac
    while [ $# -gt 0 ]; do
        case "$1" in
            --agent) shift; agent="${1:-}" ;;
            --reason) shift; reason="${1:-}" ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: notify: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    [ -n "$agent" ] || { echo "$PROG: notify requires --agent <named-agent>" >&2; return 2; }

    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: notify: $bead does not resolve in this store" >&2; return 1; }
    status="$(printf '%s' "$json" | jq -r '.status // ""')"
    assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
    if [ "$status" = "closed" ]; then
        echo "$PROG: $bead is closed, so no notice is owed"
        return 0
    fi
    if [ "$assignee" != "$agent" ]; then
        echo "$PROG: notify: $bead is not assigned to $agent${assignee:+ (its assignee is $assignee)}, and a notice is owed only for an assignment. Assign it first: gc bd update $bead --assignee $agent" >&2
        return 1
    fi
    if [ "$status" = "in_progress" ]; then
        echo "$PROG: $agent already claimed $bead, so no notice is owed"
        return 0
    fi

    # The record goes down first, so the notice is owed from here on: a read
    # that cannot tell whether the bead is ready, or a notice that gets the
    # agent no turn, leaves it for the next reconcile pass.
    bd_ update "$bead" --set-metadata "$K_NOTIFY=$agent" \
        --append-notes "$PROG: notice armed by $(actor) at $(now_utc) — tells $agent once bd reports this bead ready${reason:+ — $reason}" >/dev/null 2>&1 || {
            echo "$PROG: notify: failed to record the notice on $bead" >&2; return 1; }

    if ! { mktemp_tracked && rows="$REPLY" && notice_rows "$rows"; }; then
        echo "$PROG: notify: recorded the notice on $bead, but could not read whether bd reports it ready; the next reconcile pass sends it once bd does" >&2
        return 0
    fi
    while IFS=$'\037' read -r id _ _ _ rdy title; do
        [ "$id" = "$bead" ] && { ready="$rdy"; bead_title="$title"; break; }
    done < "$rows"
    if [ "$ready" != "1" ]; then
        echo "$PROG: armed a notice on $bead -> $agent; the reconcile pass sends it once bd reports $bead ready"
        return 0
    fi
    if ! send_notice "$bead" "$agent" "$bead_title"; then
        echo "$PROG: notify: recorded the notice on $bead, but $agent's turn was not requested; the next reconcile pass tries again" >&2
        return 0
    fi
    local retire_rc=0
    retire_notice sent "$bead" "$agent" || retire_rc=$?
    case "$retire_rc" in
        0) ;;
        3) echo "$PROG: notify: notified $agent, and left the notice on $bead: $RETIRE_NOTE" >&2 ;;
        *) echo "$PROG: notify: notified $agent, but could not clear the notice on $bead; the next reconcile pass requests $agent's turn again, and the dedup key keeps a second copy of the mail out of its mailbox" >&2 ;;
    esac
    echo "$PROG: notified $agent that $bead is ready"
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

    # The notices owed, each with what decides it: bd's readiness, or the status
    # bd never reports ready.
    local nrows id status assignee agent ready state
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; nrows="$REPLY"
    notice_rows "$nrows" || { echo "$PROG: list: could not enumerate the notices owed" >&2; return 1; }
    while IFS=$'\037' read -r id status assignee agent ready _; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        if [ "$status" = "closed" ]; then state="CLOSED (notice no longer owed)"
        elif [ "$assignee" != "$agent" ]; then state="MOOT — no longer assigned to $agent"
        elif [ "$status" = "in_progress" ]; then state="CLAIMED (notice no longer owed)"
        elif [ "$ready" = "1" ]; then state="READY — bd reports it ready"
        elif [ "$status" != "open" ]; then state="WAITING — status=$status, which bd never reports ready"
        else state="WAITING — bd does not report it ready yet"
        fi
        printf '%s -> notice to %s [%s]\n' "$id" "${agent:-?}" "$state"
    done < "$nrows"
    [ "$n" -gt 0 ] || echo "$PROG: no pending dispatches in this store"
    return 0
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    arm)       cmd_arm "$@" ;;
    notify)    cmd_notify "$@" ;;
    disarm)    cmd_disarm "$@" ;;
    list)      cmd_list "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
