#!/usr/bin/env bash
# Hermetic test for merge-skill.sh (close-on-land merge skill — the single writer
# of merged-truth). Stubs `gh` (PR state + the real merge) and `gc` (bead-ledger
# list/close/update) on PATH. No live city, Dolt, network, or real pull requests.
#
# The skill is the LANDING path that replaces GitHub auto-merge: for each OPEN
# gating anchor it runs validate -> merge -> record. Covered:
#   (1) ready (base==target, every check_set gate green@head, no child,
#        mergeStateStatus=CLEAN) -> MERGED (gh pr merge --squash) + anchor closed
#        "Merged to <target> at <sha>" + merge_result=merged recorded
#   (1b) NO-GATE: empty check_set + CLEAN -> MERGED (the bug fix — a missing gate
#        marker no longer holds a human-approved CLEAN PR forever)
#   (2) check.codex STALE (green@<old-head>) -> merge HELD (not green at live head)
#   (3) check.codex MISSING but codex in check_set -> merge HELD
#   (4) mergeStateStatus=BLOCKED -> merge HELD (CI/approval not green)
#   (5) mergeStateStatus=BEHIND  -> merge HELD (base moved)
#   (6) open rework child references the PR -> merge HELD (a child holds the land)
#   (7) live base != anchor target (retargeted) -> merge HELD (would land wrong)
#   (8) draft PR  -> skipped (drafts retired)
#   (9) already MERGED -> skipped (the observer records it, not the skill)
#   (10) open rework child PAST the former --limit cap -> merge HELD (the
#        referencing-bead scan is unbounded, --limit=0)
#   (11) metadata.merge_hold=true on the anchor -> merge HELD even when the PR is
#        fully CLEAN and every gate is green (operator gate; before the fix such a
#        CLEAN held PR squash-merged with no operator signal)
#   (12) TWO open anchors claim the same PR (a rework bead leaked into the anchor
#        class, tk-ynz4b): one carries the codex gate (red), the duplicate has an
#        EMPTY check_set + CLEAN PR -> before the fix the gateless duplicate
#        merged the PR, bypassing codex; now EVERY anchor of a multi-anchor PR is
#        HELD until the duplicate is closed/demoted
#   (13) DEPENDENCY-LINKED rework child with NO pr_number of its own -> merge HELD
#        (tk-lgjvg: the gate resolved children by pr_number alone, so a child that
#        carries only branch/source_review_bead was invisible and the gate PASSED)
#   (14) dependency-linked child in status `blocked` -> merge HELD (the live
#        tk-h9pq5/PR#233 shape: the child was blocked + routed to human. The
#        invariant is "all children CLOSED", so every non-closed status holds)
#   (15) pr_number-carrying child in status `blocked` -> merge HELD (the probe asks
#        for every LIVE_STATUSES value, not just open,in_progress)
#   (16) open REVIEW bead attached as a `blocks` dependency OF the anchor (how a
#        signoff gate attaches) -> merge HELD
#   (17) open DOWNSTREAM dependent (up/blocks) + open EPIC PARENT (down/parent-
#        child) -> MERGED. Both are the wrong end of their edge; holding on either
#        deadlocks a healthy anchor forever, which is why both dep probes are
#        direction- AND type-filtered.
#   (18) CLOSED dependency-linked child -> MERGED (a closed child holds nothing)
#   (19) the child probe ERRORS -> merge HELD (fail closed: an empty result from a
#        broken query is indistinguishable from "no children", and reading it as
#        "no children" merges past open rework)
#   (20) a live `blocks` blocker that CARRIES merge_result=pull_request — an
#        upstream PR anchor filed as an explicit merge-ordering block -> merge
#        HELD (tk-je0rk: the merge_result exclusion was applied to the whole
#        holder set, so the one holder shape that carries merge_result BY
#        DEFINITION was deleted and the downstream PR merged past its blocker)
#   (21) a live parent-child CHILD carrying merge_result=pre_open_gate (a child
#        that reached its own PR/pre-open gate) -> merge HELD too. Same rule:
#        provenance decides, and a dependency edge holds regardless of
#        merge_result — only pr_number-swept duplicates are excludable.
#   (22) a holder probe returns a well-formed ARRAY holding a MALFORMED element
#        (metadata is a string) -> merge HELD (tk-qoyly). The old top-level-only
#        shape check passed this array through; the holder filter then aborted on
#        `.metadata.merge_result`, emptied, and read as "no children".
#   (23) every element passes the shape check but one carries a NON-STRING status,
#        which aborts the holder FILTER (ascii_downcase on a number) -> merge HELD.
#        The companion to (22) at the other guard: (22) is caught at the probe
#        boundary, this one only by the filter's own fail-closed branch, so the two
#        cases pin both layers independently.
#   (24) ONE holder returned by BOTH the pr_number probe AND a dependency probe,
#        carrying merge_result -> merge HELD. The provenance-MERGE positive
#        control: dedup must union `_via` (group_by), not keep whichever copy
#        sorted first (unique_by). Demoting such a holder to the pr_number class
#        would re-apply the merge_result exclusion and delete a real holder.
#   (25) a holder probe emits TWO JSON documents, `{}` then a valid array, with a
#        zero exit status -> merge HELD (tk-wkrcy). `jq -e` over a raw STREAM
#        reports only the LAST document's result, so this passed the old check;
#        probe_holders then reads the three payloads positionally out of one
#        slurped stream, and the extra leading document shifted the anchor's real
#        `blocks` blocker off the end. The PR merged past its merge-ordering block.
#   (26) TWO well-formed EMPTY arrays in one payload (`[]` then `[]`) -> merge
#        HELD. Nothing is malformed at all here; the document COUNT is the entire
#        defect, so this case pins the count check on its own.
#   (27) metadata.signoff_dismissed set (the city retracted its OWN blocking
#        review at the re-gate — tk-5niup) + every gate green + CLEAN, but NO
#        external approving review -> merge HELD. This is the fail-OPEN trap:
#        the dismissal is what made the PR CLEAN, and on a repo with no review
#        requirement CLEAN folds no approval at all, so pre-fix the skill
#        squash-merged unverified work on its next idle pass.
#   (27b) same, WITH an external approving review -> MERGED (the requirement is
#        satisfiable, not a permanent hold)
#   (27c) same, but the only APPROVED review is by the acting account itself ->
#        merge HELD (a self-approval is not approval; the city never approves)
#   (28) check_set names `approval` (the explicit opt-in for a rig on an
#        unprotected repo) with no approving review -> merge HELD, and held on
#        the APPROVAL gate — not on a `check.approval` marker no reviewer can
#        ever stamp (the none/off-sentinel trap, applied to approval)
#   (28b) check_set names `approval` and an external approval exists -> MERGED
#   (29) the approval is real and external but pinned to an OLDER commit -> merge
#        HELD. The stale-approval hole: `latestReviews` reports a verdict with no
#        commit, so an approval of a dead head satisfied the gate and, once the
#        city dismissed its own block, unapproved work merged. Approval is
#        head-bound now, like every check.<name>=green@<head> marker.
#   (30) the only approval sits on PAGE 2 of the reviews history -> MERGED. The
#        stub serves page 2 only to a --paginate caller, as GitHub does, so an
#        unpaginated read would strand a PR every human on it has approved.
#   (30b) approved on page 1, the SAME reviewer's later CHANGES_REQUESTED on page
#        2 -> merge HELD. The dangerous half of the pagination bug: truncated, a
#        retracted approval reads as the effective verdict.
#   (31) the anchor's metadata changes AFTER the enumeration snapshot and BEFORE
#        the gates run (signoff_dismissed 19, merge_hold 19b, check.<gate> 19c) ->
#        the gates read the FRESH bead, so the mid-pass write is honored this
#        pass; an unreadable re-read (19d) skips the anchor, fail-closed
#   (32) approval effectiveness per reviewer: a later DISMISSED shadows that
#        reviewer's earlier APPROVED (32), another reviewer's standing
#        CHANGES_REQUESTED vetoes an approval (32b), and a veto the same reviewer
#        superseded with an APPROVED does NOT hold (32c)
#   (33) the merge is bound to the validated head (--match-head-commit), and a
#        head that moved between validation and merge is REFUSED, not landed
#   (34) the fresh re-read must still BE the gating anchor: pr_number cleared
#        (34), the anchor closed (34b), or merge_result cleared (34c) mid-pass ->
#        skipped. An EMPTY fresh pr_number used to pass the mismatch guard and
#        merge against the stale snapshot's PR
#   (35) a paginated reviews read that FAILS after page 1 -> merge held. The
#        pages already streamed parse fine, so only the exit status reveals that
#        the missing tail held a superseding CHANGES_REQUESTED
#   (36) the approver must be TRUSTED, not merely non-self: a read-only
#        collaborator (36) or an account with no resolvable permission (36b) is
#        held; a trusted approval alongside an untrusted one still merges (36c);
#        MERGE_TRUSTED_APPROVERS replaces the permission probe as the policy
#        (24d), exhaustively (24e), and independently of the list's length (24f)
#   (37) the in-flight-child gate FAILS CLOSED on a ledger it cannot read: a
#        non-zero `gc bd list` (37) and an error OBJECT served at exit 0 (37b)
#        both HOLD, where before each looked exactly like "no child". It also
#        sees every non-closed owner — a `blocked` child (37c) — and every key a
#        bead names a PR with, including fork_pr (25d)
#   (38) a duplicate gating anchor that appears only in the LIVE ledger, after
#        the enumeration snapshot -> merge HELD. The one-anchor-per-PR guard is
#        recomputed live; from the snapshot it could not see the duplicate, and a
#        duplicate carries merge_result so the child hold could not either
#   (39) a long check_set naming `approval` still arms the approval gate. The
#        detector piped jq into `grep -q`, which exits at the first match and
#        SIGPIPEs jq under pipefail, so `approval` read as absent and a CLEAN
#        unprotected-repo PR merged unapproved
#   (40) a city CHANGES_REQUESTED dismissed BY HAND on github.com — no
#        signoff_dismissed marker, `approval` not in check_set, codex green at
#        the live head, CLEAN — still requires an external approval. The
#        requirement was armed only from bead-side markers, which record only
#        the dismissals the city performed itself, so a manual cleanup merged
#        unapproved work. (40c) it must not over-hold: the same PR WITH a
#        trusted approval lands. (28d) the dismissal is found on page 2 too.
#        (28e) with no resolvable self-login the arm falls back to any dismissal
#   (41) an ORDINARY codex-only anchor — check_set `codex`, check.codex green at
#        the live head, no `approval` member, no signoff_dismissed, nothing
#        dismissed in the history — with a standing external CHANGES_REQUESTED
#        -> merge HELD. The veto was enforced only inside the armed approval
#        branch, so this anchor never consulted it and, CLEAN through the
#        objection on an unprotected repo, squash-merged past a human's explicit
#        "not this". (41b) it must not over-hold: the same shape with the veto
#        SUPERSEDED by that reviewer's own later APPROVED lands, which also pins
#        the veto to each reviewer's LATEST verdict rather than to any
#        CHANGES_REQUESTED anywhere in the history
#   (INV) `gh pr merge` is reached for EXACTLY the fully-validated PRs — no
#         other anchor is merged, and every attempt is head-matched.
#   (5c) convergence: a merged+closed anchor leaves the gating set, so a second
#        pass does not re-merge it.
#   (FS) field-shape guard: the skill requests only gh-supported --json fields.
#
# PR IDENTITY (review tk-sdqwh finding #2). A bead names its PR by NUMBER, and a
# number names a different pull request in every other repository. check-set-heal.sh
# certifies that identity before it exposes a recovered anchor — but in ANOTHER
# process, whose gh repository context this one does not inherit, and the anchors it
# recovers are pr_number-only until it backfills the certified pr_url. So the full
# path is exercised HERE, after recovery, with the gh default/host drifted:
#   (ID1) DRIFT: gh's default repo is moved to a stranger's. The read is PINNED with
#         `--repo` to the origin-derived repository, so the right PR still answers
#         and still merges — the drift is a no-op, which is the whole point.
#   (ID2) IGNOREPIN: a gh that does NOT honour `--repo` (a redirect after a transfer
#         or rename, an older gh, a wrapper) serves the foreign same-numbered PR
#         anyway. Pinning alone is then no defence: the returned URL must be
#         COMPARED against the expectation, and the merge HELD.
#   (ID2b) HOSTDRIFT: GH_HOST points at another GitHub host, where the same
#         `<owner>/<repo>` is a DIFFERENT repository. The pin is host-qualified, so
#         the read still lands on ours.
#   (ID3) URLMISMATCH: the anchor's own certified pr_url names a different pull
#         request from the one that answered -> merge HELD.
#   (ID4) REPOFAIL: this checkout's origin cannot be resolved at all -> NOTHING is
#         merged this pass (fail closed; a wrong merge cannot be retried away).
#   (ID6-ID8) THE REST PATHS, which `--repo` does not reach: `gh api` takes the
#         repository in the path and the host in `--hostname`, and the approval gate
#         reads BOTH a review history and a collaborator permission that way. Left
#         ambient, a veto on OUR PR goes unseen (ID6), an approval that exists only
#         in gh's current repository satisfies the gate (ID7), and write access held
#         only THERE makes an approver trusted HERE (ID8). All three MERGE pre-fix.
#         (ID9) is the control: undrifted, the same fixtures still merge.
#   (SYNC) the `pr_nums_here` identity resolver is duplicated across two scripts and
#         the signoff template by design; the copies are asserted identical, because
#         one of them drifting narrow is exactly what tk-5knqi finding #2 was.
#
# HEAD IDENTITY (review tk-pka2d finding #2). Everything above certifies where the
# pull request LIVES. A PR opened INTO this repository FROM a fork lives here too:
# our host, our owner, our repo, our number, one of OUR urls — so every check above
# passes on it, and the skill would squash-merge a stranger's head onto the target
# under our anchor's gates. The head is the half a same-repo URL cannot answer:
#   (HD1) FORK: same branch NAME, head repository `mallory/repo` -> merge HELD.
#   (HD2) SELFCONTRA: head repository is ours AND isCrossRepository=true — the two
#         halves of the identity contradict each other -> merge HELD (unestablished,
#         not a tie to break).
#   (HD3) NOHEAD: headRepository/headRepositoryOwner are null (a deleted head repo, a
#         schema shift) -> merge HELD; unreadable must not land.
#   (HD4) BRANCHMISMATCH: right repository, right head repository, but the PR is
#         opened from a branch the anchor does not record -> merge HELD.
#   (HD5) HEADOK: the positive control — anchor branch == PR head branch, head
#         repository ours, isCrossRepository=false, CLEAN -> MERGED. Without it the
#         four holds above could all pass by the checks rejecting everything.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/merge-skill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }
has() { grep -q "$1" "$2" 2>/dev/null; }
# Assert that PATTERN (a BRE, same as `has`) appears in a CAPTURED STRING.
#
# NOT `printf '%s\n' "$OUT" | grep -q PATTERN`, which is what every assertion
# here used to be (tk-tmefn). This file runs under `set -euo pipefail`, and
# `grep -q` exits at its FIRST match — closing the pipe under a `printf` still
# writing the rest of a large captured output. printf takes SIGPIPE, the
# pipeline reports 141, and the assertion reads FALSE even though the line IS
# present; `set -e` then aborts the whole run mid-file. Whether it fires depends
# on where the match sits relative to the ~64KB pipe buffer, so the suite failed
# intermittently on output SIZE rather than on behavior — a phantom red against
# correct code. This branch removes that exact class from merge-skill.sh and
# check-set-heal.sh; a harness that still carries it cannot be trusted to judge
# the fix.
#
# A here-string is a REDIRECT, not a pipeline: bash hands grep a file it reads to
# EOF, no upstream writer exists to be signalled, and the exit status is grep's
# alone. Match semantics are unchanged from the pipelines this replaced.
hasin() { grep -q "$2" <<< "$1"; }

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source):
#   id|pr_number|merged_target|check_set|check.codex|merge_hold|signoff_dismissed|pr_url|branch|fork_pr|fork_pr_url
# The 5th column is the anchor's per-gate marker value for check.codex; a
# "green@<oid>" value means "the codex gate passed at commit <oid>". bead-NOGATE
# has an empty check_set (declares no gates) and no marker. The 6th column is
# metadata.merge_hold (an operator gate); rows that omit it read as "" (no hold),
# so only bead-HOLD carries it. The 7th is metadata.signoff_dismissed (tk-5niup):
# set when the re-gate retracted the city's OWN blocking review, which arms the
# explicit approval gate for that anchor no matter what check_set says.
# so only bead-HOLD carries it. The 8th is metadata.pr_url — ABSENT on most rows on
# purpose: a pr_number-only anchor is exactly the shape check-set-heal.sh's recovery
# produces before it backfills the certified URL, so the pinned read is the only
# thing standing between these anchors and a foreign same-numbered PR.
#
# The 9th is metadata.branch, and it is absent on every legacy row for the same
# reason: a recovered anchor records no branch, so the head-BRANCH comparison must
# not fire on it (only the two repository halves govern such a row). Only the head
# identity cases below carry one.
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex|green@HEAD301
bead-STALE|302|main|codex|green@STALE302
bead-NOSIGN|303|main|codex|
bead-BLOCKED|304|main|codex|green@HEAD304
bead-CHILD|305|main|codex|green@HEAD305
bead-RETARGET|306|main|codex|green@HEAD306
bead-DRAFT|307|main|codex|green@HEAD307
bead-MERGED|308|main|codex|green@HEAD308
bead-BEHIND|309|main|codex|green@HEAD309
bead-CAPCHILD|310|main|codex|green@HEAD310
bead-NOGATE|311|main||
bead-HOLD|312|main|codex|green@HEAD312|true
bead-DUPGATED|313|main|codex|
bead-DUPFREE|313|main||
bead-OPTOUT|314|main|none|
bead-DEPCHILD|315|main|codex|green@HEAD315
bead-BLOCKEDKID|316|main|codex|green@HEAD316
bead-PRBLOCKED|317|main|codex|green@HEAD317
bead-BLOCKGATE|318|main|codex|green@HEAD318
bead-DOWNSTREAM|319|main|codex|green@HEAD319
bead-CLOSEDCHILD|320|main|codex|green@HEAD320
bead-PROBEFAIL|321|main|codex|green@HEAD321
bead-BLOCKEDBYPR|322|main|codex|green@HEAD322
bead-KIDANCHOR|323|main|codex|green@HEAD323
bead-BADSHAPE|324|main|codex|green@HEAD324
bead-BADSTATUS|325|main|codex|green@HEAD325
bead-BOTHSRC|326|main|codex|green@HEAD326
bead-MULTIDOC|327|main|codex|green@HEAD327
bead-MULTIEMPTY|328|main|codex|green@HEAD328
bead-DISMISSED|329|main|codex|green@HEAD329||900@HEAD329
bead-DISMISSED-OK|330|main|codex|green@HEAD330||901@HEAD330
bead-SELFAPPROVE|331|main|codex|green@HEAD331||902@HEAD331
bead-APPROVALSET|332|main|codex,approval|green@HEAD332
bead-APPROVALSET-OK|333|main|codex,approval|green@HEAD333
bead-STALEAPPROVE|334|main|codex|green@HEAD334||903@HEAD334
bead-PAGE2|335|main|codex,approval|green@HEAD335
bead-LATERCR|336|main|codex,approval|green@HEAD336
bead-RACEDISMISS|337|main|codex|green@HEAD337
bead-RACEHOLD|338|main|codex|green@HEAD338
bead-RACEGATE|339|main|codex|green@HEAD339
bead-SHOWFAIL|340|main|codex|green@HEAD340
bead-DISMISSSHADOW|341|main|codex,approval|green@HEAD341
bead-VETO|342|main|codex,approval|green@HEAD342
bead-CRAPPROVE|343|main|codex,approval|green@HEAD343
bead-HEADMOVE|344|main|codex|green@HEAD344
bead-RACENOPR|345|main|codex|green@HEAD345
bead-RACECLOSED|346|main|codex|green@HEAD346
bead-RACEUNPARK|347|main|codex|green@HEAD347
bead-APIFAIL|348|main|codex,approval|green@HEAD348
bead-UNTRUSTED|349|main|codex,approval|green@HEAD349
bead-BOTAPPROVE|350|main|codex,approval|green@HEAD350
bead-MIXEDAPPROVE|351|main|codex,approval|green@HEAD351
bead-QUERYFAIL|352|main|codex|green@HEAD352
bead-PROBEOBJ|353|main|codex|green@HEAD353
bead-BLOCKEDCHILD|354|main|codex|green@HEAD354
bead-FORKCHILD|355|main|codex|green@HEAD355
bead-LIVEDUP|356|main|codex|green@HEAD356
bead-HANDDISMISS|358|main|codex|green@HEAD358
bead-HANDDISMISS-OK|359|main|codex|green@HEAD359
bead-HANDDISMISS-P2|360|main|codex|green@HEAD360
bead-CODEXVETO|361|main|codex|green@HEAD361
bead-CODEXVETO-OK|362|main|codex|green@HEAD362
bead-URLMISMATCH|363|main|codex|green@HEAD363|||https://github.com/acme/OTHER/pull/363
bead-XDUPOK|364|main|codex|green@HEAD364
bead-XDUPFOREIGN|364|main|codex|green@HEAD364|||https://otherhost/acme/repo/pull/364
bead-XCHILDFOREIGN|365|main|codex|green@HEAD365
bead-XCHILDSAME|366|main|codex|green@HEAD366
bead-XCHILDFAIL|367|main|codex|green@HEAD367
bead-DEPFOREIGN|373|main|codex|green@HEAD373
bead-FORK|368|main|codex|green@HEAD368||||polecat/bead-FORK
bead-SELFCONTRA|369|main|codex|green@HEAD369||||polecat/bead-SELFCONTRA
bead-NOHEAD|370|main|codex|green@HEAD370||||polecat/bead-NOHEAD
bead-BRANCHMISMATCH|371|main|codex|green@HEAD371||||polecat/bead-BRANCHMISMATCH
bead-HEADOK|372|main|codex|green@HEAD372||||polecat/bead-HEADOK
bead-FINALHOLD|374|main|codex|green@HEAD374
bead-FINALGATE|375|main|codex|green@HEAD375
bead-FINALCLOSED|376|main|codex|green@HEAD376
bead-FINALPR|377|main|codex|green@HEAD377
bead-FINALFAIL|378|main|codex|green@HEAD378
bead-FINALOK|379|main|codex|green@HEAD379
bead-FORKKEYED||main|codex|green@HEAD380|||||380
bead-FORKURL||main|codex|green@HEAD381||||||https://github.com/acme/repo/pull/381
bead-FORKFOREIGN||main|codex|green@HEAD382||||||https://otherhost/acme/repo/pull/382
bead-TWOKEYS|383|main|codex|green@HEAD383|||||384
bead-FINALDISMISS|385|main|codex|green@HEAD385
bead-FINALRETARGET|386|main|codex|green@HEAD386
bead-FINALURL|387|main|codex|green@HEAD387
bead-FINALBRANCH|388|main|codex|green@HEAD388
A

# (39) The long-check_set anchor, appended programmatically because its check_set
# is thousands of gates wide. Length is the whole point: the pre-fix detector
# piped jq into `grep -qxF approval`, and `grep -q` exits at its FIRST match —
# closing the pipe under jq while jq is still writing the gates that FOLLOW
# `approval`. jq then takes SIGPIPE, the pipeline reports 141 under `set -o
# pipefail`, and the trailing `&& needs_approval=1` never runs. Below ~64KB of jq
# output (the pipe buffer) jq writes once and exits before grep does, so the race
# is invisible; past it the miss is reliable — measured 4/10 at 2k gates, 10/10 at
# 10k. This fixture therefore uses a length that makes the failure DETERMINISTIC
# rather than one that looks like a plausible rig config: the bug class is what is
# being pinned, and the fix (in-shell matching, no pipeline) makes length
# irrelevant. Every gate is spelled `codex` so the one marker the stub serves
# satisfies them all and the pass actually reaches the approval gate.
LONGSET="approval"
for _i in $(seq 1 10000); do LONGSET="$LONGSET,codex"; done
printf 'bead-LONGSET|357|main|%s|green@HEAD357\n' "$LONGSET" >> "$TMP/anchors"

