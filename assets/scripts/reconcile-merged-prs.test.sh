#!/usr/bin/env bash
# Hermetic test for reconcile-merged-prs.sh (close-on-land DETECT-ONLY observer).
#
# Stubs `gh` (PR state) and `gc` (bead-ledger list/close/update + mail) on PATH.
# No live city, Dolt, network, or real pull requests. The observer RECORDS merges
# it observes and ESCALATES discrepancies, but it has NO merge authority — the
# merge itself is the merge skill's job (merge-skill.sh, tested separately in
# merge-skill.test.sh). Covers the observer's dispositions + the no-merge
# invariant + convergence:
#   (1) PR merged              -> anchor CLOSED "Merged to <target> at <sha>"
#   (2) PR closed, unmerged    -> anchor flagged (merge_result=abandoned,
#                                 routed to human) + mayor escalated once
#   (3) PR open, ready          -> DETECT-ONLY: anchor left OPEN, the observer
#                                 never merges and never closes it
#   (4) PR open, draft          -> skipped (drafts retired; a stray draft is left alone)
#   (7) PR open, ready BUT live base != anchor target (retargeted after
#        publication) -> anchor flagged merge_result=retargeted + routed to
#        human + escalated once; never closed as landed
#   (8) PR merged BUT to a base != anchor target (retargeted) -> anchor NOT
#        closed as landed (would record a landing that never happened); flagged
#        retargeted + escalated once.
#   (9) PR open, CONFLICTING (stale base: the target was rewritten under it) ->
#        a rebase CHILD is filed against the anchor and routed to the fix pool,
#        the anchor STAYS gating (merge_result=pull_request untouched, so the
#        merge skill still lands it once the rebase clears), and the arm is
#        bounded to one rebase per head via stale_base_head.
#   (10) PR open, CONFLICTING but a rework/review child is already open for the
#        PR -> no second rebase child (it would race the one in flight).
#   (11) PR open, mergeable UNKNOWN (GitHub still computing) -> nothing: an
#        indeterminate reading must never be treated as a conflict.
#   (12) open PR whose bead is CLOSED (anchorless) -> reported + escalated ONCE,
#        bounded by an anchorless_flagged marker on the closed bead; never
#        merged, closed, or reopened (disposition is an operator call).
#   (13) open PR that a LIVE bead references (anchor or rework child) -> not a
#        finding; and the tracked-set match is exact, so PR#7 never satisfies
#        PR#77.
#   (14) open PR with NO bead in any state -> reported but NOT escalated (nothing
#        durable to bound a mail with, so it must not repeat every wake).
#   (15) zero gating anchors is NOT an early exit — the anchorless scan still
#        runs (zero anchors + open PRs is exactly the stranded state).
#   (INV) the observer NEVER runs `gh pr merge` for ANY anchor — no merge authority.
#   (5) convergence: closed / flagged / retargeted anchors leave the gating set,
#       so a second pass does not re-close, re-escalate, or re-flag them; the
#       stale-base anchor STAYS in the set (by design) and is held from re-filing
#       by its stale_base_head marker instead.
#   (24) PR open, ready, but check.codex=green@<stale> (the head MOVED past the
#        reviewed commit with no rework bead filed) -> a codex RE-REVIEW child is
#        filed at the LIVE head + routed to the review pool, the anchor STAYS
#        gating (merge_result untouched, never a hand-stamped green), bounded to
#        one re-review per head via stale_gate_head. (WS4 GAP1, su-PR#31 class.)
#   (25) check.codex green AT the live head -> not stale, no re-review.
#   (26) stale gate but a review/rework child already open for the PR -> no twin.
#   (27) stale_gate_head bounds it: unchanged head -> no re-fire; re-arms when the
#        head moves again.
#   (28) no --review-pool -> HELD: never hand-stamp check.codex green (would
#        certify an unreviewed commit); stamp a DISTINCT no-pool head guard
#        (stale_gate_nopool_head, NOT stale_gate_head) and leave gating.
#   (29) a no-pool hold RECOVERS: rerun the (28) head WITH --review-pool -> the
#        re-review is dispatched, not suppressed by the head guard. Regression for
#        tk-v2b0k finding #1 (no-pool marker must not block a later configured
#        dispatch at the same head).
#   (32)-(36) a bead can name its PR under keys other than pr_number (fork_pr,
#        fork_pr_url), and every PR-keyed lookup must read all of them:
#   (32) a fork_pr-keyed rework child already in flight is SEEN by the conflict
#        arm's probe -> no second rebase child (no force-push over it). The half
#        of the widening that is easy to skip and expensive to miss.
#   (33) a fork_pr / fork_pr_url-keyed LIVE bead makes its PR tracked -> no
#        false ANCHORLESS finding repeating every patrol wake (gc-qin3c/PR#100).
#   (34) tracked is NOT owned: a live bead with no merge_result / merge_strategy /
#        branch / target gets its own UNOWNED line, never escalated and never
#        folded into silence — widening alone would just trade a false finding
#        for false quiet.
#   (35) a fork-keyed bead that DOES carry gating metadata is owned -> silent.
#   (36) the CLOSED-bead resolution is widened the same way, so a fork_pr-keyed
#        closed anchor resolves and escalates instead of degrading into the
#        non-escalating "no bead in any state" branch.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/reconcile-merged-prs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source): id|pr_number|merged_target|merge_hold|rebase_hold
# The two hold columns are optional (older rows omit them and read as unset).
#   bead-A merged to main            -> closed (observed merge recorded)
#   bead-B closed unmerged           -> flagged abandoned + escalated
#   bead-C open, ready               -> left OPEN (the merge skill lands it, not us)
#   bead-D open, draft               -> skipped
#   bead-H open, ready, retargeted   -> flagged retargeted + escalated, never closed
#   bead-I merged to wrong base      -> NOT closed as landed; flagged retargeted
#   bead-J open, CONFLICTING         -> rebase child filed + routed; STAYS gating
#   bead-K open, CONFLICTING, child in flight -> no second rebase child
#   bead-L open, mergeable UNKNOWN   -> nothing (indeterminate is not a conflict)
#   bead-M open, ready (turns CONFLICTING in run 4, which passes no --fix-pool)
#   bead-N open, CONFLICTING, merge_hold=true          -> (16) HELD, no force-push
#   bead-O open, CONFLICTING, rebase_hold=true         -> (17) HELD, no force-push
#   bead-P open, CONFLICTING, BLOCKED child rebase_hold-> (18) HELD, no force-push
#   bead-Q open, CONFLICTING, blocked child same BRANCH-> (19) no second child
#   bead-R open, CONFLICTING, HOOKED child same BRANCH -> (21) no second child
#   bead-S open, CONFLICTING, PINNED child same BRANCH -> (22) no second child
cat > "$TMP/anchors" <<'A'
bead-A|201|main
bead-B|202|main
bead-C|203|main
bead-D|204|main
bead-H|208|main
bead-I|209|main
bead-J|210|main
bead-K|211|main
bead-L|212|main
bead-M|213|main
bead-N|214|main|true|
bead-O|215|main||true
bead-P|216|main||
bead-Q|217|main||
bead-R|218|main||
bead-S|219|main||
bead-Z|230|main||
A

# PR states (gh pr view source):
#   pr|state|mergedAt|isDraft|mergeOid|baseRefName|headRefName|headRefOid|mergeable|mergeStateStatus
#   201 merged to main            -> close anchor bead-A (mergedAt set = merge)
#   202 closed, unmerged          -> flag anchor bead-B + escalate
#   203 open, ready               -> observer leaves it (detect-only)
#   204 open, draft               -> skip
#   208 open, base=integration/foo != main -> retarget (flagged, never merged)
#   209 merged BUT to integration/foo != main -> retarget (NOT closed as landed)
#   210 open, CONFLICTING/DIRTY   -> stale base: rebase child routed to the pool
#   211 open, CONFLICTING/DIRTY, already has an open rework child -> no new child
#   212 open, UNKNOWN/UNKNOWN     -> still computing; must NOT read as a conflict
#   213 open, ready for now       -> rewritten to CONFLICTING before run 4
#   214 open, CONFLICTING/DIRTY, anchor merge_hold=true  -> held, NO rebase filed
#   215 open, CONFLICTING/DIRTY, anchor rebase_hold=true -> held, NO rebase filed
#   216 open, CONFLICTING/DIRTY, blocked child holds it  -> held, NO rebase filed
#   217 open, CONFLICTING/DIRTY, blocked child on branch -> skipped, NO 2nd child
#   218 open, CONFLICTING/DIRTY, HOOKED child on branch  -> skipped, NO 2nd child
#   219 open, CONFLICTING/DIRTY, PINNED child on branch  -> skipped, NO 2nd child
cat > "$TMP/prs" <<'P'
201|MERGED|2026-06-23T01:00:00Z|false|abc12345def67890|main|polecat/bead-A|head201|MERGEABLE|CLEAN
202|CLOSED||false||main|polecat/bead-B|head202|UNKNOWN|UNKNOWN
203|OPEN||false||main|polecat/bead-C|head203|MERGEABLE|BLOCKED
204|OPEN||true||main|polecat/bead-D|head204|MERGEABLE|BLOCKED
208|OPEN||false||integration/foo|polecat/bead-H|head208|MERGEABLE|BLOCKED
209|MERGED|2026-06-23T02:00:00Z|false|cafe1234abcd5678|integration/foo|polecat/bead-I|head209|MERGEABLE|CLEAN
210|OPEN||false||main|polecat/bead-J|head210|CONFLICTING|DIRTY
211|OPEN||false||main|polecat/bead-K|head211|CONFLICTING|DIRTY
212|OPEN||false||main|polecat/bead-L|head212|UNKNOWN|UNKNOWN
213|OPEN||false||main|polecat/bead-M|head213|MERGEABLE|BLOCKED
214|OPEN||false||main|polecat/bead-N|head214|CONFLICTING|DIRTY
215|OPEN||false||main|polecat/bead-O|head215|CONFLICTING|DIRTY
216|OPEN||false||main|polecat/bead-P|head216|CONFLICTING|DIRTY
217|OPEN||false||main|polecat/bead-Q|head217|CONFLICTING|DIRTY
218|OPEN||false||main|polecat/bead-R|head218|CONFLICTING|DIRTY
219|OPEN||false||main|polecat/bead-S|head219|CONFLICTING|DIRTY
230|OPEN||false||main|polecat/bead-Z|head230|CONFLICTING|DIRTY
P

# Open PRs as `gh pr list` sees them (the anchorless scan's PR -> BEAD side):
#   pr|isDraft|headRefName|baseRefName
#   203 tracked by live anchor bead-C            -> not a finding
#   211 tracked by live anchor bead-K + child-K  -> not a finding
#   301 bead closed (dead-1)                     -> flagged + escalated once
#   302 no bead in any state                     -> flagged, NOT escalated
#   303 draft, bead closed (dead-3)              -> flagged (draft) + escalated
#   304 bead closed, marker ALREADY set          -> flagged, not re-escalated
#   77  no bead, but a live bead references PR#7 -> flagged (exact match, not
#                                                   swallowed by the "7" prefix)
#   401 live bead keyed ONLY by fork_pr, no gating metadata     -> UNOWNED
#   402 live bead keyed ONLY by fork_pr_url, no gating metadata -> UNOWNED
#   403 live bead keyed ONLY by fork_pr, WITH merge_result      -> silent (owned)
#   404 live bead keyed by pr_number, no gating metadata        -> UNOWNED
#   405 closed anchor keyed ONLY by fork_pr, open PR            -> ANCHORLESS
#   406 a FOREIGN live bead names #406 + our own closed anchor  -> ANCHORLESS
#       (the foreign bead must not track it into silence)
#   407 only a FOREIGN closed bead names #407                   -> ANCHORLESS,
#       NOT escalated and the foreign bead NOT flagged
cat > "$TMP/openprs" <<'O'
203|false|polecat/bead-C|main
211|false|polecat/bead-K|main
301|false|polecat/dead-1|main
302|false|somebody/manual-pr|main
303|true|polecat/dead-3|main
304|false|polecat/dead-4|main
77|false|polecat/dead-x|main
401|false|fork/sync-401|main
402|false|fork/sync-402|main
403|false|fork/sync-403|main
404|false|polecat/plain-404|main
405|false|fork/sync-405|main
406|false|polecat/dead-406|main
407|false|somebody/manual-407|main
O

# Live beads outside the refinery's own flow — the fixtures for the widened key
# set and the tracked-vs-OWNED split. Transcribed from the real shape: gascity
# gc-qin3c names PR#100 as fork_pr/fork_pr_url with NO pr_number, no
# merge_result, no branch, no target, no merge_strategy, assignee=operator.
# Keyed on pr_number alone every one of these PRs reported ANCHORLESS forever;
# widened but collapsed into "tracked", the ungated ones would go SILENT — which
# is quieter without being truer, since nothing will land them either way.
#   key<TAB>pr<TAB>id<TAB>assignee<TAB>gating<TAB>pr_url
#
# The 6th column is the bead's OWN pr_url, and it is what makes the tracked set an
# identity question rather than a number match. Omitted on the fork/plain rows ON
# PURPOSE — a bead that records no URL cannot be placed in any repository, stays the
# `?` wildcard, and tracks its PR exactly as it always did. live-foreign-406 records
# a URL on ANOTHER HOST: it is a real, live bead, but it names a DIFFERENT pull
# request, so it must not track our open #406 into silence (review tk-thvbq #2).
printf '%s\n' \
  'fork_pr	401	live-fork	operator	-	-' \
  'fork_pr_url	402	live-forkurl	operator	-	-' \
  'fork_pr	403	live-forkgated	refinery	yes	-' \
  'pr_number	404	live-plain	operator	-	-' \
  'pr_number	406	live-foreign-406	operator	-	https://otherhost/acme/repo/pull/406' \
  > "$TMP/livex"

