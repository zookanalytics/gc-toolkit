#!/usr/bin/env bash
# pr-status-label.sh — the single writer of the workflow-owned `status:` and
# `held:` GitHub PR labels. They project the city's own state onto GitHub's pull
# request list, where that state is otherwise invisible until you open the PR.
# `status:` says whose move it is: the city is changing an unapproved PR
# (working), the city is landing an approved one (merging), only a human's
# review verdict is left (needs-review), or a blocker stands that the city will
# not clear on its own (needs-attention). An open PR carries exactly one status
# value. `held:` names what holds it that the city will not clear on its own: an
# open visit on the PR or its work (visit), an unresolved review thread the
# merge waits on (review), or a blocker no automated actor will clear (blocked).
# Each is a label of its own, so more than one can stand, and a PR nothing holds
# carries none. Any held value reads needs-attention. pr-facts.sh's full pass
# recomputes both for each open PR its paced walk reaches, from the anchor's
# posture, holds, open visits, blockers, the merge cadence's verdict, draft
# stage and live work. Both come off once the PR merges or closes, where
# GitHub's own Merged or Closed state takes over: pr-facts.sh clears them when it
# records a merge or a close, and gctk merge when it merges, each before its
# record. A clear that does not land is recorded on the anchor as
# status_label_clear_owed, and pr-facts.sh's full pass retries it. They are
# workflow state, never an approval, and never assert a PR may merge:
# machine-readiness rides pr.machine and the draft flag. The values themselves —
# what each projects from, and their precedence — are decided by one Go package,
# services/gctk/prstatus, reached through `gctk pr-status derive` and exported so
# the helm board derives the same per-bead state, so a bead's PR labels and its
# board liveness cannot disagree.
#
# Every GitHub write is pinned to a repository the caller resolved (--repo), the
# same origin-pinning pr-open.sh and pr-facts.sh already apply; gh-origin-guard.sh
# guards agent-typed gh, not a script's own calls.
#
# Verbs:
#   ensure    --repo Q [--host H]                         create the status: and held: labels, or correct a description
#   derive    --anchor ID                                 print working | merging | needs-review | needs-attention
#   set       --pr N --value V --repo Q [--host H] [--current-labels CSV]   the status: value alone
#   reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV] derive both families and write them
#   clear     --pr N --repo Q [--host H] [--current-labels CSV]   take every status: and held: label off
#
# Exit: 0 done (set and clear may be no-ops) · 1 usage/refused · 2 a read did not
# resolve (the caller leaves the label as-is rather than flipping it blind). Not
# set -e.
set -u

PROG="pr-status-label"
warn() { echo "$PROG: $*" >&2; }

# The controlled `status:` group. One label per value; the prefix groups them on
# the list apart from human triage labels, following Rust `S-`/Kubernetes
# `do-not-merge/`/colon-grouping practice.
LABEL_PREFIX="status: "
STATUS_VALUES="working
merging
needs-review
needs-attention"
# One shared colour for the whole group so the values read as one dimension;
# override for a city that wants another. A 6-hex value, no leading '#'.
GROUP_COLOR="${GC_PR_STATUS_LABEL_COLOR:-1D76DB}"
# The controlled `held:` group, the values prstatus.Held names, with a colour of
# its own so a hold reads apart from the status beside it.
HELD_PREFIX="held: "
HELD_VALUES="visit
review
blocked"
HELD_COLOR="${GC_PR_HELD_LABEL_COLOR:-D93F0B}"
# Both families, one prefix per line. A label under either prefix is the
# writer's: a reconcile takes off every one it did not derive.
FAMILIES="$LABEL_PREFIX
$HELD_PREFIX"

label_desc() { # <label name> — its GitHub description (GitHub caps these at 100 chars)
  case "$1" in
    "${LABEL_PREFIX}working")         printf 'Workflow: the city is changing the PR or readying its draft; no human input needed.' ;;
    "${LABEL_PREFIX}merging")         printf 'Workflow: approved, and the city is landing it; nothing known blocks the merge.' ;;
    "${LABEL_PREFIX}needs-review")    printf 'Workflow: settled at the current head; awaiting a human review or re-review.' ;;
    "${LABEL_PREFIX}needs-attention") printf 'Workflow: a blocker stands that the city will not clear on its own; needs a human.' ;;
    "${HELD_PREFIX}visit")            printf 'Workflow: an open visit holds the PR or its work in flight; a person answers it.' ;;
    "${HELD_PREFIX}review")           printf 'Workflow: an unresolved review thread holds the merge; a person resolves it.' ;;
    "${HELD_PREFIX}blocked")          printf 'Workflow: a blocker no automated actor will clear holds the PR; a person clears it.' ;;
    "$HELD_PREFIX"*)                  printf 'Workflow hold label.' ;;
    *)                                printf 'Workflow status label.' ;;
  esac
}

is_status_value() { # <value>
  case "$1" in
    working|merging|needs-review|needs-attention) return 0 ;;
    *) return 1 ;;
  esac
}

