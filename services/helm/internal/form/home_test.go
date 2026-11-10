package form

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

// homeOn moves the home page's cursor to entry, from the top.
func homeOn(m *Model, entry int) {
	for range len(homeLabels) {
		m.Update(key(tea.KeyUp))
	}
	for range entry {
		m.Update(key(tea.KeyDown))
	}
}

// The home page shows its four entries and reads nothing until one opens. The
// po and mechanik hand the terminal to their own verbs, and the form leaves
// once it comes back. Start and return open the form's own screens, each
// reading the city as it opens, and Esc on either comes back to the page,
// where Esc leaves the form.
func TestTheHomePageOpensEachEntry(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{Home: true})
	if m.scr != homeScreen {
		t.Fatalf("the form opened on screen %d, not the home page", m.scr)
	}
	if cmd := m.Init(); cmd != nil || m.cityBusy {
		t.Fatal("the home page read the city before an entry asked for it")
	}
	v := m.homeView()
	for _, label := range homeLabels {
		if !strings.Contains(v, label) {
			t.Fatalf("the home page does not show %q:\n%s", label, v)
		}
	}
	if l := marked(strings.Split(v, "\n"), "› "); !strings.Contains(l, "The po") {
		t.Fatalf("the cursor does not start on the po:\n%s", v)
	}

	for _, c := range []struct {
		entry int
		seat  string
	}{{poEntry, "po"}, {mechanikEntry, "mechanik"}} {
		f := &fakeHelm{}
		m := newForm(t, f, Options{Home: true})
		homeOn(m, c.entry)
		_, cmd := m.Update(key(tea.KeyEnter))
		if cmd == nil || strings.Join(f.seats, " ") != c.seat || f.seatArgs[0] != "gc-helm.sh "+c.seat {
			t.Fatalf("opening %s ran seats %v (argv %v)", c.seat, f.seats, f.seatArgs)
		}
		if _, last := m.Update(attachedMsg{}); !isQuit(last) || m.Note() != "" {
			t.Fatalf("the form did not leave quietly once %s's terminal came back (note %q)", c.seat, m.Note())
		}
	}

	f := &fakeHelm{city: City{Rigs: rigCity().Rigs, Conversations: []Conversation{{ID: "tk-c1", Readiness: Ready}}}}
	m = newForm(t, f, Options{Home: true})
	homeOn(m, startEntry)
	_, cmd := m.Update(key(tea.KeyEnter))
	if m.scr != composeScreen || !m.cityBusy {
		t.Fatalf("start opened screen %d, reading the city %v", m.scr, m.cityBusy)
	}
	deliver(m, cmd)
	if m.city == nil || !strings.Contains(m.composeView(), "Esc back") {
		t.Fatalf("the start screen did not read the rigs or name Esc as back:\n%s", m.composeView())
	}
	if _, cmd := m.Update(key(tea.KeyEscape)); cmd != nil || m.scr != homeScreen {
		t.Fatalf("Esc on the start screen went to screen %d, not back to the home page", m.scr)
	}
	homeOn(m, returnEntry)
	_, cmd = m.Update(key(tea.KeyEnter))
	if m.scr != returnScreen {
		t.Fatalf("return opened screen %d", m.scr)
	}
	deliver(m, cmd)
	if v := m.returnView(); !strings.Contains(v, "tk-c1") || !strings.Contains(v, "Esc back") {
		t.Fatalf("the return list does not show the conversations or name Esc as back:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEscape)); cmd != nil || m.scr != homeScreen {
		t.Fatalf("Esc on the return list went to screen %d, not back to the home page", m.scr)
	}
	if _, cmd := m.Update(key(tea.KeyEscape)); !isQuit(cmd) {
		t.Fatal("Esc on the home page did not leave the form")
	}
	if len(f.seats) != 0 || len(f.attaches) != 0 || len(f.saves) != 0 {
		t.Fatalf("moving between the screens ran seats %v, attaches %v, saves %v", f.seats, f.attaches, f.saves)
	}
}

// Without the home page, Esc leaves the start and the return screens as it
// always has, and their hints say so.
func TestWithoutTheHomePageEscStillLeaves(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{})
	if v := m.composeView(); !strings.Contains(v, "Esc cancel") || strings.Contains(v, "Esc back") {
		t.Fatalf("the start screen's hint:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEscape)); !isQuit(cmd) {
		t.Fatal("Esc on the start screen did not leave the form")
	}
	m = newForm(t, &fakeHelm{}, Options{Return: true})
	if v := m.returnView(); !strings.Contains(v, "Esc leaves") {
		t.Fatalf("the return list's hint:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEscape)); !isQuit(cmd) {
		t.Fatal("Esc on the return list did not leave the form")
	}
}

// A question typed on the start screen and left there by going back is kept in
// a file before the terminal goes to a seat, and a seat's verb that fails is
// named after what it printed, ahead of where the question is.
func TestASeatOpenedAfterAnUnsavedQuestionKeepsIt(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{}
	m := newForm(t, f, Options{Home: true, DraftDir: dir})
	homeOn(m, startEntry)
	m.Update(key(tea.KeyEnter))
	focusOn(t, m, questionField)
	typeText(m, "a thought for later")
	m.Update(key(tea.KeyEscape))
	homeOn(m, poEntry)
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.seats) != 1 {
		t.Fatalf("the po did not open: seats %v", f.seats)
	}
	files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
	if len(files) != 1 {
		t.Fatalf("draft files while the po holds the terminal: %v", files)
	}
	if b, _ := os.ReadFile(files[0]); string(b) != "a thought for later" {
		t.Fatalf("kept draft = %q", b)
	}
	_, last := m.Update(attachedMsg{err: errors.New("exit status 4")})
	note := m.Note()
	if !isQuit(last) || !strings.HasPrefix(note, "The po did not open: exit status 4") || !strings.Contains(note, files[0]) {
		t.Fatalf("note after the po's verb failed = %q", note)
	}
}

// One hand-off runs: an Enter that lands before the first has taken the
// terminal opens nothing more, a seat or a conversation.
func TestASecondEnterOnTheHomePageOpensNothingMore(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-c1", Readiness: Ready}}}}
	m := newForm(t, f, Options{Home: true})
	homeOn(m, mechanikEntry)
	m.Update(key(tea.KeyEnter))
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd != nil || len(f.seats) != 1 {
		t.Fatalf("a second Enter opened seats %v", f.seats)
	}
	if cmd := m.attachTo("tk-c1", ""); cmd != nil || len(f.attaches) != 0 {
		t.Fatalf("an attach after the seat's hand-off ran: %v", f.attaches)
	}
}
