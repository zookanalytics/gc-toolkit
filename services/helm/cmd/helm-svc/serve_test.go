package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
	"github.com/zookanalytics/gc-toolkit/services/helm/internal/source"
)

// idleSource answers the board's gather with no anchors.
type idleSource struct{}

func (idleSource) Gather(context.Context) (*source.Result, error) { return &source.Result{}, nil }

// startServing serves srv through serveUntil on a loopback listener, and
// returns the board's address, stop, which ends serveUntil's context as a
// SIGTERM ends serve's, and what serveUntil returns, closed once read.
func startServing(t *testing.T, srv *server.Server) (addr string, stop func(), served <-chan error) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	out := make(chan error, 1)
	go func() {
		out <- serveUntil(ctx, &http.Server{Handler: srv.Handler()}, ln, srv)
		close(out)
	}()
	t.Cleanup(func() {
		cancel()
		if err := <-out; err != nil {
			t.Errorf("serveUntil returned %v, want nil", err)
		}
	})
	return "http://" + ln.Addr().String(), cancel, out
}

// stopped waits for serveUntil to return after a stop, and fails unless it
// returned nil.
func stopped(t *testing.T, served <-chan error) {
	t.Helper()
	select {
	case err := <-served:
		if err != nil {
			t.Fatalf("serveUntil returned %v after a stop, want nil", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("the board did not stop")
	}
}

// logLines is the log's output while a test runs, safe to read as it is
// written.
type logLines struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *logLines) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *logLines) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// captureLog sends the log's output to the lines it returns until the test
// ends.
func captureLog(t *testing.T) *logLines {
	t.Helper()
	lines := &logLines{}
	log.SetOutput(lines)
	t.Cleanup(func() { log.SetOutput(os.Stderr) })
	return lines
}

// fetch sends req on a connection of its own and answers its status and body
// as one line, or why it got no answer.
func fetch(req *http.Request) string {
	req.Close = true
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "no answer: " + err.Error()
	}
	defer func() { _ = resp.Body.Close() }()
	body, _ := io.ReadAll(resp.Body)
	return fmt.Sprintf("%d %s", resp.StatusCode, body)
}

