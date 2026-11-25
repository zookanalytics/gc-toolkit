#!/usr/bin/env bash
# tests.test.sh — guards the draft CI-cost gate in tests.yml, the concurrency
# group each job holds, the all-tests command each job runs, the jq check each
# job runs before it, the seconds each job keeps, the tools test-macos checks
# before its tests, and the jobs whose checks main's ruleset requires.
#
# A draft pull request must not run the tests, so a change still taking
# follow-up commits does not spend Actions minutes on every push. A push to
# main and a manual dispatch must always run them, and marking a draft ready
# must run them. Those are the invariants the draft gate rests on, and every
# job must hold them: a regression that drops any one spends minutes on drafts
# or skips CI where it is required. The draft flag carries no workflow state;
# this gate is only a CI-cost lever.
#
# CI runs every test in the repository, so every job runs the all-tests
# command, `make test`, which runs the Go tests, the board web app's checks and
# every shell suite, with every core and the suite's seconds kept.
#
# Every job runs check-jq.sh before the tests, so a job whose runner resolves a
# jq older than 1.8 fails by name instead of running the tests on it.
#
# Every job keeps each shell suite run's seconds for the size comment's section
# on the suite's time: it writes them with --seconds, shows them in its job
# summary and uploads them as suite-times-<job> unless the run was cancelled,
# in steps whose failure fails no check, and suite-time.sh, which reads them
# back, names the same jobs. A job that kept none, or kept them under another
# name, would show no time.
#
# Each job holds a concurrency group of its own, named for the workflow, the
# job and the ref, that cancels the run in progress, and the workflow holds
# none. A job that a draft skips never starts, so a draft's run cancels no run,
# such as the one that marking the pull request ready started, which the city's
# merge would then wait to see run again. A group on the workflow would let a
# draft's run cancel that run, a group without the ref would let one pull
# request's run cancel another's, and jobs that shared a group would cancel
# each other. The job's id is written into its group, since github.job is null
# outside a job's steps and would put every job in one group.
#
# No job runs go test on a list of packages, because a list keeps a check only
# for the packages it names.
#
# test-macos's tool check names each tool whose absence makes a test skip
# rather than fail, so a runner without one fails the step by name: lsof
# (internal/host in gctk, and suites' cases), flock (the pr package's lock
# test, and the scripts that lock with it) and tmux (tmux-intake-prompt's
# case), with bash 5 and jq 1.8 checked by version (the board's tests that
# answer from the stub store, stubStore in services/helm/internal/rigboard,
# need both).
#
# Main's ruleset requires a check for every job here, by the job's id, and
# REQUIRED below lists them as
# `gh api repos/<owner>/<repo>/rules/branches/main` does. A job missing from
# REQUIRED fails this suite, so a change that adds a job also says it is to be
# required, and the operator's edit to the ruleset goes with it. A job's check
# takes the job's id unless the job sets name: or a matrix, and either one
# renames it, so every merge would wait on a check that never reports. Each job
# has the draft gate as its whole if:, since a condition of its own that
# skipped it at a ready head would leave that head only a skipped result,
# which holds the merge.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF="$HERE/tests.yml"

[ -f "$WF" ] || { echo "tests.test.sh: cannot find tests.yml at $WF" >&2; exit 2; }

fail=0
note() { echo "tests.test.sh: FAIL — $1" >&2; fail=1; }

# Specifying types replaces GitHub's default activity set, so the three defaults
# must stay listed or normal pull requests stop running the suite, and
# ready_for_review must be present so the draft-to-ready flip runs it.
types_line="$(grep -E '^[[:space:]]*types:' "$WF" || true)"
for t in opened synchronize reopened ready_for_review; do
    grep -Eq "\\b$t\\b" <<<"$types_line" || note "pull_request types must include '$t'"
done

# The jobs under jobs:, as one "<job>" line per job and one "<job>\t<key>\t<value>"
# line per key the job sets at its own level. tests.yml puts a job id at a
# two-space indent and the job's keys at four.
job_keys() {
    awk '
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); print job; next }
        job != "" && /^    [A-Za-z0-9_-]+:/ {
            key = $1; sub(/:$/, "", key)
            val = $0; sub(/^    [A-Za-z0-9_-]+:[[:space:]]*/, "", val)
            print job "\t" key "\t" val
        }' "$WF"
}
keys="$(job_keys)"
jobs="$(awk -F'\t' 'NF == 1 { print $1 }' <<<"$keys")"
[ -n "$jobs" ] || note "found no jobs under 'jobs:' in tests.yml"

