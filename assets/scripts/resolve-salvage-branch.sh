#!/usr/bin/env bash
# resolve-salvage-branch — name the branch that holds an orphaned bead's work,
# BEFORE witness salvage decides there is nothing to salvage (tk-19213).
#
# THE BUG. `mol-witness-patrol` Step 2 reads the salvage keys off the ORPHANED
# BEAD itself:
#
#     WORKTREE=$(echo "$META" | jq -r '.work_dir // empty')
#     BRANCH=$(echo "$META"   | jq -r '.branch   // empty')
#
# That is correct for a plain work bead, which records both in its own metadata.
# It is empty for the shape the witness actually orphans most often: a graph.v2
# STEP bead. A step carries `gc.step_ref`, `gc.root_bead_id`, `gc.session_name`
# and nothing else — the branch and worktree live on the ANCHOR (the work item),
# one hop away through the root's input convoy. So `$BRANCH` is empty, Cases A
# through D are all skipped, and every orphaned step lands in Case E, "nothing
# salvageable", no matter how much finished work is sitting on origin.
#
# With no branch name in hand, the witness improvises: it searches remote refs
# for the only ids it does have — the workflow, the convoy, the session. No
# branch is ever named after any of those. A polecat branch is
# `polecat/<work-item-id>`, so the search cannot match the branch it exists to
# find, and reports "none found" with the confidence of a real answer.
#
# THE NEAR-MISS (2026-08-13). Step tk-bs8mv (workflow tk-s68nh) was closed with
#
#     "no branch/worktree work to salvage (verified via git branch -r search for
#      s68nh/c2h7d/mnd3, none found)"
#
# while `polecat/tk-lv6q5` held the entire implementation — codex-green at
# a0468f9, review bead already closed. It later merged as PR #333. Nothing was
# lost, but only because the work item's own review/merge lane carried it; the
# salvage check contributed nothing but a false all-clear. The same path on a
# branch that had not yet landed would have discarded it.
#
# WHAT THIS DOES. Resolves the anchor the way every other pass in this rig does
# — root -> `gc.input_convoy_id` -> the convoy's single tracked member — and
# hands the caller the branch to look for, in priority order:
#
#   1. the orphaned bead's own `metadata.branch`   (unchanged behavior)
#   2. the anchor's `metadata.branch`              (recorded explicitly at setup)
#   3. `polecat/<anchor-id>`                       (the naming convention)
#   4. `polecat/<bead-id>`                         (a work bead whose branch
#                                                   metadata write was lost)
#
# The workflow/convoy/session id searches are KEPT, as additional keys rather
# than the only ones: they run as a substring scan over remote refs and are
# reported separately as `candidate_refs`. Replacing one blind key with another
# blind key would just move the blind spot.
#
# AND IT FAILS LOUD. "None found" is only reported when the search actually had
# a branch name to look for. If the anchor cannot be resolved, or the store or
# the remote cannot answer, the pass exits non-zero and says so — a salvage
# check that cannot name the branch convention it is searching for must not be
# allowed to conclude that there is nothing there. The caller (Step 2's Case E)
# is gated on that exit status: loud means skip the bead this cycle, never
# "nothing to salvage".
#
# Read-only. Never writes a bead, never touches a worktree, never pushes.
#
# Usage:
#   resolve-salvage-branch.sh --bead <id> [--remote origin] [--repo-root <path>]
#
# Exit status:
#   0  resolution complete — read `salvageable=` for the verdict
#   2  usage error
#   3  anchor unresolved: no branch convention could be named — DO NOT conclude
#      "nothing to salvage"
#   4  cannot search: bead unreadable, no repository, or the remote did not
#      answer — DO NOT conclude "nothing to salvage"
set -uo pipefail

SELF=resolve-salvage-branch

usage() {
  cat >&2 <<'EOF'
Usage: resolve-salvage-branch.sh --bead <id> [--remote <name>] [--repo-root <path>]

Prints key=value lines describing where an orphaned bead's work can be found:

  bead, root, convoy, anchor   the resolution chain
  branch, branch_sha           the branch the work is on (empty if none found)
  work_dir                     worktree recorded by the bead or its anchor
  match                        exact | substring | none
  salvageable                  1 | 0 | unknown
  resolution                   ok | unresolved-anchor | unreadable | no-repo | no-remote
  searched                     exact branch candidates, in priority order
  id_keys                      workflow/convoy/session keys used for the scan
  candidate_refs               remote refs matching an id key (weak signal)
EOF
}

