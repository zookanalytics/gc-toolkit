#!/usr/bin/env bash
# step-close — close the step bead THIS shell is executing, identified by its
# molecule and gc.step_ref, never by an environment variable.
# GC_TRIGGER_BEAD_ID is the spawn-time bead and goes stale across a hook-claim,
# so closing on it writes against the wrong bead; the store is authoritative.
#
#   step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>]
#                 [--root <id>] [--dry-run]
#
# The assignee does not name a molecule. A pool agent wears one assignee for
# every run it has ever made, so (assignee, gc.step_ref) matches the same step
# of every molecule it ran before this one; only (gc.root_bead_id, gc.step_ref)
# is unique. Resolution is scoped to the molecule and the assignee corroborates
# it — a finalized chain has no assignees left, and a blank one inside our own
# molecule is still ours (tk-xgfhj3).
#
# Deriving that molecule from the assignee borrows the same non-unique pair, so
# it settles nothing by itself: this chain's own bead may be one the finalizer
# stripped, sitting in a molecule the assignee never mentions. Where `--root` or
# the gc.session_id stamp names the molecule independently, the close proceeds;
# where only the assignee does and another live bead for this step could equally
# be ours, it is refused rather than guessed.
#
# --bead is a HINT (e.g. `.bead_id` from `gc hook --claim --json`): used only if
# it verifies as this session's bead for this step inside the molecule being
# executed. It never establishes which molecule that is: a hint scoped by a root
# it supplied itself is scoped by nothing, so pass --root when no other source
# names one. A graph.v2 step executes at status `open` (the graph pre-assigns
# it, so the claim advances nothing); in_progress is resolved first, open only
# when that tier is empty. Ambiguity is refused — a stalled step is visible, a
# wrong close corrupts two workflows.
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
usage: step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>]
                     [--root <id>] [--dry-run]

  --step     the step's `gc.step_ref`, e.g. mol-feedback-distiller.load-and-gate
             (required — it is half of the identity that makes the close safe)
  --outcome  value for metadata gc.outcome, default "pass"
  --bead     candidate id, e.g. `.bead_id` from `gc hook --claim --json`. A
             HINT: used only if it verifies as this session's bead for --step
             inside the molecule being executed, and never to establish which
             molecule that is — with none established it is ignored, and
             --root is how a caller supplies one. A stale hint is reported and
             ignored, never obeyed.
  --root     the molecule's root bead, e.g. `.root_bead_id` from that same
             claim. Skips the derivation; the other half of the unique pair.
  --dry-run  resolve and report; write nothing.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS name the session; any that are
     set are tried as the assignee. GC_SESSION_ID also finds the molecule,
     through the gc.session_id a claim stamps on the step it hands out.
     GC_TRIGGER_BEAD_ID is consulted only as a last resort and only if it
     verifies.

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
    --step|--outcome|--bead|--root|--dry-run|-h|--help)
      echo "step-close: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

STEP=""; OUTCOME="pass"; HINT=""; ROOT=""; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --step)    require_value "$@"; STEP="$2";    shift 2 ;;
    --outcome) require_value "$@"; OUTCOME="$2"; shift 2 ;;
    --bead)    require_value "$@"; HINT="$2";    shift 2 ;;
    --root)    require_value "$@"; ROOT="$2";    shift 2 ;;
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
case "$ROOT" in
  *[!A-Za-z0-9._-]*)
    echo "step-close: --root must contain only [A-Za-z0-9._-] (got '$ROOT')" >&2
    exit 2 ;;
esac

