package pr_test

import (
	"encoding/json"
	"errors"
	"maps"
	"reflect"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// The PR watch's cases (specs/tk-1tfzr71.149/design.md, sections 1, 3, 4, 6
// and 7). Each starts from the bead on the pending record that ready() holds,
// whose PR the evaluator reads ready, with the cheap question's own signs set,
// and a clock that moves a second at each read of it.

// watched is a world as the PR watch reads it.
type watched struct {
	*world
	w     pr.Watcher
	clock time.Time
}

func newWatched(t *testing.T) *watched {
	t.Helper()
	w := ready()
	w.pr.Facts.ID = "PR_7"
	w.pr.Labels = []string{"status: merging"}
	w.pr.UpdatedAt = "2026-11-16T09:00:00Z"
	w.pr.BaseTip = "b000000000000000000000000000000000000000"
	w.pr.ReviewDecision = "APPROVED"
	w.pr.Rollup = "SUCCESS"
	d := &watched{world: w, clock: time.Date(2026, 11, 16, 10, 0, 0, 0, time.UTC)}
	d.w = pr.Watcher{
		Ledger:   ledger.New(w.store),
		Dir:      t.TempDir(),
		GitHub:   func(string) pr.Watch { return w.github },
		Feedback: func() (pr.Feedback, error) { return w.rule, nil },
		Now:      func() time.Time { d.clock = d.clock.Add(time.Second); return d.clock },
		Wait:     5 * time.Second,
	}
	w.put(w.md)
	return d
}

// poll runs one pass and fails if the store's listing did not read.
func (d *watched) poll(t *testing.T) pr.PollReport {
	t.Helper()
	rep, err := d.w.Poll(pr.PollOptions{Window: 90 * time.Second})
	if err != nil {
		t.Fatalf("Poll: %v", err)
	}
	return rep
}

func (d *watched) row(t *testing.T, id string) fake.Bead {
	t.Helper()
	b, ok := d.store.Row(id)
	if !ok {
		t.Fatalf("the store lost %s", id)
	}
	return b
}

// saved is the read saved on id, nil when it carries none.
func (d *watched) saved(t *testing.T, id string) *pr.SavedRead {
	t.Helper()
	raw, ok := d.row(t, id).Metadata["pr_github_read"]
	if !ok {
		return nil
	}
	var s pr.SavedRead
	if err := json.Unmarshal([]byte(raw), &s); err != nil {
		t.Fatalf("the saved read %q does not decode: %v", raw, err)
	}
	return &s
}

// readsSince is GitHub's reads after the first n.
func (d *watched) readsSince(n int) []string { return d.github.Reads()[n:] }

// updated fails unless the pass saved one PR's parts named, and nothing failed.
func updated(t *testing.T, rep pr.PollReport, parts string) {
	t.Helper()
	if len(rep.Failed) != 0 || len(rep.Updates) != 1 {
		t.Fatalf("the pass failed %v and updated %+v, want one update", rep.Failed, rep.Updates)
	}
	if u := rep.Updates[0]; u.Action != pr.ActSaved || !strings.HasSuffix(u.Detail, "saved "+parts) {
		t.Fatalf("the update %s (%s), want %q saved", u.Action, u.Detail, parts)
	}
}

func TestTheFirstPassReadsAndSavesEveryPart(t *testing.T) {
	d := newWatched(t)
	updated(t, d.poll(t), "pr, checks, conversation, labels")
	if got := d.github.Reads(); !slices.Equal(got, []string{"Signs", "PullRequestPart+checks", "Login", "Conversation"}) {
		t.Fatalf("the pass read %v", got)
	}
	s := d.saved(t, bead)
	if s.PR == nil || s.Checks == nil || s.Conversation == nil || s.Labels == nil {
		t.Fatalf("the pass saved %+v, want every part", s)
	}
	if s.PR.Head != head || s.Checks.Head != head || s.PR.Signs.BaseTip != d.pr.BaseTip ||
		!slices.Equal(s.Labels.Names, []string{"status: merging"}) || s.Conversation.ReviewDecision != "APPROVED" {
		t.Fatalf("the saved read is not GitHub's side: %+v %+v %+v %+v", *s.PR, *s.Checks, *s.Conversation, *s.Labels)
	}
	// A part's signs are read no later than its facts.
	if s.Labels.ReadAt >= s.PR.ReadAt || s.PR.ReadAt >= s.Conversation.ReadAt {
		t.Fatalf("the parts were read at %s, %s and %s, want the signs first", s.Labels.ReadAt, s.PR.ReadAt,
			s.Conversation.ReadAt)
	}
	b := d.row(t, bead)
	meta(t, b, map[string]string{"pr_state": "open"})
	if at := b.Metadata["pr_last_checked_at"]; !regexp.MustCompile(`^2026-11-16T10:00:[0-9]{2}Z$`).MatchString(at) {
		t.Fatalf("pr_last_checked_at %q is not the update's stamp to the second", at)
	}

	// The saved read answers as the live read does.
	md := maps.Clone(b.Metadata)
	live, _ := d.live(t)
	if got := d.fromStore(t, md); !reflect.DeepEqual(got, live) {
		t.Fatalf("over the saved read the rule answers\n%+v\nand live\n%+v", got, live)
	}
}

func TestAPassInWhichNothingMovedWritesNoBead(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	reads, writes := len(d.github.Reads()), len(d.store.Writes())
	rep := d.poll(t)
	if len(rep.Updates) != 0 || len(rep.Failed) != 0 || rep.Asked != 1 || rep.Repositories != 1 {
		t.Fatalf("an unmoved pass reported %+v", rep)
	}
	if got := d.readsSince(reads); !slices.Equal(got, []string{"Signs"}) {
		t.Fatalf("an unmoved pass read %v, want the cheap question alone", got)
	}
	if got := d.store.Writes()[writes:]; len(got) != 0 {
		t.Fatalf("an unmoved pass wrote %+v", got)
	}
}

// A saved read that does not decode as the four parts, such as one whose
// checks are a list, is read as none: the pass reads every part and saves the
// four over it.
func TestASavedReadThatDoesNotDecodeIsReadWholeAndReplaced(t *testing.T) {
	d := newWatched(t)
	b, _ := d.store.Row(bead)
	b.Metadata = maps.Clone(b.Metadata)
	b.Metadata["pr_github_read"] = `{"read_at":"2026-11-16T09:00:00Z","head":"` + head +
		`","checks":[{"name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]}`
	d.store.Put(b)
	updated(t, d.poll(t), "pr, checks, conversation, labels")
	if s := d.saved(t, bead); s.PR == nil || s.Checks == nil || s.Conversation == nil || s.Labels == nil {
		t.Fatalf("the pass saved %+v over a read that does not decode, want every part", s)
	}
}

// Each sign that moved reads its row of the update's table, and the update
// saves the parts whose facts or signs differ (section 4).
func TestEachSignsMoveReadsItsRowOfTheTable(t *testing.T) {
	for _, tc := range []struct {
		name  string
		move  func(*watched)
		reads []string
		saved string
	}{
		{"a label", func(d *watched) { d.pr.Labels = append(d.pr.Labels, "held: you") },
			nil, "labels"},
		{"the base's tip", func(d *watched) { d.pr.BaseTip = "c000000000000000000000000000000000000000" },
			[]string{"PullRequestPart"}, "pr"},
		{"when GitHub last changed the PR, as an edit of a post moves it", func(d *watched) {
			d.pr.UpdatedAt = "2026-11-16T09:05:00Z"
		}, []string{"PullRequestPart", "Login", "Conversation"}, "pr, conversation"},
		{"the head", func(d *watched) {
			d.pr.Facts.HeadRefOid = other
			d.pr.Suites[other] = d.pr.Suites[head]
		}, []string{"PullRequestPart+checks"}, "pr, checks"},
		{"a finished check", func(d *watched) {
			d.pr.Suites[head] = []gh.CheckSuite{{ID: 1, Runs: []gh.CheckRun{
				{Name: "test", Status: "COMPLETED", Conclusion: "FAILURE", Required: true}, passed("test-macos")}}}
		}, []string{"PullRequestPart+checks"}, "checks"},
		{"a commit status", func(d *watched) { d.pr.Statuses = map[string]int{"PENDING": 1} },
			[]string{"PullRequestPart+checks"}, "checks"},
		{"the rollup's state", func(d *watched) { d.pr.Rollup = "PENDING" },
			[]string{"PullRequestPart+checks"}, "checks"},
		{"a conversation comment", func(d *watched) {
			d.pr.Comments = append(d.pr.Comments, gh.IssueComment{ID: 300, Author: "operator", Body: "and this",
				CreatedAt: "2026-11-16T09:10:00Z", UpdatedAt: "2026-11-16T09:10:00Z"})
		}, []string{"PullRequestPart", "Login", "Conversation"}, "conversation"},
		{"an inline comment", func(d *watched) {
			d.pr.Threads = append(d.pr.Threads, gh.Thread{ID: "T9", Comments: []gh.Comment{{ID: 400,
				Author: "operator", Body: "rename", CreatedAt: "2026-11-16T09:10:00Z", UpdatedAt: "2026-11-16T09:10:00Z"}}})
		}, []string{"PullRequestPart", "Login", "Conversation"}, "conversation"},
		{"a review", func(d *watched) {
			d.pr.Reviews = append(d.pr.Reviews, gh.Review{ID: 101, State: "COMMENTED", Body: "a thought",
				Author: "operator", AuthorCanPush: true, SubmittedAt: "2026-11-16T09:10:00Z"})
		}, []string{"PullRequestPart", "Login", "Conversation"}, "conversation"},
		{"a dismissed review", func(d *watched) { d.pr.Reviews[0].State = "DISMISSED" },
			[]string{"PullRequestPart", "Login", "Conversation"}, "conversation"},
		{"a merge", func(d *watched) { d.pr.Facts.State = "MERGED" },
			[]string{"PullRequestPart"}, "pr"},
		{"the draft flag", func(d *watched) { d.pr.Facts.IsDraft = true },
			[]string{"PullRequestPart"}, "pr"},
		{"the bead's provenance instant, which makes the saved read not current", func(d *watched) {
			b, _ := d.store.Row(bead)
			b.Metadata = maps.Clone(b.Metadata)
			b.Metadata["pr_provenance_since"] = "2026-11-16T08:00:00Z"
			d.store.Put(b)
		}, []string{"PullRequestPart+checks", "Login", "Conversation"}, "conversation"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := newWatched(t)
			d.poll(t)
			reads, writes := len(d.github.Reads()), len(d.store.Writes())
			tc.move(d)
			rep := d.poll(t)
			updated(t, rep, tc.saved)
			if got := d.readsSince(reads); !slices.Equal(got, append([]string{"Signs"}, tc.reads...)) {
				t.Fatalf("the pass read %v, want the signs and %v", got, tc.reads)
			}
			ws := d.store.Writes()[writes:]
			if len(ws) != 1 {
				t.Fatalf("the pass wrote %d times, want once: %+v", len(ws), ws)
			}
			args := strings.Join(ws[0].Args, " ")
			for _, want := range []string{"--if-status=blocked", "--if-assignee=rig/refinery", "pr_github_read=",
				"pr_state=", "pr_last_checked_at="} {
				if !strings.Contains(args, want) {
					t.Errorf("the write %q lacks %q", args, want)
				}
			}
			// The next pass finds nothing moved, unless the PR's head is
			// another than the store holds.
			if tc.name == "the head" {
				return
			}
			reads = len(d.github.Reads())
			if rep := d.poll(t); len(rep.Updates) != 0 || !slices.Equal(d.readsSince(reads), []string{"Signs"}) {
				t.Fatalf("the pass after the update read %v and updated %+v", d.readsSince(reads), rep.Updates)
			}
		})
	}
}

