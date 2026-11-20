package standing

import "testing"

// TestAnOpenPullRequestOnEitherRecord: a bead owns an open pull request at
// pull_request, and at either value Gas Town's pending record gives one, and at
// no value that records a landing or an end without one.
func TestAnOpenPullRequestOnEitherRecord(t *testing.T) {
	for _, v := range []string{"pull_request", "pull_request_pending", "pull_request_head_changed"} {
		if !hasOpenPullRequest(Bead{MergeResult: v}) {
			t.Errorf("merge_result %s owns an open pull request", v)
		}
	}
	for _, v := range []string{"", "pre_open_gate", "merged", "mr_merged", "pull_request_closed_unmerged"} {
		if hasOpenPullRequest(Bead{MergeResult: v}) {
			t.Errorf("merge_result %q owns no open pull request", v)
		}
	}
}
