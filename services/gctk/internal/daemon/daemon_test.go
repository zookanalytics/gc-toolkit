package daemon

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestDisabledHonorsGCNoAPI(t *testing.T) {
	for _, tc := range []struct {
		val  string
		want bool
	}{
		{"", false}, {"0", false}, {"false", false}, {"no", false},
		{"1", true}, {"true", true}, {"YES", true},
		{"garbage", false}, // unrecognized reads as unset, left on
	} {
		t.Setenv("GC_NO_API", tc.val)
		if got := Disabled(); got != tc.want {
			t.Errorf("Disabled() with GC_NO_API=%q = %v, want %v", tc.val, got, tc.want)
		}
	}
}

func TestBaseURL(t *testing.T) {
	t.Setenv("GC_NO_API", "")

	t.Run("defaults to the supervisor's own 127.0.0.1:8372 when config absent", func(t *testing.T) {
		t.Setenv("GC_HOME", t.TempDir())
		got, ok := BaseURL()
		if !ok || got != "http://127.0.0.1:8372" {
			t.Fatalf("BaseURL() = (%q, %v), want (http://127.0.0.1:8372, true)", got, ok)
		}
	})

	t.Run("reads [supervisor] port and normalizes a wildcard bind to loopback", func(t *testing.T) {
		home := t.TempDir()
		writeFile(t, filepath.Join(home, "supervisor.toml"), "[supervisor]\nbind = \"0.0.0.0\"\nport = 9001\n")
		t.Setenv("GC_HOME", home)
		got, ok := BaseURL()
		if !ok || got != "http://127.0.0.1:9001" {
			t.Fatalf("BaseURL() = (%q, %v), want (http://127.0.0.1:9001, true)", got, ok)
		}
	})

	t.Run("a key outside [supervisor] does not bleed in", func(t *testing.T) {
		home := t.TempDir()
		writeFile(t, filepath.Join(home, "supervisor.toml"), "[other]\nport = 1\n[supervisor]\nport = 9100\n")
		t.Setenv("GC_HOME", home)
		got, ok := BaseURL()
		if !ok || got != "http://127.0.0.1:9100" {
			t.Fatalf("BaseURL() = (%q, %v), want (http://127.0.0.1:9100, true)", got, ok)
		}
	})

	t.Run("disabled yields not-ok", func(t *testing.T) {
		t.Setenv("GC_HOME", t.TempDir())
		t.Setenv("GC_NO_API", "1")
		if url, ok := BaseURL(); ok {
			t.Errorf("BaseURL() = (%q, true) with GC_NO_API=1; want not-ok", url)
		}
	})
}

// listing is a supervisor whose GET /v0/cities answers status and body, and
// which answers any other path 404.
func listing(t *testing.T, status int, body string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/v0/cities" {
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(status)
		fmt.Fprint(w, body)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestCity(t *testing.T) {
	city := func(t *testing.T, srv *httptest.Server, path, wantName, wantWhy string) {
		t.Helper()
		name, why := City(srv.Client(), srv.URL, path)
		if name != wantName || why != wantWhy {
			t.Fatalf("City(%q) = (%q, %q), want (%q, %q)", path, name, why, wantName, wantWhy)
		}
	}

	t.Run("the name listed at the path, not city.toml's name or the basename", func(t *testing.T) {
		dir := filepath.Join(t.TempDir(), "dirname")
		writeFile(t, filepath.Join(dir, "city.toml"), "[workspace]\nname = \"tomlname\"\n")
		srv := listing(t, http.StatusOK, fmt.Sprintf(
			`{"items":[{"name":"dirname","path":"/elsewhere/dirname","running":true},{"name":"registered","path":%q,"running":true}],"total":2}`, dir))
		city(t, srv, dir, "registered", "")
	})

	t.Run("a trailing separator on either path still matches", func(t *testing.T) {
		srv := listing(t, http.StatusOK, `{"items":[{"name":"registered","path":"/cities/one/"}],"total":1}`)
		city(t, srv, "/cities/one", "registered", "")
		city(t, srv, "/cities/one/", "registered", "")
	})

	t.Run("no city listed at the path", func(t *testing.T) {
		srv := listing(t, http.StatusOK, `{"items":[{"name":"other","path":"/cities/other"},{"name":"","path":"/cities/one"}],"total":2}`)
		city(t, srv, "/cities/one", "", "city-unlisted")
	})

	t.Run("a listing that answers another status", func(t *testing.T) {
		srv := listing(t, http.StatusServiceUnavailable, `{"items":[{"name":"registered","path":"/cities/one"}]}`)
		city(t, srv, "/cities/one", "", "city-status-503")
	})

	t.Run("a listing that does not decode", func(t *testing.T) {
		srv := listing(t, http.StatusOK, `not json`)
		city(t, srv, "/cities/one", "", "city-decode")
	})

	t.Run("a supervisor that does not answer", func(t *testing.T) {
		srv := listing(t, http.StatusOK, `{"items":[]}`)
		srv.Close()
		city(t, srv, "/cities/one", "", "city-transport")
	})
}

func TestBeadURLEscapes(t *testing.T) {
	got := BeadURL("http://h:1", "c i/ty", "tk-1")
	want := "http://h:1/v0/city/c%20i%2Fty/bead/tk-1"
	if got != want {
		t.Errorf("BeadURL = %q, want %q", got, want)
	}
}
