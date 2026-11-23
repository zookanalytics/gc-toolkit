package gate

import (
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// held is the alias the conversation tk-c's sitting goes by, which its claim
// records as the conversation's assignee.
const held = "gc-toolkit/gc-toolkit.tk-c"

// newStore holds the conversation tk-c, in progress under its sitting, and the
// work tk-w, open, in a rig's store.
func newStore() *fake.Store {
	s := fake.New()
	s.IDPrefix = "tk"
	s.Put(fake.Bead{ID: "tk-c", Title: "the conversation", Status: "in_progress", IssueType: "task", Assignee: held})
	s.Put(fake.Bead{ID: "tk-w", Title: "the work", Status: "open", IssueType: "task"})
	return s
}

func promises(s *fake.Store) *Promises {
	return &Promises{Ledger: ledger.New(s), InRig: func(string) (bool, bool, error) { return true, true, nil }, Alias: held}
}

func needsReview(work string) Request {
	return Request{Type: NeedsReview, Work: work, Conversation: "tk-c"}
}

func blocks(id string) gcbd.Edge { return gcbd.Edge{Type: gcbd.EdgeBlocks, ID: id, Status: "open"} }

// waitsOnGates is the gates the conversation waits on through its blocks edges.
func waitsOnGates(s *fake.Store) []string {
	row, _ := s.Row("tk-c")
	var out []string
	for _, e := range row.Edges {
		if g, ok := s.Row(e.ID); ok && e.Type == gcbd.EdgeBlocks && g.IssueType == "gate" {
			out = append(out, e.ID)
		}
	}
	return out
}

func TestCityCloses(t *testing.T) {
	for _, c := range []struct {
		issueType, awaitType string
		want                 bool
	}{
		{"gate", NeedsReview, true},
		{"gate", "human", false},
		{"gate", "", false},
		{"gate", "timer", false},
		{"task", NeedsReview, false},
	} {
		if got := CityCloses(c.issueType, c.awaitType); got != c.want {
			t.Errorf("CityCloses(%q, %q) = %v, want %v", c.issueType, c.awaitType, got, c.want)
		}
	}
}

func TestCreateFilesTheGateThatBlocksTheConversation(t *testing.T) {
	s := newStore()
	out, err := promises(s).Create(needsReview("tk-w"))
	if err != nil {
		t.Fatal(err)
	}
	if out.Found || out.Gate == "" {
		t.Fatalf("Create = %+v, want a gate filed now", out)
	}
	creates := s.Creates()
	if len(creates) != 1 || creates[0].ID != out.Gate {
		t.Fatalf("creates = %+v, want the one gate %s", creates, out.Gate)
	}
	if got := strings.Join(creates[0].Args, " "); got != "gate --type gctk:needs-review --await-id tk-w --blocks tk-c" {
		t.Errorf("the create's args = %q", got)
	}
	if creates[0].Title != Title("tk-w") {
		t.Errorf("the gate's title = %q, want %q", creates[0].Title, Title("tk-w"))
	}
	g, _ := s.Row(out.Gate)
	if g.IssueType != "gate" || g.AwaitType != NeedsReview || g.AwaitID != "tk-w" || g.Status != "open" {
		t.Errorf("the gate = %+v", g)
	}
	if got := waitsOnGates(s); len(got) != 1 || got[0] != out.Gate {
		t.Errorf("the conversation waits on %v, want %s", got, out.Gate)
	}
}

func TestCreateFindsTheOpenGateForTheSameWork(t *testing.T) {
	s := newStore()
	first, err := promises(s).Create(needsReview("tk-w"))
	if err != nil {
		t.Fatal(err)
	}
	again, err := promises(s).Create(needsReview("tk-w"))
	if err != nil {
		t.Fatal(err)
	}
	if !again.Found || again.Gate != first.Gate {
		t.Errorf("the second promise = %+v, want the gate %s found", again, first.Gate)
	}
	if n := len(s.Creates()); n != 1 {
		t.Errorf("%d creates, want the first alone", n)
	}
}

// A create that stopped between bd's two writes leaves a gate nothing waits
// on, and the next run files a gate that holds the conversation.
func TestCreateAfterAStoppedCreateFilesAFreshGate(t *testing.T) {
	s := newStore()
	s.GateEdgeless = true
	if _, err := promises(s).Create(needsReview("tk-w")); err == nil || Refused(err) {
		t.Fatalf("the stopped create = %v, want a write that did not land", err)
	}
	stray := s.Creates()[0].ID
	s.GateEdgeless = false
	out, err := promises(s).Create(needsReview("tk-w"))
	if err != nil {
		t.Fatal(err)
	}
	if out.Found || out.Gate == stray {
		t.Errorf("the next run = %+v, want a fresh gate beside the stray %s", out, stray)
	}
	if got := waitsOnGates(s); len(got) != 1 || got[0] != out.Gate {
		t.Errorf("the conversation waits on %v, want the fresh gate %s alone", got, out.Gate)
	}
}

// The work's own hold on the conversation is no stall: a PR the conversation
// holds can be promised.
func TestCreatePromisesAPRTheConversationHolds(t *testing.T) {
	s := newStore()
	s.Put(fake.Bead{ID: "tk-w", Title: "the PR", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-c")}})
	if _, err := promises(s).Create(needsReview("tk-w")); err != nil {
		t.Fatalf("Create = %v, want the PR the conversation holds promised", err)
	}
}

func TestCreateRefuses(t *testing.T) {
	cases := []struct {
		name string
		edit func(s *fake.Store, p *Promises) Request
		want string
	}{
		{"a type the pack does not define", func(*fake.Store, *Promises) Request {
			return Request{Type: "human", Work: "tk-w", Conversation: "tk-c"}
		}, "no gate type the pack defines"},
		{"a closed conversation", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-c", Status: "closed", IssueType: "task", Assignee: held})
			return needsReview("tk-w")
		}, "is closed"},
		{"a conversation in the operator's queue", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-c", Status: "open", IssueType: "task", Assignee: "human"})
			return needsReview("tk-w")
		}, "no conversation a sitting holds"},
		{"a conversation another sitting holds", func(_ *fake.Store, p *Promises) Request {
			p.Alias = "gc-toolkit/gc-toolkit.tk-other"
			return needsReview("tk-w")
		}, "not to the caller"},
		{"a caller whose alias only ends in the conversation's id", func(_ *fake.Store, p *Promises) Request {
			p.Alias = "tk-c"
			return needsReview("tk-w")
		}, "not to the caller"},
		{"a caller with no alias", func(_ *fake.Store, p *Promises) Request {
			p.Alias = ""
			return needsReview("tk-w")
		}, "not to the caller"},
		{"work in another store", func(*fake.Store, *Promises) Request { return needsReview("gc-w") }, "another store"},
		{"work the store does not hold", func(*fake.Store, *Promises) Request { return needsReview("tk-gone") }, "holds no tk-gone"},
		{"work that has closed", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-w", Status: "closed", IssueType: "task"})
			return needsReview("tk-w")
		}, "has closed"},
		{"work in the city's own store", func(_ *fake.Store, p *Promises) Request {
			p.InRig = func(string) (bool, bool, error) { return false, true, nil }
			return needsReview("tk-w")
		}, "the city's own store"},
		{"a second piece while a gate is open", func(s *fake.Store, p *Promises) Request {
			s.Put(fake.Bead{ID: "tk-w2", Status: "open", IssueType: "task"})
			if _, err := p.Create(needsReview("tk-w2")); err != nil {
				panic(err)
			}
			return needsReview("tk-w")
		}, "already waits on the open gate"},
		{"work that waits on the conversation through another bead", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-x", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-c")}})
			s.Put(fake.Bead{ID: "tk-w", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-x")}})
			return needsReview("tk-w")
		}, "through tk-x"},
		{"an ask on the work that waits on a piece the conversation holds", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-piece", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-c")}})
			s.Put(fake.Bead{ID: "tk-ask", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-piece")}})
			s.Put(fake.Bead{ID: "tk-w", Status: "blocked", IssueType: "task", Edges: []gcbd.Edge{blocks("tk-ask"), blocks("tk-c")}})
			return needsReview("tk-w")
		}, "through tk-piece"},
		{"a closed bead on the path", func(s *fake.Store, _ *Promises) Request {
			s.Put(fake.Bead{ID: "tk-x", Status: "closed", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeParentChild, ID: "tk-c", Status: "in_progress"}}})
			s.Put(fake.Bead{ID: "tk-w", Status: "open", IssueType: "task", Edges: []gcbd.Edge{{Type: gcbd.EdgeConditionalBlocks, ID: "tk-x", Status: "closed"}}})
			return needsReview("tk-w")
		}, "through tk-x"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := newStore()
			p := promises(s)
			req := c.edit(s, p)
			before := len(s.Creates())
			_, err := p.Create(req)
			if !Refused(err) || !strings.Contains(err.Error(), c.want) {
				t.Fatalf("Create = %v, want a refusal saying %q", err, c.want)
			}
			if n := len(s.Creates()); n != before {
				t.Errorf("the refusal filed %d gates", n-before)
			}
		})
	}
}

