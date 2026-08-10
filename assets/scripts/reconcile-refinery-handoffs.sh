#!/usr/bin/env bash
# reconcile-refinery-handoffs — recover merge handoffs stranded by a NEAR-MISS
# refinery address, i.e. an assignee that is almost this rig's canonical refinery
# identity but not exactly it, and that no session answers to (tk-0nn3f).
#
# THE BUG, REPRODUCED LIVE (shutupandlisten witness, 2026-07-23). su-lou.13 was
# handed off for merge with assignee "shutupandlisten/refinery" — the canonical
# identity is "shutupandlisten/gc-toolkit.refinery", so the address was missing the
# `gc-toolkit.` binding prefix. The refinery's find-work query is an EXACT match:
#
#   gc bd list --assignee=$GC_AGENT --status=open --exclude-type=epic \
#     --has-metadata-key=branch
#
# and it was verified both ways: the canonical assignee returned EMPTY while the
# near-miss returned the bead. The refinery sat ACTIVE with an empty queue for
# ~1h07m while completed, pushed work waited invisibly. A human witness found it
# and repaired the assignee by hand; the bead then opened its PR immediately.
#
# WHY NOTHING CAUGHT IT — this shape is invisible to EVERY existing pass at once:
#
#   refinery find-work            exact `--assignee=$GC_AGENT`; the near-miss misses
#   check-set-heal phase 0        enumerates on `pr_url`/`pr_number` — the handoff
#                                 has neither, no PR was ever opened
#   check-set-heal phase 1        enumerates on `merge_result` — never stamped, the
#                                 refinery never saw the bead to stamp it
#   witness recover-orphaned      SKIPS assignees that look like infrastructure
#                                 identities ("beads assigned to the refinery,
#                                 witness, or other infrastructure agents should be
#                                 skipped") — a near-miss refinery address reads as
#                                 exactly that, so recovery steps over it
#   witness check-refinery        queries the CANONICAL assignee, gets nothing, and
#                                 its own docs read that as healthy: "Empty queue:
#                                 No work assigned — refinery is idle, which is fine"
#
# An idle refinery with an empty queue is indistinguishable from the healthy state,
# so there is no signal anywhere and the strand is unbounded — the handing-off agent
# reports success and "watches to land" forever.
#
# WHY THIS PASS REPAIRS, WHERE check-set-heal's FLAG ARM DELIBERATELY DOES NOT.
# check-set-heal already flags a non-canonical assignee on a GATING anchor and
# refuses to rewrite it ("the identity is an operator call", tk-wsxd0). That call is
# right for THAT set and is left untouched here: a gating anchor carries
# `merge_result`, so every bead-keyed pass — merge-skill, the observer, the heal
# itself — still enumerates and lands it. Its assignee is a visibility wart, and a
# wrong rewrite could move a live bead out from under whoever holds it: all risk, no
# recovery.
#
# The set THIS pass takes is the opposite case. A pre-PR handoff has NO
# `merge_result` and NO `pr_url`, so no bead-keyed pass can see it; the assignee is
# the ONLY path by which it is ever processed. Flagging alone leaves the work
# stranded behind a stderr line until a human reads a patrol log — which is what the
# live incident already proved costs over an hour of a completed PR's life. So here
# the rewrite IS the repair, and it is taken only once this pass has PROVED there is
# no holder to take it from. The two sets are disjoint by construction (this pass
# requires an ABSENT merge_result), so neither pass can act on the other's beads.
#
# WHAT IT WILL NOT DO — every one of these is report-only, bounded to one warning
# per offending value by a marker on the bead, because each is a case where a
# rewrite could be the wrong answer and a human must decide:
#
#   a LIVE session answers to the near-miss   somebody really is called that; the
#                                             CANONICAL string is then the suspect
#   the address names ANOTHER rig             cross-rig routing can be deliberate
#   the canonical identity resolves to        rewriting would move the bead from one
#     no session at all                       dead address to another and silence the
#                                             signal without delivering the work —
#                                             the "template guesses a name no session
#                                             holds" failure, from the other end
#   the roster could not be read, or is       an empty roster makes EVERY address
#     empty while sessions exist              look dead; repairing on it would rewrite
#                                             assignees out from under live agents
#
# The fail-safe direction is always "leave it and say so": an un-repaired strand is
# the status quo this pass improves on, while a wrong rewrite creates a new one.
#
# But "say so" has to mean more than a log line for the ONE refusal that means work
# is stranded and this pass cannot fix it — an unresolvable canonical identity. A
# stderr line in a patrol log is the same weak signal this whole bug is made of (the
# live case was found by a human noticing, not by a report), so that arm also mails
# the mayor, bounded by the same per-bead marker. The benign refusals do not: a live
# holder and deliberate cross-rig routing are not incidents, and mailing them would
# train the reader to ignore the ones that are.
#
# NOT set -e: best-effort, must never abort the patrol mid-pass. Any tool error
# skips that bead and retries next cycle. The pass DOES exit non-zero when a repair
# it decided on could not be verified — the call sites treat that as non-fatal and
# retry, and a silent exit 0 over a failed write is how this class hides.
set -uo pipefail

