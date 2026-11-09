// Package waits answers what holds a bead, from one snapshot of the store
// (docs/gctk-architecture.md, "The bead holds contract"). The answer is the
// store's: waits reads the store's blocked set with the blockers it names on
// each bead and the close times of the waits that have landed, and computes no
// wait itself. It never walks the dependency graph and never judges a gate, so a
// change in the store's rule reaches every caller at once.
//
// What it adds over the store's answer is the rule that applies by where the
// work is. Work that has not started is held while the store keeps it out of bd
// ready for a wait, its own or a parent-child ancestor's. Work in flight is held
// only by its own waits, the ones bd refuses its close for, because a wait gates
// claims, not running work. Whether a bead is in flight is steering.md's test
// (In flight), held here in one definition as adopted debt: a bead's execution
// state lives at once in its status, its metadata stamps and the position of a
// workflow poured for it, and the test goes once that state has one home.
//
// The package sits outside internal/ so the helm board, a separate module, can
// import it.
package waits

import (
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// Status is what holds a bead, in one word.
type Status string

const (
	// Blocked is a bead a wait of its own holds.
	Blocked Status = "blocked"
	// Held is a bead whose work has not started, which only an ancestor's wait
	// holds.
	Held Status = "held"
	// Unjudged is a bead with a waits-for edge of its own. The bd the city runs
	// judges such an edge by its spawner's status rather than by its gate, so the
	// store cannot say whether it holds, and the answer stands until bd judges
	// the gate. A caller that acts holds such a bead.
	Unjudged Status = "unjudged"
	// Clear is a bead nothing holds.
	Clear Status = "clear"
)

// Wait is one wait: the bead waited on, the type of the edge onto it, and that
// bead's title and status. Ancestor names the ancestor whose wait it is, and is
// empty for a wait of the bead's own. A waits-for wait is unjudged.
type Wait struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Title    string `json:"title"`
	Status   string `json:"status"`
	Ancestor string `json:"ancestor,omitempty"`
}

// Foreign is one of a bead's wait edges onto a bead its store does not hold, an
// edge into another store, which holds nothing.
type Foreign struct {
	ID   string `json:"id"`
	Type string `json:"type"`
}

// Arm is the arm on a bead armed to start by itself, each value as the store
// holds it: the pool or agent a sling goes to, with its arguments, why and by
// whom it was armed and when, its sling marker and attempt count, and the agent
// a notice is owed to.
type Arm struct {
	Target    string `json:"target,omitempty"`
	Args      string `json:"args,omitempty"`
	Reason    string `json:"reason,omitempty"`
	ArmedBy   string `json:"armed_by,omitempty"`
	ArmedAt   string `json:"armed_at,omitempty"`
	Slung     string `json:"slung,omitempty"`
	FailCount string `json:"fail_count,omitempty"`
	Notify    string `json:"notify,omitempty"`
}

// Holds is what holds one bead. Waits are the waits behind its status: its own
// for a blocked or an unjudged bead, and the waits of the one ancestor it is
// held through for a held bead. Pending are its own waits that have not landed.
// LastLanded is when the last wait that applies to it landed, by the rule for
// where its work is: its own waits, and for work that has not started the waits
// of each live ancestor too, since they hold that work as its own do. InFlight is
// why the bead is in flight, empty when it is not. Arm is nil when the bead
// carries none, and Foreign lists its wait edges into another store.
type Holds struct {
	ID         string    `json:"id"`
	Status     Status    `json:"status"`
	Waits      []Wait    `json:"waits"`
	Pending    []Wait    `json:"pending"`
	LastLanded string    `json:"last_landed"`
	InFlight   string    `json:"in_flight"`
	Arm        *Arm      `json:"arm"`
	Foreign    []Foreign `json:"foreign"`
}

// waitTypes are the edge types the store's blocked rule reads as a wait of the
// bead's own.
var waitTypes = []string{ledger.EdgeBlocks, ledger.EdgeConditionalBlocks, ledger.EdgeWaitsFor}

func isWait(e ledger.Edge) bool { return slices.Contains(waitTypes, e.Type) }

// Snapshot is one pass's read of what holds the beads named: the ledger's
// snapshot of them and their ancestors with the store's blocked set, the
// listing's view of each one's edges, and the runs that tell whether each is in
// flight. Every question asked of it in a pass gets the same answer.
type Snapshot struct {
	ls      *ledger.Snapshot
	missing map[string]error
	foreign map[string][]Foreign
	flight  map[string]string
}

