#!/usr/bin/env bash
# Hermetic test for check-set-heal.sh PHASE 0 — merge_result recovery (tk-wsxd0).
# Stubs `gc` (bead ledger) and `gh` (PR state) on PATH. No live city, Dolt, network,
# or real pull requests. Phase 1 (check_set normalization) is covered by the sibling
# check-set-heal.test.sh; this file covers only the visibility repair beneath it.
#
# THE BUG. Every refinery pass — this heal, merge-skill.sh, pre-open-resolve.sh and
# the observer — enumerates gating anchors on the `merge_result` metadata field. An
# anchor missing `merge_result` ENTIRELY is therefore invisible to ALL of them at
# once: not un-healed, but unseeable. shutupandlisten's hand-recovered su-uzy9.1
# carried `branch` + `pr_url` and no `merge_result`; the rig-wide gating set read
# EMPTY and PR#37 sat open 6 days with zero escalations. Phase 0 enumerates on a
# predicate that survives the damage (`pr_url`/`pr_number` present, `merge_result`
# absent) and restores the field.
#
# Covered:
#   (RECOVER)  pr_url + branch, no merge_result -> merge_result=pull_request stamped,
#              pr_number + merged_target backfilled from the live PR, AND phase 1
#              gates it in the SAME pass (stamp check_set + dispatch the signoff).
#   (PRNUMONLY) the pr_number-only shape (no pr_url) is a POSITIVE anchor, not just
#              the negative b-ROUTED case: recovered, with nothing re-backfilled.
#   (CSNORMAL) merge_result missing but check_set ALREADY 'codex' and no marker ->
#              recovered AND a signoff dispatched. The damage that dropped
#              merge_result need not have dropped check_set, so such an anchor reads
#              "already normalized"; skipping it strands the merge on a check.codex
#              nothing exists to stamp (review tk-ej3wq finding #1).
#   (ROUTED)   a rework child (gc.routed_to set) -> NEVER stamped. Stamping it would
#              cancel the in-flight-rework hold merge-skill.sh derives from its empty
#              merge_result and land a PR mid-rework.
#   (ANCHORB)  anchor_bead set (a review/rework child) -> NEVER stamped.
#   (TASKKIND) task_kind=review -> NEVER stamped.
#   (SRCREV)   source_review_bead set -> NEVER stamped.
#   (SRCANCH)  source_anchor_bead set (reconcile-merged-prs.sh's stale-base rebase
#              child) with routing CLEARED -> NEVER stamped (review tk-ej3wq #3).
#   (NOBRANCH) a PR-referencing bead with no branch (a plain review bead) -> skipped.
#   (POLECAT)  assigned to a polecat, not the refinery -> skipped (live WIP).
#   (ONEANCH)  the PR is already claimed by another open merge_result-carrying bead
#              -> skipped (one-anchor-per-PR, tk-ynz4b).
#   (INCFAIL)  the incumbent-anchor lookup FAILS -> skipped, not promoted. An
#              unreadable ledger must not read as "no incumbent" (review tk-ej3wq
#              testing gap).
#   (AMBIG)    two candidates naming the SAME PR -> NEITHER stamped (fail closed).
#   (DUPCROSSREPO) ...but "the SAME PR" is REPOSITORY + number, not the bare number. A
#              damaged candidate for another repository's #745 must not make this repo's
#              #745 ambiguous — this guard runs before the repository-aware incumbent
#              checks, so keyed on the number alone it blocks the real recovery forever
#              (review tk-jza6h finding #1).
#   (INFLIGHTID) the in-flight dedup must VALIDATE the match it stops on: a foreign
#              same-numbered bead, one naming ANOTHER anchor, and an unattributable
#              review (lost `anchor_bead`) are not this anchor's signoff, and stopping on
#              one holds the merge forever — while a live same-repo rival, and one whose
#              repository cannot be named, still hold (review tk-jza6h finding #2).
#   (NONUM)    pr_url with no resolvable number -> skipped + warned.
#   (GHFAIL)   `gh pr view` fails -> not stamped (the PR is unconfirmed), warned.
#   (MERGED)   the PR already merged -> merge_result restored for the observer to
#              close, but NO gate armed and NO signoff dispatched.
#   (INERT2)   ...and that skip SURVIVES the pass: a later pass reads the persisted
#              merge_result_pr_state, re-checks it live, and still arms nothing
#              (review tk-ej3wq finding #4).
#   (REOPEN)   a recovered anchor whose CLOSED PR was REOPENED is gated normally —
#              the persisted state is re-checked, never blindly trusted.
#   (REOPENWRONG) ...but that re-check must RE-CERTIFY the PR, not just name it by
#              number: an OPEN PR of the same number in ANOTHER REPOSITORY must not
#              refresh the record to OPEN and drop the anchor into gating. Phase 0
#              certified the PR by URL/repo/head; the re-check runs on every LATER pass,
#              where gh's repository context is not guaranteed to be the same one
#              (review tk-r11wt finding #1).
#   (REOPENNOURL) the same, on an anchor carrying pr_number but NO pr_url — the shape
#              phase 0 itself produces, since pr_number is a field it BACKFILLS. With
#              no recorded URL the URL comparison is skipped, so the certified ORIGIN
#              REPOSITORY is the only guard left and must hold on its own.
#   (REOPENFORK) the same re-check, on the other identity half: the same number in the
#              right repo, opened from a branch of the bead's NAME but in a FORK ->
#              still not this bead's PR, so nothing is refreshed or gated.
#   (TGTONLY)  merged_target ABSENT + target recorded -> backfill takes the recorded
#              target, not the PR's live base.
#   (MTEMPTY)  merged_target PRESENT BUT EMPTY + target recorded -> same. jq `//`
#              does not treat "" as absent, so an empty merged_target used to shadow
#              the recorded target and bless a retarget (review tk-ej3wq finding #5).
#   (NONCANON) a non-canonical refinery assignee is FLAGGED (not rewritten).
#   (STAMPFAIL) a merge_result stamp that does not persist is not counted, is
#              flagged once, and the pass still exits 0 — NOT the UNSAFE_RC that an
#              ungated check_set uses, because an invisible anchor cannot be merged.
#   (URLMISMATCH) the bead's pr_url names ANOTHER repo's same-numbered PR -> refused.
#              `gh pr view <n>` resolves the number in the CURRENT repo, so a number
#              alone would bind the anchor to a stranger's PR and merge it
#              (review tk-lgpyg finding #2).
#   (HEADMISMATCH) the PR is opened from a branch that is not the bead's -> refused.
#   (FORKHEAD) the PR is opened from a branch of the bead's NAME but in a FORK ->
#              refused. A branch name is owned by nobody, so headRefName alone is
#              satisfied by any fork that reuses it; the post-open validation in
#              mol-refinery-patrol already checks the head REPOSITORY and the recovery
#              owes the same check (review tk-h1ymf finding #1).
#   (PARTIALID) `gh` answers with a readable object but a BLANK identity field ->
#              refused + warned. The fail-closed branch that makes a partial or
#              schema-shifted CLI response safe (review tk-h1ymf testing gap).
#   (REPOFAIL) this checkout's own origin repository cannot be resolved -> refused.
#              With nothing to compare against, "the repo matches" would only mean
#              "the repo was never checked" (review tk-h1ymf finding #1).
#   (WRONGDEFAULT) gh's CURRENT repository is not this checkout's — `gh repo
#              set-default`, GH_REPO or a different cwd all move it. Three arms: a
#              pr_number-only recovery (nothing but the repository check left to catch
#              it) and the persisted-non-OPEN reopen re-check must both refuse the
#              foreign same-numbered PR; and, as the positive control, a PR that DOES
#              exist in origin's repo still recovers, read from THAT repo. Deriving the
#              expected repo from gh and the PR from gh takes both halves of the
#              identity from one movable source, so they agree on a stranger's pull
#              request; the expectation comes from `git remote get-url origin` and pins
#              the read with `--repo` (review tk-5nxyg finding #1).
#   (CROSSREPOINC) an open anchor for ANOTHER repository's PR of the same number must
#              not block recovery — pull numbers are unique only within a repository,
#              and a number-keyed incumbent guard refuses a real repair before identity
#              certification ever runs. The same-repo incumbent still blocks
#              (review tk-5nxyg finding #2). BOTH incumbent surfaces are keyed that
#              way: the pr_url scan AND the `--metadata-field pr_number=<n>` lookup that
#              runs before it, which stayed number-only and so still refused a repair
#              whenever the foreign incumbent also carried a pr_number. An incumbent
#              with NO pr_url cannot be placed in a repository and still blocks
#              (review tk-47bij finding #2).
#   (GHHOST)   `<owner>/<repo>` names one repository PER HOST. `gh pr view --repo` takes
#              `[HOST/]OWNER/REPO` and fills the host from GH_HOST when omitted, so a
#              hostless `--repo o/r` under a foreign GH_HOST reads THAT host's `o/r` and
#              returns a PR indistinguishable from ours on owner/repo and head repo
#              alike. Three arms: the foreign host must not certify (pr_number-only, so
#              only the repository check is left); origin's own PR still recovers and is
#              read from origin's host; and a gh that IGNORES `--repo` is caught by the
#              host-qualified URL comparison — pinning the read and comparing the answer
#              are two halves of one check (review tk-47bij finding #1).
#   (UNREACHED) the gating enumeration drops THIS anchor while returning others. Reach
#              is VERIFIED, not inferred from a non-empty check_set: an anchor recovered
#              with check_set already `codex` passes a gatedness-only sweep in silence
#              while no signoff was ever dispatched. Gated-but-unreached is reported and
#              held on its own gate; unreached AND ungated is the ungated-merge
#              condition and exits UNSAFE_RC (review tk-47bij finding #3).
#   (PAGE)     ...and the enumeration itself is unbounded. 200 already-normalized
#              anchors ahead of a recovered one used to put it past the phase-1 cap:
#              visible to merge-skill, gate armed, no signoff, no warning, pass exits 0
#              (review tk-47bij finding #3).
#   (DROPROUTE) the dispatch's LAST write — gc.routed_to, the field that makes a review
#              claimable — is lost. Pass 1 must NOT count it as dispatched; pass 2 must
#              RE-ROUTE the stranded review rather than reading it as in-flight forever
#              (which strands it permanently: armed gate, unclaimable review, held
#              merge, no escalation) and must not mint a twin
#              (review tk-5nxyg finding #3).
#   (URLINC)   the PR is already anchored by an open bead carrying merge_result and
#              pr_url but NO pr_number -> the candidate is refused. pr_number is a
#              field phase 0 BACKFILLS, so an incumbent can be missing it; a
#              number-keyed incumbent lookup cannot see one and would mint a second
#              anchor for a live PR (review tk-h1ymf finding #2).
#   (INCURLFAIL) that pr_url incumbent scan is unreadable -> refused, not promoted.
#              Same fail-closed rule as INCFAIL, on the other identity surface.
#   (URLSUFFIX) a pr_url with a sub-path (/files) is the SAME PR -> still recovered;
#              the identity check must not invent mismatches from cosmetics.
#   (PARTIAL)  a DEPENDENT of visibility (pr_number/merged_target) does not stick ->
#              merge_result is NOT flipped: the bead stays invisible and retried,
#              never visible-with-a-missing-protection. merge-skill's retarget guard
#              SKIPS on an empty merged_target rather than failing, so exposing one
#              is a merge with no base check at all (review tk-lgpyg finding #1).
#   (INVARIANT) swept over the whole fixture: no bead ends a pass visible to
#              merge-skill with an empty merged_target.
#   (RETRY)    ...and with the write-loss lifted the next pass completes the same
#              recovery — "leave it invisible" is a deferral, not a new stall.
#   (MRHEALED) a lost merge_result_healed marker is a lost dependent too: without it
#              a recovered anchor whose check_set already reads normal is skipped
#              forever while merge-skill holds (review tk-lgpyg finding #4).
#   (MRSTATE)  a lost merge_result_pr_state on a MERGED PR -> not exposed, so no
#              later pass dispatches a signoff into the void (finding #4).
#   (LIVEFAIL) a recovered anchor carrying a persisted non-OPEN state whose LIVE
#              re-check is unreadable -> the recorded verdict stands and NOTHING is
#              armed. The re-check exists so a REOPENED PR is gated again; this is the
#              other direction, where an unanswered `gh` must not be read as "reopened"
#              and dispatch a signoff for a PR nobody can merge (review tk-h1ymf
#              testing gap). And because that anchor is VISIBLE and UNGATED, the pass
#              also exits UNSAFE_RC -- a recorded non-OPEN state is a memory of an
#              earlier read, not a gate, and WHICH pass recovered the anchor does not
#              change what merge-skill would do with an empty check_set
#              (review tk-pka2d finding #4).
#   (LIVEFAILGATED) the same anchor with a NON-empty check_set -> a deferral (exit 0),
#              because its gate already holds any merge. The contrast is what keeps
#              the fix from holding the whole rig's queue on one unreadable read.
#   (LIVEFAILNONUM) the same anchor with NO pr_number -> a deferral too: merge-skill
#              finds a PR by number and skips an anchor without one, so it cannot be
#              landed at all. The hold is owed to the EXPOSURE, not to every refusal.
#   (SCANFAIL) one candidate scan is unreadable -> the WHOLE phase is skipped. The
#              ambiguity guard is a whole-set property, so a partial set can turn a
#              real duplicate into a promoted anchor (review tk-lgpyg finding #3);
#              with both scans readable the same fixture is correctly refused.
#   (UNGATED)  merge_result sticks but the check_set stamp does NOT -> the anchor is
#              VISIBLE and ungated, so the pass exits UNSAFE_RC (review tk-ej3wq #2).
#   (ENUMFAIL) merge_result sticks but the phase-1 enumeration returns NOTHING ->
#              same exposure, same UNSAFE_RC instead of a quiet "no gating anchors".
#   (IDEMPOT)  a second pass recovers nothing (the stamped bead is no longer a
#              candidate).
#   (REOPENSAME)     a CLOSED PR REOPENED between phase 0's certification and phase 1
#                    -> gated on THIS pass. The pass-local inert skip re-asks the
#                    certified live state instead of trusting phase 0's read, because
#                    phase 0 has already made the anchor visible to merge-skill.sh
#                    with an empty check_set (review tk-sdqwh finding #1).
#   (INERTLIVEFAIL)  the same exposure with the live state UNREADABLE -> UNSAFE_RC.
#                    An exposure this pass created and cannot confirm inert holds the
#                    merge skill -- and so does the identical one an EARLIER pass
#                    created (Run 5j), because the hold keys on the exposure (visible +
#                    ungated + unconfirmable), never on its provenance.
#   (PRNUMONLY)      the certified pr_url is persisted on a pr_number-only anchor, so
#                    the identity survives into the processes that act on it
#                    (review tk-sdqwh finding #2).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/check-set-heal.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
eq()  { [ "$1" = "$2" ] && ok "$3" || bad "$3 (got '$1' want '$2')"; }

mkdir -p "$TMP/bin"

# Beads. One per line:
#   id|assignee|merge_result|pr_url|pr_number|branch|merged_target|anchor_bead|
#   task_kind|source_review_bead|routed_to|check_set|target|source_anchor_bead
# Field 7 is `merged_target` (what the merge skill validates against); field 13 is
# the plain `target` a polecat records at hand-off. They are separate on purpose:
# the backfill must prefer the recorded intent over the PR's live base.
# An empty field means the metadata key is ABSENT; the literal `__EMPTY__` in field 7
# means the key is PRESENT with an empty value (a partial write) — a distinction jq's
# `//` collapses and this script must not. `merge_result` here is the STORED value; a
# stamp applied during a run overlays it (see mr_for).
cat > "$TMP/beads" <<'B'
b-RECOVER|||https://github.com/o/r/pull/701||polecat/feat-recover|||||||
b-ROUTED||||702|polecat/feat-routed|main||||pool/polecat||
b-ANCHORB|||https://github.com/o/r/pull/703|703|polecat/feat-anchorb|main|b-RECOVER|||||
b-TASKKIND|||https://github.com/o/r/pull/704|704|polecat/feat-taskkind|main||review||||
b-SRCREV|||https://github.com/o/r/pull/705|705|polecat/feat-srcrev|main|||b-TASKKIND|||
b-NOBRANCH|||https://github.com/o/r/pull/706|706||main||||||
b-POLECAT|gc-toolkit/gc-toolkit.nux||https://github.com/o/r/pull/707|707|polecat/feat-polecat|main||||||
b-ONEANCH|||https://github.com/o/r/pull/708|708|polecat/feat-oneanch|main||||||
b-INCUMBENT||pull_request|https://github.com/o/r/pull/708|708|polecat/feat-incumbent|main|||||codex||
b-AMBIG1|||https://github.com/o/r/pull/709|709|polecat/feat-ambig1|main||||||
b-AMBIG2|||https://github.com/o/r/pull/709|709|polecat/feat-ambig2|main||||||
b-NONUM|||https://github.com/o/r/commits/deadbeef||polecat/feat-nonum|||||||
b-GHFAIL|||https://github.com/o/r/pull/711|711|polecat/feat-ghfail|main||||||
b-MERGED|||https://github.com/o/r/pull/712|712|polecat/feat-merged|||||||
b-NONCANON|shutupandlisten/refinery||https://github.com/o/r/pull/713|713|polecat/feat-noncanon|main||||||
b-TGTONLY|||https://github.com/o/r/pull/714|714|polecat/feat-tgtonly|||||||release-2|
b-CSNORMAL|||https://github.com/o/r/pull/715|715|polecat/feat-csnormal|main|||||codex||
b-PRNUMONLY||||716|polecat/feat-prnumonly|main||||||
b-SRCANCH|||https://github.com/o/r/pull/717|717|polecat/feat-srcanch|main|||||||b-ANCHOR-X
b-MTEMPTY|||https://github.com/o/r/pull/718|718|polecat/feat-mtempty|__EMPTY__||||||release-3|
b-INCFAIL|||https://github.com/o/r/pull/719|719|polecat/feat-incfail|main||||||
b-URLMISMATCH|||https://github.com/o/OTHER/pull/740|740|polecat/feat-urlmismatch|main||||||
b-HEADMISMATCH|||https://github.com/o/r/pull/741|741|polecat/feat-headmismatch|main||||||
b-URLSUFFIX|||https://github.com/o/r/pull/742/files|742|polecat/feat-urlsuffix|main||||||
b-PARTIALID|||https://github.com/o/r/pull/743|743|polecat/feat-partialid|main||||||
b-FORKHEAD|||https://github.com/o/r/pull/744|744|polecat/feat-forkhead|main||||||
b-URLINC|||https://github.com/o/r/pull/745|745|polecat/feat-urlinc|main||||||
b-URLINCUMB||pull_request|https://github.com/o/r/pull/745||polecat/feat-urlincumb|main|||||codex||
B