// A merge or a close is saved as GitHub's state, lower-cased, in pr_state.
func TestTheUpdateSavesThePRsStateInPRState(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	d.pr.Facts.State = "MERGED"
	d.poll(t)
	meta(t, d.row(t, bead), map[string]string{"pr_state": "merged"})
}

// Two updates of one PR can cross: the one whose read was sent first must not
// write over the part the later read saved (section 7).
func TestAnOlderReadNeverReplacesANewerOne(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	d.pr.BaseTip = "c000000000000000000000000000000000000000"
	crossed := false
	d.github.OnRead = func(method string, p *ghfake.PR) {
		if method != "PullRequestPart" || crossed {
			return
		}
		crossed = true
		// The later update reads the merge state GitHub computed since, and
		// saves it first.
		p.Facts.MergeStateStatus = "BLOCKED"
		if _, err := d.w.Refresh(prURL); err != nil {
			t.Errorf("the later update: %v", err)
		}
		p.Facts.MergeStateStatus = "CLEAN"
	}
	rep := d.poll(t)
	if len(rep.Failed) != 0 || len(rep.Updates) != 1 || rep.Updates[0].Action != pr.ActUnchanged {
		t.Fatalf("the earlier update reported %+v, failed %v, want it to save nothing", rep.Updates, rep.Failed)
	}
	if s := d.saved(t, bead); s.PR.MergeState != "BLOCKED" {
		t.Fatalf("the saved merge state is %s, want the later read's BLOCKED", s.PR.MergeState)
	}
}

