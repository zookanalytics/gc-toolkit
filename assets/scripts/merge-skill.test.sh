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
#   (INV) `gh pr merge` is reached for EXACTLY the fully-validated PRs — no
#         other anchor is merged.
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

mkdir -p "$TMP/bin"

# Gating anchors (gc bd list source):
#   id|pr_number|merged_target|check_set|check.codex|merge_hold|pr_url|branch
# The 5th column is the anchor's per-gate marker value for check.codex; a
# "green@<oid>" value means "the codex gate passed at commit <oid>". bead-NOGATE
# has an empty check_set (declares no gates) and no marker. The 6th column is
# metadata.merge_hold (an operator gate); rows that omit it read as "" (no hold),
# so only bead-HOLD carries it. The 7th is metadata.pr_url — ABSENT on most rows on
# purpose: a pr_number-only anchor is exactly the shape check-set-heal.sh's recovery
# produces before it backfills the certified URL, so the pinned read is the only
# thing standing between these anchors and a foreign same-numbered PR.
#
# The 8th is metadata.branch, and it is absent on every legacy row for the same
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
bead-URLMISMATCH|330|main|codex|green@HEAD330||https://github.com/acme/OTHER/pull/330
bead-XDUPOK|331|main|codex|green@HEAD331
bead-XDUPFOREIGN|331|main|codex|green@HEAD331||https://otherhost/acme/repo/pull/331
bead-XCHILDFOREIGN|332|main|codex|green@HEAD332
bead-XCHILDSAME|333|main|codex|green@HEAD333
bead-XCHILDFAIL|334|main|codex|green@HEAD334
bead-DEPFOREIGN|340|main|codex|green@HEAD340
bead-FORK|335|main|codex|green@HEAD335|||polecat/bead-FORK
bead-SELFCONTRA|336|main|codex|green@HEAD336|||polecat/bead-SELFCONTRA
bead-NOHEAD|337|main|codex|green@HEAD337|||polecat/bead-NOHEAD
bead-BRANCHMISMATCH|338|main|codex|green@HEAD338|||polecat/bead-BRANCHMISMATCH
bead-HEADOK|339|main|codex|green@HEAD339|||polecat/bead-HEADOK
A

# PR states (gh pr view source):
#   pr|state|isDraft|baseRefName|headRefOid|mergeStateStatus|mergeable|mergeOid
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
#   335 OPEN, CLEAN, every gate green — but opened from FORK mallory/repo's branch
#       of the SAME NAME -> HELD (HD1). Pre-fix this squash-merged a stranger's head.
#   336 OPEN, CLEAN, head repository ours BUT isCrossRepository=true -> HELD (HD2)
#   337 OPEN, CLEAN, headRepository/headRepositoryOwner null -> HELD (HD3)
#   338 OPEN, CLEAN, ours, but opened from 'polecat/somebody-else' while the anchor
#       records 'polecat/bead-BRANCHMISMATCH' -> HELD (HD4)
#   339 OPEN, CLEAN, ours, head branch == the anchor's recorded branch -> MERGED (HD5)
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
330|OPEN|false|main|HEAD330|CLEAN|MERGEABLE|
331|OPEN|false|main|HEAD331|CLEAN|MERGEABLE|a331c0ffee111111
332|OPEN|false|main|HEAD332|CLEAN|MERGEABLE|a332c0ffee222222
333|OPEN|false|main|HEAD333|CLEAN|MERGEABLE|
334|OPEN|false|main|HEAD334|CLEAN|MERGEABLE|
335|OPEN|false|main|HEAD335|CLEAN|MERGEABLE|f335c0ffee000001|polecat/bead-FORK|mallory/repo|true
336|OPEN|false|main|HEAD336|CLEAN|MERGEABLE|f336c0ffee000002|polecat/bead-SELFCONTRA|acme/repo|true
337|OPEN|false|main|HEAD337|CLEAN|MERGEABLE|f337c0ffee000003|polecat/bead-NOHEAD|-|false
338|OPEN|false|main|HEAD338|CLEAN|MERGEABLE|f338c0ffee000004|polecat/somebody-else|acme/repo|false
339|OPEN|false|main|HEAD339|CLEAN|MERGEABLE|a339c0ffee000005|polecat/bead-HEADOK|acme/repo|false
340|OPEN|false|main|HEAD340|CLEAN|MERGEABLE|
P

