#!/usr/bin/env bash
# review-run.sh — the acts of a review run's steps (formulas/mol-pr-review.toml
# and mol-pr-review-lane.toml) beyond the judgment in their text: the run's
# workspace and each step's worktree in it, what each step reads, the output a
# step writes, and every write the run makes outside its own beads, each made
# only by the step it belongs to.
#
# Every verb acts for the step this session holds, the bead `gc hook current`
# names, and reads the run's facts for it with `gctk review step`: the run, the
# PR, its branch and target, the iteration and the head it judges. A verb the
# step does not own is refused, so a lane cannot push or post.
#
# The run's result belongs to no step: the loop's check records it as it ends
# the loop (review-passed-check.sh), and the review-workspace-reap order
# removes the workspace once the run's root closes.
#
# Usage (each verb's step in brackets):
#   review-run.sh triage                          [triage]
#       stop a run that must stop, by cancelling it with no result (exit 3),
#       else make the run's workspace and triage's worktree at the head and
#       print what it reads: the change, none at a head that already passed,
#       the merges in it, the check index and the rig's guidance for triage
#       there, the asks and, at a head the repair pushed, the rulings that push
#       answers
#   review-run.sh lane --check <check>            [a lane]
#       make the lane's worktree at the head and print what the lane reads
#   review-run.sh repair                          [rule-and-repair]
#       make the run's worktree at the head and print the round to rule
#   review-run.sh output [--check <check>] [--file <path>]   [triage, a lane, rule-and-repair]
#       check the output with `gctk review output` and write it as the step's
#       gc.output_json; the file is the step's output.json in its part of the
#       workspace unless --file names another, and a lane names its check
#   review-run.sh withdraw --reason <text>        [triage]
#       withdraw the approvals a material head leaves behind (gctk pr withdraw)
#   review-run.sh push                            [rule-and-repair]
#       return the PR to draft (gctk pr draft), then push the repair's commits
#       onto the PR's branch with a lease on the head the round judged. A push
#       that fails is weighed by the branch on origin: at the repair's head it
#       landed, at the judged head nothing moved (exit 2, run it again), and at
#       any other commit the branch moved (exit 1)
#   review-run.sh post                            [triage, rule-and-repair]
#       post the round's answers on the PR (gctk pr answer): each person's post
#       an ask the round ruled carries, answered where it was made, and the
#       head's comment, or an edit of the one its mark finds, once the round has
#       ruled all it will. Triage's post answers the posts triage ruled, with
#       the comment when triage leaves rule-and-repair nothing
#   review-run.sh defer --title <text> --file <path>   [rule-and-repair]
#       file a fix outside the reviewed diff as a bead of its own, waiting on the
#       PR's bead and armed to start once it lands, its target the PR's
#   review-run.sh question --key <slug> --message <text>   [rule-and-repair]
#       put a question only a person can answer to a human gate on the PR's bead
#   review-run.sh deliver --file <capture>        [a lane]
#       deliver a demo capture to the PR (demo-deliver.sh)
#
# Prints what each verb did or read on stdout, and why it stopped on stderr.
# Exit: 0 done, or nothing to do · 1 a write did not land, and running it again
#       can change that · 2 a read did not answer · 3 refused: the run must
#       stop, the step does not own the verb, or the change does not stand ·
#       64 usage
set -uo pipefail

PROG=review-run
HERE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    sed -n '/^# Usage/,/^# Prints/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//' >&2
    exit 64
}
die() { local rc="$1"; shift; echo "$PROG: $*" >&2; exit "$rc"; }

[ "$#" -ge 1 ] || usage
VERB="$1"; shift
CHECK=""; FILE=""; REASON=""; TITLE=""; KEY=""; MESSAGE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --check)   [ "$#" -ge 2 ] || usage; CHECK="$2"; shift 2 ;;
        --file)    [ "$#" -ge 2 ] || usage; FILE="$2"; shift 2 ;;
        --reason)  [ "$#" -ge 2 ] || usage; REASON="$2"; shift 2 ;;
        --title)   [ "$#" -ge 2 ] || usage; TITLE="$2"; shift 2 ;;
        --key)     [ "$#" -ge 2 ] || usage; KEY="$2"; shift 2 ;;
        --message) [ "$#" -ge 2 ] || usage; MESSAGE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "$PROG: unknown argument '$1'" >&2; usage ;;
    esac
