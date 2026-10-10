#!/usr/bin/env bash
# bring-current-guard — keeps an approval from covering code it never saw. A
# merge-in child (the bead pr-facts.sh's conflict arm files for an approved PR
# whose branch conflicts) brings the branch current with its base. When that
# took no judgment, the approval still describes the code that would land, and
# it stands: main's ruleset does not dismiss stale reviews on push. When it took
# judgment, this files a visit on the anchor and dismisses the approval, so the
# operator re-reviews what changed instead of landing it under the old approval.
#
# Called by submit-and-exit (formulas/mol-polecat-work.toml) right after the
# push is verified, for every bead it hands off; any bead but a merge-in child of
# an open PR is left alone.
#
# THE BOUNDARY. A bring-current is MECHANICAL when every commit it adds to the
# branch is a merge of the base whose result is the one git produces on its own,
# except where git stopped on a conflict. A conflict is mechanical only where
# both sides inserted lines at one place and replaced nothing the merge base
# had there, and the resolution keeps the two inserted blocks whole, one after
# the other, in either order. Each block is compared as git reads it with no
# common lines hoisted out, so two blocks that end in the same `fi` keep a `fi`
# each, and only blank lines may differ. Paths in the generated tier
# (linguist-generated in .gitattributes) are exempt: they are renders the pack
# writes and nobody edits by hand, and merge.sh refuses a merge whose
# seed-audit render is not current.
# Everything else is JUDGMENT, and so is anything this cannot establish:
#   - a commit of its own on the branch (a fix-up, a rename, a test repair);
#   - a merge of anything but the base, or of more than two parents;
#   - a change to a file the merge did not conflict on;
#   - a conflict where both sides changed lines the merge base had, however it
#     was resolved, or one resolved by choosing a side, interleaving the two
#     blocks, rewriting, or dropping a line;
#   - a conflict over a deleted, renamed, binary or mode-changed file;
#   - a history it cannot read, or no record of where the bring-current began.
#
# ORDER. On judgment over a standing approval, the visit is filed first and read
# back: it holds the anchor's merge (finalize-gate.sh) and tells the operator
# why, so no dismissal strands a PR without a signal. Each approving account is
# then re-requested and its approval dismissed, the order pr-facts.sh uses when
# it clears a human review. A dismissal that does not land is noted on the
# visit, which still holds the merge.
#
# Usage:
#   bring-current-guard.sh guard --bead <id> [--to <oid>] [--from <oid>]
#   bring-current-guard.sh classify --from <oid> --to <oid> --base <ref>
# guard: <id> is the bead being handed off and --to the pushed head (default
# HEAD). The bead's bring_current_from, stamped where its resume began, marks
# where the bring-current started; --from, the origin head before the push,
# stands in when that stamp is absent.
# classify: prints `mechanical` or `judgment`, then one reason per line.
# Both read the git repository of the working directory.
# Exit: 0 nothing owed, or the visit that holds the merge landed · 1 a read
# failed or the visit did not land, so nothing was dismissed and the caller
# retries · 2 usage
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
# shellcheck source=bd-lib.sh
. "${GC_BD_LIB:-$SCRIPTS_DIR/bd-lib.sh}" || { echo "$PROG: cannot source bd-lib.sh beside this script" >&2; exit 2; }
# The approval rule merge.sh lands on: standing_approvals($self) is one review per
# approving account other than the city's.
# shellcheck source=review-verdict.sh
. "$SCRIPTS_DIR/review-verdict.sh" || { echo "$PROG: cannot source review-verdict.sh beside this script" >&2; exit 2; }

LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"
TAB=$(printf '\t')
# How many reasons a visit or a dismissal message lists before it counts the rest.
MAX_REASONS=8

usage() {
  echo "usage: $PROG guard --bead <id> [--to <oid>] [--from <oid>]" >&2
  echo "       $PROG classify --from <oid> --to <oid> --base <ref>" >&2
  exit 2
}

WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

