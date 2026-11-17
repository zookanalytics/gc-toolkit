package pr_test

import (
	"context"
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
// is asked for, holds one while held says why, fails one while err is set,
// holds one whose bead no longer has the status, the assignee or the ruling the
// run judged, as bead-rehome.sh's --if-status, --if-assignee and --if-ruled
// do, and otherwise closes the bead and clears the marker, as bead-rehome.sh's
// close does.
type rehome struct {
	mu    sync.Mutex
	store *fake.Store
	calls []string
	notes []string
	got   []pr.Disposal
	held  string
	err   error
}

func (r *rehome) Close(x pr.Disposal) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	d := x.Disposition
	r.calls = append(r.calls, strings.TrimSpace(fmt.Sprintf("%s %s %s %s", x.Bead, d.Kind, d.Successor, d.Store)))
	r.notes = append(r.notes, x.Note)
	r.got = append(r.got, x)
	switch {
	case r.err != nil:
		return r.err
	case r.held != "":
		return &pr.HeldClose{Why: r.held}
	}
	row, ok := r.store.Row(x.Bead)
	if !ok {
		return errors.New("no such bead")
	}
	if row.Status != x.Status || row.Assignee != x.Assignee {
		return &pr.HeldClose{Why: fmt.Sprintf("%s is %s under %q now, not %s under %q as the run judged it",
			x.Bead, row.Status, row.Assignee, x.Status, x.Assignee)}
	}
	m := row.Metadata
	if now := (pr.Disposition{Kind: m["gc.pr_close_disposition_kind"], Successor: m["gc.pr_close_disposition_successor"],
		Store: m["gc.pr_close_disposition_successor_store"]}); now != d {
		return &pr.HeldClose{Why: fmt.Sprintf("%s records the ruling %s onto %s now, not the %s onto %s the run read",
			x.Bead, now.Kind, now.Successor, d.Kind, d.Successor)}
	}
	row.Status = "closed"
	delete(row.Metadata, "pr_reconcile_pending")
	r.store.Put(row)
	return nil
}

func (r *rehome) disposals() []pr.Disposal {
	r.mu.Lock()
	defer r.mu.Unlock()
	return slices.Clone(r.got)
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
	readsNoGitHub(t, d)
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
	if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
		t.Fatalf("a later run read a disposed bead: %+v", out)
	}
}

// The act decides the closed PR under the lock and hands the close on once the
// lock is free, writing nothing on the bead itself: a writer that waited for
// the lock would never get it.
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
	if w := d.runWrites(); len(w) != 0 {
		t.Fatalf("the run wrote on the bead: %+v", w)
	}
}

// closeFunc is a disposition writer that runs a function.
type closeFunc func() error

func (f closeFunc) Close(pr.Disposal) error { return f() }

// A close the writer holds for now, as the ruling's open conversation holds it,
// leaves the bead blocked with its marker, and the next run tries it again. It
// is a wait, so it fails no run.
func TestAHeldDispositionCloseIsTriedAgainByTheNextRun(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	r.held = "held by the open conversation " + conversation
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, r.held) {
		t.Fatalf("the held close says %q", o.Detail)
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
	d.refresh(t)
	var out []pr.RunOutcome
	err := d.l.Reconcile(pr.Options{}, func(o pr.RunOutcome) { out = append(out, o) })
	if err == nil || len(out) != 1 {
		t.Fatalf("Reconcile: %v, outcomes %+v", err, out)
	}
	is(t, out[0], pr.ActFailed)
	if !strings.Contains(out[0].Detail, "does not exist") {
		t.Fatalf("the failure says %q", out[0].Detail)
	}
}

// The writer is handed the run's judgment of the bead under the record lock:
// the status and assignee it read there, and the ruling it read.
func TestTheDispositionWriterIsHandedTheRunsJudgment(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	is(t, d.once(t), pr.ActDisposed)
	want := pr.Disposal{Bead: bead, Status: "blocked", Assignee: refinery,
		Disposition: pr.Disposition{Kind: "not-needed", Successor: conversation},
		Note:        "PR #7 closed under the disposition a ruling recorded before the close"}
	if got := r.disposals(); len(got) != 1 || got[0] != want {
		t.Fatalf("the writer was handed %+v, want %+v", got, want)
	}
}

// gap is the disposition writer with another writer's change landing on the
// bead just before its first close, as a release or a second ruling can land
// once the run has freed the record lock and before the writer takes it.
type gap struct {
	*rehome
	change func()
	once   sync.Once
}

func (g *gap) Close(x pr.Disposal) error {
	g.once.Do(g.change)
	return g.rehome.Close(x)
}

// A release that lands once the act has freed the record lock, as
// hand-back.sh's or refinery-requeue.sh's can, since neither takes the lock,
// holds the close: the writer is held to what the act judged, not to a read
// made after the release. The next run reads the bead as released: it clears
// the marker and closes nothing.
func TestABeadReleasedOnceTheRunFreesTheLockIsLeftWhereTheReleaseLeftIt(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	d.l.Dispositions = &gap{rehome: r, change: func() {
		d.edit(t, func(b *fake.Bead) { b.Status, b.Assignee = "open", "" })
	}}
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "not blocked under \""+refinery+"\" as the run judged it") {
		t.Fatalf("the held close says %q", o.Detail)
	}
	if b := d.row(t); b.Status != "open" || b.Assignee != "" {
		t.Fatalf("the released bead is %s under %q", b.Status, b.Assignee)
	}
	is(t, d.once(t), pr.ActReleased)
	b := d.row(t)
	if b.Status != "open" || len(r.asked()) != 1 {
		t.Fatalf("the next run left the bead %s and asked the writer %v", b.Status, r.asked())
	}
	meta(t, b, map[string]string{"pr_reconcile_pending": ""})
}

