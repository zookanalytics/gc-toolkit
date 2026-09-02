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
# The route is proved against the live agent set before anything is created,
# and an already-open visit carrying an unroutable route is repointed rather
# than counted as a satisfied escalation. A rig-qualified --pool also selects
# the store the visit lands in, so route and store cannot disagree.
# A CLOSED visit answers too: a situation a sitting closed `moot` or `benign`
# is not re-filed for GC_ESCALATE_VERDICT_WINDOW seconds (default 86400, 0
# disables), and each suppressed repeat is tallied on that visit.
# Exit: 0 filed, already open, repointed or inside the verdict window · 1 unroutable/could not file/verify · 2 usage
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
  --pool     converse pool to route to; default gc-toolkit.converse, qualified
             with GC_RIG. The route must name a live agent identity that reads
             this rig's store, so a caller with GC_RIG unset must pass this
             explicitly — the unqualified default matches no rig-scoped pool.
             A rig-qualified pool also selects the store, so the two agree.

env:
  GC_ESCALATE_VERDICT_WINDOW  seconds a `moot` or `benign` verdict suppresses
             a re-file of the same situation (default 86400). A detector whose
             condition outlives the sitting re-raises it every cycle otherwise,
             and each repeat costs a sitting to reach the same answer. 0
             disables the window. To raise a situation that has genuinely
             changed, give it a new --key rather than widening this.
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

# GC_RIG selects the store `gc bd` reads and writes, outranking BEADS_DIR and
# the working directory, and a pool offer is claimed only by an agent that
# reads that store. A rig-less caller naming a rig-qualified pool therefore
# adopts that rig: one flag names the route and the store, and they agree.
POOL_RIG="${POOL_ARG%%/*}"
if [ -z "${GC_RIG:-}" ] && [ -n "$POOL_ARG" ] && [ "$POOL_RIG" != "$POOL_ARG" ]; then
  export GC_RIG="$POOL_RIG"
  warn "GC_RIG unset; adopting rig '$POOL_RIG' from --pool so the visit lands in the store that pool reads"
fi

bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

# The route gate is pool-route.sh, shared with every other copy of this
# block: one implementation decides what "addresses somebody" means, so a
# caller cannot drift from it by re-deriving the answer in its own copy.
SELF_DIR=$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")
POOL_ROUTE="$SELF_DIR/pool-route.sh"
[ -x "$POOL_ROUTE" ] || { warn "pool-route.sh not found beside this script ($POOL_ROUTE); no route can be proved, so nothing is filed"; exit 1; }
# ok | unknown | cross-rig | no-identity, for a route this script did not write.
route_verdict() { "$POOL_ROUTE" --verdict "$1"; }

HEADLINE=$(printf '%s' "$MESSAGE" | head -n 1 | cut -c1-100)

# >>> gate-visit
# Canonical gate-visit shape (formulas/mol-visit.toml); gate-visit.test.sh
# checks this copy's invariants. escalation_key rides its own flag beside it.
# The pool is resolved at each point that WRITES it, never up here: an
# escalation whose visit is already open and routable has already asked its
# human, and a default pool that call never needed must not turn it into a
# failure.
POOL_NAME="${POOL_ARG:-gc-toolkit.converse}"

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
# The matched row's own route rides the listing too: a visit nothing can claim
# has asked nobody, so counting it as satisfied is the same mute one pass
# later.
#
# An unreadable listing files anyway — a duplicate visit is a bounded nuisance,
# a silent mute is the failure this replaces.
case "$SUBJECT" in
  *-wisp-*) SUBJECT_IS_EPHEMERAL=1 ;;
  *)        SUBJECT_IS_EPHEMERAL=0 ;;
esac
if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
  DEDUP_SCOPE="[$KEY]"
  OPEN_ROW=$(bd_json list --status=open,in_progress --metadata-field "escalation_key=$KEY" --limit=20 \
    | jq -r --arg k "$KEY" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k) | [.id, (.metadata["gc.routed_to"] // "")] | @tsv) else empty end' 2>/dev/null \
    | head -n 1)
else
  DEDUP_SCOPE="$SUBJECT [$KEY]"
  OPEN_ROW=$(bd_json list --status=open,in_progress --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=20 \
    | jq -r --arg k "$KEY" --arg s "$SUBJECT" \
        'if type == "array" then (.[] | select((.metadata.escalation_key // "") == $k and (.metadata["gc.continuation_group"] // "") == $s) | [.id, (.metadata["gc.routed_to"] // "")] | @tsv) else empty end' 2>/dev/null \
    | head -n 1)
fi
OPEN="${OPEN_ROW%%$'\t'*}"; OPEN_ROUTE=""
case "$OPEN_ROW" in *$'\t'*) OPEN_ROUTE="${OPEN_ROW#*$'\t'}" ;; esac
if [ -n "$OPEN" ]; then
  case "$(route_verdict "$OPEN_ROUTE")" in
    ok)
      echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — not filing another"
      exit 0 ;;
    unknown)
      echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — not filing another; its route '$OPEN_ROUTE' is UNVERIFIED"
      exit 0 ;;
  esac
  POOL=$("$POOL_ROUTE" "$POOL_NAME") || exit 1
  warn "visit $OPEN is open for $DEDUP_SCOPE but routes to '$OPEN_ROUTE', which no live pool claims — repointing it at '$POOL'."
  gc bd update "$OPEN" --set-metadata "gc.routed_to=$POOL" >/dev/null 2>&1
  OPEN_GOT=$(bd_json show "$OPEN" | jq -r '.[0].metadata["gc.routed_to"] // ""' 2>/dev/null)
  if [ "$OPEN_GOT" != "$POOL" ]; then
    warn "the repoint did not land on $OPEN (route reads '$OPEN_GOT'); repair: gc bd update $OPEN --set-metadata gc.routed_to=$POOL"
    exit 1
  fi
  echo "escalate: visit $OPEN already open for $DEDUP_SCOPE — repointed to $POOL, not filing another"
  exit 0
