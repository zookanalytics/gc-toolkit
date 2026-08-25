#!/usr/bin/env bash
# hold-dispatch — park a dispatch ATOMICALLY over its whole molecule, in one
# writer, so a hold cannot be half-performed (tk-oqseh6).
#
# THE DEFECT. A polecat that HOLDS a dispatch before doing any work — a live
# sitting owns the decision, the filed premise is falsified, a peer already has
# the branch — parks the bead by hand:
#
#     gc bd update <anchor> --assignee "" --set-metadata gc.routed_to="" \
#       --append-notes "Dispatch HELD because ..."
#
# That parks the ANCHOR. Nothing parks the MOLECULE. `mol-polecat-work`
# materializes seven chained step beads, each carrying
# `gc.routed_to=<rig>/<prefix>polecat` and `gc.session_affinity=require`. The
# chain is dep-ordered, so `load-context` is the only unblocked step — and open
# + unassigned + routed + ready is exactly the pool's offer predicate. The
# holder's drain releases the step assignees, and from that moment the dead
# chain is served to every idle polecat, forever.
#
# Observed end to end: anchor tk-iljtmq was held at 2026-08-24T09:52Z by session
# lx-4cnzt; its molecule tk-p3p9iv stayed fully routed and was re-offered ~3h
# later to lx-4e5a0, which burned a whole session establishing that it must not
# do the work and then swept the chain by hand.
#
# WHY THE EXISTING MACHINERY DOES NOT COVER IT.
#
#   #443 (polecats close their own step chain, template-fragments/
#   polecat-close-step-chain) stops husk INFLOW from polecats that COMPLETE
#   work. A held dispatch never reaches `submit-and-exit`, so nothing closes the
#   chain. This generator produces fresh husks after #443.
#
#   quiesce-completed-workflows.sh gates on is_terminal_anchor(). A parked-OPEN
#   anchor is non-terminal, so the pass stamps `quiesce.terminal_since=live` and
#   declines, every cycle, forever. Verified by positive control — a live
#   `--dry-run` reports `root tk-p3p9iv — anchor tk-iljtmq still live
#   (status=open merge_result=none ...); left alone`. specs/tk-8m8d4 names the
#   witness's manual sweep as the only fallback for exactly this population.
#
#   gc-helm.sh's quiesce_release_molecule_steps() DOES walk the molecule, but
#   only from `takeaway <bead> --release`, which is the operator/converse park
#   and stamps `gc.takeaway` — a conversation-board headline that also MUTES the
#   stall detector. A polecat holding its own dispatch is not writing a board
#   headline, and its steps are still HELD (see the split-call note below), which
#   that function's single-update form cannot clear.
#
# WHY A SCRIPT AND NOT AN INSTRUCTION. The park is six-plus keys across eight
# beads and every one of them is a separate re-attracting channel. The hold that
# produced tk-oqseh6 was performed by a careful agent that wrote a 300-word note
# explaining itself — and still cleared exactly one key on exactly one bead. A
# half-park is invisible from inside the shell that performs it: every write
# succeeds, the bead looks parked, and the failure surfaces hours later as a
# fresh polecat holding a dead chain. That is the same argument
# template-fragments/bead-disposition makes for bead-rehome.sh: where a
# multi-write invariant has to hold, there is ONE writer.
#
# WHAT IT DOES, in order.
#
#   1. Records the hold on the anchor (`--append-notes`) BEFORE any delivery key
#      is touched, so a run that dies mid-walk leaves an explained bead rather
#      than a silently de-routed one.
#   2. Parks the anchor: every delivery channel it actually carries, then the
#      assignee.
#   3. Resolves the molecule(s) poured on this anchor and quiesces their steps.
#   4. Appends what it did, and exits non-zero if any part of it failed.
#
# THE DELIVERY CHANNELS ARE SIX, NOT ONE. docs/gascity-dispatch-containment.md
# enumerates three live keys and their deferred twins, and a park that clears
# only `gc.routed_to` leaves the rest live:
#
#     gc.routed_to        gc.deferred_routed_to
#     gc.execution_routed_to  gc.deferred_execution_routed_to
#     assignee (a column)     gc.deferred_assignee
#
# A deferred twin is WITHHELD delivery that activation promotes into the live
# key, so clearing only the live half re-delivers the record the moment the step
# activates. The held instance above still carried
# `gc.execution_routed_to=gc-toolkit/gc-toolkit.polecat` a full day after it was
# "parked" — a second half-park inside the one this script exists to prevent.
#
# ONLY KEYS ACTUALLY PRESENT ARE TOUCHED, and they are UNSET rather than set to
# "". `gc bd update --set-metadata k=""` on an absent key CREATES it empty, and
# absent-vs-empty is a live tri-state in this store. The one exception is the
# anchor's own `gc.routed_to`, written as "" because that is the spelling every
# other writer of a parked anchor uses (the done sequence, gc-helm's release,
# check-set-heal) and check-routed-work-claimable reads it explicitly as "no
# route". Both spellings fail the offer predicate identically; each side keeps
# the convention its own readers already understand.
#
# TWO CALLS PER BEAD, ROUTE FIRST — the signature quiesce-completed-workflows.sh
# arrived at (tk-z27pw, tk-d553m), and load-bearing here for a sharper reason
# than there. At hold time the steps are HELD: `load-context` is in_progress
# under the holding session and the rest are open and assigned to it. bd's claim
# guard can refuse `--assignee ""` on a held bead, and a refusal inside a BATCHED
# update rolls the whole update back — so the route would not be cleared either,
# even though unsetting a route needs no claim at all. The step stays fully
# re-offerable and the hold reports success. Splitting means the half that can
# always land, always lands.
#
#   WHY ROUTE FIRST. Clearing the assignee first leaves the bead open +
#   unassigned + routed — the exact pool-offer shape — racing a fresh polecat
#   into the husk being retired. Route first inverts that: the intermediate
#   state is open + assigned + unrouted, which is invisible to the pool.
#
#   AND THE ASSIGNEE HALF IS GATED ON IT. Order alone only rules out the
#   pool-offer shape while the route clear SUCCEEDS. A refused route clear
#   therefore skips the assignee clear entirely: the bead is left exactly as it
#   was and counted failed, rather than parked into a shape strictly worse than
#   the one we found.
#
# --force IS A FALLBACK, AND ONLY OVER OUR OWN CLAIM. `gc bd` rejects --force in
# its bead-id pre-check, so that half runs through bare `bd` — the same binary on
# the same store, honoring the BEADS_DIR the agent env pins, and every id here
# comes verbatim from a listing, so the partial-id resolution that pre-check
# guards is not in play. The licence is narrower than the sibling pass's: this
# script clears an assignee ONLY when it is one of the CALLER's own identities,
# so the claim being forced past is always the caller's own, released
# deliberately, one call before it drains. A step held by ANY other session is
# left untouched and reported — that is a live molecule, not this hold's, and
# stripping it is the precise hazard every quiesce guard in this pack exists to
# prevent.
#
# WHAT IT NEVER DOES.
#
#   NEVER CLOSES A STEP, and never writes a step's status. Closing `load-context`
#   unblocks `workspace-setup` and walks the next polecat onto a branch that may
#   already be green-gated under a live review. It is also the footgun that makes
#   a husk PERMANENT: specs/tk-8m8d4 guard 2 records that a molecule with a
#   closed step reads as "being driven step by step", so the witness's automated
#   sweep will decline it forever after. There is deliberately no close path here.
#
#   NEVER DE-ROUTES `workflow-finalize`. Its `core.control-dispatcher` route is
#   the molecule's only escape path — the dispatcher's finalizer closes the
#   workflow root and force-closes any member still open. Guarded twice, by step
#   id and by route, because losing it needs a hand repair.
#
#   NEVER TOUCHES A MOLECULE THAT IS NOT THIS ANCHOR'S. Every root is verified
#   root -> gc.input_convoy_id -> the convoy's SINGLE tracked member -> equals the
#   parked bead, before one key is written. Anything else — no convoy, a member
#   count other than one, an unreadable root — is skipped untouched.
#
# --steps-only EXISTS FOR THE DUPLICATE-DISPATCH ARM. `mol-polecat-base`'s
# `load-context` refuses when the work bead is already in_progress under a live
# owner. There the ANCHOR belongs to that live owner and must not be parked at
# all — but THIS session's molecule is the duplicate and must still be quiesced,
# or the drain hands the dead chain to the next polecat, which refuses again.
# `--steps-only` records the hold on the anchor and quiesces the molecule without
# touching the anchor's delivery keys or its assignee.
#
# NOT set -e: every exit here is explicit, and this runs in the last shell before
# a drain, where an inherited abort would skip the diagnostics that make a
# partial park actionable. Failures are counted and reported, never swallowed —
# a hold that reports success over an unquiesced step is the whole bug.
#
# exit: 0 parked · 1 something did not land (re-run, or sweep by hand) ·
#       2 refused before writing anything
set -uo pipefail

