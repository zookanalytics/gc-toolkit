#!/usr/bin/env bash
# Hermetic test for pre-open-resolve.sh (the pre-open codex gate's PR-create pass,
# tk-6d0vb.1.8). Stubs `gh` (branch head, existing-PR lookup, the real pr create),
# `git` (the origin remote the reads are pinned to) and `gc` (bead-ledger
# list/show/update) on PATH. No live city, Dolt, network, or real pull requests.
#
# The pass opens the PR for each pre_open_gate anchor once codex is green at the
# branch head, then flips it to pull_request → the unchanged merge gate. Covered:
#   (GREEN)  no PR yet + check.codex green@<live head> -> `gh pr create` (non-draft)
#            at that head + flip to pull_request with the new pr_url/pr_number.
#   (STALE)  no PR + check.codex green@<OLD head> != live head -> HELD (no create,
#            no flip): a rework advanced the head, the marker must re-earn it.
#   (MISS)   no PR + no check.codex marker -> HELD (codex not done).
#   (HASPR)  branch already has an open PR (a sibling anchor opened it) -> flipped
#            to pull_request (record the existing pr), NEVER a second `gh pr create`
#            — this is the orphan-convoy convergence.
#   (DEAD)   ...but a CLOSED-and-NOT-MERGED PR is not an existing PR in any sense the
#            merge gate can use (tk-g0hd2): it is what a supersede leaves behind, it
#            can never merge, and adopting it moved the anchor out of the only state
#            that retries PR-open. Such a branch gets a FRESH PR pointing at the one it
#            supersedes — while a MERGED sibling still flips (DEAD2) and an OPEN one is
#            still reused (DEAD3), which is what `--state all` is there for. The
#            same-head case (DEAD7) is an operator's close, not a supersede, and holds.
#   (INV)    `gh pr create` is reached for EXACTLY the one green no-PR anchor.
#   (URL)    both arms stamp the canonical pull-request URL as the anchor's identity.
#   (CONV)   convergence: a flipped anchor leaves the pre_open_gate set, so a
#            second pass neither re-creates nor re-flips it.
#
# OPERATOR HOLDS (tk-3j0ob). merge_hold/rebase_hold on the anchor are explicit
# operator gates. This pass honored neither, so a hold stopped a held anchor from
# MERGING while the open side PUBLISHED a pull request against it — the operator
# saw a hold in place and a new PR appear anyway. Covered:
#   (HOLD0) POSITIVE CONTROL, run first: the explicit "off" spellings (false, 0) do
#           NOT hold, so an unheld anchor still opens. Without it, a gate that held
#           unconditionally would pass every case below.
#   (HOLD1) merge_hold truthy -> nothing opened, nothing flipped, nothing
#           commented; named in the log and counted HELD, not skipped.
#   (HOLD2) rebase_hold truthy -> the same, named as rebase_hold specifically.
#   (HOLD3) ...but a held anchor whose branch ALREADY has a PR is still FLIPPED:
#           the hold is on publishing, not on adopting a PR that exists. Holding
#           the flip would leak the anchor open (pre_open_gate is invisible to the
#           merged-close observer, which scans only pull_request).
#   (HOLD4) the gate precedes the branch-head read, so an unreadable head cannot
#           mask an operator's block as a transient skip.
#
# REPOSITORY IDENTITY (review tk-jc66l). A branch name does not name a repository,
# and every fork of this repo can carry the same `polecat/<bead>`. Uncertified, a
# foreign same-branch PR flips this anchor OUT of pre_open_gate — the only state
# that retries PR-open — onto a stranger's pr_url/pr_number, so the real PR is
# never opened by anything. Covered:
#   (ID1) gh's current repository is MOVED (`gh repo set-default`/GH_REPO): every
#         read and the create are pinned to the origin-derived repository, so the
#         right branch answers and the PR is opened in the right repository.
#   (ID2) GH_HOST is moved under a hostless pin: `<owner>/<repo>` names one
#         repository PER HOST, so the pins are host-qualified (`--repo
#         <host>/<owner>/<repo>`, `gh api --hostname`) and the drift changes nothing.
#   (ID3) a gh that IGNORES the pin (a wrapper, a redirect after a transfer/rename):
#         a foreign same-branch PR must NOT flip the anchor, and a foreign branch-head
#         answer must NOT open a PR. Nothing stamped; the anchor stays pre_open_gate.
#   (ID4) `gh pr create` answers with a PR in another repository: the returned URL is
#         certified BEFORE it becomes this anchor's identity — nothing stamped.
#   (ID5) this checkout's origin cannot be resolved at all -> NOTHING is opened,
#         flipped or stamped this pass (fail closed: an opened PR cannot be retried
#         away).
#
# HEAD IDENTITY (review tk-j0q41). Pinning a read to the origin repository says where
# the ANSWER came from, never which branch — in which repository — the pull request is
# opened FROM. A FORK'S PR INTO THIS REPOSITORY HAS ONE OF OUR URLS AND ONE OF THEIR
# BRANCHES, so the url check passes on it; and `--head` filters on the branch NAME
# alone, so it is listed next to ours with nothing but arrival order between them.
# Covered:
#   (FK1) a same-base fork PR reusing the branch name is NOT this anchor's PR: it is
#         refused by name, and the anchor is not flipped onto it.
#   (FK2) ...and a name collision is not a licence to open one either — nothing is
#         created for that branch; the anchor stays pre_open_gate for an operator.
#   (FK3) a fork row arriving BEFORE a valid same-repo row does not win: every row is
#         certified and the branch's own OPEN pull request is the one selected.
#   (FK4) a same-repo, same-head PR targeting a DIFFERENT base is not this anchor's
#         either — the anchor lands somewhere else than that pull request does.
#   (FK5) a NULL head repository (gh's answer for a deleted fork) is UNREADABLE, not
#         "not ours": nothing is flipped and nothing is created.
#   (FK6) a create that answers with a fork-head pull request is caught by reading the
#         created PR back BY NUMBER and certifying it — nothing is stamped.
#   (FK7) no pull request is ever resolved by BRANCH NAME (`gh pr view <branch>`):
#         that lookup is the gap itself, and the create-race discovery uses the same
#         certified scan instead.
#   (RACE) a create race (a concurrent open) is still discovered — via that scan — and
#         the discovered PR is flipped onto only because it certified.
#   (READ) a FAILED `gh pr list` is not an empty one: "I could not see it" must not
#         become "no PR exists", which would open a twin.
#   (TRUNC) a full page of branch-name matches may be truncated, so "no pull request
#         of ours" cannot be concluded from it — refuse rather than open a twin.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/pre-open-resolve.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Pre-open-gated anchors (gc bd list source):
#   id|branch|merged_target|check.codex[|merge_hold|rebase_hold]
# The two hold columns are optional — omitted means the marker is unset, which is
# the shape every anchor filed before tk-3j0ob has.
#   bead-GREEN : green at the live head            -> open PR + flip
#   bead-STALE : green at an OLD head (rework moved it) -> held
#   bead-MISS  : no marker (codex not done)        -> held
#   bead-HASPR : branch already has an open PR      -> flip (no second create)
cat > "$TMP/anchors" <<'A'
bead-GREEN|polecat/feat-a|main|green@HEADA
bead-STALE|polecat/feat-b|main|green@OLDB
bead-MISS|polecat/feat-c|main|
bead-HASPR|polecat/feat-d|main|green@HEADD
A

# Live branch heads (gh api .../commits/<branch> -> .sha):
cat > "$TMP/heads" <<'H'
polecat/feat-a|HEADA
polecat/feat-b|HEADB
polecat/feat-c|HEADC
polecat/feat-d|HEADD
H

# PULL REQUESTS, in the shape `gh pr list --json`/`gh pr view --json` answers:
#   branch|number|url|state|baseRefName|headRefName|<headRepoOwner>/<headRepoName>
# The last field is the half a same-repo URL cannot answer, and the half a fork
# differs in. `-` models gh's NULL head repository (the fork was deleted); an EMPTY
# field models a partial or schema-shifted response. Both must read as
# UNCERTIFIABLE, never as "not ours".
#
# Existing PRs by branch (gh pr list --head <branch>): only feat-d has one.
cat > "$TMP/existpr" <<'E'
polecat/feat-d|404|https://github.com/acme/repo/pull/404|OPEN|main|polecat/feat-d|acme/repo
E

# What `gh pr create --head <branch>` produces, and what reading that PR back by
# number then answers: only feat-a reaches create (the sole green, no-PR anchor).
cat > "$TMP/newpr" <<'N'
polecat/feat-a|501|https://github.com/acme/repo/pull/501|OPEN|main|polecat/feat-a|acme/repo
N

# A concurrent open: `gh pr create` finds the branch already has a PR, so it emits
# nothing — and the row appears in the existing-PR list from then on.
: > "$TMP/racepr"

# Branches for which a FOREIGN repository has a same-named branch with an open PR.
# Only consulted when an invocation resolved somewhere other than the origin
# repository — i.e. when a pin was ignored (ID3).
: > "$TMP/foreignpr"

# Review beads carrying the codex verdict (anchor_id|review_id) + notes.
cat > "$TMP/reviews" <<'R'
bead-GREEN|rev-green
R
cat > "$TMP/notes" <<'NT'
rev-green|Codex signoff: LGTM (pre-open).
NT

: > "$TMP/createdbody"; : > "$TMP/commentbody"
: > "$TMP/created"; : > "$TMP/fliplog"; : > "$TMP/flipped"; : > "$TMP/comments"
: > "$TMP/meta"; : > "$TMP/drop"
: > "$TMP/createdwhere"; : > "$TMP/flipurl"; : > "$TMP/commentwhere"
: > "$TMP/viewbyname"
# Identity knobs, all clear for the baseline runs.
: > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
: > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"

# --- git stub. ----------------------------------------------------------------
# `git remote get-url origin` -> what this checkout pushes to, and the ONLY source
# of the repository every read and the create are pinned to. Deliberately NOT
# `gh`: gh's idea of the current repository is movable, and moving it must not
# move the expectation. $FAKE_REPOFAIL makes it unanswerable, as a checkout with
# no origin remote would (ID5).
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_REPOFAIL" ] && exit 1
  printf 'https://github.com/acme/repo.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gh stub: api (branch head), pr list/create/view/comment. -----------------
