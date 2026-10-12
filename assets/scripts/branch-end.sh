#!/usr/bin/env bash
# branch-end — end the origin branch of work the city retired without landing
# it, the way a merge ends a landed one: pin the tip, then delete the branch at
# exactly the tip that was checked.
#
# A merge ends its branch through the repository's delete-on-merge setting. A
# retire closes its bead through bead-rehome.sh, which calls this once the close
# reads back. It also runs by hand, one branch at a time.
#
# Whose branch. The branch stays while a live owner names it: a bead in the
# rig's own store whose status is outside the `done` category and whose
# metadata.branch or metadata.target is the branch. That covers an anchor,
# work not yet handed off, a convoy and the members landing on its integration
# branch, and a successor that resumed the branch. The retired bead's own
# review scaffolding, the beads whose anchor_bead names it, is not an owner once
# that bead reads closed: scaffolding-sweep.sh retires it as moot, and
# review-sweep.sh closes a review only after the branch is gone, so counting it
# would keep nearly every branch. A ledger that does not read keeps the branch.
# The default branch, main, and claude/* (the operator's own sessions) are
# never ended.
#
# Nothing is lost. The tip is pinned before the delete. A pull request whose
# refs/pull/<n>/head on origin equals the tip already pins it: GitHub keeps that
# ref after the branch is deleted, and the PR page offers to restore the branch.
# Otherwise an annotated archive/<branch>@<short-sha> tag is pushed at the tip
# and read back on origin, and an existing one is reused only if it peels to the
# tip. The delete is a push whose lease names the checked tip, so origin itself
# refuses it if the branch moved, and a moved branch is left alone. Whether the
# branch is gone is read back from origin, not taken from the push's status.
# Origin is written only through git: the delete and the tag. Nothing here
# writes to the ledger.
#
# Usage:
#   branch-end.sh --rig <name> --branch <branch> [--bead <id>] [--dry-run]
#     --rig     the rig whose checkout's origin holds the branch; its store is
#               the ledger the owner check reads
#     --branch  the branch to end
#     --bead    the bead the branch belongs to; its scaffolding is not an owner
#               once it reads closed
#     --dry-run every read, then the plan; writes nothing
# Exit: 0 the branch is gone from origin, ended now or already absent (a dry
#       run: it would be ended) · 3 kept: a live owner names it or its name is
#       protected · 4 not ended: a read failed, the pin did not land, the branch
#       moved, or origin refused the delete · 2 usage.
# Caller: bead-rehome.sh. Doctrine: docs/state-machine.md "Disposition"; the
# grant: docs/authority-map.md "Powers over origin refs". Test: branch-end.test.sh.
set -uo pipefail

PROG="branch-end"
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub

usage() {
  cat >&2 <<'U'
usage: branch-end.sh --rig <name> --branch <branch> [--bead <id>] [--dry-run]

Ends a retired origin branch: keeps it while a live bead in the rig's store
names it, pins its tip (the PR's refs/pull/<n>/head, or an annotated
archive/<branch>@<short-sha> tag), then deletes it at the checked tip.
Exit: 0 gone · 3 kept · 4 not ended · 2 usage.
U
  exit 2
}

RIG=""; BRANCH=""; BEAD=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --rig)     RIG="${2:-}"; shift 2 ;;
    --branch)  BRANCH="${2:-}"; shift 2 ;;
    --bead)    BEAD="${2:-}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage ;;
    *)         echo "$PROG: unknown argument '$1'" >&2; usage ;;
  esac
done
RIG="${RIG#rig:}"
[ -n "$RIG" ] || { echo "$PROG: --rig is required" >&2; usage; }
[ -n "$BRANCH" ] || { echo "$PROG: --branch is required" >&2; usage; }

RERUN="$HERE/branch-end.sh --rig $(printf '%q' "$RIG") --branch $(printf '%q' "$BRANCH")"
[ -n "$BEAD" ] && RERUN="$RERUN --bead $(printf '%q' "$BEAD")"

# Every refusal names the branch and the command that ends it once the cause
# clears.
not_ended() {
  echo "$PROG: did NOT end $BRANCH: $1. It stays on origin; end it with: $RERUN" >&2
  exit 4
}
kept() { echo "$PROG: kept $BRANCH: $1"; exit 3; }

for tool in gc jq git; do
  command -v "$tool" >/dev/null 2>&1 || not_ended "$tool is not on PATH"
done
git check-ref-format "refs/heads/$BRANCH" 2>/dev/null \
  || { echo "$PROG: '$BRANCH' is not a branch name" >&2; exit 2; }

# --- the rig: its checkout carries the origin, its store is the ledger -------
RIG_PATH=$(gc rig list --json 2>/dev/null | scrub \
  | jq -r --arg n "$RIG" '[.rigs[]? | select(.name == $n) | .path // empty][0] // empty' 2>/dev/null)