done

# shellcheck source=gctk-resolve.sh
. "$HERE/gctk-resolve.sh" || die 1 "cannot source gctk-resolve.sh beside this script"
gctk=$(gctk_path) || die 2 "no gctk binary to read the run with"
# gctk reads the pack's check index beside the pack's scripts directory, which
# is this script's own whatever binding the rig imports the pack under, and
# without GCTK_SCRIPTS_DIR it asks gc for the gc-toolkit binding's.
export GCTK_SCRIPTS_DIR="$HERE"

# The step this session holds, and the run's facts for it.
ID=$(gc hook current --id-only </dev/null 2>/dev/null) && [ -n "$ID" ] \
    || die 3 "gc hook current names no bead this session claimed; claim the step with gc hook --claim --json"
step_facts() {
    local out rc
    out=$("$gctk" review step "$ID" --json 2>&1); rc=$?
    case "$rc" in
        0) FACTS=$out ;;
        3) die 3 "${out#gctk review step: }" ;;
        *) die 2 "${out#gctk review step: }" ;;
    esac
}
fact() { printf '%s' "$FACTS" | jq -r "$1 // empty"; }

# owns <step>... — refuse a verb this step does not own.
owns() {
    local s
    for s in "$@"; do [ "$STEP" = "$s" ] && return 0; done
    die 3 "$VERB belongs to the run's $* step, and this session holds $ID ($(fact .ref))"
}

load() {
    step_facts
    RUN=$(fact .run); PR_BEAD=$(fact .pr_bead); PR=$(fact .pr); BRANCH=$(fact .branch)
    TARGET=$(fact .target); HEAD=$(fact .head); N=$(fact .iteration)
    case "$(fact .output)" in
        triage) STEP=triage ;; lane) STEP=lane ;; repair) STEP=rule-and-repair ;; *) STEP=other ;;
    esac
    WS=$("$HERE/review-workspace.sh" path --root "$RUN") || die 1 "no workspace path for $RUN"
}

# The rig's checkout, with the PR's branch and target fetched and the head held.
repo() {
    REPO=$("$HERE/rig-root.sh") && [ -n "$REPO" ] || die 2 "cannot resolve the rig's checkout"
    git -C "$REPO" fetch --quiet --no-tags origin "$TARGET" "$BRANCH" || die 2 "git fetch of $TARGET and $BRANCH did not answer"
    if ! git -C "$REPO" cat-file -e "$HEAD^{commit}" 2>/dev/null; then
        git -C "$REPO" fetch --quiet --no-tags origin "$HEAD" || die 2 "cannot fetch $HEAD"
    fi
}

# worktree <part flag...> — the step's worktree at the head, in WT. It sets WT
# rather than printing the path, so a worktree that did not land stops the
# verb here and not only a subshell. The repair's worktree is kept when it is
# at the head or past it, and one at any other commit is refused, which stops
# the run (exit 3).
worktree() {
    local rc
    WT=$("$HERE/review-workspace.sh" add --root "$RUN" "$@" --oid "$HEAD" --repo "$REPO"); rc=$?
    case "$rc" in
        0) [ -n "$WT" ] || die 1 "the worktree did not land" ;;
        3) die 3 "the run's worktree holds work that is not on $HEAD, the head the round judged, or past it, so it is kept as it stands and the run must stop" ;;
        *) die 1 "the worktree did not land" ;;
    esac
}

print_run() {
    printf '%s\n' "== The run: $RUN, reviewing $PR ($PR_BEAD) from $BRANCH into $TARGET"
    [ -z "$N" ] || [ "$N" = 0 ] || printf '%s\n' "== Iteration $N, at the head $HEAD"
    return 0
}

