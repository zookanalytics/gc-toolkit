#!/usr/bin/env bash
# first-reaction-dispose.sh — the disposition a first reaction ends in.
# A reaction reads a subject bead S once and takes one of four exits, and this
# script performs it as the write-back to S. Three exits advance S and leave it
# open; the fourth closes it through the one evidence-gated writer.
#
#   actionable  the bead is work -> release it TO a pool, which is the whole
#               of "schedule an action for a bead": a routed, unassigned,
#               open bead is what a pool's find-work offers.
#   blocked     the bead is waiting -> the wait becomes a `blocks` edge on a
#               bead in the SAME store (component-model I1). Optionally arm a
#               deferred dispatch, so the wait converts to work when it lifts.
#   ruling      only the operator can answer -> the visit its caller filed.
#   superseded  the bead is a duplicate or fixed upstream -> close it with a
#               successor pointer through bead-rehome.sh, which gates its own
#               evidence. The narrow close a reaction may make on its own.
#
# The reaction is its own leased bead R (mol-polecat-work model). Pass
# --reaction-bead R: this script performs the write-back to S, stamps
# gc.reacted_by=R on S as the completion marker (last, after any edge), and
# closes R. A worker that died in the act-on-S -> close-R window is re-offered
# the same R; on re-run it sees gc.reacted_by=R (or, for superseded, S already
# closed) and closes R without touching S again. Called without --reaction-bead
# — the frozen invocation of a mol-first-reaction molecule poured before the
# cutover — it performs the same write-back on the claimed subject and stamps
# no marker, closes no R.
#
# The subject-metadata done-marker (gc.first_reaction*, gc.proactive_reaction)
# is retired: exactly-once for the reaction is the substrate's, keyed on R's
# identity, not a stamp on S written around the act.
# Callers: agents/proactive/prompt.template.md, in-flight mol-first-reaction
# molecules (advance-and-drain), operators by hand.
# Exit: 0 disposed · 2 usage · 4 runtime failure.
set -u

PROG="first-reaction-dispose"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$HERE/gc-helm.sh}"
DEFERRED="${GC_DEFERRED_DISPATCH_TOOL:-$HERE/deferred-dispatch.sh}"
PROACTIVE="${GC_PROACTIVE_TOOL:-$HERE/../../tools/gc-proactive.sh}"
REHOME="${GC_BEAD_REHOME_TOOL:-$HERE/bead-rehome.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

