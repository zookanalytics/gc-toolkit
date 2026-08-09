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
#   (30)-(31) a DROPPED route write must not arm the head guard; a later pass
#        repairs the stranded review instead of stranding it forever (tk-3xy37).
#   (58)-(59) the same, for the DURABLE half: a batched route write that persists
#        gc.routed_to and silently loses review_pool must not arm either, and the
#        repair path must cover that shape too — a routed review with no durable
#        copy is one claim away from being unroutable, and the repair predicate
#        has to match what the arming predicate rejects or the arm never
#        converges (tk-bdfww).
#   (60)-(61) the same, for the LIVE half pointing at the WRONG pool: review_pool
#        correct but gc.routed_to naming ANOTHER pool with nobody claiming. The
#        arm rejects that split route; the unrouted-only repair predicate skipped
#        it as "already routed", so the pass spun forever — head never armed,
#        route never healed. The repair predicate is now the exact NEGATION of the
#        arming one, so the two cannot disagree (tk-5niup).
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
#   (39)-(45) the superseded-review self-heal (tk-5niup) — the INVERSE of the
#        stale gate: the marker is green AT the live head and it is GITHUB that
#        lags, because a COMMENT review never supersedes the same reviewer's
#        earlier CHANGES_REQUESTED. The PR stays BLOCKED on a dead commit forever
#        and the stale-gate arm cannot reach it (the marker is current):
#   (39) our own superseded CHANGES_REQUESTED -> RETRACTED, signoff_dismissed
#        recorded on the anchor, and NO re-review filed (the gate is green).
#   (40) the OPERATOR's CHANGES_REQUESTED at an equally dead commit -> left
#        standing. Only the author guard saves it; a "is it stale" filter would
#        erase a human veto.
#   (41) our own CHANGES_REQUESTED AT the live head -> left standing (blocked and
#        passed the same commit is a contradiction, not a supersede).
#   (42) reviewDecision=APPROVED -> the arm does not fire.
#   (43) merge_hold=true -> retraction HELD (operator gate), same as the rebase
#        and stale-gate arms.
#   (44) convergence: a healed PR is not re-retracted on the next pass.
#   (45) unresolvable acting login -> nothing retracted (fail-closed: we cannot
#        tell our reviews from a human's).
#   (49) the auto-merge probe FAILS -> nothing retracted (an unreadable probe is
#        indistinguishable from "disarmed" through a `// empty` filter, so it
#        counts as armed)
#   (50) the auto-merge payload is MALFORMED / missing the key -> same
#   (51) auto-merge armed AFTER the up-front probe -> nothing retracted (the
#        re-probe immediately before the irreversible call)
#   (52) signoff_dismissed reports success but is NOT durable -> nothing
#        retracted (the marker is read back, not trusted on its exit status)
#   (53) the ANCHOR is re-read immediately before the dismissal, because the row
#        the arm decided from predates the PR read: merge_hold set mid-pass (53),
#        check.codex re-gated off the live head (53b), the anchor un-parked from
#        the PR (53c) and an unreadable anchor (53d) each hold the retraction
#   (53f-53g) ...and that re-read resolves the anchor's PR the WIDE way, under
#        every key a bead names one with: a fork_pr- or fork_pr_url-keyed anchor
#        is retracted for, where reading pr_number alone left it BLOCKED forever
#        in the one arm that could have un-stranded it
#   (53h-53j) ...and re-asks the REST of the identity against the live PR: a
#        mid-pass retarget (53h), a pr_url moved to another PR (53i) and a branch
#        corrected off this PR (53j) each hold the retraction. None of the three
#        moves the head, so the head re-read cannot see them
#   (58) the tracked-set membership test is in-shell, not a `grep -q` pipeline
#        whose SIGPIPE under pipefail reads a MATCH as a miss — which would report
#        a well-anchored PR as ANCHORLESS and mail the mayor about it
#   (PIN3) every `gh api` call carries --hostname: a repo-pinned REST path is only
#        half pinned, and `acme/repo` names one repository per host
#   (46) native auto-merge ARMED -> nothing retracted. The dismissal would not
#        permit a merge, it would PERFORM one server-side, before merge-skill.sh
#        ever applies the approval requirement this arm records.
#   (47) the superseded review sits on PAGE 2 of the reviews history -> still
#        found and retracted (the read is paginated); unpaginated it is missed and
#        the PR stays stranded.
#   (48) the head MOVES between the reviews listing and the dismissal -> nothing
#        retracted: against a stale head the review may be a FRESH block on the
#        new head, indistinguishable by commit from a superseded one.
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
# Assert that PATTERN (a BRE, same as `has`) appears in a CAPTURED STRING.
#
# NOT `printf '%s\n' "$OUT" | grep -q PATTERN`. This file runs under `set -euo
# pipefail`, and `grep -q` exits at its FIRST match — closing the pipe under a
# `printf` still writing the rest of a large captured output. printf takes
# SIGPIPE, the pipeline reports 141, and the assertion reads FALSE even though
# the line IS present. Whether it fires depends on where the match sits relative
# to the ~64KB pipe buffer, so a suite carrying it fails on output SIZE rather
# than on behavior — a phantom red against correct code, which is exactly how
# merge-skill.test.sh went red at 204/1 while the code under test was fine.
#
# A here-string is a REDIRECT, not a pipeline: bash hands grep a file it reads to
# EOF, no upstream writer exists to be signalled, and the exit status is grep's
# alone. Match semantics are unchanged from the pipelines this replaced. Same
# helper, same reasoning, as merge-skill.test.sh's.
hasin() { grep -q "$2" <<< "$1"; }

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
# The pin the CALLER passed, captured before $FAKE_IGNORE_REPO models a gh that
# throws it away. What the caller asked for and where the call actually landed are
# different questions: the identity guards (ID2) measure the second, the pinning
# assertions (PIN2) measure the FIRST — a script cannot be blamed for a gh that
# ignores `--repo`, but it is entirely responsible for passing it.
PIN_ARG="$RESOLVED"
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

# `gh api` arms, for the superseded-review self-heal (tk-5niup):
#   user                       -> the acting login ($FAKE_SELF_LOGIN)
#   .../pulls/N/reviews        -> $FAKE_REVIEWS rows:
#                                 pr|id|login|state|commit_id|page. `page` models
#                                 GitHub's paging: a row on page >1 is served ONLY
#                                 to a caller that passed --paginate, so an
#                                 unpaginated read sees page 1 and nothing else.
#   -X PUT .../reviews/<id>/dismissals -> RECORDS the retraction (the seam: it
#                                 must fire for exactly the superseded self-reviews)
# --jq FILTER is applied with real jq, as gh does.
if [ "$1" = "api" ]; then
  shift
  METHOD=GET; PATH_ARG=""; PAGINATE=""; JQF=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -X)         METHOD="$2"; shift 2 ;;
      -f)         shift 2 ;;
      -q)         shift 2 ;;
      --jq)       JQF="$2"; shift 2 ;;
      --hostname) APIHOST="$2"; shift 2 ;;
      --paginate) PAGINATE=1; shift ;;
      *)          PATH_ARG="$1"; shift ;;
    esac
  done
  # WHICH HOST, recorded alongside it. A REST path carries `<owner>/<repo>` and no
  # host at all, so `gh api` takes the host as `--hostname` and fills it from
  # $GH_HOST when it is omitted — meaning a repo-pinned path is still only HALF
  # pinned, and `acme/repo` names one repository PER HOST. Recorded separately so
  # the assertion can demand both halves (review tk-5knqi finding #1).
  [ -n "${FAKE_APIHOST:-}" ] && printf '%s\n' "${APIHOST:-<unpinned>}" >> "$FAKE_APIHOST"
  # WHICH REPOSITORY the REST path names. `repos/{owner}/{repo}/...` is resolved by
  # gh from its AMBIENT context, so a path carrying the literal placeholders is
  # recorded here as `{owner}/{repo}` — indistinguishable from any other unpinned
  # call, and exactly what the assertions below refuse. A pinned path records the
  # real `<owner>/<repo>` (review tk-78ty5 finding #3).
  case "$PATH_ARG" in
    repos/*)
      apiwhere="${PATH_ARG#repos/}"
      apiwhere="$(printf '%s' "$apiwhere" | cut -d/ -f1,2)"
      [ -n "${FAKE_APIWHERE:-}" ] && printf '%s\n' "$apiwhere" >> "$FAKE_APIWHERE" ;;
  esac
  case "$PATH_ARG" in
    user) printf '%s\n' "${FAKE_SELF_LOGIN-zook-bot}" ;;
    */dismissals)
      [ "$METHOD" = "PUT" ] || exit 1
      rid="${PATH_ARG%/dismissals}"; rid="${rid##*/}"
      printf '%s\n' "$rid" >> "$FAKE_DISMISSED" ;;
    */reviews*)
      prnum="${PATH_ARG%%\?*}"; prnum="${prnum%/reviews}"; prnum="${prnum##*/}"
      # $FAKE_REVIEWS_FAIL stages a PAGINATED read that DIES PART WAY: `gh
      # --paginate` writes each page as it arrives, so the pages already fetched
      # are still on stdout when the call fails. The output alone is a well-formed
      # history — just not the WHOLE one — so only the exit status can reveal that
      # the tail is missing.
      failnow=""
      if [ -n "${FAKE_REVIEWS_FAIL:-}" ] \
         && printf '%s\n' "$FAKE_REVIEWS_FAIL" | tr ',' '\n' | grep -qxF "$prnum"; then
        failnow=1
      fi
      out=""
      if [ -f "${FAKE_REVIEWS:-}" ]; then
        while IFS='|' read -r rpr rid rlogin rstate rcommit rpage; do
          [ -n "$rpr" ] || continue
          [ "$rpr" = "$prnum" ] || continue
          if [ -n "$failnow" ]; then
            # A read that died after page 1 never delivers page 2.
            [ "${rpage:-1}" = "1" ] || continue
          else
            [ -n "$PAGINATE" ] || [ "${rpage:-1}" = "1" ] || continue
          fi
          obj=$(printf '{"id":%s,"user":{"login":"%s"},"state":"%s","commit_id":"%s"}' "$rid" "$rlogin" "$rstate" "$rcommit")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_REVIEWS"
      fi
      if [ -n "$JQF" ]; then printf '[%s]\n' "$out" | jq -r "$JQF"
      else printf '[%s]\n' "$out"; fi
      [ -z "$failnow" ] || exit 1 ;;
  esac
  exit 0