PROG=hold-dispatch

usage() {
  cat >&2 <<'USAGE'
usage: hold-dispatch.sh --bead <work-bead-id> --reason "<why>" [--steps-only] [--dry-run]

  --bead        the work bead being held — the ANCHOR of the molecule you were
                dispatched on (required)
  --reason      why the dispatch is being held, one paragraph. Appended to the
                anchor's notes BEFORE anything is de-routed (required)
  --steps-only  quiesce the molecule but leave the anchor's delivery keys and
                assignee alone. For the duplicate-dispatch arm, where the anchor
                belongs to a live owner and only THIS molecule is dead.
  --dry-run     resolve and report; write nothing.

env: GC_ALIAS, GC_AGENT, GC_SESSION_NAME, GC_SESSION_ID name the caller; any
     that are set are treated as this session's identities. An assignee that is
     not one of them is never cleared.

exit: 0 parked · 1 a write did not land · 2 refused, nothing written
USAGE
}

# Value-taking options validate before the shift: `OPT="$2"; shift 2` both hangs
# the parse loop when the option ends argv and silently eats a following option
# as its value. Same shape as step-close.sh; keep it when adding an option.
require_value() {
  if [ "$#" -lt 2 ]; then
    echo "$PROG: $1 requires a value" >&2
    usage
    exit 2
  fi
  case "$2" in
    --bead|--reason|--steps-only|--dry-run|-h|--help)
      echo "$PROG: $1 requires a value, but the next argument is the option '$2'" >&2
      usage
      exit 2 ;;
  esac
}

