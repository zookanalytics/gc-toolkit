package form

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"charm.land/bubbles/v2/textarea"
	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// Options are what the command line fills in before the form opens.
type Options struct {
	Subject  string   // a subject reference: a bead, conversation or gate id, or a PR number or URL
	Rig      string   // a new topic's rig
	Model    string   // the converse variant; empty takes Models[0]
	Question string   // the question, as given
	Models   []string // the converse variants, the default first
	Return   bool     // open on the return list
	DraftDir string   // where the question of a cancelled form is kept
	Debounce time.Duration
	Poll     time.Duration
	Refresh  time.Duration // how often the return list reads the city again
	Now      func() time.Time
}

type screen int

const (
	composeScreen screen = iota
	progressScreen
	returnScreen
)

type field int

const (
	subjectField field = iota
	rigField
	modelField
	questionField
	contextField
)

// lookup is one `conversations <ref>` read, keyed by the reference it was
// asked for.
type lookup struct {
	pending bool
	about   About
	err     error
}

type (
	aboutMsg struct {
		ref   string
		about About
		err   error
	}
	cityMsg struct {
		city City
		err  error
	}
	debounceMsg struct{ seq int }
	savedMsg    struct {
		saved Saved
		err   error
	}
	startedMsg struct{ err error }
	pollMsg    struct{}
	readyMsg   struct {
		conv Conversation
		err  error
	}
	cityTickMsg struct{}
	attachedMsg struct{ err error }
)

// newChoice is the context row that files the question as a new conversation.
const newChoice = ""

// Model is the form. It is driven by bubbletea, and every read and write it
// asks for runs as a command, so a key press is handled while a lookup runs.
type Model struct {
	helm Helm
	opt  Options
	ctx  context.Context

	scr           screen
	width, height int

	subject  textinput.Model
	question textarea.Model
	focus    field

	seq      int // edits of the subject field, so a stale debounce does nothing
	lookups  map[string]*lookup
	city     *City
	cityErr  string
	cityBusy bool
	ticking  bool // a refresh of the return list is scheduled

	rig   string // the rig a new topic is filed in, chosen by name and only by the operator
	model int    // index into opt.Models

	choice        string // newChoice, or the conversation the operator chose
	choiceTouched bool
	cursor        int

	// The progress of a submit.
	saving    bool
	saved     *Saved
	partial   string // a new subject a failed save filed without its conversation
	existing  bool   // the conversation was chosen, not filed
	starting  bool
	started   bool
	startErr  string
	readiness string
	pollErr   string
	leaving   bool // the operator left while a save or a start ran, so the form leaves once it lands

	retCursor int
	status    string
	note      string // printed once the form has left the terminal
}

// New builds the form over helm.
func New(ctx context.Context, helm Helm, opt Options) *Model {
	if opt.Debounce <= 0 {
		opt.Debounce = 400 * time.Millisecond
	}
	if opt.Poll <= 0 {
		opt.Poll = 3 * time.Second
	}
	if opt.Refresh <= 0 {
		opt.Refresh = 10 * time.Second
	}
	if opt.Now == nil {
		opt.Now = time.Now
	}
	if len(opt.Models) == 0 {
		opt.Models = []string{"opus"}
	}
	m := &Model{helm: helm, opt: opt, ctx: ctx, lookups: map[string]*lookup{}, rig: opt.Rig}
	for i, v := range opt.Models {
		if v == opt.Model {
			m.model = i
		}
	}

	m.subject = textinput.New()
	m.subject.Prompt = ""
	m.subject.Placeholder = "a bead id, PR number or URL — empty for a new topic"
	m.subject.SetValue(opt.Subject)
	m.subject.SetWidth(60)

	m.question = textarea.New()
	m.question.ShowLineNumbers = false
	m.question.MaxHeight = 0 // a question is as long as the operator makes it
	m.question.CharLimit = 0
	m.question.Placeholder = "What do you want to talk about? Enter adds a line."
	m.question.SetWidth(76)
	m.question.SetHeight(8)
	m.question.SetValue(opt.Question)

	if opt.Return {
		m.scr = returnScreen
	}
	if opt.Subject != "" || opt.Rig != "" {
		m.setFocus(questionField)
	} else {
		m.setFocus(subjectField)
	}
	return m
}