VERDICT="mechanical"; REASONS=""
judge() { VERDICT="judgment"; REASONS="${REASONS:+$REASONS
}$*"; }
short() { git rev-parse --short=12 "$1" 2>/dev/null || printf '%s' "$1"; }

EMPTY_BLOB=""
empty_blob() {
  [ -n "$EMPTY_BLOB" ] || EMPTY_BLOB=$(git hash-object -w --stdin </dev/null 2>/dev/null)
  printf '%s' "$EMPTY_BLOB"
}

# NUL-separated paths on stdin, the ones .gitattributes at <commit> does not mark
# linguist-generated on stdout, NUL-separated. An attribute read that fails
# exempts nothing, so every path goes on to be judged.
reviewed_paths() { # <commit>
  cat > "$WORK/paths"
  if ! git check-attr -z --stdin --source "$1" linguist-generated <"$WORK/paths" >"$WORK/attrs" 2>/dev/null; then
    cat "$WORK/paths"
    return
  fi
  while IFS= read -r -d '' p && IFS= read -r -d '' _attr && IFS= read -r -d '' val; do
    [ "$val" = "set" ] || printf '%s\0' "$p"
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
# `base` when a hunk replaced lines the base had; `differ` when the resolution
# is anything else; `unreadable` when no diff3 hunk could be read.
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
  local c="$1" tree="$2" p="$3" st="$4" s stages="" mode="" base="" ours="" theirs="" rmode res hunks
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
    judge "$(short "$c"): $p conflicted over a file one side deleted or renamed, so keeping it or not was a choice"
    return ;;
  esac
  case "$mode" in 100644|100755) : ;; *)
    judge "$(short "$c"): $p conflicted over its file mode or type"
    return ;;
  esac
  rmode=$(git ls-tree "$c" -- "$p" 2>/dev/null | awk '{print $1}')
  res=$(git rev-parse -q --verify "${c}:${p}" 2>/dev/null)
  if [ -z "$res" ] || [ "$rmode" != "$mode" ]; then
    judge "$(short "$c"): $p conflicted and the merge deleted it or changed its mode"
    return
  fi
  [ -n "$base" ] || base=$(empty_blob)
  if is_binary "$base" || is_binary "$ours" || is_binary "$theirs" || is_binary "$res"; then
    judge "$(short "$c"): $p is a binary file in conflict"
    return
  fi
  git cat-file blob "${tree}:${p}" > "$WORK/replay" 2>/dev/null
  git cat-file blob "$res" > "$WORK/resolution" 2>/dev/null
  hunks=$(awk -v M="$MARK" "$HUNK_MATCH_AWK" "$WORK/replay" "$WORK/resolution" 2>/dev/null)
  case "$hunks" in
    ok) : ;;
    base) judge "$(short "$c"): $p conflicted where both sides changed lines the merge base had, so the resolution had to choose" ;;
    differ) judge "$(short "$c"): $p conflicted, and the resolution is not the two sides' insertions kept whole (it chose a side, interleaved them, rewrote, or dropped a line)" ;;
    *) judge "$(short "$c"): $p conflicted, and its conflict could not be read back" ;;
  esac
}

