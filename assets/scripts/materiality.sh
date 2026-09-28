#!/usr/bin/env bash
# materiality.sh — does a standing human approval still cover the live head?
#
# A human GitHub APPROVED review persists across pushes: the city never dismisses
# it (signoff.sh dismisses only its own machine CHANGES_REQUESTED) and GitHub's
# dismiss-stale-on-push is off and stays off. So a moved head does not by itself
# unapprove a pull request. Treating every new commit as stale re-reviews a pure
# rebase and every trivial fixup, which is not what an approval means; the rule is
# materiality: the sign-off stands across a change that does not alter the
# reviewed diff in substance, and a re-review is owed only when the change since
# the approval is material. The approved commit is the diff base for that
# judgment, never a binding on the review's validity (specs/tk-6bji7k.1).
#
#   materiality.sh classify --anchor <id> [--approved-oid <oid>] [--head <oid>]
#   materiality.sh record   --anchor <id> --verdict stands|owed
#                           [--approved-oid <oid>] [--head <oid>]
#
# classify prints one word, which the merge gate reads:
#   none        no standing human APPROVED review on the pull request at all.
#   at-head     the approval was given at the live head; trivially covered.
#   immaterial  the head adds no file change over the approved commit (an empty
#               or no-op rewrite): the reviewed content is unchanged, so the
#               sign-off stands. The one case decided without a judgment.
#   stands      an agent judged the change since the approval immaterial and
#               recorded it for this exact head.
#   owed        an agent judged the change material, or none has judged a content
#               change: a re-review is owed before the standing approval merges.
# at-head, immaterial and stands cover the head; owed and a `none` on an armed
# gate hold. The merge gate treats a non-zero exit (a read that did not resolve)
# as owed, never as covered.
#
# record is the agent's semantic verdict and the only writer of
# approval_materiality. It is an issued verdict, never a cadence auto-promotion:
# no reconcile pass calls it, so the merge cadence gains no second writer of a
# review verdict (specs/tk-w26b6/stale-gate-re-dispatch.md rules that a
# materiality skip belongs in a verdict an agent issues, not in the cadence). The
# verdict binds to the head it judged: a commit past the recorded head is
# unjudged, so classify reads `stands` only when the live approved oid and head
# both match the recorded pair, and any later head falls back to a fresh
# judgment.
#
# The human approval itself is never written or dismissed here; it is external
# evidence the city reads.
#
# Exit: 0 done (classify prints the word) · 1 refused (bad args) · 2 a read did
#       not resolve (the merge gate treats that as owed, never as covered).
set -uo pipefail

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
bd_json() { gc bd "$@" --json 2>/dev/null | scrub; }
warn() { echo "materiality: $*" >&2; }

usage() {
  cat >&2 <<'U'
usage: materiality.sh classify --anchor <id> [--approved-oid <oid>] [--head <oid>]
       materiality.sh record   --anchor <id> --verdict stands|owed
                               [--approved-oid <oid>] [--head <oid>]
U
}

