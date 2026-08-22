// Package visit runs the city's visit-filing verb on behalf of the board.
//
// It is a thin exec wrapper and nothing else. `gc-helm.sh open` owns what a
// visit IS — the gate-visit block, the subject-existence gate, the
// one-open-visit-per-subject gate, rig resolution, the board cache bust — and
// this package exists so the HTTP layer can reach that one copy rather than
// grow a second. The same reuse discipline assets/scripts/gc-visit-open.sh
// follows, for the same reason: assets/scripts/gate-visit.test.sh guards a
// single canonical copy, and a Go reimplementation would be an unguarded one.
package visit

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/helm/internal/server"
)

// DefaultTimeout bounds one `gc-helm.sh open` run.
//
// Generous on purpose. The verb is not one command: it enumerates rigs (itself
// bounded at 30s by default, GC_HELM_RIG_TIMEOUT), reads the subject, scans the
// city's open beads for an existing visit, then creates and stamps a bead and
// files a dependency edge. Each of those is a `gc`/`bd` call against Dolt, and
// under city load the CLI startup cost alone is seconds. Cutting a slow-but-
// working open short would report failure for a visit that then appears anyway
// — the worst outcome available, because the operator's retry is what splits
// the conversation.
const DefaultTimeout = 120 * time.Second

// killGrace bounds how long Wait may block AFTER the deadline has fired and the
// process group has been signalled — covering anything that somehow still holds
// an inherited pipe. Short: by this point the answer is already "timed out",
// and the only question is how long the handler waits to say so.
const killGrace = 2 * time.Second

// Opener runs the `open` verb as a subprocess. It satisfies [server.Opener].
type Opener struct {
	// script is the absolute path to gc-helm.sh.
	script string
	// dir is the working directory for the run: the city root, so `gc`'s city
	// discovery is deterministic wherever this process was started from. Same
	// rationale as internal/source/gccli.go and tmux-pick-helm.sh's --city-path.
	dir     string
	timeout time.Duration
}

// New builds an Opener, or reports why the write route cannot be served.
//
// RESOLUTION ORDER, and why there is no rig-name guess in it:
//
//  1. GC_HELM_OPEN_TOOL — an explicit path. This is what the launcher sets
//     (assets/scripts/gc-helm-svc.sh exports the sibling gc-helm.sh next to
//     itself), so the normal deployment always resolves, and it is what tests
//     point at a stub. It mirrors GC_HELM_GC_BIN in internal/source.
//  2. `gc-helm.sh` on PATH.
//
// Deliberately NOT a third guess at "rigs/<rig>/assets/scripts/gc-helm.sh".
// gc-toolkit is rig-imported by four rigs, so there is no single correct rig
// name to hardcode, and picking one would silently run a DIFFERENT rig's copy
// of the script than the binary was built from. A service that cannot resolve
// the script serves the whole board and refuses this one route with a message
// naming the variable — which is recoverable — rather than filing visits
// through a script nobody chose.
func New(cityPath string) (*Opener, error) {
	script, err := resolveScript()
	if err != nil {
		return nil, err
	}
	return &Opener{script: script, dir: cityPath, timeout: timeout()}, nil
}

func resolveScript() (string, error) {
	if p := strings.TrimSpace(os.Getenv("GC_HELM_OPEN_TOOL")); p != "" {
		abs, err := filepath.Abs(p)
		if err != nil {
			return "", fmt.Errorf("GC_HELM_OPEN_TOOL=%s: %w", p, err)
		}
		if st, err := os.Stat(abs); err != nil || st.IsDir() {
			return "", fmt.Errorf("GC_HELM_OPEN_TOOL=%s: not a readable file", p)
		}
		return abs, nil
	}
	if p, err := exec.LookPath("gc-helm.sh"); err == nil {
		return p, nil
	}
	return "", errors.New("gc-helm.sh not found (set GC_HELM_OPEN_TOOL to its path, or put it on PATH)")
}

// timeout reads GC_HELM_OPEN_TIMEOUT as a Go duration ("90s") or a bare number
// of seconds, falling back to [DefaultTimeout]. Zero and negative fall back
// too: an instantly-expiring deadline would fail every open before the script
// could file anything, which is not a tuning knob.
func timeout() time.Duration {
	v := strings.TrimSpace(os.Getenv("GC_HELM_OPEN_TIMEOUT"))
	if v == "" {
		return DefaultTimeout
	}
	if d, err := time.ParseDuration(v); err == nil && d > 0 {
		return d
	}
	if secs, err := strconv.Atoi(v); err == nil && secs > 0 {
		return time.Duration(secs) * time.Second
	}
	return DefaultTimeout
}

// Script is the resolved path, for logging at startup.
func (o *Opener) Script() string { return o.script }

// Open runs `gc-helm.sh open <bead>` and returns its result.
//
// A non-zero exit is a RESULT, not an error: the exit codes are the script's
// contract and the HTTP layer maps them (see internal/server/open.go). Only a
// failure to run or to finish is an error, and those are reported as the
// sentinels [server.ErrToolUnavailable] and [server.ErrToolTimeout] so the
// mapping can tell them apart from each other and from an exit code.
//
// The bead argument is passed as an argv element — there is no shell, so no
// quoting question arises. It has already been validated against the bead-id
// shape by the handler, which is what keeps it from being read as a flag.
func (o *Opener) Open(ctx context.Context, bead string) (server.ToolResult, error) {
	ctx, cancel := context.WithTimeout(ctx, o.timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, o.script, "open", bead)
	if o.dir != "" {
		cmd.Dir = o.dir
		cmd.Env = append(os.Environ(), "GC_CITY_PATH="+o.dir)
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	// THE DEADLINE MUST REACH THE GRANDCHILDREN, or it does not bound anything.
	//
	// gc-helm.sh is not one process: it runs `gc rig list`, several `gc bd`
	// calls, `jq`. CommandContext's default cancel kills only the script, and a
	// surviving grandchild keeps the inherited stdout pipe open — so Wait blocks
	// on the copy goroutines until that child finishes on its own, long past the
	// timeout whose whole purpose was to stop waiting. Measured: a 50ms deadline
	// over a script whose child slept 5s returned after the full 5s.
	//
	// That is the exact case this bound exists for — a wedged data plane, where
	// the `gc bd` call is the thing hanging — and it would have held the HTTP
	// request and the handler's per-bead gate open for the duration.
	//
	// So: put the run in its own process group and cancel by signalling the
	// GROUP (negative pid), which reaches the children too. WaitDelay is the
	// backstop for anything that still holds a pipe after that.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return nil
		}
		return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	}
	cmd.WaitDelay = killGrace

	err := cmd.Run()
	res := server.ToolResult{Stdout: stdout.String(), Stderr: stderr.String()}

	if err == nil {
		return res, nil
	}
	// Deadline first: CommandContext kills the process on expiry, which surfaces
	// as a signal-shaped ExitError whose code would otherwise be mapped as if
	// the script had chosen it.
	if ctx.Err() != nil {
		return res, fmt.Errorf("%w after %s", server.ErrToolTimeout, o.timeout)
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		res.ExitCode = ee.ExitCode()
		return res, nil
	}
	// Could not start at all: not executable, vanished since resolution.
	return res, fmt.Errorf("%w: %s: %v", server.ErrToolUnavailable, o.script, err)
}
