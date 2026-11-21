package source

import (
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"testing"
)

// TestDiscoverCityPath covers the resolution DiscoverCityPath performs: the
// explicit env overrides, then the gc fallback that lets the CLI read a city
// from a plain shell setting none of them.
func TestDiscoverCityPath(t *testing.T) {
	// Env wins over gc, in declared precedence order. A gc stub that would answer
	// a different path is installed throughout, so a case that leaked past the env
	// check would return "/from/gc" — a wrong, detectable value — rather than
	// silently reaching the developer's live gc.
	t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, `{"city_path":"/from/gc"}`, 0))
	for _, tc := range []struct {
		name string
		set  map[string]string
		want string
	}{
		{"GC_HELM_CITY_PATH first", map[string]string{"GC_HELM_CITY_PATH": "/from/helm", "GC_CITY_PATH": "/from/city_path", "GC_CITY": "/from/city"}, "/from/helm"},
		{"GC_CITY_PATH next", map[string]string{"GC_HELM_CITY_PATH": "", "GC_CITY_PATH": "/from/city_path", "GC_CITY": "/from/city"}, "/from/city_path"},
		{"GC_CITY last", map[string]string{"GC_HELM_CITY_PATH": "", "GC_CITY_PATH": "", "GC_CITY": "/from/city"}, "/from/city"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			for k, v := range tc.set {
				t.Setenv(k, v)
			}
			if got := DiscoverCityPath(); got != tc.want {
				t.Errorf("DiscoverCityPath: got %q, want %q", got, tc.want)
			}
		})
	}

	// None set: DiscoverCityPath asks gc. The stub stands in for
	// `gc config show --json`, and it prefixes the JSON with a warning line so the
	// real subprocess AND decodeLooseJSON's chatter-skipping are both exercised.
	t.Run("gc fallback when no env is set", func(t *testing.T) {
		t.Setenv("GC_HELM_CITY_PATH", "")
		t.Setenv("GC_CITY_PATH", "")
		t.Setenv("GC_CITY", "")
		t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, "warning: city.toml is deprecated\n{\"city_path\":\"/discovered/by/gc\"}\n", 0))
		if got := DiscoverCityPath(); got != "/discovered/by/gc" {
			t.Errorf("DiscoverCityPath gc fallback: got %q, want %q", got, "/discovered/by/gc")
		}
	})

	// A gc that cannot answer — run outside any city, or absent — is the
	// fail-closed case: DiscoverCityPath yields "", the "no city" the callers
	// already handle, never a partial or a panic. The stub exits non-zero, which
	// run() surfaces as an error regardless of what it printed.
	t.Run("empty when gc fails", func(t *testing.T) {
		t.Setenv("GC_HELM_CITY_PATH", "")
		t.Setenv("GC_CITY_PATH", "")
		t.Setenv("GC_CITY", "")
		t.Setenv("GC_HELM_GC_BIN", writeGCStub(t, "gc: no city found\n", 1))
		if got := DiscoverCityPath(); got != "" {
			t.Errorf("DiscoverCityPath with a failing gc: got %q, want empty", got)
		}
	})
}

// writeGCStub writes an executable stand-in for the `gc` binary that prints
// stdout verbatim and exits with code. GC_HELM_GC_BIN points newGCExec at it, so
// DiscoverCityPath's fallback runs the stub instead of the real gc — the whole
// subprocess path, hermetically. The body is carried in a sibling file the stub
// cats, so any content (warnings, newlines) round-trips without shell quoting.
func writeGCStub(t *testing.T, stdout string, code int) string {
	t.Helper()
	dir := t.TempDir()
	payload := filepath.Join(dir, "payload")
	if err := os.WriteFile(payload, []byte(stdout), 0o644); err != nil {
		t.Fatalf("write gc stub payload: %v", err)
	}
	path := filepath.Join(dir, "gc")
	script := fmt.Sprintf("#!/bin/sh\ncat %q\nexit %d\n", payload, code)
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatalf("write gc stub: %v", err)
	}
	return path
}

// TestDecodeLooseJSON: `gc --json` output is not reliably JSON from byte zero —
// deprecation warnings and named-session advisories precede it.
func TestDecodeLooseJSON(t *testing.T) {
	want := map[string]string{"a": "b"}
	cases := []struct {
		name string
		in   string
		ok   bool
	}{
		{"clean", `{"a":"b"}`, true},
		{"leading warning", "named_session \"x\": mode \"always\"\n{\"a\":\"b\"}", true},
		{"warning containing a brace", "warn: got {not json} here\n{\"a\":\"b\"}", true},
		{"whole-input trim handles an indented payload", "  {\"a\":\"b\"}", true},
		{"no json at all", "boom\n", false},
	}
	for _, c := range cases {
		var got map[string]string
		err := decodeLooseJSON([]byte(c.in), &got)
		if c.ok != (err == nil) {
			t.Errorf("%s: err=%v, wanted ok=%v", c.name, err, c.ok)
			continue
		}
		if c.ok && !maps.Equal(got, want) {
			t.Errorf("%s: got %v, want %v", c.name, got, want)
		}
	}
}
