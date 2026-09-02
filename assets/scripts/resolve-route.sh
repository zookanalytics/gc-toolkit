#!/usr/bin/env bash
# resolve-route.sh — name the live agent identity to stamp as a route or an
# assignee.
#   resolve-route.sh <name>
# A pool offer and an assignment poll both match by exact byte equality
# (gascity hookClaimMatchesRoute), so an address that is merely well-formed is
# claimed by nobody and every stamp still reads back clean. The qualifier a
# name needs is not a property of the name: a city-scoped agent carries a bare
# identity and a rig-scoped one carries `<rig>/`, so the same guess is wrong in
# opposite directions for two agents an author sees side by side. This resolves
# the guess against `gc agent list` instead: give it any form of the name and
# it prints the identity that is live, or refuses.
#
# Scope: GC_RIG selects the store the bead lands in, and only an agent that
# reads that store can be offered it, so candidates are the city-scoped
# identities plus this rig's. A name live only under another rig is a refusal,
# not a resolution.
#
# Exit: 0 resolved, identity on stdout · 1 unroutable (nothing on stdout)
#     · 2 usage · 3 roster unreadable, <name> echoed UNVERIFIED
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: resolve-route.sh <name>

Prints the live agent identity <name> resolves to. Accepts the identity
itself, the rig-unqualified form of one (`gc-toolkit.polecat`), a form
carrying a qualifier the identity does not (`gc-toolkit/gc-toolkit.dog`), or a
bare role (`refinery`). `human` is the operator marker and resolves to itself.

Stamp what it prints:
  ROUTE=$(resolve-route.sh gc-toolkit.dog) || ROUTE=""
  [ -n "$ROUTE" ] && gc bd create ... --metadata "{\"gc.routed_to\":\"$ROUTE\"}"

Refuses rather than guesses when a name resolves to several live identities;
name the one you mean. Exit 3 means the roster could not be read: <name> comes
back unchanged and unproven, which is the caller's decision to accept.
U
}

NAME="${1:-}"
[ "$#" -eq 1 ] && [ -n "$NAME" ] || { usage; exit 2; }
case "$NAME" in -*) usage; exit 2 ;; esac

ROSTER=$(if command -v timeout >/dev/null 2>&1; then timeout 15 gc agent list --json 2>/dev/null
         else gc agent list --json 2>/dev/null; fi | scrub)
IDS=$(printf '%s' "$ROSTER" | jq -c \
  '[.agents[]? | (.qualified_name // "") | select(. != "")] | unique' 2>/dev/null)

# Empty is the absence of proof, never proof of an empty city: with no roster
# every address looks dead, and refusing them all would mute the caller
# entirely. Hand the name back marked unproven and let the caller decide.
if [ -z "$IDS" ] || [ "$IDS" = "[]" ]; then
  echo "resolve-route: could not read the live agent set (\`gc agent list --json\`); '$NAME' is UNVERIFIED — confirm an agent carries it" >&2
  printf '%s\n' "$NAME"
  exit 3
fi

# `human` is the city's durable "the operator owns it; no agent will take it"
# marker (services/helm/README.md) — already held by its reader, not a name
# that failed to resolve.
if [ "$NAME" = "human" ]; then printf 'human\n'; exit 0; fi

# ok | ambiguous | unknown, then the identity (ok) or the candidate list, then
# the live identities the name resembles across every rig.
VERDICT=$(printf '%s' "$IDS" | jq -r --arg n "$NAME" --arg R "${GC_RIG:-}" '
  def bare: sub("^.*/"; "");
  def rig: if test("/") then sub("/.*$"; "") else "" end;
  def role: bare | sub("^.*\\."; "");
  . as $all
  | [ $all[] | select($R == "" or rig == "" or rig == $R) ] as $reach
  | [ $all[] | select(. == $n or bare == $n or . == ($n | bare) or role == $n) ] as $near
  | (if ($reach | index($n)) != null then ["ok", $n]
     elif ($n | bare) != $n and ($reach | index($n | bare)) != null then ["ok", ($n | bare)]
     else
       ([ $reach[] | select(bare == $n) ]) as $q
       | if ($q | length) == 1 then ["ok", $q[0]]
         elif ($q | length) > 1 then ["ambiguous", ($q | join(", "))]
         else
           ([ $reach[] | select(role == $n) ]) as $r
           | if ($n | test("[./]")) then ["unknown", ""]
             elif ($r | length) == 1 then ["ok", $r[0]]
             elif ($r | length) > 1 then ["ambiguous", ($r | join(", "))]
             else ["unknown", ""] end
         end
     end)
  + [($near | join(", "))]
  | join("\u001f")' 2>/dev/null)

IFS=$'\037' read -r CLASS VALUE NEAR <<< "$VERDICT"

case "${CLASS:-}" in
  ok)
    printf '%s\n' "$VALUE"
    exit 0 ;;
  ambiguous)
    echo "resolve-route: '$NAME' names several live identities, none of them more correct than the others: $VALUE" >&2
    echo "  stamping either would offer the work to one pool and hide it from the rest — pass the one you mean." >&2
    exit 1 ;;
  unknown)
    echo "resolve-route: '$NAME' matches no live agent identity that reads this store — nothing resolved (an address nothing claims still reads back clean)." >&2
    [ -n "${NEAR:-}" ] && echo "  live identities resembling it: $NEAR" >&2
    [ -n "${GC_RIG:-}" ] && echo "  GC_RIG=$GC_RIG selects the store, so only a city-scoped identity or one under '$GC_RIG/' can be offered work filed here." >&2
    exit 1 ;;
  *)
    echo "resolve-route: could not classify '$NAME' against the live agent set — nothing resolved." >&2
    exit 1 ;;
esac
