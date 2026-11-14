#!/usr/bin/env bash
# bead-rehome — the one writer that closes a bead with a successor, for every
# actor. The successor is recorded in bd's own edge from the closed bead:
# `duplicates` onto the canonical under --kind duplicate, `supersedes` onto the
# bead that carries the work, or under not-needed onto the evidence that ruled it
# out. The edge lives in the origin's store and may name a bead in another rig's
# store, which bd keeps unverified and `gc bd list` returns. Readers take it
# through bd-lib.sh's $DISPOSITION_JQ.
#
# The close is bd's checked close, written as one `gc bd update --status=closed`
# that bd applies only while the origin still has the status and assignee this
# run read before judging it. bd refuses it while a live blocker or an open
# child holds the origin, and the finalize gate (finalize-gate.sh), asked before
# any write, holds it while an open human gate blocks the origin. bd's update
# leaves out two refusals its `bd close` makes, a pinned bead and a bead
# assigned to anyone but the actor, so the writer reads those off the origin
# first, and a close any of these holds writes nothing. bd's update sets no close
# reason, so the disposition's prose rides the close as an appended note.
#
# The close takes the store's record lock, a flock on pr-record.lock in the
# origin store's .beads directory, which gctk's pr domain names and its two
# writers of a PR's pending record take: `gctk pr record` across both of its
# writes, and the landing order's run for each record it reads
# (specs/tk-1tfzr71.66/design.md, section 4). The lock is taken before the
# origin is read, whatever the origin carries, because a publication can mark
# the bead after a read made without it, and it is held through the close. So
# the close lands before a publication takes the lock, or after both of its
# writes, and never between a run's read of the record and its write. The close
# clears the record's marker, pr_reconcile_pending, in its own write when the
# origin carries it, so no later run of the landing order reopens the closed
# bead. A closed origin clears it the same way: the repair's note carries the
# clear, and an origin that already records this disposition and still carries
# the marker gets a note that carries it, held to the status and assignee this
# run read. --check and --dry-run write nothing and take no lock. Every gc call
# made while the lock is held runs with its descriptor closed, so no process a
# call starts, such as a Dolt server, keeps the lock after this script ends, and
# the lock is freed once the close has landed, before the branch is ended.
#
# The edge goes on just before the close, the order `bd duplicate` and
# `bd supersede` write the two in. So this writer's close names its
# successor, and a second caller finds the first one's choice on the bead, a
# reopened bead included, and refuses to name another (exit 6). Those two commands
# close unchecked, past a gate and an open child, record no reason, and refuse a
# successor in another store (specs/tk-1tfzr71.13/gas-city-search.md). bd keeps
# one edge per pair of beads and none per bead, so two callers that read the origin
# before either wrote can each add an edge. The edge is therefore read back before
# the close, and a caller that finds another disposition edge beside its own takes
# its own back and stops. A close that then does not land takes the edge back too,
# and leaves it only when a close naming this same successor is what beat it.
# Callers naming one successor share one edge, and bd's dep add and dep remove take
# no compare-and-set, so one caller's take-back can reach the edge another's close
# relies on. So each reads after it acts (settle_edge): a closer once its close has
# landed, and a caller once it has taken its edge back. A take-back before the
# closer's read is seen by the closer, and one after it comes after the close, so
# the caller sees the close. Whichever finds a close naming this successor with no
# edge puts the edge on.
#
# The close is gated on EVIDENCE the script re-establishes itself:
#   (a) EVERY kind: the origin is not a review, step or workflow bead, and it is
#       not in_progress under another actor.
#   (b) fixed-upstream and duplicate also: the origin did no work
#       (gc.work_outcome=no-op, accepted even beside a work-product key a
#       rebase or rework twin leaves behind, or no work_outcome and none of
#       branch, work_dir, gc.work_dir, pr_number, pr_url, merge_result or
#       gc.work_commit), so an origin with unlanded work is refused, and the
#       successor is in the same store. Under fixed-upstream the successor is
#       also closed or work_outcome=shipped: the fix has landed. A duplicate
#       closes at once, open canonical or closed, because the canonical carries
#       the work. An origin carrying the operator's pre-recorded PR-close
#       disposition for this kind and successor (pr-dispose.sh) is a ruling
#       already made, and (b) does not re-judge it.
#   The judgment kinds re-homed, folded and not-needed are held to (a) only, and
#   a non-closed merge_result does not bar them, because the judgment is the
#   caller's (docs/authority-map.md, Close-with-successor).
# A duplicate's close must not end the waits on it early, and bd's ready rule
# follows a blocks edge but never a duplicates edge. So before a duplicate of a
# canonical that has neither closed nor shipped closes, each open bead it blocks
# gains a blocks edge onto the canonical. One that has it already,
# and the canonical itself, need none. A waiter that cannot take the edge
# refuses the close before anything is written: one joined to the canonical by
# another edge type, since bd keeps one edge per pair, and any waiter when the
# canonical is in another store, where the edge holds nothing. A waiter bd
# refuses the edge, for a cycle or a parent chain, refuses the close too, and the
# edges added before it stay, true while the origin duplicates the canonical.
# bd's close neither reads nor refuses what waits on the bead, so a bead can come
# to wait on the duplicate after that read. The read is made again once the close
# has landed (carry_late), and a waiter it finds gains its edge then. One whose
# edge lands after that read waits on a closed bead, which holds nothing, as a
# wait on any closed bead does.
# Every other kind ends its waits with the close: fixed-upstream once the fix
# has landed, the judgment kinds on the caller's judgment.
# --check evaluates those gates and the duplicate's waits, and exits 0
# (eligible) or non-zero (refused, with the reason on stderr), writing nothing.
#
# A `blocks` edge from the origin onto its successor is a wait the disposition
# ends, and bd keeps one edge per pair of beads, so it is dropped just before the
# close and put back when the close does not land.
# A caller that reports its own refusals of the close as human gates names their
# key with --except-key. The retry reads what would hold the close: the origin's
# live blockers and open children, and the template, the pin and the assignee
# an unforced close refuses, which lets the close through only for an origin no
# one is assigned or one assigned to exactly the actor it runs as. When anything
# but its own unassigned gates under the key would hold it, nothing is written.
# Otherwise it resolves those gates with a reason that names the retry and
# carries no outcome word, so no quiet period starts, and then closes. A run
# that stops after the withdrawal leaves a state the next run completes,
# because a resolved gate stays resolved. With --except-key, --check reads the
# same holds, so a caller that answers those gates itself, such as
# stand-down.sh, can stop before its first write.
# An already-closed origin is the REPAIR path: it gains the edge, read back the
# same way, and an appended note, with the gates skipped and no wait moved (the
# close they would guard already happened). The note is written only while the
# origin still has the status and assignee this run read, the one write bd can
# hold to that, so a reopen or a claim since the read takes the edge back and
# records nothing on the bead someone else now holds.
# Once the origin is closed, on either path, the branch it names in
# metadata.branch is ended on the git remote through branch-end.sh, the way a
# merge ends a landed branch. That remote write never gates the disposition:
# when the branch cannot be ended the close stands, and a warning names the
# branch and the command that ends it. The bead's notes record the outcome.
# The writer records no outcome of its own on the origin: the outcome is its
# closer's word.
# Callers: converse dispositions, operator re-homes, pr-facts.sh (a PR closed
# with a pre-recorded disposition, and that branch's parked rework children),
# stand-down.sh (a person's ruling that work a human gate holds will not go
# on), scaffolding-sweep.sh (a finding a disposed PR leaves unanswered, closed
# onto the bug that carries it).
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
# The composable "may this bead be finalized?" precondition set, asked before
# anything is written. An open human gate that blocks the origin holds its
# close, a pinned one included, which bd's own close does not count, the same
# precondition merge.sh applies to a merge (docs/finalize-gate.md). Overridable
# for a test.
FINALIZE_GATE="${GC_FINALIZE_GATE_TOOL:-$HERE/finalize-gate.sh}"
# Ends the retired branch on the git remote once the close has landed.
# Overridable for a test.
BRANCH_END="${GC_BRANCH_END_TOOL:-$HERE/branch-end.sh}"
# The rule of which human gates still hold a bead, $HUMAN_GATE_JQ, which the
# retry's withdrawal reads its own gates by, and the reading of a disposition,
# $DISPOSITION_JQ. This script reads through bd_at, so it takes the rules and
# none of the library's store reads.
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

