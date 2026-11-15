#!/usr/bin/env bash
# first-reaction-dispose.sh — the disposition a first reaction ends in.
# A reaction reads a subject bead S once and takes one of the exits below, and
# this script performs it as the write-back to S. Each exit advances S and
# leaves it open; none of them closes it.
#
#   actionable  the bead is work -> release it TO a pool, which is the whole
#               of "schedule an action for a bead": a routed, unassigned,
#               open bead is what a pool's find-work offers. Work that is a
#               named agent's own (a town-repo edit is mechanik's) is handed
#               TO that agent instead (--assign), in the form it finds its
#               work in: gc sling routes it to the mechanik's hook, the
#               release assigns it to the refinery or the keeper, and the
#               exit nudges the agent when bd reports the bead ready.
#   recommend   the action is known but warrants the operator's trigger -> put
#               it to the operator as a human gate (as ruling does) AND stamp
#               gc.recommended_formula on the subject, so the board offers
#               Accept — which runs that mol at the subject — beside Discuss.
#               The bridge between actionable and ruling: the action is
#               determinable, but authority-gated or consequential enough to
#               confirm before it runs.
#   blocked     the bead is waiting -> each wait becomes a `blocks` edge onto a
#               bead in the SAME store (component-model I1). Optionally arm a
#               deferred dispatch, so the wait converts to work when it lifts,
#               or hand the bead to the named agent whose work it is, in the
#               form the agent finds its work in. The exit nudges the agent
#               when bd already reports the bead ready, as it does once the
#               wait has lifted, and otherwise Gas City nudges the agent when
#               the blocker closes.
#   close       there is nothing to do, now or once another bead lands -> hand
#               the bead to a validating-closer pool (mol-validate-close), which
#               re-checks the call and closes the bead or asks the operator. A
#               first reaction never closes a bead. When the bead's whole job
#               ends once another bead in the SAME store lands, such as the bead
#               that retires its code (--waiting-on), the bead waits on that
#               bead through a `blocks` edge and the closer is armed for when it
#               closes.
#   ruling      only the operator can answer, and the reaction has no action to
#               recommend -> a human gate on the subject, Discuss-only. A gate
#               that carries a determinable action is the recommend exit.
#
# Intake holds findings for placement (docs/steering.md). The actionable exit's
# pool route and the blocked exit's --then-route reach a pool only for a bead
# that may enter one: a member of an epic (it has a parent), PR-finishing work
# (it carries anchor_bead), or an emergency whose failing check --emergency
# names and main's own checks confirm, which is routed at P0. Any other bead is held
# with Gas City's hold:mayor label and left unrouted, for the operator's placement
# sitting (`gc beads list --label hold:mayor` lists it). A named agent's own work
# (--assign, --then-assign) is not pool work, so the rule does not read it. The
# po is no such agent: it takes no work by assignment, and both refuse it.
#
# ruling and recommend file a native human gate through human-gate.sh, under the
# key first-reaction, that blocks the subject: the subject waits for the
# operator until the gate is cleared. On a subject with open children the gate
# blocks the parent too, and its unstarted parts wait with it, because the
# ruling or recommendation decides how the whole bead proceeds.
#
# A first reaction is a run of formulas/mol-first-reaction.toml slung on S, and
# this script is the one call its react step makes to dispose S. The run is the
# reaction's lease: a worker that dies before it closes its step leaves the
# step to the next, whose first act is the check (tools/gc-proactive.sh sling
# <S> --check --run <root>). The check passes over the reaction's own run and
# over a first-reaction gate whose message names that run, and each exit orders
# its writes so that the write which dispatches, holds or gates S comes last.
# Until it lands the check passes, the card the run wrote names the run, and the
# worker re-runs the same exit, whose earlier writes repeat harmlessly. The gate
# a ruling or a recommend files names the run (--run), so a re-offered reaction
# finishes those writes too. No key on S records that an exit landed.
#
# Every exit reads S's status before its first write, and writes nothing to an
# S that is not open (exit 3). A close that lands after that read meets the
# release's compare-and-swap or gc sling's own refusal, at the writes they make.
# Callers: agents/proactive/prompt.template.md, operators by hand.
# Exit: 0 disposed · 2 usage, nothing written · 3 the subject is not open,
# nothing written · 4 runtime failure: the message names what landed, and a
# re-run of the same command resumes.
set -u

PROG="first-reaction-dispose"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$HERE/gc-helm.sh}"
HUMAN_GATE="${GC_HUMAN_GATE_TOOL:-$HERE/human-gate.sh}"
# The arm and the read of what holds the subject are gctk's, from the binary
# the city builds.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
PROACTIVE="${GC_PROACTIVE_TOOL:-$HERE/../../tools/gc-proactive.sh}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The one read of a bead's human gates, and the rule of which of them still hold
# it. Exposes the die this script reports through, and bd_open_human_gates,
# which reads through _bd_call.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh from $HERE" >&2; exit 4; }
DIE_STATUS=4
usage_die() { printf '%s: %s\n' "$PROG" "$*" >&2; usage; exit 2; }
note() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
    cat >&2 <<'EOF'