# The repository behind the anchor's origin remote, as host-qualified owner/repo,
# echoed on stdout. Fail-closed: any unparseable remote returns non-zero.
origin_slug() {
  local u slug
  u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
  case "$u" in
    git@github.com:*|https://github.com/*|ssh://git@github.com/*)
      slug=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
        -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    *) return 1 ;;
  esac
  case "$slug" in */*/*|/*|*/) return 1 ;; */*) : ;; *) return 1 ;; esac
  printf '%s' "$slug"
}

# The commit of the most recent standing APPROVED review by a non-city account on
# <pr> — the same row merge.sh's approval reducer weighs, so a verdict record
# writes keys on the base the merge gate reads back — echoed on stdout; empty
# (exit 0) when there is no standing approval; non-zero when the reviews history
# could not be read. The city never posts an APPROVED review (signoff.sh posts
# --comment), so an APPROVED is a human's; a per-reviewer latest-row reduction
# lets a later CHANGES_REQUESTED or DISMISSED by the same account retract an
# earlier approval, and among the survivors the most recent APPROVED is the one
# the merge leans on.
approved_oid_of() { # <slug> <pr>
  local slug="$1" pr="$2" body
  command -v gh >/dev/null 2>&1 || return 1
  body=$(gh api "repos/$slug/pulls/$pr/reviews?per_page=100" --paginate 2>/dev/null) || return 1
  [ -n "$body" ] || return 1
  printf '%s' "$body" | scrub | jq -sr '
    [ .[][]? | select((.state // "") == "APPROVED" or (.state // "") == "CHANGES_REQUESTED" or (.state // "") == "DISMISSED") ]
    | group_by(.user.login // "") | map(sort_by((.submitted_at // ""), (.id // 0)) | last)
    | [ .[] | select((.state // "") == "APPROVED") ] | sort_by(.submitted_at // "") | last | (.commit_id // "")' 2>/dev/null
}

# The live head of <pr>, echoed on stdout; non-zero when it could not be read.
# Read the way merge.sh reads it — the PR's own headRefOid — so the two never
# disagree about which commit the approval is being weighed against.
head_of() { # <slug> <pr>
  local slug="$1" pr="$2" h
  command -v gh >/dev/null 2>&1 || return 1
  h=$(gh pr view "$pr" --repo "$slug" --json headRefOid -q .headRefOid 2>/dev/null) || return 1
  [ -n "$h" ] || return 1
  printf '%s' "$h"
}

# Whether the head introduces no file change over the approved commit — the
# reviewed content is byte-identical. Uses the compare API's three-dot file set
# (the diff from merge-base(approved, head) to head): empty means the head added
# nothing the approval did not already carry. Fail-closed: an unreadable compare
# is not "immaterial". Echoes `yes` or `no`; non-zero when it could not be read.
head_adds_nothing() { # <slug> <approved_oid> <head>
  local slug="$1" a="$2" h="$3" n
  command -v gh >/dev/null 2>&1 || return 1
  n=$(gh api "repos/$slug/compare/$a...$h" --jq '(.files // []) | length' 2>/dev/null) || return 1
  case "$n" in ''|*[!0-9]*) return 1 ;; esac
  [ "$n" -eq 0 ] && printf 'yes' || printf 'no'
}

# The recorded verdict for the current (approved_oid, head) pair, or empty when
# none matches. approval_materiality is `<stands|owed>@<approved_oid>..<head>`; a
# verdict for a different head is stale and read as no verdict.
recorded_verdict() { # <anchor> <approved_oid> <head>
  local anchor="$1" a="$2" h="$3" marker verb pair ra rh
  marker=$(bd_json show "$anchor" | jq -r '(.[0].metadata.approval_materiality // "") | tostring' 2>/dev/null)
  [ -n "$marker" ] || return 0
  verb="${marker%%@*}"; pair="${marker#*@}"
  ra="${pair%%..*}"; rh="${pair##*..}"
  [ "$ra" = "$a" ] && [ "$rh" = "$h" ] || return 0
  case "$verb" in stands|owed) printf '%s' "$verb" ;; esac
}

cmd_classify() {
  local anchor="" approved_oid="" head="" arow pr slug
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --approved-oid) approved_oid="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --head) head="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "classify needs --anchor"; usage; exit 1; }

  arow=$(bd_json show "$anchor")
  printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { warn "anchor $anchor does not resolve"; return 2; }
  pr=$(printf '%s' "$arow" | jq -r '(.[0].metadata.pr_number // "") | tostring' 2>/dev/null)
  case "$pr" in ''|*[!0-9]*) echo none; return 0 ;; esac
  slug=$(origin_slug) || { warn "origin remote is not a readable github repo"; return 2; }

  if [ -z "$approved_oid" ]; then
    approved_oid=$(approved_oid_of "$slug" "$pr") || { warn "PR#$pr reviews history unreadable"; return 2; }
  fi
  [ -n "$approved_oid" ] || { echo none; return 0; }

  if [ -z "$head" ]; then
    head=$(head_of "$slug" "$pr") || { warn "PR#$pr live head unreadable"; return 2; }
  fi

  [ "$approved_oid" = "$head" ] && { echo at-head; return 0; }

  # An agent's recorded judgment for this exact head wins over the mechanical
  # read: it is the semantic call the mechanical one cannot make.
  local rec; rec=$(recorded_verdict "$anchor" "$approved_oid" "$head")
  case "$rec" in
    stands) echo stands; return 0 ;;
    owed)   echo owed;   return 0 ;;
  esac

  local adds; adds=$(head_adds_nothing "$slug" "$approved_oid" "$head") \
    || { warn "PR#$pr compare $approved_oid...$head unreadable"; return 2; }
  [ "$adds" = "yes" ] && { echo immaterial; return 0; }

  # A content change since the approval that no agent has judged immaterial: a
  # re-review is owed before the standing approval may merge.
  echo owed
}

cmd_record() {
  local anchor="" verdict="" approved_oid="" head="" arow pr slug got want
  while [ $# -gt 0 ]; do case "$1" in
    --anchor) anchor="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --verdict) verdict="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --approved-oid) approved_oid="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --head) head="${2:-}"; shift 2 || { usage; exit 1; } ;;
    *) warn "unknown arg '$1'"; usage; exit 1 ;;
  esac; done
  [ -n "$anchor" ] || { warn "record needs --anchor"; usage; exit 1; }
  case "$verdict" in
    stands|owed) ;;
    *) warn "--verdict must be stands or owed (got '$verdict')"; usage; exit 1 ;;
  esac

  arow=$(bd_json show "$anchor")
  printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { warn "anchor $anchor does not resolve; nothing written"; return 2; }
  pr=$(printf '%s' "$arow" | jq -r '(.[0].metadata.pr_number // "") | tostring' 2>/dev/null)
  case "$pr" in ''|*[!0-9]*) warn "anchor $anchor names no PR; a materiality verdict has nothing to cover"; return 1 ;; esac
  slug=$(origin_slug) || { warn "origin remote is not a readable github repo"; return 2; }

  if [ -z "$approved_oid" ]; then
    approved_oid=$(approved_oid_of "$slug" "$pr") || { warn "PR#$pr reviews history unreadable; nothing written"; return 2; }
  fi
  [ -n "$approved_oid" ] || { warn "PR#$pr carries no standing approval; a materiality verdict has nothing to cover"; return 1; }
  if [ -z "$head" ]; then
    head=$(head_of "$slug" "$pr") || { warn "PR#$pr live head unreadable; nothing written"; return 2; }
  fi

  want="$verdict@$approved_oid..$head"
  gc bd update "$anchor" --set-metadata "approval_materiality=$want" >/dev/null 2>&1 || true
  got=$(bd_json show "$anchor" | jq -r '(.[0].metadata.approval_materiality // "") | tostring' 2>/dev/null)
  if [ "$got" != "$want" ]; then
    warn "approval_materiality did not read back on $anchor (got '${got:-}', want '$want')"
    return 2
  fi
  echo "$want"
}

[ $# -ge 1 ] || { usage; exit 1; }
VERB="$1"; shift
case "$VERB" in
  classify) cmd_classify "$@" ;;
  record)   cmd_record "$@" ;;
  *) warn "unknown verb '$VERB'"; usage; exit 1 ;;
esac
