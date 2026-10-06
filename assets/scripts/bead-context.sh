#!/usr/bin/env bash
# bead-context.sh — one call rebuilds a subject's working context for an agent
# orienting on it: the converse opening claims, folds, then primes a subject
# before any work, and this answers that prime in a single call.
#
# Given a bead id it returns, and nothing outside this:
#   A. Subject core — title, status, priority, issue_type, task_kind, assignee;
#      routing (gc.routed_to, gc.execution_routed_to); anchor state when the
#      bead carries a merge_result (merge_result, pr_number, branch,
#      merged_target); the first_reaction fields; gc.origin; and the distilled
#      gc.takeaway headline (with gc.takeaway_settled). The free-text body is
#      never parsed.
#   D. Context edges, shown but never gating — the parent, the relates-to edges,
#      the tracked-by visits, and a count per class.
#   E. Store — the store that answered, and the db it read.
# and, each behind its own opt-in flag:
#   B. --frontier — the blockers. A verdict over {ready, advancing, stuck}: ready
#      with no open blocker, else the worst open blocker's advance. Each open
#      blocks-dep is named {id, title, status, advance}, plus stuck_on {id, why}
#      when it is stuck; closed blockers are a count.
#   C. --horizon — the direct children. The epic-health snapshot
#      {total, open, closed, advancing, stuck}; open children named
#      {id, title, status, advance} (plus stuck_on when stuck); done children
#      counted only, so a hundred-story epic stays bounded.
# The converse opening opts into both; a caller that only needs claimability
# opts into --frontier alone.
#
# `advance` is transitive. A blocker or child is advancing only when the city
# moves it without a person — it is claimed, routed, assigned, machine work,
# armed for deferred dispatch, or a merge anchor the cadence will act on — AND
# every open blocker beneath it advances too. Anything else is stuck, and
# stuck_on names the bead that stops it and why (the classifier below lists
# each reason). The walk reads level by level, one batched read per store, and
# stops descending at the first stuck bead on a branch.
#
# `gc bd show` leaves out an edge whose far end lives in another rig's store, so
# a blocker's edges come from its list row, which keeps them, and each blocker is
# read from the store its prefix binds — the binding assets/scripts/bead-store.sh
# proves. A blocker whose store no rig carries reads unknown and fails the verdict
# closed. Three `gc bd --json` quirks are handled so the read never dies on live
# data: a leading `gc bd:` notice line is stripped; raw C0 control bytes are
# scrubbed before jq; and the ARRAY-when-resolved versus `{"error":…}`-OBJECT-
# when-not payloads are told apart on type, not the exit code they share.
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
#                             [--frontier] [--horizon] [--walk-budget <n>] [--json]
#
# Exit: 0 reported · 2 usage · 4 the subject id could not be resolved to a bead.
# Doctrine: docs/bead-store-resolution.md. Test: bead-context.test.sh.
set -uo pipefail

PROG="bead-context"

# The walk's bounds. It reads at most WALK_BUDGET beads beyond the subject's own
# direct blockers, which are always read, and descends at most WALK_DEPTH levels.
# A branch either bound cuts reads stuck with why=budget: a walk that stopped
# early cannot vouch that the branch drains.
WALK_BUDGET=50
WALK_DEPTH=6
# deferred-dispatch.sh stops re-slinging an armed bead at this many failed slings
# and hands it to a person; the same knob and default set the cap read here.
ARM_CAP="${GC_MAX_DISPATCH_SLING_FAILURES:-3}"
case "$ARM_CAP" in ''|*[!0-9]*) ARM_CAP=3 ;; esac

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
                                 [--frontier] [--horizon] [--walk-budget <n>] [--json]

