#!/usr/bin/env bash
# deferred-dispatch.sh — a pending dispatch is a fact about the work, so it
# lives on the work bead, not in an agent's context. `gc sling` pours
# immediately and reads no `blocks` deps, so sequencing needs a durable hold:
#   arm <bead> --target <agent> [--sling-arg X]... [--reason "..."]
# records the intent as metadata; `reconcile` (orders/deferred-dispatch.toml,
# cooldown, scope="rig") performs the sling once nothing holds the bead. What
# holds a bead is `gctk bead holds`' answer, which is the store's
# (docs/gctk-architecture.md, "The bead holds contract"): work that has not
# started is held by a wait of its own or one on a parent-child ancestor, and
# work in flight only by its own waits, so an armed re-dispatch of work already
# begun fires under a parked epic. The pass asks it once for every open armed
# bead, and slings one it answers clear. One it holds, blocked, held or
# unjudged, keeps its arm and fires once nothing holds it, and one it could not
# answer stays armed for the next pass. Status still gates: a non-open status is
# set deliberately, and a bead at one is never dispatched. `list` answers "what
# dispatches are owed?", naming the wait that holds each held arm; `disarm`
# withdraws one.
#
# Work assigned to a named agent owes a notice, not a sling (`notify`). A named
# session's hook offers it a bead by the bead's assignee once bd reports the
# bead ready, and under wake_mode = "resume" nothing wakes an idle named session
# into that hook when a wait lifts. So `notify` mails the agent at once when bd
# already reports the bead ready, and otherwise records the notice on the bead
# for `reconcile` to send when bd does. A notice waits on bd's readiness, the
# predicate the hook reads, and not on what gctk bead holds answers: a bead bd
# keeps unready is one the hook does not offer, and a notice then would wake the
# agent for nothing. A notice is done once the agent's turn is requested, not once its
# mail is saved, because mail alone requests no turn; until then the record
# stays for the next pass.
#
# `arm` is the default move for a blocked follow-up you file or keep back by
# hand: arm it instead of leaving it unrouted for someone to route once its
# blocker lands, and the reconcile pass routes it the moment nothing holds it —
# so a sitting can queue everything and drain, with nothing left to remember.
# The bead resolves by id, so the arm lands from any seat, rig-scoped or not.
# Callers: agents sequencing dependent work; first-reaction-dispose.sh
# --then-route (arm) and --assign/--then-assign (notify); the deferred-dispatch
# order. doctor/check-blocked-work-armed flags a blocked work bead that was
# never armed and carries no route.
#
# Per-bead best-effort (one bad bead never skips the rest; the next cooldown
# retries), but a failure to ENUMERATE exits non-zero — an unreadable queue
# must never read as an empty one.
#
# A reconcile pass holds a per-rig pass lock for its whole life, so two passes
# never sling the same bead. It starts a sling or an ask for a person only while
# its pass budget can still cover a sling, so the order's timeout does not kill
# it mid-sling. The ready beads past the budget wait, still armed, for the next
# pass, and so do the asks.
set -u

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

PROG="deferred-dispatch"

# One key is index AND payload: `bd list --has-metadata-key` enumerates armed
# beads without knowing any target in advance.
K_TARGET="gc.dispatch_when_ready"
K_ARGS="gc.dispatch_when_ready_args"
K_BY="gc.dispatch_when_ready_armed_by"
K_AT="gc.dispatch_when_ready_armed_at"
K_REASON="gc.dispatch_when_ready_reason"
# reconcile's own idempotency marker: a two-state record it stamps around its
# sling and clears by disarm. "slinging@<ts>" is written immediately before the
# sling and marks an attempt in flight but NOT proven; "slung@<ts>" replaces it
# the instant the sling returns success and marks the dispatch proven. Only a
# proven marker lets a later pass retire an arm without slinging again: a
# surviving "slinging@" is an attempt that never confirmed (a pass that died
# before or during its sling, or a failed sling whose rollback did not land), so
# recovery re-slings rather than retire an arm that may never have dispatched. A
# marker with no state prefix is read as proven, so an arm already mid-dispatch
# reads as done, not as a fresh attempt. Recovery keys on this one owned marker,
# never on the stamps a sling leaves (gc.routed_to for a plain pool sling,
# gc.execution_routed_to for an --on pour), which differ by delivery lane.
K_SLUNG="gc.dispatch_when_ready_slung"
SLUNG_TRYING="slinging@"   # value prefix: sling attempt in flight, not proven
SLUNG_DONE="slung@"        # value prefix: sling returned success, arm may retire

# A notice owed to the named agent a bead is assigned to. Like K_TARGET it is
# index and payload: its presence is the record, and its value is the agent the
# notice goes to. The record stays until the agent's turn is requested, so the
# next pass tries a notice again when its request failed. A repeat mints nothing,
# so a notice needs none of the sling's marker or counter: the mail's dedup key
# keeps a second copy out of the agent's mailbox while the first notice about
# the bead is still there.
K_NOTIFY="gc.notify_when_ready"
NOTICE_DEDUP_PREFIX="ready-notice:"

# `gc sling` mints an input convoy on every call, so a sling that never
# finalizes must not be re-attempted forever — that leaks one convoy per pass.
# This counter is the retry's memory: it lives on the bead, counts sling
# attempts, and once they reach the cap reconcile stops re-slinging and hands the
# bead to a person rather than minting convoy after convoy. It is cleared by
# disarm, so a proven dispatch resets the budget and clearing it by hand re-arms.
# Modeled on record-failure-cap.sh, the same pattern for merge.sh's record retry.
K_FAILS="gc.dispatch_when_ready_fail_count"
MAX_SLING_FAILURES="${GC_MAX_DISPATCH_SLING_FAILURES:-3}"
case "$MAX_SLING_FAILURES" in ''|*[!0-9]*) MAX_SLING_FAILURES=3 ;; esac

