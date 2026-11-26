package rig

import (
	"encoding/json"
	"fmt"
	"reflect"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/disposition"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/git"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
)

// setup and build run with no record, so a pre-existing mark of either judges
// the self-review's note of what it did at the commit.
const (
	CheckSetup = "setup"
	CheckBuild = "build"
)

// Mark is a caller's judgment that one recorded fail of a check is
// pre-existing: the same failure is red on the target, and the trackers it
// names carry it.
type Mark struct {
	// Commit is the full sha the judgment is about.
	Commit string `json:"commit"`
	// Record is the fail it judged, as JSON: for test, lint and typecheck the
	// record the record store held at Commit, and for setup and build the
	// bead's note of what they did there.
	Record json.RawMessage `json:"record"`
	// Trackers are the tracker beads that carry the failure.
	Trackers []string `json:"trackers"`
}

// markKeyDoc is what each rig_check_pre_existing.<check> key holds, as the key
// registry states it.
const markKeyDoc = "A caller's judgment that one recorded fail of a check is pre-existing: the same failure is " +
	"red on the target, carried by the tracker beads it names. One JSON object of commit, the full sha the " +
	"judgment is about; record, the fail it judged, which for test, lint and typecheck is the record `gctk rig " +
	"<check> --check` reads at that commit and for setup and build the bead's self_review_setup_build note " +
	"naming the check failed there; and trackers, the tracker bead ids. `gctk rig pre-existing <check> --commit` " +
	"writes it, on the work bead in mol-polecat-work's self-review and on the anchor in the refinery's " +
	"handle-failures, and refuses a tracker that is not open. A write for the same record adds its trackers, " +
	"and one for another record replaces the value. `gctk rig pre-existing <check>` answers whether it holds: " +
	"only at its commit, for the fail recorded there, and while a tracker it names is open. " +
	"assets/scripts/self-review-check.sh asks it of the work bead, so the self-review loop converges past the " +
	"fail, and assets/scripts/review-evidence.sh of the anchor, so a correctness review runs no suite for it. " +
	"Absent means no caller judged a fail pre-existing. Never cleared."

// markKeys are the keys a mark is written in, one per check it judges. rig
// owns them.
var markKeys = map[string]ledger.Key[*Mark]{
	CheckTest:      ledger.Declare("rig_check_pre_existing."+CheckTest, ledger.JSON[*Mark](), markKeyDoc),
	CheckLint:      ledger.Declare("rig_check_pre_existing."+CheckLint, ledger.JSON[*Mark](), markKeyDoc),
	CheckTypecheck: ledger.Declare("rig_check_pre_existing."+CheckTypecheck, ledger.JSON[*Mark](), markKeyDoc),
	CheckSetup:     ledger.Declare("rig_check_pre_existing."+CheckSetup, ledger.JSON[*Mark](), markKeyDoc),
	CheckBuild:     ledger.Declare("rig_check_pre_existing."+CheckBuild, ledger.JSON[*Mark](), markKeyDoc),
}

// setupBuildKey is the self-review's note of what setup and build did at a
// commit, the fail a mark of either judges.
var setupBuildKey = ledger.ReadOnly("self_review_setup_build", ledger.JSON[json.RawMessage](),
	"What setup and build did at the commit a self-review iteration ran them at, which "+
		"assets/scripts/rig-checks.sh writes on the work bead: commit, setup and build, each pass, fail or none, "+
		"and the commands they ran. A pre-existing mark of setup or build holds this note as the fail it judged.")

// Marked reports whether check is one a pre-existing mark judges.
func Marked(check string) bool {
	_, ok := markKeys[check]
	return ok
}

// Answer is what a question about a pre-existing mark found.
type Answer int

const (
	// Holds is a mark that names the commit, holds the fail recorded there, and
	// names a tracker that is open.
	Holds Answer = iota
	// NoFail is a commit at which nothing recorded is a fail of the check.
	NoFail
	// NoMark is a bead with no mark of the check that names the commit and a
	// tracker.
	NoMark
	// AnotherRun is a mark at the commit that holds another run's fail, such as
	// the one a run with another command or scope replaced.
	AnotherRun
	// NoOpenTracker is a mark that holds the fail, no tracker of which is open.
	NoOpenTracker
	// Unread is a question a read did not answer: the record store, the bead,
	// or, when no tracker reads open, a tracker.
	Unread
)

// Judgment is the answer to whether a bead's mark holds a check's fail at a
// commit.
type Judgment struct {
	Answer Answer
	// Line says what was found, for an agent or a person to read, and is ""
	// for NoMark. For Holds it reads "pre-existing, tracked by <the open
	// trackers>". For NoOpenTracker and Unread it gives one clause per tracker
	// that is not open, saying what to do instead.
	Line string
	// Open is the trackers that are open, for Holds.
	Open []string
	// Warnings say why the chain of a tracker that closed ended with no bead,
	// where its walk said why.
	Warnings []string
}