# Rework/review children referencing a PR by their OWN pr_number metadata
# (gc bd list pr_number= source):
#   pr_number|child_id|merge_result|status     (empty status reads as `open`)
# PR 305 has an open rework child (no merge_result -> the skill must count it and
# HOLD). PR 310's real child sits PAST the former --limit cap behind 24
# jq-excluded decoys. PR 317's child is `blocked`, NOT open — the stub honours the
# requested --status list, so it is returned only because the skill now asks for
# every live status instead of open,in_progress.
# PR 326's child is the BOTH-SOURCE holder: it stamps pr_number (so this probe
# returns it, carrying merge_result=pull_request — the excludable shape) AND it is
# a parent-child dep of the anchor (so the dep probe returns it too). Provenance
# must UNION to "dep" and hold; demote it to "pr_number" and the merge_result
# exclusion deletes a live rework child.
cat > "$TMP/children" 
# The 5th column is the child's OWN pr_url, and it is what makes the child-hold
# guard an identity question rather than a number match. Omitted on rows that
# predate it ON PURPOSE: a child with no recorded URL cannot be placed in any
# repository, so it stays the `?` wildcard and holds exactly as it always did
# (case (6)/305 pins that legacy shape). child-foreign-332 names ANOTHER HOST's
# repository — somebody else's rework, which can never land ours — and must not
# hold; child-same-333 names this one and must.
cat > "$TMP/children" <<'C'
305|child-305|||
317|prblocked-317||blocked|
326|bothsrc-326|pull_request||
305|child-305|||
332|child-foreign-332|||https://otherhost/acme/repo/pull/332
333|child-same-333|||https://github.com/acme/repo/pull/333
C
for i in $(seq -w 1 24); do
  printf '310|decoy-%s|pull_request|\n' "$i" >> "$TMP/children"
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
bead-DEPFOREIGN|down|blocks|upstream-340|open|pull_request|https://otherhost/acme/repo/pull/999
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

# PR#334 has NO child at all: the only thing that can hold it is the guarded read
# refusing to answer, so a missing guard merges it and the case cannot pass by
# accident.
printf '334\terror-rc1\n' > "$TMP/childfail"

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
case "$1 $2" in
  "pr view")
    num="$3"; shift 3
    fields=""
    while [ $# -gt 0 ]; do case "$1" in --json) fields="$2"; shift 2 ;; *) shift ;; esac; done
    SUPPORTED=" number state mergedAt mergeCommit isDraft baseRefName headRefName headRefOid headRepository headRepositoryOwner isCrossRepository url title body author additions deletions mergeable mergeStateStatus "
    OIFS="$IFS"; IFS=','
    for f in $fields; do
      case "$SUPPORTED" in
        *" $f "*) : ;;
        *) IFS="$OIFS"; echo "Unknown JSON field: \"$f\"" >&2; exit 1 ;;
      esac
    done
    IFS="$OIFS"
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
    # Columns 9-11 are the head identity. Legacy rows omit them, so they default to
    # THIS repository's branch for this PR — the shape every pre-existing case was
    # written against — and only the head-identity rows vary them. A headrepo of `-`
    # emits NULL objects, which is what gh returns for a deleted head repository (an
    # omitted column cannot mean that: it has to keep meaning "ours").
    while IFS='|' read -r pr state isdraft base headoid mss mergeable oid headref headrepo cross; do
      [ "$pr" = "$num" ] || continue
      [ -n "$headref" ]  || headref="polecat/pr-$num"
      [ -n "$cross" ]    || cross="false"
      [ -n "$headrepo" ] || headrepo="acme/repo"
      jq -n --arg s "$state" --argjson d "$isdraft" --arg b "$base" \
            --arg h "$headoid" --arg m "$mss" --arg mg "$mergeable" --arg o "$oid" \
            --arg n "$num" --arg hr "$headref" --arg hrepo "$headrepo" \
            --argjson x "$cross" \
        '{state:$s, isDraft:$d, baseRefName:$b, headRefOid:$h, headRefName:$hr,
          headRepositoryOwner:(if $hrepo=="-" then null else {login:($hrepo | split("/")[0])} end),
          headRepository:(if $hrepo=="-" then null else {name:($hrepo | split("/")[1])} end),
          isCrossRepository:$x,
          mergeStateStatus:$m, mergeable:$mg, mergeCommit:(if $o=="" then null else {oid:$o} end), url:("https://github.com/acme/repo/pull/" + $n)}'
      exit 0
    done < "$FAKE_PRS"
    exit 0 ;;
  "pr merge")
    printf '%s\n' "$3" >> "$FAKE_MERGED"
    # WHERE the merge landed, not just which number: a merge performed in the
    # wrong repository is the failure these identity tests exist to catch.
    printf '%s\t%s\n' "$3" "$RESOLVED" >> "$FAKE_MERGEDWHERE" ;;
