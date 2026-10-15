package rig

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	commitA = "1111111111111111111111111111111111111111"
	commitB = "2222222222222222222222222222222222222222"
	commitC = "3333333333333333333333333333333333333333"
	treeT   = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	treeU   = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

// rec is a run of command "true", or of nothing when scope is ScopeNone.
func rec(check, result, scope, commit, tree string) *Record {
	r := &Record{Check: check, Result: result, Scope: scope, Commit: commit, Tree: tree,
		Runner: "test", RecordedAt: "2026-10-13T00:00:00Z", Command: "true", DurationMS: 5}
	if result == ResultFail {
		r.ExitCode = 1
	}
	if scope == ScopeNone {
		r.Command = ""
	}
	return r
}

func mustPut(t *testing.T, s *Store, r *Record) {
	t.Helper()
	if err := s.Put(r); err != nil {
		t.Fatalf("Put(%+v): %v", r, err)
	}
}

func mustLookup(t *testing.T, s *Store, check, commit, tree string) Found {
	t.Helper()
	f, err := s.Lookup(check, commit, tree)
	if err != nil {
		t.Fatalf("Lookup(%s, %s, %s): %v", check, commit, tree, err)
	}
	return f
}

func TestTheCommitsOwnRecordAnswersTheRunItRecords(t *testing.T) {
	s := NewStore(t.TempDir())
	if f := mustLookup(t, s, CheckTest, commitA, treeT); f.Commit != nil || f.Tree != nil {
		t.Fatalf("an empty store read %+v", f)
	}
	mustPut(t, s, rec(CheckTest, ResultPass, ScopeAffected, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	r, src := f.Answer(ScopeAffected, "true")
	if r == nil || src != FromCommit || r.Scope != ScopeAffected || r.Result != ResultPass {
		t.Fatalf("Answer = %+v from %q, want the affected pass from the commit", r, src)
	}
	if r, _ := f.Recorded(); r == nil || r.Scope != ScopeAffected {
		t.Fatalf("Recorded = %+v, want the affected pass", r)
	}
	if f := mustLookup(t, s, CheckLint, commitA, treeT); f.Commit != nil {
		t.Fatalf("a test record answered for lint: %+v", f.Commit)
	}
}

func TestARecordAnswersOnlyItsOwnCommandAndScope(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	for _, c := range []struct{ scope, command string }{
		{ScopeFull, "false"},
		{ScopeFull, "true "},
		{ScopeAffected, "true"},
		{ScopeNone, ""},
	} {
		if r, src := f.Answer(c.scope, c.command); r != nil {
			t.Errorf("Answer(%q, %q) = %+v from %q, want no answer", c.scope, c.command, r, src)
		}
	}
	// What is recorded is still there for --check, whatever run asks.
	if r, src := f.Recorded(); r == nil || src != FromCommit {
		t.Fatalf("Recorded = %+v from %q", r, src)
	}
}

func TestFullSuitePassAnswersForEveryCommitWithItsTree(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitB, treeT)
	if r, src := f.Answer(ScopeFull, "true"); r == nil || src != FromTree || r.Commit != commitA {
		t.Fatalf("a new commit with the same tree read %+v from %q, want commit A's full pass from the tree", r, src)
	}
	if r, src := f.Recorded(); r == nil || src != FromTree {
		t.Fatalf("Recorded = %+v from %q, want the tree's pass", r, src)
	}
	// The tree's pass answers only a full-suite call with its own command.
	if r, _ := f.Answer(ScopeFull, "false"); r != nil {
		t.Fatalf("the tree's pass answered another command: %+v", r)
	}
	if r, _ := f.Answer(ScopeAffected, "true"); r != nil {
		t.Fatalf("the tree's pass answered an affected call: %+v", r)
	}
	if f := mustLookup(t, s, CheckTest, commitB, treeU); f.Tree != nil {
		t.Fatalf("a commit with another tree read %+v", f.Tree)
	}
}

func TestOnlyAFullSuiteTestPassCrossesCommits(t *testing.T) {
	cases := []struct {
		name string
		r    *Record
	}{
		{"an affected pass", rec(CheckTest, ResultPass, ScopeAffected, commitA, treeT)},
		{"a full fail", rec(CheckTest, ResultFail, ScopeFull, commitA, treeT)},
		{"a run of nothing", rec(CheckTest, ResultPass, ScopeNone, commitA, treeT)},
		{"a lint pass", rec(CheckLint, ResultPass, "", commitA, treeT)},
		{"a typecheck pass", rec(CheckTypecheck, ResultPass, "", commitA, treeT)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := NewStore(t.TempDir())
			mustPut(t, s, c.r)
			f := mustLookup(t, s, c.r.Check, commitB, treeT)
			if r, src := f.Recorded(); r != nil {
				t.Fatalf("commit B read %+v from %q", r, src)
			}
		})
	}
}

