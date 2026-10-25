#!/usr/bin/env bash
# orphan-dispose.sh — dispose of ONE bead that orphan recovery classified as
# orphaned, by the kind of thing the bead is.
#
# Each kind is disposed by what it is; the rule for each is below. Some kinds
# return a bead to a pool to be claimed again, and some of those return it only
# when its work has not already reached a downstream court.
#
#   visit          release the sitting and keep the visit. The assignee and the
#                  session pins (gc.session_id, gc.session_name) name the
#                  sitting that is gone. The route, continuation group and
#                  task_kind are the visit's identity and are never written.
#                  Released, the visit names no owner, so orphan recovery does
#                  not find it again, and the helm board reads it as parked,
#                  under the headline engage's reclaim of a gone sitting
#                  writes.
#   review         a review bead is the source bead of its own mol-review
#                  molecule and carries no worktree of its own, so it disposes by
#                  the source contract below (delete-source is a no-op on an
#                  input-convoy root, reopen-source returns it to its review
#                  pool). It is recognised by task_kind before the source arm the
#                  way a visit is, and the witness salvage scope gate skips its
#                  worktree salvage and merge-verify for the same reason.
#   workflow-root  skip. A graph.v2 root is not schedulable work: nothing
#                  claims it, and it closes when its workflow-finalize step
#                  closes. Setting it open+unassigned+routed is what makes a
#                  pool offer the root itself as work. Its chain is recovered
#                  through its steps, which are candidates in their own right.
#   workflow-step  release the dead session's pin and preserve the chain. The
#                  step keeps gc.routed_to, gc.step_ref, gc.root_bead_id and
#                  its dependency edges, so the molecule resumes at the same
#                  step under whichever pool member claims it next.
#   workflow-step-dead
#                  the step's root has CLOSED, so there is no molecule left to
#                  resume and releasing it would offer a finished chain to a
#                  pool as fresh work. Delegate to run-cancel.sh --ended, which
#                  ends what the run left open through gascity's own close of a
#                  workflow and writes no member itself.
#   workflow-step-unresolved
#                  the step names a root that will not read. An unreadable root
#                  is not a live one, so nothing is written: the step stays
#                  owned and returns next cycle.
#   source         delegate to `gc workflow delete-source --apply` plus
#                  `gc workflow reopen-source`, the contract those commands were
#                  built for, then clear the session pins so the pooled bead
#                  stops naming a dead owner, and restore gc.routed_to from the
#                  durable gc.execution_routed_to stamp so the reopened bead is
#                  offered again rather than left bd-ready but unrouted. EXCEPT
#                  when the work already reached a downstream court — an in-flight
#                  PR (merge_result pre_open_gate/pull_request) the refinery owns
#                  landing, or a human gate (gc.routed_to=human) a person owns
#                  clearing: reopening would return that work to the pool — skip it.
#
# The root read is what separates the two step arms, and it is a read of the
# root itself — not of the input convoy, and not of the anchors it tracks. A
# closed root cannot produce work whatever those say.
#
# `delete-source` matches workflow roots on gc.source_bead_id. A root poured
# from an input convoy never carries that key, so it reports already_clean for
# graph.v2 chains whichever of their ids it is handed, and `reopen-source`
# then runs alone. That is why the source arm is not the disposal for a step or
# a root: reopening either one hands live molecule machinery to a pool.
#
# A visit or step release is ONE write. bd applies an update as one operation
# and checks its --if-assignee and --if-status guards inside it, so the pins,
# the status and the assignee land together or not at all, and a release never
# leaves part of itself on a bead another writer has taken since this script
# read it. The source arm writes only after reopen-source has released the
# bead, so its writes carry no guard. Every release is verified by re-reading
# the bead.
#
# A disposal acts only on the claim orphan recovery found dead: the owner whose
# session it proved gone, and the status and assignee its listing showed beside
# that owner. The bead must still carry that claim when this script reads it,
# and a visit or step release is guarded on the status and assignee the read
# found, so a bead another holder takes before or during the release keeps that
# holder's claim.
#
# Usage:
#   orphan-dispose.sh <bead-id> [--claim <owner>:<status>:<assignee>] [--apply] [--json]
# Without --apply this previews: it classifies and prints, and writes nothing.
#   --claim <owner>:<status>:<assignee>
#                    the claim orphan recovery judged dead: the owner whose
#                    session it found gone, and the status and assignee its
#                    listing read beside that owner, joined by colons. The
#                    assignee may be empty. A bead that no longer carries that
#                    claim, or is no longer open or in_progress, is skipped with
#                    nothing written. Without --claim nothing is compared.
#   --json           emit the result as one JSON object instead of key=value.
# Exit: 0 disposed or previewed · 1 unreadable bead or failed write ·
#       2 usage · 3 PARTIAL write (some fields landed, some did not).
# NOT set -e: every failure is handled explicitly and reported.
set -uo pipefail

