package pr_test

import (
	"context"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"sync"
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

// The landing order admits the review run (specs/tk-1tfzr71.108/design.md,
// sections 1 and 7), each case one of section 12's for unit 4, on the landing
// order's world with no passed result at the validated head.

// boundRefinery is a refinery whose address names its rig and the binding the
// pack is imported under, which the review run's pools carry.
const boundRefinery = "rig/gc-toolkit.refinery"

// pours is the pour of a review run as gc formula cook --attach makes it: the
// root, which carries its formula, its vars and the meta written on it, and the
// bead's blocks edge onto it, which the store's blocked listing holds the bead
// on. err fails the pour. Its rank records the root it settles, runs onRank
// first when that is set, and answers rankErr.
type pours struct {
	mu      sync.Mutex
	store   *fake.Store
	vars    []map[string]string
	metas   []map[string]string
	ranked  []string
	err     error
	rankErr error
	onRank  func(ctx context.Context, root string)
}

func (p *pours) Pour(formula, b string, vars, meta map[string]string) (string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.err != nil {
		return "", p.err
	}
	p.vars = append(p.vars, maps.Clone(vars))
	p.metas = append(p.metas, maps.Clone(meta))
	root := fmt.Sprintf("tk-run%d", len(p.vars))
	md := map[string]string{"gc.kind": "workflow", "gc.formula_name": formula}
	for k, v := range vars {
		md["gc.var."+k] = v
	}
	maps.Copy(md, meta)
	p.store.Put(fake.Bead{ID: root, Title: formula, Status: "open", Metadata: md})
	row, _ := p.store.Row(b)
	row.Edges = append(row.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: root, Title: formula, Status: "open"})
	p.store.Put(row)
	p.store.List(b, root)
	return root, nil
}

func (p *pours) Rank(ctx context.Context, root string) error {
	if p.onRank != nil {
		p.onRank(ctx, root)
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	p.ranked = append(p.ranked, root)
	return p.rankErr
}

func (p *pours) count() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.vars)
}

func (p *pours) ranks() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return slices.Clone(p.ranked)
}

// admitting is the landing order's world with no review result at the
// validated head, a refinery whose address names its binding, and the pour.
type admitting struct {
	*land
	runs *pours
}

func newAdmit(t *testing.T) *admitting {
	t.Helper()
	d := newCycle(t)
	d.l.Refinery = boundRefinery
	d.edit(t, func(b *fake.Bead) { delete(b.Metadata, "review_results") })
	p := &pours{store: d.store}
	d.l.Runs = p
	return &admitting{land: d, runs: p}
}

// A review run's pour is the one call an act does not stop, since a cook
// stopped before it attaches its run leaves a run the order never reads, so an
// act starts it only while the pour's reserve of its bound is left. An act
// with less left pours nothing and fails no run, and the next run, whose act
// has its whole bound, pours it.
func TestAPourStartsOnlyWhileItsReserveIsLeft(t *testing.T) {
	d := newAdmit(t)
	d.refresh(t)
	out := d.reconcile(t, pr.Options{Stop: 5 * time.Second})
	if len(out) != 1 {
		t.Fatalf("one record, %d outcomes: %+v", len(out), out)
	}
	is(t, out[0], pr.ActLeft)
	if !strings.Contains(out[0].Detail, "reserves") || d.runs.count() != 0 {
		t.Fatalf("an act short of the reserve says %q and poured %d runs", out[0].Detail, d.runs.count())
	}
	is(t, d.run(t), pr.ActPoured)
	if n := d.runs.count(); n != 1 {
		t.Fatalf("the next run poured %d runs, want 1", n)
	}
}

// end closes the run, as a run's end closes its root, with the outcome given,
// and stops the blocked listing holding the bead on it.
func (d *admitting) end(t *testing.T, root, outcome, at string) {
	t.Helper()
	r, ok := d.store.Row(root)
	if !ok {
		t.Fatalf("no run %s", root)
	}
	r.Status, r.ClosedAt = "closed", at
	r.Metadata["gc.outcome"] = outcome
	d.store.Put(r)
	d.edit(t, func(b *fake.Bead) {
		for i := range b.Edges {
			if b.Edges[i].ID == root {
				b.Edges[i].Status, b.Edges[i].ClosedAt = "closed", at
			}
		}
	})
	d.store.Unlist(bead)
}