# $FAKE_FLIP rows are "<num>\t<state>": the PR's state CHANGES to <state> after its
# FIRST view of this run. That models the one thing a point-in-time certification
# cannot see — a PR reopened (or closed) between the read that certified it and the
# next read — which is the whole of review tk-sdqwh finding #1: phase 0 certifies a
# CLOSED PR, RESTORES merge_result, and the anchor is visible to merge-skill.sh with
# an empty check_set from that moment on.
# $FAKE_VIEWFAIL_LATER rows are bare numbers whose SECOND and later views fail, as a
# gh outage between two reads in one pass would.
# Live PRs: num|state|base|head|url|headRepo. A number absent here makes the gh stub
# fail (GHFAIL). `head`, `url` and `headRepo` are the PR's IDENTITY: the recovery must
# certify that the PR it is about to bind an anchor to is really this bead's PR, since
# `gh pr view <n>` resolves the number in the CURRENT repo and a number alone can name
# somebody else's pull request — and a branch NAME can be reused by any fork, so the
# head repository is part of that identity too. An empty url column defaults to this
# repo's canonical URL for that number; an empty headRepo column defaults to this repo
# (`o/r`), i.e. not a fork. A blank state/base/head column models a partial `gh`
# response (PARTIALID).
cat > "$TMP/prs" <<'P'
701|OPEN|main|polecat/feat-recover|
703|OPEN|main|polecat/feat-anchorb|
704|OPEN|main|polecat/feat-taskkind|
705|OPEN|main|polecat/feat-srcrev|
706|OPEN|main||
707|OPEN|main|polecat/feat-polecat|
708|OPEN|main|polecat/feat-oneanch|
709|OPEN|main|polecat/feat-ambig1|
712|MERGED|main|polecat/feat-merged|
713|OPEN|release|polecat/feat-noncanon|
714|OPEN|main|polecat/feat-tgtonly|
715|OPEN|main|polecat/feat-csnormal|
716|OPEN|main|polecat/feat-prnumonly|
717|OPEN|main|polecat/feat-srcanch|
718|OPEN|main|polecat/feat-mtempty|
719|OPEN|main|polecat/feat-incfail|
740|OPEN|main|polecat/feat-urlmismatch|
741|OPEN|main|polecat/somebody-elses-work|
742|OPEN|main|polecat/feat-urlsuffix|
743|OPEN||polecat/feat-partialid|
744|OPEN|main|polecat/feat-forkhead||fork-owner/r
745|OPEN|main|polecat/feat-urlinc|
P

# --- git stub. ------------------------------------------------------------------
# `git remote get-url origin` -> what this checkout pushes to, and the ONLY source of
# the expected repository (review tk-5nxyg finding #1). It is deliberately NOT `gh`:
# gh's idea of the current repository is movable, and moving it must not move the
# expectation. $FAKE_REPOFAIL makes it unanswerable, as a checkout with no origin
# remote would (REPOFAIL).
cat > "$TMP/bin/git" <<'GIT'
#!/usr/bin/env bash
if [ "$1" = "remote" ] && [ "$2" = "get-url" ] && [ "$3" = "origin" ]; then
  [ -s "$FAKE_REPOFAIL" ] && exit 1
  printf 'https://github.com/o/r.git\n'; exit 0
fi
exit 0
GIT
chmod +x "$TMP/bin/git"

# --- gh stub. -------------------------------------------------------------------
# `gh pr view <num> [--repo <r>] --json state,baseRefName,url,headRefName,headRepositoryOwner,headRepository`
# `gh repo view --json nameWithOwner -q .nameWithOwner` -> whatever repository gh
# considers CURRENT. $FAKE_GH_DEFAULT moves it, exactly as `gh repo set-default`,
# GH_REPO or a different cwd would; `o/r` when unset. $FAKE_REPOFAIL makes gh
# unanswerable, as a gh with no auth would.
#
# THE READ FOLLOWS THAT DEFAULT UNLESS `--repo` PINS IT. This is the whole hazard of
# finding #1 in one stub: with the default moved, a bare `gh pr view <n>` answers with
# ANOTHER repository's same-numbered pull request — OPEN, based on main, and opened
# from a branch of exactly the name the bead records, so it is indistinguishable from
# ours on every field except the repository. A script that derives its expected repo
# from `gh repo view` compares that foreign PR against that same foreign repo and
# certifies it. Only a read pinned with `--repo` to the ORIGIN-derived repository can
# tell them apart.
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
ghdefault=$(cat "$FAKE_GH_DEFAULT" 2>/dev/null)
[ -n "$ghdefault" ] || ghdefault="o/r"
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  [ -s "$FAKE_REPOFAIL" ] && exit 1
  printf '%s\n' "$ghdefault"; exit 0
fi
[ "$1" = "pr" ] && [ "$2" = "view" ] || exit 0
num="$3"; shift 3
repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    *)      shift ;;
  esac
done
# $FAKE_IGNORE_REPO models a gh that does not honour `--repo` at all — a redirect after
# a repository transfer or rename, an older gh, a wrapper. The pinned read is then no
# defence, and only COMPARING what came back against the expectation catches it.
[ -s "$FAKE_IGNORE_REPO" ] && repo=""
[ -n "$repo" ] || repo="$ghdefault"
# `--repo` is `[HOST/]OWNER/REPO`, and with the host OMITTED gh supplies it from
# GH_HOST (`gh help environment`) — modelled by $FAKE_GH_HOST, github.com when unset.
# That is finding #1 in one stub: a hostless `--repo o/r` does not name a repository,
# it names one PER HOST, so pointing GH_HOST at another GitHub host reads THAT host's
# `o/r`. The PR that comes back has the same owner/repo and the same head repo, so an
# identity keyed on owner/repo alone cannot tell it from ours — only a comparison that
# keeps the host can.
host=""
case "$repo" in
  */*/*) host="${repo%%/*}"; repo="${repo#*/}" ;;
esac
if [ -z "$host" ]; then
  host=$(cat "$FAKE_GH_HOST" 2>/dev/null)
  [ -n "$host" ] || host="github.com"
fi
if [ "$host/$repo" != "github.com/o/r" ]; then
  # A foreign repository's PR of the same number — foreign by owner/repo, by HOST, or
  # by both. Its head branch mirrors ours when the fixture knows the number, so the
  # deception is total; $FAKE_FOREIGN_HEAD names it for the runs where the number
  # exists ONLY in the foreign repo.
  fhead=$(awk -F'|' -v n="$num" '$1==n{print $4; exit}' "$FAKE_PRS" 2>/dev/null)
  [ -n "$fhead" ] || fhead=$(cat "$FAKE_FOREIGN_HEAD" 2>/dev/null)
  jq -nc --arg n "$num" --arg r "$repo" --arg hst "$host" --arg h "$fhead" \
    '{state:"OPEN", baseRefName:"main", headRefName:$h,
      url:("https://" + $hst + "/" + $r + "/pull/" + $n),
      headRepositoryOwner:{login:($r|split("/")[0])},
      headRepository:{name:($r|split("/")[1])}}'
  exit 0
fi
row=$(awk -F'|' -v n="$num" '$1==n{print; exit}' "$FAKE_PRS" 2>/dev/null)
# Unknown PR -> a failed view (empty stdout, non-zero), as the real gh does.
[ -n "$row" ] || exit 1
state=$(printf '%s' "$row" | cut -d'|' -f2)
# Second-and-later views of this number: fail (a gh outage mid-pass), or serve the
# CHANGED state (the PR moved between two reads of the same pass). Both key on a
# per-number marker file, so they survive across stub invocations.
seen="$FAKE_SEEN_DIR/$num"
if [ -e "$seen" ]; then
  grep -qx "$num" "$FAKE_VIEWFAIL_LATER" 2>/dev/null && exit 1
  flip=$(awk -F'\t' -v n="$num" '$1==n{print $2; exit}' "$FAKE_FLIP" 2>/dev/null)
  [ -n "$flip" ] && state="$flip"
else
  : > "$seen"
fi
base=$(printf '%s' "$row" | cut -d'|' -f3)
head=$(printf '%s' "$row" | cut -d'|' -f4)
url=$(printf '%s' "$row" | cut -d'|' -f5)
hrepo=$(printf '%s' "$row" | cut -d'|' -f6)
[ -n "$url" ] || url="https://github.com/o/r/pull/$num"
# Not a fork unless the fixture says so.
[ -n "$hrepo" ] || hrepo="o/r"
jq -nc --arg s "$state" --arg b "$base" --arg h "$head" --arg u "$url" \
       --arg ho "${hrepo%%/*}" --arg hn "${hrepo#*/}" \
  '{state:$s, baseRefName:$b, headRefName:$h, url:$u,
    headRepositoryOwner:{login:$ho}, headRepository:{name:$hn}}'
GH
chmod +x "$TMP/bin/gh"

# --- gc stub. ------------------------------------------------------------------
# bd list --has-metadata-key <k>            -> beads carrying that key (phase 0 scan)
# bd list --metadata-field merge_result=<s> -> beads whose LIVE merge_result matches
#                                              ($FAKE_ENUMFAIL forces this EMPTY, to
#                                              simulate a failed phase-1 enumeration)
# bd list --metadata-field pr_number=<n>    -> beads with that pr_number (one-anchor
#                                              guard + inflight_for). A number listed
#                                              in $FAKE_LOOKUPFAIL fails outright.
# bd list --metadata-field anchor_bead=<a>  -> reviews minted this run
# bd show / create / update / dep / session
cat > "$TMP/bin/gc" <<'GC'
#!/usr/bin/env bash
[ "$1" = "bd" ] || exit 0

# A metadata value written this run overlays the stored one. $FAKE_STAMPS rows are
# "<id>\t<key>\t<value>"; the last write wins.
stamp_for() {
  awk -F'\t' -v i="$1" -v k="$2" '$1==i && $2==k{print $3}' "$FAKE_STAMPS" 2>/dev/null | tail -1
}
# Live merge_result: a stamp applied this run overlays the stored value.
mr_for() {
  local v; v=$(stamp_for "$1" merge_result)
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  awk -F'|' -v i="$1" '$1==i{print $3; exit}' "$FAKE_BEADS"
}
# Live check_set (phase 1 stamps it).
cs_for() {
  local v; v=$(stamp_for "$1" check_set)
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  awk -F'|' -v i="$1" '$1==i{print $12; exit}' "$FAKE_BEADS"
}
# Live pr_number (phase 0 may backfill it).
pr_for() {
  local v; v=$(stamp_for "$1" pr_number)
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  awk -F'|' -v i="$1" '$1==i{print $5; exit}' "$FAKE_BEADS"
}
# Live pr_url (phase 0 backfills the CERTIFIED url on an anchor that has none, so
# the identity it certified outlives the process that certified it).
purl_for() {
  local v; v=$(stamp_for "$1" pr_url)
  [ -n "$v" ] && { printf '%s' "$v"; return; }
  awk -F'|' -v i="$1" '$1==i{print $4; exit}' "$FAKE_BEADS"
}

# Emit one bead as a JSON object, with LIVE metadata overlays applied.
emit() {
  local id="$1" assignee mr prurl prnum branch target ab tk srev routed cs sab
  local row; row=$(awk -F'|' -v i="$id" '$1==i{print; exit}' "$FAKE_BEADS")
  assignee=$(printf '%s' "$row" | cut -d'|' -f2)
  prurl=$(purl_for "$id")
  branch=$(printf '%s' "$row" | cut -d'|' -f6)
  ab=$(printf '%s' "$row" | cut -d'|' -f8)
  tk=$(printf '%s' "$row" | cut -d'|' -f9)
  srev=$(printf '%s' "$row" | cut -d'|' -f10)
  routed=$(printf '%s' "$row" | cut -d'|' -f11)
  sab=$(printf '%s' "$row" | cut -d'|' -f14)
  local plaintgt; plaintgt=$(printf '%s' "$row" | cut -d'|' -f13)
  mr=$(mr_for "$id"); prnum=$(pr_for "$id"); cs=$(cs_for "$id")
  # merged_target: a phase-0 backfill overlays the stored target.
  target=$(stamp_for "$id" merged_target)
  [ -n "$target" ] || target=$(printf '%s' "$row" | cut -d'|' -f7)
  # Flags/markers written this run, so their effect is observable on a later pass.
  local anc hflag mrh mrs
  anc=$(stamp_for "$id" assignee_noncanonical)
  hflag=$(stamp_for "$id" check_set_healed)
  mrh=$(stamp_for "$id" merge_result_healed)
  mrs=$(stamp_for "$id" merge_result_pr_state)
  # Pre-seeded durable markers (a run that starts mid-history seeds these directly).
  [ -n "$mrh" ] || mrh=$(awk -F'\t' -v i="$id" '$1==i && $2=="merge_result_healed"{print $3}' "$FAKE_SEED" 2>/dev/null | tail -1)
  [ -n "$mrs" ] || mrs=$(awk -F'\t' -v i="$id" '$1==i && $2=="merge_result_pr_state"{print $3}' "$FAKE_SEED" 2>/dev/null | tail -1)
  jq -nc --arg id "$id" --arg as "$assignee" --arg mr "$mr" --arg pu "$prurl" \
         --arg pn "$prnum" --arg br "$branch" --arg tg "$target" --arg ab "$ab" \
         --arg tk "$tk" --arg sr "$srev" --arg rt "$routed" --arg cs "$cs" \
         --arg anc "$anc" --arg hf "$hflag" --arg pt "$plaintgt" --arg sab "$sab" \
         --arg mrh "$mrh" --arg mrs "$mrs" '
    {id: $id, title: ("impl " + $id), assignee: (if $as == "" then null else $as end),
     metadata: ({}
       + (if $mr == "" then {} else {merge_result: $mr} end)
       + (if $pu == "" then {} else {pr_url: $pu} end)
       + (if $pn == "" then {} else {pr_number: $pn} end)
       + (if $br == "" then {} else {branch: $br} end)
       + (if $tg == "" then {} elif $tg == "__EMPTY__" then {merged_target: ""} else {merged_target: $tg} end)
       + (if $pt == "" then {} else {target: $pt} end)
       + (if $ab == "" then {} else {anchor_bead: $ab} end)
       + (if $tk == "" then {} else {task_kind: $tk} end)
       + (if $sr == "" then {} else {source_review_bead: $sr} end)
       + (if $sab == "" then {} else {source_anchor_bead: $sab} end)
       + (if $rt == "" then {} else {"gc.routed_to": $rt} end)
       + (if $anc == "" then {} else {assignee_noncanonical: $anc} end)
       + (if $hf == "" then {} else {check_set_healed: $hf} end)
       + (if $mrh == "" then {} else {merge_result_healed: $mrh} end)
       + (if $mrs == "" then {} else {merge_result_pr_state: $mrs} end)
       + (if $cs == "" then {} else {check_set: $cs} end))}'
}

case "$2" in
  list)
    ids=""
    # THE FAILURE AN "IS IT AN ARRAY?" TEST CANNOT SEE. Every injection below models
    # a read that wrote NOTHING and exited non-zero. This one models the other half:
    # a read that FAILED while still writing a well-formed, EMPTY array — a read that
    # died after emitting, a page that came back short. The payload passes any shape
    # test, so only the EXIT STATUS distinguishes it from a truthful "[]", and "[]" is
    # exactly the value every caller reads as a positive fact ("no duplicate", "no
    # incumbent", "no anchors", "nothing in flight"). Rows in $FAKE_RCPAYLOAD name
    # which surface fails this way, so each guard can be pinned on its own
    # (review tk-thvbq finding #1).
    rcpayload() { grep -qx "$1" "$FAKE_RCPAYLOAD" 2>/dev/null; }
    # THE OTHER HALF THE EXIT STATUS CANNOT SEE. rcpayload models a read that FAILED
    # while writing a well-formed array; this models a read that SUCCEEDED (exit 0)
    # while writing a JSON ERROR OBJECT instead of the array of beads that was asked
    # for. The exit-status guard passes it and the "output at all" guard passes it —
    # only the `type == "array"` payload-shape guard can tell it was never a bead
    # list. And an object is not inert: `.[]` iterates its VALUES happily, so an
    # object whose values are bead-shaped would be read as a bead list by every
    # caller downstream (review tk-pka2d, non-blocking note).
    objpayload() { grep -qx "$1" "$FAKE_OBJPAYLOAD" 2>/dev/null; }
    case "$*" in
      *"--status=open,in_progress --has-metadata-key pr_url"*)
        # The incumbent scan by URL (one-anchor-per-PR's other identity surface).
        # Distinguished from the phase-0 candidate scan by its status filter, so each
        # can be failed independently. $FAKE_INCSCANFAIL makes it unreadable.
        [ -s "$FAKE_INCSCANFAIL" ] && exit 1
        rcpayload incscan && { printf '[]\n'; exit 1; }
        objpayload incscan && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'|' '$4!=""{print $1}' "$FAKE_BEADS") ;;
      *"--has-metadata-key pr_url"*)
        # Injected scan failure: this key's candidate scan is unreadable. A real `gc`
        # failure prints nothing to stdout and exits non-zero — indistinguishable
        # from an empty result unless the caller checks.
        grep -qx pr_url "$FAKE_SCANFAIL" 2>/dev/null && exit 1
        rcpayload scan-pr_url && { printf '[]\n'; exit 1; }
        objpayload scan-pr_url && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'|' '$4!=""{print $1}' "$FAKE_BEADS") ;;
      *"--has-metadata-key pr_number"*)
        grep -qx pr_number "$FAKE_SCANFAIL" 2>/dev/null && exit 1
        rcpayload scan-pr_number && { printf '[]\n'; exit 1; }
        objpayload scan-pr_number && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        # Includes beads whose pr_number was backfilled this run.
        ids=$(awk -F'|' '{print $1}' "$FAKE_BEADS" | while read -r i; do
                [ -n "$(pr_for "$i")" ] && echo "$i"; done) ;;
      *"merge_result=pull_request"*)
        # Injected enumeration failure: the gating scan returns nothing at all.
        [ -s "$FAKE_ENUMFAIL" ] && { printf '[]\n'; exit 0; }
        rcpayload enum-pull_request && { printf '[]\n'; exit 1; }
        objpayload enum-pull_request && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'|' '{print $1}' "$FAKE_BEADS" | while read -r i; do
                [ "$(mr_for "$i")" = "pull_request" ] && echo "$i"; done) ;;
      *"merge_result=pre_open_gate"*)
        [ -s "$FAKE_ENUMFAIL" ] && { printf '[]\n'; exit 0; }
        rcpayload enum-pre_open_gate && { printf '[]\n'; exit 1; }
        objpayload enum-pre_open_gate && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'|' '{print $1}' "$FAKE_BEADS" | while read -r i; do
                [ "$(mr_for "$i")" = "pre_open_gate" ] && echo "$i"; done) ;;
      *"pr_number="*)
        want=$(printf '%s' "$*" | sed -n 's/.*--metadata-field pr_number=\([0-9][0-9]*\).*/\1/p')
        # Injected lookup failure: the ledger is unreadable for this PR. Real `gc`
        # failures print nothing to stdout and exit non-zero.
        grep -qx "$want" "$FAKE_LOOKUPFAIL" 2>/dev/null && exit 1
        rcpayload "lookup-$want" && { printf '[]\n'; exit 1; }
        objpayload "lookup-$want" && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'|' '{print $1}' "$FAKE_BEADS" | while read -r i; do
                [ "$(pr_for "$i")" = "$want" ] && echo "$i"; done) ;;
      *"anchor_bead="*)
        want=$(printf '%s' "$*" | sed -n 's/.*--metadata-field anchor_bead=\([^ ]*\).*/\1/p')
        rcpayload inflight-anchor_bead && { printf '[]\n'; exit 1; }
        objpayload inflight-anchor_bead && { printf '{"error":"ledger unavailable"}\n'; exit 0; }
        ids=$(awk -F'\t' -v a="$want" '$2=="anchor_bead" && $3==a{print $1}' "$FAKE_REVMETA" 2>/dev/null) ;;
      *) : ;;
    esac
    # Injected PARTIAL enumeration: these ids are dropped from the gating scans only
    # (the phase-0 recovery scans still see them), modelling a row the enumeration
    # loses for any reason — a page boundary, a jq error, a write that lands after the
    # scan. Distinct from $FAKE_ENUMFAIL, which empties the scan entirely.
    case "$*" in
      *"merge_result="*)
        if [ -s "$FAKE_ENUMDROP" ]; then
          ids=$(printf '%s\n' $ids | grep -vxF -f "$FAKE_ENUMDROP" || true)
        fi ;;
    esac
    # `--limit=N` TRUNCATES, as the real `gc bd list` does; `--limit=0` is unbounded.
    # Modelled because a cap is not cosmetic here: a gating anchor past it is one no
    # pass dispatches a signoff for (tk-47bij finding #3), and a stub that ignores the
    # flag cannot tell an unbounded scan from a capped one.
    lim=$(printf '%s' "$*" | sed -n 's/.*--limit=\([0-9][0-9]*\).*/\1/p')
    if [ -n "$lim" ] && [ "$lim" -gt 0 ]; then
      ids=$(printf '%s\n' $ids | head -n "$lim")
    fi
    out=""
    for i in $ids; do
      o=$(emit "$i")
      if [ -z "$out" ]; then out="$o"; else out="$out,$o"; fi
    done
    printf '[%s]\n' "$out" ;;
  show)
    id="$3"
    # A review minted this run is not in FAKE_BEADS; serve its recorded metadata.
    # task_kind / gc.routed_to / assignee are the fields the stranded-route repair
    # inspects, so they are served too — last write wins, as the ledger would.
    if ! awk -F'|' -v i="$id" '$1==i{f=1} END{exit !f}' "$FAKE_BEADS"; then
      rv() { awk -F'\t' -v i="$id" -v k="$1" '$1==i && $2==k{v=$3} END{print v}' "$FAKE_REVMETA" 2>/dev/null; }
      ab=$(rv anchor_bead); rtk=$(rv task_kind); rrt=$(rv gc.routed_to)
      jq -nc --arg ab "$ab" --arg tk "$rtk" --arg rt "$rrt" \
        '[{assignee: null, status: "open", metadata: ({}
           + (if $ab == "" then {} else {anchor_bead: $ab} end)
           + (if $tk == "" then {} else {task_kind: $tk} end)
           + (if $rt == "" then {} else {"gc.routed_to": $rt} end))}]'
      exit 0
    fi
    printf '[%s]\n' "$(emit "$id")" ;;
  create)
    n=$(cat "$FAKE_SEQ" 2>/dev/null || echo 0); n=$((n + 1)); printf '%s' "$n" > "$FAKE_SEQ"
    printf '{"id":"rev-new-%s"}\n' "$n" ;;
  update)
    id="$3"
    for k in merge_result merge_result_healed merge_result_heal_flagged \
             merge_result_pr_state pr_number pr_url merged_target check_set check_set_healed \
             check_set_heal_flagged assignee_noncanonical anchor_bead gc.routed_to \
             task_kind review_branch; do
      if printf '%s' "$*" | grep -q -- "--set-metadata $k="; then
        v=$(printf '%s' "$*" | sed -n "s/.*--set-metadata $k=\\([^ ]*\\).*/\\1/p")
        # Injected write-loss, per (id, key): never persist this key for this bead.
        if grep -qx "$(printf '%s\t%s' "$id" "$k")" "$FAKE_STAMPFAIL" 2>/dev/null; then
          continue
        fi
        printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_STAMPS"
        case "$k" in
          anchor_bead|gc.routed_to|task_kind|review_branch)
            printf '%s\t%s\t%s\n' "$id" "$k" "$v" >> "$FAKE_REVMETA" ;;
        esac
      fi
    done ;;
  dep)
    rev="$3"; anchor=$(printf '%s' "$*" | sed -n 's/.*--blocks \([^ ]*\).*/\1/p')
    printf '%s\t%s\n' "$rev" "$anchor" >> "$FAKE_DEPS" ;;
