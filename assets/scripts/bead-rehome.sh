#!/usr/bin/env bash
# bead-rehome — the ONE writer that closes a bead with a successor pointer, for
# every actor. The pointer (gc.superseded_by + _store) is the only thing that
# distinguishes a sound disposition from a careless close where the question
# gets asked, so it is stamped and READ BACK before the close; this script would
# rather leave the origin OPEN than close it unpointed.
# The close is gated on EVIDENCE the script re-establishes itself:
#   (a) EVERY kind — origin is not a review, step, or workflow bead; origin is
#       not in_progress under another actor.
#   (b) the evidence kinds fixed-upstream|duplicate ALSO — they claim the
#       origin's work is already delivered elsewhere, so the successor resolves
#       in the SAME store and is closed or work_outcome=shipped, and the origin
#       did no work (gc.work_outcome=no-op, accepted even with a work-product
#       key a rebase/rework twin leaves behind, or no work_outcome and none of
#       branch/work_dir/gc.work_dir/pr_number/pr_url/merge_result/
#       gc.work_commit — so an origin with unlanded work is refused). An origin
#       carrying the operator's pre-recorded PR-close disposition for this kind
#       and successor (pr-dispose.sh) is a ruling already made, and (b) does not
#       re-judge it.
#   The judgment kinds re-homed|folded|not-needed are held to (a) only, and a
#   non-closed merge_result does not bar them, because the judgment is the
#   caller's. A hand disposition judges the bead itself, and an automated
#   caller proves its own case before it calls (docs/authority-map.md,
#   Close-with-successor).
# --check evaluates those gates for the given origin/successor/kind and exits
# 0 (eligible) or non-zero (refused, with the reason on stderr), writing
# nothing.
# Writes, in order: pointer on the origin (verified), a populated close reason
# (kind + successor + store), a best-effort back-pointer on the successor. The
# pointer goes on in one write bd applies only while the origin still has the
# status and assignee this run read before judging it. A caller that read the
# bead before another actor claimed, assigned or moved it therefore stamps
# nothing while that change stands, and exits 4, as it does for a pointer that
# does not stick. When the origin is a task_kind=visit it also gets
# gc.work_outcome=no-op, for the work-record gate the close runs, from
# work-outcome.sh: a write of its own that never gates the close and never
# replaces a work outcome the visit already records.
# An open human gate that blocks the origin holds its close (finalize-gate.sh).
# A caller that reports its own refusals of the close as human gates names their
# key with --except-key, and the retry withdraws those gates before it closes,
# in three steps: it reads what would hold the close (the finalize gate; the
# origin's live blockers and open children; and the template, the pin and the
# assignee an unforced `bd close` refuses, which lets the close through only for
# an origin no one is assigned or one assigned to exactly the actor it runs as),
# and stops there when anything but its own unassigned gates under the key
# would; it resolves each of those gates with a reason that names the retry and
# carries no outcome word, so no quiet period starts; then it closes.
# A run that stops between steps leaves a state the next run completes, because
# a resolved gate stays resolved.
# An already-closed origin is the REPAIR path: pointer + appended note, plus that
# work outcome when the visit lacks it, with the gates skipped (the close they
# would guard already happened).
# Once the origin reads back closed, on either path, the branch it names in
# metadata.branch is ended on the git remote through branch-end.sh, the way a
# merge ends a landed branch. That remote write never gates the disposition:
# when the branch cannot be ended the close stands, and a warning names the
# branch and the command that ends it. The bead's notes record the outcome.
# Also drops an origin->successor `blocks` wait edge on the way: `bd close`
# refuses a blocked issue, and a disposed bead is not waiting on its successor.
# Reads the legacy bare `superseded_by` key as evidence of a prior disposition;
# writes only the canonical gc.-prefixed pair.
# Callers: converse dispositions, operator re-homes, duplicate-sweep.sh,
# pr-facts.sh (a PR closed with a pre-recorded disposition, and that branch's
# parked rework children), scaffolding-sweep.sh (a finding a disposed PR leaves
# unanswered, closed onto the bug that carries it), deferred-dispatch.sh
# (folded, onto the `until` target that closed last, for an open, unassigned
# bead whose `until` targets have all closed, whose `until` edge to that target
# still stands, that no open `blocks` blocker of its own holds, and that carries
# no live work as live-work.sh defines it, checked on its listing and again on
# a fresh read just before the call. It claims the bead before that read and
# runs this script as the claim, its holder, so no other caller's stamp lands
# on the bead while it holds the claim. It removes the pointer itself:
# reopening the bead when its read after the close finds something that landed
# on the bead or its edges while it held the bead, and giving the bead back
# when this script stamped the pointer and did not close the bead).
# Doctrine: docs/state-machine.md "Disposition". Test: bead-rehome.test.sh.
set -euo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BEAD_STORE="${GC_BEAD_STORE_TOOL:-$HERE/bead-store.sh}"
# The composable "may this bead be finalized?" precondition set. An open human
# gate that blocks the origin holds its close, the same precondition merge.sh
# applies to a merge (docs/finalize-gate.md). Overridable for a test.
FINALIZE_GATE="${GC_FINALIZE_GATE_TOOL:-$HERE/finalize-gate.sh}"
# Ends the retired branch on the git remote once the close reads back.
# Overridable for a test.
BRANCH_END="${GC_BRANCH_END_TOOL:-$HERE/branch-end.sh}"
# The one gc.work_outcome stamp a visit gets before it closes, shared with every
# other visit closer. Exposes work_outcome_noop.
# shellcheck source=work-outcome.sh
. "$HERE/work-outcome.sh" || { echo "bead-rehome: cannot source work-outcome.sh from $HERE" >&2; exit 1; }
# The rule of which human gates still hold a bead, $HUMAN_GATE_JQ, which the
# retry's withdrawal reads its own gates by. This script reads through bd_at, so
# it takes the rule and none of the library's store reads.
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$HERE/bd-lib.sh}" || { echo "bead-rehome: cannot source bd-lib.sh from $HERE" >&2; exit 1; }

