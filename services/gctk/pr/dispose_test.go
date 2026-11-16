package pr_test

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// A ruling that a PR on the pending record will not land records its
// disposition on the bead that owns the PR and then closes the PR
// (pr-dispose.sh). The landing order never merges such a PR, and once it has
// closed the order hands the bead's close to the disposition writer.

// conversation is the bead the cases name as a not-needed disposition's
// successor: the conversation of the sitting that ruled.
const conversation = "tk-conv"

// rehome is the disposition writer as a test sets it. It records each close it
// is asked for, holds one while held says why, fails one while err is set, and
// otherwise closes the bead and clears the marker, as bead-rehome.sh's close
// does.
type rehome struct {
	mu    sync.Mutex
	store *fake.Store
	calls []string
	notes []string
	held  string
	err   error
}

func (r *rehome) Close(b string, d pr.Disposition, note string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, strings.TrimSpace(fmt.Sprintf("%s %s %s %s", b, d.Kind, d.Successor, d.Store)))
	r.notes = append(r.notes, note)
	switch {
	case r.err != nil:
		return r.err
	case r.held != "":
		return &pr.HeldClose{Why: r.held}
	}
	row, ok := r.store.Row(b)
	if !ok {
		return errors.New("no such bead")
	}
	row.Status = "closed"
	delete(row.Metadata, "pr_reconcile_pending")
	r.store.Put(row)
	return nil
}

func (r *rehome) asked() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.calls)
}

// retired is the landing order's world with a disposition a ruling recorded on
// the bead, not-needed onto the sitting's conversation, and the writer.
func retired(t *testing.T) (*land, *rehome) {
	t.Helper()
	d := newCycle(t)
	r := &rehome{store: d.store}
	d.l.Dispositions = r
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["gc.pr_close_disposition_kind"] = "not-needed"
		b.Metadata["gc.pr_close_disposition_successor"] = conversation
	})
	return d, r
}

// A retired PR still open is never merged, whatever the evaluator would say of
// it, and its bead waits for the PR's close with its marker kept.
func TestARetiredPRStillOpenIsNeverMerged(t *testing.T) {
	d, r := retired(t)
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "no merge is requested") {
		t.Fatalf("the check says %q", o.Detail)
	}
	if a := asks(d.github); len(a) != 0 {
		t.Fatalf("a retired PR was asked of GitHub: %v", a)
	}
	b := d.row(t)
	if b.Status != "blocked" || len(r.asked()) != 0 {
		t.Fatalf("an open retired PR left the bead %s and asked the writer %v", b.Status, r.asked())
	}
	meta(t, b, map[string]string{"pr_state": "open", "pr_reconcile_pending": "true", "merge_result": record.Pending})
}

// Once the retired PR has closed, the bead goes to the disposition writer under
// the ruling's kind and successor, with no gate filed, and once it has closed
// no later run reads it.
func TestARetiredPRThatClosedGoesToTheDispositionWriter(t *testing.T) {
	d, r := retired(t)
	d.edit(t, func(b *fake.Bead) { b.Metadata["gc.pr_close_disposition_successor_store"] = "rig:gc-toolkit" })
	d.pr.Facts.State = "CLOSED"
	o := d.once(t)
	is(t, o, pr.ActDisposed)
	if want := []string{bead + " not-needed " + conversation + " rig:gc-toolkit"}; !slices.Equal(r.asked(), want) {
		t.Fatalf("the writer was asked %v, want %v", r.asked(), want)
	}
	if !strings.Contains(r.notes[0], "PR #7 closed") {
		t.Fatalf("the close's note is %q", r.notes[0])
	}
	if g := d.gates.list(); len(g) != 0 {
		t.Fatalf("a retired PR's close filed gates %v", g)
	}
	if b := d.row(t); b.Status != "closed" {
		t.Fatalf("the writer's close left the bead %s", b.Status)
	}
	if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
		t.Fatalf("a later run read a disposed bead: %+v", out)
	}
}

// The order records the closed PR under the lock before it hands the close on,
// and the writer runs once the lock is free: a writer that waited for the lock
// would never get it.
func TestTheDispositionWriterRunsWithTheRecordLockFree(t *testing.T) {
	d, _ := retired(t)
	d.pr.Facts.State = "CLOSED"
	free := false
	d.l.Dispositions = closeFunc(func() error {
		release, err := record.Lock(d.l.Dir, 0)
		if err == nil {
			free = true
			release()
		}
		return nil
	})
	is(t, d.once(t), pr.ActDisposed)
	if !free {
		t.Fatal("the writer ran while the run held the record lock")
	}
	meta(t, d.row(t), map[string]string{"pr_state": "closed"})
}

// closeFunc is a disposition writer that runs a function.
type closeFunc func() error

func (f closeFunc) Close(string, pr.Disposition, string) error { return f() }

