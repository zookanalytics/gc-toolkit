package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// moduleRoot is services/helm, two levels up from this package: the directory
// the command runs from, where its default board path resolves.
const moduleRoot = "../.."

// TestLinksNothingThatReachesACity holds the command's import graph to the
// standard library, the app's package and package fixture. A bead source or a
// write tool anywhere in it could read or write the city a capture runs beside,
// and the beads library would bring back the cgo build this command exists to
// avoid.
func TestLinksNothingThatReachesACity(t *testing.T) {
	out, err := exec.Command("go", "list", "-deps", "-f", "{{if not .Standard}}{{.ImportPath}}{{end}}", ".").Output()
	if err != nil {
		t.Fatalf("go list -deps: %v", err)
	}
	allowed := map[string]bool{
		"github.com/zookanalytics/gc-toolkit/services/helm/cmd/helm-fixture": true,
		"github.com/zookanalytics/gc-toolkit/services/helm/internal/fixture": true,
		"github.com/zookanalytics/gc-toolkit/services/helm/web":              true,
	}
	for _, pkg := range strings.Fields(string(out)) {
		if !allowed[pkg] {
			t.Errorf("helm-fixture links %s, outside the standard library, the app's package and package fixture", pkg)
		}
	}
}

func noEnv(string) string { return "" }