// ReadStore reads one snapshot of what holds each bead named, as Read does,
// from the city's store at db, a store's .beads directory, or from the store gc
// resolves when db is empty. Every read names that one store, so a bead's edge
// into another store is never read as one its store holds. It is the entry for
// a reader the ledger is internal to, the helm board among them, which names
// each rig's store.
func ReadStore(db string, ids ...string) (*Snapshot, error) {
	l, err := ledger.Open(db)
	if err != nil {
		return nil, err
	}
	return Read(l, ids...)
}

// Read reads one snapshot of what holds each bead named. A bead the store does
// not hold gets its error from Holds, and every other bead is answered. A read
// that fails fails the snapshot with its *ledger.ReadError.
func Read(l *ledger.Ledger, ids ...string) (*Snapshot, error) {
	ids = slices.Compact(slices.Sorted(slices.Values(ids)))
	s := &Snapshot{missing: map[string]error{}, foreign: map[string][]Foreign{}, flight: map[string]string{}}
	listed, err := l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	edges := make(map[string][]ledger.Edge, len(listed))
	for _, r := range listed {
		e, err := r.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		edges[r.ID] = e
	}
	var held []string
	for _, id := range ids {
		if _, ok := edges[id]; !ok {
			s.missing[id] = &ledger.ReadError{ID: id, Reason: "the store holds no such bead"}
			continue
		}
		held = append(held, id)
	}
	if len(held) == 0 {
		return s, nil
	}
	if s.ls, err = l.Read(held...); err != nil {
		return nil, err
	}
	if err := s.readForeign(l, held, edges); err != nil {
		return nil, err
	}
	if err := s.readFlight(l, held); err != nil {
		return nil, err
	}
	return s, nil
}

// readForeign finds each bead's wait edges into another store. A snapshot's
// record leaves out an edge whose far bead the store does not hold, and the
// listing keeps every edge, so an edge the listing has and the record lacks is a
// candidate, and one more read of the candidates' far beads names the ones the
// store does not hold.
func (s *Snapshot) readForeign(l *ledger.Ledger, ids []string, listed map[string][]ledger.Edge) error {
	shown := make(map[string][]ledger.Edge, len(ids))
	var far []string
	for _, id := range ids {
		r, _ := s.ls.Record(id)
		e, err := r.Edges()
		if err != nil {
			return &ledger.ReadError{ID: id, Reason: "its edges did not decode: " + err.Error()}
		}
		shown[id] = e
		for _, c := range candidates(listed[id], e) {
			far = append(far, c.ID)
		}
	}
	rows, err := l.Find(ledger.ByID(far...).WithClosed())
	if err != nil {
		return err
	}
	held := map[string]bool{}
	for _, r := range rows {
		held[r.ID] = true
	}
	for _, id := range ids {
		if f := foreignOf(listed[id], shown[id], held); len(f) > 0 {
			s.foreign[id] = f
		}
	}
	return nil
}

// candidates are the wait edges the listing has that the record lacks.
func candidates(listed, shown []ledger.Edge) []ledger.Edge {
	var out []ledger.Edge
	for _, e := range listed {
		if isWait(e) && !slices.ContainsFunc(shown, func(x ledger.Edge) bool { return x.ID == e.ID && x.Type == e.Type }) {
			out = append(out, e)
		}
	}
	return out
}

// foreignOf is the candidates whose far bead the store does not hold, held
// naming the far beads it does. A candidate whose far bead the store holds is
// not one into another store. A write between the reads made them disagree,
// such as the edge's removal after the listing read it or the far bead's
// creation after the snapshot left the edge out.
func foreignOf(listed, shown []ledger.Edge, held map[string]bool) []Foreign {
	var out []Foreign
	for _, e := range candidates(listed, shown) {
		if !held[e.ID] {
			out = append(out, Foreign{ID: e.ID, Type: e.Type})
		}
	}
	return out
}

// readFlight decides, for each bead, whether it is in flight. Its own row
// settles most beads, and only the beads it does not settle need the runs read.
func (s *Snapshot) readFlight(l *ledger.Ledger, ids []string) error {
	var unsettled []string
	for _, id := range ids {
		r, _ := s.ls.Record(id)
		why, err := rowFlight(r)
		if err != nil {
			return err
		}
		if why == "" {
			unsettled = append(unsettled, id)
			continue
		}
		s.flight[id] = why
	}
	if len(unsettled) == 0 {
		return nil
	}
	runs, err := liveRuns(l)
	if err != nil {
		return err
	}
	for _, r := range runs {
		if r.bead == "" || !slices.Contains(unsettled, r.bead) || s.flight[r.bead] != "" {
			continue
		}
		past, err := pastLoadContext(l, r.root)
		if err != nil {
			return err
		}
		if past {
			s.flight[r.bead] = "workflow " + r.root + " past load-context"
		}
	}
	return nil
}