print_change() { # <worktree>
    local from why range
    from=$(fact .change.from); why=$(fact .change.why)
    if [ "$from" = "$HEAD" ]; then
        printf '%s\n' "== The change to judge: none, because $why: pick only the checks an ask open on $PR_BEAD sends back"
        return 0
    fi
    if [ -n "$from" ]; then
        range="$from..$HEAD"
        git -C "$1" cat-file -e "$from^{commit}" 2>/dev/null || git -C "$1" fetch --quiet --no-tags origin "$from" || die 2 "cannot fetch $from"
    else
        range="origin/$TARGET...$HEAD"
    fi
    printf '%s\n' "== The change to judge: git diff $range ($why)"
    git -C "$1" diff --stat "$range" || die 2 "git diff $range did not read"
    local merges
    merges=$(git -C "$1" log --merges --format='%H %s' "${range/.../..}" 2>/dev/null)
    if [ -n "$merges" ]; then
        printf '%s\n' "== Merges in it: read each with git show --remerge-diff <commit>, and its message, which says what collided"
        printf '%s\n' "$merges"
    fi
}

# A run that must stop ends with no result: the cancel closes its root, the
# root's edge stops holding the PR's bead, and the landing order pours a fresh
# run once the refinery validates the PR's live head. Triage's read asks it at
# every head before triage judges, the run's first head and each push of its
# repair. A step whose run does not read as one, such as a run poured with an
# empty record, stops the same way when the step is triage's.
stands() {
    local out rc row ref
    out=$("$gctk" review step "$ID" --json --stands 2>&1); rc=$?
    case "$rc" in
        0) return 0 ;;
        3)
            row=$(gc bd show "$ID" --json 2>/dev/null) \
                || die 2 "${out#gctk review step: }; whether $ID is triage's step did not read, so nothing is cancelled"
            ref=$(printf '%s' "$row" | jq -r '.[0].metadata["gc.step_ref"] // empty' 2>/dev/null)
            case "$ref" in *.triage) ;; *) die 3 "${out#gctk review step: }" ;; esac
            echo "$PROG: ${out#gctk review step: }" >&2
            "$HERE/decline.sh" --step review-loop --reason "${out#gctk review step: }" \
                || die 1 "the run must stop, and its cancel did not land: run this again"
            exit 3 ;;
        # The run's check did not answer, so whether it stands is unknown.
        *) die 2 "${out#gctk review step: }" ;;
    esac
}

cmd_triage() {
    stands
    load; owns triage; repo
    local wt
    worktree --triage; wt=$WT
    print_run
    print_change "$wt"
    printf '%s\n' "== The check index at $HEAD"
    (cd "$wt" && "$gctk" review checks --at "$HEAD") || die 2 "the check index at $HEAD did not read"
    printf '%s\n' "== The rig's guidance for triage at $HEAD, empty when it keeps none"
    (cd "$wt" && "$gctk" review guidance triage --at "$HEAD") || die 2 "the rig's guidance for triage at $HEAD did not read"
    printf '%s\n' "== The run so far, and the asks open on $PR_BEAD"
    "$gctk" review passed "$ID" --explain || true
    if [ "$N" -gt 1 ]; then
        printf '%s\n' "== The round before, whose push this head may be"
        "$gctk" review passed "$ID" --iteration "$((N - 1))" --explain || true
    fi
    printf '%s\n' "== The run's workspace: $WS" "== Triage's worktree: $wt" "== Write the output to: ${wt%/wt}/output.json"
}

cmd_lane() {
    [ -n "$CHECK" ] || usage
    load; owns lane; repo
    local wt
    worktree --lane "$CHECK"; wt=$WT
    print_run
    printf '%s\n' "== The PR as published: $PR"
    gh pr view "$PR" --json title,body --jq '.title, "", .body' || die 2 "gh pr view $PR did not answer"
    printf '%s\n' "== The change: git diff origin/$TARGET...HEAD in the worktree"
    git -C "$wt" diff --stat "origin/$TARGET...HEAD" || die 2 "the diff did not read"
    printf '%s\n' "== The rig's guidance for $CHECK at $HEAD, empty when it keeps none"
    (cd "$wt" && "$gctk" review guidance "$CHECK" --at "$HEAD") || die 2 "the guidance did not read"
    printf '%s\n' "== What gctk rig recorded at $HEAD"
    "$HERE/review-evidence.sh" --anchor "$PR_BEAD" --commit "$HEAD" --worktree "$wt" || die 2 "the evidence did not read"
    printf '%s\n' "== The lane's worktree: $wt" "== The lane's files, its capture and its output among them: ${wt%/wt}" \
        "== Write the output to: ${wt%/wt}/output.json"
}

