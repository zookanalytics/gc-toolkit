package gascity

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// stubCity is a city whose gc logs each call's arguments as one line, answers
// with the file the call's first two words name under replies (agent-list,
// config-show, rig-list), and exits STUB_EXIT.
func rosterCity(t *testing.T, replies map[string]string) (*City, string) {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "log")
	for name, body := range replies {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	stub := "#!/bin/sh\necho \"$*\" >> '" + log + "'\nf='" + dir + "'/\"$1-$2\"\n[ -f \"$f\" ] && cat \"$f\"\nexit \"${STUB_EXIT:-0}\"\n"
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("STUB_EXIT", "0")
	return &City{bin: filepath.Join(dir, "gc")}, log
}

func rosterCalls(t *testing.T, log string) []string {
	t.Helper()
	raw, _ := os.ReadFile(log)
	return strings.Split(strings.TrimSpace(string(raw)), "\n")
}

// The roster reads every agent with the fields the pool's and a named agent's
// answers read, and a roster that does not answer, or answers with no list, is
// an error rather than an empty city.
func TestTheRosterReadsEveryAgent(t *testing.T) {
	c, _ := rosterCity(t, map[string]string{"agent-list": `{"agents":[
		{"qualified_name":"rig/gc-toolkit.polecat","name":"polecat","dir":"rig","scope":"rig","suspended":false,"pool":{"min":0,"max":2}},
		{"qualified_name":"gc-toolkit.mechanik","name":"mechanik","dir":null,"scope":"city","suspended":true}]}`})
	agents, err := c.Agents()
	if err != nil || len(agents) != 2 {
		t.Fatalf("Agents = %+v, %v", agents, err)
	}
	if n, ok := agents[0].MaxSessions(); !ok || n != 2 || agents[0].Dir != "rig" || agents[0].Scope != "rig" {
		t.Errorf("the pool read as %+v (max %d, %v)", agents[0], n, ok)
	}
	if _, ok := agents[1].MaxSessions(); ok || !agents[1].Suspended || agents[1].Dir != "" {
		t.Errorf("the named agent read as %+v", agents[1])
	}
	for _, reply := range []string{`{"ok":true}`, `not json`} {
		c, _ := rosterCity(t, map[string]string{"agent-list": reply})
		if a, err := c.Agents(); err == nil {
			t.Errorf("the roster %q read as %+v", reply, a)
		}
	}
	c, _ = rosterCity(t, map[string]string{"agent-list": `{"agents":[]}`})
	t.Setenv("STUB_EXIT", "1")
	if a, err := c.Agents(); err == nil {
		t.Errorf("a roster read that exited 1 read as %+v", a)
	}
}

// A bounded read that runs out of time ends with its whole process group and
// says it did not answer in time.
func TestABoundedReadEndsAtItsLimit(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "gc")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\nsleep 30 &\nwait\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	r := runBounded(dir, 200*time.Millisecond, bin, "agent", "list")
	if r.Code != -1 || r.Err == nil || !strings.Contains(r.Err.Error(), "did not answer within") {
		t.Fatalf("a read past its limit answered %+v", r)
	}
	if took := time.Since(start); took > 10*time.Second {
		t.Fatalf("the read ended %s after it started", took)
	}
}

// The named sessions and the rigs are each read once per process, whatever
// asks, and a list the answer does not carry is an error.
func TestTheNamedSessionsAndTheRigsAreReadOnce(t *testing.T) {
	c, log := rosterCity(t, map[string]string{
		"config-show": `{"config":{"NamedSessions":[{"Name":"","Template":"mechanik","Scope":"city","Dir":""},{"Template":"refinery","Dir":"rig"}]}}`,
		"rig-list":    `{"rigs":[{"name":"town","path":"/town","prefix":"lx","hq":true},{"name":"rig","path":"/town/rigs/rig","prefix":"tk"}]}`,
	})
	for range 3 {
		named, err := c.NamedSessions()
		if err != nil || len(named) != 2 || named[1].Template != "refinery" || named[1].Dir != "rig" {
			t.Fatalf("NamedSessions = %+v, %v", named, err)
		}
		rigs, err := c.Rigs()
		if err != nil || len(rigs) != 2 || !rigs[0].HQ || rigs[1].Prefix != "tk" || rigs[1].Path != "/town/rigs/rig" {
			t.Fatalf("Rigs = %+v, %v", rigs, err)
		}
	}
	if got := rosterCalls(t, log); len(got) != 2 {
		t.Fatalf("three asks of each made the calls %q, want one of each", got)
	}
	c, _ = rosterCity(t, map[string]string{"config-show": `{"config":{}}`, "rig-list": `{"ok":true}`})
	if _, err := c.NamedSessions(); err == nil {
		t.Error("a config with no named sessions listed read as an answer")
	}
	if _, err := c.Rigs(); err == nil {
		t.Error("a rig list with no rigs listed read as an answer")
	}
}

// A sling with no formula routes the bead to the target's own name and files
// no convoy, a sling with no title passes none, and a nudge and a formula's
// show each run as one call.
func TestTheSlingNudgeAndFormulaCalls(t *testing.T) {
	c, log := rosterCity(t, nil)
	c.Sling(Sling{Rig: "rig", Target: "gc-toolkit.mechanik", Bead: "tk-1", NoFormula: true})
	c.Sling(Sling{Target: "rig/gc-toolkit.polecat", Bead: "tk-1", Formula: "mol-validate-close"})
	c.Nudge("gc-toolkit.mechanik", "tk-1 is routed to you and ready")
	c.ShowFormula("mol-polecat-work")
	want := []string{
		"sling --rig rig gc-toolkit.mechanik tk-1 --no-formula --no-convoy",
		"sling rig/gc-toolkit.polecat tk-1 --on mol-validate-close",
		"session nudge gc-toolkit.mechanik tk-1 is routed to you and ready",
		"formula show mol-polecat-work",
	}
	if got := rosterCalls(t, log); strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("the calls ran %q, want %q", got, want)
	}
}