# One merge commit <c> = <p1> (the branch) + <p2>, replayed with git's own merge.
classify_merge() { # <c> <p1> <p2>
  local c="$1" p1="$2" p2="$3" out rc tree entry meta p stg diffs
  out="$WORK/merge-tree.$c"
  # diff3 markers show what the merge base had in each hunk, and MARK-long
  # markers cannot collide with a line of the file. Neither changes which paths
  # conflict or what git merges cleanly.
  [ -f "$WORK/attributes" ] || printf '* conflict-marker-size=%s\n' "$MARK" > "$WORK/attributes"
  git -c core.attributesFile="$WORK/attributes" -c merge.conflictStyle=diff3 \
    merge-tree --write-tree -z --no-messages "$p1" "$p2" >"$out" 2>/dev/null
  rc=$?
  if [ "$rc" -gt 1 ]; then
    judge "$(short "$c"): its merge could not be replayed to compare against"
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
    judge "$(short "$c"): its merge could not be replayed to compare against"
    return
  fi
  # Every path the merge commit carries differently from git's own result.
  diffs="$WORK/diffs.$c"
  if ! git diff-tree -r -z --no-renames --name-only "$tree" "$c" >"$diffs" 2>/dev/null; then
    judge "$(short "$c"): its tree could not be compared with the replayed merge"
    return
  fi
  # A conflicted path is judged by its resolution whether or not it differs from
  # the replayed markers; any other differing path is an edit the merge did not
  # need. The generated tier is left out of both.
  awk -F'\t' '{print $1}' "$WORK/conflicts" | sort -u | tr '\n' '\0' > "$WORK/cpaths"
  { cat "$diffs"; cat "$WORK/cpaths"; } | reviewed_paths "$c" | sort -zu > "$WORK/judged"
  while IFS= read -r -d '' p; do
    stg=$(P="$p" awk -F'\t' '$1 == ENVIRON["P"] { printf "%s ", $2 }' "$WORK/conflicts")
    if [ -n "$stg" ]; then
      classify_conflict "$c" "$tree" "$p" "$stg"
    else
      judge "$(short "$c"): $p changed beyond what merging $(short "$p2") produces"
    fi
  done < "$WORK/judged"
}

# The commits <to> adds over <from> along the branch's own line, each judged.
classify() { # <from> <to> <base-ref>
  local from="$1" to="$2" base="$3" c commits parents p1 p2 n subj
  VERDICT="mechanical"; REASONS=""
  [ -n "$WORK" ] || WORK=$(mktemp -d "${TMPDIR:-/tmp}/gctk-bring-current-guard.XXXXXX") || { judge "no scratch directory to replay the merge in"; return; }
  from=$(git rev-parse -q --verify "$from^{commit}" 2>/dev/null) || { judge "the start of the bring-current ($1) is not a commit here"; return; }
  to=$(git rev-parse -q --verify "$to^{commit}" 2>/dev/null) || { judge "the pushed head ($2) is not a commit here"; return; }
  if ! git rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    judge "the base $base could not be read, so no merge in the push can be shown to be of it"
    return
  fi
  if [ "$from" = "$to" ]; then
    REASONS="nothing was pushed past $(short "$from")"
    return
  fi
  if ! git merge-base --is-ancestor "$from" "$to" 2>/dev/null; then
    judge "the pushed head $(short "$to") does not descend from $(short "$from"): the branch history was rewritten"
    return
  fi
  if ! commits=$(git rev-list --first-parent "$from..$to" 2>/dev/null); then
    judge "the commits from $(short "$from") to $(short "$to") could not be listed"
    return
  fi
  for c in $commits; do
    parents=$(git rev-list --parents -n 1 "$c" 2>/dev/null)
    set -- $parents
    shift
    n=$#
    subj=$(git log -1 --format=%s "$c" 2>/dev/null)
    if [ "$n" -eq 1 ]; then
      if ! git diff-tree -r -z --no-renames --name-only "$1" "$c" >"$WORK/own" 2>/dev/null; then
        judge "$(short "$c") \"$subj\" is a commit of its own, and what it changed could not be read"
      elif [ -n "$(reviewed_paths "$c" <"$WORK/own" | tr '\0' '\n')" ]; then
        judge "$(short "$c") \"$subj\" is a commit of its own, not part of a merge"
      fi
      continue
    fi
    if [ "$n" -ne 2 ]; then
      judge "$(short "$c") \"$subj\" merges $n parents at once"
      continue
    fi
    p1="$1"; p2="$2"
    if ! git merge-base --is-ancestor "$p2" "$base" 2>/dev/null; then
      judge "$(short "$c") \"$subj\" merges $(short "$p2"), which is not on $base"
      continue
    fi
    classify_merge "$c" "$p1" "$p2"
  done
  if [ "$VERDICT" = "mechanical" ]; then
    REASONS="every commit past $(short "$from") is a merge of $base that git made, or whose conflicts keep both sides' insertions whole"
  fi
}

