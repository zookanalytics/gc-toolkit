package arm

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// The dispatch lock: one flock(2) per armed bead, held by gctk bead arm, gctk
// bead disarm and each step the start takes on the bead, so no arm or disarm
// lands while a start sends the bead, and no two starts send it. The bead's id
// names its store by its prefix, so one file per id is one per store and bead.
// The file lives in Locks, the city's .gc/runtime/packs/gc-toolkit, as
// dispatch-<bead>.lock, and while the lock is held it names its holder: the
// process and when it took the lock. The kernel releases the lock when its
// holder ends, however it ends. Go opens the file close-on-exec, so no process
// the holder starts, gc sling among them, carries it. The release removes the
// file, and a call that locked a file removed meanwhile takes the file that
// replaced it.

// lockWait is how long arm and disarm wait for a start that holds the bead's
// lock to finish. A start holds it for one sling, and its allowance is the
// same time.
const lockWait = slingAllowance

// lockPoll is how often a waiting call tries the lock again.
const lockPoll = 200 * time.Millisecond

// lockWaiting takes the bead's lock, waiting while another call holds it, and
// returns its release. A lock still held once the wait has passed is an error
// that names its holder, and the call writes nothing.
func (a *Arms) lockWaiting(id string) (func(), error) {
	wait := a.Wait
	if wait == 0 {
		wait = lockWait
	}
	release, holder, err := a.takeLock(id, wait)
	switch {
	case err != nil:
		return nil, err
	case release == nil:
		return nil, fmt.Errorf("%s's dispatch lock is held by %s, so a start is sending it; nothing was written, and the call can run again once it finishes", id, holder)
	}
	return release, nil
}

// takeLock takes the bead's lock, trying again for up to wait while another
// call holds it. It returns the release once it holds the lock, and a nil
// release with the holder's description when the lock is still held at the end
// of wait. An error says the lock could not be taken at all.
func (a *Arms) takeLock(id string, wait time.Duration) (func(), string, error) {
	if a.Locks == "" {
		return nil, "", errors.New("no directory for the dispatch locks was named, so no lock can be taken and nothing was written")
	}
	if err := os.MkdirAll(a.Locks, 0o755); err != nil {
		return nil, "", fmt.Errorf("the dispatch locks' directory %s could not be made: %w", a.Locks, err)
	}
	path := filepath.Join(a.Locks, "dispatch-"+fileSafe(id)+".lock")
	deadline := time.Now().Add(wait)
	for {
		f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
		if err != nil {
			return nil, "", fmt.Errorf("the dispatch lock %s could not be opened: %w", path, err)
		}
		fd := int(f.Fd())
		for {
			err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
			if !errors.Is(err, syscall.EINTR) {
				break
			}
		}
		if errors.Is(err, syscall.EWOULDBLOCK) {
			holder := lockHolder(path)
			_ = f.Close()
			if !time.Now().Before(deadline) {
				return nil, holder, nil
			}
			time.Sleep(lockPoll)
			continue
		}
		if err != nil {
			_ = f.Close()
			return nil, "", fmt.Errorf("the dispatch lock %s could not be taken: %w", path, err)
		}
		held, err := f.Stat()
		if err != nil {
			_ = f.Close()
			return nil, "", fmt.Errorf("the dispatch lock %s could not be read: %w", path, err)
		}
		now, err := os.Stat(path)
		if err == nil && os.SameFile(held, now) {
			_ = f.Truncate(0)
			_, _ = f.WriteAt([]byte(fmt.Sprintf("pid %d since %s\n", os.Getpid(), time.Now().UTC().Format(time.RFC3339))), 0)
			return func() {
				_ = os.Remove(path)
				_ = syscall.Flock(fd, syscall.LOCK_UN)
				_ = f.Close()
			}, "", nil
		}
		_ = f.Close()
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, "", fmt.Errorf("the dispatch lock %s could not be read: %w", path, err)
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
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '.', r == '_', r == '-':
			return r
		}
		return '_'
	}, id)
}
