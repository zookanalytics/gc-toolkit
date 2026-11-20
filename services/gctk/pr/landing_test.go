package pr_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"math/rand/v2"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	ghfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The landing order's cases follow Gas Town's pr-merge-reconcile tests at
// gascity-packs 7f86098c04ea (gastown/tests/test_pr_merge_reconcile.sh), each
// named for the case it ports, and add the pack's: the merge request, the merge
// queue, the order of the record's writers under the store's record lock, and
// the run that acts from the beads (specs/tk-1tfzr71.149/design.md, section 5).
// Gas Town's cases about its artifact cleanup after the close, its REST lookup
// without gh, its witness's wake of the refinery and its formula's wiring have
// no counterpart: the pack runs no artifact cleanup, reads GitHub through gh,
// runs the order with no agent, and the refinery's formula is unit 4's.
//
// A run decides from the read the one-PR update saved on the bead, so a case
// that changes GitHub has the PR watch save it first (once), as its next pass
// would, and asserts on what the run itself read and wrote.

const (
	refinery = "rig/refinery"
	merged   = "e111111111111111111111111111111111111111"
	origin   = "git@github.com:acme/widgets.git"
)

// checkout is the rig's clone as a test sets it: its origin, a fetch that fails
// when fetchErr is set, runs onFetch first when it is set, or blocks until its
// context ends when fetchBlocks is set, the branches each fetch named, and the
// commits on the target once a fetch has run. Its
// default branch is def, main when that is empty, and a branch's tip once a
// fetch has run is tip, else, for the PR's branch, the head GitHub holds for the
// PR, prHead, as a remote's branch is its PR's head, and the merge commit
// otherwise. defErr and tipErr fail their reads.
// descends names, for each commit, the commits it descends from, which
// Contains reads, and containsErr fails it.
type checkout struct {
	mu          sync.Mutex
	origin      string
	fetchErr    error
	onFetch     func()
	fetchBlocks bool
	fetched     bool
	branches    []string
	reachable   map[string]bool
	def, tip    string
	prHead      func() string
	defErr      error
	tipErr      error
	descends    map[string][]string
	containsErr error
}

func (c *checkout) OriginURL() (string, error) { return c.origin, nil }

func (c *checkout) DefaultBranch() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.defErr != nil {
		return "", c.defErr
	}
	if c.def == "" {
		return "main", nil
	}
	return c.def, nil
}

func (c *checkout) Tip(name string) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	switch {
	case c.tipErr != nil:
		return "", c.tipErr
	case !c.fetched:
		return "", errors.New("origin/" + name + " was never fetched")
	case c.tip != "":
		return c.tip, nil
	case name == branch && c.prHead != nil:
		return c.prHead(), nil
	}
	return merged, nil
}

func (c *checkout) FetchBranch(ctx context.Context, branch string) error {
	c.mu.Lock()
	on, blocks, err := c.onFetch, c.fetchBlocks, c.fetchErr
	c.branches = append(c.branches, branch)
	c.mu.Unlock()
	if blocks {
		<-ctx.Done()
		return fmt.Errorf("git fetch: origin/main was stopped: %w", ctx.Err())
	}
	if on != nil {
		on()
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if err != nil {
		return err
	}
	c.fetched = true
	return nil
}

func (c *checkout) Reaches(commit, _ string) (bool, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.fetched && c.reachable[commit], nil
}

func (c *checkout) Contains(commit, ancestor string) (bool, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.containsErr != nil {
		return false, c.containsErr
	}
	return commit == ancestor || slices.Contains(c.descends[commit], ancestor), nil
}

// clock is the run's clock as a test moves it: it stands still until the test
// moves it on.
type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.t
}

func (c *clock) advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.t = c.t.Add(d)
}

// timed gives the run a clock the test moves, which a run's window reads.
func (d *land) timed() *clock {
	c := &clock{t: time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC)}
	d.l.Now = c.now
	return c
}

// gates records each gate filed, fails a filing when err is set, and while
// stall is set answers no filing until the act's context ends.
type gates struct {
	mu       sync.Mutex
	filed    []string
	messages []string
	err      error
	stall    bool
}

func (g *gates) File(ctx context.Context, subject, key, message string) error {
	g.mu.Lock()
	stall := g.stall
	g.mu.Unlock()
	if stall {
		<-ctx.Done()
		return fmt.Errorf("human-gate.sh was stopped: %w", ctx.Err())
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.err != nil {
		return g.err
	}
	g.filed = append(g.filed, subject+" "+key)
	g.messages = append(g.messages, message)
	return nil
}

func (g *gates) list() []string {
	g.mu.Lock()
	defer g.mu.Unlock()
	return slices.Clone(g.filed)
}

// audit is the seed audit as a test sets it: the pages stale at each commit, a
// check that fails while failChecks counts down, and a writer that refuses while
// failReaudits does. It records each commit checked, and each hand-off as its
// branch and pages, with who found them.
type audit struct {
	mu           sync.Mutex
	stale        map[string][]string
	failChecks   int
	failReaudits int
	checks       []string
	reaudits     []string
	seenBy       []string
}

func (a *audit) Stale(commit string) ([]string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.checks = append(a.checks, commit)
	if a.failChecks > 0 {
		a.failChecks--
		return nil, errors.New("render-seed-audit.sh: exit 2: gc is not on PATH")
	}
	return a.stale[commit], nil
}

func (a *audit) Reaudit(branch, seenBy string, pages []string) (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.reaudits = append(a.reaudits, branch+" "+strings.Join(pages, ","))
	a.seenBy = append(a.seenBy, seenBy)
	if a.failReaudits > 0 {
		a.failReaudits--
		return "", errors.New("seed-audit-reaudit.sh: exit 2: the dedup query failed")
	}
	return "re-1 gc-toolkit/gc-toolkit.polecat filed", nil
}

// calls is what the audit was asked: each commit checked, and each hand-off.
func (a *audit) calls() (checks, reaudits []string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	return slices.Clone(a.checks), slices.Clone(a.reaudits)
}

// land is one bead on the pending record, blocked and assigned to nobody,
// whose PR the evaluator reads ready, with the landing order's sources and the
// PR watch's one-PR update, which saves GitHub's side on the bead. reads and
// writes mark where the last run's GitHub reads and store writes start.
type land struct {
	*world
	co     *checkout
	gates  *gates
	l      pr.Landing
	watch  pr.Watcher
	clock  time.Time
	tick   int
	reads  int
	writes int
}

func newLand(t *testing.T) *land {
	t.Helper()
	w := ready()
	w.pr.Facts.ID = "PR_7"
	for k, v := range map[string]string{
		"pr_reconcile_pending": "true", "pr_state": "open", "pr_last_checked_at": "2026-11-12T01:00:00Z",
		"blocked_reason": "Awaiting verified merge of " + prURL,
	} {
		w.md[k] = v
	}
	co := &checkout{origin: origin, reachable: map[string]bool{merged: true}, descends: map[string][]string{},
		prHead: func() string { return w.pr.Facts.HeadRefOid }}
	g := &gates{}
	d := &land{world: w, co: co, gates: g, clock: time.Date(2026, 11, 12, 8, 0, 0, 0, time.UTC)}
	dir := t.TempDir()
	d.l = pr.Landing{
		Ledger:   ledger.New(w.store),
		Dir:      dir,
		Refinery: refinery,
		Hub:      func(context.Context, string) pr.Hub { return w.github },
		Feedback: func() (pr.Feedback, error) { return w.rule, nil },
		Checkout: co,
		Gates:    g,
		Now:      func() time.Time { return time.Date(2026, 11, 12, 9, 0, 0, 0, time.UTC) },
		Wait:     5 * time.Second,
		Shuffle:  func([]string) {},
	}
	d.watch = pr.Watcher{
		Ledger:   ledger.New(w.store),
		Dir:      dir,
		GitHub:   func(string) pr.Watch { return w.github },
		Feedback: func() (pr.Feedback, error) { return w.rule, nil },
		Now: func() time.Time {
			d.clock = d.clock.Add(time.Second)
			return d.clock
		},
		Wait: 5 * time.Second,
	}
	d.put("blocked", "")
	return d
}

// put writes the bead's row with its record as the world holds it.
func (d *land) put(status, assignee string) {
	d.store.Put(fake.Bead{ID: bead, Title: "the work", Status: status, Assignee: assignee, Metadata: d.md, Edges: d.edges})
}

// row is the bead's row as the store holds it.
func (d *land) row(t *testing.T) fake.Bead {
	t.Helper()
	r, ok := d.store.Row(bead)
	if !ok {
		t.Fatal("the store lost the bead")
	}
	return r
}

// refresh is the PR watch's next pass over the bead's PR: GitHub's change time
// moves, so the one-PR update reads the PR and its conversation, and saves on
// the bead what differs.
func (d *land) refresh(t *testing.T) {
	t.Helper()
	d.tick++
	d.pr.UpdatedAt = fmt.Sprintf("2026-11-12T07:%02d:%02dZ", d.tick/60%60, d.tick%60)
	if _, err := d.watch.Refresh(prURL); err != nil {
		t.Fatalf("the PR watch's update: %v", err)
	}
}

// reconcile runs the landing order once and returns each outcome. A run that
// reports an act that did not complete returns an error, and one that reports
// none returns none.
func (d *land) reconcile(t *testing.T, o pr.Options) []pr.RunOutcome {
	t.Helper()
	d.reads, d.writes = len(d.github.Reads()), len(d.store.Writes())
	var out []pr.RunOutcome
	var mu sync.Mutex
	err := d.l.Reconcile(o, func(x pr.RunOutcome) { mu.Lock(); out = append(out, x); mu.Unlock() })
	owed := slices.ContainsFunc(out, func(x pr.RunOutcome) bool { return x.Action == pr.ActRetry || x.Action == pr.ActFailed })
	if (err != nil) != owed {
		t.Fatalf("Reconcile returned %v over the outcomes %+v", err, out)
	}
	return out
}

// run runs the landing order over the bead as the store holds it, and returns
// its one outcome.
func (d *land) run(t *testing.T) pr.RunOutcome {
	t.Helper()
	out := d.reconcile(t, pr.Options{})
	if len(out) != 1 {
		t.Fatalf("one record, %d outcomes: %+v", len(out), out)
	}
	return out[0]
}

// once is the PR watch's pass over the bead's PR, then a run of the landing
// order, and returns the run's one outcome.
func (d *land) once(t *testing.T) pr.RunOutcome {
	t.Helper()
	d.refresh(t)
	return d.run(t)
}

// runReads is each GitHub read the last run made.
func (d *land) runReads() []string { return d.github.Reads()[d.reads:] }

// runWrites is each store write the last run made.
func (d *land) runWrites() []fake.Write { return d.store.Writes()[d.writes:] }

// readsNoGitHub fails if the last run read GitHub.
func readsNoGitHub(t *testing.T, d *land) {
	t.Helper()
	if reads := d.runReads(); len(reads) != 0 {
		t.Fatalf("the run read GitHub to decide: %v", reads)
	}
}

func is(t *testing.T, o pr.RunOutcome, action string) {
	t.Helper()
	if o.Action != action {
		t.Fatalf("outcome %s (%s), want %s", o.Action, o.Detail, action)
	}
}

func meta(t *testing.T, b fake.Bead, want map[string]string) {
	t.Helper()
	for k, v := range want {
		got, held := b.Metadata[k]
		switch {
		case v == "<absent>" && held:
			t.Errorf("%s = %q, want it absent", k, got)
		case v != "<absent>" && got != v:
			t.Errorf("%s = %q, want %q", k, got, v)
		}
	}
}

func asks(g *ghfake.GitHub) []string {
	var out []string
	for _, a := range g.Asks() {
		out = append(out, a.Method+" "+a.ID+" "+a.Head)
	}
	return out
}

// publication is the PR the refinery publishes for the bead at h.
func publication(h string) record.Publication {
	return record.Publication{URL: prURL, Repo: repo, Number: 7, Head: h, Target: "main"}
}

// also puts another bead on the pending record of the same PR, a copy of the
// bead as the store holds it, the read the watch saved on it included.
func (d *land) also(t *testing.T, id, status string) {
	t.Helper()
	b := d.row(t)
	d.store.Put(fake.Bead{ID: id, Title: "more work", Status: status, Metadata: maps.Clone(b.Metadata)})
}

// --- Gas Town's cases -------------------------------------------------------

func TestRecordBlocksWithoutClosing(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch, "merged_sha": "old", "pr_merged_at": "old", "observed_pr_head_sha": other,
		"rejection_reason": "an earlier round"}
	d.put("open", refinery)
	if err := d.l.Record(bead, publication(head)); err != nil {
		t.Fatal(err)
	}
	ws := d.store.Writes()
	if len(ws) != 2 {
		t.Fatalf("a publication is two writes, got %d: %+v", len(ws), ws)
	}
	arm, whole := strings.Join(ws[0].Args, " "), strings.Join(ws[1].Args, " ")
	for _, want := range []string{"--if-status=open", "--if-assignee=" + refinery, "pr_reconcile_pending=true", "existing_pr=" + prURL} {
		if !strings.Contains(arm, want) {
			t.Errorf("the first write %q lacks %q", arm, want)
		}
	}
	if strings.Contains(arm, "--status=") {
		t.Errorf("the first write moves the bead: %q", arm)
	}
	for _, want := range []string{"--if-status=open", "--if-assignee=" + refinery, "--status=blocked", "--assignee=",
		"pr_reconcile_pending=true", "merge_result=pull_request_pending", "pr_head_sha=" + head} {
		if !strings.Contains(whole, want) {
			t.Errorf("the record's write %q lacks %q", whole, want)
		}
	}
	b := d.row(t)
	if b.Status != "blocked" || b.Assignee != "" {
		t.Fatalf("recorded bead is %s under %q, want blocked and assigned to nobody", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.Pending, "pr_url": prURL, "pr_number": "7", "pr_repo": repo,
		"pr_head_sha": head, "pr_state": "<absent>", "merged_target": "main", "pr_last_checked_at": "<absent>",
		"blocked_reason": "Awaiting verified merge of " + prURL, "pr_reconcile_pending": "true",
		"merged_sha": "<absent>", "pr_merged_at": "<absent>", "observed_pr_head_sha": "<absent>",
		"existing_pr": "<absent>", "rejection_reason": "<absent>"})
}

