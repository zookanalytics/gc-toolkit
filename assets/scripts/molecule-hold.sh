#!/usr/bin/env bash
# molecule-hold — hold a graph.v2 molecule at the step this shell is executing,
# without closing anything.
#
#   molecule-hold.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]
#
# For the refusal arms that must NOT close: closing advances the graph into the
# next step, and for mol-polecat-work that step recreates the branch and
# destroys a live worker's commits. `open` is the other half of the pool's
# offer predicate, so "decline and leave it open" re-offers the same step to a
# fresh worker every cycle. `blocked` satisfies the not-closed invariant
# without being claimable.
#
# The status write comes before any route clear. gascity's stranded-worker
# repair (unclaimWorkAssignedToRetiredSessionInfo, cmd/gc/session_beads.go)
# sweeps `{open, in_progress}` assigned to a retired session and calls
# ReleaseWorkBead, which re-stamps a run_target fallback "only when otherwise
# unrouted" — so clearing gc.routed_to on a step left open invites the very
# re-route it was meant to prevent. Outside those two statuses the sweep never
# looks.
#
# Blocking before touching any assignee also keeps every write ungated: bd's
# claim guard refuses `--assignee ""` only on an in_progress bead with a live
# holder, and that refusal is atomic over the whole update, so a
# batched status+assignee call can lose the status too.
#
# Every route this script sets out to clear is load-bearing for the caller's
# drain decision, not just for the log: callers drain on exit 0, and a molecule
# still routed anywhere is re-offered however quiet its steps are. So any write
# below the hold that fails exits 1, and a sibling whose route clear failed
# keeps its assignee — the claim is the last thing holding it out of the pool's
# `open + unassigned + routed` offer predicate.
#
# Callers: mol-polecat-work load-context's duplicate-dispatch arm; any polecat
# arm that declines work it must not close.
# exit: 0 the molecule is quiet · 1 the hold did not fully land · 2 refused, nothing written
set -uo pipefail

PROG="molecule-hold"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: molecule-hold.sh --step <formula.step-id> --reason "<text>" [--bead <id>] [--dry-run]

  --step     the step's `gc.step_ref`, e.g. mol-polecat-work.load-context
             (required — half of the identity that makes the write safe)
  --reason   why the molecule is held; stamped as blocked_reason (required)
  --bead     candidate id, e.g. `.bead_id` from `gc hook --claim --json`. A
             HINT: used only if it verifies as this session's bead for --step.
  --dry-run  resolve and report; write nothing.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS name the session; any that are
     set are tried as the assignee.

Closes nothing, and never touches the work bead — record the reason there and
escalate separately.

exit: 0 the molecule is quiet · 1 the hold did not fully land · 2 refused, nothing written
USAGE
}

# `OPT="$2"; shift 2` hangs the parse loop when the option ends argv.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
  case "$2" in
    --step|--reason|--bead|--dry-run|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

STEP=""; REASON=""; HINT=""; DRY_RUN=0; HELD_ALREADY=0; QUIESCE_FAILED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";   shift 2 ;;
    --reason)  require_value "$@"; REASON="$2"; shift 2 ;;
    --bead)    require_value "$@"; HINT="$2";   shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$STEP" ]; then
  echo "$PROG: --step is required — without it there is no way to tell this session's bead for THIS step from its bead for another one" >&2
  usage
  exit 2
fi
case "$STEP" in
  '{{'*'}}')
    echo "$PROG: --step was passed unsubstituted ('$STEP') — the pour did not render it; hold by explicit id and file the pour defect" >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    echo "$PROG: --step must contain only [A-Za-z0-9._-] (got '$STEP')" >&2
    exit 2 ;;
esac
if [ -z "$REASON" ]; then
  echo "$PROG: --reason is required — a hold nobody can read is a stall, and the reason is what a human releases it on" >&2
  usage
  exit 2
fi

bd_json() {
  gc bd "$@" --json 2>/dev/null | scrub
}

