package form

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
)

// fakeHelm answers the form's reads and records its writes. A read runs only
// when the test runs the command the form returned for it, so a test decides
// what has loaded when.
type fakeHelm struct {
	about    map[string]About
	aboutErr map[string]error
	city     City
	saveResp Saved
	saveErr  error
	startErr error

	saves    []SaveRequest
	starts   []string
	attaches []string
}

func (f *fakeHelm) About(_ context.Context, ref string) (About, error) {
	if err := f.aboutErr[ref]; err != nil {
		return About{}, err
	}
	return f.about[ref], nil
}
func (f *fakeHelm) City(context.Context) (City, error) { return f.city, nil }
func (f *fakeHelm) Save(_ context.Context, req SaveRequest) (Saved, error) {
	f.saves = append(f.saves, req)
	return f.saveResp, f.saveErr
}
func (f *fakeHelm) Start(_ context.Context, conv, model string) error {
	f.starts = append(f.starts, conv+" "+model)
	return f.startErr
}
func (f *fakeHelm) AttachCommand(conv string) *exec.Cmd {
	f.attaches = append(f.attaches, conv)
	return exec.Command("true")
}

func rigCity() City {
	return City{Rigs: []Rig{
		{Name: "gc-toolkit", Converse: true},
		{Name: "gascity", Converse: true},
		{Name: "paused", Converse: true, Suspended: true},
		{Name: "docs", Converse: false},
	}}
}

func subjectAbout(id, rig string) About {
	return About{Ref: id, Subject: Subject{ID: id, Title: "the subject " + id, Status: "open", IssueType: "task", Rig: rig}, HoldsRead: true}
}

func newForm(t *testing.T, f *fakeHelm, opt Options) *Model {
	t.Helper()
	if opt.Models == nil {
		opt.Models = []string{"opus", "fable", "codex"}
	}
	opt.Debounce = time.Millisecond
	opt.Poll = time.Millisecond
	return New(context.Background(), f, opt)
}

func key(code rune) tea.KeyPressMsg { return tea.KeyPressMsg{Code: code} }
func ctrl(r rune) tea.KeyPressMsg   { return tea.KeyPressMsg{Code: r, Mod: tea.ModCtrl} }

// typeText types s into the focused field, a newline as Enter.
func typeText(m *Model, s string) {
	for _, r := range s {
		if r == '\n' {
			m.Update(key(tea.KeyEnter))
			continue
		}
		m.Update(tea.KeyPressMsg{Code: r, Text: string(r)})
	}
}

// deliver runs a command and hands the form's own messages back to it, through
// batches and ticks, the way the bubbletea runtime would. It stops at the
// readiness poll and at runtime messages such as the cursor's blink, which
// repeat for as long as the form runs, so a test that wants a poll runs it.
func deliver(m *Model, cmd tea.Cmd) { deliverN(m, cmd, 0) }

func deliverN(m *Model, cmd tea.Cmd, depth int) {
	if cmd == nil || depth > 40 {
		return
	}
	msg := cmd()
	if batch, ok := msg.(tea.BatchMsg); ok {
		for _, c := range batch {
			deliverN(m, c, depth+1)
		}
		return
	}
	switch msg.(type) {
	case aboutMsg, cityMsg, debounceMsg, savedMsg, startedMsg, readyMsg, attachedMsg:
		_, next := m.Update(msg)
		deliverN(m, next, depth+1)
	}
}

func loadCity(m *Model) { deliver(m, m.loadCity()) }

// settle looks up the subject field as it reads now and delivers the answer.
func settle(m *Model) {
	ref := m.ref()
	delete(m.lookups, ref)
	deliver(m, m.lookup(ref))
}

func focusOn(t *testing.T, m *Model, f field) {
	t.Helper()
	for i := 0; i < 8 && m.focus != f; i++ {
		m.Update(key(tea.KeyTab))
	}
	if m.focus != f {
		t.Fatalf("could not reach field %d (fields %v)", f, m.fields())
	}
}

