#!/usr/bin/env bash
# escalate.sh — one open visit per situation. Files a board-visible visit on
# the subject bead (the canonical gate-visit shape from formulas/mol-visit.toml)
# stamped with an escalation_key; a later call with the same subject+key finds
# the open visit and files nothing. Replaces escalation-gate.sh and every
# patrol `gc mail send` — escalations are visits a human can claim and close.
#   escalate.sh --subject <bead-id> --key <situation-key> --message <text>
#               [--pool <rig-qualified converse pool>]
# Callers: patrol formulas (refinery/witness/deacon), signoff.sh peers, and any
# script that would otherwise mail. A changed situation gets a NEW key.
# Exit: 0 filed or already open · 1 could not file/verify · 2 usage
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: escalate.sh --subject <bead-id> --key <situation-key> --message <text>
                   [--pool <rig-qualified converse pool>]

  --subject  the bead the escalation is about; the visit tracks it (required)
  --key      names the SITUATION, not the wording: one open visit per
             subject+key, [A-Za-z0-9._-] only (required)
  --message  what the visit needs from a human; first line becomes the
             visit title's headline (required)
  --pool     converse pool to route to; default ${GC_RIG:+$GC_RIG/}gc-toolkit.converse
U
}

warn() { echo "escalate: $*" >&2; }

SUBJECT=""; KEY=""; MESSAGE=""; POOL_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --subject) SUBJECT="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --key)     KEY="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --message) MESSAGE="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --pool)    POOL_ARG="${2:-}"; shift 2 || { usage; exit 2; } ;;
    -h|--help) usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
if [ -z "$SUBJECT" ] || [ -z "$KEY" ] || [ -z "$MESSAGE" ]; then
  warn "--subject, --key and --message are all required"; usage; exit 2
fi
# A '=' or metacharacter in the key breaks the exact-match dedup read.
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac

bd_json() { gc bd "$@" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037'; }

# Idempotence: an open (or claimed) visit for this subject+key means the human
# is already asked. BOTH filters ride the listing itself: a shared key (e.g.
# triage-recurrence across many subjects) must dedup exactly even when more
# than the row window carry it — subject-side filtering of a truncated window
# would re-file a duplicate every pass. An unreadable listing files anyway —
# a duplicate visit is a bounded nuisance, a silent mute is the failure this
# replaces.
OPEN=$(bd_json list --status=open,in_progress --metadata-field "escalation_key=$KEY" \
    --metadata-field "gc.continuation_group=$SUBJECT" --limit=20 \
  | jq -r --arg s "$SUBJECT" \
      'if type == "array" then (.[] | select((.metadata["gc.continuation_group"] // "") == $s) | .id) else empty end' 2>/dev/null \
  | head -n 1)
if [ -n "$OPEN" ]; then
  echo "escalate: visit $OPEN already open for $SUBJECT [$KEY] — not filing another"
  exit 0
fi

HEADLINE=$(printf '%s' "$MESSAGE" | head -n 1 | cut -c1-100)

# >>> gate-visit
# Canonical gate-visit shape (formulas/mol-visit.toml); gate-visit.test.sh
# checks this copy's invariants. escalation_key rides its own flag beside it.
POOL="${GC_RIG:+$GC_RIG/}gc-toolkit.converse"
[ -n "$POOL_ARG" ] && POOL="$POOL_ARG"
VISIT=$(gc bd create -t task --title "visit: $SUBJECT — $HEADLINE" -d "$MESSAGE" --json | jq -r '.id // .[0].id')
[ -n "$VISIT" ] && [ "$VISIT" != "null" ] \
  || { echo "escalate: bd create returned no id — nothing filed; re-run rather than improvising another create form" >&2; exit 1; }
gc bd update "$VISIT" --set-metadata "gc.routed_to=$POOL" \
  --set-metadata "gc.continuation_group=$SUBJECT" \
  --set-metadata "task_kind=visit" \
  --set-metadata "escalation_key=$KEY"
gc bd dep add "$VISIT" "$SUBJECT" --type=tracks
# tracks, NOT parent-child: a parent-child edge transmits the subject's
# blocked state to the visit, unclaimable exactly where conversation is owed.
# <<< gate-visit

# The route and key are what make the visit claimable and the dedup real, so
# both are read back; a visit that did not stamp is repaired by hand.
ROW=$(bd_json show "$VISIT")
GOT_ROUTE=$(printf '%s' "$ROW" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
GOT_KEY=$(printf '%s' "$ROW" | jq -r '.[0].metadata.escalation_key // ""' 2>/dev/null)
if [ "$GOT_ROUTE" != "$POOL" ] || [ "$GOT_KEY" != "$KEY" ]; then
  warn "visit $VISIT was created but its stamps did not read back (route='$GOT_ROUTE' key='$GOT_KEY'); repair: gc bd update $VISIT --set-metadata gc.routed_to=$POOL --set-metadata escalation_key=$KEY"
  exit 1
fi

echo "escalate: filed visit $VISIT on $SUBJECT [$KEY] -> $POOL"
exit 0
