package park

import (
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
)

// newStore is a store holding the epic tk-epic, its children tk-c1 and tk-c2,
// tk-c1's child tk-g1, and the bead tk-other beside them. It files a gate
// under their prefix, since the ledger writes no wait edge between two.
func newStore() *fake.Store {
	s := fake.New()
	s.IDPrefix = "tk"
	s.Put(fake.Bead{ID: "tk-epic", Title: "the epic", Status: "open", IssueType: "epic"})
	s.Put(fake.Bead{ID: "tk-c1", Title: "child one", Status: "open", IssueType: "task", Edges: []gcbd.Edge{child("tk-epic")}})
	s.Put(fake.Bead{ID: "tk-c2", Title: "child two", Status: "open", IssueType: "task", Edges: []gcbd.Edge{child("tk-epic")}})
	s.Put(fake.Bead{ID: "tk-g1", Title: "grandchild", Status: "open", IssueType: "task", Edges: []gcbd.Edge{child("tk-c1")}})
	s.Put(fake.Bead{ID: "tk-other", Title: "another bead", Status: "open", IssueType: "task"})
	return s
}

func child(parent string) gcbd.Edge {
	return gcbd.Edge{Type: gcbd.EdgeParentChild, ID: parent, Status: "open"}
}

// run pours a live graph.v2 run for bead under root, through convoy, with its
// load-context step open when atLoad says so and closed otherwise.
func run(s *fake.Store, bead, root, convoy string, atLoad bool) {
	s.Put(fake.Bead{ID: convoy, Status: "open", IssueType: "convoy", Edges: []gcbd.Edge{{Type: "tracks", ID: bead, Status: "open"}}})
	s.Put(fake.Bead{ID: root, Status: "in_progress", Metadata: map[string]string{
		"gc.kind": "workflow", "gc.formula_contract": "graph.v2", "gc.input_convoy_id": convoy}})
	status := "closed"
	if atLoad {
		status = "open"
	}
	s.Put(fake.Bead{ID: root + ".lc", Status: status, Metadata: map[string]string{
		"gc.root_bead_id": root, "gc.step_ref": "mol-polecat-work.load-context"}})
}

func parks(s gcbd.Store) *Parks { return &Parks{Ledger: ledger.New(s)} }

// blocksOnto is the beads id waits on through a blocks edge.
func blocksOnto(s *fake.Store, id string) []string {
	row, _ := s.Row(id)
	var out []string
	for _, e := range row.Edges {
		if e.Type == gcbd.EdgeBlocks {
			out = append(out, e.ID)
		}
	}
	return out
}

func TestParkFilesAGateBornWithItsEdge(t *testing.T) {
	s := newStore()
	out, err := parks(s).Park(Request{Bead: "tk-epic", Text: "  Parked\tuntil the   board lands ", Body: "the detail", BodySet: true})
	if err != nil {
		t.Fatalf("Park: %v", err)
	}
	creates := s.Creates()
	if len(creates) != 1 {
		t.Fatalf("creates = %v, want one gate", creates)
	}
	gate, _ := s.Row(out.Blocker)
	if gate.IssueType != "gate" || gate.Title != "Parked until the board lands" || gate.Description != "the detail" {
		t.Errorf("gate = %+v, want a gate titled with the text on one line and described by --body", gate)
	}
	if got := blocksOnto(s, "tk-epic"); !slices.Equal(got, []string{out.Blocker}) {
		t.Errorf("tk-epic waits on %v, want the gate %s, by the edge it was born with", got, out.Blocker)
	}
	if !slices.Contains(creates[0].Args, "blocks:tk-epic") {
		t.Errorf("the create's args %v carry no blocks:tk-epic, so the edge was not born with the gate", creates[0].Args)
	}
	if len(s.EdgeWrites()) != 0 {
		t.Errorf("edge writes %v, want none beside the create", s.EdgeWrites())
	}
	lines := out.Lines("tk-epic")
	if lines[0] != "park "+out.Blocker+" holds tk-epic: Parked until the board lands" {
		t.Errorf("first line = %q", lines[0])
	}
	if want := "held, not started: tk-epic tk-c1 tk-c2 tk-g1"; lines[1] != want {
		t.Errorf("held line = %q, want %q: the bead and every bead under it, through any depth", lines[1], want)
	}
}

