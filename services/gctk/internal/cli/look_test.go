package cli

import (
	"bytes"
	"encoding/json"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd"
	"github.com/zookanalytics/gc-toolkit/services/gctk/refinery"
	"github.com/zookanalytics/gc-toolkit/services/gctk/session"
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
  "rig list --json") cat '` + answer("rigs", `{"rigs":[{"name":"city","path":"/city","prefix":"hq","hq":true},{"name":"tools","path":"/city/rigs/tools","prefix":"tk","hq":false}]}`) + `' ;;
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

// progress finds a busy pool seat with no write for three hours, reads its
// session bead in the city's store and its writes in both stores, and records
// it as one event.
func TestSessionProgressRecordsWhatItFound(t *testing.T) {
	calls := lookStub(t, lookCity{
		sessions: `{"sessions":[{"id":"hq-1","state":"active","agent_name":"tools/gc-toolkit.polecat-1","created_at":"2026-11-01T00:00:00Z","last_active":"` + agoStamp(10*time.Second) + `"}]}`,
		hq:       `[{"id":"hq-1","title":"s","status":"open","issue_type":"session","metadata":{"pool_managed":"true","last_woke_at":"` + agoStamp(5*time.Hour) + `"}}]`,
		rig:      `[{"id":"tk-1","title":"t","status":"in_progress","issue_type":"task","assignee":"hq-1","metadata":{"gc.session_id":"hq-1"}}]`,
		writes:   `[{"actor":"hq-1","newest":"` + agoStamp(4*time.Hour) + `"}]`,
	})
	var out, errb bytes.Buffer
	if code := Run([]string{"session", "progress"}, "", &out, &errb); code != 0 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	var rec session.Record
	if err := json.Unmarshal(out.Bytes(), &rec); err != nil || len(rec.Stalled) != 1 || rec.Stalled[0].Bead != "tk-1" || !rec.Stalled[0].Wrote {
		t.Fatalf("stdout %q: %v", out.String(), err)
	}
	if !strings.HasSuffix(errb.String(), "hq-1 holding tk-1; recorded\n") {
		t.Errorf("stderr %q", errb.String())
	}
	got := calls()
	for _, want := range []string{
		"bd --db /city/rigs/tools/.beads list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --has-metadata-key gc.session_id\n",
		"bd --db /city/.beads list --id hq-1 --include-ephemeral",
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
	for _, want := range []string{
		"rig list --json\nagent list --json\n",
		"bd --db /city/rigs/tools/.beads list --json --limit 0 --assignee tools/gc-toolkit.refinery --status open\n",
		"bd --db /city/rigs/tools/.beads blocked --json",
		"event emit gc-toolkit.refinery-queue.stuck --json --actor gctk",
	} {
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

// A session list that does not read fails the run with no record, and nothing
// else is read.
func TestALookWhoseSessionListDoesNotReadFails(t *testing.T) {
	calls := lookStub(t, lookCity{sessions: `not json`, hq: "[]", rig: "[]"})
	var out, errb bytes.Buffer
	if code := Run([]string{"session", "progress"}, "", &out, &errb); code != 1 {
		t.Fatalf("exit %d, stderr %q", code, errb.String())
	}
	if out.Len() != 0 || !strings.Contains(errb.String(), "gctk session progress: the session list did not read, so no seat was judged") {
		t.Errorf("stdout %q, stderr %q", out.String(), errb.String())
	}
	if strings.TrimSpace(calls()) != "session list --json" {
		t.Errorf("gc was called:\n%s", calls())
	}
}

// stuckStoreStub puts a gc on PATH that answers the looks' session, rig and
// agent lists, and runs every store call in the group it leads with a child
// started under it, appending its pid to the file it returns and waiting. Each
// call it takes is logged to calls.
func stuckStoreStub(t *testing.T) (groups, calls string) {
	t.Helper()
	bin := t.TempDir()
	groups, calls = filepath.Join(bin, "groups"), filepath.Join(bin, "calls")
	stub := `#!/bin/sh
echo "$*" >> '` + calls + `'
case "$*" in
  "session list --json") echo '{"sessions":[{"id":"hq-1","state":"active","agent_name":"tools/gc-toolkit.polecat-1","created_at":"2026-11-01T00:00:00Z","last_active":"` + agoStamp(10*time.Second) + `"}]}' ;;
  "rig list --json") echo '{"rigs":[{"name":"city","path":"/city","prefix":"hq","hq":true},{"name":"tools","path":"/city/rigs/tools","prefix":"tk","hq":false}]}' ;;
  "agent list --json") echo '{"agents":[{"name":"refinery","qualified_name":"tools/gc-toolkit.refinery","dir":"tools"}]}' ;;
  "bd "*) sleep 30 & echo $$ >> '` + groups + `'; wait ;;
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
	t.Cleanup(func() {
		raw, _ := os.ReadFile(groups)
		for _, f := range strings.Fields(string(raw)) {
			if pid, err := strconv.Atoi(f); err == nil && pid > 0 {
				_ = syscall.Kill(-pid, syscall.SIGKILL)
			}
		}
	})
	return groups, calls
}

// stuckGroups waits for n store calls to have started and returns the group
// each leads.
func stuckGroups(t *testing.T, groups string, n int) []int {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		raw, _ := os.ReadFile(groups)
		var pids []int
		for _, f := range strings.Fields(string(raw)) {
			if pid, err := strconv.Atoi(f); err == nil && pid > 0 {
				pids = append(pids, pid)
			}
		}
		if len(pids) >= n {
			return pids
		}
		if time.Now().After(deadline) {
			t.Fatalf("%d of %d store calls started", len(pids), n)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// storeGroupGone waits for every process in group pid to be gone. A member
// killed outright stays in the group until it is reaped.
func storeGroupGone(t *testing.T, pid int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(deadline) {
			t.Fatalf("the store call's process group %d outlived the stop", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A store read leads a process group of its own, so the SIGTERM or the Ctrl-C
// that reaches this process's group does not reach it. A look stopped during
// one ends that read's whole group, the child gc started among it, starts no
// other call, prints nothing, and exits with 128 plus the signal.
func TestALookStoppedDuringAStoreReadEndsItAndWritesNothing(t *testing.T) {
	for _, look := range [][]string{{"session", "progress"}, {"refinery", "stuck"}} {
		for _, sig := range []syscall.Signal{syscall.SIGTERM, syscall.SIGINT} {
			t.Run(strings.Join(look, " ")+"/"+sig.String(), func(t *testing.T) {
				groups, calls := stuckStoreStub(t)
				// The test's own handler, so a look that does not take the signal
				// fails this test rather than ending the test binary.
				held := make(chan os.Signal, 1)
				signal.Notify(held, sig)
				t.Cleanup(func() { signal.Stop(held) })

				var out, errb bytes.Buffer
				code := make(chan int, 1)
				go func() { code <- Run(look, "", &out, &errb) }()
				pid := stuckGroups(t, groups, 1)[0]
				if err := syscall.Kill(os.Getpid(), sig); err != nil {
					t.Fatal(err)
				}
				select {
				case got := <-code:
					if want := 128 + int(sig); got != want {
						t.Errorf("a look stopped by %v exited %d, want %d", sig, got, want)
					}
				case <-time.After(10 * time.Second):
					t.Fatalf("the look did not end on the %v this process received", sig)
				}
				if out.Len() != 0 || errb.Len() != 0 {
					t.Errorf("a stopped look wrote stdout %q, stderr %q", out.String(), errb.String())
				}
				storeGroupGone(t, pid)
				raw, _ := os.ReadFile(calls)
				if n := strings.Count(string(raw), "\nbd "); n != 1 {
					t.Errorf("the look made %d store calls, want only the one the stop ended:\n%s", n, raw)
				}
			})
		}
	}
}

// Store reads that run at once under one look's context all end on its one
// stop before the look's release returns, and none of them ends this process.
func TestAStopEndsEveryStoreReadUnderTheLook(t *testing.T) {
	groups, _ := stuckStoreStub(t)
	held := make(chan os.Signal, 1)
	signal.Notify(held, syscall.SIGTERM)
	t.Cleanup(func() { signal.Stop(held) })

	ctx, release := stopOnSignal()
	var reads sync.WaitGroup
	for _, db := range []string{"/city/.beads", "/city/rigs/tools/.beads"} {
		reads.Add(1)
		go func() {
			defer reads.Done()
			_, _ = gcbd.New().In(db).WithContext(ctx).Find(gcbd.Query{Every: true})
		}()
	}
	pids := stuckGroups(t, groups, 2)
	if err := syscall.Kill(os.Getpid(), syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	ended := make(chan struct{})
	go func() { reads.Wait(); close(ended) }()
	select {
	case <-ended:
	case <-time.After(10 * time.Second):
		t.Fatal("the reads did not end on the SIGTERM this process received")
	}
	if sig := release(); sig != syscall.SIGTERM {
		t.Errorf("release returned %v, want %v", sig, syscall.SIGTERM)
	}
	for _, pid := range pids {
		storeGroupGone(t, pid)
	}
}