// Note is what the form says once it has left the terminal: where a cancelled
// question was kept, or where the conversation it saved stands.
func (m *Model) Note() string { return m.note }

// Init starts the background reads: the city's conversations and rigs, and the
// subject the command line named. The return list reads the city again while
// it is on screen.
func (m *Model) Init() tea.Cmd {
	cmds := []tea.Cmd{m.loadCity()}
	if ref := m.ref(); ref != "" {
		cmds = append(cmds, m.lookup(ref))
	}
	if m.scr == returnScreen {
		cmds = append(cmds, m.refreshCity())
	}
	return tea.Batch(cmds...)
}

// refreshCity schedules the next read of the city for the return list, so the
// readiness it shows stays current. One refresh is scheduled at a time, and it
// schedules the next only while the list is on screen.
func (m *Model) refreshCity() tea.Cmd {
	if m.ticking {
		return nil
	}
	m.ticking = true
	return tea.Tick(m.opt.Refresh, func(time.Time) tea.Msg { return cityTickMsg{} })
}

func (m *Model) ref() string { return strings.TrimSpace(m.subject.Value()) }

func (m *Model) newTopic() bool { return m.ref() == "" }

func (m *Model) loadCity() tea.Cmd {
	if m.cityBusy {
		return nil
	}
	m.cityBusy = true
	return func() tea.Msg {
		c, err := m.helm.City(m.ctx)
		return cityMsg{city: c, err: err}
	}
}

// lookup reads the subject ref names, once per reference while that read is
// running or has answered. A read that failed is read again.
func (m *Model) lookup(ref string) tea.Cmd {
	if ref == "" {
		return nil
	}
	if l, ok := m.lookups[ref]; ok && (l.pending || l.err == nil) {
		return nil
	}
	m.lookups[ref] = &lookup{pending: true}
	return func() tea.Msg {
		a, err := m.helm.About(m.ctx, ref)
		return aboutMsg{ref: ref, about: a, err: err}
	}
}

func (m *Model) setFocus(f field) {
	m.focus = f
	m.subject.Blur()
	m.question.Blur()
	switch f {
	case subjectField:
		m.subject.Focus()
	case questionField:
		m.question.Focus()
	}
}

// fields is the focus order. The rig is a field only for a new topic, and the
// context list only when it holds something to choose.
func (m *Model) fields() []field {
	fs := []field{subjectField}
	if m.newTopic() {
		fs = append(fs, rigField)
	}
	fs = append(fs, modelField, questionField)
	if len(m.contextRows()) > 1 {
		fs = append(fs, contextField)
	}
	return fs
}

func (m *Model) moveFocus(step int) tea.Cmd {
	fs := m.fields()
	at := 0
	for i, f := range fs {
		if f == m.focus {
			at = i
		}
	}
	leaving := m.focus
	m.setFocus(fs[(at+step+len(fs))%len(fs)])
	if leaving == subjectField {
		return m.lookup(m.ref())
	}
	return nil
}

// current is the finished lookup of the subject field as it reads now, or nil.
func (m *Model) current() *lookup {
	l := m.lookups[m.ref()]
	if l == nil || l.pending {
		return nil
	}
	return l
}

// contextRow is one choosable row under the subject.
type contextRow struct {
	kind  string // "new", "conversation", "hold", "candidate"
	id    string
	label string
}

func (m *Model) contextRows() []contextRow {
	l := m.current()
	if l == nil || l.err != nil {
		return nil
	}
	a := l.about
	if len(a.Candidates) > 0 {
		var rows []contextRow
		for _, c := range a.Candidates {
			rows = append(rows, contextRow{kind: "candidate", id: c.ID, label: fmt.Sprintf("%s  in %s — %s", c.ID, c.Rig, c.Title)})
		}
		return rows
	}
	rows := []contextRow{{kind: "new", id: newChoice, label: "a new conversation with your question"}}
	for _, c := range a.Conversations {
		mark := c.Readiness
		if c.Attached() {
			mark += ", attached"
		}
		rows = append(rows, contextRow{kind: "conversation", id: c.ID, label: fmt.Sprintf("%s  %s — %s", c.ID, mark, c.Title)})
	}
	for _, h := range a.Holds {
		if h.ID == "" {
			continue
		}
		rows = append(rows, contextRow{kind: "hold", id: h.ID, label: fmt.Sprintf("%s  held: %s — %s (becomes the subject)", h.ID, h.Held, h.Title)})
	}
	return rows
}