# Closed beads that still name a PR (the anchorless arm's bead resolution):
#   pr<TAB>bead-id<TAB>anchorless_flagged-marker<TAB>merge_result<TAB>created_at
# "-" means empty. It has to be a placeholder rather than an empty field: TAB is
# IFS *whitespace*, so bash collapses a run of them and an empty middle column
# would silently shift every field after it.
# PR#301 models the real shape: THREE closed beads name it — a review bead, a
# later "address findings" rework child, and the anchor that actually opened the
# PR. Both the rework child and the anchor carry merge_result, and the anchor is
# listed LAST, so only "oldest bead carrying merge_result" resolves it correctly.
# dead-4 is pre-flagged, so it must be reported but NOT re-escalated.
#
# The 6th column is the metadata key the closed bead names its PR with (default
# pr_number). dead-5 names PR#405 only as fork_pr: keyed on pr_number alone the
# resolution finds nothing, the arm falls into the "no bead in any state" branch
# — which by design does NOT escalate — and a genuinely stranded PR is downgraded
# to a log line forever.
#
# The 7th column is the closed bead's OWN pr_url ("-" = none, the common shape).
# dead-foreign-407 records another HOST's URL: keyed on the bare number it resolves
# as the dead anchor of OUR #407 and receives the anchorless_flagged stamp plus a
# mail naming it — a write onto a stranger's bead, which also bounds the escalation
# for a PR it never owned (review tk-thvbq finding #2).
printf '%s\n' \
  '301	review-1	-	-	2026-01-02T00:00:00Z	-	-' \
  '301	rework-1	-	pull_request	2026-01-03T00:00:00Z	-	-' \
  '301	dead-1	-	pull_request	2026-01-01T00:00:00Z	-	-' \
  '303	dead-3	-	pull_request	2026-01-01T00:00:00Z	-	-' \
  '304	dead-4	304	pull_request	2026-01-01T00:00:00Z	-	-' \
  '405	dead-5	-	pull_request	2026-01-01T00:00:00Z	fork_pr	-' \
  '406	dead-406	-	pull_request	2026-01-01T00:00:00Z	-	-' \
  '407	dead-foreign-407	-	pull_request	2026-01-01T00:00:00Z	-	https://otherhost/acme/repo/pull/407' \
  > "$TMP/dead"

: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/retargeted"; : > "$TMP/mailbody"
: > "$TMP/automerge"; : > "$TMP/mail"; : > "$TMP/closelog"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/staled"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"

# Rework/review children referencing a PR (the merge skill's in-flight set; the
# conflict arm reuses that query so it never races a rework already in flight).
#   pr<TAB>child-id<TAB>branch<TAB>status<TAB>rebase_hold
# The last three columns are optional; a missing status reads as `open` (the
# shape the older rows were written in). The arm appends its own children here as
# it files them, exactly as the real ledger would.
#   child-K   PR#211, open                 -> case (10): no second child
#   child-tiny PR#7                         -> puts "7" in the tracked set, the
#                                              fixture for case (13)'s exact-match
#                                              guard against open PR#77
#   child-P   PR#216, BLOCKED, rebase_hold -> case (18): the observed shape — a
#                                              keeper neutralised a runaway rebase
#                                              child by blocking it and setting
#                                              rebase_hold. It is invisible to a
#                                              status=open,in_progress probe.
#   child-Q   PR#999, BLOCKED, but names branch polecat/bead-Q -> case (19): the
#                                              branch dimension. Keyed by PR alone
#                                              it is missed; a force-push would
#                                              race it on the shared branch.
#   child-R   PR#998, HOOKED, names branch polecat/bead-R -> case (21): `hooked`
#                                              is a built-in wip status ("attached
#                                              to an agent's hook") — a child in it
#                                              is being worked RIGHT NOW, the most
#                                              dangerous moment to force-push under.
#   child-S   PR#997, PINNED, names branch polecat/bead-S -> case (22): the other
#                                              non-closed status the probe used to
#                                              omit. No rebase_hold on either: the
#                                              STATUS LIST alone must make them
#                                              visible, with no operator marker to
#                                              fall back on.
#   child-Z   PR#230, open, names it as fork_pr (6th column) and carries NO
#                                              branch -> case (32): the PR
#                                              dimension is the ONLY thing that
#                                              can see it. Keyed on pr_number
#                                              alone the probe misses it and the
#                                              arm force-pushes over a rework
#                                              already in flight.
printf '%s\n' \
  '211	child-K' \
  '7	child-tiny' \
  '216	child-P	polecat/bead-P	blocked	true' \
  '999	child-Q	polecat/bead-Q	blocked	-' \
  '998	child-R	polecat/bead-R	hooked	-' \
  '997	child-S	polecat/bead-S	pinned	-' \
  '230	child-Z	-	open	-	fork_pr' \
  > "$TMP/children"

FIX_POOL="test-rig/gc-toolkit.polecat"

# --- gh stub: pr view (emit state JSON), pr merge (record any merge attempt). --
# The `pr view` arm VALIDATES the requested `--json` fields against the set a
# supported gh actually exposes for a PR, and errors (exit 1, like real gh) on
# any unknown field. This is the regression guard for the field-shape bug:
# `merged` is NOT a pr-view field (`mergedAt` is), so a buggy
# `--json ...merged...` empties PR_JSON and the disposition matrix below fails —
# exactly the real-world failure where close-on-land silently closes nothing.
#
# The `pr merge` arm records to $FAKE_AUTOMERGE. The observer must NEVER reach it
# (it has no merge authority): the INV assertion below proves that file stays
# empty across the whole run. The merge skill's own test exercises real merges.
#
# BOTH READS FOLLOW gh's CURRENT REPOSITORY UNLESS `--repo` PINS THEM. $FAKE_GH_DEFAULT
# moves that default exactly as `gh repo set-default`, GH_REPO or a different cwd
# would; `acme/repo` when unset. $FAKE_IGNORE_REPO models a gh that ignores the pin
# entirely (a redirect after a repository transfer or rename, an older gh, a
# wrapper), so the returned URL is the only thing left to catch it. $FAKE_GH_HOST
# models GH_HOST, which fills the host of a HOSTLESS `--repo` pin.
#
# Every emitted `url` names the repository the call ACTUALLY resolved in, not a
# hardcoded one — that is what makes the identity cases below meaningful, and it is
# byte-identical to the old fixed string whenever the pin is honoured (the default),
# so every pre-existing case is unaffected.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
ghdefault=$(cat "${FAKE_GH_DEFAULT:-/dev/null}" 2>/dev/null)
[ -n "$ghdefault" ] || ghdefault="acme/repo"
RESOLVED=""
for a in "$@"; do
  case "${prev:-}" in --repo|-R) RESOLVED="$a" ;; esac
  prev="$a"
