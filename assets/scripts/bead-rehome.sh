#!/usr/bin/env bash
# bead-rehome — close a bead with a successor pointer that is legible from the
# store the bead lived in. The pointer (gc.superseded_by + _store) is the only
# thing that distinguishes a sound disposition from a careless close where the
# question gets asked, so it is stamped and READ BACK before the close; this
# script would rather leave the origin OPEN than close it unpointed.
# Writes, in order: pointer on the origin (verified), a populated close reason
# (kind + successor + store), a best-effort back-pointer on the successor. An
# already-closed origin is the REPAIR path: pointer + appended note only.
# Also drops an origin->successor `blocks` wait edge on the way: `bd close`
# refuses a blocked issue, and a disposed bead is not waiting on its successor.
# Reads the legacy bare `superseded_by` key as evidence of a prior disposition;
# writes only the canonical gc.-prefixed pair.
# Callers: converse dispositions, operator re-homes, duplicate-sweep.sh.
# Doctrine: docs/state-machine.md "Disposition". Test: bead-rehome.test.sh.
set -euo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

ORIGIN=""; SUCCESSOR=""; KIND=""; NOTE=""
ORIGIN_STORE=""; SUCCESSOR_STORE=""; DRY_RUN=""

usage() {
    cat <<'U'
Usage:
  bead-rehome.sh --origin <bead-id> --successor <bead-id> \
                 --kind re-homed|folded|fixed-upstream|duplicate \
                 [--note "<one sentence of why>"] \
                 [--origin-store rig:<name>] [--successor-store rig:<name>] \
                 [--dry-run]

Stores are derived from each bead id's prefix via `gc rig list --json`;
pass --origin-store/--successor-store when a prefix is ambiguous.
An already-closed origin gains the pointer and an appended note (repair path).
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
        --dry-run)          DRY_RUN=1; shift ;;
        -h|--help)          usage 0 ;;
        *)                  die "unknown argument '$1' (try --help)" 64 ;;
    esac
done

[ -n "$ORIGIN" ]    || die "--origin is required (try --help)" 64
[ -n "$SUCCESSOR" ] || die "--successor is required (try --help)" 64
[ -n "$KIND" ]      || die "--kind is required (try --help)" 64

# The kind shapes the close reason, so it is a closed set.
case "$KIND" in
    re-homed|folded|fixed-upstream|duplicate) ;;
    *) die "--kind must be one of re-homed|folded|fixed-upstream|duplicate (got '$KIND')" 64 ;;
esac

[ "$ORIGIN" != "$SUCCESSOR" ] || die "--origin and --successor are the same bead ($ORIGIN)" 64

# Store refs are `rig:<name>`; reads go through `bd --db <path>/.beads` (the
# `gc bd --rig` form answers empty for the HQ store).
RIGS_JSON=""
rigs_json() {
    [ -n "$RIGS_JSON" ] && { printf '%s' "$RIGS_JSON"; return 0; }
    RIGS_JSON=$(gc rig list --json 2>/dev/null || true)
    printf '%s' "$RIGS_JSON"
}

store_path() { # rig:<name> -> repo path, empty when unresolvable
    local ref="$1" name
    case "$ref" in
        rig:?*) name="${ref#rig:}" ;;
        *) return 0 ;;
    esac
    rigs_json | jq -r --arg n "$name" '.rigs[]? | select(.name == $n) | .path // empty' 2>/dev/null || true
    return 0
}

