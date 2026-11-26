package reaction

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/arm"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gascity"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/standing/person"
)

// Accept answers a first reaction's recommendation: it clears the human gate
// under the key first-reaction that put gc.recommended_formula to the operator,
// and dispatches that formula at the bead. A sitting's sign-off runs it when the
// operator's ruling takes the recommendation (converse-signoff.sh --accept), so
// every dispatch of a recommendation goes through this one writer and its lock.
// It clears that one gate and nothing else: separate situations on one bead are
// separate gates, and each gate's close does something of its own.
//
// It takes the recommendation only while all three hold: the bead carries it;
// its gate is open and unassigned, or closed with an acceptance an earlier
// Accept did not finish; and no other open human gate blocks the bead, since
// the bead's next step waits for each gate that blocks it and a formula's
// sling reads no blocks edge.
//
// Every Accept on a bead runs under the bead's acceptance lock, from before its
// live read of those conditions to its last write. Its first write removes the
// bead's arm, because the gate's answer could release the bead to that arm ahead
// of Accept's own pour. On an open gate it records the acceptance's dispatch
// input on the gate (gc.acceptance: its token, the formula and each var),
// answers the gate `ruled: accepted <formula> accept:<token>`, then reads which
// answer the gate took. bd's resolve exits 0 on a gate already closed and
// leaves its answer, so that read settles which answer reached the gate first,
// and the first stands: a sitting's ruling, a filer's withdrawal or a person's
// resolve, beside which Accept slings nothing and reopens nothing. It then reads
// that no open human gate blocks the bead, slings the formula titled
// `<formula> accept:<token>` with each var, lifts the bead's hold:mayor, since an
// Accept is a placement, and records the dispatch by clearing the
// recommendation. A gate filed in the meantime, or a sling that landed no pour
// under the token, reopens the gate from Accept's own answer. A run that
// stopped after its answer leaves the acceptance unfinished, and the next run
// finishes it under the same token: it records the dispatch when a pour under
// the token landed, and otherwise reads that no gate blocks the bead and slings
// the vars the gate records under the token, whoever runs it.

// The keys an acceptance writes, which this package alone writes.
// converse-signoff.sh still reads the dispatch's record in shell
// (docs/gctk-architecture.md, Debt), so it stays registered in
// lifecycle/lifecycle.toml too.
var (
	dispatchedKey = ledger.Declare("gc.recommended_formula_dispatched", ledger.String,
		"The formula gctk reaction accept slung at the bead for its recommendation, written in the update that "+
			"clears gc.recommended_formula, so absent means no Accept has recorded a dispatch. An Accept that finds "+
			"it and no recommendation says the recommendation was dispatched, and so does a sitting's sign-off, "+
			"which converse-signoff.sh reads in shell. Never cleared. A formula name.")
	acceptanceKey = ledger.Declare("gc.acceptance", ledger.JSON[acceptance](),
		"On the human gate under the key first-reaction, the dispatch input of the acceptance that answers it: "+
			"a JSON object {token, formula, vars}, with vars the <key>=<value> strings its sling carries. "+
			"gctk reaction accept writes it before the answer that names the token, and a run that finishes that "+
			"acceptance slings the vars recorded under the token, so a finishing run given no var dispatches what "+
			"the operator accepted. A record whose token no answer on the gate names binds nothing, and the next "+
			"acceptance overwrites it. Never cleared.")
)

// acceptance is the dispatch input of one acceptance, as its gate records it.
type acceptance struct {
	Token   string   `json:"token"`
	Formula string   `json:"formula"`
	Vars    []string `json:"vars"`
}

// AcceptRequest is one acceptance: the bead, why, the conversation whose
// sitting's sign-off runs it, which it does not warn of, and each var the
// caller settled for the dispatch, as <key>=<value>.
type AcceptRequest struct {
	Bead, Reason, Conversation string
	Vars                       []string
}

// Accepted is what an acceptance did: the formula it dispatched and its token,
// whether it finished one an earlier run left, and, when that run had already
// poured, the root it recorded instead of slinging.
type Accepted struct {
	Formula, Token string
	Finished       bool
	Root           string
}

