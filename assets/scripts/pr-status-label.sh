#!/usr/bin/env bash
# pr-status-label.sh — the single writer of the workflow-owned GitHub PR labels.
# It projects the city's own state onto GitHub's pull request list, where that
# state is otherwise invisible until you open the PR. Two orthogonal groups:
#
#   status:  who must act on the PR next — the city holds the ball, a human should
#            review the head, or a human must weigh in before the PR can settle.
#            One value at a time, and pr-facts.sh recomputes it every cadence pass
#            from the anchor's posture, holds, and rework children. It is workflow
#            state, never an approval, and never asserts a PR may merge:
#            machine-readiness rides pr.machine and the draft flag. The tri-state
#            itself — the values, what each projects from, and their precedence —
#            is decided by one Go package, services/gctk/prstatus, reached through
#            `gctk pr-status derive` and exported so the helm board derives the
#            same per-bead state, so a bead's PR label and its board liveness
#            cannot disagree.
#   base:    where an approved change lands. A base under integration/ is a convoy
#            checkpoint, marked so a reviewer never mistakes it for a merge to main
#            (specs/tk-6bji7k.9/decision.md). Set once at pr-open where the base is
#            known and standing thereafter — a PR's base does not change — so it is
#            not reconciled the way status: is. A main-targeted PR is the default
#            and carries no base: label. mark_base is its writer.
#
# The two groups never touch: set matches only labels under `status: `, so it never
# removes a base: label, and mark_base only ever adds a base: label. A checkpoint PR
# is `status: needs-review` and `base: integration` at once, which a mutually
# exclusive shared group could not express.
#
# Every GitHub write is pinned to a repository the caller resolved (--repo), the
# same origin-pinning pr-open.sh and pr-facts.sh already apply; gh-origin-guard.sh
# guards agent-typed gh, not a script's own calls.
#
# Verbs:
#   ensure    --repo Q [--host H]                         create the status: labels if missing
#   derive    --anchor ID                                 print working | needs-review | needs-attention
#   set       --pr N --value V --repo Q [--host H] [--current-labels CSV]
#   reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV]
#   mark-base --pr N --target BRANCH --repo Q [--host H]  stamp base: from the target (no-op off integration/)
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
STATUS_VALUES="working
needs-review
needs-attention"
# One shared colour for the whole group so the values read as one dimension;
# override for a city that wants another. A 6-hex value, no leading '#'.
GROUP_COLOR="${GC_PR_STATUS_LABEL_COLOR:-1D76DB}"

label_desc() { # <value> — the label's GitHub description (GitHub caps these at 100 chars)
  case "$1" in
    working)         printf 'Workflow: the city holds the ball — rework or merge in flight; no human input needed.' ;;
    needs-review)    printf 'Workflow: settled at the current head; awaiting a human review or re-review.' ;;
    needs-attention) printf 'Workflow: stopped without settling (signoff cap, hold, blocked merge); needs a human to unstick.' ;;
    *)               printf 'Workflow status label.' ;;
  esac
}

is_status_value() { # <value>
  case "$1" in
    working|needs-review|needs-attention) return 0 ;;
    *) return 1 ;;
  esac
}

# The sibling `base:` group: where an approved change lands. One value today —
# `integration` marks a checkpoint into a convoy integration branch. A distinct
# colour so it reads as a second dimension, not another status; override for a city
# that wants another. A 6-hex value, no leading '#'.
BASE_LABEL_PREFIX="base: "
BASE_VALUES="integration"
BASE_GROUP_COLOR="${GC_PR_BASE_LABEL_COLOR:-5319E7}"

base_label_desc() { # <value> — the label's GitHub description (GitHub caps these at 100 chars)
  case "$1" in
    integration) printf 'Workflow: checkpoint into integration; approval mints a phase, not a merge to main.' ;;
    *)           printf 'Workflow base label.' ;;
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

