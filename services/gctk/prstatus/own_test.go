package prstatus_test

import (
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// Own reads the label's rule over the PR's own conditions: what holds it is
// set aside, and the city's work comes before an approval
// (specs/tk-ai367om/design.md, section 3).
func TestOwnReadsThePRsOwnConditions(t *testing.T) {
	cond := func(k pr.Kind, value string) pr.Condition { return pr.Condition{Kind: k, Value: value} }
	wait := func(id string) pr.Condition { return pr.Condition{Kind: pr.KindWait, ID: id} }
	run := prstatus.Facts{Runs: []prstatus.Run{{ID: "tk-run", Status: "closed", Head: "h1", Target: "main", ClosedAt: "2026-11-23T01:00:00Z"}}}
	cases := []struct {
		name  string
		ready bool
		conds []pr.Condition
		facts prstatus.Facts
		want  prstatus.State
	}{
		{"a ready PR is merging", true, nil, prstatus.Facts{}, prstatus.Merging},
		{"a draft is working", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindDraft, "")}, prstatus.Facts{}, prstatus.Working},
		{"a PR GitHub has not read at its head is working", false, []pr.Condition{cond(pr.KindGitHubUnread, "")}, prstatus.Facts{}, prstatus.Working},
		{"a pending required check is working", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindCheckPending, "test")}, prstatus.Facts{}, prstatus.Working},
		{"a failed required check needs attention", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindCheckFailed, "test")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"no passed review at its head is working", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindReview, "")}, prstatus.Facts{}, prstatus.Working},
		{"a review run that ended with no result needs attention",
			false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindReview, "")}, run, prstatus.NeedsAttention},
		{"an open send-back is working", false, []pr.Condition{cond(pr.KindApproval, ""), wait("tk-ask")}, prstatus.Facts{}, prstatus.Working},
		{"a wait on other work is working, whoever that work waits for",
			false, []pr.Condition{cond(pr.KindApproval, ""), wait("tk-other")},
			prstatus.Facts{Owed: []person.Blocker{{ID: "tk-behind-other", Title: "a conversation behind the other work"}}}, prstatus.Working},
		{"an attached review run is working", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindInFlight, "")}, prstatus.Facts{}, prstatus.Working},
		{"an approved PR the city is still changing is working", false, []pr.Condition{cond(pr.KindHead, "")}, prstatus.Facts{}, prstatus.Working},
		{"an approved PR with nothing of its own left is merging", false, nil, prstatus.Facts{}, prstatus.Merging},
		{"an approved PR GitHub has not computed yet is merging", false, []pr.Condition{cond(pr.KindMergeState, "UNKNOWN")}, prstatus.Facts{}, prstatus.Merging},
		{"an approved PR that conflicts with nothing else left needs attention", false, []pr.Condition{cond(pr.KindMergeState, "DIRTY")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a PR that waits only on an approval needs review", false, []pr.Condition{cond(pr.KindApproval, "")}, prstatus.Facts{}, prstatus.NeedsReview},
		{"a request for changes its author has to lift needs review", false, []pr.Condition{cond(pr.KindChangesRequested, "operator")}, prstatus.Facts{}, prstatus.NeedsReview},
		{"a review thread nothing acts on needs attention", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindThread, "T1")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a review thread work acts on is working", false, []pr.Condition{cond(pr.KindApproval, ""), cond(pr.KindThread, "T1"), cond(pr.KindFeedback, "")}, prstatus.Facts{}, prstatus.Working},
		{"a PR that is not the one the record names needs attention", false, []pr.Condition{cond(pr.KindRecord, "")}, prstatus.Facts{}, prstatus.NeedsAttention},
		{"a PR closed on the record needs attention", false, []pr.Condition{cond(pr.KindOpen, "")}, prstatus.Facts{}, prstatus.NeedsAttention},
	}
	holds := []struct {
		name string
		cond pr.Condition
		add  func(prstatus.Facts) prstatus.Facts
	}{
		{"a hold set by hand", cond(pr.KindHold, ""), func(f prstatus.Facts) prstatus.Facts { return f }},
		{"a question for a person", wait("tk-gate"), func(f prstatus.Facts) prstatus.Facts {
			f.Gates = append(f.Gates, person.Blocker{ID: "tk-gate", Title: "a question", IssueType: "gate", AwaitType: "human"})
			return f
		}},
		{"a conversation that holds the merge", wait("tk-conv"), func(f prstatus.Facts) prstatus.Facts {
			f.Owed = append(f.Owed, person.Blocker{ID: "tk-conv", Title: "a conversation"})
			return f
		}},
		{"a conversation that stays for the work", wait("tk-conv"), func(f prstatus.Facts) prstatus.Facts {
			f.Staying = append(f.Staying, person.Blocker{ID: "tk-conv", Title: "a staying conversation"})
			return f
		}},
	}
	for _, c := range cases {
		a := pr.Answer{Bead: "tk-pr", Ready: c.ready, Head: "h1", Target: "main", Conditions: c.conds}
		if got := prstatus.Own(a, c.facts); got != c.want {
			t.Errorf("%s: Own = %s, want %s", c.name, got, c.want)
		}
		if c.ready {
			continue
		}
		for _, h := range holds {
			held := a
			held.Conditions = append(append([]pr.Condition(nil), c.conds...), h.cond)
			if got := prstatus.Own(held, h.add(c.facts)); got != c.want {
				t.Errorf("%s, with %s: Own = %s, want %s unchanged", c.name, h.name, got, c.want)
			}
		}
	}
}

// The label and the own status part where a hold or the city's work meets an
// approval.
func TestOwnDiffersFromTheLabelWhereTheDesignSays(t *testing.T) {
	approvedChanging := pr.Answer{Bead: "tk-pr", Head: "h1", Target: "main", Conditions: []pr.Condition{{Kind: pr.KindCheckPending, Value: "test"}}}
	if label, own := prstatus.Render(approvedChanging, prstatus.Facts{}), prstatus.Own(approvedChanging, prstatus.Facts{}); label != prstatus.Merging || own != prstatus.Working {
		t.Errorf("an approved PR with a check running: label %s, own %s; want merging and working", label, own)
	}
	held := pr.Answer{Bead: "tk-pr", Head: "h1", Target: "main", Conditions: []pr.Condition{{Kind: pr.KindApproval}, {Kind: pr.KindWait, ID: "tk-conv"}}}
	facts := prstatus.Facts{Owed: []person.Blocker{{ID: "tk-conv", Title: "a conversation"}}}
	if label, own := prstatus.Render(held, facts), prstatus.Own(held, facts); label != prstatus.NeedsAttention || own != prstatus.NeedsReview {
		t.Errorf("a PR a conversation holds that waits on an approval: label %s, own %s; want needs-attention and needs-review", label, own)
	}
}