REFINERY_ID=""
DRY_RUN=0
while [ $# -gt 0 ]; do
  case "$1" in
    --refinery) REFINERY_ID="${2:-}"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    *)          shift ;;
  esac
done

# Without a canonical identity there is nothing to compare against and every
# assignee would look wrong. Same skip check-set-heal takes for the same reason.
if [ -z "$REFINERY_ID" ]; then
  echo "reconcile-refinery-handoffs: no --refinery identity given; skipping (nothing to compare against)" >&2
  exit 0
fi

# The canonical identity's own shape, split once: the rig qualifier (everything
# before the last "/", empty in an HQ-only city) and the local part.
CANON_RIG=""
case "$REFINERY_ID" in */*) CANON_RIG="${REFINERY_ID%/*}" ;; esac

# --- session roster: who actually answers to an address --------------------
# Two sources, exactly as the witness's liveness recipe uses (mol-witness-patrol
# recover-orphaned-beads). `gc session list` returns an OBJECT {sessions:[...]},
# and its fields are lowercase snake_case; an identity may be recorded as any of
# id / name / session_name / alias / agent_name, so all five are keys. Verified
# live: this rig's refinery answers to "gc-toolkit/gc-toolkit.refinery" on its
# `alias` field, with `name` null and `closed` null.
#
# The session BEADS are the second source and they are not optional: a configured
# named session that is not currently spawned (scale-from-zero) may be absent from
# the live roster while its `configured_named_identity` still names the address
# that owns the queue. Without them a refinery between spawns would read as "no
# session holds the canonical identity" and every repair would be refused exactly
# when the queue most needs filling.
#
# Both blobs go to jq on STDIN, never `--argjson` on argv: on a busy city the
# session `command` fields overflow ARG_MAX ("argument list too long: jq").
SESSIONS_JSON=$(gc session list --state=all --json 2>/dev/null) || SESSIONS_JSON=""
SESSION_BEADS_JSON=$(gc bd list --type=session --label=gc:session --include-infra \
  --include-gates --all --json --limit=0 2>/dev/null) || SESSION_BEADS_JSON=""

SESSION_COUNT=$(printf '%s' "$SESSIONS_JSON" | jq -r '(.sessions // []) | length' 2>/dev/null)
[ -n "$SESSION_COUNT" ] || SESSION_COUNT=0

# Every identifier form of every session that is NOT closed or archived. A
# `drained`, `asleep`, `suspended` or `quarantined` session still has an owner and
# still counts as alive — the same classification the witness applies, so the two
# passes cannot disagree about who exists.
ALIVE_IDS=$(printf '%s' "$SESSIONS_JSON" | jq -r '
  (.sessions // [])[]
  | select(((.closed // false) | not))
  | select((((.state // "") | ascii_downcase)) as $s | $s != "closed" and $s != "archived")
  | [.id, .name, .session_name, .alias, .agent_name][]
  | select(. != null and . != "")' 2>/dev/null)

ALIVE_NAMED=$(printf '%s' "$SESSION_BEADS_JSON" | jq -r '
  .[]?
  | select(((.status // "") | ascii_downcase) != "closed")
  | select(((((.metadata // {}).state // "") | ascii_downcase)) as $s
           | $s != "closed" and $s != "archived")
  | ((.metadata // {}).configured_named_identity // empty)
  | select(. != "")' 2>/dev/null)

if [ -n "$ALIVE_NAMED" ]; then
  ALIVE_IDS="${ALIVE_IDS:+$ALIVE_IDS
}$ALIVE_NAMED"
fi

# FAIL SAFE — never repair on an unreadable or empty roster. An empty identity set
# resolves every address to "nobody holds it", which is the permissive direction
# here: it would rewrite assignees out from under live agents. Report-only for the
# pass; the next cycle re-reads.
ROSTER_OK=1
if [ -z "$ALIVE_IDS" ]; then
  ROSTER_OK=0
  echo "reconcile-refinery-handoffs: FAIL-SAFE the session roster is empty or unreadable ($SESSION_COUNT session(s) listed); NOT repairing any assignee this pass — an empty roster makes every address look unheld. Reporting only; retries next cycle" >&2
fi

# Membership test against the roster. A here-string, never a `... | grep -qxF`
# pipeline: `set -o pipefail` is on and `grep -q` exits at its first match, which
# SIGPIPEs the writer and reports 141 — a true answer read as false, decided by
# nothing but how much text followed the match.
is_alive() {
  [ -n "${1:-}" ] || return 1
  [ "$ROSTER_OK" = 1 ] || return 1
  grep -Fxq -- "$1" <<< "$ALIVE_IDS"
}

CANON_ALIVE=0
is_alive "$REFINERY_ID" && CANON_ALIVE=1

# --- candidate enumeration -------------------------------------------------
# The handoff shape, and nothing else: OPEN, carrying `metadata.branch` (what the
# done sequence stamps and what find-work filters on), not an epic.
RAW=$(gc bd list --status=open --has-metadata-key=branch --exclude-type=epic \
  --limit=0 --json 2>/dev/null)
RC=$?
if [ "$RC" -ne 0 ] || [ -z "$RAW" ] \
   || ! printf '%s' "$RAW" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "reconcile-refinery-handoffs: WARN the open-handoff enumeration did not return a readable result (rc=$RC); nothing examined this pass, retries next cycle" >&2
  exit 0
fi

# Narrow to the INVISIBLE set — the beads no other pass can reach:
#   assignee set, and not the canonical identity     (nothing else to recover)
#   merge_result ABSENT   the bead-keyed passes enumerate on it; a bead that HAS
#                         one is visible to them and belongs to check-set-heal's
#                         flag-only arm, never to this pass's rewrite
#   gc.routed_to ABSENT   a live route means a POOL still owns the bead; the done
#                         sequence clears the route when it hands to the refinery,
#                         so a routed bead is not a completed handoff
#   the assignee's role segment is exactly `refinery` — the last "/"-segment with
#   any binding prefix (`<prefix>.`) stripped. `gc-toolkit.refinery-2` has role
#   `refinery-2` and is left alone; guessing wider is how a rewrite hits a real
#   session that merely sounds similar.
CANDIDATES=$(printf '%s' "$RAW" | tr -d '\000-\010\013\014\016-\037' | jq -c --arg canon "$REFINERY_ID" '
  .[]
  | ((.metadata // {})) as $m
  | (((.assignee // "") | tostring)) as $a
  | select($a != "" and $a != $canon)
  | select(((($m.merge_result // "") | tostring)) == "")
  | select(((($m["gc.routed_to"] // "") | tostring)) == "")
  | (($a | sub("^.*/"; ""))) as $tail
  | (($tail | sub("^.*\\."; ""))) as $role
  | select($role == "refinery")
  | {id: .id,
     assignee: $a,
     rig: (if ($a | test("/")) then ($a | sub("/[^/]*$"; "")) else "" end),
     branch: ((($m.branch // "") | tostring)),
     flagged: ((($m.refinery_handoff_flagged // "") | tostring))}' 2>/dev/null)

repaired=0
reported=0
failed=0

# Report a bead we refuse to rewrite, ONCE per offending value. The marker records
# the address that provoked it, so the warning repeats only if the assignee changes
# to another wrong one rather than every cycle forever.
report_only() { # <id> <assignee> <already-flagged-value> <branch> <escalate 0|1> <reason>
  local id="$1" assignee="$2" flagged="$3" branch="$4" escalate="$5" reason="$6"
  reported=$((reported + 1))
  if [ "$flagged" = "$assignee" ]; then
    return 0
  fi
  echo "reconcile-refinery-handoffs: WARN $id is assigned '$assignee', which is not the canonical refinery identity '$REFINERY_ID' — $reason. The bead carries branch '${branch:-none}' and no merge_result, so no pass can see it: it is a merge handoff nobody will process until an operator resolves the address (tk-0nn3f)" >&2
  [ "$DRY_RUN" = 1 ] && return 0
  # A stderr line in a patrol log is the same weak signal this whole bug is made
  # of — the live case was found by a human noticing, not by a report. So the one
  # refusal that means WORK IS STRANDED AND THIS PASS CANNOT FIX IT also mails.
  # The benign refusals (a live holder, deliberate cross-rig routing, a roster
  # that did not read this cycle) do not: they are not incidents, and mailing them
  # would train the reader to ignore the ones that are. Bounded by the SAME marker
  # written just below, so a given bead escalates once per offending address, not
  # once per cycle.
  if [ "$escalate" = 1 ]; then
    gc mail send mayor/ -s "STRANDED HANDOFF: $id addressed to '$assignee'" -m "Bead $id is a completed merge handoff (branch ${branch:-none}) assigned to '$assignee'.
That address resolves to no session, so nobody polls it — and the bead carries no merge_result and no pr_url, so no bead-keyed reconcile pass can see it either. It will wait indefinitely.
It was NOT repaired: the canonical refinery identity this pass was given, '$REFINERY_ID', resolves to no session either, so rewriting would move the bead from one dead address to another and remove the last evidence.
Action needed: confirm the refinery's real identity, then reassign the bead to it. If '$REFINERY_ID' is wrong, the configured/rendered refinery address is the actual defect and every future handoff will strand the same way (tk-0nn3f)." >/dev/null 2>&1 || true
  fi
  gc bd update "$id" --set-metadata refinery_handoff_flagged="$assignee" >/dev/null 2>&1 || true
}

while IFS= read -r row; do
  [ -n "$row" ] || continue
  ID=$(printf '%s' "$row" | jq -r '.id // empty' 2>/dev/null)
  ASSIGNEE=$(printf '%s' "$row" | jq -r '.assignee // empty' 2>/dev/null)
  RIG=$(printf '%s' "$row" | jq -r '.rig // empty' 2>/dev/null)
  BRANCH=$(printf '%s' "$row" | jq -r '.branch // empty' 2>/dev/null)
  FLAGGED=$(printf '%s' "$row" | jq -r '.flagged // empty' 2>/dev/null)
  [ -n "$ID" ] && [ -n "$ASSIGNEE" ] || continue

  # Somebody really answers to this address. Then the near-miss is not the
  # suspect — the canonical string this pass was handed may be the wrong one, and
  # rewriting would take the bead off a live agent.
  if is_alive "$ASSIGNEE"; then
    report_only "$ID" "$ASSIGNEE" "$FLAGGED" "$BRANCH" 0 "a LIVE session answers to that address, so the bead is not stranded by a dead name (if the refinery's canonical identity is '$REFINERY_ID', that live session is the one to reconcile)"
    continue
  fi

  # Another rig's refinery. Cross-rig routing exists and can be deliberate; this
  # pass has no way to tell a typo from an intent, so it never guesses.
  if [ -n "$RIG" ] && [ "$RIG" != "$CANON_RIG" ]; then
    report_only "$ID" "$ASSIGNEE" "$FLAGGED" "$BRANCH" 0 "it names a DIFFERENT rig ('$RIG' vs '$CANON_RIG'), which can be deliberate cross-rig routing"
    continue
  fi

  # The roster could not be read (fail-safe above), or the canonical identity
  # itself resolves to nobody. Rewriting into a second dead address would remove
  # the only remaining evidence without delivering the work.
  if [ "$ROSTER_OK" != 1 ]; then
    report_only "$ID" "$ASSIGNEE" "$FLAGGED" "$BRANCH" 0 "the session roster could not be read this pass, so no address can be proved dead"
    continue
  fi
  if [ "$CANON_ALIVE" != 1 ]; then
    report_only "$ID" "$ASSIGNEE" "$FLAGGED" "$BRANCH" 1 "the canonical identity '$REFINERY_ID' resolves to NO session either, so the configured refinery address is itself unresolvable — rewriting would move the bead from one dead address to another and silence the last signal"
    continue
  fi

  # Repair. Nobody holds the address, the canonical one is real, and the bead is a
  # completed merge handoff no pass can see.
  if [ "$DRY_RUN" = 1 ]; then
    echo "reconcile-refinery-handoffs: DRY-RUN would reassign $ID '$ASSIGNEE' -> '$REFINERY_ID' (branch ${BRANCH:-none})"
    repaired=$((repaired + 1))
    continue
  fi

  # The assignee is its OWN call and lands first: it is the load-bearing half, and
  # batching it with the marker risks losing both to one rejection. The marker is
  # never part of the repair predicate either — a marker that stuck while the
  # assignee did not must NOT suppress the retry.
  gc bd update "$ID" --assignee="$REFINERY_ID" >/dev/null 2>&1 || true
  GOT=$(gc bd show "$ID" --json 2>/dev/null | tr -d '\000-\010\013\014\016-\037' \
    | jq -r '.[0].assignee // empty' 2>/dev/null)
  if [ "$GOT" != "$REFINERY_ID" ]; then
    failed=$((failed + 1))
    echo "reconcile-refinery-handoffs: WARN $ID reassign did NOT stick (read back '${GOT:-}', want '$REFINERY_ID'); the handoff is still stranded — retries next cycle" >&2
    continue
  fi
  repaired=$((repaired + 1))
  echo "reconcile-refinery-handoffs: REPAIRED $ID assignee '$ASSIGNEE' -> '$REFINERY_ID' (branch ${BRANCH:-none}); a completed merge handoff that no session would ever have polled (tk-0nn3f)"
  gc bd update "$ID" \
    --set-metadata refinery_address_repaired="$ASSIGNEE" \
    --append-notes "reconcile-refinery-handoffs: assignee was '$ASSIGNEE', a near-miss of the canonical refinery identity '$REFINERY_ID' that no session answered to. The bead carried branch '${BRANCH:-none}' and no merge_result, so it was invisible to the refinery's assignee filter AND to every bead-keyed pass. Reassigned to the canonical identity; work content, branch and metadata untouched (tk-0nn3f)." \
    >/dev/null 2>&1 || true
done <<< "$CANDIDATES"

# Prompt the refinery only when we are NOT it. Run from the refinery's own idle
# loop the nudge is pointless — its find-work re-check picks the bead up in this
# same cycle — and self-nudging an idle session is how a poll turns into a loop.
if [ "$repaired" -gt 0 ] && [ "$DRY_RUN" != 1 ] && [ "${GC_AGENT:-}" != "$REFINERY_ID" ]; then
  gc session nudge "$REFINERY_ID" "Merge handoff(s) recovered from a near-miss address; run 'gc prime' and check the queue." >/dev/null 2>&1 || true
fi

echo "reconcile-refinery-handoffs: $repaired repaired, $reported reported (not rewritten), $failed failed"
[ "$failed" -eq 0 ]
