package review

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// An ask is a request for a change on a PR's branch, or for a check at its next
// head: a task bead that blocks the bead that owns the PR by its own edge,
// names the PR's branch in `branch`, and carries no assignee, no route and no
// role, so no pool claims it and the review run is the one that works it. The
// route is either of Gas City's, gc.routed_to, which a pool claims by, and
// gc.execution_routed_to, which its sling stamps on a work bead whose workflow
// it started and which stays while that bead is unassigned and its steps are
// claimed. The role is task_kind, which a rework child carries and an ask never
// does. refinery-lib.sh's refinery_ask applies the same rule to the beads the
// refinery reads, and a test runs that definition over the beads this one
// classifies. An ask's description is its reason, a discovered-from edge names
// the bead it came from when it came from one, review_checks names the checks
// it sends back, and its own blocks edges name the beads it waits on. It has no
// parent, because an ask filed under the bead it blocks would read held through
// that bead for as long as it stays open.
//
// A run can take an ask only when nothing holds it, which `gctk bead holds`
// reads as clear. Every reader of an ask here applies that one test, so an ask
// that waits on other work is neither taken nor counted against a pass.

// Ask is one ask on a PR's bead as the store holds it. WaitingOn is each bead
// its own blocks edges name, open or closed, and Holds is what
// `gctk bead holds` reads for an open ask, "" for a closed one.
type Ask struct {
	ID, Status, Reason, Source string
	Checks, WaitingOn          []string
	Holds                      waits.Status
}

// Open reports whether the ask is still to be answered.
func (a Ask) Open() bool { return a.Status != "closed" }

// Takeable reports whether a run can take the ask: it is open and nothing
// holds it.
func (a Ask) Takeable() bool { return a.Open() && a.Holds == waits.Clear }

// AsksOn reads every ask on the bead that owns a PR, open or closed, in id
// order, and what holds each open one. A read that fails returns its error.
func AsksOn(l *ledger.Ledger, bead string) ([]Ask, error) {
	owner, err := one(l, bead)
	if err != nil {
		return nil, err
	}
	return asksOf(l, owner)
}

func asksOf(l *ledger.Ledger, owner *ledger.Record) ([]Ask, error) {
	if view(record.Branch, owner) == "" {
		return nil, nil
	}
	edges, err := owner.Edges()
	if err != nil {
		return nil, &ledger.ReadError{ID: owner.ID, Reason: "its edges did not decode: " + err.Error()}
	}
	var ids []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks && !slices.Contains(ids, e.ID) {
			ids = append(ids, e.ID)
		}
	}
	if len(ids) == 0 {
		return nil, nil
	}
	rows, err := l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
	}
	return AsksIn(l, owner, rows)
}

// AsksIn is every ask among rows, the beads the bead that owns a PR waits on
// through its blocks edges, open or closed, as a caller that already read them
// holds them, in id order, with what holds each open one. A read that fails
// returns its error.
func AsksIn(l *ledger.Ledger, owner *ledger.Record, rows []*ledger.Record) ([]Ask, error) {
	branch := view(record.Branch, owner)
	if branch == "" {
		return nil, nil
	}
	var asks []Ask
	var open []string
	for _, r := range rows {
		if !isAsk(r, branch) {
			continue
		}
		a := Ask{ID: r.ID, Status: r.Status(), Reason: strings.TrimSpace(r.Description())}
		redges, err := r.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		for _, e := range redges {
			switch e.Type {
			case "discovered-from":
				a.Source = e.ID
			case ledger.EdgeBlocks:
				a.WaitingOn = append(a.WaitingOn, e.ID)
			}
		}
		a.Checks = splitChecks(str(checksKey, r))
		asks = append(asks, a)
		if a.Open() {
			open = append(open, a.ID)
		}
	}
	if len(open) > 0 {
		snap, err := waits.Read(l, open...)
		if err != nil {
			return nil, err
		}
		for i := range asks {
			if !asks[i].Open() {
				continue
			}
			h, err := snap.Holds(asks[i].ID)
			if err != nil {
				return nil, err
			}
			asks[i].Holds = h.Status
		}
	}
	slices.SortFunc(asks, func(a, b Ask) int { return strings.Compare(a.ID, b.ID) })
	return asks, nil
}

// IsAsk reports whether r, a bead that names a PR's branch, is an ask on that
// PR: a task that names the branch, with no assignee, no route and no role. A
// bead of another shape that names the branch is work of its own on it.
func IsAsk(r *ledger.Record, branch string) bool { return isAsk(r, branch) }

// isAsk reports whether r, a bead the PR's bead waits on, is an ask on the PR
// whose branch is branch: a task that names that branch, with no assignee, no
// route of either kind and no role.
func isAsk(r *ledger.Record, branch string) bool {
	return r.IssueType() == "task" && view(record.Branch, r) == branch && r.Assignee() == "" &&
		str(routedKey, r) == "" && str(executionRoutedKey, r) == "" && str(roleKey, r) == ""
}

// splitChecks reads a comma list of check names, each once and in order.
func splitChecks(list string) []string {
	var out []string
	for _, c := range strings.Split(list, ",") {
		if c = strings.TrimSpace(c); c != "" && !slices.ContainsFunc(out, func(o string) bool { return strings.EqualFold(o, c) }) {
			out = append(out, c)
		}
	}
	return out
}

