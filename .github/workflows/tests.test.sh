#!/usr/bin/env bash
# tests.test.sh — guards the draft CI-cost gate in tests.yml.
#
# A draft pull request must not run the *.test.sh suite, so a change still
# taking follow-up commits does not spend Actions minutes on every push. A push
# to main and a manual dispatch must always run it, and marking a draft ready
# must run it. Those are the invariants the draft gate rests on: a regression
# that drops any one spends minutes on drafts or skips CI where it is required.
# The draft flag carries no workflow state; this gate is only a CI-cost lever.

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

# The test job gates on the pull request not being a draft, and non-pull_request
# events (a push to main, a manual dispatch) carry no draft field, so the
# event-name guard keeps them running.
grep -Fq "draft == false" "$WF" \
    || note "the test job must gate on 'draft == false' so a draft pull request skips the suite"
grep -Fq "github.event_name != 'pull_request'" "$WF" \
    || note "the draft gate must let non-pull_request events run, or pushes to main stop running the suite"

if [ "$fail" -ne 0 ]; then
    echo "tests.test.sh: FAILED" >&2
    exit 1
fi
echo "tests.test.sh: OK"
