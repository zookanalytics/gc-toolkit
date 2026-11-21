package cli

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/claudecode/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	gfake "github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/memory"
)

// memoryCity is a city with one rig, r, whose sessions keep memory in mem,
// which holds two notes, and returns that directory and the fakes.
func memoryCity(t *testing.T) (mem string, rt *gfake.Runtime, claude *cfake.Claude) {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	co := filepath.Join(root, "rigs", "r")
	mem = filepath.Join(root, "mem")
	for _, d := range []string{co, mem} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for name, at := range map[string]time.Time{"a.md": time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC), "b.md": time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC)} {
		f := filepath.Join(mem, name)
		if err := os.WriteFile(f, []byte(name+" lesson.\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(f, at, at); err != nil {
			t.Fatal(err)
		}
	}
	rt = &gfake.Runtime{Root: root, RigList: []gascity.Rig{{Name: "town", Path: root, Prefix: "lx", HQ: true}, {Name: "r", Path: co, Prefix: "tk"}}}
	claude = &cfake.Claude{Dirs: map[string]string{root: filepath.Join(root, "none"), co: mem}, Version: "2.1.326"}
	store := fake.New()
	store.Put(fake.Bead{ID: "tk-p1", Status: "open"})
	restore := newIntake
	newIntake = func() *memory.Intake {
		return &memory.Intake{Runtime: rt, Claude: claude, LockWait: time.Second,
			Now:   func() time.Time { return time.Date(2026, 11, 15, 12, 0, 0, 0, time.UTC) },
			Store: func(string) (*ledger.Ledger, error) { return ledger.New(store), nil }}
	}
	t.Cleanup(func() { newIntake = restore })
	return mem, rt, claude
}

func runMemory(args ...string) (int, string, string) {
	var out, errb bytes.Buffer
	code := Run(append([]string{"memory"}, args...), "test", &out, &errb)
	return code, out.String(), errb.String()
}

// due prints the due notes as a JSON array, oldest first; --limit takes the
// oldest and --count counts them, and the two do not go together.
func TestMemoryDuePrintsTheDueNotes(t *testing.T) {
	memoryCity(t)
	code, out, errs := runMemory("due")
	var due []map[string]string
	if err := json.Unmarshal([]byte(out), &due); err != nil || code != 0 || errs != "" {
		t.Fatalf("due = %d, %q, %q", code, out, errs)
	}
	if len(due) != 2 || !strings.HasSuffix(due[0]["memory_file"], "/a.md") || due[0]["memory_due"] != "new" ||
		due[0]["created_at"] != "2026-11-01T00:00:00Z" || due[0]["memory_ref"] == "" {
		t.Errorf("due %v", due)
	}
	if _, has := due[0]["memory_text"]; has {
		t.Error("a note carries memory_text")
	}
	if code, out, _ := runMemory("due", "--limit", "1"); code != 0 || strings.Count(out, "memory_ref") != 1 || !strings.Contains(out, "/a.md") {
		t.Errorf("--limit 1 = %d, %q", code, out)
	}
	if code, out, _ := runMemory("due", "--count"); code != 0 || out != "2\n" {
		t.Errorf("--count = %d, %q", code, out)
	}
	if code, _, errs := runMemory("due", "--count", "--limit", "1"); code != 2 || !strings.Contains(errs, "go alone") {
		t.Errorf("--count with --limit = %d, %q", code, errs)
	}
}

// A place it cannot learn is named on stderr and exits 3, and the rest print;
// a city whose rigs do not read prints none and exits 1.
func TestMemoryDueNamesAPlaceItCannotLearn(t *testing.T) {
	_, rt, claude := memoryCity(t)
	claude.Dirs[rt.Root] = ""
	code, out, errs := runMemory("due", "--count")
	if code != 3 || out != "2\n" || !strings.Contains(errs, "town: cannot learn where its sessions keep memory: Claude Code 2.1.326 named no memory directory") {
		t.Errorf("due = %d, %q, %q", code, out, errs)
	}
	rt.RigsErr = errors.New("gc rig list did not read")
	if code, out, errs := runMemory("due"); code != 1 || out != "[]\n" || !strings.Contains(errs, "no memory directory was placed") {
		t.Errorf("due with no rigs = %d, %q, %q", code, out, errs)
	}
}

// apply reads its decisions from a file and says what it did of each; one it
// cannot read or do exits 1.
func TestMemoryApplyRecordsTheDecisions(t *testing.T) {
	mem, _, _ := memoryCity(t)
	_, out, _ := runMemory("due")
	var due []map[string]string
	if err := json.Unmarshal([]byte(out), &due); err != nil {
		t.Fatal(err)
	}
	file := filepath.Join(t.TempDir(), "decisions")
	if err := os.WriteFile(file, []byte(due[0]["memory_ref"]+" waits tk-p1\n"+due[1]["memory_ref"]+" drop\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errs := runMemory("apply", file)
	if code != 0 || errs != "" || !strings.Contains(out, "recorded "+due[0]["memory_ref"]+": waits on tk-p1\n") ||
		!strings.Contains(out, "removed "+due[1]["memory_ref"]) {
		t.Errorf("apply = %d, %q, %q", code, out, errs)
	}
	if _, err := os.Stat(filepath.Join(mem, "b.md")); !os.IsNotExist(err) {
		t.Error("the dropped note is there")
	}
	if code, _, errs := runMemory("apply", filepath.Join(t.TempDir(), "absent")); code != 1 || !strings.Contains(errs, "cannot read") {
		t.Errorf("apply of a file that is not there = %d, %q", code, errs)
	}
	if err := os.WriteFile(file, []byte("nonsense\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, errs := runMemory("apply", file); code != 1 || !strings.Contains(errs, "gctk memory apply: not a decision") {
		t.Errorf("apply of no decision = %d, %q", code, errs)
	}
	if code, _, _ := runMemory("apply"); code != 2 {
		t.Errorf("apply with no file = %d, want usage", code)
	}
}

// settle says what it ended and each place, and exits 3 for a place it cannot
// learn, after settling the rest.
func TestMemorySettleSaysWhatItEnded(t *testing.T) {
	mem, rt, claude := memoryCity(t)
	code, out, errs := runMemory("settle")
	if code != 0 || errs != "" || !strings.Contains(out, "r: "+mem+", 2 notes and 0 entries\n") ||
		!strings.Contains(out, "town: no memory directory at ") ||
		!strings.Contains(out, "waits ended: 0 units removed with a fix landed, each one's text kept; 0 units due again with no fix landed\n") {
		t.Errorf("settle = %d, %q, %q", code, out, errs)
	}
	claude.Dirs[rt.Root] = ""
	if code, _, errs := runMemory("settle"); code != 3 || !strings.Contains(errs, "town: cannot learn") {
		t.Errorf("settle with a place it cannot learn = %d, %q", code, errs)
	}
}
