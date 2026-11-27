package mail

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
	"time"
)

// The ledger is LedgerFile in the State directory: each unread message a pass
// has requested a turn for, with the session it nudged and when. A pass writes
// it whole once it has visited every session, through a file it renames into
// place, so a reader never sees half of one. LockFile is the lock every pass
// holds from before it reads the ledger until after it writes it, so the
// orders' runs, and a run by hand, never nudge a session twice for one
// message. The lock is the kernel's advisory lock on the file, which the
// kernel releases when its holder ends however it ends, and Go opens the file
// close-on-exec, so the gc commands a pass runs do not carry it.
const (
	LedgerFile = "mail-notify.json"
	LockFile   = "mail-notify.lock"
)

// lockPoll is how often a pass that finds the lock held tries it again.
const lockPoll = 100 * time.Millisecond

type entry struct {
	Session string    `json:"session"`
	At      time.Time `json:"at"`
}

type ledger map[string]entry

func (l ledger) has(id string) bool {
	_, ok := l[id]
	return ok
}

// readLedger reads the ledger in dir. A ledger that is not there is empty, and
// one that does not read is an error, since nudging past it would request a
// second turn for every message it holds.
func readLedger(dir string) (ledger, error) {
	path := filepath.Join(dir, LedgerFile)
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return ledger{}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("the notify ledger %s did not read: %w", path, err)
	}
	var file struct {
		Notified ledger `json:"notified"`
	}
	if err := json.Unmarshal(raw, &file); err != nil || file.Notified == nil {
		return nil, fmt.Errorf("the notify ledger %s holds no notified map that reads", path)
	}
	return file.Notified, nil
}

// writeLedger writes l to dir through a file it renames into place.
func writeLedger(dir string, l ledger) error {
	path := filepath.Join(dir, LedgerFile)
	raw, err := json.MarshalIndent(struct {
		Notified ledger `json:"notified"`
	}{l}, "", "  ")
	if err != nil {
		return fmt.Errorf("the notify ledger did not encode: %w", err)
	}
	tmp, err := os.CreateTemp(dir, "."+LedgerFile+".*")
	if err != nil {
		return fmt.Errorf("the notify ledger %s was not written: %w", path, err)
	}
	_, werr := tmp.Write(append(raw, '\n'))
	cerr := tmp.Close()
	if err := errors.Join(werr, cerr); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("the notify ledger %s was not written: %w", path, err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		_ = os.Remove(tmp.Name())
		return fmt.Errorf("the notify ledger %s was not written: %w", path, err)
	}
	return nil
}

// lock takes the passes' lock in dir, waiting while another pass holds it,
// until ctx ends. It returns the release once it holds the lock.
func lock(ctx context.Context, dir string) (func(), error) {
	if dir == "" {
		return nil, errors.New("no directory for the notify ledger and its lock was named")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("the directory of the notify ledger, %s, could not be made: %w", dir, err)
	}
	path := filepath.Join(dir, LockFile)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, fmt.Errorf("the notify lock %s could not be opened: %w", path, err)
	}
	fd := int(f.Fd())
	for {
		err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			break
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EINTR) {
			_ = f.Close()
			return nil, fmt.Errorf("the notify lock %s could not be taken: %w", path, err)
		}
		select {
		case <-ctx.Done():
			_ = f.Close()
			return nil, fmt.Errorf("the notify lock %s stayed held by another pass until this one's deadline", path)
		case <-time.After(lockPoll):
		}
	}
	return func() {
		_ = syscall.Flock(fd, syscall.LOCK_UN)
		_ = f.Close()
	}, nil
}
