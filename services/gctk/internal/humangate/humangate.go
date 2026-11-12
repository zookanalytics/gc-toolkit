// Package humangate is gctk's seam to the pack's one writer of a human gate,
// human-gate.sh in the pack's scripts directory (docs/gctk-architecture.md,
// "The adapters"). The script files one open gate per bead and situation key,
// titled with the message's first line, and the gate blocks the bead until a
// person clears it. This adapter runs it and holds none of its rules.
package humangate

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// Gates files human gates through the pack's human-gate.sh.
type Gates struct {
	script string
}

// New returns the gate writer in the pack's scripts directory scripts.
func New(scripts string) *Gates {
	return &Gates{script: filepath.Join(scripts, "human-gate.sh")}
}

// File files a human gate on subject under key, carrying message, or finds the
// one already open there. An error is a gate the script did not file, with the
// script's own words.
func (g *Gates) File(subject, key, message string) error {
	if subject == "" || key == "" || message == "" {
		return errors.New("human gate: a gate names its bead, its key and its message")
	}
	cmd := exec.Command(g.script, "--subject", subject, "--key", key, "--message", message)
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(out.String()); msg != "" {
			return fmt.Errorf("human gate on %s [%s]: %w: %s", subject, key, err, msg)
		}
		return fmt.Errorf("human gate on %s [%s]: %w", subject, key, err)
	}
	return nil
}
