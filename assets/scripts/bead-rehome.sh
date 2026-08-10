#!/usr/bin/env bash
# bead-rehome — close a bead with a successor pointer that is legible from the
# store the bead lived in.
#
# THE FAILURE THIS EXISTS TO PREVENT (tk-isyz0, incident 2026-08-09).
# An operator ruling re-homed eight su-rig beads into the gc-toolkit store: a
# mirror bead was created in the target store, then the origin bead was closed
# in the rig store. Five of those closes were correct re-homes whose mirrors
# had been created SECONDS earlier — and every one of the eight wrote a bare
# `[Closed]` with no successor pointer. From the store where the bead lived,
# nothing pointed anywhere, so a sound disposition and a careless false close
# looked EXACTLY alike.
#
# What that ambiguity cost, measured: a refinery read the signature as a
# careless sweep and escalated; the mayor acted on the escalation and reopened
# two beads; the refinery found the actor and retracted, but confirmed the two
# reopens as correct; a re-verification found BOTH of those confirmations were
# also wrong — one bead had been folded into a target that said so in its own
# notes, the other fixed upstream by a named commit. Four wrong conclusions,
# two agents, one missing field. Nobody was careless. The signal was absent.
#
# So the pointer is not paperwork, it is the only thing that distinguishes a
# disposition from a mistake at the place where the question gets asked. This
# script is the one way to write it, because an instruction to "remember the
# pointer" is exactly what failed: it is invisible when skipped, and the actor
# skipping it is mid-ruling with eight beads to close.
#
# THE KEY NAMES ARE NOT A FRESH INVENTION. Two conventions are already in the
# wild: bare `superseded_by` (4 beads across the tk/su stores) and
# `gc.superseded_by` (5 su beads, written by the converse session that is
# retro-stamping the incident's own beads — the newer write, and the one the
# actor performing re-homes actually uses). This script writes
# `gc.superseded_by` to compose with that sweep instead of forking from it: a
# bead the sweep already stamped runs through here cleanly and simply GAINS the
# store half it was missing. The bare form is still READ as a legacy alias,
# because a read side that knows only one key reproduces this bead's own
# failure — a disposition invisible to whoever is asking.
#
# WHAT IT WRITES, and the order, which is load-bearing:
#   1. `gc.superseded_by` + `gc.superseded_by_store` on the ORIGIN — stamped and
#      READ BACK BEFORE the close. A close is irreversible in the sense that
#      matters (the bead leaves every open-work query); the pointer is what
#      makes it legible afterward. Stamp-then-close can only leave an OPEN
#      bead carrying a pointer — visible, self-explanatory, trivially
#      finishable. Close-then-stamp loses the pointer forever on a failed
#      write and reproduces the exact bug.
#   2. A populated close reason naming kind + successor + store. Never bare:
#      the reason is what a human reads first, and `[Closed]` is what a bare
#      close renders as.
#   3. `gc.supersedes` + `gc.supersedes_store` on the SUCCESSOR — the
#      back-pointer, best-effort, so the target side is legible too.
#
# Fail-closed throughout: it would rather leave the origin OPEN than close it
# unpointed. Every refusal exits non-zero and says what to run.
#
# Usage:
#   bead-rehome.sh --origin <bead-id> --successor <bead-id> \
#                  --kind re-homed|folded|fixed-upstream|duplicate \
#                  [--note "<one sentence of why>"] \
#                  [--origin-store rig:<name>] [--successor-store rig:<name>] \
#                  [--dry-run]
#
# An ALREADY-CLOSED origin is the REPAIR path, not an error: the pointer is
# stamped and the disposition appended to the notes. `bd` has no flag that
# rewrites a close reason after the fact, so the note is the only prose that can
# still be added — and that is how a pre-rule bare close (there are hundreds)
# becomes legible without reopening anything.
#
# Stores are derived from each bead id's prefix via `gc rig list --json`
# (`tk-` -> rig:gc-toolkit); pass --origin-store/--successor-store to override
# when a prefix is ambiguous or the store is not a listed rig.
#
# Doctrine: docs/work-bead-state-machine.md, "Disposition: a close that hands
# the work to a successor". Regression test: bead-rehome.test.sh.
set -euo pipefail

ORIGIN=""; SUCCESSOR=""; KIND=""; NOTE=""
ORIGIN_STORE=""; SUCCESSOR_STORE=""; DRY_RUN=""

usage() {
    sed -n '/^# Usage:/,/^#$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# The kind shapes the close reason, so it is a closed set: a free-text kind
# would render an unreadable reason, which is the thing being fixed.
case "$KIND" in
    re-homed|folded|fixed-upstream|duplicate) ;;
    *) die "--kind must be one of re-homed|folded|fixed-upstream|duplicate (got '$KIND')" 64 ;;