done
[ -s "${FAKE_IGNORE_REPO:-/dev/null}" ] && RESOLVED=""
[ -n "$RESOLVED" ] || RESOLVED="$ghdefault"
# `--repo` is `[HOST/]OWNER/REPO`; with the host OMITTED gh supplies it from GH_HOST
# (`gh help environment`). So `<owner>/<repo>` does not name a repository, it names
# one PER HOST: a hostless pin under a drifted GH_HOST reads THAT host's acme/repo —
# same owner, same repo, same number, different pull request. Only a host-qualified
# pin closes it, which is why the resolved name below keeps its host.
case "$RESOLVED" in
  */*/*) : ;;
  *)     ghhost=$(cat "${FAKE_GH_HOST:-/dev/null}" 2>/dev/null)
         [ -n "$ghhost" ] || ghhost="github.com"
         RESOLVED="$ghhost/$RESOLVED" ;;
esac
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    # Supported `gh pr view --json` fields (subset; notably NOT `merged`).
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid headRepository headRepositoryOwner isCrossRepository url title body author additions deletions mergeable mergeStateStatus "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    # Columns 11-12 are the HEAD identity: which repository the PR is opened FROM,
    # and GitHub's own cross-repository flag. Both are OMITTED on every pre-existing
    # row and default to THIS repository / not-cross — the shape those cases were
    # written against — so only the head-identity cases below vary them. A headrepo
    # of `-` emits NULL objects, which is what gh returns for a deleted head repo (an
    # omitted column cannot mean that: it has to keep meaning "ours").
    while IFS='|' read -r pr state mergedat isdraft oid base head headoid mergeable mergestate headrepo cross; do
      [ "$pr" = "$num" ] || continue
      [ -n "$headrepo" ] || headrepo="acme/repo"
      [ -n "$cross" ]    || cross="false"
      jq -n --arg s "$state" --arg ma "$mergedat" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" --arg h "$head" --arg ho "$headoid" \
            --arg m "$mergeable" --arg ms "$mergestate" --arg n "$num" \
            --arg rq "$RESOLVED" --arg hrepo "$headrepo" --argjson x "$cross" \
        '{state:$s, mergedAt:(if $ma=="" then null else $ma end), isDraft:$d,
          mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b,
          headRefName:$h, headRefOid:$ho, mergeable:$m, mergeStateStatus:$ms,
          headRepositoryOwner:(if $hrepo=="-" then null else {login:($hrepo | split("/")[0])} end),
          headRepository:(if $hrepo=="-" then null else {name:($hrepo | split("/")[1])} end),
          isCrossRepository:$x,
          url:("https://" + $rq + "/pull/" + $n)}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr list")
    # Open PRs, for the anchorless (PR -> BEAD) scan.
    out=""
    while IFS='|' read -r pr isdraft head base; do
      [ -n "$pr" ] || continue
      obj=$(jq -n --arg n "$pr" --argjson d "$isdraft" --arg h "$head" --arg b "$base" \
        --arg rq "$RESOLVED" \
        '{number:($n|tonumber), url:("https://" + $rq + "/pull/" + $n),
          isDraft:$d, headRefName:$h, baseRefName:$b}')
      if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
    done < "$FAKE_OPENPRS"
    printf '[%s]\n' "$out"
    exit 0 ;;
  "pr merge")
    printf '%s\n' "$3" >> "$FAKE_AUTOMERGE" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- git stub. ----------------------------------------------------------------
# `git remote get-url origin` -> what this checkout pushes to, and the ONLY source
# of the repository every `gh pr view` / `gh pr list` below is pinned to. Never
# `gh`: gh's current repository is movable, and a bare PR NUMBER read in the wrong
# one lets this pass close a live anchor against a stranger's merge (review
# tk-sdqwh finding #2). $FAKE_REPOFAIL makes it unanswerable, as a checkout with
# no origin remote would.
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_REPOFAIL" ] && exit 1
  printf 'https://github.com/acme/repo.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gc stub: bd list / create / close / update / dep + session + mail. -------
# bd list reflects state: a closed, flagged (abandoned), or retargeted anchor
# leaves the gating set, which is what makes the convergence assertion
# meaningful. A stale-base anchor deliberately does NOT leave it (the merge skill
# must keep watching the PR), so the gating rows carry the stale_base_head marker
# the conflict arm stamps — that marker, not the scan, is what bounds it.
# Two list shapes are modeled: the gating-anchor scan
# (`--metadata-field merge_result=pull_request`) and the conflict arm's
# in-flight-rework probe (`--metadata-field pr_number=<n>`).
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
if [ "$1" = "mail" ]; then
  shift; subj=""; body=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -s) subj="$2"; shift 2 ;;
      -m) body="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  printf '%s\n' "$subj" >> "$FAKE_MAIL"
  printf '%s\n' "$body" >> "$FAKE_MAILBODY"
  exit 0
fi
if [ "$1" = "session" ]; then
  [ "${2:-}" = "wake" ] && printf '%s\n' "${3:-}" >> "$FAKE_WAKES"
  exit 0
fi
[ "$1" = "bd" ] || exit 0
case "$2" in
  list)
    case "$*" in
      *"--status closed"*)
        # CLOSED bead that still names a PR — the anchorless arm's resolution of
        # "who used to own this PR". Must be matched BEFORE the generic
        # pr_number= arm below, which would otherwise swallow it and return the
        # live children instead.
        #
        # The arm is keyed the same THREE ways the script asks (pr_number=,
        # fork_pr=, --has-metadata-key fork_pr_url), because it now issues one
        # read per key and unions them. A closed bead's key lives in $FAKE_DEAD's
        # 6th column (default pr_number), so a closed anchor keyed only by
        # fork_pr resolves exactly as the real ledger would.
        qkey="pr_number"; num=""
        for a in "$@"; do
          case "$a" in
            pr_number=*) qkey="pr_number"; num="${a#pr_number=}" ;;
            fork_pr=*)   qkey="fork_pr";   num="${a#fork_pr=}" ;;
            fork_pr_url) qkey="fork_pr_url" ;;
          esac
        done
        out=""
        while IFS="$(printf '\t')" read -r pr bid flagged mres created dkey dprurl; do
          [ -n "$bid" ] || continue
          [ -n "$dkey" ] && [ "$dkey" != "-" ] || dkey="pr_number"
          [ "$dkey" = "$qkey" ] || continue
          # The URL arm asks for every bead HOLDING the key, not a value match —
          # the script parses the number out of the URL itself.
          [ "$qkey" = "fork_pr_url" ] || [ "$pr" = "$num" ] || continue
          [ "$flagged" = "-" ] && flagged=""
          [ "$mres" = "-" ] && mres=""
          [ "$dprurl" = "-" ] && dprurl=""
          case "$dkey" in
            fork_pr_url) keyjson=$(printf '"fork_pr_url":"https://github.com/acme/repo/pull/%s"' "$pr") ;;
            *)           keyjson=$(printf '"%s":"%s"' "$dkey" "$pr") ;;
          esac
          obj=$(printf '{"id":"%s","created_at":"%s","metadata":{%s,"pr_url":"%s","anchorless_flagged":"%s","merge_result":"%s"}}' \
                  "$bid" "$created" "$keyjson" "$dprurl" "$flagged" "$mres")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_DEAD"
        printf '[%s]\n' "$out" ;;
      *"--metadata-field branch="*|*"--metadata-field pr_number="*|*"--metadata-field fork_pr="*|*"--has-metadata-key fork_pr_url"*)
        # The conflict arm's pre-dispatch probe, keyed on pr_number OR branch.
        # Returns anchors AND rework children (the real ledger does not
        # distinguish them — merge_result does, and the arm filters on it), and
        # honors the requested --status list: a bead whose status the caller did
        # not ask for is INVISIBLE, exactly as in the ledger. That is what makes
        # the status list load-bearing — narrow the probe back to
        # open,in_progress and the blocked children below vanish, which is the
        # bug this guards (tk-gajop).
        # FAKE_PROBE_FAIL models a failed ledger read: empty output, NOT "[]",
        # exactly as a broken `gc bd list` behaves. The arm must fail CLOSED.
        [ -n "${FAKE_PROBE_FAIL:-}" ] && exit 0
        # FAKE_PROBE_SHAPE models the failure family an emptiness test cannot see:
        # a read that FAILED but still put something on stdout. Each shape defeats
        # a different guard, so each is asserted separately below — a guard no test
        # pins is a guard a later edit can delete silently, which is how the
        # `hooked` gap got in.
        #   error-rc1 — the observed shape, transcribed from the real thing
        #               (`gc bd list --metadata-field malformed --status open
        #               --json`): a JSON error OBJECT plus exit 1.
        #   error-rc0 — the same object arriving with a ZERO exit. Isolates the
        #               payload-shape guard: the exit-status guard cannot see this.
        #   array-rc1 — a well-formed, EMPTY array with a non-zero exit (the read
        #               died after emitting). Isolates the exit-status guard: the
        #               payload-shape guard cannot see this, and "[]" is precisely
        #               the value that legitimately means "nobody holds it".
        #   bad-array — an array of non-objects: passes the shape guard, then blows
        #               up the projection. Isolates the jq-status guard.
        #   object-map— the nastiest shape, and the only one the projection cannot
        #               catch: an OBJECT whose values are bead-shaped, e.g. a
        #               `--json` envelope keyed by id rather than a list. `.[]`
        #               happily iterates an object's values, so the projection
        #               SUCCEEDS and emits a well-formed row; only "is the payload
        #               an array?" rejects it. The row is a foreign ANCHOR
        #               (merge_result set, no rebase_hold) precisely so it passes
        #               both the frozen and in-flight filters — i.e. so the arm
        #               would DISPATCH on it, and the test cannot pass by accident.
        case "${FAKE_PROBE_SHAPE:-}" in
          error-rc1)  printf '{\n  "error": "invalid --metadata-field: expected key=value, got \\"malformed\\"",\n  "schema_version": 1\n}\n'; exit 1 ;;
          error-rc0)  printf '{\n  "error": "invalid --metadata-field: expected key=value, got \\"malformed\\"",\n  "schema_version": 1\n}\n'; exit 0 ;;
          array-rc1)  printf '[]\n'; exit 1 ;;
          bad-array)  printf '[1, 2]\n'; exit 0 ;;
          object-map) printf '{"other-anchor": {"id": "other-anchor", "metadata": {"merge_result": "pull_request"}}}\n'; exit 0 ;;
        esac
        # The PR dimension is asked THREE ways now (one read per key that can name
        # a PR), so the stub keys on each of them. The URL arm is a
        # --has-metadata-key query with no value to match — it returns every bead
        # HOLDING fork_pr_url and the script parses the number out itself, which is
        # exactly why it cannot be an exact --metadata-field filter.
        key=""; val=""; sts=""; prev=""
        for a in "$@"; do
          case "$a" in
            pr_number=*)  key="pr_number";   val="${a#pr_number=}" ;;
            fork_pr=*)    key="fork_pr";     val="${a#fork_pr=}" ;;
            fork_pr_url)  key="fork_pr_url" ;;
            branch=*)     key="branch";      val="${a#branch=}" ;;
          esac
          [ "$prev" = "--status" ] && sts="$a"
          prev="$a"
        done
        visible() { printf '%s' ",$sts," | grep -q ",$1,"; }
        # A bead's PR key -> the metadata object that names it. fork_pr_url holds a
        # URL, so the number only reaches the script through the parse.
        keyjson_for() {
          case "$1" in
            fork_pr_url) printf '"fork_pr_url":"https://github.com/acme/repo/pull/%s"' "$2" ;;
            *)           printf '"%s":"%s"' "$1" "$2" ;;
          esac
        }
        out=""
        while IFS='|' read -r id pr target mhold rhold cset cmark; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          case "$key" in
            pr_number) [ "$pr" = "$val" ] || continue ;;
            branch)    [ "polecat/$id" = "$val" ] || continue ;;
            *)         continue ;;   # gating anchors are always pr_number-keyed
          esac
          visible open || continue
          # Anchors carry merge_result — that is what marks them as NOT a rework
          # child, and the arm must exclude them on it (plus its own id).
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","branch":"polecat/%s","merge_result":"pull_request","rebase_hold":"%s"}}' \
                  "$id" "$pr" "$id" "$rhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        while IFS="$(printf '\t')" read -r pr cid cbranch cstatus crhold ckey; do
          [ -n "$cid" ] || continue
          [ -n "$cstatus" ] && [ "$cstatus" != "-" ] || cstatus="open"
          [ "$cbranch" = "-" ] && cbranch=""
          [ "$crhold" = "-" ] && crhold=""
          # 6th column: which key this child names its PR with (default pr_number).
          [ -n "$ckey" ] && [ "$ckey" != "-" ] || ckey="pr_number"
          case "$key" in
            pr_number|fork_pr) [ "$ckey" = "$key" ] && [ "$pr" = "$val" ] || continue ;;
            fork_pr_url)       [ "$ckey" = "fork_pr_url" ] || continue ;;
            branch)            [ -n "$cbranch" ] && [ "$cbranch" = "$val" ] || continue ;;
            *)                 continue ;;
          esac
          visible "$cstatus" || continue
          obj=$(printf '{"id":"%s","metadata":{%s,"branch":"%s","rebase_hold":"%s"}}' \
                  "$cid" "$(keyjson_for "$ckey" "$pr")" "$cbranch" "$crhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_CHILDREN"
        printf '[%s]\n' "$out" ;;
      *"merge_result=pull_request"*)
        out=""
        # The 8th column is the anchor's RECORDED pr_url (the identity
        # check-set-heal.sh certifies and persists). Empty for almost every
        # fixture — a pr_number-only anchor is the common shape, and is governed
        # by the pinned read plus the repository comparison alone.
        while IFS='|' read -r id pr target mhold rhold cset cmark prurl; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          staled=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_STALED" 2>/dev/null | tail -1)
          gatehead=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_GATEHEAD" 2>/dev/null | tail -1)
          gatenopool=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_GATENOPOOL" 2>/dev/null | tail -1)
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","pr_url":"%s","merged_target":"%s","branch":"polecat/%s","stale_base_head":"%s","stale_gate_head":"%s","stale_gate_nopool_head":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s","rebase_hold":"%s"}}' \
                  "$id" "$pr" "$prurl" "$target" "$id" "$staled" "$gatehead" "$gatenopool" "$cset" "$cmark" "$mhold" "$rhold")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        printf '[%s]\n' "$out" ;;
      *"open,in_progress,blocked"*)
        # Every LIVE bead that names a PR: gating anchors still in the set, plus
        # open rework/review children. This is the tracked set the anchorless
        # scan subtracts from `gh pr list`. Matched AFTER the probe arms above:
        # the probe's own --status list is a superset of this string, so ordering
        # is what keeps a keyed probe from falling into this unkeyed scan.
        # FAKE_LIVE_FAIL models a failed ledger read (empty output, NOT "[]") so
        # the fail-closed guard can be exercised.
        [ -n "${FAKE_LIVE_FAIL:-}" ] && exit 0
        # ...and FAKE_LIVE_SHAPE models the failures an EMPTINESS test cannot see —
        # the same family the keyed probes already pin, on the live-bead read that
        # decides which PRs are tracked. Each defeats a different guard:
        #   error-rc1 — a JSON error OBJECT plus exit 1 (the observed shape).
        #   error-rc0 — the same object with a ZERO exit; only the payload-shape
        #               guard sees it. Note `.[]` iterates an object's values
        #               happily, so an unguarded read builds a TRACKED set out of
        #               error text and silences real findings.
        #   array-rc1 — a well-formed EMPTY array with a non-zero exit; only the
        #               exit-status guard sees it, and "[]" is exactly the value
        #               that legitimately means "no live bead names anything".
        case "${FAKE_LIVE_SHAPE:-}" in
          error-rc1) printf '{"error":"ledger unavailable","schema_version":1}\n'; exit 1 ;;
          error-rc0) printf '{"error":"ledger unavailable","schema_version":1}\n'; exit 0 ;;
          array-rc1) printf '[]\n'; exit 1 ;;
        esac
        # Beads are emitted with the metadata that decides OWNERSHIP, not just the
        # PR key: gating anchors are in this set BECAUSE they carry
        # merge_result=pull_request, and rework children carry branch/target. That
        # is what separates "a live bead names this PR" (tracked) from "something
        # will actually land it" (owned) — the distinction the UNOWNED arm reads.
        keyjson_for() {
          case "$1" in
            fork_pr_url) printf '"fork_pr_url":"https://github.com/acme/repo/pull/%s"' "$2" ;;
            *)           printf '"%s":"%s"' "$1" "$2" ;;
          esac
        }
        out=""
        while IFS='|' read -r id pr target mhold rhold cset cmark; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","assignee":"refinery","metadata":{"pr_number":"%s","merge_result":"pull_request","branch":"polecat/%s"}}' \
                  "$id" "$pr" "$id")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        while IFS="$(printf '\t')" read -r pr cid cbranch cstatus crhold ckey; do
          [ -n "$cid" ] || continue
          [ -n "$cbranch" ] && [ "$cbranch" != "-" ] || cbranch="polecat/$cid"
          [ -n "$ckey" ] && [ "$ckey" != "-" ] || ckey="pr_number"
          obj=$(printf '{"id":"%s","assignee":"","metadata":{%s,"branch":"%s","target":"main"}}' \
                  "$cid" "$(keyjson_for "$ckey" "$pr")" "$cbranch")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_CHILDREN"
        # Live beads that name a PR but are NOT part of the refinery's own flow:
        # non-canonical keying and/or no gating metadata at all. Modeled only in
        # this (PR -> BEAD) direction, which is the one they change.
        #   key<TAB>pr<TAB>id<TAB>assignee<TAB>gating("yes" = carries merge_result)
        while IFS="$(printf '\t')" read -r lkey lval lid lassignee lgating lprurl; do
          [ -n "$lid" ] || continue
          [ "$lassignee" = "-" ] && lassignee=""
          gjson=""
          [ "$lgating" = "yes" ] && gjson=',"merge_result":"pull_request"'
          ujson=""
          [ -n "$lprurl" ] && [ "$lprurl" != "-" ] && ujson=$(printf ',"pr_url":"%s"' "$lprurl")
          obj=$(printf '{"id":"%s","assignee":"%s","metadata":{%s%s%s}}' \
                  "$lid" "$lassignee" "$(keyjson_for "$lkey" "$lval")" "$gjson" "$ujson")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "${FAKE_LIVEX:-/dev/null}"
        printf '[%s]\n' "$out" ;;
      *) printf '[]\n' ;;
    esac ;;
  create)
    # Mint a deterministic child id and echo it in `--json` shape.
    n=$(( $(wc -l < "$FAKE_CREATED") + 1 ))
    cid="fix-$n"
    printf '%s\t%s\n' "$cid" "$3" >> "$FAKE_CREATED"
    # Capture the dispatched BODY (tk-jufvl). The stale-gate re-review carries the
    # review METHOD on stdin via --body-file -; recording it per-bead is what lets
    # the assertions prove the re-review names a method instead of a bare title.
    if printf '%s' "$*" | grep -q -- '--body-file -'; then
      cat > "$FAKE_BODIES/$cid" 2>/dev/null || true
    fi
    printf '{"id":"%s"}\n' "$cid" ;;
  close)
    id="$3"; shift 3
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac; done
    printf '%s\n' "$id" >> "$FAKE_CLOSED"
    printf '%s\t%s\n' "$id" "$reason" >> "$FAKE_CLOSELOG" ;;
  update)
    id="$3"
    # Inject a transient route-write loss: while FAKE_ROUTE_FAIL is set, a write that
    # routes to that pool (gc.routed_to=<pool>) does NOT persist — nothing is appended
    # to the log — and the command reports failure. Models the ledger dropping the
    # stale-gate route step so the verify-before-arm path (arm_stale_gate) and the
    # next-pass in-flight repair can be exercised. Scoped to the one run that sets it.
    if [ -n "${FAKE_ROUTE_FAIL:-}" ] && printf '%s' "$*" | grep -q "gc.routed_to=$FAKE_ROUTE_FAIL"; then
      exit 1
    fi
    printf '%s\t%s\n' "$id" "$*" >> "$FAKE_UPDATES"
    case "$*" in
      *merge_result=abandoned*)  printf '%s\n' "$id" >> "$FAKE_ABANDONED" ;;
      *merge_result=retargeted*) printf '%s\n' "$id" >> "$FAKE_RETARGETED" ;;
    esac
    # Mirror the metadata writes the ledger would make visible to later passes:
    # the anchor's stale_base_head marker, and a child joining the in-flight set
    # once it carries pr_number. The child's BRANCH is recorded alongside, since
    # the conflict arm probes that dimension too — a child written without one
    # would be invisible to the branch probe on the next pass.
    child_pr=""; child_branch=""
    for a in "$@"; do
      case "$a" in
        stale_base_head=*) printf '%s\t%s\n' "$id" "${a#stale_base_head=}" >> "$FAKE_STALED" ;;
        stale_gate_nopool_head=*) printf '%s\t%s\n' "$id" "${a#stale_gate_nopool_head=}" >> "$FAKE_GATENOPOOL" ;;
        stale_gate_head=*) printf '%s\t%s\n' "$id" "${a#stale_gate_head=}" >> "$FAKE_GATEHEAD" ;;
        pr_number=*)       child_pr="${a#pr_number=}" ;;
        branch=*)          child_branch="${a#branch=}" ;;
        anchorless_flagged=*)
          # Mirror the escalation bound onto the closed bead, so a later pass
          # sees it and does not re-escalate.
          awk -F'\t' -v i="$id" -v v="${a#anchorless_flagged=}" \
              'BEGIN{OFS="\t"} $2==i{$3=v} {print}' "$FAKE_DEAD" > "$FAKE_DEAD.n" \
            && mv "$FAKE_DEAD.n" "$FAKE_DEAD" ;;
      esac
    done
    # "-" placeholders, never empty fields: TAB is IFS whitespace, so bash
    # collapses a run of them and an empty column would shift every field after
    # it (same convention as $FAKE_DEAD).
    if [ -n "$child_pr" ]; then
      [ -n "$child_branch" ] || child_branch="-"
      printf '%s\t%s\t%s\topen\t-\n' "$child_pr" "$id" "$child_branch" >> "$FAKE_CHILDREN"
    fi ;;
  dep)
    printf '%s\n' "$*" >> "$FAKE_DEPS" ;;
  show)
    # Reconstruct the metadata a later read would see, from the update log. The
    # fields the scripts read back: anchor_bead (the stale-gate / check-set-heal
    # "did the link persist before routing?" verification), plus task_kind and
    # gc.routed_to (the stale-gate REPAIR probe — "is this stranded in-flight bead an
    # unrouted codex review for this anchor?"). Modeled by replaying the LAST value
    # each field was updated with. A write the shim dropped (FAKE_ROUTE_FAIL) never
    # lands in the log, so its read-back is empty here — exactly what a transient
    # ledger loss looks like to arm_stale_gate's verify.
    sid="$3"
    slog=$(awk -F'\t' -v i="$sid" '$1==i{print $2}' "$FAKE_UPDATES" 2>/dev/null)
    ab=$(printf '%s\n' "$slog" | grep -o 'anchor_bead=[^ ]*' | tail -1 | sed 's/anchor_bead=//')
    tk=$(printf '%s\n' "$slog" | grep -o 'task_kind=[^ ]*' | tail -1 | sed 's/task_kind=//')
    rt=$(printf '%s\n' "$slog" | grep -o 'gc.routed_to=[^ ]*' | tail -1 | sed 's/gc.routed_to=//')
    printf '[{"id":"%s","metadata":{"anchor_bead":"%s","task_kind":"%s","gc.routed_to":"%s"}}]\n' \
      "$sid" "$ab" "$tk" "$rt" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" \
       FAKE_CLOSED="$TMP/closed" FAKE_ABANDONED="$TMP/abandoned" \
       FAKE_RETARGETED="$TMP/retargeted" \
       FAKE_AUTOMERGE="$TMP/automerge" FAKE_MAIL="$TMP/mail" FAKE_CLOSELOG="$TMP/closelog" \
       FAKE_CREATED="$TMP/created" FAKE_UPDATES="$TMP/updates" FAKE_DEPS="$TMP/deps" \
       FAKE_WAKES="$TMP/wakes" FAKE_STALED="$TMP/staled" FAKE_CHILDREN="$TMP/children" \
       FAKE_GATEHEAD="$TMP/gatehead" FAKE_GATENOPOOL="$TMP/gatenopool" \
       FAKE_OPENPRS="$TMP/openprs" FAKE_DEAD="$TMP/dead" FAKE_MAILBODY="$TMP/mailbody" \
       FAKE_LIVEX="$TMP/livex" FAKE_BODIES="$TMP/bodies" \
       FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_GH_DEFAULT="$TMP/ghdefault" FAKE_IGNORE_REPO="$TMP/ignorerepo" \
       FAKE_GH_HOST="$TMP/ghhost"
mkdir -p "$TMP/bodies"
: > "$TMP/repofail"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/ghhost"

# --- Run 1: the disposition matrix. ------------------------------------------
OUT1="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"

has '^bead-A$' "$TMP/closed" && ok "(1) merged PR -> anchor closed" \
                             || bad "(1) merged PR -> anchor closed"
grep -q 'Merged to main at abc12345' "$TMP/closelog" \
  && ok "(1) close reason names target + short merge sha" \
  || bad "(1) close reason names target + short merge sha (got: $(cat "$TMP/closelog"))"
has '^bead-B$' "$TMP/abandoned" && ok "(2) closed-unmerged PR -> anchor flagged" \
                                || bad "(2) closed-unmerged PR -> anchor flagged"
eq "$(grep -c 'out-of-band close of PR#202' "$TMP/mail")" "1" \
   "(2) out-of-band close escalates to mayor once"
has '^bead-C$' "$TMP/closed" && bad "(3) ready anchor must NOT be closed by the observer" \
                             || ok "(3) ready PR -> anchor left OPEN (detect-only; merge skill lands it)"
has '^bead-D$' "$TMP/closed" && bad "(4) draft anchor must NOT be closed" \
                             || ok "(4) draft PR -> anchor not closed"
# (7) retargeted open PR: flagged + escalated, never closed.
has '^bead-H$' "$TMP/retargeted" && ok "(7) retargeted open anchor flagged merge_result=retargeted" \
                                 || bad "(7) retargeted open anchor flagged merge_result=retargeted"
has '^bead-H$' "$TMP/closed" && bad "(7) retargeted open anchor must NOT be closed" \
                             || ok "(7) retargeted open anchor not closed as landed"
eq "$(grep -c 'PR#208 retargeted' "$TMP/mail")" "1" "(7) retarget escalates to mayor once"
# (8) merged-to-wrong-base: NOT closed as landed, flagged retargeted.
has '^bead-I$' "$TMP/closed" && bad "(8) merged-to-wrong-base anchor must NOT be closed" \
                             || ok "(8) merged-to-wrong-base anchor not closed as landed"
has '^bead-I$' "$TMP/retargeted" && ok "(8) merged-to-wrong-base anchor flagged retargeted" \
                                 || bad "(8) merged-to-wrong-base anchor flagged retargeted"
eq "$(grep -c 'PR#209 retargeted' "$TMP/mail")" "1" "(8) merged-to-wrong-base escalates once"

# (9) stale base: a conflicted PR gets a rebase CHILD routed to the fix pool, and
# the anchor STAYS gating so the merge skill still lands it after the rebase.
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" "(9) conflicted PR -> one rebase child filed"
grep -q "gc.routed_to=$FIX_POOL" "$TMP/updates" \
  && ok "(9) rebase child routed to the fix pool" \
  || bad "(9) rebase child routed to the fix pool (got: $(cat "$TMP/updates"))"
grep -q 'existing_pr=https://github.com/acme/repo/pull/210' "$TMP/updates" \
  && ok "(9) rebase child reworks the EXISTING PR (existing_pr set)" \
  || bad "(9) rebase child must carry existing_pr so no second PR is opened"
J_UPDATES=$(grep '^bead-J' "$TMP/updates" || true)
printf '%s\n' "$J_UPDATES" | grep -q 'stale_base_head=head210' \
  && ok "(9) anchor marked stale_base_head at the detected head" \
  || bad "(9) anchor marked stale_base_head at the detected head (got: $J_UPDATES)"
printf '%s\n' "$J_UPDATES" | grep -q 'merge_result=' \
  && bad "(9) anchor must KEEP merge_result=pull_request (the merge skill still lands it)" \
  || ok "(9) anchor keeps merge_result=pull_request (stays gating, unlike retarget/abandon)"
has '^bead-J$' "$TMP/closed" && bad "(9) conflicted anchor must NOT be closed" \
                             || ok "(9) conflicted anchor not closed"
grep -q 'fix-1 bead-J' "$TMP/deps" \
  && ok "(9) rebase child linked parent-child under the anchor" \
  || bad "(9) rebase child linked parent-child under the anchor (got: $(cat "$TMP/deps"))"
grep -qx "$FIX_POOL" "$TMP/wakes" && ok "(9) fix pool woken for the rebase" \
                                  || bad "(9) fix pool woken for the rebase"
eq "$(grep -c 'PR#210' "$TMP/mail")" "0" "(9) a routable conflict does not escalate to mayor"

# (10) a rework/review child is already open for PR#211 -> do not race it.
eq "$(grep -c 'Rebase PR#211' "$TMP/created")" "0" \
   "(10) conflicted PR with a rework child in flight -> no second rebase child"
# (11) UNKNOWN is GitHub still computing, not a conflict.
eq "$(grep -c 'Rebase PR#212' "$TMP/created")" "0" \
   "(11) mergeable=UNKNOWN never treated as a conflict"
eq "$(grep -c 'Rebase PR#203' "$TMP/created")" "0" \
   "(11) a ready (non-conflicted) PR gets no rebase child"

# --- (16)-(19) operator holds veto the force-push dispatch. -------------------
# This arm does not merge, it DISPATCHES A FORCE-PUSH to a live pool, so every
# marker that holds the gentler merge must hold it too. Before this, none of the
# four shapes below was read: merge-skill.sh refused to merge a merge_hold anchor
# and, seconds later in the same pass, this arm used that same anchor to route a
# rebase (tk-gajop). Each case asserts BOTH halves — no child filed, and the hold
# is announced — because a silent skip is indistinguishable from a missed anchor.

# (16) merge_hold on the anchor: an operator gate on landing is necessarily a
# gate on rewriting the branch underneath it.
eq "$(grep -c 'Rebase PR#214' "$TMP/created")" "0" \
   "(16) anchor merge_hold -> NO rebase child filed (no force-push dispatched)"
printf '%s\n' "$OUT1" | grep -q "bead-N — PR#214 conflicted (stale base) but merge_hold set" \
  && ok "(16) merge_hold hold is announced, naming the operator gate" \
  || bad "(16) merge_hold hold reason (got: $OUT1)"

# (17) rebase_hold on the anchor: the narrower "do not rebase this branch".
eq "$(grep -c 'Rebase PR#215' "$TMP/created")" "0" \
   "(17) anchor rebase_hold -> NO rebase child filed"
printf '%s\n' "$OUT1" | grep -q "bead-O — PR#215 conflicted (stale base) but rebase_hold set" \
  && ok "(17) anchor rebase_hold hold is announced" \
  || bad "(17) anchor rebase_hold hold reason (got: $OUT1)"

# (18) THE OBSERVED DEFECT. A keeper neutralised a runaway rebase child by
# BLOCKING it and setting rebase_hold=true. The old probe asked for
# status=open,in_progress only, so that child was invisible and the arm filed a
# second one on the very next pass — two live children on one branch, a
# concurrent force-push race. Both halves matter: the blocked child must be
# VISIBLE (status list) and its rebase_hold must be READ (the veto).
eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
   "(18) BLOCKED child with rebase_hold -> NO second rebase child on its branch"
printf '%s\n' "$OUT1" | grep -q "child-P holds branch 'polecat/bead-P' with rebase_hold" \
  && ok "(18) hold reason names the holding child and the branch it protects" \
  || bad "(18) blocked-child rebase_hold hold reason (got: $OUT1)"

# (19) The branch dimension. child-Q names PR#999 — keyed on pr_number alone it
# is missed entirely — but it holds branch polecat/bead-Q, which is what a
# force-push actually collides on. This is the shape a PR carrying two anchors
# produces: the per-ANCHOR stale_base_head marker cannot dedupe across anchors,
# so only the branch probe sees the sibling.
eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
   "(19) live child on the same BRANCH under another PR -> no second rebase child"

# (21)(22) EVERY non-closed status owns the branch, not just the ones an operator
# reaches for. `closed` is the only status in the `done` category; the probe's
# status list is a hand-maintained complement of it, so any status left out is an
# invisible branch owner and therefore a second force-push. `hooked` is the sharp
# case — it means a child is attached to an agent's hook, i.e. being worked right
# now — and neither child below carries rebase_hold, so nothing but the status
# list can save them.
eq "$(grep -c 'Rebase PR#218' "$TMP/created")" "0" \
   "(21) HOOKED child on the same branch -> no second rebase child (no force-push race)"
eq "$(grep -c 'Rebase PR#219' "$TMP/created")" "0" \
   "(22) PINNED child on the same branch -> no second rebase child"

# --- (12)(13)(14) anchorless open PRs: the PR -> BEAD direction. --------------
# (12) closed bead + open PR: the close-on-publish blind spot. Reported and
# escalated exactly once, bounded by a marker on the closed bead.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#301' \
  && ok "(12) open PR whose bead is CLOSED is reported as anchorless" \
  || bad "(12) open PR whose bead is CLOSED is reported as anchorless (got: $OUT1)"
eq "$(grep -c 'anchorless open PR#301' "$TMP/mail")" "1" \
   "(12) anchorless PR escalated to mayor once"
grep '^dead-1' "$TMP/updates" | grep -q 'anchorless_flagged=301' \
  && ok "(12) escalation bounded by an anchorless_flagged marker on the closed bead" \
  || bad "(12) escalation bounded by an anchorless_flagged marker (got: $(grep dead-1 "$TMP/updates" || true))"
# Resolution must land on the bead that OPENED the PR — not a review bead (no
# merge_result) and not a later rework child (same marker, newer).
grep -q '^review-1' "$TMP/updates" \
  && bad "(12) review bead must not be marked in place of the anchor" \
  || ok "(12) anchor resolved over a review bead that names the same PR"
grep -q '^rework-1' "$TMP/updates" \
  && bad "(12) later rework child must not be marked in place of the opening anchor" \
  || ok "(12) oldest merge_result bead wins over a later rework child sharing the marker"
grep -q 'anchorless open PR#301 (bead dead-1 is closed)' "$TMP/mail" \
  && ok "(12) escalation names the anchor bead the operator must reopen" \
  || bad "(12) escalation names the anchor bead (got: $(grep 301 "$TMP/mail" || true))"
grep -q 'dead-1, review-1, rework-1' "$TMP/mailbody" \
  && ok "(12) escalation lists every closed bead naming the PR, oldest first" \
  || bad "(12) escalation lists every closed bead naming the PR (got: $(grep -o 'All:.*' "$TMP/mailbody" || true))"
# Detect + surface ONLY: the arm must not close, reopen, or otherwise dispose.
has '^dead-1$' "$TMP/closed" && bad "(12) anchorless arm must NOT close anything" \
                             || ok "(12) anchorless arm closes nothing (detect + surface only)"
grep '^dead-1' "$TMP/updates" | grep -q 'status' \
  && bad "(12) anchorless arm must NOT reopen the closed bead" \
  || ok "(12) anchorless arm never reopens the closed bead (disposition is the operator's)"
# A draft is still invisible to every automated path, so it is still a finding —
# labelled so the operator can weight it.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#303 (draft)' \
  && ok "(12) anchorless draft PR reported and labelled as a draft" \
  || bad "(12) anchorless draft PR reported and labelled (got: $OUT1)"
# Already-escalated: keep reporting (still stranded), do not re-mail.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#304' \
  && ok "(12) already-flagged anchorless PR still reported each pass" \
  || bad "(12) already-flagged anchorless PR still reported each pass"
eq "$(grep -c 'anchorless open PR#304' "$TMP/mail")" "0" \
   "(12) already-flagged anchorless PR is not re-escalated"

# (13) a PR any LIVE bead references is tracked by something -> not a finding.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#203' \
  && bad "(13) PR tracked by a live gating anchor must not be flagged" \
  || ok "(13) PR tracked by a live gating anchor is not flagged"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#211' \
  && bad "(13) PR tracked by a live rework child must not be flagged" \
  || ok "(13) PR tracked by a live rework child is not flagged"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#77' \
  && ok "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7" \
  || bad "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7 (got: $OUT1)"

# (14) no bead in any state: report it, but never mail — there is nothing
# durable to bound the escalation, so mailing would repeat every wake forever.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#302' \
  && ok "(14) open PR with no bead in any state is reported" \
  || bad "(14) open PR with no bead in any state is reported (got: $OUT1)"
eq "$(grep -c 'anchorless open PR#302' "$TMP/mail")" "0" \
   "(14) unboundable (no-bead) finding is reported but never escalated"

printf '%s\n' "$OUT1" | grep -q '8 anchorless open PRs' \
  && ok "run 1 summary reports 8 anchorless open PRs" \
  || bad "run 1 summary anchorless count (got: $OUT1)"

# --- (32)-(36) a bead can name its PR under keys other than pr_number. ---------
# reconcile built every PR-keyed lookup from metadata.pr_number ALONE, so a live
# bead naming its PR as fork_pr / fork_pr_url was invisible to all of them. The
# observed case is gascity gc-qin3c / PR#100: open, live, naming the PR — and
# reported ANCHORLESS on every single refinery cycle, re-triaged from scratch
# each wake with nothing any pass could do to clear it.

# (32) The BEAD -> PR direction: the in-flight probe. child-Z is open on PR#230
# under fork_pr and carries no branch, so the branch dimension cannot see it
# either — the widened PR key is the only thing standing between a conflicted PR
# and a second force-push onto a rework already in flight. This is the half of
# the widening that is easy to skip and expensive to miss.
eq "$(grep -c 'Rebase PR#230' "$TMP/created")" "0" \
   "(32) fork_pr-keyed rework child in flight -> no second rebase child (probe sees it)"

# (33) The PR -> BEAD direction: a fork_pr-keyed live bead makes its PR tracked,
# so it is no longer reported as anchorless...
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#401' \
  && bad "(33) PR named by a live fork_pr-keyed bead must not be reported anchorless" \
  || ok "(33) fork_pr-keyed live bead makes its PR tracked (no false anchorless)"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#402' \
  && bad "(33) PR named by a live fork_pr_url-keyed bead must not be reported anchorless" \
  || ok "(33) fork_pr_url-keyed live bead makes its PR tracked (number parsed from the URL)"
eq "$(grep -c 'anchorless open PR#401' "$TMP/mail")" "0" \
   "(33) fork_pr-keyed tracked PR is never escalated"

# (34) ...but tracked is NOT owned. Widening the key set alone would convert
# PR#401 from a noisy false finding into SILENCE, which is the exact downside the
# cheap alternative (hand-stamping pr_number) was rejected for. A live bead with
# no merge_result, no branch, no target and no merge_strategy tracks the PR
# without owning it: nothing will land it either way, so it keeps its own line.
printf '%s\n' "$OUT1" | grep -q 'UNOWNED PR#401' \
  && ok "(34) tracked-but-ungated PR reported as UNOWNED, not silently dropped" \
  || bad "(34) tracked-but-ungated PR reported as UNOWNED (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q 'UNOWNED PR#401.*live-fork (operator)' \
  && ok "(34) UNOWNED line names the live bead and its assignee" \
  || bad "(34) UNOWNED line names the bead + assignee (got: $(printf '%s\n' "$OUT1" | grep 'PR#401' || true))"
printf '%s\n' "$OUT1" | grep -q 'UNOWNED PR#402' \
  && ok "(34) fork_pr_url-keyed ungated PR also reported as UNOWNED" \
  || bad "(34) fork_pr_url-keyed ungated PR reported as UNOWNED (got: $OUT1)"
# The rule is about gating metadata, not about the fork keys: a plain
# pr_number-keyed bead with nothing to act on is just as unowned.
printf '%s\n' "$OUT1" | grep -q 'UNOWNED PR#404' \
  && ok "(34) pr_number-keyed bead with no gating metadata is UNOWNED too (not a fork-only rule)" \
  || bad "(34) ungated pr_number-keyed bead is UNOWNED (got: $OUT1)"
# Non-escalating: the naming bead is LIVE, so this is a routing gap an operator
# can close, not a stranded PR. Mailing it would repeat every wake.
eq "$(grep -c 'PR#401' "$TMP/mail")" "0" \
   "(34) UNOWNED is reported but never escalated (a live bead still names it)"

# (35) A bead that DOES carry gating metadata is owned, whatever key it used to
# name the PR — so it stays silent. Without this the UNOWNED arm would just be
# the anchorless arm under a new name.
printf '%s\n' "$OUT1" | grep -q 'PR#403' \
  && bad "(35) fork_pr-keyed bead WITH gating metadata must be silent (owned)" \
  || ok "(35) fork_pr-keyed bead with gating metadata -> owned, no line at all"
printf '%s\n' "$OUT1" | grep -q '3 unowned open PRs' \
  && ok "(34) run 1 summary reports 3 unowned open PRs" \
  || bad "(34) run 1 summary unowned count (got: $OUT1)"

# (36) The CLOSED-bead resolution is widened the same way. dead-5 named PR#405
# only as fork_pr: keyed on pr_number alone it resolves to nothing, the arm falls
# into the "no bead in any state" branch — which by design does NOT escalate —
# and a genuinely stranded PR is silently downgraded to a log line forever.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#405' \
  && ok "(36) open PR whose closed anchor is fork_pr-keyed is still anchorless" \
  || bad "(36) fork_pr-keyed closed anchor -> anchorless (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#405.*anchor dead-5 is CLOSED' \
  && ok "(36) fork_pr-keyed closed anchor is RESOLVED, not reported as 'no bead in any state'" \
  || bad "(36) fork_pr-keyed closed anchor resolved to dead-5 (got: $(printf '%s\n' "$OUT1" | grep 'PR#405' || true))"
eq "$(grep -c 'anchorless open PR#405' "$TMP/mail")" "1" \
   "(36) resolved fork_pr-keyed anchor escalates once (the unwidened path could not)"
grep '^dead-5' "$TMP/updates" | grep -q 'anchorless_flagged=405' \
  && ok "(36) escalation bounded by a marker on the fork_pr-keyed closed bead" \
  || bad "(36) anchorless_flagged marker on dead-5 (got: $(grep dead-5 "$TMP/updates" || true))"

# --- (37)(38) A PR NUMBER IS NOT AN IDENTITY. ---------------------------------
# Every lookup above widened the KEYS a bead may name its PR with. This is the
# other half: the numbers those keys hold are unique only within a repository,
# while `gh pr list` here is pinned to $ORIGIN_REPO_Q — so the tracked set and the
# closed-bead resolution were comparing THIS repository's pull requests against
# EVERY repository's beads. Both directions break, and in opposite ways
# (review tk-thvbq finding #2).

# (37) A FOREIGN LIVE bead silences a real finding. live-foreign-406 is open and
# names #406, but its pr_url is on another host — a different pull request. Keyed
# on the bare number our open #406 reads as tracked (or UNOWNED) and its genuinely
# anchorless state is never reported: silence that looks exactly like health.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#406' \
  && ok "(37) a foreign same-numbered LIVE bead does not track our PR#406 into silence" \
  || bad "(37) PR#406 must still be reported anchorless (got: $(printf '%s\n' "$OUT1" | grep 'PR#406' || echo '<no line at all>'))"
printf '%s\n' "$OUT1" | grep -q 'UNOWNED PR#406' \
  && bad "(37) a foreign bead must not make our PR 'tracked but unowned' either" \
  || ok "(37) the foreign bead does not downgrade the finding to UNOWNED"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#406.*anchor dead-406 is CLOSED' \
  && ok "(37) ...and the SAME-repository closed anchor still resolves normally" \
  || bad "(37) dead-406 must still resolve (got: $(printf '%s\n' "$OUT1" | grep 'PR#406' || true))"
eq "$(grep -c 'anchorless open PR#406' "$TMP/mail")" "1" \
   "(37) the real finding escalates once, as it would with no foreign bead present"

# (38) A FOREIGN CLOSED bead RECEIVES A WRITE it should never see. Keyed on the
# bare number, dead-foreign-407 resolves as the dead anchor of OUR #407: it gets
# the anchorless_flagged stamp (a write onto a stranger's bead) and is named in a
# mail as the bead to reopen — and, worse, that stamp BOUNDS the escalation for a
# PR it never owned, so the real finding goes quiet from the next pass on.
# Qualified, nothing resolves and the PR falls to the non-escalating
# "no bead in any state" arm, which is the honest answer here.
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#407' \
  && ok "(38) PR#407 is still reported anchorless" \
  || bad "(38) PR#407 must be reported anchorless (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q 'ANCHORLESS PR#407.*no bead in any state references it' \
  && ok "(38) a foreign closed bead does not resolve as our PR's dead anchor" \
  || bad "(38) PR#407 must fall to the no-bead arm (got: $(printf '%s\n' "$OUT1" | grep 'PR#407' || true))"
grep '^dead-foreign-407' "$TMP/updates" | grep -q 'anchorless_flagged' \
  && bad "(38) a foreign closed bead must NEVER be stamped anchorless_flagged for our PR" \
  || ok "(38) no metadata written to the foreign closed bead"
eq "$(grep -c 'anchorless open PR#407' "$TMP/mail")" "0" \
   "(38) nothing escalated naming a stranger's bead (and no false bound on the finding)"

# (INV) NO MERGE AUTHORITY: the observer must never call `gh pr merge` for ANY
# anchor — the seam that the auto-merge retirement turns on. $FAKE_AUTOMERGE
# stays empty across the entire run (ready, draft, retargeted, merged alike).
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(INV) observer never runs 'gh pr merge' (detect-only, no merge authority)"

# Summary counters + the absence of any auto-merge wording.
printf '%s\n' "$OUT1" | grep -q "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "2 retargeted" \
  && ok "run 1 summary reports 2 retargeted" \
  || bad "run 1 summary retargeted count (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -qi "auto-merge" \
  && bad "run 1 summary must not mention auto-merge (it was retired)" \
  || ok "run 1 summary makes no mention of auto-merge"

# --- Regression guard (field shape): only gh-supported --json fields. ---------
# The stub models real gh: it REJECTS `merged` (the field the original bug
# requested) and ACCEPTS the script's real field set. The disposition matrix
# above already exercises this end-to-end (the script would skip every anchor on
# a rejected field); these direct probes document the contract so a reintroduced
# `merged` fails loudly with an obvious message.
gh pr view 201 --json merged >/dev/null 2>&1 \
  && bad "(6) gh stub must REJECT unsupported field 'merged' (models real gh)" \
  || ok "(6) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 201 --json state,mergedAt,mergeCommit,isDraft,baseRefName >/dev/null 2>&1 \
  && ok "(6) the script's --json field set is accepted by the gh stub" \
  || bad "(6) the script's --json field set must be accepted"

# --- Run 2: convergence. Closed / flagged / retargeted anchors leave the set. -
MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c '^bead-A$' "$TMP/closed")" "1" "(5) merged anchor not re-closed on second pass"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" "(5) flagged + retargeted anchors not re-escalated on second pass"
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" \
   "(5) stale-base anchor stays in the gating set but files no second rebase child"
eq "$(grep -c 'anchorless open PR#301' "$TMP/mail")" "1" \
   "(12) anchorless PR not re-escalated on a second pass (marker converged)"

# --- Run 3: the marker is what bounds it, and it re-arms when the head moves. --
# Close the rebase child (as the patrol does on hand-back) so the in-flight guard
# no longer applies — the stale_base_head marker alone must hold the arm.
awk -F'\t' '$1 != "210"' "$TMP/children" > "$TMP/children.next"
mv "$TMP/children.next" "$TMP/children"
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "1" \
   "(9) same head, child closed -> stale_base_head alone bounds it to one rebase"
# The polecat pushed: same conflict, NEW head -> a genuinely new stall, so re-arm.
sed 's/^210|\(.*\)|head210|/210|\1|head210b|/' "$TMP/prs" > "$TMP/prs.next"
mv "$TMP/prs.next" "$TMP/prs"
bash "$SCRIPT" --fix-pool "$FIX_POOL" >/dev/null
eq "$(grep -c 'Rebase PR#210' "$TMP/created")" "2" \
   "(9) head moved and still conflicting -> arm re-fires for the new head"

# --- Run 4: no fix pool -> escalate to human rather than file an unroutable ---
# child. Flip PR#213 to CONFLICTING and run with no --fix-pool.
sed 's/^213|.*/213|OPEN||false||main|polecat\/bead-M|head213|CONFLICTING|DIRTY/' "$TMP/prs" > "$TMP/prs.next"
mv "$TMP/prs.next" "$TMP/prs"
bash "$SCRIPT" >/dev/null
eq "$(grep -c 'Rebase PR#213' "$TMP/created")" "0" \
   "(9) no fix pool -> no unroutable rebase child is filed"