die()  { printf '%s: %s\n' "$PROG" "$*" >&2; exit 4; }
usage_die() { printf '%s: %s\n' "$PROG" "$*" >&2; usage; exit 2; }
note() { printf '%s: %s\n' "$PROG" "$*" >&2; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

usage() {
    cat >&2 <<'EOF'
Usage:
  first-reaction-dispose.sh <bead> --disposition actionable --reason "<why>" --takeaway "<headline>"
                            [--route <rig>/<agent>] [--reaction-bead <R>]
  first-reaction-dispose.sh <bead> --disposition blocked --reason "<why>" --takeaway "<headline>"
                            (--waiting-on <bead-id> | --blocker "<title>" [--blocker-key <key>])...
                            [--then-route <rig>/<agent>] [--reaction-bead <R>]
  first-reaction-dispose.sh <bead> --disposition ruling --reason "<why>" --takeaway "<headline>"
                            --visit <visit-bead-id> [--reaction-bead <R>]
  first-reaction-dispose.sh <bead> --disposition superseded --reason "<why>" --takeaway "<headline>"
                            --successor <bead-id> [--kind fixed-upstream|duplicate]
                            [--successor-store rig:<name>] [--reaction-bead <R>]
  common: [--by <who>] [--db <path>] [--dry-run]

  --reason is required on every exit: a disposition nobody can second-guess is
  a silent classification. It lands on the bead beside the choice.
  --takeaway is the board headline (≤140 chars, enforced by gc-helm.sh).
  --route defaults to ${GC_RIG}/gc-toolkit.polecat, and fails closed when the
  target cannot be rig-qualified.
  --blocker files (once) the bead the subject is waiting on, when the wait is
  not a bead yet; --blocker-key dedups repeats of one recurring cause onto
  that single bead instead of one bead per instance.
  --then-route arms the deferred dispatch that slings the subject when the
  blocker closes (assets/scripts/deferred-dispatch.sh).
  --successor names the bead that carries the work S duplicates or that fixed
  it upstream; --kind is fixed-upstream (default) or duplicate — the two a
  reaction may judge. A re-home or fold is the operator's call: take ruling.
  --reaction-bead is R, the reaction's own leased bead. Given it, this script
  closes R after the write-back lands and stamps gc.reacted_by=R on S.
EOF
}

BEAD=""; DISPOSITION=""; REASON=""; TAKEAWAY=""; BY="proactive"
ROUTE=""; VISIT=""; THEN_ROUTE=""; BLOCKER_TITLE=""; BLOCKER_KEY=""
SUCCESSOR=""; SUCCESSOR_STORE=""; KIND=""; REACTION_BEAD=""
DB=""; DRY=""
WAITING=""          # space-separated bead ids

while [ $# -gt 0 ]; do
    case "$1" in
        --disposition) shift; [ $# -gt 0 ] || usage_die "--disposition needs a value"; DISPOSITION="$1"; shift ;;
        --disposition=*) DISPOSITION="${1#--disposition=}"; shift ;;
        --reason)   shift; [ $# -gt 0 ] || usage_die "--reason needs a value"; REASON="$1"; shift ;;
        --reason=*) REASON="${1#--reason=}"; shift ;;
        --takeaway) shift; [ $# -gt 0 ] || usage_die "--takeaway needs a value"; TAKEAWAY="$1"; shift ;;
        --takeaway=*) TAKEAWAY="${1#--takeaway=}"; shift ;;
        --by)       shift; [ $# -gt 0 ] || usage_die "--by needs a value"; BY="$1"; shift ;;
        --by=*)     BY="${1#--by=}"; shift ;;
        --route)    shift; [ $# -gt 0 ] || usage_die "--route needs a <rig>/<agent> target"; ROUTE="$1"; shift ;;
        --route=*)  ROUTE="${1#--route=}"; shift ;;
        --then-route)   shift; [ $# -gt 0 ] || usage_die "--then-route needs a <rig>/<agent> target"; THEN_ROUTE="$1"; shift ;;
        --then-route=*) THEN_ROUTE="${1#--then-route=}"; shift ;;
        --waiting-on)   shift; [ $# -gt 0 ] || usage_die "--waiting-on needs a bead id"; WAITING="$WAITING $1"; shift ;;
        --waiting-on=*) WAITING="$WAITING ${1#--waiting-on=}"; shift ;;
        --blocker)   shift; [ $# -gt 0 ] || usage_die "--blocker needs a title"; BLOCKER_TITLE="$1"; shift ;;
        --blocker=*) BLOCKER_TITLE="${1#--blocker=}"; shift ;;
        --blocker-key)   shift; [ $# -gt 0 ] || usage_die "--blocker-key needs a value"; BLOCKER_KEY="$1"; shift ;;
        --blocker-key=*) BLOCKER_KEY="${1#--blocker-key=}"; shift ;;
        --visit)    shift; [ $# -gt 0 ] || usage_die "--visit needs a bead id"; VISIT="$1"; shift ;;
        --visit=*)  VISIT="${1#--visit=}"; shift ;;
        --successor)   shift; [ $# -gt 0 ] || usage_die "--successor needs a bead id"; SUCCESSOR="$1"; shift ;;
        --successor=*) SUCCESSOR="${1#--successor=}"; shift ;;
        --successor-store)   shift; [ $# -gt 0 ] || usage_die "--successor-store needs a rig:<name>"; SUCCESSOR_STORE="$1"; shift ;;
        --successor-store=*) SUCCESSOR_STORE="${1#--successor-store=}"; shift ;;
        --kind)     shift; [ $# -gt 0 ] || usage_die "--kind needs a value"; KIND="$1"; shift ;;
        --kind=*)   KIND="${1#--kind=}"; shift ;;
        --reaction-bead)   shift; [ $# -gt 0 ] || usage_die "--reaction-bead needs a bead id"; REACTION_BEAD="$1"; shift ;;
        --reaction-bead=*) REACTION_BEAD="${1#--reaction-bead=}"; shift ;;
        --db)       shift; [ $# -gt 0 ] || usage_die "--db needs a path"; DB="$1"; shift ;;
        --db=*)     DB="${1#--db=}"; shift ;;
        --dry-run|-n) DRY=1; shift ;;
        -h|--help)  usage; exit 0 ;;
        -*) usage_die "unknown flag '$1'" ;;
        *)  [ -z "$BEAD" ] || usage_die "takes one <bead-id> (got '$BEAD' and '$1')"; BEAD="$1"; shift ;;
    esac