// gate files an open human gate on the bead under key, which the blocked
// listing holds the bead on.
func (d *admitting) gate(t *testing.T, id, key string) {
	t.Helper()
	d.store.Put(fake.Bead{ID: id, Title: "a gate keyed " + key, Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: key})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Title: "a gate keyed " + key, Status: "open", IssueType: "gate", AwaitType: "human"})
	})
	d.store.List(bead, id)
}

// clear closes the gate at at.
func (d *admitting) clear(t *testing.T, id, at string) {
	t.Helper()
	g, _ := d.store.Row(id)
	g.Status, g.ClosedAt = "closed", at
	d.store.Put(g)
	d.edit(t, func(b *fake.Bead) {
		for i := range b.Edges {
			if b.Edges[i].ID == id {
				b.Edges[i].Status, b.Edges[i].ClosedAt = "closed", at
			}
		}
	})
	d.store.Unlist(bead)
}

// ask files an ask on the bead, as gctk review ask does, which the blocked
// listing holds the bead on.
func (d *admitting) ask(t *testing.T, reason string) string {
	t.Helper()
	id, filed, err := review.FileAsk(ledger.New(d.store), review.AskRequest{Bead: bead, Reason: reason}, nil)
	if err != nil || !filed {
		t.Fatalf("the ask did not file: %v (filed %v)", err, filed)
	}
	d.store.List(bead, id)
	return id
}

func gated(d *admitting, key string) bool {
	return slices.Contains(d.gates.list(), bead+" "+key)
}

// A head the refinery validated with no review result gets one run, poured
// with the record's vars and the pools and binding the refinery's address
// names, and two runs of the order that overlap pour one between them.
func TestAHeadValidatedWithNoResultGetsOneRunUnderOverlappingPasses(t *testing.T) {
	d := newAdmit(t)
	o := d.once(t)
	is(t, o, pr.ActPoured)
	want := map[string]string{"pr_bead": bead, "head": head, "target": "main", "branch": branch,
		"review_target": "rig/gc-toolkit.polecat-codex", "repair_target": "rig/gc-toolkit.polecat", "binding_prefix": "gc-toolkit."}
	if got := d.runs.vars[0]; !maps.Equal(got, want) {
		t.Fatalf("the run was poured with %v, want %v", got, want)
	}
	savesNothingOfGitHub(t, d.land)
	is(t, d.once(t), pr.ActChecked)
	savesNothingOfGitHub(t, d.land)
	if n := d.runs.count(); n != 1 {
		t.Fatalf("the attached run did not keep the next run from pouring: %d runs", n)
	}

	e := newAdmit(t)
	e.refresh(t)
	var wg sync.WaitGroup
	for range 4 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var said []pr.RunOutcome
			if err := e.l.Reconcile(pr.Options{}, func(o pr.RunOutcome) { said = append(said, o) }); err != nil {
				t.Errorf("Reconcile: %v (%+v)", err, said)
			}
		}()
	}
	wg.Wait()
	if n := e.runs.count(); n != 1 {
		t.Fatalf("four overlapping runs of the order poured %d review runs, want one", n)
	}
}

