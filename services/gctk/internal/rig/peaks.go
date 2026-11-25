package rig

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Peaks keeps the memory the runs of each check used at most in one
// repository, in <git common dir>/gc-rig-memory: a file for each check and
// scope, such as test-full, with a line per run, "<time> <bytes> <command>",
// the newest last, where <command> is a digest of the command line the run
// was given. Every worktree of the repository shares it.
//
// A run is weighed by the runs of its own command line, check and scope, the
// run a record answers for (Found.Answer), so the runs of a lighter command
// never stand in for it. A command with no run kept is weighed by the most
// any kept run of its check and scope used.
type Peaks struct{ dir string }

// peakRuns is how many of a command's last runs its weight reads. A file
// keeps the last peakKeep runs of its check and scope: the run that takes it
// past twice that many trims it back to them.
const (
	peakRuns = 10
	peakKeep = 50
)

// NewPeaks is the peaks kept in the git common directory common.
func NewPeaks(common string) *Peaks { return &Peaks{dir: filepath.Join(common, "gc-rig-memory")} }

func (p *Peaks) path(check, scope string) string {
	if scope != "" {
		check += "-" + scope
	}
	return filepath.Join(p.dir, check)
}

// commandKey is the digest a line names its run's command line by.
func commandKey(command string) string {
	sum := sha256.Sum256([]byte(command))
	return hex.EncodeToString(sum[:8])
}

// Weight is the most memory one of the last peakRuns runs of command used,
// among the kept runs of check with scope, and own is true. When none of
// those runs is command's, it is the most any of them used, own is false, and
// it is zero when none is kept. A line it cannot read is passed over.
func (p *Peaks) Weight(check, scope, command string) (weight int64, own bool, err error) {
	lines, err := p.lines(check, scope)
	if err != nil {
		return 0, false, err
	}
	key := commandKey(command)
	var most int64
	var mine []int64
	for _, line := range lines {
		f := strings.Fields(line)
		if len(f) != 3 {
			continue
		}
		n, err := strconv.ParseInt(f[1], 10, 64)
		if err != nil {
			continue
		}
		most = max(most, n)
		if f[2] == key {
			mine = append(mine, n)
		}
	}
	if len(mine) == 0 {
		return most, false, nil
	}
	for _, n := range mine[max(0, len(mine)-peakRuns):] {
		weight = max(weight, n)
	}
	return weight, true, nil
}

func (p *Peaks) lines(check, scope string) ([]string, error) {
	b, err := os.ReadFile(p.path(check, scope))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return strings.Split(strings.TrimRight(string(b), "\n"), "\n"), nil
}

// Add keeps the peak of a run of command at the end of the file of its check
// and scope. The line is one append, so runs that end together each keep
// theirs. A trim rewrites the file whole, and a line another run appends while
// it does is lost.
func (p *Peaks) Add(check, scope, command string, at time.Time, peak int64) error {
	// Only the directory of its own is made: a git directory that is gone is
	// not made again.
	if err := os.Mkdir(p.dir, 0o755); err != nil && !os.IsExist(err) {
		return err
	}
	path := p.path(check, scope)
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	_, werr := fmt.Fprintf(f, "%s %d %s\n", at.UTC().Format(time.RFC3339), peak, commandKey(command))
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		return werr
	}
	lines, err := p.lines(check, scope)
	if err != nil || len(lines) <= 2*peakKeep {
		return err
	}
	tmp, err := os.CreateTemp(p.dir, filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	_, werr = tmp.WriteString(strings.Join(lines[len(lines)-peakKeep:], "\n") + "\n")
	if cerr := tmp.Close(); werr == nil {
		werr = cerr
	}
	if werr == nil {
		werr = os.Rename(tmp.Name(), path)
	}
	if werr != nil {
		_ = os.Remove(tmp.Name())
	}
	return werr
}
