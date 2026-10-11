#!/usr/bin/env bash
# refinery-stuck-escalate — the witness patrol's check on the refinery's inbound
# queue: escalate a handoff that has gone genuinely stuck, and the blind monitor
# when the queue cannot be read, but never transient churn.
#
#   refinery-stuck-escalate.sh --binding-prefix <prefix, e.g. gc-toolkit.>
#
# The refinery session claims open, branch-bearing work assigned to it with no
# merge_result, prepares the branch, and stamps the first merge_result; the
# refinery-reconcile cadence then owns the anchor and clears its assignee
# (docs/refinery-merge-cadence.md). So the beads still assigned to the refinery
# are its inbound queue: fresh handoffs and rebase/rework tasks. Both turn over
# on their own, a handoff within a poll interval and a rebase task once the fix
# pool claims it, so their count is churn, not a health signal. What a human
# must see is one bead that has sat untouched far past that turnover.
#
# One escalate.sh call per stuck bead: escalate.sh narrows its dedup to a durable
# subject, so each stuck bead gets its own visit and a churning queue files none.
# A queue that will not parse even after the control-byte strip escalates once
# under its own key, and so does a refinery address that resolves to no live
# agent, without reading a queue: either way the monitor is blind, and a blind
# monitor is surfaced rather than silently trusted.
#
# The counterpart retract closes the loop. A handoff an open visit escalates
# that a queue read at the refinery's verified address no longer carries is read
# by id, and its visit is retracted moot through escalate.sh --retract only when
# that read shows the handoff closed, prepared, or assigned away from the
# refinery. A listing that omits a handoff still sitting with the refinery
# withdraws nothing, and a handoff that cannot be read keeps its visit.
#
# GC_RIG rig-qualifies the refinery address; GC_BEAD_ID or GC_SESSION_ID names
# the patrol run a blind-monitor escalation is filed against.
# Called by mol-witness-patrol's check-refinery step.
# env: GC_ESCALATE_TOOL and GC_RESOLVE_ROUTE_TOOL replace the sibling scripts.
# exit: 0 the check ran (each escalation's failure is reported on stderr)
#       · 2 usage

PROG="refinery-stuck-escalate"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="${GC_ESCALATE_TOOL:-$SCRIPTS_DIR/escalate.sh}"
RESOLVE_ROUTE="${GC_RESOLVE_ROUTE_TOOL:-$SCRIPTS_DIR/resolve-route.sh}"

BINDING_PREFIX=""; HAVE_PREFIX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --binding-prefix)
      [ "$#" -ge 2 ] || { echo "$PROG: --binding-prefix requires a value" >&2; exit 2; }
      BINDING_PREFIX="$2"; HAVE_PREFIX=1; shift 2 ;;
    *) echo "usage: $PROG --binding-prefix <prefix>" >&2; exit 2 ;;
  esac
done
[ "$HAVE_PREFIX" = 1 ] || { echo "usage: $PROG --binding-prefix <prefix>" >&2; exit 2; }

# The queue is whatever is assigned to the refinery's live identity, so the
# address is resolved against the roster rather than assembled: bd lists an
# address no agent holds as a valid empty array, which reads exactly like a
# clean queue. The rig-qualified form goes in, as in bug-dispatch, so an
# unreadable roster (exit 3) echoes back, unverified, a name a rig-scoped
# refinery can hold. A refusal prints nothing, which leaves REFINERY empty.
if REFINERY=$("$RESOLVE_ROUTE" "${GC_RIG:+$GC_RIG/}${BINDING_PREFIX}refinery"); then ROUTE_RC=0; else ROUTE_RC=$?; fi
# A bead assigned to the refinery clears on its own: a handoff within a poll
# interval, a rebase/rework task within the fix pool's work time (observed under
# ~2h). Past this bound it is not churn; the session is not advancing it.
# Conservative on purpose: a false escalation here is the defect this check fixes.
STUCK_SECS=14400
NOW=$(date -u +%s)
# Under a strict shell a plain VAR=$(...) capture exits the script at a failed
# listing, before the arms below can tell an unreadable queue from a healthy one.
# bd's --json can emit a raw control byte inside a bead string (an unescaped
# newline from a multi-paragraph note), which is invalid JSON and aborts jq;
# scrub drops the control bytes JSON forbids raw before the parse,
# the same strip the witness's orphan recovery applies to its bd --json read.
# The common blinding case is a control byte in an otherwise-valid queue, which
# the strip rescues. An unresolved address is never read.
QUEUE=""
QUEUE_RC=0
if [ -n "$REFINERY" ]; then
  if QUEUE=$(gc bd list --assignee="$REFINERY" --status=open --exclude-type=epic --has-metadata-key=branch --json --limit=0 | scrub); then QUEUE_RC=0; else QUEUE_RC=$?; fi
