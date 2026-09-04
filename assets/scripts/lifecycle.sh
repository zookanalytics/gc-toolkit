#!/usr/bin/env bash
# lifecycle.sh — THE writer of anchor lifecycle transitions (lifecycle/lifecycle.toml).
#   lifecycle.sh transition <bead-id> --to <state> [--expect <state>] [--set k=v]...
#     [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>] [--route <pool>]
#     [--takeaway <text>] [--close] [--append-notes <t>] [--json]
#   lifecycle.sh state <bead-id>
#   lifecycle.sh reopen <bead-id>
# transition: validate the edge against the declared machine, perform ONE atomic
# `gc bd update` carrying every field, re-read and verify each written field.
# --set-dated writes a key in the dated shape <value>@<oid>@<since>, appending
# the third component under compare-and-preserve: the existing instant survives
# while value and oid both hold, and a change to either stamps a fresh one. The
# reconcile cadence re-derives the same verdict at the same head every few
# minutes, so a naive clock would restart a three-day wait on every pass.
# --close only into a closed state, or into unanchored from a non-anchor
# current state — unanchored or held, the terminal a non-anchor takes, whose
# declared status is open|closed; a closed state requires --close (status and
# merge_result move together). A state's declared
# routing rides in the same call unless --route is given: human states stamp
# gc.routed_to=human, and detached states clear it unless the bead already
# rests on the park route.
# A detached state also clears the assignee of a bead still at status=open,
# unless --assignee is given; that is the unheld half of the same property. A
# human state also refuses an EMPTY --route: a bead waiting on a person has to
# name one, and routing to the park sentinel refuses without a takeaway — the
# board spends gc.takeaway as the row's NEEDS sentence, so a park with none
# reaches the operator saying no question was recorded. --takeaway writes the
# triple (text/_at/_by) in the same atomic call, capped at 140 codepoints and
# refused when it normalizes to nothing; a bead that already carries a takeaway
# satisfies the guard.
# reopen: repair a bead closed while merge_result is a NON-closed state — set
# status=open, merge_result untouched. Human-invoked only (docs/authority-map.md).
# Callers: pr-open.sh, merge.sh, pr-facts.sh, mol-refinery-patrol.
# Exits: 0 ok; 1 illegal edge / --expect mismatch / bd refusal / usage;
# 2 post-write verification mismatch (or unreadable bead).
# CAVEAT (docs/gascity-routing-model.md row 46): clearing an assignee on a bead
# another actor holds in_progress is refused by bd, and the refusal drops the
# WHOLE atomic update — a caller that passes --assignee "" must hold the claim.
# The detached-state clear reads the status for that reason and stops at open.
#
# THE SHELL BELOW IS THE FALLBACK. `gctk lifecycle` (services/gctk) is the
# ported implementation and answers whenever the build order has published a
# binary; this script runs when it has not — a fresh city, a build that failed,
# a rig checkout ahead of the deployed binary. Both must stay correct until the
# last port lands and the fallback drops, so lifecycle.test.sh runs its whole
# body against both, and both mirrors of the state table are held against
# lifecycle/lifecycle.toml.
set -u

# Resolution is EXPLICIT: $GCTK_BIN, else the city named by GC_CITY_PATH,
# GC_CITY or GC_CITY_ROOT — the same precedence boot-health.sh, doctor-sweep.sh
# and the tmux pickers read, and GC_CITY_PATH is the one the supervisor puts in
# an agent session — else the city `gc service list --json` reports. The
# listing is what the merge cadence itself needs: the order runner that execs
# refinery-reconcile.sh carries no city variable at all (docs/
# refinery-merge-cadence.md), so an env-only chain would leave every cadence
# transition on this fallback while the board reported the binary current.
# Never a walk up from this file's own path — the hermetic suite runs from a
# tree inside a live city, and a filesystem hunt would find that city's binary
# and stop testing this script. GCTK_BIN=none forces this implementation.
#
# A binary the city resolved is also held to THIS checkout: `gctk version`
# carries the tree hash of services/gctk it was built from, and a checkout
# whose services/gctk is at another one — a rig ahead of the build order's
# ~5m lag, or a branch that changed the port — falls back to this script,
# which is the writer that matches its callers. A binary that cannot be
# compared (no stamp, no git) is trusted; an explicit $GCTK_BIN is never
# second-guessed.
GCTK_BIN="${GCTK_BIN:-}"
if [ -z "$GCTK_BIN" ]; then
    _gctk_city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    if [ -z "$_gctk_city" ]; then
        _gctk_city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
    fi
    [ -n "$_gctk_city" ] && GCTK_BIN="$_gctk_city/.gc/services/gctk/bin/gctk"
    if [ -n "$GCTK_BIN" ] && [ -x "$GCTK_BIN" ]; then
        _gctk_mod="$(dirname "${BASH_SOURCE[0]}")/../../services/gctk"
        _gctk_want="$(git -C "$_gctk_mod" rev-parse 'HEAD:./' 2>/dev/null || true)"
        _gctk_have="$("$GCTK_BIN" version 2>/dev/null | head -n 1 || true)"
        if [ -n "$_gctk_want" ] && [ -n "$_gctk_have" ] && [ "$_gctk_have" != unknown ] \
           && [ "$_gctk_have" != "$_gctk_want" ]; then
            # A hand build carries the toolchain's commit stamp instead; the
            # subtree that commit holds is the comparable identity.
            _gctk_mapped="$(git -C "$_gctk_mod" rev-parse "${_gctk_have%-dirty}:./" 2>/dev/null || true)"
            if [ "$_gctk_mapped" != "$_gctk_want" ]; then
                echo "$0: deployed gctk is built from $_gctk_have, this checkout's services/gctk is at $_gctk_want; using the shell fallback" >&2
                GCTK_BIN=""
            fi
        fi
    fi
