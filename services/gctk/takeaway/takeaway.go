// Package takeaway is a bead's takeaway: the one-line headline its handling
// concluded, who wrote it and when, and whether anything still waits on the
// bead, which `gctk bead takeaway` writes in one update. With --release the
// same update takes the bead out of play, and the verb removes its arm first
// and ends the run beneath it after, so a release stops the bead or sends it
// on to a pool or a named agent.
//
// The release is one update guarded by the status and the assignee it read, so
// a close or a claim that lands after the read refuses it whole, and a re-read
// then settles which of the two it was: a bead closed since keeps its
// disposition and takes the headline alone, and any other change leaves the
// bead with whoever holds it now. A claim a live session holds is never taken.
// The verb asks waits what holds the bead and which runs work it, the pr record
// where its PR stands and which branch its work is on, prstatus which beads are
// human gates, and the arm to remove its arm. The reaction's dispose writes each exit's headline through
// it, and its sweep asks it whether a bead carries a headline.
package takeaway

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/lifecycle"
	prrecord "github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The takeaway's keys, which this package writes, each in the one update that
// writes the headline. gctk lifecycle's --takeaway can also write them, and
// shell still reads them (docs/gctk-architecture.md, Debt), so they stay
// registered in lifecycle/lifecycle.toml too.
var (
	textKey = ledger.Declare("gc.takeaway", ledger.String,
		"A bead's headline: the one line, at most lifecycle.TakeawayMax codepoints, that its handling concluded, "+
			"which gctk bead takeaway writes and every exit of a first reaction and every sitting's sign-off "+
			"leaves. The first reaction's sweep passes over a bead that carries one, as one already triaged. "+
			"Absent, nothing has concluded on the bead.")
	atKey = ledger.Declare("gc.takeaway_at", ledger.String,
		"When the bead's headline was written, RFC 3339 UTC to the second, in the update that writes it.")
	byKey = ledger.Declare("gc.takeaway_by", ledger.String,
		"Who wrote the bead's headline, such as host, proactive or converse, in the update that writes it. The "+
			"first reaction's sweep passes over a bead that carries one, as one already triaged.")
	settledKey = ledger.Declare("gc.takeaway_settled", ledger.String,
		"1 when the writer of the bead's headline said nothing waits on the bead, and empty when it named a "+
			"wait or said neither, written with every headline so no earlier headline's answer stands for a "+
			"later one. lifecycle/lifecycle.toml [holds] pairs it with gc.takeaway, so a headline left with "+
			"neither an edge nor this mark reads as a hold on prose.")
)

// Text and By are the reading faces of a bead's headline and of who wrote it.
var (
	Text = textKey.View()
	By   = byKey.View()
)

// Request is one takeaway on Bead: the headline Text, the writer By names,
// host when it names none, and the beads the bead waits on, or NoWait when
// nothing waits on it. Release takes the bead out of play, and Route sends it
// on to a pool, <rig>/<agent>, or Assign to a named agent.
type Request struct {
	Bead, Text, By string
	WaitingOn      []string
	NoWait         bool
	Release        bool
	Route, Assign  string
}

// City is Gas City as a takeaway reaches it: the sling that routes a released
// bead, the pack's run-cancel.sh, which ends a run through Gas City's run
// cancel, the session list that says whether a claim's holder is gone, and the
// nudge that asks a live holder to give the bead back.
type City interface {
	Sling(s gascity.Sling) gascity.SlingResult
	Script(name string, args ...string) gascity.Result
	NudgeNow(session, message, bead string) gascity.Result
	Sessions(ctx context.Context) ([]gascity.Session, error)
}

// Takeaways is the takeaway's verb over one store.
type Takeaways struct {
	Ledger *ledger.Ledger
	City   City
	// Disarm removes a bead's arm under its dispatch lock, as gctk bead
	// disarm does, and says what it did.
	Disarm func(id, reason string) (string, error)
	// DB is the store the caller named, a store's .beads directory, which a
	// remedy and the run cancel name, empty when gc routes the bead to its
	// store.
	DB string
	// Scripts is the pack's scripts directory, which holds run-cancel.sh and
	// the hand-back a live holder is asked to run, empty when the caller names
	// none.
	Scripts string
	// Self is the names this session goes by, its session name, its session id
	// and its alias: a run whose live member one of them holds is this
	// session's own. Agent is its agent address, which names a claim of its
	// own beside them.
	Self  []string
	Agent string
	// Now is the clock the headline's time is read from.
	Now func() time.Time
	// Log takes each line the verb says as it goes, nil for none.
	Log func(string)
}

