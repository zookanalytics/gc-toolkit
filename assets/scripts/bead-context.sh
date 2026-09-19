#!/usr/bin/env bash
# bead-context.sh — one call rebuilds a subject's working context for an agent
# orienting on it: the converse opening claims, folds, then primes a subject
# before any work, and this answers that prime in a single call.
#
# Given a bead id it returns, and nothing outside this:
#   A. Subject core — status, priority, issue_type, task_kind, assignee; routing
#      (gc.routed_to, gc.execution_routed_to); anchor state when the bead carries
#      a merge_result (merge_result, pr_number, branch, merged_target); the
#      first_reaction fields; gc.origin; and the distilled gc.takeaway headline
#      (with gc.takeaway_settled). The free-text body is never parsed.
#   D. Context edges, shown but never gating — the parent, the relates-to edges,
#      the tracked-by visits, and a count per class.
#   E. Store — the store that answered, and the db it read.
# and, each behind its own opt-in flag:
#   B. --frontier — the blockers. A verdict over {ready, advancing, stuck}: ready
#      with no open blocker, else the worst open blocker's state. Each open
#      blocks-dep is named {id, title, status, advance}; closed blockers are a
#      count. `advance` is advancing when the blocker is itself moving (routed or
#      in progress) and stuck otherwise (unrouted, parked, blocked, or unknown —
#      fail closed).
#   C. --horizon — the direct children. The epic-health snapshot
#      {total, open, closed, advancing, stuck}; open children named
#      {id, title, status, advance}; done children counted only, so a
#      hundred-story epic stays bounded.
# The converse opening opts into both; a caller that only needs claimability
# opts into --frontier alone.
#
# A dependency in another rig's store comes back without an embedded status, so
# it is read from THAT store — the prefix binding assets/scripts/bead-store.sh
# proves — and folded in; a blocker whose store no rig carries reads unknown and
# fails the verdict closed. Three `gc bd show --json` quirks are handled so the
# read never dies on live data: a leading `gc bd:` notice line is stripped; raw
# C0 control bytes are scrubbed before jq; and the ARRAY-when-resolved versus
# `{"error":…}`-OBJECT-when-not payloads are told apart on type, not the exit
# code they share.
#
# Reads only. Descriptions, notes and comments — of the subject or any listed
# bead — and any body beyond {id, title, status, advance}, and any closed
# blocker or done child beyond its count, are omitted on purpose: that is the
# context bloat this tool exists to cut. `gc bd show <id>` still carries the
# body, and `<id> --json` the full per-edge detail, for the one bead a decision
# turns on. This complements `gc bd show`; it does not replace it.
#
# Usage:
#   bead-context.sh <bead-id> [--store rig:<name> | --db <path>/.beads]
#                             [--frontier] [--horizon] [--json]
#
# Exit: 0 reported · 2 usage · 4 the subject id could not be resolved to a bead.
# Doctrine: docs/bead-store-resolution.md. Test: bead-context.test.sh.
set -uo pipefail

PROG="bead-context"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

die()  { echo "$PROG: $1" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<'U'
usage: bead-context.sh <bead-id> [--store rig:<name> | --db <path>/.beads]
                                 [--frontier] [--horizon] [--json]

Rebuilds one bead's working context in a single call: its core (status,
priority, type, task_kind, assignee, routing, anchor state, first_reaction,
origin, takeaway), its context edges (parent, relates-to, tracked-by visits,
with a count per class), and the store that answered. --frontier adds the
blocker verdict (ready/advancing/stuck) with open blockers named and closed
counted; --horizon adds the direct-children epic-health snapshot. --store / --db
pin the owning store when a prefix is ambiguous or names the city's own store,
which no --rig value reaches. --json emits the whole context as one object.

Examples:
  bead-context.sh tk-8kc5dz --json                    core + edges + store
  bead-context.sh tk-8kc5dz --frontier --json         ... plus the blocker verdict
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
RIGS_JSON=$(bounded gc rig list --json 2>/dev/null | scrub || true)

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
# The subject and each dependency are read with --brief-deps: only a bead's own
# fields and its edges' {id, title, status, type} are read here, never a listed
# bead's body, and a hub bead's dependency bodies would otherwise dwarf the read.
bd_show() { bd_json "$1" show "$2" --brief-deps; }