func TestParkWithNoBodyDescribesTheRelease(t *testing.T) {
	s := newStore()
	out, err := parks(s).Park(Request{Bead: "tk-c2", Text: "not now"})
	if err != nil {
		t.Fatalf("Park: %v", err)
	}
	gate, _ := s.Row(out.Blocker)
	if !strings.Contains(gate.Description, "Closing this gate releases it") || !strings.Contains(gate.Description, "gc bd dep remove <bead> <this gate>") {
		t.Errorf("description = %q, want the default naming the release and the one-bead release", gate.Description)
	}
}

func TestParkAgainFilesNoSecondGateAndTakesANewBody(t *testing.T) {
	s := newStore()
	p := parks(s)
	first, err := p.Park(Request{Bead: "tk-epic", Text: "hold it"})
	if err != nil {
		t.Fatalf("first Park: %v", err)
	}
	again, err := p.Park(Request{Bead: "tk-epic", Text: "hold   it"})
	if err != nil || again.Blocker != first.Blocker || !again.Reused || again.Described {
		t.Fatalf("second Park = %+v, %v; want the same gate reused, its description untouched", again, err)
	}
	body, err := p.Park(Request{Bead: "tk-epic", Text: "hold it", Body: "new detail", BodySet: true})
	if err != nil || body.Blocker != first.Blocker || !body.Described {
		t.Fatalf("Park with a new --body = %+v, %v; want the same gate, described anew", body, err)
	}
	if gate, _ := s.Row(first.Blocker); gate.Description != "new detail" {
		t.Errorf("description = %q, want the re-run's --body", gate.Description)
	}
	if n := len(s.Creates()); n != 1 {
		t.Errorf("creates = %d, want one gate across three parks", n)
	}
	same, err := p.Park(Request{Bead: "tk-epic", Text: "hold it", Body: "new detail", BodySet: true})
	if err != nil || same.Described {
		t.Errorf("a re-run with the body the gate already has = %+v, %v; want nothing written", same, err)
	}
}

// A gate of another kind under the same title is not a park: a human gate, a
// gate with an await type, and a gate with metadata each belong to something
// else, so the park files its own.
func TestParkAdoptsOnlyAGateInItsOwnShape(t *testing.T) {
	for _, tc := range []struct {
		name string
		gate fake.Bead
	}{
		{"a human gate", fake.Bead{AwaitType: "human"}},
		{"a timer gate", fake.Bead{AwaitType: "timer"}},
		{"a stamped gate", fake.Bead{Metadata: map[string]string{"gc.kind": "x"}}},
		{"a closed gate", fake.Bead{Status: "closed"}},
		{"a task", fake.Bead{IssueType: "task"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore()
			g := tc.gate
			g.ID, g.Title = "tk-gx", "hold it"
			if g.Status == "" {
				g.Status = "open"
			}
			if g.IssueType == "" {
				g.IssueType = "gate"
			}
			s.Put(g)
			s.Put(fake.Bead{ID: "tk-epic", Title: "the epic", Status: "open", IssueType: "epic",
				Edges: []gcbd.Edge{{Type: gcbd.EdgeBlocks, ID: "tk-gx", Status: g.Status}}})
			out, err := parks(s).Park(Request{Bead: "tk-epic", Text: "hold it"})
			if err != nil || out.Reused || out.Blocker == "tk-gx" {
				t.Fatalf("Park = %+v, %v; want a gate of its own beside %s", out, err, tc.name)
			}
		})
	}
}

func TestParkCapIsTheHeadline(t *testing.T) {
	s := newStore()
	at := strings.Repeat("é", lifecycle.TakeawayMax)
	if _, err := parks(s).Park(Request{Bead: "tk-c1", Text: at}); err != nil {
		t.Fatalf("a title of exactly the cap: %v", err)
	}
	_, err := parks(s).Park(Request{Bead: "tk-c2", Text: at + "x"})
	if !Refused(err) || !strings.Contains(err.Error(), "the cap is 140") || !strings.Contains(err.Error(), "--body") {
		t.Fatalf("a title over the cap = %v, want it refused whole, naming the cap and --body", err)
	}
	if n := len(s.Creates()); n != 1 {
		t.Errorf("creates = %d, want only the park under the cap", n)
	}
}

