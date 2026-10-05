#!/usr/bin/env bash
# Tests for stale-branch-triage.sh against a real bare origin.
#
# The sweep mutates origin refs, so like worktree-reap.test.sh this suite drives
# REAL git — it sources test-harness.sh for the assertions only (harness_init
# would stub git out) and asserts on the origin's actual ref state, with a KEEP
# beside every TAKE in one run: "acted on everything" and "acted on nothing"
# print the same count, so a survivor-only check proves nothing about the filter.
#
# The origin is a bare repo. `git remote get-url` would apply url.insteadOf, but
# the SUT reads identity through `git config --get remote.origin.url`, so origin
# can carry a github slug (for the slug parse) while insteadOf points transport
# at the bare. Origin writes (create tag, delete ref) go through a fake `gh api`
# that operates on the bare directly; origin reads (ls-remote) are real git.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-stale-branch-triage-test.XXXXXX")"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub out git
PASS=0; FAIL=0

# The SUT resolves siblings (patrol-finding.sh) from its own dir, so run a COPY
# next to a fake filer rather than the shipped one.
SCR="$TMP/scripts"; mkdir -p "$SCR"
cp "$HERE/stale-branch-triage.sh" "$SCR/stale-branch-triage.sh"
SUT="$SCR/stale-branch-triage.sh"
FINDINGS="$TMP/findings.log"
cat > "$SCR/patrol-finding.sh" <<'STUB'
#!/usr/bin/env bash
set -u
[ "${STUB_FINDING_RC:-0}" = 0 ] || { echo "patrol-finding: simulated failure" >&2; exit "${STUB_FINDING_RC}"; }
printf '%s\n' "$*" >> "${FINDINGS:?}"
STUB
chmod +x "$SCR/patrol-finding.sh"

BIN="$TMP/bin"; mkdir -p "$BIN"
BARE="$TMP/origin.git"
WORK="$TMP/work"
STUB_STATUSES="$TMP/statuses.json"
STUB_LIVE="$TMP/live.json"
STUB_PR="$TMP/pr.txt"

export GC_RIG="testrig"
export GC_RIG_ROOT="$WORK"
export STALE_BRANCH_COLD_DAYS=14
export STALE_BRANCH_BUDGET=0
export STUB_BARE="$BARE"
export STUB_STATUSES STUB_LIVE STUB_PR FINDINGS
export PATH="$BIN:$PATH"
NOW=$(date +%s); DAY=86400

# --- fake gc: the bead ledger -------------------------------------------------
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
case " $* " in
  *" statuses "*) [ "${STUB_STATUSES_RC:-0}" = 0 ] || { echo "gc: simulated failure" >&2; exit "${STUB_STATUSES_RC}"; }; cat "${STUB_STATUSES:?}" ;;
  *" list "*)     [ "${STUB_LIVE_RC:-0}" = 0 ] || { echo "gc: simulated failure" >&2; exit "${STUB_LIVE_RC}"; }; cat "${STUB_LIVE:?}" ;;
  *) exit 0 ;;
esac
STUB

# --- fake gh: PR listing + origin ref mutations against the bare --------------
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -u
BARE="${STUB_BARE:?}"
gitb() { git -C "$BARE" -c user.email=t@e.com -c user.name=T -c tag.gpgSign=false "$@"; }
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  [ "${STUB_PR_RC:-0}" = 0 ] || { echo "gh: pr list failure" >&2; exit "${STUB_PR_RC}"; }
  cat "${STUB_PR:?}"; exit 0
fi
if [ "${1:-}" = "api" ]; then
  shift
  method=GET; path=""; jqf=""; declare -A F=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --hostname) shift 2 ;;
      -X|--method) method="$2"; shift 2 ;;
      -f|-F|--raw-field) F["${2%%=*}"]="${2#*=}"; shift 2 ;;
      -q|--jq) jqf="$2"; shift 2 ;;
      *) [ -z "$path" ] && path="$1"; shift ;;
    esac
  done
  case "$method $path" in
    "POST "*/git/tags)
      [ "${STUB_TAG_RC:-0}" = 0 ] || { echo "gh: tags failure" >&2; exit "${STUB_TAG_RC}"; }
      gitb tag -a "${F[tag]}" "${F[object]}" -m "${F[message]}" 2>/dev/null || exit 1
      sha="$(gitb rev-parse "refs/tags/${F[tag]}")"
      if [ "$jqf" = ".sha" ]; then printf '%s\n' "$sha"; else printf '{"sha":"%s"}\n' "$sha"; fi ;;
    "POST "*/git/refs)
      # The annotated tag ref is created atomically at POST .../git/tags above.
      [ "${STUB_REF_RC:-0}" = 0 ] || { echo "gh: refs failure" >&2; exit "${STUB_REF_RC}"; }
      echo '{}' ;;
    "DELETE "*/git/refs/heads/*)
      [ "${STUB_DELETE_RC:-0}" = 0 ] || { echo "gh: delete failure" >&2; exit "${STUB_DELETE_RC}"; }
      gitb update-ref -d "refs/heads/${path#*/git/refs/heads/}" 2>/dev/null || exit 1 ;;
    *) exit 0 ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "$BIN/gc" "$BIN/gh"

