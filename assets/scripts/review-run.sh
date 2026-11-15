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
# step does not own is refused, so a lane cannot push and triage cannot post.
#
# A shadow run (its shadow var reads true) writes nothing outside itself. Each
# verb that would write prints what it would have written instead, and the
# repair's are kept in <workspace>/repair/shadow-writes.txt, which its output
# carries. A demo lane's capture stays in the run's workspace.
#
# Usage (each verb's step in brackets):
#   review-run.sh prepare                         [prepare]
#       stop a run that must stop, by cancelling it with no result (exit 3),
#       else make its workspace and print the run
#   review-run.sh triage                          [triage]
#       make triage's worktree at the head and print what it reads: the change,
#       the merges in it, the check index there, the asks and, at a head the
#       repair pushed, the rulings that push answers
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
#       onto the PR's branch with a lease on the head the round judged
#   review-run.sh post                            [rule-and-repair]
#       post the head's comment (gctk review comment), or edit the one its mark
#       finds, through pr-post.sh
#   review-run.sh defer --title <text> --file <path>   [rule-and-repair]
#       file a fix outside the reviewed diff as a bead of its own, waiting on the
#       PR's bead and armed to start once it lands, its target the PR's
#   review-run.sh question --key <slug> --message <text>   [rule-and-repair]
#       put a question only a person can answer to a human gate on the PR's bead
#   review-run.sh deliver --file <capture>        [a lane]
#       deliver a demo capture to the PR (demo-deliver.sh)
#   review-run.sh record                          [record]
#       record the run's result (gctk review record), ask a person through a
#       gate when the loop exhausted its attempts, and remove the workspace
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
    TARGET=$(fact .target); HEAD=$(fact .head); N=$(fact .iteration); SHADOW=$(fact .shadow)
    case "$(fact .output)" in
        triage) STEP=triage ;; lane) STEP=lane ;; repair) STEP=rule-and-repair ;;
        *) case "$(fact .ref)" in *.prepare) STEP=prepare ;; *.record) STEP=record ;; *) STEP=other ;; esac ;;
    esac
    WS=$("$HERE/review-workspace.sh" path --root "$RUN") || die 1 "no workspace path for $RUN"
    SHADOW_WRITES="$WS/repair/shadow-writes.txt"
}

# would <line> — what a shadow run's step would have written, kept for its output.
would() {
    echo "shadow run: wrote nothing: $1"
    if [ "$STEP" = rule-and-repair ]; then
        mkdir -p "$WS/repair" && printf '%s\n' "$1" >> "$SHADOW_WRITES"
    fi
}

# The rig's checkout, with the PR's branch and target fetched and the head held.
repo() {
    REPO=$("$HERE/rig-root.sh") && [ -n "$REPO" ] || die 2 "cannot resolve the rig's checkout"
    git -C "$REPO" fetch --quiet --no-tags origin "$TARGET" "$BRANCH" || die 2 "git fetch of $TARGET and $BRANCH did not answer"
    if ! git -C "$REPO" cat-file -e "$HEAD^{commit}" 2>/dev/null; then
        git -C "$REPO" fetch --quiet --no-tags origin "$HEAD" || die 2 "cannot fetch $HEAD"
    fi
}

worktree() { # <part flag...> — the step's worktree at the head
    "$HERE/review-workspace.sh" add --root "$RUN" "$@" --oid "$HEAD" --repo "$REPO" || die 1 "the worktree did not land"
}

print_run() {
    printf '%s\n' "== The run: $RUN, reviewing $PR ($PR_BEAD) from $BRANCH into $TARGET"
    [ "$SHADOW" = true ] && printf '%s\n' "== A shadow run: it writes nothing outside itself"
    [ -z "$N" ] || [ "$N" = 0 ] || printf '%s\n' "== Iteration $N, at the head $HEAD"
    return 0
}

