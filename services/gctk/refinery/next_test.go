package refinery

import (
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// queue is one rig's store and the search a refinery session there runs.
type queue struct {
	s        *fake.Store
	sessions []gascity.Session
	listErr  error
	// held is what the store's blocked listing names as holding each bead.
	held map[string][]string
}

func newQueue() *queue { return &queue{s: fake.New(), held: map[string][]string{}} }

// put adds a bead assigned to the refinery, open, on branch polecat/<id>,
// created at created (an RFC 3339 stamp), with the metadata kv names.
func (q *queue) put(id, created string, kv ...string) fake.Bead {
	m := map[string]string{"branch": "polecat/" + id}
	for i := 0; i+1 < len(kv); i += 2 {
		if kv[i+1] == "" {
			delete(m, kv[i])
			continue
		}
		m[kv[i]] = kv[i+1]
	}
	b := fake.Bead{ID: id, Title: id, Status: "open", IssueType: "task", Assignee: ref, Priority: 2, CreatedAt: created, Metadata: m}
	q.s.Put(b)
	return b
}

// edit applies f to the bead id and puts it back.
func (q *queue) edit(id string, f func(*fake.Bead)) {
	b, _ := q.s.Row(id)
	f(&b)
	q.s.Put(b)
}

// waitOn gives id a blocks edge onto on, whose status the edge carries, and,
// while on has not closed, puts id in the store's blocked listing held by it,
// as bd lists a bead its open wait holds.
func (q *queue) waitOn(id, on string) {
	far, _ := q.s.Row(on)
	q.edit(id, func(b *fake.Bead) {
		b.Edges = append(b.Edges, gcbd.Edge{Type: gcbd.EdgeBlocks, ID: on, Status: far.Status})
	})
	if far.Status == "closed" {
		return
	}
	q.held[id] = append(q.held[id], on)
	q.s.List(id, q.held[id]...)
	q.s.Mark(id)
}

func (q *queue) next(t *testing.T) Answer {
	t.Helper()
	search := &Search{Ledger: ledger.New(q.s), Refinery: ref, Self: []string{ref, "tools--refinery"},
		Sessions: func() ([]gascity.Session, error) { return q.sessions, q.listErr }}
	ans, err := search.Next()
	if err != nil {
		t.Fatalf("Next: %v", err)
	}
	return ans
}

func took(ans Answer) string {
	if ans.Take == nil {
		return ""
	}
	return ans.Take.ID
}

func leftIDs(ans Answer) []string {
	var out []string
	for _, l := range ans.Left {
		out = append(out, l.ID)
	}
	return out
}

// The search takes a bead assigned to the refinery and prints it as the row
// the hook claims: no other agent's bead, and none closed, and no blocked_by.
func TestNextTakesABeadAssignedToTheRefinery(t *testing.T) {
	q := newQueue()
	q.put("tk-a", stamp(0))
	other := q.put("tk-other", stamp(9))
	other.Assignee = "tools/gc-toolkit.witness"
	q.s.Put(other)
	shut := q.put("tk-shut", stamp(9))
	shut.Status = "closed"
	q.s.Put(shut)
	ans := q.next(t)
	if took(ans) != "tk-a" || ans.Take.Assignee != ref || ans.Take.Status != "open" || ans.Take.Metadata["branch"] != "polecat/tk-a" {
		t.Fatalf("took %+v", ans.Take)
	}
	if got := newQueue().next(t); got.Take != nil || len(got.Left) != 0 {
		t.Fatalf("an empty queue answered %+v", got)
	}
}

// A bead something holds is left, but a conversation or an ask on its PR
// holds only the merge, so a bead they alone hold is taken.
func TestNextLeavesAHeldBeadButTakesOneOnlyItsPRsConversationOrAskHolds(t *testing.T) {
	for _, c := range []struct {
		name  string
		build func(q *queue)
		take  bool
	}{
		{"an open wait", func(q *queue) {
			q.s.Put(fake.Bead{ID: "tk-unit", Status: "open", IssueType: "task"})
			q.waitOn("tk-p", "tk-unit")
		}, false},
		{"a conversation waiting in the operator's queue", func(q *queue) {
			q.s.Put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human",
				Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-p", Status: "open"}}})
			q.waitOn("tk-p", "tk-conv")
		}, true},
		{"an ask on its PR", func(q *queue) {
			q.s.Put(fake.Bead{ID: "tk-ask", Status: "open", IssueType: "task", Metadata: map[string]string{"branch": "polecat/tk-p"}})
			q.waitOn("tk-p", "tk-ask")
		}, true},
		{"a conversation and another wait", func(q *queue) {
			q.s.Put(fake.Bead{ID: "tk-conv", Status: "open", IssueType: "task", Assignee: "human",
				Edges: []gcbd.Edge{{Type: "tracks", ID: "tk-p", Status: "open"}}})
			q.s.Put(fake.Bead{ID: "tk-gate", Status: "open", IssueType: "gate"})
			q.waitOn("tk-p", "tk-conv")
			q.waitOn("tk-p", "tk-gate")
		}, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			q := newQueue()
			q.put("tk-p", stamp(0))
			c.build(q)
			ans := q.next(t)
			if (took(ans) == "tk-p") != c.take {
				t.Fatalf("took %q, left %+v; want taken %v", took(ans), ans.Left, c.take)
			}
			if !c.take && !slices.Equal(leftIDs(ans), []string{"tk-p"}) {
				t.Fatalf("left %+v; want tk-p named", ans.Left)
			}
		})
	}
}

