#!/usr/bin/env bash
# orphan-dispose.sh — dispose of ONE bead that orphan recovery classified as
# orphaned, by the kind of thing the bead is.
#
# Six kinds reach this script and only two of them are returned to the pool:
#
#   visit          release the assignee and NOTHING else. A visit's metadata
#                  (route, continuation group, task_kind) is its identity.
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
#                  pool as fresh work. Delegate to dead-molecule-dispose.sh,
#                  which de-routes the whole chain before it closes anything.
#   workflow-step-unresolved
#                  the step names a root that will not read. An unreadable root
#                  is not a live one, so nothing is written: the step stays
#                  owned and returns next cycle.
#   source         delegate to `gc workflow delete-source --apply` plus
#                  `gc workflow reopen-source`, which is the contract those
#                  commands were built for.
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
# WRITE ORDER is load-bearing. bd's claim guard refuses an assignee change on
# an in_progress bead with a live holder and rejects the WHOLE update, so a
# release batched into one call rolls back every field while reporting success.
# Each field gets its own call, in the order that keeps the intermediate state
# invisible to a pool: metadata (no claim needed), then status, then assignee
# last. Every write is verified by re-reading the bead.
#
# Usage:
#   orphan-dispose.sh <bead-id> [--owner <owner>] [--apply] [--json]
# Without --apply this previews: it classifies and prints, and writes nothing.
#   --owner <owner>  the dead owner orphan recovery resolved, for the report.
#                    It is not the assignee guard: on a step the owner is
#                    usually gc.session_id and the assignee a live pool slot.
#   --json           emit the result as one JSON object instead of key=value.
# Exit: 0 disposed or previewed · 1 unreadable bead or failed write ·
#       2 usage · 3 PARTIAL write (some fields landed, some did not).
# NOT set -e: every failure is handled explicitly and reported.
set -uo pipefail

usage() {
    sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'
}

BEAD=""
OWNER=""
OWNER_SET=0
APPLY=0
WANT_JSON=0

while [ $# -gt 0 ]; do
    case "$1" in
        --apply) APPLY=1 ;;
        --json)  WANT_JSON=1 ;;
        --owner)
            if [ $# -lt 2 ]; then echo "orphan-dispose: --owner needs a value" >&2; exit 2; fi
            shift; OWNER="$1"; OWNER_SET=1
            ;;
        --owner=*) OWNER="${1#--owner=}"; OWNER_SET=1 ;;
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
command -v jq >/dev/null 2>&1 || { echo "orphan-dispose: jq is required" >&2; exit 1; }

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

read_bead() { gc bd show "$1" --json 2>/dev/null | scrub; }

# Resolved from $0 so a copy of this script runs against the copy beside it.
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
DEAD_DISPOSE="${GC_DEAD_MOLECULE_TOOL:-$HERE/dead-molecule-dispose.sh}"

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

# Classification order matters. A visit is the source bead of its own mol-visit
# molecule, so it must be recognised before the source arm would claim it. Root
# before step: gascity's own IsWorkflowRoot is gc.kind=workflow OR
# gc.formula_contract=graph.v2, and a step carries neither.
if [ "$TASK_KIND" = "visit" ]; then
    CLASS="visit"
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

# The assignee guard is the assignee read a moment ago, never --owner. Orphan
# recovery resolves an owner by precedence over gc.session_id, assignee and
# gc.session_name, so on the shape this script most needs to release — a step
# whose dead owner is its gc.session_id beside a live pool-slot assignee — the
# two are different strings. Guarding on the owner would mismatch and refuse
# every such release. --owner records who was proved dead and is reported; the
# guard's job is the narrower one of catching a re-claim since the read.
GUARD="$ASSIGNEE"
REPORT_OWNER="$ASSIGNEE"
[ "$OWNER_SET" = "1" ] && REPORT_OWNER="$OWNER"

FAILED=""
LANDED=""

note_failed() { FAILED="${FAILED:+$FAILED,}$1"; }
note_landed() { LANDED="${LANDED:+$LANDED,}$1"; }

# clear_pins removes the routing pins that name a session. Metadata writes do
# not go through the claim guard, so this half always lands.
clear_pins() {
    if gc bd update "$BEAD" \
        --unset-metadata gc.session_id \
        --unset-metadata gc.session_affinity \
        --unset-metadata gc.continuation_group >/dev/null 2>&1; then
        note_landed pins
    else
        note_failed pins
    fi
}

# open_bead moves the bead to open while it is still assigned. That
# intermediate — open, assigned, routed — is invisible to a pool's offer
# predicate, and it is what lets the assignee clear that follows run against an
# open bead instead of a live in_progress claim.
open_bead() {
    [ "$STATUS" = "open" ] && return 0
    if gc bd update "$BEAD" --status=open >/dev/null 2>&1; then
        note_landed status
    else
        note_failed status
    fi
}

