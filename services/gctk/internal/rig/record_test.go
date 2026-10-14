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
	treeT   = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	treeU   = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
)

func rec(check, result, method, commit, tree string) *Record {
	r := &Record{Check: check, Result: result, Method: method, Commit: commit, Tree: tree,
		Runner: "test", RecordedAt: "2026-10-13T00:00:00Z", Command: "true", DurationMS: 5}
	if result == ResultFail {
		r.ExitCode = 1
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

func TestLookupAnswersFromTheCommitsOwnRecord(t *testing.T) {
	s := NewStore(t.TempDir())
	if f := mustLookup(t, s, CheckTest, commitA, treeT); f.Record != nil {
		t.Fatalf("an empty store answered %+v", f.Record)
	}
	mustPut(t, s, rec(CheckTest, ResultPass, MethodAffected, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	if f.Record == nil || f.Source != FromCommit || f.Record.Method != MethodAffected || f.Record.Result != ResultPass {
		t.Fatalf("Lookup = %+v from %q, want the affected pass from the commit", f.Record, f.Source)
	}
	if f := mustLookup(t, s, CheckLint, commitA, treeT); f.Record != nil {
		t.Fatalf("a test record answered for lint: %+v", f.Record)
	}
}

func TestFullSuitePassAnswersForEveryCommitWithItsTree(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, MethodFull, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitB, treeT)
	if f.Record == nil || f.Source != FromTree || f.Record.Commit != commitA {
		t.Fatalf("a new commit with the same tree read %+v from %q, want commit A's full pass from the tree", f.Record, f.Source)
	}
	if f := mustLookup(t, s, CheckTest, commitB, treeU); f.Record != nil {
		t.Fatalf("a commit with another tree read %+v", f.Record)
	}
}

func TestOnlyAFullSuiteTestPassCrossesCommits(t *testing.T) {
	cases := []struct {
		name string
		r    *Record
	}{
		{"an affected pass", rec(CheckTest, ResultPass, MethodAffected, commitA, treeT)},
		{"a full fail", rec(CheckTest, ResultFail, MethodFull, commitA, treeT)},
		{"a run of nothing", rec(CheckTest, ResultPass, MethodNone, commitA, treeT)},
		{"a lint pass", rec(CheckLint, ResultPass, MethodFull, commitA, treeT)},
		{"a typecheck pass", rec(CheckTypecheck, ResultPass, MethodFull, commitA, treeT)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := NewStore(t.TempDir())
			mustPut(t, s, c.r)
			if f := mustLookup(t, s, c.r.Check, commitB, treeT); f.Record != nil {
				t.Fatalf("commit B read %+v from %q", f.Record, f.Source)
			}
		})
	}
}

func TestFullFailWithdrawsTheTreesPass(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckTest, ResultPass, MethodFull, commitA, treeT))
	mustPut(t, s, rec(CheckTest, ResultFail, MethodFull, commitA, treeT))
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	if f.Record == nil || f.Record.Result != ResultFail {
		t.Fatalf("commit A read %+v, want its latest record, the fail", f.Record)
	}
	if f := mustLookup(t, s, CheckTest, commitB, treeT); f.Record != nil {
		t.Fatalf("commit B still read the tree's withdrawn pass: %+v", f.Record)
	}
	if _, err := os.Stat(s.TreePath(CheckTest, treeT)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("the tree entry survived the fail: %v", err)
	}
}

func TestPutIsALastWriteWinsUpsert(t *testing.T) {
	s := NewStore(t.TempDir())
	mustPut(t, s, rec(CheckLint, ResultFail, MethodFull, commitA, treeT))
	mustPut(t, s, rec(CheckLint, ResultPass, MethodFull, commitA, treeT))
	f := mustLookup(t, s, CheckLint, commitA, treeT)
	if f.Record == nil || f.Record.Result != ResultPass {
		t.Fatalf("Lookup after two writes = %+v, want the second", f.Record)
	}
	left, err := filepath.Glob(filepath.Join(s.Root(), CheckLint, "commits", ".*.tmp"))
	if err != nil || len(left) != 0 {
		t.Fatalf("temporary files left behind: %v %v", left, err)
	}
}

func TestADamagedRecordReadsAsAbsent(t *testing.T) {
	cases := map[string]string{
		"not json":            "{",
		"no result":           `{"check":"test","method":"full","commit":"` + commitA + `","tree":"` + treeT + `"}`,
		"filed under another": `{"check":"test","result":"pass","method":"full","commit":"` + commitB + `","tree":"` + treeT + `"}`,
		"a failed none":       `{"check":"test","result":"fail","method":"none","commit":"` + commitA + `","tree":"` + treeT + `"}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			s := NewStore(t.TempDir())
			path := s.CommitPath(CheckTest, commitA)
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
				t.Fatal(err)
			}
			f := mustLookup(t, s, CheckTest, commitA, treeT)
			if f.Record != nil {
				t.Fatalf("a damaged record answered: %+v", f.Record)
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
	mustPut(t, s, rec(CheckTest, ResultPass, MethodFull, commitA, treeT))
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
	if err := s.Put(rec(CheckTest, ResultPass, MethodFull, "../x", treeT)); err == nil {
		t.Error("Put accepted a commit that is not an object id")
	}
}

func TestMarkPreExistingAnnotatesOnlyAFail(t *testing.T) {
	s := NewStore(t.TempDir())
	if _, err := s.MarkPreExisting(CheckTest, commitA, "tk-x"); !errors.Is(err, ErrNoFail) {
		t.Fatalf("annotating with no record = %v, want ErrNoFail", err)
	}
	mustPut(t, s, rec(CheckTest, ResultPass, MethodFull, commitA, treeT))
	if _, err := s.MarkPreExisting(CheckTest, commitA, "tk-x"); !errors.Is(err, ErrNoFail) {
		t.Fatalf("annotating a pass = %v, want ErrNoFail", err)
	}
	mustPut(t, s, rec(CheckTest, ResultFail, MethodAffected, commitA, treeT))
	got, err := s.MarkPreExisting(CheckTest, commitA, "tk-x")
	if err != nil {
		t.Fatalf("annotating a fail: %v", err)
	}
	if got.Disposition != DispositionPreExisting || got.Tracker != "tk-x" || got.Result != ResultFail {
		t.Fatalf("annotated record = %+v", got)
	}
	f := mustLookup(t, s, CheckTest, commitA, treeT)
	if f.Record.Disposition != DispositionPreExisting || f.Record.Tracker != "tk-x" {
		t.Fatalf("the annotation did not persist: %+v", f.Record)
	}
	if _, err := s.MarkPreExisting(CheckTest, commitA, ""); err == nil {
		t.Fatal("an annotation with no tracker was accepted")
	}
}

// The cost of one record write (a full-suite test pass, which writes the
// commit's file and the tree's) and of one lookup that finds it.
func BenchmarkPutFullPass(b *testing.B) {
	s := NewStore(b.TempDir())
	r := rec(CheckTest, ResultPass, MethodFull, commitA, treeT)
	for b.Loop() {
		if err := s.Put(r); err != nil {
			b.Fatal(err)
		}
	}
}

func BenchmarkLookupHit(b *testing.B) {
	s := NewStore(b.TempDir())
	if err := s.Put(rec(CheckTest, ResultPass, MethodFull, commitA, treeT)); err != nil {
		b.Fatal(err)
	}
	for b.Loop() {
		if f, err := s.Lookup(CheckTest, commitA, treeT); err != nil || f.Record == nil {
			b.Fatal(err)
		}
	}
}