// Refusal is a takeaway refused before anything was written.
type Refusal struct{ Msg string }

func (e *Refusal) Error() string { return e.Msg }

func refuse(format string, args ...any) error {
	return &Refusal{Msg: fmt.Sprintf(format, args...)}
}

// Refused reports whether err is a takeaway refused before anything was
// written.
func Refused(err error) bool {
	var r *Refusal
	return errors.As(err, &r)
}

func (t *Takeaways) say(format string, args ...any) {
	if t.Log != nil {
		t.Log(fmt.Sprintf(format, args...))
	}
}

// claimStatuses are bd's claim statuses, a session's hold on a bead.
var claimStatuses = []string{"in_progress", "hooked"}

// Take writes req's headline in one update, which a release also carries, and
// returns the line that says what landed. A *Refusal wrote nothing. Any other
// error stopped the verb part way, or after every write, and says what landed
// and what did not, so a caller that writes next, such as a sitting's sign-off
// answering its gates, goes on only once Take returns no error.
func (t *Takeaways) Take(req Request) (string, error) {
	bead := strings.TrimSpace(req.Bead)
	if bead == "" {
		return "", refuse("name the bead: gctk bead takeaway <bead> \"<text>\"")
	}
	if req.NoWait && len(req.WaitingOn) > 0 {
		return "", refuse("--no-wait contradicts --waiting-on %s: one says nothing is waiting on %s, the other names what is. Pass whichever is true. Nothing was written.",
			strings.Join(req.WaitingOn, " "), bead)
	}
	text, err := lifecycle.Headline(req.Text)
	var long *lifecycle.LongHeadline
	switch {
	case errors.Is(err, lifecycle.ErrNoHeadline):
		return "", refuse("takeaway needs \"<text>\", the one-line headline of at most %d characters. Nothing was written.", lifecycle.TakeawayMax)
	case errors.As(err, &long):
		return "", refuse("the text is %d characters, and the cap is %d. It is the bead's headline, one line read at a glance, so cut it to the single sentence the operator needs and put the rest in the bead's notes. Nothing was written.",
			long.Len, lifecycle.TakeawayMax)
	case err != nil:
		return "", refuse("%v. Nothing was written.", err)
	}
	by := req.By
	if by == "" {
		by = "host"
	}
	if req.Route != "" {
		if !req.Release {
			return "", refuse("--route needs --release, since it names where the bead is released to. Nothing was written.")
		}
		if !strings.Contains(req.Route, "/") {
			return "", refuse("--route %q is not rig-qualified. gc.routed_to is matched as an exact string, so a bare agent name routes to nobody and the bead sits forever. Use <rig>/<agent>. Nothing was written.", req.Route)
		}
	}
	if req.Assign != "" {
		if !req.Release {
			return "", refuse("--assign needs --release, since it names who the bead is released to. Nothing was written.")
		}
		if req.Route != "" {
			return "", refuse("--assign and --route both name where %s goes. A bead is addressed to a named agent by its assignee or to a pool by gc.routed_to, never both. Pass one. Nothing was written.", bead)
		}
	}
	if req.Release && t.Scripts == "" {
		return "", refuse("--release ends the run beneath %s through the pack's run-cancel.sh, and GCTK_SCRIPTS_DIR names no pack scripts directory to run it from. Run it as GCTK_SCRIPTS_DIR=\"$(gc <binding> scripts-dir)\" gctk bead takeaway ... Nothing was written.", bead)
	}

	r := &take{t: t, req: req, bead: bead, text: text, by: by, noWait: req.NoWait}
	if err := r.readAnchor(); err != nil {
		return "", err
	}
	if err := r.guardRelease(); err != nil {
		return "", err
	}
	if err := r.sortWaits(); err != nil {
		return "", err
	}
	if err := r.guardDestination(); err != nil {
		return "", err
	}
	r.readClaim()
	return r.write()
}

