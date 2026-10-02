#!/usr/bin/env bash
# approval-drift.sh — decide whether a lane's standing approval still covers the
# change in front of it. The drift counterpart to lane-state.sh: gate-ensure
# consults it at the same point it asks whether a lane derives green, and
# merge.sh rides the review it selects. A human approval survives the ordinary
# commits that follow it — that is the right default and the overwhelming path.
# This names the two narrow cases where it should not, and leaves everything
# else standing.
#
#   approval-drift.sh classify --anchor <id> --lane <lane> [--head <sha>] [--base <ref>]
#   approval-drift.sh scope-digest --anchor <id>
#
# classify answers one of three words on stdout for a lane that would otherwise
# read green:
#
#   stands  the approved baseline still applies; green is settled, nothing owed.
#   scope   the bead's scope-bearing content (title + authored description) no
#           longer matches what was approved — a workflow rewrote the
#           requirements the review read. The response is a fresh review of the
#           change's own lane.
#   arch    the change since the approved commit grew beyond the reviewed
#           envelope: it touches a top-level path absent from the reviewed file
#           set, or (when a magnitude factor is configured) exceeds the reviewed
#           envelope's size by that factor. The response is a human approval at
#           the drifted head.
#
# The baseline two facts, each bound to one lane and written on the anchor by
# whichever writer records a fresh approval (signoff.sh for a city verdict,
# pr-facts.sh for an external GitHub approval):
#
#   approved_oid.<lane>            the commit the approval stands on.
#   approved_scope_digest.<lane>   the scope digest at that moment.
#
# A lane with no recorded baseline has no drift by definition — approved before
# this shipped, or never approved — so classify answers stands and the baseline
# is captured the next time a fresh approval lands.
#
# Fail toward stands. Both inputs are local (the bead and the branch), so an
# unreadable read is rare; and this is a net-new trigger layered over the
# existing gates, so a read it cannot complete must not manufacture a re-review.
# This is the opposite of merge.sh's fail-closed direction, and it is
# deliberate: the safe default here is the standing approval, which the lane
# green and the merge posture already guard. classify therefore always prints a
# word and exits 0; only a usage error exits non-zero.
#
# scope-digest prints the current scope digest (title + authored description,
# whitespace-normalized) so the approval writers capture exactly what classify
# later compares. The bead's appended notes live in a separate field and are
# excluded on purpose: dispatch notes, breadcrumbs, and routing diagnosis are
# operational churn, not scope.
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }
warn() { echo "approval-drift: $*" >&2; }

usage() {
  echo "usage: approval-drift.sh classify --anchor <id> --lane <lane> [--head <sha>] [--base <ref>]" >&2
  echo "       approval-drift.sh scope-digest --anchor <id>" >&2
}

# The one place the digest is computed, so the writer and the reader agree. A
# divergent copy would capture one string and compare another, and every lane
# would read scope-drifted forever.
scope_digest_of() { # <anchor-id> -> 12-hex digest on stdout, or empty + rc 1
  local arow title desc
  arow=$(bd_json show "$1")
  printf '%s' "$arow" | jq -e '.[0].id // empty' >/dev/null 2>&1 || return 1
  title=$(printf '%s' "$arow" | jq -r '.[0].title // ""' 2>/dev/null) || return 1
  desc=$(printf '%s' "$arow" | jq -r '.[0].description // ""' 2>/dev/null) || return 1
  printf '%s\037%s' "$title" "$desc" | tr '\n\t' '  ' | tr -s ' ' | sed 's/^ //; s/ $//' | sha256sum | cut -c1-12
}

# Resolve a ref or raw oid to a commit sha, trying the bare form (a stored oid)
# and the origin-qualified forms (a branch name). Empty + rc 1 when unresolvable.
resolve_commit() { # <ref-or-oid> -> sha or empty(rc 1)
  local r sha
  for r in "$1" "origin/$1" "refs/remotes/origin/$1"; do
    sha=$(git rev-parse --verify --quiet "${r}^{commit}" 2>/dev/null) && { printf '%s' "$sha"; return 0; }
  done
  return 1
}