// rowFlight is why the bead's own row shows it in flight: a claim status,
// in_progress or hooked, or a key that the work's start writes. It is empty when
// the row shows neither.
func rowFlight(r *ledger.Record) (string, error) {
	if st := r.Status(); st == "in_progress" || st == "hooked" {
		return "status " + st, nil
	}
	for _, k := range []ledger.Key[string]{branchKey, mergeResultKey, rejectionReasonKey} {
		v, _, err := k.Get(r)
		if err != nil {
			return "", err
		}
		if v != "" {
			return "carries " + k.Name(), nil
		}
	}
	return "", nil
}

// InFlight is why the bead is in flight, by steering.md's test, empty when it
// is not: someone has claimed it, it carries branch, merge_result or
// rejection_reason, or a live workflow poured for it has passed load-context.
func (s *Snapshot) InFlight(id string) (string, error) {
	if err := s.missing[id]; err != nil {
		return "", err
	}
	if _, ok := s.record(id); !ok {
		return "", &ledger.ReadError{ID: id, Reason: "the snapshot did not read it"}
	}
	return s.flight[id], nil
}

func (s *Snapshot) record(id string) (*ledger.Record, bool) {
	if s.ls == nil {
		return nil, false
	}
	return s.ls.Record(id)
}

// Holds answers what holds the bead. A read that could not answer returns its
// *ledger.ReadError and no status, and so does a bead the store marks blocked
// that its blocked listing left out. A bead with a waits-for edge of its own
// reads Unjudged, which is not a failed read.
func (s *Snapshot) Holds(id string) (Holds, error) {
	if err := s.missing[id]; err != nil {
		return Holds{}, err
	}
	r, ok := s.record(id)
	if !ok {
		return Holds{}, &ledger.ReadError{ID: id, Reason: "the snapshot did not read it"}
	}
	own, err := r.Edges()
	if err != nil {
		return Holds{}, &ledger.ReadError{ID: id, Reason: "its edges did not decode: " + err.Error()}
	}
	h := Holds{ID: id, Waits: []Wait{}, Pending: []Wait{}, InFlight: s.flight[id], Arm: armOf(r), Foreign: []Foreign{}}
	if h.LastLanded, err = s.lastLanded(r, own, h.InFlight == ""); err != nil {
		return Holds{}, err
	}
	if f := s.foreign[id]; f != nil {
		h.Foreign = f
	}
	ans, err := s.ls.Blocking(id)
	var wf *ledger.WaitsForError
	switch {
	case errors.As(err, &wf):
		h.Status = Unjudged
		h.Waits = waitsOn(own, append(slices.Clone(wf.Spawners), wf.Blocks...), "")
		h.Pending = h.Waits
	case err != nil:
		return Holds{}, err
	case !ans.Blocked:
		h.Status = Clear
	case len(ans.On) > 0:
		h.Status = Blocked
		h.Waits = waitsOn(own, ans.On, "")
		h.Pending = h.Waits
	case h.InFlight != "":
		h.Status = Clear
	default:
		h.Status = Held
		if h.Waits, err = s.inherited(id, ans.Through); err != nil {
			return Holds{}, err
		}
	}
	return h, nil
}