// take is one Take as it goes: what it read, and what it has decided to
// write.
type take struct {
	t                *Takeaways
	req              Request
	bead, text, by   string
	noWait           bool
	anchor           *ledger.Record // the bead as a release read it
	status, assignee string         // its status and assignee then
	mergeResult      string
	// park is a release that reopens the bead: one whose bead still stands.
	park bool
	// holds are the spellings of hold:mayor a release that sends the bead on
	// lifts.
	holds []string
	// real are the waits that become edges, riders the landed riders that do
	// not, and routeWaits the waits a route counts as work on a blocker, with
	// routeUnread those whose row did not read.
	real, riders, routeWaits, routeUnread []string
	branch                                string
	// kept names the holder of a live claim the release keeps, sessions the
	// sessions the list names it under, and unread a list that did not read.
	kept     string
	sessions []string
	unread   bool
}

// readAnchor reads the bead a release acts on. A release's park is right for a
// bead still standing and destructive for one already disposed, which a fold
// closes with its successor named, so a bead whose status does not read is
// refused, and a closed one keeps its disposition and gets the headline and
// the run's end alone.
func (r *take) readAnchor() error {
	if !r.req.Release {
		return nil
	}
	r.park = true
	rec, err := r.t.read(r.bead)
	if err != nil || rec == nil || rec.Status() == "" {
		why := "its store does not hold it"
		if err != nil {
			why = err.Error()
		}
		return fmt.Errorf("could not read the status of %s (%s). A release that cannot read a bead's disposition would reopen it blind, so it is refused and nothing was written", r.bead, why)
	}
	r.anchor, r.status, r.assignee = rec, rec.Status(), rec.Assignee()
	r.mergeResult = value(prrecord.Result, rec)
	r.branch = value(prrecord.Branch, rec)
	if r.status == "closed" {
		r.park = false
		r.t.say("%s", r.closedSkip(rec, "is closed"))
	}
	return nil
}

// guardRelease refuses a release the bead's state makes wrong, before
// anything is written.
func (r *take) guardRelease() error {
	if !r.park {
		return nil
	}
	// A bead whose PR waits on the pending record is assigned to nobody while
	// the landing order works it, so a release would leave the order working
	// it. A human gate holds the PR's merge, and the PR's retirement ends it.
	if prrecord.OnRecord(r.mergeResult) {
		return refuse("--release on %s, whose PR waits on the pending record (%s). The landing order works that bead while it is assigned to nobody, so a release would not stop it. To hold the PR for a person, file a human gate on %s: %s --subject %s --key <key> --message '<what the person decides>'. To end the PR, retire it: %s --anchor %s --successor <bead> --kind <kind> --note '<why>', or --retire on a sitting's sign-off. Re-run without --release to land the headline alone. Nothing was written.",
			r.bead, r.mergeResult, r.bead, r.t.script("human-gate.sh"), r.bead, r.t.script("pr-dispose.sh"), r.bead)
	}
	// Sending a held bead on is a placement, and Gas City serves no bead a hold
	// label holds, so the release lifts the bead's hold:mayor.
	if r.req.Route != "" || r.req.Assign != "" {
		r.holds = gascity.Spellings(r.anchor.Labels(), "hold:mayor")
	}
	// A release that parks the bead for a person states its disposition: the
	// wait as an edge, or the settled mark that says there is none. Only an
	// open blocker the bead already carries lets it go with neither, since that
	// edge is the wait. A headline holding the bead with no edge and no mark is
	// the hold on prose doctor/check-wait-is-an-edge reports.
	if r.req.Route == "" && r.req.Assign == "" && !r.req.NoWait && len(r.req.WaitingOn) == 0 {
		pending, err := r.t.pending(r.bead)
		if err != nil {
			return refuse("--release parks %s for a person, and a park states its disposition, but %s's blockers could not be read (%v), so an open blocker that holds it cannot be proven. Pass --waiting-on <bead> for the wait it holds on, which becomes a blocks edge, or --no-wait when nothing waits on it, or re-run once the store answers. Nothing was written.",
				r.bead, r.bead, err)
		}
		if len(pending) == 0 {
			return refuse("--release parks %s for a person, and a park states its disposition: --waiting-on <bead> for the wait it holds on, which becomes a blocks edge, or --no-wait when nothing waits on it. %s carries no open blocker to hold it, so with neither the headline is a hold on prose, which doctor/check-wait-is-an-edge reports. Nothing was written.",
				r.bead, r.bead)
		}
	}
	return nil
}