BEAD=""
REMOTE="origin"
REPO_ROOT="${GC_RIG_ROOT:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --bead|--remote|--repo-root)
      if [ $# -lt 2 ]; then
        echo "$SELF: $1 requires a value" >&2
        exit 2
      fi
      case "$1" in
        --bead)      BEAD="$2" ;;
        --remote)    REMOTE="$2" ;;
        --repo-root) REPO_ROOT="$2" ;;
      esac
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$SELF: unknown argument '$1'" >&2; usage; exit 2 ;;
  esac
done

if [ -z "$BEAD" ]; then
  echo "$SELF: --bead is required" >&2
  usage
  exit 2
fi

# Everything the caller needs is printed on EVERY exit path, including the loud
# ones. A witness that skipped a bead because the anchor would not resolve still
# has to say which chain it got stuck on, and a verdict that appears only on the
# happy path is a verdict the failure case has to reconstruct by hand.
BEAD_ROOT=""; BEAD_CONVOY=""; ANCHOR=""
BRANCH=""; BRANCH_SHA=""; WORK_DIR=""
MATCH=none; SALVAGEABLE=unknown; RESOLUTION=ok
SEARCHED=""; ID_KEYS=""; CANDIDATE_REFS=""

emit() {
  printf 'bead=%s\n'           "$BEAD"
  printf 'root=%s\n'           "$BEAD_ROOT"
  printf 'convoy=%s\n'         "$BEAD_CONVOY"
  printf 'anchor=%s\n'         "$ANCHOR"
  printf 'branch=%s\n'         "$BRANCH"
  printf 'branch_sha=%s\n'     "$BRANCH_SHA"
  printf 'work_dir=%s\n'       "$WORK_DIR"
  printf 'match=%s\n'          "$MATCH"
  printf 'salvageable=%s\n'    "$SALVAGEABLE"
  printf 'resolution=%s\n'     "$RESOLUTION"
  printf 'searched=%s\n'       "$SEARCHED"
  printf 'id_keys=%s\n'        "$ID_KEYS"
  printf 'candidate_refs=%s\n' "$CANDIDATE_REFS"
}

die_loud() {
  # $1 = resolution slug, $2 = exit code, $3 = human explanation
  RESOLUTION="$1"
  SALVAGEABLE=unknown
  emit
  echo "$SELF: $BEAD — $3" >&2
  echo "$SELF: NOT a 'nothing to salvage' verdict — the search never ran. Skip this bead and re-check next cycle." >&2
  exit "$2"
}

# --- The repository the branch questions are answered against. ----------------
# Pinned, never left to the ambient cwd: this runs from a patrol worktree, and a
# husk work_dir resolves `origin` from whatever repo encloses it (see the HUSK
# GUARD in mol-witness-patrol). An `ls-remote` against the wrong remote answers
# "no such branch" for a branch that exists — the same false all-clear this pass
# exists to prevent, one layer down.
if [ -z "$REPO_ROOT" ] || ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  REPO_ROOT=""
  for cand in "${GC_RIG_ROOT:-}" "$(git rev-parse --show-toplevel 2>/dev/null)"; do
    [ -n "$cand" ] || continue
    if git -C "$cand" rev-parse --git-dir >/dev/null 2>&1; then REPO_ROOT="$cand"; break; fi
  done
fi
[ -n "$REPO_ROOT" ] \
  || die_loud no-repo 4 "no git repository resolved (\$GC_RIG_ROOT='${GC_RIG_ROOT:-}'); cannot ask whether any branch is published"

# --- Bead reads. --------------------------------------------------------------
# bd's JSON carries raw control characters often enough to be worth scrubbing
# every time; unscrubbed they kill jq and the failure reads as an empty field.
# TAB and newline are spared — jq wants them and nothing else here minds.
bead_metadata() {
  # $1 = bead id. Prints the metadata object. Non-zero when the store did not
  # answer, which is a different thing from a bead that answered with no
  # metadata (`{}`) — the caller must not conflate them.
  local raw meta
  raw=$(gc bd show "$1" --json 2>/dev/null) || return 1
  [ -n "$raw" ] || return 1
  meta=$(printf '%s' "$raw" \
    | tr -d '\000-\010\013\014\016-\037' \
    | jq -c 'if type == "array" and length > 0 then (.[0].metadata // {}) else empty end' 2>/dev/null) || return 1
  [ -n "$meta" ] || return 1
  printf '%s' "$meta"
}

