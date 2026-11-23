package pr_test

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/gate"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/listing"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr"
)

// stayConv is a conversation whose sitting stays for the work tk-1's PR
// carries.
const stayConv = "tk-stay"

// staying is the landing world with a conversation open under its sitting
// that waits on a stay's gate for the bead, and the own status handed to the
// order. It returns the world and the gate.
func staying(t *testing.T) (*land, string) {
	t.Helper()
	d := newLand(t)
	d.l.Status = listing.OwnStatus{}
	d.store.Put(fake.Bead{ID: stayConv, Title: "the conversation", Status: "open", IssueType: "task",
		Assignee: "gc-toolkit/gc-toolkit." + stayConv})
	return d, promise(t, d, bead)
}

// promise files the stay's gate on work, blocking the conversation.
func promise(t *testing.T, d *land, work string) string {
	t.Helper()
	id, err := ledger.New(d.store).CreateGate(gate.NeedsReview, work, stayConv, gate.Title(work))
	if err != nil {
		t.Fatal(err)
	}
	return id
}

// needsReview takes the approval off the PR, so all it waits on is a person's
// review.
func needsReview(d *land) { d.pr.Reviews = nil }

// resolved reports the gate closed with a reason that says each of wants.
func resolved(t *testing.T, d *land, g string, wants ...string) {
	t.Helper()
	row, _ := d.store.Row(g)
	if row.Status != "closed" {
		t.Fatalf("the gate %s is %s, want resolved", g, row.Status)
	}
	for _, w := range wants {
		if !strings.Contains(row.CloseReason, w) {
			t.Errorf("the gate's reason %q does not say %q", row.CloseReason, w)
		}
	}
}

func open(t *testing.T, d *land, g string) {
	t.Helper()
	if row, _ := d.store.Row(g); row.Status != "open" {
		t.Fatalf("the gate %s is %s, want it open", g, row.Status)
	}
}

// holdsOnto is the beads the bead waits on through a blocks edge.
func holdsOnto(d *land) []string {
	row, _ := d.store.Row(bead)
	var out []string
	for _, e := range row.Edges {
		if e.Type == gcbd.EdgeBlocks {
			out = append(out, e.ID)
		}
	}
	return out
}

func noMerge(t *testing.T, d *land) {
	t.Helper()
	if got := asks(d.github); len(got) > 0 {
		t.Fatalf("asked %v, want no merge requested under the gate", got)
	}
}

// New work's PR, once it reads needs-review in its own right, gets the
// conversation's hold and its gate resolved, and nothing else in that pass.
func TestAStayComesBackWhenItsPRNeedsReview(t *testing.T) {
	d, g := staying(t)
	needsReview(d)
	out := d.once(t)
	is(t, out, pr.ActResolved)
	says(t, out, g, "needs-review", stayConv)
	resolved(t, d, g, bead, "needs-review", head)
	if got := holdsOnto(d); !slices.Equal(got, []string{stayConv}) {
		t.Errorf("the bead waits on %v, want the conversation's hold", got)
	}
	noMerge(t, d)
}

// A rework or the conversation's own subject: the conversation holds the PR
// from engage, so the hold's write is a no-op and the gate resolves.
func TestAStayOnAPRItsConversationHoldsKeepsTheHoldItHas(t *testing.T) {
	d, g := staying(t)
	d.edges = []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: stayConv, Title: "the conversation", Status: "open"}}
	d.put("blocked", "")
	d.store.List(bead, stayConv)
	needsReview(d)
	is(t, d.once(t), pr.ActResolved)
	resolved(t, d, g, "needs-review")
	if got := holdsOnto(d); !slices.Equal(got, []string{stayConv}) {
		t.Errorf("the bead waits on %v, want the one hold it had", got)
	}
}

// A PR found ready under an open gate, such as one an earlier round's approval
// stands on after a send-back the run answered without a push, gets the hold
// and the resolve in place of the merge request, and the hold keeps the merge
// from then on.
func TestAPRFoundReadyUnderAGateIsHeldNotMerged(t *testing.T) {
	d, g := staying(t)
	out := d.once(t)
	is(t, out, pr.ActResolved)
	resolved(t, d, g, "merging")
	noMerge(t, d)
	if got := holdsOnto(d); !slices.Equal(got, []string{stayConv}) {
		t.Fatalf("the bead waits on %v, want the conversation's hold", got)
	}
	// The store reads the bead blocked by the hold, as bd does from the edge.
	d.store.List(bead, stayConv)
	is(t, d.once(t), pr.ActChecked)
	noMerge(t, d)
}

// While the city still works the PR, the gate stays open and no merge is
// requested.
func TestAGateStaysOpenWhileThePRIsTheCitys(t *testing.T) {
	d, g := staying(t)
	d.pr.Suites[head][0].Runs[0] = run("test", "IN_PROGRESS", "")
	out := d.once(t)
	is(t, out, pr.ActChecked)
	open(t, d, g)
	noMerge(t, d)
	if got := holdsOnto(d); len(got) != 0 {
		t.Errorf("the bead waits on %v, want no hold while the work is out", got)
	}
}

