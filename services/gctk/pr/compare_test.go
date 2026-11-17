package pr_test

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The net's cases (specs/tk-1tfzr71.149/design.md, section 2). Each starts
// from the watched world of refresh_test.go once a pass of the cheap question
// has saved every part, then makes a change on GitHub and runs a pass of the
// cheap question and a pass of the net, in that order.

// compare runs one pass of the net and fails if the store's listing did not
// read.
func (d *watched) compare(t *testing.T) pr.PassReport {
	t.Helper()
	rep, err := d.w.Compare(pr.PassOptions{Window: 3 * time.Minute})
	if err != nil {
		t.Fatalf("Compare: %v", err)
	}
	return rep
}

// discussed is the watched world with a review thread and a conversation
// comment, saved by a first pass of the cheap question.
func discussed(t *testing.T) *watched {
	t.Helper()
	d := newWatched(t)
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 400, Author: "operator", Body: "rename this",
		CreatedAt: "2026-11-16T08:00:00Z", UpdatedAt: "2026-11-16T08:00:00Z"}}}}
	d.pr.Comments = []gh.IssueComment{{ID: 300, Author: "operator", Body: "looks fine",
		CreatedAt: "2026-11-16T08:30:00Z", UpdatedAt: "2026-11-16T08:30:00Z"}}
	updated(t, d.poll(t), "pr, checks, conversation, labels")
	return d
}

// onlyTheNetSees fails unless a pass of the cheap question finds nothing moved,
// and then a pass of the net reads reads beside its full read and saves the
// parts named.
func onlyTheNetSees(t *testing.T, d *watched, reads []string, parts string) {
	t.Helper()
	n, writes := len(d.github.Reads()), len(d.store.Writes())
	if rep := d.poll(t); len(rep.Updates) != 0 || len(rep.Failed) != 0 {
		t.Fatalf("the cheap question updated %+v and failed %v, want the change unseen", rep.Updates, rep.Failed)
	}
	if got := d.readsSince(n); !slices.Equal(got, []string{"Signs"}) || len(d.store.Writes()) != writes {
		t.Fatalf("the cheap question read %v and wrote %d times", got, len(d.store.Writes())-writes)
	}
	n = len(d.github.Reads())
	updated(t, d.compare(t), parts)
	if got := d.readsSince(n); !slices.Equal(got, append([]string{"FullRead"}, reads...)) {
		t.Fatalf("the net read %v, want its full read and %v", got, reads)
	}
	if got := d.store.Writes()[writes:]; len(got) != 1 {
		t.Fatalf("the net wrote %d times, want once", len(got))
	}
	// The next pass of the net finds nothing that differs.
	n = len(d.github.Reads())
	if rep := d.compare(t); len(rep.Updates) != 0 || !slices.Equal(d.readsSince(n), []string{"FullRead"}) {
		t.Fatalf("the net's next pass read %v and updated %+v", d.readsSince(n), rep.Updates)
	}
}

// A review thread resolved or reopened moves no cheap sign, so only the net's
// read of each thread's resolution saves it.
func TestTheNetSavesAThreadResolvedOrReopened(t *testing.T) {
	d := discussed(t)
	if got := d.saved(t, bead).Conversation.Unresolved; !slices.Equal(got, []string{"T1"}) {
		t.Fatalf("the first pass saved the unresolved threads %v", got)
	}
	d.pr.Threads[0].Resolved = true
	onlyTheNetSees(t, d, []string{"Login", "Conversation"}, "conversation")
	if got := d.saved(t, bead).Conversation.Unresolved; len(got) != 0 {
		t.Fatalf("the net saved the unresolved threads %v after the thread was resolved", got)
	}
	d.pr.Threads[0].Resolved = false
	onlyTheNetSees(t, d, []string{"Login", "Conversation"}, "conversation")
	if got := d.saved(t, bead).Conversation.Unresolved; !slices.Equal(got, []string{"T1"}) {
		t.Fatalf("the net saved the unresolved threads %v after the thread was reopened", got)
	}
}

