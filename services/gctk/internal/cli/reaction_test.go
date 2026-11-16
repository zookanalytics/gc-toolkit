package cli

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
)

// stubLoggingGC puts a gc on PATH that logs each call and answers the rig list
// with rigs, and returns the log's path.
func stubLoggingGC(t *testing.T, rigs string) string {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "log")
	stub := "#!/bin/sh\necho \"$*\" >> '" + log + "'\ncase \"$1 $2\" in \"rig list\") printf '%s' \"$STUB_RIGS\" ;; esac\nexit 0\n"
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_RIGS", rigs)
	return log
}

// A call the dispose refuses for what it asks exits 2 with the reason and the
// usage, before Gas City or the store is asked anything.
func TestReactionDisposeRefusesUsageBeforeAnyCall(t *testing.T) {
	log := stubLoggingGC(t, `{"rigs":[]}`)
	t.Setenv("GC_RIG", "gc-toolkit")
	for name, args := range map[string][]string{
		"an unknown exit":     {"reaction", "dispose", "tk-sub", "--disposition", "sideways", "--reason", "r", "--takeaway", "t"},
		"another exit's flag": {"reaction", "dispose", "tk-sub", "--disposition", "ruling", "--reason", "r", "--takeaway", "t", "--route", "gc-toolkit/gc-toolkit.polecat"},
		"the keeper":          {"reaction", "dispose", "tk-sub", "--disposition", "actionable", "--reason", "r", "--takeaway", "t", "--assign", "gc-toolkit.keeper"},
		"no bead":             {"reaction", "dispose", "--disposition", "ruling", "--reason", "r", "--takeaway", "t"},
	} {
		var out, errb bytes.Buffer
		if code := Run(args, "test", &out, &errb); code != 2 {
			t.Errorf("%s exited %d, want 2: %s", name, code, errb.String())
		}
		if !strings.Contains(errb.String(), "Usage:") {
			t.Errorf("%s printed no usage: %s", name, errb.String())
		}
	}
	if raw, _ := os.ReadFile(log); len(raw) != 0 {
		t.Errorf("a refused call asked gc %q", raw)
	}
}

// The subject's store is the .beads directory of the rig whose prefix is the
// bead's, from the city's rig list, and none when no such rig holds one, so
// that gc routes the bead instead.
func TestReactionDisposeFindsTheSubjectsStoreByItsPrefix(t *testing.T) {
	rig := t.TempDir()
	if err := os.Mkdir(filepath.Join(rig, ".beads"), 0o755); err != nil {
		t.Fatal(err)
	}
	rt := &fake.Runtime{RigList: []gascity.Rig{{Name: "town", Path: t.TempDir(), Prefix: "hq", HQ: true}, {Name: "gc-toolkit", Path: rig, Prefix: "tk"}}}
	if got := subjectStore(rt, "tk-sub"); got != filepath.Join(rig, ".beads") {
		t.Errorf("tk-sub's store is %q", got)
	}
	if got := subjectStore(rt, "hq-sub"); got != "" {
		t.Errorf("a rig with no .beads named the store %q", got)
	}
	if got := subjectStore(rt, "zz-sub"); got != "" {
		t.Errorf("a prefix no rig owns named the store %q", got)
	}
}