eq "$(grep -c 'PR#213 conflicted (stale base) with no fix pool' "$TMP/mail")" "1" \
   "(9) no fix pool -> escalated to mayor once"
M_UPDATES=$(grep '^bead-M' "$TMP/updates" || true)
printf '%s\n' "$M_UPDATES" | grep -q 'gc.routed_to=human' \
  && ok "(9) no fix pool -> anchor routed to human" \
  || bad "(9) no fix pool -> anchor routed to human (got: $M_UPDATES)"

# --- Run 5: zero gating anchors must NOT short-circuit the anchorless scan. ---
# Before the anchorless arm this pass returned early on an empty gating set. That
# is the worst possible place to go blind: zero live anchors WITH open PRs is
# precisely the stranded state the scan exists to surface.
: > "$TMP/anchors"
printf '305|false|polecat/dead-5|main\n' > "$TMP/openprs"
OUT5="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"
printf '%s\n' "$OUT5" | grep -q 'no gating anchors' \
  && ok "(15) empty gating set still reported" \
  || bad "(15) empty gating set still reported (got: $OUT5)"
printf '%s\n' "$OUT5" | grep -q 'ANCHORLESS PR#305' \
  && ok "(15) anchorless scan runs even with zero gating anchors" \
  || bad "(15) anchorless scan runs even with zero gating anchors (got: $OUT5)"