fi
# Keep only the session's own inbound work (merge_result empty; a gating anchor
# carries one and belongs to the cadence, and is unassigned anyway) that has sat
# past the bound. A listing that is not an array yields nothing (STUCK_N empty),
# which the unreadable arm below catches and escalates.
STUCK=$(printf '%s' "$QUEUE" | jq -c --argjson now "$NOW" --argjson max "$STUCK_SECS" 'if type == "array" then [ .[] | select((.metadata.merge_result // "") == "") | select($now - ((.updated_at | fromdateiso8601?) // $now) > $max) | {id, updated_at} ] else empty end' 2>/dev/null) || STUCK=""
STUCK_N=$(printf '%s' "$STUCK" | jq 'if type == "array" then length else empty end' 2>/dev/null) || STUCK_N=""
case "${STUCK_N:-}" in
  ''|*[!0-9]*) STUCK_N="" ;;
esac
if [ -z "$REFINERY" ]; then
  # No live agent carries the address, so there is no queue to read. A listing
  # there would come back empty and look healthy, so no stuck handoff would ever
  # escalate. The monitor is blind, so escalate that under its own key, the way
  # an unreadable queue is escalated.
  echo "check-refinery: no live refinery identity resolves from '${GC_RIG:+$GC_RIG/}${BINDING_PREFIX}refinery'; read no queue and retracted nothing; escalating the blind monitor" >&2
  "$ESCALATE" --subject "${GC_BEAD_ID:-${GC_SESSION_ID:-refinery}}" --key witness-refinery-queue-unroutable --message "check-refinery cannot resolve the refinery address it builds for rig ${GC_RIG:-<unset>} to a live agent identity, so it read no queue. A listing at an address no agent holds returns an empty array that looks like a clean queue, so the stuck-handoff monitor is blind until the address resolves. Compare the binding_prefix this witness patrol was poured with against the refinery identity in gc agent list." || echo "check-refinery: refinery address unroutable AND escalation failed" >&2
elif [ "$QUEUE_RC" -ne 0 ] || [ -z "$STUCK_N" ]; then
  # Genuinely unreadable: bd failed, or the listing is not a JSON array even
  # after the control-byte strip. A blinded monitor lets a genuinely stuck
  # handoff go unseen, so escalate the blind monitor itself. escalate.sh dedups
  # one open visit per key, so a persistently blind read files one visit, not a
  # storm. The subject is this patrol run (a wisp id, or the session as a
  # fallback); escalate.sh redirects an ephemeral subject onto the standing
  # triage bucket.
  echo "check-refinery: refinery queue unreadable (rc=$QUEUE_RC; not a JSON array after the control-byte strip); escalating the blind monitor" >&2
  "$ESCALATE" --subject "${GC_BEAD_ID:-${GC_SESSION_ID:-refinery}}" --key witness-refinery-queue-unreadable --message "check-refinery cannot read the refinery queue (rc=$QUEUE_RC; the bd --json listing is not a JSON array even after stripping control bytes). The stuck-handoff monitor is blind, so a genuinely stuck refinery handoff would go unseen until this is fixed. Inspect the refinery queue listing and the store's health." || echo "check-refinery: queue unreadable AND escalation failed (rc=$QUEUE_RC)" >&2
elif [ "$STUCK_N" -eq 0 ]; then
  echo "check-refinery: no stuck handoffs; the queue is churning normally" >&2
else
  printf '%s' "$STUCK" | jq -r '.[] | .id + " " + (.updated_at // "unknown")' | while read -r SID SWHEN; do
    "$ESCALATE" --subject "$SID" --key witness-refinery-queue --message "Refinery handoff $SID has sat assigned to $REFINERY, unprepared, since $SWHEN, past the ${STUCK_SECS}s stuck bound while the session kept polling. It is not draining on its own; inspect the bead and the refinery session." || echo "check-refinery: escalate failed for $SID" >&2
  done