# The anchor state as a LATER `gc bd show` reads it — same columns plus an
# optional 8th (status) and 9th (merge_result), and it OVERRIDES $TMP/anchors for
# the per-anchor metadata re-read the skill performs after the PR-state read.
# This is the concurrency seam: the signoff path writes the anchor (stamps
# check.<gate>, records signoff_dismissed, then dismisses the GitHub review) WHILE
# the skill is mid-pass, so the enumeration snapshot and the live bead disagree.
# Only anchors listed here differ from their snapshot row. A `-` in columns 8/9
# means the field is EMPTY on the live bead (an omitted column keeps the normal
# open + merge_result=pull_request gating shape).
#   337 signoff_dismissed appears only in the fresh read -> approval now required
#   338 merge_hold appears only in the fresh read        -> operator gate now set
#   339 check.codex went STALE in the fresh read         -> gate re-gated
#   345 pr_number CLEARED in the fresh read              -> anchor no longer claims the PR
#   346 the anchor CLOSED mid-pass                       -> no longer a gating anchor
#   347 merge_result cleared (un-parked mid-pass)        -> no longer PR-parked
cat > "$TMP/anchors-fresh" <<'AF'
bead-RACEDISMISS|337|main|codex|green@HEAD337||904@HEAD337
bead-RACEHOLD|338|main|codex|green@HEAD338|true
bead-RACEGATE|339|main|codex|green@OLD339
bead-RACENOPR||main|codex|green@HEAD345
bead-RACECLOSED|346|main|codex|green@HEAD346|||||||closed
bead-RACEUNPARK|347|main|codex|green@HEAD347|||||||open|-
AF

# THE ANCHOR AS IT IS THE INSTANT BEFORE `gh pr merge` — served from the SECOND
# `gc bd show` of that id onwards (review tk-tbacg finding #1). Same columns as
# $TMP/anchors-fresh. Every row here passed EVERY gate on the first read: the PR is
# OPEN, non-draft, CLEAN, the codex marker is green at the live head, no child holds
# it. What changed is only what another writer did in the window between the last
# gate and the merge call — a window made of the PR read, the referencing-bead
# query, the holder probes and the reviews history, every one a network or ledger
# round-trip. `--match-head-commit` cannot see any of it: the head never moved.
#   374 merge_hold set (an operator parked the anchor mid-pass)
#   375 check.codex advanced to a DIFFERENT head (a re-gate landed)
#   376 the anchor was closed
#   377 the anchor was retargeted onto another PR
#   379 UNCHANGED — the control: the terminal re-read must not hold a merge that is
#       still authorized, or it would just be a second way to never merge.
#
# 385-388 are the four fields the terminal re-read did NOT ask about before review
# tk-78ty5 finding #2, and they are here because NONE of them move the head — so
# `--match-head-commit` passes on every one and the merge fires against a bead that
# no longer authorizes it. Each row is IDENTICAL to its first-read shape except for
# the single field under test:
#   385 signoff_dismissed APPEARS — the signoff retracted the city's own blocking
#       review after the approval gate already decided this PR needed no external
#       approval. The marker exists to ARM that requirement; arriving late means it
#       armed nothing.
#   386 merged_target repointed to integration/foo while the PR's live base is
#       still main — a SAME-HEAD retarget, invisible to the head-match, landing the
#       merge on a branch no gate in this pass looked at.
#   387 pr_url backfilled to ANOTHER repository's #387. First read carries no
#       pr_url at all (the pr_number-only shape), so the identity gate had nothing
#       to compare and passed by absence; the repair is what makes it comparable.
#   388 branch repaired to somebody else's. The PR is opened from
#       polecat/bead-FINALBRANCH, so first read (no branch recorded) passed the
#       head-branch gate by absence and the terminal read must catch the conflict.
cat > "$TMP/anchors-final" <<'AN'
bead-FINALHOLD|374|main|codex|green@HEAD374|true
bead-FINALGATE|375|main|codex|green@MOVED375
bead-FINALCLOSED|376|main|codex|green@HEAD376|||||||closed
bead-FINALPR|377|main|codex|green@HEAD377
bead-FINALOK|379|main|codex|green@HEAD379
bead-FINALDISMISS|385|main|codex|green@HEAD385||950@HEAD385
bead-FINALRETARGET|386|integration/foo|codex|green@HEAD386
bead-FINALURL|387|main|codex|green@HEAD387|||https://github.com/acme/OTHER/pull/387
bead-FINALBRANCH|388|main|codex|green@HEAD388||||polecat/somebody-else
AN

# 377's terminal read must claim a DIFFERENT PR than the one validated. Appended
# rather than written inline because the row it needs (pr_number=999) would
# otherwise be indistinguishable from a typo in the table above.
printf 'bead-FINALPR|999|main|codex|green@HEAD377\n' > "$TMP/anchors-final.tmp"
grep -v '^bead-FINALPR|' "$TMP/anchors-final" > "$TMP/anchors-final.keep"
cat "$TMP/anchors-final.keep" "$TMP/anchors-final.tmp" > "$TMP/anchors-final"

# An anchor whose SECOND `gc bd show` fails while the first succeeded: the terminal
# re-read is the unreadable one. A merge that cannot re-confirm its authorization is
# the one act this pass can never retract, so it must HOLD rather than proceed on
# metadata read a dozen round-trips ago.
SHOWFAIL_FINAL_IDS="bead-FINALFAIL"
mkdir -p "$TMP/showcount"

# Anchors whose `gc bd show` FAILS outright (empty output), to prove the re-read
# is fail-closed: an anchor whose live metadata cannot be read is skipped, never
# validated against the stale snapshot the race is about.
SHOWFAIL_IDS="bead-SHOWFAIL"

# PRs whose head MOVED after validation, as `--match-head-commit` sees it:
# pr|actual_head. The gh stub refuses a merge whose --match-head-commit does not
# equal the actual head, exactly as GitHub does.
cat > "$TMP/headmove" <<'HM'
344|NEWHEAD344
HM

# PR states (gh pr view source):
#   pr|state|isDraft|baseRefName|headRefOid|mergeStateStatus|mergeable|mergeOid|reviewDecision
# reviewDecision appears in the approval gate's hold message only. The approval
# EVIDENCE lives in $TMP/reviews below, because it must carry the commit each
# verdict was attached to — `gh pr view --json latestReviews` carries none, which
# is exactly why the gate cannot be built on it (tk-5niup).
#   301 OPEN, base==target, check.codex green@head, CLEAN -> MERGED + recorded
#   302 OPEN, check.codex green@old-head (stale)  -> HELD
#   303 OPEN, codex in check_set but no marker    -> HELD
#   304 OPEN, check green@head BUT mergeState BLOCKED -> HELD
#   305 OPEN, check green@head, CLEAN, open child -> HELD
#   306 OPEN, base=integration/foo != main        -> HELD (retargeted)
#   307 OPEN, draft                               -> skipped
#   308 MERGED already                            -> skipped (observer's job)
#   309 OPEN, check green@head BUT mergeState BEHIND -> HELD
#   310 OPEN, check green@head, CLEAN, open child past former cap -> HELD
#   311 OPEN, empty check_set (no gate), CLEAN    -> MERGED (the bug fix)
#   312 OPEN, check green@head, CLEAN BUT merge_hold=true -> HELD (operator gate)
#   313 OPEN, CLEAN, claimed by TWO anchors (bead-DUPGATED codex-red +
#       bead-DUPFREE gateless) -> HELD via both (one-anchor-per-PR, tk-ynz4b);
#       pre-fix the gateless duplicate merged it, bypassing the codex gate
#   314 OPEN, CLEAN, check_set="none" (the EXPLICIT opt-out sentinel, tk-i48ca)
#       -> MERGED. The sentinel is now STAMPED on the anchor instead of being
#       collapsed to "", so it arrives here as a gate NAME; if the gate-splitting
#       did not drop it, a gateless rig would hold forever on `check.none` — a
#       marker no reviewer can stamp.
#   315 OPEN, CLEAN, gate green — open dep-linked child, NO pr_number  -> HELD
#   316 OPEN, CLEAN, gate green — dep-linked child in status `blocked` -> HELD
#   317 OPEN, CLEAN, gate green — pr_number child in status `blocked`  -> HELD
#   318 OPEN, CLEAN, gate green — open review bead BLOCKING the anchor -> HELD
#   319 OPEN, CLEAN, gate green — only wrong-end edges (downstream dependent,
#       epic parent)                                                   -> MERGED
#   320 OPEN, CLEAN, gate green — dep-linked child already CLOSED      -> MERGED
#   321 OPEN, CLEAN, gate green — the child probe errors               -> HELD
#   322 OPEN, CLEAN, gate green — `blocks` blocker carrying
#       merge_result=pull_request (an upstream PR ordered ahead)       -> HELD
#   323 OPEN, CLEAN, gate green — parent-child child carrying
#       merge_result=pre_open_gate                                     -> HELD
#   329 OPEN, gate green, CLEAN, anchor carries signoff_dismissed, NO approving
#       review -> HELD (tk-5niup: the dismissal is what made it CLEAN)
#   330 same as 329 but johnzook APPROVED at the live head -> MERGED
#   331 same as 329 but the ACTING account approved -> HELD (self-approval)
#   332 OPEN, gate green, CLEAN, check_set="codex,approval", no approval -> HELD
#   333 same as 332 but johnzook APPROVED at the live head -> MERGED
#   334 same as 330 but the approval is pinned to an OLDER commit -> HELD
#   335 approval exists only on PAGE 2 of the reviews history -> MERGED
#   336 approval on page 1, the SAME reviewer's later CHANGES_REQUESTED on page
#       2 -> HELD (the later verdict is the effective one)
#   337 CLEAN, gate green, snapshot has NO signoff_dismissed but the live bead
#       does -> HELD (the mid-pass dismissal race; pre-fix it merged unapproved)
#   338 CLEAN, gate green, merge_hold appears only in the live bead -> HELD
#   339 CLEAN, snapshot marker green@head but the live bead's went stale -> HELD
#   340 CLEAN, gate green, but `gc bd show` FAILS for its anchor -> skipped
#   341 CLEAN, external APPROVED at the head then that review DISMISSED -> HELD
#   342 CLEAN, one external APPROVED at the head, ANOTHER external reviewer's
#       latest is CHANGES_REQUESTED -> HELD (an approval is not a veto override)
#   343 CLEAN, external CHANGES_REQUESTED then the SAME reviewer APPROVED at the
#       head -> MERGED (the guard holds vetoes, it does not over-hold)
#   344 CLEAN, every gate green, but the head MOVED before the merge call ->
#       HELD (GitHub refuses the --match-head-commit merge)
#   358 THE tk-tmefn HOLE: check_set is plain `codex` (NOT approval), the anchor
#       carries NO signoff_dismissed, check.codex is green at the live head, and
#       the PR is CLEAN — but the city's own CHANGES_REQUESTED was dismissed BY
#       HAND on github.com. Nothing bead-side records that, and CLEAN is only
#       true because WE were the block that someone lifted, so pre-fix this
#       merged with no approval owed to anyone. -> HELD. The later self COMMENT
#       (11:00, after the 10:00 dismissal) is the shadowing case: a
#       latest-review-per-author reading would let it hide the dismissal, which
#       is why the arm counts the WHOLE history
#   359 same hand-dismissal as 358 but johnzook (admin) APPROVED at the live head
#       -> MERGED. The arm must not over-hold: a dismissal makes an approval
#       REQUIRED, not impossible
#   360 same hand-dismissal as 358 with the DISMISSED row on PAGE 2 -> HELD. The
#       tail is where a dismissal hides from an unpaginated read, and missing it
#       fails OPEN
#   361 THE tk-bdfww HOLE: the most ORDINARY anchor there is — check_set plain
#       `codex`, check.codex green at the live head, no `approval` member, no
#       signoff_dismissed, nothing dismissed in the history, no open child — and
#       one external human's standing CHANGES_REQUESTED. The veto was read only
#       inside the armed approval branch, which this anchor never enters, so
#       nothing looked at the objection; the repo is unprotected, so CLEAN is
#       true straight through it, and the pass squash-merged past a human's
#       explicit "not this". -> HELD, on the veto
#   362 same shape as 361 but the objection is SUPERSEDED by that same
#       reviewer's later APPROVED -> MERGED. The veto is each reviewer's LATEST
#       verdict, not "a CHANGES_REQUESTED appears somewhere in the history"; a
#       hoisted check written the naive way would strand every PR that ever took
#       a review round, which is a worse bug than the one being closed. Note the
#       gate here is codex ALONE — the approval is not required, it is only what
#       withdraws the objection
#   368 OPEN, CLEAN, every gate green — but opened from FORK mallory/repo's branch
#       of the SAME NAME -> HELD (HD1). Pre-fix this squash-merged a stranger's head.
#   369 OPEN, CLEAN, head repository ours BUT isCrossRepository=true -> HELD (HD2)
#   370 OPEN, CLEAN, headRepository/headRepositoryOwner null -> HELD (HD3)
#   371 OPEN, CLEAN, ours, but opened from 'polecat/somebody-else' while the anchor
#       records 'polecat/bead-BRANCHMISMATCH' -> HELD (HD4)
#   372 OPEN, CLEAN, ours, head branch == the anchor's recorded branch -> MERGED (HD5)
#
# Columns 9-11 (headRefName|headRepo|isCrossRepository) are the head identity. They
# are OMITTED on every legacy row and default to "ours" in the stub — so those rows
# keep exercising what they were written to exercise, and only the cases below turn
# the head into the variable.
cat > "$TMP/prs" <<'P'
301|OPEN|false|main|HEAD301|CLEAN|MERGEABLE|a301c0ffee123456
302|OPEN|false|main|HEAD302|CLEAN|MERGEABLE|
303|OPEN|false|main|HEAD303|CLEAN|MERGEABLE|
304|OPEN|false|main|HEAD304|BLOCKED|MERGEABLE|
305|OPEN|false|main|HEAD305|CLEAN|MERGEABLE|
306|OPEN|false|integration/foo|HEAD306|CLEAN|MERGEABLE|
307|OPEN|true|main|HEAD307|CLEAN|MERGEABLE|
308|MERGED|false|main|HEAD308|CLEAN|MERGEABLE|d308dead00beef11
309|OPEN|false|main|HEAD309|BEHIND|MERGEABLE|
310|OPEN|false|main|HEAD310|CLEAN|MERGEABLE|
311|OPEN|false|main|HEAD311|CLEAN|MERGEABLE|b311c0ffee654321
312|OPEN|false|main|HEAD312|CLEAN|MERGEABLE|
313|OPEN|false|main|HEAD313|CLEAN|MERGEABLE|
314|OPEN|false|main|HEAD314|CLEAN|MERGEABLE|e314f00d5add1e00
315|OPEN|false|main|HEAD315|CLEAN|MERGEABLE|
316|OPEN|false|main|HEAD316|CLEAN|MERGEABLE|
317|OPEN|false|main|HEAD317|CLEAN|MERGEABLE|
318|OPEN|false|main|HEAD318|CLEAN|MERGEABLE|
319|OPEN|false|main|HEAD319|CLEAN|MERGEABLE|f319c0ffee333333
320|OPEN|false|main|HEAD320|CLEAN|MERGEABLE|a320c0ffee444444
321|OPEN|false|main|HEAD321|CLEAN|MERGEABLE|
322|OPEN|false|main|HEAD322|CLEAN|MERGEABLE|
323|OPEN|false|main|HEAD323|CLEAN|MERGEABLE|
324|OPEN|false|main|HEAD324|CLEAN|MERGEABLE|
325|OPEN|false|main|HEAD325|CLEAN|MERGEABLE|
326|OPEN|false|main|HEAD326|CLEAN|MERGEABLE|
327|OPEN|false|main|HEAD327|CLEAN|MERGEABLE|
328|OPEN|false|main|HEAD328|CLEAN|MERGEABLE|
329|OPEN|false|main|HEAD329|CLEAN|MERGEABLE||
330|OPEN|false|main|HEAD330|CLEAN|MERGEABLE|f330c0ffee111111|APPROVED
331|OPEN|false|main|HEAD331|CLEAN|MERGEABLE||
332|OPEN|false|main|HEAD332|CLEAN|MERGEABLE||
333|OPEN|false|main|HEAD333|CLEAN|MERGEABLE|a333c0ffee222222|APPROVED
334|OPEN|false|main|HEAD334|CLEAN|MERGEABLE||APPROVED
335|OPEN|false|main|HEAD335|CLEAN|MERGEABLE|c335c0ffee333333|APPROVED
336|OPEN|false|main|HEAD336|CLEAN|MERGEABLE||CHANGES_REQUESTED
337|OPEN|false|main|HEAD337|CLEAN|MERGEABLE||
338|OPEN|false|main|HEAD338|CLEAN|MERGEABLE||
339|OPEN|false|main|HEAD339|CLEAN|MERGEABLE||
340|OPEN|false|main|HEAD340|CLEAN|MERGEABLE||
341|OPEN|false|main|HEAD341|CLEAN|MERGEABLE||APPROVED
342|OPEN|false|main|HEAD342|CLEAN|MERGEABLE||CHANGES_REQUESTED
343|OPEN|false|main|HEAD343|CLEAN|MERGEABLE|b343c0ffee444444|APPROVED
344|OPEN|false|main|HEAD344|CLEAN|MERGEABLE|c344c0ffee555555|
345|OPEN|false|main|HEAD345|CLEAN|MERGEABLE|d345c0ffee666666|
346|OPEN|false|main|HEAD346|CLEAN|MERGEABLE|e346c0ffee777777|
347|OPEN|false|main|HEAD347|CLEAN|MERGEABLE|f347c0ffee888888|
348|OPEN|false|main|HEAD348|CLEAN|MERGEABLE|a348c0ffee999999|APPROVED
349|OPEN|false|main|HEAD349|CLEAN|MERGEABLE|b349c0ffeeaaaaaa|APPROVED
350|OPEN|false|main|HEAD350|CLEAN|MERGEABLE|c350c0ffeebbbbbb|APPROVED
351|OPEN|false|main|HEAD351|CLEAN|MERGEABLE|d351c0ffeecccccc|APPROVED
352|OPEN|false|main|HEAD352|CLEAN|MERGEABLE|a352c0ffeeddddd1|
353|OPEN|false|main|HEAD353|CLEAN|MERGEABLE|b353c0ffeeddddd2|
354|OPEN|false|main|HEAD354|CLEAN|MERGEABLE|c354c0ffeeddddd3|
355|OPEN|false|main|HEAD355|CLEAN|MERGEABLE|d355c0ffeeddddd4|
356|OPEN|false|main|HEAD356|CLEAN|MERGEABLE|e356c0ffeeddddd5|
357|OPEN|false|main|HEAD357|CLEAN|MERGEABLE|f357c0ffeeddddd6|
358|OPEN|false|main|HEAD358|CLEAN|MERGEABLE|a358c0ffeeddddd7|
359|OPEN|false|main|HEAD359|CLEAN|MERGEABLE|b359c0ffeeddddd8|APPROVED
360|OPEN|false|main|HEAD360|CLEAN|MERGEABLE|c360c0ffeeddddd9|
361|OPEN|false|main|HEAD361|CLEAN|MERGEABLE|d361c0ffeedddd10|CHANGES_REQUESTED
362|OPEN|false|main|HEAD362|CLEAN|MERGEABLE|e362c0ffeedddd11|APPROVED
363|OPEN|false|main|HEAD363|CLEAN|MERGEABLE|
364|OPEN|false|main|HEAD364|CLEAN|MERGEABLE|a364c0ffee111111
365|OPEN|false|main|HEAD365|CLEAN|MERGEABLE|a365c0ffee222222
366|OPEN|false|main|HEAD366|CLEAN|MERGEABLE|
367|OPEN|false|main|HEAD367|CLEAN|MERGEABLE|
368|OPEN|false|main|HEAD368|CLEAN|MERGEABLE|f368c0ffee000001||polecat/bead-FORK|mallory/repo|true
369|OPEN|false|main|HEAD369|CLEAN|MERGEABLE|f369c0ffee000002||polecat/bead-SELFCONTRA|acme/repo|true
370|OPEN|false|main|HEAD370|CLEAN|MERGEABLE|f370c0ffee000003||polecat/bead-NOHEAD|-|false
371|OPEN|false|main|HEAD371|CLEAN|MERGEABLE|f371c0ffee000004||polecat/somebody-else|acme/repo|false
372|OPEN|false|main|HEAD372|CLEAN|MERGEABLE|a372c0ffee000005||polecat/bead-HEADOK|acme/repo|false
373|OPEN|false|main|HEAD373|CLEAN|MERGEABLE|
374|OPEN|false|main|HEAD374|CLEAN|MERGEABLE|a374c0ffee000011
375|OPEN|false|main|HEAD375|CLEAN|MERGEABLE|a375c0ffee000012
376|OPEN|false|main|HEAD376|CLEAN|MERGEABLE|a376c0ffee000013
377|OPEN|false|main|HEAD377|CLEAN|MERGEABLE|a377c0ffee000014
378|OPEN|false|main|HEAD378|CLEAN|MERGEABLE|a378c0ffee000015
379|OPEN|false|main|HEAD379|CLEAN|MERGEABLE|a379c0ffee000016
380|OPEN|false|main|HEAD380|CLEAN|MERGEABLE|a380c0ffee000017
381|OPEN|false|main|HEAD381|CLEAN|MERGEABLE|a381c0ffee000018
382|OPEN|false|main|HEAD382|CLEAN|MERGEABLE|a382c0ffee000019
383|OPEN|false|main|HEAD383|CLEAN|MERGEABLE|a383c0ffee000020
384|OPEN|false|main|HEAD384|CLEAN|MERGEABLE|a384c0ffee000021
385|OPEN|false|main|HEAD385|CLEAN|MERGEABLE|a385c0ffee000022
386|OPEN|false|main|HEAD386|CLEAN|MERGEABLE|a386c0ffee000023
387|OPEN|false|main|HEAD387|CLEAN|MERGEABLE|a387c0ffee000024
388|OPEN|false|main|HEAD388|CLEAN|MERGEABLE|a388c0ffee000025||polecat/bead-FINALBRANCH|acme/repo|false
P

