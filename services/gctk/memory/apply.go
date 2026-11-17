package memory

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// The verbs of a decision.
const (
	Waits = "waits"
	Next  = "next"
	Drop  = "drop"
	// AskUse follows a next decision on a whole note to ask its users to record
	// the days they use it.
	AskUse = "ask-use"
)

// decisionForm is what a decision line holds, for a message that refuses one.
const decisionForm = "<ref> waits <bead> | <ref> next <YYYY-MM-DD after today> [ask-use] | <ref> drop"

// refLine reads a decision: a ref runs to the @ and the sixteen hex digits that
// end it, since a note's name can hold spaces, and the words after it decide.
var refLine = regexp.MustCompile(`^\s*([0-9a-f]{16})/(.+)@([0-9a-f]{16})(?:\s+(.*))?$`)

type decision struct {
	line, ref, key16, name, full16 string
	verb, arg                      string
	askUse                         bool
}

// parseDecision reads one line, and reports whether it is a decision.
func parseDecision(line, today string) (decision, bool) {
	m := refLine.FindStringSubmatch(line)
	if m == nil || strings.Contains(m[2], "/") {
		return decision{}, false
	}
	d := decision{line: line, ref: m[1] + "/" + m[2] + "@" + m[3], key16: m[1], name: m[2], full16: m[3]}
	words := strings.Fields(m[4])
	if len(words) == 0 {
		return decision{}, false
	}
	d.verb = words[0]
	switch {
	case d.verb == Drop && len(words) == 1:
	case d.verb == Waits && len(words) == 2:
		d.arg = words[1]
	case d.verb == Next && (len(words) == 2 || (len(words) == 3 && words[2] == AskUse)):
		day, err := time.Parse(time.DateOnly, words[1])
		if err != nil || day.Format(time.DateOnly) != words[1] || words[1] <= today {
			return decision{}, false
		}
		d.arg, d.askUse = words[1], len(words) == 3
	default:
		return decision{}, false
	}
	return d, true
}

// Applied is what an apply said of each decision, and what it could not do.
type Applied struct {
	Said   []string
	Failed []string
}

// Apply records the judge's decisions, one a line: a unit waits on a bead, is
// due again on a day, with ask-use asking a note's users to record the days
// they use it, or is dropped. A drop keeps the unit's text and removes it, then
// takes the pointers to a removed note out of the index and the collection
// notes while its name holds no file, those of an earlier run's removals that
// did not come out with them. A decision acts only on the text the ref names,
// and one whose unit changed since it was listed is refused and stays due. An
// error is a city whose places did not read.
func (in *Intake) Apply(decisions string) (Applied, error) {
	var a Applied
	today := in.today()
	var ds []decision
	for _, line := range lines(decisions) {
		if t := strings.TrimSpace(line); t == "" || strings.HasPrefix(t, "#") {
			continue
		}
		d, ok := parseDecision(line, today)
		if !ok {
			a.Failed = append(a.Failed, fmt.Sprintf("not a decision (%s): %s", decisionForm, line))
			continue
		}
		ds = append(ds, d)
	}
	if len(ds) == 0 {
		return a, nil
	}
	ps, err := in.Places()
	if err != nil {
		return a, err
	}
	var waits []string
	for _, d := range ds {
		if d.verb == Waits {
			waits = append(waits, d.arg)
		}
	}
	unheld := in.unheld(ps, waits)
	byPlace := map[string][]decision{}
	for _, d := range ds {
		p, ok := ps.byKey(d.key16)
		switch {
		case !ok:
			a.Failed = append(a.Failed, d.ref+": no memory directory the run reads now has that key")
		case d.verb == Waits && unheld[d.arg] != "":
			a.Failed = append(a.Failed, d.ref+": "+unheld[d.arg])
		default:
			byPlace[p.Key] = append(byPlace[p.Key], d)
		}
	}
	for _, p := range ps.Read {
		if len(byPlace[p.Key]) > 0 {
			in.applyIn(ps, p, byPlace[p.Key], &a)
		}
	}
	return a, nil
}

// unheld is why a note cannot wait on each id its store does not hold, from
// one read of each store.
func (in *Intake) unheld(ps Places, ids []string) map[string]string {
	why := map[string]string{}
	byStore := map[string][]string{}
	for _, id := range ids {
		rig, ok := ps.rigOf(id)
		if !ok {
			why[id] = "no store of the city carries " + id
			continue
		}
		db := filepath.Join(rig.Path, ".beads")
		byStore[db] = append(byStore[db], id)
	}
	for db, ids := range byStore {
		recs, err := in.find(db, ids)
		for _, id := range ids {
			switch _, ok := recs[id]; {
			case err != nil:
				why[id] = fmt.Sprintf("the store at %s did not answer, so nothing is recorded to wait on %s: %v", db, id, err)
			case !ok:
				why[id] = id + " is not in its store"
			}
		}
	}
	return why
}

// find reads the beads named from the store at db, closed ones among them.
func (in *Intake) find(db string, ids []string) (map[string]*ledger.Record, error) {
	l, err := in.Store(db)
	if err != nil {
		return nil, err
	}
	recs, err := l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	out := make(map[string]*ledger.Record, len(recs))
	for _, r := range recs {
		out[r.ID] = r
	}
	return out, nil
}

