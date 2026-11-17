package memory

import (
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// Settled is what one settle did: the units it removed because a fix they
// waited on landed, the units due again because their wait ended with none,
// what it said of each place, and what it could not do.
type Settled struct {
	Places    Places
	Left, Due int
	Said      []string
	Failed    []string
}

// How a wait stands.
const (
	waiting = iota
	landedFix
	ended
)

type outcome struct {
	state    int
	day, why string
}

// landingDepth bounds how many integration branches a landing is followed
// through.
const landingDepth = 3

// Settle ends each wait that is done. A unit whose bead closed on a merge that
// reached its repository's default branch is removed, its text kept, and the
// pointers to a removed note go with it. For a feedback pattern that is any of
// its follow-ups, once none is still on its way: the beads its blocks edges
// name, its proposal_bead and its eng_bead. A merge into an integration
// branch lands when the effort's landing bead does. A wait that ended with no
// fix landed makes its unit due at once, as old as the day it ended, with why.
// A row whose unit is gone from its directory leaves the list. A place whose
// memory directory it cannot learn is one patrol finding. An error is a city
// whose places did not read.
func (in *Intake) Settle() (Settled, error) {
	ps, err := in.Places()
	if err != nil {
		return Settled{}, err
	}
	s := Settled{Places: ps}
	var ids []string
	for _, p := range ps.Read {
		rows, err := readList(ps.state(p))
		if err != nil {
			s.Failed = append(s.Failed, err.Error())
			continue
		}
		for _, r := range rows {
			if r.Wait != "" && !slices.Contains(ids, r.Wait) {
				ids = append(ids, r.Wait)
			}
		}
	}
	outcomes := in.decide(ps, ids, &s)
	for _, p := range ps.Read {
		in.settleIn(ps, p, outcomes, &s)
	}
	in.report(ps, &s)
	return s, nil
}

// The patrol finding a settle keeps for the places it cannot learn.
const (
	findingScope = "memory-intake"
	findingKey   = "memory-intake.places"
)

// report files one finding that names each place whose memory directory the
// intake could not learn, through patrol-finding.sh, which updates the live
// finding of its key, and clears that finding once every place is learned.
func (in *Intake) report(ps Places, s *Settled) {
	args := []string{"--scope", findingScope, "--key", findingKey}
	if len(ps.Unknown) == 0 {
		args = append(args, "--cleared", "--message", "The memory intake learns every place's memory directory again.")
		if f := in.Runtime.Script("patrol-finding.sh", args...).Failure(); f != "" {
			s.Failed = append(s.Failed, "the finding "+findingKey+" was not cleared: "+f)
		}
		return
	}
	var names, why []string
	for _, u := range ps.Unknown {
		names = append(names, u.Name)
		why = append(why, "- "+u.Name+": "+u.Why)
	}
	args = append(args, "--title", "Memory intake cannot learn where Claude Code keeps the memory of "+strings.Join(names, ", "),
		"--message", "The learning loop's memory intake asks Claude Code where the sessions of each rig and of the "+
			"city's root keep memory, and reads and removes nothing where it cannot learn that:\n"+strings.Join(why, "\n"),
		"--type", "bug", "--priority", "3")
	if f := in.Runtime.Script("patrol-finding.sh", args...).Failure(); f != "" {
		s.Failed = append(s.Failed, "the finding "+findingKey+" did not record: "+f)
	}
}

// decide reads every bead a unit waits on, from one read of each store, and
// says how each wait stands. A wait whose store does not answer stays.
func (in *Intake) decide(ps Places, ids []string, s *Settled) map[string]outcome {
	out := map[string]outcome{}
	byRig := map[string][]string{}
	rigs := map[string]gascity.Rig{}
	for _, id := range ids {
		rig, ok := ps.rigOf(id)
		if !ok {
			s.Failed = append(s.Failed, "no store of the city carries "+id+", so what waits on it stays")
			continue
		}
		byRig[rig.Path] = append(byRig[rig.Path], id)
		rigs[rig.Path] = rig
	}
	today := in.today()
	for path, ids := range byRig {
		j := &judge{in: in, rig: rigs[path], db: filepath.Join(path, ".beads"), s: s}
		recs, err := in.find(j.db, ids)
		if err != nil {
			s.Failed = append(s.Failed, fmt.Sprintf("the store at %s did not answer, so the waits on its beads stay: %v", j.db, err))
			continue
		}
		j.read = recs
		for _, id := range ids {
			out[id] = j.wait(id, today)
		}
	}
	return out
}

// A judge decides the waits on one store's beads.
type judge struct {
	in   *Intake
	rig  gascity.Rig
	db   string
	read map[string]*ledger.Record
	s    *Settled

	defaultRead bool
	def         string
}

func (j *judge) wait(id, today string) outcome {
	r, ok := j.read[id]
	if !ok {
		return outcome{ended, today, "waited on " + id + ", which is not in its store"}
	}
	if r.Status() != "closed" {
		return outcome{state: waiting}
	}
	day := closedDay(r, today)
	reason := ""
	if cr := strings.TrimSpace(r.CloseReason()); cr != "" {
		reason = ": " + cr
	}
	role, _, err := roleKey.Get(r)
	if err != nil {
		j.fail("%s's task_kind did not read, so what waits on it stays: %v", id, err)
		return outcome{state: waiting}
	}
	if role != pattern {
		switch j.landed(r, 0) {
		case landedFix:
			return outcome{state: landedFix}
		case ended:
			return outcome{ended, day, "waited on " + id + ", which closed with no merge" + reason}
		}
		return outcome{state: waiting}
	}
	ups, err := j.followUps(r)
	if err != nil {
		j.fail("the store at %s did not answer for the follow-ups of %s, so what waits on it stays: %v", j.db, id, err)
		return outcome{state: waiting}
	}
	any := false
	for _, f := range ups {
		switch j.landed(f, 0) {
		case waiting:
			return outcome{state: waiting}
		case landedFix:
			any = true
		}
	}
	if any {
		return outcome{state: landedFix}
	}
	return outcome{ended, day, "waited on " + id + ", which closed with no fix landed" + reason}
}

// followUps is the beads a pattern spawned that its store holds: the beads its
// blocks edges name, its proposal_bead and its eng_bead.
func (j *judge) followUps(r *ledger.Record) ([]*ledger.Record, error) {
	var ids []string
	for _, k := range []ledger.Key[string]{proposalKey, engKey} {
		v, _, err := k.Get(r)
		if err != nil {
			return nil, err
		}
		if v = strings.TrimSpace(v); v != "" {
			ids = append(ids, v)
		}
	}
	edges, err := r.Edges()
	if err != nil {
		return nil, err
	}
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks {
			ids = append(ids, e.ID)
		}
	}
	slices.Sort(ids)
	ids = slices.Compact(ids)
	if err := j.load(ids); err != nil {
		return nil, err
	}
	var out []*ledger.Record
	for _, id := range ids {
		if f, ok := j.read[id]; ok {
			out = append(out, f)
		}
	}
	return out, nil
}