# PR review history (the REST `pulls/N/reviews` source — the approval gate's real
# evidence, because each row carries the COMMIT its verdict was attached to):
#   pr|review_id|login|state|commit_id|submitted_at|page
# `page` models GitHub's paging: a row on page >1 is returned ONLY when the caller
# passes --paginate. That is the seam for the pagination regression — an
# unpaginated read sees page 1 and nothing else, exactly as against real GitHub.
# zook-bot is the acting account (FAKE_SELF_LOGIN); johnzook is an external human.
cat > "$TMP/reviews" <<'R'
330|8000|zook-bot|COMMENTED|HEAD330|2026-07-30T09:00:00Z|1
330|8001|johnzook|APPROVED|HEAD330|2026-07-30T10:00:00Z|1
331|8101|zook-bot|APPROVED|HEAD331|2026-07-30T10:00:00Z|1
333|8201|johnzook|APPROVED|HEAD333|2026-07-30T10:00:00Z|1
334|8301|johnzook|APPROVED|OLDHEAD334|2026-07-29T10:00:00Z|1
335|8401|zook-bot|COMMENTED|HEAD335|2026-07-30T09:00:00Z|1
335|8402|johnzook|APPROVED|HEAD335|2026-07-30T10:00:00Z|2
336|8501|johnzook|APPROVED|HEAD336|2026-07-30T10:00:00Z|1
336|8502|johnzook|CHANGES_REQUESTED|HEAD336|2026-07-30T11:00:00Z|2
341|8601|johnzook|APPROVED|HEAD341|2026-07-30T10:00:00Z|1
341|8602|johnzook|DISMISSED|HEAD341|2026-07-30T11:00:00Z|1
342|8701|johnzook|APPROVED|HEAD342|2026-07-30T10:00:00Z|1
342|8702|otherhuman|CHANGES_REQUESTED|HEAD342|2026-07-30T11:00:00Z|1
343|8801|johnzook|CHANGES_REQUESTED|HEAD343|2026-07-30T10:00:00Z|1
343|8802|johnzook|APPROVED|HEAD343|2026-07-30T11:00:00Z|1
348|8901|johnzook|APPROVED|HEAD348|2026-07-30T10:00:00Z|1
348|8902|johnzook|CHANGES_REQUESTED|HEAD348|2026-07-30T11:00:00Z|2
349|9001|readonlyhuman|APPROVED|HEAD349|2026-07-30T10:00:00Z|1
350|9101|driveby-bot|APPROVED|HEAD350|2026-07-30T10:00:00Z|1
351|9201|readonlyhuman|APPROVED|HEAD351|2026-07-30T10:00:00Z|1
351|9202|johnzook|APPROVED|HEAD351|2026-07-30T11:00:00Z|1
358|9301|zook-bot|DISMISSED|HEAD358|2026-07-30T10:00:00Z|1
358|9302|zook-bot|COMMENTED|HEAD358|2026-07-30T11:00:00Z|1
359|9401|zook-bot|DISMISSED|HEAD359|2026-07-30T10:00:00Z|1
359|9402|johnzook|APPROVED|HEAD359|2026-07-30T11:00:00Z|1
360|9501|zook-bot|COMMENTED|HEAD360|2026-07-30T09:00:00Z|1
360|9502|zook-bot|DISMISSED|HEAD360|2026-07-30T10:00:00Z|2
361|9601|zook-bot|COMMENTED|HEAD361|2026-07-30T09:00:00Z|1
361|9602|otherhuman|CHANGES_REQUESTED|HEAD361|2026-07-30T10:00:00Z|1
362|9701|otherhuman|CHANGES_REQUESTED|HEAD362|2026-07-30T10:00:00Z|1
362|9702|otherhuman|APPROVED|HEAD362|2026-07-30T11:00:00Z|1
R

# Repo permission per login (the `collaborators/<login>/permission` source — the
# default trusted-approver policy). login|permission. A login with NO row makes
# the probe FAIL, exactly as GitHub 404s for a non-collaborator (driveby-bot) or
# 403s for a token that cannot read the endpoint — and unreadable is untrusted.
# readonlyhuman is a real collaborator with READ access: a login the old non-self
# test accepted and the policy must not.
cat > "$TMP/perms" <<'PM'
johnzook|admin
otherhuman|write
readonlyhuman|read
PM

# PRs whose paginated reviews read DIES PART WAY (comma-separated). The pages
# already fetched are still streamed and the call exits non-zero: a truncated but
# perfectly parseable history, which is only detectable from the exit status.
APIFAIL_PRS="348"

# Open rework/review children referencing a PR (gc bd list pr_number= source):
# pr_number|child_id|merge_result|status|pr_url. The 5th column is the child's
# OWN pr_url, and it is what makes the child-hold guard an identity question
# rather than a number match. Omitted on rows that predate it ON PURPOSE: a child
# with no recorded URL cannot be placed in any repository, so it stays the `?`
# wildcard and holds exactly as it always did (case (6)/305 pins that legacy
# shape). child-foreign-365 names ANOTHER HOST's repository — somebody else's
# rework, which can never land ours — and must not hold; child-same-366 names
# this one and must.
# PR 305 has an open rework child (no
# merge_result -> the skill must count it and HOLD). PR 310's real child sits
# PAST the former --limit cap behind 24 jq-excluded decoys. PR 354's child is
# `blocked`, not open: it owes exactly as much work, and a gate keyed on
# open,in_progress alone could not see it at all.
cat > "$TMP/children" <<'C'
305|child-305||open
317|prblocked-317||blocked
326|bothsrc-326|pre_open_gate|
354|child-354||blocked
365|child-foreign-365|||https://otherhost/acme/repo/pull/365
366|child-same-366|||https://github.com/acme/repo/pull/366
C

# Children that name their PR with `fork_pr` and carry NO pr_number — the
# fork-sync keying. Invisible to a pr_number-only probe, which is why the gate
# reads every key the reconciler does. fork_pr|child_id|merge_result|status.
cat > "$TMP/forkchildren" <<'FC'
355|forkchild-355||open
FC

# A duplicate gating anchor that exists ONLY in the live ledger and NOT in the
# enumeration snapshot: created or reclassified mid-pass, after ROWS was captured.
# The pre-fix one-anchor-per-PR guard was computed once from that snapshot, so it
# could not see this anchor at all — and, because a duplicate carries
# merge_result, the in-flight-child hold excludes it too. id|pr_number|status.
cat > "$TMP/live-anchors" <<'LA'
dup-LIVEDUP|356|open
LA

# PRs whose in-flight-child ledger read is UNREADABLE, in the two ways that are
# not "empty": a non-zero exit (FAKE_QUERYFAIL) and an error OBJECT served with a
# zero exit (FAKE_PROBEOBJ). Both project to zero rows, so pre-fix both read as
# "no child holds this PR" and the merge went ahead.
QUERYFAIL_PRS="352"
PROBEOBJ_PRS="353"
# The padding rows are `merged`, not `pull_request`: they must be excluded from
# the CHILD projection (any non-empty merge_result is) without joining the OPEN
# GATING ANCHOR set, which `pull_request` would — 24 sibling anchors on one PR is
# a one-anchor-per-PR violation, and that guard would then hold PR#310 before the
# child gate this case is about ever ran.
for i in $(seq -w 1 24); do
  printf '310|decoy-%s|merged\n' "$i" >> "$TMP/children"
done
printf '310|child-310||\n' >> "$TMP/children"

# Dependency edges (gc bd dep list source), the resolution path tk-lgjvg adds:
#   anchor|direction|type|bead_id|status|merge_result
# `direction` is the flag the skill passes (up = dependents of the anchor,
# down = what the anchor depends on), so a row is returned ONLY to the exact
# direction+type walk that asks for it. The two wrong-end rows on bead-DOWNSTREAM
# are the deadlock guards: an `up|blocks` dependent WAITS for this merge and a
# `down|parent-child` parent stays open until the anchor closes, so a gate that
# held on either would never land a healthy anchor.
#
# The last two rows carry a NON-EMPTY merge_result (tk-je0rk). They are the holder
# shapes the merge_result exclusion used to delete: an upstream PR anchor ordered
# ahead of this one by an explicit `blocks` edge carries merge_result=pull_request
# BY DEFINITION, and a child that reached its own pre-open gate carries
# pre_open_gate. Reached by a dependency edge, both hold — the exclusion is scoped
# to pr_number-swept duplicate anchors only.
cat > "$TMP/deps" <<'D'
bead-DEPCHILD|up|parent-child|depchild-315|open|
bead-BLOCKEDKID|up|parent-child|blockedkid-316|blocked|
bead-BLOCKGATE|down|blocks|review-318|open|
bead-DOWNSTREAM|up|blocks|downstream-319|open|
bead-DOWNSTREAM|down|parent-child|epic-319|open|
bead-CLOSEDCHILD|up|parent-child|closedchild-320|closed|
bead-BLOCKEDBYPR|down|blocks|upstream-322|open|pull_request
bead-KIDANCHOR|up|parent-child|kidanchor-323|open|pre_open_gate
bead-BOTHSRC|up|parent-child|bothsrc-326|open|pull_request
bead-MULTIDOC|down|blocks|blocker-327|open|pull_request
bead-MULTIEMPTY|down|blocks|blocker-328|open|pull_request
bead-DEPFOREIGN|down|blocks|upstream-373|open|pull_request|https://otherhost/acme/repo/pull/999
D

# Anchors whose dep probe ERRORS (exit 1) — the fail-closed case.
printf 'bead-PROBEFAIL\n' > "$TMP/depfail"

# Anchors whose dep probe returns a payload with a ZERO exit status that the
# reader still cannot use. These are NOT probe failures — the command succeeds,
# so the old checks waved them through. Format:
#
#   anchor|direction|raw_payload      (direction = the walk this payload answers)
#
# Keyed by DIRECTION, not anchor alone, so a fixture can poison ONE walk and leave
# the other returning a real holder through $TMP/deps. That separation is what
# makes the multi-document cases below provable: the dropped blocker has to come
# from a walk the poisoned payload did not also supply.
#
#   bead-BADSHAPE   — element metadata is a STRING. Caught at the probe boundary
#                     by bead_read_array's per-element shape check.
#   bead-BADSTATUS  — element is structurally fine (string id, object metadata) so
#                     it PASSES that check, but its status is a NUMBER, which
#                     aborts the holder filter's ascii_downcase. Only the filter's
#                     own fail-closed branch can catch this one.
#   bead-MULTIDOC   — TWO JSON documents, `{}` then a valid array (tk-wkrcy). Every
#                     document is well-formed and the LAST one is a valid holder
#                     array, which is precisely why `jq -e` on the raw stream
#                     passed it: -e reports the last output only.
#   bead-MULTIEMPTY — TWO documents that are BOTH valid arrays, `[]` then `[]`. The
#                     variant with nothing malformed anywhere — the only defect is
#                     the COUNT, so it pins the document-count check specifically
#                     rather than any shape check.
#
# All four must end in a HELD merge.
cat > "$TMP/depraw" <<'R'
bead-BADSHAPE|up|[{"id":"badshape-324","status":"open","metadata":"oops"}]
bead-BADSHAPE|down|[{"id":"badshape-324","status":"open","metadata":"oops"}]
bead-BADSTATUS|up|[{"id":"badstatus-325","status":7,"metadata":{}}]
bead-BADSTATUS|down|[{"id":"badstatus-325","status":7,"metadata":{}}]
bead-MULTIDOC|up|{} []
bead-MULTIEMPTY|up|[] []
R

: > "$TMP/closed"; : > "$TMP/merged"; : > "$TMP/mergedrec"; : > "$TMP/closelog"
: > "$TMP/mergedwhere"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/repofail"
: > "$TMP/ghhost"

# PR#367 has NO child at all: the only thing that can hold it is the guarded read
# refusing to answer, so a missing guard merges it and the case cannot pass by
# accident.
printf '367\terror-rc1\n' > "$TMP/childfail"

# --- git stub. ----------------------------------------------------------------
# `git remote get-url origin` -> what this checkout pushes to, and the ONLY source
# of the repository every read and the merge are pinned to. Deliberately NOT `gh`:
# gh's idea of the current repository is movable, and moving it must not move the
# expectation. $FAKE_REPOFAIL makes it unanswerable, as a checkout with no origin
# remote would (ID4).
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_REPOFAIL" ] && exit 1
  printf 'https://github.com/acme/repo.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gh stub: pr view (emit state JSON), pr merge (record the merge). ---------
# `pr view` validates requested --json fields against a supported set (NOT
# `merged`) and emits a full object; the skill reads the subset it asked for.
# `pr merge` records the merged PR number — this is the seam: it must be reached
# for EXACTLY the one fully-validated anchor.
#
# THE READ AND THE MERGE FOLLOW gh's CURRENT REPOSITORY UNLESS `--repo` PINS THEM.
# $FAKE_GH_DEFAULT moves that default exactly as `gh repo set-default`, GH_REPO or a
# different cwd would; `acme/repo` when unset. With it moved, a bare
# `gh pr view <n>` / `gh pr merge <n>` answers for ANOTHER repository's
# same-numbered pull request — OPEN, based on main, CLEAN — indistinguishable from
# ours on every field except the repository, and a merge performed there lands a
# stranger's code. $FAKE_IGNORE_REPO models a gh that ignores the pin entirely, so
# the returned URL is the only thing left to catch it.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
ghdefault=$(cat "$FAKE_GH_DEFAULT" 2>/dev/null)
[ -n "$ghdefault" ] || ghdefault="acme/repo"
# Which repository this invocation actually resolves in: the pin when honoured,
# else gh's movable default. `--repo` takes [HOST/]OWNER/REPO.
RESOLVED=""
for a in "$@"; do
  case "${prev:-}" in --repo|-R) RESOLVED="$a" ;; esac
  prev="$a"
done
[ -s "$FAKE_IGNORE_REPO" ] && RESOLVED=""
[ -n "$RESOLVED" ] || RESOLVED="$ghdefault"
# `--repo` is `[HOST/]OWNER/REPO`, and with the host OMITTED gh supplies it from
# GH_HOST (`gh help environment`) — modelled by $FAKE_GH_HOST, github.com when
# unset. So `<owner>/<repo>` does not name a repository, it names one PER HOST: a
# hostless pin under a drifted GH_HOST reads THAT host's acme/repo, whose PR
# matches ours on owner, repo and number alike. Only a HOST-QUALIFIED pin closes
# it, which is why the resolved name below keeps its host.
case "$RESOLVED" in
  */*/*) : ;;
  *)     ghhost=$(cat "$FAKE_GH_HOST" 2>/dev/null)
         [ -n "$ghhost" ] || ghhost="github.com"
         RESOLVED="$ghhost/$RESOLVED" ;;
esac

# `gh api` arms:
#   user                      -> the acting account ($FAKE_SELF_LOGIN), which the
#                                approval gate excludes so the city can never
#                                satisfy its own approval requirement.
#   .../pulls/N/reviews       -> $FAKE_REVIEWS rows for PR N. Models GitHub's
#                                PAGING: rows on page >1 are served ONLY when the
#                                caller passes --paginate, so an unpaginated read
#                                sees page 1 alone — the real failure mode.
# --jq FILTER is applied with real jq, as gh does.
if [ "$1" = "api" ]; then
  shift
  PAGINATE=""; JQF=""; PATH_ARG=""; APIHOST=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --paginate) PAGINATE=1; shift ;;
      --jq)       JQF="$2"; shift 2 ;;
      --hostname) APIHOST="$2"; shift 2 ;;
      -q)         shift 2 ;;
      -X|-f)      shift 2 ;;
      *)          PATH_ARG="$1"; shift ;;
    esac
  done
  # WHICH REPOSITORY — AND HOST — THIS REST CALL RESOLVES IN. `gh api` takes no
  # `--repo`: the repository lives in the path and the HOST in `--hostname`, and
  # each half falls back to gh's ambient context when omitted — the path to gh's
  # current repository (`gh repo set-default`, $GH_REPO, the cwd), the host to
  # $GH_HOST. So a `repos/{owner}/{repo}/...` path is unpinned in BOTH halves and a
  # `repos/acme/repo/...` path with no `--hostname` is unpinned in one, which is
  # enough: `acme/repo` names one repository per host.
  #
  # A call that lands anywhere but github.com/acme/repo is answered from FOREIGN
  # fixtures below — a different review history, different collaborator
  # permissions, a different acting account. That is the whole point: the ambient
  # repository is not a neutral place to ask an approval question, because its
  # answers are perfectly well-formed and about somebody else's pull request
  # (review tk-5knqi finding #1).
  arepo=""
  case "$PATH_ARG" in
    repos/*) arepo="${PATH_ARG#repos/}"; arepo="$(printf '%s' "$arepo" | cut -d/ -f1,2)" ;;
  esac
  case "$arepo" in ""|'{owner}/{repo}') arepo="$ghdefault" ;; esac
  ahost="$APIHOST"
  if [ -z "$ahost" ]; then
    ahost=$(cat "$FAKE_GH_HOST" 2>/dev/null); [ -n "$ahost" ] || ahost="github.com"
  fi
  FOREIGN=""
  [ "$ahost/$arepo" = "github.com/acme/repo" ] || FOREIGN=1
  case "$PATH_ARG" in
    user)
      # An account name is host-scoped: the same token is a DIFFERENT login on a
      # different host, and a self-exclusion keyed on the wrong name stops
      # excluding what it exists to exclude.
      if [ -n "$FOREIGN" ]; then printf '%s\n' "${FAKE_SELF_LOGIN_FOREIGN-other-host-bot}"
      else printf '%s\n' "${FAKE_SELF_LOGIN-zook-bot}"; fi ;;
    */collaborators/*/permission*)
      # The default trusted-approver policy's probe. A login with no row in
      # $FAKE_PERMS fails the call (GitHub 404s a non-collaborator, and 403s a
      # token that may not read collaborator permissions) — the unreadable case
      # the policy must treat as untrusted.
      plogin="${PATH_ARG%%\?*}"; plogin="${plogin%/permission}"; plogin="${plogin##*/}"
      perm=""
      # A COLLABORATOR ROW IS PER REPOSITORY. Asked of the ambient one, "may this
      # account write here" is answered about a repository the merge will never
      # touch — and a yes there is indistinguishable from a yes here.
      permsrc="${FAKE_PERMS:-}"
      [ -n "$FOREIGN" ] && permsrc="${FAKE_PERMS_FOREIGN:-}"
      if [ -n "$permsrc" ] && [ -f "$permsrc" ]; then
        while IFS='|' read -r wlogin wperm; do
          [ "$wlogin" = "$plogin" ] || continue
          perm="$wperm"; break
        done < "$permsrc"
      fi
      [ -n "$perm" ] || exit 1
      pobj=$(printf '{"permission":"%s"}' "$perm")
      if [ -n "$JQF" ]; then printf '%s\n' "$pobj" | jq -r "$JQF"
      else printf '%s\n' "$pobj"; fi ;;
    */rules/branches/*)
      # RULESETS — the modern required-check mechanism, and the first of the two
      # sources the UNSTABLE arm unions. `$FAKE_PROTECTION` is `<branch>|<ruleset
      # contexts>|<classic contexts>`; a branch with no row is a repository with
      # no rules at all, which GitHub answers `[]` — a DEFINITE empty, not a
      # failure. `$FAKE_PROTFAIL` lists branches whose protection cannot be read
      # (the non-admin 404 / a 5xx), the case that must hold rather than reduce to
      # "nothing required".
      #
      # Pinned through gh_api_origin like every other REST read here, so the
      # host/repository identity is the reviews arm's story, not this one's.
      rbranch="${PATH_ARG#*/rules/branches/}"
      if [ -n "${FAKE_PROTFAIL:-}" ] \
         && printf '%s\n' "$FAKE_PROTFAIL" | tr ',' '\n' | grep -qxF "$rbranch"; then
        printf '{"message":"Not Found","status":"404"}\n'; exit 1
      fi
      rctx=""
      if [ -n "${FAKE_PROTECTION:-}" ] && [ -f "$FAKE_PROTECTION" ]; then
        while IFS='|' read -r pbranch prules pclassic; do
          [ "$pbranch" = "$rbranch" ] || continue
          rctx="$prules"; break
        done < "$FAKE_PROTECTION"
      fi
      # A `pull_request` rule always rides along: a branch can be governed by a
      # ruleset that requires review and NO status check, which is exactly what
      # both live rigs configure — so "has rules" must never imply "has required
      # checks".
      # `%s\n`, not `%s`: `jq -R` reads LINES, and an empty string with no newline
      # is zero lines, so the program never runs and the arm emits nothing at all
      # — which the script correctly reads as an unreadable payload rather than as
      # "no required contexts". A branch that requires nothing is the shape both
      # live rigs are in, so getting it wrong here would hide the whole fix.
      robj=$(printf '%s\n' "$rctx" | jq -R -c 'split(",") | map(select(length > 0)) |
        [ {type: "pull_request", parameters: {required_approving_review_count: 1}} ]
        + (if length == 0 then []
           else [ {type: "required_status_checks",
                   parameters: {required_status_checks: map({context: .})}} ] end)')
      if [ -n "$JQF" ]; then printf '%s\n' "$robj" | jq -r "$JQF"
      else printf '%s\n' "$robj"; fi ;;
    */branches/*)
      # The BRANCH object — classic branch protection's required_status_checks,
      # read from `repos/{o}/{r}/branches/{branch}` rather than from
      # `.../branches/{branch}/protection`, which needs ADMIN. Both `contexts`
      # (legacy) and `checks[].context` (current) are emitted, since a repository
      # can report either and the script unions them.
      bbranch="${PATH_ARG#*/branches/}"
      if [ -n "${FAKE_PROTFAIL:-}" ] \
         && printf '%s\n' "$FAKE_PROTFAIL" | tr ',' '\n' | grep -qxF "$bbranch"; then
        printf '{"message":"Not Found","status":"404"}\n'; exit 1
      fi
      cctx=""
      if [ -n "${FAKE_PROTECTION:-}" ] && [ -f "$FAKE_PROTECTION" ]; then
        while IFS='|' read -r pbranch prules pclassic; do
          [ "$pbranch" = "$bbranch" ] || continue
          cctx="$pclassic"; break
        done < "$FAKE_PROTECTION"
      fi
      bobj=$(printf '%s\n' "$cctx" | jq -R -c --arg b "$bbranch" \
        'split(",") | map(select(length > 0)) as $c
         | {name: $b, protected: (($c | length) > 0),
            protection: {required_status_checks:
              {contexts: $c, checks: ($c | map({context: ., app_id: null}))}}}')
      if [ -n "$JQF" ]; then printf '%s\n' "$bobj" | jq -r "$JQF"
      else printf '%s\n' "$bobj"; fi ;;
    */reviews*)
      prnum="${PATH_ARG%%\?*}"; prnum="${prnum%/reviews}"; prnum="${prnum##*/}"
      # $FAKE_APIFAIL stages a PAGINATED read that dies part way: `gh --paginate`
      # writes each page as it arrives, so the pages already fetched are still on
      # stdout when the call fails. The output alone is a well-formed history —
      # just not the WHOLE one — so only the exit status can tell the caller that
      # the tail (where a superseding CHANGES_REQUESTED lives) is missing.
      failnow=""
      if [ -n "${FAKE_APIFAIL:-}" ] \
         && printf '%s\n' "$FAKE_APIFAIL" | tr ',' '\n' | grep -qxF "$prnum"; then
        failnow=1
      fi
      # THE REVIEW HISTORY IS PER REPOSITORY TOO, and it is the evidence the veto
      # and approval gates are decided from. Read from the ambient repository, a
      # same-numbered PR approved THERE satisfies the gate here, and a standing
      # CHANGES_REQUESTED here is invisible because the veto lives in a history
      # that was never read — both directions merge work no reviewer of this
      # repository ever cleared.
      revsrc="$FAKE_REVIEWS"
      [ -n "$FOREIGN" ] && revsrc="${FAKE_REVIEWS_FOREIGN:-/dev/null}"
      out=""
      while IFS='|' read -r rpr rid rlogin rstate rcommit rsub rpage; do
        [ -n "$rpr" ] || continue
        [ "$rpr" = "$prnum" ] || continue
        if [ -n "$failnow" ]; then
          # A read that died after page 1 never delivers page 2, --paginate or not.
          [ "${rpage:-1}" = "1" ] || continue
        else
          [ -n "$PAGINATE" ] || [ "${rpage:-1}" = "1" ] || continue
        fi
        obj=$(printf '{"id":%s,"user":{"login":"%s"},"state":"%s","commit_id":"%s","submitted_at":"%s"}' \
                "$rid" "$rlogin" "$rstate" "$rcommit" "$rsub")
        if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
      done < "$revsrc"
      if [ -n "$JQF" ]; then printf '[%s]\n' "$out" | jq -r "$JQF"
      else printf '[%s]\n' "$out"; fi
      [ -z "$failnow" ] || exit 1 ;;
  esac
  exit 0