func TestRunRefusesWhatItCannotServe(t *testing.T) {
	board := filepath.Join(moduleRoot, defaultBoard)
	badAnswers := t.TempDir()
	if err := os.WriteFile(filepath.Join(badAnswers, "dismiss.json"), []byte("dismissed"), 0o644); err != nil {
		t.Fatal(err)
	}
	notJSON := filepath.Join(t.TempDir(), "board.json")
	if err := os.WriteFile(notJSON, []byte("<html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		args []string
		env  func(string) string
		want int
		says string
	}{
		{"no address and no PORT", []string{"--board", board}, noEnv, 2, "set PORT"},
		{"an address off this host", []string{"--board", board, "--addr", "0.0.0.0:0"}, noEnv, 2, "not a loopback address"},
		{"an address with no port", []string{"--board", board, "--addr", "127.0.0.1"}, noEnv, 2, "not host:port"},
		{"an argument it does not take", []string{"--board", board, "--addr", "127.0.0.1:0", "extra"}, noEnv, 2, "takes no arguments"},
		{"a flag it does not take", []string{"--port", "1"}, noEnv, 2, "flag provided but not defined"},
		{"a board it cannot read", []string{"--board", filepath.Join(t.TempDir(), "missing.json"), "--addr", "127.0.0.1:0"}, noEnv, 1, "read the board answer"},
		{"a board that is not JSON", []string{"--board", notJSON, "--addr", "127.0.0.1:0"}, noEnv, 1, "not JSON"},
		{"an answer that is not JSON", []string{"--board", board, "--answers", badAnswers, "--addr", "127.0.0.1:0"}, noEnv, 1, "dismiss.json"},
	}
	for _, c := range cases {
		var stderr bytes.Buffer
		ctx, cancel := context.WithCancel(context.Background())
		cancel() // a case that starts serving stops at once instead of hanging the test
		if got := run(ctx, c.args, c.env, &stderr, nil); got != c.want {
			t.Errorf("%s: exit %d, want %d (stderr %q)", c.name, got, c.want, stderr.String())
		}
		if !strings.Contains(stderr.String(), c.says) {
			t.Errorf("%s: stderr %q does not say %q", c.name, stderr.String(), c.says)
		}
	}
}

func get(t *testing.T, method, url, accept string) (*http.Response, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, url, strings.NewReader(`{"bead":"tk-abc12"}`))
	if err != nil {
		t.Fatal(err)
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, url, err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return res, body
}

// TestRunServesUntilItIsStopped starts the fixture on PORT the way a capture's
// --serve command does, reads the board, the app and a canned answer back, then
// cancels it as the engine's SIGTERM would.
func TestRunServesUntilItIsStopped(t *testing.T) {
	answers := t.TempDir()
	if err := os.WriteFile(filepath.Join(answers, "dismiss.json"), []byte(`{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	board := filepath.Join(moduleRoot, defaultBoard)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ready := make(chan string, 1)
	done := make(chan int, 1)
	var stderr bytes.Buffer
	env := func(k string) string {
		if k == "PORT" {
			return "0"
		}
		return ""
	}
	go func() { done <- run(ctx, []string{"--board", board, "--answers", answers}, env, &stderr, ready) }()

	var base string
	select {
	case addr := <-ready:
		base = "http://" + addr
	case code := <-done:
		t.Fatalf("run exited %d before it served: %s", code, stderr.String())
	case <-time.After(10 * time.Second):
		t.Fatal("run did not start serving within 10s")
	}
	if !strings.HasPrefix(base, "http://127.0.0.1:") {
		t.Errorf("PORT served on %s, want 127.0.0.1", base)
	}

	want, err := os.ReadFile(board)
	if err != nil {
		t.Fatal(err)
	}
	res, body := get(t, http.MethodGet, base+"/helm", "")
	if res.StatusCode != http.StatusOK || !bytes.Equal(body, want) || res.Header.Get("Content-Type") != "application/json" {
		t.Errorf("GET /helm: %d %s, want the board file as application/json", res.StatusCode, res.Header.Get("Content-Type"))
	}
	shell, err := os.ReadFile(filepath.Join(moduleRoot, "web/dist/index.html"))
	if err != nil {
		t.Fatal(err)
	}
	if res, body := get(t, http.MethodGet, base+"/", "text/html"); res.StatusCode != http.StatusOK || !bytes.Equal(body, shell) {
		t.Errorf("GET /: %d, want the embedded app shell", res.StatusCode)
	}
	if res, body := get(t, http.MethodPost, base+"/helm/dismiss", ""); res.StatusCode != http.StatusOK || !strings.Contains(string(body), `"message":"dismissed"`) {
		t.Errorf("POST /helm/dismiss: %d %s, want the canned answer", res.StatusCode, body)
	}

	cancel()
	select {
	case code := <-done:
		if code != 0 {
			t.Errorf("run exited %d after a stop, want 0: %s", code, stderr.String())
		}
	case <-time.After(5 * time.Second):
		t.Fatal("run did not stop within 5s of its context ending")
	}
	if !strings.Contains(stderr.String(), "with 1 canned answer(s)") {
		t.Errorf("stderr %q does not say how many answers it serves", stderr.String())
	}
}

// docCommand reads the board's capture from docs/review-demo.md and returns the
// command it gives demo-screenshot.sh as --serve, the directory its --cwd names
// under <worktree>, and its --port. The page gives the capture in prose, as
// inline code that can wrap, so the page is read with its line breaks folded
// into spaces and the capture runs to the end of its code span.
func docCommand(t *testing.T) (serve, cwd, port string) {
	t.Helper()
	doc, err := os.ReadFile(filepath.Join(moduleRoot, "../../docs/review-demo.md"))
	if err != nil {
		t.Fatal(err)
	}
	text := strings.Join(strings.Fields(string(doc)), " ")
	var capture string
	for _, c := range regexp.MustCompile("demo-screenshot\\.sh\"? page [^`]*").FindAllString(text, -1) {
		if strings.Contains(c, "helm-fixture") {
			if capture != "" {
				t.Fatalf("docs/review-demo.md gives more than one capture of the board:\n%s\n%s", capture, c)
			}
			capture = c
		}
	}
	if capture == "" {
		t.Fatal("docs/review-demo.md gives no capture of the board through helm-fixture")
	}
	for _, f := range []struct {
		re  *regexp.Regexp
		out *string
	}{
		{regexp.MustCompile(`--serve "([^"]+)"`), &serve},
		{regexp.MustCompile(`--cwd "?<worktree>/([^"\s]+)`), &cwd},
		{regexp.MustCompile(`--port (\S+)`), &port},
	} {
		m := f.re.FindStringSubmatch(capture)
		if m == nil {
			t.Fatalf("the board's capture has no %s: %s", f.re, capture)
		}
		*f.out = m[1]
	}
	return serve, cwd, port
}

// lockedBuffer collects a command's output, which the test reads while the
// command may still be writing it.
type lockedBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (l *lockedBuffer) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.Write(p)
}

func (l *lockedBuffer) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.b.String()
}