// A bead whose branch another open bead works on is left, and made to wait on
// that bead, so it is no demand until it closes. The anchor a bead names and
// a bead waiting here too are no writers of its branch.
func TestNextMakesABeadWaitOnAnotherThatWorksItsBranch(t *testing.T) {
	q := newQueue()
	q.put("tk-a", stamp(0), "branch", "polecat/shared")
	q.s.Put(fake.Bead{ID: "tk-w", Status: "in_progress", IssueType: "task", Assignee: "tools/gc-toolkit.polecat-1",
		Metadata: map[string]string{"branch": "polecat/shared"}})
	ans := q.next(t)
	if took(ans) != "" || len(ans.Left) != 1 || ans.Left[0].ID != "tk-a" || !strings.Contains(ans.Left[0].Why, "tk-w works its branch") {
		t.Fatalf("took %q, left %+v", took(ans), ans.Left)
	}
	if got := q.s.EdgeWrites(); !slices.Equal(got, []fake.Edge{{ID: "tk-a", Far: "tk-w", Type: gcbd.EdgeBlocks}}) {
		t.Fatalf("edges written %+v", got)
	}

	q = newQueue()
	q.put("tk-child", stamp(0), "branch", "polecat/pr", "task_kind", "rework", "anchor_bead", "tk-anchor")
	q.s.Put(fake.Bead{ID: "tk-anchor", Status: "blocked", IssueType: "task", Metadata: map[string]string{"branch": "polecat/pr"}})
	q.put("tk-twin", stamp(5), "branch", "polecat/pr")
	if ans := q.next(t); took(ans) != "tk-child" || len(q.s.EdgeWrites()) != 0 {
		t.Fatalf("took %q, left %+v, edges %+v; want the child, its anchor and a bead waiting here no writers", took(ans), ans.Left, q.s.EdgeWrites())
	}
}

