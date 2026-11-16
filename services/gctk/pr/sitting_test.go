package pr_test

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/review"
)

// A converse sitting's push onto the branch of a PR on the pending record
// (specs/tk-1tfzr71.108/design.md, section 10), on the landing order's world:
// a bead on the record, blocked and assigned to the refinery, whose PR is
// ready, and a conversation in progress under the sitting that the bead waits
// on through the blocks edge a conversation on an open PR writes.

const (
	conv  = "tk-conv"
	alias = "rig/gc-toolkit.tk-conv"
)

// sitter is the names the sitting's session claims under.
var sitter = []string{"tk-conv-session", alias}

// tree is the sitting's checkout as a test sets it: the URLs its origin
// fetches from and pushes to, what it holds that no commit holds, the errors
// its reads and its push return, and each push it was asked for, with whether
// the PR was a draft at that moment. Each call it takes while the store's
// record lock, in the .beads directory lock, is free is listed in free.
type tree struct {
	pr          *ghfake.PR
	lock        string
	fetch, push []string
	originErr   error
	left        string
	leftErr     error
	pushErr     error
	pushed      []string
	asDrafts    []bool
	free        []string
}

func (t *tree) Origin() ([]string, []string, error) {
	t.called("Origin")
	return t.fetch, t.push, t.originErr
}

func (t *tree) Uncommitted() (string, error) {
	t.called("Uncommitted")
	return t.left, t.leftErr
}

func (t *tree) Push(branch string) error {
	t.called("Push")
	t.pushed = append(t.pushed, branch)
	t.asDrafts = append(t.asDrafts, t.pr.Facts.IsDraft)
	return t.pushErr
}

func (t *tree) called(call string) {
	if lockFree(t.lock) {
		t.free = append(t.free, call)
	}
}

// lockFree reports whether nothing holds the record lock of the store whose
// .beads directory is dir.
func lockFree(dir string) bool {
	release, err := record.Lock(dir, 0)
	if err != nil {
		return false
	}
	release()
	return true
}

// hold makes conversation conv in progress under the sitting, and gives the
// bead its blocks edge onto it.
func hold(t *testing.T, d *land) {
	t.Helper()
	d.store.Put(fake.Bead{ID: conv, Title: "Converse about the PR", Status: "in_progress", IssueType: "task", Assignee: alias})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: conv, Status: "in_progress"})
	})
	d.store.List(bead, conv)
}

// newSitting is the world with the sitting's conversation holding the bead,
// and its checkout a clone of the PR's repository.
func newSitting(t *testing.T) (*land, *tree) {
	t.Helper()
	d := newCycle(t)
	hold(t, d)
	return d, &tree{pr: d.pr, lock: d.l.Dir, fetch: []string{origin}, push: []string{origin}}
}

// refusedFor reports whether err is a refusal whose reason says why.
func refusedFor(err error, why string) bool {
	var refused *pr.PushRefusal
	return errors.As(err, &refused) && strings.Contains(refused.Why, why)
}

// A sitting that holds the branch returns the PR to draft and then pushes, so
// the push lands on a draft. A later push of the same round finds the PR a
// draft and converts nothing.
func TestASittingThatHoldsTheBranchReturnsThePRToDraftBeforeItPushes(t *testing.T) {
	d, tr := newSitting(t)
	got, err := d.l.Push(bead, conv, sitter, tr)
	if err != nil || !got.Converted || got.Branch != branch || got.URL != prURL || got.Conversation != conv {
		t.Fatalf("the push read %+v, %v", got, err)
	}
	if !slices.Equal(tr.pushed, []string{branch}) || !slices.Equal(tr.asDrafts, []bool{true}) {
		t.Fatalf("pushed %v with the PR a draft %v, want one push onto %s once it is a draft", tr.pushed, tr.asDrafts, branch)
	}
	again, err := d.l.Push(bead, conv, sitter, tr)
	if err != nil || again.Converted || len(tr.pushed) != 2 {
		t.Fatalf("the round's later push read %+v, %v, after %d pushes", again, err, len(tr.pushed))
	}
	if got := asks(d.github); !slices.Equal(got, []string{"ConvertToDraft PR_7 "}) {
		t.Fatalf("asked %v, want one conversion", got)
	}
}