// Judge answers whether bead's pre-existing mark of check holds the fail
// recorded at co's HEAD. It reads the fail itself: for test, lint and
// typecheck the record the record store holds at HEAD, and for setup and build
// the bead's note of them. A mark holds only at its commit, for that very
// fail, and while a tracker it names is open. A tracker that does not read is
// not open, and is reported as unread, never as closed.
func Judge(l *ledger.Ledger, co *git.Checkout, bead, check string) Judgment {
	at := co.Commit
	var fail json.RawMessage
	if validCheck(check) {
		rec, what, err := recordedFail(co, check)
		if err != nil {
			return Judgment{Answer: Unread, Line: err.Error()}
		}
		if rec == nil {
			return Judgment{Answer: NoFail, Line: what + ", so there is no fail to judge"}
		}
		fail = rec
	}
	b, err := readBead(l, bead)
	if err != nil {
		return Judgment{Answer: Unread, Line: fmt.Sprintf("%s did not read, so no pre-existing mark is known: %v", bead, err)}
	}
	if fail == nil {
		note, what := notedFail(b, at, check)
		if note == nil {
			return Judgment{Answer: NoFail, Line: what + ", so there is no fail to judge"}
		}
		fail = note
	}
	m := markOf(b, check)
	if m == nil || m.Commit != at || len(m.Trackers) == 0 {
		return Judgment{Answer: NoMark}
	}
	if !sameJSON(m.Record, fail) {
		return Judgment{Answer: AnotherRun, Line: fmt.Sprintf("the pre-existing mark on %s at %s judged another "+
			"run's fail, so this one needs a judgment of its own", bead, at)}
	}
	var open, closed, unread, warnings []string
	for _, t := range m.Trackers {
		s := trackerNow(l, t)
		switch {
		case s.open:
			open = append(open, t)
		case s.unread:
			unread = append(unread, s.clause)
		default:
			closed = append(closed, s.clause)
		}
		if s.warning != "" {
			warnings = append(warnings, s.warning)
		}
	}
	switch {
	case len(open) > 0:
		return Judgment{Answer: Holds, Line: "pre-existing, tracked by " + strings.Join(open, ", "), Open: open,
			Warnings: warnings}
	case len(unread) > 0:
		return Judgment{Answer: Unread, Line: fmt.Sprintf("the trackers of the pre-existing mark on %s at %s did "+
			"not read, so nothing shows the mark still holds: %s", bead, at, strings.Join(append(unread, closed...), "; ")),
			Warnings: warnings}
	}
	return Judgment{Answer: NoOpenTracker, Line: fmt.Sprintf("the pre-existing mark on %s at %s names no open "+
		"tracker, so it judges nothing: %s", bead, at, strings.Join(closed, "; ")), Warnings: warnings}
}

// Refusal is a mark the writer would not write, with what to do instead.
// Nothing was written.
type Refusal struct{ Reason string }

func (r *Refusal) Error() string { return r.Reason }

// MarkFail records on bead the judgment that the fail of check recorded at
// commit is pre-existing, carried by trackers, and returns the mark it wrote.
// commit must be co's HEAD, and the fail is the one Judge reads there. Every
// tracker named must itself be open, because a mark holds only while one is: a
// tracker that closed is refused with the bead its failure moved to, or with
// the advice to merge the base in when no open bead carries it. A mark of the
// same commit and fail already on the bead keeps its trackers beside these, and
// any other value is replaced, so a judgment never carries over to a run it did
// not see. The write is one update, whose exit decides whether it landed. A
// *Refusal says why nothing was written, and any other error is a read or a
// write that did not answer.
func MarkFail(l *ledger.Ledger, co *git.Checkout, bead, check, commit string, trackers []string) (*Mark, error) {
	if co.Commit != commit {
		return nil, &Refusal{fmt.Sprintf("the checkout is at %s, not at %s, so the fail it holds is not that "+
			"commit's, and nothing was written", co.Commit, commit)}
	}
	var fail json.RawMessage
	if validCheck(check) {
		rec, what, err := recordedFail(co, check)
		if err != nil {
			return nil, err
		}
		if rec == nil {
			return nil, &Refusal{what + ", so there is nothing to mark, and nothing was written"}
		}
		fail = rec
	}
	b, err := readBead(l, bead)
	if err != nil {
		return nil, fmt.Errorf("%s did not read, so nothing was written: %w", bead, err)
	}
	if fail == nil {
		note, what := notedFail(b, commit, check)
		if note == nil {
			return nil, &Refusal{what + ", so there is nothing to mark, and nothing was written"}
		}
		fail = note
	}
	var refused []string
	for _, t := range trackers {
		s := trackerNow(l, t)
		switch {
		case s.unread:
			return nil, fmt.Errorf("a mark holds only while a tracker it names is open, and %s, so nothing was "+
				"written", s.clause)
		case !s.open:
			refused = append(refused, s.clause)
		}
	}
	if len(refused) > 0 {
		return nil, &Refusal{"a mark holds only while a tracker it names is open, so nothing was written: " +
			strings.Join(refused, "; ")}
	}
	kept := slices.Clone(trackers)
	if old := markOf(b, check); old != nil && old.Commit == commit && sameJSON(old.Record, fail) {
		kept = append(kept, old.Trackers...)
	}
	slices.Sort(kept)
	m := &Mark{Commit: commit, Record: fail, Trackers: slices.Compact(kept)}
	w := l.Write(bead)
	markKeys[check].Set(w, m)
	if err := l.Commit(w); err != nil {
		return nil, fmt.Errorf("the mark on %s did not land: %w", bead, err)
	}
	return m, nil
}