func TestAFailedReadKeepsTheSavedSignsAndFailsThePass(t *testing.T) {
	t.Run("the cheap question fails for one PR alone", func(t *testing.T) {
		d := newWatched(t)
		eight := &ghfake.PR{Facts: gh.PullRequest{ID: "PR_8", Number: 8, URL: "https://github.com/acme/widgets/pull/8",
			State: "OPEN", HeadRefName: "polecat/tk-8", HeadRefOid: other, BaseRefName: "main", MergeStateStatus: "CLEAN",
			Repository: repo}}
		d.github.Put(eight)
		md := maps.Clone(d.md)
		md["pr_url"], md["pr_number"], md["branch"], md["pr_head_sha"] = eight.Facts.URL, "8", "polecat/tk-8", other
		d.store.Put(fake.Bead{ID: "tk-8", Status: "blocked", Assignee: refinery, Metadata: md})
		d.github.SignsFail[7] = errors.New("github: the signs of PR 7 failed: something went wrong")
		rep := d.poll(t)
		if rep.Failed[prURL] == nil || len(rep.Updates) != 1 || rep.Updates[0].Bead != "tk-8" {
			t.Fatalf("the pass updated %+v and failed %v, want PR 8 updated and PR 7 failed", rep.Updates, rep.Failed)
		}
		if d.saved(t, bead) != nil {
			t.Fatal("a PR whose signs failed had a read saved")
		}
		if asked := d.github.SignsAsked(); len(asked) != 1 || !slices.Equal(asked[0], []int{7, 8}) {
			t.Fatalf("the cheap question asked %v, want both PRs in one request", asked)
		}
	})
	for name, fail := range map[string]func(*watched){
		"a part's read":              func(d *watched) { d.github.Fail["Conversation"] = errors.New("github: HTTP 502") },
		"the login":                  func(d *watched) { d.github.Fail["Login"] = errors.New("github: HTTP 502") },
		"the definition of feedback": func(d *watched) { d.rule.err = errors.New("jq: failed") },
	} {
		t.Run(name, func(t *testing.T) {
			d := newWatched(t)
			d.poll(t)
			before := d.row(t, bead).Metadata["pr_github_read"]
			writes := len(d.store.Writes())
			d.pr.UpdatedAt = "2026-11-16T09:05:00Z"
			fail(d)
			rep := d.poll(t)
			if rep.Failed[prURL] == nil || len(rep.Updates) != 0 {
				t.Fatalf("the pass updated %+v and failed %v, want the PR failed", rep.Updates, rep.Failed)
			}
			if got := d.store.Writes()[writes:]; len(got) != 0 || d.row(t, bead).Metadata["pr_github_read"] != before {
				t.Fatalf("a read that failed saved %+v", got)
			}
			// The signs stay as they were, so the next pass reads the PR again.
			delete(d.github.Fail, "Conversation")
			delete(d.github.Fail, "Login")
			d.rule.err = nil
			updated(t, d.poll(t), "pr, conversation")
		})
	}
}

