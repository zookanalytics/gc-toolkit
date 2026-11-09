package form

import (
	"context"
	"errors"
	"fmt"
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
	cityErr  error
	saveResp Saved
	saveErr  error
	startErr error

	saves    []SaveRequest
	starts   []string
	attaches []string
	// attachArgs is the argv each attach would run, as Script builds it.
	attachArgs []string
}

func (f *fakeHelm) About(_ context.Context, ref string) (About, error) {
	if err := f.aboutErr[ref]; err != nil {
		return About{}, err
	}
	return f.about[ref], nil
}
func (f *fakeHelm) City(context.Context) (City, error) { return f.city, f.cityErr }
func (f *fakeHelm) Save(_ context.Context, req SaveRequest) (Saved, error) {
	f.saves = append(f.saves, req)
	return f.saveResp, f.saveErr
}
func (f *fakeHelm) Start(_ context.Context, conv, model string) error {
	f.starts = append(f.starts, conv+" "+model)
	return f.startErr
}
func (f *fakeHelm) AttachCommand(conv, model string) *exec.Cmd {
	f.attaches = append(f.attaches, conv)
	f.attachArgs = append(f.attachArgs, strings.Join(Script{Path: "gc-helm.sh"}.AttachCommand(conv, model).Args[1:], " "))
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
	return newFormOn(t, f, opt)
}

// newFormOn is newForm over any Helm, such as one whose save runs a Script.
func newFormOn(t *testing.T, h Helm, opt Options) *Model {
	t.Helper()
	if opt.Models == nil {
		opt.Models = []string{"opus", "fable", "codex"}
	}
	opt.Debounce = time.Millisecond
	opt.Poll = time.Millisecond
	opt.Refresh = time.Millisecond
	return New(context.Background(), h, opt)
}

