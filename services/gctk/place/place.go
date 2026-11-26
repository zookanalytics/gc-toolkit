// Package place is a placement: a bead held for placement, which carries Gas
// City's hold:mayor label, given its parent or none, its dispatch, and then the
// lift of its hold (docs/steering.md, "Placing a bead"). `gctk bead place`
// makes it. gc sling reads no hold, so a sling leaves the label on, and no
// native write both dispatches a bead and lifts its hold. So a placement makes
// the native writes in one order, each taking its exit, and a run again after
// a stop at any write finishes the placement:
//
//  1. It reads the bead, its parent and the runs that work it, and refuses
//     what it does not place with nothing written. A bead with no hold:mayor
//     that a live run, a route, an arm or an assignee shows dispatched is
//     placed already. It holds the bead's acceptance lock from this read to
//     its last write (reaction.LockBead), as a first reaction's exit does, so
//     the exit never releases a bead this placement is sending on.
//  2. It clears a route, which gctk bead arm refuses. With a parent it removes
//     a relates-to link between the bead and the parent, since bd refuses a
//     parent-child edge beside one, sets the parent, and moves the shift
//     through queue-priority.sh move.
//  3. It settles the bead's priority (queue-priority.sh settle), because a
//     pour copies the priority once.
//  4. It dispatches, unless an assignee, a merge_result, a live run or an arm
//     shows that an earlier dispatch did. A run of mol-first-reaction shows
//     none, since a first reaction triages the bead and works none of it, and
//     its exit lands only its headline on a bead sent on while it ran. A bead a
//     wait holds, its own or a parent's above it such as a park, is
//     armed, so the wait keeps holding it, and so is one whose holds could not
//     be read. Any other is slung, and gc sling's exit 3 says a live run of the
//     formula already works the bead.
//  5. It lifts the hold with its note in one write.
//
// The dispatch comes before the lift, so a dispatch that fails leaves the bead
// held and in the queue. A run cut off between the two goes on with the hold on
// its bead, and the next placement finishes the lift without a second run while
// that run is live, or once it has claimed, landed or closed the bead. gc sling
// refuses only a second live run, so a run that ends with none of those leaves
// nothing a placement reads as the dispatch, and a stop at the lift names the
// lift by hand, which dispatches nothing.
//
// It asks waits what holds the bead and which runs work it, the arm to arm one
// and the arm's record whether one is armed, the pr record whether it carries a
// merge_result, and the runtime for the rig's polecat pool, the sling, and the
// pack's priority writer, queue-priority.sh. No domain asks it.
package place

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	prrecord "github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	rx "github.com/zookanalytics/gc-toolkit/services/gctk/reaction"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The keys a placement reads and does not write. No domain owns them: the
// route is the runtime's, which the ledger's Unroute clears, and shell writes
// the anchor.
var (
	routedToKey = ledger.ReadOnly("gc.routed_to", ledger.String,
		"A placement clears the route of a held bead, which gctk bead arm refuses, before it dispatches it.")
	anchorKey = ledger.ReadOnly("anchor_bead", ledger.String,
		"A placement refuses PR-finishing work, which follows its anchor and is never a member of an epic.")
)

// hold is the hold a placement lifts: Gas City's hold for a bead whose next
// actor is the coordinator, which intake holds new work with.
const hold = "hold:mayor"

// reaction is the formula of a first reaction, whose run is no dispatch.
const reaction = "mol-first-reaction"

// closer is the formula of a validating closer, whose arm is a wait on another
// bead rather than work to place.
const closer = "mol-validate-close"

// Places is the placement's verb over one store: its ledger, the Gas City it
// slings through and asks for the pack's scripts, the arm it arms through, the
// bead's rig, which a sling runs under and whose polecat pool a placement
// with no route sends to, the store, a store's .beads directory, which the
// priority writer and a remedy name, the clock a note's time is read from, and
// where the lines it says as it goes are written.
type Places struct {
	Ledger  *ledger.Ledger
	Runtime gascity.Runtime
	// Arm arms a bead, as gctk bead arm does.
	Arm func(arm.Request) (string, error)
	Rig string
	DB  string
	Now func() time.Time
	Log func(string)
}

