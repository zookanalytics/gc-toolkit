package form

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

// peopleCity is rigCity with the seats `conversations` lists for it: mechanik
// with a terminal attached, gc-toolkit's po with no session, harbor's asleep,
// the suspended rig's, and the po of docs, a rig with no converse template.
func peopleCity() City {
	c := rigCity()
	c.Seats = []Seat{
		{Name: "mechanik", Session: &Session{ID: "s-m", Name: "gc-toolkit__mechanik", State: "active", Attached: true}},
		{Name: "po", Rig: "gc-toolkit"},
		{Name: "po", Rig: "harbor", Session: &Session{ID: "s-h", Name: "harbor--gc-toolkit__po", State: "asleep"}},
		{Name: "po", Rig: "paused"},
		{Name: "po", Rig: "docs", Session: &Session{ID: "s-d", Name: "docs--gc-toolkit__po", State: "active"}},
	}
	return c
}

// toPage goes to page p with the keys the operator presses: on the start
// page ↑ from the subject reaches the tabs, and → moves along them. What each
// key asks for is delivered, as the program would.
func toPage(t *testing.T, m *Model, p screen) {
	t.Helper()
	if m.scr == composeScreen && m.focus != tabsField {
		focusOn(t, m, subjectField)
		_, cmd := m.Update(key(tea.KeyUp))
		deliver(m, cmd)
	}
	for i := 0; i < len(pages) && m.scr != p; i++ {
		_, cmd := m.Update(key(tea.KeyRight))
		deliver(m, cmd)
	}
	if m.scr != p {
		t.Fatalf("could not reach page %d (on %d)", p, m.scr)
	}
}