// isQuit says whether cmd is the one that ends the program.
func isQuit(cmd tea.Cmd) bool {
	if cmd == nil {
		return false
	}
	_, ok := cmd().(tea.QuitMsg)
	return ok
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

// A save that filed the conversation and then failed, here because its reply
// onto the gate did not read back, leaves the question saved in that
// conversation. Nothing starts, and r sends the save again naming that
// conversation, which open completes rather than file a second one.
func TestAConversationFiledWhoseSaveFailedIsKeptAndSavedAgainNotFiledAgain(t *testing.T) {
	a := subjectAbout("tk-held", "gc-toolkit")
	a.Ref, a.Gate = "tk-gate", "tk-gate"
	f := &fakeHelm{
		about:    map[string]About{"tk-gate": a},
		saveResp: Saved{Subject: "tk-held", Conversation: "tk-c1", Filed: true},
		saveErr:  &Refusal{Code: 4, Why: "gc-helm: open: conversation tk-c1 is filed on tk-held, but its reply onto gate tk-gate did not read back. Add it by hand: gc bd dep add tk-c1 tk-gate --type replies-to"},
	}
	dir := t.TempDir()
	m := newForm(t, f, Options{Subject: "tk-gate", DraftDir: dir})
	settle(m)
	typeText(m, "the question")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.scr != progressScreen || m.saved == nil || m.saved.Conversation != "tk-c1" || len(f.starts) != 0 {
		t.Fatalf("after a save that filed tk-c1 and failed: screen %d, saved %+v, starts %v", m.scr, m.saved, f.starts)
	}
	v := m.progressView()
	if strings.Contains(v, "Not saved") || !strings.Contains(v, "saved: conversation tk-c1") || !strings.Contains(v, "reply onto gate tk-gate did not read back") {
		t.Fatalf("the screen should say tk-c1 holds the question and its reply is missing:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd != nil || len(f.attaches) != 0 {
		t.Fatalf("Enter attached %v to a conversation whose save did not complete", f.attaches)
	}
	if n := m.savedNote(); !strings.Contains(n, "tk-c1") || !strings.Contains(n, "did not complete") || !strings.Contains(n, "no sitting was started") {
		t.Fatalf("note = %q", n)
	}

	// A save again that does not answer keeps the conversation the first one filed.
	f.saveResp, f.saveErr = Saved{}, &Refusal{Code: 4, Why: "gc-helm: open: could not read the conversations on tk-held"}
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	if m.scr != progressScreen || m.saved == nil || m.saved.Conversation != "tk-c1" || !strings.Contains(m.saveErr, "could not read the conversations") {
		t.Fatalf("after a save again that did not answer: screen %d, saved %+v, saveErr %q", m.scr, m.saved, m.saveErr)
	}

	// A save again refused for good, as for a conversation closed since, says
	// why, and the hint promises only what r does either way.
	f.saveErr = &Refusal{Code: 4, Why: "gc-helm: open: conversation tk-c1 is not an open conversation about tk-held: it was closed since it was filed"}
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	v = m.progressView()
	if !strings.Contains(v, "it was closed since it was filed") || !strings.Contains(v, "r saves it again onto conversation tk-c1, which completes it or says why it cannot, and files no other.") || len(f.starts) != 0 {
		t.Fatalf("after a save again refused for good, starts %v:\n%s", f.starts, v)
	}

	// The next save again completes tk-c1 and starts it.
	f.saveResp, f.saveErr = Saved{Subject: "tk-held", Conversation: "tk-c1", Filed: true}, nil
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	if f.saves[0] != (SaveRequest{Ref: "tk-gate", Subject: "tk-held", Question: "the question"}) {
		t.Fatalf("save request = %+v", f.saves[0])
	}
	again := f.saves[0]
	again.Conversation = "tk-c1"
	if len(f.saves) != 4 || f.saves[1] != again || f.saves[2] != again || f.saves[3] != again {
		t.Fatalf("saves = %+v, want each save again to be the first naming tk-c1", f.saves)
	}
	if m.saveErr != "" || len(f.starts) != 1 || f.starts[0] != "tk-c1 opus" {
		t.Fatalf("after the save completed: saveErr %q, starts %v", m.saveErr, f.starts)
	}
	if files, _ := filepath.Glob(filepath.Join(dir, "*")); len(files) != 0 {
		t.Fatalf("a question a conversation holds was kept in a draft too: %v", files)
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
	// The candidate chosen is the reference the save sends.
	f.saveResp = Saved{Subject: "gc-b", Conversation: "gc-c", Filed: true}
	focusOn(t, m, questionField)
	typeText(m, "q")
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Ref != "gc-b" || f.saves[0].Subject != "gc-b" {
		t.Fatalf("saves = %+v, want the candidate chosen", f.saves)
	}
}

// The save sends the reference as the operator typed it, so open resolves it
// again and its --if-subject refuses a PR whose anchor moved while the operator
// typed. The subject is the one the screen shows.
func TestASaveSendsTheReferenceAsTyped(t *testing.T) {
	for _, ref := range []string{"https://github.com/o/r/pull/12", "1446"} {
		a := subjectAbout("tk-a", "gc-toolkit")
		a.Ref = ref
		f := &fakeHelm{about: map[string]About{ref: a}, saveResp: Saved{Subject: "tk-a", Conversation: "tk-c", Filed: true}}
		m := newForm(t, f, Options{Subject: ref})
		settle(m)
		typeText(m, "q")
		_, cmd := m.Update(ctrl('s'))
		deliver(m, cmd)
		if len(f.saves) != 1 || f.saves[0].Ref != ref || f.saves[0].Subject != "tk-a" {
			t.Fatalf("saves for %s = %+v, want the reference as typed, bound to tk-a", ref, f.saves)
		}
	}
}

func TestARefusedSubjectIsShownAndNothingIsFiled(t *testing.T) {
	a := subjectAbout("hq-1", "city-hq")
	a.Refusal = "converse is not available for 'hq-1': its rig 'city-hq' carries no converse template."
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

// An attach from the progress screen can hold the conversation in a new
// sitting, when the start failed or the sitting ended, so it runs on the model
// the start ran on. The return list shows no model, and attaches on engage's
// default.
func TestAnAttachThatCanHoldANewSittingKeepsTheModelTheStartRanOn(t *testing.T) {
	const want = "gc-helm.sh engage tk-c1 --no-input --model fable"

	// The start failed, so no sitting holds the conversation.
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
		startErr: errors.New("gc-helm: engage: the reconciler is down"),
	}
	m := newForm(t, f, Options{Subject: "tk-a", Model: "fable"})
	settle(m)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.startErr == "" || len(f.starts) != 1 || f.starts[0] != "tk-c1 fable" {
		t.Fatalf("start error %q, starts %v", m.startErr, f.starts)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attachArgs) != 1 || f.attachArgs[0] != want {
		t.Fatalf("attach after a failed start = %v, want %q", f.attachArgs, want)
	}

	// The sitting started and then ended before it was ready.
	f = &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m = newForm(t, f, Options{Subject: "tk-a", Model: "fable"})
	settle(m)
	typeText(m, "q")
	_, cmd = m.Update(ctrl('s'))
	_, cmd = m.Update(cmd())
	_, cmd = m.Update(cmd())
	f.about["tk-c1"] = About{Subject: Subject{ID: "tk-a"}, Conversations: []Conversation{{ID: "tk-c1", Readiness: Ended}}}
	_, cmd = m.Update(cmd())
	m.Update(cmd())
	if m.readiness != Ended {
		t.Fatalf("readiness = %q, want ended", m.readiness)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attachArgs) != 1 || f.attachArgs[0] != want {
		t.Fatalf("attach after an ended sitting = %v, want %q", f.attachArgs, want)
	}

	// The return list attaches on engage's default.
	f = &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-gone", Readiness: Ended}}}}
	m = newForm(t, f, Options{Return: true, Model: "fable"})
	loadCity(m)
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attachArgs) != 1 || f.attachArgs[0] != "gc-helm.sh engage tk-gone --no-input" {
		t.Fatalf("attach from the return list = %v", f.attachArgs)
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
	if len(f.saves) != 1 || f.saves[0].Ref != "tk-g" || f.saves[0].Subject != "tk-a" {
		t.Fatalf("saves = %+v, want the conversation filed through the gate, bound to tk-a", f.saves)
	}
}

func TestLeavingWhileTheSaveRunsWaitsForTheSaveAndTheStart(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
	settle(m)
	typeText(m, "a question")
	_, saveCmd := m.Update(ctrl('s'))
	if _, cmd := m.Update(key('q')); cmd != nil || !m.leaving {
		t.Fatalf("q while the save runs: leaving %v, a command %v", m.leaving, cmd != nil)
	}
	if v := m.progressView(); !strings.Contains(v, "Leaving once this lands") {
		t.Fatalf("screen while leaving:\n%s", v)
	}
	_, startCmd := m.Update(saveCmd())
	if startCmd == nil {
		t.Fatalf("the form left before the start ran")
	}
	started := startCmd()
	if _, ok := started.(startedMsg); !ok {
		t.Fatalf("after the save landed the form ran %T, not the start", started)
	}
	_, last := m.Update(started)
	if !isQuit(last) {
		t.Fatalf("the form did not leave once the start landed")
	}
	if len(f.starts) != 1 || !strings.Contains(m.Note(), "Conversation tk-c1 on tk-a is saved, and its sitting is starting") {
		t.Fatalf("starts %v, note %q", f.starts, m.Note())
	}
	if files, _ := filepath.Glob(filepath.Join(dir, "*")); len(files) != 0 {
		t.Fatalf("a saved question was kept as a draft too: %v", files)
	}
}

func TestLeavingWhileANewTopicIsSavedNamesTheSubjectItFiled(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{
		city:     rigCity(),
		saveResp: Saved{Subject: "tk-new", Filed: false},
		saveErr:  &Refusal{Code: 4, Why: "gc-helm: open: subject tk-new was filed, but its conversation was not"},
	}
	m := newForm(t, f, Options{Rig: "gc-toolkit", DraftDir: dir})
	loadCity(m)
	typeText(m, "the question\nin two lines")
	_, saveCmd := m.Update(ctrl('s'))
	m.Update(key(tea.KeyEscape))
	_, last := m.Update(saveCmd())
	if !isQuit(last) {
		t.Fatalf("the form did not leave once the save landed")
	}
	note := m.Note()
	if !strings.Contains(note, "Subject tk-new was filed, and its conversation was not.") || strings.Contains(note, "Nothing was filed") {
		t.Fatalf("note = %q", note)
	}
	if !strings.Contains(note, "&& gc-helm.sh engage tk-new --reason") {
		t.Fatalf("the note does not file the question onto tk-new: %q", note)
	}
	files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
	if len(files) != 1 {
		t.Fatalf("draft files %v", files)
	}
	if b, _ := os.ReadFile(files[0]); string(b) != "the question\nin two lines" {
		t.Fatalf("kept draft = %q", b)
	}
}

func TestCancellingAfterAPartialSaveNamesTheSubjectItFiled(t *testing.T) {
	f := &fakeHelm{
		city:     rigCity(),
		about:    map[string]About{"tk-new": subjectAbout("tk-new", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-new", Filed: false},
		saveErr:  &Refusal{Code: 4, Why: "gc-helm: open: subject tk-new was filed, but its conversation was not"},
	}
	m := newForm(t, f, Options{Rig: "gc-toolkit", DraftDir: t.TempDir()})
	loadCity(m)
	typeText(m, "the question")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	m.Update(key(tea.KeyEscape))
	if note := m.Note(); !strings.Contains(note, "Subject tk-new was filed") || strings.Contains(note, "Nothing was filed") {
		t.Fatalf("note = %q", note)
	}
}

func TestASecondCtrlCLeavesAtOnceAndSaysTheSaveIsUnknown(t *testing.T) {
	dir := t.TempDir()
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
	m := newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
	settle(m)
	typeText(m, "a question")
	m.Update(ctrl('s')) // the save's command never runs
	if _, cmd := m.Update(ctrl('c')); cmd != nil {
		t.Fatalf("the first Ctrl+C left while the save ran")
	}
	_, cmd := m.Update(ctrl('c'))
	if !isQuit(cmd) {
		t.Fatalf("the second Ctrl+C did not leave")
	}
	if !strings.Contains(m.Note(), "whether it was filed is unknown") {
		t.Fatalf("note = %q", m.Note())
	}
	if files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt")); len(files) != 1 {
		t.Fatalf("draft files %v", files)
	}
}

func TestARefusedSaveReadsTheSubjectAgain(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		aboutErr: map[string]error{"tk-a": errors.New("gc-helm.sh conversations exited 4")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "a question")
	_, cmd := m.Update(ctrl('s'))
	if len(f.saves) != 0 || cmd == nil || !strings.Contains(m.status, "exited 4. Reading it again.") {
		t.Fatalf("saves %v, a read %v, status %q", f.saves, cmd != nil, m.status)
	}
	delete(f.aboutErr, "tk-a")
	deliver(m, cmd)
	if _, ok := m.destination(); !ok {
		t.Fatalf("the read again did not settle the destination")
	}
	// A refusal that can change, such as a suspended rig, is read again too.
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Refusal = "rig 'gc-toolkit' is suspended."
	f.about["tk-a"] = a
	settle(m)
	_, cmd = m.Update(ctrl('s'))
	if len(f.saves) != 0 || !strings.HasSuffix(m.status, "is suspended. Reading it again.") {
		t.Fatalf("saves %v, status %q", f.saves, m.status)
	}
	f.about["tk-a"] = subjectAbout("tk-a", "gc-toolkit")
	deliver(m, cmd)
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Question != "a question" {
		t.Fatalf("saves = %+v", f.saves)
	}
	// A failed lookup is read again when the operator leaves the field, too.
	f.aboutErr = map[string]error{"tk-b": errors.New("timed out")}
	m2 := newForm(t, f, Options{})
	typeText(m2, "tk-b")
	deliver(m2, m2.lookup("tk-b"))
	if m2.lookups["tk-b"].err == nil || m2.lookup("tk-b") == nil {
		t.Fatalf("a failed lookup is not read again")
	}
}

func TestANewTopicReadsTheRigsAgainWhenTheyDidNotRead(t *testing.T) {
	f := &fakeHelm{city: rigCity(), cityErr: errors.New("gc rig list timed out"), saveResp: Saved{Subject: "tk-new", Conversation: "tk-c", Filed: true}}
	m := newForm(t, f, Options{})
	loadCity(m)
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "did not read (gc rig list timed out)") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	focusOn(t, m, questionField)
	typeText(m, "a new topic")
	_, cmd := m.Update(ctrl('s'))
	if cmd == nil || !strings.Contains(m.status, "Reading it again") {
		t.Fatalf("a read %v, status %q", cmd != nil, m.status)
	}
	f.cityErr = nil
	deliver(m, cmd)
	focusOn(t, m, rigField)
	m.Update(key(tea.KeyRight))
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Rig != "gc-toolkit" {
		t.Fatalf("saves = %+v", f.saves)
	}
}

func TestTheReturnListReadsTheCityAgainWhileOnScreen(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-c1", Readiness: Starting}}}}
	m := newForm(t, f, Options{Return: true})
	deliver(m, m.Init())
	if !m.ticking || len(m.returnRows()) != 1 {
		t.Fatalf("the return list schedules no refresh (ticking %v, rows %d)", m.ticking, len(m.returnRows()))
	}
	f.city.Conversations[0].Readiness = Ready
	_, next := m.Update(cityTickMsg{})
	deliver(m, next)
	if rows := m.returnRows(); rows[0].Readiness != Ready || !m.ticking {
		t.Fatalf("after a refresh: readiness %q, ticking %v", rows[0].Readiness, m.ticking)
	}
	if m.refreshCity() != nil {
		t.Fatalf("a second refresh was scheduled beside the first")
	}
	m.Update(ctrl('r')) // to the compose screen
	if _, next := m.Update(cityTickMsg{}); next != nil || m.ticking {
		t.Fatalf("the compose screen kept refreshing the return list")
	}
}

func TestTheKeptDraftNamesTheCommandThatFilesItAgain(t *testing.T) {
	dir := t.TempDir()
	url := "https://github.com/o/r/pull/12?x=1&y=2"
	m := newForm(t, &fakeHelm{}, Options{Subject: url, DraftDir: dir})
	typeText(m, "q")
	m.Update(key(tea.KeyEscape))
	if !strings.Contains(m.Note(), "gc-helm.sh engage '"+url+"' --reason") {
		t.Fatalf("note = %q", m.Note())
	}
	m = newForm(t, &fakeHelm{}, Options{Rig: "gc-toolkit", DraftDir: dir})
	typeText(m, "q")
	m.Update(key(tea.KeyEscape))
	if !strings.Contains(m.Note(), "gc-helm.sh engage --new-subject --rig gc-toolkit --reason") {
		t.Fatalf("note = %q", m.Note())
	}
	if shellQuote("it's here") != `'it'\''s here'` || shellQuote("tk-a") != "tk-a" {
		t.Fatalf("shellQuote")
	}
}

func TestAttachingFromTheReturnListKeepsTheUnsavedQuestion(t *testing.T) {
	for _, attachErr := range []error{nil, errors.New("exit status 1")} {
		dir := t.TempDir()
		f := &fakeHelm{
			about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
			city:  City{Conversations: []Conversation{{ID: "tk-c1", Readiness: Ready}}},
		}
		m := newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
		settle(m)
		loadCity(m)
		typeText(m, "a question\n  on two lines ")
		m.Update(ctrl('r'))
		_, cmd := m.Update(key(tea.KeyEnter))
		if cmd == nil || len(f.attaches) != 1 || f.attaches[0] != "tk-c1" {
			t.Fatalf("attach = %v", f.attaches)
		}
		// The question is in a file before the terminal goes to the sitting.
		files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
		if len(files) != 1 {
			t.Fatalf("draft files while the attach runs: %v", files)
		}
		if b, _ := os.ReadFile(files[0]); string(b) != "a question\n  on two lines " {
			t.Fatalf("kept draft = %q", b)
		}
		_, last := m.Update(attachedMsg{err: attachErr})
		if !isQuit(last) {
			t.Fatalf("the form did not leave once the attach came back (err %v)", attachErr)
		}
		note := m.Note()
		if !strings.Contains(note, files[0]) || !strings.Contains(note, "Nothing was filed.") || !strings.Contains(note, "gc-helm.sh engage tk-a --reason") {
			t.Fatalf("note after the attach (err %v) = %q", attachErr, note)
		}
		if attachErr != nil && !strings.HasPrefix(note, "The attach did not run: exit status 1") {
			t.Fatalf("note after a failed attach = %q", note)
		}
		if again, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt")); len(again) != 1 {
			t.Fatalf("the question was kept more than once: %v", again)
		}
	}
	// A question the form saved is not kept as a draft when the terminal goes.
	dir := t.TempDir()
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
	settle(m)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	m.Update(key(tea.KeyEnter))
	m.Update(attachedMsg{})
	if files, _ := filepath.Glob(filepath.Join(dir, "*")); len(files) != 0 || len(f.attaches) != 1 {
		t.Fatalf("after attaching a saved conversation: drafts %v, attaches %v", files, f.attaches)
	}
}

func TestASaveRefusedForASubjectThatMovedShowsWhereItLeadsBeforeTheNextSave(t *testing.T) {
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	typeText(m, "a question")
	if dest, ok := m.destination(); !ok || !strings.Contains(dest, "on tk-a") || !strings.Contains(dest, "in rig gc-toolkit") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	// While the operator types, tk-a closes onto a successor in another rig, and
	// open, told the subject the form showed, refuses to follow it.
	moved := subjectAbout("gc-b", "gascity")
	moved.Ref = "tk-a"
	f.about["tk-a"] = moved
	f.saveErr = &Refusal{Code: 4, Why: "gc-helm: open: tk-a names gc-b in rig gascity now, not tk-a (--if-subject). No conversation filed."}
	_, saveCmd := m.Update(ctrl('s'))
	_, reread := m.Update(saveCmd())
	if len(f.saves) != 1 || f.saves[0].Ref != "tk-a" || f.saves[0].Subject != "tk-a" {
		t.Fatalf("saves = %+v, want one bound to tk-a", f.saves)
	}
	if m.scr != composeScreen || m.question.Value() != "a question" || len(f.starts) != 0 {
		t.Fatalf("after the refusal: screen %d, question %q, starts %v", m.scr, m.question.Value(), f.starts)
	}
	if !strings.Contains(m.status, "names gc-b in rig gascity now") || strings.Contains(m.status, "..") {
		t.Fatalf("status = %q", m.status)
	}
	// Until the subject reads again, nothing can be saved.
	if reread == nil {
		t.Fatalf("the refused save does not read the subject again")
	}
	m.Update(ctrl('s'))
	if len(f.saves) != 1 {
		t.Fatalf("saved again before the subject read again: %+v", f.saves)
	}
	deliver(m, reread)
	if v := m.composeView(); !strings.Contains(v, "a conversation on gc-b") || !strings.Contains(v, "in rig gascity") {
		t.Fatalf("the screen does not show where tk-a leads now:\n%s", v)
	}
	f.saveErr, f.saveResp = nil, Saved{Subject: "gc-b", Conversation: "gc-c", Filed: true}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 2 || f.saves[1].Ref != "tk-a" || f.saves[1].Subject != "gc-b" {
		t.Fatalf("second save = %+v, want tk-a as typed, bound to gc-b, the subject now shown", f.saves)
	}
}

func TestTheReturnListKeepsItsSelectionAcrossARefresh(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: []Conversation{
		{ID: "tk-a", Readiness: Ready, CreatedAt: "2026-11-08T10:00:00Z"},
		{ID: "tk-b", Readiness: Preparing, CreatedAt: "2026-11-08T11:00:00Z"},
	}}}
	m := newForm(t, f, Options{Return: true})
	loadCity(m)
	m.Update(key(tea.KeyDown))
	if m.retSel != "tk-b" {
		t.Fatalf("selected %q, want tk-b", m.retSel)
	}
	// tk-b becomes ready and sorts above tk-a on the next read.
	f.city.Conversations[1].Readiness = Ready
	loadCity(m)
	if rows := m.returnRows(); rows[0].ID != "tk-b" {
		t.Fatalf("order after the refresh = %v", rows)
	}
	if v := m.returnView(); !strings.Contains(v, "› ready") || strings.Index(v, "› ") > strings.Index(v, "tk-b") {
		t.Fatalf("the cursor is not on tk-b:\n%s", v)
	}
	m.Update(key(tea.KeyEnter))
	if len(f.attaches) != 1 || f.attaches[0] != "tk-b" {
		t.Fatalf("attach = %v, want tk-b, the conversation selected", f.attaches)
	}

	// A selected conversation that leaves the list leaves nothing selected.
	f = &fakeHelm{city: City{Conversations: []Conversation{
		{ID: "tk-a", Readiness: Ready, CreatedAt: "2026-11-08T10:00:00Z"},
		{ID: "tk-b", Readiness: Preparing, CreatedAt: "2026-11-08T11:00:00Z"},
	}}}
	m = newForm(t, f, Options{Return: true})
	loadCity(m)
	m.Update(key(tea.KeyDown))
	f.city.Conversations = f.city.Conversations[:1]
	loadCity(m)
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd != nil || len(f.attaches) != 0 {
		t.Fatalf("Enter attached %v with the selected conversation gone", f.attaches)
	}
	if v := m.returnView(); !strings.Contains(v, "tk-b is no longer listed") || strings.Contains(v, "› ") {
		t.Fatalf("the screen with the selected conversation gone:\n%s", v)
	}
	// It comes back, and is selected again.
	f.city.Conversations = append(f.city.Conversations, Conversation{ID: "tk-b", Readiness: Preparing, CreatedAt: "2026-11-08T11:00:00Z"})
	loadCity(m)
	if m.retSel != "tk-b" || retIndex(m.returnRows(), "tk-b") != 1 {
		t.Fatalf("selection after tk-b came back = %q", m.retSel)
	}
	// Gone again, ↑/↓ picks the row now in its place.
	f.city.Conversations = f.city.Conversations[:1]
	loadCity(m)
	m.Update(key(tea.KeyDown))
	m.Update(key(tea.KeyEnter))
	if len(f.attaches) != 1 || f.attaches[0] != "tk-a" {
		t.Fatalf("attach after ↓ = %v, want tk-a", f.attaches)
	}
}