esac
exit 0
GC
chmod +x "$TMP/bin/gc"

: > "$TMP/stamps"; : > "$TMP/revmeta"; : > "$TMP/deps"; : > "$TMP/stampfail"
: > "$TMP/lookupfail"; : > "$TMP/enumfail"; : > "$TMP/seed"; : > "$TMP/scanfail"
: > "$TMP/incscanfail"; : > "$TMP/repofail"; : > "$TMP/rcpayload"; : > "$TMP/objpayload"
: > "$TMP/ghdefault"; : > "$TMP/foreignhead"; : > "$TMP/ghhost"
: > "$TMP/ignorerepo"; : > "$TMP/enumdrop"
: > "$TMP/flip"; : > "$TMP/viewfaillater"; mkdir -p "$TMP/seen"
echo 0 > "$TMP/seq"

export PATH="$TMP/bin:$PATH"
export FAKE_BEADS="$TMP/beads" FAKE_PRS="$TMP/prs" FAKE_STAMPS="$TMP/stamps" \
       FAKE_REVMETA="$TMP/revmeta" FAKE_DEPS="$TMP/deps" \
       FAKE_STAMPFAIL="$TMP/stampfail" FAKE_SEQ="$TMP/seq" \
       FAKE_LOOKUPFAIL="$TMP/lookupfail" FAKE_ENUMFAIL="$TMP/enumfail" \
       FAKE_SEED="$TMP/seed" FAKE_SCANFAIL="$TMP/scanfail" \
       FAKE_INCSCANFAIL="$TMP/incscanfail" FAKE_REPOFAIL="$TMP/repofail" \
       FAKE_GH_DEFAULT="$TMP/ghdefault" FAKE_FOREIGN_HEAD="$TMP/foreignhead" \
       FAKE_GH_HOST="$TMP/ghhost" FAKE_IGNORE_REPO="$TMP/ignorerepo" \
       FAKE_ENUMDROP="$TMP/enumdrop" FAKE_FLIP="$TMP/flip" \
       FAKE_VIEWFAIL_LATER="$TMP/viewfaillater" FAKE_SEEN_DIR="$TMP/seen" \
       FAKE_RCPAYLOAD="$TMP/rcpayload" FAKE_OBJPAYLOAD="$TMP/objpayload"

stamped() { grep -qx "$(printf '%s\t%s\t%s' "$1" "$2" "$3")" "$TMP/stamps"; }
recovered() { grep -qx "$(printf '%s\tmerge_result\tpull_request' "$1")" "$TMP/stamps"; }
dispatched_for() { grep -q "$(printf '\tanchor_bead\t%s' "$1")" "$TMP/revmeta"; }
# The bead's LIVE merged_target: a backfill stamped this run, else the stored column
# (where the literal __EMPTY__ means "key present but empty").
live_mt() {
  local v; v=$(awk -F'\t' -v i="$1" '$1==i && $2=="merged_target"{print $3}' "$TMP/stamps" 2>/dev/null | tail -1)
  if [ -z "$v" ]; then
    v=$(awk -F'|' -v i="$1" '$1==i{print $7; exit}' "$TMP/beads")
    [ "$v" = "__EMPTY__" ] && v=""
  fi
  printf '%s' "$v"
}
# THE INVARIANT THE RECOVERY OWES merge-skill.sh. merge-skill enumerates anchors on
# merge_result=pull_request, and its retarget guard is
#   [ -n "$target" ] && [ -n "$base" ] && [ "$target" != "$base" ]
# — an EMPTY merged_target does not FAIL that check, it SKIPS it, and the anchor then
# merges onto whatever base the PR now points at with no base validation at all. So
# "visible with an empty merged_target" is precisely the state that bypasses the base
# check, and the heal must never leave a bead in it: either both fields land, or
# neither does and the bead stays invisible (review tk-lgpyg finding #1).
exposed_unprotected() { recovered "$1" && [ -z "$(live_mt "$1")" ]; }
run_heal() {
  bash "$SCRIPT" \
    --default 'codex' \
    --review-pool 'gc-toolkit/gc-toolkit.polecat-codex' \
    --fix-pool 'gc-toolkit/gc-toolkit.polecat' \
    --refinery 'gc-toolkit/gc-toolkit.refinery'
}
reset_run() { : > "$TMP/stamps"; : > "$TMP/revmeta"; : > "$TMP/deps"
              : > "$TMP/stampfail"; : > "$TMP/lookupfail"; : > "$TMP/enumfail"
              : > "$TMP/seed"; : > "$TMP/scanfail"
              : > "$TMP/incscanfail"; : > "$TMP/repofail"; : > "$TMP/rcpayload"; : > "$TMP/objpayload"
              : > "$TMP/ghdefault"; : > "$TMP/foreignhead"; : > "$TMP/ghhost"
              : > "$TMP/ignorerepo"; : > "$TMP/enumdrop"
              : > "$TMP/flip"; : > "$TMP/viewfaillater"
              rm -rf "$TMP/seen"; mkdir -p "$TMP/seen"
              echo 0 > "$TMP/seq"; }

# --- Run 1: the full candidate field. -------------------------------------------
echo '719' > "$TMP/lookupfail"
RC1=0
OUT1="$(run_heal 2>"$TMP/err1")" || RC1=$?
eq "$RC1" "0" "(EXIT) a recovery pass with no ungated check_set exits 0"

# (RECOVER) the live-case shape: pr_url + branch, no merge_result, unassigned.
recovered b-RECOVER \
  && ok "(RECOVER) a merge_result-less anchor carrying pr_url is restored to pull_request" \
  || bad "(RECOVER) must restore merge_result (stamps: $(cat "$TMP/stamps"))"
stamped b-RECOVER pr_number 701 \
  && ok "(RECOVER) pr_number backfilled from pr_url (merge-skill skips an anchor without one)" \
  || bad "(RECOVER) must backfill pr_number=701"
stamped b-RECOVER merged_target main \
  && ok "(RECOVER) merged_target backfilled from the live PR base" \
  || bad "(RECOVER) must backfill merged_target=main"
stamped b-RECOVER merge_result_healed pull_request \
  && ok "(RECOVER) the repair leaves a durable audit marker" \
  || bad "(RECOVER) must record merge_result_healed"
stamped b-RECOVER merge_result_pr_state OPEN \
  && ok "(RECOVER) the PR state observed at recovery is persisted for later passes" \
  || bad "(RECOVER) must record merge_result_pr_state (stamps: $(cat "$TMP/stamps"))"

# The whole point of running phase 0 FIRST: the recovered anchor is also GATED on
# this same pass, not one wake later.
stamped b-RECOVER check_set codex \
  && ok "(RECOVER) the recovered anchor is check_set-healed in the SAME pass" \
  || bad "(RECOVER) recovered anchor must reach phase 1 in the same pass"
dispatched_for b-RECOVER \
  && ok "(RECOVER) a codex signoff is dispatched for the recovered anchor" \
  || bad "(RECOVER) recovered anchor must get a signoff (revmeta: $(cat "$TMP/revmeta"))"

# (PRNUMONLY) the positive counterpart to b-ROUTED: pr_number alone (no pr_url) is a
# real anchor shape, and nothing needs backfilling.
recovered b-PRNUMONLY \
  && ok "(PRNUMONLY) a pr_number-only anchor is recovered (pr_url is not required)" \
  || bad "(PRNUMONLY) must recover a pr_number-only anchor"
stamped b-PRNUMONLY pr_number 716 \
  && bad "(PRNUMONLY) an already-present pr_number must not be re-stamped" \
  || ok "(PRNUMONLY) pr_number already present -> not re-backfilled"
# ...and the CERTIFIED URL is persisted on it (review tk-sdqwh finding #2). This is
# the shape the finding names: recovery leaves a pr_number-only anchor, and a bare
# number is what a moved gh default re-points at a stranger's pull request. The
# certification happened in THIS process; the backfill is what carries it to
# merge-skill.sh and the observer, which run in others.
stamped b-PRNUMONLY pr_url https://github.com/o/r/pull/716 \
  && ok "(PRNUMONLY) the certified pr_url is backfilled, so the identity outlives this process" \
  || bad "(PRNUMONLY) must backfill the certified pr_url (stamps: $(cat "$TMP/stamps"))"
# An anchor that already HAS one keeps it: the backfill fills a gap, it never
# overwrites what the bead recorded.
stamped b-RECOVER pr_url https://github.com/o/r/pull/701 \
  && bad "(PRNUMONLY) an anchor with its own pr_url must not have it re-stamped" \
  || ok "(PRNUMONLY) pr_url already present -> not re-written"
dispatched_for b-PRNUMONLY \
  && ok "(PRNUMONLY) the recovered pr_number-only anchor is gated in the same pass" \
  || bad "(PRNUMONLY) pr_number-only anchor must be gated"

# (CSNORMAL) review tk-ej3wq finding #1. merge_result was lost but check_set survived,
# so the anchor reads "already normalized" — yet its gate has NOTHING to raise it.
# Skipping it holds the merge forever on a check.codex nobody was dispatched to stamp.
recovered b-CSNORMAL \
  && ok "(CSNORMAL) an anchor with a surviving check_set is still recovered" \
  || bad "(CSNORMAL) must recover an anchor whose check_set survived"
stamped b-CSNORMAL check_set codex \
  && bad "(CSNORMAL) an already-normal check_set must NOT be re-stamped" \
  || ok "(CSNORMAL) already-normal check_set left alone (no redundant stamp)"
dispatched_for b-CSNORMAL \
  && ok "(CSNORMAL) a recovered anchor with a normal check_set STILL gets a signoff" \
  || bad "(CSNORMAL) recovered+normal anchor must be dispatched, not skipped forever (revmeta: $(cat "$TMP/revmeta"))"

# (ROUTED) THE hazard: merge-skill.sh's in-flight-rework hold counts open beads
# referencing the PR with an EMPTY merge_result. Stamping a rework child cancels
# that hold and lands the PR mid-rework.
recovered b-ROUTED && bad "(ROUTED) a pool-routed rework child must NEVER be stamped — it would cancel the in-flight hold" \
                   || ok "(ROUTED) pool-routed rework child left alone (in-flight hold preserved)"
recovered b-ANCHORB && bad "(ANCHORB) a bead carrying anchor_bead is a child, not an anchor" \
                    || ok "(ANCHORB) anchor_bead-carrying child left alone"
recovered b-TASKKIND && bad "(TASKKIND) task_kind=review is not an anchor" \
                     || ok "(TASKKIND) review bead left alone"
recovered b-SRCREV && bad "(SRCREV) source_review_bead marks a rework child" \
                   || ok "(SRCREV) signoff-spawned rework child left alone"
recovered b-NOBRANCH && bad "(NOBRANCH) a PR-referencing bead with no branch is not a merge anchor" \
                    || ok "(NOBRANCH) branchless PR bead left alone"
recovered b-POLECAT && bad "(POLECAT) a polecat-assigned bead is live WIP, not a parked anchor" \
                   || ok "(POLECAT) polecat-assigned bead left alone"

# (SRCANCH) review tk-ej3wq finding #3. reconcile-merged-prs.sh files stale-base
# rebase children carrying branch + pr_url + pr_number + source_anchor_bead and NO
# merge_result — the candidate shape exactly. Routing alone does not exclude them:
# gc.routed_to is CLEARED when a polecat claims the child, so this fixture wears the
# post-claim shape with routing gone.
recovered b-SRCANCH \
  && bad "(SRCANCH) a source_anchor_bead rebase child must NEVER be promoted to anchor" \
  || ok "(SRCANCH) source_anchor_bead rebase child left alone (routing already cleared)"

# (ONEANCH) PR#708 already has an open anchor (b-INCUMBENT carries merge_result).
recovered b-ONEANCH && bad "(ONEANCH) a PR already claimed by an open anchor must not gain a second (tk-ynz4b)" \
                    || ok "(ONEANCH) PR with an incumbent anchor -> candidate skipped"

# (INCFAIL) the incumbent lookup for PR#719 FAILS. An unreadable ledger returns the
# same empty string as "no incumbent" — reading that as absence would promote a child
# on any transient hiccup, so it must fail CLOSED.
recovered b-INCFAIL \
  && bad "(INCFAIL) a failed incumbent lookup must not read as 'no incumbent' (fail closed)" \
  || ok "(INCFAIL) incumbent-lookup failure -> candidate skipped, not promoted"
grep -q 'incumbent-anchor lookup for PR#719 failed' "$TMP/err1" \
  && ok "(INCFAIL) the unreadable lookup is warned about" \
  || bad "(INCFAIL) must warn on an unreadable incumbent lookup (err: $(cat "$TMP/err1"))"

# (AMBIG) two candidates for PR#709 — neither can be identified as the anchor.
if recovered b-AMBIG1 || recovered b-AMBIG2; then
  bad "(AMBIG) two candidates for one PR must BOTH be skipped (fail closed)"
else
  ok "(AMBIG) two candidates naming one PR -> neither stamped (fail closed)"
fi
grep -q 'MULTIPLE merge_result-less candidates' "$TMP/err1" \
  && ok "(AMBIG) the ambiguity is reported for an operator" \
  || bad "(AMBIG) ambiguity must be reported (err: $(cat "$TMP/err1"))"

# (NONUM) a pr_url that names no PR number cannot be repaired.
recovered b-NONUM && bad "(NONUM) an unresolvable PR number must not be stamped" \
                  || ok "(NONUM) unresolvable PR number -> skipped"
grep -q 'no resolvable PR number' "$TMP/err1" \
  && ok "(NONUM) the unresolvable reference is warned about" \
  || bad "(NONUM) must warn on an unresolvable PR number"

# (GHFAIL) PR#711 is absent from the PR fixture -> `gh pr view` fails.
recovered b-GHFAIL && bad "(GHFAIL) an unconfirmed PR must not be stamped" \
                   || ok "(GHFAIL) gh view failure -> not stamped (retry next pass)"
grep -q 'PR#711 view failed' "$TMP/err1" \
  && ok "(GHFAIL) the failed PR read is warned about" \
  || bad "(GHFAIL) must warn on a failed PR view"

# (MERGED) an already-merged PR needs VISIBILITY (so the observer closes the bead),
# not a gate: arming codex would dispatch a signoff for a PR nobody can merge.
recovered b-MERGED \
  && ok "(MERGED) a merged PR's anchor is restored to visibility for the observer" \
  || bad "(MERGED) must restore merge_result on a merged PR's anchor"
stamped b-MERGED check_set codex && bad "(MERGED) a merged PR must NOT have a gate armed" \
                                 || ok "(MERGED) merged PR -> no gate armed"
dispatched_for b-MERGED && bad "(MERGED) a merged PR must NOT dispatch a signoff" \
                        || ok "(MERGED) merged PR -> no signoff dispatched"
stamped b-MERGED merge_result_pr_state MERGED \
  && ok "(MERGED) the non-OPEN PR state is PERSISTED so the skip survives the pass" \
  || bad "(MERGED) must persist merge_result_pr_state=MERGED (stamps: $(cat "$TMP/stamps"))"

# (NONCANON) the second half of the live case's invisibility. Flagged, not rewritten.
recovered b-NONCANON \
  && ok "(NONCANON) a refinery-assigned (non-canonical) anchor is still recovered" \
  || bad "(NONCANON) refinery-ish assignee must not block recovery"
stamped b-NONCANON assignee_noncanonical shutupandlisten/refinery \
  && ok "(NONCANON) the non-canonical assignee is FLAGGED on the bead" \
  || bad "(NONCANON) must flag assignee_noncanonical (stamps: $(cat "$TMP/stamps"))"
grep -q "is not the canonical refinery identity" "$TMP/err1" \
  && ok "(NONCANON) the non-canonical assignee is reported for an operator" \
  || bad "(NONCANON) must warn about the non-canonical assignee"
# Flag only — the assignee itself is an operator call, never auto-rewritten.
grep -q -- '--assignee' "$TMP/err1" && bad "(NONCANON) the assignee must never be rewritten" \
                                    || ok "(NONCANON) assignee flagged, never rewritten"

# (TGTONLY) merged_target ABSENT but a plain `target` survived: the backfill must
# take the RECORDED INTENT, not the PR's live base. Taking the live base would bless
# a retarget that happened while the anchor was invisible.
recovered b-TGTONLY \
  && ok "(TGTONLY) an anchor with target but no merged_target is recovered" \
  || bad "(TGTONLY) must recover an anchor missing merged_target"