# --- Run 6: fail CLOSED when the live-bead read fails. -----------------------
# An empty ledger read is indistinguishable from "no bead tracks anything". If
# the scan trusted it, EVERY open PR would be flagged and escalated at once — a
# mail storm out of a transient Dolt blip. It must report nothing instead.
MAIL_BEFORE6=$(wc -l < "$TMP/mail" | tr -d ' ')
printf '306|false|polecat/dead-6|main\n' > "$TMP/openprs"
OUT6="$(FAKE_LIVE_FAIL=1 bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
printf '%s\n' "$OUT6" | grep -q 'ANCHORLESS' \
  && bad "(14) failed live-bead read must not flag anything (fail closed)" \
  || ok "(14) failed live-bead read flags nothing (fail closed, no mail storm)"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE6" \
   "(14) failed live-bead read escalates nothing"
printf '%s\n' "$OUT6" | grep -q '0 anchorless open PRs' \
  && ok "(14) failed live-bead read reports a zero anchorless count" \
  || bad "(14) failed live-bead read reports a zero anchorless count (got: $OUT6)"

# --- (39) ...and "failed" is more shapes than "empty". ------------------------
# The emptiness test above catches only the read that wrote NOTHING. `gc bd list
# --json` reports its own failures as a non-empty error OBJECT on stdout, and a
# read that dies after emitting announces that only in its exit status — both
# survive an emptiness test, and both then build a TRACKED set out of a payload
# that is not a bead list. The consequence is the same mail storm this arm fails
# closed against, reached by a route the original guard could not see
# (review tk-thvbq finding #3). Each shape is asserted separately: a guard no case
# pins is a guard a later edit can delete silently.
for shape in error-rc1 error-rc0 array-rc1; do
  MAIL_BEFORE=$(wc -l < "$TMP/mail" | tr -d ' ')
  UPD_BEFORE=$(wc -l < "$TMP/updates" | tr -d ' ')
  OUT_S="$(FAKE_LIVE_SHAPE="$shape" bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>"$TMP/err39")"
  printf '%s\n' "$OUT_S" | grep -q 'ANCHORLESS' \
    && bad "(39/$shape) an unreadable live-bead read must flag nothing (fail closed)" \
    || ok "(39/$shape) unreadable live-bead read ($shape) flags nothing"
  eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE" \
     "(39/$shape) unreadable live-bead read escalates nothing"
  eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "$UPD_BEFORE" \
     "(39/$shape) unreadable live-bead read writes no bead metadata"
  grep -q 'live-bead read failed; anchorless scan skipped' "$TMP/err39" \
    && ok "(39/$shape) the skipped scan is reported, never silent" \
    || bad "(39/$shape) must report the skipped scan (err: $(cat "$TMP/err39"))"
