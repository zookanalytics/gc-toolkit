package prstatus_test

import (
	"reflect"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// Render puts the evaluator's answer in the status vocabulary, by Derive's
// precedence: what a person must clear, then an approved PR the city lands
// unless a conversation stays for work, then the city's work, a side of
// GitHub's the landing order has yet to read among it, then the approval
// alone.
func TestRenderTheEvaluatorsAnswer(t *testing.T) {
	cond := func(k pr.Kind, value string) pr.Condition { return pr.Condition{Kind: k, Value: value} }
	staying := prstatus.Facts{Staying: []prstatus.Blocker{{ID: "tk-conv", Title: "a conversation that stays for its work"}}}
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
		{"an approved PR a conversation whose sitting stays for work holds is working, as Derive reads it",
			false, []pr.Condition{{Kind: pr.KindWait, ID: "tk-conv"}}, staying, prstatus.Working},
		{"an unapproved PR a conversation whose sitting stays for work holds is working",
			false, []pr.Condition{cond(pr.KindApproval, ""), {Kind: pr.KindWait, ID: "tk-conv"}}, staying, prstatus.Working},
		{"a review thread beside a stay, with nothing of the city's acting on it, needs attention",
			false, []pr.Condition{cond(pr.KindThread, "T1"), {Kind: pr.KindWait, ID: "tk-conv"}}, staying, prstatus.NeedsAttention},
		{"a PR whose GitHub side is unread is working, since no approval is known",
			false, []pr.Condition{cond(pr.KindGitHubUnread, "")}, prstatus.Facts{}, prstatus.Working},
		{"an unread PR beside the city's work is working",
			false, []pr.Condition{cond(pr.KindGitHubUnread, ""), {Kind: pr.KindInFlight, ID: "tk-k"}}, prstatus.Facts{},
			prstatus.Working},
		{"an unread PR a conversation whose sitting stays for work holds is working",
			false, []pr.Condition{cond(pr.KindGitHubUnread, ""), {Kind: pr.KindWait, ID: "tk-conv"}}, staying, prstatus.Working},
		{"an unread PR beside a human gate needs attention",
			false, []pr.Condition{cond(pr.KindGitHubUnread, ""), {Kind: pr.KindWait, ID: "gate"}},
			prstatus.Facts{Gates: []prstatus.Blocker{{ID: "gate", Title: "decide"}}}, prstatus.NeedsAttention},
		{"an unread PR beside a bead a person owes needs attention",
			false, []pr.Condition{cond(pr.KindGitHubUnread, ""), {Kind: pr.KindWait, ID: "tk-owed"}},
			prstatus.Facts{Owed: []prstatus.Blocker{{ID: "tk-owed", Title: "answer the question"}}}, prstatus.NeedsAttention},
		{"an unread PR a hold set by hand holds needs attention",
			false, []pr.Condition{cond(pr.KindGitHubUnread, ""), cond(pr.KindHold, "")}, prstatus.Facts{},
			prstatus.NeedsAttention},
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
// the city's answer, then the beads a person owes. A wait on a gate, on a bead
// a person owes or on a conversation whose sitting stays for work is no work
// of the city's on the threads, so they still hold.
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
	t.Run("an unread side names no thread, so only what the walk finds holds the PR", func(t *testing.T) {
		unread := pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindGitHubUnread}, {Kind: pr.KindWait, ID: "tk-gate"}}}
		want := []prstatus.Reason{{Held: prstatus.HeldGate, ID: "tk-gate", Title: "decide the scope"}}
		gated := prstatus.Facts{Gates: f.Gates}
		if got := prstatus.RenderReasons(unread, gated); !reflect.DeepEqual(got, want) {
			t.Fatalf("RenderReasons = %+v, want %+v", got, want)
		}
	})
	t.Run("a stay's wait acts on no thread, so the thread holds", func(t *testing.T) {
		stay := prstatus.Facts{Staying: []prstatus.Blocker{{ID: "tk-conv", Title: "a conversation that stays for its work"}}}
		a := pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindThread, Value: "T1"}, {Kind: pr.KindWait, ID: "tk-conv"}}}
		want := []prstatus.Reason{{Held: prstatus.HeldReview, Title: "1 review thread waits on the city's answer"}}
		if got := prstatus.RenderReasons(a, stay); !reflect.DeepEqual(got, want) {
			t.Fatalf("RenderReasons = %+v, want %+v", got, want)
		}
	})
	t.Run("a thread the city's work acts on holds nothing", func(t *testing.T) {
		acted := pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindThread, Value: "T1"}, {Kind: pr.KindWait, ID: "tk-fix"}}}
		if got := prstatus.RenderReasons(acted, prstatus.Facts{PRPosture: "review_required@oid@t"}); len(got) != 0 {
			t.Fatalf("RenderReasons = %+v, want none", got)
		}
	})
}