// Unaccepted is an acceptance that went no further, with the exit the command
// gives it: 2 for a call refused for what it asks or a bead with no
// recommendation, 3 for a lock that could not be taken, 4 for a refusal or a
// step that did not land, and 1 for a sling that poured nothing. Msg says what
// landed and what runs it again.
type Unaccepted struct {
	Code int
	Msg  string
}

func (e *Unaccepted) Error() string { return e.Msg }

func stop(code int, format string, args ...any) error {
	return &Unaccepted{Code: code, Msg: fmt.Sprintf(format, args...)}
}

// varForm is a var a caller settled: a key, then = and its value, on one line.
var varForm = regexp.MustCompile(`^[^=\n][^\n]*=[^\n]*$`)

// CheckVars refuses, with exit 2, a var that is not <key>=<value> on one line.
func CheckVars(vars []string) error {
	for _, v := range vars {
		if !varForm.MatchString(v) {
			return stop(2, "--var takes <key>=<value> on one line, not %q", v)
		}
	}
	return nil
}

// answerForm is an Accept's answer on a gate: the formula and the token.
var answerForm = regexp.MustCompile(`^ruled: accepted (\S+) accept:([0-9a-f]+)$`)

// Accept takes the bead's recommendation, as the package's account of an
// acceptance says.
func (r *Reactions) Accept(req AcceptRequest) (Accepted, error) {
	var out Accepted
	bead := strings.TrimSpace(req.Bead)
	if bead == "" {
		return out, stop(2, "accept needs <bead-id>")
	}
	if err := CheckVars(req.Vars); err != nil {
		return out, err
	}
	release, holder, err := r.acceptLock(bead)
	switch {
	case errors.Is(err, errLockDir):
		return out, stop(3, "cannot take %s's acceptance lock (%v). Accept refuses without it, because two Accepts on one bead could each dispatch it. Nothing dispatched", bead, err)
	case err != nil:
		return out, stop(3, "cannot take %s's acceptance lock (%v). Nothing dispatched", bead, err)
	case release == nil:
		return out, stop(4, "another Accept on %s holds its acceptance lock (%s), so this one refuses and writes nothing. Run it again once that one has finished", bead, holder)
	}
	defer release()

	// The live read of the three conditions, under the lock: a board row can be
	// stale and a command can be copied.
	row, err := r.readBead(bead)
	switch {
	case err != nil:
		return out, stop(4, "could not verify %s: the store did not answer (%v). Nothing dispatched", bead, err)
	case row == nil:
		return out, stop(4, "bead not found: %s, which its store does not hold. Nothing dispatched", bead)
	}
	formula := strings.TrimSpace(raw(recommendedFormulaKey, row))
	if formula == "" {
		if d := strings.TrimSpace(raw(dispatchedKey, row)); d != "" {
			return out, stop(2, "%s carries no gc.recommended_formula: its recommendation was dispatched (%s). Nothing to accept; nothing dispatched", bead, d)
		}
		return out, stop(2, "%s carries no gc.recommended_formula, so it is discuss-only. Engage it to decide. Nothing dispatched", bead)
	}
	out.Formula = formula
	gates, err := r.humanGates(row)
	if err != nil {
		return out, stop(4, "could not read the human gates on %s (%v), so whether Accept may answer cannot be told. Nothing dispatched", bead, err)
	}
	var others, recOpen, recAssigned []string
	for _, g := range gates {
		if g.Status() == "closed" {
			continue
		}
		switch {
		case g.AwaitID() != GateKey:
			others = append(others, fmt.Sprintf("%s (%s)", g.ID, nonBlank(g.Title(), "untitled")))
		case g.Assignee() != "":
			recAssigned = append(recAssigned, fmt.Sprintf("%s (assigned to %s)", g.ID, g.Assignee()))
		default:
			recOpen = append(recOpen, g.ID)
		}
	}
	if len(others) > 0 {
		return out, stop(4, "another human gate still blocks %s: %s. Accept answers only the recommendation, and %s's next step waits for every gate that blocks it, so Accept waits until those are cleared. Discuss it to answer them: gc-helm engage %s. Nothing dispatched", bead, strings.Join(others, "; "), bead, bead)
	}
	if len(recAssigned) > 0 {
		return out, stop(4, "the recommendation's gate %s is that person's to clear, not Accept's. Nothing dispatched", strings.Join(recAssigned, "; "))
	}
	recGates := recOpen
	var newest *ledger.Record
	if len(recGates) == 0 {
		// No open gate under the key: the newest gate under it is the
		// recommendation's, because no recommendation is older than the gate
		// that asks it. An Accept's answer there beside the recommendation is
		// an acceptance an earlier run did not finish.
		for _, g := range gates {
			if g.AwaitID() == GateKey && (newest == nil || g.CreatedAt() > newest.CreatedAt()) {
				newest = g
			}
		}
		if newest == nil {
			return out, stop(4, "no human gate under the key %s puts %s's recommendation (%s) to the operator, so nothing asks for an Accept. Discuss it to decide: gc-helm engage %s. Nothing dispatched", GateKey, bead, formula, bead)
		}
		recGates = []string{newest.ID}
		m := answerForm.FindStringSubmatch(newest.CloseReason())
		if m == nil || m[1] != formula {
			return out, stop(4, "the recommendation's gate %s on %s was answered: %q. That answer stands, and nothing asks for an Accept. Discuss it to decide: gc-helm engage %s. Nothing dispatched", newest.ID, bead, nonBlank(newest.CloseReason(), "no reason"), bead)
		}
		out.Token, out.Finished = m[2], true
	}
	r.warnLive(bead, req.Conversation, recGates)

	// The first write removes the bead's arm: the gate's answer could otherwise
	// release the bead to its arm ahead of Accept's own pour.
	if r.Disarm == nil {
		return out, stop(4, "Accept has no way to remove %s's arm, so nothing is dispatched or written. Nothing dispatched", bead)
	}
	if _, err := r.Disarm(bead, "accept: Accept dispatches "+formula+" at the bead itself"); err != nil {
		return out, stop(4, "Accept dispatches %s at %s itself, so its first write removes the arm that would start %s another way once the gate's answer releases it, and that disarm did not land (%s). Nothing is dispatched or written. Run it again once the arm can be removed: gctk reaction accept %s", formula, bead, bead, strings.TrimPrefix(err.Error(), "refused: "), bead)
	}

	vars := req.Vars
	if !out.Finished {
		if err := r.answer(bead, formula, vars, recGates, &out); err != nil {
			return out, err
		}
	} else {
		r.say("%s carries an acceptance an earlier Accept left unfinished (%s); finishing it", bead, out.Token)
		root, err := r.tokenRoot(out.Token)
		switch {
		case err != nil:
			return out, stop(4, "could not search for a root of acceptance %s on %s (%v), which proves nothing, so nothing is dispatched or written. Run it again once the store answers: gctk reaction accept %s", out.Token, bead, err, bead)
		case root != "":
			out.Root = root
			if _, err := r.liftHold(bead, ""); err != nil {
				return out, stop(4, "acceptance %s already dispatched %s at %s (root %s), but the write that lifts its hold:mayor did not land (%v), so the bead still waits in the placement queue. The next Accept finishes the lift and the record without a second dispatch: gctk reaction accept %s", out.Token, formula, bead, root, err, bead)
			}
			if err := r.markDispatched(bead, formula, out.Token, req.Reason); err != nil {
				return out, stop(4, "acceptance %s already dispatched %s at %s (root %s), but the record did not land (%v). The next Accept finishes the record without a second dispatch: gctk reaction accept %s", out.Token, formula, bead, root, err, bead)
			}
			if len(vars) > 0 {
				r.say("root %s keeps the vars it was poured with, so the --var given here does not reach it", root)
			}
			return out, nil
		}
		// No pour under the token landed, so this run slings, and it slings the
		// input the acceptance was made with, read off the gate, never this
		// run's own: a finishing run given no var would otherwise undo a var the
		// operator's ruling settled.
		in, ok, _ := acceptanceKey.Get(newest)
		if !ok || in.Token != out.Token || in.Formula != formula {
			return out, stop(4, "the recommendation's gate %s on %s records no dispatch input for acceptance %s, so the vars it was accepted with cannot be told, and nothing is dispatched or written. Reopen the gate and Accept again: gc bd reopen %s && gctk reaction accept %s", newest.ID, bead, out.Token, newest.ID, bead)
		}
		if len(req.Vars) > 0 && !slices.Equal(req.Vars, in.Vars) {
			return out, stop(4, "acceptance %s on %s was accepted with %s, and this run was given %s. An acceptance dispatches the input it was accepted with, so nothing is dispatched or written. Finish it as accepted, with those vars or none: gctk reaction accept %s. To dispatch other vars, reopen the gate first: gc bd reopen %s", out.Token, bead, varsSaid(in.Vars), varsSaid(req.Vars), bead, newest.ID)
		}
		vars = in.Vars
		if len(vars) > 0 {
			r.say("acceptance %s slings the vars it was accepted with: %s", out.Token, varsSaid(vars))
		}
	}

	// No open human gate may block the bead now. A gate filed between the live
	// read and the answer shows here, and the recommendation goes back on the
	// board rather than starting the work ahead of that gate.
	again, err := r.readBead(bead)
	if err == nil && again == nil {
		err = errors.New("its store no longer holds it")
	}
	var late []string
	if err == nil {
		gates, err = r.humanGates(again)
		for _, g := range gates {
			if g.Status() != "closed" {
				late = append(late, fmt.Sprintf("%s (%s)", g.ID, nonBlank(g.Title(), "untitled")))
			}
		}
	}
	if err != nil {
		return out, stop(4, "could not read the human gates on %s again after its acceptance %s (%v), so nothing is dispatched yet. The next Accept finishes it once the store answers: gctk reaction accept %s", bead, out.Token, err, bead)
	}
	if len(late) > 0 {
		back := r.reopen("Accept stood down: another human gate blocks the bead", recGates)
		return out, stop(4, "a human gate filed since Accept read %s blocks it: %s. Nothing is dispatched ahead of it.%s Discuss it: gc-helm engage %s", bead, strings.Join(late, "; "), back, bead)
	}

	// Dispatch the recommendation at the bead, titled with the token, so the
	// root it pours names the acceptance that sent it. A graph.v2 formula reads
	// the bead as its input convoy's one tracked member, so the sling carries no
	// var of its own, only each var the acceptance was made with.
	res := r.Runtime.Sling(gascity.Sling{Rig: r.Rig, Bead: bead, Formula: formula, Title: formula + " accept:" + out.Token, Vars: vars})
	if res.Code != 0 {
		// A sling can fail after its pour committed, and that pour runs, so the
		// token's root decides whether the dispatch landed.
		root, err := r.tokenRoot(out.Token)
		switch {
		case err != nil:
			return out, stop(4, "gc sling of %s exited %d for %s, and whether it poured could not be read (%v), so nothing more is written. The next Accept finishes acceptance %s once the store answers: gctk reaction accept %s", formula, res.Code, bead, err, out.Token, bead)
		case root != "":
			r.say("gc sling of %s exited %d for %s, but root %s carries acceptance %s, so the dispatch landed", formula, res.Code, bead, root, out.Token)
		default:
			back := r.reopen("Accept's sling of "+formula+" landed no pour, so the question stands", recGates)
			why := fmt.Sprintf("gc sling of %s failed (%s) and landed no pour under acceptance %s", formula, res.Failure(), out.Token)
			if res.Code == 3 {
				why = formula + " already runs at " + bead + " from another dispatch, which Gas City's launch lock refused to start twice"
			}
			return out, stop(1, "%s. Nothing is dispatched.%s Try it again, or Discuss it: gc-helm engage %s", why, back, bead)
		}
	}

	// Lift the bead's hold:mayor, since an Accept is a placement, then record the
	// dispatch, which clears the recommendation. The lift comes first, so a run
	// that stops between the two leaves an acceptance the next Accept finishes,
	// lift included.
	if _, err := r.liftHold(bead, ""); err != nil {
		return out, stop(4, "dispatched %s at %s (acceptance %s), but the write that lifts its hold:mayor did not land (%v), so the bead still waits in the placement queue. The next Accept finishes the lift and the record without a second dispatch: gctk reaction accept %s", formula, bead, out.Token, err, bead)
	}
	if err := r.markDispatched(bead, formula, out.Token, req.Reason); err != nil {
		return out, stop(4, "dispatched %s at %s (acceptance %s), but the record did not land (%v). The next Accept finishes the record without a second dispatch: gctk reaction accept %s", formula, bead, out.Token, err, bead)
	}
	return out, nil
}

