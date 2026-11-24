package reaction

import (
	"fmt"
	"regexp"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/takeaway"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// Dispose is one exit a reaction takes on its subject, Bead: the exit, why it
// was chosen, the subject's headline, the run that reacted, who disposed it, and
// the exit's own flags. Set names each flag the call set, by its name, so a
// flag set to an empty value is still refused by an exit that takes none.
type Dispose struct {
	Bead, Disposition, Reason, Takeaway, Run, By string

	Route, ThenRoute, Assign, ThenAssign, Emergency string
	Blocker, RecommendedFormula                     string
	WaitingOn                                       []string

	Set map[string]bool
}

// ExitFlags is each exit's own flags. A flag set for an exit whose row does not
// name it is refused before anything is read, so a flag added to one exit
// leaves the others unchanged. Every exit takes the common flags as well.
var ExitFlags = map[string][]string{
	Actionable: {"route", "emergency", "assign"},
	Recommend:  {"recommended-formula"},
	Blocked:    {"waiting-on", "blocker", "then-route", "emergency", "then-assign"},
	Close:      {"route", "waiting-on"},
	Ruling:     nil,
}

// commonFlags is the flags every exit takes.
var commonFlags = []string{"disposition", "reason", "takeaway", "run", "by", "db"}

// Exits is the exits, in the order the usage names them.
var Exits = []string{Actionable, Recommend, Blocked, Close, Ruling}

// The forms a named agent takes a bead in (docs/authority-map.md, Route work).
const (
	formRoute    = "route"    // the agent's hook serves a bead routed to its own name
	formAssignee = "assignee" // the agent lists the beads assigned to it
)

// runID is the shape of a run's root id, one word the check finds among the
// words of a gate's message.
var runID = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// Validate refuses a call for what it asks, before anything is read or
// written, and fills in the pool an actionable or a close exit routes to when
// it names none: the rig's polecat pool, which the city's roster names. A
// recommend's formula is asked of Gas City, because Accept slings that exact
// name.
func Validate(rt gascity.Runtime, rig string, d *Dispose) error {
	if d.Bead == "" {
		return usage("name the subject: gctk reaction dispose <bead> --disposition <exit> ...")
	}
	flags, known := ExitFlags[d.Disposition]
	switch {
	case d.Disposition == "":
		return usage("name the exit: --disposition %s", strings.Join(Exits, "|"))
	case !known:
		return usage("--disposition %s is no exit; the exits are %s", d.Disposition, strings.Join(Exits, ", "))
	}
	for _, name := range slices.Sorted(func(yield func(string) bool) {
		for k, v := range d.Set {
			if v && !yield(k) {
				return
			}
		}
	}) {
		if !slices.Contains(flags, name) && !slices.Contains(commonFlags, name) {
			takes := "no flag of its own"
			if len(flags) > 0 {
				takes = "--" + strings.Join(flags, ", --")
			}
			var owners []string
			for _, e := range Exits {
				if slices.Contains(ExitFlags[e], name) {
					owners = append(owners, e)
				}
			}
			belongs := ""
			switch len(owners) {
			case 0:
			case 1:
				belongs = "; it belongs to the " + owners[0] + " exit"
			default:
				belongs = "; it belongs to the " + strings.Join(owners[:len(owners)-1], ", ") + " and " + owners[len(owners)-1] + " exits"
			}
			return usage("--%s does not belong to the %s exit, which takes %s%s", name, d.Disposition, takes, belongs)
		}
	}
	if d.Reason == "" {
		return usage("--reason is required: the record of why this exit was chosen is what makes a wrong call visible")
	}
	if d.Takeaway == "" {
		return usage("--takeaway is required: it is the subject's one-line headline")
	}
	if d.Set["run"] {
		if !runID.MatchString(d.Run) {
			return usage("--run needs the root of the reaction's run, one bead id of [A-Za-z0-9._-] (got %q)", d.Run)
		}
		if d.Run == d.Bead {
			return usage("--run %s is the subject itself; the run is the reaction poured on %s, so pass the root_bead_id the claim of its react step returned", d.Run, d.Bead)
		}
	}
	if d.Set["emergency"] && strings.TrimSpace(d.Emergency) == "" {
		return usage("--emergency needs the name of the check that fails on main: a check run's name or a commit status's context")
	}
	// route gives an actionable or a close exit that names no --route the rig's
	// polecat pool, by the qualified name the city's roster gives it (rigPool),
	// and refuses a route that names no rig. A refusal names the route as what
	// says, and ends with also.
	route := func(what, also string) error {
		if d.Route == "" {
			if rig == "" {
				return usage("cannot name %s: set GC_RIG or pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody%s", what, also)
			}
			pool, err := rigPool(rt, rig, defaultPool)
			if err != nil {
				return usage("%v; pass --route <rig>/<agent> to name %s", err, what)
			}
			d.Route = pool
		}
		if !strings.Contains(d.Route, "/") {
			return usage("cannot rig-qualify %s %q: pass --route <rig>/<agent>. gc.routed_to is matched as an exact string, so a bare name routes to nobody%s", what, d.Route, also)
		}
		return nil
	}
	switch d.Disposition {
	case Actionable:
		if d.Assign != "" {
			if d.Route != "" {
				return usage("--route and --assign both name where %s goes; pass --route for a pool or --assign for a named agent, not both", d.Bead)
			}
			if d.Emergency != "" {
				return usage("--emergency admits a bead to a pool at P0, and --assign hands it to a named agent instead, which intake does not hold; pass --route for the pool an emergency goes to, or drop --emergency")
			}
			break
		}
		if err := route("the route", ", and a named agent such as the mechanik takes --assign"); err != nil {
			return err
		}
	case Close:
		if err := route("the closer", ""); err != nil {
			return err
		}
		if slices.Contains(d.WaitingOn, d.Bead) {
			return usage("--waiting-on %s is the subject itself", d.Bead)
		}
	case Blocked:
		if d.ThenRoute != "" && d.ThenAssign != "" {
			return usage("--then-route and --then-assign both name where %s goes once its wait lifts; pass --then-route for a pool or --then-assign for a named agent, not both", d.Bead)
		}
		if len(d.WaitingOn) == 0 && d.Blocker == "" {
			return usage("blocked needs --waiting-on <bead> or --blocker \"<title>\": the wait is the edge, and prose about it holds nothing")
		}
		if n := len(d.Blocker); n > 500 {
			return usage("--blocker's title is %d bytes, and bd's cap is 500; name the wait in one line and put the detail in --reason", n)
		}
		if slices.Contains(d.WaitingOn, d.Bead) {
			return usage("--waiting-on %s is the subject itself", d.Bead)
		}
		if d.ThenRoute != "" && !strings.Contains(d.ThenRoute, "/") {
			return usage("--then-route %q is not rig-qualified (<rig>/<agent>)", d.ThenRoute)
		}
		if d.ThenRoute == "" && d.Emergency != "" {
			return usage("--emergency admits the dispatch a --then-route arms, at P0, and this blocked exit arms none; pass --then-route <rig>/<agent>, or drop --emergency")
		}
	case Recommend, Ruling:
		if n := utf8.RuneCountInString(oneLine(d.Takeaway)); n > 140 {
			return usage("--takeaway is %d characters, and the cap is 140, because it is the gate's title and the subject's headline", n)
		}
		if d.Disposition == Recommend {
			if d.RecommendedFormula == "" {
				return usage("recommend needs --recommended-formula <mol>: it is the action the operator Accepts. A gate with no recommended action is --disposition ruling")
			}
			if res := rt.ShowFormula(d.RecommendedFormula); res.Code != 0 {
				return usage("--recommended-formula %s does not resolve to a formula (gc formula show found none), and Accept slings this exact name; fix the typo, or run gc formula list for the roster", d.RecommendedFormula)
			}
		}
	}
	for _, who := range []struct{ name, flag, route string }{{d.Assign, "--assign", "--route"}, {d.ThenAssign, "--then-assign", "--then-route"}} {
		if who.name == "" {
			continue
		}
		if _, err := handoffForm(who.name, who.flag, who.route, d.Bead); err != nil {
			return err
		}
	}
	return nil
}

// handoffForm is the form the named agent who takes a bead in, by the agent's
// name, or the refusal of an agent no bead is handed to. The po takes no work by
// assignment, since its queue is the new work intake holds. The deacon and the
// witness patrol their own wisps and take what they must act on as mail. The
// keeper is no target of a first reaction. Any other agent has no form this
// exit knows.
func handoffForm(who, flag, route, bead string) (string, error) {
	name := who[strings.LastIndex(who, "/")+1:]
	is := func(role string) bool { return name == role || strings.HasSuffix(name, "."+role) }
	switch {
	case is("po"):
		return "", usage("%s %s names the po, which takes no work by assignment: its queue is the new work intake holds with hold:mayor. Pass %s for the pool that would build %s, and intake holds it for placement when no epic holds it, or pass %s for the named agent whose work it is", flag, who, route, bead, flag)
	case is("mechanik"):
		return formRoute, nil
	case is("refinery"):
		return formAssignee, nil
	case is("keeper"):
		return "", usage("%s %s names the keeper, and a first reaction hands no bead to the keeper. Pass %s for the pool that would build %s, %s the mechanik or a refinery for work that is theirs, or put %s to the operator with --disposition ruling", flag, who, route, bead, flag, bead)
	case is("deacon"), is("witness"):
		return "", usage("%s %s names an agent that patrols its own wisps and takes no bead, so a bead handed to it is read by nobody. Send it what it must act on as mail (gc mail send %s -s \"<what it must do>\" -m \"<the bead, and what to do about it>\"), and dispose %s another way", flag, who, who, bead)
	}
	return "", usage("%s %s names no agent this exit can hand a bead to. The mechanik takes a route and the refinery the assignee (docs/authority-map.md, Route work), so pass %s with one of their qualified names, or route the bead to a pool", flag, who, flag)
}

// Disposed is what an exit did: the subject, the exit and what it names.
type Disposed struct {
	Bead, Disposition, Target string
}

func (d Disposed) String() string {
	target := d.Target
	if target == "" {
		target = "no target"
	}
	return fmt.Sprintf("%s disposed as %s (%s)", d.Bead, d.Disposition, target)
}

// Dispose takes the exit d names on its subject, a call Validate passed. It
// reads the subject's status before its first write and writes nothing to a
// subject that is not open (NotOpen). A call that asks for what cannot land,
// such as a hand-off to an agent whose hook would not offer the bead, is a
// *UsageError, with nothing written. Any other error, a route gc sling refuses
// among them, stops the exit part way, and its message says what landed; a
// re-run of the same call resumes it.
func (r *Reactions) Dispose(d *Dispose) (Disposed, error) {
	out := Disposed{Bead: d.Bead, Disposition: d.Disposition}
	if d.By == "" {
		d.By = "proactive"
	}
	release, holder, err := r.acceptLock(d.Bead)
	switch {
	case err != nil:
		return out, fmt.Errorf("could not take %s's acceptance lock (%v), which an exit holds so that it cannot release %s while a placement sends it on. Nothing was written; re-run this command once the lock can be taken", d.Bead, err, d.Bead)
	case release == nil:
		return out, fmt.Errorf("an Accept, a placement or another reaction's exit on %s holds its acceptance lock (%s), so this exit wrote nothing. Re-run this command once that one has finished", d.Bead, holder)
	}
	defer release()
	rows, err := r.Ledger.Find(ledger.ByID(d.Bead).WithClosed())
	if err != nil {
		return out, fmt.Errorf("could not read %s (%v). An exit writes only to an open subject, so nothing was written; re-run this command once the store answers", d.Bead, err)
	}
	var subject *ledger.Record
	for _, row := range rows {
		if row.ID == d.Bead {
			subject = row
		}
	}
	if subject == nil {
		return out, fmt.Errorf("could not read %s: its store does not hold it. An exit writes only to an open subject, so nothing was written", d.Bead)
	}
	if status := subject.Status(); status != "" && status != "open" {
		return out, fmt.Errorf("%w: %s is %s, and an exit writes only to an open subject, so nothing was written and there is nothing for this reaction to dispose", errNotOpen, d.Bead, status)
	}

	// The check took the subject with no assignee, no dispatch path and no run
	// of another formula, so one it carries now came while this reaction ran,
	// from a placement or an Accept. A release would undo that dispatch, since
	// it ends every run under the bead, removes its arm and parks it, so the
	// headline lands alone.
	sent, err := r.sentOn(subject)
	if err != nil {
		return out, fmt.Errorf("could not read the runs that work %s (%v), so whether it was sent on while this reaction ran cannot be told. Nothing was written; re-run this command once the store answers", d.Bead, err)
	}
	if sent != "" {
		if _, err := r.Takeaway(takeaway.Request{Bead: d.Bead, Text: d.Takeaway, By: d.By}); err != nil {
			return out, fmt.Errorf("%s was sent on while this reaction ran (%s), so this exit lands only its headline, and the headline did not land (%v). Nothing else was written; re-run this command", d.Bead, sent, err)
		}
		r.say("%s was sent on while this reaction ran (%s): its headline landed alone, and nothing was released, routed, armed or held", d.Bead, sent)
		return out, nil
	}

	// A subject that carries hold:mayor arrived in the placement queue, where
	// its filer put it, and its placement is the po's and the operator's.
	arrivedHeld := gascity.HasHold(subject.Labels(), gascity.HoldMayor)

	// Intake: only a member of an epic, PR-finishing work, the tracker of a
	// failure on a base branch or a confirmed emergency enters a pool
	// (docs/steering.md), and of a subject that arrived held, only a confirmed
	// emergency. The pool route this exit would write is the actionable exit's
	// route or the blocked exit's --then-route. A named agent's own work is no
	// pool route, and the close exit's closer shrinks the queue rather than
	// adding to it.
	poolTarget := ""
	switch {
	case d.Disposition == Actionable && d.Assign == "":
		poolTarget = d.Route
	case d.Disposition == Blocked:
		poolTarget = d.ThenRoute
	}
	admit, admitWhy, holdWhy := "", "", ""
	if poolTarget != "" {
		if d.Emergency != "" {
			outcome, why := r.checkMain(d.Bead, d.Emergency)
			if outcome == mainRed {
				admit, admitWhy = "emergency", why
			} else {
				holdWhy = "--emergency was not confirmed: " + why
			}
		}
		if admit == "" && !arrivedHeld {
			parents, err := subject.Parents()
			if err != nil {
				return out, fmt.Errorf("could not read %s's parent (%v), so intake cannot decide; nothing was written", d.Bead, err)
			}
			anchor, failure := raw(anchorKey, subject), raw(failureKey, subject)
			switch {
			case len(parents) > 0:
				admit, admitWhy = "member", "a member of "+parents[0]
			case anchor != "":
				admit, admitWhy = "pr-finishing", "PR-finishing work of "+anchor
			case failure != "":
				admit, admitWhy = "tracker", "the tracker of "+failure+", a failure on a base branch"
			}
		}
		switch {
		case admit != "":
			note := ""
			if holdWhy != "" {
				note = " (" + holdWhy + ")"
			}
			r.say("intake admits %s to %s: %s%s", d.Bead, poolTarget, admitWhy, note)
		case arrivedHeld:
			note := ""
			if holdWhy != "" {
				note = " (" + holdWhy + ")"
			}
			r.say("intake leaves %s held for placement instead of %s: it arrived held%s", d.Bead, poolTarget, note)
		default:
			if holdWhy != "" {
				holdWhy += "; "
			}
			holdWhy += d.Bead + " has no parent epic and is not PR-finishing work or a failure's tracker"
			r.say("intake holds %s for placement instead of %s: %s", d.Bead, poolTarget, holdWhy)
		}
	}

	// A route goes to its pool whether or not the pool runs. One that cannot
	// work is refused where the exit makes it: gc sling refuses a target the
	// city configures no agent for and a route into a store the target does not
	// read, before it writes anything (cmdSlingWithJSON in cmd/gc/cmd_sling.go
	// and preflight in internal/sling/sling_core.go, at gastownhall/gascity
	// 781c975d79), and the arm refuses a --then-route whose default formula
	// does not read. A hand-off is made only to a named agent whose hook would
	// offer the bead.
	who, form := d.Assign, ""
	if who == "" {
		who = d.ThenAssign
	}
	if who != "" {
		form, _ = handoffForm(who, "", "", d.Bead)
		if ok, why := r.Assignable(who, d.Bead); !ok {
			return out, usage("%s cannot be handed this bead: %s. Handing it there would leave %s offered to nobody. Name the agent by its exact qualified name, as gc agent list prints it (the mechanik takes a town-repo edit), or route a pool with --route or --then-route", who, why, d.Bead)
		}
	}

	// What holds the subject and the beads it would wait on, read before the
	// first write. A bead its store does not hold would take an edge that holds
	// nothing, and a subject with a wait edge into another store would read as
	// waiting while nothing holds it, which the arm refuses.
	waiting := slices.Clone(d.WaitingOn)
	var holds waits.Holds
	if d.Disposition == Blocked || (d.Disposition == Close && len(waiting) > 0) {
		snap, err := waits.Read(r.Ledger, append([]string{d.Bead}, waiting...)...)
		if err == nil {
			holds, err = snap.Holds(d.Bead)
		}
		if err != nil {
			return out, fmt.Errorf("could not read what holds %s (%v), so whether it carries a wait edge into another store, and whether its store holds each bead it would wait on, is unknown and nothing was written. Re-run this command once the store answers", d.Bead, err)
		}
		for _, w := range waiting {
			if _, err := snap.Holds(w); err != nil {
				if !waits.NotHeld(err) {
					return out, fmt.Errorf("could not read whether %s's store holds %s (%v), so nothing was written. Re-run this command once the store answers for %s", d.Bead, w, err, w)
				}
				if d.Disposition == Close {
					return out, usage("--waiting-on %s is not a bead %s's store holds, so an edge onto it would hold nothing and could not hold %s until %s lands. Nothing was written. When %s is a bead in another store, a person closes %s once it lands instead: put that to the operator with --disposition ruling", w, d.Bead, d.Bead, w, w, d.Bead)
				}
				return out, usage("--waiting-on %s is not a bead %s's store holds, so an edge onto it would hold nothing. Nothing was written. When %s is a bead in another store, wait on a bead in %s's store that names it instead, which --blocker \"<title>\" files", w, d.Bead, w, prefixOf(d.Bead))
			}
		}
		if len(holds.Foreign) > 0 {
			var named []string
			for _, f := range holds.Foreign {
				named = append(named, f.ID+" ("+f.Type+")")
			}
			return out, fmt.Errorf("%s carries a wait edge into another store (%s), which holds nothing, so it would read as waiting on that bead while nothing holds it. Nothing was written. Remove the edge (gc bd dep remove %s %s%s), wait on a bead in %s's store that names it instead, and re-run this command",
				d.Bead, strings.Join(named, ", "), d.Bead, holds.Foreign[0].ID, r.dbFlag(), prefixOf(d.Bead))
		}
	}

	// The blocked exit's missing bead is filed with the subject's wait on it
	// in the same create, so a blocker an earlier run filed is among the
	// subject's pending waits, found by its title, and waited on again.
	if d.Disposition == Blocked && d.Blocker != "" {
		existing := ""
		for _, p := range holds.Pending {
			if p.Type == ledger.EdgeBlocks && p.Title == d.Blocker {
				existing = p.ID
				break
			}
		}
		if existing != "" {
			r.say("the wait '%s' is already %s's pending wait %s; waiting on that one", d.Blocker, d.Bead, existing)
			waiting = append(waiting, existing)
		} else {
			f := r.Ledger.File(d.Blocker, "task")
			f.Description("Filed by a first reaction on " + d.Bead + ", which is waiting on it.\n\n" + d.Reason)
			f.Blocks(d.Bead)
			id, err := r.Ledger.Create(f)
			if err != nil {
				return out, fmt.Errorf("bd named no blocker bead for '%s' (%v). It files the bead and %s's wait on it in one write, so either both landed or neither did, and nothing else was written to %s. Re-run this command: it waits on a blocker that landed, as one of %s's pending waits, and files one that did not", d.Blocker, err, d.Bead, d.Bead, d.Bead)
			}
			r.say("filed the wait as %s", id)
			waiting = append(waiting, id)
		}
	}

	switch d.Disposition {
	case Actionable:
		out.Target = d.Route
		if d.Assign != "" {
			out.Target = d.Assign
		}
	case Blocked:
		out.Target = strings.Join(waiting, ",")
	case Close:
		out.Target = d.Route
		if len(waiting) > 0 {
			out.Target += " once " + strings.Join(waiting, ",") + " closes"
		}
	}
	if poolTarget != "" {
		switch {
		case d.Disposition == Blocked && admit == "":
			out.Target += "; held for placement"
		case d.Disposition == Actionable && admit == "":
			out.Target = "held for placement"
		case d.Disposition == Blocked && admit == "emergency":
			out.Target += "; armed at P0"
		case admit == "emergency":
			out.Target += " at P0"
		}
	}

	// A recommendation already on the subject is cleared before the act, so
	// the subject never offers a superseded Accept, and no recommendation is
	// older than the newest first-reaction gate.
	if raw(recommendedFormulaKey, subject) != "" {
		if err := r.setRecommendation(d.Bead, ""); err != nil {
			return out, fmt.Errorf("the store refused the clear of the earlier recommendation on %s (%v). Nothing else was written. An exit must not leave a superseded Accept executable, so it stops here; clear the cause and re-run this command", d.Bead, err)
		}
	}

	if d.Disposition == Close {
		return r.closeExit(d, waiting, out, arrivedHeld)
	}

	gate := ""
	if d.Disposition == Ruling || d.Disposition == Recommend {
		if gate, err = r.fileGate(d); err != nil {
			return out, err
		}
		out.Target = gate
		r.say("put %s to the operator as the human gate %s", d.Bead, gate)
		if d.Disposition == Recommend {
			if err := r.setRecommendation(d.Bead, d.RecommendedFormula); err != nil {
				return out, fmt.Errorf("the store refused gc.recommended_formula=%s on %s (%v). The gate %s is filed. The operator's Accept reads this key, so the exit stops here rather than leave a recommendation gate that offers only Discuss; clear the cause and re-run this command", d.RecommendedFormula, d.Bead, err, gate)
			}
		}
	}

	// A confirmed emergency carries P0 before its route or its arm, so it is
	// never claimable at the priority it was filed at.
	intakeAt := r.stamp()
	if poolTarget != "" && admit == "emergency" {
		w := r.Ledger.Write(d.Bead)
		w.Priority(0)
		w.Note("## Intake (first reaction, " + intakeAt + ")\nRouted to " + poolTarget + " at P0 as an emergency: " + admitWhy + ".")
		if err := r.Ledger.Commit(w); err != nil {
			return out, fmt.Errorf("could not write priority P0 on %s (%v), so it was not released. Nothing else was written by this step; clear the cause and re-run this command", d.Bead, err)
		}
		r.say("intake wrote priority P0 on %s", d.Bead)
	}

	// The act: the takeaway writes the headline, the release and the wait
	// edges. A blocked exit waits on its blockers, and a ruling or a recommend
	// on its gate, whose edge the gate's create already wrote.
	req := takeaway.Request{Bead: d.Bead, Text: d.Takeaway, By: d.By, Release: true}
	switch d.Disposition {
	case Actionable:
		req.NoWait = true
		switch {
		case d.Assign == "" && admit != "":
			req.Route = d.Route
		case form == formAssignee:
			req.Assign = d.Assign
		}
	case Blocked:
		req.WaitingOn = waiting
		if form == formAssignee {
			req.Assign = d.ThenAssign
		}
	case Recommend, Ruling:
		req.WaitingOn = []string{gate}
	}
	if _, err := r.Takeaway(req); err != nil {
		if req.Route != "" {
			return out, fmt.Errorf("the takeaway on %s stopped: %v. Its route to %s is its last write, so when gc sling refused that route, as it refuses a pool the city does not configure and a store the pool does not read, the headline and the release stand: run this exit again with --route naming a pool the city configures. Otherwise clear the cause and re-run this command", d.Bead, err, req.Route)
		}
		return out, fmt.Errorf("the takeaway on %s stopped: %v. Clear the cause and re-run this command", d.Bead, err)
	}

	// A requested arm is part of the write-back: held with no arm, the bead
	// would wait on its edge with nothing to route it once the wait lifts. A
	// bead intake held is armed by nothing, since its dispatch is the
	// placement sitting's. A subject that arrived held is lifted out of the
	// queue first, since the deferred-dispatch pass fires no arm on a held
	// bead.
	if d.Disposition == Blocked && d.ThenRoute != "" && admit != "" {
		if arrivedHeld {
			if err := r.lift(d, "the dispatch to "+d.ThenRoute+" armed for when its wait lifts"); err != nil {
				return out, err
			}
		}
		if _, err := r.Arm(arm.Request{ID: d.Bead, Target: d.ThenRoute, Reason: "first reaction: " + d.Reason}); err != nil {
			return out, fmt.Errorf("the blocked exit on %s did not land: the dispatch to %s for when its wait lifts was not armed (%v), so nothing would route %s once the wait lifts. The headline, the release and the hold stand. When the arm refused %s because the city configures no such pool, run this exit again with --then-route naming one it configures. Otherwise clear the cause and re-run this command: a re-run resumes rather than refusing", d.Bead, d.ThenRoute, err, d.Bead, d.ThenRoute)
		}
		r.say("armed the dispatch to %s for when the wait lifts", d.ThenRoute)
	}

	// A hand-off of a subject that arrived held lifts it out of the queue,
	// since Gas City serves a held bead to no hook. The refinery's assignee
	// rode the takeaway's release, which lifts the hold of a bead it sends on;
	// the mechanik's route is the hand-off's own sling, so the lift comes
	// before it.
	if who != "" {
		if arrivedHeld && form == formRoute {
			if err := r.lift(d, "the hand-off to "+who); err != nil {
				return out, err
			}
		}
		if err := r.handOver(d, who, form); err != nil {
			return out, err
		}
	}

	// A subject that arrived held stays held, and gets intake's note only for
	// an emergency its check did not confirm, which nothing else records.
	if poolTarget != "" && admit == "" && arrivedHeld {
		if holdWhy != "" {
			w := r.Ledger.Write(d.Bead)
			w.Note("## Intake (first reaction, " + intakeAt + ")\nLeft held for placement instead of reaching " + poolTarget + ": " + holdWhy + ".")
			if err := r.Ledger.Commit(w); err != nil {
				return out, fmt.Errorf("the %s exit on %s did not land. The headline and the release stand, and %s is still held, but intake's note saying why the emergency was not confirmed did not (%v). Clear the cause and re-run this command", d.Disposition, d.Bead, d.Bead, err)
			}
		}
		return out, nil
	}

	// Intake's hold is the exit's last write, because the check a re-offered
	// reaction runs first refuses a held bead that carries a headline: a
	// worker cut off before it lands meets a subject the check passes, and
	// re-runs this exit to the end.
	if poolTarget != "" && admit == "" {
		reason := "Held for placement instead of reaching " + poolTarget + ": " + holdWhy + "."
		w := r.Ledger.Write(d.Bead)
		w.Note("## Intake (first reaction, " + intakeAt + ")\n" + reason + " The operator's placement sitting places it under an epic or routes it on its own; gc beads list --label hold:mayor lists it.")
		if err := r.Ledger.Commit(w); err != nil {
			return out, fmt.Errorf("the %s exit on %s did not land. The headline and the release stand, but intake's note saying why it holds %s did not (%v), so the hold:mayor label was not written. Clear the cause and re-run this command", d.Disposition, d.Bead, d.Bead, err)
		}
		if err := r.Ledger.SetState(d.Bead, "hold", "mayor", reason); err != nil {
			return out, fmt.Errorf("the %s exit on %s did not land. The headline, the release and intake's note stand, but the hold:mayor label did not (%v), so %s rests open and unrouted outside the placement sitting's queue. Clear the cause and re-run this command", d.Disposition, d.Bead, err, d.Bead)
		}
		r.say("intake wrote the hold:mayor label on %s", d.Bead)
	}
	return out, nil
}

// closeExit hands the subject to a validating closer and never closes it: the
// closer re-checks the call against live state and closes the subject or asks
// the operator. The close brief and the headline land before any closer is
// dispatched, so a closer that runs at once finds them. A subject whose job
// ends once other beads land waits on each, and the closer is armed for when
// they have closed; any other is slung to the closer now. A subject that
// arrived held has its hold lifted before the closer is sent, since the closer
// is its next actor and the deferred-dispatch pass fires no arm on a held
// bead.
func (r *Reactions) closeExit(d *Dispose, waiting []string, out Disposed, held bool) (Disposed, error) {
	heldOn := ""
	if len(waiting) > 0 {
		heldOn = "held on " + strings.Join(waiting, ",") + ", "
	}
	w := r.Ledger.Write(d.Bead)
	w.Note("## Close brief (first reaction, " + heldOn + r.stamp() + ")\n" + d.Reason)
	if err := r.Ledger.Commit(w); err != nil {
		return out, fmt.Errorf("could not append the close brief to %s's notes (%v); the validating closer reads it there, so nothing was dispatched. Clear the cause and re-run this command", d.Bead, err)
	}
	if _, err := r.Takeaway(takeaway.Request{Bead: d.Bead, Text: d.Takeaway, By: d.By}); err != nil {
		return out, fmt.Errorf("the close brief is on %s, but its headline did not land (%v), so no closer was dispatched. Clear the cause and re-run this command", d.Bead, err)
	}
	if len(waiting) > 0 {
		for _, h := range waiting {
			if err := r.Ledger.AddBlocker(d.Bead, h); err != nil {
				return out, fmt.Errorf("could not hold %s on %s (%v), so the closer is not armed, since the deferred-dispatch order would sling it before %s closes. bd keeps one edge type per pair of beads, so an edge of another type %s already has onto %s refuses this one: remove it with gc bd dep remove %s %s%s. Clear the cause and re-run this command", d.Bead, h, err, h, d.Bead, h, d.Bead, h, r.dbFlag())
			}
		}
		if held {
			if err := r.lift(d, "the validating closer armed for when "+strings.Join(waiting, ",")+" closes"); err != nil {
				return out, err
			}
		}
		if _, err := r.Arm(arm.Request{ID: d.Bead, Target: d.Route, Formula: closer, Reason: "first reaction close: " + d.Reason}); err != nil {
			return out, fmt.Errorf("the close brief, the headline and the holds stand on %s, but the validating closer was not armed (%v). A wait onto a bead another store holds is an edge that holds nothing, and the arm refuses a bead that carries one: remove it (gc bd dep remove %s <that bead>%s) and put %s's close to the operator with --disposition ruling. Otherwise clear the cause and re-run this command", d.Bead, err, d.Bead, r.dbFlag(), d.Bead)
		}
		return out, nil
	}
	if held {
		if err := r.lift(d, "the validating closer on "+d.Route); err != nil {
			return out, err
		}
	}
	res := r.Runtime.Sling(gascity.Sling{Rig: r.Rig, Target: d.Route, Bead: d.Bead, Formula: closer})
	switch {
	case res.Code == 3:
		// gc sling exits 3 only when a live run of the same formula works the
		// bead already, such as the closer an earlier run of this exit slung.
		r.say("a validating closer already drives %s, so no second is slung: %s", d.Bead, oneLine(res.Output))
	case res.Failure() != "":
		return out, fmt.Errorf("could not sling %s to the validating closer %s (gc sling --on %s: %s). The close brief and the headline stand. When gc sling refused the route, as it refuses a pool the city does not configure and a store the pool does not read, run this exit again with --route naming a pool the city configures; otherwise clear the cause and re-run this command", d.Bead, d.Route, closer, res.Failure())
	}
	return out, nil
}

// handOver hands the released subject to the named agent who, in its form. The
// mechanik takes Gas City's own route, a sling that pours nothing and files no
// convoy; the refinery's assignee the release already wrote. A route or an
// assignee alone gives a running agent no turn, so the agent is nudged when bd
// reports the subject ready, read after the hand-off lands. A subject still
// waiting has a blocker that closes later, and Gas City nudges the agent then.
func (r *Reactions) handOver(d *Dispose, who, form string) error {
	how, what := "assigned", "assignee"
	if form == formRoute {
		how, what = "routed", "route"
		res := r.Runtime.Sling(gascity.Sling{Rig: r.Rig, Target: who, Bead: d.Bead, NoFormula: true})
		if f := res.Failure(); f != "" {
			return fmt.Errorf("the %s exit on %s did not land: gc sling did not hand it to %s (%s), so the agent's hook does not offer it. The headline and the release stand, so clear the cause and re-run this command: a re-run resumes rather than refusing", d.Disposition, d.Bead, who, f)
		}
	}
	ready, err := r.Ledger.ReadyIDs()
	if err != nil {
		return fmt.Errorf("the %s exit on %s did not land. It is %s to %s, but whether bd reports it ready could not be read (%v), so whether the agent is owed a nudge now is unknown. The headline, the release and the %s stand, so clear the cause and re-run this command: a re-run resumes rather than refusing", d.Disposition, d.Bead, how, who, err, what)
	}
	if slices.Contains(ready, d.Bead) {
		if res := r.Runtime.Nudge(who, d.Bead+" is "+how+" to you and ready"); res.Failure() != "" {
			return fmt.Errorf("the %s exit on %s did not land. It is %s to %s, but gc session nudge did not reach the agent (%s), so a running agent gets no turn for it. The headline, the release and the %s stand, so clear the cause and re-run this command: a re-run resumes rather than refusing", d.Disposition, d.Bead, how, who, res.Failure(), what)
		}
	}
	r.say("handed %s to %s", d.Bead, who)
	return nil
}

// sentOn names what sent the subject on while this reaction ran, empty when
// nothing did: a live run of a formula that no exit pours on its subject, any
// but a first reaction's and the validating closer's, and, while the subject
// carries no headline, an assignee or a dispatch path. Once it carries one, an
// assignee and a dispatch path are this run's own exit run again, which wrote
// them after its headline.
func (r *Reactions) sentOn(subject *ledger.Record) (string, error) {
	var by []string
	if !concluded(subject) {
		if a := strings.TrimSpace(subject.Assignee()); a != "" {
			by = append(by, "assigned to "+a)
		}
		by = append(by, dispatchPaths(subject)...)
	}
	runs, err := waits.RunsOf(r.Ledger, subject.ID)
	if err != nil {
		return "", err
	}
	for _, run := range runs {
		if run.Live && run.Formula != Formula && run.Formula != closer {
			by = append(by, "live run "+run.Root)
		}
	}
	return strings.Join(by, ", "), nil
}

// lift takes the subject out of the placement queue for the next actor this
// exit sends it to, which to names. A lift that does not land stops the exit,
// and a re-run resumes it, since the check a re-offered reaction runs passes
// over the headline its own run wrote.
func (r *Reactions) lift(d *Dispose, to string) error {
	lifted, err := r.liftHold(d.Bead, "")
	if err != nil {
		return fmt.Errorf("the %s exit on %s did not land: hold:mayor was not lifted for %s (%v), and Gas City serves a held bead to no hook. The headline and the release stand, so clear the cause and re-run this command: a re-run resumes rather than refusing", d.Disposition, d.Bead, to, err)
	}
	if len(lifted) > 0 {
		r.say("lifted hold:mayor from %s for %s", d.Bead, to)
	}
	return nil
}

// setRecommendation sets the subject's recommendation to formula, or clears it
// when formula is empty.
func (r *Reactions) setRecommendation(bead, formula string) error {
	w := r.Ledger.Write(bead)
	if formula == "" {
		recommendedFormulaKey.Clear(w)
	} else {
		recommendedFormulaKey.Set(w, formula)
	}
	return r.Ledger.Commit(w)
}

// dbFlag is the store flag a remedy's command names, empty when the caller
// named no store.
func (r *Reactions) dbFlag() string {
	if r.DB == "" {
		return ""
	}
	return " --db " + r.DB
}