// A review run is PR-finishing work of the bead that owns the PR
// (docs/steering.md), so its root is poured one level sooner than the bead,
// and the act settles the run's priority once it has freed the record lock,
// before its own bound ends, since the pour gave every bead of the run the
// bead's own priority. A later run, which finds the run attached, settles
// nothing.
func TestAPouredRunIsSettledAsPRFinishingWorkOnceTheLockIsFree(t *testing.T) {
	d := newAdmit(t)
	free, bounded := true, true
	d.runs.onRank = func(ctx context.Context, _ string) {
		if _, ok := ctx.Deadline(); !ok || ctx.Err() != nil {
			bounded = false
		}
		release, err := record.Lock(d.l.Dir, 0)
		if err != nil {
			free = false
			return
		}
		release()
	}
	d.refresh(t)
	out := d.reconcile(t, pr.Options{Stop: time.Minute})
	if len(out) != 1 {
		t.Fatalf("one record, %d outcomes: %+v", len(out), out)
	}
	is(t, out[0], pr.ActPoured)
	if got := d.runs.metas[0]; !maps.Equal(got, map[string]string{"priority_shift": "-1"}) {
		t.Fatalf("the run's root was poured with %v, want priority_shift -1", got)
	}
	if root, _ := d.store.Row("tk-run1"); root.Metadata["priority_shift"] != "-1" {
		t.Fatalf("the run's root carries priority_shift %q, want -1", root.Metadata["priority_shift"])
	}
	if got := d.runs.ranks(); !slices.Equal(got, []string{"tk-run1"}) {
		t.Fatalf("the run settled %v, want the run's root tk-run1", got)
	}
	if !free || !bounded {
		t.Fatalf("the settle ran with the record lock free: %v, and inside the act's bound: %v; want both", free, bounded)
	}
	if !strings.Contains(out[0].Detail, "; its priority settled") {
		t.Fatalf("the pour says %q", out[0].Detail)
	}
	is(t, d.once(t), pr.ActChecked)
	if n := len(d.runs.ranks()); n != 1 {
		t.Fatalf("the runs settled %d times in all, want 1", n)
	}
}

// A settle that fails leaves the run poured, since the act is done: the run
// waits at the bead's priority until the priority pass reaches it, which the
// outcome says, and the next run pours no second one. A pour that fails
// settles nothing.
func TestARunWhosePriorityDoesNotSettleStaysPoured(t *testing.T) {
	d := newAdmit(t)
	d.runs.rankErr = errors.New("queue-priority.sh settle tk-run1: exit 1: could not take the priority lock")
	o := d.once(t)
	is(t, o, pr.ActPoured)
	if !strings.Contains(o.Detail, "its priority did not settle") || !strings.Contains(o.Detail, "could not take the priority lock") {
		t.Fatalf("the pour whose settle failed says %q", o.Detail)
	}
	is(t, d.once(t), pr.ActChecked)
	if n := d.runs.count(); n != 1 {
		t.Fatalf("a settle that failed led to %d pours, want 1", n)
	}

	e := newAdmit(t)
	e.runs.err = errors.New("gc formula cook: exit 1: the store did not answer")
	is(t, e.once(t), pr.ActRetry)
	if got := e.runs.ranks(); len(got) != 0 {
		t.Fatalf("a pour that failed settled %v", got)
	}
}

// A run that ended without a result is poured again, and when the second at
// the same head ends without one too, the order asks a person through a
// review-run-failed gate naming both runs and how each ended, and pours none.
// A gate that does not file is filed by the next run.
func TestARunThatEndedWithoutAResultIsPouredAgainAndTheSecondFailureGetsTheGate(t *testing.T) {
	d := newAdmit(t)
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run1", "canceled", "2026-11-12T09:10:00Z")
	is(t, d.once(t), pr.ActPoured)
	if gated(d, "review-run-failed") {
		t.Fatal("the first failure asked a person")
	}
	d.end(t, "tk-run2", "canceled", "2026-11-12T09:20:00Z")
	d.gates.err = errors.New("human-gate: could not read the bead's gates")
	is(t, d.once(t), pr.ActRetry)
	savesNothingOfGitHub(t, d.land)
	d.gates.err = nil
	o := d.once(t)
	is(t, o, pr.ActExcepted)
	savesNothingOfGitHub(t, d.land)
	if !gated(d, "review-run-failed") || d.runs.count() != 2 {
		t.Fatalf("the second failure filed %v and poured %d runs, want the gate and two runs", d.gates.list(), d.runs.count())
	}
	msg := d.gates.messages[len(d.gates.messages)-1]
	for _, want := range []string{"tk-run1", "tk-run2", "cancelled", head} {
		if !strings.Contains(msg, want) {
			t.Errorf("the gate's message lacks %q: %s", want, msg)
		}
	}
	// The gate holds the bead, so the next run pours nothing.
	d.gate(t, "tk-g1", "review-run-failed")
	is(t, d.once(t), pr.ActChecked)
	if d.runs.count() != 2 {
		t.Fatal("the order poured a run while the review-run-failed gate held the bead")
	}
}

