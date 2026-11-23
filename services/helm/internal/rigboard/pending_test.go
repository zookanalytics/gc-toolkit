package rigboard

import (
	"context"
	"encoding/json"
	"reflect"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// pendingHead is the head the refinery validated for tk-a's PR.
const pendingHead = "1111111111111111111111111111111111111111"

// savedRead is the read the one-PR update saves of tk-a's PR at pendingHead
// that leaves nothing to do, open, approved, CLEAN and its required check
// passed, after edit changes it, in the parts the update saves it in.
func savedRead(t *testing.T, edit func(*pr.GitHubRead)) string {
	t.Helper()
	r := &pr.GitHubRead{ReadAt: "2026-11-15T09:00:00Z", URL: "https://github.com/acme/widgets/pull/7", Number: 7,
		Repository: "acme/widgets", HeadBranch: "polecat/tk-a", Base: "main", Head: pendingHead, State: "OPEN",
		MergeState: "CLEAN", Checks: []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS"}},
		Approvers: []string{"operator"}, Requesters: []string{}, Awaiting: []string{}}
	if edit != nil {
		edit(r)
	}
	raw, err := json.Marshal(&pr.SavedRead{
		PR: &pr.SavedPR{ReadAt: r.ReadAt, URL: r.URL, Number: r.Number, Repository: r.Repository,
			HeadBranch: r.HeadBranch, Base: r.Base, Head: r.Head, State: r.State, Draft: r.Draft, MergeState: r.MergeState},
		Checks: &pr.SavedChecks{ReadAt: r.ReadAt, Head: r.Head, Runs: r.Checks},
		Conversation: &pr.SavedConversation{ReadAt: r.ReadAt, Since: r.Since, Approvers: r.Approvers,
			Requesters: r.Requesters, Untaken: r.Untaken, Awaiting: r.Awaiting, Unresolved: []string{}},
		Labels: &pr.SavedLabels{ReadAt: r.ReadAt, Names: []string{}},
	})
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// pendingRows is a rig whose tk-a owns PR 7 on Gas Town's pending record,
// blocked and assigned to nobody as the record writes it, validated at
// pendingHead into main with a review result passed there, and carrying read as
// the read the one-PR update saved, none when read is empty. With gated, tk-a
// waits on tk-q, an open human gate.
func pendingRows(t *testing.T, gated bool, read string) []json.RawMessage {
	t.Helper()
	md := map[string]any{"merge_result": "pull_request_pending", "pr_number": "7",
		"pr_url": "https://github.com/acme/widgets/pull/7", "pr_repo": "acme/widgets", "pr_head_sha": pendingHead,
		"merged_target": "main", "branch": "polecat/tk-a",
		"review_results": `[{"head":"` + pendingHead + `","target":"main","passed":true}]`}
	if read != "" {
		md["pr_github_read"] = read
	}
	a := map[string]any{"id": "tk-a", "title": "pending work", "status": "blocked", "priority": 2, "issue_type": "task",
		"metadata": md, "created_at": "2026-01-01"}
	if gated {
		a["dependencies"] = []map[string]any{{"issue_id": "tk-a", "depends_on_id": "tk-q", "type": "blocks"}}
	}
	var out []json.RawMessage
	for _, r := range []map[string]any{a,
		{"id": "tk-q", "title": "which way?", "status": "open", "priority": 1, "issue_type": "gate", "await_type": "human",
			"assignee": "human", "created_at": "2026-01-02"},
	} {
		raw, err := json.Marshal(r)
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, raw)
	}
	return out
}

// TestAPullRequestOnThePendingRecordReadsTheEvaluatorsAnswer reads, through
// the read itself, a pull request on Gas Town's pending record once for each
// status the evaluator's answer renders as, from the GitHub read the landing
// order saved on its bead. Its row carries the status and the held: values
// `gctk pr status` gives it, prstatus.Render's over the answer, where the
// facts alone would read needs-review every time, so each case that renders
// another status fails if the board falls back to them. A PR the city is
// moving reads as its pull request in the queue, and one that waits on a person
// is a need.
func TestAPullRequestOnThePendingRecordReadsTheEvaluatorsAnswer(t *testing.T) {
	cases := []struct {
		name    string
		gated   bool
		read    func(*pr.GitHubRead)
		state   string
		held    []string
		reasons []Reason
		signal  string
		group   Group
		ask     Ask
	}{
		{name: "a ready PR is merging", state: "merging", signal: "Pull request #7", group: GroupQueued},
		{name: "an unapproved draft with the city's work left is working",
			read:  func(r *pr.GitHubRead) { r.Draft, r.Approvers = true, []string{} },
			state: "working", signal: "Pull request #7", group: GroupQueued},
		{name: "a PR waiting on your approval alone needs review",
			read:  func(r *pr.GitHubRead) { r.Approvers = []string{} },
			state: "needs-review", signal: "needs-review", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a review thread waiting on the city's answer needs attention",
			read:  func(r *pr.GitHubRead) { r.Awaiting = []string{"T1"} },
			state: "needs-attention", held: []string{"review"},
			reasons: []Reason{{Held: "review", Title: "1 review thread waits on the city's answer"}},
			signal:  "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a human gate the PR waits on needs attention", gated: true,
			state: "needs-attention", held: []string{"gate"},
			reasons: []Reason{{Held: "gate", ID: "tk-q", Title: "which way?"}},
			signal:  "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a failed required check needs attention",
			read: func(r *pr.GitHubRead) {
				r.Checks = []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "FAILURE"}}
			},
			state: "needs-attention", signal: "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			doc, err := Read(context.Background(), stubStore(t, pendingRows(t, c.gated, savedRead(t, c.read))))
			if err != nil {
				t.Fatalf("Read: %v", err)
			}
			r := doc.Rows["tk-a"]
			if r.PullRequest == nil || r.PullRequest.Number != "7" || r.PullRequest.State != c.state ||
				!slices.Equal(r.PullRequest.Held, c.held) {
				t.Errorf("tk-a's pull request reads %+v, want #7 at %s held by %v", r.PullRequest, c.state, c.held)
			}
			if !reflect.DeepEqual(r.Reasons, c.reasons) {
				t.Errorf("tk-a's reasons read %+v, want %+v", r.Reasons, c.reasons)
			}
			if r.Signal != c.signal || r.Group != c.group || r.Ask != c.ask {
				t.Errorf("tk-a reads %q in %q asking %q, want %q in %q asking %q",
					r.Signal, r.Group, r.Ask, c.signal, c.group, c.ask)
			}
			if c.group == GroupQueued && (r.Note != c.state || !slices.Contains(doc.WorkQueue.Queue, "tk-a")) {
				t.Errorf("tk-a notes %q and the Work queue lists %v, want %s and tk-a in it",
					r.Note, doc.WorkQueue.Queue, c.state)
			}
		})
	}
}