Usage:
  first-reaction-dispose.sh <bead> --disposition actionable --reason "<why>" --takeaway "<headline>"
                            [--route <rig>/<agent> [--emergency <check>] | --assign <named-agent>]
  first-reaction-dispose.sh <bead> --disposition recommend --reason "<why>" --takeaway "<recommendation; why discuss>"
                            --recommended-formula <mol>
  first-reaction-dispose.sh <bead> --disposition blocked --reason "<why>" --takeaway "<headline>"
                            (--waiting-on <bead-id> | --blocker "<title>")...
                            [--then-route <rig>/<agent> [--emergency <check>] | --then-assign <named-agent>]
  first-reaction-dispose.sh <bead> --disposition close --reason "<why nothing to do>" --takeaway "<headline>"
                            [--route <rig>/<agent>] [--waiting-on <bead-id>]...
  first-reaction-dispose.sh <bead> --disposition ruling --reason "<why>" --takeaway "<headline>"
  common: [--run <root>] [--by <who>] [--db <path>] [--dry-run]

  --reason is required on every exit: a disposition nobody can second-guess is
  a silent classification. It lands on the bead beside the choice.
  --takeaway is the board headline (≤140 chars, enforced by gc-helm.sh).
  --run is the root of the reaction's run, the root_bead_id its claim of the
  react step returned. The gate a ruling or a recommend files names it, so the
  check a re-offered reaction runs first (tools/gc-proactive.sh sling <bead>
  --check --run <root>) passes over the gate this run filed, and the exit's
  writes finish. A call by hand names no run, and its gate names none.
  The subject's status is read before the first write, and a subject that is
  not open takes none: the exit writes nothing and exits 3.
  --route (actionable, close) defaults to ${GC_RIG}/gc-toolkit.polecat, and
  fails closed when the target cannot be rig-qualified. On close it is the
  validating-closer pool that runs mol-validate-close, which re-checks the
  no-work conclusion and closes the bead or asks the operator.
  --waiting-on (close, one or more) names a bead in the subject's store whose
  landing ends the subject's job, such as the bead that retires its code. The
  closer is then DEFERRED: the bead waits on each through a `blocks` edge, and
  a deferred dispatch is armed, so the deferred-dispatch order slings
  mol-validate-close once they have all closed, and the closer checks that
  their landing did end the job. Before its first write the exit reads what
  holds the subject and each bead it names (gctk bead holds). A bead the
  subject's store does not hold, such as one in another store, is refused,
  because an edge onto it holds nothing: a person closes the subject once that
  bead lands instead (--disposition ruling asks them). A subject with a wait
  edge into another store takes no write either, since gctk bead arm refuses
  to arm it.
  --waiting-on (blocked) names a bead the subject waits on. --blocker files
  the bead the subject is waiting on, when the wait is not a bead yet, and the
  same create writes the subject's wait on it. A pending wait of the subject's
  with that title, as gctk bead holds lists it, is reused instead, so a re-run
  waits on the bead an earlier run filed, wherever that run stopped.
  Before its first write the blocked exit reads what holds the subject
  (gctk bead holds), and a subject with a wait edge into another store, which
  holds nothing, takes no write. The same read names each --waiting-on, and
  a bead the subject's store does not hold, such as one in another store, is
  refused before anything is written, because its edge would hold nothing.
  --then-route arms the deferred dispatch that slings the subject when the
  blocker closes (gctk bead arm). An arm that does not land fails the exit,
  and a re-run resumes it.
  Intake decides whether the actionable route and the --then-route arm are
  written at all. Only a member of an epic, PR-finishing work (anchor_bead)
  or a confirmed emergency reaches a pool. Any other bead is held with Gas
  City's hold:mayor label (gc bd set-state <id> hold=mayor) and left
  unrouted, with no arm, for the operator's placement sitting. The hold is the
  exit's last write.
  --emergency <check> (actionable, or blocked with --then-route) claims the
  bead is a red main or a broken gate, and names the check on main whose
  failure it is about: a check run's name or a commit status's context. The
  claim is checked, not taken: on the head of the default branch of the
  subject's repository, that check must be failing (gh). Another check failing
  there confirms nothing. A confirmed emergency is routed, or armed, at P0. An
  unconfirmed one is held for placement like any other bead, and its note says
  what the check found.
  --assign (actionable) hands the bead to a named agent instead of a pool, in
  the form the agent finds its work in (docs/authority-map.md, Route work).
  The mechanik claims through its hook, so the release leaves the bead
  unassigned and gc sling <agent> <bead> --no-formula --no-convoy routes it to
  the agent's own name. The refinery and the keeper list the beads assigned to
  them, so the release writes the agent as the assignee. Either way the exit
  then reads whether bd reports the bead ready, and when it does, gc session
  nudge gives the agent a turn for it. A town-repo edit
  (city.toml, packs.lock) is mechanik's, so it takes --assign
  gc-toolkit.mechanik. Refused for the deacon and the witness, which patrol
  their own wisps and take what they must act on as mail, for any other agent
  the row does not name, for the po, which takes no work by assignment (its
  queue is the new work intake holds with hold:mayor), and for an agent that
  is not a registered named session whose hook reads this bead's store
  (tools/gc-proactive.sh assignable).
  --then-assign (blocked) hands the held bead to a named agent in the same
  form, held to the same tests as --assign, and reads its readiness the same
  way. A blocker that has closed already leaves the bead ready, so the exit
  nudges the agent. While the blocker holds, the exit sends no nudge, and Gas
  City nudges the agent when the blocker closes.
  ruling and recommend put the subject to the operator as a native human gate:
  the script files it with human-gate.sh under the key first-reaction, the
  takeaway as its title, and the gate blocks the subject. Its message names
  the run that filed it and, on a recommend, the recommended formula. One open
  gate stands per subject and key, so a re-run of the same exit finds the gate
  it filed rather than filing a second. An open first-reaction gate whose
  brief, its title and its description, is not the one this exit would file
  is withdrawn first, so the one open gate always asks this exit's question.
  Each exit clears a recommendation already on the subject before it files its
  gate, and recommend stamps its own only once the gate is filed, so no
  recommendation is older than the newest first-reaction gate.
  --recommended-formula (recommend only, required) names the execution mol the
  recommendation runs; it stamps gc.recommended_formula on the subject, which
  with the first-reaction gate is what offers the operator Accept on the board.
  A ruling carries no recommended action and rejects it.

  Exit: 0 disposed · 2 usage, nothing written · 3 the subject is not open,
  nothing written · 4 runtime failure: the message names what landed, and a
  re-run of the same command resumes.
EOF
}

BEAD=""; DISPOSITION=""; REASON=""; TAKEAWAY=""; BY="proactive"
ROUTE=""; THEN_ROUTE=""; BLOCKER_TITLE=""
ASSIGN=""; THEN_ASSIGN=""; EMERGENCY=""; EMERGENCY_SET=""
DB=""; DRY=""; RECOMMENDED_FORMULA=""; RUN=""; RUN_SET=""
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
        --run)      shift; [ $# -gt 0 ] || usage_die "--run needs the root of the reaction's run"; RUN="$1"; RUN_SET=1; shift ;;
        --run=*)    RUN="${1#--run=}"; RUN_SET=1; shift ;;
        --route)    shift; [ $# -gt 0 ] || usage_die "--route needs a <rig>/<agent> target"; ROUTE="$1"; shift ;;
        --route=*)  ROUTE="${1#--route=}"; shift ;;
        --then-route)   shift; [ $# -gt 0 ] || usage_die "--then-route needs a <rig>/<agent> target"; THEN_ROUTE="$1"; shift ;;
        --then-route=*) THEN_ROUTE="${1#--then-route=}"; shift ;;
        --assign)   shift; [ $# -gt 0 ] || usage_die "--assign needs a named-agent identity"; ASSIGN="$1"; shift ;;
        --assign=*) ASSIGN="${1#--assign=}"; shift ;;
        --then-assign)   shift; [ $# -gt 0 ] || usage_die "--then-assign needs a named-agent identity"; THEN_ASSIGN="$1"; shift ;;
        --then-assign=*) THEN_ASSIGN="${1#--then-assign=}"; shift ;;
        --emergency)   shift; case "${1:--}" in -*) usage_die "--emergency needs the name of the check that fails on main" ;; esac
                       EMERGENCY="$1"; EMERGENCY_SET=1; shift ;;
        --emergency=*) EMERGENCY="${1#--emergency=}"; EMERGENCY_SET=1; shift ;;
        --waiting-on)   shift; [ $# -gt 0 ] || usage_die "--waiting-on needs a bead id"; WAITING="$WAITING $1"; shift ;;
        --waiting-on=*) WAITING="$WAITING ${1#--waiting-on=}"; shift ;;
        --blocker)   shift; [ $# -gt 0 ] || usage_die "--blocker needs a title"; BLOCKER_TITLE="$1"; shift ;;
        --blocker=*) BLOCKER_TITLE="${1#--blocker=}"; shift ;;
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
    actionable|recommend|blocked|close|ruling) : ;;
    "") usage_die "needs --disposition actionable|recommend|blocked|close|ruling" ;;
    *)  usage_die "unknown disposition '$DISPOSITION' (actionable|recommend|blocked|close|ruling)" ;;
esac
[ -n "$REASON" ]   || usage_die "--reason is required: the record of WHY this disposition was chosen is what makes a wrong call visible"
[ -n "$TAKEAWAY" ] || usage_die "--takeaway is required: it is the board headline the operator reads"
# The check finds the run's own gate by the run's id among the words of the
# gate's message, so the id is one word of those characters.
if [ -n "$RUN_SET" ]; then
    case "$RUN" in
        ""|*[!A-Za-z0-9._-]*) usage_die "--run needs the root of the reaction's run, one bead id of [A-Za-z0-9._-] (got '$RUN')" ;;
    esac
    [ "$RUN" != "$BEAD" ] || usage_die "--run $RUN is the subject itself; the run is the reaction poured on $BEAD, so pass the root_bead_id the claim of its react step returned"
fi
# An emergency is confirmed only by the check it names, so a claim that names
# none is refused rather than read as no claim.
if [ -n "$EMERGENCY_SET" ]; then
    case "$EMERGENCY" in
        *[![:space:]]*) : ;;
        *) usage_die "--emergency needs the name of the check that fails on main: a check run's name or a commit status's context" ;;
    esac
fi