Closes the origin and records its successor in bd's own edge from it:
`duplicates` under --kind duplicate, `supersedes` under every other kind.

Under every kind but not-needed the successor is the bead that carries the
work now. Under not-needed nothing carries it, and the successor is the
evidence that concluded the bead was unnecessary — typically the conversation
the ruling was given in. It is required either way.

The close is refused unless the evidence holds (see the header): every kind
needs the origin to be a plain work bead no other session holds;
fixed-upstream and duplicate additionally need the origin to have done no work
and the successor in the same store, and fixed-upstream needs the successor
closed or shipped, unless the origin carries the operator's pre-recorded
PR-close disposition for that kind and successor.

A duplicate of a canonical that has neither closed nor shipped first gives
each open bead blocked by it a blocks edge onto the canonical, so its close
releases none of them before the canonical delivers. A waiter that cannot take
that edge refuses the close. A bead that comes to wait on the duplicate after
that read gains the edge just after the close.

The edge goes on just before the close, and is read back. The close is bd's
checked close, applied only while the origin still has the status and assignee
this run judged: a live blocker, an open human gate, an open child or a change
since the read refuses it, and then the edge comes back off, and nothing stays
written but the edges a duplicate's waiters gained, which the refusal names, and
the gates a retry resolved, as below.

The close takes the store's record lock (pr-record.lock in the origin store's
.beads directory) before it reads the origin, waiting up to
$PR_RECORD_LOCK_WAIT_SECS (300) while a writer of a PR's pending record holds
it, and clears the landing order's marker, pr_reconcile_pending, in its own
write when the origin carries it. A closed origin that already records this
disposition and still carries the marker has it cleared in a write of its own,
which lands only while the origin has the status and assignee this run read
(exit 4 otherwise).

--check evaluates that evidence and a duplicate's waiters, and exits 0
(eligible) or non-zero (refused, reason on stderr) without writing anything.
With --except-key it also reads what would hold the close.

Stores are derived from each bead id's prefix via `gc rig list --json`;
pass --origin-store/--successor-store when a prefix is ambiguous.
An already-closed origin gains the edge and an appended note (repair path),
with the evidence gates skipped. A reopen or a claim since the read leaves it
unrecorded (exit 4).

--except-key is for the caller that reports its own refusals of this close as
human gates through human-gate.sh: it names the situation key that caller files
them under. A gate under that key that no person is assigned does not hold the
retry it asks for, and the retry resolves it just before the close, because an
open gate makes the close refuse the bead it blocks. A gate assigned to a
person still holds, and so does every gate under any other key, every other
live blocker and every open child: then nothing is resolved or closed.

Exit: 0 disposed (or already recorded) · 1 --check refused · 2 a store does not
resolve · 3 the origin or successor does not exist · 4 a write did not land: the
origin changed since it was judged, or a waiter's edge onto the canonical or the
origin's own edge did not write or read back, or a write after the close did not
land, which leaves the close standing · 5 the close is held or refused, a
waiter that cannot wait on the canonical included · 6 the origin already names
another successor, read before any write or beside this run's own edge · 7 the
evidence refuses the close · 64 usage
U
    exit "${1:-1}"
}

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

# The kind shapes the edge and the note, so it is a closed set. All but one say
# the work RELOCATED and the successor carries it now; under not-needed nothing
# carries it and the successor is the evidence that concluded the bead was
# unnecessary. The successor is required under both readings: a close that
# names nothing is indistinguishable from a careless one whatever ended the bead.
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

# The id-prefix derivation lives in bead-store.sh, so an edge's far end and the
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
        gc bd --db "$db/.beads" --actor "$ACTOR" "$@" 9>&-
    else
        gc bd --db "$db/.beads" "$@" 9>&-
    fi
}

# The store's record lock (the header's rule), taken on fd 9 before the origin
# is read and held through the close. PR_RECORD_LOCK_WAIT_SECS bounds the wait:
# a run of the landing order holds the lock for one record at a time, and its
# order's 300-second time limit frees it at the latest.
RECORD_LOCK_WAIT="${PR_RECORD_LOCK_WAIT_SECS:-300}"
case "$RECORD_LOCK_WAIT" in ''|*[!0-9]*) RECORD_LOCK_WAIT=300 ;; esac
take_record_lock() {
    local lock="$ORIGIN_PATH/.beads/pr-record.lock"
    command -v flock >/dev/null 2>&1 \
        || die "flock is not on PATH, so the store's record lock ($lock) cannot be taken; nothing written, $ORIGIN untouched" 5
    exec 9>>"$lock" \
        || die "the store's record lock ($lock) does not open; nothing written, $ORIGIN untouched" 5
    flock -w "$RECORD_LOCK_WAIT" 9 \
        || die "another writer of a PR's pending record held the store's record lock ($lock) for ${RECORD_LOCK_WAIT}s; nothing written, $ORIGIN untouched. Re-run this close" 5
}
release_record_lock() { exec 9>&-; }

# bead_row <repo-path> <id> — the bead's `gc bd list` row as a one-element
# array, the shape every read below takes. The list row, unlike `show`, carries
# an edge onto a bead in another store. Gates, infrastructure beads and
# templates are listed too, so no bead reads as absent for its type. Empty when
# the store does not hold the bead or does not answer.
bead_row() {
    bd_at "$1" list --id "$2" --all --include-gates --include-infra --include-templates --json --limit 0 2>/dev/null \
        | grep -a -vE '^gc bd:' | scrub \
        | jq -c --arg id "$2" '[ .[]? | select(((.id // "") | tostring) == $id) ] | select(length == 1)' 2>/dev/null || true
}

# The successor is checked first and hardest: an edge onto a bead that does not
# exist reads as a resolved disposition and resolves to nothing.
SUCC_JSON=$(bead_row "$SUCCESSOR_PATH" "$SUCCESSOR")
[ -n "$SUCC_JSON" ] \
    || die "successor $SUCCESSOR does not exist in $SUCCESSOR_STORE ($SUCCESSOR_PATH/.beads) — nothing written, origin $ORIGIN untouched" 3

