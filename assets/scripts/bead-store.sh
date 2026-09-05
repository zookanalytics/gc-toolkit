#!/usr/bin/env bash
# bead-store.sh — resolve a bead id to the store that owns it, and answer
# whether that store holds it.
#
# A bead id names its store in its prefix and nowhere else. A bare `gc bd show`
# resolves a live id from whichever store holds it, but it cannot prove an
# absence: a miss is answered by the store the caller happens to sit in, not
# the one the prefix names, so a bead absent from ANOTHER store returns the
# same "no issues found matching the provided IDs" as one that exists nowhere.
# A gate that reads that miss as permission — prune this worktree, salvage
# nothing, delete this source — then destroys on a confident answer about the
# wrong subject.
#
# Absence is therefore a claim to be earned: resolve the prefix to a rig
# through `gc rig list --json`, ask THAT rig's store by path, and report
# absent only when it answers. `gc bd --db <path>/.beads` is the form that
# pins a store, and the only one that reaches the HQ store, which no `--rig`
# value names.
#
# The owning store answers a bare id as an exact-or-prefix match, so its answer
# is a verdict only about THIS id when the id is exact. A hit whose id is longer
# is a partial match on some other bead. A miss object is byte-identical whether
# nothing matched or several did, and only the exact not-found — which the store
# states on stderr — earns `absent`; ambiguity and any other lookup error are
# unproven. A reference that resolves to one other bead, or to many, is never a
# verdict.
#
# Every verdict fails closed, and the exit code says which kind of answer it
# is: 1 is a proven no, 3 is no answer at all. `--absent` exits 0 only when a
# store answered and does not hold the bead, so
# `bead-store.sh --absent "$id" && rm -rf "$dir"` cannot destroy on an
# unknown prefix, a prefix two rigs carry, an unreadable rig list, or an
# unreadable store. `--present` is the same guard at the opposite polarity
# rather than the negation of `--absent`: both refuse an unproven store.
#
# Usage:
#   bead-store.sh <bead-id>            the rig whose store owns the id
#   bead-store.sh --path <bead-id>     that rig's repo path
#   bead-store.sh --db <bead-id>       that rig's bead store, <path>/.beads
#   bead-store.sh --absent <bead-id>   proven absent from its own store
#   bead-store.sh --present <bead-id>  proven present in its own store
#
# Resolution modes print the answer on stdout. Verdict modes print nothing on
# stdout and state their reasoning on stderr, so a caller reads the exit code.
#
# Exit: 0 resolved, or the verdict holds
#       1 proven otherwise — the opposite state was read from the owning
#         store, or, in a resolution mode, no rig carries the prefix
#       2 usage
#       3 unproven — no store could be reached to ask, or the store answered
#         about a different or an ambiguous id rather than this exact one. A
#         verdict mode ends here for every unresolved prefix as well: an id no
#         rig claims is a store nobody asked, not a bead nobody has.
# Callers: escalation-rig.sh, bead-rehome.sh, and any gate whose next act is
# destructive. Test: bead-store.test.sh.
set -uo pipefail

PROG="bead-store"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: bead-store.sh [--path|--db|--absent|--present] <bead-id>

Resolves <bead-id>'s owning store from its id prefix through `gc rig list`,
and asks that store — not the caller's ambient one — whether it holds the
bead. Every unresolved shape exits non-zero, so a destructive gate written as
`bead-store.sh --absent "$id" && <destroy>` refuses the cases it cannot prove.
U
  exit 2
}

MODE=rig
case "${1:-}" in
  --path)    MODE=path;    shift ;;
  --db)      MODE=db;      shift ;;
  --absent)  MODE=absent;  shift ;;
  --present) MODE=present; shift ;;
  -*)        usage ;;
esac

BEAD="${1:-}"
[ "$#" -eq 1 ] && [ -n "$BEAD" ] || usage

# A bounded call: an unreachable Dolt server hangs, and a gate that hangs is a
# gate that never refuses.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 15 "$@"; else "$@"; fi
}

# An id whose store cannot be named answers a resolution mode with a plain no,
# and answers a verdict mode with nothing at all: a prefix no rig claims leaves
# the bead unasked-about, which is exactly the reading that turns a foreign id
# into permission to destroy.
case "$MODE" in
  absent|present) UNPLACED=3 ;;
  *)              UNPLACED=1 ;;
esac

PREFIX="${BEAD%%-*}"
[ -n "$PREFIX" ] && [ "$PREFIX" != "$BEAD" ] || {
  echo "$PROG: '$BEAD' has no '<prefix>-' segment to resolve a store from" >&2
  exit "$UNPLACED"
}

RIGS=$(bounded gc rig list --json 2>/dev/null | scrub)
# Empty means UNREADABLE as often as it means "no such prefix", and the two
# have different repairs, so they are reported apart.
if [ -z "$RIGS" ]; then
  echo "$PROG: could not read \`gc rig list --json\` — the store for $BEAD is unproven, so nothing may be concluded about it" >&2
  exit 3
fi

