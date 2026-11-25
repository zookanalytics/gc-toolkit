package arm

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	prrecord "github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
	"github.com/zookanalytics/gc-toolkit/services/gctk/waits"
)

// The start's time. The order that runs it kills it at its timeout
// (orders/deferred-dispatch.toml, 600s), and a sling killed part way has
// minted its input convoy and spent an attempt, so the start begins no sling
// once less than one sling's allowance is left before its deadline, which sits
// below that timeout. The arms it leaves stay armed for the next pass.
const (
	passDeadline   = 7 * time.Minute
	slingAllowance = 90 * time.Second
)

// What the start does with an arm, its Act's action.
const (
	ActRetire    = "retire"    // the bead closed or another path delivered its work: the arm is cleared, nothing slung
	ActStart     = "start"     // slung, and the arm cleared; in a dry run, what would be slung
	ActSent      = "sent"      // the work is sent already: the arm is cleared, nothing slung
	ActHold      = "hold"      // something holds the bead, and the arm stays
	ActAsk       = "ask"       // a person is asked, and the arm stays
	ActLeave     = "leave"     // left for the next pass, the arm untouched
	ActWithdrawn = "withdrawn" // the arm was removed after the pass listed it, and nothing was sent
	ActFail      = "fail"      // a read, a write, a sling or an ask failed, or the record is malformed, and the arm stays
)

// Act is what the start did with one arm, or in a dry run would do: the
// action, which case of it, why in words, the formula a start pours, and the
// workflow roots it read to decide.
type Act struct {
	Action  string   `json:"action"`
	Case    string   `json:"case,omitempty"`
	Why     string   `json:"why"`
	Formula string   `json:"formula,omitempty"`
	Roots   []string `json:"roots,omitempty"`
}

// Line is one arm's line: the answer gctk bead holds gives for the bead, or why
// it could not answer, with the start's act beside it.
type Line struct {
	ID    string
	Holds *waits.Holds
	Error string
	Arm   *record.Arm
	Start Act
}

// MarshalJSON prints a line as gctk bead holds prints its answer, with "start"
// added: the whole answer when there is one, and {"id", "error", "arm"} when
// the read could not answer.
func (l Line) MarshalJSON() ([]byte, error) {
	start, err := json.Marshal(l.Start)
	if err != nil {
		return nil, err
	}
	var head []byte
	if l.Holds != nil {
		head, err = json.Marshal(l.Holds)
	} else {
		head, err = json.Marshal(struct {
			ID    string      `json:"id"`
			Error string      `json:"error,omitempty"`
			Arm   *record.Arm `json:"arm"`
		}{l.ID, l.Error, l.Arm})
	}
	if err != nil {
		return nil, err
	}
	head = bytes.TrimSuffix(bytes.TrimSpace(head), []byte("}"))
	return append(append(append(head, []byte(`,"start":`)...), start...), '}'), nil
}

// Summary counts the start's acts by action.
type Summary map[string]int

// Failed is how many acts failed.
func (s Summary) Failed() int { return s[ActFail] }

// String is the pass's one line.
func (s Summary) String() string {
	var parts []string
	for _, act := range []string{ActStart, ActSent, ActRetire, ActWithdrawn, ActHold, ActAsk, ActLeave, ActFail} {
		parts = append(parts, fmt.Sprintf("%d %s", s[act], act))
	}
	return strings.Join(parts, ", ")
}

// StartOptions is one pass's options: a dry run, which writes, slings and asks
// nothing and takes no lock, and the rig gc sling's --rig names, when one does.
type StartOptions struct {
	DryRun bool
	Rig    string
}

// ErrListing is a start that could not list the store's armed beads, which is
// never an empty queue.
var ErrListing = errors.New("could not list the armed beads")