print_change() { # <worktree>
    local from why range
    from=$(fact .change.from); why=$(fact .change.why)
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
# run once the refinery validates the PR's live head.
cmd_prepare() {
    local out rc ref
    out=$("$gctk" review step "$ID" --json --prepare 2>&1); rc=$?
    if [ "$rc" = 3 ]; then
        ref=$("$gctk" review step "$ID" --json 2>/dev/null | jq -r '.ref // empty')
        [ "$ref" = mol-pr-review.prepare ] || die 3 "${out#gctk review step: }"
        echo "$PROG: ${out#gctk review step: }" >&2
        "$HERE/decline.sh" --step mol-pr-review.prepare --reason "${out#gctk review step: }" \
            || die 1 "the run must stop, and its cancel did not land: run this again"
        exit 3
    fi
    load
    owns prepare
    { mkdir -p "$WS" && chmod 700 "$WS"; } || die 1 "cannot make the run's workspace $WS"
    print_run
    printf '%s\n' "== The run's workspace: $WS"
}

cmd_triage() {
    load; owns triage; repo
    local wt
    wt=$(worktree --triage)
    print_run
    print_change "$wt"
    printf '%s\n' "== The check index at $HEAD"
    (cd "$wt" && "$gctk" review checks --at "$HEAD") || die 2 "the check index at $HEAD did not read"
    printf '%s\n' "== The run so far, and the asks open on $PR_BEAD"
    "$gctk" review passed "$ID" --explain || true
    if [ "$N" -gt 1 ]; then
        printf '%s\n' "== The round before, whose push this head may be"
        "$gctk" review passed "$ID" --iteration "$((N - 1))" --explain || true
    fi
    printf '%s\n' "== Triage's worktree: $wt" "== Write the output to: ${wt%/wt}/output.json"
}

cmd_lane() {
    [ -n "$CHECK" ] || usage
    load; owns lane; repo
    local wt
    wt=$(worktree --lane "$CHECK")
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
    local wt
    wt=$(worktree --repair)
    print_run
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
    local json rc writes=()
    [ "$SHADOW" = true ] && [ "$STEP" = rule-and-repair ] && writes=(--writes "$SHADOW_WRITES")
    json=$("$gctk" review output "$ID" --file "$FILE" ${writes[@]+"${writes[@]}"}); rc=$?
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
    if [ "$SHADOW" = true ]; then would "withdraw: the approvals given before $HEAD: $REASON"; return 0; fi
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
    if [ "$SHADOW" = true ]; then
        would "push: $(git -C "$wt" rev-list --count "$HEAD..$new") commit(s) onto $BRANCH, to $new"
        return 0
    fi
    local rc
    (cd "$wt" && "$gctk" pr draft "$PR_BEAD"); rc=$?
    case "$rc" in
        0) ;;
        3) die 3 "gctk pr draft refused, so nothing is pushed" ;;
        *) die 2 "the PR may still be ready, so nothing is pushed" ;;
    esac
    git -C "$wt" push --quiet --force-with-lease="refs/heads/$BRANCH:$HEAD" origin "HEAD:refs/heads/$BRANCH" \
        || die 1 "the push onto $BRANCH did not land: the branch may have moved from $HEAD"
    echo "$new"
}

