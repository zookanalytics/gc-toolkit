#!/usr/bin/env bash
# tests.test.sh — guards the draft CI-cost gate in tests.yml, the concurrency
# group that keeps a draft's run from cancelling a run that tests, the jq check
# each job runs before the suite, the seconds each job that runs the suite
# keeps, and the jobs whose checks main's ruleset requires.
#
# A draft pull request must not run the *.test.sh suite, so a change still
# taking follow-up commits does not spend Actions minutes on every push. A push
# to main and a manual dispatch must always run it, and marking a draft ready
# must run it. Those are the invariants the draft gate rests on, and every job
# that runs the suite must hold them: a regression that drops any one spends
# minutes on drafts or skips CI where it is required. The draft flag carries no
# workflow state; this gate is only a CI-cost lever.
#
# Every job that runs the suite runs check-jq.sh before it, so a job whose
# runner resolves a jq older than 1.8 fails by name instead of running the
# suite on it.
#
# Every job that runs the suite keeps each run's seconds for the size comment's
# section on the suite's time: it writes them with --seconds, shows them in its
# job summary and uploads them as suite-times-<job> unless the run was
# cancelled, in steps whose failure fails no check, and suite-time.sh, which
# reads them back, names the same jobs. A job that kept none, or kept them under
# another name, would show no time.
#
# A draft's run, whose jobs all skip, never takes the concurrency group of its
# own head, where it could cancel the run that marking the pull request ready
# started at that head. The city's merge counts neither a skipped nor a
# cancelled result, so it would wait for a re-run. tests.yml's comment above the
# group gives each run's group. The group line is pinned whole, so a change to
# it changes this suite too.
#
# Main's ruleset requires the checks named test, test-macos and go. A job's
# check takes the job's id unless the job sets name: or a matrix, and either one
# renames it, so every merge would wait on a check that never reports. Each of
# those jobs has the draft gate as its whole if:, since a condition of its own
# that skipped it at a ready head would leave that head only a skipped result,
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
# first that runs the suite, as one "<job>\t<line>\t<line>" row per job, with 0
# for a job that runs neither.
jq_check_lines() {
    awk '
        function flush() { if (job != "") print job "\t" check "\t" suite; job = "" }
        /^jobs:[[:space:]]*$/ { in_jobs = 1; next }
        in_jobs && /^[^[:space:]#]/ { flush(); in_jobs = 0 }
        !in_jobs { next }
        /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job = $1; sub(/:$/, "", job); check = 0; suite = 0; next }
        /^[[:space:]]*#/ { next }
        job != "" && check == 0 && /check-jq\.sh/ { check = NR }
        job != "" && suite == 0 && /run-tests\.sh/ { suite = NR }
        END { flush() }' "$WF"
}
suite_jobs=0
while IFS=$'\t' read -r j check suite; do
    [ "$suite" -gt 0 ] || continue
    suite_jobs=$((suite_jobs + 1))
    if [ "$check" -eq 0 ]; then
        note "job '$j' must run check-jq.sh, or it runs the suite on whatever jq its runner resolves"
    elif [ "$check" -gt "$suite" ]; then
        note "job '$j' must run check-jq.sh before the suite, not after it"
    fi
done < <(jq_check_lines)
# A job counts as running the suite when it names run-tests.sh, so with no such
# job the check above has checked nothing.
[ "$suite_jobs" -gt 0 ] \
    || note "found no job that runs run-tests.sh in tests.yml, so the jq check checked no job"

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
    for want in 'tools/run-tests.sh -j "$(getconf _NPROCESSORS_ONLN)" --seconds "$RUNNER_TEMP/suite-times.tsv"' \
        'run: bash .github/workflows/suite-time.sh summary "$RUNNER_TEMP/suite-times.tsv" >> "$GITHUB_STEP_SUMMARY"' \
        'name: suite-times-${{ github.job }}' 'path: ${{ runner.temp }}/suite-times.tsv'; do
        grep -Fq -- "$want" <<<"$lines" || note "job '$j' must keep each run's seconds: it lacks '$want'"
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

# The workflow's own concurrency group, the one line at a two-space indent. A
# job's group would sit deeper, under the job.
group_line="$(grep -E '^  group:' "$WF" || true)"
want_group="  group: tests-\${{ github.ref }}\${{ github.event_name == 'pull_request' && format('-{0}', github.event.pull_request.draft && (github.event.before || github.run_id) || github.event.pull_request.head.sha) || '' }}"
[ "$group_line" = "$want_group" ] \
    || note "the concurrency group must give a run that tests a pull request its head's group and a draft push's run the group of the head its push replaced, so a draft's run never cancels the run at its own head; found '${group_line#"  "}'"
grep -Eq '^  cancel-in-progress: true$' "$WF" \
    || note "the concurrency group must cancel the run in progress, or a draft push leaves the run at the head it replaced going"

# The checks main's ruleset requires, by job id, as
# `gh api repos/<owner>/<repo>/rules/branches/main` lists them.
REQUIRED="test test-macos go"
DRAFT_GATE="github.event_name != 'pull_request' || github.event.pull_request.draft == false"
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

if [ "$fail" -ne 0 ]; then
    echo "tests.test.sh: FAILED" >&2
    exit 1
fi
echo "tests.test.sh: OK"
