#!/usr/bin/env bash
# Pack doctor check: a pull request has exactly one open gating anchor, and an
# open gating anchor names exactly one pull request (component-model I4,
# tk-qz6081).
#
# THE INVARIANT (docs/component-model.md §3, I4): "Every PR has exactly one
# owning anchor, and every gating anchor is open." The document records it as
# PARTIAL, and this check is the half that was UNCHECKED.
#
# WHY A CHECK AND NOT ONLY THE HOLD. The property is enforced today as a RUNTIME
# HOLD inside assets/scripts/merge-skill.sh: the validate stage refuses a PR
# claimed by more than one open gating anchor (tk-ynz4b), because the loop
# validates each anchor INDEPENDENTLY and the PR would otherwise be gated by its
# WEAKEST anchor — a rework child that leaked into the anchor class with no
# check_set would land the PR while the real anchor's codex gate is red. That
# hold protects the merge. It does not detect the condition: nothing looks at a
# PR until something tries to land it, so a second anchor is invisible for as
# long as nobody merges, and the state is created UPSTREAM (a rework child filed
# against the wrong parent, a hand recovery, a rig checkout on an older pack)
# where nothing looks at all.
#
# Since tk-3sdfq the hold is weaker still as a detector: more than one open
# anchor is now COALESCED into a single gate whose check_set is the UNION of
# theirs, and the merge PROCEEDS. That is correct for the merge — a union is
# stronger than either member — but it means the duplicate no longer even stops
# the pass that would have surfaced it. The pair simply persists. Nothing
# retires it: the hold told operators to "close/demote the duplicate", nothing
# performs that demotion, and the pass that used to converge these pairs
# (reconcile-merged-prs.sh closing every anchor of the PR ON MERGE) runs only
# after the merge. So the condition is now both silent AND self-perpetuating,
# which is exactly what a doctor check is for.
#
# WHAT IS FLAGGED
#
#   (A) One PR, more than one open gating anchor. The tk-ynz4b condition,
#       observed from the ledger instead of from a merge attempt.
#
#   (B) One open gating anchor naming more than one PR NUMBER in one repository.
#       The dual, and the other way the 1:1 correspondence I4 asserts can break:
#       if anchor X owns both PR#1 and PR#2, then neither PR has an unambiguous
#       owner. merge-skill.sh holds this at the same site and with the same
#       invisibility ("anchor $id names more than one PR number in this
#       repository ... merge held — operator must repair the metadata"), so
#       leaving it out would check one direction of a correspondence and not the
#       other. It costs nothing extra: it is read off the same projection as (A).
#
# THE ANCHOR PREDICATE IS MIRRORED FROM merge-skill.sh, DELIBERATELY. A check
# that recognised a different set of anchors than the pass it backstops would
# report a state that pass cannot reach, or miss the one it can:
#
#   * status `open` (case-insensitively) — merge-skill enumerates open beads
#     only, so a closed bead is not a competing anchor no matter what it holds;
#   * `metadata.merge_result == "pull_request"` — the gating marker its
#     enumeration keys on. This is also why `tracking_only` records never appear
#     here: that marker means "references a PR for LINKAGE ONLY", and such a bead
#     WITHHOLDS merge_result by construction (tk-8329m), so it is already out;
#   * PR numbers from `pr_number`, `fork_pr`, and `fork_pr_url`'s `/pull/<n>` —
#     merge-skill's `pr_nums_here`. Reading only `pr_number`, as an earlier
#     version of that pass did, made a fork-keyed anchor invisible to the very
#     guard that owns it;
#   * repository from `metadata.pr_url`, with `?` for absent-or-unparseable —
#     merge-skill's `repo_of`/`same_repo`. A PR NUMBER names a different pull
#     request in every other repository, so anchors are only ever compared
#     within one repository.
#
# THE ONE PLACE THIS CHECK MUST GO BEYOND THAT PASS, AND THE GUARD IT NEEDS.
# merge-skill reads ONE store and resolves `?` against ITS OWN checkout's origin
# (`repo: (if $r == "?" then $o else $r end)`). This check spans EVERY store, so
# "the origin" is not a single value here and a `?` cannot be resolved globally.
# Each store's `?` is resolved against THAT store's own rig checkout origin,
# parsed exactly as merge-skill and check-set-heal.sh parse theirs. When a store
# has no resolvable origin its `?` anchors stay unqualified and are compared
# ONLY against other anchors in the SAME store — never across stores, where an
# unknown repository would otherwise match every repository and manufacture
# findings out of two unrelated ledgers that happen to share a PR number. That
# narrowing is reported as a note rather than left silent.
#
# WHAT IS NOT FLAGGED, AND WHY
#
#   * A CLOSED bead carrying a handoff marker (`merge_result=pull_request` or
#     `pre_open_gate`) — i.e. the "every gating anchor is open" half of I4, and
#     the ANCHORLESS signature. Deliberately out of scope, for two measured
#     reasons.
#
#     First, the ledger alone cannot tell the failure from its own history. On
#     2026-08-24 the live city held 288 such beads across five stores (gc-toolkit
#     183, gascity 94, signal-loom 6, shutupandlisten 5), dating back to April.
#     Nearly all are PRs that merged long ago whose metadata was simply never
#     reconciled from the handoff spelling to `merged` — the I5 shape recorded in
#     docs/component-model.md, where all eight anchors of the 2026-08-23 incident
#     have since landed. A live strand (tk-fip23: closed anchor, PR STILL OPEN,
#     nothing able to land it) is byte-identical in the ledger to that stale
#     history. Only the PR's live state separates them, so a ledger-only arm here
#     would ship permanently red on 288 historical rows and be muted in a week.
#
#     Second, the distinction that needs GitHub is ALREADY DRAWN, by a pass that
#     runs far more often than `gc doctor`: reconcile-merged-prs.sh walks
#     PR -> BEAD on every refinery idle wake, reports an open PR no live bead
#     points at as ANCHORLESS, and escalates it once; check-set-heal.sh's
#     closed-but-not-landed phase owns the repair, carrying the guards such a
#     repair needs. Adding a third reader of that same condition — one that would
#     also make `gc doctor` depend on network and `gh` auth — would duplicate a
#     working pass rather than close a gap.
#
#   * A single open anchor sharing its PR with any number of CLOSED beads. That
#     is the ordinary shape after a coalesce or a land, and merge-skill cannot
#     see a closed bead either.
#
#   * An anchor under `merge_hold`. An operator-parked anchor is still an anchor
#     and merge-skill still counts it when deciding duplication; parking pauses a
#     merge, it does not resolve an ownership conflict.
#
# Exit codes: 0=OK, 1=Warning, 2=Error
# stdout: first line=message, rest=details