stamped b-TGTONLY merged_target release-2 \
  && ok "(TGTONLY) merged_target backfilled from the recorded target, not the live PR base" \
  || bad "(TGTONLY) must prefer target=release-2 over live base=main (stamps: $(cat "$TMP/stamps"))"
stamped b-TGTONLY merged_target main \
  && bad "(TGTONLY) the live base must NOT overwrite the recorded target" \
  || ok "(TGTONLY) live base did not override the recorded intent"

# (MTEMPTY) review tk-ej3wq finding #5. merged_target is PRESENT but EMPTY (a partial
# write). jq `//` treats only null/false as absent, so the empty string used to
# shadow the recorded target and drop through to the live PR base — silently blessing
# a retarget. An empty value must resolve exactly like an absent one.
recovered b-MTEMPTY \
  && ok "(MTEMPTY) an anchor with an empty merged_target is recovered" \
  || bad "(MTEMPTY) must recover an anchor whose merged_target is empty"
stamped b-MTEMPTY merged_target release-3 \
  && ok "(MTEMPTY) an EMPTY merged_target does not shadow the recorded target" \
  || bad "(MTEMPTY) empty merged_target must fall through to target=release-3 (stamps: $(cat "$TMP/stamps"))"
stamped b-MTEMPTY merged_target main \
  && bad "(MTEMPTY) an empty merged_target must NOT resolve to the live PR base (blesses a retarget)" \
  || ok "(MTEMPTY) live base did not fill an empty merged_target"

# (URLMISMATCH) review tk-lgpyg finding #2. The bead's pr_url names ANOTHER repo's
# #740, but `gh pr view 740` resolves in the CURRENT repo — so the number alone would
# bind this anchor to a pull request that has nothing to do with it, and then gate and
# MERGE it. The metadata that named the PR is damaged by construction (that is why
# merge_result is missing), so the PR's own identity is the only trustworthy source.
recovered b-URLMISMATCH \
  && bad "(URLMISMATCH) a pr_url naming a DIFFERENT repo must never be bound to this repo's same-numbered PR" \
  || ok "(URLMISMATCH) pr_url/live-URL mismatch -> refused (fail closed)"
grep -q "would bind this anchor to a DIFFERENT pull request" "$TMP/err1" \
  && ok "(URLMISMATCH) the mis-binding is reported for an operator" \
  || bad "(URLMISMATCH) must warn about the URL mismatch (err: $(cat "$TMP/err1"))"

# (HEADMISMATCH) the second half of the identity: PR#741 exists in this repo but is
# opened from somebody else's branch, so the bead and the PR describe different work.
recovered b-HEADMISMATCH \
  && bad "(HEADMISMATCH) a PR whose head branch is not the bead's branch is not this bead's PR" \
  || ok "(HEADMISMATCH) branch/headRefName mismatch -> refused (fail closed)"
grep -q "describe different work" "$TMP/err1" \
  && ok "(HEADMISMATCH) the branch mismatch is reported for an operator" \
  || bad "(HEADMISMATCH) must warn about the head mismatch (err: $(cat "$TMP/err1"))"

# (URLSUFFIX) the recertification must not invent mismatches: a pr_url with a
# sub-path (/files, /commits, a trailing slash) is the SAME PR and must still recover.
# A fail-closed check that fires on cosmetics would strand every such anchor.
recovered b-URLSUFFIX \
  && ok "(URLSUFFIX) a pr_url with a sub-path still matches the canonical PR URL" \
  || bad "(URLSUFFIX) URL normalization must not reject '/pull/742/files' (err: $(cat "$TMP/err1"))"

# (FORKHEAD) review tk-h1ymf finding #1. PR#744 satisfies EVERY other half of the
# identity — right repo, right number, matching URL, and a headRefName equal to the
# bead's branch — and is still not this bead's PR: it is opened from a branch of that
# name in a FORK. Branch names are owned by nobody, so headRefName alone is satisfied
# by any fork that reuses one; without the head-repository check the recovery binds the
# anchor to it and merge-skill later merges a stranger's code under this bead.
recovered b-FORKHEAD \
  && bad "(FORKHEAD) a fork's PR reusing the bead's branch NAME must never be bound to the bead" \
  || ok "(FORKHEAD) fork head repository -> refused (fail closed)"
grep -q "in FORK 'fork-owner/r'" "$TMP/err1" \
  && ok "(FORKHEAD) the fork head is named in the warning" \
  || bad "(FORKHEAD) must warn that the head branch lives in a fork (err: $(cat "$TMP/err1"))"

# (PARTIALID) `gh` answered — it did not fail — but the object is missing a field
# (PR#743 has a blank baseRefName). A partial or schema-shifted response leaves the
# identity uncertified, and an uncertified identity is exactly what phase 0 must not
# act on. The guard is part of the safety contract, so it is pinned by a test rather
# than left to survive the next refactor by luck (review tk-h1ymf testing gap).
recovered b-PARTIALID \
  && bad "(PARTIALID) a PR whose identity fields are partly blank must not be certified" \
  || ok "(PARTIALID) partial gh identity -> refused (fail closed)"
grep -q "PR#743 identity is unreadable" "$TMP/err1" \
  && ok "(PARTIALID) the unreadable identity is reported for an operator" \
  || bad "(PARTIALID) must warn that the identity is unreadable (err: $(cat "$TMP/err1"))"

# (URLINC) review tk-h1ymf finding #2. PR#745 is ALREADY anchored by b-URLINCUMB, which
# carries merge_result and pr_url but no pr_number — a shape phase 0 itself produces,
# since pr_number is one of the fields it backfills. A number-keyed incumbent lookup
# cannot see it, so the candidate would pass the one-anchor guard, be stamped WITH a
# pr_number, and become the only anchor merge-skill can see (it skips anchors without
# one) while the real one is stranded. The lookup must use the same identity surface as
# the recovery: number OR normalized URL.
recovered b-URLINC \
  && bad "(URLINC) a PR already anchored by URL alone must not gain a second anchor (tk-ynz4b)" \
  || ok "(URLINC) URL-only incumbent seen -> candidate skipped"
grep -q "b-URLINCUMB already anchors it by pr_url" "$TMP/err1" \
  && ok "(URLINC) the incumbent is named for an operator" \
  || bad "(URLINC) must name the URL-only incumbent (err: $(cat "$TMP/err1"))"

# THE INVARIANT, swept across every bead this pass touched: nothing is left VISIBLE
# to merge-skill without the merged_target its retarget guard needs. Asserted over the
# whole fixture rather than one case, because the hazard is a partial write, and a
# partial write can happen on any of them (review tk-lgpyg finding #1).
UNPROTECTED=""
while IFS= read -r b; do
  [ -n "$b" ] || continue
  exposed_unprotected "$b" && UNPROTECTED="$UNPROTECTED $b"
done < <(awk -F'|' '{print $1}' "$TMP/beads")
[ -z "$UNPROTECTED" ] \
  && ok "(INVARIANT) no anchor is left visible-to-merge-skill with an empty merged_target" \
  || bad "(INVARIANT) these anchors would merge with NO retarget guard:$UNPROTECTED"

printf '%s\n' "$OUT1" | grep -q '8 anchor(s) restored to visible gating' \
  && ok "run 1 reports 8 anchors restored" || bad "run 1 recovery count (got: $OUT1)"

# --- Run 2: idempotence. Stamped anchors are no longer candidates. --------------
: > "$TMP/err2"
OUT2="$(run_heal 2>"$TMP/err2")"
printf '%s\n' "$OUT2" | grep -q '0 anchor(s) restored to visible gating' \
  && ok "(IDEMPOT) a second pass restores nothing (already visible)" \
  || bad "(IDEMPOT) second pass must recover 0 (got: $OUT2)"
# The flag is bounded: the same non-canonical assignee is not re-warned.
grep -q "is not the canonical refinery identity" "$TMP/err2" \
  && bad "(IDEMPOT) the non-canonical assignee warning must not repeat every pass" \
  || ok "(IDEMPOT) the non-canonical flag is bounded (no repeat warning)"

# (INERT2) review tk-ej3wq finding #4. b-MERGED is now VISIBLE (run 1 stamped its
# merge_result) and carries merge_result_healed, so it flows into the satisfiability
# path on this pass. Without the persisted merge_result_pr_state the pass would have
# no memory that PR#712 is MERGED and would arm codex + dispatch a signoff for a PR
# nobody can merge.
stamped b-MERGED check_set codex \
  && bad "(INERT2) a second pass must NOT arm a gate on a merged PR's anchor" \
  || ok "(INERT2) the MERGED skip survives the pass (persisted PR state honoured)"
dispatched_for b-MERGED \
  && bad "(INERT2) a second pass must NOT dispatch a signoff for a merged PR" \
  || ok "(INERT2) merged PR -> still no signoff on a later pass"
printf '%s\n' "$OUT2" | grep -q 'its PR is MERGED; leaving the gate alone' \
  && ok "(INERT2) the durable skip is reported" || bad "(INERT2) must report the persisted-state skip (got: $OUT2)"

# --- Run 3: REOPEN. A persisted non-OPEN state is RE-CHECKED, never blindly trusted:
#     a PR reopened after the recovery must be gated normally, not suppressed forever.
reset_run
cat > "$TMP/beads" <<'B'
b-REOPEN||pull_request|https://github.com/o/r/pull/720|720|polecat/feat-reopen|main||||||
B
cat > "$TMP/prs" <<'P'
720|OPEN|main|polecat/feat-reopen|
P
printf 'b-REOPEN\tmerge_result_healed\tpull_request\nb-REOPEN\tmerge_result_pr_state\tCLOSED\n' > "$TMP/seed"
RC3=0
OUT3="$(run_heal 2>"$TMP/err3")" || RC3=$?
stamped b-REOPEN merge_result_pr_state OPEN \
  && ok "(REOPEN) the stale non-OPEN record is refreshed once the PR is open again" \
  || bad "(REOPEN) must refresh merge_result_pr_state to OPEN (stamps: $(cat "$TMP/stamps"))"
dispatched_for b-REOPEN \
  && ok "(REOPEN) a reopened PR's anchor is gated normally, not suppressed by the stale record" \
  || bad "(REOPEN) reopened PR must be gated (revmeta: $(cat "$TMP/revmeta"))"
eq "$RC3" "0" "(REOPEN) a gated reopened anchor exits 0"
printf '%s\n' "$OUT3" | grep -q 'is OPEN again; refreshing the record' \
  && ok "(REOPEN) the stale-record correction is reported" \
  || bad "(REOPEN) must report the reopen (got: $OUT3)"

# --- Run 3a: REOPENSAME. The SAME-PASS reopen (review tk-sdqwh finding #1). --------
# Phase 0 certifies PR#746 CLOSED, restores merge_result — and the anchor is VISIBLE
# to merge-skill.sh from that instant, with an empty check_set that merge-skill reads
# as "declares no gates". The PR is then reopened before phase 1 reaches the bead.
# The pass-local skip used to trust phase 0's read unconditionally and leave the gate
# alone: an OPEN PR, visible, ungated, mergeable un-reviewed by the merge skill that
# runs later in this very pass. The pass-local arm must therefore re-ask the SAME
# certified question the persisted arm asks, and gate the anchor when the answer is
# OPEN.
reset_run
cat > "$TMP/beads" <<'B'
b-REOPENSAME|||https://github.com/o/r/pull/746|746|polecat/feat-reopensame|main||||||
B
cat > "$TMP/prs" <<'P'
746|CLOSED|main|polecat/feat-reopensame|
P
printf '746\tOPEN\n' > "$TMP/flip"
RC3A=0
run_heal >/dev/null 2>"$TMP/err3a" || RC3A=$?
recovered b-REOPENSAME \
  && ok "(REOPENSAME) phase 0 still restores visibility (the PR was CLOSED when it looked)" \
  || bad "(REOPENSAME) must restore merge_result (stamps: $(cat "$TMP/stamps"))"
stamped b-REOPENSAME check_set codex \
  && ok "(REOPENSAME) reopened between the phases -> GATED on this pass, not left ungated" \
  || bad "(REOPENSAME) a same-pass reopen must be gated before merge-skill runs (stamps: $(cat "$TMP/stamps"))"
dispatched_for b-REOPENSAME \
  && ok "(REOPENSAME) ...and its signoff is dispatched, so the armed gate is satisfiable" \
  || bad "(REOPENSAME) must dispatch the signoff (revmeta: $(cat "$TMP/revmeta"))"
stamped b-REOPENSAME merge_result_pr_state OPEN \
  && ok "(REOPENSAME) the recorded PR state is corrected to OPEN" \
  || bad "(REOPENSAME) must refresh the recorded state"
eq "$RC3A" "0" "(REOPENSAME) an anchor gated on the same pass is not an exposure -> exit 0"

# --- Run 3a2: INERTLIVEFAIL. The same exposure, with the re-check UNREADABLE. ------
# Phase 0 restored merge_result on a CLOSED PR — durable, already visible — and then
# the live state cannot be read at all, so nothing here can say whether the PR is
# still closed. The check_set is still empty, which merge-skill reads as "no gates".
# THIS pass created that exposure, so it is the one arm that must not merely defer:
# hold merge-skill for the pass (UNSAFE_RC) and re-ask on the next idle wake. The
# Run 5j (LIVEFAIL) is the same exposure created by an EARLIER pass, and it holds the
# merge skill too: the anchor is equally visible and equally ungated, so provenance
# changes only the wording. The real contrast is Run 5j2 (LIVEFAILGATED), where a
# NON-empty check_set already holds any merge and the unreadable state is therefore
# only a deferral — which is what keeps one anchor's silence from stalling the rig.
reset_run
cat > "$TMP/beads" <<'B'
b-INERTLIVEFAIL|||https://github.com/o/r/pull/747|747|polecat/feat-inertlivefail|main||||||
B
cat > "$TMP/prs" <<'P'
747|CLOSED|main|polecat/feat-inertlivefail|
P
printf '747\n' > "$TMP/viewfaillater"
RC3A2=0
run_heal >/dev/null 2>"$TMP/err3a2" || RC3A2=$?
recovered b-INERTLIVEFAIL \
  && ok "(INERTLIVEFAIL) the visibility repair itself still lands" \
  || bad "(INERTLIVEFAIL) must restore merge_result"
stamped b-INERTLIVEFAIL check_set codex \
  && bad "(INERTLIVEFAIL) an unconfirmable PR must not have a gate armed off a stale read" \
  || ok "(INERTLIVEFAIL) unreadable live state -> no gate armed"
eq "$RC3A2" "3" "(INERTLIVEFAIL) exposed-this-pass + ungated + unconfirmable -> UNSAFE_RC holds merge-skill"
grep -q 'UNSAFE — b-INERTLIVEFAIL was restored to visibility THIS pass' "$TMP/err3a2" \
  && ok "(INERTLIVEFAIL) the exposure is named for an operator" \
  || bad "(INERTLIVEFAIL) must report the unsafe exposure (err: $(cat "$TMP/err3a2"))"

# --- Run 3b: REOPENWRONG. The reopen re-check must RE-CERTIFY the PR, not name it by
#     number (review tk-r11wt finding #1). ------------------------------------------
# `gh pr view <n>` resolves a number in whatever repository gh considers CURRENT, and
# THIS arm runs on a later pass than the one that certified the anchor — a
# `gh repo set-default`, a GH_REPO in the environment, or a different cwd is enough to
# move which repo answers. Here PR#723 answers from `o/OTHER`, OPEN. Probing state
# alone would read "reopened", refresh this anchor's record to OPEN, arm codex and
# dispatch a signoff — for a stranger's pull request, and then release the merge on its
# state. The identity phase 0 certified (URL + repository) must be re-confirmed, so an
# uncertifiable probe is treated exactly like an unreadable one: nothing refreshed,
# nothing armed, retried next pass.
reset_run
cat > "$TMP/beads" <<'B'
b-REOPENWRONG||pull_request|https://github.com/o/r/pull/723|723|polecat/feat-reopenwrong|main||||||
B
cat > "$TMP/prs" <<'P'
723|OPEN|main|polecat/feat-reopenwrong|https://github.com/o/OTHER/pull/723
P
printf 'b-REOPENWRONG\tmerge_result_healed\tpull_request\nb-REOPENWRONG\tmerge_result_pr_state\tCLOSED\n' > "$TMP/seed"
RC3B=0
run_heal >/dev/null 2>"$TMP/err3b" || RC3B=$?
stamped b-REOPENWRONG merge_result_pr_state OPEN \
  && bad "(REOPENWRONG) another repo's same-numbered PR must NOT refresh this anchor's record to OPEN" \
  || ok "(REOPENWRONG) wrong-repo probe -> the recorded verdict stands"
dispatched_for b-REOPENWRONG \
  && bad "(REOPENWRONG) a signoff must never be dispatched off a stranger's pull request" \
  || ok "(REOPENWRONG) wrong-repo probe -> no signoff dispatched"
stamped b-REOPENWRONG check_set codex \
  && bad "(REOPENWRONG) no gate may be armed on an uncertified PR" \
  || ok "(REOPENWRONG) wrong-repo probe -> no gate armed"
grep -q "would bind this anchor to a DIFFERENT pull request" "$TMP/err3b" \
  && ok "(REOPENWRONG) the foreign pull request is reported for an operator" \
  || bad "(REOPENWRONG) must warn which PR answered (err: $(cat "$TMP/err3b"))"
# An uncertifiable probe is treated exactly like an unreadable one — and this anchor
# is VISIBLE (merge_result is stamped) with an EMPTY check_set, which merge-skill.sh
# reads as "declares no gates". merge-skill runs later in this same patrol pass in its
# own gh context and may resolve #723 perfectly well; if it does, it lands an
# un-reviewed PR. Why THIS pass could not certify does not change that, so the hold is
# owed here too (review tk-pka2d finding #4). It used to exit 0.
eq "$RC3B" "3" "(REOPENWRONG) an uncertified PR on a VISIBLE, UNGATED anchor holds the merge (UNSAFE_RC)"

# --- Run 3b2: REOPENNOURL. The same hazard on an anchor with NO pr_url of its own.
# The strongest form of the regression: with no recorded URL to compare against, the
# URL half of the certification is SKIPPED entirely, so the only thing standing between
# this anchor and a stranger's PR is the certified ORIGIN REPOSITORY check. And this is
# not a hypothetical shape — pr_number is a field phase 0 BACKFILLS, so an anchor
# recovered from a bare pr_url, or one whose pr_url was among the fields lost to the
# same damage, reaches this arm carrying a number and nothing else.
reset_run
cat > "$TMP/beads" <<'B'
b-REOPENNOURL||pull_request||725|polecat/feat-reopennourl|main||||||
B
cat > "$TMP/prs" <<'P'
725|OPEN|main|polecat/feat-reopennourl|https://github.com/o/OTHER/pull/725
P
printf 'b-REOPENNOURL\tmerge_result_healed\tpull_request\nb-REOPENNOURL\tmerge_result_pr_state\tCLOSED\n' > "$TMP/seed"
RC3B2=0
run_heal >/dev/null 2>"$TMP/err3b2" || RC3B2=$?
stamped b-REOPENNOURL merge_result_pr_state OPEN \
  && bad "(REOPENNOURL) with no pr_url to compare, the origin-repo check is the only guard — it must hold" \
  || ok "(REOPENNOURL) wrong-repo probe on a URL-less anchor -> the recorded verdict stands"
dispatched_for b-REOPENNOURL \
  && bad "(REOPENNOURL) a signoff must never be dispatched off another repository's PR" \
  || ok "(REOPENNOURL) wrong-repo probe on a URL-less anchor -> no signoff dispatched"
