package form

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"charm.land/bubbles/v2/textinput"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// Options are what the command line fills in before the form opens.
type Options struct {
	Subject  string   // a subject reference, as engage takes one: a bead, conversation or gate id, or a PR number or URL
	From     string   // the bead the subject, a gate, was reached from, as engage's --from names it
	Rig      string   // a new topic's rig, by its name, which fills in an empty subject
	Model    string   // the converse variant; empty takes Models[0]
	Question string   // the question, as given
	Models   []string // the converse variants, the default first
	NoAttach bool     // leave once the sitting starts, rather than attach to it
	Return   bool     // open on the return list
	DraftDir string   // where the question of a cancelled form is kept
	Debounce time.Duration
	Refresh  time.Duration // how often a list page, the return list or People, reads the city again
	Now      func() time.Time
}

type screen int

const (
	composeScreen screen = iota
	progressScreen
	returnScreen
	peopleScreen
)

// pages are the screens the tabs at the top of the form name, in the order the
// tabs show them, and pageNames what the tabs call them. A submit's progress is
// no page: it shows what a save and a start do as they land.
var (
	pages     = []screen{composeScreen, returnScreen, peopleScreen}
	pageNames = map[screen]string{composeScreen: "Start a conversation", returnScreen: "Return to a conversation", peopleScreen: "People"}
)

type field int

// The fields, in the order the screen shows them.
const (
	subjectField field = iota
	questionField
	modelField
	attachField
	contextField
	// tabsField is the row of tabs above the subject, which ↑ from the
	// subject reaches. Tab does not move through it, so the question stays
	// one Tab after the subject.
	tabsField
)

// lookup is one `conversations <ref>` read, keyed by the reference it was
// asked for and the bead that reference was reached from (lookupKey).
type lookup struct {
	pending    bool
	refreshing bool // read again while its answer stays on screen (refresh)
	about      About
	err        error
}

// source is where the subject field's text came from, which decides how the
// form reads it.
type source int

const (
	// typed is text the operator typed. A rig's whole name or prefix,
	// ignoring case, names that rig, and other text is a subject to look up.
	// The city's rigs tell the two apart, so typed text settles only once
	// they have been read.
	typed source = iota
	// rigFlag is the rig --rig named, by its exact name, as open
	// --new-subject --rig takes it.
	rigFlag
	// given is a reference engage's command line named as the subject, or a
	// bead the form put in the field: a gate or a bead chosen from what holds
	// a subject, an anchor chosen for a PR, or a subject a save filed. It is
	// looked up, and never read as a rig.
	given
)

// lookupKey is what a lookup reads: the reference, and the bead it was reached
// from, which a gate several beads wait on is about when it is one of them. A
// reference the operator typed was reached from nothing.
type lookupKey struct{ ref, from string }