done

# --- (20) an unreadable rework probe must fail CLOSED. -----------------------
# The probe is the only thing standing between a conflicted PR and a dispatched
# force-push, so a FAILED read of it must never be mistaken for "nobody holds
# this branch". PR#216 and PR#217 are the live cases: both are held only by a
# bead the probe would have to return, so if the failure reads as "empty" the arm
# files a rebase child for each — dispatching exactly the force-push the operator
# froze. A deferred rebase costs one pass; an un-vetoed force-push is not
# recoverable by retry.
# Run 5 emptied the gating set to prove the anchorless scan still runs; restore
# the two anchors this case needs (neither carries stale_base_head — they have
# only ever exited the arm through a hold, before the stamp — so both reach the
# probe on this pass).
printf '%s\n' 'bead-P|216|main||' 'bead-Q|217|main||' > "$TMP/anchors"
CREATED_BEFORE7="$(wc -l < "$TMP/created" | tr -d ' ')"
OUT7="$(FAKE_PROBE_FAIL=1 bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
eq "$(wc -l < "$TMP/created" | tr -d ' ')" "$CREATED_BEFORE7" \
   "(20) failed rework probe files NO rebase child (fail closed, no force-push)"
eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
   "(20) failed probe -> still no child for the branch a keeper froze"
eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
   "(20) failed probe -> still no child for the shared-branch PR"
printf '%s\n' "$OUT7" | grep -q '0 stale-base rebases routed' \
  && ok "(20) failed probe routes no rebases at all" \
  || bad "(20) failed probe must route zero rebases (got: $OUT7)"

# --- (23) a probe that FAILS WITH OUTPUT must also fail CLOSED. ---------------
# Case (20) covers the failure that is easy to spot: no output at all. These are
# the ones that are not. `gc ... --json` reports its own errors as a non-empty
# JSON object on stdout, so "did anything come back?" answers YES for a read that
# wholly failed; the object then yields zero rows through the projection and the
# arm concludes the branch is unowned.
#
# Each shape below defeats every guard except one, so each pins a DIFFERENT guard
# and none of them can be deleted without a red test. Same fixtures as (20) —
# PR#216 and PR#217 are held ONLY by beads the probe would have to return — so any
# shape that reads as "empty" force-pushes over exactly the freeze an operator
# just set. `[]` with a zero exit is NOT in this list: that is the legitimate
# "nobody holds it" answer, and cases (9)-(11) already cover it.
for shape in error-rc1 error-rc0 array-rc1 bad-array object-map; do
  CREATED_BEFORE8="$(wc -l < "$TMP/created" | tr -d ' ')"
  OUT8="$(FAKE_PROBE_SHAPE="$shape" bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
  eq "$(wc -l < "$TMP/created" | tr -d ' ')" "$CREATED_BEFORE8" \
     "(23/$shape) unreadable probe files NO rebase child (fail closed)"
  eq "$(grep -c 'Rebase PR#216' "$TMP/created")" "0" \
     "(23/$shape) still no child for the branch a keeper froze"
  eq "$(grep -c 'Rebase PR#217' "$TMP/created")" "0" \
     "(23/$shape) still no child for the shared-branch PR"
  printf '%s\n' "$OUT8" | grep -q '0 stale-base rebases routed' \
    && ok "(23/$shape) routes no rebases at all" \
    || bad "(23/$shape) must route zero rebases (got: $OUT8)"
done

# --- Run 8: stale-gate self-heal (WS4 GAP1, su-PR#31 class). ------------------
# A gating anchor whose codex marker is green@<oid> at a head that has since MOVED
# (a direct push to the PR branch filed no rework bead) sits in a SILENT
# indefinite hold: merge-skill.sh refuses (green@old != live head) but nothing
# re-dispatches the review. The new arm files a codex RE-REVIEW child at the LIVE
# head, routes it to the review (codex) pool, keeps the anchor gating, and bounds
# itself to one re-review per head. Symmetric with the stale-BASE rebase arm.
REVIEW_POOL="test-rig/gc-toolkit.polecat-codex"
# anchors: id|pr|target|merge_hold|rebase_hold|check_set|check.codex-marker
#   bead-T 220 codex green@old220, live head head220 -> STALE -> re-review filed
#   bead-U 221 codex green@head221 == live head       -> current, nothing
#   bead-V 222 codex green@old222 STALE but a review child already open -> no twin
printf '%s\n' \
  'bead-T|220|main|||codex|green@old220' \
  'bead-U|221|main|||codex|green@head221' \
  'bead-V|222|main|||codex|green@old222' \
  > "$TMP/anchors"
# All open, ready, non-conflicting: the stale gate is the ONLY thing holding them.
printf '%s\n' \
  '220|OPEN||false||main|polecat/bead-T|head220|MERGEABLE|BLOCKED' \
  '221|OPEN||false||main|polecat/bead-U|head221|MERGEABLE|BLOCKED' \
  '222|OPEN||false||main|polecat/bead-V|head222|MERGEABLE|BLOCKED' \
  > "$TMP/prs"
printf '222\tchild-V\n' > "$TMP/children"       # bead-V already has an open review child
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"
OUT8="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"

# (24) moved head: green@stale + no child -> ONE re-review child at the live head.
eq "$(grep -c 'Review PR#220' "$TMP/created")" "1" \
   "(24) stale codex gate (head moved) -> one re-review child filed"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && ok "(24) re-review child routed to the review (codex) pool" \
  || bad "(24) re-review child routed to the review pool (got: $(cat "$TMP/updates"))"
grep -q 'task_kind=review' "$TMP/updates" \
  && ok "(24) re-review child is task_kind=review" \
  || bad "(24) re-review child is task_kind=review"
grep -q 'anchor_bead=bead-T' "$TMP/updates" \
  && ok "(24) re-review child anchored to the gating anchor (anchor_bead)" \
  || bad "(24) re-review child carries anchor_bead=bead-T"
grep -q 'pr_number=220' "$TMP/updates" \
  && ok "(24) re-review child names the PR (post-open review)" \
  || bad "(24) re-review child names the PR"
# The re-review MUST carry fix_target_pool or its signoff completion path can do
# NOTHING with the verdict — no check.codex stamp on COMMENT, no rework child on
# REQUEST_CHANGES (template-fragments/polecat-non-impl-done.template.md gates every
# action on a non-empty fix_target_pool). bead-T carries no fix_target_pool of its
# own (normal gating anchors don't), so the arm must fall back to the patrol's
# --fix-pool value. Without the fallback the anchor keeps its stale marker and sits
# in the exact indefinite hold this arm heals (tk-awrlk finding #1). Together with
# the pr_number/anchor_bead/blocks-dep assertions above, this proves the child
# carries the COMPLETE metadata set a REQUEST_CHANGES rework needs to route.
grep -q "fix_target_pool=$FIX_POOL" "$TMP/updates" \
  && ok "(24) re-review child carries fix_target_pool (falls back to the --fix-pool default)" \
  || bad "(24) re-review child carries fix_target_pool=$FIX_POOL (got: $(grep 'fix_target_pool' "$TMP/updates" || echo none))"
grep -q -- '--blocks bead-T' "$TMP/deps" \
  && ok "(24) re-review child gates the anchor via a BLOCKS dep" \
  || bad "(24) re-review child blocks-dep on the anchor (got: $(cat "$TMP/deps"))"
# (24-METHOD) The re-review carries the review METHOD in its body (tk-jufvl), from
# the SAME emitter check-set-heal.sh uses — a re-review that described the job
# differently from the first-round review would be the divergence that fix
# removes. A title-only bead sends the reviewer back to catalog-matching, which is
# what ran the ~4.7M-token persona fan-out per review.
REREVIEW_ID=$(awk -F'\t' '$2 ~ /Review PR#220/{print $1; exit}' "$TMP/created")
if [ -n "$REREVIEW_ID" ] && [ -f "$TMP/bodies/$REREVIEW_ID" ]; then
  ok "(24-METHOD) the re-review was created with a body"
  grep -qF 'signoff-review' "$TMP/bodies/$REREVIEW_ID" \
    && ok "(24-METHOD) the re-review body names the signoff-review method" \
    || bad "(24-METHOD) the re-review body must name the method"
  grep -qF 'Do NOT spawn' "$TMP/bodies/$REREVIEW_ID" \
    && ok "(24-METHOD) the re-review body forbids subagent/persona fan-out" \
    || bad "(24-METHOD) the re-review body must forbid fan-out"
  # The stale-gate context reaches the BODY too, not just review_note metadata:
  # which head went stale is what tells the reviewer where to look.
  grep -qF 'Stale-gate self-heal' "$TMP/bodies/$REREVIEW_ID" \
    && ok "(24-METHOD) the dispatch note (which head went stale) reaches the body" \
    || bad "(24-METHOD) the stale-gate note must reach the body"
else
  bad "(24-METHOD) no body captured for the re-review (got created: $(cat "$TMP/created"))"
fi
grep -qx "$REVIEW_POOL" "$TMP/wakes" && ok "(24) review pool woken" \
                                     || bad "(24) review pool woken"
T_UPD=$(grep '^bead-T' "$TMP/updates" || true)
printf '%s\n' "$T_UPD" | grep -q 'stale_gate_head=head220' \
  && ok "(24) anchor marked stale_gate_head at the live head" \
  || bad "(24) anchor marked stale_gate_head (got: $T_UPD)"
printf '%s\n' "$T_UPD" | grep -q 'merge_result=' \
  && bad "(24) anchor must KEEP merge_result=pull_request (stays gating)" \
  || ok "(24) anchor keeps merge_result=pull_request (unlike retarget/abandon)"
has '^bead-T$' "$TMP/closed" && bad "(24) stale-gate anchor must NOT be closed" \
                             || ok "(24) stale-gate anchor not closed"
# The remedy is a REAL review, NEVER a hand-stamped green (that certifies an
# unreviewed commit — the tk-4na1b failure mode).
printf '%s\n' "$T_UPD" | grep -q 'check.codex=green' \
  && bad "(24) must NEVER hand-stamp check.codex green (certifies an unreviewed commit)" \
  || ok "(24) never hand-stamps check.codex green (dispatches a real review)"