stamped b-REOPENNOURL check_set codex \
  && bad "(REOPENNOURL) no gate may be armed on an uncertified PR" \
  || ok "(REOPENNOURL) wrong-repo probe on a URL-less anchor -> no gate armed"
grep -q "not this checkout's 'github.com/o/r'" "$TMP/err3b2" \
  && ok "(REOPENNOURL) the foreign repository is named for an operator" \
  || bad "(REOPENNOURL) must warn which repository answered (err: $(cat "$TMP/err3b2"))"
# Same exposure, reached through a missing pr_url rather than a wrong repository:
# visible, ungated, uncertifiable. The anchor still records a pr_number, so
# merge-skill can find and land it.
eq "$RC3B2" "3" "(REOPENNOURL) an uncertifiable identity on a VISIBLE, UNGATED anchor holds the merge"

# --- Run 3c: REOPENFORK. The other identity half, on the same re-check. -----------
# PR#724 is in the RIGHT repository and its headRefName is exactly the bead's branch —
# and it is still not this bead's PR, because that head branch lives in a FORK. A
# branch NAME is owned by nobody, so the head-repository half of the identity is what
# separates "a PR that looks like this bead's" from "this bead's PR" here too.
reset_run
cat > "$TMP/beads" <<'B'
b-REOPENFORK||pull_request|https://github.com/o/r/pull/724|724|polecat/feat-reopenfork|main||||||
B
cat > "$TMP/prs" <<'P'
724|OPEN|main|polecat/feat-reopenfork||fork-owner/r
P
printf 'b-REOPENFORK\tmerge_result_healed\tpull_request\nb-REOPENFORK\tmerge_result_pr_state\tCLOSED\n' > "$TMP/seed"
RC3C=0
run_heal >/dev/null 2>"$TMP/err3c" || RC3C=$?
stamped b-REOPENFORK merge_result_pr_state OPEN \
  && bad "(REOPENFORK) a fork's PR reusing the bead's branch NAME must not refresh the record" \
  || ok "(REOPENFORK) fork-head probe -> the recorded verdict stands"
dispatched_for b-REOPENFORK \
  && bad "(REOPENFORK) a signoff must never be dispatched off a fork's pull request" \
  || ok "(REOPENFORK) fork-head probe -> no signoff dispatched"
grep -q "in FORK 'fork-owner/r'" "$TMP/err3c" \
  && ok "(REOPENFORK) the fork head is named for an operator" \
  || bad "(REOPENFORK) must warn that the head branch lives in a fork (err: $(cat "$TMP/err3c"))"
# And through a fork head. Refusing to GATE a fork's PR is right; leaving the anchor
# visible and ungated while refusing is the part that was not.
eq "$RC3C" "3" "(REOPENFORK) a fork's PR on a VISIBLE, UNGATED anchor holds the merge"

# --- Run 4: STAMPFAIL. A merge_result write that does not persist. --------------
# Deliberately NOT the UNSAFE_RC path: an invisible anchor cannot be merged by
# merge-skill.sh either, so this is the stalled status quo, not an ungated merge.
# Holding the whole rig's merge pass over it would trade a stall for a bigger one.
reset_run
cat > "$TMP/beads" <<'B'
b-STAMPFAIL|||https://github.com/o/r/pull/701||polecat/feat-stampfail|||||||
B
cat > "$TMP/prs" <<'P'
701|OPEN|main|polecat/feat-stampfail|
P
printf 'b-STAMPFAIL\tmerge_result\n' > "$TMP/stampfail"
RC4=0
OUT4="$(run_heal 2>"$TMP/err4")" || RC4=$?
recovered b-STAMPFAIL && bad "(STAMPFAIL) a non-persisting stamp must not count as recovered" \
                      || ok "(STAMPFAIL) non-persisting merge_result stamp -> not recovered"
stamped b-STAMPFAIL merge_result_heal_flagged 1 \
  && ok "(STAMPFAIL) the failed repair is flagged once" \
  || bad "(STAMPFAIL) must flag the bead once"
grep -q 'stays invisible' "$TMP/err4" \
  && ok "(STAMPFAIL) the still-invisible anchor is warned about" \
  || bad "(STAMPFAIL) must warn that the anchor stays invisible"
eq "$RC4" "0" "(STAMPFAIL) a failed visibility repair exits 0, NOT UNSAFE_RC (it cannot merge ungated)"
printf '%s\n' "$OUT4" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(STAMPFAIL) reported as skipped, not restored" || bad "(STAMPFAIL) summary (got: $OUT4)"

# --- Run 5: PARTIAL persistence. A DEPENDENT of visibility does not stick. -------
# `merge_result` is the switch that exposes the bead to merge-skill.sh; pr_number and
# merged_target are what merge-skill then depends on. Landing the switch while a
# dependent is missing is NOT recoverable later — the bead now has a merge_result, so
# it is no longer a phase-0 candidate and nothing will ever restore the missing field.
# Worst case is merged_target: merge-skill's retarget guard SKIPS on an empty value
# rather than failing on it, so the anchor merges with no base validation at all. So
# the dependents are written and verified BEFORE visibility: a lost one leaves the
# bead INVISIBLE (the stall we already had) and retried, never exposed-and-unprotected
# (review tk-lgpyg finding #1).
reset_run
cat > "$TMP/beads" <<'B'
b-PARTIAL|||https://github.com/o/r/pull/730||polecat/feat-partial|||||||
B
cat > "$TMP/prs" <<'P'
730|OPEN|main|polecat/feat-partial|
P
printf 'b-PARTIAL\tpr_number\nb-PARTIAL\tmerged_target\n' > "$TMP/stampfail"
RC5=0
OUT5="$(run_heal 2>"$TMP/err5")" || RC5=$?
recovered b-PARTIAL \
  && bad "(PARTIAL) visibility must NOT be flipped while a dependent is missing" \
  || ok "(PARTIAL) a lost dependent leaves the anchor INVISIBLE, not visible-and-unprotected"
exposed_unprotected b-PARTIAL \
  && bad "(PARTIAL) the anchor would merge with NO retarget guard — exactly the bypass this ordering exists to prevent" \
  || ok "(PARTIAL) merge-skill's base check cannot be bypassed by a lost merged_target"
grep -q 'required field(s) did not persist' "$TMP/err5" \
  && ok "(PARTIAL) the un-durable repair is reported" \
  || bad "(PARTIAL) must warn about the failed dependents (err: $(cat "$TMP/err5"))"
grep -q 'pr_number' "$TMP/err5" && grep -q 'merged_target' "$TMP/err5" \
  && ok "(PARTIAL) the warning names the fields that did not persist" \
  || bad "(PARTIAL) must name pr_number and merged_target (err: $(cat "$TMP/err5"))"
stamped b-PARTIAL merge_result_heal_flagged 1 \
  && ok "(PARTIAL) the failed repair is flagged once (bounded noise)" \
  || bad "(PARTIAL) must flag the bead once"
eq "$RC5" "0" "(PARTIAL) an invisible anchor is a stall, NOT the UNSAFE_RC exposure"
printf '%s\n' "$OUT5" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(PARTIAL) reported as skipped, not restored" || bad "(PARTIAL) summary (got: $OUT5)"

# ...and the repair is RETRIED UNTIL DURABLE: with the write-loss lifted, the very
# next pass recovers the same bead completely. This is what makes "leave it invisible"
# a deferral rather than a new permanent stall — the candidate predicate (merge_result
# absent) still matches, so the bead is still a candidate.
: > "$TMP/stampfail"; : > "$TMP/stamps"; : > "$TMP/revmeta"
RC5B=0
OUT5B="$(run_heal 2>"$TMP/err5b")" || RC5B=$?
recovered b-PARTIAL \
  && ok "(RETRY) the next pass recovers the bead once the writes stick" \
  || bad "(RETRY) a deferred recovery must retry (stamps: $(cat "$TMP/stamps"))"
stamped b-PARTIAL merged_target main \
  && ok "(RETRY) the dependent backfill lands on the retry" \
  || bad "(RETRY) merged_target must land on the retry"
eq "$RC5B" "0" "(RETRY) the completed recovery exits 0"
printf '%s\n' "$OUT5B" | grep -q '1 anchor(s) restored to visible gating' \
  && ok "(RETRY) the deferred anchor is reported restored on the retry" \
  || bad "(RETRY) retry recovery count (got: $OUT5B)"

# --- Run 5c: a lost RECOVERY MARKER is a lost dependent too. ---------------------
# merge_result_healed keeps a recovered anchor in phase 1's satisfiability path even
# when its check_set already reads normal; without it the anchor takes the "already
# normalized" exit forever while merge-skill holds on a check.codex nothing was ever
# dispatched to stamp. It is verified with the rest (review tk-lgpyg finding #4).
reset_run
cat > "$TMP/beads" <<'B'
b-MRHEALED|||https://github.com/o/r/pull/734|734|polecat/feat-mrhealed|main|||||codex||
B
cat > "$TMP/prs" <<'P'
734|OPEN|main|polecat/feat-mrhealed|
P
printf 'b-MRHEALED\tmerge_result_healed\n' > "$TMP/stampfail"
RC5C=0
OUT5C="$(run_heal 2>"$TMP/err5c")" || RC5C=$?
recovered b-MRHEALED \
  && bad "(MRHEALED) a lost merge_result_healed must not be exposed — the anchor would be visible and never dispatched" \
  || ok "(MRHEALED) a lost recovery marker leaves the anchor invisible and retried"
grep -q 'merge_result_healed' "$TMP/err5c" \
  && ok "(MRHEALED) the lost marker is named in the warning" \
  || bad "(MRHEALED) must name merge_result_healed (err: $(cat "$TMP/err5c"))"
eq "$RC5C" "0" "(MRHEALED) a lost marker is a stall, not an exposure"
printf '%s\n' "$OUT5C" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(MRHEALED) reported as skipped, not restored" || bad "(MRHEALED) summary (got: $OUT5C)"

# --- Run 5d: merge_result_pr_state is the marker that keeps a MERGED PR quiet. ----
# Lose it and the next pass has no memory that PR#735 is merged: it arms codex and
# dispatches a signoff for a PR nobody can merge. Verified before visibility, so the
# noise never gets a chance to start (review tk-lgpyg finding #4).
reset_run
cat > "$TMP/beads" <<'B'
b-MRSTATE|||https://github.com/o/r/pull/735|735|polecat/feat-mrstate|main||||||
B
cat > "$TMP/prs" <<'P'
735|MERGED|main|polecat/feat-mrstate|
P
printf 'b-MRSTATE\tmerge_result_pr_state\n' > "$TMP/stampfail"
RC5D=0
OUT5D="$(run_heal 2>"$TMP/err5d")" || RC5D=$?
recovered b-MRSTATE \
  && bad "(MRSTATE) a merged PR must not be made visible without the state record that keeps later passes quiet" \
  || ok "(MRSTATE) a lost merge_result_pr_state leaves the anchor invisible and retried"
dispatched_for b-MRSTATE \
  && bad "(MRSTATE) no signoff may be dispatched for a MERGED PR" \
  || ok "(MRSTATE) no signoff dispatched into the void"
grep -q 'merge_result_pr_state' "$TMP/err5d" \
  && ok "(MRSTATE) the lost marker is named in the warning" \
  || bad "(MRSTATE) must name merge_result_pr_state (err: $(cat "$TMP/err5d"))"
eq "$RC5D" "0" "(MRSTATE) a lost marker is a stall, not an exposure"
printf '%s\n' "$OUT5D" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(MRSTATE) reported as skipped, not restored" || bad "(MRSTATE) summary (got: $OUT5D)"

# --- Run 5e: SCANFAIL. One candidate scan is unreadable. -------------------------
# The ambiguity guard is a WHOLE-SET property: it can only see that two candidates
# name the same PR if BOTH are in the set. b-SCANA is reachable only via the pr_url
# scan and b-SCANB only via the pr_number scan, and they name the SAME PR#750. Drop
# the pr_url scan and b-SCANB looks unambiguous — and gets promoted to anchor for a PR
# it may not own. The incumbent guard cannot catch it either: neither rival carries a
# merge_result, so neither reads as an incumbent (review tk-lgpyg finding #3).
reset_run
cat > "$TMP/beads" <<'B'
b-SCANA|||https://github.com/o/r/pull/750||polecat/feat-scana|main||||||
b-SCANB||||750|polecat/feat-scanb|main||||||
B
cat > "$TMP/prs" <<'P'
750|OPEN|main|polecat/feat-scanb|
P
echo 'pr_url' > "$TMP/scanfail"
RC5E=0
OUT5E="$(run_heal 2>"$TMP/err5e")" || RC5E=$?
recovered b-SCANB \
  && bad "(SCANFAIL) a partial candidate set turned a real ambiguity into a promoted anchor" \
  || ok "(SCANFAIL) an unreadable scan skips the phase — no promotion from a partial view"
recovered b-SCANA \
  && bad "(SCANFAIL) nothing may be recovered from an incomplete candidate set" \
  || ok "(SCANFAIL) the phase is skipped wholesale, not per-candidate"
grep -q "recovery scan did not return a readable result" "$TMP/err5e" \
  && ok "(SCANFAIL) the unreadable scan is reported" \
  || bad "(SCANFAIL) must warn about the unreadable scan (err: $(cat "$TMP/err5e"))"
eq "$RC5E" "0" "(SCANFAIL) a skipped recovery phase is not an exposure (nothing was made visible)"
printf '%s\n' "$OUT5E" | grep -q 'restored to visible gating' \
  && bad "(SCANFAIL) the phase must be skipped WHOLESALE, not run and reported per candidate (got: $OUT5E)" \
  || ok "(SCANFAIL) no recovery summary at all — the phase never ran on a partial set"

# ...and with both scans readable the ambiguity is SEEN and both are refused — the
# same fixture, proving the skip above was the scan failure and not the guard.
: > "$TMP/scanfail"; : > "$TMP/stamps"; : > "$TMP/revmeta"
OUT5F="$(run_heal 2>"$TMP/err5f")" || true
if recovered b-SCANA || recovered b-SCANB; then
  bad "(SCANFAIL) with both scans readable the ambiguity must be caught and both refused"
else
  ok "(SCANFAIL) both scans readable -> the ambiguity guard sees the duplicate and refuses both"
fi
grep -q 'MULTIPLE merge_result-less candidates' "$TMP/err5f" \
  && ok "(SCANFAIL) the now-visible ambiguity is reported" \
  || bad "(SCANFAIL) must report the ambiguity once the set is complete (err: $(cat "$TMP/err5f"))"
printf '%s\n' "$OUT5F" | grep -q '0 anchor(s) restored to visible gating, 2 skipped' \
  && ok "(SCANFAIL) BOTH rivals are counted as skipped once the set is complete" \
  || bad "(SCANFAIL) complete-set summary (got: $OUT5F)"

# --- Run 5g: INCURLFAIL. The incumbent scan by pr_url is unreadable. --------------
# Same shape as INCFAIL, on the identity surface finding #2 added: a failed scan
# returns the same empty result as "no incumbent by URL", so reading it as absence
# would mint a second anchor on any transient ledger hiccup. Unlike SCANFAIL this is
# per-candidate — the answer is missing for THIS candidate's PR, not for the candidate
# set as a whole — so the phase still runs and reports the skip.
reset_run
cat > "$TMP/beads" <<'B'
b-INCURLFAIL|||https://github.com/o/r/pull/746|746|polecat/feat-incurlfail|main||||||
B
cat > "$TMP/prs" <<'P'
746|OPEN|main|polecat/feat-incurlfail|
P
echo 1 > "$TMP/incscanfail"
RC5G=0
OUT5G="$(run_heal 2>"$TMP/err5g")" || RC5G=$?
recovered b-INCURLFAIL \
  && bad "(INCURLFAIL) an unreadable pr_url incumbent scan must not read as 'no incumbent' (fail closed)" \
  || ok "(INCURLFAIL) pr_url incumbent scan failure -> candidate skipped, not promoted"
grep -q 'incumbent-anchor scan by pr_url failed' "$TMP/err5g" \
  && ok "(INCURLFAIL) the unreadable scan is warned about" \
  || bad "(INCURLFAIL) must warn on an unreadable pr_url incumbent scan (err: $(cat "$TMP/err5g"))"
eq "$RC5G" "0" "(INCURLFAIL) a deferred recovery is a stall, not an exposure"
printf '%s\n' "$OUT5G" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(INCURLFAIL) reported as skipped, not restored" || bad "(INCURLFAIL) summary (got: $OUT5G)"

# ...and with the scan readable the SAME bead recovers — proving the refusal above was
# the unreadable scan and not some other guard.
: > "$TMP/incscanfail"; : > "$TMP/stamps"; : > "$TMP/revmeta"
run_heal >/dev/null 2>"$TMP/err5h" || true
recovered b-INCURLFAIL \
  && ok "(INCURLFAIL) a readable scan with no incumbent -> the same bead recovers" \
  || bad "(INCURLFAIL) the refusal must be the scan failure, not a standing block (err: $(cat "$TMP/err5h"))"

# --- Run 5i: REPOFAIL. This checkout's own origin repository cannot be resolved. ---
# The head-repository check is only as good as the repository it compares against.
# With `gh repo view` failing and no git remote to fall back on, there is no expected
# value — and "matches" would then mean "was never checked", which is precisely the
# fork-binding hole finding #1 closed. Refuse and retry (review tk-h1ymf finding #1).
reset_run
cat > "$TMP/beads" <<'B'
b-REPOFAIL|||https://github.com/o/r/pull/747|747|polecat/feat-repofail|main||||||
B
cat > "$TMP/prs" <<'P'
747|OPEN|main|polecat/feat-repofail|
P
echo 1 > "$TMP/repofail"
RC5I=0
# `git remote get-url origin` must not answer either: run from a directory that is not
# a work tree, so the fallback is as unavailable as gh (cd back afterwards — $SCRIPT
# and $TMP are absolute, but the later runs read relative to nothing else).
OUT5I="$(cd "$TMP" && run_heal 2>"$TMP/err5i")" || RC5I=$?
recovered b-REPOFAIL \
  && bad "(REPOFAIL) with no expected repository the head-repo check is vacuous — must not certify" \
  || ok "(REPOFAIL) unresolvable origin repository -> refused (fail closed)"
grep -q 'cannot resolve this checkout' "$TMP/err5i" \
  && ok "(REPOFAIL) the unresolvable origin is reported for an operator" \
  || bad "(REPOFAIL) must warn that the origin repository is unresolvable (err: $(cat "$TMP/err5i"))"
eq "$RC5I" "0" "(REPOFAIL) a deferred recovery is a stall, not an exposure"
printf '%s\n' "$OUT5I" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(REPOFAIL) reported as skipped, not restored" || bad "(REPOFAIL) summary (got: $OUT5I)"

# --- Run 5i2: WRONGDEFAULT. gh's current repository is NOT this checkout's. --------
# The repository check is only meaningful if its two halves come from DIFFERENT
# sources. Deriving the expectation from `gh repo view` and the observation from a bare
# `gh pr view <n>` takes both from the one thing an operator can move — so pointing gh
# at a stranger's repository moves the expectation onto the stranger too and the
# comparison passes on a foreign pull request. Reproduced live with
# origin=zookanalytics/gc-toolkit and `gh repo set-default cli/cli`: both commands
# answered for cli/cli (review tk-5nxyg finding #1).
#
# Arm A is the shape with the least left to catch it: pr_number and NO pr_url, which is
# what phase 0 itself BACKFILLS toward. With no recorded URL the URL comparison is
# skipped entirely, so if the expected repository is also gh's, NOTHING distinguishes
# this bead's PR from the foreign one — same number, OPEN, same head branch name. Here
# PR#750 does not exist in `o/r` at all; only the wrongly-defaulted repo has one.
reset_run
cat > "$TMP/beads" <<'B'
b-WRONGDEF||||750|polecat/feat-wrongdef|||||||
B
: > "$TMP/prs"
echo 'evil/other' > "$TMP/ghdefault"
echo 'polecat/feat-wrongdef' > "$TMP/foreignhead"
RC5I2=0
OUT5I2="$(run_heal 2>"$TMP/err5i2")" || RC5I2=$?
recovered b-WRONGDEF \
  && bad "(WRONGDEFAULT) a moved gh default must not bind this anchor to another repo's PR#750" \
  || ok "(WRONGDEFAULT) pr_number-only anchor + wrong gh default -> refused (the read is pinned to origin)"
