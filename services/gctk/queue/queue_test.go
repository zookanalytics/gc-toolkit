package queue

import (
	"errors"
	"fmt"
	"math/rand/v2"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// store is a [Store] over fixed answers. A bead it holds a row for and no
// answer about what holds it reads as clear. ready is the store's ready set,
// and worked the beads a live run works. Each read is recorded, so a test can
// tell what Order asked for, and fail names a read that errors.
type store struct {
	rows   map[string]Row
	holds  map[string]waits.Holds
	failed map[string]error
	ready  []string
	worked map[string]bool
	fail   string
	calls  []string
}

func (s *store) record(read string, ids []string) error {
	s.calls = append(s.calls, strings.TrimSpace(read+" "+strings.Join(ids, " ")))
	if s.fail == read {
		return fmt.Errorf("%s did not read", read)
	}
	return nil
}

func (s *store) Ready() ([]string, error) {
	if err := s.record("ready", nil); err != nil {
		return nil, err
	}
	return slices.Clone(s.ready), nil
}

func (s *store) Worked(ids []string) (map[string]bool, error) {
	if err := s.record("worked", ids); err != nil {
		return nil, err
	}
	out := map[string]bool{}
	for _, id := range ids {
		if s.worked[id] {
			out[id] = true
		}
	}
	return out, nil
}

func (s *store) Rows(ids []string) (map[string]Row, error) {
	if err := s.record("rows", ids); err != nil {
		return nil, err
	}
	out := map[string]Row{}
	for _, id := range ids {
		if r, ok := s.rows[id]; ok {
			out[id] = r
		}
	}
	return out, nil
}

func (s *store) Holds(ids []string) (map[string]waits.Holds, map[string]error, error) {
	if err := s.record("holds", ids); err != nil {
		return nil, nil, err
	}
	holds, failed := map[string]waits.Holds{}, map[string]error{}
	for _, id := range ids {
		if err := s.failed[id]; err != nil {
			failed[id] = err
			continue
		}
		h, ok := s.holds[id]
		if !ok {
			h = waits.Holds{ID: id, Status: waits.Clear}
		}
		holds[id] = h
	}
	return holds, failed, nil
}

func ids(ps []Place) []string {
	out := []string{}
	for _, p := range ps {
		out = append(out, p.ID)
	}
	return out
}

func placeOf(o Ordered, id string) (Place, bool) {
	for _, p := range append(slices.Clone(o.Queue), o.NotScheduled...) {
		if p.ID == id {
			return p, true
		}
	}
	return Place{}, false
}

func layerOf(o Ordered, id string) int {
	if p, ok := placeOf(o, id); ok {
		return p.Layer
	}
	return -1
}

// TestOrderGathersItsOwnInputs places work named by id, and reads through the
// store everything a place depends on: each piece's row and what holds it, the
// anchor of each bead it waits on, the store's ready set and the runs that
// work it.
func TestOrderGathersItsOwnInputs(t *testing.T) {
	polecat := "gc-toolkit/gc-toolkit.polecat"
	wait := func(id string) waits.Wait { return waits.Wait{ID: id, Type: "blocks", Status: "open"} }
	// tk-pr's own rework waits on nothing ahead of it, and tk-w1 waits on
	// tk-pr. Armed tk-w2 waits on question tk-q, which is no work named.
	// tk-held is routed and held for the Product Owner, and assigned tk-behind
	// waits on it. Nothing sends tk-idle, nor tk-stale, whose row still shows a
	// branch its ended run left, and routed tk-after waits on tk-idle. A live
	// run works tk-poured, whose pour cleared its route. hold:external holds
	// tk-ext.
	read := func() *store {
		return &store{
			rows: map[string]Row{
				"tk-pr":     {ID: "tk-pr", Status: "open", Priority: 2, CreatedAt: "2026-01-01", RoutedTo: polecat},
				"tk-rework": {ID: "tk-rework", Status: "open", Priority: 2, CreatedAt: "2026-01-09", Anchor: "tk-pr"},
				"tk-w1":     {ID: "tk-w1", Status: "open", Priority: 2, CreatedAt: "2026-01-02", RoutedTo: polecat},
				"tk-q":      {ID: "tk-q", Status: "open", Priority: 1, CreatedAt: "2026-01-01"},
				"tk-w2":     {ID: "tk-w2", Status: "open", Priority: 1, CreatedAt: "2026-01-03"},
				"tk-held":   {ID: "tk-held", Status: "open", Priority: 1, CreatedAt: "2026-01-04", RoutedTo: polecat, Labels: []string{"hold:mayor"}},
				"tk-behind": {ID: "tk-behind", Status: "open", Priority: 0, CreatedAt: "2026-01-05", Assignee: "gc-toolkit/gc-toolkit.mechanik"},
				"tk-idle":   {ID: "tk-idle", Status: "open", Priority: 2, CreatedAt: "2026-01-06"},
				"tk-poured": {ID: "tk-poured", Status: "open", Priority: 2, CreatedAt: "2026-01-07"},
				"tk-ext":    {ID: "tk-ext", Status: "open", Priority: 3, CreatedAt: "2026-01-08", RoutedTo: polecat, Labels: []string{" Hold:External "}},
				"tk-after":  {ID: "tk-after", Status: "open", Priority: 1, CreatedAt: "2026-01-09", RoutedTo: polecat},
				"tk-stale":  {ID: "tk-stale", Status: "open", Priority: 2, CreatedAt: "2026-01-10"},
			},
			holds: map[string]waits.Holds{
				"tk-pr":     {ID: "tk-pr", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-rework")}},
				"tk-w1":     {ID: "tk-w1", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-pr")}},
				"tk-w2":     {ID: "tk-w2", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-q")}, Arm: &waits.Arm{Target: polecat}},
				"tk-behind": {ID: "tk-behind", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-held")}},
				"tk-after":  {ID: "tk-after", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-idle")}},
				"tk-stale":  {ID: "tk-stale", Status: waits.Clear, InFlight: "carries branch"},
			},
			ready:  []string{"tk-held", "tk-idle", "tk-poured", "tk-ext", "tk-stale", "tk-elsewhere"},
			worked: map[string]bool{"tk-poured": true},
		}
	}
	named := []string{"tk-w1", "tk-pr", "tk-w2", "tk-held", "tk-behind", "tk-idle", "tk-poured", "tk-ext", "tk-after", "tk-stale"}

	t.Run("each place comes from the store's rows, waits' answers, its ready set and the runs", func(t *testing.T) {
		s := read()
		o, err := Order(named, s)
		if err != nil {
			t.Fatal(err)
		}
		if got, want := ids(o.Queue), []string{"tk-held", "tk-pr", "tk-poured", "tk-ext", "tk-behind", "tk-w2", "tk-after", "tk-w1"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v: tk-pr's own rework puts nothing ahead of it, and work behind work nothing sends stays behind it", got, want)
		}
		if got, want := ids(o.NotScheduled), []string{"tk-idle", "tk-stale"}; !slices.Equal(got, want) {
			t.Errorf("not scheduled = %v, want %v: the ready work nothing sends, a stamp its ended run left notwithstanding", got, want)
		}
		for id, want := range map[string]Place{
			"tk-pr":     {ID: "tk-pr", Layer: 0, Scheduled: true},
			"tk-w1":     {ID: "tk-w1", Layer: 1, Scheduled: true},
			"tk-w2":     {ID: "tk-w2", Layer: 1, Scheduled: true},
			"tk-held":   {ID: "tk-held", Layer: 0, Scheduled: false},
			"tk-behind": {ID: "tk-behind", Layer: 1, Scheduled: true},
			"tk-idle":   {ID: "tk-idle", Layer: 0, Scheduled: false},
			"tk-poured": {ID: "tk-poured", Layer: 0, Scheduled: true},
			"tk-ext":    {ID: "tk-ext", Layer: 0, Scheduled: false, Outside: true},
			"tk-after":  {ID: "tk-after", Layer: 1, Scheduled: true},
			"tk-stale":  {ID: "tk-stale", Layer: 0, Scheduled: false},
		} {
			if got, _ := placeOf(o, id); got != want {
				t.Errorf("%s is placed %+v, want %+v", id, got, want)
			}
		}
		if len(o.Unread) != 0 {
			t.Errorf("unread = %v, want none", o.Unread)
		}
		all := strings.Join(named, " ")
		want := []string{"rows " + all, "holds " + all, "rows tk-rework tk-q", "ready", "worked " + all}
		if !slices.Equal(s.calls, want) {
			t.Errorf("reads = %q, want %q: the waits' beads not yet read, once each, then the ready set and the runs", s.calls, want)
		}
	})

	t.Run("a live run sends a piece, held or not, and only a ready piece can be unsent", func(t *testing.T) {
		s := read()
		s.worked = map[string]bool{"tk-idle": true, "tk-ext": true}
		s.ready = []string{"tk-stale"}
		o, err := Order(named, s)
		if err != nil {
			t.Fatal(err)
		}
		if got, want := ids(o.NotScheduled), []string{"tk-stale"}; !slices.Equal(got, want) {
			t.Errorf("not scheduled = %v, want %v: tk-poured left the ready set, and a run works tk-idle", got, want)
		}
		if p, _ := placeOf(o, "tk-ext"); !p.Scheduled || p.Outside {
			t.Errorf("tk-ext is placed %+v, want sent by its run and not waiting outside the city", p)
		}
		if p, _ := placeOf(o, "tk-poured"); p.Scheduled {
			t.Errorf("tk-poured is placed %+v, want unsent once no live run works it", p)
		}
	})

	t.Run("work the store holds no row for, or whose waits it could not answer, has no place", func(t *testing.T) {
		s := read()
		s.rows["tk-after"] = Row{ID: "tk-after", Status: "open", Priority: 2, CreatedAt: "2026-01-06", RoutedTo: polecat}
		s.holds["tk-after"] = waits.Holds{ID: "tk-after", Status: waits.Blocked, Waits: []waits.Wait{wait("tk-w1")}}
		s.failed = map[string]error{"tk-w1": errors.New("its edges did not decode")}
		o, err := Order([]string{"tk-gone", "tk-w1", "tk-after"}, s)
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Equal(o.Unread, []string{"tk-gone", "tk-w1"}) {
			t.Errorf("unread = %v, want tk-gone and tk-w1, in the order named", o.Unread)
		}
		if got := ids(o.Queue); !slices.Equal(got, []string{"tk-after"}) || layerOf(o, "tk-after") != 1 {
			t.Errorf("queue = %+v, want tk-after in layer 1, behind a bead that is no work placed", o.Queue)
		}
		if s.calls[1] != "holds tk-w1 tk-after" {
			t.Errorf("reads = %q, want waits asked about the work the store holds alone", s.calls)
		}
	})

	t.Run("a read that fails returns its error and no order", func(t *testing.T) {
		for _, read1 := range []string{"rows", "holds", "ready", "worked"} {
			s := read()
			s.fail = read1
			o, err := Order(named, s)
			if err == nil || len(o.Queue)+len(o.NotScheduled)+len(o.Unread) != 0 {
				t.Errorf("a failed %s read gave %+v, %v; want its error and no order", read1, o, err)
			}
		}
	})

	t.Run("work named twice is placed once, and nothing named reads nothing", func(t *testing.T) {
		s := read()
		o, err := Order([]string{"tk-pr", "", "tk-pr"}, s)
		if err != nil || !slices.Equal(ids(o.Queue), []string{"tk-pr"}) || s.calls[0] != "rows tk-pr" {
			t.Errorf("Order = %+v, %v after reads %q; want tk-pr once", o, err, s.calls)
		}
		s = read()
		if o, err := Order(nil, s); err != nil || len(o.Queue)+len(o.NotScheduled)+len(o.Unread) != 0 || len(s.calls) != 0 {
			t.Errorf("Order of nothing = %+v, %v after reads %q", o, err, s.calls)
		}
	})
}

func TestOrder(t *testing.T) {
	work := func(id string, p int, created string, waits ...string) item {
		return item{id: id, priority: p, createdAt: created, status: "open", waits: waits, scheduled: true}
	}

	t.Run("what can go now comes first, then each layer in the pool's claim order", func(t *testing.T) {
		o := order([]item{
			work("tk-c", 2, "2026-01-03", "tk-a"),
			work("tk-b", 1, "2026-01-05"),
			work("tk-a", 2, "2026-01-01"),
			work("tk-d", 0, "2026-01-09", "tk-c"),
			work("tk-e", 2, "2026-01-01"),
		})
		if got, want := ids(o.Queue), []string{"tk-b", "tk-a", "tk-e", "tk-c", "tk-d"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v", got, want)
		}
		for id, want := range map[string]int{"tk-a": 0, "tk-b": 0, "tk-e": 0, "tk-c": 1, "tk-d": 2} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
	})

	t.Run("a bead sits one layer past the latest of what it waits on", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01"),
			work("tk-b", 2, "2026-01-02", "tk-a"),
			work("tk-c", 2, "2026-01-03", "tk-b"),
			work("tk-d", 0, "2026-01-04", "tk-a", "tk-c"),
		})
		if got := layerOf(o, "tk-d"); got != 3 {
			t.Errorf("tk-d is in layer %d, want 3, past tk-c", got)
		}
		if got, want := ids(o.Queue), []string{"tk-a", "tk-b", "tk-c", "tk-d"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v: a P0 never sits above what it waits on", got, want)
		}
	})

	t.Run("a wait on a bead that is no item puts it in layer 1", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01", "tk-question"),
			work("tk-b", 3, "2026-01-02"),
			work("tk-c", 2, "2026-01-03", "tk-a"),
		})
		for id, want := range map[string]int{"tk-a": 1, "tk-b": 0, "tk-c": 2} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
		if got, want := ids(o.Queue), []string{"tk-b", "tk-a", "tk-c"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v", got, want)
		}
	})

	t.Run("a status that keeps a bead from going puts it in layer 1, and a claim goes", func(t *testing.T) {
		deferred := work("tk-a", 0, "2026-01-01")
		deferred.status = "deferred"
		claimed := work("tk-b", 2, "2026-01-02")
		claimed.status = "in_progress"
		hooked := work("tk-c", 2, "2026-01-03")
		hooked.status = " Hooked "
		o := order([]item{deferred, claimed, hooked})
		for id, want := range map[string]int{"tk-a": 1, "tk-b": 0, "tk-c": 0} {
			if got := layerOf(o, id); got != want {
				t.Errorf("%s is in layer %d, want %d", id, got, want)
			}
		}
	})

	t.Run("ready work nothing sends comes after the queue, and work behind it stays in it", func(t *testing.T) {
		idle := work("tk-a", 1, "2026-01-01")
		idle.ready, idle.scheduled = true, false
		behind := work("tk-b", 1, "2026-01-02", "tk-a")
		behind.scheduled = false
		o := order([]item{idle, behind, work("tk-c", 1, "2026-01-03", "tk-b"), work("tk-d", 3, "2026-01-04")})
		if got, want := ids(o.Queue), []string{"tk-d", "tk-b", "tk-c"}; !slices.Equal(got, want) {
			t.Errorf("queue = %v, want %v: tk-b waits on tk-a, so it does not go though nothing sends it", got, want)
		}
		if got, want := ids(o.NotScheduled), []string{"tk-a"}; !slices.Equal(got, want) {
			t.Errorf("not scheduled = %v, want %v", got, want)
		}
		if p, _ := placeOf(o, "tk-b"); p.Scheduled || p.Layer != 1 {
			t.Errorf("tk-b is placed %+v, want unsent in layer 1", p)
		}
	})

	t.Run("ready work a hold holds or something sends stays in the queue", func(t *testing.T) {
		held := work("tk-a", 1, "2026-01-01")
		held.ready, held.held, held.scheduled = true, true, false
		outside := work("tk-b", 1, "2026-01-02")
		outside.ready, outside.held, outside.outside, outside.scheduled = true, true, true, false
		sent := work("tk-c", 1, "2026-01-03")
		sent.ready = true
		o := order([]item{held, outside, sent})
		if got, want := ids(o.Queue), []string{"tk-a", "tk-b", "tk-c"}; !slices.Equal(got, want) || len(o.NotScheduled) != 0 {
			t.Errorf("queue = %v and not scheduled = %v, want %v and none", got, ids(o.NotScheduled), want)
		}
		if p, _ := placeOf(o, "tk-b"); !p.Outside {
			t.Errorf("tk-b is placed %+v, want it waiting outside the city", p)
		}
	})

	t.Run("a cycle of waits ends, its beads in layer 1 at least", func(t *testing.T) {
		o := order([]item{
			work("tk-a", 2, "2026-01-01", "tk-b"),
			work("tk-b", 2, "2026-01-02", "tk-a"),
			work("tk-c", 2, "2026-01-03", "tk-c"),
		})
		if len(o.Queue) != 3 {
			t.Fatalf("queue = %+v, want all three", o.Queue)
		}
		for _, id := range []string{"tk-a", "tk-b"} {
			if got := layerOf(o, id); got < 1 {
				t.Errorf("%s is in layer %d, want 1 at least", id, got)
			}
		}
		if got := layerOf(o, "tk-c"); got != 0 {
			t.Errorf("tk-c waits only on itself and is in layer %d, want 0", got)
		}
	})
}