# EVERY SUBCOMMAND RESOLVES IN gh's CURRENT REPOSITORY UNLESS A PIN OVERRIDES IT.
# $FAKE_GH_DEFAULT moves that default exactly as `gh repo set-default`, GH_REPO or
# a different cwd would (`acme/repo` when unset), and $FAKE_GH_HOST moves the host
# a HOSTLESS `--repo o/r` is filled from (`gh help environment`) — the two ways a
# stranger's same-branch PR gets served to this pass. $FAKE_IGNORE_REPO models a
# gh that ignores the pins entirely, so the returned URL is the only thing left to
# catch it; $FAKE_IGNORE_REPO_CREATE narrows that to `pr create` alone (a redirect
# on the write path), which is the case the stamp-time certification exists for.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
ghdefault=$(cat "$FAKE_GH_DEFAULT" 2>/dev/null)
[ -n "$ghdefault" ] || ghdefault="acme/repo"
ghhost=$(cat "$FAKE_GH_HOST" 2>/dev/null)
[ -n "$ghhost" ] || ghhost="github.com"

# Host-qualify a `[HOST/]OWNER/REPO`, filling the host from GH_HOST when omitted.
qualify() {
  case "$1" in
    */*/*) printf '%s' "$1" ;;
    *)     printf '%s/%s' "$ghhost" "$1" ;;
  esac
}

# Fixture rows on stdin -> the JSON array `--json` answers with. The head-repository
# object is what gh really returns: a nested owner/name pair that is NULL when the
# head repository is gone, which is why the script assembles it defensively.
rows_json() {
  jq -R -s --arg origin "acme/repo" '
    [ split("\n")[] | select(length > 0) | split("|")
      | (.[6] // "") as $hr
      | { number: (if ((.[1] // "") | length) > 0 then (.[1] | tonumber) else null end),
          url: (.[2] // ""), state: (.[3] // ""),
          baseRefName: (.[4] // ""), headRefName: (.[5] // ""),
          headRefOid: (.[7] // ""),
          # gh reports mergedAt as NULL on everything that did not land — including a
          # pull request closed unmerged, which is the row the dead/live distinction
          # turns on. Derived from the state so every fixture carries the real shape;
          # column 9 states it outright, for the REST shape (state=closed + merged_at
          # set) that no state-derived default can produce.
          mergedAt: (if ((.[8] // "") | length) > 0 then .[8]
                     elif (.[3] // "") == "MERGED" then "2026-07-01T00:00:00Z"
                     else null end),
          isCrossRepository: ($hr != $origin) }
        + ( if $hr == "" or $hr == "-"
            then { headRepositoryOwner: null, headRepository: null }
            else { headRepositoryOwner: { login: ($hr | split("/")[0]) },
                   headRepository:      { name:  ($hr | split("/")[1]) } } end ) ]'
}

if [ "$1" = "api" ]; then
  # gh api [--hostname H] repos/<owner>/<repo>/commits/<branch>
  # `repos/{owner}/{repo}/...` is a PLACEHOLDER path gh fills from its CURRENT
  # repository — the unpinned form. An explicit `repos/o/r/...` path plus
  # `--hostname` is the pin.
  shift; hostpin=""; path=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --hostname) hostpin="$2"; shift 2 ;;
      --jq|-q|-H|-f|-F) shift 2 ;;
      -*) shift ;;
      *) [ -n "$path" ] || path="$1"; shift ;;
    esac
  done
  case "$path" in
    'repos/{owner}/{repo}/'*) apirepo="$ghdefault" ;;
    repos/*) apirepo=$(printf '%s' "$path" | sed -n 's#^repos/\([^/][^/]*/[^/][^/]*\)/.*#\1#p') ;;
    *)       apirepo="$ghdefault" ;;
  esac
  apihost="$hostpin"; [ -n "$apihost" ] || apihost="$ghhost"
  if [ -s "$FAKE_IGNORE_REPO" ]; then apirepo="$ghdefault"; apihost="$ghhost"; fi
  branch=$(printf '%s' "$path" | sed 's#^repos/[^/]*/[^/]*/commits/##')
  sha=$(awk -F'|' -v b="$branch" '$1==b{print $2; exit}' "$FAKE_HEADS")
  [ -n "$sha" ] || exit 1
  # A foreign repository answers for ITS branch of the same name. Deliberately the
  # SAME sha as ours: nothing but the repository the commit lives in distinguishes
  # the answer, so only the html_url certification can catch it.
  jq -n --arg s "$sha" --arg r "$apirepo" --arg h "$apihost" \
    '{sha:$s, html_url:("https://" + $h + "/" + $r + "/commit/" + $s)}'
  exit 0
fi

# Which repository this invocation actually resolves in: the `--repo` pin when
# honoured, else gh's movable default.
cmd="$1"; sub="${2:-}"
RESOLVED=""; prev=""
for a in "$@"; do
  case "$prev" in --repo|-R) RESOLVED="$a" ;; esac
  prev="$a"
done
[ -s "$FAKE_IGNORE_REPO" ] && RESOLVED=""
if [ "$cmd $sub" = "pr create" ] && [ -s "$FAKE_IGNORE_REPO_CREATE" ]; then RESOLVED=""; fi
[ -n "$RESOLVED" ] || RESOLVED="$ghdefault"
RESOLVED=$(qualify "$RESOLVED")