done

# ── Validation: refuse before writing anything ───────────────────────
[ -n "$BEAD" ] || usage_die "needs <bead-id>"
case "$DISPOSITION" in
    actionable|blocked|ruling|superseded) : ;;
    "") usage_die "needs --disposition actionable|blocked|ruling|superseded" ;;
    *)  usage_die "unknown disposition '$DISPOSITION' (actionable|blocked|ruling|superseded)" ;;
esac
[ -n "$REASON" ]   || usage_die "--reason is required: the record of WHY this disposition was chosen is what makes a wrong call visible"
[ -n "$TAKEAWAY" ] || usage_die "--takeaway is required: it is the board headline the operator reads"
[ "$REACTION_BEAD" != "$BEAD" ] || usage_die "--reaction-bead $REACTION_BEAD is the subject itself; R tracks S, it is not S"

# One store. `bd dep add` naming a bead in another rig's store answers "✓
# Added dependency" and holds nothing (component-model I1), so a cross-store
# wait is refused here rather than written and believed.
same_store() { [ "${1%%-*}" = "${2%%-*}" ]; }

case "$DISPOSITION" in
    actionable)
        [ -z "$WAITING$BLOCKER_TITLE$VISIT$THEN_ROUTE$SUCCESSOR" ] \
            || usage_die "actionable takes --route only (--waiting-on/--blocker/--then-route/--visit/--successor belong to the other exits)"
        [ -n "$ROUTE" ] || ROUTE="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
        case "$ROUTE" in
            */*) : ;;
            *) usage_die "cannot rig-qualify the route target '$ROUTE': set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody." ;;
        esac
        ;;
    blocked)
        [ -z "$ROUTE$VISIT$SUCCESSOR" ] || usage_die "blocked takes --waiting-on/--blocker/--then-route (--route/--visit/--successor belong to the other exits)"
        [ -n "$WAITING" ] || [ -n "$BLOCKER_TITLE" ] \
            || usage_die "blocked needs --waiting-on <bead-id> or --blocker \"<title>\": the wait IS the edge, and prose about it holds nothing"
        if [ -n "$BLOCKER_TITLE" ]; then
            # bd refuses a title over 500 bytes, and the refusal reads as "no
            # id returned" — a cap checked here names the actual cause.
            _tbytes=$(printf '%s' "$BLOCKER_TITLE" | wc -c | tr -d ' ')
            [ "$_tbytes" -le 500 ] \
                || usage_die "--blocker title is $_tbytes bytes; bd's cap is 500. Name the wait in one line and put the detail in --reason."
        fi
        for w in $WAITING; do
            [ "$w" != "$BEAD" ] || usage_die "--waiting-on $w is the bead itself"
            same_store "$w" "$BEAD" \
                || usage_die "--waiting-on $w is in another store than $BEAD; a cross-store edge reports success and holds nothing. File a demand bead in ${BEAD%%-*}'s store naming $w in its body, and wait on that."
        done
        if [ -n "$THEN_ROUTE" ]; then
            case "$THEN_ROUTE" in */*) : ;; *) usage_die "--then-route '$THEN_ROUTE' is not rig-qualified (<rig>/<agent>)" ;; esac
        fi
        ;;
    ruling)
        [ -z "$ROUTE$WAITING$BLOCKER_TITLE$THEN_ROUTE$SUCCESSOR" ] || usage_die "ruling takes --visit only"
        [ -n "$VISIT" ] || usage_die "ruling needs --visit <visit-bead-id>: file the visit first (the gate-visit block), then record it here"
        [ "$VISIT" != "$BEAD" ] || usage_die "--visit $VISIT is the bead itself"
        same_store "$VISIT" "$BEAD" \
            || usage_die "--visit $VISIT is in another store than $BEAD; a blocks edge onto it reports success and holds nothing (component-model I1). File the visit in ${BEAD%%-*}'s store, then record it here."
        ;;
    superseded)
        [ -z "$ROUTE$WAITING$BLOCKER_TITLE$THEN_ROUTE$VISIT" ] || usage_die "superseded takes --successor/--kind only"
        [ -n "$SUCCESSOR" ] || usage_die "superseded needs --successor <bead-id>: the bead that carries the work, or that fixed it upstream"
        [ "$SUCCESSOR" != "$BEAD" ] || usage_die "--successor $SUCCESSOR is the bead itself"
        [ -n "$KIND" ] || KIND="fixed-upstream"
        case "$KIND" in
            fixed-upstream|duplicate) : ;;
            re-homed|folded|not-needed) usage_die "--kind $KIND is a judgment a reaction does not make on its own — re-home, fold, and not-needed are the operator's call. Take --disposition ruling and let the visit dispose it." ;;
            *) usage_die "unknown --kind '$KIND' for superseded (fixed-upstream|duplicate)" ;;
        esac
        [ -x "$REHOME" ] || die "bead-rehome.sh not found at $REHOME; superseded closes S through it, the one evidence-gated close-with-successor writer"
        ;;
