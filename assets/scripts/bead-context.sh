#!/usr/bin/env bash
# bead-context.sh — one call rebuilds a subject's working context for an agent
# orienting on it: the converse opening claims, folds, then primes a subject
# before any work, and this answers that prime in a single call.
#
# Given a bead id it returns, and nothing outside this:
#   A. Subject core — title, status, priority, issue_type, task_kind, assignee;
#      routing (gc.routed_to, gc.execution_routed_to); anchor state when the
#      bead carries a merge_result (merge_result, pr_number, branch,
#      merged_target); the first_reaction fields (the gc.first_reaction*
#      record an older reaction left on its subject); gc.origin; and the
#      distilled gc.takeaway headline (with gc.takeaway_settled). The free-text
#      body is never parsed.
#   D. Context edges, shown but never gating — the parent, the relates-to edges,
#      the beads that track it (a conversation about it, a convoy carrying it),
#      the beads that wait on this one by a blocks or an until edge (open ones
#      first, at most AWAITED_CAP named), and a count per class.
#   E. Store — the store that answered, and the db it read.
# and, each behind its own opt-in flag:
#   B. --frontier — what holds it. A verdict over {ready, advancing, stuck}:
#      ready when nothing holds it, else advancing when every wait behind what
#      holds it advances. Each wait is named {id, title, status, advance}, plus
#      stuck_on {id, why} when it is stuck, ancestor when it is an ancestor's
#      wait, and unjudged when it is a waits-for wait the store cannot judge
#      yet. holds is what holds it in one word, an edge into another store,
#      which holds nothing, is listed under foreign, and the bead's own landed
#      blockers are a count.
#   C. --horizon — the direct children. The epic-health snapshot
#      {total, open, closed, advancing, stuck}; open children named
#      {id, title, status, advance} (plus stuck_on when stuck); done children
#      counted only, so a hundred-story epic stays bounded.
# The converse opening opts into both; a caller that only needs claimability
# opts into --frontier alone.
#
# What holds the subject, with the waits behind it, is the answer of
# `gctk bead holds`, and the verdict, each wait's advance and each open child's
# are the answers of `gctk bead stands`, the rule the helm board reads
# (docs/gctk-architecture.md, "The bead holds contract" and "The bead stands
# contract"). Each is asked once, through the binary the city builds, pinned to
# the subject's store, so a wait into another store is left out, as
# `gctk bead holds` leaves it. A read that does not answer fails closed: the
# verdict is stuck, and a bead with no answer reads stuck on itself, unread.
# Three `gc bd --json` quirks are handled so the read never dies on live data:
# a leading `gc bd:` notice line is stripped; raw C0 control bytes are scrubbed
# before jq; and the ARRAY-when-resolved versus `{"error":…}`-OBJECT-when-not
# payloads are told apart on type, not the exit code they share.
#
# Reads only. Descriptions, notes and comments — of the subject or any listed
# bead — and any body beyond {id, title, status, advance} and a stuck bead's
# stuck_on {id, why}, and any closed blocker or done child beyond its count, are
# omitted on purpose: that is the context bloat this tool exists to cut.
# `gc bd show <id>` still carries the body, and `<id> --json` the full per-edge
# detail, for the one bead a decision turns on. This complements `gc bd show`;
# it does not replace it.
#
# Usage:
#   bead-context.sh <bead-id> [--store rig:<name> | --db <path>/.beads]
#                             [--frontier] [--horizon] [--json]
#
# Exit: 0 reported · 2 usage · 4 the subject id could not be resolved to a bead.
# Doctrine: docs/bead-store-resolution.md. Test: bead-context.test.sh.
set -uo pipefail

PROG="bead-context"

# The awaited-by edges name at most this many of the beads that wait on the
# subject, the open ones first, and count the rest. A gate can hold a hundred
# parked beads, and the edges print on every read.
AWAITED_CAP=10

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

_bd_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$_bd_lib_dir/bd-lib.sh}" || { echo "cannot source bd-lib.sh beside this script" >&2; exit 1; }