type (
	aboutMsg struct {
		key   lookupKey
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
	startedMsg  struct{ err error }
	cityTickMsg struct{}
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
	src      source // where the subject field's text came from; an edit makes it typed
	question questionEditor
	focus    field

	seq      int // edits of the subject field, so a stale debounce does nothing
	lookups  map[lookupKey]*lookup
	from     string // the subject a gate in the subject field was chosen from, until the field is edited
	city     *City
	cityAt   time.Time // when city was read
	cityErr  string    // why the last read of the city failed; city stays the last one read
	cityBusy bool
	ticking  bool // a refresh of the list pages is scheduled

	model  int  // index into opt.Models; -1 while it is opt.Model, which no variant carries
	attach bool // the operator's choice to attach to the sitting once it starts; off, the form leaves then

	choice        string // newChoice, or the conversation the operator chose
	choiceTouched bool
	cursor        int

	// The progress of a submit.
	req      SaveRequest // what the save sent; a save again sends it with the conversation it filed
	waits    string      // the suspended rig the save files in, where no sitting starts, or ""
	saving   bool
	saved    *Saved
	saveErr  string // why the save that filed saved's conversation did not complete
	partial  string // a new subject a failed save filed without its conversation
	existing bool   // the conversation was chosen, not filed
	starting bool
	startErr string
	leaving  bool // the operator left while a save or a start ran, so the form leaves once it lands

	// How the form leaves the terminal.
	attaching bool      // the form has kept a hand-off, so it keeps no other
	attachCmd *exec.Cmd // the command the form left to run (Attach): an attach, or a seat's verb
	left      bool      // the form has left by its own path, so the note is what it says

	// The return list's selection is a conversation, so a refresh that re-sorts
	// the list leaves it on the conversation the operator picked.
	retSel string
	retAt  int // where retSel was last in the list, for ↑/↓ once it has left the list

	// The People page's selection is a seat, so a read that changes the city's
	// rigs leaves it on the seat the operator picked.
	seatSel string
	seatAt  int // where seatSel was last in the list, as retAt is

	status string
	note   string // printed once the form has left the terminal
	kept   string // what the note says of the question kept in a file
	keptQ  string // the question kept, so a question is kept once
}

// New builds the form over helm.
func New(ctx context.Context, helm Helm, opt Options) *Model {
	if opt.Debounce <= 0 {
		opt.Debounce = 400 * time.Millisecond
	}
	if opt.Refresh <= 0 {
		opt.Refresh = 10 * time.Second
	}
	if opt.Now == nil {
		opt.Now = time.Now
	}
	if len(opt.Models) == 0 {
		// No variant was named, as when engage could not list them: a model the
		// command line named stands unconfirmed, as engage's own check lets it.
		opt.Models = []string{"claude-opus"}
		if opt.Model != "" {
			opt.Models = []string{opt.Model}
		}
	}
	m := &Model{helm: helm, opt: opt, ctx: ctx, lookups: map[lookupKey]*lookup{}, attach: !opt.NoAttach}
	if opt.Subject != "" {
		m.from = opt.From
	}
	if opt.Model != "" {
		// A model no variant carries is shown as it was named, marked, and
		// nothing starts on it until the operator picks a variant.
		m.model = -1
		for i, v := range opt.Models {
			if v == opt.Model {
				m.model = i
			}
		}
	}

	m.subject = textinput.New()
	m.subject.Prompt = ""
	// The field is 60 cells wide until the terminal's size is known, and the
	// placeholder is cut at the field's edge.
	m.subject.Placeholder = "a bead id or PR, or a rig's name or prefix for a new topic"
	// The command line's subject is a reference, as the flag-driven engage
	// takes it, and --rig names a rig as open --new-subject --rig does. Each is
	// read that way until the operator edits the field.
	switch rig := strings.TrimSpace(opt.Rig); {
	case opt.Subject != "":
		m.subject.SetValue(opt.Subject)
		m.src = given
	case rig != "":
		m.subject.SetValue(rig)
		m.src = rigFlag
	}
	m.subject.SetWidth(60)

	m.question = newQuestionEditor()
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
	if m.ref() != "" {
		cmds = append(cmds, m.lookup(m.subjectKey()))
	}
	if m.scr == returnScreen {
		cmds = append(cmds, m.refreshCity())
	}
	return tea.Batch(cmds...)
}

// refreshCity schedules the next read of the city for the list pages, so the
// readiness the return list shows, and the seats' states the People page
// shows, stay current. One refresh is scheduled at a time, and it schedules the
// next only while a list page is on screen.
func (m *Model) refreshCity() tea.Cmd {
	if m.ticking {
		return nil
	}
	m.ticking = true
	return tea.Tick(m.opt.Refresh, func(time.Time) tea.Msg { return cityTickMsg{} })
}

func (m *Model) ref() string { return strings.TrimSpace(m.subject.Value()) }

// subjectKey is what the subject field reads now: its reference, and the
// subject a gate there was chosen from.
func (m *Model) subjectKey() lookupKey { return lookupKey{ref: m.ref(), from: m.from} }

// namedRigs are the rigs of the city the subject field names, as its source
// reads it. Text the operator typed names each rig whose whole name or prefix
// it is, ignoring case: part of one names nothing, and the form completes
// none. The rig --rig named is the rig of that exact name. A reference the
// field was given names no rig. It is nil until the city's rigs have been read.
func (m *Model) namedRigs() []Rig {
	ref := m.ref()
	if m.city == nil || ref == "" {
		return nil
	}
	var rs []Rig
	for _, r := range m.city.Rigs {
		switch {
		case m.src == rigFlag && r.Name == ref,
			m.src == typed && (strings.EqualFold(ref, r.Name) || (r.Prefix != "" && strings.EqualFold(ref, r.Prefix))):
			rs = append(rs, r)
		}
	}
	return rs
}

// newTopic says whether the subject field names a new topic's rig rather than
// a subject to look up: the rig --rig named, before the city's rigs have been
// read too, or typed text the rigs say is a rig's name or prefix.
func (m *Model) newTopic() bool { return m.src == rigFlag || len(m.namedRigs()) > 0 }

// topicRig is the one rig the subject field names, which a new topic is filed
// in. Until the city's rigs have been read, it is the rig --rig named, by that
// name and not yet checked.
func (m *Model) topicRig() (Rig, bool) {
	if m.src == rigFlag && m.city == nil {
		return Rig{Name: m.ref()}, true
	}
	if rs := m.namedRigs(); len(rs) == 1 {
		return rs[0], true
	}
	return Rig{}, false
}

// suspendedRig is the suspended rig a save would file in, or "": the rig the
// subject field names, or the rig of the bead it names. Gas City starts no
// session for an agent in a suspended rig, so a conversation saved there
// starts no sitting, and it waits in the operator's queue until the rig
// resumes.
func (m *Model) suspendedRig() string {
	if m.newTopic() {
		if r, ok := m.topicRig(); ok && r.Suspended {
			return r.Name
		}
		return ""
	}
	if l := m.resolved(); l != nil && l.about.RigSuspended {
		return l.about.Subject.Rig
	}
	return ""
}

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

// lookup reads the subject k names, once per reference and origin while that
// read is running or has answered. A read that failed is read again. A
// reference already read selects the conversation it names, as its answer did.
// A subject field that names a rig holds no subject to read, so it is not
// looked up. Text typed before the city's rigs have been read is looked up,
// and its answer stands aside once they say it names a rig.
func (m *Model) lookup(k lookupKey) tea.Cmd {
	if k.ref == "" || (k == m.subjectKey() && m.newTopic()) {
		return nil
	}
	if l, ok := m.lookups[k]; ok && (l.pending || l.err == nil) {
		m.selectNamed()
		return nil
	}
	m.lookups[k] = &lookup{pending: true}
	return func() tea.Msg {
		a, err := m.helm.About(m.ctx, k.ref, k.from)
		return aboutMsg{key: k, about: a, err: err}
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

// fields is the focus order, which is the order the screen shows them in. The
// subject comes first and the question one Tab after it, since those are what
// the operator gives almost every time. The rig the subject names is shown,
// not a field, and the context list is a field only when it holds something to
// choose. The tabs above the subject are no field of this order (tabsField).
func (m *Model) fields() []field {
	fs := []field{subjectField, questionField, modelField, attachField}
	if len(m.contextRows()) > 1 {
		fs = append(fs, contextField)
	}
	return fs
}

// focusAt is where the focus is in fs.
func (m *Model) focusAt(fs []field) int {
	for i, f := range fs {
		if f == m.focus {
			return i
		}
	}
	return 0
}

// moveFocus moves the focus step fields along, as Tab and Shift+Tab do, and
// wraps around at either end.
func (m *Model) moveFocus(step int) tea.Cmd {
	fs := m.fields()
	return m.focusOn(fs[(m.focusAt(fs)+step+len(fs))%len(fs)])
}

// moveFocusArrow moves the focus to the field above or below, as ↑ and ↓ do at
// a field's first or last row, and stops at the form's first and last field.
// ↓ enters the context list on its first row.
func (m *Model) moveFocusArrow(step int) tea.Cmd {
	fs := m.fields()
	to := m.focusAt(fs) + step
	if to < 0 || to >= len(fs) {
		return nil
	}
	if fs[to] == contextField {
		m.cursor = 0
	}
	return m.focusOn(fs[to])
}

// focusOn gives f the focus. Leaving the subject field looks up the subject it
// names, however the focus leaves it.
func (m *Model) focusOn(f field) tea.Cmd {
	leaving := m.focus
	m.setFocus(f)
	if leaving == subjectField {
		return m.lookup(m.subjectKey())
	}
	return nil
}

// current is the finished lookup of the subject field as it reads now, or nil.
// A field that names a rig has none: a lookup made before the city's rigs said
// so stands aside.
func (m *Model) current() *lookup {
	if m.newTopic() {
		return nil
	}
	l := m.lookups[m.subjectKey()]
	if l == nil || l.pending {
		return nil
	}
	return l
}

// selectNamed makes the open conversation the subject field names the choice,
// as a conversation id typed as the subject names it, until the operator makes
// another. It reads the field as it reads now, so the answer for an earlier
// reference selects nothing, and a reference the field comes back to selects
// its conversation again.
func (m *Model) selectNamed() {
	l := m.current()
	if l == nil || l.err != nil || m.choiceTouched {
		return
	}
	if a := l.about; a.Conversation != "" && a.Closed == nil {
		m.choice = a.Conversation
	}
}

// contextRow is one choosable row under the subject.
type contextRow struct {
	kind  string // "new", "conversation", "hold", "candidate"
	id    string
	held  string // a hold's held: value
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
			continue // no bead to choose: heldLines shows it
		}
		rows = append(rows, contextRow{kind: "hold", id: h.ID, held: h.Held, label: fmt.Sprintf("%s  held: %s — %s (becomes the subject)", h.ID, h.Held, h.Title)})
	}
	return rows
}

// resolved is the finished lookup of the subject field when it names one
// subject, or nil. A PR number several live anchors record names candidates
// instead, and that answer carries no holds and no holds_read.
func (m *Model) resolved() *lookup {
	l := m.current()
	if l == nil || l.err != nil || len(l.about.Candidates) > 0 {
		return nil
	}
	return l
}

// heldLines are what holds the subject with no bead behind it: the PR's own
// review threads and its blocked merge verdict, which prstatus.Reasons gives
// with no ID. Engaging the subject is how a person acts on them, so each is a
// line under the rows on the subject, and no row: the cursor, Space and Ctrl+S
// never reach it. A gate or a blocker is a row (contextRows).
func (m *Model) heldLines() []string {
	l := m.resolved()
	if l == nil {
		return nil
	}
	var out []string
	for _, h := range l.about.Holds {
		if h.ID == "" {
			out = append(out, fmt.Sprintf("  · held: %s — %s", h.Held, h.Title))
		}
	}
	return out
}

// standing is how far a destination is from a save that files there.
type standing int

const (
	refused standing = iota // a save files nothing there as the form reads it now
	reading                 // a read that settles it is still running
	settled                 // a save files there
)

// destination is where a submit would file the question, and whether it is
// settled.
func (m *Model) destination() (string, bool) {
	d, st := m.where()
	return d, st == settled
}

// where is where a submit would file the question, and how far that is
// settled. It reads only what was verified for the subject field as it reads
// now, so a result for an earlier reference never stands in for it.
func (m *Model) where() (string, standing) {
	ref := m.ref()
	if ref == "" {
		return "name the subject: a bead id, a PR number or URL, or a rig's name or prefix, which starts a new topic in that rig", refused
	}
	if m.newTopic() {
		return m.topicWhere(ref)
	}
	l := m.lookups[m.subjectKey()]
	if l == nil || l.pending {
		return fmt.Sprintf("looking up %s…", ref), reading
	}
	// Until the city's rigs have been read, typed text can still be a rig's
	// name or prefix, which wins over whatever its lookup answered, so the
	// rigs settle it.
	unread := m.src == typed && m.city == nil
	if l.err != nil {
		if unread && m.cityErr == "" {
			return l.err.Error(), reading
		}
		return l.err.Error(), refused
	}
	a := l.about
	if len(a.Candidates) > 0 {
		return fmt.Sprintf("%s is recorded by more than one live bead: choose the one you mean below", ref), refused
	}
	if a.Refusal != "" {
		return a.Refusal, refused
	}
	d := fmt.Sprintf("a conversation on %s — %s — in rig %s", a.Subject.ID, a.Subject.Title, a.Subject.Rig)
	if a.Gate != "" {
		d += fmt.Sprintf(", answering gate %s", a.Gate)
	}
	switch {
	case unread && m.cityErr != "":
		return fmt.Sprintf("%s, unless %s names a rig: the rigs did not read (%s), so that cannot be checked", d, ref, m.cityErr), refused
	case unread:
		return fmt.Sprintf("%s, unless %s names a rig: checking the rigs…", d, ref), reading
	}
	return d, settled
}

// topicWhere is where a new topic is filed: the rig the subject field names.
func (m *Model) topicWhere(ref string) (string, standing) {
	if m.city == nil {
		if m.cityErr != "" {
			return fmt.Sprintf("the rigs did not read (%s), so rig %s cannot be checked", m.cityErr, ref), refused
		}
		return fmt.Sprintf("a new subject in rig %s: checking the rig…", ref), reading
	}
	rs := m.namedRigs()
	switch {
	case len(rs) == 0:
		return fmt.Sprintf("rig %s is not a rig of this city", ref), refused
	case len(rs) > 1:
		var named []string
		for _, r := range rs {
			named = append(named, r.Name)
		}
		return fmt.Sprintf("%s names more than one rig (%s): name the one you mean by a name or prefix only it has", ref, strings.Join(named, ", ")), refused
	}
	r := rs[0]
	if !r.Converse {
		return fmt.Sprintf("rig %s carries no converse template, so no sitting can start there", r.Name), refused
	}
	return fmt.Sprintf("a new subject in rig %s", r.Name), settled
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

// modelName is the model field as it reads: the variant chosen, or the model
// the command line named while no variant carries it.
func (m *Model) modelName() string {
	if m.model < 0 {
		return m.opt.Model
	}
	return m.opt.Models[m.model]
}

// modelLabel is a variant's name as the form shows it: each word between its
// hyphens leads with a capital, so claude-opus reads Claude-Opus. The name
// itself is what engage's --model takes and what the form passes on.
func modelLabel(name string) string {
	words := strings.Split(name, "-")
	for i, w := range words {
		if r, size := utf8.DecodeRuneInString(w); size > 0 {
			words[i] = string(unicode.ToUpper(r)) + w[size:]
		}
	}
	return strings.Join(words, "-")
}

// modelLabels is each variant's label, in order.
func modelLabels(names []string) []string {
	out := make([]string, len(names))
	for i, n := range names {
		out[i] = modelLabel(n)
	}
	return out
}

// cycleModel moves the model field to the next or previous variant. From a
// model no variant carries, → takes the first variant and ← the last.
func (m *Model) cycleModel(step int) {
	n := len(m.opt.Models)
	switch {
	case m.model < 0 && step > 0:
		m.model = 0
	case m.model < 0:
		m.model = n - 1
	default:
		m.model = (m.model + step + n) % n
	}
}

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
		l := m.lookups[msg.key]
		if l == nil {
			return m, nil
		}
		l.pending, l.refreshing, l.about, l.err = false, false, msg.about, msg.err
		m.selectNamed()
		return m, nil
	case cityMsg:
		m.cityBusy = false
		if msg.err != nil {
			m.cityErr = msg.err.Error()
			return m, nil
		}
		c := msg.city
		m.city, m.cityAt, m.cityErr = &c, m.opt.Now(), ""
		m.keepSelection()
		m.keepSeat()
		// A new topic has no conversations to choose among, so a choice a
		// lookup made before the rigs said the subject names a rig is cleared.
		if m.newTopic() {
			m.choice, m.choiceTouched, m.cursor = newChoice, false, 0
		}
		// A reference not looked up because it named a rig is looked up once
		// the rigs say it names none. While the operator is in the subject
		// field, the pause in typing or leaving the field looks it up, so a
		// reference typed halfway is not read.
		if k := m.subjectKey(); m.focus != subjectField && m.lookups[k] == nil {
			return m, m.lookup(k)
		}
		return m, nil
	case debounceMsg:
		if msg.seq == m.seq {
			return m, m.lookup(m.subjectKey())
		}
		return m, nil
	case savedMsg:
		return m, m.onSaved(msg)
	case startedMsg:
		m.starting = false
		m.startErr = ""
		if msg.err != nil {
			m.startErr = msg.err.Error()
		}
		if m.leaving {
			return m, m.quit()
		}
		if msg.err != nil {
			return m, nil
		}
		// The sitting has started. The form attaches to it, as engage does on
		// the command line, and with attaching off it leaves the sitting to
		// prepare and says how to return to it. engage's attach waits for the
		// session to start, and holds the conversation in a new sitting on the
		// model the start ran on if this one has ended by then.
		if m.attach {
			return m, m.attachTo(m.saved.Conversation, m.modelName())
		}
		return m, m.quit()
	case cityTickMsg:
		m.ticking = false
		if m.scr == returnScreen || m.scr == peopleScreen {
			return m, tea.Batch(m.loadCity(), m.refreshCity())
		}
		return m, nil
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
			// A reference the operator types was reached from nothing, so a gate
			// chosen from a subject's holds loses that subject once it is edited.
			// Whatever filled the field in, an edit makes it typed text.
			m.seq++
			seq := m.seq
			m.src, m.from = typed, ""
			m.choice, m.choiceTouched, m.cursor = newChoice, false, 0
			return tea.Batch(cmd, tea.Tick(m.opt.Debounce, func(time.Time) tea.Msg { return debounceMsg{seq: seq} }))
		}
		return cmd
	case questionField:
		return m.question.Update(msg)
	}
	return nil
}