# A payload that is not a rig list at all would leave every prefix unmatched
# and read as "no rig carries it", which is a fact about the rigs rather than
# about the answer. Establish that it IS one before drawing anything from it.
printf '%s' "$RIGS" | jq -e '(.rigs | type) == "array"' >/dev/null 2>&1 || {
  echo "$PROG: \`gc rig list --json\` did not answer with a rig list — the store for $BEAD is unproven, so nothing may be concluded about it" >&2
  exit 3
}

ROWS=$(printf '%s' "$RIGS" | jq -r --arg p "$PREFIX" \
  '.rigs[]? | select(.prefix == $p) | [.name, (.path // "")] | @tsv' 2>/dev/null)
COUNT=$(printf '%s' "$ROWS" | grep -c . || true)

if [ "$COUNT" = "0" ]; then
  echo "$PROG: no rig carries the prefix '$PREFIX' (from $BEAD); \`gc rig list\` has $(printf '%s' "$RIGS" | jq -r '[.rigs[]?.prefix] | join(", ")' 2>/dev/null)" >&2
  exit "$UNPLACED"
fi
if [ "$COUNT" != "1" ]; then
  echo "$PROG: prefix '$PREFIX' (from $BEAD) is carried by $COUNT rigs ($(printf '%s' "$ROWS" | cut -f1 | tr '\n' ' ')) — name the store explicitly" >&2
  exit 3
fi

RIG_NAME=$(printf '%s' "$ROWS" | cut -f1)
RIG_PATH=$(printf '%s' "$ROWS" | cut -f2)

case "$MODE" in
  rig) printf '%s\n' "$RIG_NAME"; exit 0 ;;
esac

# Every mode below is the rig's path. A rig that reports none is a rig whose
# store cannot be addressed, which is unproven rather than absent.
[ -n "$RIG_PATH" ] || {
  echo "$PROG: rig '$RIG_NAME' carries prefix '$PREFIX' but reports no path, so its store cannot be asked about $BEAD" >&2
  exit 3
}
DB="$RIG_PATH/.beads"

case "$MODE" in
  path) printf '%s\n' "$RIG_PATH"; exit 0 ;;
  db)   printf '%s\n' "$DB"; exit 0 ;;
esac

ERR_FILE=$(mktemp)
PAYLOAD=$(bounded gc bd --db "$DB" show "$BEAD" --json 2>"$ERR_FILE" | scrub)
STORE_ERR=$(scrub <"$ERR_FILE"); rm -f "$ERR_FILE"

# The payload and the store's own stderr decide, never the exit code: a store
# that cannot be opened exits the same 1 as a genuine miss and prints nothing at
# all. bd resolves a bare id as an exact-or-prefix match, so neither a hit nor a
# miss is a verdict about THIS id on its own:
#   - a hit proves presence only when it carries the exact id; an array whose
#     ids are all longer is a prefix match on some other bead, and this id's own
#     state is unproven.
#   - the miss object is byte-identical for a genuine not-found and an ambiguous
#     reference. Only the exact not-found, which the store states on stderr,
#     earns absence; ambiguity and any other lookup error are unproven.
UNPROVEN_MSG="$RIG_NAME ($DB) gave no readable answer about $BEAD — no verdict"
if printf '%s' "$PAYLOAD" | jq -e --arg b "$BEAD" 'type == "array" and any(.[]; (.id? // "") == $b)' >/dev/null 2>&1; then
  STATE=present
elif printf '%s' "$PAYLOAD" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
  STATE=unproven
  MATCHED=$(printf '%s' "$PAYLOAD" | jq -r '[.[].id] | join(", ")' 2>/dev/null)
  UNPROVEN_MSG="$BEAD is present in $RIG_NAME ($DB) only as a prefix of $MATCHED, a different bead, so its own state is unproven"
elif printf '%s' "$PAYLOAD" | jq -e 'type == "object" and (.error | type) == "string"' >/dev/null 2>&1; then
  if grep -qiE 'ambiguous' <<<"$STORE_ERR"; then
    STATE=unproven
    UNPROVEN_MSG="$BEAD is an ambiguous reference in $RIG_NAME ($DB); it matches several ids, so it is unproven, never absent"
  elif grep -qiF 'not found' <<<"$STORE_ERR"; then
    STATE=absent
  else
    STATE=unproven
    UNPROVEN_MSG="$RIG_NAME ($DB) answered about $BEAD with an error that is not a plain not-found, so its absence is unproven"
  fi
else
  STATE=unproven
fi

case "$MODE:$STATE" in
  absent:absent)
    echo "$PROG: $BEAD is absent from $RIG_NAME ($DB), the store its prefix names" >&2; exit 0 ;;
  absent:present)
    echo "$PROG: $BEAD EXISTS in $RIG_NAME ($DB) — it is not absent, whatever another store answers" >&2; exit 1 ;;
  present:present)
    echo "$PROG: $BEAD is present in $RIG_NAME ($DB)" >&2; exit 0 ;;
  present:absent)
    echo "$PROG: $BEAD is absent from $RIG_NAME ($DB), the store its prefix names" >&2; exit 1 ;;
  *)
    echo "$PROG: $UNPROVEN_MSG" >&2; exit 3 ;;
esac