func TestRecordRefusesAPROutsideTheRigsOriginBeforeAnyWrite(t *testing.T) {
	d := newLand(t)
	d.co.origin = "https://github.com/example/other.git"
	err := d.l.Record(bead, publication(head))
	var origin *pr.OriginError
	if !errors.As(err, &origin) {
		t.Fatalf("a PR outside the rig's origin read as %v", err)
	}
	if len(d.store.Writes()) != 0 {
		t.Fatalf("the refusal wrote %+v", d.store.Writes())
	}
}

func TestAPartialRecordNeverBlocksWithoutTheWholeRecord(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 2 {
			return errors.New("the store did not answer")
		}
		return nil
	}
	err := d.l.Record(bead, publication(head))
	if err == nil || !strings.Contains(err.Error(), "the marker landed and the record did not") {
		t.Fatalf("a failed second write read as %v", err)
	}
	b := d.row(t)
	if b.Status != "open" {
		t.Fatalf("a failed record left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"pr_reconcile_pending": "true", "existing_pr": prURL, "merge_result": "<absent>"})
}

func TestOpenUnchangedPRStaysBlocked(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	is(t, d.once(t), pr.ActChecked)
	b := d.row(t)
	if b.Status != "blocked" || b.Assignee != "" {
		t.Fatalf("an unchanged open PR left the bead %s under %q", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"pr_state": "open", "pr_reconcile_pending": "true"})
	readsNoGitHub(t, d)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a record that owes no act was written: %+v", ws)
	}
	if len(d.github.Asks()) != 0 {
		t.Fatalf("a PR the evaluator holds was asked to merge: %v", asks(d.github))
	}
}

// A PR outside the clone's origin owes no act the run can make: it reads no
// GitHub, writes nothing, and the run's exit says the record could not be
// decided.
func TestAnOriginMismatchActsOnNothingAndWritesNothing(t *testing.T) {
	d := newLand(t)
	d.co.origin = "git@github.com:example/other.git"
	o := d.once(t)
	is(t, o, pr.ActRetry)
	readsNoGitHub(t, d)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("an origin mismatch wrote %+v", ws)
	}
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("an origin mismatch left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"pr_reconcile_pending": "true", "pr_reconcile_error": "<absent>"})
}

// A writer that died between the publication's two writes left an open bead
// with only the marker and the PR to reuse. The run sends it back to the
// refinery as half written and requests no merge. The write that sends it back
// assigns it to the refinery, so a half-written record nobody is assigned goes
// to the refinery too.
func TestAMarkerOnlyOpenRecordGoesBackForRevalidation(t *testing.T) {
	for name, assignee := range map[string]string{"the refinery's": refinery, "nobody's": ""} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			d.md = map[string]string{"branch": branch, "pr_reconcile_pending": "true", "existing_pr": prURL,
				"pr_url": prURL, "pr_head_sha": head}
			d.put("open", assignee)
			is(t, d.once(t), pr.ActRevalidate)
			b := d.row(t)
			if b.Status != "open" || b.Assignee != refinery {
				t.Fatalf("a half-written record left the bead %s under %q", b.Status, b.Assignee)
			}
			meta(t, b, map[string]string{"merge_result": record.Incomplete, "existing_pr": prURL, "pr_url": "<absent>",
				"pr_head_sha": "<absent>", "pr_reconcile_pending": "<absent>", "pr_state": "<absent>"})
			if b.Metadata["rejection_reason"] == "" {
				t.Fatal("the bead goes back with no reason")
			}
			readsNoGitHub(t, d)
			if len(d.github.Asks()) != 0 {
				t.Fatalf("a half-written record asked %v", asks(d.github))
			}
		})
	}
}

func TestACompleteOpenPendingRecordFinishesItsBlockFirst(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	d.put("open", refinery)
	is(t, d.once(t), pr.ActChecked)
	ws := d.runWrites()
	if len(ws) != 1 || !slices.Contains(ws[0].Args, "--status=blocked") || !slices.Contains(ws[0].Args, "--assignee=") {
		t.Fatalf("the run's writes are not the block alone: %+v", ws)
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
	if b := d.row(t); b.Status != "blocked" || b.Assignee != "" {
		t.Fatalf("the bead is %s under %q, want blocked and assigned to nobody", b.Status, b.Assignee)
	}
}

func TestAChangedHeadOpenMarkerIsSettled(t *testing.T) {
	d := newLand(t)
	d.md["merge_result"] = record.HeadChanged
	d.md["observed_pr_head_sha"] = other
	d.put("open", "")
	is(t, d.once(t), pr.ActSettled)
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
	if b := d.row(t); b.Status != "open" || b.Assignee != refinery {
		t.Fatalf("the settle left the bead %s under %q", b.Status, b.Assignee)
	}
	readsNoGitHub(t, d)
}

func TestAnInvalidBlockedRecordIsAnExceptionBeforeTheSavedReadIsRead(t *testing.T) {
	for _, result := range []string{"", "pull_request", "merged", record.Invalid, record.Merged} {
		t.Run(result, func(t *testing.T) {
			d := newLand(t)
			if result == "" {
				delete(d.md, "merge_result")
			} else {
				d.md["merge_result"] = result
			}
			d.put("blocked", "")
			is(t, d.run(t), pr.ActExcepted)
			b := d.row(t)
			meta(t, b, map[string]string{"merge_result": record.Invalid, "pr_reconcile_pending": "<absent>"})
			if b.Status != "blocked" {
				t.Fatalf("an invalid record left the bead %s", b.Status)
			}
			readsNoGitHub(t, d)
			if g := d.gates.list(); !slices.Equal(g, []string{bead + " " + record.Invalid}) {
				t.Fatalf("gates filed %v", g)
			}
		})
	}
}

func TestAnOpenChangedHeadIsRequeuedForValidation(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	is(t, d.once(t), pr.ActRequeued)
	if ws := d.runWrites(); len(ws) != 1 || !slices.Contains(ws[0].Args, "--assignee="+refinery) {
		t.Fatalf("the requeue wrote %+v, want one write that hands the head to the refinery", ws)
	}
	b := d.row(t)
	if b.Status != "open" || b.Assignee != refinery {
		t.Fatalf("a changed head left the bead %s under %s", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other, "pr_head_sha": head,
		"existing_pr": prURL, "pr_reconcile_pending": "<absent>", "blocked_reason": "<absent>"})
	if !strings.Contains(b.Metadata["rejection_reason"], other) {
		t.Fatalf("the requeue's reason %q does not name the head found", b.Metadata["rejection_reason"])
	}
	readsNoGitHub(t, d)
}

// The refinery pushes a head and then records it, so a read the watch saved
// before the push finds the PR at a head the validated one descends from. The
// act fetches the PR's branch and finds the validated head on it, so the read
// is older than the record: nothing is sent back on it, and once the watch
// reads the PR again, the record stands at its head.
func TestASavedReadOlderThanTheValidatedHeadSendsNothingBack(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	d.co.descends[other] = []string{head}
	d.co.tip = other
	d.pr.Facts.HeadRefOid = other
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_head_sha"] = other })
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "read before the refinery recorded its head") {
		t.Fatalf("the stale read's outcome says %q", o.Detail)
	}
	if !slices.Equal(d.co.branches, []string{branch}) {
		t.Fatalf("the act fetched %v, want the PR's branch %s", d.co.branches, branch)
	}
	readsNoGitHub(t, d)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a read older than the record sent the head back: %+v", ws)
	}
	o = d.once(t)
	if o.Action == pr.ActRequeued || d.row(t).Metadata["merge_result"] != record.Pending {
		t.Fatalf("once the watch read the PR at the validated head, the run did %+v", o)
	}
}

// A person rewrites the PR's branch off the head the watch last read, and the
// refinery's preparation fetches the rewritten head, validates it and records
// it before the watch reads the PR again. The saved head is on no line of the
// validated head's history, so only the branch tells the two apart: its tip is
// the validated head, so nothing is sent back on the read, and once the watch
// reads the PR again, the record stands at its head.
func TestAValidatedRewrittenHeadIsNotSentBackOnTheReadFromBeforeIt(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	d.edit(t, func(b *fake.Bead) { b.Status, b.Assignee = "open", refinery })
	d.pr.Facts.HeadRefOid = rewrite
	if err := d.l.Record(bead, record.Publication{URL: prURL, Number: 7, Repo: "acme/widgets", Head: rewrite,
		Target: "main"}); err != nil {
		t.Fatal(err)
	}
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "read before the refinery recorded its head") {
		t.Fatalf("the read from before the rewrite's outcome says %q", o.Detail)
	}
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a read from before the validated rewrite sent the head back: %+v", ws)
	}
	o = d.once(t)
	if o.Action == pr.ActRequeued || d.row(t).Metadata["merge_result"] != record.Pending {
		t.Fatalf("once the watch read the PR at the validated head, the run did %+v", o)
	}
}

