#!/usr/bin/env bash
# Tests for branch-end.sh against a real bare origin.
#
# The script writes origin refs, so the suite drives REAL git and asserts on
# the bare repository's actual refs. It sources test-harness.sh for the
# assertions only: harness_init would stub git out. The rig checkout's origin
# carries a GitHub-shaped URL, and url.insteadOf points its transport at the
# bare, so every push and ls-remote reaches the bare. Origin's refusals come
# from the bare's own pre-receive hook, switched on by a control file, and a
# branch that moves between the check and the delete comes from a git wrapper
# that pushes the move just before the delete's lease is sent. The ledger is a
# fake `gc` that serves `rig list` and the three `gc bd --db` reads from a JSON
# file, and refuses any store other than the rig's own.
#
# Every case that ends a branch also checks a second branch, which no case
# names, is still on origin, so "ended everything" cannot pass as "ended the
# one asked for".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/branch-end.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/gctk-branch-end-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=test-harness.sh
. "$HERE/test-harness.sh"   # assertions only; harness_init would stub git out
PASS=0; FAIL=0

# The suite runs inside a live city and maybe a git hook: none of the session's
# rig, store or repository settings may reach the script or the git it drives.
unset "${!GC_@}" "${!BEADS_@}" "${!GIT_@}" 2>/dev/null || true
export GIT_CONFIG_GLOBAL="$TMP/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
REAL_GIT="$(command -v git)"

BIN="$TMP/bin"; mkdir -p "$BIN"
BARE="$TMP/origin.git"
RIG="$TMP/rig"
CTL="$TMP/ctl"; mkdir -p "$CTL"
export STUB_RIGS="$TMP/rigs.json" STUB_DB="$RIG/.beads" STUB_LEDGER="$TMP/ledger.json"
export STUB_STATUSES="$TMP/statuses.json" STUB_GC_LOG="$TMP/gc.log"
export PATH="$BIN:$PATH"

cat > "$STUB_RIGS" <<JSON
{"rigs":[{"name":"demo","path":"$RIG","prefix":"tk"},{"name":"elsewhere","path":"$TMP/elsewhere","prefix":"zz"}]}
JSON
cat > "$STUB_STATUSES" <<'JSON'
{"built_in_statuses":[
  {"name":"open","category":"active"},{"name":"in_progress","category":"wip"},
  {"name":"blocked","category":"wip"},{"name":"deferred","category":"frozen"},
  {"name":"closed","category":"done"},{"name":"pinned","category":"frozen"},
  {"name":"hooked","category":"wip"}]}
JSON

# --- fake gc: the rig roster and the ledger ---------------------------------
cat > "$BIN/gc" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${STUB_GC_LOG:?}"
if [ "${1:-}" = rig ] && [ "${2:-}" = list ]; then cat "${STUB_RIGS:?}"; exit 0; fi
[ "${1:-}" = bd ] || exit 1
shift
db=""
while [ $# -gt 0 ]; do
  case "$1" in
    --db) db="$2"; shift 2 ;;
    --actor) shift 2 ;;
    *) break ;;
  esac
done
[ "$db" = "${STUB_DB:?}" ] || { echo "stub gc: read of store '$db', not the rig's" >&2; exit 1; }
sub="${1:-}"; shift || true
case "$sub" in
  statuses)
    [ "${STUB_STATUSES_RC:-0}" = 0 ] || exit "$STUB_STATUSES_RC"
    cat "${STUB_STATUSES:?}" ;;
  list)
    [ "${STUB_LIST_RC:-0}" = 0 ] || { echo "stub gc: list failure" >&2; exit "$STUB_LIST_RC"; }
    if [ -n "${STUB_LIST_PAYLOAD:-}" ]; then cat "$STUB_LIST_PAYLOAD"; exit 0; fi
    st=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --status) st="$2"; shift 2 ;;
        --status=*) st="${1#--status=}"; shift ;;
        *) shift ;;
      esac
    done
    jq -c --arg st "$st" '[.[] | select(.status as $s | ($st | split(",") | index($s)) != null)]' "${STUB_LEDGER:?}" ;;
  show)
    [ "${STUB_SHOW_RC:-0}" = 0 ] || exit "$STUB_SHOW_RC"
    out=$(jq -c --arg id "${1:-}" '[.[] | select(.id == $id)]' "${STUB_LEDGER:?}")
    if [ "$out" = "[]" ]; then
      printf '{"error":"no issues found matching the provided IDs","schema_version":1}\n'; exit 1
    fi
    printf '%s\n' "$out" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$BIN/gc"