// hostingRigs are the rigs a new topic can be filed in, in the city's order.
func (m *Model) hostingRigs() []Rig {
	if m.city == nil {
		return nil
	}
	var rs []Rig
	for _, r := range m.city.Rigs {
		if r.Hosts() {
			rs = append(rs, r)
		}
	}
	return rs
}

// cycleRig moves the new topic's rig to the next or previous rig that can host
// a sitting. Only the operator's key moves it.
func (m *Model) cycleRig(step int) {
	rs := m.hostingRigs()
	if len(rs) == 0 {
		return
	}
	at := -1
	for i, r := range rs {
		if r.Name == m.rig {
			at = i
		}
	}
	if at < 0 {
		if step > 0 {
			at = -1
		} else {
			at = 0
		}
	}
	m.rig = rs[(at+step+len(rs))%len(rs)].Name
}

// destination is where a submit would file the question, and whether it is
// settled. It reads only what was verified for the subject field as it reads
// now, so a result for an earlier reference never stands in for it.
func (m *Model) destination() (string, bool) {
	if m.newTopic() {
		if m.rig == "" {
			if m.city == nil && m.cityErr == "" {
				return "a new topic: loading the rigs it can be filed in…", false
			}
			if m.city == nil {
				return fmt.Sprintf("a new topic: the rigs it can be filed in did not read (%s)", m.cityErr), false
			}
			return "a new topic: choose its rig (Tab to Rig, then ←/→)", false
		}
		if m.city != nil {
			for _, r := range m.city.Rigs {
				if r.Name == m.rig {
					if !r.Converse {
						return fmt.Sprintf("rig %s carries no converse template, so no sitting can start there", m.rig), false
					}
					if r.Suspended {
						return fmt.Sprintf("rig %s is suspended, so no sitting can start there", m.rig), false
					}
					return fmt.Sprintf("a new subject in rig %s", m.rig), true
				}
			}
			return fmt.Sprintf("rig %s is not a rig of this city", m.rig), false
		}
		if m.cityErr != "" {
			return fmt.Sprintf("the rigs did not read (%s), so rig %s cannot be checked", m.cityErr, m.rig), false
		}
		return fmt.Sprintf("a new subject in rig %s: checking the rig…", m.rig), false
	}
	ref := m.ref()
	l := m.lookups[ref]
	if l == nil || l.pending {
		return fmt.Sprintf("looking up %s…", ref), false
	}
	if l.err != nil {
		return l.err.Error(), false
	}
	a := l.about
	if len(a.Candidates) > 0 {
		return fmt.Sprintf("%s is recorded by more than one live bead: choose the one you mean below", ref), false
	}
	if a.Refusal != "" {
		return a.Refusal, false
	}
	d := fmt.Sprintf("a conversation on %s — %s — in rig %s", a.Subject.ID, a.Subject.Title, a.Subject.Rig)
	if a.Gate != "" {
		d += fmt.Sprintf(", answering gate %s", a.Gate)
	}
	return d, true
}

// chosen is the open conversation the operator chose, when it is still one of
// the subject's.
func (m *Model) chosen() (Conversation, bool) {
	l := m.current()
	if m.choice == newChoice || l == nil {
		return Conversation{}, false
	}
	for _, c := range l.about.Conversations {
		if c.ID == m.choice {
			return c, true
		}
	}
	return Conversation{}, false
}

func (m *Model) modelName() string { return m.opt.Models[m.model] }

