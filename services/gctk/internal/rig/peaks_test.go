package rig

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPeaksWeighARunByTheLastTenRunsOfItsOwnCommand(t *testing.T) {
	common := t.TempDir()
	p := NewPeaks(common)
	weight := func(scope, command string, want int64, wantOwn bool) {
		t.Helper()
		if w, own, err := p.Weight(CheckTest, scope, command); err != nil || w != want || own != wantOwn {
			t.Fatalf("Weight(%s, %q) = %d, %v, %v; want %d, %v", scope, command, w, own, err, want, wantOwn)
		}
	}
	add := func(scope, command string, peaks ...int64) {
		t.Helper()
		for _, n := range peaks {
			if err := p.Add(CheckTest, scope, command, time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC), n); err != nil {
				t.Fatal(err)
			}
		}
	}
	weight(ScopeFull, "make test", 0, false)

	add(ScopeFull, "make test", 12<<30)
	add(ScopeAffected, "make test-affected", 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20, 7<<20)
	weight(ScopeFull, "make test", 12<<30, true)
	weight(ScopeAffected, "make test-affected", 7<<20, true)
	weight(ScopeFull, "go test ./two", 12<<30, false)

	add(ScopeFull, "make test", 90, 80, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)
	add(ScopeFull, "go test ./one", 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
	weight(ScopeFull, "make test", 14, true)
	weight(ScopeFull, "go test ./one", 1, true)
	weight(ScopeFull, "go test ./two", 14, false)

	f := filepath.Join(common, "gc-rig-memory", CheckTest+"-"+ScopeFull)
	b, _ := os.ReadFile(f)
	if err := os.WriteFile(f, append(b, []byte("not a line\n2026-11-25T00:00:00Z many "+commandKey("make test")+"\n2026-11-25T00:00:00Z 99\n")...), 0o644); err != nil {
		t.Fatal(err)
	}
	weight(ScopeFull, "make test", 14, true)
}

// The runs of other commands push a command's own runs out only once
// peakCommands others have run since, through the trim too.
func TestPeaksKeepTheLastRunsOfEachOfTheLastCommandsAndMakeNoGitDirectory(t *testing.T) {
	common := t.TempDir()
	p := NewPeaks(common)
	at := time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC)
	add := func(command string, peak int64, runs int) {
		t.Helper()
		for range runs {
			if err := p.Add(CheckTest, ScopeFull, command, at, peak); err != nil {
				t.Fatal(err)
			}
		}
	}
	weight := func(command string, want int64, wantOwn bool) {
		t.Helper()
		if w, own, err := p.Weight(CheckTest, ScopeFull, command); err != nil || w != want || own != wantOwn {
			t.Fatalf("Weight(%q) = %d, %v, %v; want %d, %v", command, w, own, err, want, wantOwn)
		}
	}
	add("heavy", 12<<30, 1)
	add("light", 1<<20, 2*peakRuns*peakCommands)
	weight("heavy", 12<<30, true)
	b, err := os.ReadFile(filepath.Join(common, "gc-rig-memory", CheckTest+"-"+ScopeFull))
	if err != nil {
		t.Fatal(err)
	}
	if lines := strings.Split(strings.TrimSpace(string(b)), "\n"); len(lines) != peakRuns+1 {
		t.Fatalf("after %d runs the file holds %d lines; want the light command's last %d and the heavy one's", 2*peakRuns*peakCommands+1, len(lines), peakRuns)
	}
	for i := range peakCommands - 2 {
		add(fmt.Sprintf("other %d", i), 2<<20, 1)
	}
	weight("heavy", 12<<30, true)
	add("one more", 2<<20, 1)
	weight("heavy", 2<<20, false)

	gone := filepath.Join(t.TempDir(), "moved-away", ".git")
	if err := NewPeaks(gone).Add(CheckLint, "", "lint", at, 1); err == nil {
		t.Fatal("Add into a git directory that is gone succeeded")
	}
	if _, err := os.Stat(gone); !os.IsNotExist(err) {
		t.Fatalf("Add made the git directory that was gone: %v", err)
	}
}