# --- fixtures -----------------------------------------------------------------
statuses_default() {
  printf '%s\n' '[{"name":"open","category":"active"},{"name":"in_progress","category":"active"},{"name":"closed","category":"done"}]' > "$STUB_STATUSES"
}
# live beads: each row's metadata.branch / metadata.target protects a ref
live_default() { printf '%s\n' '[]' > "$STUB_LIVE"; }
live_set() { printf '%s\n' "$1" > "$STUB_LIVE"; }
pr_default() { : > "$STUB_PR"; }
pr_set() { printf '%s\n' "$@" > "$STUB_PR"; }

# push a branch to origin with a commit of a given age (days), from main
mk_branch() { # <branch> <age-days> [<subject>]
  local br="$1" age="$2" subj="${3:-work on $1}" at
  at="$(date -u -d "@$((NOW - age * DAY))" +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -r "$((NOW - age * DAY))" +%Y-%m-%dT%H:%M:%S)"
  git -C "$WORK" checkout -q -b "$br" main
  echo "$br" > "$WORK/f-$(printf '%s' "$br" | tr / _)"
  git -C "$WORK" add -A
  GIT_AUTHOR_DATE="$at" GIT_COMMITTER_DATE="$at" git -C "$WORK" commit -qm "$subj"
  git -C "$WORK" push -q origin "$br"
  git -C "$WORK" checkout -q main
}
# push a branch pointing at origin/main's current tip: 0 ahead, reachable ->
# superseded. mk_branch always adds a commit, so it can never make this shape.
mk_merged_branch() { # <branch>
  git -C "$WORK" checkout -q main
  git -C "$WORK" push -q origin "main:refs/heads/$1"
}
# land a commit on origin/main carrying a subject (for the squash signal)
land_subject() { # <subject>
  git -C "$WORK" checkout -q main
  echo "$RANDOM" > "$WORK/landed-$RANDOM"; git -C "$WORK" add -A
  git -C "$WORK" commit -qm "$1"
  git -C "$WORK" push -q origin main
}

new_origin() {
  rm -rf "$BARE" "$WORK"
  git init -q --bare "$BARE"
  git -C "$BARE" config user.email t@e.com; git -C "$BARE" config user.name T
  git init -q -b main "$WORK"
  git -C "$WORK" config user.email t@e.com
  git -C "$WORK" config user.name T
  git -C "$WORK" config commit.gpgsign false
  git -C "$WORK" remote add origin https://github.com/test/demo.git
  git -C "$WORK" config "url.$BARE.insteadOf" https://github.com/test/demo.git
  echo seed > "$WORK/seed"; git -C "$WORK" add seed; git -C "$WORK" commit -qm seed
  git -C "$WORK" push -q origin main
  git -C "$WORK" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  statuses_default; live_default; pr_default
  : > "$FINDINGS"
}

run() { bash "$SUT" "$@" 2>&1; }
on_origin() { [ -n "$(git -C "$WORK" ls-remote --heads origin "refs/heads/$1" 2>/dev/null)" ]; }
tag_on_origin() { [ -n "$(git -C "$WORK" ls-remote --tags origin "refs/tags/$1" 2>/dev/null)" ]; }

# =============================================================================
# One run, every disposition — a KEEP beside every TAKE
# =============================================================================
new_origin
land_subject "squashed work (tk-sqsh9)"  # advance main; its bead id now on main
mk_merged_branch superseded-reachable  # 0 ahead of main -> reachable -> DELETE
mk_branch polecat/tk-sqsh9 30          # main+1, but its bead id landed -> squash -> DELETE
mk_branch claude/cold-unmerged 40      # cold + unmerged + no PR -> ARCHIVE then delete
mk_branch polecat/fresh-unmerged 1     # unmerged but fresh -> KEEP
mk_branch polecat/live-owned 40        # cold+unmerged but a live bead names it -> KEEP
mk_branch integration/conv-live 40     # cold+unmerged but a live bead TARGETS it -> KEEP
mk_branch claude/cold-with-pr 40       # cold+unmerged but an open PR heads it -> CONTESTED
live_set '[{"id":"tk-a","status":"open","metadata":{"branch":"polecat/live-owned"}},
           {"id":"tk-b","status":"in_progress","metadata":{"target":"integration/conv-live"}}]'