// inherited follows the store's answer up from the parent a bead is held
// through to the ancestor whose own waits hold it, and returns those waits,
// each naming that ancestor. An ancestor with a waits-for edge of its own is the
// one, with its waits unjudged. An ancestor the store could not answer, or one
// its listing does not hold, leaves the bead's answer unread.
func (s *Snapshot) inherited(id, through string) ([]Wait, error) {
	seen := map[string]bool{id: true}
	for cur := through; ; {
		if seen[cur] {
			return nil, &ledger.ReadError{ID: id, Reason: fmt.Sprintf("the store holds it through %s, whose ancestry comes back to itself", cur)}
		}
		seen[cur] = true
		r, ok := s.record(cur)
		if !ok {
			return nil, &ledger.ReadError{ID: id, Reason: "the snapshot did not read its ancestor " + cur}
		}
		edges, err := r.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: id, Reason: fmt.Sprintf("the edges of its ancestor %s did not decode: %v", cur, err)}
		}
		ans, err := s.ls.Blocking(cur)
		var wf *ledger.WaitsForError
		switch {
		case errors.As(err, &wf):
			return waitsOn(edges, append(slices.Clone(wf.Spawners), wf.Blocks...), cur), nil
		case err != nil:
			return nil, &ledger.ReadError{ID: id, Reason: fmt.Sprintf("the store holds it through %s, which it could not answer: %v", cur, err)}
		case !ans.Blocked:
			return nil, &ledger.ReadError{ID: id, Reason: fmt.Sprintf("the store holds it through %s, which its blocked listing does not hold", cur)}
		case len(ans.On) > 0:
			return waitsOn(edges, ans.On, cur), nil
		}
		cur = ans.Through
	}
}

// waitsOn is the wait edges among edges onto the beads ids names, in the order
// named, each naming ancestor, the bead whose edges they are, unless that is the
// bead asked about.
func waitsOn(edges []ledger.Edge, ids []string, ancestor string) []Wait {
	out := []Wait{}
	for _, id := range ids {
		for _, e := range edges {
			if e.ID == id && isWait(e) {
				out = append(out, Wait{ID: e.ID, Type: e.Type, Title: e.Title, Status: e.Status, Ancestor: ancestor})
			}
		}
	}
	return out
}

// lastLanded is when the last wait that applies to the bead landed: the latest
// close time among its own blocks and conditional-blocks edges onto a closed
// bead and, for work that has not started, among those of each ancestor the
// store holds it under, up to the first closed or pinned one, whose waits hold
// nothing below it. It is empty when none has closed. A waits-for edge lands
// when its gate opens, which no close time records, so its spawner's close is no
// landing.
func (s *Snapshot) lastLanded(r *ledger.Record, own []ledger.Edge, unstarted bool) (string, error) {
	last, text, err := landedAmong(r.ID, own, time.Time{}, "")
	if err != nil || !unstarted {
		return text, err
	}
	seen := map[string]bool{r.ID: true}
	cur, err := r.Parent()
	for ; err == nil && cur != "" && !seen[cur]; cur, err = r.Parent() {
		seen[cur] = true
		var ok bool
		if r, ok = s.record(cur); !ok {
			return text, nil
		}
		if st := r.Status(); st == "closed" || st == "pinned" {
			return text, nil
		}
		edges, eerr := r.Edges()
		if eerr != nil {
			return "", &ledger.ReadError{ID: cur, Reason: "its edges did not decode: " + eerr.Error()}
		}
		if last, text, err = landedAmong(cur, edges, last, text); err != nil {
			return "", err
		}
	}
	if err != nil {
		return "", &ledger.ReadError{ID: cur, Reason: "its edges did not decode: " + err.Error()}
	}
	return text, nil
}

// landedAmong is the later of last, whose stored text is text, and the latest
// close among edges' blocks and conditional-blocks waits onto a closed bead.
func landedAmong(id string, edges []ledger.Edge, last time.Time, text string) (time.Time, string, error) {
	for _, e := range edges {
		if (e.Type != ledger.EdgeBlocks && e.Type != ledger.EdgeConditionalBlocks) || e.Status != "closed" {
			continue
		}
		at, err := time.Parse(time.RFC3339Nano, e.ClosedAt)
		if err != nil {
			return last, "", &ledger.ReadError{ID: id, Reason: fmt.Sprintf("the close time of %s, %q, does not read as a time", e.ID, e.ClosedAt)}
		}
		if text == "" || at.After(last) {
			last, text = at, e.ClosedAt
		}
	}
	return last, text, nil
}

// armOf is the bead's arm, nil when it carries neither a sling target nor an
// owed notice.
func armOf(r *ledger.Record) *Arm {
	get := func(k ledger.Key[string]) string {
		v, _, _ := k.Get(r) // a String key's stored text always decodes
		return v
	}
	a := Arm{
		Target:    get(armTargetKey),
		Args:      get(armArgsKey),
		Reason:    get(armReasonKey),
		ArmedBy:   get(armedByKey),
		ArmedAt:   get(armedAtKey),
		Slung:     get(armSlungKey),
		FailCount: get(armFailCountKey),
		Notify:    get(noticeKey),
	}
	if a.Target == "" && a.Notify == "" {
		return nil
	}
	return &a
}
