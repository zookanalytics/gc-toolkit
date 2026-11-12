package gcbd

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// findStub puts a `gc` on PATH that answers each `bd list` with $STUB_LIST and
// exit $STUB_LIST_RC, and logs each call's argv to the file it returns.
func findStub(t *testing.T, list string) string {
	t.Helper()
	dir := t.TempDir()
	log := filepath.Join(dir, "calls")
	stub := `#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
case "$1 $2" in
"bd list") printf '%s\n' "$STUB_LIST"; exit "${STUB_LIST_RC:-0}" ;;
esac
echo "stub gc: no answer for $*" >&2
exit 2
`
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_LOG", log)
	t.Setenv("STUB_LIST", list)
	return log
}

// findCalls reads the log findStub returns: each call's argv, one per line, and
// none when nothing called the stub.
func findCalls(t *testing.T, log string) []string {
	t.Helper()
	raw, err := os.ReadFile(log)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		t.Fatal(err)
	}
	return strings.Split(strings.TrimRight(string(raw), "\n"), "\n")
}

// Each query is one `gc bd list` that reads every type a listing hides unless
// asked, wisps, gates, infrastructure beads and templates, with no row limit,
// and reads closed beads only when asked.
func TestFindAsksTheListing(t *testing.T) {
	for _, tc := range []struct {
		name string
		q    Query
		want string
	}{
		{"the beads that carry a key", Query{HasKey: "gc.input_convoy_id"},
			"bd list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --has-metadata-key gc.input_convoy_id"},
		{"the beads whose key holds a value", Query{Key: "gc.root_bead_id", Value: "tk-root"},
			"bd list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --metadata-field gc.root_bead_id=tk-root"},
		{"the beads named, closed ones included", Query{IDs: []string{"b-2", "b-1", "b-2"}, Closed: true},
			"bd list --id b-1,b-2 --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --all"},
		{"every live bead", Query{Every: true},
			"bd list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0"},
		{"the beads under a parent, closed ones included", Query{Parent: "tk-e", Closed: true},
			"bd list --include-ephemeral --include-gates --include-infra --include-templates --json --limit 0 --all --parent tk-e"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			log := findStub(t, `[]`)
			if _, err := (&Client{bin: "gc"}).Find(tc.q); err != nil {
				t.Fatal(err)
			}
			if got := findCalls(t, log); !slices.Equal(got, []string{tc.want}) {
				t.Errorf("calls = %q, want %q", got, tc.want)
			}
		})
	}
}

// Many ids are read in batches, so no read builds an argument the store
// refuses, and the rows of every batch come back together.
func TestFindReadsManyIDsInBatches(t *testing.T) {
	var ids []string
	for i := range idBatch + 1 {
		ids = append(ids, fmt.Sprintf("b-%03d", i))
	}
	log := findStub(t, `[{"id":"b-000","status":"open"}]`)
	rows, err := (&Client{bin: "gc"}).Find(Query{IDs: ids})
	if err != nil {
		t.Fatal(err)
	}
	got := findCalls(t, log)
	if len(got) != 2 || len(rows) != 2 {
		t.Fatalf("%d reads returned %d rows; want 2 reads, one row each", len(got), len(rows))
	}
	if n := strings.Count(strings.Fields(got[0])[3], ","); n != idBatch-1 {
		t.Errorf("the first read names %d ids, want %d", n+1, idBatch)
	}
}

// A listing row's edges name the far bead and the edge's type, and carry no
// status of the far bead.
func TestFindReadsTheListingsEdges(t *testing.T) {
	findStub(t, `[{"id":"cv","status":"open","issue_type":"convoy","dependencies":[{"issue_id":"cv","depends_on_id":"w-1","type":"tracks","metadata":"{}"}]}]`)
	rows, err := (&Client{bin: "gc"}).Find(Query{IDs: []string{"cv"}})
	if err != nil || len(rows) != 1 {
		t.Fatalf("Find = %v, %v", rows, err)
	}
	edges, err := rows[0].Edges()
	if err != nil {
		t.Fatal(err)
	}
	if want := []Edge{{Type: "tracks", ID: "w-1"}}; !slices.Equal(edges, want) {
		t.Errorf("edges = %+v, want %+v", edges, want)
	}
	if rows[0].IssueTypeString() != "convoy" {
		t.Errorf("issue type = %q", rows[0].IssueTypeString())
	}
}

// A listing row's own fields read through their accessors: a whole-number
// priority, the labels that are strings, and the description, creation and
// close times as text. A row that carries none of them reads empty.
func TestFindReadsTheRowsFields(t *testing.T) {
	findStub(t, `[{"id":"w-1","status":"closed","priority":2,"labels":["hold:mayor",7,"b"],"description":"the whole text","created_at":"2026-11-01T00:00:00Z","closed_at":"2026-11-02T00:00:00Z"},{"id":"w-2","priority":1.5},{"id":"w-3","ephemeral":true},{"id":"w-4","no_history":true,"is_template":true}]`)
	rows, err := (&Client{bin: "gc"}).Find(Query{Every: true, Closed: true})
	if err != nil || len(rows) != 4 {
		t.Fatalf("Find = %v, %v", rows, err)
	}
	b := rows[0]
	if b.PriorityInt() != 2 || !slices.Equal(b.LabelStrings(), []string{"hold:mayor", "b"}) || b.DescriptionString() != "the whole text" ||
		b.CreatedAtString() != "2026-11-01T00:00:00Z" || b.ClosedAtString() != "2026-11-02T00:00:00Z" {
		t.Errorf("w-1 reads priority %d, labels %q, description %q, created %q, closed %q", b.PriorityInt(), b.LabelStrings(),
			b.DescriptionString(), b.CreatedAtString(), b.ClosedAtString())
	}
	e := rows[1]
	if e.PriorityInt() != 0 || e.LabelStrings() != nil || e.DescriptionString() != "" || e.CreatedAtString() != "" || e.ClosedAtString() != "" {
		t.Errorf("w-2 reads priority %d, labels %q, description %q, created %q, closed %q", e.PriorityInt(), e.LabelStrings(),
			e.DescriptionString(), e.CreatedAtString(), e.ClosedAtString())
	}
	if b.InEphemeralPlane() || b.Template() || !rows[2].InEphemeralPlane() || rows[2].Template() ||
		!rows[3].InEphemeralPlane() || !rows[3].Template() {
		t.Errorf("the ephemeral plane reads %v %v %v, templates %v %v %v", b.InEphemeralPlane(), rows[2].InEphemeralPlane(),
			rows[3].InEphemeralPlane(), b.Template(), rows[2].Template(), rows[3].Template())
	}
}