fi
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    # WHICH REPOSITORY this read was PINNED to (empty when the caller passed no
    # `--repo` at all). Recorded for EVERY `gh pr view` — not just the main PR read —
    # so the assertions below cover the mid-pass head re-read and the auto-merge
    # probe too, both of which were bare `gh pr view "$num"` before review tk-78ty5
    # finding #3.
    [ -n "${FAKE_VIEWWHERE:-}" ] && printf '%s\t%s\n' "$num" "${PIN_ARG:-<unpinned>}" >> "$FAKE_VIEWWHERE"
    fields=""; Q=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --json)   fields="$2"; shift 2 ;;
        -q|--jq)  Q="$2"; shift 2 ;;
        *)        shift ;;
      esac
    done
    # Supported `gh pr view --json` fields (subset; notably NOT `merged`).
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid headRepository headRepositoryOwner isCrossRepository url title body author additions deletions mergeable mergeStateStatus reviewDecision autoMergeRequest "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    # A single-field `--json headRefOid` read is the retraction arm's LIVE-head
    # re-read, taken immediately before each dismissal. $FAKE_HEADMOVE (pr|newoid)
    # makes that one read report a DIFFERENT head than the pass's snapshot —
    # modelling a head that moves mid-pass, where a review the listing called
    # superseded may in fact be a fresh block on the new head.
    # The auto-merge probe is read THREE-valued (armed/disarmed/unknown), so the
    # stub can serve the two shapes the PR fixture cannot express plus the
    # mid-pass arming window. All three are keyed by PR number, so one run can
    # hold an unreadable probe on one anchor while the others retract normally:
    #   $FAKE_AM_FAIL=<pr>       the probe FAILS (non-zero, no output)
    #   $FAKE_AM_MALFORMED=<pr>  a payload without a readable autoMergeRequest key
    #   $FAKE_AM_ARM_AFTER=<pr>  disarmed on the first read, armed from the second
    #                            on — auto-merge armed between the up-front probe
    #                            and the dismissal.
    if [ "$fields" = "autoMergeRequest" ]; then
      [ "${FAKE_AM_FAIL:-}" = "$num" ] && exit 1
      if [ "${FAKE_AM_MALFORMED:-}" = "$num" ]; then
        printf 'not json at all\n'; exit 0
      fi
      if [ "${FAKE_AM_ARM_AFTER:-}" = "$num" ]; then
        a=0
        [ -f "${FAKE_AM_READS:-/dev/null}" ] && a=$(cat "$FAKE_AM_READS")
        a=$((a + 1))
        [ -n "${FAKE_AM_READS:-}" ] && printf '%s' "$a" > "$FAKE_AM_READS"
        if [ "$a" -ge 2 ]; then
          OBJ='{"autoMergeRequest":{"enabledBy":{"login":"johnzook"}}}'
        else
          OBJ='{"autoMergeRequest":null}'
        fi
        if [ -n "$Q" ]; then printf '%s\n' "$OBJ" | jq -r "$Q"; else printf '%s\n' "$OBJ"; fi
        exit 0
      fi
    fi
    if [ "$fields" = "headRefOid" ] && [ -f "${FAKE_HEADMOVE:-}" ]; then
      while IFS='|' read -r mpr moid; do
        [ "$mpr" = "$num" ] || continue
        if [ -n "$Q" ]; then jq -n --arg ho "$moid" '{headRefOid:$ho}' | jq -r "$Q"
        else jq -n --arg ho "$moid" '{headRefOid:$ho}'; fi
        exit 0
      done < "$FAKE_HEADMOVE"
    fi
    # Trailing columns are OPTIONAL and positional: 11-12 carry the review state
    # (reviewDecision, auto-merge enabler) the retraction arm reads, 13-14 the HEAD
    # identity (which repository the PR is opened FROM, and GitHub's own
    # cross-repository flag). All four are OMITTED on every pre-existing row and
    # default to none / THIS repository / not-cross — the shape those cases were
    # written against — so only the cases below vary them. A headrepo of `-` emits
    # NULL objects, which is what gh returns for a deleted head repo (an omitted
    # column cannot mean that: it has to keep meaning "ours").
    while IFS='|' read -r pr state mergedat isdraft oid base head headoid mergeable mergestate revdec automerge headrepo cross; do
      [ "$pr" = "$num" ] || continue
      [ -n "$headrepo" ] || headrepo="acme/repo"
      [ -n "$cross" ]    || cross="false"
      OBJ=$(jq -n --arg s "$state" --arg ma "$mergedat" --argjson d "$isdraft" \
            --arg o "$oid" --arg b "$base" --arg h "$head" --arg ho "$headoid" \
            --arg m "$mergeable" --arg ms "$mergestate" --arg n "$num" --arg rd "$revdec" \
            --arg am "$automerge" --arg rq "$RESOLVED" --arg hrepo "$headrepo" --argjson x "$cross" \
        '{state:$s, mergedAt:(if $ma=="" then null else $ma end), isDraft:$d,
          mergeCommit:(if $o=="" then null else {oid:$o} end), baseRefName:$b,
          headRefName:$h, headRefOid:$ho, mergeable:$m, mergeStateStatus:$ms,
          reviewDecision:$rd,
          autoMergeRequest:(if $am=="" then null else {enabledBy:{login:$am}} end),
          headRepositoryOwner:(if $hrepo=="-" then null else {login:($hrepo | split("/")[0])} end),
          headRepository:(if $hrepo=="-" then null else {name:($hrepo | split("/")[1])} end),
          isCrossRepository:$x,
          url:("https://" + $rq + "/pull/" + $n)}')
      if [ -n "$Q" ]; then printf '%s\n' "$OBJ" | jq -r "$Q"; else printf '%s\n' "$OBJ"; fi
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
        # Columns 9-10 are `fork_pr` / `fork_pr_url`, the OTHER two keys a bead can
        # name a PR with. Omitted everywhere but the fork-keyed case: an anchor
        # wearing them and NO pr_number is exactly the shape the per-anchor loop
        # used to drop (review tk-78ty5 finding #5).
        while IFS='|' read -r id pr target mhold rhold cset cmark prurl forkpr forkprurl; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_ABANDONED" 2>/dev/null && continue
          grep -qx "$id" "$FAKE_RETARGETED" 2>/dev/null && continue
          staled=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_STALED" 2>/dev/null | tail -1)
          gatehead=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_GATEHEAD" 2>/dev/null | tail -1)
          gatenopool=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_GATENOPOOL" 2>/dev/null | tail -1)
          # The consecutive close-failure count and its escalation marker, replayed
          # the same way — this is what makes "N consecutive PASSES" testable at
          # all: pass 2 has to read what pass 1 wrote.
          cfails=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_CLOSEFAILS" 2>/dev/null | tail -1)
          cesc=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_CLOSEESC" 2>/dev/null | tail -1)
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merged_target":"%s","branch":"polecat/%s","stale_base_head":"%s","stale_gate_head":"%s","stale_gate_nopool_head":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s","rebase_hold":"%s","close_failures":"%s","close_escalated":"%s"}}' \
                  "$id" "$pr" "$prurl" "$forkpr" "$forkprurl" "$target" "$id" "$staled" "$gatehead" "$gatenopool" "$cset" "$cmark" "$mhold" "$rhold" "$cfails" "$cesc")
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
    reason=""; cforce=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --reason) reason="$2"; shift 2 ;;
        --force)  cforce=1; shift ;;
        *) shift ;;
      esac
    done
    # Model bd's assignee gate, which is what wedges close-on-land.
    #
    # $FAKE_CLOSE_REFUSE holds `id<TAB>message` rows: closing that id WITHOUT
    # --force fails with that message and records NOTHING, exactly as the real
    # refusal does; WITH --force it succeeds. That asymmetry is what makes "did
    # the override actually fire?" observable rather than inferred.
    #
    # $FAKE_CLOSE_HARDFAIL rows fail for BOTH forms — the refusals the override
    # must never paper over (a genuinely foreign assignee, an open-children hold)
    # and the wedge the consecutive-failure escalation exists for.
    if [ -z "$cforce" ] && [ -s "${FAKE_CLOSE_REFUSE:-/dev/null}" ]; then
      cmsg=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_CLOSE_REFUSE" 2>/dev/null | head -1)
      if [ -n "$cmsg" ]; then printf 'Error: %s\n' "$cmsg" >&2; exit 1; fi
    fi
    if [ -s "${FAKE_CLOSE_HARDFAIL:-/dev/null}" ]; then
      cmsg=$(awk -F'\t' -v i="$id" '$1==i{print $2}' "$FAKE_CLOSE_HARDFAIL" 2>/dev/null | head -1)
      if [ -n "$cmsg" ]; then printf 'Error: %s\n' "$cmsg" >&2; exit 1; fi
    fi
    [ -z "$cforce" ] || printf '%s\n' "$id" >> "$FAKE_FORCED"
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
    # A signoff_dismissed write on FAKE_MARK_NOT_DURABLE's bead reports SUCCESS
    # and stores nothing — the failure an exit-status check cannot see, and the
    # reason that write is read back. Scoped to one bead so the other anchors in
    # the same run still retract normally.
    if [ -n "${FAKE_MARK_NOT_DURABLE:-}" ] && [ "$id" = "$FAKE_MARK_NOT_DURABLE" ] \
       && printf '%s' "$*" | grep -q 'signoff_dismissed='; then
      exit 0
    fi
    # Inject a PARTIAL route write: the batched update carries both halves of the
    # route (gc.routed_to + review_pool), and while FAKE_POOL_FAIL is set only the
    # DURABLE half is dropped — the live gc.routed_to lands and the call reports
    # SUCCESS. That is the shape an exit status cannot see and the single-field
    # read-back could not see either: the route looks verified on the evidence of
    # the field that persisted. Scoped to the one run that sets it.
    upd_args="$*"
    if [ -n "${FAKE_POOL_FAIL:-}" ]; then
      upd_args="${upd_args//--set-metadata review_pool=$FAKE_POOL_FAIL/}"
    fi
    # Inject a SPLIT route: the batched update lands, the DURABLE half is stored as
    # written, but the LIVE half persists pointing at a DIFFERENT pool
    # ($FAKE_ROUTE_WRONG). Models a stale/clobbered gc.routed_to surviving a route
    # write — the shape where the field is populated (so an "is it empty?" repair
    # test skips it) yet names a pool that will never stamp this gate. Scoped to
    # the one run that sets it. Requires FAKE_ROUTE_WRONG_TO to name the wrong pool.
    if [ -n "${FAKE_ROUTE_WRONG:-}" ]; then
      upd_args="${upd_args//--set-metadata gc.routed_to=$FAKE_ROUTE_WRONG/--set-metadata gc.routed_to=${FAKE_ROUTE_WRONG_TO:-rig/rig.wrong-pool}}"
    fi
    # An UNSET is two args (`--unset-metadata close_failures`), so it cannot be
    # matched by the `key=value` loop below. Replay it as an empty value, which is
    # what a later `tail -1` read of the log must see for the anchor to look clean.
    case "$*" in
      *"--unset-metadata close_failures"*)  printf '%s\t\n' "$id" >> "$FAKE_CLOSEFAILS" ;;
    esac
    case "$*" in
      *"--unset-metadata close_escalated"*) printf '%s\t\n' "$id" >> "$FAKE_CLOSEESC" ;;
    esac
    printf '%s\t%s\n' "$id" "$upd_args" >> "$FAKE_UPDATES"
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
        close_failures=*)  printf '%s\t%s\n' "$id" "${a#close_failures=}" >> "$FAKE_CLOSEFAILS" ;;
        close_escalated=*) printf '%s\t%s\n' "$id" "${a#close_escalated=}" >> "$FAKE_CLOSEESC" ;;
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
    # An id in $FAKE_SHOW_FAIL answers with NOTHING — the unreadable-bead case the
    # pre-dismissal re-read must treat as unsafe rather than as "no hold set".
    case " ${FAKE_SHOW_FAIL:-} " in *" $sid "*) exit 0 ;; esac
    slog=$(awk -F'\t' -v i="$sid" '$1==i{print $2}' "$FAKE_UPDATES" 2>/dev/null)
    ab=$(printf '%s\n' "$slog" | grep -o 'anchor_bead=[^ ]*' | tail -1 | sed 's/anchor_bead=//')
    tk=$(printf '%s\n' "$slog" | grep -o 'task_kind=[^ ]*' | tail -1 | sed 's/task_kind=//')
    rt=$(printf '%s\n' "$slog" | grep -o 'gc.routed_to=[^ ]*' | tail -1 | sed 's/gc.routed_to=//')
    # review_pool — the DURABLE half of the route, replayed the same way. It is
    # read back alongside gc.routed_to before the stale-gate head guard is armed
    # (arm_stale_gate, tk-bdfww): the two go out in ONE batched write, so a write
    # that persists only the live half must be visible here as review_pool="" for
    # that partial-write case to be testable at all. A write the shim stripped
    # (FAKE_POOL_FAIL) never lands in the log, so it reads back empty.
    rp=$(printf '%s\n' "$slog" | grep -o 'review_pool=[^ ]*' | tail -1 | sed 's/review_pool=//')
    # signoff_dismissed joins the replay for the retraction arm's read-back ("is
    # the pairing marker really recorded before I drop the GitHub block?"). A
    # write the shim dropped never reaches the log, so it reads back empty here —
    # exactly what a non-durable ledger write looks like to that guard.
    sd=$(printf '%s\n' "$slog" | grep -o 'signoff_dismissed=[^ ]*' | tail -1 | sed 's/signoff_dismissed=//')
    # A GATING ANCHOR also answers with its live gating state — status, pr_number,
    # merge_result, check.codex, merge_hold — because the retraction arm re-reads
    # the anchor immediately before the irreversible dismissal and requires it to
    # still be the anchor it decided about. $FAKE_ANCHORS_FRESH OVERRIDES
    # $FAKE_ANCHORS for these reads only: that is the mid-pass write seam (the
    # enumeration snapshot and the live bead disagreeing), with two extra columns
    # for status and merge_result, where `-` means the field is EMPTY on the live
    # bead. A non-anchor id (a review bead) matches no row and answers as before.
    #
    # Three MORE show-only columns follow status/merge_result, because the guard
    # re-asks the anchor's whole identity, not just its gating state:
    #   10 pr_key   which key the anchor names its PR with — pr_number (default),
    #               fork_pr, or fork_pr_url. The fork-sync flow stamps the latter
    #               two and NO pr_number, and a guard that reads pr_number alone
    #               cannot tell that anchor apart from one that moved off this PR.
    #   11 pr_url   the anchor's recorded url ("" = records none)
    #   12 branch   the anchor's recorded branch (default polecat/<id>, which is
    #               what the PR fixtures are opened from, so the matching case is
    #               exercised too)
    # merged_target needs no new column: it is column 3, which the enumeration
    # already reads as the anchor's target.
    s_status="open"; s_result="pull_request"; s_pr=""; s_mark=""; s_hold=""; s_found=""
    s_key="pr_number"; s_prurl=""; s_branch=""; s_target=""
    for asrc in "${FAKE_ANCHORS_FRESH:-}" "$FAKE_ANCHORS"; do
      [ -n "$asrc" ] && [ -f "$asrc" ] || continue
      [ -n "$s_found" ] && break
      while IFS='|' read -r aid apr atarget ahold arhold acset amark astatus aresult akey aprurl abranch; do
        [ "$aid" = "$sid" ] || continue
        s_pr="$apr"; s_mark="$amark"; s_hold="$ahold"; s_found=1
        [ -n "$astatus" ] && s_status="$astatus"
        [ -n "$aresult" ] && s_result="$aresult"
        [ "$s_status" = "-" ] && s_status=""
        [ "$s_result" = "-" ] && s_result=""
        s_target="$atarget"; [ "$s_target" = "-" ] && s_target=""
        [ -n "$akey" ] && [ "$akey" != "-" ] && s_key="$akey"
        s_prurl="$aprurl"; [ "$s_prurl" = "-" ] && s_prurl=""
        s_branch="$abranch"
        [ -n "$s_branch" ] || s_branch="polecat/$aid"
        [ "$s_branch" = "-" ] && s_branch=""
        break
      done < "$asrc"
    done
    # The PR is named under s_key ALONE: a fork-keyed anchor carries no pr_number
    # at all, which is the whole shape under test.
    prkey_json=""
    if [ -n "$s_pr" ]; then
      case "$s_key" in
        fork_pr_url) prkey_json=$(printf '"fork_pr_url":"https://github.com/acme/repo/pull/%s"' "$s_pr") ;;
        *)           prkey_json=$(printf '"%s":"%s"' "$s_key" "$s_pr") ;;
      esac
    fi
    printf '[{"id":"%s","status":"%s","metadata":{"anchor_bead":"%s","task_kind":"%s","gc.routed_to":"%s","review_pool":"%s","signoff_dismissed":"%s",%s"merged_target":"%s","pr_url":"%s","branch":"%s","merge_result":"%s","check.codex":"%s","merge_hold":"%s"}}]\n' \
      "$sid" "$s_status" "$ab" "$tk" "$rt" "$rp" "$sd" \
      "${prkey_json:+$prkey_json,}" "$s_target" "$s_prurl" "$s_branch" "$s_result" "$s_mark" "$s_hold" ;;
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
       FAKE_REVIEWS="$TMP/reviews" FAKE_DISMISSED="$TMP/dismissed" \
       FAKE_HEADMOVE="$TMP/headmove" FAKE_AM_READS="$TMP/amreads" \
       FAKE_OPENPRS="$TMP/openprs" FAKE_DEAD="$TMP/dead" FAKE_MAILBODY="$TMP/mailbody" \
       FAKE_LIVEX="$TMP/livex" FAKE_BODIES="$TMP/bodies" \
       FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_GH_DEFAULT="$TMP/ghdefault" FAKE_IGNORE_REPO="$TMP/ignorerepo" \
       FAKE_GH_HOST="$TMP/ghhost" \
       FAKE_APIWHERE="$TMP/apiwhere" FAKE_VIEWWHERE="$TMP/viewwhere" \
       FAKE_APIHOST="$TMP/apihost" \
       FAKE_CLOSE_REFUSE="$TMP/closerefuse" FAKE_CLOSE_HARDFAIL="$TMP/closehard" \
       FAKE_FORCED="$TMP/forced" FAKE_CLOSEFAILS="$TMP/closefails" \
       FAKE_CLOSEESC="$TMP/closeesc"
