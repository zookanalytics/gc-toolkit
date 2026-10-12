#!/usr/bin/env bash
# patrol-finding.sh — one durable BEAD per distinct patrol finding.
# A patrol observes something wrong and files it here. The bead is deduped on
# a situation key, so a finding that recurs updates the bead it already has
# instead of filing a second one, and a proactive first reaction
# (formulas/mol-first-reaction.toml) reads it and picks the disposition: route
# it to a pool, hold it on an edge, or file the visit.
# A patrol that types its key by hand picks it afresh on every pass, so one
# situation can come back under a new key or a new subject, where the
# exact-match dedup cannot see it. A NEW bead that shares its key or its subject
# with a live finding in its scope is therefore refused, and those findings are
# listed for the caller to compare. --distinct files it anyway.
#   patrol-finding.sh --key <situation-key> --title <one line> --message <text>
#                     [--about <bead-id>] [--scope <slug>] [--type <t>]
#                     [--priority <n>] [--rig <rig>] [--distinct]
#                     [--no-react] [--dry-run]
# Callers: formulas/mol-deacon-patrol.toml, formulas/mol-witness-patrol.toml.
# The visit is not this path's exit. A finding needing the operator's judgment
# gets there through the reaction's `ruling` disposition, which files the visit
# inline (the gate-visit block in formulas/mol-first-reaction.toml). A patrol
# calls assets/scripts/escalate.sh directly only for an emergency it cannot
# express as a bead.
# Exit: 0 filed or already tracked · 1 could not file/verify · 2 usage ·
#       3 refused: a live finding in the scope shares the key or the subject
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
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

usage() {
  cat >&2 <<'U'
usage: patrol-finding.sh --key <situation-key> --title <one line>
                         --message <text> [options]

  --key       names the SITUATION, not the wording: one live bead per key,
              narrowed to --about when that is given. [A-Za-z0-9._-] only.
              Two findings that need separate work need separate keys, so
              encode what distinguishes them (`dolt-backup-<db>`). A doctor
              check's key is derived: use --check, not --key. `doctor-<check>`
              is reserved for that derivation (`doctor-sweep-failed`, a
              whole-sweep failure, is the one hand-typed doctor key)
  --check     a doctor check name — the sweep payload's `.name`, e.g.
              `gc-toolkit:check-step-terminal`. Derives the key `doctor-<check>`
              with the `<rig>:` prefix stripped, so every rendering of one
              check's name dedups to one bead. Mutually exclusive with --key;
              give exactly one
  --title     the board label for the bead; cut at a word boundary past 200
  --message   the finding, verbatim — it becomes the bead body, and it is
              what the first reaction reads
  --about     the bead this finding is ABOUT. Adds a `tracks` edge and
              narrows the dedup to that bead. A wisp (`*-wisp-*`) is dropped
              with a warning: its pass burns it, so the key alone is the
              identity
  --scope     which patrol filed it (deacon-findings, witness-findings);
              recorded as finding.scope
  --distinct  file a new bead although a live finding in this scope shares
              its key (about another bead) or its subject (under another
              key). Without it that filing is refused with exit 3 and the
              live findings are listed; when the report is one of their
              situations, re-run with that finding's --key and --about. A
              per-bead key, one finding per --about, passes it on every call
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

KEY=""; CHECK=""; TITLE=""; MESSAGE=""; ABOUT=""; SCOPE=""; TYPE="bug"
PRIORITY=""; RIG_ARG=""; DISTINCT=""; NO_REACT=""; DRY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key)      KEY="${2:-}";      shift 2 || { usage; exit 2; } ;;
    --check)    CHECK="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --title)    TITLE="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --message)  MESSAGE="${2:-}";  shift 2 || { usage; exit 2; } ;;
    --about)    ABOUT="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --scope)    SCOPE="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --type)     TYPE="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --priority) PRIORITY="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --rig)      RIG_ARG="${2:-}";  shift 2 || { usage; exit 2; } ;;
    --distinct) DISTINCT=1; shift ;;
    --no-react) NO_REACT=1; shift ;;
    -n|--dry-run) DRY=1; shift ;;
    -h|--help)  usage; exit 2 ;;
    *) warn "unknown argument '$1'"; usage; exit 2 ;;
  esac
done
# --check derives the key from a doctor check's name so the caller never hand-types
# it. The doctor JSON names a check `<rig>:<check>`; dedup is exact-match on the key,
# so a key that varies with how the `<rig>:` prefix is rendered splits one check
# across several beads. Stripping the prefix yields one key, `doctor-<check>`, for
# every rendering of the name.
if [ -n "$CHECK" ]; then
  if [ -n "$KEY" ]; then
    warn "--key and --check are mutually exclusive; --check derives the key"
    usage; exit 2
  fi
  KEY="doctor-${CHECK##*:}"