meta_get() {
  # $1 = metadata JSON, $2 = key. Flat lookup: gc metadata keys are dotted
  # strings (`gc.root_bead_id`), not nested objects.
  printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // ""' 2>/dev/null
}

BEAD_META=$(bead_metadata "$BEAD") \
  || die_loud unreadable 4 "could not read bead metadata from the store"

BEAD_BRANCH=$(meta_get "$BEAD_META" branch)
BEAD_WORK_DIR=$(meta_get "$BEAD_META" work_dir)
BEAD_STEP_REF=$(meta_get "$BEAD_META" "gc.step_ref")
BEAD_ROOT=$(meta_get "$BEAD_META" "gc.root_bead_id")
BEAD_SESSION=$(meta_get "$BEAD_META" "gc.session_id")
BEAD_SESSION_NAME=$(meta_get "$BEAD_META" "gc.session_name")

# --- Anchor resolution: root -> input convoy -> the convoy's single member. ----
# The same chain `quiesce-completed-workflows.sh` and `core.control-dispatcher`
# walk. Both mol-polecat-base and mol-scoped-work require exactly one tracked
# member and refuse to run otherwise, so a convoy holding any other number is a
# shape this pass does not understand — and guessing at it is how a live
# molecule's branch gets attributed to the wrong work item.
ANCHOR_META=""
if [ -n "$BEAD_ROOT" ]; then
  ROOT_META=$(bead_metadata "$BEAD_ROOT") \
    || die_loud unreadable 4 "step of workflow $BEAD_ROOT, whose root row could not be read; the anchor is unreachable"
  BEAD_CONVOY=$(meta_get "$ROOT_META" "gc.input_convoy_id")
  if [ -n "$BEAD_CONVOY" ]; then
    ANCHOR=$(gc convoy status "$BEAD_CONVOY" --json 2>/dev/null \
      | tr -d '\000-\010\013\014\016-\037' \
      | jq -r 'if ((.children // []) | length) == 1 then (.children[0].id // empty) else empty end' 2>/dev/null)
  fi
  if [ -n "$ANCHOR" ]; then
    ANCHOR_META=$(bead_metadata "$ANCHOR") \
      || die_loud unreadable 4 "anchor $ANCHOR resolved but its row could not be read"
  fi
fi

# A bead that IS a graph.v2 step and has no branch of its own depends entirely on
# the anchor for its branch name. If that hop failed there is no convention left
# to name, and "none found" would be a statement about a search that never ran.
if [ -z "$ANCHOR" ] && [ -z "$BEAD_BRANCH" ] \
   && { [ -n "$BEAD_STEP_REF" ] || [ -n "$BEAD_ROOT" ]; }; then
  die_loud unresolved-anchor 3 "graph.v2 step (root '${BEAD_ROOT:-none}', convoy '${BEAD_CONVOY:-none}') whose anchor did not resolve; no branch convention can be named for it"
fi

ANCHOR_BRANCH=""
ANCHOR_WORK_DIR=""
if [ -n "$ANCHOR_META" ]; then
  ANCHOR_BRANCH=$(meta_get "$ANCHOR_META" branch)
  ANCHOR_WORK_DIR=$(meta_get "$ANCHOR_META" work_dir)
fi

# The worktree follows the same precedence as the branch: the bead's own record
# first, the anchor's when the bead has none. Cases C and D still gate every
# write on the HUSK GUARD, so handing them the anchor's path widens what salvage
# can see without widening what it may write.
WORK_DIR="$BEAD_WORK_DIR"
[ -n "$WORK_DIR" ] || WORK_DIR="$ANCHOR_WORK_DIR"

# --- Candidate branch names, most authoritative first. -------------------------
# Explicit records beat the convention: a rejection-resume or a caller-supplied
# branch is deliberately NOT `polecat/<id>`, and the recorded name is the one the
# refinery merges.
CANDIDATES=()
add_candidate() {
  [ -n "$1" ] || return 0
  local seen
  for seen in ${CANDIDATES+"${CANDIDATES[@]}"}; do
    [ "$seen" = "$1" ] && return 0
  done
  CANDIDATES+=("$1")
}
add_candidate "$BEAD_BRANCH"
add_candidate "$ANCHOR_BRANCH"
[ -n "$ANCHOR" ] && add_candidate "polecat/$ANCHOR"
add_candidate "polecat/$BEAD"
SEARCHED="${CANDIDATES[*]}"