// sortWaits sorts the named waits into the ones that become edges and the
// landed riders. A landed rider rode the bead's own branch and has put its
// work there, so the bead's own merge carries it, and an edge would hold that
// merge on work that merges with it. A shared branch alone is no proof, since
// workspace-setup writes it before the wait pushes. The proof is a state a
// push precedes: the wait closed, handed to the refinery, or its PR on the
// pending record. When every named wait is a landed rider, nothing waits, and
// the headline takes the settled mark --no-wait writes. A route also counts
// each owed wait that is neither closed nor a human gate as work on a blocker.
func (r *take) sortWaits() error {
	if len(r.req.WaitingOn) == 0 {
		return nil
	}
	var named []string
	for _, w := range r.req.WaitingOn {
		w = strings.TrimSpace(w)
		switch {
		case w == "":
		case w == r.bead:
			r.t.say("--waiting-on %s is the bead itself; skipped", w)
		case prefixOf(w) != prefixOf(r.bead):
			return refuse("--waiting-on %s lives in another store than %s, and bd resolves an edge only within one store, so an edge onto %s would hold nothing. Wait on a bead in %s's store that names %s instead. Nothing was written.",
				w, r.bead, w, r.bead, w)
		case !slices.Contains(named, w):
			named = append(named, w)
		}
	}
	if len(named) == 0 {
		return nil
	}
	if r.anchor == nil {
		if rec, err := r.t.read(r.bead); err == nil && rec != nil {
			r.branch = value(prrecord.Branch, rec)
		}
	}
	rows := map[string]*ledger.Record{}
	if found, err := r.t.Ledger.Find(ledger.ByID(named...).WithClosed()); err == nil {
		for _, rec := range found {
			rows[rec.ID] = rec
		}
	}
	for _, w := range named {
		row := rows[w]
		if row != nil && r.branch != "" && value(prrecord.Branch, row) == r.branch && landed(row) {
			r.riders = append(r.riders, w)
			continue
		}
		r.real = append(r.real, w)
		if r.req.Route == "" || !r.park {
			continue
		}
		switch {
		case row == nil:
			r.routeWaits, r.routeUnread = append(r.routeWaits, w), append(r.routeUnread, w)
		case row.Status() != "closed" && !person.IsHumanGate(row.IssueType(), row.AwaitType()):
			r.routeWaits = append(r.routeWaits, w)
		}
	}
	if len(r.riders) > 0 && len(r.real) == 0 {
		r.noWait = true
	}
	return nil
}

// landed reports whether a wait's work has provably reached its branch: it
// closed, the refinery holds it, or its PR waits on the pending record.
func landed(w *ledger.Record) bool {
	a := w.Assignee()
	return w.Status() == "closed" || a == "refinery" || strings.HasSuffix(a, ".refinery") || strings.HasSuffix(a, "/refinery") ||
		prrecord.OnRecord(value(prrecord.Result, w))
}