// A branch that moved since the watch's read to a tip off the validated head
// goes back to the refinery at that tip, the head the branch holds, and not at
// the older head the read saved.
func TestABranchMovedOffTheValidatedHeadSinceTheReadIsRequeuedAtItsTip(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	d.co.descends[other] = []string{head}
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_head_sha"] = other })
	d.pr.Facts.HeadRefOid = rewrite
	o := d.run(t)
	is(t, o, pr.ActRequeued)
	if !strings.Contains(o.Detail, "origin/"+branch+" is at "+rewrite) {
		t.Fatalf("the requeue's outcome %q does not name the branch's tip", o.Detail)
	}
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": rewrite,
		"pr_head_sha": other})
}

// A push onto the PR's branch after the refinery validated its head, which the
// watch has read, goes back to the refinery at the pushed head, though that
// head contains the validated one.
func TestAPushOntoTheValidatedHeadIsRequeuedAtThePushedHead(t *testing.T) {
	d := newLand(t)
	d.co.descends[later] = []string{head}
	d.pr.Facts.HeadRefOid = later
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": later,
		"pr_head_sha": head})
}

// A person resets the PR's branch to a head the validated one descends from,
// and the watch saves its read there. The act fetches the branch and finds a
// tip that does not contain the validated head, so the bead goes back to the
// refinery as on any other head.
func TestABranchResetToAnAncestorOfTheValidatedHeadIsRequeued(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	d.co.descends[other] = []string{head}
	d.co.tip = head
	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_head_sha"] = other })
	o := d.run(t)
	is(t, o, pr.ActRequeued)
	if !strings.Contains(o.Detail, "origin/"+branch+" is at "+head) {
		t.Fatalf("the requeue's outcome %q does not name the branch's tip", o.Detail)
	}
	b := d.row(t)
	if b.Status != "open" || b.Assignee != refinery {
		t.Fatalf("a reset branch left the bead %s under %s", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": head, "pr_head_sha": other,
		"existing_pr": prURL, "pr_reconcile_pending": "<absent>", "blocked_reason": "<absent>"})
	if !strings.Contains(b.Metadata["rejection_reason"], head) {
		t.Fatalf("the requeue's reason %q does not name the head found", b.Metadata["rejection_reason"])
	}
	readsNoGitHub(t, d)
}

// While the saved read is at another head than the validated one, a fetch of
// the PR's branch that fails sends nothing back, and neither does a read of its
// tip, or of whether a tip the saved read does not show contains the validated
// head, that fails. The next run decides again.
func TestAFailedReadOfTheBranchSendsNothingBack(t *testing.T) {
	for name, fail := range map[string]func(*checkout){
		"fetch": func(c *checkout) { c.fetchErr = errors.New("git fetch: the remote hung up") },
		"tip":   func(c *checkout) { c.tipErr = errors.New("origin/" + branch + " names no commit in the clone") },
		"contains": func(c *checkout) {
			c.onFetch = func() {
				c.mu.Lock()
				defer c.mu.Unlock()
				c.containsErr = errors.New("git merge-base: fatal: bad object")
			}
		},
	} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			d.refresh(t)
			d.co.descends[other] = []string{head}
			d.co.tip = rewrite
			fail(d.co)
			d.edit(t, func(b *fake.Bead) { b.Metadata["pr_head_sha"] = other })
			o := d.run(t)
			is(t, o, pr.ActRetry)
			if !strings.Contains(o.Detail, "nothing is sent back") {
				t.Fatalf("the failed read's outcome says %q", o.Detail)
			}
			if ws := d.runWrites(); len(ws) != 0 {
				t.Fatalf("a failed read of the branch wrote %+v", ws)
			}
			d.co.fetchErr, d.co.tipErr, d.co.containsErr, d.co.onFetch = nil, nil, nil, nil
			is(t, d.run(t), pr.ActRequeued)
		})
	}
}

func TestAClosedUnmergedPRStaysBlockedBehindAGate(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	meta(t, b, map[string]string{"merge_result": record.ClosedUnmerged, "pr_state": "closed", "pr_reconcile_pending": "<absent>"})
	if b.Status != "blocked" || !slices.Equal(d.gates.list(), []string{bead + " " + record.ClosedUnmerged}) {
		t.Fatalf("a closed PR left the bead %s with gates %v", b.Status, d.gates.list())
	}
	if got := d.runReads(); !slices.Equal(got, []string{"PullRequest"}) {
		t.Fatalf("the exception was recorded on the reads %v, want the act's own read of the PR", got)
	}
}

// An exception the saved read decides holds the work behind a person, so the
// act records it only once its own read of the PR finds the PR as the saved
// read did. A PR the watch read closed that a person reopened, whose work the
// refinery published again before the watch read it, gets no exception and no
// gate and keeps its marker, and once the watch reads it the record stands
// pending.
func TestARepublishedPRIsNotExceptedOnAClosedReadFromBeforeIt(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	d.refresh(t)
	d.edit(t, func(b *fake.Bead) { b.Status, b.Assignee = "open", refinery })
	d.pr.Facts.State = "OPEN"
	if err := d.l.Record(bead, publication(head)); err != nil {
		t.Fatal(err)
	}
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "the act's own read of the PR finds it open") {
		t.Fatalf("the run says %q", o.Detail)
	}
	if ws, g := d.runWrites(), d.gates.list(); len(ws) != 0 || len(g) != 0 {
		t.Fatalf("the run wrote %+v and filed %v", ws, g)
	}
	meta(t, d.row(t), map[string]string{"merge_result": record.Pending, "pr_reconcile_pending": "true"})
	is(t, d.once(t), pr.ActRequested)
}

// A PR the saved read finds on another base than the record's target, which
// the act's own read finds on the record's target, as after a base the
// refinery's publication followed and the watch has not read since, is no
// exception: nothing is recorded and no gate is filed.
func TestAPRTheSavedReadFindsRetargetedIsExceptedOnlyOnTheActsOwnRead(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.BaseRefName = "release"
	d.refresh(t)
	d.pr.Facts.BaseRefName = "main"
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "finds the PR the record names") {
		t.Fatalf("the run says %q", o.Detail)
	}
	if ws, g := d.runWrites(), d.gates.list(); len(ws) != 0 || len(g) != 0 {
		t.Fatalf("the run wrote %+v and filed %v", ws, g)
	}
	d.pr.Facts.BaseRefName = "release"
	is(t, d.run(t), pr.ActExcepted)
	if g := d.gates.list(); !slices.Equal(g, []string{bead + " " + record.Invalid}) {
		t.Fatalf("gates filed %v", g)
	}
}

// A record of a merge on a bead the saved read finds open is a contradiction
// only once the act's own read finds the PR open too: a merge that landed after
// the watch's read records nothing.
func TestAMergedRecordsContradictionIsRecordedOnTheActsOwnRead(t *testing.T) {
	for _, c := range []struct {
		name, state, action string
		gates               []string
	}{
		{"the PR still open", "OPEN", pr.ActExcepted, []string{bead + " " + record.EvidenceContradiction}},
		{"the PR merged since the watch read it", "MERGED", pr.ActChecked, nil},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newLand(t)
			for k, v := range map[string]string{"merge_result": record.Merged, "merged_sha": merged,
				"pr_merged_at": "2026-11-12T08:30:00Z"} {
				d.md[k] = v
			}
			d.put("blocked", "")
			d.refresh(t)
			d.pr.Facts.State = c.state
			is(t, d.run(t), c.action)
			if g := d.gates.list(); !slices.Equal(g, c.gates) {
				t.Fatalf("gates filed %v, want %v", g, c.gates)
			}
			if got := d.runReads(); !slices.Equal(got, []string{"PullRequest"}) {
				t.Fatalf("the act read %v, want its own read of the PR", got)
			}
		})
	}
}

func mergedOnGitHub(d *land, h string) {
	d.pr.Facts.State, d.pr.Facts.HeadRefOid = "MERGED", h
	d.pr.Facts.MergeCommit, d.pr.Facts.MergedAt = merged, "2026-11-12T08:30:00Z"
}

// The exception is recorded, guarded, before its gate is filed. A gate that
// does not file keeps the marker, and the next run files it and clears it.
func TestAnExceptionWhoseGateDidNotFileIsFiledByTheNextRun(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	d.gates.err = errors.New("human-gate: could not read the bead's gates")
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("the exception left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.ClosedUnmerged, "pr_reconcile_pending": "true",
		"pr_reconcile_error": "<absent>"})
	d.gates.err = nil
	is(t, d.once(t), pr.ActExcepted)
	meta(t, d.row(t), map[string]string{"merge_result": record.ClosedUnmerged, "pr_reconcile_pending": "<absent>"})
	if !slices.Equal(d.gates.list(), []string{bead + " " + record.ClosedUnmerged}) {
		t.Fatalf("gates filed %v", d.gates.list())
	}
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a later run read the excepted bead: %+v", out)
	}
}

// An exception on a bead that moved between the act's read and its write, as
// one a person reopened, records nothing and files no gate.
func TestAnExceptionOnABeadThatMovedFilesNoGate(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.State = "CLOSED"
	d.refresh(t)
	once := false
	d.store.BeforeUpdate = func(string, []string) error {
		if !once {
			once = true
			d.put("open", "")
		}
		return nil
	}
	is(t, d.run(t), pr.ActMoved)
	if len(d.gates.list()) != 0 || d.row(t).Metadata["merge_result"] != record.Pending {
		t.Fatalf("a moved bead got gates %v and result %s", d.gates.list(), d.row(t).Metadata["merge_result"])
	}
}

func TestAMergedValidatedHeadOnItsTargetCloses(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	is(t, d.once(t), pr.ActLanded)
	b := d.row(t)
	if b.Status != "closed" {
		t.Fatalf("a verified merge left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.Merged, "merged_sha": merged, "merged_target": "main",
		"pr_merged_at": "2026-11-12T08:30:00Z", "pr_head_sha": head, "branch": branch,
		"pr_reconcile_pending": "<absent>", "blocked_reason": "<absent>"})
	savesNothingOfGitHub(t, d)
	readsNoGitHub(t, d)
	if !strings.Contains(b.Notes, "merged to main at "+merged[:8]) {
		t.Fatalf("the close names no merge: %q", b.Notes)
	}
	// The marker is gone, so no later run reads the bead again.
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a later run read a landed bead: %+v", out)
	}
}

// The one-PR update writes pr_state=merged once it reads the PR merged, which
// can come before a run lands the bead: the record is still pending, and the
// run lands it.
func TestAPendingRecordTheUpdateReadMergedLands(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.md["pr_state"] = "merged"
	d.put("blocked", refinery)
	is(t, d.once(t), pr.ActLanded)
}

func TestAMergedChangedHeadStaysBlockedBehindAGate(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, other)
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	meta(t, b, map[string]string{"merge_result": record.MergedUnvalidatedHead, "pr_reconcile_pending": "<absent>"})
	if b.Status != "blocked" || !slices.Equal(d.gates.list(), []string{bead + " " + record.MergedUnvalidatedHead}) {
		t.Fatalf("a merge of another head left the bead %s with gates %v", b.Status, d.gates.list())
	}
}