cmd_post() {
    load; owns rule-and-repair
    local body file mark host repo number id
    body=$("$gctk" review comment "$RUN" --iteration "$N") || die 2 "the head's comment did not render"
    if [ -z "$body" ]; then echo "$PROG: nothing to answer at $HEAD, so nothing is posted"; return 0; fi
    if [ "$SHADOW" = true ]; then
        printf '%s\n' "$body"
        echo "shadow run: posted nothing; the round's output carries this comment"
        return 0
    fi
    [[ "$PR" =~ ^https://([^/]+)/([^/]+/[^/]+)/pull/([0-9]+)$ ]] || die 3 "$PR is not a PR's URL"
    host=${BASH_REMATCH[1]}; repo=${BASH_REMATCH[2]}; number=${BASH_REMATCH[3]}
    mark=$(printf '%s\n' "$body" | head -1)
    id=$(gh api --hostname "$host" "repos/$repo/issues/$number/comments" --paginate \
        --jq ".[] | select(.body | contains($(jq -Rn --arg m "$mark" '$m'))) | .id" | head -1) \
        || die 2 "the PR's comments did not read"
    file="$WS/repair/comment-$N.md"
    { mkdir -p "$WS/repair" && printf '%s\n' "$body" > "$file"; } || die 1 "cannot write $file"
    if [ -n "$id" ]; then
        "$HERE/pr-post.sh" edit --repo "$host/$repo" --comment "$id" --body-file "$file" >/dev/null \
            || die 1 "the edit of comment $id did not land"
        echo "$PROG: edited the comment for $HEAD ($id)"
    else
        "$HERE/pr-post.sh" comment --repo "$host/$repo" --pr "$number" --body-file "$file" || die 1 "the comment did not post"
    fi
}

cmd_defer() {
    [ -n "$TITLE" ] && [ -n "$FILE" ] || usage
    load; owns rule-and-repair
    [ -s "$FILE" ] || die 64 "--file $FILE holds no description"
    if [ "$SHADOW" = true ]; then would "bead: $TITLE, waiting on $PR_BEAD and armed to start once it lands"; return 0; fi
    local found new pool
    found=$(gc bd list --all --title-contains "$TITLE" --json --limit 0 2>/dev/null \
        | jq -r --arg t "$TITLE" --arg pr "$PR_BEAD" '.[]? | select(.title == $t)
            | select([.dependencies[]? | select((.depends_on_id // .id) == $pr and (.dependency_type // .type) == "discovered-from")] | length > 0)
            | .id' | head -1)
    if [ -n "$found" ]; then echo "$found"; echo "$PROG: $found already carries this fix" >&2; return 0; fi
    new=$(gc bd create "$TITLE" -t task -d "$(cat "$FILE")" --deps "discovered-from:$PR_BEAD" \
        --metadata "$(jq -cn --arg t "$TARGET" '{target: $t}')" --json \
        | jq -r 'if type == "array" then (.[0].id // empty) else (.id // empty) end' 2>/dev/null)
    [ -n "$new" ] || die 1 "the create returned no bead; a retry finds one that landed"
    gc bd dep add "$new" "$PR_BEAD" --type=blocks >/dev/null || die 1 "$new is filed and its wait on $PR_BEAD did not land"
    pool=$(gc bd show "$RUN" --json 2>/dev/null | jq -r '.[0].metadata["gc.var.repair_target"] // empty')
    [ -n "$pool" ] || die 1 "$new waits on $PR_BEAD and is not armed: the run names no repair pool"
    "$gctk" bead arm "$new" --target "$pool" --on mol-polecat-work \
        --reason "deferred by review run $RUN: a fix outside the diff of $PR, started once $PR_BEAD lands" >/dev/null \
        || die 1 "$new waits on $PR_BEAD and its arm did not land"
    echo "$new"
}

cmd_question() {
    [ -n "$KEY" ] && [ -n "$MESSAGE" ] || usage
    case "$KEY" in *[!a-z0-9-]*) die 64 "--key takes a slug of a-z, 0-9 and -, got '$KEY'" ;; esac
    load; owns rule-and-repair
    if [ "$SHADOW" = true ]; then would "gate review-question-$KEY on $PR_BEAD: $MESSAGE"; return 0; fi
    "$HERE/human-gate.sh" --subject "$PR_BEAD" --key "review-question-$KEY" --message "$MESSAGE" \
        || die 1 "the gate did not land"
}

cmd_deliver() {
    [ -n "$FILE" ] || usage
    load; owns lane
    [ -s "$FILE" ] || die 64 "--file $FILE is empty or missing"
    if [ "$SHADOW" = true ]; then would "deliver: $FILE, kept in the run's workspace"; return 0; fi
    "$HERE/demo-deliver.sh" --file "$FILE" --pr "$PR"
}

cmd_record() {
    load; owns record
    local out rc
    out=$("$gctk" review record "$RUN" 2>&1); rc=$?
    printf '%s\n' "$out"
    case "$rc" in
        0) ;;
        3) exit 3 ;;
        *) exit 2 ;;
    esac
    local last
    last=$(printf '%s\n' "$out" | sed -n 's/.*: the loop exhausted its attempts at \([0-9a-f]*\)$/\1/p' | head -1)
    if [ -n "$last" ]; then
        local explain
        explain=$("$gctk" review passed "$RUN" --explain 2>&1)
        if [ "$SHADOW" = true ]; then
            echo "shadow run: wrote nothing: gate review-loop-exhausted on $PR_BEAD, at $last"
        else
            "$HERE/human-gate.sh" --subject "$PR_BEAD" --key review-loop-exhausted --message "$(printf '%s\n\n%s' \
                "Review run $RUN exhausted its attempts at $last without a passed head, so $PR waits for you. Clearing this gate has the landing order pour a fresh run." \
                "$explain")" || die 1 "the result is recorded and the review-loop-exhausted gate did not land"
        fi
    fi
    if [ "$SHADOW" = true ]; then
        echo "shadow run: its workspace stays for the comparison until the reap order takes it: $WS"
        return 0
    fi
    "$HERE/review-workspace.sh" remove --root "$RUN" || die 1 "the run's workspace was not removed; the reap order takes it"
}

case "$VERB" in
    prepare|triage|lane|repair|output|withdraw|push|post|defer|question|deliver|record) "cmd_$VERB" ;;
    *) usage ;;
esac