func TestAModelNoVariantCarriesIsShownAndStartsNothing(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a", Model: "typo"})
	settle(m)
	typeText(m, "q")
	if v := m.composeView(); !strings.Contains(v, "typo") || !strings.Contains(v, "not a configured model") {
		t.Fatalf("compose view does not mark the model:\n%s", v)
	}
	m.Update(ctrl('s'))
	if len(f.saves) != 0 || len(f.starts) != 0 || !strings.Contains(m.status, "typo is not a configured model (opus, fable, codex)") {
		t.Fatalf("saves %v, starts %v, status %q", f.saves, f.starts, m.status)
	}
	focusOn(t, m, modelField)
	m.Update(key(tea.KeyLeft))
	if m.modelName() != "codex" {
		t.Fatalf("← from the unknown model = %q, want the last variant", m.modelName())
	}
	m.Update(key(tea.KeyRight))
	if m.modelName() != "opus" {
		t.Fatalf("→ from codex = %q", m.modelName())
	}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || len(f.starts) != 1 || f.starts[0] != "tk-c1 opus" {
		t.Fatalf("saves %v, starts %v", f.saves, f.starts)
	}
	// → from the unknown model takes the first variant.
	m = newForm(t, &fakeHelm{}, Options{Model: "typo"})
	m.cycleModel(1)
	if m.modelName() != "opus" {
		t.Fatalf("→ from the unknown model = %q, want the first variant", m.modelName())
	}
	// With no variants named, the model the command line named stands.
	m = newForm(t, &fakeHelm{}, Options{Model: "fable", Models: []string{}})
	if m.model != 0 || m.modelName() != "fable" || strings.Contains(m.composeView(), "not a configured model") {
		t.Fatalf("model %d %q with no variants named", m.model, m.modelName())
	}
}

