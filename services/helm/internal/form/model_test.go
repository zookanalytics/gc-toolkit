package form

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
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

	abouts   []string // each read, as about keys it
	saves    []SaveRequest
	starts   []string
	attaches []string
	// attachArgs is the argv each attach would run, as Script builds it, and
	// attachCmds the command each one returned.
	attachArgs []string
	attachCmds []*exec.Cmd
}

// About answers a reference from about, and one reached from a bead from the
// entry "<ref> --from <bead>".
func (f *fakeHelm) About(_ context.Context, ref, from string) (About, error) {
	k := ref
	if from != "" {
		k += " --from " + from
	}
	f.abouts = append(f.abouts, k)
	if err := f.aboutErr[k]; err != nil {
		return About{}, err
	}
	return f.about[k], nil
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
	c := exec.Command("true")
	f.attachCmds = append(f.attachCmds, c)
	return c
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
		opt.Models = []string{"claude-opus", "claude-fable", "codex-astra", "codex-sol"}
	}
	opt.Debounce = time.Millisecond
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
// batches and ticks, the way the bubbletea runtime would. It stops at runtime
// messages such as the cursor's blink, which repeat for as long as the form
// runs, and at the form's end, which only the runtime acts on.
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
	case aboutMsg, cityMsg, debounceMsg, savedMsg, startedMsg:
		_, next := m.Update(msg)
		deliverN(m, next, depth+1)
	}
}

func loadCity(m *Model) { deliver(m, m.loadCity()) }