dispatched_for b-WRONGDEF \
  && bad "(WRONGDEFAULT) a signoff must never be dispatched off a foreign pull request" \
  || ok "(WRONGDEFAULT) wrong gh default -> no signoff dispatched"
grep -q 'PR#750 view failed' "$TMP/err5i2" \
  && ok "(WRONGDEFAULT) the origin-pinned read reports the PR as absent HERE, not as a foreign match" \
  || bad "(WRONGDEFAULT) must warn that PR#750 is unreadable in this repo (err: $(cat "$TMP/err5i2"))"
eq "$RC5I2" "0" "(WRONGDEFAULT) a refused recovery is a stall, not an exposure"
printf '%s\n' "$OUT5I2" | grep -q '0 anchor(s) restored to visible gating, 1 skipped' \
  && ok "(WRONGDEFAULT) reported as skipped, not restored" || bad "(WRONGDEFAULT) summary (got: $OUT5I2)"

# Arm B, the positive control: gh is STILL pointed at `evil/other`, but this time
# `o/r` really does have a PR#750. The fix must not degrade into "refuse whenever gh
# disagrees" — it must READ THE RIGHT ONE. Our #750 is based on `release-9` and the
# foreign one on `main`, and the bead records no target of its own, so the backfilled
# merged_target names which repository actually answered.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/prs" <<'P'
750|OPEN|release-9|polecat/feat-wrongdef|
P
run_heal >/dev/null 2>"$TMP/err5i3" || true
recovered b-WRONGDEF \
  && ok "(WRONGDEFAULT) with the PR present in origin's repo the same anchor recovers" \
  || bad "(WRONGDEFAULT) the refusal above must be the wrong repo, not a standing block (err: $(cat "$TMP/err5i3"))"
stamped b-WRONGDEF merged_target release-9 \
  && ok "(WRONGDEFAULT) the backfill reads ORIGIN's PR#750 (base release-9), not the gh default's" \
  || bad "(WRONGDEFAULT) merged_target must come from o/r's PR (stamps: $(cat "$TMP/stamps"))"
stamped b-WRONGDEF merged_target main \
  && bad "(WRONGDEFAULT) merged_target came from the FOREIGN PR — the read followed gh's default" \
  || ok "(WRONGDEFAULT) the foreign PR's base never reaches the anchor"

# Arm C: the same hazard on the REOPEN re-check, which runs on every LATER pass — in a
# process whose gh context is even less likely to be the one that certified the anchor.
# A persisted CLOSED verdict plus a foreign OPEN PR of the same number would refresh the
# record to OPEN and drop a stranger's PR into codex gating.
reset_run
cat > "$TMP/beads" <<'B'
b-WRONGDEFREOPEN||pull_request||751|polecat/feat-wrongdefreopen|main||||||
B
: > "$TMP/prs"
echo 'evil/other' > "$TMP/ghdefault"
echo 'polecat/feat-wrongdefreopen' > "$TMP/foreignhead"
printf 'b-WRONGDEFREOPEN\tmerge_result_healed\tpull_request\nb-WRONGDEFREOPEN\tmerge_result_pr_state\tCLOSED\n' > "$TMP/seed"
RC5I4=0
run_heal >/dev/null 2>"$TMP/err5i4" || RC5I4=$?
stamped b-WRONGDEFREOPEN merge_result_pr_state OPEN \
  && bad "(WRONGDEFAULT) a foreign OPEN PR must not refresh a CLOSED anchor's record" \
  || ok "(WRONGDEFAULT) reopen re-check with a moved gh default -> the recorded verdict stands"
dispatched_for b-WRONGDEFREOPEN \
  && bad "(WRONGDEFAULT) the reopen re-check must not dispatch off a foreign PR" \
  || ok "(WRONGDEFAULT) reopen re-check with a moved gh default -> no signoff dispatched"
stamped b-WRONGDEFREOPEN check_set codex \
  && bad "(WRONGDEFAULT) no gate may be armed on a PR read from the wrong repository" \
  || ok "(WRONGDEFAULT) reopen re-check with a moved gh default -> no gate armed"
# The reopen re-check under a moved gh default: the recorded verdict correctly stands
# and nothing is armed — but the anchor is visible, ungated and carries a pr_number, so
# the merge is held for the pass rather than left to merge-skill's own gh context.
eq "$RC5I4" "3" "(WRONGDEFAULT) a reopen re-check that cannot certify, on a VISIBLE UNGATED anchor, holds the merge"

# --- Run 5i5: CROSSREPOINC. Same pull NUMBER, different repository. ---------------
# Pull numbers are unique only within a repository, and this city's ledger spans rigs
# with different ones. An incumbent guard keyed on the bare number therefore reads
# `o/OTHER#745` as the owner of `o/r#745` and refuses a real repair — before PR identity
# certification, which would have caught the confusion, ever runs. That is precisely the
# silent stall this phase exists to end, reintroduced one identity field short
# (review tk-5nxyg finding #2).
reset_run
cat > "$TMP/beads" <<'B'
b-CROSSINC|||https://github.com/o/r/pull/745|745|polecat/feat-crossinc|main||||||
b-FOREIGNANCH||pull_request|https://github.com/o/OTHER/pull/745||polecat/feat-foreignanch|main|||||codex||
B
cat > "$TMP/prs" <<'P'
745|OPEN|main|polecat/feat-crossinc|
P
run_heal >/dev/null 2>"$TMP/err5i5" || true
recovered b-CROSSINC \
  && ok "(CROSSREPOINC) another repository's PR#745 does not anchor this one" \
  || bad "(CROSSREPOINC) cross-repo same-number incumbent must not block recovery (err: $(cat "$TMP/err5i5"))"
grep -q 'already anchors it by pr_url' "$TMP/err5i5" \
  && bad "(CROSSREPOINC) reported a false incumbent from another repository" \
  || ok "(CROSSREPOINC) no false-incumbent warning naming an unrelated bead"

# ...and the guard still FIRES when the incumbent really is this repo's #745 — proving
# the pass above came from the repository comparison, not from a disabled guard.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-CROSSINC|||https://github.com/o/r/pull/745|745|polecat/feat-crossinc|main||||||
b-FOREIGNANCH||pull_request|https://github.com/o/r/pull/745||polecat/feat-foreignanch|main|||||codex||
B
run_heal >/dev/null 2>"$TMP/err5i6" || true
recovered b-CROSSINC \
  && bad "(CROSSREPOINC) a SAME-repo URL incumbent must still block (one anchor per PR, tk-ynz4b)" \
  || ok "(CROSSREPOINC) same-repo URL incumbent -> still refused"
grep -q "b-FOREIGNANCH already anchors it by pr_url" "$TMP/err5i6" \
  && ok "(CROSSREPOINC) the real incumbent is still named for an operator" \
  || bad "(CROSSREPOINC) must warn on a same-repo URL incumbent (err: $(cat "$TMP/err5i6"))"

# ...and the NUMBERED incumbent surface must be repository-keyed too. The pr_url guard
# above was qualified by tk-5nxyg finding #2; the `--metadata-field pr_number=<n>`
# lookup that runs BEFORE it was not, so a foreign incumbent that also carries a
# pr_number still blocked a real repair — the same false incumbent, reached one guard
# earlier (review tk-47bij finding #2).
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-CROSSINC|||https://github.com/o/r/pull/745|745|polecat/feat-crossinc|main||||||
b-FOREIGNANCH||pull_request|https://github.com/o/OTHER/pull/745|745|polecat/feat-foreignanch|main|||||codex||
B
run_heal >/dev/null 2>"$TMP/err5i5b" || true
recovered b-CROSSINC \
  && ok "(CROSSREPOINC) a foreign incumbent carrying pr_number too still does not anchor this PR" \
  || bad "(CROSSREPOINC) the NUMBERED incumbent guard must be repository-keyed (err: $(cat "$TMP/err5i5b"))"

# ...and it still FIRES on a same-repo numbered incumbent — including one carrying NO
# pr_url, whose repository therefore cannot be named at all. That is the fail-closed
# direction: an incumbent that cannot be placed in a repository must not be assumed to
# be in a different one, or the repository key would become a way around the guard.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-CROSSINC|||https://github.com/o/r/pull/745|745|polecat/feat-crossinc|main||||||
b-NOURLANCH||pull_request||745|polecat/feat-nourlanch|main|||||codex||
B
run_heal >/dev/null 2>"$TMP/err5i5c" || true
recovered b-CROSSINC \
  && bad "(CROSSREPOINC) an incumbent whose repository is UNKNOWN must still block (fail closed)" \
  || ok "(CROSSREPOINC) numbered incumbent with no pr_url -> repository unknown -> still refused"

# --- Run 5i6b: GHHOST. `<owner>/<repo>` names one repository PER HOST. -------------
# `gh pr view --repo` takes `[HOST/]OWNER/REPO` and fills the host from GH_HOST when it
# is omitted (`gh help environment`). So a hostless `--repo o/r` is not a pinned read at
# all: under a GH_HOST pointing at another GitHub host it reads THAT host's `o/r`, and
# the PR it returns has the same owner/repo and the same head repository as ours. Every
# check keyed on owner/repo alone passes on it. This is the tk-5nxyg hazard one
# component deeper — the expectation came from origin, but the name it was expressed in
# was not specific enough to pin anything (review tk-47bij finding #1).
#
# Arm A: the shape with the least left to catch it — pr_number and NO pr_url, so the URL
# comparison is skipped and only the repository check remains. PR#760 does not exist in
# origin's `o/r`; only the wrongly-hosted one has it.
reset_run
cat > "$TMP/beads" <<'B'
b-GHHOST||||760|polecat/feat-ghhost|||||||
B
: > "$TMP/prs"
echo 'ghe.evil.example' > "$TMP/ghhost"
echo 'polecat/feat-ghhost' > "$TMP/foreignhead"
RC5H=0
run_heal >/dev/null 2>"$TMP/err5h" || RC5H=$?
recovered b-GHHOST \
  && bad "(GHHOST) a GH_HOST-supplied host must not bind this anchor to another host's o/r" \
  || ok "(GHHOST) pr_number-only anchor + foreign GH_HOST -> refused (the read is host-qualified)"
dispatched_for b-GHHOST \
  && bad "(GHHOST) a signoff must never be dispatched off another host's pull request" \
  || ok "(GHHOST) foreign GH_HOST -> no signoff dispatched"
grep -q 'PR#760 view failed' "$TMP/err5h" \
  && ok "(GHHOST) the host-qualified read reports the PR as absent HERE, not as a foreign match" \
  || bad "(GHHOST) must warn that PR#760 is unreadable in this repo (err: $(cat "$TMP/err5h"))"
eq "$RC5H" "0" "(GHHOST) a refused recovery is a stall, not an exposure"

# Arm B, the positive control: GH_HOST still points at the other host, but origin's
# `o/r` really does have a PR#760. The fix must READ THE RIGHT ONE rather than degrade
# into "refuse whenever a host is set". Our #760 is based on `release-7` and the foreign
# one on `main`, and the bead records no target, so the backfilled merged_target names
# which host actually answered.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/prs" <<'P'
760|OPEN|release-7|polecat/feat-ghhost|
P
run_heal >/dev/null 2>"$TMP/err5h2" || true
recovered b-GHHOST \
  && ok "(GHHOST) with the PR present on origin's host the same anchor recovers" \
  || bad "(GHHOST) the refusal above must be the wrong host, not a standing block (err: $(cat "$TMP/err5h2"))"
stamped b-GHHOST merged_target release-7 \
  && ok "(GHHOST) the backfill reads github.com's PR#760 (base release-7), not the GH_HOST default's" \
  || bad "(GHHOST) merged_target must come from origin's host (stamps: $(cat "$TMP/stamps"))"
stamped b-GHHOST merged_target main \
  && bad "(GHHOST) merged_target came from the foreign HOST's PR — the read was not pinned" \
  || ok "(GHHOST) the foreign host's PR never reaches the anchor"

# Arm C: pinning the read is only half of it. A gh that IGNORES `--repo` — a redirect
# after a repository transfer, an older gh, a wrapper — puts the same foreign-host PR
# back on the table, and then only COMPARING the certified URL against the expectation
# catches it. That comparison must therefore keep the host too, or it agrees with a
# stranger on `o/r`.
: > "$TMP/stamps"; : > "$TMP/revmeta"
echo 1 > "$TMP/ignorerepo"
RC5H3=0
run_heal >/dev/null 2>"$TMP/err5h3" || RC5H3=$?
recovered b-GHHOST \
  && bad "(GHHOST) a gh that ignored --repo returned another host's o/r and it was certified" \
  || ok "(GHHOST) unpinned read -> the host-qualified URL comparison still refuses it"
grep -q "in repo 'ghe.evil.example/o/r', not this checkout's 'github.com/o/r'" "$TMP/err5h3" \
  && ok "(GHHOST) the warning names both hosts, so an operator can see which answered" \
  || bad "(GHHOST) must report the foreign HOST in the mismatch (err: $(cat "$TMP/err5h3"))"
eq "$RC5H3" "0" "(GHHOST) refusing an unpinned read is a stall, not an exposure"

# --- Run 5i7: DROPROUTE. The dispatch's LAST write is lost. Two passes. ------------
# `gc.routed_to` is what makes a review claimable, and it is written last. Lose it and
# the bead still exists, still open, still carrying task_kind=review and anchor_bead —
# so the next pass's in-flight lookup finds it and suppresses the replacement dispatch,
# while no polecat can ever claim it. The gate is armed, nothing can raise it, the merge
# is held indefinitely, and the pass reports a signoff as dispatched. The
# over-inclusive dedup is what makes that permanent instead of self-correcting
# (review tk-5nxyg finding #3).
reset_run
cat > "$TMP/beads" <<'B'
b-DROPROUTE||pull_request|https://github.com/o/r/pull/752|752|polecat/feat-droproute|main||||||
B
cat > "$TMP/prs" <<'P'
752|OPEN|main|polecat/feat-droproute|
P
printf 'rev-new-1\tgc.routed_to\n' > "$TMP/stampfail"
RC5I7=0
OUT5I7="$(run_heal 2>"$TMP/err5i7")" || RC5I7=$?
grep -q '^rev-new-1	gc.routed_to	' "$TMP/revmeta" \
  && bad "(DROPROUTE) the fixture must actually drop the routing write" \
  || ok "(DROPROUTE) pass 1: the routing write is lost"
grep -q 'did not record gc.routed_to' "$TMP/err5i7" \
  && ok "(DROPROUTE) pass 1: the unclaimable review is reported, not assumed dispatched" \
  || bad "(DROPROUTE) pass 1 must verify the route it just wrote (err: $(cat "$TMP/err5i7"))"
printf '%s\n' "$OUT5I7" | grep -q '0 signoffs dispatched' \
  && ok "(DROPROUTE) pass 1: a review nobody can claim is not counted as dispatched" \
  || bad "(DROPROUTE) pass 1 summary (got: $OUT5I7)"
eq "$RC5I7" "0" "(DROPROUTE) pass 1: a held merge is a stall, not an exposure"

# Pass 2 with the write-loss lifted and the ledger intact — the state a later idle wake
# actually finds. The stranded review must be RE-ROUTED, not counted as in flight, and
# no twin may be minted.
: > "$TMP/stampfail"
RC5I8=0
OUT5I8="$(run_heal 2>"$TMP/err5i8")" || RC5I8=$?
grep -q '^rev-new-1	gc.routed_to	gc-toolkit/gc-toolkit.polecat-codex$' "$TMP/revmeta" \
  && ok "(DROPROUTE) pass 2: the stranded review is re-routed and becomes claimable" \
  || bad "(DROPROUTE) pass 2 must repair the route (revmeta: $(cat "$TMP/revmeta"))"
eq "$(cat "$TMP/seq")" "1" "(DROPROUTE) pass 2: repaired, not twinned — no second review minted"
printf '%s\n' "$OUT5I8" | grep -q 'STRANDED signoff rev-new-1' \
  && ok "(DROPROUTE) pass 2: the repair is reported for an operator" \
  || bad "(DROPROUTE) pass 2 must report the repair (got: $OUT5I8)"
printf '%s\n' "$OUT5I8" | grep -q '1 signoffs dispatched' \
  && ok "(DROPROUTE) pass 2: the re-routed review counts as the dispatch" \
  || bad "(DROPROUTE) pass 2 summary (got: $OUT5I8)"
eq "$RC5I8" "0" "(DROPROUTE) pass 2: a repaired dispatch exits 0"

# --- Run 5j: LIVEFAIL. A recovered anchor carrying a persisted non-OPEN PR state
#     whose LIVE re-check is unreadable — and whose check_set is EMPTY. -------------
# The re-check exists so a CLOSED-then-REOPENED PR is gated again rather than
# suppressed forever by a stale record (REOPEN, above). This is the other direction:
# `gh` does not answer at all. An unanswered probe must keep the RECORDED verdict —
# treating it as "open again" would arm codex and dispatch a signoff for a PR nobody
# can merge, which is the noise the persisted state exists to prevent. The branch is
# part of what makes the re-check safe under a transient gh failure, so it is pinned
# here (review tk-h1ymf testing gap).
#
# BUT KEEPING THE RECORDED VERDICT IS NOT THE SAME AS LETTING THE MERGE PROCEED
# (review tk-pka2d finding #4). This anchor is VISIBLE (merge_result is stamped and
# durable) and UNGATED (check_set is empty, which merge-skill.sh reads as "no
# gates"), and the recorded MERGED state is a memory of an earlier pass's read — a PR
# recorded MERGED or CLOSED can have been reopened since. merge-skill.sh runs later in
# this same patrol pass, in its own gh context, and may well be able to read what this
# pass could not. So the exposure is identical to INERTLIVEFAIL's; only the pass that
# created it differs, and provenance is not a gate. This used to exit 0 — deferring —
# on the reasoning that an earlier pass's recovery is the status quo. That reasoning
# holds only for a GATED anchor (Run 5j2 below), which cannot merge ungated no matter
# who is confused about it.
reset_run
cat > "$TMP/beads" <<'B'
b-LIVEFAIL||pull_request|https://github.com/o/r/pull/721|721|polecat/feat-livefail|main||||||
B
: > "$TMP/prs"   # PR#721 is absent -> `gh pr view` fails -> the live state is unreadable
printf 'b-LIVEFAIL\tmerge_result_healed\tpull_request\nb-LIVEFAIL\tmerge_result_pr_state\tMERGED\n' > "$TMP/seed"
RC5J=0
run_heal >/dev/null 2>"$TMP/err5j" || RC5J=$?
dispatched_for b-LIVEFAIL \
  && bad "(LIVEFAIL) an unreadable live state must not be read as 'reopened' — no signoff into the void" \
  || ok "(LIVEFAIL) unreadable live state -> no signoff dispatched"
stamped b-LIVEFAIL check_set codex \
  && bad "(LIVEFAIL) no gate may be armed while the PR's state is unknown" \
  || ok "(LIVEFAIL) unreadable live state -> no gate armed"
