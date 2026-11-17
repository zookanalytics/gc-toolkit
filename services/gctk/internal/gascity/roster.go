package gascity

import (
	"context"
	"encoding/json"
	"fmt"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"
)

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

// Rig is one rig `gc rig list --json` lists, the city's own HQ among them
// (RigListItem in cmd/gc/cmd_rig.go at gastownhall/gascity c7eb6d2f43): its
// name, the absolute path of its directory, which holds its bead store's
// .beads, its bead prefix, and whether it is the HQ or suspended.
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

// Rigs reads `gc rig list --json` once. A read that fails, prints no rigs list
// that reads, or lists a rig with no name or no path is an error.
func (c *City) Rigs(ctx context.Context) ([]Rig, error) {
	b := c.runBounded(ctx, c.bin, "rig", "list", "--json")
	if f := b.Failure(); f != "" {
		return nil, fmt.Errorf("gc rig list did not read: %s", f)
	}
	var list struct {
		Rigs *[]Rig `json:"rigs"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &list); err != nil || list.Rigs == nil {
		return nil, fmt.Errorf("gc rig list printed no rigs list that reads: %s", clipLine(b.Stdout))
	}
	for _, r := range *list.Rigs {
		if r.Name == "" || r.Path == "" {
			return nil, fmt.Errorf("gc rig list listed a rig with no name or no path: %+v", r)
		}
	}
	return *list.Rigs, nil
}

// Agent is one agent `gc agent list --json` lists (AgentListItem in
// cmd/gc/cmd_agent.go at gastownhall/gascity c7eb6d2f43): its template's name,
// the identity work assigned to it names, and the rig whose directory it
// serves, empty for a city-scoped agent.
type Agent struct {
	Name          string `json:"name"`
	QualifiedName string `json:"qualified_name"`
	Dir           string `json:"dir"`
	Suspended     bool   `json:"suspended"`
}

// Agents reads `gc agent list --json` once. A read that fails, prints no agents
// list that reads, or lists an agent with no name or no qualified name is an
// error.
func (c *City) Agents(ctx context.Context) ([]Agent, error) {
	b := c.runBounded(ctx, c.bin, "agent", "list", "--json")
	if f := b.Failure(); f != "" {
		return nil, fmt.Errorf("gc agent list did not read: %s", f)
	}
	var list struct {
		Agents *[]Agent `json:"agents"`
	}
	if err := json.Unmarshal([]byte(strings.TrimSpace(b.Stdout)), &list); err != nil || list.Agents == nil {
		return nil, fmt.Errorf("gc agent list printed no agents list that reads: %s", clipLine(b.Stdout))
	}
	for _, a := range *list.Agents {
		if a.Name == "" || a.QualifiedName == "" {
			return nil, fmt.Errorf("gc agent list listed an agent with no name or no qualified name: %+v", a)
		}
	}
	return *list.Agents, nil
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
