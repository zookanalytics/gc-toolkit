package prstatus_test

import (
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// Render puts the evaluator's answer in the status vocabulary, by Derive's
// precedence: what a person must clear, then an approved PR the city lands,
// then the city's work, then the approval alone.
func TestRenderTheEvaluatorsAnswer(t *testing.T) {
	cond := func(k pr.Kind, value string) pr.Condition { return pr.Condition{Kind: k, Value: value} }
	cases := []struct {
		name  string
		ready bool
		conds []pr.Condition
		facts prstatus.Facts
		want  prstatus.State
	}{
		{"a ready PR is merging", true, nil, prstatus.Facts{}, prstatus.Merging},
		{"an approved PR with a check still running is merging",
			false, []pr.Condition{cond(pr.KindCheckPending, "test")}, prstatus.Facts{}, prstatus.Merging},
		{"an approved PR the review loop has not passed is merging",
			false, []pr.Condition{cond(pr.KindReview, ""), cond(pr.KindInFlight, "")}, prstatus.Facts{}, prstatus.Merging},
		{"an unapproved PR with the city's work left is working",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindDraft, "")}, prstatus.Facts{}, prstatus.Working},
		{"an unapproved PR with unanswered feedback is working",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindThread, "T1")}, prstatus.Facts{}, prstatus.Working},
		{"a PR waiting only on an approval needs review",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindMergeState, "BLOCKED")}, prstatus.Facts{}, prstatus.NeedsReview},
		{"a PR whose request for changes stands needs review",
			false, []pr.Condition{cond(pr.KindChangesRequested, "operator")}, prstatus.Facts{}, prstatus.NeedsReview},
		{"a hold set by hand needs attention",
			false, []pr.Condition{cond(pr.KindHold, "")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a failed required check needs attention",
			false, []pr.Condition{cond(pr.KindCheckFailed, "test")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a PR that is not the one the record names needs attention",
			false, []pr.Condition{cond(pr.KindRecord, "")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a PR closed on the record needs attention",
			false, []pr.Condition{cond(pr.KindOpen, "")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"an approved PR GitHub blocks for a rule nothing else names needs attention",
			false, []pr.Condition{cond(pr.KindMergeState, "BLOCKED")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"an approved PR that conflicts with nothing else left needs attention",
			false, []pr.Condition{cond(pr.KindMergeState, "DIRTY")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"an approved PR GitHub has not computed yet is merging",
			false, []pr.Condition{cond(pr.KindMergeState, "UNKNOWN")}, prstatus.Facts{}, prstatus.Merging},
		{"a human gate the walk finds needs attention",
			false, []pr.Condition{cond(pr.KindWait, "")},
			prstatus.Facts{Gates: []prstatus.Blocker{{ID: "gate", Title: "decide"}}}, prstatus.NeedsAttention},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := prstatus.Render(pr.Answer{Ready: c.ready, Conditions: c.conds}, c.facts)
			if got != c.want {
				t.Fatalf("got %s, want %s", got, c.want)
			}
		})
	}
}
