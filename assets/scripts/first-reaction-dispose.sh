#!/usr/bin/env bash
# first-reaction-dispose.sh — the disposition a first reaction ends in.
# A reaction reads a subject bead S once and takes one of five exits, and this
# script performs it as the write-back to S. Each exit advances S and leaves it
# open; none of them closes it.
#
#   actionable  the bead is work -> release it TO a pool, which is the whole
#               of "schedule an action for a bead": a routed, unassigned,
#               open bead is what a pool's find-work offers. Work that is a
#               named agent's own (a town-repo edit is mechanik's) is released
#               TO that agent instead, as its assignee (--assign).
#   recommend   the action is known but warrants the operator's trigger -> put
#               it to the operator as a human gate (as ruling does) AND stamp
#               gc.recommended_formula on the subject, so the board offers
#               Accept — which runs that mol at the subject — beside Discuss.
#               The bridge between actionable and ruling: the action is
#               determinable, but authority-gated or consequential enough to
#               confirm before it runs.
#   blocked     the bead is waiting -> the wait becomes a `blocks` edge on a
#               bead in the SAME store (component-model I1). Optionally arm a
#               deferred dispatch, so the wait converts to work when it lifts,
#               or assign the bead to the named agent whose work it is, whose
#               hook offers it once the wait lifts.
#   close       there is nothing to do -> hand the bead to a validating-closer
#               pool (mol-validate-close), which re-checks the call and closes
#               the bead or escalates. A first reaction never closes a bead. Run
#               from inside a live reaction workflow (--after-workflow), the
#               closer is deferred until that workflow closes, so it is the
#               bead's sole dispatch surface rather than a second one stacked on
#               the reaction.
#   ruling      only the operator can answer, and the reaction has no action to
#               recommend -> a human gate on the subject, Discuss-only. A gate
#               that carries a determinable action is the recommend exit.
#
# Intake holds findings for placement (docs/steering.md). The actionable exit's
# pool route and the blocked exit's --then-route reach a pool only for a bead
# that may enter one: a member of an epic (it has a parent), PR-finishing work
# (it carries anchor_bead), or an emergency that --emergency claims and main's
# own checks confirm, which is routed at P0. Any other bead is marked
# placement=pending and left unrouted, for the operator's placement sitting
# (gc-helm.sh unplaced lists it). A named agent's own work (--assign,
# --then-assign) is not pool work, so the rule does not read it.
#
# ruling and recommend file a native human gate (gc-helm.sh demand) that blocks
# the subject: the gate is the escalation's state, and orders/gate-visit-sweep
# files the visit that resolves it on its next pass. --visit holds the subject
# on a visit the caller filed instead, and files no gate.
#
# The reaction is its own leased bead R, which tracks S. Pass --reaction-bead R:
# this script performs the write-back to S, stamps gc.reacted_by=R on S as the
# completion marker (last, after any edge), and closes R. A worker that died in
# the act-on-S -> close-R window is re-offered the same R; on re-run it sees
# gc.reacted_by=R and closes R without touching S again. Called without
# --reaction-bead — the frozen invocation of a mol-first-reaction molecule
# poured before the cutover — it performs the same write-back on the claimed
# subject and, with no R to name, stamps the legacy landed proof
# gc.proactive_reaction=1 instead, and closes no R. That molecule's own REACTED
# checks and this script's re-offer guard both read the proof, so a re-offered
# frozen step does not re-release a bead a downstream worker may already hold.
#
# No attempt record is written before the act: exactly-once for a reaction bead
# is the substrate's, keyed on R's identity. The LANDED proof is written after
# the act — gc.reacted_by=R for a reaction bead, gc.proactive_reaction=1 for the
# frozen no-R path — so its presence proves the write-back landed. The card in
# S's notes is the record of what was chosen and why.
# Callers: agents/proactive/prompt.template.md, in-flight mol-first-reaction
# molecules (advance-and-drain), operators by hand.
# Exit: 0 disposed · 2 usage · 4 runtime failure.
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

usage() {
    cat >&2 <<'EOF'
Usage:
  first-reaction-dispose.sh <bead> --disposition actionable --reason "<why>" --takeaway "<headline>"
                            [--route <rig>/<agent> [--emergency] | --assign <named-agent>]
  first-reaction-dispose.sh <bead> --disposition recommend --reason "<why>" --takeaway "<recommendation; why discuss>"
                            --recommended-formula <mol> [--visit <visit-bead-id>]
  first-reaction-dispose.sh <bead> --disposition blocked --reason "<why>" --takeaway "<headline>"
                            (--waiting-on <bead-id> | --blocker "<title>" [--blocker-key <key>])...
                            [--then-route <rig>/<agent> [--emergency] | --then-assign <named-agent>]
  first-reaction-dispose.sh <bead> --disposition close --reason "<why nothing to do>" --takeaway "<headline>"
                            [--route <rig>/<agent>] [--after-workflow <root-bead-id>]
  first-reaction-dispose.sh <bead> --disposition ruling --reason "<why>" --takeaway "<headline>"
                            [--visit <visit-bead-id>]
  common: [--reaction-bead <R>] [--by <who>] [--db <path>] [--dry-run]

  --reason is required on every exit: a disposition nobody can second-guess is
  a silent classification. It lands on the bead beside the choice.
  --takeaway is the board headline (≤140 chars, enforced by gc-helm.sh).
  --reaction-bead is R, the reaction's own leased bead. Given it, this script
  stamps gc.reacted_by=R on the subject once the write-back lands and closes R.
  --route (actionable, close) defaults to ${GC_RIG}/gc-toolkit.polecat, and
  fails closed when the target cannot be rig-qualified. On close it is the
  validating-closer pool that runs mol-validate-close, which re-checks the
  no-work conclusion and closes the bead or escalates.
  --after-workflow (close) names the live workflow this close runs inside — a
  frozen mol-first-reaction molecule's own root. The closer is then DEFERRED,
  not slung now: the bead is held on that root and a deferred dispatch is
  armed, so the reconcile pass slings mol-validate-close once the root closes
  and the bead is the sole live workflow's target. Omit it to sling the closer
  immediately (a reaction bead, which is not a workflow on the subject, or an
  operator running this by hand).
  --blocker files (once) the bead the subject is waiting on, when the wait is
  not a bead yet; --blocker-key dedups repeats of one recurring cause onto
  that single bead instead of one bead per instance.
  --then-route arms the deferred dispatch that slings the subject when the
  blocker closes (assets/scripts/deferred-dispatch.sh). An arm that does not
  land fails the exit before the landed proof, so a re-run resumes it.
  Intake decides whether the actionable route and the --then-route arm are
  written at all. Only a member of an epic, PR-finishing work (anchor_bead)
  or a confirmed emergency reaches a pool. Any other bead is marked
  placement=pending and left unrouted, with no arm, for the operator's
  placement sitting.
  --emergency (actionable, or blocked with --then-route) claims the bead is a
  red main or a broken gate. The claim is checked, not taken: the head of the
  default branch of the subject's repository must carry a failing check run or
  commit status (gh). A confirmed emergency is routed, or armed, at P0. An
  unconfirmed one is held for placement like any other bead, and its note says
  what the check found.
  --assign (actionable) releases the bead to a named agent instead of a pool:
  the agent becomes its assignee, the address its own hook matches, and no
  route is stamped. A town-repo edit (city.toml, packs.lock) is mechanik's, so
  it takes --assign gc-toolkit.mechanik. Refused unless the agent is a
  registered named session whose hook reads this bead's store
  (tools/gc-proactive.sh assignable).
  --then-assign (blocked) assigns the held bead to a named agent in the same
  release. Its hook offers the bead once the wait lifts, so nothing is armed.
  ruling and recommend put the subject to the operator as a native human gate:
  the script files it with gc-helm.sh demand under the topic first-reaction,
  the takeaway as its question, and holds the subject on it. One open gate
  stands per subject and topic, so a re-run refreshes the reaction's gate
  rather than filing a second, and a demand a sitting already holds on the
  subject is left alone. orders/gate-visit-sweep files the visit that resolves
  the gate on its next pass (a 5-minute cooldown), so the subject waits up to
  one pass with a gate and no visit.
  --visit (ruling, recommend) holds the subject on a visit the caller already
  filed instead, and files no gate.
  --recommended-formula (recommend only, required) names the execution mol the
  recommendation runs; it stamps gc.recommended_formula on the subject, which
  is what offers the operator Accept on the visit. A ruling carries no
  recommended action and rejects it.
EOF
}

