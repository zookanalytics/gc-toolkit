package daemon

import (
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

func TestCity(t *testing.T) {
	// A city path alone resolves the rest; clear the others so the chain is
	// deterministic regardless of the ambient session.
	clearCityEnv := func(t *testing.T) {
		t.Setenv("GC_CITY", "")
		t.Setenv("GC_CITY_ROOT", "")
	}

	t.Run("basename when city.toml declares no workspace name", func(t *testing.T) {
		clearCityEnv(t)
		dir := filepath.Join(t.TempDir(), "loomington")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		t.Setenv("GC_CITY_PATH", dir)
		got, ok := City()
		if !ok || got != "loomington" {
			t.Fatalf("City() = (%q, %v), want (loomington, true)", got, ok)
		}
	})

	t.Run("workspace name wins over basename", func(t *testing.T) {
		clearCityEnv(t)
		dir := filepath.Join(t.TempDir(), "dirname")
		writeFile(t, filepath.Join(dir, "city.toml"), "[workspace]\nprovider = \"claude\"\nname = \"realname\"\n")
		t.Setenv("GC_CITY_PATH", dir)
		got, ok := City()
		if !ok || got != "realname" {
			t.Fatalf("City() = (%q, %v), want (realname, true)", got, ok)
		}
	})

	t.Run("no city path yields not-ok", func(t *testing.T) {
		clearCityEnv(t)
		t.Setenv("GC_CITY_PATH", "")
		if name, ok := City(); ok {
			t.Errorf("City() = (%q, true) with no city path; want not-ok", name)
		}
	})
}

func TestBeadURLEscapes(t *testing.T) {
	got := BeadURL("http://h:1", "c i/ty", "tk-1")
	want := "http://h:1/v0/city/c%20i%2Fty/bead/tk-1"
	if got != want {
		t.Errorf("BeadURL = %q, want %q", got, want)
	}
}