// settle looks up the subject field as it reads now and delivers the answer.
func settle(m *Model) {
	k := m.subjectKey()
	delete(m.lookups, k)
	deliver(m, m.lookup(k))
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
	if initCmd == nil || !m.lookups[lookupKey{ref: "tk-a"}].pending || !m.cityBusy {
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
	staleCmd := m.lookup(lookupKey{ref: "tk-a"}) // asked for while the field read tk-a
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

// The save is said before the start runs, and once the sitting has started the
// form leaves to attach the terminal to it, on the model the start ran on.
func TestSavedIsSaidBeforeTheStartAndTheSittingIsAttachedOnceItStarts(t *testing.T) {
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
	if v := m.progressView(); !strings.Contains(v, "saved: conversation tk-c1") || !strings.Contains(v, "starting its sitting on Claude-Opus") || !strings.Contains(v, "Attaches once its sitting starts") {
		t.Fatalf("after the save, before the start, the screen says:\n%s", v)
	}
	if len(f.starts) != 0 || len(f.attaches) != 0 {
		t.Fatalf("the start or the attach ran before the start's command did: starts %v, attaches %v", f.starts, f.attaches)
	}
	_, attachCmd := m.Update(startCmd())
	if len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-opus" {
		t.Fatalf("starts = %v", f.starts)
	}
	if len(f.attachArgs) != 1 || f.attachArgs[0] != "gc-helm.sh engage tk-c1 --no-input --model claude-opus" {
		t.Fatalf("once the sitting started the form kept the attach %v, want tk-c1 on claude-opus", f.attachArgs)
	}
	// The form keeps the attach and leaves, and the attach runs once the
	// form's program has returned, so the form draws nothing after it.
	if !isQuit(attachCmd) || m.Attach() == nil || m.Attach() != f.attachCmds[0] {
		t.Fatalf("once the sitting started: left %v, attach kept %v", isQuit(attachCmd), m.Attach() != nil)
	}
	// An Enter that lands before the form's program ends keeps no second
	// attach.
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd != nil || len(f.attaches) != 1 {
		t.Fatalf("Enter after the sitting started attached again: %v", f.attaches)
	}
	if m.Note() != "" || m.Leave() != "" {
		t.Fatalf("the form left to attach saying %q, then %q", m.Note(), m.Leave())
	}
}

// Tab goes from the subject to the question, and then to the rig, the model and
// whether to attach, which is the order the screen shows them in.
func TestTheQuestionIsOneTabFromTheSubject(t *testing.T) {
	f := &fakeHelm{city: rigCity(), about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")}}
	m := newForm(t, f, Options{})
	if m.focus != subjectField {
		t.Fatalf("an empty form opens on field %d, want the subject", m.focus)
	}
	for _, want := range []field{questionField, rigField, modelField, attachField, subjectField} {
		m.Update(key(tea.KeyTab))
		if m.focus != want {
			t.Fatalf("Tab reached field %d, want %d (fields %v)", m.focus, want, m.fields())
		}
	}
	m.Update(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	if m.focus != attachField {
		t.Fatalf("Shift+Tab from the subject reached field %d, want the attach field", m.focus)
	}
	order := []string{"Subject", "Question", "Rig", "Model", "Attach", "Files as"}
	v := m.composeView()
	at := -1
	for _, label := range order {
		i := strings.Index(v, label)
		if i <= at {
			t.Fatalf("the screen does not show %v in that order:\n%s", order, v)
		}
		at = i
	}
	// A subject from the command line opens on the question. Enter in the
	// subject field goes to the question too, and an existing subject has no rig
	// field, since its rig is its own.
	m = newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	if m.focus != questionField {
		t.Fatalf("a form with its subject opens on field %d, want the question", m.focus)
	}
	m.Update(tea.KeyPressMsg{Code: tea.KeyTab, Mod: tea.ModShift})
	m.Update(key(tea.KeyEnter))
	if m.focus != questionField {
		t.Fatalf("Enter in the subject field reached field %d, want the question", m.focus)
	}
	if fs := m.fields(); len(fs) != 4 || fs[0] != subjectField || fs[1] != questionField || fs[2] != modelField || fs[3] != attachField {
		t.Fatalf("an existing subject's fields = %v", fs)
	}
}

// With attaching off, the form saves and starts the question's sitting, then
// leaves it to prepare, and says how to return to it. --no-attach opens the
// form with attaching off.
func TestWithAttachingOffTheFormLeavesOnceTheSittingStarts(t *testing.T) {
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	if v := m.composeView(); !strings.Contains(v, "Ctrl+S save, start and attach") || !strings.Contains(v, "‹ yes, once its sitting starts") {
		t.Fatalf("attaching is not on by default:\n%s", v)
	}
	focusOn(t, m, attachField)
	m.Update(key(tea.KeySpace))
	if v := m.composeView(); m.attach || !strings.Contains(v, "Ctrl+S save, start and leave") || !strings.Contains(v, "‹ no, leave once its sitting starts ›") {
		t.Fatalf("Space did not turn attaching off:\n%s", v)
	}
	focusOn(t, m, questionField)
	typeText(m, "a question")
	_, saveCmd := m.Update(ctrl('s'))
	_, startCmd := m.Update(saveCmd())
	if v := m.progressView(); !strings.Contains(v, "Leaves once its sitting starts; return with gc-helm.sh attach") {
		t.Fatalf("while the start runs the screen says:\n%s", v)
	}
	_, last := m.Update(startCmd())
	if !isQuit(last) || len(f.starts) != 1 || len(f.attaches) != 0 {
		t.Fatalf("once the sitting started: left %v, starts %v, attaches %v", isQuit(last), f.starts, f.attaches)
	}
	if n := m.Note(); n != "Conversation tk-c1 on tk-a is saved, and its sitting is starting. Return to it with: gc-helm.sh attach tk-c1" {
		t.Fatalf("note = %q", n)
	}

	m = newForm(t, f, Options{Subject: "tk-a", NoAttach: true})
	if m.attach || !strings.Contains(m.composeView(), "‹ no, leave once its sitting starts ›") {
		t.Fatalf("--no-attach opened the form with attaching on:\n%s", m.composeView())
	}
	focusOn(t, m, attachField)
	m.Update(key(tea.KeyRight))
	if !m.attach {
		t.Fatalf("→ did not turn attaching back on")
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

// A save that filed the conversation and then failed, here because the store
// refused its reply onto the gate, leaves the question saved in that
// conversation. Nothing starts, and r sends the save again naming that
// conversation, which open completes rather than file a second one.
func TestAConversationFiledWhoseSaveFailedIsKeptAndSavedAgainNotFiledAgain(t *testing.T) {
	a := subjectAbout("tk-held", "gc-toolkit")
	a.Ref, a.Gate = "tk-gate", "tk-gate"
	f := &fakeHelm{
		about:    map[string]About{"tk-gate": a},
		saveResp: Saved{Subject: "tk-held", Conversation: "tk-c1", Filed: true},
		saveErr:  &Refusal{Code: 4, Why: "gc-helm: open: conversation tk-c1 is filed on tk-held, but the store refused its reply onto gate tk-gate. Add it by hand: gc bd dep add tk-c1 tk-gate --type replies-to"},
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
	if strings.Contains(v, "Not saved") || !strings.Contains(v, "saved: conversation tk-c1") || !strings.Contains(v, "the store refused its reply onto gate tk-gate") {
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
	if m.saveErr != "" || len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-opus" {
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
	if len(f.saves) != 0 || len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-opus" || len(f.attaches) != 1 || f.attaches[0] != "tk-c1" {
		t.Fatalf("continuing tk-c1: saves %v starts %v attaches %v", f.saves, f.starts, f.attaches)
	}
}

func TestATypedConversationIdIsChosenUntilTheOperatorChooses(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversation = "tk-c1"
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Ended}}
	f := &fakeHelm{about: map[string]About{"tk-c1": a}}
	m := newForm(t, f, Options{Subject: "tk-c1"})
	deliver(m, m.lookup(lookupKey{ref: "tk-c1"}))
	if m.choice != "tk-c1" {
		t.Fatalf("choice = %q, want the conversation the subject field named", m.choice)
	}
	m.choice, m.choiceTouched = newChoice, true
	delete(m.lookups, lookupKey{ref: "tk-c1"})
	deliver(m, m.lookup(lookupKey{ref: "tk-c1"}))
	if m.choice != newChoice {
		t.Fatalf("a later lookup moved the operator's choice to %q", m.choice)
	}
}

// A conversation id edited away and typed back names that conversation again,
// though the answer for it came before the edit and is not read again, so an
// empty question continues it. A choice the operator made stands while the
// field reads the same reference.
func TestAConversationIdTypedBackIsChosenAgain(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversation = "tk-c1"
	a.Conversations = []Conversation{{ID: "tk-c1", Readiness: Ended}}
	typedBack := func(f *fakeHelm) *Model {
		m := newForm(t, f, Options{Subject: "tk-c1"})
		settle(m)
		focusOn(t, m, subjectField)
		m.Update(key(tea.KeyBackspace))
		typeText(m, "1")
		if m.ref() != "tk-c1" || m.choice != newChoice {
			t.Fatalf("after the edit: subject %q, choice %q", m.ref(), m.choice)
		}
		if _, cmd := m.Update(debounceMsg{seq: m.seq}); cmd != nil {
			t.Fatalf("tk-c1 was read again though its answer stands")
		}
		return m
	}
	f := &fakeHelm{about: map[string]About{"tk-c1": a}}
	m := typedBack(f)
	if m.choice != "tk-c1" {
		t.Fatalf("choice = %q, want tk-c1, which the subject field names again", m.choice)
	}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 0 || len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-opus" {
		t.Fatalf("an empty question on tk-c1: saves %v, starts %v, status %q", f.saves, f.starts, m.status)
	}

	f = &fakeHelm{about: map[string]About{"tk-c1": a}}
	m = typedBack(f)
	focusOn(t, m, contextField)
	m.Update(key(tea.KeySpace)) // the new-conversation row, under the cursor
	focusOn(t, m, subjectField)
	m.Update(key(tea.KeyTab))
	if m.choice != newChoice {
		t.Fatalf("leaving the subject field moved the operator's choice to %q", m.choice)
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
	if v := m.progressView(); !strings.Contains(v, "Enter attaches, holding it in a new sitting · q leaves it in your queue") {
		t.Fatalf("after the failed start the screen does not say what Enter and q do:\n%s", v)
	}
	f.startErr = nil
	_, cmd = m.Update(key('r'))
	deliver(m, cmd)
	if len(f.starts) != 2 || m.startErr != "" || len(f.attaches) != 1 || f.attaches[0] != "tk-c1" {
		t.Fatalf("after the retried start: starts %v, start error %q, attaches %v", f.starts, m.startErr, f.attaches)
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
	if v := m.composeView(); !strings.Contains(v, "Claude-Opus") || !strings.Contains(v, "(default)") || strings.Contains(v, "claude-opus") {
		t.Fatalf("compose view does not show the default model by its label:\n%s", v)
	}
	focusOn(t, m, modelField)
	m.Update(key(tea.KeyRight))
	focusOn(t, m, questionField)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-fable" {
		t.Fatalf("starts = %v", f.starts)
	}
}

// The model field shows each variant by its label, every word of its name
// capitalized, in the order engage lists them, and starts the sitting on the
// name itself, which is what engage's --model takes.
func TestTheModelFieldShowsEachVariantByItsLabel(t *testing.T) {
	for name, want := range map[string]string{
		"claude-opus": "Claude-Opus", "claude-fable": "Claude-Fable",
		"codex-sol": "Codex-Sol", "codex-astra": "Codex-Astra",
		"opus": "Opus", "": "",
	} {
		if got := modelLabel(name); got != want {
			t.Errorf("modelLabel(%q) = %q, want %q", name, got, want)
		}
	}
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	focusOn(t, m, modelField)
	var shown []string
	for range m.opt.Models {
		v := m.composeView()
		for _, l := range []string{"Claude-Opus", "Claude-Fable", "Codex-Astra", "Codex-Sol"} {
			if strings.Contains(v, "‹ "+l) {
				shown = append(shown, l)
			}
		}
		m.Update(key(tea.KeyRight))
	}
	if got := strings.Join(shown, ", "); got != "Claude-Opus, Claude-Fable, Codex-Astra, Codex-Sol" {
		t.Fatalf("the model field showed %s", got)
	}
	m.Update(key(tea.KeyLeft))
	focusOn(t, m, questionField)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.starts) != 1 || f.starts[0] != "tk-c1 codex-sol" {
		t.Fatalf("starts = %v, want the sitting started on codex-sol", f.starts)
	}
}

// An attach after a start can hold the conversation in a new sitting, when the
// start failed or the sitting ended before engage's attach reached it, so it
// runs on the model the start ran on. The return list shows no model, and
// attaches on engage's default.
func TestAnAttachThatCanHoldANewSittingKeepsTheModelTheStartRanOn(t *testing.T) {
	const want = "gc-helm.sh engage tk-c1 --no-input --model claude-fable"

	// The start failed, so no sitting holds the conversation.
	f := &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
		startErr: errors.New("gc-helm: engage: the reconciler is down"),
	}
	m := newForm(t, f, Options{Subject: "tk-a", Model: "claude-fable"})
	settle(m)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.startErr == "" || len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-fable" {
		t.Fatalf("start error %q, starts %v", m.startErr, f.starts)
	}
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attachArgs) != 1 || f.attachArgs[0] != want {
		t.Fatalf("attach after a failed start = %v, want %q", f.attachArgs, want)
	}

	// The sitting started, and the attach that follows names its model.
	f = &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m = newForm(t, f, Options{Subject: "tk-a", Model: "claude-fable"})
	settle(m)
	typeText(m, "q")
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.attachArgs) != 1 || f.attachArgs[0] != want {
		t.Fatalf("attach once the sitting started = %v, want %q", f.attachArgs, want)
	}

	// The return list attaches on engage's default.
	f = &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-gone", Readiness: Ended}}}}
	m = newForm(t, f, Options{Return: true, Model: "claude-fable"})
	loadCity(m)
	if _, cmd := m.Update(key(tea.KeyEnter)); cmd == nil || len(f.attachArgs) != 1 || f.attachArgs[0] != "gc-helm.sh engage tk-gone --no-input" {
		t.Fatalf("attach from the return list = %v", f.attachArgs)
	}
}

