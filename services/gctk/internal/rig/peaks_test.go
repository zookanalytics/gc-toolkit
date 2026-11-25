package rig

import (
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

	add(ScopeFull, "make test", 90, 80, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14)
	add(ScopeFull, "go test ./one", 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1)
	weight(ScopeFull, "make test", 14, true)
	weight(ScopeFull, "go test ./one", 1, true)
	weight(ScopeFull, "go test ./two", 12<<30, false)

	f := filepath.Join(common, "gc-rig-memory", CheckTest+"-"+ScopeFull)
	b, _ := os.ReadFile(f)
	if err := os.WriteFile(f, append(b, []byte("not a line\n2026-11-25T00:00:00Z many "+commandKey("make test")+"\n2026-11-25T00:00:00Z 99\n")...), 0o644); err != nil {
		t.Fatal(err)
	}
	weight(ScopeFull, "make test", 14, true)
}

func TestPeaksTrimToTheLastRunsTheyKeepAndMakeNoGitDirectory(t *testing.T) {
	common := t.TempDir()
	p := NewPeaks(common)
	at := time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC)
	for i := 0; i <= 2*peakKeep; i++ {
		if err := p.Add(CheckLint, "", "lint", at, int64(i)); err != nil {
			t.Fatal(err)
		}
	}
	b, err := os.ReadFile(filepath.Join(common, "gc-rig-memory", CheckLint))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	want := " " + "100 " + commandKey("lint")
	if len(lines) != peakKeep || !strings.HasSuffix(lines[peakKeep-1], want) {
		t.Fatalf("after %d runs the file holds %d lines ending %q; want the last %d", 2*peakKeep+1, len(lines), lines[len(lines)-1], peakKeep)
	}
	gone := filepath.Join(t.TempDir(), "moved-away", ".git")
	if err := NewPeaks(gone).Add(CheckLint, "", "lint", at, 1); err == nil {
		t.Fatal("Add into a git directory that is gone succeeded")
	}
	if _, err := os.Stat(gone); !os.IsNotExist(err) {
		t.Fatalf("Add made the git directory that was gone: %v", err)
	}
}