// Request is one placement: the bead, the parent it goes under with the shift
// that ranks it against that parent, or no parent at all, and the pool and
// formula it is sent to, empty for the rig's polecat pool and its default.
type Request struct {
	Bead, Under, Shift, Route, Formula string
	Standalone                         bool
}

// Placed is what a placement did: whether the bead was placed already, with
// nothing written, and in a sentence how it was dispatched, with the priority
// it settled at.
type Placed struct {
	Already  bool
	How      string
	Priority string
}

// Refusal is a placement refused for what it asks or for what the bead is,
// before anything is written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error {
	return &Refusal{Msg: fmt.Sprintf(format, args...)}
}

// Refused reports whether err is a placement refused with nothing written,
// rather than a read, a write or a dispatch that failed.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

// shiftForm is the shape of a shift: a signed whole number.
var shiftForm = regexp.MustCompile(`^[+-]?[0-9]+$`)

// Validate refuses a call for what it asks, before anything is read.
func Validate(req Request) error {
	switch {
	case req.Bead == "":
		return refuse("place needs <bead-id>")
	case req.Under != "" && req.Standalone:
		return refuse("--under and --standalone are the two placements, and a bead takes one: a member under its parent, or a bead that follows nothing. Pass one. Nothing was written")
	case req.Under == "" && !req.Standalone:
		return refuse("place needs --under <parent>, to place %s as a member of an epic or a Delivery, or --standalone, to place it with no parent. Nothing was written", req.Bead)
	case req.Shift != "" && req.Under == "":
		return refuse("--shift ranks a member against its parent, and --standalone gives %s none, so it keeps its own priority. Nothing was written", req.Bead)
	case req.Shift != "" && !shiftForm.MatchString(req.Shift):
		return refuse("--shift %q is not a signed integer, such as +1 or -1. Nothing was written", req.Shift)
	case req.Route != "" && !strings.Contains(req.Route, "/"):
		return refuse("--route %q is not rig-qualified; a pool's queue is matched by its exact <rig>/<pool> name, so a bare one reaches nobody. Nothing was written", req.Route)
	case req.Under == req.Bead:
		return refuse("%s cannot be its own parent. Nothing was written", req.Bead)
	}
	return nil
}

// Command is the placement as a command line, for a message that names a run
// again.
func (req Request) Command() string {
	s := "gctk bead place " + req.Bead
	if req.Under != "" {
		s += " --under " + req.Under
	}
	if req.Standalone {
		s += " --standalone"
	}
	if req.Shift != "" {
		s += " --shift " + req.Shift
	}
	if req.Route != "" {
		s += " --route " + req.Route
	}
	if req.Formula != "" {
		s += " --on " + req.Formula
	}
	return s
}

func (p *Places) say(format string, args ...any) {
	if p.Log != nil {
		p.Log(fmt.Sprintf(format, args...))
	}
}