# Each job gates on the pull request not being a draft, and non-pull_request
# events (a push to main, a manual dispatch) carry no draft field, so the
# event-name guard keeps them running.
for j in $jobs; do
    gate="$(awk -F'\t' -v j="$j" '$1 == j && $2 == "if" { print $3 }' <<<"$keys")"
    grep -Fq "draft == false" <<<"$gate" \
        || note "job '$j' must gate on 'draft == false' so a draft pull request skips the suite"
    grep -Fq "github.event_name != 'pull_request'" <<<"$gate" \
        || note "job '$j' must let non-pull_request events run, or pushes to main stop running the suite"
done

# The first line outside a comment in each job that runs check-jq.sh, and the
# first that runs the tests, as one "<job>\t<line>\t<line>" row per job, with
# 0 for a job that runs neither.
jq_check_lines() {
    awk '
        function flush() { if (job != "") print job "\t" check "\t" suite; job = "" }
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { flush(); in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); check = 0; suite = 0; next }
        /^[[:space:]]*#/ { next }
        job != "" && check == 0 && /check-jq\.sh/ { check = NR }
        job != "" && suite == 0 && /make test / { suite = NR }
        END { flush() }' "$WF"
}
suite_jobs=0
while IFS=$'\t' read -r j check suite; do
    if [ "$suite" -eq 0 ]; then
        note "job '$j' must run the all-tests command, make test, since CI runs every test"
        continue
    fi
    suite_jobs=$((suite_jobs + 1))
    if [ "$check" -eq 0 ]; then
        note "job '$j' must run check-jq.sh, or it runs the tests on whatever jq its runner resolves"
    elif [ "$check" -gt "$suite" ]; then
        note "job '$j' must run check-jq.sh before the tests, not after them"
    fi
done < <(jq_check_lines)
# A job counts as running the tests when it runs make test, so with no such job
# the check above has checked nothing.
[ "$suite_jobs" -gt 0 ] \
    || note "found no job that runs make test in tests.yml, so the jq check checked no job"

# The lines of a job that are not comments.
job_lines() {
    awk -v j="$1" '
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); next }
        job == j && !/^[[:space:]]*#/' "$WF"
}
suite_names=""
while IFS=$'\t' read -r j check suite; do
    [ "$suite" -gt 0 ] || continue
    suite_names="$suite_names $j"
    lines="$(job_lines "$j")"
    for want in 'run: make test RUN_TESTS_FLAGS="-j $(getconf _NPROCESSORS_ONLN) --seconds $RUNNER_TEMP/suite-times.tsv"' \
        'run: bash .github/workflows/suite-time.sh summary "$RUNNER_TEMP/suite-times.tsv" >> "$GITHUB_STEP_SUMMARY"' \
        'name: suite-times-${{ github.job }}' 'path: ${{ runner.temp }}/suite-times.tsv'; do
        grep -Fq -- "$want" <<<"$lines" || note "job '$j' must run every test on every core and keep each run's seconds: it lacks '$want'"
    done
    [ "$(grep -cF 'if: ${{ !cancelled() }}' <<<"$lines")" -ge 2 ] \
        || note "job '$j' must show and upload the seconds unless the run was cancelled, so a failed suite keeps them too"
    [ "$(grep -cF 'continue-on-error: true' <<<"$lines")" -ge 2 ] \
        || note "job '$j' must let the steps that keep the seconds fail without failing the check"
done < <(jq_check_lines)
listed="$(sed -n 's/^SUITES=(\(.*\))$/\1/p' "$HERE/suite-time.sh" | tr ' ' '\n' | sort | paste -sd' ' -)"
ran="$(tr ' ' '\n' <<<"$suite_names" | grep -v '^$' | sort | paste -sd' ' -)"
[ "$listed" = "$ran" ] \
    || note "suite-time.sh's SUITES ($listed) must name the jobs that run the suite ($ran)"

! grep -Eq '^concurrency:' "$WF" \
    || note "the workflow must hold no concurrency group, or a draft's run, whose jobs all skip, can cancel the run that marking the pull request ready started"

# The concurrency keys each job sets, as one "<job>\t<key>\t<value>" line per
# key under the job's concurrency:, which sits at a four-space indent and its
# keys at six.
job_concurrency() {
    awk '
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { job = $1; sub(/:$/, "", job); in_c = 0; next }
        /^    concurrency:[[:space:]]*$/ { in_c = 1; next }
        /^    [^[:space:]]/ { in_c = 0 }
        in_c && /^      [A-Za-z0-9_-]+:/ {
            key = $1; sub(/:$/, "", key)
            val = $0; sub(/^      [A-Za-z0-9_-]+:[[:space:]]*/, "", val)
            print job "\t" key "\t" val
        }' "$WF"
}
concurrency_keys="$(job_concurrency)"
for j in $jobs; do
    want="\${{ github.workflow }}-$j-\${{ github.ref }}"
    group="$(awk -F'\t' -v j="$j" '$1 == j && $2 == "group" { print $3 }' <<<"$concurrency_keys")"
    [ "$group" = "$want" ] \
        || note "job '$j' must hold the concurrency group '$want': its id written in, since github.job is null outside a job's steps and the jobs of one run that shared a group would cancel each other, and the ref, so one pull request's run does not cancel another's; found '$group'"
    cancel="$(awk -F'\t' -v j="$j" '$1 == j && $2 == "cancel-in-progress" { print $3 }' <<<"$concurrency_keys")"
    [ "$cancel" = "true" ] \
        || note "job '$j''s concurrency group must cancel the run in progress, or a newer run of the job waits for the one testing the commit it replaced; found '$cancel'"