BEAD=""; REASON=""; STEPS_ONLY=0; DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bead)       require_value "$@"; BEAD="$2";   shift 2 ;;
    --reason)     require_value "$@"; REASON="$2"; shift 2 ;;
    --steps-only) STEPS_ONLY=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    usage; exit 2 ;;
    *)            echo "$PROG: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$BEAD" ]; then
  echo "$PROG: --bead is required" >&2; usage; exit 2
fi
case "$BEAD" in
  *[!A-Za-z0-9-]*)
    echo "$PROG: --bead must be a bead id ([A-Za-z0-9-]), got '$BEAD'" >&2; exit 2 ;;
esac
if [ -z "$REASON" ]; then
  # A hold with no recorded reason is the thing that makes a parked bead
  # indistinguishable from a stalled one: nothing downstream can tell "held
  # deliberately" from "dropped". Refuse rather than park silently.
  echo "$PROG: --reason is required — a parked bead with no recorded reason cannot be told from an abandoned one" >&2
  usage
  exit 2
fi

# Every non-closed status, not just open/in_progress. `hooked` and `blocked` are
# bd's wip category and `pinned` its frozen one; a graph node in `hooked` is
# exactly as deliverable as one in `in_progress`, and filtering it out drops it
# from the clear AND from the report — a bead never looked at, reported as
# parked (docs/gascity-dispatch-containment.md step 0).
LIVE=open,in_progress,hooked,blocked,deferred,pinned

# The assignee half needs `bd ... --force` when the claim guard refuses, which
# `gc bd` will not pass through. Resolve once so a host without `bd` says so
# plainly instead of surfacing as N opaque per-bead failures.
BD_BIN=$(command -v bd 2>/dev/null || true)

# bd emits raw control characters inside JSON string values often enough that an
# unfiltered `| jq` is a coin flip on any bead whose notes carry one — and this
# script reads beads whose notes are long by construction. Strip the C0 set but
# keep TAB/LF/CR, which are legal in the payloads we read.
bd_json() {
  gc bd "$@" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037'
}