fi
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid headRepository headRepositoryOwner isCrossRepository url title body author additions deletions mergeable mergeStateStatus reviewDecision statusCheckRollup "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
    # The head's check ROLLUP, read only by the UNSTABLE arm's required-check
    # evaluation. `$FAKE_ROLLUP` is `<pr>|<kind>|<name>|<value>`: kind `status`
    # emits a StatusContext (context + state), anything else a CheckRun (name +
    # conclusion), and an EMPTY value emits a CheckRun still running — conclusion
    # null — which is the shape a required check that has not reported yet takes.
    # `$FAKE_ROLLUPFAIL` lists PRs whose rollup read FAILS, and only for a call
    # that actually asks for the field: the main PR read must stay unaffected.
    case ",$fields," in
      *,statusCheckRollup,*)
        if [ -n "${FAKE_ROLLUPFAIL:-}" ] \
           && printf '%s\n' "$FAKE_ROLLUPFAIL" | tr ',' '\n' | grep -qxF "$num"; then
          echo "could not read rollup" >&2; exit 1
        fi ;;
    esac
    ROLLUP="[]"
    if [ -n "${FAKE_ROLLUP:-}" ] && [ -f "$FAKE_ROLLUP" ]; then
      relems=""
      while IFS='|' read -r rpr rkind rname rval; do
        [ "$rpr" = "$num" ] || continue
        if [ "$rkind" = "status" ]; then
          robj=$(jq -nc --arg n "$rname" --arg v "$rval" \
            '{__typename:"StatusContext", context:$n, state:$v}')
        else
          robj=$(jq -nc --arg n "$rname" --arg v "$rval" \
            '{__typename:"CheckRun", name:$n,
              status:(if $v == "" then "IN_PROGRESS" else "COMPLETED" end),
              conclusion:(if $v == "" then null else $v end)}')
        fi
        if [ -z "$relems" ]; then relems="$robj"; else relems="$relems,$robj"; fi
      done < "$FAKE_ROLLUP"
      ROLLUP="[$relems]"
    fi
    if [ "$RESOLVED" != "github.com/acme/repo" ]; then
      # A foreign repository's PR of the same number — foreign by owner/repo, by
      # HOST, or by both. Deliberately CLEAN, OPEN and non-draft: nothing but the
      # URL distinguishes it from ours.
      jq -n --arg n "$num" --arg r "${RESOLVED#*/}" --arg h "${RESOLVED%%/*}" \
        '{state:"OPEN", isDraft:false, baseRefName:"main", headRefOid:("HEAD" + $n),
          headRefName:("polecat/foreign-" + $n),
          headRepositoryOwner:{login:($r | split("/")[0])},
          headRepository:{name:($r | split("/")[1])},
          isCrossRepository:false,
          mergeStateStatus:"CLEAN", mergeable:"MERGEABLE",
          mergeCommit:{oid:("f0re19n" + $n)},
          url:("https://" + $h + "/" + $r + "/pull/" + $n)}'
      exit 0
    fi
    # Trailing columns are OPTIONAL and positional: 9 is reviewDecision, 10-12 the
    # head identity (branch, head repository, GitHub's cross-repository flag). All
    # are OMITTED on every legacy row and default to none / THIS repository's branch
    # for this PR — the shape every pre-existing case was written against — so only
    # the cases that turn on them vary them. A headrepo of `-` emits NULL objects,
    # which is what gh returns for a deleted head repository (an omitted column
    # cannot mean that: it has to keep meaning "ours").
    while IFS='|' read -r pr state isdraft base headoid mss mergeable oid rd headref headrepo cross; do
      [ "$pr" = "$num" ] || continue
      [ -n "$headref" ]  || headref="polecat/pr-$num"
      [ -n "$cross" ]    || cross="false"
      [ -n "$headrepo" ] || headrepo="acme/repo"
      jq -n --arg s "$state" --argjson d "$isdraft" --arg b "$base" \
            --arg h "$headoid" --arg m "$mss" --arg mg "$mergeable" --arg o "$oid" \
            --arg n "$num" --arg rd "$rd" --arg hr "$headref" --arg hrepo "$headrepo" \
            --argjson x "$cross" --argjson scr "$ROLLUP" \
        '{state:$s, isDraft:$d, baseRefName:$b, headRefOid:$h, headRefName:$hr,
          statusCheckRollup:$scr,
          headRepositoryOwner:(if $hrepo=="-" then null else {login:($hrepo | split("/")[0])} end),
          headRepository:(if $hrepo=="-" then null else {name:($hrepo | split("/")[1])} end),
          isCrossRepository:$x, reviewDecision:$rd,
          mergeStateStatus:$m, mergeable:$mg, mergeCommit:(if $o=="" then null else {oid:$o} end), url:("https://github.com/acme/repo/pull/" + $n)}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr merge")
    num="$3"; shift 3
    match=""
    while [ $# -gt 0 ]; do
      case "$1" in --match-head-commit) match="$2"; shift 2 ;; *) shift ;; esac
    done
    # Every merge attempt is logged with the head it bound itself to, so a test
    # can assert the flag was passed at all — not just that a merge happened.
    printf '%s\t%s\n' "$num" "$match" >> "${FAKE_MERGEARGS:-/dev/null}"
    # GitHub refuses a --match-head-commit merge whose commit is no longer the
    # PR's head. $FAKE_HEADMOVE stages that: a listed PR's REAL head differs from
    # what validation saw, so the merge must be rejected rather than land a
    # commit no gate in this pass validated.
    if [ -n "${FAKE_HEADMOVE:-}" ] && [ -f "$FAKE_HEADMOVE" ]; then
      while IFS='|' read -r hpr hnew; do
        [ "$hpr" = "$num" ] || continue
        if [ "$match" != "$hnew" ]; then
          echo "Pull request is not mergeable: head has changed (expected ${match:-none}, actual $hnew)" >&2
          exit 1
        fi
      done < "$FAKE_HEADMOVE"
    fi
    printf '%s\n' "$num" >> "$FAKE_MERGED"
    # WHERE the merge landed, not just which number: a merge performed in the
    # wrong repository is the failure the identity tests exist to catch.
    printf '%s\t%s\n' "$num" "$RESOLVED" >> "$FAKE_MERGEDWHERE" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list / bd dep list / bd show / bd close / bd update. --------
# Two list shapes: the gating-anchor scan (merge_result=pull_request, excluding
# already-closed anchors so convergence holds) and the referencing-bead scan
# (pr_number=N, fork_pr=N and fork_pr_url, honouring the requested --status list)
# that returns the anchor (which the skill EXCLUDES) plus any live rework/review
# children (which HOLD the merge). `bd dep list` serves the two dependency walks,
# each answering ONLY the direction+type it was asked for — a stub that ignored
# the flags could not tell a rework child from the epic parent or the downstream
# dependent.
#
# `bd show <id>` serves the anchor's LIVE metadata for the per-anchor re-read the
# skill performs after the PR-state read. It answers from $FAKE_ANCHORS_FRESH
# when that file carries a row for the id (the mid-pass write the enumeration
# snapshot missed) and from $FAKE_ANCHORS otherwise, and it returns NOTHING for
# an id in $FAKE_SHOWFAIL — the unreadable-metadata case.
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
emit_rows() {
  raw="[$1]"; n="$2"
  if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
    printf '%s' "$raw" | jq -c ".[:$n]"
  else
    printf '%s\n' "$raw"
  fi
}
[ "$1" = "bd" ] || exit 0
case "$2" in
  show)
    want="$3"
    case " ${FAKE_SHOWFAIL:-} " in *" $want "*) exit 0 ;; esac
    # HOW MANY TIMES this anchor has been shown in the current run of the script.
    # The pass re-reads an anchor TWICE on the merge path — once before the gates
    # and once immediately before `gh pr merge` — and the whole point of the second
    # read is that the bead can change in between, so the stub has to be able to
    # answer the two reads DIFFERENTLY.
    SHOWN=0
    if [ -n "${FAKE_SHOWCOUNT:-}" ] && [ -d "$FAKE_SHOWCOUNT" ]; then
      [ -f "$FAKE_SHOWCOUNT/$want" ] && SHOWN=$(cat "$FAKE_SHOWCOUNT/$want")
      SHOWN=$((SHOWN + 1))
      printf '%s' "$SHOWN" > "$FAKE_SHOWCOUNT/$want"
    fi
    # An anchor whose SECOND read fails: the terminal re-read is unreadable while
    # everything before it was fine. Distinct from $FAKE_SHOWFAIL, which fails
    # every read and so never reaches the merge path at all.
    if [ "$SHOWN" -ge 2 ]; then
      case " ${FAKE_SHOWFAIL_FINAL:-} " in *" $want "*) exit 0 ;; esac
    fi
    src="$FAKE_ANCHORS"
    if [ -n "${FAKE_ANCHORS_FRESH:-}" ] && [ -f "$FAKE_ANCHORS_FRESH" ] \
       && grep -q "^$want|" "$FAKE_ANCHORS_FRESH"; then
      src="$FAKE_ANCHORS_FRESH"
    fi
    # $FAKE_ANCHORS_FINAL is served from the SECOND read on: the state another
    # writer left behind AFTER every gate validated and BEFORE the merge fired.
    if [ "$SHOWN" -ge 2 ] && [ -n "${FAKE_ANCHORS_FINAL:-}" ] && [ -f "$FAKE_ANCHORS_FINAL" ] \
       && grep -q "^$want|" "$FAKE_ANCHORS_FINAL"; then
      src="$FAKE_ANCHORS_FINAL"
    fi
    while IFS='|' read -r id pr target checkset checkcodex merge_hold dismissed prurl branch forkpr forkprurl status result; do
      [ "$id" = "$want" ] || continue
      # Columns 8/9 (status, merge_result) exist only in the FRESH file, and only
      # for the cases that stage a mid-pass identity change. Absent -> the normal
      # gating-anchor shape the enumeration selected; the literal `-` means the
      # field is EMPTY on the live bead (the cleared-metadata case).
      [ -n "$status" ] || status="open"
      [ -n "$result" ] || result="pull_request"
      [ "$status" = "-" ] && status=""
      [ "$result" = "-" ] && result=""
      printf '[{"id":"%s","status":"%s","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merged_target":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s","signoff_dismissed":"%s","branch":"%s","merge_result":"%s"}}]\n' \
        "$id" "$status" "$pr" "$prurl" "$forkpr" "$forkprurl" "$target" "$checkset" "$checkcodex" "$merge_hold" "$dismissed" "$branch" "$result"
      exit 0
    done < "$src"
    printf '[]\n' ;;
  list)
    lim=$(printf '%s' "$*" | sed -n 's/.*--limit=\([0-9][0-9]*\).*/\1/p')
    # The --status filter is HONORED, not ignored: a probe that asks for a subset
    # of the non-closed statuses must genuinely be unable to see beads outside it.
    # Ignoring it would make an open,in_progress-only gate look like it covers
    # `blocked`/`hooked` children when it cannot, hiding the very gap case (37c)
    # exists to pin.
    want_status=$(printf '%s' "$*" | sed -n 's/.*--status[ =]\([a-z_,]*\).*/\1/p')
    status_ok() {
      [ -n "$want_status" ] || return 0
      case ",$want_status," in *",$1,"*) return 0 ;; esac
      return 1
    }
    case "$*" in
      *"merge_result=pull_request"*)
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold dismissed prurl branch forkpr forkprurl; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merged_target":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s","signoff_dismissed":"%s","branch":"%s"}}' "$id" "$pr" "$prurl" "$forkpr" "$forkprurl" "$target" "$checkset" "$checkcodex" "$merge_hold" "$dismissed" "$branch")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *"pr_number="*)
        prnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        # $FAKE_QUERYFAIL / $FAKE_PROBEOBJ stage the two ways this read can be
        # UNREADABLE without being empty — the pair the guarded probe exists for.
        # QUERYFAIL: a non-zero exit (a transient ledger error), with output, so
        # only the status reveals it. PROBEOBJ: `gc ... --json` reporting its own
        # failure as a JSON *object* on stdout with a ZERO status — non-empty,
        # parseable, and projecting to zero rows, so every guard except the
        # array-shape one waves it through as "no child holds this PR".
        if [ -n "${FAKE_QUERYFAIL:-}" ] \
           && printf '%s\n' "$FAKE_QUERYFAIL" | tr ',' '\n' | grep -qxF "$prnum"; then
          printf '[]\n'; exit 1
        fi
        if [ -n "${FAKE_PROBEOBJ:-}" ] \
           && printf '%s\n' "$FAKE_PROBEOBJ" | tr ',' '\n' | grep -qxF "$prnum"; then
          printf '{"error":"ledger unavailable"}\n'; exit 0
        fi
        # A FAILED child lookup, scoped to one PR so every other case is unaffected.
        # $FAKE_CHILD_FAIL holds "<pr><TAB><shape>" rows. Each shape defeats a
        # different guard, so a guard that is deleted fails exactly one case:
        #   error-rc1 — the observed shape: a JSON error OBJECT plus exit 1.
        #   error-rc0 — the same object with a ZERO exit; only the payload-shape
        #               guard can see it.
        #   array-rc1 — a well-formed EMPTY array with a non-zero exit; only the
        #               exit-status guard can see it, and "[]" is precisely the
        #               value that legitimately means "no child holds this PR".
        cfail=$(awk -F'\t' -v n="$prnum" '$1==n{print $2}' "${FAKE_CHILD_FAIL:-/dev/null}" 2>/dev/null | tail -1)
        case "$cfail" in
          error-rc1) printf '{"error":"ledger unavailable"}\n'; exit 1 ;;
          error-rc0) printf '{"error":"ledger unavailable"}\n'; exit 0 ;;
          array-rc1) printf '[]\n'; exit 1 ;;
        esac
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold dismissed prurl branch forkpr forkprurl; do
          [ -n "$id" ] || continue
          [ "$pr" = "$prnum" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          status_ok open || continue
          # pr_url rides along: it is what places this anchor in a REPOSITORY, and
          # without it a foreign same-numbered anchor reads as the `?` wildcard and
          # makes an ordinary PR look multi-anchored.
          obj=$(printf '{"id":"%s","status":"open","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merge_result":"pull_request"}}' "$id" "$pr" "$prurl" "$forkpr" "$forkprurl")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        # Anchors visible ONLY to this live read and NOT to the enumeration
        # snapshot: a duplicate gating anchor created or reclassified mid-pass.
        # id|pr|status.
        if [ -n "${FAKE_LIVE_ANCHORS:-}" ] && [ -f "$FAKE_LIVE_ANCHORS" ]; then
          while IFS='|' read -r lid lpr lstatus; do
            [ -n "$lid" ] || continue
            [ "$lpr" = "$prnum" ] || continue
            grep -qx "$lid" "$FAKE_CLOSED" 2>/dev/null && continue
            status_ok "${lstatus:-open}" || continue
            obj=$(printf '{"id":"%s","status":"%s","metadata":{"pr_number":"%s","merge_result":"pull_request"}}' \
                    "$lid" "${lstatus:-open}" "$lpr")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_LIVE_ANCHORS"
        fi
        if [ -f "$FAKE_CHILDREN" ]; then
          # 4th column: the child's STATUS. Absent -> open. The gate reads every
          # non-closed status, so a `blocked`/`hooked` child holds the merge too.
          # 5th: the child's own pr_url (empty = the `?` wildcard).
          while IFS='|' read -r cpr cid cmr cstatus cprurl; do
            [ -n "$cpr" ] || continue
            [ "$cpr" = "$prnum" ] || continue
            grep -qx "$cid" "$FAKE_CLOSED" 2>/dev/null && continue
            status_ok "${cstatus:-open}" || continue
            obj=$(printf '{"id":"%s","status":"%s","metadata":{"pr_number":"%s","merge_result":"%s","pr_url":"%s"}}' \
                    "$cid" "${cstatus:-open}" "$cpr" "$cmr" "$cprurl")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_CHILDREN"
        fi
        emit_rows "$out" "$lim" ;;
      *"fork_pr="*)
        # The fork-sync keying: a live bead that names its PR as `fork_pr` and
        # carries no pr_number at all. Invisible to a pr_number-only gate.
        # fork_pr|child_id|merge_result|status.
        fnum=$(printf '%s' "$*" | sed -n 's/.*fork_pr=\([0-9][0-9]*\).*/\1/p')
        out=""
        if [ -n "${FAKE_FORKCHILDREN:-}" ] && [ -f "$FAKE_FORKCHILDREN" ]; then
          while IFS='|' read -r fpr fid fmr fstatus; do
            [ -n "$fpr" ] || continue
            [ "$fpr" = "$fnum" ] || continue
            grep -qx "$fid" "$FAKE_CLOSED" 2>/dev/null && continue
            status_ok "${fstatus:-open}" || continue
            obj=$(printf '{"id":"%s","status":"%s","metadata":{"fork_pr":"%s","merge_result":"%s"}}' \
                    "$fid" "${fstatus:-open}" "$fpr" "$fmr")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_FORKCHILDREN"
        fi
        # ...and ANCHORS whose own identity is fork-keyed. The anchor reads its own
        # number through the same key set every probe uses, so a `fork_pr`-only
        # anchor has to be reachable here or it is invisible to its own PR.
        while IFS='|' read -r id pr target checkset checkcodex merge_hold dismissed prurl branch forkpr forkprurl; do
          [ -n "$id" ] || continue
          [ "$forkpr" = "$fnum" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          status_ok open || continue
          obj=$(printf '{"id":"%s","status":"open","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merge_result":"pull_request"}}' "$id" "$pr" "$prurl" "$forkpr" "$forkprurl")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *"--has-metadata-key fork_pr_url"*)
        # The URL-keyed half of the same set: every bead carrying a fork_pr_url at
        # all, which the caller then filters by number. Bounded in production by the
        # key being rare; here it is just the anchors that record one.
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold dismissed prurl branch forkpr forkprurl; do
          [ -n "$id" ] || continue
          [ -n "$forkprurl" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          status_ok open || continue
          obj=$(printf '{"id":"%s","status":"open","metadata":{"pr_number":"%s","pr_url":"%s","fork_pr":"%s","fork_pr_url":"%s","merge_result":"pull_request"}}' "$id" "$pr" "$prurl" "$forkpr" "$forkprurl")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *) printf '[]\n' ;;
    esac ;;
  dep)
    [ "$3" = "list" ] || { printf '[]\n'; exit 0; }
    aid="$4"; shift 4
    dir="down"; typ=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --direction=*) dir="${1#--direction=}"; shift ;;
        --direction) dir="$2"; shift 2 ;;
        -t|--type) typ="$2"; shift 2 ;;
        --type=*) typ="${1#--type=}"; shift ;;
        *) shift ;;
      esac
    done
    # A wedged/unreadable probe: non-zero exit with no usable payload.
    if grep -qx "$aid" "$FAKE_DEPFAIL" 2>/dev/null; then
      echo "gc: dep list failed for $aid" >&2; exit 1
    fi
    # A probe that SUCCEEDS (exit 0) but whose payload the reader cannot use.
    # Emitted verbatim — including a MULTI-DOCUMENT stream — so the test controls
    # the exact bytes. Keyed on anchor AND direction so one walk can be poisoned
    # while the other still answers from $TMP/deps.
    if [ -f "$FAKE_DEPRAW" ]; then
      raw=$(sed -n "s/^${aid}|${dir}|//p" "$FAKE_DEPRAW")
      if [ -n "$raw" ]; then printf '%s\n' "$raw"; exit 0; fi
    fi
    out=""
    if [ -f "$FAKE_DEPS" ]; then
      while IFS='|' read -r danchor ddir dtype did dstatus dmr dprurl; do
        [ -n "$danchor" ] || continue
        [ "$danchor" = "$aid" ] || continue
        [ "$ddir" = "$dir" ] || continue
        [ -z "$typ" ] || [ "$dtype" = "$typ" ] || continue
        grep -qx "$did" "$FAKE_CLOSED" 2>/dev/null && continue
        obj=$(printf '{"id":"%s","status":"%s","dependency_type":"%s","metadata":{"merge_result":"%s","pr_url":"%s"}}' "$did" "$dstatus" "$dtype" "$dmr" "$dprurl")
        if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
      done < "$FAKE_DEPS"
    fi
    printf '[%s]\n' "$out" ;;
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
    # Model bd's assignee gate — the refusal that wedges the record half.
    #
    # $FAKE_CLOSE_REFUSE holds `id<TAB>message` rows: closing that id WITHOUT
    # --force fails with that message and records NOTHING, exactly as the real
    # refusal does; WITH --force it succeeds. That asymmetry is what makes "did
    # the override actually fire?" observable rather than inferred.
    #
    # $FAKE_CLOSE_HARDFAIL rows fail for BOTH forms — the refusals the override
    # must never paper over (a genuinely foreign assignee, an open-children hold).
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
    case "$*" in
      *merge_result=merged*) printf '%s\n' "$id" >> "$FAKE_MERGEDREC" ;;
    esac ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

: > "$TMP/mergeargs"

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" FAKE_CHILDREN="$TMP/children" \
       FAKE_DEPS="$TMP/deps" FAKE_DEPFAIL="$TMP/depfail" FAKE_DEPRAW="$TMP/depraw" \
       FAKE_REVIEWS="$TMP/reviews" FAKE_PERMS="$TMP/perms" FAKE_APIFAIL="$APIFAIL_PRS" \
       FAKE_ANCHORS_FRESH="$TMP/anchors-fresh" FAKE_SHOWFAIL="$SHOWFAIL_IDS" \
       FAKE_HEADMOVE="$TMP/headmove" FAKE_MERGEARGS="$TMP/mergeargs" \
       FAKE_FORKCHILDREN="$TMP/forkchildren" FAKE_LIVE_ANCHORS="$TMP/live-anchors" \
       FAKE_QUERYFAIL="$QUERYFAIL_PRS" FAKE_PROBEOBJ="$PROBEOBJ_PRS" \
       FAKE_CLOSED="$TMP/closed" FAKE_MERGED="$TMP/merged" \
       FAKE_MERGEDREC="$TMP/mergedrec" FAKE_CLOSELOG="$TMP/closelog" \
       FAKE_MERGEDWHERE="$TMP/mergedwhere" FAKE_GH_DEFAULT="$TMP/ghdefault" \
       FAKE_IGNORE_REPO="$TMP/ignorerepo" FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_GH_HOST="$TMP/ghhost" FAKE_CHILD_FAIL="$TMP/childfail" \
       FAKE_ANCHORS_FINAL="$TMP/anchors-final" FAKE_SHOWCOUNT="$TMP/showcount" \
       FAKE_SHOWFAIL_FINAL="$SHOWFAIL_FINAL_IDS" \
       FAKE_CLOSE_REFUSE="$TMP/closerefuse" FAKE_CLOSE_HARDFAIL="$TMP/closehard" \
       FAKE_FORCED="$TMP/forced" \
       FAKE_PROTECTION="$TMP/protection" FAKE_ROLLUP="$TMP/rollup"
# Branch protection and check rollups are INERT for every scenario above the
# required-set run at the end of this file: no branch requires a status check and
# no PR reports one, which is the shape every pre-existing case was written
# against (and the shape both live rigs are actually in). $FAKE_PROTFAIL and
# $FAKE_ROLLUPFAIL are unset — no read fails.
: > "$TMP/protection"; : > "$TMP/rollup"
# The close gate is INERT by default: every scenario above the close-gate runs at
# the end of this file closes cleanly.
: > "$TMP/closerefuse"; : > "$TMP/closehard"; : > "$TMP/forced"

