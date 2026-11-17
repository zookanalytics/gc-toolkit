package gascity

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// Sessions reads each row's identities, its state and its times, and reads a
// last_active of "" or one that does not parse as no time.
func TestSessionsReadsTheList(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"schema_version":"1","_cache_age_s":2.5,"filters":{},"sessions":[{"id":"hq-1","name":"rig__polecat-hq-1","template":"rig/gc-toolkit.polecat","state":"active","rig":"rig","agent_name":"rig/gc-toolkit.polecat-3","session_name":"rig__polecat-hq-1","created_at":"2026-11-16T20:00:00Z","last_active":"2026-11-16T23:15:36Z","attached":false,"closed":false},{"id":"hq-2","name":"rig/gc-toolkit.refinery","template":"rig/gc-toolkit.refinery","state":"asleep","alias":"rig/gc-toolkit.refinery","created_at":"2026-11-01T00:00:00Z","last_active":""},{"id":"hq-3","state":"active","created_at":"2026-11-01T00:00:00Z","last_active":"yesterday"}],"summary":{"total":3}}'
`)
	got, err := c.Sessions(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 3 {
		t.Fatalf("read %d sessions: %+v", len(got), got)
	}
	s := got[0]
	if s.ID != "hq-1" || s.AgentName != "rig/gc-toolkit.polecat-3" || s.SessionName != "rig__polecat-hq-1" || s.State != "active" || s.Rig != "rig" {
		t.Errorf("first row %+v", s)
	}
	if !s.LastActive.Equal(time.Date(2026, 11, 16, 23, 15, 36, 0, time.UTC)) || !s.CreatedAt.Equal(time.Date(2026, 11, 16, 20, 0, 0, 0, time.UTC)) {
		t.Errorf("first row's times %v, %v", s.LastActive, s.CreatedAt)
	}
	if got[1].Alias != "rig/gc-toolkit.refinery" || !got[1].LastActive.IsZero() || !got[2].LastActive.IsZero() {
		t.Errorf("rows %+v", got[1:])
	}
	if strings.Join(log(), " ") != "session list --json" {
		t.Errorf("gc ran with %q", log())
	}
}

// A list that reads with no sessions is an empty list, and a read that fails
// or prints no sessions list is an error.
func TestSessionsFailsClosed(t *testing.T) {
	c, _ := stubGC(t, `printf '%s\n' '{"schema_version":"1","sessions":[]}'`)
	if got, err := c.Sessions(context.Background()); err != nil || len(got) != 0 || got == nil {
		t.Errorf("an empty list answered %v, %v", got, err)
	}
	for _, body := range []string{
		"echo 'gc session list: no city' >&2\nexit 1\n",
		"printf '%s\\n' '{\"schema_version\":\"1\"}'\n",
		"printf '%s\\n' '{\"sessions\":null}'\n",
		"printf 'not json\\n'\n",
	} {
		c, _ := stubGC(t, body)
		if got, err := c.Sessions(context.Background()); err == nil {
			t.Errorf("%q answered %+v and no error", body, got)
		}
	}
}

// Rigs reads each rig's name, path, prefix and HQ flag, and refuses a rig with
// no name or no path.
func TestRigsReadsTheList(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"city_name":"c","rigs":[{"name":"c","path":"/c","prefix":"hq","hq":true,"suspended":false,"beads":"initialized"},{"name":"tools","path":"/c/rigs/tools","prefix":"tk","hq":false,"suspended":true}]}'`)
	got, err := c.Rigs(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := []Rig{{Name: "c", Path: "/c", Prefix: "hq", HQ: true}, {Name: "tools", Path: "/c/rigs/tools", Prefix: "tk", Suspended: true}}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("read %+v", got)
	}
	if strings.Join(log(), " ") != "rig list --json" {
		t.Errorf("gc ran with %q", log())
	}
	for _, body := range []string{
		"exit 2\n",
		"printf '%s\\n' '{\"city_name\":\"c\"}'\n",
		"printf '%s\\n' '{\"rigs\":[{\"name\":\"c\",\"path\":\"\"}]}'\n",
	} {
		c, _ := stubGC(t, body)
		if got, err := c.Rigs(context.Background()); err == nil {
			t.Errorf("%q answered %+v and no error", body, got)
		}
	}
}

// Agents reads each agent's name, qualified name and directory, and refuses
// an agent with no name or no qualified name.
func TestAgentsReadsTheList(t *testing.T) {
	c, log := stubGC(t, `printf '%s\n' '{"agents":[{"name":"refinery","qualified_name":"tools/gc-toolkit.refinery","dir":"tools","scope":"rig","suspended":false},{"name":"mechanik","qualified_name":"gc-toolkit.mechanik","suspended":true}]}'`)
	got, err := c.Agents(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	want := []Agent{{Name: "refinery", QualifiedName: "tools/gc-toolkit.refinery", Dir: "tools"}, {Name: "mechanik", QualifiedName: "gc-toolkit.mechanik", Suspended: true}}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Errorf("read %+v", got)
	}
	if strings.Join(log(), " ") != "agent list --json" {
		t.Errorf("gc ran with %q", log())
	}
	for _, body := range []string{
		"exit 1\n",
		"printf '%s\\n' '[]'\n",
		"printf '%s\\n' '{\"agents\":[{\"name\":\"refinery\"}]}'\n",
	} {
		c, _ := stubGC(t, body)
		if got, err := c.Agents(context.Background()); err == nil {
			t.Errorf("%q answered %+v and no error", body, got)
		}
	}
}

// A list read the context ends first answers ErrDeadline.
func TestListReadsEndAtTheDeadline(t *testing.T) {
	c, _ := stubGC(t, "sleep 30\n")
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	if _, err := c.Sessions(ctx); err == nil || !strings.Contains(err.Error(), ErrDeadline.Error()) {
		t.Errorf("answered %v", err)
	}
	if !errors.Is(ctx.Err(), context.DeadlineExceeded) {
		t.Errorf("the context did not end: %v", ctx.Err())
	}
}