BEAD=""; DISPOSITION=""; REASON=""; TAKEAWAY=""; BY="proactive"
ROUTE=""; VISIT=""; THEN_ROUTE=""; BLOCKER_TITLE=""; BLOCKER_KEY=""
ASSIGN=""; THEN_ASSIGN=""; EMERGENCY=""
DB=""; DRY=""; AFTER_WORKFLOW=""; RECOMMENDED_FORMULA=""; REACTION_BEAD=""
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
        --assign)   shift; [ $# -gt 0 ] || usage_die "--assign needs a named-agent identity"; ASSIGN="$1"; shift ;;
        --assign=*) ASSIGN="${1#--assign=}"; shift ;;
        --then-assign)   shift; [ $# -gt 0 ] || usage_die "--then-assign needs a named-agent identity"; THEN_ASSIGN="$1"; shift ;;
        --then-assign=*) THEN_ASSIGN="${1#--then-assign=}"; shift ;;
        --emergency) EMERGENCY=1; shift ;;
        --waiting-on)   shift; [ $# -gt 0 ] || usage_die "--waiting-on needs a bead id"; WAITING="$WAITING $1"; shift ;;
        --waiting-on=*) WAITING="$WAITING ${1#--waiting-on=}"; shift ;;
        --blocker)   shift; [ $# -gt 0 ] || usage_die "--blocker needs a title"; BLOCKER_TITLE="$1"; shift ;;
        --blocker=*) BLOCKER_TITLE="${1#--blocker=}"; shift ;;
        --blocker-key)   shift; [ $# -gt 0 ] || usage_die "--blocker-key needs a value"; BLOCKER_KEY="$1"; shift ;;
        --blocker-key=*) BLOCKER_KEY="${1#--blocker-key=}"; shift ;;
        --visit)    shift; [ $# -gt 0 ] || usage_die "--visit needs a bead id"; VISIT="$1"; shift ;;
        --visit=*)  VISIT="${1#--visit=}"; shift ;;
        --after-workflow)   shift; [ $# -gt 0 ] || usage_die "--after-workflow needs a bead id"; AFTER_WORKFLOW="$1"; shift ;;
        --after-workflow=*) AFTER_WORKFLOW="${1#--after-workflow=}"; shift ;;
        --recommended-formula)   shift; [ $# -gt 0 ] || usage_die "--recommended-formula needs a mol name"; RECOMMENDED_FORMULA="$1"; shift ;;
        --recommended-formula=*) RECOMMENDED_FORMULA="${1#--recommended-formula=}"; shift ;;
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
    actionable|recommend|blocked|close|ruling) : ;;
    "") usage_die "needs --disposition actionable|recommend|blocked|close|ruling" ;;
    *)  usage_die "unknown disposition '$DISPOSITION' (actionable|recommend|blocked|close|ruling)" ;;
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
        [ -z "$WAITING$BLOCKER_TITLE$VISIT$THEN_ROUTE$THEN_ASSIGN$AFTER_WORKFLOW$RECOMMENDED_FORMULA" ] \
            || usage_die "actionable takes --route or --assign only (--waiting-on/--blocker/--then-route/--then-assign/--visit/--after-workflow/--recommended-formula belong to the other exits)"
        # A bead goes to a pool by gc.routed_to or to a named agent by assignee,
        # never both: the assignee drops it out of the pool's unassigned claim
        # filter, and a named agent's hook never reads the route.
        if [ -n "$ASSIGN" ]; then
            [ -z "$ROUTE" ] || usage_die "--route and --assign both name where $BEAD goes; pass --route for a pool or --assign for a named agent, not both"
            [ -z "$EMERGENCY" ] || usage_die "--emergency admits a bead to a pool at P0, and --assign hands it to a named agent instead, which intake does not hold. Pass --route for the pool an emergency goes to, or drop --emergency."
        else
            [ -n "$ROUTE" ] || ROUTE="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
            case "$ROUTE" in
                */*) : ;;
                *) usage_die "cannot rig-qualify the route target '$ROUTE': set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody. A named agent such as gc-toolkit.mechanik takes --assign." ;;
            esac
        fi
        ;;
    close)
        # close routes to a validating closer, so it takes --route like
        # actionable; the closer re-checks the no-work call and closes the bead.
        # --after-workflow names the live workflow this close is performed from
        # (a frozen first-reaction molecule's own root): the closer is deferred
        # until that root closes, so it is poured as the bead's sole dispatch
        # surface, never a second one stacked on the live reaction. A reaction
        # bead is not a workflow on the subject, so it slings the closer now.
        [ -z "$WAITING$BLOCKER_TITLE$VISIT$THEN_ROUTE$ASSIGN$THEN_ASSIGN$RECOMMENDED_FORMULA$EMERGENCY" ] \
            || usage_die "close takes --route and --after-workflow only (--waiting-on/--blocker/--then-route/--assign/--then-assign/--visit/--recommended-formula/--emergency belong to the other exits)"
        [ -n "$ROUTE" ] || ROUTE="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
        case "$ROUTE" in
            */*) : ;;
            *) usage_die "cannot rig-qualify the closer target '$ROUTE': set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody." ;;
        esac
        if [ -n "$AFTER_WORKFLOW" ]; then
            [ -z "$REACTION_BEAD" ] \
                || usage_die "--after-workflow names a frozen reaction molecule's root; a reaction bead ($REACTION_BEAD) is not a workflow on $BEAD, so its close slings the closer now. Drop --after-workflow."
            [ "$AFTER_WORKFLOW" != "$BEAD" ] || usage_die "--after-workflow $AFTER_WORKFLOW is the bead itself"
            same_store "$AFTER_WORKFLOW" "$BEAD" \
                || usage_die "--after-workflow $AFTER_WORKFLOW is in another store than $BEAD; the gating hold is a blocks edge, which holds nothing across stores (component-model I1)."
        fi
        ;;
    blocked)
        [ -z "$ROUTE$ASSIGN$VISIT$AFTER_WORKFLOW$RECOMMENDED_FORMULA" ] || usage_die "blocked takes --waiting-on/--blocker/--then-route/--then-assign (--route/--assign/--visit/--after-workflow/--recommended-formula belong to the other exits)"
        [ -z "$THEN_ROUTE" ] || [ -z "$THEN_ASSIGN" ] \
            || usage_die "--then-route and --then-assign both name where $BEAD goes once its wait lifts; pass --then-route for a pool or --then-assign for a named agent, not both"
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
            # The arm is part of this exit's write-back, and with no tool to
            # record it the exit cannot land, so it does not start.
            [ -x "$DEFERRED" ] \
                || die "--then-route needs $DEFERRED to arm the dispatch for when $BEAD's wait lifts, and it is not executable. Nothing was written. Restore it and re-run this command."
        else
            [ -z "$EMERGENCY" ] \
                || usage_die "--emergency admits the dispatch a --then-route arms, at P0, and this blocked exit arms none. Pass --then-route <rig>/<agent>, or drop --emergency."
        fi
        ;;
    recommend|ruling)
        # Both put the subject to the operator and hold it there on a blocks
        # edge: on the human gate this script files, or on the visit --visit
        # names. They differ only in whether a recommended action rides along.
        # recommend REQUIRES --recommended-formula (it is the disposition that
        # stamps the key the board's Accept reads); ruling REJECTS it (the
        # operator's judgment names no worker-runnable action, so the visit is
        # Discuss-only).
        [ -z "$ROUTE$ASSIGN$WAITING$BLOCKER_TITLE$THEN_ROUTE$THEN_ASSIGN$AFTER_WORKFLOW$EMERGENCY" ] \
            || usage_die "$DISPOSITION takes --visit (and --recommended-formula on recommend); --route/--assign/--waiting-on/--blocker/--then-route/--then-assign/--after-workflow/--emergency belong to the other exits"
        if [ -n "$VISIT" ]; then
            [ "$VISIT" != "$BEAD" ] || usage_die "--visit $VISIT is the bead itself"
            same_store "$VISIT" "$BEAD" \
                || usage_die "--visit $VISIT is in another store than $BEAD; a blocks edge onto it reports success and holds nothing (component-model I1). File the visit in ${BEAD%%-*}'s store, then record it here."
        fi
        if [ "$DISPOSITION" = recommend ]; then
            [ -n "$RECOMMENDED_FORMULA" ] \
                || usage_die "recommend needs --recommended-formula <mol>: it is the action the operator Accepts from the visit. A visit with no recommended action is --disposition ruling."
            # Accept slings this exact mol name, so validate it resolves before
            # anything is written — the roster discipline --route/--then-route
            # already take. Unvalidated, a typo stamps a live
            # gc.recommended_formula, the board renders 'accept ▸', and every
            # click fails at gc sling. A usage error here refuses it at the
            # source instead.
            gc formula show "$RECOMMENDED_FORMULA" >/dev/null 2>&1 \
                || usage_die "--recommended-formula '$RECOMMENDED_FORMULA' does not resolve to a formula (gc formula show found none). Accept slings this exact name; fix the typo, or run 'gc formula list' for the roster."
        else
            [ -z "$RECOMMENDED_FORMULA" ] \
                || usage_die "ruling does not take --recommended-formula: a ruling is the operator's judgment with no worker-runnable action (Discuss-only). To recommend an action the operator can Accept, use --disposition recommend."
        fi
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
# The subject's rig checkout, for the one read that needs its repository rather
# than its store: an emergency's check of main.
RIG_PATH="${_path:-}"
[ -n "$RIG_PATH" ] || case "$DB" in */.beads) RIG_PATH="${DB%/.beads}" ;; esac