// A new topic whose subject and conversation were both filed before its save
// failed is saved again onto that subject, naming the conversation, so neither
// is filed a second time.
func TestANewTopicSavedAgainCompletesTheConversationItFiled(t *testing.T) {
	f := &fakeHelm{
		city:     rigCity(),
		saveResp: Saved{Subject: "tk-new", Conversation: "tk-c", Filed: true},
		saveErr:  errors.New("gc-helm.sh open: signal: killed"),
	}
	m := newForm(t, f, Options{Rig: "gc-toolkit"})
	loadCity(m)
	typeText(m, "the question")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.scr != progressScreen || m.saved == nil || m.saveErr == "" || len(f.starts) != 0 {
		t.Fatalf("after a save that filed tk-c and failed: screen %d, saved %+v, saveErr %q, starts %v", m.scr, m.saved, m.saveErr, f.starts)
	}
	f.saveErr = nil
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	want := SaveRequest{Ref: "tk-new", Subject: "tk-new", Question: "the question", Conversation: "tk-c"}
	if len(f.saves) != 2 || f.saves[1] != want {
		t.Fatalf("saves = %+v, want the save again onto tk-new naming tk-c", f.saves)
	}
	if m.saveErr != "" || len(f.starts) != 1 || f.starts[0] != "tk-c opus" {
		t.Fatalf("after the save again: saveErr %q, starts %v", m.saveErr, f.starts)
	}
}