// Place places the bead, its five steps in their order.
func (p *Places) Place(req Request) (Placed, error) {
	var out Placed
	if err := Validate(req); err != nil {
		return out, err
	}
	again := req.Command()
	if p.DB != "" {
		again += " --db " + p.DB
	}

	release, holder, err := rx.LockBead(p.Runtime, req.Bead)
	switch {
	case err != nil:
		return out, fmt.Errorf("could not take %s's acceptance lock (%v), which a placement holds so that a first reaction's exit cannot release %s while it is sent on. Nothing was written", req.Bead, err, req.Bead)
	case release == nil:
		return out, refuse("an Accept, a placement or a first reaction's exit on %s holds its acceptance lock (%s), so this placement writes nothing. Place it again once that one has finished: %s", req.Bead, holder, again)
	}
	defer release()

	// Step 1: read, and refuse what a placement does not place.
	row, err := p.read(req.Bead)
	switch {
	case err != nil:
		return out, fmt.Errorf("could not read %s (%v). Nothing was written", req.Bead, err)
	case row == nil:
		return out, fmt.Errorf("%s does not resolve in rig %s. Nothing was written", req.Bead, p.Rig)
	case row.Status() == "closed":
		return out, refuse("%s is closed, so it has no work to place. Nothing was written", req.Bead)
	}
	if a := value(anchorKey, row); a != "" {
		return out, refuse("%s is PR-finishing work of %s (anchor_bead), which follows its anchor and is never a member of an epic. Nothing was written", req.Bead, a)
	}
	runs, err := waits.RunsOf(p.Ledger, req.Bead)
	if err != nil {
		return out, fmt.Errorf("could not read the runs that work %s (%v), so whether an earlier dispatch already started one cannot be told. Re-run once the store answers. Nothing was written", req.Bead, err)
	}
	var shown []string
	if a := row.Assignee(); a != "" {
		shown = append(shown, "assigned to "+a)
	}
	if m, _, _ := prrecord.Result.Get(row); strings.TrimSpace(m) != "" {
		shown = append(shown, "merge_result="+m)
	}
	var live []string
	for _, r := range runs {
		if r.Live && r.Formula != reaction {
			live = append(live, r.Root)
		}
	}
	if len(live) > 0 {
		shown = append(shown, "live run "+strings.Join(live, " "))
	}
	spellings := gascity.Spellings(row.Labels(), hold)
	armed := record.Of(row)
	if armed != nil && strings.TrimSpace(armed.Target) == "" {
		armed = nil
	}
	if len(spellings) == 0 {
		if r := value(routedToKey, row); r != "" {
			shown = append(shown, "routed to "+r)
		}
		if armed != nil {
			shown = append(shown, "armed for "+armed.Target)
		}
		if len(shown) > 0 {
			out.Already, out.How = true, strings.Join(shown, ", ")
			return out, nil
		}
		return out, refuse("%s carries no hold:mayor, so it is not in the placement queue, and nothing shows that it was dispatched. Hold it first, then place it: gc bd set-state %s hold=mayor --reason \"<why it waits for placement>\". Nothing was written", req.Bead, req.Bead)
	}
	for _, l := range row.Labels() {
		if gascity.IsDispatchHold(l) && !slices.Contains(spellings, l) {
			return out, refuse("%s also carries %s, Gas City's hold for a next actor outside this city, and a placement lifts only hold:mayor. Place it once that hold is lifted. Nothing was written", req.Bead, strings.TrimSpace(l))
		}
	}
	dispatched := strings.Join(shown, ", ")
	if st := row.Status(); st != "open" && dispatched == "" {
		return out, refuse("%s is %s, a status set on purpose, and a placement dispatches only an open bead. Return it to open, then place it. Nothing was written", req.Bead, st)
	}
	parents, err := row.Parents()
	if err != nil {
		return out, fmt.Errorf("%s's edges did not decode (%v). Nothing was written", req.Bead, err)
	}
	parent := ""
	if len(parents) > 0 {
		parent = parents[0]
	}
	if req.Standalone && parent != "" {
		return out, refuse("--standalone places %s with no parent, and it has one, %s. Place it under that parent with --under %s, or remove the parent first: gc bd update %s%s --parent \"\". Nothing was written", req.Bead, parent, parent, req.Bead, p.dbFlag())
	}
	if req.Under != "" {
		up, err := p.read(req.Under)
		switch {
		case err != nil:
			return out, fmt.Errorf("could not read --under %s (%v). Nothing was written", req.Under, err)
		case up == nil:
			return out, fmt.Errorf("--under %s does not resolve in rig %s, the store that holds %s, and bd links a parent only within one store. Nothing was written", req.Under, p.Rig, req.Bead)
		case up.Status() == "closed":
			return out, refuse("%s is closed, and a member of a closed epic follows nothing, so its state would never decide when %s runs. Nothing was written", req.Under, req.Bead)
		}
	}
	pool := req.Route
	if pool == "" {
		if pool, err = p.polecatPool(); err != nil {
			return out, fmt.Errorf("could not name the polecat pool of rig %s (%v), so %s has nowhere to go. Name its pool with --route <rig>/<pool>. Nothing was written", p.Rig, err, req.Bead)
		}
	}
	// An arm the bead already carries is a dispatch already made, such as the
	// one an earlier placement wrote before it stopped short of its lift. The
	// deferred-dispatch pass slings it once nothing holds the bead, so a second
	// dispatch beside it would start a second run when it fires. A placement
	// keeps an arm that sends the bead where it would, and refuses one that
	// sends it to another pool or on another formula. The arm verb judges an
	// arm for this pool that names another formula, since an arm that names
	// none pours the pool's default: on an armed bead it writes nothing, and
	// succeeds only when the two pour the same formula. An arm whose stored
	// record does not decode reads as naming no formula, and the start slings no
	// such arm, so it goes to the arm verb too, which refuses it. An arm for the
	// validating closer is a wait on another bead, which the closer checks once
	// that bead lands, so its refusal names the lift that lets the closer run.
	var keptArm *record.Arm
	if dispatched == "" && armed != nil {
		same := armed.Malformed() == "" && armed.Target == pool && armed.Formula() == req.Formula
		said := ""
		if !same && armed.Target == pool {
			if _, err := p.Arm(arm.Request{ID: req.Bead, Target: pool, Formula: req.Formula, Reason: "placed" + under(req)}); err == nil {
				same = true
			} else {
				said = strings.TrimPrefix(err.Error(), "refused: ")
			}
		}
		if !same {
			if armed.Formula() == closer {
				return out, refuse("%s is armed for its validating closer (%s) on %s: it waits on another bead to land and is checked then, so it is not new work to place. Lift its hold and keep the arm: %s. To place it as work instead, disarm it, then run again: %s && %s. Nothing was written",
					req.Bead, closer, armed.Target, liftCommand(req.Bead, spellings, "", p.dbFlag()), disarmCommand(req.Bead, "placed as work instead of waiting for its validating closer", p.dbFlag()), again)
			}
			why := ""
			if said != "" {
				why = " (" + said + ")"
			}
			return out, refuse("%s is already armed for %s on %s, and this placement would send it to %s%s%s. Disarm it, then run again: %s && %s. Nothing was written",
				req.Bead, armed.Target, nonEmpty(armed.Formula(), "its default formula"), pool, onFormula(req.Formula), why, disarmCommand(req.Bead, "placed to "+pool+onFormula(req.Formula), p.dbFlag()), again)
		}
		keptArm = armed
	}

	// Step 2: clear the route, then give the bead its parent and its shift.
	if dispatched == "" {
		now, err := p.read(req.Bead)
		if err != nil || now == nil {
			return out, fmt.Errorf("could not read %s again before its first write (%v). Its hold stays on. Run again: %s", req.Bead, err, again)
		}
		if r := value(routedToKey, now); r != "" {
			w := p.Ledger.Write(req.Bead)
			w.Unroute()
			if err := p.Ledger.Commit(w); err != nil {
				return out, fmt.Errorf("%s is routed to %q, which a held bead never carries and gctk bead arm refuses, and the write that clears it did not land (%v). Its hold stays on. Clear it by hand, then run again: gc bd update %s%s --unset-metadata gc.routed_to && %s", req.Bead, r, err, req.Bead, p.dbFlag(), again)
			}
			p.say("cleared the route %q %s carried while held", r, req.Bead)
		}
	}
	if req.Under != "" {
		edges, err := row.Edges()
		if err != nil {
			return out, fmt.Errorf("%s's edges did not decode (%v). Its hold stays on. Run again: %s", req.Bead, err, again)
		}
		if slices.ContainsFunc(edges, func(e ledger.Edge) bool { return e.Type == ledger.EdgeRelatesTo && e.ID == req.Under }) {
			if err := p.Ledger.Unrelate(req.Bead, req.Under); err != nil {
				return out, fmt.Errorf("the removal of %s's relates-to link to %s did not land (%v), and bd refuses a parent beside it. Its hold stays on. Run again: %s", req.Bead, req.Under, err, again)
			}
		}
		if parent != req.Under {
			w := p.Ledger.Write(req.Bead)
			w.Parent(req.Under)
			if err := p.Ledger.Commit(w); err != nil {
				return out, fmt.Errorf("%s did not take %s as its parent (%v; bd refuses a parent that sits under the bead). Its hold stays on. Run again once the cause is fixed: %s", req.Bead, req.Under, err, again)
			}
		}
		if req.Shift != "" {
			if res := p.priority("move", req.Bead, "--shift", req.Shift); res.Code != 0 {
				return out, fmt.Errorf("the shift %s on %s did not land (queue-priority.sh move: %s). %s is under %s, and its hold stays on. Run again to finish: %s", req.Shift, req.Bead, res.Failure(), req.Bead, req.Under, again)
			}
		}
	}

	// Step 3: settle the priority the pour will copy.
	if res := p.priority("settle", req.Bead); res.Code != 0 {
		return out, fmt.Errorf("%s did not settle at its priority (queue-priority.sh settle: %s). A pour copies the priority once, so nothing is dispatched and its hold stays on. Run again once it can settle: %s", req.Bead, res.Failure(), again)
	}
	if now, err := p.read(req.Bead); err == nil && now != nil {
		out.Priority = fmt.Sprintf("P%d", now.Priority())
	}

	// Step 4: dispatch, unless an earlier dispatch shows.
	switch {
	case dispatched != "":
		out.How = "already dispatched (" + dispatched + ")"
	case keptArm != nil:
		out.How = "already armed for " + keptArm.Target + onFormula(req.Formula) + ", so its run starts once nothing holds it"
	default:
		free, why := p.holds(req.Bead)
		if free {
			res := p.Runtime.Sling(gascity.Sling{Rig: p.Rig, Target: pool, Bead: req.Bead, Formula: req.Formula})
			p.output(res.Output)
			switch res.Code {
			case 0:
				out.How = "slung to " + pool + onFormula(req.Formula)
			case 3:
				out.How = "a live run" + ofFormula(req.Formula) + " already works it, and gc sling refused to start another"
			default:
				return out, fmt.Errorf("gc sling did not send %s (%s), so nothing is dispatched and its hold stays on: %s stays in the queue. Run again once the cause is fixed: %s", req.Bead, res.Failure(), req.Bead, again)
			}
			break
		}
		if _, err := p.Arm(arm.Request{ID: req.Bead, Target: pool, Formula: req.Formula, Reason: "placed" + under(req) + ", held by " + why}); err != nil {
			return out, fmt.Errorf("%s is held by %s, so it is armed rather than slung, and the arm did not land (%s). Its hold stays on, so it stays in the queue. Run again once the cause is fixed: %s", req.Bead, why, strings.TrimPrefix(err.Error(), "refused: "), again)
		}
		out.How = "armed for " + pool + onFormula(req.Formula) + ", held by " + why + ", so its run starts once nothing holds it"
	}

	// Step 5: lift the hold, with the note, in one write.
	note := "Placed at " + p.now().UTC().Format(time.RFC3339) + under(req)
	if req.Standalone {
		note += " with no parent"
	}
	if out.Priority != "" {
		note += " at " + out.Priority
	}
	note += ": " + out.How + ". hold:mayor lifted."
	if err := p.lift(req.Bead, note); err != nil {
		return out, fmt.Errorf("%s is %s%s, but the write that lifts its hold:mayor did not land (%v), so it still waits in the queue, and an arm on it does not fire. Finish with the lift by hand, which dispatches nothing: %s. A run again of the placement reads only a live run, an assignee, a merge_result or an arm as this dispatch, so once a run that leaves none of them has ended, it would dispatch %s again",
			req.Bead, placedUnder(req), out.How, err, liftCommand(req.Bead, spellings, note, p.dbFlag()), req.Bead)
	}
	return out, nil
}