// startServe runs cmdline with bash from dir on a free port it hands over as
// PORT, as demo-screenshot.sh's --port 0 does for a --serve command, waits for it
// to answer, and stops its process group when the test ends, as the engine does.
func startServe(t *testing.T, cmdline, dir string) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	ln.Close()

	var stderr lockedBuffer
	cmd := exec.Command("bash", "-c", cmdline)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "PORT="+port)
	cmd.Stdout, cmd.Stderr = &stderr, &stderr
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	// exited is closed once the command has exited, so every reader sees it,
	// the wait below and the cleanup alike.
	exited := make(chan struct{})
	var waitErr error
	go func() { waitErr = cmd.Wait(); close(exited) }()
	t.Cleanup(func() {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
		select {
		case <-exited:
		case <-time.After(10 * time.Second):
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			<-exited
		}
	})

	base := "http://127.0.0.1:" + port
	// A cold build cache makes go run compile the standard library's HTTP stack
	// first, so this waits longer than a capture's engine does.
	deadline := time.Now().Add(3 * time.Minute)
	for time.Now().Before(deadline) {
		select {
		case <-exited:
			t.Fatalf("%q exited before it answered: %v\n%s", cmdline, waitErr, stderr.String())
		default:
		}
		if res, err := http.Get(base + "/"); err == nil {
			res.Body.Close()
			if res.StatusCode == http.StatusOK {
				return base
			}
		}
		time.Sleep(250 * time.Millisecond)
	}
	t.Fatalf("%q did not answer on %s within 3m:\n%s", cmdline, base, stderr.String())
	return ""
}

// TestTheDocumentedCommandServesTheBoard runs the --serve command
// docs/review-demo.md gives a capture of the board, from the directory its --cwd
// names, on the free port its --port 0 has demo-screenshot.sh hand over, and
// reads back what the capture's browser reads: the app, the board as JSON at its
// own path, and a verb refused for want of an answer. It runs the command again
// with the --answers the page tells a reviewer to add, and a click's answer
// comes back.
func TestTheDocumentedCommandServesTheBoard(t *testing.T) {
	if testing.Short() {
		t.Skip("builds and runs the command with go run")
	}
	serve, cwd, port := docCommand(t)
	if port != "0" {
		t.Errorf("the board's capture passes --port %s; it needs --port 0, the free port the command reads from PORT", port)
	}
	repo, err := filepath.Abs(filepath.Join(moduleRoot, "../.."))
	if err != nil {
		t.Fatal(err)
	}
	mod, err := filepath.Abs(moduleRoot)
	if err != nil {
		t.Fatal(err)
	}
	if rel, _ := filepath.Rel(repo, mod); rel != cwd {
		t.Fatalf("the board's capture runs its command from <worktree>/%s, but the command's default board resolves from <worktree>/%s", cwd, rel)
	}
	board, err := os.ReadFile(filepath.Join(mod, defaultBoard))
	if err != nil {
		t.Fatal(err)
	}
	shell, err := os.ReadFile(filepath.Join(mod, "web/dist/index.html"))
	if err != nil {
		t.Fatal(err)
	}

	t.Run("as the page gives it", func(t *testing.T) {
		base := startServe(t, serve, mod)
		if res, body := get(t, http.MethodGet, base+"/", "text/html"); res.StatusCode != http.StatusOK || !bytes.Equal(body, shell) {
			t.Errorf("GET /: %d, want the app shell the reviewed commit embeds", res.StatusCode)
		}
		res, body := get(t, http.MethodGet, base+"/helm", "")
		if res.StatusCode != http.StatusOK || !bytes.Equal(body, board) {
			t.Errorf("GET /helm: %d, want %s byte for byte", res.StatusCode, defaultBoard)
		}
		if ct := res.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("GET /helm: Content-Type %q, want application/json", ct)
		}
		if res, body := get(t, http.MethodPost, base+"/helm/dismiss", ""); res.StatusCode != http.StatusServiceUnavailable || !strings.Contains(string(body), `"reason":"unavailable"`) {
			t.Errorf("POST /helm/dismiss with no answer: %d %s, want 503 unavailable", res.StatusCode, body)
		}
	})

	t.Run("with the answers a reviewer adds", func(t *testing.T) {
		answers := t.TempDir()
		answer := `{"bead":"tk-abc12","verb":"dismiss","message":"dismissed"}`
		if err := os.WriteFile(filepath.Join(answers, "dismiss.json"), []byte(answer), 0o644); err != nil {
			t.Fatal(err)
		}
		base := startServe(t, serve+" --answers "+answers, mod)
		if res, body := get(t, http.MethodPost, base+"/helm/dismiss", ""); res.StatusCode != http.StatusOK || string(body) != answer {
			t.Errorf("POST /helm/dismiss: %d %s, want the canned answer", res.StatusCode, body)
		}
	})
}