// Update handles one message.
func (m *Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		w := msg.Width - 4
		if w > 100 {
			w = 100
		}
		if w > 20 {
			m.question.SetWidth(w)
			m.subject.SetWidth(w - 12)
		}
		return m, nil
	case aboutMsg:
		l := m.lookups[msg.ref]
		if l == nil {
			return m, nil
		}
		l.pending, l.about, l.err = false, msg.about, msg.err
		// A conversation id typed as the subject names that conversation, so it
		// is the choice until the operator makes another.
		if msg.err == nil && msg.ref == m.ref() && !m.choiceTouched && msg.about.Conversation != "" && msg.about.Closed == nil {
			m.choice = msg.about.Conversation
		}
		return m, nil
	case cityMsg:
		m.cityBusy = false
		if msg.err != nil {
			m.cityErr = msg.err.Error()
			return m, nil
		}
		c := msg.city
		m.city, m.cityErr = &c, ""
		return m, nil
	case debounceMsg:
		if msg.seq == m.seq {
			return m, m.lookup(m.ref())
		}
		return m, nil
	case savedMsg:
		return m, m.onSaved(msg)
	case startedMsg:
		m.starting = false
		if msg.err != nil {
			m.startErr = msg.err.Error()
		} else {
			m.started, m.startErr = true, ""
		}
		if m.leaving {
			return m, m.quit()
		}
		if msg.err != nil {
			return m, nil
		}
		return m, m.poll(0)
	case pollMsg:
		if m.saved == nil {
			return m, nil
		}
		conv := m.saved.Conversation
		return m, func() tea.Msg {
			a, err := m.helm.About(m.ctx, conv)
			if err != nil {
				return readyMsg{err: err}
			}
			for _, c := range a.Conversations {
				if c.ID == conv {
					return readyMsg{conv: c}
				}
			}
			return readyMsg{err: fmt.Errorf("conversation %s is no longer open", conv)}
		}
	case readyMsg:
		if msg.err != nil {
			m.pollErr = msg.err.Error()
			return m, m.poll(m.opt.Poll)
		}
		m.pollErr, m.readiness = "", msg.conv.Readiness
		if m.readiness == Ready || m.readiness == Ended {
			return m, nil
		}
		return m, m.poll(m.opt.Poll)
	case cityTickMsg:
		m.ticking = false
		if m.scr == returnScreen {
			return m, tea.Batch(m.loadCity(), m.refreshCity())
		}
		return m, nil
	case attachedMsg:
		if msg.err != nil {
			m.note = fmt.Sprintf("The attach did not run: %v", msg.err)
		}
		return m, tea.Quit
	case tea.PasteMsg:
		return m, m.typeInto(msg)
	case tea.KeyPressMsg:
		return m, m.key(msg)
	}
	return m, m.typeInto(msg)
}

// typeInto hands a message to the field that has focus.
func (m *Model) typeInto(msg tea.Msg) tea.Cmd {
	if m.scr != composeScreen {
		return nil
	}
	switch m.focus {
	case subjectField:
		before := m.subject.Value()
		var cmd tea.Cmd
		m.subject, cmd = m.subject.Update(msg)
		if m.subject.Value() != before {
			m.seq++
			seq := m.seq
			m.choice, m.choiceTouched, m.cursor = newChoice, false, 0
			return tea.Batch(cmd, tea.Tick(m.opt.Debounce, func(time.Time) tea.Msg { return debounceMsg{seq: seq} }))
		}
		return cmd
	case questionField:
		var cmd tea.Cmd
		m.question, cmd = m.question.Update(msg)
		return cmd
	}
	return nil
}

func (m *Model) key(k tea.KeyPressMsg) tea.Cmd {
	s := k.String()
	if s == "ctrl+c" {
		if m.leaving {
			return m.leaveNow()
		}
		return m.quit()
	}
	switch m.scr {
	case progressScreen:
		return m.progressKey(s)
	case returnScreen:
		return m.returnKey(s)
	}
	switch s {
	case "esc":
		return m.quit()
	case "ctrl+s":
		return m.submit()
	case "ctrl+r":
		m.scr = returnScreen
		return tea.Batch(m.loadCity(), m.refreshCity())
	case "tab":
		return m.moveFocus(1)
	case "shift+tab":
		return m.moveFocus(-1)
	}
	switch m.focus {
	case subjectField:
		if s == "enter" {
			return m.moveFocus(1)
		}
	case rigField:
		switch s {
		case "left":
			m.cycleRig(-1)
		case "right", "space":
			m.cycleRig(1)
		}
		return nil
	case modelField:
		switch s {
		case "left":
			m.model = (m.model - 1 + len(m.opt.Models)) % len(m.opt.Models)
		case "right", "space":
			m.model = (m.model + 1) % len(m.opt.Models)
		}
		return nil
	case contextField:
		rows := m.contextRows()
		switch s {
		case "up":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down":
			if m.cursor < len(rows)-1 {
				m.cursor++
			}
		case "space", "enter":
			return m.choose(rows)
		}
		return nil
	}
	return m.typeInto(k)
}