// What holds a verified merge's close, an open child or a live blocker, is no
// fact the landing order can change, so the close bd refuses is an exception a
// person resolves, with the merge's evidence kept.
func TestAVerifiedMergeWhoseCloseBdRefusesIsAnExceptionBehindAGate(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.store.BeforeUpdate = func(_ string, args []string) error {
		if slices.Contains(args, "--status=closed") {
			return errors.New("exit status 1: Error: cannot close blocked issue: " + bead + " is blocked by [tk-kid]")
		}
		return nil
	}
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a refused close left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.CloseRefused, "merged_sha": merged,
		"merged_target": "main", "pr_merged_at": "2026-11-12T08:30:00Z", "pr_reconcile_pending": "<absent>"})
	savesNothingOfGitHub(t, d)
	if !strings.Contains(b.Metadata["blocked_reason"], "is blocked by [tk-kid]") {
		t.Errorf("blocked_reason %q does not name what holds the close", b.Metadata["blocked_reason"])
	}
	if got := d.gates.list(); !slices.Equal(got, []string{bead + " " + record.CloseRefused}) {
		t.Fatalf("gates %v, want one keyed %s", got, record.CloseRefused)
	}
	msg := d.gates.messages[0]
	for _, want := range []string{"is blocked by [tk-kid]", "gc bd update " + bead + " --status=closed --set-metadata merge_result=" + record.Merged} {
		if !strings.Contains(msg, want) {
			t.Errorf("the gate's message %q lacks %q", msg, want)
		}
	}
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a run after the exception read %+v, want nothing: the marker is cleared", out)
	}
}

// A close the store failed says nothing about what holds it, so the next run
// acts on it again.
func TestAVerifiedMergeWhoseCloseTheStoreFailedIsActedOnAgain(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	fail := true
	d.store.BeforeUpdate = func(_ string, args []string) error {
		if fail && slices.Contains(args, "--status=closed") {
			return errors.New("exit status 1: Error: database is locked")
		}
		return nil
	}
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a failed close left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.Pending, "pr_reconcile_pending": "true", "pr_reconcile_error": "<absent>"})
	if got := d.gates.list(); len(got) != 0 {
		t.Fatalf("a failed write filed gates %v", got)
	}
	fail = false
	is(t, d.once(t), pr.ActLanded)
}

func TestAnUnreachableMergeCommitIsActedOnAgainWithoutAClose(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.co.reachable = map[string]bool{}
	is(t, d.once(t), pr.ActRetry)
	b := d.row(t)
	meta(t, b, map[string]string{"pr_reconcile_pending": "true", "merge_result": record.Pending, "pr_reconcile_error": "<absent>"})
	if b.Status != "blocked" || len(d.gates.list()) != 0 {
		t.Fatalf("an unreachable merge left the bead %s with gates %v", b.Status, d.gates.list())
	}
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("an unreachable merge wrote %+v", ws)
	}
}

// A landing whose fetch failed, and a merge whose own read of GitHub failed,
// each write nothing, and the next run acts on the record again.
func TestAFailedFetchOrMergeReadWritesNothingAndTheNextRunActs(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.co.fetchErr = errors.New("could not read from remote repository")
	is(t, d.once(t), pr.ActRetry)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a failed fetch wrote %+v", ws)
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true", "pr_reconcile_error": "<absent>"})
	d.co.fetchErr = nil
	is(t, d.once(t), pr.ActLanded)

	d = newLand(t)
	d.refresh(t)
	d.github.Fail["PullRequest"] = errors.New("HTTP 502")
	is(t, d.run(t), pr.ActRetry)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a merge whose own read failed wrote %+v", ws)
	}
	delete(d.github.Fail, "PullRequest")
	is(t, d.run(t), pr.ActRequested)
}

func TestAClosedBeadWithNoVerifiedMergeIsReopenedBlocked(t *testing.T) {
	d := newLand(t)
	d.put("closed", "")
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a closed bead with no verified merge was left %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.LegacyClosed, "pr_reconcile_pending": "<absent>"})
	if !slices.Equal(d.gates.list(), []string{bead + " " + record.LegacyClosed}) {
		t.Fatalf("gates filed %v", d.gates.list())
	}
}

// A verified merge is its commit and its time, which the landing writes:
// pr_state is the one-PR update's read, here still open.
func TestAClosedBeadOnAVerifiedMergeHasItsMarkerCleared(t *testing.T) {
	d := newLand(t)
	for k, v := range map[string]string{"merge_result": record.Merged, "merged_sha": merged,
		"pr_merged_at": "2026-11-12T08:30:00Z"} {
		d.md[k] = v
	}
	d.put("closed", "")
	is(t, d.once(t), pr.ActSettled)
	if b := d.row(t); b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the settle left %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
}

func TestAPRThatIsNoLongerTheRecordsIsAnException(t *testing.T) {
	for name, change := range map[string]func(*ghfake.PR){
		"its head branch": func(p *ghfake.PR) { p.Facts.HeadRefName = "polecat/other" },
		"its base":        func(p *ghfake.PR) { p.Facts.BaseRefName = "release" },
		"its URL":         func(p *ghfake.PR) { p.Facts.URL = "https://github.com/acme/widgets/pull/8" },
	} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			change(d.pr)
			is(t, d.once(t), pr.ActExcepted)
			meta(t, d.row(t), map[string]string{"merge_result": record.Invalid})
		})
	}
}

// A bead with no read of its PR saved owes no act until the PR watch saves one.
func TestARecordWithNoSavedReadWaitsForThePRWatch(t *testing.T) {
	d := newLand(t)
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "no read of the PR itself is saved") {
		t.Fatalf("a record with no saved read says %q", o.Detail)
	}
	readsNoGitHub(t, d)
	if len(d.runWrites()) != 0 || len(d.github.Asks()) != 0 {
		t.Fatalf("a record with no saved read was written %+v or asked %v", d.runWrites(), asks(d.github))
	}
}

// --- the run's order and bounds ---------------------------------------------

// A run decides every record and takes the ones that owe an act in the order
// Shuffle gives them. A record that owes none reports what it waits on first.
func TestARunTakesTheRecordsThatOweAnActInAShuffledOrder(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	d.refresh(t)
	for i := range 3 {
		id := fmt.Sprintf("tk-o%d", i)
		d.also(t, id, "open")
		r, _ := d.store.Row(id)
		r.Metadata["merge_result"], r.Metadata["observed_pr_head_sha"] = record.HeadChanged, other
		d.store.Put(r)
	}
	var given []string
	d.l.Shuffle = func(ids []string) {
		given = slices.Clone(ids)
		slices.Reverse(ids)
	}
	out := d.reconcile(t, pr.Options{})
	if !slices.Equal(given, []string{"tk-o0", "tk-o1", "tk-o2"}) {
		t.Fatalf("the shuffle was given %v, want the records that owe an act", given)
	}
	var order []string
	for _, o := range out {
		order = append(order, o.Bead+" "+o.Action)
	}
	want := []string{"tk-1 checked", "tk-o2 settled", "tk-o1 settled", "tk-o0 settled"}
	if !slices.Equal(order, want) {
		t.Fatalf("the run did %v, want %v", order, want)
	}
	readsNoGitHub(t, d)
}

// No act starts past the run's window, and the acts the window left are the
// next run's.
func TestNoActStartsPastTheRunsWindow(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	d.refresh(t)
	d.also(t, "tk-a", "blocked")
	d.also(t, "tk-b", "blocked")
	c := d.timed()
	window := 45 * time.Second
	first := true
	d.store.BeforeUpdate = func(string, []string) error {
		if first {
			first = false
			c.advance(window + time.Second)
		}
		return nil
	}
	out := d.reconcile(t, pr.Options{Window: window})
	var order []string
	for _, o := range out {
		order = append(order, o.Bead+" "+o.Action)
	}
	if !slices.Equal(order, []string{"tk-1 requeued", "tk-a left", "tk-b left"}) {
		t.Fatalf("the run did %v, want the first act and the rest left at the window", order)
	}
	acted := map[string]string{}
	for _, o := range d.reconcile(t, pr.Options{Window: window}) {
		acted[o.Bead] = o.Action
	}
	if acted["tk-a"] != pr.ActRequeued || acted["tk-b"] != pr.ActRequeued {
		t.Fatalf("the next run did %v, want the acts the window left", acted)
	}
}

// Each act is stopped at its bound with whatever GitHub call, fetch, human
// gate's filing or refinery's wake it is making, so a run whose first act does
// not end still starts the next one. A stopped act's difference stays on the
// bead, and the next run acts on it again.
func TestAnActIsStoppedAtItsBoundAndTheNextActStarts(t *testing.T) {
	t.Run("a GitHub call", func(t *testing.T) {
		d := newLand(t)
		d.refresh(t)
		d.also(t, "tk-2", "blocked")
		d.l.Hub = func(ctx context.Context, _ string) pr.Hub { return stalled{d.github, ctx} }
		start := time.Now()
		out := d.reconcile(t, pr.Options{Window: time.Minute, Stop: 300 * time.Millisecond})
		if elapsed := time.Since(start); elapsed > 5*time.Second {
			t.Fatalf("two stopped acts took %s", elapsed.Round(time.Millisecond))
		}
		if len(out) != 2 {
			t.Fatalf("two records, %d outcomes: %+v", len(out), out)
		}
		for _, o := range out {
			is(t, o, pr.ActRetry)
			if !strings.Contains(o.Detail, "stopped") {
				t.Fatalf("a stopped act says %q", o.Detail)
			}
		}
		if ws := d.runWrites(); len(ws) != 0 {
			t.Fatalf("a stopped act wrote %+v", ws)
		}
	})
	t.Run("a fetch", func(t *testing.T) {
		d := newLand(t)
		mergedOnGitHub(d, head)
		d.refresh(t)
		d.co.fetchBlocks = true
		start := time.Now()
		o := d.reconcile(t, pr.Options{Window: time.Minute, Stop: 300 * time.Millisecond})
		if elapsed := time.Since(start); elapsed > 5*time.Second {
			t.Fatalf("a stopped fetch took %s", elapsed.Round(time.Millisecond))
		}
		if len(o) != 1 {
			t.Fatalf("one record, %d outcomes: %+v", len(o), o)
		}
		is(t, o[0], pr.ActRetry)
		if !strings.Contains(o[0].Detail, "stopped") || len(d.runWrites()) != 0 {
			t.Fatalf("a stopped fetch says %q and wrote %+v", o[0].Detail, d.runWrites())
		}
		d.co.fetchBlocks = false
		is(t, d.run(t), pr.ActLanded)
	})
	t.Run("a human gate's filing", func(t *testing.T) {
		d := newLand(t)
		d.pr.Facts.State = "CLOSED"
		d.refresh(t)
		d.also(t, "tk-2", "blocked")
		d.gates.stall = true
		start := time.Now()
		out := d.reconcile(t, pr.Options{Window: time.Minute, Stop: 300 * time.Millisecond})
		if elapsed := time.Since(start); elapsed > 5*time.Second {
			t.Fatalf("two stopped filings took %s", elapsed.Round(time.Millisecond))
		}
		if len(out) != 2 {
			t.Fatalf("two records, %d outcomes: %+v", len(out), out)
		}
		for _, o := range out {
			is(t, o, pr.ActRetry)
			if !strings.Contains(o.Detail, "stopped") || !strings.Contains(o.Detail, record.ClosedUnmerged) {
				t.Fatalf("a stopped filing says %q", o.Detail)
			}
		}
		if g := d.gates.list(); len(g) != 0 {
			t.Fatalf("a stopped filing filed %v", g)
		}
		d.gates.stall = false
		for _, o := range d.reconcile(t, pr.Options{Window: time.Minute, Stop: 300 * time.Millisecond}) {
			is(t, o, pr.ActExcepted)
		}
		if g := d.gates.list(); !slices.Equal(g, []string{bead + " " + record.ClosedUnmerged, "tk-2 " + record.ClosedUnmerged}) {
			t.Fatalf("the next run filed %v", g)
		}
	})
	t.Run("the refinery's wake", func(t *testing.T) {
		d := newHanding(t)
		d.conversation(t, "open", "human", "")
		d.pr.Facts.HeadRefOid = other
		d.refresh(t)
		d.l.Wake = stalledWake{}
		start := time.Now()
		out := d.reconcile(t, pr.Options{Window: time.Minute, Stop: 300 * time.Millisecond})
		if elapsed := time.Since(start); elapsed > 5*time.Second {
			t.Fatalf("a stopped wake took %s", elapsed.Round(time.Millisecond))
		}
		if len(out) != 1 {
			t.Fatalf("one record, %d outcomes: %+v", len(out), out)
		}
		is(t, out[0], pr.ActRetry)
		if !strings.Contains(out[0].Detail, "stopped") || !strings.Contains(out[0].Detail, "wake did not land") {
			t.Fatalf("a stopped wake says %q", out[0].Detail)
		}
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
		d.l.Wake = d.wakes
		o := d.run(t)
		is(t, o, pr.ActSettled)
		d.wokeOnce(t, "tk-conv")
	})
}