ORIGIN=""; SUCCESSOR=""; KIND=""; NOTE=""
ORIGIN_STORE=""; SUCCESSOR_STORE=""; DRY_RUN=""; CHECK=""; EXCEPT_KEY=""

usage() {
    cat <<'U'
Usage:
  bead-rehome.sh --origin <bead-id> --successor <bead-id> \
                 --kind re-homed|folded|fixed-upstream|duplicate|not-needed \
                 [--note "<one sentence of why>"] \
                 [--origin-store rig:<name>] [--successor-store rig:<name>] \
                 [--except-key <situation-key>] [--check] [--dry-run]

Under every kind but not-needed the successor is the bead that carries the
work now. Under not-needed nothing carries it, and the successor is the
evidence that concluded the bead was unnecessary — typically the visit bead
from the sitting that ruled. It is required either way.

The close is refused unless the evidence holds (see the header): every kind
needs the origin to be a plain work bead no other session holds;
fixed-upstream and duplicate additionally need the successor closed or shipped
in the same store and the origin to have done no work, unless the origin
carries the operator's pre-recorded PR-close disposition for that kind and
successor.

--check evaluates that evidence and exits 0 (eligible) or non-zero (refused,
reason on stderr) without writing anything.

Stores are derived from each bead id's prefix via `gc rig list --json`;
pass --origin-store/--successor-store when a prefix is ambiguous.
An already-closed origin gains the pointer and an appended note (repair path),
with the evidence gates skipped.

An open human gate that blocks the origin holds the close (finalize-gate.sh).
--except-key is for the caller that reports its own refusals of this close as
human gates through human-gate.sh: it names the situation key that caller files
them under. A gate under that key that no person is assigned does not hold the
retry it asks for, and the retry resolves it just before the close, because an
open gate makes the close refuse the bead it blocks. A gate assigned to a
person still holds, and so does every gate under any other key, every other
live blocker and every open child: then nothing is resolved or closed.
U
    exit "${1:-1}"
}

die() { echo "bead-rehome: $1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --origin)           ORIGIN="${2:-}"; shift 2 ;;
        --successor)        SUCCESSOR="${2:-}"; shift 2 ;;
        --kind)             KIND="${2:-}"; shift 2 ;;
        --note)             NOTE="${2:-}"; shift 2 ;;
        --origin-store)     ORIGIN_STORE="${2:-}"; shift 2 ;;
        --successor-store)  SUCCESSOR_STORE="${2:-}"; shift 2 ;;
        --except-key)       EXCEPT_KEY="${2:-}"; shift 2 ;;
        --check)            CHECK=1; shift ;;
        --dry-run)          DRY_RUN=1; shift ;;
        -h|--help)          usage 0 ;;
        *)                  die "unknown argument '$1' (try --help)" 64 ;;
    esac
done

[ -n "$ORIGIN" ]    || die "--origin is required (try --help)" 64
[ -n "$SUCCESSOR" ] || die "--successor is required (try --help)" 64
[ -n "$KIND" ]      || die "--kind is required (try --help)" 64

# The kind shapes the close reason, so it is a closed set. All but one say the
# work RELOCATED and the successor carries it now; under not-needed nothing
# carries it and the successor is the evidence that concluded the bead was
# unnecessary. The pointer is required under both readings — an unpointed close
# is indistinguishable from a careless one whatever ended the bead.
case "$KIND" in
    re-homed|folded|fixed-upstream|duplicate|not-needed) ;;
    *) die "--kind must be one of re-homed|folded|fixed-upstream|duplicate|not-needed (got '$KIND')" 64 ;;
esac

[ "$ORIGIN" != "$SUCCESSOR" ] || die "--origin and --successor are the same bead ($ORIGIN)" 64

# Store refs are `rig:<name>`; reads go through `gc bd --db <path>/.beads`
# (the `--rig` form answers empty for the HQ store, `--db` does not).
RIGS_JSON=""
rigs_json() {
    [ -n "$RIGS_JSON" ] && { printf '%s' "$RIGS_JSON"; return 0; }
    RIGS_JSON=$("$HERE/rig-map.sh" || true)
    printf '%s' "$RIGS_JSON"
}