// A run whose loop exhausted recorded a result, so it counts as no failure:
// the run after it, at the same head, ending without a result is poured again.
func TestARunThatRecordedItsResultIsNoFailureOfTheReOffer(t *testing.T) {
	d := newAdmit(t)
	is(t, d.once(t), pr.ActPoured)
	recorded(t, d, "tk-run1")
	d.end(t, "tk-run1", "fail", "2026-11-12T09:10:00Z")
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run2", "canceled", "2026-11-12T09:20:00Z")
	is(t, d.once(t), pr.ActPoured)
	if gated(d, "review-run-failed") {
		t.Fatal("a run that recorded its result was counted as one that ended without one")
	}
}

// recorded writes what a run whose loop's check recorded its result leaves:
// the steps of a run that judged the head and exhausted its loop (judged), and
// the entry the check wrote for that head and target, naming the run.
func recorded(t *testing.T, d *admitting, root string) {
	t.Helper()
	judged(t, d, root)
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["review_results"] = `[{"head":"` + head + `","target":"main","passed":false,"run":"` + root + `"}]`
	})
}

// judged writes the steps of a run that judged the head and exhausted its
// loop, whose bound the root carries as Gas City's cook stamps every var.
func judged(t *testing.T, d *admitting, root string) {
	t.Helper()
	r, ok := d.store.Row(root)
	if !ok {
		t.Fatalf("no run %s", root)
	}
	r.Metadata["gc.var.max_attempts"] = "1"
	d.store.Put(r)
	member := func(id, kind, ref, outcome, output string) {
		md := map[string]string{"gc.root_bead_id": root, "gc.step_ref": ref, "gc.outcome": outcome}
		if kind != "" {
			md["gc.kind"] = kind
		}
		if output != "" {
			md["gc.output_json"] = output
		}
		d.store.Put(fake.Bead{ID: id, Title: ref, Status: "closed", Metadata: md})
	}
	member(root+"-loop", "ralph", "mol-pr-review.review-loop", "fail", "")
	member(root+"-triage", "", "review-loop.iteration.1.triage", "pass",
		`{"review":"triage","iteration":1,"head":"`+head+`","checks":[],"material":false}`)
}

// A run whose loop closed exhausted at the head with no entry of its own for
// that head, as when Gas City spends a check's infrastructure budget on a
// record that keeps failing and grades the last re-run an ordinary failure,
// ended without a result: two such runs at the head get the review-run-failed
// gate, whose message says the record never landed.
func TestARunWhoseRecordNeverLandedEndedWithoutAResult(t *testing.T) {
	d := newAdmit(t)
	is(t, d.once(t), pr.ActPoured)
	judged(t, d, "tk-run1")
	d.end(t, "tk-run1", "fail", "2026-11-12T09:10:00Z")
	is(t, d.once(t), pr.ActPoured)
	judged(t, d, "tk-run2")
	d.end(t, "tk-run2", "fail", "2026-11-12T09:20:00Z")
	is(t, d.once(t), pr.ActExcepted)
	if !gated(d, "review-run-failed") || d.runs.count() != 2 {
		t.Fatalf("two runs whose records never landed filed %v and poured %d runs, want the gate and two runs", d.gates.list(), d.runs.count())
	}
	if msg := d.gates.messages[len(d.gates.messages)-1]; !strings.Contains(msg, "record never landed") {
		t.Fatalf("the gate's message does not say the record never landed: %s", msg)
	}
}