// StartArmed is one pass over the store's armed beads. It retires each arm
// whose dispatch is no longer owed (retireCase), then starts each armed bead
// the pool's own serve rule would serve and nothing bd cannot judge holds, each
// exactly once, under its dispatch lock. It hands emit one Line per armed bead,
// and returns the counts.
func (a *Arms) StartArmed(opts StartOptions, emit func(Line)) (Summary, error) {
	began := a.Now()
	sum := Summary{}
	out := func(l Line) {
		sum[l.Start.Action]++
		emit(l)
	}
	armed, err := a.Ledger.Find(record.Armed().WithClosed())
	if err != nil {
		return sum, fmt.Errorf("%w: %v", ErrListing, err)
	}
	if len(armed) == 0 {
		return sum, nil
	}
	ids := make([]string, 0, len(armed))
	for _, r := range armed {
		ids = append(ids, r.ID)
	}
	snap, holdsErr := waits.Read(a.Ledger, ids...)
	ready, readyErr := record.Ready(a.Ledger, serveRule)
	readyAt := map[string]int{}
	for i, r := range ready {
		readyAt[r.ID] = i + 1
	}

	type queued struct {
		r *ledger.Record
		l Line
	}
	var starts []queued
	for _, r := range armed {
		l := Line{ID: r.ID, Arm: record.Of(r)}
		h, herr := waits.Holds{}, holdsErr
		if herr == nil {
			h, herr = snap.Holds(r.ID)
		}
		if herr != nil {
			l.Error = herr.Error()
		} else {
			l.Holds = &h
		}
		if act, retire := retireCase(r); retire {
			l.Start = a.retire(r.ID, act, opts.DryRun)
			out(l)
			continue
		}
		if act, held := a.judge(r, l.Arm, h, herr, readyErr, readyAt[r.ID] > 0); held {
			l.Start = act
			out(l)
			continue
		}
		starts = append(starts, queued{r, l})
	}
	slices.SortStableFunc(starts, func(x, y queued) int { return readyAt[x.r.ID] - readyAt[y.r.ID] })
	for _, q := range starts {
		if !opts.DryRun && a.Now().Add(slingAllowance).After(began.Add(passDeadline)) {
			q.l.Start = Act{Action: ActLeave, Case: "deadline",
				Why: fmt.Sprintf("the pass has less than one sling's allowance (%s) left before its deadline, %s after it began, so the next pass sends it", slingAllowance, passDeadline)}
			out(q.l)
			continue
		}
		q.l.Start = a.start(q.r, opts)
		out(q.l)
	}
	return sum, nil
}

// closer is the validating closer's formula, which checks a bead once the work
// it waits on lands and puts a bead that carries a merge_result to a person
// rather than closing it.
const closer = "mol-validate-close"

// retireCase is the act that retires an arm on a bead whose dispatch is no
// longer owed, and whether there is one: the bead has closed, or it carries a
// merge_result, so another path has delivered its work and the arm would pour
// work on it again. Either retires the arm whatever holds the bead. The
// closer's arm pours no work, so on a bead that carries a merge_result it is
// still owed, and the start's holds judge it as they judge any other.
func retireCase(r *ledger.Record) (Act, bool) {
	if r.Status() == "closed" {
		return Act{Action: ActRetire, Case: "closed", Why: "the bead closed with a dispatch still armed, so none is owed"}, true
	}
	if mr, _, _ := prrecord.Result.Get(r); strings.TrimSpace(mr) != "" {
		if arm := record.Of(r); arm != nil && arm.Formula() == closer {
			return Act{}, false
		}
		return Act{Action: ActRetire, Case: "delivered",
			Why: fmt.Sprintf("another path already delivered its work (merge_result=%s), so the arm retires without a sling", strings.TrimSpace(mr))}, true
	}
	return Act{}, false
}

