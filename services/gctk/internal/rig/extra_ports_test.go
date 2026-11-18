package rig

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gcfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

// A copy gets the number of ports the city gives the rig whose clone holds the
// checkout, matched through any symlink in either path, and a checkout of no
// rig gets none without a var being read.
func TestExtraPortsAreTheNumberTheCityGivesTheCheckoutsRig(t *testing.T) {
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	clone := filepath.Join(dir, "rig-a")
	if err := os.MkdirAll(filepath.Join(clone, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(dir, "link")
	if err := os.Symlink(clone, link); err != nil {
		t.Fatal(err)
	}
	rt := &gcfake.Runtime{
		RigList: []gascity.Rig{{Name: "hq", Path: dir, HQ: true}, {Name: "rig-a", Path: link}},
		Vars:    map[[3]string]string{{ExtraPortsFormula, "rig-a", ExtraPortsVar}: "2"},
	}
	n, note, err := ExtraPorts(rt, filepath.Join(clone, ".git"))
	if n != 2 || note != "" || err != nil {
		t.Errorf("a checkout of rig-a, which the city gives 2: %d, %q, %v; want 2, and no note or error", n, note, err)
	}
	if got, want := rt.VarsRead(), [][3]string{{"mol-rig-demo", "rig-a", "ui_serve_extra_ports"}}; !slices.Equal(got, want) {
		t.Errorf("read %v, want %v", got, want)
	}
	n, note, err = ExtraPorts(rt, filepath.Join(dir, "elsewhere", ".git"))
	if n != 0 || note != "" || err != nil || len(rt.VarsRead()) != 1 {
		t.Errorf("a checkout of no rig: %d, %q, %v, %d reads; want 0, no note or error, and no read", n, note, err, len(rt.VarsRead()))
	}
}

// The city's own answer decides, and every answer that gives no number says
// why the copy gets no port beyond its own, except a rig the city gives none.
func TestExtraPortsReadOnlyAWholeNumberAndSayWhyTheyAreNone(t *testing.T) {
	common := filepath.Join(t.TempDir(), "rig-a", ".git")
	rigs := []gascity.Rig{{Name: "rig-a", Path: filepath.Dir(common)}}
	key := [3]string{ExtraPortsFormula, "rig-a", ExtraPortsVar}
	for _, tc := range []struct {
		name string
		rt   *gcfake.Runtime
		n    int
		note string
		err  string
	}{
		{"a rig the city gives none", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: ""}}, 0, "", ""},
		{"a number in blanks", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: " 3 "}}, 3, "", ""},
		{"the most a copy takes", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: "16"}}, 16, "", ""},
		{"a rig map that does not read", &gcfake.Runtime{RigsErr: errors.New("gc is wedged")}, 0, "rig map did not read (gc is wedged)", ""},
		{"a var that does not read", &gcfake.Runtime{RigList: rigs, VarsErr: errors.New("no such formula")}, 0, "rig rig-a did not read (no such formula)", ""},
		{"a formula that declares no such var", &gcfake.Runtime{RigList: rigs}, 0, "mol-rig-demo declares no ui_serve_extra_ports", ""},
		{"a word", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: "two"}}, 0, "", `ui_serve_extra_ports = "two"`},
		{"a number below none", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: "-1"}}, 0, "", `= "-1"`},
		{"a port's own number", &gcfake.Runtime{RigList: rigs, Vars: map[[3]string]string{key: "8080"}}, 0, "", "from 0 to 16"},
	} {
		n, note, err := ExtraPorts(tc.rt, common)
		switch {
		case n != tc.n:
			t.Errorf("%s: %d ports, want %d", tc.name, n, tc.n)
		case tc.note == "" && note != "", tc.note != "" && (!strings.Contains(note, tc.note) || !strings.HasSuffix(note, "no loopback port beyond its own")):
			t.Errorf("%s: note %q, want one saying %q", tc.name, note, tc.note)
		case tc.err == "" && err != nil, tc.err != "" && (err == nil || !strings.Contains(err.Error(), tc.err)):
			t.Errorf("%s: error %v, want one saying %q", tc.name, err, tc.err)
		}
	}
}

// The formula the rule reads the var from declares it, with a default that
// gives a rig no port beyond the copy's own and a description that names the
// most a rig is given.
func TestTheFormulaDeclaresTheExtraPortsVar(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "formulas", ExtraPortsFormula+".toml"))
	if err != nil {
		t.Fatal(err)
	}
	head := "[vars." + ExtraPortsVar + "]\n"
	_, block, found := strings.Cut(string(raw), head)
	if !found {
		t.Fatalf("%s declares no %s", ExtraPortsFormula, ExtraPortsVar)
	}
	block, _, _ = strings.Cut(block, "\n[")
	if !strings.Contains(block, `default = "0"`) || !strings.Contains(block, fmt.Sprintf("from 0 to %d", MaxExtraPorts)) {
		t.Errorf("%s's %s is %q, want the default \"0\" and a description saying from 0 to %d", ExtraPortsFormula, ExtraPortsVar, block, MaxExtraPorts)
	}
}
