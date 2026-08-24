#!/usr/bin/env bash
# Pack doctor check: a CLOSED bead never claims work that has not landed.
#
# THE INVARIANT (docs/component-model.md §3, I5). "No bead is closed while the
# work it represents is unlanded." Under the close-on-land contract (#163)
# `closed` MEANS landed — that is the whole reason the refinery, not the
# polecat, owns the close. A bead closed over an OPEN pull request therefore
# spells a fact that is not true, and it spells it in the one field every
# downstream reader trusts.
#
# WHY THAT IS WORSE THAN AN ORDINARY STALL. merge-skill.sh, pre-open-resolve.sh,
# reconcile-merged-prs.sh's per-anchor pass and check-set-heal.sh's phase 0 all
# enumerate OPEN beads. A closed anchor is invisible to every one of them AT
# ONCE, so nothing escalates — the ledger reads "landed" while the PR rots. The
# failure has no symptom other than a queue that quietly stops moving.
#
# THE TWO DATED CASES this check is measured against:
#
#   tk-vnlll — signal-loom sl-jcr4 was CLOSED at PR-creation on 2026-08-05
#     carrying pr_url=.../pull/518 and NO merge_result. PR#518 then sat OPEN for
#     four days satisfying every non-codex gate (head matching the anchor's
#     gc.work_commit, base main, mergeStateStatus CLEAN, all 11 checks SUCCESS,
#     APPROVED by an admin) with zero escalations.
#
#   tk-fip23 — on 2026-08-23 eight gc-toolkit anchors were closed in a
#     19-second span carrying merge_result=pull_request, pr_number, and a green
#     check.codex at the live head. The operator approved all eight PRs; every
#     one was CLEAN and MERGEABLE; none landed. The rig's merge queue sat dead
#     for hours one API call from eight landings — and the fix for it was itself
#     a PR stranded in the same queue.
#
# WHAT THIS ADDS, GIVEN THE REPAIR ALREADY EXISTS. check-set-heal.sh phase 0a
# ("(a-reopen) CLOSED-BUT-NOT-LANDED") repairs this shape: it reopens the bead
# and lets the merge queue drive the PR again. This check does NOT duplicate
# that repair and ships no fix. It is the independent observer of whether the
# property actually HOLDS, and that is not the same question, for three reasons:
#
#   1. Phase 0a fires only from the `refinery-reconcile` order. A rig whose
#      registration stopped ticking has no merge cadence and therefore no
#      healer — the exact outage `check-refinery-merge-cadence` exists for
#      (47 minutes of no merge cadence citywide, 2026-08-19, tk-fdstg). The
#      healer cannot report its own absence; a property check can.
#   2. Phase 0a REFUSES several shapes on purpose (ambiguity; a bead it already
#      reopened once and something re-closed). Those are exactly the violations
#      that persist, and the ambiguity refusal escalates to nothing at all —
#      it writes one stderr line into a pass log and moves on.
#   3. `bd close --force` closes a bead past open children and live blockers by
#      design. No writer-side guard covers that route.
#
#   Every other rig-scoped store in this city is checked too, including ones
#   with no refinery at all, where nothing would ever repair a violation.
#
# So a red verdict here means one of: the cadence is not running, the healer
# refused, or something closed a bead out of band. The details say which.
#
# WHAT IS FLAGGED — a CLOSED bead in a rig's store, all of these together:
#
#   * `merge_result` is NON-TERMINAL, by explicit ALLOW-LIST — absent,
#     `pull_request`, or `pre_open_gate`. `merge_result` spells two different
#     facts with one key: a DISPOSITION (`merged`, `abandoned`, `retargeted`)
#     records that a pass decided the bead was finished, while a HANDOFF
#     (`pull_request` — the PR is open awaiting a land; `pre_open_gate` — the
#     branch awaits its codex signoff) records the opposite. Anything else,
#     INCLUDING a marker this check has never heard of, reads as a disposition
#     and is left alone. An allow-list is what keeps the widening fail-closed.
#
#     The bead that filed this check (tk-39tv12) named the two in-flight
#     spellings. Absent is carried as well, deliberately: it is the SAME
#     invariant and it is the spelling the tk-vnlll case wore, so a check that
#     declined it would certify I5 true with sl-jcr4's exact shape sitting in
#     the ledger. It is also the healer's own allow-list, which keeps the two
#     surfaces reporting on one set. Each row says which spelling it wore.
#
#   * it names a pull request (`pr_number`, else a `/pull/<n>` in `pr_url`),
#     and
#   * that PR is still OPEN.
#
#     A pull number is unique only WITHIN a repository, so which repository is
#     resolved per bead — from the `pr_url` when it parses, else this rig's own
#     origin — and never assumed. The bulk `gh pr list` answers for this rig's
#     origin; a bead naming ANOTHER repository (a normal shape: a bead filed in
#     one rig's store tracking work that lands in a different repo) gets one
#     targeted `gh pr view` against the repository it names, capped, with the
#     remainder reported UNDETERMINED.
#
# WHAT IS NOT FLAGGED — each exclusion is the healer's, kept deliberately in
# step with it so a red verdict here always names something a repair pass would
# act on or has explicitly refused:
#
#   - REWORK / REVIEW CHILDREN (`anchor_bead`, `task_kind`, `source_review_bead`
#     or `source_anchor_bead` set). A child's close claims its own work is
#     folded in, never that the PR landed; the anchor makes that claim. This is
#     the COMMON closed shape that references a live PR, and dropping it is what
#     keeps the check off ~100 spent review beads per rig.
#   - A bead with NO `branch`. It is not the anchor shape — nothing could have
#     landed it — so its close is not a landing claim. Counted in the summary,
#     never silently dropped.
#   - A SURVIVING `gc.routed_to`. A closed bead that still carries a pool route
#     is not a spent anchor; the refinery orphan scan offers exactly
#     open + branch + no assignee, so this shape belongs to the route, not here.
#   - A NON-GATING ASSIGNEE. Empty, or refinery-ish, is the gating shape
#     (sl-jcr4 was assigned signal-loom/gc-toolkit.refinery when it was closed).
#     Anything else is a worker's own record.
#   - A PR ALREADY ANCHORED BY A LIVE BEAD — keyed, as phase 0a keys it, on a
#     LIVE bead carrying a `merge_result` for the same PR. That bead IS the
#     anchor, so the closed one is a spent predecessor and the PR is tracked.
#     (This is what correctly acquits a closed rework child under a live parent
#     anchor — the shape that carries no child metadata marker at all.)
#   - `tracking_only` — a deliberately non-gating tracking record.
#   - A PR IN ANOTHER REPOSITORY whose state could not be read, or that fell
#     past the per-rig cross-repository read cap. Reported as UNDETERMINED,
#     never as OK — and never matched against this repository's same-numbered
#     PR, which would be answering about a stranger's.
#
# COST, and the order that buys it. The closed PR-referencing set is LARGE
# (905 beads on this rig — every anchor closed since merge_result existed).
# The LEDGER is read first because it is local and cheap; `gh` is a network
# round trip and is reached ONLY for a rig that produced candidates at all.
# The live-anchor lookup is one more query, made only for a rig with survivors
# — which on a healthy city is none. The per-PR cross-repository reads are the
# one input not bounded by construction, so they carry an explicit cap.
#
# FAIL-CLOSED THROUGHOUT. Every unreadable input is a WARNING naming what was
# not checked, never a pass: an empty result from a failed call is
# indistinguishable from "nothing is wrong" while meaning the opposite, and
# that fail-open is the exact shape this check exists to remove.
#
# Suspended rigs are skipped, matching the doctor core's per-rig rule: opening
# their bead store triggers bd auto-start of orphan Dolt servers.
#
# Detect only. It writes nothing, ships no fix.sh, and changes no merge
# semantics.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# Per-probe bound. `gc doctor` runs every check under `--check-timeout`
# (default 60s), and a check that overruns is ABANDONED and reported as
# "outcome unknown" — every warning it had collected is lost with it. So a
# single wedged probe must not be able to spend the whole budget.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-30}"

