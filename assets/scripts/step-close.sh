#!/usr/bin/env bash
# step-close — close the step bead THIS shell is executing, identified by the
# (assignee, gc.step_ref) pair, never by an environment variable.
# GC_TRIGGER_BEAD_ID is the spawn-time bead and goes stale across a hook-claim,
# so closing on it writes against the wrong bead; the store is authoritative.
#
#   step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>] [--dry-run]
#
# --bead is a HINT (e.g. `.bead_id` from `gc hook --claim --json`): used only if
# it verifies against the same identity pair. A graph.v2 step executes at status
# `open` (the graph pre-assigns it, so the claim advances nothing); in_progress
# is resolved first, open only when that tier is empty. Ambiguity is refused —
# a stalled step is visible, a wrong close corrupts two workflows.
# Callers: formula done arms (mol-feedback-*), mol-polecat-work submit.
# exit: 0 closed (or already closed) · 2 refused, nothing written
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'USAGE'
usage: step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>] [--dry-run]

  --step     the step's `gc.step_ref`, e.g. mol-feedback-distiller.load-and-gate
             (required — it is half of the identity that makes the close safe)
  --outcome  value for metadata gc.outcome, default "pass"
  --bead     candidate id, e.g. `.bead_id` from `gc hook --claim --json`. A
             HINT: used only if it verifies as this session's bead for --step.
  --dry-run  resolve and report; write nothing.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS name the session; any that are
     set are tried as the assignee. GC_TRIGGER_BEAD_ID is consulted only as a
     last resort and only if it verifies.

exit: 0 closed (or already closed) · 2 refused to close, nothing written
USAGE
}

# Validate before the shift: `OPT="$2"; shift 2` hangs the parse loop when the
# option ends argv, and silently eats a following option as its value.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "step-close: $1 requires a value" >&2
    usage
    exit 2
  fi
  case "$2" in
    --step|--outcome|--bead|--dry-run|-h|--help)
      echo "step-close: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

STEP=""; OUTCOME="pass"; HINT=""; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --outcome) require_value "$@"; OUTCOME="$2"; shift 2 ;;
    --bead)    require_value "$@"; HINT="$2";    shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 2 ;;
    *)         echo "step-close: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$STEP" ]; then
  echo "step-close: --step is required — without it there is no way to tell this session's bead for THIS step from its bead for another one" >&2
  usage
  exit 2
fi

case "$STEP" in
  '{{'*'}}')
    echo "step-close: --step was passed unsubstituted ('$STEP') — the pour did not render it; close by explicit id and file the pour defect" >&2
    exit 2 ;;
  *[!A-Za-z0-9._-]*)
    echo "step-close: --step must contain only [A-Za-z0-9._-] (got '$STEP')" >&2
    exit 2 ;;
esac
case "$OUTCOME" in
  ''|*[!A-Za-z0-9._-]*)
    echo "step-close: --outcome must be non-empty and contain only [A-Za-z0-9._-] (got '$OUTCOME')" >&2
    exit 2 ;;
esac

# bd JSON with the C0 set stripped (TAB/LF/CR kept): a raw control byte in a
# note makes jq read the whole payload as "no such bead".
bd_json() {
  gc bd "$@" --json 2>/dev/null | scrub
}