# Both resolvers end in `return 0`: under set -e a non-zero "no match" would
# abort before the die below can name the unresolvable store.
store_for_bead() { # bead id -> rig:<name> via prefix; empty on 0 or >1 hits
    local id="$1" pfx="${1%%-*}" hits
    [ "$pfx" != "$id" ] || return 0
    hits=$(rigs_json | jq -r --arg p "$pfx" '[.rigs[]? | select(.prefix == $p) | .name] | if length == 1 then .[0] else empty end' 2>/dev/null || true)
    [ -n "$hits" ] && printf 'rig:%s' "$hits"
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
        bd --db "$db/.beads" --actor "$ACTOR" "$@"
    else
        bd --db "$db/.beads" "$@"
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
esac
REASON="$PHRASE $SUCCESSOR in $SUCCESSOR_STORE"
[ -n "$NOTE" ] && REASON="$REASON — $NOTE"

if [ -n "$DRY_RUN" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        CLOSE_PLAN="already closed — pointer + note only, close reason left as-is"
    else
        CLOSE_PLAN="$REASON"
    fi
    if [ "$(wait_edge_count "$ORIGIN_JSON")" -gt 0 ]; then
        EDGE_PLAN="drop the 'blocked by $SUCCESSOR' wait edge (it would refuse this close)"
    else
        EDGE_PLAN="none ($ORIGIN carries no wait edge to $SUCCESSOR)"
    fi
    printf 'bead-rehome (dry run)\n  origin:    %s [%s] in %s\n  successor: %s in %s\n  stamp:     gc.superseded_by=%s gc.superseded_by_store=%s\n  edge:      %s\n  close:     %s\n  actor:     %s\n' \
        "$ORIGIN" "${ORIGIN_STATUS:-unknown}" "$ORIGIN_STORE" \
        "$SUCCESSOR" "$SUCCESSOR_STORE" "$SUCCESSOR" "$SUCCESSOR_STORE" \
        "$EDGE_PLAN" "$CLOSE_PLAN" "${ACTOR:-<bd default>}"
    exit 0
fi

# 1. Stamp the pointer and prove it landed: the close below is gated on the
# read-back, not on an exit status.
bd_at "$ORIGIN_PATH" update "$ORIGIN" \
    --set-metadata gc.superseded_by="$SUCCESSOR" \
    --set-metadata gc.superseded_by_store="$SUCCESSOR_STORE" >/dev/null 2>&1 || true

CHECK_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
GOT_SUCC=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // empty' 2>/dev/null || true)
GOT_STORE=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // empty' 2>/dev/null || true)
if [ "$GOT_SUCC" != "$SUCCESSOR" ] || [ "$GOT_STORE" != "$SUCCESSOR_STORE" ]; then
    die "successor pointer did NOT stick on $ORIGIN (read back gc.superseded_by='${GOT_SUCC:-}' gc.superseded_by_store='${GOT_STORE:-}'); NOT closing it — an unpointed close is the defect this script exists to prevent. The bead is still open and visible; re-run once the store accepts the write" 4
fi

# 1b. Drop ONLY the wait edge to THIS successor: it would refuse the close,
# and gc.superseded_by records the relationship more strongly. Any other
# blocker is a real hold whose refusal below is correct.
if [ "$(wait_edge_count "$CHECK_JSON")" -gt 0 ]; then
    bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 || true
    # `bd dep remove` reports success for an edge that never existed; read the
    # graph back instead.
    if [ "$(wait_edge_count "$(bead_json "$ORIGIN_PATH" "$ORIGIN")")" -gt 0 ]; then
        echo "bead-rehome: WARN could not drop the '$ORIGIN blocked by $SUCCESSOR' wait edge; while it stands the close below is refused — clear it with: bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR" >&2
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
    # Deliberately NOT --force: the same flag overrides a foreign assignee and
    # an open-children hold. A refusal leaves an OPEN, pointed, findable bead.
    CLOSE_ERR=""
    if ! CLOSE_ERR=$(bd_at "$ORIGIN_PATH" close "$ORIGIN" --reason "$REASON" 2>&1); then
        echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close was refused:" >&2
        printf '%s\n' "$CLOSE_ERR" >&2
        echo "bead-rehome: the disposition is legible either way — the bead is open, pointed, and findable. Judge the refusal, then finish it:" >&2
        echo "  bd --db $ORIGIN_PATH/.beads close $ORIGIN --reason \"$REASON\"" >&2
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