esac

# A bead cannot supersede itself, and a pointer that says it does is worse than
# none: it reads as a resolved disposition and resolves to nothing.
[ "$ORIGIN" != "$SUCCESSOR" ] || die "--origin and --successor are the same bead ($ORIGIN)" 64

# --- store resolution -------------------------------------------------------
# One canonical store-ref form, `rig:<name>`, matching the `gc.root_store_ref`
# the runtime already stamps on workflow roots. Reads go through
# `bd --db <path>/.beads` and NOT `gc bd --rig <name>`: the latter answers
# empty for the HQ store (verified live), and a re-home target can live in HQ.
RIGS_JSON=""
rigs_json() {
    [ -n "$RIGS_JSON" ] && { printf '%s' "$RIGS_JSON"; return 0; }
    RIGS_JSON=$(gc rig list --json 2>/dev/null || true)
    printf '%s' "$RIGS_JSON"
}

# `rig:<name>` -> repo path holding that store. Empty when it does not resolve.
store_path() {
    local ref="$1" name
    case "$ref" in
        rig:?*) name="${ref#rig:}" ;;
        *) return 0 ;;
    esac
    rigs_json | jq -r --arg n "$name" '.rigs[]? | select(.name == $n) | .path // empty' 2>/dev/null || true
    return 0
}

# bead id -> `rig:<name>`, via the id prefix. Empty when no rig claims it or
# more than one does — an ambiguous prefix must be resolved by the caller, not
# guessed, because guessing wrong writes a pointer into the wrong store.
#
# Both resolvers END IN `return 0` deliberately. They are called as
# `[ -n "$X" ] || X=$(resolve ...)`, and under `set -e` a resolver that returned
# non-zero on "no match" would abort the script THERE — before the `die` below
# could name the unresolvable store. The empty-string answer is the signal; the
# exit status carries nothing.
store_for_bead() {
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

# The audit trail. `bd` defaults the actor to $BEADS_ACTOR, then git user.name,
# then $USER — so a close run from a shell with no BEADS_ACTOR records a human
# username for an agent's action. The per-store `events` table is the ONLY
# place close attribution exists (the issues row carries no closed_by, and
# every Dolt write commits as beads@local), so passing the session identity
# explicitly is what makes "who closed this" answerable at all.
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
    bd_at "$1" show "$2" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037' || true
}

# --- both beads must exist --------------------------------------------------
# The successor is checked FIRST and hardest. A pointer to a bead that does not
# exist is strictly worse than no pointer: it reads as a resolved disposition,
# and the reader who follows it finds nothing and is back to the original
# ambiguity with false confidence added.
SUCC_JSON=$(bead_json "$SUCCESSOR_PATH" "$SUCCESSOR")
SUCC_ID=$(printf '%s' "$SUCC_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true)
[ -n "$SUCC_ID" ] \
    || die "successor $SUCCESSOR does not exist in $SUCCESSOR_STORE ($SUCCESSOR_PATH/.beads) — nothing stamped, origin $ORIGIN untouched" 3

ORIGIN_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
ORIGIN_ID=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].id // empty' 2>/dev/null || true)
[ -n "$ORIGIN_ID" ] \
    || die "origin $ORIGIN does not exist in $ORIGIN_STORE ($ORIGIN_PATH/.beads) — nothing stamped" 3