// The proof names the branch the sitting holds and changes nothing, so a
// sitting can ask before its first edit.
func TestASittingProvesItHoldsTheBranchWithoutChangingIt(t *testing.T) {
	d, tr := newSitting(t)
	got, err := d.l.Held(bead, conv, sitter)
	if err != nil || got != (pr.Holding{Bead: bead, Conversation: conv, Branch: branch, PR: prURL}) {
		t.Fatalf("the proof read %+v, %v", got, err)
	}
	if len(d.github.Asks()) != 0 || len(tr.pushed) != 0 || d.pr.Facts.IsDraft {
		t.Fatalf("the proof changed something: asks %v, pushes %v, draft %v", asks(d.github), tr.pushed, d.pr.Facts.IsDraft)
	}
}

// A sitting writes only a branch it holds: the bead owns a PR on the pending
// record, the conversation is in progress under this session, the bead waits
// on it, no review run is attached, and no other open bead works the branch.
// Each refusal changes nothing.
func TestASittingPushesOnlyABranchItHolds(t *testing.T) {
	for name, c := range map[string]struct {
		change func(t *testing.T, d *land)
		self   []string
		why    string
	}{
		"the old path": {change: func(t *testing.T, d *land) {
			d.edit(t, func(b *fake.Bead) { b.Metadata["merge_result"] = "pull_request" })
		}, why: `no PR open on the pending record (merge_result "pull_request")`},
		"a closed bead": {change: func(t *testing.T, d *land) {
			d.edit(t, func(b *fake.Bead) { b.Status = "closed" })
		}, why: "it is closed"},
		"a record that names no PR": {change: func(t *testing.T, d *land) {
			d.edit(t, func(b *fake.Bead) { delete(b.Metadata, "pr_url") })
		}, why: "its record names no PR"},
		"a record whose URL is no PR's": {change: func(t *testing.T, d *land) {
			d.edit(t, func(b *fake.Bead) { b.Metadata["pr_url"] = "https://github.com/acme/widgets/issues/7" })
		}, why: `"https://github.com/acme/widgets/issues/7" is not a pull request's URL`},
		"no edge onto the conversation": {change: func(t *testing.T, d *land) {
			d.edit(t, func(b *fake.Bead) { b.Edges = nil })
		}, why: "no blocks edge onto conversation " + conv},
		"a conversation in the operator's queue": {change: func(t *testing.T, d *land) {
			d.store.Put(fake.Bead{ID: conv, Title: "Converse about the PR", Status: "open", IssueType: "task", Assignee: "human"})
		}, why: "conversation " + conv + " is open and assigned to human"},
		"another session's sitting": {change: func(*testing.T, *land) {},
			self: []string{"another-session"}, why: "so this session does not hold it"},
		"a closed conversation": {change: func(t *testing.T, d *land) {
			d.store.Put(fake.Bead{ID: conv, Title: "Converse about the PR", Status: "closed", IssueType: "task", Assignee: alias})
		}, why: "is closed and assigned to " + alias},
		"no conversation": {change: func(t *testing.T, d *land) {
			d.store.Put(fake.Bead{ID: conv, Title: "Fix the flag", Status: "in_progress", IssueType: "task", Assignee: "rig/gc-toolkit.polecat-1"})
		}, why: conv + " is no conversation held by a sitting"},
		"an attached review run": {change: func(t *testing.T, d *land) {
			d.store.Put(fake.Bead{ID: "tk-run1", Title: "mol-pr-review", Status: "open",
				Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review"}})
			d.edit(t, func(b *fake.Bead) {
				b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-run1", Status: "open"})
			})
		}, why: "review run tk-run1 is attached to it and works its branch"},
		"another writer on the branch": {change: func(t *testing.T, d *land) {
			d.store.Put(fake.Bead{ID: "tk-kid", Title: "Rework the branch", Status: "in_progress", IssueType: "task",
				Assignee: "rig/gc-toolkit.polecat-1", Metadata: map[string]string{"branch": branch, "task_kind": "rework"}})
		}, why: "tk-kid works its branch " + branch},
	} {
		t.Run(name, func(t *testing.T) {
			d, tr := newSitting(t)
			c.change(t, d)
			self := sitter
			if c.self != nil {
				self = c.self
			}
			if _, err := d.l.Held(bead, conv, self); !refusedFor(err, c.why) {
				t.Fatalf("the proof read %v, want a refusal saying %q", err, c.why)
			}
			if _, err := d.l.Push(bead, conv, self, tr); !refusedFor(err, c.why) {
				t.Fatalf("the push read %v, want a refusal saying %q", err, c.why)
			}
			if len(d.github.Asks()) != 0 || len(tr.pushed) != 0 {
				t.Fatalf("a refusal changed something: asks %v, pushes %v", asks(d.github), tr.pushed)
			}
		})
	}
}

// Every reason the proof fails is named, so one answer tells the sitting all
// it must settle.
func TestTheProofNamesEveryReasonItFails(t *testing.T) {
	d, _ := newSitting(t)
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["merge_result"] = "pull_request"
		b.Edges = nil
	})
	_, err := d.l.Held(bead, conv, sitter)
	if !refusedFor(err, "no PR open on the pending record") || !refusedFor(err, "no blocks edge onto conversation") {
		t.Fatalf("the proof read %v, want both reasons", err)
	}
}