# True (rc 0) when base...head grows beyond base...approved by structural
# surface. The reviewed envelope is base...approved; the live change is
# base...head. Ordinary change clears it: a rebase reproduces the reviewed net
# diff, and a fixup edits files already in the reviewed set. Unreadable inputs
# return 1 (no arch), so the caller falls through to the scope check rather than
# reading arch into a range it could not compute.
arch_paths_drift() { # <base-sha> <approved-sha> <head-sha>
  local basec="$1" approvedc="$2" headc="$3" reviewed live newpaths
  [ -n "$basec" ] && [ -n "$approvedc" ] && [ -n "$headc" ] || return 1
  # Nothing has happened since approval.
  [ "$headc" = "$approvedc" ] && return 1
  reviewed=$(git diff --name-only "$basec...$approvedc" 2>/dev/null | awk -F/ 'NF{print $1}' | sort -u) || return 1
  live=$(git diff --name-only "$basec...$headc" 2>/dev/null | awk -F/ 'NF{print $1}' | sort -u) || return 1
  # A top-level path in the live change absent from the reviewed one is new
  # structural surface the reviewer never read.
  newpaths=$(comm -13 <(printf '%s\n' "$reviewed") <(printf '%s\n' "$live") | sed '/^$/d')
  [ -n "$newpaths" ] && return 0
  # The magnitude factor is off unless configured — the design ships on the path
  # signal first. When set, the live change tripping more than <factor>x the
  # reviewed envelope's changed-line count is arch too.
  local factor="${APPROVAL_DRIFT_ARCH_MAGNITUDE_FACTOR:-}"
  if [ -n "$factor" ]; then
    local rl ll
    rl=$(git diff --numstat "$basec...$approvedc" 2>/dev/null | awk '{a+=$1; d+=$2} END{print a+d+0}') || return 1
    ll=$(git diff --numstat "$basec...$headc" 2>/dev/null | awk '{a+=$1; d+=$2} END{print a+d+0}') || return 1
    awk -v l="$ll" -v r="$rl" -v f="$factor" 'BEGIN{exit !(r>0 && l > r*f)}' && return 0
  fi
  return 1
}

cmd_classify() {
  local anchor="" lane="" head_arg="" base_arg=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --lane)   lane="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --head)   head_arg="${2:-}"; shift 2 || { usage; exit 2; } ;;
    --base)   base_arg="${2:-}"; shift 2 || { usage; exit 2; } ;;
    *) warn "unknown arg '$1'"; usage; exit 2 ;;
  esac; done
  [ -n "$anchor" ] || { warn "classify needs --anchor"; usage; exit 2; }
  [ -n "$lane" ] || lane="codex"

  # An unreadable anchor is not drift — fall to the standing approval.
  local arow
  arow=$(bd_json show "$anchor")
  printf '%s' "$arow" | jq -e '.[0].id // empty' >/dev/null 2>&1 || { echo stands; return 0; }

  local approved_oid approved_digest
  approved_oid=$(printf '%s' "$arow" | jq -r --arg l "$lane" '.[0].metadata["approved_oid." + $l] // ""' 2>/dev/null)
  approved_digest=$(printf '%s' "$arow" | jq -r --arg l "$lane" '.[0].metadata["approved_scope_digest." + $l] // ""' 2>/dev/null)
  # No baseline on this lane: nothing was captured, so nothing can have drifted.
  [ -z "$approved_oid" ] && [ -z "$approved_digest" ] && { echo stands; return 0; }

  # Architecture first — the stronger response subsumes a scope re-read. Resolve
  # the three commits, fetching once if a ref is missing; an unresolved range is
  # no-arch, not stands-overall, so a scope rewrite is still caught below.
  if [ -n "$approved_oid" ]; then
    local branch target headref basec approvedc headc
    branch=$(printf '%s' "$arow" | jq -r '.[0].metadata.branch // ""' 2>/dev/null)
    target="$base_arg"
    [ -n "$target" ] || target=$(printf '%s' "$arow" | jq -r '.[0].metadata.merged_target // .[0].metadata.target // "main"' 2>/dev/null)
    headref="$head_arg"
    [ -n "$headref" ] || headref="$branch"
    basec=$(resolve_commit "$target" || true)
    approvedc=$(resolve_commit "$approved_oid" || true)
    headc=$(resolve_commit "$headref" || true)
    if [ -z "$basec" ] || [ -z "$approvedc" ] || [ -z "$headc" ]; then
      git fetch --quiet origin "$target" ${branch:+"$branch"} 2>/dev/null || true
      basec=$(resolve_commit "$target" || true)
      approvedc=$(resolve_commit "$approved_oid" || true)
      headc=$(resolve_commit "$headref" || true)
    fi
    if arch_paths_drift "$basec" "$approvedc" "$headc"; then echo arch; return 0; fi
  fi

  # Scope: the current scope digest differs from the one captured at approval.
  if [ -n "$approved_digest" ]; then
    local cur
    cur=$(scope_digest_of "$anchor" || true)
    if [ -n "$cur" ] && [ "$cur" != "$approved_digest" ]; then echo scope; return 0; fi
  fi

  echo stands
  return 0
}

cmd_scope_digest() {
  local anchor=""
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 2; } ;;
    *) warn "unknown arg '$1'"; usage; exit 2 ;;
  esac; done
  [ -n "$anchor" ] || { warn "scope-digest needs --anchor"; usage; exit 2; }
  local d
  d=$(scope_digest_of "$anchor") || { warn "could not read scope of $anchor"; return 1; }
  printf '%s\n' "$d"
}

[ $# -ge 1 ] || { usage; exit 2; }
VERB="$1"; shift
case "$VERB" in
  classify)     cmd_classify "$@" ;;
  scope-digest) cmd_scope_digest "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 2 ;;
esac