pr_set "claude/cold-with-pr"

OUT="$(run)"; RC=$?
eq "$RC" 0 "a normal pass exits 0"
# TAKES
if on_origin superseded-reachable; then bad "a branch reachable from the target is deleted"; else ok "a branch reachable from the target is deleted"; fi
if on_origin polecat/tk-sqsh9; then bad "a branch whose bead id landed by squash is deleted"; else ok "a branch whose bead id landed by squash is deleted"; fi
if on_origin claude/cold-unmerged; then bad "a cold unmerged branch is archived then deleted"; else ok "a cold unmerged branch is archived then deleted"; fi
if grep -q "refs/tags/archive/claude/cold-unmerged@" < <(git -C "$WORK" ls-remote --tags origin); then ok "the archived branch is pinned by an archive tag on origin"; else bad "the archived branch is pinned by an archive tag on origin"; fi
# KEEPS
if on_origin polecat/fresh-unmerged; then ok "a fresh unmerged branch is kept"; else bad "a fresh unmerged branch is kept"; fi
if on_origin polecat/live-owned; then ok "a branch a live bead names is kept"; else bad "a branch a live bead names is kept"; fi
if on_origin integration/conv-live; then ok "a branch a live bead targets is kept"; else bad "a branch a live bead targets is kept"; fi
if on_origin claude/cold-with-pr; then ok "a branch under an open PR is not deleted"; else bad "a branch under an open PR is not deleted"; fi
# CONTESTED -> a finding, branch untouched
has "$(cat "$FINDINGS")" "claude/cold-with-pr" "a contested branch gets a finding"
has "$(cat "$FINDINGS")" "open PR heads it" "the finding carries the classification"
# summary line
has "$OUT" "deleted 2 superseded, archived 1 cold, filed 1 contested" "the summary counts each disposition"

# the archive tag preserves the content: the branch is one command back
TAGREF="$(git -C "$WORK" ls-remote --tags origin | sed -n 's#.*refs/tags/\(archive/claude/cold-unmerged@[0-9a-f]*\)$#\1#p' | head -1)"
if [ -n "$TAGREF" ]; then
  git -C "$WORK" fetch -q origin "refs/tags/$TAGREF:refs/tags/restore-probe" 2>/dev/null
  if git -C "$WORK" rev-parse -q --verify "refs/tags/restore-probe^{commit}" >/dev/null 2>&1; then
    ok "the archive tag dereferences to the pinned commit (restore point intact)"
  else bad "the archive tag dereferences to the pinned commit (restore point intact)"; fi
else bad "the archive tag dereferences to the pinned commit (restore point intact)"; fi

# =============================================================================
# Dry run is the review surface: reports the plan, touches nothing
# =============================================================================
new_origin
mk_branch claude/cold-unmerged 40
mk_merged_branch superseded-reachable
DRY="$(run --dry-run)"; RC=$?
eq "$RC" 0 "--dry-run exits 0"
has "$DRY" "DRY RUN" "--dry-run says so"
has "$DRY" "would ARCHIVE then delete 1" "--dry-run reports the archive plan"
has "$DRY" "claude/cold-unmerged" "--dry-run names a branch it would archive"
has "$DRY" "would DELETE 1 superseded" "--dry-run reports the superseded plan"
if on_origin claude/cold-unmerged && on_origin superseded-reachable; then ok "--dry-run deletes nothing"; else bad "--dry-run deletes nothing"; fi
if grep -q refs/tags/archive/ < <(git -C "$WORK" ls-remote --tags origin); then bad "--dry-run writes no archive tag"; else ok "--dry-run writes no archive tag"; fi
[ -s "$FINDINGS" ] && bad "--dry-run files no finding" || ok "--dry-run files no finding"

# =============================================================================
# Fail closed: an unreadable input sweeps nothing
# =============================================================================
new_origin; mk_branch claude/cold-unmerged 40
OUT="$(STUB_LIVE_RC=1 run)"; RC=$?
eq "$RC" 0 "an unreadable ledger exits 0 (soft)"
has "$OUT" "unreadable" "an unreadable ledger is named"
if on_origin claude/cold-unmerged; then ok "an unreadable ledger deletes nothing"; else bad "an unreadable ledger deletes nothing"; fi

