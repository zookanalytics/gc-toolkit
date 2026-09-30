#!/usr/bin/env bash
# file-warrant.sh — resolve a wedged owner to a LIVE session id and file (or
# dedup) exactly one warrant for the dog pool.
#   file-warrant.sh --owner <owner> --reason <reason> --requester <who> \
#                   --dog <route> [--role <text>]
#
# warrant.target is contractually a session id: the dog feeds it straight to
# dance-probe.sh --session and `gc session kill`, and dance-probe.sh refuses
# any value outside [A-Za-z0-9._-] (see dance-probe.sh charset guard). An owner
# named on a wedged bead is often NOT that: owner precedence falls to the
# assignee, a rig-qualified agent address carrying a `/` (gc-toolkit/gc-toolkit.polecat-3),
# which dance-probe.sh rejects — the warrant is filed, refused as unsafe, and the
# session is never drained. This filer resolves the owner to the session id the
# dog can act on before it writes, and refuses rather than file a warrant no dog
# can execute.
#
#   --owner      the wedged owner to resolve: a session id, an alias (the
#                rig-qualified agent address), or a session name. Resolved to a
#                live session id against `gc session list --state=all --json`,
#                the same source dance-probe.sh reads, matching .id / .alias /
#                .session_name.
#   --reason     warrant.reason — what is stale, and for how long.
#   --requester  warrant.requester — the detector filing it (witness, deacon).
#   --dog        the resolved dog route, stamped as gc.routed_to. The caller
#                resolves it (resolve-route.sh) so city-vs-rig scope is decided
#                where the roster is known.
#   --role       human-readable label for the title (default: --owner). The
#                title carries the role a human reads; warrant.target carries the
#                session id the dog acts on.
#
# Dedup is keyed on the resolved session id, so two owners that name one session
# collapse to a single open warrant.
#
# Exit: 0 a new warrant was filed — its id on stdout
#     · 3 a warrant was already open for this session — its id on stdout, nothing
#         filed (a caller that ledgers a filing keys on 0 and skips 3; a caller
#         that only needs the session covered treats 0 and 3 alike)
#     · 1 owner did not resolve to a live, safe session id — nothing filed
#     · 4 the create failed and no open warrant could be re-read — nothing filed
#         (distinct from 1: the owner resolved, but the store write did not land,
#         so a caller must not read it as covered)
#     · 2 usage error
set -uo pipefail

usage() {
  cat >&2 <<'U'
usage: file-warrant.sh --owner <owner> --reason <reason> --requester <who> \
                       --dog <route> [--role <text>]

Resolves <owner> to a live session id and files ONE dog-pool warrant against
it, deduped on that id. Refuses (exit 1, nothing filed) when <owner> resolves
to no live session, so no warrant the dog cannot execute is ever written.
U
}

OWNER=""; REASON=""; REQUESTER=""; DOG=""; ROLE=""; ROLE_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --owner)     OWNER="${2:-}";     shift 2 || { usage; exit 2; } ;;
    --reason)    REASON="${2:-}";    shift 2 || { usage; exit 2; } ;;
    --requester) REQUESTER="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --dog)       DOG="${2:-}";       shift 2 || { usage; exit 2; } ;;
    --role)      ROLE="${2:-}"; ROLE_SET=1; shift 2 || { usage; exit 2; } ;;
    -h|--help)   usage; exit 2 ;;
    *) echo "file-warrant: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done
[ "$ROLE_SET" -eq 1 ] || ROLE="$OWNER"
for pair in "owner:$OWNER" "reason:$REASON" "requester:$REQUESTER" "dog:$DOG"; do
  if [ -z "${pair#*:}" ]; then
    echo "file-warrant: --${pair%%:*} is required" >&2; usage; exit 2
  fi
done

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

# An id unsafe as a filename or argument is refused, never filed. This is
# dance-probe.sh's own charset guard: reject an empty value, any byte outside
# [A-Za-z0-9._-], a leading . or -, or an embedded ".." — so the target a
# warrant carries is exactly what dance-probe.sh --session will accept.
safe_id() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*|.*|-*|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

# Resolve an owner to a live session's id. Matches .id / .alias / .session_name
# (dance-probe.sh's session lookup), preferring an id match, then an alias, then
# a session name. Excludes the states dance-probe.sh treats as gone
# (absent/closed/archived), so a warrant is never targeted at a dead session.
# Prints the id, or nothing when no live session matches or the list is
# unreadable — an unreadable list is not proof of a live target, so it too
# yields a refusal upstream.
resolve_live_session() {
  local owner="$1" json
  json="$(gc session list --state=all --json 2>/dev/null | scrub)"
  [ -n "$json" ] || return 0
  printf '%s' "$json" | jq -r --arg o "$owner" '
    def live: (.state // "") | (. != "absent" and . != "closed" and . != "archived");
    [ .sessions[]? | select(live) ] as $ls
    | ( [ $ls[] | select(.id == $o) ]
      + [ $ls[] | select((.alias // "") == $o) ]
      + [ $ls[] | select((.session_name // "") == $o) ] )
    | (.[0].id // empty)' 2>/dev/null
}

SID="$(resolve_live_session "$OWNER")"
if [ -z "$SID" ] || ! safe_id "$SID"; then
  echo "file-warrant: owner '$OWNER' did not resolve to a live, safe session id (got '${SID:-<none>}'); no warrant filed — a target dance-probe.sh would reject is never written." >&2
  exit 1
fi

# Dedup on the resolved session id, like an escalation key: one open warrant per
# wedged session, never a second.
open_warrant_for() {
  gc bd list --status=open,in_progress --metadata-field "warrant.target=$1" --limit=1 --json 2>/dev/null \
    | jq -r 'if type == "array" then (.[0].id // empty) else empty end' 2>/dev/null
}

EXISTING="$(open_warrant_for "$SID")"
if [ -n "$EXISTING" ]; then
  echo "warrant $EXISTING already open for $SID; not filing another" >&2
  printf '%s\n' "$EXISTING"
  exit 3
fi

gc bd create --type=task --title="Stuck: $ROLE" --label=warrant \
  --metadata "$(jq -nc --arg t "$SID" --arg r "$REASON" --arg who "$REQUESTER" --arg d "$DOG" \
    '{"warrant.target":$t,"warrant.reason":$r,"warrant.requester":$who,"gc.routed_to":$d}')" >&2
CREATE_RC=$?

# Re-read the id rather than trusting create's stdout, which can answer with an
# empty id although the bead landed. A resolved id proves the warrant stands
# whatever the create's exit, so print it and report a filing.
FILED="$(open_warrant_for "$SID")"
if [ -n "$FILED" ]; then
  printf '%s\n' "$FILED"
  exit 0
fi

# Nothing re-reads. A failed create with no warrant is the silent gap this filer
# exists to close: the owner resolved, but the store write did not land, so a
# caller must not read the session as covered. Refuse instead of exiting 0.
if [ "$CREATE_RC" -ne 0 ]; then
  echo "file-warrant: gc bd create failed (rc=$CREATE_RC) and no open warrant for $SID could be re-read; nothing filed." >&2
  exit 4
fi

# The create succeeded though its id has not re-read yet (store lag): the bead
# landed, so report the filing with the empty stdout the caller defaults rather
# than lose it.
exit 0
