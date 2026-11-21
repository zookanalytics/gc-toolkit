package pr_test

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The hand-over of a changed head (handover.go). Gas City gives the refinery a
// turn for a bead only once nothing holds it, so while only merge holds, the
// conversations and asks on a PR, hold its bead, the landing order wakes and
// nudges the refinery for the bead's changed head, once no withdrawal and no
// review run holds that head.

// waking records each wake the order asks for, as "<session>: <message>", and
// err fails each.
type waking struct {
	mu  sync.Mutex
	got []string
	err error
}

func (w *waking) Wake(_ context.Context, session, message string) error {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.got = append(w.got, session+": "+message)
	return w.err
}

func (w *waking) woken() []string {
	w.mu.Lock()
	defer w.mu.Unlock()
	return slices.Clone(w.got)
}

func (w *waking) fail(err error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.err = err
}

// handing is the landing order's world of admitting, with the refinery's wake.
type handing struct {
	*admitting
	wakes *waking
}

func newHanding(t *testing.T) *handing {
	t.Helper()
	d := newAdmit(t)
	w := &waking{}
	d.l.Wake = w
	return &handing{admitting: d, wakes: w}
}

// wokeOnce fails unless the order has woken the refinery once, for the bead
// and the merge hold that holds it.
func (d *handing) wokeOnce(t *testing.T, holder string) {
	t.Helper()
	got := d.wakes.woken()
	if len(got) != 1 || !strings.HasPrefix(got[0], boundRefinery+": ") || !strings.Contains(got[0], bead) ||
		!strings.Contains(got[0], holder) {
		t.Fatalf("the refinery was woken %d times, want once for %s and %s: %q", len(got), bead, holder, got)
	}
}

// assignedTo fails unless the bead is assigned to want, "" for nobody.
func assignedTo(t *testing.T, d *land, want string) {
	t.Helper()
	if b := d.row(t); b.Assignee != want {
		t.Fatalf("the bead is assigned to %q, want %q", b.Assignee, want)
	}
}

func (d *handing) wokeNone(t *testing.T) {
	t.Helper()
	if got := d.wakes.woken(); len(got) > 0 {
		t.Fatalf("the order woke a session: %q", got)
	}
}

// A head the PR moved to, which the run sends back to the refinery while only a
// conversation holds the bead and no review run is attached, has the refinery
// woken and nudged in the run that sends it back, and its marker cleared, so
// no later run reads the record or wakes the refinery again.
func TestARequeueOnlyAConversationHoldsWakesTheRefinery(t *testing.T) {
	for _, c := range []struct{ name, status, assignee string }{
		{"in the operator's queue", "open", "human"},
		{"held by a sitting", "in_progress", "rig/gc-toolkit.tk-conv"},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newHanding(t)
			d.conversation(t, c.status, c.assignee, "")
			d.pr.Facts.HeadRefOid = other
			o := d.once(t)
			is(t, o, pr.ActRequeued)
			says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged", "the marker is cleared")
			d.wokeOnce(t, "tk-conv")
			b := d.row(t)
			if b.Status != "open" || b.Assignee != boundRefinery {
				t.Fatalf("the requeue left the bead %s under %s", b.Status, b.Assignee)
			}
			meta(t, b, map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other,
				"pr_reconcile_pending": "<absent>"})
			if out := d.reconcile(t, pr.Options{}); len(out) != 0 {
				t.Fatalf("the hand-over left the record for another run: %+v", out)
			}
			d.wokeOnce(t, "tk-conv")
		})
	}
}

