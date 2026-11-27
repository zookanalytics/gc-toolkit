package gcbd

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
)

// TestMain keeps the subprocess-path suites off the live supervisor. The exec
// and List tests drive a stubbed `gc` on PATH; GC_NO_API=1 stops New() from
// discovering the ambient session's real daemon and routing a read there
// instead of to the stub. The daemon-path tests below build a Client pointed at
// a fake server directly, so GC_NO_API does not reach them, or turn it off for
// New and point New at a fake server (supervisorListing).
func TestMain(m *testing.M) {
	if err := os.Setenv("GC_NO_API", "1"); err != nil {
		panic(err)
	}
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

// knownCity is a city's name a test gives a client, so no listing is read.
func knownCity(name string) func() (string, string) {
	return func() (string, string) { return name, "" }
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

// A healthy daemon read returns the daemon's bead and never forks `gc bd`,
// which is what the cached read is for. The stub's distinct value and the fork
// marker prove the daemon answered and the subprocess stayed untouched.
func TestShowCachedReadsViaDaemonWithoutForkingBd(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "forks")
	srv, gotPath := daemonServing(t,
		`{"id":"b-1","status":"open","assignee":"someone","metadata":{"merge_result":"pull_request"}}`)
	c := &Client{
		bin:     gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, marker),
		httpc:   srv.Client(),
		baseURL: srv.URL,
		city:    knownCity("testcity"),
	}
	b := c.ShowCached("b-1")
	if b == nil {
		t.Fatal("ShowCached via daemon = nil")
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
// `gc bd` read, so whether a bead exists is always `gc bd`'s answer. The stub's
// from_bd value proves the fallback arm ran.
func TestShowCachedFallsBackToBdWhenDaemonUnavailable(t *testing.T) {
	const bdPayload = `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`
	assertFellBack := func(t *testing.T, c *Client) {
		t.Helper()
		b := c.ShowCached("b-1")
		if b == nil || b.Meta("merge_result") != "from_bd" {
			t.Fatalf("ShowCached = %+v, want the bd fallback value from_bd", b)
		}
	}

	t.Run("non-200 status", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, `{"code":"bead-not-found"}`, http.StatusNotFound)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: knownCity("c")})
	})

	t.Run("transport failure", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
		dead := srv.URL
		srv.Close() // nothing listens now; the GET is refused
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: &http.Client{}, baseURL: dead, city: knownCity("c")})
	})

	t.Run("undecodable 200 body", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `not json`)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: knownCity("c")})
	})

	t.Run("200 with no id is a miss, not a bead", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprint(w, `{"status":"open"}`)
		}))
		t.Cleanup(srv.Close)
		assertFellBack(t, &Client{bin: gcShowStub(t, bdPayload, ""), httpc: srv.Client(), baseURL: srv.URL, city: knownCity("c")})
	})
}

// Show is the authoritative read: it forks `gc bd` and never consults the
// daemon, even a healthy one, so a read that decides a write observes the latest
// write and carries notes the daemon payload omits.
func TestShowBypassesDaemon(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "forks")
	srv, _ := daemonServing(t, `{"id":"b-1","metadata":{"merge_result":"from_daemon"}}`)
	c := &Client{
		bin:     gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, marker),
		httpc:   srv.Client(),
		baseURL: srv.URL,
		city:    knownCity("c"),
	}
	b := c.Show("b-1")
	if b == nil || b.Meta("merge_result") != "from_bd" {
		t.Fatalf("Show = %+v, want the bd value from_bd, never the daemon's", b)
	}
	if _, err := os.Stat(marker); os.IsNotExist(err) {
		t.Error("Show did not fork gc bd; the authoritative read must never come from the daemon cache")
	}
}