// GitHub computes a merge state after a push or a base move: a read of it as
// unknown is saved, and the PR part keeps its earlier signs, so the next pass
// reads the part again (section 4).
func TestAMergeStateReadUnknownKeepsThePartsEarlierSigns(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	first := d.saved(t, bead).PR.Signs
	d.pr.BaseTip = "c000000000000000000000000000000000000000"
	d.pr.Facts.MergeStateStatus = "UNKNOWN"
	updated(t, d.poll(t), "pr")
	s := d.saved(t, bead)
	if s.PR.MergeState != "UNKNOWN" || s.PR.Signs != first {
		t.Fatalf("saved %s with signs %+v, want UNKNOWN with the earlier signs %+v", s.PR.MergeState, s.PR.Signs, first)
	}
	reads := len(d.github.Reads())
	d.pr.Facts.MergeStateStatus = "CLEAN"
	updated(t, d.poll(t), "pr")
	if got := d.readsSince(reads); !slices.Equal(got, []string{"Signs", "PullRequestPart"}) {
		t.Fatalf("the next pass read %v, want the PR part again", got)
	}
	if s := d.saved(t, bead); s.PR.MergeState != "CLEAN" || s.PR.Signs.BaseTip != d.pr.BaseTip {
		t.Fatalf("the next pass saved %+v", *s.PR)
	}
}