mkdir -p "$TMP/bodies"
# The close gate is INERT by default: every scenario above this point closes
# cleanly, and only the identity-encoding runs at the end arm these.
: > "$TMP/closerefuse"; : > "$TMP/closehard"; : > "$TMP/forced"
: > "$TMP/closefails"; : > "$TMP/closeesc"
: > "$TMP/repofail"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/ghhost"
# WHERE each GitHub call went, recorded for every run in the file: `gh api` by the
# repository its REST path names, `gh pr view` by the repository the call resolved
# in. The assertions that read them are at the end (PIN1/PIN2).
: > "$TMP/apiwhere"; : > "$TMP/viewwhere"; : > "$TMP/apihost"

# No PR reviews, no dismissals, and a head that never moves by default: the
# superseded-review arm is inert for every scenario except Run 13, which supplies
# its own fixtures.
: > "$TMP/reviews"; : > "$TMP/dismissed"; : > "$TMP/headmove"

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
hasin "$J_UPDATES" 'stale_base_head=head210' \
  && ok "(9) anchor marked stale_base_head at the detected head" \
  || bad "(9) anchor marked stale_base_head at the detected head (got: $J_UPDATES)"
hasin "$J_UPDATES" 'merge_result=' \
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
hasin "$OUT1" "bead-N — PR#214 conflicted (stale base) but merge_hold set" \
  && ok "(16) merge_hold hold is announced, naming the operator gate" \
  || bad "(16) merge_hold hold reason (got: $OUT1)"

# (17) rebase_hold on the anchor: the narrower "do not rebase this branch".
eq "$(grep -c 'Rebase PR#215' "$TMP/created")" "0" \
   "(17) anchor rebase_hold -> NO rebase child filed"
hasin "$OUT1" "bead-O — PR#215 conflicted (stale base) but rebase_hold set" \
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
hasin "$OUT1" "child-P holds branch 'polecat/bead-P' with rebase_hold" \
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
hasin "$OUT1" 'ANCHORLESS PR#301' \
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
hasin "$OUT1" 'ANCHORLESS PR#303 (draft)' \
  && ok "(12) anchorless draft PR reported and labelled as a draft" \
  || bad "(12) anchorless draft PR reported and labelled (got: $OUT1)"
# Already-escalated: keep reporting (still stranded), do not re-mail.
hasin "$OUT1" 'ANCHORLESS PR#304' \
  && ok "(12) already-flagged anchorless PR still reported each pass" \
  || bad "(12) already-flagged anchorless PR still reported each pass"
eq "$(grep -c 'anchorless open PR#304' "$TMP/mail")" "0" \
   "(12) already-flagged anchorless PR is not re-escalated"

# (13) a PR any LIVE bead references is tracked by something -> not a finding.
hasin "$OUT1" 'ANCHORLESS PR#203' \
  && bad "(13) PR tracked by a live gating anchor must not be flagged" \
  || ok "(13) PR tracked by a live gating anchor is not flagged"
hasin "$OUT1" 'ANCHORLESS PR#211' \
  && bad "(13) PR tracked by a live rework child must not be flagged" \
  || ok "(13) PR tracked by a live rework child is not flagged"
hasin "$OUT1" 'ANCHORLESS PR#77' \
  && ok "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7" \
  || bad "(13) tracked-set match is exact — PR#77 not satisfied by tracked PR#7 (got: $OUT1)"

# (14) no bead in any state: report it, but never mail — there is nothing
# durable to bound the escalation, so mailing would repeat every wake forever.
hasin "$OUT1" 'ANCHORLESS PR#302' \
  && ok "(14) open PR with no bead in any state is reported" \
  || bad "(14) open PR with no bead in any state is reported (got: $OUT1)"
eq "$(grep -c 'anchorless open PR#302' "$TMP/mail")" "0" \
   "(14) unboundable (no-bead) finding is reported but never escalated"

hasin "$OUT1" '8 anchorless open PRs' \
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
hasin "$OUT1" 'ANCHORLESS PR#401' \
  && bad "(33) PR named by a live fork_pr-keyed bead must not be reported anchorless" \
  || ok "(33) fork_pr-keyed live bead makes its PR tracked (no false anchorless)"
hasin "$OUT1" 'ANCHORLESS PR#402' \
  && bad "(33) PR named by a live fork_pr_url-keyed bead must not be reported anchorless" \
  || ok "(33) fork_pr_url-keyed live bead makes its PR tracked (number parsed from the URL)"
eq "$(grep -c 'anchorless open PR#401' "$TMP/mail")" "0" \
   "(33) fork_pr-keyed tracked PR is never escalated"

# (34) ...but tracked is NOT owned. Widening the key set alone would convert
# PR#401 from a noisy false finding into SILENCE, which is the exact downside the
# cheap alternative (hand-stamping pr_number) was rejected for. A live bead with
# no merge_result, no branch, no target and no merge_strategy tracks the PR
# without owning it: nothing will land it either way, so it keeps its own line.
hasin "$OUT1" 'UNOWNED PR#401' \
  && ok "(34) tracked-but-ungated PR reported as UNOWNED, not silently dropped" \
  || bad "(34) tracked-but-ungated PR reported as UNOWNED (got: $OUT1)"
hasin "$OUT1" 'UNOWNED PR#401.*live-fork (operator)' \
  && ok "(34) UNOWNED line names the live bead and its assignee" \
  || bad "(34) UNOWNED line names the bead + assignee (got: $(printf '%s\n' "$OUT1" | grep 'PR#401' || true))"
hasin "$OUT1" 'UNOWNED PR#402' \
  && ok "(34) fork_pr_url-keyed ungated PR also reported as UNOWNED" \
  || bad "(34) fork_pr_url-keyed ungated PR reported as UNOWNED (got: $OUT1)"
# The rule is about gating metadata, not about the fork keys: a plain
# pr_number-keyed bead with nothing to act on is just as unowned.
hasin "$OUT1" 'UNOWNED PR#404' \
  && ok "(34) pr_number-keyed bead with no gating metadata is UNOWNED too (not a fork-only rule)" \
  || bad "(34) ungated pr_number-keyed bead is UNOWNED (got: $OUT1)"
# Non-escalating: the naming bead is LIVE, so this is a routing gap an operator
# can close, not a stranded PR. Mailing it would repeat every wake.
eq "$(grep -c 'PR#401' "$TMP/mail")" "0" \
   "(34) UNOWNED is reported but never escalated (a live bead still names it)"

# (35) A bead that DOES carry gating metadata is owned, whatever key it used to
# name the PR — so it stays silent. Without this the UNOWNED arm would just be
# the anchorless arm under a new name.
hasin "$OUT1" 'PR#403' \
  && bad "(35) fork_pr-keyed bead WITH gating metadata must be silent (owned)" \
  || ok "(35) fork_pr-keyed bead with gating metadata -> owned, no line at all"
hasin "$OUT1" '3 unowned open PRs' \
  && ok "(34) run 1 summary reports 3 unowned open PRs" \
  || bad "(34) run 1 summary unowned count (got: $OUT1)"

# (36) The CLOSED-bead resolution is widened the same way. dead-5 named PR#405
# only as fork_pr: keyed on pr_number alone it resolves to nothing, the arm falls
# into the "no bead in any state" branch — which by design does NOT escalate —
# and a genuinely stranded PR is silently downgraded to a log line forever.
hasin "$OUT1" 'ANCHORLESS PR#405' \
  && ok "(36) open PR whose closed anchor is fork_pr-keyed is still anchorless" \
  || bad "(36) fork_pr-keyed closed anchor -> anchorless (got: $OUT1)"
hasin "$OUT1" 'ANCHORLESS PR#405.*anchor dead-5 is CLOSED' \
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
hasin "$OUT1" 'ANCHORLESS PR#406' \
  && ok "(37) a foreign same-numbered LIVE bead does not track our PR#406 into silence" \
  || bad "(37) PR#406 must still be reported anchorless (got: $(printf '%s\n' "$OUT1" | grep 'PR#406' || echo '<no line at all>'))"
hasin "$OUT1" 'UNOWNED PR#406' \
  && bad "(37) a foreign bead must not make our PR 'tracked but unowned' either" \
  || ok "(37) the foreign bead does not downgrade the finding to UNOWNED"
hasin "$OUT1" 'ANCHORLESS PR#406.*anchor dead-406 is CLOSED' \
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
hasin "$OUT1" 'ANCHORLESS PR#407' \
  && ok "(38) PR#407 is still reported anchorless" \
  || bad "(38) PR#407 must be reported anchorless (got: $OUT1)"
hasin "$OUT1" 'ANCHORLESS PR#407.*no bead in any state references it' \
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
hasin "$OUT1" "1 closed, 1 abandoned" \
  && ok "run 1 summary reports 1 closed, 1 abandoned" \
  || bad "run 1 summary (got: $OUT1)"
hasin "$OUT1" "2 retargeted" \
  && ok "run 1 summary reports 2 retargeted" \
  || bad "run 1 summary retargeted count (got: $OUT1)"
grep -qi "auto-merge" <<< "$OUT1" \
  && bad "run 1 summary must not mention auto-merge (it was retired)" \
  || ok "run 1 summary makes no mention of auto-merge"

# --- Regression guard (field shape): only gh-supported --json fields. ---------
# The stub models real gh: it REJECTS `merged` (the field the original bug
# requested) and ACCEPTS the script's real field set. The disposition matrix
# above already exercises this end-to-end (the script would skip every anchor on
# a rejected field); these direct probes document the contract so a reintroduced
# `merged` fails loudly with an obvious message.
# FAKE_VIEWWHERE is cleared for these two: they are the TEST calling the stub
# directly to document its contract, not the script making a call. Recording them
# would put an <unpinned> row in the ledger that PIN2 reads and blame the script for
# a probe it never made.
FAKE_VIEWWHERE='' gh pr view 201 --json merged >/dev/null 2>&1 \
  && bad "(6) gh stub must REJECT unsupported field 'merged' (models real gh)" \
  || ok "(6) unsupported --json field 'merged' rejected (guards the field-shape bug)"
FAKE_VIEWWHERE='' gh pr view 201 --json state,mergedAt,mergeCommit,isDraft,baseRefName >/dev/null 2>&1 \
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
hasin "$M_UPDATES" 'gc.routed_to=human' \
  && ok "(9) no fix pool -> anchor routed to human" \
  || bad "(9) no fix pool -> anchor routed to human (got: $M_UPDATES)"

# --- Run 5: zero gating anchors must NOT short-circuit the anchorless scan. ---
# Before the anchorless arm this pass returned early on an empty gating set. That
# is the worst possible place to go blind: zero live anchors WITH open PRs is
# precisely the stranded state the scan exists to surface.
: > "$TMP/anchors"
printf '305|false|polecat/dead-5|main\n' > "$TMP/openprs"
OUT5="$(bash "$SCRIPT" --fix-pool "$FIX_POOL")"
hasin "$OUT5" 'no gating anchors' \
  && ok "(15) empty gating set still reported" \
  || bad "(15) empty gating set still reported (got: $OUT5)"
hasin "$OUT5" 'ANCHORLESS PR#305' \
  && ok "(15) anchorless scan runs even with zero gating anchors" \
  || bad "(15) anchorless scan runs even with zero gating anchors (got: $OUT5)"

# --- Run 6: fail CLOSED when the live-bead read fails. -----------------------
# An empty ledger read is indistinguishable from "no bead tracks anything". If
# the scan trusted it, EVERY open PR would be flagged and escalated at once — a
# mail storm out of a transient Dolt blip. It must report nothing instead.
MAIL_BEFORE6=$(wc -l < "$TMP/mail" | tr -d ' ')
printf '306|false|polecat/dead-6|main\n' > "$TMP/openprs"
OUT6="$(FAKE_LIVE_FAIL=1 bash "$SCRIPT" --fix-pool "$FIX_POOL" 2>/dev/null)"
hasin "$OUT6" 'ANCHORLESS' \
  && bad "(14) failed live-bead read must not flag anything (fail closed)" \
  || ok "(14) failed live-bead read flags nothing (fail closed, no mail storm)"
eq "$(wc -l < "$TMP/mail" | tr -d ' ')" "$MAIL_BEFORE6" \
   "(14) failed live-bead read escalates nothing"
hasin "$OUT6" '0 anchorless open PRs' \
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
hasin "$OUT7" '0 stale-base rebases routed' \
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
hasin "$T_UPD" 'stale_gate_head=head220' \
  && ok "(24) anchor marked stale_gate_head at the live head" \
  || bad "(24) anchor marked stale_gate_head (got: $T_UPD)"
hasin "$T_UPD" 'merge_result=' \
  && bad "(24) anchor must KEEP merge_result=pull_request (stays gating)" \
  || ok "(24) anchor keeps merge_result=pull_request (unlike retarget/abandon)"
has '^bead-T$' "$TMP/closed" && bad "(24) stale-gate anchor must NOT be closed" \
                             || ok "(24) stale-gate anchor not closed"
# The remedy is a REAL review, NEVER a hand-stamped green (that certifies an
# unreviewed commit — the tk-4na1b failure mode).
hasin "$T_UPD" 'check.codex=green' \
  && bad "(24) must NEVER hand-stamp check.codex green (certifies an unreviewed commit)" \
  || ok "(24) never hand-stamps check.codex green (dispatches a real review)"