is_held_value() { # <value>
  case "$1" in
    visit|review|blocked) return 0 ;;
    *) return 1 ;;
  esac
}

# Every label the writer owns, one per line: its name, a tab, its colour.
owned_labels() {
  local v
  while IFS= read -r v; do
    [ -n "$v" ] && printf '%s%s\t%s\n' "$LABEL_PREFIX" "$v" "$GROUP_COLOR"
  done <<< "$STATUS_VALUES"
  while IFS= read -r v; do
    [ -n "$v" ] && printf '%s%s\t%s\n' "$HELD_PREFIX" "$v" "$HELD_COLOR"
  done <<< "$HELD_VALUES"
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

# Create any status: or held: label missing from the repo, and correct the
# description of one whose description no longer says what the value means.
# Idempotent: reads the label list once and writes only what differs, so a steady
# state does no write. A read that fails is not proof a label is missing, so it
# writes nothing.
ensure_labels() { # uses ORIGIN_*
  local have rc name color want cur
  have=$(gh label list --repo "$ORIGIN_REPO_Q" --limit 200 --json name,description \
    -q '.[] | [.name, (.description // "")] | @tsv' 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "could not list labels on $ORIGIN_REPO_Q (rc=$rc); not creating any"
    return 2
  fi
  owned_labels | while IFS=$'\t' read -r name color; do
    [ -n "$name" ] || continue
    want=$(label_desc "$name")
    if ! cur=$(printf '%s\n' "$have" | awk -F'\t' -v n="$name" '$1 == n { print $2; found = 1; exit } END { exit !found }'); then
      gh label create "$name" --repo "$ORIGIN_REPO_Q" \
        --color "$color" --description "$want" >/dev/null 2>&1 \
        || warn "could not create label '$name' on $ORIGIN_REPO_Q"
    elif [ "$cur" != "$want" ]; then
      gh label edit "$name" --repo "$ORIGIN_REPO_Q" --description "$want" >/dev/null 2>&1 \
        || warn "could not correct the description of '$name' on $ORIGIN_REPO_Q"
    fi
  done
  return 0
}

# --- the projection derivation (one Go code path) -------------------------

# The values are computed by one Go package, services/gctk/prstatus, exported so
# the helm board derives the same per-bead state from it, so a bead's PR labels
# and its board liveness cannot disagree. `gctk pr-status derive --anchor ID`
# prints working|merging|needs-review|needs-attention, and with --json one object
# carrying that status and the held values, {"status": ..., "held": [...]}. It
# exits 0 on success and 2 when a read did not resolve. There is deliberately no
# shell reimplementation: a second code path is the divergence this shared
# package exists to remove, and the board has no shell to fall back to. When
# gctk cannot answer, the caller leaves the labels as they are, because a failed
# read is not a state.
#
# The binary is resolved as lifecycle.sh resolves it — an explicit $GCTK_BIN,
# else the city's deployed build — and, as there, it is not compared against the
# checkout: a binary too old to carry `pr-status`, or its --json, exits non-zero
# on the unknown subcommand or flag, which reads as "could not derive" and
# leaves the labels untouched until the build order catches up.
resolve_gctk() { # succeed with GCTK_BIN naming an executable, else fail
  if [ -z "${GCTK_BIN:-}" ]; then
    local city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    [ -z "$city" ] && city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
    [ -n "$city" ] && GCTK_BIN="$city/.gc/services/gctk/bin/gctk"
  fi
  [ "${GCTK_BIN:-}" != "none" ] && [ -n "${GCTK_BIN:-}" ] && [ -x "${GCTK_BIN:-}" ]
}

# derive_value prints the status value on stdout, or with --json the object
# carrying the status and the held values, and returns 1 on a usage error and 2
# when a read did not resolve.
derive_value() { # <anchor-id> [--json]
  local anchor="$1"; shift
  [ -n "$anchor" ] || { warn "derive needs --anchor"; return 1; }
  if resolve_gctk; then
    "$GCTK_BIN" pr-status derive --anchor "$anchor" "$@"
    return $?
  fi
  warn "gctk unavailable (GCTK_BIN='${GCTK_BIN:-}'); cannot derive a status without the shared code path — leaving the labels unchanged"
  return 2
}

# --- writing the labels ---------------------------------------------------

# in_family reports whether a label belongs to one of the families named, by
# its leading prefix, so a label that merely contains a prefix mid-name is never
# mistaken for one of ours.
in_family() { # <label> <families, one prefix per line>
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$1" in "$p"*) return 0 ;; esac
  done <<< "$2"
  return 1
}

# sync_labels brings a PR's labels of the families named to exactly the targets,
# in one edit: it adds each target the PR lacks and takes off every label of
# those families that is not a target. It reads the PR's current labels
# (--current-labels lets a caller that already has them skip the read), and a
# read that does not resolve leaves them as they are rather than writing blind.
# A no-op when the PR already carries exactly the targets. An edit that adds a
# label first ensures the labels exist, since GitHub refuses one the repository
# lacks. It returns 2 when a read or the edit does not land.
sync_labels() { # <pr-number> <targets, one per line> <families, one per line> [<current-labels csv or newline>]
  local num="$1" targets="$2" families="$3" provided="${4:-}" cur rc l
  if [ -n "$provided" ]; then
    cur=$(printf '%s' "$provided" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d')
  else
    cur=$(gh pr view "$num" --repo "$ORIGIN_REPO_Q" --json labels -q '.labels[].name' 2>/dev/null); rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "could not read PR#$num labels on $ORIGIN_REPO_Q (rc=$rc); labels left unchanged"
      return 2
    fi
  fi
  local present="" add="" rm=""
  while IFS= read -r l; do
    [ -n "$l" ] && in_family "$l" "$families" && present="$present$l"$'\n'
  done <<< "$cur"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    grep -Fxq -- "$l" <<< "$present" || add="${add:+$add,}$l"
  done <<< "$targets"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    grep -Fxq -- "$l" <<< "$targets" || rm="${rm:+$rm,}$l"
  done <<< "$present"
  [ -n "$add" ] || [ -n "$rm" ] || return 0
  [ -z "$add" ] || ensure_labels
  local args=(pr edit "$num" --repo "$ORIGIN_REPO_Q")
  [ -n "$add" ] && args+=(--add-label "$add")
  [ -n "$rm" ] && args+=(--remove-label "$rm")
  if ! gh "${args[@]}" >/dev/null 2>&1; then
    warn "could not write PR#$num's labels (adding '${add}', removing '${rm}'); the reconcile retries next pass"
    return 2
  fi
  return 0
}

# Set the target status value on a PR, mutually exclusive: add the target and
# remove every OTHER status: label present. The held: labels are left as they
# are. A no-op when the target is already the only status: label.
set_label() { # <pr-number> <value> [<current-labels-csv or newline>]
  local num="$1" value="$2" provided="${3:-}"
  [ -n "$num" ] || { warn "set needs --pr"; return 1; }
  is_status_value "$value" || { warn "set --value must be one of: $(printf '%s' "$STATUS_VALUES" | paste -sd'|' -) (got '$value')"; return 1; }
  sync_labels "$num" "${LABEL_PREFIX}${value}" "$LABEL_PREFIX" "$provided"
}

# Write what the derivation returned: the one status value, and a held: label
# for each held value, every other label of both families removed. Exits as the
# derivation does when it cannot answer, and 2 when its answer names a value the
# writer has no label for, leaving the labels as they are either way.
reconcile_labels() { # <anchor-id> <pr-number> [<current-labels-csv or newline>]
  local anchor="$1" num="$2" provided="${3:-}" d dr v h targets
  [ -n "$num" ] || { warn "reconcile needs --pr"; return 1; }
  d=$(derive_value "$anchor" --json); dr=$?
  [ "$dr" -eq 0 ] || return "$dr"
  v=$(printf '%s' "$d" | jq -r '.status // empty' 2>/dev/null)
  h=$(printf '%s' "$d" | jq -r 'if (.held | type) == "array" then .held[] else error("no held list") end' 2>/dev/null) \
    || { warn "the derivation of $anchor carried no held list ('$d'); labels left unchanged"; return 2; }
  is_status_value "$v" || { warn "the derivation of $anchor named no status value ('$d'); labels left unchanged"; return 2; }
  targets="${LABEL_PREFIX}${v}"
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    is_held_value "$v" || { warn "the derivation of $anchor named a held value the writer has no label for ('$v'); labels left unchanged"; return 2; }
    targets="$targets"$'\n'"${HELD_PREFIX}${v}"
  done <<< "$h"
  sync_labels "$num" "$targets" "$FAMILIES" "$provided"
}

# Take every status: and held: label off a PR, the terminal step once it has
# merged or closed. A no-op when none is present. A read of the PR's labels that
# does not resolve leaves them as they are.
clear_labels() { # <pr-number> [<current-labels-csv or newline>]
  local num="$1" provided="${2:-}"
  [ -n "$num" ] || { warn "clear needs --pr"; return 1; }
  sync_labels "$num" "" "$FAMILIES" "$provided"
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
    reconcile_labels "$ANCHOR" "$PR" "$CURRENT"; exit $? ;;
  clear)
    resolve_origin "$REPO" "$HOST" || exit 2
    clear_labels "$PR" "$CURRENT"; exit $? ;;
  ''|-h|--help|help)
    cat >&2 <<'USAGE'
usage: pr-status-label.sh <verb> [options]
  ensure    --repo Q [--host H]
  derive    --anchor ID
  set       --pr N --value working|merging|needs-review|needs-attention --repo Q [--host H] [--current-labels CSV]
  reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV]
  clear     --pr N --repo Q [--host H] [--current-labels CSV]
USAGE
    [ -n "$VERB" ] && exit 0 || exit 1 ;;
  *) warn "unknown verb '$VERB'"; exit 1 ;;
esac
