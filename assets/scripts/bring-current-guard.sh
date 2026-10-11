#!/usr/bin/env bash
# bring-current-guard — holds a bring-current to the worker's audit of it, and
# routes a conflicted one to triage, so no review covers code it never saw.
#
# Bringing a branch current merges its base in. Run at every hand-off
# (submit-and-exit in formulas/mol-polecat-work.toml, right after the push),
# this reads what the hand-off pushed onto a branch that carries a review to
# keep current: its anchor is gating, or a PR stands on it. A branch nobody has
# reviewed yet has nothing to keep, and is left alone. The round is one of:
#
#   CLEAN. Every commit the round adds is a merge of the base whose tree is the
#   one git produces on its own. Nothing was resolved by hand, so the round owes
#   no account and no triage. Its record is stored on the anchor and it lands
#   quietly. This comparison is the tripwire that proves "clean": nothing rides
#   in under that label.
#
#   CONFLICTED. Anything else. Each ITEM below is something git did not produce
#   on its own, and the worker owes one audit entry for each
#   (bring-current-audit.sh):
#     - a file in git's conflict set, however it was resolved;
#     - a file a merge commit changed beyond what git's own merge produces;
#     - a merge of anything but the base, or of more than two parents
#       (path `commit:<short>`), or a pushed head that does not descend from
#       where the round began (path `history`);
#     - a commit's own change that could not be read (path `commit:<short>`);
#     - on a bead whose only job is the bring-current
#       (bring_current_scope=merge-only, stamped where its resume began), each
#       file a commit of its own changes. On any other bead a commit of its own
#       is the bead's work, which its own review path judges; it is listed as
#       evidence and owes no entry.
#   A round whose audit lacks an entry for an item, or whose entry is
#   incomplete, is REFUSED (exit 3): nothing is handed off, and the worker
#   writes the missing entries and re-runs. A covered round is stored on the
#   anchor with the evidence, and routed to triage: the triage lane is
#   superseded, so gate-ensure.sh dispatches it again, and triage is added to
#   the lanes this anchor's rounds reopened (bring_current_reopened) with the
#   round's time (bring_current_round_at). lane-state.sh lets no approval given
#   before that time vouch for a reopened lane, so a standing approval neither
#   lets the merge skip triage nor keeps triage from being dispatched. An anchor
#   whose check_set declares no triage lane records the round and owes no
#   ruling.
#
# The guard renders no verdict on follow-up, and the worker's rating of an
# entry gates nothing. Triage decides what the round reopens, and records it
# through signoff.sh, which runs `decide` here: lanes to run again, and whether
# the human approval is dismissed.
#
# EVIDENCE. Each conflicted file is replayed with git's own merge (diff3, so
# each hunk shows what the merge base had there) and its resolution compared:
# whether both sides only added lines and the resolution keeps the two
# additions whole, one after the other in either order (each block read as git
# reads it, no common lines hoisted out, only blank lines ignored); whether the
# merge base had lines in a hunk that one or both sides changed; or whether the
# resolution is something else. Deleted, renamed, binary and mode-changed files
# are named as such. Paths in the generated tier (linguist-generated in
# .gitattributes) are renders the pack writes and nobody edits by hand, and
# merge.sh refuses a merge whose seed-audit render is not current, so they owe
# no entry and are listed as evidence only.
#
# DECIDE. `decide` records triage's ruling in the anchor's record, adds the
# lanes it reopens to bring_current_reopened, supersedes each reopened lane's
# standing review so gate-ensure.sh dispatches it again, and, when triage rules
# the approval no longer covers what would land, dismisses it. The visit that
# re-asks for the review is filed and read back first, so no dismissal strands
# a PR without a signal; each approving account is then re-requested and its
# approval dismissed, the order pr-facts.sh uses when it clears a human review.
# A dismissal that does not land is noted on the visit, which still holds the
# merge. The visit, the dismissal note and the round section of triage's
# posted verdict are all rendered from the stored record.
#
# Usage:
#   bring-current-guard.sh guard --bead <id> [--to <oid>] [--from <oid>]
#   bring-current-guard.sh coverage --bead <id> [--to <oid>] [--from <oid>]
#   bring-current-guard.sh classify --from <oid> --to <oid> --base <ref> [--scope merge-only|with-work]
#   bring-current-guard.sh decide --anchor <id> --review-bead <id> --reopen <lanes|none>
#       [--add <lanes>] [--dismiss-approval] --reason <text> [--body-out <file>]
# guard: <id> is the bead being handed off and --to the pushed head (default
# HEAD). The bead's bring_current_from, stamped where its resume began, marks
# where the round started; --from, the origin head before the push, stands in
# when that stamp is absent. With neither a stamp nor a --from short of the
# head, nothing records where the work began, which is refused too.
# coverage: the guard's reading without its writes: each item and whether the
# audit covers it. classify: prints none, clean, conflicted or unreadable, then
# one evidence line per item. All three read the git repository of the working
# directory.
# Exit: 0 nothing owed, or the round recorded (and routed) · 1 a read or a
# write failed, so nothing was handed off and the caller retries · 2 usage ·
# 3 the audit does not cover the round, or nothing records where it began: the
# worker completes it and re-runs
set -u