# A raw control byte in a note makes jq read the whole payload as "no such
# bead".
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
# substrings, which would let session lx-zzk own lx-zzk9's bead. A known
# molecule gates every answer below it: one assignee covers every molecule a
# pool agent ever ran, so a matching assignee corroborates the candidate and
# never outranks its root. While $ROOT is empty that gate is inert and the
# answer is back to the non-unique pair, so every caller of verify() has to
# treat an unscoped verdict as unproven.
verify() {
  local cand="$1" json
  [ -n "$cand" ] || return 1
  json=$(bd_json show "$cand")
  [ -n "$json" ] || return 1
  printf '%s' "$json" | jq -r --arg step "$STEP" --arg ids "$IDENTITIES" --arg root "$ROOT" '
    ($ids | split("\n") | map(select(. != ""))) as $me
    | .[0] as $b
    | if $b == null then empty
      elif (($b.metadata["gc.step_ref"] // "") != $step) then empty
      elif ($root != "") and (($b.metadata["gc.root_bead_id"] // "") != $root) then empty
      elif (($me | index($b.assignee // "")) != null) then ($b.status // "")
      elif (($b.assignee // "") == "") and ($root != "") then ($b.status // "")
      else empty end
  ' 2>/dev/null
}

count() { printf '%s\n' "$1" | awk 'NF' | wc -l | tr -d ' '; }

# The formula half of --step. One session can run steps from more than one
# formula, and only a same-formula bead says anything about this one.
FORMULA="${STEP%%.*}"

# gc.root_bead_id of <id>, empty when the bead is unreadable or carries none.
root_of() {
  [ -n "${1:-}" ] || return 0
  bd_json show "$1" | jq -r '
    if type == "array" then (.[0].metadata["gc.root_bead_id"] // empty) else empty end
  ' 2>/dev/null
}

# Distinct gc.root_bead_id over a listing, restricted to this step's formula.
roots_from() { # <bd list args...>
  bd_json list "$@" --limit=0 | jq -r --arg f "$FORMULA." '
    if type == "array" then
      .[] | select(((.metadata["gc.step_ref"] // "") | startswith($f)))
          | (.metadata["gc.root_bead_id"] // empty)
    else empty end
  ' 2>/dev/null | awk 'NF && !seen[$0]++'
}

# The molecule this shell is executing, as "<source> <root>" — empty when
# nothing proves which it is. Each source answers only when it names exactly one
# root; an ambiguous source is no answer rather than a refusal, so a session
# carrying husks from earlier runs still resolves through a later source. Order
# is most to least trustworthy: the session stamp a claim leaves on the step it
# hands out, this step's own live bead, then any live bead of this formula.
#
# The source is half the answer. `session` names the molecule independently of
# the assignee; `assignee` names it with the same non-unique pair the scoping
# exists to replace, and a root only that pair vouches for cannot authorize a
# close on its own (see unproven_rivals).
#
# --bead is not a source. $ROOT is empty here, so verify() is down to the
# (assignee, gc.step_ref) pair one pool assignee shares with every molecule it
# has ever run; a root taken from a hint that matched on it would scope every
# resolution below to the wrong chain, and then vouch for that same hint on the
# way back out (tk-xgfhj3).
derive_root() {
  local found ident json this_step="" same_formula=""
  if [ -n "${GC_SESSION_ID:-}" ]; then
    found=$(roots_from --metadata-field "gc.session_id=$GC_SESSION_ID" \
                       --status=open,in_progress,blocked,closed)
    [ "$(count "$found")" = "1" ] && { printf 'session %s' "$found"; return 0; }
  fi
  while IFS= read -r ident; do
    [ -n "$ident" ] || continue
    json=$(bd_json list --status=open,in_progress --assignee="$ident" --limit=0)
    [ -n "$json" ] || continue
    this_step="$this_step
$(printf '%s' "$json" | jq -r --arg step "$STEP" '
      if type == "array" then
        .[] | select((.metadata["gc.step_ref"] // "") == $step)
            | (.metadata["gc.root_bead_id"] // empty)
      else empty end' 2>/dev/null)"
    same_formula="$same_formula
$(printf '%s' "$json" | jq -r --arg f "$FORMULA." '
      if type == "array" then
        .[] | select(((.metadata["gc.step_ref"] // "") | startswith($f)))
            | (.metadata["gc.root_bead_id"] // empty)
      else empty end' 2>/dev/null)"
  done <<< "$IDENTITIES"
  found=$(printf '%s\n' "$this_step" | awk 'NF && !seen[$0]++')
  [ "$(count "$found")" = "1" ] && { printf 'assignee %s' "$found"; return 0; }
  found=$(printf '%s\n' "$same_formula" | awk 'NF && !seen[$0]++')
  [ "$(count "$found")" = "1" ] && { printf 'assignee %s' "$found"; return 0; }
  return 0
}

# Every bead at <status> for this step this shell may close. One status per
# call: the caller resolves in_progress ahead of open. Inside a known molecule
# the (root, step_ref) pair is the identity and the assignee only corroborates,
# so a bead the finalizer stripped is still resolved and one held by another
# session is not. With no molecule the (assignee, step_ref) pair is all there
# is, which is what it has always been.
discover() {
  local want_status="$1" ident json
  if [ -n "$ROOT" ]; then
    bd_json list --metadata-field "gc.root_bead_id=$ROOT" --status="$want_status" --limit=0 \
      | jq -r --arg step "$STEP" --arg ids "$IDENTITIES" '
          ($ids | split("\n") | map(select(. != ""))) as $me
          | if type == "array" then
              .[] | . as $b
                  | select(($b.metadata["gc.step_ref"] // "") == $step)
                  | select((($b.assignee // "") == "") or (($me | index($b.assignee // "")) != null))
                  | $b.id
            else empty end
        ' 2>/dev/null
    return 0
  fi
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

# This step's bead in the molecule at <status-list>, whoever holds it, as
# "<id> <status> <assignee>". Ownership is not asked: within one molecule the
# step_ref names one bead, and who holds it is the answer, not the filter.
molecule_rows() { # <status-list>
  [ -n "$ROOT" ] || return 0
  bd_json list --metadata-field "gc.root_bead_id=$ROOT" --status="$1" --limit=0 \
    | jq -r --arg step "$STEP" '
        if type == "array" then
          .[] | select((.metadata["gc.step_ref"] // "") == $step)
              | "\(.id) \(.status // "?") \(.assignee // "")"
        else empty end
      ' 2>/dev/null
}

# Live beads for this step, outside <root>, that this shell could itself be
# executing. The finalizer strips assignees, so an unassigned live bead for this
# step is a candidate for "our own"; so is one under our own assignee in another
# molecule. A bead another session holds — by assignee, or by the gc.session_id
# a claim stamped on it — is that session's and is not counted.
unproven_rivals() { # <root the close would act in>
  bd_json list --metadata-field "gc.step_ref=$STEP" --status=open,in_progress --limit=0 \
    | jq -r --arg step "$STEP" --arg root "${1:-}" --arg ids "$IDENTITIES" \
            --arg sid "${GC_SESSION_ID:-}" '
        ($ids | split("\n") | map(select(. != ""))) as $me
        | if type == "array" then
            .[] | . as $b
                | select(($b.metadata["gc.step_ref"] // "") == $step)
                | select(($b.metadata["gc.root_bead_id"] // "") != $root)
                | select((($b.assignee // "") == "") or (($me | index($b.assignee // "")) != null))
                | select((($b.metadata["gc.session_id"] // "") | . == "" or . == $sid))
                | "\($b.id) (molecule \($b.metadata["gc.root_bead_id"] // "?"))"
          else empty end
      ' 2>/dev/null
}

# A close may rest on the molecule only when something other than the assignee
# named it. `--root` and the gc.session_id stamp are such sources; the assignee
# is not — one pool assignee covers every molecule the agent has ever run, so
# the root it names is this chain's only if no other live bead for this step
# could equally be ours. When one could, the answer is a guess, and this refuses
# it: a stalled step is visible and the finalizer still reaches it, while a
# close in another chain is silent and takes a step out of a workflow nobody was
# running.
guard_unproven() { # <root the arm would act in> <what it would act on>
  local acting="$1" subject="$2" rival
  case "$ROOT_SOURCE" in flag|session) return 0 ;; esac
  rival=$(unproven_rivals "$acting")
  [ -n "$rival" ] || return 0
  echo "step-close: FATAL — refusing to act on $subject for step '$STEP': nothing but this session's assignee names molecule ${acting:-<none>}, and that assignee covers every molecule this agent has ever run." >&2
  echo "step-close:   Live for this step and equally ours: $(printf '%s' "$rival" | tr '\n' ' ')" >&2
  echo "step-close:   Pass --root <root bead id> (\`.root_bead_id\` from \`gc hook --claim --json\`) to name the molecule this shell is executing." >&2
  echo "step-close:   The step bead is still UNCLOSED and will be re-offered until it is closed." >&2
  exit 2
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

# The molecule scopes every resolution below, so it is established first. A
# caller-supplied --root is taken as given; deriving it costs one listing.
ROOT_SOURCE=""
if [ -n "$ROOT" ]; then
  ROOT_SOURCE=flag
else
  DERIVED=$(derive_root)
  case "$DERIVED" in
    *' '*) ROOT_SOURCE="${DERIVED%% *}"; ROOT="${DERIVED#* }" ;;
    *)     ROOT_SOURCE=""; ROOT="" ;;
  esac
fi

TIER=in_progress
FOUND=$(discover in_progress | sort -u)
N=$(count "$FOUND")
if [ "$N" -eq 0 ]; then
  TIER=open
  FOUND=$(discover open | sort -u)
  N=$(count "$FOUND")
fi

HINT_STATUS=""
[ -n "$HINT" ] && HINT_STATUS=$(verify "$HINT")

# A hint is acted on only inside an established molecule. Unscoped, verify() is
# back to (assignee, gc.step_ref), and an earlier molecule's bead for this same
# step satisfies that pair exactly as this chain's own would: closing it is a
# wrong close, calling it already closed is a pass for a chain this shell never
# ran. Both fall through to the store instead, which closes an executable bead
# on the old pair and refuses a closed one. Only the two acting verdicts are
# dropped — the reporting arms below do not act, and a parked hint's status is
# the fact the reader needs (tk-xgfhj3).
if [ -z "$ROOT" ]; then
  case "$HINT_STATUS" in
    in_progress|open|closed)
      echo "step-close: NOTE — --bead $HINT carries this session's assignee and $STEP at status '$HINT_STATUS', but no molecule is established, and that pair matches another molecule's bead for this same step too. Pass --root (\`.root_bead_id\` from \`gc hook --claim --json\`) to act on the hint; resolving from the store instead." >&2
      HINT=""; HINT_STATUS="" ;;
  esac
fi

# 1. A hint that verifies wins; one that does not is reported, never obeyed.
if [ -n "$HINT" ]; then
  case "$HINT_STATUS" in
    in_progress|open)
      if [ "$N" -gt 1 ]; then
        echo "step-close: NOTE — $N $TIER beads match $STEP in ${ROOT:+molecule $ROOT}${ROOT:-this session} ($(printf '%s' "$FOUND" | tr '\n' ' ')); using the caller's verified --bead $HINT" >&2
      fi
      warn_env_mismatch "$HINT"
      guard_unproven "$ROOT" "--bead $HINT"
      close_bead "$HINT" "--bead, verified" || exit 2
      exit 0 ;;
    closed)
      guard_unproven "$ROOT" "--bead $HINT"
      echo "step-close: $HINT ($STEP) is already closed — nothing to do"
      exit 0 ;;
    '')
      HINT_ROOT=$(root_of "$HINT")
      if [ -n "$ROOT" ] && [ -n "$HINT_ROOT" ] && [ "$HINT_ROOT" != "$ROOT" ]; then
        echo "step-close: NOTE — --bead $HINT belongs to molecule $HINT_ROOT, not the one this shell is executing ($ROOT); ignoring the hint and resolving from the store" >&2
      else
        echo "step-close: NOTE — --bead $HINT is not this session's bead for $STEP; ignoring the hint and resolving from the store" >&2
      fi ;;
    *)
      echo "step-close: NOTE — --bead $HINT IS this session's bead for $STEP, but its status is '$HINT_STATUS', which this script does not close; ignoring the hint and resolving from the store" >&2 ;;
  esac
fi

# 2. Authoritative resolution.
if [ "$N" -eq 1 ]; then
  TARGET=$(printf '%s' "$FOUND" | head -n 1)
  warn_env_mismatch "$TARGET"
  guard_unproven "${ROOT:-$(root_of "$TARGET")}" "$TARGET"
  if [ -n "$ROOT" ]; then
    close_bead "$TARGET" "resolved by (molecule $ROOT, step_ref)" || exit 2
  else
    close_bead "$TARGET" "resolved by (assignee, step_ref)" || exit 2
  fi
  exit 0
fi

if [ "$N" -gt 1 ]; then
  echo "step-close: FATAL — $N $TIER beads match step '$STEP' in ${ROOT:+molecule $ROOT}${ROOT:-this session}: $(printf '%s' "$FOUND" | tr '\n' ' ')" >&2
  echo "step-close: refusing to guess which one this shell is executing. Close the right one by explicit id (--bead), and treat the duplicate as a graph defect — one molecule pours one bead per step." >&2
  exit 2
fi

# 3. Nothing executable: an already-closed step is a normal re-run, and only a
#    bead in this molecule proves it. Unscoped, this arm answers with whatever
#    closed bead shares the assignee — one per molecule this agent ran before
#    this one — and a chain that closed nothing reads, line for line, exactly
#    like one that worked (tk-xgfhj3).
if [ -n "$ROOT" ]; then
  ALREADY=$(molecule_rows closed | awk 'NF {print $1}' | sort -u | head -n 1)
  if [ -n "$ALREADY" ]; then
    guard_unproven "$ROOT" "$ALREADY"
    echo "step-close: $ALREADY ($STEP) is already closed — nothing to do"
    exit 0
  fi
else
  STRAY=$(discover closed | sort -u | head -n 1)
  if [ -n "$STRAY" ]; then
    echo "step-close: FATAL — $STRAY ($STEP) is closed under one of this session's identities, but it belongs to molecule $(root_of "$STRAY"), and this shell could not establish which molecule it is executing." >&2
    echo "step-close:   Reporting it as already closed would be a pass for a bead this shell never ran. Pass --root <root bead id> (\`.root_bead_id\` from \`gc hook --claim --json\`), or close this session's bead by explicit id." >&2
    echo "step-close:   The step bead is still UNCLOSED and will be re-offered until it is closed." >&2
    exit 2
  fi
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
echo "step-close:   molecule: ${ROOT:-<not established: no --root, no gc.session_id match, no live bead of this formula>}" >&2
HELD=$(molecule_rows open,in_progress,blocked,closed)
[ -n "$HELD" ] && echo "step-close:   this molecule's bead for the step: $HELD — an assignee that is not this session's means a second worker holds the chain, which is a different problem from a stale environment." >&2
if [ -n "$ENV_STATUS" ]; then
  echo "step-close:   GC_TRIGGER_BEAD_ID=${GC_TRIGGER_BEAD_ID} IS this session's bead for this step, but its status is '$ENV_STATUS' — this script closes 'in_progress' and 'open', and reports 'closed' as already done. Nothing else was resolvable either." >&2
else
  echo "step-close:   GC_TRIGGER_BEAD_ID=${GC_TRIGGER_BEAD_ID:-<unset>} (not this step's bead, or unreadable)" >&2
fi
echo "step-close:   The step bead is still UNCLOSED and will be re-offered until it is closed by explicit id." >&2
exit 2