# --- Ask origin, once, for everything it has. ---------------------------------
# One `ls-remote` serves both the exact lookups and the id scan. Its exit status
# is the only thing that separates "the remote says there are no such branches"
# from "the remote did not answer" — and collapsing those two is precisely the
# false all-clear this pass exists to prevent.
if ! REMOTE_LINES=$(git -C "$REPO_ROOT" ls-remote --heads "$REMOTE" 2>/dev/null); then
  die_loud no-remote 4 "'git ls-remote --heads $REMOTE' failed from $REPO_ROOT; the remote did not answer, so no branch can be ruled out"
fi

remote_sha_for() {
  # $1 = branch name -> its sha on the remote, empty when absent.
  # Fed by redirect, not a pipe: awk exits at the first match, which SIGPIPEs the
  # writer, and `pipefail` would promote that 141 to the substitution's status —
  # the same defect doctor/check-pipefail-grep-q exists to keep out.
  awk -v ref="refs/heads/$1" '$2 == ref { print $1; exit }' < <(printf '%s\n' "$REMOTE_LINES")
}

for cand in ${CANDIDATES+"${CANDIDATES[@]}"}; do
  sha=$(remote_sha_for "$cand")
  if [ -n "$sha" ]; then
    BRANCH="$cand"
    BRANCH_SHA="$sha"
    MATCH=exact
    break
  fi
done

# --- The legacy id searches, kept as ADDITIONAL keys. -------------------------
# These are what the near-miss searched on its own: workflow, convoy and session
# ids, in full and stripped of their `<prefix>-` (the "s68nh/c2h7d/mnd3" form).
# No branch is named after any of them, so a hit here is a weak signal reported
# for the operator's benefit — never the verdict. They run whether or not an
# exact match was found, because their whole value is describing what else is out
# there when the named branch is missing.
KEYS=()
add_key() {
  [ -n "$1" ] || return 0
  local seen
  for seen in ${KEYS+"${KEYS[@]}"}; do
    [ "$seen" = "$1" ] && return 0
  done
  KEYS+=("$1")
}
for key in "$BEAD" "$ANCHOR" "$BEAD_ROOT" "$BEAD_CONVOY" "$BEAD_SESSION" "$BEAD_SESSION_NAME"; do
  [ -n "$key" ] || continue
  add_key "$key"
  # The bare form too — `tk-s68nh` also searched as `s68nh`, which is the form
  # the near-miss used. Only for a short-prefixed id: stripping the first
  # component off a session NAME leaves a fragment that is not an id at all, and
  # a substring scan is exactly where a junk key does damage.
  short="${key#*-}"
  case "$key" in
    ?-*|??-*|???-*|????-*) ;;
    *) short="" ;;
  esac
  case "$short" in
    *-*) short="" ;;
  esac
  add_key "$short"
done
ID_KEYS="${KEYS[*]}"

REMOTE_BRANCHES=$(printf '%s\n' "$REMOTE_LINES" \
  | awk '{ sub(/^refs\/heads\//, "", $2); if ($2 != "") print $2 }')
for key in ${KEYS+"${KEYS[@]}"}; do
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    case " $CANDIDATE_REFS " in
      *" $hit "*) continue ;;
    esac
    CANDIDATE_REFS="${CANDIDATE_REFS:+$CANDIDATE_REFS }$hit"
  done < <(printf '%s\n' "$REMOTE_BRANCHES" | grep -F -- "$key")
done

if [ -z "$BRANCH" ] && [ -n "$CANDIDATE_REFS" ]; then
  MATCH=substring
fi

# --- Verdict. -----------------------------------------------------------------
# `salvageable=0` is now a claim the pass has standing to make: a branch name was
# derived from the anchor and origin was asked about it by name.
if [ -n "$BRANCH" ]; then
  SALVAGEABLE=1
else
  SALVAGEABLE=0
fi
emit

if [ "$SALVAGEABLE" = "1" ]; then
  echo "$SELF: $BEAD — work is published on '$BRANCH' ($BRANCH_SHA)${ANCHOR:+, via anchor $ANCHOR}" >&2
else
  echo "$SELF: $BEAD — no branch found for: $SEARCHED${CANDIDATE_REFS:+ (id-key hits, weak: $CANDIDATE_REFS)}" >&2
fi
exit 0