func TestTypingIsHandledWhileLookupsRun(t *testing.T) {
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	initCmd := m.Init() // the city read and the subject lookup, not run yet
	if initCmd == nil || !m.lookups["tk-a"].pending || !m.cityBusy {
		t.Fatalf("Init should start the city read and the subject lookup")
	}
	typeText(m, "first line\nsecond")
	if got := m.question.Value(); got != "first line\nsecond" {
		t.Fatalf("question while lookups run = %q", got)
	}
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "looking up tk-a") {
		t.Fatalf("destination before the lookup lands = %q, %v", dest, ok)
	}
	deliver(m, initCmd)
	if dest, ok := m.destination(); !ok || !strings.Contains(dest, "rig gc-toolkit") {
		t.Fatalf("destination after the lookup = %q, %v", dest, ok)
	}
	if got := m.question.Value(); got != "first line\nsecond" {
		t.Fatalf("the lookup changed the question: %q", got)
	}
}

func TestALookupForAnEarlierSubjectSettlesNothing(t *testing.T) {
	f := &fakeHelm{about: map[string]About{
		"tk-a": subjectAbout("tk-a", "gc-toolkit"),
		"gc-b": subjectAbout("gc-b", "gascity"),
	}}
	m := newForm(t, f, Options{})
	typeText(m, "tk-a")
	staleCmd := m.lookup("tk-a") // asked for while the field read tk-a
	for range 4 {
		m.Update(key(tea.KeyBackspace))
	}
	typeText(m, "gc-b")
	deliver(m, staleCmd) // tk-a's answer arrives after the edit
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "looking up gc-b") {
		t.Fatalf("destination for gc-b after tk-a's late answer = %q, %v", dest, ok)
	}
	focusOn(t, m, questionField)
	typeText(m, "a question")
	m.Update(ctrl('s'))
	if len(f.saves) != 0 {
		t.Fatalf("saved before gc-b was verified: %+v", f.saves)
	}
	if !strings.Contains(m.status, "Not saved") {
		t.Fatalf("status = %q", m.status)
	}
	settle(m)
	f.saveResp = Saved{Subject: "gc-b", Conversation: "gc-c", Filed: true}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Ref != "gc-b" {
		t.Fatalf("saves = %+v, want one onto gc-b", f.saves)
	}
}

func TestANewTopicNeedsARigTheOperatorChose(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{})
	focusOn(t, m, questionField)
	typeText(m, "a new topic")
	m.Update(ctrl('s'))
	if len(f.saves) != 0 {
		t.Fatalf("saved with the rigs unread: %+v", f.saves)
	}
	loadCity(m)
	if _, ok := m.destination(); ok {
		t.Fatalf("a rig was chosen without the operator")
	}
	focusOn(t, m, rigField)
	m.Update(key(tea.KeyRight))
	if m.rig != "gc-toolkit" {
		t.Fatalf("rig after one → = %q", m.rig)
	}
	m.Update(key(tea.KeyRight))
	m.Update(key(tea.KeyRight)) // paused and docs cannot host a sitting, so it wraps
	if m.rig != "gc-toolkit" {
		t.Fatalf("rig after three → = %q, want a hosting rig", m.rig)
	}
	m.Update(key(tea.KeyRight))
	// A later read of the city with the rigs in another order leaves the choice.
	f.city = City{Rigs: []Rig{{Name: "gascity", Converse: true}, {Name: "gc-toolkit", Converse: true}}}
	loadCity(m)
	if m.rig != "gascity" {
		t.Fatalf("a city reload changed the chosen rig to %q", m.rig)
	}
	f.saveResp = Saved{Subject: "gc-new", Conversation: "gc-conv", Filed: true}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Rig != "gascity" || f.saves[0].Ref != "" {
		t.Fatalf("saves = %+v, want one new subject in gascity", f.saves)
	}
}

func TestAPreFilledRigThatCannotHostIsRefused(t *testing.T) {
	f := &fakeHelm{city: rigCity()}
	m := newForm(t, f, Options{Rig: "paused"})
	loadCity(m)
	typeText(m, "question")
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "suspended") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
}