# release_assignee clears the assignee last. bd refuses this on an in_progress
# bead held by a live actor, and `gc bd update --force` cannot carry the
# override (the wrapper's bead-id pre-check allowlists no --force), so the
# fallback goes through bare bd. The forced retry is legitimate only because
# orphan recovery already established this owner is gone.
release_assignee() {
    [ -z "$ASSIGNEE" ] && return 0
    if gc bd update "$BEAD" --assignee "" --if-assignee "$GUARD" >/dev/null 2>&1; then
        note_landed assignee
        return 0
    fi
    # raw-bd: gc bd's bead-id pre-check allowlists no --force, so it exits 1
    # before reaching bd and the override cannot be carried through the wrapper.
    if bd update "$BEAD" --assignee "" --if-assignee "$GUARD" --force >/dev/null 2>&1; then
        note_landed assignee
        return 0
    fi
    note_failed assignee
}

# verify re-reads the bead and confirms the release actually landed. A write
# that reports success and rolls back is the failure this exists to catch.
verify() {
    local after
    after="$(read_bead "$BEAD")"
    printf '%s' "$after" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 || {
        note_failed reread
        return
    }
    local st asg sid
    st="$(printf  '%s' "$after" | jq -r '.[0].status // ""')"
    asg="$(printf '%s' "$after" | jq -r '.[0].assignee // ""')"
    sid="$(printf '%s' "$after" | jq -r '.[0].metadata["gc.session_id"] // ""')"
    [ "$st"  = "open" ] || note_failed "status(still=$st)"
    [ -z "$asg" ]       || note_failed "assignee(still=$asg)"
    [ "$CLASS" = "workflow-step" ] && [ -n "$sid" ] && note_failed "gc.session_id(still=$sid)"
    return 0
}

ACTION=""
DETAIL=""

case "$CLASS" in
    visit)
        # Release the assignee and nothing else: no metadata is touched, so the
        # route, continuation group and task_kind that ARE the visit survive.
        ACTION="release-assignee"
        if [ "$APPLY" = "1" ]; then
            open_bead
            release_assignee
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
            clear_pins
            open_bead
            release_assignee
            verify
        fi
        ;;
    workflow-step-dead)
        # The molecule is over. The chain, not this bead, is the disposal unit:
        # closing one step readies the next, so a per-bead close here would be
        # the partial teardown that offers a successor of a finished molecule
        # to a pool. dead-molecule-dispose.sh de-routes the whole chain before
        # it closes anything, and refuses a chain holding a work bead.
        #
        # The disposer reserves exit 3 for a chain left half torn down — some
        # members de-routed or closed, some not. That is the partial-write state
        # this script's own exit 3 names, and the witness patrol escalates it
        # (witness-partial-release) rather than retrying, so it must survive the
        # wrapper: capture the disposer's rc and report instead of discarding
        # them. An inner 3 becomes this script's partial and carries the member
        # detail the disposer named; any other nonzero is a plain failed=dead-chain.
        ACTION="dispose-dead-chain"
        DETAIL="root_closed"
        if [ "$APPLY" = "1" ]; then
            if [ -x "$DEAD_DISPOSE" ]; then
                DEAD_OUT="$("$DEAD_DISPOSE" "$BEAD" --apply --json 2>/dev/null)"
                DEAD_RC=$?
                DEAD_DETAIL="$(printf '%s' "$DEAD_OUT" | jq -r '(.detail // .members // "") | select(. != "")' 2>/dev/null)"
                case "$DEAD_RC" in
                    0) note_landed dead-chain ;;
                    3)
                        note_landed dead-chain
                        note_failed dead-chain-incomplete
                        [ -n "$DEAD_DETAIL" ] && DETAIL="root_closed;$DEAD_DETAIL"
                        ;;
                    *)
                        note_failed dead-chain
                        [ -n "$DEAD_DETAIL" ] && DETAIL="root_closed;$DEAD_DETAIL"
                        ;;
                esac
            else
                note_failed "dead-molecule-dispose-missing"
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
    source)
        ACTION="delegate-source-workflow"
        if [ "$APPLY" = "1" ]; then
            if gc workflow delete-source "$BEAD" --apply >/dev/null 2>&1; then
                note_landed delete-source
            else
                note_failed delete-source
            fi
            case ",$FAILED," in
                *,delete-source,*) ;;
                *)
                    if gc workflow reopen-source "$BEAD" >/dev/null 2>&1; then
                        note_landed reopen-source
                    else
                        note_failed reopen-source
                    fi
                    ;;
            esac
        fi
        ;;
esac

if [ "$APPLY" != "1" ]; then
    RESULT="preview"
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