esac

# ── Pin the store, do not let the cwd choose it ──────────────────────
# This runs from a pool worktree, where .beads is gitignored, so an unpinned
# up-walk overshoots to whatever ledger it finds first. Two of the writes
# below cannot survive that: a blocker filed into another store makes the
# hold a cross-store edge, which reports success and holds nothing. Resolve
# the subject's own rig by its id prefix, the way the board's write verbs do.
if [ -z "$DB" ]; then
    _rigs="$(gc rig list --json 2>/dev/null || printf '')"
    if [ -n "$_rigs" ]; then
        _path="$(printf '%s' "$_rigs" | scrub \
            | jq -r --arg p "${BEAD%%-*}" '((.rigs // []) | map(select((.prefix // "") == $p)) | .[0].path // "")' 2>/dev/null || printf '')"
        [ -n "$_path" ] && [ -d "$_path/.beads" ] && DB="$_path/.beads"
    fi
fi
BD_DB_ARGS=""
[ -n "$DB" ] && BD_DB_ARGS="--db $DB"

# The pin rides at the END of every call: `gc bd <verb> … --db <path>`, the
# form every other caller in the pack uses.
# shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
gc_bd() { gc bd "$@" $BD_DB_ARGS; }

# ── Read the subject once; the guards below all ask its metadata ──────
# The store is pinned, so this reads the subject's own rig. Both refusals
# below — already-reacted and operator-commissioned — key off it, and one read
# keeps them from disagreeing. Positive finding only: an unreadable bead is not
# evidence of anything, so an empty read falls through to the act.
SUBJECT_JSON=$(gc_bd show "$BEAD" --json 2>/dev/null | scrub || printf '')
subject_field() {
    printf '%s' "$SUBJECT_JSON" \
        | jq -r --arg k "$1" 'if type == "array" then (.[0][$k] // "") else "" end' 2>/dev/null || printf ''
}
subject_meta() {
    printf '%s' "$SUBJECT_JSON" \
        | jq -r --arg k "$1" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

# ── Close R once the write-back has landed ────────────────────────────
# R is the reaction's own work bead. Closing it is what records the reaction
# done — exactly-once is the substrate's, keyed on R, not on a stamp on S. A
# close that is refused leaves R open under this worker's lease; the re-offer
# then re-runs and reaches this close again, so a transient refusal self-heals.
close_reaction() {
    [ -n "$REACTION_BEAD" ] || return 0
    if gc_bd update "$REACTION_BEAD" --set-metadata "gc.outcome=reacted" --status=closed >/dev/null 2>&1; then
        note "closed reaction bead $REACTION_BEAD"
    else
        note "WARNING: could not close reaction bead $REACTION_BEAD; the write-back landed, so a re-offer of $REACTION_BEAD reads gc.reacted_by on $BEAD and closes it. Close it by hand: gc bd update $REACTION_BEAD --status=closed"
    fi
}

# ── A reaction happens once — self-heal the act-on-S -> close-R window ─
# The write-back stamps gc.reacted_by=R on S as its last act; for superseded
# the signal is S itself being closed with a successor. A worker re-offered R
# after a crash in that window reads the marker and closes R without touching S
# again — S is never re-dispatched, never yanked from a worker that has since
# claimed a routed S. Without R (a frozen mol-first-reaction call) there is no
# marker and no self-heal: exactly-once there is the graph.v2 step chain's.
if [ -n "$REACTION_BEAD" ]; then
    PRIOR_REACTED_BY=$(subject_meta "gc.reacted_by")
    S_STATUS=$(subject_field "status")
    S_SUPERSEDED=$(subject_meta "gc.superseded_by")
    if [ "$PRIOR_REACTED_BY" = "$REACTION_BEAD" ] \
       || { [ "$DISPOSITION" = "superseded" ] && [ "$S_STATUS" = "closed" ] && [ -n "$S_SUPERSEDED" ]; }; then
        note "$BEAD already carries this reaction's write-back (gc.reacted_by=${PRIOR_REACTED_BY:-<unset>}${S_SUPERSEDED:+, superseded_by=$S_SUPERSEDED}); closing $REACTION_BEAD without re-disposing."
        close_reaction
        exit 0
    fi
fi

# ── Route only where something can claim ─────────────────────────────
# A route to a pool this city does not run is worse than a visit: the bead is
# open, unassigned and offered to nobody, and nothing says so. gc-proactive.sh
# `deliverable` already answers exactly this question against the agent
# roster, for any rig-qualified target, and it answers no only on a positive
# finding — so a probe that cannot run leaves the disposition alone.
if [ "$DISPOSITION" = "actionable" ] && [ -x "$PROACTIVE" ]; then
    DELIVERABLE_WHY="$("$PROACTIVE" deliverable "$ROUTE" 2>/dev/null)" || {
        usage_die "$ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Routing there would leave $BEAD open, unassigned and offered to nobody. File the visit instead (--disposition ruling)."
    }
fi
# --then-route names the pool the deferred dispatch slings the bead to once its
# blocker lifts, so it is held to the SAME roster test as --route. Its own check
# at parse time only tests for a "/", which a copied `<rig>/<agent>` placeholder
# passes; a target the roster does not know would arm a dispatch every reconcile
# pass replays into a failure. The probe answers no only on a positive finding,
# so an unrunnable probe leaves the arm alone.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ] && [ -x "$PROACTIVE" ]; then
    DELIVERABLE_WHY="$("$PROACTIVE" deliverable "$THEN_ROUTE" 2>/dev/null)" || {
        usage_die "--then-route $THEN_ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Arming it would record a dispatch the reconcile pass replays into a failure every cycle. Pass a pool that runs (e.g. <rig>/<rig>.polecat), or omit --then-route if no pool takes this bead."
    }
fi

# ── The one subject that is always a conversation ────────────────────
# gc.origin=operator means a human typed this topic into gc-visit-open and is
# waiting to talk about it (docs/gascity-human-engagement.md). Routing, holding,
# or superseding it answers a question nobody asked and leaves the operator with
# a topic that looks filed and is silently forgotten — the outcome that intake
# path exists to prevent. Positive finding only: a read that fails or comes
# back empty proceeds, because an unreadable bead is not evidence of anything.
if [ "$DISPOSITION" != "ruling" ]; then
    ORIGIN=$(subject_meta "gc.origin")
    if [ "$ORIGIN" = "operator" ]; then
        usage_die "$BEAD carries gc.origin=operator: a human commissioned this topic and is waiting on the conversation, so the visit IS the answer. Take --disposition ruling. If the work is also real, the operator schedules it from the visit."
    fi
fi

if [ -n "$DRY" ]; then
    printf 'disposition=%s bead=%s reason=%s\n' "$DISPOSITION" "$BEAD" "$REASON"
    case "$DISPOSITION" in
        actionable) printf 'would release %s to %s\n' "$BEAD" "$ROUTE" ;;
        blocked)    printf 'would wait %s on:%s%s\n' "$BEAD" "$WAITING" "${BLOCKER_TITLE:+ (new: $BLOCKER_TITLE)}" ;;
        ruling)     printf 'would record visit %s on %s\n' "$VISIT" "$BEAD" ;;
        superseded) printf 'would close %s as %s of %s\n' "$BEAD" "$KIND" "$SUCCESSOR" ;;
    esac
    [ -n "$REACTION_BEAD" ] && printf 'would close reaction bead %s\n' "$REACTION_BEAD"
    exit 0