# `bd show` answers an ARRAY when at least one id resolves and a bare OBJECT
# when none do, exit 0 either way. Array-shaped jq throws on the object form, so
# every read goes through this guard rather than assuming `.[0]`.
first_of() {
  jq -r 'if type == "array" and length > 0 then .[0] else empty end' 2>/dev/null
}

# Identities this session may appear under as an assignee. Step beads of a
# graph.v2 molecule are assigned by the graph to the AGENT address (GC_ALIAS /
# GC_AGENT), while a pool claim writes the session name — so all four are tried,
# in the order the startup work query uses. `awk NF && !seen` drops the unset
# ones and keeps the first spelling when two are equal.
IDENTITIES=$(printf '%s\n%s\n%s\n%s\n' \
  "${GC_ALIAS:-}" "${GC_AGENT:-}" "${GC_SESSION_NAME:-}" "${GC_SESSION_ID:-}" \
  | awk 'NF && !seen[$0]++')

is_ours() {
  local who="$1" id
  [ -n "$who" ] || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$id" = "$who" ] && return 0
  done <<< "$IDENTITIES"
  return 1
}

failed=0; quiesced=0; already=0; foreign=0; roots_matched=0; roots_skipped=0

# ── The anchor ───────────────────────────────────────────────────────
ANCHOR_JSON=$(bd_json show "$BEAD")
if [ -z "$(printf '%s' "$ANCHOR_JSON" | tr -d '[:space:]')" ]; then
  # An unreadable bead is not proof of anything. Refuse before writing.
  echo "$PROG: cannot read $BEAD ('gc bd show' returned nothing) — refusing to park a bead this store did not answer for. Nothing was written." >&2
  exit 2
fi

