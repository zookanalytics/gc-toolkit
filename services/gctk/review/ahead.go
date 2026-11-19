package review

import (
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

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
// PR's bead. It then files an ask on the PR's bead that waits on the fix by the
// ask's own edge and sends the lane's checks back, and only then sends the fix
// to the repair pool, so no fix the call sends can land before the ask that
// waits on it stands. The ask holds the PR's merge from the moment it is filed,
// and while the fix is open it counts for nothing, so it pours no run and fails
// no iteration. Once the fix closes, the landing order pours a run that takes
// the ask, and the checks it sends back judge the PR again.
//
// The fix is found by its title and its target among the store's open beads,
// so a second PR into the same branch whose lane asks for the same fix waits on
// the same bead, and that PR's case joins the bead's notes. A fix lands only on
// its target, so a PR into another branch gets a fix of its own. A bead that
// waits on the PR's bead, as a fix deferred behind the PR does, cannot also land
// ahead of the PR, so the call passes it over. A call that
// runs again for the same PR finds first the fix of that title and target that
// its open ask waits on, closed or not, so a fix that landed before the call ran
// again is not filed and sent a second time. A fix another PR's run sent can
// still land before this PR's ask on it files, when that create fails, and the
// call that runs again then files the fix anew. Each call holds the store's
// record lock from its first read of the fix to the fix's filing, so two review
// runs that ask for one fix at once file it once. A found fix that a label
// holds from every pool, such as the hold:mayor of work that waits for the
// operator's placement, is sent nowhere, because gc sling reads no hold, and
// the ask waits on it while the hold stands.

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
// open bead of its title that lands on the PR's target and does not wait on the
// bead, files the ask on the bead that waits on it, and then sends it to
// req.Pool on req.Formula unless it
// is on its way already or a label holds it. It finds or files the fix under
// the record lock of the store whose .beads directory is dir, waiting up to
// wait for it. It refuses what FileAsk refuses, and a request that sends no
// check back, before anything is filed. A read that fails, and a lock not
// taken, return their error. A write that fails returns its error with what
// landed before it, which the next call finds: the fix through the open ask
// that waits on it, or by its title and target while it is open, and the ask
// by its reason.
func SendAhead(l *ledger.Ledger, dir string, wait time.Duration, rt gascity.Runtime, req AheadRequest, index func(at string) (Index, error)) (Ahead, error) {
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
	fix, err := fixFor(l, dir, wait, owner, rec, title, desc, pr, &out)
	if err != nil {
		return out, err
	}
	reason := fmt.Sprintf("Run %s again once %s lands ahead of this PR: %s", strings.Join(checks, ", "), out.Fix, title)
	out.Ask, out.AskFiled, err = fileAsk(l, owner, branch, reason, "", checks, []string{out.Fix})
	if err != nil {
		return out, fmt.Errorf("%s carries the fix, and the ask that holds the PR for it did not file: %w", out.Fix, err)
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
	return out, nil
}

// fixFor finds or files the fix SendAhead sends, holding the store's record
// lock from its first read of the fix to the fix's create, so two review runs
// that ask for one fix at once file it once: the fix of its title and the PR's
// target that an open ask on the PR waits on, else the open bead of that title
// and target that does not wait on owner, whose notes take the PR's case, else
// a new bead. It fills in out's
// fix, and returns the found fix's record, nil for a fix it filed.
func fixFor(l *ledger.Ledger, dir string, wait time.Duration, owner *ledger.Record, rec record.Record, title, desc, pr string, out *Ahead) (*ledger.Record, error) {
	release, err := record.Lock(dir, wait)
	if err != nil {
		return nil, err
	}
	defer release()
	fix, err := sentFix(l, owner, title, rec.Target)
	if err != nil {
		return nil, err
	}
	if fix == nil {
		if fix, err = openFix(l, title, rec.Target, owner.ID); err != nil {
			return nil, err
		}
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
			return nil, fmt.Errorf("the fix did not file, and the next call finds one that landed: %w", err)
		}
		out.Fix, out.FixFiled = id, true
		return nil, nil
	}
	out.Fix, out.Held = fix.ID, arm.HoldLabel(fix)
	if mark := "Ahead of " + owner.ID + "'s PR"; !strings.Contains(fix.Description()+"\n"+fix.Notes(), mark) {
		w := l.Write(fix.ID)
		w.Note("Ahead of " + pr + " as well: its review run waits for this to land.\n\n" + desc)
		if err := l.Commit(w); err != nil {
			return nil, fmt.Errorf("%s carries the fix, and %s's case did not join its notes: %w", fix.ID, owner.ID, err)
		}
	}
	return fix, nil
}

// sentFix is the fix of title that lands on target and that an open ask on
// owner's PR waits on, closed or not, the one of lowest id when several are, and
// nil when no open ask waits on one. The ask waits on its fix by its own blocks
// edge, so the ask still names the fix after the fix has closed, where openFix
// sees only open beads.
func sentFix(l *ledger.Ledger, owner *ledger.Record, title, target string) (*ledger.Record, error) {
	asks, err := asksOf(l, owner)
	if err != nil {
		return nil, err
	}
	var open []string
	for _, a := range asks {
		if a.Open() {
			open = append(open, a.ID)
		}
	}
	if len(open) == 0 {
		return nil, nil
	}
	rows, err := l.Find(ledger.ByID(open...))
	if err != nil {
		return nil, err
	}
	var waited []string
	for _, r := range rows {
		edges, err := r.Edges()
		if err != nil {
			return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
		}
		for _, e := range edges {
			if e.Type == ledger.EdgeBlocks && e.ID != owner.ID && !slices.Contains(waited, e.ID) {
				waited = append(waited, e.ID)
			}
		}
	}
	if len(waited) == 0 {
		return nil, nil
	}
	fixes, err := l.Find(ledger.ByID(waited...).WithClosed())
	if err != nil {
		return nil, err
	}
	var found *ledger.Record
	for _, r := range fixes {
		if !fixOf(r, title, target) {
			continue
		}
		if found == nil || r.ID < found.ID {
			found = r
		}
	}
	return found, nil
}

// openFix is the open bead of title that lands on target, other than owner, that
// does not wait on owner, the one of lowest id when several are, and nil when
// none is.
func openFix(l *ledger.Ledger, title, target, owner string) (*ledger.Record, error) {
	rows, err := l.Find(ledger.Titled(title))
	if err != nil {
		return nil, err
	}
	rows = slices.DeleteFunc(rows, func(r *ledger.Record) bool {
		return !fixOf(r, title, target) || r.Status() == "closed" || r.ID == owner
	})
	slices.SortFunc(rows, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, r := range rows {
		waits, err := waitsOn(l, r, owner)
		if err != nil {
			return nil, err
		}
		if !waits {
			return r, nil
		}
	}
	return nil, nil
}

// waitsOn reports whether r waits on the bead id names, by an edge of its own or
// through the beads it waits on, closed ones included, over the edges bd's cycle
// check follows: blocks, conditional-blocks and parent-child
// (cycleReachabilityQuery in internal/storage/issueops/dependencies.go, beads
// v1.3.4). An ask on that bead that waited on r would close a cycle, and bd
// refuses its create.
func waitsOn(l *ledger.Ledger, r *ledger.Record, id string) (bool, error) {
	seen := map[string]bool{r.ID: true}
	for next := []*ledger.Record{r}; len(next) > 0; {
		var far []string
		for _, n := range next {
			edges, err := n.Edges()
			if err != nil {
				return false, &ledger.ReadError{ID: n.ID, Reason: "its edges did not decode: " + err.Error()}
			}
			for _, e := range edges {
				switch {
				case e.Type != ledger.EdgeBlocks && e.Type != ledger.EdgeConditionalBlocks && e.Type != ledger.EdgeParentChild:
				case e.ID == id:
					return true, nil
				case !seen[e.ID]:
					seen[e.ID] = true
					far = append(far, e.ID)
				}
			}
		}
		var err error
		if next, err = l.Find(ledger.ByID(far...).WithClosed()); err != nil {
			return false, err
		}
	}
	return false, nil
}

// fixOf reports whether r is the fix of title that lands on target. A fix lands
// only on its target, so one on another branch leaves the PR's target without
// what the PR waits for.
func fixOf(r *ledger.Record, title, target string) bool {
	return strings.TrimSpace(r.Title()) == title && view(record.LandsOn, r) == target
}

// unsent reports whether r, a found fix, is on no way to a pool: open,
// assigned to nobody, routed nowhere, armed for nothing, and naming no branch
// its work is on.
func unsent(r *ledger.Record) bool {
	return r != nil && r.Status() == "open" && r.Assignee() == "" && str(routedKey, r) == "" &&
		str(executionRoutedKey, r) == "" && !armrecord.Present(r) && view(record.Branch, r) == ""
}