# A listing that exits 0 is unread until it parses as one array of bead rows.
# Taking any of these as "no live beads" would leave every branch unowned, so
# the cold branch that pass would otherwise archive must survive each one.
for payload in 'not-json-but-exit-zero' '{"error":"store busy"}' '["claude/cold-unmerged"]' ''; do
  new_origin; mk_branch claude/cold-unmerged 40
  printf '%s' "$payload" > "$STUB_LIVE"
  OUT="$(run)"; RC=$?
  what="an exit-0 ledger reading '${payload:-<empty>}'"
  eq "$RC" 0 "$what exits 0 (soft)"
  has "$OUT" "did not parse" "$what is named"
  if on_origin claude/cold-unmerged; then ok "$what deletes nothing"; else bad "$what deletes nothing"; fi
done

new_origin; mk_branch claude/cold-unmerged 40
OUT="$(STUB_PR_RC=1 run)"
if on_origin claude/cold-unmerged; then ok "an unreadable PR list deletes nothing"; else bad "an unreadable PR list deletes nothing"; fi
has "$OUT" "pull requests" "an unreadable PR list is named"

# the archive tag must be verified on origin before the branch is deleted
new_origin; mk_branch claude/cold-unmerged 40
OUT="$(STUB_TAG_RC=1 run)"
if on_origin claude/cold-unmerged; then ok "a branch whose archive tag could not be pushed is NOT deleted"; else bad "a branch whose archive tag could not be pushed is NOT deleted"; fi
has "$OUT" "refused" "a failed archive is reported refused"

# a delete that fails leaves the branch (and does not count as deleted)
new_origin; mk_branch superseded-tip 10
OUT="$(STUB_DELETE_RC=1 run)"
if on_origin superseded-tip; then ok "a branch whose delete failed is kept"; else bad "a branch whose delete failed is kept"; fi

# =============================================================================
# Match-head: a branch whose origin tip no longer matches what was classified
# is not deleted (a commit arrived after classification, unpinned by the tag)
# =============================================================================
new_origin; mk_branch claude/moved 40
REAL_GIT="$(command -v git)"
cat > "$BIN/git" <<STUB
#!/usr/bin/env bash
# The pre-delete head re-read for this one branch reports a different tip than
# the classified one; every other git call is real.
if [ "\${3:-}" = "ls-remote" ] && [ "\${6:-}" = "refs/heads/claude/moved" ]; then
  echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef	refs/heads/claude/moved"
  exit 0
fi
exec "$REAL_GIT" "\$@"
STUB
chmod +x "$BIN/git"
OUT="$(run)"
rm -f "$BIN/git"
if on_origin claude/moved; then ok "a branch whose tip moved since classification is NOT deleted"; else bad "a branch whose tip moved since classification is NOT deleted"; fi
has "$OUT" "refused" "a moved tip is reported refused"

# =============================================================================
# Protected names are reported, not archived
# =============================================================================
new_origin; mk_branch integration/keepme 40
OUT="$(STALE_BRANCH_PROTECT='integration/*' run)"
if on_origin integration/keepme; then ok "a protected-name branch is not archived"; else bad "a protected-name branch is not archived"; fi
has "$(cat "$FINDINGS")" "integration/keepme" "a protected cold branch is reported contested"

# =============================================================================
# An origin that is not a resolvable github slug is swept as nothing, gracefully
# =============================================================================
new_origin; mk_branch claude/cold-unmerged 40
git -C "$WORK" remote set-url origin /some/local/path.git
OUT="$(run)"; RC=$?
eq "$RC" 0 "an unresolvable origin exits 0"
has "$OUT" "cannot resolve" "an unresolvable origin says so"
# origin now points at a bad path, so check the bare directly
if git -C "$BARE" show-ref --verify --quiet refs/heads/claude/cold-unmerged; then ok "an unresolvable origin deletes nothing"; else bad "an unresolvable origin deletes nothing"; fi

# =============================================================================
# Rails: usage and bad env
# =============================================================================
new_origin
run --nope >/dev/null 2>&1; eq "$?" 2 "an unknown argument is refused"
OUT="$(STALE_BRANCH_COLD_DAYS=0 run 2>&1)"; eq "$?" 2 "a zero cold horizon is refused"
OUT="$(STALE_BRANCH_COLD_DAYS=xx run 2>&1)"; eq "$?" 2 "a non-numeric cold horizon is refused"
unset_rig_out="$(GC_RIG='' run 2>&1)"; eq "$?" 2 "a missing GC_RIG is refused"

echo
echo "stale-branch-triage.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
