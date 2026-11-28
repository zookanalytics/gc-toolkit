package reaction

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
	"time"

	rtfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/gcbdtest"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
)

// Intake's store acceptance case runs its hold against the bd the city runs, on
// a scratch store (gcbdtest), while another writer adds hold:external to the
// subject just before intake's write. It pins what bd does with that write,
// which the fake store only stands in for: the update keeps the other hold and
// records the label it adds in the bead's history, where `bd set-state
// hold=mayor` after the same add swaps hold:external out. It runs only when
// GCTK_STORE_ACCEPTANCE=1 asks for it:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./reaction -run TestStoreAcceptance -v
func TestStoreAcceptanceIntakeKeepsAnotherWritersHold(t *testing.T) {
	if !gcbdtest.Asked() {
		t.Skip("the store acceptance cases run the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs them")
	}
	s := gcbdtest.New(t, "ra")
	subject := s.Create("new work no epic holds", "-t", "task")
	swapped := s.Create("new work held with set-state", "-t", "task")
	s.Enter(t, "")

	r := &Reactions{
		Ledger:   ledger.New(&anotherWriter{Client: gcbd.New().In(s.DB()), s: s, bead: subject}),
		Runtime:  &rtfake.Runtime{},
		Rig:      "scratch",
		Takeaway: func(takeaway.Request) (string, error) { return "", nil },
		Now:      func() time.Time { return time.Date(2026, 11, 25, 7, 0, 0, 0, time.UTC) },
		Log:      func(string) {},
	}
	d := &Dispose{Bead: subject, Disposition: Actionable, Reason: "r", Takeaway: "t", Route: "scratch/scratch.polecat", Run: "ra-root", By: "proactive"}
	if out, err := r.Dispose(d); err != nil || out.Target != "held for placement" {
		t.Fatalf("Dispose = %+v, %v", out, err)
	}
	row := storeRow(t, s, subject)
	if want := []string{"hold:external", "hold:mayor"}; !slices.Equal(row.Labels, want) {
		t.Errorf("the subject carries %v, want %v", row.Labels, want)
	}
	if !strings.Contains(row.Notes, "Held for placement instead of reaching scratch/scratch.polecat") {
		t.Errorf("the subject's notes hold no reason for the hold: %q", row.Notes)
	}
	hist := storeHistory(t, s, subject)
	if !slices.Contains(hist, "label_added hold:mayor") || slices.Contains(hist, "label_removed hold:external") {
		t.Errorf("the subject's history is %q, want hold:mayor added and hold:external never removed", hist)
	}

	s.Run("label", "add", swapped, "hold:external")
	s.Run("set-state", swapped, "hold=mayor", "--reason", "held for placement")
	if got, want := storeRow(t, s, swapped).Labels, []string{"hold:mayor"}; !slices.Equal(got, want) {
		t.Errorf("after set-state the bead carries %v, want %v, the swap intake's update is built to avoid (docs/steering.md)", got, want)
	}
}

// anotherWriter is the store adapter with another writer beside intake, which
// adds hold:external to bead just before the first update that adds a label to
// it.
type anotherWriter struct {
	*gcbd.Client
	s    *gcbdtest.Store
	bead string
	done bool
}

func (a *anotherWriter) Update(id string, args ...string) (string, error) {
	if id == a.bead && !a.done && slices.Contains(args, "--add-label") {
		a.done = true
		a.s.Run("label", "add", id, "hold:external")
	}
	return a.Client.Update(id, args...)
}

// storeBead is a bead's labels and notes as bd shows them.
type storeBead struct {
	Labels []string `json:"labels"`
	Notes  string   `json:"notes"`
}

// storeRow is the bead as bd shows it, its labels sorted.
func storeRow(t *testing.T, s *gcbdtest.Store, id string) storeBead {
	t.Helper()
	var rows []storeBead
	if err := json.Unmarshal([]byte(s.Run("show", id, "--json")), &rows); err != nil || len(rows) != 1 {
		t.Fatalf("bd show %s: %v", id, err)
	}
	slices.Sort(rows[0].Labels)
	return rows[0]
}

// storeHistory is the bead's audit events, each as its type and the label or
// value it names.
func storeHistory(t *testing.T, s *gcbdtest.Store, id string) []string {
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
	return out
}