// A gate whose conversation has closed resolves at its condition, with no
// hold.
func TestAGateWhoseConversationClosedResolvesWithNoHold(t *testing.T) {
	d, g := staying(t)
	row, _ := d.store.Row(stayConv)
	row.Status = "closed"
	d.store.Put(row)
	needsReview(d)
	out := d.once(t)
	is(t, out, pr.ActResolved)
	says(t, out, "no conversation open")
	resolved(t, d, g, "needs-review")
	if got := holdsOnto(d); len(got) != 0 {
		t.Errorf("the bead waits on %v, want no hold for a closed conversation", got)
	}
}

// A hold that does not land ends that PR's pass with the gate open and no
// merge requested, and the next run tries again.
func TestAHoldThatDoesNotLandIsTriedAgain(t *testing.T) {
	d, g := staying(t)
	d.store.EdgeErr = errors.New("bd: exit 1: database is locked")
	out := d.once(t)
	is(t, out, pr.ActRetry)
	says(t, out, "did not land", "stays open")
	open(t, d, g)
	noMerge(t, d)
	d.store.EdgeErr = nil
	is(t, d.once(t), pr.ActResolved)
	resolved(t, d, g, "merging")
	noMerge(t, d)
}

// A resolve that does not land is tried again too.
func TestAResolveThatDoesNotLandIsTriedAgain(t *testing.T) {
	d, g := staying(t)
	d.store.ResolveErr = errors.New("bd: exit 1: database is locked")
	is(t, d.once(t), pr.ActRetry)
	open(t, d, g)
	noMerge(t, d)
	d.store.ResolveErr = nil
	is(t, d.once(t), pr.ActResolved)
	resolved(t, d, g, "merging")
}

// A PR in its base's merge queue is left to GitHub, its gate open.
func TestAPRInAMergeQueueLeavesItsGateOpen(t *testing.T) {
	d, g := staying(t)
	d.pr.Facts.InMergeQueue = true
	is(t, d.once(t), pr.ActChecked)
	open(t, d, g)
}

// The order reads every open gate, past the 50 bd lists by default.
func TestAGatePastTheFirstFiftyIsResolved(t *testing.T) {
	d := newLand(t)
	d.l.Status = listing.OwnStatus{}
	for i := range 60 {
		d.store.Put(fake.Bead{ID: fmt.Sprintf("tk-g%02d", i), Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "ask"})
	}
	d.store.Put(fake.Bead{ID: stayConv, Title: "the conversation", Status: "open", IssueType: "task",
		Assignee: "gc-toolkit/gc-toolkit." + stayConv})
	g := promise(t, d, bead)
	needsReview(d)
	is(t, d.once(t), pr.ActResolved)
	resolved(t, d, g, "needs-review")
}

// A gate whose work has closed resolves in every run, whatever PR it names.
func TestAGateWhoseWorkClosedResolves(t *testing.T) {
	d, _ := staying(t)
	d.store.Put(fake.Bead{ID: "tk-done", Title: "work that closed", Status: "closed", IssueType: "task"})
	g := promise(t, d, "tk-done")
	d.refresh(t)
	outs := d.reconcile(t, pr.Options{})
	i := slices.IndexFunc(outs, func(o pr.RunOutcome) bool { return o.Bead == g })
	if i < 0 {
		t.Fatalf("no outcome for the gate %s among %+v", g, outs)
	}
	is(t, outs[i], pr.ActResolved)
	resolved(t, d, g, "tk-done closed")
}

// Without the own status, the order requests no merge of a PR a gate names.
func TestNoMergeUnderAGateTheOrderCannotRead(t *testing.T) {
	d, g := staying(t)
	d.l.Status = nil
	out := d.once(t)
	is(t, out, pr.ActChecked)
	says(t, out, g)
	open(t, d, g)
	noMerge(t, d)
}

// Without the own status, a PR a gate names that is not ready goes on to the
// rest of the decision.
func TestAGateTheOrderCannotReadLeavesANotReadyPRToTheRest(t *testing.T) {
	d, g := staying(t)
	d.l.Status = nil
	d.pr.Suites[head][0].Runs[0] = run("test", "IN_PROGRESS", "")
	out := d.once(t)
	is(t, out, pr.ActChecked)
	says(t, out, "not ready")
	open(t, d, g)
	noMerge(t, d)
}

// A gate filed during the merge's act, after the decision read the gates, is
// found at the act's last read, so no merge is requested.
func TestAGateFiledDuringTheActHoldsTheMerge(t *testing.T) {
	d, _ := staying(t)
	row, _ := d.store.Row(stayConv)
	for _, e := range row.Edges {
		if e.Type == gcbd.EdgeBlocks {
			gr, _ := d.store.Row(e.ID)
			gr.Status = "closed"
			d.store.Put(gr)
		}
	}
	reread, gateReads, filed := false, 0, ""
	inner := d.l.Reread
	d.l.Reread = func(ctx context.Context, url string) error {
		reread = true
		return inner(ctx, url)
	}
	d.store.OnFind = func(q gcbd.Query) {
		if !reread || q.Type != "gate" || filed != "" {
			return
		}
		if gateReads++; gateReads == 2 {
			filed = promise(t, d, bead)
		}
	}
	out := d.once(t)
	is(t, out, pr.ActChecked)
	if filed == "" {
		t.Fatal("the test filed no gate during the act")
	}
	says(t, out, filed, "during the act")
	noMerge(t, d)
}
