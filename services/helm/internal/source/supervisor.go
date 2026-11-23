package source

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// defaultSupervisorPort is the supervisor's documented default loopback port
// (internal/supervisor/config.go PortOrDefault). Used when supervisor.toml is
// unreadable and no override env is set.
const defaultSupervisorPort = 8372

// discoverBaseURL finds the supervisor's loopback API the way the gc CLI does:
// GC_HELM_SUPERVISOR_URL, else the port in supervisor.toml under GC_HOME (or
// ~/.gc), else the default port.
func discoverBaseURL() string {
	if v := strings.TrimSpace(os.Getenv("GC_HELM_SUPERVISOR_URL")); v != "" {
		return strings.TrimRight(v, "/")
	}
	port := defaultSupervisorPort
	home := strings.TrimSpace(os.Getenv("GC_HOME"))
	if home == "" {
		if h, err := os.UserHomeDir(); err == nil {
			home = filepath.Join(h, ".gc")
		}
	}
	if home != "" {
		if p, ok := readSupervisorPort(filepath.Join(home, "supervisor.toml")); ok {
			port = p
		}
	}
	return fmt.Sprintf("http://127.0.0.1:%d", port)
}

// readSupervisorPort does a minimal scan of supervisor.toml for the
// `[supervisor] port = N` value, avoiding a TOML dependency. Best-effort.
func readSupervisorPort(path string) (int, bool) {
	f, err := os.Open(path)
	if err != nil {
		return 0, false
	}
	defer func() { _ = f.Close() }()
	inSection := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		switch {
		case strings.HasPrefix(line, "["):
			inSection = line == "[supervisor]"
		case inSection && strings.HasPrefix(line, "port"):
			if _, val, ok := strings.Cut(line, "="); ok {
				var p int
				if _, err := fmt.Sscanf(strings.TrimSpace(val), "%d", &p); err == nil && p > 0 {
					return p, true
				}
			}
		}
	}
	return 0, false
}

// discoverCity names the city whose routes the supervisor's API serves:
// GC_HELM_CITY, else the city in the GC_SERVICE_URL_PREFIX the supervisor
// injects, else the basename of GC_CITY_PATH or GC_CITY.
func discoverCity() string {
	if v := strings.TrimSpace(os.Getenv("GC_HELM_CITY")); v != "" {
		return v
	}
	// GC_SERVICE_URL_PREFIX = /v0/city/<city>/svc/<name>
	if p := strings.Trim(os.Getenv("GC_SERVICE_URL_PREFIX"), "/"); p != "" {
		parts := strings.Split(p, "/")
		for i, seg := range parts {
			if seg == "city" && i+1 < len(parts) {
				return parts[i+1]
			}
		}
	}
	for _, k := range []string{"GC_CITY_PATH", "GC_CITY"} {
		if cp := strings.TrimSpace(os.Getenv(k)); cp != "" {
			return filepath.Base(cp)
		}
	}
	return ""
}
