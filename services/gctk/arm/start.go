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

// StartArmed is one pass over the store's armed beads. It retires the arm on
// each bead that has closed or whose work another path delivered, then starts
// each armed bead the pool's own serve rule would serve and nothing bd cannot
// judge holds, each exactly once, under its dispatch lock. It hands emit one
// Line per armed bead, and returns the counts.
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

// retireCase is the act that retires an arm on a bead whose dispatch is no
// longer owed, and whether there is one: the bead has closed, or it carries a
// merge_result, so another path has delivered its work. Either retires the arm
// whatever holds the bead.
func retireCase(r *ledger.Record) (Act, bool) {
	if r.Status() == "closed" {
		return Act{Action: ActRetire, Case: "closed", Why: "the bead closed with a dispatch still armed, so none is owed"}, true
	}
	if mr, _, _ := mergeResultKey.Get(r); strings.TrimSpace(mr) != "" {
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
// into another store, which bd never holds a bead on. It also holds a bead that
// carries one of Gas City's hold labels in any spelling, as Gas City's hook
// does after bd's exact comparison.
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
	if act, held := a.judge(r, arm, waits.Holds{Status: waits.Clear}, nil, nil, true); held {
		if act.Action == ActHold {
			act.Why += ", which a read after this pass listed it found"
		}
		return act
	}
	formula := arm.Formula()
	if formula == "" {
		f, err := a.defaultFormula(arm.Target)
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
		pours, err := a.pours(roots, token)
		if err != nil {
			return Act{Action: ActFail, Case: "read", Formula: formula, Why: err.Error()}
		}
		if landed := pours.landed(); len(landed) > 0 {
			return a.sent(id, formula, landed, fmt.Sprintf("an earlier attempt's pour %s landed, so the arm retires without a second pour", strings.Join(landed, ", ")), opts.DryRun)
		}
		if open := pours.openUnfinished(); len(open) > 0 {
			return a.askUnfinished(id, formula, pours.only(open), opts.DryRun)
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
		return a.liveOnExit3(id, formula, res)
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
// workflow works the bead already, naming each. One that is not an unfinished
// pour means the work is sent. When each is an unfinished pour, none of them can
// finish, and gc sling refuses another pour while it is open, so a person is
// asked.
func (a *Arms) liveOnExit3(id, formula string, res gascity.SlingResult) Act {
	if len(res.Live) == 0 {
		return Act{Action: ActFail, Case: "sling", Formula: formula,
			Why: "gc sling exited 3 and named no live workflow, so it stays armed: " + res.Tail()}
	}
	rows, err := a.Ledger.Find(ledger.ByID(res.Live...).WithClosed())
	if err != nil {
		return Act{Action: ActFail, Case: "read", Formula: formula, Roots: res.Live,
			Why: "gc sling named live workflows that could not be read, so it stays armed: " + err.Error()}
	}
	pours, err := a.pours(rows, "")
	if err != nil {
		return Act{Action: ActFail, Case: "read", Formula: formula, Roots: res.Live, Why: err.Error()}
	}
	for _, root := range res.Live {
		if _, ok := pours[root]; !ok {
			return Act{Action: ActFail, Case: "read", Formula: formula, Roots: res.Live,
				Why: fmt.Sprintf("gc sling named the live workflow %s, which this store does not hold, so whether its pour finished is unknown, and it stays armed", root)}
		}
	}
	if sent := pours.landed(); len(sent) > 0 {
		return a.sent(id, formula, res.Live, fmt.Sprintf("gc sling found %s working it already, so the arm retires without a second pour", strings.Join(sent, ", ")), false)
	}
	return a.askUnfinished(id, formula, pours, false)
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

// pour is one workflow root a start read: whether it is still open, whether it
// is an unfinished pour, and the marks that say so.
type pour struct {
	id       string
	open     bool
	finished bool
	why      string
}

type pours map[string]pour

// pours reads each root in rows that carries token in its title, every root
// when token is empty: whether it is open, and whether Gas City left its pour
// unfinished. A root is an unfinished pour when it carries molecule_failed=true,
// or when it or a bead poured under it still carries the fence
// gc.instantiating, whatever their status. A failure stamp on a bead under it
// does not show that the root's own pour failed, since Gas City stamps a fanout
// it pours into a live run when that pour fails.
func (a *Arms) pours(rows []*ledger.Record, token string) (pours, error) {
	out := pours{}
	for _, r := range rows {
		if token != "" && !strings.Contains(r.Title(), token) {
			continue
		}
		p := pour{id: r.ID, open: r.Status() != "closed", finished: true}
		var marks []string
		if v, _, _ := moleculeFailedKey.Get(r); strings.TrimSpace(v) == "true" {
			marks = append(marks, "it carries molecule_failed=true")
		}
		if v, _, _ := instantiatingKey.Get(r); strings.TrimSpace(v) != "" {
			marks = append(marks, "it is still fenced by gc.instantiating")
		}
		under, err := a.Ledger.Find(ledger.Matching(rootBeadKey, r.ID).WithClosed())
		if err != nil {
			return nil, fmt.Errorf("the beads poured under %s could not be read, so whether its pour finished is unknown, and it stays armed: %v", r.ID, err)
		}
		var fenced []string
		for _, b := range under {
			if v, _, _ := instantiatingKey.Get(b); strings.TrimSpace(v) != "" {
				fenced = append(fenced, b.ID)
			}
		}
		if len(fenced) > 0 {
			marks = append(marks, "gc.instantiating still fences "+strings.Join(fenced, ", ")+" under it")
		}
		if len(marks) > 0 {
			p.finished, p.why = false, strings.Join(marks, ", and ")
		}
		out[r.ID] = p
	}
	return out, nil
}

// landed is the roots whose pour finished, open or closed, in id order.
func (ps pours) landed() []string { return ps.select_(func(p pour) bool { return p.finished }) }

// openUnfinished is the open roots whose pour did not finish, in id order.
func (ps pours) openUnfinished() []string {
	return ps.select_(func(p pour) bool { return !p.finished && p.open })
}

// only is the pours ids names.
func (ps pours) only(ids []string) pours {
	out := pours{}
	for _, id := range ids {
		out[id] = ps[id]
	}
	return out
}

func (ps pours) select_(keep func(pour) bool) []string {
	var out []string
	for id, p := range ps {
		if keep(p) {
			out = append(out, id)
		}
	}
	slices.Sort(out)
	return out
}

// askKey is the key the start asks a person about an arm under.
func askKey(id string) string { return "deferred-dispatch-sling-failed." + id }

// askUnfinished keeps the arm and asks a person about the pours Gas City left
// unfinished, naming each root and the command that closes it with its steps.
// The start ends no Gas City run itself.
func (a *Arms) askUnfinished(id, formula string, ps pours, dryRun bool) Act {
	roots := ps.select_(func(pour) bool { return true })
	var parts, closes []string
	for _, r := range roots {
		parts = append(parts, fmt.Sprintf("%s (%s)", r, ps[r].why))
		closes = append(closes, "gc convoy delete "+r+" --force")
	}
	act := Act{Action: ActAsk, Case: "unfinished", Formula: formula, Roots: roots,
		Why: fmt.Sprintf("Gas City left its pour of %s unfinished: %s, and gc sling refuses another pour of %s while such a root is open, so a person is asked", formula, strings.Join(parts, "; "), formula)}
	if dryRun {
		return act
	}
	msg := fmt.Sprintf("Deferred dispatch cannot send armed bead %s on %s: Gas City left its pour unfinished, at %s. gc sling refuses another pour of %s on %s while such a root is open, and the start ends no Gas City run itself. Close each root and its steps (%s), then clear this gate, and the next pass sends %s.",
		id, formula, strings.Join(parts, "; "), formula, id, strings.Join(closes, "; "), id)
	return a.ask(id, act, "deferred dispatch found an unfinished pour on it", msg)
}

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
