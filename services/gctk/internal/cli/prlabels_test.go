package cli

import (
	"path/filepath"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/prstatus"
)

// The landing order and the net keep the PRs' labels through prLabels, which
// hands the pr domain the labels prstatus keeps and names, each with the
// colour and the description a repository holds it with.
func TestTheLabelsAreKeptAsPRStatusNamesThem(t *testing.T) {
	db := filepath.Join(t.TempDir(), ".beads")
	l, err := landing(db, "rig/refinery")
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := l.Labels.(prLabels); !ok {
		t.Fatalf("the landing order keeps the labels through %T", l.Labels)
	}
	w, err := watcher(db)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := w.Labels.(prLabels); !ok || w.Origin == nil {
		t.Fatalf("the net clears the labels through %T, with an origin read %v", w.Labels, w.Origin != nil)
	}
	lw := prLabels{}
	if !lw.Kept("held: gate") || !lw.Kept("status: shipped") || lw.Kept("bug") {
		t.Fatal("the labels the landing order keeps are not prstatus's")
	}
	defined := prstatus.Defined()
	got := lw.Defined()
	if len(got) != len(defined) {
		t.Fatalf("the landing order names %d labels, prstatus %d", len(got), len(defined))
	}
	for i, d := range defined {
		if want := (gh.Label{Name: d.Name, Color: d.Color, Description: d.Description}); got[i] != want {
			t.Errorf("label %d is %+v, prstatus names %+v", i, got[i], want)
		}
	}
}