func TestTheQuestionIsSavedExactlyAsTyped(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	want := "Why does the refinery hold siblings?\n\n  - indented point  \nlast line, über ünïcödé"
	typeText(m, "Why does the refinery hold siblings?\n\n  - indented point  \n")
	m.Update(tea.PasteMsg{Content: "last line, über ünïcödé"})
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 {
		t.Fatalf("saves = %+v", f.saves)
	}
	if got := f.saves[0].Question; got != want {
		t.Fatalf("saved question = %q, want %q", got, want)
	}
	if len(want) <= 500 && !strings.Contains(want, "\n") {
		t.Fatalf("the case must carry newlines")
	}
}

func TestSavedIsSaidBeforeTheSittingIsReady(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "a question")
	_, saveCmd := m.Update(ctrl('s'))
	if v := m.progressView(); !strings.Contains(v, "saving your question") || strings.Contains(v, "saved:") {
		t.Fatalf("before the save answers the screen says:\n%s", v)
	}
	_, startCmd := m.Update(saveCmd())
	if v := m.progressView(); !strings.Contains(v, "saved: conversation tk-c1") || !strings.Contains(v, "starting its sitting on opus") {
		t.Fatalf("after the save, before the start, the screen says:\n%s", v)
	}
	if len(f.starts) != 0 {
		t.Fatalf("the start ran before its command did")
	}
	_, pollCmd := m.Update(startCmd())
	if len(f.starts) != 1 || f.starts[0] != "tk-c1 opus" {
		t.Fatalf("starts = %v", f.starts)
	}
	// The sitting is preparing, then ready.
	f.about["tk-c1"] = About{Subject: Subject{ID: "tk-a"}, Conversations: []Conversation{{ID: "tk-c1", Readiness: Preparing}}}
	_, readCmd := m.Update(pollCmd())
	_, next := m.Update(readCmd())
	if m.readiness != Preparing || next == nil {
		t.Fatalf("readiness = %q, next poll %v", m.readiness, next != nil)
	}
	f.about["tk-c1"] = About{Subject: Subject{ID: "tk-a"}, Conversations: []Conversation{{ID: "tk-c1", Readiness: Ready}}}
	_, readCmd = m.Update(next())
	_, last := m.Update(readCmd())
	if last != nil {
		t.Fatalf("a ready sitting is polled again")
	}
	if m.readiness != Ready || !strings.Contains(m.progressView(), "ready: the sitting has posted its framing") {
		t.Fatalf("readiness = %q:\n%s", m.readiness, m.progressView())
	}
	m.Update(key('q'))
	if !strings.Contains(m.Note(), "tk-c1") || !strings.Contains(m.Note(), "attach tk-c1") {
		t.Fatalf("note on leaving = %q", m.Note())
	}
}

func TestAFailedSaveKeepsTheQuestion(t *testing.T) {
	f := &fakeHelm{
		about:   map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveErr: &Refusal{Code: 4, Why: "gc-helm: open: could not create a conversation for 'tk-a'"},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "keep\nme")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.scr != composeScreen || m.question.Value() != "keep\nme" {
		t.Fatalf("after a failed save: screen %d, question %q", m.scr, m.question.Value())
	}
	if !strings.Contains(m.status, "could not create a conversation") || len(f.starts) != 0 {
		t.Fatalf("status = %q, starts %v", m.status, f.starts)
	}
}

