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
# WHAT IT DOES. One visit, routed to the rig's converse pool, on a parked subject
# that nobody is talking to and that one of TWO observations applies to:
#
#   DISPOSITION DUE  an operator-origin park whose routed work has ALL landed
#                    (below: The four questions)
#   STRANDED HOLD    a `holding` takeaway with no live sitting behind it — the
#                    sitting was reaped mid-hold (below: The second observation)
#
# It writes exactly one metadata key per visit (that observation's dedup marker) and
# nothing else. It never closes anything, never clears the takeaway, and never
# touches the work.
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
# ── The second observation: a stranded hold (tk-jsyci7) ──────────────────────
#
# THE INTERACTION. The converse contract stamps `gc.takeaway` when a hold BEGINS —
# `gc-helm takeaway <item> "holding — <the one decision or input needed>"`,
# agents/converse/prompt.template.md step 5 — precisely so that a session reaped
# mid-hold still leaves a dated trace of what it was waiting for. That is correct and
# does not change here.
#
# But a non-empty takeaway is also what MUTES detect-stalled-workflows.sh. So the
# field written to survive the reap is the same field that hides it, and the tk-2cyxo
# un-mute cannot help: it keys on a RECORDED wait closing, and a sitting holding on
# the OPERATOR has no recorded wait at all — what it waits on is a human answer, not
# a bead. No edge, no child, nothing that can close. The mute is therefore permanent.
#
# MEASURED. tk-fhlv4, 2026-08-23: holding since 06:09:20Z, found by hand at 16:2xZ —
# 10h16m, no live visit, no assignee, its substantive finding unanswered. A second
# the same day (tk-hs2e8's sitting, reaped ~07:34Z) came back only when the pool
# re-offered its still-open visit at ~16:12Z: 8h38m, and by a slower path than
# anything purpose-built.
#
# WHY THE DISPOSITION ARM CANNOT REACH IT — the sharper half. tk-fhlv4 is not merely
# outside that arm, it is RETIRED from it: `disposition_flagged=tk-yhwfv.1,tk-yhwfv.2`
# was stamped when its routed work landed and a visit was filed for that. The sitting
# that took the visit then re-parked into a HOLD, which routes nothing, so no new
# landed set can ever form and the marker can never differ again. Every path to a
# push was closed. That is the shape this arm exists for.
#
# THE PREDICATE, and what each half refuses:
#
#   a `holding` takeaway   the one shape the contract writes, anchored and
#                          word-bounded. Tested ONCE, in the row query, so the shell
#                          and jq halves cannot drift into two definitions.
#
#   no live visit          the same is_held union as the disposition arm, plus
#                          `stall_root` — see below. This is what separates a
#                          stranded hold from a live one: a live sitting holds its
#                          visit, a reaped one does not.
#
#   nothing still in       a hold whose recorded wait is OPEN is not stranded, it is
#   flight                 WAITING, and the disposition arm fires for it when that
#                          wait lands. Without this half every ordinary mid-flight
#                          hold becomes a visit about work still in progress — the
#                          one thing the whole pass is written not to do.
#
# NO ORIGIN FILTER, deliberately, and unlike the disposition arm. That arm is narrow
# because an agent-origin PARK is not owed a push. A HOLD is different in kind: the
# contract's own rule is that "a hold with nothing for the operator to decide is not
# a hold", so the standing expectation of an answer comes from the hold itself, not
# from who filed the subject. A hold stamped on a workflow root by a stalled-workflow
# sitting is owed the same push as one on an operator's own question.
#
# WHY `stall_root` IS IN THE LIVE-VISIT UNION, and why it is load-bearing rather than
# thorough. The takeaway lands on the ITEM, never on the shared bucket (contract step
# 5), and for a stalled-workflow visit the item is the root named in that visit's
# `stall_root` while its `gc.continuation_group` is the shared triage subject. Match
# only the stamp and the tracks edge and such an item reads as having no visit while
# a session is mid-conversation about it. `gc-helm.sh open` does NOT close this gap:
# its own already-held guard reads the stamp and the edge only, so it would file the
# duplicate rather than refuse it. This guard is the only thing standing there.
#
# KEYED ON THE HOLD, not on a clock. `hold_flagged=<gc.takeaway_at>` records THE
# TAKEAWAY STAMP THAT WAS CURRENT WHEN THIS PASS LAST PUT THE SUBJECT IN FRONT OF
# CONVERSE. So the same hold is signalled exactly once, and a NEW hold — a re-park,
# which restamps `gc.takeaway_at` — earns exactly one more visit. Same discipline as
# `disposition_flagged`, for the same reason: this runs from a patrol, so anything
# keyed on a last-touch re-files forever, since stamping the marker is itself a
# write. An undated `holding` takeaway has no stable observation key, so it is
# reported and skipped rather than signalled off a key that cannot dedupe.
#
# WHICH IS WHY A DISPOSITION FILING STAMPS IT TOO. Both arms send the subject to the
# same place, so both have to record it. Left to the hold arm alone, the two arms
# amplify each other: the disposition arm files, a sitting takes the visit, concludes
# and closes it — WITHOUT clearing a takeaway that still begins "holding", which is
# the ordinary case, since the takeaway is the sitting's headline and not its state
# machine — and the next pass reads a hold with no live visit and files again, once
# per round, forever. Recording the stamp on every filing closes that: after either
# arm fires, only a genuine RE-PARK reopens the question. Not bundling — the same
# fact, written by whichever arm observed it.
#
# PRECEDENCE. The disposition arm is tried first. When both apply, the landed work is
# the more specific thing to say and its body is the better brief; the hold arm is
# the residue, which is exactly how it reaches a subject the disposition marker has
# already retired.
#
# ── What it never does ───────────────────────────────────────────────────────
#
# It never clears `gc.takeaway`. That stamp is the durable record of what the sitting
# concluded and the operator's own headline on the board; the visit is ADDITIVE. It
# writes one key per visit — `disposition_flagged` or `hold_flagged`, whichever
# observation fired — and only to a subject it has just filed a visit for.
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