// stalledWake is a refinery whose wake does not answer until the act's context
// ends.
type stalledWake struct{}

func (stalledWake) Wake(ctx context.Context, _, _ string) error {
	<-ctx.Done()
	return fmt.Errorf("gc session wake was stopped: %w", ctx.Err())
}

// stalled is GitHub answering no merge's read or request until the act's
// context ends.
type stalled struct {
	*ghfake.GitHub
	ctx context.Context
}

func (s stalled) PullRequest(string, int) (*gh.PullRequest, error) {
	<-s.ctx.Done()
	return nil, fmt.Errorf("gh: the call was stopped: %w", s.ctx.Err())
}

// Over runs whose window takes a few of many records' acts, a shuffled order
// reaches every record within a few runs, with no record waiting behind the
// same others, here acts that keep failing.
func TestTheOrderOfActsAcrossRunsUnderLoad(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.refresh(t)
	c := d.timed()
	d.co.fetchErr, d.co.onFetch = errors.New("could not read from remote repository"), func() { c.advance(3 * time.Second) }
	src := rand.New(rand.NewPCG(1, 2))
	d.l.Shuffle = func(ids []string) { src.Shuffle(len(ids), func(i, j int) { ids[i], ids[j] = ids[j], ids[i] }) }
	ids := []string{bead}
	for i := 0; i < 50; i++ {
		id := fmt.Sprintf("tk-l%02d", i)
		d.also(t, id, "blocked")
		ids = append(ids, id)
	}
	seen := map[string]int{}
	runs := 0
	for ; runs < 20 && len(seen) < len(ids); runs++ {
		for _, o := range d.reconcile(t, pr.Options{Window: 45 * time.Second}) {
			if o.Action != pr.ActLeft {
				seen[o.Bead]++
			}
		}
	}
	for _, id := range ids {
		if seen[id] == 0 {
			t.Fatalf("%s was not acted on in %d runs over 51 records: %v", id, runs, seen)
		}
	}
}

// --- the pack's merge request -------------------------------------------------

func TestAReadyPRIsMergedWithItsHeadPinned(t *testing.T) {
	d := newLand(t)
	is(t, d.once(t), pr.ActRequested)
	if got := asks(d.github); !slices.Equal(got, []string{"MergePullRequest PR_7 " + head}) {
		t.Fatalf("asked %v, want one merge pinned to %s", got, head)
	}
	if d.row(t).Status != "blocked" {
		t.Fatal("the request closed the bead before the merge was verified")
	}
	// The watch reads the merged PR, and the next run closes the bead.
	is(t, d.once(t), pr.ActLanded)
	if d.row(t).Status != "closed" || len(d.github.Asks()) != 1 {
		t.Fatalf("after the merge the bead is %s, with asks %v", d.row(t).Status, asks(d.github))
	}
}

// The merge takes the whole read of GitHub in its own act and pins its request
// to the head that read judged, whatever the saved read found.
func TestTheMergeDecidesAgainOnItsOwnReadPinnedToTheHeadItJudged(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	d.pr.Facts.HeadRefOid = other
	o := d.run(t)
	is(t, o, pr.ActChecked)
	if !strings.HasSuffix(o.Detail, "the merge's own read found it not ready, so no merge was requested: github-unread") {
		t.Fatalf("a head pushed after the saved read was merged or said %q", o.Detail)
	}
	if len(d.github.Asks()) != 0 {
		t.Fatalf("asked %v on a read whose head moved", asks(d.github))
	}
	reads := d.runReads()
	for _, want := range []string{"PullRequest", "CheckSuites", "Reviews", "ReviewThreads", "IssueComments"} {
		if !slices.Contains(reads, want) {
			t.Fatalf("the merge's own read %v lacks %s", reads, want)
		}
	}
	if n := len(slices.DeleteFunc(slices.Clone(reads), func(r string) bool { return r != "PullRequest" })); n != 1 {
		t.Fatalf("the merge read the PR %d times, want once: %v", n, reads)
	}
}

func TestAPushBetweenTheAnswerAndTheRequestIsRefusedAndRequeued(t *testing.T) {
	d := newLand(t)
	d.github.OnMerge = func(_ string, p *ghfake.PR, h string) error {
		p.Facts.HeadRefOid = other
		if p.Facts.HeadRefOid != h {
			return errors.New("github: Head branch was modified. Review and try the merge again.")
		}
		return nil
	}
	is(t, d.once(t), pr.ActRetry)
	if d.pr.Facts.State != "OPEN" || d.row(t).Status != "blocked" {
		t.Fatal("a refused request merged or moved the bead")
	}
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other})
}

func TestARequestLeftUnansweredIsDecidedAgain(t *testing.T) {
	// GitHub takes the request after its answer was lost: the watch reads it
	// merged, and the next run lands it.
	d := newLand(t)
	d.github.OnMerge = func(_ string, p *ghfake.PR, h string) error {
		p.Facts.State, p.Facts.MergeCommit, p.Facts.MergedAt = "MERGED", merged, "2026-11-12T08:30:00Z"
		return errors.New("github: timeout awaiting response")
	}
	is(t, d.once(t), pr.ActRetry)
	is(t, d.once(t), pr.ActLanded)

	// GitHub never took it: the next run decides again and asks again.
	d = newLand(t)
	d.github.OnMerge = func(string, *ghfake.PR, string) error { return errors.New("github: timeout awaiting response") }
	is(t, d.once(t), pr.ActRetry)
	is(t, d.once(t), pr.ActRetry)
	if len(d.github.Asks()) != 2 {
		t.Fatalf("an unanswered request was not asked again: %v", asks(d.github))
	}
}

func TestAMergeQueueTakesThePROrDropsIt(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.MergeQueueEnabled = true
	is(t, d.once(t), pr.ActRequested)
	if got := asks(d.github); !slices.Equal(got, []string{"EnqueuePullRequest PR_7 " + head}) {
		t.Fatalf("asked %v, want one enqueue pinned to %s", got, head)
	}
	// In the queue, the PR's merge is requested already.
	is(t, d.once(t), pr.ActChecked)
	readsNoGitHub(t, d)
	if len(d.github.Asks()) != 1 {
		t.Fatalf("a queued PR was asked again: %v", asks(d.github))
	}
	// The queue drops it: the next run decides again.
	d.pr.Facts.InMergeQueue = false
	is(t, d.once(t), pr.ActRequested)
	// The queue takes it: the run after closes the bead.
	mergedOnGitHub(d, head)
	is(t, d.once(t), pr.ActLanded)
}

func TestAPRMergedIntoAnotherBaseIsNotLanded(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.pr.Facts.BaseRefName = "release"
	is(t, d.once(t), pr.ActExcepted)
	b := d.row(t)
	if b.Status != "blocked" || b.Metadata["merge_result"] != record.Invalid {
		t.Fatalf("a merge into another base left the bead %s, %s", b.Status, b.Metadata["merge_result"])
	}
}

// --- the landing order acts from the beads -------------------------------------

// Every act but the merge decides from the saved read and the store: a run
// reads no GitHub for a landing, a send-back, a draft marked ready or a
// withdrawn approval's dismissal, and the only calls it makes are the act's own
// writes. An exception the saved read finds a closed PR owes is recorded on the
// act's own read of the PR, which must find it closed too, and a withdrawal
// closes on the act's own read of the PR's reviews.
func TestEachActButTheMergeDecidesFromTheSavedRead(t *testing.T) {
	for _, c := range []struct {
		name   string
		set    func(*land)
		action string
		reads  []string
		asked  []string
	}{
		{"a landing", func(d *land) { mergedOnGitHub(d, head) }, pr.ActLanded, nil, nil},
		{"a send-back", func(d *land) { d.pr.Facts.HeadRefOid = other }, pr.ActRequeued, nil, nil},
		{"an exception's gate", func(d *land) { d.pr.Facts.State = "CLOSED" }, pr.ActExcepted, []string{"PullRequest"}, nil},
		{"a draft marked ready", func(d *land) { d.pr.Facts.IsDraft = true }, pr.ActReadied, nil, []string{"MarkReady PR_7 "}},
		{"a withdrawn approval's dismissal", func(d *land) {
			d.pr.Reviews = []gh.Review{approved(100, "operator", older), approved(101, "reviewer", head)}
			d.pr.Facts.HeadRefOid = later
		}, pr.ActRequeued, []string{"Reviews"}, []string{"DismissReview 100 "}},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newCycle(t)
			c.set(d)
			if c.name == "a withdrawn approval's dismissal" {
				d.withdraw(t, head)
			}
			is(t, d.once(t), c.action)
			if got := d.runReads(); !slices.Equal(got, c.reads) {
				t.Fatalf("the act read GitHub %v, want %v", got, c.reads)
			}
			if got := asks(d.github); !slices.Equal(got, c.asked) {
				t.Fatalf("the act asked GitHub %v, want %v", got, c.asked)
			}
		})
	}
}

// The one-PR update is the one writer of GitHub's side on a bead (refresh.go),
// so no write a run makes carries the saved read, pr_state or
// pr_last_checked_at.

// displayed is what a display derives over the store as the run left it.
func (d *land) displayed(t *testing.T) pr.Answer {
	t.Helper()
	ans, err := pr.FromStore(ledger.New(d.store), bead)
	if err != nil {
		t.Fatalf("FromStore: %v", err)
	}
	return ans
}