PROG="bring-current-guard"
# >>> control-char-scrub
# A raw C0 byte inside a JSON string aborts jq on the whole payload, so every
# C0 byte (U+0000-U+001F) is scrubbed before jq, LF included. DEL and bytes
# above 0x1F pass through raw, which JSON permits; the output feeds jq, so
# dropping a structural LF or TAB just minifies.
scrub() { tr -d '\000-\037'; }
# <<< control-char-scrub
SCRIPTS_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ESCALATE="$SCRIPTS_DIR/escalate.sh"
REVIEW_OUTCOME="${GC_REVIEW_OUTCOME_TOOL:-$SCRIPTS_DIR/review-outcome.sh}"
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }
# The audit's reads and every rendering of a round come from one place.
# shellcheck source=bring-current-audit.sh
. "$SCRIPTS_DIR/bring-current-audit.sh" || { echo "$PROG: cannot source bring-current-audit.sh beside this script" >&2; exit 2; }
# The approval rule merge.sh lands on: standing_approvals($self) is one review per
# approving account other than the city's.
# shellcheck source=review-verdict.sh
. "$SCRIPTS_DIR/review-verdict.sh" || { echo "$PROG: cannot source review-verdict.sh beside this script" >&2; exit 2; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
TAB=$(printf '\t')
TRIAGE_LANE="triage"

usage() {
  echo "usage: $PROG guard --bead <id> [--to <oid>] [--from <oid>]" >&2
  echo "       $PROG coverage --bead <id> [--to <oid>] [--from <oid>]" >&2
  echo "       $PROG classify --from <oid> --to <oid> --base <ref> [--scope merge-only|with-work]" >&2
  echo "       $PROG decide --anchor <id> --review-bead <id> --reopen <lanes|none> [--add <lanes>] [--dismiss-approval] --reason <text> [--body-out <file>]" >&2
  exit 2
}

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

short() { git rev-parse --short=12 "$1" 2>/dev/null || printf '%s' "$1"; }
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# The round being read. CLASS ends as none, clean, conflicted or unreadable;
# each evidence row is "<covered 1|0>\t<kind>\t<path>\t<commit>\t<detail>".
CLASS="none"; READ_FAIL=""; BASE_MERGES=0
ev() { # <covered> <kind> <path> <commit> <detail>
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$WORK/evidence"
}
unreadable() { READ_FAIL="$*"; }

EMPTY_BLOB=""
empty_blob() {
  [ -n "$EMPTY_BLOB" ] || EMPTY_BLOB=$(git hash-object -w --stdin </dev/null 2>/dev/null)
  printf '%s' "$EMPTY_BLOB"
}

# NUL-separated paths on stdin; prints those .gitattributes at <commit> does not
# mark linguist-generated (the reviewed tier) to stdout and the generated ones to
# <generated-file>, both NUL-separated. An attribute read that fails exempts
# nothing, so every path goes on to be judged.
split_paths() { # <commit> <generated-file>
  cat > "$WORK/paths"
  : > "$2"
  if ! git check-attr -z --stdin --source "$1" linguist-generated <"$WORK/paths" >"$WORK/attrs" 2>/dev/null; then
    cat "$WORK/paths"
    return
  fi
  while IFS= read -r -d '' p && IFS= read -r -d '' _attr && IFS= read -r -d '' val; do
    if [ "$val" = "set" ]; then printf '%s\0' "$p" >> "$2"; else printf '%s\0' "$p"; fi
  done <"$WORK/attrs"
}

# True when git reads <blob> as binary, by its own test: a diff from the empty
# blob counts no lines for it.
is_binary() { # <blob>
  case "$(git diff --no-ext-diff --no-textconv --numstat "$(empty_blob)" "$1" 2>/dev/null)" in
    -*) return 0 ;;
  esac
  return 1
}

# Conflict markers this long cannot be mistaken for a line of the file.
MARK=40
# Matches a committed resolution (second file) against git's own replay of the
# conflict (first file, diff3 markers MARK long, so each hunk shows what the
# merge base had there). Blank lines are left out of both. Prints `ok` when
# every hunk replaced nothing the base had and the resolution keeps the two
# sides' blocks whole, one after the other, around git's own merged text;
# `base` when a hunk had lines in the merge base that one or both sides changed;
# `differ` when the resolution is anything else; `unreadable` when no diff3 hunk
# could be read.
HUNK_MATCH_AWK='
function rep(c, n,   r) { r = ""; while (n-- > 0) r = r c; return r }
function blank(l) { return l ~ /^[ \t\r]*$/ }
function marker(l, m) { return substr(l, 1, M) == m && (length(l) == M || substr(l, M + 1, 1) == " ") }
function fits(at, a, b,   x) {
  for (x = 1; x <= a[0]; x++) if (R[at + x] != a[x]) return 0
  for (x = 1; x <= b[0]; x++) if (R[at + a[0] + x] != b[x]) return 0
  return 1
}
BEGIN { lt = rep("<", M); bar = rep("|", M); eq = rep("=", M); gt = rep(">", M); h = 0; ns[0] = 0 }
FILENAME == ARGV[1] {
  if (state == 0) {
    if (marker($0, lt)) { h++; no[h] = 0; nt[h] = 0; nb[h] = 0; ns[h] = 0; state = 1; next }
    if (!blank($0)) S[h, ++ns[h]] = $0
    next
  }
  if (state == 1) {
    if (marker($0, bar)) { state = 2; next }
    if ($0 == eq) { nobase = 1; state = 3; next }
    if (!blank($0)) O[h, ++no[h]] = $0
    next
  }
  if (state == 2) { if ($0 == eq) { state = 3; next } if (!blank($0)) nb[h]++; next }
  if (marker($0, gt)) { state = 0; next }
  if (!blank($0)) T[h, ++nt[h]] = $0
  next
}
{ if (!blank($0)) R[++nr] = $0 }
END {
  if (state != 0 || h == 0 || nobase) { print "unreadable"; exit }
  for (i = 1; i <= h; i++) if (nb[i] > 0) { print "base"; exit }
  total = 0
  for (j = 0; j <= h; j++) total += ns[j]
  for (i = 1; i <= h; i++) total += no[i] + nt[i]
  if (total != nr) { print "differ"; exit }
  pos = 0
  for (j = 0; j <= h; j++) {
    if (j > 0) {
      split("", a); split("", b); a[0] = no[j]; b[0] = nt[j]
      for (x = 1; x <= no[j]; x++) a[x] = O[j, x]
      for (x = 1; x <= nt[j]; x++) b[x] = T[j, x]
      if (!fits(pos, a, b) && !fits(pos, b, a)) { print "differ"; exit }
      pos += no[j] + nt[j]
    }
    for (x = 1; x <= ns[j]; x++) if (R[pos + x] != S[j, x]) { print "differ"; exit }
    pos += ns[j]
  }
  print "ok"
}'

