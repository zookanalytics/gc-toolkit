// Package daemon is the part of gctk's store adapter that finds the local Gas
// City supervisor API and builds the per-city read URL for one bead. Only
// internal/gcbd imports it.
//
// It is the seam every store read that goes to the supervisor's pooled,
// process-lifetime Dolt connection shares: a `gc bd` invocation forks and opens
// its own Dolt connection, where a GET against the already-running supervisor
// answers in-process over its pool. The base URL is not advertised
// in any runtime file; it is derived from config exactly as `gc`'s own
// supervisor-API discovery derives it — `$GC_HOME/supervisor.toml`'s
// `[supervisor]` bind and port, defaulting to the supervisor's own
// `127.0.0.1:8372`. The city's name in the read URL is the supervisor's own
// answer, from its city listing ([City]). Reachability is not probed: the
// caller falls back when the listing read or the bead read fails.
//
// The TOML read is a scalar lookup within one section, which is enough for
// these flat keys.
package daemon

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

const (
	defaultBind = "127.0.0.1"
	defaultPort = 8372
)

// maxListing caps the city listing a read will decode, so a runaway payload
// cannot exhaust memory. One city's entry is a few hundred bytes.
const maxListing = 1 << 20

// Disabled reports whether the supervisor-API read path is turned off for this
// process, mirroring `gc beads`' GC_NO_API escape hatch so one switch governs
// every API-routed read in the city: "1", "true", or "yes" disable it; empty
// or "0"/"false"/"no" leave it on. An unrecognized value is treated as unset
// (left on), the same lenient reading `gc` takes. The hermetic test harnesses
// set GC_NO_API=1 so a stubbed `gc` on PATH, not the live supervisor, answers.
func Disabled() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv("GC_NO_API"))) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}

// gcHome resolves the machine-wide gc home the supervisor config lives under:
// $GC_HOME, else ~/.gc. It matches the supervisor's own DefaultHome so a client
// reads the same supervisor.toml the running daemon was configured from.
func gcHome() string {
	if h := strings.TrimSpace(os.Getenv("GC_HOME")); h != "" {
		return h
	}
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return ""
	}
	return filepath.Join(home, ".gc")
}

// CityPath is the directory of the city this process works in, the first of
// GC_CITY_PATH, GC_CITY and GC_CITY_ROOT that is set, or empty when none is.
func CityPath() string {
	for _, env := range []string{"GC_CITY_PATH", "GC_CITY", "GC_CITY_ROOT"} {
		if v := strings.TrimSpace(os.Getenv(env)); v != "" {
			return v
		}
	}
	return ""
}

// BaseURL resolves the supervisor API base URL from config, or ("", false) when
// the read path is Disabled. The port and bind come from
// $GC_HOME/supervisor.toml's [supervisor] section, each falling back to the
// supervisor's own default (127.0.0.1:8372) when absent — the port is assigned
// from config, never advertised in a runtime file, so a client reconstructs it
// the same way. A wildcard bind is normalized to its loopback form, since a
// client reaches the daemon over loopback.
func BaseURL() (string, bool) {
	if Disabled() {
		return "", false
	}
	bind := defaultBind
	port := defaultPort
	if home := gcHome(); home != "" {
		if v, ok := tomlSectionValue(filepath.Join(home, "supervisor.toml"), "supervisor", "bind"); ok && v != "" {
			bind = v
		}
		if v, ok := tomlSectionValue(filepath.Join(home, "supervisor.toml"), "supervisor", "port"); ok {
			if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && n > 0 {
				port = n
			}
		}
	}
	switch bind {
	case "", "0.0.0.0":
		bind = "127.0.0.1"
	case "::", "[::]":
		bind = "::1"
	}
	return "http://" + net.JoinHostPort(bind, strconv.Itoa(port)), true
}

// City is the name the supervisor serves the city at path under, the name
// every per-city route carries. It asks the supervisor's city listing, GET
// /v0/cities, and takes the name the listing gives the city at path. The
// supervisor serves a city under the name its registry entry stores, which
// neither city.toml's [workspace] name nor the path's basename has to match.
// It lists the city at the path that entry stores, the path it runs the city
// from, which the city's sessions find in GC_CITY_PATH (startOneCity in
// cmd/gc/cmd_supervisor.go at gastownhall/gascity 77143ecd18). So the two
// paths are compared as text, once each is cleaned. why is empty when a city is
// listed at path, and otherwise says what failed, for the caller's route log.
func City(httpc *http.Client, base, path string) (name, why string) {
	resp, err := httpc.Get(base + "/v0/cities")
	if err != nil {
		return "", "city-transport"
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return "", "city-status-" + strconv.Itoa(resp.StatusCode)
	}
	var listing struct {
		Items []struct {
			Name string `json:"name"`
			Path string `json:"path"`
		} `json:"items"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxListing)).Decode(&listing); err != nil {
		return "", "city-decode"
	}
	want := filepath.Clean(path)
	for _, city := range listing.Items {
		if city.Name != "" && filepath.Clean(city.Path) == want {
			return city.Name, ""
		}
	}
	return "", "city-unlisted"
}

// BeadURL builds the single-bead read URL. The id and city are path-escaped so
// an id with a reserved byte cannot reshape the path.
func BeadURL(base, city, id string) string {
	return base + "/v0/city/" + url.PathEscape(city) + "/bead/" + url.PathEscape(id)
}

// tomlSectionValue reads one scalar key from one top-level table of a flat TOML
// file: it walks lines, tracks the current [section] header, and returns the
// first key match inside the wanted section. Quotes around a string value are
// stripped; inline comments after an unquoted value are not expected in these
// generated files and are left intact. ok is false when the file cannot be
// read or the key is absent — callers fall back to a default either way, so an
// unreadable config is indistinguishable from an unset key, which is the intent.
func tomlSectionValue(path, section, key string) (string, bool) {
	data, err := os.ReadFile(path)
	if err != nil {
		return "", false
	}
	cur := ""
	for _, raw := range strings.Split(string(data), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			cur = strings.TrimSpace(strings.Trim(line, "[]"))
			continue
		}
		if cur != section {
			continue
		}
		eq := strings.IndexByte(line, '=')
		if eq < 0 {
			continue
		}
		if strings.TrimSpace(line[:eq]) != key {
			continue
		}
		val := strings.TrimSpace(line[eq+1:])
		if len(val) >= 2 && (val[0] == '"' || val[0] == '\'') && val[len(val)-1] == val[0] {
			val = val[1 : len(val)-1]
		}
		return val, true
	}
	return "", false
}