esac
exit 0
GH
chmod +x "$TMP/bin/gh"

# --- gc stub: bd list / bd dep list / bd close / bd update. ------------------
# Two list shapes: the gating-anchor scan (merge_result=pull_request, excluding
# already-closed anchors so convergence holds) and the referencing-bead scan
# (pr_number=N, honouring the requested --status list) that returns the anchor
# (which the skill EXCLUDES) plus any live rework/review children (which HOLD the
# merge). `bd dep list` serves the two dependency walks, each answering ONLY the
# direction+type it was asked for — a stub that ignored the flags could not tell
# a rework child from the epic parent or the downstream dependent.
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
  list)
    lim=$(printf '%s' "$*" | sed -n 's/.*--limit=\([0-9][0-9]*\).*/\1/p')
    case "$*" in
      *"merge_result=pull_request"*)
        out=""
        while IFS='|' read -r id pr target checkset checkcodex merge_hold prurl branch; do
          [ -n "$id" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","metadata":{"pr_number":"%s","pr_url":"%s","merged_target":"%s","check_set":"%s","check.codex":"%s","merge_hold":"%s","branch":"%s"}}' "$id" "$pr" "$prurl" "$target" "$checkset" "$checkcodex" "$merge_hold" "$branch")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        emit_rows "$out" "$lim" ;;
      *"pr_number="*)
        prnum=$(printf '%s' "$*" | sed -n 's/.*pr_number=\([0-9][0-9]*\).*/\1/p')
        # The status filter the caller asked for. A child whose status is not in
        # the list is invisible, exactly as the real `gc bd list --status` behaves.
        want=$(printf '%s' "$*" | sed -n 's/.*--status[= ]\([a-z_,]*\).*/\1/p')
        [ -n "$want" ] || want="open"
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
        while IFS='|' read -r id pr target checkset checkcodex merge_hold; do
          [ -n "$id" ] || continue
          [ "$pr" = "$prnum" ] || continue
          grep -qx "$id" "$FAKE_CLOSED" 2>/dev/null && continue
          obj=$(printf '{"id":"%s","status":"open","metadata":{"pr_number":"%s","merge_result":"pull_request"}}' "$id" "$pr")
          if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
        done < "$FAKE_ANCHORS"
        if [ -f "$FAKE_CHILDREN" ]; then
          while IFS='|' read -r cpr cid cmr cstatus cprurl; do
            [ -n "$cpr" ] || continue
            [ "$cpr" = "$prnum" ] || continue
            grep -qx "$cid" "$FAKE_CLOSED" 2>/dev/null && continue
            [ -n "$cstatus" ] || cstatus="open"
            printf '%s' ",$want," | grep -q ",$cstatus," || continue
            obj=$(printf '{"id":"%s","status":"%s","metadata":{"pr_number":"%s","merge_result":"%s","pr_url":"%s"}}' "$cid" "$cstatus" "$cpr" "$cmr" "$cprurl")
            if [ -z "$out" ]; then out="$obj"; else out="$out,$obj"; fi
          done < "$FAKE_CHILDREN"
        fi
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
    reason=""
    while [ $# -gt 0 ]; do case "$1" in --reason) reason="$2"; shift 2 ;; *) shift ;; esac; done
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

export PATH="$TMP/bin:$PATH"
export FAKE_ANCHORS="$TMP/anchors" FAKE_PRS="$TMP/prs" FAKE_CHILDREN="$TMP/children" \
       FAKE_DEPS="$TMP/deps" FAKE_DEPFAIL="$TMP/depfail" FAKE_DEPRAW="$TMP/depraw" \
       FAKE_CLOSED="$TMP/closed" FAKE_MERGED="$TMP/merged" \
       FAKE_MERGEDREC="$TMP/mergedrec" FAKE_CLOSELOG="$TMP/closelog" \
       FAKE_MERGEDWHERE="$TMP/mergedwhere" FAKE_GH_DEFAULT="$TMP/ghdefault" \
       FAKE_IGNORE_REPO="$TMP/ignorerepo" FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_GH_HOST="$TMP/ghhost" FAKE_CHILD_FAIL="$TMP/childfail"

# --- Run 1: validate -> merge -> record for the one ready PR, hold the rest. --
OUT1="$(bash "$SCRIPT")"

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
# would have merged pre-fix. 315-318 and 321 are the tk-lgjvg child-resolution
# cases: every one is CLEAN with its codex gate green at the live head, so the
# ONLY thing standing between them and a merge is the child gate.
for n in 302 303 304 305 306 307 308 309 310 312 313 315 316 317 318 321 322 323 324 325 326; do
  has "^$n$" "$TMP/merged" && bad "($n) anchor must NOT be merged" \
                          || ok "($n) anchor not merged"
done

# Hold reasons name the specific gate that blocked each PR.
#
# These assert with `grep -q PATTERN <<< "$OUT1"`, NOT `printf … | grep -q …`.
# Do not "tidy" them back into a pipe. Under this file's `set -o pipefail`, the
# piped form reports a FALSE FAILURE on a string that is genuinely present:
# `grep -q` exits 0 the instant it matches, closing the pipe while `printf` is
# still writing, so printf dies of SIGPIPE (141) and pipefail promotes that to
# the pipeline's status — the `&&`/`||` then takes the `bad` branch even though
# the match succeeded. It is a RACE on how much printf flushed before grep quit,
# so it hides while the payload is small and widens as the payload grows.
#
# Measured on this suite's real $OUT1 (2552 B): the piped form produced 14 false
# failures in 3000 tries (~0.5%), the here-string form 0 in 3000. At 18 piped
# assertions per run that is roughly a 1-in-12 chance of a spurious FAIL per
# execution — which is exactly the "ANOMALY" recorded in tk-lgjvg's notes: a lone
# "(14) blocked dep-linked child must hold" failure whose own diagnostic dump
# CONTAINED the asserted substring, written off as unreproducible after 16 clean
# reruns. It was never a flaky assertion; it was this. (Anchors 322/323 lengthen
# $OUT1 slightly and so nudge the odds up, but the defect predates them.)
#
# A here-string is not a pipeline, so there is no SIGPIPE and no pipefail
# interaction. The same pattern is still live in ~10 other pack test files and in
# reconcile-graduated-convoys.sh:209 (shipped, where it can silently skip a
# convoy) — tracked as tk-zfjg9, deliberately not swept here.
grep -q "PR#302 check 'codex' not green at live head" <<< "$OUT1" \
  && ok "(2) stale check.codex (green@old-head) -> held, reason names the gate" \
  || bad "(2) stale check hold reason (got: $OUT1)"
grep -q "PR#303 check 'codex' not green at live head" <<< "$OUT1" \
  && ok "(3) missing check.codex (codex in check_set) -> held" || bad "(3) missing check hold (got: $OUT1)"
grep -q "PR#304 not mergeable yet (mergeStateStatus='BLOCKED'" <<< "$OUT1" \
  && ok "(4) BLOCKED -> held, reason names mergeStateStatus" || bad "(4) BLOCKED hold (got: $OUT1)"
grep -q "PR#309 not mergeable yet (mergeStateStatus='BEHIND'" <<< "$OUT1" \
  && ok "(5) BEHIND -> held" || bad "(5) BEHIND hold (got: $OUT1)"
grep -q "PR#305 has unclosed rework/review bead child-305 (open)" <<< "$OUT1" \
  && ok "(6) open rework child -> held, reason names the child" || bad "(6) child hold (got: $OUT1)"
grep -q "PR#306 base 'integration/foo' != target 'main' (retargeted)" <<< "$OUT1" \
  && ok "(7) retargeted -> held, reason names the base mismatch" || bad "(7) retarget hold (got: $OUT1)"
grep -q "PR#310 has unclosed rework/review bead child-310 (open)" <<< "$OUT1" \
  && ok "(10) open child past former cap -> held (unbounded scan found it)" \
  || bad "(10) past-cap child hold (got: $OUT1)"
grep -q "PR#312 merge_hold set (operator gate)" <<< "$OUT1" \
  && ok "(11) merge_hold=true -> held, reason names the operator gate" \
  || bad "(11) merge_hold hold reason (got: $OUT1)"
grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPGATED)" <<< "$OUT1" \
  && ok "(12) multi-anchor PR -> gated anchor held with the one-anchor-per-PR reason" \
  || bad "(12) multi-anchor gated-anchor hold (got: $OUT1)"
