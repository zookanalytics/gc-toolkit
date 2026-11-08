package gcbd

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// The adapter's acceptance test runs the bd the city runs against a scratch
// store, so it pins the answer that bd gives for each kind of wait, each gate
// included, and the beads it marks blocked (docs/gctk-architecture.md, "The
// adapters"). That bd is built without cgo and opens no embedded store, so the
// store runs on a dolt sql-server of its own, which `bd init --proxied-server`
// starts. It needs bd and dolt on PATH, takes a few seconds and starts servers,
// so it runs only when GCTK_STORE_ACCEPTANCE=1 asks for it:
//
//	GCTK_STORE_ACCEPTANCE=1 go test ./internal/gcbd -run TestStoreAcceptance -v
//
// Each case builds its beads, then compares the adapter's answer with what the
// store does. A waits-for edge's gate lives in the edge's metadata, which no bd
// verb writes, so a case sets it through `bd sql` and then closes and reopens
// the waiter, the write that makes bd mark the waiter again.

// scratchStore is a bd store in its own directory, on its own server.
type scratchStore struct {
	t   *testing.T
	dir string
	env []string
}

func newScratchStore(t *testing.T) *scratchStore {
	t.Helper()
	for _, tool := range []string{"bd", "dolt"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Fatalf("GCTK_STORE_ACCEPTANCE asks for the store acceptance test, and %s is not on PATH", tool)
		}
	}
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	var env []string
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, "BEADS_") && !strings.HasPrefix(kv, "GC_") {
			env = append(env, kv)
		}
	}
	s := &scratchStore{t: t, dir: dir, env: env}
	t.Cleanup(func() {
		// The store's server and bd's proxy outlive the test and shrug off a
		// SIGTERM, so each process started from the scratch directory is killed.
		_ = exec.Command("pkill", "-KILL", "-f", dir).Run()
	})
	s.run("init", "--prefix", "pb", "--non-interactive", "--proxied-server")
	s.env = append(s.env, "BEADS_DIR="+filepath.Join(dir, ".beads"))
	return s
}