# (25) current-green: marker == live head -> not stale, no re-review.
eq "$(grep -c 'Review PR#221' "$TMP/created")" "0" \
   "(25) codex green AT the live head -> no re-review (not stale)"
# (26) an open review child already re-raises the gate -> no twin.
eq "$(grep -c 'Review PR#222' "$TMP/created")" "0" \
   "(26) stale gate but a review child already open -> no second re-review"

hasin "$OUT8" '1 stale-gate re-reviews routed' \
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
hasin "$W_UPD" 'check.codex=green' \
  && bad "(28) no pool must NEVER hand-stamp check.codex green" \
  || ok "(28) no pool never hand-stamps check.codex green (holds instead)"
# The no-pool hold stamps a DISTINCT marker (stale_gate_nopool_head), NOT
# stale_gate_head. stale_gate_head means "a review was dispatched at this head" and
# the one-per-head guard skips it forever; stamping it on a no-pool pass would
# suppress the dispatch even after a review pool is configured (tk-v2b0k finding #1,
# tested in Run 11 below). The no-pool marker bounds the busy-loop without blocking
# that later recovery.
hasin "$W_UPD" 'stale_gate_nopool_head=head223' \
  && ok "(28) no pool -> DISTINCT no-pool head guard stamped so it does not busy-loop" \
  || bad "(28) no pool -> stale_gate_nopool_head stamped (got: $W_UPD)"
hasin "$W_UPD" 'stale_gate_head=head223' \
  && bad "(28) no pool must NOT stamp stale_gate_head (would suppress a later configured dispatch)" \
  || ok "(28) no pool -> stale_gate_head NOT stamped (reserved for a real dispatch)"
hasin "$OUT10" '1 stale-gate re-reviews held' \
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
hasin "$W_UPD2" 'stale_gate_head=head223' \
  && ok "(29) recovered dispatch stamps the real stale_gate_head guard at the live head" \
  || bad "(29) recovered dispatch stamps stale_gate_head=head223 (got: $W_UPD2)"
hasin "$W_UPD2" 'check.codex=green' \
  && bad "(29) recovered dispatch must NEVER hand-stamp check.codex green" \
  || ok "(29) recovered dispatch never hand-stamps green (files a real review)"
hasin "$OUT11" '1 stale-gate re-reviews routed' \
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
hasin "$OUT12A" '0 stale-gate re-reviews routed' \
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
hasin "$OUT12B" 'stale-gate repair' \
  && ok "(31) repair pass logs the stale-gate route repair" \
  || bad "(31) repair pass must log the repair (got: $OUT12B)"
hasin "$OUT12B" '1 stale-gate re-reviews routed' \
  && ok "(31) repair pass -> summary reports the recovered re-review routed" \
  || bad "(31) run 12B summary stale-gate routed count (got: $OUT12B)"
grep -qx "$REVIEW_POOL" "$TMP/wakes" \
  && ok "(31) repair pass wakes the review pool" \
  || bad "(31) repair pass wakes the review pool"

# --- Run 12b: the DURABLE half of the route is what a dropped write loses last,
# and it must not be assumed from the live half (tk-bdfww). -------------------
# gc.routed_to and review_pool go out in ONE batched update. Reading back only
# gc.routed_to declares the route durable on the evidence of the field that is
# NOT the durable one: a write that persists the live half and silently drops
# review_pool passes that check, so the arm stamps stale_gate_head, the
# one-per-head guard closes behind it, and the review is left with no durable
# route copy. The damage lands one step later — a codex polecat claims the
# review, which CONSUMES gc.routed_to, and a signoff that ends WITHOUT stamping
# the gate then has to put the review back in a pool with nothing left to say
# which pool that was (template-fragments/polecat-non-impl-done.template.md).
# The bead is released open, unassigned and unrouted — offered to nobody, gate
# owed forever — and the head is already marked dispatched, so no later pass
# re-enters. Same terminal strand as tk-3xy37, reached through the other field.
printf '%s\n' 'bead-XP|225|main|||codex|green@old225' > "$TMP/anchors"
printf '%s\n' '225|OPEN||false||main|polecat/bead-XP|head225|MERGEABLE|BLOCKED' > "$TMP/prs"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/children"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"

# Pass A: the live half lands, the durable half is dropped, the call SUCCEEDS.
OUT12C="$(FAKE_POOL_FAIL="$REVIEW_POOL" bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#225' "$TMP/created")" "1" \
   "(58) dropped review_pool -> the re-review bead is still filed"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && ok "(58) the LIVE half of the route did persist (only the durable copy was lost)" \
  || bad "(58) fixture must persist gc.routed_to (got: $(cat "$TMP/updates"))"
grep -q "review_pool=$REVIEW_POOL" "$TMP/updates" \
  && bad "(58) fixture must drop review_pool (the partial write being modeled)" \
  || ok "(58) the DURABLE half was dropped in flight"
grep -q 'stale_gate_head=head225' "$TMP/updates" \
  && bad "(58) must NOT arm stale_gate_head when review_pool did not persist (a claim then makes the review unroutable forever)" \
  || ok "(58) head guard NOT armed on a lost durable route copy"
hasin "$OUT12C" '0 stale-gate re-reviews routed' \
  && ok "(58) dropped review_pool -> summary counts routed=0, not a false dispatch" \
  || bad "(58) run 12b pass A summary must report 0 routed (got: $OUT12C)"

# Pass B: the loss clears. The repair path must ALSO cover this shape — the bead
# is ROUTED, so the unrouted-only repair predicate skipped it at the twin guard
# while the arm kept refusing to arm: the pass would spin forever, never healing
# review_pool and never arming the head. Repair predicate and arming predicate
# have to agree.
OUT12D="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#225' "$TMP/created")" "1" \
   "(59) repair pass reuses the SAME review -> no twin re-review bead"
grep -q "review_pool=$REVIEW_POOL" "$TMP/updates" \
  && ok "(59) repair pass restores the durable review_pool copy" \
  || bad "(59) repair pass must restore review_pool (got: $(cat "$TMP/updates"))"
grep -q 'stale_gate_head=head225' "$TMP/updates" \
  && ok "(59) repair pass NOW arms stale_gate_head at the live head" \
  || bad "(59) repair pass must arm stale_gate_head=head225"
hasin "$OUT12D" 'stale-gate repair' \
  && ok "(59) repair pass logs the stale-gate route repair" \
  || bad "(59) repair pass must log the repair (got: $OUT12D)"
hasin "$OUT12D" '1 stale-gate re-reviews routed' \
  && ok "(59) repair pass -> summary reports the recovered re-review routed" \
  || bad "(59) run 12b pass B summary stale-gate routed count (got: $OUT12D)"

# --- Run 12c: the SPLIT route — the live half persists pointing at the WRONG
# pool (tk-5niup). ------------------------------------------------------------
# arm_stale_gate refuses to arm unless review_pool matches AND the review is
# either claimed or LIVE-routed to that same pool. The repair predicate only
# asked whether gc.routed_to was EMPTY, so it did not cover the shape where the
# field is populated with a DIFFERENT pool and nobody has claimed the bead — the
# arm rejects it, the twin guard skips it as "already routed", and the two
# disagree forever: the head is never armed, the route is never healed, and the
# merge sits held behind a re-review the codex pool is never offered. Same
# terminal spin as run 12b, reached through the live half instead of the durable
# one. The repair predicate has to be the exact negation of the arming one.
printf '%s\n' 'bead-XW|226|main|||codex|green@old226' > "$TMP/anchors"
printf '%s\n' '226|OPEN||false||main|polecat/bead-XW|head226|MERGEABLE|BLOCKED' > "$TMP/prs"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/children"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"

# Pass A: the durable half lands, the live half persists as a DIFFERENT pool.
OUT12E="$(FAKE_ROUTE_WRONG="$REVIEW_POOL" FAKE_ROUTE_WRONG_TO='rig/rig.wrong-pool' \
  bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#226' "$TMP/created")" "1" \
   "(60) split route -> the re-review bead is still filed"
grep -q "review_pool=$REVIEW_POOL" "$TMP/updates" \
  && ok "(60) the DURABLE half persisted (only the live route is wrong)" \
  || bad "(60) fixture must persist review_pool (got: $(cat "$TMP/updates"))"
grep -q 'gc.routed_to=rig/rig.wrong-pool' "$TMP/updates" \
  && ok "(60) the LIVE half persisted pointing at another pool (the split being modeled)" \
  || bad "(60) fixture must persist the wrong live route (got: $(cat "$TMP/updates"))"
grep -q 'stale_gate_head=head226' "$TMP/updates" \
  && bad "(60) must NOT arm stale_gate_head on a route offered to the wrong pool" \
  || ok "(60) head guard NOT armed on a split route"
hasin "$OUT12E" '0 stale-gate re-reviews routed' \
  && ok "(60) split route -> summary counts routed=0, not a false dispatch" \
  || bad "(60) run 12c pass A summary must report 0 routed (got: $OUT12E)"

# Pass B: the injection clears. The repair path must cover this shape too — the
# bead IS routed (just not to us) and unclaimed, so the unrouted-only predicate
# skipped it at the twin guard while the arm kept refusing: the spin run 12b
# closed for the durable half, reached through the live one.
OUT12F="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL")"
eq "$(grep -c 'Review PR#226' "$TMP/created")" "1" \
   "(61) repair pass reuses the SAME review -> no twin re-review bead"
grep -q "gc.routed_to=$REVIEW_POOL" "$TMP/updates" \
  && ok "(61) repair pass re-routes the misrouted re-review to the review pool" \
  || bad "(61) repair pass must re-route a misrouted review (got: $(cat "$TMP/updates"))"
grep -q 'stale_gate_head=head226' "$TMP/updates" \
  && ok "(61) repair pass NOW arms stale_gate_head at the live head" \
  || bad "(61) repair pass must arm stale_gate_head=head226"
hasin "$OUT12F" 'stale-gate repair' \
  && ok "(61) repair pass logs the stale-gate route repair" \
  || bad "(61) repair pass must log the repair (got: $OUT12F)"
hasin "$OUT12F" '1 stale-gate re-reviews routed' \
  && ok "(61) repair pass -> summary reports the recovered re-review routed" \
  || bad "(61) run 12c pass B summary stale-gate routed count (got: $OUT12F)"

# --- Run 13: superseded-review self-heal (tk-5niup). --------------------------
# The INVERSE of the stale-gate arm: the bead marker is green AT the live head,
# and it is GITHUB that lags — our own CHANGES_REQUESTED from an earlier round is
# still standing, pinned to a commit that no longer exists. A COMMENT review does
# not supersede the same reviewer's earlier CHANGES_REQUESTED, so reviewDecision
# stays CHANGES_REQUESTED and mergeStateStatus stays BLOCKED forever while the
# gate reads green; merge-skill.sh requires CLEAN, so the PR strands with NO
# in-band path out (the stale-gate arm cannot fire — the marker is current).
# anchors: id|pr|target|merge_hold|rebase_hold|check_set|check.codex-marker
#   bead-W 240 green@head240, OUR stale CHANGES_REQUESTED  -> RETRACTED + marker
#   bead-X 241 green@head241, the OPERATOR's CHANGES_REQUESTED -> left standing
#   bead-Y 242 green@head242, OUR CHANGES_REQUESTED AT the live head -> stands
#   bead-Z2 243 green@head243, reviewDecision APPROVED      -> nothing to do
#   bead-W2 244 green@head244, our stale CR BUT merge_hold  -> operator gate wins
#   bead-AM 245 green@head245, our stale CR BUT native auto-merge ARMED -> HELD
#   bead-P2 246 green@head246, our stale CR only on reviews PAGE 2 -> RETRACTED
#   bead-HM 247 green@head247, our stale CR but the head MOVES mid-pass -> HELD
printf '%s\n' \
  'bead-W|240|main|||codex|green@head240' \
  'bead-X|241|main|||codex|green@head241' \
  'bead-Y|242|main|||codex|green@head242' \
  'bead-Z2|243|main|||codex|green@head243' \
  'bead-W2|244|main|true||codex|green@head244' \
  'bead-AM|245|main|||codex|green@head245' \
  'bead-P2|246|main|||codex|green@head246' \
  'bead-HM|247|main|||codex|green@head247' \
  'bead-AF|248|main|||codex|green@head248' \
  'bead-AB|249|main|||codex|green@head249' \
  'bead-AA|250|main|||codex|green@head250' \
  'bead-ND|251|main|||codex|green@head251' \
  'bead-MH|252|main|||codex|green@head252' \
  'bead-GC|253|main|||codex|green@head253' \
  'bead-UP|254|main|||codex|green@head254' \
  'bead-SF|255|main|||codex|green@head255' \
  'bead-RF|256|main|||codex|green@head256' \
  'bead-FK||main|||codex|green@head257||257|' \
  'bead-FU||main|||codex|green@head258|||https://github.com/acme/repo/pull/258' \
  'bead-RT|259|main|||codex|green@head259' \
  'bead-PU|260|main|||codex|green@head260' \
  'bead-BR|261|main|||codex|green@head261' \
  > "$TMP/anchors"
# The anchor as a LATER `gc bd show` reads it — the mid-pass write the ROWS
# snapshot missed. Same columns plus status (8) and merge_result (9), where `-`
# means the field is EMPTY on the live bead. Only listed anchors differ.
#   bead-MH 252 an operator sets merge_hold after the pass enumerated
#   bead-GC 253 a re-gate moves check.codex off the live head
#   bead-UP 254 the anchor is un-parked from its PR (merge_result cleared)
#   bead-FK 257 keyed by fork_pr ONLY — no pr_number anywhere on the bead
#   bead-FU 258 keyed by fork_pr_url ONLY
#   bead-RT 259 an operator retargets the anchor off the PR's base mid-pass
#   bead-PU 260 the anchor's pr_url is repaired to name a DIFFERENT PR mid-pass
#   bead-BR 261 the anchor's branch is corrected off this PR's head ref mid-pass
printf '%s\n' \
  'bead-MH|252|main|true||codex|green@head252' \
  'bead-GC|253|main|||codex|green@stale253' \
  'bead-UP|254|main|||codex|green@head254|open|-' \
  'bead-FK|257|main|||codex|green@head257|open|pull_request|fork_pr' \
  'bead-FU|258|main|||codex|green@head258|open|pull_request|fork_pr_url' \
  'bead-RT|259|release/2.0|||codex|green@head259|open|pull_request' \
  'bead-PU|260|main|||codex|green@head260|open|pull_request|pr_number|https://github.com/acme/repo/pull/999' \
  'bead-BR|261|main|||codex|green@head261|open|pull_request|pr_number||polecat/somebody-else' \
  > "$TMP/anchors-fresh"
