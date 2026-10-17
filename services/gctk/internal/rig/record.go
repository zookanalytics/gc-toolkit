// Package rig carries the actions gctk takes on a rig. The first are its
// checks: a check runs the command its caller passes and keeps the record of
// what the run found, keyed to the commit it ran at.
//
// A record certifies a commit, not a session's word: it is written by the
// process that ran the command and captured its exit status, and only for a
// clean checkout, so the commit names exactly the tree that was checked. It
// lives under the rig clone's git common directory, which every worktree of
// the clone shares, which outlives any one worktree, and which needs no store
// or service to read. A re-clone loses the records, and the cost of that is one
// run of each check.
package rig

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
)

// The checks whose result is a property of a commit. setup and build run with
// no record: setup leaves environment state behind, and a build makes itself
// current.
const (
	CheckTest      = "test"
	CheckLint      = "lint"
	CheckTypecheck = "typecheck"
)

// A record's result.
const (
	ResultPass = "pass"
	ResultFail = "fail"
)

// A record's scope: what the run covered, as its caller declared it. Only test
// has two commands to tell apart. A lint or typecheck run has one, and records
// no scope.
const (
	// ScopeFull is a test run of the whole suite. Its result is a property of
	// the tree, so its pass also answers for every commit with the same tree.
	ScopeFull = "full"
	// ScopeAffected is a test run of the subset the commit's diff selects. The
	// command works out that diff itself, so its result answers only for the
	// commit it ran at.
	ScopeAffected = "affected"
	// ScopeNone is a pass that ran nothing, recorded when the caller declares
	// that the rig declares no command for the check.
	ScopeNone = "none"
)

// dirName is the record directory under the git common directory, beside the
// refinery's gc-refinery-gate and gc-refinery-prep.
const dirName = "gc-rig-checks"

// Record is one check's result at one commit, written by the run itself.
type Record struct {
	Check  string `json:"check"`
	Result string `json:"result"`
	Scope  string `json:"scope,omitempty"`
	Commit string `json:"commit"`
	Tree   string `json:"tree"`
	// ExitCode is the command's own exit status: 0 for a pass, and for a fail
	// the status the command exited with.
	ExitCode   int    `json:"exit_code"`
	DurationMS int64  `json:"duration_ms"`
	Runner     string `json:"runner"`
	RecordedAt string `json:"recorded_at"`
	// Command is the command line the caller passed, empty for a run of
	// nothing.
	Command string `json:"command"`
}

// Where the record that answers for a commit was found.
const (
	// FromCommit is the commit's own record.
	FromCommit = "commit"
	// FromTree is a full-suite test pass recorded at another commit whose tree
	// is the same.
	FromTree = "tree"
)

// Found is what a lookup read for one commit.
type Found struct {
	// Commit is the commit's own record, nil when it has none.
	Commit *Record
	// Tree is the full-suite test pass the commit's tree answers with, nil when
	// there is none. Only a test lookup reads it.
	Tree *Record
	// Ignored lists record files that exist but did not parse as a record for
	// the commit or tree they are filed under. A lookup reads each one as
	// absent, so a damaged file costs a run and never certifies anything.
	Ignored []string
}

// Answer returns the record that answers a call declaring scope and command,
// and where it was found, or nil when no record answers. A record answers only
// the run it records: the same command line, byte for byte, and the same
// scope. The commit's own record is read first. A full-suite test pass recorded
// at another commit with the same tree answers a call that declares the full
// suite with the same command.
func (f Found) Answer(scope, command string) (*Record, string) {
	if r := f.Commit; r != nil && r.Scope == scope && r.Command == command {
		return r, FromCommit
	}
	if r := f.Tree; r != nil && scope == ScopeFull && r.Command == command {
		return r, FromTree
	}
	return nil, ""
}

// Recorded returns what is recorded for the commit whatever run made it, and
// where it was found: the commit's own record, else the full-suite pass its
// tree answers with.
func (f Found) Recorded() (*Record, string) {
	if f.Commit != nil {
		return f.Commit, FromCommit
	}
	if f.Tree != nil {
		return f.Tree, FromTree
	}
	return nil, ""
}

// Store is the record directory of one rig clone.
type Store struct {
	root string
}

// NewStore returns the store under commonDir, the clone's git common
// directory.
func NewStore(commonDir string) *Store {
	return &Store{root: filepath.Join(commonDir, dirName)}
}

// Root is the store's directory.
func (s *Store) Root() string { return s.root }

func validCheck(check string) bool {
	switch check {
	case CheckTest, CheckLint, CheckTypecheck:
		return true
	}
	return false
}

// CommitPath is the file that holds check's record for commit.
func (s *Store) CommitPath(check, commit string) string {
	return filepath.Join(s.root, check, "commits", commit+".json")
}

// TreePath is the file that holds the full-suite test pass a tree answers with.
func (s *Store) TreePath(check, tree string) string {
	return filepath.Join(s.root, check, "trees", tree+".json")
}

