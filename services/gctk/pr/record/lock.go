package record

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// LockFile is the store's record lock: a flock on this file in the store's
// .beads directory, the path every writer of the record names the same way
// (specs/tk-1tfzr71.66/design.md, section 4). `gctk pr record` holds it across
// both of a publication's writes, `gctk pr reconcile` holds it for one record
// at a time, from its read of the record to its last write of it, and
// bead-rehome.sh holds it from its read of a bead to its close. Nothing that
// holds it takes another lock, so no two writers wait on each other in a cycle.
const LockFile = "pr-record.lock"

// lockPoll is how often a writer waiting for the lock asks for it again.
const lockPoll = 20 * time.Millisecond

// ErrLockWait is the error of a writer that waited for the record lock as long
// as it would and did not get it.
var ErrLockWait = errors.New("another writer of the record held the record lock for as long as this writer would wait")

// Lock takes the record lock of the store whose .beads directory is dir,
// waiting up to wait while another writer holds it, and returns the call that
// releases it. The file is opened close-on-exec, as Go opens every file, so no
// process the holder starts, such as gh or a Dolt server a store read brings
// up, inherits the lock, and the kernel releases it when the holder's process
// ends, so a holder that dies, or that an order's time limit stops, holds
// nothing.
func Lock(dir string, wait time.Duration) (release func(), err error) {
	if dir == "" {
		return nil, errors.New("record lock: the store's .beads directory is not named")
	}
	path := filepath.Join(dir, LockFile)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, fmt.Errorf("record lock: %w", err)
	}
	deadline := time.Now().Add(wait)
	for {
		err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EINTR) {
			f.Close()
			return nil, fmt.Errorf("record lock: %s: %w", path, err)
		}
		if !time.Now().Before(deadline) {
			f.Close()
			return nil, fmt.Errorf("record lock: %s after %s: %w", path, wait, ErrLockWait)
		}
		time.Sleep(lockPoll)
	}
	return func() {
		_ = syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		f.Close()
	}, nil
}