// A cleared review-run-failed or review-loop-exhausted gate gets one more run:
// the runs that ended before the review-run-failed gate closed are not counted
// again, and a run that fails after it is poured again once.
func TestAClearedRunFailedOrLoopExhaustedGateGetsOneMoreRun(t *testing.T) {
	d := newAdmit(t)
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run1", "canceled", "2026-11-12T09:10:00Z")
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run2", "canceled", "2026-11-12T09:20:00Z")
	is(t, d.once(t), pr.ActExcepted)
	d.gate(t, "tk-g1", "review-run-failed")
	d.clear(t, "tk-g1", "2026-11-12T09:30:00Z")
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run3", "canceled", "2026-11-12T09:40:00Z")
	is(t, d.once(t), pr.ActPoured)
	if n := len(d.gates.list()); n != 1 {
		t.Fatalf("one failure after the gate cleared asked a person again: %v", d.gates.list())
	}

	e := newAdmit(t)
	is(t, e.once(t), pr.ActPoured)
	recorded(t, e, "tk-run1")
	e.end(t, "tk-run1", "fail", "2026-11-12T09:10:00Z")
	e.gate(t, "tk-g2", "review-loop-exhausted")
	is(t, e.once(t), pr.ActChecked)
	e.clear(t, "tk-g2", "2026-11-12T09:30:00Z")
	is(t, e.once(t), pr.ActPoured)
}

// An open human gate on the bead keeps the order from pouring until it
// closes, and so does an open rework child on the branch, assigned or, as a
// fix unit whose workflow Gas City's sling started, unassigned with its
// execution route while its steps are claimed.
func TestAGateOrAnotherWriterKeepsTheRunOffTheBranch(t *testing.T) {
	d := newAdmit(t)
	d.gate(t, "tk-q1", "review-question-scope")
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if d.runs.count() != 0 || !strings.Contains(o.Detail, "tk-q1") {
		t.Fatalf("an open human gate let the order pour: %d runs (%s)", d.runs.count(), o.Detail)
	}
	d.clear(t, "tk-q1", "2026-11-12T09:30:00Z")
	is(t, d.once(t), pr.ActPoured)

	f := newAdmit(t)
	f.store.Put(fake.Bead{ID: "tk-kid", Title: "Rework the branch", Status: "in_progress", IssueType: "task",
		Assignee: "rig/gc-toolkit.polecat-1", Metadata: map[string]string{"branch": branch, "task_kind": "rework"}})
	o = f.once(t)
	is(t, o, pr.ActChecked)
	if f.runs.count() != 0 || !strings.Contains(o.Detail, "tk-kid") {
		t.Fatalf("a rework child on the branch let the order pour: %d runs (%s)", f.runs.count(), o.Detail)
	}

	g := newAdmit(t)
	g.store.Put(fake.Bead{ID: "tk-fix", Title: "Rework PR#1: address signoff findings", Status: "open", IssueType: "task",
		Metadata: map[string]string{"branch": branch, "task_kind": "rework", "anchor_bead": bead,
			"gc.routed_to": "", "gc.execution_routed_to": "rig/gc-toolkit.polecat"}})
	g.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-fix", Status: "open"})
	})
	g.store.List(bead, "tk-fix")
	o = g.once(t)
	is(t, o, pr.ActChecked)
	if g.runs.count() != 0 || !strings.Contains(o.Detail, "tk-fix works") {
		t.Fatalf("a fix unit whose workflow the sling started let the order pour: %d runs (%s)", g.runs.count(), o.Detail)
	}
}

// conversation files conversation tk-conv on the PR, a task that tracks the
// bead, with status and assignee as given, and the bead's blocks edge onto it,
// the edge that holds the PR's merge, which the blocked listing holds the bead
// on. wait is the status of the work a stay leaves the conversation waiting
// on, and "" files none.
func (d *admitting) conversation(t *testing.T, status, assignee, wait string) {
	t.Helper()
	c := fake.Bead{ID: "tk-conv", Title: "Converse about the PR", Status: status, IssueType: "task", Assignee: assignee,
		Edges: []gcbd.Edge{{Type: "tracks", ID: bead, Title: "the work", Status: "blocked"}}}
	if wait != "" {
		w := fake.Bead{ID: "tk-work", Title: "The work the ruling sent", Status: wait, IssueType: "task"}
		if wait == "closed" {
			w.ClosedAt = "2026-11-12T09:30:00Z"
		}
		d.store.Put(w)
		c.Edges = append(c.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-work", Title: w.Title, Status: wait, IssueType: "task", ClosedAt: w.ClosedAt})
		if wait != "closed" {
			d.store.List("tk-conv", "tk-work")
		}
	}
	d.store.Put(c)
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-conv", Title: c.Title, Status: status, IssueType: "task"})
	})
	d.store.List(bead, "tk-conv")
}