func TestParkRefusesWhatItDoesNotPark(t *testing.T) {
	for _, tc := range []struct {
		name string
		req  Request
		prep func(*fake.Store)
		want string
	}{
		{"both forms", Request{Bead: "tk-c1", Text: "x", WaitingOn: "tk-other"}, nil, "two forms"},
		{"neither form", Request{Bead: "tk-c1"}, nil, "--waiting-on <bead-id>"},
		{"a body beside --waiting-on", Request{Bead: "tk-c1", WaitingOn: "tk-other", BodySet: true}, nil, "--body describes the gate"},
		{"an empty text", Request{Bead: "tk-c1", Text: " \n "}, nil, "one-line headline"},
		{"a closed bead", Request{Bead: "tk-c1", Text: "x"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-c1", Status: "closed", IssueType: "task"})
		}, "is closed"},
		{"waiting on itself", Request{Bead: "tk-c1", WaitingOn: "tk-c1"}, nil, "itself"},
		{"waiting on another store", Request{Bead: "tk-c1", WaitingOn: "zz-1"}, nil, "another store"},
		{"waiting on a bead under it", Request{Bead: "tk-epic", WaitingOn: "tk-g1"}, nil, "its own part"},
		{"waiting on a closed bead", Request{Bead: "tk-c1", WaitingOn: "tk-other"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-other", Status: "closed", IssueType: "task"})
		}, "is closed"},
		{"waiting on a pinned bead", Request{Bead: "tk-c1", WaitingOn: "tk-other"}, func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-other", Status: "pinned", IssueType: "task"})
		}, "is pinned"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore()
			if tc.prep != nil {
				tc.prep(s)
			}
			_, err := parks(s).Park(tc.req)
			if !Refused(err) || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("Park = %v, want a refusal naming %q", err, tc.want)
			}
			if len(s.Writes())+len(s.Creates())+len(s.EdgeWrites()) != 0 {
				t.Errorf("a refusal wrote %v %v %v", s.Writes(), s.Creates(), s.EdgeWrites())
			}
		})
	}
}

// A bead in flight takes no park of its own: its edge would hold its merge and
// its close. The refusal names its parent, whose park holds what has not
// started and leaves the bead running.
func TestParkRefusesABeadInFlight(t *testing.T) {
	for _, tc := range []struct {
		name string
		prep func(*fake.Store)
		why  string
	}{
		{"claimed", func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-c1", Status: "in_progress", Assignee: "a", IssueType: "task", Edges: []gcbd.Edge{child("tk-epic")}})
		}, "status in_progress"},
		{"carrying merge_result", func(s *fake.Store) {
			s.Put(fake.Bead{ID: "tk-c1", Status: "open", IssueType: "task", Metadata: map[string]string{"merge_result": "pull_request"},
				Edges: []gcbd.Edge{child("tk-epic")}})
		}, "merge_result"},
		{"worked past load-context", func(s *fake.Store) { run(s, "tk-c1", "tk-r1", "tk-cv1", false) }, "workflow tk-r1 past load-context"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := newStore()
			tc.prep(s)
			_, err := parks(s).Park(Request{Bead: "tk-c1", Text: "hold it"})
			if !Refused(err) || !strings.Contains(err.Error(), tc.why) || !strings.Contains(err.Error(), "Park tk-epic instead") {
				t.Fatalf("Park = %v, want a refusal naming why (%s) and the parent to park", err, tc.why)
			}
			if len(s.Creates()) != 0 {
				t.Errorf("a refused park filed %v", s.Creates())
			}
		})
	}
}

// What a park holds and what it leaves running: a member in flight keeps
// running, one with a run load-context still holds is named as poured, and an
// armed member is held, since its start waits on the park too.
func TestParkSaysWhatItHoldsAndWhatItLeavesRunning(t *testing.T) {
	s := newStore()
	s.Put(fake.Bead{ID: "tk-c2", Status: "in_progress", Assignee: "polecat", IssueType: "task", Edges: []gcbd.Edge{child("tk-epic")}})
	run(s, "tk-g1", "tk-r1", "tk-cv1", true)
	s.Put(fake.Bead{ID: "tk-c3", Status: "open", IssueType: "task", Edges: []gcbd.Edge{child("tk-epic")},
		Metadata: map[string]string{"gc.dispatch_when_ready": "gc-toolkit/gc-toolkit.polecat"}})
	run(s, "tk-c3", "tk-r3", "tk-cv3", true)
	out, err := parks(s).Park(Request{Bead: "tk-epic", Text: "hold it"})
	if err != nil {
		t.Fatalf("Park: %v", err)
	}
	if want := []string{"tk-epic", "tk-c1", "tk-c3"}; !slices.Equal(sorted(out.Held), sorted(want)) {
		t.Errorf("held = %v, want %v", out.Held, want)
	}
	if len(out.Flight) != 1 || out.Flight[0].ID != "tk-c2" || out.Flight[0].Why != "status in_progress" {
		t.Errorf("flight = %+v, want tk-c2 in progress", out.Flight)
	}
	if len(out.Poured) != 1 || out.Poured[0] != (Poured{ID: "tk-g1", Root: "tk-r1"}) {
		t.Errorf("poured = %+v, want tk-g1 under tk-r1", out.Poured)
	}
	lines := strings.Join(out.Lines("tk-epic"), "\n")
	for _, want := range []string{"in flight, keeps running: tk-c2 (status in_progress)",
		"poured before the park, waiting at load-context: tk-g1 (workflow tk-r1)"} {
		if !strings.Contains(lines, want) {
			t.Errorf("lines %q lack %q", lines, want)
		}
	}
}

