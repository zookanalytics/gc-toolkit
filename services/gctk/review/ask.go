package review

import (
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
// names the PR's branch in `branch`, and carries no route and no assignee, so
// no pool claims it and the review run is the one that works it. Its
// description is its reason, a discovered-from edge names the bead it came
// from when it came from one, and review_checks names the checks it sends
// back. It has no parent, because an ask filed under the bead it blocks would
// read held through that bead for as long as it stays open.
//
// A run can take an ask only when nothing holds it, which `gctk bead holds`
// reads as clear. Every reader of an ask here applies that one test, so an ask
// that waits on other work is neither taken nor counted against a pass.

// Ask is one ask on a PR's bead as the store holds it. Holds is what
// `gctk bead holds` reads for an open ask, "" for a closed one.
type Ask struct {
	ID, Status, Reason, Source string
	Checks                     []string
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
	branch := view(record.Branch, owner)
	if branch == "" {
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
	rows, err := l.Find(ledger.ByID(ids...).WithClosed())
	if err != nil {
		return nil, err
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
			if e.Type == "discovered-from" {
				a.Source = e.ID
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

// isAsk reports whether r, a bead the PR's bead waits on, is an ask on the PR
// whose branch is branch: a task that names that branch, with no route and no
// assignee.
func isAsk(r *ledger.Record, branch string) bool {
	return r.IssueType() == "task" && view(record.Branch, r) == branch && r.Assignee() == "" && str(routedKey, r) == ""
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
// came from when it came from one, and the checks it sends back.
type AskRequest struct {
	Bead, Reason, Source string
	Checks               []string
}

// Refusal is an ask filing the review domain refuses, with why. Nothing was
// filed.
type Refusal struct{ Bead, Why string }

func (e *Refusal) Error() string { return "nothing filed on " + e.Bead + ": " + e.Why }

// FileAsk files the ask req names and returns its id, with filed false when an
// ask of the same source and reason already stands on the bead, open or
// closed, which it returns instead, so a filer that runs again after its ask
// closed files nothing. It refuses a bead that owns no PR on the record, and a
// check index names no check req sends back: the index at the head the
// refinery validated, which index reads. A read that fails returns its error
// with nothing filed, and a create that fails may still have filed the ask,
// which the next call finds.
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
	reason := strings.TrimSpace(req.Reason)
	asks, err := asksOf(l, owner)
	if err != nil {
		return "", false, err
	}
	for _, a := range asks {
		if a.Reason == reason && a.Source == req.Source {
			return a.ID, false, nil
		}
	}
	f := l.File(askTitle(reason), "task")
	f.Description(reason)
	record.NameBranch(f, branch)
	if len(checks) > 0 {
		checksKey.Set(f, strings.Join(checks, ","))
	}
	f.Blocks(owner.ID)
	if req.Source != "" {
		f.From(req.Source)
	}
	id, err = l.Create(f)
	if err != nil {
		return "", false, err
	}
	return id, true, nil
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