# The advance enum, as a jq expression over a bead object, shared verbatim by the
# frontier per-blocker read and the horizon child scan so the two cannot drift. A
# bead moving on its own advances without external input: in progress, or routed
# to a worker or pool that will action it. A route to the reserved `human` alias
# is the opposite — a human gate — so it is stuck, as is an unrouted, parked (park
# clears the route), or unknown bead. One level, one bead's own row; a transitive
# walk (a blocker blocked by a blocker) drops in on the same enum later.
# gc.execution_routed_to is a finished pour's provenance, not a live route, so it
# is not consulted here.
ADV='(.metadata["gc.routed_to"] // "") as $r | if .status == "in_progress" then "advancing" elif ($r == "" or $r == "human" or ($r | endswith("/human"))) then "stuck" else "advancing" end'

# A blocker read reduced to the facts the frontier turns on: {status, advance,
# title}, as compact JSON so an empty route survives (a tab-delimited read
# collapses adjacent empty fields). Unreadable or absent reads unknown, which is
# stuck and fails the verdict closed rather than passing for landed.
read_bead() {
  bd_show "$1" "$2" | jq -c "def adv: $ADV;"' (if type == "array" and length > 0 then .[0] else {status: "unknown", metadata: {}, title: ""} end)
    | {status: (.status // "unknown"), advance: adv, title: (.title // "")}' 2>/dev/null \
    || echo '{"status":"unknown","advance":"stuck","title":""}'
}

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
    id, status,
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
# the older `related` — so the class matches either. The tracked-by visits are
# an INBOUND `tracks` edge (a visit tracks its subject; the subject carries no
# reverse edge), so they are read with a reverse dep-list.
TRACKED_BY=$(bd_json "$DB" dep list "$BEAD" --direction=up --type tracks \
  | jq -c 'if type == "array" then [.[] | {id, status}] else [] end' 2>/dev/null || echo '[]')
EDGES_JSON=$(printf '%s' "$SUBJ" | jq -c --argjson tracked "$TRACKED_BY" '
  (.parent // null) as $pid |
  ([.dependencies[]? | select(.dependency_type == "parent-child" and .id == $pid) | {id, title, status}] | .[0]) as $pedge |
  {
    parent: (if ($pid == null or $pid == "") then null else ($pedge // {id: $pid, title: null, status: null}) end),
    relates_to: [.dependencies[]? | select(.dependency_type == "relates-to" or .dependency_type == "related") | {id, title, status}],
    tracked_by: $tracked
  }
  | . + {counts: {
      parent: (if .parent == null then 0 else 1 end),
      relates_to: (.relates_to | length),
      tracked_by: (.tracked_by | length)
    }}')

# ── B. Frontier — blockers (opt-in) ─────────────────────────────────────────
# Each blocks-edge is a blocker of the subject. A same-store closed blocker
# carries its status in the edge and is only counted — the common bulk on an
# epic costs no read. Every other blocker is read once: to place a cross-store
# blocker open-vs-closed, and to read gc.routed_to for an open blocker's advance.
FRONTIER_JSON=""
if [ -n "$WANT_FRONTIER" ]; then
  CLOSED_BLK=0
  OPEN_BLK=()
  while IFS=$'\t' read -r bid btitle bstatus; do
    [ -n "$bid" ] || continue
    if [ "$bstatus" = "closed" ]; then CLOSED_BLK=$((CLOSED_BLK + 1)); continue; fi
    BJ=$(read_bead "$(db_for_prefix "${bid%%-*}")" "$bid")
    st=$(printf '%s' "$BJ" | jq -r '.status')
    if [ "$st" = "closed" ]; then CLOSED_BLK=$((CLOSED_BLK + 1)); continue; fi
    adv=$(printf '%s' "$BJ" | jq -r '.advance')
    rtitle=$(printf '%s' "$BJ" | jq -r '.title')
    title="$btitle"; { [ -z "$title" ] || [ "$title" = "null" ]; } && title="$rtitle"
    OPEN_BLK+=("$(jq -nc --arg id "$bid" --arg t "$title" --arg s "$st" --arg a "$adv" \
      '{id: $id, title: (if $t == "" then null else $t end), status: $s, advance: $a}')")
  done < <(printf '%s' "$SUBJ" | jq -rc '.dependencies[]? | select(.dependency_type == "blocks") | [.id, (.title // ""), (.status // "")] | @tsv')

  if [ "${#OPEN_BLK[@]}" -gt 0 ]; then OPEN_BLK_JSON=$(printf '%s\n' "${OPEN_BLK[@]}" | jq -sc '.'); else OPEN_BLK_JSON="[]"; fi
  OPEN_N="${#OPEN_BLK[@]}"
  if [ "$OPEN_N" -eq 0 ]; then VERDICT=ready
  elif printf '%s' "$OPEN_BLK_JSON" | jq -e 'any(.[]; .advance == "stuck")' >/dev/null 2>&1; then VERDICT=stuck
  else VERDICT=advancing; fi
  FRONTIER_JSON=$(jq -nc --arg v "$VERDICT" --argjson oc "$OPEN_N" --argjson cc "$CLOSED_BLK" --argjson open "$OPEN_BLK_JSON" \
    '{verdict: $v, blockers: {open: $oc, closed: $cc}, open: $open}')
fi

# ── C. Horizon — direct children (opt-in) ───────────────────────────────────
# The parent-child edge is stored on the child pointing up, so children are read
# with a --parent listing (closed included, or a done child is dropped from the
# count). The listing carries each child's metadata inline, so an advance state
# costs no extra read. Done children are counted only; open children are named.
HORIZON_JSON=""
if [ -n "$WANT_HORIZON" ]; then
  CHILDREN=$(bd_json "$DB" list --parent "$BEAD" --status open,in_progress,blocked,deferred,closed --limit 0)
  HORIZON_JSON=$(printf '%s' "$CHILDREN" | jq -c "def adv: $ADV;"'
    (if type == "array" then . else [] end) as $c |
    [$c[] | select(.status != "closed")] as $open |
    {
      children: {
        total: ($c | length),
        open: ($open | length),
        closed: ([$c[] | select(.status == "closed")] | length),
        advancing: ([$open[] | select(adv == "advancing")] | length),
        stuck: ([$open[] | select(adv == "stuck")] | length)
      },
      open: [$open[] | {id, title, status, advance: adv}]
    }' 2>/dev/null || echo '{"children":{"total":0,"open":0,"closed":0,"advancing":0,"stuck":0},"open":[]}')
fi

# ── Assemble ────────────────────────────────────────────────────────────────
FINAL=$(jq -nc --argjson subject "$SUBJECT_CORE" --argjson store "$STORE_JSON" --argjson edges "$EDGES_JSON" \
  '{subject: $subject, store: $store, edges: $edges}')
[ -n "$FRONTIER_JSON" ] && FINAL=$(printf '%s' "$FINAL" | jq -c --argjson f "$FRONTIER_JSON" '. + {frontier: $f}')
[ -n "$HORIZON_JSON" ]  && FINAL=$(printf '%s' "$FINAL" | jq -c --argjson h "$HORIZON_JSON" '. + {horizon: $h}')

if [ -n "$JSON_OUT" ]; then
  printf '%s\n' "$FINAL" | jq '.'
  exit 0
fi

# ── Human-readable block ────────────────────────────────────────────────────
g() { printf '%s' "$FINAL" | jq -r "$1" 2>/dev/null; }
val() { case "$1" in ""|null) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

printf '%s: %s\n\n' "$PROG" "$(g '.subject.id')"
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
[ "$(g '.edges.parent')" = "null" ] && [ "$REL_N" = "0" ] && [ "$TB_N" = "0" ] && printf '    (none)\n'

if [ -n "$WANT_FRONTIER" ]; then
  printf '\n  Frontier\n'
  printf '    verdict     %s\n' "$(g '.frontier.verdict')"
  printf '    blockers    %s open · %s closed\n' "$(g '.frontier.blockers.open')" "$(g '.frontier.blockers.closed')"
  g '.frontier.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(.advance))"'
fi

if [ -n "$WANT_HORIZON" ]; then
  printf '\n  Horizon\n'
  printf '    children    %s total · %s open · %s closed · %s advancing · %s stuck\n' \
    "$(g '.horizon.children.total')" "$(g '.horizon.children.open')" "$(g '.horizon.children.closed')" \
    "$(g '.horizon.children.advancing')" "$(g '.horizon.children.stuck')"
  g '.horizon.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(.advance))"'
fi