func TestCreateFailsOnAStoreThatDoesNotPlaceTheWork(t *testing.T) {
	s := newStore()
	p := promises(s)
	p.InRig = func(string) (bool, bool, error) { return false, false, errors.New("gc config show did not answer") }
	if _, err := p.Create(needsReview("tk-w")); err == nil || Refused(err) {
		t.Fatalf("Create = %v, want a read that failed", err)
	}
	if n := len(s.Creates()); n != 0 {
		t.Errorf("%d gates filed", n)
	}
}

func TestOpenListsTheOpenGatesOfThePacksTypes(t *testing.T) {
	s := newStore()
	s.Put(fake.Bead{ID: "tk-g1", Status: "open", IssueType: "gate", AwaitType: NeedsReview, AwaitID: "tk-w"})
	s.Put(fake.Bead{ID: "tk-g2", Status: "closed", IssueType: "gate", AwaitType: NeedsReview, AwaitID: "tk-w"})
	s.Put(fake.Bead{ID: "tk-g3", Status: "open", IssueType: "gate", AwaitType: "human", AwaitID: "ask"})
	rows, err := ledger.New(s).Find(ledger.ByID("tk-g1", "tk-g2", "tk-g3").WithClosed())
	if err != nil {
		t.Fatal(err)
	}
	got := Open(rows)
	if len(got) != 1 || got[0] != (Gate{ID: "tk-g1", Type: NeedsReview, Work: "tk-w"}) {
		t.Errorf("Open = %+v, want tk-g1 alone", got)
	}
}