// answer records an acceptance on an open recommendation gate and answers it:
// its dispatch input on each gate first, then the answer that names its token,
// then the read of which answer each gate took. Any gate that took another's
// answer, or did not close, stops the acceptance, and the gates that took this
// run's answer open again.
func (r *Reactions) answer(bead, formula string, vars, recGates []string, out *Accepted) error {
	token, err := newToken()
	if err != nil {
		return stop(4, "could not make an acceptance token (%v). Nothing dispatched", err)
	}
	out.Token = token
	answer := "ruled: accepted " + formula + " accept:" + token
	in := acceptance{Token: token, Formula: formula, Vars: append([]string{}, vars...)}
	var left []string
	for _, g := range recGates {
		w := r.Ledger.Write(g)
		acceptanceKey.Set(w, in)
		if err := r.Ledger.Commit(w); err != nil {
			left = append(left, g)
		}
	}
	if len(left) > 0 {
		return stop(4, "could not record acceptance %s's dispatch input (%s) on %s's recommendation gate %s, so nothing is answered or dispatched. Run it again once the store answers: gctk reaction accept %s", token, varsSaid(vars), bead, strings.Join(left, " "), bead)
	}
	for _, g := range recGates {
		if err := r.Ledger.ResolveGate(g, answer); err != nil {
			r.say("the answer on %s did not land (%v); the read that follows says where the gate stands", g, err)
		}
	}
	// bd answers a gate already closed with the same line and exit 0, so only a
	// read of the gate tells this answer from one that reached it first.
	rows, err := r.Ledger.Find(ledger.ByID(recGates...).WithClosed())
	if err != nil {
		return stop(4, "answered %s's recommendation gate %s, but which answer it took could not be read (%v), so nothing is dispatched yet. The next Accept finishes this acceptance (%s) once the store answers: gctk reaction accept %s", bead, strings.Join(recGates, " "), err, token, bead)
	}
	byID := map[string]*ledger.Record{}
	for _, g := range rows {
		byID[g.ID] = g
	}
	var ours, theirs, unclosed []string
	for _, g := range recGates {
		row := byID[g]
		switch {
		case row == nil || row.Status() != "closed":
			unclosed = append(unclosed, g)
		case row.CloseReason() == answer:
			ours = append(ours, g)
		default:
			theirs = append(theirs, fmt.Sprintf("%s: %q", g, row.CloseReason()))
		}
	}
	if len(theirs)+len(unclosed) == 0 {
		return nil
	}
	back := ""
	if len(ours) > 0 {
		back = r.reopen("Accept stood down: another answer reached the recommendation first", ours)
	}
	if len(theirs) > 0 {
		return stop(4, "another answer reached %s's recommendation gate first: %s. The first answer stands, so Accept dispatches nothing.%s", bead, strings.Join(theirs, "; "), back)
	}
	return stop(4, "the recommendation gate %s on %s did not close on its answer, so Accept dispatches nothing. Run it again, or resolve it by hand.%s", strings.Join(unclosed, " "), bead, back)
}

