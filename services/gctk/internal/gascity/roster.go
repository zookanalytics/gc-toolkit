package gascity

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// RosterWait bounds each read of the city's roster and of its config's named
// sessions. A caller asks them while an operator can be waiting at a prompt,
// such as operator-intake.sh's choice of path, so a read that hangs ends as one
// that did not answer.
const RosterWait = 15 * time.Second

// RigListWait bounds each read of the city's rig list when GC_RIG_LIST_TIMEOUT
// sets none. rig-map.sh bounds its read by the same variable and default, which
// cut off a gc that never answers and so sit far above what the listing takes
// on a loaded host (docs/bead-store-resolution.md, "Reading the rig map").
const RigListWait = 120 * time.Second

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
// whether it is the HQ or suspended.
type Rig struct {
	Name      string `json:"name"`
	Path      string `json:"path"`
	Prefix    string `json:"prefix"`
	HQ        bool   `json:"hq"`
	Suspended bool   `json:"suspended"`
}

// Store is the rig's bead store, the .beads directory under its path, which a
// read pinned there names with bd's --db.
func (r Rig) Store() string { return filepath.Join(r.Path, ".beads") }

// Agents reads the city's roster, bounded by RosterWait. A read that fails,
// runs out of time or answers with no list of agents is an error.
func (c *City) Agents() ([]Agent, error) {
	out, err := c.readBounded(RosterWait, c.bin, "agent", "list", "--json")
	if err != nil {
		return nil, fmt.Errorf("gc agent list did not read the city's roster: %v", err)
	}
	var list struct {
		Agents *[]Agent `json:"agents"`
	}
	if err := json.Unmarshal(out, &list); err != nil {
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
	out, err := c.readBounded(RosterWait, c.bin, "config", "show", "--json")
	if err != nil {
		return nil, fmt.Errorf("gc config show did not read the city's config: %v", err)
	}
	var shown struct {
		Config struct {
			NamedSessions *[]NamedSession `json:"NamedSessions"`
		} `json:"config"`
	}
	if err := json.Unmarshal(out, &shown); err != nil {
		return nil, fmt.Errorf("gc config show's answer did not decode: %v", err)
	}
	if shown.Config.NamedSessions == nil {
		return nil, errors.New("gc config show answered with no list of named sessions")
	}
	return *shown.Config.NamedSessions, nil
}

// Rigs reads the rigs `gc rig list --json` names, once per process, bounded by
// GC_RIG_LIST_TIMEOUT's whole seconds, or by RigListWait when it is unset or
// empty. A read that fails, runs out of time or answers with no list of rigs is
// an error, and so is a GC_RIG_LIST_TIMEOUT that is not a whole number of
// seconds above 0, which rig-map.sh refuses too.
func (c *City) Rigs() ([]Rig, error) {
	c.rigsOnce.Do(func() { c.rigs, c.rigsErr = c.readRigs() })
	return c.rigs, c.rigsErr
}

func (c *City) readRigs() ([]Rig, error) {
	limit, err := rigListWait()
	if err != nil {
		return nil, err
	}
	out, err := c.readBounded(limit, c.bin, "rig", "list", "--json")
	if err != nil {
		return nil, fmt.Errorf("gc rig list did not read the city's rigs: %v", err)
	}
	var list struct {
		Rigs *[]Rig `json:"rigs"`
	}
	if err := json.Unmarshal(out, &list); err != nil {
		return nil, fmt.Errorf("gc rig list's answer did not decode: %v", err)
	}
	if list.Rigs == nil {
		return nil, errors.New("gc rig list answered with no list of rigs")
	}
	return *list.Rigs, nil
}

// rigListWait is the bound Rigs reads the list under.
func rigListWait() (time.Duration, error) {
	v := os.Getenv("GC_RIG_LIST_TIMEOUT")
	if v == "" {
		return RigListWait, nil
	}
	n, err := strconv.ParseUint(v, 10, 32)
	if err != nil || n == 0 {
		return 0, fmt.Errorf("gc rig list was not run: GC_RIG_LIST_TIMEOUT=%q is not a whole number of seconds above 0", v)
	}
	return time.Duration(n) * time.Second, nil
}

// Session is one session `gc session list --json` lists, which with no --state
// is every session that has not closed (sessionListJSONRow in
// cmd/gc/cmd_session.go at gastownhall/gascity c7eb6d2f43). Each of ID, Name,
// SessionName, Alias and AgentName is an identity a bead can name the session
// by, and is empty when the row carries none. LastActive is when its pane last
// printed, zero when it has not printed or the row's time does not read.
type Session struct {
	ID          string
	Name        string
	Template    string
	Rig         string
	State       string
	Alias       string
	AgentName   string
	SessionName string
	CreatedAt   time.Time
	LastActive  time.Time
}

// sessionRow is the row as gc prints it: last_active is RFC 3339 in UTC, or
// "" when the session has not been active (sessionListLastActive there).
type sessionRow struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	Template    string    `json:"template"`
	Rig         string    `json:"rig"`
	State       string    `json:"state"`
	Alias       string    `json:"alias"`
	AgentName   string    `json:"agent_name"`
	SessionName string    `json:"session_name"`
	CreatedAt   time.Time `json:"created_at"`
	LastActive  string    `json:"last_active"`
}

