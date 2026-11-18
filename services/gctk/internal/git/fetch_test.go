package git

import (
	"context"
	"errors"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// A fetch the landing order makes is stopped at its act's bound
// (specs/tk-1tfzr71.149/design.md, section 5). These run FetchBranch against
// a fake git at the front of PATH that answers check-ref-format as git does and
// stands for a fetch that does not end: it holds a lock file the way git holds
// refs/remotes/origin/<branch>.lock, and removes it in its SIGTERM handler,
// which a SIGKILL never runs.

// fakeFetch puts an executable `git` at the front of PATH, in a fresh directory
// it returns, which for a fetch sets trap first, then writes its pid to git.pid,
// so a test that waits for git.pid signals a git whose handler is in place, and
// then runs script. Every process the script starts leads or joins git's own
// group, and the cleanup kills whatever of that group is still running.
func fakeFetch(t *testing.T, trap, script string) string {
	t.Helper()
	dir := t.TempDir()
	body := "#!/bin/sh\ncase \"$1\" in check-ref-format) exit 0 ;; esac\n" + trap + "\necho $$ > '" +
		filepath.Join(dir, "git.pid") + "'\n" + script
	if err := os.WriteFile(filepath.Join(dir, "git"), []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Cleanup(func() {
		raw, err := os.ReadFile(filepath.Join(dir, "git.pid"))
		if pid, _ := strconv.Atoi(strings.TrimSpace(string(raw))); err == nil && pid > 0 {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
		}
	})
	return dir
}

// appears reports whether path exists within d.
func appears(path string, d time.Duration) bool {
	for deadline := time.Now().Add(d); ; time.Sleep(20 * time.Millisecond) {
		if _, err := os.Stat(path); err == nil {
			return true
		}
		if time.Now().After(deadline) {
			return false
		}
	}
}

// shortGrace sets the stop grace for one test.
func shortGrace(t *testing.T, grace time.Duration) {
	t.Helper()
	g := fetchStopGrace
	fetchStopGrace = grace
	t.Cleanup(func() { fetchStopGrace = g })
}

// holdsALock is a fetch whose SIGTERM handler records the signal and removes a
// lock file in dir, as git's handler removes the locks it holds, and which then
// takes the lock and runs on in a child that holds its stderr, as git's ssh
// does. It writes git.ready in dir once that child runs, so a test that waits
// for git.ready signals a group that holds every process the fetch starts: a
// child forked after a signal to its group never gets it, and one that held
// stderr would keep the fetch waiting on its pipe.
func holdsALock(dir string) (trap, script string) {
	lock, term, ready := filepath.Join(dir, "main.lock"), filepath.Join(dir, "git.term"), filepath.Join(dir, "git.ready")
	return "trap 'touch \"" + term + "\"; rm -f \"" + lock + "\"; exit 143' TERM",
		"touch '" + lock + "'\nsleep 30 &\ntouch '" + ready + "'\nwait $!\n"
}

// fetchBound is the bound the tests stop a fetch at, long enough for a loaded
// host to start the fake git and set its handler first.
const fetchBound = 2 * time.Second

func TestAFetchStoppedAtItsBoundGetsASIGTERMAndLeavesNoLock(t *testing.T) {
	marks := t.TempDir()
	trap, script := holdsALock(marks)
	dir := fakeFetch(t, trap, script)
	shortGrace(t, 30*time.Second)
	ctx, cancel := context.WithTimeout(context.Background(), fetchBound)
	defer cancel()

	start := time.Now()
	err := FetchBranch(ctx, dir, "main")
	if elapsed := time.Since(start); elapsed > 10*time.Second {
		t.Errorf("the fetch returned after %s: git did not exit on the stop at its bound", elapsed.Round(time.Millisecond))
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Errorf("a fetch stopped at its bound returned %v, want the bound's error", err)
	}
	if !appears(filepath.Join(marks, "git.term"), 5*time.Second) {
		t.Errorf("git was stopped without a SIGTERM it could handle")
	}
	if _, err := os.Stat(filepath.Join(marks, "main.lock")); !os.IsNotExist(err) {
		t.Errorf("the stopped fetch left its lock behind (%v), which fails every later fetch of the branch", err)
	}
}

func TestAFetchThatOutlivesItsStopGraceIsKilled(t *testing.T) {
	dir := fakeFetch(t, "trap '' TERM", "sleep 30\n")
	shortGrace(t, time.Second)
	ctx, cancel := context.WithTimeout(context.Background(), fetchBound)
	defer cancel()

	start := time.Now()
	err := FetchBranch(ctx, dir, "main")
	elapsed := time.Since(start)
	if elapsed > 10*time.Second {
		t.Errorf("the fetch returned after %s, past its bound and its %s grace", elapsed.Round(time.Millisecond), fetchStopGrace)
	}
	if elapsed < fetchStopGrace {
		t.Errorf("the fetch returned after %s, before the %s grace a git that ignores SIGTERM gets", elapsed.Round(time.Millisecond), fetchStopGrace)
	}
	if err == nil {
		t.Errorf("a fetch killed after its grace reported success")
	}
}

func TestAStopSignalReachesGitsGroupAndEndsTheFetch(t *testing.T) {
	// git leads its own group, so the SIGTERM the order runner sends this
	// process's group does not reach it. The fetch passes it on and returns
	// Interrupted, for the caller to end the process with.
	marks := t.TempDir()
	trap, script := holdsALock(marks)
	dir := fakeFetch(t, trap, script)
	shortGrace(t, 30*time.Second)
	// The test's own relay, so a fetch that does not take the signal fails this
	// test rather than ending the test binary.
	held := make(chan os.Signal, 1)
	signal.Notify(held, syscall.SIGTERM)
	t.Cleanup(func() { signal.Stop(held) })

	done := make(chan error, 1)
	go func() { done <- FetchBranch(context.Background(), dir, "main") }()
	if !appears(filepath.Join(marks, "git.ready"), 5*time.Second) {
		t.Fatal("the fake git never started its fetch")
	}
	if err := syscall.Kill(os.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-done:
		var stopped *Interrupted
		if !errors.As(err, &stopped) || stopped.Signal != syscall.SIGTERM {
			t.Errorf("a fetch this process's SIGTERM stopped returned %v, want Interrupted by SIGTERM", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the fetch did not end on the SIGTERM this process received")
	}
	if !appears(filepath.Join(marks, "git.term"), 5*time.Second) {
		t.Errorf("the SIGTERM this process received never reached git's group")
	}
	if _, err := os.Stat(filepath.Join(marks, "main.lock")); !os.IsNotExist(err) {
		t.Errorf("the interrupted fetch left its lock behind: %v", err)
	}
}

func TestContainsReadsTheClonesHistory(t *testing.T) {
	dir, landed, side := clone(t)
	if err := FetchBranch(context.Background(), dir, "main"); err != nil {
		t.Fatal(err)
	}
	if err := FetchBranch(context.Background(), dir, "side"); err != nil {
		t.Fatal(err)
	}
	base := gitIn(t, dir, "rev-parse", "HEAD")
	absent := strings.Repeat("1", 40)
	for _, c := range []struct {
		name             string
		commit, ancestor string
		want             bool
	}{
		{"a commit contains itself", landed, landed, true},
		{"a commit contains its parent", landed, base, true},
		{"a parent does not contain its child", base, landed, false},
		{"diverged commits contain neither", side, landed, false},
		{"a commit the clone lacks contains nothing", absent, base, false},
		{"an ancestor the clone lacks is in no history it holds", landed, absent, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, err := Contains(dir, c.commit, c.ancestor)
			if err != nil || got != c.want {
				t.Fatalf("Contains(%s, %s) = %v, %v, want %v", c.commit[:7], c.ancestor[:7], got, err, c.want)
			}
		})
	}
	if _, err := Contains(dir, "HEAD", base); err == nil {
		t.Fatal("Contains took a name that is no object id")
	}
}
