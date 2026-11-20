package pr

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/feedback"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/gh"
	"github.com/zookanalytics/gc-toolkit/services/gctk/internal/ledger"
	"github.com/zookanalytics/gc-toolkit/services/gctk/pr/record"
)

// The approval withdrawal (specs/tk-1tfzr71.108/design.md, section 4). When
// triage rules a head of a PR a material change, it files a withdrawal with
// Withdraw: a bead that blocks the bead that owns the PR and names the head in
// withdraw_head, so the evaluator holds the PR from the moment it is filed. The
// landing order carries it out from the approvals the one-PR update saved on
// the bead (specs/tk-1tfzr71.149/design.md, section 5). It waits while an
// approval it would dismiss carries feedback the intake has not routed, on the
// saved read and then on the act's own read of the PR's review threads,
// dismisses each approval that stands on a commit that does not contain the
// head, and closes the withdrawal once the act's own read of the PR's reviews
// shows none standing past the ones it dismissed. It files a human gate on the
// bead when GitHub refuses a dismissal.
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

// WithdrawalFor is the withdrawal for head filed on the bead, open or closed,
// "" when none is: the one Withdraw files, and finds again on a retry. A
// review run's triage output that rules its head material stands only once it
// is filed. A read that fails, and a bead the store does not hold, return an
// error.
func WithdrawalFor(l *ledger.Ledger, bead, head string) (string, error) {
	land := Landing{Ledger: l}
	r, err := land.read(bead)
	if err != nil {
		return "", err
	}
	if r == nil {
		return "", &ledger.ReadError{ID: bead, Reason: "the store holds no such bead"}
	}
	rows, err := land.blockers(r, true)
	if err != nil {
		return "", err
	}
	filed, err := withdrawalsIn(rows)
	if err != nil {
		return "", err
	}
	for _, w := range filed {
		if w.head == head {
			return w.id, nil
		}
	}
	return "", nil
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
	return blockersIn(l.Ledger, r, closed)
}

// blockersIn is blockers, read through l.
func blockersIn(l *ledger.Ledger, r *ledger.Record, closed bool) ([]*ledger.Record, error) {
	ids, err := blockerIDs(r)
	if err != nil || len(ids) == 0 {
		return nil, err
	}
	sel := ledger.ByID(ids...)
	if closed {
		sel = sel.WithClosed()
	}
	return l.Find(sel)
}