usage() {
    sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'
}

BEAD=""
CLAIM=""
CLAIM_SET=0
APPLY=0
WANT_JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --json)  WANT_JSON=1 ;;
        --claim)
            if [ $# -lt 2 ]; then echo "orphan-dispose: --claim needs a value" >&2; exit 2; fi
            shift; CLAIM="$1"; CLAIM_SET=1
            ;;
        --claim=*) CLAIM="${1#--claim=}"; CLAIM_SET=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "orphan-dispose: unknown flag: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$BEAD" ]; then echo "orphan-dispose: unexpected argument: $1" >&2; exit 2; fi
            BEAD="$1"
            ;;
    esac
    shift
done

[ -n "$BEAD" ] || { echo "orphan-dispose: a bead id is required" >&2; usage >&2; exit 2; }
# The claim is compared whole, never split, so an owner or assignee that carries
# a colon still compares as itself. Only its shape is checked here: an owner and
# a status before the second colon.
if [ "$CLAIM_SET" = "1" ]; then
    case "$CLAIM" in
        ?*:?*:*) ;;
        *) echo "orphan-dispose: --claim takes <owner>:<status>:<assignee>, got '$CLAIM'" >&2; exit 2 ;;
    esac
fi
command -v jq >/dev/null 2>&1 || { echo "orphan-dispose: jq is required" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

read_bead() { gc bd show "$1" --json 2>/dev/null | scrub; }

# The strip mol-witness-patrol's candidate listing runs over bd's JSON before
# its first jq. A formula block stays backslash-free, so the listing names the
# control class rather than the C0 range scrub removes, and the class also takes
# DEL and, in a UTF-8 locale, characters past it such as U+0085 and U+200B. The
# claim check compares through it.
# >>> listing-strip
listing_strip() { tr -d '[:cntrl:]'; }
# <<< listing-strip

# The headline a released visit re-parks under: the one `gc-helm engage` writes
# when it reclaims a visit from a gone sitting, so the board reads the two the
# same.
# >>> gone-sitting-takeaway
GONE_SITTING_TAKEAWAY="Reclaimed from a gone sitting; re-parked for re-engagement."
# <<< gone-sitting-takeaway

# Resolved from $0 so a copy of this script runs against the copy beside it.
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
RUN_CANCEL="${GC_RUN_CANCEL_TOOL:-$HERE/run-cancel.sh}"

# The source arm's two `gc workflow` calls run under a hard bound. They are slow
# rather than stuck: each scans every store in the city, and a healthy call takes
# tens of seconds on a loaded host, so the bound sits well above that. Once
# either command holds its per-bead lock, SIGTERM no longer stops it: the signal
# only cancels a lock wait, and the work inside the lock runs to completion. A
# TERM-only timeout would wait as long as the command does, so -k follows the
# TERM with SIGKILL after a grace. The same deferral means a timeout exit (124,
# or 137 after the KILL) does not prove the call wrote nothing, because the
# command can finish its writes after the timer fires. So a timed-out
# delete-source counts as failed, and a timed-out reopen-source is judged by
# re-reading the bead.
WORKFLOW_BOUND="${GC_ORPHAN_WORKFLOW_TIMEOUT:-180}"
WORKFLOW_KILL_AFTER="${GC_ORPHAN_WORKFLOW_KILL_AFTER:-30}"
run_bounded() { if command -v timeout >/dev/null 2>&1; then timeout -k "$WORKFLOW_KILL_AFTER" "$WORKFLOW_BOUND" "$@" </dev/null; else "$@" </dev/null; fi; }
timed_out() { [ "$1" -eq 124 ] || [ "$1" -eq 137 ]; }

BEAD_JSON="$(read_bead "$BEAD")"
if ! printf '%s' "$BEAD_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    echo "orphan-dispose: cannot read $BEAD — nothing disposed" >&2
    exit 1
fi

META="$(printf '%s' "$BEAD_JSON" | jq -c '.[0].metadata // {}')"
STATUS="$(printf '%s' "$BEAD_JSON" | jq -r '.[0].status // ""')"
ASSIGNEE="$(printf '%s' "$BEAD_JSON" | jq -r '.[0].assignee // ""')"
mval() { printf '%s' "$META" | jq -r --arg k "$1" '.[$k] // ""'; }

TASK_KIND="$(mval task_kind)"
KIND="$(mval gc.kind)"
CONTRACT="$(mval gc.formula_contract)"
STEP_REF="$(mval gc.step_ref)"
ROOT_ID="$(mval gc.root_bead_id)"
ROUTED="$(mval gc.routed_to)"
MERGE_RESULT="$(mval merge_result)"

# Classification order matters. A visit and a review are each the source bead of
# their own molecule (mol-visit, mol-review), so both must be recognised by
# task_kind before the source arm would claim them. Root before step: gascity's
# own IsWorkflowRoot is gc.kind=workflow OR gc.formula_contract=graph.v2, and a
# step carries neither.
if [ "$TASK_KIND" = "visit" ]; then
    CLASS="visit"
elif [ "$TASK_KIND" = "review" ]; then
    CLASS="review"
elif [ "$KIND" = "workflow" ] || [ "$CONTRACT" = "graph.v2" ]; then
    CLASS="workflow-root"
elif [ -n "$STEP_REF" ]; then
    CLASS="workflow-step"
else
    CLASS="source"
fi

# A step is only worth resuming while its molecule can still produce work, and
# the root's own status settles that. Releasing a step whose root has CLOSED
# does not resume anything — it hands a finished molecule back to a pool as
# fresh work. So the root is read before the release arm, and an unreadable
# root is not a live one: it withholds the release rather than guessing.
ROOT_STATUS=""
if [ "$CLASS" = "workflow-step" ] && [ -n "$ROOT_ID" ]; then
    ROOT_JSON="$(read_bead "$ROOT_ID")"
    if printf '%s' "$ROOT_JSON" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        ROOT_STATUS="$(printf '%s' "$ROOT_JSON" | jq -r '.[0].status // ""')"
        [ "$ROOT_STATUS" = "closed" ] && CLASS="workflow-step-dead"
    else
        ROOT_STATUS="unreadable"
        CLASS="workflow-step-unresolved"
    fi
fi

# The claim check. Orphan recovery resolves a bead's owner as the first
# non-empty of gc.session_id, the assignee and gc.session_name, finds that
# owner's session dead, and passes that owner, with the status and assignee it
# listed beside it, as --claim. It judged the bead from that listing, and a
# holder can take the bead before this read: `gc-helm engage` reclaims a visit
# bound to a gone sitting and binds a fresh one, and a pool claims a step whose
# dead holder Gas City released. So this read resolves the owner the same way
# and compares the whole claim, because no one part of it settles the question.
# A session that claims a step under the pool's alias, as a named session, a
# namepool member or an explicit `gc hook <agent>` target does, leaves the
# assignee and status as they were listed, and only the owner, the
# gc.session_id its claim stamps, tells it apart. A visit re-bound by a writer
# that leaves an earlier sitting's pin on it resolves the listed owner again,
# and only the assignee tells it apart. A bead whose claim differs from the
# listed one, or that is no longer open or in_progress, the statuses recovery
# lists, is not the claim recovery judged, and it is skipped with nothing
# written.
#
# The listed claim was read through the listing's strip, which removes
# characters this read keeps, so both claims are compared through that strip.
# A claim nobody changed then reads unchanged however its values are spelled,
# and its dead holder is released rather than skipped every cycle. The guards
# below still carry the assignee and status exactly as the store holds them.
READ_OWNER="$(printf '%s' "$BEAD_JSON" | jq -r '.[0]
    | [ (.metadata["gc.session_id"] // ""), (.assignee // ""), (.metadata["gc.session_name"] // "") ]
    | map(select(. != "")) | first // ""')"
CLAIM_CHANGED=""
if [ "$CLAIM_SET" = "1" ]; then
    if [ "$(printf '%s' "$CLAIM" | listing_strip)" != "$(printf '%s' "$READ_OWNER:$STATUS:$ASSIGNEE" | listing_strip)" ] \
        || { [ "$STATUS" != "open" ] && [ "$STATUS" != "in_progress" ]; }; then
        CLAIM_CHANGED="claim_changed(owner=${READ_OWNER:-none},status=${STATUS:-none},assignee=${ASSIGNEE:-none})"
    fi
fi
REPORT_OWNER="$ASSIGNEE"
[ "$CLAIM_SET" = "1" ] && REPORT_OWNER="$READ_OWNER"

# The conditional guards. HELD_BY and HELD_STATUS are the assignee and status
# this read found, which the claim check above has matched to --claim when it
# was given. A visit or step release carries them as bd's --if-assignee and
# --if-status, which bd checks inside the write: once the bead's assignee or
# status has moved, the write lands nothing and exits 13. LOST then names the
# refused write, and the bead is skipped as the writer that moved it left it.
# bd compares no metadata, so a holder that takes the bead without moving its
# assignee or status is caught only by the claim check above.
#
# A guard's value is attached (--if-assignee=<v>), never a separate argument.
# gc bd picks the store from the bead ids among a command's arguments, and a
# session-id assignee names a real bead in the city store. An attached value is
# never read as one of those ids, so only $BEAD selects the store.
HELD_BY="$ASSIGNEE"
HELD_STATUS="$STATUS"
LOST=""

FAILED=""
LANDED=""
EXPECT_ROUTE=""

note_failed() { FAILED="${FAILED:+$FAILED,}$1"; }
note_landed() { LANDED="${LANDED:+$LANDED,}$1"; }

# pin_args [--keep-continuation] sets PIN_ARGS to one --unset-metadata pair for
# each pin a release removes. gc.session_id and gc.session_name name the
# session a claim ran in, and both always go. Orphan recovery resolves a bead's
# owner as the first non-empty of gc.session_id, the assignee, then
# gc.session_name, so one left behind keeps resolving the dead session as the
# owner once the bead is unassigned, and re-detects it every cycle. The helm
# board also reads a visit whose gc.session_name is set as engaged.
# gc.session_affinity and gc.continuation_group tie a step to the session that
# ran its chain, and go with it. --keep-continuation keeps those two on a
# visit, whose continuation group is its subject rather than a pin. Removing an
# absent key changes nothing.
pin_args() {
    PIN_ARGS=(--unset-metadata gc.session_id --unset-metadata gc.session_name)
    [ "${1:-}" = "--keep-continuation" ] \
        || PIN_ARGS+=(--unset-metadata gc.session_affinity --unset-metadata gc.continuation_group)
}

# release <update args...> releases a visit or a step in ONE write under the
# conditional guards: the args given, open status and no assignee. bd applies
# the whole update as one operation and checks the guards inside it, so the
# release lands whole or not at all. bd fences an assignee change on another
# actor's in_progress claim, except a change whose --if-assignee names that
# actor, so the release needs no --force, which bd refuses beside --if-assignee.
release() {
    local rc=0
    gc bd update "$BEAD" "$@" --status=open --assignee "" \
        --if-assignee="$HELD_BY" --if-status="$HELD_STATUS" >/dev/null 2>&1 || rc=$?
    case "$rc" in
        0)  note_landed release ;;
        13) LOST=release ;;
        *)  note_failed release ;;
    esac
}

