package memory

import (
	"cmp"
	"errors"
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// A directory's state, under Places.State/<key>: its list, its real path, each
// removed unit's text, the notes removed whose pointers did not all come out,
// and the lock a writer holds.
const (
	listFile    = "list.tsv"
	pathFile    = "path"
	removedDir  = "removed"
	goneFile    = "gone"
	lockFile    = "lock"
	listHead    = "#memory-intake list 1\tkind\tname\thash\tjudged\twait\tnext\twhy"
	lockPoll    = 20 * time.Millisecond
	defaultWait = 2 * time.Minute
)

// A row is one unit the judge read and kept: its hash, when it was judged, and
// the bead it waits on or the day it is next due, with why it is due again
// when its wait ended with no fix landed.
type row struct {
	Kind, Name, Hash, Judged, Wait, Next, Why string
}

// key is a row's identity: a note's name, or an entry's name and hash.
func (r row) key() string {
	if r.Kind == Note {
		return Note + "\x00" + r.Name
	}
	return r.Kind + "\x00" + r.Name + "\x00" + r.Hash
}

func (u Unit) key() string { return row{Kind: u.Kind, Name: u.Name, Hash: u.Hash}.key() }

// prior is what the list held for a unit, for the judge.
func (r row) prior() string {
	switch {
	case r.Why != "":
		return r.Why
	case r.Wait != "":
		return "waited on " + r.Wait
	case r.Next != "":
		return "kept until " + r.Next
	}
	return ""
}

// readList reads the rows under state, none when it holds no list.
func readList(state string) ([]row, error) {
	raw, err := os.ReadFile(filepath.Join(state, listFile))
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("the list under %s did not read: %w", state, err)
	}
	var rows []row
	for _, l := range lines(string(raw)) {
		if l == "" || strings.HasPrefix(l, "#") {
			continue
		}
		f := strings.SplitN(l, "\t", 7)
		for len(f) < 7 {
			f = append(f, "")
		}
		rows = append(rows, row{f[0], f[1], f[2], f[3], f[4], f[5], f[6]})
	}
	return rows, nil
}

// writeList replaces the list under state with rows, sorted by name, kind and
// hash.
func writeList(state string, rows []row) error {
	sorted := slices.Clone(rows)
	slices.SortFunc(sorted, func(a, b row) int {
		return cmp.Or(cmp.Compare(a.Name, b.Name), cmp.Compare(a.Kind, b.Kind), cmp.Compare(a.Hash, b.Hash))
	})
	var b strings.Builder
	b.WriteString(listHead + "\n")
	for _, r := range sorted {
		b.WriteString(strings.Join([]string{r.Kind, r.Name, r.Hash, r.Judged, r.Wait, r.Next, oneLine(r.Why)}, "\t") + "\n")
	}
	return replace(filepath.Join(state, listFile), b.String(), 0o644)
}

// readGone reads the notes removed whose pointers did not all come out, kept
// under state one quoted name a line, none when it keeps none.
func readGone(state string) (map[string]bool, error) {
	gone := map[string]bool{}
	raw, err := os.ReadFile(filepath.Join(state, goneFile))
	if errors.Is(err, os.ErrNotExist) {
		return gone, nil
	}
	if err != nil {
		return nil, fmt.Errorf("the notes under %s whose pointers are still to come out did not read: %w", state, err)
	}
	for _, l := range lines(string(raw)) {
		if name, err := strconv.Unquote(l); err == nil && name != "" {
			gone[name] = true
		}
	}
	return gone, nil
}

// writeGone keeps the notes in gone under state, and removes the file when
// gone is empty.
func writeGone(state string, gone map[string]bool) error {
	file := filepath.Join(state, goneFile)
	if len(gone) == 0 {
		if err := os.Remove(file); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("cannot remove %s: %w", file, err)
		}
		return nil
	}
	var b strings.Builder
	for _, name := range slices.Sorted(maps.Keys(gone)) {
		b.WriteString(strconv.Quote(name) + "\n")
	}
	return replace(file, b.String(), 0o644)
}

// lock takes the lock on a directory's state, making the state and its path
// file first, and returns the call that releases it. Nothing that runs while it
// is held starts a process that could outlive the holder.
func (in *Intake) lock(state, dir string) (func(), error) {
	if err := os.MkdirAll(state, 0o755); err != nil {
		return nil, fmt.Errorf("cannot make %s: %w", state, err)
	}
	f, err := os.OpenFile(filepath.Join(state, lockFile), os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, fmt.Errorf("cannot open the lock under %s: %w", state, err)
	}
	wait := in.LockWait
	if wait <= 0 {
		wait = defaultWait
	}
	deadline := time.Now().Add(wait)
	for {
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EINTR) {
			_ = f.Close()
			return nil, fmt.Errorf("the lock under %s: %w", state, err)
		}
		if !time.Now().Before(deadline) {
			_ = f.Close()
			return nil, fmt.Errorf("another run held the lock under %s for %s", state, wait)
		}
		time.Sleep(lockPoll)
	}
	release := func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		_ = f.Close()
	}
	if _, err := os.Stat(filepath.Join(state, pathFile)); errors.Is(err, os.ErrNotExist) {
		if err := replace(filepath.Join(state, pathFile), dir+"\n", 0o644); err != nil {
			release()
			return nil, err
		}
	}
	return release, nil
}

// replace writes text to file through a new file beside it, so a reader sees
// the old text or the new, never part of either.
func replace(file, text string, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(file), ".memory-intake.*")
	if err != nil {
		return fmt.Errorf("cannot write %s: %w", file, err)
	}
	_, werr := tmp.WriteString(text)
	cerr := tmp.Close()
	if err := cmp.Or(werr, cerr, os.Chmod(tmp.Name(), mode)); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("cannot write %s: %w", file, err)
	}
	if err := os.Rename(tmp.Name(), file); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("cannot write %s: %w", file, err)
	}
	return nil
}