// A close the writer holds for now, as the ruling's open conversation holds it,
// leaves the bead blocked with its marker, and the next run tries it again.
func TestAHeldDispositionCloseIsTriedAgainByTheNextRun(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	r.held = "held by the open conversation " + conversation
	o := d.once(t)
	is(t, o, pr.ActRetry)
	if !strings.Contains(o.Detail, r.held) {
		t.Fatalf("the retry says %q", o.Detail)
	}
	b := d.row(t)
	if b.Status != "blocked" {
		t.Fatalf("a held close left the bead %s", b.Status)
	}
	meta(t, b, map[string]string{"pr_state": "closed", "pr_reconcile_pending": "true", "merge_result": record.Pending})
	r.held = ""
	is(t, d.once(t), pr.ActDisposed)
	if n := len(r.asked()); n != 2 {
		t.Fatalf("the writer was asked %d times, want 2", n)
	}
}

// A writer that did not answer is a failed record, which fails the run.
func TestADispositionWriterThatDidNotAnswerFailsTheRun(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	r.err = errors.New("bead-rehome.sh: exit 3: successor tk-conv does not exist")
	var out []pr.RunOutcome
	err := d.l.Reconcile(pr.Options{Count: 10}, func(o pr.RunOutcome) { out = append(out, o) })
	if err == nil || len(out) != 1 {
		t.Fatalf("Reconcile: %v, outcomes %+v", err, out)
	}
	is(t, out[0], pr.ActFailed)
	if !strings.Contains(out[0].Detail, "does not exist") {
		t.Fatalf("the failure says %q", out[0].Detail)
	}
}

// A changed head the order sent back to the refinery carries no marker, and the
// order reads it all the same once a ruling's disposition is on it, so its
// close reaches the writer. With no disposition the order does not read it.
func TestARetiredChangedHeadIsReadWithoutItsMarker(t *testing.T) {
	d, r := retired(t)
	d.edit(t, func(b *fake.Bead) {
		b.Status = "open"
		b.Metadata["merge_result"] = record.HeadChanged
		b.Metadata["observed_pr_head_sha"] = other
		delete(b.Metadata, "pr_reconcile_pending")
	})
	d.pr.Facts.State, d.pr.Facts.HeadRefOid = "CLOSED", other
	is(t, d.once(t), pr.ActDisposed)
	if want := []string{bead + " not-needed " + conversation}; !slices.Equal(r.asked(), want) {
		t.Fatalf("the writer was asked %v, want %v", r.asked(), want)
	}

	e, _ := retired(t)
	e.edit(t, func(b *fake.Bead) {
		b.Status = "open"
		b.Metadata["merge_result"] = record.HeadChanged
		delete(b.Metadata, "pr_reconcile_pending")
		delete(b.Metadata, "gc.pr_close_disposition_kind")
	})
	if out := e.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
		t.Fatalf("a changed head with no marker and no whole disposition was read: %+v", out)
	}
}

// The order reads a disposition only on a bead the refinery holds on the
// record: one a release took, or one whose disposition is not whole, is not
// read for it.
func TestADispositionIsReadOnlyOnTheRefinerysBeadOnTheRecord(t *testing.T) {
	for name, change := range map[string]func(*fake.Bead){
		"released":     func(b *fake.Bead) { b.Assignee = "rig/gc-toolkit.polecat-1" },
		"no successor": func(b *fake.Bead) { delete(b.Metadata, "gc.pr_close_disposition_successor") },
		"unknown kind": func(b *fake.Bead) { b.Metadata["gc.pr_close_disposition_kind"] = "abandoned" },
		"off the record": func(b *fake.Bead) {
			b.Metadata["merge_result"] = "pull_request"
		},
	} {
		t.Run(name, func(t *testing.T) {
			d, r := retired(t)
			d.edit(t, func(b *fake.Bead) {
				b.Status = "open"
				delete(b.Metadata, "pr_reconcile_pending")
				change(b)
			})
			d.pr.Facts.State = "CLOSED"
			if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 || len(r.asked()) != 0 {
				t.Fatalf("the order read it: %+v, and asked the writer %v", out, r.asked())
			}
		})
	}
}

// rulingHub is GitHub while a ruling lands: rule records the ruling's
// disposition on the bead as the run reads the PR, after the run read the bead.
type rulingHub struct {
	pr.Hub
	rule func()
}

func (h rulingHub) PullRequest(repo string, number int) (*gh.PullRequest, error) {
	h.rule()
	return h.Hub.PullRequest(repo, number)
}

