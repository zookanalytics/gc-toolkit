package review

import (
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// A review run judges one head of one PR: a root of the review formula,
// attached to the bead that owns the PR, whose vars name that bead, the head
// and the target. Its loop is a checked template step, one iteration per head
// it judges. In each iteration triage picks the checks the head needs, one lane
// runs each, and rule-and-repair rules every finding and every ask it takes
// and makes the round's fixes as one push.
//
// What the run judged is in its steps' outputs, which Gas City keeps on the
// run's beads: each step writes one JSON object as its gc.output_json before it
// closes, in the shapes below. The `review` field names the step that wrote it
// and `iteration` the loop iteration it ran in, the number the runtime counts
// iterations by, from 1. A step's output with no `review` field is not one of
// these and is not read.

// The steps whose outputs a run reads, as an output's `review` field names
// them.
const (
	OutputTriage = "triage"
	OutputLane   = "lane"
	OutputRepair = "repair"
)

// A lane's verdict.
const (
	VerdictApprove        = "approve"
	VerdictRequestChanges = "request-changes"
)

// A ruling of a finding or an ask, by the rule its source carries.
const (
	// RulingMustFix: it holds, and the round fixes it. The ruling names the
	// commit that fixes it.
	RulingMustFix = "must-fix"
	// RulingDeclined: its source's own rule shows it does not hold, or does
	// not fix it, as a nit is answered and not fixed. The reason says which.
	RulingDeclined = "declined"
	// RulingDeferred: it holds and reaches outside the reviewed diff, so it goes
	// to a bead of its own, armed to start once the PR lands.
	RulingDeferred = "deferred"
	// RulingAnswered: nothing is left to change, because the head already
	// carries its answer, such as an ask whose fix an earlier head carries or
	// whose check ran at this head.
	RulingAnswered = "answered"
	// RulingQuestion: only a person can answer it, so the round put it to one
	// through a human gate on the bead, which the ruling names.
	RulingQuestion = "question"
)

var rulings = []string{RulingMustFix, RulingDeclined, RulingDeferred, RulingAnswered, RulingQuestion}

// Triage is what the triage step writes: the head it judged, the checks it
// picked for that head, one lane bonded for each, and whether the change it
// judged is material.
type Triage struct {
	Review    string `json:"review"`
	Iteration int    `json:"iteration"`
	Head      string `json:"head"`
	Checks    []Pick `json:"checks"`
	Material  bool   `json:"material"`
}

// Pick is one check triage picked at its head, the item its fan-out bonds a
// lane for.
type Pick struct {
	Check string `json:"check"`
	Head  string `json:"head"`
}

// Lane is what a lane writes: its check, the head it reviewed, its verdict and
// its findings, and the verdict's note for the person who approves the merge,
// "" when the verdict needs nothing from them.
type Lane struct {
	Review    string    `json:"review"`
	Iteration int       `json:"iteration"`
	Check     string    `json:"check"`
	Head      string    `json:"head"`
	Verdict   string    `json:"verdict"`
	Findings  []Finding `json:"findings"`
	NeedsYou  string    `json:"needs_you,omitempty"`
}

// Finding is one finding a lane raised, in the finding contract its check's
// method writes, with the id a ruling names it by, unique among its lane's
// findings.
type Finding struct {
	ID              string `json:"id"`
	Locus           string `json:"locus"`
	Message         string `json:"message"`
	Severity        string `json:"severity"`
	Category        string `json:"category"`
	FailureScenario string `json:"failure_scenario"`
	Verification    string `json:"verification,omitempty"`
}

// Repair is what rule-and-repair writes: the head it ruled at, a ruling for
// each finding and each ask it took, and the head its push made, "" when it
// pushed nothing.
type Repair struct {
	Review    string   `json:"review"`
	Iteration int      `json:"iteration"`
	Head      string   `json:"head"`
	Rulings   []Ruling `json:"rulings"`
	Pushed    string   `json:"pushed,omitempty"`
}

// Ruling is how the round ruled one finding, named by its lane's check and its
// id, or one ask, named by its bead: the ruling, its reason, the commit that
// fixes a must-fix finding and the gate a question went to.
type Ruling struct {
	Check   string `json:"check,omitempty"`
	Finding string `json:"finding,omitempty"`
	Ask     string `json:"ask,omitempty"`
	Ruling  string `json:"ruling"`
	Reason  string `json:"reason,omitempty"`
	Commit  string `json:"commit,omitempty"`
	Gate    string `json:"gate,omitempty"`
}

// Subject is what the ruling rules, as the account names it.
func (r Ruling) Subject() string {
	if r.Ask != "" {
		return "ask " + r.Ask
	}
	return r.Check + " finding " + r.Finding
}

// Run is a review run as the store holds it: its root, the vars it was poured
// with, the control bead of its loop, and the outputs its steps wrote, by
// iteration. Broken names each output that names a step of the review and
// does not read as one, which the pass rule reads as not written.
type Run struct {
	Root, PRBead, Head, Target string
	Shadow                     bool
	Loop                       *ledger.Record
	Iterations                 map[int]*Iteration
	Broken                     []string
}

// Iteration is what one iteration's steps wrote.
type Iteration struct {
	N      int
	Triage *Triage
	Lanes  []Lane
	Repair *Repair
}

// NotARun is the error of a bead that is neither a review run's root nor a
// bead poured under one.
type NotARun struct{ ID, Why string }

func (e *NotARun) Error() string { return e.ID + " is not a review run: " + e.Why }

// ReadRun reads the review run id names: its root, or any bead poured under
// it, such as the iteration its loop's check runs for. A read that fails
// returns the store's error.
func ReadRun(l *ledger.Ledger, id string) (*Run, error) {
	root, err := one(l, id)
	if err != nil {
		return nil, err
	}
	if up := str(rootBeadKey, root); up != "" && up != root.ID {
		if root, err = one(l, up); err != nil {
			return nil, err
		}
	}
	run := &Run{Root: root.ID, PRBead: str(prBeadVar, root), Head: str(headVar, root),
		Target: str(targetVar, root), Shadow: str(shadowVar, root) == "true", Iterations: map[int]*Iteration{}}
	if run.PRBead == "" {
		return nil, &NotARun{ID: id, Why: fmt.Sprintf("its root %s names no pr_bead var", root.ID)}
	}
	members, err := l.Find(ledger.Matching(rootBeadKey, root.ID).WithClosed())
	if err != nil {
		return nil, err
	}
	slices.SortFunc(members, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, m := range members {
		if strings.EqualFold(str(kindKey, m), "ralph") {
			if run.Loop != nil {
				return nil, &NotARun{ID: id, Why: fmt.Sprintf("its root %s has two loops, %s and %s", root.ID, run.Loop.ID, m.ID)}
			}
			run.Loop = m
		}
		if raw := str(outputKey, m); raw != "" {
			if why := run.add(raw); why != "" {
				run.Broken = append(run.Broken, m.ID+": "+why)
			}
		}
	}
	return run, nil
}

// one is the bead id names, closed or not.
func one(l *ledger.Ledger, id string) (*ledger.Record, error) {
	rows, err := l.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, &ledger.ReadError{ID: id, Reason: "the store holds no such bead"}
	}
	return rows[0], nil
}

// str is a String key's value on r, trimmed, "" when r does not carry it. A
// String key's stored text always decodes.
func str(k ledger.Key[string], r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return strings.TrimSpace(v)
}

// view is a String key's value on r read through its owner's face, trimmed,
// "" when r does not carry it.
func view(k ledger.View[string], r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return strings.TrimSpace(v)
}

// add files one step's output under its iteration, or says why it does not
// read. An output with no `review` field is another step's, and adds nothing.
func (run *Run) add(raw string) string {
	var head struct {
		Review    *string `json:"review"`
		Iteration int     `json:"iteration"`
	}
	if err := json.Unmarshal([]byte(raw), &head); err != nil {
		return "its output is not one JSON object: " + err.Error()
	}
	if head.Review == nil {
		return ""
	}
	if head.Iteration < 1 {
		return fmt.Sprintf("its %s output names no iteration", *head.Review)
	}
	it := run.Iterations[head.Iteration]
	if it == nil {
		it = &Iteration{N: head.Iteration}
		run.Iterations[head.Iteration] = it
	}
	switch *head.Review {
	case OutputTriage:
		var t Triage
		if err := strict(raw, &t); err != nil {
			return "its triage output does not read: " + err.Error()
		}
		if it.Triage != nil {
			return fmt.Sprintf("iteration %d has a second triage output", head.Iteration)
		}
		it.Triage = &t
	case OutputLane:
		var ln Lane
		if err := strict(raw, &ln); err != nil {
			return "its lane output does not read: " + err.Error()
		}
		for _, prior := range it.Lanes {
			if strings.EqualFold(prior.Check, ln.Check) {
				return fmt.Sprintf("iteration %d has a second %s lane", head.Iteration, ln.Check)
			}
		}
		it.Lanes = append(it.Lanes, ln)
	case OutputRepair:
		var rp Repair
		if err := strict(raw, &rp); err != nil {
			return "its repair output does not read: " + err.Error()
		}
		if it.Repair != nil {
			return fmt.Sprintf("iteration %d has a second repair output", head.Iteration)
		}
		it.Repair = &rp
	default:
		return fmt.Sprintf("its output names the step %q, which is not triage, lane or repair", *head.Review)
	}
	return ""
}

// strict decodes raw into v, refusing a field the shape does not name, so a
// step that misspells one is read as not having written it.
func strict(raw string, v any) error {
	dec := json.NewDecoder(strings.NewReader(raw))
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

// Last is the number of the run's last iteration whose triage wrote a head,
// the last head the run judged, and 0 when it judged none.
func (run *Run) Last() int {
	last := 0
	for n, it := range run.Iterations {
		if it.Triage != nil && it.Triage.Head != "" && n > last {
			last = n
		}
	}
	return last
}

// Latest is the number of the run's latest iteration any step wrote for.
func (run *Run) Latest() int {
	latest := 0
	for n := range run.Iterations {
		latest = max(latest, n)
	}
	return latest
}