set -u

# Per-probe wall-clock bound. `gc doctor` gives each check a total budget
# (`--check-timeout`, default 1m0s) and a check that exceeds it is ABANDONED and
# its findings DISCARDED — so an unbounded probe against a wedged store does not
# merely stall this check, it destroys the report for the stores that answered.
# The default is sized against that budget rather than against the work: the scan
# is one narrow, server-side `--metadata-field` query per store (measured
# 2026-08-24 on the live city at 848ms TOTAL for five stores), so 10s is already
# two orders of magnitude of headroom, and five stores at the bound still land
# inside the 60s budget with room for the summary. A store that trips the bound
# is reported as NOT CHECKED and the rest of the run survives, which is the whole
# point of bounding it here instead of letting doctor abandon the check.
BOUND="${GC_DOCTOR_CHECK_TIMEOUT:-10}"

errors=()
warnings=()
notes=()

run_bounded() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "$BOUND" "$@" </dev/null
    else
        # No coreutils timeout (some macOS hosts). Degrade to an unbounded call
        # rather than skipping the check entirely.
        "$@" </dev/null
    fi
}

# `printf '%s\n' "${arr[@]}"` with an EMPTY array still prints a blank line,
# which reads as an unexplained detail row in doctor output. Print nothing.
print_lines() { [ "$#" -eq 0 ] || printf '%s\n' "$@"; }

# Bead notes and titles carry control characters often enough to abort jq
# mid-parse, which would otherwise cost a whole store. Everything below 0x20
# except the newline goes — wider than the usual pack idiom, because a literal
# TAB is just as invalid inside a JSON string and it also clears the 0x1F this
# check joins its rows on, so no payload byte can pose as a field separator.
strip_ctl() { tr -d '\000-\011\013-\037'; }