ledger() { printf '%s\n' "$1" > "$STUB_LEDGER"; }

# --- fixtures ----------------------------------------------------------------
# The origin and the rig checkout are built once, then copied for each case: a
# git call is a process, and rebuilding the pair per case dominated the run.
build_origin() {
  rm -rf "$BARE" "$RIG" "$CTL"; mkdir -p "$CTL"
  git init -q --bare -b main "$BARE"
  # Origin's refusals, each switched on by a control file.
  cat > "$BARE/hooks/pre-receive" <<HOOK
#!/usr/bin/env bash
while read -r old new ref; do
  case "\$ref" in
    refs/heads/*) case "\$new" in *[!0]*) ;; *) [ -e "$CTL/refuse-delete" ] && { echo "refusing branch deletes" >&2; exit 1; } ;; esac ;;
    refs/tags/*) [ -e "$CTL/refuse-tag" ] && { echo "refusing tags" >&2; exit 1; } ;;
  esac
done
exit 0
HOOK
  chmod +x "$BARE/hooks/pre-receive"
  git init -q -b main "$RIG"
  git -C "$RIG" config user.email t@e.com
  git -C "$RIG" config user.name T
  git -C "$RIG" config commit.gpgsign false
  git -C "$RIG" config tag.gpgSign false
  git -C "$RIG" remote add origin https://github.com/test/demo.git
  git -C "$RIG" config "url.$BARE.insteadOf" https://github.com/test/demo.git
  echo seed > "$RIG/seed"; git -C "$RIG" add seed; git -C "$RIG" commit -qm seed
  git -C "$RIG" push -q origin main
  git -C "$RIG" fetch -q origin
  git -C "$RIG" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
build_origin
cp -R "$BARE" "$TMP/template-origin.git"
cp -R "$RIG" "$TMP/template-rig"

new_origin() {
  rm -rf "$BARE" "$RIG" "$TMP/other" "$CTL"; mkdir -p "$CTL"
  cp -R "$TMP/template-origin.git" "$BARE"
  cp -R "$TMP/template-rig" "$RIG"
  ledger '[]'
  : > "$STUB_GC_LOG"
}

mk_branch() { # <branch> — a commit on top of main, pushed to origin
  git -C "$RIG" checkout -q -b "$1" main
  echo "$1" > "$RIG/f-$(printf '%s' "$1" | tr / _)"
  git -C "$RIG" add -A
  git -C "$RIG" commit -qm "work on $1"
  git -C "$RIG" push -q origin "$1"
  git -C "$RIG" checkout -q main
}

origin_tip() { git -C "$BARE" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || true; }
on_origin() { [ -n "$(origin_tip "$1")" ]; }
tags_on_origin() { git -C "$BARE" for-each-ref --format='%(refname)' refs/tags/ | paste -sd ' ' -; }
pr_pin() { git -C "$BARE" update-ref "refs/pull/$1/head" "$2"; } # <n> <sha>

run() { bash "$SUT" "$@" >"$TMP/out" 2>"$TMP/err"; }
out() { cat "$TMP/out" "$TMP/err"; }

gone_kept() { # <ended-branch> <bystander> <what>
  if on_origin "$1"; then bad "$3: $1 is gone from origin"; else ok "$3: $1 is gone from origin"; fi
  if on_origin "$2"; then ok "$3: the bystander $2 is still on origin"; else bad "$3: the bystander $2 is still on origin"; fi
}

RETIRED_ROW='{"id":"tk-a","status":"closed","metadata":{"branch":"polecat/tk-a","target":"main"}}'

# =============================================================================
# The PR pin: a pull request's refs/pull/<n>/head equal to the tip keeps it
# =============================================================================
new_origin
mk_branch polecat/tk-a; mk_branch polecat/tk-bystander
TIP=$(origin_tip polecat/tk-a)
pr_pin 7 "$TIP"
pr_pin 8 "$(origin_tip polecat/tk-bystander)"
ledger "[$RETIRED_ROW]"
rc=0; run --rig demo --branch polecat/tk-a --bead tk-a || rc=$?
eq "$rc" 0 "a PR-pinned retired branch is ended"
gone_kept polecat/tk-a polecat/tk-bystander "PR pin"
eq "$(git -C "$BARE" rev-parse refs/pull/7/head)" "$TIP" "the PR's head ref still holds the tip, so the delete lost nothing"
eq "$(tags_on_origin)" "" "a PR-pinned tip gets no archive tag"
has "$(out)" "kept by refs/pull/7/head" "the output names what keeps the tip"
has "$(cat "$STUB_GC_LOG")" "bd --db $RIG/.beads list" "the owner check reads the rig's own store"

# =============================================================================
# The archive pin: no PR ref holds the tip, so a tag is pushed and read back
# =============================================================================
new_origin
mk_branch polecat/tk-b; mk_branch polecat/tk-bystander
TIP=$(origin_tip polecat/tk-b)
TAG="archive/polecat/tk-b@${TIP:0:12}"
ledger '[{"id":"tk-b","status":"closed","metadata":{"branch":"polecat/tk-b"}}]'
rc=0; run --rig demo --branch polecat/tk-b --bead tk-b || rc=$?
eq "$rc" 0 "an unpinned retired branch is ended"
gone_kept polecat/tk-b polecat/tk-bystander "archive pin"
eq "$(git -C "$BARE" rev-parse -q --verify "refs/tags/$TAG^{commit}")" "$TIP" "the archive tag on origin peels to the tip"
eq "$(git -C "$BARE" cat-file -t "refs/tags/$TAG")" tag "the archive tag is annotated"
has "$(git -C "$BARE" cat-file -p "refs/tags/$TAG")" "git push origin $TIP:refs/heads/polecat/tk-b" "the tag message carries the restore command"
has "$(out)" "kept by refs/tags/$TAG" "the output names the archive tag"
eq "$(git -C "$RIG" for-each-ref --format='%(refname)' refs/tags/)" "" "no local tag ref is left in the rig checkout"
# The restore the tag message names brings the branch back at the same tip.
git -C "$RIG" fetch -q origin "refs/tags/$TAG" 2>/dev/null
git -C "$RIG" push -q origin "$TIP:refs/heads/polecat/tk-b" 2>/dev/null
eq "$(origin_tip polecat/tk-b)" "$TIP" "the restore command brings the branch back at its tip"

# A PR ref that holds some other commit pins nothing, so the tag still goes up.
new_origin
mk_branch polecat/tk-c; mk_branch polecat/tk-bystander
TIP=$(origin_tip polecat/tk-c)
pr_pin 9 "$(git -C "$BARE" rev-parse refs/heads/main)"
rc=0; run --rig demo --branch polecat/tk-c || rc=$?
eq "$rc" 0 "a branch whose PR ref lags its tip is ended"
eq "$(git -C "$BARE" rev-parse -q --verify "refs/tags/archive/polecat/tk-c@${TIP:0:12}^{commit}")" "$TIP" "…pinned by an archive tag, not by the stale PR ref"
gone_kept polecat/tk-c polecat/tk-bystander "stale PR ref"

# The tip is not in the rig checkout (pushed from another clone): it is fetched
# so the tag object can be written.
new_origin
mk_branch polecat/tk-bystander
git clone -q "$BARE" "$TMP/other"
git -C "$TMP/other" -c user.email=t@e.com -c user.name=T -c commit.gpgsign=false commit -q --allow-empty -m "elsewhere"
git -C "$TMP/other" push -q origin HEAD:refs/heads/polecat/tk-far
TIP=$(origin_tip polecat/tk-far)
if git -C "$RIG" cat-file -e "$TIP^{commit}" 2>/dev/null; then bad "fixture: the far tip is absent from the rig checkout"; else ok "fixture: the far tip is absent from the rig checkout"; fi
rc=0; run --rig demo --branch polecat/tk-far || rc=$?
eq "$rc" 0 "a tip the rig checkout lacks is fetched and pinned"
eq "$(git -C "$BARE" rev-parse -q --verify "refs/tags/archive/polecat/tk-far@${TIP:0:12}^{commit}")" "$TIP" "…by an archive tag at that tip"
gone_kept polecat/tk-far polecat/tk-bystander "fetched tip"

# =============================================================================
# Whose branch: a live owner keeps it
# =============================================================================
new_origin
mk_branch polecat/tk-own
TIP=$(origin_tip polecat/tk-own)
ledger '[{"id":"tk-own","status":"closed","metadata":{"branch":"polecat/tk-own"}},
         {"id":"tk-succ","status":"open","metadata":{"branch":"polecat/tk-own","target":"main"}}]'
rc=0; run --rig demo --branch polecat/tk-own --bead tk-own || rc=$?
eq "$rc" 3 "a branch another open bead names in metadata.branch is kept"
eq "$(origin_tip polecat/tk-own)" "$TIP" "…and stays on origin at its tip"
eq "$(tags_on_origin)" "" "…with no tag pushed for it"
has "$(out)" "tk-succ (open, metadata.branch)" "the output names the owner and how it names the branch"

new_origin
mk_branch integration/conv
ledger '[{"id":"tk-conv","status":"open","metadata":{"target":"integration/conv"}},
         {"id":"tk-member","status":"in_progress","metadata":{"branch":"polecat/tk-member","target":"integration/conv"}}]'
rc=0; run --rig demo --branch integration/conv || rc=$?
eq "$rc" 3 "an integration branch a live convoy and its member target is kept"
on_origin integration/conv && ok "…and stays on origin" || bad "…and stays on origin"
has "$(out)" "tk-conv (open, metadata.target)" "the output names the convoy that targets it"

# Every status outside the done category owns: a deferred bead is parked work.
new_origin
mk_branch polecat/tk-park
ledger '[{"id":"tk-park","status":"deferred","metadata":{"branch":"polecat/tk-park"}}]'
rc=0; run --rig demo --branch polecat/tk-park || rc=$?
eq "$rc" 3 "a deferred bead still owns its branch"

# =============================================================================
# Whose branch: the retired bead's own scaffolding is not an owner
# =============================================================================
new_origin
mk_branch polecat/tk-s; mk_branch polecat/tk-bystander
ledger '[{"id":"tk-s","status":"closed","metadata":{"branch":"polecat/tk-s"}},
         {"id":"tk-s-rework","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-s","branch":"polecat/tk-s","target":"main"}},
         {"id":"tk-s-rebase","status":"in_progress","metadata":{"task_kind":"rework","anchor_bead":"tk-s","branch":"polecat/tk-s","target":"main"}},
         {"id":"tk-s-review","status":"open","metadata":{"task_kind":"review","anchor_bead":"tk-s","review_branch":"polecat/tk-s"}}]'
rc=0; run --rig demo --branch polecat/tk-s --bead tk-s || rc=$?
eq "$rc" 0 "the retired bead's open rework, rebase and review beads do not keep its branch"
gone_kept polecat/tk-s polecat/tk-bystander "scaffolding"

# While the bead is still open it owns its branch, and its scaffolding counts.
new_origin
mk_branch polecat/tk-s
ledger '[{"id":"tk-s","status":"open","metadata":{"branch":"polecat/tk-s"}},
         {"id":"tk-s-rework","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-s","branch":"polecat/tk-s"}}]'
rc=0; run --rig demo --branch polecat/tk-s --bead tk-s || rc=$?
eq "$rc" 3 "a bead that is not closed keeps its branch"
has "$(out)" "tk-s (open, metadata.branch)" "…naming the bead itself as the owner"
has "$(out)" "tk-s-rework (open, metadata.branch)" "…and its scaffolding with it"

# Scaffolding of some other anchor on the same branch is that anchor's claim.
new_origin
mk_branch polecat/tk-s
ledger '[{"id":"tk-s","status":"closed","metadata":{"branch":"polecat/tk-s"}},
         {"id":"tk-x-rework","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-x","branch":"polecat/tk-s"}}]'
rc=0; run --rig demo --branch polecat/tk-s --bead tk-s || rc=$?
eq "$rc" 3 "a rework child of another anchor on the branch keeps it"
has "$(out)" "tk-x-rework" "…and is named"

# With no --bead nothing is told apart as scaffolding.
new_origin
mk_branch polecat/tk-s
ledger '[{"id":"tk-s-rework","status":"open","metadata":{"task_kind":"rework","anchor_bead":"tk-s","branch":"polecat/tk-s"}}]'
rc=0; run --rig demo --branch polecat/tk-s || rc=$?
eq "$rc" 3 "without --bead a rework child naming the branch keeps it"

# =============================================================================
# An unreadable ledger keeps the branch
# =============================================================================
new_origin
mk_branch polecat/tk-u
TIP=$(origin_tip polecat/tk-u)
ledger "[{\"id\":\"tk-u\",\"status\":\"closed\",\"metadata\":{\"branch\":\"polecat/tk-u\"}}]"
rc=0; STUB_LIST_RC=1 run --rig demo --branch polecat/tk-u --bead tk-u || rc=$?
eq "$rc" 4 "a ledger listing that fails is not ended"
eq "$(origin_tip polecat/tk-u)" "$TIP" "…and the branch stays at its tip"
has "$(out)" "did not read" "…and the refusal says the ledger did not read"
has "$(out)" "end it with: $SUT --rig demo --branch polecat/tk-u --bead tk-u" "…and names the command that ends it"

rc=0; STUB_STATUSES_RC=1 run --rig demo --branch polecat/tk-u --bead tk-u || rc=$?
eq "$rc" 4 "a status contract that does not read is not ended"
rc=0; STUB_SHOW_RC=1 run --rig demo --branch polecat/tk-u --bead tk-u || rc=$?
eq "$rc" 4 "a --bead that does not read is not ended"
# A listing that exits 0 is read only once it parses as exactly one array.
for payload in 'not-json-but-exit-zero' '{"error":"store busy"}' '' '[] []'; do
  printf '%s' "$payload" > "$TMP/payload"
  rc=0; STUB_LIST_PAYLOAD="$TMP/payload" run --rig demo --branch polecat/tk-u --bead tk-u || rc=$?
  eq "$rc" 4 "a ledger answering '${payload:-<empty>}' is not ended"
done
eq "$(origin_tip polecat/tk-u)" "$TIP" "no unreadable ledger ended the branch"
eq "$(tags_on_origin)" "" "…or pushed a tag for it"

# =============================================================================
# A branch that moved after the check is left alone
# =============================================================================
move_before_delete() { # <branch> — a wrapper that pushes a new commit onto <branch> just before the lease is sent
  local moved
  moved=$(git -C "$BARE" commit-tree -p "$(origin_tip "$1")" -m "pushed after the check" "$(origin_tip "$1")^{tree}")
  cat > "$BIN/git" <<WRAP
#!/usr/bin/env bash
case " \$* " in
  *" push "*"--force-with-lease=refs/heads/$1:"*) "$REAL_GIT" -C "$BARE" update-ref "refs/heads/$1" "$moved" ;;
esac
exec "$REAL_GIT" "\$@"
WRAP
  chmod +x "$BIN/git"
  printf '%s' "$moved"
}

new_origin
mk_branch polecat/tk-m
TIP=$(origin_tip polecat/tk-m)
pr_pin 11 "$TIP"
MOVED=$(move_before_delete polecat/tk-m)
rc=0; run --rig demo --branch polecat/tk-m || rc=$?
rm -f "$BIN/git"
eq "$rc" 4 "a branch that moved after the check is not ended"
eq "$(origin_tip polecat/tk-m)" "$MOVED" "…and stays on origin at the commit pushed after the check"
has "$(out)" "moved to ${MOVED:0:12}" "…and the refusal says it moved"

new_origin
mk_branch polecat/tk-m
TIP=$(origin_tip polecat/tk-m)
MOVED=$(move_before_delete polecat/tk-m)
rc=0; run --rig demo --branch polecat/tk-m || rc=$?
rm -f "$BIN/git"
eq "$rc" 4 "a branch that moved after its archive tag went up is not ended"
eq "$(origin_tip polecat/tk-m)" "$MOVED" "…and stays on origin at the new commit"
eq "$(git -C "$BARE" rev-parse -q --verify "refs/tags/archive/polecat/tk-m@${TIP:0:12}^{commit}")" "$TIP" "…while the tag still pins the tip that was checked"

# =============================================================================
# Origin refuses: nothing is deleted without a pin, a refused delete keeps it
# =============================================================================
new_origin
mk_branch polecat/tk-r
TIP=$(origin_tip polecat/tk-r)
: > "$CTL/refuse-tag"
rc=0; run --rig demo --branch polecat/tk-r || rc=$?
rm -f "$CTL/refuse-tag"
eq "$rc" 4 "a branch whose archive tag origin refused is not ended"
eq "$(origin_tip polecat/tk-r)" "$TIP" "…so an unpinned tip is never deleted"
has "$(out)" "did not read back on origin" "…and the refusal says the tag did not land"

: > "$CTL/refuse-delete"
rc=0; run --rig demo --branch polecat/tk-r || rc=$?
rm -f "$CTL/refuse-delete"
eq "$rc" 4 "a delete origin refuses is reported, not taken as done"
eq "$(origin_tip polecat/tk-r)" "$TIP" "…and the branch stays at its tip"
has "$(out)" "origin refused the delete" "…and the refusal says so"
TAGOBJ=$(git -C "$BARE" rev-parse "refs/tags/archive/polecat/tk-r@${TIP:0:12}")
# The re-run finds its own tag at the tip and ends the branch on it.
rc=0; run --rig demo --branch polecat/tk-r || rc=$?
eq "$rc" 0 "the re-run ends the branch once origin takes the delete"
eq "$(git -C "$BARE" rev-parse "refs/tags/archive/polecat/tk-r@${TIP:0:12}")" "$TAGOBJ" "…reusing the archive tag the refused run pushed"
on_origin polecat/tk-r && bad "…and the branch is gone" || ok "…and the branch is gone"

# A tag of that name at some other commit is not a pin.
new_origin
mk_branch polecat/tk-t
TIP=$(origin_tip polecat/tk-t)
git -C "$BARE" -c user.email=t@e.com -c user.name=T tag -a "archive/polecat/tk-t@${TIP:0:12}" refs/heads/main -m "not the tip"
rc=0; run --rig demo --branch polecat/tk-t || rc=$?
eq "$rc" 4 "an archive tag at another commit refuses the end"
eq "$(origin_tip polecat/tk-t)" "$TIP" "…and the branch stays"

# =============================================================================
# Nothing to end, protected names, the dry run
# =============================================================================
new_origin
ledger '[]'
rc=0; STUB_LIST_RC=1 run --rig demo --branch polecat/tk-gone --bead tk-gone || rc=$?
eq "$rc" 0 "a branch already gone from origin is done"
has "$(out)" "not on origin" "…and says there was nothing to end"
case "$(cat "$STUB_GC_LOG")" in
  *"/.beads list"*|*"/.beads statuses"*) bad "…without reading the ledger" ;;
  *) ok "…without reading the ledger" ;;
esac

new_origin
mk_branch claude/research
rc=0; run --rig demo --branch main || rc=$?
eq "$rc" 3 "the default branch is never ended"
on_origin main && ok "…and main stays" || bad "…and main stays"
rc=0; run --rig demo --branch claude/research || rc=$?
eq "$rc" 3 "a claude/* branch is never ended"
on_origin claude/research && ok "…and stays on origin" || bad "…and stays on origin"

new_origin
mk_branch polecat/tk-d; mk_branch polecat/tk-dp
pr_pin 12 "$(origin_tip polecat/tk-dp)"
rc=0; run --rig demo --branch polecat/tk-d --dry-run || rc=$?
eq "$rc" 0 "a dry run of an unpinned branch exits 0"
has "$(out)" "would push tag archive/polecat/tk-d@" "…and names the tag it would push"
rc=0; run --rig demo --branch polecat/tk-dp --dry-run || rc=$?
eq "$rc" 0 "a dry run of a PR-pinned branch exits 0"
has "$(out)" "kept by refs/pull/12/head" "…and names the PR ref that keeps it"
on_origin polecat/tk-d && on_origin polecat/tk-dp && ok "the dry run ends nothing" || bad "the dry run ends nothing"
eq "$(tags_on_origin)" "" "the dry run pushes no tag"

# =============================================================================
# Rails: an unreadable origin, a rig that does not resolve, usage
# =============================================================================
new_origin
mk_branch polecat/tk-o
git -C "$RIG" config "url.$TMP/missing.git.insteadOf" https://github.com/test/demo.git
git -C "$RIG" config --unset "url.$BARE.insteadOf"
rc=0; run --rig demo --branch polecat/tk-o || rc=$?
eq "$rc" 4 "an origin whose refs do not read ends nothing"
on_origin polecat/tk-o && ok "…and the branch stays" || bad "…and the branch stays"

rc=0; run --rig nowhere --branch polecat/tk-o || rc=$?
eq "$rc" 4 "a rig gc does not know is refused"
rc=0; run --rig elsewhere --branch polecat/tk-o || rc=$?
eq "$rc" 4 "a rig whose path is not a checkout is refused"
rc=0; run --branch polecat/tk-o || rc=$?
eq "$rc" 2 "--rig is required"
rc=0; run --rig demo || rc=$?
eq "$rc" 2 "--branch is required"
rc=0; run --rig demo --branch 'bad..name' || rc=$?
eq "$rc" 2 "a name that is not a branch is refused"
rc=0; run --rig demo --branch polecat/tk-o --nope || rc=$?
eq "$rc" 2 "an unknown argument is refused"

echo "---"
echo "branch-end.test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
