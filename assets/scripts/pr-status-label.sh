#!/usr/bin/env bash
# pr-status-label.sh — the single writer of the workflow-owned `status:` GitHub
# PR label. It projects the human-attention half of the two-signal model onto
# GitHub's PR list, where "Changes requested" is sticky and cannot say whether a
# PR was reworked-and-handed-back or is still in rework. specs/tk-6bji7k.1
# (PR #793) owns the WIP/ready model and the machine axis; this owns the label
# taxonomy and the projection.
#
# The label is one value from a mutually-exclusive `status:` group. Setting one
# value removes any other `status:` value, so future phases are a value addition,
# not a redesign. Seed values: `in-rework`, `ready-for-review`.
#
# The signal is the city's OWN rework state, never GitHub's sticky posture and
# never a commit-agnostic lane marker:
#   in-rework        an open rework child stands on the anchor, or the anchor is
#                    parked by the signoff round cap (merge_hold=signoff_cap)
#   ready-for-review otherwise (born gate-green, reworked-and-handed-back,
#                    awaiting or past a human review)
# A rework child is filed against the reviewed commit and resolved when the fix
# lands, so the flip tracks the reviewed commit rather than a `green` that
# survives a rewrite (the stale-green bug this deliberately does not read). The
# label carries human attention only: machine-readiness/CI stays on pr.machine
# and the future draft flag, and this never asserts a PR may merge.
#
# Every GitHub write is pinned to a repository the caller resolved (--repo), the
# same origin-pinning pr-open.sh and pr-facts.sh already apply; gh-origin-guard.sh
# guards agent-typed gh, not a script's own calls.
#
# Verbs:
#   ensure   --repo Q [--host H]                          create the status: labels if missing
#   derive   --anchor ID                                  print in-rework | ready-for-review
#   set      --pr N --value V --repo Q [--host H] [--current-labels CSV]
#   reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV]
#
# Exit: 0 done (set may be a no-op) · 1 usage/refused · 2 a read did not resolve
# (the caller leaves the label as-is rather than flipping it blind). Not set -e.
set -u

PROG="pr-status-label"
warn() { echo "$PROG: $*" >&2; }

# The controlled `status:` group. One label per value; the prefix groups them on
# the list apart from human triage labels, following Rust `S-`/Kubernetes
# `do-not-merge/`/colon-grouping practice.
LABEL_PREFIX="status: "
STATUS_VALUES="in-rework
ready-for-review"
# One shared colour for the whole group so the values read as one dimension;
# override for a city that wants another. A 6-hex value, no leading '#'.
GROUP_COLOR="${GC_PR_STATUS_LABEL_COLOR:-1D76DB}"

label_desc() { # <value> — the label's GitHub description
  case "$1" in
    in-rework)        printf 'Workflow: the city is reworking this PR (changes requested and not yet handed back).' ;;
    ready-for-review) printf 'Workflow: ready for review — freshly gate-green, or reworked and handed back.' ;;
    *)                printf 'Workflow status label.' ;;
  esac
}

is_status_value() { # <value>
  case "$1" in
    in-rework|ready-for-review) return 0 ;;
    *) return 1 ;;
  esac
}

command -v gh >/dev/null 2>&1 || { warn "gh not found; nothing done"; exit 0; }
command -v jq >/dev/null 2>&1 || { warn "jq not found; nothing done"; exit 0; }

# --- repository identity --------------------------------------------------