fi

# A closed visit carries a VERDICT, and two of them say a human was not needed:
# `moot` (the premise no longer holds) and `benign` (it holds but needs nobody).
# The converse role stamps them on gc.outcome before it closes
# (agents/converse/prompt.template.md). Nothing read them back, and the dedup
# above only sees OPEN visits, so a detector whose condition outlives the
# sitting re-filed the identical situation on its next cycle and spent another
# one. This window is where that verdict is honored.
#
# The newest closed visit for the situation decides, across every outcome. Only
# moot and benign suppress; any other outcome means the sitting acted, so the
# next occurrence stands on different ground and an older moot behind a newer
# ruling cannot mute it. A situation that has CHANGED takes a new key by the
# rule at the top of this file, so the window cannot trap a new signal behind an
# old answer.
#
# The newest is chosen by timestamp across the whole closed set, not a page of
# it, because a truncated listing could return an older verdict as though it
# were the latest.
#
# Suppression is COUNTED, never silent — this script exists to end silent
# mutes. The tally rides the visit that earned the verdict, so a recurrence
# costs one in-place update instead of a bead per cycle, and a situation that
# recurs relentlessly reports how many sittings the window saved.
VERDICT_WINDOW="${GC_ESCALATE_VERDICT_WINDOW:-86400}"
case "$VERDICT_WINDOW" in ''|*[!0-9]*) VERDICT_WINDOW=86400 ;; esac
if [ "$VERDICT_WINDOW" -gt 0 ]; then
  if [ "$SUBJECT_IS_EPHEMERAL" = 1 ]; then
    VERDICT_SUBJECT=""
    VERDICT_RAW=$(bd_json list --status=closed --metadata-field "escalation_key=$KEY" --limit=0)
  else
    VERDICT_SUBJECT="$SUBJECT"
    VERDICT_RAW=$(bd_json list --status=closed --metadata-field "escalation_key=$KEY" \
      --metadata-field "gc.continuation_group=$SUBJECT" --limit=0)
  fi
  # Re-checked field by field for the same reason the open listing is: a
  # listing that silently ignored a filter would suppress everything.
  VERDICT_ROW=$(printf '%s' "$VERDICT_RAW" | jq -r --arg k "$KEY" --arg s "$VERDICT_SUBJECT" '
    if type != "array" then empty else
      [ .[]
        | select((.metadata.escalation_key // "") == $k)
        | select($s == "" or (.metadata["gc.continuation_group"] // "") == $s)
        | { id: .id,
            outcome: (.metadata["gc.outcome"] // ""),
            n: (((.metadata["escalation.recurrences"] // "0") | tonumber?) // 0),
            at: (((.closed_at // "") | fromdateiso8601?) // 0) }
        | select(.at > 0) ]
      | sort_by(.at)
      | last
      | if . == null then empty
        elif (.outcome == "moot" or .outcome == "benign")
        then [ .id, .outcome, ((now - .at) | floor | tostring), (.n | tostring) ] | @tsv
        else empty end
    end' 2>/dev/null)
  if [ -n "$VERDICT_ROW" ]; then
    V_ID="${VERDICT_ROW%%	*}";   V_REST="${VERDICT_ROW#*	}"
    V_OUTCOME="${V_REST%%	*}";  V_REST="${V_REST#*	}"
    V_AGE="${V_REST%%	*}";      V_COUNT="${V_REST#*	}"
    case "$V_AGE$V_COUNT" in *[!0-9]*) V_AGE=""; V_COUNT="" ;; esac
    if [ -n "$V_AGE" ] && [ "$V_AGE" -lt "$VERDICT_WINDOW" ]; then
      V_COUNT=$((V_COUNT + 1))
      gc bd update "$V_ID" \
        --set-metadata "escalation.recurrences=$V_COUNT" \
        --set-metadata "escalation.recurrence_last=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 \
        || warn "could not record the recurrence on $V_ID; the suppression below still stands"
      echo "escalate: $DEDUP_SCOPE was answered '$V_OUTCOME' ${V_AGE}s ago on visit $V_ID — not filing another inside ${VERDICT_WINDOW}s (recurrence $V_COUNT). A situation that has CHANGED takes a new --key; GC_ESCALATE_VERDICT_WINDOW=0 disables the window."
      exit 0
    fi
  fi
fi

POOL=$("$POOL_ROUTE" "$POOL_NAME") || exit 1
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
# re-claim fence — and here also this script's own dedup listing for a
# durable subject. Repair and warn, never exit — this block files the one
# visit for its scope, and on a persistent miss the tracks edge still
# carries the subject for guards that read the union.
GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
if [ "$GROUP_GOT" != "$SUBJECT" ]; then
  echo "gate-visit: warning: gc.continuation_group on $VISIT read back as '$GROUP_GOT', expected '$SUBJECT' — repairing" >&2
  gc bd update "$VISIT" --set-metadata "gc.continuation_group=$SUBJECT" || true
  GROUP_GOT=$(gc bd show "$VISIT" --json | tr -d '[:cntrl:]' | jq -r '.[0].metadata["gc.continuation_group"] // ""' 2>/dev/null || printf '')
  if [ "$GROUP_GOT" = "$SUBJECT" ]; then
    echo "gate-visit: the repair landed on $VISIT" >&2
  else
    echo "gate-visit: warning: the repair did not land on $VISIT — the tracks edge still carries the subject, and the live-visit guards read the union" >&2
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
