package review

import (
	"errors"
	"fmt"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	armrecord "github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// A fix that lands ahead of a PR is work that a lane's rule keeps off the PR's
// branch, such as the architecture document the arch method finds missing. It
// lands in a PR of its own, and the PR waits for it. The round files it as a
// task bead of its own, which takes the PR's target and the priority of the
// PR's bead and goes to the repair pool at once. It then files an ask on the
// PR's bead that waits on the fix by the ask's own edge and sends the lane's
// checks back. The ask holds the PR's merge from the moment it is filed, and
// while the fix is open it counts for nothing, so it pours no run and fails no
// iteration. Once the fix closes, the landing order pours a run that takes the
// ask, and the checks it sends back judge the PR again.
//
// The fix is found by its title among the store's open beads, so a second PR
// whose lane asks for the same fix waits on the same bead, and that PR's case
// joins the bead's notes. A found fix that a label holds from every pool, such
// as the hold:mayor of work that waits for the operator's placement, is sent
// nowhere, because gc sling reads no hold, and the ask waits on it while the
// hold stands.

// AheadRequest is a fix to file ahead of the PR the bead owns: its title, what
// it must hold, the pool and the formula it is sent on, and the checks the ask
// sends back once it lands.
type AheadRequest struct {
	Bead, Title, Description string
	Pool, Formula            string
	Checks                   []string
}

// Ahead is what SendAhead did: the fix and the ask that waits on it, whether
// each was filed or found, whether this call sent the fix to the pool, and the
// label that holds a found fix from every pool, "" when none does.
type Ahead struct {
	Fix, Ask           string
	FixFiled, AskFiled bool
	Sent               bool
	Held               string
}

// SendAhead files the fix req names ahead of the PR the bead owns, or finds the
// open bead of its title, sends it to req.Pool on req.Formula unless it is on
// its way already or a label holds it, and files the ask on the bead that waits
// on it. It refuses what FileAsk refuses, and a request that sends no check
// back, before anything is filed. A read that fails returns its error. A write
// that fails returns its error with what landed before it, which the next call
// finds: the fix by its title, and the ask by its reason.
func SendAhead(l *ledger.Ledger, rt gascity.Runtime, req AheadRequest, index func(at string) (Index, error)) (Ahead, error) {
	var out Ahead
	title, desc := strings.TrimSpace(req.Title), strings.TrimSpace(req.Description)
	if title == "" || desc == "" || strings.TrimSpace(req.Pool) == "" || strings.TrimSpace(req.Formula) == "" {
		return out, errors.New("a fix ahead of a PR names its title, what it must hold, its pool and its formula")
	}
	if len(req.Checks) == 0 {
		return out, &Refusal{Bead: req.Bead, Why: "the fix sends no check back, so nothing would judge the PR once it lands"}
	}
	owner, rec, branch, err := askable(l, req.Bead)
	if err != nil {
		return out, err
	}
	checks, err := askChecks(req.Bead, rec.Head, req.Checks, index)
	if err != nil {
		return out, err
	}
	pr := owner.ID + "'s PR"
	if rec.URL != "" {
		pr += " " + rec.URL
	}
	mark := "Ahead of " + owner.ID + "'s PR"
	fix, err := openTitled(l, title, owner.ID)
	if err != nil {
		return out, err
	}
	if fix == nil {
		f := l.File(title, "task")
		f.Description(desc + "\n\nAhead of " + pr + ": its review run waits for this to land.")
		f.Priority(owner.Priority())
		if rec.Target != "" {
			record.NameTarget(f, rec.Target)
		}
		f.From(owner.ID)
		id, err := l.Create(f)
		if err != nil {
			return out, fmt.Errorf("the fix did not file, and the next call finds one that landed: %w", err)
		}
		out.Fix, out.FixFiled = id, true
	} else {
		out.Fix, out.Held = fix.ID, arm.HoldLabel(fix)
		if !strings.Contains(fix.Description()+"\n"+fix.Notes(), mark) {
			w := l.Write(fix.ID)
			w.Note("Ahead of " + pr + " as well: its review run waits for this to land.\n\n" + desc)
			if err := l.Commit(w); err != nil {
				return out, fmt.Errorf("%s carries the fix, and %s's case did not join its notes: %w", fix.ID, owner.ID, err)
			}
		}
	}
	if out.FixFiled || (out.Held == "" && unsent(fix)) {
		res := rt.Sling(gascity.Sling{Target: req.Pool, Bead: out.Fix, Formula: req.Formula})
		switch {
		case res.Code == 0 && res.Err == nil:
			out.Sent = true
		case res.Code == 3 && len(res.Live) > 0:
		default:
			why := fmt.Sprintf("exit %d: %s", res.Code, oneLine(res.Output))
			if res.Err != nil {
				why = res.Err.Error()
			}
			return out, fmt.Errorf("%s carries the fix, and its sling to %s did not land, so the next call sends it: %s", out.Fix, req.Pool, why)
		}
	}
	reason := fmt.Sprintf("Run %s again once %s lands ahead of this PR: %s", strings.Join(checks, ", "), out.Fix, title)
	out.Ask, out.AskFiled, err = fileAsk(l, owner, branch, reason, "", checks, []string{out.Fix})
	if err != nil {
		return out, fmt.Errorf("%s carries the fix, and the ask that holds the PR for it did not file: %w", out.Fix, err)
	}
	return out, nil
}

// openTitled is the open bead titled title, other than the bead not, the one
// of lowest id when several are, and nil when none is.
func openTitled(l *ledger.Ledger, title, not string) (*ledger.Record, error) {
	rows, err := l.Find(ledger.Titled(title))
	if err != nil {
		return nil, err
	}
	var found *ledger.Record
	for _, r := range rows {
		if strings.TrimSpace(r.Title()) != title || r.Status() == "closed" || r.ID == not {
			continue
		}
		if found == nil || r.ID < found.ID {
			found = r
		}
	}
	return found, nil
}

// unsent reports whether r, a fix found by its title, is on no way to a pool:
// open, assigned to nobody, routed nowhere, armed for nothing, and naming no
// branch its work is on.
func unsent(r *ledger.Record) bool {
	return r != nil && r.Status() == "open" && r.Assignee() == "" && str(routedKey, r) == "" &&
		str(executionRoutedKey, r) == "" && !armrecord.Present(r) && view(record.Branch, r) == ""
}