# All open + BLOCKED (the standing review is what blocks them), except 243.
# The last column is autoMergeRequest's enabling account ("" = not armed).
printf '%s\n' \
  '240|OPEN||false||main|polecat/bead-W|head240|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '241|OPEN||false||main|polecat/bead-X|head241|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '242|OPEN||false||main|polecat/bead-Y|head242|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '243|OPEN||false||main|polecat/bead-Z2|head243|MERGEABLE|CLEAN|APPROVED|' \
  '244|OPEN||false||main|polecat/bead-W2|head244|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '245|OPEN||false||main|polecat/bead-AM|head245|MERGEABLE|BLOCKED|CHANGES_REQUESTED|johnzook' \
  '246|OPEN||false||main|polecat/bead-P2|head246|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '247|OPEN||false||main|polecat/bead-HM|head247|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '248|OPEN||false||main|polecat/bead-AF|head248|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '249|OPEN||false||main|polecat/bead-AB|head249|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '250|OPEN||false||main|polecat/bead-AA|head250|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '251|OPEN||false||main|polecat/bead-ND|head251|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '252|OPEN||false||main|polecat/bead-MH|head252|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '253|OPEN||false||main|polecat/bead-GC|head253|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '254|OPEN||false||main|polecat/bead-UP|head254|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '255|OPEN||false||main|polecat/bead-SF|head255|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '256|OPEN||false||main|polecat/bead-RF|head256|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '257|OPEN||false||main|polecat/bead-FK|head257|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '258|OPEN||false||main|polecat/bead-FU|head258|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '259|OPEN||false||main|polecat/bead-RT|head259|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '260|OPEN||false||main|polecat/bead-PU|head260|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  '261|OPEN||false||main|polecat/bead-BR|head261|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  > "$TMP/prs"
# reviews: pr|id|login|state|commit_id|page ("page" >1 is served only to a
# --paginate caller, as GitHub does).
printf '%s\n' \
  '240|9001|zook-bot|CHANGES_REQUESTED|deadcommit240|1' \
  '240|9002|zook-bot|COMMENTED|head240|1' \
  '241|9101|johnzook|CHANGES_REQUESTED|deadcommit241|1' \
  '242|9201|zook-bot|CHANGES_REQUESTED|head242|1' \
  '243|9301|johnzook|APPROVED|head243|1' \
  '244|9401|zook-bot|CHANGES_REQUESTED|deadcommit244|1' \
  '245|9501|zook-bot|CHANGES_REQUESTED|deadcommit245|1' \
  '246|9601|zook-bot|COMMENTED|head246|1' \
  '246|9602|zook-bot|CHANGES_REQUESTED|deadcommit246|2' \
  '247|9701|zook-bot|CHANGES_REQUESTED|deadcommit247|1' \
  '248|9801|zook-bot|CHANGES_REQUESTED|deadcommit248|1' \
  '249|9901|zook-bot|CHANGES_REQUESTED|deadcommit249|1' \
  '250|9911|zook-bot|CHANGES_REQUESTED|deadcommit250|1' \
  '251|9921|zook-bot|CHANGES_REQUESTED|deadcommit251|1' \
  '252|9931|zook-bot|CHANGES_REQUESTED|deadcommit252|1' \
  '253|9941|zook-bot|CHANGES_REQUESTED|deadcommit253|1' \
  '254|9951|zook-bot|CHANGES_REQUESTED|deadcommit254|1' \
  '255|9961|zook-bot|CHANGES_REQUESTED|deadcommit255|1' \
  '256|9971|zook-bot|CHANGES_REQUESTED|deadcommit256|1' \
  '256|9972|zook-bot|CHANGES_REQUESTED|deadcommit256b|2' \
  '257|9981|zook-bot|CHANGES_REQUESTED|deadcommit257|1' \
  '258|9982|zook-bot|CHANGES_REQUESTED|deadcommit258|1' \
  '259|9983|zook-bot|CHANGES_REQUESTED|deadcommit259|1' \
  '260|9984|zook-bot|CHANGES_REQUESTED|deadcommit260|1' \
  '261|9985|zook-bot|CHANGES_REQUESTED|deadcommit261|1' \
  > "$TMP/reviews"
# PR 247's head moves between the pass's snapshot and the dismissal call.
printf '%s\n' '247|newhead247' > "$TMP/headmove"
printf '0' > "$TMP/amreads"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"; : > "$TMP/dismissed"
# Both streams are asserted below, and they carry different things on purpose:
# a HELD retraction with a routine, expected cause (merge_hold — an operator
# deliberately gated the PR) reports on stdout alongside the summary counters,
# while an ANOMALY a human should look at (auto-merge armed, the head moving
# mid-pass) is a WARN on stderr, as everywhere else in this script. Capturing
# only stdout would silently pass any assertion about the WARNs.
OUT13="$(FAKE_AM_FAIL=248 FAKE_AM_MALFORMED=249 FAKE_AM_ARM_AFTER=250 \
         FAKE_MARK_NOT_DURABLE=bead-ND \
         FAKE_ANCHORS_FRESH="$TMP/anchors-fresh" FAKE_SHOW_FAIL=bead-SF FAKE_REVIEWS_FAIL=256 \
         bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" 2>"$TMP/err13")"
ERR13="$(cat "$TMP/err13")"

# (39) THE HEAL: our superseded review is retracted, so GitHub can leave BLOCKED.
grep -qx '9001' "$TMP/dismissed" \
  && ok "(39) superseded self-review retracted (PR was BLOCKED on a dead commit)" \
  || bad "(39) superseded self-review must be dismissed (got: $(cat "$TMP/dismissed"))"
grep -q 'signoff_dismissed=9001@head240' "$TMP/updates" \
  && ok "(39) signoff_dismissed recorded on the anchor (arms merge-skill's approval gate)" \
  || bad "(39) signoff_dismissed marker (got: $(cat "$TMP/updates"))"
hasin "$OUT13" 'retracted superseded self-review 9001' \
  && ok "(39) retraction is reported, naming the review" \
  || bad "(39) retraction log line (got: $OUT13)"
# The retraction is the ONLY action: the anchor stays gating for the merge skill.
grep -q 'Review PR#240' "$TMP/created" \
  && bad "(39) heal must not file a re-review (the gate is already green at head)" \
  || ok "(39) no re-review filed — the gate is current, only GitHub was stale"

# (40) SAFETY: the operator's CHANGES_REQUESTED is a veto. It is superseded by the
# same test (a dead commit) and would be dismissed by any "is it stale" filter —
# only the AUTHOR check saves it.
grep -qx '9101' "$TMP/dismissed" \
  && bad "(40) the operator's review must NEVER be dismissed" \
  || ok "(40) operator CHANGES_REQUESTED left standing (author guard holds)"

# (41) our own CHANGES_REQUESTED at the LIVE head is a contradiction, not a
# supersede: both blocked and passed the same commit -> the block stands.
grep -qx '9201' "$TMP/dismissed" \
  && bad "(41) a self-review AT the reviewed head must not be dismissed" \
  || ok "(41) self-review at the live head left standing (not superseded)"

# (42) nothing to reconcile when GitHub already agrees.
grep -qx '9301' "$TMP/dismissed" \
  && bad "(42) an APPROVED review must never be touched" \
  || ok "(42) reviewDecision=APPROVED -> arm does not fire"

# (43) merge_hold is an operator gate; retraction is pipeline work toward landing,
# so it honors the hold exactly as the rebase and stale-gate arms do.
grep -qx '9401' "$TMP/dismissed" \
  && bad "(43) merge_hold must suppress the retraction" \
  || ok "(43) merge_hold=true -> no retraction (operator gate honored)"
hasin "$OUT13" 'PR#244 blocked by a superseded self-review but merge_hold set' \
  && ok "(43) the held retraction is reported with the operator-gate reason" \
  || bad "(43) merge_hold hold reason (got: $OUT13)"

# (46) NATIVE AUTO-MERGE. Dismissing the last block on a PR with `gh pr merge
# --auto` armed does not permit a merge, it PERFORMS one — server-side, at once,
# before merge-skill.sh ever reads the signoff_dismissed marker this arm records.
# That marker binds our own skill, never GitHub, so the only safe move is to
# leave the block standing.
grep -qx '9501' "$TMP/dismissed" \
  && bad "(46) auto-merge armed: dismissal would trigger an immediate server-side merge" \
  || ok "(46) native auto-merge armed -> no retraction (fail-closed)"
hasin "$ERR13" 'PR#245 blocked by a superseded self-review, but native auto-merge is ARMED' \
  && ok "(46) the auto-merge hold is reported, naming the reason" \
  || bad "(46) auto-merge hold reason (got: $ERR13)"

# (47) PAGINATION. 246's superseded review sits on page 2 of the reviews history.
# Unpaginated, the arm sees only the COMMENTED review on page 1, retracts nothing,
# and the PR stays stranded in exactly the state this arm exists to heal — and a
# PR that has taken a changes round is precisely the PR whose reviews run long.
grep -qx '9602' "$TMP/dismissed" \
  && ok "(47) superseded review on page 2 is found and retracted (read is paginated)" \
  || bad "(47) unpaginated reviews read misses the standing block (got: $(cat "$TMP/dismissed"))"

# (48) HEAD MOVED MID-PASS. The reviews listing is a snapshot; between it and the
# dismissal the head can advance and a FRESH block can be posted on the new head.
# Against the pass's stale head_oid the commit_id filter cannot tell that fresh
# block from a superseded one, so the live-head re-read immediately before the
# dismissal is what keeps this from retracting a live veto.
grep -qx '9701' "$TMP/dismissed" \
  && bad "(48) head moved mid-pass: the review may block the NEW head, must not be dismissed" \
  || ok "(48) head moved mid-pass -> no retraction (re-read before the irreversible call)"
hasin "$ERR13" 'PR#247 head moved (head247 -> newhead247) mid-pass' \
  && ok "(48) the mid-pass head move is reported" \
  || bad "(48) head-move hold reason (got: $ERR13)"

# (49) AUTO-MERGE PROBE FAILED. Read through `.autoMergeRequest // empty`, an API
# error, an auth failure and a rate limit all produce the SAME empty string a
# genuinely disarmed PR does — so the guard that exists to stop a server-side
# merge would clear itself on an answer it never received. Unreadable counts as
# armed: this is the one field where guessing wrong merges unreviewed work.
grep -qx '9801' "$TMP/dismissed" \
  && bad "(49) a FAILED auto-merge probe must not be read as 'disarmed'" \
  || ok "(49) auto-merge probe fails -> no retraction (unreadable counts as armed)"
hasin "$ERR13" "PR#248 blocked by a superseded self-review, but its native auto-merge state is UNREADABLE" \
  && ok "(49) the unreadable probe is reported as the reason, distinct from ARMED" \
  || bad "(49) unreadable-probe hold reason (got: $ERR13)"

# (50) The same fail-open shape from a MALFORMED payload rather than a failed
# call: a truncated body, or valid JSON that simply lacks the key (a schema
# change, a `gh` too old to know the field). The guard demands the key be PRESENT
# in a parseable object, so this is unknown -> held, not "disarmed" -> dismissed.
grep -qx '9901' "$TMP/dismissed" \
  && bad "(50) a MALFORMED auto-merge payload must not be read as 'disarmed'" \
  || ok "(50) malformed auto-merge payload -> no retraction (fail-closed)"
hasin "$ERR13" 'PR#249 blocked by a superseded self-review, but its native auto-merge state is UNREADABLE' \
  && ok "(50) the malformed probe is reported with the same unreadable reason" \
  || bad "(50) malformed-probe hold reason (got: $ERR13)"

# (51) TOCTOU: the up-front probe answered "disarmed" honestly, then an operator
# armed auto-merge before the dismissal landed. A one-time probe cannot see that
# window — the re-probe immediately before the irreversible call, in the same
# place and for the same reason as the live-head re-read, can.
grep -qx '9911' "$TMP/dismissed" \
  && bad "(51) auto-merge armed mid-pass: the dismissal would merge server-side" \
  || ok "(51) auto-merge armed after the up-front probe -> no retraction"
hasin "$ERR13" "PR#250 native auto-merge state is 'armed' immediately before dismissing review 9911" \
  && ok "(51) the mid-pass arming is reported, naming the review left in place" \
  || bad "(51) mid-pass auto-merge hold reason (got: $ERR13)"

# (52) NON-DURABLE PAIRING MARKER. `gc bd update` reports success and stores
# nothing. Pre-fix the exit status said "recorded", the dismissal ran, and the PR
# lost its GitHub block while merge-skill.sh saw no signoff_dismissed and so
# demanded no external approval — block and requirement gone together, the one
# combination that lands unreviewed work. Only reading the marker back sees it.
grep -qx '9921' "$TMP/dismissed" \
  && bad "(52) dismissal ran on a signoff_dismissed write that did not persist" \
  || ok "(52) non-durable signoff_dismissed -> no retraction (read-back guard)"
hasin "$ERR13" "could not record signoff_dismissed durably (read back '', want '9921@head251')" \
  && ok "(52) the read-back names the pairing marker it expected and did not find" \
  || bad "(52) non-durable marker hold reason (got: $ERR13)"