grep -q "PR#313 has multiple open gating anchors (one-anchor-per-PR violated); merge held (anchor bead-DUPFREE)" <<< "$OUT1" \
  && ok "(12) multi-anchor PR -> gateless duplicate ALSO held (pre-fix it merged, bypassing codex)" \
  || bad "(12) multi-anchor gateless-duplicate hold (got: $OUT1)"

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
# probes and carries merge_result=pull_request — the exact shape the pr_number
# exclusion drops. Dedup must UNION provenance (group_by) so the dep sighting
# wins and the holder survives; a unique_by(.id) that kept the first-sorted copy
# would class it pr_number, apply the exclusion, and merge past a live child.
grep -q "PR#326 has unclosed rework/review bead bothsrc-326 (open, merge_result=pull_request)" <<< "$OUT1" \
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

# (ID3) the anchor's own certified pr_url names a DIFFERENT pull request from the
# one that answered. Everything else about PR#330 is merge-ready (OPEN, non-draft,
# base==target, codex green@head, CLEAN), so the identity check is the only thing
# that can stop it — and it must, because one of the two names is wrong and nothing
# here can say which.
has '^330$' "$TMP/merged" && bad "(ID3) an anchor whose pr_url names another PR must NOT be merged" \
                          || ok "(ID3) pr_url/live-URL mismatch -> merge held"