// TestNothingSitsAboveWhatItWaitsOn places many random graphs of waits, with
// ready beads, held beads and beads nothing sends among them, and holds every
// placement to the rule: within the queue and after it, a bead comes after
// every item it waits on, and after the queue is exactly the ready work that
// no hold holds and nothing sends.
func TestNothingSitsAboveWhatItWaitsOn(t *testing.T) {
	r := rand.New(rand.NewPCG(1, 2))
	for round := range 200 {
		n := 2 + r.IntN(30)
		var items []item
		for i := range n {
			it := item{id: fmt.Sprintf("tk-%02d", i), priority: r.IntN(4), createdAt: fmt.Sprintf("2026-01-%02d", 1+r.IntN(28)),
				status: "open", scheduled: r.IntN(5) > 0, ready: r.IntN(2) == 0, held: r.IntN(6) == 0}
			it.outside = it.held && r.IntN(2) == 0
			if r.IntN(8) == 0 {
				it.status = "deferred"
			}
			for j := range i {
				if r.IntN(6) == 0 {
					it.waits = append(it.waits, fmt.Sprintf("tk-%02d", j))
				}
			}
			if r.IntN(7) == 0 {
				it.waits = append(it.waits, "tk-question")
			}
			items = append(items, it)
		}
		r.Shuffle(len(items), func(i, j int) { items[i], items[j] = items[j], items[i] })
		o := order(items)
		byID := map[string]item{}
		for _, it := range items {
			byID[it.id] = it
		}
		if len(o.Queue)+len(o.NotScheduled) != n {
			t.Fatalf("round %d placed %d of %d", round, len(o.Queue)+len(o.NotScheduled), n)
		}
		for _, list := range [][]Place{o.Queue, o.NotScheduled} {
			at := map[string]int{}
			for i, p := range list {
				at[p.ID] = i
			}
			for i, p := range list {
				if it := byID[p.ID]; p.Scheduled != it.scheduled || p.Outside != it.outside {
					t.Fatalf("round %d: %s is placed %+v, want its own scheduled %v and outside %v", round, p.ID, p, it.scheduled, it.outside)
				}
				for _, w := range byID[p.ID].waits {
					if j, ok := at[w]; ok && j > i {
						t.Fatalf("round %d: %s sits above %s, which it waits on", round, p.ID, w)
					}
				}
			}
		}
		after := map[string]bool{}
		for _, p := range o.NotScheduled {
			after[p.ID] = true
		}
		for _, it := range items {
			if want := it.ready && !it.held && !it.scheduled; after[it.id] != want {
				t.Fatalf("round %d: %s (ready %v, held %v, scheduled %v) sits after the queue: %v, want %v",
					round, it.id, it.ready, it.held, it.scheduled, after[it.id], want)
			}
		}
	}
}