stamped b-LIVEFAIL merge_result_pr_state OPEN \
  && bad "(LIVEFAIL) the recorded MERGED verdict must NOT be refreshed from an unreadable probe" \
  || ok "(LIVEFAIL) the persisted verdict stands (nothing refreshed from silence)"
eq "$RC5J" "3" \
   "(LIVEFAIL) visible + UNGATED + unconfirmable -> UNSAFE_RC, even though an EARLIER pass recovered it"
grep -q 'UNSAFE — b-LIVEFAIL was restored to visibility on an EARLIER pass' "$TMP/err5j" \
  && ok "(LIVEFAIL) the exposure is named, and names the provenance without depending on it" \
  || bad "(LIVEFAIL) must report the unsafe exposure (err: $(cat "$TMP/err5j"))"

# --- Run 5j2: LIVEFAILGATED. THE CONTRAST, and the reason the hold keys on the
#     EXPOSURE rather than on provenance. -------------------------------------------
# Byte-for-byte Run 5j except that check_set is `codex`. The anchor is equally
# visible, equally unreadable and equally recovered-on-an-earlier-pass — but it is
# GATED, so merge-skill.sh holds it on the unmet check.codex marker no matter what
# this pass could not read. Deferring is safe here, and it is what keeps ONE anchor's
# unreadable state from holding the whole rig's merge queue. Without this case, the
# fix for finding #4 could have been "always UNSAFE", which trades every anchor's
# throughput for one anchor's safety.
reset_run
cat > "$TMP/beads" <<'B'
b-LIVEFAILGATED||pull_request|https://github.com/o/r/pull/722|722|polecat/feat-livefailgated|main|||||codex|
B
: > "$TMP/prs"   # PR#722 absent -> the live state is unreadable, exactly as in 5j
printf 'b-LIVEFAILGATED\tmerge_result_healed\tpull_request\nb-LIVEFAILGATED\tmerge_result_pr_state\tMERGED\n' > "$TMP/seed"
RC5J2=0
run_heal >/dev/null 2>"$TMP/err5j2" || RC5J2=$?
eq "$RC5J2" "0" \
   "(LIVEFAILGATED) the SAME unreadable state on a GATED anchor is a deferral, not an exposure"
dispatched_for b-LIVEFAILGATED \
  && bad "(LIVEFAILGATED) no signoff may be dispatched for a PR nobody can merge" \
  || ok "(LIVEFAILGATED) unreadable live state -> still no signoff dispatched"
grep -q 'live state is unreadable' "$TMP/err5j2" \
  && ok "(LIVEFAILGATED) the unreadable re-check is still reported" \
  || bad "(LIVEFAILGATED) must warn that the live state is unreadable (err: $(cat "$TMP/err5j2"))"
grep -q 'UNSAFE — b-LIVEFAILGATED' "$TMP/err5j2" \
  && bad "(LIVEFAILGATED) a gated anchor must NOT hold the rig's merge queue" \
  || ok "(LIVEFAILGATED) ...and it does not raise UNSAFE: its check_set already gates the merge"

# --- Run 5j3: LIVEFAILNONUM. The OTHER reason an ungated anchor is not an exposure. --
# Byte-for-byte Run 5j — visible, UNGATED, live state unreadable, recovered on an
# earlier pass — except that it records NO pr_number. merge-skill.sh finds its PR by
# number and skips any anchor without one outright, so this anchor cannot be landed
# however empty its check_set is: it is the ordinary stall an operator repairs, not the
# ungated-merge window. Holding the whole rig's queue for a merge that structurally
# cannot happen would trade every anchor's throughput for nothing — so the hold is
# owed to the EXPOSURE, and an anchor merge-skill cannot even find is not one.
reset_run
cat > "$TMP/beads" <<'B'
b-LIVEFAILNONUM||pull_request|https://github.com/o/r/pull/757||polecat/feat-livefailnonum|main||||||
B
: > "$TMP/prs"
printf 'b-LIVEFAILNONUM\tmerge_result_healed\tpull_request\nb-LIVEFAILNONUM\tmerge_result_pr_state\tMERGED\n' > "$TMP/seed"
RC5J3=0
run_heal >/dev/null 2>"$TMP/err5j3" || RC5J3=$?
eq "$RC5J3" "0" \
   "(LIVEFAILNONUM) an UNGATED anchor with no pr_number is a stall, not an exposure -> exit 0"
grep -q 'UNSAFE — b-LIVEFAILNONUM' "$TMP/err5j3" \
  && bad "(LIVEFAILNONUM) an anchor merge-skill cannot even find must not hold the queue" \
  || ok "(LIVEFAILNONUM) ...and it raises no UNSAFE hold"
grep -q 'records no pr_number, so merge-skill cannot land it at all' "$TMP/err5j3" \
  && ok "(LIVEFAILNONUM) the deferral says WHY it is safe, not just that it deferred" \
  || bad "(LIVEFAILNONUM) must name the missing pr_number (err: $(cat "$TMP/err5j3"))"

# --- Run 6: UNGATED. merge_result sticks (the anchor is EXPOSED to merge-skill) but
#     the check_set stamp does NOT. Phase 0 has actively created the ungated-merge
#     window, so the pass must HOLD the merge (review tk-ej3wq finding #2).
reset_run
cat > "$TMP/beads" <<'B'
b-UNGATED|||https://github.com/o/r/pull/731||polecat/feat-ungated|||||||
B
cat > "$TMP/prs" <<'P'
731|OPEN|main|polecat/feat-ungated|
P
printf 'b-UNGATED\tcheck_set\n' > "$TMP/stampfail"
RC6=0
OUT6="$(run_heal 2>"$TMP/err6")" || RC6=$?
recovered b-UNGATED \
  && ok "(UNGATED) the anchor was made visible to merge-skill" \
  || bad "(UNGATED) merge_result must persist for this case to matter"
dispatched_for b-UNGATED \
  && bad "(UNGATED) an unstamped anchor must NOT dispatch a signoff (fail-closed)" \
  || ok "(UNGATED) failed check_set stamp -> no signoff dispatched"
eq "$RC6" "3" "(UNGATED) a visible-but-ungated anchor makes the pass exit UNSAFE rc=3"
grep -q 'still UNGATED' "$TMP/err6" \
  && ok "(UNGATED) the exposure is named in the warning" \
  || bad "(UNGATED) must warn that the anchor is ungated (err: $(cat "$TMP/err6"))"
grep -q '1 anchor(s) are visible to merge-skill but still ungated' "$TMP/err6" \
  && ok "(UNGATED) exactly one anchor is counted (the two checks do not double-count)" \
  || bad "(UNGATED) unsafe count must be 1 (err: $(cat "$TMP/err6"))"
printf '%s\n' "$OUT6" | grep -q '1 anchor(s) restored to visible gating' \
  && ok "(UNGATED) the exposure really happened (the anchor was restored)" \
  || bad "(UNGATED) recovery count (got: $OUT6)"

# --- Run 7: ENUMFAIL. merge_result sticks, but the phase-1 gating enumeration
#     returns NOTHING. Exiting 0 as "no gating anchors" would hand a freshly visible,
#     possibly ungated anchor straight to merge-skill.sh in this same pass.
reset_run
cat > "$TMP/beads" <<'B'
b-ENUMFAIL|||https://github.com/o/r/pull/732||polecat/feat-enumfail|||||||
B
cat > "$TMP/prs" <<'P'
732|OPEN|main|polecat/feat-enumfail|
P
echo 1 > "$TMP/enumfail"
RC7=0
OUT7="$(run_heal 2>"$TMP/err7")" || RC7=$?
recovered b-ENUMFAIL \
  && ok "(ENUMFAIL) the anchor was made visible to merge-skill" \
  || bad "(ENUMFAIL) merge_result must persist for this case to matter"
eq "$RC7" "3" "(ENUMFAIL) an empty enumeration after a recovery exits UNSAFE rc=3, not 0"
grep -q 'gating enumeration returned NOTHING' "$TMP/err7" \
  && ok "(ENUMFAIL) the contradiction is named in the warning" \
  || bad "(ENUMFAIL) must warn about the empty enumeration (err: $(cat "$TMP/err7"))"
printf '%s\n' "$OUT7" | grep -q 'no gating anchors' \
  && bad "(ENUMFAIL) must NOT report the benign 'no gating anchors' after a recovery" \
  || ok "(ENUMFAIL) the benign no-anchors exit is not taken"

# --- Run 7b: UNREACHED. The enumeration is not empty — it just drops THIS anchor. ---
# ENUMFAIL above covers the total failure, which the empty-ROWS guard catches. The
# partial one is the dangerous shape, because it looks like a normal pass: other anchors
# enumerate, the summary reads healthy, and the recovered anchor is simply absent. And
# the post-loop sweep could not see it, because it inferred reach from a non-empty
# check_set — which is exactly what this anchor has (the CSNORMAL shape: the damage
# dropped merge_result and left check_set reading `codex`). Phase 0 exposed it, nothing
# dispatched a signoff, and merge-skill holds forever on a gate nothing can raise.
# So reach is now VERIFIED, not inferred (review tk-47bij finding #3).
reset_run
cat > "$TMP/beads" <<'B'
b-DECOY||pull_request|https://github.com/o/r/pull/770|770|polecat/feat-decoy|main|||||codex||
b-UNREACHED|||https://github.com/o/r/pull/771|771|polecat/feat-unreached|main|||||codex||
B
cat > "$TMP/prs" <<'P'
770|OPEN|main|polecat/feat-decoy|
771|OPEN|main|polecat/feat-unreached|
P
echo 'b-UNREACHED' > "$TMP/enumdrop"
RC7B=0
run_heal >/dev/null 2>"$TMP/err7b" || RC7B=$?
recovered b-UNREACHED \
  && ok "(UNREACHED) phase 0 still recovers it — the drop is in the gating scan" \
  || bad "(UNREACHED) fixture must recover (err: $(cat "$TMP/err7b"))"
dispatched_for b-UNREACHED \
  && bad "(UNREACHED) fixture is wrong: the dropped anchor must NOT have been dispatched" \
  || ok "(UNREACHED) the dropped anchor got no signoff, as the defect requires"
grep -q "b-UNREACHED was restored to visibility this pass but the gating enumeration never reached it" "$TMP/err7b" \
  && ok "(UNREACHED) an unreached recovered anchor is REPORTED, not silently passed" \
  || bad "(UNREACHED) must warn that phase 1 never reached it (err: $(cat "$TMP/err7b"))"
eq "$RC7B" "0" "(UNREACHED) a gated-but-unreached anchor HOLDS on its own gate — not the whole queue"

# ...and when the unreached anchor is also UNGATED, it IS the ungated-merge condition:
# merge-skill reads an empty check_set as "no gates" and lands it un-reviewed this pass.
# Same drop, opposite disposition — which is why reach and gatedness are checked as two
# questions rather than one.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-DECOY||pull_request|https://github.com/o/r/pull/770|770|polecat/feat-decoy|main|||||codex||
b-UNREACHED|||https://github.com/o/r/pull/771|771|polecat/feat-unreached|main||||||
B
RC7C=0
run_heal >/dev/null 2>"$TMP/err7c" || RC7C=$?
eq "$RC7C" "3" "(UNREACHED) unreached AND ungated -> UNSAFE rc=3, the merge is held"
grep -q "STILL UNGATED .*never reached it" "$TMP/err7c" \
  && ok "(UNREACHED) the warning says both what is wrong and why it was missed" \
  || bad "(UNREACHED) the ungated warning must name the unreached enumeration (err: $(cat "$TMP/err7c"))"

# --- Run 7d: PAGE. The gating enumeration must not stop at a page. -----------------
# The phase-1 scan took the first 200 anchors. That was defensible while every anchor it
# enumerated was ALREADY visible — one past the cap was merely deferred to a later pass.
# Phase 0 broke that: an anchor it recovers is visible to merge-skill NOW, and the ONLY
# enumeration that will ever dispatch its signoff is this one, in this pass. Past the
# cap, it is a live anchor with an armed gate nothing was dispatched to raise, no
# escalation, and — carrying `codex` already — nothing in the post-loop sweep to notice.
# 200 already-normalized anchors ahead of it put the recovered one past that boundary
# (review tk-47bij finding #3).
reset_run
: > "$TMP/beads"; : > "$TMP/prs"
i=1
while [ "$i" -le 200 ]; do
  printf 'f-%03d||pull_request||9%03d|polecat/f-%03d|main|||||codex||\n' "$i" "$i" "$i" >> "$TMP/beads"
  i=$((i + 1))
done
# check_set already reads `codex` — the CSNORMAL shape, and the one that makes the page
# boundary SILENT rather than merely slow: the post-loop sweep saw a gated anchor and
# asked no further question, so nothing warned, nothing escalated, and the pass exited 0
# reporting a healthy queue while this PR was held on a gate nobody had dispatched for.
printf 'b-PAGE|||https://github.com/o/r/pull/780|780|polecat/feat-page|main|||||codex||\n' >> "$TMP/beads"
printf '780|OPEN|main|polecat/feat-page|\n' > "$TMP/prs"
RC7D=0
run_heal >/dev/null 2>"$TMP/err7d" || RC7D=$?
recovered b-PAGE \
  && ok "(PAGE) the unbounded recovery scan finds the candidate behind 200 anchors" \
  || bad "(PAGE) fixture must recover (err: $(cat "$TMP/err7d"))"
dispatched_for b-PAGE \
  && ok "(PAGE) the gating enumeration reaches anchor 201 and dispatches its signoff" \
  || bad "(PAGE) a recovered anchor past a 200-row page got NO signoff (err: $(cat "$TMP/err7d"))"
grep -q 'never reached it' "$TMP/err7d" \
  && bad "(PAGE) the recovered anchor was not reached by the gating enumeration" \
  || ok "(PAGE) no unreached warning — the enumeration is complete, not capped"
eq "$RC7D" "0" "(PAGE) a fully-enumerated pass exits 0"

# --- Run 8: a pass that recovers NOTHING still exits 0 on an empty enumeration. ---
reset_run
cat > "$TMP/beads" <<'B'
b-NOTHING||pull_request|https://github.com/o/r/pull/733|733|polecat/feat-nothing|main|||||none||
B
cat > "$TMP/prs" <<'P'
733|OPEN|main|polecat/feat-nothing|
P
echo 1 > "$TMP/enumfail"
RC8=0
OUT8="$(run_heal 2>"$TMP/err8")" || RC8=$?
eq "$RC8" "0" "(NOTHING) an empty enumeration with NO recovery is still the benign exit"
printf '%s\n' "$OUT8" | grep -q 'no gating anchors' \
  && ok "(NOTHING) reports 'no gating anchors'" || bad "(NOTHING) summary (got: $OUT8)"

# --- Run 9: DUPCROSSREPO. The duplicate-candidate key is REPOSITORY **and** number. -
# A pull number is unique only within a repository and this city's ledger spans rigs with
# different ones, so a guard keyed on the bare number reads a damaged candidate for
# `o/OTHER#745` as a rival claimant to THIS repo's `#745`. This guard runs FIRST — before
# `crepo` is derived and before the repository-aware incumbent checks that would have told
# the two apart — so it skips BOTH, every pass, and the real anchor's recovery is blocked
# indefinitely by a bead from another repository: the same false-incumbent stall tk-5nxyg
# and tk-47bij closed on the two incumbent surfaces, still open on this one
# (review tk-jza6h finding #1).
reset_run
cat > "$TMP/beads" <<'B'
b-DUPMINE|||https://github.com/o/r/pull/745|745|polecat/feat-dupmine|main||||||
b-DUPTHEIRS|||https://github.com/o/OTHER/pull/745|745|polecat/feat-duptheirs|main||||||
B
cat > "$TMP/prs" <<'P'
745|OPEN|main|polecat/feat-dupmine|
P
run_heal >/dev/null 2>"$TMP/err9" || true
recovered b-DUPMINE \
  && ok "(DUPCROSSREPO) another repository's damaged #745 does not make THIS #745 ambiguous" \
  || bad "(DUPCROSSREPO) a cross-repo same-number candidate must not block recovery (err: $(cat "$TMP/err9"))"
recovered b-DUPTHEIRS \
  && bad "(DUPCROSSREPO) the foreign candidate must NOT be bound to this origin's PR" \
  || ok "(DUPCROSSREPO) the foreign candidate is still refused by PR certification"
grep -q 'MULTIPLE merge_result-less candidates' "$TMP/err9" \
  && bad "(DUPCROSSREPO) reported a false ambiguity between two repositories" \
  || ok "(DUPCROSSREPO) no false-ambiguity warning across repositories"

# ...and the guard still FIRES when both candidates really do name the SAME repository's
# PR — proving the pass above came from the repository half of the key and not from a
# guard that stopped guarding.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-DUPMINE|||https://github.com/o/r/pull/745|745|polecat/feat-dupmine|main||||||
b-DUPMINE2|||https://github.com/o/r/pull/745|745|polecat/feat-dupmine2|main||||||
B
run_heal >/dev/null 2>"$TMP/err9b" || true
recovered b-DUPMINE \
  && bad "(DUPCROSSREPO) two candidates for the SAME repository's #745 must both be skipped" \
  || ok "(DUPCROSSREPO) same-repository duplicates -> neither is promoted to anchor"
recovered b-DUPMINE2 \
  && bad "(DUPCROSSREPO) the second same-repository candidate must be skipped too" \
  || ok "(DUPCROSSREPO) ...including the second one"
grep -q "PR#745 in 'github.com/o/r' has MULTIPLE merge_result-less candidates" "$TMP/err9b" \
  && ok "(DUPCROSSREPO) the ambiguity is reported WITH the repository it is in" \
  || bad "(DUPCROSSREPO) must warn naming the repository (err: $(cat "$TMP/err9b"))"

# ...and a candidate carrying pr_number but NO pr_url of its own is keyed on the
# repository certification would REQUIRE of it — this checkout's origin — not on the
# wildcard. So a foreign-URL twin stays distinct from it...
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-DUPNOURL||||745|polecat/feat-dupnourl|main||||||
b-DUPTHEIRS|||https://github.com/o/OTHER/pull/745|745|polecat/feat-duptheirs|main||||||
B
cat > "$TMP/prs" <<'P'
745|OPEN|main|polecat/feat-dupnourl|
P
run_heal >/dev/null 2>"$TMP/err9c" || true
recovered b-DUPNOURL \
  && ok "(DUPCROSSREPO) a pr_number-only candidate keys on origin, so a foreign-URL twin does not collide with it" \
  || bad "(DUPCROSSREPO) an origin-keyed candidate must still recover (err: $(cat "$TMP/err9c"))"

# ...while a twin in THIS repository still collides with it. The origin fallback is the
# fail-closed direction, not a way around the guard.
: > "$TMP/stamps"; : > "$TMP/revmeta"
cat > "$TMP/beads" <<'B'
b-DUPNOURL||||745|polecat/feat-dupnourl|main||||||
b-DUPMINE|||https://github.com/o/r/pull/745|745|polecat/feat-dupmine|main||||||
B
run_heal >/dev/null 2>"$TMP/err9d" || true
recovered b-DUPNOURL \
  && bad "(DUPCROSSREPO) a pr_number-only candidate must still collide with THIS repo's same number" \
  || ok "(DUPCROSSREPO) pr_number-only vs same-repo URL twin -> still ambiguous, neither promoted"

