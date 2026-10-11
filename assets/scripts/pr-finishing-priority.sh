#!/usr/bin/env bash
# pr-finishing-priority.sh — the single definition of the priority PR-finishing
# work is filed at: the reviews, validation passes, merge-ins, red-check fixes
# and review reworks that carry an anchor's built branch to its merge. A polecat
# claims in priority order, and a pour copies the slung bead's priority into its
# workflow once, so the priority a child carries when it becomes claimable is
# the one it runs at. bd files a bead at P2 when no priority is given, which is
# where new work queues, so finishing work is filed above it:
#   0  the anchor's recorded pr_posture reads approved
#   1  any other posture, or none recorded (an anchor with no PR yet)
#
# Sourced (never executed) by the creators, each of which passes the result as
# --priority in the write that makes its child claimable: pr-facts.sh and
# pre-open-rebase.sh in the route stamp of a fix-pool child, gate-ensure.sh
# ahead of the sling of a review or a validation pass, and signoff.sh ahead of
# the sling of its rework child. One definition, no copies:
# pr-finishing-priority.test.sh fails when a creator stops sourcing this file.

# pr_finishing_priority <posture> — prints the priority for a child of an anchor
# whose pr_posture is <posture>, given as recorded (<posture>@<oid>@<since>) or
# as the bare posture word.
pr_finishing_priority() {
  case "${1%%@*}" in
    approved) echo 0 ;;
    *) echo 1 ;;
  esac
}