printf '%s\n' "$OUT1" | grep -q "anchor bead-URLMISMATCH records pr_url 'https://github.com/acme/OTHER/pull/330'" \
  && ok "(ID3) the hold reason names both pull requests for an operator" \
  || bad "(ID3) hold reason must name the recorded pr_url (got: $OUT1)"

# (XREPO) BOTH hold guards are keyed on REPOSITORY + number, not the bare number.
# Each fails toward holding, so the bug they had was not a wrong merge — it was an
# indefinite hold on a ready PR that no repair in THIS repository could release
# (review tk-thvbq finding #4).
#
# (XREPO-DUP) PR#331 is claimed by our bead-XDUPOK (pr_number-only, so it keys on
# origin) and by bead-XDUPFOREIGN, whose pr_url names ANOTHER HOST's acme/repo.
# Keyed on "331" alone that is a one-anchor-per-PR violation and BOTH are held
# forever; keyed on repository+number the foreign anchor is a different pull
# request and ours merges.
has '^331$' "$TMP/merged" \
  && ok "(XREPO-DUP) a foreign same-numbered anchor is not a duplicate -> our PR#331 still merges" \
  || bad "(XREPO-DUP) PR#331 must merge; a foreign anchor must not make it multi-anchor (got: $OUT1)"
printf '%s\n' "$OUT1" | grep -q "PR#331 has multiple open gating anchors" \
  && bad "(XREPO-DUP) must NOT report a one-anchor-per-PR violation across repositories" \
  || ok "(XREPO-DUP) no false one-anchor-per-PR hold across repositories"