done

# The checks main's ruleset requires, by job id, as
# `gh api repos/<owner>/<repo>/rules/branches/main` lists them: every job here.
REQUIRED="test test-macos"
DRAFT_GATE="github.event_name != 'pull_request' || github.event.pull_request.draft == false"
for j in $jobs; do
    grep -qx -- "$j" <<<"$(tr ' ' '\n' <<<"$REQUIRED")" \
        || note "job '$j' is missing from REQUIRED: every job in tests.yml is a check main's ruleset requires, so list it there and have the operator require it"
done
for j in $REQUIRED; do
    grep -qx -- "$j" <<<"$jobs" \
        || { note "a job with the id '$j' must exist; main's ruleset requires the check named $j"; continue; }
    renames="$(awk -F'\t' -v j="$j" '$1 == j && ($2 == "name" || $2 == "strategy") { print $2 }' <<<"$keys" | paste -sd, -)"
    [ -z "$renames" ] \
        || note "the $j job must not set $renames; it renames the check main's ruleset requires"
    gate="$(awk -F'\t' -v j="$j" '$1 == j && $2 == "if" { print $3 }' <<<"$keys")"
    [ "$gate" = "$DRAFT_GATE" ] \
        || note "the $j job's if: must be the draft gate alone ('$DRAFT_GATE'), since a condition of its own that skips it at a ready head holds the merge; found '$gate'"
done

# Each step of each job, as one "<job>\t<working-directory>\t<run>" row, the
# lines of a block run joined by spaces. tests.yml puts a step's dash at a
# six-space indent, its keys at eight and a block run's lines at ten.
step_rows() {
    awk '
        function flush() { if (job != "" && step) print job "\t" wd "\t" run; step = 0; wd = ""; run = ""; inrun = 0 }
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { flush(); in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); next }
        inrun && (/^          / || /^[[:space:]]*$/) { line = $0; sub(/^[[:space:]]+/, "", line); run = run " " line; next }
        { inrun = 0 }
        /^      - / { flush(); step = 1 }
        /^        working-directory:/ { wd = $0; sub(/^ +working-directory:[[:space:]]*/, "", wd) }
        /^        run:[[:space:]]*\|[[:space:]]*$/ { inrun = 1; next }
        /^        run:/ { run = $0; sub(/^ +run:[[:space:]]*/, "", run) }
        END { flush() }' "$WF"
}
steps="$(step_rows)"
tool_check="$(awk -F'\t' '$1 == "test-macos" && index($3, "command -v") { print $3 }' <<<"$steps")"
for t in lsof flock tmux; do
    grep -Eq "for t in ([^;]* )?${t}[ ;]" <<<"$tool_check" \
        || note "test-macos's tool check must name $t, or a test that needs it skips quietly on a runner without it"
done
grep -Fq 'bash .github/workflows/check-jq.sh' <<<"$tool_check" \
    || note "test-macos's tool check must run check-jq.sh, or a test that needs jq 1.8 skips or fails on an older one"
{ grep -Fq 'BASH_VERSINFO[0]' <<<"$tool_check" && grep -Fq -- '-ge 5 ]' <<<"$tool_check"; } \
    || note "test-macos's tool check must hold env bash to version 5, or a test that needs bash 5 runs under the image's bash 3.2"
package_lists="$(awk -F'\t' '{
    s = $3
    while (match(s, /go test[^;&|]*/)) {
        seg = substr(s, RSTART + 7, RLENGTH - 7); s = substr(s, RSTART + RLENGTH)
        n = split(seg, w, /[[:space:]]+/)
        for (i = 1; i <= n; i++) if (w[i] ~ /^\.\// && w[i] != "./...") { print $1; break }
    }
}' <<<"$steps" | sort -u | paste -sd, -)"
[ -z "$package_lists" ] \
    || note "job(s) $package_lists run go test on a list of packages; a Go check runs go test ./... over the module"

if [ "$fail" -ne 0 ]; then
    echo "tests.test.sh: FAILED" >&2
    exit 1
fi
echo "tests.test.sh: OK"