# Both resolvers end in `return 0`: under set -e a non-zero "no match" would
# abort before the die below can name the unresolvable store.
store_path() { # rig:<name> -> repo path, empty when unresolvable
    local ref="$1" name
    case "$ref" in
        rig:?*) name="${ref#rig:}" ;;
        *) return 0 ;;
    esac
    rigs_json | jq -r --arg n "$name" '.rigs[]? | select(.name == $n) | .path // empty' 2>/dev/null || true
    return 0
}

# The id-prefix derivation lives in bead-store.sh, so a stamped pointer and the
# destructive gates that read one place the same id in the same store.
store_for_bead() { # bead id -> rig:<name> via prefix; empty when unresolved
    local name
    name=$("$BEAD_STORE" "$1") || return 0
    [ -n "$name" ] && printf 'rig:%s' "$name"
    return 0
}

[ -n "$ORIGIN_STORE" ]    || ORIGIN_STORE=$(store_for_bead "$ORIGIN")
[ -n "$SUCCESSOR_STORE" ] || SUCCESSOR_STORE=$(store_for_bead "$SUCCESSOR")
[ -n "$ORIGIN_STORE" ] \
    || die "cannot derive the store for origin $ORIGIN from its id prefix; pass --origin-store rig:<name>" 2
[ -n "$SUCCESSOR_STORE" ] \
    || die "cannot derive the store for successor $SUCCESSOR from its id prefix; pass --successor-store rig:<name>" 2

ORIGIN_PATH=$(store_path "$ORIGIN_STORE")
SUCCESSOR_PATH=$(store_path "$SUCCESSOR_STORE")
[ -n "$ORIGIN_PATH" ]    || die "origin store '$ORIGIN_STORE' does not resolve to a rig (want rig:<name> from 'gc rig list')" 2
[ -n "$SUCCESSOR_PATH" ] || die "successor store '$SUCCESSOR_STORE' does not resolve to a rig (want rig:<name> from 'gc rig list')" 2

# The per-store events table is the only place close attribution exists, so
# the session identity is passed explicitly rather than left to bd's defaults.
ACTOR="${BEADS_ACTOR:-${GC_SESSION_NAME:-${GC_AGENT:-}}}"

bd_at() {
    local db="$1"; shift
    if [ -n "$ACTOR" ]; then
        gc bd --db "$db/.beads" --actor "$ACTOR" "$@"
    else
        gc bd --db "$db/.beads" "$@"
    fi
}

bead_json() {
    bd_at "$1" show "$2" --json 2>/dev/null | scrub || true
}

# The successor is checked first and hardest: a pointer to a bead that does
# not exist reads as a resolved disposition and resolves to nothing.
SUCC_JSON=$(bead_json "$SUCCESSOR_PATH" "$SUCCESSOR")
SUCC_ID=$(printf '%s' "$SUCC_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true)
[ -n "$SUCC_ID" ] \
    || die "successor $SUCCESSOR does not exist in $SUCCESSOR_STORE ($SUCCESSOR_PATH/.beads) — nothing stamped, origin $ORIGIN untouched" 3

ORIGIN_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
ORIGIN_ID=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true)
[ -n "$ORIGIN_ID" ] \
    || die "origin $ORIGIN does not exist in $ORIGIN_STORE ($ORIGIN_PATH/.beads) — nothing stamped" 3

ORIGIN_STATUS=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
# The status and assignee the gates below judge, as the store holds them. The
# stamp (step 1) is conditional on both.
JUDGED_STATUS=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].status // "") | tostring' 2>/dev/null || true)
JUDGED_ASSIGNEE=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].assignee // "") | tostring' 2>/dev/null || true)
# gc.superseded_by is a FLAT dotted key: bracket access, never .metadata.gc.x.
PRIOR_SUCC=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // .[0].metadata.superseded_by // empty' 2>/dev/null || true)
PRIOR_STORE=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // .[0].metadata.superseded_by_store // empty' 2>/dev/null || true)

# Does the origin carry a `blocks` edge naming the successor as its blocker?
# Unparseable answers 0: a probe that cannot read the graph must not claim an
# edge exists.
wait_edge_count() {
    local n
    n=$(printf '%s' "$1" | jq -r --arg s "$SUCCESSOR" \
        '[.[0].dependencies[]? | select((.id // "") == $s and ((.dependency_type // "") == "blocks"))] | length' \
        2>/dev/null || true)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    printf '%s' "$n"
}

# The branch a bead names in metadata.branch; empty when it names none or the
# answer does not parse.
origin_branch() {
    printf '%s' "$1" | jq -r '(.[0].metadata.branch // "") | tostring' 2>/dev/null || true
}

# A recorded disposition to a DIFFERENT successor is somebody else's decision.
if [ -n "$PRIOR_SUCC" ] && [ "$PRIOR_SUCC" != "$SUCCESSOR" ]; then
    die "origin $ORIGIN already records a successor pointer to $PRIOR_SUCC (${PRIOR_STORE:-store unrecorded}); refusing to overwrite another disposition — reconcile the two by hand" 6
fi

case "$KIND" in
    re-homed)       PHRASE="re-homed to" ;;
    folded)         PHRASE="folded into" ;;
    fixed-upstream) PHRASE="fixed upstream by" ;;
    duplicate)      PHRASE="duplicate of" ;;
    not-needed)     PHRASE="not needed, per" ;;