# --- Run 1: validate -> merge -> record for the one ready PR, hold the rest. --
# stdout carries the per-anchor hold/merge decisions; the tool-error paths (an
# unreadable anchor re-read, a refused merge) report on stderr, so capture both.
OUT1="$(bash "$SCRIPT" 2>"$TMP/err1")"
ERR1="$(cat "$TMP/err1")"

# (1) ready PR -> merged + recorded + closed.
has '^301$' "$TMP/merged" && ok "(1) ready PR -> 'gh pr merge --squash' performed" \
                          || bad "(1) ready PR -> merge performed"
has '^bead-CLEAN$' "$TMP/closed" && ok "(1) ready anchor closed (record)" \
                                 || bad "(1) ready anchor closed"
grep -q 'Merged to main at a301c0ff' "$TMP/closelog" \
  && ok "(1) close reason names target + short merge sha" \
  || bad "(1) close reason (got: $(cat "$TMP/closelog"))"
has '^bead-CLEAN$' "$TMP/mergedrec" && ok "(1) merge_result=merged recorded on anchor" \
                                    || bad "(1) merge_result=merged recorded"

# (1b) THE BUG FIX: an anchor with an empty check_set (no required gate) merges
# once CLEAN, instead of the former unconditional hold on a missing signoff_head.
has '^311$' "$TMP/merged" && ok "(1b) no-gate PR (empty check_set) -> merged (missing gate no longer holds forever)" \
                          || bad "(1b) no-gate PR -> merged"
has '^bead-NOGATE$' "$TMP/closed" && ok "(1b) no-gate anchor closed (record)" \
                                  || bad "(1b) no-gate anchor closed"
has '^bead-NOGATE$' "$TMP/mergedrec" && ok "(1b) merge_result=merged recorded on no-gate anchor" \
                                     || bad "(1b) no-gate merge_result recorded"

# (1c) THE OPT-OUT SENTINEL (tk-i48ca): check_set="none" is a gateless rig saying
# so EXPLICITLY. It reaches this script as a gate NAME (the formula now stamps the
# sentinel instead of collapsing it to ""), so the gate-splitting must DROP it —
# otherwise the anchor holds forever on `check.none`, a marker no reviewer can
# stamp. Stamping the sentinel is what lets an EMPTY check_set stay a reliable
# "this bead never ran normalization" signal for check-set-heal.sh.
has '^314$' "$TMP/merged" && ok "(1c) opt-out PR (check_set='none') -> merged (sentinel read as no-gates)" \
                          || bad "(1c) opt-out sentinel must merge, not hold on a 'check.none' marker"
has '^bead-OPTOUT$' "$TMP/closed" && ok "(1c) opt-out anchor closed (record)" \
                                  || bad "(1c) opt-out anchor closed"

# (17) THE ANTI-DEADLOCK GUARD: bead-DOWNSTREAM's only edges point the WRONG way
# — an `up|blocks` dependent waiting for this merge, and a `down|parent-child`
# epic parent that stays open until the anchor closes. Neither is a child. A gate
# that walked those directions would hold a healthy anchor forever.
has '^319$' "$TMP/merged" && ok "(17) wrong-end edges (downstream dependent + epic parent) -> merged, not deadlocked" \
                          || bad "(17) wrong-end edges must NOT hold the merge"
# (18) a CLOSED dependency-linked child holds nothing — the invariant is "all
# children CLOSED", and this one is.
has '^320$' "$TMP/merged" && ok "(18) closed dep-linked child -> merged" \
                          || bad "(18) closed dep-linked child must not hold"

# (2)-(19) every other anchor is HELD or skipped — NOT merged. 313 is the
# multi-anchor PR: its gateless duplicate anchor (bead-DUPFREE) is CLEAN and
# would have merged pre-fix. 315-318 and 321-328 are the tk-lgjvg/tk-je0rk
# child-resolution anchors and 329+ the tk-5niup approval/veto anchors: every
# one is CLEAN with its codex gate green at the live head, so the ONLY thing
# standing between them and a merge is the gate each case is about.
for n in 302 303 304 305 306 307 308 309 310 312 313 315 316 317 318 321 \
         322 323 324 325 326 329 331 332 334 336 337 338 339 340 341 342 \
         344 345 346 347 348 349 350 358 360 361; do
  has "^$n$" "$TMP/merged" && bad "($n) anchor must NOT be merged" \
                          || ok "($n) anchor not merged"
done

# Hold reasons name the specific gate that blocked each PR.
hasin "$OUT1" "PR#302 check 'codex' not green at live head" \
  && ok "(2) stale check.codex (green@old-head) -> held, reason names the gate" \
  || bad "(2) stale check hold reason (got: $OUT1)"
hasin "$OUT1" "PR#303 check 'codex' not green at live head" \
  && ok "(3) missing check.codex (codex in check_set) -> held" || bad "(3) missing check hold (got: $OUT1)"
hasin "$OUT1" "PR#304 not mergeable yet (mergeStateStatus='BLOCKED'" \
  && ok "(4) BLOCKED -> held, reason names mergeStateStatus" || bad "(4) BLOCKED hold (got: $OUT1)"
hasin "$OUT1" "PR#309 not mergeable yet (mergeStateStatus='BEHIND'" \
  && ok "(5) BEHIND -> held" || bad "(5) BEHIND hold (got: $OUT1)"
hasin "$OUT1" "PR#305 has unclosed rework/review bead child-305 (open)" \
  && ok "(6) open rework child -> held, reason names the child" || bad "(6) child hold (got: $OUT1)"
hasin "$OUT1" "PR#306 base 'integration/foo' != target 'main' (retargeted)" \
  && ok "(7) retargeted -> held, reason names the base mismatch" || bad "(7) retarget hold (got: $OUT1)"
hasin "$OUT1" "PR#310 has unclosed rework/review bead child-310 (open)" \
  && ok "(10) open child past former cap -> held (unbounded scan found it)" \
  || bad "(10) past-cap child hold (got: $OUT1)"
hasin "$OUT1" "PR#312 merge_hold set (operator gate)" \
  && ok "(11) merge_hold=true -> held, reason names the operator gate" \
  || bad "(11) merge_hold hold reason (got: $OUT1)"
hasin "$OUT1" "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPGATED)" \
  && ok "(12) multi-anchor PR -> gated anchor held with the one-anchor-per-PR reason" \
  || bad "(12) multi-anchor gated-anchor hold (got: $OUT1)"
hasin "$OUT1" "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPFREE)" \
  && ok "(12) multi-anchor PR -> gateless duplicate ALSO held (pre-fix it merged, bypassing codex)" \
  || bad "(12) multi-anchor gateless-duplicate hold (got: $OUT1)"

# (27) THE FAIL-OPEN TRAP (tk-5niup). The re-gate retracted the city's own
# blocking review, which is what turned this PR CLEAN; on a repo with no review
# requirement CLEAN folds NO approval, so pre-fix the skill squash-merged
# unverified work the moment the block came off. signoff_dismissed arms an
# explicit approval requirement that CLEAN cannot satisfy on its own.
hasin "$OUT1" "PR#329 no external approving review at the live head HEAD329 (signoff_dismissed=900@HEAD329" \
  && ok "(27) dismissed-own-review + CLEAN + no approval -> held, reason names signoff_dismissed" \
  || bad "(27) signoff_dismissed approval hold (got: $OUT1)"
# (27b) and it is satisfiable — a real external approval lands the same shape.
has '^330$' "$TMP/merged" && ok "(27b) dismissed-own-review WITH an external approval -> merged" \
                          || bad "(27b) approved dismissed-review PR must merge (got: $OUT1)"
# (27c) a self-approval is not approval: the city posts COMMENT signoffs and
# never approves, so an APPROVED review under the acting login must not count —
# otherwise the gate could be satisfied by the same actor that removed the block.
hasin "$OUT1" "PR#331 no external approving review" \
  && ok "(27c) APPROVED by the acting account itself -> still held (self-approval rejected)" \
  || bad "(27c) self-approval must not satisfy the gate (got: $OUT1)"
# (28) the explicit opt-in: `approval` named in check_set. It must hold on the
# APPROVAL gate, NOT on a missing `check.approval` marker — approval is evidenced
# by GitHub review state, and a marker gate would strand the anchor forever the
# way an undropped none/off sentinel would.
hasin "$OUT1" "PR#332 no external approving review at the live head HEAD332 (check_set names approval" \
  && ok "(28) check_set names approval, none given -> held on the approval gate" \
  || bad "(28) check_set approval hold (got: $OUT1)"
hasin "$OUT1" "PR#332 check 'approval' not green at live head" \
  && bad "(28) approval must NOT be treated as a check.<name> marker gate (nothing can stamp it)" \
  || ok "(28) approval dropped from the marker loop (no unstampable check.approval hold)"
has '^333$' "$TMP/merged" && ok "(28b) check_set names approval + external approval -> merged" \
                          || bad "(28b) approval-gated PR with an approval must merge (got: $OUT1)"

# (29) THE STALE-APPROVAL HOLE. johnzook approved OLDHEAD334; the head has since
# moved to HEAD334 and the city dismissed its own block. Pre-fix the gate read
# `latestReviews`, which reports the verdict but NOT the commit — so an approval
# of a dead commit satisfied it and the PR merged work nobody approved. The
# approval is head-bound now, exactly like check.<name>=green@<head>.
hasin "$OUT1" "PR#334 no external approving review at the live head HEAD334" \
  && ok "(29) approval pinned to an OLD commit -> held (approval is head-bound)" \
  || bad "(29) stale approval must not satisfy the gate (got: $OUT1)"
has '^334$' "$TMP/merged" && bad "(29) stale-approval PR must NOT be merged" \
                          || ok "(29) stale-approval PR not merged"

# (30) PAGINATION. 335's only approval sits on page 2 of the reviews history; the
# stub serves page 2 ONLY to a caller that passed --paginate, exactly as GitHub
# does. An unpaginated read sees just the city's own COMMENTED review and holds
# forever — a PR that can never merge no matter how many humans approve it.
has '^335$' "$TMP/merged" \
  && ok "(30) approval on page 2 is found (reviews read is paginated)" \
  || bad "(30) unpaginated reviews read misses the approval and strands the PR (got: $OUT1)"

# (30b) the DANGEROUS half of the same bug: 336's reviewer approved on page 1 and
# then requested changes on page 2. Truncated at page 1, the retracted approval
# reads as the effective verdict and the PR merges over a standing objection. The
# effective verdict is the LATEST verdict-bearing review per reviewer.
#
# The hold now names the VETO rather than the missing approval (tk-bdfww: a
# standing CHANGES_REQUESTED holds every candidate, so it is reached before the
# approval-specific branch). Same proof either way, and a strictly stronger one:
# reaching the veto at all requires the page-2 CHANGES_REQUESTED to have been read
# AND to have superseded the page-1 APPROVED — had the tail been missed, `.veto`
# would be empty and the earlier approval would have satisfied the gate.
hasin "$OUT1" "PR#336 external reviewer 'johnzook' has a standing CHANGES_REQUESTED" \
  && ok "(30b) a later CHANGES_REQUESTED supersedes the same reviewer's earlier APPROVED" \
  || bad "(30b) superseded approval must not satisfy the gate (got: $OUT1)"
has '^336$' "$TMP/merged" && bad "(30b) PR with a standing CHANGES_REQUESTED must NOT be merged" \
                          || ok "(30b) later-CHANGES_REQUESTED PR not merged"

# (31) THE STALE-SNAPSHOT RACE. The anchor rows are enumerated BEFORE each PR is
# read, and the signoff path writes the anchor concurrently: stamp check.<gate>,
# record signoff_dismissed, dismiss the GitHub review that was keeping the PR
# non-CLEAN. A pass that captured the row mid-sequence sees a CLEAN PR and a
# snapshot with NO signoff_dismissed — so it computes needs_approval from state
# that is already false and merges past the external approval the dismissal
# exists to require. The fix re-reads the anchor after the PR read.
hasin "$OUT1" "PR#337 no external approving review at the live head HEAD337 (signoff_dismissed=904@HEAD337" \
  && ok "(31) signoff_dismissed recorded mid-pass -> approval gate armed from the FRESH read" \
  || bad "(31) stale-snapshot signoff_dismissed must arm the approval gate (got: $OUT1)"
# (31b) the same staleness for the operator gate: merge_hold set while the pass
# is in flight must hold this pass, not the next one.
hasin "$OUT1" "PR#338 merge_hold set (operator gate)" \
  && ok "(31b) merge_hold set mid-pass -> honored from the FRESH read" \
  || bad "(31b) stale-snapshot merge_hold must hold the merge (got: $OUT1)"
# (31c) and for the per-gate marker: a re-gate that cleared/moved check.codex
# while the pass was in flight must re-gate, not merge on the snapshot's green.
hasin "$OUT1" "PR#339 check 'codex' not green at live head (have 'green@OLD339'" \
  && ok "(31c) check.<gate> changed mid-pass -> re-gated from the FRESH read" \
  || bad "(31c) stale-snapshot check marker must re-gate (got: $OUT1)"
# (19d) FAIL-CLOSED: an anchor whose live metadata cannot be read is skipped, not
# validated against the snapshot the race is about.
hasin "$ERR1" "anchor bead-SHOWFAIL metadata re-read failed" \
  && ok "(19d) unreadable anchor metadata -> skipped (never falls back to the stale row)" \
  || bad "(19d) unreadable re-read must skip the anchor (got: $ERR1)"

# (32) DISMISSED SHADOWS AN OLDER APPROVAL. johnzook approved at the live head and
# that approval was then retracted (its own row becomes DISMISSED). Filtering the
# terminal states BEFORE grouping dropped the DISMISSED row, so the older APPROVED
# resurfaced as the reviewer's effective verdict and satisfied the gate — an
# approval explicitly taken back landing the PR.
hasin "$OUT1" "PR#341 no external approving review at the live head HEAD341" \
  && ok "(32) a later DISMISSED shadows the same reviewer's earlier APPROVED" \
  || bad "(32) dismissed approval must not be resurrected (got: $OUT1)"
# (32b) one approval does not answer ANOTHER reviewer's standing objection. On an
# unprotected repo mergeStateStatus is CLEAN straight through a CHANGES_REQUESTED,
# so accepting any single APPROVED merged past a live veto.
hasin "$OUT1" "PR#342 external reviewer 'otherhuman' has a standing CHANGES_REQUESTED" \
  && ok "(32b) another reviewer's standing CHANGES_REQUESTED vetoes the merge" \
  || bad "(32b) standing changes-request must veto the merge (got: $OUT1)"
# (32c) and the veto is not an over-hold: a reviewer who requested changes and
# then approved the head has no standing objection left, so the PR lands.
has '^343$' "$TMP/merged" \
  && ok "(32c) CHANGES_REQUESTED superseded by the SAME reviewer's APPROVED -> merged" \
  || bad "(32c) superseded veto must not hold the merge forever (got: $OUT1)"

# (33) HEAD-MATCHED MERGE. Every gate above is bound to the head validated in this
# pass; the merge call was not, so a push between validation and merge squashed a
# commit nothing had looked at. The merge now passes --match-head-commit.
grep -q '^301	HEAD301$' "$TMP/mergeargs" \
  && ok "(33) merge is head-matched (--match-head-commit at the validated head)" \
  || bad "(33) merge must pass --match-head-commit (got: $(cat "$TMP/mergeargs"))"
# (33b) and the binding is load-bearing: PR 344's head moved after validation, so
# GitHub refuses the merge and the anchor is held for the next pass rather than
# landing an unvalidated head.
hasin "$ERR1" "PR#344 merge attempt failed" \
  && ok "(33b) head moved after validation -> merge REFUSED and held" \
  || bad "(33b) head-mismatch merge must fail and hold (got: $ERR1)"
has '^bead-HEADMOVE$' "$TMP/closed" \
  && bad "(33b) a refused merge must NOT close the anchor" \
  || ok "(33b) refused merge leaves the anchor OPEN for the next pass"

# (34) THE FRESH READ MUST STILL BE THE ANCHOR. Re-reading the bead and then
# validating it anyway is only half a guard: what made "$id gates PR#$num" true
# was the enumeration's own filter (open + merge_result=pull_request + this
# pr_number), and the re-read exists precisely because the anchor may have moved
# since. An anchor whose pr_number was CLEARED mid-pass no longer claims any PR —
# but the empty value slipped through the `-n` mismatch guard, so every gate below
# went on validating the snapshot's PR#$num and the merge landed on a claim the
# live bead no longer makes.
hasin "$ERR1" "anchor bead-RACENOPR no longer names exactly one PR in this repository" \
  && ok "(34) pr_number cleared mid-pass -> skipped (empty is unusable, not 'unchanged')" \
  || bad "(34) empty fresh pr_number must skip the anchor (got: $ERR1)"
# (34b) the same for an anchor that CLOSED mid-pass: it left the gating set, so
# nothing about it may be validated, let alone merged.
hasin "$ERR1" "anchor bead-RACECLOSED is no longer open (status='closed')" \
  && ok "(34b) anchor closed mid-pass -> skipped (no longer a gating anchor)" \
  || bad "(34b) closed anchor must skip (got: $ERR1)"
# (34c) and for one un-parked from its PR (merge_result cleared): the bead is no
# longer parked on a published PR, so it cannot speak for the merge either.
hasin "$ERR1" "anchor bead-RACEUNPARK no longer parked on a published PR" \
  && ok "(34c) merge_result cleared mid-pass -> skipped (not PR-parked any more)" \
  || bad "(34c) un-parked anchor must skip (got: $ERR1)"

# (35) FAIL CLOSED ON A PARTIAL REVIEW HISTORY. `gh api --paginate` streams each
# page as it arrives, so a call that dies at page 2 still leaves page 1 on stdout:
# a parseable, complete-LOOKING history. PR 348's page 1 holds johnzook's APPROVED
# and page 2 the same reviewer's later CHANGES_REQUESTED — so read without its
# exit status, the truncation converts a vetoed PR into an approved one. This is
# case (30b) arriving through the error path instead of the paging one.
hasin "$OUT1" "PR#348 reviews history read FAILED" \
  && ok "(35) a paginated reviews read that FAILS part way -> merge held (partial history is not evidence)" \
  || bad "(35) partial reviews read must hold the merge (got: $OUT1)"

# (36) TRUSTED APPROVER, not merely a non-self one. On an unprotected repo this
# gate is the whole approval policy, and any GitHub account can submit an APPROVED
# review — so "the login is not ours" would let a read-only collaborator land the
# PR. readonlyhuman is a real collaborator whose permission is `read`.
hasin "$OUT1" "PR#349 approved at the live head HEAD349 by 'readonlyhuman', but no approver satisfies the trusted-approver policy" \
  && ok "(36) approval by a read-only account -> held, naming the untrusted approver and the policy" \
  || bad "(36) untrusted approval must hold the merge (got: $OUT1)"
hasin "$OUT1" "PR#349 .*MERGE_TRUSTED_APPROVERS" \
  && ok "(36) the hold names the remedy (grant write access or allowlist)" \
  || bad "(36) untrusted-approval hold must name a remedy (got: $OUT1)"
# (36b) an account the permission probe cannot resolve at all (a drive-by bot,
# 404) is untrusted for the same reason an unreadable probe is: we cannot show it
# may write here.
hasin "$OUT1" "PR#350 approved at the live head HEAD350 by 'driveby-bot'" \
  && ok "(36b) approval by an account with no resolvable permission -> held (unreadable is untrusted)" \
  || bad "(36b) unresolvable approver must hold the merge (got: $OUT1)"
# (36c) and the policy filters CANDIDATES rather than stopping at the first one:
# PR 351 was approved by both readonlyhuman (untrusted) and johnzook (admin), so
# the trusted approval still satisfies the gate.
has '^351$' "$TMP/merged" \
  && ok "(36c) an untrusted approval alongside a trusted one -> merged (candidates are filtered, not first-wins)" \
  || bad "(36c) a trusted approval must still satisfy the gate (got: $OUT1)"

# (13)-(16),(19) tk-lgjvg: the child gate resolves holders by DEPENDENCY as well
# as by pr_number, over every live status, and fails CLOSED when it cannot look.
grep -q "PR#315 has unclosed rework/review bead depchild-315 (open)" <<< "$OUT1" \
  && ok "(13) dep-linked child with NO pr_number -> held (the fail-open defect)" \
  || bad "(13) dep-linked child must hold the merge (got: $OUT1)"
grep -q "PR#316 has unclosed rework/review bead blockedkid-316 (blocked)" <<< "$OUT1" \
  && ok "(14) dep-linked child in status 'blocked' -> held (all children CLOSED, not just open)" \
  || bad "(14) blocked dep-linked child must hold (got: $OUT1)"
grep -q "PR#317 has unclosed rework/review bead prblocked-317 (blocked)" <<< "$OUT1" \
  && ok "(15) pr_number child in status 'blocked' -> held (probe asks for every live status)" \
  || bad "(15) blocked pr_number child must hold (got: $OUT1)"
grep -q "PR#318 has unclosed rework/review bead review-318 (open)" <<< "$OUT1" \
  && ok "(16) review bead attached as a 'blocks' dep of the anchor -> held" \
  || bad "(16) blocking review bead must hold (got: $OUT1)"
grep -q "PR#321 in-flight rework/review probe failed; merge held" <<< "$OUT1" \
  && ok "(19) unreadable child probe -> held (fail closed, not merged past)" \
  || bad "(19) probe failure must fail CLOSED (got: $OUT1)"

# (20)-(21) tk-je0rk: a holder reached by a DEPENDENCY EDGE holds regardless of
# merge_result. The exclusion is for duplicate anchors the pr_number probe swept
# up — applied to the whole holder set it deleted the one holder shape that
# carries merge_result by definition (an upstream PR / pre-open anchor filed as
# an explicit merge-ordering block), and the downstream PR merged past it.
grep -q "PR#322 has unclosed rework/review bead upstream-322 (open, merge_result=pull_request)" <<< "$OUT1" \
  && ok "(20) live merge_result=pull_request blocker -> held (dep-edge holder survives the exclusion)" \
  || bad "(20) an upstream PR blocker must hold the merge (got: $OUT1)"
grep -q "PR#323 has unclosed rework/review bead kidanchor-323 (open, merge_result=pre_open_gate)" <<< "$OUT1" \
  && ok "(21) live merge_result=pre_open_gate dep child -> held, reason names the marker" \
  || bad "(21) a gating dep-linked child must hold the merge (got: $OUT1)"

# (22)-(23) tk-qoyly: a probe can SUCCEED and still be unreadable. Both anchors
# below get exit 0 and a valid top-level JSON array, so neither is a probe
# "failure" in the (19) sense — and both would have merged past their holder,
# because an aborted jq is byte-identical to "no children" once stderr is
# suppressed. The two land in DIFFERENT fail-closed branches on purpose: (22) is
# rejected at the probe boundary by the per-element shape check, while (23) is
# structurally valid and survives to abort the holder filter itself. Asserting
# each on its own message is what keeps the two guards independently pinned — a
# single "is it held" assertion would stay green if either layer were deleted.
grep -q "PR#324 in-flight rework/review probe failed; merge held" <<< "$OUT1" \
  && ok "(22) malformed holder element (metadata not an object) -> held at the probe boundary" \
  || bad "(22) a malformed holder element must fail CLOSED (got: $OUT1)"
grep -q "PR#325 in-flight holder filter unreadable; merge held" <<< "$OUT1" \
  && ok "(23) shape-valid holder that aborts the filter (non-string status) -> held by the filter guard" \
  || bad "(23) a holder filter that ERRORS must fail CLOSED, not read as empty (got: $OUT1)"