// retire clears the arm the act names, under the bead's lock, once a fresh read
// shows the bead still armed and its dispatch still not owed. A dry run reads
// and writes nothing more.
func (a *Arms) retire(id string, act Act, dryRun bool) Act {
	if dryRun {
		return act
	}
	release, holder, err := a.takeLock(id, 0)
	if err != nil {
		return Act{Action: ActFail, Case: "lock", Why: err.Error()}
	}
	if release == nil {
		return Act{Action: ActLeave, Case: "locked", Why: fmt.Sprintf("its dispatch lock is held by %s, so the next pass retires it", holder)}
	}
	defer release()
	r, err := a.read(id)
	if err != nil {
		return Act{Action: ActFail, Case: "read", Why: err.Error()}
	}
	if !record.Present(r) {
		return Act{Action: ActWithdrawn, Why: "its arm was removed after this pass listed it"}
	}
	fresh, still := retireCase(r)
	if !still {
		return Act{Action: ActLeave, Case: "changed", Why: "the bead changed after this pass listed it, so the next pass reads it again"}
	}
	if err := a.clear(id, fresh.Why); err != nil {
		return Act{Action: ActFail, Case: "write", Why: err.Error()}
	}
	return fresh
}

// judge is the act on an arm the start does not send this pass, and whether it
// holds one. The pool's serve rule is bd's ready read with the flags Gas City
// renders for a pool's routed demand, so the arm sends what the pool would
// serve. Beside it the start holds back what bd cannot judge: a waits-for edge
// of the bead's own, which gctk bead holds answers unjudged, and a wait edge
// into another store, which bd never holds a bead on. It also holds a bead a
// hold holds, whatever its value and in any spelling (holdLabel), as Gas City
// drops a held row from a pool's demand, since no bd flag names every hold.
func (a *Arms) judge(r *ledger.Record, arm *record.Arm, h waits.Holds, holdsErr, readyErr error, ready bool) (Act, bool) {
	switch status := r.Status(); {
	case arm != nil && arm.Malformed() != "":
		return Act{Action: ActFail, Case: "malformed", Why: "its arm does not decode, so nothing is slung: " + arm.Malformed()}, true
	case status != "open":
		return Act{Action: ActHold, Case: "status",
			Why: fmt.Sprintf("it is at status %s, and the start sends an open bead alone: return it to open, or disarm it", status)}, true
	case r.Assignee() != "":
		return Act{Action: ActHold, Case: "assigned",
			Why: fmt.Sprintf("it is assigned to %s, and the start sends no assigned bead: clear the assignee, or disarm it", r.Assignee())}, true
	case r.IssueType() == "epic":
		return Act{Action: ActHold, Case: "epic", Why: "it is an epic, which no pool serves: its members are its work"}, true
	}
	if l := holdLabel(r.Labels()); l != "" {
		return Act{Action: ActHold, Case: "label", Why: fmt.Sprintf("its %s label holds it, and no pool serves it while it carries one", l)}, true
	}
	if holdsErr != nil {
		return Act{Action: ActFail, Case: "read", Why: "what holds it could not be read, so it stays armed: " + holdsErr.Error()}, true
	}
	if h.Arm == nil {
		return Act{Action: ActWithdrawn, Why: "its arm was removed after this pass listed it, so nothing is sent"}, true
	}
	if h.Status == waits.Unjudged {
		return Act{Action: ActHold, Case: "unjudged",
			Why: fmt.Sprintf("its waits-for edge onto %s is one the store cannot judge yet, so the start holds it", waitIDs(h.Waits))}, true
	}
	if len(h.Foreign) > 0 {
		return Act{Action: ActHold, Case: "foreign",
			Why: fmt.Sprintf("it has a wait edge onto %s, which its store does not hold and bd never holds it on, so the start holds it until that wait moves into this store or the arm is removed", foreignIDs(h.Foreign))}, true
	}
	if readyErr != nil {
		return Act{Action: ActFail, Case: "read", Why: "bd's ready read failed, so nothing is sent: " + readyErr.Error()}, true
	}
	if !ready || h.Status != waits.Clear {
		switch h.Status {
		case waits.Blocked, waits.Held:
			return Act{Action: ActHold, Case: string(h.Status), Why: describeWaits(h.Waits) + " holds it"}, true
		}
		why := "bd does not report it ready, so the pool would not serve it either"
		if h.InFlight != "" {
			why += fmt.Sprintf(": it is in flight (%s), and bd's readiness still holds it for a wait on an ancestor", h.InFlight)
		}
		return Act{Action: ActHold, Case: "unready", Why: why}, true
	}
	return Act{}, false
}

