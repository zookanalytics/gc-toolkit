#!/usr/bin/env bash
# detect-parked-dispositions — bring a parked conversation BACK when the work it
# routed has landed (tk-2cyxo).
#
# THE GAP THIS FILLS. A `gc.takeaway` stamp does three unrelated jobs at once, and
# two of them conspire:
#
#   1. it parks the board row — `gather_meta_anchors` in gc-helm.sh emits
#      kind:"parked", floored at LOW, because a conversation that reached a
#      takeaway wants nothing and only has to stay FINDABLE;
#   2. it MUTES the stall detector — detect-stalled-workflows.sh treats a takeaway
#      on a root or its anchor as a named wait a human owns.
#
# So the one automation in the city that files visits is silenced by the exact stamp
# that records the wait. A subject that dispatched work could never be brought back
# BY the system — only by the operator noticing a row.
#
# MEASURED COST, the incident that produced this pass. tk-z9nln (operator ask,
# 2026-08-22 03:42Z) parked at 05:25Z with the takeaway "next sitting when findings
# land". The findings landed 17:54Z (tk-z9nln.1, PR #408). At 22:13Z — 4h19m later —
# the operator found it by eye. Nothing in the system had noticed. The audit's
# headline (it overturned its own commissioning premise) sat in a merged file, untold.
#
# tk-2plde (PR #411) made the wait a real `blocks` edge that the board re-asks on
# every render, so a parked row whose blockers closed can now turn ELEVATED. That is
# the necessary half and it is not sufficient: ELEVATED is passive, and it still
# waits for someone to look at a board. This pass is the push.
#
# WHAT IT DOES. One visit, routed to the rig's converse pool, on a parked
# operator-origin subject whose routed work has ALL landed. It writes exactly one
# metadata key (the dedup marker) and nothing else. It never closes anything, never
# clears the takeaway, and never touches the work.
#
# ── The four questions, and why each is asked this way ───────────────────────
#
# (1) IS IT PARKED? `gc.takeaway` non-empty. Non-empty is the test, not presence: an
#     EMPTY stamp is a CLEARED park, the same absent-vs-empty tri-state
#     mol-liveness-sweep and detect-stalled-workflows.sh read.
#
# (2) IS IT OPERATOR-ORIGIN? `gc.origin=operator`. Ruled deliberately narrow
#     (operator, 2026-08-22): that is the set where the operator has a standing
#     expectation of an answer. An agent-origin subject that parks itself is not
#     owed a push.
#
#     The key is READ here and WRITTEN by gc-visit-open.sh, the operator-origin
#     intake front door. Before it existed, origin lived as prose in the subject's
#     description ("Operator-origin intake, filed by `gc-visit-open` on …") and the
#     obvious shortcut was to grep for that line. This pass deliberately does not:
#     the prose already has THREE shapes in this rig alone (two script generations
#     and one an agent typed by hand), and a `--desc-contains` sweep for it matches
#     three beads that merely QUOTE the sentence — including the bead that filed
#     this pass. A predicate that drifts silently and false-positives on discussion
#     of itself is not a predicate. `assets/scripts/backfill-operator-origin.sh`
#     stamps the key onto the beads written before it existed; that script owns the
#     regex, once, where a wrong match is visible and re-runnable.
#
# (3) HAS THE ROUTED WORK LANDED? The recorded wait is the union of two edges, and
#     it has to be both:
#
#       blocks   the subject depends-on ids `gc-helm takeaway --waiting-on` writes.
#                This is the shape the BOARD reads (`waiting_on` →
#                `disposition_due`).
#       children the beads whose parent-child edge names this subject.
#
#     The children half is not an embellishment — it is the CANONICAL converse
#     shape, and without it this pass could not fire for the subject it was
#     measured on. A sitting that routes work files it as a child of the subject
#     and slings that; and a parent CANNOT be blocked by its own descendant:
#
#         $ gc bd dep add tk-z9nln tk-wvrga -t blocks
#         Error: tk-z9nln cannot be blocked by its descendant tk-wvrga:
#         blocked status cascades to descendants, so tk-wvrga would inherit
#         the block and never close
#
#     (reproduced live 2026-08-22T22:58Z). The guard is right and stays. The
#     consequence is that the default converse shape produces ZERO `waiting_on`
#     edges, so a readiness test keyed on "waiting_on fully closed" — which is what
#     the board's `disposition_due` is — can never be true for it. Measured the same
#     day: of 21 open roots carrying a takeaway, 3 had open children; the two live
#     operator-origin subjects with a recorded wait of ANY kind were split one to
#     each edge type.
#
#     A parent-child row on the SUBJECT means the subject is somebody's child and is
#     never read as routed work — the edge lives on the child, so children are found
#     by asking for them (`bd list --parent`), never by reading the subject's own
#     dependency list.
#
#     READY = at least one recorded wait EXISTS and every one of them is CLOSED.
#     Both halves are load-bearing. Without "at least one", every parked
#     conversation that routed nothing — the ordinary "we talked, here is the
#     conclusion" park — reads as ready forever and gets a visit it has no use for.
#
# (4) IS THE CONVERSATION ALREADY LIVE? An open visit naming this subject means the
#     conversation exists; a second would split it. Checked here for the count, and
#     again inside `gc-helm.sh open`, which owns the authoritative guard.
#
# ── Why this delegates the filing rather than copying the block ──────────────
#
# The visit is filed by `gc-helm.sh open`, exactly as gc-visit-open.sh does it.
# Visit filing lives in ONE place — that verb's marked `# >>> gate-visit` block,
# which assets/scripts/gate-visit.test.sh checks on the same terms as the formula
# copies — and calling it inherits four things this pass would otherwise re-derive:
# the canonical metadata shape, the subject-exists gate, the one-open-visit-per-
# subject gate (which matches BOTH recordings of a visit's subject, the
# gc.continuation_group stamp and the tracks edge — on su-ab9je the stamp landed
# empty while the edge carried it), and the board cache bust, without which the row
# the operator is looking at keeps saying nobody is talking about this.
#
# A copied block would satisfy the letter of "file via the canonical block" and lose
# three of those four.
#
# ── One visit per observation, not one per pass ──────────────────────────────
#
# Same two-guard shape detect-stalled-workflows.sh landed on after the amplifier
# (tk-1g9yw), for the same reason: this runs from a patrol, so a per-pass signal is
# a per-minute signal.
#
#   visit-already-open  the PRIMARY bound. A visit may sit open indefinitely — the
#                       operator gets to it — so this guard, not a timer, is what
#                       bounds the converse fleet.
#   disposition_flagged the BACKSTOP, for after that visit is closed. Keyed to the
#                       OBSERVATION: the sorted id set of the work that landed.
#                       NEVER to a timestamp — stamping the marker is a `bd update`,
#                       every update bumps `updated_at`, so a last-touch key
#                       invalidates itself and re-files forever. A subject that gets
#                       a second round of work routed and landed has a DIFFERENT set
#                       and earns exactly one more visit.
#
# There is deliberately NO staleness window. The trigger is an EDGE — the moment the
# last piece of routed work closed — not a duration, and readiness is all-or-nothing
# (one open child holds the whole subject), so a half-finished dispatch cannot fire
# it early. A wait for a settling period would only delay the push the ruling asked
# for.
#
# ── What it never does ───────────────────────────────────────────────────────
#
# It never clears `gc.takeaway`. That stamp is the durable record of what the sitting
# concluded and the operator's own headline on the board; the visit is ADDITIVE. It
# writes one key, `disposition_flagged`, and only to a subject it has just filed a
# visit for.
#
# ── --wait-spent, the shared predicate ───────────────────────────────────────
#
#   detect-parked-dispositions.sh --wait-spent <bead-id>
#
# Exit 0 iff that bead's recorded wait exists and has fully closed — i.e. its
# takeaway names a wait that has ENDED. detect-stalled-workflows.sh asks this
# before letting a takeaway mute a stall, so the two passes cannot drift into
# disagreeing about what a spent park is. Fail-closed: anything unreadable, and
# anything with no recorded wait at all, exits non-zero (= not spent = keep muting).
#
# NOT set -e: best-effort, must never abort the patrol mid-pass. FAIL-SAFE
# DIRECTION throughout — a fact that cannot be established FILES NOTHING rather than
# guessing, because every input here, misread, turns a live wait into a visit and a
# converse session for work that is still in flight.
set -uo pipefail