IDENTITIES=$(printf '%s\n%s\n%s\n' \
  "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | awk 'NF && !seen[$0]++')
if [ -z "$IDENTITIES" ]; then
  echo "$PROG: no session identity in the environment (GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS all unset) — cannot prove ownership of any bead, refusing to write" >&2
  exit 2
fi

# `index` is exact element equality — `inside`/`contains` match substrings,
# which would let session lx-zzk own lx-zzk9's bead.
verify() { # <id> -> status on a match
  local cand="$1" json
  [ -n "$cand" ] || return 1
  json=$(bd_json show "$cand")
  [ -n "$json" ] || return 1
  printf '%s' "$json" | jq -r --arg step "$STEP" --arg ids "$IDENTITIES" '
    ($ids | split("\n") | map(select(. != ""))) as $me
    | .[0] as $b
    | if $b == null then empty
      elif (($b.metadata["gc.step_ref"] // "") != $step) then empty
      elif (($me | index($b.assignee // "")) == null) then empty
      else ($b.status // "") end
  ' 2>/dev/null
}

discover() { # <status> -> ids, one per line
  local want_status="$1" ident json
  while IFS= read -r ident; do
    [ -n "$ident" ] || continue
    json=$(bd_json list --status="$want_status" --assignee="$ident" --limit=0)
    [ -n "$json" ] || continue
    printf '%s' "$json" | jq -r --arg step "$STEP" '
      if type == "array" then
        .[] | select((.metadata["gc.step_ref"] // "") == $step) | .id
      else empty end
    ' 2>/dev/null
  done <<< "$IDENTITIES"
}

TIER=in_progress
FOUND=$(discover in_progress | sort -u)
N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
if [ "$N" -eq 0 ]; then
  TIER=open
  FOUND=$(discover open | sort -u)
  N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
fi

TARGET=""
if [ -n "$HINT" ]; then
  HINT_STATUS=$(verify "$HINT")
  case "$HINT_STATUS" in
    in_progress|open)
      if [ "$N" -gt 1 ]; then
        echo "$PROG: NOTE — $N $TIER beads match $STEP for this session ($(printf '%s' "$FOUND" | tr '\n' ' ')); using the caller's verified --bead $HINT" >&2
      fi
      TARGET="$HINT" ;;
    blocked)
      TARGET="$HINT"; HELD_ALREADY=1 ;;
    closed)
      echo "$PROG: $HINT ($STEP) is already closed; a closed step is not re-offered, so there is no hold to place" >&2
      exit 0 ;;
    '')
      echo "$PROG: NOTE — --bead $HINT is not this session's bead for $STEP; ignoring the hint and resolving from the store" >&2 ;;
    *)
      echo "$PROG: NOTE — --bead $HINT IS this session's bead for $STEP, but its status is '$HINT_STATUS'; ignoring the hint and resolving from the store" >&2 ;;
  esac
fi

if [ -z "$TARGET" ]; then
  if [ "$N" -eq 1 ]; then
    TARGET=$(printf '%s' "$FOUND" | head -n 1)
  elif [ "$N" -gt 1 ]; then
    echo "$PROG: FATAL — $N $TIER beads match step '$STEP' for this session: $(printf '%s' "$FOUND" | tr '\n' ' ')" >&2
    echo "$PROG: refusing to guess which one this shell is executing. Hold the right one by explicit id (--bead), and treat the duplicate as a graph defect." >&2
    exit 2
  else
    ALREADY=$(discover blocked | sort -u | head -n 1)
    if [ -n "$ALREADY" ]; then
      TARGET="$ALREADY"; HELD_ALREADY=1
    else
      echo "$PROG: FATAL — cannot identify this session's bead for step '$STEP'." >&2
      echo "$PROG:   identities tried: $(printf '%s' "$IDENTITIES" | tr '\n' ' ')" >&2
      echo "$PROG:   The step bead is still claimable and will be re-offered until it is held by explicit id." >&2
      exit 2
    fi
  fi
fi

ROOT=$(bd_json show "$TARGET" | jq -r '.[0].metadata["gc.root_bead_id"] // empty' 2>/dev/null)

if [ "$DRY_RUN" = "1" ]; then
  if [ "$HELD_ALREADY" = "1" ]; then
    echo "$PROG: DRY RUN — $TARGET ($STEP) is already blocked; would de-route root ${ROOT:-<unresolved>} and quiesce that root's other steps"
  else
    echo "$PROG: DRY RUN — would block $TARGET ($STEP), de-route it and root ${ROOT:-<unresolved>}, and quiesce that root's other steps"
  fi
  exit 0
fi

# ── The hold. Status and metadata in one call; both are ungated, so the
# claim guard cannot roll either back. It goes first because every clear below
# it is pointless while the step itself is still claimable.
if [ "$HELD_ALREADY" = "1" ]; then
  echo "$PROG: $TARGET ($STEP) is already blocked; re-checking its root and the root's other steps"
elif ! HOLD_ERR=$(gc bd update "$TARGET" \
      --status=blocked \
      --set-metadata "blocked_reason=$REASON" \
      --unset-metadata gc.routed_to \
      --unset-metadata gc.session_affinity \
      --append-notes "Held at $STEP by ${GC_SESSION_NAME:-${GC_SESSION_ID:-unknown session}}: $REASON" 2>&1); then
  echo "$PROG: FATAL — could not block $TARGET ($STEP); the step is still claimable and the pool will re-offer it." >&2
  [ -n "$HOLD_ERR" ] && echo "$PROG:   $HOLD_ERR" >&2
  exit 1
else
  echo "$PROG: held $TARGET ($STEP) at blocked: $REASON"
fi

# The claim on THIS step is deliberately left in place. Every tier that would
# act on it — the pool offer, the stranded-worker sweep, and drain-ack's
# assigned-work close gate — reads only `open` and `in_progress`, so a blocked
# step is inert whoever holds it, and the retained (assignee, gc.step_ref) pair
# is what lets a re-run and a later reader resolve this bead at all. Sibling
# steps stay `open`, so their claims are not inert and are cleared below.

# Reporting 0 is what lets the caller drain, so it has to mean the whole
# molecule went quiet, not just that the blocking write landed.
finish() {
  if [ "$QUIESCE_FAILED" = "1" ]; then
    echo "$PROG: FATAL — $TARGET ($STEP) is blocked, but the quiesce above is incomplete and this molecule can still be re-offered. Do not drain." >&2
    exit 1
  fi
  exit 0
}

# ── De-route the root. A routed root re-offers the molecule even with every
# step quiet. Metadata-only, so the root's status and assignee are untouched.
if [ -n "$ROOT" ]; then
  ROOT_ROUTE=$(bd_json show "$ROOT" | jq -r '.[0].metadata["gc.routed_to"] // empty' 2>/dev/null)
  if [ -n "$ROOT_ROUTE" ]; then
    if gc bd update "$ROOT" --unset-metadata gc.routed_to >/dev/null 2>&1; then
      echo "$PROG: de-routed root $ROOT (was $ROOT_ROUTE)"
    else
      echo "$PROG: FATAL — could not de-route root $ROOT (was $ROOT_ROUTE); it re-offers this molecule however quiet the steps are" >&2
      QUIESCE_FAILED=1
    fi
  fi
else
  echo "$PROG: NOTE — $TARGET carries no gc.root_bead_id; held the step alone, and a routed root or sibling could still re-offer" >&2
fi

# ── Quiesce the root's other steps. They are pre-assigned by the graph, so
# they sit `open` and assigned inside the stranded-repair sweep's tier; a
# drain-ack with them still assigned is what re-pools the molecule. Route
# first, assignee second: the reverse order leaves a bead briefly
# `open + unassigned + routed`, which is exactly the pool's offer predicate.
[ -n "$ROOT" ] || finish

SIBLINGS=$(bd_json list --status=open,in_progress --limit=0 \
  | jq -r --arg root "$ROOT" --arg self "$TARGET" '
      if type == "array" then
        .[]
        | select((.metadata["gc.root_bead_id"] // "") == $root)
        | select(.id != $self)
        | select((.metadata["gc.step_ref"] // "") | endswith(".workflow-finalize") | not)
        | select(((.metadata["gc.routed_to"] // "") | test("control-dispatcher")) | not)
        | select(((.metadata["gc.routed_to"] // "") != "") or ((.assignee // "") != ""))
        | [.id, (.metadata["gc.step_ref"] // "-"), (.metadata["gc.routed_to"] // ""), (.assignee // "")]
        | @tsv
      else empty end' 2>/dev/null)

[ -n "$SIBLINGS" ] || finish

# A `<<<` here-string is backed by a temp file, and under disk pressure that
# redirection fails silently and runs the loop zero times — indistinguishable
# from a molecule with no other steps. Route it through a checked
# mktemp so an enumeration that could not happen says so.
ROWS=$(mktemp 2>/dev/null) || {
  echo "$PROG: FATAL — could not create a temp file to enumerate sibling steps; $TARGET is held but its siblings keep the routes and claims listed above" >&2
  QUIESCE_FAILED=1
  finish
}
printf '%s\n' "$SIBLINGS" > "$ROWS" || {
  echo "$PROG: FATAL — could not write the sibling enumeration; $TARGET is held but its siblings keep the routes and claims listed above" >&2
  rm -f "$ROWS"
  QUIESCE_FAILED=1
  finish
}

while IFS=$'\t' read -r sid sstep srouted swho; do
  [ -n "${sid:-}" ] || continue
  QUIET=1
  if [ -n "${srouted:-}" ]; then
    gc bd update "$sid" --unset-metadata gc.routed_to --unset-metadata gc.session_affinity >/dev/null 2>&1 \
      || { QUIET=0; echo "$PROG: FATAL — could not de-route sibling step $sid ($sstep); it re-offers" >&2; }
  fi
  if [ -n "${swho:-}" ]; then
    if [ "$QUIET" = "0" ]; then
      echo "$PROG:   keeping the claim on $sid — unassigning a step whose route survived writes the offer predicate itself" >&2
    else
      gc bd update "$sid" --assignee "" >/dev/null 2>&1 \
        || { QUIET=0; echo "$PROG: FATAL — could not unassign sibling step $sid ($sstep); the stranded-worker sweep can re-route it" >&2; }
    fi
  fi
  if [ "$QUIET" = "1" ]; then
    echo "$PROG: quiesced sibling step $sid ($sstep)"
  else
    QUIESCE_FAILED=1
  fi
done < "$ROWS"
rm -f "$ROWS"

finish