fi
# A handoff that has left the refinery queue is no longer sitting unprepared, so
# its stuck-handoff escalation is premise-moot: retract the open visit through
# escalate.sh --retract (which closes it moot via visit-close.sh, stamping
# gc.outcome) rather than leaving it open for a bare close that records no
# outcome.
#
# Absence from the queue listing makes a handoff a candidate, never proof that it
# left. A listing under a wrong address, from the wrong store, or cut short is
# still a readable array, and it omits handoffs that never moved. So each
# candidate is read by id, and its visit is retracted only when that read shows
# the handoff closed, carrying a merge_result, or assigned to something other
# than a refinery. The assignee is compared by role, the address with its rig
# qualifier and binding prefix stripped (resolve-route.sh's role), so an address
# this cycle got wrong cannot make a still-assigned handoff read as reassigned.
# bd drops an id it cannot resolve and still exits 0, so each candidate is judged
# by its own row, and a candidate with no row is left open, as is one still
# assigned to a refinery.
#
# The candidate pass runs only after a queue read that parsed as an array
# ($STUCK_N set), at an address the roster verified (resolve-route.sh exit 0).
# A failed queue read leaves every visit as it is until a later cycle reads the
# queue, and so does an unreadable roster (exit 3): the address is then the
# rendered name echoed back unproven, and the role each candidate is compared
# against comes from it. A wrong retract closes the visit moot, which
# escalate.sh's verdict window holds against a re-escalation of that handoff for
# a day by default. Only a visit whose group is exactly the handoff bead id is a
# candidate. A legacy group carrying extra tokens (a malformed-subject filing)
# names no handoff, so this arm leaves it. Such a visit was filed in error, and
# it closes through visit-close.sh with outcome moot, never a bare gc bd close.
if [ "$ROUTE_RC" -eq 0 ] && [ "$QUEUE_RC" -eq 0 ] && [ -n "$STUCK_N" ]; then
  QUEUE_IDS_JSON=$(printf '%s' "$QUEUE" | jq -c 'if type == "array" then [.[].id] else [] end' 2>/dev/null)
  [ -n "$QUEUE_IDS_JSON" ] || QUEUE_IDS_JSON="[]"
  CANDIDATES=$(gc bd list --status=open,in_progress --has-metadata-key=escalation_key --json --limit=0 2>/dev/null | scrub | jq -c --argjson q "$QUEUE_IDS_JSON" 'if type == "array" then [ .[] | select((.metadata.escalation_key // "") == "witness-refinery-queue") | select((.metadata.task_kind // "") == "visit") | (.metadata["gc.continuation_group"] // "") as $g | select($g | test("^[A-Za-z0-9._-]+$")) | select(($q | index($g)) == null) | $g ] else [] end' 2>/dev/null) || CANDIDATES=""
  CANDIDATE_IDS=$(printf '%s' "$CANDIDATES" | jq -r 'if type == "array" then join(",") else empty end' 2>/dev/null) || CANDIDATE_IDS=""
  if [ -n "$CANDIDATE_IDS" ]; then
    # One read for every candidate, closed ones included.
    HANDOFFS=$(gc bd list --id="$CANDIDATE_IDS" --all --json --limit=0 2>/dev/null | scrub) || HANDOFFS=""
    printf '%s' "$CANDIDATES" | jq -r '.[]' | while IFS= read -r RSUBJ || [ -n "$RSUBJ" ]; do
      [ -n "$RSUBJ" ] || continue
      # "left <reading>" or "stays <reading>"; empty when the read returned no
      # row for this candidate or did not parse.
      VERDICT=$(printf '%s' "$HANDOFFS" | jq -r --arg id "$RSUBJ" --arg r "$REFINERY" '
        def role: sub("^.*/"; "") | sub("^.*[.]"; "");
        if type != "array" then empty else
          ([ .[] | select((.id // "") == $id) ] | .[0]) as $b
          | ($b.assignee // "") as $who
          | if $b == null then empty
            elif ($b.status // "") == "closed" then "left is closed"
            elif ($b.metadata.merge_result // "") != "" then "left carries merge_result=" + ($b.metadata.merge_result | tostring)
            elif $who == "" then "left is unassigned"
            elif ($who | role) != ($r | role) then "left is assigned to " + $who + ", not a refinery"
            else "stays assigned to " + $who + " (status " + ($b.status // "unknown") + ")" end
        end' 2>/dev/null) || VERDICT=""
      case "$VERDICT" in
        "left "*)
          "$ESCALATE" --retract --subject "$RSUBJ" --key witness-refinery-queue --message "Refinery handoff $RSUBJ ${VERDICT#left }, so it has left the refinery queue and is no longer sitting unprepared; the stuck-handoff escalation is moot." || echo "check-refinery: retract failed for $RSUBJ" >&2 ;;
        "stays "*)
          echo "check-refinery: $RSUBJ is missing from the queue listing but is still unprepared and ${VERDICT#stays }; its escalation stays open" >&2 ;;
        *)
          echo "check-refinery: could not read handoff $RSUBJ; its escalation stays open" >&2 ;;
      esac
    done
  fi
fi
