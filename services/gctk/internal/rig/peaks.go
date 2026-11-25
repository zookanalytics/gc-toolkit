package rig

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Peaks keeps, for each check, the memory its runs in one repository used at
// most, in <git common dir>/gc-rig-memory/<check>: a line per run, "<time>
// <bytes>", the newest last. Every worktree of the repository shares it.
type Peaks struct{ dir string }

// peakRuns is how many of a check's last runs its weight reads, and peakKeep
// how many lines its file grows to before a run trims it to the last
// peakRuns.
const (
	peakRuns = 10
	peakKeep = 100
)

// NewPeaks is the peaks kept in the git common directory common.
func NewPeaks(common string) *Peaks { return &Peaks{dir: filepath.Join(common, "gc-rig-memory")} }

func (p *Peaks) path(check string) string { return filepath.Join(p.dir, check) }

// Weight is the most memory one of the last peakRuns runs of check used, and
// zero when no run of it is kept. A line it cannot read is passed over.
func (p *Peaks) Weight(check string) (int64, error) {
	lines, err := p.lines(check)
	if err != nil {
		return 0, err
	}
	var most int64
	for _, line := range lines[max(0, len(lines)-peakRuns):] {
		if f := strings.Fields(line); len(f) == 2 {
			if n, err := strconv.ParseInt(f[1], 10, 64); err == nil && n > most {
				most = n
			}
		}
	}
	return most, nil
}

func (p *Peaks) lines(check string) ([]string, error) {
	b, err := os.ReadFile(p.path(check))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return strings.Split(strings.TrimRight(string(b), "\n"), "\n"), nil
}

// Add keeps a run's peak at the end of check's file. The line is one append,
// so runs that end together each keep theirs. A trim rewrites the file whole,
// and a line another run appends while it does is lost.
func (p *Peaks) Add(check string, at time.Time, peak int64) error {
	// Only the directory of its own is made: a git directory that is gone is
	// not made again.
	if err := os.Mkdir(p.dir, 0o755); err != nil && !os.IsExist(err) {
		return err
	}
	f, err := os.OpenFile(p.path(check), os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	_, werr := fmt.Fprintf(f, "%s %d\n", at.UTC().Format(time.RFC3339), peak)
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		return werr
	}
	lines, err := p.lines(check)
	if err != nil || len(lines) <= peakKeep {
		return err
	}
	tmp, err := os.CreateTemp(p.dir, check+".*")
	if err != nil {
		return err
	}
	_, werr = tmp.WriteString(strings.Join(lines[len(lines)-peakRuns:], "\n") + "\n")
	if cerr := tmp.Close(); werr == nil {
		werr = cerr
	}
	if werr == nil {
		werr = os.Rename(tmp.Name(), p.path(check))
	}
	if werr != nil {
		_ = os.Remove(tmp.Name())
	}
	return werr
}