// convs is n open conversations, tk-c00 the newest, so the return list shows
// them in id order.
func convs(n int) []Conversation {
	var cs []Conversation
	for i := range n {
		cs = append(cs, Conversation{ID: fmt.Sprintf("tk-c%02d", i), Readiness: Ready, Title: "a question", CreatedAt: fmt.Sprintf("2026-11-08T10:%02d:00Z", 59-i)})
	}
	return cs
}

// onScreen is what a terminal height lines tall shows of a view: the lines past
// its height are clipped.
func onScreen(view string, height int) []string {
	ls := strings.Split(view, "\n")
	return ls[:min(len(ls), height)]
}

// marked is the line on screen that holds want, or "".
func marked(ls []string, want string) string {
	for _, l := range ls {
		if strings.Contains(l, want) {
			return l
		}
	}
	return ""
}

// The return list is paged to the terminal, so ↑/↓ never moves the selection
// past what the screen shows and Enter attaches to the row marked, through a
// resize and through a refresh that moves the selection to another page.
func TestTheReturnListPagesToTheTerminal(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: convs(30)}}
	m := newForm(t, f, Options{Return: true})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	loadCity(m)
	for range 29 {
		m.Update(key(tea.KeyDown))
	}
	if m.retSel != "tk-c29" {
		t.Fatalf("selected %q after 29 ↓, want tk-c29", m.retSel)
	}
	for _, h := range []int{24, 10, 4} {
		m.Update(tea.WindowSizeMsg{Width: 80, Height: h})
		v := m.returnView()
		if n := lines(v); n > h {
			t.Fatalf("the view is %d lines on a %d-line terminal:\n%s", n, h, v)
		}
		if l := marked(onScreen(v, h), "› "); !strings.Contains(l, "tk-c29") {
			t.Fatalf("on a %d-line terminal the selected conversation is not on screen:\n%s", h, v)
		}
		if !strings.Contains(v, "more above") || strings.Contains(v, "tk-c00") {
			t.Fatalf("on a %d-line terminal the page does not say what it leaves out:\n%s", h, v)
		}
	}
	// A refresh that sorts tk-c29 to the top moves it to the first page.
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 24})
	f.city.Conversations[29].CreatedAt = "2026-11-08T11:00:00Z"
	loadCity(m)
	v := m.returnView()
	if l := marked(onScreen(v, 24), "› "); !strings.Contains(l, "tk-c29") || !strings.Contains(v, "more below") || strings.Contains(v, "more above") {
		t.Fatalf("after the refresh the selected conversation is not on the first page:\n%s", v)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attaches) != 1 || f.attaches[0] != "tk-c29" {
		t.Fatalf("attach = %v, want tk-c29, the row marked", f.attaches)
	}
}