// start sends one armed bead nothing holds, under its lock: it reads the bead
// once more, resolves the formula, finds the pour an earlier attempt made by
// the arm's token, asks a person at the cap, counts the attempt, slings, and
// reads the sling's exit. A dry run says what it would do from the row the pass
// listed, and takes no lock.
func (a *Arms) start(listed *ledger.Record, opts StartOptions) Act {
	id, r := listed.ID, listed
	if !opts.DryRun {
		release, holder, err := a.takeLock(id, 0)
		if err != nil {
			return Act{Action: ActFail, Case: "lock", Why: err.Error()}
		}
		if release == nil {
			return Act{Action: ActLeave, Case: "locked", Why: fmt.Sprintf("its dispatch lock is held by %s, so the next pass sends it", holder)}
		}
		defer release()
		if r, err = a.read(id); err != nil {
			return Act{Action: ActFail, Case: "read", Why: "it could not be read again before its sling, so it stays armed: " + err.Error()}
		}
	}
	arm := record.Of(r)
	if arm == nil {
		return Act{Action: ActWithdrawn, Why: "its arm was removed after this pass listed it, so nothing is sent"}
	}
	if act, retire := retireCase(r); retire {
		return a.retireLocked(id, act, opts.DryRun)
	}
	if act, held := a.judge(r, arm, waits.Holds{Status: waits.Clear, Arm: arm}, nil, nil, true); held {
		if act.Action == ActHold {
			act.Why += ", which a read after this pass listed it found"
		}
		return act
	}
	formula := arm.Formula()
	if formula == "" {
		f, err := a.defaultFormula(gascity.Sling{Rig: opts.Rig, Target: arm.Target, Bead: id})
		if err != nil || f == "" {
			why := fmt.Sprintf("its arm names no formula, and %s's default formula could not be read", arm.Target)
			if err == nil {
				why = fmt.Sprintf("its arm names no formula, and %s names no default formula to pour", arm.Target)
			} else {
				why += ": " + err.Error()
			}
			return Act{Action: ActFail, Case: "formula", Why: why}
		}
		formula = f
	}
	token := "arm:" + id + "@" + arm.ArmedAt
	if arm.Attempts() > 0 {
		roots, err := a.Ledger.Find(ledger.Titled(token).WithClosed())
		if err != nil {
			return Act{Action: ActFail, Case: "read", Formula: formula, Why: "the pours of its earlier attempts could not be read, so it stays armed: " + err.Error()}
		}
		if landed := landed(roots, token); len(landed) > 0 {
			return a.sent(id, formula, landed, fmt.Sprintf("an earlier attempt's pour %s landed, so the arm retires without a second pour", strings.Join(landed, ", ")), opts.DryRun)
		}
	}
	if arm.Capped() {
		return a.askCap(id, arm, formula, opts.DryRun)
	}
	if opts.DryRun {
		return Act{Action: ActStart, Formula: formula, Why: fmt.Sprintf("nothing holds it, so a pass slings it to %s on %s", arm.Target, formula)}
	}
	w := a.Ledger.Write(id)
	record.SetAttempts(w, arm.Attempts()+1)
	if err := a.Ledger.Commit(w); err != nil {
		return Act{Action: ActFail, Case: "write", Formula: formula, Why: "its attempt could not be counted, so nothing was slung: " + err.Error()}
	}
	res := a.Runtime.Sling(gascity.Sling{Rig: opts.Rig, Target: arm.Target, Bead: id, Formula: formula, Title: formula + " " + token})
	switch {
	case res.Code == 0 && res.Err == nil:
		why := fmt.Sprintf("dispatched to %s on %s by the deferred-dispatch order", arm.Target, formula)
		if err := a.clear(id, why); err != nil {
			return Act{Action: ActFail, Case: "write", Formula: formula,
				Why: fmt.Sprintf("slung to %s on %s, and the arm could not be cleared, so the next pass finds the pour by its token and retires it: %v", arm.Target, formula, err)}
		}
		return Act{Action: ActStart, Formula: formula, Why: why}
	case res.Code == 3:
		return a.liveOnExit3(id, formula, arm.Attempts()+1, res)
	}
	return Act{Action: ActFail, Case: "sling", Formula: formula,
		Why: fmt.Sprintf("gc sling failed (%s), so it stays armed with %d attempt(s) counted", res.Failure(), arm.Attempts()+1)}
}

