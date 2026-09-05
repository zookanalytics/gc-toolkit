#!/usr/bin/env bash
# branch-context.sh — resolve the repo that OWNS a bead's branch and read that
# branch's existence and merge geometry against it. mol-witness-patrol runs from
# the witness's agent home, whose git toplevel is the town repo, so an unpinned
# git or gh call resolves `origin` there: a branch that lives in a rig repo reads
# as absent (a false "gone" that invites discarding pushed work) and a salvage
# push publishes rig commits to the town repo. Every answer here is pinned to the
# owning rig, and anything the resolved context cannot assert is "unknown", never
# absence.
#
# Owning rig, in precedence: the bead's store ref, then its work_dir path, then
# the patrol's own rig (GC_RIG). RIG_ROOT is that rig's checkout; OWNER_REPO is
# the owner/repo slug parsed from its origin, for gh calls; REPO_CTX is "ok" only
# when RIG_ROOT is a git repo whose origin reads as owner/repo.
#
#   resolve --store-ref <rig:x> --worktree <dir> --branch <ref>
#       Print eval-able KEY=VALUE for RIG_ROOT, OWNER_REPO, OWNING_ORIGIN_URL,
#       REPO_CTX and BRANCH_ON_ORIGIN (present|absent|unknown). Existence is
#       pinned to the owning rig, so a live branch never reads absent from the
#       wrong cwd; unknown whenever the owning repo was not asserted.
#
#   merged --store-ref <rig:x> --worktree <dir> --branch <ref> --target <ref>
#       Print yes|no|unknown: did BRANCH already land on TARGET in the owning
#       repo. A full checkout compares remote-tracking refs, but only after a
#       targeted fetch of BOTH succeeds — a ref left stale by an upstream delete
#       never feeds the verdict. A shallow checkout cannot answer from local
#       history (its grafted boundary lies), so it defers to the compare API.
#       Anything unreadable is unknown, never a discard signal.
#
#   push-target-ok --worktree <dir> --owning-origin <url> [--bead <id>]
#       Exit 0 when the worktree's origin IS the owning origin, so a salvage
#       `git push origin HEAD` reaches the owning repo. Exit 1 with a REFUSING
#       diagnostic when it is not, or when the owning origin is unknown.
#
# Env: GC_CITY_PATH, GC_RIG, GC_RIG_ROOT. Caller: formulas/mol-witness-patrol.toml
# (recover-orphaned-beads step — salvage, then verify-before-reset). Reads only;
# never writes the store or a branch. Exit: 0 ok · 1 refusal (push-target-ok)
# · 2 usage.
set -uo pipefail

PROG="branch-context"
note() { printf '%s: %s\n' "$PROG" "$*" >&2; }

usage() {
  cat >&2 <<'EOF'
usage:
  branch-context.sh resolve        --store-ref <rig:x> --worktree <dir> --branch <ref>
  branch-context.sh merged         --store-ref <rig:x> --worktree <dir> --branch <ref> --target <ref>
  branch-context.sh push-target-ok --worktree <dir> --owning-origin <url> [--bead <id>]
EOF
}
usage_die() { printf '%s: %s\n' "$PROG" "$*" >&2; usage; exit 2; }

# Resolve the owning rig and repo from the bead's pointers. Reads STORE_REF,
# WORKTREE and the GC_* env; sets RIG_ROOT, OWNER_REPO, OWNING_ORIGIN_URL and
# REPO_CTX. REPO_CTX=ok is the assertion that a git repo whose origin reads as
# owner/repo was found — a caller concludes absence only under it.
resolve_owning_repo() {
  local t _repo _rest _owner
  OWNING_RIG=""
  case "${STORE_REF:-}" in
    rig:*) OWNING_RIG="${STORE_REF#rig:}" ;;
  esac
  if [ -z "$OWNING_RIG" ]; then
    case "${WORKTREE:-}" in
      */rigs/*)          t="${WORKTREE##*/rigs/}"; OWNING_RIG="${t%%/*}" ;;
      */.gc/worktrees/*) t="${WORKTREE##*/.gc/worktrees/}"; OWNING_RIG="${t%%/*}" ;;
    esac
  fi
  [ -z "$OWNING_RIG" ] && OWNING_RIG="${GC_RIG:-}"
  RIG_ROOT=""
  OWNER_REPO=""
  OWNING_ORIGIN_URL=""
  REPO_CTX="unknown"
  if [ -n "$OWNING_RIG" ] && [ -n "${GC_CITY_PATH:-}" ] && git -C "${GC_CITY_PATH}/rigs/${OWNING_RIG}" rev-parse --git-dir >/dev/null 2>&1; then
    RIG_ROOT="${GC_CITY_PATH}/rigs/${OWNING_RIG}"
  elif { [ -z "$OWNING_RIG" ] || [ "$OWNING_RIG" = "${GC_RIG:-}" ]; } && [ -n "${GC_RIG_ROOT:-}" ] && git -C "${GC_RIG_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    RIG_ROOT="${GC_RIG_ROOT}"
  fi
  if [ -n "$RIG_ROOT" ]; then
    OWNING_ORIGIN_URL=$(git -C "$RIG_ROOT" remote get-url origin 2>/dev/null || true)
    if [ -n "$OWNING_ORIGIN_URL" ]; then
      t="${OWNING_ORIGIN_URL%.git}"; _repo="${t##*/}"; _rest="${t%/*}"; _owner="${_rest##*[:/]}"
      OWNER_REPO="${_owner}/${_repo}"
      case "$OWNER_REPO" in
        ?*/?*) REPO_CTX="ok" ;;
        *)     OWNER_REPO="" ;;
      esac
    fi
  fi
}

