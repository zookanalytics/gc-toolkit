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
// alongside the in-process beads library and the supervisor HTTP API. It exists
// here because two of the board's facts live nowhere else:
//
//   - SESSION LIVENESS. Whether the session that claimed a child is still alive
//     is what separates work in flight from an orphan, and no bead carries it.
//     The supervisor API has no sessions endpoint and the beads library cannot
//     see sessions at all; `gc session list` is the only reader.
//   - CONVOY OWNERSHIP. `owned` and `progress` are convoy-level facts the
//     library's issue rows do not carry.
//
// This is the same source gc-helm.sh reads (`gcq session list`, `gc convoy
// list`, `gc convoy status`), so the two boards agree by construction rather
// than by two independent derivations. It honours the package's data-access
// contract for the same reason the other two backends do: it is a Gas City
// interface, not raw Dolt. There is no sql.Open here.
//
// EVERY CALL IS BEST-EFFORT. A board that loses its liveness join is narrower
// (nothing reads as in flight) but still correct about what it does show, so a
// missing or failing `gc` degrades to a partial error rather than an aborted
// gather.

// defaultGCTimeout bounds one `gc` invocation. `gc rig list` alone has been
// measured at ~10s on this host (tk-lzdty), and the session and convoy reads
// hit the same supervisor, so the bound is generous rather than snappy: the
// cost of guessing too low is a board that silently loses its liveness join.
const defaultGCTimeout = 30 * time.Second

// gcClient is the slice of the `gc` CLI this source uses. It is an interface so
// tests can drive the gather without a live city.
type gcClient interface {
	// Sessions maps every session's NAME and its ALIAS to that session's state.
	// Both forms are keys because a child's assignee may be written either way.
	Sessions(ctx context.Context) (map[string]string, error)
	// Convoys lists every convoy in the city with its ownership and progress.
	Convoys(ctx context.Context) ([]convoyRow, error)
	// ConvoyMember resolves a convoy to its SINGLE tracked member, returning ""
	// when the convoy tracks any other number. The one-member rule is a
	// fail-closed gate, not an optimisation: a convoy of another shape is one
	// this join does not understand, and the safe reading of "not understood"
	// is "no claim about movement".
	ConvoyMember(ctx context.Context, convoyID string) (string, error)
}

// convoyRow is one entry of `gc convoy list --json`.
type convoyRow struct {
	ID       string          `json:"id"`
	Title    string          `json:"title"`
	Status   string          `json:"status"`
	Owned    bool            `json:"owned"`
	Progress *convoyProgress `json:"progress"`
}

// convoyProgress mirrors the `progress` object on a convoy row. It is declared
// here rather than reused from the board package so this file stays a pure
// transport decode; the gather converts it.
type convoyProgress struct {
	Closed int `json:"closed"`
	Total  int `json:"total"`
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

// Convoys implements gcClient.
func (g *gcExec) Convoys(ctx context.Context) ([]convoyRow, error) {
	var payload struct {
		Convoys []convoyRow `json:"convoys"`
	}
	if err := g.run(ctx, &payload, "convoy", "list", "--json"); err != nil {
		return nil, err
	}
	return payload.Convoys, nil
}

// ConvoyMember implements gcClient.
func (g *gcExec) ConvoyMember(ctx context.Context, convoyID string) (string, error) {
	var payload struct {
		Children []struct {
			ID string `json:"id"`
		} `json:"children"`
	}
	if err := g.run(ctx, &payload, "convoy", "status", convoyID, "--json"); err != nil {
		return "", err
	}
	if len(payload.Children) != 1 {
		return "", nil
	}
	return payload.Children[0].ID, nil
}