// load reads each bead named that the judge has not read.
func (j *judge) load(ids []string) error {
	var want []string
	for _, id := range ids {
		if _, ok := j.read[id]; !ok {
			want = append(want, id)
		}
	}
	if len(want) == 0 {
		return nil
	}
	recs, err := j.in.find(j.db, want)
	if err != nil {
		return err
	}
	for id, r := range recs {
		j.read[id] = r
	}
	return nil
}

// landed says whether r's work reached its repository's default branch: its
// merge commit is on origin's default branch as the rig's checkout last fetched
// it, or it merged into integration/<id> and the bead <id> has landed. A bead
// that closed with no merge commit landed nothing. Any other merge, and one
// the checkout cannot judge, is still on its way.
func (j *judge) landed(r *ledger.Record, depth int) int {
	if r.Status() != "closed" {
		return waiting
	}
	rec, err := record.Read(r)
	if err != nil {
		j.fail("%s's merge record did not read, so what waits on it stays: %v", r.ID, err)
		return waiting
	}
	if !git.IsObjectID(rec.MergedSHA) {
		return ended
	}
	def, ok := j.defaultBranch()
	if !ok {
		return waiting
	}
	if reached, err := git.Reaches(j.rig.Path, rec.MergedSHA, def); err != nil {
		j.fail("whether %s's merge %s is on origin/%s in %s did not read, so what waits on it stays: %v",
			r.ID, rec.MergedSHA, def, j.rig.Path, err)
		return waiting
	} else if reached {
		return landedFix
	}
	landing, ok := strings.CutPrefix(rec.Target, "integration/")
	if !ok || landing == "" || depth >= landingDepth {
		return waiting
	}
	if err := j.load([]string{landing}); err != nil {
		j.fail("the store at %s did not answer for %s, the landing of %s, so what waits on it stays: %v", j.db, landing, r.ID, err)
		return waiting
	}
	lr, ok := j.read[landing]
	if !ok {
		return waiting
	}
	return j.landed(lr, depth+1)
}