[ -n "$RIG_PATH" ] || not_ended "rig '$RIG' does not resolve through gc rig list"
git -C "$RIG_PATH" rev-parse --git-dir >/dev/null 2>&1 \
  || not_ended "$RIG_PATH is not a git checkout"
STORE="$RIG_PATH/.beads"

# --- protected names ---------------------------------------------------------
DEFAULT=$(git -C "$RIG_PATH" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
DEFAULT="${DEFAULT#origin/}"
[ -n "$DEFAULT" ] || DEFAULT=main
case "$BRANCH" in
  "$DEFAULT"|main) kept "the default branch and main are never ended" ;;
  claude/*)        kept "claude/* branches belong to the operator's own sessions" ;;
esac

# --- origin: one listing for the tip and whatever pins it ---------------------
# The full listing carries the branch, every refs/pull/<n>/head and any archive
# tag with its peeled commit. ls-remote matches a pattern against a ref's tail,
# so each ref is picked by its exact name instead. A branch already gone ends
# here, before the ledger is read.
ADV=$(git -C "$RIG_PATH" ls-remote origin 2>/dev/null) \
  || not_ended "origin's refs did not read from $RIG_PATH"
[ -n "$ADV" ] || not_ended "origin's refs read empty from $RIG_PATH"
ref_sha() { printf '%s\n' "$1" | awk -v r="$2" '$2 == r { print $1; exit }'; }

TIP=$(ref_sha "$ADV" "refs/heads/$BRANCH")
if [ -z "$TIP" ]; then
  echo "$PROG: $BRANCH is not on origin; nothing to end"
  exit 0
fi
case "$TIP" in *[!0-9a-f]*) not_ended "origin reported a malformed tip '$TIP'" ;; esac
SHORT="${TIP:0:12}"

# --- the ledger: does a live owner name the branch? (fail-closed) ------------
# Live is the status contract's: every status outside the `done` category, so a
# status the store gains protects a branch without a change here.
LIVE_STATUSES=$(gc bd --db "$STORE" statuses --json </dev/null 2>/dev/null | scrub \
  | jq -r '[.. | objects | select(has("name") and has("category"))
           | select(.category != "done") | .name] | unique | join(",")' 2>/dev/null)
[ -n "$LIVE_STATUSES" ] \
  || not_ended "the status contract of rig $RIG did not read, so a live owner cannot be ruled out"
# The store is asked only for the live beads that name the branch, one listing
# per field, so the read stays a few beads however many are live. The exact
# match below still decides; the store's comparison only narrows what is read.
LIVE_ROWS='[]'
for FIELD in branch target; do
  ROWS=$(gc bd --db "$STORE" list --status "$LIVE_STATUSES" --metadata-field "$FIELD=$BRANCH" --limit=0 --json </dev/null 2>/dev/null) \
    || not_ended "the live beads of rig $RIG naming it in metadata.$FIELD did not read, so a live owner cannot be ruled out"
  ROWS=$(printf '%s' "$ROWS" | scrub)
  # A listing is read only once it parses as exactly one array: an error object,
  # an empty payload or anything else would read as "no owners".
  printf '%s' "$ROWS" | jq -se 'length == 1 and (.[0] | type) == "array"' >/dev/null 2>&1 \
    || not_ended "the live beads of rig $RIG naming it in metadata.$FIELD did not parse as a bead list, so a live owner cannot be ruled out"
  LIVE_ROWS=$(printf '%s\n%s\n' "$LIVE_ROWS" "$ROWS" | jq -cs 'add | unique_by(.id)' 2>/dev/null) \
    || not_ended "the live beads of rig $RIG naming it could not be combined, so a live owner cannot be ruled out"
done

# The retired bead's scaffolding stops counting only once that bead reads
# closed. While it is open it owns its branch, and so does its scaffolding.
RETIRED=""
if [ -n "$BEAD" ]; then
  BSTATUS=$(gc bd --db "$STORE" show "$BEAD" --json </dev/null 2>/dev/null | scrub \
    | jq -r 'if type == "array" then (.[0].status // empty) else empty end' 2>/dev/null)
  [ -n "$BSTATUS" ] \
    || not_ended "bead $BEAD did not read from rig $RIG, so its scaffolding cannot be told from an owner"
  [ "$BSTATUS" = closed ] && RETIRED="$BEAD"
fi

OWNERS=$(printf '%s' "$LIVE_ROWS" | jq -r --arg b "$BRANCH" --arg r "$RETIRED" '
  .[] | (.metadata // {}) as $md
  | (($md.branch // "") | tostring) as $mb
  | (($md.target // "") | tostring) as $mt
  | select($mb == $b or $mt == $b)
  | select($r == "" or ((($md.anchor_bead // "") | tostring) != $r))
  | "\(.id // "?") (\(.status // "?"), \(if $mb == $b then "metadata.branch" else "metadata.target" end))"' 2>/dev/null) \
  || not_ended "the live beads of rig $RIG could not be matched against the branch"
if [ -n "$OWNERS" ]; then
  kept "a live owner names it: $(printf '%s\n' "$OWNERS" | head -5 | paste -sd ';' - | sed 's/;/; /g')"
fi

# --- what already pins the tip -----------------------------------------------
PIN=$(printf '%s\n' "$ADV" | awk -v t="$TIP" '$1 == t && $2 ~ /^refs\/pull\/[0-9]+\/head$/ { print $2; exit }')
TAG="archive/$BRANCH@$SHORT"
if [ -z "$PIN" ]; then
  git check-ref-format "refs/tags/$TAG" 2>/dev/null \
    || not_ended "the archive tag name $TAG is not a valid ref"
  TAG_REF=$(ref_sha "$ADV" "refs/tags/$TAG")
  if [ -n "$TAG_REF" ]; then
    TAG_AT=$(ref_sha "$ADV" "refs/tags/$TAG^{}")
    [ -n "$TAG_AT" ] || TAG_AT="$TAG_REF"
    [ "$TAG_AT" = "$TIP" ] \
      || not_ended "tag $TAG already exists on origin at ${TAG_AT:0:12}, not at the tip $SHORT"
    PIN="refs/tags/$TAG"
  fi
fi

if [ "$DRY" -eq 1 ]; then
  if [ -n "$PIN" ]; then
    echo "$PROG (dry run): would end $BRANCH at $SHORT; its tip is kept by $PIN"
  else
    echo "$PROG (dry run): would push tag $TAG at $SHORT, read it back on origin, then end $BRANCH"
  fi
  exit 0
fi

# --- pin the tip with an archive tag, read back on origin ---------------------
if [ -z "$PIN" ]; then
  # The tag object is written locally, so the tip has to be here. A branch the
  # city pushed from a worktree of this checkout already is.
  if ! git -C "$RIG_PATH" cat-file -e "${TIP}^{commit}" 2>/dev/null; then
    git -C "$RIG_PATH" fetch --quiet --no-tags --no-write-fetch-head origin "refs/heads/$BRANCH" >/dev/null 2>&1 || true
    git -C "$RIG_PATH" cat-file -e "${TIP}^{commit}" 2>/dev/null \
      || not_ended "its tip $SHORT did not fetch, so no tag can pin it"
  fi
  IDENT=$(git -C "$RIG_PATH" var GIT_COMMITTER_IDENT 2>/dev/null) \
    || not_ended "the checkout has no committer identity to name as the archive tag's tagger"
  MSG="$PROG: $BRANCH ended at $TIP${BEAD:+, retired with $BEAD}.
Restore: git fetch origin refs/tags/$TAG && git push origin $TIP:refs/heads/$BRANCH"
  TOBJ=$(printf 'object %s\ntype commit\ntag %s\ntagger %s\n\n%s\n' "$TIP" "$TAG" "$IDENT" "$MSG" \
    | git -C "$RIG_PATH" mktag 2>/dev/null) \
    || not_ended "the archive tag object could not be written"
  git -C "$RIG_PATH" push --quiet origin "${TOBJ}:refs/tags/${TAG}" >/dev/null 2>&1 || true
  GOT=$(git -C "$RIG_PATH" ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}" 2>/dev/null) \
    || not_ended "origin did not read back after the archive tag push"
  [ "$(ref_sha "$GOT" "refs/tags/$TAG^{}")" = "$TIP" ] \
    || not_ended "the archive tag $TAG did not read back on origin at $SHORT, so nothing pins the tip"
  PIN="refs/tags/$TAG"
fi

# --- delete at the checked tip, read back ------------------------------------
# The lease makes origin compare the branch with the checked tip as it deletes:
# a push that landed after the check refuses the delete.
git -C "$RIG_PATH" push --quiet --force-with-lease="refs/heads/$BRANCH:$TIP" origin ":refs/heads/$BRANCH" >/dev/null 2>&1 || true
AFTER=$(git -C "$RIG_PATH" ls-remote origin "refs/heads/$BRANCH" 2>/dev/null) \
  || not_ended "origin did not read back after the delete"
NOW=$(ref_sha "$AFTER" "refs/heads/$BRANCH")
if [ -z "$NOW" ]; then
  echo "$PROG: ended $BRANCH at $SHORT; its tip is kept by $PIN"
  exit 0
fi
[ "$NOW" = "$TIP" ] || not_ended "it moved to ${NOW:0:12} after it was checked at $SHORT, so it was left alone"
not_ended "origin refused the delete at $SHORT"
