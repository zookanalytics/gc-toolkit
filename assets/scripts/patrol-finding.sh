#!/usr/bin/env bash
# patrol-finding.sh — one durable BEAD per distinct patrol finding.
# A patrol observes something wrong and files it here. The bead is deduped on
# a situation key, so a finding that recurs updates the bead it already has
# instead of filing a second one, and a proactive first reaction
# (formulas/mol-first-reaction.toml) reads it and picks the disposition: route
# it to a pool, hold it on an edge, or file the visit.
#   patrol-finding.sh --key <situation-key> --title <one line> --message <text>
#                     [--about <bead-id>] [--scope <slug>] [--type <t>]
#                     [--priority <n>] [--rig <rig>] [--no-react] [--dry-run]
# Callers: formulas/mol-deacon-patrol.toml, formulas/mol-witness-patrol.toml.
# The visit is not this path's exit. A finding needing the operator's judgment
# gets there through the reaction's `ruling` disposition, which files the visit
# inline (the gate-visit block in formulas/mol-first-reaction.toml). A patrol
# calls assets/scripts/escalate.sh directly only for an emergency it cannot
# express as a bead.
# Exit: 0 filed or already tracked · 1 could not file/verify · 2 usage
set -uo pipefail

PROG="patrol-finding"
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PROACTIVE="${GC_PROACTIVE_TOOL:-$HERE/../../tools/gc-proactive.sh}"

# The rig whose store a finding lands in when the caller names none. The
# deacon is city-scoped, so GC_RIG arrives unset there and an unpinned
# `gc bd` would read whichever store the cwd walks up to.
DEFAULT_RIG="${GC_FINDING_DEFAULT_RIG:-gc-toolkit}"

# `bd create` refuses a title over 500 bytes, and a finding line can run long.
TITLE_MAX=200

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

usage() {
  cat >&2 <<'U'
usage: patrol-finding.sh --key <situation-key> --title <one line>
                         --message <text> [options]

  --key       names the SITUATION, not the wording: one open bead per key,
              narrowed to --about when that is given. [A-Za-z0-9._-] only.
              Two findings that need separate work need separate keys, so
              encode what distinguishes them (`doctor-<check>`,
              `dolt-backup-<db>`)
  --title     the board label for the bead; cut at a word boundary past 200
  --message   the finding, verbatim — it becomes the bead body, and it is
              what the first reaction reads
  --about     the bead this finding is ABOUT. Adds a `tracks` edge and
              narrows the dedup to that bead, so one key over two beads is
              two findings
  --scope     which patrol filed it (deacon-findings, witness-findings);
              recorded as finding.scope
  --type      bead type (default: bug)
  --priority  bead priority; the proactive scan spends its slots by board
              weight, so a finding that matters should say so
  --rig       the rig whose store this lands in (default: $GC_RIG, else
              gc-toolkit). It also rig-qualifies the proactive pool
  --no-react  file the bead and stop. It keeps gc.proactive=1, so the next
              `gc-proactive.sh scan --sling` sweep reacts to it
  --dry-run   print what would be filed and exit
U
}

KEY=""; TITLE=""; MESSAGE=""; ABOUT=""; SCOPE=""; TYPE="bug"
PRIORITY=""; RIG_ARG=""; NO_REACT=""; DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key)      KEY="${2:-}";      shift 2 || { usage; exit 2; } ;;
    --title)    TITLE="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --message)  MESSAGE="${2:-}";  shift 2 || { usage; exit 2; } ;;
    --about)    ABOUT="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --scope)    SCOPE="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --type)     TYPE="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --priority) PRIORITY="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --rig)      RIG_ARG="${2:-}";  shift 2 || { usage; exit 2; } ;;
    --no-react) NO_REACT=1; shift ;;
    -n|--dry-run) DRY=1; shift ;;
    -h|--help)  usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
if [ -z "$KEY" ] || [ -z "$TITLE" ] || [ -z "$MESSAGE" ]; then
  warn "--key, --title and --message are all required"; usage; exit 2
fi
# A '=' or metacharacter in the key breaks the exact-match dedup read.
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac

# GC_RIG selects the store `gc bd` reads and writes, and gc-proactive.sh
# rig-qualifies its pool target from it. Both have to name the same rig, so
# one value sets both.
if [ -n "$RIG_ARG" ]; then
  export GC_RIG="$RIG_ARG"
elif [ -z "${GC_RIG:-}" ]; then
  export GC_RIG="$DEFAULT_RIG"
  warn "GC_RIG unset; filing in the '$DEFAULT_RIG' store (--rig names another)"
fi