# (24) THE PROVENANCE-MERGE POSITIVE CONTROL. bothsrc-326 is returned by BOTH
# probes and carries merge_result=pre_open_gate — the exact shape the pr_number
# exclusion drops. Dedup must UNION provenance (group_by) so the dep sighting
# wins and the holder survives; a unique_by(.id) that kept the first-sorted copy
# would class it pr_number, apply the exclusion, and merge past a live child.
grep -q "PR#326 has unclosed rework/review bead bothsrc-326 (open, merge_result=pre_open_gate)" <<< "$OUT1" \
  && ok "(24) holder seen by BOTH pr_number and dep probes -> held (provenance unions to 'dep')" \
  || bad "(24) a both-source holder must not be demoted into the excludable pr_number class (got: $OUT1)"

# (25)-(26) tk-wkrcy: a probe payload can be MORE THAN ONE JSON document and still
# clear a `jq -e` run over the raw stream, because -e reports the exit status of
# the LAST output only. That is not a cosmetic mis-validation. probe_holders reads
# the three payloads POSITIONALLY out of one slurped stream (.[0]/.[1]/.[2]), so
# an extra leading document shifts every later probe down a slot and the third one
# falls off the end entirely.
#
# Both anchors here are otherwise PERFECT merge candidates — CLEAN, base==target,
# check.codex green at the live head, no pr_number child — and each has ONE real
# holder, an open `blocks` blocker carrying merge_result=pull_request, delivered
# through the `down` walk that the poisoned payload does NOT supply. Pre-fix that
# blocker landed at .[3], was never read, and the PR squash-merged straight past
# its merge-ordering block. Verified directly against the pre-fix jq: by_pr `[]` +
# children `{} []` + blockers `[blocker-327]` slurps to four documents and the
# holder projection returns `[]`.
#
# The two payloads split the guard from the shape checks. (25) leads with `{}`,
# the realistic pollution shape (a stray object on stdout ahead of the real
# answer). (26) is `[]` then `[]` — every document individually valid and
# array-shaped, so NOTHING but the document COUNT is wrong; it stays green only
# while the count check itself is present.
grep -q "PR#327 in-flight rework/review probe failed; merge held" <<< "$OUT1" \
  && ok "(25) multi-document probe payload ('{}' then '[]') -> held (count check, blocker not shifted away)" \
  || bad "(25) a multi-document probe must fail CLOSED, not drop the later probe (got: $OUT1)"
grep -q "PR#328 in-flight rework/review probe failed; merge held" <<< "$OUT1" \
  && ok "(26) two well-formed arrays in one payload ('[]' then '[]') -> held (only the count is wrong)" \
  || bad "(26) document COUNT alone must fail CLOSED (got: $OUT1)"
has '^327$' "$TMP/merged" && bad "(25) PR#327 must NOT be merged past its blocker" \
                          || ok "(25) PR#327 never reached gh pr merge"
has '^328$' "$TMP/merged" && bad "(26) PR#328 must NOT be merged past its blocker" \
                          || ok "(26) PR#328 never reached gh pr merge"

# (9) already-merged anchor is NOT closed by the skill (the observer records it).
has '^bead-MERGED$' "$TMP/closed" && bad "(9) already-merged anchor must NOT be closed by the skill" \
                                  || ok "(9) already-merged anchor left for the observer"

# (37) THE FAIL-OPEN CHILD PROBE. The in-flight-child gate is what makes "an
#      anchor lands only when ALL its children are closed" true, and it used to
#      decide from a bare `gc bd list | jq` tested only for non-emptiness. A read
#      that FAILED produced the same empty answer as "no child", and the pass
#      walked straight on to CLEAN and `gh pr merge` — an unreadable ledger
#      merging past an open rework child. Now the read's status is checked.
#      An unreadable ledger is a TOOL error, so the hold is reported on stderr
#      alongside the failed PR read and the failed anchor re-read, not on the
#      stdout decision stream.
hasin "$ERR1" "PR#352 referencing-bead read FAILED" \
  && ok "(37) unreadable child probe (non-zero exit) -> merge HELD, and the hold says why" \
  || bad "(37) failed child probe must hold (got: $ERR1)"
has '^352$' "$TMP/merged" && bad "(37) a PR whose child probe FAILED must not merge" \
                          || ok "(37) PR with a failed child probe not merged"
# (37b) The sharper shape: `gc ... --json` reporting its own failure as a JSON
#       OBJECT on stdout with a ZERO exit status. Non-empty and parseable, so an
#       emptiness test AND an exit-status test both wave it through; only the
#       array-shape guard rejects it.
hasin "$ERR1" "PR#353 referencing-bead read FAILED" \
  && ok "(37b) child probe returning an error OBJECT at exit 0 -> merge HELD (array-shape guard)" \
  || bad "(37b) error-object child probe must hold (got: $ERR1)"
has '^353$' "$TMP/merged" && bad "(37b) a PR whose child probe returned an error object must not merge" \
                          || ok "(37b) PR with an error-object child probe not merged"
# (37c) A child parked in `blocked` owes exactly as much work as an open one — it
#       is just not on a hook. Keyed on open,in_progress alone it was invisible.
hasin "$OUT1" "PR#354 has unclosed rework/review bead child-354 (blocked)" \
  && ok "(37c) a BLOCKED child holds the merge (the gate reads every non-closed status)" \
  || bad "(37c) blocked child must hold (got: $OUT1)"
has '^354$' "$TMP/merged" && bad "(37c) a PR with a blocked child must not merge" \
                          || ok "(37c) PR with a blocked child not merged"
# (25d) A child that names its PR with `fork_pr` and no pr_number at all. The
#       reconciler already reads all three PR keys; keyed on pr_number alone this
#       gate could not see such a child holding the PR.
hasin "$OUT1" "PR#355 has unclosed rework/review bead forkchild-355 (open)" \
  && ok "(25d) a fork_pr-keyed child holds the merge (PR keys match the reconciler's)" \
  || bad "(25d) fork_pr-keyed child must hold (got: $OUT1)"
has '^355$' "$TMP/merged" && bad "(25d) a PR with a fork_pr-keyed child must not merge" \
                          || ok "(25d) PR with a fork_pr-keyed child not merged"

# (38) DUPLICATE ANCHOR APPEARING MID-PASS. The one-anchor-per-PR guard used to be
#      precomputed once from the enumeration snapshot, before any PR was read, so
#      a second gating anchor created or reclassified after that snapshot was not
#      in the set — and, carrying merge_result, it was excluded from the child
#      hold too. This pass would then validate and merge PR#356 under the current
#      anchor's gates alone while a stronger duplicate gate existed. The guard is
#      computed from the LIVE ledger now, in the same place and for the same
#      reason the anchor itself is re-read.
hasin "$OUT1" "PR#356 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-LIVEDUP)" \
  && ok "(38) duplicate anchor visible only in the LIVE ledger -> merge HELD (stale snapshot missed it)" \
  || bad "(38) live duplicate anchor must hold (got: $OUT1)"
has '^356$' "$TMP/merged" && bad "(38) a PR with a mid-pass duplicate anchor must not merge" \
                          || ok "(38) PR with a live duplicate anchor not merged"

# (39) THE APPROVAL DETECTOR'S OWN PIPELINE. `approval` was matched by piping jq
#      into `grep -qxF approval` under `set -o pipefail`. `grep -q` exits at the
#      FIRST match, closing the pipe under jq while it still has gates to write;
#      jq takes SIGPIPE, the pipeline reports 141, and the trailing
#      `&& needs_approval=1` never runs — so a check_set that DOES name approval
#      reads as one that does not. On this CLEAN, unprotected-repo PR with zero
#      approving reviews, that merged unapproved work. See the fixture note above
#      for why the check_set is thousands of gates wide: it makes the race
#      deterministic. The fix drops the pipeline, so length stops mattering.
hasin "$OUT1" "PR#357 no external approving review at the live head" \
  && ok "(39) long check_set naming approval -> HELD on the APPROVAL gate (no SIGPIPE miss)" \
  || bad "(39) long check_set must still arm the approval gate (got: $OUT1)"
has '^357$' "$TMP/merged" && bad "(39) an approval-armed PR must not merge on a long check_set" \
                          || ok "(39) long-check_set approval-armed PR not merged"

# (40) THE MANUAL-DISMISSAL HOLE (tk-tmefn). The approval requirement used to be
#      armed by exactly two bead-side facts: `approval` in check_set, or the
#      anchor's signoff_dismissed marker. Both describe dismissals the CITY
#      performed IN-BAND. An operator who clears the stale city
#      CHANGES_REQUESTED by hand on github.com writes neither — and on an
#      unprotected repo with no CI, that hand-clearing is exactly what turns
#      mergeStateStatus CLEAN. So the PR presented as: codex gate green at the
#      live head, no open child, no marker, CLEAN — and merged, with the only
#      review anyone ever posted having been a block that was silently taken
#      back. The gate now reads the DISMISSAL ITSELF out of the reviews history,
#      which is the side that cannot be bypassed by omitting a marker.
hasin "$OUT1" "PR#358 no external approving review at the live head HEAD358 (a review authored by 'zook-bot' was DISMISSED on this PR (1x)" \
  && ok "(40) hand-dismissed self CHANGES_REQUESTED, no marker -> HELD, reason names the dismissal" \
  || bad "(40) a manually dismissed city block must arm the approval gate (got: $OUT1)"
has '^358$' "$TMP/merged" && bad "(40) a PR CLEAN only because our own block was hand-dismissed must NOT merge" \
                          || ok "(40) hand-dismissed PR not merged"
# (40b) The arm counts the WHOLE history, not the latest review per author: the
#       city posts a COMMENT every signoff round, and fixture 358's comment is
#       NEWER than the dismissal. Grouping by author and taking the latest would
#       let that comment shadow the dismissal away and re-open the hole — the
#       same shape as the DISMISSED-shadows-APPROVED case (341) inverted.
#       Covered by (40): its hold proves the later COMMENT did not shadow it.
#
# (40c) NOT over-holding. A dismissal makes an external approval REQUIRED, not
#       impossible — 359 is 358 plus a trusted admin approval at the live head,
#       and it must land. Without this the fix would strand every PR the city
#       ever blocked, which is a worse bug than the one it closes.
has '^359$' "$TMP/merged" \
  && ok "(40c) hand-dismissed PR WITH a trusted approval at the live head -> merged" \
  || bad "(40c) the dismissal arm must require an approval, not forbid the merge"
has '^bead-HANDDISMISS-OK$' "$TMP/closed" \
  && ok "(40c) approved hand-dismissed anchor closed (record)" \
  || bad "(40c) approved hand-dismissed anchor closed"
# (28d) PAGINATED. A dismissal in the tail is invisible to an unpaginated read,
#       and missing it fails OPEN (the PR merges unapproved) — the same reason
#       the approval read itself is paginated. 360's DISMISSED row is on page 2.
hasin "$OUT1" "PR#360 no external approving review at the live head HEAD360 (a review authored by 'zook-bot' was DISMISSED on this PR (1x)" \
  && ok "(28d) self dismissal on PAGE 2 still arms the gate (paginated read)" \
  || bad "(28d) a page-2 dismissal must not be missed (got: $OUT1)"
has '^360$' "$TMP/merged" && bad "(28d) a PR whose page-2 dismissal was missed must not merge" \
                          || ok "(28d) page-2 hand-dismissed PR not merged"

# (41) THE VETO IS NOT PART OF THE APPROVAL GATE (tk-bdfww). 361 is the ordinary
#      case, and that is the point: check_set is plain `codex`, the marker is
#      green at the live head, there is no `approval` member, no
#      signoff_dismissed, and nothing dismissed anywhere in the history — so the
#      approval branch is never armed. The veto lived INSIDE that branch, so this
#      anchor never looked at the one review anyone posted: an external human's
#      standing CHANGES_REQUESTED. The repo is unprotected, mergeStateStatus is
#      CLEAN straight through an open objection, and the pass squash-merged past
#      it. Nothing else on the PR was wrong, which is why it went unnoticed —
#      every gate that WAS consulted was green. Whether a rig declares `approval`
#      says nothing about whether another human's "not this" still counts.
hasin "$OUT1" "PR#361 external reviewer 'otherhuman' has a standing CHANGES_REQUESTED" \
  && ok "(41) codex-only CLEAN anchor with an external CHANGES_REQUESTED -> held on the veto" \
  || bad "(41) a standing changes-request must veto a codex-only merge (got: $OUT1)"
hasin "$OUT1" "PR#361 external reviewer 'otherhuman' has a standing CHANGES_REQUESTED — a latest changes-request vetoes the merge regardless of the check-set" \
  && ok "(41) the hold reason says the veto is check-set independent" \
  || bad "(41) veto hold reason (got: $OUT1)"
has '^361$' "$TMP/merged" \
  && bad "(41) a PR with a live human objection must NOT merge on a codex-only check_set" \
  || ok "(41) codex-only vetoed PR not merged"
# (41b) NOT over-holding, and the reason it cannot be written as "any
#       CHANGES_REQUESTED in the history": 362 is 361 with that same reviewer's
#       later APPROVED. The objection is withdrawn, so the merge proceeds — on
#       the codex gate alone, since check_set never named `approval` and the
#       approval here is not a gate being satisfied, only a veto being lifted. A
#       naive hoist that scanned the raw history instead of each reviewer's
#       LATEST verdict would strand every PR that ever took a review round.
has '^362$' "$TMP/merged" \
  && ok "(41b) veto superseded by the same reviewer's later APPROVED -> merged (codex gate alone)" \
  || bad "(41b) a withdrawn objection must not hold the merge forever (got: $OUT1)"
has '^bead-CODEXVETO-OK$' "$TMP/closed" \
  && ok "(41b) superseded-veto anchor closed (record)" \
  || bad "(41b) superseded-veto anchor closed"

# (INV) exactly twelve PRs were merged: the fully-validated gated head (301), the
# no-gate PR (311), the explicit opt-out (314), the two approval-satisfied PRs
# (330, 333), the page-2 approval (335), the superseded-veto PR (343), the
# mixed trusted/untrusted approval (351), the hand-dismissed PR that DID
# collect a trusted approval (359), and the codex-only PR whose objection was
# withdrawn (362). No held/skipped anchor leaked.
# =============================================================================
# THE TERMINAL ANCHOR RE-READ (review tk-tbacg finding #1).
# =============================================================================
# `--match-head-commit` binds the merge to the validated COMMIT; nothing bound it
# to the validated BEAD. Between the last gate and `gh pr merge` sit the PR read,
# the referencing-bead query, the holder probes and the reviews history — every one
# a round-trip another writer can act inside. Each case below passes EVERY gate on
# the first anchor read and then changes the bead WITHOUT moving the PR head, so
# the head-match cannot see it and only a re-read of the bead can.
#
# These run against RUN 1 above ($TMP/anchors-final is served from each anchor's
# SECOND `gc bd show` on).
has '^374$' "$TMP/merged" \
  && bad "(TR1) merge_hold set after validation must NOT merge" \
  || ok "(TR1) merge_hold set between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALHOLD changed between validation and the merge — merge_hold was set after validation" \
  && ok "(TR1) the hold names the anchor and what changed" \
  || bad "(TR1) hold reason must name the anchor and the merge_hold change"

has '^375$' "$TMP/merged" \
  && bad "(TR2) a gate that moved off the validated head must NOT merge" \
  || ok "(TR2) check.codex re-gated between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALGATE changed between validation and the merge — check 'codex' is no longer green at HEAD375" \
  && ok "(TR2) the hold names the gate and the head it is no longer green at" \
  || bad "(TR2) hold reason must name the gate and the head"

has '^376$' "$TMP/merged" \
  && bad "(TR3) an anchor closed after validation must NOT merge" \
  || ok "(TR3) anchor closed between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALCLOSED changed between validation and the merge — anchor is no longer open" \
  && ok "(TR3) the hold names the closure" \
  || bad "(TR3) hold reason must name the closure"

has '^377$' "$TMP/merged" \
  && bad "(TR4) an anchor retargeted onto another PR must NOT merge this one" \
  || ok "(TR4) anchor retargeted between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALPR changed between validation and the merge — anchor now claims '999', not PR#377" \
  && ok "(TR4) the hold names both pull requests" \
  || bad "(TR4) hold reason must name both PR numbers"

# UNREADABLE, not merely changed. A merge is the one act this pass cannot retract,
# so "I could not re-confirm the authorization" has to hold exactly as a positive
# mismatch does — the same fail-closed rule the earlier re-read follows.
has '^378$' "$TMP/merged" \
  && bad "(TR5) an unreadable terminal re-read must NOT merge" \
  || ok "(TR5) terminal re-read unreadable -> held"
hasin "$OUT1" "anchor bead-FINALFAIL could not be re-read immediately before the merge" \
  && ok "(TR5) the hold says the bead could not be re-read" \
  || bad "(TR5) hold reason must say the anchor could not be re-read"

# THE CONTROL. A gate that never lets anything through is not a gate. 379's bead is
# in the final file UNCHANGED, so the terminal read confirms exactly what the first
# one validated and the merge proceeds.
has '^379$' "$TMP/merged" \
  && ok "(TR6) an anchor still authorizing its merge at the terminal read MERGES" \
  || bad "(TR6) the terminal re-read must not hold a merge that is still authorized"

# -----------------------------------------------------------------------------
# THE REST OF THE ANCHOR-LOCAL AUTHORIZATION SET (review tk-78ty5 finding #2).
# -----------------------------------------------------------------------------
# TR1-TR5 cover the five fields the first version of this gate re-read. These four
# cover the ones it did NOT, and they are not a different KIND of hazard — each is
# a bead-local fact that authorizes the merge, written inside the same window, and
# invisible to `--match-head-commit` for the same reason: none of them move the
# head. A gate that re-reads five of nine authorizing fields is a gate with four
# holes in it.
has '^385$' "$TMP/merged" \
  && bad "(TR7) a signoff_dismissed arriving after the approval gate must NOT merge" \
  || ok "(TR7) signoff_dismissed written between the approval gate and the merge -> held"
hasin "$OUT1" "anchor bead-FINALDISMISS changed between validation and the merge — signoff_dismissed changed after the approval gate ran ('unset' -> '950@HEAD385')" \
  && ok "(TR7) the hold names the marker and both values" \
  || bad "(TR7) hold reason must name signoff_dismissed and what it changed from/to"

has '^386$' "$TMP/merged" \
  && bad "(TR8) a SAME-HEAD retarget must NOT merge (it lands on the wrong branch)" \
  || ok "(TR8) merged_target repointed between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALRETARGET changed between validation and the merge — anchor was retargeted after validation (merged_target='integration/foo', PR base 'main')" \
  && ok "(TR8) the hold names the new target and the live base" \
  || bad "(TR8) hold reason must name both branches"

has '^387$' "$TMP/merged" \
  && bad "(TR9) a pr_url naming another repository must NOT merge this PR" \
  || ok "(TR9) pr_url repaired to a foreign PR between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALURL changed between validation and the merge — anchor now records pr_url 'https://github.com/acme/OTHER/pull/387'" \
  && ok "(TR9) the hold names the URL the bead now claims" \
  || bad "(TR9) hold reason must name the conflicting pr_url"

has '^388$' "$TMP/merged" \
  && bad "(TR10) a branch naming different work must NOT merge" \
  || ok "(TR10) branch repaired to another branch between validation and merge -> held"
hasin "$OUT1" "anchor bead-FINALBRANCH changed between validation and the merge — anchor now records branch 'polecat/somebody-else' but PR#388 is opened from 'polecat/bead-FINALBRANCH'" \
  && ok "(TR10) the hold names both branches" \
  || bad "(TR10) hold reason must name the bead's branch and the PR's"

# =============================================================================
# FORK-KEYED ANCHOR IDENTITY (review tk-tbacg finding #2).
# =============================================================================
# The holder probe and reconcile-merged-prs.sh's ownership set both read every
# PR-naming key (pr_number, fork_pr, fork_pr_url). The anchor's own identity read
# pr_number ALONE, so a live `merge_result=pull_request` anchor keyed only by
# fork_pr was skipped here every pass while reconcile counted it owned and stayed
# silent — a PR that nothing lands and nothing reports.
has '^380$' "$TMP/merged" \
  && ok "(FK1) an anchor keyed only by fork_pr is mergeable" \
  || bad "(FK1) fork_pr-keyed anchor must merge (pre-fix: skipped forever, and never reported)"
has '^381$' "$TMP/merged" \
  && ok "(FK2) an anchor keyed only by fork_pr_url is mergeable" \
  || bad "(FK2) fork_pr_url-keyed anchor must merge"

# ...but only for a URL that names THIS repository. A number scanned out of a
# foreign fork_pr_url is about somebody else's pull request; acting on it would
# merge a stranger's PR number in origin. Same `in_repo` rule reconcile applies.
has '^382$' "$TMP/merged" \
  && bad "(FK3) a fork_pr_url naming ANOTHER repository must not make its number ours" \
  || ok "(FK3) foreign fork_pr_url -> not a merge candidate here"

# Several keys DISAGREEING is not a number to pick from. Merging then means
# guessing which pull request the bead means, and a wrong guess lands the wrong PR.
has '^384$' "$TMP/merged" && bad "(FK4) an ambiguous anchor must not merge the fork_pr number" || ok "(FK4) ambiguous anchor did not merge its fork_pr number"
has '^383$' "$TMP/merged" \
  && bad "(FK4) an anchor naming two different PR numbers must not merge either" \
  || ok "(FK4) pr_number and fork_pr disagreeing -> merge held, not guessed"
hasin "$OUT1" "anchor bead-TWOKEYS names more than one PR number in this repository (383, 384)" \
  && ok "(FK4) the hold names every number the anchor claims" \
  || bad "(FK4) hold reason must list the conflicting numbers"

eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "18" "(INV) exactly eighteen PRs merged (301 + 311 + 314 + unholdable children 319, 320 + approved 330, 333, 335, 343, 351, 359, 362 + cross-repo 364, 365 + head-certified 372 + terminal-re-read control 379 + fork-keyed 380, 381)"
# Every merge that was PERFORMED bound itself to the head it validated — no
# unbound `gh pr merge` slipped through on any path.
eq "$(awk -F'\t' '$2 == "" {c++} END {print c+0}' "$TMP/mergeargs")" "0" \
   "(INV) every merge attempt passed --match-head-commit"

# Summary counters.
hasin "$OUT1" "18 merged" \
  && ok "run 1 summary reports 18 merged" || bad "run 1 summary merged count (got: $OUT1)"

# --- Field-shape guard for the approval gate's own reads. ---------------------
gh pr view 301 --json reviewDecision >/dev/null 2>&1 \
  && ok "(FS) reviewDecision is an accepted gh field" \
  || bad "(FS) the approval gate's --json field must be accepted"
# latestReviews is deliberately NOT read: it carries no commit per verdict, so it
# cannot head-bind an approval (tk-5niup). The stub drops it from the supported
# set so a future edit reaching for it fails loudly instead of silently
# reintroducing the stale-approval hole.
gh pr view 301 --json latestReviews >/dev/null 2>&1 \
  && bad "(FS) latestReviews must not be reintroduced (it cannot head-bind an approval)" \
  || ok "(FS) latestReviews stays out of the approval gate's reads"

# --- Unresolvable acting login -> approval gate HOLDS (fail-closed). ----------
# If we cannot tell which account is ours, we cannot exclude a self-approval, so
# an approval-armed anchor must hold rather than count an unattributable one.
# Run against ISOLATED ledger files so it cannot perturb the convergence run.
: > "$TMP/merged-nl"; : > "$TMP/closed-nl"
OUT_NL="$(FAKE_SELF_LOGIN="" FAKE_CLOSED="$TMP/closed-nl" FAKE_MERGED="$TMP/merged-nl" \
          FAKE_MERGEDREC="$TMP/mergedrec-nl" FAKE_CLOSELOG="$TMP/closelog-nl" bash "$SCRIPT")"
