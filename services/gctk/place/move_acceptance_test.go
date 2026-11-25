package place

import (
	"context"
	"encoding/json"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The move's store acceptance case runs it against the bd the city runs, on a
// scratch store (gcbdtest), so it pins what bd's update does with each shape
// the move writes or leaves: the swap of hold:mayor for hold:po in one write
// that the bead's history records, hold:mayor beside hold:po, a hold another
// writer adds just before the write, and no change on a second move. It runs
// only when GCTK_STORE_ACCEPTANCE=1 asks for it:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./place -run TestStoreAcceptance -v
func TestStoreAcceptanceAMoveTakesTheQueueOntoHoldPO(t *testing.T) {
	if !gcbdtest.Asked() {
		t.Skip("the store acceptance cases run the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs them")
	}
	s := gcbdtest.New(t, "pm")
	old := s.Create("held on the earlier spelling", "--labels", "hold:mayor,learning")
	both := s.Create("held on both spellings", "--labels", "hold:mayor,hold:po")
	po := s.Create("held on hold:po", "--labels", "hold:po")
	ext := s.Create("held outside too", "--labels", "hold:external,hold:mayor")
	late := s.Create("held outside once the move read it", "--labels", "hold:mayor")
	shut := s.Create("a closed record", "--labels", "hold:mayor")
	s.Run("close", shut)
	s.Enter(t, "")

	city := &rtfake.Roster{RigList: []gascity.Rig{{Name: "scratch", Path: s.Dir, Prefix: "pm"}}}
	open := func(ctx context.Context, db string) (*ledger.Ledger, error) {
		return ledger.New(&another{Client: gcbd.New().WithContext(ctx).In(db), s: s, bead: late}), nil
	}
	run := func() StoreMove {
		t.Helper()
		out, err := (&Move{City: city, Open: open}).Run(context.Background())
		if err != nil || len(out.Stores) != 1 || out.Stores[0].Unread != "" {
			t.Fatalf("Run = %+v, %v", out, err)
		}
		return out.Stores[0]
	}
	labels := func(id string) []string {
		t.Helper()
		var rows []struct {
			Labels []string `json:"labels"`
		}
		if err := json.Unmarshal([]byte(s.Run("show", id, "--json")), &rows); err != nil || len(rows) != 1 {
			t.Fatalf("bd show %s: %v", id, err)
		}
		slices.Sort(rows[0].Labels)
		return rows[0].Labels
	}
	// history is the bead's history, each event as its type and the label or
	// value it names.
	history := func(id string) []string {
		t.Helper()
		var rows []struct {
			Type string `json:"event_type"`
			Old  string `json:"old_value"`
			New  string `json:"new_value"`
		}
		if err := json.Unmarshal([]byte(s.Run("history", id, "--events", "--json")), &rows); err != nil {
			t.Fatalf("bd history %s: %v", id, err)
		}
		var out []string
		for _, r := range rows {
			out = append(out, r.Type+" "+r.Old+r.New)
		}
		slices.Sort(out)
		return out
	}

	first := run()
	if want := []string{old, both, late}; !slices.Equal(first.Moved, sorted(want)) || !slices.Equal(first.OnPO, []string{po}) || len(first.Left) != 1 || first.Left[0].ID != ext {
		t.Fatalf("the move = %+v, want %v moved, %s on hold:po and %s left", first, want, po, ext)
	}
	for id, want := range map[string][]string{
		old: {"hold:po", "learning"}, both: {"hold:po"}, po: {"hold:po"},
		ext: {"hold:external", "hold:mayor"}, late: {"hold:external", "hold:po"}, shut: {"hold:mayor"},
	} {
		if got := labels(id); !slices.Equal(got, want) {
			t.Errorf("%s carries %v, want %v", id, got, want)
		}
	}
	for id, swap := range map[string][]string{
		old:  {"label_added hold:po", "label_removed hold:mayor"},
		both: {"label_removed hold:mayor"},
		late: {"label_added hold:po", "label_removed hold:mayor"},
	} {
		if got := history(id); !includes(got, swap) {
			t.Errorf("%s's history is %q, want the move's %q in it", id, got, swap)
		}
	}
	if got := history(po); slices.Contains(got, "label_removed hold:mayor") {
		t.Errorf("%s, on hold:po alone, was written: %q", po, got)
	}

	before := map[string][]string{old: history(old), both: history(both), late: history(late)}
	second := run()
	if len(second.Moved) != 0 || !slices.Equal(second.OnPO, sorted([]string{old, both, late, po})) {
		t.Errorf("a second move = %+v, want nothing moved", second)
	}
	for id, was := range before {
		if got := history(id); !slices.Equal(got, was) {
			t.Errorf("a second move wrote %s: its history went from %q to %q", id, was, got)
		}
	}
}

// another is the store adapter with another writer beside the move, which adds
// hold:external to bead just before the first write the move makes to it, by
// update or by set-state, so the case holds whichever write the move makes.
type another struct {
	*gcbd.Client
	s    *gcbdtest.Store
	bead string
	done bool
}

func (a *another) add(id string) {
	if id == a.bead && !a.done {
		a.done = true
		a.s.Run("label", "add", id, "hold:external")
	}
}

func (a *another) Update(id string, args ...string) (string, error) {
	a.add(id)
	return a.Client.Update(id, args...)
}

func (a *another) SetState(id, dimension, value, reason string) error {
	a.add(id)
	return a.Client.SetState(id, dimension, value, reason)
}

func includes(have, want []string) bool {
	for _, w := range want {
		if !slices.Contains(have, w) {
			return false
		}
	}
	return true
}

func sorted(ids []string) []string {
	out := slices.Clone(ids)
	slices.Sort(out)
	return out
}