// An edit to a post can leave the PR's updatedAt as it was, and moves no
// count, so only the net's read of each post's time saves it. An edit that
// takes out the mark saying a post is not for review turns it into feedback.
func TestTheNetSavesAPostEditThatLeftThePRsUpdatedAtUnmoved(t *testing.T) {
	for _, tc := range []struct {
		name string
		edit func(d *watched)
	}{
		{"a conversation comment", func(d *watched) {
			d.pr.Comments[0].Body, d.pr.Comments[0].UpdatedAt = "looks fine, but", "2026-11-16T09:30:00Z"
		}},
		{"an inline comment", func(d *watched) {
			d.pr.Threads[0].Comments[0].Body = "rename this, and that"
			d.pr.Threads[0].Comments[0].UpdatedAt = "2026-11-16T09:30:00Z"
		}},
		{"a review", func(d *watched) {
			d.pr.Reviews[0].Body, d.pr.Reviews[0].UpdatedAt = "approved, with a thought", "2026-11-16T09:30:00Z"
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := discussed(t)
			before := d.pr.UpdatedAt
			tc.edit(d)
			if d.pr.UpdatedAt != before {
				t.Fatal("the edit moved the PR's updatedAt")
			}
			onlyTheNetSees(t, d, []string{"Login", "Conversation"}, "conversation")
			if got := d.saved(t, bead).Conversation.Signs.NewestPost; got != "2026-11-16T09:30:00Z" {
				t.Fatalf("the net saved the newest post time %q, want the edit's", got)
			}
		})
	}
	t.Run("one that turns a post into feedback", func(t *testing.T) {
		d := newWatched(t)
		d.pr.Comments = []gh.IssueComment{{ID: 300, Author: "operator", Body: "<!-- not for review --> a note",
			CreatedAt: "2026-11-16T08:30:00Z", UpdatedAt: "2026-11-16T08:30:00Z"}}
		d.rule.notFeedback[300] = true
		d.poll(t)
		if got := d.saved(t, bead).Conversation.Feedback.Conversation; got != 0 {
			t.Fatalf("a post marked not for review was saved as feedback %d", got)
		}
		d.pr.Comments[0].Body, d.pr.Comments[0].UpdatedAt = "a note", "2026-11-16T09:30:00Z"
		delete(d.rule.notFeedback, 300)
		onlyTheNetSees(t, d, []string{"Login", "Conversation"}, "conversation")
		if got := d.saved(t, bead).Conversation.Feedback.Conversation; got != 300 {
			t.Fatalf("the net saved the newest conversation feedback %d, want the edited post's 300", got)
		}
	})
}

// A check the PR comes to require, or stops requiring, moves no count, so only
// the net's read of each check run's required flag saves it.
func TestTheNetSavesARequiredChecksFlag(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	required := func() []string {
		var names []string
		for _, r := range d.saved(t, bead).Checks.Runs {
			names = append(names, r.Name)
		}
		return slices.Sorted(slices.Values(names))
	}
	if got := required(); !slices.Equal(got, []string{"test", "test-macos"}) {
		t.Fatalf("the first pass saved the required runs %v", got)
	}
	d.pr.Suites[head][0].Runs[2].Required = true
	onlyTheNetSees(t, d, []string{"PullRequestPart+checks"}, "checks")
	if got := required(); !slices.Equal(got, []string{"size", "test", "test-macos"}) {
		t.Fatalf("the net saved the required runs %v once size was required", got)
	}
	d.pr.Suites[head][0].Runs[0].Required = false
	onlyTheNetSees(t, d, []string{"PullRequestPart+checks"}, "checks")
	if got := required(); !slices.Equal(got, []string{"size", "test-macos"}) {
		t.Fatalf("the net saved the required runs %v once test was no longer required", got)
	}
}

// The other facts no sign shows: a change of the repository's rules can move
// the review decision or the merge state while no review or check moves, and
// a merge queue moves its flags.
func TestTheNetSavesWhatNoSignShows(t *testing.T) {
	for _, tc := range []struct {
		name  string
		move  func(*watched)
		reads []string
		saved string
		check func(*pr.SavedRead) bool
	}{
		{"the review decision", func(d *watched) { d.pr.ReviewDecision = "REVIEW_REQUIRED" },
			[]string{"Login", "Conversation"}, "conversation",
			func(s *pr.SavedRead) bool { return s.Conversation.ReviewDecision == "REVIEW_REQUIRED" }},
		{"the merge state", func(d *watched) { d.pr.Facts.MergeStateStatus = "BLOCKED" },
			[]string{"PullRequestPart"}, "pr", func(s *pr.SavedRead) bool { return s.PR.MergeState == "BLOCKED" }},
		{"the PR entering a merge queue", func(d *watched) { d.pr.Facts.InMergeQueue = true },
			[]string{"PullRequestPart"}, "pr", func(s *pr.SavedRead) bool { return s.PR.InMergeQueue }},
		{"the base coming to require a merge queue", func(d *watched) { d.pr.Facts.MergeQueueEnabled = true },
			[]string{"PullRequestPart"}, "pr", func(s *pr.SavedRead) bool { return s.PR.MergeQueueEnabled }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := newWatched(t)
			d.poll(t)
			tc.move(d)
			onlyTheNetSees(t, d, tc.reads, tc.saved)
			if s := d.saved(t, bead); !tc.check(s) {
				t.Fatalf("the net saved %+v %+v", *s.PR, *s.Conversation)
			}
		})
	}
}

