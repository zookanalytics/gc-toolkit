package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/refinery"
	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
	"github.com/zookanalytics/gc-toolkit/services/gctk/worktree"
)

// lookCity is the city the looks' stub gc answers for: an HQ at /city and the
// rig tools, which its refinery serves.
type lookCity struct {
	sessions string // gc session list --json
	hq, rig  string // gc bd list of each store's live beads
	writes   string // the write log's answer
	emit     string // gc event emit --json
}

// lookStub puts a gc on PATH that logs each call's arguments on one line and
// answers the looks' reads the way a city does: the session, rig and agent
// lists, each store's listing, its blocked set, its write log, and the event
// emit. A read of beads by id answers the store's listing too.
func lookStub(t *testing.T, c lookCity) (calls func() string) {
	t.Helper()
	bin := t.TempDir()
	log := filepath.Join(bin, "calls")
	answer := func(name, text string) string {
		p := filepath.Join(bin, name)
		if err := os.WriteFile(p, []byte(text+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	if c.emit == "" {
		c.emit = `{"ok":true,"submitted":true}`
	}
	if c.writes == "" {
		c.writes = "[]"
	}
	stub := `#!/bin/sh
echo "$*" >> '` + log + `'
case "$*" in
  "session list --json") cat '` + answer("sessions", c.sessions) + `' ;;
  "rig list --json") cat '` + answer("rigs", `{"rigs":[{"name":"city","path":"/city","prefix":"lx","hq":true},{"name":"tools","path":"/city/rigs/tools","prefix":"tk","hq":false}]}`) + `' ;;
  "agent list --json") cat '` + answer("agents", `{"agents":[{"name":"refinery","qualified_name":"tools/gc-toolkit.refinery","dir":"tools"}]}`) + `' ;;
  "bd --db /city/.beads list "*) cat '` + answer("hq", c.hq) + `' ;;
  "bd --db /city/rigs/tools/.beads list "*) cat '` + answer("rig", c.rig) + `' ;;
  "bd --db "*" blocked --json") echo '[]' ;;
  "bd --db "*" sql --json "*wisp_events*) cat '` + answer("writes", c.writes) + `' ;;
  "bd --db "*" sql --json "*) echo '[]' ;;
  "event emit "*) cat '` + answer("emit", c.emit) + `' ;;
  *) echo "stub gc: no answer for $*" >&2; exit 9 ;;
esac
`
	if err := os.WriteFile(filepath.Join(bin, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, v := range []string{"GC_CITY", "GC_CITY_PATH", "GC_CITY_ROOT", "GC_RIG", "GC_RIG_ROOT", "BEADS_DIR"} {
		t.Setenv(v, "")
	}
	return func() string {
		raw, _ := os.ReadFile(log)
		return string(raw)
	}
}

func agoStamp(d time.Duration) string { return time.Now().UTC().Add(-d).Format(time.RFC3339) }

const liveSessions = `{"schema_version":"1","sessions":[{"id":"lx-ctl","alias":"control-dispatcher","state":"active","created_at":"2026-11-01T00:00:00Z","last_active":""}]}`

// salvage finds a claim whose session no live session answers to, records it
// as one event, prints the record and a summary, and exits 0.
func TestWorktreeSalvageRecordsWhatItFound(t *testing.T) {
	calls := lookStub(t, lookCity{
		sessions: liveSessions,
		hq:       "[]",
		rig:      `[{"id":"tk-1","title":"t","status":"in_progress","issue_type":"task","assignee":"lx-dead","metadata":{"gc.session_id":"lx-dead","work_dir":"/wt/tk-1"}},{"id":"tk-2","title":"t","status":"in_progress","issue_type":"task","assignee":"control-dispatcher"}]`,
	})
	var out, errb bytes.Buffer
	if code := Run([]string{"worktree", "salvage"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	var rec worktree.Record
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil || len(rec.Found) != 1 || rec.Found[0].Bead != "tk-1" || rec.Found[0].WorkDir != "/wt/tk-1" {
		t.Fatalf("stdout %q: %v", out.String(), err)
	}
	if got := errb.String(); got != "gctk worktree salvage: beads whose owner no live session answers to: tk-1; recorded\n" {
		t.Errorf("stderr %q", got)
	}
	got := calls()
	for _, want := range []string{
		"session list --json\nrig list --json\n",
		"bd --db /city/.beads list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0\n",
		"bd --db /city/rigs/tools/.beads list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0\n",
		"event emit gc-toolkit.orphan-work.found --json --actor gctk --message beads whose owner no live session answers to: tk-1 --payload {",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("gc was not called with %q:\n%s", want, got)
		}
	}
}

// A look that finds nothing prints its record, records nothing, and exits 0.
func TestWorktreeSalvageWithNothingFound(t *testing.T) {
	calls := lookStub(t, lookCity{sessions: liveSessions, hq: "[]", rig: "[]"})
	var out, errb bytes.Buffer
	if code := Run([]string{"worktree", "salvage"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if !strings.Contains(out.String(), `"found":[]`) {
		t.Errorf("stdout %q", out.String())
	}
	if got := errb.String(); got != "gctk worktree salvage: no bead names an owner that no live session answers to; nothing recorded\n" {
		t.Errorf("stderr %q", got)
	}
	if strings.Contains(calls(), "event emit") {
		t.Errorf("an event was recorded:\n%s", calls())
	}
}

// A session list that does not read fails the run with no record.
func TestWorktreeSalvageFailsOnAnUnreadSessionList(t *testing.T) {
	calls := lookStub(t, lookCity{sessions: `not json`, hq: "[]", rig: "[]"})
	var out, errb bytes.Buffer
	if code := Run([]string{"worktree", "salvage"}, "", &out, &errb); code != 1 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if out.Len() != 0 || !strings.Contains(errb.String(), "gctk worktree salvage: the session list did not read, so no owner was judged") {
		t.Errorf("stdout %q, stderr %q", out.String(), errb.String())
	}
	if strings.TrimSpace(calls()) != "session list --json" {
		t.Errorf("gc was called:\n%s", calls())
	}
}

// progress finds a busy pool seat with no write for three hours, reads its
// session bead in the city's store and its writes in both stores, and records
// it as one event.
func TestSessionProgressRecordsWhatItFound(t *testing.T) {
	calls := lookStub(t, lookCity{
		sessions: `{"sessions":[{"id":"lx-1","state":"active","agent_name":"tools/gc-toolkit.polecat-1","created_at":"2026-11-01T00:00:00Z","last_active":"` + agoStamp(10*time.Second) + `"}]}`,
		hq:       `[{"id":"lx-1","title":"s","status":"open","issue_type":"session","metadata":{"pool_managed":"true","last_woke_at":"` + agoStamp(5*time.Hour) + `"}}]`,
		rig:      `[{"id":"tk-1","title":"t","status":"in_progress","issue_type":"task","assignee":"lx-1","metadata":{"gc.session_id":"lx-1"}}]`,
		writes:   `[{"actor":"lx-1","newest":"` + agoStamp(4*time.Hour) + `"}]`,
	})
	var out, errb bytes.Buffer
	if code := Run([]string{"session", "progress"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	var rec session.Record
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil || len(rec.Stalled) != 1 || rec.Stalled[0].Bead != "tk-1" || !rec.Stalled[0].Wrote {
		t.Fatalf("stdout %q: %v", out.String(), err)
	}
	if !strings.HasSuffix(errb.String(), "lx-1 holding tk-1; recorded\n") {
		t.Errorf("stderr %q", errb.String())
	}
	got := calls()
	for _, want := range []string{
		"bd --db /city/rigs/tools/.beads list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --has-metadata-key gc.session_id\n",
		"bd --db /city/.beads list --id lx-1 --include-ephemeral",
		"bd --db /city/.beads sql --json SELECT actor",
		"bd --db /city/rigs/tools/.beads sql --json SELECT actor",
		"event emit gc-toolkit.seat-progress.stalled --json --actor gctk --message ",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("gc was not called with %q:\n%s", want, got)
		}
	}
}

// stuck finds a handoff past the bound in the queue of the rig's refinery,
// reads what holds it, and records it as one event; the HQ, which no refinery
// serves, is not read.
func TestRefineryStuckRecordsWhatItFound(t *testing.T) {
	calls := lookStub(t, lookCity{
		hq:  "[]",
		rig: `[{"id":"tk-1","title":"t","status":"open","issue_type":"task","assignee":"tools/gc-toolkit.refinery","updated_at":"` + agoStamp(6*time.Hour) + `","metadata":{"branch":"polecat/tk-1"}}]`,
	})
	var out, errb bytes.Buffer
	if code := Run([]string{"refinery", "stuck"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	var rec refinery.Record
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil || len(rec.Stuck) != 1 || rec.Stuck[0].Refinery != "tools/gc-toolkit.refinery" {
		t.Fatalf("stdout %q: %v", out.String(), err)
	}
	if !strings.HasSuffix(errb.String(), "tk-1 (tools/gc-toolkit.refinery); recorded\n") {
		t.Errorf("stderr %q", errb.String())
	}
	got := calls()
	if strings.Contains(got, "/city/.beads") {
		t.Errorf("the HQ's store was read:\n%s", got)
	}
	for _, want := range []string{"rig list --json\nagent list --json\n", "bd --db /city/rigs/tools/.beads blocked --json", "event emit gc-toolkit.refinery-queue.stuck --json --actor gctk"} {
		if !strings.Contains(got, want) {
			t.Errorf("gc was not called with %q:\n%s", want, got)
		}
	}
}

// An event gc does not submit fails the run, and the record still prints.
func TestALookWhoseEventIsNotRecordedFails(t *testing.T) {
	lookStub(t, lookCity{
		hq:   "[]",
		rig:  `[{"id":"tk-1","title":"t","status":"open","issue_type":"task","assignee":"tools/gc-toolkit.refinery","updated_at":"` + agoStamp(6*time.Hour) + `","metadata":{"branch":"polecat/tk-1"}}]`,
		emit: `{"ok":true,"submitted":false}`,
	})
	var out, errb bytes.Buffer
	if code := Run([]string{"refinery", "stuck"}, "", &out, &errb); code != 1 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if !strings.Contains(out.String(), `"bead":"tk-1"`) || !strings.Contains(errb.String(), "; not recorded\n") || !strings.Contains(errb.String(), "the look's event was not recorded") {
		t.Errorf("stdout %q, stderr %q", out.String(), errb.String())
	}
}
