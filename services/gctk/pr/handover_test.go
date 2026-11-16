package pr_test

import (
	"errors"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

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

func (w *waking) Wake(session, message string) error {
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
			if out := d.reconcile(t, pr.Options{Count: 10}); len(out) != 0 {
				t.Fatalf("the hand-over left the record for another run: %+v", out)
			}
			d.wokeOnce(t, "tk-conv")
		})
	}
}

// A head a review run's repair pushed waits on that run while it is attached:
// the requeue keeps the marker and wakes no one, and each run that reads the
// record while the review run lives stamps the read and reads no PR. The first
// run after the review run ends wakes the refinery, since the conversation
// still holds the bead, and clears the marker.
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
	d.wokeNone(t)

	d.l.Now = func() time.Time { return time.Date(2026, 11, 12, 9, 10, 0, 0, time.UTC) }
	reads := len(d.github.Reads())
	o = d.once(t)
	is(t, o, pr.ActChecked)
	says(t, o, "waits on review run tk-run1")
	if more := d.github.Reads()[reads:]; len(more) > 0 {
		t.Fatalf("a read of a head that waits on its run read GitHub: %v", more)
	}
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true", "pr_last_checked_at": "2026-11-12T09:10:00Z"})
	d.wokeNone(t)

	d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
	d.store.List(bead, "tk-conv")
	o = d.once(t)
	is(t, o, pr.ActSettled)
	says(t, o, "only conversation tk-conv holds the bead, so the refinery was woken and nudged", "the marker is cleared")
	d.wokeOnce(t, "tk-conv")
	meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
}

// With no conversation, the order wakes no one, since Gas City gives the
// refinery its turn for a bead nothing holds. A requeue with no run attached
// clears the marker in its own write, and a head a review run pushed waits on
// that run, with the marker cleared by the first run after it ends.
func TestAChangedHeadNoConversationHoldsWakesNoOne(t *testing.T) {
	t.Run("no run attached", func(t *testing.T) {
		d := newHanding(t)
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		d.wokeNone(t)
	})
	t.Run("a run attached", func(t *testing.T) {
		d := newHanding(t)
		is(t, d.once(t), pr.ActPoured)
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "true"})
		d.end(t, "tk-run1", "pass", "2026-11-12T09:30:00Z")
		o := d.once(t)
		is(t, o, pr.ActSettled)
		says(t, o, "the marker is cleared")
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
		d.wokeNone(t)
	})
}

// A conversation beside another wait wakes no one, since the bead is not the
// refinery's to take while that wait holds it, as with a human gate. An ask is
// the review run's work, a merge hold find-work takes the bead past as it does
// a conversation, so the refinery is woken for an ask beside the conversation
// and for an ask alone.
func TestWhatElseHoldsTheBeadDecidesTheWake(t *testing.T) {
	t.Run("a human gate", func(t *testing.T) {
		d := newHanding(t)
		d.conversation(t, "open", "human", "")
		d.gate(t, "tk-gate", "a-question")
		d.store.List(bead, "tk-conv", "tk-gate")
		d.pr.Facts.HeadRefOid = other
		is(t, d.once(t), pr.ActRequeued)
		meta(t, d.row(t), map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "<absent>"})
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
}

// A wake that does not land keeps the marker and says why on the record, and
// the next run wakes the refinery again and clears both.
func TestAWakeThatDoesNotLandIsMadeAgainByTheNextRun(t *testing.T) {
	d := newHanding(t)
	d.conversation(t, "open", "human", "")
	d.wakes.fail(errors.New("gc session nudge rig/gc-toolkit.refinery: exit 1: the session is closed"))
	d.pr.Facts.HeadRefOid = other
	o := d.once(t)
	is(t, o, pr.ActRetry)
	says(t, o, "the refinery's wake did not land", "the session is closed")
	b := d.row(t)
	meta(t, b, map[string]string{"merge_result": record.HeadChanged, "pr_reconcile_pending": "true"})
	if !strings.Contains(b.Metadata["pr_reconcile_error"], "the refinery's wake did not land") {
		t.Fatalf("the record does not say the wake did not land: %q", b.Metadata["pr_reconcile_error"])
	}
	d.wakes.fail(nil)
	is(t, d.once(t), pr.ActSettled)
	meta(t, d.row(t), map[string]string{"pr_reconcile_pending": "<absent>", "pr_reconcile_error": "<absent>"})
	if got := d.wakes.woken(); len(got) != 2 {
		t.Fatalf("the refinery was asked to wake %d times, want the failed wake and one more: %q", len(got), got)
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
}
