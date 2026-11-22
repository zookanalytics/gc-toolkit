package listing

import (
	"encoding/json"
	"maps"
	"reflect"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

const validatedHead = "1111111111111111111111111111111111111111"

// onRecord is the metadata of a bead whose PR, number n in acme/widgets, is on
// Gas Town's pending record, validated at validatedHead into main with a review
// result passed there, and with read saved on it in the parts the one-PR update
// saves, none when read is nil.
func onRecord(t *testing.T, n string, read *pr.GitHubRead) map[string]string {
	t.Helper()
	md := map[string]string{
		"merge_result": "pull_request_pending", "pr_url": "https://github.com/acme/widgets/pull/" + n, "pr_number": n,
		"pr_repo": "acme/widgets", "pr_head_sha": validatedHead, "merged_target": "main", "branch": "polecat/" + n,
		"review_results": `[{"head":"` + validatedHead + `","target":"main","passed":true}]`,
	}
	if read != nil {
		raw, err := json.Marshal(inParts(read))
		if err != nil {
			t.Fatal(err)
		}
		md["pr_github_read"] = string(raw)
	}
	return md
}

// inParts is r, GitHub's side of a PR at one head, in the four parts the one-PR
// update saves it in, each read at r's instant.
func inParts(r *pr.GitHubRead) *pr.SavedRead {
	return &pr.SavedRead{
		PR: &pr.SavedPR{ReadAt: r.ReadAt, URL: r.URL, Number: r.Number, Repository: r.Repository,
			HeadBranch: r.HeadBranch, Base: r.Base, Head: r.Head, State: r.State, Draft: r.Draft, MergeState: r.MergeState},
		Checks: &pr.SavedChecks{ReadAt: r.ReadAt, Head: r.Head, Runs: r.Checks},
		Conversation: &pr.SavedConversation{ReadAt: r.ReadAt, Since: r.Since, Approvers: r.Approvers,
			Requesters: r.Requesters, Untaken: r.Untaken, Awaiting: r.Awaiting, Unresolved: []string{}},
		Labels: &pr.SavedLabels{ReadAt: r.ReadAt, Names: []string{}},
	}
}

// readyRead is the read of PR 7 at validatedHead that leaves nothing to do:
// open, approved, CLEAN, its required check passed.
func readyRead() *pr.GitHubRead {
	return &pr.GitHubRead{ReadAt: "2026-11-15T09:00:00Z", URL: "https://github.com/acme/widgets/pull/7", Number: 7,
		Repository: "acme/widgets", HeadBranch: "polecat/7", Base: "main", Head: validatedHead, State: "OPEN",
		MergeState: "CLEAN", Checks: []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS"}},
		Approvers: []string{"operator"}, Requesters: []string{}, Awaiting: []string{}}
}

// PRAnswers asks the evaluator over the listing's own pass: each answer is the
// one the rows the listing read give, with the GitHub read saved on the bead,
// as pr.FromStore gives it over the store, so a write that lands after the
// listing changes none of them. It reads none of the beads the listing holds
// again, and the store by no key and never whole. A bead whose saved read does
// not decode gets its error and no answer.
func TestPRAnswersAskTheEvaluatorOverTheListingsPass(t *testing.T) {
	s := fake.New()
	ready := onRecord(t, "7", readyRead())
	broken := onRecord(t, "9", nil)
	broken["pr_github_read"] = "{not json"
	for _, b := range []fake.Bead{
		{ID: "tk-p", Title: "ready work", Status: "blocked", IssueType: "task", Metadata: ready},
		{ID: "tk-u", Title: "work the landing order has yet to read", Status: "blocked", IssueType: "task",
			Metadata: onRecord(t, "8", nil)},
		{ID: "tk-bad", Title: "work whose read does not decode", Status: "blocked", IssueType: "task", Metadata: broken},
	} {
		s.Put(b)
	}
	unread, err := pr.FromStore(ledger.New(s), "tk-u")
	if err != nil {
		t.Fatal(err)
	}
	ls, err := read(ledger.New(s))
	if err != nil {
		t.Fatal(err)
	}
	listed := len(s.Finds())
	held := maps.Clone(ready)
	held["merge_hold"] = "true"
	s.Put(fake.Bead{ID: "tk-p", Title: "ready work", Status: "blocked", IssueType: "task", Metadata: held})

	answers, failed := ls.PRAnswers([]string{"tk-p", "tk-u", "tk-bad", "tk-p"})
	if got := slices.Sorted(maps.Keys(answers)); !slices.Equal(got, []string{"tk-p", "tk-u"}) {
		t.Fatalf("answered %v, want tk-p and tk-u", got)
	}
	if a := answers["tk-p"]; !a.Ready || a.Head != validatedHead || a.Target != "main" {
		t.Errorf("tk-p reads %+v, want ready at the saved read's head, as the listing read it", a)
	}
	if a := answers["tk-u"]; !reflect.DeepEqual(a, unread) || len(a.Conditions) != 1 || a.Conditions[0].Kind != pr.KindGitHubUnread {
		t.Errorf("tk-u reads %+v, want FromStore's answer over the store, %+v: GitHub's side unread", a, unread)
	}
	if _, ok := failed["tk-bad"]; !ok || len(failed) != 1 {
		t.Errorf("failed = %v, want tk-bad's undecodable read alone", failed)
	}
	for _, q := range s.Finds()[listed:] {
		for _, id := range q.IDs {
			if slices.Contains([]string{"tk-p", "tk-u", "tk-bad"}, id) {
				t.Errorf("PRAnswers read %s again, which the listing holds: %+v", id, q)
			}
		}
		if q.HasKey != "" || q.Key != "" || q.Every {
			t.Errorf("PRAnswers read the store by a key or whole: %+v", q)
		}
	}
}

// PRLabels derives the labels `gctk pr status` gives the labels' writer: a PR
// on the pending record from the evaluator's answer, any other from the facts
// its row and its edges hold, each over the rows of a pass the caller already
// holds (Over), which it lists no second time. A bead nothing reads gets its
// error and no labels.
func TestPRLabelsDeriveWhatTheWriterWrites(t *testing.T) {
	s := rig()
	s.Put(fake.Bead{ID: "tk-p", Title: "ready work", Status: "blocked", IssueType: "task",
		Metadata: onRecord(t, "7", readyRead())})
	pass := ledger.New(s).Pass()
	if _, err := pass.Find(ledger.Every()); err != nil {
		t.Fatal(err)
	}
	listed := len(s.Finds())
	ls, err := Over(pass)
	if err != nil {
		t.Fatal(err)
	}
	labels, failed := ls.PRLabels([]string{"tk-p", "tk-e.2", "tk-gone", "tk-p"})
	want := map[string][]string{
		"tk-p":   {"status: merging"},
		"tk-e.2": {"status: needs-attention", "held: gate"},
	}
	if !reflect.DeepEqual(labels, want) {
		t.Errorf("labels = %q, want %q", labels, want)
	}
	if _, ok := failed["tk-gone"]; !ok || len(failed) != 1 {
		t.Errorf("failed = %v, want tk-gone, which the store does not hold, alone", failed)
	}
	for _, q := range s.Finds()[listed:] {
		if q.HasKey != "" || q.Key != "" || q.Every {
			t.Errorf("PRLabels read the store by a key or whole: %+v", q)
		}
	}
}
