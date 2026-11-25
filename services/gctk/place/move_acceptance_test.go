package place

import (
	"context"
	"encoding/json"
	"slices"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The move's store acceptance case runs it against the bd the city runs, on a
// scratch store (gcbdtest), so it pins what bd's set-state does with each
// shape the move writes or leaves: the swap of hold:mayor for hold:po in one
// write that files its event bead, hold:mayor beside hold:po, and no change on
// a second move. It runs only when GCTK_STORE_ACCEPTANCE=1 asks for it:
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
	shut := s.Create("a closed record", "--labels", "hold:mayor")
	s.Run("close", shut)
	s.Enter(t, "")

	city := &rtfake.Roster{RigList: []gascity.Rig{{Name: "scratch", Path: s.Dir, Prefix: "pm"}}}
	run := func() StoreMove {
		t.Helper()
		out, err := (&Move{City: city, Open: ledger.OpenStore}).Run(context.Background())
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
	events := func(id string) int {
		t.Helper()
		var rows []struct {
			Title string `json:"title"`
		}
		if err := json.Unmarshal([]byte(s.Run("list", "--parent", id, "--type", "event", "--all", "--json", "--limit", "0")), &rows); err != nil {
			t.Fatalf("bd list --parent %s: %v", id, err)
		}
		return len(rows)
	}

	first := run()
	if want := []string{old, both}; !slices.Equal(first.Moved, sorted(want)) || !slices.Equal(first.OnPO, []string{po}) || len(first.Left) != 1 || first.Left[0].ID != ext {
		t.Fatalf("the move = %+v, want %v moved, %s on hold:po and %s left", first, want, po, ext)
	}
	for id, want := range map[string][]string{
		old: {"hold:po", "learning"}, both: {"hold:po"}, po: {"hold:po"},
		ext: {"hold:external", "hold:mayor"}, shut: {"hold:mayor"},
	} {
		if got := labels(id); !slices.Equal(got, want) {
			t.Errorf("%s carries %v, want %v", id, got, want)
		}
	}
	if events(old) != 1 || events(both) != 1 || events(po) != 0 {
		t.Errorf("event beads: %d on the moved bead, %d on the one on both spellings, %d on the one on hold:po; want the set-state's one each and none", events(old), events(both), events(po))
	}

	second := run()
	if len(second.Moved) != 0 || !slices.Equal(second.OnPO, sorted([]string{old, both, po})) || events(old) != 1 || events(both) != 1 {
		t.Errorf("a second move = %+v, with %d and %d event beads; want nothing moved and no event filed", second, events(old), events(both))
	}
}

func sorted(ids []string) []string {
	out := slices.Clone(ids)
	slices.Sort(out)
	return out
}
