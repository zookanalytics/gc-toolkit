#!/usr/bin/env bash
# escalate.sh — one open visit per situation. Files a board-visible visit on
# the subject bead (the canonical gate-visit shape from formulas/mol-visit.toml)
# stamped with an escalation_key; a later call naming the same situation finds
# the open visit and files nothing. Replaces escalation-gate.sh and every
# patrol `gc mail send` — escalations are visits a human can claim and close.
#   escalate.sh --subject <bead-id> --key <situation-key> --message <text>
#               [--pool <rig-qualified converse pool>]
# Callers: patrol formulas (refinery/witness/deacon), signoff.sh peers, and any
# script that would otherwise mail. A changed situation gets a NEW key.
# Exit: 0 filed or already open · 1 could not file/verify · 2 usage
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: escalate.sh --subject <bead-id> --key <situation-key> --message <text>
                   [--pool <rig-qualified converse pool>]

  --subject  the bead the escalation is about; the visit tracks it (required).
             A durable bead also narrows the dedup to that bead; an ephemeral
             one (a patrol wisp) cannot, so there the key alone is the identity
  --key      names the SITUATION, not the wording: one open visit per key,
             narrowed to the subject when the subject is durable.
             [A-Za-z0-9._-] only (required). To keep two situations apart
             under an ephemeral subject, encode what distinguishes them in
             the key (`wedged-<target>`)
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

bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

# Idempotence: an open (or claimed) visit for this situation means the human is
# already asked. What "this situation" is depends on whether the subject
# carries identity from one call to the next.
#
# A durable subject narrows the situation to one bead — `polecat-blocked` on
# two work beads is two situations — and both filters ride the listing so a
# shared key dedups exactly even when more than the row window carry it;
# subject-side filtering of a truncated window would re-file a duplicate every
# pass. A patrol wisp is burned and re-poured every cycle, so its id cannot
# identify a situation from one call to the next and the conjunction can never
# match. The key alone is the identity there, and a key-only listing cannot be
# truncated past its own match. Either way the matched row is re-checked
# field by field, because a listing that silently ignored a filter would
# suppress everything.
#
# An unreadable listing files anyway — a duplicate visit is a bounded nuisance,
# a silent mute is the failure this replaces.
case "$SUBJECT" in
  *-wisp-*) SUBJECT_IS_EPHEMERAL=1 ;;
  *)        SUBJECT_IS_EPHEMERAL=0 ;;
esac
if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
  DEDUP_SCOPE="[$KEY]"
  OPEN=$(bd_json list --status=open,in_progress --metadata-field "escalation_key=$KEY" --limit=20 \
    | jq -r --arg k "$KEY" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k) | .id) else empty end' 2>/dev/null \
    | head -n 1)
else
  DEDUP_SCOPE="$SUBJECT [$KEY]"
  OPEN=$(bd_json list --status=open,in_progress --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=20 \
    | jq -r --arg k "$KEY" --arg s "$SUBJECT" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == $s) | .id) else empty end' 2>/dev/null \
    | head -n 1)
fi
if [ -n "$OPEN" ]; then
  echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — not filing another"
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
# Read the group stamp back and repair it from the subject if it landed
# empty: it can land present-but-empty while every sibling stamp in the
# same update lands, and an empty group disables converse's group-scoped
# re-claim fence (tk-ax6y4, tk-msfmu) — and here also this script's own
# dedup listing for a durable subject. Repair and warn, never exit — this
# block files the one visit for its scope, and on a persistent miss the
# tracks edge still carries the subject for guards that read the union
# (tk-d6ddn).
GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
if [ "$GROUP_GOT" != "$SUBJECT" ]; then
  echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$SUBJECT' — repairing (tk-ax6y4)" >&2
  gc bd update "$VISIT" --set-metadata "gc.continuation_group=$SUBJECT" || true
  GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
  if [ "$GROUP_GOT" = "$SUBJECT" ]; then
    echo "gate-visit: the repair landed on $VISIT" >&2
  else
    echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union (tk-d6ddn)" >&2
  fi
fi
# <<< gate-visit

# The route and key are what make the visit claimable and the dedup real, so
# both are read back; a visit that did not stamp is repaired by hand. (The
# group stamp is read back and repaired inside the gate-visit block above.)
ROW=$(bd_json show "$VISIT")
GOT_ROUTE=$(printf '%s' "$ROW" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
GOT_KEY=$(printf '%s' "$ROW" | jq -r '.[0].metadata.escalation_key // ""' 2>/dev/null)
if [ "$GOT_ROUTE" != "$POOL" ] || [ "$GOT_KEY" != "$KEY" ]; then
  warn "visit $VISIT was created but its stamps did not read back (route='$GOT_ROUTE' key='$GOT_KEY'); repair: gc bd update $VISIT --set-metadata gc.routed_to=$POOL --set-metadata escalation_key=$KEY"
  exit 1
fi

echo "escalate: filed visit $VISIT on $SUBJECT [$KEY] -> $POOL"
exit 0
