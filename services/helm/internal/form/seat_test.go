package form

import (
	"os"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

// A seat typed as the subject, mechanik or a rig's po by the rig's name or
// prefix, ignoring case, is opened by its own verb once the form has left the
// terminal. It is never looked up, and nothing is saved or started.
func TestASeatTheSubjectNamesIsOpenedByItsVerb(t *testing.T) {
	for _, c := range []struct{ typed, verb string }{
		{"mechanik", "mechanik"},
		{" Mechanik ", "mechanik"},
		{"tk/po", "po --rig gc-toolkit"},
		{"gc-toolkit/po", "po --rig gc-toolkit"},
		{"Harbor / PO", "po --rig harbor"},
	} {
		t.Run(c.typed, func(t *testing.T) {
			f := &fakeHelm{city: rigCity()}
			m := newForm(t, f, Options{})
			loadCity(m)
			typeText(m, c.typed)
			if _, cmd := m.Update(debounceMsg{seq: m.seq}); cmd != nil {
				t.Fatalf("%q was looked up once the typing stopped", c.typed)
			}
			if _, st := m.where(); st != settled {
				d, _ := m.where()
				t.Fatalf("%q is not settled: %q", c.typed, d)
			}
			_, cmd := m.Update(ctrl('s'))
			if !isQuit(cmd) || m.Attach() == nil {
				t.Fatalf("Ctrl+S on %q did not leave the form to open the seat (status %q)", c.typed, m.status)
			}
			if strings.Join(f.seats, "|") != c.verb {
				t.Fatalf("seats = %v, want %q", f.seats, c.verb)
			}
			if len(f.abouts) != 0 || len(f.saves) != 0 || len(f.starts) != 0 || len(f.attaches) != 0 {
				t.Fatalf("opening a seat read %v, saved %v, started %v, attached %v", f.abouts, f.saves, f.starts, f.attaches)
			}
			if m.Leave() != "" {
				t.Fatalf("the note once the form left for the seat = %q", m.Leave())
			}
		})
	}
}

// The screen says what Ctrl+S opens and that the sitting's purpose is given in
// it. A seat runs on its own model and is attached to, so the model and the
// attach are shown and are no fields.
func TestTheScreenSaysWhatASeatOpens(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	typeText(m, "tk/po")
	v := m.composeView()
	for _, want := range []string{"Ctrl+S attach to the po", "Opens", "the po of rig gc-toolkit", "give the sitting its purpose once you are in it", "the seat's own", "yes, to the seat's session"} {
		if !strings.Contains(v, want) {
			t.Fatalf("the screen does not say %q:\n%s", want, v)
		}
	}
	if l := marked(strings.Split(v, "\n"), "Rig"); !strings.Contains(l, "gc-toolkit") {
		t.Fatalf("the screen does not show the po's rig:\n%s", v)
	}
	if strings.Contains(v, "Files as") || strings.Contains(v, "‹") {
		t.Fatalf("the screen offers a seat what only a conversation takes:\n%s", v)
	}
	if fs := m.fields(); len(fs) != 2 || fs[0] != subjectField || fs[1] != questionField {
		t.Fatalf("fields with a seat named = %v", fs)
	}
	m = newForm(t, &fakeHelm{}, Options{})
	typeText(m, "mechanik")
	if v := m.composeView(); !strings.Contains(v, "Ctrl+S attach to mechanik") || !strings.Contains(v, "mechanik, the city's standing conversation") {
		t.Fatalf("the screen does not say it opens mechanik:\n%s", v)
	}
}

// An empty subject's line names the seats beside a subject and a rig.
func TestAnEmptySubjectNamesTheSeats(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{})
	if d, st := m.where(); st != refused || !strings.Contains(d, "<rig>/po for a rig's po, or mechanik") {
		t.Fatalf("an empty subject's line = %q", d)
	}
}