// AskRequest is an ask to file on the bead that owns a PR: why, the bead it
// came from when it came from one, the checks it sends back, and the beads it
// waits on, which no run takes it before.
type AskRequest struct {
	Bead, Reason, Source string
	Checks, WaitingOn    []string
}

// Refusal is an ask filing the review domain refuses, with why. Nothing was
// filed.
type Refusal struct{ Bead, Why string }

func (e *Refusal) Error() string { return "nothing filed on " + e.Bead + ": " + e.Why }

// FileAsk files the ask req names and returns its id, with filed false when an
// ask of the same source and reason already stands on the bead, open or
// closed, which it returns instead, so a filer that runs again after its ask
// closed files nothing. The ask waits on each bead req names by its own blocks
// edge, written in the create that files it, so no landing pass reads the ask
// clear before it waits.
//
// It refuses a bead that owns no PR on the record, and a check req sends back
// that the check index does not declare at the head the refinery validated,
// which index reads. It refuses to return an ask it finds that does not wait on
// every bead req names, because a run can take that ask before they close, or
// already has. The ledger refuses the ask's create when its edge onto the bead,
// or onto a bead it waits on, would hold nothing, as it refuses every such wait
// edge (ledger.NotHeld), and FileAsk returns that refusal as its own. A refusal
// files nothing. A read that fails returns its error with nothing filed, and a
// create that fails may still have filed the ask, which the next call finds.
func FileAsk(l *ledger.Ledger, req AskRequest, index func(at string) (Index, error)) (id string, filed bool, err error) {
	owner, err := one(l, req.Bead)
	if err != nil {
		return "", false, err
	}
	rec, err := record.Read(owner)
	if err != nil {
		return "", false, err
	}
	branch := view(record.Branch, owner)
	switch {
	case owner.Status() == "closed":
		return "", false, &Refusal{Bead: req.Bead, Why: "it is closed"}
	case !record.OnRecord(rec.Result):
		return "", false, &Refusal{Bead: req.Bead, Why: fmt.Sprintf("it owns no PR on the record (merge_result reads %q)", rec.Result)}
	case branch == "":
		return "", false, &Refusal{Bead: req.Bead, Why: "it names no branch for an ask to name"}
	}
	var checks []string
	if len(req.Checks) > 0 {
		ix, err := index(rec.Head)
		if err != nil {
			return "", false, err
		}
		for _, name := range req.Checks {
			c, ok := ix.Lookup(name)
			if !ok {
				return "", false, &Refusal{Bead: req.Bead, Why: fmt.Sprintf("the check index at %s declares no check %q", rec.Head, name)}
			}
			if !slices.Contains(checks, c.Name) {
				checks = append(checks, c.Name)
			}
		}
	}
	waits := waitsOf(req)
	reason := strings.TrimSpace(req.Reason)
	asks, err := asksOf(l, owner)
	if err != nil {
		return "", false, err
	}
	for _, a := range asks {
		if a.Reason != reason || a.Source != req.Source {
			continue
		}
		var lacks []string
		for _, w := range waits {
			if !slices.Contains(a.WaitingOn, w) {
				lacks = append(lacks, w)
			}
		}
		if len(lacks) > 0 {
			why := fmt.Sprintf("ask %s of the same source and reason is open and does not wait on %s, so a run can take it before that work lands",
				a.ID, strings.Join(lacks, " or "))
			if !a.Open() {
				why = fmt.Sprintf("ask %s of the same source and reason closed without waiting on %s, so a run may have worked it before that work landed",
					a.ID, strings.Join(lacks, " or "))
			}
			return "", false, &Refusal{Bead: req.Bead, Why: why}
		}
		return a.ID, false, nil
	}
	f := l.File(askTitle(reason), "task")
	f.Description(reason)
	record.NameBranch(f, branch)
	if len(checks) > 0 {
		checksKey.Set(f, strings.Join(checks, ","))
	}
	f.Blocks(owner.ID)
	f.BlockedBy(waits...)
	if req.Source != "" {
		f.From(req.Source)
	}
	id, err = l.Create(f)
	var refused *ledger.NotHeld
	if errors.As(err, &refused) {
		return "", false, &Refusal{Bead: req.Bead, Why: refused.Error()}
	}
	if err != nil {
		return "", false, err
	}
	return id, true, nil
}

// waitsOf is each bead req names for the ask to wait on, once each and in the
// order named.
func waitsOf(req AskRequest) []string {
	var waits []string
	for _, w := range req.WaitingOn {
		if w = strings.TrimSpace(w); w != "" && !slices.Contains(waits, w) {
			waits = append(waits, w)
		}
	}
	return waits
}

// askTitle is an ask's title: its reason's first line, cut to fit a listing.
func askTitle(reason string) string {
	line, _, _ := strings.Cut(reason, "\n")
	line = strings.TrimSpace(line)
	const most = 100
	if utf8.RuneCountInString(line) > most {
		line = string([]rune(line)[:most-1]) + "…"
	}
	return "Review ask: " + line
}
