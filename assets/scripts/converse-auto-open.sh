#!/usr/bin/env bash
# converse-auto-open.sh — open a converse on an operator's just-filed visit, so a
# prefix+a topic becomes a live conversation instead of a row that parks on the
# helm board and waits for a manual engage.
#
# The force-to-visit invariant (first-reaction-dispose.sh, spec tk-diqxx9) stands:
# every operator-origin subject still reaches a visit. This completes that visit
# by spawning its sitting; it does not bypass it. The visit is filed first, by
# the caller; this engages it with `gc-helm engage <visit> --no-attach`, the same
# spawn the board picker runs (tmux-pick-helm.sh) — the operator attaches later
# from the session picker, and converse-idle-recycle reclaims the slot if nobody
# ever does.
#
# Scope is LIVE interactive intake, and the discriminator is a one-shot marker,
# never gc.origin=operator. gc.origin is permanent and rides every operator
# subject, including stale ones a scan re-reacts; auto-engaging on it would spawn
# a converse with no human present — the d407b8c3 runaway. gc.interactive_intake
# is stamped ONLY by gc-visit-open's live keystroke path and is CONSUMED here the
# moment it is read, so a replayed or scan-driven reaction finds nothing to arm
# and this is a no-op. Fail-safe direction: every uncertain path ends with the
# visit PARKED (manual engage still works), never with a headless auto-open.
#
# Concurrency: CONVERSE_AUTO_OPEN_CAP bounds how many auto-opened, not-yet-attended
# converse visits may stand at once in the subject's rig. Firing several prefix+a
# and walking away must not stack speculative sittings against the converse
# session slots; past the cap this parks the visit and says so.
#
# Usage:
#   converse-auto-open.sh --subject <subject-id> [--visit <visit-id>] [--dry-run]
# --visit is resolved from the subject's single parked visit when omitted (the
# gc-visit-open fallback path does not capture the id gc-helm open prints).
# Exit: 0 engaged, or cleanly declined (not a live intake, cap reached, visit not
# engageable) — the visit is in a good state either way · 2 usage.
set -u

PROG="converse-auto-open"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$HERE/gc-helm.sh}"
GC="${CONVERSE_AUTO_OPEN_GC:-gc}"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but LF
# go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting consumers
# downstream split jq's own @tsv.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

note() { printf '%s: %s\n' "$PROG" "$*" >&2; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
usage() { printf 'Usage: %s --subject <subject-id> [--visit <visit-id>] [--dry-run]\n' "$PROG" >&2; }

SUBJECT=""; VISIT=""; DRY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --subject) shift; [ $# -gt 0 ] || { note "--subject needs a value"; exit 2; }; SUBJECT="$1"; shift ;;
        --subject=*) SUBJECT="${1#--subject=}"; shift ;;
        --visit) shift; [ $# -gt 0 ] || { note "--visit needs a value"; exit 2; }; VISIT="$1"; shift ;;
        --visit=*) VISIT="${1#--visit=}"; shift ;;
        --dry-run|-n) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) note "unknown flag '$1'"; usage; exit 2 ;;
        *) note "unexpected argument '$1'"; usage; exit 2 ;;
    esac
done
[ -n "$SUBJECT" ] || { note "needs --subject <subject-id>"; usage; exit 2; }

# ── Cap: a per-rig integer with a safe default ───────────────────────────────
# A non-numeric override is a silent mis-compare, not just a bad bound, so fall
# back rather than trust it (the liveness-sweep.sh pattern).
CAP="${CONVERSE_AUTO_OPEN_CAP:-2}"
case "$CAP" in ''|*[!0-9]*) CAP=2 ;; esac

# ── The arming marker: read, then CONSUME before anything can branch ─────────
# One read decides the whole run, and consuming it here — before the cap check,
# before the engage — is what makes the arming one-shot: a retried or replayed
# reaction on the same subject finds it gone and declines. An unreadable subject
# is not evidence of a live intake, so an empty read declines too (positive
# finding only).
ARMED=$("$GC" bd show "$SUBJECT" --json 2>/dev/null | scrub \
    | jq -r 'if type == "array" then ((.[0].metadata // {})["gc.interactive_intake"] // "") else "" end' 2>/dev/null || printf '')
if [ "$ARMED" != "1" ]; then
    note "subject $SUBJECT carries no live gc.interactive_intake marker — not a live interactive intake; leaving it parked"
    exit 0
fi
if [ -z "$DRY" ]; then
    "$GC" bd update "$SUBJECT" --unset-metadata gc.interactive_intake >/dev/null 2>&1 \
        || note "warning: could not consume gc.interactive_intake on $SUBJECT; proceeding (a stale marker only ever costs a later decline)"