fi
if [ "$GCTK_BIN" != "none" ] && [ -n "$GCTK_BIN" ] && [ -x "$GCTK_BIN" ]; then
    exec "$GCTK_BIN" lifecycle "$@"
fi

PROG="lifecycle"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub

# >>> lifecycle-state-table
# Mirrors lifecycle/lifecycle.toml exactly; lifecycle.test.sh fails on drift.
LIFECYCLE_STATES="unanchored pre_open_gate pull_request merged abandoned retargeted blocked refused_false_completion held"
LIFECYCLE_HUMAN_STATES="abandoned retargeted blocked refused_false_completion held"
LIFECYCLE_DETACHED_STATES="pre_open_gate pull_request"
LIFECYCLE_PARK_ROUTE="human"
LIFECYCLE_CLOSED_STATES="merged"
LIFECYCLE_TRANSITIONS="
unanchored>pre_open_gate
unanchored>pull_request
unanchored>merged
unanchored>blocked
unanchored>refused_false_completion
unanchored>held
pre_open_gate>pull_request
pre_open_gate>unanchored
pull_request>merged
pull_request>abandoned
pull_request>retargeted
pull_request>unanchored
abandoned>unanchored
retargeted>pull_request
retargeted>unanchored
blocked>unanchored
refused_false_completion>unanchored
held>unanchored
"
# <<< lifecycle-state-table

# The board's NEEDS cell, in codepoints. Mirrors gc-helm.sh's TAKEAWAY_MAX.
LIFECYCLE_TAKEAWAY_MAX=140

is_state() { # <name>
  case " $LIFECYCLE_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_human_state() { # <name>
  case " $LIFECYCLE_HUMAN_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_detached_state() { # <name>
  case " $LIFECYCLE_DETACHED_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_closed_state() { # <name>
  case " $LIFECYCLE_CLOSED_STATES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

edge_legal() { # <from> <to>  (a self-edge is always legal: idempotent re-record)
  [ "$1" = "$2" ] && return 0
  case "$LIFECYCLE_TRANSITIONS" in *"
$1>$2
"*) return 0 ;; *) return 1 ;; esac
}

read_bead() { # <id> -> the bead object, or nothing
  gc bd show "$1" --json 2>/dev/null | scrub | jq -c '.[0] // empty' 2>/dev/null
}

# Current state off a bead object: merge_result, "unanchored" when absent.
state_of() { # <bead-json>; echoes state, or "?<raw>" for an undeclared value
  local mr
  mr=$(printf '%s' "$1" | jq -r '(.metadata.merge_result // "") | tostring' 2>/dev/null)
  if [ -z "$mr" ]; then printf 'unanchored'; return 0; fi
  if is_state "$mr" && [ "$mr" != "unanchored" ]; then printf '%s' "$mr"; return 0; fi
  printf '?%s' "$mr"
  return 1
}

# The `since` write rule, in one place so two writers cannot disagree about
# when a turn began: keep the existing instant while both the value and the oid
# hold, and stamp the current one when either differs. A value that is not
# already in the three-component shape has no instant to keep.
dated_since() { # <existing-value> <wanted "value@oid"> -> RFC 3339 UTC
  local have="${1:-}" want="${2:-}" rest
  case "$have" in
    "$want@"*)
      rest="${have#"$want@"}"
      case "$rest" in
        ""|*@*) : ;;
        *) printf '%s' "$rest"; return 0 ;;
      esac ;;
  esac
  date -u +%Y-%m-%dT%H:%M:%SZ
}