// choose takes the context row under the cursor. A conversation becomes the
// choice; the new-conversation row clears it; a hold or a PR's candidate
// becomes the subject, which is looked up in turn. Nothing else changes: the
// question stays as typed.
func (m *Model) choose(rows []contextRow) tea.Cmd {
	if m.cursor >= len(rows) {
		return nil
	}
	r := rows[m.cursor]
	switch r.kind {
	case "new", "conversation":
		m.choice, m.choiceTouched = r.id, true
		return nil
	default:
		m.subject.SetValue(r.id)
		m.seq++
		m.choice, m.choiceTouched, m.cursor = newChoice, false, 0
		return m.lookup(r.id)
	}
}

// submit files the question, or starts the conversation chosen, once the
// destination is settled. Nothing is written before then.
func (m *Model) submit() tea.Cmd {
	dest, ok := m.destination()
	if !ok {
		m.status = "Not saved: " + dest
		cmd := m.reread()
		if cmd != nil {
			m.status = strings.TrimSuffix(m.status, ".") + ". Reading it again."
		}
		return cmd
	}
	q := m.question.Value()
	blank := strings.TrimSpace(q) == ""
	if m.choice != newChoice {
		c, ok := m.chosen()
		if !ok {
			m.status = fmt.Sprintf("Not started: conversation %s is not among %s's open conversations now; choose again", m.choice, m.ref())
			return nil
		}
		if !blank {
			m.status = "Not started: your question is not sent into an existing conversation. Choose \"a new conversation\" to file it, or clear it to continue " + c.ID + "."
			return nil
		}
		sub := m.current().about.Subject.ID
		m.saved = &Saved{Subject: sub, Conversation: c.ID}
		m.existing = true
		m.scr = progressScreen
		return m.start()
	}
	if blank {
		m.status = "Not saved: type your question first."
		return nil
	}
	req := SaveRequest{Question: q}
	if m.newTopic() {
		req.Rig = m.rig
	} else {
		a := m.current().about
		req.Ref = a.Subject.ID
		if a.Gate != "" {
			req.Ref = a.Gate
		}
	}
	m.scr, m.saving, m.status = progressScreen, true, ""
	return func() tea.Msg {
		sv, err := m.helm.Save(m.ctx, req)
		return savedMsg{saved: sv, err: err}
	}
}

// reread reads again what a refused submit was refused on, when that read can
// answer differently now: a subject lookup that failed or named a refusal,
// such as a suspended rig, or the city's rigs for a new topic. Nothing is
// filed, and the next Ctrl+S reads the new answer.
func (m *Model) reread() tea.Cmd {
	if m.newTopic() {
		if m.rig == "" && m.cityErr == "" {
			return nil
		}
		return m.loadCity()
	}
	ref := m.ref()
	l := m.lookups[ref]
	if l == nil || l.pending || (l.err == nil && l.about.Refusal == "") {
		return nil
	}
	delete(m.lookups, ref)
	return m.lookup(ref)
}

func (m *Model) onSaved(msg savedMsg) tea.Cmd {
	m.saving = false
	if msg.err != nil || !msg.saved.Filed {
		m.scr = composeScreen
		why := "the save answered without filing a conversation"
		if msg.err != nil {
			why = msg.err.Error()
		}
		m.status = "Not saved: " + why + ". Your question is still here."
		var cmd tea.Cmd
		if msg.saved.Subject != "" && m.newTopic() {
			// The new subject was filed and its conversation was not: the next
			// save files the question onto that subject, never a second one.
			m.partial = msg.saved.Subject
			m.subject.SetValue(msg.saved.Subject)
			m.seq++
			m.status += fmt.Sprintf(" Subject %s was filed; saving again files your question onto it.", msg.saved.Subject)
			cmd = m.lookup(msg.saved.Subject)
		}
		if m.leaving {
			return m.quit()
		}
		return cmd
	}
	sv := msg.saved
	m.saved = &sv
	return m.start()
}

func (m *Model) start() tea.Cmd {
	m.starting, m.startErr = true, ""
	conv, model := m.saved.Conversation, m.modelName()
	return func() tea.Msg {
		return startedMsg{err: m.helm.Start(m.ctx, conv, model)}
	}
}