// One attach runs. The form leaves once it keeps an attach, and a key its
// program reads before it ends does nothing, so an Enter that lands then, on
// the return list or after a start that failed, keeps no second attach, and an
// r starts nothing.
func TestASecondEnterBeforeTheAttachAttachesNothingMore(t *testing.T) {
	t.Run("on the return list", func(t *testing.T) {
		f := &fakeHelm{city: City{Conversations: []Conversation{{ID: "tk-c1", Readiness: Ready}}}}
		m := newForm(t, f, Options{Return: true})
		loadCity(m)
		_, first := m.Update(key(tea.KeyEnter))
		_, second := m.Update(key(tea.KeyEnter))
		if first == nil || second != nil || len(f.attaches) != 1 {
			t.Fatalf("two Enters: an attach %v, then %v; attaches %v", first != nil, second != nil, f.attaches)
		}
	})
	t.Run("after a failed start", func(t *testing.T) {
		f := &fakeHelm{
			about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
			saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
			startErr: errors.New("gc-helm: engage: the reconciler is down"),
		}
		m := newForm(t, f, Options{Subject: "tk-a"})
		settle(m)
		typeText(m, "q")
		_, cmd := m.Update(ctrl('s'))
		deliver(m, cmd)
		_, first := m.Update(key(tea.KeyEnter))
		_, second := m.Update(key(tea.KeyEnter))
		if first == nil || second != nil || len(f.attaches) != 1 {
			t.Fatalf("two Enters: an attach %v, then %v; attaches %v", first != nil, second != nil, f.attaches)
		}
		f.startErr = nil
		if _, cmd := m.Update(key('r')); cmd != nil || len(f.starts) != 1 || len(f.attaches) != 1 {
			t.Fatalf("r after the form left to attach: a command %v, starts %v, attaches %v", cmd != nil, f.starts, f.attaches)
		}
	})
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
	if len(f.starts) != 1 || len(f.attaches) != 0 || !strings.Contains(m.Note(), "Conversation tk-c1 on tk-a is saved, and its sitting is starting") {
		t.Fatalf("starts %v, attaches %v, note %q", f.starts, f.attaches, m.Note())
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
	note := m.Note()
	if !strings.Contains(note, "whether it was filed is unknown") {
		t.Fatalf("note = %q", note)
	}
	// The program ends once the form has left, and what the form says then is
	// what it said as it left.
	if again := m.Leave(); again != note {
		t.Fatalf("once the program ended the note was %q, not %q", again, note)
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
	deliver(m2, m2.lookup(lookupKey{ref: "tk-b"}))
	if m2.lookups[lookupKey{ref: "tk-b"}].err == nil || m2.lookup(lookupKey{ref: "tk-b"}) == nil {
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
	if !isQuit(cmd) || m.Attach() == nil || len(f.attaches) != 1 || f.attaches[0] != "tk-c1" {
		t.Fatalf("left %v, attach kept %v, attaches %v", isQuit(cmd), m.Attach() != nil, f.attaches)
	}
	// The question is in a file before the terminal goes to the sitting, and
	// the note, printed before the attach runs, says where.
	files, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt"))
	if len(files) != 1 {
		t.Fatalf("draft files once the form left to attach: %v", files)
	}
	if b, _ := os.ReadFile(files[0]); string(b) != "a question\n  on two lines " {
		t.Fatalf("kept draft = %q", b)
	}
	note := m.Leave()
	if !strings.Contains(note, files[0]) || !strings.Contains(note, "Nothing was filed.") || !strings.Contains(note, "gc-helm.sh engage tk-a --reason") {
		t.Fatalf("note once the form left to attach = %q", note)
	}
	if again, _ := filepath.Glob(filepath.Join(dir, "engage-draft-*.txt")); len(again) != 1 {
		t.Fatalf("the question was kept more than once: %v", again)
	}
	// A question the form saved is not kept as a draft when the form leaves to
	// attach its sitting, once that sitting starts.
	dir = t.TempDir()
	f = &fakeHelm{
		about:    map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c1", Filed: true},
	}
	m = newForm(t, f, Options{Subject: "tk-a", DraftDir: dir})
	settle(m)
	typeText(m, "q")
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	if files, _ := filepath.Glob(filepath.Join(dir, "*")); len(files) != 0 || len(f.attaches) != 1 || m.Leave() != "" {
		t.Fatalf("after attaching a saved conversation: drafts %v, attaches %v, note %q", files, f.attaches, m.Leave())
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
	if len(f.saves) != 0 || len(f.starts) != 0 || !strings.Contains(m.status, "typo is not a configured model (Claude-Opus, Claude-Fable, Codex-Astra, Codex-Sol)") {
		t.Fatalf("saves %v, starts %v, status %q", f.saves, f.starts, m.status)
	}
	focusOn(t, m, modelField)
	m.Update(key(tea.KeyLeft))
	if m.modelName() != "codex-sol" {
		t.Fatalf("← from the unknown model = %q, want the last variant", m.modelName())
	}
	m.Update(key(tea.KeyRight))
	if m.modelName() != "claude-opus" {
		t.Fatalf("→ from codex-sol = %q", m.modelName())
	}
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 1 || len(f.starts) != 1 || f.starts[0] != "tk-c1 claude-opus" {
		t.Fatalf("saves %v, starts %v", f.saves, f.starts)
	}
	// → from the unknown model takes the first variant.
	m = newForm(t, &fakeHelm{}, Options{Model: "typo"})
	m.cycleModel(1)
	if m.modelName() != "claude-opus" {
		t.Fatalf("→ from the unknown model = %q, want the first variant", m.modelName())
	}
	// With no variants named, the model the command line named stands.
	m = newForm(t, &fakeHelm{}, Options{Model: "claude-fable", Models: []string{}})
	if m.model != 0 || m.modelName() != "claude-fable" || strings.Contains(m.composeView(), "not a configured model") {
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
	if m.saveErr != "" || len(f.starts) != 1 || f.starts[0] != "tk-c claude-opus" {
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
	// At 80 columns the header wraps onto two lines, so five lines is the
	// shortest terminal with room for it, the line under it, the row selected
	// and the line that counts the rows left out.
	for _, h := range []int{24, 10, 5} {
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

// A short terminal shows fewer lines of the question, down to a few, so the
// fields, the row in play, the line that counts what the list leaves out and
// the status under the list stay on screen: the cursor's row while the list has
// focus, and the row chosen, which Ctrl+S acts on, once it has not. The
// question keeps every line typed into it, and a terminal tall enough shows
// all of its lines again.
func TestAShortTerminalShowsFewerLinesOfTheQuestion(t *testing.T) {
	a := subjectAbout("tk-a", "gc-toolkit")
	a.Conversations = convs(3)
	f := &fakeHelm{about: map[string]About{"tk-a": a}, saveErr: errors.New("the store did not answer")}
	m := newForm(t, f, Options{Subject: "tk-a"})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 20})
	settle(m)
	const q = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine"
	typeText(m, q)
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if m.scr != composeScreen || !strings.HasPrefix(m.status, "Not saved") {
		t.Fatalf("after the refused save: screen %d, status %q", m.scr, m.status)
	}
	focusOn(t, m, contextField)
	for range 3 {
		m.Update(key(tea.KeyDown))
	}
	onShort := func(mark, id string) {
		t.Helper()
		for _, h := range []int{20, 21, 22} {
			m.Update(tea.WindowSizeMsg{Width: 80, Height: h})
			v := m.composeView()
			if n := lines(v); n > h {
				t.Fatalf("the view is %d lines on a %d-line terminal:\n%s", n, h, v)
			}
			ls := onScreen(v, h)
			if l := marked(ls, mark); !strings.Contains(l, id) {
				t.Fatalf("on a %d-line terminal the row marked %q is not %s:\n%s", h, mark, id, v)
			}
			if marked(ls, "3 more above") == "" || marked(ls, "Not saved") == "" {
				t.Fatalf("on a %d-line terminal the count of the rows left out or the status is not on screen:\n%s", h, v)
			}
		}
	}
	onShort("› ", "tk-c02")
	m.Update(key(tea.KeySpace))
	if m.choice != "tk-c02" {
		t.Fatalf("choice = %q, want tk-c02", m.choice)
	}
	focusOn(t, m, questionField)
	onShort("● ", "tk-c02")
	if m.question.Value() != q {
		t.Fatalf("question = %q, want every line typed", m.question.Value())
	}
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 40})
	m.composeView()
	if h := m.question.Height(); h != questionLines {
		t.Fatalf("on a 40-line terminal the question shows %d lines, want %d", h, questionLines)
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

// sharedGateHelm answers tk-a, held by gate tk-g1, which tk-a and tk-b both wait
// on, and by decision tk-dec. Typed alone the gate names two beads and is
// refused, as gc-helm.sh refuses it. Reached from tk-a it is about tk-a, and the
// conversation replies to it.
func sharedGateHelm() *fakeHelm {
	a := heldAbout()
	a.Holds = append(a.Holds, Hold{Held: "blocked", ID: "tk-dec", Title: "keep the old flag?"})
	viaA := subjectAbout("tk-a", "gc-toolkit")
	viaA.Ref, viaA.Gate = "tk-g1", "tk-g1"
	viaA.Conversations = a.Conversations
	return &fakeHelm{
		about: map[string]About{"tk-a": a, "tk-g1 --from tk-a": viaA, "tk-dec": subjectAbout("tk-dec", "gc-toolkit")},
		aboutErr: map[string]error{"tk-g1": &Refusal{Code: 4, Why: "gc-helm: conversations: gate tk-g1 is about 2 beads still waiting on it (tk-a tk-b), " +
			"and a conversation is about one bead. Name the one you mean: gc-helm conversations tk-g1 --from <bead>. Nothing read."}},
	}
}

// chooseRow moves the cursor to the context row whose id is id and chooses it,
// delivering the lookup the choice starts.
func chooseRow(t *testing.T, m *Model, id string) {
	t.Helper()
	focusOn(t, m, contextField)
	for i, r := range m.contextRows() {
		if r.id == id {
			m.cursor = i
			_, cmd := m.Update(key(tea.KeySpace))
			deliver(m, cmd)
			return
		}
	}
	t.Fatalf("no row %s among %+v", id, m.contextRows())
}

// A gate chosen from what holds a subject is about that subject, read and saved
// from it, so a gate another bead waits on too is not refused: the screen files
// on the subject the gate was chosen from, says so, and the save names it, which
// open checks still waits on the gate before it files the reply.
func TestAGateSeveralBeadsWaitOnIsAboutTheSubjectItWasChosenFrom(t *testing.T) {
	f := sharedGateHelm()
	f.saveResp = Saved{Subject: "tk-a", Conversation: "tk-c2", Filed: true}
	m := newForm(t, f, Options{Subject: "tk-a"})
	m.Update(tea.WindowSizeMsg{Width: 110, Height: 40})
	settle(m)
	chooseRow(t, m, "tk-g1")
	if m.ref() != "tk-g1" || f.abouts[len(f.abouts)-1] != "tk-g1 --from tk-a" {
		t.Fatalf("subject %q, reads %v, want the gate read from tk-a", m.ref(), f.abouts)
	}
	if dest, ok := m.destination(); !ok || !strings.Contains(dest, "a conversation on tk-a") || !strings.Contains(dest, "answering gate tk-g1") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	// The note is on screen on a 110-column terminal, which the subject field,
	// padded to its width, leaves no room beside it for.
	if l := marked(strings.Split(m.composeView(), "\n"), "chosen from what holds tk-a"); l == "" || lipgloss.Width(l) > 110 {
		t.Fatalf("the screen does not say where the gate was chosen from, within 110 columns (%d): %q\n%s", lipgloss.Width(l), l, m.composeView())
	}
	focusOn(t, m, questionField)
	typeText(m, "is the wording right?")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	want := SaveRequest{Ref: "tk-g1", Subject: "tk-a", From: "tk-a", Question: "is the wording right?"}
	if len(f.saves) != 1 || f.saves[0] != want {
		t.Fatalf("saves = %+v, want %+v", f.saves, want)
	}
	if len(f.starts) != 1 || f.starts[0] != "tk-c2 claude-opus" {
		t.Fatalf("starts = %v, want tk-c2", f.starts)
	}
}

// A gate the operator types was reached from nothing, so one several beads wait
// on is refused, naming them, and nothing is filed. A gate a choice put in the
// field is read from nothing too once the field is edited, back to the same id
// included, and a blocker chosen from what holds a subject is a subject of its
// own, read from nothing.
func TestAGateSeveralBeadsWaitOnIsRefusedWithNoSubjectItWasChosenFrom(t *testing.T) {
	f := sharedGateHelm()
	m := newForm(t, f, Options{Subject: "tk-g1"})
	settle(m)
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "2 beads still waiting on it (tk-a tk-b)") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	typeText(m, "q")
	m.Update(ctrl('s'))
	if len(f.saves) != 0 || !strings.Contains(m.status, "Not saved") {
		t.Fatalf("saves %v status %q", f.saves, m.status)
	}

	m = newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	chooseRow(t, m, "tk-g1")
	focusOn(t, m, subjectField)
	m.Update(key(tea.KeyEnd))
	m.Update(key(tea.KeyBackspace))
	typeText(m, "1")
	if m.ref() != "tk-g1" || m.from != "" {
		t.Fatalf("after the edit: subject %q from %q, want tk-g1 from nothing", m.ref(), m.from)
	}
	settle(m)
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "2 beads still waiting on it") {
		t.Fatalf("destination after the edit = %q, %v", dest, ok)
	}
	if strings.Contains(m.composeView(), "chosen from what holds") {
		t.Fatalf("an edited gate still says where it was chosen from:\n%s", m.composeView())
	}

	m = newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	chooseRow(t, m, "tk-dec")
	if m.ref() != "tk-dec" || m.from != "" || f.abouts[len(f.abouts)-1] != "tk-dec" {
		t.Fatalf("a chosen blocker: subject %q from %q, reads %v", m.ref(), m.from, f.abouts)
	}
}

// A gate that no longer holds the subject it was chosen from is refused by the
// read, and the form shows that refusal and files nothing: it never reads the
// gate again without the subject, which would hand it to another bead.
func TestAGateThatNoLongerHoldsItsSubjectFilesNothing(t *testing.T) {
	f := sharedGateHelm()
	delete(f.about, "tk-g1 --from tk-a")
	f.aboutErr["tk-g1 --from tk-a"] = &Refusal{Code: 4, Why: "gc-helm: conversations: tk-a does not wait on gate tk-g1 now " +
		"(the beads waiting on it are tk-b), so the gate is not tk-a's to answer. Nothing read."}
	m := newForm(t, f, Options{Subject: "tk-a"})
	settle(m)
	chooseRow(t, m, "tk-g1")
	if dest, ok := m.destination(); ok || !strings.Contains(dest, "tk-a does not wait on gate tk-g1 now") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	focusOn(t, m, questionField)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if len(f.saves) != 0 {
		t.Fatalf("saves = %+v, want none", f.saves)
	}
	for _, k := range f.abouts {
		if k == "tk-g1" {
			t.Fatalf("the gate was read without the subject it was chosen from: reads %v", f.abouts)
		}
	}
}

// engage's --from fills in where the subject, a gate, was reached from, so the
// form reads it from there before the operator does anything, and a --from with
// no subject is dropped.
func TestTheCommandLinesFromReadsTheGateFromThatSubject(t *testing.T) {
	f := sharedGateHelm()
	m := newForm(t, f, Options{Subject: "tk-g1", From: "tk-a"})
	deliver(m, m.Init())
	if dest, ok := m.destination(); !ok || !strings.Contains(dest, "a conversation on tk-a") || len(f.abouts) != 1 || f.abouts[0] != "tk-g1 --from tk-a" {
		t.Fatalf("destination = %q, %v; reads %v", dest, ok, f.abouts)
	}
	if m := newForm(t, f, Options{From: "tk-a"}); m.from != "" {
		t.Fatalf("a --from with no subject was kept: %q", m.from)
	}
}

// The command that files a kept question again names where a gate was chosen
// from, so it files where the form would have.
func TestAKeptDraftOnAGateNamesTheSubjectItWasChosenFrom(t *testing.T) {
	f := sharedGateHelm()
	m := newForm(t, f, Options{Subject: "tk-a", DraftDir: t.TempDir()})
	settle(m)
	chooseRow(t, m, "tk-g1")
	focusOn(t, m, questionField)
	typeText(m, "q")
	m.Update(key(tea.KeyEscape))
	if !strings.Contains(m.Note(), "gc-helm.sh engage tk-g1 --from tk-a --reason") {
		t.Fatalf("note = %q", m.Note())
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

// sgr matches the style sequences lipgloss writes.
var sgr = regexp.MustCompile("\x1b\\[[0-9;]*m")

// screenAt is the text a terminal width columns wide and height lines tall
// shows of a view: bubbletea v2 draws the view without wrapping it, so the
// terminal cuts each line at its edge and drops the lines below its last.
func screenAt(view string, width, height int) []string {
	var out []string
	for _, l := range onScreen(sgr.ReplaceAllString(view, ""), height) {
		for lipgloss.Width(l) > width {
			_, n := utf8.DecodeLastRuneInString(l)
			l = l[:len(l)-n]
		}
		out = append(out, l)
	}
	return out
}

// reads is the text of the lines of a screen, as one line with single spaces,
// so a sentence the screen wraps reads as it was written.
func reads(screen []string) string {
	return strings.Join(strings.Fields(strings.Join(screen, " ")), " ")
}

// filesAs is the destination a screen shows: the text beside "Files as" and
// its mark, and the lines indented under that text.
func filesAs(screen []string) string {
	const under = "            " // as wide as "Files as  ✓ "
	for i, l := range screen {
		rest, ok := strings.CutPrefix(l, "Files as  ")
		if !ok {
			continue
		}
		_, text, _ := strings.Cut(rest, " ")
		parts := []string{strings.TrimSpace(text)}
		for _, c := range screen[i+1:] {
			if !strings.HasPrefix(c, under) || strings.TrimSpace(c) == "" {
				break
			}
			parts = append(parts, strings.TrimSpace(c))
		}
		return strings.Join(parts, " ")
	}
	return ""
}

// demoGateHelm answers as testdata/helm-fixture.sh answers for tk-demo1, a
// subject whose title fills much of a line, and for tk-demo10, the gate it is
// held by, which tk-demo11 waits on too: read from tk-demo1 it is about
// tk-demo1, and read from nothing it is refused, naming both.
func demoGateHelm() *fakeHelm {
	subject := Subject{ID: "tk-demo1", Title: "Board: show a PR's held reason on its row", Status: "open", IssueType: "task", Rig: "gc-toolkit"}
	asked := Conversation{ID: "tk-demo2", Readiness: Ready, Title: "why does the held label lag the gate by a cycle?"}
	gate := Hold{Held: "gate", ID: "tk-demo10", Title: "Approve the label wording"}
	return &fakeHelm{
		about: map[string]About{
			"tk-demo1": {Ref: "tk-demo1", Subject: subject, HoldsRead: true,
				Conversations: []Conversation{asked, {ID: "tk-demo9", Readiness: Preparing, Title: "your question"}},
				Holds:         []Hold{gate, {Held: "review", Title: "2 review threads wait on the city's answer"}}},
			"tk-demo10 --from tk-demo1": {Ref: "tk-demo10", Subject: subject, Gate: "tk-demo10", HoldsRead: true,
				Conversations: []Conversation{asked}, Holds: []Hold{gate}},
		},
		aboutErr: map[string]error{"tk-demo10": &Refusal{Code: 4, Why: "gc-helm: conversations: gate tk-demo10 is about 2 beads still waiting on it (tk-demo1 tk-demo11), " +
			"and a conversation is about one bead. Name the one you mean: gc-helm conversations tk-demo10 --from <bead>. Nothing read."}},
	}
}

// The destination is wrapped to the terminal beside "Files as", each line after
// the first under its text, so a narrow terminal shows all of it before Ctrl+S:
// the subject, its rig and the gate the conversation answers. On one line, the
// fixture's gate chosen from tk-demo1 files a destination 128 columns wide.
func TestTheDestinationIsShownWholeOnANarrowTerminal(t *testing.T) {
	m := newForm(t, demoGateHelm(), Options{Subject: "tk-demo1"})
	m.Update(tea.WindowSizeMsg{Width: 110, Height: 40})
	settle(m)
	chooseRow(t, m, "tk-demo10")
	dest, ok := m.destination()
	if !ok || !strings.HasSuffix(dest, "— in rig gc-toolkit, answering gate tk-demo10") {
		t.Fatalf("destination = %q, %v", dest, ok)
	}
	for _, w := range []int{110, 80, 60, 40} {
		m.Update(tea.WindowSizeMsg{Width: w, Height: 40})
		v := m.composeView()
		if got := filesAs(screenAt(v, w, 40)); got != dest {
			t.Fatalf("at %d columns the screen shows the destination as\n%q, want\n%q:\n%s", w, got, dest, v)
		}
	}
}

// The rows page around the lines the destination wraps onto, so on a short
// terminal the whole destination, the row in play, the line that counts the
// rows left out and the status are all on screen.
func TestTheRowsPageAroundTheLinesTheDestinationWrapsOnto(t *testing.T) {
	f := demoGateHelm()
	f.saveErr = errors.New("the store did not answer")
	m := newForm(t, f, Options{Subject: "tk-demo1"})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 22})
	settle(m)
	chooseRow(t, m, "tk-demo10")
	focusOn(t, m, questionField)
	typeText(m, "is the wording right?")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	if !strings.HasPrefix(m.status, "Not saved") {
		t.Fatalf("status = %q", m.status)
	}
	focusOn(t, m, contextField)
	for range 3 {
		m.Update(key(tea.KeyDown))
	}
	dest, _ := m.destination()
	v := m.composeView()
	if n := lines(v); n > 22 {
		t.Fatalf("the view is %d lines on a 22-line terminal:\n%s", n, v)
	}
	screen := screenAt(v, 80, 22)
	if got := filesAs(screen); got != dest {
		t.Fatalf("the screen shows the destination as %q, want %q:\n%s", got, dest, v)
	}
	if !strings.Contains(marked(screen, "› "), "tk-demo10") || marked(screen, "2 more above") == "" || marked(screen, "Not saved") == "" {
		t.Fatalf("the cursor's row, the count of the rows left out or the status is not on screen:\n%s", strings.Join(screen, "\n"))
	}
}

// Each screen wraps its text to the terminal, so what a refused save or a read
// that failed says is shown whole: on the compose screen the refusal beside
// "Files as" and the status under it, on the progress screen why the save did
// not complete and what r does, and on the return list the rigs whose store
// did not read, with the selected row on screen.
func TestEveryScreenShowsWhatItSaysWhole(t *testing.T) {
	why := "gc-helm: conversations: gate tk-demo10 is about 2 beads still waiting on it (tk-demo1 tk-demo11), " +
		"and a conversation is about one bead. Name the one you mean: gc-helm conversations tk-demo10 --from <bead>. Nothing read."
	m := newForm(t, demoGateHelm(), Options{Subject: "tk-demo10"})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 30})
	settle(m)
	typeText(m, "q")
	_, cmd := m.Update(ctrl('s'))
	deliver(m, cmd)
	screen := screenAt(m.composeView(), 80, 30)
	if got := filesAs(screen); got != why {
		t.Fatalf("the screen shows the refusal as %q:\n%s", got, strings.Join(screen, "\n"))
	}
	if said := "Not saved: " + strings.TrimSuffix(why, ".") + ". Reading it again."; !strings.Contains(reads(screen), said) {
		t.Fatalf("the screen does not show the status whole, %q:\n%s", said, strings.Join(screen, "\n"))
	}

	saveErr := "gc-helm: open: filed conversation tk-c on tk-a, but its reply onto gate tk-g did not write: the store did not answer within 30s"
	f := &fakeHelm{about: map[string]About{"tk-a": subjectAbout("tk-a", "gc-toolkit")},
		saveResp: Saved{Subject: "tk-a", Conversation: "tk-c", Filed: true}, saveErr: errors.New(saveErr)}
	m = newForm(t, f, Options{Subject: "tk-a"})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 30})
	settle(m)
	typeText(m, "q")
	_, cmd = m.Update(ctrl('s'))
	deliver(m, cmd)
	text := reads(screenAt(m.progressView(), 80, 30))
	for _, said := range []string{
		"✗ the save did not complete, so no sitting was started: " + saveErr,
		"r saves it again onto conversation tk-c, which completes it or says why it cannot, and files no other.",
	} {
		if !strings.Contains(text, said) {
			t.Fatalf("the progress screen does not show %q whole:\n%s", said, m.progressView())
		}
	}

	unread := []string{"gc-toolkit", "gascity", "a-rig-whose-name-runs-long", "another-rig-with-a-long-name", "docs"}
	f = &fakeHelm{city: City{Conversations: convs(30), Unread: unread}}
	m = newForm(t, f, Options{Return: true})
	m.Update(tea.WindowSizeMsg{Width: 80, Height: 12})
	loadCity(m)
	for range 29 {
		m.Update(key(tea.KeyDown))
	}
	v := m.returnView()
	screen = screenAt(v, 80, 12)
	if said := "Not listed: the store of " + strings.Join(unread, ", ") + " could not be read."; !strings.Contains(reads(screen), said) {
		t.Fatalf("the return list does not show %q whole:\n%s", said, v)
	}
	if n := lines(v); n > 12 || !strings.Contains(marked(screen, "› "), "tk-c29") {
		t.Fatalf("on a 12-line terminal the view is %d lines, or the selected row is not on screen:\n%s", n, v)
	}
}