// The rows on a subject are paged too: the cursor's row while the list has
// focus, and the row chosen once it has not.
func TestTheRowsOnASubjectPageToTheTerminal(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversations = convs(30)
	f := &fakeHelm{about: map[string]About{"tk-a": a}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	m.Update(tea.WindowSizeMsg{Width: 100, Height: 30})
	settle(m)
	focusOn(t, m, contextField)
	for range 25 {
		m.Update(key(tea.KeyDown))
	}
	v := m.composeView()
	if n := lines(v); n > 30 {
		t.Fatalf("the view is %d lines on a 30-line terminal:\n%s", n, v)
	}
	if l := marked(onScreen(v, 30), "› "); !strings.Contains(l, "tk-c24") || !strings.Contains(v, "more above") {
		t.Fatalf("the cursor's row is not on screen:\n%s", v)
	}
	m.Update(key(tea.KeySpace))
	if m.choice != "tk-c24" {
		t.Fatalf("choice = %q, want tk-c24", m.choice)
	}
	m.cursor = 0
	focusOn(t, m, questionField)
	if l := marked(onScreen(m.composeView(), 30), "● "); !strings.Contains(l, "tk-c24") {
		t.Fatalf("the row chosen is not on screen once the list has no focus:\n%s", m.composeView())
	}
}

// heldAbout is tk-a with one conversation, held by a gate, by its PR's review
// threads and by the merge pass's blocked verdict. The two the PR holds it by
// carry no ID, as prstatus.Reasons gives them.
func heldAbout() About {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Ready, Title: "a question"}}
	a.Holds = []Hold{
		{Held: "gate", ID: "tk-g1", Title: "approve the wording"},
		{Held: "review", Title: "2 review threads wait on the city's answer"},
		{Held: "blocked", Title: "a live blocker no automated actor holds"},
	}
	return a
}