# Identities this session may appear under as an assignee, first spelling wins.
IDENTITIES=$(printf '%s\n%s\n%s\n' \
  "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | awk 'NF && !seen[$0]++')
if [ -z "$IDENTITIES" ]; then
  echo "step-close: no session identity in the environment (GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS all unset) — cannot prove ownership of any bead, refusing to close" >&2
  exit 2
fi

# Does <id> verify as this session's bead for this step? Echoes its status on a
# match. `index` is exact element equality — `inside`/`contains` match
# substrings, which would let session lx-zzk own lx-zzk9's bead.
verify() {
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

# Every bead at <status> for this step assigned to one of our identities.
# One status per call: the caller resolves in_progress ahead of open.
discover() {
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

close_bead() {
  local target="$1" via="$2" err
  if [ "$DRY_RUN" = "1" ]; then
    echo "step-close: DRY RUN — would close $target ($STEP) outcome=$OUTCOME [$via]"
    return 0
  fi
  if err=$(gc bd update "$target" --set-metadata "gc.outcome=$OUTCOME" --status=closed 2>&1); then
    echo "step-close: closed $target ($STEP) outcome=$OUTCOME [$via]"
    return 0
  fi
  echo "step-close: FATAL — 'gc bd update $target --status=closed' failed; the step bead is still unclosed and will be re-offered. Close it by explicit id." >&2
  [ -n "$err" ] && echo "step-close:   $err" >&2
  return 1
}

warn_env_mismatch() {
  local resolved="$1"
  local env_id="${GC_TRIGGER_BEAD_ID:-}"
  [ -n "$env_id" ] || return 0
  [ "$env_id" != "$resolved" ] || return 0
  echo "step-close: NOTE — GC_TRIGGER_BEAD_ID=$env_id is not this step's bead ($resolved for $STEP); the environment value is stale after a hook-claim and was not used (tk-niu2f)." >&2
}

TIER=in_progress
FOUND=$(discover in_progress | sort -u)
N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
if [ "$N" -eq 0 ]; then
  TIER=open
  FOUND=$(discover open | sort -u)
  N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')
fi

# 1. A hint that verifies wins; one that does not is reported, never obeyed.
if [ -n "$HINT" ]; then
  HINT_STATUS=$(verify "$HINT")
  case "$HINT_STATUS" in
    in_progress|open)
      if [ "$N" -gt 1 ]; then
        echo "step-close: NOTE — $N $TIER beads match $STEP for this session ($(printf '%s' "$FOUND" | tr '\n' ' ')); using the caller's verified --bead $HINT" >&2
      fi
      warn_env_mismatch "$HINT"
      close_bead "$HINT" "--bead, verified" || exit 2
      exit 0 ;;
    closed)
      echo "step-close: $HINT ($STEP) is already closed — nothing to do"
      exit 0 ;;
    '')
      echo "step-close: NOTE — --bead $HINT is not this session's bead for $STEP; ignoring the hint and resolving from the store" >&2 ;;
    *)
      echo "step-close: NOTE — --bead $HINT IS this session's bead for $STEP, but its status is '$HINT_STATUS', which this script does not close; ignoring the hint and resolving from the store" >&2 ;;
  esac
fi

# 2. Authoritative resolution.
if [ "$N" -eq 1 ]; then
  TARGET=$(printf '%s' "$FOUND" | head -n 1)
  warn_env_mismatch "$TARGET"
  close_bead "$TARGET" "resolved by (assignee, step_ref)" || exit 2
  exit 0
fi

if [ "$N" -gt 1 ]; then
  echo "step-close: FATAL — $N $TIER beads match step '$STEP' for this session: $(printf '%s' "$FOUND" | tr '\n' ' ')" >&2
  echo "step-close: refusing to guess which one this shell is executing. Close the right one by explicit id (--bead), and treat the duplicate as a graph defect." >&2
  exit 2
fi

# 3. Nothing executable: already closed is a normal re-run.
ALREADY=$(discover closed | sort -u | head -n 1)
if [ -n "$ALREADY" ]; then
  echo "step-close: $ALREADY ($STEP) is already closed — nothing to do"
  exit 0
fi

# 4. Last resort: the environment, and only if it verifies.
ENV_STATUS=$(verify "${GC_TRIGGER_BEAD_ID:-}")
case "$ENV_STATUS" in
  in_progress|open)
    echo "step-close: NOTE — resolved from GC_TRIGGER_BEAD_ID (${GC_TRIGGER_BEAD_ID}) after the store listing returned nothing; verified as this session's bead for $STEP" >&2
    close_bead "${GC_TRIGGER_BEAD_ID}" "GC_TRIGGER_BEAD_ID, verified" || exit 2
    exit 0 ;;
  closed)
    echo "step-close: ${GC_TRIGGER_BEAD_ID} ($STEP) is already closed — nothing to do"
    exit 0 ;;
esac

# A non-empty ENV_STATUS means ownership was proven and only the status refused
# the close — name that, it has a different fix than a stale environment.
echo "step-close: FATAL — cannot identify this session's bead for step '$STEP'." >&2
echo "step-close:   identities tried: $(printf '%s' "$IDENTITIES" | tr '\n' ' ')" >&2
if [ -n "$ENV_STATUS" ]; then
  echo "step-close:   GC_TRIGGER_BEAD_ID=${GC_TRIGGER_BEAD_ID} IS this session's bead for this step, but its status is '$ENV_STATUS' — this script closes 'in_progress' and 'open', and reports 'closed' as already done. Nothing else was resolvable either." >&2
else
  echo "step-close:   GC_TRIGGER_BEAD_ID=${GC_TRIGGER_BEAD_ID:-<unset>} (not this step's bead, or unreadable)" >&2
fi
echo "step-close:   The step bead is still UNCLOSED and will be re-offered until it is closed by explicit id." >&2
exit 2