// defaultBranch is the branch origin/HEAD names in the rig's checkout, read
// once. Where it names none, no merge there is taken as landed.
func (j *judge) defaultBranch() (string, bool) {
	if !j.defaultRead {
		j.defaultRead = true
		def, err := git.DefaultBranch(j.rig.Path)
		if err != nil {
			j.fail("the origin/HEAD of %s names no branch, so no merge there is taken as landed and each wait on one stays; "+
				"set it with git -C '%s' remote set-head origin --auto", j.rig.Path, j.rig.Path)
		}
		j.def = def
	}
	return j.def, j.def != ""
}

func (j *judge) fail(format string, args ...any) {
	j.s.Failed = append(j.s.Failed, fmt.Sprintf(format, args...))
}

// closedDay is the UTC day r closed, or today when its close time names none or
// a later day.
func closedDay(r *ledger.Record, today string) string {
	t, err := time.Parse(time.RFC3339, strings.TrimSpace(r.ClosedAt()))
	if err != nil {
		return today
	}
	if d := t.UTC().Format(time.DateOnly); d <= today {
		return d
	}
	return today
}

// settleIn applies the decided waits to one place under its lock: it removes
// each unit whose fix landed and is unchanged since it was judged, makes each
// unit whose wait ended due, takes out the pointers to a removed note, and
// drops the rows whose unit is gone.
func (in *Intake) settleIn(ps Places, p Place, outcomes map[string]outcome, s *Settled) {
	state := ps.state(p)
	release, err := in.lock(state, p.Dir)
	if err != nil {
		s.Failed = append(s.Failed, err.Error())
		return
	}
	defer release()
	units, err := scan(p.Dir)
	if err != nil {
		s.Failed = append(s.Failed, err.Error()+"; nothing there is removed, and its list stays as it is")
		return
	}
	rows, err := readList(state)
	if err != nil {
		s.Failed = append(s.Failed, err.Error())
		return
	}
	present := map[string]Unit{}
	notes, entries := 0, 0
	for _, u := range units {
		present[u.key()] = u
		if u.Kind == Note {
			notes++
		} else {
			entries++
		}
	}
	gone := map[string]bool{}
	var keep []row
	for _, r := range rows {
		u, ok := present[r.key()]
		if !ok {
			continue
		}
		o, decided := outcomes[r.Wait]
		switch {
		case r.Wait == "" || !decided || o.state == waiting:
		case o.state == ended:
			r.Wait, r.Next, r.Why = "", o.day, o.why
			s.Due++
		case u.Hash != r.Hash:
		default:
			if in.leave(state, p.Dir, u, gone, s) {
				s.Left++
				continue
			}
		}
		keep = append(keep, r)
	}
	if len(gone) > 0 {
		s.Failed = append(s.Failed, prune(state, p.Dir, gone)...)
		keep = withoutFiles(keep, gone)
	}
	if err := writeList(state, keep); err != nil {
		s.Failed = append(s.Failed, err.Error())
	}
	s.Said = append(s.Said, fmt.Sprintf("%s: %s, %d notes and %d entries", p.names(), p.Dir, notes, entries))
}

// leave removes a unit whose fix landed, and reports whether it went.
func (in *Intake) leave(state, dir string, u Unit, gone map[string]bool, s *Settled) bool {
	if u.Kind == Note {
		r, _, err := removeNote(state, dir, u.Name, u.Full)
		switch r {
		case removed:
			gone[u.Name] = true
			return true
		case failed:
			s.Failed = append(s.Failed, fmt.Sprintf("%s stays, though its wait ended with a fix landed: %v", filepath.Join(dir, u.Name), err))
		}
		return false
	}
	r, _, hubGone, err := removeEntry(state, dir, u)
	if hubGone {
		gone[u.Name] = true
	}
	if err != nil {
		s.Failed = append(s.Failed, fmt.Sprintf("%s: %v", filepath.Join(dir, u.Name), err))
	}
	return r == removed
}