case "$DISPOSITION" in
    actionable)
        [ -z "$WAITING$BLOCKER_TITLE$THEN_ROUTE$THEN_ASSIGN$RECOMMENDED_FORMULA" ] \
            || usage_die "actionable takes --route or --assign only (--waiting-on/--blocker/--then-route/--then-assign/--recommended-formula belong to the other exits)"
        # A bead goes to one place: a pool, or the named agent whose work it is.
        # Both are routes, so the one gc.routed_to carries either, never both.
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
        # --waiting-on names the beads whose landing ends the subject's job: the
        # subject waits on them, and the closer is deferred until they close.
        [ -z "$BLOCKER_TITLE$THEN_ROUTE$ASSIGN$THEN_ASSIGN$RECOMMENDED_FORMULA$EMERGENCY" ] \
            || usage_die "close takes --route and --waiting-on only (--blocker/--then-route/--assign/--then-assign/--recommended-formula/--emergency belong to the other exits)"
        [ -n "$ROUTE" ] || ROUTE="${GC_RIG:+$GC_RIG/}gc-toolkit.polecat"
        case "$ROUTE" in
            */*) : ;;
            *) usage_die "cannot rig-qualify the closer target '$ROUTE': set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody." ;;
        esac
        for w in $WAITING; do
            [ "$w" != "$BEAD" ] || usage_die "--waiting-on $w is the bead itself"
        done
        # A close that waits reads what holds the subject and its waits before
        # its first write, and arms through the same binary, so with no tool it
        # cannot land and does not start.
        if [ -n "$WAITING" ]; then
            [ -x "$GCTK" ] \
                || die "a deferred close reads what holds $BEAD and each bead it waits on through gctk bead holds before it writes, and arms the validating closer through gctk bead arm, and there is no gctk binary at '$GCTK' (GCTK_BIN names one, or GC_CITY_PATH the city whose build it is). Nothing was written. Restore it and re-run this command."
        fi
        ;;
    blocked)
        [ -z "$ROUTE$ASSIGN$RECOMMENDED_FORMULA" ] || usage_die "blocked takes --waiting-on/--blocker/--then-route/--then-assign (--route/--assign/--recommended-formula belong to the other exits)"
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
        done
        if [ -n "$THEN_ROUTE" ]; then
            case "$THEN_ROUTE" in */*) : ;; *) usage_die "--then-route '$THEN_ROUTE' is not rig-qualified (<rig>/<agent>)" ;; esac
        else
            [ -z "$EMERGENCY" ] \
                || usage_die "--emergency admits the dispatch a --then-route arms, at P0, and this blocked exit arms none. Pass --then-route <rig>/<agent>, or drop --emergency."
        fi
        # The exit reads what holds the subject before its first write, and
        # arms through the same binary, so with no tool it cannot land and does
        # not start.
        [ -x "$GCTK" ] \
            || die "the blocked exit reads what holds $BEAD through gctk bead holds before it writes, and arms through gctk bead arm, and there is no gctk binary at '$GCTK' (GCTK_BIN names one, or GC_CITY_PATH the city whose build it is). Nothing was written. Restore it and re-run this command."
        ;;
    recommend|ruling)
        # Both put the subject to the operator and hold it there on the human
        # gate this script files, which blocks it. They differ only in whether
        # a recommended action rides along. recommend REQUIRES
        # --recommended-formula (it is the disposition that stamps the key the
        # board's Accept reads); ruling REJECTS it (the operator's judgment
        # names no worker-runnable action, so the gate is Discuss-only).
        [ -z "$ROUTE$ASSIGN$WAITING$BLOCKER_TITLE$THEN_ROUTE$THEN_ASSIGN$EMERGENCY" ] \
            || usage_die "$DISPOSITION takes --recommended-formula on recommend and nothing else; --route/--assign/--waiting-on/--blocker/--then-route/--then-assign/--emergency belong to the other exits"
        # In codepoints, as gc-helm.sh takeaway checks it.
        tlen=$(printf '%s' "$TAKEAWAY" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//' | jq -Rsr 'length' 2>/dev/null || true)
        case "$tlen" in ''|*[!0-9]*) tlen=${#TAKEAWAY} ;; esac
        [ "$tlen" -le 140 ] \
            || usage_die "--takeaway is $tlen characters; the cap is 140, because it is the gate's title and the board headline. Nothing was written."
        if [ "$DISPOSITION" = recommend ]; then
            [ -n "$RECOMMENDED_FORMULA" ] \
                || usage_die "recommend needs --recommended-formula <mol>: it is the action the operator Accepts. A gate with no recommended action is --disposition ruling."
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

# ── The po takes no work by assignment ───────────────────────────────
# Its queue is the new work intake holds with hold:mayor, which it places, and a
# bead handed to it as its own work is the dumping ground that queue keeps it
# from becoming. So neither --assign nor --then-assign may name it, bare or
# qualified.
for _who in "$ASSIGN" "$THEN_ASSIGN"; do
    [ -n "$_who" ] || continue
    case "${_who##*/}" in
        po|*.po)
            _flag=--assign; _route=--route
            [ "$_who" = "$THEN_ASSIGN" ] && [ -n "$THEN_ASSIGN" ] && { _flag=--then-assign; _route=--then-route; }
            usage_die "$_flag $_who names the po, which takes no work by assignment: its queue is the new work intake holds with hold:mayor. Pass $_route for the pool that would build $BEAD, and intake holds it for placement when no epic holds it, or pass $_flag for the named agent whose work it is." ;;
    esac
done

# ── The form a named agent takes its work in ─────────────────────────
# docs/authority-map.md's Route work row: a route reaches a named agent that
# claims its work through its hook, as the mechanik does. The refinery and the
# keeper list the beads assigned to them, which a route never reaches, so each
# takes the assignee, which the release writes. The deacon and the witness
# patrol their own wisps and take no bead, and an agent the row does not name
# has no form this exit knows, so each is refused here, before anything is read
# or written.
WHO="${ASSIGN:-$THEN_ASSIGN}"; HANDOFF=""
if [ -n "$WHO" ]; then
    _flag=--assign; [ -z "$THEN_ASSIGN" ] || _flag=--then-assign
    case "${WHO##*/}" in
        mechanik|*.mechanik) HANDOFF=route ;;
        refinery|*.refinery|keeper|*.keeper) HANDOFF=assignee ;;
        deacon|*.deacon|witness|*.witness)
            usage_die "$_flag $WHO names an agent that patrols its own wisps and takes no bead, so a bead handed to it is read by nobody. Send it what it must act on as mail (gc mail send $WHO -s \"<what it must do>\" -m \"<the bead, and what to do about it>\"), and dispose $BEAD another way." ;;
        *)  usage_die "$_flag $WHO names no agent this exit can hand a bead to. The mechanik takes a route, and the refinery and the keeper take the assignee (docs/authority-map.md, Route work), so pass $_flag with one of their qualified names, or route the bead to a pool." ;;
    esac
fi

# ── Pin the store, do not let the cwd choose it ──────────────────────
# This runs from a pool worktree, where .beads is gitignored, so an unpinned
# up-walk overshoots to whatever ledger it finds first. Two of the writes
# below cannot survive that: a blocker filed into another store makes the
# hold a cross-store edge, which reports success and holds nothing. Resolve
# the subject's own rig by its id prefix, the way the board's write verbs do.
if [ -z "$DB" ]; then
    _rigs="$("$HERE/rig-map.sh" || printf '')"
    if [ -n "$_rigs" ]; then
        _path="$(printf '%s' "$_rigs" \
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
_bd_call() { gc_bd "$@"; }