func (m *Model) poll(after time.Duration) tea.Cmd {
	if after <= 0 {
		return func() tea.Msg { return pollMsg{} }
	}
	return tea.Tick(after, func(time.Time) tea.Msg { return pollMsg{} })
}

func (m *Model) progressKey(s string) tea.Cmd {
	switch s {
	case "enter":
		if m.saved != nil && !m.saving && !m.starting {
			return m.attach(m.saved.Conversation)
		}
	case "r":
		if m.saved != nil && m.startErr != "" && !m.starting {
			return m.start()
		}
	case "esc", "q":
		return m.quit()
	}
	return nil
}

// returnRows are the conversations to return to: those no terminal is attached
// to first, by readiness, the newest first within each.
func (m *Model) returnRows() []Conversation {
	if m.city == nil {
		return nil
	}
	rank := map[string]int{Ready: 0, Preparing: 1, Starting: 2, Ended: 3, Queued: 4}
	rows := append([]Conversation(nil), m.city.Conversations...)
	sort.SliceStable(rows, func(i, j int) bool {
		a, b := rows[i], rows[j]
		if a.Attached() != b.Attached() {
			return !a.Attached()
		}
		if rank[a.Readiness] != rank[b.Readiness] {
			return rank[a.Readiness] < rank[b.Readiness]
		}
		return a.CreatedAt > b.CreatedAt
	})
	return rows
}

func (m *Model) returnKey(s string) tea.Cmd {
	rows := m.returnRows()
	switch s {
	case "up":
		if m.retCursor > 0 {
			m.retCursor--
		}
	case "down":
		if m.retCursor < len(rows)-1 {
			m.retCursor++
		}
	case "enter":
		if m.retCursor < len(rows) {
			return m.attach(rows[m.retCursor].ID)
		}
	case "r":
		return m.loadCity()
	case "ctrl+r", "ctrl+n":
		m.scr = composeScreen
	case "esc", "q":
		return m.quit()
	}
	return nil
}

func (m *Model) attach(conv string) tea.Cmd {
	return tea.ExecProcess(m.helm.AttachCommand(conv), func(err error) tea.Msg { return attachedMsg{err: err} })
}

// quit leaves the form. While a save or a start runs, the form leaves once it
// lands instead. The verb's process outlives the form, and once the form's
// end of its output pipes closes, the verb's next write kills it, which can
// cut a save off between a new subject and its conversation. A question the
// form did not save is kept in a file, named in the note, so leaving never
// loses it.
func (m *Model) quit() tea.Cmd {
	if m.saving || m.starting {
		m.leaving = true
		return nil
	}
	switch {
	case m.saved != nil:
		m.note = m.savedNote()
	case strings.TrimSpace(m.question.Value()) != "":
		filed := "Nothing was filed."
		if m.partial != "" {
			filed = fmt.Sprintf("Subject %s was filed, and its conversation was not.", m.partial)
		}
		m.note = m.keepDraft(filed)
	}
	return tea.Quit
}

// leaveNow leaves at once, on a second Ctrl+C while a save or a start runs.
// What that run did is unknown, so the note says so and keeps the question.
func (m *Model) leaveNow() tea.Cmd {
	if m.saved != nil {
		m.note = m.savedNote()
	} else {
		m.note = m.keepDraft("You left while your question was being saved, so whether it was filed is unknown: gc-helm.sh conversations lists the open conversations.")
	}
	return tea.Quit
}

func (m *Model) savedNote() string {
	s := m.saved
	what := "is saved"
	if m.existing {
		what = "was chosen"
	}
	state := "its sitting is starting"
	switch {
	case m.starting:
		state = "you left while its sitting was being started, so whether it started is unknown"
	case m.startErr != "":
		state = "no sitting started (" + m.startErr + "); it waits in your queue"
	case m.readiness == Ready:
		state = "its sitting is ready"
	case m.readiness != "":
		state = "its sitting is " + m.readiness
	}
	return fmt.Sprintf("Conversation %s on %s %s, and %s. Return to it with: gc-helm.sh attach %s", s.Conversation, s.Subject, what, state, s.Conversation)
}

