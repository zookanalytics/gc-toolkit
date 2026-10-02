#!/usr/bin/env bash
# dead-molecule-dispose.sh — tear down a graph.v2 chain that is residue.
#
# A step bead outlives its molecule. The root closes — disposed by the witness,
# finalized, or retired — and its steps keep the status, the route and the
# dependency edges they were poured with. What is left re-offers a finished
# molecule as fresh work, or, when the head step is `blocked`, sits outside
# every readiness query where no sweep and no pool can see it at all.
#
# A chain is residue in one of two shapes:
#   * its ROOT has CLOSED — a closed root cannot produce more work, so every
#     step under it is residue whatever its own status says, and no convoy walk
#     or anchor check is needed to know it;
#   * its ROOT still reads open/in_progress/blocked but is a DEAD, UNCONTESTED
#     HUSK — a molecule parked by a prior molecule-hold whose teardown never
#     ran, or drained mid-flight, with nothing live behind it and no human still
#     owning it. A non-closed root is disposed ONLY when all three guards hold:
#       - NO LIVE SESSION: no session the root or a non-closed member names
#         (assignee, gc.session_id, gc.session_name) is active in `gc session
#         list`. Liveness that cannot be read at all refuses — an unprovable
#         death is not a death. This is dead-wisp and no-live-step together.
#       - EVERY ESCALATION ANSWERED: no visit carrying an escalation_key tracks
#         the root or its input-convoy work bead while still open. An open visit
#         is a human owning the decision, and disposing would strand it.
#       - SOURCE NOT MID-PR: the input-convoy work bead carries no merge_result
#         of pre_open_gate or pull_request — an in-flight PR the refinery owns.
#     Guard semantics mirror doctor/check-root-advancing (I13): a session is
#     live iff its state is active.
#
# TWO PHASES, and the order is the safety property. Closing a step readies its
# successor, so a chain torn down close-first passes through states where a
# pool can claim the next step — the partial teardown that mints a duplicate
# PR for already-merged code. De-routing every member FIRST makes each readied
# successor offerable to nobody, and only then do the closes run.
#
# Closes go in passes rather than in a computed order: `bd` refuses to close a
# blocked issue, so each pass closes what is currently unblocked and the chain
# unwinds from its open end. A pass that closes nothing ends the loop.
#
# Enumeration is the step beads (gc.root_bead_id == root) and the root itself;
# the input-convoy work bead is READ for the husk guards but NEVER enumerated or
# closed — only the refinery closes a work bead, on a verified merge.
#
# REFUSALS (nothing is written, and the chain is left for a human):
#   * a non-closed root with a live session, an open escalation, or a source
#     mid-PR — not residue yet, or not this script's to close;
#   * a root that will not read — an unreadable root is not a disposable one;
#   * a bead in the chain carrying `branch` or `merge_result` — that is a work
#     bead, and only the refinery closes an anchor, on a verified merge.
#
# Usage:
#   dead-molecule-dispose.sh <bead-id> [--apply] [--json] [--db <path>]
# <bead-id> is any member of the chain: the root itself, or a step carrying
# gc.root_bead_id. Without --apply this previews — it resolves and reports and
# writes nothing.
# Exit: 0 disposed, previewed, or refused with the chain intact · 1 unreadable
#       or a failed write · 2 usage · 3 PARTIAL (some writes landed, some did
#       not; the chain is half torn down and needs a human).
# NOT set -e: every failure is handled explicitly and reported.
set -uo pipefail

PROG="dead-molecule-dispose"
BOUND="${GC_DEAD_MOLECULE_TIMEOUT:-60}"
MAX_PASSES="${GC_DEAD_MOLECULE_PASSES:-10}"
# Every status a live bead can wear. A member in any of them is still standing
# and is a close candidate; anything else is already disposed.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
# The pins that make a bead offerable or bind it to a dead session. Clearing
# them is what turns a readied successor into something no pool answers for.
ROUTE_KEYS="gc.routed_to gc.run_target gc.session_id gc.session_affinity gc.continuation_group"

usage() { sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; }