# One conflicted path of merge <c>: its stages as merge-tree reported them, its
# replayed conflict in <tree>, and the resolution the merge commit carries.
classify_conflict() { # <c> <tree> <path> <stages: "<stage>:<mode>:<oid> ..." >
  local c="$1" tree="$2" p="$3" st="$4" s stages="" mode="" base="" ours="" theirs="" rmode res hunks sc
  sc=$(short "$c")
  for s in $st; do
    stages="$stages${s%%:*}"
    case "${s%%:*}" in
      1) base="${s##*:}" ;;
      2) ours="${s##*:}" ;;
      3) theirs="${s##*:}" ;;
    esac
    s="${s#*:}"; s="${s%%:*}"
    if [ -z "$mode" ]; then mode="$s"; elif [ "$mode" != "$s" ]; then mode="mixed"; fi
  done
  case "$stages" in 123|23) : ;; *)
    ev 1 conflict "$p" "$sc" "conflicted over a file one side deleted or renamed, so keeping it or not was a choice"
    return ;;
  esac
  case "$mode" in 100644|100755) : ;; *)
    ev 1 conflict "$p" "$sc" "conflicted over its file mode or type"
    return ;;
  esac
  rmode=$(git ls-tree "$c" -- "$p" 2>/dev/null | awk '{print $1}')
  res=$(git rev-parse -q --verify "${c}:${p}" 2>/dev/null)
  if [ -z "$res" ] || [ "$rmode" != "$mode" ]; then
    ev 1 conflict "$p" "$sc" "conflicted, and the merge deleted it or changed its mode"
    return
  fi
  [ -n "$base" ] || base=$(empty_blob)
  if is_binary "$base" || is_binary "$ours" || is_binary "$theirs" || is_binary "$res"; then
    ev 1 conflict "$p" "$sc" "is a binary file in conflict"
    return
  fi
  git cat-file blob "${tree}:${p}" > "$WORK/replay" 2>/dev/null
  git cat-file blob "$res" > "$WORK/resolution" 2>/dev/null
  hunks=$(awk -v M="$MARK" "$HUNK_MATCH_AWK" "$WORK/replay" "$WORK/resolution" 2>/dev/null)
  case "$hunks" in
    ok)     ev 1 conflict "$p" "$sc" "conflicted where both sides only added lines; the resolution keeps both additions whole" ;;
    base)   ev 1 conflict "$p" "$sc" "conflicted where the merge base had lines that one or both sides changed, so git could not merge it on its own" ;;
    differ) ev 1 conflict "$p" "$sc" "conflicted, and the resolution is not the two sides' additions kept whole: it took a side, interleaved them, rewrote, or dropped a line" ;;
    *)      ev 1 conflict "$p" "$sc" "conflicted, and its conflict could not be read back" ;;
  esac
}

# One merge commit <c> = <p1> (the branch) + <p2>, replayed with git's own merge.
classify_merge() { # <c> <p1> <p2>
  local c="$1" p1="$2" p2="$3" out rc tree entry meta p stg diffs sc
  sc=$(short "$c")
  out="$WORK/merge-tree.$c"
  # diff3 markers show what the merge base had in each hunk, and MARK-long
  # markers cannot collide with a line of the file. Neither changes which paths
  # conflict or what git merges cleanly.
  [ -f "$WORK/attributes" ] || printf '* conflict-marker-size=%s\n' "$MARK" > "$WORK/attributes"
  git -c core.attributesFile="$WORK/attributes" -c merge.conflictStyle=diff3 \
    merge-tree --write-tree -z --no-messages "$p1" "$p2" >"$out" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    ev 1 merge "commit:$sc" "$sc" "its merge of $(short "$p2") could not be replayed to compare against"
    return
  fi
  tree=""
  : > "$WORK/conflicts"
  while IFS= read -r -d '' entry; do
    if [ -z "$tree" ]; then tree="$entry"; continue; fi
    meta="${entry%%"$TAB"*}"; p="${entry#*"$TAB"}"
    # meta is "<mode> <oid> <stage>"
    printf '%s\t%s\n' "$p" "$(printf '%s' "$meta" | awk '{print $3 ":" $1 ":" $2}')" >> "$WORK/conflicts"
  done < "$out"
  if [ -z "$tree" ]; then
    ev 1 merge "commit:$sc" "$sc" "its merge of $(short "$p2") could not be replayed to compare against"
    return
  fi
  # Every path the merge commit carries differently from git's own result.
  diffs="$WORK/diffs.$c"
  if ! git diff-tree -r -z --no-renames --name-only "$tree" "$c" >"$diffs" 2>/dev/null; then
    ev 1 merge "commit:$sc" "$sc" "its tree could not be compared with git's own merge of $(short "$p2")"
    return
  fi
  # A conflicted path is an item whether or not its resolution differs from the
  # replayed markers; any other differing path is an edit the merge did not
  # need. The generated tier owes no entry and is listed as evidence.
  awk -F'\t' '{print $1}' "$WORK/conflicts" | sort -u | tr '\n' '\0' > "$WORK/cpaths"
  { cat "$diffs"; cat "$WORK/cpaths"; } | sort -zu | split_paths "$c" "$WORK/generated" > "$WORK/judged"
  while IFS= read -r -d '' p; do
    stg=$(P="$p" awk -F'\t' '$1 == ENVIRON["P"] { printf "%s ", $2 }' "$WORK/conflicts")
    if [ -n "$stg" ]; then
      classify_conflict "$c" "$tree" "$p" "$stg"
    else
      ev 1 beyond "$p" "$sc" "changed beyond what merging $(short "$p2") produces"
    fi
  done < "$WORK/judged"
  while IFS= read -r -d '' p; do
    ev 0 generated "$p" "$sc" "a generated render (linguist-generated), which owes no entry"
  done < "$WORK/generated"
}

# A commit of its own, <c> on <parent>: on a merge-only bead each file it
# changes is an item; elsewhere it is the bead's work, listed once.
classify_own() { # <c> <parent> <scope>
  local c="$1" parent="$2" scope="$3" sc subj n p
  sc=$(short "$c")
  subj=$(git log -1 --format=%s "$c" 2>/dev/null)
  if ! git diff-tree -r -z --no-renames --name-only "$parent" "$c" >"$WORK/own" 2>/dev/null; then
    if [ "$scope" = "merge-only" ]; then
      ev 1 own "commit:$sc" "$sc" "\"$subj\" is a commit of its own, and what it changed could not be read"
    else
      ev 0 own "commit:$sc" "$sc" "\"$subj\" is a commit of its own, and what it changed could not be read"
    fi
    return
  fi
  split_paths "$c" "$WORK/own-generated" < "$WORK/own" > "$WORK/own-reviewed"
  [ -s "$WORK/own-reviewed" ] || return 0
  if [ "$scope" = "merge-only" ]; then
    while IFS= read -r -d '' p; do
      ev 1 own "$p" "$sc" "changed by $sc \"$subj\", a commit of its own on a bead whose only job is the bring-current"
    done < "$WORK/own-reviewed"
  else
    n=$(tr -cd '\0' < "$WORK/own-reviewed" | wc -c | tr -d ' ')
    ev 0 own "commit:$sc" "$sc" "\"$subj\" is a commit of the bead's own work ($n file(s)), judged by its own review path"
  fi
}