# The first MAX_REASONS reasons as "- " lines, and a count of the rest.
reason_lines() {
  printf '%s\n' "$REASONS" | awk -v max="$MAX_REASONS" 'NF { n++; if (n <= max) print "- " $0 } END { if (n > max) print "- and " (n - max) " more" }'
}

# --- classify ------------------------------------------------------------------
cmd_classify() {
  local from="" to="" base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="${2:-}"; shift 2 ;;
      --to)   to="${2:-}"; shift 2 ;;
      --base) base="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$from" ] && [ -n "$to" ] && [ -n "$base" ] || usage
  classify "$from" "$to" "$base"
  printf '%s\n' "$VERDICT"
  [ -z "$REASONS" ] || printf '%s\n' "$REASONS"
  return 0
}

# --- guard ---------------------------------------------------------------------
cmd_guard() {
  local bead="" to="" from_arg="" row title branch target num url anchor stamp from base
  while [ $# -gt 0 ]; do
    case "$1" in
      --bead) bead="${2:-}"; shift 2 ;;
      --to)   to="${2:-}"; shift 2 ;;
      --from) from_arg="${2:-}"; shift 2 ;;
      *) usage ;;
    esac
  done
  [ -n "$bead" ] || usage
  [ -n "$to" ] || to=$(git rev-parse -q --verify HEAD 2>/dev/null)
  [ -n "$to" ] || { echo "$PROG: no pushed head to read; nothing is guarded and the caller retries" >&2; return 1; }

  row=$(bd_json show "$bead" | jq -c '.[0] | select(type == "object")' 2>/dev/null)
  [ -n "$row" ] || { echo "$PROG: $bead could not be read; nothing is guarded and the caller retries" >&2; return 1; }
  title=$(printf '%s' "$row" | jq -r '.title // ""')
  branch=$(printf '%s' "$row" | jq -r '(.metadata.branch // "") | tostring')
  target=$(printf '%s' "$row" | jq -r '(.metadata.target // "") | tostring')
  num=$(printf '%s' "$row" | jq -r '(.metadata.pr_number // "") | tostring')
  url=$(printf '%s' "$row" | jq -r '(.metadata.pr_url // .metadata.existing_pr // "") | tostring')
  anchor=$(printf '%s' "$row" | jq -r '(.metadata.anchor_bead // "") | tostring')
  stamp=$(printf '%s' "$row" | jq -r '(.metadata.bring_current_from // "") | tostring')
  # A merge-in child carries the title pr-facts.sh composes from its own PR,
  # branch and base, the key its orphan adoption matches on.
  case "$num" in ''|*[!0-9]*) num="" ;; esac
  if [ -z "$num" ] || [ -z "$branch" ] || [ -z "$target" ] \
     || [ "${title#"Merge $target into PR#$num (branch $branch):"}" = "$title" ]; then
    echo "$PROG: $bead is not a merge-in child of an open PR; nothing to guard"
    return 0
  fi

  # The stamp marks where this bead's bring-current began, so a head that does
  # not descend from it is a rewritten history, which classify judges.
  from="${stamp:-$from_arg}"
  git fetch -q origin "+refs/heads/$target:refs/remotes/origin/$target" >/dev/null 2>&1 || true
  base="refs/remotes/origin/$target"
  if [ -n "$from" ]; then
    classify "$from" "$to" "$base"
  else
    VERDICT="judgment"
    REASONS="nothing records where this bring-current began, so what it changed cannot be read"
  fi
  if [ "$VERDICT" = "mechanical" ]; then
    echo "$PROG: PR#$num's bring-current took no judgment: $REASONS. Any approval stands."
    return 0
  fi

  # Judgment. Whether it costs an approval depends on whether one stands.
  local host repo self reviews approvals logins noun covers them are key msg dmsg visit rows failed="" dismissed="" rid login
  host=$(printf '%s' "$url" | sed -n 's#^https://\([^/]*\)/[^/]*/[^/]*/pull/[0-9][0-9]*.*#\1#p')
  repo=$(printf '%s' "$url" | sed -n 's#^https://[^/]*/\([^/]*/[^/]*\)/pull/[0-9][0-9]*.*#\1#p')
  if [ -z "$host" ] || [ -z "$repo" ] || [ "$(printf '%s' "$url" | sed -n 's#.*/pull/\([0-9][0-9]*\).*#\1#p')" != "$num" ]; then
    echo "$PROG: $bead names PR#$num but its pr_url '$url' does not; nothing is dismissed and the caller retries" >&2
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
    echo "$PROG: PR#$num's bring-current took judgment, but no approval stands to dismiss; the next review sees the change"
    return 0
  fi
  logins=$(printf '%s' "$approvals" | jq -r '[ .[].login ] | if length > 1 then (.[:-1] | join(", ")) + " and " + .[-1] else .[0] end')
  if [ "$(printf '%s' "$approvals" | jq 'length')" -gt 1 ]; then
    noun="approvals"; covers="cover"; them="them"; are="are"
  else
    noun="approval"; covers="covers"; them="it"; are="is"
  fi

  if [ -z "$anchor" ]; then
    rows=$(bd_list --status=open --metadata-field branch="$branch") || rows=""
    anchor=$(printf '%s' "$rows" | jq -r --arg self "$bead" '
      [ .[]? | select(.id != $self) | select((((.metadata // {}).merge_result // "") | tostring) != "") ]
      | sort_by(.created_at // .created // .id) | .[0].id // empty' 2>/dev/null)
  fi
  if [ -z "$anchor" ]; then
    echo "$PROG: PR#$num's anchor could not be resolved, so there is no bead to file the visit on; nothing is dismissed and the caller retries" >&2
    return 1
  fi

  key="bring-current-judgment.$num.$to"
  msg="PR#$num $noun dismissed: bringing it current with $target took judgment
Bringing PR#$num ($url) current with $target changed the approved code in ways git does not make on its own, so the $noun from $logins no longer $covers what would land. The city dismisses $them and asks for the review again.

What the bring-current changed beyond a mechanical merge, up to pushed head $(short "$to"):
$(reason_lines)

Your call: review the change on the PR and approve again to let it land, or say what to change. This visit holds the merge while it is open."
  if ! "$ESCALATE" --subject "$anchor" --key "$key" --message "$msg"; then
    echo "$PROG: the visit on $anchor did not land; the approval is NOT dismissed, so it is never cleared without a signal, and the caller retries" >&2
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
    echo "$PROG: escalate.sh left no open visit for this bring-current (a sitting has already answered it), so the $noun from $logins $are left standing"
    return 0
  fi

  dmsg="Bringing this branch current with $target took judgment (pushed head $(short "$to")), so this approval no longer covers the code that would land: $(printf '%s\n' "$REASONS" | awk -v max="$MAX_REASONS" 'NF { n++; if (n <= max) printf "%s%s", (n > 1 ? "; " : ""), $0 } END { if (n > max) printf "; and %d more", n - max }'). Please review the change and approve again."
  while IFS=$'\t' read -r rid login; do
    [ -n "$rid" ] || continue
    gh api --hostname "$host" -X POST "repos/$repo/pulls/$num/requested_reviewers" \
      -f "reviewers[]=$login" </dev/null >/dev/null 2>&1 || failed="$failed; $login was not re-requested"
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
    gc bd update "$visit" --append-notes "Not every write on GitHub landed: ${failed#; }. Any approval still showing there predates the judgment this bring-current took, and this visit holds the merge until it closes." >/dev/null 2>&1 \
      || echo "$PROG: WARN the dismissal failures could not be noted on visit $visit" >&2
    echo "$PROG: PR#$num's bring-current took judgment; visit $visit holds the merge; dismissed: ${dismissed:-none}; not cleared: ${failed#; }" >&2
    return 0
  fi
  echo "$PROG: PR#$num's bring-current took judgment; visit $visit holds the merge, and the $noun from $logins $are dismissed"
  return 0
}

case "${1:-}" in
  classify) shift; cmd_classify "$@" ;;
  guard)    shift; cmd_guard "$@" ;;
  *) usage ;;
esac