// With no daemon configured — the default from New() under GC_NO_API, or any
// city-less session — ShowCached reads straight through the subprocess.
func TestShowCachedWithoutDaemonConfigUsesBd(t *testing.T) {
	c := &Client{bin: gcShowStub(t, `[{"id":"b-1","metadata":{"merge_result":"from_bd"}}]`, "")}
	b := c.ShowCached("b-1")
	if b == nil || b.Meta("merge_result") != "from_bd" {
		t.Fatalf("ShowCached with no daemon config = %+v, want from_bd", b)
	}
}

// supervisorListing starts a fake supervisor that lists one city, name at
// path, and serves beadJSON on that city's route for b-1, and points New at
// it: GC_HOME's supervisor.toml names its address, GC_NO_API is off and the
// session names no city, which each test then sets. It returns every path the
// supervisor is asked for, in order.
func supervisorListing(t *testing.T, name, path, beadJSON string) func() []string {
	t.Helper()
	var mu sync.Mutex
	var asked []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		mu.Lock()
		asked = append(asked, r.URL.Path)
		mu.Unlock()
		switch r.URL.Path {
		case "/v0/cities":
			fmt.Fprintf(w, `{"items":[{"name":%q,"path":%q,"running":true}],"total":1}`, name, path)
		case "/v0/city/" + name + "/bead/b-1":
			fmt.Fprint(w, beadJSON)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	u, err := url.Parse(srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	toml := fmt.Sprintf("[supervisor]\nbind = %q\nport = %s\n", u.Hostname(), u.Port())
	if err := os.WriteFile(filepath.Join(home, "supervisor.toml"), []byte(toml), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GC_HOME", home)
	t.Setenv("GC_NO_API", "")
	for _, env := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT"} {
		t.Setenv(env, "")
	}
	return func() []string {
		mu.Lock()
		defer mu.Unlock()
		return slices.Clone(asked)
	}
}

// New names the city on the bead route by the name the supervisor lists at the
// session's city path, not by the path's basename, and reads that listing once
// for the client and the copies WithContext makes.
func TestNewNamesTheCityAsTheSupervisorListsIt(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "dirname")
	asked := supervisorListing(t, "registered", dir, `{"id":"b-1","metadata":{"merge_result":"from_daemon"}}`)
	t.Setenv("GC_CITY_PATH", dir)
	c := New()
	for i, read := range []*Client{c, c.WithContext(context.Background())} {
		if b, why := read.showViaDaemon("b-1"); b == nil || b.Meta("merge_result") != "from_daemon" {
			t.Fatalf("read %d: showViaDaemon = (%+v, %q), want the supervisor's bead", i, b, why)
		}
	}
	want := []string{"/v0/cities", "/v0/city/registered/bead/b-1", "/v0/city/registered/bead/b-1"}
	if got := asked(); !slices.Equal(got, want) {
		t.Errorf("supervisor asked for %q, want %q", got, want)
	}
}

// A city the supervisor's listing gives no name is a read to fall back from,
// with the listing's reason, and asks no bead route, even where the path's
// basename is another listed city's name.
func TestNewFallsBackForACityTheSupervisorDoesNotList(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "dirname")
	asked := supervisorListing(t, "dirname", filepath.Join(t.TempDir(), "elsewhere"), `{"id":"b-1"}`)
	t.Setenv("GC_CITY_PATH", dir)
	if b, why := New().showViaDaemon("b-1"); b != nil || why != "city-unlisted" {
		t.Fatalf("showViaDaemon = (%+v, %q), want no bead and the reason city-unlisted", b, why)
	}
	if got, want := asked(), []string{"/v0/cities"}; !slices.Equal(got, want) {
		t.Errorf("supervisor asked for %q, want %q", got, want)
	}
}

// A session that names no city reads every bead through `gc bd`, and New wires
// no supervisor read at all.
func TestNewWithoutACityPathWiresNoSupervisorRead(t *testing.T) {
	supervisorListing(t, "registered", "/cities/one", `{"id":"b-1"}`)
	if New().daemonConfigured() {
		t.Error("New wired the supervisor read for a session that names no city")
	}
}
