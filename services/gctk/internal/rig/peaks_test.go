package rig

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestPeaksWeighTheLastTenRunsOfACheck(t *testing.T) {
	common := t.TempDir()
	p := NewPeaks(common)
	if w, err := p.Weight(CheckTest); err != nil || w != 0 {
		t.Fatalf("Weight with no run kept = %d, %v; want 0", w, err)
	}
	at := time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC)
	for i, peak := range []int64{90, 80, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14} {
		if err := p.Add(CheckTest, at.Add(time.Duration(i)*time.Minute), peak); err != nil {
			t.Fatal(err)
		}
	}
	if err := p.Add(CheckLint, at, 70); err != nil {
		t.Fatal(err)
	}
	if w, err := p.Weight(CheckTest); err != nil || w != 14 {
		t.Fatalf("Weight = %d, %v; want 14, the most of the last ten, which the first two runs' 90 and 80 are not among", w, err)
	}
	f := filepath.Join(common, "gc-rig-memory", CheckTest)
	b, _ := os.ReadFile(f)
	if err := os.WriteFile(f, append(b, []byte("not a line\n2026-11-25T00:00:00Z many\n")...), 0o644); err != nil {
		t.Fatal(err)
	}
	if w, err := p.Weight(CheckTest); err != nil || w != 14 {
		t.Fatalf("Weight with lines it cannot read = %d, %v; want 14", w, err)
	}
}

func TestPeaksTrimToTheLastTenAndMakeNoGitDirectory(t *testing.T) {
	common := t.TempDir()
	p := NewPeaks(common)
	at := time.Date(2026, 11, 25, 0, 0, 0, 0, time.UTC)
	for i := 0; i <= peakKeep; i++ {
		if err := p.Add(CheckLint, at, int64(i)); err != nil {
			t.Fatal(err)
		}
	}
	b, err := os.ReadFile(filepath.Join(common, "gc-rig-memory", CheckLint))
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimSpace(string(b)), "\n")
	if len(lines) != peakRuns || !strings.HasSuffix(lines[peakRuns-1], " 100") {
		t.Fatalf("after %d runs the file holds %d lines ending %q; want the last %d", peakKeep+1, len(lines), lines[len(lines)-1], peakRuns)
	}
	gone := filepath.Join(t.TempDir(), "moved-away", ".git")
	if err := NewPeaks(gone).Add(CheckLint, at, 1); err == nil {
		t.Fatal("Add into a git directory that is gone succeeded")
	}
	if _, err := os.Stat(gone); !os.IsNotExist(err) {
		t.Fatalf("Add made the git directory that was gone: %v", err)
	}
}