hasin "$OUT_NL" "PR#330 approval required but the acting login is unresolved" \
  && ok "(15d) unresolvable acting login -> approval-armed anchor held, not merged" \
  || bad "(15d) unresolved login must hold the approval gate (got: $OUT_NL)"
has '^330$' "$TMP/merged-nl" && bad "(15d) approval-armed PR must NOT merge with an unresolved login" \
                             || ok "(15d) approval-armed PR not merged with an unresolved login"
has '^301$' "$TMP/merged-nl" \
  && ok "(15d) an un-armed anchor still merges (the hold is scoped to approval-armed anchors)" \
  || bad "(15d) unresolved login must not hold anchors that never armed the gate"
# (28e) The dismissal arm with NO resolvable login. A dismissal cannot be
# ATTRIBUTED without knowing our own account, so the arm falls back to "was
# anything dismissed on this PR at all" — over-broad on purpose, and only on PRs
# whose review state someone has already been editing. 358's dismissal is still
# seen, so the hole does not re-open just because `gh api user` blipped; 301,
# which has no reviews at all, is untouched (asserted directly above), so the
# fallback cannot stall the whole queue.
has '^358$' "$TMP/merged-nl" \
  && bad "(28e) an unattributable dismissal must still arm the gate with no self-login" \
  || ok "(28e) unresolved login -> any dismissal arms the gate (hand-dismissed PR still held)"

# --- Allowlist mode: MERGE_TRUSTED_APPROVERS IS the policy. -------------------
# (24d) The escape hatch the untrusted hold names, and the reason it exists: a
# token that cannot read collaborator permissions would otherwise hold every PR
# forever. With the operator's allowlist set, the listed account satisfies the
# gate WITHOUT a permission probe — so readonlyhuman, held above, now lands PR
# 349. Isolated ledger files again so the convergence run is untouched.
: > "$TMP/merged-al"; : > "$TMP/closed-al"
OUT_AL="$(MERGE_TRUSTED_APPROVERS="readonlyhuman, someone-else" \
          FAKE_CLOSED="$TMP/closed-al" FAKE_MERGED="$TMP/merged-al" \
          FAKE_MERGEDREC="$TMP/mergedrec-al" FAKE_CLOSELOG="$TMP/closelog-al" bash "$SCRIPT")"
has '^349$' "$TMP/merged-al" \
  && ok "(24d) MERGE_TRUSTED_APPROVERS lists the approver -> merged (allowlist is the policy)" \
  || bad "(24d) an allowlisted approver must satisfy the gate (got: $OUT_AL)"
# (24e) and the allowlist REPLACES the permission probe rather than widening it:
# an account that is not listed is untrusted even with write access on the repo,
# so PR 350's bot and PR 351's johnzook-only path both stay held.
has '^350$' "$TMP/merged-al" \
  && bad "(24e) an unlisted account must NOT satisfy the allowlist policy" \
  || ok "(24e) allowlist mode holds an unlisted approver (the allowlist is exhaustive)"
hasin "$OUT_AL" "PR#350 .*trusted-approver policy (the MERGE_TRUSTED_APPROVERS allowlist)" \
  && ok "(24e) the hold names the ACTIVE policy (allowlist, not the permission probe)" \
  || bad "(24e) allowlist-mode hold must name the allowlist policy (got: $OUT_AL)"
# (24f) The allowlist decision must not depend on the LENGTH of the allowlist.
# Matching it by piping the list into `grep -qx` looks equivalent, but `grep -q`
# exits at the first match, and with `set -o pipefail` on, an upstream filter that
# is still writing then dies of SIGPIPE and the pipeline reports 141 — reading a
# TRUSTED approver as untrusted. The match is early here and the tail is far past
# a 64KiB pipe buffer, which is exactly the shape that trips it; the same
# allowlist, same approver, same expected merge as (24d).
#
# ~88KiB of filler is deliberate: comfortably past the 64KiB pipe capacity that
# makes an upstream writer block (and so take the SIGPIPE), while staying under
# the 128KiB per-string cap the kernel puts on one environment entry — overshoot
# that and the run dies with "Argument list too long" instead of testing anything.
: > "$TMP/merged-alw"; : > "$TMP/closed-alw"
AL_LONG="readonlyhuman,$(awk 'BEGIN{for(i=0;i<4000;i++)printf "filler-account-%06d,",i}')someone-else"
OUT_ALW="$(MERGE_TRUSTED_APPROVERS="$AL_LONG" \
           FAKE_CLOSED="$TMP/closed-alw" FAKE_MERGED="$TMP/merged-alw" \
           FAKE_MERGEDREC="$TMP/mergedrec-alw" FAKE_CLOSELOG="$TMP/closelog-alw" bash "$SCRIPT")"
has '^349$' "$TMP/merged-alw" \
  && ok "(24f) an early match in a >64KiB allowlist still merges (no SIGPIPE/pipefail misread)" \
  || bad "(24f) allowlist match must not depend on list length (got: $OUT_ALW)"
has '^350$' "$TMP/merged-alw" \
  && bad "(24f) a long allowlist must still be exhaustive for unlisted accounts" \
  || ok "(24f) a long allowlist stays exhaustive (unlisted approver still held)"

# (ID3) the anchor's own certified pr_url names a DIFFERENT pull request from the
# one that answered. Everything else about PR#363 is merge-ready (OPEN, non-draft,
# base==target, codex green@head, CLEAN), so the identity check is the only thing
# that can stop it — and it must, because one of the two names is wrong and nothing
# here can say which.
has '^363$' "$TMP/merged" && bad "(ID3) an anchor whose pr_url names another PR must NOT be merged" \
                          || ok "(ID3) pr_url/live-URL mismatch -> merge held"
hasin "$OUT1" "anchor bead-URLMISMATCH records pr_url 'https://github.com/acme/OTHER/pull/363'" \
  && ok "(ID3) the hold reason names both pull requests for an operator" \
  || bad "(ID3) hold reason must name the recorded pr_url (got: $OUT1)"

# (XREPO) BOTH hold guards are keyed on REPOSITORY + number, not the bare number.
# Each fails toward holding, so the bug they had was not a wrong merge — it was an
# indefinite hold on a ready PR that no repair in THIS repository could release
# (review tk-thvbq finding #4).
#
# (XREPO-DUP) PR#364 is claimed by our bead-XDUPOK (pr_number-only, so it keys on
# origin) and by bead-XDUPFOREIGN, whose pr_url names ANOTHER HOST's acme/repo.
# Keyed on "364" alone that is a one-anchor-per-PR violation and BOTH are held
# forever; keyed on repository+number the foreign anchor is a different pull
# request and ours merges.
has '^364$' "$TMP/merged" \
  && ok "(XREPO-DUP) a foreign same-numbered anchor is not a duplicate -> our PR#364 still merges" \
  || bad "(XREPO-DUP) PR#364 must merge; a foreign anchor must not make it multi-anchor (got: $OUT1)"
hasin "$OUT1" "PR#364 has multiple open gating anchors" \
  && bad "(XREPO-DUP) must NOT report a one-anchor-per-PR violation across repositories" \
  || ok "(XREPO-DUP) no false one-anchor-per-PR hold across repositories"
# ...and the foreign anchor is still refused, by the identity check that owns that
# job — the dup guard getting out of its way must not let it merge.
has '^bead-XDUPFOREIGN$' "$TMP/closed" \
  && bad "(XREPO-DUP) the foreign anchor must never be closed off our PR" \
  || ok "(XREPO-DUP) the foreign anchor is still refused by the pr_url identity check"
# The SAME-repository duplicate must still be held: the qualification only rules out
# a positive disagreement, it does not weaken the guard where it applies (313).
hasin "$OUT1" "PR#313 has multiple open gating anchors" \
  && ok "(XREPO-DUP) a same-repository duplicate is still held (guard not weakened)" \
  || bad "(XREPO-DUP) same-repository duplicates must still hold"

# (XREPO-CHILD) PR#365's only open child names another host's repository — it is
# somebody else's rework and can never land ours, so it must not hold. PR#366's
# child names THIS repository and must. The unqualified guard held both.
has '^365$' "$TMP/merged" \
  && ok "(XREPO-CHILD) a foreign same-numbered child does not hold -> PR#365 merges" \
  || bad "(XREPO-CHILD) PR#365 must merge; a foreign child cannot hold it (got: $OUT1)"
has '^366$' "$TMP/merged" \
  && bad "(XREPO-CHILD) a same-repository open child MUST still hold PR#366" \
  || ok "(XREPO-CHILD) a same-repository open child still holds the merge"
hasin "$OUT1" "PR#366 has unclosed rework/review bead child-same-366 (open)" \
  && ok "(XREPO-CHILD) the hold names the same-repository child" \
  || bad "(XREPO-CHILD) hold reason must name child-same-366 (got: $OUT1)"

# (CHILDFAIL) the child lookup FAILED (error object + exit 1). PR#367 has no child
# at all and is otherwise fully mergeable, so an unguarded read merges it. "I could
# not tell" must hold instead: this is the one script whose mistake — merging past
# an open rework — cannot be retried away.
#
# The failure is injected into the PR_NUMBER probe specifically, which is what
# distinguishes this case from (21)/PR#321: that one fails a DEPENDENCY probe. Since
# tk-lgjvg the holder set is the union of three reads, so each leg needs its own
# case — a guard restored on the dep probes alone would still merge this one.
has '^367$' "$TMP/merged" \
  && bad "(CHILDFAIL) an unreadable child lookup must HOLD, never merge (rework in flight cannot be ruled out)" \
  || ok "(CHILDFAIL) unreadable open-child lookup -> merge held"
# The referencing-bead read is now taken ONCE per anchor and feeds both the
# duplicate-anchor gate and the child hold, so an unreadable ledger is reported
# where it is read — naming both things it can no longer rule out — rather than
# later, from the holder probe alone. On STDERR, with the failed PR read and the
# failed anchor re-read: an unreadable ledger is a TOOL error, not a gate saying
# no, and the two streams are how an operator tells "the machine could not look"
# from "the machine looked and held" (cases 37/37b pin the same split).
hasin "$ERR1" "PR#367 referencing-bead read FAILED" \
  && ok "(CHILDFAIL) the hold reason names the failed lookup" \
  || bad "(CHILDFAIL) hold reason must name the failed lookup (got: $OUT1)"

# --- HEAD IDENTITY (review tk-pka2d finding #2). ------------------------------
# Every case here is a PR in OUR repository, OPEN, non-draft, CLEAN, based on main,
# with check.codex green at its live head — indistinguishable from a ready merge on
# every field the script checked before this fix. Only the HEAD differs.

# (HD1) FORK: the branch NAME matches, the branch does not. Pre-fix this squash-merged
# mallory/repo's head onto main under our anchor's gates.
has '^368$' "$TMP/merged" \
  && bad "(HD1) a PR opened from a FORK must never be merged under our anchor" \
  || ok "(HD1) fork head -> merge held"
hasin "$OUT1" "PR#368 is opened from FORK 'mallory/repo'" \
  && ok "(HD1) the hold names the fork and this checkout's repository" \
  || bad "(HD1) hold reason must name the fork (got: $OUT1)"
has '^bead-FORK$' "$TMP/closed" \
  && bad "(HD1) the fork's anchor must NOT be closed" \
  || ok "(HD1) no anchor closed on the fork PR"

# (HD2) SELFCONTRA: headRepository says ours, isCrossRepository says otherwise. An
# identity that contradicts itself has not been established — it is not a tie to
# break in the merge's favour.
has '^369$' "$TMP/merged" \
  && bad "(HD2) a self-contradicting head identity must never merge" \
  || ok "(HD2) headRepository/isCrossRepository disagreement -> merge held"
hasin "$OUT1" "PR#369 reports head repository 'acme/repo' (this checkout's own) and cross-repository='true'" \
  && ok "(HD2) the hold names both halves of the contradiction" \
  || bad "(HD2) hold reason must name the contradiction (got: $OUT1)"

# (HD3) NOHEAD: gh returns null head repository objects (deleted head repo, schema
# shift). "I cannot tell whether this is a fork" must hold, not merge.
has '^370$' "$TMP/merged" \
  && bad "(HD3) an unreadable head identity must HOLD, never merge" \
  || ok "(HD3) null headRepository/headRepositoryOwner -> merge held"
hasin "$OUT1" "PR#370 head identity is unreadable" \
  && ok "(HD3) the hold names the unreadable identity" \
  || bad "(HD3) hold reason must name the unreadable head (got: $OUT1)"

# (HD4) BRANCHMISMATCH: right repository, right head repository, WRONG branch. The
# anchor and the PR describe different work.
has '^371$' "$TMP/merged" \
  && bad "(HD4) a PR opened from a branch the anchor does not record must not merge" \
  || ok "(HD4) head branch != anchor's recorded branch -> merge held"
hasin "$OUT1" "anchor bead-BRANCHMISMATCH records branch 'polecat/bead-BRANCHMISMATCH' but PR#371 is opened from 'polecat/somebody-else'" \
  && ok "(HD4) the hold names both branches" \
  || bad "(HD4) hold reason must name both branches (got: $OUT1)"

# (HD5) HEADOK — THE POSITIVE CONTROL. Without it every assertion above could pass
# by the head checks rejecting everything, including legitimate merges.
has '^372$' "$TMP/merged" \
  && ok "(HD5) a fully-certified head (ours, non-cross, anchor's branch) still MERGES" \
  || bad "(HD5) the head checks must not block a legitimate merge"
has '^bead-HEADOK$' "$TMP/closed" \
  && ok "(HD5) the certified anchor closed (record)" || bad "(HD5) certified anchor closed"

# (XREPO-DEP) THE SCOPING GUARD for the two fixes' intersection. PR#373's only
# holder is reached by a `blocks` DEPENDENCY EDGE, and it carries BOTH excludable
# marks at once: merge_result=pull_request AND a pr_url naming another host's
# repository. That is the real shape of a cross-repository merge-ordering block —
# an operator saying "land the other repo's PR first" — and it must HOLD.
#
# Each exclusion deletes it if scoped to the whole holder set instead of to
# `_via == "pr_number"`, so this one case fails if EITHER scope regresses:
# merge_result (tk-je0rk) or repository identity (tk-9m8q4). Both exist only to
# undo the pr_number probe's over-broad sweep; neither says anything true about a
# bead found by an explicit edge in this ledger. Without this case the identity
# filter could be widened to the dep set and every suite above would still pass.
has '^373$' "$TMP/merged" \
  && bad "(XREPO-DEP) a dependency-edge blocker must hold regardless of merge_result AND of the repository its pr_url names" \
  || ok "(XREPO-DEP) cross-repository dep-edge blocker -> merge held"
hasin "$OUT1" "PR#373 has unclosed rework/review bead upstream-373 (open, merge_result=pull_request)" \
  && ok "(XREPO-DEP) the hold names the cross-repository blocker" \
  || bad "(XREPO-DEP) hold reason must name upstream-373 (got: $OUT1)"

# (INV) exactly eight PRs were merged, and the two fixes' merge sets are disjoint:
#   tk-lgjvg's — the fully-validated gated head (301), the no-gate PR (311), the
#     explicit opt-out (314), and the two whose only children cannot hold: wrong-end
#     edges (319) and an already-closed child (320);
#   this branch's — the two whose only blockers are FOREIGN beads (364, 365) and the
#     certified head (372).
# No held/skipped anchor leaked: not one of the dependency-edge holders, and not one
# of the four head-identity cases.
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "18" "(INV) exactly eighteen PRs merged (301 + 311 + 314 + unholdable children 319, 320 + approved 330, 333, 335, 343, 351, 359, 362 + cross-repo 364, 365 + head-certified 372 + terminal-re-read control 379 + fork-keyed 380, 381)"
# ...and all of them landed in THIS checkout's repository, not wherever gh pointed.
eq "$(cut -f2 "$TMP/mergedwhere" | sort -u | tr '\n' ' ')" "github.com/acme/repo " \
   "(INV) every merge landed in the origin-derived repository"

# Summary counters.
hasin "$OUT1" "18 merged" \
  && ok "run 1 summary reports 18 merged (identity view of the same run)" || bad "run 1 summary merged count (got: $OUT1)"

# --- Field-shape guard: only gh-supported --json fields. ----------------------
gh pr view 301 --json merged >/dev/null 2>&1 \
  && bad "(FS) gh stub must REJECT unsupported field 'merged'" \
  || ok "(FS) unsupported --json field 'merged' rejected (guards the field-shape bug)"
gh pr view 301 --json state,isDraft,baseRefName,headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository,mergeStateStatus,mergeable,url >/dev/null 2>&1 \
  && ok "(FS) the skill's validate --json field set is accepted" \
  || bad "(FS) the skill's --json field set must be accepted"
gh pr view 301 --json mergeCommit >/dev/null 2>&1 \
  && ok "(FS) the skill's record --json mergeCommit is accepted" \
  || bad "(FS) mergeCommit field must be accepted"

# --- Run 2: convergence. The merged+closed anchor leaves the gating set. -------
bash "$SCRIPT" >/dev/null
eq "$(grep -c '^301$' "$TMP/merged")" "1" "(5c) merged gated anchor not re-merged on second pass"
eq "$(grep -c '^311$' "$TMP/merged")" "1" "(5c) merged no-gate anchor not re-merged on second pass"
eq "$(grep -c '^319$' "$TMP/merged")" "1" "(5c) wrong-end-edge anchor not re-merged on second pass"

# --- PR IDENTITY: the full path, with gh's repository drifted after recovery. ---
# The state these runs model is the one check-set-heal.sh's phase 0 produces and
# then hands on: an anchor restored to visibility, carrying a PR NUMBER, now read
# and merged by THIS script in a process that never saw that certification.
reset_ids() {
  : > "$TMP/closed"; : > "$TMP/merged"; : > "$TMP/mergedrec"; : > "$TMP/closelog"
  : > "$TMP/mergedwhere"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/repofail"
  : > "$TMP/ghhost"
  # One ready pr_number-only anchor: nothing but the repository the read resolves
  # in decides which pull request "PR#301" means.
  cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex|green@HEAD301
A
}

# (ID1) DRIFT: gh's default repository is moved to a stranger's. The read and the
# merge are PINNED to the origin-derived repository, so the drift changes nothing —
# the right PR answers, and the merge lands in acme/repo.
reset_ids
echo 'stranger/repo' > "$TMP/ghdefault"
OUTID1="$(bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && ok "(ID1) gh default drifted to a stranger -> the pinned read still finds OUR PR#301 and merges it" \
  || bad "(ID1) pinned read must survive a moved gh default (got: $OUTID1)"
eq "$(cut -f2 "$TMP/mergedwhere" | sort -u)" "github.com/acme/repo" \
   "(ID1) the merge landed in the origin repository, not gh's default"
has '^bead-CLEAN$' "$TMP/closed" && ok "(ID1) the anchor is closed on the real merge" \
                                 || bad "(ID1) anchor closed"

# (ID2) IGNOREPIN: the same drift, against a gh that does NOT honour `--repo` — a
# redirect after a repository transfer or rename, an older gh, a wrapper. The
# foreign same-numbered PR comes back OPEN, non-draft, base main, CLEAN: every gate
# below the identity check passes on it. Pinning alone is no defence here; only
# COMPARING the returned URL against the expectation is, which is why the
# comparison is kept after the pin rather than trusted away as a tautology.
reset_ids
echo 'stranger/repo' > "$TMP/ghdefault"
: > "$TMP/ignorerepo"; echo 1 > "$TMP/ignorerepo"
OUTID2="$(bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && bad "(ID2) a foreign same-numbered PR must NEVER be merged (a wrong merge cannot be retried away)" \
  || ok "(ID2) gh ignores the pin -> the foreign PR is caught by the URL comparison, merge held"
has '^bead-CLEAN$' "$TMP/closed" \
  && bad "(ID2) no anchor may be closed off a stranger's pull request" \
  || ok "(ID2) no anchor closed on the foreign PR"
hasin "$OUTID2" "answered from 'github.com/stranger/repo', not this checkout's 'github.com/acme/repo'" \
  && ok "(ID2) the hold reason names the repository that answered" \
  || bad "(ID2) must name the foreign repository (got: $OUTID2)"

# (ID2b) HOSTDRIFT: GH_HOST points at another GitHub host. `<owner>/<repo>` does not
# name a repository — it names one per host — and `--repo` fills an omitted host from
# GH_HOST, so a HOSTLESS pin resolves to that host's acme/repo: same owner, same repo,
# same number, different pull request. The pin must therefore be host-qualified, and
# the comparison must keep the host, or this drift walks straight through both.
reset_ids
echo 'ghe.example.com' > "$TMP/ghhost"
OUTID2B="$(bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && ok "(ID2b) GH_HOST drifted -> the host-qualified pin still reads OUR PR#301" \
  || bad "(ID2b) a host-qualified pin must survive GH_HOST drift (got: $OUTID2B)"
eq "$(cut -f2 "$TMP/mergedwhere" | sort -u)" "github.com/acme/repo" \
   "(ID2b) the merge landed on THIS host's repository, not GH_HOST's"

# =============================================================================
# (ID6-ID8) THE REST-PATH HALF OF THE SAME QUESTION (review tk-5knqi finding #1)
# =============================================================================
# ID1/ID2/ID2b cover the PR READS, which `gh pr view --repo <host>/<owner>/<repo>`
# pins. But the approval gate does not decide from the PR read alone: it reads the
# REVIEW HISTORY and a COLLABORATOR PERMISSION through `gh api`, which takes no
# `--repo` — the repository lives in the REST path and the host in `--hostname`,
# and each half omitted falls back to gh's ambient context. Those two calls carried
# `repos/{owner}/{repo}/...`, unpinned in BOTH halves, so the evidence that
# authorizes a merge here could come from wherever gh happened to point. The three
# cases below are the three ways that goes wrong, and each one MERGES pre-fix.
#
# The foreign fixtures are deliberately plausible: an approving review from a
# real-looking account, a write-level collaborator row. Nothing about the ANSWER
# says it is about another repository — only where the question was asked does.

# (ID6) THE MISSED VETO. Our PR#301 carries a standing CHANGES_REQUESTED from an
# operator; the ambient repository's #301 does not. Read there, the veto simply
# does not exist, and the pass merges past a human's explicit block.
reset_ids
: > "$TMP/perms"; printf 'johnzook|write\n' > "$TMP/perms"
printf '301|7001|johnzook|CHANGES_REQUESTED|HEAD301|2026-01-01T00:00:00Z|1\n' > "$TMP/reviews"
: > "$TMP/reviews-foreign"          # the ambient repository's #301: no veto at all
echo 'stranger/repo' > "$TMP/ghdefault"
OUTID6="$(FAKE_REVIEWS_FOREIGN="$TMP/reviews-foreign" bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && bad "(ID6) a veto on OUR PR must hold the merge even when the ambient repository shows none" \
  || ok "(ID6) gh default drifted -> the reviews read is still ours, so the standing veto holds the merge"
hasin "$OUTID6" "PR#301 external reviewer 'johnzook' has a standing CHANGES_REQUESTED" \
  && ok "(ID6) the hold names the veto it found in OUR repository's history" \
  || bad "(ID6) must report the veto (got: $OUTID6)"