# --- Run 10: INFLIGHTID. The in-flight dedup VALIDATES the match it stops on. --------
# `inflight_for` asks three surfaces and two of them — `pr_number` and `branch` — name a
# bead by a field that is not this anchor's identity. A match from one that is not about
# this anchor can never raise this anchor's gate, so suppressing the dispatch on it is not
# a delay but the permanent hold: the gate stays armed and unmeetable, the merge is held
# forever, and the pass reports a signoff already in flight (review tk-jza6h finding #2).
# So the EXACT surface (`anchor_bead`) is asked first and trusted outright, a match from a
# broad surface must survive validation, and a rejected one does not end the search.
# Anything unresolved still counts as in flight — only a POSITIVE disagreement clears it.
#
# The anchor here is already VISIBLE (merge_result=pull_request) carrying no check_set, so
# phase 1 heals its gate and must then dispatch its signoff; phase 0 is not involved. Each
# rival below is excluded from the phase-0 candidate set by its own metadata (routed,
# task_kind, anchor_bead), so it is purely an in-flight fixture.
inflight_fixture() { # <rival-bead-row>
  reset_run
  { printf 'b-INF||pull_request|https://github.com/o/r/pull/750|750|polecat/feat-inf|main||||||\n'
    printf '%s\n' "$1"; } > "$TMP/beads"
  printf '750|OPEN|main|polecat/feat-inf|\n' > "$TMP/prs"
  run_heal >/dev/null 2>"$TMP/errinf" || true
}

# (A) A LIVE bead for ANOTHER repository's #750. Its own anchor holds its own merge;
# nothing about it can ever raise this one's gate.
inflight_fixture 'b-FOREIGNLIVE|||https://github.com/o/OTHER/pull/750|750|polecat/feat-foreignlive|main||||pool/polecat|||'
dispatched_for b-INF \
  && ok "(INFLIGHTID) another repository's #750 does not count as this anchor's signoff" \
  || bad "(INFLIGHTID) a foreign same-number bead suppressed the dispatch (err: $(cat "$TMP/errinf"))"

# (B) A review that names NO anchor, routed nowhere, claimed by nobody — the shape a lost
# `anchor_bead` write leaves behind. `repair_review_routing` will not route it (it cannot
# be attributed to any anchor) and no polecat can claim it unrouted, so it is inert, not in
# flight. It carries this anchor's number AND its branch, so BOTH broad surfaces surface it
# and both must reject it.
inflight_fixture 'b-LOSTREV|||https://github.com/o/r/pull/750|750|polecat/feat-inf|main||review||||'
dispatched_for b-INF \
  && ok "(INFLIGHTID) an unattributable review is inert, not in flight — a fresh signoff goes out" \
  || bad "(INFLIGHTID) a review with no anchor_bead held the gate forever (err: $(cat "$TMP/errinf"))"

# (C) A review that names ANOTHER anchor: positively not about this one.
inflight_fixture 'b-OTHERSREV|||https://github.com/o/r/pull/750|750|polecat/feat-inf|main|b-SOMEONE|review||||'
dispatched_for b-INF \
  && ok "(INFLIGHTID) a review naming ANOTHER anchor does not hold this one" \
  || bad "(INFLIGHTID) another anchor's review suppressed the dispatch (err: $(cat "$TMP/errinf"))"

# (D) ...and the dedup still HOLDS on a rival that is plausibly this anchor's own work:
# same repository, unattributed but ROUTED — a rework child, whose hand-back re-dispatches
# the review. Proof the arms above came from a positive disagreement and not from a dedup
# that stopped deduping. `gc bd create` is the observable: a dispatch mints a review bead.
inflight_fixture 'b-REWORK|||https://github.com/o/r/pull/750|750|polecat/feat-inf|main||||pool/polecat|||'
eq "$(cat "$TMP/seq")" "0" "(INFLIGHTID) a live same-repository rework child still holds the dispatch"

# (E) ...and a rival whose repository cannot be named still holds: `?` matches everything,
# the same fail-closed wildcard the incumbent guards use. Not-shown-to-be-different is not
# shown to be different.
inflight_fixture 'b-NOURLREWORK||||750|polecat/feat-inf|main||||pool/polecat|||'
eq "$(cat "$TMP/seq")" "0" "(INFLIGHTID) a rival whose repository cannot be named still holds (fail closed)"

# (F) ...and the EXACT surface is asked FIRST and trusted outright: a review NAMING this
# anchor holds it, with no identity question left to get wrong.
reset_run
printf 'b-INF||pull_request|https://github.com/o/r/pull/750|750|polecat/feat-inf|main||||||\n' > "$TMP/beads"
printf '750|OPEN|main|polecat/feat-inf|\n' > "$TMP/prs"
{ printf 'rev-live\tanchor_bead\tb-INF\n'
  printf 'rev-live\ttask_kind\treview\n'
  printf 'rev-live\tgc.routed_to\tpool/codex\n'; } >> "$TMP/revmeta"
run_heal >/dev/null 2>"$TMP/errinf6" || true
eq "$(cat "$TMP/seq")" "0" "(INFLIGHTID) a routed review naming THIS anchor holds the dispatch"

# --- Run 11: RCPAYLOAD. A read can FAIL and still write a well-formed array. --------
# Every fail-closed guard above was written against ONE failure shape: a read that
# printed nothing. Each validated the payload (`type == "array"`) and never the
# command's own verdict — so a read that DIED AFTER EMITTING, or a page that came back
# short, arrives as a well-formed EMPTY array and is accepted as a complete scan. "[]"
# is precisely the value each caller reads as a positive fact: no duplicate, no
# incumbent, nothing in flight, no anchors at all. So the same fixtures that pin each
# guard are re-run with this shape; every one must reach the SAME refusal
# (review tk-thvbq finding #1).

# (RCPAYLOAD-scan) the recovery scan. Same fixture as SCANFAIL: b-SCANA is reachable
# only through the pr_url scan and b-SCANB only through pr_number, and they name the
# same PR. A short pr_url scan hides the ambiguity and b-SCANB is promoted to anchor.
reset_run
cat > "$TMP/beads" <<'B'
b-SCANA|||https://github.com/o/r/pull/750||polecat/feat-scana|main||||||
b-SCANB||||750|polecat/feat-scanb|main||||||
B
printf '750|OPEN|main|polecat/feat-scanb|\n' > "$TMP/prs"
echo 'scan-pr_url' > "$TMP/rcpayload"
run_heal >/dev/null 2>"$TMP/err11" || true
if recovered b-SCANA || recovered b-SCANB; then
  bad "(RCPAYLOAD-scan) a scan that failed WITH an array payload was accepted as a complete set"
else
  ok "(RCPAYLOAD-scan) a non-zero exit with an array payload still skips the recovery phase"
fi
grep -q "recovery scan did not return a readable result" "$TMP/err11" \
  && ok "(RCPAYLOAD-scan) the unreadable scan is reported" \
  || bad "(RCPAYLOAD-scan) must warn about the unreadable scan (err: $(cat "$TMP/err11"))"

# (RCPAYLOAD-lookup) the incumbent-anchor lookup by pr_number. Reading a short answer
# as "no incumbent" promotes a child to anchor and mints the second anchor
# one-anchor-per-PR exists to prevent.
reset_run
printf 'b-INCFAIL2|||https://github.com/o/r/pull/719|719|polecat/feat-incfail2|main||||||\n' > "$TMP/beads"
printf '719|OPEN|main|polecat/feat-incfail2|\n' > "$TMP/prs"
echo 'lookup-719' > "$TMP/rcpayload"
run_heal >/dev/null 2>"$TMP/err11b" || true
recovered b-INCFAIL2 \
  && bad "(RCPAYLOAD-lookup) an incumbent lookup that failed WITH a payload must not read as 'no incumbent'" \
  || ok "(RCPAYLOAD-lookup) non-zero exit + array payload -> candidate skipped, not promoted"
grep -q 'incumbent-anchor lookup for PR#719 failed' "$TMP/err11b" \
  && ok "(RCPAYLOAD-lookup) the unreadable lookup is warned about" \
  || bad "(RCPAYLOAD-lookup) must warn on the unreadable lookup (err: $(cat "$TMP/err11b"))"
# Control: the same fixture with a readable ledger recovers, so the refusal above is
# the failed read and not some standing block.
: > "$TMP/rcpayload"; : > "$TMP/stamps"; : > "$TMP/revmeta"
run_heal >/dev/null 2>&1 || true
recovered b-INCFAIL2 \
  && ok "(RCPAYLOAD-lookup) control: a readable ledger recovers the same bead" \
  || bad "(RCPAYLOAD-lookup) control must recover (the refusal must be the failed read)"

# (RCPAYLOAD-incscan) the other incumbent surface, scanned by pr_url.
reset_run
printf 'b-INCURL2|||https://github.com/o/r/pull/746|746|polecat/feat-incurl2|main||||||\n' > "$TMP/beads"
printf '746|OPEN|main|polecat/feat-incurl2|\n' > "$TMP/prs"
echo 'incscan' > "$TMP/rcpayload"
run_heal >/dev/null 2>"$TMP/err11c" || true
recovered b-INCURL2 \
  && bad "(RCPAYLOAD-incscan) a pr_url incumbent scan that failed WITH a payload must not read as absence" \
  || ok "(RCPAYLOAD-incscan) non-zero exit + array payload -> candidate skipped, not promoted"
grep -q 'incumbent-anchor scan by pr_url failed' "$TMP/err11c" \
  && ok "(RCPAYLOAD-incscan) the unreadable scan is warned about" \
  || bad "(RCPAYLOAD-incscan) must warn on the unreadable pr_url scan (err: $(cat "$TMP/err11c"))"

# (RCPAYLOAD-enum) the phase-1 gating enumeration — the surface merge-skill.sh runs
# behind. A short read leaves every anchor it did not see un-normalized, and an
# un-normalized (empty) check_set is exactly what merge-skill reads as "no gates".
# Unlike ENUMFAIL this needs no recovery to be unsafe: the exposure is that this pass
# cannot show ANY visible anchor was gated, so it must hold the merge for the pass.
reset_run
printf 'b-RCENUM||pull_request|https://github.com/o/r/pull/733|733|polecat/feat-rcenum|main|||||codex|\n' > "$TMP/beads"
printf '733|OPEN|main|polecat/feat-rcenum|\n' > "$TMP/prs"
echo 'enum-pull_request' > "$TMP/rcpayload"
RC11D=0
OUT11D="$(run_heal 2>"$TMP/err11d")" || RC11D=$?
eq "$RC11D" "3" "(RCPAYLOAD-enum) an unreadable gating enumeration exits UNSAFE rc=3 (merge held)"
grep -q 'gating enumeration did not return a readable result' "$TMP/err11d" \
  && ok "(RCPAYLOAD-enum) the unreadable enumeration is reported" \
  || bad "(RCPAYLOAD-enum) must warn about the unreadable enumeration (err: $(cat "$TMP/err11d"))"
printf '%s\n' "$OUT11D" | grep -q 'no gating anchors' \
  && bad "(RCPAYLOAD-enum) must NOT report the benign 'no gating anchors' on an unreadable scan (got: $OUT11D)" \
  || ok "(RCPAYLOAD-enum) the benign no-anchors exit is not taken"
# Control: readable enumeration -> the anchor is gated normally and the pass exits 0.
: > "$TMP/rcpayload"; : > "$TMP/stamps"; : > "$TMP/revmeta"
RC11E=0
run_heal >/dev/null 2>&1 || RC11E=$?
eq "$RC11E" "0" "(RCPAYLOAD-enum) control: a readable enumeration exits 0"

# (RCPAYLOAD-inflight) the in-flight signoff dedup. A short read reads as "nothing in
# flight" and dispatches a SECOND claimable review for one gate — the twin this dedup
# exists to prevent. Holding costs a pass; the gate is already armed, so the merge is
# held either way.
reset_run
printf 'b-RCINF||pull_request|https://github.com/o/r/pull/751|751|polecat/feat-rcinf|main||||||\n' > "$TMP/beads"
printf '751|OPEN|main|polecat/feat-rcinf|\n' > "$TMP/prs"
echo 'inflight-anchor_bead' > "$TMP/rcpayload"
run_heal >/dev/null 2>"$TMP/err11f" || true
eq "$(cat "$TMP/seq")" "0" \
   "(RCPAYLOAD-inflight) an unreadable in-flight lookup dispatches NOTHING (no twin signoff)"
grep -q 'in-flight signoff lookup failed' "$TMP/err11f" \
  && ok "(RCPAYLOAD-inflight) the unreadable lookup is warned about" \
  || bad "(RCPAYLOAD-inflight) must warn on the unreadable in-flight lookup (err: $(cat "$TMP/err11f"))"
# Control: with the ledger readable and nothing in flight, the signoff IS dispatched —
# so the silence above is the failed read, not a dedup that stopped dispatching.
: > "$TMP/rcpayload"; : > "$TMP/stamps"; : > "$TMP/revmeta"; echo 0 > "$TMP/seq"
run_heal >/dev/null 2>&1 || true
[ "$(cat "$TMP/seq")" != "0" ] \
  && ok "(RCPAYLOAD-inflight) control: a readable ledger with nothing in flight dispatches the signoff" \
  || bad "(RCPAYLOAD-inflight) control must dispatch (the silence must be the failed read)"

# --- Run 11b: OBJPAYLOAD. The mirror shape — a read that SUCCEEDS (exit 0) while
#     answering with a JSON ERROR OBJECT instead of the array it was asked for. ------
# bd_list_read has three guards, and Run 11 above exercises the first two: the exit
# status, and output-at-all. This shape defeats BOTH — it exits 0 and it writes a
# well-formed JSON document — so only the third, `type == "array"`, can see it. That
# guard existed but nothing pinned it, so deleting it broke no test while re-opening
# every hole Run 11 closes (review tk-pka2d, non-blocking note).
#
# An object is not harmlessly empty, either: `.[]` iterates a JSON object's VALUES,
# so an error payload whose values happened to be bead-shaped would flow into the
# callers as a bead list. Each surface is therefore pinned on its own, against the
# same fixtures Run 11 uses, and each must reach the SAME refusal.

# (OBJPAYLOAD-scan) the recovery scan.
reset_run
cat > "$TMP/beads" <<'B'
b-OSCANA|||https://github.com/o/r/pull/752||polecat/feat-oscana|main||||||
b-OSCANB||||752|polecat/feat-oscanb|main||||||
B
printf '752|OPEN|main|polecat/feat-oscanb|\n' > "$TMP/prs"
echo 'scan-pr_url' > "$TMP/objpayload"
run_heal >/dev/null 2>"$TMP/err11g" || true
if recovered b-OSCANA || recovered b-OSCANB; then
  bad "(OBJPAYLOAD-scan) an rc=0 JSON error OBJECT was accepted as a complete candidate set"
else
  ok "(OBJPAYLOAD-scan) rc=0 + a non-array payload still skips the recovery phase"
fi
grep -q "recovery scan did not return a readable result" "$TMP/err11g" \
  && ok "(OBJPAYLOAD-scan) the unreadable scan is reported" \
  || bad "(OBJPAYLOAD-scan) must warn about the unreadable scan (err: $(cat "$TMP/err11g"))"

# (OBJPAYLOAD-lookup) the incumbent-anchor lookup by pr_number.
reset_run
printf 'b-OINCFAIL|||https://github.com/o/r/pull/753|753|polecat/feat-oincfail|main||||||\n' > "$TMP/beads"
printf '753|OPEN|main|polecat/feat-oincfail|\n' > "$TMP/prs"
echo 'lookup-753' > "$TMP/objpayload"
run_heal >/dev/null 2>"$TMP/err11h" || true
recovered b-OINCFAIL \
  && bad "(OBJPAYLOAD-lookup) an rc=0 object payload must not read as 'no incumbent'" \
  || ok "(OBJPAYLOAD-lookup) rc=0 + non-array payload -> candidate skipped, not promoted"
grep -q 'incumbent-anchor lookup for PR#753 failed' "$TMP/err11h" \
  && ok "(OBJPAYLOAD-lookup) the unreadable lookup is warned about" \
  || bad "(OBJPAYLOAD-lookup) must warn on the unreadable lookup (err: $(cat "$TMP/err11h"))"
# Control: the same fixture with a readable ledger recovers, so the refusal above is
# the payload shape and not some standing block.
: > "$TMP/objpayload"; : > "$TMP/stamps"; : > "$TMP/revmeta"
run_heal >/dev/null 2>&1 || true
recovered b-OINCFAIL \
  && ok "(OBJPAYLOAD-lookup) control: a readable ledger recovers the same bead" \
  || bad "(OBJPAYLOAD-lookup) control must recover (the refusal must be the payload shape)"

# (OBJPAYLOAD-incscan) the other incumbent surface, scanned by pr_url.
reset_run
printf 'b-OINCURL|||https://github.com/o/r/pull/754|754|polecat/feat-oincurl|main||||||\n' > "$TMP/beads"
printf '754|OPEN|main|polecat/feat-oincurl|\n' > "$TMP/prs"
echo 'incscan' > "$TMP/objpayload"
run_heal >/dev/null 2>"$TMP/err11i" || true
recovered b-OINCURL \
  && bad "(OBJPAYLOAD-incscan) an rc=0 object payload must not read as absence" \
  || ok "(OBJPAYLOAD-incscan) rc=0 + non-array payload -> candidate skipped, not promoted"
grep -q 'incumbent-anchor scan by pr_url failed' "$TMP/err11i" \
  && ok "(OBJPAYLOAD-incscan) the unreadable scan is warned about" \
  || bad "(OBJPAYLOAD-incscan) must warn on the unreadable pr_url scan (err: $(cat "$TMP/err11i"))"

# (OBJPAYLOAD-enum) the phase-1 gating enumeration — the surface merge-skill.sh runs
# behind, and the one whose short read lets an ungated anchor through.
reset_run
printf 'b-OENUM||pull_request|https://github.com/o/r/pull/755|755|polecat/feat-oenum|main|||||codex|\n' > "$TMP/beads"
printf '755|OPEN|main|polecat/feat-oenum|\n' > "$TMP/prs"
echo 'enum-pull_request' > "$TMP/objpayload"
RC11J=0
OUT11J="$(run_heal 2>"$TMP/err11j")" || RC11J=$?
eq "$RC11J" "3" "(OBJPAYLOAD-enum) an rc=0 object payload on the gating enumeration exits UNSAFE rc=3"
grep -q 'gating enumeration did not return a readable result' "$TMP/err11j" \
  && ok "(OBJPAYLOAD-enum) the unreadable enumeration is reported" \
  || bad "(OBJPAYLOAD-enum) must warn about the unreadable enumeration (err: $(cat "$TMP/err11j"))"
printf '%s\n' "$OUT11J" | grep -q 'no gating anchors' \
  && bad "(OBJPAYLOAD-enum) must NOT report the benign 'no gating anchors' (got: $OUT11J)" \
  || ok "(OBJPAYLOAD-enum) the benign no-anchors exit is not taken"

# (OBJPAYLOAD-inflight) the in-flight signoff dedup.
reset_run
printf 'b-OINF||pull_request|https://github.com/o/r/pull/756|756|polecat/feat-oinf|main||||||\n' > "$TMP/beads"
printf '756|OPEN|main|polecat/feat-oinf|\n' > "$TMP/prs"
echo 'inflight-anchor_bead' > "$TMP/objpayload"
run_heal >/dev/null 2>"$TMP/err11k" || true
eq "$(cat "$TMP/seq")" "0" \
   "(OBJPAYLOAD-inflight) an rc=0 object payload dispatches NOTHING (no twin signoff)"
grep -q 'in-flight signoff lookup failed' "$TMP/err11k" \
  && ok "(OBJPAYLOAD-inflight) the unreadable lookup is warned about" \
  || bad "(OBJPAYLOAD-inflight) must warn on the unreadable in-flight lookup (err: $(cat "$TMP/err11k"))"

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