// A conversation on the PR holds its merge and nothing else, so the order
// pours the run as it would with no conversation, whether the conversation
// waits in the operator's queue, a sitting holds it, its sitting stays for the
// work it sent, or its sitting has come back from that stay.
func TestAConversationKeepsNoRunOffTheBranch(t *testing.T) {
	for _, c := range []struct{ name, status, assignee, wait string }{
		{"in the operator's queue", "open", "human", ""},
		{"held by a sitting", "in_progress", "rig/gc-toolkit.tk-conv", ""},
		{"whose sitting stays", "open", "rig/gc-toolkit.tk-conv", "open"},
		{"whose sitting came back from its stay", "open", "rig/gc-toolkit.tk-conv", "closed"},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newAdmit(t)
			d.conversation(t, c.status, c.assignee, c.wait)
			o := d.once(t)
			is(t, o, pr.ActPoured)
			if d.runs.count() != 1 {
				t.Fatalf("a conversation %s kept the run off the branch: %d runs (%s)", c.name, d.runs.count(), o.Detail)
			}
		})
	}
}

// A conversation holds the PR's merge until it closes: at a head a run passed,
// the order asks GitHub for no merge while the conversation is open, and pours
// no run, since the head needs none, then requests the merge once the
// conversation closes.
func TestAConversationHoldsTheMergeUntilItCloses(t *testing.T) {
	merges := func(x ghfake.Ask) bool { return x.Method == "MergePullRequest" || x.Method == "EnqueuePullRequest" }
	for _, c := range []struct{ name, status, assignee string }{
		{"in the operator's queue", "open", "human"},
		{"held by a sitting", "in_progress", "rig/gc-toolkit.tk-conv"},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newAdmit(t)
			d.edit(t, func(b *fake.Bead) {
				b.Metadata["review_results"] = `[{"head":"` + head + `","target":"main","passed":true,"run":"tk-run0"}]`
			})
			d.conversation(t, c.status, c.assignee, "")
			o := d.once(t)
			is(t, o, pr.ActChecked)
			if d.runs.count() != 0 || o.Detail != "not ready: wait" {
				t.Fatalf("a passed head with a conversation %s was not held on its wait: %d runs (%s)", c.name, d.runs.count(), o.Detail)
			}
			if slices.ContainsFunc(d.github.Asks(), merges) {
				t.Fatalf("a conversation %s let the merge be requested: %v", c.name, asks(d.github))
			}
			d.clear(t, "tk-conv", "2026-11-12T09:30:00Z")
			is(t, d.once(t), pr.ActRequested)
		})
	}
}

// An ask on a head that already passed starts a round: the order pours a run
// for it, and marks no draft ready while it is open.
func TestAnAskOnAPassedHeadStartsARound(t *testing.T) {
	d := newAdmit(t)
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["review_results"] = `[{"head":"` + head + `","target":"main","passed":true}]`
	})
	d.pr.Facts.IsDraft = true
	a := d.ask(t, "Rename the flag, as the operator ruled.")
	o := d.once(t)
	is(t, o, pr.ActPoured)
	if !strings.Contains(o.Detail, a) {
		t.Fatalf("the pour does not name the ask it is for: %s", o.Detail)
	}
	if slices.ContainsFunc(d.github.Asks(), func(x ghfake.Ask) bool { return x.Method == "MarkReady" }) {
		t.Fatalf("a draft with an open ask was marked ready: %v", asks(d.github))
	}
}

// A PR that is no draft, recorded pending at a head a run passed, has its
// merge requested, but not while an ask is open on its bead, as one the
// refinery files before it records a head it sends back: the order pours the
// run that takes the ask, and asks GitHub for no merge.
func TestAnOpenAskHoldsTheMergeOfAPassedHead(t *testing.T) {
	passed := `[{"head":"` + head + `","target":"main","passed":true,"run":"tk-run0"}]`
	d := newAdmit(t)
	d.edit(t, func(b *fake.Bead) { b.Metadata["review_results"] = passed })
	is(t, d.once(t), pr.ActRequested)

	e := newAdmit(t)
	e.edit(t, func(b *fake.Bead) { b.Metadata["review_results"] = passed })
	a := e.ask(t, "The refinery sent "+head+" back:\ntest TestX fails")
	o := e.once(t)
	is(t, o, pr.ActPoured)
	if !strings.Contains(o.Detail, a) {
		t.Fatalf("the pour does not name the ask it is for: %s", o.Detail)
	}
	if slices.ContainsFunc(e.github.Asks(), func(x ghfake.Ask) bool {
		return x.Method == "MergePullRequest" || x.Method == "EnqueuePullRequest"
	}) {
		t.Fatalf("a passed head with an open ask had its merge requested: %v", asks(e.github))
	}
}