# >>> control-char-scrub
# bd emits stray control characters inside a bead's title, description or notes,
# and a single one aborts the whole jq parse (tk-6kf6r) — the cost is a whole
# store, not one bead. Delete every C0 byte except LF. A sub-0x20 byte is invalid
# inside a JSON string, so a raw one is always corruption to drop and never
# payload: a TAB or CR that is genuine bead content arrives ESCAPED (\t, \r), two
# printable characters a byte filter cannot touch. TAB and CR are deleted with the
# rest rather than spared as JSON whitespace, because a single tab-indented note
# would otherwise abort the parse and blind a caller to an entire store — and
# nothing here splits on either, since rows are joined on US (0x1F), which this
# also deletes so no payload byte can pose as a separator. LF is spared alone: it
# is the one C0 byte bd actually emits, as pretty-print whitespace between tokens.
# ONE definition, copied verbatim into every host, the markers included —
# assets/scripts/control-char-scrub.test.sh fails on any copy that drifts.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

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

# How long a stamp has stood, as "10h16m". DISPLAY ONLY — never a key and never a
# gate, so the two date dialects are tried in turn and an unparsable stamp yields the
# EMPTY string rather than a wrong duration. Every caller omits the line when it is
# empty: "holding 10h16m" is the number that makes an operator act, and a fabricated
# one is worse than none.
held_for() {
  _t=""
  _t=$(date -u -d "${1:-}" +%s 2>/dev/null) || _t=""
  [ -n "$_t" ] || _t=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "${1:-}" +%s 2>/dev/null) || _t=""
  [ -n "$_t" ] || return 0
  _n=$(date -u +%s 2>/dev/null) || return 0
  _d=$((_n - _t))
  [ "$_d" -ge 0 ] || return 0
  printf '%dh%02dm' "$((_d / 3600))" "$(((_d % 3600) / 60))"
}

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

