#!/usr/bin/env bash
# step-close — close the step bead THIS shell is executing, identified by who
# owns it and which step it is, never by an environment variable (tk-niu2f).
#
# THE BUG THIS EXISTS TO PREVENT. Every graph.v2 step must close its own bead:
# closing is what makes the next step ready, and a session that drains while
# still owning an open assigned step bead is parked and re-pooled, so the step
# is re-offered forever. Formulas therefore end each arm with a self-close, and
# the id they closed on came from the environment:
#
#     gc bd update "$GC_TRIGGER_BEAD_ID" --set-metadata gc.outcome=pass --status=closed
#
# `gc hook --claim` does NOT update `GC_TRIGGER_BEAD_ID` in the running
# session's environment. After a hook-claim the variable still holds whatever
# the session was spawned with, so the close lands on a bead this step has
# nothing to do with. Observed 2026-08-13, session lx-2m6c: it claimed tk-9b3d8
# (mol-feedback-distiller.load-and-gate) while its environment still read
# GC_TRIGGER_BEAD_ID=tk-dy6cn — mol-feedback-miner.load-context, in_progress,
# owned by a DIFFERENT live session (lx-dq84). Running the formula literally
# would have closed the other session's unexecuted step AND left its own step
# open to be re-offered: two molecules corrupted by one write.
#
# THE SAME-SESSION HALF, which is the commoner one. The fixture above is the
# dramatic case; the everyday case needs no second session at all. A formula
# whose steps deliberately share one session (continuation-group affinity) reads
# a CORRECT variable on step 1 — the bead it was spawned on — and that same, now
# stale, value on steps 2 and 3. There it names this session's OWN already-closed
# step 1, so the close re-closes a closed bead: a successful, exit-0 no-op, after
# which steps 2 and 3 are re-offered forever. Observed on signal-loom (root
# sl-y17b: sl-sw26 -> sl-ot00 -> sl-57zu, the variable pinned at sl-sw26
# throughout). Every multi-step single-session formula hits this on its happy
# path.
#
# WHY THE OBVIOUS GUARD DOES NOT CATCH IT. The idiom is already guarded —
# `[ -n "${GC_TRIGGER_BEAD_ID:-}" ]` — and the guard passes, because the
# variable IS set. It is set to the wrong bead. Emptiness was never the failure
# mode.
#
# WHY THIS IS FIXED HERE AND NOT IN THE RUNTIME. The obvious alternative — have
# `gc hook --claim` re-export the variable — cannot work. GC_TRIGGER_BEAD_ID is
# written in exactly two places, both building a session's SPAWN environment from
# session.Info.TriggerBeadID (gascity cmd/gc/build_desired_state.go:3141 and
# cmd/gc/session_lifecycle_parallel.go:1213, whose own comment notes neither key
# is mutated on the start-prep path). A claim made by an already-running process
# cannot alter that process's environment, so no runtime change makes this
# variable track the current step. Resolution has to happen where the step runs.
#
# WHY IT IS WORSE THAN THE BUG IT REPLACED. The predecessor idiom closed on
# `$GC_BEAD_ID`, which is not populated in the step environment at all
# (tk-7w69a). That failed CLOSED: nothing was written and one workflow stalled
# visibly. `$GC_TRIGGER_BEAD_ID` fails OPEN — a confident, successful write
# against someone else's bead, with a zero exit status and nothing in the log
# that looks wrong.
#
# WHAT IS AUTHORITATIVE INSTEAD. The bead itself. Every step bead carries, set
# by the claim that dispatched it:
#
#     assignee                = the claiming session's name
#     metadata."gc.step_ref"  = the formula step it materializes
#     status                  = in_progress while it is being executed
#
# Those three together name exactly one bead: this session's bead for this
# step. That is a query, not an inheritance, so it cannot go stale across a
# hook-claim — which is the whole defect. The caller passes --step because the
# step id is the one fact the shell knows about itself and cannot misread; the
# rest is read back from the store.
#
# WHY --bead IS A HINT AND NOT AN INSTRUCTION. `gc hook --claim --json` returns
# `.bead_id`, and a caller holding it should say so — it saves a listing and it
# is the id the claim actually handed out. But it is passed through the SAME
# verification as everything else, because a caller can carry a stale id for
# exactly the reason the environment does. A hint that verifies is used; a hint
# that does not is reported and discarded, never trusted on the caller's word.
#
# WHAT IT REFUSES TO DO. It will not close a bead that is not assigned to this
# session, not for this step, or one of several equally-matching candidates. A
# refusal exits 2 and says why: an un-closed step bead stalls one workflow and
# is visible in the graph, while a wrong close silently corrupts two. Between a
# stall and a stray write, this script always picks the stall.
#
# IDEMPOTENT. A step bead already closed for this session and step is reported
# and exits 0. Re-running an arm after a partial failure is a normal recovery
# path and must not read as a fatal error.
#
# NOT set -e: every exit here is explicit, and a self-close runs at the end of
# an arm where an inherited abort would skip the diagnostics that make a
# failure actionable.
set -uo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: step-close.sh --step <formula.step-id> [--outcome <v>] [--bead <id>] [--dry-run]

  --step     the step's `gc.step_ref`, e.g. mol-feedback-distiller.load-and-gate
             (required — it is half of the identity that makes the close safe)
  --outcome  value for metadata gc.outcome, default "pass". The formulas use
             "pass" and "fail"; any [A-Za-z0-9._-] value is accepted.
  --bead     candidate id, e.g. `.bead_id` from `gc hook --claim --json`. A
             HINT: used only if it verifies as this session's bead for --step.
  --dry-run  resolve and report; write nothing.