// wrapAtSpaces breaks a line only at its spaces, measured in display cells,
// so an id or a rig with a hyphen in it stays on one line and a wide rune
// counts as the two columns it takes. A word wider than the line is cut, at
// its hyphen where it has one, the spaces a line starts with stay, a style
// carries onto each line it wraps onto, and a line that fits is left as it is.
func TestWrapAtSpacesBreaksOnlyAtSpaces(t *testing.T) {
	for _, c := range []struct {
		s     string
		width int
		want  []string
	}{
		{"answering gate tk-demo10", 18, []string{"answering gate", "tk-demo10"}},
		{"in rig gc-toolkit, answering", 11, []string{"in rig", "gc-toolkit,", "answering"}},
		{"in rig gc-toolkit, answering", 10, []string{"in rig", "gc-", "toolkit,", "answering"}},
		{"確認 確認 確認 tk-a1b2", 9, []string{"確認 確認", "確認", "tk-a1b2"}},
		{"see https://example.com/a/very/long/path", 12, []string{"see", "https://exam", "ple.com/a/ve", "ry/long/path"}},
		{"  · held: review — 2 review threads wait", 20, []string{"  · held: review — 2", "review threads wait"}},
		{"fits\nthis one does not fit", 9, []string{"fits", "this one", "does not", "fit"}},
	} {
		got := strings.Split(wrapAtSpaces(c.s, c.width), "\n")
		if strings.Join(got, "|") != strings.Join(c.want, "|") {
			t.Errorf("wrapAtSpaces(%q, %d) = %q, want %q", c.s, c.width, got, c.want)
		}
		for _, l := range got {
			if lipgloss.Width(l) > c.width {
				t.Errorf("wrapAtSpaces(%q, %d): %q is %d cells wide", c.s, c.width, l, lipgloss.Width(l))
			}
		}
	}
	styled := badStyle.Render("Not saved: the store did not answer")
	for _, l := range strings.Split(wrapAtSpaces(styled, 12), "\n") {
		if text := sgr.ReplaceAllString(l, ""); l != badStyle.Render(text) {
			t.Errorf("line %q does not carry the style on its own, as %q does", l, badStyle.Render(text))
		}
	}
	if s := "a line far wider than its terminal"; wrapAtSpaces(s, 0) != s {
		t.Errorf("a terminal whose width is not known yet wrapped %q", s)
	}
}