usage() {
  cat >&2 <<'U'
usage: bead-context.sh <bead-id> [--store rig:<name> | --db <path>/.beads]
                                 [--frontier] [--horizon] [--json]

Rebuilds one bead's working context in a single call: its core (title, status,
priority, type, task_kind, assignee, routing, anchor state, first_reaction,
origin, takeaway), its context edges (parent, relates-to, the beads that
track it, the beads that wait on it by a blocks or until edge, with a count per
class), and the store that answered. --frontier adds the verdict on what holds
it (ready/advancing/stuck) with each open wait named and its closed blockers
counted; --horizon adds the direct-children epic-health snapshot. Each named
wait or child carries its advance from gctk bead stands: stuck names the bead
that stops it and why. --store / --db pin the owning store when a prefix is
ambiguous or names the city's own store, which no --rig value reaches. --json
emits the whole context as one object.

Examples:
  bead-context.sh tk-8kc5dz --json                    core + edges + store
  bead-context.sh tk-8kc5dz --frontier --json         ... plus the verdict on what holds it
  bead-context.sh tk-87nwhv --frontier --horizon --json   the converse opening's call
  bead-context.sh ab-1a2b3c --store rig:other         pin the store when a prefix is ambiguous
U
  exit 2
}

BEAD=""; STORE_REF=""; DB=""; JSON_OUT=""; WANT_FRONTIER=""; WANT_HORIZON=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --store)    [ "$#" -ge 2 ] || die "--store needs a value (rig:<name>)" 2; STORE_REF="$2"; shift 2 ;;
    --db)       [ "$#" -ge 2 ] || die "--db needs a value (<path>/.beads)" 2; DB="$2"; shift 2 ;;
    --frontier) WANT_FRONTIER=1; shift ;;
    --horizon)  WANT_HORIZON=1; shift ;;
    --json)     JSON_OUT=1; shift ;;
    -h|--help)  usage ;;
    -*)         die "unknown argument '$1' (try --help)" 2 ;;
    *)          [ -z "$BEAD" ] || die "more than one bead id given ('$BEAD' and '$1')" 2; BEAD="$1"; shift ;;
  esac
done
[ -n "$BEAD" ] || usage

# A bounded call: an unreachable Dolt server hangs, and a tool that hangs never
# answers. Mirrors bead-store.sh, whose resolution this shares.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else "$@"; fi
}

# The rig roster is read once and reused for every prefix resolution below, so a
# bead with a dozen same-store deps does not re-shell `gc rig list` a dozen times.
# A roster that does not read leaves every prefix unresolved, and rig-map.sh says
# why on stderr.
RIGS_JSON=$("$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rig-map.sh" || true)

# prefix -> owning rig name, empty unless exactly one rig carries it (an unknown
# or a two-rig prefix is not a store this tool may silently pick).
rig_name_for_prefix() {
  printf '%s' "$RIGS_JSON" | jq -r --arg p "$1" \
    '[.rigs[]? | select(.prefix == $p)] | if length == 1 then .[0].name else "" end' 2>/dev/null || true
}
# prefix -> that rig's `<path>/.beads` store, empty when unresolved or pathless.
db_for_prefix() {
  printf '%s' "$RIGS_JSON" | jq -r --arg p "$1" \
    '[.rigs[]? | select(.prefix == $p)] | if length == 1 and ((.[0].path // "") != "") then .[0].path + "/.beads" else "" end' 2>/dev/null || true
}
# rig name -> that rig's `<path>/.beads` store, for --store rig:<name>.
db_for_rig_name() {
  printf '%s' "$RIGS_JSON" | jq -r --arg n "$1" \
    '[.rigs[]? | select(.name == $n)] | if length == 1 and ((.[0].path // "") != "") then .[0].path + "/.beads" else "" end' 2>/dev/null || true
}