// blockerIDs is each bead r's blocks edges name, once.
func blockerIDs(r *ledger.Record) ([]string, error) {
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
	return ids, nil
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

// verdict is what a withdrawal owes, as the saved read shows the PR: a close,
// since no approval stands on a commit without its head, the approvals to
// dismiss, or why it waits for a later run. failed says the wait is a read that
// did not answer.
type verdict struct {
	close   bool
	dismiss []Approval
	wait    string
	failed  bool
}

// conversationFor is the conversation part of saved, and why it is no read the
// withdrawals can act on: none is saved, or it applied the definition of
// feedback from another instant than the bead's, which the PR watch reads
// again.
func conversationFor(s state, saved *SavedRead) (*SavedConversation, string) {
	switch c := saved.Conversation; {
	case c == nil:
		return nil, "no read of the PR's conversation is saved on the bead, and the PR watch saves one"
	case c.Since != s.since:
		return nil, fmt.Sprintf("the saved conversation applied the definition of feedback from %q, not from the "+
			"bead's provenance instant %q, and the PR watch reads it again", c.Since, s.since)
	default:
		return c, ""
	}
}

// judge decides withdrawal w from the approvals conv saved, past the ones
// gone, which this act dismissed for an earlier withdrawal: the ones that stand
// on a commit without the head (withoutHead) to dismiss, or a close when none
// does, which carryOne makes only once the act's own read of the PR's reviews
// shows none either.
func (u *run) judge(s state, conv *SavedConversation, w withdrawal, gone map[int64]bool) verdict {
	targets, err := u.withoutHead(conv.Approvals, w.head, gone)
	if err != nil {
		return verdict{wait: err.Error(), failed: true}
	}
	if len(targets) == 0 {
		return verdict{close: true}
	}
	// A dismissal retires the inline comments of the review it dismisses, so it
	// waits while one of them is feedback the intake has not routed.
	rc, err := commentReceipts(s.row)
	if err != nil {
		return verdict{wait: "the bead's comment receipts did not read: " + err.Error(), failed: true}
	}
	if unread := unrouted(rc, targets); len(unread) > 0 {
		return verdict{wait: fmt.Sprintf("an approval to dismiss carries inline comment %s, which the intake has not "+
			"routed, and a dismissal would retire it unread", joinIDs(unread))}
	}
	return verdict{dismiss: targets}
}

// withoutHead is each of approvals, past the ones gone, that stands on a commit
// that does not contain head. A commit contains the head when it is the head, or
// descends from it in the clone's history (Checkout.Contains). A commit the
// clone does not hold once the act has fetched the PR's branch (carryOne), such
// as one a force-push left behind, is not shown to contain the head, and neither
// is an approval that names no commit, so each stands without it, which errs
// toward a dismissal: otherwise a commit no one holds would keep the withdrawal
// waiting on every run, with no one asked. An approval of the head, or of any
// later head of the branch, contains it, since every push onto a PR's branch on
// the record is a fast-forward. A read of the history that does not answer is
// an error.
func (u *run) withoutHead(approvals []Approval, head string, gone map[int64]bool) ([]Approval, error) {
	var out []Approval
	for _, a := range approvals {
		if gone[a.ID] {
			continue
		}
		if a.Commit != "" {
			in, err := u.holds(a.Commit, head)
			if err != nil {
				return nil, fmt.Errorf("whether approved commit %s contains the head did not read: %v", short(a.Commit), err)
			}
			if in {
				continue
			}
		}
		out = append(out, a)
	}
	return out, nil
}

// commentReceipts are the bead's receipts of the inline comments the intake
// has handled.
func commentReceipts(r *ledger.Record) (receipts, error) {
	var rerr error
	read := func(k ledger.Key[string]) string {
		v, _, err := k.Get(r)
		if err != nil && rerr == nil {
			rerr = err
		}
		return strings.TrimSpace(v)
	}
	rc := receipts{comment: mark(read(commentWatermarkKey)), commentAnswered: mark(read(commentAnsweredKey))}
	return rc, rerr
}

// readUnrouted is the inline comments that dismissing targets would retire
// before the intake routes them, as unrouted reads them, on the act's own read
// of the PR's review threads. The saved read applied the definition of feedback
// to each comment's text as the PR watch read it, and a comment edited since,
// or a definition the rig's checkout changed since, can be feedback now that
// was not then.
func (u *run) readUnrouted(s state, host string, hub Hub, number int, targets []Approval) ([]int64, error) {
	threads, err := hub.ReviewThreads(s.rec.Repo, number)
	if err != nil {
		return nil, err
	}
	var carried []feedback.Comment
	for _, t := range threads {
		for _, c := range t.Comments {
			if c.Review != nil && slices.ContainsFunc(targets, func(a Approval) bool { return a.ID == c.Review.ID }) {
				carried = append(carried, commentOf(c))
			}
		}
	}
	if len(carried) == 0 {
		return nil, nil
	}
	rule, err := u.rule()
	if err != nil {
		return nil, err
	}
	self, err := u.login(host, hub)
	if err != nil {
		return nil, err
	}
	inline, err := rule.Comments(self, s.since, carried)
	if err != nil {
		return nil, err
	}
	rc, err := commentReceipts(s.row)
	if err != nil {
		return nil, err
	}
	now := slices.Clone(targets)
	for i := range now {
		now[i].Inline = newestCarried(now[i].ID, threads, inline)
	}
	return unrouted(rc, now), nil
}

// carrying decides the open withdrawals on the record s read, from saved: an
// account of the ones that wait, whether any owes a close or a dismissal,
// which makes the record owe an act, and whether a wait is a read that did not
// answer.
func (u *run) carrying(s state, saved *SavedRead) (string, bool, bool) {
	var open []withdrawal
	for _, w := range s.withdrawals {
		if w.open {
			open = append(open, w)
		}
	}
	if len(open) == 0 {
		return "", false, false
	}
	conv, why := conversationFor(s, saved)
	if why != "" {
		return fmt.Sprintf("%s waits for the next run: %s", names(open), why), false, false
	}
	gone := map[int64]bool{}
	var said []string
	acts, failed := false, false
	for _, w := range open {
		v := u.judge(s, conv, w, gone)
		if v.wait != "" {
			said = append(said, fmt.Sprintf("withdrawal %s for %s waits for the next run: %s", w.id, short(w.head), v.wait))
			failed = failed || v.failed
			continue
		}
		acts = true
		for _, a := range v.dismiss {
			gone[a.ID] = true
		}
	}
	return strings.Join(said, "; "), acts, failed
}

// withCarry makes p carry out the record's open withdrawals first, from saved.
// When p owes no act, the withdrawals that owe one are the record's act, and
// their account rides p's outcome; when none owes one, p is what it was, with
// the account of the ones that wait, and a retry when a wait is a read that did
// not answer.
func (u *run) withCarry(s state, saved *SavedRead, p plan) plan {
	if !withdrawing(s) {
		return p
	}
	note, acts, failed := u.carrying(s, saved)
	if p.act == nil {
		if !acts {
			p.out.Detail = withNote(p.out.Detail, note)
			if failed && p.out.Action == ActChecked {
				p.out.Action = ActRetry
			}
			return p
		}
		out := p.out
		return doing(func(ctx context.Context, _ carriedOut) RunOutcome {
			c := u.carry(ctx, s, saved)
			o := out
			o.Detail = withNote(o.Detail, c.note)
			if c.failed {
				o.Action = ActRetry
			}
			return o
		})
	}
	main := p.act
	return doing(func(ctx context.Context, _ carriedOut) RunOutcome { return main(ctx, u.carry(ctx, s, saved)) })
}

// carry carries out each open withdrawal on the record s read, oldest first,
// from the approvals saved holds. It returns its account, whether a withdrawal
// is still open, and whether a step did not complete.
func (u *run) carry(ctx context.Context, s state, saved *SavedRead) carriedOut {
	var open []withdrawal
	for _, w := range s.withdrawals {
		if w.open {
			open = append(open, w)
		}
	}
	if len(open) == 0 {
		return carriedOut{}
	}
	conv, why := conversationFor(s, saved)
	if why != "" {
		return carriedOut{note: fmt.Sprintf("%s waits for the next run: %s", names(open), why), held: true}
	}
	host, _, _, _ := record.ParseURL(s.rec.URL)
	gone := map[int64]bool{}
	var out carriedOut
	var said []string
	for _, w := range open {
		note, still, failed := u.carryOne(ctx, s, host, saved.PR, conv, w, gone)
		said = append(said, note)
		out.held = out.held || still
		out.failed = out.failed || failed
	}
	out.note = strings.Join(said, "; ")
	return out
}

// carryOne carries out withdrawal w, past the approvals gone, which this act
// dismissed for an earlier withdrawal and which it adds to: it dismisses the
// approvals judge finds in conv once the act's own read of the PR's review
// threads shows none of them carrying feedback the intake has not routed, and
// closes w only once the act's own read of the PR's reviews shows none
// standing without its head. It returns its account, whether w is still open,
// and whether a step did not complete.
func (u *run) carryOne(ctx context.Context, s state, host string, p *SavedPR, conv *SavedConversation, w withdrawal, gone map[int64]bool) (string, bool, bool) {
	at := fmt.Sprintf("withdrawal %s for %s", w.id, short(w.head))
	waits := func(why string, failed bool) (string, bool, bool) {
		return at + " waits for the next run: " + why, true, failed
	}
	v := u.judge(s, conv, w, gone)
	if v.wait == "" && len(v.dismiss) > 0 && !u.fetched[s.branch] {
		// An approved commit the clone has not fetched, such as one a person
		// pushed onto the PR's branch, can contain the head, so the act fetches
		// the branch before it dismisses any approval, and judges them again.
		if err := u.fetchBranch(ctx, s.branch); err != nil {
			return waits(fmt.Sprintf("origin/%s did not fetch, so no approval is dismissed: %v", s.branch, err), true)
		}
		v = u.judge(s, conv, w, gone)
	}
	if v.wait != "" {
		return waits(v.wait, v.failed)
	}
	hub := u.Hub(ctx, host)
	var dismissed []Approval
	if len(v.dismiss) > 0 {
		unread, err := u.readUnrouted(s, host, hub, p.Number, v.dismiss)
		if err != nil {
			return waits("the act's own read of the PR's review threads did not answer, and no approval is dismissed "+
				"without it: "+err.Error(), true)
		}
		if len(unread) > 0 {
			return waits(fmt.Sprintf("the act's own read of the review threads shows inline comment %s, on an approval "+
				"to dismiss, as feedback the intake has not routed, and a dismissal would retire it unread",
				joinIDs(unread)), false)
		}
		mark, err := u.cityMark()
		if err != nil {
			return waits("the city's mark did not read, and no dismissal goes without it: "+err.Error(), true)
		}
		message := w.reason
		if message == "" {
			message = fmt.Sprintf("Triage ruled head %s a material change, so this approval does not cover the code that will land.", short(w.head))
		}
		var refused, unanswered []Approval
		var why string
		for _, a := range v.dismiss {
			if ctx.Err() != nil {
				unanswered = append(unanswered, a)
				continue
			}
			switch err := hub.DismissReview(s.rec.Repo, p.Number, a.ID, message+"\n\n"+mark); {
			case err == nil:
				gone[a.ID] = true
				dismissed = append(dismissed, a)
			case gh.Refused(err):
				refused = append(refused, a)
				if why == "" {
					why = err.Error()
				}
			default:
				unanswered = append(unanswered, a)
			}
		}
		if len(refused) > 0 {
			// GitHub refused: a person dismisses them, or rules otherwise.
			if err := u.Gates.File(ctx, s.id, withdrawRefusedKey, refusedWithdrawal(s, p, w, refused, why)); err != nil {
				return waits(fmt.Sprintf("GitHub refused to dismiss %s, and the gate %s did not file; the next run files it: %v",
					approvalNames(refused), withdrawRefusedKey, err), true)
			}
			return fmt.Sprintf("%s is held: GitHub refused to dismiss %s, and the gate %s asks a person", at,
				approvalNames(refused), withdrawRefusedKey), true, false
		}
		if len(unanswered) > 0 {
			return waits(fmt.Sprintf("the dismissal of %s was not answered", approvalNames(unanswered)), true)
		}
	}
	// The saved conversation can lack an approval given since the PR watch
	// read it, and a closed withdrawal dismisses nothing more, so the close
	// waits on the act's own read of the reviews.
	reviews, err := hub.Reviews(s.rec.Repo, p.Number)
	if err != nil {
		return waits("the act's own read of the PR's reviews did not answer, and the withdrawal closes only on it: "+
			err.Error(), true)
	}
	var live []Approval
	for _, r := range reviews {
		if r.State == "APPROVED" {
			live = append(live, Approval{ID: r.ID, Author: r.Author, Commit: r.Commit})
		}
	}
	left, err := u.withoutHead(live, w.head, gone)
	if err != nil {
		return waits(err.Error(), true)
	}
	if len(left) > 0 {
		return waits(fmt.Sprintf("the act's own read of the reviews shows %s standing on a commit without the head, "+
			"which the read the PR watch saved does not hold yet, and a later run dismisses it from the watch's next read",
			approvalNames(left)), false)
	}
	note := fmt.Sprintf("The landing order carried out this withdrawal (%s): ", u.stamp())
	if len(dismissed) == 0 {
		note += fmt.Sprintf("no approval of PR #%d stood on a commit without %s.", p.Number, short(w.head))
	} else {
		note += fmt.Sprintf("it dismissed %s of PR #%d, and no other approval stood on a commit without %s.",
			approvalNames(dismissed), p.Number, short(w.head))
	}
	// A withdrawal is a plain task, whose close the runtime's work-record gate
	// reads. Carrying it out ships no commit, so its record is no-op.
	cw := u.Ledger.Write(w.id)
	cw.Guard(w.status, w.assignee)
	cw.Status("closed")
	cw.WorkRecord("no-op", "", "")
	cw.Note(note)
	if err := u.Ledger.Commit(cw); err != nil {
		return waits("the withdrawal's close did not land: "+err.Error(), true)
	}
	if len(dismissed) == 0 {
		return at + " closed: no approval stood on a commit without its head", false, false
	}
	return fmt.Sprintf("%s closed: dismissed %s", at, approvalNames(dismissed)), false, false
}

// refusedWithdrawal is the message of the gate a refused dismissal files: what
// GitHub refused, why triage withdrew the approvals, and how a person settles
// it.
func refusedWithdrawal(s state, p *SavedPR, w withdrawal, stuck []Approval, why string) string {
	reason := w.reason
	if reason == "" {
		reason = fmt.Sprintf("triage ruled head %s a material change", short(w.head))
	}
	return fmt.Sprintf("GitHub refused to dismiss %s on PR #%d (%s), given on a commit that does not contain head %s: "+
		"%s. Triage withdrew them because %s %s stays held, and what waits on it stays held, until no such approval "+
		"stands. Dismiss them on GitHub, then clear this gate. To keep them, close the withdrawal instead "+
		"(gc bd close %s), then clear this gate.", approvalNames(stuck), p.Number, p.URL, w.head,
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

// approvalNames names approvals by their review ids and authors.
func approvalNames(approvals []Approval) string {
	var parts []string
	for _, v := range approvals {
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