// A bead on the branch that waits on the one the search would take writes its
// branch only while someone writes it: a live run works it, or a listed
// session other than this one holds its claim. The bead it writes for cannot
// wait on it, since bd refuses that edge as a cycle, so it waits on the runs
// that work it, and a claim with no run leaves no bead to wait on.
func TestNextCountsABeadThatWaitsOnItAsAWriterOnlyWhileSomeoneWritesIt(t *testing.T) {
	for _, c := range []struct {
		name   string
		build  func(q *queue)
		writes bool
		edge   string
	}{
		{"open, armed and run by nobody", func(*queue) {}, false, ""},
		{"a live run works it", func(q *queue) {
			q.s.Put(fake.Bead{ID: "tk-root-sib", Status: "in_progress", IssueType: "task",
				Metadata: map[string]string{"gc.kind": "workflow", "gc.var.issue": "tk-sib"}})
		}, true, "tk-root-sib"},
		{"its claim is a listed session's", func(q *queue) {
			q.edit("tk-sib", func(b *fake.Bead) { b.Status, b.Assignee = "in_progress", "tools/gc-toolkit.polecat-2" })
			q.sessions = []gascity.Session{{Alias: "tools/gc-toolkit.polecat-2"}}
		}, true, ""},
		{"its claim is a session no list names", func(q *queue) {
			q.edit("tk-sib", func(b *fake.Bead) { b.Status, b.Assignee = "in_progress", "tools/gc-toolkit.polecat-9" })
		}, false, ""},
		{"its claim's session list does not read", func(q *queue) {
			q.edit("tk-sib", func(b *fake.Bead) { b.Status, b.Assignee = "in_progress", "tools/gc-toolkit.polecat-2" })
			q.listErr = errors.New("gc session list did not answer")
		}, true, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			q := newQueue()
			q.put("tk-first", stamp(0), "branch", "polecat/pr")
			q.s.Put(fake.Bead{ID: "tk-sib", Status: "open", IssueType: "task",
				Metadata: map[string]string{"branch": "polecat/pr", "task_kind": "rework", "anchor_bead": "tk-anchor"}})
			q.waitOn("tk-sib", "tk-first")
			c.build(q)
			ans := q.next(t)
			if (took(ans) == "") != c.writes {
				t.Fatalf("took %q, left %+v; want tk-sib a writer %v", took(ans), ans.Left, c.writes)
			}
			var want []fake.Edge
			if c.edge != "" {
				want = []fake.Edge{{ID: "tk-first", Far: c.edge, Type: gcbd.EdgeBlocks}}
			}
			if got := q.s.EdgeWrites(); !slices.Equal(got, want) {
				t.Fatalf("edges written %+v; want %+v", got, want)
			}
			row, _ := q.s.Row("tk-first")
			if failed := len(ans.Failures) > 0; failed != (c.writes && c.edge == "") || (c.edge != "" && demand(row)) {
				t.Fatalf("failures %v, tk-first demand %v; want a failure only for a claim with no run, and no demand once it waits",
					ans.Failures, demand(row))
			}
		})
	}
}

// Among the beads it can take, the search takes a claim a session left in
// progress, then a rework child before its anchor, then the highest
// priority, then the oldest.
func TestNextTakesAClaimThenAReworkChildThenByPriorityAndAge(t *testing.T) {
	q := newQueue()
	q.put("tk-old", stamp(9*time.Hour))
	q.put("tk-new", stamp(time.Hour))
	q.put("tk-urgent", stamp(0))
	q.edit("tk-urgent", func(b *fake.Bead) { b.Priority = 0 })
	q.put("tk-child", stamp(0), "task_kind", "rework", "anchor_bead", "tk-old")
	q.put("tk-left", stamp(0))
	q.edit("tk-left", func(b *fake.Bead) { b.Status = "in_progress" })
	want := []string{"tk-left", "tk-child", "tk-urgent", "tk-old", "tk-new"}
	for _, id := range want {
		ans := q.next(t)
		if took(ans) != id {
			t.Fatalf("took %q; want %s, in the order %v", took(ans), id, want)
		}
		q.edit(id, func(b *fake.Bead) { b.Status = "closed" })
	}
}

