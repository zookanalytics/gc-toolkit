package cli

import (
	"bytes"
	"errors"
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gcbd/fake"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
)

// runUnmarked prints what the store's unmarked beads answer, and returns its
// exit, stdout and stderr.
func runUnmarked(t *testing.T, s *fake.Store) (int, string, string) {
	t.Helper()
	var out, errb bytes.Buffer
	r := &reaction.Reactions{Ledger: ledger.New(s), Log: func(line string) { errb.WriteString(line + "\n") }}
	code := reactionUnmarked(r, &out, &errb)
	return code, out.String(), errb.String()
}

// Each unmarked bead prints on one line, highest priority first: its id, its
// priority and its title, each control character in the title a space.
func TestReactionUnmarkedPrintsEachBeadOnALine(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-a", Title: "Found: a gap\tin the sweep", Status: "open", IssueType: "bug", Priority: 2})
	s.Put(fake.Bead{ID: "tk-b", Title: "a raw task", Status: "open", IssueType: "task", Priority: 1})
	s.Put(fake.Bead{ID: "tk-held", Title: "held", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}})
	for _, id := range []string{"tk-a", "tk-b", "tk-held"} {
		s.MakeReady(id)
	}
	code, out, errb := runUnmarked(t, s)
	if want := "tk-b\tP1\ta raw task\ntk-a\tP2\tFound: a gap in the sweep\n"; code != 0 || out != want {
		t.Errorf("exit %d, stdout %q (stderr %q); want %q", code, out, errb, want)
	}
}

// With nothing to list it says so on one line.
func TestReactionUnmarkedSaysWhenNothingIsUnmarked(t *testing.T) {
	s := fake.New()
	s.Put(fake.Bead{ID: "tk-held", Title: "held", Status: "open", IssueType: "task", Labels: []string{"hold:mayor"}})
	s.MakeReady("tk-held")
	if code, out, _ := runUnmarked(t, s); code != 0 || out != unmarkedNone+"\n" {
		t.Errorf("exit %d, stdout %q; want the line that says nothing is unmarked", code, out)
	}
}

// A store that does not answer lists nothing on stdout, says so on stderr and
// exits 1, since a list it could not read is not an empty one.
func TestReactionUnmarkedStopsWhenTheStoreDoesNotAnswer(t *testing.T) {
	s := fake.New()
	s.ReadyErr = errors.New("gc bd ready exited 1: database is locked")
	code, out, errb := runUnmarked(t, s)
	if code != 1 || out != "" || !strings.Contains(errb, "the store did not answer") || !strings.Contains(errb, "database is locked") {
		t.Errorf("exit %d, stdout %q, stderr %q; want exit 1 naming the failed read", code, out, errb)
	}
}

// The list takes no argument.
func TestReactionUnmarkedTakesNoArgument(t *testing.T) {
	var out, errb bytes.Buffer
	if code := Run([]string{"reaction", "unmarked", "tk-sub"}, "test", &out, &errb); code != 2 {
		t.Errorf("an argument exited %d, saying %q; want 2", code, errb.String())
	}
}