// A PR is owned by the live bead that names it as its own and is no other
// bead's child (section 1).
func TestThePollAsksAboutEveryPRALiveBeadOwns(t *testing.T) {
	d := newWatched(t)
	url := func(n string) string { return "https://github.com/acme/widgets/pull/" + n }
	for _, b := range []fake.Bead{
		{ID: "tk-sent", Status: "open", Assignee: refinery, Metadata: map[string]string{
			"merge_result": "pull_request_record_incomplete", "existing_pr": url("11")}},
		{ID: "tk-old", Status: "open", Metadata: map[string]string{"merge_result": "pull_request", "pr_url": url("12")}},
		{ID: "tk-child", Status: "open", Metadata: map[string]string{"pr_url": url("13"), "existing_pr": url("13"),
			"anchor_bead": "tk-old"}},
		{ID: "tk-closed", Status: "closed", Metadata: map[string]string{"merge_result": "mr_merged", "pr_url": url("14")}},
		{ID: "tk-unrecorded", Status: "open", Metadata: map[string]string{"pr_url": url("15")}},
	} {
		d.store.Put(b)
	}
	rep := d.poll(t)
	if asked := d.github.SignsAsked(); len(asked) != 1 || !slices.Equal(asked[0], []int{7, 11, 12}) {
		t.Fatalf("the cheap question asked %v, want the PRs of the anchor, the bead sent back and the old path", asked)
	}
	if rep.Asked != 3 {
		t.Fatalf("the pass asked about %d PRs, want 3", rep.Asked)
	}
}

// A bead on the old path owns its PR too, and gets the saved read, with no key
// of the pending record's.
func TestTheUpdateWritesNoRecordKeyOffThePendingRecord(t *testing.T) {
	d := newWatched(t)
	md := maps.Clone(d.md)
	md["merge_result"] = "pull_request"
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: "open", Metadata: md})
	updated(t, d.poll(t), "pr, checks, conversation, labels")
	meta(t, d.row(t, bead), map[string]string{"pr_state": "<absent>", "pr_last_checked_at": "<absent>"})
}

func TestAPRTwoLiveBeadsOwnIsSavedOnNeither(t *testing.T) {
	d := newWatched(t)
	d.store.Put(fake.Bead{ID: "tk-twin", Status: "blocked", Assignee: refinery, Metadata: maps.Clone(d.md)})
	rep := d.poll(t)
	if err := rep.Failed[prURL]; err == nil || !strings.Contains(err.Error(), "tk-1, tk-twin") {
		t.Fatalf("a PR two beads own failed as %v", err)
	}
	if len(d.store.Writes()) != 0 || len(d.github.SignsAsked()) != 0 {
		t.Fatalf("a PR two beads own was asked %v or saved %+v", d.github.SignsAsked(), d.store.Writes())
	}
}