fi
if [ -z "$KEY" ] || [ -z "$TITLE" ] || [ -z "$MESSAGE" ]; then
  warn "--key (or --check) and --title and --message are all required"; usage; exit 2
fi
# A '=' or metacharacter in the key breaks the exact-match dedup read.
case "$KEY" in
  *[!A-Za-z0-9._-]*) warn "--key must contain only [A-Za-z0-9._-] (got '$KEY')"; exit 2 ;;
esac
# A wisp names no subject a later pass can match: its patrol burns it when the
# pass ends and the next pass pours another, so every pass would carry a new
# --about and file a new bead. The key alone is the identity there, as in
# escalate.sh's subject-class block, and no tracks edge is drawn to it.
case "$ABOUT" in
  *-wisp-*) warn "--about $ABOUT is a wisp, which its pass burns; filing on the key alone"; ABOUT="" ;;
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

# A doctor finding's key is DERIVED, not hand-typed: --check turns a check's
# name into the one canonical key doctor-<check>, the <rig>: prefix stripped
# (above). A hand-typed --key that renders the name any other way splits one
# check across beads — a '.' where the derivation writes a '-'
# (doctor.<check>), or the <rig> that --check strips left embedded
# (doctor-<rig>-<check>, doctor-<rig>.<check>). Refuse the renderings a
# derivation never emits and name --check; the guard reads $GC_RIG, so it must
# follow its resolution. doctor-sweep-failed is the one hand-typed doctor key:
# a whole-sweep failure names no check to derive from.
if [ -z "$CHECK" ]; then
  case "$KEY" in
    doctor-sweep-failed) : ;;
    doctor.* | doctor-"$GC_RIG"-* | doctor-"$GC_RIG".*)
      warn "'$KEY' is a hand-typed doctor key in a drifted rendering; a doctor check's key comes from --check <name> (yields doctor-<check>). doctor-sweep-failed is the only hand-typed doctor key."
      exit 2 ;;
  esac
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

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