fi

# ── superseded: close S with a successor, through the one gated writer ─
# bead-rehome.sh re-establishes the evidence itself (successor closed/shipped
# and same-store, S did no work, S is not a step/review/workflow bead). --check
# first, so a refusal falls back to a ruling instead of a half-close; then the
# close. reacted_by is not stamped — S closing with gc.superseded_by IS the
# completion signal the re-offer recovery above reads.
if [ "$DISPOSITION" = "superseded" ]; then
    CHECK_ERR="$("$REHOME" --check --origin "$BEAD" --successor "$SUCCESSOR" --kind "$KIND" \
                    ${SUCCESSOR_STORE:+--successor-store "$SUCCESSOR_STORE"} 2>&1)" || {
        printf '%s\n' "$CHECK_ERR" >&2
        die "superseded refused by bead-rehome --check on $BEAD -> $SUCCESSOR ($KIND); nothing was written. The evidence a reaction may close on is not present — take --disposition ruling and let the operator dispose it."
    }
    "$REHOME" --origin "$BEAD" --successor "$SUCCESSOR" --kind "$KIND" --note "$REASON" \
        ${SUCCESSOR_STORE:+--successor-store "$SUCCESSOR_STORE"} \
        || die "bead-rehome.sh could not close $BEAD as $KIND of $SUCCESSOR; its message above names what stopped it. Nothing here re-tries the close — clear the cause and re-run, or take ruling."
    close_reaction
    printf '%s: %s disposed as %s (%s of %s)\n' "$PROG" "$BEAD" "$DISPOSITION" "$KIND" "$SUCCESSOR"
    exit 0