[ -n "$CHECK$DRY_RUN" ] || take_record_lock
ORIGIN_JSON=$(bead_row "$ORIGIN_PATH" "$ORIGIN")
[ -n "$ORIGIN_JSON" ] \
    || die "origin $ORIGIN does not exist in $ORIGIN_STORE ($ORIGIN_PATH/.beads) — nothing written" 3
# The landing order's marker, which the close clears in its own write.
CLEAR_MARKER=()
if printf '%s' "$ORIGIN_JSON" | jq -e '(.[0].metadata // {}) | has("pr_reconcile_pending")' >/dev/null 2>&1; then
    CLEAR_MARKER=(--unset-metadata pr_reconcile_pending)
fi

ORIGIN_STATUS=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
# The status and assignee the gates below judge, as the store holds them. The
# close is conditional on both.
JUDGED_STATUS=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].status // "") | tostring' 2>/dev/null || true)
JUDGED_ASSIGNEE=$(printf '%s' "$ORIGIN_JSON" | jq -r '(.[0].assignee // "") | tostring' 2>/dev/null || true)

# With no identity of its own, a caller's writes run as bd's default actor, which
# only bd can name, since gc runs it in the store's directory and git's user.name
# resolves there. The gates compare an assignee with that actor, so it is read off
# bd's preview of a create, which writes nothing. An answer that does not read
# leaves it empty, and close_guard holds an assigned origin.
if [ -z "$ACTOR" ] && [ -n "$JUDGED_ASSIGNEE" ]; then
    ACTOR=$(bd_at "$ORIGIN_PATH" create "bead-rehome actor read" --dry-run --json 2>/dev/null \
        | grep -a -vE '^gc bd:' | scrub \
        | jq -r 'if type == "array" then .[0] else . end | (.created_by // "") | tostring' 2>/dev/null || true)
fi

case "$KIND" in
    duplicate) EDGE_TYPE=duplicates ;;
    *)         EDGE_TYPE=supersedes ;;
esac

# The edge the origin already carries onto the successor, by type, or empty.
# bd keeps one edge per pair, so its type decides what the disposition does.
PAIR_TYPE=$(printf '%s' "$ORIGIN_JSON" | jq -r --arg s "$SUCCESSOR" \
    '[.[0].dependencies[]? | select(((.depends_on_id // "") | tostring) == $s) | ((.type // "") | tostring)] | .[0] // ""' \
    2>/dev/null || true)
# other_successor <origin-row> — a bead other than this successor that one of the
# row's disposition edges names, or nothing. Every edge counts, not only the first
# a reader takes.
other_successor() {
    printf '%s' "$1" | jq -r --arg s "$SUCCESSOR" "$DISPOSITION_JQ"'
        [ .[0].dependencies[]? | select(disposition_edge) | edge_target | select(. != $s) ] | .[0] // ""' 2>/dev/null || true
}
# A disposition the origin already records, onto another bead, is somebody
# else's decision.
PRIOR_SUCC=$(other_successor "$ORIGIN_JSON")
if [ -n "$PRIOR_SUCC" ]; then
    die "origin $ORIGIN already names $PRIOR_SUCC as its successor (a duplicates or supersedes edge); refusing to record another disposition over it — reconcile the two by hand" 6
fi
case "$PAIR_TYPE" in
    ''|blocks|duplicates|supersedes) ;;
    *) die "origin $ORIGIN already joins $SUCCESSOR by a '$PAIR_TYPE' edge, and bd keeps one edge per pair of beads, so the $EDGE_TYPE edge cannot be recorded beside it. Remove it with gc bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR, then re-run this close" 6 ;;
esac
if [ -n "$PAIR_TYPE" ] && [ "$PAIR_TYPE" != blocks ] && [ "$PAIR_TYPE" != "$EDGE_TYPE" ]; then
    die "origin $ORIGIN already names $SUCCESSOR through a '$PAIR_TYPE' edge, which records another kind of disposition than --kind $KIND; refusing to rewrite it — reconcile the two by hand" 6