// lift removes every spelling of hold:mayor the bead carries now, with note, in
// one write. A bead that carries none is not written.
func (p *Places) lift(bead, note string) error {
	row, err := p.read(bead)
	if err != nil {
		return err
	}
	if row == nil {
		return fmt.Errorf("%s does not resolve", bead)
	}
	spellings := gascity.Spellings(row.Labels(), hold)
	if len(spellings) == 0 {
		return nil
	}
	w := p.Ledger.Write(bead)
	for _, s := range spellings {
		w.RemoveLabel(s)
	}
	w.Note(note)
	return p.Ledger.Commit(w)
}

// holds is whether nothing holds the bead now, as gctk bead holds answers it,
// and otherwise what does: the first wait that holds it, the bead waited on
// with its title, an unjudged waits-for edge named as such, and the ancestor it
// sits on when it is not the bead's own. A read that does not answer holds it.
func (p *Places) holds(bead string) (bool, string) {
	snap, err := waits.Read(p.Ledger, bead)
	if err != nil {
		return false, "a hold that could not be read"
	}
	h, err := snap.Holds(bead)
	if err != nil {
		return false, "a hold that could not be read"
	}
	if h.Status == waits.Clear {
		return true, ""
	}
	if len(h.Waits) == 0 {
		return false, "a hold gctk bead holds names"
	}
	w := h.Waits[0]
	why := w.ID
	if w.Title != "" {
		why += fmt.Sprintf(" %q", w.Title)
	}
	if w.Type == ledger.EdgeWaitsFor {
		why += " (waits-for, unjudged)"
	}
	if w.Ancestor != "" {
		why += " on ancestor " + w.Ancestor
	}
	return false, why
}