cmd_repair() {
    load; owns rule-and-repair; repo
    local wt ahead edits
    worktree --repair; wt=$WT
    print_run
    ahead=$(git -C "$wt" log --oneline "$HEAD..HEAD") || die 2 "the run's worktree does not read"
    edits=$(git -C "$wt" status --short) || die 2 "the run's worktree does not read"
    if [ -n "$ahead$edits" ]; then
        printf '%s\n' "== The round's work already in the run's worktree, kept as it stands: its commits past $HEAD, then its uncommitted edits"
        [ -z "$ahead" ] || printf '%s\n' "$ahead"
        [ -z "$edits" ] || printf '%s\n' "$edits"
    fi
    printf '%s\n' "== The round to rule"
    "$gctk" review passed "$ID" --explain || true
    printf '%s\n' "== Each lane's files, its evidence on disk"
    for d in "$WS"/lane-*; do [ -d "$d" ] && printf '%s\n' "$d"; done
    printf '%s\n' "== The run's worktree, at the head: $wt" "== Write the output to: ${wt%/wt}/output.json"
}

cmd_output() {
    load; owns triage lane rule-and-repair
    if [ -z "$FILE" ]; then
        case "$STEP" in
            triage) FILE="$WS/triage/output.json" ;;
            rule-and-repair) FILE="$WS/repair/output.json" ;;
            lane) [ -n "$CHECK" ] || die 64 "a lane names its check: output --check <check>"; FILE="$WS/lane-$CHECK/output.json" ;;
        esac
    fi
    [ -s "$FILE" ] || die 64 "$FILE holds no output; write it there first"
    local json rc
    json=$("$gctk" review output "$ID" --file "$FILE"); rc=$?
    case "$rc" in
        0) ;;
        3) exit 3 ;;
        1) exit 64 ;;
        *) exit 2 ;;
    esac
    gc bd update "$ID" --set-metadata "gc.output_json=$json" >/dev/null || die 1 "the output of $ID did not land"
    echo "$PROG: wrote the $(fact .output) output of $ID"
}

cmd_withdraw() {
    [ -n "$REASON" ] || usage
    load; owns triage
    "$gctk" pr withdraw "$PR_BEAD" --head "$HEAD" --reason "$REASON"
}

cmd_push() {
    load; owns rule-and-repair
    local wt new
    wt="$WS/repair/wt"
    [ -d "$wt" ] || die 3 "the run has no worktree at $wt; review-run.sh repair makes it"
    new=$(git -C "$wt" rev-parse HEAD) || die 2 "the run's worktree does not read"
    if [ "$new" = "$HEAD" ]; then echo "$PROG: nothing to push: the worktree is at the head the round judged"; return 0; fi
    git -C "$wt" merge-base --is-ancestor "$HEAD" "$new" || die 3 "$new does not descend from $HEAD, so the push is no fast-forward"
    local rc
    (cd "$wt" && "$gctk" pr draft "$PR_BEAD"); rc=$?
    case "$rc" in
        0) ;;
        3) die 3 "gctk pr draft refused, so nothing is pushed" ;;
        *) die 2 "the PR may still be ready, so nothing is pushed" ;;
    esac
    if ! git -C "$wt" push --quiet --force-with-lease="refs/heads/$BRANCH:$HEAD" origin "HEAD:refs/heads/$BRANCH"; then
        # git exits non-zero both for a lease the branch no longer matches and
        # for a push that never reached origin, so the branch on origin says
        # which: only a branch at another commit means the run's head is gone.
        local at
        at=$(git -C "$wt" ls-remote origin "refs/heads/$BRANCH") \
            || die 2 "the push onto $BRANCH did not land, and the branch on origin did not read, so nothing says it moved from $HEAD: run it again"
        at=$(printf '%s' "$at" | cut -f1)
        case "$at" in
            "$new") echo "$PROG: the push reported a failure, and $BRANCH is at $new on origin, so the repair's commits are there" >&2 ;;
            "$HEAD") die 2 "the push onto $BRANCH did not land, and the branch is still at $HEAD, the head the round judged: run it again" ;;
            *) die 1 "the push onto $BRANCH did not land: the branch moved from $HEAD, the head the round judged, to ${at:-no commit, deleted}" ;;
        esac
    fi
    echo "$new"
}