// A draft with an open ask that nothing holds is not marked ready, even while
// a run is attached; once the ask closes and the run has ended, it is.
func TestADraftWithAnOpenAskThatNothingHoldsIsNotMarkedReady(t *testing.T) {
	d := newAdmit(t)
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["review_results"] = `[{"head":"` + head + `","target":"main","passed":true}]`
	})
	d.pr.Facts.IsDraft = true
	a := d.ask(t, "Answer the reviewer's comment on the flag.")
	d.runs.err = errors.New("gc formula cook: exit 1: the store did not answer")
	is(t, d.once(t), pr.ActRetry)
	savesNothingOfGitHub(t, d.land)
	if slices.ContainsFunc(d.github.Asks(), func(x ghfake.Ask) bool { return x.Method == "MarkReady" }) {
		t.Fatalf("a draft with an open ask that nothing holds was marked ready: %v", asks(d.github))
	}
	r, _ := d.store.Row(a)
	r.Status, r.ClosedAt = "closed", "2026-11-12T09:30:00Z"
	d.store.Put(r)
	d.store.Unlist(bead)
	is(t, d.once(t), pr.ActReadied)
}

// listOnItsWaits has the blocked listing hold the bead on each bead its own
// blocks edges name that has not closed, and leave it out when none is open,
// as the store's blocked rule does, so the listing holds an ask only on a wait
// its create wrote.
func (d *admitting) listOnItsWaits(t *testing.T, id string) {
	t.Helper()
	r, ok := d.store.Row(id)
	if !ok {
		t.Fatalf("no bead %s", id)
	}
	var on []string
	for _, e := range r.Edges {
		if far, ok := d.store.Row(e.ID); ok && e.Type == gcbd.EdgeBlocks && far.Status != "closed" {
			on = append(on, e.ID)
		}
	}
	if len(on) == 0 {
		d.store.Unlist(id)
		return
	}
	d.store.List(id, on...)
}

// An ask filed to wait on an open bead, as a send-back that waits for another
// PR is, on a head that passed, pours no run, files no gate and leaves the
// head's passed result, because its create wrote the wait. The pass after that
// bead closes pours one run, which can take it.
func TestAnAskFiledToWaitOnAnOpenBeadGetsNoRunUntilThatBeadCloses(t *testing.T) {
	d := newAdmit(t)
	passed := `[{"head":"` + head + `","target":"main","passed":true}]`
	d.edit(t, func(b *fake.Bead) { b.Metadata["review_results"] = passed })
	d.store.Put(fake.Bead{ID: "tk-other", Title: "the other PR's work", Status: "open"})
	a, filed, err := review.FileAsk(ledger.New(d.store), review.AskRequest{Bead: bead,
		Reason: "Apply the ruling once the other PR lands.", WaitingOn: []string{"tk-other"}}, nil)
	if err != nil || !filed {
		t.Fatalf("the ask did not file: %v (filed %v)", err, filed)
	}
	d.store.List(bead, a)
	d.listOnItsWaits(t, a)
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if d.runs.count() != 0 || len(d.gates.list()) != 0 || d.row(t).Metadata["review_results"] != passed {
		t.Fatalf("a held ask poured %d runs, filed %v, or moved the result to %q (%s)",
			d.runs.count(), d.gates.list(), d.row(t).Metadata["review_results"], o.Detail)
	}
	other, _ := d.store.Row("tk-other")
	other.Status, other.ClosedAt = "closed", "2026-11-12T09:30:00Z"
	d.store.Put(other)
	r, _ := d.store.Row(a)
	for i := range r.Edges {
		if r.Edges[i].ID == "tk-other" {
			r.Edges[i].Status, r.Edges[i].ClosedAt = "closed", other.ClosedAt
		}
	}
	d.store.Put(r)
	d.listOnItsWaits(t, a)
	o = d.once(t)
	is(t, o, pr.ActPoured)
	if !strings.Contains(o.Detail, a) || d.runs.count() != 1 {
		t.Fatalf("the pass after tk-other closed poured %d runs (%s)", d.runs.count(), o.Detail)
	}
	got, err := review.AsksOn(ledger.New(d.store), bead)
	if err != nil || len(got) != 1 || !got[0].Takeable() {
		t.Fatalf("the ask does not read as one the run can take: %+v, %v", got, err)
	}
}

