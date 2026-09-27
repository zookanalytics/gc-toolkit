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

// The `gc` CLI is the third sanctioned Gas City interface this package reads,
// alongside the in-process beads library and the supervisor HTTP API. Two facts
// come from it:
//
//   - SESSION LIVENESS. Whether the session that claimed a child is still alive
//     is what separates work in flight from an orphan, and no bead carries it.
//     The supervisor API has no sessions endpoint and the beads library cannot
//     see sessions at all; `gc session list` is the only reader. This is the
//     same read gc-helm.sh makes (`gcq session list`), so the two boards agree
//     by construction rather than by two independent derivations.
//
//   - CITY DISCOVERY. When no city env var is set, the city root comes from
//     `gc config show` — the city gc itself resolves — rather than a discovery
//     reimplemented here: gc-toolkit runs on Gas City, so gc is the authority on
//     which city to read and helm-svc mirrors its answer. See DiscoverCityPath
//     and CityPath.
//
// Convoy ownership and membership are read in-process from the rig store: a
// convoy is `owned` when its bead carries the "owned" label — the test gascity
// itself applies for the `gc convoy list` owned flag — and its members are the
// `tracks` edges out of it. This source honours the package's data-access
// contract for the same reason the other two backends do: it is a Gas City
// interface, not raw Dolt. There is no sql.Open here.
//
// EVERY CALL IS BEST-EFFORT. A board that loses its liveness join is narrower
// (nothing reads as in flight) but still correct about what it does show, so a
// missing or failing `gc` degrades to a partial error rather than an aborted
// gather.

// defaultGCTimeout bounds one `gc` invocation. `gc rig list` alone has been
// measured at ~10s on this host (tk-lzdty), and the session read hits the same
// supervisor, so the bound is generous rather than snappy: the cost of guessing
// too low is a board that silently loses its liveness join.
const defaultGCTimeout = 30 * time.Second

// gcClient is the slice of the `gc` CLI this source uses. It is an interface so
// tests can drive the gather without a live city.
type gcClient interface {
	// Sessions maps every session's NAME and its ALIAS to that session's state.
	// Both forms are keys because a child's assignee may be written either way.
	Sessions(ctx context.Context) (map[string]string, error)
}

// gcExec is the production gcClient: it shells out to the `gc` binary.
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

// Sessions implements gcClient.
func (g *gcExec) Sessions(ctx context.Context) (map[string]string, error) {
	var payload struct {
		Sessions []struct {
			ID          string `json:"id"`
			Alias       string `json:"alias"`
			SessionName string `json:"session_name"`
			State       string `json:"state"`
		} `json:"sessions"`
	}
	if err := g.run(ctx, &payload, "session", "list", "--state", "all", "--json"); err != nil {
		return nil, err
	}
	out := make(map[string]string, len(payload.Sessions)*2)
	for _, s := range payload.Sessions {
		// Key on every form a claim may have recorded: `gc bd update --claim`
		// writes the session NAME, a routed assignment writes the ALIAS, and a
		// bead claimed by id carries the ID.
		for _, k := range []string{s.SessionName, s.Alias, s.ID} {
			if k != "" {
				out[k] = s.State
			}
		}
	}
	return out, nil
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