# Every status a finding's bead can hold and still be its live record; only
# `closed` ends one. One comma list, because a repeated --status flag keeps only
# its last value.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# rows_by_key <status-list> -> the beads already holding this finding, as a
# JSON array in listing order, or `[]` when the store is readable and holds
# none. Returns NON-ZERO without printing when the lookup itself could not be
# trusted: the list command exited non-zero, or its output was not a JSON
# array. A caller must treat that as "unknown", never as "none" — an empty
# result read as "no existing finding" files the duplicate this script exists
# to prevent, during the very store-read failure it is meant to survive.
#
# The key rides the listing so the store does the narrowing, and --about rides
# it too when given: a truncated window filtered client-side would miss its
# own match and file a duplicate every pass. --limit=0 removes the window
# entirely, which the key filter can afford. Each row is then re-checked field
# by field, because a listing that silently ignored a filter would match
# everything, and because "no --about" means the finding.about key is ABSENT —
# a condition --metadata-field cannot express.
rows_by_key() {
  local statuses="$1" out
  # Capture the listing and its exit status BEFORE the parse: piping straight
  # into jq (as before) let a failed list emit an empty string that the parser
  # read as "no match", so the fail-open path and the no-match path were the
  # same. `|| return 2` splits them.
  # shellcheck disable=SC2086  # the --about filter expands to 0 or 2 fields
  out=$(bd_json list --status="$statuses" --metadata-field "finding.key=$KEY" \
      ${ABOUT:+--metadata-field "finding.about=$ABOUT"} --limit=0) \
    || return 2
  # A listing that is not a JSON array — an error object, a truncated payload,
  # the empty string — cannot be read as "no match". Fail closed.
  printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$out" \
    | jq -c --arg k "$KEY" --arg a "$ABOUT" --arg st "$statuses" \
        '($st | split(",")) as $want
         | [ .[] | select(((.metadata["finding.key"] // "") == $k)
                      and ((.metadata["finding.about"] // "") == $a)
                      and ((.status // "") as $s | $want | any(. == $s))) ]' 2>/dev/null \
    || return 2
}

# find_by_key <status-list> -> the id of the first bead rows_by_key lists, or
# empty when it lists none. Non-zero exactly when rows_by_key is.
find_by_key() {
  local rows
  rows=$(rows_by_key "$1") || return 2
  printf '%s' "$rows" | jq -r '.[0].id // empty' 2>/dev/null || return 2
}

# siblings -> the live findings in this scope that share the key about another
# subject (or none), or the subject under another key, as a JSON array with
# the oldest unheld bead first, or `[]` when there are none. NON-ZERO without
# printing when the listing cannot be trusted, the same contract as
# rows_by_key: a failed read is not "no sibling".
siblings() {
  local out
  out=$(bd_json list --status="$LIVE_STATUSES" --metadata-field "finding.scope=$SCOPE_LABEL" --limit=0) \
    || return 2
  printf '%s' "$out" | jq -e 'type == "array"' >/dev/null 2>&1 || return 2
  printf '%s' "$out" \
    | jq -c --arg k "$KEY" --arg a "$ABOUT" --arg sc "$SCOPE_LABEL" --arg st "$LIVE_STATUSES" \
        '($st | split(",")) as $want
         | [ .[] | select(((.metadata["finding.scope"] // "") == $sc)
                      and ((.status // "") as $s | $want | any(. == $s)))
                 | ((.metadata["finding.key"] // "") | tostring) as $fk
                 | ((.metadata["finding.about"] // "") | tostring) as $fa
                 | select($fk != "")
                 | select(($fk == $k and $fa != $a) or ($a != "" and $fa == $a and $fk != $k)) ]
         | sort_by([(.status == "blocked"), (.created_at // "")])' 2>/dev/null \
    || return 2
}

# waits_on_open <blocker-id>... -> 0 while one of the blockers is still open, 1
# once every one of them reads closed, and 1 when there are none. A blocker
# counts as closed only when a read shows it closed. One whose read fails, or
# that no store answers for, is still waited on, because reading it as closed
# would file a second bead on the strength of a failed read. `gc bd show`
# resolves an id by its prefix in whichever rig's store holds it, so a blocker
# filed in another rig is read where it lives.
waits_on_open() {
  local b
  for b in "$@"; do
    [ "$(bd_json show "$b" | jq -r '.[0].status // empty' 2>/dev/null)" = "closed" ] || return 0
  done
  return 1
}

SCOPE_LABEL="${SCOPE:-unscoped}"
DEDUP_SCOPE="[$KEY]${ABOUT:+ on $ABOUT}"

if [ -n "$DRY" ]; then
  printf 'key=%s scope=%s rig=%s type=%s%s%s\n' \
    "$KEY" "$SCOPE_LABEL" "${GC_RIG:-}" "$TYPE" "${ABOUT:+ about=$ABOUT}" "${DISTINCT:+ distinct}"
  printf 'title=%s\n' "$TITLE"
  printf 'would file (or update) one bead for %s\n' "$DEDUP_SCOPE"
  exit 0
fi

# ── The finding already has a bead ───────────────────────────────────
# Its recurrence belongs on that bead. This is the whole point: the live bead
# spans the recurrence, where an open VISIT did not — a sitting closes each
# visit before the next sweep runs, so the dedup window never covered the gap
# and one situation filed a visit per tick.
#
# Every live status is read, not just open and in_progress: a bead parked at
# blocked, deferred, hooked or pinned is still the finding's bead, and a lookup
# blind to it files a second bead beside it. A bead held at blocked keeps the
# recurrence only while something it waits on is still open. `bd ready` skips a
# blocked bead whatever its edges say, and the status stays set after its
# blockers close. So once nothing it waits on is open, no pool is offered that
# bead again, and a recurrence recorded on it starts no reaction. That
# recurrence is news, filed below. Otherwise the recurrence goes to a live
# bead: first one not held at blocked, then a held one still waiting on an open
# blocker.
if ! LIVE=$(rows_by_key "$LIVE_STATUSES"); then
  warn "dedup lookup failed (list exited non-zero, or its output was not a JSON array) for $DEDUP_SCOPE — refusing to file, so a transient store-read failure cannot create a duplicate of a bead that may already be live. Re-run when the store is readable."
  exit 1
fi
EXISTING=$(printf '%s' "$LIVE" | jq -r '[.[] | select(.status != "blocked")][0].id // empty' 2>/dev/null)
HELD=""; HELD_ON=""
if [ -z "$EXISTING" ]; then
  # `bd list` carries each bead's outgoing edges on its row, keyed `.type` with
  # the target in `.depends_on_id`; `bd show` keys them `.dependency_type` and
  # `.id`, and leaves out an edge into another store. Both spellings are read.
  # Only a `blocks` edge is a wait: the `tracks` edge --about adds names the
  # bead the finding is about.
  if ! HELD_ROWS=$(printf '%s' "$LIVE" | jq -r '.[] | select(.status == "blocked")
      | [ .id, ([ (.dependencies // [])[]
                  | select(((.type // .dependency_type // "") | tostring) == "blocks")
                  | ((.depends_on_id // .id // "") | tostring)
                  | select(. != "") ] | unique | join(" ")) ] | @tsv'); then
    warn "could not read the blockers of the blocked bead holding $DEDUP_SCOPE — refusing to file, because a bead that may still be waiting would get a second one beside it. Re-run when the store is readable."
    exit 1
  fi
  while IFS=$'\t' read -r id on; do
    [ -n "$id" ] || continue
    # shellcheck disable=SC2086  # $on is space-separated bead ids, one field each
    if waits_on_open $on; then EXISTING="$id"; break; fi
    [ -n "$HELD" ] || { HELD="$id"; HELD_ON="$on"; }
  done <<< "$HELD_ROWS"
fi
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

# ── A live finding already reports this situation under another name ──
# The exact match above sees a repeat only when the caller typed the same key
# and subject again. A patrol that types its key afresh each pass can report
# one situation under a new key with the same subject, or under the same key
# with another subject, and each such filing would be a twin with its own first
# reaction. So a new bead that shares either half with a live finding in this
# scope is refused, and those findings are listed. A caller whose situation is
# one of them re-runs with its --key and --about, and the report becomes an
# occurrence there. --distinct says the caller compared and it is not, or that
# the key is per-bead by design.
if [ -z "$DISTINCT" ]; then
  if ! SIBLINGS=$(siblings); then
    warn "sibling lookup failed (list exited non-zero, or its output was not a JSON array) for $DEDUP_SCOPE — refusing to file, so a transient store-read failure cannot let a twin of a live finding through. Re-run when the store is readable."
    exit 1
  fi
  if [ "$(printf '%s' "$SIBLINGS" | jq 'length' 2>/dev/null)" != "0" ]; then
    warn "refusing to file a new bead for $DEDUP_SCOPE: live findings in the $SCOPE_LABEL scope already share its key or its subject:"
    printf '%s' "$SIBLINGS" | jq -r '.[]
      | "  \(.id) [\(.status // "?")] --key \(.metadata["finding.key"] // "")"
        + (if (.metadata["finding.about"] // "") != "" then " --about \(.metadata["finding.about"])" else "" end)
        + " — \(.title // "")"' >&2
    warn "If this is one of those situations, re-run with its --key and --about, and the report lands on it as an occurrence. If it is a different situation, re-run with --distinct."
    exit 3
  fi
fi

# ── Recurring after its bead let go is news, and gets its own bead ────
# A finding whose bead was closed as fixed, firing again, means the fix did
# not hold. A bead held at blocked with nothing open left to wait on is the
# same news before anyone has closed it, and it is the predecessor to name,
# not an older closed bead. That is worth one new bead — and only one: the next
# recurrence finds THIS bead open above.
PRIOR="$HELD"
if [ -z "$PRIOR" ] && ! PRIOR=$(find_by_key "closed"); then
  warn "dedup lookup failed (list exited non-zero, or its output was not a JSON array) for the closed-bead probe of $DEDUP_SCOPE — refusing to file, so a transient store-read failure cannot create a duplicate. Re-run when the store is readable."
  exit 1
fi

BODY="$MESSAGE

## Filing
Filed by the $SCOPE_LABEL patrol under finding key \`$KEY\`. A recurrence
updates \`finding.occurrences\` and \`finding.last_seen\` on this bead rather
than filing another, and appends a note when the finding text changes."
if [ -n "$HELD" ] && [ -n "$HELD_ON" ]; then
  BODY="$BODY

This finding fired again while $HELD was held at blocked and everything it
waited on (${HELD_ON// /, }) had closed, so what those beads delivered did not
stop it. Read that bead before re-deriving the cause."
elif [ -n "$HELD" ]; then
  BODY="$BODY

This finding fired again while $HELD was held at blocked with no blocker to
wait on, so nothing in the graph will release it to take the recurrence. Read
that bead before re-deriving the cause."
elif [ -n "$PRIOR" ]; then
  BODY="$BODY

This finding fired again after $PRIOR was closed, so the earlier fix did not
hold. Read that bead before re-deriving the cause."
fi

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
BEAD=$(gc bd create "$@" --json 2>/dev/null | scrub | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)

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

if [ -n "$HELD" ]; then
  echo "$PROG: filed $BEAD for $DEDUP_SCOPE (recurrence of $HELD, held at blocked with nothing open to wait on)"
else
  echo "$PROG: filed $BEAD for $DEDUP_SCOPE${PRIOR:+ (recurrence of closed $PRIOR)}"
fi

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