// A claim a session left in progress that something holds goes back to open,
// guarded on its claim, so what holds it decides when it is taken.
func TestNextReturnsAHeldClaimToOpen(t *testing.T) {
	q := newQueue()
	q.put("tk-parked", stamp(0))
	q.edit("tk-parked", func(b *fake.Bead) { b.Status = "in_progress" })
	q.s.Put(fake.Bead{ID: "tk-gate", Status: "open", IssueType: "gate"})
	q.waitOn("tk-parked", "tk-gate")
	ans := q.next(t)
	if took(ans) != "" || len(ans.Left) != 1 || ans.Left[0].Wrote == "" {
		t.Fatalf("took %q, left %+v", took(ans), ans.Left)
	}
	if row, _ := q.s.Row("tk-parked"); row.Status != "open" || row.Assignee != ref {
		t.Fatalf("the held claim reads %s, %s; want open and still the refinery's", row.Status, row.Assignee)
	}
	w := q.s.Writes()
	if len(w) != 1 || !slices.Contains(w[0].Args, "--if-status=in_progress") || !slices.Contains(w[0].Args, "--if-assignee="+ref) {
		t.Fatalf("writes %+v; want one guarded on the claim", w)
	}
}

// A bead with no branch, such as an effort's hand-off to bring its branch
// current, is taken as it is, for the session to read.
func TestNextTakesABeadWithNoBranch(t *testing.T) {
	q := newQueue()
	q.put("tk-handoff", stamp(0), "branch", "")
	if ans := q.next(t); took(ans) != "tk-handoff" {
		t.Fatalf("took %q, left %+v", took(ans), ans.Left)
	}
}

// demand reports whether Gas City would start a refinery session for b: in
// progress, or open with no wait edge onto a bead that has not closed, as bd's
// ready reads one.
func demand(b fake.Bead) bool {
	if b.Assignee != ref {
		return false
	}
	if b.Status == "in_progress" {
		return true
	}
	if b.Status != "open" {
		return false
	}
	return !slices.ContainsFunc(b.Edges, func(e gcbd.Edge) bool {
		return (e.Type == gcbd.EdgeBlocks || e.Type == gcbd.EdgeWaitsFor || e.Type == gcbd.EdgeConditionalBlocks) && e.Status != "closed"
	})
}

// No bead the search leaves stays demand for a session, so a session never
// starts for a bead the next search leaves again.
func TestNoBeadTheSearchLeavesStaysDemand(t *testing.T) {
	q := newQueue()
	q.put("tk-take", stamp(9))
	q.put("tk-held", stamp(0))
	q.s.Put(fake.Bead{ID: "tk-unit", Status: "open", IssueType: "task"})
	q.waitOn("tk-held", "tk-unit")
	q.put("tk-claim", stamp(0))
	q.edit("tk-claim", func(b *fake.Bead) { b.Status = "in_progress" })
	q.waitOn("tk-claim", "tk-unit")
	q.put("tk-busy", stamp(0), "branch", "polecat/shared")
	q.put("tk-busy-claim", stamp(0), "branch", "polecat/shared")
	q.edit("tk-busy-claim", func(b *fake.Bead) { b.Status = "in_progress" })
	q.s.Put(fake.Bead{ID: "tk-writer", Status: "in_progress", IssueType: "task", Assignee: "tools/gc-toolkit.polecat-1",
		Metadata: map[string]string{"branch": "polecat/shared"}})
	ans := q.next(t)
	if took(ans) != "tk-take" || len(ans.Failures) != 0 {
		t.Fatalf("took %q, failures %v", took(ans), ans.Failures)
	}
	for _, l := range ans.Left {
		if row, _ := q.s.Row(l.ID); demand(row) {
			t.Errorf("%s was left (%s) and is still demand: %s with edges %+v", l.ID, l.Why, row.Status, row.Edges)
		}
	}
	if len(ans.Left) != 4 {
		t.Errorf("left %+v; want the held bead, the held claim, and the bead and the claim whose branch another works", ans.Left)
	}
}

