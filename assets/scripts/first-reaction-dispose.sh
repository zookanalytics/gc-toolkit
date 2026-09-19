#!/usr/bin/env bash
# first-reaction-dispose.sh — the disposition a first reaction ends in.
# mol-first-reaction's terminal step chooses one of three exits from the card
# it just wrote, and this script performs it. Each exit advances the subject
# and records what was chosen and why; none of them closes it.
#
#   actionable  the bead is work -> release it TO a pool, which is the whole
#               of "schedule an action for a bead": a routed, unassigned,
#               open bead is what a pool's find-work offers.
#   blocked     the bead is waiting -> the wait becomes a `blocks` edge on a
#               bead in the SAME store (component-model I1). Optionally arm a
#               deferred dispatch, so the wait converts to work when it lifts.
#   ruling      only the operator can answer -> the visit its caller filed. A
#               ruling that names a determinable action also passes
#               --recommended-formula, which stamps gc.recommended_formula on
#               the subject so the operator can Accept the recommendation from
#               the visit; a Discuss-only ruling omits it.
#
# The route/edge/visit is the act; gc.first_reaction* is the record of it, and
# is written FIRST so a disposition that dies half-way is still auditable.
# Callers: formulas/mol-first-reaction.toml (advance-and-drain), operators by
# hand. Exit: 0 disposed · 2 usage · 4 runtime failure.
set -u

PROG="first-reaction-dispose"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$HERE/gc-helm.sh}"
DEFERRED="${GC_DEFERRED_DISPATCH_TOOL:-$HERE/deferred-dispatch.sh}"
PROACTIVE="${GC_PROACTIVE_TOOL:-$HERE/../../tools/gc-proactive.sh}"

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
                            [--route <rig>/<agent>]
  first-reaction-dispose.sh <bead> --disposition blocked --reason "<why>" --takeaway "<headline>"
                            (--waiting-on <bead-id> | --blocker "<title>" [--blocker-key <key>])...
                            [--then-route <rig>/<agent>]
  first-reaction-dispose.sh <bead> --disposition ruling --reason "<why>" --takeaway "<headline>"
                            --visit <visit-bead-id> [--recommended-formula <mol>]
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
  --recommended-formula (ruling only) names the execution mol a
  determinable-action ruling recommends; it stamps gc.recommended_formula on
  the subject, which is what offers the operator Accept on the visit. Omit it
  for a Discuss-only ruling.
EOF
}

BEAD=""; DISPOSITION=""; REASON=""; TAKEAWAY=""; BY="proactive"
ROUTE=""; VISIT=""; THEN_ROUTE=""; BLOCKER_TITLE=""; BLOCKER_KEY=""
DB=""; DRY=""; RECOMMENDED_FORMULA=""
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
        --recommended-formula)   shift; [ $# -gt 0 ] || usage_die "--recommended-formula needs a mol name"; RECOMMENDED_FORMULA="$1"; shift ;;
        --recommended-formula=*) RECOMMENDED_FORMULA="${1#--recommended-formula=}"; shift ;;
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
    actionable|blocked|ruling) : ;;
    "") usage_die "needs --disposition actionable|blocked|ruling" ;;
    *)  usage_die "unknown disposition '$DISPOSITION' (actionable|blocked|ruling)" ;;
esac
[ -n "$REASON" ]   || usage_die "--reason is required: the record of WHY this disposition was chosen is what makes a wrong call visible"
[ -n "$TAKEAWAY" ] || usage_die "--takeaway is required: it is the board headline the operator reads"

# One store. `bd dep add` naming a bead in another rig's store answers "✓
# Added dependency" and holds nothing (component-model I1), so a cross-store
# wait is refused here rather than written and believed.
same_store() { [ "${1%%-*}" = "${2%%-*}" ]; }