// The review condition renders with the run's state (specs/tk-1tfzr71.108/
// design.md, section 7): a run attached is the city's work in flight, and a
// closed run with no result at the head, and the gates a run's failure files,
// read needs-attention as the machine's fault, which holds no held: value, so
// none reads as a person's hold or a ruling owed.
func TestTheReviewConditionRendersWithTheRunsState(t *testing.T) {
	const at = "1111111111111111111111111111111111111111"
	attached := pr.Answer{Head: at, Target: "main", Conditions: []pr.Condition{
		{Kind: pr.KindReview}, {Kind: pr.KindWait, ID: "tk-run2"}}}
	live := prstatus.Facts{Runs: []prstatus.Run{
		{ID: "tk-run1", Status: "closed", Head: at, Target: "main", ClosedAt: "2026-11-12T09:10:00Z"},
		{ID: "tk-run2", Status: "open", Head: at, Target: "main"}}}
	if got := prstatus.Render(attached, live); got != prstatus.Merging {
		t.Fatalf("a run attached rendered %s, want the city's work in flight on an approved PR, merging", got)
	}
	if got := prstatus.RenderReasons(attached, live); len(got) != 0 {
		t.Fatalf("a run attached gave reasons %+v, want none", got)
	}

	ended := pr.Answer{Head: at, Target: "main", Conditions: []pr.Condition{{Kind: pr.KindReview}}}
	closed := prstatus.Facts{Runs: []prstatus.Run{
		{ID: "tk-run1", Status: "closed", Head: at, Target: "main", ClosedAt: "2026-11-12T09:10:00Z"},
		{ID: "tk-run2", Status: "closed", Head: at, Target: "main", ClosedAt: "2026-11-12T09:20:00Z"},
		{ID: "tk-run0", Status: "closed", Head: "2222222222222222222222222222222222222222", Target: "main",
			ClosedAt: "2026-11-12T09:30:00Z"}}}
	if got := prstatus.Render(ended, closed); got != prstatus.NeedsAttention {
		t.Fatalf("a closed run with no result at the head rendered %s, want needs-attention", got)
	}
	reasons := prstatus.RenderReasons(ended, closed)
	if len(reasons) != 1 || reasons[0].Held != "" || reasons[0].ID != "tk-run2" {
		t.Fatalf("a closed run with no result gave %+v, want the last run at the head, with no held value", reasons)
	}
	if held := prstatus.RenderHeld(ended, closed); len(held) != 0 {
		t.Fatalf("the machine's fault named held values %v, want none", held)
	}
	withResult := ended
	withResult.ReviewResult = &review.Result{Head: at, Target: "main", Run: "tk-run2"}
	if got := prstatus.RenderReasons(withResult, closed); len(got) != 0 {
		t.Fatalf("a run that recorded a result that did not pass gave %+v, want none", got)
	}

	for _, key := range []string{"review-run-failed", "review-loop-exhausted"} {
		f := prstatus.Facts{Gates: []prstatus.Blocker{{ID: "tk-g", Title: "look at the runs", IssueType: "gate",
			AwaitType: "human", AwaitID: key}}}
		gate := pr.Answer{Conditions: []pr.Condition{{Kind: pr.KindReview}, {Kind: pr.KindWait, ID: "tk-g"}}}
		if got := prstatus.Render(gate, f); got != prstatus.NeedsAttention {
			t.Fatalf("a %s gate rendered %s, want needs-attention", key, got)
		}
		want := []prstatus.Reason{{ID: "tk-g", Title: "look at the runs"}}
		if got := prstatus.RenderReasons(gate, f); !reflect.DeepEqual(got, want) {
			t.Fatalf("a %s gate gave %+v, want %+v, the machine's fault", key, got, want)
		}
		if got := prstatus.Derive(f); got != prstatus.NeedsAttention || len(prstatus.Held(f)) != 0 {
			t.Fatalf("on the old record a %s gate derived %s with held %v, want needs-attention and none", key, got, prstatus.Held(f))
		}
	}
	question := prstatus.Facts{Gates: []prstatus.Blocker{{ID: "tk-q", Title: "which scope?", IssueType: "gate",
		AwaitType: "human", AwaitID: "review-question-scope"}}}
	if got := prstatus.RenderHeld(pr.Answer{}, question); !reflect.DeepEqual(got, []prstatus.Hold{prstatus.HeldGate}) {
		t.Fatalf("a run's question to a person held %v, want a person's hold, gate", got)
	}
}