# ...and the sweep as a whole stops itself before the doctor does. A partial
# answer that NAMES the stores it did not reach beats an abandoned one that
# says nothing about any of them. Set below the doctor default on purpose;
# raise both together if a city ever needs it. `SECONDS` is a bash builtin, so
# the guard costs no process. Measured cost of a full sweep on the reference
# city: ~18s over 5 rigs and 1,513 closed PR-referencing beads.
BUDGET="${GC_DOCTOR_CHECK_BUDGET:-45}"

# The statuses a bead can wear and still be somebody's live work. The same list
# check-set-heal.sh and check-merge-gate-drop use, so "is this PR already
# anchored" is answered the same way on every surface.
LIVE_STATUSES="open,in_progress,blocked,deferred,hooked,pinned"

# The most cross-repository PRs any one rig will be read one-by-one. The bulk
# open-PR list cannot answer for a foreign repo, so each of those costs its own
# API call; past this many they are reported UNDETERMINED rather than read.
# Three exist city-wide today, so the cap is headroom, not a trim.
FOREIGN_CAP=25

# gh requires a --limit. Generous rather than absent: a PR past it is not a new
# exposure (the bead stays closed either way) but it would be a SILENT gap, so a
# full page is reported rather than assumed complete.
PR_PAGE=1000

errors=()
warnings=()
notes=()