case "$DISPOSITION" in
    actionable)
        [ -z "$WAITING$BLOCKER_TITLE$VISIT$THEN_ROUTE$RECOMMENDED_FORMULA" ] \
            || usage_die "actionable takes --route only (--waiting-on/--blocker/--then-route/--visit/--recommended-formula belong to the other exits)"
        [ -n "$ROUTE" ] || ROUTE="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
        case "$ROUTE" in
            */*) : ;;
            *) usage_die "cannot rig-qualify the route target '$ROUTE': set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody." ;;
        esac
        ;;
    blocked)
        [ -z "$ROUTE$VISIT$RECOMMENDED_FORMULA" ] || usage_die "blocked takes --waiting-on/--blocker/--then-route (--route/--visit/--recommended-formula belong to the other exits)"
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
        [ -z "$ROUTE$WAITING$BLOCKER_TITLE$THEN_ROUTE" ] || usage_die "ruling takes --visit, and optionally --recommended-formula"
        [ -n "$VISIT" ] || usage_die "ruling needs --visit <visit-bead-id>: file the visit first (the gate-visit block), then record it here"
        [ "$VISIT" != "$BEAD" ] || usage_die "--visit $VISIT is the bead itself"
        same_store "$VISIT" "$BEAD" \
            || usage_die "--visit $VISIT is in another store than $BEAD; a blocks edge onto it reports success and holds nothing (component-model I1). File the visit in ${BEAD%%-*}'s store, then record it here."
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
subject_meta() {
    printf '%s' "$SUBJECT_JSON" \
        | jq -r --arg k "$1" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

# ── A first reaction happens once — once it has LANDED ────────────────
# gc.first_reaction* is written BEFORE the act (below), so its presence proves
# the disposition was ATTEMPTED, not that it landed. The act — gc-helm.sh
# takeaway --release — stamps gc.proactive_reaction=1 in the same write that
# parks the subject (reopen, unassign, route), so that stamp is what proves the
# release landed. Key the guard on it: a landed reaction refuses a second
# dispose, which would re-release a bead a worker has since claimed and yank
# live work back to the pool.
#
# A bare record with no such stamp is a PARTIAL: the act failed after the record
# was written (gc-helm.sh exited non-zero, or a guard below fired). Refusing it
# on the record alone is what strands the documented retry — the die messages
# below say "re-run this command", and the record would refuse the re-run. So a
# partial falls through and re-attempts the act.
PRIOR_REACTION=$(subject_meta "gc.first_reaction")
PRIOR_PROACTIVE=$(subject_meta "gc.proactive_reaction")
if [ "$PRIOR_PROACTIVE" = "1" ]; then
    PRIOR_AT=$(subject_meta "gc.first_reaction_at")
    PRIOR_TARGET=$(subject_meta "gc.first_reaction_target")
    usage_die "$BEAD already carries a first reaction that landed (gc.first_reaction=${PRIOR_REACTION:-<unset>}${PRIOR_AT:+ at $PRIOR_AT}${PRIOR_TARGET:+ -> $PRIOR_TARGET}, released). A second dispose re-releases a bead a worker may already hold; the reaction is done, so drain this re-offered run rather than re-disposing."
elif [ -n "$PRIOR_REACTION" ]; then
    note "$BEAD carries a first-reaction record (gc.first_reaction=$PRIOR_REACTION) but no gc.proactive_reaction=1 — the prior act did not land. Resuming: re-attempting the disposition."
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
# waiting to talk about it (docs/gascity-human-engagement.md). Routing or
# holding it answers a question nobody asked and leaves the operator with a
# topic that looks filed and is silently forgotten — the outcome that intake
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
        ruling)     printf 'would record visit %s on %s%s\n' "$VISIT" "$BEAD" "${RECOMMENDED_FORMULA:+ recommending $RECOMMENDED_FORMULA}" ;;
    esac
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

# ── The record, before the act ───────────────────────────────────────
# What was chosen, why, and what it names. Written first so a run that dies
# part-way leaves the classification visible instead of an unexplained bead. A
# ruling that recommends an execution stamps gc.recommended_formula in the same
# write: it is the field that turns a plain visit into a recommendation visit
# (the operator's Accept reads it), so a half-written recommendation stays
# visible rather than leaving a bare visit that lost its recommendation.
TARGET=""
case "$DISPOSITION" in
    actionable) TARGET="$ROUTE" ;;
    blocked)    TARGET="$(printf '%s' "${WAITING# }" | tr -s ' ' ',')" ;;
    ruling)     TARGET="$VISIT" ;;
esac
set -- --set-metadata "gc.first_reaction=$DISPOSITION" \
       --set-metadata "gc.first_reaction_reason=$REASON" \
       --set-metadata "gc.first_reaction_target=$TARGET" \
       --set-metadata "gc.first_reaction_at=$(now_utc)"
[ -n "$RECOMMENDED_FORMULA" ] && set -- "$@" --set-metadata "gc.recommended_formula=$RECOMMENDED_FORMULA"
gc_bd update "$BEAD" "$@" >/dev/null 2>&1 \
    || die "could not record the disposition on $BEAD (does it exist${DB:+ in $DB}?) — nothing else was written"

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
"$HELM" "$@" || die "gc-helm.sh takeaway failed on $BEAD; its message above names what landed and what did not. The disposition record stands — clear the cause and re-run this command."

# The edge is the hold. gc-helm.sh warns on a rejected edge and keeps going,
# which is right for a headline but not for the exits that hold on one: a
# blocked disposition waits on its blocker, a ruling waits on its visit, and
# either whose edge never landed leaves the bead unheld with nothing to say so.
# A missing edge fails the whole exit, so the terminal step stops rather than
# closing over a bead that is recorded as waiting and is not held.
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
        || die "the $DISPOSITION disposition on $BEAD did not land. Nothing holds it on:${MISSING}, so the bead is not held — it reads as parked on prose alone, the wait this exit recorded carried by no edge. The record, the headline and the release stand — only the hold is missing, so wire the edge above by hand to complete it (a second dispose is refused, because the release already landed)."
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

printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${TARGET:-no target}"