// An ask on the PR is the review run's work once a run takes it, and no
// writer of the branch while it waits, so it leaves the sitting the branch. A
// closed rework child is no writer either.
func TestAnAskOrAClosedChildLeavesTheSittingItsBranch(t *testing.T) {
	d, tr := newSitting(t)
	id, filed, err := review.FileAsk(ledger.New(d.store), review.AskRequest{Bead: bead, Reason: "operator ruling: rename the flag"}, nil)
	if err != nil || !filed {
		t.Fatalf("the ask did not file: %v (filed %v)", err, filed)
	}
	d.store.List(bead, conv, id)
	d.store.Put(fake.Bead{ID: "tk-kid", Title: "Rework the branch", Status: "closed", IssueType: "task",
		Metadata: map[string]string{"branch": branch, "task_kind": "rework"}})
	if _, err := d.l.Push(bead, conv, sitter, tr); err != nil || len(tr.pushed) != 1 {
		t.Fatalf("an ask and a closed child kept the sitting off the branch: %v, pushes %v", err, tr.pushed)
	}
}

// The push goes only to the PR's repository: a checkout whose origin fetches
// from or pushes to any other, or names none, is refused before the PR returns
// to draft. The refusal names each URL by the repository it names, so it
// repeats no credentials. The PR's repository in any of origin's forms, in any
// case, is the PR's.
func TestTheCheckoutMustFetchFromAndPushToThePRsRepository(t *testing.T) {
	const fork = "git@github.com:fork/widgets.git"
	for name, c := range map[string]struct {
		fetch, push []string
		why         string
	}{
		"a fork it fetches from":    {fetch: []string{"https://github.com/fork/widgets.git"}, push: []string{origin}, why: "it fetches from github.com/fork/widgets"},
		"a fork it pushes to":       {fetch: []string{origin}, push: []string{fork}, why: "it pushes to github.com/fork/widgets"},
		"a fork's clone":            {fetch: []string{fork}, push: []string{fork}, why: "it fetches from and pushes to github.com/fork/widgets"},
		"a second push URL":         {fetch: []string{origin}, push: []string{origin, fork}, why: "it pushes to github.com/fork/widgets"},
		"another host":              {fetch: []string{origin}, push: []string{"git@gitlab.com:acme/widgets.git"}, why: "it pushes to gitlab.com/acme/widgets"},
		"a path":                    {fetch: []string{"/srv/git/widgets.git"}, push: []string{"/srv/git/widgets.git"}, why: "it fetches from and pushes to /srv/git/widgets.git, which names no repository on a host"},
		"no push URL":               {fetch: []string{origin}, why: "it pushes to no URL"},
		"no URL":                    {why: "it fetches from no URL; it pushes to no URL"},
		"a credentialed fork's URL": {fetch: []string{origin}, push: []string{"https://x-access-token:s3cret@github.com/fork/widgets.git"}, why: "it pushes to github.com/fork/widgets"},
	} {
		t.Run(name, func(t *testing.T) {
			d, tr := newSitting(t)
			tr.fetch, tr.push = c.fetch, c.push
			_, err := d.l.Push(bead, conv, sitter, tr)
			if !refusedFor(err, "the checkout's origin is not the PR's repository, github.com/acme/widgets: ") || !refusedFor(err, c.why) {
				t.Fatalf("the push read %v, want a refusal saying %q", err, c.why)
			}
			if strings.Contains(err.Error(), "s3cret") {
				t.Fatalf("the refusal repeats the URL's credentials: %v", err)
			}
			if len(d.github.Asks()) != 0 || len(tr.pushed) != 0 || d.pr.Facts.IsDraft {
				t.Fatalf("a checkout of another repository changed something: asks %v, pushes %v, draft %v", asks(d.github), tr.pushed, d.pr.Facts.IsDraft)
			}
		})
	}

	d, tr := newSitting(t)
	tr.fetch = []string{"https://github.com/acme/widgets"}
	tr.push = []string{"ssh://git@github.com/Acme/Widgets.git", "https://x-access-token:s3cret@github.com/acme/widgets.git"}
	if _, err := d.l.Push(bead, conv, sitter, tr); err != nil || len(tr.pushed) != 1 {
		t.Fatalf("the PR's repository in other forms read %v, pushes %v", err, tr.pushed)
	}

	e, et := newSitting(t)
	et.originErr = errors.New("git remote: error: No such remote 'origin'")
	_, err := e.l.Push(bead, conv, sitter, et)
	var refused *pr.PushRefusal
	if err == nil || errors.As(err, &refused) || len(e.github.Asks()) != 0 || len(et.pushed) != 0 {
		t.Fatalf("an origin that did not read read as %v, asks %v, pushes %v", err, asks(e.github), et.pushed)
	}
}