# The pin rides at the END of every call: `gc bd <verb> … --db <path>`, the
# form every other caller in the pack uses.
# shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
gc_bd() { gc bd "$@" $BD_DB_ARGS; }

# ── Read the subject once; the guards below all ask its metadata ──────
# The store is pinned, so this reads the subject's own rig. The re-offer guard
# and the stale-recommendation clear both key off it, and one read keeps them
# from disagreeing. Positive finding only: an unreadable bead is not evidence of
# anything, so an empty read falls through to the act.
SUBJECT_JSON=$(gc_bd show "$BEAD" --json 2>/dev/null | scrub || printf '')
subject_meta() {
    printf '%s' "$SUBJECT_JSON" \
        | jq -r --arg k "$1" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

# ── Close R once the write-back has landed ────────────────────────────
# R is the reaction's own work bead. Closing it is what records the reaction
# done — exactly-once is the substrate's, keyed on R, not on a stamp on S. A
# close that is refused leaves R open under this worker's lease; the re-offer
# then re-runs and reaches this close again, so a transient refusal self-heals.
# R is a plain task, so its close answers the work-record contract too: its work
# is a card and a disposition on S, never a commit, so gc.work_outcome=no-op.
close_reaction() {
    [ -n "$REACTION_BEAD" ] || return 0
    if gc_bd update "$REACTION_BEAD" --set-metadata "gc.outcome=reacted" --set-metadata "gc.work_outcome=no-op" --status=closed >/dev/null 2>&1; then
        note "closed reaction bead $REACTION_BEAD"
    else
        note "WARNING: could not close reaction bead $REACTION_BEAD; the write-back landed, so a re-offer of $REACTION_BEAD reads gc.reacted_by on $BEAD and closes it. Close it by hand: gc bd update $REACTION_BEAD --status=closed"
    fi
}

# ── A reaction happens once — self-heal the act-on-S -> close-R window ─
# The write-back stamps a landed proof on S as its last act (gc.reacted_by=R
# with a reaction bead, gc.proactive_reaction=1 on the frozen no-R path). A
# worker re-offered after a crash in that window reads the proof and does not
# re-dispose — S is never re-released, never yanked from a worker that has since
# claimed a routed S, and never handed a second closer.
if [ -n "$REACTION_BEAD" ]; then
    PRIOR_REACTED_BY=$(subject_meta "gc.reacted_by")
    if [ "$PRIOR_REACTED_BY" = "$REACTION_BEAD" ]; then
        note "$BEAD already carries this reaction's write-back (gc.reacted_by=$PRIOR_REACTED_BY); closing $REACTION_BEAD without re-disposing."
        close_reaction
        exit 0
    fi
else
    # The frozen mol-first-reaction call has no R to key exactly-once on, so its
    # landed proof is the legacy gc.proactive_reaction=1 stamped below. A
    # re-offered frozen step reads it here and stops before the act — a second
    # release would reopen and re-route a bead a downstream worker may hold.
    PRIOR_PROACTIVE=$(subject_meta "gc.proactive_reaction")
    if [ "$PRIOR_PROACTIVE" = "1" ]; then
        note "$BEAD already carries a landed first reaction (gc.proactive_reaction=$PRIOR_PROACTIVE); not re-disposing. A frozen mol-first-reaction molecule keys exactly-once on this legacy marker, and a second release would yank a bead a worker may already hold."
        exit 0
    fi
fi

# ── Intake: only placed work, PR-finishing work or an emergency enters a pool ──
# A bead may be routed or armed to a pool only when it is a member of an epic,
# PR-finishing work of an anchor, an emergency checked rather than asserted, or
# routed by the operator (docs/steering.md). A reaction is none of the
# operator's moves, so the first three decide. The pool route this exit would
# write is the actionable exit's --route or the blocked exit's --then-route. A
# named agent's own work (--assign, --then-assign) is no pool route, so the rule
# does not read it, and the close exit's validating closer shrinks the queue
# rather than adding work to it.
#
# A bead the rule does not admit is held for placement: marked placement=pending
# and left unrouted, with no arm, until the operator's placement sitting places
# it under an epic or routes it on its own. An unreadable subject proves no
# membership, so it is held too.
POOL_TARGET=""
case "$DISPOSITION" in
    actionable) [ -n "$ASSIGN" ] || POOL_TARGET="$ROUTE" ;;
    blocked)    POOL_TARGET="$THEN_ROUTE" ;;
