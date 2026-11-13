package prstatus_test

import (
	"reflect"
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
		{"an unapproved PR with feedback the intake has yet to route is working",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindFeedback, "")}, prstatus.Facts{}, prstatus.Working},
		{"an unapproved PR whose review thread waits on the city's answer, with nothing acting on it, needs attention",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindThread, "T1")}, prstatus.Facts{}, prstatus.NeedsAttention},
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
		{"an approved PR behind a base that requires it current, with nothing else left, needs attention",
			false, []pr.Condition{cond(pr.KindMergeState, "BEHIND")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"an approved PR in a merge state the evaluator does not merge on, with nothing else left, needs attention",
			false, []pr.Condition{cond(pr.KindMergeState, "HAS_HOOKS")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a human gate the walk finds needs attention",
			false, []pr.Condition{cond(pr.KindWait, "")},
			prstatus.Facts{Gates: []prstatus.Blocker{{ID: "gate", Title: "decide"}}}, prstatus.NeedsAttention},
		{"a review thread waiting on the city's answer, with nothing of the city's acting on it, needs attention",
			false, []pr.Condition{cond(pr.KindThread, "T1")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"one that work on the PR's branch acts on is the city's",
			false, []pr.Condition{cond(pr.KindThread, "T1"), {Kind: pr.KindWait, ID: "tk-fix"}}, prstatus.Facts{}, prstatus.Merging},
		{"one that a bead anchored to the PR acts on is the city's",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindThread, "T1"), {Kind: pr.KindInFlight, ID: "tk-k"}},
			prstatus.Facts{}, prstatus.Working},
		{"one beside feedback the intake has yet to route is the city's",
			false, []pr.Condition{cond(pr.KindThread, "T1"), cond(pr.KindFeedback, "")}, prstatus.Facts{}, prstatus.Merging},
		{"the merge pass's verdict and thread count, left from the old record, hold nothing",
			false, []pr.Condition{cond(pr.KindCheckPending, "test")},
			prstatus.Facts{PRPosture: "approved@oid@t", PRMachine: "blocked@oid@t", PRMachineCause: prstatus.CauseBlocker,
				PRUnansweredThreads: "2@oid"}, prstatus.Merging},
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

// RenderReasons names what holds a PR on the pending record in the order the
// held: labels take: the gates the walk finds, the review threads waiting on
// the city's answer, then the beads a person owes. A wait on a gate or on a
// bead a person owes is no work of the city's, so the threads still hold.
func TestRenderReasons(t *testing.T) {
	f := prstatus.Facts{
		Gates: []prstatus.Blocker{{ID: "tk-gate", Title: "decide the scope"}},
		Owed:  []prstatus.Blocker{{ID: "tk-owed", Title: "answer the question"}},
	}
	a := pr.Answer{Conditions: []pr.Condition{
		{Kind: pr.KindThread, Value: "T1"}, {Kind: pr.KindThread, Value: "T2"},
		{Kind: pr.KindWait, ID: "tk-gate"}, {Kind: pr.KindWait, ID: "tk-owed"},
	}}
	want := []prstatus.Reason{
		{Held: prstatus.HeldGate, ID: "tk-gate", Title: "decide the scope"},
		{Held: prstatus.HeldReview, Title: "2 review threads wait on the city's answer"},
		{Held: prstatus.HeldBlocked, ID: "tk-owed", Title: "answer the question"},
	}
	if got := prstatus.RenderReasons(a, f); !reflect.DeepEqual(got, want) {
		t.Fatalf("RenderReasons = %+v, want %+v", got, want)
	}
	wantHeld := []prstatus.Hold{prstatus.HeldGate, prstatus.HeldReview, prstatus.HeldBlocked}
	if got := prstatus.RenderHeld(a, f); !reflect.DeepEqual(got, wantHeld) {
		t.Fatalf("RenderHeld = %v, want %v", got, wantHeld)
	}
	t.Run("the merge pass's records hold nothing, and neither does a thread the city's work acts on", func(t *testing.T) {
		stale := prstatus.Facts{PRPosture: "review_required@oid@t", PRMachine: "blocked@oid@t",
			PRMachineCause: prstatus.CauseReviewThreads, PRUnansweredThreads: "1@oid"}
		acted := pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindThread, Value: "T1"}, {Kind: pr.KindWait, ID: "tk-fix"}}}
		if got := prstatus.RenderReasons(acted, stale); len(got) != 0 {
			t.Fatalf("RenderReasons = %+v, want none", got)
		}
		if got := prstatus.Reasons(stale); len(got) == 0 {
			t.Fatal("the old record's reasons read nothing from the same facts, so this case shows nothing")
		}
	})
}