fi

# ── The blocked exit's missing bead: file it once, or reuse it ────────
# One bead per recurring CAUSE, not one per instance: --blocker-key is the
# dedup handle, and a second reaction naming the same key waits on the bead
# the first one filed.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$BLOCKER_TITLE" ]; then
    EXISTING=""
    if [ -n "$BLOCKER_KEY" ]; then
        EXISTING=$(gc_bd list --status=open,in_progress --metadata-field "gc.blocker_key=$BLOCKER_KEY" --limit=1 --json 2>/dev/null \
            | scrub | jq -r 'if type == "array" then (.[0].id // "") else "" end' 2>/dev/null || printf '')
    fi
    if [ -n "$EXISTING" ]; then
        note "the wait '$BLOCKER_TITLE' is already filed as $EXISTING (gc.blocker_key=$BLOCKER_KEY); waiting on that one"
        WAITING="$WAITING $EXISTING"
    else
        # The key rides the create: a bead filed without it is a bead the
        # next reaction on the same cause cannot find, and files again.
        set --
        if [ -n "$BLOCKER_KEY" ]; then
            _meta=$(jq -nc --arg k "$BLOCKER_KEY" '{"gc.blocker_key": $k}' 2>/dev/null || printf '')
            [ -n "$_meta" ] && set -- --metadata "$_meta"
        fi
        NEW=$(gc_bd create -t task --title "$BLOCKER_TITLE" "$@" \
            -d "Filed by a first reaction on $BEAD, which is waiting on it.

$REASON" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].id // "") else (.id // "") end' 2>/dev/null || printf '')
        [ -n "$NEW" ] && [ "$NEW" != "null" ] \
            || die "could not file the blocker bead for '$BLOCKER_TITLE' — nothing was written to $BEAD; re-run this command"
        note "filed the wait as $NEW"
        WAITING="$WAITING $NEW"
    fi
fi

# ── The act ──────────────────────────────────────────────────────────
# gc-helm.sh takeaway carries the headline, the release, and the wait edges;
# --route releases the bead to a pool instead of back to the human.
#
# Each disposition also answers the headline's own question — is anything still
# waiting on this bead? An actionable one is not: it is moving, and the pool its
# route names will claim it, so --no-wait says so. A blocked one names its wait
# as an edge. A ruling names the visit as its wait: the subject is waiting on a
# person, and the visit bead is what carries that wait, so --waiting-on stamps
# the blocks edge onto it. The release parks the subject and the edge holds it,
# so it is not offered again until the visit closes, and the wait is a graph
# state doctor/check-wait-is-an-edge reads rather than prose it reports.
set -- takeaway "$BEAD" "$TAKEAWAY" --by "$BY" --release
case "$DISPOSITION" in
    actionable) set -- "$@" --route "$ROUTE" --no-wait ;;
    blocked)    for w in $WAITING; do set -- "$@" --waiting-on "$w"; done ;;
    ruling)     set -- "$@" --waiting-on "$VISIT" ;;