// storeStub puts a gc on PATH that lists the rigs one and two, and runs every
// store call in the group it leads with a child started under it, appending
// its pid to the file it returns and waiting.
func storeStub(t *testing.T) (groups string) {
	t.Helper()
	bin := t.TempDir()
	groups = filepath.Join(bin, "groups")
	stub := `#!/bin/sh
case "$*" in
  "rig list --json") echo '{"rigs":[{"name":"one","path":"/city/rigs/one"},{"name":"two","path":"/city/rigs/two"}]}' ;;
  "bd "*) sleep 30 & echo $$ >> '` + groups + `'; wait ;;
  *) echo "stub gc: no answer for $*" >&2; exit 9 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, v := range []string{"GC_HELM_GC_BIN", "GC_CITY", "GC_CITY_PATH", "GC_CITY_ROOT", "GC_RIG", "GC_RIG_ROOT", "BEADS_DIR"} {
		t.Setenv(v, "")
	}
	t.Cleanup(func() {
		for _, pid := range readGroups(groups) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
		}
	})
	return groups
}

func readGroups(groups string) []int {
	raw, _ := os.ReadFile(groups)
	var pids []int
	for _, f := range strings.Fields(string(raw)) {
		if pid, err := strconv.Atoi(f); err == nil && pid > 0 {
			pids = append(pids, pid)
		}
	}
	return pids
}

// stuckGroups waits for n store calls to have started and returns the group
// each leads.
func stuckGroups(t *testing.T, groups string, n int) []int {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		if pids := readGroups(groups); len(pids) >= n {
			return pids
		}
		if time.Now().After(deadline) {
			t.Fatalf("%d of %d store calls started", len(readGroups(groups)), n)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// A store read runs in a process group of its own, which the SIGTERM that
// stops the board's group does not reach. Two reads in flight at once both end
// on one stop, and serveUntil returns only once each has: the read's own wait
// has reaped its group's leader, a child of this process, by then. The
// requests waiting on them answer that the board is stopping, so the drain
// finishes within the grace.
func TestAStopEndsEveryStoreReadInFlightBeforeServeReturns(t *testing.T) {
	logs := captureLog(t)
	groups := storeStub(t)
	srv := server.New(idleSource{}, time.Minute, server.WithRigBoard(source.NewGC(""), time.Minute))
	addr, stop, served := startServing(t, srv)

	answers := make(chan string, 2)
	for _, rig := range []string{"one", "two"} {
		req, err := http.NewRequest(http.MethodGet, addr+"/helm/rigs/"+rig, nil)
		if err != nil {
			t.Fatal(err)
		}
		go func() { answers <- fetch(req) }()
	}
	pids := stuckGroups(t, groups, 2)

	stop()
	stopped(t, served)
	for _, pid := range pids {
		if err := syscall.Kill(pid, 0); !errors.Is(err, syscall.ESRCH) {
			t.Errorf("the store read leading group %d had not returned when serveUntil did (kill: %v)", pid, err)
		}
	}
	for _, pid := range pids {
		deadline := time.Now().Add(5 * time.Second)
		for syscall.Kill(-pid, 0) == nil {
			if time.Now().After(deadline) {
				t.Fatalf("the store read's process group %d outlived the stop", pid)
			}
			time.Sleep(20 * time.Millisecond)
		}
	}
	for range 2 {
		if got := <-answers; !strings.HasPrefix(got, "502 ") || !strings.Contains(got, server.ErrStopping.Error()) {
			t.Errorf("a request whose read the stop ended answered %q, want a 502 saying the board is stopping", got)
		}
	}
	if !strings.Contains(logs.String(), "shut down cleanly") {
		t.Errorf("the drain did not finish within the grace; the log says:\n%s", logs)
	}
}

// slowWrite stands in for the write tool: a write that takes a set time, and
// says when it starts and when it has finished.
type slowWrite struct {
	took              time.Duration
	started, finished chan struct{}
}

func (w *slowWrite) Run(context.Context, string, string) (server.ToolResult, error) {
	close(w.started)
	time.Sleep(w.took)
	close(w.finished)
	return server.ToolResult{Stdout: "gc-helm: dismiss: dismissed tk-abc12\n"}, nil
}

// A stop gives a request it finds open up to shutdownGrace to finish, here a
// write. serveUntil returns once the write has finished and logs that the
// board shut down cleanly. A write still running when the grace ends is left
// to the process's exit, and the log says requests were still open.
func TestAStopGivesAnOpenWriteTheGraceToFinish(t *testing.T) {
	for _, c := range []struct {
		name     string
		took     time.Duration
		finished bool
		log      string
	}{
		{"within the grace", 300 * time.Millisecond, true, "shut down cleanly"},
		{"past the grace", shutdownGrace + 300*time.Millisecond, false, "shut down with requests still open after " + shutdownGrace.String()},
	} {
		t.Run(c.name, func(t *testing.T) {
			logs := captureLog(t)
			w := &slowWrite{took: c.took, started: make(chan struct{}), finished: make(chan struct{})}
			srv := server.New(idleSource{}, time.Minute, server.WithActuator(w))
			addr, stop, served := startServing(t, srv)

			req, err := http.NewRequest(http.MethodPost, addr+"/helm/dismiss", strings.NewReader(`{"bead":"tk-abc12"}`))
			if err != nil {
				t.Fatal(err)
			}
			req.Header.Set("Content-Type", "application/json")
			answer := make(chan string, 1)
			go func() { answer <- fetch(req) }()
			select {
			case <-w.started:
			case <-time.After(5 * time.Second):
				t.Fatal("the write did not start")
			}

			stop()
			stopped(t, served)
			finished := false
			select {
			case <-w.finished:
				finished = true
			default:
			}
			if finished != c.finished {
				t.Errorf("when serveUntil returned the write had finished: %v, want %v", finished, c.finished)
			}
			if !strings.Contains(logs.String(), c.log) {
				t.Errorf("the log does not say %q:\n%s", c.log, logs)
			}
			if got := <-answer; !strings.HasPrefix(got, "200 ") {
				t.Errorf("the write answered %q, want 200", got)
			}
		})
	}
}