// savesNothingOfGitHub fails if a write the last run made carries GitHub's
// side.
func savesNothingOfGitHub(t *testing.T, d *land) {
	t.Helper()
	for _, w := range d.runWrites() {
		for _, a := range w.Args {
			for _, k := range []string{"pr_github_read=", "pr_state=", "pr_last_checked_at="} {
				if strings.Contains(a, k) {
					t.Fatalf("a run wrote %s: %v", a, w.Args)
				}
			}
		}
	}
}

func TestACheckOfAPRNotReadyWritesNothing(t *testing.T) {
	d := newLand(t)
	d.pr.Reviews = nil
	is(t, d.once(t), pr.ActChecked)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a check that left the record standing wrote %+v", ws)
	}
}

// An act that did not complete records nothing: no key says it failed, its
// difference stays on the bead, and the next run acts on it again.
func TestAnActThatDidNotCompleteWritesNothingAndTheNextRunActs(t *testing.T) {
	d := newLand(t)
	mergedOnGitHub(d, head)
	d.refresh(t)
	d.co.fetchErr = errors.New("could not read from remote repository")
	is(t, d.run(t), pr.ActRetry)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("an act that did not complete wrote %+v", ws)
	}
	for k := range d.row(t).Metadata {
		if strings.Contains(k, "error") {
			t.Fatalf("an act that did not complete left %s on the bead", k)
		}
	}
	d.co.fetchErr = nil
	is(t, d.run(t), pr.ActLanded)
}

func TestARequestSavesNothingOfGitHub(t *testing.T) {
	d := newLand(t)
	d.github.OnMerge = func(_ string, p *ghfake.PR, h string) error {
		p.Facts.State, p.Facts.MergeCommit, p.Facts.MergedAt = "MERGED", merged, "2026-11-12T08:30:00Z"
		return nil
	}
	is(t, d.once(t), pr.ActRequested)
	savesNothingOfGitHub(t, d)
}

func TestARefusedRequestWritesNothing(t *testing.T) {
	d := newLand(t)
	d.github.OnMerge = func(string, *ghfake.PR, string) error { return errors.New("github: timeout awaiting response") }
	is(t, d.once(t), pr.ActRetry)
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a refused request wrote %+v", ws)
	}
}

// A merge whose own read does not answer writes nothing and requests nothing,
// and the next run decides again.
func TestAMergesOwnReadThatFailsWritesNothing(t *testing.T) {
	for _, f := range []string{"PullRequest", "CheckSuites", "Reviews", "Login", "ReviewThreads", "IssueComments", "the definition"} {
		t.Run(f, func(t *testing.T) {
			d := newLand(t)
			d.refresh(t)
			if f == "the definition" {
				d.rule.err = errors.New("jq: failed")
			} else {
				d.github.Fail[f] = errors.New("github: HTTP 502")
			}
			is(t, d.run(t), pr.ActRetry)
			if ws := d.runWrites(); len(ws) != 0 || len(d.github.Asks()) != 0 {
				t.Fatalf("the failed read wrote %+v and asked %v", ws, asks(d.github))
			}
			meta(t, d.row(t), map[string]string{"merge_result": record.Pending, "pr_reconcile_pending": "true"})
		})
	}
}

// A writer that takes no lock can leave the record lacking a part between the
// run's decision and the merge's own read, which then reads no more of GitHub.
func TestAMergeWhoseRecordLostAPartReadsThePRAlone(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	moved := false
	d.github.OnRead = func(method string, _ *ghfake.PR) {
		if method != "PullRequest" || moved {
			return
		}
		moved = true
		b, _ := d.store.Row(bead)
		b.Metadata = maps.Clone(b.Metadata)
		delete(b.Metadata, "merged_target")
		d.store.Put(b)
	}
	out := d.run(t)
	is(t, out, pr.ActChecked)
	if !strings.HasSuffix(out.Detail, "so no merge was requested: record") {
		t.Fatalf("the merge says %q, want the record's gap alone", out.Detail)
	}
	if reads := d.runReads(); !slices.Equal(reads, []string{"PullRequest"}) {
		t.Fatalf("the run read %v, want the PR's read alone", reads)
	}
	savesNothingOfGitHub(t, d)
}

// The merge needs both: a saved read the evaluator finds ready, and its own
// read of GitHub, which it decides again on.
func TestTheMergeActsOnlyWhenTheSavedReadAndItsOwnReadFindThePRReady(t *testing.T) {
	save := func(t *testing.T, d *land, read pr.GitHubRead) {
		t.Helper()
		raw, err := json.Marshal(saveRead(&read))
		if err != nil {
			t.Fatal(err)
		}
		d.md["pr_github_read"] = string(raw)
		d.put("blocked", "")
	}
	readyRead := pr.GitHubRead{ReadAt: "2026-11-12T08:00:00Z", URL: prURL, Number: 7, Repository: repo,
		HeadBranch: branch, Base: "main", Head: head, State: "OPEN", MergeState: "CLEAN",
		Checks:    []pr.RequiredRun{{Name: "test", Status: "COMPLETED", Conclusion: "SUCCESS"}},
		Approvers: []string{"operator"}, Requesters: []string{}, Awaiting: []string{}}
	t.Run("a saved read that is ready, while GitHub holds the PR, gets no request", func(t *testing.T) {
		d := newLand(t)
		save(t, d, readyRead)
		isReady(t, d.displayed(t))
		d.pr.Reviews = nil
		is(t, d.run(t), pr.ActChecked)
		if len(d.github.Asks()) != 0 {
			t.Fatalf("asked %v on a saved read while GitHub holds the PR", asks(d.github))
		}
		savesNothingOfGitHub(t, d)
	})
	t.Run("a saved read that holds the PR gets no request, and reads no GitHub", func(t *testing.T) {
		d := newLand(t)
		held := readyRead
		held.Approvers = []string{}
		save(t, d, held)
		only(t, d.displayed(t), pr.KindApproval)
		is(t, d.run(t), pr.ActChecked)
		readsNoGitHub(t, d)
		if len(d.github.Asks()) != 0 {
			t.Fatalf("asked %v on a saved read that holds the PR", asks(d.github))
		}
	})
}

// --- the seed audit after a landing --------------------------------------------

// withAudit is a bead whose PR merged at the validated head into main, the
// rig's default branch, in a rig whose repository carries a seed audit stale in
// pages at the merge.
func withAudit(t *testing.T, pages ...string) (*land, *audit) {
	t.Helper()
	d := newLand(t)
	mergedOnGitHub(d, head)
	a := &audit{stale: map[string][]string{merged: pages}}
	d.l.Audit = a
	return d, a
}

func says(t *testing.T, o pr.RunOutcome, wants ...string) {
	t.Helper()
	for _, w := range wants {
		if !strings.Contains(o.Detail, w) {
			t.Errorf("the outcome %q does not say %q", o.Detail, w)
		}
	}
}