# derive_title <text> — one-line board label; an over-long title is cut at a
# WORD boundary, because an offset cut can slice a multi-byte character.
derive_title() {
  local t
  t=$(printf '%s' "$1" | tr '\n\r\t' '   ' | tr -s ' ')
  t="${t# }"; t="${t% }"
  if [ "${#t}" -gt "$TITLE_MAX" ]; then
    t="${t:0:$TITLE_MAX}"
    case "$t" in *" "*) t="${t% *}" ;; esac
    t="$t…"
  fi
  printf '%s' "$t"
}
TITLE=$(derive_title "$TITLE")

# The finding's text fingerprint. A recurrence whose text is unchanged is a
# tick; one whose text moved is news, and only news is worth a note.
digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | cut -c1-12
  else
    printf '%s' "$1" | cksum | tr -d ' ' | cut -c1-12
  fi
}
DIGEST=$(digest_of "$MESSAGE")

bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }

# find_by_key <status-list> -> the id of the bead already holding this
# finding, or empty.
#
# The key rides the listing so the store does the narrowing, and --about rides
# it too when given: a truncated window filtered client-side would miss its
# own match and file a duplicate every pass. --limit=0 removes the window
# entirely, which the key filter can afford. The matched row is then re-checked
# field by field, because a listing that silently ignored a filter would match
# everything, and because "no --about" means the finding.about key is ABSENT —
# a condition --metadata-field cannot express.
find_by_key() {
  local statuses="$1"
  # shellcheck disable=SC2086  # the --about filter expands to 0 or 2 fields
  bd_json list --status="$statuses" --metadata-field "finding.key=$KEY" \
      ${ABOUT:+--metadata-field "finding.about=$ABOUT"} --limit=0 \
    | jq -r --arg k "$KEY" --arg a "$ABOUT" \
        'if type == "array"
         then (.[] | select(((.metadata["finding.key"] // "") == $k)
                        and ((.metadata["finding.about"] // "") == $a)) | .id)
         else empty end' 2>/dev/null \
    | head -n 1
}

SCOPE_LABEL="${SCOPE:-unscoped}"
DEDUP_SCOPE="[$KEY]${ABOUT:+ on $ABOUT}"

if [ -n "$DRY" ]; then
  printf 'key=%s scope=%s rig=%s type=%s%s\n' \
    "$KEY" "$SCOPE_LABEL" "${GC_RIG:-}" "$TYPE" "${ABOUT:+ about=$ABOUT}"
  printf 'title=%s\n' "$TITLE"
  printf 'would file (or update) one bead for %s\n' "$DEDUP_SCOPE"
  exit 0
fi

# ── The finding already has a bead ───────────────────────────────────
# Its recurrence belongs on that bead. This is the whole point: the open bead
# spans the recurrence, where an open VISIT did not — a sitting closes each
# visit before the next sweep runs, so the dedup window never covered the gap
# and one situation filed a visit per tick.
EXISTING=$(find_by_key "open,in_progress")
if [ -n "$EXISTING" ]; then
  ROW=$(bd_json show "$EXISTING")
  SEEN=$(printf '%s' "$ROW" | jq -r '.[0].metadata["finding.occurrences"] // "1"' 2>/dev/null)
  case "$SEEN" in ''|*[!0-9]*) SEEN=1 ;; esac
  SEEN=$(( SEEN + 1 ))
  WAS=$(printf '%s' "$ROW" | jq -r '.[0].metadata["finding.digest"] // ""' 2>/dev/null)

  set -- --set-metadata "finding.occurrences=$SEEN" \
         --set-metadata "finding.last_seen=$(now_utc)"
  if [ "$WAS" != "$DIGEST" ]; then
    # --append-notes, never --notes: --notes REPLACES, and the body a patrol
    # would erase is the one the first reaction read.
    set -- "$@" --set-metadata "finding.digest=$DIGEST" \
           --append-notes "[$(now_utc)] $SCOPE_LABEL: finding recurred with changed text (occurrence $SEEN):
$MESSAGE"
  fi
  if gc bd update "$EXISTING" "$@" >/dev/null 2>&1; then
    if [ "$WAS" != "$DIGEST" ]; then
      echo "$PROG: $EXISTING already tracks $DEDUP_SCOPE — recorded occurrence $SEEN and the changed text"
    else
      echo "$PROG: $EXISTING already tracks $DEDUP_SCOPE — recorded occurrence $SEEN, text unchanged"
    fi
    exit 0
  fi
  warn "could not record the recurrence on $EXISTING; the finding is still tracked there"
  exit 1
fi

# ── Recurring after a close is news, and gets its own bead ────────────
# A finding whose bead was closed as fixed, firing again, means the fix did
# not hold. That is worth one new bead — and only one: the next recurrence
# finds THIS bead open above.
PRIOR=$(find_by_key "closed")

BODY="$MESSAGE

## Filing
Filed by the $SCOPE_LABEL patrol under finding key \`$KEY\`. A recurrence
updates \`finding.occurrences\` and \`finding.last_seen\` on this bead rather
than filing another, and appends a note when the finding text changes."
[ -n "$PRIOR" ] && BODY="$BODY

This finding fired again after $PRIOR was closed, so the earlier fix did not
hold. Read that bead before re-deriving the cause."

# Every stamp rides the create. A bead whose finding.key landed in a second
# write that failed is a bead the next sweep cannot find, and it files again —
# and when `bd create --json` returns an empty id for a bead it did create,
# the key is the only thing that can identify it below.
META=$(jq -nc \
  --arg k "$KEY" --arg s "$SCOPE_LABEL" --arg d "$DIGEST" \
  --arg t "$(now_utc)" --arg a "$ABOUT" --arg p "$PRIOR" \
  '{"finding.key": $k, "finding.scope": $s, "finding.digest": $d,
    "finding.first_seen": $t, "finding.last_seen": $t,
    "finding.occurrences": "1", "gc.proactive": "1"}
   + (if $a == "" then {} else {"finding.about": $a} end)
   + (if $p == "" then {} else {"finding.recurrence_of": $p} end)' 2>/dev/null)
[ -n "$META" ] || { warn "could not build the metadata payload (jq); nothing filed"; exit 1; }

set -- -t "$TYPE" --title "$TITLE" -d "$BODY" --metadata "$META"
[ -n "$PRIORITY" ] && set -- "$@" --priority "$PRIORITY"
BEAD=$(gc bd create "$@" --json 2>/dev/null | scrub | jq -r '.id // .[0].id // ""' 2>/dev/null)

# `bd create --json` can answer with an empty id for a bead it did create, and
# a blind retry would file the duplicate this script exists to prevent. The key
# rode the create, so the bead can be found instead of re-created.
if [ -z "$BEAD" ] || [ "$BEAD" = "null" ]; then
  BEAD=$(find_by_key "open,in_progress")
  [ -n "$BEAD" ] && warn "bd create returned no id but the bead exists as $BEAD (found by finding.key)"
fi
if [ -z "$BEAD" ]; then
  warn "bd create filed nothing for $DEDUP_SCOPE — re-run this command rather than improvising another create form"
  exit 1
fi

# tracks, NOT parent-child: a parent-child edge transmits the subject's
# blocked state to the finding, which would hold the very bead the reaction
# needs to be able to route. Advisory — the finding stands without the edge.
if [ -n "$ABOUT" ]; then
  gc bd dep add "$BEAD" "$ABOUT" --type=tracks >/dev/null 2>&1 \
    || warn "could not add the tracks edge $BEAD -> $ABOUT; the finding.about stamp still names it"
fi

# The key is what makes the dedup real: unstamped, this bead is invisible to
# every later sweep and the next one files another. Read it back.
GOT_KEY=$(bd_json show "$BEAD" | jq -r '.[0].metadata["finding.key"] // ""' 2>/dev/null)
if [ "$GOT_KEY" != "$KEY" ]; then
  warn "finding.key on $BEAD read back as '$GOT_KEY', expected '$KEY' — every later sweep will file a duplicate. Repair: gc bd update $BEAD --set-metadata finding.key=$KEY"
  exit 1
fi

echo "$PROG: filed $BEAD for $DEDUP_SCOPE${PRIOR:+ (recurrence of closed $PRIOR)}"

# ── Hand it to the first reaction ────────────────────────────────────
# The reaction is what disposes the finding: routed to a pool, held on an
# edge, or escalated to the operator as a visit. A sling that cannot land is
# not a failure of the filing — gc.proactive=1 is the standing opt-in the
# next `gc-proactive.sh scan --sling` sweep reads, so the bead is reacted to
# either way, just later.
[ -n "$NO_REACT" ] && exit 0
if [ ! -x "$PROACTIVE" ]; then
  warn "cannot find gc-proactive.sh (looked at $PROACTIVE); $BEAD carries gc.proactive=1 and waits for the next scan sweep"
  exit 0
fi
if ! "$PROACTIVE" deliverable >/dev/null 2>&1; then
  warn "the proactive pool cannot pick a reaction up right now; $BEAD carries gc.proactive=1 and waits for the next scan sweep"
  exit 0
fi
"$PROACTIVE" sling "$BEAD" \
  || warn "the first-reaction sling on $BEAD failed; it carries gc.proactive=1 and waits for the next scan sweep"
exit 0