cmd_state() { # <bead-id>
  local id="${1:-}" bead st
  [ -n "$id" ] || { echo "$PROG: state needs a bead id" >&2; exit 1; }
  bead=$(read_bead "$id")
  if [ -z "$bead" ]; then
    echo "$PROG: $id unreadable — cannot answer its state" >&2; exit 2
  fi
  st=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${st#?}' — not a state lifecycle.toml declares" >&2
    exit 1
  }
  printf '%s\n' "$st"
  exit 0
}

# A value-taking flag with no token after it is a malformed invocation, and it
# must refuse: `shift 2` on one remaining argument shifts nothing, so the loop
# below would spin forever, and the empty value it would otherwise take drops
# --expect's compare-and-swap guard. Same refusal, same exit, as the port.
need_value() { # <flag> <rest...>
  [ $# -ge 2 ] || { echo "$PROG: flag $1 needs a value" >&2; exit 1; }
}

cmd_transition() {
  local id="${1:-}"; shift || true
  [ -n "$id" ] || { echo "$PROG: transition needs a bead id" >&2; exit 1; }
  local TO="" EXPECT="" ROUTE="" ROUTE_SET=0 ASSIGNEE="" ASSIGNEE_SET=0
  local CLOSE=0 NOTES="" NOTES_SET=0 JSON=0 TAKEAWAY="" TAKEAWAY_SET=0
  local SETS=() UNSETS=() DATED=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --to)           need_value "$@"; TO="$2"; shift 2 ;;
      --expect)       need_value "$@"; EXPECT="$2"; shift 2 ;;
      --set)          need_value "$@"; SETS+=("$2"); shift 2 ;;
      --set-dated)    need_value "$@"; DATED+=("$2"); shift 2 ;;
      --unset)        need_value "$@"; UNSETS+=("$2"); shift 2 ;;
      --assignee)     need_value "$@"; ASSIGNEE="$2"; ASSIGNEE_SET=1; shift 2 ;;
      --route)        need_value "$@"; ROUTE="$2"; ROUTE_SET=1; shift 2 ;;
      --takeaway)     need_value "$@"; TAKEAWAY="$2"; TAKEAWAY_SET=1; shift 2 ;;
      --close)        CLOSE=1; shift ;;
      --append-notes) need_value "$@"; NOTES="$2"; NOTES_SET=1; shift 2 ;;
      --json)         JSON=1; shift ;;
      *) echo "$PROG: unknown argument '$1'" >&2; exit 1 ;;
    esac
  done
  [ -n "$TO" ] || { echo "$PROG: transition needs --to <state>" >&2; exit 1; }
  is_state "$TO" || { echo "$PROG: '$TO' is not a declared state" >&2; exit 1; }
  # status and merge_result move together: a close on a non-terminal state (or
  # a terminal state left open) is the closed-means-landed violation (I5).
  # `unanchored` is the one exception: lifecycle.toml declares its status
  # "open|closed", so it MAY close (the terminal a non-anchor takes) without
  # being a closed_state that MUST close. This target-level guard permits that
  # close; the current-state guard after the bead read narrows it to a non-anchor
  # current state, so a live anchor cannot close by routing to unanchored.
  if [ "$CLOSE" = 1 ] && ! is_closed_state "$TO" && [ "$TO" != "unanchored" ]; then
    echo "$PROG: --close refused with --to $TO — '$TO' is not a closed state (closed_states: $LIFECYCLE_CLOSED_STATES) and not unanchored; a closed bead on a non-terminal merge_result is invisible to every open-bead consumer" >&2
    exit 1
  fi
  if [ "$CLOSE" = 0 ] && is_closed_state "$TO"; then
    echo "$PROG: --to $TO requires --close — a closed state must close in the same atomic write, or the bead is left open+$TO" >&2
    exit 1
  fi
  # `merged` carries the evidence its own definition names: lifecycle.toml
  # declares [states.merged] meaning = "landed; merged_sha recorded". Require
  # that sha in the same atomic write, so the state cannot be entered with no
  # landing to point at — the closed-implies-landed violation
  # doctor/check-closed-implies-landed reports after the fact, refused here at
  # the write instead. Every sanctioned writer (merge.sh, pr-facts.sh,
  # mol-refinery-patrol) already passes --set merged_sha=<oid>; what this
  # refuses is the bead with no PR that never had one, whose terminal is
  # `--to unanchored --close`, not a false landing.
  if [ "$TO" = "merged" ]; then
    local have_sha="" skv
    for skv in ${SETS[@]+"${SETS[@]}"}; do
      case "$skv" in merged_sha=?*) have_sha=1 ;; esac
    done
    if [ -z "$have_sha" ]; then
      echo "$PROG: --to merged requires --set merged_sha=<oid> — 'merged' means 'landed; merged_sha recorded' (lifecycle.toml), so it cannot be entered without the landing that defines it. A bead with no PR has not landed: close it with '$PROG transition $id --to unanchored --close' (a closed unanchored bead is legal), not --to merged" >&2
      exit 1
    fi
  fi
  # A human state is a bead waiting on a person, so it must name one. An
  # omitted --route takes the default; an EMPTY one is the write that leaves a
  # bead waiting on nobody — no queue holds it and no invariant can name it.
  if is_human_state "$TO"; then
    [ "$ROUTE_SET" = 1 ] || { ROUTE="human"; ROUTE_SET=1; }
    if [ -z "$ROUTE" ]; then
      echo "$PROG: --to $TO requires a route — '$TO' is a human state (human_states: $LIFECYCLE_HUMAN_STATES) and an empty gc.routed_to leaves the bead waiting on nobody" >&2
      exit 1
    fi
  fi
  local kv
  for kv in ${SETS[@]+"${SETS[@]}"} ${DATED[@]+"${DATED[@]}"}; do
    case "${kv%%=*}" in
      merge_result) echo "$PROG: merge_result is written by --to, never by --set" >&2; exit 1 ;;
      gc.routed_to) echo "$PROG: route via --route, never by --set" >&2; exit 1 ;;
      gc.takeaway|gc.takeaway_at|gc.takeaway_by|gc.takeaway_settled)
        echo "$PROG: the takeaway stamp is written by --takeaway, never by --set" >&2; exit 1 ;;
    esac
  done
  # A dated key's ARGUMENT carries the two components its writer decided; this
  # script owns the third. Refusing a malformed one here is what keeps the
  # preserve rule decidable: it compares on value and oid, and cannot find them
  # in a value that does not have exactly those two parts.
  for kv in ${DATED[@]+"${DATED[@]}"}; do
    case "$kv" in
      *=*) : ;;
      *) echo "$PROG: --set-dated '$kv' is not k=<value>@<oid>" >&2; exit 1 ;;
    esac
    local dv="${kv#*=}"
    case "$dv" in
      *@*@*|*@) echo "$PROG: --set-dated '$kv' must carry exactly <value>@<oid>; lifecycle.sh appends the @<since>" >&2; exit 1 ;;
      *@*) : ;;
      *) echo "$PROG: --set-dated '$kv' must carry exactly <value>@<oid>; lifecycle.sh appends the @<since>" >&2; exit 1 ;;
    esac
  done

  # A key written by --set/--set-dated must be named once on the set side and
  # not also unset. The update assembly (below) appends every --set, then the
  # resolved --set-dated, then every --unset, so a key named twice on the set
  # side, or set and unset together, resolves by argument order and the
  # post-write read-back can never verify a value it was told to write twice or
  # to both write and clear. Both shapes reach the closed-with-no-landing (I5)
  # state this transition refuses: `--to merged --set merged_sha=<oid> --set
  # merged_sha=` and `--to merged --set merged_sha=<oid> --unset merged_sha`
  # each satisfy the merged_sha guard above on the first token, then a later
  # empty set or the unset wins. Repeated --unset of one key is idempotent — it
  # lands the same absence in any order — so it stays allowed. Reject the
  # ambiguity before any write rather than leave the bead half-applied.
  local i j uk setkeys=() ki
  for kv in ${SETS[@]+"${SETS[@]}"} ${DATED[@]+"${DATED[@]}"}; do setkeys+=("${kv%%=*}"); done
  for (( i = 0; i < ${#setkeys[@]}; i++ )); do
    ki="${setkeys[i]}"
    for (( j = i + 1; j < ${#setkeys[@]}; j++ )); do
      if [ "$ki" = "${setkeys[j]}" ]; then
        echo "$PROG: '$ki' is set more than once (--set/--set-dated) — the write applies them in order, so the surviving value turns on argument order and the read-back can never verify; set each key once" >&2
        exit 1
      fi
    done
    for uk in ${UNSETS[@]+"${UNSETS[@]}"}; do
      if [ "$ki" = "$uk" ]; then
        echo "$PROG: '$ki' is both set and unset in one call — the write applies --set then --unset, so the result depends on argument order and can never verify; drop one" >&2
        exit 1
      fi
    done
  done

  if [ "$TAKEAWAY_SET" = 1 ]; then
    # Collapse whitespace runs and trim BEFORE the empty check and the cap.
    TAKEAWAY=$(printf '%s' "$TAKEAWAY" | tr -s '[:space:]' ' ')
    TAKEAWAY="${TAKEAWAY# }"; TAKEAWAY="${TAKEAWAY% }"
    # The flag's presence is not a takeaway. Whitespace normalizes to nothing,
    # and an empty one writes the exact row the park guard below refuses: the
    # board renders a person-routed row that carries no takeaway as having no
    # question recorded. gc-helm.sh, the other writer, refuses it here too.
    if [ -z "$TAKEAWAY" ]; then
      echo "$PROG: --takeaway is empty; it renders as the board's NEEDS cell, and a row with an empty one reads as 'routed to you — no question recorded'" >&2
      echo "$PROG: give it the one sentence the operator needs, or drop the flag." >&2
      exit 1
    fi
    # >>> takeaway-length-gate
    # Mirrors gc-helm.sh's gate; lifecycle.test.sh fails on drift. REJECT over
    # the cap, never truncate: only the author knows which clause is the
    # headline. Measured in CODEPOINTS — what both renderers measure — with a
    # shell-count fallback so the gate cannot silently fail open on a broken jq.
    local tlen
    tlen=$(printf '%s' "$TAKEAWAY" | jq -Rsr 'length' 2>/dev/null || true)
    case "$tlen" in ''|*[!0-9]*) tlen=${#TAKEAWAY} ;; esac
    if [ "$tlen" -gt "$LIFECYCLE_TAKEAWAY_MAX" ]; then
      echo "$PROG: --takeaway is $tlen chars; the cap is $LIFECYCLE_TAKEAWAY_MAX" >&2
      echo "$PROG: it renders as the board's NEEDS cell — one line, read at a glance. Cut it to the single sentence the operator needs and put the rest in --append-notes." >&2
      exit 1
    fi
    # <<< takeaway-length-gate
  fi

  local bead cur
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id unreadable — refusing to transition blind" >&2; exit 2; }
  cur=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${cur#?}'; repair it before transitioning" >&2
    exit 1
  }
  if [ -n "$EXPECT" ] && [ "$cur" != "$EXPECT" ]; then
    echo "$PROG: $id is '$cur', not the expected '$EXPECT'; transition refused" >&2
    exit 1
  fi
  if ! edge_legal "$cur" "$TO"; then
    echo "$PROG: illegal edge $cur -> $TO for $id (declared machine: lifecycle/lifecycle.toml)" >&2
    exit 1
  fi
  # --to unanchored --close unsets merge_result AND closes in one write. That is
  # a bead's terminal only from a state that is not a live anchor: `unanchored`
  # (a task that never anchored a PR) or `held` (a sitting whose ruling
  # concluded). Every other state with an edge to unanchored is a live merge
  # anchor the cadence drives, or a PR-derived human state a person must repair
  # and re-engage; the same call would clear its merge_result and close it in one
  # write, dropping it from the open-anchor readers still waiting on it while
  # recording a terminal it never reached (I5). Those reach unanchored by their
  # own edge, which leaves the bead open, and close from there. Keyed on the
  # CURRENT state read off the bead, so an omitted --expect is held to the same
  # rule as a named one.
  if [ "$CLOSE" = 1 ] && [ "$TO" = "unanchored" ] && [ "$cur" != "unanchored" ] && [ "$cur" != "held" ]; then
    echo "$PROG: --close refused: $id is '$cur' — a one-step --to unanchored --close is the terminal only from 'unanchored' or 'held', and '$cur' is a live or human-queued anchor whose merge_result this would clear while closing it, hiding it from every open-anchor reader. Take it to unanchored by its own edge (which leaves it open), then close." >&2
    exit 1
  fi
  # A bead already resting on the park route keeps it. No pool claims that
  # value, and clearing it would retract a bead a person still owns. Setting
  # ROUTE_SET also puts gc.routed_to under the post-write verification below,
  # so a route that fails to clear surfaces as an unverified transition rather
  # than as a silent pool offer. A human state never reaches here: the guard
  # above set ROUTE_SET on arguments alone.
  local cur_route=""
  if [ "$ROUTE_SET" = 0 ] && is_detached_state "$TO"; then
    cur_route=$(printf '%s' "$bead" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    if [ "$cur_route" != "$LIFECYCLE_PARK_ROUTE" ]; then
      ROUTE=""; ROUTE_SET=1
    fi
  fi

  # The unheld half of the same property. An anchor's assignee is the polecat
  # handoff pointer, and mol-refinery-patrol's find-work enumerates by it: a
  # bead carrying a merge_result found in that queue is flagged, never taken,
  # so a survivor sits there for the life of the anchor with nothing converging
  # it. Setting ASSIGNEE_SET puts the clear under the post-write read-back, the
  # same way the route arm does.
  #
  # Only at status=open. That is the status every detached state declares, and
  # it is the term of bd's anti-steal guard that decides whether the edit lands
  # at all: against an in_progress bead the clear is refused and takes the whole
  # atomic update down with it. A live claim there is the retraction this must
  # not perform, and no cadence pass reaches one anyway, because every anchor
  # enumeration is --status=open. An assignee already empty emits no flag, so a
  # healthy transition issues the same bd call it always did.
  local cur_assignee="" cur_status=""
  if [ "$ASSIGNEE_SET" = 0 ] && is_detached_state "$TO"; then
    cur_assignee=$(printf '%s' "$bead" | jq -r '(.assignee // "") | tostring')
    cur_status=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
    if [ -n "$cur_assignee" ] && [ "$cur_status" = "open" ]; then
      ASSIGNEE=""; ASSIGNEE_SET=1
    fi
  fi

  # A park must NAME what is owed. The helm board spends an anchor's
  # gc.takeaway as its NEEDS sentence and, finding none on a row routed to a
  # person, reports that nobody recorded a question — so a route to the park
  # sentinel without a takeaway hands the operator a row it cannot read. The
  # sentence rides the same atomic write as the route; a bead that already
  # carries one satisfies this, which is the sitting that stamped its hold
  # before transitioning. Only the WRITE is guarded: a call that names the park
  # route a bead already rests on establishes no park, so it leaves the question
  # with whoever asked it. Observers do exactly that — gate-ensure.sh and
  # merge.sh pass gc.routed_to back so recording a verdict cannot clear a route
  # they never looked at — and a wedged anchor is the park they most need to
  # record.
  local cur_takeaway="" cur_route=""
  if [ "$ROUTE_SET" = 1 ] && [ "$ROUTE" = "$LIFECYCLE_PARK_ROUTE" ] && [ "$TAKEAWAY_SET" = 0 ]; then
    cur_takeaway=$(printf '%s' "$bead" | jq -r '(.metadata["gc.takeaway"] // "") | tostring')
    cur_route=$(printf '%s' "$bead" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    if [ -z "$cur_takeaway" ] && [ "$cur_route" != "$LIFECYCLE_PARK_ROUTE" ]; then
      echo "$PROG: --route $LIFECYCLE_PARK_ROUTE needs --takeaway \"<text>\" — $id carries no gc.takeaway, and the board renders a person-routed row with an empty takeaway as 'routed to you — no question recorded'" >&2
      exit 1
    fi
  fi

  # Resolve each dated key against the bead already in hand, appending the
  # instant, then let it ride the ordinary --set path: one atomic write, and the
  # post-write verification below checks the whole three-component value.
  local dk dwant dhave
  for kv in ${DATED[@]+"${DATED[@]}"}; do
    dk="${kv%%=*}"; dwant="${kv#*=}"
    dhave=$(printf '%s' "$bead" | jq -r --arg k "$dk" '(.metadata[$k] // "") | tostring')
    SETS+=("$dk=$dwant@$(dated_since "$dhave" "$dwant")")
  done

  # A transition that would change nothing performs no write. The observer arms
  # re-assert a verdict they already recorded on most anchors of every pass, and
  # each re-assertion costs an update plus the read-back that verifies it — two
  # store subprocesses per anchor, on a cadence whose whole budget is store
  # subprocesses. Skipping is safe because the comparison is made against the
  # bead this transition already re-read: matching it is the same evidence the
  # post-write read-back collects, gathered before the write instead of after.
  #
  # Only a pure re-assertion qualifies. --append-notes accumulates, --takeaway
  # stamps a fresh instant, and --close and --assignee move fields this
  # comparison does not cover, so any of them writes unconditionally. The
  # validation above — --expect, edge legality, the park guard — has already run
  # and is not what is being skipped: an illegal edge is still refused, and an
  # edge that is legal but idle is what returns here.
  if [ "$NOTES_SET" = 0 ] && [ "$TAKEAWAY_SET" = 0 ] \
     && [ "$CLOSE" = 0 ] && [ "$ASSIGNEE_SET" = 0 ] && [ "$cur" = "$TO" ]; then
    local idle=1 sk sv got
    for kv in ${SETS[@]+"${SETS[@]}"}; do
      sk="${kv%%=*}"; sv="${kv#*=}"
      got=$(printf '%s' "$bead" | jq -r --arg k "$sk" '(.metadata[$k] // "") | tostring')
      [ "$got" = "$sv" ] || { idle=0; break; }
    done
    if [ "$idle" = 1 ]; then
      for sk in ${UNSETS[@]+"${UNSETS[@]}"}; do
        got=$(printf '%s' "$bead" | jq -r --arg k "$sk" '(.metadata[$k] // "") | tostring')
        [ -z "$got" ] || { idle=0; break; }
      done
    fi
    if [ "$idle" = 1 ] && [ "$ROUTE_SET" = 1 ]; then
      got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
      [ "$got" = "$ROUTE" ] || idle=0
    fi
    if [ "$idle" = 1 ]; then
      if [ "$JSON" = 1 ]; then
        jq -nc --arg id "$id" --arg from "$cur" --arg to "$TO" \
          '{id: $id, from: $from, to: $to, ok: true}'
      else
        echo "$PROG: $id $cur -> $TO"
      fi
      exit 0
    fi
  fi

  local ARGS=()
  if [ "$TO" = "unanchored" ]; then
    ARGS+=(--unset-metadata merge_result)
  else
    ARGS+=(--set-metadata "merge_result=$TO")
  fi
  for kv in ${SETS[@]+"${SETS[@]}"}; do ARGS+=(--set-metadata "$kv"); done
  local k
  for k in ${UNSETS[@]+"${UNSETS[@]}"}; do ARGS+=(--unset-metadata "$k"); done
  [ "$ROUTE_SET" = 1 ] && ARGS+=(--set-metadata "gc.routed_to=$ROUTE")
  local TAKEAWAY_AT=""
  if [ "$TAKEAWAY_SET" = 1 ]; then
    TAKEAWAY_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # gc.takeaway_settled goes empty with every headline this writer stamps.
    # A transition's takeaway names a park or an end, never a subject that
    # settled itself while staying live, and the disposition of the sitting
    # before it must not answer for this one (lifecycle.toml [holds]).
    ARGS+=(--set-metadata "gc.takeaway=$TAKEAWAY"
           --set-metadata "gc.takeaway_at=$TAKEAWAY_AT"
           --set-metadata "gc.takeaway_by=$PROG"
           --set-metadata "gc.takeaway_settled=")
  fi
  [ "$ASSIGNEE_SET" = 1 ] && ARGS+=(--assignee="$ASSIGNEE")
  [ "$CLOSE" = 1 ] && ARGS+=(--status=closed)
  [ "$NOTES_SET" = 1 ] && ARGS+=(--append-notes "$NOTES")

  # ONE atomic write carrying every field of the transition.
  local out rc
  out=$(gc bd update "$id" "${ARGS[@]}" 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "$PROG: $id $cur -> $TO refused by bd (rc=$rc): $out" >&2
    exit 1
  fi

  # Re-read and verify every written field; a write that reported success but
  # did not land must never be reported as a transition.
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id $cur -> $TO written but the read-back failed; UNVERIFIED" >&2; exit 2; }
  local BAD="" got v
  got=$(printf '%s' "$bead" | jq -r '(.metadata.merge_result // "") | tostring')
  if [ "$TO" = "unanchored" ]; then
    [ -z "$got" ] || BAD="$BAD merge_result='$got'(want absent)"
  else
    [ "$got" = "$TO" ] || BAD="$BAD merge_result='$got'(want '$TO')"
  fi
  for kv in ${SETS[@]+"${SETS[@]}"}; do
    k="${kv%%=*}"; v="${kv#*=}"
    got=$(printf '%s' "$bead" | jq -r --arg k "$k" '(.metadata[$k] // "") | tostring')
    [ "$got" = "$v" ] || BAD="$BAD $k='$got'(want '$v')"
  done
  for k in ${UNSETS[@]+"${UNSETS[@]}"}; do
    got=$(printf '%s' "$bead" | jq -r --arg k "$k" '(.metadata[$k] // "") | tostring')
    [ -z "$got" ] || BAD="$BAD $k='$got'(want unset)"
  done
  if [ "$ROUTE_SET" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.routed_to"] // "") | tostring')
    [ "$got" = "$ROUTE" ] || BAD="$BAD gc.routed_to='$got'(want '$ROUTE')"
  fi
  # Every field of the takeaway stamp, not just the text a person reads.
  # The timestamp dates the wait: helm orders the operator's queue by it, and
  # attributes a takeaway to the sitting whose span contains it, dropping one it
  # cannot date. The writer is the provenance readers discriminate on to tell a
  # sitting's decision from a park's own sentence. A stamp that lands in part
  # leaves a headline the board can neither place nor attribute, so it is a
  # failed transition and not a recorded one.
  #
  # The settled-key is verified CLEARED rather than merely written: a
  # transition's takeaway names a park or an end, and a value inherited from an
  # earlier sitting reads as this headline's own disposition, which is what
  # doctor/check-wait-is-an-edge answers from.
  if [ "$TAKEAWAY_SET" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.takeaway"] // "") | tostring')
    [ "$got" = "$TAKEAWAY" ] || BAD="$BAD gc.takeaway='$got'(want '$TAKEAWAY')"
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.takeaway_at"] // "") | tostring')
    [ "$got" = "$TAKEAWAY_AT" ] || BAD="$BAD gc.takeaway_at='$got'(want '$TAKEAWAY_AT')"
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.takeaway_by"] // "") | tostring')
    [ "$got" = "$PROG" ] || BAD="$BAD gc.takeaway_by='$got'(want '$PROG')"
    got=$(printf '%s' "$bead" | jq -r '(.metadata["gc.takeaway_settled"] // "") | tostring')
    [ -z "$got" ] || BAD="$BAD gc.takeaway_settled='$got'(want cleared)"
  fi
  if [ "$ASSIGNEE_SET" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.assignee // "") | tostring')
    [ "$got" = "$ASSIGNEE" ] || BAD="$BAD assignee='$got'(want '$ASSIGNEE')"
  fi
  if [ "$CLOSE" = 1 ]; then
    got=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
    [ "$got" = "closed" ] || BAD="$BAD status='$got'(want closed)"
  fi
  if [ "$NOTES_SET" = 1 ] && [ -n "$NOTES" ]; then
    got=$(printf '%s' "$bead" | jq -r '(.notes // "") | tostring')
    case "$got" in *"$NOTES"*) : ;; *) BAD="$BAD notes(missing appended text)" ;; esac
  fi
  if [ -n "$BAD" ]; then
    echo "$PROG: $id $cur -> $TO wrote but did NOT verify:$BAD" >&2
    exit 2
  fi

  if [ "$JSON" = 1 ]; then
    jq -nc --arg id "$id" --arg from "$cur" --arg to "$TO" \
      '{id: $id, from: $from, to: $to, ok: true}'
  else
    echo "$PROG: $id $cur -> $TO"
  fi
  exit 0
}

cmd_reopen() { # <bead-id> — repair a wrongly-closed bead (closed + non-closed state)
  local id="${1:-}"; shift || true
  [ -n "$id" ] || { echo "$PROG: reopen needs a bead id" >&2; exit 1; }
  [ $# -eq 0 ] || { echo "$PROG: reopen takes no options — it only sets status=open" >&2; exit 1; }
  local bead st status
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id unreadable — refusing to reopen blind" >&2; exit 2; }
  st=$(state_of "$bead") || {
    echo "$PROG: $id carries undeclared merge_result '${st#?}'; repair it before reopening" >&2
    exit 1
  }
  status=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
  if [ "$status" != "closed" ]; then
    echo "$PROG: $id is not closed (status='$status') — nothing to repair" >&2
    exit 1
  fi
  if [ "$st" = "unanchored" ]; then
    echo "$PROG: $id is closed with no merge_result — a closed unanchored bead is legal; reopen refused" >&2
    exit 1
  fi
  if is_closed_state "$st"; then
    echo "$PROG: $id is closed as '$st', a closed state — that close is legitimate; reopen refused" >&2
    exit 1
  fi

  local out rc
  out=$(gc bd update "$id" --status=open 2>&1); rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "$PROG: $id reopen refused by bd (rc=$rc): $out" >&2
    exit 1
  fi
  # Same read-back discipline as transition: verify status flipped and
  # merge_result stayed put before reporting the repair.
  bead=$(read_bead "$id")
  [ -n "$bead" ] || { echo "$PROG: $id reopen written but the read-back failed; UNVERIFIED" >&2; exit 2; }
  local BAD="" got
  got=$(printf '%s' "$bead" | jq -r '(.status // "") | tostring | ascii_downcase')
  [ "$got" = "open" ] || BAD="$BAD status='$got'(want open)"
  got=$(printf '%s' "$bead" | jq -r '(.metadata.merge_result // "") | tostring')
  [ "$got" = "$st" ] || BAD="$BAD merge_result='$got'(want '$st' unchanged)"
  if [ -n "$BAD" ]; then
    echo "$PROG: $id reopen wrote but did NOT verify:$BAD" >&2
    exit 2
  fi
  echo "$PROG: $id reopened — status closed -> open, merge_result '$st' unchanged"
  exit 0
}

case "${1:-}" in
  transition) shift; cmd_transition "$@" ;;
  state)      shift; cmd_state "$@" ;;
  reopen)     shift; cmd_reopen "$@" ;;
  *)
    echo "usage: lifecycle.sh transition <bead-id> --to <state> [--expect <state>] [--set k=v]... [--set-dated k=<value>@<oid>]... [--unset k]... [--assignee <a>] [--route <pool>] [--takeaway <text>] [--close] [--append-notes <text>] [--json]" >&2
    echo "       lifecycle.sh state <bead-id>" >&2
    echo "       lifecycle.sh reopen <bead-id>   # repair a bead closed on a non-closed merge_result" >&2
    exit 1 ;;
esac