esac
"$HELM" "$@" || die "gc-helm.sh takeaway failed on $BEAD; its message above names what landed and what did not. Clear the cause and re-run this command."

# The edge is the hold. gc-helm.sh warns on a rejected edge and keeps going,
# which is right for a headline but not for the exits that hold on one: a
# blocked disposition waits on its blocker, a ruling waits on its visit, and
# either whose edge never landed leaves the bead unheld with nothing to say so.
# A missing edge fails the whole exit, so the reaction stops rather than
# closing R over a bead that is recorded as waiting and is not held.
HOLD_WAITS=""
case "$DISPOSITION" in
    blocked) HOLD_WAITS="$WAITING" ;;
    ruling)  HOLD_WAITS="$VISIT" ;;
esac
if [ -n "$HOLD_WAITS" ]; then
    HELD=$(gc_bd dep list "$BEAD" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[]?.id // empty) else empty end' 2>/dev/null || printf '')
    MISSING=""
    for w in $HOLD_WAITS; do
        case " $(printf '%s' "$HELD" | tr '\n' ' ') " in
            *" $w "*) : ;;
            *) note "$BEAD is not held by $w — wire it by hand: gc bd dep add $BEAD $w -t blocks"
               MISSING="$MISSING $w" ;;
        esac
    done
    [ -z "$MISSING" ] \
        || die "the $DISPOSITION disposition on $BEAD did not land. Nothing holds it on:${MISSING}, so the bead is not held — it reads as parked on prose alone, the wait this exit recorded carried by no edge. The headline and the release stand — only the hold is missing, so wire the edge above by hand to complete it, then close $REACTION_BEAD."
    if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ]; then
        if [ -x "$DEFERRED" ]; then
            # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
            "$DEFERRED" arm "$BEAD" --target "$THEN_ROUTE" --reason "first reaction: $REASON" $BD_DB_ARGS >/dev/null 2>&1 \
                && note "armed the dispatch to $THEN_ROUTE for when the wait lifts" \
                || note "WARNING: could not arm the deferred dispatch to $THEN_ROUTE; the wait still holds, but nothing will route $BEAD when it lifts"
        else
            note "WARNING: deferred-dispatch.sh not found at $DEFERRED; the wait holds but nothing will route $BEAD when it lifts"
        fi
    fi
fi

# ── The completion marker, last ──────────────────────────────────────
# gc.reacted_by=R is the residual-window self-heal, stamped after the act (and
# after the edge, above) so its presence proves the whole write-back landed. It
# is not a guard anything refuses progress on — the write-backs are idempotent,
# so a re-run without it is safe — it only spares the redundant work and keeps a
# claimed S from being re-dispatched. Without R there is nothing to name, and
# the frozen molecule's exactly-once is its step chain.
if [ -n "$REACTION_BEAD" ]; then
    gc_bd update "$BEAD" --set-metadata "gc.reacted_by=$REACTION_BEAD" >/dev/null 2>&1 \
        || note "WARNING: could not stamp gc.reacted_by=$REACTION_BEAD on $BEAD; the disposition landed, so a re-offer of $REACTION_BEAD re-runs the idempotent write-back and reaches the close again."
fi

close_reaction
printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${ROUTE:-${WAITING:-$VISIT}}"