esac
REASON="$PHRASE $SUCCESSOR in $SUCCESSOR_STORE"
[ -n "$NOTE" ] && REASON="$REASON — $NOTE"

# ── The evidence, re-established here so no caller closes over work it cannot prove ──
# The gates guard the CLOSE, so they run only when the origin is still open; an
# already-closed origin is the repair path and its close, if any, already
# happened. --check runs them and exits without writing; the real path refuses.
ACTOR_IDS="$ACTOR
${GC_SESSION_NAME:-}
${GC_SESSION_ID:-}
${GC_AGENT:-}
${GC_ALIAS:-}"
is_self() { # $1 assignee -> 0 when it names this session, 1 otherwise
    local a="$1" id
    [ -n "$a" ] || return 1
    while IFS= read -r id; do
        [ -n "$id" ] && [ "$a" = "$id" ] && return 0
    done <<IDS
$ACTOR_IDS
IDS
    return 1
}

# ruled_disposition -> 0 when the origin carries the operator's pre-recorded
# PR-close disposition (pr-dispose.sh) naming this kind and this successor, and
# that successor's store when the record names one.
ruled_disposition() {
    local rk rs rss
    rk=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.pr_close_disposition_kind"] // ""' 2>/dev/null || true)
    rs=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.pr_close_disposition_successor"] // ""' 2>/dev/null || true)
    rss=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.pr_close_disposition_successor_store"] // ""' 2>/dev/null || true)
    [ -n "$rk" ] && [ "$rk" = "$KIND" ] && [ "$rs" = "$SUCCESSOR" ] || return 1
    [ -z "$rss" ] || [ "$rss" = "$SUCCESSOR_STORE" ]
}