# ...and the foreign anchor is still refused, by the identity check that owns that
# job — the dup guard getting out of its way must not let it merge.
has '^bead-XDUPFOREIGN$' "$TMP/closed" \
  && bad "(XREPO-DUP) the foreign anchor must never be closed off our PR" \
  || ok "(XREPO-DUP) the foreign anchor is still refused by the pr_url identity check"
# The SAME-repository duplicate must still be held: the qualification only rules out
# a positive disagreement, it does not weaken the guard where it applies (313).
printf '%s\n' "$OUT1" | grep -q "PR#313 has multiple open gating anchors" \
  && ok "(XREPO-DUP) a same-repository duplicate is still held (guard not weakened)" \
  || bad "(XREPO-DUP) same-repository duplicates must still hold"

# (XREPO-CHILD) PR#332's only open child names another host's repository — it is
# somebody else's rework and can never land ours, so it must not hold. PR#333's
# child names THIS repository and must. The unqualified guard held both.
has '^332$' "$TMP/merged" \
  && ok "(XREPO-CHILD) a foreign same-numbered child does not hold -> PR#332 merges" \
  || bad "(XREPO-CHILD) PR#332 must merge; a foreign child cannot hold it (got: $OUT1)"
has '^333$' "$TMP/merged" \
  && bad "(XREPO-CHILD) a same-repository open child MUST still hold PR#333" \
  || ok "(XREPO-CHILD) a same-repository open child still holds the merge"
printf '%s\n' "$OUT1" | grep -q "PR#333 has unclosed rework/review bead child-same-333 (open)" \
  && ok "(XREPO-CHILD) the hold names the same-repository child" \
  || bad "(XREPO-CHILD) hold reason must name child-same-333 (got: $OUT1)"

# (CHILDFAIL) the child lookup FAILED (error object + exit 1). PR#334 has no child
# at all and is otherwise fully mergeable, so an unguarded read merges it. "I could
# not tell" must hold instead: this is the one script whose mistake — merging past
# an open rework — cannot be retried away.
#
# The failure is injected into the PR_NUMBER probe specifically, which is what
# distinguishes this case from (21)/PR#321: that one fails a DEPENDENCY probe. Since
# tk-lgjvg the holder set is the union of three reads, so each leg needs its own
# case — a guard restored on the dep probes alone would still merge this one.
has '^334$' "$TMP/merged" \
  && bad "(CHILDFAIL) an unreadable child lookup must HOLD, never merge (rework in flight cannot be ruled out)" \
  || ok "(CHILDFAIL) unreadable open-child lookup -> merge held"
printf '%s\n' "$OUT1" | grep -q "PR#334 in-flight rework/review probe failed" \
  && ok "(CHILDFAIL) the hold reason names the failed lookup" \
  || bad "(CHILDFAIL) hold reason must name the failed lookup (got: $OUT1)"

# --- HEAD IDENTITY (review tk-pka2d finding #2). ------------------------------
# Every case here is a PR in OUR repository, OPEN, non-draft, CLEAN, based on main,
# with check.codex green at its live head — indistinguishable from a ready merge on
# every field the script checked before this fix. Only the HEAD differs.

# (HD1) FORK: the branch NAME matches, the branch does not. Pre-fix this squash-merged
# mallory/repo's head onto main under our anchor's gates.
has '^335$' "$TMP/merged" \
  && bad "(HD1) a PR opened from a FORK must never be merged under our anchor" \
  || ok "(HD1) fork head -> merge held"
printf '%s\n' "$OUT1" | grep -q "PR#335 is opened from FORK 'mallory/repo'" \
  && ok "(HD1) the hold names the fork and this checkout's repository" \
  || bad "(HD1) hold reason must name the fork (got: $OUT1)"
has '^bead-FORK$' "$TMP/closed" \
  && bad "(HD1) the fork's anchor must NOT be closed" \
  || ok "(HD1) no anchor closed on the fork PR"

# (HD2) SELFCONTRA: headRepository says ours, isCrossRepository says otherwise. An
# identity that contradicts itself has not been established — it is not a tie to
# break in the merge's favour.
has '^336$' "$TMP/merged" \
  && bad "(HD2) a self-contradicting head identity must never merge" \
  || ok "(HD2) headRepository/isCrossRepository disagreement -> merge held"
