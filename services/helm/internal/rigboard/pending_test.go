package rigboard

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// pendingRows is a rig whose tk-a owns PR 7 on Gas Town's pending record, at
// the blocked status the record writes and with the old record's posture left
// on it, approved, which prstatus.Derive reads as merging. With gated, tk-a
// waits on tk-q, an open human gate. tk-o owns PR 8 on the old record.
func pendingRows(gated bool) []json.RawMessage {
	deps := ""
	if gated {
		deps = `,"dependencies":[{"issue_id":"tk-a","depends_on_id":"tk-q","type":"blocks"}]`
	}
	return []json.RawMessage{
		json.RawMessage(`{"id":"tk-a","title":"pending work","status":"blocked","priority":2,"issue_type":"task","assignee":"gc-toolkit/refinery","metadata":{"merge_result":"pull_request_pending","pr_number":"7","pr_url":"https://github.com/acme/widgets/pull/7","pr_repo":"acme/widgets","branch":"polecat/tk-a","pr_posture":"approved@1111111@2026-01-01T00:00:00Z"},"created_at":"2026-01-01"` + deps + `}`),
		json.RawMessage(`{"id":"tk-q","title":"which way?","status":"open","priority":1,"issue_type":"gate","await_type":"human","assignee":"human","created_at":"2026-01-02"}`),
		json.RawMessage(`{"id":"tk-o","title":"old work","status":"open","priority":2,"issue_type":"task","assignee":"gc-toolkit/refinery","metadata":{"merge_result":"pull_request","pr_number":"8","pr_url":"https://github.com/acme/widgets/pull/8"},"created_at":"2026-01-03"}`),
	}
}

// answering makes the read's evaluator give answer for tk-a, or no answer when
// answer is nil, and records the beads it was asked about.
func answering(t *testing.T, answer *pr.Answer) *[]string {
	t.Helper()
	asked := &[]string{}
	old := ready
	t.Cleanup(func() { ready = old })
	ready = func(_ *listing.Listing, ids []string) (map[string]pr.Answer, map[string]error) {
		*asked = append(*asked, ids...)
		answers, failed := map[string]pr.Answer{}, map[string]error{}
		for _, id := range ids {
			if id == "tk-a" && answer != nil {
				answers[id] = *answer
			} else {
				failed[id] = errors.New("github: the read did not answer")
			}
		}
		return answers, failed
	}
	return asked
}

func cond(k pr.Kind, id, value string) pr.Condition {
	return pr.Condition{Kind: k, ID: id, Value: value}
}

// TestAPullRequestOnThePendingRecordReadsTheEvaluatorsAnswer reads, through
// the read itself, a pull request on Gas Town's pending record once for each
// status the evaluator's answer renders as. Its row carries the status and
// the held: values `gctk pr status` gives it, prstatus.Render's over the
// answer, where the recorded posture alone would read merging every time. A PR
// the city is moving reads as its pull request in the queue, and one that
// waits on a person is a need. The evaluator is asked about the PR on the
// pending record alone.
func TestAPullRequestOnThePendingRecordReadsTheEvaluatorsAnswer(t *testing.T) {
	cases := []struct {
		name    string
		gated   bool
		answer  pr.Answer
		state   string
		held    []string
		reasons []Reason
		signal  string
		group   Group
		ask     Ask
	}{
		{name: "a ready PR is merging", answer: pr.Answer{Ready: true},
			state: "merging", signal: "Pull request #7", group: GroupQueued},
		{name: "an unapproved draft with the city's work left is working",
			answer: pr.Answer{Conditions: []pr.Condition{cond(pr.KindApproval, "", ""), cond(pr.KindDraft, "", "")}},
			state:  "working", signal: "Pull request #7", group: GroupQueued},
		{name: "a PR waiting on your approval alone needs review",
			answer: pr.Answer{Conditions: []pr.Condition{cond(pr.KindApproval, "", "")}},
			state:  "needs-review", signal: "needs-review", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a review thread waiting on the city's answer needs attention",
			answer: pr.Answer{Conditions: []pr.Condition{cond(pr.KindThread, "", "T1")}},
			state:  "needs-attention", held: []string{"review"},
			reasons: []Reason{{Held: "review", Title: "1 review thread waits on the city's answer"}},
			signal:  "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a human gate the PR waits on needs attention", gated: true,
			answer: pr.Answer{Conditions: []pr.Condition{cond(pr.KindWait, "tk-q", "")}},
			state:  "needs-attention", held: []string{"gate"},
			reasons: []Reason{{Held: "gate", ID: "tk-q", Title: "which way?"}},
			signal:  "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
		{name: "a failed required check needs attention",
			answer: pr.Answer{Conditions: []pr.Condition{cond(pr.KindCheckFailed, "", "test")}},
			state:  "needs-attention", signal: "needs-attention", group: GroupWaitingOnYou, ask: AskPullRequest},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			asked := answering(t, &c.answer)
			doc, err := Read(context.Background(), stubStore(t, pendingRows(c.gated)))
			if err != nil {
				t.Fatalf("Read: %v", err)
			}
			if !slices.Equal(*asked, []string{"tk-a"}) {
				t.Errorf("the evaluator was asked about %v, want tk-a alone", *asked)
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
			if o := doc.Rows["tk-o"].PullRequest; o == nil || o.State == "" {
				t.Errorf("tk-o, on the old record, reads %+v, want a state derived from its facts", o)
			}
		})
	}
}

// A pull request on the pending record that the evaluator could not answer for
// reads unread, with no status, as `gctk pr status` derives none for it.
func TestAPullRequestTheEvaluatorDidNotAnswerReadsUnread(t *testing.T) {
	answering(t, nil)
	doc, err := Read(context.Background(), stubStore(t, pendingRows(false)))
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
