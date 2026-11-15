package pr

import (
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The approval withdrawal (specs/tk-1tfzr71.108/design.md, section 4). When
// triage rules a head of a PR a material change, it files a withdrawal with
// Withdraw: a bead that blocks the bead that owns the PR and names the head in
// withdraw_head, so the evaluator holds the PR from the moment it is filed. The
// landing order carries it out on each run that reads the record. It waits
// while an approval it would dismiss carries feedback the intake has not
// routed, dismisses each approval that stands on a commit that does not contain
// the head, reads the reviews again and closes the withdrawal once none stands,
// and files a human gate on the bead when GitHub refuses a dismissal.
//
// A withdrawal holds the bead from the refinery as any wait does, so the
// record stays marked while one is open, and the order reads it on every run
// until the withdrawal is carried out, a head it sent back to the refinery
// included.

// withdrawRefusedKey keys the human gate a withdrawal files on the bead when
// GitHub refuses to dismiss an approval it withdraws.
const withdrawRefusedKey = "approval-withdraw-refused"

// reviewFormula is the formula of a review run. A live root of it that a blocks
// edge of the bead names is a run attached to the bead.
const reviewFormula = "mol-pr-review"

// Withdrawn is the withdrawal Withdraw found or filed: its bead, and whether
// this call filed it.
type Withdrawn struct {
	ID    string
	Filed bool
}

// WithdrawRefusal is a withdrawal the bead's state refused: the store holds no
// such bead, it is closed, it owns no PR on the record, or it moved since the
// call read it. Nothing was filed.
type WithdrawRefusal struct{ Bead, Why string }

func (e *WithdrawRefusal) Error() string { return fmt.Sprintf("%s: nothing filed: %s", e.Bead, e.Why) }

// Withdraw files the withdrawal of the approvals of the PR the bead owns that
// were given on a commit that does not contain head, with reason as what each
// dismissal tells its approver. A withdrawal for head already filed on the
// bead, open or closed, is found and not filed again. The bead must own a PR
// on the record. Withdraw holds the store's record lock, so no run of the
// landing order reads the record between its writes. When the record carries
// no marker, as on a bead the order sent back to the refinery, it sets the
// marker first, guarded on the status and assignee it read, so the order reads
// the record until the withdrawal is carried out. Then it files the withdrawal
// with its blocks edge in one create. A create the store failed may still have
// filed it, which a retry finds.
func (l Landing) Withdraw(bead, head, reason string) (Withdrawn, error) {
	if !record.IsObjectID(head) {
		return Withdrawn{}, fmt.Errorf("%q is not a full commit id", head)
	}
	reason = strings.TrimSpace(reason)
	if reason == "" {
		return Withdrawn{}, errors.New("a withdrawal needs the reason its dismissals give")
	}
	release, err := record.Lock(l.Dir, l.Wait)
	if err != nil {
		return Withdrawn{}, err
	}
	defer release()
	r, err := l.read(bead)
	if err != nil {
		return Withdrawn{}, err
	}
	if r == nil {
		return Withdrawn{}, &WithdrawRefusal{Bead: bead, Why: "the store holds no such bead"}
	}
	rec, err := record.Read(r)
	if err != nil {
		return Withdrawn{}, err
	}
	status, assignee := r.Status(), r.Assignee()
	switch {
	case status == "closed":
		return Withdrawn{}, &WithdrawRefusal{Bead: bead, Why: "it is closed"}
	case !record.OnRecord(rec.Result):
		return Withdrawn{}, &WithdrawRefusal{Bead: bead,
			Why: fmt.Sprintf("it owns no PR on the record: its merge_result reads %q", rec.Result)}
	}
	rows, err := l.blockers(r, true)
	if err != nil {
		return Withdrawn{}, err
	}
	filed, err := withdrawalsIn(rows)
	if err != nil {
		return Withdrawn{}, err
	}
	var found *withdrawal
	for i := range filed {
		if filed[i].head == head {
			found = &filed[i]
			break
		}
	}
	if !rec.Marked && (found == nil || found.open) {
		w := l.Ledger.Write(bead)
		w.Guard(status, assignee)
		record.Mark(w)
		if err := l.Ledger.Commit(w); err != nil {
			if errors.Is(err, ledger.ErrGuard) {
				return Withdrawn{}, &WithdrawRefusal{Bead: bead, Why: "it moved since this call read it"}
			}
			return Withdrawn{}, err
		}
	}
	if found != nil {
		return Withdrawn{ID: found.id}, nil
	}
	f := l.Ledger.File(withdrawTitle(rec.Number, head), "task")
	f.Description(reason)
	withdrawHeadKey.Set(f, head)
	f.Blocks(bead)
	id, err := l.Ledger.Create(f)
	if err != nil {
		return Withdrawn{}, err
	}
	return Withdrawn{ID: id, Filed: true}, nil
}

// withdrawTitle is a withdrawal's title: what it withdraws, of which PR.
func withdrawTitle(number, head string) string {
	pr := "the PR"
	if number != "" {
		pr = "PR #" + number
	}
	return fmt.Sprintf("Withdraw each approval of %s given on a commit without %s", pr, short(head))
}

// withdrawal is a withdrawal filed on a bead: its own bead, the head it names,
// the reason its dismissals give, and whether it is still open.
type withdrawal struct {
	id, head, reason string
	status, assignee string
	open             bool
}

// blockers reads the beads that the bead's own blocks edges name, closed ones
// too when closed is set: the withdrawals filed on it and the review runs
// attached to it among them. A bead with no blocks edge reads nothing.
func (l Landing) blockers(r *ledger.Record, closed bool) ([]*ledger.Record, error) {
	edges, err := r.Edges()
	if err != nil {
		return nil, &ledger.ReadError{ID: r.ID, Reason: "its edges did not decode: " + err.Error()}
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
	sel := ledger.ByID(ids...)
	if closed {
		sel = sel.WithClosed()
	}
	return l.Ledger.Find(sel)
}

// withdrawalsIn is each withdrawal among rows, the beads that carry
// withdraw_head, oldest first.
func withdrawalsIn(rows []*ledger.Record) ([]withdrawal, error) {
	type dated struct {
		w       withdrawal
		created string
	}
	var all []dated
	for _, b := range rows {
		h, ok, err := withdrawHeadKey.Get(b)
		if err != nil {
			return nil, err
		}
		if !ok {
			continue
		}
		all = append(all, dated{withdrawal{id: b.ID, head: strings.TrimSpace(h), reason: strings.TrimSpace(b.Description()),
			status: b.Status(), assignee: b.Assignee(), open: b.Status() != "closed"}, b.CreatedAt()})
	}
	slices.SortStableFunc(all, func(a, b dated) int {
		if c := strings.Compare(a.created, b.created); c != 0 {
			return c
		}
		return strings.Compare(a.w.id, b.w.id)
	})
	out := make([]withdrawal, len(all))
	for i, d := range all {
		out[i] = d.w
	}
	return out, nil
}

// runsIn names the review runs among rows: the live roots of the review
// formula.
func runsIn(rows []*ledger.Record) ([]string, error) {
	var out []string
	for _, b := range rows {
		if b.Status() == "closed" {
			continue
		}
		kind, _, err := kindKey.Get(b)
		if err != nil {
			return nil, err
		}
		name, _, err := formulaNameKey.Get(b)
		if err != nil {
			return nil, err
		}
		if strings.TrimSpace(kind) == "workflow" && strings.TrimSpace(name) == reviewFormula {
			out = append(out, b.ID)
		}
	}
	return out, nil
}

// carry carries out each open withdrawal on the record s read against p, the
// PR GitHub reports open, oldest first. It returns its account of what it did,
// for the record's outcome, and whether a withdrawal is still open. A read
// that does not answer leaves every withdrawal for the next run.
func (u *run) carry(s state, host string, hub Hub, p *gh.PullRequest) (string, bool) {
	var open []withdrawal
	for _, w := range s.withdrawals {
		if w.open {
			open = append(open, w)
		}
	}
	if len(open) == 0 {
		return "", false
	}
	waits := func(why string) (string, bool) {
		return fmt.Sprintf("%s waits for the next run: %s", names(open), why), true
	}
	reviews, err := hub.Reviews(s.rec.Repo, p.Number)
	if err != nil {
		return waits("the PR's reviews did not read: " + err.Error())
	}
	c := &compares{hub: hub, repo: s.rec.Repo, seen: map[[2]string]bool{}}
	var said []string
	held := false
	for _, w := range open {
		var note string
		var still bool
		note, still, reviews = u.carryOne(s, host, hub, p, w, reviews, c)
		said = append(said, note)
		held = held || still
	}
	return strings.Join(said, "; "), held
}

// carryOne carries out withdrawal w with the PR's reviews as last read. It
// returns its account, whether w is still open, and the reviews as it last
// read them, which a dismissal changes for the next withdrawal.
func (u *run) carryOne(s state, host string, hub Hub, p *gh.PullRequest, w withdrawal, reviews []gh.Review, c *compares) (string, bool, []gh.Review) {
	at := fmt.Sprintf("withdrawal %s for %s", w.id, short(w.head))
	waits := func(why string) (string, bool, []gh.Review) {
		return at + " waits for the next run: " + why, true, reviews
	}
	targets, err := c.standing(w.head, reviews)
	if err != nil {
		return waits("GitHub did not answer whether an approved commit contains the head: " + err.Error())
	}
	if len(targets) > 0 {
		// 1. A dismissal retires the inline comments of the review it dismisses,
		// so it waits while one of them is feedback the intake has not routed.
		unread, err := u.unrouted(s, host, hub, p, targets)
		if err != nil {
			return waits("whether an approval to dismiss carries unrouted feedback did not read: " + err.Error())
		}
		if len(unread) > 0 {
			return waits(fmt.Sprintf("an approval to dismiss carries inline comment %s, which the intake has not routed, "+
				"and a dismissal would retire it unread", joinIDs(unread)))
		}
		// 2. Dismiss each approval that stands on a commit without the head.
		mark, err := u.cityMark()
		if err != nil {
			return waits("the city's mark did not read, and no dismissal goes without it: " + err.Error())
		}
		message := w.reason
		if message == "" {
			message = fmt.Sprintf("Triage ruled head %s a material change, so this approval does not cover the code that will land.", short(w.head))
		}
		refused := map[int64]string{}
		for _, v := range targets {
			if err := hub.DismissReview(s.rec.Repo, p.Number, v.ID, message+"\n\n"+mark); err != nil && gh.Refused(err) {
				refused[v.ID] = err.Error()
			}
		}
		// 3. Read the reviews again: the withdrawal closes only once no approval
		// stands on a commit without its head.
		again, err := hub.Reviews(s.rec.Repo, p.Number)
		if err != nil {
			return waits("the reviews did not read again after the dismissals: " + err.Error())
		}
		reviews = again
		left, err := c.standing(w.head, again)
		if err != nil {
			return waits("GitHub did not answer whether an approved commit contains the head: " + err.Error())
		}
		if len(left) > 0 {
			var stuck []gh.Review
			for _, v := range left {
				if _, ok := refused[v.ID]; ok {
					stuck = append(stuck, v)
				}
			}
			if len(stuck) == 0 {
				return waits(fmt.Sprintf("%s still stands, and its dismissal was not answered", reviewNames(left)))
			}
			// 4. GitHub refused: a person dismisses them, or rules otherwise.
			why := refused[stuck[0].ID]
			if err := u.Gates.File(s.id, withdrawRefusedKey, refusedWithdrawal(s, p, w, stuck, why)); err != nil {
				return waits(fmt.Sprintf("GitHub refused to dismiss %s, and the gate %s did not file; the next run files it: %v",
					reviewNames(stuck), withdrawRefusedKey, err))
			}
			return fmt.Sprintf("%s is held: GitHub refused to dismiss %s, and the gate %s asks a person", at,
				reviewNames(stuck), withdrawRefusedKey), true, reviews
		}
	}
	note := fmt.Sprintf("The landing order carried out this withdrawal (%s): ", u.stamp())
	if len(targets) == 0 {
		note += fmt.Sprintf("no approval of PR #%d stood on a commit without %s.", p.Number, short(w.head))
	} else {
		note += fmt.Sprintf("it dismissed %s of PR #%d, and no approval stands on a commit without %s.",
			reviewNames(targets), p.Number, short(w.head))
	}
	cw := u.Ledger.Write(w.id)
	cw.Guard(w.status, w.assignee)
	cw.Status("closed")
	cw.Note(note)
	if err := u.Ledger.Commit(cw); err != nil {
		return waits("the withdrawal's close did not land: " + err.Error())
	}
	if len(targets) == 0 {
		return at + " closed: no approval stood on a commit without its head", false, reviews
	}
	return fmt.Sprintf("%s closed: dismissed %s", at, reviewNames(targets)), false, reviews
}

// compares answers whether an approved commit contains a head, through
// GitHub's compare of the two, each pair asked once in a run.
type compares struct {
	hub  Hub
	repo string
	seen map[[2]string]bool
}

// contains reports whether commit contains head: it is head, or it descends
// from it, which GitHub's compare of head with commit reads as identical or
// ahead. A compare GitHub refuses, as it does for a commit it no longer holds,
// does not show that commit contains head, so it reads as not containing it.
// A compare GitHub did not answer is an error.
func (c *compares) contains(head, commit string) (bool, error) {
	if commit == head {
		return true, nil
	}
	k := [2]string{head, commit}
	if v, ok := c.seen[k]; ok {
		return v, nil
	}
	status, err := c.hub.Compare(c.repo, head, commit)
	if err != nil && !gh.Refused(err) {
		return false, err
	}
	v := err == nil && (status == "identical" || status == "ahead")
	c.seen[k] = v
	return v, nil
}

// standing is each approval among reviews that stands on a commit that does
// not contain head. A review that has not been dismissed and approves stands,
// whoever gave it. A review that names no commit, or whose commit GitHub
// refuses to compare, is not shown to contain the head, so it stands among
// them, which errs toward a dismissal: otherwise a commit GitHub no longer
// holds would keep the withdrawal waiting on every run, with no one asked. An
// approval of the head, or of any later head of the branch, contains it, since
// every push onto a PR's branch on the record is a fast-forward.
func (c *compares) standing(head string, reviews []gh.Review) ([]gh.Review, error) {
	var out []gh.Review
	for _, v := range reviews {
		if v.State != "APPROVED" {
			continue
		}
		if v.Commit != "" {
			in, err := c.contains(head, v.Commit)
			if err != nil {
				return nil, err
			}
			if in {
				continue
			}
		}
		out = append(out, v)
	}
	return out, nil
}

// unrouted is the ids of the inline comments that dismissing targets would
// retire before the intake routes them, read against the bead's receipts.
func (u *run) unrouted(s state, host string, hub Hub, p *gh.PullRequest, targets []gh.Review) ([]int64, error) {
	rule, err := u.rule()
	if err != nil {
		return nil, err
	}
	self, err := u.login(host, hub)
	if err != nil {
		return nil, err
	}
	threads, err := hub.ReviewThreads(s.rec.Repo, p.Number)
	if err != nil {
		return nil, err
	}
	var ids []int64
	for _, v := range targets {
		ids = append(ids, v.ID)
	}
	var rerr error
	read := func(k ledger.Key[string]) string {
		v, _, err := k.Get(s.row)
		if err != nil && rerr == nil {
			rerr = err
		}
		return strings.TrimSpace(v)
	}
	since := read(provenanceKey)
	rc := receipts{comment: mark(read(commentWatermarkKey)), commentAnswered: mark(read(commentAnsweredKey))}
	if rerr != nil {
		return nil, rerr
	}
	return unrouted(rule, self, since, rc, threads, ids)
}

// refusedWithdrawal is the message of the gate a refused dismissal files: what
// GitHub refused, why triage withdrew the approvals, and how a person settles
// it.
func refusedWithdrawal(s state, p *gh.PullRequest, w withdrawal, stuck []gh.Review, why string) string {
	reason := w.reason
	if reason == "" {
		reason = fmt.Sprintf("triage ruled head %s a material change", short(w.head))
	}
	return fmt.Sprintf("GitHub refused to dismiss %s on PR #%d (%s), given on a commit that does not contain head %s: "+
		"%s. Triage withdrew them because %s %s stays held, and what waits on it stays held, until no such approval "+
		"stands. Dismiss them on GitHub, then clear this gate. To keep them, close the withdrawal instead "+
		"(gc bd close %s), then clear this gate.", reviewNames(stuck), p.Number, p.URL, w.head,
		strings.Join(strings.Fields(why), " "), sentence(reason), s.id, w.id)
}

// sentence is text as one sentence, ending in a stop.
func sentence(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if text == "" || strings.HasSuffix(text, ".") || strings.HasSuffix(text, "!") || strings.HasSuffix(text, "?") {
		return text
	}
	return text + "."
}

// names lists the withdrawals' beads.
func names(ws []withdrawal) string {
	var ids []string
	for _, w := range ws {
		ids = append(ids, w.id)
	}
	if len(ids) == 1 {
		return "withdrawal " + ids[0]
	}
	return "withdrawals " + strings.Join(ids, ", ")
}

// reviewNames names reviews by their ids and authors.
func reviewNames(reviews []gh.Review) string {
	var parts []string
	for _, v := range reviews {
		who := v.Author
		if who == "" {
			who = "an account GitHub no longer names"
		}
		parts = append(parts, fmt.Sprintf("review %d (%s)", v.ID, who))
	}
	noun := "the approval"
	if len(parts) > 1 {
		noun = "the approvals"
	}
	return noun + " " + strings.Join(parts, ", ")
}

// joinIDs lists ids.
func joinIDs(ids []int64) string {
	var parts []string
	for _, id := range ids {
		parts = append(parts, fmt.Sprint(id))
	}
	return strings.Join(parts, ", ")
}