# Candidate rows, for BOTH observations:
#   id US takeaway US takeaway_at US takeaway_by US flagged US hold_flagged US origin
#      US is_hold US blocks-csv US title
#
# A row qualifies as operator-origin (the disposition arm) OR as a hold (the stranded
# -hold arm, which carries no origin filter — see the header). Non-empty is still the
# park test, not presence: an EMPTY stamp is a CLEARED park.
#
# `$hold` IS THE HOLD PREDICATE, and it is defined here and nowhere else. The loop
# reads the flag rather than re-testing the string, so the shell and jq halves cannot
# drift into two definitions of what a hold is. Anchored and word-bounded against the
# one shape the contract writes — `holding — <the one decision or input needed>` —
# so a takeaway that merely mentions holding something is not one; case-insensitive
# because the writer is a machine but the field is hand-editable.
ROWS=$(printf '%s' "$LIVE" | scrub | jq -r '
  .[]
  | ((.metadata // {})) as $m
  | ((($m["gc.takeaway"] // "") | tostring)) as $tk
  | select($tk != "")
  | ((($m["gc.origin"] // "") | tostring)) as $origin
  | ($tk | test("^holding\\b"; "i")) as $hold
  | select($origin == "operator" or $hold)
  | [ (.dependencies // [])[]
      | select((((.type // .dependency_type // "") | tostring)) == "blocks")
      | (((.depends_on_id // .id // "") | tostring)) | select(length > 0) ] as $blocks
  | [(.id // ""),
     ($tk | split("\n") | join(" ")),
     (($m["gc.takeaway_at"] // "") | tostring),
     (($m["gc.takeaway_by"] // "") | tostring),
     (($m.disposition_flagged // "") | tostring),
     (($m.hold_flagged // "") | tostring),
     $origin,
     (if $hold then "1" else "0" end),
     ($blocks | unique | join(",")),
     (((.title // "") | tostring) | split("\n") | join(" "))]
  | join("\u001f")' 2>/dev/null)

# Beads already under conversation, by ALL THREE recordings a visit makes of what it
# is about. The union, with the empty ones dropped — anything with no id would match
# those.
#
#   gc.continuation_group  the stamp the gate-visit block writes
#   tracks                 the edge it files alongside; the only one that has proved
#                          reliable on its own (su-ab9je, 2026-08-20: the stamp
#                          landed EMPTY while the edge carried the subject)
#   stall_root             the visit's ITEM, when that differs from its subject. The
#                          takeaway lands on the ITEM, never on the shared bucket
#                          (converse contract step 5), so a stalled-workflow sitting
#                          stamps the ROOT while its visit's continuation_group names
#                          the shared triage subject. Without this the hold arm reads
#                          such an item as having no visit and files a duplicate onto
#                          a live sitting — and `gc-helm.sh open` will NOT catch it,
#                          because its own guard reads the stamp and the edge only.
HELD_SUBJECTS=$(printf '%s' "$LIVE" | scrub | jq -r '
  .[] | select(((.metadata // {}).task_kind // "") == "visit")
  | (((.metadata // {})["gc.continuation_group"] // ""),
     (((.metadata // {}).stall_root // "") | tostring),
     ((.dependencies // [])[]? | select((((.type // .dependency_type // "") | tostring)) == "tracks") | ((.depends_on_id // .id // "") | tostring)))
  | select(. != "")' 2>/dev/null)
# A here-string, never `... | grep -qxF`: with pipefail on, `grep -q` exits at its
# first match and SIGPIPEs the writer, reporting 141 — a true answer read as false.
is_held() { [ -n "${1:-}" ] && grep -Fxq -- "$1" <<< "$HELD_SUBJECTS"; }

if [ -z "$ROWS" ]; then
  echo "$PROG: no parked operator-origin subjects, and nothing holding"
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

filed=0; holds=0; waiting=0; no_wait=0; already=0; hold_already=0; hold_undated=0
visit_open=0; unreadable=0; failed=0

while IFS="$SEP" read -r subj takeaway tk_at tk_by flagged hold_flagged origin is_hold blocks title; do
  [ -n "${subj:-}" ] || continue

  # (0) ALREADY UNDER CONVERSATION — asked FIRST, because it answers both
  # observations at once and reads nothing the pass has not already loaded. Hoisted
  # above the child listing so a live sitting costs no extra read, and so a hold
  # whose sitting is alive can never be classified as a stranded one. gc-helm.sh open
  # re-checks the subject half of this authoritatively.
  if is_held "$subj"; then
    visit_open=$((visit_open + 1)); continue
  fi

  if ! recorded_wait "$subj" "$(printf '%s' "$blocks" | tr ',' ' ')"; then
    echo "$PROG: $subj — $WAIT_WHY; skipped, so a visit is never filed on a read that did not happen" >&2
    unreadable=$((unreadable + 1)); continue
  fi

  LANDED_KEY=$(sorted_key "$WAIT_IDS")
  READY=0
  [ -n "$WAIT_IDS" ] && [ -z "$WAIT_OPEN" ] && READY=1

  # ── Which observation, if either ────────────────────────────────────────────
  # The disposition arm is tried first: when both apply, the landed work is the more
  # specific thing to say. The hold arm is the RESIDUE, which is how it reaches a
  # subject whose disposition marker already retired it (tk-fhlv4) — a hold routes
  # nothing, so no new landed set can ever form there and that marker can never
  # differ again.
  ACTION=""
  if [ "$origin" = "operator" ] && [ "$READY" = "1" ] && [ "$flagged" != "$LANDED_KEY" ]; then
    ACTION=dispose
  elif [ "$is_hold" = "1" ] && [ -z "$WAIT_OPEN" ] && [ -n "$tk_at" ] && [ "$hold_flagged" != "$tk_at" ]; then
    # `-z "$WAIT_OPEN"`: a hold whose recorded wait is still OPEN is not stranded, it
    # is waiting, and the disposition arm fires for it when that wait lands. Filing
    # here would invite the operator into a conversation about work still in flight.
    ACTION=hold
  fi

  # Exactly ONE bucket per candidate, in the same order the arms were tried, so the
  # census line says which test held it. The buckets can MASK each other — an empty
  # landed key equals an empty marker, so a dropped guard reclassifies rather than
  # firing — and the counts are the only place that shows it.
  if [ -z "$ACTION" ]; then
    if [ -n "$WAIT_OPEN" ]; then
      waiting=$((waiting + 1))
    elif [ "$origin" = "operator" ] && [ "$READY" = "1" ] && [ "$flagged" = "$LANDED_KEY" ]; then
      already=$((already + 1))
    elif [ "$is_hold" = "1" ] && [ -z "$tk_at" ]; then
      # No gc.takeaway_at means no stable observation key. `gc-helm takeaway` always
      # stamps one, so this is a hand-written field; report it rather than signal off
      # a key that cannot dedupe — an empty key equals an unset marker forever.
      echo "$PROG: $subj — a 'holding' takeaway with no gc.takeaway_at has no observation key to dedupe on; reported, not signalled" >&2
      hold_undated=$((hold_undated + 1))
    elif [ "$is_hold" = "1" ]; then
      hold_already=$((hold_already + 1))
    else
      # Nothing recorded as waited-on: the ordinary "we talked, here is the
      # conclusion" park. It is not waiting on anything, so there is nothing to come
      # back about.
      no_wait=$((no_wait + 1))
    fi
    continue
  fi

  # ── The observation, in the caller's words and the marker it retires on ─────
  HELD_SINCE=$(held_for "$tk_at")

  # The markers this filing retires, held in two SEPARATE variables rather than one
  # space-joined list. `gc.takeaway_at` is machine-written as an ISO instant, but the
  # field is hand-editable, and one written "2026-08-23 06:09:20" would word-split a
  # joined list into a TRUNCATED marker plus a garbage argument — after which the
  # stamped value never equals the takeaway again and the subject re-files every
  # pass. That is the amplifier tk-1g9yw, reached through a quoting bug.
  MARK2=""
  if [ "$ACTION" = "dispose" ]; then
    filed=$((filed + 1))
    MARKER="disposition_flagged=$LANDED_KEY"
    # Plus the hold marker, so closing this visit does not hand the same subject
    # straight to the hold arm — see the header. Skipped when the takeaway carries no
    # stamp, since there is then nothing to record.
    [ -n "$tk_at" ] && MARK2="hold_flagged=$tk_at"
    REASON="parked · routed work landed — dispose or resume"
    echo "$PROG: $subj DISPOSITION DUE — parked${tk_at:+ at $tk_at}${tk_by:+ by $tk_by}, routed work landed: $LANDED_KEY"
  else
    holds=$((holds + 1))
    MARKER="hold_flagged=$tk_at"
    REASON="stranded hold · the sitting that stamped it is gone"
    echo "$PROG: $subj STRANDED HOLD — holding since $tk_at${HELD_SINCE:+ ($HELD_SINCE)}${tk_by:+, stamped by $tk_by}, and no live visit names it"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    continue
  fi

  # The visit body IS the premise, written so converse's step-2 re-check can kill it
  # cheaply if the situation changed between filing and claiming: what was observed,
  # what it rests on, and when this was true. One body per observation — they rest on
  # DIFFERENT premises, so a single body would have to hedge about which is being
  # claimed, and a hedged premise is one no re-check can falsify.
  if [ "$ACTION" = "hold" ]; then
  BODY=$(printf '%s\n' \
    "Held subject: $subj — $title" \
    "" \
    "A converse sitting stamped this hold and is no longer here. The takeaway it" \
    "left${tk_at:+, at $tk_at}${tk_by:+, by $tk_by}${HELD_SINCE:+ — $HELD_SINCE ago}:" \
    "  \"$takeaway\"" \
    "" \
    "Nothing is talking to it (checked $NOW_ISO): no open visit names $subj by its" \
    "gc.continuation_group stamp, by a tracks edge, or as a stall_root item." \
    "" \
    "A hold waits on a HUMAN ANSWER, so it routes no work and records no wait — which" \
    "is why nothing brought it back on its own. Resume it: read the takeaway, rebuild" \
    "enough of the thread to state the decision it is waiting for, and put that to the" \
    "operator. What the sitting concluded is in this subject's notes." \
    "" \
    "PREMISE, re-checkable in two commands — if a sitting is in fact live on this," \
    "or the takeaway no longer names a hold, this visit is moot and costs one close:" \
    "  gc bd show $subj --json | jq -r '.[0].metadata.\"gc.takeaway\"'" \
    "  gc bd list --status=open,in_progress --json --limit=0 | jq '[.[]" \
    "    | select(.metadata.task_kind == \"visit\")" \
    "    | select(.metadata[\"gc.continuation_group\"] == \"$subj\"" \
    "             or .metadata.stall_root == \"$subj\")]'" \
    "" \
    "Why this arrived on its own: the stamp that records a hold is the same field that" \
    "MUTES the stall detector, and the un-mute keys on a recorded wait closing — which" \
    "a hold never has. So a sitting reaped mid-hold was invisible permanently, not" \
    "briefly. Measured on tk-fhlv4: 10h16m unattended, found by eye (2026-08-23)." \
    "" \
    "Dispositions:" \
    "  - resume   put the decision to the operator and hold again; re-stamp the" \
    "             takeaway so the new hold is dated — that is what earns the next" \
    "             visit if this one is reaped too" \
    "  - close    if the answer arrived elsewhere, or the question is moot, close the" \
    "             subject (docs/work-bead-state-machine.md)" \
    "  - re-park  if it is now waiting on WORK rather than an answer, say so as an" \
    "             edge, not as prose:" \
    "             gc-helm takeaway $subj \"<new headline>\" --waiting-on <bead-id>" \
    "" \
    "The takeaway above is untouched — it is the record of what the sitting was" \
    "waiting for, and this visit is additive." \
    "" \
    "Filed once per hold by assets/scripts/detect-parked-dispositions.sh (tk-jsyci7).")
  else
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
  fi

  # The filer's own diagnostic is kept, not discarded: it is the difference between
  # "the subject id does not resolve" and "the data plane is down", and this pass runs
  # unattended, so a swallowed reason is one nobody ever recovers.
  HELM_OUT=$("$HELM" open "$subj" \
        --reason "$REASON" \
        --body "$BODY" 2>&1)
  HELM_RC=$?
  if [ "$HELM_RC" -ne 0 ]; then
    echo "$PROG: $subj — gc-helm open refused to file the visit (exit $HELM_RC): $(printf '%s' "$HELM_OUT" | tr '\n' ' ' | cut -c1-300); NOT stamping the marker so the next pass retries the whole signal" >&2
    failed=$((failed + 1)); continue
  fi

  # VERIFIED, not assumed. `open` exits 0 both when it files and when it finds an
  # existing visit, and a create that reports success without persisting is exactly
  # the failure a marker would retire forever. Ask the store instead: is there now an
  # open visit naming this subject? Matched on the same three recordings the
  # already-held guard reads, so a filing cannot read back as missing on a shape that
  # guard would have counted.
  VNOW=$(bd_pinned list --status=open,in_progress --brief --limit=0 --json 2>/dev/null | scrub \
    | jq -r --arg s "$subj" '[ .[]? | select(((.metadata // {}).task_kind // "") == "visit")
        | select((((.metadata // {})["gc.continuation_group"] // "") == $s)
                 or ((((.metadata // {}).stall_root // "") | tostring) == $s)
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
  # One key per write, so a partial failure names the key that did not stick and the
  # other one still lands. Both expansions are QUOTED — see above.
  STAMP_FAILED=0
  for _mark in "$MARKER" "$MARK2"; do
    [ -n "$_mark" ] || continue
    bd_pinned update "$subj" --set-metadata "$_mark" >/dev/null 2>&1 && continue
    echo "$PROG: $subj — visit filed but the ${_mark%%=*} marker did not stick; harmless while the visit stays open (the guard dedupes), a duplicate only if it is closed before the next pass" >&2
    STAMP_FAILED=1
  done
  if [ "$STAMP_FAILED" -ne 0 ]; then
    failed=$((failed + 1)); continue
  fi
  echo "  -> visit filed on $subj, stamped $MARKER${MARK2:+ $MARK2}"
done <<< "$ROWS"

MODE=""
[ "$DRY_RUN" -eq 1 ] && MODE="(dry-run) "
echo "$PROG: ${MODE}${filed} disposition(s) and ${holds} stranded hold(s) signalled; $waiting still waiting, $no_wait with no recorded wait, $visit_open already under an open visit, $already already flagged, $hold_already hold(s) already signalled, $hold_undated undated hold(s), $unreadable unreadable, $failed failed"

# Only failed WRITES decide the exit code. An unreadable subject is a deliberate
# fail-closed skip, already reported on stderr, and correct.
[ "$failed" -eq 0 ] || exit 1
exit 0