// A pass starts no update past its window, and the PRs it leaves keep their
// signs, so the next pass reads them.
func TestThePollStartsNoUpdatePastItsWindow(t *testing.T) {
	d := newWatched(t)
	eight := *d.pr
	eight.Facts.Number, eight.Facts.URL, eight.Facts.ID = 8, "https://github.com/acme/widgets/pull/8", "PR_8"
	d.github.Put(&eight)
	md := maps.Clone(d.md)
	md["pr_url"], md["pr_number"] = eight.Facts.URL, "8"
	d.store.Put(fake.Bead{ID: "tk-8", Status: "blocked", Assignee: refinery, Metadata: md})
	// Each read of the clock moves it 20 seconds: PR 7's update starts 40
	// seconds in and reads it three times, so PR 8's would start 120 seconds in.
	d.w.Now = func() time.Time { d.clock = d.clock.Add(20 * time.Second); return d.clock }
	rep, err := d.w.Poll(pr.PollOptions{Window: 90 * time.Second})
	if err != nil {
		t.Fatal(err)
	}
	if len(rep.Updates) != 1 || rep.Updates[0].Bead != bead || !slices.Equal(rep.Late, []string{eight.Facts.URL}) {
		t.Fatalf("the pass updated %+v and left %v, want PR 7 updated and PR 8 left", rep.Updates, rep.Late)
	}
	if d.saved(t, "tk-8") != nil {
		t.Fatal("a PR the window left was saved")
	}
}

func TestARefreshOfAPRNoLiveBeadOwnsSavesNothing(t *testing.T) {
	d := newWatched(t)
	got, err := d.w.Refresh("https://github.com/acme/widgets/pull/99")
	if err != nil || got.Action != pr.ActUnowned {
		t.Fatalf("a refresh of an unowned PR answered %+v, %v", got, err)
	}
	if len(d.github.Reads()) != 0 || len(d.store.Writes()) != 0 {
		t.Fatalf("it read %v and wrote %+v", d.github.Reads(), d.store.Writes())
	}
	if _, err := d.w.Refresh("not a url"); err == nil {
		t.Fatal("a refresh of no PR's URL answered")
	}
}

// Called alone, as a webhook's rule can call it, the update reads the PR's signs
// itself, and then what they say moved.
func TestARefreshAloneReadsThePRsSignsItself(t *testing.T) {
	d := newWatched(t)
	got, err := d.w.Refresh(prURL)
	if err != nil || got.Action != pr.ActSaved || got.Bead != bead {
		t.Fatalf("the refresh answered %+v, %v", got, err)
	}
	if reads := d.github.Reads(); !slices.Equal(reads, []string{"Signs", "PullRequestPart+checks", "Login", "Conversation"}) {
		t.Fatalf("the refresh read %v", reads)
	}
	if asked := d.github.SignsAsked(); len(asked) != 1 || !slices.Equal(asked[0], []int{7}) {
		t.Fatalf("the refresh asked %v, want its PR alone", asked)
	}
	got, err = d.w.Refresh(prURL)
	if err != nil || got.Action != pr.ActUnchanged {
		t.Fatalf("a refresh with nothing moved answered %+v, %v", got, err)
	}
}

// The write is guarded on the status and assignee the update read under the
// lock, so a bead that moved since gets nothing.
func TestAnUpdateWritesNothingOnABeadThatMovedSinceItsRead(t *testing.T) {
	d := newWatched(t)
	d.store.BeforeUpdate = func(id string, _ []string) error {
		b, _ := d.store.Row(id)
		b.Status = "closed"
		d.store.Put(b)
		return nil
	}
	rep := d.poll(t)
	if err := rep.Failed[prURL]; err == nil || !strings.Contains(err.Error(), "moved") {
		t.Fatalf("an update on a bead that moved failed as %v", err)
	}
	if d.saved(t, bead) != nil {
		t.Fatal("the update wrote over a bead that moved")
	}
}