// A second ruling that lands once the run has freed the lock, as pr-dispose.sh
// records it under the lock, holds the close of the first, and the next run
// carries out the second.
func TestARulingRecordedOnceTheRunFreesTheLockIsCarriedOutByTheNextRun(t *testing.T) {
	d, r := retired(t)
	d.pr.Facts.State = "CLOSED"
	d.l.Dispositions = &gap{rehome: r, change: func() {
		d.edit(t, func(b *fake.Bead) {
			b.Metadata["gc.pr_close_disposition_kind"] = "re-homed"
			b.Metadata["gc.pr_close_disposition_successor"] = "tk-carrier"
		})
	}}
	o := d.once(t)
	is(t, o, pr.ActChecked)
	if !strings.Contains(o.Detail, "records the ruling re-homed onto tk-carrier now") {
		t.Fatalf("the held close says %q", o.Detail)
	}
	if b := d.row(t); b.Status != "blocked" {
		t.Fatalf("the held close left the bead %s", b.Status)
	}
	is(t, d.once(t), pr.ActDisposed)
	if want := []string{bead + " not-needed " + conversation, bead + " re-homed tk-carrier"}; !slices.Equal(r.asked(), want) {
		t.Fatalf("the writer was asked %v, want %v", r.asked(), want)
	}
	if b := d.row(t); b.Status != "closed" {
		t.Fatalf("the second ruling's close left the bead %s", b.Status)
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
	if out := e.reconcile(t, pr.Options{}); len(out) != 0 {
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
			if out := d.reconcile(t, pr.Options{}); len(out) != 0 || len(r.asked()) != 0 {
				t.Fatalf("the order read it: %+v, and asked the writer %v", out, r.asked())
			}
		})
	}
}

// rulingHub is GitHub while a ruling waits for the record lock, which it takes
// from its read of the bead to its stamp of the disposition (pr-dispose.sh): at
// the run's read of the PR and at its merge request, the ruling tries the lock
// once, and tries records what each try found.
type rulingHub struct {
	pr.Hub
	dir   string
	tries *[]string
}

func (h rulingHub) try(at string) {
	release, err := record.Lock(h.dir, 0)
	switch {
	case err == nil:
		release()
		*h.tries = append(*h.tries, at+": free")
	case errors.Is(err, record.ErrLockWait):
		*h.tries = append(*h.tries, at+": held")
	default:
		*h.tries = append(*h.tries, at+": "+err.Error())
	}
}

func (h rulingHub) PullRequest(repo string, number int) (*gh.PullRequest, error) {
	h.try("read")
	return h.Hub.PullRequest(repo, number)
}

func (h rulingHub) MergePullRequest(id, head string) error {
	h.try("merge")
	return h.Hub.MergePullRequest(id, head)
}

// An act holds the record lock from its read of the bead to its last write, so
// a ruling that comes while the merge's own read finds an open PR ready waits
// for the act: the merge is requested before the ruling records that the work
// will not land, never after it. The ruling records its disposition once
// the lock is free, and the next run finds the PR merged and lands it as any
// merge, asking nothing of the disposition writer.
func TestARulingThatComesWhileARunReadsAnOpenPRWaitsForTheRun(t *testing.T) {
	d := newCycle(t)
	r := &rehome{store: d.store}
	d.l.Dispositions = r
	var tries []string
	hub := d.l.Hub
	d.l.Hub = func(ctx context.Context, host string) pr.Hub {
		return rulingHub{Hub: hub(ctx, host), dir: d.l.Dir, tries: &tries}
	}
	is(t, d.once(t), pr.ActRequested)
	if want := []string{"read: held", "merge: held"}; !slices.Equal(tries, want) {
		t.Fatalf("the ruling's tries at the lock found %v, want %v", tries, want)
	}
	if want := []string{"MergePullRequest PR_7 " + head}; !slices.Equal(asks(d.github), want) {
		t.Fatalf("GitHub was asked %v, want %v", asks(d.github), want)
	}
	release, err := record.Lock(d.l.Dir, 0)
	if err != nil {
		t.Fatalf("the ruling did not get the lock once the run ended: %v", err)
	}
	d.edit(t, func(b *fake.Bead) {
		b.Metadata["gc.pr_close_disposition_kind"] = "not-needed"
		b.Metadata["gc.pr_close_disposition_successor"] = conversation
	})
	release()
	is(t, d.once(t), pr.ActLanded)
	if len(r.asked()) != 0 {
		t.Fatalf("a merged PR asked the disposition writer %v", r.asked())
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
// would hold the bead's close. One that closed before the PR is left as it is.
func TestARetiredPRsAsksAndWithdrawalsCloseWithIt(t *testing.T) {
	d, r := retired(t)
	d.store.WorkRecordGate = true
	gone := []string{d.withdraw(t, other), (&admitting{land: d}).ask(t, "drop the flag")}
	for _, id := range gone {
		b, _ := d.store.Row(id)
		b.Status = "closed"
		d.store.Put(b)
	}
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
	for _, id := range gone {
		if b, _ := d.store.Row(id); strings.Contains(b.Notes, "PR #7 closed") || strings.Contains(o.Detail, id) {
			t.Fatalf("%s, closed before the PR, was closed again: notes %q, outcome %q", id, b.Notes, o.Detail)
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