# plain_update <field> <update args...> writes without the guards. The source
# arm writes only after reopen-source has released the bead, so the claim
# recovery judged is no longer there to guard on.
plain_update() {
    local field="$1"
    shift
    if gc bd update "$BEAD" "$@" >/dev/null 2>&1; then
        note_landed "$field"
    else
        note_failed "$field"
    fi
}

# restore_route puts gc.routed_to back on a source bead reopen-source returned
# to the pool. reopen-source reopens the bead but preserves the route it finds,
# and a bead reaches recovery with gc.routed_to already emptied by its own claim,
# so the reopened bead lands open, unassigned and unrouted. gc.routed_to is half
# a pool's offer predicate, so that bead is bd-ready yet never offered again —
# the strand this restore prevents. The claim that emptied gc.routed_to left
# gc.execution_routed_to, the durable dispatch route stamped at the pour, in
# place, so the offer route is restored from it. A route already present is left
# alone: reopen-source or a source-id workflow may have set one, and a live route
# is never clobbered. With no execution route to copy the bead cannot be offered,
# and leaving it silent recreates the strand, so that case is a failed release
# the patrol surfaces rather than a clean disposal. Metadata bypasses the claim
# guard, so the write always lands; verify confirms it against EXPECT_ROUTE.
restore_route() {
    local after routed_now exec_route
    after="$(read_bead "$BEAD")"
    printf '%s' "$after" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || { note_failed route-reread; return; }
    routed_now="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.routed_to"] // ""')"
    [ -n "$routed_now" ] && return 0
    exec_route="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.execution_routed_to"] // ""')"
    if [ -z "$exec_route" ]; then
        note_failed route-unrecoverable
        return
    fi
    if gc bd update "$BEAD" --set-metadata gc.routed_to="$exec_route" >/dev/null 2>&1; then
        note_landed route
        EXPECT_ROUTE="$exec_route"
    else
        note_failed route
    fi
}