Rebuilds one bead's working context in a single call: its core (title, status,
priority, type, task_kind, assignee, routing, anchor state, first_reaction,
origin, takeaway), its context edges (parent, relates-to, tracked-by visits,
with a count per class), and the store that answered. --frontier adds the
blocker verdict (ready/advancing/stuck) with open blockers named and closed
counted; --horizon adds the direct-children epic-health snapshot. Each named
blocker or child carries a transitive advance: stuck names the bead that stops
it and why. --walk-budget caps the beads that walk reads beyond the subject's
direct blockers (default 50). --store / --db pin the owning store when a prefix
is ambiguous or names the city's own store, which no --rig value reaches.
--json emits the whole context as one object.

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
    --walk-budget)
      [ "$#" -ge 2 ] || die "--walk-budget needs a value (a positive count of beads)" 2
      case "$2" in ''|*[!0-9]*) die "--walk-budget wants a positive count of beads (got '$2')" 2 ;; esac
      WALK_BUDGET=$((10#$2))
      [ "$WALK_BUDGET" -gt 0 ] || die "--walk-budget wants a positive count of beads (got '$2')" 2
      shift 2 ;;
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
# The subject is read with --brief-deps: only its own fields and its edges'
# {id, title, status, type} are read here, never a listed bead's body, and a hub
# bead's dependency bodies would otherwise dwarf the read.
bd_show() { bd_json "$1" show "$2" --brief-deps; }
# The walk reads list rows instead: `gc bd show` leaves out an edge whose far end
# lives in another rig's store, and a list row keeps every edge. --brief drops the
# free text. `gc bd list` hides gates, infrastructure beads, template molecules
# and ephemeral rows unless asked, and a blocker can be any of them, so the read
# asks for all four.
# One call takes any number of ids from one store and returns the rows it found,
# so a missing id shows as an absence. bd_rows <db> <id>...
bd_rows() {
  local db="$1"; shift
  local ids; ids=$(IFS=,; printf '%s' "$*")
  bd_json "$db" list --id "$ids" --all --brief --include-gates --include-infra --include-templates --include-ephemeral --limit 0
}

# ── The advance classifier ──────────────────────────────────────────────────
# jq defs, prepended to every program that classifies, so the frontier and the
# horizon read one classifier and cannot drift. adv_own is a bead's own state,
# read off its own row:
#
#   advancing  in progress or hooked: someone holds it.
#              review, rework, validation or finding: machine work the review
#                cycle owns. The pour that dispatched it clears its route, so an
#                empty route there is the pour's residue, not a gate.
#              routed to a worker or pool.
#              armed for deferred dispatch: the reconcile order slings it once
#                its own blockers close.
#              assigned to an agent, whose queue holds it.
#              a merge anchor the cadence acts on: its recorded machine axis is
#                progressing, or settled before a PR exists (the PR-open pass
#                publishes it), or settled with a PR that needs no further review.
#   stuck      human: routed or assigned to the reserved `human` gate, a
#                decision, a finding that needs the operator, or an anchor parked
#                in a human state.
#              held: any other status. Blocked, deferred and pinned are
#                deliberate holds no pool offers; a status a store adds is one
#                this classifier does not know, so it fails closed.
#              approval: an open PR settled and waiting on the operator's review
#                (review required, or changes requested) at its live head.
#              merge-hold: an operator merge or rebase hold on an anchor.
#              wedged, merge-blocked: the anchor's machine axis says no automated
#                actor can move it.
#              unread: an anchor whose machine axis, or whose PR posture at that
#                axis's head, is not recorded.
#              capped: an armed dispatch that hit its sling-failure cap.
#              unrouted: open with no route, arm or assignee, so nothing picks it up.
#
# Where two rules apply, in-progress outranks everything and an explicit human
# route outranks every advancing kind, so a review routed to a person stays stuck.
# Whether a claim's or a route's session is still up is a liveness join over the
# session list, not a fact on the row, so a stranded claim reads advancing here,
# and a bead a poured molecule is working (its work bead, or an inline step)
# carries no route of its own and reads unrouted. gc.execution_routed_to is a
# pour's provenance, not a live route, and is not read.
ADV='
def adv_truthy: ((. // "") | tostring) as $s
  | ($s == "" or $s == "false" or $s == "False" or $s == "FALSE" or $s == "0" or $s == "null") | not;
def adv_human: . == "human" or endswith("/human");
def adv_dated: ((. // "") | tostring | split("@")) as $p
  | if ($p | length) == 3 and $p[0] != "" and $p[1] != "" then {value: $p[0], head: $p[1]} else null end;
def adv_anchor($m; $mr):
  if $mr != "pre_open_gate" and $mr != "pull_request" then {state: "stuck", why: "human"}
  elif ($m["merge_hold"] | adv_truthy) or ($m["rebase_hold"] | adv_truthy) then {state: "stuck", why: "merge-hold"}
  else ($m["pr.machine"] | adv_dated) as $ma | ($m["pr_posture"] | adv_dated) as $po
    | if $ma == null then {state: "stuck", why: "unread"}
      elif $ma.value == "progressing" then {state: "advancing"}
      elif $ma.value == "wedged-exception" then {state: "stuck", why: "wedged"}
      elif $ma.value == "blocked" then {state: "stuck", why: "merge-blocked"}
      elif $ma.value != "settled" then {state: "stuck", why: "unread"}
      elif $mr == "pre_open_gate" then {state: "advancing"}
      elif $po == null or $po.head != $ma.head then {state: "stuck", why: "unread"}
      elif $po.value == "review_required" or $po.value == "changes_requested" then {state: "stuck", why: "approval"}
      elif $po.value == "approved" or $po.value == "commented" or $po.value == "none" then {state: "advancing"}
      else {state: "stuck", why: "unread"} end
  end;
def adv_own($cap):
  (.metadata // {}) as $m
  | (($m["gc.routed_to"] // "") | tostring) as $r
  | (($m["task_kind"] // "") | tostring) as $tk
  | (($m["merge_result"] // "") | tostring) as $mr
  | ((.assignee // "") | tostring) as $a
  | if .status == "in_progress" or .status == "hooked" then {state: "advancing"}
    elif ($r | adv_human) or ($a | adv_human) or .issue_type == "decision" then {state: "stuck", why: "human"}
    elif .status != "open" then {state: "stuck", why: "held"}
    elif $mr != "" then adv_anchor($m; $mr)
    elif $tk == "finding" and (($m["finding.disposition"] // "") == "needs-you") then {state: "stuck", why: "human"}
    elif $tk == "review" or $tk == "rework" or $tk == "validation" or $tk == "finding" then {state: "advancing"}
    elif $r != "" then {state: "advancing"}
    elif (($m["gc.dispatch_when_ready"] // "") | tostring) != "" then
      (if (($m["gc.dispatch_when_ready_fail_count"] // 0) | tostring | tonumber? // 0) >= $cap
       then {state: "stuck", why: "capped"} else {state: "advancing"} end)
    elif $a != "" then {state: "advancing"}
    else {state: "stuck", why: "unrouted"} end;
'

# ── The walk ────────────────────────────────────────────────────────────────
# A bead advances only when its own state does and every open blocker beneath it
# advances too, so an armed bead, or a routed bead behind a stuck one, takes its
# blockers' verdict. The walk carries one object between reads: rows (id -> the
# row as read), req (the ids asked for), and the roots the sections name.
#   walk_blocks   a row's blocks edges in either read shape: `gc bd show` gives
#                 {dependency_type, id, status, title}, `gc bd list` gives
#                 {type, depends_on_id} with no status.
#   walk_open     its open blockers: an edge or a row that reads closed holds
#                 nothing.
#   walk_states   every row's state, settled to a fixpoint. A bead is stuck when
#                 its own state is or any open blocker is, and inherits that
#                 blocker's stuck_on; advancing when its own state is and every
#                 open blocker advances. A blocker asked for and not returned is
#                 unknown. In the final pass a blocker never asked for is budget.
#                 Beads on a cycle never settle, since each waits on the next.
#   walk_pending  the unread blockers still worth reading: those reachable from an
#                 unsettled root through unsettled beads. A settled bead's
#                 subtree cannot change its verdict, so it is not read.
#   walk_verdict  a root's final {state, on}; an unsettled root sits on or behind
#                 a cycle, and on names a bead on that cycle.
WALK_JQ='
def walk_blocks: [(.dependencies // [])[]?
  | select(((.dependency_type // .type) // "") == "blocks")
  | {id: ((.id // .depends_on_id) // ""), status: (.status // null), title: (.title // null)}
  | select(.id != "")];
def walk_open($rows): [walk_blocks[] | select(.status != "closed") | .id
  | select((($rows[.] // {}).status // "") != "closed")];
def walk_leaf($rows; $req; $final; $acc; $b):
  if $rows[$b] != null then $acc[$b]
  elif $req[$b] then {state: "stuck", on: {id: $b, why: "unknown"}}
  elif $final then {state: "stuck", on: {id: $b, why: "budget"}}
  else null end;
def walk_pass($rows; $own; $req; $final):
  reduce ($rows | keys_unsorted[]) as $id (.;
    . as $acc
    | if $acc[$id] != null or $own[$id].state == "closed" then $acc
      elif $own[$id].state == "stuck" then $acc + {($id): {state: "stuck", on: {id: $id, why: $own[$id].why}}}
      else [$rows[$id] | walk_open($rows)[] as $b | walk_leaf($rows; $req; $final; $acc; $b)] as $bs
        | ([$bs[] | select(. != null and .state == "stuck")] | .[0]) as $hit
        | if $hit != null then $acc + {($id): {state: "stuck", on: $hit.on}}
          elif all($bs[]; . != null and .state == "advancing") then $acc + {($id): {state: "advancing"}}
          else $acc end
      end);
def walk_states($rows; $req; $final; $cap):
  ($rows | map_values(if .status == "closed" then {state: "closed"} else adv_own($cap) end)) as $own
  | def settle: walk_pass($rows; $own; $req; $final) as $n | if $n == . then . else ($n | settle) end;
    {} | settle;
def walk_cycle($rows; $st; $id):
  {cur: $id, seen: {}}
  | until(.cur == null or .seen[.cur];
      .cur as $c | .seen[$c] = true
      | .cur = ([$rows[$c] | walk_open($rows)[] | select($rows[.] != null and $st[.] == null)] | .[0]))
  | .cur // $id;
def walk_pending($rows; $req; $st; $roots):
  {todo: $roots, seen: {}, out: []}
  | until((.todo | length) == 0;
      .todo[0] as $id | .todo |= .[1:]
      | if .seen[$id] then .
        else .seen[$id] = true
          | if $rows[$id] == null then (if $req[$id] then . else .out += [$id] end)
            elif $st[$id] != null or (($rows[$id].status // "") == "closed") then .
            else .todo += [$rows[$id] | walk_open($rows)[]] end
        end)
  | .out;
def walk_verdict($rows; $req; $st; $id):
  if $rows[$id] == null then walk_leaf($rows; $req; true; $st; $id)
  elif ($rows[$id].status // "") == "closed" then {state: "closed"}
  elif $st[$id] != null then $st[$id]
  else {state: "stuck", on: {id: walk_cycle($rows; $st; $id), why: "cycle"}} end;
'

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

# ── B/C. Frontier and horizon — the advance walk (opt-in) ───────────────────
# The roots are the beads the two sections name: the subject's blockers, and its
# open children. A same-store closed blocker of the subject carries its status in
# the show edge and is only counted, so the common bulk on an epic costs no read.
# The subject's own list row rides the first level's read, since only a list row
# carries the subject's blockers in other stores. Its other blockers are always
# read, whatever the budget, as the frontier has to place each one open or
# closed. The parent-child edge is stored on the child pointing up, so children
# come from a --parent listing, asked for with --all. bd's default scope leaves
# out closed and pinned children, and a --status list leaves out every status it
# does not name, a store's own statuses included, so either would drop a child
# from the count. The listing carries each child's own row, so only its blockers
# are read, and only while its own state advances.
FRONTIER_JSON=""; HORIZON_JSON=""
if [ -n "$WANT_FRONTIER" ] || [ -n "$WANT_HORIZON" ]; then
  CHILDREN='[]'
  if [ -n "$WANT_HORIZON" ]; then
    CHILDREN=$(bd_json "$DB" list --parent "$BEAD" --all --limit 0 \
      | jq -c 'if type == "array" then . else [] end' 2>/dev/null)
    [ -n "$CHILDREN" ] || CHILDREN='[]'
  fi
  WALK=$(printf '%s\n%s\n' "$SUBJ" "$CHILDREN" | jq -sc --arg f "$WANT_FRONTIER" "$WALK_JQ"'
    .[0] as $s | [.[1][] | select(.status != "closed")] as $open
    | (if $f == "" then [] else [$s | walk_blocks[] | select(.status != "closed") | .id] end) as $direct
    | {subject: $s.id, relist: (if $f == "" then [] else [$s.id] end),
       rows: ((if $f == "" then {} else {($s.id): $s} end) + ([$open[] | {key: .id, value: .}] | from_entries)),
       req: {}, roots: ($direct + [$open[].id]),
       forced: ([$direct[] | {key: ., value: true}] | from_entries)}' 2>/dev/null)
  [ -n "$WALK" ] || WALK='{"subject":"","relist":[],"rows":{},"req":{},"roots":[],"forced":{}}'

  # Level by level: ask for every unread blocker still worth reading, the
  # subject's own first, at one read per store, and fold the rows back in. The
  # budget counts the open beads met below the subject's own blockers; a closed
  # row costs nothing, as an open blocker's own rows bring its closed edges too.
  SPENT=0; LEVEL=0
  declare -A DB_OF=()   # prefix -> its store, resolved once per prefix
  while [ "$LEVEL" -lt "$WALK_DEPTH" ]; do
    NEXT=$(printf '%s' "$WALK" | jq -r --argjson cap "$ARM_CAP" "$ADV$WALK_JQ"'
      walk_states(.rows; .req; false; $cap) as $st | .forced as $f
      | walk_pending(.rows; .req; $st; .roots) as $p
      | (.relist | map("F\t\(.)")) + ($p | map(select($f[.]) | "F\t\(.)")) + ($p | map(select($f[.] | not) | "B\t\(.)"))
      | .[]' 2>/dev/null) || break
    ASK=(); BELOW=()
    while IFS=$'\t' read -r kind id; do
      [ -n "${id:-}" ] || continue
      if [ "$kind" = F ]; then ASK+=("$id")
      elif [ "$SPENT" -lt "$WALK_BUDGET" ]; then ASK+=("$id"); BELOW+=("$id"); fi
    done <<< "$NEXT"
    [ "${#ASK[@]}" -gt 0 ] || break
    # id<TAB>store, the id first so an unresolved store survives as an empty field.
    PAIRS=""
    for id in "${ASK[@]}"; do
      p="${id%%-*}"
      [ -n "${DB_OF[$p]+set}" ] || DB_OF[$p]=$(db_for_prefix "$p")
      PAIRS+="$id"$'\t'"${DB_OF[$p]}"$'\n'
    done
    BATCH='[]'
    while IFS= read -r gdb; do
      GIDS=()
      while IFS=$'\t' read -r pid pdb; do
        [ -n "${pid:-}" ] && [ "${pdb:-}" = "$gdb" ] && GIDS+=("$pid")
      done <<< "$PAIRS"
      [ "${#GIDS[@]}" -gt 0 ] || continue
      GOT=$(bd_rows "$gdb" "${GIDS[@]}")
      MERGED=$(printf '%s\n%s\n' "$BATCH" "$GOT" | jq -sc '.[0] + (.[1] | if type == "array" then . else [] end)' 2>/dev/null)
      [ -n "$MERGED" ] && BATCH="$MERGED"
    done < <(printf '%s' "$PAIRS" | cut -f2 | sort -u)
    ASKED=$(printf '%s\n' "${ASK[@]}" | jq -R . | jq -sc .)
    if [ "${#BELOW[@]}" -gt 0 ]; then BELOW_JSON=$(printf '%s\n' "${BELOW[@]}" | jq -R . | jq -sc .); else BELOW_JSON='[]'; fi
    # Fold the rows in, first read wins. The subject's list row only completes the
    # subject's edges: every blocks edge it carries joins the subject's own, the
    # show edge's status and title kept where one exists, and a blocker only the
    # list row names becomes a root the next level reads.
    NEW=$(printf '%s\n%s\n' "$WALK" "$BATCH" | jq -sc --argjson asked "$ASKED" "$WALK_JQ"'
      .[0] as $w | [.[1][]? | select(type == "object" and (.id // "") != "")] as $got
      | ([$got[] | select(.id == $w.subject and ($w.relist | index([$w.subject])) != null)] | .[0]) as $sl
      | $w
      | .rows = (([$got[] | select(.id != $w.subject) | {key: .id, value: .}] | from_entries) + .rows)
      | .req += ([$asked[] | {key: ., value: true}] | from_entries)
      | .relist = []
      | if $sl == null then . else
          (.rows[$w.subject] | walk_blocks) as $shown
          | [$sl | walk_blocks[] | . as $e | (([$shown[] | select(.id == $e.id)] | .[0]) // $e)] as $edges
          | ($shown + [$edges[] | select(.id as $i | ($shown | map(.id) | index([$i])) == null)]) as $all
          | .rows[$w.subject].dependencies = [$all[] | {id, dependency_type: "blocks", status, title}]
          | ([$all[] | select(.status != "closed") | .id] - .roots) as $new
          | .roots = (.roots + $new)
          | .forced += ([$new[] | {key: ., value: true}] | from_entries)
        end' 2>/dev/null)
    [ -n "$NEW" ] || break
    WALK="$NEW"
    MET=$(printf '%s\n' "$BATCH" | jq -r --argjson below "$BELOW_JSON" \
      '[.[]? | select(type == "object" and (.status // "") != "closed" and (.id as $i | $below | index([$i])) != null)] | length' 2>/dev/null)
    SPENT=$((SPENT + ${MET:-0}))
    LEVEL=$((LEVEL + 1))
  done

  RES=$(printf '%s' "$WALK" | jq -c --argjson cap "$ARM_CAP" "$ADV$WALK_JQ"'
    .rows as $rows | .req as $req | walk_states($rows; $req; true; $cap) as $st
    | [.roots[] | {key: ., value: walk_verdict($rows; $req; $st; .)}] | from_entries' 2>/dev/null)
  [ -n "$RES" ] || RES='{}'
  # A root the resolution could not place reads unknown: stuck, fail closed.
  VERDICT_OF='def verdict_of($res; $id): ($res[$id] // {state: "stuck", on: {id: $id, why: "unknown"}});
    def named($v): {advance: (if $v.state == "advancing" then "advancing" else "stuck" end)}
      + (if $v.state == "advancing" then {} else {stuck_on: $v.on} end);'

  # B. The frontier: ready with no open blocker, else the worst open blocker's
  # advance. An unreadable blocker stays open with status unknown.
  if [ -n "$WANT_FRONTIER" ]; then
    FRONTIER_JSON=$(printf '%s\n%s\n%s\n' "$SUBJ" "$WALK" "$RES" | jq -sc "$WALK_JQ$VERDICT_OF"'
      .[1].rows as $rows | .[2] as $res
      | (($rows[.[1].subject] // .[0]) | walk_blocks) as $all
      | [$all[] | select(.status != "closed") | select(($res[.id].state // "") != "closed")] as $open
      | {verdict: (if ($open | length) == 0 then "ready"
                   elif any($open[]; verdict_of($res; .id).state != "advancing") then "stuck"
                   else "advancing" end),
         blockers: {open: ($open | length), closed: (($all | length) - ($open | length))},
         open: [$open[] | . as $d | ($rows[$d.id] // {}) as $row
           | {id: $d.id,
              title: ((if ($d.title // "") != "" then $d.title else ($row.title // "") end) | if . == "" then null else . end),
              status: ($row.status // "unknown")}
             + named(verdict_of($res; $d.id))]}' 2>/dev/null)
    [ -n "$FRONTIER_JSON" ] || FRONTIER_JSON='{"verdict":"stuck","blockers":{"open":0,"closed":0},"open":[]}'
  fi

  # C. The horizon: done children counted only, open children named.
  if [ -n "$WANT_HORIZON" ]; then
    HORIZON_JSON=$(printf '%s\n%s\n' "$CHILDREN" "$RES" | jq -sc "$VERDICT_OF"'
      .[0] as $c | .[1] as $res
      | [$c[] | select(.status != "closed")] as $open
      | {children: {total: ($c | length), open: ($open | length),
                    closed: ([$c[] | select(.status == "closed")] | length),
                    advancing: ([$open[] | select(verdict_of($res; .id).state == "advancing")] | length),
                    stuck: ([$open[] | select(verdict_of($res; .id).state != "advancing")] | length)},
         open: [$open[] | {id, title, status} + named(verdict_of($res; .id))]}' 2>/dev/null)
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
[ "$(g '.edges.parent')" = "null" ] && [ "$REL_N" = "0" ] && [ "$TB_N" = "0" ] && printf '    (none)\n'

if [ -n "$WANT_FRONTIER" ]; then
  printf '\n  Frontier\n'
  printf '    verdict     %s\n' "$(g '.frontier.verdict')"
  printf '    blockers    %s open · %s closed\n' "$(g '.frontier.blockers.open')" "$(g '.frontier.blockers.closed')"
  g "$ADV_TEXT"'.frontier.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(adv_text))"'
fi

if [ -n "$WANT_HORIZON" ]; then
  printf '\n  Horizon\n'
  printf '    children    %s total · %s open · %s closed · %s advancing · %s stuck\n' \
    "$(g '.horizon.children.total')" "$(g '.horizon.children.open')" "$(g '.horizon.children.closed')" \
    "$(g '.horizon.children.advancing')" "$(g '.horizon.children.stuck')"
  g "$ADV_TEXT"'.horizon.open[]? | "    open        \(.id)  \(.title // "") (\(.status), \(adv_text))"'
fi