# (ID7) THE BORROWED APPROVAL. The anchor declares the `approval` gate, so a real
# external APPROVED review is required. Ours has none; the ambient repository's
# same-numbered PR has one, from an account with write access there. Read there,
# the requirement is satisfied by a review of a pull request this merge will never
# touch.
reset_ids
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex,approval|green@HEAD301
A
: > "$TMP/perms"                    # here: no collaborator rows at all
: > "$TMP/reviews"                  # here: nobody approved #301
# There: an approving review AND the write access that makes it trusted. Both
# halves of the evidence are borrowed, so an unpinned pass merges.
printf 'outsider|write\n' > "$TMP/perms-foreign"
printf '301|7002|outsider|APPROVED|HEAD301|2026-01-01T00:00:00Z|1\n' > "$TMP/reviews-foreign"
echo 'stranger/repo' > "$TMP/ghdefault"
OUTID7="$(FAKE_REVIEWS_FOREIGN="$TMP/reviews-foreign" FAKE_PERMS_FOREIGN="$TMP/perms-foreign" \
          bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && bad "(ID7) an approval that exists only in the ambient repository must NOT satisfy this merge's approval gate" \
  || ok "(ID7) gh default drifted -> the approval gate reads OUR history and holds, unapproved"
hasin "$OUTID7" "PR#301 no external approving review at the live head" \
  && ok "(ID7) the hold says OUR PR is unapproved, not that somebody else's is approved" \
  || bad "(ID7) must report the unapproved hold (got: $OUTID7)"

# (ID8) THE BORROWED PERMISSION. The approving review IS ours this time — the
# reviews read is pinned and finds it — but the approver holds write access only in
# the AMBIENT repository, and none here. The trusted-approver probe is a second,
# separate `gh api` call, so pinning the reviews read alone does not close this:
# "may this account write to the repository we are about to merge in" has to be
# asked OF that repository.
reset_ids
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex,approval|green@HEAD301
A
: > "$TMP/perms"                    # no collaborator row here — not a writer
printf 'outsider|write\n' > "$TMP/perms-foreign"
# The SAME approving review in both repositories, so the reviews read cannot be
# what decides this case: an unpinned pass and a pinned one both find the approval,
# and only the permission probe tells them apart. That isolates the second call —
# pinning the history alone would leave this hole open.
printf '301|7003|outsider|APPROVED|HEAD301|2026-01-01T00:00:00Z|1\n' > "$TMP/reviews"
cp "$TMP/reviews" "$TMP/reviews-foreign"
echo 'stranger/repo' > "$TMP/ghdefault"
OUTID8="$(FAKE_PERMS_FOREIGN="$TMP/perms-foreign" FAKE_REVIEWS_FOREIGN="$TMP/reviews-foreign" \
          bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && bad "(ID8) write access in ANOTHER repository must not make an approver trusted here" \
  || ok "(ID8) gh default drifted -> the permission probe asks OUR repository and the approval is untrusted"
hasin "$OUTID8" "no approver satisfies the trusted-approver policy" \
  && ok "(ID8) the hold names the trusted-approver policy" \
  || bad "(ID8) must report the untrusted approver (got: $OUTID8)"

# (ID9) NOT over-pinning: with gh's context UNDRIFTED, the very same fixtures merge.
# Otherwise ID6-ID8 could all be passing because the approval path is broken
# outright rather than because it is pinned.
reset_ids
cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex,approval|green@HEAD301
A
printf 'outsider|write\n' > "$TMP/perms"
printf '301|7004|outsider|APPROVED|HEAD301|2026-01-01T00:00:00Z|1\n' > "$TMP/reviews"
OUTID9="$(bash "$SCRIPT")"
has '^301$' "$TMP/merged" \
  && ok "(ID9) control: an approval in OUR repository, by a writer here, still merges" \
  || bad "(ID9) the pinned approval path must still merge a genuinely approved PR (got: $OUTID9)"

# =============================================================================
# (SYNC) THE DUPLICATED IDENTITY RESOLVER MUST NOT DRIFT
# =============================================================================
# `pr_nums_here` — which PR a bead names, under every key, restricted to this
# repository — exists in THREE places: this script, reconcile-merged-prs.sh, and
# the signoff template's pre-dismissal guard. They are duplicated on purpose (each
# script is standalone, and the third is instruction text a polecat executes, so
# there is nothing to source), and every one of those files says "keep them in
# step" in prose. Prose is not a mechanism: tk-5knqi finding #2 was precisely one
# of the three drifting to `pr_number` alone, which stranded fork-keyed anchors in
# the arm that was supposed to un-strand them, while the other two kept working.
#
# So the invariant is checked rather than asked for. Whitespace-normalized, because
# the template's copy is indented inside a jq program; everything else must match
# character for character.
extract_pnh() { # <file> -> the pr_nums_here definition, whitespace-normalized
  sed -n '/^ *def pr_nums_here(\$o):/,/unique;/p' "$1" \
    | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//'
}
PNH_MS=$(extract_pnh "$SCRIPT")
PNH_RC=$(extract_pnh "$(dirname "$SCRIPT")/reconcile-merged-prs.sh")
PNH_TM=$(extract_pnh "$(dirname "$SCRIPT")/../../template-fragments/polecat-non-impl-done.template.md")
[ -n "$PNH_MS" ] \
  && ok "(SYNC) pr_nums_here found in merge-skill.sh (the reference copy)" \
  || bad "(SYNC) pr_nums_here not found in $SCRIPT"
eq "$PNH_RC" "$PNH_MS" "(SYNC) reconcile-merged-prs.sh's copy is identical"
eq "$PNH_TM" "$PNH_MS" "(SYNC) the signoff template's copy is identical"
# ...and it really does read all three keys, so three identical copies of a
# NARROWED definition cannot pass this check quietly.
hasin "$PNH_MS" 'pr_number' && hasin "$PNH_MS" 'fork_pr' && hasin "$PNH_MS" 'fork_pr_url' \
  && ok "(SYNC) and the shared definition names all three PR keys" \
  || bad "(SYNC) pr_nums_here must read pr_number, fork_pr and fork_pr_url (got: $PNH_MS)"

# (ID4) REPOFAIL: this checkout's origin cannot be resolved at all. Every PR number
# would then be read — and merged — wherever gh happens to point, so the pass must
# merge NOTHING. Fail closed: a deferred merge costs one idle wake, a wrong merge
# cannot be retried away.
reset_ids
echo 1 > "$TMP/repofail"
bash "$SCRIPT" >/dev/null 2>"$TMP/errid4"
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "0" "(ID4) unresolvable origin -> nothing merged this pass"
eq "$(wc -l < "$TMP/closed" | tr -d ' ')" "0" "(ID4) unresolvable origin -> no anchor closed"
grep -q "cannot resolve this checkout's origin repository" "$TMP/errid4" \
  && ok "(ID4) the refusal is reported for an operator" \
  || bad "(ID4) must warn that the origin is unresolvable (err: $(cat "$TMP/errid4"))"

# --- (CL) the record half's close gate: identity-ENCODING override. -----------
# `bd close` is assignee-gated and compares the ASSIGNEE string to the ACTOR
# string. Those two routinely carry the SAME principal in two renderings —
# `<rig>/<pack>.<role>` ($GC_AGENT) vs `<rig>--<pack>__<role>` ($GC_SESSION_NAME)
# — so this script, which closes the anchor IT JUST MERGED, is refused on a bead
# it holds. That is the worst place to lose the close: the PR has LANDED and the
# ledger does not say so, and the observer then inherits an anchor it cannot close
# either (signal-loom PR#518: ~40 consecutive failing passes, forced by hand).
#
# Retry once with --force on THAT refusal only. Not a blanket --force: the same
# flag also overrides a genuinely foreign assignee and an open-children hold, and
# forcing past either would paper over exactly what the gate is for — those keep
# falling through to "close failed; observer records next pass", which is correct
# (the observer counts them and escalates).
reset_close_ms() {
  : > "$TMP/closed"; : > "$TMP/merged"; : > "$TMP/mergedrec"; : > "$TMP/closelog"
  : > "$TMP/mergedwhere"; : > "$TMP/ghdefault"; : > "$TMP/ignorerepo"; : > "$TMP/repofail"
  : > "$TMP/ghhost"; : > "$TMP/forced"; : > "$TMP/closerefuse"; : > "$TMP/closehard"
  cat > "$TMP/anchors" <<'A'
bead-CLEAN|301|main|codex|green@HEAD301
A
}

# (CL1) the encoding refusal: the PR merges, the close is refused, and the anchor
# still ends up CLOSED via the one-shot --force.
reset_close_ms
printf 'bead-CLEAN\tcannot close bead-CLEAN: assignee is "signal-loom/gc-toolkit.refinery", actor is "signal-loom--gc-toolkit__refinery"; reclaim or use --force to override\n' \
  > "$TMP/closerefuse"
OUTCL1="$(bash "$SCRIPT" 2>"$TMP/errcl1")"
has '^301$' "$TMP/merged" \
  && ok "(CL1) the merge itself is unaffected by the close gate" \
  || bad "(CL1) PR#301 must still merge (got: $OUTCL1)"
has '^bead-CLEAN$' "$TMP/closed" \
  && ok "(CL1) identity-ENCODING refusal -> the merged anchor still CLOSES" \
  || bad "(CL1) encoding-refused anchor must close via --force (got: $OUTCL1)"
has '^bead-CLEAN$' "$TMP/forced" \
  && ok "(CL1) ...and it closed via --force, not by the refusal silently passing" \
  || bad "(CL1) the close must have gone through --force"
has 'identity-ENCODING mismatch' "$TMP/errcl1" \
  && ok "(CL1) the retry is logged, so an override that fired is auditable" \
  || bad "(CL1) the --force retry must be logged (got: $(cat "$TMP/errcl1"))"
hasin "$OUTCL1" '1 identity-encoding forced closes' \
  && ok "(CL1) the summary line counts the forced close" \
  || bad "(CL1) summary must count forced closes (got: $OUTCL1)"
has '^bead-CLEAN$' "$TMP/mergedrec" \
  && ok "(CL1) merge_result=merged is still recorded after the forced close" \
  || bad "(CL1) the record half must complete after a forced close"

# (CL2) NOT a blanket --force. This refusal has the SAME message shape as (CL1)'s
# and names two DIFFERENT principals (polecat vs refinery) — matching the shape
# alone, or matching "the close failed", would force past a real ownership gate.
# The merge still happened, so the anchor is left for the observer, which is the
# existing documented behaviour for a failed close.
reset_close_ms
printf 'bead-CLEAN\tcannot close bead-CLEAN: assignee is "signal-loom/gc-toolkit.polecat", actor is "signal-loom--gc-toolkit__refinery"; reclaim or use --force to override\n' \
  > "$TMP/closehard"
OUTCL2="$(bash "$SCRIPT" 2>"$TMP/errcl2")"
has '^bead-CLEAN$' "$TMP/closed" \
  && bad "(CL2) a GENUINELY foreign assignee must never be forced past" \
  || ok "(CL2) foreign assignee -> NOT closed (the ownership gate still holds)"
has '^bead-CLEAN$' "$TMP/forced" \
  && bad "(CL2) --force must not be attempted on a foreign assignee" \
  || ok "(CL2) ...and --force was never even attempted for it"
has 'MERGED but close failed' "$TMP/errcl2" \
  && ok "(CL2) it falls through to the existing hand-off: the observer records it next pass" \
  || bad "(CL2) must report the failed close for the observer (got: $(cat "$TMP/errcl2"))"

# (CL3) an open-children hold — the OTHER refusal that suggests --force in its own
# text, and the one a message-keyword match would most easily swallow.
reset_close_ms
printf 'bead-CLEAN\tcannot close bead-CLEAN: 2 open child issue(s); close children first or use --force to override\n' \
  > "$TMP/closehard"
OUTCL3="$(bash "$SCRIPT" 2>/dev/null)"
has '^bead-CLEAN$' "$TMP/closed" \
  && bad "(CL3) an open-children hold must never be forced past" \
  || ok "(CL3) open-children refusal -> NOT closed"
has '^bead-CLEAN$' "$TMP/forced" \
  && bad "(CL3) --force must not be attempted on an open-children hold" \
  || ok "(CL3) ...and --force was never even attempted for it"

# (CL-CTL) positive control: with no refusal armed the same anchor closes cleanly
# and is NOT reported as forced. Without this, (CL2)/(CL3) could pass because the
# fixture never closed anything at all.
reset_close_ms
OUTCLC="$(bash "$SCRIPT" 2>/dev/null)"
has '^bead-CLEAN$' "$TMP/closed" \
  && ok "(CL-CTL) an unrefused close still closes normally" \
  || bad "(CL-CTL) control anchor must close (got: $OUTCLC)"
has '^bead-CLEAN$' "$TMP/forced" \
  && bad "(CL-CTL) an unrefused close must not report as forced" \
  || ok "(CL-CTL) ...and it is not counted as a forced close"
hasin "$OUTCLC" '0 identity-encoding forced closes' \
  && ok "(CL-CTL) ...and the summary says so" \
  || bad "(CL-CTL) summary must report zero forced closes (got: $OUTCLC)"

# =============================================================================
# (RQ) UNSTABLE is decided on the REQUIRED set, not on the composite (tk-zuoys).
# =============================================================================
# The bug: the terminal gate held on `mergeStateStatus != CLEAN`, which treats
# UNSTABLE (advisory checks red, nothing gating) exactly like BLOCKED (a required
# check or review genuinely gating). On a repository whose CI is red but whose
# checks are not REQUIRED, no PR can ever reach CLEAN — so refinery throughput
# for that rig is permanently zero, and the hold is this script's own, not
# GitHub's. Both live rigs are in exactly that shape: zero required status checks
# on main (gc-toolkit's main is governed by a ruleset that requires a REVIEW and
# no check; gascity's has no rules at all).
#
# The fix is not "merge unless BLOCKED" — that is the composite over again, and
# it would land a red REQUIRED check on any repository that grows one. UNSTABLE
# is resolved against the REQUIRED CONTEXTS for the base branch, evaluated at the
# validated head, with an unreadable protection API holding.
#
# Run against fully ISOLATED fixtures — its own anchors, PRs, ledger files — so
# the eighteen-merge invariant of the main run is untouched.
: > "$TMP/merged-rq"; : > "$TMP/closed-rq"
cat > "$TMP/prs-rq" <<'P'
401|OPEN|false|main|HEAD401|UNSTABLE|MERGEABLE|a401c0ffee000001
402|OPEN|false|guarded|HEAD402|UNSTABLE|MERGEABLE|a402c0ffee000002
403|OPEN|false|guarded|HEAD403|UNSTABLE|MERGEABLE|
404|OPEN|false|guarded|HEAD404|UNSTABLE|MERGEABLE|
405|OPEN|false|dark|HEAD405|UNSTABLE|MERGEABLE|
406|OPEN|false|main|HEAD406|BLOCKED|MERGEABLE|
407|OPEN|false|guarded|HEAD407|UNSTABLE|MERGEABLE|
408|OPEN|false|main|HEAD408|UNSTABLE|MERGEABLE|
409|OPEN|false|guarded|HEAD409|UNSTABLE|MERGEABLE|
P
cat > "$TMP/anchors-rq" <<'A'
bead-RQADVISORY|401|main|codex|green@HEAD401
bead-RQGREEN|402|guarded|codex|green@HEAD402
bead-RQRED|403|guarded|codex|green@HEAD403
bead-RQMISSING|404|guarded|codex|green@HEAD404
bead-RQDARK|405|dark|codex|green@HEAD405
bead-RQBLOCKED|406|main|codex|green@HEAD406
bead-RQPENDING|407|guarded|codex|green@HEAD407
bead-RQNOAPPROVAL|408|main|codex,approval|green@HEAD408
bead-RQROLLUPFAIL|409|guarded|codex|green@HEAD409
A
# `guarded` requires ci/build via a RULESET and ci/legacy via CLASSIC protection —
# both sources in one branch, so a fix that reads only one of them fails here.
# `main` is governed but requires no status check (the live-rig shape); `dark` is
# listed in $FAKE_PROTFAIL below and cannot be read at all.
cat > "$TMP/protection-rq" <<'PR'
guarded|ci/build|ci/legacy
main||
PR
# Advisory checks are red on EVERY PR here — that is what makes them UNSTABLE.
cat > "$TMP/rollup-rq" <<'R'
401|check|advisory-lint|FAILURE
401|check|advisory-e2e|FAILURE
402|check|ci/build|SUCCESS
402|status|ci/legacy|SUCCESS
402|check|advisory-lint|FAILURE
403|check|ci/build|FAILURE
403|status|ci/legacy|SUCCESS
404|check|ci/build|SUCCESS
404|check|advisory-lint|FAILURE
407|check|ci/build|
407|status|ci/legacy|SUCCESS
408|check|advisory-lint|FAILURE
409|check|ci/build|SUCCESS
409|status|ci/legacy|SUCCESS
R
OUT_RQ="$(FAKE_ANCHORS="$TMP/anchors-rq" FAKE_PRS="$TMP/prs-rq" \
          FAKE_PROTECTION="$TMP/protection-rq" FAKE_ROLLUP="$TMP/rollup-rq" \
          FAKE_PROTFAIL="dark" FAKE_ROLLUPFAIL="409" \
          FAKE_CLOSED="$TMP/closed-rq" FAKE_MERGED="$TMP/merged-rq" \
          FAKE_MERGEDREC="$TMP/mergedrec-rq" FAKE_CLOSELOG="$TMP/closelog-rq" \
          bash "$SCRIPT" 2>/dev/null)"

# (RQ1) THE FIX: red ADVISORY checks with ZERO required contexts -> MERGED. This
# is gascity PR#105, the PR a plain `gh pr merge --squash` took with no override.
has '^401$' "$TMP/merged-rq" \
  && ok "(RQ1) UNSTABLE + zero required contexts -> merged (advisory red gates nothing)" \
  || bad "(RQ1) advisory-red PR must merge (got: $OUT_RQ)"
hasin "$OUT_RQ" "PR#401 is UNSTABLE but base 'main' requires NO status checks" \
  && ok "(RQ1) ...and the decision names the required set it was made from" \
  || bad "(RQ1) the UNSTABLE decision must be legible (got: $OUT_RQ)"

# (RQ2) red ADVISORY beside GREEN REQUIRED checks -> MERGED, and both sources of
# required contexts are honoured: ci/build comes from the ruleset, ci/legacy from
# classic protection. A fix that read only one source would still merge this PR,
# so (RQ3) below is what actually pins the union.
has '^402$' "$TMP/merged-rq" \
  && ok "(RQ2) UNSTABLE + every required check green -> merged" \
  || bad "(RQ2) required-green PR must merge (got: $OUT_RQ)"
hasin "$OUT_RQ" "PR#402 is UNSTABLE but every REQUIRED status check on base 'guarded' is green" \
  && ok "(RQ2) ...and the log names the contexts that were evaluated" \
  || bad "(RQ2) the required-green decision must name the contexts (got: $OUT_RQ)"

# (RQ3) THE OTHER SIDE OF THE FIX — a red REQUIRED check still HOLDS. Without
# this the change would have removed a gate rather than repaired one.
has '^403$' "$TMP/merged-rq" \
  && bad "(RQ3) a red REQUIRED check must never merge" \
  || ok "(RQ3) UNSTABLE + red REQUIRED check -> merge held"
hasin "$OUT_RQ" "PR#403 is UNSTABLE and a REQUIRED status check is not green at head HEAD403: ci/build(RED)" \
  && ok "(RQ3) ...and the hold names WHICH required check was red" \
  || bad "(RQ3) the hold must name the failing required context (got: $OUT_RQ)"

# (RQ4) a required context with NO rollup entry at all is MISSING, never green.
# ci/legacy is required by classic protection and simply absent from 404's
# rollup — the shape a fix that unioned only the ruleset source would sail past.
has '^404$' "$TMP/merged-rq" \
  && bad "(RQ4) a required context absent from the rollup must not count as green" \
  || ok "(RQ4) UNSTABLE + required check MISSING from the rollup -> merge held"
hasin "$OUT_RQ" "PR#404 .*ci/legacy(MISSING)" \
  && ok "(RQ4) ...and the hold names it as MISSING, not as failing" \
  || bad "(RQ4) a missing required context must be reported as MISSING (got: $OUT_RQ)"

# (RQ5) FAIL CLOSED: protection that cannot be read holds. Unreadable is
# indistinguishable from "nothing required", and guessing merges a red required
# check — the one error here that cannot be retried away.
has '^405$' "$TMP/merged-rq" \
  && bad "(RQ5) unreadable protection must hold, not merge" \
  || ok "(RQ5) UNSTABLE + unreadable required set -> merge held (fail closed)"
hasin "$OUT_RQ" "PR#405 is UNSTABLE and the REQUIRED status-check set for base 'dark' could not be read" \
  && ok "(RQ5) ...and the hold says the protection read is what failed" \
  || bad "(RQ5) the unreadable-protection hold must say so (got: $OUT_RQ)"

# (RQ6) BLOCKED is untouched: something is genuinely gating (a required check, a
# required review), and it holds exactly as it always did.
has '^406$' "$TMP/merged-rq" \
  && bad "(RQ6) BLOCKED must still hold" \
  || ok "(RQ6) BLOCKED -> merge held (the composite still decides every other state)"
hasin "$OUT_RQ" "PR#406 not mergeable yet (mergeStateStatus='BLOCKED'" \
  && ok "(RQ6) ...and it holds through the generic composite arm" \
  || bad "(RQ6) BLOCKED must hold through the composite arm (got: $OUT_RQ)"

# (RQ7) a required check that has not REPORTED yet (a CheckRun with no conclusion)
# is not green either — pending required work must not be merged past.
has '^407$' "$TMP/merged-rq" \
  && bad "(RQ7) a pending required check must not merge" \
  || ok "(RQ7) UNSTABLE + required check still running -> merge held"

# (RQ8) the approval gate is INDEPENDENT of this change and still runs ahead of
# it: an approval-armed anchor with no approving review holds even though its red
# checks are purely advisory. The new arm must not become a way around it.
has '^408$' "$TMP/merged-rq" \
  && bad "(RQ8) an approval-armed anchor must not merge without an approval" \
  || ok "(RQ8) UNSTABLE + approval armed + no approving review -> merge held"
hasin "$OUT_RQ" "PR#408 no external approving review" \
  && ok "(RQ8) ...and it is the APPROVAL gate that holds it, not the required-set arm" \
  || bad "(RQ8) the approval hold must fire before the required-set arm (got: $OUT_RQ)"

# (RQ9) the rollup read is fail-closed too: required contexts exist but the head's
# check rollup cannot be read, so nothing can be shown green.
has '^409$' "$TMP/merged-rq" \
  && bad "(RQ9) an unreadable rollup must hold" \
  || ok "(RQ9) UNSTABLE + unreadable check rollup -> merge held (fail closed)"
hasin "$OUT_RQ" "PR#409 .*the head's check rollup is unreadable" \
  && ok "(RQ9) ...and the hold names the rollup read as the failure" \
  || bad "(RQ9) the unreadable-rollup hold must say so (got: $OUT_RQ)"

# (RQ-INV) exactly two of the nine merged: the two whose required set is
# established AND satisfied. A fix that relaxed the gate to "merge unless
# BLOCKED" would land 403, 404, 405, 407 and 409 as well.
eq "$(wc -l < "$TMP/merged-rq" | tr -d ' ')" "2" \
   "(RQ-INV) exactly two UNSTABLE PRs merged (401 advisory-only + 402 required-green)"

# (RQ-FS) statusCheckRollup must be a field gh actually supports — the same
# field-shape guard the approval gate's reads carry. An unknown field would empty
# the read and hold every UNSTABLE PR on a repository that does require checks.
gh pr view 401 --json statusCheckRollup >/dev/null 2>&1 \
  && ok "(RQ-FS) statusCheckRollup is an accepted gh field" \
  || bad "(RQ-FS) the required-check evaluation's --json field must be accepted"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