anchor_get() {
  printf '%s' "$ANCHOR_JSON" | first_of | jq -r --arg k "$1" '
    if $k == "status" then (.status // "")
    elif $k == "assignee" then (.assignee // "")
    else (.metadata[$k] // "") end' 2>/dev/null
}

A_STATUS=$(anchor_get status)
A_WHO=$(anchor_get assignee)
if [ -z "$A_STATUS" ]; then
  echo "$PROG: $BEAD resolved to no issue (bd answered, but with no such bead) — nothing was written." >&2
  exit 2
fi

if [ "$STEPS_ONLY" -eq 0 ] && [ -n "$A_WHO" ] && ! is_ours "$A_WHO"; then
  # Parking a bead somebody else holds is not a hold, it is a theft of their
  # claim. The duplicate-dispatch arm wants exactly this case and passes
  # --steps-only, which never reaches here.
  echo "$PROG: $BEAD is held by '$A_WHO', which is not one of this session's identities ($(printf '%s' "$IDENTITIES" | tr '\n' ' ')). Refusing to park another holder's bead — pass --steps-only to quiesce this molecule and leave the anchor to its owner. Nothing was written." >&2
  exit 2
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown-time")
BY="${GC_SESSION_NAME:-${GC_ALIAS:-${GC_AGENT:-unknown-session}}}"

# The hold is RECORDED BEFORE it is performed. A run that dies between here and
# the walk leaves an explained bead; the reverse order leaves a de-routed bead
# nobody can account for, which is worse than the husk.
HOLD_NOTE="Dispatch HELD by $BY at $NOW (hold-dispatch.sh).

$REASON"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "$PROG: DRY RUN — would append the hold note to $BEAD"
elif gc bd update "$BEAD" --append-notes "$HOLD_NOTE" >/dev/null 2>&1; then
  echo "$PROG: recorded the hold on $BEAD"
else
  # Not fatal: the delivery keys are what actually stop the re-offer, and a bead
  # parked without its note is recoverable by hand. Say so loudly and continue.
  echo "$PROG: could not append the hold note to $BEAD — continuing with the park, but the reason is NOT recorded on the bead" >&2
  failed=$((failed + 1))
fi

# clear_delivery <id> <label> — unset every delivery key the bead actually
# carries, in ONE call. Returns non-zero if the write was refused, which gates
# the assignee half. Never touches `assignee`; never touches status.
clear_delivery() {
  local id="$1" label="$2" k v
  local -a args=()
  local -a present=()
  for k in gc.routed_to gc.execution_routed_to \
           gc.deferred_routed_to gc.deferred_execution_routed_to \
           gc.deferred_assignee gc.session_affinity; do
    v=$(printf '%s' "$3" | jq -r --arg k "$k" '.[$k] // ""' 2>/dev/null)
    [ -n "$v" ] || continue
    present+=("$k")
    args+=(--unset-metadata "$k")
  done
  if [ "${#args[@]}" -eq 0 ]; then
    return 0
  fi
  echo "  $label: clearing ${present[*]}"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if gc bd update "$id" "${args[@]}" >/dev/null 2>&1; then
    return 0
  fi
  echo "$PROG: $id delivery clear failed; the bead is UNCHANGED and still deliverable" >&2
  return 1
}

# clear_assignee <id> <who> — release a claim that is OURS. Plain first; bare
# `bd --force` only when the claim guard refuses, and only over one of this
# session's own identities (see the header).
clear_assignee() {
  local id="$1" who="$2"
  [ -n "$who" ] || return 0
  if ! is_ours "$who"; then
    echo "$PROG: $id is assigned to '$who', not this session — left untouched (a step held by another session belongs to a live molecule)" >&2
    foreign=$((foreign + 1))
    return 1
  fi
  echo "  $id: releasing our own claim ('$who')"
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  if gc bd update "$id" --assignee "" >/dev/null 2>&1; then
    return 0
  fi
  if [ -z "$BD_BIN" ]; then
    echo "$PROG: $id assignee clear was refused and bd is not on PATH (gc bd cannot pass --force); the bead keeps its assignee" >&2
    return 1
  fi
  if "$BD_BIN" update "$id" --assignee "" --force >/dev/null 2>&1; then
    return 0
  fi
  echo "$PROG: $id assignee clear failed even with --force; the bead keeps its assignee" >&2
  return 1
}

if [ "$STEPS_ONLY" -eq 1 ]; then
  echo "$PROG: --steps-only: leaving the anchor's delivery keys and assignee to their owner"
else
  A_META=$(printf '%s' "$ANCHOR_JSON" | first_of | jq -c '.metadata // {}' 2>/dev/null)
  [ -n "$A_META" ] || A_META='{}'
  route_ok=1
  # The anchor's own `gc.routed_to` is written EMPTY rather than unset — the
  # spelling every other writer of a parked anchor uses. clear_delivery unsets
  # the rest, so the two are issued as one update by listing the set here.
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  $BEAD (anchor): would clear gc.routed_to and every other delivery key present"
  else
    a_args=(--set-metadata "gc.routed_to=")
    for k in gc.execution_routed_to gc.deferred_routed_to \
             gc.deferred_execution_routed_to gc.deferred_assignee; do
      v=$(printf '%s' "$A_META" | jq -r --arg k "$k" '.[$k] // ""' 2>/dev/null)
      [ -n "$v" ] && a_args+=(--unset-metadata "$k")
    done
    if gc bd update "$BEAD" "${a_args[@]}" >/dev/null 2>&1; then
      echo "  $BEAD (anchor): delivery cleared"
    else
      echo "$PROG: $BEAD delivery clear failed; the anchor is UNCHANGED and still deliverable" >&2
      route_ok=0
      failed=$((failed + 1))
    fi
  fi
  if [ -n "$A_WHO" ] && [ "$route_ok" -eq 1 ]; then
    # `in_progress` with no assignee is a state nothing writes on purpose, so
    # the release carries the status back to `open` in the same call. Any other
    # status is left alone: a `blocked` anchor is blocked for a reason this
    # script does not know.
    a_rel=(--assignee "")
    [ "$A_STATUS" = "in_progress" ] && a_rel+=(--status=open)
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  $BEAD (anchor): would release our own claim ('$A_WHO')"
    elif gc bd update "$BEAD" "${a_rel[@]}" >/dev/null 2>&1; then
      echo "  $BEAD (anchor): claim released"
    elif [ -n "$BD_BIN" ] && "$BD_BIN" update "$BEAD" --assignee "" --force >/dev/null 2>&1; then
      echo "  $BEAD (anchor): claim released (--force)"
    else
      echo "$PROG: $BEAD assignee clear failed; the anchor keeps its assignee" >&2
      failed=$((failed + 1))
    fi
  elif [ -n "$A_WHO" ]; then
    echo "$PROG: $BEAD assignee clear skipped (delivery clear failed; clearing it now would leave the anchor unassigned and still routed)" >&2
  fi
fi

# ── The molecule(s) ──────────────────────────────────────────────────
# FORWARD walk first, because the caller starts from the anchor and the anchor
# HAS a forward pointer: the synthetic one-item input convoy that `tracks` it,
# named back on each root as `gc.input_convoy_id`. It is also the only walk that
# finds EVERY root — a re-poured bead is tracked by one convoy per pour, each
# naming a different root, and a walk that keeps one leaves the others routed
# while reporting nothing (docs/gascity-dispatch-containment.md step 1).
CONVOYS=$(bd_json dep list "$BEAD" --direction=up -t tracks \
  | jq -r 'if type == "array"
           then (.[] | select((((.issue_type // .type) // "") | ascii_downcase) == "convoy") | .id)
           else empty end' 2>/dev/null)

ROOTS=""
for convoy in $CONVOYS; do
  [ -n "$convoy" ] || continue
  found=$(bd_json list --metadata-field "gc.input_convoy_id=$convoy" \
    --metadata-field "gc.kind=workflow" --status "$LIVE" --limit=0 \
    | jq -r 'if type == "array" then .[].id else empty end' 2>/dev/null)
  ROOTS=$(printf '%s\n%s\n' "$ROOTS" "$found")
done

# Legacy source-workflow roots carry the pointer on the bead instead. UNION it
# in rather than consulting it only when the convoy path came back empty: a bead
# can be tracked by a real convoy AND still be running under a legacy-shape
# workflow, and either lookup alone leaves the other root routed.
LEGACY=$(printf '%s' "$ANCHOR_JSON" | first_of | jq -r '.metadata.workflow_id // empty' 2>/dev/null)
if [ -n "$LEGACY" ]; then
  alive=$(bd_json show "$LEGACY" | first_of | jq -r 'select((.status // "") != "closed") | .id' 2>/dev/null)
  [ -n "$alive" ] && ROOTS=$(printf '%s\n%s\n' "$ROOTS" "$alive")
fi

ROOTS=$(printf '%s\n' "$ROOTS" | awk 'NF && !seen[$0]++')

if [ -z "$ROOTS" ]; then
  # The forward edge is missing or unreadable. Fall back to the REVERSE scan the
  # sibling passes use — enumerate live graph.v2 steps and take their roots — so
  # a broken `tracks` edge costs a listing rather than a silent miss. Every root
  # it produces still faces the same anchor-match gate below, so widening the
  # candidate set removes no guard.
  echo "$PROG: no root reached through the input convoy; falling back to the reverse step scan" >&2
  ROOTS=$(bd_json list --status "$LIVE" --limit=0 \
    | jq -r 'if type == "array"
             then (.[] | select((.metadata["gc.step_ref"] // "") != "")
                       | (.metadata["gc.root_bead_id"] // "")
                       | select(. != ""))
             else empty end' 2>/dev/null | awk 'NF && !seen[$0]++')
fi

if [ -z "$ROOTS" ]; then
  echo "$PROG: no graph.v2 molecule found for $BEAD — nothing to quiesce (an attached root-only wisp has no step graph; see docs/gascity-dispatch-containment.md)"
else
  while IFS= read -r root; do
    [ -n "${root:-}" ] || continue

    # FAIL CLOSED. Resolve the anchor the way the formula does — root ->
    # gc.input_convoy_id -> the convoy's SINGLE tracked member — and act only
    # when it IS the bead being held. Both mol-polecat-base and mol-scoped-work
    # refuse to run on any other member count, so anything else is a shape this
    # script does not understand. Refusing costs a husk that stays noisy;
    # guessing costs a live molecule drained out from under a running polecat.
    r_convoy=$(bd_json show "$root" | first_of | jq -r '.metadata["gc.input_convoy_id"] // empty' 2>/dev/null)
    r_anchor=""
    if [ -n "$r_convoy" ]; then
      r_anchor=$(gc convoy status "$r_convoy" --json 2>/dev/null \
        | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)
    fi
    if [ -z "$r_anchor" ] || [ "$r_anchor" != "$BEAD" ]; then
      roots_skipped=$((roots_skipped + 1))
      continue
    fi
    roots_matched=$((roots_matched + 1))
    echo "$PROG: molecule $root (anchor $BEAD)"

    STEPS=$(bd_json list --metadata-field "gc.root_bead_id=$root" --status "$LIVE" --limit=0 \
      | jq -c 'if type == "array"
               then (.[] | { id,
                             step:     (.metadata["gc.step_ref"] // ""),
                             routed:   (.metadata["gc.routed_to"] // ""),
                             assignee: (.assignee // ""),
                             meta:     (.metadata // {}) })
               else empty end' 2>/dev/null)
    if [ -z "$STEPS" ]; then
      echo "$PROG: could not list the steps of $root; its molecule was NOT quiesced" >&2
      failed=$((failed + 1))
      continue
    fi

    while IFS= read -r row; do
      [ -n "$row" ] || continue
      sid=$(printf '%s' "$row"  | jq -r '.id // empty' 2>/dev/null)
      step=$(printf '%s' "$row" | jq -r '.step // empty' 2>/dev/null)
      routed=$(printf '%s' "$row" | jq -r '.routed // empty' 2>/dev/null)
      who=$(printf '%s' "$row"  | jq -r '.assignee // empty' 2>/dev/null)
      meta=$(printf '%s' "$row" | jq -c '.meta // {}' 2>/dev/null)
      [ -n "$sid" ] || continue

      # The finalize step is the molecule's only escape path. Guarded by step id
      # AND by route, because losing this one needs a hand repair.
      case "$step" in *.workflow-finalize) continue ;; esac
      case "$routed" in *control-dispatcher*) continue ;; esac

      # Idempotent: a step with no delivery key and no assignee was already
      # quiesced, by an earlier run or by hand.
      pins=$(printf '%s' "$meta" | jq -r '[ to_entries[]
        | select(.key == "gc.routed_to" or .key == "gc.execution_routed_to"
              or .key == "gc.deferred_routed_to" or .key == "gc.deferred_execution_routed_to"
              or .key == "gc.deferred_assignee" or .key == "gc.session_affinity")
        | select((.value // "") != "") ] | length' 2>/dev/null)
      [ -n "$pins" ] || pins=0
      if [ "$pins" -eq 0 ] && [ -z "$who" ]; then
        already=$((already + 1)); continue
      fi

      step_ok=1
      if clear_delivery "$sid" "$sid ($step)" "$meta"; then
        if [ -n "$who" ]; then
          clear_assignee "$sid" "$who" || step_ok=0
        fi
      else
        step_ok=0
        if [ -n "$who" ]; then
          echo "$PROG: $sid assignee clear skipped (delivery clear failed; clearing it now would leave the step open+unassigned+routed)" >&2
        fi
      fi
      if [ "$step_ok" -eq 1 ]; then
        quiesced=$((quiesced + 1))
      else
        failed=$((failed + 1))
      fi
    done <<< "$STEPS"
  done <<< "$ROOTS"
fi

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
SUMMARY="${MODE}${quiesced} step(s) quiesced across $roots_matched molecule(s) of $BEAD; $already already quiet, $roots_skipped root(s) skipped (anchor did not match), $foreign step(s) left to another session, $failed failed"
echo "$PROG: $SUMMARY"

# Append what was actually done, in the past tense, and only what landed. The
# hold note above says WHY; this says WHAT, so a reader of the bead can tell a
# completed park from one that gave up halfway — the distinction the hand-written
# park could never record because it never knew.
if [ "$DRY_RUN" -eq 0 ]; then
  gc bd update "$BEAD" --append-notes "Molecule park (hold-dispatch.sh): $SUMMARY. No step was closed and no step status was rewritten; workflow-finalize keeps its control-dispatcher route." >/dev/null 2>&1 \
    || echo "$PROG: could not append the park summary to $BEAD" >&2
fi

[ "$failed" -eq 0 ] || exit 1
exit 0