printf '%s\n' "$OUT1" | grep -q "PR#336 reports head repository 'acme/repo' (this checkout's own) and cross-repository='true'" \
  && ok "(HD2) the hold names both halves of the contradiction" \
  || bad "(HD2) hold reason must name the contradiction (got: $OUT1)"

# (HD3) NOHEAD: gh returns null head repository objects (deleted head repo, schema
# shift). "I cannot tell whether this is a fork" must hold, not merge.
has '^337$' "$TMP/merged" \
  && bad "(HD3) an unreadable head identity must HOLD, never merge" \
  || ok "(HD3) null headRepository/headRepositoryOwner -> merge held"
printf '%s\n' "$OUT1" | grep -q "PR#337 head identity is unreadable" \
  && ok "(HD3) the hold names the unreadable identity" \
  || bad "(HD3) hold reason must name the unreadable head (got: $OUT1)"

# (HD4) BRANCHMISMATCH: right repository, right head repository, WRONG branch. The
# anchor and the PR describe different work.
has '^338$' "$TMP/merged" \
  && bad "(HD4) a PR opened from a branch the anchor does not record must not merge" \
  || ok "(HD4) head branch != anchor's recorded branch -> merge held"
printf '%s\n' "$OUT1" | grep -q "anchor bead-BRANCHMISMATCH records branch 'polecat/bead-BRANCHMISMATCH' but PR#338 is opened from 'polecat/somebody-else'" \
  && ok "(HD4) the hold names both branches" \
  || bad "(HD4) hold reason must name both branches (got: $OUT1)"

# (HD5) HEADOK — THE POSITIVE CONTROL. Without it every assertion above could pass
# by the head checks rejecting everything, including legitimate merges.
has '^339$' "$TMP/merged" \
  && ok "(HD5) a fully-certified head (ours, non-cross, anchor's branch) still MERGES" \
  || bad "(HD5) the head checks must not block a legitimate merge"
has '^bead-HEADOK$' "$TMP/closed" \
  && ok "(HD5) the certified anchor closed (record)" || bad "(HD5) certified anchor closed"

# (XREPO-DEP) THE SCOPING GUARD for the two fixes' intersection. PR#340's only
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
has '^340$' "$TMP/merged" \
  && bad "(XREPO-DEP) a dependency-edge blocker must hold regardless of merge_result AND of the repository its pr_url names" \
  || ok "(XREPO-DEP) cross-repository dep-edge blocker -> merge held"
printf '%s\n' "$OUT1" | grep -q "PR#340 has unclosed rework/review bead upstream-340 (open, merge_result=pull_request)" \
  && ok "(XREPO-DEP) the hold names the cross-repository blocker" \
  || bad "(XREPO-DEP) hold reason must name upstream-340 (got: $OUT1)"

# (INV) exactly eight PRs were merged, and the two fixes' merge sets are disjoint:
#   tk-lgjvg's — the fully-validated gated head (301), the no-gate PR (311), the
#     explicit opt-out (314), and the two whose only children cannot hold: wrong-end
#     edges (319) and an already-closed child (320);
#   this branch's — the two whose only blockers are FOREIGN beads (331, 332) and the
#     certified head (339).
# No held/skipped anchor leaked: not one of the dependency-edge holders, and not one
# of the four head-identity cases.
eq "$(wc -l < "$TMP/merged" | tr -d ' ')" "8" "(INV) exactly eight PRs merged (301 + 311 + 314 + dep-edge 319, 320 + cross-repo 331, 332 + head-certified 339)"
# ...and all of them landed in THIS checkout's repository, not wherever gh pointed.
eq "$(cut -f2 "$TMP/mergedwhere" | sort -u | tr '\n' ' ')" "github.com/acme/repo " \
   "(INV) every merge landed in the origin-derived repository"

# Summary counters.
printf '%s\n' "$OUT1" | grep -q "8 merged" \
  && ok "run 1 summary reports 8 merged" || bad "run 1 summary merged count (got: $OUT1)"

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
printf '%s\n' "$OUTID2" | grep -q "answered from 'github.com/stranger/repo', not this checkout's 'github.com/acme/repo'" \
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

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