PROG="detect-parked-dispositions"
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
HELM="${GC_HELM_TOOL:-$SCRIPT_DIR/gc-helm.sh}"

DRY_RUN=0
RIG_PIN=""
WAIT_SPENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --rig) RIG_PIN="${2:-}"; shift 2 ;;
    --helm) HELM="${2:-}"; shift 2 ;;
    --wait-spent) WAIT_SPENT="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

bd_pinned() { # <bd-subcommand> [args...]
  if [ -n "$RIG_PIN" ]; then
    gc bd --rig "$RIG_PIN" "$@"
  else
    gc bd "$@"
  fi
}

# Control characters in a bead's notes break jq (tk-6kf6r); strip the range that
# cannot appear in valid JSON string content, sparing TAB/LF/CR.
scrub() { tr -d '\000-\010\013\014\016-\037'; }

# FIELDS ARE JOINED ON US (0x1f), NEVER ON A TAB. Tab is IFS *whitespace*:
# consecutive tabs collapse into one delimiter, so an empty interior field shifts
# every later field left by one — and most fields here (`gc.origin`,
# `disposition_flagged`, the waiting set) are empty on most beads, so with @tsv a
# subject's TITLE lands in the origin field and reads as operator-origin. That
# misread is SILENT and it manufactures work. `scrub` strips 0x1f before jq runs, so
# no bead value can smuggle one in.
SEP=$(printf '\037')