ORIGIN_STATUS=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
# Both key conventions are read (see the header): the canonical dotted key
# first, then the legacy bare one. `gc.superseded_by` is a FLAT dotted key, not
# a nested object, so it needs bracket access — `.metadata.gc.superseded_by`
# silently yields null and would make every existing pointer invisible here,
# which is the one failure mode this script must not have.
PRIOR_SUCC=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // .[0].metadata.superseded_by // empty' 2>/dev/null || true)
PRIOR_STORE=$(printf '%s' "$ORIGIN_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // .[0].metadata.superseded_by_store // empty' 2>/dev/null || true)

# A disposition already on the record for a DIFFERENT successor is somebody
# else's decision. Overwriting it silently would erase the one signal this
# script exists to create, so refuse and let a human reconcile the two.
if [ -n "$PRIOR_SUCC" ] && [ "$PRIOR_SUCC" != "$SUCCESSOR" ]; then
    die "origin $ORIGIN already records a successor pointer to $PRIOR_SUCC (${PRIOR_STORE:-store unrecorded}); refusing to overwrite another disposition — reconcile the two by hand" 6
fi

# --- the close reason, auto-populated --------------------------------------
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
    printf 'bead-rehome (dry run)\n  origin:    %s [%s] in %s\n  successor: %s in %s\n  stamp:     gc.superseded_by=%s gc.superseded_by_store=%s\n  close:     %s\n  actor:     %s\n' \
        "$ORIGIN" "${ORIGIN_STATUS:-unknown}" "$ORIGIN_STORE" \
        "$SUCCESSOR" "$SUCCESSOR_STORE" "$SUCCESSOR" "$SUCCESSOR_STORE" \
        "$CLOSE_PLAN" "${ACTOR:-<bd default>}"
    exit 0
fi

# --- 1. stamp the pointer, and prove it landed -----------------------------
# `bd update` reporting success is not proof the write is durable, and this
# pointer is the whole point of the operation — so it is read back, and the
# close below is gated on the read-back rather than on an exit status.
bd_at "$ORIGIN_PATH" update "$ORIGIN" \
    --set-metadata gc.superseded_by="$SUCCESSOR" \
    --set-metadata gc.superseded_by_store="$SUCCESSOR_STORE" >/dev/null 2>&1 || true

# Read back the CANONICAL keys only. The legacy alias is accepted as evidence of
# a prior disposition above, but it is not proof that THIS write landed.
CHECK_JSON=$(bead_json "$ORIGIN_PATH" "$ORIGIN")
GOT_SUCC=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by"] // empty' 2>/dev/null || true)
GOT_STORE=$(printf '%s' "$CHECK_JSON" | jq -r '.[0].metadata["gc.superseded_by_store"] // empty' 2>/dev/null || true)
if [ "$GOT_SUCC" != "$SUCCESSOR" ] || [ "$GOT_STORE" != "$SUCCESSOR_STORE" ]; then
    die "successor pointer did NOT stick on $ORIGIN (read back gc.superseded_by='${GOT_SUCC:-}' gc.superseded_by_store='${GOT_STORE:-}'); NOT closing it — an unpointed close is the defect this script exists to prevent. The bead is still open and visible; re-run once the store accepts the write" 4
fi

# --- 2. the prose carrier --------------------------------------------------
# `bd show` renders `Close reason:` in its header and does NOT render metadata,
# so the reason — not the pointer — is what a human reading the bead actually
# sees. The pointer is for queries; the reason is for the reader who is deciding
# whether this close was sound. Both are required.
#
# REPAIR PATH. An already-closed bead is the shape every pre-rule bare close
# left behind, including the eight from the incident, and stamping their pointer
# after the fact is exactly what the read-side rule asks for once a disposition
# is resolved. `bd` has no flag that rewrites a close reason on an update, so
# for those the note is the only prose that can still be added — and it is
# appended, never replacing (`--notes` REPLACES; `--append-notes` does not).
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
    # Deliberately NOT --force. `bd close` is assignee-gated, and the same flag
    # also overrides a genuinely foreign assignee and an open-children hold, so
    # forcing past a refusal here could close a bead somebody else is holding or
    # one whose children are still live. A refusal leaves an OPEN bead carrying
    # the pointer — the disposition is already legible — so the safe move is to
    # report it and let the caller decide.
    CLOSE_ERR=""
    if ! CLOSE_ERR=$(bd_at "$ORIGIN_PATH" close "$ORIGIN" --reason "$REASON" 2>&1); then
        echo "bead-rehome: pointer IS recorded on $ORIGIN (gc.superseded_by=$SUCCESSOR in $SUCCESSOR_STORE) but the close was refused:" >&2
        printf '%s\n' "$CLOSE_ERR" >&2
        echo "bead-rehome: the disposition is legible either way — the bead is open, pointed, and findable. Judge the refusal, then finish it:" >&2
        echo "  bd --db $ORIGIN_PATH/.beads close $ORIGIN --reason \"$REASON\"" >&2
        exit 5
    fi
fi

# --- 3. back-pointer on the successor, best-effort -------------------------
# The forward pointer is what the incident needed; this makes the target side
# legible too ("what did this absorb?"). A failure here does not undo a
# correct, fully-recorded disposition, so it warns and exits 0.
bd_at "$SUCCESSOR_PATH" update "$SUCCESSOR" \
    --set-metadata gc.supersedes="$ORIGIN" \
    --set-metadata gc.supersedes_store="$ORIGIN_STORE" >/dev/null 2>&1 \
    || echo "bead-rehome: WARN could not write the back-pointer on $SUCCESSOR ($SUCCESSOR_STORE); the forward pointer on $ORIGIN is recorded and is the one that matters" >&2

[ "$ORIGIN_STATUS" = "closed" ] \
    || printf 'bead-rehome: %s closed in %s — %s\n' "$ORIGIN" "$ORIGIN_STORE" "$REASON"
printf 'bead-rehome: attribution is in the store events table, not the issues row:\n  gc dolt sql -q "SELECT issue_id, event_type, actor, created_at FROM %s.events WHERE issue_id = '"'"'%s'"'"' ORDER BY created_at"\n' \
    "${ORIGIN%%-*}" "$ORIGIN"