// Sessions reads `gc session list --json` once. A read that fails, or prints
// no JSON object carrying a sessions list, is an error, never an empty list.
func (c *City) Sessions(ctx context.Context) ([]Session, error) {
	b := c.runBounded(ctx, c.bin, "session", "list", "--json")
	if f := b.Failure(); f != "" {
		return nil, fmt.Errorf("gc session list did not read: %s", f)
	}
	var list struct {
		Sessions *[]sessionRow `json:"sessions"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &list); err != nil || list.Sessions == nil {
		return nil, fmt.Errorf("gc session list printed no session list that reads: %s", clipLine(b.Stdout))
	}
	out := make([]Session, 0, len(*list.Sessions))
	for _, r := range *list.Sessions {
		s := Session{ID: r.ID, Name: r.Name, Template: r.Template, Rig: r.Rig, State: r.State, Alias: r.Alias,
			AgentName: r.AgentName, SessionName: r.SessionName, CreatedAt: r.CreatedAt.UTC()}
		if t, err := time.Parse(time.RFC3339, r.LastActive); err == nil {
			s.LastActive = t.UTC()
		}
		out = append(out, s)
	}
	return out, nil
}

// ShowFormula runs one `gc formula show <name>`, which exits 0 only for a
// formula the city resolves.
func (c *City) ShowFormula(name string) Result {
	return c.run(c.bin, "formula", "show", name)
}

// readBounded runs one of gc's reads with a time limit and returns what it
// printed on standard output, the answer to decode. gc prints a config warning
// on standard error and still exits 0 with its whole answer (doAgentList hands
// its stderr to the config load's warnings, in cmd/gc/cmd_agent.go at
// gastownhall/gascity 191c6b5b8b), so standard error is read only to say why a
// read that exits non-zero failed. It runs through runBounded: once limit
// passes, the command's whole process group is killed and the read says it did
// not answer in time, and a stop this process is sent kills the group too.
func (c *City) readBounded(limit time.Duration, bin string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), limit)
	defer cancel()
	out := c.runBounded(ctx, bin, args...)
	switch {
	case errors.Is(out.Err, ErrDeadline):
		return nil, fmt.Errorf("%s did not answer within %s", bin+" "+args[0]+" "+args[1], limit)
	case out.Err != nil:
		return nil, out.Err
	case out.Code != 0:
		return nil, errors.New(Result{Code: out.Code, Output: out.Stdout + "\n" + out.Stderr}.why())
	}
	return []byte(out.Stdout), nil
}

// clipLine is output in one line of at most 200 bytes, for a message that
// shows what a read printed in place of what it should have.
func clipLine(s string) string {
	s = strings.Join(strings.Fields(s), " ")
	if s == "" {
		return "it printed nothing"
	}
	if len(s) <= 200 {
		return s
	}
	cut := 200
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut] + "…"
}
