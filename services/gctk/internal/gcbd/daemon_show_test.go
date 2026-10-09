package gcbd

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestMain keeps the subprocess-path suites off the live supervisor. The exec
// and List tests drive a stubbed `gc` on PATH; GC_NO_API=1 stops New() from
// discovering the ambient session's real daemon and routing a read there
// instead of to the stub. The daemon-path tests below build a Client pointed at
// a fake server directly, so GC_NO_API does not reach them.
func TestMain(m *testing.M) {
	os.Setenv("GC_NO_API", "1")
	os.Exit(m.Run())
}

// gcShowStub writes an absolute `gc` stub that answers every call with showJSON
// and, when marker is non-empty, records each invocation's args there — so a
// Client whose bin points at it reveals whether the subprocess read path ran at
// all. The marker write is redirected to a file, never stdout, so it cannot
// pollute the payload cmd.Output() reads.
func gcShowStub(t *testing.T, showJSON, marker string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "gc")
	var b strings.Builder
	b.WriteString("#!/bin/sh\n")
	if marker != "" {
		fmt.Fprintf(&b, "printf '%%s\\n' \"$*\" >> %q\n", marker)
	}
	fmt.Fprintf(&b, "cat <<'GCEOF'\n%s\nGCEOF\n", showJSON)
	if err := os.WriteFile(p, []byte(b.String()), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

// daemonServing returns a fake supervisor that serves beadJSON at any path and
// records the last path it was asked for, so a test can assert the per-city URL
// shape.
func daemonServing(t *testing.T, beadJSON string) (*httptest.Server, *string) {
	t.Helper()
	var gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath = r.URL.Path
		fmt.Fprint(w, beadJSON)
	}))
	t.Cleanup(srv.Close)
	return srv, &gotPath
}

// A healthy daemon read returns the daemon's bead and never forks `gc bd` —
// the whole point of the change. The stub's distinct value and the fork marker
// prove the daemon answered and the subprocess stayed untouched.
func TestShowReadsViaDaemonWithoutForkingBd(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "forks")
	srv, gotPath := daemonServing(t,
		`{"id":"b-1","status":"open","assignee":"someone","metadata":{"merge_result":"pull_request"}}`)
	c := &Client{
		bin:     gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, marker),
		httpc:   srv.Client(),
		baseURL: srv.URL,
		city:    "testcity",
	}
	b := c.Show("b-1")
	if b == nil {
		t.Fatal("Show via daemon = nil")
	}
	if got := b.Meta("merge_result"); got != "pull_request" {
		t.Errorf("merge_result = %q, want pull_request (the daemon's value, not the stub's)", got)
	}
	if got := b.AssigneeString(); got != "someone" {
		t.Errorf("assignee = %q, want someone", got)
	}
	if want := "/v0/city/testcity/bead/b-1"; *gotPath != want {
		t.Errorf("daemon path = %q, want %q", *gotPath, want)
	}
	if _, err := os.Stat(marker); !os.IsNotExist(err) {
		t.Error("the healthy daemon read forked gc bd (fork marker exists); it must not touch the subprocess")
	}
}

// Every way the daemon can fail to answer a trusted bead falls through to the
// `gc bd` read, so the daemon only ever makes a read faster, never changes its
// answer. The stub's from_bd value proves the fallback arm ran.
func TestShowFallsBackToBdWhenDaemonUnavailable(t *testing.T) {
	const bdPayload = `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`
	assertFellBack := func(t *testing.T, c *Client) {
		t.Helper()
		b := c.Show("b-1")
		if b == nil || b.Meta("merge_result") != "from_bd" {
			t.Fatalf("Show = %+v, want the bd fallback value from_bd", b)
		}
	}

	t.Run("non-200 status", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, `{"code":"bead-not-found"}`, http.StatusNotFound)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: "c"})
	})

	t.Run("transport failure", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
		dead := srv.URL
		srv.Close() // nothing listens now; the GET is refused
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: &http.Client{}, baseURL: dead, city: "c"})
	})

	t.Run("undecodable 200 body", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `not json`)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: "c"})
	})

	t.Run("200 with no id is a miss, not a bead", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `{"status":"open"}`)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: "c"})
	})
}

// ShowDirect is the authoritative read: it forks `gc bd` and never consults the
// daemon, even a healthy one, so a read-back observes the write it is verifying
// and carries notes the daemon payload omits.
func TestShowDirectBypassesDaemon(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "forks")
	srv, _ := daemonServing(t, `{"id":"b-1","metadata":{"merge_result":"from_daemon"}}`)
	c := &Client{
		bin:     gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, marker),
		httpc:   srv.Client(),
		baseURL: srv.URL,
		city:    "c",
	}
	b := c.ShowDirect("b-1")
	if b == nil || b.Meta("merge_result") != "from_bd" {
		t.Fatalf("ShowDirect = %+v, want the bd value from_bd, never the daemon's", b)
	}
	if _, err := os.Stat(marker); os.IsNotExist(err) {
		t.Error("ShowDirect did not fork gc bd; the authoritative read must never come from the daemon cache")
	}
}

// With no daemon configured — the default from New() under GC_NO_API, or any
// city-less session — Show reads straight through the subprocess.
func TestShowWithoutDaemonConfigUsesBd(t *testing.T) {
	c := &Client{bin: gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, "")}
	b := c.Show("b-1")
	if b == nil || b.Meta("merge_result") != "from_bd" {
		t.Fatalf("Show with no daemon config = %+v, want from_bd", b)
	}
}