func TestParkBehindABead(t *testing.T) {
	s := newStore()
	out, err := parks(s).Park(Request{Bead: "tk-epic", WaitingOn: "tk-other"})
	if err != nil || out.Blocker != "tk-other" || out.Title != "another bead" {
		t.Fatalf("Park = %+v, %v; want tk-epic parked behind tk-other", out, err)
	}
	if got := s.EdgeWrites(); len(got) != 1 || got[0] != (fake.Edge{ID: "tk-epic", Far: "tk-other", Type: gcbd.EdgeBlocks}) {
		t.Errorf("edge writes = %v, want one blocks edge from tk-epic onto tk-other", got)
	}
	if len(s.Creates()) != 0 {
		t.Errorf("--waiting-on filed %v, want no gate", s.Creates())
	}
}

func TestParkBehindABeadWhoseEdgeIsRefused(t *testing.T) {
	s := newStore()
	s.EdgeErr = errors.New("bd refused the edge")
	_, err := parks(s).Park(Request{Bead: "tk-epic", WaitingOn: "tk-other"})
	if err == nil || Refused(err) || !strings.Contains(err.Error(), "is NOT blocked by tk-other") ||
		!strings.Contains(err.Error(), "gc bd dep add tk-epic tk-other -t blocks") {
		t.Fatalf("Park = %v, want a failure naming the edge to wire by hand", err)
	}
}

// A listing that does not read leaves the bead's workflows unproven, so the park
// stops rather than guess, and writes nothing.
func TestParkStopsWhenTheStoreDoesNotList(t *testing.T) {
	s := newStore()
	s.FindErr = &gcbd.ReadError{Reason: "the store did not answer"}
	_, err := parks(s).Park(Request{Bead: "tk-epic", Text: "hold it"})
	if err == nil || Refused(err) {
		t.Fatalf("Park = %v, want a failure", err)
	}
	if len(s.Creates()) != 0 {
		t.Errorf("a park whose survey failed filed %v", s.Creates())
	}
}

func TestParkOfABeadTheStoreDoesNotHold(t *testing.T) {
	_, err := parks(newStore()).Park(Request{Bead: "tk-gone", Text: "x"})
	if err == nil || Refused(err) || !strings.Contains(err.Error(), "does not resolve") {
		t.Fatalf("Park = %v, want a failure saying the bead does not resolve", err)
	}
}

// lossy is a store whose create files the bead and then loses its answer, as
// bd answers a create whose commit result it lost.
type lossy struct{ *fake.Store }

func (l lossy) Create(title string, args ...string) (string, error) {
	_, _ = l.Store.Create(title, args...)
	return "", errors.New("bd's create exited 1, so whether it filed the bead is unknown")
}

func TestParkFindsTheGateACreateFiledAndLostTheAnswerTo(t *testing.T) {
	s := newStore()
	out, err := parks(lossy{s}).Park(Request{Bead: "tk-epic", Text: "hold it"})
	if err != nil || out.Blocker == "" {
		t.Fatalf("Park = %+v, %v; want the gate the lost create filed", out, err)
	}
	if got := blocksOnto(s, "tk-epic"); !slices.Equal(got, []string{out.Blocker}) {
		t.Errorf("tk-epic waits on %v, want %s", got, out.Blocker)
	}
}

func TestParkWhoseCreateFiledNothing(t *testing.T) {
	s := newStore()
	s.CreateErr = errors.New("bd refused the create")
	_, err := parks(s).Park(Request{Bead: "tk-epic", Text: "hold it"})
	if err == nil || Refused(err) || !strings.Contains(err.Error(), "nothing holds tk-epic") {
		t.Fatalf("Park = %v, want a failure saying nothing holds the bead", err)
	}
}

func sorted(in []string) []string {
	out := slices.Clone(in)
	slices.Sort(out)
	return out
}