// tokenRoot searches for the root a sling under the token poured, and names
// the one whose pour landed, or none: a listing of the beads whose title holds
// accept:<token>, closed ones and gate-typed ones among them, since only a
// sling under that acceptance titles a root with its token. A root, open or
// closed, is the dispatch unless Gas City stamped it as a pour that failed,
// which is no dispatch, as deferred dispatch's start reads one (arm.FailedPour).
func (r *Reactions) tokenRoot(token string) (string, error) {
	rows, err := r.Ledger.Find(ledger.Titled("accept:" + token).WithClosed())
	if err != nil {
		return "", err
	}
	slices.SortFunc(rows, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	for _, row := range rows {
		if !strings.Contains(row.Title(), "accept:"+token) || raw(rootBeadKey, row) != "" {
			continue
		}
		if !arm.FailedPour(row) {
			return row.ID, nil
		}
	}
	return "", nil
}

// humanGates is the human gates on the bead, open and closed: each bead a blocks
// edge of its own names that is a human gate.
func (r *Reactions) humanGates(row *ledger.Record) ([]*ledger.Record, error) {
	edges, err := row.Edges()
	if err != nil {
		return nil, fmt.Errorf("%s's edges did not decode: %w", row.ID, err)
	}
	var far []string
	for _, e := range edges {
		if e.Type == ledger.EdgeBlocks {
			far = append(far, e.ID)
		}
	}
	rows, err := r.Ledger.Find(ledger.ByID(far...).WithClosed())
	if err != nil {
		return nil, err
	}
	var out []*ledger.Record
	for _, g := range rows {
		if person.IsHumanGate(g.IssueType(), g.AwaitType()) {
			out = append(out, g)
		}
	}
	slices.SortFunc(out, func(a, b *ledger.Record) int { return strings.Compare(a.ID, b.ID) })
	return out, nil
}

// reopen puts each gate back on the board, open and owed, from Accept's own
// answer, and says so, or names the gates whose reopen did not land.
func (r *Reactions) reopen(why string, gates []string) string {
	var left []string
	for _, g := range gates {
		if err := r.Ledger.Reopen(g, why); err != nil {
			left = append(left, g)
		}
	}
	if len(left) == 0 {
		return " The recommendation's gate " + strings.Join(gates, " ") + " is open again, back on the board."
	}
	return " The reopen of " + strings.Join(left, " ") + " did not land, so it reads answered while nothing is dispatched. Reopen it by hand: gc bd reopen <id>."
}

// liftHold removes every spelling of hold:mayor the bead carries now, with note
// when one is given, in one write, and names the spellings it removed. A bead
// that carries none is not written.
func (r *Reactions) liftHold(bead, note string) ([]string, error) {
	row, err := r.readBead(bead)
	if err != nil {
		return nil, err
	}
	if row == nil {
		return nil, fmt.Errorf("%s does not resolve", bead)
	}
	spellings := gascity.Spellings(row.Labels(), "hold:mayor")
	if len(spellings) == 0 {
		return nil, nil
	}
	w := r.Ledger.Write(bead)
	for _, s := range spellings {
		w.RemoveLabel(s)
	}
	if note != "" {
		w.Note(note)
	}
	if err := r.Ledger.Commit(w); err != nil {
		return nil, err
	}
	return spellings, nil
}

// markDispatched records that Accept dispatched formula, and withdraws the
// recommendation, in one write, so no later Accept dispatches it again.
func (r *Reactions) markDispatched(bead, formula, token, reason string) error {
	w := r.Ledger.Write(bead)
	dispatchedKey.Set(w, formula)
	recommendedFormulaKey.Clear(w)
	why := ""
	if reason != "" {
		why = ": " + reason
	}
	w.Note(fmt.Sprintf("Accept dispatched %s (acceptance %s)%s; gc.recommended_formula withdrawn.", formula, token, why))
	return r.Ledger.Commit(w)
}

// readBead is the bead's record, closed or not, nil when the store does not
// hold it.
func (r *Reactions) readBead(id string) (*ledger.Record, error) {
	rows, err := r.Ledger.Find(ledger.ByID(id).WithClosed())
	if err != nil {
		return nil, err
	}
	for _, row := range rows {
		if row.ID == id {
			return row, nil
		}
	}
	return nil, nil
}

// newToken is a token unique to one acceptance, sixteen hex digits, fixed in
// length so no token is another's prefix in a title search.
func newToken() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// varsSaid is vars as a sling carries them, for a message.
func varsSaid(vars []string) string {
	if len(vars) == 0 {
		return "no --var"
	}
	return "--var " + strings.Join(vars, " --var ")
}

func nonBlank(s, otherwise string) string {
	if strings.TrimSpace(s) == "" {
		return otherwise
	}
	return s
}