func TestFullFailWithdrawsTheTreesPass(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT))
	mustPut(t, s, rec(CheckTest, ResultFail, ScopeFull, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	if f.Commit == nil || f.Commit.Result != ResultFail {
		t.Fatalf("commit A read %+v, want its latest record, the fail", f.Commit)
	}
	if f := mustLookup(t, s, CheckTest, commitB, treeT); f.Tree != nil {
		t.Fatalf("commit B still read the tree's withdrawn pass: %+v", f.Tree)
	}
	if _, err := os.Stat(s.TreePath(CheckTest, treeT)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the tree entry survived the fail: %v", err)
	}
}

func TestPutIsALastWriteWinsUpsert(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckLint, ResultFail, "", commitA, treeT))
	mustPut(t, s, rec(CheckLint, ResultPass, "", commitA, treeT))
	f := mustLookup(t, s, CheckLint, commitA, treeT)
	if f.Commit == nil || f.Commit.Result != ResultPass {
		t.Fatalf("Lookup after two writes = %+v, want the second", f.Commit)
	}
	left, err := filepath.Glob(filepath.Join(s.Root(), CheckLint, "commits", ".*.tmp"))
	if err != nil || len(left) != 0 {
		t.Fatalf("temporary files left behind: %v %v", left, err)
	}
}

// readOnly makes dir, creating it if need be, refuse writes until the test
// ends. It still reads, so a lookup through it answers.
func readOnly(t *testing.T, dir string) {
	t.Helper()
	if os.Geteuid() == 0 {
		t.Skip("root writes into a read-only directory")
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755) })
}

func TestAPutTheStoreDoesNotTakeLeavesNoRecordOfTheResult(t *testing.T) {
	cases := []struct {
		name string
		// prior is recorded before the store stops taking writes.
		prior *Record
		r     *Record
		// refused is the directory under the check's own that takes no writes.
		refused string
	}{
		{"a lint pass", nil, rec(CheckLint, ResultPass, "", commitA, treeT), "commits"},
		{"an affected pass", nil, rec(CheckTest, ResultPass, ScopeAffected, commitA, treeT), "commits"},
		{"a run of nothing", nil, rec(CheckTest, ResultPass, ScopeNone, commitA, treeT), "commits"},
		{"a full pass whose tree entry cannot be written", nil, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT), "trees"},
		{"a full pass whose commit record cannot be written", nil, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT), "commits"},
		{"a full fail that cannot withdraw the tree's pass", rec(CheckTest, ResultPass, ScopeFull, commitB, treeT), rec(CheckTest, ResultFail, ScopeFull, commitA, treeT), "trees"},
		{"a full fail whose commit record cannot be written", rec(CheckTest, ResultPass, ScopeFull, commitB, treeT), rec(CheckTest, ResultFail, ScopeFull, commitA, treeT), "commits"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := NewStore(t.TempDir())
			if c.prior != nil {
				mustPut(t, s, c.prior)
			}
			readOnly(t, filepath.Join(s.Root(), c.r.Check, c.refused))
			if err := s.Put(c.r); err == nil {
				t.Fatal("Put reported no error")
			}
			// No commit reads the result: not its own, not one the tree answers
			// for.
			for _, commit := range []string{commitA, commitB, commitC} {
				f := mustLookup(t, s, c.r.Check, commit, treeT)
				if r, src := f.Recorded(); r != nil && *r == *c.r {
					t.Fatalf("commit %s reads the result Put refused, from %q", commit, src)
				}
			}
		})
	}
}