cmd_resolve() {
  STORE_REF=""; WORKTREE=""; BRANCH=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store-ref) STORE_REF="${2-}"; shift 2 ;;
      --worktree)  WORKTREE="${2-}"; shift 2 ;;
      --branch)    BRANCH="${2-}"; shift 2 ;;
      *) usage_die "resolve: unexpected argument '$1'" ;;
    esac
  done
  resolve_owning_repo
  # Existence, pinned to the owning rig. `unknown` unless the owning repo was
  # asserted, so a live branch is never read absent from the wrong repo context.
  local BRANCH_ON_ORIGIN="unknown" LS_HEADS
  if [ "$REPO_CTX" = "ok" ] && [ -n "${BRANCH:-}" ]; then
    if LS_HEADS=$(git -C "$RIG_ROOT" ls-remote --heads origin "$BRANCH" 2>/dev/null); then
      if [ -n "$LS_HEADS" ]; then BRANCH_ON_ORIGIN="present"; else BRANCH_ON_ORIGIN="absent"; fi
    fi
  fi
  printf 'RIG_ROOT=%q\n'          "$RIG_ROOT"
  printf 'OWNER_REPO=%q\n'        "$OWNER_REPO"
  printf 'OWNING_ORIGIN_URL=%q\n' "$OWNING_ORIGIN_URL"
  printf 'REPO_CTX=%q\n'          "$REPO_CTX"
  printf 'BRANCH_ON_ORIGIN=%q\n'  "$BRANCH_ON_ORIGIN"
}

cmd_merged() {
  STORE_REF=""; WORKTREE=""; BRANCH=""; TARGET=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --store-ref) STORE_REF="${2-}"; shift 2 ;;
      --worktree)  WORKTREE="${2-}"; shift 2 ;;
      --branch)    BRANCH="${2-}"; shift 2 ;;
      --target)    TARGET="${2-}"; shift 2 ;;
      *) usage_die "merged: unexpected argument '$1'" ;;
    esac
  done
  resolve_owning_repo
  local BRANCH_MERGED="unknown" SHALLOW AHEAD
  if [ "$REPO_CTX" = "ok" ] && [ -n "${BRANCH:-}" ] && [ -n "${TARGET:-}" ]; then
    SHALLOW=$(git -C "$RIG_ROOT" rev-parse --is-shallow-repository 2>/dev/null || echo true)
    if [ "$SHALLOW" = "false" ]; then
      # A stale refs/remotes/origin/<ref> left by an upstream delete must never
      # feed the verdict, so the targeted fetch of BOTH refs is load-bearing: a
      # fetch that fails (branch gone, network) leaves the state unknown.
      if git -C "$RIG_ROOT" fetch --quiet origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" 2>/dev/null \
         && git -C "$RIG_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null 2>&1 \
         && git -C "$RIG_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$TARGET" >/dev/null 2>&1; then
        if git -C "$RIG_ROOT" merge-base --is-ancestor "refs/remotes/origin/$BRANCH" "refs/remotes/origin/$TARGET" 2>/dev/null; then
          BRANCH_MERGED="yes"
        else
          BRANCH_MERGED="no"
        fi
      fi
    elif [ -n "$OWNER_REPO" ]; then
      # Shallow: local history cannot answer (grafted boundary), so the compare
      # API is authoritative. ahead_by=0 means BRANCH holds nothing TARGET lacks.
      AHEAD=$(gh -R "$OWNER_REPO" api "repos/{owner}/{repo}/compare/${TARGET}...${BRANCH}" --jq '.ahead_by' 2>/dev/null || true)
      case "$AHEAD" in
        0)           BRANCH_MERGED="yes" ;;
        ''|*[!0-9]*) BRANCH_MERGED="unknown" ;;
        *)           BRANCH_MERGED="no" ;;
      esac
    fi
  fi
  printf '%s\n' "$BRANCH_MERGED"
}

cmd_push_target_ok() {
  local WORKTREE="" OWNING_ORIGIN_URL="" BEAD="<bead>" WT_ORIGIN
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worktree)      WORKTREE="${2-}"; shift 2 ;;
      --owning-origin) OWNING_ORIGIN_URL="${2-}"; shift 2 ;;
      --bead)          BEAD="${2-}"; shift 2 ;;
      *) usage_die "push-target-ok: unexpected argument '$1'" ;;
    esac
  done
  WT_ORIGIN=$(git -C "$WORKTREE" remote get-url origin 2>/dev/null || true)
  if [ -z "$OWNING_ORIGIN_URL" ] || [ "$WT_ORIGIN" != "$OWNING_ORIGIN_URL" ]; then
    note "REFUSING salvage push for $BEAD — worktree origin '${WT_ORIGIN:-<none>}' is not the owning origin '${OWNING_ORIGIN_URL:-<unknown>}'; skipping push to avoid cross-repo contamination."
    return 1
  fi
  return 0
}

[ "$#" -ge 1 ] || usage_die "a subcommand is required"
SUB="$1"; shift
case "$SUB" in
  resolve)        cmd_resolve "$@" ;;
  merged)         cmd_merged "$@" ;;
  push-target-ok) cmd_push_target_ok "$@" ;;
  -h|--help)      usage; exit 0 ;;
  *)              usage_die "unknown subcommand '$SUB'" ;;
esac