# (53) THE ANCHOR IS RE-READ TOO. The head and auto-merge re-checks above cover
# GitHub's side of the window; every BEAD-side fact this arm acts on still came
# from the ROWS snapshot taken before the PR was even read. An operator parking
# the anchor inside that window would have the last GitHub-side block removed from
# the PR they just held — merge-triggering work in defiance of the gate that
# exists to stop it.
grep -qx '9931' "$TMP/dismissed" \
  && bad "(53) merge_hold set mid-pass: the dismissal must not run on a held anchor" \
  || ok "(53) merge_hold appears after enumeration -> no retraction (anchor re-read)"
hasin "$ERR13" "bead-MH — anchor changed mid-pass (status='open' merge_hold='true'" \
  && ok "(53) the mid-pass hold is reported, naming the fields that changed" \
  || bad "(53) mid-pass hold reason (got: $ERR13)"
# (53b) the same for the gate itself: a re-gate that moved check.codex off the
# live head means the commit this arm is unblocking is no longer validated —
# retracting would leave an unreviewed head with nothing blocking it.
grep -qx '9941' "$TMP/dismissed" \
  && bad "(53b) check.codex moved off the live head: the PR is no longer gate-green" \
  || ok "(53b) check.codex re-gated mid-pass -> no retraction"
hasin "$ERR13" "bead-GC — anchor changed mid-pass .*check.codex='green@stale253'" \
  && ok "(53b) the re-gated marker is named in the hold" \
  || bad "(53b) re-gated marker hold reason (got: $ERR13)"
# (53c) and for the anchor's claim on the PR: un-parked (merge_result cleared), it
# no longer speaks for this PR at all, so it cannot authorize dropping its block.
grep -qx '9951' "$TMP/dismissed" \
  && bad "(53c) an un-parked anchor must not authorize a dismissal on its former PR" \
  || ok "(53c) merge_result cleared mid-pass -> no retraction"
# (53d) unreadable is unsafe, exactly as for the auto-merge probe: a read we never
# got cannot prove the anchor is unheld, still parked, and still green.
grep -qx '9961' "$TMP/dismissed" \
  && bad "(53d) an unreadable anchor must not be read as 'nothing changed'" \
  || ok "(53d) anchor metadata unreadable -> no retraction (fail-closed)"
hasin "$ERR13" "bead-SF — anchor metadata UNREADABLE immediately before dismissing review 9961" \
  && ok "(53d) the unreadable anchor is reported as the reason" \
  || bad "(53d) unreadable-anchor hold reason (got: $ERR13)"

# (53e) PARTIAL REVIEW HISTORY. `gh --paginate` streams the pages it did get and
# THEN fails, so the pages already on stdout parse perfectly — a well-formed
# history that is simply not the whole one. Fused into a single `gh | jq`
# assignment tested only for emptiness, that truncation was invisible, and this
# arm retracted from it as though it had read everything; a read that failed
# OUTRIGHT was equally invisible, rendering as "nothing to retract" and stranding
# the PR silently. PR#256's page 1 carries a stale self-CR that would otherwise be
# dismissed, and the read dies before page 2.
grep -qx '9971' "$TMP/dismissed" \
  && bad "(53e) a review found in a TRUNCATED history must not be retracted" \
  || ok "(53e) paginated reviews read fails part way -> no retraction (fail-closed)"
hasin "$ERR13" "bead-RF — PR#256 reviews history read FAILED" \
  && ok "(53e) the failed history read is reported, not swallowed" \
  || bad "(53e) failed reviews read must warn (got: $ERR13)"

# (53f-53g) THE FORK-KEYED ANCHOR (review tk-5knqi finding #2). Every other path in
# this pass resolves an anchor's PR under every key a bead names one with —
# pr_number, fork_pr, fork_pr_url — and the ROWS projection picks $num that way.
# The pre-dismissal re-read did NOT: it asked for `metadata.pr_number` alone. So a
# fork-keyed anchor (the fork-sync shape, which stamps NO pr_number) sailed through
# enumeration and every guard, then failed the last one with pr_number='' read as
# "the anchor moved off this PR". Nothing retracted, and this arm is the ONLY
# in-band way out for such a PR: its gate is green at the live head, so the
# stale-gate arm never fires and no re-review is ever dispatched. The PR stayed
# BLOCKED on a dead commit forever — the exact strand the arm exists to clear,
# reintroduced in its own last guard for precisely the beads the rest of the pass
# had just been widened to see.
grep -qx '9981' "$TMP/dismissed" \
  && ok "(53f) fork_pr-keyed anchor -> its superseded self-review IS retracted" \
  || bad "(53f) a fork_pr-keyed anchor must not be stranded by the re-read (got: $(cat "$TMP/dismissed"))"
grep -q 'signoff_dismissed=9981@head257' "$TMP/updates" \
  && ok "(53f) and the pairing marker is recorded on it, as for any other anchor" \
  || bad "(53f) fork_pr-keyed pairing marker (got: $(cat "$TMP/updates"))"
grep -qx '9982' "$TMP/dismissed" \
  && ok "(53g) fork_pr_url-keyed anchor -> retracted too (number parsed out of the url)" \
  || bad "(53g) a fork_pr_url-keyed anchor must not be stranded (got: $(cat "$TMP/dismissed"))"

# (53h-53j) THE REST OF THE IDENTITY, mutated mid-pass. merged_target, pr_url and
# branch authorize the retraction as directly as the gate marker does, and NONE of
# them moves the PR head — so neither the head re-read nor `check.codex` can catch
# them. Each is staged as a live-bead value that disagrees with the ROWS snapshot
# the arm decided from, which is what an operator retarget or a check-set-heal
# identity backfill looks like from inside the pass. Same set, same reasoning, as
# merge-skill.sh's terminal re-read immediately before `gh pr merge`.
grep -qx '9983' "$TMP/dismissed" \
  && bad "(53h) a retargeted anchor must not authorize a dismissal on this PR" \
  || ok "(53h) merged_target moved off the PR's base mid-pass -> no retraction"
hasin "$ERR13" "bead-RT — anchor was retargeted mid-pass (merged_target='release/2.0', PR base 'main')" \
  && ok "(53h) the retarget is reported against the PR's live base" \
  || bad "(53h) mid-pass retarget hold reason (got: $ERR13)"
grep -qx '9984' "$TMP/dismissed" \
  && bad "(53i) an anchor whose pr_url names another PR must not authorize this one" \
  || ok "(53i) pr_url repaired to a different PR mid-pass -> no retraction"
hasin "$ERR13" "bead-PU — anchor now records pr_url 'https://github.com/acme/repo/pull/999'" \
  && ok "(53i) the disagreeing url is reported against the PR this pass read" \
  || bad "(53i) mid-pass pr_url hold reason (got: $ERR13)"
grep -qx '9985' "$TMP/dismissed" \
  && bad "(53j) an anchor whose branch is not this PR's head must not authorize it" \
  || ok "(53j) branch corrected off this PR mid-pass -> no retraction"
hasin "$ERR13" "bead-BR — anchor now records branch 'polecat/somebody-else' but PR#261 is opened from 'polecat/bead-BR'" \
  && ok "(53j) the branch disagreement is reported against the PR's live head ref" \
  || bad "(53j) mid-pass branch hold reason (got: $ERR13)"
# ...and the new guard does NOT over-fire: every anchor retracted above (39/47/53f/
# 53g) carries an AGREEING merged_target and branch, so a matching identity still
# dismisses. Silence on a field is not a disagreement either — the fork-keyed pair
# records no pr_url at all and is retracted regardless.

# Retractions report on their OWN counters — folding them into the stale-gate
# re-review counters would misreport that arm's throughput.
hasin "$OUT13" '4 superseded reviews retracted, 15 retractions held' \
  && ok "(43) summary counts retractions separately from stale-gate re-reviews" \
  || bad "(43) summary retraction counters (got: $OUT13)"
hasin "$OUT13" '0 stale-gate re-reviews routed' \
  && ok "(43) a retraction is NOT counted as a stale-gate re-review" \
  || bad "(43) retraction must not inflate the stale-gate counter (got: $OUT13)"

# (44) CONVERGENCE: once dismissed the review is no longer CHANGES_REQUESTED, so a
# second pass retracts nothing — the arm cannot loop on the same PR.
#
# Model the heal faithfully: EVERY review the pass actually dismissed comes back
# DISMISSED (that is what GitHub reports afterwards) and the PR it unblocked comes
# back CLEAN/APPROVED. Flipping only one PR's review by hand would leave the other
# healed PR still reading CHANGES_REQUESTED, so the second pass would re-retract
# it and the case would measure a stale fixture rather than convergence. Driving
# it off "$TMP/dismissed" also keeps this correct as retraction fixtures are added.
HEALED_IDS="$(sort -u "$TMP/dismissed")"
for rid in $HEALED_IDS; do
  pr=$(awk -F'|' -v r="$rid" '$2==r{print $1; exit}' "$TMP/reviews")
  awk -F'|' -v r="$rid" 'BEGIN{OFS="|"} $2==r{$4="DISMISSED"} {print}' \
    "$TMP/reviews" > "$TMP/reviews.next" && mv "$TMP/reviews.next" "$TMP/reviews"
  [ -n "$pr" ] || continue
  awk -F'|' -v p="$pr" 'BEGIN{OFS="|"} $1==p && $10=="BLOCKED"{$10="CLEAN"; $11="APPROVED"} {print}' \
    "$TMP/prs" > "$TMP/prs.next" && mv "$TMP/prs.next" "$TMP/prs"
done
: > "$TMP/dismissed"
# The injected faults are carried into this pass DELIBERATELY. They are what the
# held anchors are held ON: drop them and 248-255 stop being held, retract on this
# pass, and the case measures "a transient fault cleared" instead of "a healed PR
# is not re-retracted". (That those anchors DO retract once the fault clears is
# the intended behaviour — a hold here is never terminal — it is just not what
# this assertion is for.) That includes the mid-pass anchor states: without
# FAKE_ANCHORS_FRESH/FAKE_SHOW_FAIL, 252-255 would simply be healthy anchors here.
# stderr is dropped: 245 (auto-merge), 247 (head move) and 248-251 are still
# legitimately held on this pass and re-emit their WARNs, which the cases above
# already assert.
FAKE_AM_FAIL=248 FAKE_AM_MALFORMED=249 FAKE_AM_ARM_AFTER=250 \
  FAKE_MARK_NOT_DURABLE=bead-ND \
  FAKE_ANCHORS_FRESH="$TMP/anchors-fresh" FAKE_SHOW_FAIL=bead-SF FAKE_REVIEWS_FAIL=256 \
  bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" >/dev/null 2>&1
eq "$(wc -l < "$TMP/dismissed" | tr -d ' ')" "0" \
   "(44) converges: a healed PR is not re-retracted on the next pass"

# (45) FAIL-CLOSED: with no resolvable acting login the arm cannot tell our
# reviews from a human's, so it retracts nothing at all.
: > "$TMP/dismissed"
printf '%s\n' '241|9101|johnzook|CHANGES_REQUESTED|deadcommit241' \
              '244|9401|zook-bot|CHANGES_REQUESTED|deadcommit244' > "$TMP/reviews"
FAKE_SELF_LOGIN="" bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" >/dev/null
eq "$(wc -l < "$TMP/dismissed" | tr -d ' ')" "0" \
   "(45) unresolvable acting login -> nothing retracted (cannot distinguish ours)"

# --- Run 14: LONG, SPACED check_set (tk-gzz54). -------------------------------
# BOTH arms above are gated on the same `codex is a declared check-set member`
# test, so anything that makes that test misread takes out stale-gate re-review
# AND the superseded-review self-heal at once, leaving those PRs blocked with no
# in-band path out. Every case so far declares the single-token check_set
# "codex", which exercises neither risk in that test:
#   * a NATURAL spaced list ("lint, codex, ...") must still match — the untrimmed
#     literal-substring form this membership test used to have would miss it;
#   * `codex` must be matched WHOLE-TOKEN, so a neighbouring gate whose name
#     merely contains it ("codex-lite") is not mistaken for the gate itself;
#   * and the test must survive a check_set with MANY gates listed after `codex`.
#     That last one is why the pipeline form was replaced: `set -o pipefail` is on
#     and `grep -q` exits at the first match, so with trailing gates still being
#     written the upstream `tr`/`sed` can take SIGPIPE and the pipeline reports
#     141 — the membership flag never gets set and both arms silently skip. It is
#     timing-dependent, so no test can reliably PROVOKE it; the static guard below
#     asserts the form instead, and these cases pin the behaviour that form must
#     preserve.
LONG_CS='lint, codex-lite, codex, typecheck, security, docs, coverage, shellcheck'
# anchors: id|pr|target|merge_hold|rebase_hold|check_set|check.codex-marker
#   bead-LC1 260 long check_set, marker green@old260 (head moved) -> STALE-GATE
#   bead-LC2 261 long check_set, marker green@head261 + our dead CR -> SUPERSEDED
printf '%s\n' \
  "bead-LC1|260|main|||$LONG_CS|green@old260" \
  "bead-LC2|261|main|||$LONG_CS|green@head261" \
  > "$TMP/anchors"
printf '%s\n' \
  '260|OPEN||false||main|polecat/bead-LC1|head260|MERGEABLE|BLOCKED||' \
  '261|OPEN||false||main|polecat/bead-LC2|head261|MERGEABLE|BLOCKED|CHANGES_REQUESTED|' \
  > "$TMP/prs"
printf '%s\n' '261|9981|zook-bot|CHANGES_REQUESTED|deadcommit261|1' > "$TMP/reviews"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"; : > "$TMP/wakes"
: > "$TMP/gatehead"; : > "$TMP/gatenopool"; : > "$TMP/openprs"; : > "$TMP/dismissed"
: > "$TMP/children"; : > "$TMP/headmove"; printf '0' > "$TMP/amreads"
OUT14="$(bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" 2>/dev/null)"

# (54) stale-gate arm still fires when `codex` is one member of a long list.
eq "$(grep -c 'Review PR#260' "$TMP/created")" "1" \
   "(54) long spaced check_set -> stale gate still re-reviewed (codex recognized)"
grep -q 'stale_gate_head=head260' "$TMP/updates" \
  && ok "(54) and the one-per-head guard is armed on the anchor" \
  || bad "(54) stale_gate_head must be armed (got: $(cat "$TMP/updates"))"

