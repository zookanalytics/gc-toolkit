// Package gcbdtest is the store acceptance harness: a scratch store the bd the
// city runs serves, on a dolt sql-server of its own, which the store adapter's
// acceptance test and a domain's store acceptance cases run against
// (docs/gctk-architecture.md, "The adapters"). That bd is built without cgo and
// opens no embedded store, so `bd init --proxied-server` starts the server. A
// store needs bd and dolt on PATH, takes a few seconds and starts servers, so
// its callers run only when GCTK_STORE_ACCEPTANCE=1 asks for them.
package gcbdtest

import (
	"bufio"
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
)

// Asked reports whether GCTK_STORE_ACCEPTANCE=1 asks for the store acceptance
// cases.
func Asked() bool { return os.Getenv("GCTK_STORE_ACCEPTANCE") == "1" }

// Store is a bd store in its own directory, on its own server.
type Store struct {
	t   testing.TB
	Dir string
	env []string
}

// New makes a scratch store whose beads carry prefix, and ends every process
// it started when the test ends. It fails the test when bd or dolt is not on
// PATH.
func New(t testing.TB, prefix string) *Store {
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
	s := &Store{t: t, Dir: dir, env: env}
	// The store's server and bd's proxy outlive the test and shrug off a
	// SIGTERM, so each process whose command line names the scratch directory
	// is killed, by its pid from the process table.
	t.Cleanup(func() { killUnder(dir) })
	s.Run("init", "--prefix", prefix, "--non-interactive", "--proxied-server")
	s.env = append(s.env, "BEADS_DIR="+s.DB())
	return s
}

// DB is the store's .beads directory, which a read pinned to it names.
func (s *Store) DB() string { return filepath.Join(s.Dir, ".beads") }

// Run runs bd in the store and returns what it prints, failing the test on a
// non-zero exit.
func (s *Store) Run(args ...string) string {
	s.t.Helper()
	out, err := s.Try(args...)
	if err != nil {
		s.t.Fatalf("bd %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return out
}

// Try runs bd in the store and returns its output and its error.
func (s *Store) Try(args ...string) (string, error) {
	cmd := exec.Command("bd", args...)
	cmd.Dir = s.Dir
	cmd.Env = s.env
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// Create files a bead titled title, with bd create's further args, and returns
// its id.
func (s *Store) Create(title string, args ...string) string {
	s.t.Helper()
	cmd := exec.Command("bd", append([]string{"create", title, "--json"}, args...)...)
	cmd.Dir, cmd.Env = s.Dir, s.env
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

// Edge adds an edge from id onto target, and with meta sets its metadata, then
// has bd mark id again. A waits-for edge's gate lives in the edge's metadata,
// which no bd verb writes, so it is set through `bd sql`, and closing and
// reopening the waiter is the write that makes bd mark it again.
func (s *Store) Edge(id, target, typ, meta string) {
	s.t.Helper()
	s.Run("dep", "add", id, target, "--type", typ)
	if meta == "" {
		return
	}
	s.Run("sql", "UPDATE dependencies SET metadata='"+meta+"' WHERE issue_id='"+id+"' AND depends_on_issue_id='"+target+"'")
	s.Run("close", id, "--force")
	s.Run("reopen", id)
}

// Listing is what `bd blocked --json` names for each bead.
func (s *Store) Listing() map[string][]string {
	s.t.Helper()
	var rows []struct {
		ID        string   `json:"id"`
		BlockedBy []string `json:"blocked_by"`
	}
	if err := json.Unmarshal([]byte(s.Run("blocked", "--json")), &rows); err != nil {
		s.t.Fatal(err)
	}
	out := map[string][]string{}
	for _, r := range rows {
		out[r.ID] = r.BlockedBy
	}
	return out
}

// ParentRows is what bd's blocked listing reads for a bead's parents, in the
// order it reads them: its own query, whose last row names the parent the
// listing gives (loadParentIDsForChildrenInTx in
// internal/storage/issueops/blocked.go, beads 7ef2fd05e).
func (s *Store) ParentRows(id string) []string {
	s.t.Helper()
	var rows []struct {
		ID string `json:"depends_on_id"`
	}
	query := "SELECT issue_id, COALESCE(depends_on_issue_id, depends_on_wisp_id, depends_on_external) AS depends_on_id FROM dependencies WHERE issue_id = '" + id + "' AND type = 'parent-child'"
	if err := json.Unmarshal([]byte(s.Run("sql", "--json", query)), &rows); err != nil {
		s.t.Fatal(err)
	}
	var ids []string
	for _, r := range rows {
		ids = append(ids, r.ID)
	}
	return ids
}

// Ready is the ids `bd ready --json` offers.
func (s *Store) Ready() []string {
	s.t.Helper()
	var rows []struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal([]byte(s.Run("ready", "--json")), &rows); err != nil {
		s.t.Fatal(err)
	}
	var ids []string
	for _, r := range rows {
		ids = append(ids, r.ID)
	}
	return ids
}

// Enter points this test process at the store, through the same gc bd seam
// the city's reads take: a gc on PATH that hands `gc bd` to bd and answers
// any other call by the shell case arms more holds, each a `<pattern>) ... ;;`
// on gc's first argument, with every GC_ and BEADS_ variable cleared, BEADS_DIR
// naming the store, and the store's directory the working directory.
func (s *Store) Enter(t *testing.T, more string) {
	t.Helper()
	shim := t.TempDir()
	script := "#!/bin/sh\ncase \"$1\" in\nbd) shift; exec bd \"$@\" ;;\n" + more + "\nesac\necho \"gc shim: no answer for $*\" >&2\nexit 2\n"
	if err := os.WriteFile(filepath.Join(shim, "gc"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", shim+string(os.PathListSeparator)+os.Getenv("PATH"))
	for _, kv := range os.Environ() {
		if name, _, _ := strings.Cut(kv, "="); strings.HasPrefix(name, "BEADS_") || strings.HasPrefix(name, "GC_") {
			t.Setenv(name, "")
			os.Unsetenv(name)
		}
	}
	t.Setenv("BEADS_DIR", s.DB())
	t.Chdir(s.Dir)
}

// killUnder kills each process whose command line names dir.
func killUnder(dir string) {
	out, err := exec.Command("ps", "-axo", "pid=,command=").Output()
	if err != nil {
		return
	}
	self := os.Getpid()
	sc := bufio.NewScanner(bytes.NewReader(out))
	for sc.Scan() {
		pid, cmd, ok := strings.Cut(strings.TrimSpace(sc.Text()), " ")
		if !ok || !strings.Contains(cmd, dir) {
			continue
		}
		if n, err := strconv.Atoi(pid); err == nil && n != self {
			_ = syscall.Kill(n, syscall.SIGKILL)
		}
	}
}