// A head a review run's repair pushed waits on that run while it is attached:
// the requeue keeps the marker and the bead assigned to nobody, since Gas City
// retires a run whose input bead an agent outside it is assigned, and wakes no
// one. The first run that decides the record while the review run lives reads
// no PR and writes only the digest of what it decided on, and a run after it in
// which nothing changed decides nothing. The first run after the review run
// ends wakes the
// refinery, since the conversation still holds the bead, and hands the head to
// it in the write that clears the marker.
func TestAReviewRunsEndHandsAHeadAConversationHoldsToTheRefinery(t *testing.T) {
	d := newHanding(t)
	d.conversation(t, "open", "human", "")
	is(t, d.once(t), pr.ActPoured)
	d.store.List(bead, "tk-run1", "tk-conv")
	d.pr.Facts.HeadRefOid = other
	o := d.once(t)
	is(t, o, pr.ActRequeued)
	says(t, o, "waits on review run tk-run1")
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	assignedTo(t, d.land, "")
	d.wokeNone(t)

	o = d.run(t)
	is(t, o, pr.ActChecked)
	says(t, o, "waits on review run tk-run1")
	readsNoGitHub(t, d.land)
	if w := d.runWrites(); !keptDigest(w) {
		t.Fatalf("a run that found the head still waiting on its run wrote the bead %+v, want the digest of what it "+
			"decided on alone", w)
	}
	is(t, d.run(t), pr.ActChecked)
	readsNoGitHub(t, d.land)
	if w := d.runWrites(); len(w) > 0 {
		t.Fatalf("a run in which nothing changed wrote the bead: %+v", w)
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
	assignedTo(t, d.land, "")
	d.wokeNone(t)

	d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
	d.store.List(bead, "tk-conv")
	o = d.once(t)
	is(t, o, pr.ActSettled)
	says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged", "the marker is cleared")
	d.wokeOnce(t, "tk-conv")
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
	assignedTo(t, d.land, boundRefinery)
}

// With no conversation, the order wakes no one, since Gas City gives the
// refinery its turn for a bead nothing holds, which the refinery is assigned.
// A requeue with no run attached hands the head to the refinery in its own
// write, and a head a review run pushed waits on that run, with the bead
// assigned to nobody until the first run after it ends hands the head over.
func TestAChangedHeadNoConversationHoldsWakesNoOne(t *testing.T) {
	t.Run("no run attached", func(t *testing.T) {
		d := newHanding(t)
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		if ws := d.runWrites(); len(ws) != 1 || !slices.Contains(ws[0].Args, "--assignee="+boundRefinery) {
			t.Fatalf("the requeue wrote %+v, want one write that assigns the refinery", ws)
		}
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		assignedTo(t, d.land, boundRefinery)
		d.wokeNone(t)
	})
	t.Run("a run attached", func(t *testing.T) {
		d := newHanding(t)
		is(t, d.once(t), pr.ActPoured)
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
		assignedTo(t, d.land, "")
		d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
		o := d.once(t)
		is(t, o, pr.ActSettled)
		says(t, o, "the bead is assigned to the refinery and the marker is cleared")
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		assignedTo(t, d.land, boundRefinery)
		d.wokeNone(t)
	})
}

// A conversation beside another wait wakes no one, since the bead is not the
// refinery's to take while that wait holds it, as with a human gate. An ask is
// the review run's work, a merge hold find-work takes the bead past as it does
// a conversation, so the refinery is woken for an ask beside the conversation
// and for an ask alone. find-work reads only an open ask as one, so an ask at
// another status holds the bead as other work does, and wakes no one.
func TestWhatElseHoldsTheBeadDecidesTheWake(t *testing.T) {
	t.Run("a human gate", func(t *testing.T) {
		d := newHanding(t)
		d.conversation(t, "open", "human", "")
		d.gate(t, "tk-gate", "a-question")
		d.store.List(bead, "tk-conv", "tk-gate")
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		assignedTo(t, d.land, boundRefinery)
		d.wokeNone(t)
	})
	t.Run("an ask", func(t *testing.T) {
		d := newHanding(t)
		d.conversation(t, "open", "human", "")
		id := d.ask(t, "rename the flag")
		d.store.List(bead, "tk-conv", id)
		d.pr.Facts.HeadRefOid = other
		o := d.once(t)
		is(t, o, pr.ActRequeued)
		says(t, o, "conversation tk-conv", "ask "+id, "hold the bead, so the refinery was woken and nudged")
		meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
		d.wokeOnce(t, "tk-conv")
	})
	t.Run("an ask alone", func(t *testing.T) {
		d := newHanding(t)
		id := d.ask(t, "rename the flag")
		d.pr.Facts.HeadRefOid = other
		o := d.once(t)
		is(t, o, pr.ActRequeued)
		says(t, o, "only ask "+id+" holds the bead, so the refinery was woken and nudged")
		meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
		d.wokeOnce(t, id)
	})
	t.Run("an ask that is not open", func(t *testing.T) {
		d := newHanding(t)
		d.conversation(t, "open", "human", "")
		id := d.ask(t, "rename the flag")
		a, _ := d.store.Row(id)
		a.Status = "deferred"
		d.store.Put(a)
		d.store.List(bead, "tk-conv", id)
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		d.wokeNone(t)
	})
}

// A wake that does not land keeps the marker and records nothing else, as an act
// that does not complete records nothing, on a bead already assigned to the
// refinery, and the next run wakes the refinery again and clears the marker.
func TestAWakeThatDoesNotLandIsMadeAgainByTheNextRun(t *testing.T) {
	d := newHanding(t)
	d.conversation(t, "open", "human", "")
	d.wakes.fail(errors.New("gc session nudge rig/gc-toolkit.refinery: exit 1: the session is closed"))
	d.pr.Facts.HeadRefOid = other
	o := d.once(t)
	is(t, o, pr.ActRetry)
	says(t, o, "the refinery's wake did not land", "the session is closed")
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	assignedTo(t, d.land, boundRefinery)
	d.wakes.fail(nil)
	is(t, d.run(t), pr.ActSettled)
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
	assignedTo(t, d.land, boundRefinery)
	if got := d.wakes.woken(); len(got) != 2 {
		t.Fatalf("the refinery was asked to wake %d times, want the failed wake and one more: %q", len(got), got)
	}
}

// seeing is a refinery that takes its turn the moment it is woken, before the
// run's next write: it keeps the bead's row as the store holds it then.
type seeing struct {
	d    *handing
	rows []fake.Bead
}

func (s *seeing) Wake(context.Context, string, string) error {
	b, _ := s.d.store.Row(bead)
	s.rows = append(s.rows, b)
	return nil
}

// The refinery is woken only once the bead is assigned to it, so a refinery
// that takes its turn the moment the wake reaches it, before the run's last
// write, lists the bead at its find-work. The marker is still set then, so a
// run that stops before its last write leaves the next run to wake the
// refinery again. Both runs that wake it do so: the one that requeues the head
// and the first one after a review run ends.
func TestTheRefineryIsWokenOnlyOnceTheBeadIsAssignedToIt(t *testing.T) {
	for _, c := range []struct {
		name   string
		action string
		before func(t *testing.T, d *handing)
	}{
		{"in the run that requeues the head", pr.ActRequeued, func(_ *testing.T, d *handing) {
			d.pr.Facts.HeadRefOid = other
		}},
		{"in the first run after a review run ends", pr.ActSettled, func(t *testing.T, d *handing) {
			is(t, d.once(t), pr.ActPoured)
			d.store.List(bead, "tk-run1", "tk-conv")
			d.pr.Facts.HeadRefOid = other
			is(t, d.once(t), pr.ActRequeued)
			d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
			d.store.List(bead, "tk-conv")
		}},
	} {
		t.Run(c.name, func(t *testing.T) {
			d := newHanding(t)
			d.conversation(t, "open", "human", "")
			woken := &seeing{d: d}
			d.l.Wake = woken
			c.before(t, d)
			is(t, d.once(t), c.action)
			if len(woken.rows) != 1 {
				t.Fatalf("the refinery was woken %d times, want once", len(woken.rows))
			}
			if b := woken.rows[0]; b.Status != "open" || b.Assignee != boundRefinery || b.Metadata["pr_reconcile_pending"] != "true" {
				t.Fatalf("the wake reached the refinery with the bead %s under %q and marker %q, want open under %s and marked",
					b.Status, b.Assignee, b.Metadata["pr_reconcile_pending"], boundRefinery)
			}
			meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
			assignedTo(t, d.land, boundRefinery)
		})
	}
}

// A withdrawal that held a changed head from the refinery, carried out while a
// conversation holds the bead, has the refinery woken in the run that carries
// it out.
func TestAWithdrawalCarriedOutWhileAConversationHoldsTheBeadWakesTheRefinery(t *testing.T) {
	d := newHanding(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 300, Author: "operator", Body: "rename this",
		CreatedAt: "2026-11-12T01:00:00Z", Review: &gh.CommentReview{ID: 100, State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"}}}}}
	d.conversation(t, "open", "human", "")
	d.pr.Facts.HeadRefOid = later
	id := d.withdraw(t, head)
	d.store.List(bead, id, "tk-conv")
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	assignedTo(t, d.land, "")
	d.wokeNone(t)

	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_comment_watermark"] = "300" })
	// The store's blocked listing leaves the withdrawal out once the run closes
	// it, so the hand-over after the carry reads the conversation alone.
	d.store.List(bead, "tk-conv")
	o := d.once(t)
	is(t, o, pr.ActSettled)
	says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged")
	if status(t, d.land, id) != "closed" {
		t.Fatalf("the withdrawal is %s", status(t, d.land, id))
	}
	d.wokeOnce(t, "tk-conv")
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
	assignedTo(t, d.land, boundRefinery)
}

// A withdrawal carried out while a review run is still attached leaves the
// changed head waiting on that run: the marker stays and no one is woken, and
// the first run after the review run ends hands the head to the refinery.
func TestAWithdrawalCarriedOutWhileARunIsAttachedWaitsOnTheRun(t *testing.T) {
	d := newHanding(t)
	d.pr.Reviews = []gh.Review{approved(100, "operator", older)}
	d.pr.Threads = []gh.Thread{{ID: "T1", Comments: []gh.Comment{{ID: 300, Author: "operator", Body: "rename this",
		CreatedAt: "2026-11-12T01:00:00Z", Review: &gh.CommentReview{ID: 100, State: "APPROVED", SubmittedAt: "2026-11-12T01:00:00Z"}}}}}
	d.conversation(t, "open", "human", "")
	is(t, d.once(t), pr.ActPoured)
	d.pr.Facts.HeadRefOid = later
	id := d.withdraw(t, head)
	d.store.List(bead, id, "tk-run1", "tk-conv")
	is(t, d.once(t), pr.ActRequeued)
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	d.wokeNone(t)

	d.edit(t, func(b *fake.Bead) { b.Metadata["pr_comment_watermark"] = "300" })
	d.store.List(bead, "tk-run1", "tk-conv")
	o := d.once(t)
	is(t, o, pr.ActChecked)
	says(t, o, "waits on review run tk-run1")
	if status(t, d.land, id) != "closed" {
		t.Fatalf("the withdrawal is %s", status(t, d.land, id))
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
	d.wokeNone(t)

	d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
	d.store.List(bead, "tk-conv")
	o = d.once(t)
	is(t, o, pr.ActSettled)
	says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged")
	d.wokeOnce(t, "tk-conv")
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
}

// A requeue whose read of what holds the bead fails keeps the marker and
// records nothing else, as an act that does not complete records nothing, and
// the next run reads the bead's holds again, wakes the refinery for the
// conversation and clears the marker.
func TestARequeueThatCannotReadWhatHoldsTheBeadLeavesTheWakeToTheNextRun(t *testing.T) {
	d := newHanding(t)
	d.conversation(t, "open", "human", "")
	d.pr.Facts.HeadRefOid = other
	d.refresh(t)
	d.store.BlockedErr = errors.New("bd's blocked listing did not answer")
	o := d.run(t)
	is(t, o, pr.ActRetry)
	says(t, o, "what holds the bead did not read", "bd's blocked listing did not answer")
	if w := d.runWrites(); len(w) != 1 {
		t.Fatalf("the run wrote %d times, want the requeue alone: %+v", len(w), w)
	}
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "observed_pr_head_sha": other,
		"pr_reconcile_pending": "true"})
	d.wokeNone(t)

	d.store.BlockedErr = nil
	o = d.run(t)
	is(t, o, pr.ActSettled)
	says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged")
	d.wokeOnce(t, "tk-conv")
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>"})
}