# ── The recorded wait ────────────────────────────────────────────────────────
# Sets WAIT_IDS (space-separated, the union) and WAIT_OPEN (space-separated, the
# ones not proved closed) for one bead. Returns 1 when a read failed, so the caller
# can fail closed rather than treat an unreadable store as "nothing is waiting".
#
# $1 = bead id, $2 = its own `blocks` depends-on ids (space-separated, may be empty)
WAIT_IDS=""; WAIT_OPEN=""; WAIT_WHY=""
recorded_wait() {
  _bead="${1:-}"; _blocks="${2:-}"
  WAIT_IDS=""; WAIT_OPEN=""; WAIT_WHY=""
  [ -n "$_bead" ] || { WAIT_WHY="no bead id"; return 1; }

  # CHILDREN. `bd list --parent` is the only way to ask: a parent-child edge is
  # stored on the CHILD, so a parent has no readable child list of its own. `--all`
  # because a closed child is the whole point — it is the landed work — and `--brief`
  # because nothing here reads a description.
  _kids=$(bd_pinned list --parent "$_bead" --all --brief --json --limit=0 2>/dev/null)
  if [ -z "$_kids" ] || ! printf '%s' "$_kids" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
    WAIT_WHY="the child listing for $_bead was unreadable"
    return 1
  fi
  _kid_open=$(printf '%s' "$_kids" | scrub | jq -r '.[] | select(((.status // "") | ascii_downcase) != "closed") | .id // empty' 2>/dev/null)
  _kid_all=$(printf '%s' "$_kids" | scrub | jq -r '.[] | .id // empty' 2>/dev/null)

  # BLOCKERS. One batched read for every id at once. `bd show` answers with an ARRAY
  # when any id resolves and a bare OBJECT when none do, rc=0 either way, so the
  # shape is tested rather than assumed.
  _blk_open=""
  if [ -n "$_blocks" ]; then
    # shellcheck disable=SC2086  # a deliberate list of bare ids
    _raw=$(bd_pinned show $_blocks --json 2>/dev/null | scrub)
    _map=$(printf '%s' "$_raw" | jq -c 'if type == "array"
        then [ .[]? | select(type == "object") | {key: ((.id // "") | tostring), value: ((.status // "") | ascii_downcase)} | select(.key != "") ] | from_entries
        else {} end' 2>/dev/null)
    [ -n "$_map" ] || _map='{}'
    # An id the map cannot answer for reads as STILL OPEN. Wrong in the quiet
    # direction on purpose, exactly as the board's waitmap is: a missed push costs a
    # glance, a false "the work landed" invites the operator into a conversation
    # about work that is still in flight.
    for _b in $_blocks; do
      _st=$(printf '%s' "$_map" | jq -r --arg i "$_b" '.[$i] // ""' 2>/dev/null)
      [ "$_st" = "closed" ] || _blk_open="${_blk_open:+$_blk_open }$_b"
    done
  fi

  WAIT_IDS=$(printf '%s %s' "$(printf '%s' "$_kid_all" | tr '\n' ' ')" "$_blocks" | tr -s ' ' | sed 's/^ //; s/ $//')
  WAIT_OPEN=$(printf '%s %s' "$(printf '%s' "$_kid_open" | tr '\n' ' ')" "$_blk_open" | tr -s ' ' | sed 's/^ //; s/ $//')
  return 0
}

# Sorted, comma-joined — the dedup key and the report order, independent of the
# order any listing happened to return.
sorted_key() { printf '%s' "${1:-}" | tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort -u | tr '\n' ',' | sed 's/,$//'; }

# ── Query mode: is this bead's named wait spent? ─────────────────────────────
# The shared predicate, exposed so detect-stalled-workflows.sh can ask it instead of
# growing a second copy that drifts.
if [ -n "$WAIT_SPENT" ]; then
  BLOCKS=$(bd_pinned show "$WAIT_SPENT" --json 2>/dev/null | scrub \
    | jq -r 'if type == "array" then (.[0].dependencies // [])[]?
             | select(((.dependency_type // .type // "") | tostring) == "blocks")
             | ((.id // .depends_on_id // "") | tostring) | select(length > 0)
             else empty end' 2>/dev/null | tr '\n' ' ')
  if ! recorded_wait "$WAIT_SPENT" "$BLOCKS"; then
    echo "$PROG: --wait-spent $WAIT_SPENT: NOT spent — $WAIT_WHY (fail-closed)"
    exit 1
  fi
  if [ -z "$WAIT_IDS" ]; then
    echo "$PROG: --wait-spent $WAIT_SPENT: NOT spent — no recorded wait (no children, no blocks edges)"
    exit 1
  fi
  if [ -n "$WAIT_OPEN" ]; then
    echo "$PROG: --wait-spent $WAIT_SPENT: NOT spent — still open: $(sorted_key "$WAIT_OPEN")"
    exit 1
  fi
  echo "$PROG: --wait-spent $WAIT_SPENT: SPENT — all landed: $(sorted_key "$WAIT_IDS")"
  exit 0
fi

# ── The pass ─────────────────────────────────────────────────────────────────
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# One listing answers both the candidate set and the visit-already-open guard.
# `--brief` drops the free-form text and keeps metadata, dependencies and title —
# verified against the running bd — so a rig's whole open set costs one small read.
LIVE=$(bd_pinned list --status=open,in_progress --brief --limit=0 --json 2>/dev/null)
if [ -z "$LIVE" ] || ! printf '%s' "$LIVE" | scrub | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "$PROG: FAIL-SAFE the open listing did not return a readable array; filing NOTHING this pass — a subject can only be called ready against a listing that was actually read. Retries next cycle" >&2
  exit 0
fi

# Candidate rows: id US takeaway US takeaway_at US takeaway_by US flagged US blocks-csv US title
ROWS=$(printf '%s' "$LIVE" | scrub | jq -r '
  .[]
  | ((.metadata // {})) as $m
  | select((($m["gc.takeaway"] // "") | tostring) != "")
  | select((($m["gc.origin"] // "") | tostring) == "operator")
  | [ (.dependencies // [])[]
      | select((((.type // .dependency_type // "") | tostring)) == "blocks")
      | (((.depends_on_id // .id // "") | tostring)) | select(length > 0) ] as $blocks
  | [(.id // ""),
     ((($m["gc.takeaway"] // "") | tostring) | split("\n") | join(" ")),
     (($m["gc.takeaway_at"] // "") | tostring),
     (($m["gc.takeaway_by"] // "") | tostring),
     (($m.disposition_flagged // "") | tostring),
     ($blocks | unique | join(",")),
     (((.title // "") | tostring) | split("\n") | join(" "))]
  | join("\u001f")' 2>/dev/null)

# Subjects already under conversation. A visit records its subject TWICE — the
# gc.continuation_group stamp and the tracks edge — and only the edge has proved
# reliable (su-ab9je, 2026-08-20: the stamp landed EMPTY while the edge carried it),
# so take the union and drop the empty stamp, which anything with no id would match.
HELD_SUBJECTS=$(printf '%s' "$LIVE" | scrub | jq -r '
  .[] | select(((.metadata // {}).task_kind // "") == "visit")
  | (((.metadata // {})["gc.continuation_group"] // ""),
     ((.dependencies // [])[]? | select((((.type // .dependency_type // "") | tostring)) == "tracks") | ((.depends_on_id // .id // "") | tostring)))
  | select(. != "")' 2>/dev/null)
# A here-string, never `... | grep -qxF`: with pipefail on, `grep -q` exits at its
# first match and SIGPIPEs the writer, reporting 141 — a true answer read as false.
is_held() { [ -n "${1:-}" ] && grep -Fxq -- "$1" <<< "$HELD_SUBJECTS"; }

if [ -z "$ROWS" ]; then
  echo "$PROG: no parked operator-origin subjects"
  exit 0
fi

# Visit filing lives in gc-helm.sh, so without it this pass can decide but not act.
# It degrades to REPORT-ONLY rather than exiting: the selection is the useful half of
# the answer, and a per-subject "could not file" for every candidate every cycle would
# bury the one line that says why.
if [ "$DRY_RUN" -eq 0 ] && [ ! -x "$HELM" ]; then
  echo "$PROG: FAIL-SAFE cannot find gc-helm.sh (looked at $HELM) — visit filing lives there, so this pass reports its selection and files NOTHING. Retries next cycle" >&2
  DRY_RUN=1
fi

filed=0; waiting=0; no_wait=0; already=0; visit_open=0; unreadable=0; failed=0

while IFS="$SEP" read -r subj takeaway tk_at tk_by flagged blocks title; do
  [ -n "${subj:-}" ] || continue

  if ! recorded_wait "$subj" "$(printf '%s' "$blocks" | tr ',' ' ')"; then
    echo "$PROG: $subj — $WAIT_WHY; skipped, so a visit is never filed on a read that did not happen" >&2
    unreadable=$((unreadable + 1)); continue
  fi

  # It routed nothing this pass can see. The ordinary "we talked, here is the
  # conclusion" park — it is not waiting on anything, so there is nothing to come
  # back about.
  if [ -z "$WAIT_IDS" ]; then
    no_wait=$((no_wait + 1)); continue
  fi
  if [ -n "$WAIT_OPEN" ]; then
    waiting=$((waiting + 1)); continue
  fi

  LANDED_KEY=$(sorted_key "$WAIT_IDS")

  # Already under conversation: the primary bound. Counted here so the summary line
  # says why nothing was filed; gc-helm.sh open re-checks it authoritatively.
  if is_held "$subj"; then
    visit_open=$((visit_open + 1)); continue
  fi

  # Same observation already signalled — the backstop for after that visit closed.
  if [ "$flagged" = "$LANDED_KEY" ]; then
    already=$((already + 1)); continue
  fi

  filed=$((filed + 1))
  echo "$PROG: $subj DISPOSITION DUE — parked${tk_at:+ at $tk_at}${tk_by:+ by $tk_by}, routed work landed: $LANDED_KEY"

  if [ "$DRY_RUN" -eq 1 ]; then
    continue
  fi

  # The visit body IS the premise, written so converse's step-2 re-check can kill it
  # cheaply if the situation changed between filing and claiming: what was parked,
  # what has since closed, and when this was true.
  BODY=$(printf '%s\n' \
    "Parked subject: $subj — $title" \
    "" \
    "It was parked${tk_at:+ at $tk_at}${tk_by:+ by $tk_by} with this takeaway:" \
    "  \"$takeaway\"" \
    "" \
    "Every piece of work it routed has since landed (checked $NOW_ISO):" \
    "  $LANDED_KEY" \
    "" \
    "Nothing else is recorded as waited-on: no open child, no open blocks edge." \
    "" \
    "PREMISE, re-checkable in one command — if any of the ids above is open again," \
    "or the takeaway now names a NEW wait, this visit is moot and costs one close:" \
    "  gc bd show $subj --json | jq -r '.[0].metadata.\"gc.takeaway\"'" \
    "  gc bd list --parent $subj --all --brief --json --limit=0" \
    "" \
    "Why this arrived on its own: a takeaway parks the board row AND mutes the stall" \
    "detector, so before this pass a subject whose routed work finished had nothing" \
    "that could bring it back — the incident this exists to prevent sat 4h19m before" \
    "the operator found it by eye (tk-z9nln, 2026-08-22)." \
    "" \
    "Dispositions:" \
    "  - resume   hold the sitting the work was routed out of; the landed work is" \
    "             what the conversation reacts to" \
    "  - close    if the work IS the answer, close the subject with a successor" \
    "             pointer to it (docs/work-bead-state-machine.md)" \
    "  - re-park  if it waits on something new, say so as an edge, not as prose:" \
    "             gc-helm takeaway $subj \"<new headline>\" --waiting-on <bead-id>" \
    "" \
    "The takeaway above is untouched — it is the record of what the sitting" \
    "concluded, and this visit is additive." \
    "" \
    "Filed once per observation by assets/scripts/detect-parked-dispositions.sh (tk-2cyxo).")

  # The filer's own diagnostic is kept, not discarded: it is the difference between
  # "the subject id does not resolve" and "the data plane is down", and this pass runs
  # unattended, so a swallowed reason is one nobody ever recovers.
  HELM_OUT=$("$HELM" open "$subj" \
        --reason "parked · routed work landed — dispose or resume" \
        --body "$BODY" 2>&1)
  HELM_RC=$?
  if [ "$HELM_RC" -ne 0 ]; then
    echo "$PROG: $subj — gc-helm open refused to file the visit (exit $HELM_RC): $(printf '%s' "$HELM_OUT" | tr '\n' ' ' | cut -c1-300); NOT stamping the marker so the next pass retries the whole signal" >&2
    failed=$((failed + 1)); continue
  fi

  # VERIFIED, not assumed. `open` exits 0 both when it files and when it finds an
  # existing visit, and a create that reports success without persisting is exactly
  # the failure a marker would retire forever. Ask the store instead: is there now an
  # open visit naming this subject?
  VNOW=$(bd_pinned list --status=open,in_progress --brief --limit=0 --json 2>/dev/null | scrub \
    | jq -r --arg s "$subj" '[ .[]? | select(((.metadata // {}).task_kind // "") == "visit")
        | select((((.metadata // {})["gc.continuation_group"] // "") == $s)
                 or ([ (.dependencies // [])[]? | select((((.type // .dependency_type // "") | tostring)) == "tracks")
                       | select((((.depends_on_id // .id // "") | tostring)) == $s) ] | length > 0)) ] | length' 2>/dev/null)
  [ -n "$VNOW" ] || VNOW=0
  if [ "$VNOW" -lt 1 ]; then
    echo "$PROG: $subj — gc-helm open exited 0 but no open visit names this subject; NOT stamping the marker so the next pass re-signals" >&2
    failed=$((failed + 1)); continue
  fi

  # The marker is stamped LAST, and only over a visit that read back. In that order a
  # failed filing leaves the subject unflagged and the next pass retries; the reverse
  # would retire the disposition on a conversation nobody ever had. If this stamp
  # itself fails, the visit is open, so next pass the visit-already-open guard covers
  # it — the marker only matters after that visit is closed.
  if ! bd_pinned update "$subj" --set-metadata "disposition_flagged=$LANDED_KEY" >/dev/null 2>&1; then
    echo "$PROG: $subj — visit filed but the disposition_flagged marker did not stick; harmless while the visit stays open (the guard dedupes), a duplicate only if it is closed before the next pass" >&2
    failed=$((failed + 1)); continue
  fi
  echo "  -> visit filed on $subj, stamped disposition_flagged=$LANDED_KEY"
done <<< "$ROWS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "$PROG: ${MODE}${filed} disposition(s) signalled; $waiting still waiting, $no_wait with no recorded wait, $visit_open already under an open visit, $already already flagged, $unreadable unreadable, $failed failed"

# Only failed WRITES decide the exit code. An unreadable subject is a deliberate
# fail-closed skip, already reported on stderr, and correct.
[ "$failed" -eq 0 ] || exit 1
exit 0
