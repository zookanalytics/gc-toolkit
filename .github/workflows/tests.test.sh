#!/usr/bin/env bash
# tests.test.sh — guards the draft CI-cost gate in tests.yml, and the name of
# the check main's ruleset requires.
#
# A draft pull request must not run the *.test.sh suite, so a change still
# taking follow-up commits does not spend Actions minutes on every push. A push
# to main and a manual dispatch must always run it, and marking a draft ready
# must run it. Those are the invariants the draft gate rests on, and every job
# that runs the suite must hold them: a regression that drops any one spends
# minutes on drafts or skips CI where it is required. The draft flag carries no
# workflow state; this gate is only a CI-cost lever.
#
# Main's ruleset requires the check named test. A job's check takes the job's
# id unless the job sets name: or a matrix, and either one renames it, so every
# merge would wait on a check that never reports.

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

grep -qx test <<<"$jobs" \
    || note "a job with the id 'test' must exist; main's ruleset requires the check named test"
renames="$(awk -F'\t' '$1 == "test" && ($2 == "name" || $2 == "strategy") { print $2 }' <<<"$keys" | paste -sd, -)"
[ -z "$renames" ] \
    || note "the test job must not set $renames; it renames the check main's ruleset requires"

if [ "$fail" -ne 0 ]; then
    echo "tests.test.sh: FAILED" >&2
    exit 1
fi
echo "tests.test.sh: OK"