# (25) current-green: marker == live head -> not stale, no re-review.
eq "$(grep -c 'Review PR#221' "$TMP/created")" "0" \
   "(25) codex green AT the live head -> no re-review (not stale)"
# (26) an open review child already re-raises the gate -> no twin.
eq "$(grep -c 'Review PR#222' "$TMP/created")" "0" \
   "(26) stale gate but a review child already open -> no second re-review"

printf '%s\n' "$OUT8" | grep -q '1 stale-gate re-reviews routed' \
  && ok "(24) run 8 summary reports 1 stale-gate re-review routed" \
  || bad "(24) run 8 summary stale-gate count (got: $OUT8)"

# --- Run 9: stale_gate_head bounds it (unchanged head), re-arms when head moves. -
# Close bead-T's review child (as the patrol does on hand-back) so the in-flight
# guard no longer applies — stale_gate_head alone must hold the arm at an
# unchanged head, then re-fire once the head advances again.
awk -F'\t' '$1 != "220"' "$TMP/children" > "$TMP/children.next"
mv "$TMP/children.next" "$TMP/children"
bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" >/dev/null
eq "$(grep -c 'Review PR#220' "$TMP/created")" "1" \
   "(27) unchanged head, child closed -> stale_gate_head alone bounds it to one re-review"
# A new direct push moved the head; the gate is stale against a NEW head -> re-arm.
sed 's/^220|\(.*\)|head220|/220|\1|head220b|/' "$TMP/prs" > "$TMP/prs.next"
mv "$TMP/prs.next" "$TMP/prs"
bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" >/dev/null
eq "$(grep -c 'Review PR#220' "$TMP/created")" "2" \
   "(27) head moved again and gate still stale -> arm re-fires for the new head"

# --- Run 10: no --review-pool -> HOLD, never hand-stamp green. ----------------
# Without a review pool the arm cannot dispatch. It must NOT stamp check.codex
# green itself (that certifies an unreviewed commit — the tk-4na1b failure mode);
# it stamps the head guard, surfaces the block, and leaves the anchor gating so
# the merge stays HELD on the stale marker.
printf '%s\n' 'bead-W|223|main|||codex|green@old223' > "$TMP/anchors"
printf '%s\n' '223|OPEN||false||main|polecat/bead-W|head223|MERGEABLE|BLOCKED' > "$TMP/prs"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"
OUT10="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"
eq "$(grep -c 'Review PR#223' "$TMP/created")" "0" \
   "(28) no review pool -> no re-review child filed"
W_UPD=$(grep '^bead-W' "$TMP/updates" || true)
printf '%s\n' "$W_UPD" | grep -q 'check.codex=green' \
  && bad "(28) no pool must NEVER hand-stamp check.codex green" \
  || ok "(28) no pool never hand-stamps check.codex green (holds instead)"
# The no-pool hold stamps a DISTINCT marker (stale_gate_nopool_head), NOT
# stale_gate_head. stale_gate_head means "a review was dispatched at this head" and
# the one-per-head guard skips it forever; stamping it on a no-pool pass would
# suppress the dispatch even after a review pool is configured (tk-v2b0k finding #1,
# tested in Run 11 below). The no-pool marker bounds the busy-loop without blocking
# that later recovery.
printf '%s\n' "$W_UPD" | grep -q 'stale_gate_nopool_head=head223' \
  && ok "(28) no pool -> DISTINCT no-pool head guard stamped so it does not busy-loop" \
  || bad "(28) no pool -> stale_gate_nopool_head stamped (got: $W_UPD)"
printf '%s\n' "$W_UPD" | grep -q 'stale_gate_head=head223' \
  && bad "(28) no pool must NOT stamp stale_gate_head (would suppress a later configured dispatch)" \
  || ok "(28) no pool -> stale_gate_head NOT stamped (reserved for a real dispatch)"
printf '%s\n' "$OUT10" | grep -q '1 stale-gate re-reviews held' \
  && ok "(28) no pool -> counted as a held re-review" \
  || bad "(28) no pool -> held count (got: $OUT10)"

# --- Run 11: a no-pool hold RECOVERS once a review pool is configured. ---------
# The Run 10 no-pool pass held bead-W at head223 without dispatching. Re-run at the
# SAME head WITH --review-pool: the arm must now file the re-review instead of being
# permanently suppressed by the head guard. Before tk-v2b0k finding #1 the no-pool
# pass stamped stale_gate_head=head223, so this pass hit the one-per-head guard and
# skipped forever — recreating the exact silent hold the whole arm exists to heal.
# (Continues from Run 10: gatenopool carries the head223 hold marker; NOT reset.)
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
OUT11="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#223' "$TMP/created")" "1" \
   "(29) no-pool hold + review pool configured later -> re-review dispatched at the same head (not suppressed)"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && ok "(29) recovered re-review child routed to the review pool" \
  || bad "(29) recovered re-review child routed to the review pool (got: $(cat "$TMP/updates"))"
grep -q 'anchor_bead=bead-W' "$TMP/updates" \
  && ok "(29) recovered re-review anchored to bead-W" \
  || bad "(29) recovered re-review carries anchor_bead=bead-W"
W_UPD2=$(grep '^bead-W' "$TMP/updates" || true)
printf '%s\n' "$W_UPD2" | grep -q 'stale_gate_head=head223' \
  && ok "(29) recovered dispatch stamps the real stale_gate_head guard at the live head" \
  || bad "(29) recovered dispatch stamps stale_gate_head=head223 (got: $W_UPD2)"
printf '%s\n' "$W_UPD2" | grep -q 'check.codex=green' \
  && bad "(29) recovered dispatch must NEVER hand-stamp check.codex green" \
  || ok "(29) recovered dispatch never hand-stamps green (files a real review)"
printf '%s\n' "$OUT11" | grep -q '1 stale-gate re-reviews routed' \
  && ok "(29) run 11 summary reports the recovered re-review routed" \
  || bad "(29) run 11 summary stale-gate routed count (got: $OUT11)"

# --- Run 12: a DROPPED route write must not falsely arm the head; a later pass
# repairs the stranded review (tk-3xy37 finding). -----------------------------
# The stale-gate route write (gc.routed_to -> review pool) is what makes the
# re-review CLAIMABLE. Before this fix it was an unchecked best-effort write, yet
# the arm stamped stale_gate_head and counted the dispatch unconditionally: a
# transient loss left the review UNROUTED (inert) while the one-per-head guard
# marked the head done, so every later pass skipped it at that guard and the merge
# sat held behind a bead nothing could claim — the exact silent hold this arm
# exists to heal. The fix arms the head ONLY after reading gc.routed_to back, and
# the in-flight probe re-routes an unrouted review for the anchor on a later pass.
printf '%s\n' 'bead-X|224|main|||codex|green@old224' > "$TMP/anchors"
printf '%s\n' '224|OPEN||false||main|polecat/bead-X|head224|MERGEABLE|BLOCKED' > "$TMP/prs"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/children"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"

# Pass A: the route write to the review pool is dropped in flight.
OUT12A="$(FAKE_ROUTE_FAIL="$REVIEW_POOL" bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#224' "$TMP/created")" "1" \
   "(30) route write dropped -> the re-review bead is still filed"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && bad "(30) dropped route must NOT persist gc.routed_to (it was lost in flight)" \
  || ok "(30) dropped route leaves the re-review UNROUTED"
grep -q 'stale_gate_head=head224' "$TMP/updates" \
  && bad "(30) must NOT arm stale_gate_head when the route did not persist (would suppress the retry)" \
  || ok "(30) head guard NOT armed on a dropped route (so a later pass re-enters)"
printf '%s\n' "$OUT12A" | grep -q '0 stale-gate re-reviews routed' \
  && ok "(30) dropped route -> summary counts routed=0, not a false dispatch" \
  || bad "(30) run 12A summary must report 0 routed (got: $OUT12A)"

# Pass B: the transient loss clears. The arm re-enters (head unarmed) and the
# in-flight probe re-routes the SAME stranded review — no twin, no new bead.
OUT12B="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#224' "$TMP/created")" "1" \
   "(31) repair pass re-routes the SAME review -> no twin re-review bead"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && ok "(31) repair pass routes the stranded re-review to the review pool" \
  || bad "(31) repair pass must route the stranded re-review (got: $(cat "$TMP/updates"))"
grep -q 'stale_gate_head=head224' "$TMP/updates" \
  && ok "(31) repair pass NOW arms stale_gate_head at the live head" \
  || bad "(31) repair pass must arm stale_gate_head=head224"
printf '%s\n' "$OUT12B" | grep -q 'stale-gate repair' \
  && ok "(31) repair pass logs the stale-gate route repair" \
  || bad "(31) repair pass must log the repair (got: $OUT12B)"
printf '%s\n' "$OUT12B" | grep -q '1 stale-gate re-reviews routed' \
  && ok "(31) repair pass -> summary reports the recovered re-review routed" \
  || bad "(31) run 12B summary stale-gate routed count (got: $OUT12B)"
grep -qx "$REVIEW_POOL" "$TMP/wakes" \
  && ok "(31) repair pass wakes the review pool" \
  || bad "(31) repair pass wakes the review pool"

# --- Run 13: REPOFAIL. The origin repository cannot be resolved. ---------------
# Every PR here is named by NUMBER, and a number resolves in whatever repository
# gh considers current. This pass has no merge authority, but it CLOSES anchors as
# landed and escalates out-of-band closes — terminal writes, made off those reads.
# With no origin to pin them to, it must record NOTHING and retry next wake
# (review tk-sdqwh finding #2).
: > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/mail"; : > "$TMP/created"
echo 1 > "$TMP/repofail"
RC13=0
bash "$SCRIPT" --fix-pool "$FIX_POOL" >"$TMP/out13" 2>"$TMP/err13" || RC13=$?
: > "$TMP/repofail"
eq "$RC13" "0" "(REPOFAIL) the refusal is a clean skip, never an abort of the patrol loop"
eq "$(wc -l < "$TMP/closed" | tr -d ' ')" "0" "(REPOFAIL) unresolvable origin -> no anchor closed"
eq "$(wc -l < "$TMP/abandoned" | tr -d ' ')" "0" "(REPOFAIL) unresolvable origin -> nothing flagged abandoned"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "0" "(REPOFAIL) unresolvable origin -> nothing escalated"
grep -q "cannot resolve this checkout's origin repository" "$TMP/err13" \
  && ok "(REPOFAIL) the refusal is reported for an operator" \
  || bad "(REPOFAIL) must warn that the origin is unresolvable (err: $(cat "$TMP/err13"))"