func TestANewSubjectFiledWithoutItsConversationIsSavedOntoNext(t *testing.T) {
	f := &fakeHelm{
		city:     rigCity(),
		about:    map[string]About{"tk-new": subjectAbout("tk-new", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-new", Filed: false},
		saveErr:  &Refusal{Code: 4, Why: "gc-helm: open: subject tk-new was filed, but its conversation was not"},
	}
	m := newForm(t, f, Options{Rig: "gc-toolkit"})
	loadCity(m)
	typeText(m, "the question")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.ref() != "tk-new" || !strings.Contains(m.status, "tk-new was filed") {
		t.Fatalf("subject %q, status %q", m.ref(), m.status)
	}
	f.saveErr, f.saveResp = nil, Saved{Subject: "tk-new", Conversation: "tk-c", Filed: true}
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 2 || f.saves[1].Ref != "tk-new" || f.saves[1].Rig != "" || f.saves[1].Question != "the question" {
		t.Fatalf("second save = %+v, want the question onto tk-new", f.saves)
	}
}

func TestChoosingAnOpenConversationKeepsTheDraft(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Queued, Title: "an open question"}}
	f := &fakeHelm{about: map[string]About{"tk-a": a}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "my draft")
	focusOn(t, m, contextField)
	m.Update(key(tea.KeyDown))
	m.Update(key(tea.KeySpace))
	if m.choice != "tk-c1" || m.question.Value() != "my draft" {
		t.Fatalf("choice %q, question %q", m.choice, m.question.Value())
	}
	m.Update(ctrl('s'))
	if len(f.starts) != 0 || len(f.saves) != 0 || !strings.Contains(m.status, "not sent into an existing conversation") {
		t.Fatalf("a draft beside a chosen conversation: starts %v saves %v status %q", f.starts, f.saves, m.status)
	}
	// A new lookup of the same subject that drops the chosen conversation does
	// not move the choice.
	m.Update(key(tea.KeyUp))
	m.Update(key(tea.KeySpace))
	if m.choice != newChoice || m.question.Value() != "my draft" {
		t.Fatalf("choosing the new row: choice %q, question %q", m.choice, m.question.Value())
	}
	m.Update(key(tea.KeyDown))
	m.Update(key(tea.KeySpace))
	focusOn(t, m, questionField)
	for range len("my draft") {
		m.Update(key(tea.KeyBackspace))
	}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 0 || len(f.starts) != 1 || f.starts[0] != "tk-c1 opus" {
		t.Fatalf("continuing tk-c1: saves %v starts %v", f.saves, f.starts)
	}
}

func TestATypedConversationIdIsChosenUntilTheOperatorChooses(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversation = "tk-c1"
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Ended}}
	f := &fakeHelm{about: map[string]About{"tk-c1": a}}
	m := newForm(t, f, Options{Subject: "tk-c1"})
	deliver(m, m.lookup("tk-c1"))
	if m.choice != "tk-c1" {
		t.Fatalf("choice = %q, want the conversation the subject field named", m.choice)
	}
	m.choice, m.choiceTouched = newChoice, true
	delete(m.lookups, "tk-c1")
	deliver(m, m.lookup("tk-c1"))
	if m.choice != newChoice {
		t.Fatalf("a later lookup moved the operator's choice to %q", m.choice)
	}
}

func TestAnAmbiguousPRIsChosenExplicitly(t *testing.T) {
	f := &fakeHelm{about: map[string]About{
		"1446": {Ref: "1446", Candidates: []Candidate{{ID: "tk-a", Rig: "gc-toolkit", Title: "one"}, {ID: "gc-b", Rig: "gascity", Title: "two"}}},
		"gc-b": subjectAbout("gc-b", "gascity"),
	}}
	m := newForm(t, f, Options{Subject: "1446"})
	settle(m)
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "more than one") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	focusOn(t, m, contextField)
	m.Update(key(tea.KeyDown))
	_, cmd := m.Update(key(tea.KeySpace))
	if m.ref() != "gc-b" {
		t.Fatalf("subject after choosing = %q", m.ref())
	}
	deliver(m, cmd)
	if dest, ok := m.destination(); !ok || !strings.Contains(dest, "rig gascity") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
}

func TestARefusedSubjectIsShownAndNothingIsFiled(t *testing.T) {
	a := subjectAbout("hq-1", "loomington")
	a.Refusal = "converse is not available for 'hq-1': its rig 'loomington' carries no converse template."
	f := &fakeHelm{about: map[string]About{"hq-1": a}, aboutErr: map[string]error{"tk-gone": &Refusal{Code: 4, Why: "gc-helm: conversations: bead not found: 'tk-gone'"}}}
	m := newForm(t, f, Options{Subject: "hq-1"})
	settle(m)
	typeText(m, "q")
	m.Update(ctrl('s'))
	if len(f.saves) != 0 || !strings.Contains(m.status, "no converse template") {
		t.Fatalf("saves %v status %q", f.saves, m.status)
	}
	m.subject.SetValue("tk-gone")
	settle(m)
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "bead not found") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
}