// recordedFail is the record the record store holds for check at co's HEAD,
// as `gctk rig <check> --check` prints it, when it is a fail recorded there.
// Otherwise what says what is recorded.
func recordedFail(co *git.Checkout, check string) (rec json.RawMessage, what string, err error) {
	found, err := NewStore(co.Common).Lookup(check, co.Commit, co.Tree)
	if err != nil {
		return nil, "", fmt.Errorf("the record store did not read: %w", err)
	}
	r, _ := found.Recorded()
	switch {
	case r == nil:
		return nil, fmt.Sprintf("nothing is recorded for %s at %s", check, co.Commit), nil
	case r.Result != ResultFail || r.Commit != co.Commit:
		return nil, fmt.Sprintf("%s's record at %s is a %s", check, co.Commit, r.Result), nil
	}
	raw, err := json.Marshal(r)
	if err != nil {
		return nil, "", err
	}
	return raw, "", nil
}

// notedFail is b's self_review_setup_build note when it names commit and
// records check failed there. Otherwise what says what the note holds.
func notedFail(b *ledger.Record, commit, check string) (note json.RawMessage, what string) {
	raw, held, err := setupBuildKey.Get(b)
	var fields map[string]any
	if held && err == nil {
		_ = json.Unmarshal(raw, &fields)
	}
	if fields == nil || fields["commit"] != commit {
		return nil, fmt.Sprintf("%s notes no setup and build at %s", b.ID, commit)
	}
	if fields[check] != "fail" {
		outcome, _ := fields[check].(string)
		if outcome == "" {
			outcome = "nothing"
		}
		return nil, fmt.Sprintf("%s's note at %s records %s as %s", b.ID, commit, check, outcome)
	}
	return raw, ""
}

// markOf is b's mark of check, nil when it holds none. A value that does not
// decode is no judgment.
func markOf(b *ledger.Record, check string) *Mark {
	m, held, err := markKeys[check].Get(b)
	if !held || err != nil {
		return nil
	}
	return m
}

// readBead reads id's row, closed or not.
func readBead(l *ledger.Ledger, id string) (*ledger.Record, error) {
	recs, err := l.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, r := range recs {
		if r.ID == id {
			return r, nil
		}
	}
	return nil, fmt.Errorf("the store holds no bead %s", id)
}

// trackerState is what one tracker a mark names says now.
type trackerState struct {
	open, unread bool
	// clause says, for a tracker that is not open, why, and what to do instead.
	clause string
	// warning is why its chain ended with no bead, where the walk said why.
	warning string
}

// trackerNow reads what tracker t says now: open while it is itself open,
// and otherwise the bead its failure moved to, if any.
func trackerNow(l *ledger.Ledger, t string) trackerState {
	c, err := disposition.Carrier(l, t)
	switch {
	case err != nil:
		return trackerState{unread: true, clause: fmt.Sprintf("%s did not read (%v)", t, err)}
	case c.By == t:
		return trackerState{open: true}
	case c.By != "":
		return trackerState{clause: fmt.Sprintf("%s has closed, and %s carries its failure now, so mark the fail "+
			"against %s", t, c.By, c.By)}
	}
	return trackerState{clause: fmt.Sprintf("%s is not open and no open bead carries its failure, so merge the "+
		"base in", t), warning: c.Warning}
}

// sameJSON reports whether a and b are one JSON value, as jq's == compares two:
// objects by their keys and values whatever their order, and numbers by value.
func sameJSON(a, b json.RawMessage) bool {
	var x, y any
	if json.Unmarshal(a, &x) != nil || json.Unmarshal(b, &y) != nil {
		return false
	}
	return reflect.DeepEqual(x, y)
}