# (55) superseded-review arm still fires on the same shape of check_set.
grep -qx '9981' "$TMP/dismissed" \
  && ok "(55) long spaced check_set -> superseded self-review still retracted" \
  || bad "(55) superseded review must be dismissed (got: $(cat "$TMP/dismissed"))"
grep -q 'signoff_dismissed=9981@head261' "$TMP/updates" \
  && ok "(55) and the pairing marker is recorded on the anchor" \
  || bad "(55) signoff_dismissed marker (got: $(cat "$TMP/updates"))"
# Both counters move in the SAME pass: the membership test they share read the
# long check_set correctly for each arm, not just for whichever ran first.
hasin "$OUT14" '1 stale-gate re-reviews routed' \
  && ok "(55) summary counts the stale-gate re-review under a long check_set" \
  || bad "(55) run 14 summary stale-gate count (got: $OUT14)"
hasin "$OUT14" '1 superseded reviews retracted' \
  && ok "(55) summary counts the retraction under a long check_set" \
  || bad "(55) run 14 summary retraction count (got: $OUT14)"

# (56) WHOLE-TOKEN: `codex-lite` sits in the same list and must not be what
# matched. A gateless rig is the mirror image of the same requirement — its
# `none` sentinel names no gate, so neither arm may fire on it.
printf '%s\n' \
  'bead-LC3|262|main|||lint, codex-lite, typecheck|green@old262' \
  'bead-LC4|263|main|||none|green@old263' \
  > "$TMP/anchors"
printf '%s\n' \
  '262|OPEN||false||main|polecat/bead-LC3|head262|MERGEABLE|BLOCKED||' \
  '263|OPEN||false||main|polecat/bead-LC4|head263|MERGEABLE|BLOCKED||' \
  > "$TMP/prs"
: > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/gatehead"; : > "$TMP/dismissed"
bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL" >/dev/null 2>&1
eq "$(grep -c 'Review PR#262' "$TMP/created")" "0" \
   "(56) 'codex-lite' is a different gate -> no re-review (whole-token match)"
eq "$(grep -c 'Review PR#263' "$TMP/created")" "0" \
   "(56) the none sentinel names no gate -> gateless rig never enters the arm"

# (57) STATIC GUARD: the membership test must stay in-shell. A `grep -q` pipeline
# reintroduces the pipefail/SIGPIPE misread that (54)/(55) cannot provoke on
# demand — the same regression merge-skill.sh's approval and trusted-approver
# tests are written this way to prevent.
# Anchored on the `is_codex_member=""` initialiser rather than on a mention of the
# flag: the rationale comment above the test quotes `grep -q` while explaining why
# it is gone, so a looser anchor would read the prose and fail on the fixed code.
CS_SITE=$(grep -n 'is_codex_member=""' "$SCRIPT" | head -1 | cut -d: -f1)
[ -n "$CS_SITE" ] \
  && ok "(57) the codex-membership site is present" \
  || bad "(57) could not locate the codex-membership site in $SCRIPT"
CS_BLOCK=$(sed -n "$CS_SITE,$((CS_SITE + 4))p" "$SCRIPT")
hasin "$CS_BLOCK" 'grep -q' \
  && bad "(57) codex membership must NOT be decided by a grep pipeline (pipefail/SIGPIPE misread)" \
  || ok "(57) codex membership is matched in-shell, not through a grep pipeline"
hasin "$CS_BLOCK" '",codex,"' \
  && ok "(57) and it is a comma-wrapped whole-token match" \
  || bad "(57) codex membership must be a comma-wrapped whole-token match"

# (58) THE SAME CLASS ON THE TRACKED SET. The anchorless scan asks "is this open PR
# named by a live bead?" against a newline-separated list, and it asked with
# `printf '%s\n' "$TRACKED" | grep -qxF "$pnum"`. `grep -q` exits at the FIRST
# match, closing the pipe under a `printf` that may still be writing — printf takes
# SIGPIPE, `set -o pipefail` reports 141, and the `if` reads a MATCH as a MISS,
# decided by nothing but how many lines happen to follow the one that matched.
# Inverted, this arm reports a perfectly well-anchored PR as ANCHORLESS and mails
# the mayor about it — the one finding this pass escalates. Structural, like (57),
# because the race cannot be provoked on demand.
TS_SITE=$(grep -n 'Tracked by a live bead' "$SCRIPT" | head -1 | cut -d: -f1)
[ -n "$TS_SITE" ] \
  && ok "(58) the tracked-set membership site is present" \
  || bad "(58) could not locate the tracked-set membership site in $SCRIPT"
TS_BLOCK=$(sed -n "$TS_SITE,$((TS_SITE + 3))p" "$SCRIPT")
hasin "$TS_BLOCK" 'grep -q' \
  && bad "(58) tracked-set membership must NOT be decided by a grep pipeline (pipefail/SIGPIPE misread)" \
  || ok "(58) tracked-set membership is matched in-shell, not through a grep pipeline"
# ...and the helper it uses really does match WHOLE LINES, extracted from the
# script and exercised directly: PR#7 must never be satisfied by PR#77 or PR#177,
# and an empty needle must never match the delimiters themselves.
LHL=$(sed -n '/^list_has_line() {/,/^}/p' "$SCRIPT")
[ -n "$LHL" ] \
  && ok "(58) list_has_line extracted from the script" \
  || bad "(58) list_has_line not found in $SCRIPT"
lhl_probe() { # <haystack> <needle>
  bash -c "set -uo pipefail
$LHL
list_has_line \"\$1\" \"\$2\" && echo yes || echo no" _ "$1" "$2"
}
eq "$(lhl_probe "$(printf '7\n42\n')" '7')"   "yes" "(58) an exact line matches"
eq "$(lhl_probe "$(printf '77\n177\n')" '7')" "no"  "(58) PR#7 is NOT satisfied by 77 or 177"
eq "$(lhl_probe "$(printf '7\n42\n')" '42')"  "yes" "(58) the LAST line matches too"
eq "$(lhl_probe "$(printf '7\n42\n')" '')"    "no"  "(58) an empty needle never matches"
eq "$(lhl_probe '' '7')"                      "no"  "(58) an empty haystack never matches"

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
hasin "$OUTID1" '0 foreign-PR identity holds' \
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
hasin "$OUTID2" "answered from 'github.com/stranger/repo', not this checkout's 'github.com/acme/repo'" \
  && ok "(ID2) the refusal names the repository that answered" \
  || bad "(ID2) must name the foreign repository (got: $OUTID2)"
hasin "$OUTID2" '5 foreign-PR identity holds' \
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
hasin "$OUTID2B" '0 foreign-PR identity holds' \
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
hasin "$OUTID3" "anchor id-CLOSE records pr_url 'https://github.com/acme/OTHER/pull/501'" \
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
hasin "$OUTID5A" 'ANCHORLESS PR#601' \
  && ok "(ID5) control: an open PR of OURS with a closed anchor IS reported anchorless" \
  || bad "(ID5) control: anchorless finding expected (got: $OUTID5A)"
eq "$(grep -c 'anchorless open PR#601' "$TMP/mail")" "1" "(ID5) control: the anchorless finding escalates once"
reset_identity
: > "$TMP/anchors"; : > "$TMP/prs"
printf '%s\n' '601|false|polecat/dead-6|main' > "$TMP/openprs"
printf '%s\n' '601	dead-6	-	pull_request	2026-01-01T00:00:00Z	-' > "$TMP/dead"
echo 'stranger/repo' > "$TMP/ghdefault"; echo 1 > "$TMP/ignorerepo"
OUTID5B="$(IDRUN 2>"$TMP/errid5")"
hasin "$OUTID5B" 'ANCHORLESS' \
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
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|||mallory/repo|true' \
  '502|CLOSED||false||main|polecat/id-ABAND|head502|UNKNOWN|UNKNOWN|||mallory/repo|true' \
  '503|OPEN||false||main|polecat/id-RETGT|head503|MERGEABLE|BLOCKED|||mallory/repo|true' \
  '504|OPEN||false||main|polecat/id-CONF|head504|CONFLICTING|DIRTY|||mallory/repo|true' \
  '505|OPEN||false||main|polecat/id-GATE|head505|MERGEABLE|BLOCKED|||mallory/repo|true' \
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
hasin "$OUTHD1" "PR#501 is opened from FORK 'mallory/repo'" \
  && ok "(HD1) the refusal names the fork and this checkout's repository" \
  || bad "(HD1) refusal must name the fork (got: $OUTHD1)"

# (HD2) SELFCONTRA: the head repository IS ours and isCrossRepository says otherwise.
# A self-contradicting identity is unestablished, not a tie to break.
reset_identity
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|||acme/repo|true' \
  > "$TMP/prs"
OUTHD2="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(HD2) a self-contradicting head identity must record no state" \
  || ok "(HD2) headRepository/isCrossRepository disagreement -> no state recorded"
hasin "$OUTHD2" "PR#501 reports head repository 'acme/repo' (this checkout's own) and cross-repository='true'" \
  && ok "(HD2) the refusal names both halves of the contradiction" \
  || bad "(HD2) refusal must name the contradiction (got: $OUTHD2)"

# (HD3) NOHEAD: gh returns null head repository objects (a deleted head repository, a
# schema shift). "I cannot tell whether this is a fork" must record nothing.
reset_identity
printf '%s\n' \
  '501|MERGED|2026-07-01T00:00:00Z|false|5015015015015015|main|polecat/id-CLOSE|head501|MERGEABLE|CLEAN|||-|false' \
  > "$TMP/prs"
OUTHD3="$(IDRUN)"
has '^id-CLOSE$' "$TMP/closed" \
  && bad "(HD3) an unreadable head identity must record no state" \
  || ok "(HD3) null headRepository/headRepositoryOwner -> no state recorded"
hasin "$OUTHD3" "PR#501 head identity is unreadable" \
  && ok "(HD3) the refusal names the unreadable identity" \
  || bad "(HD3) refusal must name the unreadable head (got: $OUTHD3)"

# (HD4) BRANCHMISMATCH: our repository, our head repository, WRONG branch — the
# anchor and the pull request describe different work. The rebase arm is the one that
# makes this concrete: `fix_branch` comes from the PR's headRefName, so an unchecked
# mismatch force-pushes a rebase onto a branch the anchor never recorded.
reset_identity
printf '%s\n' \
  '504|OPEN||false||main|polecat/somebody-else|head504|CONFLICTING|DIRTY|||acme/repo|false' \
  > "$TMP/prs"
OUTHD4="$(IDRUN)"
eq "$(grep -c 'Rebase PR#504' "$TMP/created")" "0" \
   "(HD4) head branch != anchor's recorded branch -> NO rebase child dispatched"
hasin "$OUTHD4" "anchor id-CONF records branch 'polecat/id-CONF' but PR#504 is opened from 'polecat/somebody-else'" \
  && ok "(HD4) the refusal names both branches" \
  || bad "(HD4) refusal must name both branches (got: $OUTHD4)"

# --- FORK-KEYED GATING ANCHORS (review tk-78ty5 finding #5). ------------------
# The ownership probes and the anchorless scan already read every key a bead names
# a PR with (pr_number, fork_pr, fork_pr_url); merge-skill.sh reads all three for an
# anchor's OWN identity too. The per-anchor loop here read `pr_number` ALONE, so an
# anchor keyed only by fork_pr — the shape the fork-sync flow stamps, which sets no
# pr_number at all — produced an empty `pr` and was dropped by the loop's own
# empty-number skip. Every per-anchor arm was therefore blind to it: merged
# externally, closed out-of-band, retargeted, conflicted, stale-gated — none of it
# reconciled. Meanwhile the anchorless scan counted its PR owned and said nothing,
# and merge-skill.sh treated it as live. The two passes disagreed about who owns the
# PR, and the quieter answer won.
reset_identity
: > "$TMP/dismissed"
#          id|pr|target|mhold|rhold|cset|cmark|prurl|fork_pr
printf '%s\n' 'id-FORKKEY||main||||||507' > "$TMP/anchors"
printf '%s\n' \
  '507|MERGED|2026-07-01T00:00:00Z|false|5075075075075075|main|polecat/id-FORKKEY|head507|MERGEABLE|CLEAN' \
  > "$TMP/prs"
OUTFK="$(IDRUN)"
has '^id-FORKKEY$' "$TMP/closed" \
  && ok "(FK-ANCHOR) a fork_pr-keyed gating anchor enters the per-anchor loop and its merged PR closes it" \
  || bad "(FK-ANCHOR) fork_pr-keyed anchor must reconcile (pre-fix: empty pr -> skipped by every arm, and silent) (got: $OUTFK)"

# ...and the same anchor keyed by a fork_pr_url naming ANOTHER repository does NOT.
# `in_repo` keeps the fail-closed `?` wildcard for a bare number that names no
# repository, but a URL that positively names somewhere else is somebody else's pull
# request — reconciling our anchor against THEIR #507 is the cross-repository write
# the identity guards exist to stop, arriving through the key set instead of through
# the read.
reset_identity
#          id|pr|target|mhold|rhold|cset|cmark|prurl|fork_pr|fork_pr_url
printf '%s\n' 'id-FORKFOREIGN||main|||||||https://otherhost/acme/repo/pull/507' > "$TMP/anchors"
printf '%s\n' \
  '507|MERGED|2026-07-01T00:00:00Z|false|5075075075075075|main|polecat/id-FORKFOREIGN|head507|MERGEABLE|CLEAN' \
  > "$TMP/prs"
OUTFKF="$(IDRUN)"
has '^id-FORKFOREIGN$' "$TMP/closed" \
  && bad "(FK-FOREIGN) a fork_pr_url naming another repository must NOT close a local anchor (got: $OUTFKF)" \
  || ok "(FK-FOREIGN) fork_pr_url pointing elsewhere -> anchor not reconciled against our same-numbered PR"

