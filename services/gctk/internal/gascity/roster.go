package gascity

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

// RosterWait bounds each read of the city's roster and of its config's named
// sessions. A caller asks them while an operator can be waiting at a prompt,
// such as operator-intake.sh's choice of path, so a read that hangs ends as one
// that did not answer.
const RosterWait = 15 * time.Second

// Agent is one agent the city's roster names (`gc agent list --json`): the name
// a route or an assignee matches it by, its own name, the rig directory it
// serves, empty for a city agent, its scope, whether it is suspended, and the
// most sessions its pool runs, nil when the roster gives none.
type Agent struct {
	QualifiedName string `json:"qualified_name"`
	Name          string `json:"name"`
	Dir           string `json:"dir"`
	Scope         string `json:"scope"`
	Suspended     bool   `json:"suspended"`
	Pool          *struct {
		Max *int `json:"max"`
	} `json:"pool"`
}

// MaxSessions is the most sessions the agent's pool runs, and false when the
// roster gives none.
func (a Agent) MaxSessions() (int, bool) {
	if a.Pool == nil || a.Pool.Max == nil {
		return 0, false
	}
	return *a.Pool.Max, true
}

// NamedSession is one named session the city's merged config lists
// (`gc config show --json`, config.NamedSessions): the agent template it runs
// and the rig directory it serves, empty for a city session.
type NamedSession struct {
	Template string `json:"Template"`
	Dir      string `json:"Dir"`
}

// Rig is one rig `gc rig list --json` names, the city's HQ among them: its
// name, the path its checkout and .beads sit under, its bead prefix, and
// whether it is the HQ.
type Rig struct {
	Name   string `json:"name"`
	Path   string `json:"path"`
	Prefix string `json:"prefix"`
	HQ     bool   `json:"hq"`
}

// Agents reads the city's roster, bounded by RosterWait. A read that fails,
// runs out of time or answers with no list of agents is an error.
func (c *City) Agents() ([]Agent, error) {
	r := c.runBounded(RosterWait, c.bin, "agent", "list", "--json")
	if r.Code != 0 {
		return nil, fmt.Errorf("gc agent list did not read the city's roster: %s", r.why())
	}
	var list struct {
		Agents *[]Agent `json:"agents"`
	}
	if err := json.Unmarshal([]byte(r.Output), &list); err != nil {
		return nil, fmt.Errorf("gc agent list's answer did not decode: %v", err)
	}
	if list.Agents == nil {
		return nil, errors.New("gc agent list answered with no list of agents")
	}
	return *list.Agents, nil
}

// NamedSessions reads the named sessions the city's merged config lists, once
// per process, bounded by RosterWait. A read that fails, runs out of time or
// answers with no list of them is an error.
func (c *City) NamedSessions() ([]NamedSession, error) {
	c.namedOnce.Do(func() { c.named, c.namedErr = c.readNamed() })
	return c.named, c.namedErr
}

func (c *City) readNamed() ([]NamedSession, error) {
	r := c.runBounded(RosterWait, c.bin, "config", "show", "--json")
	if r.Code != 0 {
		return nil, fmt.Errorf("gc config show did not read the city's config: %s", r.why())
	}
	var shown struct {
		Config struct {
			NamedSessions *[]NamedSession `json:"NamedSessions"`
		} `json:"config"`
	}
	if err := json.Unmarshal([]byte(r.Output), &shown); err != nil {
		return nil, fmt.Errorf("gc config show's answer did not decode: %v", err)
	}
	if shown.Config.NamedSessions == nil {
		return nil, errors.New("gc config show answered with no list of named sessions")
	}
	return *shown.Config.NamedSessions, nil
}

// Rigs reads the rigs `gc rig list --json` names, once per process. A read that
// fails or answers with no list of rigs is an error.
func (c *City) Rigs() ([]Rig, error) {
	c.rigsOnce.Do(func() { c.rigs, c.rigsErr = c.readRigs() })
	return c.rigs, c.rigsErr
}

func (c *City) readRigs() ([]Rig, error) {
	r := c.run(c.bin, "rig", "list", "--json")
	if r.Code != 0 {
		return nil, fmt.Errorf("gc rig list did not read the city's rigs: %s", r.why())
	}
	var list struct {
		Rigs *[]Rig `json:"rigs"`
	}
	if err := json.Unmarshal([]byte(r.Output), &list); err != nil {
		return nil, fmt.Errorf("gc rig list's answer did not decode: %v", err)
	}
	if list.Rigs == nil {
		return nil, errors.New("gc rig list answered with no list of rigs")
	}
	return *list.Rigs, nil
}

// ShowFormula runs one `gc formula show <name>`, which exits 0 only for a
// formula the city resolves.
func (c *City) ShowFormula(name string) Result {
	return c.run(c.bin, "formula", "show", name)
}

// runBounded is run with a time limit: once limit passes, the command's whole
// process group is killed and the result says it did not answer in time.
func (c *City) runBounded(limit time.Duration, bin string, args ...string) Result {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, args...)
	cmd.Dir = c.dir
	if c.actor != "" {
		cmd.Env = append(os.Environ(), "BEADS_ACTOR="+c.actor)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = 2 * time.Second
	var out bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &out
	err := cmd.Run()
	var ee *exec.ExitError
	switch {
	case ctx.Err() != nil:
		return Result{Code: -1, Output: out.String(), Err: fmt.Errorf("%s did not answer within %s", bin+" "+args[0]+" "+args[1], limit)}
	case err == nil:
		return Result{Code: 0, Output: out.String()}
	case errors.As(err, &ee):
		return Result{Code: ee.ExitCode(), Output: out.String()}
	default:
		return Result{Code: -1, Output: out.String(), Err: err}
	}
}