// guardDestination refuses a route, or an assignment that names no wait, onto
// a bead whose work is on a blocker. A pool route promises a claim some
// session can perform, and a bead blocked by anything but a human gate has its
// method elsewhere: no pool sees it until the blocker closes, and then it is a
// record of work already done. A human gate is the one blocker that leaves the
// route honest, since answering it is what makes the bead the work. A route
// counts the waits its own call names beside the edges the bead carries, since
// those are written only after the release. An assignment that names its waits
// is gated by them, since the agent's hook offers the bead only once bd reports
// it ready. A blocker read that fails lets the destination through, and says
// so: a store that does not answer must not cost a sitting its disposition.
func (r *take) guardDestination() error {
	dest, flag := r.req.Route, "--route"
	if dest == "" && r.req.Assign != "" && len(r.req.WaitingOn) == 0 {
		dest, flag = r.req.Assign, "--assign"
	}
	if dest == "" || !r.park {
		return nil
	}
	pending, err := r.t.pending(r.bead)
	if err != nil {
		r.t.say("could not read the blockers on %s (%v), so %s %s goes unchecked. If this bead's work is on a blocker, it reaches %s with no method to perform once that blocker closes. Re-run with --release alone to leave it at rest, or re-run this call once the store answers.",
			r.bead, err, flag, dest, dest)
		pending = nil
	}
	var blockedBy []string
	for _, p := range pending {
		if !person.IsHumanGate(p.IssueType, p.AwaitType) {
			blockedBy = append(blockedBy, p.ID)
		}
	}
	if flag == "--route" && (len(blockedBy) > 0 || len(r.routeWaits) > 0) {
		var why []string
		if len(blockedBy) > 0 {
			why = append(why, "which is blocked by "+strings.Join(blockedBy, " "))
		}
		if len(r.routeWaits) > 0 {
			why = append(why, "whose --waiting-on names "+strings.Join(r.routeWaits, " "))
		}
		unread := ""
		if len(r.routeUnread) > 0 {
			unread = fmt.Sprintf(" The row of %s did not read, so nothing shows it closed or a human gate.", strings.Join(r.routeUnread, " "))
		}
		rerun := "Re-run with --release alone, which still lands the headline and the release and leaves the bead at rest."
		if len(r.routeWaits) > 0 {
			rerun = "Re-run without --route, which still lands the headline, the release and the waits, and leaves the bead at rest."
		}
		return refuse("--route %s on %s, %s. None of those is a human gate on %s, so the work is on them and this bead has no method a pool can perform: routed, it waits for them to close and is then offered to %s forever.%s %s A bead that should reach a pool once its blocker clears is gctk reaction dispose --disposition blocked --then-route %s, which routes on the unblock instead of now.",
			dest, r.bead, strings.Join(why, ", and "), r.bead, dest, unread, rerun, dest)
	}
	if len(blockedBy) > 0 {
		return refuse("--assign %s on %s, which is blocked by %s. None of those is a human gate on %s, so the work is on them: assigned, %s reaches %s once they close, as a record of work already done. Re-run with --release alone, which still lands the headline and the release and leaves the bead at rest. A bead that should reach %s once its blocker clears names that wait: gctk reaction dispose --disposition blocked --then-assign %s.",
			dest, r.bead, strings.Join(blockedBy, " "), r.bead, r.bead, dest, dest, dest)
	}
	return nil
}

// readClaim decides whether a release takes the bead's claim. bd lets a write
// guarded on a claim's holder change a claim it would refuse to touch
// otherwise, so the release names a holder in its guard only once the holder
// is shown gone: the claim is this session's, or the session list names its
// holder under none of its names. A holder the list still names, or a list
// that does not read, keeps the claim: nothing in Gas City stops a session that
// holds a bare bead, and the holder's own hand-back releases the claim and its
// route in one guarded write.
func (r *take) readClaim() {
	if !r.park || r.assignee == "" || !slices.Contains(claimStatuses, r.status) || r.t.mine(r.assignee) {
		return
	}
	sessions, err := r.t.holders(r.assignee)
	switch {
	case err != nil:
		r.kept, r.unread = r.assignee, true
	case len(sessions) > 0:
		r.kept, r.sessions = r.assignee, sessions
	}
}

