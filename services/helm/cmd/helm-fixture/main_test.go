package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
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
	rig := filepath.Join(moduleRoot, defaultRigBoard)
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
		{"a board that is not JSON", []string{"--board", notJSON, "--rig-board", rig, "--addr", "127.0.0.1:0"}, noEnv, 1, "not JSON"},
		{"a rig document it cannot read", []string{"--board", board, "--rig-board", filepath.Join(t.TempDir(), "missing.json"), "--addr", "127.0.0.1:0"}, noEnv, 1, "read the rig document"},
		{"a rig document that is not JSON", []string{"--board", board, "--rig-board", notJSON, "--addr", "127.0.0.1:0"}, noEnv, 1, "rig document is not a JSON object"},
		{"an answer that is not JSON", []string{"--board", board, "--rig-board", rig, "--answers", badAnswers, "--addr", "127.0.0.1:0"}, noEnv, 1, "dismiss.json"},
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
	rig := filepath.Join(moduleRoot, defaultRigBoard)
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
	go func() {
		done <- run(ctx, []string{"--board", board, "--rig-board", rig, "--answers", answers}, env, &stderr, ready)
	}()

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
	wantRig, err := os.ReadFile(rig)
	if err != nil {
		t.Fatal(err)
	}
	if res, body := get(t, http.MethodGet, base+"/helm/rigs/gc-toolkit", ""); res.StatusCode != http.StatusOK || !sameJSON(t, rigBoardOf(t, body), wantRig) {
		t.Errorf("GET /helm/rigs/gc-toolkit: %d, want the rig document file as its board", res.StatusCode)
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

// declaredServe is the command a city declares as gc-toolkit's
// ui_serve_command, which gctk rig serve runs for a sitting's live copy of the
// board. docs/review-demo.md, the rig's demo guide, names the same command on
// its **Serve:** line, so a capture shows the board a live copy shows. It runs
// from the worktree's root, and it ends with the fixture's own invocation, so a
// capture can add the fixture's flags to it.
const declaredServe = "cd services/helm && exec go run ./cmd/helm-fixture"

// docGuide reads docs/review-demo.md, the rig's demo guide, and returns the
// lines of its section "Bring the app up", the value of that section's
// **Serve:** line, and the board's capture: the demo-screenshot.sh call whose
// --script is board.md. The page gives the capture in prose, as inline code
// that can wrap, so the capture is read with the page's line breaks folded into
// spaces, and it runs to the end of its code span.
func docGuide(t *testing.T) (section []string, serve, capture string) {
	t.Helper()
	doc, err := os.ReadFile(filepath.Join(moduleRoot, "../../docs/review-demo.md"))
	if err != nil {
		t.Fatal(err)
	}
	in := false
	for _, line := range strings.Split(string(doc), "\n") {
		if strings.HasPrefix(line, "## ") {
			in = strings.TrimSpace(strings.TrimPrefix(line, "## ")) == "Bring the app up"
			continue
		}
		if in {
			section = append(section, line)
		}
	}
	if section == nil {
		t.Fatal("docs/review-demo.md has no section \"Bring the app up\"")
	}
	for _, line := range section {
		if m := regexp.MustCompile("^\\*\\*Serve:\\*\\* `([^`]+)`$").FindStringSubmatch(strings.TrimSpace(line)); m != nil {
			if serve != "" {
				t.Fatalf("the guide's section \"Bring the app up\" names **Serve:** twice")
			}
			serve = m[1]
		}
	}
	text := strings.Join(strings.Fields(string(doc)), " ")
	for _, c := range regexp.MustCompile("demo-screenshot\\.sh\"? page [^`]*").FindAllString(text, -1) {
		if strings.Contains(c, "--script board.md") {
			if capture != "" {
				t.Fatalf("docs/review-demo.md gives more than one capture of the board:\n%s\n%s", capture, c)
			}
			capture = c
		}
	}
	if capture == "" {
		t.Fatal("docs/review-demo.md gives no capture of the board")
	}
	return section, serve, capture
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
// PORT, as gctk rig serve does for a copy, waits for it to answer, and stops
// its process group when the test ends, as a stop of the copy does.
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

// TestTheDocumentedCommandServesTheBoard checks that docs/review-demo.md, the
// rig's demo guide, names the rig's declared command as the app a capture
// brings up, run from the worktree's root on the free port gctk rig serve hands
// a copy, and that the board's capture takes the app from the guide. It runs
// that command, and reads back what the capture's browser reads: the app, the
// board as JSON at its own path, and a verb refused for want of an answer. It
// runs the command again with the --answers the page tells a reviewer to add,
// and a click's answer comes back.
func TestTheDocumentedCommandServesTheBoard(t *testing.T) {
	if testing.Short() {
		t.Skip("builds and runs the command with go run")
	}
	section, serve, capture := docGuide(t)
	if serve != declaredServe {
		t.Errorf("the guide's **Serve:** line serves %q; it serves %q, the command the city declares as gc-toolkit's ui_serve_command, from the worktree's root", serve, declaredServe)
	}
	for _, line := range section {
		if strings.HasPrefix(strings.TrimSpace(line), "**Port:**") {
			t.Errorf("the guide names a port, %q, which a serve command's copy does not take: it gets a free port of its own as $PORT", line)
		}
	}
	if !strings.Contains(capture, "--guide <worktree>") || strings.Contains(capture, "--serve") || strings.Contains(capture, "--port") {
		t.Errorf("the board's capture names its own app; it takes the app from the guide with --guide <worktree>: %s", capture)
	}
	repo, err := filepath.Abs(filepath.Join(moduleRoot, "../.."))
	if err != nil {
		t.Fatal(err)
	}
	mod, err := filepath.Abs(moduleRoot)
	if err != nil {
		t.Fatal(err)
	}
	board, err := os.ReadFile(filepath.Join(mod, defaultBoard))
	if err != nil {
		t.Fatal(err)
	}
	rig, err := os.ReadFile(filepath.Join(mod, defaultRigBoard))
	if err != nil {
		t.Fatal(err)
	}
	shell, err := os.ReadFile(filepath.Join(mod, "web/dist/index.html"))
	if err != nil {
		t.Fatal(err)
	}

	t.Run("as the page gives it", func(t *testing.T) {
		base := startServe(t, declaredServe, repo)
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
		if res, body := get(t, http.MethodGet, base+"/helm/rigs/gc-toolkit", ""); res.StatusCode != http.StatusOK || !sameJSON(t, rigBoardOf(t, body), rig) {
			t.Errorf("GET /helm/rigs/gc-toolkit: %d, want %s as its board", res.StatusCode, defaultRigBoard)
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
		base := startServe(t, declaredServe+" --answers "+answers, repo)
		if res, body := get(t, http.MethodPost, base+"/helm/dismiss", ""); res.StatusCode != http.StatusOK || string(body) != answer {
			t.Errorf("POST /helm/dismiss: %d %s, want the canned answer", res.StatusCode, body)
		}
	})
}

// rigBoardOf is the board a rig route's answer carries.
func rigBoardOf(t *testing.T, body []byte) []byte {
	t.Helper()
	var answer struct {
		ReadAt string          `json:"read_at"`
		Board  json.RawMessage `json:"board"`
	}
	if err := json.Unmarshal(body, &answer); err != nil {
		t.Fatalf("the rig answer is not JSON: %v", err)
	}
	if answer.ReadAt == "" {
		t.Error("the rig answer carries no read time")
	}
	return answer.Board
}

// sameJSON reports whether two JSON texts hold the same value.
func sameJSON(t *testing.T, a, b []byte) bool {
	t.Helper()
	var x, y any
	if err := json.Unmarshal(a, &x); err != nil {
		t.Fatalf("not JSON: %v", err)
	}
	if err := json.Unmarshal(b, &y); err != nil {
		t.Fatalf("not JSON: %v", err)
	}
	return reflect.DeepEqual(x, y)
}