// A read that fails, or a reply that is not one array of rows with ids, is a
// *ReadError, and so is a query that selects no beads, which reads nothing.
func TestFindThatFailsIsAReadError(t *testing.T) {
	for _, tc := range []struct{ name, list, rc string }{
		{"the listing exits non-zero", `{"error":"dolt timeout"}`, "1"},
		{"the listing is not an array", `{"error":"dolt timeout"}`, "0"},
		{"a row has no id", `[{"status":"open"}]`, "0"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			findStub(t, tc.list)
			t.Setenv("STUB_LIST_RC", tc.rc)
			rows, err := (&Client{bin: "gc"}).Find(Query{HasKey: "k"})
			var re *ReadError
			if !errors.As(err, &re) || rows != nil {
				t.Fatalf("Find = %v, %v; want a *ReadError", rows, err)
			}
		})
	}
	log := findStub(t, `[]`)
	var re *ReadError
	if _, err := (&Client{bin: "gc"}).Find(Query{Closed: true}); !errors.As(err, &re) {
		t.Errorf("a query that selects nothing = %v, want a *ReadError", err)
	}
	if _, err := os.Stat(log); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("a query that selects nothing ran a read")
	}
}

// A bead with a waits-for edge of its own gets the waits-for error, which names
// beside its spawners the bead's own blocks waits the listing names live, and
// never the parent the listing can name in their place.
func TestTheWaitsForErrorNamesTheListedBlocks(t *testing.T) {
	b := &Bead{ID: "w", Dependencies: []any{
		map[string]any{"id": "spawner", "dependency_type": "waits-for", "status": "open"},
		map[string]any{"id": "blocker", "dependency_type": "blocks", "status": "open"},
		map[string]any{"id": "parent", "dependency_type": "parent-child", "status": "open"},
	}}
	for _, tc := range []struct {
		name   string
		listed []string
		blocks []string
	}{
		{"the listing names its blocker", []string{"spawner", "blocker"}, []string{"blocker"}},
		{"the listing names its parent", []string{"parent"}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			set := NewBlockedSet(map[string][]string{"w": tc.listed}, []string{"w"})
			_, err := set.Answer(b)
			var wf *WaitsForError
			if !errors.As(err, &wf) || !slices.Equal(wf.Spawners, []string{"spawner"}) || !slices.Equal(wf.Blocks, tc.blocks) {
				t.Errorf("Answer = %v; want the waits-for error naming spawner and blocks %v", err, tc.blocks)
			}
		})
	}
}

// TestAStoppedCallEndsEveryProcessItStarted reads through a client with a
// context over a gc that does what `gc bd` does: it starts a child that holds
// the call's output, as gc runs bd, and waits on it. Once the context is done
// the read returns the context's error without waiting out the child, and the
// call's whole process group, the child among it, is gone.
func TestAStoppedCallEndsEveryProcessItStarted(t *testing.T) {
	dir := t.TempDir()
	group := filepath.Join(dir, "group")
	stub := "#!/bin/sh\nsleep 30 &\necho $$ > \"$STUB_GROUP\"\nwait\n"
	if err := os.WriteFile(filepath.Join(dir, "gc"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("STUB_GROUP", group)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		_, err := (&Client{bin: "gc"}).WithContext(ctx).Find(Query{Every: true})
		done <- err
	}()
	pid := stubGroup(t, group)
	cancel()
	stop := time.Now()
	select {
	case err := <-done:
		// A stop that killed gc alone would leave the child holding the
		// call's output, and the read would wait out stopGrace for it.
		if took := time.Since(stop); took >= stopGrace {
			t.Errorf("the read returned %s after the stop, as late as a wait on a child left running", took)
		}
		var re *ReadError
		if !errors.As(err, &re) || !errors.Is(err, context.Canceled) {
			t.Errorf("Find = %v, want a *ReadError carrying the context's error", err)
		}
	case <-time.After(stopGrace + 10*time.Second):
		_ = syscall.Kill(-pid, syscall.SIGKILL)
		t.Fatal("the read did not return once its context was done")
	}
	groupGone(t, pid)
}

// stubGroup is the process group a stub gc wrote to path, which it leads, as a
// call the client stops runs in a group of its own.
func stubGroup(t *testing.T, path string) int {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		raw, _ := os.ReadFile(path)
		if pid, err := strconv.Atoi(strings.TrimSpace(string(raw))); err == nil && pid > 0 {
			return pid
		}
		if time.Now().After(deadline) {
			t.Fatal("the stub gc never started")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// groupGone waits for every process in group pid to be gone. A member killed
// outright stays in the group until it is reaped.
func groupGone(t *testing.T, pid int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(-pid, 0) == nil {
		if time.Now().After(deadline) {
			_ = syscall.Kill(-pid, syscall.SIGKILL)
			t.Fatalf("the call's process group %d outlived the stop", pid)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