env: GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS name the session; any that are
     set are tried as the assignee. GC_TRIGGER_BEAD_ID is consulted only as a
     last resort and only if it verifies — see the header.

exit: 0 closed (or already closed) · 2 refused to close, nothing written
USAGE
}

# Value-taking options validate before the shift: `OPT="$2"; shift 2` both hangs
# the parse loop when the option ends argv (shift 2 fails, argv is untouched,
# `while [ $# -gt 0 ]` spins) and silently eats a following option as its value.
# Same shape as escalation-gate.sh; keep it when adding an option.
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

# An unsubstituted formula var reaching here means the pour did not materialize
# it. Refuse rather than search for the literal: `{{x}}` matches no step_ref, so
# resolution would fail anyway, and it would fail with a confusing "no bead
# found" instead of naming the real problem.
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

# bd emits raw control characters inside JSON string values often enough that an
# unfiltered `| jq` is a coin flip on any bead whose notes carry one: jq exits
# "invalid" and the caller reads a parse failure as "no such bead". Strip the C0
# set but keep TAB/LF/CR, which are legal in the payloads we read.
bd_json() {
  gc bd "$@" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037'
}

# Identities this session may appear under as an assignee. Step beads carry the
# session NAME, but a bead claimed through the alias route carries the alias, so
# try each set one, in the same order the startup work query does. `awk NF` drops
# the unset ones and `!seen` keeps the first spelling when two are equal.
IDENTITIES=$(printf '%s\n%s\n%s\n' \
  "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" "${GC_ALIAS:-}" | awk 'NF && !seen[$0]++')
if [ -z "$IDENTITIES" ]; then
  echo "step-close: no session identity in the environment (GC_SESSION_NAME, GC_SESSION_ID, GC_ALIAS all unset) — cannot prove ownership of any bead, refusing to close" >&2
  exit 2
fi

