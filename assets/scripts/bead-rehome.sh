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
#   The judgment kinds re-homed|folded|not-needed are a person's call, held to
#   (a) only: a non-closed merge_result does not bar them.
# --check evaluates those gates for the given origin/successor/kind and exits
# 0 (eligible) or non-zero (refused, with the reason on stderr), writing
# nothing.
# Writes, in order: pointer on the origin (verified), a populated close reason
# (kind + successor + store), a best-effort back-pointer on the successor. When
# the origin is a task_kind=visit it also stamps the outcome the board reads —
# gc.outcome = the kind, gc.outcome_reason = that close reason — verified before
# the close, because a closed visit with no gc.outcome is a sitting the board
# cannot report and no re-run reaches it (doctor/check-visit-outcome-recorded).
# An already-closed origin is the REPAIR path: pointer + appended note, plus that
# outcome when the visit lacks one, with the gates skipped (the close they would
# guard already happened).
# Also drops an origin->successor `blocks` wait edge on the way: `bd close`
# refuses a blocked issue, and a disposed bead is not waiting on its successor.
# Reads the legacy bare `superseded_by` key as evidence of a prior disposition;
# writes only the canonical gc.-prefixed pair.
# Callers: converse dispositions, operator re-homes, duplicate-sweep.sh,
# pr-facts.sh (a PR closed with a pre-recorded disposition, and that branch's
# parked rework children).
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
# The composable "may this bead be finalized?" precondition set. An open visit
# tracking the origin holds its close, the same subject-scoped precondition
# merge.sh applies to a merge (docs/finalize-gate.md). Overridable for a test.
FINALIZE_GATE="${GC_FINALIZE_GATE_TOOL:-$HERE/finalize-gate.sh}"

ORIGIN=""; SUCCESSOR=""; KIND=""; NOTE=""
ORIGIN_STORE=""; SUCCESSOR_STORE=""; DRY_RUN=""; CHECK=""; EXCEPT_KEY=""

