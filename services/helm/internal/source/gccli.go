// Package source reads what the board's pages show from Gas City's own
// interfaces: the gc command, through which the rig board reads each rig's
// store (internal/rigboard) and the service finds its city, and the
// supervisor's API, whose event log the city page reads (events.go).
//
// The gc command is run from the city root and bounded, and its JSON is read
// past the chatter gc prints before it.
package source

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"
)

// defaultGCTimeout bounds one `gc` invocation. `gc rig list` alone has been
// measured at ~10s on this host, so the bound is generous rather than snappy:
// a bound guessed too low fails a read that would have answered.
const defaultGCTimeout = 30 * time.Second

// gcExec runs the `gc` binary.
type gcExec struct {
	bin      string
	cityPath string
	timeout  time.Duration
}

// newGCExec locates the `gc` binary. GC_HELM_GC_BIN overrides the lookup, which
// is what lets a test point at a stub without touching PATH. A binary that
// cannot be found yields a client that reports the failure on first use rather
// than a nil one every caller has to guard.
func newGCExec(cityPath string) *gcExec {
	bin := strings.TrimSpace(os.Getenv("GC_HELM_GC_BIN"))
	if bin == "" {
		if p, err := exec.LookPath("gc"); err == nil {
			bin = p
		}
	}
	return &gcExec{bin: bin, cityPath: cityPath, timeout: defaultGCTimeout}
}

// run invokes one `gc` subcommand and decodes its JSON into out.
func (g *gcExec) run(ctx context.Context, out any, args ...string) error {
	if g.bin == "" {
		return fmt.Errorf("gc binary not found (set GC_HELM_GC_BIN or put gc on PATH)")
	}
	ctx, cancel := context.WithTimeout(ctx, g.timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, g.bin, args...)
	// Run from the city root and name it explicitly: `gc`'s city discovery walks
	// up from the working directory, and this process may be started anywhere.
	if g.cityPath != "" {
		cmd.Dir = g.cityPath
		cmd.Env = append(os.Environ(), "GC_CITY_PATH="+g.cityPath)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			return fmt.Errorf("gc %s: %w: %s", strings.Join(args, " "), err, firstLine(msg))
		}
		return fmt.Errorf("gc %s: %w", strings.Join(args, " "), err)
	}
	return decodeLooseJSON(stdout.Bytes(), out)
}

// decodeLooseJSON decodes the JSON document inside output that may be preceded
// by chatter. `gc` prints city.toml deprecation warnings and named-session
// advisories on the way to its payload, and some land on stdout — so the first
// byte of a `--json` run is not reliably `{`.
//
// Candidates are restricted to a bracket at the START of a line, which is where
// a pretty-printed or compact payload begins and where prose never does. The
// LAST such candidate is tried first: warnings precede the payload, so scanning
// from the end reaches it without decoding a bracket that merely appeared
// inside a warning.
func decodeLooseJSON(data []byte, out any) error {
	if err := json.Unmarshal(bytes.TrimSpace(data), out); err == nil {
		return nil
	}

	var starts []int
	for i := 0; i < len(data); i++ {
		if (data[i] == '{' || data[i] == '[') && (i == 0 || data[i-1] == '\n') {
			starts = append(starts, i)
		}
	}
	for i := len(starts) - 1; i >= 0; i-- {
		if err := json.Unmarshal(bytes.TrimSpace(data[starts[i]:]), out); err == nil {
			return nil
		}
	}
	return fmt.Errorf("no JSON document in %d bytes of output: %s", len(data), firstLine(string(data)))
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		s = s[:i]
	}
	if len(s) > 200 {
		s = s[:200] + "…"
	}
	return s
}

// CityPath returns the city root gc resolves for this invocation, so discovery
// reads the same city gc acts on instead of reimplementing city discovery.
// `gc config show` reports gc's resolved configuration, city_path among it, so
// this asks gc "which city would you act on here?" and takes that answer. The
// discovery client carries no cityPath, so run pins neither --city nor
// GC_CITY_PATH and leaves cmd.Dir at this process's cwd; gc resolves from where
// helm-svc was started — the plain-shell case the env vars do not cover.
func (g *gcExec) CityPath(ctx context.Context) (string, error) {
	var payload struct {
		CityPath string `json:"city_path"`
	}
	if err := g.run(ctx, &payload, "config", "show", "--json"); err != nil {
		return "", err
	}
	return strings.TrimSpace(payload.CityPath), nil
}

// GC is the gc command as a reader outside this package runs it: one
// subcommand, run from the city root and bounded as every call here is, with
// its JSON decoded into out. The rig board's gather (internal/rigboard) reads
// each rig's store through it.
type GC interface {
	JSON(ctx context.Context, out any, args ...string) error
}

// NewGC returns the gc command, located and run from cityPath.
func NewGC(cityPath string) GC { return newGCExec(cityPath) }

// JSON implements GC.
func (g *gcExec) JSON(ctx context.Context, out any, args ...string) error {
	return g.run(ctx, out, args...)
}

// DiscoverCityPath returns the city root this process should read. An explicit
// GC_HELM_CITY_PATH, GC_CITY_PATH or GC_CITY wins, in that order; with none of
// them set it asks gc — `gc config show` — for the city it would act on and takes
// that. A plain shell that injects none of those vars still reads a city, the
// same one gc resolves, rather than a discovery reimplemented here: gc-toolkit
// runs on Gas City, so gc is the authority on which city to read. A gc that
// cannot answer — absent, or resolving no city — yields "", the same fail-closed
// "no city" the callers already handle.
//
// The entrypoint resolves it once at startup and threads it to the rig board's
// reads and the verb runner's working directory, so they cannot disagree about
// which city they act on.
func DiscoverCityPath() string {
	for _, k := range []string{"GC_HELM_CITY_PATH", "GC_CITY_PATH", "GC_CITY"} {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	// The plain-shell case: no city env set. Ask gc which city it resolves. The
	// discovery client carries no cityPath, so gc resolves from this process's
	// own context (see gcExec.CityPath); run bounds the call with its own timeout.
	// Best-effort — any failure resolves to "".
	if p, err := newGCExec("").CityPath(context.Background()); err == nil {
		return p
	}
	return ""
}