# verify re-reads the bead and confirms the release actually landed. A write
# that reports success and rolls back is the failure this exists to catch. A
# release a conditional guard stopped has left the bead to whoever took it, so
# there is nothing of this release's to verify.
verify() {
    [ -z "$LOST" ] || return 0
    local after
    after="$(read_bead "$BEAD")"
    printf '%s' "$after" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || {
        note_failed reread
        return
    }
    local st asg sid sname
    st="$(printf  '%s' "$after" | jq -r '.[0].status // ""')"
    asg="$(printf '%s' "$after" | jq -r '.[0].assignee // ""')"
    sid="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.session_id"] // ""')"
    sname="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.session_name"] // ""')"
    [ "$st"  = "open" ] || note_failed "status(still=$st)"
    [ -z "$asg" ]       || note_failed "assignee(still=$asg)"
    # The arms that clear session pins — visit, workflow-step, source and review —
    # must land it: a surviving pin is exactly what makes orphan recovery
    # re-detect the bead.
    case "$CLASS" in
        visit|workflow-step|source|review)
            [ -n "$sid" ]   && note_failed "gc.session_id(still=$sid)"
            [ -n "$sname" ] && note_failed "gc.session_name(still=$sname)"
            ;;
    esac
    # A visit's headline is read back like its pins: one that reports written
    # and rolls back leaves the board showing what the gone sitting last wrote.
    if [ "$CLASS" = "visit" ]; then
        local tk
        tk="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.takeaway"] // ""')"
        [ "$tk" = "$GONE_SITTING_TAKEAWAY" ] || note_failed "gc.takeaway(got=${tk:-empty})"
    fi
    # A restored route must survive the re-read: a gc.routed_to that reports set
    # and rolls back would strand the reopened bead exactly as before.
    if [ -n "$EXPECT_ROUTE" ]; then
        local rt
        rt="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.routed_to"] // ""')"
        [ "$rt" = "$EXPECT_ROUTE" ] || note_failed "gc.routed_to(want=$EXPECT_ROUTE,got=${rt:-empty})"
    fi
    return 0
}