# The commits <to> adds over <from> along the branch's own line, each read.
classify() { # <from> <to> <base-ref> <scope>
  local from="$1" to="$2" base="$3" scope="${4:-with-work}" c commits parents n subj
  CLASS="none"; READ_FAIL=""; BASE_MERGES=0
  [ -n "$WORK" ] || WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-bring-current-guard.XXXXXX") || { unreadable "no scratch directory to replay the merge in"; CLASS=unreadable; return; }
  : > "$WORK/evidence"
  from=$(git rev-parse -q --verify "$from^{commit}" 2>/dev/null) || { unreadable "the start of the round ($1) is not a commit here"; CLASS=unreadable; return; }
  to=$(git rev-parse -q --verify "$to^{commit}" 2>/dev/null) || { unreadable "the pushed head ($2) is not a commit here"; CLASS=unreadable; return; }
  if ! git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    unreadable "the base $base could not be read, so no merge in the push can be shown to be of it"
    CLASS=unreadable; return
  fi
  [ "$from" != "$to" ] || return 0
  if ! git merge-base --is-ancestor "$from" "$to" 2>/dev/null; then
    ev 1 history "history" "$(short "$to")" "the pushed head $(short "$to") does not descend from $(short "$from"), where the round began: the branch history was rewritten"
    CLASS=conflicted; return
  fi
  if ! commits=$(git rev-list --first-parent "$from..$to" 2>/dev/null); then
    unreadable "the commits from $(short "$from") to $(short "$to") could not be listed"
    CLASS=unreadable; return
  fi
  for c in $commits; do
    parents=$(git rev-list --parents -n 1 "$c" 2>/dev/null)
    set -- $parents
    shift
    n=$#
    if [ "$n" -eq 1 ]; then
      classify_own "$c" "$1" "$scope"
      continue
    fi
    subj=$(git log -1 --format=%s "$c" 2>/dev/null)
    if [ "$n" -ne 2 ]; then
      ev 1 merge "commit:$(short "$c")" "$(short "$c")" "\"$subj\" merges $n parents at once"
      continue
    fi
    if ! git merge-base --is-ancestor "$2" "$base" 2>/dev/null; then
      ev 1 merge "commit:$(short "$c")" "$(short "$c")" "\"$subj\" merges $(short "$2"), which is not on $base"
      continue
    fi
    BASE_MERGES=$((BASE_MERGES + 1))
    classify_merge "$c" "$1" "$2"
  done
  if awk -F'\t' '$1 == 1 { found = 1 } END { exit !found }' "$WORK/evidence"; then
    CLASS=conflicted
  elif [ "$BASE_MERGES" -gt 0 ]; then
    CLASS=clean
  fi
}

# The evidence rows as a JSON array.
evidence_json() {
  jq -Rsc 'split("\n") | map(select(length > 0) | split("\t")
    | {covered: (.[0] == "1"), kind: .[1], path: .[2], commit: .[3], detail: (.[4:] | join("\t"))})' "$WORK/evidence"
}

# --- classify ------------------------------------------------------------------
cmd_classify() {
  local from="" to="" base="" scope="with-work"
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)  from="${2:-}"; shift 2 ;;
      --to)    to="${2:-}"; shift 2 ;;
      --base)  base="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$from" ] && [ -n "$to" ] && [ -n "$base" ] || usage
  case "$scope" in merge-only|with-work) : ;; *) usage ;; esac
  classify "$from" "$to" "$base" "$scope"
  printf '%s\n' "$CLASS"
  [ -z "$READ_FAIL" ] || printf '%s\n' "$READ_FAIL"
  [ -n "$WORK" ] && [ -s "$WORK/evidence" ] && awk -F'\t' '{ printf "%s %s: %s\n", ($1 == 1 ? "audit" : "note "), $3, $5 }' "$WORK/evidence"
  return 0
}

# --- the hand-off's reading, shared by guard and coverage -----------------------
# Sets ROW, BEAD, ANCHOR, AROW, BRANCH, TARGET, SCOPE, FROM, TO and the round.
# rc: 0 a round to judge · 10 nothing to guard (printed) · 1 a read failed ·
# 3 nothing records where the work began
read_handoff() { # <bead> <to> <from-arg>
  local stamp
  BEAD="$1"; TO="$2"
  [ -n "$TO" ] || TO=$(git rev-parse -q --verify HEAD 2>/dev/null)
  [ -n "$TO" ] || { echo "$PROG: no pushed head to read; nothing is guarded and the caller retries" >&2; return 1; }
  TO=$(git rev-parse -q --verify "$TO^{commit}" 2>/dev/null) || { echo "$PROG: the pushed head $2 is not a commit here; nothing is guarded and the caller retries" >&2; return 1; }
  ROW=$(bd_json show "$BEAD")
  printf '%s' "$ROW" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { echo "$PROG: $BEAD could not be read; nothing is guarded and the caller retries" >&2; return 1; }
  ANCHOR=$(bca_anchor_of "$ROW") || { echo "$PROG: the beads on $BEAD's branch could not be listed, so its anchor is unknown; nothing is guarded and the caller retries" >&2; return 1; }
  if [ "$ANCHOR" = "$BEAD" ]; then
    AROW="$ROW"
  else
    AROW=$(bd_json show "$ANCHOR")
    printf '%s' "$AROW" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
      || { echo "$PROG: anchor $ANCHOR could not be read; nothing is guarded and the caller retries" >&2; return 1; }
  fi
  BRANCH=$(bca_meta "$ROW" branch); [ -n "$BRANCH" ] || BRANCH=$(bca_meta "$AROW" branch)
  if ! bca_reviewed "$AROW" "$ROW"; then
    echo "$PROG: ${BRANCH:-$BEAD} carries no review to keep current (anchor $ANCHOR is not gating and no PR stands on it); nothing to guard"
    return 10
  fi
  TARGET=$(bca_meta "$ROW" target); [ -n "$TARGET" ] || TARGET=$(bca_meta "$AROW" target)
  [ -n "$TARGET" ] || { echo "$PROG: neither $BEAD nor anchor $ANCHOR names the target the branch is brought current with; nothing is guarded and the caller retries" >&2; return 1; }
  SCOPE=$(bca_meta "$ROW" bring_current_scope)
  [ "$SCOPE" = "merge-only" ] || SCOPE="with-work"
  stamp=$(bca_meta "$ROW" bring_current_from)
  FROM="${stamp:-$3}"
  if [ -z "$stamp" ] && { [ -z "$FROM" ] || [ "$(git rev-parse -q --verify "$FROM^{commit}" 2>/dev/null)" = "$TO" ]; }; then
    echo "$PROG: nothing records where $BEAD's work on ${BRANCH:-its branch} began (no bring_current_from stamp, and nothing was pushed past ${FROM:-an unknown head} by this hand-off), so whether it brought the branch current cannot be read. Stamp the head the branch had before this bead's first commit or merge: gc bd update $BEAD --set-metadata bring_current_from=<oid>, then re-run" >&2
    return 3
  fi
  git fetch -q origin "+refs/heads/$TARGET:refs/remotes/origin/$TARGET" >/dev/null 2>&1 || true
  classify "$FROM" "$TO" "refs/remotes/origin/$TARGET" "$SCOPE"
  if [ "$CLASS" = "unreadable" ]; then
    echo "$PROG: the round $(short "$FROM")..$(short "$TO") could not be read ($READ_FAIL); nothing is guarded and the caller retries" >&2
    return 1
  fi
  if [ "$CLASS" = "none" ]; then
    echo "$PROG: $BEAD pushed no merge of $TARGET onto ${BRANCH:-its branch} past $(short "$FROM"); nothing to guard"
    return 10
  fi
  return 0
}

