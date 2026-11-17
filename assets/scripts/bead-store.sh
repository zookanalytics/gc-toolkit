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
# pins a store, and the one form that reaches every store, the HQ store
# included, which no `--rig` value names.
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
#
# Sourced, the file defines bead_store_map and bead_store_rig below and runs no
# part of the command, so a script that places several ids reads the rig map
# once and places each one by this derivation.
#
# Callers: bead-rehome.sh (sourced), converse-signoff.sh and converse-rework.sh
# (resolution modes), and any gate whose next act is destructive. Test:
# bead-store.test.sh.

# bead_store_map — the rig map, as rig-map.sh prints it, in BEAD_STORE_MAP. The
# first call in a shell reads it, and leaves it empty when it does not read,
# with rig-map.sh's reason on stderr. Every later call in that shell reuses it.
# A map in the environment is not one it read, so loading this file clears it.
# rig-map.sh sits beside this file, in BEAD_STORE_DIR, which is read as the file
# loads: zsh leaves BASH_SOURCE unset and names the file it sources in $0.
unset BEAD_STORE_MAP
BEAD_STORE_DIR="${BASH_SOURCE[0]:-$0}"
case "$BEAD_STORE_DIR" in
  */*) BEAD_STORE_DIR="${BEAD_STORE_DIR%/*}"; BEAD_STORE_DIR="${BEAD_STORE_DIR:-/}" ;;
  *)   BEAD_STORE_DIR=. ;;
esac
case "$BEAD_STORE_DIR" in /*) ;; *) BEAD_STORE_DIR="$PWD/$BEAD_STORE_DIR" ;; esac
bead_store_map() {
  [ -z "${BEAD_STORE_MAP+set}" ] || return 0
  BEAD_STORE_MAP=$("$BEAD_STORE_DIR/rig-map.sh") || BEAD_STORE_MAP=""
  return 0
}

# bead_store_rig <bead-id> — the rig whose store owns <bead-id>, read off
# bead_store_map's map: it sets BEAD_STORE_RIG to the rig's name and
# BEAD_STORE_PATH to its path, which is empty when the rig reports none, and
# returns 0. Otherwise it names on stderr why, and returns 1 when the id is not
# a '<prefix>-<id>' pair or no rig carries its prefix, and 3 when the map did
# not read or two rigs carry the prefix.
bead_store_rig() {
  local bead="$1" prefix suffix rows row count=0 names=""
  BEAD_STORE_RIG=""; BEAD_STORE_PATH=""
  # A resolvable id is `<prefix>-<id>` with text on both sides of the first dash.
  # A bare `<prefix>-` names a store but no bead. Its prefix resolves to a rig,
  # so probing it reads that store's generic not-found as this id's own absence.
  # That is the fail-open this guard refuses, so require a non-empty id, not
  # just a non-empty prefix.
  prefix="${bead%%-*}"
  suffix="${bead#*-}"
  [ -n "$prefix" ] && [ "$prefix" != "$bead" ] && [ -n "$suffix" ] || {
    echo "bead-store: '$bead' is not a '<prefix>-<id>' pair (needs text on both sides of the first '-'), so no store can be asked about it" >&2
    return 1
  }
  # A roster that did not read, or is not a rig list, would leave every prefix
  # unmatched and read as "no rig carries it", which is a fact about the rigs
  # rather than about the answer and has a different repair. rig-map.sh refuses
  # both and names why.
  bead_store_map
  [ -n "$BEAD_STORE_MAP" ] || {
    echo "bead-store: could not read the rig map, so the store for $bead is unproven and nothing may be concluded about it" >&2
    return 3
  }
  rows=$(printf '%s' "$BEAD_STORE_MAP" | jq -r --arg p "$prefix" \
    '.rigs[]? | select(.prefix == $p) | [.name, (.path // "")] | @tsv' 2>/dev/null) || :
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    count=$((count + 1)); names="$names${row%%$'\t'*} "
  done <<<"$rows"
  if [ "$count" = 0 ]; then
    echo "bead-store: no rig carries the prefix '$prefix' (from $bead); \`gc rig list\` has $(printf '%s' "$BEAD_STORE_MAP" | jq -r '[.rigs[]?.prefix] | join(", ")' 2>/dev/null)" >&2
    return 1
  fi
  if [ "$count" != 1 ]; then
    echo "bead-store: prefix '$prefix' (from $bead) is carried by $count rigs ($names) — name the store explicitly" >&2
    return 3
  fi
  BEAD_STORE_RIG="${rows%%$'\t'*}"
  BEAD_STORE_PATH="${rows#*$'\t'}"
  return 0
}

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# The command. A sourced load skips it, in zsh as well, where BASH_SOURCE is
# unset and a caller's nounset would refuse it bare.
if [ "${BASH_SOURCE[0]:-}" = "$0" ]; then
  set -uo pipefail

  PROG="bead-store"

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

  bead_store_rig "$BEAD"
  case "$?" in
    0) ;;
    1) exit "$UNPLACED" ;;
    *) exit 3 ;;
  esac
  RIG_NAME="$BEAD_STORE_RIG"
  RIG_PATH="$BEAD_STORE_PATH"
  PREFIX="${BEAD%%-*}"

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

  ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/gctk-bead-store.XXXXXX")
  trap 'rm -f "$ERR_FILE" 2>/dev/null' EXIT
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  PAYLOAD=$(bounded gc bd --db "$DB" show "$BEAD" --json 2>"$ERR_FILE" | scrub)
  STORE_ERR=$(scrub <"$ERR_FILE"); rm -f "$ERR_FILE"
  trap - EXIT INT TERM HUP

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
fi