# Totals for the summary, so a green verdict states what it actually looked at
# rather than merely asserting itself.
rigs_checked=0
rigs_skipped=0
closed_scanned=0
candidates=0
open_pr_hits=0
no_branch=0
anchored_live=0

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# Bead notes and titles carry control characters that make jq abort mid-parse,
# which would otherwise cost a whole store. Everything below 0x20 except the
# newline goes — a literal TAB is invalid inside a JSON string just like the
# rest, and dropping it also clears the 0x1F these rows are joined on, so no
# payload byte can pose as a field separator. Nothing here reads free text, only
# ids and PR references, so there is no payload to preserve.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# Enumeration loops read from a CHECKED temp file, never from a `<<<`
# here-string. bash backs a here-string with a temp file it creates silently;
# under disk pressure that redirection fails, the loop body runs ZERO times, and
# a check falls through to its green summary — byte-identical to a healthy empty
# result and strictly worse than a crash, because a crash escalates (tk-lslk2).
# A plain file redirect still keeps the loop in the current shell, so the
# counters below survive it.
TMPD=$(mktemp -d 2>/dev/null) || TMPD=""
if [ -z "$TMPD" ] || [ ! -d "$TMPD" ]; then
    echo "cannot determine whether any closed bead is unlanded"
    echo "\`mktemp -d\` failed, so the row enumerations below could not be given a checked backing file; refusing to scan rather than risk a silently-empty sweep that would report OK."
    exit 1
fi
trap 'rm -rf "$TMPD"' EXIT

# Writes $1 to a named scratch file and echoes its path, or echoes nothing when
# the write failed. A caller that gets nothing back must treat the enumeration
# as UNREADABLE — that is the whole point of routing through a checked file.
rows_file() {
    local f="$TMPD/$1"
    printf '%s\n' "$2" > "$f" 2>/dev/null || return 1
    printf '%s' "$f"
}