// keepDraft writes the question, unchanged, to a file in the draft directory,
// and says, after what filed says was filed, where the question is and the
// command that files it again on the subject or rig the form was filing it on.
func (m *Model) keepDraft(filed string) string {
	q := m.question.Value()
	path, err := m.writeDraft(q)
	if err != nil {
		return filed + " The question could not be kept in a file. Here it is:\n\n" + q
	}
	again := "gc-helm.sh engage --new-subject --rig <rig>"
	switch {
	case !m.newTopic():
		again = "gc-helm.sh engage " + shellQuote(m.ref())
	case m.rig != "":
		again = "gc-helm.sh engage --new-subject --rig " + shellQuote(m.rig)
	}
	return fmt.Sprintf("%s Your question is kept in %s; start it again with: %s --reason \"$(cat %s)\"", filed, path, again, shellQuote(path))
}

func (m *Model) writeDraft(q string) (string, error) {
	dir := m.opt.DraftDir
	if dir == "" {
		return "", fmt.Errorf("no draft directory")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	f, err := os.CreateTemp(dir, "engage-draft-"+m.opt.Now().UTC().Format("20060102-150405")+"-*.txt")
	if err != nil {
		return "", err
	}
	_, werr := f.WriteString(q)
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		return "", werr
	}
	return f.Name(), nil
}

// shellQuote is s as one shell word, so a command the note prints can be
// pasted as it is: a PR URL can carry & or ?, and a path can carry a space.
func shellQuote(s string) string {
	if s != "" && strings.Trim(s, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:") == "" {
		return s
	}
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

var (
	labelStyle = lipgloss.NewStyle().Bold(true)
	hintStyle  = lipgloss.NewStyle().Faint(true)
	okStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("2"))
	waitStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("3"))
	badStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("1"))
	focusStyle = lipgloss.NewStyle().Reverse(true)
)

// View renders the screen.
func (m *Model) View() tea.View {
	var s string
	switch m.scr {
	case progressScreen:
		s = m.progressView()
	case returnScreen:
		s = m.returnView()
	default:
		s = m.composeView()
	}
	v := tea.NewView(s)
	v.AltScreen = true
	return v
}

func (m *Model) label(f field, text string) string {
	if m.focus == f {
		return focusStyle.Render(text)
	}
	return labelStyle.Render(text)
}

func (m *Model) composeView() string {
	var b strings.Builder
	b.WriteString(labelStyle.Render("Start a conversation"))
	b.WriteString(hintStyle.Render("   Ctrl+S save and start · Tab next field · Ctrl+R return to a conversation · Esc cancel"))
	b.WriteString("\n\n")
	b.WriteString(m.label(subjectField, "Subject ") + "  " + m.subject.View() + "\n")
	if m.newTopic() {
		rig := m.rig
		if rig == "" {
			rig = "none chosen"
		}
		b.WriteString(m.label(rigField, "Rig     ") + "  ‹ " + rig + " ›" + hintStyle.Render("   a new topic names its rig") + "\n")
	} else if l := m.current(); l != nil && l.err == nil && l.about.Subject.Rig != "" {
		b.WriteString(labelStyle.Render("Rig     ") + "  " + l.about.Subject.Rig + hintStyle.Render("   the subject's own") + "\n")
	}
	model := m.modelName()
	if m.model == 0 {
		model += hintStyle.Render(" (default)")
	}
	b.WriteString(m.label(modelField, "Model   ") + "  ‹ " + model + " ›\n\n")
	b.WriteString(m.label(questionField, "Question") + hintStyle.Render("  Enter adds a line") + "\n")
	b.WriteString(m.question.View() + "\n\n")
	dest, ok := m.destination()
	mark := waitStyle.Render("…")
	if ok {
		mark = okStyle.Render("✓")
	} else if l := m.lookups[m.ref()]; (l != nil && !l.pending) || m.newTopic() {
		mark = badStyle.Render("✗")
	}
	b.WriteString(labelStyle.Render("Files as") + "  " + mark + " " + dest + "\n")
	if rows := m.contextRows(); len(rows) > 0 {
		b.WriteString("\n" + m.label(contextField, "On this subject") + hintStyle.Render("  Tab here, ↑/↓, Space chooses") + "\n")
		for i, r := range rows {
			cur := "  "
			if m.focus == contextField && i == m.cursor {
				cur = "› "
			}
			dot := "○ "
			if (r.kind == "new" || r.kind == "conversation") && r.id == m.choice {
				dot = "● "
			}
			if r.kind == "hold" || r.kind == "candidate" {
				dot = "→ "
			}
			b.WriteString(cur + dot + r.label + "\n")
		}
	} else if l := m.current(); l != nil && l.err == nil && !l.about.HoldsRead {
		b.WriteString(hintStyle.Render("What holds the subject did not read.") + "\n")
	}
	if l := m.current(); l != nil && l.err == nil && l.about.Closed != nil {
		b.WriteString(hintStyle.Render(l.about.Closed.Said) + "\n")
	}
	if m.status != "" {
		b.WriteString("\n" + badStyle.Render(m.status) + "\n")
	}
	return b.String()
}

