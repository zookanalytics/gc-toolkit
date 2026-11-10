package form

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
)

// stallingHelm is a fakeHelm whose save runs until the test releases it, so
// the program can end while the save is in flight.
type stallingHelm struct {
	*fakeHelm
	saving  chan struct{} // closed once the save has begun
	release chan struct{}
}

func (h *stallingHelm) Save(ctx context.Context, req SaveRequest) (Saved, error) {
	close(h.saving)
	<-h.release
	return h.fakeHelm.Save(ctx, req)
}

// runProgram runs the form in a bubbletea program with no input, so the test's
// own messages are all it gets, and with its output discarded. done is closed
// once Run has returned, and *err is then what it returned.
func runProgram(m *Model) (p *tea.Program, done <-chan struct{}, err *error) {
	p = tea.NewProgram(m, tea.WithInput(nil), tea.WithOutput(io.Discard), tea.WithoutSignalHandler())
	ch, runErr := make(chan struct{}), new(error)
	go func() {
		defer close(ch)
		_, *runErr = p.Run()
	}()
	return p, ch, runErr
}

// within waits for ch, closed or sent on, and fails the test after ten seconds.
func within(t *testing.T, ch <-chan struct{}, what string) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(10 * time.Second):
		t.Fatalf("%s did not happen within ten seconds", what)
	}
}

// The form's program can end with no key the form handles. bubbletea's signal
// handler sends InterruptMsg for an interrupt and QuitMsg for a termination,
// and its event loop returns on each before Update sees it. Leave then keeps
// the question the form did not save, as the form's own leaving does, and
// while a save runs it says whether the question was filed is unknown.
func TestAFormSomethingElseEndsKeepsTheQuestion(t *testing.T) {
	const question = "the question\n  in two lines "
	for _, end := range []struct {
		name string
		msg  tea.Msg
		err  error // what Run returns
	}{
		{"interrupt", tea.InterruptMsg{}, tea.ErrInterrupted},
		{"termination", tea.QuitMsg{}, nil},
	} {
		ran := func(t *testing.T, done <-chan struct{}, err *error) {
			t.Helper()
			within(t, done, "the end of the program")
			if (end.err == nil) != (*err == nil) || (end.err != nil && !errors.Is(*err, end.err)) {
				t.Fatalf("Run returned %v, want %v", *err, end.err)
			}
		}
		kept := func(t *testing.T, dir, note string) {
			t.Helper()
			files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
			if len(files) != 1 || !strings.Contains(note, files[0]) {
				t.Fatalf("draft files %v, note %q", files, note)
			}
			if b, _ := os.ReadFile(files[0]); string(b) != question {
				t.Fatalf("kept draft = %q, want %q", b, question)
			}
		}

		t.Run(end.name+" while the form is idle", func(t *testing.T) {
			dir := t.TempDir()
			f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
			m := newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
			p, done, err := runProgram(m)
			p.Send(tea.PasteMsg{Content: question})
			p.Send(end.msg)
			ran(t, done, err)
			note := m.Leave()
			kept(t, dir, note)
			if !strings.HasPrefix(note, "Nothing was filed.") || !strings.Contains(note, "gc-helm.sh engage tk-a --reason") {
				t.Fatalf("note = %q", note)
			}
			if again := m.Leave(); again != note {
				t.Fatalf("Leave said %q, then %q", note, again)
			}
			kept(t, dir, note)
		})

		t.Run(end.name+" while a save runs", func(t *testing.T) {
			dir := t.TempDir()
			h := &stallingHelm{
				fakeHelm: &fakeHelm{
					about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
					saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
				},
				saving:  make(chan struct{}),
				release: make(chan struct{}),
			}
			defer close(h.release)
			m := newFormOn(t, h, Options{Subject: "tk-a", DraftDir: dir})
			p, done, err := runProgram(m)
			// The subject's lookup lands before Ctrl+S, so the save runs.
			p.Send(aboutMsg{key: lookupKey{ref: "tk-a"}, about: subjectAbout("tk-a", "gc-toolkit")})
			p.Send(tea.PasteMsg{Content: question})
			p.Send(ctrl('s'))
			within(t, h.saving, "the save")
			p.Send(end.msg)
			ran(t, done, err)
			note := m.Leave()
			kept(t, dir, note)
			if !strings.HasPrefix(note, "The form closed while your question was being saved, so whether it was filed is unknown") {
				t.Fatalf("note = %q", note)
			}
		})
	}
}