// write makes the takeaway's writes in their order: the disarm, the one
// update, the wait edges, the run's end, then what a kept claim, a closed bead
// or a route still owes. What follows the update cannot be taken back, so a
// refused update ends the verb with no edge and no run's end.
func (r *take) write() (string, error) {
	t := r.t
	if r.req.Release {
		said, err := t.Disarm(r.bead, "takeaway --release: "+r.text)
		if err != nil {
			return "", fmt.Errorf("--release stops %s, so its first write removes the arm that would start it again once nothing holds it, and that disarm did not land (%v). Nothing else was written. Re-run once the arm can be removed", r.bead, err)
		}
		if strings.HasPrefix(said, "disarmed ") {
			t.say("%s", said)
		}
	}
	at := t.Now().UTC().Format(time.RFC3339)
	release := r.park && r.kept == ""
	err := t.Ledger.Commit(r.update(at, release))
	if release && errors.Is(err, ledger.ErrGuard) {
		now, readErr := t.read(r.bead)
		if readErr != nil || now == nil || now.Status() != "closed" {
			shows := "could not be read again"
			if readErr == nil && now != nil {
				shows = "now shows status " + now.Status() + under(now.Assignee())
			}
			return "", fmt.Errorf("%s changed after the release read it, so bd refused its guarded write and nothing was written: it showed status %s%s, and %s. The release takes it from no one who holds it now, so no wait was wired and no run was ended. Re-run to decide again on what it shows now",
				r.bead, r.status, under(r.assignee), shows)
		}
		r.park, r.holds = false, nil
		t.say("%s", r.closedSkip(now, "closed after the release read it"))
		err = t.Ledger.Commit(r.update(at, false))
	}
	if err != nil {
		return "", fmt.Errorf("could not write the headline on %s (%v), so nothing after it was written", r.bead, err)
	}

	edgeMissed := false
	for _, w := range r.real {
		if err := t.Ledger.AddBlocker(r.bead, w); err != nil {
			edgeMissed = true
			t.say("could not wire --waiting-on %s (%v). The headline stands, but nothing holds %s on %s. Wire it by hand: gc bd dep add %s %s -t blocks%s", w, err, r.bead, w, r.bead, w, t.dbFlag())
			continue
		}
		t.say("waiting-on edge: %s depends on %s", r.bead, w)
	}
	for _, w := range r.riders {
		t.say("--waiting-on %s is a landed rider on %s's own branch (%s): its work is already there, so %s's merge lands it and no wait edge is written, since an edge would hold %s's merge on work that merges with it", w, r.bead, r.branch, r.bead, r.bead)
	}
	runsEnded := true
	if r.req.Release {
		runsEnded = t.endRuns(r.bead)
	}
	if r.kept != "" {
		return "", r.keptClaim()
	}
	switch {
	case !runsEnded:
		return "", fmt.Errorf("a run beneath %s did not end, as the lines above say with the cancel to run by hand. The headline%s stands", r.bead, r.released())
	case r.req.Route != "" && !r.park:
		return "", fmt.Errorf("%s is closed, so it was not routed to %s: a pool that claimed it would work a bead whose disposition landed. The headline and the run's end are written. If the disposition is wrong, reopen the bead deliberately and re-run: gc bd update %s%s --status=open", r.bead, r.req.Route, r.bead, t.dbFlag())
	case r.req.Assign != "" && !r.park:
		return "", fmt.Errorf("%s is closed, so it was not assigned to %s: the agent would be handed a bead whose disposition landed. The headline and the run's end are written. If the disposition is wrong, reopen the bead deliberately and re-run: gc bd update %s%s --status=open", r.bead, r.req.Assign, r.bead, t.dbFlag())
	case edgeMissed:
		return "", fmt.Errorf("a --waiting-on edge on %s did not land, as the lines above say. The headline%s stands", r.bead, r.released())
	}
	// The bead is released and its run has ended, so a route sends it to the
	// pool now, through a sling that pours nothing and files no convoy.
	if r.req.Route != "" {
		res := t.City.Sling(gascity.Sling{Target: r.req.Route, Bead: r.bead, NoFormula: true})
		if f := res.Failure(); f != "" {
			return "", fmt.Errorf("%s is released and the run beneath it has ended, but gc sling did not route it to %s (%s), so it rests open, unassigned and routed to no pool. Route it once the cause is fixed: gc sling %s %s --no-formula --no-convoy", r.bead, r.req.Route, f, r.req.Route, r.bead)
		}
	}
	note := ""
	switch {
	case r.req.Release && r.park:
		to := ""
		switch {
		case r.req.Route != "":
			to = " to " + r.req.Route
		case r.req.Assign != "":
			to = " to " + r.req.Assign
		}
		lifted := ""
		if len(r.holds) > 0 {
			lifted = "; hold:mayor lifted"
		}
		note = " [released" + to + lifted + "]"
	case r.req.Release:
		note = " [run ended; anchor left closed]"
	}
	return fmt.Sprintf("takeaway set on %s (by %s)%s: %s", r.bead, r.by, note, r.text), nil
}

