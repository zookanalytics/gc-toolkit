package rig

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"slices"
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

// The runs a file keeps are the last peakRuns runs of each of the last
// peakCommands commands to run, so the runs of other commands push a
// command's own runs out only once that many others have run since. The run
// whose line takes a file past twice the most it keeps trims it back to them.
const (
	peakRuns     = 10
	peakCommands = 50
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

// Weight is the most memory a kept run of command used, among the kept runs
// of check with scope, and own is true. When none of those runs is command's,
// it is the most any of them used, own is false, and it is zero when none is
// kept.
func (p *Peaks) Weight(check, scope, command string) (weight int64, own bool, err error) {
	lines, err := p.lines(check, scope)
	if err != nil {
		return 0, false, err
	}
	key := commandKey(command)
	var most int64
	for _, r := range kept(lines) {
		most = max(most, r.peak)
		if r.command == key {
			weight, own = max(weight, r.peak), true
		}
	}
	if !own {
		return most, false, nil
	}
	return weight, true, nil
}

// peakRun is one line of a file of peaks.
type peakRun struct {
	line    string
	peak    int64
	command string
}

// kept is the runs a file keeps of lines, in their order. A line it cannot
// read is left out.
func kept(lines []string) []peakRun {
	var runs []peakRun
	count := map[string]int{}
	for i := len(lines) - 1; i >= 0; i-- {
		f := strings.Fields(lines[i])
		if len(f) != 3 {
			continue
		}
		n, err := strconv.ParseInt(f[1], 10, 64)
		if err != nil {
			continue
		}
		c, seen := count[f[2]]
		if (!seen && len(count) == peakCommands) || c == peakRuns {
			continue
		}
		count[f[2]] = c + 1
		runs = append(runs, peakRun{line: lines[i], peak: n, command: f[2]})
	}
	slices.Reverse(runs)
	return runs
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
	if err != nil || len(lines) <= 2*peakRuns*peakCommands {
		return err
	}
	var keep strings.Builder
	for _, r := range kept(lines) {
		keep.WriteString(r.line + "\n")
	}
	tmp, err := os.CreateTemp(p.dir, filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	_, werr = tmp.WriteString(keep.String())
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