// Lookup reads what is recorded for commit: its own record, and for the test
// check the full-suite pass its tree answers with. Only a full-suite test pass
// crosses commits. A test subset depends on the commit's diff against its base,
// and so can a lint or typecheck command, and two commits with one tree need
// not share that diff. An error is a read that failed for a reason other than
// the record's absence.
func (s *Store) Lookup(check, commit, tree string) (Found, error) {
	var f Found
	if !validCheck(check) || !git.IsObjectID(commit) || !git.IsObjectID(tree) {
		return f, fmt.Errorf("lookup: invalid check %q, commit %q or tree %q", check, commit, tree)
	}
	path := s.CommitPath(check, commit)
	rec, err := readRecord(path)
	switch {
	case err == nil && rec.Check == check && rec.Commit == commit:
		f.Commit = rec
	case err == nil, errors.Is(err, errMalformed):
		f.Ignored = append(f.Ignored, path)
	case !errors.Is(err, fs.ErrNotExist):
		return f, err
	}
	if check != CheckTest {
		return f, nil
	}
	path = s.TreePath(check, tree)
	rec, err = readRecord(path)
	switch {
	case err == nil && rec.Check == check && rec.Tree == tree && rec.Result == ResultPass && rec.Scope == ScopeFull:
		f.Tree = rec
	case err == nil, errors.Is(err, errMalformed):
		f.Ignored = append(f.Ignored, path)
	case !errors.Is(err, fs.ErrNotExist):
		return f, err
	}
	return f, nil
}

// Put records rec at its commit, or returns an error. It is an upsert, and the
// last write wins, so two runners at one commit may both run the check and both
// write; neither waits on the other. Each file is written whole and renamed
// into place, so a reader sees the old record or the new one, never part of
// either.
//
// A full-suite test result also keeps the tree's entry: a pass files it, so
// every commit with the same tree reads the pass, and a fail withdraws it,
// because the tree's latest full-suite result is no longer a pass. The entry
// changes before the commit's record is written, so a fail is never recorded
// beside a pass the tree still answers with. A pass's entry is withdrawn again
// when the commit's record cannot be written. So a Put that returns an error
// leaves no record of rec, unless the error says that withdrawal failed too.
func (s *Store) Put(rec *Record) error {
	if err := rec.valid(); err != nil {
		return err
	}
	commit := s.CommitPath(rec.Check, rec.Commit)
	if rec.Check != CheckTest || rec.Scope != ScopeFull {
		return writeRecord(commit, rec)
	}
	tree := s.TreePath(rec.Check, rec.Tree)
	if rec.Result == ResultFail {
		if err := os.Remove(tree); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return fmt.Errorf("the tree's entry was not withdrawn: %w", err)
		}
		return writeRecord(commit, rec)
	}
	if err := writeRecord(tree, rec); err != nil {
		return fmt.Errorf("the tree's entry was not written: %w", err)
	}
	if err := writeRecord(commit, rec); err != nil {
		if rerr := os.Remove(tree); rerr != nil && !errors.Is(rerr, fs.ErrNotExist) {
			return fmt.Errorf("%w; the tree's entry, already written, could not be withdrawn: %v", err, rerr)
		}
		return err
	}
	return nil
}

// Runner names who ran a check: the session, else the agent, else the user and
// host of a run made by hand.
func Runner() string {
	for _, k := range []string{"GC_SESSION_NAME", "GC_AGENT", "GC_ALIAS"} {
		if v := strings.TrimSpace(os.Getenv(k)); v != "" {
			return v
		}
	}
	user := strings.TrimSpace(os.Getenv("USER"))
	if user == "" {
		user = "unknown"
	}
	host, err := os.Hostname()
	if err != nil || host == "" {
		return user
	}
	return user + "@" + host
}

// errMalformed reports a record file that exists but is not a record.
var errMalformed = errors.New("malformed record")

func readRecord(path string) (*Record, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var rec Record
	if err := json.Unmarshal(raw, &rec); err != nil {
		return nil, fmt.Errorf("%w: %s: %v", errMalformed, path, err)
	}
	if err := rec.valid(); err != nil {
		return nil, fmt.Errorf("%w: %s: %v", errMalformed, path, err)
	}
	return &rec, nil
}

// valid checks the fields every reader relies on.
func (r *Record) valid() error {
	switch {
	case !validCheck(r.Check):
		return fmt.Errorf("check %q is not test, lint or typecheck", r.Check)
	case r.Result != ResultPass && r.Result != ResultFail:
		return fmt.Errorf("result %q is not pass or fail", r.Result)
	case r.Check == CheckTest && r.Scope != ScopeFull && r.Scope != ScopeAffected && r.Scope != ScopeNone:
		return fmt.Errorf("a test record's scope %q is not full, affected or none", r.Scope)
	case r.Check != CheckTest && r.Scope != "" && r.Scope != ScopeNone:
		return fmt.Errorf("a %s record's scope %q is not none", r.Check, r.Scope)
	case r.Scope == ScopeNone && (r.Result != ResultPass || r.Command != ""):
		return fmt.Errorf("a run of nothing is a pass with no command")
	case r.Scope != ScopeNone && r.Command == "":
		return fmt.Errorf("a run's record names its command")
	case !git.IsObjectID(r.Commit):
		return fmt.Errorf("commit %q is not a full object name", r.Commit)
	case !git.IsObjectID(r.Tree):
		return fmt.Errorf("tree %q is not a full object name", r.Tree)
	}
	return nil
}

// writeRecord writes rec to a temporary file beside path and renames it into
// place.
func writeRecord(path string, rec *Record) error {
	raw, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	_, werr := tmp.Write(append(raw, '\n'))
	cerr := tmp.Close()
	if werr == nil {
		werr = cerr
	}
	if werr == nil {
		werr = os.Chmod(tmp.Name(), 0o644)
	}
	if werr == nil {
		werr = os.Rename(tmp.Name(), path)
	}
	if werr != nil {
		_ = os.Remove(tmp.Name())
		return werr
	}
	return nil
}