// A ruling records its disposition without the record lock and then closes the
// PR, so a run that read the bead before the disposition landed can read the
// PR the ruling closed. The run reads the bead again before it calls the close
// the record's exception, and the bead goes to the disposition writer with no
// gate filed, blocked on the record or a changed head the order sent back
// behind a withdrawal.
func TestAPRClosedByARulingAfterTheRunReadTheBeadIsRetired(t *testing.T) {
	for name, setup := range map[string]func(*testing.T, *land){
		"blocked on the record": func(*testing.T, *land) {},
		"a changed head behind a withdrawal": func(t *testing.T, d *land) {
			d.pr.Facts.HeadRefOid = later
			d.edit(t, func(b *fake.Bead) {
				b.Status = "open"
				b.Metadata["merge_result"] = record.HeadChanged
				b.Metadata["observed_pr_head_sha"] = later
			})
			d.withdraw(t, later)
		},
	} {
		t.Run(name, func(t *testing.T) {
			d := newCycle(t)
			r := &rehome{store: d.store}
			d.l.Dispositions = r
			setup(t, d)
			d.pr.Facts.State = "CLOSED"
			hub := d.l.Hub
			d.l.Hub = func(host string) pr.Hub {
				return rulingHub{Hub: hub(host), rule: func() {
					d.edit(t, func(b *fake.Bead) {
						b.Metadata["gc.pr_close_disposition_kind"] = "not-needed"
						b.Metadata["gc.pr_close_disposition_successor"] = conversation
					})
				}}
			}
			is(t, d.once(t), pr.ActDisposed)
			if g := d.gates.list(); len(g) != 0 {
				t.Fatalf("a ruling's close the run read late filed gates %v", g)
			}
			if want := []string{bead + " not-needed " + conversation}; !slices.Equal(r.asked(), want) {
				t.Fatalf("the writer was asked %v, want %v", r.asked(), want)
			}
		})
	}
}

// A marked bead whose disposition is not whole is no retired PR: its closed PR
// is the record's exception, as one closed with no ruling is.
func TestAClosedPRWhoseDispositionIsNotWholeStaysBlockedBehindAGate(t *testing.T) {
	d, r := retired(t)
	d.edit(t, func(b *fake.Bead) { b.Metadata["gc.pr_close_disposition_kind"] = "abandoned" })
	d.pr.Facts.State = "CLOSED"
	is(t, d.once(t), pr.ActExcepted)
	if !slices.Equal(d.gates.list(), []string{bead + " " + record.ClosedUnmerged}) || len(r.asked()) != 0 {
		t.Fatalf("gates %v, writer asked %v", d.gates.list(), r.asked())
	}
}

// A review run attached to the bead keeps working the branch until it ends,
// so the bead's close waits for it, and goes to the writer once it has ended.
func TestARetiredPRsCloseWaitsForAnAttachedReviewRun(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	d.store.Put(fake.Bead{ID: "tk-run", Title: "mol-pr-review", Status: "in_progress",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review"}})
	d.edit(t, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: "tk-run", Status: "in_progress"})
	})
	d.store.List(bead, "tk-run")
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "tk-run") || len(r.asked()) != 0 {
		t.Fatalf("with a run attached the check says %q and asked the writer %v", o.Detail, r.asked())
	}
	d.store.Put(fake.Bead{ID: "tk-run", Title: "mol-pr-review", Status: "closed",
		Metadata: map[string]string{"gc.kind": "workflow", "gc.formula_name": "mol-pr-review"}})
	d.store.Unlist(bead)
	is(t, d.once(t), pr.ActDisposed)
}

// The asks and the withdrawals still open on the bead are closed once the PR
// has closed, each with a no-op work record and a note saying why, since no
// run takes an ask and no withdrawal is carried out on a closed PR, and both
// would hold the bead's close.
func TestARetiredPRsAsksAndWithdrawalsCloseWithIt(t *testing.T) {
	d, r := retired(t)
	d.store.WorkRecordGate = true
	w := d.withdraw(t, later)
	a := (&admitting{land: d}).ask(t, "rename the flag")
	d.pr.Facts.State = "CLOSED"
	o := d.once(t)
	is(t, o, pr.ActDisposed)
	for _, id := range []string{w, a} {
		b, _ := d.store.Row(id)
		if b.Status != "closed" || b.Metadata["gc.work_outcome"] != "no-op" || !strings.Contains(b.Notes, "PR #7 closed") {
			t.Fatalf("%s is %s with %v and notes %q", id, b.Status, b.Metadata, b.Notes)
		}
		if !strings.Contains(o.Detail, id) {
			t.Fatalf("the outcome %q does not name %s", o.Detail, id)
		}
	}
	if len(r.asked()) != 1 {
		t.Fatalf("the writer was asked %v", r.asked())
	}
}

// A retired PR that merged all the same lands as any merge does: the work is
// on its target.
func TestARetiredPRThatMergedAllTheSameLands(t *testing.T) {
	d, r := retired(t)
	mergedOnGitHub(d, head)
	is(t, d.once(t), pr.ActLanded)
	b := d.row(t)
	if b.Status != "closed" || len(r.asked()) != 0 {
		t.Fatalf("a merged retired PR left the bead %s and asked the writer %v", b.Status, r.asked())
	}
	meta(t, b, map[string]string{"merge_result": record.Merged, "merged_sha": merged})
}