# ---------------------------------------------------------------------------
# THE PR-NUMBER AND REPOSITORY PROJECTION, shared by both ledger scans.
#
# A bead names its PR by NUMBER, and a number is unique only WITHIN a
# repository. So every row resolves both halves in the ONE jq program that
# builds it: the number from `pr_number`, else parsed out of `pr_url`; the
# repository from `pr_url` when it parses, else this rig's own origin. Resolving
# the repository in a later per-row pass would drop rows whose jq failed, and a
# dropped row is not merely unreported — the ambiguity guard below is a
# WHOLE-SET property, so losing one of two candidates for a PR makes the
# survivor look unambiguous.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # a jq program: $m and $originq are jq bindings, not shell
PR_IDENT_JQ='
def pr_num($m):
  (($m.pr_url // "") | tostring) as $u
  | if (($m.pr_number // "") | tostring) != "" then (($m.pr_number) | tostring)
    else ([$u | capture("/pull/(?<n>[0-9]+)")] | .[0]
          | if . == null then "" else .n end) end;
def pr_repo($m; $originq):
  (($m.pr_url // "") | tostring) as $u
  | ([$u | capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<rp>[^/]+/[^/]+)/pull/[0-9]")] | .[0]) as $c
  | if $c != null then ($c.h + "/" + $c.rp) else $originq end;
'

# ---------------------------------------------------------------------------
# The rig roster. `gc rig list --json` reports EFFECTIVE suspension (runtime
# state, not just the config's suspended_on_start), which is what the skip
# needs. Unreadable is a WARNING, never a pass: with no roster nothing is
# scanned at all, and reporting that as clean is the fail-open this check
# exists to remove.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether any closed bead is unlanded"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc, timeout ${BOUND}s) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

rig_rows=$(printf '%s' "$rigs_raw" | jq -r '
    .rigs[]? | select((.path // "") != "")
    | [ ((.name // "") | gsub("[[:cntrl:]]"; " ")),
        .path,
        (((.suspended // false)) | tostring) ]
    | join("\u001f")' 2>/dev/null)

if [ -z "$rig_rows" ]; then
    echo "cannot determine whether any closed bead is unlanded"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

rig_expected=$(printf '%s\n' "$rig_rows" | grep -c . 2>/dev/null) || rig_expected=0
rig_seen=0
budget_stop=0

rig_file=$(rows_file rigs "$rig_rows") || rig_file=""
if [ -z "$rig_file" ]; then
    echo "cannot determine whether any closed bead is unlanded"
    echo "the rig roster could not be written to a scratch file; refusing to scan rather than risk a silently-empty sweep."
    exit 1
fi

# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash collapses the pair, lands
# the path in rig_name, leaves rig_path empty and `continue`s — silently
# skipping a whole store. US is not IFS whitespace, so empty fields survive.
while IFS=$'\037' read -r rig_name rig_path suspended; do
    [ -n "$rig_path" ] || continue
    if [ "$SECONDS" -ge "$BUDGET" ]; then
        budget_stop=1
        break
    fi
    rig_seen=$((rig_seen + 1))
    label="${rig_name:-<city>}"

    if [ "$suspended" = "true" ]; then
        rigs_skipped=$((rigs_skipped + 1))
        notes+=("$label: skipped (suspended — querying its store would auto-start an orphan Dolt server)")
        continue
    fi

    # -----------------------------------------------------------------------
    # THE REPOSITORY THIS RIG'S PR NUMBERS ARE READ IN, host-qualified
    # `<host>/<owner>/<repo>` — the form `--repo` takes and the form a
    # pull-request URL carries.
    #
    # It comes from the rig checkout's origin remote, NEVER from `gh`: an
    # unpinned `gh pr list` answers about whatever repository gh considers
    # current (`gh repo set-default`, GH_REPO, GH_HOST and cwd all move it), and
    # a foreign same-numbered PR would either acquit a real violation or invent
    # one. Same parse and same fail-closed rule as check-set-heal.sh's
    # resolve_origin_repo_q and reconcile-merged-prs.sh's; those are standalone
    # by design, so this is duplicated rather than sourced. Keep them in step.
    # -----------------------------------------------------------------------
    origin_q=""
    origin_url=$(git -C "$rig_path" remote get-url origin 2>/dev/null | tr -d '[:space:]')
    case "$origin_url" in
        git@github.com:*|https://github.com/*|ssh://git@github.com/*)
            origin_q=$(printf '%s' "$origin_url" \
                | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
                      -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    case "$origin_q" in
        */*/*|/*|*/) origin_q="" ;;
        */*)         origin_q="github.com/$origin_q" ;;
        *)           origin_q="" ;;
    esac

    if [ -z "$origin_q" ]; then
        warnings+=("$label: cannot resolve $rig_path to a github.com <owner>/<repo> origin (no origin remote, or an unrecognised URL) — a PR number there could only be read in whatever repository gh considers current, so this store was NOT checked")
        continue
    fi

    # -----------------------------------------------------------------------
    # THE LEDGER SIDE FIRST. Both key scans must succeed: a read that DIED after
    # emitting a well-formed array passes a shape test and reads as a complete
    # scan, and the ambiguity guard below is a whole-set property that cannot
    # see a duplicate it never scanned.
    # -----------------------------------------------------------------------
    closed_raw=""
    scan_ok=1
    for key in pr_url pr_number; do
        # `--db` pins the store explicitly. An ambient BEADS_DIR pins the
        # caller's OWN rig, so a doctor run from inside one rig would otherwise
        # read that rig's ledger once per rig and report its beads under every
        # other rig's name.
        raw=$(run_bounded bd list --db "$rig_path/.beads" \
                  --status closed --has-metadata-key "$key" --json --limit 0 2>/dev/null)
        rc=$?
        if [ "$rc" -ne 0 ] || [ -z "$raw" ]; then
            warnings+=("$label: could not list closed beads carrying \`$key\` in $rig_path/.beads (rc=$rc, timeout ${BOUND}s) — this store was NOT checked")
            scan_ok=0
            break
        fi
        if ! printf '%s' "$raw" | strip_ctl | jq -e 'type == "array"' >/dev/null 2>&1; then
            warnings+=("$label: the closed \`$key\` listing from $rig_path/.beads was not a readable array — this store was NOT checked")
            scan_ok=0
            break
        fi
        closed_raw="$closed_raw
$raw"
    done
    [ "$scan_ok" = 1 ] || continue

    rigs_checked=$((rigs_checked + 1))

    # DISTINCT beads, not rows: the two key scans overlap heavily (a bead
    # carrying both pr_url and pr_number is in both), and summing their lengths
    # would report roughly double what was actually looked at.
    n_closed=$(printf '%s\n' "$closed_raw" | strip_ctl \
        | jq -s '[.[][]] | unique_by(.id) | length' 2>/dev/null) || n_closed=""
    [ -n "$n_closed" ] || n_closed=0
    closed_scanned=$((closed_scanned + n_closed))

    # -----------------------------------------------------------------------
    # Candidate projection. The exclusions are check-set-heal.sh phase 0a's,
    # applied to metadata, minus the open-PR intersection which needs the
    # network read below.
    # -----------------------------------------------------------------------
    cands=$(printf '%s\n' "$closed_raw" | strip_ctl | jq -s -c --arg originq "$origin_q" "
      $PR_IDENT_JQ"'
      # An operator hold, read the way merge-skill.sh reads it: set and not one
      # of the explicit off spellings. `tostring` BEFORE `ascii_downcase`,
      # because a marker is not always a string — a writer storing JSON
      # (`merge_hold: true`) yields a boolean, and ascii_downcase on a boolean
      # ABORTS the jq program, whose error this projection would discard: the
      # hold would evaporate along with the whole candidate set. jq `//`
      # already folds boolean false (and null) to "", the off answer, so only
      # the truthy side needs the cast.
      def held($v): ($v // "") | tostring | ascii_downcase
                    | (. != "" and . != "false" and . != "0" and . != "null");
      ((add // []) | unique_by(.id))[]
      | . as $b | (($b.metadata // {})) as $m
      # THE NON-TERMINAL ALLOW-LIST. See the header: never a deny-list of the
      # terminal values, so a marker this check has never heard of reads as a
      # disposition and is left alone.
      | ((($m.merge_result // "") | tostring | ascii_downcase | gsub("[[:space:]]"; ""))) as $mr
      | select($mr == "" or $mr == "pull_request" or $mr == "pre_open_gate")
      # Rework and review CHILDREN. A child close is not a landing claim.
      | select((($m.anchor_bead // "") | tostring) == "")
      | select((($m.task_kind // "") | tostring) == "")
      | select((($m.source_review_bead // "") | tostring) == "")
      | select((($m.source_anchor_bead // "") | tostring) == "")
      # A surviving pool route. Not a spent anchor.
      | select((($m["gc.routed_to"] // "") | tostring) == "")
      | pr_num($m) as $n
      | select($n != "")
      | {
          id:       (($b.id // "?") | tostring),
          num:      $n,
          repo:     pr_repo($m; $originq),
          mr:       $mr,
          branch:   (($m.branch // "") | tostring),
          assignee: ((($b.assignee // "") | tostring) | ascii_downcase),
          already:  (($m.reopened_not_landed // "") | tostring),
          hold: ([ (if held($m.merge_hold) then "merge_hold=" + ($m.merge_hold | tostring) else empty end),
                   (if held($m.rebase_hold) then "rebase_hold=" + ($m.rebase_hold | tostring) else empty end),
                   (if held($m.tracking_only) then "tracking_only=" + ($m.tracking_only | tostring) else empty end) ]
                 | join(", "))
        }' 2>/dev/null)
    cands_rc=$?

    if [ "$cands_rc" -ne 0 ]; then
        warnings+=("$label: the closed-candidate projection over $rig_path/.beads failed — this store was NOT checked")
        continue
    fi

    n_cands=$(printf '%s\n' "$cands" | grep -c . 2>/dev/null) || n_cands=0
    candidates=$((candidates + n_cands))
    [ -n "$cands" ] || continue

    # -----------------------------------------------------------------------
    # The cheap discriminator, read ONCE and only now: every PR still open in
    # THIS repository. Fail-closed on an unreadable answer — "which PRs are
    # open" is the entire basis for flagging anything, and an empty result from
    # a failed call is indistinguishable from "nothing is open" while meaning
    # the opposite.
    # -----------------------------------------------------------------------
    if ! command -v gh >/dev/null 2>&1; then
        warnings+=("$label: \`gh\` is not on PATH, so no PR's state could be read — $n_cands closed candidate(s) in $rig_path/.beads were NOT checked")
        continue
    fi

    pr_raw=$(run_bounded gh pr list --repo "$origin_q" --state open --limit "$PR_PAGE" --json number 2>/dev/null)
    pr_rc=$?
    if [ "$pr_rc" -ne 0 ] || [ -z "$pr_raw" ] \
       || ! printf '%s' "$pr_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
        warnings+=("$label: the open-PR enumeration for '$origin_q' did not return a readable result (rc=$pr_rc, timeout ${BOUND}s) — $n_cands closed candidate(s) were NOT checked; a closed bead can only be flagged against a PR confirmed OPEN")
        continue
    fi

    n_open=$(printf '%s' "$pr_raw" | jq -r 'length' 2>/dev/null)
    if [ "$n_open" = "$PR_PAGE" ]; then
        warnings+=("$label: the open-PR enumeration for '$origin_q' returned a FULL page ($PR_PAGE); a closed-but-unlanded anchor whose PR fell past it is invisible to this run")
    fi
    open_nums=$(printf '%s' "$pr_raw" | jq -c '[.[].number | tostring]' 2>/dev/null)
    [ -n "$open_nums" ] || open_nums='[]'

    # -----------------------------------------------------------------------
    # A candidate whose pr_url names ANOTHER repository is a normal shape, not
    # an anomaly: a bead filed in one rig's store routinely tracks work that
    # lands in a different repo (a gc-binary fix filed against the toolkit, a
    # cross-rig dependency). Three of them exist on this city right now.
    #
    # The bulk list above cannot answer for them — a pull number is unique only
    # within a repository, so matching PR#21 against THIS repo's open list
    # would be answering about a stranger's PR. But the pr_url names the
    # repository outright, so one targeted `gh pr view` can. Reporting them as
    # permanently UNDETERMINED instead would leave the check amber on a healthy
    # city forever, and a check that is always amber is a check nobody reads.
    #
    # Capped, because the cost is one API call each and this is the only
    # unbounded-by-construction input here. Past the cap they stay
    # undetermined, and the cap says so rather than trimming silently.
    # -----------------------------------------------------------------------
    foreign_rows=$(printf '%s\n' "$cands" | jq -s -c --arg originq "$origin_q" '
        .[] | select(.repo != $originq)' 2>/dev/null)

    foreign_open=""
    if [ -n "$foreign_rows" ]; then
        n_foreign=$(printf '%s\n' "$foreign_rows" | grep -c . 2>/dev/null) || n_foreign=0
        foreign_file=$(rows_file foreign "$foreign_rows") || foreign_file=""
        if [ -z "$foreign_file" ]; then
            warnings+=("$label: $n_foreign closed candidate(s) naming another repository could not be written to a scratch file — whether they landed is UNDETERMINED")
        else
            fseen=0
            while IFS= read -r frow; do
                [ -n "$frow" ] || continue
                fseen=$((fseen + 1))
                fid=$(printf '%s' "$frow" | jq -r '.id // "?"' 2>/dev/null)
                fnum=$(printf '%s' "$frow" | jq -r '.num // ""' 2>/dev/null)
                frepo=$(printf '%s' "$frow" | jq -r '.repo // ""' 2>/dev/null)
                if [ "$fseen" -gt "$FOREIGN_CAP" ]; then
                    warnings+=("$label: closed bead $fid names PR#$fnum in $frepo, past this run's cap of $FOREIGN_CAP cross-repository reads — whether it landed is UNDETERMINED")
                    continue
                fi
                fstate=$(run_bounded gh pr view "$fnum" --repo "$frepo" --json state -q .state 2>/dev/null)
                fstate_rc=$?
                if [ "$fstate_rc" -ne 0 ] || [ -z "$fstate" ]; then
                    warnings+=("$label: closed bead $fid names PR#$fnum in $frepo (another repository than this rig's origin $origin_q) and that PR's state could not be read (rc=$fstate_rc, timeout ${BOUND}s) — whether it landed is UNDETERMINED")
                    continue
                fi
                [ "$fstate" = "OPEN" ] || continue
                foreign_open="$foreign_open
$frow"
            done < "$foreign_file"
            rm -f "$foreign_file"
            if [ "$fseen" -ne "$n_foreign" ]; then
                warnings+=("$label: read only $fseen of $n_foreign cross-repository candidate(s) — the enumeration did not complete, so the rest were NOT checked")
            fi
        fi
    fi

    # -----------------------------------------------------------------------
    # Intersect the local half, fold in the foreign PRs confirmed OPEN, and
    # settle the one remaining whole-set question here rather than in a per-row
    # pass: which survivors share a PR with another survivor (the ambiguity
    # phase 0a refuses on). Keyed on REPOSITORY and number together, because a
    # pull number is unique only within a repository — a candidate for another
    # repo's #10 must not make ours look ambiguous.
    # -----------------------------------------------------------------------
    # The LOCAL half only. `$foreign_open` is folded in below already filtered
    # to the PRs a targeted read CONFIRMED open — re-selecting the foreign rows
    # out of `$cands` here would put back every cross-repository candidate,
    # including the ones whose PRs are merged.
    local_surv=$(printf '%s\n' "$cands" | jq -c --arg originq "$origin_q" --argjson open "$open_nums" '
        select(.repo == $originq) | . as $c | select($open | index($c.num))' 2>/dev/null)
    local_rc=$?

    surv=$(printf '%s\n%s\n' "$local_surv" "$foreign_open" | jq -s -c '
        unique_by(.id) as $s
        | $s[]
        | . as $c
        | . + { dup: ([ $s[]
                        | select(.id != $c.id)
                        | select(.num == $c.num and .repo == $c.repo) ] | length > 0) }' 2>/dev/null)
    surv_rc=$?
    if [ "$local_rc" -ne 0 ] || [ "$surv_rc" -ne 0 ]; then
        warnings+=("$label: the open-PR intersection over $n_cands closed candidate(s) failed — this store was NOT checked")
        continue
    fi

    [ -n "$surv" ] || continue

    n_surv=$(printf '%s\n' "$surv" | grep -c . 2>/dev/null) || n_surv=0
    open_pr_hits=$((open_pr_hits + n_surv))

    # -----------------------------------------------------------------------
    # IS THE PR ALREADY ANCHORED? Asked once per rig, and only for a rig that
    # produced survivors — on a healthy city that is never.
    #
    # Keyed on a LIVE bead carrying a merge_result for the same PR, the way
    # phase 0a keys it: that bead IS the anchor, so a closed bead naming the
    # same PR is a spent predecessor and the PR is tracked. Rework and review
    # children name a PR and carry no merge_result by construction, so they
    # cannot buy a violation this silence.
    #
    # An UNREADABLE ledger is not "nothing is anchored": the arm reports the
    # survivors anyway with the failure named.
    # -----------------------------------------------------------------------
    anchored=""
    anchored_known=1
    live_raw=$(run_bounded bd list --db "$rig_path/.beads" \
                   --status="$LIVE_STATUSES" --has-metadata-key merge_result \
                   --json --limit 0 2>/dev/null)
    live_rc=$?
    if [ "$live_rc" -ne 0 ] || [ -z "$live_raw" ] \
       || ! printf '%s' "$live_raw" | strip_ctl | jq -e 'type == "array"' >/dev/null 2>&1; then
        anchored_known=0
    else
        anchored=$(printf '%s' "$live_raw" | strip_ctl | jq -r --arg originq "$origin_q" "
          $PR_IDENT_JQ"'
          .[]? | . as $b | (($b.metadata // {})) as $m
          | select((($m.merge_result // "") | tostring | gsub("[[:space:]]"; "")) != "")
          | pr_num($m) as $n
          | select($n != "")
          # REPOSITORY and number together: a pull number is unique only within
          # a repository, so a live anchor on some OTHER repository #10 must
          # not acquit a violation on ours.
          | (pr_repo($m; $originq) + "#" + $n) + " " + (($b.id // "?") | tostring)' 2>/dev/null) || anchored_known=0
    fi

    surv_file=$(rows_file survivors "$surv") || surv_file=""
    if [ -z "$surv_file" ]; then
        warnings+=("$label: $n_surv closed candidate(s) with an OPEN PR could not be written to a scratch file for classification — reported as undetermined rather than dropped")
        continue
    fi

    surv_seen=0
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        surv_seen=$((surv_seen + 1))

        bid=$(printf '%s' "$row" | jq -r '.id // "?"' 2>/dev/null)
        num=$(printf '%s' "$row" | jq -r '.num // "?"' 2>/dev/null)
        # The row's OWN repository, not this rig's origin: a survivor confirmed
        # open by the cross-repository read names a different one, and both the
        # message and the anchor lookup have to say which.
        repo=$(printf '%s' "$row" | jq -r '.repo // ""' 2>/dev/null)
        [ -n "$repo" ] || repo="$origin_q"
        mr=$(printf '%s' "$row" | jq -r '.mr // ""' 2>/dev/null)
        branch=$(printf '%s' "$row" | jq -r '.branch // ""' 2>/dev/null)
        assignee=$(printf '%s' "$row" | jq -r '.assignee // ""' 2>/dev/null)
        already=$(printf '%s' "$row" | jq -r '.already // ""' 2>/dev/null)
        hold=$(printf '%s' "$row" | jq -r '.hold // ""' 2>/dev/null)
        dup=$(printf '%s' "$row" | jq -r '.dup // false' 2>/dev/null)

        # The spelling this bead wore, phrased once and reused, so the sites
        # that state the same fact cannot drift apart.
        if [ -n "$mr" ]; then
            spell="merge_result=$mr, which records a HANDOFF (still in flight), not a disposition"
        else
            spell="NO merge_result at all — the tk-vnlll spelling"
        fi
        where="$label/$bid: CLOSED over OPEN $repo#$num"

        # A tracking record is not a landing claim, and it is excluded before
        # every other judgement for the same reason phase 0a excludes it: it is
        # deliberately non-gating.
        case "$hold" in
            *tracking_only*)
                notes+=("$where, but it is a tracking_only record ($hold) — deliberately non-gating, so its close claims no landing")
                continue ;;
        esac

        if [ -z "$branch" ]; then
            no_branch=$((no_branch + 1))
            notes+=("$where, but it records no branch — not the anchor shape, so nothing could have landed it; not counted as a landing claim")
            continue
        fi

        # Not the gating shape. Empty or refinery-ish is what an anchor wears.
        case "$assignee" in
            ""|*refinery*) : ;;
            *)
                notes+=("$where, but its assignee ($assignee) is neither empty nor a refinery address — not the gating anchor shape, so its close is a worker's own record")
                continue ;;
        esac

        if [ "$anchored_known" = 1 ] && [ -n "$anchored" ]; then
            owner=$(printf '%s\n' "$anchored" | awk -v k="$repo#$num" '$1 == k { print $2; exit }' 2>/dev/null)
            if [ -n "$owner" ] && [ "$owner" != "$bid" ]; then
                anchored_live=$((anchored_live + 1))
                notes+=("$where — NOT flagged: $label/$owner is live and carries a merge_result for the same PR, so that bead is the anchor and this one is a spent predecessor")
                continue
            fi
        fi

        anchor_note=""
        [ "$anchored_known" = 1 ] || anchor_note=" Whether a LIVE bead already anchors this PR is UNDETERMINED (that lookup failed or timed out at ${BOUND}s) — reported rather than assumed owned."

        if [ -n "$hold" ]; then
            warnings+=("$where ($spell), under an operator hold ($hold). The ledger record is false either way, but the hold is a deliberate hand-removal from the automated queue and check-set-heal.sh phase 0a will not reopen it — a human owns this one.$anchor_note")
            continue
        fi

        if [ "$dup" = "true" ]; then
            errors+=("$where ($spell), and it is NOT the only closed candidate naming that PR. check-set-heal.sh phase 0a refuses an ambiguous PR and reopens NEITHER, and that refusal escalates to nothing — it writes one line to a pass log. Nothing will repair this without an operator deciding which bead is the anchor.$anchor_note")
            continue
        fi

        case "$already" in
            *@open)
                errors+=("$where ($spell), and it carries reopened_not_landed=$already — check-set-heal.sh phase 0a already reopened it once and CONFIRMED it open, so a live writer re-closed it afterwards. Phase 0a will not reopen it a second time (that would flap), so nothing automated is coming: find the writer that is re-closing it.$anchor_note")
                continue ;;
        esac

        errors+=("$where ($spell), branch $branch. Under the close-on-land contract \`closed\` means landed, so this bead is a FALSE DURABLE RECORD and is invisible to every merge pass at once — they all enumerate open beads. check-set-heal.sh phase 0a should reopen it on the next refinery-reconcile tick; if it persists, that rig's merge cadence is not running (check-refinery-merge-cadence) or the bead was closed out of band.$anchor_note")
    done < "$surv_file"
    rm -f "$surv_file"

    # A loop that processed fewer rows than were rendered did not enumerate the
    # set — the silent-redirect failure above, or a read that died mid-file.
    # Reporting the remainder as clean is exactly the fail-open this check
    # exists to remove.
    if [ "$surv_seen" -ne "$n_surv" ]; then
        warnings+=("$label: classified only $surv_seen of $n_surv closed candidate(s) with an OPEN PR — the enumeration did not complete, so the rest were NOT checked")
    fi
done < "$rig_file"
rm -f "$rig_file"

if [ "$budget_stop" = 1 ]; then
    warnings+=("stopped after $rig_seen of $rig_expected rig(s): this check's ${BUDGET}s wall-clock budget was spent, so the remaining store(s) were NOT checked. Stopping here is deliberate — overrunning \`gc doctor --check-timeout\` would abandon the whole check and discard the findings above. Re-run alone, or raise GC_DOCTOR_CHECK_BUDGET and --check-timeout together.")
elif [ "$rig_seen" -ne "$rig_expected" ]; then
    warnings+=("scanned only $rig_seen of $rig_expected rig(s) — the roster enumeration did not complete, so the rest were NOT checked")
fi

# ---------------------------------------------------------------------------
# Report. Errors outrank warnings; an undeterminable arm always surfaces.
# ---------------------------------------------------------------------------
emit_details() {
    local v
    for v in ${errors[@]+"${errors[@]}"};     do echo "ERROR: $v"; done
    for v in ${warnings[@]+"${warnings[@]}"}; do echo "WARN:  $v"; done
    for v in ${notes[@]+"${notes[@]}"};       do echo "note:  $v"; done
}

n_err=${#errors[@]}
n_warn=${#warnings[@]}

if [ "$n_err" -gt 0 ]; then
    echo "$n_err closed bead(s) claim work that has not landed"
    emit_details
    echo ""
    echo "Each of these is CLOSED while its pull request is still OPEN, so the ledger records a landing that did not happen — and because every merge pass (merge-skill.sh, pre-open-resolve.sh, reconcile-merged-prs.sh, check-set-heal.sh phase 0) enumerates OPEN beads, a closed anchor is invisible to all of them at once and nothing escalates. Remedy: reopen the bead (\`gc bd update <bead> --status=open\`), which is the whole repair — an in-flight merge_result is already the marker merge-skill.sh enumerates on, and an absent one is re-stamped by check-set-heal.sh phase 0 on the same pass. Detect only: this check writes nothing. Invariant I5, docs/component-model.md §3."
    exit 2
fi

if [ "$n_warn" -gt 0 ]; then
    echo "closed-implies-landed partially determined ($n_warn undetermined or held)"
    emit_details
    exit 1
fi

summary="OK: no closed bead claims unlanded work — $rigs_checked rig(s) checked, $closed_scanned closed PR-referencing bead(s) scanned, $candidates anchor-shaped candidate(s), $open_pr_hits with a still-open PR, 0 unlanded"
[ "$anchored_live" -gt 0 ] && summary="$summary ($anchored_live already anchored by a live bead)"
[ "$no_branch" -gt 0 ] && summary="$summary ($no_branch branchless, not a landing claim)"
[ "$rigs_skipped" -gt 0 ] && summary="$summary ($rigs_skipped suspended rig(s) skipped)"
echo "$summary"
emit_details
exit 0