func (m *Model) progressView() string {
	var b strings.Builder
	b.WriteString(labelStyle.Render("Start a conversation") + "\n\n")
	switch {
	case m.saving:
		b.WriteString(waitStyle.Render("…") + " saving your question\n")
	case m.saved != nil && m.existing:
		b.WriteString(okStyle.Render("✓") + fmt.Sprintf(" conversation %s on %s, chosen\n", m.saved.Conversation, m.saved.Subject))
	case m.saved != nil:
		b.WriteString(okStyle.Render("✓") + fmt.Sprintf(" saved: conversation %s on %s holds your question\n", m.saved.Conversation, m.saved.Subject))
	}
	switch {
	case m.starting:
		b.WriteString(waitStyle.Render("…") + fmt.Sprintf(" starting its sitting on %s\n", m.modelName()))
	case m.startErr != "":
		b.WriteString(badStyle.Render("✗") + " no sitting started: " + m.startErr + "\n")
		b.WriteString(hintStyle.Render("  The conversation waits in your queue. r retries the start.") + "\n")
	case m.started:
		switch m.readiness {
		case Ready:
			b.WriteString(okStyle.Render("✓") + " ready: the sitting has posted its framing\n")
		case Ended:
			b.WriteString(badStyle.Render("✗") + " the sitting ended before it was ready; Enter holds the conversation in a new one\n")
		case "":
			b.WriteString(waitStyle.Render("…") + " sitting started; reading its state\n")
		default:
			b.WriteString(waitStyle.Render("…") + " sitting " + m.readiness + "\n")
		}
		if m.pollErr != "" {
			b.WriteString(hintStyle.Render("  its state did not read: "+m.pollErr) + "\n")
		}
	}
	switch {
	case m.leaving:
		b.WriteString("\n" + waitStyle.Render("Leaving once this lands, so it is not cut off midway. Ctrl+C again leaves now.") + "\n")
	case m.saved != nil && !m.saving:
		b.WriteString("\n" + hintStyle.Render("Enter attaches · q leaves it running; return with gc-helm.sh attach") + "\n")
	}
	return b.String()
}

func (m *Model) returnView() string {
	var b strings.Builder
	b.WriteString(labelStyle.Render("Return to a conversation"))
	b.WriteString(hintStyle.Render("   ↑/↓ choose · Enter attaches · r refreshes · Ctrl+R start one · Esc leaves") + "\n\n")
	if m.city == nil {
		if m.cityErr != "" {
			b.WriteString(badStyle.Render("The conversations did not read: "+m.cityErr) + "\n")
		} else {
			b.WriteString(waitStyle.Render("…") + " reading the open conversations\n")
		}
		return b.String()
	}
	rows := m.returnRows()
	if len(rows) == 0 {
		b.WriteString("No open conversation.\n")
	}
	for i, c := range rows {
		cur := "  "
		if i == m.retCursor {
			cur = "› "
		}
		mark := c.Readiness
		if c.Attached() {
			mark += ", attached"
		}
		topic := c.Title
		if c.SubjectTitle != "" && c.SubjectTitle != c.Title {
			topic += hintStyle.Render("  on " + c.Subject + ": " + c.SubjectTitle)
		}
		b.WriteString(fmt.Sprintf("%s%-22s %s  %s  %s\n", cur, mark, c.ID, hintStyle.Render(c.Rig), topic))
	}
	if len(m.city.Unread) > 0 {
		b.WriteString("\n" + badStyle.Render("Not listed: the store of "+strings.Join(m.city.Unread, ", ")+" did not answer.") + "\n")
	}
	return b.String()
}