# --- PR IDENTITY: a same-numbered pull request from ANOTHER repository. --------
# REPOFAIL above covers the case where the expectation cannot be formed at all.
# These cover the case where it CAN — the read is pinned to it — and the answer
# comes back from somewhere else anyway: a gh that ignores `--repo` (a redirect
# after a repository transfer or rename, an older gh, a wrapper), a drifted
# GH_HOST under a hostless pin, or an anchor whose own recorded pr_url names a
# different pull request.
#
# merge-skill.sh added this post-read guard because a wrong MERGE cannot be
# retried away. This pass has no merge authority, but it closes anchors as landed,
# flags them abandoned/retargeted, mails escalations, and dispatches rework and
# re-review children — all terminal, all written off the same read. Acting on a
# stranger's PR closes a live bead against someone else's merge AND strands the
# real PR in the anchorless blind spot this very script exists to close
# (review tk-vdlbo P1).
#
# ONE fixture set exercises EVERY mutating arm at once, so the assertions are not
# vacuous: run identically with the pin HONOURED (ID-BASE) each anchor performs
# its mutation, and with the pin IGNORED (ID2) none of them may.
#   id-CLOSE 501 MERGED to main                  -> would CLOSE
#   id-ABAND 502 CLOSED unmerged                 -> would flag abandoned + mail
#   id-RETGT 503 OPEN, base main != integration/foo -> would flag retargeted + mail
#   id-CONF  504 OPEN CONFLICTING/DIRTY          -> would file a rebase child + wake
#   id-GATE  505 OPEN, codex green@old505 stale  -> would file a re-review + wake
reset_identity() {
  : > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/retargeted"; : > "$TMP/mail"
  : > "$TMP/mailbody"; : > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"
  : > "$TMP/wakes"; : > "$TMP/staled"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"
  : > "$TMP/closelog"; : > "$TMP/children"; : > "$TMP/openprs"; : > "$TMP/livex"
  : > "$TMP/dead"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/ghhost"
  # id|pr|merged_target|merge_hold|rebase_hold|check_set|check.codex|pr_url
  printf '%s\n' \
    'id-CLOSE|501|main' \
    'id-ABAND|502|main' \
    'id-RETGT|503|integration/foo' \
    'id-CONF|504|main' \
    'id-GATE|505|main|||codex|green@old505' \
    > "$TMP/anchors"
  printf '%s\n' \
    '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN' \
    '502|CLOSED||false||main|polecat/id-ABAND|head502|UNKNOWN|UNKNOWN' \
    '503|OPEN||false||main|polecat/id-RETGT|head503|MERGEABLE|BLOCKED' \
    '504|OPEN||false||main|polecat/id-CONF|head504|CONFLICTING|DIRTY' \
    '505|OPEN||false||main|polecat/id-GATE|head505|MERGEABLE|BLOCKED' \
    > "$TMP/prs"
}
IDRUN() { bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL"; }

# (ID-BASE) POSITIVE CONTROL. Pin honoured, nothing drifted: every arm fires. A
# guard whose "must not happen" cases pass because the fixture never triggered
# them is worth nothing, so prove the triggers first.
reset_identity
OUTIDB="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed"       && ok "(ID-BASE) control: merged PR closes its anchor" \
                                     || bad "(ID-BASE) control: merged PR must close its anchor (got: $OUTIDB)"
has '^id-ABAND$' "$TMP/abandoned"    && ok "(ID-BASE) control: closed-unmerged PR flags its anchor abandoned" \
                                     || bad "(ID-BASE) control: abandoned flag (got: $OUTIDB)"
has '^id-RETGT$' "$TMP/retargeted"   && ok "(ID-BASE) control: retargeted PR flags its anchor" \
                                     || bad "(ID-BASE) control: retarget flag (got: $OUTIDB)"
grep -q 'Rebase PR#504' "$TMP/created" && ok "(ID-BASE) control: conflicting PR files a rebase child" \
                                       || bad "(ID-BASE) control: rebase child (got: $(cat "$TMP/created"))"
grep -q 'Review PR#505' "$TMP/created" && ok "(ID-BASE) control: stale codex gate files a re-review child" \
                                       || bad "(ID-BASE) control: re-review child (got: $(cat "$TMP/created"))"
eq "$(grep -c . "$TMP/mail")" "2" "(ID-BASE) control: the two escalating arms mail (abandon + retarget)"

# (ID1) DRIFT: gh's default repository is moved to a stranger's. Both reads are
# PINNED to the origin-derived repository, so the drift changes nothing — the right
# PRs answer and every arm still fires. This is what keeps ID2 honest: it proves the
# refusal there comes from the URL comparison, not from the drift alone.
reset_identity
echo 'stranger/repo' > "$TMP/ghdefault"
OUTID1="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && ok "(ID1) gh default drifted to a stranger -> the pinned read still finds OUR PR#501 and closes the anchor" \
  || bad "(ID1) the pinned read must survive a moved gh default (got: $OUTID1)"
printf '%s\n' "$OUTID1" | grep -q '0 foreign-PR identity holds' \
  && ok "(ID1) a honoured pin holds nothing on identity" \
  || bad "(ID1) no identity holds expected (got: $OUTID1)"

# (ID2) IGNOREPIN: the same drift against a gh that does NOT honour `--repo`. Every
# returned PR is a stranger's same-numbered one — and it is otherwise INDISTINGUISH-
# ABLE from ours: same number, same state, same base, same head. Pinning alone is no
# defence; only comparing the returned URL is, which is why the comparison is kept
# after the pin rather than trusted away as a tautology.
reset_identity
echo 'stranger/repo' > "$TMP/ghdefault"
echo 1 > "$TMP/ignorerepo"
OUTID2="$(IDRUN 2>"$TMP/errid2")"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(ID2) a foreign same-numbered PR must NEVER close a local anchor" \
  || ok "(ID2) foreign PR -> anchor NOT closed"
has '^id-ABAND$' "$TMP/abandoned" \
  && bad "(ID2) a foreign closed PR must NEVER flag a local anchor abandoned" \
  || ok "(ID2) foreign PR -> anchor NOT flagged abandoned"
has '^id-RETGT$' "$TMP/retargeted" \
  && bad "(ID2) a foreign PR's base must NEVER retarget-flag a local anchor" \
  || ok "(ID2) foreign PR -> anchor NOT flagged retargeted"
eq "$(grep -c 'Rebase PR#504' "$TMP/created")" "0" \
   "(ID2) foreign PR -> NO rebase child dispatched (no force-push routed off a stranger's conflict)"
eq "$(grep -c 'Review PR#505' "$TMP/created")" "0" \
   "(ID2) foreign PR -> NO stale-gate re-review dispatched"
eq "$(wc -l < "$TMP/gatehead" | tr -d ' ')" "0" \
   "(ID2) foreign PR -> stale_gate_head never armed"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "0" \
   "(ID2) foreign PR -> nothing escalated to the mayor"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" \
   "(ID2) foreign PR -> NO metadata written to any local bead"
eq "$(wc -l < "$TMP/wakes" | tr -d ' ')" "0" "(ID2) foreign PR -> no pool woken"
printf '%s\n' "$OUTID2" | grep -q "answered from 'github.com/stranger/repo', not this checkout's 'github.com/acme/repo'" \
  && ok "(ID2) the refusal names the repository that answered" \
  || bad "(ID2) must name the foreign repository (got: $OUTID2)"
printf '%s\n' "$OUTID2" | grep -q '5 foreign-PR identity holds' \
  && ok "(ID2) the summary counts all five refusals" \
  || bad "(ID2) summary identity-hold count (got: $OUTID2)"

# (ID2b) HOSTDRIFT: GH_HOST points at another GitHub host. `<owner>/<repo>` does not
# name a repository — it names one per host — and `--repo` fills an omitted host from
# GH_HOST, so a HOSTLESS pin would resolve to THAT host's acme/repo: same owner, same
# repo, same number, different pull request. The pin is host-qualified and the
# comparison keeps the host, so the drift is a no-op.
reset_identity
echo 'ghe.example.com' > "$TMP/ghhost"
OUTID2B="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && ok "(ID2b) GH_HOST drifted -> the host-qualified pin still reads OUR PR#501" \
  || bad "(ID2b) a host-qualified pin must survive GH_HOST drift (got: $OUTID2B)"
printf '%s\n' "$OUTID2B" | grep -q '0 foreign-PR identity holds' \
  && ok "(ID2b) host-qualified pin -> no identity holds" \
  || bad "(ID2b) no identity holds expected (got: $OUTID2B)"

# (ID3) URL MISMATCH: the pin is honoured and OUR PR#501 answers, but the anchor's
# OWN recorded pr_url — the identity check-set-heal.sh certified and persisted —
# names a different pull request. One of the two names is wrong and nothing here can
# say which, so the anchor must not be closed off either.
reset_identity
printf '%s\n' \
  'id-CLOSE|501|main|||||https://github.com/acme/OTHER/pull/501' \
  > "$TMP/anchors"
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN' \
  > "$TMP/prs"
OUTID3="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(ID3) an anchor whose pr_url names another PR must NOT be closed" \
  || ok "(ID3) pr_url/live-URL mismatch -> no state recorded"
printf '%s\n' "$OUTID3" | grep -q "anchor id-CLOSE records pr_url 'https://github.com/acme/OTHER/pull/501'" \
  && ok "(ID3) the refusal names both pull requests for an operator" \
  || bad "(ID3) refusal must name the recorded pr_url (got: $OUTID3)"

# (ID3b) the SAME anchor with a matching pr_url still closes. Without this, ID3
# would also pass if the guard simply refused every anchor carrying a pr_url.
reset_identity
printf '%s\n' \
  'id-CLOSE|501|main|||||https://github.com/acme/repo/pull/501/files' \
  > "$TMP/anchors"
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN' \
  > "$TMP/prs"
OUTID3B="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && ok "(ID3b) a matching pr_url still closes — and a '/files' suffix is normalized away, not read as a different PR" \
  || bad "(ID3b) matching pr_url must not be refused (got: $OUTID3B)"

# (ID5) the ANCHORLESS scan reads the same class of answer from `gh pr list`, and
# acts on it: it stamps anchorless_flagged on a LOCAL closed bead and mails an
# escalation about it. An ignored pin there would resolve strangers' pull requests
# onto this rig's beads, one escalation per number that happens to collide.
reset_identity
: > "$TMP/anchors"; : > "$TMP/prs"
printf '%s\n' '601|false|polecat/dead-6|main' > "$TMP/openprs"
printf '%s\n' '601	dead-6	-	pull_request	2026-01-01T00:00:00Z	-' > "$TMP/dead"
OUTID5A="$(IDRUN)"                       # control: ours -> reported + escalated
printf '%s\n' "$OUTID5A" | grep -q 'ANCHORLESS PR#601' \
  && ok "(ID5) control: an open PR of OURS with a closed anchor IS reported anchorless" \
  || bad "(ID5) control: anchorless finding expected (got: $OUTID5A)"
eq "$(grep -c 'anchorless open PR#601' "$TMP/mail")" "1" "(ID5) control: the anchorless finding escalates once"
reset_identity
: > "$TMP/anchors"; : > "$TMP/prs"
printf '%s\n' '601|false|polecat/dead-6|main' > "$TMP/openprs"
printf '%s\n' '601	dead-6	-	pull_request	2026-01-01T00:00:00Z	-' > "$TMP/dead"
echo 'stranger/repo' > "$TMP/ghdefault"; echo 1 > "$TMP/ignorerepo"
OUTID5B="$(IDRUN 2>"$TMP/errid5")"
printf '%s\n' "$OUTID5B" | grep -q 'ANCHORLESS' \
  && bad "(ID5) a foreign repository's open PR must NEVER be reported anchorless against a local bead" \
  || ok "(ID5) foreign PR list -> no anchorless finding"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "0" "(ID5) foreign PR list -> nothing escalated"
eq "$(wc -l < "$TMP/updates" | tr -d ' ')" "0" "(ID5) foreign PR list -> no local bead flagged"
grep -q "did not name 'github.com/acme/repo' and were IGNORED" "$TMP/errid5" \
  && ok "(ID5) the ignored rows are reported, never silently dropped" \
  || bad "(ID5) must warn that the PR list was foreign (err: $(cat "$TMP/errid5"))"

# --- HEAD IDENTITY (review tk-pka2d finding #3). ------------------------------
# Everything above certifies where a pull request LIVES. A PR opened INTO this
# repository FROM a fork lives here too — our host, our owner, our repo, our number,
# one of OUR urls — so it passes every check above while its HEAD is a stranger's.
# That matters more here than almost anywhere, because EVERY arm of this pass writes
# terminal state off the object: it closes anchors as landed, escalates out-of-band
# closes, flags retargets, and dispatches a rebase child whose `fix_branch` is taken
# from the PR's own `headRefName` and force-pushed. Against a fork's head, that is a
# rebase dispatched onto a branch this rig does not own.
#
# reset_identity's fixture triggers ALL FIVE arms (close, abandon, retarget, rebase,
# stale-gate re-review) and ID-BASE above already proved each one fires when the head
# is ours. So the fork cases below only have to change the head — every refusal is
# then measured against a positive control that is known to act.

# (HD1) FORK: every PR is opened from `mallory/repo`'s branch of the same name.
# NOTHING durable may happen: no close, no abandon, no retarget, no rebase child, no
# re-review child, no escalation mail.
reset_identity
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|mallory/repo|true' \
  '502|CLOSED||false||main|polecat/id-ABAND|head502|UNKNOWN|UNKNOWN|mallory/repo|true' \
  '503|OPEN||false||main|polecat/id-RETGT|head503|MERGEABLE|BLOCKED|mallory/repo|true' \
  '504|OPEN||false||main|polecat/id-CONF|head504|CONFLICTING|DIRTY|mallory/repo|true' \
  '505|OPEN||false||main|polecat/id-GATE|head505|MERGEABLE|BLOCKED|mallory/repo|true' \
  > "$TMP/prs"
OUTHD1="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(HD1) a fork's MERGED PR must never close our anchor as landed" \
  || ok "(HD1) fork head -> merged-close refused"
has '^id-ABAND$' "$TMP/abandoned" \
  && bad "(HD1) a fork's CLOSED PR must never abandon our anchor" \
  || ok "(HD1) fork head -> abandoned-close refused"
has '^id-RETGT$' "$TMP/retargeted" \
  && bad "(HD1) a fork's PR must never flag our anchor as retargeted" \
  || ok "(HD1) fork head -> retarget flag refused"
eq "$(grep -c 'Rebase PR#504' "$TMP/created")" "0" \
   "(HD1) fork head -> NO rebase child dispatched (stale-base arm)"
eq "$(grep -c 'Review PR#505' "$TMP/created")" "0" \
   "(HD1) fork head -> NO re-review child dispatched (stale-gate arm)"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "0" "(HD1) fork head -> nothing escalated"
printf '%s\n' "$OUTHD1" | grep -q "PR#501 is opened from FORK 'mallory/repo'" \
  && ok "(HD1) the refusal names the fork and this checkout's repository" \
  || bad "(HD1) refusal must name the fork (got: $OUTHD1)"

# (HD2) SELFCONTRA: the head repository IS ours and isCrossRepository says otherwise.
# A self-contradicting identity is unestablished, not a tie to break.
reset_identity
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|acme/repo|true' \
  > "$TMP/prs"
OUTHD2="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(HD2) a self-contradicting head identity must record no state" \
  || ok "(HD2) headRepository/isCrossRepository disagreement -> no state recorded"
printf '%s\n' "$OUTHD2" | grep -q "PR#501 reports head repository 'acme/repo' (this checkout's own) and cross-repository='true'" \
  && ok "(HD2) the refusal names both halves of the contradiction" \
  || bad "(HD2) refusal must name the contradiction (got: $OUTHD2)"

# (HD3) NOHEAD: gh returns null head repository objects (a deleted head repository, a
# schema shift). "I cannot tell whether this is a fork" must record nothing.
reset_identity
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|-|false' \
  > "$TMP/prs"
OUTHD3="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(HD3) an unreadable head identity must record no state" \
  || ok "(HD3) null headRepository/headRepositoryOwner -> no state recorded"
printf '%s\n' "$OUTHD3" | grep -q "PR#501 head identity is unreadable" \
  && ok "(HD3) the refusal names the unreadable identity" \
  || bad "(HD3) refusal must name the unreadable head (got: $OUTHD3)"

# (HD4) BRANCHMISMATCH: our repository, our head repository, WRONG branch — the
# anchor and the pull request describe different work. The rebase arm is the one that
# makes this concrete: `fix_branch` comes from the PR's headRefName, so an unchecked
# mismatch force-pushes a rebase onto a branch the anchor never recorded.
reset_identity
printf '%s\n' \
  '504|OPEN||false||main|polecat/somebody-else|head504|CONFLICTING|DIRTY|acme/repo|false' \
  > "$TMP/prs"
OUTHD4="$(IDRUN)"
eq "$(grep -c 'Rebase PR#504' "$TMP/created")" "0" \
   "(HD4) head branch != anchor's recorded branch -> NO rebase child dispatched"
printf '%s\n' "$OUTHD4" | grep -q "anchor id-CONF records branch 'polecat/id-CONF' but PR#504 is opened from 'polecat/somebody-else'" \
  && ok "(HD4) the refusal names both branches" \
  || bad "(HD4) refusal must name both branches (got: $OUTHD4)"

# (ID-INV) the observer never merges anything, identity drift or not.
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(ID-INV) the observer reached no merge path across every identity run"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