# Does <id> verify as this session's bead for this step? Echoes the bead's
# status on a match and nothing otherwise, so the caller can tell an
# already-closed bead from a foreign one.
verify() {
  local cand="$1" json
  [ -n "$cand" ] || return 1
  json=$(bd_json show "$cand")
  [ -n "$json" ] || return 1
  # `index` on an array of strings is EXACT element equality. `inside`/`contains`
  # are the trap here: on strings they match SUBSTRINGS, so a session named
  # lx-zzk would verify as the owner of lx-zzk9's bead — the same
  # close-someone-else's-bead failure this script exists to prevent, reintroduced
  # inside the check meant to stop it.
  #
  # The bead is bound to $b BEFORE the membership test. Written inline as
  # `select(($me | index(.assignee // "")) != null)`, the `.assignee` inside the
  # argument resolves against $me — the identity ARRAY, not the bead — so jq
  # errors, the error is swallowed, and every verification silently returns
  # "does not verify". That failure is invisible from the outside: resolution
  # falls through to discovery and closes the right bead anyway, on every test
  # that has an unambiguous one.
  printf '%s' "$json" | jq -r --arg step "$STEP" --arg ids "$IDENTITIES" '
    ($ids | split("\n") | map(select(. != ""))) as $me
    | .[0] as $b
    | if $b == null then empty
      elif (($b.metadata["gc.step_ref"] // "") != $step) then empty
      elif (($me | index($b.assignee // "")) == null) then empty
      else ($b.status // "") end
  ' 2>/dev/null
}

# Every in_progress bead for this step assigned to one of our identities, one id
# per line. This is the authoritative resolution: it asks the store who owns
# this step right now instead of trusting a value the session inherited.
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
  # Keep the update's own diagnostics: "the close failed" is not actionable on
  # its own, and this is the last thing an arm runs before its shell ends.
  if err=$(gc bd update "$target" --set-metadata "gc.outcome=$OUTCOME" --status=closed 2>&1); then
    echo "step-close: closed $target ($STEP) outcome=$OUTCOME [$via]"
    return 0
  fi
  echo "step-close: FATAL — 'gc bd update $target --status=closed' failed; the step bead is still open and will be re-offered. Close it by explicit id." >&2
  [ -n "$err" ] && echo "step-close:   $err" >&2
  return 1
}

# Report the stale-environment fingerprint whenever it appears. It is the defect
# this script exists for and it is otherwise invisible: the wrong close used to
# succeed silently, so a run log that never mentions the mismatch is exactly
# what the bug looked like.
warn_env_mismatch() {
  local resolved="$1"
  local env_id="${GC_TRIGGER_BEAD_ID:-}"
  [ -n "$env_id" ] || return 0
  [ "$env_id" != "$resolved" ] || return 0
  echo "step-close: NOTE — GC_TRIGGER_BEAD_ID=$env_id is not this step's bead ($resolved for $STEP); the environment value is stale after a hook-claim and was not used (tk-niu2f)." >&2
}

FOUND=$(discover in_progress | sort -u)
N=$(printf '%s\n' "$FOUND" | awk 'NF' | wc -l | tr -d ' ')

# 1. A hint that verifies wins: it is the id the claim handed out, and it has
#    just been checked against the same (assignee, step_ref) identity as
#    everything else. Report — but do not obey — a hint that does not verify.
if [ -n "$HINT" ]; then
  HINT_STATUS=$(verify "$HINT")
  case "$HINT_STATUS" in
    in_progress)
      if [ "$N" -gt 1 ]; then
        echo "step-close: NOTE — $N in_progress beads match $STEP for this session ($(printf '%s' "$FOUND" | tr '\n' ' ')); using the caller's verified --bead $HINT" >&2
      fi
      warn_env_mismatch "$HINT"
      close_bead "$HINT" "--bead, verified" || exit 2
      exit 0 ;;
    closed)
      echo "step-close: $HINT ($STEP) is already closed — nothing to do"
      exit 0 ;;
    *)
      echo "step-close: NOTE — --bead $HINT is not this session's in_progress bead for $STEP; ignoring the hint and resolving from the store" >&2 ;;
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
  echo "step-close: FATAL — $N in_progress beads match step '$STEP' for this session: $(printf '%s' "$FOUND" | tr '\n' ' ')" >&2
  echo "step-close: refusing to guess which one this shell is executing. Close the right one by explicit id (--bead), and treat the duplicate as a graph defect." >&2
  exit 2
fi

# 3. Nothing in progress. Already closed is a normal re-run, not a failure.
ALREADY=$(discover closed | sort -u | head -n 1)
if [ -n "$ALREADY" ]; then
  echo "step-close: $ALREADY ($STEP) is already closed — nothing to do"
  exit 0
fi

# 4. Last resort: the environment, and only if it verifies. This is the old
#    idiom's path, kept for the case where it was right all along — a session
#    still executing the bead it was spawned with — and gated by the check that
#    makes it safe.
ENV_STATUS=$(verify "${GC_TRIGGER_BEAD_ID:-}")
case "$ENV_STATUS" in
  in_progress)
    echo "step-close: NOTE — resolved from GC_TRIGGER_BEAD_ID (${GC_TRIGGER_BEAD_ID}) after the store listing returned nothing; verified as this session's bead for $STEP" >&2
    close_bead "${GC_TRIGGER_BEAD_ID}" "GC_TRIGGER_BEAD_ID, verified" || exit 2
    exit 0 ;;
  closed)
    echo "step-close: ${GC_TRIGGER_BEAD_ID} ($STEP) is already closed — nothing to do"
    exit 0 ;;
esac

echo "step-close: FATAL — cannot identify this session's bead for step '$STEP'." >&2
echo "step-close:   identities tried: $(printf '%s' "$IDENTITIES" | tr '\n' ' ')" >&2
echo "step-close:   GC_TRIGGER_BEAD_ID=${GC_TRIGGER_BEAD_ID:-<unset>} (not this step's bead, or unreadable)" >&2
echo "step-close:   The step bead is still OPEN and will be re-offered until it is closed by explicit id." >&2
exit 2