# ── Read the subject once; the guards below all ask it ───────────────
# The store is pinned, so this reads the subject's own rig. Its status, its
# membership and the stale-recommendation clear all key off it, and one read
# keeps them from disagreeing. bd answers an id as an exact-or-prefix match, so
# only a first row whose id is the subject's answers. A read that does not
# answer leaves its status unknown, and an exit writes only to an open subject,
# so it writes nothing.
SUBJECT_JSON=$(gc_bd show "$BEAD" --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || printf '')
SUBJECT_STATUS=$(printf '%s' "$SUBJECT_JSON" | jq -r --arg b "$BEAD" '
    if type == "array" and length > 0 and ((.[0].id // "") | tostring) == $b
    then ((.[0].status // "open") | tostring | ascii_downcase) else empty end' 2>/dev/null || printf '')
[ -n "$SUBJECT_STATUS" ] \
    || die "could not read $BEAD${DB:+ in $DB}: the store does not hold it, holds it only as a prefix of another id, or did not answer. An exit writes only to an open subject, so nothing was written. Re-run this command once the store answers."
if [ "$SUBJECT_STATUS" != open ]; then
    note "$BEAD is $SUBJECT_STATUS, and an exit writes only to an open subject, so nothing was written and there is nothing for this reaction to dispose."
    exit 3
fi
subject_meta() {
    printf '%s' "$SUBJECT_JSON" \
        | jq -r --arg k "$1" 'if type == "array" then ((.[0].metadata // {})[$k] // "") else "" end' 2>/dev/null || printf ''
}

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
# A bead the rule does not admit is held for placement: it carries hold:mayor and
# is left unrouted, with no arm, until the operator's placement sitting places it
# under an epic or routes it on its own.
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

# main_red <check> — is <check> failing on the default branch of the subject's
# repository right now? <check> is the name of a check run or the context of a
# commit status. Failing is a check run on the head that concluded failure,
# timed_out or startup_failure, or a commit status of failure or error. A run
# that is still going, or one cancelled by a newer push, is not failing. Only
# the named check confirms: another check failing on main says nothing about
# this bead, so it confirms nothing, and the note names it. Sets MAIN_RED_WHY to
# the evidence either way and returns 0 failing, 1 not failing, 2 unknown.
# Unknown covers a checkout, an origin or a GitHub answer that could not be
# read, and it confirms nothing, so a check that cannot run leaves the claim
# unconfirmed. A gate broken in a way main's own checks do not show cannot be
# confirmed here either.
#
# Every GitHub read is bounded (gh_bounded), so a stalled connection cannot hold
# the reaction, and its pool slot, with its step leased; a read that runs out
# of time is unknown. The check runs and the commit statuses are read across
# all their pages, so a failure past the first page still confirms.
MAIN_RED_WHY=""
GH_TIMEOUT="${GC_FIRST_REACTION_GH_TIMEOUT:-20}"
case "$GH_TIMEOUT" in ''|*[!0-9]*) GH_TIMEOUT=20 ;; esac
if command -v timeout >/dev/null 2>&1; then GH_TIMEOUT_BIN=timeout
elif command -v gtimeout >/dev/null 2>&1; then GH_TIMEOUT_BIN=gtimeout
else GH_TIMEOUT_BIN=""
fi
gh_bounded() {
    if [ -n "$GH_TIMEOUT_BIN" ] && [ "$GH_TIMEOUT" -gt 0 ]; then
        "$GH_TIMEOUT_BIN" "$GH_TIMEOUT" gh "$@" </dev/null
    else
        gh "$@" </dev/null
    fi
}
# gh_unanswered <what> <rc> — MAIN_RED_WHY for a GitHub read that failed.
gh_unanswered() {
    if [ "$2" -eq 124 ]; then
        MAIN_RED_WHY="GitHub did not answer for $1 within ${GH_TIMEOUT}s"
    else
        MAIN_RED_WHY="GitHub did not answer for $1 (gh exit $2)"
    fi
}
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
    _rc=0; _repo=$(gh_bounded api "repos/$_slug" 2>/dev/null) || _rc=$?
    [ "$_rc" -eq 0 ] || { gh_unanswered "the default branch of $_slug" "$_rc"; return 2; }
    _branch=$(printf '%s' "$_repo" | scrub | jq -r 'if type == "object" then (.default_branch // "") else "" end' 2>/dev/null || printf '')
    [ -n "$_branch" ] \
        || { MAIN_RED_WHY="GitHub did not name the default branch of $_slug"; return 2; }
    # --paginate prints one JSON object per page; jq -s merges their arrays. A
    # read that stopped partway is never merged, because its exit is checked
    # first.
    _rc=0; _runs=$(gh_bounded api "repos/$_slug/commits/$_branch/check-runs?per_page=100" --paginate 2>/dev/null) || _rc=$?
    [ "$_rc" -eq 0 ] || { gh_unanswered "the check runs on $_branch of $_slug" "$_rc"; return 2; }
    _rc=0; _status=$(gh_bounded api "repos/$_slug/commits/$_branch/status?per_page=100" --paginate 2>/dev/null) || _rc=$?
    [ "$_rc" -eq 0 ] || { gh_unanswered "the commit statuses on $_branch of $_slug" "$_rc"; return 2; }
    _runs=$(printf '%s' "$_runs" | scrub | jq -cs '
        if length > 0 and all(.[]; type == "object" and (.check_runs | type) == "array")
        then {check_runs: [.[].check_runs[]]} else null end' 2>/dev/null)
    _status=$(printf '%s' "$_status" | scrub | jq -cs '
        if length > 0 and all(.[]; type == "object" and (.statuses | type) == "array")
        then {sha: .[0].sha, statuses: [.[].statuses[]]} else null end' 2>/dev/null)
    _shape=$(jq -rn --argjson r "${_runs:-null}" --argjson s "${_status:-null}" '
        if (($r | type) == "object" and ($r.check_runs | type) == "array"
            and ($s | type) == "object" and ($s.statuses | type) == "array") then "ok" else "unknown" end' 2>/dev/null || printf 'unknown')
    [ "$_shape" = ok ] \
        || { MAIN_RED_WHY="GitHub did not answer for the checks on $_branch of $_slug"; return 2; }
    _sha=$(jq -rn --argjson r "$_runs" --argjson s "$_status" \
        '($s.sha // $r.check_runs[0].head_sha // "") | tostring | .[0:12]' 2>/dev/null || printf '')
    _head="$_branch of $_slug${_sha:+ at $_sha}"
    # One line, three fields: whether the head carries a check by the claimed
    # name (1 or 0), that check's failing entries, and every other failing one.
    _verdict=$(jq -rn --argjson r "$_runs" --argjson s "$_status" --arg c "$1" '
        def shown: "\(.name) (\(.state))" | gsub("[[:cntrl:]]"; " ");
        [ ($r.check_runs[] | {name: ((.name // "") | tostring), state: ((.conclusion // "") | tostring),
                              red: (.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure")}),
          ($s.statuses[] | {name: ((.context // "") | tostring), state: ((.state // "") | tostring),
                            red: (.state == "failure" or .state == "error")}) ] as $all
        | [ (if ($all | any(.name == $c)) then "1" else "0" end),
            ($all | map(select(.red and .name == $c) | shown) | unique | join(", ")),
            ($all | map(select(.red and .name != $c) | shown) | unique | join(", ")) ]
        | join("\u001f")' 2>/dev/null) \
        || { MAIN_RED_WHY="the checks on $_head could not be read"; return 2; }
    IFS=$(printf '\037') read -r _present _named _others <<EOF
$_verdict
EOF
    if [ -n "$_named" ]; then
        MAIN_RED_WHY="$_head is red: $_named"
        return 0
    fi
    if [ "$_present" = 1 ]; then
        MAIN_RED_WHY="$1 is not failing on $_head"
    else
        MAIN_RED_WHY="$_head has no check named $1"
    fi
    [ -z "$_others" ] || MAIN_RED_WHY="$MAIN_RED_WHY; other checks failing there: $_others"
    return 1
}

ADMIT=""         # member | pr-finishing | emergency; empty holds the bead for placement
ADMIT_WHY=""; HOLD_WHY=""
if [ -n "$POOL_TARGET" ]; then
    if [ -n "$EMERGENCY" ]; then
        if main_red "$EMERGENCY"; then
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
# bead's store — is worse than a human gate: the bead is open, unassigned and offered
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
# A hand-off is held to the same standard: --assign and --then-assign name a
# named agent whose own hook must offer the bead, and gc-proactive.sh
# `assignable` answers that against the roster, the named sessions and the
# stores the agent's hook reads, answering no only on a positive finding.
if [ -n "$WHO" ] && [ -x "$PROACTIVE" ]; then
    ASSIGNABLE_WHY="$("$PROACTIVE" assignable "$WHO" "$BEAD" 2>/dev/null)" || {
        usage_die "$WHO cannot be handed this bead — ${ASSIGNABLE_WHY:-the agent answered no}. Handing it there would leave $BEAD offered to nobody. Name the agent by its exact qualified name (gc-toolkit.mechanik for a town-repo edit), or route a pool with --route/--then-route."
    }
fi
# --then-route names the pool the deferred dispatch slings the bead to once its
# blocker lifts, so it is held to the SAME roster and store test as --route. Its
# own check at parse time only tests for a "/", which a copied `<rig>/<agent>`
# placeholder passes; a target the roster does not know, or one whose rig does
# not own this bead's store, would arm a dispatch every pass of the
# deferred-dispatch order replays into a failure. The probe answers no only on a positive finding, so an
# unrunnable probe leaves the arm alone. An arm intake holds for placement is
# never written, so it is not asked about either.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ] && [ -n "$ADMIT" ] && [ -x "$PROACTIVE" ]; then
    DELIVERABLE_WHY="$("$PROACTIVE" deliverable "$THEN_ROUTE" "$BEAD" 2>/dev/null)" || {
        usage_die "--then-route $THEN_ROUTE cannot pick this bead up — ${DELIVERABLE_WHY:-the pool answered no}. Arming it would record a dispatch the deferred-dispatch order replays into a failure every cycle. Pass a pool that runs (e.g. <rig>/<rig>.polecat), or omit --then-route if no pool takes this bead."
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
# enters a pool, and the route-deliverability guards, because they catch a
# disposition that cannot land.

if [ -n "$DRY" ]; then
    printf 'disposition=%s bead=%s reason=%s\n' "$DISPOSITION" "$BEAD" "$REASON"
    case "$DISPOSITION" in
        actionable) if [ "$HANDOFF" = assignee ]; then
                        printf 'would release %s to named agent %s as its assignee and nudge it if bd reports the bead ready\n' "$BEAD" "$ASSIGN"
                    elif [ -n "$ASSIGN" ]; then
                        printf 'would hand %s to named agent %s (gc sling %s %s --no-formula --no-convoy) and nudge it if bd reports the bead ready\n' "$BEAD" "$ASSIGN" "$ASSIGN" "$BEAD"
                    elif [ -z "$ADMIT" ]; then
                        printf 'would hold %s for placement (hold:mayor, unrouted): %s\n' "$BEAD" "$HOLD_WHY"
                    elif [ "$ADMIT" = emergency ]; then
                        printf 'would release %s to %s at P0: %s\n' "$BEAD" "$ROUTE" "$ADMIT_WHY"
                    else
                        printf 'would release %s to %s\n' "$BEAD" "$ROUTE"
                    fi ;;
        recommend)  printf 'would file a human gate on %s recommending %s and hold %s on it\n' "$BEAD" "$RECOMMENDED_FORMULA" "$BEAD" ;;
        blocked)    printf 'would wait %s on:%s%s\n' "$BEAD" "$WAITING" "${BLOCKER_TITLE:+ (new: $BLOCKER_TITLE)}"
                    if [ "$HANDOFF" = assignee ]; then
                        printf 'would release %s to named agent %s as its assignee and nudge it if bd reports the bead ready; while the wait holds, Gas City nudges it when the blocker closes\n' "$BEAD" "$THEN_ASSIGN"
                    elif [ -n "$THEN_ASSIGN" ]; then
                        printf 'would hand %s to named agent %s (gc sling %s %s --no-formula --no-convoy) and nudge it if bd reports the bead ready; while the wait holds, Gas City nudges it when the blocker closes\n' "$BEAD" "$THEN_ASSIGN" "$THEN_ASSIGN" "$BEAD"
                    fi
                    if [ -n "$THEN_ROUTE" ] && [ -z "$ADMIT" ]; then
                        printf 'would hold %s for placement (hold:mayor) and arm no dispatch to %s: %s\n' "$BEAD" "$THEN_ROUTE" "$HOLD_WHY"
                    elif [ -n "$THEN_ROUTE" ]; then
                        _p0=""; [ "$ADMIT" = emergency ] && _p0=" at P0"
                        printf 'would arm a dispatch to %s%s for when the wait lifts\n' "$THEN_ROUTE" "$_p0"
                    fi ;;
        close)      if [ -n "$WAITING" ]; then
                        printf 'would wait %s on:%s, then arm a deferred dispatch to validating closer %s (mol-validate-close) for when the wait lifts\n' "$BEAD" "$WAITING" "$ROUTE"
                    else
                        printf 'would sling %s to validating closer %s (mol-validate-close)\n' "$BEAD" "$ROUTE"
                    fi ;;
        ruling)     printf 'would file a human gate on %s and hold %s on it\n' "$BEAD" "$BEAD" ;;
    esac
    exit 0
fi

# ── What holds the subject and its waits, read before the first write ──
# The waits are read, never computed: gctk bead holds lists the subject's own
# pending waits and its wait edges into another store (foreign), which hold
# nothing, since bd keeps an edge onto a bead its store does not hold and the
# edge holds nothing. The blocked exit and a close that waits each write wait
# edges, so each reads it before its first write. The read names each
# --waiting-on beside the subject and answers a bead the subject's store does
# not hold, such as one in another store, with an error line. An edge onto that
# bead would hold nothing, so the call is refused as malformed. A subject that
# carries a foreign edge would read as waiting while nothing holds it, and
# gctk bead arm refuses it, so the exit refuses it and names the edge. A read
# that does not answer for the subject leaves all of this unknown, so nothing
# is written.
HOLDS_LINE=""
if [ "$DISPOSITION" = "blocked" ] || { [ "$DISPOSITION" = "close" ] && [ -n "$WAITING" ]; }; then
    # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields, and $WAITING to bead ids
    HOLDS_ALL=$("$GCTK" bead holds $BD_DB_ARGS "$BEAD" $WAITING </dev/null 2>/dev/null | scrub \
        | jq -sc '[ .[] | select(type == "object") ]' 2>/dev/null)
    HOLDS_LINE=$(printf '%s' "$HOLDS_ALL" | jq -c --arg b "$BEAD" '.[]? | select(.id == $b and (has("error") | not)
                                       and (.pending | type) == "array" and (.foreign | type) == "array")' 2>/dev/null | head -n 1)
    [ -n "$HOLDS_LINE" ] \
        || die "could not read what holds $BEAD (gctk bead holds did not answer for it), so whether it carries a wait edge into another store, and whether its store holds each bead it would wait on, is unknown and nothing was written. Re-run this command once the store answers."
    for w in $WAITING; do
        _wline=$(printf '%s' "$HOLDS_ALL" | jq -c --arg w "$w" '[ .[]? | select(.id == $w) ] | .[0] // empty' 2>/dev/null)
        [ -n "$_wline" ] \
            || die "could not read whether $BEAD's store holds $w (gctk bead holds gave no line for it), so nothing was written. Re-run this command once the store answers."
        _werr=$(printf '%s' "$_wline" | jq -r '.error // ""' 2>/dev/null)
        [ -n "$_werr" ] || continue
        [ "$DISPOSITION" != "close" ] \
            || usage_die "--waiting-on $w is not a bead $BEAD's store holds ($_werr), so an edge onto it would hold nothing and could not hold $BEAD until $w lands. Nothing was written. When $w is a bead in another store, a person closes $BEAD once it lands instead: put that to the operator with --disposition ruling."
        usage_die "--waiting-on $w is not a bead $BEAD's store holds ($_werr), so an edge onto it would hold nothing. Nothing was written. When $w is a bead in another store, wait on a bead in ${BEAD%%-*}'s store that names it instead, which --blocker \"<title>\" files."
    done
    _foreign=$(printf '%s' "$HOLDS_LINE" | jq -r '[ .foreign[]? | "\(.id) (\(.type // "blocks"))" ] | join(", ")' 2>/dev/null || printf '')
    if [ -n "$_foreign" ]; then
        _first=$(printf '%s' "$HOLDS_LINE" | jq -r '.foreign[0].id // ""' 2>/dev/null || printf '')
        die "$BEAD carries a wait edge into another store ($_foreign), which holds nothing, so it would read as waiting on that bead while nothing holds it. Nothing was written. Remove the edge (gc bd dep remove $BEAD $_first${DB:+ --db $DB}), wait on a bead in ${BEAD%%-*}'s store that names it instead, and re-run this command."
    fi
fi

# ── The blocked exit's missing bead: reuse it, or file it once ────────
# The blocker is filed with the subject's wait on it in the same create
# (--deps blocks:<subject>, which bd writes with the bead in one transaction),
# so a blocker this exit filed is always one of the subject's pending waits,
# however the exit stops after it. A pending wait of the subject's whose title
# is the blocker's is therefore the bead an earlier run of this exit filed, and
# the exit waits on it again rather than filing a second. A create whose reply
# was lost is found the same way, because the create lands whole or not at all.
# The check a re-offered reaction runs first refuses a human gate, not a wait
# on a bead like this one, so a reaction cut off after the create still passes
# it and finishes the exit.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$BLOCKER_TITLE" ]; then
    EXISTING=$(printf '%s' "$HOLDS_LINE" | jq -r --arg t "$BLOCKER_TITLE" \
        '[ .pending[]? | select(((.type // "") == "blocks") and ((.title // "") == $t)) | .id ] | .[0] // ""' 2>/dev/null || printf '')
    if [ -n "$EXISTING" ]; then
        note "the wait '$BLOCKER_TITLE' is already $BEAD's pending wait $EXISTING; waiting on that one"
        WAITING="$WAITING $EXISTING"
    else
        NEW=$(gc_bd create -t task --title "$BLOCKER_TITLE" --deps "blocks:$BEAD" \
            -d "Filed by a first reaction on $BEAD, which is waiting on it.

$REASON" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].id // "") else (.id // "") end' 2>/dev/null || printf '')
        [ -n "$NEW" ] && [ "$NEW" != "null" ] \
            || die "bd named no blocker bead for '$BLOCKER_TITLE'. It files the bead and $BEAD's wait on it in one write, so either both landed or neither did, and nothing else was written to $BEAD. Re-run this command: it waits on a blocker that landed, as one of $BEAD's pending waits, and files one that did not."
        note "filed the wait as $NEW"
        WAITING="$WAITING $NEW"
    fi
fi

# What the disposition names, for the line this script prints. A ruling or
# recommend names its gate once the gate exists, below.
TARGET=""
case "$DISPOSITION" in
    actionable) TARGET="${ASSIGN:-$ROUTE}" ;;
    blocked)    TARGET="$(printf '%s' "${WAITING# }" | tr -s ' ' ',')" ;;
    close)      TARGET="$ROUTE"
                [ -z "$WAITING" ] || TARGET="$TARGET once $(printf '%s' "${WAITING# }" | tr -s ' ' ',') closes" ;;
esac
if [ -n "$POOL_TARGET" ]; then
    case "$DISPOSITION:$ADMIT" in
        blocked:)          TARGET="$TARGET; held for placement" ;;
        actionable:)       TARGET="held for placement" ;;
        blocked:emergency) TARGET="$TARGET; armed at P0" ;;
        *:emergency)       TARGET="$TARGET at P0" ;;
    esac
fi

# ── The recommendation must be true when it is read ─────────────────
# gc.recommended_formula is read as a NON-EMPTY value by every reader — the
# board's Accept derivation (services/helm/internal/board/derive.go tests
# `rf != ""`), gc-helm.sh accept, and converse-invalidate-recommendation.sh — so
# a present-but-empty key is no live recommendation, and the clear below tests
# it the same non-empty way. A key that did not move is invisible until the
# operator meets the wrong affordance: a set that did not land leaves a
# recommendation gate that offers only Discuss, and a clear that did not land
# leaves a superseded Accept executable. So reco_ensure stops the exit when the
# store refuses the write, because the release, the arm and the close after it
# cannot be undone.
reco_ensure() { # <formula, or empty to clear> <what has already landed, for the failure>
    local want="$1" landed="$2"
    if [ -n "$want" ]; then
        gc_bd update "$BEAD" --set-metadata "gc.recommended_formula=$want" >/dev/null 2>&1 \
            || die "the store refused gc.recommended_formula=$want on $BEAD. $landed The operator's Accept reads this key, so the exit stops here rather than leave a recommendation gate that offers only Discuss. Clear the cause and re-run this command."
        return 0
    fi
    gc_bd update "$BEAD" --unset-metadata "gc.recommended_formula" >/dev/null 2>&1 \
        || die "the store refused the clear of the earlier recommendation on $BEAD. $landed A disposition must not leave a superseded Accept executable, so the exit stops here. Clear the cause and re-run this command."
}

# ── A recommendation already on the subject is cleared, before the act ─────
# The subject states the current recommendation and never a superseded one the
# operator could still Accept. No recommendation older than the newest
# first-reaction gate is how Accept finds the recommendation's gate once the gate
# is closed, and an exit that stops part way never leaves its gate beside an
# older recommendation, which Accept would sling in place of the one the gate
# asks about.
if [ -n "$(subject_meta gc.recommended_formula)" ]; then
    reco_ensure "" "Nothing else was written."
fi

# ── A named agent is handed the bead ─────────────────────────────────
# --assign and --then-assign name an agent by the identity gc-proactive.sh
# assignable checked above, and the hand-off takes the form HANDOFF chose for
# it. The mechanik takes Gas City's own route: gc sling routes the bead to the
# agent's name, and a named session's hook serves work routed to its own name
# once bd reports it ready. The sling pours no formula and, as gc-helm.sh
# takeaway --route does, files no convoy. The refinery and the keeper take the
# assignee, which the release above wrote, so nothing more is written for them.
# A route or an assignee alone gives a running agent no turn, so the exit nudges
# the agent with the bead's id when bd reports the bead ready; a nudge to an
# agent that is not running wakes it. Whether the bead is ready is read after
# the hand-off lands, for either exit, and never taken from the exit's name. A
# blocked exit's blocker can close before the hand-off is written, even while
# the reaction is prepared, and its close then found no route or assignee to
# nudge. A bead the read finds still waiting has a blocker that closes after the
# hand-off, and Gas City nudges the route or the assignee then
# (docs/deferred-dispatch.md). The read is bd's ready set, the answer the work
# skill gives for a ready bead. A hand-off that does not land, the read and the
# nudge included, fails the exit, as a missing arm does, so a re-run resumes it.
hand_over() { # <named-agent>
    local out rc=0 rig_arg="" how=assigned what=assignee ready="" why
    if [ "$HANDOFF" = route ]; then
        how=routed; what=route
        [ -n "${GC_RIG:-}" ] && rig_arg="--rig $GC_RIG"
        # shellcheck disable=SC2086  # $rig_arg expands to 0 or 2 space-free fields
        out=$(gc sling $rig_arg "$1" "$BEAD" --no-formula --no-convoy 2>&1 </dev/null) || rc=$?
        if [ "$rc" -ne 0 ]; then
            die "the $DISPOSITION disposition on $BEAD did not land. gc sling did not hand it to $1 (exit $rc: $(printf '%s' "${out:-it named no cause}" | tr '\n' ' ')), so the agent's hook does not offer it. The headline and the release stand, so clear the cause and re-run this command: a re-run resumes rather than refusing."
        fi
    fi
    # Unreadable is not waiting: only a listing that answers an array decides.
    out=$(gc_bd ready --brief --json --limit 0 2>/dev/null </dev/null) || rc=$?
    [ "$rc" -ne 0 ] || ready=$(printf '%s' "$out" | scrub | jq -r --arg b "$BEAD" '
        if type == "array" then (if any(.[]; (.id // "") == $b) then "ready" else "waits" end) else empty end' 2>/dev/null) || ready=""
    case "$ready" in
        waits) ;;
        ready)
            out=$(gc session nudge "$1" "$BEAD is $how to you and ready" 2>&1 </dev/null) || rc=$?
            if [ "$rc" -ne 0 ]; then
                die "the $DISPOSITION disposition on $BEAD did not land. It is $how to $1, but gc session nudge did not reach the agent (exit $rc: $(printf '%s' "${out:-it named no cause}" | tr '\n' ' ')), so a running agent gets no turn for it. The headline, the release and the $what stand, so clear the cause and re-run this command: a re-run resumes rather than refusing."
            fi ;;
        *)
            why="answered no list"
            [ "$rc" -eq 0 ] || why="exited $rc"
            die "the $DISPOSITION disposition on $BEAD did not land. It is $how to $1, but whether bd reports it ready could not be read (gc bd ready $why), so whether the agent is owed a nudge now is unknown. The headline, the release and the $what stand, so clear the cause and re-run this command: a re-run resumes rather than refusing." ;;
    esac
    note "handed $BEAD to $1"
}

# ── The close exit: hand the bead to a validating closer, never close here ────
# The reaction concluded there is nothing to do. first-reaction never closes a
# bead — a cheap model must not have the last word on a close — so the bead is
# handed to a capable pool running mol-validate-close, which re-checks the
# conclusion against live state and closes the bead only when it agrees,
# asking the operator or re-routing when it does not. mol-validate-close reads
# its subject as its input convoy's single tracked member, so the bead is claimed
# there as the workflow's member, not via a raw pool route — a raw route runs
# mol-polecat-work, which never closes a bead.
#
# --waiting-on names the beads whose landing ends the bead's job, such as the
# bead that retires its code. Its close is owed once they land, and the closer
# checks that their landing did end the job, so that sling is DEFERRED: the bead
# is held on each of them and a deferred dispatch is armed, and the
# deferred-dispatch order slings mol-validate-close once they have all closed and
# bd reports the bead ready. With no --waiting-on the closer is slung now.
#
# The closer validates a claim, so the claim travels with the bead: --reason
# (why there is no work, and the counter-case for keeping the bead open) is
# appended to the subject's notes as its close brief, beside the reaction's
# card, before anything can dispatch the closer that reads it. A brief written
# for a bead that waits names the beads it is held on. The board headline is
# written next, before the closer is dispatched, so a closer that runs at once
# finds it and a dispatch that fails leaves it for the re-run to write again.
if [ "$DISPOSITION" = "close" ]; then
    HELD_ON=""
    [ -z "$WAITING" ] || HELD_ON="held on $(printf '%s' "${WAITING# }" | tr -s ' ' ','), "
    gc_bd update "$BEAD" --append-notes "## Close brief (first reaction, ${HELD_ON}$(date -u +%Y-%m-%dT%H:%M:%SZ))
$REASON" >/dev/null 2>&1 \
        || die "could not append the close brief to $BEAD's notes; the validating closer reads it there, so nothing was dispatched. Clear the cause and re-run this command."
    "$HELM" takeaway "$BEAD" "$TAKEAWAY" --by "$BY" >/dev/null 2>&1 \
        || die "the close brief is on $BEAD, but its board headline did not land (gc-helm.sh takeaway failed), so no closer was dispatched. Clear the cause and re-run this command."
    if [ -n "$WAITING" ]; then
        # Gate the deferred dispatch: hold the bead on what it waits for so
        # the deferred-dispatch order does not sling until that closes. The
        # hold is a REQUIRED write. The order dispatches by bd's readiness
        # (`bd ready`), so a bead left unheld reads ready and mol-validate-close
        # slings at once, before the landing it waits on. A hold that does not
        # land therefore fails closed: refuse to arm, and let the documented
        # re-run resume. bd keeps one edge type per pair of beads, so an edge of
        # another type onto the same bead refuses this one.
        for h in $WAITING; do
            gc_bd dep add "$BEAD" "$h" -t blocks >/dev/null 2>&1 \
                || die "could not hold $BEAD on $h; refusing to arm the closer dispatch ungated (the deferred-dispatch order would sling mol-validate-close before $h closes). bd keeps one edge type per pair of beads, so an edge of another type $BEAD already has onto $h refuses this one: remove it with gc bd dep remove $BEAD $h${DB:+ --db $DB}. Clear the cause and re-run this command."
        done
        # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
        ARM_ERR=$("$GCTK" bead arm "$BEAD" --target "$ROUTE" --on mol-validate-close --reason "first reaction close: $REASON" $BD_DB_ARGS 2>&1 >/dev/null) \
            || die "the close brief, the headline and the holds stand on $BEAD, but the validating closer was not armed (${ARM_ERR:-gctk bead arm exited non-zero and named no cause}). A wait onto a bead another store holds is an edge that holds nothing, and the arm refuses a bead that carries one: remove it (gc bd dep remove $BEAD <that bead>${DB:+ --db $DB}) and put $BEAD's close to the operator with --disposition ruling. Otherwise clear the cause and re-run this command."
    else
        SLING_RIG_ARG=""
        [ -n "${GC_RIG:-}" ] && SLING_RIG_ARG="--rig $GC_RIG"
        # shellcheck disable=SC2086  # $SLING_RIG_ARG expands to 0 or 2 space-free fields
        SLING_OUT=$(gc sling $SLING_RIG_ARG "$ROUTE" "$BEAD" --on mol-validate-close 2>&1 </dev/null)
        sling_rc=$?
        if [ "$sling_rc" -eq 3 ]; then
            # gc sling exits 3 only when a live run of the same formula already
            # works the bead: a validating closer drives it already, such as the
            # one an earlier run of this exit slung before its worker was cut
            # off, so the bead has its closer.
            note "a validating closer already drives $BEAD, so no second is slung: $(printf '%s' "${SLING_OUT:-gc sling named no run}" | tr '\n' ' ')"
        elif [ "$sling_rc" -ne 0 ]; then
            die "could not sling $BEAD to the validating closer $ROUTE (gc sling --on mol-validate-close exited $sling_rc: $(printf '%s' "${SLING_OUT:-it named no cause}" | tr '\n' ' ')). The close brief and the headline stand. Clear the cause and re-run this command."
        fi
    fi
    printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${TARGET:-no target}"
    exit 0
fi

# ── The ruling and recommend exits' human gate ───────────────────────
# The gate's title is the takeaway with its whitespace collapsed onto one line,
# as gc-helm.sh takeaway stores it, so the gate says the sentence the board shows
# on the subject. The helper titles a gate with its message's first line, cut
# to fit bd, and makes the whole message its description. The message names the
# run that filed it, which the check a re-offered reaction runs passes over,
# and the formula a recommend recommends, so the brief changes whenever the
# action does. An open first-reaction gate asks this exit's question only when
# its whole brief is this exit's: its description is this message, and its
# title is the message's first line or the helper's cut of it. Any other open
# first-reaction gate asks a superseded reaction's question, so it is withdrawn
# first, and the gate filed after it carries this exit's.
GATE=""
if [ "$DISPOSITION" = "ruling" ] || [ "$DISPOSITION" = "recommend" ]; then
    [ -x "$HUMAN_GATE" ] \
        || die "human-gate.sh not found beside this script ($HUMAN_GATE); no gate was filed on $BEAD. Restore it and re-run this command."
    TITLE_WANT=$(printf '%s' "$TAKEAWAY" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
    GATE_RECO=""
    [ "$DISPOSITION" != recommend ] || GATE_RECO="
It recommends $RECOMMENDED_FORMULA, the formula Accept runs on $BEAD."
    GATE_MESSAGE="$TITLE_WANT
Filed by a first reaction on $BEAD ($DISPOSITION${RUN:+, run $RUN}), which waits on it.${GATE_RECO}

$REASON

The card in $BEAD's notes carries the evidence. Clearing this gate makes $BEAD ready."
    FR_GATES=$(bd_open_human_gates "$BEAD" first-reaction) \
        || die "could not read the human gates of $BEAD, so whether a first-reaction gate already asks is unknown; nothing was filed. Clear the cause and re-run this command."
    if printf '%s' "$FR_GATES" | jq -e --arg t "$TITLE_WANT" --arg m "$GATE_MESSAGE" '
        def this_title: . as $g | ($g | rtrimstr("…")) as $cut
            | $g == $t or (($g | endswith("…")) and $cut != "" and ($t | startswith($cut)));
        any(.[]; ((.description // "") | tostring) != $m or (((.title // "") | tostring) | this_title | not))' >/dev/null 2>&1; then
        "$HUMAN_GATE" --retract --subject "$BEAD" --key first-reaction \
            --message "superseded by a newer first reaction on $BEAD, which asks: $TITLE_WANT" >/dev/null \
            || die "could not withdraw the superseded first-reaction gate on $BEAD; nothing new was filed. Clear the cause and re-run this command."
    fi
    GATE=$("$HUMAN_GATE" --subject "$BEAD" --key first-reaction --message "$GATE_MESSAGE") \
        || die "could not file the human gate on $BEAD (human-gate.sh failed; its message above names why). Clear the cause and re-run this command."
    TARGET="$GATE"
    note "put $BEAD to the operator as the human gate $GATE"
    if [ "$DISPOSITION" = "recommend" ]; then
        reco_ensure "$RECOMMENDED_FORMULA" "The gate $GATE is filed."
    fi
fi

# ── An emergency's priority, before the act ──────────────────────────
# A confirmed emergency carries P0 before its route or its arm, so it is never
# claimable at the priority it was filed at, and its note rides the same write.
# The route after it cannot be undone, so a write the store refuses stops the
# exit before the act, and a re-run resumes.
INTAKE_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -n "$POOL_TARGET" ] && [ "$ADMIT" = emergency ]; then
    gc_bd update "$BEAD" --priority 0 --append-notes "## Intake (first reaction, $INTAKE_AT)
Routed to $POOL_TARGET at P0 as an emergency: $ADMIT_WHY." >/dev/null 2>&1 \
        || die "could not write priority P0 on $BEAD (does it exist${DB:+ in $DB}?), so it was not released. Nothing else was written by this step; clear the cause and re-run this command."
    note "intake wrote priority P0 on $BEAD"
fi

# ── The act ──────────────────────────────────────────────────────────
# gc-helm.sh takeaway carries the headline, the release, and the wait edges;
# --route releases the bead to a pool instead of back to the human. A bead for
# the refinery or the keeper is released to it as its assignee (--assign), and
# one for the mechanik is released at rest and routed after (hand_over, below).
# The release ends the runs beneath the bead but the one this session holds a
# step of, so the reaction's own run goes on to its step's close.
#
# Each disposition also answers the headline's own question — is anything still
# waiting on this bead? An actionable one is not waiting on a bead: it is
# moving, and the pool its route names, or the agent it is handed to, will
# take it. Held for placement, it is released with no route into the sitting's
# queue, which its hold:mayor label puts it in and
# `gc beads list --label hold:mayor` lists. Either way --no-wait says so. A
# blocked one names its wait as an edge, and a --then-assign hands the bead over
# in the same form, so the agent reads it once the edge clears. A blocker this
# exit filed carries that edge from its create, and adding it again leaves it
# single. A recommend
# or a ruling names its human gate as its wait: the subject is waiting on a
# person, and the gate carries the wait, so --waiting-on records the blocks edge
# onto it. That edge is the one the gate's create already wrote, and adding it
# again leaves it single. The release parks the subject and the edge holds it,
# so it is not offered again until the gate is cleared, and the wait is a graph
# state doctor/check-wait-is-an-edge reads rather than prose it reports.
set -- takeaway "$BEAD" "$TAKEAWAY" --by "$BY" --release
case "$DISPOSITION" in
    actionable)
        if [ -z "$ASSIGN" ] && [ -n "$ADMIT" ]; then set -- "$@" --route "$ROUTE" --no-wait
        elif [ "$HANDOFF" = assignee ]; then set -- "$@" --assign "$ASSIGN" --no-wait
        else set -- "$@" --no-wait; fi ;;
    blocked)
        for w in $WAITING; do set -- "$@" --waiting-on "$w"; done
        [ "$HANDOFF" != assignee ] || set -- "$@" --assign "$THEN_ASSIGN" ;;
    recommend|ruling) set -- "$@" --waiting-on "$GATE" ;;
esac
"$HELM" "$@" || die "gc-helm.sh takeaway failed on $BEAD; its message above names what landed and what did not. Clear the cause and re-run this command."

# The edge is the hold: a blocked disposition waits on its blocker, and a
# recommend or a ruling on its gate. takeaway exits non-zero when an edge it was
# asked for is refused, so the exit stops above, before any arm, hand-off or
# hold, rather than send on a bead recorded as waiting and not held, and a
# re-run resumes.
#
# A requested arm is part of the write-back too. Held with no arm, the bead
# waits on its edge with nothing to route it once the wait lifts. So an arm that
# does not land fails the exit the way a refused edge does. The release leaves
# the bead open, unassigned and unrouted, which is what the arm needs, and an
# arm already on the bead for the same target and formula writes nothing, so a
# re-run arms cleanly. A bead intake held for placement is armed by nothing: its
# dispatch is the sitting's, once it places the bead.
if [ "$DISPOSITION" = "blocked" ] && [ -n "$THEN_ROUTE" ] && [ -n "$ADMIT" ]; then
    # shellcheck disable=SC2086  # $BD_DB_ARGS expands to 0 or 2 space-free fields
    if ARM_ERR=$("$GCTK" bead arm "$BEAD" --target "$THEN_ROUTE" --reason "first reaction: $REASON" $BD_DB_ARGS 2>&1 >/dev/null); then
        note "armed the dispatch to $THEN_ROUTE for when the wait lifts"
    else
        die "the blocked disposition on $BEAD did not land. The dispatch to $THEN_ROUTE for when its wait lifts was not armed (${ARM_ERR:-gctk bead arm exited non-zero and named no cause}), so nothing would route $BEAD once the wait lifts. The headline, the release and the hold stand, so clear the cause and re-run this command: a re-run resumes rather than refusing."
    fi
fi

# --assign and --then-assign name the agent the released bead is handed to.
[ -z "$WHO" ] || hand_over "$WHO"

# ── Intake's hold, the exit's last write ─────────────────────────────
# A bead intake does not admit carries hold:mayor, which puts it in the
# placement sitting's queue and keeps every pool's claim off it. The hold is
# Gas City's, written with gc bd set-state, which records the reason in an event
# bead and sets the label in one write. It is the exit's last write, after the
# release and after the note that says what intake found and names the queue's
# read, because the check a re-offered reaction runs first refuses a held bead:
# a worker cut off before the hold lands meets a subject the check passes, and
# re-runs this exit to the end.
if [ -n "$POOL_TARGET" ] && [ -z "$ADMIT" ]; then
    HOLD_REASON="Held for placement instead of reaching $POOL_TARGET: $HOLD_WHY."
    gc_bd update "$BEAD" --append-notes "## Intake (first reaction, $INTAKE_AT)
$HOLD_REASON The operator's placement sitting places it under an epic or routes it on its own; gc beads list --label hold:mayor lists it." >/dev/null 2>&1 \
        || die "the $DISPOSITION disposition on $BEAD did not land. The headline and the release stand, but intake's note saying why it holds $BEAD did not, so the hold:mayor label was not written. Clear the cause and re-run this command."
    gc_bd set-state "$BEAD" hold=mayor --reason "$HOLD_REASON" >/dev/null 2>&1 \
        || die "the $DISPOSITION disposition on $BEAD did not land. The headline, the release and intake's note stand, but the hold:mayor label did not (gc bd set-state $BEAD hold=mayor${DB:+ --db $DB}), so $BEAD rests open and unrouted outside the placement sitting's queue. Clear the cause and re-run this command."
    note "intake wrote the hold:mayor label on $BEAD"
fi

printf '%s: %s disposed as %s (%s)\n' "$PROG" "$BEAD" "$DISPOSITION" "${TARGET:-no target}"