esac

# subject_parent — the subject's parent, or empty. bd shows a parent as .parent
# and as a parent-child dependency; either one is membership.
subject_parent() {
    printf '%s' "$SUBJECT_JSON" | jq -r '
        if type == "array" and length > 0 then
          (.[0] as $b
           | [ ($b.parent // ""),
               ($b.dependencies[]? | select(((.dependency_type // .type) // "") == "parent-child")
                                   | (.id // .depends_on_id // "")) ]
           | map(select(type == "string" and . != "")) | .[0] // "")
        else "" end' 2>/dev/null || printf ''
}

# main_red — is the default branch of the subject's repository red right now?
# Red is a check run on its head that concluded failure, timed_out or
# startup_failure, or a commit status of failure or error. A run that is still
# going, or one cancelled by a newer push, is not red. Sets MAIN_RED_WHY to the
# evidence either way and returns 0 red, 1 not red, 2 unknown. Unknown covers a
# checkout, an origin or a GitHub answer that could not be read, and it confirms
# nothing, so a check that cannot run leaves the claim unconfirmed. A gate broken
# in a way main's own checks do not show cannot be confirmed here either.
MAIN_RED_WHY=""
main_red() {
    MAIN_RED_WHY=""
    command -v gh >/dev/null 2>&1 \
        || { MAIN_RED_WHY="gh is not installed, so main's checks could not be read"; return 2; }
    [ -n "$RIG_PATH" ] \
        || { MAIN_RED_WHY="no rig checkout is known for ${BEAD%%-*}, so its repository could not be named"; return 2; }
    _url=$(git -C "$RIG_PATH" remote get-url origin 2>/dev/null | tr -d '[:space:]')
    _slug=""
    case "$_url" in
        git@github.com:*|https://github.com/*|ssh://git@github.com/*)
            _slug=$(printf '%s' "$_url" | sed -e 's#^ssh://git@github.com/##' \
                -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    case "$_slug" in */*/*|/*|*/) _slug="" ;; */*) : ;; *) _slug="" ;; esac
    [ -n "$_slug" ] \
        || { MAIN_RED_WHY="the origin of $RIG_PATH (${_url:-none}) is not a GitHub repository"; return 2; }
    _branch=$(gh api "repos/$_slug" 2>/dev/null | scrub | jq -r 'if type == "object" then (.default_branch // "") else "" end' 2>/dev/null || printf '')
    [ -n "$_branch" ] \
        || { MAIN_RED_WHY="GitHub did not name the default branch of $_slug"; return 2; }
    _runs=$(gh api "repos/$_slug/commits/$_branch/check-runs?per_page=100" 2>/dev/null | scrub)
    _status=$(gh api "repos/$_slug/commits/$_branch/status" 2>/dev/null | scrub)
    _shape=$(jq -rn --argjson r "${_runs:-null}" --argjson s "${_status:-null}" '
        if (($r | type) == "object" and ($r.check_runs | type) == "array"
            and ($s | type) == "object" and ($s.statuses | type) == "array") then "ok" else "unknown" end' 2>/dev/null || printf 'unknown')
    [ "$_shape" = ok ] \
        || { MAIN_RED_WHY="GitHub did not answer for the checks on $_branch of $_slug"; return 2; }
    _sha=$(jq -rn --argjson r "$_runs" --argjson s "$_status" \
        '($s.sha // $r.check_runs[0].head_sha // "") | tostring | .[0:12]' 2>/dev/null || printf '')
    _red=$(jq -rn --argjson r "$_runs" --argjson s "$_status" '
        [ $r.check_runs[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")
          | "\(.name) (\(.conclusion))" ]
        + [ $s.statuses[] | select(.state == "failure" or .state == "error") | "\(.context) (\(.state))" ]
        | unique | join(", ")' 2>/dev/null || printf '')
    if [ -n "$_red" ]; then
        MAIN_RED_WHY="$_branch of $_slug${_sha:+ at $_sha} is red: $_red"
        return 0
    fi
    MAIN_RED_WHY="$_branch of $_slug${_sha:+ at $_sha} has no failing check"
    return 1
}

ADMIT=""         # member | pr-finishing | emergency; empty holds the bead for placement
ADMIT_WHY=""; HOLD_WHY=""
if [ -n "$POOL_TARGET" ]; then
    if [ -n "$EMERGENCY" ]; then
        if main_red; then
            ADMIT=emergency; ADMIT_WHY="$MAIN_RED_WHY"
        else
            HOLD_WHY="--emergency was not confirmed: $MAIN_RED_WHY"
        fi
    fi
    if [ -z "$ADMIT" ]; then
        _parent=$(subject_parent)
        _anchor=$(subject_meta anchor_bead)
        if [ -n "$_parent" ]; then
            ADMIT=member; ADMIT_WHY="a member of $_parent"
        elif [ -n "$_anchor" ]; then
            ADMIT=pr-finishing; ADMIT_WHY="PR-finishing work of $_anchor"
        fi
    fi
    if [ -n "$ADMIT" ]; then
        note "intake admits $BEAD to $POOL_TARGET: ${ADMIT_WHY}${HOLD_WHY:+ ($HOLD_WHY)}"
    else
        HOLD_WHY="${HOLD_WHY:+$HOLD_WHY; }$BEAD has no parent epic and is not PR-finishing work"
        note "intake holds $BEAD for placement instead of ${POOL_TARGET}: $HOLD_WHY"
    fi
fi

# ── Route only where something can claim ─────────────────────────────
# A route to a pool this city does not run — or one whose rig does not own this
# bead's store — is worse than a visit: the bead is open, unassigned and offered
# to nobody, and nothing says so. gc-proactive.sh `deliverable` answers exactly
# this against the agent roster and, given the bead, against store ownership too
# (a rig-scope pool only claims beads in its own store), for any rig-qualified
# target, and it answers no only on a positive finding — so a probe that cannot
# run leaves the disposition alone. A route intake holds for placement is never
# written, so it is not asked about.
CLAIM_ROUTE=""
case "$DISPOSITION" in
    actionable) [ -n "$ADMIT" ] && CLAIM_ROUTE="$ROUTE" ;;
    close)      CLAIM_ROUTE="$ROUTE" ;;
esac
if [ -n "$CLAIM_ROUTE" ] && [ -x "$PROACTIVE" ]; then
    DELIVERABLE_WHY="$("$PROACTIVE" deliverable "$ROUTE" "$BEAD" 2>/dev/null)" || {
        if [ "$DISPOSITION" = "actionable" ]; then
            usage_die "$ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Routing there would leave $BEAD open, unassigned and offered to nobody. Route it to a pool that can claim it, or address it with --assign to the named agent whose work it is (a town-repo edit is gc-toolkit.mechanik's). Put it to the operator (--disposition recommend or ruling) only when the next move is the operator's."
        else
            usage_die "$ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Routing there would leave $BEAD open, unassigned and offered to nobody. Put it to the operator instead (--disposition recommend or ruling)."
        fi
    }
fi
# An assignment is held to the same standard: --assign and --then-assign name a
# named agent whose own hook must offer the bead, and gc-proactive.sh
# `assignable` answers that against the roster, the named sessions and the
# stores the agent's hook reads, answering no only on a positive finding.
WHO="${ASSIGN:-$THEN_ASSIGN}"
if [ -n "$WHO" ] && [ -x "$PROACTIVE" ]; then
    ASSIGNABLE_WHY="$("$PROACTIVE" assignable "$WHO" "$BEAD" 2>/dev/null)" || {
        usage_die "$WHO cannot be handed this bead — ${ASSIGNABLE_WHY:-the agent answered no}. Assigning it there would leave $BEAD offered to nobody. Name the agent by its exact qualified name (gc-toolkit.mechanik for a town-repo edit), or route a pool with --route/--then-route."
    }
fi
# --then-route names the pool the deferred dispatch slings the bead to once its
# blocker lifts, so it is held to the SAME roster and store test as --route. Its
# own check at parse time only tests for a "/", which a copied `<rig>/<agent>`
# placeholder passes; a target the roster does not know, or one whose rig does
# not own this bead's store, would arm a dispatch every reconcile pass replays
# into a failure. The probe answers no only on a positive finding, so an
# unrunnable probe leaves the arm alone. An arm intake holds for placement is
# never written, so it is not asked about either.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ] && [ -n "$ADMIT" ] && [ -x "$PROACTIVE" ]; then
    DELIVERABLE_WHY="$("$PROACTIVE" deliverable "$THEN_ROUTE" "$BEAD" 2>/dev/null)" || {
        usage_die "--then-route $THEN_ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Arming it would record a dispatch the reconcile pass replays into a failure every cycle. Pass a pool that runs (e.g. <rig>/<rig>.polecat), or omit --then-route if no pool takes this bead."
    }
fi

# Origin does not decide the exit. A bead's `gc.origin` is a fact the reacting
# agent weighs in its triage — an operator capture with a clear, reversible
# action moves forward like any other bead — but it gates nothing here. The
# guardrail that a genuine fork, an irreversible or destructive action, or a
# policy call still goes to a human lives in the reacting agent's rubric
# (agents/proactive/prompt.template.md), which is what chooses the disposition;
# this script performs the one it was given. The checks above stay whatever the
# reacting agent intended: intake, because the operator decides what new work
# enters a pool, and the route-deliverability and same-store guards, because
# they catch a disposition that cannot land.

if [ -n "$DRY" ]; then
    printf 'disposition=%s bead=%s reason=%s\n' "$DISPOSITION" "$BEAD" "$REASON"
    case "$DISPOSITION" in
        actionable) if [ -n "$ASSIGN" ]; then
                        printf 'would release %s to named agent %s (assignee, no route)\n' "$BEAD" "$ASSIGN"
                    elif [ -z "$ADMIT" ]; then
                        printf 'would hold %s for placement (placement=pending, unrouted): %s\n' "$BEAD" "$HOLD_WHY"
                    elif [ "$ADMIT" = emergency ]; then
                        printf 'would release %s to %s at P0: %s\n' "$BEAD" "$ROUTE" "$ADMIT_WHY"
                    else
                        printf 'would release %s to %s\n' "$BEAD" "$ROUTE"
                    fi ;;
        recommend)  if [ -n "$VISIT" ]; then
                        printf 'would record visit %s on %s recommending %s\n' "$VISIT" "$BEAD" "$RECOMMENDED_FORMULA"
                    else
                        printf 'would file a human gate on %s recommending %s and hold %s on it\n' "$BEAD" "$RECOMMENDED_FORMULA" "$BEAD"
                    fi ;;
        blocked)    printf 'would wait %s on:%s%s%s\n' "$BEAD" "$WAITING" "${BLOCKER_TITLE:+ (new: $BLOCKER_TITLE)}" "${THEN_ASSIGN:+, assigned to $THEN_ASSIGN}"
                    if [ -n "$THEN_ROUTE" ] && [ -z "$ADMIT" ]; then
                        printf 'would hold %s for placement (placement=pending) and arm no dispatch to %s: %s\n' "$BEAD" "$THEN_ROUTE" "$HOLD_WHY"
                    elif [ -n "$THEN_ROUTE" ]; then
                        _p0=""; [ "$ADMIT" = emergency ] && _p0=" at P0"
                        printf 'would arm a dispatch to %s%s for when the wait lifts\n' "$THEN_ROUTE" "$_p0"
                    fi ;;
        close)      if [ -n "$AFTER_WORKFLOW" ]; then
                        printf 'would hold %s on %s, then arm a deferred dispatch to validating closer %s (mol-validate-close) for when %s closes\n' "$BEAD" "$AFTER_WORKFLOW" "$ROUTE" "$AFTER_WORKFLOW"
                    else
                        printf 'would sling %s to validating closer %s (mol-validate-close)\n' "$BEAD" "$ROUTE"
                    fi ;;
        ruling)     if [ -n "$VISIT" ]; then
                        printf 'would record visit %s on %s\n' "$VISIT" "$BEAD"
                    else
                        printf 'would file a human gate on %s and hold %s on it\n' "$BEAD" "$BEAD"
                    fi ;;
    esac
    [ -n "$REACTION_BEAD" ] && printf 'would close reaction bead %s\n' "$REACTION_BEAD"
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

# What the disposition names, for the line this script prints. A ruling or
# recommend that files its own gate names it once the gate exists, below.
TARGET=""
case "$DISPOSITION" in
    actionable) TARGET="${ASSIGN:-$ROUTE}" ;;
    recommend)  TARGET="$VISIT" ;;
    blocked)    TARGET="$(printf '%s' "${WAITING# }" | tr -s ' ' ',')" ;;
    close)      TARGET="$ROUTE" ;;
    ruling)     TARGET="$VISIT" ;;
esac
if [ -n "$POOL_TARGET" ]; then
    case "$DISPOSITION:$ADMIT" in
        blocked:)          TARGET="$TARGET; held for placement" ;;
        actionable:)       TARGET="held for placement" ;;
        blocked:emergency) TARGET="$TARGET; armed at P0" ;;
        *:emergency)       TARGET="$TARGET at P0" ;;
    esac
fi

# ── The recommendation, before the act ───────────────────────────────
# A recommend disposition stamps gc.recommended_formula: it is the field that
# turns a plain visit into a recommendation visit (the operator's Accept reads
# it), so it lands before the gate that brings the visit. Any disposition that
# names no recommendation clears a stale one a prior recommend left, so the
# subject states the current recommendation and never a superseded one the
# operator could still Accept. RECO_WANT is what gc.recommended_formula must
# read back as after this write: the named mol on a recommend disposition, empty
# (absent) when a disposition names none and clears a stale one. RECO_TOUCHED
# marks that this write changed the key, so the read-back below runs only when it
# did.
RECO_WANT=""; RECO_TOUCHED=""
if [ -n "$RECOMMENDED_FORMULA" ]; then
    RECO_WANT="$RECOMMENDED_FORMULA"; RECO_TOUCHED=1
    gc_bd update "$BEAD" --set-metadata "gc.recommended_formula=$RECOMMENDED_FORMULA" >/dev/null 2>&1 \
        || die "could not stamp gc.recommended_formula on $BEAD (does it exist${DB:+ in $DB}?) — nothing else was written"
elif [ -n "$(subject_meta gc.recommended_formula)" ]; then
    RECO_TOUCHED=1
    gc_bd update "$BEAD" --unset-metadata "gc.recommended_formula" >/dev/null 2>&1 \
        || die "could not clear the stale gc.recommended_formula on $BEAD (does it exist${DB:+ in $DB}?) — nothing else was written"
fi

# ── The recommendation must be true before the act ───────────────────
# gc.recommended_formula is read as a NON-EMPTY value by every reader — the
# board's Accept derivation (services/helm/internal/board/derive.go tests
# `rf != ""`), gc-helm.sh accept, and converse-invalidate-recommendation.sh — so
# a present-but-empty key is no live recommendation, and the stale-clear above
# tests it the same non-empty way. An update can report success without proving
# the key moved, and a silent drop is invisible until the operator meets the
# wrong affordance — a dropped set files a recommendation visit that offers only
# Discuss, a dropped stale-clear leaves a superseded Accept executable. So read
# it back from a valid payload, retry the lone set/unset once, and refuse before
# the act if it is still wrong — or if the subject cannot be read to prove the
# key moved; nothing else has been written, so this command re-runs.
if [ -n "$RECO_TOUCHED" ]; then
    # Tag the read so an unreadable subject is never mistaken for a proven
    # clear: "v:<value>" is a valid array payload (<value> empty = key absent),
    # "u:" is a non-array, error object, empty, or unparseable read whose state
    # is unknown. gc bd show answers an error OBJECT (not an array) for a subject
    # it cannot resolve, and a bare "" would collapse that onto "key absent" and
    # let a dropped stale-clear (RECO_WANT empty) satisfy the guard. So the guard
    # compares against "v:$RECO_WANT"; a "u:" matches neither the set nor the
    # clear, and the read-back fails closed.
    reco_now() {
        gc_bd show "$BEAD" --json 2>/dev/null | scrub \
            | jq -r 'if (type == "array" and length > 0) then "v:" + (((.[0].metadata // {})["gc.recommended_formula"]) // "") else "u:" end' 2>/dev/null \
            || printf 'u:'
    }
    RECO_OK="v:$RECO_WANT"
    if [ "$(reco_now)" != "$RECO_OK" ]; then
        if [ -n "$RECO_WANT" ]; then
            gc_bd update "$BEAD" --set-metadata "gc.recommended_formula=$RECO_WANT" >/dev/null 2>&1 || true
        else
            gc_bd update "$BEAD" --unset-metadata "gc.recommended_formula" >/dev/null 2>&1 || true
        fi
    fi
    RECO_GOT="$(reco_now)"
    if [ "$RECO_GOT" != "$RECO_OK" ]; then
        if [ -n "$RECO_WANT" ]; then
            die "the recommendation did not land on $BEAD: gc.recommended_formula read back as '$RECO_GOT' (want 'v:$RECO_WANT'; a 'u:' means the subject could not be read, which is not proof it landed). The operator's Accept reads this key, so the act is withheld rather than leave the operator a recommendation visit that offers only Discuss. Clear the cause and re-run this command."
        else
            die "the stale recommendation did not clear on $BEAD: gc.recommended_formula read back as '$RECO_GOT' (want 'v:' for a proven-absent key; a 'u:' means the subject could not be read, which is not proof it cleared). A disposition that recommends nothing must not leave a superseded Accept executable, so the act is withheld. Clear the cause and re-run this command."
        fi
    fi
fi

# ── The completion marker, last ──────────────────────────────────────
# The landed proof is stamped after the act (and after any edge or arm) so its
# presence proves the whole write-back landed, and the re-offer guard at the top
# reads it to skip a second dispose. With a reaction bead it is gc.reacted_by=R;
# the frozen no-R path has no R to name, so it stamps the legacy
# gc.proactive_reaction=1 — the same marker that molecule's own REACTED checks
# read. A lost R stamp is safe (the write-backs are idempotent and the re-offered
# R reaches the close again); a lost no-R stamp is the window the frozen
# molecule's step chain does not cover, so it fails the exit with the by-hand
# repair named.
stamp_landed() {
    if [ -n "$REACTION_BEAD" ]; then
        gc_bd update "$BEAD" --set-metadata "gc.reacted_by=$REACTION_BEAD" >/dev/null 2>&1 \
            || note "WARNING: could not stamp gc.reacted_by=$REACTION_BEAD on $BEAD; the disposition landed, so a re-offer of $REACTION_BEAD re-runs the idempotent write-back and reaches the close again."
    else
        gc_bd update "$BEAD" --set-metadata "gc.proactive_reaction=1" >/dev/null 2>&1 \
            || die "the $DISPOSITION disposition landed on $BEAD but gc.proactive_reaction=1 did not stamp; a re-offered frozen mol-first-reaction step reads no landed proof and would re-dispose, reopening and re-routing a bead a worker may already hold. Stamp it by hand: gc bd update $BEAD${DB:+ --db $DB} --set-metadata gc.proactive_reaction=1"
    fi
}

# ── The close exit: hand the bead to a validating closer, never close here ────
# The reaction concluded there is nothing to do. first-reaction never closes a
# bead — a cheap model must not have the last word on a close — so the bead is
# handed to a capable pool running mol-validate-close, which re-checks the
# conclusion against live state and closes the bead only when it agrees,
# escalating to a human or re-routing when it does not. mol-validate-close reads
# its subject as its input convoy's single tracked member, so the bead is claimed
# there as the workflow's member, not via a raw pool route — a raw route runs
# mol-polecat-work, which never closes a bead.
#
# --after-workflow names the live reaction workflow a frozen molecule's close
# runs inside. The closer must be the bead's SOLE dispatch surface, never a
# second workflow stacked on the still-live reaction
# (docs/reference/specs/formula-spec-v2.md §3, "one live dispatch surface per
# unit of work"). So that sling is DEFERRED: the bead is held on the reaction's
# own workflow root and a deferred dispatch is armed, and the deferred-dispatch
# reconcile pass slings mol-validate-close once that root closes and bd reports
# the bead ready. A reaction bead is no workflow on the subject, and an operator
# by hand has none, so with --after-workflow absent the closer is slung now.
#
# The closer validates a claim, so the claim travels with the bead: --reason
# (why there is no work, and the counter-case for keeping the bead open) is
# appended to the subject's notes as its close brief, beside the reaction's
# card, before anything can dispatch the closer that reads it.
if [ "$DISPOSITION" = "close" ]; then
    gc_bd update "$BEAD" --append-notes "## Close brief (first reaction, $(date -u +%Y-%m-%dT%H:%M:%SZ))
$REASON" >/dev/null 2>&1 \
        || die "could not append the close brief to $BEAD's notes; the validating closer reads it there, so nothing was dispatched. Clear the cause and re-run this command."
    if [ -n "$AFTER_WORKFLOW" ]; then
        # Gate the deferred dispatch: hold the bead on the live reaction root so
        # reconcile does not sling until it closes. The hold is a REQUIRED write.
        # Reconcile dispatches from `bd list --ready`, so a bead left unheld reads
        # ready and mol-validate-close slings beside the still-live reaction, the
        # two-live-surfaces shape this exit exists to prevent (formula-spec-v2 §3).
        # A hold that does not land therefore fails closed: refuse to arm, and let
        # the documented re-run resume.
        gc_bd dep add "$BEAD" "$AFTER_WORKFLOW" -t blocks >/dev/null 2>&1 \
            || die "could not hold $BEAD on the reaction root $AFTER_WORKFLOW; refusing to arm the closer dispatch ungated (reconcile would sling mol-validate-close beside the live reaction). Clear the cause and re-run this command."
        # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
        "$DEFERRED" arm "$BEAD" --target "$ROUTE" --sling-arg --on --sling-arg mol-validate-close --reason "first reaction close: $REASON" $BD_DB_ARGS >/dev/null 2>&1 \
            || die "could not arm the validating-closer dispatch on $BEAD (deferred-dispatch arm --on mol-validate-close failed). Clear the cause and re-run this command."
    else
        SLING_RIG_ARG=""
        [ -n "${GC_RIG:-}" ] && SLING_RIG_ARG="--rig $GC_RIG"
        # shellcheck disable=SC2086  # $SLING_RIG_ARG expands to 0 or 2 space-free fields
        gc sling $SLING_RIG_ARG "$ROUTE" "$BEAD" --on mol-validate-close >/dev/null 2>&1
        sling_rc=$?
        if [ "$sling_rc" -ne 0 ]; then
            # gc sling exits 3 only when a live workflow already drives the bead.
            # For a reaction bead re-offered after the crash window, that is the
            # closer this same reaction slung on its earlier run, so the act has
            # landed and the run carries on to the marker and the close of R.
            # Anything else, or a 3 with no reaction bead behind it, is a sling
            # that did not happen.
            if [ "$sling_rc" -eq 3 ] && [ -n "$REACTION_BEAD" ]; then
                note "a live workflow already drives $BEAD (the validating closer an earlier run of $REACTION_BEAD slung); not slinging a second"
            else
                die "could not sling $BEAD to the validating closer $ROUTE (gc sling --on mol-validate-close exited $sling_rc). Clear the cause and re-run this command."
            fi
        fi
    fi
    # The board headline, for the moment the closer escalates back to a visit.
    "$HELM" takeaway "$BEAD" "$TAKEAWAY" --by "$BY" >/dev/null 2>&1 \
        || note "dispatched the closer for $BEAD but the board takeaway did not set; the closer holds the bead regardless"
    stamp_landed
    close_reaction
    printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${TARGET:-no target}"
    exit 0
fi

# ── The ruling and recommend exits' human gate ───────────────────────
# The next move is the operator's, and what a person owes is a native human gate
# that blocks the subject (gc-helm.sh demand; docs/gascity-human-engagement.md).
# The takeaway is its question, the same sentence the board shows on the
# subject. demand keeps one open gate per gated bead and topic, and this gate is
# filed under the topic first-reaction. So a re-run after a partial refreshes
# the gate a prior run filed instead of filing a second, and a demand a converse
# sitting already holds on the subject keeps its own question. With no topic,
# demand matches on the subject alone: it would refresh a sitting's lone demand
# in place and overwrite its question, and it would stop on a subject that
# carries two.
#
# It is filed after the recommendation read-back above because the gate is what
# brings the visit: orders/gate-visit-sweep files the visit that resolves it on
# its next pass, and on a recommend that visit must offer Accept. Until the pass
# runs, the subject waits on a gate with no visit.
GATE=""
if { [ "$DISPOSITION" = "ruling" ] || [ "$DISPOSITION" = "recommend" ]; } && [ -z "$VISIT" ]; then
    DEMAND_OUT=$("$HELM" demand "$BEAD" "$TAKEAWAY" --by "$BY" --topic first-reaction --body "Filed by a first reaction on $BEAD ($DISPOSITION), which waits on it.

$REASON

The card in $BEAD's notes carries the evidence. Resolving this gate makes $BEAD ready.") \
        || die "could not file the human gate on $BEAD (gc-helm.sh demand failed; its message above names what landed and what did not). Clear the cause and re-run this command."
    GATE=$(printf '%s\n' "$DEMAND_OUT" | awk '/^demand /{print $2; exit}')
    [ -n "$GATE" ] \
        || die "gc-helm.sh demand named no gate for $BEAD (its output: ${DEMAND_OUT:-<empty>}). Re-run this command; demand refreshes a gate it already filed rather than filing a second."
    TARGET="$GATE"
    note "put $BEAD to the operator as the human gate $GATE; gate-visit-sweep files its visit on its next pass"
fi

# ── Intake's write, before the act ───────────────────────────────────
# A held bead carries placement=pending before the release leaves it unrouted,
# so it is never open and unrouted without the marker that puts it in the
# sitting's queue. A confirmed emergency carries P0 before its route or its arm,
# so it is never claimable at the priority it was filed at. Either write carries
# a note saying what intake found, and either is read back: one that did not
# land stops the exit before the act, with no landed proof, so a re-run resumes.
# subject_now <jq-path> answers "v:<value>" from a readable subject and "u:"
# from anything else, so an unreadable subject never reads as a write that
# landed.
subject_now() {
    gc_bd show "$BEAD" --json 2>/dev/null | scrub \
        | jq -r "if (type == \"array\" and length > 0) then \"v:\" + (((.[0] | $1) // \"\") | tostring) else \"u:\" end" 2>/dev/null \
        || printf 'u:'
}
if [ -n "$POOL_TARGET" ]; then
    INTAKE_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if [ -z "$ADMIT" ]; then
        set -- --set-metadata "placement=pending" --append-notes "## Intake (first reaction, $INTAKE_AT)
Held for placement instead of reaching $POOL_TARGET: $HOLD_WHY. The operator's placement sitting places it under an epic or routes it on its own; gc-helm.sh unplaced lists it."
        WANT="v:pending"; WHAT="placement=pending"; NOW_PATH=".metadata.placement"
    elif [ "$ADMIT" = emergency ]; then
        set -- --priority 0 --append-notes "## Intake (first reaction, $INTAKE_AT)
Routed to $POOL_TARGET at P0 as an emergency: $ADMIT_WHY."
        WANT="v:0"; WHAT="priority P0"; NOW_PATH=".priority"
    else
        set --
    fi
    if [ $# -gt 0 ]; then
        gc_bd update "$BEAD" "$@" >/dev/null 2>&1 \
            || die "could not write $WHAT on $BEAD (does it exist${DB:+ in $DB}?), so it was not released. Nothing else was written by this step; clear the cause and re-run this command."
        if [ "$(subject_now "$NOW_PATH")" != "$WANT" ]; then
            if [ "$ADMIT" = emergency ]; then
                gc_bd update "$BEAD" --priority 0 >/dev/null 2>&1 || true
            else
                gc_bd update "$BEAD" --set-metadata "placement=pending" >/dev/null 2>&1 || true
            fi
            _got="$(subject_now "$NOW_PATH")"
            [ "$_got" = "$WANT" ] \
                || die "$WHAT did not land on $BEAD (it read back as '$_got', want '$WANT'; a 'u:' means the subject could not be read, which is not proof it landed). The release is withheld, so $BEAD is not left unrouted without its marker or routed at the wrong priority. Clear the cause and re-run this command."
        fi
        note "intake wrote $WHAT on $BEAD"
    fi
fi

# ── The act ──────────────────────────────────────────────────────────
# gc-helm.sh takeaway carries the headline, the release, and the wait edges;
# --route releases the bead to a pool instead of back to the human, and
# --assign releases it to a named agent as its assignee.
#
# Each disposition also answers the headline's own question — is anything still
# waiting on this bead? An actionable one is not waiting on a bead: it is
# moving, and the pool its route names, or the agent it is assigned to, will
# take it. Held for placement, it is released with no route into the sitting's
# queue, which placement=pending names and gc-helm.sh unplaced lists. Either
# way --no-wait says so. A blocked one names its wait as an edge, and a
# --then-assign rides the same release, so the agent's hook offers the bead
# once the edge clears. A recommend or a ruling names its human gate as its
# wait, or the visit --visit named: the subject is waiting on a person, and
# that bead carries the wait, so --waiting-on records the blocks edge onto
# it. On a gate that edge is the one gc-helm.sh demand already wrote, and
# adding it again leaves it single. The release parks the subject and the edge
# holds it, so it is not offered again until the gate resolves or the visit
# closes, and the wait is a graph state doctor/check-wait-is-an-edge reads
# rather than prose it reports.
#
# A subject held for placement can carry the stamp a dead pour left
# (gc.execution_routed_to), which the queue reads as a live pour. The release
# clears it and fails when it survives on a held bead, so this exit stops before
# its landed proof rather than record a hold the sitting cannot see.
set -- takeaway "$BEAD" "$TAKEAWAY" --by "$BY" --release
case "$DISPOSITION" in
    actionable)
        if [ -n "$ASSIGN" ]; then set -- "$@" --assign "$ASSIGN" --no-wait
        elif [ -n "$ADMIT" ]; then set -- "$@" --route "$ROUTE" --no-wait
        else set -- "$@" --no-wait; fi ;;
    blocked)
        for w in $WAITING; do set -- "$@" --waiting-on "$w"; done
        if [ -n "$THEN_ASSIGN" ]; then set -- "$@" --assign "$THEN_ASSIGN"; fi ;;
    recommend|ruling) set -- "$@" --waiting-on "${GATE:-$VISIT}" ;;
esac
"$HELM" "$@" || die "gc-helm.sh takeaway failed on $BEAD; its message above names what landed and what did not. Clear the cause and re-run this command."

# The edge is the hold. gc-helm.sh warns on a rejected edge and keeps going,
# which is right for a headline but not for the exits that hold on one: a
# blocked disposition waits on its blocker, a recommend or a ruling on its gate
# or visit, and any whose edge never landed leaves the bead unheld with nothing
# to say so.
# A missing edge fails the whole exit before the landed proof is stamped, so the
# reaction stops rather than recording done over a bead that is recorded as
# waiting and is not held, and a re-run resumes it.
HOLD_WAITS=""
case "$DISPOSITION" in
    blocked)          HOLD_WAITS="$WAITING" ;;
    recommend|ruling) HOLD_WAITS="${GATE:-$VISIT}" ;;
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
        || die "the $DISPOSITION disposition on $BEAD did not land. Nothing holds it on:${MISSING}, so the bead is not held — it reads as parked on prose alone, the wait this exit recorded carried by no edge. The headline and the release stand — only the hold is missing, so wire the edge above by hand, or re-run this command: no landed proof was stamped, so a re-run resumes rather than refusing."
    # A requested arm is part of the write-back too. Held with no arm, the bead
    # waits on its edge with nothing to route it once the wait lifts, and a
    # closed R brings no re-offer to arm it later. So an arm that does not land
    # fails the exit the way a missing edge does, before the landed proof. The
    # release leaves the bead open, unassigned and unrouted, which is what the
    # arm needs, and the arm rewrites its own record, so a re-run arms cleanly.
    # A bead intake held for placement is armed by nothing: its dispatch is the
    # sitting's, once it places the bead.
    if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ] && [ -n "$ADMIT" ]; then
        # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
        if ARM_ERR=$("$DEFERRED" arm "$BEAD" --target "$THEN_ROUTE" --reason "first reaction: $REASON" $BD_DB_ARGS 2>&1 >/dev/null); then
            note "armed the dispatch to $THEN_ROUTE for when the wait lifts"
        else
            die "the blocked disposition on $BEAD did not land. The dispatch to $THEN_ROUTE for when its wait lifts was not armed (${ARM_ERR:-deferred-dispatch.sh arm exited non-zero and named no cause}), so nothing would route $BEAD once the wait lifts. The headline, the release and the hold stand. No landed proof was stamped and the reaction bead stays open, so clear the cause and re-run this command: a re-run resumes rather than refusing."
        fi
    fi
fi

stamp_landed
close_reaction
printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${TARGET:-no target}"