BEAD=""
APPLY=0
WANT_JSON=0
BD_DB="${GC_RIG_ROOT:+$GC_RIG_ROOT/.beads}"

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --json)  WANT_JSON=1 ;;
        --db)
            if [ $# -lt 2 ]; then echo "$PROG: --db needs a value" >&2; exit 2; fi
            shift; BD_DB="$1" ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "$PROG: unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$BEAD" ]; then echo "$PROG: unexpected argument: $1" >&2; exit 2; fi
            BEAD="$1" ;;
    esac
    shift
done

[ -n "$BEAD" ] || { echo "$PROG: a bead id is required" >&2; usage >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "$PROG: jq is required" >&2; exit 1; }

run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout "$BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The store, pinned: `gc bd` resolves its ledger from the invoking rig, so an
# unpinned read answers about whatever rig gc resolves rather than the one this
# chain lives in. `--db` goes LAST, the form `gc bd <verb>` parses.
bd_() { if [ -n "$BD_DB" ]; then run_bounded gc bd "$@" --db "$BD_DB"; else run_bounded gc bd "$@"; fi; }

# `bd show --json` answers an array on a hit and an {"error":...} object on a
# miss, both at rc=0 — discriminate on type, not exit status.
show_bead() { # id -> single bead object on stdout, or nothing (rc 1)
    local raw
    raw="$(bd_ show "$1" --json 2>/dev/null)" || return 1
    [ -n "$raw" ] || return 1
    printf '%s' "$raw" | scrub | jq -ce '
        if type == "array" then (.[0] // empty)
        elif type == "object" then (if has("error") then empty else . end)
        else empty end' 2>/dev/null
}

meta_of() { printf '%s' "$1" | jq -r --arg k "$2" '((.metadata // {})[$k] // "") | tostring' 2>/dev/null; }

refuse() { # <result> <detail>
    emit "$1" "$2"
    exit 0
}

FAILED=""
CLEARED=0
CLOSED=0
MEMBERS=""
ROOT=""

emit() { # <result> <detail>
    local result="$1" detail="${2:-}"
    if [ "$WANT_JSON" = "1" ]; then
        jq -cn --arg bead "$BEAD" --arg root "$ROOT" --arg result "$result" \
            --arg detail "$detail" --arg failed "$FAILED" \
            --argjson cleared "$CLEARED" --argjson closed "$CLOSED" \
            --arg members "$MEMBERS" '
            {bead: $bead, root: ($root | select(. != "") // null), result: $result,
             members: ($members | select(. != "") // null),
             deroutes: $cleared, closes: $closed,
             failed: ($failed | select(. != "") // null),
             detail: ($detail | select(. != "") // null)}'
    else
        printf 'result=%s bead=%s' "$result" "$BEAD"
        [ -n "$ROOT" ] && printf ' root=%s' "$ROOT"
        [ -n "$MEMBERS" ] && printf ' members=%s' "$MEMBERS"
        printf ' deroutes=%s closes=%s' "$CLEARED" "$CLOSED"
        [ -n "$FAILED" ] && printf ' failed=%s' "$FAILED"
        [ -n "$detail" ] && printf ' detail=%s' "$detail"
        printf '\n'
    fi
}

# --- resolve the root --------------------------------------------------------
SELF_JSON="$(show_bead "$BEAD")" || SELF_JSON=""
[ -n "$SELF_JSON" ] || { echo "$PROG: cannot read $BEAD — nothing disposed" >&2; emit unreadable "bead_unreadable"; exit 1; }

SELF_ROOT="$(meta_of "$SELF_JSON" gc.root_bead_id)"
SELF_KIND="$(meta_of "$SELF_JSON" gc.kind)"
SELF_CONTRACT="$(meta_of "$SELF_JSON" gc.formula_contract)"

if [ -n "$SELF_ROOT" ]; then
    ROOT="$SELF_ROOT"
elif [ "$SELF_KIND" = "workflow" ] || [ "$SELF_CONTRACT" = "graph.v2" ]; then
    # gascity's own IsWorkflowRoot: a root carries gc.kind=workflow or
    # gc.formula_contract=graph.v2, and a step carries neither.
    ROOT="$BEAD"
else
    echo "$PROG: $BEAD is neither a workflow root nor a step (no gc.root_bead_id, no gc.kind/gc.formula_contract) — nothing disposed" >&2
    refuse refused "not_a_molecule"
fi

ROOT_JSON="$(show_bead "$ROOT")" || ROOT_JSON=""
if [ -z "$ROOT_JSON" ]; then
    echo "$PROG: cannot read root $ROOT — an unreadable root is not a closed one; nothing disposed" >&2
    emit unreadable "root_unreadable"
    exit 1
fi
ROOT_STATUS="$(printf '%s' "$ROOT_JSON" | jq -r '.status // ""')"
# A closed root is residue outright. A root that still reads open/in_progress/
# blocked is live machinery UNLESS it is a dead, uncontested husk — a verdict
# that needs the enumerated chain and the input convoy, so it is deferred to the
# guarded block below (after the anchor refuse). Here we only record the shape.
ROOT_NOT_CLOSED=0
[ "$ROOT_STATUS" = "closed" ] || ROOT_NOT_CLOSED=1

# --- enumerate the chain -----------------------------------------------------
# Unreadable is not empty: a failed listing must never read as a clean chain.
ALL="$(bd_ list --status "$LIVE_STATUSES" --json --limit 0 2>/dev/null | scrub)" || ALL=""
if [ -z "$ALL" ] || ! printf '%s' "$ALL" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "$PROG: could not list live beads — NOT treating that as an empty chain; nothing disposed" >&2
    emit unreadable "listing_unreadable"
    exit 1
fi

MEMBER_LIST="$(printf '%s' "$ALL" | jq -r --arg r "$ROOT" '
    [ .[] | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r or .id == $r) | .id ] | .[]' 2>/dev/null)"
MEMBERS="$(printf '%s' "$MEMBER_LIST" | tr '\n' ',' | sed 's/,$//')"

if [ -z "$MEMBER_LIST" ]; then
    emit clean "chain_already_disposed"
    exit 0
fi

# A step or control bead carries no work product. `branch` and `merge_result`
# are an anchor's keys, and an anchor closes from merge-push on a verified
# merge and from nowhere else — including here.
ANCHORS="$(printf '%s' "$ALL" | jq -r --arg r "$ROOT" '
    [ .[]
      | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r or .id == $r)
      | select((((.metadata["branch"] // "") | tostring) != "") or (((.metadata["merge_result"] // "") | tostring) != ""))
      | .id ] | join(",")' 2>/dev/null)"
if [ -n "$ANCHORS" ]; then
    echo "$PROG: chain under $ROOT contains work bead(s) $ANCHORS (branch/merge_result set) — REFUSING the teardown; only the refinery closes an anchor" >&2
    refuse refused "work_bead_in_chain=$ANCHORS"
fi

# --- a non-closed root: dispose only a dead, uncontested husk -----------------
# The default verdict on a root that still reads open/in_progress/blocked is
# live_root — machinery, not residue. Three fail-closed guards are what let one
# through. Every guard runs in preview too, so a preview reports the same
# verdict apply would reach. Guard semantics mirror
# doctor/check-root-advancing (I13): a session is live iff its state is active.
if [ "$ROOT_NOT_CLOSED" = "1" ]; then
    # GUARD 1 — NO LIVE SESSION (dead-wisp + no-live-step). Refuse if any session
    # the root or a non-closed member names is active, OR if liveness cannot be
    # read at all: an unprovable death is not a death.
    SESS_RAW="$(run_bounded gc session list --json 2>/dev/null)"; SESS_RC=$?
    SESS="$(printf '%s' "$SESS_RAW" | scrub | jq -c '[(.sessions // [])[]? | select(type == "object")]' 2>/dev/null)"
    if [ "$SESS_RC" -ne 0 ] || [ -z "$SESS" ] || [ "$SESS" = "[]" ] \
       || ! printf '%s' "$SESS" | jq -e 'any(.[]?; has("state") or has("running"))' >/dev/null 2>&1; then
        echo "$PROG: root $ROOT is $ROOT_STATUS and \`gc session list\` could not establish liveness — an unprovable death is not a death; nothing disposed" >&2
        refuse live_root "root_status=$ROOT_STATUS,liveness_undetermined"
    fi
    # A live-identity set, keyed on every name an active session carries (id,
    # session_name, alias); then the first chain name that is in it. A name the
    # root or a non-closed member carries as its assignee, gc.session_id or
    # gc.session_name — any of the three forms a claim writes.
    declare -A LIVE_SET=()
    while IFS= read -r _id; do
        [ -n "$_id" ] && LIVE_SET["$_id"]=1
    done <<EOF
$(printf '%s' "$SESS" | jq -r '.[] | select(((.state // "") | tostring) == "active" or (.running == true)) | (.id, .session_name, .alias) | select((. // "") != "")' 2>/dev/null)
EOF
    LIVE_SESSION=""
    while IFS= read -r _cand; do
        [ -n "$_cand" ] || continue
        if [ -n "${LIVE_SET[$_cand]:-}" ]; then LIVE_SESSION="$_cand"; break; fi
    done <<EOF
$(printf '%s' "$ALL" | jq -r --arg r "$ROOT" '.[] | select(((.metadata["gc.root_bead_id"] // "") | tostring) == $r or .id == $r) | (.assignee // ""), (.metadata["gc.session_id"] // ""), (.metadata["gc.session_name"] // "")' 2>/dev/null)
EOF
    if [ -n "$LIVE_SESSION" ]; then
        echo "$PROG: root $ROOT is $ROOT_STATUS and a live session ($LIVE_SESSION) still stands behind it — machinery, not residue; nothing disposed" >&2
        refuse live_root "root_status=$ROOT_STATUS,live_session=$LIVE_SESSION"
    fi

    # Resolve the input convoy's single tracked work bead, store-pinned. `gc
    # convoy status` takes no --db, so walk the tracks edge with bd: the convoy
    # TRACKS the work bead. The work bead is read for guards 2 and 3; it is never
    # enumerated or closed. A convoy present but unreadable fails closed.
    CONVOY="$(meta_of "$ROOT_JSON" gc.input_convoy_id)"
    WORK_BEAD=""
    if [ -n "$CONVOY" ]; then
        WB_RAW="$(bd_ dep list "$CONVOY" --direction=down -t tracks --json 2>/dev/null | scrub)"
        if ! printf '%s' "$WB_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$PROG: root $ROOT is $ROOT_STATUS but its input convoy $CONVOY would not read — cannot prove the work has no open PR or escalation; nothing disposed" >&2
            refuse refused "convoy_unreadable=$CONVOY"
        fi
        WORK_BEAD="$(printf '%s' "$WB_RAW" | jq -r '[ .[]? | .id ] | (.[0] // "")')"
    fi

    # GUARD 2 — SOURCE NOT MID-PR. An in-flight PR is the refinery's to land, so
    # disposing the molecule under it would orphan the PR. Mirrors
    # orphan-dispose.sh's source-arm inflight_pr skip.
    if [ -n "$WORK_BEAD" ]; then
        WB_JSON="$(show_bead "$WORK_BEAD")" || WB_JSON=""
        if [ -z "$WB_JSON" ]; then
            echo "$PROG: root $ROOT is $ROOT_STATUS but its work bead $WORK_BEAD would not read — cannot prove it has no open PR; nothing disposed" >&2
            refuse refused "work_bead_unreadable=$WORK_BEAD"
        fi
        WB_MR="$(meta_of "$WB_JSON" merge_result)"
        case "$WB_MR" in
            pre_open_gate|pull_request)
                echo "$PROG: root $ROOT is $ROOT_STATUS but its work bead $WORK_BEAD carries merge_result=$WB_MR (a PR the refinery owns) — nothing disposed" >&2
                refuse refused "source_inflight_pr=$WB_MR" ;;
        esac
    fi

    # GUARD 3 — EVERY ESCALATION ANSWERED. A visit carrying an escalation_key and
    # still open, tracking the root or its work bead, is a human owning the
    # decision; disposing would strand that visit. The input convoy tracks the
    # work bead too, so the escalation_key filter is what separates a visit from
    # the convoy. A tracks read that will not parse fails closed.
    for SUBJ in "$ROOT" "$WORK_BEAD"; do
        [ -n "$SUBJ" ] || continue
        TRK_RAW="$(bd_ dep list "$SUBJ" --direction=up -t tracks --json 2>/dev/null | scrub)"
        if ! printf '%s' "$TRK_RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
            echo "$PROG: root $ROOT is $ROOT_STATUS but the tracking edges on $SUBJ would not read — cannot prove no open escalation; nothing disposed" >&2
            refuse refused "tracks_unreadable=$SUBJ"
        fi
        OPEN_VISIT="$(printf '%s' "$TRK_RAW" | jq -r '
            [ .[]? | select((((.metadata["escalation_key"] // "") | tostring) != "") and ((.status // "") != "closed")) | .id ] | (.[0] // "")' 2>/dev/null)"
        if [ -n "$OPEN_VISIT" ]; then
            echo "$PROG: root $ROOT is $ROOT_STATUS and an open escalation visit ($OPEN_VISIT) still tracks $SUBJ — a human owns this; nothing disposed" >&2
            refuse refused "open_escalation=$OPEN_VISIT"
        fi
    done
fi

if [ "$APPLY" != "1" ]; then
    emit preview "would_deroute_and_close"
    exit 0
fi

note_failed() { FAILED="${FAILED:+$FAILED,}$1"; }

# Why the chain is residue — a closed root, or a dead husk the guards cleared.
if [ "$ROOT_NOT_CLOSED" = "1" ]; then
    DISPOSE_REASON="molecule root $ROOT is a dead husk (status=$ROOT_STATUS, no live session, no open escalation, no in-flight PR)"
else
    DISPOSE_REASON="molecule root $ROOT is closed"
fi

# --- phase 1: de-route every member, before anything closes ------------------
# Metadata writes do not go through bd's claim guard, so this half lands even
# on a bead a live actor holds.
while IFS= read -r M; do
    [ -n "$M" ] || continue
    UNSETS=()
    for K in $ROUTE_KEYS; do UNSETS+=(--unset-metadata "$K"); done
    if bd_ update "$M" ${UNSETS[@]+"${UNSETS[@]}"} >/dev/null 2>&1; then
        CLEARED=$((CLEARED + 1))
    else
        note_failed "deroute($M)"
    fi
done <<EOF
$MEMBER_LIST
EOF

# A member left routed can still be offered the moment a close readies it, so
# a failed de-route stops the teardown before the first close.
if [ -n "$FAILED" ]; then
    echo "$PROG: could not de-route every member of $ROOT ($FAILED) — stopping BEFORE any close, so no step is readied while still routed" >&2
    emit partial "deroute_incomplete"
    exit 3
fi

# --- phase 2: close what is unblocked, pass by pass ---------------------------
# 0 while an open blocker (or an unreadable probe) holds the bead: an
# unreadable dep listing must not read as an unblocked bead.
blocked_now() {
    local rows
    rows="$(bd_ dep list "$1" --direction=down -t blocks --json 2>/dev/null | scrub)"
    printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0
    printf '%s' "$rows" | jq -e '[ .[] | select((.status // "open") != "closed") ] | length > 0' >/dev/null 2>&1
}

PASS=0
REMAINING="$MEMBER_LIST"
while [ -n "$REMAINING" ] && [ "$PASS" -lt "$MAX_PASSES" ]; do
    PASS=$((PASS + 1))
    PROGRESS=0
    NEXT=""
    while IFS= read -r M; do
        [ -n "$M" ] || continue
        if blocked_now "$M"; then NEXT="${NEXT}${M}"$'\n'; continue; fi
        if bd_ update "$M" --status=closed \
              --set-metadata gc.outcome=moot \
              --set-metadata gc.work_outcome=no-op \
              --append-notes "$PROG: $DISPOSE_REASON; this step is residue — de-routed and closed, no re-dispatch." >/dev/null 2>&1; then
            # A write that reports success and rolls back is the failure this
            # re-read exists to catch.
            AFTER="$(show_bead "$M")" || AFTER=""
            if [ -n "$AFTER" ] && [ "$(printf '%s' "$AFTER" | jq -r '.status // ""')" = "closed" ]; then
                CLOSED=$((CLOSED + 1)); PROGRESS=$((PROGRESS + 1)); continue
            fi
        fi
        note_failed "close($M)"
        NEXT="${NEXT}${M}"$'\n'
    done <<EOF
$REMAINING
EOF
    REMAINING="$(printf '%s' "$NEXT" | sed '/^$/d')"
    [ "$PROGRESS" -gt 0 ] || break
done

if [ -n "$REMAINING" ]; then
    LEFT="$(printf '%s' "$REMAINING" | tr '\n' ',' | sed 's/,$//')"
    echo "$PROG: $ROOT still has unclosed member(s) $LEFT after $PASS pass(es) — they are de-routed, so no pool can claim them, but the chain needs a human" >&2
    emit partial "unclosed=$LEFT"
    exit 3
fi

emit disposed "passes=$PASS"
exit 0