// update is the one update: the headline, its time, its writer and its settled
// mark, and for a release the park, guarded by the status and the assignee the
// release read. The park reopens the bead and assigns it to the named agent or
// to nobody, clears Gas City's route and session pins, and lifts hold:mayor
// from a bead it sends on.
func (r *take) update(at string, release bool) *ledger.Write {
	w := r.t.Ledger.Write(r.bead)
	textKey.Set(w, r.text)
	atKey.Set(w, at)
	byKey.Set(w, r.by)
	settled := ""
	if r.noWait {
		settled = "1"
	}
	settledKey.Set(w, settled)
	if release {
		w.Guard(r.status, r.assignee)
		w.Status("open")
		w.Assignee(r.req.Assign)
		w.Release()
		for _, h := range r.holds {
			w.RemoveLabel(h)
		}
	}
	return w
}

// keptClaim nudges the holder of the claim the release kept to stop and give
// the bead back, at each session the list names it under, or at the holder's
// own name when the list did not read, and is the error that says so.
func (r *take) keptClaim() error {
	t := r.t
	targets := r.sessions
	if len(targets) == 0 {
		targets = []string{r.kept}
	}
	msg := fmt.Sprintf("Stop work on %s: a takeaway --release took it out of play while you hold its claim, and its headline says why: %s. Give it back in one guarded write that reopens it and clears your claim and its route: %s %s --set-metadata gc.routed_to=",
		r.bead, r.text, t.script("hand-back.sh"), r.bead)
	var hit []string
	for _, s := range targets {
		if res := t.City.NudgeNow(s, msg, r.bead); res.Failure() == "" {
			hit = append(hit, s)
		}
	}
	why := fmt.Sprintf("gc session list still lists that holder (%s)", strings.Join(r.sessions, " "))
	if r.unread {
		why = "gc session list could not be read, so nothing shows that holder gone"
	}
	asked := fmt.Sprintf("The nudge to %s did not land, so ask it to stop and give the bead back", r.kept)
	if len(hit) > 0 {
		asked = fmt.Sprintf("%s was nudged (%s) to stop and give the bead back", r.kept, strings.Join(hit, " "))
	}
	waits := ""
	if len(r.real) > 0 {
		waits = " and the waits"
	}
	return fmt.Errorf("%s is %s under %s, and %s, so its claim was kept: a release takes no live claim, and nothing in Gas City stops a session that holds a bare bead. The headline%s and the run's end are written, but %s was not released%s. %s. A stop that must hold even if %s dies first waits on a human gate (--waiting-on <gate>). Once the bead is given back, re-run this call",
		r.bead, r.status, r.kept, why, waits, r.bead, r.destination(), asked, r.kept)
}

// endRuns ends each live run that works the bead through Gas City's run
// cancel, which closes the root and every step that is not closed. A run whose
// live member this session holds is its own, such as a sitting disposing the
// bead it runs on, and is left to close its own chain. A read that fails, of
// the runs or of whose they are, ends nothing, since a run it could not read
// may still run. It reports false when a run it set out to end did not end, or
// when it could not read which to end, each said with the cancel to run by
// hand.
func (t *Takeaways) endRuns(bead string) bool {
	byHand := fmt.Sprintf("%s --root <root>%s --reason \"<why>\"", t.script("run-cancel.sh"), t.dbFlag())
	runs, err := waits.RunsOf(t.Ledger, bead)
	if err != nil {
		t.say("could not read the runs beneath %s (%v), so none was ended and any of them may still run. End each by hand: %s", bead, err, byHand)
		return false
	}
	type live struct {
		root    string
		holders []string
	}
	var ends []live
	for _, run := range runs {
		if !run.Live {
			continue
		}
		holders, err := waits.RunHolders(t.Ledger, run.Root)
		if err != nil {
			t.say("could not read whose runs are beneath %s (%v), so none was ended and any of them may still run. End each by hand: %s", bead, err, byHand)
			return false
		}
		ends = append(ends, live{root: run.Root, holders: holders})
	}
	ended := true
	for _, e := range ends {
		if slices.ContainsFunc(e.holders, func(h string) bool { return slices.Contains(t.Self, h) }) {
			t.say("kept run %s of %s: this session holds a step of it and closes its own chain", e.root, bead)
			continue
		}
		args := []string{"--root", e.root}
		if t.DB != "" {
			args = append(args, "--db", t.DB)
		}
		args = append(args, "--reason", "takeaway --release on "+bead+" took its work out of play")
		if res := t.City.Script("run-cancel.sh", args...); res.Failure() != "" {
			ended = false
			t.say("run %s of %s did not end (%s). End it by hand: %s --root %s%s --reason \"<why>\"", e.root, bead, res.Failure(), t.script("run-cancel.sh"), e.root, t.dbFlag())
			continue
		}
		t.say("ended run %s of %s through gascity", e.root, bead)
	}
	return ended
}