// The proof reads under the record lock, so while another writer holds it the
// proof and the push wait, and one that waited as long as it would changes
// nothing and reads no checkout.
func TestTheProofWaitsForTheRecordLock(t *testing.T) {
	d, tr := newSitting(t)
	release, err := record.Lock(d.l.Dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	d.l.Wait = 50 * time.Millisecond
	if _, err := d.l.Held(bead, conv, sitter); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("the proof under a held lock read %v, want the lock's wait error", err)
	}
	if _, err := d.l.Push(bead, conv, sitter, tr); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("the push under a held lock read %v, want the lock's wait error", err)
	}
	if len(d.github.Asks()) != 0 || len(tr.pushed) != 0 || len(tr.free) != 0 {
		t.Fatalf("a push that did not get the lock went on: asks %v, pushes %v, calls %v", asks(d.github), tr.pushed, tr.free)
	}
}

// A run of the landing order that read the bead before the conversation held
// it pours its review run under the record lock, so the proof made while that
// run holds the lock waits for it, sees the run attached, and refuses.
func TestARunPouredFromAReadBeforeTheHoldIsSeenByTheProof(t *testing.T) {
	d := newAdmit(t)
	there, goOn := pause(d.github)
	ran := make(chan error, 1)
	go func() { ran <- d.l.Reconcile(pr.Options{Count: 10}, func(pr.RunOutcome) {}) }()
	<-there
	hold(t, d.land)
	proved := make(chan error, 1)
	go func() {
		_, err := d.l.Held(bead, conv, sitter)
		proved <- err
	}()
	waits(t, proved, "the proof")
	close(goOn)
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if err := <-proved; !refusedFor(err, "review run tk-run1 is attached to it") {
		t.Fatalf("the proof after the run poured read %v, want a refusal naming the run", err)
	}
	if n := d.runs.count(); n != 1 {
		t.Fatalf("the order poured %d review runs, want the one", n)
	}
}