// retireLocked retires an arm a start found closed or delivered on its fresh
// read, under the lock it already holds.
func (a *Arms) retireLocked(id string, act Act, dryRun bool) Act {
	if dryRun {
		return act
	}
	if err := a.clear(id, act.Why); err != nil {
		return Act{Action: ActFail, Case: "write", Why: err.Error()}
	}
	return act
}

// liveOnExit3 reads gc sling's exit 3, which it gives only when a live
// workflow works the bead already, naming each. One that Gas City did not
// stamp as failed means the work is sent. When each carries the stamp, the
// attempt failed, so the arm stays with it counted, as after a sling that
// failed, and the cap on attempts asks a person once they run out.
func (a *Arms) liveOnExit3(id, formula string, attempts int, res gascity.SlingResult) Act {
	if len(res.Live) == 0 {
		return Act{Action: ActFail, Case: "sling", Formula: formula,
			Why: "gc sling exited 3 and named no live workflow, so it stays armed: " + res.Tail()}
	}
	rows, err := a.Ledger.Find(ledger.ByID(res.Live...).WithClosed())
	if err != nil {
		return Act{Action: ActFail, Case: "read", Formula: formula, Roots: res.Live,
			Why: "gc sling named live workflows that could not be read, so it stays armed: " + err.Error()}
	}
	held := map[string]bool{}
	for _, r := range rows {
		held[r.ID] = true
	}
	for _, root := range res.Live {
		if !held[root] {
			return Act{Action: ActFail, Case: "read", Formula: formula, Roots: res.Live,
				Why: fmt.Sprintf("gc sling named the live workflow %s, which this store does not hold, so whether its pour failed is unknown, and it stays armed", root)}
		}
	}
	if sent := landed(rows, ""); len(sent) > 0 {
		return a.sent(id, formula, res.Live, fmt.Sprintf("gc sling found %s working it already, so the arm retires without a second pour", strings.Join(sent, ", ")), false)
	}
	return Act{Action: ActFail, Case: "sling", Formula: formula, Roots: res.Live,
		Why: fmt.Sprintf("gc sling exited 3 naming only pours Gas City stamped as failed (%s), so the attempt failed, and it stays armed with %d attempt(s) counted", strings.Join(res.Live, ", "), attempts)}
}

// sent retires the arm on a bead whose work is sent already.
func (a *Arms) sent(id, formula string, roots []string, why string, dryRun bool) Act {
	act := Act{Action: ActSent, Formula: formula, Roots: roots, Why: why}
	if dryRun {
		return act
	}
	if err := a.clear(id, why); err != nil {
		return Act{Action: ActFail, Case: "write", Formula: formula, Roots: roots, Why: err.Error()}
	}
	return act
}