// What holds the subject with no bead behind it, the PR's review threads and
// its blocked verdict, is shown under the rows, and no key reaches it: the
// cursor stops on the last row, Space chooses only rows, and Ctrl+S files on the
// subject.
func TestHoldsWithNoBeadAreShownAndNeverChosen(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": heldAbout()},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c2", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	v := m.composeView()
	for _, want := range []string{
		"· held: review — 2 review threads wait on the city's answer",
		"· held: blocked — a live blocker no automated actor holds",
	} {
		if !strings.Contains(v, want) {
			t.Fatalf("the screen does not show %q:\n%s", want, v)
		}
	}
	if rows := m.contextRows(); len(rows) != 3 || rows[1].id != "tk-c1" || rows[2].id != "tk-g1" {
		t.Fatalf("rows = %+v, want the new conversation, tk-c1 and the gate", rows)
	}
	focusOn(t, m, contextField)
	for range 6 {
		m.Update(key(tea.KeyDown))
	}
	if l := marked(strings.Split(m.composeView(), "\n"), "› "); m.cursor != 2 || !strings.Contains(l, "tk-g1") {
		t.Fatalf("after 6 ↓ the cursor is at %d, on %q, want the gate's row, the last", m.cursor, l)
	}
	for range 6 {
		m.Update(key(tea.KeyUp))
	}
	m.Update(key(tea.KeySpace))
	focusOn(t, m, questionField)
	typeText(m, "why is it held?")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || f.saves[0].Ref != "tk-a" || f.saves[0].Subject != "tk-a" {
		t.Fatalf("saves = %+v, want one on tk-a", f.saves)
	}
}

// The lines under the rows take room, which the rows page around, so on a short
// terminal the cursor's row and the held lines are both on screen.
func TestHeldLinesStayOnScreenWithTheRowInPlay(t *testing.T) {
	a := heldAbout()
	a.Conversations = convs(30)
	f := &fakeHelm{about: map[string]About{"tk-a": a}}
	m := newForm(t, f, Options{Subject: "tk-a"})
	m.Update(tea.WindowSizeMsg{Width: 100, Height: 30})
	settle(m)
	focusOn(t, m, contextField)
	for range 25 {
		m.Update(key(tea.KeyDown))
	}
	v := m.composeView()
	if n := lines(v); n > 30 {
		t.Fatalf("the view is %d lines on a 30-line terminal:\n%s", n, v)
	}
	shown := onScreen(v, 30)
	if l := marked(shown, "› "); !strings.Contains(l, "tk-c24") {
		t.Fatalf("the cursor's row is not on screen:\n%s", v)
	}
	if marked(shown, "· held: review") == "" || marked(shown, "· held: blocked") == "" {
		t.Fatalf("the held lines are not on screen:\n%s", v)
	}
}