// A landing on the default branch that leaves its seed audit stale hands the
// stale pages to the writer of the branch's re-render, once, and the bead
// closes as it does in a rig with no audit.
func TestALandingThatLeavesTheSeedAuditStaleAsksForItsReRenderOnce(t *testing.T) {
	d, a := withAudit(t, "agents/claude.md", "formulas/mol-polecat-base.md")
	o := d.once(t)
	is(t, o, pr.ActLanded)
	b := d.row(t)
	if b.Status != "closed" {
		t.Fatalf("the landing left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"merge_result": record.Merged, "pr_reconcile_pending": "<absent>"})
	checks, reaudits := a.calls()
	if !slices.Equal(checks, []string{merged}) {
		t.Fatalf("checked %v, want the merge on main", checks)
	}
	if !slices.Equal(reaudits, []string{"main agents/claude.md,formulas/mol-polecat-base.md"}) {
		t.Fatalf("handed off %v, want main's two stale pages once", reaudits)
	}
	if want := "The landing order, checking main at " + merged + " after PR #7 landed,"; a.seenBy[0] != want {
		t.Errorf("the writer was told it was found by %q, want %q", a.seenBy[0], want)
	}
	says(t, o, "PR #7 merged to main at e1111111: the bead is closed",
		"the seed audit on main at e1111111 is stale in 2 of its pages",
		"answered re-1 gc-toolkit/gc-toolkit.polecat filed")
}

// A landing that leaves the audit current asks for no re-render.
func TestALandingThatLeavesTheSeedAuditCurrentAsksForNone(t *testing.T) {
	d, a := withAudit(t)
	o := d.once(t)
	is(t, o, pr.ActLanded)
	checks, reaudits := a.calls()
	if !slices.Equal(checks, []string{merged}) || len(reaudits) != 0 {
		t.Fatalf("checked %v and handed off %v, want one check and no hand-off", checks, reaudits)
	}
	says(t, o, "the seed audit on main is current at e1111111")
}

// The check reads the default branch at its tip as the act fetched it, which
// carries every merge since this one, so a render a later commit made current
// asks for nothing.
func TestTheCheckReadsTheDefaultBranchAtTheTipTheActFetched(t *testing.T) {
	d, a := withAudit(t, "agents/claude.md")
	d.co.tip = other
	o := d.once(t)
	checks, reaudits := a.calls()
	if !slices.Equal(checks, []string{other}) || len(reaudits) != 0 {
		t.Fatalf("checked %v and handed off %v, want main's tip %s alone", checks, reaudits, other)
	}
	says(t, o, "the seed audit on main is current at 22222222")
}

// Only the default branch is re-rendered, so a landing on any other, such as an
// integration branch, checks nothing and says nothing of the audit.
func TestALandingOnAnotherBranchChecksNoSeedAudit(t *testing.T) {
	d, a := withAudit(t, "agents/claude.md")
	d.co.def = "trunk"
	o := d.once(t)
	is(t, o, pr.ActLanded)
	if checks, reaudits := a.calls(); len(checks)+len(reaudits) != 0 {
		t.Fatalf("a landing on main, not the default trunk, checked %v and handed off %v", checks, reaudits)
	}
	if strings.Contains(o.Detail, "seed audit") {
		t.Fatalf("the outcome %q speaks of an audit no landing on main checks", o.Detail)
	}
}

// A check that does not run, for any reason, holds nothing: the bead closes and
// its marker clears as with no audit, nothing is handed off but the pages a
// check found, and the outcome says a later landing asks again.
func TestASeedAuditCheckThatDoesNotRunHoldsNothing(t *testing.T) {
	for _, c := range []struct {
		name   string
		set    func(*land, *audit)
		says   string
		handed int
	}{
		{"the default branch does not read", func(d *land, _ *audit) { d.co.defErr = errors.New("origin/HEAD is gone") },
			"the rig's default branch did not read, so no seed audit was checked, and a later landing checks it", 0},
		{"the tip does not read", func(d *land, _ *audit) { d.co.tipErr = errors.New("bad object") },
			"the tip of main did not read, so its seed audit was not checked, and a later landing checks it", 0},
		{"the render does not run", func(_ *land, a *audit) { a.failChecks = 1 },
			"the seed audit on main at e1111111 was not checked, and a later landing checks it: render-seed-audit.sh: exit 2", 0},
		{"the writer refuses", func(_ *land, a *audit) { a.failReaudits = 1 },
			"its re-render was not asked for, so a later landing asks again: seed-audit-reaudit.sh: exit 2", 1},
	} {
		t.Run(c.name, func(t *testing.T) {
			d, a := withAudit(t, "agents/claude.md")
			c.set(d, a)
			o := d.once(t)
			is(t, o, pr.ActLanded)
			b := d.row(t)
			if b.Status != "closed" || len(d.gates.list()) != 0 {
				t.Fatalf("a check that did not run left the bead %s, with gates %v", b.Status, d.gates.list())
			}
			meta(t, b, map[string]string{"merge_result": record.Merged, "pr_reconcile_pending": "<absent>"})
			if _, reaudits := a.calls(); len(reaudits) != c.handed {
				t.Errorf("handed off %v, want %d", reaudits, c.handed)
			}
			says(t, o, "the bead is closed", c.says)
		})
	}
}

// A check that did not run is asked for again by the next landing, even one the
// same run finds at the same tip, and a tip a check has answered is not checked
// again in that run.
func TestALaterLandingChecksAgainAndATipIsCheckedOnceARun(t *testing.T) {
	d, a := withAudit(t, "agents/claude.md")
	a.failChecks = 1
	d.refresh(t)
	d.also(t, "tk-2", "blocked")
	d.also(t, "tk-3", "blocked")
	out := d.reconcile(t, pr.Options{})
	if len(out) != 3 {
		t.Fatalf("three records, %d outcomes: %+v", len(out), out)
	}
	for _, o := range out {
		is(t, o, pr.ActLanded)
	}
	checks, reaudits := a.calls()
	if !slices.Equal(checks, []string{merged, merged}) || !slices.Equal(reaudits, []string{"main agents/claude.md"}) {
		t.Fatalf("checked %v and handed off %v, want the failed check run again once, and one hand-off", checks, reaudits)
	}
	says(t, out[0], "was not checked, and a later landing checks it")
	says(t, out[1], "is stale in 1 of its pages", "answered re-1")
	says(t, out[2], "the seed audit on main at e1111111 was checked after tk-2 landed")
}

// A landing that completes after the run's window leaves the check to a later
// landing, so the check cannot carry a run past its time limit.
func TestALandingPastTheRunsWindowLeavesTheCheckToALaterOne(t *testing.T) {
	d, a := withAudit(t, "agents/claude.md")
	d.refresh(t)
	c := d.timed()
	window := 45 * time.Second
	d.store.BeforeUpdate = func(_ string, args []string) error {
		if slices.Contains(args, "--status=closed") {
			c.advance(window + time.Second)
		}
		return nil
	}
	out := d.reconcile(t, pr.Options{Window: window})
	if len(out) != 1 {
		t.Fatalf("one record, %d outcomes: %+v", len(out), out)
	}
	is(t, out[0], pr.ActLanded)
	if checks, _ := a.calls(); len(checks) != 0 {
		t.Fatalf("a landing past the window checked %v", checks)
	}
	says(t, out[0], "the run had used its 45s, so the seed audit on main was not checked, and a later landing checks it")
}

// --- the record's writers under the lock --------------------------------------

// pause makes the first read of the PR a merge makes wait until the test lets
// it go, and reports when the act is there, holding the lock.
func pause(g *ghfake.GitHub) (there, goOn chan struct{}) {
	there, goOn = make(chan struct{}), make(chan struct{})
	var once sync.Once
	g.OnRead = func(method string, _ *ghfake.PR) {
		if method != "PullRequest" {
			return
		}
		once.Do(func() {
			close(there)
			<-goOn
		})
	}
	return there, goOn
}

// pauseWrite makes the first write a run makes wait until the test lets it go,
// and reports when the act is there, holding the lock.
func pauseWrite(s *fake.Store) (there, goOn chan struct{}) {
	there, goOn = make(chan struct{}), make(chan struct{})
	var once sync.Once
	s.BeforeUpdate = func(string, []string) error {
		once.Do(func() {
			close(there)
			<-goOn
		})
		return nil
	}
	return there, goOn
}

// waits fails unless done stays open for a while: the writer behind it waits.
func waits(t *testing.T, done chan error, who string) {
	t.Helper()
	select {
	case err := <-done:
		t.Fatalf("%s went ahead while another writer held the lock: %v", who, err)
	case <-time.After(300 * time.Millisecond):
	}
}

// dispose is a disposition's close as bead-rehome.sh makes it: under the
// record lock, it reads the bead, then closes it guarded on what it read and
// clears any marker it finds, in one write.
func dispose(d *land) error {
	release, err := record.Lock(d.l.Dir, 5*time.Second)
	if err != nil {
		return err
	}
	defer release()
	b, _ := d.store.Row(bead)
	args := []string{"--if-status=" + b.Status, "--if-assignee=" + b.Assignee, "--status=closed"}
	if _, marked := b.Metadata["pr_reconcile_pending"]; marked {
		args = append(args, "--unset-metadata", "pr_reconcile_pending")
	}
	_, err = d.store.Update(bead, args...)
	return err
}

// The record lock is the store's, so the refinery's publication waits while an
// act holds the lock, and lands after the act's last write: here the act hands
// a changed head to the refinery, which publishes it.
func TestARecordWriteWaitsWhileAnActHoldsTheLockAndLandsAfterItsLastWrite(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	d.refresh(t)
	mark := len(d.store.Writes())
	there, goOn := pauseWrite(d.store)
	ran := make(chan error, 1)
	go func() { ran <- d.l.Reconcile(pr.Options{}, func(pr.RunOutcome) {}) }()
	<-there
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(other)) }()
	waits(t, recorded, "the publication")
	close(goOn)
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	ws := d.store.Writes()[mark:]
	if len(ws) != 3 || !slices.Contains(ws[0].Args, "merge_result="+record.HeadChanged) ||
		!slices.Contains(ws[2].Args, "pr_head_sha="+other) {
		t.Fatalf("the writes landed out of order: %+v", ws)
	}
	b := d.row(t)
	if b.Status != "blocked" || b.Assignee != "" {
		t.Fatalf("the published bead is %s under %q", b.Status, b.Assignee)
	}
	meta(t, b, map[string]string{"pr_head_sha": other, "merge_result": record.Pending})
}

// A publication at a new head holds the lock across its two writes. An act
// that starts between them waits for the lock, reads the whole record,
// blocked and assigned to nobody, at the new head, and finds the saved read
// older than it, so it sends nothing back and merges nothing.
func TestAnActWaitsWhileARecordWriteHoldsTheLockThenDecidesOnTheWholeRecord(t *testing.T) {
	d := newLand(t)
	d.md["merge_result"], d.md["observed_pr_head_sha"] = record.HeadChanged, other
	delete(d.md, "pr_reconcile_pending")
	d.put("open", refinery)
	d.refresh(t)
	d.pr.Facts.HeadRefOid = other // the refinery validated a new head and pushed it
	d.co.descends[other] = []string{head}
	d.co.tip = other
	between, goOn := make(chan struct{}), make(chan struct{})
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 2 {
			close(between)
			<-goOn
		}
		return nil
	}
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(other)) }()
	<-between
	ran := make(chan error, 1)
	var out []pr.RunOutcome
	go func() { ran <- d.l.Reconcile(pr.Options{}, func(o pr.RunOutcome) { out = append(out, o) }) }()
	waits(t, ran, "the run")
	close(goOn)
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if len(out) != 1 || out[0].Action != pr.ActChecked || len(d.github.Asks()) != 0 {
		t.Fatalf("the run did %+v with asks %v, want the whole record at the new head, checked", out, asks(d.github))
	}
}

func TestADispositionsCloseWaitsWhileAnActHoldsTheLockAndClearsTheMarker(t *testing.T) {
	d := newLand(t)
	d.refresh(t)
	there, goOn := pause(d.github)
	ran := make(chan error, 1)
	go func() { ran <- d.l.Reconcile(pr.Options{}, func(pr.RunOutcome) {}) }()
	<-there
	disposed := make(chan error, 1)
	go func() { disposed <- dispose(d) }()
	waits(t, disposed, "the disposition")
	close(goOn)
	if err := <-ran; err != nil {
		t.Fatal(err)
	}
	if err := <-disposed; err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 3; i++ {
		if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
			t.Fatalf("a later run read the disposed bead: %+v", out)
		}
	}
	if b := d.row(t); b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the disposed bead is %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
}

func TestADispositionThatClosesBeforeAPublicationTakesTheLockLeavesNoRecord(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	if err := dispose(d); err != nil {
		t.Fatal(err)
	}
	err := d.l.Record(bead, publication(head))
	var refused *pr.Refusal
	if !errors.As(err, &refused) || refused.Armed {
		t.Fatalf("a publication on a disposed bead read as %v", err)
	}
	for i := 0; i < 2; i++ {
		if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
			t.Fatalf("a later run read the disposed bead: %+v", out)
		}
	}
	b := d.row(t)
	if b.Status != "closed" || len(b.Metadata) != 1 {
		t.Fatalf("the disposed bead is %s carrying %v", b.Status, b.Metadata)
	}
}

func TestACloseOrAReassignmentBetweenThePublicationsReadAndItsFirstWriteIsRefused(t *testing.T) {
	for name, move := range map[string]func(*fake.Bead){
		"a close":        func(b *fake.Bead) { b.Status = "closed" },
		"a reassignment": func(b *fake.Bead) { b.Assignee = "" },
	} {
		t.Run(name, func(t *testing.T) {
			d := newLand(t)
			d.md = map[string]string{"branch": branch}
			d.put("open", refinery)
			once := false
			d.store.BeforeUpdate = func(string, []string) error {
				if !once {
					once = true
					b, _ := d.store.Row(bead)
					move(&b)
					d.store.Put(b)
				}
				return nil
			}
			var refused *pr.Refusal
			if err := d.l.Record(bead, publication(head)); !errors.As(err, &refused) || refused.Armed {
				t.Fatalf("the publication read as %v", err)
			}
			if b := d.row(t); b.Metadata["pr_reconcile_pending"] != "" || b.Metadata["merge_result"] != "" {
				t.Fatalf("the guard let a write through: %v", b.Metadata)
			}
			if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
				t.Fatalf("a later run read the bead: %+v", out)
			}
		})
	}
}

func TestADispositionThatStartsBeforeAPublicationMarksTheBeadWaitsThenClearsTheMarker(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch}
	d.put("open", refinery)
	between, goOn := make(chan struct{}), make(chan struct{})
	n := 0
	d.store.BeforeUpdate = func(string, []string) error {
		if n++; n == 1 {
			close(between)
			<-goOn
		}
		return nil
	}
	recorded := make(chan error, 1)
	go func() { recorded <- d.l.Record(bead, publication(head)) }()
	<-between
	disposed := make(chan error, 1)
	go func() { disposed <- dispose(d) }()
	waits(t, disposed, "the disposition")
	close(goOn)
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	if err := <-disposed; err != nil {
		t.Fatal(err)
	}
	b := d.row(t)
	if b.Status != "closed" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the disposition left %s with marker %q", b.Status, b.Metadata["pr_reconcile_pending"])
	}
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a later run read the disposed bead: %+v", out)
	}
}

