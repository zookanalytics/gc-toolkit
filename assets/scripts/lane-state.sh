#!/usr/bin/env bash
# lane-state.sh — derive a review lane's GREEN state from the finding and
# review-outcome graph, never from a stored check.<lane> marker.
#
# A lane is one reviewer, named by one check_set member. `green` is a state of
# the lane, not a claim about a commit: a push creates and closes no bead in the
# set this reads, so it does not move a lane out of green. This is the one shared
# helper the merge predicate, pr-open, the liveness sweep and the board are meant
# to ask, so every reader derives green the same way.
#
#   lane-state.sh green --anchor <id> --lane <lane> [--no-remote]
#
# green(anchor, lane) holds when a closed review bead backs the lane and no
# review for the lane is in flight:
#
#   backing   a closed task_kind=review bead whose anchor_bead is this anchor and
#             whose check_name is this lane (absent check_name resolves to codex)
#             carries signoff_verdict=approve and is not superseded (gc.outcome is
#             not superseded); OR, for a legacy bead written before the verdict
#             stamp, carries no signoff_verdict with gc.outcome=recorded; OR the
#             anchor's pr_number has an APPROVED GitHub review (an approval names
#             no gate, so it backs every lane).
#   in flight an open review bead for this lane holds the lane out of green — the
#             precedence that keeps green from co-existing with a live review.
#
# The non-superseded clause is what this adds over doctor/check-gate-marker-
# provenance's resolver: the validator supersedes an approve bead to send a lane
# back to unreviewed (stamping gc.outcome=superseded), so a superseded approve
# must stop backing the lane. The legacy branch needs no such clause — a
# supersede stamp removes the gc.outcome=recorded it requires.
#
# Two conditions the full derivation names are deliberately NOT read here: an
# open must-fix finding (anchor-wide, subsumed by the merge predicate's own
# blocker probe) and an open validation pass (the validator owns that bead).
# Each reader adds those where the design assigns them.
#
# Exit 0 green, 1 not green, 2 the store would not read (a merge predicate must
# treat that as not green, never as green by default).
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload. All but
# LF go: raw TAB and CR do not occur in bd/gh output, and the TAB-splitting
# consumers downstream split jq's own @tsv, emitted after this runs.
scrub() { tr -d '\000-\011\013-\037'; }
# <<< control-char-scrub
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }
warn() { echo "lane-state: $*" >&2; }

ALL_STATUSES="open,in_progress,blocked,deferred,hooked,pinned,closed"

usage() { echo "usage: lane-state.sh green --anchor <id> --lane <lane> [--no-remote]" >&2; }

# An APPROVED GitHub review on the anchor's PR backs every lane. Consulted only
# when no local review bead backs the lane, and fail-closed: any step that
# cannot be completed returns 1 (not green), never 0.
github_approved() {
  local anchor="$1" arow pr slug u body
  arow=$(bd_json show "$anchor")
  pr=$(printf '%s' "$arow" | jq -r '(.[0].metadata.pr_number // "") | tostring' 2>/dev/null)
  [ -n "$pr" ] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
  case "$u" in
    git@github.com:*|https://github.com/*|ssh://git@github.com/*)
      slug=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
        -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    *) return 1 ;;
  esac
  case "$slug" in */*/*|/*|*/) return 1 ;; */*) : ;; *) return 1 ;; esac
  body=$(gh api "repos/$slug/pulls/$pr/reviews?per_page=100" --paginate 2>/dev/null) || return 1
  [ -n "$body" ] || return 1
  [ "$(printf '%s' "$body" | scrub | jq -sr '[ .[][]? | select(((.state // "") | tostring) == "APPROVED") ] | length > 0' 2>/dev/null)" = "true" ]
}

cmd_green() {
  local anchor="" lane="" no_remote=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --lane) lane="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --no-remote) no_remote=1; shift ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] && [ -n "$lane" ] || { warn "green needs --anchor and --lane"; exit 1; }

  # Read live AND closed review beads: an open one must be SEEN to exclude the
  # lane, and a closed one is the backing — a status filter that skipped either
  # would derive green from an absence.
  local rows
  rows=$(gc bd list --metadata-field anchor_bead="$anchor" --status="$ALL_STATUSES" --limit=0 --json 2>/dev/null | scrub)
  printf '%s' "$rows" | jq -e 'type == "array"' >/dev/null 2>&1 \
    || { warn "could not read review beads on $anchor"; return 2; }

  # An open review for this lane holds it out of green whatever else is true.
  local inflight
  inflight=$(printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | select(((.metadata.task_kind // "") | tostring) == "review")
          | select((((.metadata.check_name // "") | tostring) | if . == "" then "codex" else . end) == $lane)
          | select(((.status // "") | tostring | ascii_downcase) != "closed") ]
    | length > 0' 2>/dev/null)
  [ "$inflight" = "true" ] && return 1

  local backed
  backed=$(printf '%s' "$rows" | jq -r --arg lane "$lane" '
    [ .[] | (.metadata // {}) as $m
          | select(((($m.task_kind // "") | tostring)) == "review")
          | select(((($m.check_name // "") | tostring) | if . == "" then "codex" else . end) == $lane)
          | select(((.status // "") | tostring | ascii_downcase) == "closed")
          | (($m.signoff_verdict // "") | tostring) as $sv
          | ((($m["gc.outcome"] // "") | tostring)) as $oc
          | select(($sv == "approve" and $oc != "superseded") or ($sv == "" and $oc == "recorded")) ]
    | length > 0' 2>/dev/null)
  [ "$backed" = "true" ] && return 0

  # No local backing. An operator's GitHub approval is the last way the approve
  # half is met; absent that, or when it cannot be confirmed, the lane is not
  # green.
  [ -n "$no_remote" ] && return 1
  github_approved "$anchor" && return 0
  return 1
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  green) cmd_green "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