func TestWaiting(t *testing.T) {
	h := waits.Holds{ID: "tk-pr", Waits: []waits.Wait{
		{ID: "tk-rework"}, {ID: "tk-a"}, {ID: "tk-a", Ancestor: "tk-p"}, {ID: "tk-pr"}, {ID: "tk-b"},
	}}
	anchorOf := func(id string) string {
		if id == "tk-rework" {
			return "tk-pr"
		}
		return ""
	}
	if got, want := waiting(h, anchorOf), []string{"tk-a", "tk-b"}; !slices.Equal(got, want) {
		t.Errorf("waiting = %v, want %v: each wait once, less its own rework and itself", got, want)
	}
}

func TestScheduled(t *testing.T) {
	armed := waits.Holds{Arm: &waits.Arm{Target: "gc-toolkit/gc-toolkit.polecat"}}
	for _, c := range []struct {
		name               string
		h                  waits.Holds
		worked             bool
		routedTo, assignee string
		labels             []string
		want               bool
	}{
		{name: "a live run works it", worked: true, want: true},
		{name: "a stamp a run left, with no live run, sends nothing", h: waits.Holds{InFlight: "carries branch"}, want: false},
		{name: "armed", h: armed, want: true},
		{name: "routed", routedTo: "gc-toolkit/gc-toolkit.polecat", want: true},
		{name: "assigned", assignee: "gc-toolkit/gc-toolkit.mechanik", want: true},
		{name: "an arm that names no target sends nothing", h: waits.Holds{Arm: &waits.Arm{Target: " "}}, want: false},
		{name: "nothing", routedTo: " ", assignee: "", want: false},
		{name: "armed and held for the Product Owner", h: armed, labels: []string{"hold:mayor"}, want: false},
		{name: "routed and held outside the store", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"hold:external"}, want: false},
		{name: "assigned and held, in any spelling", assignee: "gc-toolkit/gc-toolkit.mechanik", labels: []string{"learning", " Hold:Mayor "}, want: false},
		{name: "worked and held", worked: true, labels: []string{"hold:mayor"}, want: true},
		{name: "routed, with a label that is no hold", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"learning", "hold:mayor-later"}, want: true},
		{name: "armed and waiting on a person", h: armed, labels: []string{"human"}, want: false},
		{name: "routed and waiting on a person, the label trimmed", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"learning", " human "}, want: false},
		{name: "assigned and waiting on a person", assignee: "gc-toolkit/gc-toolkit.mechanik", labels: []string{"human"}, want: true},
		{name: "worked and waiting on a person", worked: true, labels: []string{"human"}, want: true},
		{name: "routed, with labels that only resemble the human label", routedTo: "gc-toolkit/gc-toolkit.polecat", labels: []string{"Human", "humans"}, want: true},
	} {
		if got := scheduled(c.h, c.worked, c.routedTo, c.assignee, c.labels); got != c.want {
			t.Errorf("%s: scheduled = %v, want %v", c.name, got, c.want)
		}
	}
}

// The Product Owner's queue holds a bead held hold:mayor in every spelling the
// order reads a dispatch hold in, and no bead another hold or label holds.
func TestForProductOwner(t *testing.T) {
	for _, c := range []struct {
		labels []string
		want   bool
	}{
		{[]string{"hold:mayor"}, true},
		{[]string{"learning", " Hold:Mayor "}, true},
		{[]string{"HOLD:MAYOR"}, true},
		{[]string{"hold:external"}, false},
		{[]string{"hold:mayor-later", "xhold:mayor"}, false},
		{nil, false},
	} {
		if got := ForProductOwner(c.labels); got != c.want {
			t.Errorf("ForProductOwner(%q) = %v, want %v", c.labels, got, c.want)
		}
	}
}