# The covered items the audit lacks, one "<path>\t<why>" per line: no entry, or
# an entry missing a field or a known rating.
missing_entries() { # <audit-json>
  evidence_json | jq -r --argjson a "$1" '
    [ .[] | select(.covered) | .path ] | unique | .[]
    | . as $p
    | ([ $a[]? | select(type == "object" and .path == $p) ] | .[0]) as $e
    | if $e == null then "\($p)\tno entry"
      elif ([$e.collided, $e.resolution, $e.check] | map((. // "") | tostring | length > 0) | all) | not then "\($p)\tthe entry lacks collided, resolution or check"
      elif ($e.rating != "routine" and $e.rating != "judgment") then "\($p)\tthe entry rating is \($e.rating // "absent"), not routine or judgment"
      else empty end' 2>/dev/null
}

coverage_report() { # <audit-json>
  evidence_json | jq -r --argjson a "$1" '
    [ .[] | select(.covered) ] | group_by(.path) | .[] | .[0] as $i
    | ([ $a[]? | select(type == "object" and .path == $i.path) ] | .[0]) as $e
    | (if $e == null then "NEEDS AN ENTRY" else "covered (\($e.rating // "?"))" end) as $s
    | "  \($s)  \($i.path): \($i.detail)"' 2>/dev/null
}

audit_of() { # <row-json>
  local a
  a=$(bca_meta_json "$1" conflict_audit)
  printf '%s' "$a" | jq -e 'type == "array"' >/dev/null 2>&1 || a='[]'
  printf '%s' "$a"
}

# --- coverage ------------------------------------------------------------------
cmd_coverage() {
  local bead="" to="" from_arg="" rc audit missing
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --to)   to="${2:-}"; shift 2 ;;
      --from) from_arg="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$bead" ] || usage
  read_handoff "$bead" "$to" "$from_arg"; rc=$?
  case "$rc" in 0) : ;; 10) return 0 ;; *) return "$rc" ;; esac
  if [ "$CLASS" = "clean" ]; then
    echo "$PROG: the round $(short "$FROM")..$(short "$TO") is clean: git merged $TARGET on its own, so it owes no entry"
    return 0
  fi
  audit=$(audit_of "$ROW")
  echo "$PROG: the round $(short "$FROM")..$(short "$TO") conflicted; each item and the audit entry it owes:"
  coverage_report "$audit"
  missing=$(missing_entries "$audit")
  [ -z "$missing" ] && return 0
  return 3
}