func TestADamagedRecordReadsAsAbsent(t *testing.T) {
	head := `{"check":"test","result":"pass","scope":"full","commit":"` + commitA + `","tree":"` + treeT + `"`
	cases := map[string]struct {
		check, body string
	}{
		"not json":                        {CheckTest, "{"},
		"no result":                       {CheckTest, `{"check":"test","scope":"full","commit":"` + commitA + `","tree":"` + treeT + `","command":"true"}`},
		"filed under another":             {CheckTest, `{"check":"test","result":"pass","scope":"full","commit":"` + commitB + `","tree":"` + treeT + `","command":"true"}`},
		"a test run with no scope":        {CheckTest, `{"check":"test","result":"pass","commit":"` + commitA + `","tree":"` + treeT + `","command":"true"}`},
		"a run with no command":           {CheckTest, head + `}`},
		"a failed run of nothing":         {CheckTest, `{"check":"test","result":"fail","scope":"none","commit":"` + commitA + `","tree":"` + treeT + `"}`},
		"a run of nothing with a command": {CheckTest, `{"check":"test","result":"pass","scope":"none","commit":"` + commitA + `","tree":"` + treeT + `","command":"true"}`},
		"a lint record with a test scope": {CheckLint, `{"check":"lint","result":"pass","scope":"full","commit":"` + commitA + `","tree":"` + treeT + `","command":"true"}`},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			s := NewStore(t.TempDir())
			path := s.CommitPath(c.check, commitA)
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, []byte(c.body), 0o644); err != nil {
				t.Fatal(err)
			}
			f := mustLookup(t, s, c.check, commitA, treeT)
			if r, _ := f.Recorded(); r != nil {
				t.Fatalf("a damaged record answered: %+v", r)
			}
			if len(f.Ignored) != 1 || f.Ignored[0] != path {
				t.Fatalf("Ignored = %v, want [%s]", f.Ignored, path)
			}
		})
	}
}

func TestAnUnreadableStoreIsAnError(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root reads a mode-000 directory")
	}
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, ScopeFull, commitA, treeT))
	dir := filepath.Join(s.Root(), CheckTest, "commits")
	if err := os.Chmod(dir, 0); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(dir, 0o755)
	if _, err := s.Lookup(CheckTest, commitA, treeT); err == nil {
		t.Fatal("a lookup that could not read the store reported no error")
	}
}

func TestLookupRefusesANameThatIsNotAnObjectID(t *testing.T) {
	s := NewStore(t.TempDir())
	for _, c := range []string{"../../etc", "HEAD", strings.Repeat("a", 39)} {
		if _, err := s.Lookup(CheckTest, c, treeT); err == nil {
			t.Errorf("Lookup accepted commit %q", c)
		}
	}
	if _, err := s.Lookup("setup", commitA, treeT); err == nil {
		t.Error("Lookup accepted check setup, which records nothing")
	}
	if err := s.Put(rec(CheckTest, ResultPass, ScopeFull, "../x", treeT)); err == nil {
		t.Error("Put accepted a commit that is not an object id")
	}
}

// The cost of one record write (a full-suite test pass, which writes the
// commit's file and the tree's) and of one lookup that finds it.
func BenchmarkPutFullPass(b *testing.B) {
	s := NewStore(b.TempDir())
	r := rec(CheckTest, ResultPass, ScopeFull, commitA, treeT)
	for b.Loop() {
		if err := s.Put(r); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkLookupHit(b *testing.B) {
	s := NewStore(b.TempDir())
	if err := s.Put(rec(CheckTest, ResultPass, ScopeFull, commitA, treeT)); err != nil {
		b.Fatal(err)
	}
	for b.Loop() {
		if f, err := s.Lookup(CheckTest, commitA, treeT); err != nil || f.Commit == nil {
			b.Fatal(err)
		}
	}
}