// A bead on the record assigned to someone other than the refinery is that
// assignee's while they work it: no run lists it, and a run that reads it
// assigned after its listing names who holds it. Neither writes anything to
// it, reads GitHub, requests a merge or pours a review run, and once the
// assignee is gone the next run works it as a waiting bead.
func TestABeadAssignedToAnotherIsLeftToItsAssignee(t *testing.T) {
	const holder = "rig/gc-toolkit.polecat-1"
	check := func(t *testing.T, d *land) {
		t.Helper()
		n, reads := len(d.store.Writes()), len(d.github.Reads())
		for i := 0; i < 2; i++ {
			if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
				t.Fatalf("a run took the held bead: %+v", out)
			}
		}
		b := d.row(t)
		if b.Status != "blocked" || b.Assignee != holder {
			t.Fatalf("the held bead is %s under %q", b.Status, b.Assignee)
		}
		meta(t, b, map[string]string{"pr_reconcile_pending": "true", "merge_result": record.Pending})
		if len(d.store.Writes()) != n || len(d.github.Reads()) != reads || len(d.github.Asks()) != 0 {
			t.Fatalf("the runs wrote %+v, read GitHub %v or asked for a merge %v", d.store.Writes()[n:],
				d.github.Reads()[reads:], asks(d.github))
		}
		d.put("blocked", "")
		is(t, d.once(t), pr.ActRequested)
	}
	t.Run("before a run lists it", func(t *testing.T) {
		d := newLand(t)
		d.put("blocked", holder)
		check(t, d)
	})
	t.Run("between a run's listing and its read", func(t *testing.T) {
		d := newLand(t)
		d.refresh(t)
		assigned := false
		d.store.OnFind = func(q gcbd.Query) {
			if !assigned && slices.Contains(q.IDs, bead) {
				assigned = true
				d.put("blocked", holder)
			}
		}
		o := d.run(t)
		is(t, o, pr.ActAssigned)
		if !strings.Contains(o.Detail, holder) {
			t.Fatalf("the outcome %q does not name who holds the bead", o.Detail)
		}
		if ws, reads := d.runWrites(), d.runReads(); len(ws) != 0 || len(reads) != 0 {
			t.Fatalf("the run wrote %+v or read GitHub %v", ws, reads)
		}
		d.store.OnFind = nil
		check(t, d)
	})
	t.Run("while the merge reads GitHub", func(t *testing.T) {
		d := newLand(t)
		d.refresh(t)
		d.github.OnRead = func(method string, _ *ghfake.PR) {
			if method == "PullRequest" {
				if b, _ := d.store.Row(bead); b.Assignee == "" {
					d.put("blocked", holder)
				}
			}
		}
		o := d.run(t)
		is(t, o, pr.ActChecked)
		if !strings.Contains(o.Detail, "assigned") || len(d.runWrites()) != 0 || len(d.github.Asks()) != 0 {
			t.Fatalf("a bead assigned during the merge's read did %q, wrote %+v and asked %v", o.Detail, d.runWrites(), asks(d.github))
		}
		d.github.OnRead = nil
		check(t, d)
	})
}

// A run reads the store as often whatever the number of records it decides:
// the marked records, every live bead, and in one read the closed beads their
// blocks edges name, such as a review run that ended, which the read of every
// live bead does not hold.
func TestARunsReadsDoNotGrowWithItsRecords(t *testing.T) {
	finds := func(n int) int {
		d := newLand(t)
		for i := range n {
			id, run := fmt.Sprintf("tk-w%d", i), fmt.Sprintf("tk-r%d", i)
			md := maps.Clone(d.md)
			md["branch"] = "polecat/" + id
			d.store.Put(fake.Bead{ID: run, Title: "a review run", Status: "closed"})
			d.store.Put(fake.Bead{ID: id, Title: "waiting work", Status: "blocked", Metadata: md,
				Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: run, Title: "a review run", Status: "closed"}}})
		}
		count := 0
		d.store.OnFind = func(gcbd.Query) { count++ }
		if out := d.reconcile(t, pr.Options{}); len(out) != n+1 {
			t.Fatalf("a run of %d records decided %+v", n+1, out)
		}
		return count
	}
	if one, five := finds(1), finds(4); one != five {
		t.Fatalf("a run of two records read the store %d times, and one of five %d", one, five)
	}
}

// Beads on the record that agents other than the refinery are assigned are
// left out of a run's pass, since a run writes nothing to them: each run
// decides the waiting bead beside them alone, and leaves the held beads as
// they were.
func TestBeadsAssignedToAnotherAreLeftOutOfARunsPass(t *testing.T) {
	const holder = "rig/gc-toolkit.polecat-1"
	d := newLand(t)
	var held []string
	for i := range 3 {
		id := fmt.Sprintf("tk-held%d", i)
		md := maps.Clone(d.md)
		md["branch"] = "polecat/" + id
		md["pr_url"] = fmt.Sprintf("https://github.com/%s/pull/%d", repo, 100+i)
		md["pr_number"] = fmt.Sprint(100 + i)
		d.store.Put(fake.Bead{ID: id, Title: "held work", Status: "blocked", Assignee: holder, Metadata: md})
		held = append(held, id)
	}
	n := len(d.store.Writes())
	for run := range 2 {
		out := d.reconcile(t, pr.Options{})
		if len(out) != 1 || out[0].Bead != bead {
			t.Fatalf("run %d decided %+v, want the waiting bead alone", run+1, out)
		}
	}
	for _, w := range d.store.Writes()[n:] {
		if slices.Contains(held, w.ID) {
			t.Fatalf("a run wrote to a held bead: %+v", w)
		}
	}
}

func TestASecondRunActsOnARecordOnlyOnceTheFirstHasWrittenIt(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	d.refresh(t)
	mark := len(d.store.Writes())
	there, goOn := pauseWrite(d.store)
	first, second := make(chan error, 1), make(chan error, 1)
	var firstOut, secondOut []pr.RunOutcome
	go func() {
		first <- d.l.Reconcile(pr.Options{}, func(o pr.RunOutcome) { firstOut = append(firstOut, o) })
	}()
	<-there
	// The watchdog closed the first run's tracking bead, and the next cooldown
	// started a second run while the first still holds the record.
	go func() {
		second <- d.l.Reconcile(pr.Options{}, func(o pr.RunOutcome) { secondOut = append(secondOut, o) })
	}()
	waits(t, second, "the second run")
	close(goOn)
	if err := <-first; err != nil {
		t.Fatal(err)
	}
	if err := <-second; err != nil {
		t.Fatal(err)
	}
	if len(firstOut) != 1 || firstOut[0].Action != pr.ActRequeued {
		t.Fatalf("the first run did %+v", firstOut)
	}
	if len(secondOut) != 1 || secondOut[0].Action != pr.ActSkipped {
		t.Fatalf("the second run did %+v, want it to read the record as the first left it, with no marker", secondOut)
	}
	if n := len(d.store.Writes()) - mark; n != 1 {
		t.Fatalf("%d writes, want the first run's one", n)
	}
}

// A run that read a half-written bead, before the refinery requeued it to the
// pool, writes nothing. The requeue's own write clears the marker, so no later
// run reads the bead, and it stays with the pool.
func TestARunThatReadAHalfWrittenBeadBeforeItsRequeueToThePoolWritesNothing(t *testing.T) {
	d := newLand(t)
	d.md = map[string]string{"branch": branch, "pr_reconcile_pending": "true", "existing_pr": prURL}
	d.put("open", refinery)
	d.refresh(t)
	once := false
	d.store.BeforeUpdate = func(string, []string) error {
		if !once {
			once = true
			// The refinery's requeue reopens it unassigned with its marker cleared.
			d.md = map[string]string{"branch": branch, "existing_pr": prURL, "rejection_reason": "test TestX fails"}
			d.put("open", "")
		}
		return nil
	}
	is(t, d.run(t), pr.ActMoved)
	b := d.row(t)
	if b.Metadata["merge_result"] != "" || b.Metadata["pr_reconcile_pending"] != "" {
		t.Fatalf("the refused write landed: %v", b.Metadata)
	}
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a later run read the requeued bead: %+v", out)
	}
	if b = d.row(t); b.Status != "open" || b.Assignee != "" {
		t.Fatalf("the requeued bead is %s under %q", b.Status, b.Assignee)
	}
}

// --- the lock ---------------------------------------------------------------

func TestTheLockWaitsForItsHolderAndGivesUpAtItsBound(t *testing.T) {
	dir := t.TempDir()
	release, err := record.Lock(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("a second writer got the lock or failed otherwise: %v", err)
	}
	got := make(chan error, 1)
	go func() {
		r, err := record.Lock(dir, 5*time.Second)
		if err == nil {
			r()
		}
		got <- err
	}()
	time.Sleep(100 * time.Millisecond)
	release()
	if err := <-got; err != nil {
		t.Fatalf("the waiting writer did not get the lock once it was free: %v", err)
	}
}

// An act whose lock does not come free inside its bound did not complete: it
// writes nothing, and the next run acts on the record.
func TestAnActWhoseLockDoesNotComeFreeIsActedOnByTheNextRun(t *testing.T) {
	d := newLand(t)
	d.pr.Facts.HeadRefOid = other
	d.refresh(t)
	release, err := record.Lock(d.l.Dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	out := d.reconcile(t, pr.Options{Stop: 200 * time.Millisecond})
	if len(out) != 1 || out[0].Action != pr.ActRetry || len(d.runWrites()) != 0 {
		t.Fatalf("an act behind a held lock did %+v and wrote %+v", out, d.runWrites())
	}
	release()
	is(t, d.run(t), pr.ActRequeued)
}

// A run that an order's time limit stops holds nothing: the kernel frees the
// lock when the run's process ends.
func TestARunStoppedAtItsTimeLimitLeavesTheLockFree(t *testing.T) {
	if dir := os.Getenv("GCTK_TEST_HOLD_RECORD_LOCK"); dir != "" {
		if _, err := record.Lock(dir, time.Second); err != nil {
			os.Exit(3)
		}
		fmt.Println("held")
		time.Sleep(time.Minute)
		os.Exit(0)
	}
	dir := t.TempDir()
	cmd := exec.Command(os.Args[0], "-test.run", "^TestARunStoppedAtItsTimeLimitLeavesTheLockFree$")
	cmd.Env = append(os.Environ(), "GCTK_TEST_HOLD_RECORD_LOCK="+dir)
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	if _, err := out.Read(buf); err != nil || string(buf) != "held" {
		t.Fatalf("the holder did not take the lock: %q %v", buf, err)
	}
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("the lock was free while its holder ran: %v", err)
	}
	_ = cmd.Process.Kill()
	_ = cmd.Wait()
	release, err := record.Lock(dir, 2*time.Second)
	if err != nil {
		t.Fatalf("the lock stayed held after its holder was stopped: %v", err)
	}
	release()
}

// bead-rehome.sh takes the same lock with flock(1), so the shell's lock and the
// verbs' exclude each other.
func TestTheShellsFlockAndTheRecordLockExcludeEachOther(t *testing.T) {
	flock, err := exec.LookPath("flock")
	if err != nil {
		t.Skip("flock(1) is not on PATH")
	}
	dir := t.TempDir()
	release, err := record.Lock(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	path := dir + "/" + record.LockFile
	if exec.Command(flock, "-n", path, "true").Run() == nil {
		t.Fatal("flock(1) took the lock while gctk held it")
	}
	release()
	if err := exec.Command(flock, "-n", path, "true").Run(); err != nil {
		t.Fatalf("flock(1) did not take the free lock: %v", err)
	}
	hold := exec.Command(flock, path, "sleep", "2")
	if err := hold.Start(); err != nil {
		t.Fatal(err)
	}
	defer hold.Wait()
	time.Sleep(300 * time.Millisecond)
	if _, err := record.Lock(dir, 100*time.Millisecond); !errors.Is(err, record.ErrLockWait) {
		t.Fatalf("gctk took the lock while flock(1) held it: %v", err)
	}
}