# `gc bd [--db <db>] <args...> --json`, cleaned of the two contaminants that
# break a naive pipe to jq: the `gc bd:` notice line that can lead stdout, and
# raw control bytes. The notice strip runs with `grep -a` (force text mode): a
# raw NUL byte in the notes otherwise switches grep to binary and drops the
# whole payload before scrub can remove the byte, so the read must stay text
# through the filter and let scrub take the C0 bytes out. Prints the cleaned
# payload; the caller discriminates shape.
bd_json() {
  local db="$1"; shift
  if [ -n "$db" ]; then
    bounded gc bd --db "$db" "$@" --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true
  else
    bounded gc bd "$@" --json 2>/dev/null | grep -a -vE '^gc bd:' | scrub || true
  fi
}
# The subject is read with --brief-deps: only its own fields and its edges'
# {id, title, status, type} are read here, never a listed bead's body, and a hub
# bead's dependency bodies would otherwise dwarf the read. --include-dependents
# adds the beads with an edge to it, each cut by bd to its identity fields and
# the edge's type, again with no body.
bd_show() { bd_json "$1" show "$2" --brief-deps --include-dependents; }
# ── Resolve the subject's store ─────────────────────────────────────────────
# --db wins outright; then --store rig:<name>; then the id's own prefix. When
# none resolves, the read falls back to an unpinned `gc bd show`, which finds a
# live id in whichever store holds it (it cannot prove an ABSENCE, but this tool
# reports rather than destroys, so a plain not-found is a safe answer).
SUBJ_PREFIX="${BEAD%%-*}"
SUBJ_RIG=""
if [ -n "$DB" ]; then
  SUBJ_RIG=$(printf '%s' "$RIGS_JSON" | jq -r --arg d "$DB" \
    '[.rigs[]? | select(((.path // "") + "/.beads") == $d)] | if length == 1 then .[0].name else "" end' 2>/dev/null || true)
elif [ -n "$STORE_REF" ]; then
  case "$STORE_REF" in
    rig:?*) SUBJ_RIG="${STORE_REF#rig:}"; DB=$(db_for_rig_name "$SUBJ_RIG") ;;
    *) die "--store wants the form rig:<name> (got '$STORE_REF')" 2 ;;
  esac
  [ -n "$DB" ] || die "--store $STORE_REF does not resolve to a rig with a store path in 'gc rig list'" 2
else
  SUBJ_RIG=$(rig_name_for_prefix "$SUBJ_PREFIX")
  DB=$(db_for_prefix "$SUBJ_PREFIX")
fi

RAW=$(bd_show "$DB" "$BEAD")
KIND=$(printf '%s' "$RAW" | jq -r 'type' 2>/dev/null || true)
if [ "$KIND" != "array" ]; then
  # An object is the `{"error":…}` not-found; empty is an unreadable store. Both
  # are "no bead to report", distinct from a bead that exists and is empty.
  WHERE="${SUBJ_RIG:-${DB:-the ambient store}}"
  die "$BEAD did not resolve to a bead in $WHERE — nothing to report (pass --store rig:<name> or --db <path>/.beads if it lives elsewhere)" 4
fi

# bd resolves a bare id as an exact-or-prefix match, so .[0] may be a longer
# bead the prefix hit. Report whichever id actually resolved rather than echoing
# the input.
SUBJ=$(printf '%s' "$RAW" | jq -c '.[0]')