// A patrol wisp left assigned to the refinery is closed, guarded on what the
// search read of it, and never taken, so it is no demand; a wisp of another
// formula is left as it is, and a bead beside them is taken.
func TestNextClosesAPatrolWispLeftAssignedToTheRefinery(t *testing.T) {
	q := newQueue()
	q.s.Put(fake.Bead{ID: "tk-wisp-a", Title: patrolTitle, Status: "open", IssueType: "molecule", Assignee: ref, Ephemeral: true})
	q.s.Put(fake.Bead{ID: "tk-wisp-b", Title: patrolTitle, Status: "in_progress", IssueType: "molecule", Assignee: ref, Ephemeral: true})
	q.s.Put(fake.Bead{ID: "tk-wisp-c", Title: "mol-other", Status: "open", IssueType: "molecule", Assignee: ref, Ephemeral: true})
	q.put("tk-take", stamp(0))
	ans := q.next(t)
	if took(ans) != "tk-take" || len(ans.Failures) != 0 {
		t.Fatalf("took %q, failures %v; want tk-take and none", took(ans), ans.Failures)
	}
	for _, c := range []struct{ id, read, now string }{
		{"tk-wisp-a", "open", "closed"}, {"tk-wisp-b", "in_progress", "closed"}, {"tk-wisp-c", "open", "open"},
	} {
		row, _ := q.s.Row(c.id)
		if row.Status != c.now {
			t.Errorf("%s reads %s; want %s", c.id, row.Status, c.now)
		}
		if c.now == "closed" && !slices.ContainsFunc(q.s.Writes(), func(w fake.Write) bool {
			return w.ID == c.id && slices.Contains(w.Args, "--if-status="+c.read) && slices.Contains(w.Args, "--if-assignee="+ref)
		}) {
			t.Errorf("writes %+v; want %s's close guarded on %s and the refinery", q.s.Writes(), c.id, c.read)
		}
	}
	if !slices.Equal(leftIDs(ans), []string{"tk-wisp-a", "tk-wisp-b"}) {
		t.Errorf("left %+v; want the two patrol wisps", ans.Left)
	}
}

// A read that does not answer takes nothing, and an empty identity is no
// filter.
func TestNextReadsNothingWithoutAnAnswer(t *testing.T) {
	q := newQueue()
	q.put("tk-a", stamp(0))
	q.s.FindErr = errors.New("bd did not answer")
	if _, err := (&Search{Ledger: ledger.New(q.s), Refinery: ref}).Next(); err == nil {
		t.Fatal("a listing that failed answered")
	}
	if _, err := (&Search{Ledger: ledger.New(fake.New())}).Next(); err == nil {
		t.Fatal("an empty identity answered")
	}
}

// Of two claims left in progress that the search can take, it takes one and
// puts the other back to open, still the refinery's, since a drain releases to
// nobody a claim its session did not start.
func TestNextPutsTheClaimsItDoesNotTakeBackToOpen(t *testing.T) {
	q := newQueue()
	q.put("tk-a", stamp(0))
	q.put("tk-b", stamp(9))
	q.edit("tk-a", func(b *fake.Bead) { b.Status = "in_progress" })
	q.edit("tk-b", func(b *fake.Bead) { b.Status = "in_progress" })
	ans := q.next(t)
	other := map[string]string{"tk-a": "tk-b", "tk-b": "tk-a"}[took(ans)]
	if other == "" {
		t.Fatalf("took %q; want one of the two claims", took(ans))
	}
	if b, _ := q.s.Row(other); b.Status != "open" || b.Assignee != ref || len(ans.Failures) > 0 {
		t.Fatalf("%s is %s under %q, failures %v; want it open under the refinery", other, b.Status, b.Assignee, ans.Failures)
	}
}
