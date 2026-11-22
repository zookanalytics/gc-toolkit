package distiller

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// The start's lock is one flock(2) on LockFile in the Starter's Locks, the
// city's .gc/runtime/packs/gc-toolkit, where the dispatch locks live too
// (arm.LockDir). A start takes it without waiting once it has found the home
// rig's pool, before it reads the rig's store, and holds it to the sling's end.
// So of starts that overlap, the order's and any made by hand, the one that
// holds it reads and slings, and each other starts nothing. The kernel releases
// the lock when its holder ends, however it ends, and Go opens the file
// close-on-exec, so the gc sling the holder runs does not carry it. The file
// stays, so every start locks the same one, and while the lock is held it names
// its holder.

// LockFile is the name of the start's lock in the Starter's Locks.
const LockFile = "distiller-start.lock"

// lock takes the start's lock without waiting. It returns the release once it
// holds the lock, and a nil release with the holder's description when another
// start holds it. An error says the lock could not be taken at all.
func (s *Starter) lock() (func(), string, error) {
	if s.Locks == "" {
		return nil, "", errors.New("no directory for the start's lock was named")
	}
	if err := os.MkdirAll(s.Locks, 0o755); err != nil {
		return nil, "", fmt.Errorf("the directory of the start's lock, %s, could not be made: %w", s.Locks, err)
	}
	path := filepath.Join(s.Locks, LockFile)
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE, 0o644)
	if err != nil {
		return nil, "", fmt.Errorf("the start's lock %s could not be opened: %w", path, err)
	}
	fd := int(f.Fd())
	for {
		err = syscall.Flock(fd, syscall.LOCK_EX|syscall.LOCK_NB)
		if !errors.Is(err, syscall.EINTR) {
			break
		}
	}
	switch {
	case errors.Is(err, syscall.EWOULDBLOCK):
		_ = f.Close()
		holder := "a start that has not named itself yet"
		if raw, rerr := os.ReadFile(path); rerr == nil && strings.TrimSpace(string(raw)) != "" {
			holder = strings.TrimSpace(string(raw))
		}
		return nil, holder, nil
	case err != nil:
		_ = f.Close()
		return nil, "", fmt.Errorf("the start's lock %s could not be taken: %w", path, err)
	}
	_ = f.Truncate(0)
	_, _ = f.WriteAt([]byte(fmt.Sprintf("pid %d since %s\n", os.Getpid(), time.Now().UTC().Format(time.RFC3339))), 0)
	return func() {
		_ = f.Truncate(0)
		_ = syscall.Flock(fd, syscall.LOCK_UN)
		_ = f.Close()
	}, "", nil
}