# ── A. Subject core ─────────────────────────────────────────────────────────
# absent -> null, present-but-empty -> "" is preserved: `//` alternates only on
# null, so a metadata key that resolves to "" (a cleared route, an unsettled
# takeaway) reads as the empty string it is, distinct from an absent key.
SUBJECT_CORE=$(printf '%s' "$SUBJ" | jq -c '
  (.metadata // {}) as $m | {
    id,
    title: (.title // null),
    status,
    priority: (.priority // null),
    issue_type: (.issue_type // null),
    task_kind: ($m["task_kind"] // null),
    assignee: (.assignee // null),
    routed_to: ($m["gc.routed_to"] // null),
    execution_routed_to: ($m["gc.execution_routed_to"] // null),
    anchor: (if (($m["merge_result"] // "") | tostring) != "" then {
        merge_result: $m["merge_result"],
        pr_number: ($m["pr_number"] // null),
        branch: ($m["branch"] // null),
        merged_target: ($m["merged_target"] // null)
      } else null end),
    first_reaction: {
        reaction: ($m["gc.first_reaction"] // null),
        at: ($m["gc.first_reaction_at"] // null),
        reason: ($m["gc.first_reaction_reason"] // null),
        target: ($m["gc.first_reaction_target"] // null)
      },
    origin: ($m["gc.origin"] // null),
    takeaway: ($m["gc.takeaway"] // null),
    takeaway_settled: ($m["gc.takeaway_settled"] // null)
  }')

# ── E. Store ────────────────────────────────────────────────────────────────
STORE_JSON=$(jq -nc --arg rig "$SUBJ_RIG" --arg db "$DB" \
  '{rig: (if $rig == "" then null else $rig end), db: (if $db == "" then null else $db end)}')

# ── D. Context edges (never gating) ─────────────────────────────────────────
# The parent link and the relates-to edges are outbound, so they come from the
# subject's own read. Both edge spellings live in the store — `relates-to` and
# the older `related` — so the class matches either. The beads that track it are
# an INBOUND `tracks` edge (a conversation tracks the bead it is about, and the
# subject carries no reverse edge), so they are read with a reverse dep-list.
# The beads that wait on the subject carry a `blocks` or an `until` edge to it,
# inbound too, and they come from the dependents the subject's own read carries.
# The dependents also hold every child and every inbound `related` edge, the
# review and rework machinery this list leaves out, so it keeps the two edge
# types. bd neither bounds the dependents nor puts the open ones first, so the
# list does both and counts all of them. bd reads only the subject's store, so a
# bead in another store that waits on it is not listed.
TRACKED_BY=$(bd_json "$DB" dep list "$BEAD" --direction=up --type tracks \
  | jq -c 'if type == "array" then [.[] | {id, status}] else [] end' 2>/dev/null || echo '[]')
AWAITED=$(printf '%s' "$SUBJ" | jq -c --argjson cap "$AWAITED_CAP" '
  [.dependents[]? | select(type == "object" and (.id // "") != "" and (.dependency_type == "blocks" or .dependency_type == "until"))
    | {id, title: (.title // null), status, edge: .dependency_type}]
  | unique_by(.id) | sort_by(.status == "closed")
  | {total: length, open: ([.[] | select(.status != "closed")] | length), named: .[:$cap]}' 2>/dev/null)
[ -n "$AWAITED" ] || AWAITED='{"total":0,"open":0,"named":[]}'
EDGES_JSON=$(printf '%s' "$SUBJ" | jq -c --argjson tracked "$TRACKED_BY" --argjson awaited "$AWAITED" '
  (.parent // null) as $pid |
  ([.dependencies[]? | select(.dependency_type == "parent-child" and .id == $pid) | {id, title, status}] | .[0]) as $pedge |
  {
    parent: (if ($pid == null or $pid == "") then null else ($pedge // {id: $pid, title: null, status: null}) end),
    relates_to: [.dependencies[]? | select(.dependency_type == "relates-to" or .dependency_type == "related") | {id, title, status}],
    tracked_by: $tracked,
    awaited_by: $awaited.named
  }
  | . + {counts: {
      parent: (if .parent == null then 0 else 1 end),
      relates_to: (.relates_to | length),
      tracked_by: (.tracked_by | length),
      awaited_by: $awaited.total,
      awaited_by_open: $awaited.open
    }}')

# ── B/C. Frontier and horizon (opt-in) ──────────────────────────────────────
# The children are the subject's direct children. The parent-child edge is
# stored on the child pointing up, so they come from a --parent listing, asked
# for with --all: bd's default scope leaves out closed and pinned children, and a
# --status list leaves out every status it does not name, a store's own
# statuses included, so either would drop a child from the count. The listing
# also returns the closed event bead `bd set-state` files under a bead each time
# its state changes. An event records the change, not work, so it is left out
# and never counted as a child.
# What holds the subject comes from `gctk bead holds`, and where the subject and
# its open children stand from one `gctk bead stands`, each through the binary
# the city builds, pinned to the store the subject was read from. The subject's
# line carries its frontier, the verdict with each wait's advance as the
# verdict reads it.
# >>> gctk-bin
GCTK="${GCTK_BIN:-${GC_CITY_PATH:-}/.gc/services/gctk/bin/gctk}"
# <<< gctk-bin
SUBJ_ID=$(printf '%s' "$SUBJ" | jq -r '.id')
HOLDS='{"status":"unread","error":"the frontier was not asked for","waits":[],"foreign":[]}'
if [ -n "$WANT_FRONTIER" ]; then
  if [ -x "$GCTK" ]; then
    HOLDS=$("$GCTK" bead holds ${DB:+--db "$DB"} "$SUBJ_ID" 2>/dev/null | scrub \
      | jq -c 'if .error == null and (.status // "") != "" then . else {status: "unread", error: (.error // "gctk bead holds gave no status"), waits: [], foreign: []} end' 2>/dev/null)
    [ -n "$HOLDS" ] || HOLDS='{"status":"unread","error":"gctk bead holds did not answer","waits":[],"foreign":[]}'
  else
    HOLDS=$(jq -nc --arg g "$GCTK" '{status: "unread", error: ("no gctk binary at " + $g), waits: [], foreign: []}')
  fi
fi
FRONTIER_JSON=""; HORIZON_JSON=""
if [ -n "$WANT_FRONTIER" ] || [ -n "$WANT_HORIZON" ]; then
  CHILDREN='[]'
  if [ -n "$WANT_HORIZON" ]; then
    CHILDREN=$(bd_json "$DB" list --parent "$BEAD" --all --limit 0 \
      | jq -c 'if type == "array"
               then [.[] | select((.issue_type? // "") != "event")]
               else [] end' 2>/dev/null)
    [ -n "$CHILDREN" ] || CHILDREN='[]'
  fi
  # The beads asked about: the subject for its frontier, and each open child.
  ASK=()
  [ -z "$WANT_FRONTIER" ] || ASK+=("$SUBJ_ID")
  while IFS= read -r id; do
    [ -n "$id" ] && ASK+=("$id")
  done < <(printf '%s' "$CHILDREN" | jq -r '.[] | select(.status != "closed") | .id' 2>/dev/null)
  # Each line keyed by its id. A line that carries an error, and a bead with no
  # line, has no answer.
  STANDS='{}'; STANDS_ERR=""
  if [ "${#ASK[@]}" -gt 0 ]; then
    if [ -x "$GCTK" ]; then
      STANDS=$("$GCTK" bead stands ${DB:+--db "$DB"} "${ASK[@]}" 2>/dev/null | scrub \
        | jq -sc '[.[] | objects | select((.id // "") != "")] | map({key: .id, value: .}) | from_entries' 2>/dev/null)
      [ -n "$STANDS" ] || { STANDS='{}'; STANDS_ERR="gctk bead stands did not answer"; }
    else
      STANDS_ERR="no gctk binary at $GCTK"
    fi
  fi
  # A named bead's advance as stands answered it, and stuck on itself, unread,
  # where it has no answer.
  NAMED='def named($id; $a): if ($a.advance // "") == "advancing" then {advance: "advancing"}
      else {advance: "stuck", stuck_on: ($a.stuck_on // {id: $id, why: "unread"})} end;'

  # B. The frontier. It is ready when holds answers that nothing holds the
  # subject, a closed subject included, whose stands line carries no frontier.
  # Otherwise it is the subject's frontier as stands reads it, with each wait
  # holds names read as the verdict reads it. A read of what holds it that did
  # not answer, or a held subject stands did not answer, is stuck, and says why.
  if [ -n "$WANT_FRONTIER" ]; then
    FRONTIER_JSON=$(printf '%s\n%s\n%s\n' "$SUBJ" "$STANDS" "$HOLDS" | jq -sc --arg serr "$STANDS_ERR" "$NAMED"'
      .[0] as $s | .[2] as $h | (.[1][$s.id] // {}) as $line | ($line.frontier // null) as $f
      | [$h.waits[]?] as $waits
      | (if $h.status == "unread" then $h.error
         elif $h.status == "clear" then null
         elif $f == null then ($line.error // (if $serr != "" then $serr else "gctk bead stands gave no frontier" end))
         else null end) as $unread
      | {verdict: (if $unread != null then "stuck" elif $h.status == "clear" then "ready" else $f.verdict end),
         holds: $h.status,
         blockers: {open: ($waits | length),
                    closed: ([$s.dependencies[]? | select(.dependency_type == "blocks" and .status == "closed")] | length)},
         open: [$waits[] | . as $w
           | {id: $w.id,
              title: (($w.title // "") | if . == "" then null else . end),
              status: (if ($w.status // "") != "" then $w.status else "unknown" end)}
             + (if ($w.ancestor // "") != "" then {ancestor: $w.ancestor} else {} end)
             + (if $w.type == "waits-for" then {unjudged: true} else {} end)
             + named($w.id; ([$f.waits[]? | select(.id == $w.id)] | .[0]))]}
        + (if $unread != null then {unread: $unread} else {} end)
        + (if ([$h.foreign[]?] | length) > 0 then {foreign: [$h.foreign[].id]} else {} end)' 2>/dev/null)
    [ -n "$FRONTIER_JSON" ] || FRONTIER_JSON='{"verdict":"stuck","holds":"unread","blockers":{"open":0,"closed":0},"open":[],"unread":"the frontier did not compose"}'
  fi

  # C. The horizon: done children counted only, open children named.
  if [ -n "$WANT_HORIZON" ]; then
    HORIZON_JSON=$(printf '%s\n%s\n' "$CHILDREN" "$STANDS" | jq -sc "$NAMED"'
      .[0] as $c | .[1] as $st
      | [$c[] | select(.status != "closed") | {id, title, status} + named(.id; $st[.id])] as $open
      | {children: {total: ($c | length), open: ($open | length),
                    closed: ([$c[] | select(.status == "closed")] | length),
                    advancing: ([$open[] | select(.advance == "advancing")] | length),
                    stuck: ([$open[] | select(.advance != "advancing")] | length)},
         open: $open}' 2>/dev/null)
    [ -n "$HORIZON_JSON" ] || HORIZON_JSON='{"children":{"total":0,"open":0,"closed":0,"advancing":0,"stuck":0},"open":[]}'
  fi
fi

# ── Assemble ────────────────────────────────────────────────────────────────
FINAL=$(jq -nc --argjson subject "$SUBJECT_CORE" --argjson store "$STORE_JSON" --argjson edges "$EDGES_JSON" \
  '{subject: $subject, store: $store, edges: $edges}')
# The sections ride stdin, not an argument: a wide epic's horizon outgrows the
# kernel's cap on one argument.
[ -n "$FRONTIER_JSON" ] && FINAL=$(printf '%s\n%s\n' "$FINAL" "$FRONTIER_JSON" | jq -sc '.[0] + {frontier: .[1]}')
[ -n "$HORIZON_JSON" ]  && FINAL=$(printf '%s\n%s\n' "$FINAL" "$HORIZON_JSON" | jq -sc '.[0] + {horizon: .[1]}')

if [ -n "$JSON_OUT" ]; then
  printf '%s\n' "$FINAL" | jq '.'
  exit 0
fi

# ── Human-readable block ────────────────────────────────────────────────────
g() { printf '%s' "$FINAL" | jq -r "$1" 2>/dev/null; }
val() { case "$1" in ""|null) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
# A named blocker or child's advance as one phrase: "advancing", "stuck: <why>"
# when it stops itself, "stuck on <id>: <why>" when a bead beneath it does.
ADV_TEXT='def adv_text: if .advance == "advancing" then "advancing"
  elif (.stuck_on.id // .id) == .id then "stuck: \(.stuck_on.why // "unknown")"
  else "stuck on \(.stuck_on.id): \(.stuck_on.why // "unknown")" end; '

printf '%s: %s\n\n' "$PROG" "$(g '.subject.id')"
printf '  Title       %s\n' "$(val "$(g '.subject.title // ""')" '(untitled)')"
printf '  Status      %s\n' "$(g '.subject.status')"
printf '  Priority    %s\n' "$(val "$(g '.subject.priority // ""')" '(none)')"
printf '  Type        %s\n' "$(val "$(g '.subject.issue_type // ""')" '(none)')"
TK=$(g '.subject.task_kind // ""'); [ -n "$TK" ] && printf '  Task kind   %s\n' "$TK"
printf '  Assignee    %s\n' "$(val "$(g '.subject.assignee // ""')" '(unassigned)')"
printf '  Store       %s\n' "$(val "$(g '.store.rig // ""')" "(unresolved: prefix '$SUBJ_PREFIX')")"

RT=$(g '.subject.routed_to // ""'); XRT=$(g '.subject.execution_routed_to // ""')
[ -n "$RT" ]  && printf '  Routed to   %s\n' "$RT"
[ -n "$XRT" ] && printf '  Execution   %s  (provenance, not a live route)\n' "$XRT"
OR=$(g '.subject.origin // ""'); [ -n "$OR" ] && printf '  Origin      %s\n' "$OR"
TA=$(g '.subject.takeaway // ""')
if [ -n "$TA" ]; then
  SETTLED=$(g '.subject.takeaway_settled // ""')
  printf '  Takeaway    %s%s\n' "$TA" "$(case "$SETTLED" in ""|null|0) ;; *) printf '  [settled]' ;; esac)"
fi
FR=$(g '.subject.first_reaction.reaction // ""')
if [ -n "$FR" ]; then
  FRT=$(g '.subject.first_reaction.target // ""')
  printf '  First react %s%s\n' "$FR" "$( [ -n "$FRT" ] && printf ' → %s' "$FRT")"
fi

if [ "$(g '.subject.anchor')" != "null" ]; then
  printf '\n  Anchor\n'
  printf '    merge_result  %s\n' "$(g '.subject.anchor.merge_result')"
  PRN=$(g '.subject.anchor.pr_number // ""'); [ -n "$PRN" ] && printf '    pr            #%s\n' "$PRN"
  printf '    branch        %s\n' "$(val "$(g '.subject.anchor.branch // ""')" '(unset)')"
  printf '    merged_target %s\n' "$(val "$(g '.subject.anchor.merged_target // ""')" '(unset)')"
fi

printf '\n  Edges\n'
if [ "$(g '.edges.parent')" != "null" ]; then
  printf '    parent      %s  %s (%s)\n' "$(g '.edges.parent.id')" "$(g '.edges.parent.title // ""')" "$(g '.edges.parent.status // "?"')"
fi
REL_N=$(g '.edges.counts.relates_to')
if [ "$REL_N" != "0" ]; then
  printf '    relates-to  %s: %s\n' "$REL_N" "$(g '.edges.relates_to | map("\(.id) (\(.status))") | join(", ")')"
fi
TB_N=$(g '.edges.counts.tracked_by')
if [ "$TB_N" != "0" ]; then
  printf '    tracked-by  %s: %s\n' "$TB_N" "$(g '.edges.tracked_by | map("\(.id) (\(.status))") | join(", ")')"
fi
AW_N=$(g '.edges.counts.awaited_by')
if [ "$AW_N" != "0" ]; then
  printf '    awaited-by  %s\n' "$(g '.edges | "\(.counts.awaited_by) (\(.counts.awaited_by_open) open): "
    + (.awaited_by | map("\(.id) (\(.status), \(.edge))") | join(", "))
    + ((.counts.awaited_by - (.awaited_by | length)) as $more | if $more > 0 then ", and \($more) more" else "" end)')"
fi
[ "$(g '.edges.parent')" = "null" ] && [ "$REL_N" = "0" ] && [ "$TB_N" = "0" ] && [ "$AW_N" = "0" ] && printf '    (none)\n'

if [ -n "$WANT_FRONTIER" ]; then
  printf '\n  Frontier\n'
  printf '    verdict     %s (%s)\n' "$(g '.frontier.verdict')" "$(g '.frontier.holds')"
  [ "$(g '.frontier.unread // ""')" = "" ] || printf '    unread      %s\n' "$(g '.frontier.unread')"
  printf '    blockers    %s open · %s closed\n' "$(g '.frontier.blockers.open')" "$(g '.frontier.blockers.closed')"
  g "$ADV_TEXT"'.frontier.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(adv_text))"
    + (if .ancestor then " on ancestor \(.ancestor)" else "" end) + (if .unjudged then ", waits-for, unjudged" else "" end)'
  [ "$(g '.frontier.foreign // [] | length')" = "0" ] || printf '    foreign     %s (edges into another store, which hold nothing)\n' "$(g '.frontier.foreign | join(", ")')"
fi

if [ -n "$WANT_HORIZON" ]; then
  printf '\n  Horizon\n'
  printf '    children    %s total · %s open · %s closed · %s advancing · %s stuck\n' \
    "$(g '.horizon.children.total')" "$(g '.horizon.children.open')" "$(g '.horizon.children.closed')" \
    "$(g '.horizon.children.advancing')" "$(g '.horizon.children.stuck')"
  g "$ADV_TEXT"'.horizon.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(adv_text))"'
fi
