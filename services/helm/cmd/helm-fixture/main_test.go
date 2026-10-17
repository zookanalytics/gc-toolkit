package main

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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
