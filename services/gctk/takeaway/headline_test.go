package takeaway

import (
	"strings"
	"testing"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
)

// The headline is one line of at most lifecycle.TakeawayMax codepoints,
// collapsed before it is measured, so what is measured is what is stored, and
// a longer one is refused whole, never cut, before anything is written, a
// release and its waits included (CAP, CAPWS, CAPFIRST).
func TestTheHeadlineIsCappedBeforeAnythingIsWritten(t *testing.T) {
	at := strings.Repeat("é", lifecycle.TakeawayMax)
	w := newWorld(t)
	if code, _, err := w.take(Request{Bead: "tk-a", Text: at}); code != 0 || w.row("tk-a").Metadata["gc.takeaway"] != at {
		t.Errorf("(CAP) a headline at the cap exits %d (%v)", code, err)
	}
	w = newWorld(t)
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: "a" + strings.Repeat(" \n", 100) + "b"}); code != 0 || w.row("tk-a").Metadata["gc.takeaway"] != "a b" {
		t.Errorf("(CAPWS) the headline stored is %q", w.row("tk-a").Metadata["gc.takeaway"])
	}
	for _, req := range []Request{
		{Bead: "tk-a", Text: at + "x"},
		{Bead: "tk-a", Text: at + "x", Release: true, WaitingOn: []string{"tk-b"}},
	} {
		w = newWorld(t)
		code, _, err := w.take(req)
		if code != 2 || len(w.log) != 0 {
			t.Errorf("(CAPFIRST) a headline past the cap exits %d with %q written, want 2 and nothing", code, w.log)
		}
		has(t, errText(err), "141 characters, and the cap is 140", "(CAP) the refusal")
	}
	w = newWorld(t)
	if code, _, _ := w.take(Request{Bead: "tk-a", Text: " \t "}); code != 2 || len(w.log) != 0 {
		t.Errorf("an empty headline exits %d with %q written, want 2 and nothing", code, w.log)
	}
}

// A release ends the run beneath the bead through the pack's run-cancel.sh, so
// a caller that names no pack scripts directory is refused before anything is
// written, and a headline alone needs none.
func TestAReleaseNeedsThePacksScripts(t *testing.T) {
	w := newWorld(t)
	w.tk.Scripts = ""
	code, _, err := w.take(Request{Bead: "tk-a", Text: "stopped", Release: true, NoWait: true})
	if code != 2 || len(w.log) != 0 {
		t.Errorf("a release with no scripts directory exits %d with %q written, want 2 and nothing", code, w.log)
	}
	has(t, errText(err), "GCTK_SCRIPTS_DIR", "the refusal")
	w = newWorld(t)
	w.tk.Scripts = ""
	if code, _, err := w.take(Request{Bead: "tk-a", Text: "a headline"}); code != 0 {
		t.Errorf("a headline with no scripts directory exits %d (%v)", code, err)
	}
}