// FailedPour reports whether Gas City stamped root as a pour that failed part
// way (molecule_failed=true). The start reads a root its token titles, or one
// gc sling's exit 3 names, by it, and Accept a root its token titles: a failed
// pour is an attempt that failed, which is tried again, and any other root is
// the pour that landed. A stamp on a bead under the root does not show that
// the root's own pour failed, since Gas City stamps a fanout it pours into a
// live run when that pour fails.
func FailedPour(root *ledger.Record) bool {
	v, _, _ := moleculeFailedKey.Get(root)
	return strings.TrimSpace(v) == "true"
}

// landed is the roots in rows whose pour landed, in id order: each that
// carries token in its title, every one when token is empty, that Gas City did
// not stamp as failed.
func landed(rows []*ledger.Record, token string) []string {
	var out []string
	for _, r := range rows {
		if token != "" && !strings.Contains(r.Title(), token) {
			continue
		}
		if !FailedPour(r) {
			out = append(out, r.ID)
		}
	}
	slices.Sort(out)
	return out
}

// askKey is the key the start asks a person about an arm under.
func askKey(id string) string { return "deferred-dispatch-sling-failed." + id }

// askCap keeps the arm and asks a person about a bead whose attempts have
// reached the cap, instead of slinging it again.
func (a *Arms) askCap(id string, arm *record.Arm, formula string, dryRun bool) Act {
	act := Act{Action: ActAsk, Case: "cap", Formula: formula,
		Why: fmt.Sprintf("%d attempts have reached the cap of %d, so a person is asked instead of slinging it again", arm.Attempts(), record.Cap())}
	if dryRun {
		return act
	}
	msg := fmt.Sprintf("Deferred dispatch has tried to sling armed bead %s to %s on %s %d times, and its cap is %d, so it asks a person instead of slinging again. Each attempt mints an input convoy. A common cause is work another path already delivered, or a target that refuses the pour. Look at why the slings failed, then disarm it (gctk bead disarm %s --reason \"<why>\"), or disarm it and arm it again, which starts its attempts over (gctk bead arm %s --target %s --on %s --reason \"<why>\").",
		id, arm.Target, formula, arm.Attempts(), record.Cap(), id, id, arm.Target, formula)
	return a.ask(id, act, fmt.Sprintf("deferred dispatch has failed %d times: disarm or re-arm", arm.Attempts()), msg)
}

// ask puts the question to a person: a conversation on a bead with an open
// child, through gc-helm.sh open, since a gate on a parent would hold its
// unstarted parts too, and otherwise a human gate on the bead, through
// human-gate.sh, which holds the bead while it is open, so the start sends
// nothing until it is answered. A read of the children that fails files the
// gate. An ask that does not reach a person keeps the arm, and the next pass
// asks again.
func (a *Arms) ask(id string, act Act, reason, msg string) Act {
	var res gascity.Result
	if a.hasOpenChild(id) {
		res = a.Runtime.Script("gc-helm.sh", "open", id, "--reason", reason, "--body", msg)
	} else {
		res = a.Runtime.Script("human-gate.sh", "--subject", id, "--key", askKey(id), "--quiet-window", "86400",
			"--message", msg+" Then clear this gate. It holds "+id+", so the start sends nothing while it is open, and a gate cleared while the same cause stands is asked again by a later pass.")
	}
	if f := res.Failure(); f != "" {
		return Act{Action: ActFail, Case: "ask", Formula: act.Formula, Roots: act.Roots,
			Why: act.Why + ", and the ask did not reach one (" + f + "), so it stays armed and the next pass asks again"}
	}
	return act
}

// hasOpenChild reports whether a bead the store lists under id, whose own
// parent-child edge names id, is neither closed nor pinned.
func (a *Arms) hasOpenChild(id string) bool {
	kids, err := a.Ledger.Find(ledger.Under(id))
	if err != nil {
		return false
	}
	for _, k := range kids {
		parents, err := k.Parents()
		if err != nil || !slices.Contains(parents, id) {
			continue
		}
		if st := k.Status(); st != "closed" && st != "pinned" {
			return true
		}
	}
	return false
}