fi
# This disposition's edge is on the origin already: an earlier run wrote it.
EDGE_STANDS=""
[ "$PAIR_TYPE" != "$EDGE_TYPE" ] || EDGE_STANDS=1

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

    # (b) The evidence kinds assert a specific claim, that this bead's work is
    # carried or already delivered elsewhere, so they carry the burden of
    # proving it. The judgment kinds (re-homed, folded, not-needed) carry the
    # caller's judgment, which this script does not re-judge, so a non-closed
    # merge_result does not bar them: the converse retire path disposes an
    # in-flight anchor through here on the operator's ruling. An origin
    # carrying the operator's pre-recorded PR-close disposition for this kind
    # and successor (pr-dispose.sh) is that ruling already made, read from the
    # store rather than taken from the caller, so (b) does not re-judge it. An
    # automated caller passes a judgment kind only on its own proof.
    if ruled_disposition; then
        return 0
    fi
    case "$KIND" in
        fixed-upstream|duplicate)
            [ "$SUCCESSOR_STORE" = "$ORIGIN_STORE" ] \
                || { GATE_REASON="a $KIND close needs the successor $SUCCESSOR in the same store as $ORIGIN ($ORIGIN_STORE); it is $SUCCESSOR_STORE. Judge a cross-store successor by hand"; return 1; }
            # A fix upstream has to have landed. A duplicate's canonical carries
            # the work whatever its state, so the duplicate closes at once.
            if [ "$KIND" = fixed-upstream ]; then
                local sstatus soutcome
                sstatus=$(printf '%s' "$SUCC_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
                soutcome=$(printf '%s' "$SUCC_JSON" | jq -r '.[0].metadata["gc.work_outcome"] // .[0].metadata["work_outcome"] // ""' 2>/dev/null || true)
                if [ "$sstatus" != "closed" ] && [ "$soutcome" != "shipped" ]; then
                    GATE_REASON="a $KIND close needs the successor $SUCCESSOR closed or work_outcome=shipped; it is ${sstatus:-unreadable} and has not shipped"; return 1
                fi
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

# What holds the close, read and not written, for the close and for --check
# alike. <origin-row> is a bead_row answer. It sets OWN_GATES, the ids of the
# origin's own gates under --except-key, and at most one of: HOLD_UNREAD, the
# read that did not answer, so nothing proves the close clear; HELD_BY, the
# other live blockers and the open child that hold it; and CLOSE_GUARD, what an
# unforced close would refuse on. The wait edge onto the successor holds
# nothing here, because the close drops it first. With no --except-key no gate
# is the origin's own, so every live blocker holds: that is the read a
# duplicate's close makes before its waiters gain their edges.
except_key_holds() { # <origin-row>
    OWN_GATES=""; HOLD_UNREAD=""; HELD_BY=""; CLOSE_GUARD=""
    local blk_json other_blockers kids_json open_kid
    # Which of the gates are open is bd-lib.sh's open_human_gate rule. Every other
    # live blocker and every open child holds the close, and with one standing
    # the gates stay open and nothing closes. Any other blocker that is closed or
    # pinned holds nothing, as in bd.
    blk_json=$(bd_at "$ORIGIN_PATH" dep list "$ORIGIN" --type blocks --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true)
    if ! printf '%s' "$blk_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        HOLD_UNREAD="its blockers did not read, so whether anything${EXCEPT_KEY:+ besides its own [$EXCEPT_KEY] gates} holds the close is unknown"
        return 0
    fi
    OWN_GATES=$(printf '%s' "$blk_json" | jq -r --arg k "$EXCEPT_KEY" "$HUMAN_GATE_JQ"'
        .[] | select($k != "" and open_human_gate($k) and ((.assignee // "") | tostring) == "") | .id' 2>/dev/null || true)
    other_blockers=$(printf '%s' "$blk_json" | jq -r --arg k "$EXCEPT_KEY" --arg dropped "$SUCCESSOR" "$HUMAN_GATE_JQ"'
        [ .[] | select(((.status // "open") | tostring) as $st | $st != "closed" and $st != "pinned")
              | select(($k != "" and open_human_gate($k) and ((.assignee // "") | tostring) == "") | not)
              | select((.id // "") != $dropped)
              | .id ] | join(" ")' 2>/dev/null || true)
    kids_json=$(bd_at "$ORIGIN_PATH" list --parent "$ORIGIN" --include-gates --include-infra --include-templates --json --limit 1 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true)
    if ! printf '%s' "$kids_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        HOLD_UNREAD="its children did not read, so whether an open child holds the close is unknown"
        return 0
    fi
    open_kid=$(printf '%s' "$kids_json" | jq -r '.[0].id // empty' 2>/dev/null || true)
    if [ -n "$other_blockers" ] || [ -n "$open_kid" ]; then
        HELD_BY="${other_blockers:+blocker(s) $other_blockers}"
        [ -z "$open_kid" ] || HELD_BY="${HELD_BY:+$HELD_BY and }open child $open_kid"
        return 0
    fi
    # Withdrawing the gates ahead of a close that is then refused would take
    # the question away from the person it asks, and the caller's next refused
    # retry would file it again, so the close's own guards are read here too.
    CLOSE_GUARD=$(close_guard "$1")
    return 0
}

# close_guard <origin-row> — what bd's unforced `bd close` refuses on whatever
# the bead's status, printed, or nothing: a template, a pinned bead, and a bead
# assigned to anyone but the actor the close runs as. The guarded update this
# writer closes through refuses a template and applies bd's blocker and child
# policy, but not the pin or the assignee, so these are read off the origin's
# row before anything is written, and any of them holds the close. bd compares the assignee with the --actor it is given
# and with no other name of this session, so only an origin no one is
# assigned, or one assigned to exactly $ACTOR, goes on to the close.
close_guard() {
    printf '%s' "$1" | jq -r --arg actor "$ACTOR" --arg who "${ACTOR:-the actor bd defaults to}" '.[0]
        | ((.assignee // "") | tostring) as $as
        | if (.is_template // false) == true then "it is a template, which bd never closes"
          elif ((.status // "") | tostring | ascii_downcase) == "pinned" or (.pinned // false) == true
            then "it is pinned, which bd closes only by force"
          elif $as != "" and $as != $actor
            then "it is assigned to \($as), and bd closes an assigned bead only for its assignee, while this close runs as \($who)"
          else empty end' 2>/dev/null || true
}

# list_rows <ids, space-separated> — those beads' `gc bd list` rows from the
# origin's store, whose edges carry `type` and `depends_on_id`, or nothing when
# the store does not answer.
list_rows() {
    bd_at "$ORIGIN_PATH" list --id "$(printf '%s' "$1" | tr ' ' ',')" --all --include-gates --include-infra --include-templates --json --limit 0 2>/dev/null \
        | grep -a -vE '^gc bd:' | scrub || true
}

# carry_plan — the waits a duplicate's close would end before its canonical
# has delivered, read and not written (the header's rule). It sets CARRY, the
# beads the origin blocks that need a blocks edge onto the canonical; CARRY_HELD,
# why one cannot take it, so the close must not run; CARRY_UNREAD, the read that
# did not answer; and CARRY_NONE, why no wait moves, for the dry run.
CARRY=""; CARRY_HELD=""; CARRY_UNREAD=""; CARRY_NONE=""
carry_plan() {
    CARRY=""; CARRY_HELD=""; CARRY_UNREAD=""; CARRY_NONE=""
    if [ "$KIND" != duplicate ]; then
        CARRY_NONE="a $KIND close moves no wait"; return 0
    fi
    local sstatus soutcome up_json waiting rows_json w t conflicts=""
    sstatus=$(printf '%s' "$SUCC_JSON" | jq -r '(.[0].status // "") | ascii_downcase' 2>/dev/null || true)
    soutcome=$(printf '%s' "$SUCC_JSON" | jq -r '.[0].metadata["gc.work_outcome"] // .[0].metadata["work_outcome"] // ""' 2>/dev/null || true)
    if [ "$sstatus" = closed ] || [ "$soutcome" = shipped ]; then
        CARRY_NONE="$SUCCESSOR has closed or shipped, so a wait on $ORIGIN may end with its close"; return 0
    fi
    up_json=$(bd_at "$ORIGIN_PATH" dep list "$ORIGIN" --direction=up --type blocks --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true)
    # The canonical's own wait on the duplicate ends with the close: the work it
    # waits for is its own.
    if ! waiting=$(printf '%s' "$up_json" | jq -er --arg s "$SUCCESSOR" '
            if type != "array" then error("not an array") else
              [ .[] | select(((.status // "open") | tostring | ascii_downcase) != "closed")
                    | (.id // "") | tostring | select(. != "" and . != $s) ] | unique | join(" ")
            end' 2>/dev/null); then
        CARRY_UNREAD="the beads $ORIGIN blocks did not read, so whether its close would release one before $SUCCESSOR has delivered is unknown"
        return 0
    fi
    if [ -z "$waiting" ]; then
        CARRY_NONE="no open bead waits on $ORIGIN"; return 0
    fi
    if [ "$SUCCESSOR_STORE" != "$ORIGIN_STORE" ]; then
        CARRY_HELD="$ORIGIN blocks $waiting, and its canonical $SUCCESSOR is in $SUCCESSOR_STORE, where a blocks edge from $ORIGIN_STORE holds nothing, so its close releases them before $SUCCESSOR has delivered. Give each one that must still wait a human gate that names $SUCCESSOR, and end each one's wait on $ORIGIN with gc bd --db $ORIGIN_PATH/.beads dep remove <bead> $ORIGIN"
        return 0
    fi
    rows_json=$(list_rows "$waiting")
    if ! printf '%s' "$rows_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
        CARRY_UNREAD="the beads $ORIGIN blocks ($waiting) did not read, so whether each can come to wait on $SUCCESSOR is unknown"
        return 0
    fi
    for w in $waiting; do
        # The waiter's own edge onto the canonical, by type, or "?" when its
        # row is missing from the listing.
        t=$(printf '%s' "$rows_json" | jq -r --arg w "$w" --arg s "$SUCCESSOR" '
            [ .[] | select(((.id // "") | tostring) == $w) ] as $r
            | if ($r | length) != 1 then "?"
              else [ $r[0].dependencies[]? | select(((.depends_on_id // "") | tostring) == $s) | ((.type // "") | tostring) ] | (.[0] // "")
              end' 2>/dev/null || printf '?')
        case "$t" in
            '?') CARRY_UNREAD="$ORIGIN blocks $w, whose row did not read, so whether it can come to wait on $SUCCESSOR is unknown"; return 0 ;;
            blocks) ;;
            '') CARRY="${CARRY:+$CARRY }$w" ;;
            *) conflicts="${conflicts:+$conflicts, }$w by a '$t' edge" ;;
        esac
    done
    if [ -n "$conflicts" ]; then
        CARRY_HELD="$ORIGIN blocks beads already joined to $SUCCESSOR, $conflicts, and bd keeps one edge per pair of beads, so they cannot come to wait on $SUCCESSOR and its close releases them before $SUCCESSOR has delivered. Replace each such edge with a blocks edge (gc bd --db $ORIGIN_PATH/.beads dep remove <bead> $SUCCESSOR, then dep add <bead> $SUCCESSOR --type blocks), or end its wait by hand"
    elif [ -z "$CARRY" ]; then
        CARRY_NONE="every open bead $ORIGIN blocks already waits on $SUCCESSOR"
    fi
    return 0
}

# carry_waits — the writes carry_plan planned. Each bead in $CARRY gains its
# blocks edge onto the canonical. The close that follows releases those beads
# and cannot be taken back, so an edge bd refuses stops the disposition before
# its close. The edges added before it stay: each is true while the origin
# duplicates the canonical, and a run that closed the origin first needs them.
# CARRIED names them.
CARRIED=""
carried_left() { # the sentence a refusal after the carry ends on, or nothing
    [ -n "$CARRIED" ] || return 0
    printf ' %s keep the blocks edge onto %s they gained; if %s turns out not to duplicate %s, remove each with gc bd --db %s/.beads dep remove <bead> %s.' \
        "$CARRIED" "$SUCCESSOR" "$ORIGIN" "$SUCCESSOR" "$ORIGIN_PATH" "$SUCCESSOR"
}
carry_waits() {
    CARRIED=""
    [ -n "$CARRY" ] || return 0
    local w err
    for w in $CARRY; do
        if ! err=$(bd_at "$ORIGIN_PATH" dep add "$w" "$SUCCESSOR" --type blocks 2>&1 >/dev/null); then
            printf '%s\n' "$err" >&2
            die "$ORIGIN blocks $w, and bd refused $w a blocks edge onto $SUCCESSOR, as printed above, so closing $ORIGIN would release $w before $SUCCESSOR has delivered. Nothing is closed.$(carried_left) Judge the refusal; $RERUN" 5
        fi
        CARRIED="${CARRIED:+$CARRIED }$w"
    done
    return 0
}

if [ "$ORIGIN_STATUS" != "closed" ]; then
    if ! gates_pass; then
        if [ -n "$CHECK" ]; then
            echo "bead-rehome: --check refused: $GATE_REASON" >&2
            exit 1
        fi
        die "$GATE_REASON — nothing written, $ORIGIN untouched" 7
    fi
    carry_plan
fi
if [ -n "$CHECK" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        echo "bead-rehome: --check: $ORIGIN is already closed — the repair path adds the edge only, no close is gated"
    else
        if [ -n "$CARRY_UNREAD$CARRY_HELD" ]; then
            echo "bead-rehome: --check refused: ${CARRY_UNREAD:-$CARRY_HELD}" >&2
            exit 1
        fi
        if [ -n "$EXCEPT_KEY" ]; then
            # The gate reads the origin as the close will leave it, disposed,
            # which is how a stewarded epic's disposition passes it.
            FG_REASON=""
            if ! FG_REASON=$("$FINALIZE_GATE" check "$ORIGIN" --except-key "$EXCEPT_KEY" --as-disposed 2>/dev/null); then
                echo "bead-rehome: --check refused: the close is held: ${FG_REASON:-finalize gate refused (fail-closed)}" >&2
                exit 1
            fi
            except_key_holds "$ORIGIN_JSON"
            HOLD_WHY="$HOLD_UNREAD"
            [ -z "$HELD_BY" ] || HOLD_WHY="the close is held by $HELD_BY"
            [ -z "$CLOSE_GUARD" ] || HOLD_WHY="bd would refuse its close: $CLOSE_GUARD"
            if [ -n "$HOLD_WHY" ]; then
                echo "bead-rehome: --check refused: $HOLD_WHY" >&2
                exit 1
            fi
        fi
        printf 'bead-rehome: --check: %s is eligible to close as "%s"%s\n' "$ORIGIN" "$REASON" \
            "${CARRY:+, once $CARRY, which it blocks, wait on $SUCCESSOR too}"
    fi
    exit 0
fi

# The branch a bead names in metadata.branch; empty when it names none or the
# answer does not parse.
origin_branch() {
    printf '%s' "$1" | jq -r '(.[0].metadata.branch // "") | tostring' 2>/dev/null || true
}

if [ -n "$DRY_RUN" ]; then
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        CLOSE_PLAN="already closed — edge + note only, the close left as it is"
    else
        MARKER_PLAN=""
        [ "${#CLEAR_MARKER[@]}" -eq 0 ] || MARKER_PLAN=", clearing the landing order's pr_reconcile_pending marker in the same write, under the store's record lock"
        CLOSE_PLAN="bd's checked close while $ORIGIN is still ${JUDGED_STATUS:-?} and ${JUDGED_ASSIGNEE:-unassigned}, noting \"$REASON\"$MARKER_PLAN"
    fi
    if [ -n "$EDGE_STANDS" ]; then
        EDGE_PLAN="none ($ORIGIN already names $SUCCESSOR)"
    elif [ "$ORIGIN_STATUS" = "closed" ]; then
        EDGE_PLAN="$ORIGIN $EDGE_TYPE $SUCCESSOR, in $ORIGIN_STORE, read back"
    else
        EDGE_PLAN="$ORIGIN $EDGE_TYPE $SUCCESSOR, in $ORIGIN_STORE, read back before the close and taken back if the close does not land"
    fi
    if [ "$PAIR_TYPE" = blocks ] && [ "$ORIGIN_STATUS" != "closed" ]; then
        WAIT_PLAN="drop the 'blocked by $SUCCESSOR' wait edge for the disposition's edge, and put it back if the close does not land"
    else
        WAIT_PLAN="none ($ORIGIN carries no wait edge to $SUCCESSOR)"
    fi
    if [ "$ORIGIN_STATUS" = "closed" ]; then
        WAITERS_PLAN="none (the close already happened)"
    elif [ -n "$CARRY_UNREAD$CARRY_HELD" ]; then
        WAITERS_PLAN="the close would be refused: ${CARRY_UNREAD:-$CARRY_HELD}"
    elif [ -n "$CARRY" ]; then
        WAITERS_PLAN="$CARRY, which $ORIGIN blocks, each gain a blocks edge onto $SUCCESSOR before the close"
    else
        WAITERS_PLAN="none ($CARRY_NONE)"
    fi
    PLAN_BRANCH=$(origin_branch "$ORIGIN_JSON")
    if [ -n "$PLAN_BRANCH" ]; then
        PLAN_CMD=$(printf '%q ' "$BRANCH_END" --rig "${ORIGIN_STORE#rig:}" --branch "$PLAN_BRANCH" --bead "$ORIGIN" --dry-run)
        BRANCH_PLAN="end $PLAN_BRANCH on the git remote of $ORIGIN_STORE once the close lands, unless a live owner names it (${PLAN_CMD% } previews it)"
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
    printf 'bead-rehome (dry run)\n  origin:    %s [%s] in %s\n  successor: %s in %s\n  waiters:   %s\n  wait:      %s\n  edge:      %s\n  gates:     %s\n  close:     %s\n  branch:    %s\n  actor:     %s\n' \
        "$ORIGIN" "${ORIGIN_STATUS:-unknown}" "$ORIGIN_STORE" \
        "$SUCCESSOR" "$SUCCESSOR_STORE" "$WAITERS_PLAN" "$WAIT_PLAN" "$EDGE_PLAN" "$GATE_PLAN" \
        "$CLOSE_PLAN" "$BRANCH_PLAN" "${ACTOR:-<bd default>}"
    exit 0
fi

RERUN="re-run this call once it is cleared"

# What this run wrote on the origin ahead of a close, so that a close that does
# not land can take it back.
EDGE_ADDED=""; WAIT_DROPPED=""

# undo_edges — take back this run's disposition edge, then put back the wait it
# replaced, since bd keeps one edge per pair. An edge this run found on the origin
# was not this run's to take. Another caller naming this successor can share the
# edge, so settle_edge reads first: a close of theirs keeps the edge and ended the
# wait.
undo_edges() {
    local wait="$WAIT_DROPPED"
    WAIT_DROPPED=""
    if [ -n "$EDGE_ADDED" ]; then
        EDGE_ADDED=""
        bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 \
            || echo "bead-rehome: WARN the $EDGE_TYPE edge from $ORIGIN onto $SUCCESSOR did not come back off, so $ORIGIN names $SUCCESSOR with no close behind it; take it off with gc bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR" >&2
    elif [ -z "$wait" ]; then
        return 0
    fi
    settle_edge || true
    if [ -n "$wait" ] && [ -z "$CLOSE_NAMED" ]; then
        bd_at "$ORIGIN_PATH" dep add "$ORIGIN" "$SUCCESSOR" --type blocks >/dev/null 2>&1 \
            || echo "bead-rehome: WARN the '$ORIGIN blocked by $SUCCESSOR' wait edge was dropped for the close and did not go back; restore it with gc bd --db $ORIGIN_PATH/.beads dep add $ORIGIN $SUCCESSOR --type blocks" >&2
    fi
    return 0
}

# write_edge — add the disposition edge and read it back, the read the header's
# rule rests on. Whichever order two callers' writes and reads fall in, the later
# writer reads both edges. EDGE_STOP says why it did not stand, and the exit status
# is the one this run ends on.
EDGE_STOP=""
write_edge() {
    local err="" row other
    EDGE_STOP=""
    if ! err=$(bd_at "$ORIGIN_PATH" dep add "$ORIGIN" "$SUCCESSOR" --type "$EDGE_TYPE" 2>&1 >/dev/null); then
        printf '%s\n' "$err" >&2
        EDGE_STOP="the $EDGE_TYPE edge from $ORIGIN onto $SUCCESSOR did not write"
        return 4
    fi
    EDGE_ADDED=1
    row=$(bead_row "$ORIGIN_PATH" "$ORIGIN")
    other=$(other_successor "$row")
    if [ -n "$other" ]; then
        EDGE_STOP="another caller named $other as the successor of $ORIGIN while this run was naming $SUCCESSOR"
        return 6
    fi
    if ! printf '%s' "$row" | jq -e --arg s "$SUCCESSOR" --arg t "$EDGE_TYPE" \
            'any(.[0].dependencies[]?; ((.depends_on_id // "") | tostring) == $s and ((.type // "") | tostring) == $t)' >/dev/null 2>&1; then
        EDGE_STOP="the $EDGE_TYPE edge from $ORIGIN onto $SUCCESSOR did not read back, so whether another caller named another successor is unknown"
        return 4
    fi
    return 0
}

# record_edge — the edge ahead of a close or a repair's note. So that two callers
# cannot both leave a successor, the later writer takes its own back. Two that read
# after both wrote both stand down, and a re-run judges the bead as it then stands.
# An edge an earlier run wrote is not written again.
record_edge() {
    [ -z "$EDGE_STANDS" ] || return 0
    local rc=0
    write_edge || rc=$?
    case "$rc" in
        0) return 0 ;;
        6) undo_edges
           die "$EDGE_STOP, so this run took its edge back and closes nothing.$(carried_left) Reconcile the two by hand" 6 ;;
        *) undo_edges
           die "$EDGE_STOP, so this run closes nothing.$(carried_left) Re-run this call" 4 ;;
    esac
}

# closed_naming <origin-row> — the row reads closed with a note naming this
# successor: a close this disposition's edge records, whoever's it was.
closed_naming() {
    printf '%s' "$1" | jq -e --arg named " $SUCCESSOR in $SUCCESSOR_STORE" '
        ((.[0].status // "") | tostring | ascii_downcase) == "closed"
        and ((.[0].notes // "") | tostring | contains($named))' >/dev/null 2>&1
}

# settle_edge — the read each side of a shared edge makes after it acts (the
# header's rule). When a close naming this successor stands and no disposition edge
# names it, the edge goes on. CLOSE_NAMED says such a close stands. The exit status
# is 0, or what a run owes for an edge it could not put on, which the same call run
# again records through the repair path.
CLOSE_NAMED=""
settle_edge() {
    local row rc=0
    CLOSE_NAMED=""
    row=$(bead_row "$ORIGIN_PATH" "$ORIGIN")
    if [ -z "$row" ]; then
        echo "bead-rehome: WARN $ORIGIN did not read after its edge changed, so whether a close naming $SUCCESSOR stands without that edge is unknown; if it does, the same call run again records it" >&2
        return 4
    fi
    closed_naming "$row" || return 0
    CLOSE_NAMED=1
    printf '%s' "$row" | jq -e --arg s "$SUCCESSOR" "$DISPOSITION_JQ"'
        any(.[0].dependencies[]?; disposition_edge and edge_target == $s)' >/dev/null 2>&1 && return 0
    write_edge || rc=$?
    EDGE_ADDED=""
    case "$rc" in
        0) printf 'bead-rehome: %s is closed naming %s and its %s edge had gone, so it is back\n' "$ORIGIN" "$SUCCESSOR" "$EDGE_TYPE" ;;
        6) bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 \
               || echo "bead-rehome: WARN the $EDGE_TYPE edge it put back onto $SUCCESSOR did not come off again" >&2
           echo "bead-rehome: WARN $ORIGIN is closed naming $SUCCESSOR, but $EDGE_STOP; reconcile the two by hand" >&2 ;;
        *) echo "bead-rehome: WARN $ORIGIN is closed naming $SUCCESSOR, but $EDGE_STOP; the same call run again records it" >&2 ;;
    esac
    return "$rc"
}

# carry_late — the second read of what waits on a duplicate, once its close has
# landed (the header's rule). A wait it cannot move is too late to refuse: the close
# stands, the run ends on exit 4, and the note says so, because a caller that runs
# this script for its exit status drops its output.
AFTER_CLOSE_RC=0
carry_late() {
    [ "$KIND" = duplicate ] || return 0
    local w err moved="" why stop
    carry_plan
    why="${CARRY_UNREAD:-$CARRY_HELD}"
    for w in $CARRY; do
        if err=$(bd_at "$ORIGIN_PATH" dep add "$w" "$SUCCESSOR" --type blocks 2>&1 >/dev/null); then
            moved="${moved:+$moved }$w"
        else
            why="${why:+$why; }bd refused $w a blocks edge onto $SUCCESSOR ($err)"
        fi
    done
    [ -z "$moved" ] || printf 'bead-rehome: %s came to wait on %s as it closed, and wait on %s now\n' "$moved" "$ORIGIN" "$SUCCESSOR"
    [ -n "$why" ] || return 0
    stop="$ORIGIN has closed, and what came to wait on it after this run first read its waiters did not all move to $SUCCESSOR, so a bead can go ready before $SUCCESSOR has delivered: $why. What waits on it: gc bd --db $ORIGIN_PATH/.beads dep list $ORIGIN --direction=up --type blocks"
    echo "bead-rehome: WARN $stop" >&2
    bd_at "$ORIGIN_PATH" update "$ORIGIN" --append-notes "$stop" >/dev/null 2>&1 \
        || echo "bead-rehome: WARN could not record that on $ORIGIN" >&2
    AFTER_CLOSE_RC=4
}

if [ "$ORIGIN_STATUS" = "closed" ]; then
    # The repair path: the close happened earlier, so the edge and a note record
    # the disposition now. A note says when it was recorded, because the close
    # it explains predates it.
    if [ -n "$EDGE_STANDS" ] && [ "${#CLEAR_MARKER[@]}" -eq 0 ]; then
        printf 'bead-rehome: %s already records this disposition (%s %s) — nothing to do\n' \
            "$ORIGIN" "$EDGE_TYPE" "$SUCCESSOR"
    elif [ -n "$EDGE_STANDS" ]; then
        # The disposition is recorded, but the close that made it left the
        # landing order's marker on the bead, and a run of the order reopens a
        # closed bead that carries the marker with no verified merge. So the
        # marker clears now, in a write held to the status and assignee this
        # run read, as the repair's note is below.
        if ! bd_at "$ORIGIN_PATH" update "$ORIGIN" \
                --if-status="$JUDGED_STATUS" --if-assignee="$JUDGED_ASSIGNEE" \
                "${CLEAR_MARKER[@]}" \
                --append-notes "Disposition confirmed $(date -u +%Y-%m-%dT%H:%MZ): $REASON. The landing order's pending-record marker is cleared, so no run of the order reopens this closed bead." \
                >/dev/null 2>&1; then
            die "$ORIGIN already records this disposition ($EDGE_TYPE $SUCCESSOR), but the landing order's pr_reconcile_pending marker did not clear under the status and assignee this run read (${JUDGED_STATUS}, ${JUDGED_ASSIGNEE:-unassigned}): a reopen, a claim or an assignment landed since, or the store did not answer. While the marker stands, a run of the landing order reopens the closed bead. Re-run to judge it as it stands now" 4
        fi
        printf 'bead-rehome: %s already records this disposition (%s %s); the landing order'\''s pr_reconcile_pending marker is cleared\n' \
            "$ORIGIN" "$EDGE_TYPE" "$SUCCESSOR"
    else
        # A wait onto the successor that a forced close left behind ends with
        # the disposition, and bd keeps one edge per pair.
        if [ "$PAIR_TYPE" = blocks ]; then
            bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 \
                || die "could not drop the '$ORIGIN blocked by $SUCCESSOR' wait edge, which stands where the $EDGE_TYPE edge goes; nothing recorded. Clear it with gc bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR, then re-run this call" 4
            WAIT_DROPPED=1
        fi
        record_edge
        # bd takes no compare-and-set on an edge, so the guarded note is what shows
        # the bead was still closed under the same assignee once the edge stood. A
        # reopen or a claim since the read leaves that holder's bead as they have it.
        if ! bd_at "$ORIGIN_PATH" update "$ORIGIN" \
                --if-status="$JUDGED_STATUS" --if-assignee="$JUDGED_ASSIGNEE" \
                ${CLEAR_MARKER[@]+"${CLEAR_MARKER[@]}"} \
                --append-notes "Disposition recorded $(date -u +%Y-%m-%dT%H:%MZ): $REASON. (Recorded after the close.)" \
                >/dev/null 2>&1; then
            undo_edges
            die "the disposition note on $ORIGIN did not write under the status and assignee this run read (${JUDGED_STATUS}, ${JUDGED_ASSIGNEE:-unassigned}), so a reopen, a claim or an assignment landed since, or the store did not answer, and nothing is recorded on it. Re-run to judge it as it stands now" 4
        fi
        EDGE_ADDED=""; WAIT_DROPPED=""
        printf 'bead-rehome: %s was ALREADY closed in %s — its successor is recorded now (%s %s).\n' \
            "$ORIGIN" "$ORIGIN_STORE" "$EDGE_TYPE" "$SUCCESSOR"
    fi
else
    # What holds the close is read before anything is written, so a held close
    # writes nothing. The finalize gate holds it on an open human gate, and
    # reads the origin as the close will leave it, disposed, which is how a
    # stewarded epic's disposition passes it. The release is to clear the gate,
    # then re-run this close.
    FG_ARGS=(check "$ORIGIN" --as-disposed)
    if [ -n "$EXCEPT_KEY" ]; then FG_ARGS+=(--except-key "$EXCEPT_KEY"); fi
    if ! FG_REASON=$("$FINALIZE_GATE" "${FG_ARGS[@]}" 2>/dev/null 9>&-); then
        die "the close of $ORIGIN is held: ${FG_REASON:-finalize gate refused (fail-closed)}. Nothing is recorded; clear what holds it, then re-run this close" 5
    fi
    GUARD=$(close_guard "$ORIGIN_JSON")
    [ -z "$GUARD" ] \
        || die "bd would refuse the close of $ORIGIN: $GUARD. Nothing is recorded" 5
    # The retry's own gates, and what else would hold the close once they go.
    if [ -n "$EXCEPT_KEY" ]; then
        except_key_holds "$ORIGIN_JSON"
        [ -z "$HOLD_UNREAD" ] \
            || die "$HOLD_UNREAD; nothing was resolved or closed. Re-run this close." 5
        [ -z "$HELD_BY" ] \
            || die "$ORIGIN is held by $HELD_BY, so its own [$EXCEPT_KEY] gates stay open and nothing closes; $RERUN" 5
        [ -z "$CLOSE_GUARD" ] \
            || die "bd would refuse the close of $ORIGIN: $CLOSE_GUARD. Its own [$EXCEPT_KEY] gates stay open and nothing closes" 5
    fi

    # A duplicate's waiters, read before the first write: one that cannot come to
    # wait on the canonical holds the close, and so does anything bd's close
    # would refuse on, so no waiter gains an edge for a close that is refused.
    [ -z "$CARRY_UNREAD" ] || die "$CARRY_UNREAD; nothing written. Re-run this close." 5
    [ -z "$CARRY_HELD" ] || die "$CARRY_HELD, then re-run this close. Nothing written" 5
    if [ -n "$CARRY" ] && [ -z "$EXCEPT_KEY" ]; then
        except_key_holds "$ORIGIN_JSON"
        [ -z "$HOLD_UNREAD" ] || die "$HOLD_UNREAD; nothing written. Re-run this close." 5
        [ -z "$HELD_BY" ] \
            || die "$ORIGIN is held by $HELD_BY, so bd would refuse its close, and nothing is written; $RERUN" 5
    fi
    carry_waits

    # The wait onto the successor ends with the disposition, bd refuses to close
    # a bead it blocks, and bd keeps one edge per pair, so the wait gives way to
    # the disposition's edge. Both come back undone when the close does not land,
    # so a held close leaves the wait as it was.
    if [ "$PAIR_TYPE" = blocks ]; then
        bd_at "$ORIGIN_PATH" dep remove "$ORIGIN" "$SUCCESSOR" >/dev/null 2>&1 \
            || die "could not drop the '$ORIGIN blocked by $SUCCESSOR' wait edge, and while it stands bd refuses the close; nothing closed.$(carried_left) Clear it with gc bd --db $ORIGIN_PATH/.beads dep remove $ORIGIN $SUCCESSOR, then re-run this close" 5
        WAIT_DROPPED=1
    fi
    record_edge

    # The withdrawal: the gates the caller filed under its key ask for this
    # retry, and bd refuses the close while one blocks the origin. Nothing else
    # holds the close by now. The reason names the retry and carries no outcome
    # word, because the close has not landed yet: no quiet period starts.
    if [ -n "$EXCEPT_KEY" ]; then
        GATE_REASON="Withdrawn by bead-rehome.sh just before it retries the close this gate reported: $REASON"
        for GATE in $OWN_GATES; do
            if ! bd_at "$ORIGIN_PATH" gate resolve "$GATE" --reason "$GATE_REASON" >/dev/null 2>&1; then
                undo_edges
                die "the store refused the resolve of the gate $GATE [$EXCEPT_KEY] on $ORIGIN, and while it is open bd refuses the close; nothing closed.$(carried_left) Re-run this close." 5
            fi
            printf 'bead-rehome: withdrew the gate %s [%s] on %s before the close it asked for\n' "$GATE" "$EXCEPT_KEY" "$ORIGIN"
        done
    fi

    # The close: bd's checked close, never --force, which would also override a
    # foreign assignee and an open child. It lands only while the origin still
    # has the status and assignee the gates judged, so a claim, an assignment or
    # a status change since that read, a second closer's included, closes nothing
    # (exit 13). The note rides the same write, and names the beads that came to
    # wait on the canonical.
    CLOSE_RC=0; CLOSE_ERR=""
    CLOSE_ERR=$(bd_at "$ORIGIN_PATH" update "$ORIGIN" \
        --if-status="$JUDGED_STATUS" --if-assignee="$JUDGED_ASSIGNEE" --status=closed \
        ${CLEAR_MARKER[@]+"${CLEAR_MARKER[@]}"} \
        --append-notes "Disposition $(date -u +%Y-%m-%dT%H:%MZ): $REASON.${CARRIED:+ What waited on it waits on $SUCCESSOR now: $CARRIED.}" 2>&1 >/dev/null) || CLOSE_RC=$?
    if [ "$CLOSE_RC" = 13 ]; then
        # A close naming this same successor is what beat this one: the edge is
        # its record as well, and the wait ended with it.
        if closed_naming "$(bead_row "$ORIGIN_PATH" "$ORIGIN")"; then
            EDGE_ADDED=""; WAIT_DROPPED=""
        fi
        undo_edges
        if [ -n "$JUDGED_ASSIGNEE" ]; then JUDGED_HOLDER="under $JUDGED_ASSIGNEE"; else JUDGED_HOLDER="and unassigned"; fi
        die "$ORIGIN is no longer $JUDGED_STATUS $JUDGED_HOLDER, as this run read it before judging it: a claim, an assignment, a status change or another close landed since, so nothing is recorded and $ORIGIN is not closed by this run.$(carried_left) Re-run to judge it as it stands now" 4
    elif [ "$CLOSE_RC" != 0 ]; then
        undo_edges
        printf '%s\n' "$CLOSE_ERR" >&2
        die "the close of $ORIGIN was refused, as printed above, so nothing is recorded and it stays open.$(carried_left) Judge the refusal; $RERUN" 5
    fi
    EDGE_ADDED=""; WAIT_DROPPED=""
    printf 'bead-rehome: %s closed in %s — %s (%s %s)\n' "$ORIGIN" "$ORIGIN_STORE" "$REASON" "$EDGE_TYPE" "$SUCCESSOR"
    [ -z "$CARRIED" ] || printf 'bead-rehome: %s, which %s blocked, wait on %s now\n' "$CARRIED" "$ORIGIN" "$SUCCESSOR"
    settle_edge || AFTER_CLOSE_RC=$?
    carry_late
fi

# End the branch the retired bead names on the git remote, the way a merge ends
# a landed one. The bead is closed by now: a close that did not land stopped the
# run above. branch-end.sh holds the remote write and its guards. It keeps a
# branch a live owner names, so a bead reopened since this run's read keeps its
# branch, pins the tip, and deletes only the tip it checked. The disposition is
# complete before this runs, so a branch it cannot end costs a warning, never
# the close.
release_record_lock
RETIRED_BRANCH=$(origin_branch "$ORIGIN_JSON")
if [ -n "$RETIRED_BRANCH" ]; then
    # Quoted for a paste: a branch name may carry shell metacharacters.
    END_CMD=$(printf '%q ' "$BRANCH_END" --rig "${ORIGIN_STORE#rig:}" --branch "$RETIRED_BRANCH" --bead "$ORIGIN")
    END_CMD="${END_CMD% }"
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
    # The bead records what became of its branch. pr-facts.sh runs this
    # script for its exit status and drops its output, so the note is what a
    # later reader finds. A re-run that reaches the same outcome adds nothing,
    # so the notes are read before the append.
    if [ -n "$END_NOTE" ]; then
        case "$(bead_row "$ORIGIN_PATH" "$ORIGIN" | jq -r '.[0].notes // ""' 2>/dev/null || true)" in
            *"$END_NOTE"*) ;;
            *) bd_at "$ORIGIN_PATH" update "$ORIGIN" --append-notes "$END_NOTE" >/dev/null 2>&1 \
                   || echo "bead-rehome: WARN could not record the branch's outcome on $ORIGIN: $END_NOTE" >&2 ;;
        esac
    fi
fi

printf 'bead-rehome: attribution is in the store events table, not the issues row:\n  gc dolt sql -q "SELECT issue_id, event_type, actor, created_at FROM %s.events WHERE issue_id = '"'"'%s'"'"' ORDER BY created_at"\n' \
    "${ORIGIN%%-*}" "$ORIGIN"
exit "$AFTER_CLOSE_RC"