# The repository this rig checkout pushes to, host-qualified, or empty.
#
# Same parse and same fail-closed rule as merge-skill.sh's ORIGIN_REPO_Q and
# check-set-heal.sh's resolve_origin_repo_q, which is the reference
# implementation. Duplicated rather than sourced for the reason those two are:
# the pack's scripts are standalone by design, and an importer rig may be running
# an older pack. Keep them in step.
#
# Unresolvable is NOT fatal here, unlike in merge-skill where it means a merge
# could land in a repository nobody named. It only means this store's
# unqualified anchors cannot be compared against another store's; they are still
# compared against each other, and the narrowing is reported.
origin_repo_q() { # <rig checkout path>
    local url q
    url=$(run_bounded git -C "$1" remote get-url origin 2>/dev/null | tr -d '[:space:]')
    q=""
    case "$url" in
        git@github.com:*|https://github.com/*|ssh://git@github.com/*)
            q=$(printf '%s' "$url" \
                | sed -e 's#^ssh://git@github.com/##' -e 's#^git@github.com:##' \
                      -e 's#^https://github.com/##' -e 's#\.git$##' -e 's#/*$##') ;;
    esac
    # Exactly `<owner>/<repo>`, or nothing: a half-parsed value would qualify
    # anchors into a repository nobody named.
    case "$q" in
        */*/*|/*|*/) q="" ;;
        */*)         q="github.com/$q" ;;
        *)           q="" ;;
    esac
    printf '%s' "$q"
}

# ---------------------------------------------------------------------------
# The stores to scan: every rig, plus the city root (`gc rig list` includes it).
# Unreadable is a WARNING exit, never a pass: with no store list the check has
# seen nothing, and reporting that as clean is the fail-open it exists to remove.
# ---------------------------------------------------------------------------
rigs_raw=$(run_bounded gc rig list --json 2>/dev/null)
rigs_rc=$?

if [ "$rigs_rc" -ne 0 ] || [ -z "$rigs_raw" ]; then
    echo "cannot determine whether each PR has exactly one owning anchor"
    echo "\`gc rig list --json\` failed (rc=$rigs_rc) or returned nothing; there is no set of bead stores to scan."
    exit 1
fi

scopes=$(printf '%s' "$rigs_raw" \
    | jq -r '.rigs[]? | select((.path // "") != "")
             | [((.name // "") | gsub("[[:cntrl:]]"; " ")), .path]
             | join("")' 2>/dev/null)

if [ -z "$scopes" ]; then
    echo "cannot determine whether each PR has exactly one owning anchor"
    echo "\`gc rig list --json\` listed no rig paths; the listing shape changed or the output is corrupt."
    exit 1
fi

# ---------------------------------------------------------------------------
# One targeted listing per store — open beads carrying the gating marker. Each
# anchor is projected to a compact row and accumulated across stores, because
# both findings are properties of the WHOLE anchor population and not of any one
# ledger: a PR can be claimed from two different stores, and merge-skill (which
# reads only its own) would never see that pair.
# ---------------------------------------------------------------------------
ANCHORS=""
scanned=0

# US-joined, not tab: a rig whose name is empty must still yield an empty FIRST
# field and a path in the second. Under a tab IFS bash would collapse the pair,
# land the path in rig_name, leave rig_path empty, and `continue` — silently
# skipping a whole store, which is the fail-open this check exists to remove.
while IFS=$'\037' read -r rig_name rig_path; do
    [ -n "$rig_path" ] || continue

    store_label="${rig_name:-<city>}"
    origin=$(origin_repo_q "$rig_path")

    # `--metadata-field merge_result=pull_request` is the same key/value
    # merge-skill's own enumeration asks for. `--limit 0` because a windowed
    # listing silently drops anchors, and a dropped anchor is a duplicate this
    # check reports clean — merge-skill's own `--limit=200` is bounded only
    # because it re-reads every candidate live afterwards.
    beads_raw=$(run_bounded bd list --db "$rig_path/.beads" \
        --status open --metadata-field merge_result=pull_request \
        --json --limit 0 2>/dev/null)
    beads_rc=$?

    if [ "$beads_rc" -ne 0 ]; then
        warnings+=("$store_label: could not list gating anchors in $rig_path/.beads (rc=$beads_rc) — this store was NOT checked")
        continue
    fi

    # An empty store answers `[]`; an empty STRING means the probe produced
    # nothing at all, which is not the same thing and is not a pass.
    if [ -z "$beads_raw" ]; then
        warnings+=("$store_label: \`bd list\` over $rig_path/.beads returned no output — this store was NOT checked")
        continue
    fi

    rows=$(printf '%s' "$beads_raw" | strip_ctl | jq -c \
        --arg origin "$origin" \
        --arg store "$store_label" '
        .[]?
        | . as $b
        | select((($b.status // "") | ascii_downcase) == "open")
        | select((($b.metadata["merge_result"] // "") | tostring) == "pull_request")
        # repo_of / same_repo, from merge-skill.sh. `?` means the anchor records
        # no parseable pull-request URL — not that it names no repository.
        | ( (($b.metadata["pr_url"] // "") | tostring)
            | [ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/[0-9]") ]
            | .[0]
            | if . == null then "?" else (.h + "/" + .r) end ) as $r0
        # Resolve `?` against THIS store own origin, the way merge-skill resolves
        # it against its own checkout. With no origin it stays `?`.
        | (if $r0 == "?" then (if $origin == "" then "?" else $origin end) else $r0 end) as $repo
        # pr_nums_here, from merge-skill.sh: every key that names a pull request,
        # with a fork_pr_url that positively names ANOTHER repository dropped and
        # a bare number kept (the `?` fail-closed wildcard).
        | ( [ ($b.metadata["pr_number"] // empty), ($b.metadata["fork_pr"] // empty) ]
            | map(tostring)
            + ( (($b.metadata["fork_pr_url"] // "") | tostring)
                | [ capture("^[A-Za-z][A-Za-z0-9+.-]*://(?<h>[^/]+)/(?<r>[^/]+/[^/]+)/pull/(?<n>[0-9]+)") ]
                | .[0]
                | if . == null then []
                  elif ($origin == "" or (.h + "/" + .r) == $origin) then [ .n ]
                  else [] end )
            | map(select(test("^[0-9]+$"))) | unique ) as $ns
        # An anchor naming no PR at all is not part of this correspondence. It is
        # a different defect (a gating marker with nothing to gate) and a
        # different check job; counting it here would group every such anchor in
        # a store under one empty key and report them as duplicates of each other.
        | select(($ns | length) > 0)
        # The comparison key. A POSITIVE repository is comparable across stores —
        # one pull request, wherever it is claimed from. An unresolved `?` is
        # scoped to its own store, so an unknown repository can never match
        # another ledger that merely shares a number.
        | { store: $store,
            id: (($b.id // "?") | gsub("[[:cntrl:]]"; " ")),
            repo: $repo,
            repokey: (if $repo == "?" then "?" + $store else $repo end),
            ns: $ns }' 2>/dev/null)
    rows_rc=$?

    if [ "$rows_rc" -ne 0 ]; then
        warnings+=("$store_label: gating-anchor listing from $rig_path/.beads could not be parsed — this store was NOT checked")
        continue
    fi

    scanned=$((scanned + 1))
    [ -n "$rows" ] || continue

    # The `?` narrowing is reported only where it actually APPLIES — a store with
    # no resolvable origin AND at least one anchor that records no parseable
    # pr_url. Noting it unconditionally would print a permanent line on every
    # doctor run of any city whose root is not a git checkout, describing a
    # narrowing that narrowed nothing, and a note nobody can act on is how the
    # ones that matter stop being read.
    unqualified=$(printf '%s' "$rows" | jq -s -r '[ .[] | select(.repo == "?") ] | length' 2>/dev/null)
    if [ -z "$origin" ] && [ "${unqualified:-0}" -gt 0 ]; then
        notes+=("$store_label: could not resolve an origin repository for $rig_path (no origin remote, or not a github.com <owner>/<repo> URL), and $unqualified anchor(s) there record no parseable pr_url — those were compared only against each other, never against another store's")
    fi

    ANCHORS="$ANCHORS$rows
"
done <<< "$scopes"

# Every store failed to answer. Nothing was compared, so there is nothing to
# certify — say so rather than reporting the clean verdict of an empty scan.
if [ "$scanned" -eq 0 ]; then
    echo "cannot determine whether each PR has exactly one owning anchor"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "No bead store could be read, so no anchor was compared against any other. This is not a clean result."
    exit 1
fi

# ---------------------------------------------------------------------------
# Both findings, computed once over the pooled population.
# ---------------------------------------------------------------------------
findings=""
if [ -n "$(printf '%s' "$ANCHORS" | tr -d '[:space:]')" ]; then
    findings=$(printf '%s' "$ANCHORS" | jq -s -r '
        . as $all
        # (A) group every (repository, PR number) claim; more than one anchor on
        # one key is the tk-ynz4b condition.
        | ( [ $all[] | . as $a | $a.ns[]
              | { key: ($a.repokey + "" + .), n: ., repo: $a.repo,
                  id: $a.id, store: $a.store } ]
            | group_by(.key)
            | map(select(length > 1))
            | .[]
            | [ "dup", (.[0].n), (.[0].repo),
                ([ .[] | .id + " (" + .store + ")" ] | join(", ")),
                ((length) | tostring) ]
            | join("") ),
          # (B) one anchor, more than one PR number in one repository.
          ( [ $all[] | select((.ns | length) > 1) ]
            | .[]
            | [ "multi", (.ns | join(", #")), .repo,
                (.id + " (" + .store + ")"), ((.ns | length) | tostring) ]
            | join("") )' 2>/dev/null)
    findings_rc=$?
    if [ "$findings_rc" -ne 0 ]; then
        echo "cannot determine whether each PR has exactly one owning anchor"
        print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
        echo ""
        echo "The pooled anchor projection could not be evaluated (jq rc=$findings_rc); no comparison was made."
        exit 1
    fi
fi

if [ -n "$findings" ]; then
    while IFS=$'\037' read -r class a b c n; do
        [ -n "$class" ] || continue
        repo_label="$b"
        [ "$b" != "?" ] || repo_label="<unresolved repository>"
        case "$class" in
            dup)
                errors+=("$repo_label PR#$a is claimed by $n open gating anchors: $c — the merge skill validates each anchor independently, so this PR is gated by its WEAKEST anchor (coalesced into a union gate since tk-3sdfq, which merges but never retires the pair); close or demote every anchor but the owning one")
                ;;
            multi)
                errors+=("$repo_label: open gating anchor $c names $n pull requests (#$a) — neither PR has an unambiguous owner and merge-skill refuses to merge on this anchor at all; repair the metadata so exactly one PR is claimed")
                ;;
        esac
    done <<< "$findings"
fi

if [ "${#errors[@]}" -ne 0 ]; then
    echo "PR ownership is ambiguous: ${#errors[@]} finding(s)"
    print_lines "${errors[@]}"
    print_lines "${warnings[@]+"${warnings[@]}"}" "${notes[@]+"${notes[@]}"}"
    echo ""
    echo "docs/component-model.md I4: every PR has exactly one owning anchor. An owning anchor is an OPEN bead carrying metadata.merge_result=pull_request that names the PR (pr_number/fork_pr/fork_pr_url), compared within one repository — the same predicate merge-skill.sh gates on. Each finding above is invisible to every other pass until someone attempts a merge, and since tk-3sdfq a duplicate pair is coalesced and merged rather than held, so nothing retires it on its own. Repair it on the ledger: leave exactly one open anchor per PR, and exactly one PR per anchor."
    exit 2
fi

if [ "${#warnings[@]}" -ne 0 ]; then
    echo "PR ownership partially determined ($scanned store(s) checked)"
    print_lines "${warnings[@]}"
    print_lines "${notes[@]+"${notes[@]}"}"
    exit 1
fi

echo "OK: every PR named by an open gating anchor has exactly one, across $scanned store(s)"
print_lines "${notes[@]+"${notes[@]}"}"
exit 0