# Resolve host/owner-name the way pr-open.sh does, so a self-resolved origin and
# a caller-passed --repo pin the same repository. host is kept: dropping it lets
# another forge with the same owner/name read as ours.
resolve_origin() { # sets ORIGIN_HOST, ORIGIN_REPO, ORIGIN_REPO_Q from --repo or git
  ORIGIN_HOST=""; ORIGIN_REPO=""; ORIGIN_REPO_Q=""
  local q="${1:-}" h="${2:-}"
  if [ -n "$q" ]; then
    # A caller passes host/owner/repo (pr-open's ORIGIN_REPO_Q, signoff's
    # PR_REPO_Q). Accept owner/repo too, completing the host from --host or
    # github.com.
    case "$q" in
      */*/*) ORIGIN_HOST="${q%%/*}"; ORIGIN_REPO="${q#*/}" ;;
      */*)   ORIGIN_HOST="${h:-github.com}"; ORIGIN_REPO="$q" ;;
      *)     warn "unparseable --repo '$q'"; return 1 ;;
    esac
  else
    local u; u=$(git remote get-url origin 2>/dev/null | tr -d '[:space:]')
    case "$u" in
      git@github.com:*|https://github.com/*|ssh://git@github.com/*)
        ORIGIN_HOST="github.com"
        ORIGIN_REPO=$(printf '%s' "$u" | sed -e 's#^ssh://git@github.com/##' \
          -e 's#^git@github.com:##' -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
  fi
  case "$ORIGIN_REPO" in */*/*|/*|*/) ORIGIN_REPO="" ;; */*) : ;; *) ORIGIN_REPO="" ;; esac
  if [ -z "$ORIGIN_HOST" ] || [ -z "$ORIGIN_REPO" ]; then
    warn "cannot resolve the origin repository (repo='$q' host='$h'); nothing done"
    return 1
  fi
  ORIGIN_REPO_Q="$ORIGIN_HOST/$ORIGIN_REPO"
  return 0
}

# --- label existence ------------------------------------------------------

# Create any status: label missing from the repo. Idempotent: reads the label
# list once and creates only what is absent, so a steady state does no write.
# A read that fails is not proof a label is missing, so it creates nothing.
ensure_labels() { # uses ORIGIN_*
  local have rc v name
  have=$(gh label list --repo "$ORIGIN_REPO_Q" --limit 200 --json name -q '.[].name' 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "could not list labels on $ORIGIN_REPO_Q (rc=$rc); not creating any"
    return 2
  fi
  printf '%s\n' "$STATUS_VALUES" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    name="${LABEL_PREFIX}${v}"
    if ! printf '%s\n' "$have" | grep -Fxq "$name"; then
      gh label create "$name" --repo "$ORIGIN_REPO_Q" \
        --color "$GROUP_COLOR" --description "$(label_desc "$v")" >/dev/null 2>&1 \
        || warn "could not create label '$name' on $ORIGIN_REPO_Q"
    fi
  done
  return 0
}

# --- the projection derivation --------------------------------------------

# Print the status value the anchor's state projects to. in-rework when the city
# is reworking (an open rework child, task_kind=rework + anchor_bead=<anchor>) or
# the signoff cap parked the anchor (merge_hold=signoff_cap); ready-for-review
# otherwise. Reads neither GitHub posture (sticky) nor check.<lane>=green
# (commit-agnostic). Exit 2 when a read does not resolve, so a caller does not
# flip the label on a guess.
derive_value() { # <anchor-id>
  local anchor="$1" arow hold kids
  [ -n "$anchor" ] || { warn "derive needs --anchor"; return 1; }
  arow=$(gc bd show "$anchor" --json 2>/dev/null)
  if ! printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    warn "anchor $anchor does not resolve; cannot derive a status"
    return 2
  fi
  hold=$(printf '%s' "$arow" | jq -r '(.[0].metadata.merge_hold // "") | tostring' 2>/dev/null)
  if [ "$hold" = "signoff_cap" ]; then
    printf 'in-rework\n'; return 0
  fi
  # An open rework child stands on the anchor. metadata-field selection lists
  # non-closed by default; the explicit --status keeps it robust if that default
  # changes. Repeated --status flags drop earlier values, so it is one list.
  kids=$(gc bd list --metadata-field task_kind=rework --metadata-field "anchor_bead=$anchor" \
    --status open,in_progress,blocked --limit 0 --json 2>/dev/null)
  if ! printf '%s' "$kids" | jq -e 'type == "array"' >/dev/null 2>&1; then
    warn "could not read rework children for $anchor; cannot derive a status"
    return 2
  fi
  if [ "$(printf '%s' "$kids" | jq 'length' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
    printf 'in-rework\n'; return 0
  fi
  printf 'ready-for-review\n'; return 0
}

# --- setting the label ----------------------------------------------------

# Set the target status value on a PR, mutually exclusive: add the target and
# remove every OTHER status: label present. A no-op when the target is already
# the only status: label. Reads the PR's current labels (--current-labels lets a
# caller that already has them skip the read). A read that does not resolve
# leaves the label untouched rather than adding blind.
set_label() { # <pr-number> <value> [<current-labels-csv or newline>]
  local num="$1" value="$2" provided="${3:-}"
  [ -n "$num" ] || { warn "set needs --pr"; return 1; }
  is_status_value "$value" || { warn "set --value must be one of: $(printf '%s' "$STATUS_VALUES" | paste -sd'|' -) (got '$value')"; return 1; }
  local target="${LABEL_PREFIX}${value}" cur rc
  if [ -n "$provided" ]; then
    cur=$(printf '%s' "$provided" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d')
  else
    cur=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json labels -q '.labels[].name' 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "could not read PR#$num labels on $ORIGIN_REPO_Q (rc=$rc); label left unchanged"
      return 2
    fi
  fi
  # Every status: label currently present, and those other than the target.
  # Anchor the prefix so a label that merely contains "status: " mid-name is
  # never mistaken for one of ours.
  local present_status others has_target=""
  present_status=$(printf '%s\n' "$cur" | grep "^${LABEL_PREFIX}" || true)
  printf '%s\n' "$present_status" | grep -Fxq "$target" && has_target=1
  others=$(printf '%s\n' "$present_status" | grep -Fxv "$target" | sed '/^$/d')
  # No-op: the target is already the only status: label.
  if [ -n "$has_target" ] && [ -z "$others" ]; then
    return 0
  fi
  ensure_labels
  local args=(pr edit "$num" --repo "$ORIGIN_REPO_Q")
  [ -n "$has_target" ] || args+=(--add-label "$target")
  local rm; rm=$(printf '%s' "$others" | paste -sd, -)
  [ -n "$rm" ] && args+=(--remove-label "$rm")
  if ! gh "${args[@]}" >/dev/null 2>&1; then
    warn "could not set '$target' on PR#$num (removing '${rm}'); the reconcile retries next pass"
    return 2
  fi
  return 0
}

# --- argv -----------------------------------------------------------------

VERB="${1:-}"; [ -n "$VERB" ] && shift
ANCHOR=""; PR=""; VALUE=""; REPO=""; HOST=""; CURRENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)          ANCHOR="${2:-}"; shift 2 || exit 1 ;;
    --pr)              PR="${2:-}"; shift 2 || exit 1 ;;
    --value)           VALUE="${2:-}"; shift 2 || exit 1 ;;
    --repo)            REPO="${2:-}"; shift 2 || exit 1 ;;
    --host)            HOST="${2:-}"; shift 2 || exit 1 ;;
    --current-labels)  CURRENT="${2:-}"; shift 2 || exit 1 ;;
    *) warn "unknown argument '$1'"; exit 1 ;;
  esac
done

case "$VERB" in
  ensure)
    resolve_origin "$REPO" "$HOST" || exit 2
    ensure_labels; exit $? ;;
  derive)
    derive_value "$ANCHOR"; exit $? ;;
  set)
    resolve_origin "$REPO" "$HOST" || exit 2
    set_label "$PR" "$VALUE" "$CURRENT"; exit $? ;;
  reconcile)
    resolve_origin "$REPO" "$HOST" || exit 2
    V=$(derive_value "$ANCHOR"); dr=$?
    if [ "$dr" -ne 0 ] || [ -z "$V" ]; then
      # Could not determine the state; leave the label as it is.
      exit "$dr"
    fi
    set_label "$PR" "$V" "$CURRENT"; exit $? ;;
  ''|-h|--help|help)
    cat >&2 <<'USAGE'
usage: pr-status-label.sh <verb> [options]
  ensure    --repo Q [--host H]
  derive    --anchor ID
  set       --pr N --value in-rework|ready-for-review --repo Q [--host H] [--current-labels CSV]
  reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV]
USAGE
    [ -n "$VERB" ] && exit 0 || exit 1 ;;
  *) warn "unknown verb '$VERB'"; exit 1 ;;
esac