// The form's pages are tabs. The form opens on starting a conversation with the
// cursor in the subject, ↑ from the subject reaches the tabs, ←/→ move along
// them and wrap around, and ↓, Enter or Tab go back down to the subject. On a
// list page ←/→ move along the tabs at once.
func TestTheArrowsMoveAlongTheTabs(t *testing.T) {
	f := &fakeHelm{city: peopleCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	if m.scr != composeScreen || m.focus != subjectField {
		t.Fatalf("the form opened on page %d with the focus on %d", m.scr, m.focus)
	}
	v := sgr.ReplaceAllString(m.composeView(), "")
	if !strings.Contains(v, tabRow) || !strings.Contains(v, "↑ to the tabs") {
		t.Fatalf("the start page's head:\n%s", v)
	}
	m.Update(key(tea.KeyUp))
	if m.focus != tabsField || m.scr != composeScreen {
		t.Fatalf("↑ from the subject: focus %d, page %d", m.focus, m.scr)
	}
	if v := sgr.ReplaceAllString(m.composeView(), ""); !strings.Contains(v, "←/→ another page · ↓ back to the subject") {
		t.Fatalf("the start page's head with the tabs in focus:\n%s", v)
	}
	typeText(m, "tk")
	if m.ref() != "" {
		t.Fatalf("typing on the tabs reached the subject: %q", m.ref())
	}
	for _, step := range []struct {
		k    tea.KeyPressMsg
		want screen
	}{
		{key(tea.KeyRight), returnScreen},
		{key(tea.KeyRight), peopleScreen},
		{key(tea.KeyRight), composeScreen},
		{key(tea.KeyLeft), peopleScreen},
		{key(tea.KeyLeft), returnScreen},
	} {
		if m.Update(step.k); m.scr != step.want {
			t.Fatalf("%s moved to page %d, want %d", step.k, m.scr, step.want)
		}
	}
	m.Update(key(tea.KeyLeft))
	if m.scr != composeScreen || m.focus != tabsField {
		t.Fatalf("← from the return list: page %d, focus %d", m.scr, m.focus)
	}
	for _, k := range []tea.KeyPressMsg{key(tea.KeyDown), key(tea.KeyEnter), key(tea.KeyTab)} {
		m.setFocus(tabsField)
		if m.Update(k); m.focus != subjectField {
			t.Fatalf("%s from the tabs: focus %d", k, m.focus)
		}
	}
	m.Update(key(tea.KeyTab))
	if m.focus != questionField {
		t.Fatalf("Tab from the subject: focus %d", m.focus)
	}

	m = newForm(t, f, Options{Return: true})
	loadCity(m)
	if m.scr != returnScreen {
		t.Fatalf("--return opened on page %d", m.scr)
	}
	if v := sgr.ReplaceAllString(m.returnView(), ""); !strings.Contains(v, tabRow) || !strings.Contains(v, "←/→ another page") {
		t.Fatalf("the return list's head:\n%s", v)
	}
}

// tabRow is the row of tabs as each page shows it, each tab with its key.
const tabRow = " Ctrl+N Start a conversation │ Ctrl+R Return to a conversation │ Ctrl+P People "

// Each page's key goes straight to its page, from each page and from each field
// of the start page, and the key of the page on screen does nothing. The start
// page comes back as it was left: the subject and the question as typed, and
// the focus in the field it was in.
func TestEachPagesKeyGoesStraightToIt(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Queued, Title: "an open question"}}
	f := &fakeHelm{about: map[string]About{"tk-a": a}, city: peopleCity()}
	for _, from := range []field{subjectField, questionField, modelField, attachField, contextField, tabsField} {
		m := newForm(t, f, Options{Subject: "tk-a"})
		loadCity(m)
		settle(m)
		typeText(m, "one\ntwo")
		if from == tabsField {
			focusOn(t, m, subjectField)
			m.Update(key(tea.KeyUp))
		} else {
			focusOn(t, m, from)
		}
		if m.focus != from {
			t.Fatalf("could not reach field %d", from)
		}
		for i, st := range []struct {
			k    tea.KeyPressMsg
			want screen
		}{
			{ctrl('n'), composeScreen},
			{ctrl('r'), returnScreen},
			{ctrl('r'), returnScreen},
			{ctrl('p'), peopleScreen},
			{ctrl('p'), peopleScreen},
			{ctrl('n'), composeScreen},
			{ctrl('p'), peopleScreen},
			{ctrl('r'), returnScreen},
			{ctrl('n'), composeScreen},
		} {
			was := m.scr
			_, cmd := m.Update(st.k)
			if was == st.want && cmd != nil {
				t.Fatalf("from field %d, step %d: %s on its own page asked for a command", from, i, st.k)
			}
			deliver(m, cmd)
			if m.scr != st.want || m.focus != from {
				t.Fatalf("from field %d, step %d: %s reached page %d with the focus on %d, want page %d", from, i, st.k, m.scr, m.focus, st.want)
			}
			if v := sgr.ReplaceAllString(m.View().Content, ""); !strings.Contains(v, tabRow) {
				t.Fatalf("from field %d, step %d: page %d does not show each tab's key:\n%s", from, i, m.scr, v)
			}
		}
		if m.ref() != "tk-a" || m.question.Value() != "one\ntwo" || m.modelName() != "claude-opus" || !m.attach {
			t.Fatalf("from field %d: the start page came back with subject %q, question %q, model %q, attach %v", from, m.ref(), m.question.Value(), m.modelName(), m.attach)
		}
	}
}

// In the question Ctrl+N and Ctrl+P go to their pages, ahead of the text box,
// which binds them to the line below and above, and ↓ and ↑ still move between
// its lines. Back on the start page the cursor is where it was in the question.
func TestTheQuestionsArrowsStillMoveItsCursor(t *testing.T) {
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}, city: peopleCity()}
	m := newForm(t, f, Options{Subject: "tk-a"})
	loadCity(m)
	settle(m)
	typeText(m, "one\ntwo")
	line := func(want int, after string) {
		t.Helper()
		if m.scr != composeScreen || m.focus != questionField || m.question.ta.Line() != want {
			t.Fatalf("after %s: page %d, focus %d, the cursor on line %d, want line %d of the question", after, m.scr, m.focus, m.question.ta.Line(), want)
		}
	}
	m.Update(key(tea.KeyUp))
	line(0, "↑")
	m.Update(ctrl('n'))
	line(0, "Ctrl+N")
	m.Update(key(tea.KeyDown))
	line(1, "↓")
	if m.Update(ctrl('p')); m.scr != peopleScreen {
		t.Fatalf("Ctrl+P in the question reached page %d", m.scr)
	}
	m.Update(ctrl('n'))
	line(1, "Ctrl+P and Ctrl+N")
	m.Update(key(tea.KeyUp))
	line(0, "↑ back on the start page")
}