case "$cmd $sub" in
  "pr list")   # --head <branch> --state all --repo R --json <fields> --limit N
    head=""; shift 2
    while [ $# -gt 0 ]; do case "$1" in --head) head="$2"; shift 2 ;; *) shift ;; esac; done
    # A read that FAILS. Its stdout is empty and its exit status is non-zero — the
    # difference between "nothing is open from this branch" and "I could not ask".
    [ -s "$FAKE_LISTFAIL" ] && exit 1
    if [ "$RESOLVED" = "github.com/acme/repo" ]; then
      awk -F'|' -v b="$head" '$1==b{print}' "$FAKE_EXISTPR" | rows_json
    elif grep -qxF "$head" "$FAKE_FOREIGNPR" 2>/dev/null; then
      # THE HAZARD: a stranger's repository carries a branch of the same name with
      # an open PR. Same shape as ours, different repository.
      printf '%s|777|https://%s/%s/pull/777|OPEN|main|%s|%s\n' \
        "$head" "${RESOLVED%%/*}" "${RESOLVED#*/}" "$head" "${RESOLVED#*/}" | rows_json
    else printf '[]\n'; fi ;;
  "pr create") # --repo R --base X --head <branch> --title T --body-file F
    head=""; bodyfile=""; shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --head) head="$2"; shift 2 ;;
        --body-file) bodyfile="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    # The body as the pass actually wrote it — where the supersede pointer lives.
    [ -n "$bodyfile" ] && [ -f "$bodyfile" ] \
      && { printf '=== %s\n' "$head"; cat "$bodyfile"; } >> "$FAKE_CREATEDBODY"
    row=$(awk -F'|' -v b="$head" '$1==b{print; exit}' "$FAKE_NEWPR")
    if [ -z "$row" ]; then
      # A CONCURRENT OPEN. Real `gh pr create` fails here ("a pull request already
      # exists"), and the PR is visible to the next list from then on.
      racerow=$(awk -F'|' -v b="$head" '$1==b{print; exit}' "$FAKE_RACEPR")
      [ -n "$racerow" ] && printf '%s\n' "$racerow" >> "$FAKE_EXISTPR"
      exit 1
    fi
    printf '%s\n' "$head" >> "$FAKE_CREATED"
    # WHERE the PR was opened, not just for which branch: a PR opened in the
    # wrong repository is the failure these identity tests exist to catch.
    printf '%s\t%s\n' "$head" "$RESOLVED" >> "$FAKE_CREATEDWHERE"
    if [ "$RESOLVED" = "github.com/acme/repo" ]; then
      printf '%s\n' "$(printf '%s' "$row" | cut -d'|' -f3)"   # the new PR url
    else
      printf 'https://%s/%s/pull/%s\n' "${RESOLVED%%/*}" "${RESOLVED#*/}" \
        "$(printf '%s' "$row" | cut -d'|' -f2)"
    fi ;;
  "pr view")   # <number> --repo R --json <fields>   (reading a created PR back)
    arg="$3"; shift 3
    # BY NUMBER ONLY. Resolving a pull request by BRANCH NAME is the identity gap
    # this pass closed — `gh pr view <branch>` picks whatever is open from a branch
    # of that name, fork or not. Record any relapse and fail the call.
    case "$arg" in
      ''|*[!0-9]*) printf '%s\n' "$arg" >> "$FAKE_VIEWBYNAME"; exit 1 ;;
    esac
    row=$(awk -F'|' -v n="$arg" '$2==n{print; exit}' "$FAKE_NEWPR" "$FAKE_EXISTPR")
    [ -n "$row" ] || exit 1
    if [ "$RESOLVED" != "github.com/acme/repo" ]; then
      # Answered from somewhere else: a stranger's pull request of the same number.
      row=$(printf '%s|%s|https://%s/%s/pull/%s|OPEN|main|%s|%s' \
        "$(printf '%s' "$row" | cut -d'|' -f1)" "$arg" \
        "${RESOLVED%%/*}" "${RESOLVED#*/}" "$arg" \
        "$(printf '%s' "$row" | cut -d'|' -f6)" "${RESOLVED#*/}")
    fi
    # headRefOid — the commit the pull request is actually OPEN AT, which is what the
    # create path certifies against the reviewed head. Column 8 when a fixture states
    # it; otherwise the branch's live head, so every pre-existing row keeps meaning
    # "opened at exactly the head that was just certified" and only the drift case
    # below has to say anything.
    if [ -z "$(printf '%s' "$row" | cut -d'|' -f8)" ]; then
      row="$row|$(awk -F'|' -v b="$(printf '%s' "$row" | cut -d'|' -f1)" \
                    '$1==b{print $2; exit}' "$FAKE_HEADS")"
    fi
    printf '%s\n' "$row" | rows_json | jq -c '.[0]' ;;
  "pr comment") # <num> --repo R --body ...
    printf '%s\n' "$3" >> "$FAKE_COMMENTS"
    printf '%s\t%s\n' "$3" "$RESOLVED" >> "$FAKE_COMMENTWHERE"
    cnum="$3"; cbody=""; shift 3
    while [ $# -gt 0 ]; do case "$1" in --body) cbody="$2"; shift 2 ;; *) shift ;; esac; done
    # WHICH pull request was told WHAT: the supersede pointer is posted on the DEAD
    # one, so the number alone cannot tell the two comments this pass writes apart.
    printf '%s\t%s\n' "$cnum" "$(printf '%s' "$cbody" | tr '\n' ' ')" >> "$FAKE_COMMENTBODY" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list (anchors + review lookup), bd show (notes + metadata),
#     bd update (a real per-key ledger). ------------------------------------------
#
# THE LEDGER IS MODELLED, not just the command line. What is under test at the flip
# is an ORDER of writes and a RE-READ (review tk-pka2d finding #1), and a stub that
# only records "an update mentioning merge_result happened" cannot express either:
# it would report a flip for a write that never persisted, and `gc bd show` would
# have no metadata to verify against. So writes land in a `<id>\t<key>\t<value>`
# store (last write wins) and `bd show` reads that store back.
#
# $FAKE_DROP is the partial write itself: a `<id>\t<key>` row makes writes of that
# key for that bead vanish while `gc bd update` still exits 0 — exactly what a
# `gc bd update` that persisted some of its --set-metadata flags and not others
# looks like from the caller's side.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0

meta_get() {
  awk -F'\t' -v i="$1" -v k="$2" '$1==i && $2==k{v=$3} END{printf "%s", v}' "$FAKE_META" 2>/dev/null
}

case "$2" in
  list)
    case "$*" in
      *"merge_result=pre_open_gate"*)
        out=""
        while IFS='|' read -r id branch target codexmark mhold rhold; do
          [ -n "$id" ] || continue
          # Convergence is a LEDGER fact: an anchor whose merge_result actually
          # PERSISTED as pull_request has left this scan. One whose flip did not
          # persist is still in it — which is the whole point of splitting the write.
          [ "$(meta_get "$id" merge_result)" = "pull_request" ] && continue
          obj=$(printf '{"id":"%s","title":"impl %s","description":"desc %s","metadata":{"branch":"%s","merged_target":"%s","check.codex":"%s","merge_hold":"%s","rebase_hold":"%s","merge_result":"pre_open_gate"}}' \
            "$id" "$id" "$id" "$branch" "$target" "$codexmark" "$mhold" "$rhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      *"task_kind=review"*)
        aid=$(printf '%s' "$*" | sed -n 's/.*anchor_bead=\([^ ]*\).*/\1/p')
        rid=$(awk -F'|' -v a="$aid" '$1==a{print $2; exit}' "$FAKE_REVIEWS" 2>/dev/null)
        if [ -n "$rid" ]; then printf '[{"id":"%s","updated_at":"1"}]\n' "$rid"; else printf '[]\n'; fi ;;
      *) printf '[]\n' ;;
    esac ;;
  show)
    # Serves BOTH readers: the review bead's verdict notes, and the anchor's
    # metadata (what the flip verifies its own writes against).
    rid="$3"
    notes=$(awk -F'|' -v r="$rid" '$1==r{print $2; exit}' "$FAKE_NOTES" 2>/dev/null)
    awk -F'\t' -v i="$rid" '$1==i{print $2"\t"$3}' "$FAKE_META" 2>/dev/null \
      | jq -R -s --arg n "$notes" '
          [ split("\n")[] | select(length > 0) | split("\t")
            | {key: .[0], value: (.[1] // "")} ] | from_entries
          | [{notes: $n, metadata: .}]' ;;
  update)
    id="$3"; shift 3
    while [ $# -gt 0 ]; do
      case "$1" in
        --set-metadata)
          k="${2%%=*}"; v="${2#*=}"
          if grep -qxF "$(printf '%s\t%s' "$id" "$k")" "$FAKE_DROP" 2>/dev/null; then
            shift 2; continue      # the write vanishes; the command still succeeds
          fi
          printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_META"
          # A flip is recorded only when the VISIBILITY SWITCH itself persisted, and
          # it reports the identity fields as the ledger then holds them — so a flip
          # stamped without them could not pass the pr_number/pr_url assertions.
          if [ "$k" = "merge_result" ] && [ "$v" = "pull_request" ]; then
            printf '%s\t%s\n' "$id" "$(meta_get "$id" pr_number)" >> "$FAKE_FLIPLOG"
            printf '%s\t%s\n' "$id" "$(meta_get "$id" pr_url)" >> "$FAKE_FLIPURL"
            printf '%s\n' "$id" >> "$FAKE_FLIPPED"
          fi
          shift 2 ;;
        *) shift ;;
      esac
    done ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_HEADS="$TMP/heads" FAKE_EXISTPR="$TMP/existpr" \
       FAKE_NEWPR="$TMP/newpr" FAKE_REVIEWS="$TMP/reviews" FAKE_NOTES="$TMP/notes" \
       FAKE_CREATED="$TMP/created" FAKE_FLIPLOG="$TMP/fliplog" FAKE_FLIPPED="$TMP/flipped" \
       FAKE_COMMENTS="$TMP/comments" FAKE_CREATEDWHERE="$TMP/createdwhere" \
       FAKE_FLIPURL="$TMP/flipurl" FAKE_COMMENTWHERE="$TMP/commentwhere" \
       FAKE_FOREIGNPR="$TMP/foreignpr" FAKE_RACEPR="$TMP/racepr" \
       FAKE_VIEWBYNAME="$TMP/viewbyname" FAKE_LISTFAIL="$TMP/listfail" \
       FAKE_GH_DEFAULT="$TMP/ghdefault" FAKE_GH_HOST="$TMP/ghhost" \
       FAKE_IGNORE_REPO="$TMP/ignorerepo" \
       FAKE_IGNORE_REPO_CREATE="$TMP/ignorerepocreate" FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_META="$TMP/meta" FAKE_DROP="$TMP/drop" \
       FAKE_CREATEDBODY="$TMP/createdbody" FAKE_COMMENTBODY="$TMP/commentbody"

# --- Run 1. -------------------------------------------------------------------
OUT1="$(bash "$SCRIPT")"

# (GREEN) the sole green no-PR anchor: PR created at its branch + flipped.
has '^polecat/feat-a$' "$TMP/created" \
  && ok "(GREEN) green no-PR anchor -> 'gh pr create' at its branch" \
  || bad "(GREEN) green anchor -> PR created"
grep -q '^bead-GREEN	501$' "$TMP/fliplog" \
  && ok "(GREEN) flipped to pull_request with the NEW pr_number (501)" \
  || bad "(GREEN) flip records new pr_number (got: $(cat "$TMP/fliplog"))"
printf '%s\n' "$OUT1" | grep -q "bead-GREEN opened PR#501" \
  && ok "(GREEN) summary names the opened PR" || bad "(GREEN) open summary (got: $OUT1)"

# (STALE) marker at an old head -> held, NOT created, NOT flipped.
has '^polecat/feat-b$' "$TMP/created" && bad "(STALE) must NOT create a PR" \
                                      || ok "(STALE) no PR created"
grep -q '^bead-STALE	' "$TMP/fliplog" && bad "(STALE) must NOT flip" || ok "(STALE) not flipped"
printf '%s\n' "$OUT1" | grep -q "bead-STALE .* codex not green at live head" \
  && ok "(STALE) held, reason names the stale marker" || bad "(STALE) hold reason (got: $OUT1)"

# (MISS) no marker -> held.
has '^polecat/feat-c$' "$TMP/created" && bad "(MISS) must NOT create a PR" \
                                      || ok "(MISS) no PR created"
grep -q '^bead-MISS	' "$TMP/fliplog" && bad "(MISS) must NOT flip" || ok "(MISS) not flipped"

# (HASPR) branch already has a PR -> flipped to that PR, NO second create.
grep -q '^bead-HASPR	404$' "$TMP/fliplog" \
  && ok "(HASPR) existing-PR branch -> flipped to pull_request with the existing pr_number (404)" \
  || bad "(HASPR) flip records existing pr_number (got: $(cat "$TMP/fliplog"))"
has '^polecat/feat-d$' "$TMP/created" && bad "(HASPR) must NOT open a second PR" \
                                      || ok "(HASPR) no second PR created (orphan-convoy convergence)"

# (STATE) the existing-PR lookup must query --state all, not --state open: a
# parent stranded in pre_open_gate after a pre-open rework, whose sibling PR has
# already MERGED, must still flip onto the pull_request scan the merged-close
# observer watches (reconcile-merged-prs.sh scans only pull_request). A --state
# open lookup would miss the merged sibling and strand the parent open forever.
grep -qF 'gh pr list --head "$branch" --state all' "$SCRIPT" \
  && ok "(STATE) existing-PR lookup uses --state all (a merged/closed sibling PR still flips the orphan → observable)" \
  || bad "(STATE) existing-PR lookup must use --state all so a merged sibling PR flips the orphan (observer-blindness fix)"

# (INV) exactly one `gh pr create` this pass — only the green no-PR anchor.
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(INV) exactly one PR created (the green no-PR anchor)"

# (URL) the identity stamped on the anchor is the canonical pull-request URL, in
# BOTH arms — it is what every later pass re-derives the repository from.
grep -q '^bead-GREEN	https://github.com/acme/repo/pull/501$' "$TMP/flipurl" \
  && ok "(URL) the opened PR is stamped with its canonical URL" \
  || bad "(URL) opened-PR pr_url (got: $(cat "$TMP/flipurl"))"
grep -q '^bead-HASPR	https://github.com/acme/repo/pull/404$' "$TMP/flipurl" \
  && ok "(URL) the discovered PR is stamped with its canonical URL" \
  || bad "(URL) existing-PR pr_url (got: $(cat "$TMP/flipurl"))"

# Summary counters: 1 opened, 1 flipped, 2 held.
printf '%s\n' "$OUT1" | grep -q "1 opened, 1 flipped, 2 held" \
  && ok "run 1 summary reports 1 opened, 1 flipped, 2 held" || bad "run 1 summary (got: $OUT1)"

# --- Run 2: convergence. Flipped anchors left the pre_open_gate set. -----------
bash "$SCRIPT" >/dev/null
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(CONV) green anchor not re-created on second pass"
eq "$(grep -c '^bead-GREEN	' "$TMP/fliplog")" "1" "(CONV) green anchor not re-flipped on second pass"
eq "$(grep -c '^bead-HASPR	' "$TMP/fliplog")" "1" "(CONV) has-PR anchor not re-flipped on second pass"

# ==============================================================================
# REPOSITORY IDENTITY (review tk-jc66l).
#
# A fresh two-anchor scenario, replayed under each way gh's idea of "this
# repository" can drift:
#   bead-IDG / polecat/feat-id  : no PR here -> should OPEN one (909)
#   bead-IDH / polecat/feat-idh : a PR here (808) -> should FLIP onto it
# A stranger's repository carries `polecat/feat-idh` with an open PR too, so an
# unpinned or uncertified lookup has something wrong to find.
# ==============================================================================
id_reset() {
  cat > "$TMP/anchors" <<'A'
bead-IDG|polecat/feat-id|main|green@HEADID
bead-IDH|polecat/feat-idh|main|green@HEADIDH
A
  cat > "$TMP/heads" <<'H'
polecat/feat-id|HEADID
polecat/feat-idh|HEADIDH
H
  cat > "$TMP/existpr" <<'E'
polecat/feat-idh|808|https://github.com/acme/repo/pull/808|OPEN|main|polecat/feat-idh|acme/repo
E
  cat > "$TMP/newpr" <<'N'
polecat/feat-id|909|https://github.com/acme/repo/pull/909|OPEN|main|polecat/feat-id|acme/repo
N
  printf 'polecat/feat-idh\n' > "$TMP/foreignpr"
  : > "$TMP/racepr"
  : > "$TMP/created"; : > "$TMP/createdwhere"; : > "$TMP/fliplog"
  : > "$TMP/flipurl"; : > "$TMP/flipped"; : > "$TMP/comments"; : > "$TMP/commentwhere"
  : > "$TMP/meta"; : > "$TMP/drop"
  : > "$TMP/viewbyname"
  : > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
  : > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"
}

# --- (ID1) gh's current repository is MOVED. ----------------------------------
# `gh repo set-default evil/repo` / GH_REPO. Every read and the create are pinned
# to the ORIGIN-derived repository, so the drift changes nothing: the right branch
# head answers, the right existing PR is found, and the new PR is opened here.
id_reset
printf 'evil/repo\n' > "$TMP/ghdefault"
bash "$SCRIPT" >"$TMP/outid1" 2>"$TMP/errid1"
grep -q '^polecat/feat-id	github.com/acme/repo$' "$TMP/createdwhere" \
  && ok "(ID1) moved gh default -> the PR is still opened in the ORIGIN repository" \
  || bad "(ID1) PR must be opened in github.com/acme/repo (got: $(cat "$TMP/createdwhere"))"
grep -q '^bead-IDG	909$' "$TMP/fliplog" \
  && ok "(ID1) the opened PR's own number is stamped (909, not the stranger's)" \
  || bad "(ID1) flip pr_number (got: $(cat "$TMP/fliplog"))"
grep -q '^bead-IDH	808$' "$TMP/fliplog" \
  && ok "(ID1) the existing-PR lookup found OUR PR#808, not the foreign same-branch PR#777" \
  || bad "(ID1) existing-PR flip (got: $(cat "$TMP/fliplog"))"
grep -q '	github.com/acme/repo$' "$TMP/commentwhere" \
  && ok "(ID1) the codex verdict is commented on the ORIGIN repository's PR" \
  || bad "(ID1) comment repository (got: $(cat "$TMP/commentwhere"))"

# --- (ID2) GH_HOST drift under a hostless pin. --------------------------------
# `<owner>/<repo>` names one repository PER HOST, and gh fills the host of a
# hostless `--repo` from GH_HOST. The pins here are host-qualified (and `gh api`
# gets `--hostname`), so a moved GH_HOST cannot re-host them.
id_reset
printf 'ghe.evil.example\n' > "$TMP/ghhost"
bash "$SCRIPT" >"$TMP/outid2" 2>"$TMP/errid2"
grep -q '^polecat/feat-id	github.com/acme/repo$' "$TMP/createdwhere" \
  && ok "(ID2) moved GH_HOST -> the PR is still opened on github.com, not the drifted host" \
  || bad "(ID2) PR must be opened in github.com/acme/repo (got: $(cat "$TMP/createdwhere"))"
grep -q '^bead-IDH	808$' "$TMP/fliplog" \
  && ok "(ID2) moved GH_HOST -> the existing-PR lookup still answers from github.com/acme/repo" \
  || bad "(ID2) existing-PR flip under host drift (got: $(cat "$TMP/fliplog"))"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(ID2) exactly one PR opened under host drift"

# --- (ID3) a gh that IGNORES the pin. -----------------------------------------
# A wrapper, or a redirect after a repository transfer/rename. The pins are gone,
# so the returned URL is the only thing left to catch it — and it must, in BOTH
# arms: the foreign same-branch PR must not flip the anchor, and the foreign
# branch-head answer must not open a PR. Nothing stamped; both anchors stay
# pre_open_gate, which is the only state that retries PR-open.
id_reset
printf 'evil/repo\n' > "$TMP/ghdefault"
printf '1\n' > "$TMP/ignorerepo"
bash "$SCRIPT" >"$TMP/outid3" 2>"$TMP/errid3"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" "(ID3) ignored pin -> NO anchor flipped out of pre_open_gate"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" "(ID3) ignored pin -> NO PR opened"
grep -q "another repository's pull request" "$TMP/errid3" \
  && ok "(ID3) the foreign same-branch PR is refused by name (not flipped)" \
  || bad "(ID3) must refuse the foreign same-branch PR (err: $(cat "$TMP/errid3"))"
grep -q "head answered from 'github.com/evil/repo'" "$TMP/errid3" \
  && ok "(ID3) the foreign branch-head answer is refused by name (no PR opened at it)" \
  || bad "(ID3) must refuse the foreign branch-head answer (err: $(cat "$TMP/errid3"))"

# --- (ID4) `gh pr create` answers with a PR in another repository. ------------
# The pins are honoured everywhere else, so the head is certified and create IS
# reached — and it answers with a stranger's URL. Certifying the answer BEFORE it
# becomes this anchor's identity is the whole point: nothing is stamped.
id_reset
printf 'evil/repo\n' > "$TMP/ghdefault"
printf '1\n' > "$TMP/ignorerepocreate"
bash "$SCRIPT" >"$TMP/outid4" 2>"$TMP/errid4"
grep -q '^bead-IDG	' "$TMP/fliplog" \
  && bad "(ID4) a foreign create answer must NOT be stamped as this anchor's PR" \
  || ok "(ID4) foreign create answer -> pr_url/pr_number NOT stamped"
grep -q "NOTHING stamped, anchor stays pre_open_gate" "$TMP/errid4" \
  && ok "(ID4) the refusal says what was not done, and that the anchor can still retry" \
  || bad "(ID4) refusal message (err: $(cat "$TMP/errid4"))"
# The other anchor is untouched by this: its PR already exists here, and the
# existing-PR arm never reaches create.
grep -q '^bead-IDH	808$' "$TMP/fliplog" \
  && ok "(ID4) the create-path refusal does not disturb the existing-PR arm" \
  || bad "(ID4) existing-PR arm should still flip (got: $(cat "$TMP/fliplog"))"

# --- (ID5) unresolvable origin. -----------------------------------------------
# No origin remote, or one this script cannot parse. Every branch below would be
# resolved — and a PR CREATED — in a repository it cannot name, and an opened PR
# is a published artifact no retry can take back. Fail closed.
id_reset
printf '1\n' > "$TMP/repofail"
bash "$SCRIPT" >"$TMP/outid5" 2>"$TMP/errid5"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" "(ID5) unresolvable origin -> no PR opened this pass"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" "(ID5) unresolvable origin -> no anchor flipped this pass"
grep -q "cannot resolve this checkout's origin repository" "$TMP/errid5" \
  && ok "(ID5) unresolvable origin is announced, not silent" \
  || bad "(ID5) must warn that the origin is unresolvable (err: $(cat "$TMP/errid5"))"

# ==============================================================================
# HEAD IDENTITY — THE FORK GAP (review tk-j0q41).
#
# Everything above certifies WHERE THE ANSWER CAME FROM. None of it asks where the
# pull request is opened FROM. A fork's PR into this repository is served by the
# pinned read, carries one of OUR urls, and is matched by `--head` on the branch
# NAME — so every check above passes on it while its head is a stranger's.
#
#   bead-FORK  : only a fork's PR is open from a branch of this name
#   bead-ORDER : the fork's PR is listed FIRST, ours (open 808, closed 700) after
#   bead-BASE  : our repository, our branch — but it targets a different base
#   bead-NULLR : the head repository is NULL (a deleted fork) -> unreadable
#   bead-ADOPT : no PR here; the create answers with a FORK-HEAD pull request
# ==============================================================================
fk_reset() {
  cat > "$TMP/anchors" <<'A'
bead-FORK|polecat/feat-fork|main|green@HEADFK
bead-ORDER|polecat/feat-order|main|green@HEADOR
bead-BASE|polecat/feat-base|main|green@HEADBS
bead-NULLR|polecat/feat-nullr|main|green@HEADNR
bead-ADOPT|polecat/feat-adopt|main|green@HEADAD
A
  cat > "$TMP/heads" <<'H'
polecat/feat-fork|HEADFK
polecat/feat-order|HEADOR
polecat/feat-base|HEADBS
polecat/feat-nullr|HEADNR
polecat/feat-adopt|HEADAD
H
  # The fork rows come FIRST on purpose: `--limit 1` would have taken them.
  cat > "$TMP/existpr" <<'E'
polecat/feat-fork|777|https://github.com/acme/repo/pull/777|OPEN|main|polecat/feat-fork|forker/repo
polecat/feat-order|778|https://github.com/acme/repo/pull/778|OPEN|main|polecat/feat-order|forker/repo
polecat/feat-order|700|https://github.com/acme/repo/pull/700|CLOSED|main|polecat/feat-order|acme/repo
polecat/feat-order|808|https://github.com/acme/repo/pull/808|OPEN|main|polecat/feat-order|acme/repo
polecat/feat-base|505|https://github.com/acme/repo/pull/505|OPEN|integration/other|polecat/feat-base|acme/repo
polecat/feat-nullr|606|https://github.com/acme/repo/pull/606|OPEN|main|polecat/feat-nullr|-
E
  # `gh pr create` answers with a real url in this repository — but the pull request
  # it names is opened from a FORK's branch.
  cat > "$TMP/newpr" <<'N'
polecat/feat-adopt|909|https://github.com/acme/repo/pull/909|OPEN|main|polecat/feat-adopt|forker/repo
N
  : > "$TMP/foreignpr"; : > "$TMP/racepr"
  : > "$TMP/created"; : > "$TMP/createdwhere"; : > "$TMP/fliplog"
  : > "$TMP/flipurl"; : > "$TMP/flipped"; : > "$TMP/comments"; : > "$TMP/commentwhere"
  : > "$TMP/meta"; : > "$TMP/drop"
  : > "$TMP/viewbyname"
  : > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
  : > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"
}

fk_reset
bash "$SCRIPT" >"$TMP/outfk" 2>"$TMP/errfk"

# (FK1) a fork's same-named branch is not this anchor's work.
grep -q '^bead-FORK	' "$TMP/fliplog" \
  && bad "(FK1) a fork's same-branch PR must NOT flip the anchor" \
  || ok "(FK1) same-base fork PR reusing the branch name -> NOT flipped"
grep -q "in FORK 'forker/repo'" "$TMP/errfk" \
  && ok "(FK1) the fork is refused by name, so an operator can see which half failed" \
  || bad "(FK1) refusal must name the fork (err: $(cat "$TMP/errfk"))"

# (FK2) ...and the collision is not a licence to open one either.
has '^polecat/feat-fork$' "$TMP/created" \
  && bad "(FK2) a name collision must NOT be resolved by opening a PR into it" \
  || ok "(FK2) fork-only branch -> nothing created; the anchor waits for an operator"
grep -q "NONE of them is this anchor's" "$TMP/errfk" \
  && ok "(FK2) the refusal distinguishes 'nothing of ours matched' from 'nothing matched'" \
  || bad "(FK2) must refuse a name collision explicitly (err: $(cat "$TMP/errfk"))"

# (FK3) a fork row arriving FIRST does not win, and OPEN outranks CLOSED.
grep -q '^bead-ORDER	808$' "$TMP/fliplog" \
  && ok "(FK3) fork row listed first -> the branch's own OPEN PR (808) is selected anyway" \
  || bad "(FK3) must select the certified same-repo OPEN PR (got: $(cat "$TMP/fliplog"))"
grep -q '^bead-ORDER	https://github.com/acme/repo/pull/808$' "$TMP/flipurl" \
  && ok "(FK3) the stamped identity is the certified row's canonical URL" \
  || bad "(FK3) stamped pr_url (got: $(cat "$TMP/flipurl"))"

# (FK4) our repository, our branch name — landing somewhere else.
grep -q '^bead-BASE	' "$TMP/fliplog" \
  && bad "(FK4) a PR targeting a different base must NOT be flipped onto" \
  || ok "(FK4) same-repo PR with a different base -> NOT flipped"
grep -q "targets 'integration/other'" "$TMP/errfk" \
  && ok "(FK4) the base mismatch is refused by name" \
  || bad "(FK4) refusal must name the base (err: $(cat "$TMP/errfk"))"

# (FK5) "I cannot tell" is not "not ours" — and it is certainly not "open one".
grep -q '^bead-NULLR	' "$TMP/fliplog" \
  && bad "(FK5) an unreadable row must NOT be flipped onto" \
  || ok "(FK5) NULL head repository -> NOT flipped"
has '^polecat/feat-nullr$' "$TMP/created" \
  && bad "(FK5) an unreadable row must NOT fall through to opening a twin" \
  || ok "(FK5) NULL head repository -> nothing created (unreadable ≠ absent)"
grep -q "identity is unreadable" "$TMP/errfk" \
  && ok "(FK5) the unreadable row is announced, not silently skipped" \
  || bad "(FK5) must warn that the row is unreadable (err: $(cat "$TMP/errfk"))"

# (FK6) certify the CREATED pull request too, by reading it back BY NUMBER.
has '^polecat/feat-adopt$' "$TMP/created" \
  && ok "(FK6) the no-PR green anchor does reach 'gh pr create'" \
  || bad "(FK6) create should be reached for bead-ADOPT"
grep -q '^bead-ADOPT	' "$TMP/fliplog" \
  && bad "(FK6) a fork-head create answer must NOT be stamped as this anchor's PR" \
  || ok "(FK6) create answered with a FORK-HEAD PR -> certified on read-back, nothing stamped"
grep -q '^909$' "$TMP/comments" \
  && bad "(FK6) an uncertified PR must not be commented on either" \
  || ok "(FK6) no codex verdict is replayed onto an uncertified pull request"

# (FK7) no pull request is ever resolved by BRANCH NAME.
eq "$(wc -l < "$TMP/viewbyname" | tr -d ' ')" "0" \
  "(FK7) 'gh pr view <branch>' is never used — a branch name does not identify a PR"

# --- (RACE) a concurrent open is still discovered — and still certified. -------
# `gh pr create` loses the race and emits nothing; the PR is visible to the next
# list. Discovery runs the SAME certified scan, so the race-winner is adopted only
# if it is really ours.
fk_reset
cat > "$TMP/anchors" <<'A'
bead-RACE|polecat/feat-race|main|green@HEADRC
A
cat > "$TMP/heads" <<'H'
polecat/feat-race|HEADRC
H
: > "$TMP/existpr"
: > "$TMP/newpr"
cat > "$TMP/racepr" <<'P'
polecat/feat-race|611|https://github.com/acme/repo/pull/611|OPEN|main|polecat/feat-race|acme/repo
P
bash "$SCRIPT" >"$TMP/outrace" 2>"$TMP/errrace"
grep -q '^bead-RACE	611$' "$TMP/fliplog" \
  && ok "(RACE) create race -> the concurrently-opened PR#611 is discovered and flipped onto" \
  || bad "(RACE) race discovery (got: $(cat "$TMP/fliplog"))"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" "(RACE) the losing create opened nothing"
eq "$(wc -l < "$TMP/viewbyname" | tr -d ' ')" "0" \
  "(RACE) the race is discovered by the certified scan, never by 'gh pr view <branch>'"

# --- (READ) a failed list read is not an empty one. ----------------------------
# `gh pr list` fails outright. Read as "no PR exists", this pass would open a
# SECOND pull request for a branch that may already have one.
fk_reset
cat > "$TMP/anchors" <<'A'
bead-READ|polecat/feat-read|main|green@HEADRD
A
cat > "$TMP/heads" <<'H'
polecat/feat-read|HEADRD
H
cat > "$TMP/newpr" <<'N'
polecat/feat-read|612|https://github.com/acme/repo/pull/612|OPEN|main|polecat/feat-read|acme/repo
N
printf '1\n' > "$TMP/listfail"
bash "$SCRIPT" >"$TMP/outread" 2>"$TMP/errread"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" "(READ) failed pull-request read -> NO PR opened (no twin)"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" "(READ) failed pull-request read -> nothing flipped"
grep -q "could not read this repository's pull requests" "$TMP/errread" \
  && ok "(READ) the failed read is announced as a refusal, not treated as an empty answer" \
  || bad "(READ) must warn that the read failed (err: $(cat "$TMP/errread"))"

# --- (TRUNC) a full page is not a complete answer. -----------------------------
# The branch matches as many pull requests as this pass reads in one page, so the
# list may be cut short of the row that says a PR of ours already exists.
fk_reset
cat > "$TMP/anchors" <<'A'
bead-TRUNC|polecat/feat-trunc|main|green@HEADTR
A
cat > "$TMP/heads" <<'H'
polecat/feat-trunc|HEADTR
H
: > "$TMP/existpr"
for i in $(seq 1 100); do
  printf 'polecat/feat-trunc|%s|https://github.com/acme/repo/pull/%s|CLOSED|main|polecat/feat-trunc|forker%s/repo\n' \
    "$((3000 + i))" "$((3000 + i))" "$i" >> "$TMP/existpr"
done
cat > "$TMP/newpr" <<'N'
polecat/feat-trunc|613|https://github.com/acme/repo/pull/613|OPEN|main|polecat/feat-trunc|acme/repo
N
bash "$SCRIPT" >"$TMP/outtrunc" 2>"$TMP/errtrunc"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" "(TRUNC) a possibly-truncated page -> NO PR opened"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" "(TRUNC) a possibly-truncated page -> nothing flipped"
grep -q "the list may be truncated" "$TMP/errtrunc" \
  && ok "(TRUNC) the truncation risk is announced, not silently concluded away" \
  || bad "(TRUNC) must warn that the list may be truncated (err: $(cat "$TMP/errtrunc"))"

# --- PARTIAL WRITE at the visibility flip (review tk-pka2d finding #1). --------
# `merge_result=pull_request` is the VISIBILITY SWITCH: pre_open_gate is the only
# sub-state that opens (or re-adopts) a PR, and pull_request is the one merge-skill
# and the merged-close observer act on. Written in ONE `gc bd update` with
# pr_url/pr_number/merged_target, a write that persisted the switch and dropped a
# dependent field left an anchor that had LEFT the only state that would ever open
# its PR and ENTERED the states that act on a pr_url/pr_number it does not have —
# where both passes skip it on an empty number and nothing routes it back.
#
# $FAKE_DROP makes one key's write vanish while `gc bd update` still succeeds, which
# is what a partial write looks like from this script's side.
pw_reset() {
  cat > "$TMP/anchors" <<'A'
bead-PW|polecat/feat-pw|main|green@HEADPW
A
  cat > "$TMP/heads" <<'H'
polecat/feat-pw|HEADPW
H
  : > "$TMP/existpr"
  cat > "$TMP/newpr" <<'N'
polecat/feat-pw|701|https://github.com/acme/repo/pull/701|OPEN|main|polecat/feat-pw|acme/repo
N
  : > "$TMP/foreignpr"; : > "$TMP/racepr"; : > "$TMP/reviews"; : > "$TMP/notes"
  : > "$TMP/created"; : > "$TMP/createdwhere"; : > "$TMP/fliplog"
  : > "$TMP/flipurl"; : > "$TMP/flipped"; : > "$TMP/comments"; : > "$TMP/commentwhere"
  : > "$TMP/meta"; : > "$TMP/drop"
  : > "$TMP/viewbyname"
  : > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
  : > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"
}

# (PW0) POSITIVE CONTROL. Nothing dropped: the anchor opens its PR and flips, and
# the flip is recorded WITH the identity fields already in the ledger — which is the
# ordering assertion. If the switch were still written first (or together), the
# ledger would hold no pr_number at the moment merge_result landed.
pw_reset
bash "$SCRIPT" >"$TMP/outpw0" 2>"$TMP/errpw0"
grep -q '^bead-PW	701$' "$TMP/fliplog" \
  && ok "(PW0) control: the flip persists, and pr_number is ALREADY in the ledger when it does" \
  || bad "(PW0) control: flip must record pr_number 701 (got: $(cat "$TMP/fliplog"))"
grep -q '^bead-PW	https://github.com/acme/repo/pull/701$' "$TMP/flipurl" \
  && ok "(PW0) control: pr_url is already in the ledger at the flip too" \
  || bad "(PW0) control: flip must record pr_url (got: $(cat "$TMP/flipurl"))"

# (PW1) A DEPENDENT FIELD IS DROPPED. pr_url does not persist. The switch must NOT
# be thrown: an anchor visible to the merge and observer passes with no PR identity
# for them to act on is the invisible-anchor failure from the other side, and
# nothing would route it back.
pw_reset
printf 'bead-PW\tpr_url\n' > "$TMP/drop"
bash "$SCRIPT" >"$TMP/outpw1" 2>"$TMP/errpw1"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(PW1) a dropped pr_url -> merge_result is NOT flipped"
grep -q '^bead-PW	merge_result	pull_request$' "$TMP/meta" \
  && bad "(PW1) merge_result must not reach the ledger when its dependent fields did not" \
  || ok "(PW1) the anchor stays pre_open_gate (the state that re-adopts the PR next pass)"
grep -q "identity fields did NOT persist" "$TMP/errpw1" \
  && ok "(PW1) the refusal names the fields that did not persist" \
  || bad "(PW1) must report the failed identity write (err: $(cat "$TMP/errpw1"))"

# (PW1b) ...and the PR it DID open is not lost or twinned. The anchor is still
# pre_open_gate, so the next pass takes the existing-PR arm, certifies that same PR
# and adopts it — one create across both passes, never two.
printf '%s\n' 'polecat/feat-pw|701|https://github.com/acme/repo/pull/701|OPEN|main|polecat/feat-pw|acme/repo' \
  > "$TMP/existpr"
: > "$TMP/drop"
bash "$SCRIPT" >"$TMP/outpw1b" 2>"$TMP/errpw1b"
eq "$(grep -c '^polecat/feat-pw$' "$TMP/created")" "1" \
   "(PW1b) the retry re-adopts the PR it already opened — never a twin create"
grep -q '^bead-PW	701$' "$TMP/fliplog" \
  && ok "(PW1b) the retry completes the flip onto that same PR" \
  || bad "(PW1b) retry must flip onto PR#701 (got: $(cat "$TMP/fliplog"))"

# (PW2) THE SWITCH ITSELF IS DROPPED. The identity fields persisted; merge_result did
# not. This is the SAFE half of the split — the anchor keeps a correct identity and
# stays where the next pass can finish the job — but it must still be REPORTED, not
# counted as a success.
pw_reset
printf 'bead-PW\tmerge_result\n' > "$TMP/drop"
bash "$SCRIPT" >"$TMP/outpw2" 2>"$TMP/errpw2"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" "(PW2) a dropped merge_result -> no flip recorded"
grep -q '^bead-PW	pr_url	https://github.com/acme/repo/pull/701$' "$TMP/meta" \
  && ok "(PW2) the identity fields still persisted (the safe half of the split)" \
  || bad "(PW2) identity fields should persist even when the switch does not"
grep -q "merge_result is still" "$TMP/errpw2" \
  && ok "(PW2) the un-thrown switch is reported for an operator" \
  || bad "(PW2) must report that merge_result did not persist (err: $(cat "$TMP/errpw2"))"
printf '%s\n' "$(cat "$TMP/outpw2")" | grep -q "0 opened" \
  && ok "(PW2) the pass does not count an incomplete flip as opened" \
  || bad "(PW2) summary must not report it as opened (got: $(cat "$TMP/outpw2"))"

# --- The created PR must be born at the REVIEWED head (review tk-pka2d, residual
#     risk). `--head` names a MUTABLE ref: the codex gate compares check.codex to the
#     branch head read moments earlier, but `gh pr create` opens the PR at whatever
#     that ref points to WHEN IT RUNS. A recovery polecat or an operator fixup landing
#     in that window publishes a NON-DRAFT PR at an UNREVIEWED commit — and this pass's
#     whole contract is that a PR is codex-green at birth.
pw_reset
# The create answers with a PR whose head is HEADPW2 — the branch moved after the
# gate read HEADPW. Column 8 is the head the pull request is actually open at.
cat > "$TMP/newpr" <<'N'
polecat/feat-pw|702|https://github.com/acme/repo/pull/702|OPEN|main|polecat/feat-pw|acme/repo|HEADPW2
N
bash "$SCRIPT" >"$TMP/outoid" 2>"$TMP/erroid"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(OIDDRIFT) a PR opened past the reviewed head -> nothing stamped"
eq "$(wc -l < "$TMP/comments" | tr -d ' ')" "0" \
   "(OIDDRIFT) ...and no 'codex signed off at <commit>' comment is posted about it"
grep -q "not the reviewed 'HEADPW'" "$TMP/erroid" \
  && ok "(OIDDRIFT) the refusal names both the opened head and the reviewed one" \
  || bad "(OIDDRIFT) must name the head drift (err: $(cat "$TMP/erroid"))"

# --- OPERATOR HOLDS (tk-3j0ob). ------------------------------------------------
# merge_hold/rebase_hold on the anchor are explicit operator gates, honored by
# merge-skill.sh, reconcile-merged-prs.sh and reconcile-graduated-convoys.sh — and,
# until this fix, by NEITHER arm of this pass. A hold stopped a held anchor from
# MERGING while the open side walked straight past it and PUBLISHED a pull request
# against it, so the operator saw a hold in place and a new PR appear anyway.
hold_reset() {   # <merge_hold> <rebase_hold>
  printf 'bead-HOLD|polecat/feat-hold|main|green@HEADHOLD|%s|%s\n' "${1:-}" "${2:-}" \
    > "$TMP/anchors"
  cat > "$TMP/heads" <<'H'
polecat/feat-hold|HEADHOLD
H
  : > "$TMP/existpr"
  cat > "$TMP/newpr" <<'N'
polecat/feat-hold|801|https://github.com/acme/repo/pull/801|OPEN|main|polecat/feat-hold|acme/repo
N
  : > "$TMP/foreignpr"; : > "$TMP/racepr"; : > "$TMP/reviews"; : > "$TMP/notes"
  : > "$TMP/created"; : > "$TMP/createdwhere"; : > "$TMP/fliplog"
  : > "$TMP/flipurl"; : > "$TMP/flipped"; : > "$TMP/comments"; : > "$TMP/commentwhere"
  : > "$TMP/meta"; : > "$TMP/drop"
  : > "$TMP/viewbyname"
  : > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
  : > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"
}

# (HOLD0) POSITIVE CONTROL, run FIRST so the assertions below mean something. The
# anchor is green, has no PR, and carries the explicit "off" spellings — `false`
# and `0`, the values an operator's cleared marker actually leaves behind. It must
# OPEN. A gate that held unconditionally would pass every HOLD case that follows
# while silently stopping the pass dead for every unheld anchor in the city.
hold_reset false 0
bash "$SCRIPT" >"$TMP/outh0" 2>"$TMP/errh0"
has '^polecat/feat-hold$' "$TMP/created" \
  && ok "(HOLD0) control: merge_hold=false / rebase_hold=0 do NOT hold — the PR still opens" \
  || bad "(HOLD0) control: an unheld anchor must still open its PR (err: $(cat "$TMP/errh0"))"
grep -q '^bead-HOLD	801$' "$TMP/fliplog" \
  && ok "(HOLD0) control: ...and it still flips to pull_request" \
  || bad "(HOLD0) control: flip must record pr_number 801 (got: $(cat "$TMP/fliplog"))"

# (HOLD1) merge_hold — "do not land this yet", and opening the PR is what arms the
# landing. Nothing may be published: not the pull request, not the codex-signoff
# comment that names a commit as reviewed.
hold_reset true ""
OUTH1="$(bash "$SCRIPT" 2>"$TMP/errh1")"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(HOLD1) merge_hold set -> NO pull request is opened"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(HOLD1) ...and the anchor is not flipped out of pre_open_gate"
eq "$(wc -l < "$TMP/comments" | tr -d ' ')" "0" \
   "(HOLD1) ...and no codex-signoff comment is published about it"
printf '%s\n' "$OUTH1" | grep -q "bead-HOLD branch 'polecat/feat-hold' merge_hold set (operator gate)" \
  && ok "(HOLD1) the refusal names the marker, so a held anchor is diagnosable" \
  || bad "(HOLD1) must name merge_hold (got: $OUTH1)"
printf '%s\n' "$OUTH1" | grep -q "0 opened, 0 flipped, 1 held" \
  && ok "(HOLD1) counted as HELD (an operator gate), not as a skip" \
  || bad "(HOLD1) summary must count it held (got: $OUTH1)"

# (HOLD2) rebase_hold — the narrower "do not rebase/force-push this branch", which
# is exactly the branch a PR would be published FROM. This pass's contract is that
# a PR is codex-green AT BIRTH; a branch frozen for rewriting is one whose reviewed
# head is expected to move, so the PR would be born green and be stale moments
# later, over a comment asserting a signoff at a commit that has left the branch.
hold_reset "" true
OUTH2="$(bash "$SCRIPT" 2>"$TMP/errh2")"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(HOLD2) rebase_hold set -> NO pull request is opened"
eq "$(wc -l < "$TMP/comments" | tr -d ' ')" "0" \
   "(HOLD2) ...and nothing is commented on the branch the operator froze"
printf '%s\n' "$OUTH2" | grep -q "bead-HOLD branch 'polecat/feat-hold' rebase_hold set (operator gate)" \
  && ok "(HOLD2) the refusal names rebase_hold specifically, not merge_hold" \
  || bad "(HOLD2) must name rebase_hold (got: $OUTH2)"
printf '%s\n' "$OUTH2" | grep -q "0 opened, 0 flipped, 1 held" \
  && ok "(HOLD2) counted as held" || bad "(HOLD2) summary (got: $OUTH2)"

# (HOLD3) THE HOLD IS ON THE IRREVERSIBLE HALF ONLY. A held anchor whose branch
# ALREADY has a pull request is still FLIPPED: adopting a PR that exists publishes
# nothing, and the gates it hands the anchor to honor these same markers themselves
# (merge-skill.sh holds on merge_hold; reconcile-merged-prs.sh holds its rebase
# dispatch on either). Holding the flip too would COST the convergence it exists
# for — pre_open_gate is invisible to the merged-close observer, which scans only
# pull_request, so a held anchor whose sibling PR merged would leak open forever.
hold_reset true true
printf '%s\n' 'polecat/feat-hold|802|https://github.com/acme/repo/pull/802|OPEN|main|polecat/feat-hold|acme/repo' \
  > "$TMP/existpr"
bash "$SCRIPT" >"$TMP/outh3" 2>"$TMP/errh3"
grep -q '^bead-HOLD	802$' "$TMP/fliplog" \
  && ok "(HOLD3) a held anchor still adopts the PR its branch already has (convergence preserved)" \
  || bad "(HOLD3) held anchor must still flip onto PR#802 (got: $(cat "$TMP/fliplog"))"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(HOLD3) ...and still opens nothing of its own"

# (HOLD4) THE HOLD PRECEDES THE BRANCH-HEAD READ. With the gate placed after it, a
# held anchor whose head cannot be read would be reported as a transient "retry
# next pass" skip — the operator's deliberate block rendered as a read failure, and
# counted in the wrong bucket. Same ordering merge-skill.sh gives merge_hold among
# its validate gates: cheapest, and highest priority.
hold_reset true ""
: > "$TMP/heads"          # the branch head cannot be resolved at all
OUTH4="$(bash "$SCRIPT" 2>"$TMP/errh4")"
printf '%s\n' "$OUTH4" | grep -q "merge_hold set (operator gate)" \
  && ok "(HOLD4) an unreadable head does not mask the hold — the operator gate is reported" \
  || bad "(HOLD4) must report the hold (got: $OUTH4 / err: $(cat "$TMP/errh4"))"
grep -q "head unresolved" "$TMP/errh4" \
  && bad "(HOLD4) the head read must not be reached for a held anchor" \
  || ok "(HOLD4) the gate short-circuits before the branch-head read (no I/O for a held anchor)"
printf '%s\n' "$OUTH4" | grep -q "0 opened, 0 flipped, 1 held" \
  && ok "(HOLD4) counted as held, not skipped" || bad "(HOLD4) summary (got: $OUTH4)"

# ==============================================================================
# THE DEAD PULL REQUEST (tk-g0hd2).
#
# `--state all` is deliberate — a MERGED sibling PR must still flip the anchor onto
# the scan the merged-close observer watches — but the three states it returns are
# not interchangeable. A CLOSED-and-NOT-MERGED pull request is DEAD: it is what a
# deliberate supersede leaves behind after a corrected-scope force-push. Adopting it
# moved the anchor out of pre_open_gate (the ONLY state that retries PR-open) onto a
# pull request that can never merge, while no open pull request existed for the work
# at all — the live incident on anchor tk-4jz9s / PR#212.
#
# Three anchors, one pass, covering the bead's three acceptance criteria at once:
#   bead-DEAD : its branch's ONLY pull request is closed-unmerged at an OLD head
#               -> a FRESH pull request is opened, pointing at the one it supersedes
#   bead-MRG  : a MERGED sibling PR                 -> still flipped (no regression)
#   bead-LIVE : an OPEN PR beside a closed-unmerged one -> still reuses the OPEN one
# ==============================================================================
dead_reset() {
  cat > "$TMP/anchors" <<'A'
bead-DEAD|polecat/feat-dead|main|green@HEADDEAD
bead-MRG|polecat/feat-mrg|main|green@HEADMRG
bead-LIVE|polecat/feat-live|main|green@HEADLIVE
A
  cat > "$TMP/heads" <<'H'
polecat/feat-dead|HEADDEAD
polecat/feat-mrg|HEADMRG
polecat/feat-live|HEADLIVE
H
  # Column 8 is the commit the pull request is open AT — for a closed one, the head
  # it was closed at. It is what tells a re-implemented branch from an operator's
  # close of exactly this commit, so every dead row states it.
  cat > "$TMP/existpr" <<'E'
polecat/feat-dead|601|https://github.com/acme/repo/pull/601|CLOSED|main|polecat/feat-dead|acme/repo|OLDDEAD
polecat/feat-mrg|603|https://github.com/acme/repo/pull/603|MERGED|main|polecat/feat-mrg|acme/repo|HEADMRG
polecat/feat-live|604|https://github.com/acme/repo/pull/604|CLOSED|main|polecat/feat-live|acme/repo|OLDLIVE
polecat/feat-live|605|https://github.com/acme/repo/pull/605|OPEN|main|polecat/feat-live|acme/repo|HEADLIVE
E
  cat > "$TMP/newpr" <<'N'
polecat/feat-dead|602|https://github.com/acme/repo/pull/602|OPEN|main|polecat/feat-dead|acme/repo
N
  cat > "$TMP/reviews" <<'R'
bead-DEAD|rev-dead
R
  cat > "$TMP/notes" <<'NT'
rev-dead|Codex signoff: LGTM (pre-open, re-implemented at corrected scope).
NT
  : > "$TMP/foreignpr"; : > "$TMP/racepr"
  : > "$TMP/created"; : > "$TMP/createdwhere"; : > "$TMP/fliplog"
  : > "$TMP/flipurl"; : > "$TMP/flipped"; : > "$TMP/comments"; : > "$TMP/commentwhere"
  : > "$TMP/createdbody"; : > "$TMP/commentbody"
  : > "$TMP/meta"; : > "$TMP/drop"
  : > "$TMP/viewbyname"
  : > "$TMP/ghdefault"; : > "$TMP/ghhost"; : > "$TMP/ignorerepo"
  : > "$TMP/ignorerepocreate"; : > "$TMP/repofail"; : > "$TMP/listfail"
}

dead_reset
OUTD="$(bash "$SCRIPT" 2>"$TMP/errdead")"

# (DEAD1) THE BUG. A branch whose only pull request is closed-unmerged, codex green
# at the live head, gets a FRESH pull request — never a flip onto the dead one.
has '^polecat/feat-dead$' "$TMP/created" \
  && ok "(DEAD1) closed-unmerged-only branch -> a FRESH PR is opened" \
  || bad "(DEAD1) must open a fresh PR for the superseded branch (created: $(cat "$TMP/created"))"
grep -q '^bead-DEAD	602$' "$TMP/fliplog" \
  && ok "(DEAD1) the anchor is flipped onto the FRESH PR#602" \
  || bad "(DEAD1) flip must record the fresh pr_number 602 (got: $(cat "$TMP/fliplog"))"
grep -q '^bead-DEAD	601$' "$TMP/fliplog" \
  && bad "(DEAD1) must NOT flip onto the dead PR#601 — it can never merge" \
  || ok "(DEAD1) the dead PR#601 is never stamped as the anchor's identity"
grep -q '^bead-DEAD	https://github.com/acme/repo/pull/602$' "$TMP/flipurl" \
  && ok "(DEAD1) pr_url is the fresh pull request's" \
  || bad "(DEAD1) pr_url (got: $(cat "$TMP/flipurl"))"

# (DEAD2) NO REGRESSION on the case `--state all` exists for: a MERGED sibling PR
# still flips the anchor, so reconcile-merged-prs.sh (which scans only
# merge_result=pull_request) can close it. A merged pull request is landed work, not
# a dead one — the distinction is mergedAt, not "not OPEN".
grep -q '^bead-MRG	603$' "$TMP/fliplog" \
  && ok "(DEAD2) a MERGED sibling PR still flips the anchor (observer path preserved)" \
  || bad "(DEAD2) merged sibling must still flip (got: $(cat "$TMP/fliplog"))"
has '^polecat/feat-mrg$' "$TMP/created" \
  && bad "(DEAD2) must NOT open a PR for a branch whose work already merged" \
  || ok "(DEAD2) no PR opened for the merged branch"

# (DEAD3) NO REGRESSION on the live case, and the ranking that makes it hold: a
# closed-unmerged row sitting next to an OPEN one must not win, and must not drag
# the branch onto the create path either.
grep -q '^bead-LIVE	605$' "$TMP/fliplog" \
  && ok "(DEAD3) an OPEN PR beside a dead one is still the one adopted (605, not 604)" \
  || bad "(DEAD3) must adopt the OPEN PR#605 (got: $(cat "$TMP/fliplog"))"
has '^polecat/feat-live$' "$TMP/created" \
  && bad "(DEAD3) must NOT open a twin for a branch that already has an open PR" \
  || ok "(DEAD3) no twin opened for the branch with a live PR"

# (DEAD4) THE POINTER, from both ends. The body cross-references the superseded pull
# request (which is what makes GitHub render the backlink), and the dead PR itself is
# told where the work went — that is where a human who opens #601 is standing.
grep -q 'Supersedes #601' "$TMP/createdbody" \
  && ok "(DEAD4) the fresh PR body names the pull request it supersedes" \
  || bad "(DEAD4) body must name 'Supersedes #601' (got: $(cat "$TMP/createdbody"))"
grep -q '^601	Superseded by #602' "$TMP/commentbody" \
  && ok "(DEAD4) the superseded PR#601 is commented with the pointer forward" \
  || bad "(DEAD4) pointer comment on the dead PR (got: $(cat "$TMP/commentbody"))"
grep -q '^602	Codex signoff' "$TMP/commentbody" \
  && ok "(DEAD4) ...and the codex verdict still lands on the FRESH PR, not the dead one" \
  || bad "(DEAD4) codex verdict comment (got: $(cat "$TMP/commentbody"))"

eq "$(wc -l < "$TMP/created" | tr -d ' ')" "1" "(DEAD5) exactly one PR opened this pass"
printf '%s\n' "$OUTD" | grep -q "superseding closed PR#601" \
  && ok "(DEAD5) the summary line says the fresh PR supersedes the dead one" \
  || bad "(DEAD5) summary must name the supersede (got: $OUTD)"
printf '%s\n' "$OUTD" | grep -q "1 opened, 2 flipped, 0 held" \
  && ok "(DEAD5) counters: 1 opened, 2 flipped, 0 held" || bad "(DEAD5) summary (got: $OUTD)"

# (DEAD6) CONVERGENCE. The fresh pull request outranks the headstone from the next
# pass on — modelled the way (PW1b) models it, by making the opened PR visible to the
# list and re-running with the flip suppressed. One create across both passes.
dead_reset
printf 'bead-DEAD\tmerge_result\n' > "$TMP/drop"
bash "$SCRIPT" >/dev/null 2>&1
printf '%s\n' 'polecat/feat-dead|602|https://github.com/acme/repo/pull/602|OPEN|main|polecat/feat-dead|acme/repo|HEADDEAD' \
  >> "$TMP/existpr"
: > "$TMP/drop"
bash "$SCRIPT" >"$TMP/outdead6" 2>&1
eq "$(grep -c '^polecat/feat-dead$' "$TMP/created")" "1" \
   "(DEAD6) the retry re-adopts the PR it already opened — never a second supersede"
grep -q '^bead-DEAD	602$' "$TMP/fliplog" \
  && ok "(DEAD6) the retry flips onto that same fresh PR#602" \
  || bad "(DEAD6) retry must flip onto PR#602 (got: $(cat "$TMP/fliplog"))"

# (DEAD7) AN OPERATOR'S CLOSE IS NOT A SUPERSEDE. The dead pull request was closed at
# EXACTLY the head this pass would open a new one at: nothing was re-implemented, so
# that close was a decision about this commit. Opening a replacement would re-litigate
# it — and would repeat every idle pass, since closing the replacement returns the
# branch to this same state. Hold instead.
dead_reset
cat > "$TMP/anchors" <<'A'
bead-SAME|polecat/feat-same|main|green@HEADSAME
A
cat > "$TMP/heads" <<'H'
polecat/feat-same|HEADSAME
H
cat > "$TMP/existpr" <<'E'
polecat/feat-same|606|https://github.com/acme/repo/pull/606|CLOSED|main|polecat/feat-same|acme/repo|HEADSAME
E
cat > "$TMP/newpr" <<'N'
polecat/feat-same|607|https://github.com/acme/repo/pull/607|OPEN|main|polecat/feat-same|acme/repo
N
bash "$SCRIPT" >"$TMP/outsame" 2>"$TMP/errsame"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(DEAD7) a PR closed at the reviewed head -> NO replacement is opened"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(DEAD7) ...and the anchor is not flipped onto the dead one either"
grep -q "closed at the SAME head" "$TMP/errsame" \
  && ok "(DEAD7) the hold names why: the branch was never re-implemented" \
  || bad "(DEAD7) must name the same-head close (err: $(cat "$TMP/errsame"))"

# (DEAD8) AN UNREADABLE DEAD HEAD IS A REFUSAL, not a default. A supersede and an
# operator's close differ only by that commit; without it neither action can be
# chosen, and the two have opposite consequences.
dead_reset
cat > "$TMP/anchors" <<'A'
bead-NOOID|polecat/feat-nooid|main|green@HEADNOOID
A
cat > "$TMP/heads" <<'H'
polecat/feat-nooid|HEADNOOID
H
cat > "$TMP/existpr" <<'E'
polecat/feat-nooid|608|https://github.com/acme/repo/pull/608|CLOSED|main|polecat/feat-nooid|acme/repo
E
cat > "$TMP/newpr" <<'N'
polecat/feat-nooid|609|https://github.com/acme/repo/pull/609|OPEN|main|polecat/feat-nooid|acme/repo
N
bash "$SCRIPT" >"$TMP/outnooid" 2>"$TMP/errnooid"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(DEAD8) an unreadable dead-PR head -> nothing opened"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(DEAD8) ...and nothing flipped"
grep -q "head commit is unreadable" "$TMP/errnooid" \
  && ok "(DEAD8) the refusal says which fact it is missing" \
  || bad "(DEAD8) must name the unreadable head (err: $(cat "$TMP/errnooid"))"

# (DEAD9) A STATE THIS SCRIPT DOES NOT MODEL is refused for the whole branch: `live`
# and `dead` have opposite actions (adopt it / open a second one past it), so an
# unclassifiable row is exactly what must not be fallen through on.
dead_reset
cat > "$TMP/anchors" <<'A'
bead-UNK|polecat/feat-unk|main|green@HEADUNK
A
cat > "$TMP/heads" <<'H'
polecat/feat-unk|HEADUNK
H
cat > "$TMP/existpr" <<'E'
polecat/feat-unk|610|https://github.com/acme/repo/pull/610|LOCKED|main|polecat/feat-unk|acme/repo|OLDUNK
E
cat > "$TMP/newpr" <<'N'
polecat/feat-unk|611|https://github.com/acme/repo/pull/611|OPEN|main|polecat/feat-unk|acme/repo
N
bash "$SCRIPT" >"$TMP/outunk" 2>"$TMP/errunk"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(DEAD9) an unmodelled PR state -> nothing opened"
eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
   "(DEAD9) ...and nothing flipped"
grep -q "not one of OPEN/CLOSED/MERGED" "$TMP/errunk" \
  && ok "(DEAD9) the refusal names the state it could not classify" \
  || bad "(DEAD9) must name the unmodelled state (err: $(cat "$TMP/errunk"))"

# (DEAD10) mergedAt PROMOTES, IT NEVER DEMOTES. GitHub's REST shape reports a landed
# pull request as state=closed + merged_at set; read as "CLOSED, so dead", this pass
# would open a duplicate for work that is already in. A closed row carrying a
# mergedAt is adopted as merged.
dead_reset
cat > "$TMP/anchors" <<'A'
bead-RESTMRG|polecat/feat-restmrg|main|green@HEADRESTMRG
A
cat > "$TMP/heads" <<'H'
polecat/feat-restmrg|HEADRESTMRG
H
cat > "$TMP/newpr" <<'N'
polecat/feat-restmrg|613|https://github.com/acme/repo/pull/613|OPEN|main|polecat/feat-restmrg|acme/repo
N
# CLOSED, and column 9 states the mergedAt outright — the REST shape.
cat > "$TMP/existpr" <<'E'
polecat/feat-restmrg|612|https://github.com/acme/repo/pull/612|CLOSED|main|polecat/feat-restmrg|acme/repo|OLDRESTMRG|2026-07-02T00:00:00Z
E
bash "$SCRIPT" >"$TMP/outrest" 2>"$TMP/errrest"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
   "(DEAD10) a closed row carrying mergedAt is LANDED work -> no duplicate opened"
grep -q '^bead-RESTMRG	612$' "$TMP/fliplog" \
  && ok "(DEAD10) ...and it is adopted so the merged-close observer can close the anchor" \
  || bad "(DEAD10) must flip onto the merged-by-mergedAt PR#612 (got: $(cat "$TMP/fliplog"))"

# (DEAD11) THE INTERSECTION with the operator holds (tk-3j0ob + tk-g0hd2). Replacing
# a dead pull request is an OPEN — a publish, not an adoption — so it is subject to
# merge_hold/rebase_hold like any other create. Landing these two fixes independently
# is exactly how that could have been missed: the hold gate was written when the only
# way past the existing-PR arm was "no PR at all", and the dead-PR fall-through adds a
# second way past it. Held, this branch must end the pass with nothing adopted AND
# nothing opened — not a fresh PR published under a hold the operator can see in place.
for HOLDKEY in merge rebase; do
  dead_reset
  if [ "$HOLDKEY" = "merge" ]; then
    printf 'bead-DEADHOLD|polecat/feat-deadhold|main|green@HEADDEADHOLD|true|\n' > "$TMP/anchors"
  else
    printf 'bead-DEADHOLD|polecat/feat-deadhold|main|green@HEADDEADHOLD||true\n' > "$TMP/anchors"
  fi
  cat > "$TMP/heads" <<'H'
polecat/feat-deadhold|HEADDEADHOLD
H
  # The only PR for the branch is closed-unmerged at an OLD head — the (DEAD1) shape,
  # which without a hold opens a fresh replacement.
  cat > "$TMP/existpr" <<'E'
polecat/feat-deadhold|620|https://github.com/acme/repo/pull/620|CLOSED|main|polecat/feat-deadhold|acme/repo|OLDDEADHOLD
E
  cat > "$TMP/newpr" <<'N'
polecat/feat-deadhold|621|https://github.com/acme/repo/pull/621|OPEN|main|polecat/feat-deadhold|acme/repo
N
  OUTDH="$(bash "$SCRIPT" 2>"$TMP/errdh")"
  eq "$(wc -l < "$TMP/created" | tr -d ' ')" "0" \
     "(DEAD11/${HOLDKEY}_hold) a held anchor gets NO replacement for its dead PR"
  eq "$(wc -l < "$TMP/fliplog" | tr -d ' ')" "0" \
     "(DEAD11/${HOLDKEY}_hold) ...and is not adopted onto the dead one either"
  printf '%s\n' "$OUTDH" | grep -q "${HOLDKEY}_hold set (operator gate)" \
    && ok "(DEAD11/${HOLDKEY}_hold) the operator gate is what reports the refusal" \
    || bad "(DEAD11/${HOLDKEY}_hold) must report the hold (got: $OUTDH / err: $(cat "$TMP/errdh"))"
  printf '%s\n' "$OUTDH" | grep -q "0 opened, 0 flipped, 1 held" \
    && ok "(DEAD11/${HOLDKEY}_hold) counted as held, not skipped" \
    || bad "(DEAD11/${HOLDKEY}_hold) summary (got: $OUTDH)"
done

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