# --- guard ---------------------------------------------------------------------
cmd_guard() {
  local bead="" to="" from_arg="" rc audit missing ev_json existing same_round triage_prev round_at prior record cs reopened got
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --to)   to="${2:-}"; shift 2 ;;
      --from) from_arg="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$bead" ] || usage
  read_handoff "$bead" "$to" "$from_arg"; rc=$?
  case "$rc" in 0) : ;; 10) return 0 ;; *) return "$rc" ;; esac

  audit=$(audit_of "$ROW")
  if [ "$CLASS" = "conflicted" ]; then
    missing=$(missing_entries "$audit")
    if [ -n "$missing" ]; then
      {
        echo "$PROG: the audit on $BEAD does not cover the round $(short "$FROM")..$(short "$TO"), so it is not handed off. Each item and the entry it owes:"
        coverage_report "$audit"
        echo "Missing or incomplete:"
        printf '%s\n' "$missing" | awk -F'\t' '{ printf "  %s: %s\n", $1, $2 }'
        echo "Record each with: bring-current-audit.sh add --bead $BEAD --path <path> --collided <the two intents that met> --resolution <what was kept or written, and why> --check <what a reviewer should look at> --rating routine|judgment; then re-run the guard."
      } >&2
      return 3
    fi
  fi

  ev_json=$(evidence_json)
  existing=$(bca_meta_json "$AROW" bring_current_record)
  [ -n "$existing" ] || existing='null'
  same_round=$(printf '%s' "$existing" | jq -r --arg h "$TO" --arg b "$BEAD" \
    'if type == "object" and .head == $h and .bead == $b then "1" else "" end' 2>/dev/null)
  triage_prev='null'; round_at=""; prior='{"audit":[],"evidence":[]}'
  if [ -n "$same_round" ]; then
    triage_prev=$(printf '%s' "$existing" | jq -c '.triage // null')
    round_at=$(bca_meta "$AROW" bring_current_round_at)
    prior=$(printf '%s' "$existing" | jq -c '{audit: [ .audit[]? | select(.round != null) ], evidence: [ .evidence[]? | select(.round != null) ]}')
  elif printf '%s' "$existing" | jq -e 'type == "object" and .class == "conflicted" and .triage == null' >/dev/null 2>&1; then
    # An earlier round still awaiting triage: its account rides into this record,
    # tagged with its own head, so triage rules on everything it has not seen.
    prior=$(printf '%s' "$existing" | jq -c '(.head // "") as $h
      | {audit: [ .audit[]? | if .round == null then . + {round: $h} else . end ],
         evidence: [ .evidence[]? | if .round == null then . + {round: $h} else . end ],
         from: .from}')
  fi
  record=$(jq -nc --arg head "$TO" --arg from "$FROM" --arg target "$TARGET" \
    --arg base "$(git rev-parse -q --verify "refs/remotes/origin/$TARGET" 2>/dev/null)" \
    --arg bead "$BEAD" --arg class "$CLASS" --arg scope "$SCOPE" --arg at "$(now)" \
    --argjson ev "$ev_json" --argjson audit "$audit" --argjson triage "$triage_prev" --argjson prior "$prior" '
    ([ $ev[] | select(.covered) | .path ] | unique) as $paths
    | {head: $head, from: ($prior.from // $from), target: $target, base_oid: $base, bead: $bead,
       class: $class, scope: $scope, at: $at,
       evidence: ($ev + ($prior.evidence // [])),
       audit: ([ $audit[] | select(type == "object" and (.path as $p | $paths | index($p)) != null) ] + ($prior.audit // [])),
       triage: $triage }' 2>/dev/null)
  [ -n "$record" ] || { echo "$PROG: the round's record could not be composed; nothing is handed off and the caller retries" >&2; return 1; }
  # The record covers everything since the last round triage ruled on, so a
  # clean round that carries an earlier round still awaiting triage is filed as
  # conflicted: that triage is still owed.
  record=$(printf '%s' "$record" | jq -c 'if ([ .evidence[] | select(.covered) ] | length) > 0 then .class = "conflicted" else . end')

  if [ "$(printf '%s' "$record" | jq -r '.class')" = "clean" ]; then
    gc bd update "$ANCHOR" --set-metadata "bring_current_record=$record" >/dev/null 2>&1 || true
    got=$(bca_meta_json "$(bd_json show "$ANCHOR")" bring_current_record | jq -r '.head // ""' 2>/dev/null)
    [ "$got" = "$TO" ] || { echo "$PROG: the round's record did not read back on $ANCHOR; nothing is handed off and the caller retries" >&2; return 1; }
    echo "$PROG: bringing ${BRANCH:-the branch} current with $TARGET was clean (git merged it on its own, up to $(short "$TO")); recorded on $ANCHOR, nothing reopens"
    return 0
  fi

  if [ "$triage_prev" != "null" ]; then
    gc bd update "$ANCHOR" --set-metadata "bring_current_record=$record" >/dev/null 2>&1 || true
    got=$(bca_meta_json "$(bd_json show "$ANCHOR")" bring_current_record | jq -r '.head // ""' 2>/dev/null)
    [ "$got" = "$TO" ] || { echo "$PROG: the round's record did not read back on $ANCHOR; nothing is handed off and the caller retries" >&2; return 1; }
    echo "$PROG: the round up to $(short "$TO") is already recorded on $ANCHOR and triage has ruled on it; nothing more is owed"
    return 0
  fi

  # An empty check_set is stamped with the default, which declares triage. A
  # set that declares no triage lane (an operator's opt-out, or a set without
  # it) has no triage to reopen, so the round is recorded and owes no ruling.
  cs=$(bca_meta "$AROW" check_set | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d')
  if [ -n "$cs" ] && ! grep -qx -- "$TRIAGE_LANE" <<< "$cs"; then
    gc bd update "$ANCHOR" --set-metadata "bring_current_record=$record" >/dev/null 2>&1 || true
    got=$(bca_meta_json "$(bd_json show "$ANCHOR")" bring_current_record | jq -r '.head // ""' 2>/dev/null)
    [ "$got" = "$TO" ] || { echo "$PROG: the round's record did not read back on $ANCHOR; nothing is handed off and the caller retries" >&2; return 1; }
    echo "$PROG: bringing ${BRANCH:-the branch} current conflicted; the audit is recorded on $ANCHOR, whose check_set ('$(bca_meta "$AROW" check_set)') declares no triage lane, so no ruling is owed"
    return 0
  fi
  reopened=$(printf '%s,%s' "$(bca_meta "$AROW" bring_current_reopened)" "$TRIAGE_LANE" \
    | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d' | awk '!seen[$0]++' | paste -sd, -)
  [ -n "$round_at" ] || round_at=$(now)
  # The reopened lanes and the round's time land with the record, before the
  # triage lane loses its backing: from the moment the backing goes, no approval
  # older than the round vouches for the lane, so the merge cannot slip past it.
  gc bd update "$ANCHOR" --set-metadata "bring_current_record=$record" \
    --set-metadata "bring_current_reopened=$reopened" --set-metadata "bring_current_round_at=$round_at" >/dev/null 2>&1 || true
  got=$(bd_json show "$ANCHOR")
  if [ "$(bca_meta_json "$got" bring_current_record | jq -r '.head // ""' 2>/dev/null)" != "$TO" ] \
     || [ "$(bca_meta "$got" bring_current_reopened)" != "$reopened" ] \
     || [ "$(bca_meta "$got" bring_current_round_at)" != "$round_at" ]; then
    echo "$PROG: the round's record did not read back on $ANCHOR; nothing is handed off and the caller retries" >&2
    return 1
  fi
  if ! "$REVIEW_OUTCOME" supersede-lane --anchor "$ANCHOR" --lane "$TRIAGE_LANE" \
       --reason "bring-current round up to $(short "$TO") conflicted; triage decides what it reopens" >/dev/null; then
    echo "$PROG: the triage lane on $ANCHOR could not be reopened; nothing is handed off and the caller retries" >&2
    return 1
  fi
  echo "$PROG: bringing ${BRANCH:-the branch} current with $TARGET conflicted (up to $(short "$TO")); the audit and evidence are recorded on $ANCHOR, and triage is reopened to decide what the round reopens"
  return 0
}

# --- dismiss -------------------------------------------------------------------
# Dismiss the standing approvals on the anchor's PR, the re-ask visit first.
# rc 0 nothing stood, or the visit holds the merge · 1 nothing was dismissed and
# the caller retries.
dismiss_approvals() { # <anchor> <anchor-row> <record-json>
  local anchor="$1" arow="$2" record="$3" url num host repo self reviews approvals logins noun key msg dmsg rows visit failed="" dismissed="" rid login
  url=$(bca_meta "$arow" pr_url); [ -n "$url" ] || url=$(bca_meta "$arow" existing_pr)
  num=$(bca_meta "$arow" pr_number)
  [ -n "$num" ] || num=$(printf '%s' "$url" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')
  if [ -z "$url" ] || [ -z "$num" ]; then
    echo "$PROG: no PR stands on $anchor, so no approval stands to dismiss"
    return 0
  fi
  host=$(printf '%s' "$url" | sed -n 's#^https://\([^/]*\)/[^/]*/[^/]*/pull/[0-9][0-9]*.*#\1#p')
  repo=$(printf '%s' "$url" | sed -n 's#^https://[^/]*/\([^/]*/[^/]*\)/pull/[0-9][0-9]*.*#\1#p')
  if [ -z "$host" ] || [ -z "$repo" ] || [ "$(printf '%s' "$url" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')" != "$num" ]; then
    echo "$PROG: $anchor names PR#$num but its pr_url '$url' does not; nothing is dismissed and the caller retries" >&2
    return 1
  fi
  self=$(gh api --hostname "$host" user --jq '.login' 2>/dev/null)
  if [ -z "$self" ]; then
    echo "$PROG: the acting login is unresolved, so an outside approval cannot be told from the city's own; nothing is dismissed and the caller retries" >&2
    return 1
  fi
  if ! reviews=$(gh api --hostname "$host" --paginate "repos/$repo/pulls/$num/reviews?per_page=100" --jq '.[]' 2>/dev/null); then
    echo "$PROG: PR#$num's reviews could not be read; nothing is dismissed and the caller retries" >&2
    return 1
  fi
  approvals=$(printf '%s' "$reviews" | scrub | jq -sc --arg self "$self" "$REVIEW_VERDICT_DEF"'
    [ standing_approvals($self)[] | {id: (.id // 0), login: (.user.login // "")} | select(.id != 0 and .login != "") ]' 2>/dev/null)
  if [ -z "$approvals" ]; then
    echo "$PROG: PR#$num's reviews did not parse; nothing is dismissed and the caller retries" >&2
    return 1
  fi
  if [ "$approvals" = "[]" ]; then
    echo "$PROG: triage ruled the approval on PR#$num dismissed, but no approval stands to dismiss"
    return 0
  fi
  logins=$(printf '%s' "$approvals" | jq -r '[ .[].login ] | unique | if length > 1 then (.[:-1] | join(", ")) + " and " + .[-1] else .[0] end')
  if [ "$(printf '%s' "$approvals" | jq 'length')" -gt 1 ]; then noun="approvals"; else noun="approval"; fi

  key="bring-current-dismissal.$num.$(printf '%s' "$record" | jq -r '.head // ""')"
  msg=$(bca_render_record "$record" visit "$num" "$url" "$logins")
  [ -n "$msg" ] || { echo "$PROG: the re-ask visit could not be composed; nothing is dismissed and the caller retries" >&2; return 1; }
  if ! "$ESCALATE" --subject "$anchor" --key "$key" --message "$msg"; then
    echo "$PROG: the visit on $anchor did not land; the $noun is NOT dismissed, so it is never cleared without a signal, and the caller retries" >&2
    return 1
  fi
  if ! rows=$(bd_list --status="$LIVE_STATUSES" --metadata-field "escalation_key=$key" --metadata-field "gc.continuation_group=$anchor"); then
    echo "$PROG: the visit on $anchor could not be read back; nothing is dismissed and the caller retries" >&2
    return 1
  fi
  visit=$(printf '%s' "$rows" | jq -r --arg s "$anchor" --arg k "$key" '
    [ .[] | select(((.metadata["gc.continuation_group"] // "") | tostring) == $s)
          | select(((.metadata.escalation_key // "") | tostring) == $k) | .id ] | .[0] // empty' 2>/dev/null)
  if [ -z "$visit" ]; then
    echo "$PROG: escalate.sh left no open visit for this dismissal (a sitting has already answered it), so the $noun from $logins stays standing"
    return 0
  fi

  dmsg=$(bca_render_record "$record" dismissal "$num" "$url" "$logins")
  [ "${#dmsg}" -le 2000 ] || dmsg="${dmsg:0:1990}…"
  while IFS= read -r login; do
    [ -n "$login" ] || continue
    gh api --hostname "$host" -X POST "repos/$repo/pulls/$num/requested_reviewers" \
      -f "reviewers[]=$login" </dev/null >/dev/null 2>&1 || failed="$failed; $login was not re-requested"
  done <<APPROVERS
$(printf '%s' "$approvals" | jq -r '[ .[].login ] | unique | .[]')
APPROVERS
  while IFS=$'\t' read -r rid login; do
    [ -n "$rid" ] || continue
    if gh api --hostname "$host" -X PUT "repos/$repo/pulls/$num/reviews/$rid/dismissals" \
         -f message="$dmsg" </dev/null >/dev/null 2>&1; then
      dismissed="$dismissed${dismissed:+, }$login"
    else
      failed="$failed; the approval from $login (review $rid) could not be dismissed"
    fi
  done <<APPROVALS
$(printf '%s' "$approvals" | jq -r '.[] | "\(.id)\t\(.login)"')
APPROVALS
  if [ -n "$failed" ]; then
    gc bd update "$visit" --append-notes "Not every write on GitHub landed: ${failed#; }. Any approval still showing there predates what triage ruled on this bring-current, and this visit holds the merge until it closes." >/dev/null 2>&1 \
      || echo "$PROG: WARN the dismissal failures could not be noted on visit $visit" >&2
    echo "$PROG: visit $visit holds PR#$num's merge; dismissed: ${dismissed:-none}; not cleared: ${failed#; }" >&2
    return 0
  fi
  echo "$PROG: visit $visit holds PR#$num's merge, and the $noun from $logins dismissed"
  return 0
}

# --- decide --------------------------------------------------------------------
# Triage's ruling on a conflicted round, run by signoff.sh before it records the
# triage verdict. rc 0 recorded and carried out · 1 refused, nothing written ·
# 2 a write did not land; the review stays open and the same call retries.
cmd_decide() {
  local anchor="" review="" reopen="" add="" dismiss="" reason="" body_out="" arow record decided tokens lane bad="" lanes_json add_json triage new reopened got num url
  while [ $# -gt 0 ]; do
    case "$1" in
      --anchor)           anchor="${2:-}"; shift 2 ;;
      --review-bead)      review="${2:-}"; shift 2 ;;
      --reopen)           reopen="${2:-}"; shift 2 ;;
      --add)              add="${2:-}"; shift 2 ;;
      --dismiss-approval) dismiss=1; shift ;;
      --reason)           reason="${2:-}"; shift 2 ;;
      --body-out)         body_out="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$anchor" ] && [ -n "$review" ] && [ -n "$reopen" ] || usage
  reason=$(bca_flat "$reason")
  [ -n "$reason" ] || { echo "$PROG: a ruling on a bring-current round says why (--reason); nothing written" >&2; return 1; }
  arow=$(bd_json show "$anchor")
  printf '%s' "$arow" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1 \
    || { echo "$PROG: anchor $anchor could not be read; nothing written" >&2; return 2; }
  record=$(bca_meta_json "$arow" bring_current_record)
  printf '%s' "$record" | jq -e 'type == "object" and .class == "conflicted"' >/dev/null 2>&1 \
    || { echo "$PROG: anchor $anchor carries no conflicted bring-current round for triage to rule on; nothing written" >&2; return 1; }
  decided=$(printf '%s' "$record" | jq -r '.triage.review // ""')
  if [ -n "$decided" ] && [ "$decided" != "$review" ]; then
    echo "$PROG: the round on $anchor up to $(printf '%s' "$record" | jq -r '.head // "" | .[0:12]') was already ruled on by $decided; nothing written" >&2
    return 1
  fi

  # The lanes a ruling may reopen are the ones the anchor declares. A lane it
  # does not declare has no review to run again; triage adds one with --add-gates.
  tokens=$(bca_meta "$arow" check_set | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d')
  [ "$reopen" = "none" ] && reopen=""
  for lane in $(printf '%s' "$reopen" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d'); do
    case "$lane" in none|off|approval) bad="${bad:+$bad, }$lane"; continue ;; esac
    printf '%s\n' "$tokens" | grep -qx -- "$lane" || bad="${bad:+$bad, }$lane"
  done
  if [ -n "$bad" ]; then
    echo "$PROG: --reopen names $bad, which $anchor's check_set ('$(bca_meta "$arow" check_set)') does not declare as a review lane; nothing written" >&2
    return 1
  fi
  lanes_json=$(printf '%s' "$reopen" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d' | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')
  add_json=$(printf '%s' "$add" | tr ',' '\n' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d' | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')
  if [ -n "$decided" ]; then
    # A retry of the same ruling carries out what was recorded.
    lanes_json=$(printf '%s' "$record" | jq -c '.triage.reopen // []')
    add_json=$(printf '%s' "$record" | jq -c '.triage.add // []')
    [ "$(printf '%s' "$record" | jq -r '.triage.dismiss')" = "true" ] && dismiss=1 || dismiss=""
    triage=$(printf '%s' "$record" | jq -c '.triage')
  else
    triage=$(jq -nc --arg r "$review" --argjson l "$lanes_json" --argjson a "$add_json" \
      --argjson d "$([ -n "$dismiss" ] && echo true || echo false)" --arg why "$reason" --arg at "$(now)" \
      '{review: $r, reopen: $l, add: $a, dismiss: $d, reason: $why, at: $at}')
  fi
  new=$(printf '%s' "$record" | jq -c --argjson t "$triage" '.triage = $t')
  reopened=$(printf '%s\n%s\n%s' "$(bca_meta "$arow" bring_current_reopened | tr ',' '\n')" \
      "$(printf '%s' "$lanes_json" | jq -r '.[]')" "$(printf '%s' "$add_json" | jq -r '.[]')" \
    | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]//g; /^$/d' | awk '!seen[$0]++' | paste -sd, -)
  gc bd update "$anchor" --set-metadata "bring_current_record=$new" --set-metadata "bring_current_reopened=$reopened" >/dev/null 2>&1 || true
  got=$(bd_json show "$anchor")
  if [ "$(bca_meta_json "$got" bring_current_record | jq -r '.triage.review // ""' 2>/dev/null)" != "$review" ] \
     || [ "$(bca_meta "$got" bring_current_reopened)" != "$reopened" ]; then
    echo "$PROG: triage's ruling did not read back on $anchor; the review stays open and the same call retries" >&2
    return 2
  fi
  for lane in $(printf '%s' "$lanes_json" | jq -r '.[]'); do
    if ! "$REVIEW_OUTCOME" supersede-lane --anchor "$anchor" --lane "$lane" \
         --reason "bring-current round up to $(printf '%s' "$new" | jq -r '.head // "" | .[0:12]') reopened by triage $review" >/dev/null; then
      echo "$PROG: lane $lane on $anchor could not be reopened; the review stays open and the same call retries" >&2
      return 2
    fi
  done
  if [ -n "$dismiss" ]; then
    dismiss_approvals "$anchor" "$got" "$new" || return 2
  fi
  if [ -n "$body_out" ]; then
    num=$(bca_meta "$got" pr_number); url=$(bca_meta "$got" pr_url)
    bca_render_record "$new" comment "$num" "$url" > "$body_out" || { echo "$PROG: the round's account could not be rendered; the review stays open and the same call retries" >&2; return 2; }
  fi
  echo "$PROG: triage's ruling on $anchor's bring-current round recorded: reopened $(printf '%s' "$lanes_json" | jq -r 'if length == 0 then "nothing" else join(", ") end')$([ -n "$dismiss" ] && echo ", approval dismissal requested")"
  return 0
}

case "${1:-}" in
  guard)    shift; cmd_guard "$@" ;;
  coverage) shift; cmd_coverage "$@" ;;
  classify) shift; cmd_classify "$@" ;;
  decide)   shift; cmd_decide "$@" ;;
  *) usage ;;
esac