// A submit's progress is no page, so while a save runs the pages' keys do
// nothing.
func TestThePagesKeysDoNothingWhileASaveRuns(t *testing.T) {
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}, city: peopleCity(),
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	loadCity(m)
	settle(m)
	typeText(m, "q")
	if m.Update(ctrl('s')); m.scr != progressScreen || !m.saving {
		t.Fatalf("Ctrl+S: page %d, saving %v", m.scr, m.saving)
	}
	for _, k := range []tea.KeyPressMsg{ctrl('n'), ctrl('r'), ctrl('p')} {
		if _, cmd := m.Update(k); cmd != nil || m.scr != progressScreen {
			t.Fatalf("%s while the save runs: page %d", k, m.scr)
		}
	}
}

// The People page lists mechanik and each rig's Product Owner by its rig's
// name and prefix, each with its session's state as Gas City gives it, and
// says what Enter opens for the seat picked.
func TestThePeoplePageListsTheSeatsWithTheirState(t *testing.T) {
	f := &fakeHelm{city: peopleCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	m.Update(key(tea.KeyUp))
	m.Update(key(tea.KeyLeft)) // the tabs wrap around to the last
	if m.scr != peopleScreen {
		t.Fatalf("↑ ← reached page %d", m.scr)
	}
	v := sgr.ReplaceAllString(m.peopleView(), "")
	for _, want := range []string{
		fmt.Sprintf("› %-22s mechanik", "active, attached"),
		fmt.Sprintf("  %-22s Product Owner  %-10s  tk", "no session", "gc-toolkit"),
		fmt.Sprintf("  %-22s Product Owner  %-10s  hb", "asleep", "harbor"),
		fmt.Sprintf("  %-22s Product Owner  %-10s  pz", "rig suspended", "paused"),
		fmt.Sprintf("  %-22s Product Owner  %-10s  dx", "active", "docs"),
		"Opens  ✓ mechanik, the city's standing conversation: Enter runs gc-helm mechanik, which attaches to its session, starting it first when it is not running.",
		"give the sitting its purpose once you are in it",
		"↑/↓ choose · Enter opens",
	} {
		if !strings.Contains(v, want) {
			t.Fatalf("the People page does not show %q:\n%s", want, v)
		}
	}
	m.Update(key(tea.KeyDown))
	if v := sgr.ReplaceAllString(m.peopleView(), ""); !strings.Contains(v, "Opens  ✓ the Product Owner of rig gc-toolkit: Enter runs gc-helm po --rig gc-toolkit") {
		t.Fatalf("the People page does not say what Enter opens for gc-toolkit's Product Owner:\n%s", v)
	}

	m = newForm(t, &fakeHelm{cityErr: errors.New("gc-helm: conversations: could not read 'gc session list'")}, Options{})
	loadCity(m)
	m.Update(key(tea.KeyUp))
	m.Update(key(tea.KeyLeft))
	if v := m.peopleView(); !strings.Contains(v, "The seats did not read: gc-helm: conversations: could not read 'gc session list'") {
		t.Fatalf("a read that failed:\n%s", v)
	}
}

// A read whose agent roster did not read lists no seat, and the People page
// says the seats did not read, while the return list shows the conversations
// the read gave.
func TestARosterThatDidNotReadListsNoSeat(t *testing.T) {
	c := rigCity()
	c.Conversations = []Conversation{{ID: "tk-c1", Rig: "gc-toolkit", Title: "a conversation", Readiness: Ready}}
	c.RosterUnread = true
	m := newForm(t, &fakeHelm{city: c}, Options{})
	loadCity(m)
	toPage(t, m, peopleScreen)
	v := sgr.ReplaceAllString(m.peopleView(), "")
	if !strings.Contains(v, "The seats did not read: the city's agent roster (gc agent list), which names each seat's session, could not be read.") || strings.Contains(v, "No seat is listed.") {
		t.Fatalf("the People page of a read whose roster did not read:\n%s", v)
	}
	if v := sgr.ReplaceAllString(m.returnView(), ""); !strings.Contains(v, "tk-c1") || strings.Contains(v, "did not read") {
		t.Fatalf("the return list of a read whose roster did not read:\n%s", v)
	}
}

// Enter opens the seat picked by its own verb once the form has left the
// terminal: mechanik by gc-helm mechanik and a rig's Product Owner by gc-helm
// po --rig, whether or not the rig carries a converse template. Nothing is
// looked up, saved or started.
func TestEnterOpensTheSeatPicked(t *testing.T) {
	for _, c := range []struct {
		downs int
		verb  string
	}{
		{0, "mechanik"},
		{1, "po --rig gc-toolkit"},
		{2, "po --rig harbor"},
		{4, "po --rig docs"},
	} {
		t.Run(c.verb, func(t *testing.T) {
			f := &fakeHelm{city: peopleCity()}
			m := newForm(t, f, Options{})
			loadCity(m)
			toPage(t, m, peopleScreen)
			for range c.downs {
				m.Update(key(tea.KeyDown))
			}
			_, cmd := m.Update(key(tea.KeyEnter))
			if !isQuit(cmd) || m.Attach() == nil || strings.Join(f.seats, "|") != c.verb {
				t.Fatalf("Enter: left %v, seats %v, want %q (status %q)", isQuit(cmd), f.seats, c.verb, m.status)
			}
			if len(f.abouts) != 0 || len(f.saves) != 0 || len(f.starts) != 0 || len(f.attaches) != 0 {
				t.Fatalf("opening a seat read %v, saved %v, started %v, attached %v", f.abouts, f.saves, f.starts, f.attaches)
			}
			if m.Leave() != "" {
				t.Fatalf("the note once the form left for the seat = %q", m.Leave())
			}
			if _, again := m.Update(key(tea.KeyEnter)); again != nil || len(f.seats) != 1 || m.attachTo("tk-c1", "") != nil || len(f.attaches) != 0 {
				t.Fatalf("a second hand-off ran: seats %v, attaches %v", f.seats, f.attaches)
			}
		})
	}
}

// A suspended rig's Product Owner is listed with why it cannot start. Enter
// opens nothing there: it says why and reads the rigs again, so the next Enter
// opens it once the rig has resumed.
func TestASuspendedRigsProductOwnerIsNotOpened(t *testing.T) {
	f := &fakeHelm{city: peopleCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	toPage(t, m, peopleScreen)
	for range 3 {
		m.Update(key(tea.KeyDown))
	}
	why := "rig paused is suspended, so its Product Owner cannot start until the rig resumes (gc rig resume paused)"
	if v := sgr.ReplaceAllString(m.peopleView(), ""); !strings.Contains(v, "Opens  ✗ "+why) {
		t.Fatalf("the People page does not say why:\n%s", v)
	}
	_, cmd := m.Update(key(tea.KeyEnter))
	if isQuit(cmd) || len(f.seats) != 0 || m.status != "Not opened: "+why+". Reading the rigs again." {
		t.Fatalf("Enter on a suspended rig's Product Owner: seats %v, status %q", f.seats, m.status)
	}
	if v := sgr.ReplaceAllString(m.peopleView(), ""); !strings.Contains(v, m.status) {
		t.Fatalf("the People page does not show the status:\n%s", v)
	}
	f.city = peopleCity()
	f.city.Rigs[2].Suspended = false
	deliver(m, cmd)
	if _, cmd := m.Update(key(tea.KeyEnter)); !isQuit(cmd) || strings.Join(f.seats, "|") != "po --rig paused" {
		t.Fatalf("Enter once the rig resumed: seats %v, status %q", f.seats, m.status)
	}
}

// The People page reads the city again while it is on screen, and its pick
// stays on the seat picked when the rigs change. A seat that leaves the list
// leaves nothing picked, so Enter opens nothing until ↑/↓ picks again.
func TestThePeoplePageKeepsItsPickOnASeat(t *testing.T) {
	f := &fakeHelm{city: peopleCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	toPage(t, m, peopleScreen)
	if !m.ticking {
		t.Fatalf("the People page schedules no refresh")
	}
	m.Update(key(tea.KeyDown))
	m.Update(key(tea.KeyDown))
	if m.seatSel != "po harbor" {
		t.Fatalf("picked %q, want harbor's po", m.seatSel)
	}
	read := func() {
		t.Helper()
		_, next := m.Update(cityTickMsg{})
		if next == nil {
			t.Fatalf("the People page did not read the city again")
		}
		deliver(m, next)
	}
	all := peopleCity().Seats
	f.city.Seats = []Seat{all[0], all[2], all[3], all[4]}
	read()
	if m.seatSel != "po harbor" || m.seatAt != 1 {
		t.Fatalf("after gc-toolkit's seat left: picked %q at %d", m.seatSel, m.seatAt)
	}
	f.city.Seats = []Seat{all[0], all[3], all[4]}
	read()
	v := sgr.ReplaceAllString(m.peopleView(), "")
	if !strings.Contains(v, "The seat picked is no longer listed") || strings.Contains(v, "› ") || strings.Contains(v, "Opens") {
		t.Fatalf("after the seat picked left:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd != nil || len(f.seats) != 0 {
		t.Fatalf("Enter with nothing picked opened %v", f.seats)
	}
	m.Update(key(tea.KeyDown))
	if m.seatSel != "po paused" {
		t.Fatalf("↓ picked %q, want the row now in the seat's place", m.seatSel)
	}
	m.Update(key(tea.KeyLeft))
	m.Update(key(tea.KeyLeft))
	if _, next := m.Update(cityTickMsg{}); next != nil || m.ticking {
		t.Fatalf("the start page kept reading the city")
	}
}

// The subject takes no seat: mechanik or <rig>/po typed there is a reference
// like any other, looked up as one, and Ctrl+S opens no seat.
func TestTheSubjectTakesNoSeat(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{})
	if d, st := m.where(); st != refused || strings.Contains(d, "mechanik") || strings.Contains(d, "Product Owner") {
		t.Fatalf("an empty subject's line = %q", d)
	}
	for _, typed := range []string{"mechanik", "tk/po"} {
		t.Run(typed, func(t *testing.T) {
			why := "gc-helm: conversations: bead not found: '" + typed + "' — no rig ledger answers for that id. Nothing read."
			f := &fakeHelm{city: peopleCity(), aboutErr: map[string]error{typed: errors.New(why)}}
			m := newForm(t, f, Options{})
			loadCity(m)
			typeText(m, typed)
			_, cmd := m.Update(debounceMsg{seq: m.seq})
			deliver(m, cmd)
			if strings.Join(f.abouts, " ") != typed {
				t.Fatalf("lookups = %v", f.abouts)
			}
			focusOn(t, m, questionField)
			settle(m) // leaving the subject reads a lookup that failed again
			typeText(m, "a question")
			m.Update(ctrl('s'))
			if len(f.seats) != 0 || len(f.saves) != 0 || !strings.HasPrefix(m.status, "Not saved: "+why) {
				t.Fatalf("Ctrl+S: seats %v, saves %v, status %q", f.seats, f.saves, m.status)
			}
		})
	}
}

// A question typed on the start page is kept in a file when the form leaves
// for a seat, since a seat takes no question, and the note says where.
func TestOpeningASeatKeepsTheUnsavedQuestion(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{city: peopleCity()}
	m := newForm(t, f, Options{DraftDir: dir})
	loadCity(m)
	focusOn(t, m, questionField)
	typeText(m, "is the deacon stuck?")
	toPage(t, m, peopleScreen)
	if _, cmd := m.Update(key(tea.KeyEnter)); !isQuit(cmd) || strings.Join(f.seats, "|") != "mechanik" {
		t.Fatalf("Enter: seats %v", f.seats)
	}
	files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
	if len(files) != 1 || !strings.Contains(m.Leave(), files[0]) {
		t.Fatalf("drafts %v, note %q", files, m.Leave())
	}
}
