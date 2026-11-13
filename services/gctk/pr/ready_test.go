package pr_test

import (
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// Each test starts from a PR the evaluator reads ready, and changes the one
// condition it is about. The store and GitHub are the adapters' fakes, and the
// definition of feedback is a test double that reads every post as feedback
// unless a test names it, since the definition itself is pr-post.sh's and the
// feedback adapter's own tests run it.

const (
	bead   = "tk-1"
	repo   = "acme/widgets"
	prURL  = "https://github.com/acme/widgets/pull/7"
	head   = "1111111111111111111111111111111111111111"
	other  = "2222222222222222222222222222222222222222"
	branch = "polecat/tk-1"
	self   = "zook-bot"
)

// rule is the definition of feedback as a test sets it.
type rule struct {
	notFeedback map[int64]bool
	awaits      map[string]bool
	err         error
}

func (r *rule) Reviews(_, _ string, reviews []feedback.Review) ([]int64, error) {
	var out []int64
	for _, v := range reviews {
		if !r.notFeedback[v.ID] {
			out = append(out, v.ID)
		}
	}
	return out, r.err
}

func (r *rule) comments(cs []feedback.Comment) ([]int64, error) {
	var out []int64
	for _, c := range cs {
		if !r.notFeedback[c.ID] {
			out = append(out, c.ID)
		}
	}
	return out, r.err
}

func (r *rule) Comments(_, _ string, cs []feedback.Comment) ([]int64, error) { return r.comments(cs) }

func (r *rule) IssueComments(_, _ string, cs []feedback.Comment) ([]int64, error) {
	return r.comments(cs)
}

func (r *rule) Awaiting(_, _ string, ts []feedback.Thread) ([]string, error) {
	var out []string
	for _, t := range ts {
		if r.awaits[t.ID] {
			out = append(out, t.ID)
		}
	}
	return out, r.err
}

// world is one bead on the pending record and its PR on GitHub.
type world struct {
	store  *fake.Store
	github *ghfake.GitHub
	rule   *rule
	pr     *ghfake.PR
	md     map[string]string
	edges  []gcbd.Edge
	others []fake.Bead
}

func approve(id int64, login, at string) gh.Review {
	return gh.Review{ID: id, State: "APPROVED", Author: login, AuthorCanPush: true, SubmittedAt: at}
}

func run(name, status, conclusion string) gh.CheckRun {
	return gh.CheckRun{Name: name, Status: status, Conclusion: conclusion, Required: true}
}

func passed(name string) gh.CheckRun { return run(name, "COMPLETED", "SUCCESS") }

// ready is a PR every condition holds for: approved by an account that can
// push, its required checks passed at the head the refinery validated, the
// review loop's result passed there, and nothing else holding it.
func ready() *world {
	p := &ghfake.PR{
		Facts: gh.PullRequest{Number: 7, URL: prURL, State: "OPEN", HeadRefName: branch, HeadRefOid: head,
			BaseRefName: "main", MergeStateStatus: "CLEAN", Repository: repo},
		Reviews: []gh.Review{approve(100, "operator", "2026-11-12T01:00:00Z")},
		Suites: map[string][]gh.CheckSuite{head: {
			{ID: 1, Runs: []gh.CheckRun{passed("test"), passed("test-macos"),
				{Name: "size", Status: "COMPLETED", Conclusion: "FAILURE"}}},
		}},
	}
	g := ghfake.New(self)
	g.Put(p)
	return &world{
		store: fake.New(), github: g, pr: p,
		rule: &rule{notFeedback: map[int64]bool{}, awaits: map[string]bool{}},
		md: map[string]string{
			"merge_result": "pull_request_pending", "pr_url": prURL, "pr_number": "7", "pr_repo": repo,
			"pr_head_sha": head, "merged_target": "main", "branch": branch,
			"review_results": `[{"head":"` + head + `","target":"main","passed":true}]`,
		},
	}
}

func (w *world) answer(t *testing.T) pr.Answer {
	t.Helper()
	w.store.Put(fake.Bead{ID: bead, Title: "the work", Status: "blocked", Assignee: "rig/refinery",
		Metadata: w.md, Edges: w.edges})
	for _, b := range w.others {
		w.store.Put(b)
	}
	ans, err := pr.Ready(pr.Sources{
		Ledger:   ledger.New(w.store),
		GitHub:   func(string) pr.GitHub { return w.github },
		Feedback: w.rule,
	}, bead)
	if err != nil {
		t.Fatalf("Ready: %v", err)
	}
	return ans
}

func kinds(a pr.Answer) []pr.Kind {
	var out []pr.Kind
	for _, c := range a.Conditions {
		out = append(out, c.Kind)
	}
	return out
}

// only fails unless the answer is not ready, for exactly the kinds named.
func only(t *testing.T, a pr.Answer, want ...pr.Kind) {
	t.Helper()
	if a.Ready || !reflect.DeepEqual(kinds(a), want) {
		t.Fatalf("ready=%v conditions=%+v, want not ready for %v", a.Ready, a.Conditions, want)
	}
}

func isReady(t *testing.T, a pr.Answer) {
	t.Helper()
	if !a.Ready || len(a.Conditions) != 0 {
		t.Fatalf("ready=%v conditions=%+v, want ready", a.Ready, a.Conditions)
	}
	if a.Head != head || a.Target != "main" {
		t.Fatalf("judged head %q target %q, want %q into main", a.Head, a.Target, head)
	}
}

func TestReadyAnswersWithTheHeadAndTargetItJudged(t *testing.T) {
	a := ready().answer(t)
	isReady(t, a)
	raw, err := json.Marshal(a)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"conditions":[]`) {
		t.Fatalf("a ready answer encodes as %s, want its conditions an empty array", raw)
	}
}

func TestApproval(t *testing.T) {
	cases := []struct {
		name    string
		reviews []gh.Review
		want    []pr.Kind
	}{
		{"an approval from the city's account counts like any other account's",
			[]gh.Review{approve(100, self, "2026-11-12T01:00:00Z")}, nil},
		{"an approval from an account that cannot push counts for nothing",
			[]gh.Review{{ID: 100, State: "APPROVED", Author: "visitor", SubmittedAt: "2026-11-12T01:00:00Z"}},
			[]pr.Kind{pr.KindApproval}},
		{"a request for changes from an account that cannot push holds nothing",
			[]gh.Review{approve(100, "operator", "2026-11-12T01:00:00Z"),
				{ID: 101, State: "CHANGES_REQUESTED", Author: "visitor", SubmittedAt: "2026-11-12T02:00:00Z"}},
			nil},
		{"an approval followed by a review that only comments still counts",
			[]gh.Review{approve(100, "operator", "2026-11-12T01:00:00Z"),
				{ID: 101, State: "COMMENTED", Author: "operator", AuthorCanPush: true, SubmittedAt: "2026-11-12T02:00:00Z"}},
			nil},
		{"a dismissed approval counts for nothing",
			[]gh.Review{{ID: 100, State: "DISMISSED", Author: "operator", AuthorCanPush: true, SubmittedAt: "2026-11-12T01:00:00Z"}},
			[]pr.Kind{pr.KindApproval}},
		{"a request for changes after the same account's approval stands",
			[]gh.Review{approve(100, "operator", "2026-11-12T01:00:00Z"),
				{ID: 101, State: "CHANGES_REQUESTED", Author: "operator", AuthorCanPush: true, SubmittedAt: "2026-11-12T02:00:00Z"}},
			[]pr.Kind{pr.KindApproval, pr.KindChangesRequested}},
		{"an approval after the same account's request for changes lifts it",
			[]gh.Review{{ID: 100, State: "CHANGES_REQUESTED", Author: "operator", AuthorCanPush: true, SubmittedAt: "2026-11-12T01:00:00Z"},
				approve(101, "operator", "2026-11-12T02:00:00Z")},
			nil},
		{"one account's request for changes holds the PR beside another's approval",
			[]gh.Review{approve(100, "operator", "2026-11-12T01:00:00Z"),
				{ID: 101, State: "CHANGES_REQUESTED", Author: "maintainer", AuthorCanPush: true, SubmittedAt: "2026-11-12T02:00:00Z"}},
			[]pr.Kind{pr.KindChangesRequested}},
		{"no review at all leaves no approval",
			nil, []pr.Kind{pr.KindApproval}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w := ready()
			w.pr.Reviews = c.reviews
			a := w.answer(t)
			if c.want == nil {
				isReady(t, a)
				return
			}
			only(t, a, c.want...)
		})
	}
}

func TestReviewResultCountsOnlyAtTheLiveHeadAndTarget(t *testing.T) {
	cases := map[string]string{
		"a result for another head":  `[{"head":"` + other + `","target":"main","passed":true}]`,
		"a result for another base":  `[{"head":"` + head + `","target":"release","passed":true}]`,
		"a result that did not pass": `[{"head":"` + head + `","target":"main","passed":false}]`,
		"no result":                  ``,
	}
	for name, results := range cases {
		t.Run(name, func(t *testing.T) {
			w := ready()
			if results == "" {
				delete(w.md, "review_results")
			} else {
				w.md["review_results"] = results
			}
			only(t, w.answer(t), pr.KindReview)
		})
	}
	t.Run("a branch taken back to a head the loop judged finds that head's result again", func(t *testing.T) {
		w := ready()
		w.md["review_results"] = `[{"head":"` + head + `","target":"main","passed":true},{"head":"` + other + `","target":"main","passed":false}]`
		isReady(t, w.answer(t))
	})
}

func TestHeadOtherThanTheValidatedOne(t *testing.T) {
	w := ready()
	w.pr.Facts.HeadRefOid = other
	w.pr.Suites[other] = w.pr.Suites[head]
	w.md["review_results"] = `[{"head":"` + other + `","target":"main","passed":true}]`
	a := w.answer(t)
	only(t, a, pr.KindHead)
	if a.Head != other {
		t.Fatalf("judged head %q, want the live head %q", a.Head, other)
	}
}

func TestEachMergeState(t *testing.T) {
	for _, state := range []string{"BEHIND", "BLOCKED", "DIRTY", "DRAFT", "HAS_HOOKS", "UNKNOWN"} {
		t.Run(state, func(t *testing.T) {
			w := ready()
			w.pr.Facts.MergeStateStatus = state
			a := w.answer(t)
			only(t, a, pr.KindMergeState)
			if a.Conditions[0].Value != state {
				t.Fatalf("value %q, want %q", a.Conditions[0].Value, state)
			}
		})
	}
	t.Run("CLEAN", func(t *testing.T) { isReady(t, ready().answer(t)) })
	// UNSTABLE says a check the base does not require is not passing. Each
	// required check is the evaluator's own read, so that is what holds.
	t.Run("UNSTABLE, every required check passed", func(t *testing.T) {
		w := ready()
		w.pr.Facts.MergeStateStatus = "UNSTABLE"
		isReady(t, w.answer(t))
	})
	t.Run("UNSTABLE, a required check failed", func(t *testing.T) {
		w := ready()
		w.pr.Facts.MergeStateStatus = "UNSTABLE"
		w.pr.Suites[head] = []gh.CheckSuite{{ID: 1, Runs: []gh.CheckRun{run("test", "COMPLETED", "FAILURE"), passed("test-macos")}}}
		only(t, w.answer(t), pr.KindCheckFailed)
	})
}

func TestRequiredChecks(t *testing.T) {
	skip := func(name string) gh.CheckRun { return run(name, "COMPLETED", "SKIPPED") }
	suite := func(id int64, runs ...gh.CheckRun) gh.CheckSuite {
		return gh.CheckSuite{ID: id, Runs: append(runs, passed("test-macos"))}
	}
	cases := []struct {
		name   string
		suites []gh.CheckSuite
		want   []pr.Kind
	}{
		// A suite's creation time is not read, so the order in which GitHub
		// created the suites changes nothing: only the results they hold do.
		{"only skips, from a suite created before the last ready-for-review event",
			[]gh.CheckSuite{suite(1, skip("test"))}, []pr.Kind{pr.KindCheckPending}},
		{"only skips, from suites created before the ready event and after it",
			[]gh.CheckSuite{suite(1, skip("test")), suite(2, skip("test"))}, []pr.Kind{pr.KindCheckPending}},
		{"only skips, from suites created in the same second as the ready event",
			[]gh.CheckSuite{suite(1, skip("test")), suite(2, skip("test")), suite(3, skip("test"))}, []pr.Kind{pr.KindCheckPending}},
		{"only skips until a run reports, which passes the check",
			[]gh.CheckSuite{suite(1, skip("test")), suite(2, passed("test"))}, nil},
		{"a ready run a draft push's later run cancelled holds the PR",
			[]gh.CheckSuite{suite(1, run("test", "COMPLETED", "CANCELLED")), suite(2, skip("test"))}, []pr.Kind{pr.KindCheckPending}},
		{"until a re-run of the cancelled run reports, in its own suite",
			[]gh.CheckSuite{suite(1, passed("test")), suite(2, skip("test"))}, nil},
		{"a failed result beside a passed one holds the PR",
			[]gh.CheckSuite{suite(1, passed("test")), suite(2, run("test", "COMPLETED", "FAILURE"))}, []pr.Kind{pr.KindCheckFailed}},
		{"a result a draft's run produced by running counts",
			[]gh.CheckSuite{suite(1, passed("test"))}, nil},
		{"a re-run's result stands over the attempt it re-ran",
			[]gh.CheckSuite{suite(1, passed("test"))}, nil},
		{"a neutral result counts",
			[]gh.CheckSuite{suite(1, run("test", "COMPLETED", "NEUTRAL"))}, nil},
		{"a run still going holds the PR",
			[]gh.CheckSuite{suite(1, run("test", "IN_PROGRESS", ""))}, []pr.Kind{pr.KindCheckPending}},
		{"a check the PR does not require holds nothing",
			[]gh.CheckSuite{suite(1, passed("test"), gh.CheckRun{Name: "lint", Status: "COMPLETED", Conclusion: "FAILURE"})}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w := ready()
			w.pr.Suites[head] = c.suites
			a := w.answer(t)
			if c.want == nil {
				isReady(t, a)
				return
			}
			only(t, a, c.want...)
		})
	}
	t.Run("a passing required commit status is left to the merge state", func(t *testing.T) {
		// A required commit status has no check suite, so the merge state
		// carries it: CLEAN once it passes.
		w := ready()
		w.pr.Suites[head] = []gh.CheckSuite{suite(1, passed("test"))}
		isReady(t, w.answer(t))
	})
}

func TestOpenDraftAndTheRecordsIdentity(t *testing.T) {
	cases := []struct {
		name   string
		change func(*world)
		want   []pr.Kind
	}{
		{"a merged PR", func(w *world) { w.pr.Facts.State = "MERGED" }, []pr.Kind{pr.KindOpen}},
		{"a closed PR", func(w *world) { w.pr.Facts.State = "CLOSED" }, []pr.Kind{pr.KindOpen}},
		{"a draft", func(w *world) { w.pr.Facts.IsDraft = true }, []pr.Kind{pr.KindDraft}},
		{"another base", func(w *world) {
			w.pr.Facts.BaseRefName = "release"
			w.md["review_results"] = `[{"head":"` + head + `","target":"release","passed":true}]`
		}, []pr.Kind{pr.KindRecord}},
		{"another head branch", func(w *world) { w.pr.Facts.HeadRefName = "polecat/tk-2" }, []pr.Kind{pr.KindRecord}},
		{"another URL", func(w *world) { w.pr.Facts.URL = "https://github.com/acme/other/pull/7" }, []pr.Kind{pr.KindRecord}},
		{"the repository in another case", func(w *world) { w.pr.Facts.Repository = "Acme/Widgets" }, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w := ready()
			c.change(w)
			a := w.answer(t)
			if c.want == nil {
				isReady(t, a)
				return
			}
			only(t, a, c.want...)
		})
	}
}

func TestAnIncompleteRecordReadsNoGitHub(t *testing.T) {
	for _, key := range []string{"pr_head_sha", "merged_target", "pr_url", "pr_number", "pr_repo", "branch", "merge_result"} {
		t.Run(key, func(t *testing.T) {
			w := ready()
			delete(w.md, key)
			only(t, w.answer(t), pr.KindRecord)
			if reads := w.github.Reads(); len(reads) > 0 {
				t.Fatalf("read GitHub %v for a record that names no PR whole", reads)
			}
		})
	}
	t.Run("a URL that names another number", func(t *testing.T) {
		w := ready()
		w.md["pr_url"] = "https://github.com/acme/widgets/pull/8"
		only(t, w.answer(t), pr.KindRecord)
	})
	// The landing order reads such a head as a record that no longer names its
	// PR, and the evaluator shares its reading of a whole record.
	t.Run("a validated head that is no full commit id", func(t *testing.T) {
		w := ready()
		w.md["pr_head_sha"] = "abc1234"
		only(t, w.answer(t), pr.KindRecord)
		if reads := w.github.Reads(); len(reads) > 0 {
			t.Fatalf("read GitHub %v for a record whose head is no commit id", reads)
		}
	})
}

func TestTheBeadsOwnWaitsAndHolds(t *testing.T) {
	t.Run("a wait of the bead's own holds the PR", func(t *testing.T) {
		w := ready()
		w.others = []fake.Bead{{ID: "tk-fix", Title: "fix the review's point", Status: "open"}}
		w.edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-fix", Status: "open"}}
		w.store.List(bead, "tk-fix")
		w.store.Mark(bead)
		a := w.answer(t)
		only(t, a, pr.KindWait)
		if a.Conditions[0].ID != "tk-fix" {
			t.Fatalf("the wait names %q, want tk-fix", a.Conditions[0].ID)
		}
	})
	t.Run("a wait that landed holds nothing", func(t *testing.T) {
		w := ready()
		w.others = []fake.Bead{{ID: "tk-fix", Status: "closed", ClosedAt: "2026-11-12T01:00:00Z"}}
		w.edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-fix", Status: "closed"}}
		isReady(t, w.answer(t))
	})
	t.Run("an open bead whose anchor_bead names the bead holds the PR", func(t *testing.T) {
		w := ready()
		w.others = []fake.Bead{{ID: "tk-child", Title: "rework", Status: "open", Metadata: map[string]string{"anchor_bead": bead}}}
		a := w.answer(t)
		only(t, a, pr.KindInFlight)
		if a.Conditions[0].ID != "tk-child" {
			t.Fatalf("the condition names %q, want tk-child", a.Conditions[0].ID)
		}
	})
	t.Run("a closed one holds nothing", func(t *testing.T) {
		w := ready()
		w.others = []fake.Bead{{ID: "tk-child", Status: "closed", Metadata: map[string]string{"anchor_bead": bead}}}
		isReady(t, w.answer(t))
	})
	for _, key := range []string{"merge_hold", "rebase_hold"} {
		t.Run(key, func(t *testing.T) {
			w := ready()
			w.md[key] = "true"
			only(t, w.answer(t), pr.KindHold)
			w = ready()
			w.md[key] = "false"
			isReady(t, w.answer(t))
		})
	}
	t.Run("the blocked status the record writes is no wait", func(t *testing.T) {
		isReady(t, ready().answer(t))
	})
}

func TestFeedbackReceipts(t *testing.T) {
	commented := func(id int64, at string) gh.Review {
		return gh.Review{ID: id, State: "COMMENTED", Author: "operator", AuthorCanPush: true, Body: "rename this", SubmittedAt: at}
	}
	thread := func(id string, comments ...gh.Comment) gh.Thread {
		return gh.Thread{ID: id, Comments: comments}
	}
	comment := func(id int64) gh.Comment {
		return gh.Comment{ID: id, Author: "operator", Body: "and this", CreatedAt: "2026-11-12T02:00:00Z",
			Review: &gh.CommentReview{ID: 200, State: "COMMENTED", SubmittedAt: "2026-11-12T02:00:00Z"}}
	}
	t.Run("a review newer than the review watermark holds the PR", func(t *testing.T) {
		w := ready()
		w.md["pr_review_watermark"] = "150"
		w.pr.Reviews = append(w.pr.Reviews, commented(200, "2026-11-12T02:00:00Z"))
		a := w.answer(t)
		only(t, a, pr.KindFeedback)
		if !strings.Contains(a.Conditions[0].Detail, "review 200") {
			t.Fatalf("detail %q names no review 200", a.Conditions[0].Detail)
		}
	})
	t.Run("one the intake has routed holds nothing", func(t *testing.T) {
		w := ready()
		w.md["pr_review_watermark"] = "200"
		w.pr.Reviews = append(w.pr.Reviews, commented(200, "2026-11-12T02:00:00Z"))
		isReady(t, w.answer(t))
	})
	t.Run("one the threads have answered through holds nothing", func(t *testing.T) {
		w := ready()
		w.md["pr_review_watermark"] = "150"
		w.md["pr_review_answered"] = "200"
		w.pr.Reviews = append(w.pr.Reviews, commented(200, "2026-11-12T02:00:00Z"))
		isReady(t, w.answer(t))
	})
	t.Run("beside feedback the intake's rule leaves out, which holds nothing", func(t *testing.T) {
		w := ready()
		w.md["pr_review_watermark"] = "150"
		w.md["pr_comment_watermark"] = "150"
		w.md["pr_issue_comment_watermark"] = "150"
		approvalMessage := approve(300, "operator", "2026-11-12T03:00:00Z")
		approvalMessage.Body = "ship it, and rename X"
		empty := gh.Review{ID: 301, State: "COMMENTED", Author: "operator", AuthorCanPush: true, Body: " \n", SubmittedAt: "2026-11-12T03:00:00Z"}
		cityOwn := commented(302, "2026-11-12T03:00:00Z")
		w.pr.Reviews = append(w.pr.Reviews, approvalMessage, empty, cityOwn)
		w.pr.Threads = []gh.Thread{thread("T1", comment(303))}
		w.pr.Comments = []gh.IssueComment{{ID: 304, Author: "vercel", Body: "[vc]: #deployed"}}
		w.rule.notFeedback[302] = true
		w.rule.notFeedback[303] = true
		w.rule.notFeedback[304] = true
		isReady(t, w.answer(t))
		// The same posts as feedback hold it in each space but the review
		// space, whose counted reviews are only those that comment or request
		// changes and carry text.
		w = ready()
		w.md["pr_review_watermark"] = "150"
		w.md["pr_comment_watermark"] = "150"
		w.md["pr_issue_comment_watermark"] = "150"
		w.pr.Reviews = append(w.pr.Reviews, approvalMessage, empty, cityOwn)
		w.pr.Threads = []gh.Thread{thread("T1", comment(303))}
		w.pr.Comments = []gh.IssueComment{{ID: 304, Author: "vercel", Body: "[vc]: #deployed"}}
		a := w.answer(t)
		only(t, a, pr.KindFeedback, pr.KindFeedback, pr.KindFeedback)
		if !strings.Contains(a.Conditions[0].Detail, "review 302") {
			t.Fatalf("the review space counts %q, want review 302 alone", a.Conditions[0].Detail)
		}
	})
	t.Run("an inline comment newer than the comment watermark, and past the answered mark", func(t *testing.T) {
		w := ready()
		w.md["pr_comment_watermark"] = "250"
		w.md["pr_comment_answered"] = "260"
		w.pr.Threads = []gh.Thread{{ID: "T1", Resolved: true, Comments: []gh.Comment{comment(260), comment(270)}}}
		a := w.answer(t)
		only(t, a, pr.KindFeedback)
		if !strings.Contains(a.Conditions[0].Detail, "inline comment 270") {
			t.Fatalf("detail %q names no inline comment 270", a.Conditions[0].Detail)
		}
	})
	t.Run("a conversation comment newer than its watermark", func(t *testing.T) {
		w := ready()
		w.md["pr_issue_comment_watermark"] = "not a number"
		w.pr.Comments = []gh.IssueComment{{ID: 5, Author: "operator", Body: "one more thing"}}
		only(t, w.answer(t), pr.KindFeedback)
	})
	t.Run("a review thread waiting on the city's answer holds the PR", func(t *testing.T) {
		w := ready()
		w.md["pr_comment_watermark"] = "999"
		w.pr.Threads = []gh.Thread{thread("T1", comment(303)), thread("T2", comment(304))}
		w.rule.awaits["T2"] = true
		a := w.answer(t)
		only(t, a, pr.KindThread)
		if a.Conditions[0].Value != "T2" {
			t.Fatalf("the thread condition names %q, want T2", a.Conditions[0].Value)
		}
	})
}

func TestAReadThatFailsAnswersNothing(t *testing.T) {
	for _, read := range []string{"PullRequest", "Reviews", "CheckSuites", "ReviewThreads", "IssueComments", "Login"} {
		t.Run(read, func(t *testing.T) {
			w := ready()
			w.github.Fail[read] = errors.New("github: unreachable")
			w.store.Put(fake.Bead{ID: bead, Status: "blocked", Metadata: w.md})
			_, err := pr.Ready(pr.Sources{Ledger: ledger.New(w.store),
				GitHub: func(string) pr.GitHub { return w.github }, Feedback: w.rule}, bead)
			if err == nil {
				t.Fatal("answered on a read that failed")
			}
		})
	}
	t.Run("the definition of feedback", func(t *testing.T) {
		w := ready()
		w.rule.err = errors.New("jq: failed")
		w.store.Put(fake.Bead{ID: bead, Status: "blocked", Metadata: w.md})
		if _, err := pr.Ready(pr.Sources{Ledger: ledger.New(w.store),
			GitHub: func(string) pr.GitHub { return w.github }, Feedback: w.rule}, bead); err == nil {
			t.Fatal("answered on a definition that did not run")
		}
	})
	t.Run("review results that do not decode", func(t *testing.T) {
		w := ready()
		w.md["review_results"] = "{not json"
		w.store.Put(fake.Bead{ID: bead, Status: "blocked", Metadata: w.md})
		if _, err := pr.Ready(pr.Sources{Ledger: ledger.New(w.store),
			GitHub: func(string) pr.GitHub { return w.github }, Feedback: w.rule}, bead); err == nil {
			t.Fatal("answered on review results that did not decode")
		}
	})
	t.Run("a bead the store does not hold", func(t *testing.T) {
		w := ready()
		if _, err := pr.Ready(pr.Sources{Ledger: ledger.New(w.store),
			GitHub: func(string) pr.GitHub { return w.github }, Feedback: w.rule}, bead); err == nil {
			t.Fatal("answered for a bead the store does not hold")
		}
	})
}

func TestOnRecord(t *testing.T) {
	for v, want := range map[string]bool{
		"pull_request_pending": true, "pull_request_head_changed": true,
		"pull_request": false, "pre_open_gate": false, "mr_merged": false, "": false,
	} {
		if got := pr.OnRecord(v); got != want {
			t.Errorf("OnRecord(%q) = %v, want %v", v, got, want)
		}
	}
}