// A pass of the net in which nothing differs reads every owned PR in one read
// and writes no bead. A merge state GitHub reads as UNKNOWN, as it does until
// it has computed one, differs in nothing.
func TestANetPassInWhichNothingDiffersWritesNoBead(t *testing.T) {
	d := discussed(t)
	d.pr.Facts.MergeStateStatus = "UNKNOWN"
	n, writes := len(d.github.Reads()), len(d.store.Writes())
	rep := d.compare(t)
	if len(rep.Updates) != 0 || len(rep.Failed) != 0 || rep.Asked != 1 || rep.Repositories != 1 {
		t.Fatalf("a pass with nothing different reported %+v", rep)
	}
	if got := d.readsSince(n); !slices.Equal(got, []string{"FullRead"}) || len(d.store.Writes()) != writes {
		t.Fatalf("a pass with nothing different read %v and wrote %d times", got, len(d.store.Writes())-writes)
	}
	if asked := d.github.FullAsked(); len(asked) != 1 || !slices.Equal(asked[0], []int{7}) {
		t.Fatalf("the net asked %v", asked)
	}
}

// The net reads the cheap signs too, so a pass of it saves what a moved sign
// shows, and saves every part on a bead that holds no read.
func TestTheNetRunsTheUpdateForMovedSignsToo(t *testing.T) {
	d := newWatched(t)
	updated(t, d.compare(t), "pr, checks, conversation, labels")
	d.pr.Labels = append(d.pr.Labels, "held: you")
	n := len(d.github.Reads())
	updated(t, d.compare(t), "labels")
	if got := d.readsSince(n); !slices.Equal(got, []string{"FullRead"}) {
		t.Fatalf("the net read %v for a moved label, want its full read alone", got)
	}
	if got := d.saved(t, bead).Labels.Names; !slices.Equal(got, []string{"held: you", "status: merging"}) {
		t.Fatalf("the net saved the labels %v", got)
	}
}

func TestAFailedFullReadKeepsTheSavedReadAndFailsThePass(t *testing.T) {
	d := discussed(t)
	before := d.row(t, bead).Metadata["pr_github_read"]
	d.pr.Threads[0].Resolved = true
	d.github.FullFail[7] = errors.New("github: the full read of PR 7 failed: something went wrong")
	writes := len(d.store.Writes())
	rep := d.compare(t)
	if err := rep.Failed[prURL]; err == nil || !strings.Contains(err.Error(), "something went wrong") || len(rep.Updates) != 0 {
		t.Fatalf("the pass updated %+v and failed %v, want the PR failed", rep.Updates, rep.Failed)
	}
	if len(d.store.Writes()) != writes || d.row(t, bead).Metadata["pr_github_read"] != before {
		t.Fatal("a read that failed saved something")
	}
	delete(d.github.FullFail, 7)
	updated(t, d.compare(t), "conversation")
}

// A merged or closed PR's merge state reads UNKNOWN for good, so its PR part
// keeps the signs read with it, and the next pass finds nothing moved.
func TestAMergedPRsUnknownMergeStateIsSavedWithItsSigns(t *testing.T) {
	for _, state := range []string{"MERGED", "CLOSED"} {
		t.Run(state, func(t *testing.T) {
			d := newWatched(t)
			d.poll(t)
			d.pr.Facts.State, d.pr.Facts.MergeStateStatus = state, "UNKNOWN"
			updated(t, d.poll(t), "pr")
			if s := d.saved(t, bead).PR; s.Signs.State != state || s.MergeState != "UNKNOWN" {
				t.Fatalf("saved the PR part %+v", *s)
			}
			n := len(d.github.Reads())
			if rep := d.poll(t); len(rep.Updates) != 0 || !slices.Equal(d.readsSince(n), []string{"Signs"}) {
				t.Fatalf("the pass after the %s read %v and updated %+v", state, d.readsSince(n), rep.Updates)
			}
			n = len(d.github.Reads())
			if rep := d.compare(t); len(rep.Updates) != 0 || !slices.Equal(d.readsSince(n), []string{"FullRead"}) {
				t.Fatalf("the net after the %s read %v and updated %+v", state, d.readsSince(n), rep.Updates)
			}
		})
	}
}