GATE_REASON=""
gates_pass() { # 0 eligible, 1 refused (reason in $GATE_REASON)
    GATE_REASON=""
    local assignee task_kind step_ref kind_meta
    assignee=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].assignee // ""' 2>/dev/null || true)
    task_kind=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["task_kind"] // ""' 2>/dev/null || true)
    step_ref=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.step_ref"] // .[0].metadata["gc.step_id"] // ""' 2>/dev/null || true)
    kind_meta=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.kind"] // ""' 2>/dev/null || true)

    # (a) A review, step, or workflow bead is closed by its own machinery, never
    # here: signoff.sh/review-sweep close reviews, and a step or workflow root is
    # topology, not the work.
    [ "$task_kind" != "review" ] || { GATE_REASON="$ORIGIN is a review bead (task_kind=review); signoff.sh and review-sweep close those"; return 1; }
    if [ -n "$step_ref" ] || [ "$kind_meta" = "workflow" ]; then
        GATE_REASON="$ORIGIN is a step bead or workflow root, not a work bead"; return 1
    fi
    # (a) Not held by another session right now. In_progress under this session
    # is fine: a worker re-homing the bead it holds is the holder.
    if [ "$ORIGIN_STATUS" = "in_progress" ] && [ -n "$assignee" ] && ! is_self "$assignee"; then
        GATE_REASON="$ORIGIN is in_progress under $assignee, who is judging it"; return 1
    fi

    # (b) The evidence kinds assert a specific claim — this bead's work is
    # already delivered elsewhere — so they carry the burden of proving it.
    # The judgment kinds (re-homed, folded, not-needed) carry the caller's
    # judgment, which this script does not re-judge, so a non-closed
    # merge_result does not bar them: the converse retire path disposes an
    # in-flight anchor through here on the operator's ruling. An origin
    # carrying the operator's pre-recorded PR-close disposition for this kind
    # and successor (pr-dispose.sh) is that ruling already made, read from the
    # store rather than taken from the caller, so (b) does not re-judge it. An
    # automated caller passes a judgment kind only on its own proof:
    # deferred-dispatch.sh passes folded only for a bead its `until` targets
    # resolved, and never for one carrying live work, which a merge_result is.
    if ruled_disposition; then
        return 0
    fi
    case "$KIND" in
        fixed-upstream|duplicate)
            [ "$SUCCESSOR_STORE" = "$ORIGIN_STORE" ] \
                || { GATE_REASON="a $KIND close needs the successor $SUCCESSOR in the same store as $ORIGIN ($ORIGIN_STORE); it is $SUCCESSOR_STORE. Judge a cross-store successor by hand"; return 1; }
            local sstatus soutcome
            sstatus=$(printf '%s' "$SUCC_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
            soutcome=$(printf '%s' "$SUCC_JSON" | jq -r '.[0].metadata["gc.work_outcome"] // .[0].metadata["work_outcome"] // ""' 2>/dev/null || true)
            if [ "$sstatus" != "closed" ] && [ "$soutcome" != "shipped" ]; then
                GATE_REASON="a $KIND close needs the successor $SUCCESSOR closed or work_outcome=shipped; it is ${sstatus:-unreadable} and has not shipped"; return 1
            fi
            # Origin did no work, proved positively. work_outcome=no-op is the
            # explicit statement and is accepted even beside a work-product key,
            # because a rebase/rework twin's branch names the TWIN, not a push
            # this bead made. Absent an outcome, no work-product key may be set.
            local ooutcome workkeys
            ooutcome=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.work_outcome"] // .[0].metadata["work_outcome"] // ""' 2>/dev/null || true)
            if [ "$ooutcome" = "no-op" ]; then
                :
            elif [ -z "$ooutcome" ]; then
                workkeys=$(printf '%s' "$ORIGIN_JSON" | jq -r '
                    (.[0].metadata // {}) as $m
                    | ["branch","work_dir","gc.work_dir","pr_number","pr_url","merge_result","gc.work_commit"]
                    | map(select((($m[.]) // "") | tostring | . != "")) | length' 2>/dev/null || printf '1')
                case "$workkeys" in
                    0) : ;;
                    *) GATE_REASON="a $KIND close needs $ORIGIN to have done no work: it records no work_outcome but carries work-product metadata (branch/work_dir/pr/merge_result). Stamp gc.work_outcome=no-op if it truly pushed nothing"; return 1 ;;
                esac
            else
                GATE_REASON="a $KIND close needs $ORIGIN to record no work: work_outcome=$ooutcome is not a no-op"; return 1
            fi
            ;;
    esac
    return 0
}

if [ "$ORIGIN_STATUS" != "closed" ]; then
    if ! gates_pass; then
        if [ -n "$CHECK" ]; then
            echo "bead-rehome: --check refused: $GATE_REASON" >&2
            exit 1
        fi
        die "$GATE_REASON — nothing stamped, $ORIGIN untouched" 7
    fi
fi
if [ -n "$CHECK" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        echo "bead-rehome: --check: $ORIGIN is already closed — the repair path adds the pointer only, no close is gated"
    else
        printf 'bead-rehome: --check: %s is eligible to close as "%s"\n' "$ORIGIN" "$REASON"
    fi
    exit 0
fi

# A visit's close runs the work-record gate, so step 1a stamps its work outcome.
ORIGIN_KIND=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["task_kind"] // empty' 2>/dev/null || true)
PRIOR_WORK_OUTCOME=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.work_outcome"] // empty' 2>/dev/null || true)

if [ -n "$DRY_RUN" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        CLOSE_PLAN="already closed — pointer + note only, close reason left as-is"
    else
        CLOSE_PLAN="$REASON"
    fi
    STAMP_PLAN="gc.superseded_by=$SUCCESSOR gc.superseded_by_store=$SUCCESSOR_STORE"
    [ "$ORIGIN_KIND" = "visit" ] && [ -z "$PRIOR_WORK_OUTCOME" ] && STAMP_PLAN="$STAMP_PLAN gc.work_outcome=no-op"
    if [ "$(wait_edge_count "$ORIGIN_JSON")" -gt 0 ]; then
        EDGE_PLAN="drop the 'blocked by $SUCCESSOR' wait edge (it would refuse this close)"
    else
        EDGE_PLAN="none ($ORIGIN carries no wait edge to $SUCCESSOR)"
    fi
    PLAN_BRANCH=$(origin_branch "$ORIGIN_JSON")
    if [ -n "$PLAN_BRANCH" ]; then
        PLAN_CMD=$(printf '%q ' "$BRANCH_END" --rig "${ORIGIN_STORE#rig:}" --branch "$PLAN_BRANCH" --bead "$ORIGIN" --dry-run)
        BRANCH_PLAN="end $PLAN_BRANCH on the git remote of $ORIGIN_STORE once the close reads back, unless a live owner names it (${PLAN_CMD% } previews it)"
    else
        BRANCH_PLAN="none ($ORIGIN names no metadata.branch)"
    fi
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        GATE_PLAN="none (the close already happened)"
    elif [ -n "$EXCEPT_KEY" ]; then
        GATE_PLAN="resolve each open human gate under [$EXCEPT_KEY] that blocks $ORIGIN and no person is assigned, just before the close, once nothing else would hold it"
    else
        GATE_PLAN="none (no --except-key)"
    fi
    printf 'bead-rehome (dry run)\n  origin:    %s [%s] in %s\n  successor: %s in %s\n  stamp:     %s\n  edge:      %s\n  gates:     %s\n  close:     %s\n  branch:    %s\n  actor:     %s\n' \
        "$ORIGIN" "${ORIGIN_STATUS:-unknown}" "$ORIGIN_STORE" \
        "$SUCCESSOR" "$SUCCESSOR_STORE" "$STAMP_PLAN" \
        "$EDGE_PLAN" "$GATE_PLAN" "$CLOSE_PLAN" "$BRANCH_PLAN" "${ACTOR:-<bd default>}"
    exit 0
fi

# 1. Stamp the pointer and prove it landed: the close below is gated on the
# read-back, not on an exit status. Both keys go in one update, which bd applies
# only while the origin still has the status and assignee the gates above
# judged. bd holds a claimed bead
# against another actor's assignment and close, never against a metadata write,
# so without that condition a caller whose gates passed before another actor
# claimed the bead would point it under that claim. With it, a claim, an
# assignment or a status change that lands after the gates' read makes bd write
# nothing (exit 13), and the caller stamps nothing: while a bead is claimed,
# only a caller the gates accept as its holder can point it. The stamp still
# lands on a bead this actor cannot close under, because bd's close guard holds
# only the close.
STAMP_META=(--set-metadata gc.superseded_by="$SUCCESSOR" \
            --set-metadata gc.superseded_by_store="$SUCCESSOR_STORE")
JUDGED=(--if-status="$JUDGED_STATUS" --if-assignee="$JUDGED_ASSIGNEE")
STAMP_RC=0
bd_at "$ORIGIN_PATH" update "$ORIGIN" "${JUDGED[@]}" "${STAMP_META[@]}" >/dev/null 2>&1 || STAMP_RC=$?
if [ "$STAMP_RC" = 13 ]; then
    if [ -n "$JUDGED_ASSIGNEE" ]; then JUDGED_HOLDER="under $JUDGED_ASSIGNEE"; else JUDGED_HOLDER="and unassigned"; fi
    die "$ORIGIN is no longer $JUDGED_STATUS $JUDGED_HOLDER, as this run read it before judging it: a claim, an assignment or a status change landed since, so nothing is stamped and $ORIGIN is not closed. Re-run to judge it as it stands now" 4
fi

CHECK_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
GOT_SUCC=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // empty' 2>/dev/null || true)
GOT_STORE=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // empty' 2>/dev/null || true)
if [ "$GOT_SUCC" != "$SUCCESSOR" ] || [ "$GOT_STORE" != "$SUCCESSOR_STORE" ]; then
    die "successor pointer did NOT stick on $ORIGIN (read back gc.superseded_by='${GOT_SUCC:-}' gc.superseded_by_store='${GOT_STORE:-}'); NOT closing it — an unpointed close is the defect this script exists to prevent. The bead is still open and visible; re-run once the store accepts the write" 4
fi
# 1a. A visit's work outcome, for the work-record gate the close runs. It goes
# through work-outcome.sh as a write of its own, after the gated stamp above, so
# it never decides whether the visit closes. It runs on the repair path too,
# where it reaches a closed visit that lacks this key.
if [ "$ORIGIN_KIND" = "visit" ]; then
    work_outcome_noop "$ORIGIN" bd_at "$ORIGIN_PATH"
fi

# 1b. Drop ONLY the wait edge to THIS successor: it would refuse the close,
# and gc.superseded_by records the relationship more strongly. Any other
# blocker is a real hold whose refusal below is correct.
if [ "$(wait_edge_count "$CHECK_JSON")" -gt 0 ]; then
    bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 || true
    # `bd dep remove` reports success for an edge that never existed; read the
    # graph back instead.
    if [ "$(wait_edge_count "$(bead_json "$ORIGIN_PATH" "$ORIGIN")")" -gt 0 ]; then
        echo "bead-rehome: WARN could not drop the '$ORIGIN blocked by $SUCCESSOR' wait edge; while it stands the close below is refused — clear it with: gc bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR" >&2
    else
        printf 'bead-rehome: dropped the wait edge (%s blocked by %s) — a disposed bead is not waiting on its successor; gc.superseded_by is the record\n' \
            "$ORIGIN" "$SUCCESSOR"
    fi
fi

# 2. The prose carrier: `bd show` renders the close reason, not metadata, so
# the reason is what a human reads. On an already-closed origin the reason
# cannot be rewritten; append the disposition note instead (never --notes,
# which replaces).
if [ "$ORIGIN_STATUS" = "closed" ]; then
    PRIOR_NOTES=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].notes // ""' 2>/dev/null || true)
    case "$PRIOR_NOTES" in
        *"Disposition recorded"*"$SUCCESSOR"*)
            printf 'bead-rehome: %s already records this disposition (gc.superseded_by=%s in %s) — nothing to do\n' \
                "$ORIGIN" "$SUCCESSOR" "$SUCCESSOR_STORE" ;;
        *)
            bd_at "$ORIGIN_PATH" update "$ORIGIN" \
                --append-notes "Disposition recorded $(date -u +%Y-%m-%dT%H:%MZ): $REASON. (Pointer added after the close; the close reason above predates it.)" \
                >/dev/null 2>&1 \
                || echo "bead-rehome: WARN could not append the disposition note to $ORIGIN; the pointer metadata is recorded" >&2 ;;
    esac
    printf 'bead-rehome: %s was ALREADY closed in %s — pointer recorded (gc.superseded_by=%s in %s).\n' \
        "$ORIGIN" "$ORIGIN_STORE" "$SUCCESSOR" "$SUCCESSOR_STORE"
    printf 'bead-rehome: its close reason is unchanged and may still be bare; bd show renders the reason, not the pointer, so the appended note is what a reader sees.\n'
else
    # Finalize gate: an open human gate that blocks this bead holds its close,
    # the same precondition merge.sh applies to a merge (docs/finalize-gate.md).
    # The successor pointer is already stamped, so a hold here leaves an OPEN,
    # pointed, findable bead — the shape a refused close below also leaves. The
    # release is to clear the gate, then re-run this close.
    FG_ARGS=(check "$ORIGIN")
    if [ -n "$EXCEPT_KEY" ]; then FG_ARGS+=(--except-key "$EXCEPT_KEY"); fi
    if ! FG_REASON=$("$FINALIZE_GATE" "${FG_ARGS[@]}" 2>/dev/null); then
        echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close is held: ${FG_REASON:-finalize gate refused (fail-closed)}." >&2
        echo "bead-rehome: the disposition is legible — the bead is open, pointed, and findable. Clear what holds it, then re-run this close." >&2
        exit 5
    fi
    # The retry's own gates. The finalize gate excepted the open human gates
    # under the caller's key that no person is assigned, but bd still refuses to
    # close a bead they block, so they are resolved just before the close. Which
    # of them are open is bd-lib.sh's open_human_gate rule. That happens only
    # once nothing else would refuse it: every other live blocker and every open
    # child holds the close, and with one standing the gates stay open and
    # nothing closes, as a held close leaves it. Any other blocker that is closed
    # or pinned holds nothing, as in bd. The reason names the retry and carries no
    # outcome word, because the close has not landed yet: no quiet period starts.
    if [ -n "$EXCEPT_KEY" ]; then
        BLK_JSON=$(bd_at "$ORIGIN_PATH" dep list "$ORIGIN" --type blocks --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true)
        printf '%s' "$BLK_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
            || die "pointer IS recorded on $ORIGIN, but its blockers did not read, so whether anything besides its own [$EXCEPT_KEY] gates holds the close is unknown; nothing was resolved or closed. Re-run this close." 5
        OWN_GATES=$(printf '%s' "$BLK_JSON" | jq -r --arg k "$EXCEPT_KEY" "$HUMAN_GATE_JQ"'
            .[] | select(open_human_gate($k) and ((.assignee // "") | tostring) == "") | .id' 2>/dev/null || true)
        OTHER_BLOCKERS=$(printf '%s' "$BLK_JSON" | jq -r --arg k "$EXCEPT_KEY" "$HUMAN_GATE_JQ"'
            [ .[] | select(((.status // "open") | tostring) as $st | $st != "closed" and $st != "pinned")
                  | select((open_human_gate($k) and ((.assignee // "") | tostring) == "") | not)
                  | .id ] | join(" ")' 2>/dev/null || true)
        KIDS_JSON=$(bd_at "$ORIGIN_PATH" list --parent "$ORIGIN" --include-gates --include-infra --include-templates --json --limit 1 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true)
        printf '%s' "$KIDS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1 \
            || die "pointer IS recorded on $ORIGIN, but its children did not read, so whether an open child holds the close is unknown; nothing was resolved or closed. Re-run this close." 5
        OPEN_KID=$(printf '%s' "$KIDS_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true)
        if [ -n "$OTHER_BLOCKERS" ] || [ -n "$OPEN_KID" ]; then
            HELD_BY="${OTHER_BLOCKERS:+blocker(s) $OTHER_BLOCKERS}"
            [ -z "$OPEN_KID" ] || HELD_BY="${HELD_BY:+$HELD_BY and }open child $OPEN_KID"
            echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close is held by $HELD_BY, so its own [$EXCEPT_KEY] gates stay open and nothing closes." >&2
            echo "bead-rehome: the disposition is legible — the bead is open, pointed, and findable. Clear what holds it, then re-run this close." >&2
            exit 5
        fi
        # bd's unforced close also refuses a template, a pinned bead, and a bead
        # assigned to anyone but the actor the close runs as, whatever its
        # status. Withdrawing the gates ahead of a close bd then refuses would
        # take the question away from the person it asks, and the caller's next
        # refused retry would file it again. So these are read off the origin's
        # row before anything is resolved, and any of them holds the close with
        # the gates open. bd compares the assignee with the --actor it is given
        # and with no other name of this session, so only an origin no one is
        # assigned, or one assigned to exactly $ACTOR, goes on to the close.
        CLOSE_GUARD=$(printf '%s' "$CHECK_JSON" | jq -r --arg actor "$ACTOR" --arg who "${ACTOR:-the actor bd defaults to}" '.[0]
            | ((.assignee // "") | tostring) as $as
            | if (.is_template // false) == true then "it is a template, which bd never closes"
              elif ((.status // "") | tostring | ascii_downcase) == "pinned" or (.pinned // false) == true
                then "it is pinned, which bd closes only by force"
              elif $as != "" and $as != $actor
                then "it is assigned to \($as), and bd closes an assigned bead only for its assignee, while this close runs as \($who)"
              else empty end' 2>/dev/null || true)
        if [ -n "$CLOSE_GUARD" ]; then
            echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but bd would refuse its close: $CLOSE_GUARD. Its own [$EXCEPT_KEY] gates stay open and nothing closes." >&2
            echo "bead-rehome: the disposition is legible — the bead is open, pointed, and findable. Clear what holds it, then re-run this close." >&2
            exit 5
        fi
        GATE_REASON="Withdrawn by bead-rehome.sh just before it retries the close this gate reported: $REASON"
        for GATE in $OWN_GATES; do
            bd_at "$ORIGIN_PATH" gate resolve "$GATE" --reason "$GATE_REASON" >/dev/null 2>&1 || true
            GATE_STATUS=$(bead_json "$ORIGIN_PATH" "$GATE" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
            [ "$GATE_STATUS" = "closed" ] \
                || die "pointer IS recorded on $ORIGIN, but its gate $GATE [$EXCEPT_KEY] did not resolve (status reads '${GATE_STATUS:-unreadable}'), and while it is open bd refuses the close; nothing closed. Re-run this close." 5
            printf 'bead-rehome: withdrew the gate %s [%s] on %s before the close it asked for\n' "$GATE" "$EXCEPT_KEY" "$ORIGIN"
        done
    fi
    # Deliberately NOT --force: the same flag overrides a foreign assignee and
    # an open-children hold. A refusal leaves an OPEN, pointed, findable bead.
    CLOSE_ERR=""
    if ! CLOSE_ERR=$(bd_at "$ORIGIN_PATH" close "$ORIGIN" --reason "$REASON" 2>&1); then
        echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close was refused:" >&2
        printf '%s\n' "$CLOSE_ERR" >&2
        echo "bead-rehome: the disposition is legible either way — the bead is open, pointed, and findable. Judge the refusal, then finish it:" >&2
        echo "  gc bd --db $ORIGIN_PATH/.beads close $ORIGIN --reason \"$REASON\"" >&2
        exit 5
    fi
fi

# 3. Back-pointer on the successor, best-effort: a failure here does not undo
# a fully-recorded disposition.
bd_at "$SUCCESSOR_PATH" update "$SUCCESSOR" \
    --set-metadata gc.supersedes="$ORIGIN" \
    --set-metadata gc.supersedes_store="$ORIGIN_STORE" >/dev/null 2>&1 \
    || echo "bead-rehome: WARN could not write the back-pointer on $SUCCESSOR ($SUCCESSOR_STORE); the forward pointer on $ORIGIN is recorded and is the one that matters" >&2

[ "$ORIGIN_STATUS" = "closed" ] \
    || printf 'bead-rehome: %s closed in %s — %s\n' "$ORIGIN" "$ORIGIN_STORE" "$REASON"

# 4. End the branch the retired bead names on the git remote, the way a merge
# ends a landed one. Only once the bead reads back closed: until then it still
# owns its branch. branch-end.sh holds the remote write and its guards. It keeps
# a branch a live owner names, pins the tip, and deletes only the tip it
# checked. The disposition is complete before this runs, so a branch it cannot
# end costs a warning, never the close.
RETIRED_BRANCH=$(origin_branch "$CHECK_JSON")
if [ -n "$RETIRED_BRANCH" ]; then
    # Quoted for a paste: a branch name may carry shell metacharacters.
    END_CMD=$(printf '%q ' "$BRANCH_END" --rig "${ORIGIN_STORE#rig:}" --branch "$RETIRED_BRANCH" --bead "$ORIGIN")
    END_CMD="${END_CMD% }"
    FINAL_STATUS=$(bead_json "$ORIGIN_PATH" "$ORIGIN" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
    if [ "$FINAL_STATUS" != "closed" ]; then
        echo "bead-rehome: WARN $ORIGIN did not read back closed (status '${FINAL_STATUS:-unreadable}'), so its branch $RETIRED_BRANCH was left on the git remote; once it reads closed, end it with: $END_CMD" >&2
    else
        END_RC=0
        END_OUT=$("$BRANCH_END" --rig "${ORIGIN_STORE#rig:}" --branch "$RETIRED_BRANCH" --bead "$ORIGIN" 2>&1) || END_RC=$?
        END_NOTE=""
        case "$END_RC" in
            0|3) [ -z "$END_OUT" ] || printf '%s\n' "$END_OUT"
                 case "$END_OUT" in *"is not on origin"*) ;; *) END_NOTE="$END_OUT" ;; esac ;;
            *)   [ -z "$END_OUT" ] || printf '%s\n' "$END_OUT" >&2
                 echo "bead-rehome: WARN the close stands, but branch $RETIRED_BRANCH is still on the git remote (branch-end exit $END_RC); end it with: $END_CMD" >&2
                 END_NOTE="Branch $RETIRED_BRANCH is still on the git remote (branch-end exit $END_RC: $(printf '%s' "$END_OUT" | tail -1)). End it with: $END_CMD" ;;
        esac
        # The bead records what became of its branch. pr-facts.sh and
        # duplicate-sweep.sh run this script for its exit status and drop its
        # output, so the note is what a later reader finds. A re-run that reaches
        # the same outcome adds nothing.
        if [ -n "$END_NOTE" ]; then
            case "$(printf '%s' "$CHECK_JSON" | jq -r '.[0].notes // ""' 2>/dev/null || true)" in
                *"$END_NOTE"*) ;;
                *) bd_at "$ORIGIN_PATH" update "$ORIGIN" --append-notes "$END_NOTE" >/dev/null 2>&1 \
                       || echo "bead-rehome: WARN could not record the branch's outcome on $ORIGIN: $END_NOTE" >&2 ;;
            esac
        fi
    fi
fi

printf 'bead-rehome: attribution is in the store events table, not the issues row:\n  gc dolt sql -q "SELECT issue_id, event_type, actor, created_at FROM %s.events WHERE issue_id = '"'"'%s'"'"' ORDER BY created_at"\n' \
    "${ORIGIN%%-*}" "$ORIGIN"