usage() {
    cat <<'U'
Usage:
  bead-rehome.sh --origin <bead-id> --successor <bead-id> \
                 --kind re-homed|folded|fixed-upstream|duplicate|not-needed \
                 [--note "<one sentence of why>"] \
                 [--origin-store rig:<name>] [--successor-store rig:<name>] \
                 [--except-key <escalation-key>] [--check] [--dry-run]

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

An open visit on the origin holds the close (finalize-gate.sh). --except-key
is for the caller that reports its own refusals of this close through
escalate.sh: it names the escalation key that caller files them under. A visit
under that key, stamped for this origin, that nobody is engaged in does not hold
the retry it asks for. A visit someone has claimed, or bound by assignee or
session, still holds. So does every visit under any other key. The caller
concludes its visits once the close lands.
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
    RIGS_JSON=$(gc rig list --json 2>/dev/null || true)
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
    # The judgment kinds (re-homed, folded, not-needed) are a person's call, so a
    # non-closed merge_result does not bar them: the converse retire path
    # disposes an in-flight anchor through here on the operator's ruling. An
    # origin carrying the operator's pre-recorded PR-close disposition for this
    # kind and successor (pr-dispose.sh) is that ruling already made, read from
    # the store rather than taken from the caller, so (b) does not re-judge it.
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

# A closed task_kind=visit with no gc.outcome is a sitting the board cannot
# report (doctor/check-visit-outcome-recorded projects gc.outcome as the OUTCOME
# column and gc.outcome_reason as the headline), and once a visit closes no
# re-run reaches it — the permanence visit-close.sh guards. So when the origin
# is a visit the outcome is stamped beside the pointer below and gates the close
# the same way. The --kind IS the disposition, so it is the outcome word, and
# $REASON is its headline. An outcome the visit already records is the sitting's
# own word and is left untouched (a visit closed through visit-close.sh, then
# re-homed, already carries the word it signed off with).
ORIGIN_KIND=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["task_kind"] // empty' 2>/dev/null || true)
PRIOR_OUTCOME=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.outcome"] // empty' 2>/dev/null || true)
STAMP_OUTCOME=""
if [ "$ORIGIN_KIND" = "visit" ] && [ -z "$PRIOR_OUTCOME" ]; then STAMP_OUTCOME=1; fi

if [ -n "$DRY_RUN" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        CLOSE_PLAN="already closed — pointer + note only, close reason left as-is"
    else
        CLOSE_PLAN="$REASON"
    fi
    STAMP_PLAN="gc.superseded_by=$SUCCESSOR gc.superseded_by_store=$SUCCESSOR_STORE"
    [ -n "$STAMP_OUTCOME" ] && STAMP_PLAN="$STAMP_PLAN gc.outcome=$KIND gc.outcome_reason=<the close reason>"
    if [ "$(wait_edge_count "$ORIGIN_JSON")" -gt 0 ]; then
        EDGE_PLAN="drop the 'blocked by $SUCCESSOR' wait edge (it would refuse this close)"
    else
        EDGE_PLAN="none ($ORIGIN carries no wait edge to $SUCCESSOR)"
    fi
    printf 'bead-rehome (dry run)\n  origin:    %s [%s] in %s\n  successor: %s in %s\n  stamp:     %s\n  edge:      %s\n  close:     %s\n  actor:     %s\n' \
        "$ORIGIN" "${ORIGIN_STATUS:-unknown}" "$ORIGIN_STORE" \
        "$SUCCESSOR" "$SUCCESSOR_STORE" "$STAMP_PLAN" \
        "$EDGE_PLAN" "$CLOSE_PLAN" "${ACTOR:-<bd default>}"
    exit 0
fi

# 1. Stamp the pointer — and, for a visit, the outcome the board reads — and
# prove they landed: the close below is gated on the read-back, not on an exit
# status. Both go in one update; a --set-metadata write bypasses bd's close
# guard, so it lands even on a visit this actor cannot close under.
STAMP_META=(--set-metadata gc.superseded_by="$SUCCESSOR" \
            --set-metadata gc.superseded_by_store="$SUCCESSOR_STORE")
if [ -n "$STAMP_OUTCOME" ]; then
    STAMP_META+=(--set-metadata gc.outcome="$KIND" \
                 --set-metadata gc.outcome_reason="$REASON")
fi
bd_at "$ORIGIN_PATH" update "$ORIGIN" "${STAMP_META[@]}" >/dev/null 2>&1 || true

CHECK_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
GOT_SUCC=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // empty' 2>/dev/null || true)
GOT_STORE=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // empty' 2>/dev/null || true)
if [ "$GOT_SUCC" != "$SUCCESSOR" ] || [ "$GOT_STORE" != "$SUCCESSOR_STORE" ]; then
    die "successor pointer did NOT stick on $ORIGIN (read back gc.superseded_by='${GOT_SUCC:-}' gc.superseded_by_store='${GOT_STORE:-}'); NOT closing it — an unpointed close is the defect this script exists to prevent. The bead is still open and visible; re-run once the store accepts the write" 4
fi
if [ -n "$STAMP_OUTCOME" ]; then
    # Read back BOTH stamps and repair once before gating the close. The board
    # shows gc.outcome_reason as the sitting's headline (comment above), so a
    # close that lands gc.outcome but drops the reason still leaves an illegible
    # row that no re-run repairs — PRIOR_OUTCOME is then nonempty and STAMP_OUTCOME
    # never re-arms. One --set-metadata pair can read back empty while the update
    # exits 0, so both are the precondition, the same guard visit-close.sh and
    # gc-helm.sh's dismiss verb apply.
    GOT_OUTCOME=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.outcome"] // empty' 2>/dev/null || true)
    GOT_OUTCOME_REASON=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.outcome_reason"] // empty' 2>/dev/null || true)
    if [ "$GOT_OUTCOME" != "$KIND" ] || [ "$GOT_OUTCOME_REASON" != "$REASON" ]; then
        bd_at "$ORIGIN_PATH" update "$ORIGIN" \
            --set-metadata gc.outcome="$KIND" \
            --set-metadata gc.outcome_reason="$REASON" >/dev/null 2>&1 || true
        CHECK_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
        GOT_OUTCOME=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.outcome"] // empty' 2>/dev/null || true)
        GOT_OUTCOME_REASON=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.outcome_reason"] // empty' 2>/dev/null || true)
    fi
    if [ "$GOT_OUTCOME" != "$KIND" ] || [ "$GOT_OUTCOME_REASON" != "$REASON" ]; then
        die "visit outcome did NOT stick on $ORIGIN (read back gc.outcome='${GOT_OUTCOME:-}' gc.outcome_reason='${GOT_OUTCOME_REASON:-}'); NOT closing it — a closed visit needs the outcome word the board groups by AND the reason headline it shows, and once it closes no re-run reaches it. The bead is still visible; re-run once the store accepts the write" 4
    fi
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
    # Finalize gate: an OPEN visit tracking this bead holds its close, the same
    # subject-scoped precondition merge.sh applies to a merge (docs/finalize-gate.md).
    # The successor pointer is already stamped, so a hold here leaves an OPEN,
    # pointed, findable bead — the shape a refused close below also leaves. The
    # release is to conclude the open visit, then re-run this close.
    FG_ARGS=(check "$ORIGIN")
    if [ -n "$EXCEPT_KEY" ]; then FG_ARGS+=(--except-key "$EXCEPT_KEY"); fi
    if ! FG_REASON=$("$FINALIZE_GATE" "${FG_ARGS[@]}" 2>/dev/null); then
        echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close is held: ${FG_REASON:-finalize gate refused (fail-closed)}." >&2
        echo "bead-rehome: the disposition is legible — the bead is open, pointed, and findable. Conclude the open visit, then re-run this close." >&2
        exit 5
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
printf 'bead-rehome: attribution is in the store events table, not the issues row:\n  gc dolt sql -q "SELECT issue_id, event_type, actor, created_at FROM %s.events WHERE issue_id = '"'"'%s'"'"' ORDER BY created_at"\n' \
    "${ORIGIN%%-*}" "$ORIGIN"