# The round's answers are gctk's to make (gctk pr answer), from the run's
# worktree when the repair's read made it, else the rig's checkout, whose
# origin names the PR's repository. Its exits are this script's own.
cmd_post() {
    load; owns triage rule-and-repair
    local dir="$WS/repair/wt"
    if [ ! -d "$dir" ]; then
        dir=$("$HERE/rig-root.sh") && [ -n "$dir" ] || die 2 "cannot resolve the rig's checkout"
    fi
    (cd "$dir" && "$gctk" pr answer "$RUN" --iteration "$N")
}

# A deferred fix is a task that waits on the PR's bead. bd keeps one edge
# between two beads, so that wait is the task's only edge onto the PR's bead,
# and the create writes it with the task. The task an earlier call filed is
# found by its title and that wait. A found task that is open and carries no
# arm and no route gets the arm that call did not make, and any other found
# task is left as it stands.
cmd_defer() {
    [ -n "$TITLE" ] && [ -n "$FILE" ] || usage
    load; owns rule-and-repair
    [ -s "$FILE" ] || die 64 "--file $FILE holds no description"
    local pool rows found id status routed arm
    pool=$(gc bd show "$RUN" --json 2>/dev/null | jq -r '.[0].metadata["gc.var.repair_target"] // empty')
    [ -n "$pool" ] || die 1 "the run names no repair pool to arm a deferred fix for, so nothing is filed"
    rows=$(gc bd list --all --title-contains "$TITLE" --json --limit 0 2>/dev/null) \
        || die 2 "the beads titled '$TITLE' did not read, so whether this fix is filed is unknown"
    found=$(printf '%s' "$rows" | jq -r --arg t "$TITLE" --arg pr "$PR_BEAD" '[.[]? | select(.title == $t)
        | select(any(.dependencies[]?; (.depends_on_id // .id) == $pr and (.dependency_type // .type) == "blocks"))][0]
        // empty | [.id, (.status // ""), (.metadata["gc.routed_to"] // "")] | join("\u001f")') \
        || die 2 "the beads titled '$TITLE' did not decode, so whether this fix is filed is unknown"
    if [ -z "$found" ]; then
        id=$(gc bd create "$TITLE" -t task -d "$(cat "$FILE")" --deps "blocked-by:$PR_BEAD" \
            --metadata "$(jq -cn --arg t "$TARGET" '{target: $t}')" --json \
            | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
        [ -n "$id" ] || die 1 "the create returned no bead; a retry finds one that landed"
    else
        IFS=$'\x1f' read -r id status routed <<< "$found"
        if [ "$status" != open ] || [ -n "$routed" ]; then
            echo "$id"
            echo "$PROG: $id already carries this fix, ${routed:+routed to $routed and }at status $status, so it is not armed" >&2
            return 0
        fi
        arm=$("$gctk" bead holds "$id" 2>/dev/null \
            | jq -r --arg id "$id" 'select(.id == $id) | if .error then "unread" elif .arm then "armed" else "none" end')
        case "$arm" in
            armed) echo "$id"; echo "$PROG: $id already carries this fix, armed" >&2; return 0 ;;
            none) ;;
            *) die 2 "whether $id carries its arm did not read" ;;
        esac
    fi
    "$gctk" bead arm "$id" --target "$pool" --on mol-polecat-work \
        --reason "deferred by review run $RUN: a fix outside the diff of $PR, started once $PR_BEAD lands" >/dev/null \
        || die 1 "$id waits on $PR_BEAD and its arm did not land; run this again"
    echo "$id"
}

cmd_question() {
    [ -n "$KEY" ] && [ -n "$MESSAGE" ] || usage
    case "$KEY" in *[!a-z0-9-]*) die 64 "--key takes a slug of a-z, 0-9 and -, got '$KEY'" ;; esac
    load; owns rule-and-repair
    "$HERE/human-gate.sh" --subject "$PR_BEAD" --key "review-question-$KEY" --message "$MESSAGE" \
        || die 1 "the gate did not land"
}

cmd_deliver() {
    [ -n "$FILE" ] || usage
    load; owns lane
    [ -s "$FILE" ] || die 64 "--file $FILE is empty or missing"
    "$HERE/demo-deliver.sh" --file "$FILE" --pr "$PR"
}

case "$VERB" in
    triage|lane|repair|output|withdraw|push|post|defer|question|deliver) "cmd_$VERB" ;;
    *) usage ;;
esac