# --- EVERY GitHub CALL IS PINNED (review tk-78ty5 finding #3). ----------------
# The identity guards above compare the ANSWER (the returned url) after the fact.
# That works for the read arms, but the retraction arm also WRITES to GitHub — it
# DISMISSES a review — and a write has no answer to compare: by the time a wrong
# repository is detectable, the review there is already dismissed. So the calls in
# that arm have to be pinned by CONSTRUCTION.
#
# They were not. The PR read carried `--repo`, but the reviews history and the
# dismissal were REST paths written `repos/{owner}/{repo}/...`, and gh expands
# those placeholders from its AMBIENT repository — the cwd's remote, or $GH_REPO.
# The mid-pass head re-read and the auto-merge probe were bare `gh pr view "$num"`
# for the same reason. Under a drifted context that reads a SAME-NUMBERED PR
# somewhere else and dismisses a review THERE, while stamping signoff_dismissed on
# OUR anchor — the city's block removed in one repository and the requirement that
# was supposed to replace it recorded in another.
#
# (PIN1) is what catches the placeholder form specifically: an unpinned REST path
# records the LITERAL `{owner}/{repo}` here, so it can never be mistaken for the
# origin-derived name. (PIN2) covers every `gh pr view` in the pass — the main read,
# the mid-pass head re-read, and the auto-merge probe — across every run in this
# file, including the drift runs (ID1, ID2, ID2b, ID5) where an unpinned call
# resolves somewhere else by construction.
#
# Both read the recorders accumulated by EVERY run above, so they measure the whole
# file rather than one staged scenario.
eq "$(cut -d/ -f1,2 "$TMP/apiwhere" | sort -u | tr '\n' ' ')" "acme/repo " \
   "(PIN1) every gh api REST path named the origin-derived repository (never the ambient {owner}/{repo})"
eq "$(cut -f2 "$TMP/viewwhere" | sort -u | tr '\n' ' ')" "github.com/acme/repo " \
   "(PIN2) every gh pr view passed --repo <origin> — main read, mid-pass head re-read and auto-merge probe alike (never <unpinned>)"
# (PIN3) THE OTHER HALF OF THE REST PIN. (PIN1) proves every `gh api` path named
# acme/repo; that still leaves the HOST to $GH_HOST, and another host's acme/repo
# has a PR of every number, its own review ids, and its own history. This arm
# READS a reviews history and PUTs a DISMISSAL, so a half-pinned call can retract a
# stranger's review while ours stays blocked — with (PIN1) still green.
eq "$(sort -u "$TMP/apihost" | tr '\n' ' ')" "github.com " \
   "(PIN3) every gh api call carried --hostname <origin-host> (never <unpinned>, which falls back to \$GH_HOST)"
# Positive control for both: a recorder that stayed EMPTY would satisfy the two
# assertions above vacuously (`sort -u` of nothing is nothing), so prove the calls
# were actually made and actually recorded.
[ "$(wc -l < "$TMP/apiwhere" | tr -d ' ')" -gt 0 ] \
  && ok "(PIN-CTL) the gh api recorder is non-empty (PIN1 is not vacuous)" \
  || bad "(PIN-CTL) no gh api call was recorded — PIN1 proves nothing"
[ "$(wc -l < "$TMP/viewwhere" | tr -d ' ')" -gt 0 ] \
  && ok "(PIN-CTL) the gh pr view recorder is non-empty (PIN2 is not vacuous)" \
  || bad "(PIN-CTL) no gh pr view call was recorded — PIN2 proves nothing"

# (ID-INV) the observer never merges anything, identity drift or not.
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(ID-INV) the observer reached no merge path across every identity run"

# --- (CL) the close gate: identity-ENCODING override + the wedge escalation. ---
# `bd close` is assignee-gated and compares the ASSIGNEE string to the ACTOR
# string. Those two routinely carry the same principal in two renderings —
# `<rig>/<pack>.<role>` ($GC_AGENT) vs `<rig>--<pack>__<role>` ($GC_SESSION_NAME)
# — so a refinery closing an anchor it HOLDS is refused, and nothing self-heals:
# every pass takes the identical path and fails identically, so the anchor never
# closes over a MERGED PR. Under close-on-land that is the false record in the
# dangerous direction (merged work whose bead still reads open) and it was nearly
# invisible: signal-loom PR#518 retried ~40 times behind a `0 closed ... 1 skipped`
# summary that read normal.
#
# Two behaviours, and the second is what keeps the first honest:
#   (CL1) the ENCODING refusal is retried once with --force and the anchor closes;
#   (CL2) a refusal that is NOT that — a genuinely foreign assignee, an
#         open-children hold — is NEVER forced past, because --force there would
#         paper over exactly what the gate is for;
#   (CL3) and since (CL2) means some closes still fail forever, a close that keeps
#         failing ESCALATES at the threshold instead of retrying silently.
#
#   cl-ENC   601 MERGED, close refused on the encoding mismatch -> forced, CLOSED
#   cl-FRGN  602 MERGED, close refused with a FOREIGN assignee  -> NOT closed
#   cl-KIDS  603 MERGED, close refused for open children        -> NOT closed
#   cl-OK    604 MERGED, close succeeds outright                -> CLOSED, unforced
reset_close() {
  : > "$TMP/closed"; : > "$TMP/abandoned"; : > "$TMP/retargeted"; : > "$TMP/mail"
  : > "$TMP/mailbody"; : > "$TMP/created"; : > "$TMP/updates"; : > "$TMP/deps"
  : > "$TMP/wakes"; : > "$TMP/staled"; : > "$TMP/gatehead"; : > "$TMP/gatenopool"
  : > "$TMP/closelog"; : > "$TMP/children"; : > "$TMP/openprs"; : > "$TMP/livex"
  : > "$TMP/dead"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/ghhost"
  : > "$TMP/forced"; : > "$TMP/closefails"; : > "$TMP/closeesc"
  : > "$TMP/closerefuse"; : > "$TMP/closehard"
  printf '%s\n' \
    'cl-ENC|601|main' \
    'cl-FRGN|602|main' \
    'cl-KIDS|603|main' \
    'cl-OK|604|main' \
    > "$TMP/anchors"
  printf '%s\n' \
    '601|MERGED|2026-08-09T04:58:00Z|false|6016016016016016|main|polecat/cl-ENC|head601|MERGEABLE|CLEAN' \
    '602|MERGED|2026-08-09T04:58:00Z|false|6026026026026026|main|polecat/cl-FRGN|head602|MERGEABLE|CLEAN' \
    '603|MERGED|2026-08-09T04:58:00Z|false|6036036036036036|main|polecat/cl-KIDS|head603|MERGEABLE|CLEAN' \
    '604|MERGED|2026-08-09T04:58:00Z|false|6046046046046046|main|polecat/cl-OK|head604|MERGEABLE|CLEAN' \
    > "$TMP/prs"
  # The refusals, transcribed from bd's own format string:
  #   cannot close %s: assignee is %q, actor is %q; reclaim or use --force to override
  # cl-ENC is ONE principal in two encodings; cl-FRGN is two different principals
  # (polecat vs refinery) wearing the same message shape — which is exactly why
  # matching the message alone would be a blanket --force.
  printf 'cl-ENC\tcannot close cl-ENC: assignee is "signal-loom/gc-toolkit.refinery", actor is "signal-loom--gc-toolkit__refinery"; reclaim or use --force to override\n' \
    > "$TMP/closerefuse"
  printf 'cl-FRGN\tcannot close cl-FRGN: assignee is "signal-loom/gc-toolkit.polecat", actor is "signal-loom--gc-toolkit__refinery"; reclaim or use --force to override\ncl-KIDS\tcannot close cl-KIDS: 2 open child issue(s); close children first or use --force to override\n' \
    > "$TMP/closehard"
}
CLRUN() { bash "$SCRIPT" --fix-pool "$FIX_POOL" --review-pool "$REVIEW_POOL"; }

reset_close
OUTCL1="$(CLRUN 2>"$TMP/errcl1")"

# (CL1) the wedge itself: refused on encoding, retried with --force, CLOSED.
has '^cl-ENC$' "$TMP/closed" \
  && ok "(CL1) identity-ENCODING refusal -> anchor still CLOSES (the PR#518 wedge)" \
  || bad "(CL1) encoding-refused anchor must close via --force (got: $OUTCL1)"
has '^cl-ENC$' "$TMP/forced" \
  && ok "(CL1) ...and it closed via --force, not by the refusal silently passing" \
  || bad "(CL1) the close must have gone through --force"
grep -q 'Merged to main at 60160160' "$TMP/closelog" \
  && ok "(CL1) the forced close carries the same reason as a clean one" \
  || bad "(CL1) forced close reason (got: $(cat "$TMP/closelog"))"
# The override must be VISIBLE. A --force that fires silently is indistinguishable
# from a clean close, which is how an override becomes a habit nobody audits.
has 'identity-ENCODING mismatch' "$TMP/errcl1" \
  && ok "(CL1) the retry is logged, so an override that fired is auditable" \
  || bad "(CL1) the --force retry must be logged (got: $(cat "$TMP/errcl1"))"
hasin "$OUTCL1" '1 identity-encoding forced closes' \
  && ok "(CL1) the summary line counts the forced close" \
  || bad "(CL1) summary must count forced closes (got: $OUTCL1)"

# (CL2) NOT a blanket --force. Both of these refusals are REAL, and both would be
# overridden by matching on "the close failed" — or even on the message shape, for
# cl-FRGN, whose message is character-for-character the same form as cl-ENC's.
has '^cl-FRGN$' "$TMP/closed" \
  && bad "(CL2) a GENUINELY foreign assignee must never be forced past" \
  || ok "(CL2) foreign assignee -> NOT closed (the ownership gate still holds)"
has '^cl-FRGN$' "$TMP/forced" \
  && bad "(CL2) --force must not be attempted on a foreign assignee" \
  || ok "(CL2) ...and --force was never even attempted for it"
has '^cl-KIDS$' "$TMP/closed" \
  && bad "(CL2) an open-children hold must never be forced past" \
  || ok "(CL2) open-children refusal -> NOT closed"
has '^cl-KIDS$' "$TMP/forced" \
  && bad "(CL2) --force must not be attempted on an open-children hold" \
  || ok "(CL2) ...and --force was never even attempted for it"
# Positive control: a clean close still closes, and is NOT counted as forced.
has '^cl-OK$' "$TMP/closed" \
  && ok "(CL2-CTL) an unrefused close still closes normally" \
  || bad "(CL2-CTL) control anchor must close (got: $OUTCL1)"
has '^cl-OK$' "$TMP/forced" \
  && bad "(CL2-CTL) an unrefused close must not report as forced" \
  || ok "(CL2-CTL) ...and it is not counted as a forced close"

# (CL3) the wedge does not spin silently. cl-FRGN and cl-KIDS fail every pass by
# construction, so they are the standing case for "a retry loop that can never
# succeed must not look like routine skipping". The count is per-anchor and
# durable; the escalation fires ONCE at the threshold (default 3).
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closefails" | tail -1)" "1" \
   "(CL3) pass 1 records close_failures=1"
eq "$(grep -c 'will not close over merged PR#602' "$TMP/mail")" "0" \
   "(CL3) ...and does NOT escalate yet (one blip is not a wedge)"

OUTCL2="$(CLRUN 2>/dev/null)"
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closefails" | tail -1)" "2" \
   "(CL3) pass 2 counts CONSECUTIVELY (2), reading what pass 1 wrote"
eq "$(grep -c 'will not close over merged PR#602' "$TMP/mail")" "0" \
   "(CL3) ...still below the threshold, still quiet"

OUTCL3="$(CLRUN 2>"$TMP/errcl3")"
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closefails" | tail -1)" "3" \
   "(CL3) pass 3 reaches the threshold"
eq "$(grep -c 'will not close over merged PR#602' "$TMP/mail")" "1" \
   "(CL3) ...and ESCALATES to mayor — the ~40 silent retries of PR#518 cannot recur"
eq "$(grep -c 'will not close over merged PR#603' "$TMP/mail")" "1" \
   "(CL3) each wedged anchor escalates on its own count (cl-KIDS too)"
hasin "$OUTCL3" '2 wedged-close escalations' \
  && ok "(CL3) the summary line reports the wedge instead of burying it in 'skipped'" \
  || bad "(CL3) summary must count wedged-close escalations (got: $OUTCL3)"
grep -q 'gc bd close cl-FRGN' "$TMP/mailbody" \
  && ok "(CL3) the escalation hands the operator the command that shows the refusal" \
  || bad "(CL3) escalation body should name the by-hand close command"

# ONCE, not once per pass: the counter keeps rising, so an unbounded arm would
# re-mail the same stuck anchor on every wake — the noise that gets escalations
# muted, which is how the silence returns by another route.
OUTCL4="$(CLRUN 2>/dev/null)"
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closefails" | tail -1)" "4" \
   "(CL3) pass 4 keeps counting"
eq "$(grep -c 'will not close over merged PR#602' "$TMP/mail")" "1" \
   "(CL3) ...but does NOT re-escalate — the marker bounds it to one mail per wedge"

# (CL4) the counter is CLEARED by the pass that finally closes the anchor: a
# landed anchor still carrying close_failures reads as stuck to the next human,
# and a stale close_escalated would bound an escalation for a future, unrelated
# wedge.
: > "$TMP/closehard"          # the refusal is lifted (children closed / bead reclaimed)
OUTCL5="$(CLRUN 2>/dev/null)"
has '^cl-FRGN$' "$TMP/closed" \
  && ok "(CL4) once the real refusal is lifted, the anchor closes on the next pass" \
  || bad "(CL4) anchor must close after the refusal is lifted (got: $OUTCL5)"
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closefails" | tail -1)" "" \
   "(CL4) ...and the close-failure counter is cleared with it"
eq "$(awk -F'\t' '$1=="cl-FRGN"{print $2}' "$TMP/closeesc" | tail -1)" "" \
   "(CL4) ...as is the escalation marker (a future wedge escalates on its own merit)"

# (CL-INV) none of this reached a merge path. The observer has no merge authority,
# and an arm that closes beads more aggressively must not acquire one.
eq "$(wc -l < "$TMP/automerge" | tr -d ' ')" "0" \
   "(CL-INV) the close gate ran no merge for any anchor"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