// The push holds the record lock from its proof to its end: the checkout's
// reads, the draft's read of the PR and the push all run under it, and the
// lock is free once the push returns. So no run of the landing order, whose
// ready transition reads no conversation's hold, marks the PR ready between
// its return to draft and the push.
func TestThePushHoldsTheRecordLockToItsEnd(t *testing.T) {
	d, tr := newSitting(t)
	var free []string
	d.github.OnRead = func(method string, _ *ghfake.PR) {
		if lockFree(d.l.Dir) {
			free = append(free, method)
		}
	}
	if _, err := d.l.Push(bead, conv, sitter, tr); err != nil {
		t.Fatal(err)
	}
	if len(free) != 0 || len(tr.free) != 0 || len(tr.pushed) != 1 {
		t.Fatalf("calls made with the lock free: GitHub %v, checkout %v; pushes %v", free, tr.free, tr.pushed)
	}
	if !lockFree(d.l.Dir) {
		t.Fatal("the push kept the record lock after it returned")
	}
}

// Work the checkout holds that no commit holds would be left behind by the
// push, so it is refused before the PR returns to draft.
func TestWorkNoCommitHoldsIsRefusedBeforeThePRReturnsToDraft(t *testing.T) {
	d, tr := newSitting(t)
	tr.left = " M skills/converse-edit/SKILL.md\n?? notes.txt\n"
	if _, err := d.l.Push(bead, conv, sitter, tr); !refusedFor(err, "M skills/converse-edit/SKILL.md; ?? notes.txt") {
		t.Fatalf("uncommitted work read as %v", err)
	}
	if len(d.github.Asks()) != 0 || len(tr.pushed) != 0 {
		t.Fatalf("uncommitted work changed something: asks %v, pushes %v", asks(d.github), tr.pushed)
	}
	e, et := newSitting(t)
	et.leftErr = errors.New("git status: not a git repository")
	if _, err := e.l.Push(bead, conv, sitter, et); err == nil || len(e.github.Asks()) != 0 || len(et.pushed) != 0 {
		t.Fatalf("an unread checkout read as %v, asks %v, pushes %v", err, asks(e.github), et.pushed)
	}
}

// A return to draft that did not land pushes nothing, and the retry converts
// and pushes.
func TestADraftThatDidNotLandPushesNothing(t *testing.T) {
	d, tr := newSitting(t)
	d.github.Fail["ConvertToDraft"] = errors.New("gh: error connecting to api.github.com")
	if _, err := d.l.Push(bead, conv, sitter, tr); err == nil || len(tr.pushed) != 0 {
		t.Fatalf("an unanswered draft read as %v, pushes %v", err, tr.pushed)
	}
	delete(d.github.Fail, "ConvertToDraft")
	if got, err := d.l.Push(bead, conv, sitter, tr); err != nil || !got.Converted || len(tr.pushed) != 1 {
		t.Fatalf("the retry read %+v, %v, pushes %v", got, err, tr.pushed)
	}
}

// A branch that holds a commit the checkout does not takes nothing, and the PR
// stays a draft for the push that follows once the checkout holds it. A push
// that failed otherwise is an error that is neither.
func TestABranchThatMovedTakesNothingAndLeavesThePRADraft(t *testing.T) {
	d, tr := newSitting(t)
	tr.pushErr = &pr.Moved{Branch: branch, Why: "a commit landed on the branch after the read"}
	_, err := d.l.Push(bead, conv, sitter, tr)
	var moved *pr.Moved
	if !errors.As(err, &moved) || !d.pr.Facts.IsDraft {
		t.Fatalf("a moved branch read as %v, the PR a draft %v", err, d.pr.Facts.IsDraft)
	}
	e, et := newSitting(t)
	et.pushErr = errors.New("remote: Permission to acme/widgets.git denied")
	_, err = e.l.Push(bead, conv, sitter, et)
	var refused *pr.PushRefusal
	if err == nil || errors.As(err, &moved) || errors.As(err, &refused) || !strings.Contains(err.Error(), "did not land") {
		t.Fatalf("a failed push read as %v", err)
	}
}