# released_on_reread re-reads the bead and answers whether it reads released:
# open and unassigned. The source arm asks it about a reopen-source that ran
# past its bound, whose exit code cannot say whether the release landed.
released_on_reread() {
    read_bead "$BEAD" | jq -e 'type == "array" and length > 0
        and .[0].status == "open" and ((.[0].assignee // "") == "")' >/dev/null 2>&1
}

ACTION=""
DETAIL=""

# A bead that no longer carries the claim recovery judged takes no write,
# whatever it is.
DISPOSAL="$CLASS"
[ -z "$CLAIM_CHANGED" ] || DISPOSAL="claim-changed"

case "$DISPOSAL" in
    claim-changed)
        ACTION="skip"
        DETAIL="$CLAIM_CHANGED"
        ;;
    visit)
        # Release the sitting and keep the visit: the pins and the assignee go,
        # and the route, continuation group and task_kind that ARE the visit are
        # never written. The visit parks again, so the release writes the
        # headline the board shows for it, and clears the settled flag the gone
        # sitting may have left beside its own, the way engage's reclaim does.
        ACTION="release-visit"
        if [ "$APPLY" = "1" ]; then
            pin_args --keep-continuation
            release "${PIN_ARGS[@]}" \
                --set-metadata "gc.takeaway=$GONE_SITTING_TAKEAWAY" \
                --set-metadata "gc.takeaway_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --set-metadata gc.takeaway_by=witness \
                --set-metadata gc.takeaway_settled=
            verify
        fi
        ;;
    workflow-root)
        ACTION="skip"
        DETAIL="root_not_schedulable"
        ;;
    workflow-step)
        ACTION="release-step"
        [ -z "$ROUTED" ] && DETAIL="routed=absent"
        if [ "$APPLY" = "1" ]; then
            pin_args
            release "${PIN_ARGS[@]}"
            verify
        fi
        ;;
    workflow-step-dead)
        # The molecule is over. The chain, not this bead, is the disposal unit:
        # closing one step readies the next, so a per-bead close here would be
        # the partial teardown that offers a successor of a finished molecule
        # to a pool. run-cancel.sh --ended closes every member the run left open
        # in one gascity call, and refuses (exit 2) a root that reads live on
        # its own read or a chain holding a work bead. A refusal is a skip that
        # leaves the bead owned to be re-examined next cycle; any other non-zero
        # exit is a failed dead-chain.
        ACTION="dispose-dead-chain"
        DETAIL="root_closed"
        if [ "$APPLY" = "1" ]; then
            if [ -x "$RUN_CANCEL" ]; then
                END_ERR="$("$RUN_CANCEL" --root "$ROOT_ID" --ended --reason "orphan recovery: $BEAD is a step of run $ROOT_ID, which has ended" 2>&1 >/dev/null)"
                END_RC=$?
                case "$END_RC" in
                    0) note_landed dead-chain ;;
                    2)
                        ACTION="skip"
                        DETAIL="root_closed;not-ended=refused"
                        ;;
                    *) note_failed dead-chain ;;
                esac
                [ "$END_RC" -eq 0 ] || [ -z "$END_ERR" ] \
                    || echo "orphan-dispose: run-cancel.sh: $(printf '%s' "$END_ERR" | tr '\n' ' ')" >&2
            else
                note_failed "run-cancel-missing"
            fi
        fi
        ;;
    workflow-step-unresolved)
        # Root named but unreadable. Releasing would resume a molecule that may
        # already be over; the step stays owned and returns next cycle, which
        # is the recoverable direction.
        ACTION="skip"
        DETAIL="root_unreadable"
        ;;
    source|review)
        # A review bead shares this arm: it is the source of its own mol-review
        # molecule, carries no merge_result of its own and is routed to a review
        # pool rather than a human gate, so neither skip below fires and it is
        # always reopened to that pool. It reaches here as class=review only so
        # the witness salvage scope gate can skip its worktree salvage and
        # merge-verify; the disposal it needs is exactly the source contract.
        # A source work bead whose work already reached a downstream court is not
        # lost, so delete-source + reopen-source must not return it to the pool
        # (every cycle would re-detect and re-recover it, stamping a recovery the
        # crash-loop signal reads as a RATE, escalating a moot visit). Two states
        # name a downstream court, the same set mol-witness-patrol's
        # downstream-court-skip filter drops upstream: an in-flight PR (merge_result
        # pre_open_gate/pull_request) the refinery owns landing, or a human gate
        # (gc.routed_to=human) a person owns clearing. This is the correctness
        # boundary at the disposal itself, the last step before the irreversible
        # reopen — a source bead that moves onto a human gate after that filter, or
        # reaches this script by recovery or manual replay, is still skipped here.
        # pr.machine is not read: a progressing stamp is written only with an anchor
        # merge_result (which the first arm catches), and unanchoring leaves it
        # behind, so on a repooled bead it is stale. The merge_result arm mirrors
        # the in-flight guard in liveness-sweep.sh and gate-ensure.sh.
        if [ "$MERGE_RESULT" = "pre_open_gate" ] || [ "$MERGE_RESULT" = "pull_request" ]; then
            ACTION="skip"
            DETAIL="inflight_pr(merge_result=${MERGE_RESULT:-none})"
        elif [ "$ROUTED" = "human" ]; then
            ACTION="skip"
            DETAIL="human_gate(routed_to=human)"
        else
            ACTION="delegate-source-workflow"
            if [ "$APPLY" = "1" ]; then
                # delete-source and reopen-source take no conditional guard, so
                # the claim check is the only one ahead of them.
                # A delete-source cut off by its bound counts as failed whatever
                # it finished: reopen-source does not run, so the bead stays owned
                # and comes back next cycle, where delete-source is idempotent.
                run_bounded gc workflow delete-source "$BEAD" --apply >/dev/null 2>&1
                DS_RC=$?
                if [ "$DS_RC" -eq 0 ]; then
                    note_landed delete-source
                elif timed_out "$DS_RC"; then
                    note_failed delete-source-timeout
                else
                    note_failed delete-source
                fi
                if [ "$DS_RC" -eq 0 ]; then
                    run_bounded gc workflow reopen-source "$BEAD" >/dev/null 2>&1
                    RS_RC=$?
                    # A reopen-source cut off by its bound is judged by the bead.
                    # One that reads open and unassigned is released, and its pins
                    # and route are finished below exactly as after a clean exit,
                    # with verify proving the result. One still in progress or
                    # assigned was not released, so it is left as the call left
                    # it, pins included, and stays owned for the next cycle.
                    REOPENED=0
                    if [ "$RS_RC" -eq 0 ]; then
                        REOPENED=1
                    elif timed_out "$RS_RC" && released_on_reread; then
                        REOPENED=1
                        DETAIL="reopen-source-past-bound"
                    fi
                    if [ "$REOPENED" = "1" ]; then
                        note_landed reopen-source
                        # reopen-source returns the bead to the pool but leaves the
                        # session pins its dead claim stamped, so without this the
                        # bead keeps naming that dead session as its owner and
                        # orphan recovery re-detects it every cycle. verify catches a
                        # pin that reports cleared and rolled back.
                        pin_args
                        plain_update pins "${PIN_ARGS[@]}"
                        # reopen-source also preserves the route it finds, and the
                        # dead session's own claim already emptied it, so the
                        # reopened bead is unrouted and unofferable until the route
                        # is put back from the durable execution stamp.
                        restore_route
                        verify
                    elif timed_out "$RS_RC"; then
                        note_failed reopen-source-timeout
                    else
                        note_failed reopen-source
                    fi
                fi
            fi
        fi
        ;;