// run runs bd in the store and returns what it prints, failing the test on a
// non-zero exit.
func (s *scratchStore) run(args ...string) string {
	s.t.Helper()
	out, err := s.try(args...)
	if err != nil {
		s.t.Fatalf("bd %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return out
}

// try runs bd in the store and returns its output and its error.
func (s *scratchStore) try(args ...string) (string, error) {
	cmd := exec.Command("bd", args...)
	cmd.Dir = s.dir
	cmd.Env = s.env
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func (s *scratchStore) create(title string) string {
	s.t.Helper()
	cmd := exec.Command("bd", "create", title, "--json")
	cmd.Dir, cmd.Env = s.dir, s.env
	out, err := cmd.Output()
	if err != nil {
		s.t.Fatalf("bd create %s: %v", title, err)
	}
	var row struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal(out, &row); err != nil || row.ID == "" {
		var rows []struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(out, &rows); err != nil || len(rows) == 0 {
			s.t.Fatalf("bd create %s answered %q", title, out)
		}
		row.ID = rows[0].ID
	}
	return row.ID
}

// edge adds an edge from id onto target, and with meta sets its metadata, then
// has bd mark id again.
func (s *scratchStore) edge(id, target, typ, meta string) {
	s.t.Helper()
	s.run("dep", "add", id, target, "--type", typ)
	if meta == "" {
		return
	}
	s.run("sql", "UPDATE dependencies SET metadata='"+meta+"' WHERE issue_id='"+id+"' AND depends_on_issue_id='"+target+"'")
	s.run("close", id, "--force")
	s.run("reopen", id)
}

// listing is what `bd blocked --json` names for each bead.
func (s *scratchStore) listing() map[string][]string {
	s.t.Helper()
	var rows []struct {
		ID        string   `json:"id"`
		BlockedBy []string `json:"blocked_by"`
	}
	if err := json.Unmarshal([]byte(s.run("blocked", "--json")), &rows); err != nil {
		s.t.Fatal(err)
	}
	out := map[string][]string{}
	for _, r := range rows {
		out[r.ID] = r.BlockedBy
	}
	return out
}

func (s *scratchStore) ready() []string {
	s.t.Helper()
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal([]byte(s.run("ready", "--json")), &rows); err != nil {
		s.t.Fatal(err)
	}
	var ids []string
	for _, r := range rows {
		ids = append(ids, r.ID)
	}
	return ids
}

func TestStoreAcceptance(t *testing.T) {
	if os.Getenv("GCTK_STORE_ACCEPTANCE") != "1" {
		t.Skip("the store acceptance test runs the city's bd on a scratch store; GCTK_STORE_ACCEPTANCE=1 runs it")
	}
	s := newScratchStore(t)

	// A bead with a blocks edge onto an open bead.
	own, blocker := s.create("own"), s.create("blocker")
	s.edge(own, blocker, EdgeBlocks, "")
	// A bead held only through its blocked parent.
	parent, parentBlocker, child := s.create("parent"), s.create("parent's blocker"), s.create("child")
	s.edge(parent, parentBlocker, EdgeBlocks, "")
	s.edge(child, parent, EdgeParentChild, "")
	// A parentless bead on an all-children gate whose spawner closed and then
	// gained a child that is still open.
	spawner, waiter := s.create("spawner"), s.create("waiter")
	s.edge(waiter, spawner, EdgeWaitsFor, "")
	s.run("close", spawner)
	s.edge(s.create("spawner's child"), spawner, EdgeParentChild, "")
	// The same gate on a bead whose parent is not blocked.
	openParent, parented := s.create("open parent"), s.create("parented waiter")
	s.edge(parented, openParent, EdgeParentChild, "")
	s.edge(parented, spawner, EdgeWaitsFor, "")
	// An any-children gate one closed child has opened, on a bead held only
	// through its blocked parent.
	anySpawner, closedChild, openChild := s.create("any spawner"), s.create("closed child"), s.create("open child")
	s.edge(closedChild, anySpawner, EdgeParentChild, "")
	s.edge(openChild, anySpawner, EdgeParentChild, "")
	s.run("close", closedChild)
	anyWaiter := s.create("any waiter")
	s.edge(anyWaiter, parent, EdgeParentChild, "")
	s.edge(anyWaiter, anySpawner, EdgeWaitsFor, `{"gate":"any-children"}`)
	// An also_blocks edge on an open spawner with no open child.
	alsoSpawner, alsoWaiter := s.create("also spawner"), s.create("also waiter")
	s.edge(alsoWaiter, alsoSpawner, EdgeWaitsFor, `{"also_blocks":"true"}`)

	// What the store itself answers.
	listed, ready := s.listing(), s.ready()
	for _, tc := range []struct {
		name, id string
		listed   []string // nil: the listing leaves the bead out
	}{
		{"a blocks edge names its blocker", own, []string{blocker}},
		{"a bead held through its parent names the parent", child, []string{parent}},
		{"a parentless waiter on a closed spawner's gate is left out", waiter, nil},
		{"the same gate under an open parent names that parent", parented, []string{openParent}},
		{"an opened any-children gate under a blocked parent names the open spawner", anyWaiter, []string{anySpawner}},
		{"an also_blocks edge names its open spawner", alsoWaiter, []string{alsoSpawner}},
	} {
		if got, ok := listed[tc.id]; !slices.Equal(got, tc.listed) || ok != (tc.listed != nil) {
			t.Errorf("bd blocked: %s: got %v (listed %v), want %v", tc.name, got, ok, tc.listed)
		}
		if slices.Contains(ready, tc.id) {
			t.Errorf("bd ready offers %s (%s)", tc.id, tc.name)
		}
	}

	// What the adapter answers, through the same gc bd seam the city's reads
	// take: a gc on PATH that hands bd its arguments.
	shim := t.TempDir()
	if err := os.WriteFile(filepath.Join(shim, "gc"), []byte("#!/bin/sh\n[ \"$1\" = bd ] || exit 2\nshift\nexec bd \"$@\"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shim+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, kv := range os.Environ() {
		if name, _, _ := strings.Cut(kv, "="); strings.HasPrefix(name, "BEADS_") || strings.HasPrefix(name, "GC_") {
			t.Setenv(name, "")
			os.Unsetenv(name)
		}
	}
	t.Setenv("BEADS_DIR", filepath.Join(s.dir, ".beads"))
	t.Chdir(s.dir)
	c := &Client{bin: "gc"}
	ids := []string{own, child, waiter, parented, anyWaiter, alsoWaiter, parent}
	rows, err := c.Rows(ids)
	if err != nil {
		t.Fatal(err)
	}
	set, err := c.Blocked()
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]*Bead{}
	for i := range rows {
		byID[rows[i].ID] = &rows[i]
	}
	if b, err := set.Answer(byID[own]); err != nil || !slices.Equal(b.On, []string{blocker}) {
		t.Errorf("adapter: a blocks edge = %+v, %v; want blocked on %s", b, err, blocker)
	}
	if b, err := set.Answer(byID[child]); err != nil || b.Through != parent {
		t.Errorf("adapter: held through a parent = %+v, %v; want held through %s", b, err, parent)
	}
	for _, id := range []string{waiter, parented, anyWaiter, alsoWaiter} {
		_, err := set.Answer(byID[id])
		var wf *WaitsForError
		var re *ReadError
		if !errors.As(err, &wf) || errors.As(err, &re) {
			t.Errorf("adapter: %s = %v; want the waits-for error and not a read error", id, err)
		}
	}
	// The marks read names every bead a case holds, the one the listing leaves
	// out among them.
	for _, id := range ids {
		if !set.marked[id] {
			t.Errorf("the marks read does not name %s", id)
		}
	}
	// bd's show leaves out a bead the store does not hold and exits 0 beside one
	// it holds, and fails when it holds none named, so the adapter's row read
	// fails either way, naming the bead in the first case and bd's error in the
	// second.
	if out, err := s.try("show", own, "pb-gone", "--json"); err != nil || strings.Contains(out, `"id": "pb-gone"`) {
		t.Errorf("bd show of a held bead beside one it does not hold = %v: %s; want exit 0 and no row for pb-gone", err, out)
	}
	var re *ReadError
	if _, err := c.Rows([]string{own, "pb-gone"}); !errors.As(err, &re) || re.ID != "pb-gone" {
		t.Errorf("adapter: rows with a bead the store does not hold = %v; want a read error naming pb-gone", err)
	}
	if _, err := c.Rows([]string{"pb-gone"}); !errors.As(err, &re) || !strings.Contains(err.Error(), "no issues found") {
		t.Errorf("adapter: rows of only a bead the store does not hold = %v; want a read error carrying bd's error", err)
	}

	// bd's close rule: a blocker of a bead's own refuses the close, and a bead
	// held only through its parent closes.
	if _, err := s.try("close", own); err == nil {
		t.Errorf("bd closed %s, which an open blocker of its own holds", own)
	}
	if out, err := s.try("close", child); err != nil {
		t.Errorf("bd refused to close %s, held only through its parent: %s", child, out)
	}
}
