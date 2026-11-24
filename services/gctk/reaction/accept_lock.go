package reaction

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
)

// The acceptance lock: one flock(2) per bead, accept-<bead>.lock in the city's
// .gc/runtime/packs/gc-toolkit, where the dispatch locks live too
// (arm.LockDir), held from an Accept's live read of the bead to its last write,
// so one Accept's search, sling and record never interleave with another's, and
// an acceptance is dispatched once even after the work it sent has finished
// (docs/warrants.md, "Accept's lock"). A placement (gctk bead place) and a
// first reaction's exit hold the same lock from their own live read to their
// last write, so an exit never releases a bead a placement is sending on, and a
// placement never sends one an exit is releasing. The bead's id names its store
// by its prefix, so one file per id is one per store and bead. While the lock
// is held the file names its holder: the process and when it took the lock. The
// kernel releases the lock when its holder ends, however it ends, and Go opens
// the file close-on-exec, so no process the holder starts, gc sling among them,
// carries it. The release removes the file, and a call that locked a file
// removed meanwhile takes the file that replaced it.

// errLockDir is the error of a lock that cannot be taken at all: no city root
// names its directory, or the file cannot be made.
var errLockDir = errors.New("no acceptance lock can be taken")

// acceptLock takes the bead's acceptance lock without waiting, as LockBead
// does.
func (r *Reactions) acceptLock(bead string) (func(), string, error) {
	return LockBead(r.Runtime, bead)
}

// LockBead takes the bead's acceptance lock without waiting. It returns the
// release once it holds the lock, and a nil release with the holder's
// description when an Accept, a placement or a first reaction's exit holds it.
// An error that is errLockDir says no lock could be taken.
func LockBead(rt gascity.Runtime, bead string) (func(), string, error) {
	dir, err := arm.LockDir(rt)
	if err != nil {
		return nil, "", fmt.Errorf("%w: %v", errLockDir, err)
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, "", fmt.Errorf("%w: its directory %s could not be made: %v", errLockDir, dir, err)
	}
	path := filepath.Join(dir, "accept-"+fileSafe(bead)+".lock")
	for {
		f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
		if err != nil {
			return nil, "", fmt.Errorf("%w: %s could not be opened: %v", errLockDir, path, err)
		}
		fd := int(f.Fd())
		for {
			err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
			if !errors.Is(err, syscall.EINTR) {
				break
			}
		}
		if errors.Is(err, syscall.EWOULDBLOCK) {
			_ = f.Close()
			return nil, lockHolder(path), nil
		}
		if err != nil {
			_ = f.Close()
			return nil, "", fmt.Errorf("%w: %s could not be taken: %v", errLockDir, path, err)
		}
		held, herr := f.Stat()
		now, nerr := os.Stat(path)
		if herr == nil && nerr == nil && os.SameFile(held, now) {
			_ = f.Truncate(0)
			_, _ = f.WriteAt([]byte(fmt.Sprintf("pid %d since %s\n", os.Getpid(), time.Now().UTC().Format(time.RFC3339))), 0)
			return func() {
				_ = os.Remove(path)
				_ = syscall.Flock(fd, syscall.LOCK_UN)
				_ = f.Close()
			}, "", nil
		}
		_ = f.Close()
		if herr != nil {
			return nil, "", fmt.Errorf("%w: %s could not be read: %v", errLockDir, path, herr)
		}
		if nerr != nil && !errors.Is(nerr, fs.ErrNotExist) {
			return nil, "", fmt.Errorf("%w: %s could not be read: %v", errLockDir, path, nerr)
		}
	}
}

// lockHolder describes the holder the lock file names, or says it names none.
func lockHolder(path string) string {
	raw, err := os.ReadFile(path)
	if s := strings.TrimSpace(string(raw)); err == nil && s != "" {
		return s
	}
	return "a holder that has not named itself yet"
}

// fileSafe is id with each byte outside A-Za-z0-9._- read as _.
func fileSafe(id string) string {
	return strings.Map(func(c rune) rune {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '.', c == '_', c == '-':
			return c
		}
		return '_'
	}, id)
}