// The saved read names its parts and fields as the key's declaration says.
func TestTheSavedReadsFields(t *testing.T) {
	d := newWatched(t)
	d.poll(t)
	var parts map[string]map[string]json.RawMessage
	if err := json.Unmarshal([]byte(d.row(t, bead).Metadata["pr_github_read"]), &parts); err != nil {
		t.Fatal(err)
	}
	want := map[string][]string{
		"pr": {"base", "draft", "head", "head_branch", "in_merge_queue", "merge_queue_enabled", "merge_state",
			"number", "read_at", "repository", "signs", "state", "url"},
		"checks": {"head", "read_at", "runs", "signs"},
		"conversation": {"approvers", "awaiting", "feedback", "read_at", "requesters", "review_decision", "signs",
			"since", "unresolved"},
		"labels": {"names", "read_at"},
	}
	signs := map[string][]string{
		"pr":           {"base", "base_tip", "draft", "head", "state", "updated_at"},
		"checks":       {"check_runs", "contexts", "head", "rollup", "statuses"},
		"conversation": {"comments", "dismissed", "newest_post", "reviews", "updated_at"},
	}
	if got := slices.Sorted(maps.Keys(parts)); !slices.Equal(got, []string{"checks", "conversation", "labels", "pr"}) {
		t.Fatalf("the saved read's parts are %v", got)
	}
	for part, fields := range want {
		if got := slices.Sorted(maps.Keys(parts[part])); !slices.Equal(got, fields) {
			t.Errorf("the %s part names %v, want %v", part, got, fields)
		}
		if s, ok := signs[part]; ok {
			var named map[string]json.RawMessage
			if err := json.Unmarshal(parts[part]["signs"], &named); err != nil {
				t.Fatal(err)
			}
			if got := slices.Sorted(maps.Keys(named)); !slices.Equal(got, s) {
				t.Errorf("the %s part's signs name %v, want %v", part, got, s)
			}
		}
	}
	// Only the runs the PR requires are kept.
	if got := string(parts["checks"]["runs"]); !strings.Contains(got, `"name":"test"`) || strings.Contains(got, `"size"`) {
		t.Errorf("the checks' runs encode as %s, want the required runs alone", got)
	}
	var unresolved []string
	if err := json.Unmarshal(parts["conversation"]["unresolved"], &unresolved); err != nil || unresolved == nil {
		t.Errorf("unresolved encodes as %s, want a list", parts["conversation"]["unresolved"])
	}
}

// The newest post time is the latest time any post changed, an edit's
// included, and the unresolved threads are kept, sorted.
func TestTheConversationKeepsItsNewestPostAndUnresolvedThreads(t *testing.T) {
	d := newWatched(t)
	d.pr.Threads = []gh.Thread{
		{ID: "T2", Comments: []gh.Comment{{ID: 400, Author: "operator", Body: "a", CreatedAt: "2026-11-16T08:00:00Z",
			UpdatedAt: "2026-11-16T09:30:00Z"}}},
		{ID: "T1", Resolved: true, Comments: []gh.Comment{{ID: 401, Author: "operator", Body: "b",
			CreatedAt: "2026-11-16T08:00:00Z", UpdatedAt: "2026-11-16T08:00:00Z"}}},
		{ID: "T0", Comments: []gh.Comment{{ID: 402, Author: "operator", Body: "c", CreatedAt: "2026-11-16T08:00:00Z",
			UpdatedAt: "2026-11-16T08:00:00Z"}}},
	}
	d.pr.Comments = []gh.IssueComment{{ID: 500, Author: "operator", Body: "d", CreatedAt: "2026-11-16T07:00:00Z",
		UpdatedAt: "2026-11-16T07:00:00Z"}}
	d.poll(t)
	c := d.saved(t, bead).Conversation
	if c.Signs.NewestPost != "2026-11-16T09:30:00Z" || !slices.Equal(c.Unresolved, []string{"T0", "T2"}) {
		t.Fatalf("kept newest post %q and unresolved %v", c.Signs.NewestPost, c.Unresolved)
	}
}