// polecatPool is the rig's polecat pool, by the city's roster: the one agent
// named polecat that is scoped to the city or to the bead's rig. A roster that
// does not read, or names none or several, names no pool.
func (p *Places) polecatPool() (string, error) {
	agents, err := p.Runtime.Agents()
	if err != nil {
		return "", fmt.Errorf("the city's roster did not read: %w", err)
	}
	var found []string
	for _, a := range agents {
		if a.Name == "polecat" && (a.Scope == "city" || a.Dir == p.Rig) && !slices.Contains(found, a.QualifiedName) {
			found = append(found, a.QualifiedName)
		}
	}
	switch len(found) {
	case 0:
		return "", errors.New("the roster registers no agent named polecat there")
	case 1:
		return found[0], nil
	}
	return "", fmt.Errorf("the roster names several agents called polecat there (%s)", strings.Join(found, ", "))
}

// priority runs queue-priority.sh, the pack's priority writer, in the bead's
// store, and says what it printed.
func (p *Places) priority(verb, bead string, args ...string) gascity.Result {
	full := append([]string{verb, bead}, args...)
	if p.DB != "" {
		full = append(full, "--db", p.DB)
	}
	res := p.Runtime.Script("queue-priority.sh", full...)
	p.output(res.Output)
	return res
}