func (in *Intake) applyIn(ps Places, p Place, ds []decision, a *Applied) {
	state := ps.state(p)
	release, err := in.lock(state, p.Dir)
	if err != nil {
		a.Failed = append(a.Failed, err.Error())
		return
	}
	defer release()
	units, err := scan(p.Dir)
	if err != nil {
		a.Failed = append(a.Failed, err.Error()+"; nothing there is recorded")
		return
	}
	rows, err := readList(state)
	if err != nil {
		a.Failed = append(a.Failed, err.Error())
		return
	}
	gone, err := readGone(state)
	if err != nil {
		a.Failed = append(a.Failed, err.Error())
		return
	}
	now := in.now().Format(time.RFC3339)
	for _, d := range ds {
		u, ok := unitFor(units, d)
		if !ok {
			a.Said = append(a.Said, "refused "+d.ref+": it changed since it was listed, or is gone; it stays, and is due while it is there")
			continue
		}
		if d.verb == Drop {
			if in.drop(state, p.Dir, u, d, gone, a) {
				rows = without(rows, u.key())
			}
			continue
		}
		if d.askUse && u.Kind != Note {
			a.Failed = append(a.Failed, d.ref+": ask-use takes a whole note")
			continue
		}
		hash, withdrawn, ok := in.asking(p.Dir, u, d, a)
		if !ok {
			continue
		}
		rows = without(rows, u.key())
		if d.verb == Waits {
			rows = append(rows, row{Kind: u.Kind, Name: u.Name, Hash: hash, Judged: now, Wait: d.arg})
			a.Said = append(a.Said, "recorded "+d.ref+": waits on "+d.arg+withdrawn)
			continue
		}
		rows = append(rows, row{Kind: u.Kind, Name: u.Name, Hash: hash, Judged: now, Next: d.arg})
		asked := ""
		if d.askUse {
			asked = ", with a request to record the days it is used, one line a day"
		}
		a.Said = append(a.Said, "recorded "+d.ref+": due again on "+d.arg+asked+withdrawn)
	}
	a.Failed = append(a.Failed, unlink(state, p.Dir, gone)...)
	rows = withoutFiles(rows, gone)
	if err := writeList(state, rows); err != nil {
		a.Failed = append(a.Failed, err.Error())
	}
}

// unitFor is the unit a decision's ref names: its file, at the text listed.
func unitFor(units []Unit, d decision) (Unit, bool) {
	for _, u := range units {
		if u.Name == d.name && strings.HasPrefix(u.Full, d.full16) {
			return u, true
		}
	}
	return Unit{}, false
}

// drop removes u, its text kept, and reports whether it went.
func (in *Intake) drop(state, dir string, u Unit, d decision, gone map[string]bool, a *Applied) bool {
	if u.Kind == Note {
		r, kept, err := removeNote(state, dir, u.Name, u.Full)
		switch r {
		case removed:
			gone[u.Name] = true
			a.Said = append(a.Said, "removed "+d.ref+", its text kept at "+kept)
			return true
		case stays:
			a.Said = append(a.Said, "refused "+d.ref+": it changed since it was listed; it stays and is due")
		default:
			a.Failed = append(a.Failed, fmt.Sprintf("could not remove %s, so it stays: %v", d.ref, err))
		}
		return false
	}
	r, kept, hubGone, err := removeEntry(state, dir, u)
	switch r {
	case removed:
		a.Said = append(a.Said, "removed "+d.ref+", its text kept at "+kept)
		if hubGone {
			gone[u.Name] = true
			a.Said = append(a.Said, "removed "+u.Name+", which has no entries left")
		}
		if err != nil {
			a.Failed = append(a.Failed, err.Error())
		}
		return true
	case stays:
		a.Said = append(a.Said, "refused "+d.ref+": its collection note kept changing or no longer holds it; it stays")
	default:
		a.Failed = append(a.Failed, fmt.Sprintf("could not remove %s, so it stays: %v", d.ref, err))
	}
	return false
}

// asking holds a whole note to the judge's decision on its request for uses:
// ask-use adds the line that asks, and a decision without it takes that line
// out, the note's use lines kept. It returns the hash the list keeps, what the
// recorded line adds when the request went, and whether the decision stands.
func (in *Intake) asking(dir string, u Unit, d decision, a *Applied) (string, string, bool) {
	if u.Kind != Note {
		return u.Hash, "", true
	}
	file := filepath.Join(dir, u.Name)
	raw, err := os.ReadFile(file)
	if err != nil || sum(string(raw)) != u.Full {
		a.Said = append(a.Said, "refused "+d.ref+": it changed since it was listed; it stays and is due")
		return "", "", false
	}
	var edit func(string) (string, error)
	withdrawn := ""
	switch has := asksUse(string(raw)); {
	case d.askUse && !has:
		edit = withUse(u.Full)
	case !d.askUse && has:
		edit, withdrawn = withoutUse(u.Full), "; its request to record the days it is used taken out"
	default:
		return u.Hash, "", true
	}
	written, wrote, err := rewrite(file, edit)
	switch {
	case err == nil && wrote:
		return bodyHash(written), withdrawn, true
	case err == nil || errors.Is(err, errChanged) || errors.Is(err, errMoved) || errors.Is(err, os.ErrNotExist):
		a.Said = append(a.Said, "refused "+d.ref+": it changed since it was listed; it stays and is due")
	default:
		a.Failed = append(a.Failed, fmt.Sprintf("could not record %s: %v", d.ref, err))
	}
	return "", "", false
}

// without is rows without the row whose identity is key.
func without(rows []row, key string) []row {
	out := rows[:0:0]
	for _, r := range rows {
		if r.key() != key {
			out = append(out, r)
		}
	}
	return out
}

// withoutFiles is rows without the rows of each file in gone.
func withoutFiles(rows []row, gone map[string]bool) []row {
	out := rows[:0:0]
	for _, r := range rows {
		if !gone[r.Name] {
			out = append(out, r)
		}
	}
	return out
}