func (m *Model) key(k tea.KeyPressMsg) tea.Cmd {
	// A form that has left takes no key: one its program reads before it ends
	// would act on a screen that is gone.
	if m.left {
		return nil
	}
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
	case peopleScreen:
		return m.peopleKey(s)
	}
	switch s {
	case "esc":
		return m.quit()
	case "ctrl+s":
		return m.submit()
	case "tab":
		if m.focus == tabsField {
			return m.focusOn(subjectField)
		}
		return m.moveFocus(1)
	case "shift+tab":
		return m.moveFocus(-1)
	}
	// ↑ and ↓ move between the fields at a field's first and last row, and
	// stop at the form's last field, where Tab wraps around. ↑ from the
	// subject reaches the tabs, where ←/→ move between the pages as they cycle
	// a chooser's values.
	switch m.focus {
	case tabsField:
		switch s {
		case "left":
			return m.movePage(-1)
		case "right":
			return m.movePage(1)
		case "down", "enter":
			return m.focusOn(subjectField)
		}
		return nil
	case subjectField:
		switch s {
		case "enter":
			return m.moveFocus(1)
		case "down":
			return m.moveFocusArrow(1)
		case "up":
			return m.focusOn(tabsField)
		}
	case questionField:
		// The question's rows are counted as the screen shows them, so ↑ and ↓
		// walk a line that wraps row by row before they leave the question.
		switch {
		case s == "up" && m.question.atFirstRow():
			return m.moveFocusArrow(-1)
		case s == "down" && m.question.atLastRow():
			return m.moveFocusArrow(1)
		}
	case modelField:
		switch s {
		case "left":
			m.cycleModel(-1)
		case "right", "space":
			m.cycleModel(1)
		case "up":
			return m.moveFocusArrow(-1)
		case "down":
			return m.moveFocusArrow(1)
		}
		return nil
	case attachField:
		switch s {
		case "left", "right", "space":
			// No sitting starts in a suspended rig, so attaching stays off
			// there, and the operator's choice stands for any other rig.
			if m.suspendedRig() == "" {
				m.attach = !m.attach
			}
		case "up":
			return m.moveFocusArrow(-1)
		case "down":
			return m.moveFocusArrow(1)
		}
		return nil
	case contextField:
		rows := m.contextRows()
		switch s {
		case "up":
			if m.cursor > 0 {
				m.cursor--
			} else {
				return m.moveFocusArrow(-1)
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
// becomes the subject, which is looked up in turn as the bead it is, whatever
// rig shares its id. A gate keeps the subject it was chosen from as where it
// was reached from, through the lookup and the save, so a gate several beads
// wait on is about that subject while it still waits on it. Nothing else
// changes: the question stays as typed.
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
		from := ""
		if l := m.resolved(); l != nil && r.kind == "hold" && r.held == "gate" {
			from = l.about.Subject.ID
		}
		m.subject.SetValue(r.id)
		m.src, m.from = given, from
		m.seq++
		m.choice, m.choiceTouched, m.cursor = newChoice, false, 0
		return m.lookup(m.subjectKey())
	}
}

// submit files the question, or starts the conversation chosen, once the
// destination is settled. Nothing is written before then.
func (m *Model) submit() tea.Cmd {
	if m.model < 0 {
		what := "Not saved"
		if m.choice != newChoice {
			what = "Not started"
		}
		m.status = fmt.Sprintf("%s: %s is not a configured model (%s). Tab to Model and choose one with ←/→.", what, m.opt.Model, strings.Join(modelLabels(m.opt.Models), ", "))
		return nil
	}
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
		if r := m.suspendedRig(); r != "" {
			// The rig can resume while the form is open, so the subject is read
			// again, and the next Ctrl+S starts the conversation once that read
			// says the rig runs.
			m.status = fmt.Sprintf("Not started: rig %s is suspended, so no sitting can start there. Start conversation %s once the rig resumes (gc rig resume %s).", r, c.ID, r)
			cmd := m.refresh()
			if m.lookups[m.subjectKey()].refreshing {
				m.status += " Reading the subject again."
			}
			return cmd
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
		r, _ := m.topicRig()
		req.Rig = r.Name
	} else {
		// The save files on the subject the screen shows, and open refuses it
		// when the reference names another subject by then. So the reference
		// goes as the operator typed it, which open resolves again: a PR whose
		// anchor moved, or a bead closed onto a successor, files nothing. A gate
		// goes as itself, so the conversation replies to the gate shown, and
		// from the subject it was chosen from, so a gate several beads wait on
		// files about the subject shown, and one that subject has stopped
		// waiting on files nothing.
		a := m.current().about
		req.Ref, req.Subject, req.From = m.ref(), a.Subject.ID, m.from
		if a.Gate != "" {
			req.Ref = a.Gate
		}
	}
	// In a suspended rig the save is all that runs: the form starts no sitting
	// there, and leaves once the question is saved.
	m.scr, m.status, m.req, m.waits = progressScreen, "", req, m.suspendedRig()
	return m.save()
}

// save runs the save request the submit made.
func (m *Model) save() tea.Cmd {
	m.saving = true
	req := m.req
	return func() tea.Msg {
		sv, err := m.helm.Save(m.ctx, req)
		return savedMsg{saved: sv, err: err}
	}
}

// saveAgain completes the conversation a save filed and did not complete. It
// sends the save again naming that conversation, and open completes it where it
// stands, whatever sitting has taken it since, or refuses: it never files a
// second one. A new topic's subject was filed with it, so the save again goes
// onto that subject and never files another.
func (m *Model) saveAgain() tea.Cmd {
	req := m.req
	req.Conversation = m.saved.Conversation
	if req.Ref == "" && m.saved.Subject != "" {
		req.Ref, req.Subject, req.Rig = m.saved.Subject, m.saved.Subject, ""
	}
	m.req = req
	return m.save()
}

// reread reads again what a refused submit was refused on, when that read can
// answer differently now: a subject lookup that failed or named a refusal,
// such as a downed controller, or the city's rigs for a rig the subject names
// or for typed text that can be a rig's name while they did not read. Nothing
// is filed, and the next Ctrl+S reads the new answer. A name several rigs
// carry reads the same way again, so it is not read.
func (m *Model) reread() tea.Cmd {
	switch {
	case m.ref() == "":
		return nil
	case m.newTopic():
		if len(m.namedRigs()) > 1 {
			return nil
		}
		return m.loadCity()
	}
	var cmds []tea.Cmd
	if m.city == nil && m.cityErr != "" {
		cmds = append(cmds, m.loadCity())
	}
	k := m.subjectKey()
	if l := m.lookups[k]; l != nil && !l.pending && (l.err != nil || l.about.Refusal != "") {
		delete(m.lookups, k)
		cmds = append(cmds, m.lookup(k))
	}
	return tea.Batch(cmds...)
}

// refresh reads the subject field's subject again while its answer stays on
// screen, so the rows on the subject, the cursor and the conversation chosen
// among them stay as they are until the new answer lands. A refresh already
// running is not run again.
func (m *Model) refresh() tea.Cmd {
	k := m.subjectKey()
	l := m.lookups[k]
	if l == nil || l.pending || l.refreshing {
		return nil
	}
	l.refreshing = true
	return func() tea.Msg {
		a, err := m.helm.About(m.ctx, k.ref, k.from)
		return aboutMsg{key: k, about: a, err: err}
	}
}

func (m *Model) onSaved(msg savedMsg) tea.Cmd {
	m.saving = false
	if msg.saved.Filed && msg.saved.Conversation != "" {
		// The conversation is filed and holds the question, so it is saved. A
		// save that failed after filing it, as when the store refused its reply
		// onto the gate, is not complete: nothing starts until r saves it again.
		sv := msg.saved
		m.saved, m.saveErr = &sv, ""
		if msg.err != nil {
			m.saveErr = msg.err.Error()
			if m.leaving {
				return m.quit()
			}
			return nil
		}
		if m.waits != "" {
			// No sitting starts in a suspended rig, so the form leaves the
			// conversation in the queue and says so.
			return m.quit()
		}
		return m.start()
	}
	if m.saved != nil {
		// A save again that did not answer leaves the question in the
		// conversation the first save filed, still not complete.
		m.saveErr = "the save again answered without naming its conversation"
		if msg.err != nil {
			m.saveErr = msg.err.Error()
		}
		if m.leaving {
			return m.quit()
		}
		return nil
	}
	m.scr = composeScreen
	why := "the save answered without filing a conversation"
	if msg.err != nil {
		why = msg.err.Error()
	}
	m.status = "Not saved: " + strings.TrimSuffix(why, ".") + ". Your question is still here."
	var cmd tea.Cmd
	switch {
	case msg.saved.Subject != "" && m.newTopic():
		// The new subject was filed and its conversation was not: the next
		// save files the question onto that subject, never a second one,
		// whatever rig shares its id.
		m.partial = msg.saved.Subject
		m.subject.SetValue(msg.saved.Subject)
		m.src = given
		m.seq++
		m.status += fmt.Sprintf(" Subject %s was filed; saving again files your question onto it.", msg.saved.Subject)
		cmd = m.lookup(lookupKey{ref: msg.saved.Subject})
	case !m.newTopic():
		// What open refused can be the subject as the form read it, such as
		// one closed onto a successor in another rig since. The subject is
		// read again, so the next Ctrl+S files where the screen then shows.
		delete(m.lookups, m.subjectKey())
		cmd = m.lookup(m.subjectKey())
	}
	if m.leaving {
		return m.quit()
	}
	return cmd
}

func (m *Model) start() tea.Cmd {
	m.starting, m.startErr = true, ""
	conv, model := m.saved.Conversation, m.modelName()
	return func() tea.Msg {
		return startedMsg{err: m.helm.Start(m.ctx, conv, model)}
	}
}

func (m *Model) progressKey(s string) tea.Cmd {
	switch s {
	case "enter":
		// A started sitting is attached to, or left, once it starts, so Enter
		// is the attach after a start that failed, which engage's attach holds
		// in a new sitting.
		if m.saved != nil && m.saveErr == "" && m.startErr != "" && !m.saving && !m.starting {
			return m.attachTo(m.saved.Conversation, m.modelName())
		}
	case "r":
		switch {
		case m.saved != nil && m.saveErr != "" && !m.saving:
			return m.saveAgain()
		case m.saved != nil && m.startErr != "" && !m.starting:
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

// retIndex is where conversation id is in rows, or -1.
func retIndex(rows []Conversation, id string) int {
	for i, c := range rows {
		if c.ID == id {
			return i
		}
	}
	return -1
}

// keepSelection holds the return list's selection on its conversation when the
// list is read again. Nothing selected yet takes the top row. A selected
// conversation that has left the list leaves nothing selected, so Enter
// attaches to nothing the operator did not pick, until ↑/↓ picks the row now in
// its place; one that comes back is selected again.
func (m *Model) keepSelection() {
	rows := m.returnRows()
	if m.retSel == "" {
		if len(rows) > 0 {
			m.retSel, m.retAt = rows[0].ID, 0
		}
		return
	}
	if i := retIndex(rows, m.retSel); i >= 0 {
		m.retAt = i
	}
}

func (m *Model) returnKey(s string) tea.Cmd {
	rows := m.returnRows()
	at := retIndex(rows, m.retSel)
	switch s {
	case "up", "down":
		if len(rows) == 0 {
			return nil
		}
		switch {
		case at < 0:
			at = min(m.retAt, len(rows)-1)
		case s == "up" && at > 0:
			at--
		case s == "down" && at < len(rows)-1:
			at++
		}
		m.retSel, m.retAt = rows[at].ID, at
	case "enter":
		if at >= 0 {
			return m.attachTo(m.retSel, "")
		}
	case "r":
		return m.loadCity()
	case "left":
		return m.movePage(-1)
	case "right":
		return m.movePage(1)
	case "esc", "q":
		return m.quit()
	}
	return nil
}

// movePage moves along the tabs to the page step away, wrapping around at
// either end, as ←/→ cycle a chooser's values. A list page reads the city again
// while it is on screen. Back on the start page the focus is on its tabs, so
// ←/→ go on moving along them and ↓ goes down to the subject. A status one page
// gave is not carried to another.
func (m *Model) movePage(step int) tea.Cmd {
	at := 0
	for i, p := range pages {
		if p == m.scr {
			at = i
		}
	}
	m.scr, m.status = pages[(at+step+len(pages))%len(pages)], ""
	if m.scr == composeScreen {
		return m.focusOn(tabsField)
	}
	return tea.Batch(m.loadCity(), m.refreshCity())
}

// The seats `conversations` lists, by the verb that opens each.
const (
	poSeat       = "po"
	mechanikSeat = "mechanik"
)

// seats are the People page's rows: the seats the city's read lists, in its
// order, mechanik first.
func (m *Model) seats() []Seat {
	if m.city == nil {
		return nil
	}
	return m.city.Seats
}

// seatKey is what the People page keeps its selection by: the seat, and a
// po's rig.
func seatKey(s Seat) string { return s.Name + " " + s.Rig }

// seatIndex is where the seat keyed key is in seats, or -1.
func seatIndex(seats []Seat, key string) int {
	for i, s := range seats {
		if seatKey(s) == key {
			return i
		}
	}
	return -1
}

// keepSeat holds the People page's selection on its seat when the city is read
// again, as keepSelection holds the return list's on its conversation.
func (m *Model) keepSeat() {
	rows := m.seats()
	if m.seatSel == "" {
		if len(rows) > 0 {
			m.seatSel, m.seatAt = seatKey(rows[0]), 0
		}
		return
	}
	if i := seatIndex(rows, m.seatSel); i >= 0 {
		m.seatAt = i
	}
}

// rigNamed is the city's rig of that name, as the read that listed the seats
// gave it.
func (m *Model) rigNamed(name string) (Rig, bool) {
	if m.city != nil {
		for _, r := range m.city.Rigs {
			if r.Name == name {
				return r, true
			}
		}
	}
	return Rig{}, false
}

// seatWhere is what Enter on s opens and what the People page says of it, and
// whether Enter opens it: mechanik, and a rig's po while its rig is not
// suspended, since Gas City starts no session in a suspended rig. Gas City's
// attach carries no message, so the line says the sitting's purpose is given in
// the sitting.
func (m *Model) seatWhere(s Seat) (string, standing) {
	const how = ", which attaches to its session, starting it first when it is not running. The attach carries no message, so give the sitting its purpose once you are in it."
	switch s.Name {
	case mechanikSeat:
		return "mechanik, the city's standing conversation: Enter runs gc-helm mechanik" + how, settled
	case poSeat:
		r, ok := m.rigNamed(s.Rig)
		switch {
		case !ok:
			return fmt.Sprintf("rig %s is not among the city's rigs, so its Product Owner cannot be checked", s.Rig), refused
		case r.Suspended:
			return fmt.Sprintf("rig %s is suspended, so its Product Owner cannot start until the rig resumes (gc rig resume %s)", r.Name, r.Name), refused
		}
		return fmt.Sprintf("the Product Owner of rig %s: Enter runs gc-helm po --rig %s", r.Name, r.Name) + how, settled
	}
	return fmt.Sprintf("%s is not a seat the form opens", s.Name), refused
}

// seatState is a People page row's state: a suspended rig for a po there, where
// no session starts, and otherwise the state of the seat's session as Gas
// City's session list gives it, with whether a terminal is attached, or no
// session when the list holds none.
func (m *Model) seatState(s Seat) string {
	if r, ok := m.rigNamed(s.Rig); s.Name == poSeat && ok && r.Suspended {
		return "rig suspended"
	}
	if s.Session == nil {
		return "no session"
	}
	st := s.Session.State
	if st == "" {
		st = "no state"
	}
	if s.Session.Attached {
		st += ", attached"
	}
	return st
}

func (m *Model) peopleKey(s string) tea.Cmd {
	rows := m.seats()
	at := seatIndex(rows, m.seatSel)
	switch s {
	case "up", "down":
		if len(rows) == 0 {
			return nil
		}
		switch {
		case at < 0:
			at = min(m.seatAt, len(rows)-1)
		case s == "up" && at > 0:
			at--
		case s == "down" && at < len(rows)-1:
			at++
		}
		m.seatSel, m.seatAt, m.status = seatKey(rows[at]), at, ""
	case "enter":
		if at >= 0 {
			return m.openPerson(rows[at])
		}
	case "r":
		return m.loadCity()
	case "left":
		return m.movePage(-1)
	case "right":
		return m.movePage(1)
	case "esc", "q":
		return m.quit()
	}
	return nil
}

// openPerson opens s once seatWhere says Enter opens it. One it does not open
// is refused, and the city is read again, so the next Enter opens a po whose
// rig has resumed since.
func (m *Model) openPerson(s Seat) tea.Cmd {
	if d, st := m.seatWhere(s); st != settled {
		m.status = "Not opened: " + d + "."
		if cmd := m.loadCity(); cmd != nil {
			m.status += " Reading the rigs again."
			return cmd
		}
		return nil
	}
	return m.openSeat(s)
}

// attachTo leaves the form so the terminal can go to conv's sitting (handOff).
// model is what a sitting held anew runs on. An attach after a start passes
// the model the start ran on, so a start that failed or a sitting that ended
// is held again on the model the screen showed. The return list shows no model
// and passes none, so engage's default holds it. The form keeps one hand-off,
// and a start that lands after it has left keeps no other.
func (m *Model) attachTo(conv, model string) tea.Cmd {
	if m.attaching {
		return nil
	}
	return m.handOff(m.helm.AttachCommand(conv, model))
}

// openSeat leaves the form so the terminal can go to s's verb (handOff), which
// attaches it to the seat's session. The form keeps one hand-off, as attachTo
// says.
func (m *Model) openSeat(s Seat) tea.Cmd {
	if m.attaching {
		return nil
	}
	return m.handOff(m.helm.SeatCommand(s.Name, s.Rig))
}

// handOff keeps cmd and quits, and cmd runs once the form's program has
// returned (Attach), so the form draws nothing after what cmd prints, such as
// its reason when it attaches nothing. A question the form has not saved is
// kept first, so leaving for cmd does not lose it.
func (m *Model) handOff(cmd *exec.Cmd) tea.Cmd {
	m.attaching = true
	m.attachCmd = cmd
	m.note = m.keepUnsaved()
	m.left = true
	return tea.Quit
}

// Attach is the command the form left to run, nil when it left without one:
// engage's attach, which waits for the sitting to start, attaches the
// terminal, and once the terminal comes back says how the sitting ended, or a
// seat's verb, which attaches the terminal to the seat's session. It runs once
// the form's program has returned and the note is printed, on the terminal the
// program let go, so all it prints, a refusal included, comes after the last
// screen the form drew.
func (m *Model) Attach() *exec.Cmd { return m.attachCmd }

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
	if m.saved != nil {
		m.note = m.savedNote()
	} else {
		m.note = m.keepUnsaved()
	}
	m.left = true
	return tea.Quit
}

// keepUnsaved keeps a question the form has not saved in a file, and returns
// what the note says of it: empty when there is none. A question already kept
// is not kept again.
func (m *Model) keepUnsaved() string {
	q := m.question.Value()
	if m.saved != nil || strings.TrimSpace(q) == "" {
		return ""
	}
	if m.kept == "" || m.keptQ != q {
		filed := "Nothing was filed."
		if m.partial != "" {
			filed = fmt.Sprintf("Subject %s was filed, and its conversation was not.", m.partial)
		}
		m.kept, m.keptQ = m.keepDraft(filed), q
	}
	return m.kept
}

// leaveNow leaves at once while a save or a start runs: on a second Ctrl+C, or
// once something else has ended the program (Leave). What that run did is
// unknown, so the note says so and keeps the question.
func (m *Model) leaveNow() tea.Cmd {
	if m.saved != nil {
		m.note = m.savedNote()
	} else {
		m.note = m.keepDraft("The form closed while your question was being saved, so whether it was filed is unknown: gc-helm.sh conversations lists the open conversations.")
	}
	m.left = true
	return tea.Quit
}

// Leave is what the form says once its program has returned, whatever ended
// it. A form that left by its own path made its note as it left, and that note
// stands. Something else can end the program first: bubbletea turns an
// interrupt or a termination into a message of its own that never reaches
// Update, and it stops when its input or the terminal fails. A form ended that
// way leaves here as leaveNow does while a save or a start runs, and as quit
// does otherwise, so a question it did not save is kept in a file. Call it once
// Run has returned, so no Update runs beside it.
func (m *Model) Leave() string {
	if !m.left {
		if m.saving || m.starting {
			m.leaveNow()
		} else {
			m.quit()
		}
	}
	return m.note
}

func (m *Model) savedNote() string {
	s := m.saved
	what := "is saved"
	switch {
	case m.existing:
		what = "was chosen"
	case m.saving || m.saveErr != "":
		what = "holds your question"
	}
	state := "its sitting is starting"
	switch {
	case m.saving:
		state = "the form closed while it was being saved again, so whether that save completed is unknown, and no sitting was started"
	case m.saveErr != "":
		state = "its save did not complete (" + strings.TrimSuffix(m.saveErr, ".") + "), so no sitting was started; it waits in your queue"
	case m.waits != "":
		state = fmt.Sprintf("no sitting was started: rig %s is suspended, so it waits in your queue until the rig resumes (gc rig resume %s)", m.waits, m.waits)
	case m.starting:
		state = "the form closed while its sitting was being started, so whether it started is unknown"
	case m.startErr != "":
		state = "no sitting started (" + m.startErr + "); it waits in your queue"
	}
	ret := "Return to it with"
	if m.waits != "" {
		ret = "Once the rig resumes, return to it with"
	}
	return fmt.Sprintf("Conversation %s on %s %s, and %s. %s: gc-helm.sh attach %s", s.Conversation, s.Subject, what, state, ret, s.Conversation)
}

// keepDraft writes the question, unchanged, to a file in the draft directory,
// and says, after what filed says was filed, where the question is and the
// command that files it again on the subject or rig the form was filing it on.
// The command passes the file whole. A command substitution drops the trailing
// newlines a question typed with Enter often ends in, and open lands a save
// again on the conversation an earlier save filed only when the ask matches
// exactly. So it reads the file with a mark after it, strips the mark, and runs
// nothing when the file does not read.
func (m *Model) keepDraft(filed string) string {
	q := m.question.Value()
	path, err := m.writeDraft(q)
	if err != nil {
		return filed + " The question could not be kept in a file. Here it is:\n\n" + q
	}
	again := "gc-helm.sh engage --new-subject --rig <rig>"
	switch {
	case m.newTopic():
		if r, ok := m.topicRig(); ok {
			again = "gc-helm.sh engage --new-subject --rig " + shellQuote(r.Name)
		}
	case m.ref() != "":
		again = "gc-helm.sh engage " + shellQuote(m.ref())
		if m.from != "" {
			again += " --from " + shellQuote(m.from)
		}
	}
	return fmt.Sprintf("%s Your question is kept in %s; start it again with: q=$(cat %s && echo .) && %s --reason \"${q%%.}\"", filed, path, shellQuote(path), again)
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
	case peopleScreen:
		s = m.peopleView()
	default:
		s = m.composeView()
	}
	v := tea.NewView(s)
	v.AltScreen = true
	return v
}

// lines is how many screen lines s fills, each ended by a newline.
func lines(s string) int { return strings.Count(s, "\n") }

// wrap breaks each line of s that is wider than the terminal, so the screen
// shows it whole: bubbletea v2 draws the view into a frame the terminal's size
// without wrapping it, and drops what a line holds past the frame's edge.
func (m *Model) wrap(s string) string { return wrapAtSpaces(s, m.width) }

// wrapBeside is text beside prefix, wrapped to the terminal's width with each
// line after the first indented under the text, as the destination stands
// beside "Files as". On a terminal too narrow to give the text as much room as
// prefix takes, or before its size is known, it is prefix and text on one line,
// which the view wraps as it wraps any other.
func (m *Model) wrapBeside(prefix, text string) string {
	w := lipgloss.Width(prefix)
	if m.width-w < w {
		return prefix + text
	}
	return prefix + strings.ReplaceAll(wrapAtSpaces(text, m.width-w), "\n", "\n"+strings.Repeat(" ", w))
}

// wrapAtSpaces breaks each line of s that is wider than width display cells
// into lines no wider than width. It breaks only at spaces: lipgloss.Wrap
// breaks at every hyphen too, ansi.Wrap's fixed breakpoint, which would split
// a bead id such as tk-a1b2 or a rig such as gc-toolkit across two lines. A
// line that fits is left as it is, and so is all of s while width is below 1,
// as it is until the terminal's size is known.
func wrapAtSpaces(s string, width int) string {
	if width < 1 {
		return s
	}
	ls := strings.Split(s, "\n")
	for i, l := range ls {
		if lipgloss.Width(l) > width {
			ls[i] = breakAtSpaces(l, width)
		}
	}
	return strings.Join(ls, "\n")
}

// breakAtSpaces is wrapAtSpaces for one line wider than width. The spaces the
// line starts with stay on its first line, and each line after a break starts
// at its word. A space with no room left on its line is dropped, though not a
// style written beside it, and a style runs on across each break
// (lipgloss.NewWrapWriter). A word wider than width is cut into lines no wider
// than width, at a hyphen where it has one (lipgloss.Wrap).
func breakAtSpaces(line string, width int) string {
	var out []string
	cur, curW := "", 0
	filled := false // the line holds a word, not only spaces
	for i, word := range strings.Split(line, " ") {
		w := lipgloss.Width(word)
		gap := 1
		if i == 0 {
			gap = 0
		}
		switch {
		case curW+gap+w <= width || !filled && w > 0:
			cur += strings.Repeat(" ", gap) + word
			curW += gap + w
		case w == 0:
			cur += word
		default:
			out = append(out, cur)
			cur, curW = word, w
		}
		filled = filled || w > 0
		if curW > width {
			cut := strings.Split(lipgloss.Wrap(cur, width, ""), "\n")
			out, cur = append(out, cut[:len(cut)-1]...), cut[len(cut)-1]
			curW = lipgloss.Width(cur)
		}
	}
	var b strings.Builder
	sw := lipgloss.NewWrapWriter(&b)
	_, _ = io.WriteString(sw, strings.Join(append(out, cur), "\n"))
	_ = sw.Close()
	return b.String()
}

// listLines fits the rows of a list into room screen lines around row sel. The
// screen holds a frame the terminal's size and clips the lines below it, so a
// list taller than room shows the page of rows sel is on, paged as bubbles'
// list component pages (list.Select), and a last line counts the rows above
// and below the page. The selected row is always on screen, and so is what the
// list leaves out. A room of 0 is a terminal whose size is not known yet, which
// shows every row.
func listLines(rows []string, sel, room int) []string {
	n := len(rows)
	if room <= 0 || n <= room {
		return rows
	}
	per := max(room-1, 1)
	sel = min(max(sel, 0), n-1)
	start := sel / per * per
	end := min(start+per, n)
	out := append([]string(nil), rows[start:end]...)
	if room > 1 {
		var more []string
		if start > 0 {
			more = append(more, fmt.Sprintf("↑ %d more above", start))
		}
		if end < n {
			more = append(more, fmt.Sprintf("↓ %d more below", n-end))
		}
		out = append(out, hintStyle.Render("  "+strings.Join(more, ", ")))
	}
	return out
}

// room is how many lines a list has on screen between above and below, at least
// one. It is 0 until the terminal's size is known.
func (m *Model) room(above, below string) int {
	if m.height <= 0 {
		return 0
	}
	return max(m.height-lines(above)-lines(below), 1)
}

func (m *Model) label(f field, text string) string {
	if m.focus == f {
		return focusStyle.Render(text)
	}
	return labelStyle.Render(text)
}

// tabs is the row of tabs that names the form's pages, the page on screen
// marked: reversed while ←/→ move along the row, as they do anywhere on a list
// page and from the start page's tabs, and in bold while the focus is in one
// of the start page's fields.
func (m *Model) tabs() string {
	parts := make([]string, len(pages))
	for i, p := range pages {
		name := " " + pageNames[p] + " "
		switch {
		case p != m.scr:
			parts[i] = hintStyle.Render(name)
		case p != composeScreen || m.focus == tabsField:
			parts[i] = focusStyle.Render(name)
		default:
			parts[i] = labelStyle.Render(name)
		}
	}
	return strings.Join(parts, hintStyle.Render("│"))
}

// standingMark is the mark beside a destination: settled, still being read, or
// refused.
func standingMark(st standing) string {
	switch st {
	case settled:
		return okStyle.Render("✓")
	case refused:
		return badStyle.Render("✗")
	}
	return waitStyle.Render("…")
}

// questionLines is how many lines of the question the form shows, and
// minQuestionLines the fewest it shows on a terminal too short for the fields
// and the row in play beside them.
const (
	questionLines    = 8
	minQuestionLines = 3
)

func (m *Model) composeView() string {
	// The question's lines are the one part of the screen that gives way, so
	// the view is put together once the rest of it is known: the fields above
	// and below the question, and under them the row in play and the lines
	// below the list.
	var head, b strings.Builder
	suspended := m.suspendedRig()
	act := "Ctrl+S save, start and attach"
	switch {
	case suspended != "":
		act = "Ctrl+S save and leave"
	case !m.attach:
		act = "Ctrl+S save, start and leave"
	}
	keys := " · Tab next field · ↑ to the tabs · Esc cancel"
	if m.focus == tabsField {
		keys = " · ←/→ another page · ↓ back to the subject · Esc cancel"
	}
	head.WriteString(m.tabs() + "\n" + hintStyle.Render(act+keys) + "\n\n")
	head.WriteString(m.label(subjectField, "Subject ") + "  " + m.subject.View() + "\n")
	if m.from != "" {
		// The field pads its line to its width, so a note beside it would run
		// off the screen.
		head.WriteString(hintStyle.Render("          chosen from what holds "+m.from) + "\n")
	}
	head.WriteString(m.label(questionField, "Question") + hintStyle.Render("  Enter adds a line") + "\n")
	b.WriteString("\n")
	// The rig is shown, not chosen here: the subject names it.
	if r, ok := m.topicRig(); ok {
		b.WriteString(labelStyle.Render("Rig     ") + "  " + r.Name + hintStyle.Render("   a new topic in this rig") + "\n")
	} else if l := m.current(); l != nil && l.err == nil && l.about.Subject.Rig != "" {
		b.WriteString(labelStyle.Render("Rig     ") + "  " + l.about.Subject.Rig + hintStyle.Render("   the subject's own") + "\n")
	}
	// A model no variant carries is shown as the command line named it.
	model := m.modelName()
	switch {
	case m.model < 0:
		model = badStyle.Render(model) + hintStyle.Render(" (not a configured model: ←/→ chooses one)")
	case m.model == 0:
		model = modelLabel(model) + hintStyle.Render(" (default)")
	default:
		model = modelLabel(model)
	}
	b.WriteString(m.label(modelField, "Model   ") + "  ‹ " + model + " ›\n")
	attach := "‹ yes, once its sitting starts" + hintStyle.Render(" (default)") + " ›"
	switch {
	case suspended != "":
		// Shown without ‹ ›, since no key turns it on there.
		attach = "no — rig " + suspended + " is suspended, so no sitting starts until it resumes"
	case !m.attach:
		attach = "‹ no, leave once its sitting starts ›"
	}
	b.WriteString(m.label(attachField, "Attach  ") + "  " + attach + "\n\n")
	dest, st := m.where()
	b.WriteString(m.wrapBeside(labelStyle.Render("Files as")+"  "+standingMark(st)+" ", dest) + "\n")
	// The rows on this subject are paged to the lines left below the fields, so
	// the row in play is on screen: the cursor's while the list has focus, and
	// otherwise the row chosen, which is what Ctrl+S acts on.
	var list []string
	sel := 0
	rows := m.contextRows()
	if len(rows) > 0 {
		b.WriteString("\n" + m.label(contextField, "On this subject") + hintStyle.Render("  Tab here, ↑/↓, Space chooses") + "\n")
		for i, r := range rows {
			cur := "  "
			if m.focus == contextField && i == m.cursor {
				cur = "› "
			}
			dot := "○ "
			if (r.kind == "new" || r.kind == "conversation") && r.id == m.choice {
				dot = "● "
				if m.focus != contextField {
					sel = i
				}
			}
			if r.kind == "hold" || r.kind == "candidate" {
				dot = "→ "
			}
			list = append(list, cur+dot+r.label)
		}
		if m.focus == contextField {
			sel = m.cursor
		}
	}
	// The lines below the rows are counted in the room the rows page into, so
	// they stay on screen with the row in play.
	var after strings.Builder
	for _, line := range m.heldLines() {
		after.WriteString(line + "\n")
	}
	if l := m.resolved(); l != nil && !l.about.HoldsRead {
		// Without this line, a subject whose holds did not read looks like one
		// that nothing holds.
		after.WriteString(waitStyle.Render("What holds the subject did not read, so nothing that holds it is listed.") + "\n")
	}
	if l := m.current(); l != nil && l.err == nil && l.about.Closed != nil {
		after.WriteString(hintStyle.Render(l.about.Closed.Said) + "\n")
	}
	if m.status != "" {
		after.WriteString("\n" + badStyle.Render(m.status) + "\n")
	}
	// The lines around the question and the rows are wrapped to the terminal
	// before they are counted, so the question and the rows give way to the
	// lines the screen shows. A row stays one line, since the rows are paged by
	// the line, so a row wider than the terminal is cut at its edge. Two lines
	// of the list hold the row in play and, when there are more, the line that
	// counts the rest.
	top, below, under := m.wrap(head.String()), m.wrap(b.String()), m.wrap(after.String())
	m.fitQuestion(lines(top) + lines(below) + min(len(list), 2) + lines(under))
	b.Reset()
	b.WriteString(top + m.question.View() + "\n" + below)
	for _, line := range listLines(list, sel, m.room(b.String(), under)) {
		b.WriteString(line + "\n")
	}
	b.WriteString(under)
	return b.String()
}

// fitQuestion shows as many of the question's lines as the terminal has room
// for beside the compose screen's other lines, which number others, from
// minQuestionLines up to questionLines. So a short terminal still shows the
// fields, the row in play, which Ctrl+S acts on, what the list leaves out, and
// the status under the list. Until the terminal's size is known, the question
// shows questionLines.
func (m *Model) fitQuestion(others int) {
	h := questionLines
	if m.height > 0 {
		h = min(max(m.height-others, minQuestionLines), questionLines)
	}
	if m.question.Height() != h {
		m.question.SetHeight(h)
	}
}

func (m *Model) progressView() string {
	var b strings.Builder
	b.WriteString(labelStyle.Render("Start a conversation") + "\n\n")
	switch {
	case m.saving && m.saved != nil:
		b.WriteString(waitStyle.Render("…") + fmt.Sprintf(" saving again: conversation %s on %s holds your question\n", m.saved.Conversation, m.saved.Subject))
	case m.saving:
		b.WriteString(waitStyle.Render("…") + " saving your question\n")
	case m.saved != nil && m.existing:
		b.WriteString(okStyle.Render("✓") + fmt.Sprintf(" conversation %s on %s, chosen\n", m.saved.Conversation, m.saved.Subject))
	case m.saved != nil:
		b.WriteString(okStyle.Render("✓") + fmt.Sprintf(" saved: conversation %s on %s holds your question\n", m.saved.Conversation, m.saved.Subject))
	}
	if m.saveErr != "" && !m.saving {
		b.WriteString(badStyle.Render("✗") + " the save did not complete, so no sitting was started: " + m.saveErr + "\n")
		// The save again can be refused for good, once the conversation is
		// closed or holds another ask, so the hint promises only what r does
		// either way.
		b.WriteString(hintStyle.Render("  r saves it again onto conversation "+m.saved.Conversation+", which completes it or says why it cannot, and files no other.") + "\n")
	}
	switch {
	case m.starting:
		b.WriteString(waitStyle.Render("…") + fmt.Sprintf(" starting its sitting on %s\n", modelLabel(m.modelName())))
	case m.startErr != "":
		b.WriteString(badStyle.Render("✗") + " no sitting started: " + m.startErr + "\n")
		b.WriteString(hintStyle.Render("  The conversation waits in your queue. r retries the start.") + "\n")
	}
	switch {
	case m.leaving:
		b.WriteString("\n" + waitStyle.Render("Leaving once this lands, so it is not cut off midway. Ctrl+C again leaves now.") + "\n")
	case m.saved != nil && !m.saving && m.saveErr != "":
		b.WriteString("\n" + hintStyle.Render("q leaves it in your queue, not started") + "\n")
	case m.saved != nil && !m.starting && m.startErr != "":
		b.WriteString("\n" + hintStyle.Render("Enter attaches, holding it in a new sitting · q leaves it in your queue") + "\n")
	case m.waits != "":
		b.WriteString("\n" + hintStyle.Render("Leaves once it is saved: no sitting starts while rig "+m.waits+" is suspended") + "\n")
	case m.attach:
		b.WriteString("\n" + hintStyle.Render("Attaches once its sitting starts · q leaves it to start without you") + "\n")
	default:
		b.WriteString("\n" + hintStyle.Render("Leaves once its sitting starts; return with gc-helm.sh attach") + "\n")
	}
	return m.wrap(b.String())
}

func (m *Model) returnView() string {
	var b strings.Builder
	b.WriteString(m.tabs() + "\n")
	b.WriteString(hintStyle.Render("↑/↓ choose · Enter attaches · r refreshes · ←/→ another page · Esc leaves") + "\n\n")
	if m.city == nil {
		if m.cityErr != "" {
			b.WriteString(badStyle.Render("The conversations did not read: "+m.cityErr) + "\n")
		} else {
			b.WriteString(waitStyle.Render("…") + " reading the open conversations\n")
		}
		return m.wrap(b.String())
	}
	if m.cityErr != "" {
		// A read again that failed keeps the rows the last read gave, so the
		// screen says so, and when that read was.
		b.WriteString(badStyle.Render(fmt.Sprintf("Not refreshed since %s, so the list may be out of date: %s", m.cityAt.Format("15:04:05"), m.cityErr)) + "\n\n")
	}
	rows := m.returnRows()
	if len(rows) == 0 {
		b.WriteString("No open conversation.\n")
	}
	at := retIndex(rows, m.retSel)
	var list []string
	for i, c := range rows {
		cur := "  "
		if i == at {
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
		list = append(list, fmt.Sprintf("%s%-22s %s  %s  %s", cur, mark, c.ID, hintStyle.Render(c.Rig), topic))
	}
	var after strings.Builder
	if at < 0 && m.retSel != "" && len(rows) > 0 {
		after.WriteString("\n" + waitStyle.Render(m.retSel+" is no longer listed, so nothing is selected: ↑/↓ chooses another.") + "\n")
	}
	if len(m.city.Unread) > 0 {
		after.WriteString("\n" + badStyle.Render("Not listed: the store of "+strings.Join(m.city.Unread, ", ")+" could not be read.") + "\n")
	}
	// The list is paged to the terminal, around the selection, or around where
	// it was while nothing is selected, so ↑/↓ moves through rows on screen and
	// Enter attaches to the row the operator sees marked. The lines above and
	// below the rows are wrapped before they are counted, and a row stays one
	// line, as on the compose screen.
	sel := at
	if sel < 0 {
		sel = m.retAt
	}
	top, under := m.wrap(b.String()), m.wrap(after.String())
	b.Reset()
	b.WriteString(top)
	for _, line := range listLines(list, sel, m.room(top, under)) {
		b.WriteString(line + "\n")
	}
	b.WriteString(under)
	return b.String()
}

// peopleView is the People page: the seats the operator sits with, mechanik
// and each rig's po by its rig's name and prefix, each with its state
// (seatState), and above them what Enter opens for the seat picked. It is
// paged to the terminal around the pick, as the return list is.
func (m *Model) peopleView() string {
	var b strings.Builder
	b.WriteString(m.tabs() + "\n")
	b.WriteString(hintStyle.Render("↑/↓ choose · Enter opens · r refreshes · ←/→ another page · Esc leaves") + "\n\n")
	if m.city == nil {
		if m.cityErr != "" {
			b.WriteString(badStyle.Render("The seats did not read: "+m.cityErr) + "\n")
		} else {
			b.WriteString(waitStyle.Render("…") + " reading the seats\n")
		}
		return m.wrap(b.String())
	}
	if m.cityErr != "" {
		// A read again that failed keeps the rows the last read gave, as on the
		// return list.
		b.WriteString(badStyle.Render(fmt.Sprintf("Not refreshed since %s, so the list may be out of date: %s", m.cityAt.Format("15:04:05"), m.cityErr)) + "\n\n")
	}
	rows := m.seats()
	switch {
	case m.city.RosterUnread:
		// The roster names each seat's session, so a read without it lists no
		// seat.
		b.WriteString(badStyle.Render("The seats did not read: the city's agent roster (gc agent list), which names each seat's session, could not be read.") + "\n")
	case len(rows) == 0:
		b.WriteString("No seat is listed.\n")
	}
	at := seatIndex(rows, m.seatSel)
	if at >= 0 {
		d, st := m.seatWhere(rows[at])
		b.WriteString(m.wrapBeside(labelStyle.Render("Opens")+"  "+standingMark(st)+" ", d) + "\n\n")
	}
	rigW := 0
	for _, s := range rows {
		rigW = max(rigW, lipgloss.Width(s.Rig))
	}
	var list []string
	for i, s := range rows {
		cur := "  "
		if i == at {
			cur = "› "
		}
		who := s.Name
		if s.Name == poSeat {
			r, _ := m.rigNamed(s.Rig)
			who = "Product Owner  " + s.Rig + strings.Repeat(" ", rigW-lipgloss.Width(s.Rig)) + hintStyle.Render("  "+r.Prefix)
		}
		list = append(list, fmt.Sprintf("%s%-22s %s", cur, m.seatState(s), who))
	}
	var after strings.Builder
	if at < 0 && m.seatSel != "" && len(rows) > 0 {
		after.WriteString("\n" + waitStyle.Render("The seat picked is no longer listed, so nothing is selected: ↑/↓ chooses another.") + "\n")
	}
	if m.status != "" {
		after.WriteString("\n" + badStyle.Render(m.status) + "\n")
	}
	sel := at
	if sel < 0 {
		sel = m.seatAt
	}
	top, under := m.wrap(b.String()), m.wrap(after.String())
	b.Reset()
	b.WriteString(top)
	for _, line := range listLines(list, sel, m.room(top, under)) {
		b.WriteString(line + "\n")
	}
	b.WriteString(under)
	return b.String()
}