func TestCancellingKeepsTheQuestionInAFile(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{}
	m := newForm(t, f, Options{Subject: "tk-a", DraftDir: filepath.Join(dir, "drafts")})
	typeText(m, "a thought\n  worth keeping ")
	m.Update(key(tea.KeyEscape))
	note := m.Note()
	files, _ := filepath.Glob(filepath.Join(dir, "drafts", "engage-draft-*.txt"))
	if len(files) != 1 || !strings.Contains(note, files[0]) {
		t.Fatalf("draft files %v, note %q", files, note)
	}
	b, _ := os.ReadFile(files[0])
	if string(b) != "a thought\n  worth keeping " {
		t.Fatalf("kept draft = %q", b)
	}
	if len(f.saves) != 0 {
		t.Fatalf("a cancel saved: %v", f.saves)
	}
}

func TestCancellingWithNowhereToKeepPrintsTheQuestion(t *testing.T) {
	m := newForm(t, &fakeHelm{}, Options{Subject: "tk-a", DraftDir: "/dev/null/nowhere"})
	typeText(m, "still here")
	m.Update(ctrl('c'))
	if !strings.HasSuffix(m.Note(), "still here") {
		t.Fatalf("note = %q", m.Note())
	}
}

func TestAStartThatFailsIsShownAndRetried(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
		startErr: errors.New("gc-helm: engage: rig 'gc-toolkit' is suspended"),
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if v := m.progressView(); !strings.Contains(v, "saved: conversation tk-c1") || !strings.Contains(v, "no sitting started") {
		t.Fatalf("screen:\n%s", v)
	}
	f.startErr = nil
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	if len(f.starts) != 2 || !m.started {
		t.Fatalf("starts %v started %v", f.starts, m.started)
	}
}

func TestTheReturnListPutsConversationsNoTerminalHoldsFirst(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: []Conversation{
		{ID: "tk-att", Readiness: Ready, CreatedAt: "2026-11-08T10:00:00Z", Session: &Session{Attached: true}},
		{ID: "tk-q", Readiness: Queued, CreatedAt: "2026-11-08T11:00:00Z"},
		{ID: "tk-old", Readiness: Ready, CreatedAt: "2026-11-08T09:00:00Z", Session: &Session{}},
		{ID: "tk-new", Readiness: Ready, CreatedAt: "2026-11-08T12:00:00Z", Session: &Session{}},
		{ID: "tk-prep", Readiness: Preparing, CreatedAt: "2026-11-08T12:30:00Z", Session: &Session{}},
		{ID: "tk-gone", Readiness: Ended, CreatedAt: "2026-11-08T08:00:00Z"},
	}}}
	m := newForm(t, f, Options{Return: true})
	loadCity(m)
	var got []string
	for _, c := range m.returnRows() {
		got = append(got, c.ID)
	}
	if want := "tk-new tk-old tk-prep tk-gone tk-q tk-att"; strings.Join(got, " ") != want {
		t.Fatalf("order = %v, want %s", got, want)
	}
	m.Update(key(tea.KeyDown))
	_, cmd := m.Update(key(tea.KeyEnter))
	if cmd == nil || len(f.attaches) != 1 || f.attaches[0] != "tk-old" {
		t.Fatalf("attach = %v", f.attaches)
	}
}

func TestTheModelDefaultIsShownAndOverridable(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	if v := m.composeView(); !strings.Contains(v, "opus") || !strings.Contains(v, "(default)") {
		t.Fatalf("compose view does not show the default model:\n%s", v)
	}
	focusOn(t, m, modelField)
	m.Update(key(tea.KeyRight))
	focusOn(t, m, questionField)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.starts) != 1 || f.starts[0] != "tk-c1 fable" {
		t.Fatalf("starts = %v", f.starts)
	}
}

func TestTheDestinationIsOnScreenBeforeSubmitting(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Gate = "tk-g"
	f := &fakeHelm{about: map[string]About{"tk-g": a}, saveResp: Saved{Subject: "tk-a", Conversation: "tk-c", Filed: true}}
	m := newForm(t, f, Options{Subject: "tk-g"})
	settle(m)
	if v := m.composeView(); !strings.Contains(v, "a conversation on tk-a") || !strings.Contains(v, "in rig gc-toolkit, answering gate tk-g") {
		t.Fatalf("compose view:\n%s", v)
	}
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Ref != "tk-g" {
		t.Fatalf("saves = %+v, want the conversation filed through the gate", f.saves)
	}
}