fi

# ── Resolve the visit when the caller did not name it ────────────────────────
# The subject's single OPEN, UNASSIGNED (parked) visit is the one this intake just
# filed. More than one parked visit is an ambiguity this path will not guess at —
# leave them for a manual engage; none means nothing to open.
if [ -z "$VISIT" ]; then
    PARKED=$("$GC" bd list --status=open --json --limit=0 2>/dev/null | scrub \
        | jq -r --arg s "$SUBJECT" '
            [ .[]? | select((.metadata.task_kind // "") == "visit")
                   | select((.assignee // "") == "")
                   | select(((.metadata["gc.continuation_group"] // "") == $s)
                        or ([ .dependencies[]? | select((.dependency_type // .type // "") == "tracks")
                                | select((.depends_on_id // .id // "") == $s) ] | length > 0)) ]
            | sort_by(.created_at // "") | .[].id' 2>/dev/null || printf '')
    PARKED_N=$(printf '%s\n' "$PARKED" | grep -c . || true)
    if [ "$PARKED_N" -eq 0 ]; then
        note "no parked visit on $SUBJECT to open — leaving it to the board"
        exit 0
    fi
    if [ "$PARKED_N" -gt 1 ]; then
        note "$SUBJECT has $PARKED_N parked visits ($(printf '%s' "$PARKED" | tr '\n' ' ' | sed 's/ *$//')); not guessing which to open — leaving them to a manual engage"
        exit 0
    fi
    VISIT=$(printf '%s\n' "$PARKED" | head -n1)
fi

# ── Cap: count the auto-opened, not-yet-attended visits already standing ─────
# gc.auto_opened lives on the VISIT bead, so this is one open-only bead query in
# the subject's rig — no session fan-out. A recycled sitting has its gc.auto_opened
# cleared (converse-idle-recycle) and an attended one carries gc.auto_open_attended_at,
# so both drop out of the count: the cap bounds the SPECULATIVE auto-opens, the
# ones that hold a slot without a human yet. A failed count does not open a hole
# in the cap — treat an unreadable probe as at-cap.
STANDING=$("$GC" bd list --status=open --metadata-field "gc.auto_opened=1" --json --limit=0 2>/dev/null | scrub \
    | jq -r '[ .[]? | select(((.metadata["gc.auto_open_attended_at"] // "") == "")) ] | length' 2>/dev/null || printf '')
case "$STANDING" in ''|*[!0-9]*) STANDING="$CAP" ;; esac
if [ "$STANDING" -ge "$CAP" ]; then
    note "$STANDING auto-opened visit(s) already standing (cap $CONVERSE_AUTO_OPEN_CAP=${CAP}) — parking $VISIT on the board instead of auto-opening it"
    exit 0
fi

# ── Open the conversation ────────────────────────────────────────────────────
if [ -n "$DRY" ]; then
    printf '%s: would auto-open visit %s on subject %s (%s of %s auto-opens standing)\n' "$PROG" "$VISIT" "$SUBJECT" "$STANDING" "$CAP"
    exit 0
fi

# engage spawns the sitting without attaching and binds the visit. It fails closed
# on a visit that is not open+unassigned (already engaged, blocked, lost race, no
# template in this rig); all of those leave the visit in a state a manual engage
# can still reach, so a refusal is declined, not an error.
if ! "$HELM" engage "$VISIT" --no-attach >&2; then
    note "gc-helm engage declined visit $VISIT (it is not open+unassigned, is blocked, or lost a race) — leaving it parked for a manual engage"
    exit 0
fi

# Stamp the auto-open facts only AFTER a successful spawn: gc.auto_opened marks the
# sitting for converse-idle-recycle and counts toward the cap; gc.auto_opened_at is
# the age clock the recycle timeout reads. A stamp before a failed engage would be a
# phantom auto-open — counted against the cap, swept by a pass that finds no session.
"$GC" bd update "$VISIT" \
    --set-metadata "gc.auto_opened=1" \
    --set-metadata "gc.auto_opened_at=$(now_utc)" >/dev/null 2>&1 \
    || note "warning: engaged $VISIT but could not stamp gc.auto_opened/_at; converse-idle-recycle cannot reclaim this sitting — dismiss it by hand if it is never attended"

printf '%s: auto-opened visit %s on subject %s (--no-attach); attach from the session picker (prefix+S)\n' "$PROG" "$VISIT" "$SUBJECT"
exit 0