// A refinery whose address names no binding pours nothing, since the run's
// steps name the pack's scripts by it, and neither does a landing with no
// pourer. The pour the record is owed did not happen, so each run decides it
// again.
func TestARefineryAddressWithNoBindingPoursNothing(t *testing.T) {
	d := newAdmit(t)
	d.l.Refinery = refinery
	o := d.once(t)
	is(t, o, pr.ActRetry)
	if d.runs.count() != 0 || !strings.Contains(o.Detail, "rig/refinery") {
		t.Fatalf("a refinery with no binding poured %d runs (%s)", d.runs.count(), o.Detail)
	}
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a pour the run could not make wrote %+v", ws)
	}
	is(t, d.run(t), pr.ActRetry)

	e := newAdmit(t)
	e.l.Runs = nil
	is(t, e.once(t), pr.ActRetry)
	is(t, e.run(t), pr.ActRetry)
}

// A read admission makes that does not answer is a retry, and the next run
// decides the record again: here the read of how the earlier runs at the head
// ended, failed in the run's pass and again under the record lock, then the read
// of the beads on the branch, which the act makes under the lock, failed once.
func TestAnAdmissionReadThatDoesNotAnswerIsDecidedAgainByTheNextRun(t *testing.T) {
	d := newAdmit(t)
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run1", "canceled", "2026-11-12T09:10:00Z")
	is(t, d.once(t), pr.ActPoured)
	d.end(t, "tk-run2", "fail", "2026-11-12T09:20:00Z")
	ends := 0
	d.store.OnFind = func(q gcbd.Query) {
		d.store.FindErr = nil
		if q.Key == "gc.root_bead_id" {
			if ends++; ends <= 2 {
				d.store.FindErr = errors.New("the store did not answer")
			}
		}
	}
	o := d.run(t)
	is(t, o, pr.ActRetry)
	if !strings.Contains(o.Detail, "earlier runs ended did not read") {
		t.Fatalf("the failed read of the runs' ends says %q", o.Detail)
	}
	if ws := d.runWrites(); len(ws) != 0 {
		t.Fatalf("a decision the failed read left unmade wrote %+v", ws)
	}
	is(t, d.run(t), pr.ActExcepted)
	if !gated(d, "review-run-failed") {
		t.Fatalf("the run after the failed read filed %v, want the review-run-failed gate", d.gates.list())
	}

	e := newAdmit(t)
	e.refresh(t)
	// Admission reads the beads on the branch under the record lock, through the
	// act's own pass of the store.
	e.store.OnFind = failOnce(e.land, func(q gcbd.Query) bool { return q.Key == "branch" })
	o = e.run(t)
	is(t, o, pr.ActRetry)
	if !strings.Contains(o.Detail, "the beads on "+branch+" did not read") {
		t.Fatalf("the failed read of the branch's beads says %q", o.Detail)
	}
	if ws := e.runWrites(); len(ws) != 0 {
		t.Fatalf("a decision the failed read left unmade wrote %+v", ws)
	}
	is(t, e.run(t), pr.ActPoured)
}

// failOnce fails the first find of the store fails picks, and no other.
func failOnce(d *land, fails func(gcbd.Query) bool) func(gcbd.Query) {
	failed := false
	return func(q gcbd.Query) {
		d.store.FindErr = nil
		if !failed && fails(q) {
			failed, d.store.FindErr = true, errors.New("the store did not answer")
		}
	}
}