esac

if [ -n "$LOST" ]; then
    ACTION="skip"
    DETAIL="claim_changed(write=$LOST)"
fi

if [ "$APPLY" != "1" ]; then
    RESULT="preview"
elif [ -n "$LOST" ]; then
    RESULT="skipped"
elif [ -n "$FAILED" ]; then
    RESULT=$([ -n "$LANDED" ] && echo partial || echo failed)
elif [ "$ACTION" = "skip" ]; then
    RESULT="skipped"
else
    RESULT="disposed"
fi

if [ "$WANT_JSON" = "1" ]; then
    jq -cn \
        --arg bead "$BEAD" --arg class "$CLASS" --arg action "$ACTION" \
        --arg result "$RESULT" --arg root "$ROOT_ID" --arg step_ref "$STEP_REF" \
        --arg routed "$ROUTED" --arg owner "$REPORT_OWNER" \
        --arg root_status "$ROOT_STATUS" \
        --arg landed "$LANDED" --arg failed "$FAILED" --arg detail "$DETAIL" \
        '{bead: $bead, class: $class, action: $action, result: $result,
          root: $root, root_status: ($root_status | select(. != "") // null),
          step_ref: $step_ref, routed: $routed, owner: $owner,
          landed: ($landed | select(. != "") // null),
          failed: ($failed | select(. != "") // null),
          detail: ($detail | select(. != "") // null)}'
else
    printf 'result=%s bead=%s class=%s action=%s' "$RESULT" "$BEAD" "$CLASS" "$ACTION"
    [ -n "$ROOT_ID" ] && printf ' root=%s' "$ROOT_ID"
    [ -n "$ROOT_STATUS" ] && printf ' root_status=%s' "$ROOT_STATUS"
    [ -n "$STEP_REF" ] && printf ' step_ref=%s' "$STEP_REF"
    [ -n "$LANDED" ] && printf ' landed=%s' "$LANDED"
    [ -n "$FAILED" ] && printf ' failed=%s' "$FAILED"
    [ -n "$DETAIL" ] && printf ' detail=%s' "$DETAIL"
    printf '\n'
fi

case "$RESULT" in
    partial) exit 3 ;;
    failed)  exit 1 ;;
    *)       exit 0 ;;
esac