// A rig's po is opened once the city's rigs say which rig it is and that the
// rig runs. Until they have read, Ctrl+S opens nothing; a rig the city has
// not, a name several rigs carry, and a suspended rig are each refused.
func TestARigsPoIsOpenedOnceTheRigIsKnownAndRuns(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{})
	read := m.Init() // the city's rigs, read as the form opens and not yet answered
	typeText(m, "tk/po")
	if _, cmd := m.Update(ctrl('s')); cmd != nil || len(f.seats) != 0 || m.status != "Not opened: the po of rig tk: checking the rig…" {
		t.Fatalf("Ctrl+S before the rigs read: seats %v, status %q", f.seats, m.status)
	}
	deliver(m, read)
	if _, cmd := m.Update(ctrl('s')); !isQuit(cmd) || strings.Join(f.seats, "|") != "po --rig gc-toolkit" {
		t.Fatalf("Ctrl+S once the rigs read: seats %v, status %q", f.seats, m.status)
	}

	city := rigCity()
	city.Rigs = append(city.Rigs, Rig{Name: "hb", Prefix: "hx", Converse: true})
	for _, c := range []struct{ typed, why string }{
		{"nowhere/po", "rig nowhere is not a rig of this city"},
		{"hb/po", "hb names more than one rig (harbor, hb)"},
		{"paused/po", "rig paused is suspended, so its po cannot start until the rig resumes (gc rig resume paused)"},
	} {
		f := &fakeHelm{city: city}
		m := newForm(t, f, Options{})
		loadCity(m)
		typeText(m, c.typed)
		m.Update(ctrl('s'))
		if len(f.seats) != 0 || !strings.Contains(m.status, "Not opened: "+c.why) {
			t.Fatalf("%s: seats %v, status %q", c.typed, f.seats, m.status)
		}
	}

	f = &fakeHelm{cityErr: os.ErrDeadlineExceeded}
	m = newForm(t, f, Options{})
	loadCity(m)
	typeText(m, "tk/po")
	m.Update(ctrl('s'))
	if len(f.seats) != 0 || !strings.Contains(m.status, "the rigs did not read") {
		t.Fatalf("rigs that did not read: seats %v, status %q", f.seats, m.status)
	}
}

// A seat takes no question from the form, since Gas City's attach carries no
// message, so a question typed is refused rather than dropped, and once it is
// cleared Ctrl+S opens the seat.
func TestASeatTakesNoQuestion(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	typeText(m, "mechanik")
	focusOn(t, m, questionField)
	typeText(m, "the deacon looks stuck")
	if _, cmd := m.Update(ctrl('s')); isQuit(cmd) || len(f.seats) != 0 || !strings.HasPrefix(m.status, "Not opened: a seat takes no question from the form") {
		t.Fatalf("Ctrl+S with a question: seats %v, status %q", f.seats, m.status)
	}
	for range len("the deacon looks stuck") {
		m.Update(key(tea.KeyBackspace))
	}
	if _, cmd := m.Update(ctrl('s')); !isQuit(cmd) || strings.Join(f.seats, "|") != "mechanik" {
		t.Fatalf("Ctrl+S once the question was cleared: seats %v, status %q", f.seats, m.status)
	}
}

// Only text the operator typed is read as a seat: a subject the command line
// named is looked up, as engage looks it up.
func TestAGivenSubjectIsNeverASeat(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{Subject: "mechanik"})
	deliver(m, m.Init())
	if m.isSeat() || strings.Join(f.abouts, " ") != "mechanik" {
		t.Fatalf("a given subject: seat %v, lookups %v", m.isSeat(), f.abouts)
	}
}

// One hand-off runs: a second Ctrl+S, or an attach once the seat's verb was
// kept, runs nothing more.
func TestOneHandOffRuns(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{})
	loadCity(m)
	typeText(m, "mechanik")
	m.Update(ctrl('s'))
	if _, cmd := m.Update(ctrl('s')); cmd != nil || len(f.seats) != 1 {
		t.Fatalf("a second Ctrl+S opened seats %v", f.seats)
	}
	if cmd := m.attachTo("tk-c1", ""); cmd != nil || len(f.attaches) != 0 {
		t.Fatalf("an attach after the seat's hand-off ran: %v", f.attaches)
	}
}