// A subject whose holds did not read says so beside its rows, so it does not
// look like one nothing holds. A subject whose holds read says nothing of it,
// and nor does a PR number's candidate list, an answer with no holds_read.
func TestAHoldsReadThatFailedIsShown(t *testing.T) {
	unread := subjectAbout("tk-a", "gc-toolkit")
	unread.HoldsRead = false
	unread.Conversations = []Conversation{{ID: "tk-c1", Readiness: Ready, Title: "a question"}}
	f := &fakeHelm{about: map[string]About{
		"tk-a": unread,
		"tk-b": subjectAbout("tk-b", "gc-toolkit"),
		"12":   {Ref: "12", Candidates: []Candidate{{ID: "tk-x", Rig: "gc-toolkit", Title: "x"}, {ID: "gc-y", Rig: "gascity", Title: "y"}}},
	}}
	const warning = "What holds the subject did not read"
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	if v := m.composeView(); !strings.Contains(v, warning) || !strings.Contains(v, "tk-c1") {
		t.Fatalf("a subject whose holds did not read:\n%s", v)
	}
	for ref, shows := range map[string]string{"tk-b": "a new conversation", "12": "tk-x"} {
		m := newForm(t, f, Options{Subject: ref})
		settle(m)
		if v := m.composeView(); strings.Contains(v, warning) || !strings.Contains(v, shows) {
			t.Fatalf("%s:\n%s", ref, v)
		}
	}
}

// A refresh that fails keeps the rows the last read gave, and the screen says
// the list may be out of date, since when, and why the read failed.
func TestAFailedRefreshSaysTheListMayBeOutOfDate(t *testing.T) {
	f := &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-c1", Readiness: Preparing}}}}
	at := time.Date(2026, 11, 8, 18, 30, 5, 0, time.Local)
	m := newForm(t, f, Options{Return: true, Now: func() time.Time { return at }})
	loadCity(m)
	if v := m.returnView(); strings.Contains(v, "Not refreshed") {
		t.Fatalf("a list just read says it is out of date:\n%s", v)
	}
	at = at.Add(time.Minute)
	f.cityErr = errors.New("gc-helm: conversations: could not read 'gc session list'")
	loadCity(m)
	v := m.returnView()
	if !strings.Contains(v, "tk-c1") || !strings.Contains(v, "Not refreshed since 18:30:05, so the list may be out of date: gc-helm: conversations: could not read 'gc session list'") {
		t.Fatalf("after a failed refresh:\n%s", v)
	}
	f.cityErr = nil
	loadCity(m)
	if v := m.returnView(); strings.Contains(v, "Not refreshed") {
		t.Fatalf("a refresh that read still says the list is out of date:\n%s", v)
	}
}

// The command the note prints files the question exactly as it is kept, with
// its tabs and its trailing newlines, and runs nothing once the file is gone.
func TestTheKeptDraftsCommandFilesTheQuestionWhole(t *testing.T) {
	dir := t.TempDir()
	bin := filepath.Join(dir, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	got := filepath.Join(dir, "reason")
	stub := "#!/bin/sh\nfor a; do last=$a; done\nprintf '%s' \"$last\" > '" + got + "'\n"
	if err := os.WriteFile(filepath.Join(bin, "gc-helm.sh"), []byte(stub), 0o755); err != nil {
		t.Fatal(err)
	}
	m := newForm(t, &fakeHelm{}, Options{Subject: "tk-a", DraftDir: filepath.Join(dir, "the drafts")})
	// A tab comes only in a paste, since the Tab key moves the focus.
	q := "a question\n\tindented by a tab\n  that ends in blank lines\n\n"
	typeText(m, "a question\n")
	m.Update(tea.PasteMsg{Content: "\tindented by a tab\n"})
	typeText(m, "  that ends in blank lines\n\n")
	if m.question.Value() != q {
		t.Fatalf("question = %q", m.question.Value())
	}
	m.Update(key(tea.KeyEscape))
	_, command, ok := strings.Cut(m.Note(), "start it again with: ")
	if !ok {
		t.Fatalf("note = %q", m.Note())
	}
	run := func() error {
		c := exec.Command("sh", "-c", command)
		c.Env = append(os.Environ(), "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"))
		return c.Run()
	}
	if err := run(); err != nil {
		t.Fatalf("%s: %v", command, err)
	}
	if b, _ := os.ReadFile(got); string(b) != q {
		t.Fatalf("the command filed %q, want %q", b, q)
	}
	files, _ := filepath.Glob(filepath.Join(dir, "the drafts", "engage-draft-*.txt"))
	if len(files) != 1 {
		t.Fatalf("draft files %v", files)
	}
	if b, _ := os.ReadFile(files[0]); string(b) != q {
		t.Fatalf("kept draft = %q, want %q", b, q)
	}
	if err := os.Remove(files[0]); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(got); err != nil {
		t.Fatal(err)
	}
	if err := run(); err == nil {
		t.Fatalf("the command succeeded with its draft gone")
	}
	if _, err := os.Stat(got); !os.IsNotExist(err) {
		t.Fatalf("the command ran engage with its draft gone")
	}
}