// pending is the bead's own waits that have not landed, as gctk bead holds
// answers them. A wait onto a bead in another store holds nothing, so it is
// none of them.
func (t *Takeaways) pending(bead string) ([]waits.Wait, error) {
	snap, err := waits.Read(t.Ledger, bead)
	if err != nil {
		return nil, err
	}
	h, err := snap.Holds(bead)
	if err != nil {
		return nil, err
	}
	return h.Pending, nil
}

// holders is the sessions the session list names a claim's holder under, by
// any form a claim writes: the session's id, its session name, or its alias
// or the end of one, which an agent address is. The list holds every session
// that has not closed, asleep ones included.
func (t *Takeaways) holders(holder string) ([]string, error) {
	list, err := t.City.Sessions(context.Background())
	if err != nil {
		return nil, err
	}
	var out []string
	for _, s := range list {
		if s.Alias == holder || (s.Alias != "" && strings.HasSuffix(s.Alias, holder)) || s.SessionName == holder || s.ID == holder {
			id := s.ID
			if id == "" {
				id = s.SessionName
			}
			if id == "" {
				id = s.Alias
			}
			if !slices.Contains(out, id) {
				out = append(out, id)
			}
		}
	}
	return out, nil
}

// mine reports whether a claim's holder is a name this session goes by.
func (t *Takeaways) mine(holder string) bool {
	return holder != "" && (slices.Contains(t.Self, holder) || holder == t.Agent)
}

// read is the bead's row, closed or not, nil when its store does not hold it.
func (t *Takeaways) read(id string) (*ledger.Record, error) {
	rows, err := t.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, rec := range rows {
		if rec.ID == id {
			return rec, nil
		}
	}
	return nil, nil
}

// script is the path of one of the pack's scripts, for a command a message
// names.
func (t *Takeaways) script(name string) string {
	if t.Scripts == "" {
		return "\"$(gc <binding> scripts-dir)/" + name + "\""
	}
	return filepath.Join(t.Scripts, name)
}

// dbFlag is the store flag a remedy names, empty when the caller named none.
func (t *Takeaways) dbFlag() string {
	if t.DB == "" {
		return ""
	}
	return " --db " + t.DB
}

// closedSkip says that a closed bead keeps its disposition: the release writes
// no park and still ends the run beneath it.
func (r *take) closedSkip(rec *ledger.Record, when string) string {
	successor := ""
	if edges, err := rec.Edges(); err == nil {
		for _, e := range edges {
			if (e.Type == "duplicates" || e.Type == "supersedes") && e.ID != "" {
				successor = ", superseded by " + e.ID
				break
			}
		}
	}
	return fmt.Sprintf("%s %s%s: its disposition stands, so the release writes no reopen, no unassign and no route clear, and the run beneath it is still ended", r.bead, when, successor)
}

// destination is where a release sends the bead, as a phrase, empty for
// nowhere.
func (r *take) destination() string {
	switch {
	case r.req.Route != "":
		return " to " + r.req.Route
	case r.req.Assign != "":
		return " to " + r.req.Assign
	}
	return ""
}

// released says what a release wrote beside the headline.
func (r *take) released() string {
	if r.req.Release && r.park {
		return " and the release"
	}
	return ""
}

func under(assignee string) string {
	if assignee == "" {
		return ""
	}
	return " under " + assignee
}

// value is a key's value on rec through its reading face, empty when rec does
// not carry it or it does not decode.
func value(v ledger.View[string], rec *ledger.Record) string {
	s, _, _ := v.Get(rec)
	return strings.TrimSpace(s)
}

// prefixOf is the store prefix a bead id begins with: the text before its
// first dash.
func prefixOf(id string) string {
	p, _, _ := strings.Cut(id, "-")
	return p
}