# Create any label in a group missing from the repo. Idempotent: reads the label
# list once and creates only what is absent, so a steady state does no write. A
# read that fails is not proof a label is missing, so it creates nothing. descfn
# names a function called per value for the GitHub description.
ensure_group() { # <prefix> <newline-values> <color> <desc-fn> — uses ORIGIN_*
  local prefix="$1" values="$2" color="$3" descfn="$4" have rc v name
  have=$(gh label list --repo "$ORIGIN_REPO_Q" --limit 200 --json name -q '.[].name' 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "could not list labels on $ORIGIN_REPO_Q (rc=$rc); not creating any"
    return 2
  fi
  printf '%s\n' "$values" | while IFS= read -r v; do
    [ -n "$v" ] || continue
    name="${prefix}${v}"
    if ! printf '%s\n' "$have" | grep -Fxq "$name"; then
      gh label create "$name" --repo "$ORIGIN_REPO_Q" \
        --color "$color" --description "$("$descfn" "$v")" >/dev/null 2>&1 \
        || warn "could not create label '$name' on $ORIGIN_REPO_Q"
    fi
  done
  return 0
}
ensure_labels()      { ensure_group "$LABEL_PREFIX"      "$STATUS_VALUES" "$GROUP_COLOR"      label_desc; }
ensure_base_labels() { ensure_group "$BASE_LABEL_PREFIX" "$BASE_VALUES"   "$BASE_GROUP_COLOR" base_label_desc; }

# --- the projection derivation (one Go code path) -------------------------

# The tri-state is computed by one Go package, services/gctk/prstatus, exported
# so the helm board derives the same per-bead state from it, so a bead's PR label
# and its board liveness cannot disagree. `gctk pr-status derive --anchor ID`
# prints working|needs-review|needs-attention, exits 0 on success and 2 when a read did
# not resolve — the grammar the shell derivation had, so `set`/`reconcile` are
# unchanged around it. There is deliberately no shell reimplementation: a second
# code path is the divergence this shared package exists to remove, and the board
# has no shell to fall back to. When gctk cannot answer, derive exits 2 and the
# caller leaves the label as it is.
#
# The binary is resolved as lifecycle.sh resolves it — an explicit $GCTK_BIN,
# else the city's deployed build — and, as there, it is not compared against the
# checkout: a binary too old to carry `pr-status` exits non-zero on the unknown
# subcommand, which reads as "could not derive" and leaves the label untouched
# until the build order catches up.
resolve_gctk() { # succeed with GCTK_BIN naming an executable, else fail
  if [ -z "${GCTK_BIN:-}" ]; then
    local city="${GC_CITY_PATH:-${GC_CITY:-${GC_CITY_ROOT:-}}}"
    [ -z "$city" ] && city="$(gc service list --json 2>/dev/null | jq -r '.city_path // empty' 2>/dev/null || true)"
    [ -n "$city" ] && GCTK_BIN="$city/.gc/services/gctk/bin/gctk"
  fi
  [ "${GCTK_BIN:-}" != "none" ] && [ -n "${GCTK_BIN:-}" ] && [ -x "${GCTK_BIN:-}" ]
}

# derive_value keeps its name and grammar: print the tri-state on stdout, return
# 1 on a usage error, 2 when the state cannot be determined.
derive_value() { # <anchor-id>
  local anchor="$1"
  [ -n "$anchor" ] || { warn "derive needs --anchor"; return 1; }
  if resolve_gctk; then
    "$GCTK_BIN" pr-status derive --anchor "$anchor"
    return $?
  fi
  warn "gctk unavailable (GCTK_BIN='${GCTK_BIN:-}'); cannot derive a status without the shared code path — leaving the label unchanged"
  return 2
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

# --- the base marker ------------------------------------------------------

# Stamp the base: dimension on a PR from its target. A target under integration/ is
# a convoy checkpoint and earns `base: integration`; any other base (main) is the
# default and earns nothing, so this is a no-op there. Additive and idempotent: it
# only ever adds the label — gh treats adding a present label as a no-op — and it
# never touches the orthogonal status: label. Standing, not reconciled: pr-open
# calls it once where the base is known, and a PR's base does not change.
mark_base() { # <pr-number> <target>
  local num="$1" target="$2" name
  [ -n "$num" ] || { warn "mark-base needs --pr"; return 1; }
  case "$target" in
    integration/*) : ;;
    *) return 0 ;;
  esac
  ensure_base_labels
  name="${BASE_LABEL_PREFIX}integration"
  if ! gh pr edit "$num" --repo "$ORIGIN_REPO_Q" --add-label "$name" >/dev/null 2>&1; then
    warn "could not add '$name' to PR#$num on $ORIGIN_REPO_Q"
    return 2
  fi
  return 0
}

# --- argv -----------------------------------------------------------------

VERB="${1:-}"; [ -n "$VERB" ] && shift
ANCHOR=""; PR=""; VALUE=""; REPO=""; HOST=""; CURRENT=""; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --anchor)          ANCHOR="${2:-}"; shift 2 || exit 1 ;;
    --pr)              PR="${2:-}"; shift 2 || exit 1 ;;
    --value)           VALUE="${2:-}"; shift 2 || exit 1 ;;
    --target)          TARGET="${2:-}"; shift 2 || exit 1 ;;
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
  mark-base)
    resolve_origin "$REPO" "$HOST" || exit 2
    mark_base "$PR" "$TARGET"; exit $? ;;
  ''|-h|--help|help)
    cat >&2 <<'USAGE'
usage: pr-status-label.sh <verb> [options]
  ensure    --repo Q [--host H]
  derive    --anchor ID
  set       --pr N --value working|needs-review|needs-attention --repo Q [--host H] [--current-labels CSV]
  reconcile --anchor ID --pr N --repo Q [--host H] [--current-labels CSV]
  mark-base --pr N --target BRANCH --repo Q [--host H]
USAGE
    [ -n "$VERB" ] && exit 0 || exit 1 ;;
  *) warn "unknown verb '$VERB'"; exit 1 ;;
esac
