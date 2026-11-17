// Package claudecode is gctk's adapter for Claude Code: it asks Claude Code
// where a session keeps its auto memory, and copies none of the rules Claude
// Code places memory by (docs/gctk-architecture.md, "The adapters").
package claudecode

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Claude is Claude Code as one gctk process asks it.
type Claude interface {
	// MemoryDir asks where a session started in a.Dir keeps its auto memory.
	// An error is an ask that did not answer.
	MemoryDir(a Ask) (Answer, error)
}

// Ask names the directory a session starts in and the settings file Gas City
// starts each Claude session with, "" for none.
type Ask struct {
	Dir, Settings string
}

// Answer is the startup record's memory_paths.auto and claude_code_version.
// Dir is empty when the record names no auto memory directory, which Claude
// Code does both when memory is off and in a version that stops reporting it.
type Answer struct {
	Dir, Version string
}

const (
	askTimeout = 60 * time.Second
	stopGrace  = 2 * time.Second
	prompt     = "Reply with OK."
)

// CLI asks the claude on PATH.
type CLI struct {
	bin     string
	timeout time.Duration
}

var _ Claude = (*CLI)(nil)

// New returns the adapter over the claude on PATH.
func New() *CLI { return &CLI{bin: "claude", timeout: askTimeout} }

// MemoryDir runs one bounded one-turn `claude -p` in a.Dir with the settings a
// city session gets, its hooks off, and reads the stream's init record. It then
// removes each directory the ask made on the way to the memory directory.
func (c *CLI) MemoryDir(a Ask) (Answer, error) {
	settings, err := askSettings(a.Settings)
	if err != nil {
		return Answer{}, err
	}
	began := time.Now().Truncate(time.Second)
	ctx, cancel := context.WithTimeout(context.Background(), c.timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, c.bin, "-p", "--output-format", "stream-json", "--verbose",
		"--max-turns", "1", "--no-session-persistence", "--strict-mcp-config", "--model", "haiku",
		"--settings", settings, prompt)
	cmd.Dir = a.Dir
	cmd.Env = sessionless(os.Environ())
	cmd.WaitDelay = stopGrace
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	runErr := cmd.Run()
	ans, found := initRecord(&stdout)
	switch {
	case ctx.Err() != nil && !found:
		return Answer{}, fmt.Errorf("claude did not answer within %s", c.timeout)
	case !found:
		return Answer{}, fmt.Errorf("claude printed no init record (%s)", failure(runErr, stderr.String()))
	}
	if ans.Dir != "" {
		removeMade(ans.Dir, began)
	}
	return ans, nil
}

// askSettings is the settings file's JSON object with disableAllHooks set, as
// one --settings value, since a second --settings flag replaces the first.
func askSettings(file string) (string, error) {
	obj := map[string]json.RawMessage{}
	if file != "" {
		raw, err := os.ReadFile(file)
		switch {
		case errors.Is(err, os.ErrNotExist):
		case err != nil:
			return "", fmt.Errorf("the settings file %s did not read: %w", file, err)
		default:
			if err := json.Unmarshal(raw, &obj); err != nil || obj == nil {
				return "", fmt.Errorf("the settings file %s holds no JSON object", file)
			}
		}
	}
	obj["disableAllHooks"] = json.RawMessage("true")
	out, err := json.Marshal(obj)
	if err != nil {
		return "", fmt.Errorf("the ask's settings did not encode: %w", err)
	}
	return string(out), nil
}

// sessionVars are the variables that tie a process to the Claude Code session
// that started it; a name ending in "_" is a prefix.
var sessionVars = []string{"CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_MESSAGING_"}

func sessionless(env []string) []string {
	out := make([]string, 0, len(env))
	for _, kv := range env {
		name, _, _ := strings.Cut(kv, "=")
		drop := false
		for _, v := range sessionVars {
			if name == v || (strings.HasSuffix(v, "_") && strings.HasPrefix(name, v)) {
				drop = true
				break
			}
		}
		if !drop {
			out = append(out, kv)
		}
	}
	return out
}

// initRecord is what the stream's first system record of subtype init says,
// and whether the stream held one.
func initRecord(r io.Reader) (Answer, bool) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for sc.Scan() {
		var rec struct {
			Type        string `json:"type"`
			Subtype     string `json:"subtype"`
			Version     string `json:"claude_code_version"`
			MemoryPaths *struct {
				Auto string `json:"auto"`
			} `json:"memory_paths"`
		}
		if json.Unmarshal(sc.Bytes(), &rec) != nil || rec.Type != "system" || rec.Subtype != "init" {
			continue
		}
		ans := Answer{Version: rec.Version}
		if rec.MemoryPaths != nil {
			ans.Dir = rec.MemoryPaths.Auto
		}
		return ans, true
	}
	return Answer{}, false
}

// removeMade removes, by real path from dir upward, each directory that is
// empty and changed no earlier than began, and stops at the first that is not.
func removeMade(dir string, began time.Time) {
	real, err := filepath.EvalSymlinks(filepath.Clean(dir))
	if err != nil {
		return
	}
	for d := real; d != filepath.Dir(d); d = filepath.Dir(d) {
		fi, err := os.Lstat(d)
		if err != nil || !fi.IsDir() || fi.ModTime().Before(began) {
			return
		}
		if entries, err := os.ReadDir(d); err != nil || len(entries) > 0 {
			return
		}
		if os.Remove(d) != nil {
			return
		}
	}
}

// failure is why a run printed no init record, in one line.
func failure(err error, stderr string) string {
	lines := strings.Split(strings.TrimSpace(stderr), "\n")
	last := strings.TrimSpace(lines[len(lines)-1])
	var ee *exec.ExitError
	switch {
	case err == nil && last == "":
		return "it exited 0"
	case err == nil:
		return "it exited 0: " + last
	case errors.As(err, &ee) && last != "":
		return fmt.Sprintf("exit %d: %s", ee.ExitCode(), last)
	case errors.As(err, &ee):
		return fmt.Sprintf("exit %d", ee.ExitCode())
	}
	return err.Error()
}