# The pass budget, in seconds from the start of the pass (0 = unpaced). The
# order's timeout kills a pass wherever it stands, and a sling killed mid-flight
# has already minted its input convoy, leaves it with no workflow, and spends
# one of the bead's attempts. So a pass starts a sling only while at least one
# sling's allowance is left in the budget, and leaves the remaining ready beads
# armed and untouched for the next pass. The budget sits at least one allowance
# below the order's timeout, so the last sling a pass starts can run for twice
# its allowance before the timeout lands. deferred-dispatch.test.sh holds both
# numbers against orders/deferred-dispatch.toml.
PASS_BUDGET_SECS="${DEFERRED_DISPATCH_PASS_BUDGET_SECS:-420}"
case "$PASS_BUDGET_SECS" in ''|*[!0-9]*) PASS_BUDGET_SECS=420 ;; esac
PASS_BUDGET_SECS=$((10#$PASS_BUDGET_SECS))
SLING_ALLOWANCE_SECS="${DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS:-90}"
case "$SLING_ALLOWANCE_SECS" in ''|*[!0-9]*) SLING_ALLOWANCE_SECS=90 ;; esac
SLING_ALLOWANCE_SECS=$((10#$SLING_ALLOWANCE_SECS))

# The pass lock. Two passes over one store sling the same ready bead twice: two
# input convoys for one work bead, and its attempt count bumped twice. The
# controller's open-tracking gate holds only while a run's tracking bead stays
# open, and a sweep can close that bead under a pass still running: the core
# order-tracking-sweep order at its stale-after, and the controller watchdog 2m
# after dispatch on a gc build that does not extend that window to the order's
# timeout. So a pass takes bd-lib.sh's pass lock before it reads anything and
# holds it for its whole life, and every gc, human-gate.sh and gc-helm.sh call
# the pass makes runs through pass_child, so nothing a call leaves running holds
# the lock after it. The order's timeout kills the pass's whole process group,
# its gc sling with it, and the next pass re-attempts the unconfirmed sling
# through the slinging@ recovery below.
# A holder older than this is not a slow pass, because the order's timeout would
# have killed it: the pass holding the lock outlived its timeout, and nothing is
# dispatching. It sits above the order's timeout, so a pass that is still
# running never reads as a wedged one.
LOCK_STALL_SECS="${DEFERRED_DISPATCH_LOCK_STALL_SECS:-900}"
case "$LOCK_STALL_SECS" in ''|*[!0-9]*) LOCK_STALL_SECS=900 ;; esac
LOCK_STALL_SECS=$((10#$LOCK_STALL_SECS))

# The store, pinned: `gc bd` resolves its ledger from the invoking rig and
# ignores BEADS_DIR, so an unpinned read in the rig-scoped order env answers
# about whatever rig gc resolves rather than the one the pass is for.
# `--db` overrides it.
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"
DRY_RUN=0

# The helpers the retry cap asks a person through resolve beside this script; the
# env overrides let the hermetic test point them at stubs.
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HUMAN_GATE="${GC_HUMAN_GATE_TOOL:-$SCRIPTS_DIR/human-gate.sh}"
HELM="${GC_HELM_TOOL:-$SCRIPTS_DIR/gc-helm.sh}"
# A capped bead stays capped from one pass to the next until a person disarms
# it or clears its count, so every pass that finds it unheld detects the cap
# again. The gate's call declares a quiet window, so a moot or benign answer
# stands for a day.
CAP_QUIET_WINDOW=86400

# The rig's state key, the pass lock and pass_child. Unsourceable, no pass can be
# held to one at a time, so nothing runs.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 1; }
# What holds a bead is the answer of `gctk bead holds`, the one rule
# (docs/gctk-architecture.md, "The bead holds contract"), read from the binary
# the city builds, in the store the pass is pinned to.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
# The pass lock is keyed per rig like the order, so two rigs never share one. It
# lives in the pack state dir the order's env names; the override lets the
# hermetic test point it at a tmpdir.
STATE_DIR="${DEFERRED_DISPATCH_STATE_DIR:-${GC_PACK_STATE_DIR:-${TMPDIR:-/tmp}/gc}/deferred-dispatch}/$(rig_state_key)"

TMPFILES=()
cleanup() { [ "${#TMPFILES[@]}" -gt 0 ] && rm -f "${TMPFILES[@]}"; return 0; }
trap cleanup EXIT
# Answers in $REPLY rather than on stdout, because a caller writing
# `f="$(mktemp_tracked)"` would run the append inside a command-substitution
# subshell: the registry the EXIT trap reads is the caller's, and the
# subshell's copy of it dies with the substitution, leaking every allocation.
mktemp_tracked() { REPLY="$(mktemp "${TMPDIR:-/tmp}/gctk-deferred-dispatch.XXXXXX")" || return 1; TMPFILES+=("$REPLY"); }

bd_() {
    if [ -n "$BD_DB" ]; then pass_child gc bd --db "$BD_DB" "$@"; else pass_child gc bd "$@"; fi
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }

actor() { printf '%s' "${GC_AGENT:-${BEADS_ACTOR:-${USER:-unknown}}}"; }

usage() {
    cat <<'EOF'
Usage:
  deferred-dispatch.sh arm <bead> --target <agent> [--sling-arg <arg>]... [--reason <text>] [--db <path>]
  deferred-dispatch.sh notify <bead> --agent <named-agent> [--reason <text>] [--db <path>]
  deferred-dispatch.sh disarm <bead> [--reason <text>] [--db <path>]
  deferred-dispatch.sh list [--db <path>]
  deferred-dispatch.sh list --json [--db <path>]
  deferred-dispatch.sh reconcile [--dry-run] [--db <path>]

Verbs:
  arm        Record a pending dispatch on <bead>. The sling happens later, from
             reconcile, once nothing holds the bead. This is the move for a
             blocked follow-up you file or keep back by hand: arm it instead of
             leaving it unrouted for someone to route once its blocker lands,
             so you can queue everything and drain with nothing to remember.
             The bead must be open — reconcile slings only an open bead, so an
             arm on a bead at another status could never fire.
  notify     Tell <named-agent> that <bead>, assigned to it, is ready for its
             hook: gc mail send --notify, which requests the agent's turn and
             wakes it when it is not running, with the bead id in the mail.
             Under wake_mode = "resume" nothing else wakes an idle named
             session for a new assignee. The mail goes at once when bd
             reports the bead ready; otherwise the notice is recorded on the
             bead and reconcile sends it once bd does. When the mail requests
             no turn, because the send or its turn request failed or because
             an earlier notice about the bead is still in the agent's mailbox,
             gc session nudge requests it. The notice stays recorded until a
             turn is requested. The bead must be assigned to <named-agent>.
             A closed bead, or one the agent already claimed, owes no notice
             and exits 0.
  disarm     Remove a pending dispatch, and any notice owed. The bead is left
             otherwise untouched.
  list       Show every armed bead in this store and whether it is held (and
             by which wait, as gctk bead holds answers), dispatchable now, or
             closed with a dispatch still owed; then every notice owed, and
             whether bd reports its bead ready. With --json it prints the armed
             beads alone, as bd lists them: no hold, and no notice owed.
  reconcile  One pass. It first sends every notice whose bead is ready as bd
             reports it, and retires the notice on a bead that closed, that its
             agent claimed, or that is no longer assigned to that agent. Then
             it slings every armed bead nothing holds, and retires the arm on
             every armed bead that closed or that another path already
             delivered (a merge_result stamp). Because each sling mints an
             input convoy, it stops re-slinging and asks a person about a bead
             whose dispatch has failed to finalize MAX_SLING_FAILURES times
             rather than leak a convoy per pass.
             Driven by orders/deferred-dispatch.toml (cooldown, scope="rig").
             A pass holds the rig's pass lock for its whole life; one that
             finds it held exits 0 without reading the store. It starts a
             notice, a sling or an ask for a person only while
             DEFERRED_DISPATCH_SLING_ALLOWANCE_SECS
             (90) of its DEFERRED_DISPATCH_PASS_BUDGET_SECS (420, 0 = unpaced)
             are left, and leaves the rest for the next pass. --dry-run takes no
             lock and spends no budget.

--sling-arg is repeatable and is passed through to `gc sling` verbatim after the
target and bead, e.g. --sling-arg --on --sling-arg mol-pr-from-issue.
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

# The armed-set snapshot armed_rows already read, reused instead of a `bd show`
# per bead. That per-bead read summed past the reconcile order's timeout once
# the armed set grew (with the per-bead dep-list, the other half of the same
# N+1), so a full pass was killed before it dispatched and owed arms silently
# starved. The snapshot carries every field a caller reads here (status,
# assignee, metadata), so nothing is lost but freshness, and the pass reads it
# consistently: the slung marker and the fail count are written only by this pass
# (it holds the rig's pass lock), so the snapshot is authoritative for
# them; status was already read from the snapshot for the closed-retire; and
# merge_result and assignee are now read from it too, one pass staler than the
# prior fresh per-bead show. A bead delivered or claimed in the pass window is
# therefore acted on from the pass-start view — at worst one redundant sling
# before the next pass retires it from its own snapshot — and the fail-count cap
# bounds a redundant sling that never finalizes. The file is pre-scrubbed, so a
# raw C0 byte cannot abort the read.
bead_from_cache() { # all_json_file id -> single bead object on stdout, or nothing (rc 1)
    local f="$1" id="$2" out
    out="$(jq -c --arg id "$id" 'map(select(.id == $id)) | (.[0] // empty)' "$f" 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s' "$out"
}

meta_of() { # bead-json key -> value or empty
    printf '%s' "$1" | jq -r --arg k "$2" '(.metadata[$k] // "") | tostring' 2>/dev/null
}

# holds_read <id>... — what holds each bead, as `gctk bead holds` answers in the
# pass's store: one JSON record per bead, in the order named, and {"id",
# "error"} for a bead the store could not answer. rc 0 when every bead answered,
# 1 when one could not be, and 2 when gctk did not run as asked, which says why
# on stderr. The call runs through pass_child, as every gc call the pass makes
# does, since gctk's own gc calls inherit its descriptors.
holds_read() {
    [ -x "$GCTK" ] || { echo "$PROG: no gctk binary at '$GCTK' to read what holds a bead; GCTK_BIN names one, or GC_CITY_PATH the city whose build it is" >&2; return 2; }
    local rc=0
    pass_child "$GCTK" bead holds ${BD_DB:+--db "$BD_DB"} "$@" 2>/dev/null || rc=$?
    case "$rc" in 0|1) return "$rc" ;; *) return 2 ;; esac
}

# The jq defs that print one record of `gctk bead holds` for a person. A wait
# names its bead and that bead's title, says so when it is a waits-for wait the
# store cannot judge, and names the ancestor it sits on when it is not the
# bead's own. A record's line is its first wait, then how many more.
# shellcheck disable=SC2016  # jq source; its $names are jq's
HOLDS_JQ='
  def wait_label:
    (if ((.title // "") | tostring) != "" then "\(.id) \"\(.title)\"" else (.id | tostring) end)
    + (if .type == "waits-for" then " (waits-for, unjudged)" else "" end)
    + (if ((.ancestor // "") | tostring) != "" then " on ancestor \(.ancestor)" else "" end);
  def holds_line:
    (.waits // []) as $w
    | (if ($w | length) == 0 then ""
       else ($w[0] | wait_label) + (if ($w | length) > 1 then " (+\($w | length - 1) more)" else "" end) end)
    | gsub("[[:cntrl:]]"; " ");
'

# --- arm ---------------------------------------------------------------------
cmd_arm() {
    local bead="" target="" reason="" args=() a
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

    local json
    json="$(show_bead "$bead")" || json=""
    [ -n "$json" ] || { echo "$PROG: arm: $bead does not resolve in this store" >&2; return 1; }

    # Arming already-dispatched work would queue a second pour behind the first.
    # gc.execution_routed_to is not such a dispatch: it is execution provenance
    # stamped on a workflow-driven bead, and no worker or pool-demand pass reads
    # it (they read gc.routed_to). A blocked bead carrying only it is the shape
    # doctor/check-blocked-work-armed flags and points at arming to fix, so
    # refusing on it would turn that remedy into a dead end.
    local status assignee routed slung
    status="$(printf '%s' "$json" | jq -r '.status // ""')"
    assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
    routed="$(meta_of "$json" gc.routed_to)"
    slung="$(meta_of "$json" "$K_SLUNG")"
    if [ "$status" = "closed" ]; then
        echo "$PROG: arm: $bead is closed — nothing to dispatch" >&2; return 1
    fi
    # A gc.dispatch_when_ready_slung marker in either state means reconcile is
    # mid-dispatch on a prior arm: "slinging@" an attempt in flight, "slung@" one
    # it has proven and is about to retire. Re-arming over either stacks a second
    # dispatch, so refuse; disarm first if you truly mean to re-dispatch.
    if [ "$status" = "in_progress" ] || [ -n "$routed" ] || [ -n "$slung" ]; then
        echo "$PROG: arm: $bead is already dispatched (status=$status routed_to='$routed'${slung:+ slung_marker=$slung}) — disarm-then-rearm only if you mean to re-dispatch it" >&2
        return 1
    fi
    # reconcile slings an OPEN bead only: a status is set deliberately, so an arm
    # recorded on any other live status can never fire, and nothing re-derives
    # status from the dep graph — the status is cleared by whoever set it.
    # Refusing here is the difference between a caller learning that now and an
    # arm that reads as held forever.
    if [ "$status" != "open" ]; then
        echo "$PROG: arm: $bead is status=$status, and reconcile slings open beads only — this arm could never fire. Return it to open, then arm it." >&2
        return 1
    fi

    local args_json
    if [ "${#args[@]}" -gt 0 ]; then
        args_json="$(printf '%s\n' "${args[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')" || args_json=""
        [ -n "$args_json" ] || { echo "$PROG: arm: could not encode --sling-arg values" >&2; return 1; }
    else
        args_json="[]"
    fi

    local note
    note="$PROG: dispatch armed by $(actor) at $(now_utc) — target=$target sling_args=$args_json${reason:+ reason=$reason}. It will be slung by the deferred-dispatch reconcile pass once nothing holds this bead; no agent keeps it in context."
    bd_ update "$bead" \
        --set-metadata "$K_TARGET=$target" \
        --set-metadata "$K_ARGS=$args_json" \
        --set-metadata "$K_BY=$(actor)" \
        --set-metadata "$K_AT=$(now_utc)" \
        --set-metadata "$K_REASON=$reason" \
        --append-notes "$note" >/dev/null 2>&1 || {
            echo "$PROG: arm: failed to write the dispatch record onto $bead" >&2; return 1; }

    echo "$PROG: armed $bead -> $target${reason:+ ($reason)}"

    # The hint asks the question reconcile dispatches on, what holds the bead,
    # through the same read. The bead is open here (refused above otherwise), so
    # an all-clear means the next pass slings it, and a hold names the wait the
    # arm now waits on. But bd resolves dependencies within a single store, so a
    # wait edge onto a bead in another rig holds nothing here, and the next pass
    # slings the arm while that bead is still open. The read lists such an edge,
    # so the hint names it rather than let the all-clear stand on it. This is the
    # one place a human is here to redirect the sequencing. A read that does not
    # answer proves neither, so the hint says so.
    local rec="" rec_rc=0 foreign="" hstatus="" hold=""
    rec="$(holds_read "$bead")" || rec_rc=$?
    if [ "$rec_rc" -eq 0 ]; then
        foreign="$(printf '%s' "$rec" | jq -r '[.foreign[]?.id] | join(",")' 2>/dev/null)" || rec_rc=1
        hstatus="$(printf '%s' "$rec" | jq -r '.status // ""' 2>/dev/null)" || rec_rc=1
        hold="$(printf '%s' "$rec" | jq -r "$HOLDS_JQ"'holds_line' 2>/dev/null)" || rec_rc=1
    fi
    if [ "$rec_rc" -ne 0 ] || [ -z "$hstatus" ]; then
        echo "$PROG: warning: $bead — could not read what holds it, so when reconcile will dispatch it is unproven. Read it with \`gctk bead holds $bead\` if the timing matters." >&2
    elif [ -n "$foreign" ]; then
        echo "$PROG: warning: $bead has a wait edge to $foreign, which has no row in this store. bd resolves dependencies within a single store, so this cross-rig or external blocker does not hold the arm: reconcile will dispatch $bead with $foreign still open. Sequence it by hand if that ordering matters." >&2
    elif [ "$hstatus" = clear ]; then
        echo "$PROG: note: nothing holds $bead right now — the next reconcile pass will dispatch it"
    else
        echo "$PROG: note: $bead is HELD by $hold — the first reconcile pass after nothing holds it will dispatch it"
    fi
    if [ -n "$assignee" ]; then
        echo "$PROG: note: $bead carries assignee '$assignee' — reconcile will NOT sling over an assigned bead; clear it or disarm" >&2
    fi
    return 0
}

# --- disarm ------------------------------------------------------------------
# Clears the dispatch record, and each further key the caller names in the same
# write. reconcile retires an arm through it and names none, so a notice owed on
# the same bead outlives the arm: only its own send or retire, or the disarm
# verb, clears it.
disarm_bead() { # id reason [key]... -> rc
    local id="$1" reason="${2:-}"
    local -a also=()
    shift 2 || shift $#
    while [ $# -gt 0 ]; do also+=(--unset-metadata "$1"); shift; done
    bd_ update "$id" \
        --unset-metadata "$K_TARGET" \
        --unset-metadata "$K_ARGS" \
        --unset-metadata "$K_BY" \
        --unset-metadata "$K_AT" \
        --unset-metadata "$K_REASON" \
        --unset-metadata "$K_SLUNG" \
        --unset-metadata "$K_FAILS" \
        ${also[@]+"${also[@]}"} \
        --append-notes "$PROG: dispatch record cleared at $(now_utc)${reason:+ — $reason}" >/dev/null 2>&1
}

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
    # The verb withdraws everything this script owes on the bead: the arm, and
    # any notice owed.
    disarm_bead "$bead" "${reason:-disarmed by $(actor)}" "$K_NOTIFY" || {
        echo "$PROG: disarm: failed to clear the dispatch record on $bead" >&2; return 1; }
    echo "$PROG: disarmed $bead"
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
    if [ "$DRY_RUN" = 1 ]; then
        echo "$PROG: DRY-RUN would notify $agent that $id is ready (gc mail send $agent --notify --dedup $NOTICE_DEDUP_PREFIX$id, and gc session nudge $agent if the mail requests no turn)"
        return 0
    fi
    mktemp_tracked || { echo "$PROG: could not notify $agent that $id is ready: mktemp failed" >&2; return 1; }
    err="$REPLY"
    if ! out="$(pass_child gc mail send "$agent" --notify --dedup "$NOTICE_DEDUP_PREFIX$id" --json \
            -s "Ready for you: $id" -m "$text" 2>"$err")"; then
        why="gc mail send could not mail $agent about $id ($(stderr_text "$err"))"
    elif printf '%s' "$out" | scrub | jq -e 'select(type == "object") | .notified == true' >/dev/null 2>&1; then
        return 0
    elif printf '%s' "$out" | scrub | jq -e 'select(type == "object") | .already_done == true' >/dev/null 2>&1; then
        why="the notice mailed about $id earlier is still in its mailbox, so the dedup key sent no new mail and requested no turn"
    else
        why="the mail was saved but requested no turn ($(stderr_text "$err"))"
    fi
    if ! pass_child gc session nudge "$agent" "Ready for you: $text" --reference-bead "$id" >/dev/null 2>"$err"; then
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

# Unreadable is not empty: every enumeration read is checked and any failure
# returns 1. The columns join on the unit separator, which the scrub leaves in no
# field, so a title comes back as it was stored: @tsv would write a backslash in
# one as two, and `read` folds a run of tabs into one. The third column is what
# `gctk bead holds` answers for an open bead: clear, blocked, held or unjudged,
# or error when it could not answer the bead, and empty for a bead at any other
# status, which never dispatches whatever holds it. The fourth is what holds the
# bead, its first wait as a person reads it, or why the read failed. The fifth
# names that wait again when it is an ancestor's, so the pass can group the arms
# an ancestor's wait keeps, and the sixth is why the bead is in flight, when it
# is. One read answers every open armed bead, so a pass costs the same few reads
# however large the armed set grows. A read that gctk could not make fails the
# whole enumeration rather than let an unread hold pass for none. The listing is
# cached to all_out so the list and reconcile loops read each bead's fields from
# it instead of a `bd show` per bead.
armed_rows() { # rows_out all_out : "<id>\037<status>\037<holds>\037<hold>\037<ancestor hold>\037<in flight>" per bead; caches the listing to all_out
    local out="$1" all_out="$2" all held rc=0 id
    local -a open_ids=()
    # --brief: this function and its cache consumers use only id, status,
    # assignee and metadata, all of which --brief keeps; it drops only the
    # free-form text that makes a row heavy on the shared store.
    all="$(bd_ list --has-metadata-key "$K_TARGET" --all --brief --json --limit 0 2>/dev/null)" || return 1
    [ -n "$all" ] || return 1
    printf '%s' "$all" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
    printf '%s' "$all" | scrub > "$all_out" || return 1

    while IFS= read -r id; do
        [ -n "$id" ] && open_ids+=("$id")
    done < <(jq -r '.[] | select((.status // "") == "open") | (.id // "") | tostring' "$all_out" 2>/dev/null)
    mktemp_tracked || return 1; held="$REPLY"
    if [ "${#open_ids[@]}" -gt 0 ]; then
        holds_read "${open_ids[@]}" > "$held" || rc=$?
        [ "$rc" -le 1 ] || return 1
    fi
    # The answers reach jq as a file and the listing over stdin, since both grow
    # with the armed set and an argv value past the kernel's per-argument cap
    # fails the whole enumeration. A bead the read printed no line for has no
    # answer, which is an error, never clear.
    jq -rn --slurpfile h "$held" "$HOLDS_JQ"'
        ($h | map({key: ((.id // "") | tostring), value: .}) | from_entries) as $hm
        | input | .[]
        | ((.id // "") | tostring) as $id
        | ($hm[$id] // null) as $r
        | (if (.status // "") != "open" then ""
           elif $r == null or $r.error != null then "error"
           else (($r.status // "") | tostring | if . == "" then "error" else . end) end) as $s
        | [ $id, (.status // ""), $s,
            (if $s == "error" then (if $r == null then "gctk bead holds printed no answer for it" else ($r.error | tostring) end)
             elif $s == "" or $s == "clear" then ""
             else ($r | holds_line) end),
            (if $s == "held" then ($r | holds_line) else "" end),
            (if $s == "" or $s == "error" then "" else (($r.in_flight // "") | tostring) end) ]
        | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' < "$all_out" > "$out" 2>/dev/null || return 1
    return 0
}

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
    # holds them, so it makes that one read and no hold walk. A read that fails
    # or answers no array fails the verb, since an unreadable queue is not an
    # empty one.
    if [ "$as_json" = 1 ]; then
        local listed
        listed="$(bd_ list --has-metadata-key "$K_TARGET" --all --json --limit 0 2>/dev/null)" \
            && printf '%s' "$listed" | scrub | jq -e 'type == "array"' >/dev/null 2>&1 \
            || { echo "$PROG: list: could not enumerate armed beads" >&2; return 1; }
        printf '%s\n' "$listed"
        return 0
    fi

    local rows all_cache
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; rows="$REPLY"
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; all_cache="$REPLY"
    armed_rows "$rows" "$all_cache" || { echo "$PROG: list: could not enumerate armed beads" >&2; return 1; }

    local n=0 id status holds hold via json target reason slung state mr fails flight
    while IFS=$'\037' read -r id status holds hold via flight; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        json="$(bead_from_cache "$all_cache" "$id")" || json=""
        target=""; reason=""; slung=""; mr=""; fails=0
        if [ -n "$json" ]; then
            target="$(meta_of "$json" "$K_TARGET")"
            reason="$(meta_of "$json" "$K_REASON")"
            slung="$(meta_of "$json" "$K_SLUNG")"
            mr="$(meta_of "$json" merge_result)"
            fails="$(meta_of "$json" "$K_FAILS")"; case "$fails" in ''|*[!0-9]*) fails=0 ;; esac
        fi
        # An open arm splits by what holds it, and conflating the ways is what
        # hides a dead arm. One a wait holds, its own or an ancestor's, waits on
        # something that can clear, and is shown with the wait and its title, so a
        # parked bead says why it is parked and what releases it. One nothing holds
        # is dispatchable now, and one in flight is held only by its own waits, so
        # a wait on an ancestor leaves it running. One whose read failed is
        # neither, and says so. Any other live status is never slung, so no wait
        # landing will make it dispatchable.
        if [ "$status" = "closed" ]; then state="CLOSED (dispatch no longer owed)"
        elif [ -n "$mr" ]; then state="DELIVERED — merge_result=$mr (arm retires next pass, no sling)"
        elif [ -n "$slung" ]; then
            case "$slung" in
                "$SLUNG_TRYING"*) state="dispatch in flight (attempt not yet confirmed)" ;;
                *)                state="dispatched (arm pending retirement)" ;;
            esac
        elif [ "$fails" -ge "$MAX_SLING_FAILURES" ]; then state="CAPPED — $fails sling failures, a person asked; disarm or clear $K_FAILS"
        elif [ "$status" != "open" ]; then state="STRANDED — status=$status is never slung"
        elif [ "$holds" = "error" ]; then state="UNREAD — what holds it could not be read ($hold); the pass leaves it armed"
        elif [ "$holds" != "clear" ]; then state="HELD by $hold"
        elif [ -n "$flight" ]; then state="DISPATCHABLE NOW (in flight, $flight: only its own waits hold it, and none is pending)"
        else state="DISPATCHABLE NOW"
        fi
        printf '%s -> %s [%s]%s\n' "$id" "${target:-?}" "$state" "${reason:+ — $reason}"
    done < "$rows"

    # The notices owed, each with what decides it: bd's readiness, the status
    # bd never reports ready, or what retires it on the next pass.
    local nrows assignee agent
    mktemp_tracked || { echo "$PROG: list: mktemp failed" >&2; return 1; }; nrows="$REPLY"
    notice_rows "$nrows" || { echo "$PROG: list: could not enumerate the notices owed" >&2; return 1; }
    while IFS=$'\037' read -r id status assignee agent ready _; do
        [ -n "${id:-}" ] || continue
        n=$((n + 1))
        if [ "$status" = "closed" ]; then state="CLOSED (notice no longer owed; retires next pass)"
        elif [ "$assignee" != "$agent" ]; then state="MOOT — no longer assigned to $agent (retires next pass)"
        elif [ "$status" = "in_progress" ]; then state="CLAIMED (notice no longer owed; retires next pass)"
        elif [ "$ready" = "1" ]; then state="READY — the next pass notifies $agent"
        elif [ "$status" != "open" ]; then state="WAITING — status=$status, which bd never reports ready"
        else state="WAITING — bd does not report it ready yet"
        fi
        printf '%s -> notice to %s [%s]\n' "$id" "${agent:-?}" "$state"
    done < "$nrows"
    [ "$n" -gt 0 ] || echo "$PROG: no pending dispatches in this store"
    return 0
}

# --- reconcile ---------------------------------------------------------------
sling_fits_budget() { # -> 0 while at least one sling's allowance is left in the pass budget
    [ "$PASS_BUDGET_SECS" -gt 0 ] || return 0
    [ $(( PASS_T0 + PASS_BUDGET_SECS - $(now_epoch) )) -ge "$SLING_ALLOWANCE_SECS" ]
}

# The controller keeps an exec order's output only when it exits non-zero, so a
# pass that exits 0 having skipped its work, or left some of it, also says so in
# the per-run file the controller names in GC_ORDER_OUTCOME_FILE (gascity's
# exec-order outcome contract, internal/orders/exec_outcome.go). The controller
# reads that file only after a run that exits 0, and records the declaration as
# an order.skipped event. Pairs follow the reason: a bead the pass left for the
# next one, and what it left undone on that bead.
declare_outcome() { # <skipped|partial> <reason> [<bead-id> <what-was-left>]...
    [ -n "${GC_ORDER_OUTCOME_FILE:-}" ] || return 0
    local outcome="$1" reason="$2"; shift 2
    jq -nc --arg o "$outcome" --arg r "$reason" \
        '{outcome: $o, reason: $r,
          scopes: ($ARGS.positional | [range(0; length; 2) as $i | {scope: .[$i], reason: .[$i + 1]}])}' \
        --args "$@" > "$GC_ORDER_OUTCOME_FILE" 2>/dev/null || true
}

sling_bead() { # id target args_json -> rc
    local id="$1" target="$2" args_json="$3" a
    local -a extra=()
    if [ "$args_json" != "[]" ] && [ -n "$args_json" ]; then
        printf '%s' "$args_json" | jq -e 'type == "array"' >/dev/null 2>&1 || return 3
        local argf; mktemp_tracked || return 3; argf="$REPLY"
        printf '%s' "$args_json" | jq -r '.[]' > "$argf" 2>/dev/null || return 3
        while IFS= read -r a; do [ -n "$a" ] && extra+=("$a"); done < "$argf"
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "$PROG: DRY-RUN would sling: gc sling ${GC_RIG:+--rig $GC_RIG }$target $id ${extra[*]:-}"
        return 0
    fi
    if [ -n "${GC_RIG:-}" ]; then
        pass_child gc sling --rig "$GC_RIG" "$target" "$id" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1
    else
        pass_child gc sling "$target" "$id" ${extra[@]+"${extra[@]}"} >/dev/null 2>&1
    fi
}

# The notices half of a pass. A notice whose bead bd reports ready is sent, and
# its record is retired once the agent's turn is requested; a notice that gets
# no turn requested stays armed and fails the pass. One whose bead closed, was
# claimed by its agent, or is no longer assigned to that agent owes nothing,
# and its record is retired unsent. Either retire re-reads the bead first and
# leaves a record that now names another agent, or a notice owed again, for the
# next pass (retire_notice). Any other notice waits for bd to report its
# bead ready. A notice starts under the bound a sling starts under, only while
# the pass budget has a sling's allowance left. Notices run ahead of the slings,
# because a notice is a mail and at most one nudge, and a sling can take a
# minute. Sets NOTICE_FAILED and NOTICE_LEFT_IDS for the
# pass's exit and its outcome declaration; an enumeration that fails counts as a
# failure, so the pass still slings and then exits non-zero.
NOTICE_FAILED=0
NOTICE_LEFT_IDS=()
reconcile_notices() {
    local rows expected processed=0 sent=0 retired=0 waiting=0 failed=0
    local id status assignee agent ready title why rc
    if ! { mktemp_tracked && rows="$REPLY" && notice_rows "$rows"; }; then
        echo "$PROG: reconcile: could not enumerate the notices owed — NOT treating this as an empty queue" >&2
        NOTICE_FAILED=1
        return 1
    fi
    expected="$(wc -l < "$rows" | tr -d ' ')"
    while IFS=$'\037' read -r id status assignee agent ready title; do
        [ -n "${id:-}" ] || continue
        processed=$((processed + 1))
        why="$(notice_unowed_why "$status" "$assignee" "$agent")"
        if [ -n "$why" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire the notice on $id: $why"
                retired=$((retired + 1)); continue
            fi
            rc=0; retire_notice unowed "$id" "$agent" || rc=$?
            case "$rc" in
                0) echo "$PROG: retired the notice on $id: $RETIRE_WHY"; retired=$((retired + 1)) ;;
                3) echo "$PROG: left the notice on $id: $RETIRE_NOTE"; waiting=$((waiting + 1)) ;;
                *) echo "$PROG: WARN could not retire the notice on $id" >&2; failed=$((failed + 1)) ;;
            esac
            continue
        fi
        if [ "$ready" != "1" ]; then
            waiting=$((waiting + 1)); continue
        fi
        if [ "$DRY_RUN" != 1 ] && ! sling_fits_budget; then
            NOTICE_LEFT_IDS+=("$id"); continue
        fi
        if ! send_notice "$id" "$agent" "$title"; then
            echo "$PROG: WARN could not notify $agent that $id is ready — leaving the notice armed, retrying next pass" >&2
            failed=$((failed + 1)); continue
        fi
        sent=$((sent + 1))
        [ "$DRY_RUN" = 1 ] && continue
        rc=0; retire_notice sent "$id" "$agent" || rc=$?
        case "$rc" in
            0) echo "$PROG: notified $agent that $id is ready" ;;
            3) echo "$PROG: notified $agent that $id is ready, and left the notice on $id: $RETIRE_NOTE" ;;
            *) echo "$PROG: WARN notified $agent that $id is ready, but could not clear the notice — the next pass requests $agent's turn again, and the dedup key keeps a second copy of the mail out of its mailbox" >&2 ;;
        esac
    done < "$rows"
    if [ "$processed" != "$expected" ]; then
        echo "$PROG: reconcile: enumerated $expected notice(s) but processed $processed" >&2
        failed=$((failed + 1))
    fi
    [ "$expected" -gt 0 ] \
        && echo "$PROG: notices: $sent sent, $retired retired, $waiting waiting, ${#NOTICE_LEFT_IDS[@]} left for the next pass, $failed failed (of $expected)"
    NOTICE_FAILED="$failed"
    [ "$failed" = 0 ]
}

# The dispatch half: sling every armed bead nothing holds now, and retire each
# arm whose dispatch is no longer owed.
reconcile_dispatch() {
    local rows all_cache
    mktemp_tracked || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }; rows="$REPLY"
    mktemp_tracked || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }; all_cache="$REPLY"
    armed_rows "$rows" "$all_cache" || {
        echo "$PROG: reconcile: could not enumerate armed beads — NOT treating this as an empty queue" >&2
        return 1; }

    local expected processed=0 dispatched=0 retired=0 held=0 stranded=0 assigned=0 capped=0 failed=0 left=0 budget_noted=0 heldf
    local -a left_ids=() ask_left_ids=()
    expected="$(wc -l < "$rows" | tr -d ' ')"
    mktemp_tracked || { echo "$PROG: reconcile: mktemp failed" >&2; return 1; }; heldf="$REPLY"

    local id status holds hold via json fresh target args_json assignee slung rc merge_result fails flight
    while IFS=$'\037' read -r id status holds hold via flight; do
        [ -n "${id:-}" ] || continue
        processed=$((processed + 1))

        # Armed and closed: retire the record, no dispatch is owed.
        if [ "$status" = "closed" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire arm on closed $id"
            elif disarm_bead "$id" "bead closed with a dispatch still armed; no dispatch owed"; then
                echo "$PROG: retired arm on closed $id"
            else
                echo "$PROG: WARN could not retire arm on closed $id" >&2; failed=$((failed + 1)); continue
            fi
            retired=$((retired + 1)); continue
        fi

        json="$(bead_from_cache "$all_cache" "$id")" || json=""
        if [ -z "$json" ]; then
            echo "$PROG: WARN $id enumerated but does not resolve — leaving armed" >&2
            failed=$((failed + 1)); continue
        fi

        # A surviving gc.dispatch_when_ready_slung marker means a prior pass was
        # mid-dispatch and died before it could disarm; its state decides what to
        # do. It is the ONE signal recovery reads: a plain pool sling and an --on
        # pour leave different stamps (gc.routed_to vs gc.execution_routed_to), and
        # in a default-formula city a bare `gc sling` is itself an --on-less pour,
        # so no stamp a sling leaves is a reliable "already ran" across every lane.
        # Read it before the ready gate: a dispatched bead may no longer report
        # ready, and a proven-but-stranded marker must still retire.
        slung="$(meta_of "$json" "$K_SLUNG")"
        case "$slung" in
            "")
                : # not mid-dispatch; fall through to the ready gate and sling
                ;;
            "$SLUNG_TRYING"*)
                # Attempt in flight but never confirmed: the pass died before or
                # during its sling, or a failed sling could not roll the marker
                # back. The dispatch is NOT proven, so retiring the arm here is the
                # silent lost dispatch this two-state marker exists to prevent —
                # and one doctor/check-blocked-work-armed cannot catch, because the
                # blocker has lifted and the bead is ready, not blocked. Clear the
                # unproven stamp and fall through to re-attempt the sling.
                if [ "$DRY_RUN" = 1 ]; then
                    echo "$PROG: DRY-RUN would re-attempt an unconfirmed sling on $id (marker=$slung)"
                elif bd_ update "$id" --unset-metadata "$K_SLUNG" >/dev/null 2>&1; then
                    echo "$PROG: re-attempting $id — a prior pass stamped '$slung' and never confirmed the sling"
                else
                    echo "$PROG: WARN could not clear the unconfirmed $K_SLUNG on $id — leaving armed" >&2
                    failed=$((failed + 1)); continue
                fi
                ;;
            *)
                # "slung@<ts>" (a proven dispatch), or any marker without the
                # "slinging@" prefix: the sling ran and the pass died before it
                # could disarm. Retire the arm — a second sling would double up.
                if [ "$DRY_RUN" = 1 ]; then
                    echo "$PROG: DRY-RUN would retire arm on already-dispatched $id"
                elif disarm_bead "$id" "already dispatched (reconcile confirmed the sling at $slung, then died before disarming); arm retired without a second sling"; then
                    echo "$PROG: retired arm on already-dispatched $id"
                else
                    echo "$PROG: WARN could not retire arm on already-dispatched $id" >&2; failed=$((failed + 1)); continue
                fi
                retired=$((retired + 1)); continue
                ;;
        esac

        # Already delivered: the bead carries a refinery delivery stamp (an open
        # PR, the pre-open gate, a merge), so the work this arm would pour has
        # already been produced by another path since the arm was recorded.
        # Re-slinging pours a redundant molecule and mints an input convoy with
        # it every pass — the common cause of a sling that never finalizes on an
        # already-delivered bead. Retire the arm the way a proven slung@ marker
        # does; there is no dispatch to lose, only one to stop repeating.
        merge_result="$(meta_of "$json" merge_result)"
        if [ -n "$merge_result" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would retire arm on already-delivered $id (merge_result=$merge_result)"
            elif disarm_bead "$id" "work already delivered (merge_result=$merge_result) by another path since the arm was recorded; arm retired without slinging a redundant molecule"; then
                echo "$PROG: retired arm on already-delivered $id (merge_result=$merge_result)"
            else
                echo "$PROG: WARN could not retire arm on already-delivered $id" >&2; failed=$((failed + 1)); continue
            fi
            retired=$((retired + 1)); continue
        fi

        # Not dispatchable. An open bead `gctk bead holds` answers clear is the
        # one way in. A held bead waits on a wait that can clear, its own or an
        # ancestor's, and the arm stays intact for the first pass after nothing
        # holds it. An arm an ancestor's wait holds is gathered for the pass log
        # below; one its own wait holds waits on what it was armed for, and is
        # counted. A bead the read could not answer stays armed, and the pass
        # fails, since an unread hold is not a release. Any other live status is
        # never slung, so waiting for it is waiting for something no wait landing
        # can deliver. Say so every pass — the arm outlives every session that
        # could remember it, and a silent count is how it stays lost.
        if [ "$status" != "open" ]; then
            echo "$PROG: STRANDED $id is armed at status=$status, and reconcile slings open beads only — return it to open or disarm; no wait landing will dispatch it" >&2
            stranded=$((stranded + 1)); continue
        fi
        case "$holds" in
            clear) : ;;
            error)
                echo "$PROG: WARN could not read what holds $id ($hold) — leaving armed, not slinging" >&2
                failed=$((failed + 1)); continue ;;
            *)
                [ -z "$via" ] || printf '%s\t%s\n' "$via" "$id" >> "$heldf"
                held=$((held + 1)); continue ;;
        esac
        target="$(meta_of "$json" "$K_TARGET")"
        args_json="$(meta_of "$json" "$K_ARGS")"
        assignee="$(printf '%s' "$json" | jq -r '.assignee // ""')"
        [ -n "$args_json" ] || args_json="[]"

        if [ -z "$target" ]; then
            echo "$PROG: WARN $id is armed with an empty target — leaving it for a human" >&2
            failed=$((failed + 1)); continue
        fi

        # Assigned: slinging would take the bead away from its assignee.
        if [ -n "$assignee" ]; then
            echo "$PROG: ASSIGNED $id is ready but assigned to '$assignee' — not slinging; disarm or clear the assignee" >&2
            assigned=$((assigned + 1)); continue
        fi

        # The retry has a budget. Each sling attempt mints an input convoy, so a
        # dispatch that never finalizes must stop re-slinging before it leaks one
        # convoy per pass. The counter (bumped in the stamp write below) is the
        # memory a bare rollback erases. At the cap, ask a person once and leave
        # the arm — never retire an unproven dispatch — so a person decides
        # rather than reconcile looping forever. The gate blocks the bead, so the
        # re-sling waits for the answer as well as for the cleared cap. A bead
        # with an open child is asked about in a conversation instead: the cap
        # already holds the arm, and a gate on a parent would pause its unstarted
        # parts over a failed sling. One read tells, any child that is not closed
        # or pinned, and a read that fails files the gate. Past the pass budget
        # the ask waits too: the bead stays capped and armed, so the next pass
        # files it.
        fails="$(meta_of "$json" "$K_FAILS")"
        case "$fails" in ''|*[!0-9]*) fails=0 ;; esac
        if [ "$fails" -ge "$MAX_SLING_FAILURES" ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "$PROG: DRY-RUN would ask a person about capped $id ($fails failed attempts, cap $MAX_SLING_FAILURES) instead of re-slinging"
            elif ! sling_fits_budget; then
                [ "$budget_noted" = 1 ] || { budget_noted=1; echo "$PROG: pass budget spent ($(( $(now_epoch) - PASS_T0 ))s of ${PASS_BUDGET_SECS}s gone, a sling needs ${SLING_ALLOWANCE_SECS}s) — starting no further slings or asks this pass"; }
                echo "$PROG: CAPPED $id has failed to dispatch $fails times (cap $MAX_SLING_FAILURES) — not re-slinging; asking a person waits for the next pass" >&2
                ask_left_ids+=("$id")
            else
                echo "$PROG: CAPPED $id has failed to dispatch $fails times (cap $MAX_SLING_FAILURES) — not re-slinging; asking a person and leaving the arm" >&2
                cap_msg="deferred-dispatch reconcile has failed to sling armed bead $id to '$target' $fails times (cap $MAX_SLING_FAILURES), minting an input convoy on each attempt. The retry is not converging on its own — a common cause is work already delivered by another path after the arm was recorded, or a target that refuses the pour. Investigate, then disarm the bead ($SCRIPTS_DIR/deferred-dispatch.sh disarm $id), or clear gc.dispatch_when_ready_fail_count on $id to re-arm the retry."
                children="$(bd_ list --parent "$id" --include-gates --include-infra --include-templates --json --limit 1 2>/dev/null | grep -a -vE '^gc bd:' | scrub)"
                if printf '%s' "$children" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
                    if [ -x "$HELM" ]; then
                        pass_child "$HELM" open "$id" --reason "deferred dispatch has failed $fails times: disarm or re-arm" \
                          --body "$cap_msg" >/dev/null 2>&1 \
                          || echo "$PROG: WARN could not open a conversation on capped $id; it stays capped and armed, so the next pass asks again" >&2
                    else
                        echo "$PROG: WARN gc-helm.sh '$HELM' not executable — capped $id has no conversation; disarm or clear its fail count by hand" >&2
                    fi
                elif [ -x "$HUMAN_GATE" ]; then
                    pass_child "$HUMAN_GATE" --subject "$id" --key "deferred-dispatch-sling-failed.$id" \
                      --quiet-window "$CAP_QUIET_WINDOW" --message "$cap_msg Then clear this gate. It blocks $id, so the retry stays held while the gate is open, and a gate cleared while $id is still armed at the cap is asked again by a later pass." >/dev/null 2>&1 \
                      || echo "$PROG: WARN could not file the gate on capped $id; it stays capped and armed, so the next pass asks again" >&2
                else
                    echo "$PROG: WARN human-gate.sh '$HUMAN_GATE' not executable — capped $id has no gate; disarm or clear its fail count by hand" >&2
                fi
            fi
            capped=$((capped + 1)); continue
        fi

        # The pass budget. Past it, the bead keeps its arm with no marker on it,
        # this pass counts no attempt against it, and the next pass slings it. If
        # a dead pass left an unconfirmed marker, the recovery above already
        # cleared it, and the next pass re-attempts the sling just as this one
        # would have. The retires and reports for the rest of the armed set still
        # run: each retire is one write, and a retire the timeout cuts short is
        # made again by the next pass.
        if [ "$DRY_RUN" != 1 ] && ! sling_fits_budget; then
            [ "$budget_noted" = 1 ] || { budget_noted=1; echo "$PROG: pass budget spent ($(( $(now_epoch) - PASS_T0 ))s of ${PASS_BUDGET_SECS}s gone, a sling needs ${SLING_ALLOWANCE_SECS}s) — starting no further slings or asks this pass"; }
            left=$((left + 1)); left_ids+=("$id"); continue
        fi

        # A bead in flight is held only by its own waits, so a wait on an
        # ancestor leaves it running and bd keeps it out of its ready set all the
        # same. Say why it is being slung, so the pass log is legible.
        if [ -n "$flight" ]; then
            echo "$PROG: nothing holds $id: it is in flight ($flight), so only its own waits hold it, and none is pending — dispatching"
        fi

        # The arm is read once more, because the row above is the listing the pass
        # began with, and a pass can run for minutes. A disarm that landed since has
        # withdrawn this dispatch. That is what lets stand-down.sh answer a bead's
        # gate with a ruling not to proceed: it disarms first, so a pass that read
        # the gate closed reads the arm gone here, and a pass that read the gate open
        # holds the bead above. This is one read per sling, so it does not grow with
        # the armed set. A read that does not answer leaves the bead armed for the
        # next pass.
        if ! fresh="$(show_bead "$id")" || [ -z "$fresh" ]; then
            echo "$PROG: WARN could not re-read the arm on $id before slinging it — leaving armed, not slinging" >&2
            failed=$((failed + 1)); continue
        fi
        if [ -z "$(meta_of "$fresh" "$K_TARGET")" ]; then
            echo "$PROG: withdrawn $id — its arm was removed after this pass listed it; not slinging"
            retired=$((retired + 1)); continue
        fi

        # Stamp the marker in its unproven "slinging@" state, THEN sling. Dying
        # between the two leaves an unconfirmed marker, which the next pass
        # re-slings rather than retires — so a death here costs a retry, never a
        # silently lost dispatch. A sling that fails rolls the marker back so the
        # arm retries next pass. Recovery stays keyed on this one owned marker, not
        # on whichever stamp a given lane happened to leave. The same write bumps
        # the attempt counter the cap reads: an attempt is counted the moment it
        # is about to be made, so a failure or a death both leave the count raised
        # and disarm (on the eventual proven dispatch) clears it.
        if [ "$DRY_RUN" != 1 ]; then
            bd_ update "$id" --set-metadata "$K_SLUNG=$SLUNG_TRYING$(now_utc)" --set-metadata "$K_FAILS=$((fails + 1))" >/dev/null 2>&1 || {
                echo "$PROG: WARN could not stamp $K_SLUNG on $id — leaving armed, not slinging" >&2
                failed=$((failed + 1)); continue; }
        fi

        sling_bead "$id" "$target" "$args_json"; rc=$?
        if [ "$rc" != 0 ]; then
            [ "$DRY_RUN" = 1 ] || bd_ update "$id" --unset-metadata "$K_SLUNG" >/dev/null 2>&1 \
                || echo "$PROG: WARN could not roll $K_SLUNG back on $id; the next pass reads it unconfirmed and slings again" >&2
            if [ "$rc" = 3 ]; then
                echo "$PROG: WARN $id has a malformed $K_ARGS ('$args_json') — leaving armed" >&2
            else
                echo "$PROG: WARN sling of $id -> $target failed (rc=$rc) — leaving armed, retrying next pass" >&2
            fi
            failed=$((failed + 1)); continue
        fi
        if [ "$DRY_RUN" = 1 ]; then dispatched=$((dispatched + 1)); continue; fi

        # Sling returned success: promote the marker to its proven "slung@" state
        # before clearing the record, so a death in the narrow window before disarm
        # recovers as a retire, not a second sling. disarm then clears the whole
        # record, the marker included; if the store refuses this promotion,
        # disarm still clears it on this pass, and only a death before disarm
        # falls back to a re-sling next pass.
        bd_ update "$id" --set-metadata "$K_SLUNG=$SLUNG_DONE$(now_utc)" >/dev/null 2>&1 \
            || echo "$PROG: WARN could not promote $K_SLUNG on $id to slung; the disarm below clears it" >&2
        if disarm_bead "$id" "dispatched to $target by the deferred-dispatch reconcile pass"; then
            echo "$PROG: dispatched $id -> $target"
        else
            echo "$PROG: WARN $id was slung to $target but the arm could not be cleared — the next pass will retire it" >&2
        fi
        dispatched=$((dispatched + 1))
    done < "$rows"

    # A partial pass must not print a summary that reads like success.
    if [ "$processed" != "$expected" ]; then
        echo "$PROG: reconcile: enumerated $expected armed bead(s) but processed $processed — aborting rather than reporting a partial pass as complete" >&2
        return 1
    fi
    # One line per hold an ancestor's wait makes, naming the wait, its title and
    # the arms it keeps: the arms a park on an epic holds, which a pass that read
    # no ancestor would have slung. A line per arm would
    # grow with the armed set, and only the last 2 KB of a failing pass's output
    # reach its order.failed event, so the warnings above would be pushed out.
    # `list` names the hold on every arm.
    awk -F'\t' -v prog="$PROG" '
        !($1 in arms) { order[++n] = $1; arms[$1] = $2; next }
        { arms[$1] = arms[$1] " " $2 }
        END { for (i = 1; i <= n; i++) printf "%s: HELD by %s: %s\n", prog, order[i], arms[order[i]] }' "$heldf"
    local ask_left="${#ask_left_ids[@]}"
    if [ "$left" -gt 0 ]; then
        echo "$PROG: left $left ready bead(s) armed for the next pass: ${left_ids[*]}"
        LEFT_REASON="${LEFT_REASON:+$LEFT_REASON, }$left ready bead(s) left armed for the next pass"
        for id in "${left_ids[@]}"; do LEFT_SCOPES+=("$id" "sling left for the next pass"); done
    fi
    if [ "$ask_left" -gt 0 ]; then
        echo "$PROG: left the ask about $ask_left capped bead(s) for the next pass: ${ask_left_ids[*]}"
        LEFT_REASON="${LEFT_REASON:+$LEFT_REASON, }$ask_left capped bead(s) left for the next pass to ask about"
        for id in "${ask_left_ids[@]}"; do LEFT_SCOPES+=("$id" "ask left for the next pass"); done
    fi
    echo "$PROG: $dispatched dispatched, $retired retired, $held held, $stranded stranded, $assigned assigned, $capped capped, $left left for the next pass, $failed failed (of $expected armed)"
    [ "$failed" = 0 ]
}

cmd_reconcile() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --db) shift; BD_DB="${1:-}" ;;
            *) echo "$PROG: reconcile: unknown flag '$1'" >&2; return 2 ;;
        esac
        shift || true
    done
    # The pass budget counts from here, so each half spends only what the halves
    # before it left of it.
    PASS_T0="$(now_epoch)"
    # A dry run writes nothing and slings nothing, so it takes no lock and spends
    # no budget: it lists every bead a pass would sling, with or without a pass
    # in flight.
    if [ "$DRY_RUN" != 1 ]; then
        local lock_rc=0
        take_pass_lock "$STATE_DIR" "$LOCK_STALL_SECS" || lock_rc=$?
        case "$lock_rc" in
            0) ;;
            1)
                echo "$PROG: a reconcile pass is already in flight ($LOCK_NOTE) — skipping this tick"
                declare_outcome skipped "a reconcile pass is already in flight ($LOCK_NOTE)"
                return 0 ;;
            2)
                echo "$PROG: reconcile: the pass lock has been held past ${LOCK_STALL_SECS}s ($LOCK_NOTE) — the pass is wedged and nothing is dispatching" >&2
                return 1 ;;
            *)
                echo "$PROG: reconcile: single-flight UNGUARDED ($LOCK_NOTE) — refusing to read or sling without the pass lock" >&2
                return 1 ;;
        esac
    fi
    # Each half enumerates on its own, so a half that cannot read its set, or
    # stops short of it, still lets the other run. A failure in either fails the
    # pass.
    # LEFT_REASON and LEFT_SCOPES gather what the halves leave for the next pass:
    # the reason's clauses, and the bead and what was left on it, in the pairs
    # declare_outcome takes.
    local dispatch_rc=0 notice_left id
    LEFT_REASON=""; LEFT_SCOPES=()
    # A notice that fails reports itself and fails the pass at its end, so the
    # slings still run.
    reconcile_notices || true
    notice_left="${#NOTICE_LEFT_IDS[@]}"
    if [ "$notice_left" -gt 0 ]; then
        echo "$PROG: left $notice_left ready notice(s) armed for the next pass: ${NOTICE_LEFT_IDS[*]}"
        LEFT_REASON="${LEFT_REASON:+$LEFT_REASON, }$notice_left ready notice(s) left armed for the next pass"
        for id in "${NOTICE_LEFT_IDS[@]}"; do LEFT_SCOPES+=("$id" "notice left for the next pass"); done
    fi
    reconcile_dispatch || dispatch_rc=1
    # The pass declares what its halves left in one declaration. The controller
    # reads a declaration only after a run that exits 0, so a pass with a failure
    # in any half declares nothing. The controller keeps a failed run's output,
    # and the lines the pass printed about what each half left are in it.
    if [ -n "$LEFT_REASON" ] && [ "$NOTICE_FAILED" = 0 ] && [ "$dispatch_rc" = 0 ]; then
        declare_outcome partial "pass budget spent: $LEFT_REASON" "${LEFT_SCOPES[@]}"
    fi
    [ "$NOTICE_FAILED" = 0 ] && [ "$dispatch_rc" = 0 ]
}

# --- main --------------------------------------------------------------------
verb="${1:-}"; shift || true
case "$verb" in
    arm)       cmd_arm "$@" ;;
    notify)    cmd_notify "$@" ;;
    disarm)    cmd_disarm "$@" ;;
    list)      cmd_list "$@" ;;
    reconcile) cmd_reconcile "$@" ;;
    -h|--help|help|"") usage; [ -n "$verb" ] && exit 0 || exit 2 ;;
    *) echo "$PROG: unknown verb '$verb'" >&2; usage >&2; exit 2 ;;
esac