// A pull request on the pending record whose GitHub side the landing order has
// yet to read at the head the store holds reads working, as its pull request
// in the queue, until the order's next check.
func TestAPullRequestTheLandingOrderHasNotReadIsWorking(t *testing.T) {
	doc, err := Read(context.Background(), stubStore(t, pendingRows(t, false, "")))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	r := doc.Rows["tk-a"]
	if r.PullRequest == nil || r.PullRequest.State != "working" || len(r.PullRequest.Held) != 0 {
		t.Errorf("tk-a's pull request reads %+v, want #7 working with nothing held", r.PullRequest)
	}
	if r.Signal != "Pull request #7" || r.Group != GroupQueued || r.Ask != "" || r.Note != "working" ||
		!slices.Contains(doc.WorkQueue.Queue, "tk-a") {
		t.Errorf("tk-a reads %q in %q asking %q noting %q, want its pull request working in the Work queue",
			r.Signal, r.Group, r.Ask, r.Note)
	}
}

// A pull request on the pending record that the evaluator could not answer
// for, because its saved read does not decode, reads unread, with no status,
// as `gctk pr status` derives none for it.
func TestAPullRequestTheEvaluatorDidNotAnswerReadsUnread(t *testing.T) {
	doc, err := Read(context.Background(), stubStore(t, pendingRows(t, false, "{not json")))
	if err != nil {
		t.Fatalf("Read: %v", err)
	}
	r := doc.Rows["tk-a"]
	if r.Signal != signalUnread || r.Group != "" || r.Ask != "" {
		t.Errorf("tk-a reads %q in %q asking %q, want it unread", r.Signal, r.Group, r.Ask)
	}
	if r.PullRequest == nil || r.PullRequest.State != "" || len(r.PullRequest.Held) != 0 {
		t.Errorf("tk-a's pull request reads %+v, want #7 with no status", r.PullRequest)
	}
	if !slices.Contains(doc.WorkQueue.Unread, "tk-a") {
		t.Errorf("the Work queue lists %+v, want tk-a among the unread", doc.WorkQueue)
	}
}