// output says each line a command printed.
func (p *Places) output(text string) {
	for _, line := range strings.Split(strings.TrimSpace(text), "\n") {
		if line = strings.TrimSpace(line); line != "" {
			p.say("%s", line)
		}
	}
}

// read is the bead's record in the store, closed or not, nil when the store
// does not hold it.
func (p *Places) read(id string) (*ledger.Record, error) {
	rows, err := p.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		if r.ID == id {
			return r, nil
		}
	}
	return nil, nil
}

func (p *Places) now() time.Time {
	if p.Now == nil {
		return time.Now()
	}
	return p.Now()
}

// dbFlag is the --db a remedy names, empty when the store is unnamed.
func (p *Places) dbFlag() string {
	if p.DB == "" {
		return ""
	}
	return " --db " + p.DB
}

// value is a String key's value on r, trimmed. A String key's stored text
// always decodes.
func value(k ledger.Key[string], r *ledger.Record) string {
	v, _, _ := k.Get(r)
	return strings.TrimSpace(v)
}

func under(req Request) string {
	if req.Under == "" {
		return ""
	}
	return " under " + req.Under
}

func placedUnder(req Request) string {
	if req.Under == "" {
		return ""
	}
	return "under " + req.Under + " and "
}

func onFormula(f string) string {
	if f == "" {
		return ""
	}
	return " on " + f
}

func ofFormula(f string) string {
	if f == "" {
		return ""
	}
	return " of " + f
}

func nonEmpty(s, otherwise string) string {
	if s == "" {
		return otherwise
	}
	return s
}

// liftCommand is the write that lifts the spellings by hand, one
// --remove-label each, with the note appended when one is given.
func liftCommand(bead string, spellings []string, note, dbFlag string) string {
	s := "gc bd update " + bead
	for _, l := range spellings {
		s += " --remove-label " + shQuote(l)
	}
	if note != "" {
		s += " --append-notes " + shQuote(note)
	}
	return s + dbFlag
}

// disarmCommand is the disarm a person runs by hand.
func disarmCommand(bead, reason, dbFlag string) string {
	return "gctk bead disarm " + bead + dbFlag + " --reason " + shQuote(reason)
}

// shQuote is text in single quotes, each quote in it escaped, so a command a
// message names pastes whole.
func shQuote(text string) string {
	return "'" + strings.ReplaceAll(text, "'", `'\''`) + "'"
}

// Line is what a placement says it did, in one line.
func (out Placed) Line(req Request) string {
	if out.Already {
		return "place: " + req.Bead + " carries no hold:mayor and is already placed (" + out.How + "). Nothing was written."
	}
	s := "place: " + req.Bead + " placed" + under(req)
	if req.Standalone {
		s += " with no parent"
	}
	if out.Priority != "" {
		s += " at " + out.Priority
	}
	return s + ": " + out.How + "; hold:mayor lifted"
}
